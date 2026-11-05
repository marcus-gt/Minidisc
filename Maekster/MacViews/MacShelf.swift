import SwiftSonic
import SwiftUI

/// A titled row of covers that scrolls sideways, like the Music app's Home: swipe with the trackpad
/// or use the arrows by the title, which move a page at a time. See All opens `seeAll`.
struct MacShelf<Item: Identifiable, Cell: View>: View where Item.ID: Hashable {
    let title: Text
    let items: [Item]
    var seeAll: MacRoute?
    var cellWidth: CGFloat = MacShelfMetrics.coverWidth
    @ViewBuilder let cell: (Item) -> Cell

    @State private var scrolledID: Item.ID?
    @State private var visibleWidth: CGFloat = 0

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: MaeksterSpacing.s) {
                header
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: MaeksterSpacing.l) {
                        ForEach(items) { item in
                            cell(item)
                                .frame(width: cellWidth)
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, MaeksterSpacing.xl)
                }
                .scrollIndicators(.never)
                .scrollPosition(id: $scrolledID, anchor: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { visibleWidth = $0 }
            }
        }
    }

    private var header: some View {
        HStack(spacing: MaeksterSpacing.m) {
            title
                .font(.maeksterShelfTitle)
                .lineLimit(1)
            Spacer(minLength: MaeksterSpacing.s)
            if let seeAll {
                NavigationLink(value: seeAll) {
                    Text("See All")
                }
                .buttonStyle(.link)
            }
            if items.count > pageSize {
                HStack(spacing: MaeksterSpacing.s) {
                    Button { scroll(by: -pageSize) } label: {
                        Label("Previous", systemImage: "chevron.backward")
                    }
                    .disabled(currentIndex == 0)
                    Button { scroll(by: pageSize) } label: {
                        Label("Next", systemImage: "chevron.forward")
                    }
                    .disabled(currentIndex + pageSize >= items.count)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, MaeksterSpacing.xl)
    }

    /// How many covers fit across, so the arrows move by what's on screen.
    private var pageSize: Int {
        max(1, Int((visibleWidth - 2 * MaeksterSpacing.xl + MaeksterSpacing.l) / (cellWidth + MaeksterSpacing.l)))
    }

    private var currentIndex: Int {
        scrolledID.flatMap { id in items.firstIndex { $0.id == id } } ?? 0
    }

    private func scroll(by offset: Int) {
        let target = min(max(currentIndex + offset, 0), max(items.count - pageSize, 0))
        withAnimation(.easeInOut(duration: 0.3)) { scrolledID = items[target].id }
    }
}

enum MacShelfMetrics {
    static let coverWidth: CGFloat = 180
    static let artistWidth: CGFloat = 150
    /// Covers a shelf shows before See All takes over.
    static let limit = 20
}

// MARK: - Cells

/// An album in a shelf: the cover, title and artist; opens the album page.
struct MacAlbumShelfCell: View {
    let album: AlbumID3

    var body: some View {
        NavigationLink(value: MacRoute.album(id: album.id)) {
            AlbumGridCell(album: album, titleLineLimit: 2)
        }
        .buttonStyle(.plain)
    }
}

/// A playlist in a shelf or grid: its cover, name and track count; opens the playlist.
struct MacPlaylistShelfCell: View {
    let playlist: Playlist

    var body: some View {
        NavigationLink(value: MacRoute.playlist(id: playlist.id)) {
            VStack(alignment: .leading, spacing: MaeksterSpacing.s) {
                GeometryReader { geometry in
                    PlaylistCoverThumbnail(
                        playlistId: playlist.id,
                        serverId: nil,
                        coverArtId: playlist.coverArt ?? playlist.id,
                        title: playlist.name,
                        size: geometry.size.width
                    )
                }
                .aspectRatio(1, contentMode: .fit)
                CoverCardMetadata(
                    title: playlist.name,
                    subtitle: String(localized: "\(playlist.songCount) tracks"),
                    titleLineLimit: 2
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .collectionContextMenu(itemType: .playlist, itemId: playlist.id, displayName: playlist.name,
                               displaySubtitle: playlist.owner ?? "", coverArtId: playlist.coverArt)
    }
}

/// An artist in a shelf: a round portrait and the name; opens the artist page.
struct MacArtistShelfCell: View {
    let artist: ArtistID3

    var body: some View {
        NavigationLink(value: MacRoute.artist(id: artist.id, name: artist.name)) {
            ArtistPortraitCell(name: artist.name, size: MacShelfMetrics.artistWidth) {
                CoverArtView(id: artist.coverArt ?? artist.id, size: Int(MacShelfMetrics.artistWidth * 2),
                             placeholderSystemImage: "person.fill")
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            MacArtistMenu(artistId: artist.id, artistName: artist.name)
            PinMenuButton(itemType: .artist, itemId: artist.id, displayName: artist.name,
                          displaySubtitle: "", coverArtId: artist.coverArt)
        }
    }
}

// MARK: - See All pages

/// Every album of a shelf in a grid. Recently Added keeps loading older albums as it scrolls.
struct MacAlbumCollection: View {
    let title: String
    let albums: [AlbumID3]
    let continuesRecentlyAdded: Bool

    @Environment(\.appContainer) private var container
    @State private var pager: RecentlyAddedAlbumPager?

    var body: some View {
        ScrollView {
            LazyVGrid(columns: MacShelfMetrics.gridColumns, spacing: MaeksterSpacing.l) {
                ForEach(container?.visibleAlbums(pager?.albums ?? albums) ?? []) { album in
                    MacAlbumShelfCell(album: album)
                        .frame(maxHeight: .infinity, alignment: .top)
                        // Not `.task`: the page load must survive this cell scrolling away.
                        .onAppear {
                            guard let pager else { return }
                            Task { await pager.loadMoreIfNeeded(after: album) }
                        }
                }
            }
            .padding(MaeksterSpacing.l)
            if pager?.isLoadingMore == true {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, MaeksterSpacing.l)
            }
        }
        .navigationTitle(Text(verbatim: title))
        .task {
            // Offline, `albums` is filtered to downloads, so its count is not a valid server offset.
            guard continuesRecentlyAdded, pager == nil, container?.serverState.isOnline == true,
                  let service = container?.libraryService else { return }
            pager = RecentlyAddedAlbumPager(libraryService: service, firstPage: albums)
        }
    }
}

/// Every playlist of a shelf in a grid.
struct MacPlaylistCollection: View {
    let title: String
    let playlists: [Playlist]

    @Environment(\.appContainer) private var container

    var body: some View {
        ScrollView {
            LazyVGrid(columns: MacShelfMetrics.gridColumns, spacing: MaeksterSpacing.l) {
                ForEach(container?.visiblePlaylists(playlists) ?? []) { playlist in
                    MacPlaylistShelfCell(playlist: playlist)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
            }
            .padding(MaeksterSpacing.l)
        }
        .navigationTitle(Text(verbatim: title))
    }
}

extension MacShelfMetrics {
    /// The same sizes as the library's album grid.
    static let gridColumns = [GridItem(.adaptive(minimum: 180, maximum: 280), spacing: MaeksterSpacing.l)]
}
