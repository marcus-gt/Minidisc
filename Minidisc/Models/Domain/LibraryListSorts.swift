import Foundation

/// A sort choice for a Library list, shown in `LibrarySortMenu` and stored by raw value.
protocol LibrarySortOption: Hashable, CaseIterable, RawRepresentable, Sendable where RawValue == String, AllCases: RandomAccessCollection {
    var title: LocalizedStringResource { get }
    var systemImage: String { get }
}

/// Library → Genres, and the styles inside a genre.
nonisolated enum GenreListSort: String, LibrarySortOption {
    case mostAlbums
    case name

    var title: LocalizedStringResource {
        switch self {
        case .mostAlbums: "Most Albums"
        case .name: "Name"
        }
    }

    var systemImage: String {
        switch self {
        case .mostAlbums: "square.stack"
        case .name: "textformat"
        }
    }

    /// "Other" stays last in either order: it collects whatever no main genre claims.
    func sorted(_ genres: [MainGenreSummary]) -> [MainGenreSummary] {
        let named = genres.filter { !$0.isOther }
        let other = genres.filter(\.isOther)
        return sorted(named, name: \.name, albumCount: \.albumCount) + other
    }

    func sorted(_ styles: [GenreStyleSummary]) -> [GenreStyleSummary] {
        sorted(styles, name: \.name, albumCount: \.albumCount)
    }

    private func sorted<T>(_ items: [T], name: (T) -> String, albumCount: (T) -> Int) -> [T] {
        items.sorted { lhs, rhs in
            if self == .mostAlbums, albumCount(lhs) != albumCount(rhs) { return albumCount(lhs) > albumCount(rhs) }
            return name(lhs).localizedStandardCompare(name(rhs)) == .orderedAscending
        }
    }
}

/// Library → Labels.
nonisolated enum RecordLabelListSort: String, LibrarySortOption {
    case name
    case mostAlbums

    var title: LocalizedStringResource {
        switch self {
        case .name: "Name"
        case .mostAlbums: "Most Albums"
        }
    }

    var systemImage: String {
        switch self {
        case .name: "textformat"
        case .mostAlbums: "square.stack"
        }
    }

    func sorted(_ labels: [RecordLabelSummary]) -> [RecordLabelSummary] {
        labels.sorted { lhs, rhs in
            if self == .mostAlbums, lhs.albumCount != rhs.albumCount { return lhs.albumCount > rhs.albumCount }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}

/// Library → Favorites: applied to its songs, albums and artists alike.
nonisolated enum FavoritesListSort: String, LibrarySortOption {
    case name
    case recentlyFavorited
    case recentlyPlayed

    var title: LocalizedStringResource {
        switch self {
        case .name: "Name"
        case .recentlyFavorited: "Recently Favorited"
        case .recentlyPlayed: "Recently Played"
        }
    }

    var systemImage: String {
        switch self {
        case .name: "textformat"
        case .recentlyFavorited: "heart"
        case .recentlyPlayed: "play.circle"
        }
    }
}

/// Library → Downloads: applied to its songs, albums and playlists alike.
nonisolated enum DownloadsListSort: String, LibrarySortOption {
    case name
    case recentlyDownloaded

    var title: LocalizedStringResource {
        switch self {
        case .name: "Name"
        case .recentlyDownloaded: "Recently Downloaded"
        }
    }

    var systemImage: String {
        switch self {
        case .name: "textformat"
        case .recentlyDownloaded: "arrow.down.circle"
        }
    }
}
