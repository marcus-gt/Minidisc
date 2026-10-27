import SwiftUI
import SwiftSonic
import OSLog

@Observable
@MainActor
final class LyricsViewModel {
    private let lyricsService: LyricsService
    private let playerService: any PlayerServiceProtocol
    private let playerState: PlayerState
    private let track: DisplayableSong
    private let serverId: UUID
    private let source: LyricsSource
    private let settings: LyricsSettings?

    private(set) var state: State = .loading
    private(set) var currentLineIndex: Int?
    private(set) var availableLanguages: [String] = []
    var selectedLanguage: String?
    /// While following, the view scrolls with the music and dims the lines around the current one.
    /// Scrolling by hand turns it off so the lyrics can simply be read, until the listener taps
    /// "Follow" again or the track changes (#36).
    private(set) var isFollowing: Bool = true

    private var lyricsList: LyricsList?
    private var trackingTask: Task<Void, Never>?
    /// The panel and the player's single line both track lines; either one keeps the timer running.
    private var isPanelShown = false
    private var isLineShown = false

    nonisolated enum State: Equatable {
        case loading
        case loaded(StructuredLyrics)
        case empty
        case unsupported
        case error(String)
    }

    init(
        track: DisplayableSong,
        serverId: UUID,
        source: LyricsSource,
        lyricsService: LyricsService,
        playerService: any PlayerServiceProtocol,
        playerState: PlayerState,
        settings: LyricsSettings? = nil
    ) {
        self.track = track
        self.serverId = serverId
        self.source = source
        self.settings = settings
        self.lyricsService = lyricsService
        self.playerService = playerService
        self.playerState = playerState
    }

    isolated deinit {
        trackingTask?.cancel()
    }

    // MARK: - Load

    func load() async {
        state = .loading
        do {
            let list = try await lyricsService.fetchLyrics(
                for: track,
                serverId: serverId,
                source: source
            )
            lyricsList = list
            applyCurrentLanguage()
        } catch LyricsError.notSupportedByServer {
            state = .unsupported
        } catch LyricsError.notFound {
            state = .empty
        } catch let error as LyricsError {
            state = .error(networkErrorMessage(from: error))
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    // MARK: - Line tracking

    func update(elapsedMs: Int) {
        guard case .loaded(let structured) = state, structured.synced else {
            currentLineIndex = nil
            return
        }
        // The song's own offset, plus the listener's correction for lyrics that run early or late.
        let adjustedMs = elapsedMs - structured.offset - (settings?.timingOffsetMs ?? 0)
        var newIndex: Int? = nil
        for (index, line) in structured.line.enumerated() {
            guard let start = line.start else { continue }
            if start <= adjustedMs {
                newIndex = index
            } else {
                break
            }
        }
        if newIndex != currentLineIndex {
            currentLineIndex = newIndex
        }
    }

    // MARK: - Seek

    func userTapped(lineIndex: Int) {
        guard case .loaded(let structured) = state, structured.synced else { return }
        guard lineIndex < structured.line.count else { return }
        guard let startMs = structured.line[lineIndex].start else { return }
        let targetSeconds = TimeInterval(startMs + structured.offset + (settings?.timingOffsetMs ?? 0)) / 1000.0
        Task { [weak self] in
            await self?.playerService.seek(to: targetSeconds)
        }
    }

    // MARK: - Following

    func userStartedScrolling() {
        isFollowing = false
    }

    func resumeFollowing() {
        isFollowing = true
    }

    // MARK: - Language selection

    func selectLanguage(_ lang: String) {
        guard selectedLanguage != lang else { return }
        selectedLanguage = lang
        currentLineIndex = nil
        applyCurrentLanguage()
    }

    // MARK: - Timer lifecycle

    var isPlaying: Bool { playerState.playbackState == .playing }

    private var hasSyncedLyrics: Bool {
        if case .loaded(let structured) = state { return structured.synced }
        return false
    }

    /// Called when the lyrics panel appears/disappears. Closing it starts following again, so the
    /// panel always opens on the current line.
    func setVisible(_ visible: Bool) {
        isPanelShown = visible
        if !visible { isFollowing = true }
        reconcileTracking()
    }

    /// Called when the player's single current line appears/disappears (#36).
    func setLineVisible(_ visible: Bool) {
        isLineShown = visible
        reconcileTracking()
    }

    /// The line to show in the player: the current one, or the first once playback starts.
    var currentLine: String? {
        guard case .loaded(let structured) = state, structured.synced,
              let index = currentLineIndex, structured.line.indices.contains(index) else { return nil }
        let value = structured.line[index].value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    /// Runs line tracking only for visible, playing, time-synced lyrics.
    func reconcileTracking() {
        if (isPanelShown || isLineShown) && isPlaying && hasSyncedLyrics {
            startTimer()
        } else {
            stopTimer()
            // A seek while paused still moves the line.
            if isPanelShown || isLineShown { update(elapsedMs: Int(playerState.position * 1000)) }
        }
    }

    private func startTimer() {
        guard trackingTask == nil else { return }
        trackingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .milliseconds(250))
                } catch {
                    return
                }
                guard let self else { return }
                self.update(elapsedMs: Int(self.playerState.position * 1000))
            }
        }
    }

    private func stopTimer() {
        trackingTask?.cancel()
        trackingTask = nil
    }

    // MARK: - Private helpers

    private func applyCurrentLanguage() {
        guard let list = lyricsList else { return }
        // "xxx" and "und" both mean "unspecified", and a plain and a synced set of the same language
        // are one choice, not two.
        var seen = Set<String>()
        availableLanguages = list.structuredLyrics
            .compactMap { $0.lang == "xxx" ? "und" : $0.lang }
            .filter { seen.insert($0).inserted }
        let best = lyricsService.selectBestLanguage(from: list, preferred: selectedLanguage)
        currentLineIndex = nil
        state = best.map { .loaded($0) } ?? .empty
        Logger.lyrics.info(
            "[LINE] songId=\(self.track.id, privacy: .public) source=\(self.source.rawValue, privacy: .public) sets=\(list.structuredLyrics.map { ($0.lang ?? "nil") + ($0.synced ? "/synced" : "/plain") }.joined(separator: ","), privacy: .public) chose=\(best.map { ($0.lang ?? "nil") + ($0.synced ? "/synced" : "/plain") } ?? "none", privacy: .public)"
        )
        reconcileTracking()
    }

    private func networkErrorMessage(from error: LyricsError) -> String {
        if case .networkError(let msg) = error { return msg }
        return error.localizedDescription
    }
}
