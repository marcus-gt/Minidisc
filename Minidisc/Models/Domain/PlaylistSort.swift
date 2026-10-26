import Foundation

/// Local ordering for a playlist's track list. Release date is absent on purpose: `DisplayableSong` carries no year.
nonisolated enum PlaylistSortOrder: String, CaseIterable, Identifiable, Sendable {
    case playlistOrder
    case title
    case artist
    case album

    var id: String { rawValue }
}

nonisolated enum PlaylistSortDirection: String, CaseIterable, Identifiable, Sendable {
    case ascending
    case descending

    var id: String { rawValue }
}

nonisolated enum PlaylistSort {
    /// The stored positions of `songs` in display order. Rows map back through these positions, so
    /// removing a track hits the right entry even when the list is reversed or a song appears twice.
    /// Ties keep the playlist order in both directions; songs without the sorted field come last.
    static func displayOrder(
        of songs: [DisplayableSong],
        by order: PlaylistSortOrder,
        direction: PlaylistSortDirection
    ) -> [Int] {
        let positions = Array(songs.indices)
        guard order != .playlistOrder else {
            return direction == .ascending ? positions : positions.reversed()
        }
        let keys = songs.map { key(for: $0, order: order) }
        return positions.sorted { lhs, rhs in
            switch (keys[lhs], keys[rhs]) {
            case (nil, nil): return lhs < rhs
            case (nil, _): return false
            case (_, nil): return true
            case let (left?, right?):
                switch left.localizedStandardCompare(right) {
                case .orderedSame: return lhs < rhs
                case .orderedAscending: return direction == .ascending
                case .orderedDescending: return direction == .descending
                }
            }
        }
    }

    private static func key(for song: DisplayableSong, order: PlaylistSortOrder) -> String? {
        let raw: String? = switch order {
        case .playlistOrder: nil
        case .title: song.title
        case .artist: song.artist
        case .album: song.albumName
        }
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
