import SwiftUI
import SwiftSonic

struct AlbumCarouselCollectionView: View {
    @Environment(\.appContainer) private var container
    private let title: Text
    private let albums: [AlbumID3]
    private let continuesRecentlyAdded: Bool
    @State private var pager: RecentlyAddedAlbumPager?
    private let columns = [
        GridItem(.adaptive(minimum: 140, maximum: 180), spacing: MinidiscSpacing.l)
    ]

    /// With `continuesRecentlyAdded`, `albums` is the newest-first page already loaded and scrolling
    /// pages further back through the server's newest albums.
    init(_ title: LocalizedStringResource, albums: [AlbumID3], continuesRecentlyAdded: Bool = false) {
        self.title = Text(title)
        self.albums = albums
        self.continuesRecentlyAdded = continuesRecentlyAdded
    }

    init(verbatim title: String, albums: [AlbumID3]) {
        self.title = Text(verbatim: title)
        self.albums = albums
        continuesRecentlyAdded = false
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: MinidiscSpacing.l) {
                ForEach(container?.visibleAlbums(pager?.albums ?? albums) ?? []) { album in
                    NavigationLink {
                        AlbumDetailView(album: album)
                    } label: {
                        AlbumGridCell(album: album)
                    }
                    .buttonStyle(.plain)
                    // Not `.task`: the page load must survive this cell scrolling away.
                    .onAppear {
                        guard let pager else { return }
                        Task { await pager.loadMoreIfNeeded(after: album) }
                    }
                }
            }
            .padding(MinidiscSpacing.l)
            if pager?.isLoadingMore == true {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, MinidiscSpacing.l)
            }
        }
        .minidiscContentWidth()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Offline, `albums` is filtered to downloads, so its count is not a valid server offset.
            guard continuesRecentlyAdded, pager == nil, container?.serverState.isOnline == true,
                  let service = container?.libraryService else { return }
            pager = RecentlyAddedAlbumPager(libraryService: service, firstPage: albums)
        }
    }
}

struct PlaylistCarouselCollectionView: View {
    @Environment(\.appContainer) private var container
    private let title: Text
    private let playlists: [Playlist]
    private let columns = [
        GridItem(.adaptive(minimum: 140, maximum: 180), spacing: MinidiscSpacing.l)
    ]

    init(_ title: LocalizedStringResource, playlists: [Playlist]) {
        self.title = Text(title)
        self.playlists = playlists
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: MinidiscSpacing.l) {
                ForEach(container?.visiblePlaylists(playlists) ?? []) { playlist in
                    NavigationLink {
                        PlaylistDetailView(
                            playlist: playlist,
                            coverArtId: playlist.coverArt ?? playlist.id
                        )
                    } label: {
                        PlaylistCarouselGridCell(playlist: playlist)
                    }
                    .buttonStyle(.plain)
                    .collectionContextMenu(itemType: .playlist, itemId: playlist.id, displayName: playlist.name,
                                           displaySubtitle: playlist.owner ?? "", coverArtId: playlist.coverArt)
                }
            }
            .padding(MinidiscSpacing.l)
        }
        .minidiscContentWidth()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PlaylistCarouselGridCell: View {
    let playlist: Playlist

    var body: some View {
        VStack(alignment: .leading, spacing: MinidiscSpacing.s) {
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
                subtitle: String(localized: "\(playlist.songCount) tracks")
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
