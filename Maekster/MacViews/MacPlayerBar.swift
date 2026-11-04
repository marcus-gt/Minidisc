import AppKit
import SwiftUI

/// The bar along the bottom of the window: what's playing, transport controls with a seek bar, and
/// volume. It reads `PlayerState` (the listener's intent) and sends everything to `PlayerService`.
struct MacPlayerBar: View {
    @Environment(\.appContainer) private var container
    @Environment(MacPlayerPanels.self) private var panels
    @Environment(MacNavigator.self) private var navigator
    /// Where the seek bar is held while dragging; the player only seeks on release.
    @State private var scrubPosition: TimeInterval?

    var body: some View {
        if let container {
            content(container.playerState, playerService: container.playerService)
                .task { panels.volume = Double(container.playbackPreferences.restoredVolume) }
        }
    }

    private func content(_ state: PlayerState, playerService: any PlayerServiceProtocol) -> some View {
        HStack(spacing: MaeksterSpacing.xl) {
            nowPlaying(state)
                .frame(width: 260, alignment: .leading)

            VStack(spacing: MaeksterSpacing.xs) {
                transport(state, playerService: playerService)
                seekBar(state, playerService: playerService)
            }
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)

            HStack(spacing: MaeksterSpacing.m) {
                panelToggles(state)
                volumeControl(playerService: playerService)
                    .frame(width: 140)
            }
        }
        .padding(.horizontal, MaeksterSpacing.l)
        .padding(.vertical, MaeksterSpacing.s)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    /// Clicking the cover or title opens (or closes) Now Playing; the artist and album below open
    /// their pages, like the Music app.
    private func nowPlaying(_ state: PlayerState) -> some View {
        HStack(spacing: MaeksterSpacing.m) {
            Button {
                panels.showsNowPlaying.toggle()
            } label: {
                CoverArtCard(id: state.currentTrack?.coverArtId ?? "", size: 44, cornerRadius: MaeksterCornerRadius.s)
            }
            .help("Now Playing")

            VStack(alignment: .leading, spacing: 2) {
                Button {
                    panels.showsNowPlaying.toggle()
                } label: {
                    Text(state.currentTrack?.title ?? "")
                        .font(.headline)
                }
                .help("Now Playing")

                HStack(spacing: MaeksterSpacing.xs) {
                    if let track = state.currentTrack {
                        link(track.artist, route: track.artistId.map { .artist(id: $0, name: track.artist ?? "") })
                        if let album = track.albumName, !album.isEmpty {
                            Text(verbatim: "—")
                            link(album, route: track.albumId.map { .album(id: $0) })
                        }
                    }
                }
                .foregroundStyle(.secondary)
            }
            .lineLimit(1)
        }
        .buttonStyle(.plain)
        .disabled(state.currentTrack == nil && state.currentRadio == nil)
    }

    /// Text that opens `route` (leaving Now Playing), or plain text when there's no page to open.
    @ViewBuilder
    private func link(_ text: String?, route: MacRoute?) -> some View {
        if let route {
            Button {
                panels.showsNowPlaying = false
                navigator.open(route)
            } label: {
                Text(verbatim: text ?? "")
            }
            .onHover { inside in
                if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
        } else {
            Text(verbatim: text ?? "")
        }
    }

    private func transport(_ state: PlayerState, playerService: any PlayerServiceProtocol) -> some View {
        HStack(spacing: MaeksterSpacing.l) {
            Button {
                Task { await playerService.toggleShuffle() }
            } label: {
                Label(state.isShuffled ? "Shuffle On" : "Shuffle Off", systemImage: "shuffle")
            }
            .foregroundStyle(state.isShuffled ? Color.maeksterAccent : .secondary)

            Button {
                Task { await container?.toastService.perform { try await playerService.skipToPrevious() } }
            } label: {
                Label("Previous Track", systemImage: "backward.fill")
            }

            Button {
                Task { await playerService.togglePlayPause() }
            } label: {
                Label(state.wantsPlayback ? "Pause" : "Play",
                      systemImage: state.wantsPlayback ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 32))
            }

            Button {
                Task { await container?.toastService.perform { try await playerService.skipToNext() } }
            } label: {
                Label("Next Track", systemImage: "forward.fill")
            }

            Button {
                Task { await playerService.setRepeatMode(state.repeatMode.next) }
            } label: {
                Label("Repeat", systemImage: state.repeatMode.systemImage)
            }
            .foregroundStyle(state.repeatMode == .off ? .secondary : Color.maeksterAccent)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.plain)
        .disabled(state.currentTrack == nil)
    }

    private func seekBar(_ state: PlayerState, playerService: any PlayerServiceProtocol) -> some View {
        let duration = max(state.duration, 0)
        let shown = scrubPosition ?? PlaybackClock.shownElapsed(state.position, duration: duration)
        return HStack(spacing: MaeksterSpacing.s) {
            Text(MacTrackTable.time(shown))
                .frame(width: 44, alignment: .trailing)
            Slider(
                value: Binding(get: { shown }, set: { scrubPosition = $0 }),
                in: 0...max(duration, 1)
            ) { editing in
                guard !editing, let target = scrubPosition else { return }
                Task {
                    await playerService.seek(to: target)
                    scrubPosition = nil
                }
            }
            .controlSize(.small)
            .disabled(duration <= 0 || state.isLiveStream)
            // The time left, counting down, like the Music app.
            Text(verbatim: duration > 0 ? "−" + MacTrackTable.time(duration - shown) : MacTrackTable.time(0))
                .frame(width: 44, alignment: .leading)
        }
        .font(.caption)
        .monospacedDigit()
        .foregroundStyle(.secondary)
    }

    /// Lyrics live in Now Playing: the lyrics button shows or hides them there (opening it if
    /// needed). The queue is a panel.
    private func panelToggles(_ state: PlayerState) -> some View {
        HStack(spacing: MaeksterSpacing.s) {
            Button {
                panels.toggleLyrics()
            } label: {
                Label("Lyrics", systemImage: "quote.bubble")
            }
            .foregroundStyle(panels.showsNowPlaying && panels.showsLyrics ? Color.maeksterAccent : .secondary)
            .disabled(state.currentTrack == nil)
            .help("Lyrics")

            Button {
                panels.showsQueue.toggle()
            } label: {
                Label("Queue", systemImage: "list.bullet")
            }
            .foregroundStyle(panels.showsQueue ? Color.maeksterAccent : .secondary)
            .help("Queue")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.plain)
        .imageScale(.large)
    }

    private func volumeControl(playerService: any PlayerServiceProtocol) -> some View {
        HStack(spacing: MaeksterSpacing.s) {
            Image(systemName: "speaker.fill")
            Slider(value: Binding(get: { panels.volume }, set: { panels.volume = $0 }), in: 0...1)
                .controlSize(.small)
                .onChange(of: panels.volume) { _, newValue in
                    Task { await playerService.setVolume(Float(newValue)) }
                }
            Image(systemName: "speaker.wave.3.fill")
        }
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Volume")
    }
}
