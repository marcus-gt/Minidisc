import Foundation

/// A section of the online Home feed that the user can show, hide and reorder in Settings.
/// Raw values are persisted: never rename an existing case.
nonisolated enum HomeSection: String, CaseIterable, Identifiable, Sendable {
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

/// Which Home sections are shown, and in what order. Persisted as JSON through `@AppStorage`.
///
/// Decoding is forgiving so the stored value survives app updates: unknown sections are dropped and
/// sections added in a later release are appended, visible, at the end.
nonisolated struct HomeLayoutConfiguration: Equatable, Sendable {
    private(set) var order: [HomeSection]
    private(set) var hidden: Set<HomeSection>

    static let `default` = HomeLayoutConfiguration(order: HomeSection.allCases, hidden: [])

    init(order: [HomeSection], hidden: Set<HomeSection>) {
        self.order = Self.normalized(order)
        self.hidden = hidden
    }

    var visibleSections: [HomeSection] { order.filter { !hidden.contains($0) } }

    func isVisible(_ section: HomeSection) -> Bool { !hidden.contains(section) }

    mutating func setVisible(_ visible: Bool, for section: HomeSection) {
        if visible { hidden.remove(section) } else { hidden.insert(section) }
    }

    mutating func setOrder(_ newOrder: [HomeSection]) {
        order = Self.normalized(newOrder)
    }

    /// Removes duplicates and appends any section missing from `order` in its default position order.
    private static func normalized(_ order: [HomeSection]) -> [HomeSection] {
        var seen = Set<HomeSection>()
        let unique = order.filter { seen.insert($0).inserted }
        return unique + HomeSection.allCases.filter { !seen.contains($0) }
    }
}

extension HomeLayoutConfiguration: RawRepresentable {
    /// Encoded through a separate type: a `RawRepresentable` that encodes itself recurses inside `@AppStorage`.
    private struct Stored: Codable {
        var order: [String]
        var hidden: [String]
    }

    init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return nil }
        self.init(
            order: stored.order.compactMap(HomeSection.init(rawValue:)),
            hidden: Set(stored.hidden.compactMap(HomeSection.init(rawValue:)))
        )
    }

    var rawValue: String {
        let stored = Stored(order: order.map(\.rawValue), hidden: hidden.map(\.rawValue).sorted())
        guard let data = try? JSONEncoder().encode(stored) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    static let storageKey = "minidisc.homeLayout"
    /// The playlist shelf shows only pinned playlists, in pin order.
    static let pinnedPlaylistsOnlyKey = "minidisc.homePinnedPlaylistsOnly"
}
