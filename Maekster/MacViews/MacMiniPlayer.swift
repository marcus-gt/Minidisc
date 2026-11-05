import SwiftData
import SwiftUI

extension View {
    /// The environment every Mac window needs (the main window gets it from `MaeksterApp`): the
    /// container, artwork and colour caches, toasts and the SwiftData store.
    func macAppEnvironment(_ container: AppContainer) -> some View {
        self
            .environment(\.appContainer, container)
            .environment(container.dominantColorExtractor)
            .environment(container.artworkImageCache)
            .environment(container.toastService)
            .modelContainer(container.modelContainer)
    }
}

/// A small window that floats above others (Window › Mini Player, ⇧⌘M): the cover on the
/// artwork-coloured background, the song, and previous / play-pause / next.
struct MacMiniPlayer: View {
    static let windowID = "mini-player"

    let container: AppContainer?

    var body: some View {
        if let container {
            content(container.playerState, playerService: container.playerService)
                .macAppEnvironment(container)
        } else {
            ProgressView()
                .frame(width: 280, height: 360)
        }
    }

    private func content(_ state: PlayerState, playerService: any PlayerServiceProtocol) -> some View {
        VStack(spacing: MaeksterSpacing.m) {
            CoverArtView(id: macCoverArtId(state) ?? "", size: 560, tier: .hero, cornerRadius: MaeksterCornerRadius.standard)
                .aspectRatio(1, contentMode: .fit)
                .shadow(radius: 12, y: 4)

            VStack(spacing: 2) {
                Text(state.currentTrack?.title ?? "")
                    .font(.headline)
                Text(state.currentTrack?.artist ?? "")
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)

            HStack(spacing: MaeksterSpacing.xl) {
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
                        .font(.system(size: 36))
                }
                Button {
                    Task { await container?.toastService.perform { try await playerService.skipToNext() } }
                } label: {
                    Label("Next Track", systemImage: "forward.fill")
                }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .disabled(state.currentTrack == nil)
        }
        .padding(MaeksterSpacing.l)
        .frame(width: 280)
        .background { MacArtworkBackground() }
        .environment(\.colorScheme, .dark)
    }
}
