import SwiftUI
import OSLog
import UIKit

/// Keep close/share controls above the navigation gesture layer.
struct WrappedStoryPlayerView: View {
    let year: Int

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appContainer) private var container
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let slides = WrappedStorySlideKind.allCases
    /// Long enough for a song to fade in and be heard before the crossfade (#75).
    private let slideDuration: Double = 10.0
    private let timerInterval: Double = 0.05

    @State private var currentIndex = 0
    @State private var progress: Double = 0.0
    @State private var isPaused = false
    @State private var timerTask: Task<Void, Never>? = nil
    @State private var longPressTask: Task<Void, Never>? = nil
    @State private var wrappedData: WrappedData? = nil
    /// A song per slide (#75), on players of the story's own.
    @State private var audio: WrappedStoryAudio?
    @State private var story: WrappedDataSource.StoryDetails = .empty
    /// The main player was playing when the story opened, so it picks up again on close.
    @State private var resumesMainPlayer = false
    /// Pausing the main player deactivates the audio session; the story's music starts after that.
    @State private var mainPlayerPause: Task<Void, Never>?

    @State private var renderedImage: UIImage? = nil
    @State private var showShareSheet = false
    @State private var isRendering = false

    private var palette: [Color] { WrappedYearPalette.colors(for: year) }

    var body: some View {
        ZStack {
            // Gradient base matches all slide backgrounds: no black flash during cross-dissolve.
            MeshGradientBackground(palette: palette, animated: false).ignoresSafeArea()

            slideContent(for: slides[currentIndex])
                .ignoresSafeArea()
                .id(currentIndex)
                .transition(.opacity)

            if ![.intro, .closing].contains(slides[currentIndex]) {
                // The intro and closing slides carry the mark large; the rest sign off at the foot.
                VStack {
                    Spacer()
                    WrappedBrandFooter(year: year)
                        .padding(.bottom, MinidiscSpacing.xl)
                }
                .allowsHitTesting(false)
            }

            gestureLayer

            overlayControls

            if slides[currentIndex] == .closing, let data = wrappedData {
                closingShareOverlay(data: data)
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            startTimer()
            startAudio()
        }
        .onDisappear {
            timerTask?.cancel()
            stopAudio()
        }
        .task { await loadWrappedData() }
        .onChange(of: currentIndex) { _, _ in playSoundtrack() }
        .onChange(of: isPaused) { _, paused in
            if paused { audio?.pause() } else { audio?.resume() }
        }
        .sheet(isPresented: $showShareSheet) {
            if let image = renderedImage { SystemShareSheet(item: image) }
        }
        .onChange(of: showShareSheet) { _, presented in isPaused = presented }
    }

    private func loadWrappedData() async {
        guard let container,
              let serverId = container.serverState.activeServer?.id.uuidString else { return }
        let data = await container.wrappedDataSource.wrappedData(
            for: .year(year),
            serverId: serverId,
            calendar: .current
        ).data
        wrappedData = data
        story = await container.wrappedDataSource.storyDetails(for: data, serverId: serverId, calendar: .current)
        playSoundtrack()
    }

    // MARK: - Soundtrack

    private func startAudio() {
        guard let container, audio == nil else { return }
        let resolver = container.mediaResolver
        let serverID = container.serverState.activeServer?.id
        audio = WrappedStoryAudio { songID in
            guard let serverID, let source = try? await resolver.resolve(songId: songID, serverId: serverID) else { return nil }
            switch source {
            case .downloaded(let url), .cached(let url): return (url, [:])
            case .stream(let url, let headers): return (url, headers)
            case .localFile, .liveStream: return nil
            }
        }
        if container.playerState.playbackState == .playing {
            resumesMainPlayer = true
            let player = container.playerService
            mainPlayerPause = Task { await player.pause() }
        }
    }

    private func playSoundtrack() {
        guard let audio else { return }
        let song = story.trackIDs[slides[currentIndex]].flatMap { story.songs[$0] }
        let pause = mainPlayerPause
        Task {
            await pause?.value
            await audio.play(song)
        }
    }

    private func stopAudio() {
        audio?.stop()
        guard resumesMainPlayer, let container else { return }
        resumesMainPlayer = false
        Task { await container.playerService.resume() }
    }

    // MARK: - Overlay (progress bar + close button)

    private var overlayControls: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: MinidiscSpacing.s) {
                WrappedStoryProgressBar(
                    totalSlides: slides.count,
                    currentIndex: currentIndex,
                    progress: progress
                )
                if let audio, !story.trackIDs.isEmpty {
                    Button {
                        audio.toggleMute()
                    } label: {
                        Image(systemName: audio.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 16, height: 16)
                            .padding(8)
                            .background(Color.white.opacity(0.2), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(audio.isMuted ? "Unmute" : "Mute"))
                }
                Button {
                    Logger.wrappedStory.debug("[STORY] dismissed via X button at slide=\(currentIndex, privacy: .public)")
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(Color.white.opacity(0.2), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, MinidiscSpacing.l)
            .padding(.top, MinidiscSpacing.s)
            Spacer()
        }
    }

    // MARK: - Gesture layer

    private var gestureLayer: some View {
        GeometryReader { proxy in
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { _ in
                            if longPressTask == nil {
                                longPressTask = Task {
                                    try? await Task.sleep(for: .milliseconds(300))
                                    guard !Task.isCancelled else { return }
                                    isPaused = true
                                    Logger.wrappedStory.debug("[STORY] long press — paused")
                                }
                            }
                        }
                        .onEnded { value in
                            longPressTask?.cancel()
                            longPressTask = nil
                            let wasLongPress = isPaused
                            if wasLongPress {
                                isPaused = false
                                Logger.wrappedStory.debug("[STORY] long press released — resumed")
                                return
                            }
                            if value.translation.height > 100 {
                                Logger.wrappedStory.debug("[STORY] swipe down — dismissing")
                                dismiss()
                                return
                            }
                            let dragDistance = sqrt(
                                pow(value.translation.width, 2) + pow(value.translation.height, 2)
                            )
                            guard dragDistance < 15 else { return }
                            if value.location.x < proxy.size.width / 2 {
                                goBack()
                            } else {
                                goForward()
                            }
                        }
                )
        }
        .ignoresSafeArea()
    }

    // MARK: - Slide content

    @ViewBuilder
    private func slideContent(for kind: WrappedStorySlideKind) -> some View {
        switch kind {
        case .intro:
            WrappedIntroSlide(year: year, palette: palette, artworkIDs: wrappedData?.topAlbums.map(\.albumId) ?? [])
        case .minutes:
            if let data = wrappedData {
                WrappedMinutesSlide(data: data, palette: palette)
            } else {
                loadingSlide
            }
        case .topTrack:
            if let data = wrappedData {
                WrappedTopTrackSlide(data: data, palette: palette)
            } else {
                loadingSlide
            }
        case .topArtist:
            if let data = wrappedData {
                WrappedTopArtistSlide(data: data, palette: palette)
            } else {
                loadingSlide
            }
        case .topAlbum:
            if let data = wrappedData {
                WrappedTopAlbumSlide(data: data, palette: palette)
            } else {
                loadingSlide
            }
        case .topGenre:
            if let data = wrappedData {
                WrappedTopGenreSlide(data: data, palette: palette, genres: story.topGenres)
            } else {
                loadingSlide
            }
        case .discoveries:
            if let data = wrappedData {
                WrappedDiscoveriesSlide(data: data, palette: palette)
            } else {
                loadingSlide
            }
        case .closing:
            if let data = wrappedData {
                WrappedClosingSlide(year: year, data: data, palette: palette)
            } else {
                loadingSlide
            }
        }
    }

    private var loadingSlide: some View {
        ZStack {
            MeshGradientBackground(palette: palette, animated: !reduceMotion)
            ProgressView().tint(.white)
        }
    }

    // MARK: - Navigation

    private func goForward() {
        HapticFeedback.light.trigger()
        if currentIndex < slides.count - 1 {
            progress = 0.0
            withAnimation(.easeInOut(duration: 0.25)) { currentIndex += 1 }
            Logger.wrappedStory.debug("[STORY] → slide \(currentIndex, privacy: .public)/\(slides.count, privacy: .public)")
        } else {
            Logger.wrappedStory.debug("[STORY] last slide reached — dismissing")
            timerTask?.cancel()
            timerTask = nil
            dismiss()
        }
    }

    private func goBack() {
        HapticFeedback.light.trigger()
        progress = 0.0
        withAnimation(.easeInOut(duration: 0.25)) {
            if currentIndex > 0 { currentIndex -= 1 }
        }
        Logger.wrappedStory.debug("[STORY] ← slide \(currentIndex, privacy: .public)/\(slides.count, privacy: .public)")
    }

    // MARK: - Timer

    private func startTimer() {
        timerTask?.cancel()
        timerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(Int(timerInterval * 1000)))
                guard !Task.isCancelled, !isPaused else { continue }
                guard currentIndex < slides.count - 1 else { continue }
                progress += timerInterval / slideDuration
                if progress >= 1.0 { goForward() }
            }
        }
    }

    // MARK: - Share (iOS only)

    private func closingShareOverlay(data: WrappedData) -> some View {
        VStack {
            Spacer()
            Button {
                guard !isRendering else { return }
                Task { await renderAndShare(data: data) }
            } label: {
                HStack(spacing: MinidiscSpacing.s) {
                    if isRendering {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                    }
                    Text(isRendering ? "Preparing…" : "Share your Wrapped")
                }
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, MinidiscSpacing.m)
                .background(Color.white.opacity(0.2), in: RoundedRectangle(cornerRadius: MinidiscCornerRadius.large, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, MinidiscSpacing.xl)
            .padding(.bottom, MinidiscSpacing.xl)
        }
    }

    @MainActor
    private func renderAndShare(data: WrappedData) async {
        isRendering = true
        let card = WrappedShareCardView(year: year, data: data, palette: palette)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3.0
        renderedImage = renderer.uiImage
        isRendering = false
        if renderedImage != nil { showShareSheet = true }
    }
}
