import SwiftUI
import SwiftSonic

/// Home's Pinned shelf (#44): albums, playlists and artists, mixed in pin order. Drawn from the
/// pins' own snapshots, so it shows at launch and offline without waiting for the server.
struct PinnedShelf: View {
    let items: [PinnedItem]

    var body: some View {
        if !items.isEmpty {
            MinidiscShelf {
                MinidiscCarouselHeader(HomeSection.pinned.title, showsChevron: false)
                    .accessibilityAddTraits(.isHeader)
            } content: {
                ForEach(items) { item in
                    if let destination = Self.destination(for: item) {
                        PinnedShelfCard(item: item, destination: destination)
                    }
                }
            }
            .accessibilityIdentifier(HomeSection.pinned.shelfIdentifier)
        }
    }

    /// Where a pin leads. The detail pages load everything else themselves.
    static func destination(for item: PinnedItem) -> HomeDestination? {
        switch PinnedItemType(rawValue: item.itemType) {
        case .album:
            return .album(AlbumID3(id: item.itemId, name: item.displayName, songCount: 0, duration: 0,
                                   artist: item.displaySubtitle.isEmpty ? nil : item.displaySubtitle,
                                   coverArt: item.coverArtId))
        case .playlist:
            return .playlist(Playlist(id: item.itemId, name: item.displayName, songCount: 0, duration: 0,
                                      coverArt: item.coverArtId))
        case .artist:
            return .artist(ArtistID3(id: item.itemId, name: item.displayName, coverArt: item.coverArtId))
        case nil:
            return nil
        }
    }
}

private struct PinnedShelfCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let item: PinnedItem
    let destination: HomeDestination

    private var side: CGFloat { dynamicTypeSize.isAccessibilitySize ? 260 : 160 }
    private var type: PinnedItemType? { PinnedItemType(rawValue: item.itemType) }

    var body: some View {
        NavigationLink(value: destination) {
            VStack(alignment: .leading, spacing: MinidiscSpacing.xs) {
                cover
                    .frame(width: side, height: side)
                CoverCardMetadata(title: item.displayName, subtitle: subtitle)
            }
            .frame(width: side, alignment: .leading)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let type {
                PinMenuButton(itemType: type, itemId: item.itemId, displayName: item.displayName,
                              displaySubtitle: item.displaySubtitle, coverArtId: item.coverArtId)
            }
        }
        .accessibilityIdentifier("home.pinned.\(item.id)")
    }

    @ViewBuilder
    private var cover: some View {
        switch type {
        case .playlist:
            PlaylistCoverThumbnail(playlistId: item.itemId, serverId: nil,
                                   coverArtId: item.coverArtId ?? item.itemId, title: item.displayName, size: side)
        case .artist:
            CoverArtView(id: item.coverArtId ?? item.itemId, size: Int(side * 2), placeholderSystemImage: "person.fill")
                .minidiscCoverStyle(cornerRadius: MinidiscCornerRadius.standard)
        default:
            CoverArtView(id: item.coverArtId ?? item.itemId, size: Int(side * 2))
                .minidiscCoverStyle(cornerRadius: MinidiscCornerRadius.standard)
        }
    }

    /// The artist for an album; the kind for the others, so a mixed shelf reads at a glance.
    private var subtitle: String? {
        switch type {
        case .album: item.displaySubtitle.isEmpty ? String(localized: "Album") : item.displaySubtitle
        case .playlist: String(localized: "Playlist")
        case .artist: String(localized: "Artist")
        case nil: nil
        }
    }
}
