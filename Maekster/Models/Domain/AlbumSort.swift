import Foundation
import SwiftSonic

nonisolated enum AlbumSort: String, CaseIterable, Sendable {
    case recentlyAdded
    case recentlyPlayed
    case releaseYear
    case name

    var label: String {
        switch self {
        case .recentlyAdded: return "Recently Added"
        case .recentlyPlayed: return "Recently Played"
        case .releaseYear: return "Release Year"
        case .name: return "Name"
        }
    }

    var systemImage: String {
        switch self {
        case .recentlyAdded: return "clock"
        case .recentlyPlayed: return "play.circle"
        case .releaseYear: return "calendar"
        case .name: return "textformat"
        }
    }

    /// Orders an already-fetched album array. Missing fields (no `created`, no `year`) sort last.
    /// Recently Played follows the server's recently-played list, then the albums' own last-played dates.
    func sorted(_ albums: [AlbumID3], recentlyPlayed: RecentlyPlayedOrder = RecentlyPlayedOrder()) -> [AlbumID3] {
        switch self {
        case .recentlyAdded:
            return albums.sorted { ($0.created ?? .distantPast) > ($1.created ?? .distantPast) }
        case .recentlyPlayed:
            return RecentlyPlayedOrder.ranked(albums, by: recentlyPlayed.albumIDs, id: \.id) {
                RecentlyPlayedOrder.byDateThenName($0, date: \.played, name: sortKey)
            }
        case .releaseYear:
            return albums.sorted { ($0.year ?? Int.min) > ($1.year ?? Int.min) }
        case .name:
            return albums.sorted { sortKey($0).localizedStandardCompare(sortKey($1)) == .orderedAscending }
        }
    }

    private func sortKey(_ album: AlbumID3) -> String { album.sortName ?? album.name }
}
