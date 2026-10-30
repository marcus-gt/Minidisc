import AVFoundation
import Observation
import OSLog

/// The story's soundtrack (#75): one song per slide, joined partway through, faded in and
/// crossfaded into the next slide's song. It plays on players of its own, so the play queue and
/// Now Playing are left alone; the story pauses the main player while it runs.
@MainActor @Observable
final class WrappedStoryAudio {
    /// Where a song is joined: past most intros, before most endings.
    static let startFraction = 0.35
    static let fadeDuration: Duration = .milliseconds(1_500)
    static let stopFadeDuration: Duration = .milliseconds(600)
    static let volume: Float = 0.9

    private(set) var isMuted = false

    /// The stream for a song, with the headers its server needs; nil when it can't be played.
    typealias Resolve = @Sendable (_ songID: String) async -> (url: URL, headers: [String: String])?

    @ObservationIgnored private let resolve: Resolve
    @ObservationIgnored private var current: (id: String, player: AVPlayer)?
    @ObservationIgnored private var fades: [ObjectIdentifier: Task<Void, Never>] = [:]
    /// Bumped by every request, so a slow stream for a slide already left doesn't start late.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var isPaused = false

    init(resolve: @escaping Resolve) {
        self.resolve = resolve
    }

    /// Crossfades to `song`; the same song carries on. nil fades out what's playing.
    func play(_ song: DisplayableSong?) async {
        guard song?.id != current?.id else { return }
        generation += 1
        let request = generation
        if let previous = current {
            current = nil
            fadeOut(previous.player, over: Self.fadeDuration)
        }
        guard let song, let stream = await resolve(song.id), request == generation else { return }

        Self.activateSession()
        let options: [String: Any]? = stream.headers.isEmpty ? nil : ["AVURLAssetHTTPHeaderFieldsKey": stream.headers]
        let player = AVPlayer(playerItem: AVPlayerItem(asset: AVURLAsset(url: stream.url, options: options)))
        player.volume = 0
        if song.duration > 0 {
            let start = CMTime(seconds: song.duration * Self.startFraction, preferredTimescale: 600)
            await player.seek(to: start, toleranceBefore: .positiveInfinity, toleranceAfter: .positiveInfinity)
        }
        guard request == generation else { return }
        current = (song.id, player)
        Logger.wrappedStory.debug("[STORY-AUDIO] playing '\(song.id, privacy: .public)'")
        if !isPaused { player.play() }
        fade(player, to: isMuted ? 0 : Self.volume, over: Self.fadeDuration)
    }

    func pause() {
        isPaused = true
        current?.player.pause()
    }

    func resume() {
        isPaused = false
        current?.player.play()
    }

    func toggleMute() {
        isMuted.toggle()
        if let player = current?.player {
            fade(player, to: isMuted ? 0 : Self.volume, over: .milliseconds(300))
        }
    }

    /// Fades out and lets go of everything, for when the story closes.
    func stop() {
        generation += 1
        if let previous = current {
            current = nil
            fadeOut(previous.player, over: Self.stopFadeDuration)
        }
    }

    // MARK: - Fades

    private func fade(_ player: AVPlayer, to target: Float, over duration: Duration, then completion: (() -> Void)? = nil) {
        let key = ObjectIdentifier(player)
        fades[key]?.cancel()
        let steps = 20
        let start = player.volume
        fades[key] = Task { [weak self] in
            for step in 1...steps {
                try? await Task.sleep(for: duration / steps)
                guard !Task.isCancelled else { return }
                player.volume = start + (target - start) * Float(step) / Float(steps)
            }
            completion?()
            self?.fades[key] = nil
        }
    }

    private func fadeOut(_ player: AVPlayer, over duration: Duration) {
        fade(player, to: 0, over: duration) {
            player.pause()
            player.replaceCurrentItem(with: nil)
        }
    }

    /// The main player sets the session up on its first play; the story may come first.
    private static func activateSession() {
        let session = AVAudioSession.sharedInstance()
        if session.category != .playback {
            try? session.setCategory(.playback)
        }
        try? session.setActive(true)
    }
}
