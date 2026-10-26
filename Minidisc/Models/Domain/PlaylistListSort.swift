import Foundation
import SwiftSonic

/// Ordering for the Playlists list. Persists via `@AppStorage("minidisc.playlistListSort")`.
nonisolated enum PlaylistListSort: String, CaseIterable, Identifiable, Sendable {
    case lastUsed
    case recentlyCreated
    case name

    var id: String { rawValue }

    /// Orders the playlists. Ties and missing dates fall back to the name.
    /// - Parameter lastUsed: local "added to or played" dates by playlist id (`PlaylistUsageStore`).
    func sorted(_ playlists: [Playlist], lastUsed: [String: Date]) -> [Playlist] {
        switch self {
        case .lastUsed:
            return Self.sortedByDateDescending(playlists) { Self.lastUsedDate(of: $0, local: lastUsed) }
        case .recentlyCreated:
            return Self.sortedByDateDescending(playlists) { $0.created }
        case .name:
            return playlists.sorted(by: Self.nameAscending)
        }
    }

    /// The local record wins. Without one, the server's `changed` date stands in (it moves when songs are
    /// added, also from other clients), except for generated Mood and Wrapped playlists: their date moves on
    /// every automatic sync, which isn't a use.
    static func lastUsedDate(of playlist: Playlist, local: [String: Date]) -> Date? {
        if let date = local[playlist.id] { return date }
        let isGenerated = Mood.forPlaylistName(playlist.name) != nil
            || WrappedPlaylistService.year(fromPlaylistName: playlist.name) != nil
        return isGenerated ? nil : playlist.changed
    }

    private static func sortedByDateDescending(_ playlists: [Playlist], date: (Playlist) -> Date?) -> [Playlist] {
        playlists.sorted { lhs, rhs in
            switch (date(lhs), date(rhs)) {
            case let (left?, right?) where left != right: return left > right
            case (.some, nil): return true
            case (nil, .some): return false
            default: return nameAscending(lhs, rhs)
            }
        }
    }

    private static func nameAscending(_ lhs: Playlist, _ rhs: Playlist) -> Bool {
        switch lhs.name.localizedStandardCompare(rhs.name) {
        case .orderedAscending: return true
        case .orderedDescending: return false
        case .orderedSame: return lhs.id < rhs.id
        }
    }
}
