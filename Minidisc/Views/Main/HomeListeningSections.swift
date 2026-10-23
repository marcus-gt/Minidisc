import SwiftUI
import SwiftSonic

struct HomeFavoriteSongsSection: View {
    let songs: [Song]
    @Environment(\.appContainer) private var container
    @Environment(PlaylistAddition.self) private var playlistAddition

    var body: some View {
        if !songs.isEmpty {
            VStack(alignment: .leading, spacing: MinidiscSpacing.s) {
                NavigationLink(value: HomeDestination.libraryFavorites) {
                    HStack {
                        Text("Your Favorite Songs").font(.minidiscShelfTitle)
                        Spacer()
                        Image(systemName: "chevron.right").font(.headline).foregroundStyle(.secondary)
                    }
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                let tracks = songs.map { DisplayableSong(from: $0) }
                ForEach(Array(tracks.prefix(3).enumerated()), id: \.element.id) { index, song in
                    SongRow(song: song, index: index + 1, showCoverArt: true, isFavorite: true, trailingAccessory: .favorite,
                            onAddToPlaylist: playlistAddition.present, onTap: {
                        Task {
                            await container?.toastService.perform {
                                try await container?.playerService.play(tracks: tracks, startIndex: index)
                            }
                        }
                    })
                    // Rows end in a duration: give them the wider track-row inset, headers keep the shelf inset.
                    .padding(.trailing, MinidiscSpacing.trackRowTrailing - MinidiscSpacing.l)
                }
            }
            .padding(.horizontal, MinidiscSpacing.l)
            .accessibilityIdentifier("home.favoriteSongs")
        }
    }
}

struct HomeAlbumSection: View {
    private enum Title {
        case localized(LocalizedStringResource)
        case verbatim(String)
    }

    private let title: Title
    let albums: [AlbumID3]
    let identifier: String
    /// "See all" keeps loading older albums from the server instead of stopping at `albums`.
    private let continuesRecentlyAdded: Bool
    @AppStorage private var layout: HomeShelfLayout

    /// The layout is stored per shelf, keyed on `identifier`.
    init(title: LocalizedStringResource, albums: [AlbumID3], identifier: String, continuesRecentlyAdded: Bool = false) {
        self.init(title: .localized(title), albums: albums, identifier: identifier,
                  continuesRecentlyAdded: continuesRecentlyAdded)
    }

    /// For server-provided titles such as genre names, which must not go through the String Catalog.
    /// `layoutIdentifier` lets several shelves share one stored layout (all genre shelves do).
    init(verbatim title: String, albums: [AlbumID3], identifier: String, layoutIdentifier: String? = nil) {
        self.init(title: .verbatim(title), albums: albums, identifier: identifier, layoutIdentifier: layoutIdentifier)
    }

    private init(title: Title, albums: [AlbumID3], identifier: String, layoutIdentifier: String? = nil,
                 continuesRecentlyAdded: Bool = false) {
        self.title = title
        self.albums = albums
        self.identifier = identifier
        self.continuesRecentlyAdded = continuesRecentlyAdded
        _layout = AppStorage(wrappedValue: .carousel, HomeShelfLayout.storageKey(for: layoutIdentifier ?? identifier))
    }

    var body: some View {
        if !albums.isEmpty {
            switch layout {
            case .carousel:
                MinidiscShelf {
                    header
                } content: {
                    ForEach(Array(albums.prefix(MinidiscCarouselMetrics.previewLimit))) { album in
                        AlbumShelfCard(album: album)
                    }
                }
                .accessibilityIdentifier(identifier)
            case .grid:
                VStack(alignment: .leading, spacing: MinidiscSpacing.s) {
                    header
                    HomeShelfGrid(albums.prefix(HomeShelfLayout.gridLimit)) { album in
                        HomeAlbumGridTile(album: album)
                    }
                }
                .accessibilityIdentifier(identifier)
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        switch title {
        case .localized(let title):
            MinidiscCarouselHeaderLink(title, itemCount: albums.count, visibleLimit: layout.visibleLimit) {
                AlbumCarouselCollectionView(title, albums: albums, continuesRecentlyAdded: continuesRecentlyAdded)
            }
        case .verbatim(let title):
            MinidiscCarouselHeaderLink(verbatim: title, itemCount: albums.count, visibleLimit: layout.visibleLimit) {
                AlbumCarouselCollectionView(verbatim: title, albums: albums)
            }
        }
    }
}

// MARK: - Shelf layout (carousel / grid)

/// How a Home shelf lays out its items, chosen in Settings → Application → Home Screen.
/// Persisted by raw value, one key per shelf.
nonisolated enum HomeShelfLayout: String {
    case carousel
    case grid

    /// Three rows of two; the header link opens the full list.
    static let gridLimit = 6
    /// Cover side for compact grid tiles.
    static let gridTileCoverSide: CGFloat = 64

    /// How many items the shelf shows, so the header offers "see all" exactly when some are hidden.
    @MainActor var visibleLimit: Int {
        switch self {
        case .carousel: MinidiscCarouselMetrics.previewLimit
        case .grid: Self.gridLimit
        }
    }

    static func storageKey(for identifier: String) -> String {
        "minidisc.homeShelfLayout.\(identifier)"
    }
}

/// Two flexible columns of compact tiles, inset to the shelf's horizontal padding.
struct HomeShelfGrid<Items: RandomAccessCollection, Tile: View>: View where Items.Element: Identifiable {
    private let items: Items
    private let tile: (Items.Element) -> Tile

    private static var columns: [GridItem] {
        [GridItem(.flexible(), spacing: MinidiscSpacing.s), GridItem(.flexible(), spacing: MinidiscSpacing.s)]
    }

    init(_ items: Items, @ViewBuilder tile: @escaping (Items.Element) -> Tile) {
        self.items = items
        self.tile = tile
    }

    var body: some View {
        LazyVGrid(columns: Self.columns, spacing: MinidiscSpacing.s) {
            ForEach(items) { item in
                tile(item)
            }
        }
        .padding(.horizontal, MinidiscSpacing.l)
    }
}

/// Shared chrome for grid tiles: cover on the leading edge, text beside it, on a filled rounded card.
struct HomeGridTileChrome<Cover: View, Detail: View>: View {
    @ViewBuilder let cover: () -> Cover
    @ViewBuilder let detail: () -> Detail

    var body: some View {
        HStack(spacing: MinidiscSpacing.m) {
            cover()
            detail()
            Spacer(minLength: 0)
        }
        .padding(.trailing, MinidiscSpacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: MinidiscCornerRadius.large, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: MinidiscCornerRadius.large, style: .continuous))
    }
}

struct HomeAlbumGridTile: View {
    let album: AlbumID3

    var body: some View {
        NavigationLink(value: HomeDestination.album(album)) {
            HomeGridTileChrome {
                CoverArtView(id: album.coverArt ?? album.id, size: Int(HomeShelfLayout.gridTileCoverSide * 2))
                    .frame(width: HomeShelfLayout.gridTileCoverSide, height: HomeShelfLayout.gridTileCoverSide)
                    .clipShape(RoundedRectangle(cornerRadius: MinidiscCornerRadius.large, style: .continuous))
            } detail: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(album.name)
                        .font(.minidiscCellTitle)
                        .foregroundStyle(.primary)
                        .lineLimit(album.artist == nil ? 2 : 1)
                    if let artist = album.artist {
                        Text(artist)
                            .font(.minidiscCaption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}
