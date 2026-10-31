import OSLog
import SwiftSonic
import SwiftUI

/// What a long-press on a heart offers (#68): the quick playlists, then the full playlist sheet.
struct QuickPlaylistMenuItems: View {
    let song: DisplayableSong
    /// Opens the full playlist sheet; nil where a row can't present it.
    let onAddToPlaylist: ((DisplayableSong) -> Void)?

    @Environment(\.appContainer) private var container

    private var entries: [QuickPlaylists.Entry] {
        guard let container, let serverID = container.serverState.activeServer?.id.uuidString else { return [] }
        return container.quickPlaylists.entries(serverID: serverID)
    }

    var body: some View {
        Section {
            ForEach(entries) { entry in
                Button("Add to \(entry.name)", systemImage: "text.badge.plus") {
                    guard let container else { return }
                    Task { await QuickPlaylistAction.add(song, to: entry, container: container) }
                }
            }
        } header: {
            if entries.isEmpty {
                Text("Mark playlists as quick playlists from their ⋯ menu.")
            }
        }
        if let onAddToPlaylist {
            Button("Add to Playlist…", systemImage: "music.note.list") {
                onAddToPlaylist(song)
            }
        }
    }
}

/// Adds a song to a quick playlist straight away, without the playlist sheet (#68).
@MainActor
enum QuickPlaylistAction {
    static func add(_ song: DisplayableSong, to entry: QuickPlaylists.Entry, container: AppContainer) async {
        HapticFeedback.light.trigger()
        do {
            let playlist = try await container.playlistService.getPlaylist(id: entry.id)
            if playlist.entry?.contains(where: { $0.id == song.id }) == true {
                container.toastService.show(String(localized: "Already in \(entry.name)"), subtitle: song.title,
                                            coverArtId: song.coverArtId)
            } else {
                try await container.playlistService.addTracks(playlistId: entry.id, songs: [song.asSong()])
                container.recordPlaylistUse(entry.id)
                container.toastService.showConfirmation(
                    String(localized: "Added to \(entry.name)"), subtitle: song.title, coverArtId: song.coverArtId,
                    action: .navigateToPlaylist(id: entry.id, name: entry.name, coverArtId: playlist.coverArt)
                )
            }
            if container.quickPlaylists.alsoLikes,
               !container.favoritesService.isFavorite(itemType: .song, itemId: song.id) {
                try await container.favoritesService.star(itemType: .song, itemId: song.id)
            }
        } catch {
            guard !UserFacingError.isCancellation(error) else { return }
            Logger.library.error("[QUICK-PLAYLIST] add failed: \(error, privacy: .public)")
            container.toastService.showError(UserFacingError.from(error).displayMessage)
        }
    }
}
