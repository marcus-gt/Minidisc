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

    static func rediscovery(favorites: [AlbumID3], frequent: [AlbumID3], recent: [AlbumID3]) -> [AlbumID3] {
        unique(favorites + frequent, excluding: Set(recent.map(\.id))).prefix(12).map { $0 }
    }
}
