import SwiftUI
import SwiftSonic

/// A playlist to rename, from a long-press or "…" menu.
struct PlaylistRenameRequest: Identifiable {
    let playlistId: String
    let currentName: String
    let coverArtId: String?
    var id: String { playlistId }
}

@MainActor
enum PlaylistRenamer {
    /// Mood and Wrapped playlists are named by the app and would be renamed back on their next sync.
    static func canRename(playlistName: String) -> Bool {
        Mood.forPlaylistName(playlistName) == nil && WrappedPlaylistService.year(fromPlaylistName: playlistName) == nil
    }

    /// Renames on the server, then brings everything that keeps its own copy of the name along: the
    /// pin's snapshot, and a picked gradient cover, which has the title drawn into it. Lists reload
    /// through the playlist-change notification the mutation already posts.
    @discardableResult
    static func rename(playlistId: String, coverArtId: String?, to newName: String, container: AppContainer) async -> Bool {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        guard await container.toastService.perform({
            try await container.playlistService.renamePlaylist(id: playlistId, newName: name)
        }) else { return false }
        didRename(playlistId: playlistId, coverArtId: coverArtId, to: name, container: container)
        if let serverId = container.serverState.activeServer?.id {
            await rebakeGradientTitle(playlistId: playlistId, coverArtId: coverArtId, title: name,
                                      serverId: serverId, container: container)
        }
        return true
    }

    /// The parts of a rename that don't touch the server; the full edit screen calls this after saving.
    static func didRename(playlistId: String, coverArtId: String?, to name: String, container: AppContainer) {
        container.pinService.updateDisplayName(itemType: .playlist, itemId: playlistId, displayName: name)
    }

    /// A gradient cover carries the playlist title as pixels, so a rename has to re-render it.
    static func rebakeGradientTitle(playlistId: String, coverArtId: String?, title: String,
                                    serverId: UUID, container: AppContainer) async {
        let store = PlaylistCoverStore(modelContainer: container.modelContainer)
        guard let choice = store.choice(playlistId: playlistId, serverId: serverId),
              choice.isUserPicked, let spec = choice.spec else { return }
        let manager = PlaylistCoverManager(downloadService: container.downloadService,
                                           artworkImageCache: container.artworkImageCache)
        await manager.applyGradientCover(spec, playlistId: playlistId, title: title, coverArtId: coverArtId)
    }
}

/// The rename dialog: one text field, prefilled with the current name.
private struct PlaylistRenameAlertModifier: ViewModifier {
    @Binding var request: PlaylistRenameRequest?
    let onRenamed: (() -> Void)?
    @Environment(\.appContainer) private var container
    @State private var draft = ""

    func body(content: Content) -> some View {
        content
            .alert("Rename Playlist", isPresented: Binding(
                get: { request != nil }, set: { if !$0 { request = nil } }
            ), presenting: request) { request in
                TextField("Playlist Title", text: $draft)
                    .submitLabel(.done)
                Button("Cancel", role: .cancel) {}
                Button("Rename") {
                    guard let container else { return }
                    let name = draft
                    Task {
                        if await PlaylistRenamer.rename(playlistId: request.playlistId, coverArtId: request.coverArtId,
                                                        to: name, container: container) {
                            onRenamed?()
                        }
                    }
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || draft.trimmingCharacters(in: .whitespacesAndNewlines) == request.currentName)
            }
            .onChange(of: request?.playlistId) { _, _ in
                draft = request?.currentName ?? ""
            }
    }
}

extension View {
    func playlistRenameAlert(_ request: Binding<PlaylistRenameRequest?>, onRenamed: (() -> Void)? = nil) -> some View {
        modifier(PlaylistRenameAlertModifier(request: request, onRenamed: onRenamed))
    }
}
