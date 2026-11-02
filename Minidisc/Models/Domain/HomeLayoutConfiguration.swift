import Foundation

/// A section of the online Home feed that the user can show, hide and reorder in Settings.
/// Raw values are persisted: never rename an existing case.
nonisolated enum HomeSection: String, LayoutSection {
    /// Pinned albums, playlists and artists, mixed in pin order (#44). First, so it also lands
    /// first in a layout saved before it existed.
    case pinned
    case playlists
    case queueBuilder
    /// Off by default on Home; Discover shows it (#65).
    case songPath
    case favoriteSongs
    case favoriteAlbums
    case recentlyPlayed
    case heavyRotation
    /// A daily blend of favourite, dormant and untried artists (#63).
    case artists
    case rediscover
    case recentlyAdded
    case genres

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .pinned: "Pinned"
        case .playlists: "Your Playlists"
        case .queueBuilder: "Queue Builder"
        case .songPath: "Song Path"
        case .favoriteSongs: "Your Favorite Songs"
        case .favoriteAlbums: "Your Favorite Albums"
        case .recentlyPlayed: "Recently Played"
        case .heavyRotation: "In Heavy Rotation"
        case .artists: "Artist Picks"
        case .rediscover: "Rediscover"
        case .recentlyAdded: "Recently Added"
        case .genres: "Genres"
        }
    }

    /// Identifier the section's shelf uses for accessibility and its stored layout. Genre shelves share one.
    var shelfIdentifier: String { "home.\(rawValue)" }

    /// Favorite Songs is a short vertical list, the Queue Builder a set of pickers and the artists
    /// a row of portraits, so none has a carousel / grid choice.
    var supportsLayoutChoice: Bool { ![.favoriteSongs, .queueBuilder, .songPath, .artists].contains(self) }

    static var hiddenByDefault: Set<HomeSection> { [.songPath] }
}

/// Which Home sections are shown, and in what order.
typealias HomeLayoutConfiguration = SectionLayoutConfiguration<HomeSection>

extension SectionLayoutConfiguration where Section == HomeSection {
    static var storageKey: String { "maekster.homeLayout" }
}
