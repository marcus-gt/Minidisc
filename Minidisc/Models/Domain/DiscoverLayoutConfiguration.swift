import Foundation

/// A section of the Discover screen that the user can show, hide and reorder in Settings.
/// Raw values are persisted: never rename an existing case. The default order is Discover's original one.
nonisolated enum DiscoverSection: String, LayoutSection {
    case freshReleases
    case stations
    case smartShuffle
    case moods
    case wrapped
    case internetRadio

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .freshReleases: "Fresh Releases"
        case .stations: "Stations for You"
        case .smartShuffle: "Smart Shuffle"
        case .moods: "Moods"
        case .wrapped: "Wrapped"
        case .internetRadio: "Internet Radio"
        }
    }
}

/// Which Discover sections are shown, and in what order.
typealias DiscoverLayoutConfiguration = SectionLayoutConfiguration<DiscoverSection>

extension SectionLayoutConfiguration where Section == DiscoverSection {
    static var storageKey: String { "minidisc.discoverLayout" }
}
