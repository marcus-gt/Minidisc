import SwiftUI

/// The bar along the bottom of the window: what's playing, transport controls with a seek bar, and
/// volume. It reads `PlayerState` (the listener's intent) and sends everything to `PlayerService`.
struct MacPlayerBar: View {
    @Environment(\.appContainer) private var container
    /// Where the seek bar is held while dragging; the player only seeks on release.
    @State private var scrubPosition: TimeInterval?
    @State private var volume: Double = Double(PlaybackPreferences.defaultVolume)

    var body: some View {
        if let container {
            content(container.playerState, playerService: container.playerService)
                .task { volume = Double(container.playbackPreferences.restoredVolume) }
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

            volumeControl(playerService: playerService)
                .frame(width: 160)
        }
        .padding(.horizontal, MaeksterSpacing.l)
        .padding(.vertical, MaeksterSpacing.s)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private func nowPlaying(_ state: PlayerState) -> some View {
        HStack(spacing: MaeksterSpacing.m) {
            CoverArtCard(id: state.currentTrack?.coverArtId ?? "", size: 44, cornerRadius: MaeksterCornerRadius.s)
            VStack(alignment: .leading, spacing: 2) {
                Text(state.currentTrack?.title ?? "")
                    .font(.headline)
                Text(state.currentTrack?.artist ?? "")
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
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
            Text(MacTrackTable.time(duration))
                .frame(width: 44, alignment: .leading)
        }
        .font(.caption)
        .monospacedDigit()
        .foregroundStyle(.secondary)
    }

    private func volumeControl(playerService: any PlayerServiceProtocol) -> some View {
        HStack(spacing: MaeksterSpacing.s) {
            Image(systemName: "speaker.fill")
            Slider(value: $volume, in: 0...1)
                .controlSize(.small)
                .onChange(of: volume) { _, newValue in
                    Task { await playerService.setVolume(Float(newValue)) }
                }
            Image(systemName: "speaker.wave.3.fill")
        }
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Volume")
    }
}
