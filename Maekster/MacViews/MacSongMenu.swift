import SwiftData
import SwiftUI

/// The current section's navigation stack, so menus deep in a page can open another page (an album
/// from a song's menu, …).
@Observable
final class MacNavigator {
    var path = NavigationPath()

    func open(_ route: MacRoute) {
        path.append(route)
    }
}

/// The context menu for one or more songs in a track table: the same actions as the iPhone song
/// menu, plus going to the song's album or artist, downloading, and adding to a playlist.
struct MacSongMenu: View {
    let songs: [DisplayableSong]
    /// Plays from the right-clicked song, in the table's own order and source.
    let onPlay: () -> Void
    /// Set on playlist pages.
    var onRemove: (([DisplayableSong]) -> Void)?

    @Environment(\.appContainer) private var container
    @Environment(MacNavigator.self) private var navigator
    @Environment(PlaylistAddition.self) private var playlistAddition

    var body: some View {
        Button("Play", systemImage: "play.fill", action: onPlay)
        Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") {
            Task { await container?.playerService.playNext(songs) }
        }
        Button("Add to Queue", systemImage: "text.append") {
            Task { await container?.playerService.addToQueue(songs) }
        }
        if let song = single {
            Button("Instant Mix", systemImage: instantMixSymbol) {
                startInstantMix(from: .song(id: song.id), using: container, startingWith: song)
            }
        }

        Divider()

        if !songs.contains(where: \.isLocalFile) {
            Button("Add to Playlist…", systemImage: "text.badge.plus") {
                playlistAddition.present(songs: songs)
            }
        }
        if let onRemove {
            Button("Remove from Playlist", systemImage: "minus.circle", role: .destructive) { onRemove(songs) }
        }
        favoriteButton
        downloadButton

        if let song = single {
            Divider()
            if let albumId = song.albumId {
                Button("Go to Album", systemImage: "square.stack") { navigator.open(.album(id: albumId)) }
            }
            if let artistId = song.artistId {
                Button("Go to Artist", systemImage: "music.mic") {
                    navigator.open(.artist(id: artistId, name: song.artist ?? ""))
                }
            }
        }
    }

    private var single: DisplayableSong? { songs.count == 1 ? songs.first : nil }

    /// One heart for the whole selection: it removes only when every song is already a favourite.
    @ViewBuilder
    private var favoriteButton: some View {
        if let favorites = container?.favoritesService {
            let allFavorite = songs.allSatisfy { favorites.isFavorite(itemType: .song, itemId: $0.id) }
            Button(allFavorite ? "Remove from Favorites" : "Add to Favorites",
                   systemImage: allFavorite ? "heart.slash" : "heart") {
                let ids = songs.map(\.id)
                Task {
                    for id in ids {
                        if allFavorite {
                            try? await favorites.unstar(itemType: .song, itemId: id)
                        } else {
                            try? await favorites.star(itemType: .song, itemId: id)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var downloadButton: some View {
        let streamable = songs.filter { !$0.isLocalFile }
        if !streamable.isEmpty, let container, let serverId = container.serverState.activeServer?.id {
            if streamable.allSatisfy(\.isDownloaded) {
                Button("Remove Download", systemImage: "trash") {
                    Task {
                        for song in streamable {
                            await container.toastService.perform {
                                try await container.downloadService.remove(songId: song.id, serverId: serverId)
                            }
                        }
                    }
                }
            } else {
                Button("Download", systemImage: "arrow.down.circle") {
                    Task {
                        for song in streamable where !song.isDownloaded {
                            await container.toastService.perform {
                                try await container.downloadService.download(song: song.asSong(), serverId: serverId)
                            }
                        }
                    }
                }
            }
        }
    }
}

/// The context menu for an artist: play or shuffle everything by them, an Instant Mix, and the heart.
struct MacArtistMenu: View {
    let artistId: String
    let artistName: String

    @Environment(\.appContainer) private var container
    @Query private var favoriteMatches: [FavoriteRecord]

    init(artistId: String, artistName: String) {
        self.artistId = artistId
        self.artistName = artistName
        let compositeId = "\(FavoriteType.artist.rawValue):\(artistId)"
        _favoriteMatches = Query(filter: #Predicate<FavoriteRecord> { $0.id == compositeId })
    }

    var body: some View {
        Button("Play", systemImage: "play.fill") { playAll(shuffled: false) }
        Button("Shuffle", systemImage: "shuffle") { playAll(shuffled: true) }
        Button("Instant Mix", systemImage: instantMixSymbol) {
            startInstantMix(from: .artist(id: artistId), using: container, titled: artistName)
        }
        if let favorites = container?.favoritesService {
            Divider()
            let isFavorite = !favoriteMatches.isEmpty
            Button(isFavorite ? "Remove from Favorites" : "Add to Favorites",
                   systemImage: isFavorite ? "heart.slash" : "heart") {
                Task {
                    if isFavorite {
                        try? await favorites.unstar(itemType: .artist, itemId: artistId)
                    } else {
                        try? await favorites.star(itemType: .artist, itemId: artistId)
                    }
                }
            }
        }
    }

    private func playAll(shuffled: Bool) {
        guard let container else { return }
        let source = QueueSource.artist(id: artistId, name: artistName)
        Task {
            await container.toastService.perform {
                var tracks = try await container.libraryService.fetchAllTracks(forArtistID: artistId)
                if shuffled { tracks.shuffle() }
                try await container.playerService.play(tracks: tracks, startIndex: 0, source: source)
            }
        }
    }
}
