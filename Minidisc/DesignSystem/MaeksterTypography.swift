import SwiftUI

// MARK: - Typography tokens
// Plain SF Pro throughout; hierarchy comes from size and weight, not from a second design.
// All tokens are built on text styles so they follow Dynamic Type.

extension Font {
    // MARK: Headings

    /// Artist name over the hero image.
    static let maeksterHeroTitle = Font.system(.largeTitle, weight: .bold)

    /// Track title in the full player.
    static let maeksterPlayerTitle = Font.system(.title2, weight: .bold)

    /// Artist line under the player title.
    static let maeksterPlayerSubtitle = Font.system(.title3, weight: .regular)

    /// Album line under the player artist.
    static let maeksterPlayerTertiary = Font.system(.callout, weight: .regular)

    /// Album or playlist name in a detail header.
    static let maeksterDetailTitle = Font.system(.title2, weight: .bold)

    /// Artist or owner under a detail title.
    static let maeksterDetailSubtitle = Font.system(.body, weight: .medium)

    /// Section headers in scroll views (disc headers, compact titles).
    static let maeksterSectionTitle = Font.system(.headline, weight: .semibold)

    /// Carousel / shelf headers ("More from…", "Similar Artists").
    static let maeksterShelfTitle = Font.system(.title3, weight: .bold)

    // MARK: Body & cells

    static let maeksterBody = Font.system(.body, weight: .regular)

    static let maeksterCellTitle = Font.system(.callout, weight: .semibold)

    static let maeksterCellSubtitle = Font.system(.subheadline, weight: .regular)

    /// Track titles in album and playlist lists.
    static let maeksterTrackTitle = Font.system(.body, weight: .regular)

    /// Track numbers and durations: tabular so columns line up.
    static let maeksterTrackNumber = Font.system(.subheadline, weight: .regular).monospacedDigit()

    /// Release metadata (year · songs · duration) and player format line.
    static let maeksterMetadata = Font.system(.footnote, weight: .regular).monospacedDigit()

    /// Format badges (FLAC, MP3) and other short all-caps labels.
    static let maeksterBadge = Font.system(.caption2, weight: .bold)

    static let maeksterCaption = Font.system(.caption, weight: .regular)

    static let maeksterCaption2 = Font.system(.caption2, weight: .regular)

    // MARK: Lyrics

    static let maeksterLyricsLine = Font.system(.title, weight: .bold)
}
