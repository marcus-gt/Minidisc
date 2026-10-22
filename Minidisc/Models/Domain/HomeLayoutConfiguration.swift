import Foundation

/// A section of the online Home feed that the user can show, hide and reorder in Settings.
/// Raw values are persisted: never rename an existing case.
nonisolated enum HomeSection: String, LayoutSection {
    case playlists
    case favoriteSongs
    case favoriteAlbums
    case recentlyPlayed
    case heavyRotation
    case rediscover
    case relevantAdditions
    case recentlyAdded
    case genres

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .playlists: "Your Playlists"
        case .favoriteSongs: "Your Favorite Songs"
        case .favoriteAlbums: "Your Favorite Albums"
        case .recentlyPlayed: "Recently Played"
        case .heavyRotation: "In Heavy Rotation"
        case .rediscover: "Rediscover"
        case .relevantAdditions: "Recently Added from Your Artists"
        case .recentlyAdded: "Recently Added"
        case .genres: "Genres"
        }
    }

    /// Identifier the section's shelf uses for accessibility and its stored layout. Genre shelves share one.
    var shelfIdentifier: String { "home.\(rawValue)" }

    /// Favorite Songs is a short vertical list, so it has no carousel / grid choice.
    var supportsLayoutChoice: Bool { self != .favoriteSongs }
}

/// Which Home sections are shown, and in what order.
typealias HomeLayoutConfiguration = SectionLayoutConfiguration<HomeSection>

extension SectionLayoutConfiguration where Section == HomeSection {
    static var storageKey: String { "minidisc.homeLayout" }
    /// The playlist shelf shows only pinned playlists, in pin order.
    static var pinnedPlaylistsOnlyKey: String { "minidisc.homePinnedPlaylistsOnly" }
}
