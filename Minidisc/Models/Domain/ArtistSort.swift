import Foundation
import SwiftSonic

/// User-selectable ordering for the artists list. Persists via `@AppStorage("minidisc.artistSort")`.
/// (ArtistID3 carries no date, so "recently added" isn't available without a different fetch.
/// Recently Played ranks artists by their most recently played album.)
nonisolated enum ArtistSort: String, CaseIterable, Sendable {
    case name
    case albumCount
    case recentlyPlayed

    var label: String {
        switch self {
        case .name: return "Name"
        case .albumCount: return "Album Count"
        case .recentlyPlayed: return "Recently Played"
        }
    }

    var systemImage: String {
        switch self {
        case .name: return "textformat"
        case .albumCount: return "square.stack"
        case .recentlyPlayed: return "play.circle"
        }
    }

    func sorted(_ artists: [ArtistID3], recentlyPlayed: RecentlyPlayedOrder = RecentlyPlayedOrder()) -> [ArtistID3] {
        switch self {
        case .recentlyPlayed:
            return RecentlyPlayedOrder.ranked(artists, by: recentlyPlayed.artistIDs, id: \.id) {
                ArtistSort.name.sorted($0)
            }
        case .name:
            return artists.sorted { key($0).localizedStandardCompare(key($1)) == .orderedAscending }
        case .albumCount:
            return artists.sorted {
                let a = $0.albumCount ?? 0, b = $1.albumCount ?? 0
                if a != b { return a > b }
                return key($0).localizedStandardCompare(key($1)) == .orderedAscending
            }
        }
    }

    private func key(_ artist: ArtistID3) -> String { artist.sortName ?? artist.name }
}
