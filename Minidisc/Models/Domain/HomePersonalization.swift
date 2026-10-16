import Foundation
import SwiftSonic

nonisolated struct HomeFavorites: Codable, Sendable {
    var songs: [Song] = []
    var albums: [AlbumID3] = []
    var artists: [ArtistID3] = []
}

enum HomePersonalization {
    static func unique(_ albums: [AlbumID3], excluding ids: Set<String> = []) -> [AlbumID3] {
        var seen = ids
        return albums.filter { seen.insert($0.id).inserted }
    }

    /// The first `limit` playlists, plus any later ones whose IDs are in `keeping`, in their original order.
    static func cappedPlaylists(_ playlists: [Playlist], limit: Int, keeping ids: Set<String>) -> [Playlist] {
        playlists.enumerated().filter { $0.offset < limit || ids.contains($0.element.id) }.map(\.element)
    }

    /// The Home playlist shelf: everything, or only the pinned playlists in pin order.
    static func shelfPlaylists(_ playlists: [Playlist], pinnedIDs: [String], pinnedOnly: Bool) -> [Playlist] {
        guard pinnedOnly else { return playlists }
        let byID = Dictionary(playlists.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return pinnedIDs.compactMap { byID[$0] }
    }

    static func rediscovery(favorites: [AlbumID3], frequent: [AlbumID3], recent: [AlbumID3]) -> [AlbumID3] {
        unique(favorites + frequent, excluding: Set(recent.map(\.id))).prefix(12).map { $0 }
    }

    static func relevantAdditions(_ additions: [AlbumID3], favorites: HomeFavorites, frequent: [AlbumID3]) -> [AlbumID3] {
        let ids = Set(favorites.artists.map(\.id) + favorites.albums.compactMap(\.artistId)
                      + favorites.songs.compactMap(\.artistId) + frequent.prefix(8).compactMap(\.artistId))
        // Names are a fallback only for servers that omit artist IDs.
        let names = Set((favorites.artists.map(\.name) + favorites.albums.compactMap(\.artist)
                         + favorites.songs.compactMap(\.artist) + frequent.prefix(8).compactMap(\.artist))
            .map(LibrarySearchRanking.normalized).filter { !$0.isEmpty })
        return unique(additions.filter { album in
            if let id = album.artistId { return ids.contains(id) }
            return album.artist.map { names.contains(LibrarySearchRanking.normalized($0)) } ?? false
        })
    }
}
