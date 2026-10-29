import Foundation
import SwiftSonic

/// "Recently Played" order for album and artist lists, from Navidrome's recently-played album list,
/// which the server keeps current. Artists rank by their most recently played album.
nonisolated struct RecentlyPlayedOrder: Sendable, Equatable {
    /// How many recently played albums the server is asked for (its maximum per request).
    static let albumLimit = 500

    private(set) var albumIDs: [String] = []
    private(set) var artistIDs: [String] = []

    init() {}

    init(recentlyPlayedAlbums albums: [AlbumID3]) {
        var seenAlbums = Set<String>()
        var seenArtists = Set<String>()
        for album in albums where seenAlbums.insert(album.id).inserted {
            albumIDs.append(album.id)
            for id in [album.artistId].compactMap({ $0 }) + (album.artists?.map(\.id) ?? []) where seenArtists.insert(id).inserted {
                artistIDs.append(id)
            }
        }
    }

    /// Loads the order from the server; empty when it can't be reached, so lists fall back to
    /// the last-played dates they already carry.
    static func load(from library: any LibraryServiceProtocol) async -> RecentlyPlayedOrder {
        guard let albums = try? await library.recentlyPlayedAlbums(size: albumLimit) else { return RecentlyPlayedOrder() }
        return RecentlyPlayedOrder(recentlyPlayedAlbums: albums)
    }

    /// Items in `order` first, in that order; the rest after, in `remainder`'s order.
    static func ranked<T>(_ items: [T], by order: [String], id: (T) -> String,
                          remainder: ([T]) -> [T]) -> [T] {
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let ranked = items.filter { rank[id($0)] != nil }.sorted { rank[id($0)]! < rank[id($1)]! }
        return ranked + remainder(items.filter { rank[id($0)] == nil })
    }

    /// Newest `date` first; items without one after, by `name`.
    static func byDateThenName<T>(_ items: [T], date: (T) -> Date?, name: (T) -> String) -> [T] {
        items.sorted { lhs, rhs in
            switch (date(lhs), date(rhs)) {
            case let (l?, r?) where l != r: return l > r
            case (.some, nil): return true
            case (nil, .some): return false
            default: return name(lhs).localizedStandardCompare(name(rhs)) == .orderedAscending
            }
        }
    }
}
