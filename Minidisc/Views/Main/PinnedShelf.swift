import SwiftUI
import SwiftSonic

/// Home's Pinned shelf (#44): albums, playlists and artists, mixed in pin order. Drawn from the
/// pins' own snapshots, so it shows at launch and offline without waiting for the server.
struct PinnedShelf: View {
    let items: [PinnedItem]
    @State private var renameRequest: PlaylistRenameRequest?
    @AppStorage(HomeShelfLayout.storageKey(for: HomeSection.pinned.shelfIdentifier)) private var layout: HomeShelfLayout = .carousel

    /// Every pin shows in either layout: pins are a short, hand-picked list.
    var body: some View {
        if !items.isEmpty {
            switch layout {
            case .carousel:
                MinidiscShelf {
                    header
                } content: {
                    ForEach(items) { item in
                        if let destination = Self.destination(for: item) {
                            PinnedShelfCard(item: item, destination: destination, onRename: rename)
                        }
                    }
                }
                .accessibilityIdentifier(HomeSection.pinned.shelfIdentifier)
                .playlistRenameAlert($renameRequest)
            case .grid:
                VStack(alignment: .leading, spacing: MinidiscSpacing.s) {
                    header
                    HomeShelfGrid(items) { item in
                        if let destination = Self.destination(for: item) {
                            PinnedGridTile(item: item, destination: destination, onRename: rename)
                        }
                    }
                }
                .accessibilityIdentifier(HomeSection.pinned.shelfIdentifier)
                .playlistRenameAlert($renameRequest)
            }
        }
    }

    private func rename(_ item: PinnedItem) {
        renameRequest = PlaylistRenameRequest(playlistId: item.itemId, currentName: item.displayName, coverArtId: item.coverArtId)
    }

    private var header: some View {
        MinidiscCarouselHeader(HomeSection.pinned.title, showsChevron: false)
            .accessibilityAddTraits(.isHeader)
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

/// A name as shown on a pin: a spaced dash is tied to the word before it with a no-break space, so a
/// wrapped name always reads "Techno –" / "Chill". Otherwise iOS, avoiding a lone last word, moves the
/// dash down for short names only, and "Techno" / "– Chill" sits next to "Discover –" / "this month".
/// Display only: the stored name keeps whatever was typed.
nonisolated func pinnedDisplayName(_ name: String) -> String {
    var result = name
    for dash in [" – ", " — ", " - "] {
        result = result.replacingOccurrences(of: dash, with: "\u{00A0}" + dash.dropFirst())
    }
    return result
}

/// What a pin's card says under its name: the artist for an album, the kind for the others, so a
/// mixed shelf reads at a glance.
private func pinnedSubtitle(_ item: PinnedItem) -> String? {
    switch PinnedItemType(rawValue: item.itemType) {
    case .album: item.displaySubtitle.isEmpty ? String(localized: "Album") : item.displaySubtitle
    case .playlist: String(localized: "Playlist")
    case .artist: String(localized: "Artist")
    case nil: nil
    }
}

/// A pin's long-press menu: Rename for a playlist the listener named, and Unpin.
private struct PinnedItemMenu: View {
    let item: PinnedItem
    let onRename: (PinnedItem) -> Void
    @Environment(\.appContainer) private var container

    var body: some View {
        if item.itemType == PinnedItemType.playlist.rawValue, container?.serverState.isOnline == true,
           PlaylistRenamer.canRename(playlistName: item.displayName) {
            Button("Rename", systemImage: "character.cursor.ibeam") { onRename(item) }
        }
        if let type = PinnedItemType(rawValue: item.itemType) {
            PinMenuButton(itemType: type, itemId: item.itemId, displayName: item.displayName,
                          displaySubtitle: item.displaySubtitle, coverArtId: item.coverArtId)
        }
    }
}

/// A pin's cover at any size: playlists draw their generated cover, artists a person placeholder.
private struct PinnedCover: View {
    let item: PinnedItem
    let side: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        switch PinnedItemType(rawValue: item.itemType) {
        case .playlist:
            PlaylistCoverThumbnail(playlistId: item.itemId, serverId: nil,
                                   coverArtId: item.coverArtId ?? item.itemId, title: item.displayName, size: side)
        case .artist:
            CoverArtView(id: item.coverArtId ?? item.itemId, size: Int(side * 2), placeholderSystemImage: "person.fill")
                .minidiscCoverStyle(cornerRadius: cornerRadius)
        default:
            CoverArtView(id: item.coverArtId ?? item.itemId, size: Int(side * 2))
                .minidiscCoverStyle(cornerRadius: cornerRadius)
        }
    }
}

private struct PinnedGridTile: View {
    let item: PinnedItem
    let destination: HomeDestination
    let onRename: (PinnedItem) -> Void

    var body: some View {
        NavigationLink(value: destination) {
            HomeGridTileChrome {
                PinnedCover(item: item, side: HomeShelfLayout.gridTileCoverSide, cornerRadius: MinidiscCornerRadius.large)
                    .frame(width: HomeShelfLayout.gridTileCoverSide, height: HomeShelfLayout.gridTileCoverSide)
            } detail: {
                VStack(alignment: .leading, spacing: 2) {
                    // Two lines: pinned names like "Techno - Peak Time" are often longer than half a row.
                    Text(verbatim: pinnedDisplayName(item.displayName))
                        .font(.minidiscCellTitle)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle = pinnedSubtitle(item) {
                        Text(subtitle)
                            .font(.minidiscCaption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu { PinnedItemMenu(item: item, onRename: onRename) }
        .accessibilityIdentifier("home.pinned.\(item.id)")
    }
}

private struct PinnedShelfCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let item: PinnedItem
    let destination: HomeDestination
    let onRename: (PinnedItem) -> Void

    private var side: CGFloat { dynamicTypeSize.isAccessibilitySize ? 260 : 160 }

    var body: some View {
        NavigationLink(value: destination) {
            VStack(alignment: .leading, spacing: MinidiscSpacing.xs) {
                PinnedCover(item: item, side: side, cornerRadius: MinidiscCornerRadius.standard)
                    .frame(width: side, height: side)
                CoverCardMetadata(title: pinnedDisplayName(item.displayName), subtitle: pinnedSubtitle(item))
            }
            .frame(width: side, alignment: .leading)
        }
        .buttonStyle(.plain)
        .contextMenu { PinnedItemMenu(item: item, onRename: onRename) }
        .accessibilityIdentifier("home.pinned.\(item.id)")
    }
}
