import SwiftUI
import SwiftSonic

struct LibraryView: View {
    @Environment(\.appContainer) private var container
    @Namespace private var playlistZoomNamespace
    @Namespace private var detailZoomNamespace
    @Environment(DominantColorExtractor.self) private var colorExtractor
    @Environment(ArtworkImageCache.self) private var artworkImageCache

    private var isOnline: Bool { container?.serverState.isOnline == true }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MinidiscSpacing.xl) {
                if !isOnline && container?.offlineLibrary.snapshot.songs.isEmpty != false
                    && container?.localMusic.snapshot.tracks.contains(where: \.isAvailable) != true {
                    OfflineBrowsingEmptyView()
                }
                librarySection
            }
            .padding(.horizontal, MinidiscSpacing.l)
            .padding(.top, MinidiscSpacing.m)
            .padding(.bottom, MinidiscSpacing.xl)
        }
        .navigationTitle("Library")
        .toolbarTitleDisplayMode(.inlineLarge)
        .navigationDestination(for: HomeDestination.self) { destination in
            switch destination {
            case .libraryAlbums:
                AlbumsListView()
            case .libraryArtists:
                ArtistListView()
            case .librarySongs:
                SongsListView()
            case .libraryPlaylists:
                PlaylistListView(zoomNamespace: playlistZoomNamespace)
            case .libraryFavorites:
                FavoritesView()
            case .libraryDownloads:
                DownloadedView()
            case .libraryRecordLabels:
                RecordLabelListView()
            case .album(let album):
                AlbumDetailView(
                    album: album,
                    zoomSourceId: album.id,
                    zoomNamespace: detailZoomNamespace,
                    coverArtId: album.coverArt,
                    initialDominantColor: colorExtractor.dominantColor(for: album.coverArt ?? album.id, image: nil),
                    initialCoverImage: artworkImageCache.cachedImage(for: album.coverArt ?? album.id)
                )
            case .artist(let artist):
                ArtistDetailView(artist: artist)
            case .playlist(let playlist):
                PlaylistDetailView(
                    playlist: playlist,
                    coverArtId: playlist.coverArt ?? playlist.id,
                    initialCoverImage: artworkImageCache.cachedImage(for: playlist.coverArt ?? playlist.id),
                    zoomSourceId: playlist.id,
                    zoomNamespace: playlistZoomNamespace
                )
            case .downloadedAlbum(let display):
                AlbumDetailView(albumId: display.albumId, albumName: display.name, coverArtId: display.coverArtId, mode: .downloadedOnly)
            case .albumById(let id, let name, _, let coverArtId):
                AlbumDetailView(
                    albumId: id,
                    albumName: name,
                    zoomSourceId: id,
                    zoomNamespace: detailZoomNamespace,
                    coverArtId: coverArtId,
                    initialCoverImage: artworkImageCache.cachedImage(for: coverArtId ?? id)
                )
            case .playlistById(let id, let name, let coverArtId):
                PlaylistDetailView(
                    playlistId: id,
                    name: name,
                    coverArtId: coverArtId,
                    initialCoverImage: artworkImageCache.cachedImage(for: coverArtId ?? id),
                    zoomSourceId: id,
                    zoomNamespace: detailZoomNamespace
                )
            case .artistById(let id, let name, let coverArtId):
                ArtistDetailView(artist: ArtistID3(id: id, name: name, coverArt: coverArtId))
            case .artistBestOf(let id, let name, let coverArtId):
                ArtistBestOfView(artistId: id, artistName: name, coverArtId: coverArtId)
            case .recentlyAdded(let coverArtId):
                RecentlyAddedView(coverArtId: coverArtId)
            case .offlineArtist(let artist):
                OfflineArtistAlbumsView(artist: artist)
            case .offlineAlbum(let album):
                AlbumDetailView(albumId: album.albumId, albumName: album.albumName, coverArtId: album.coverArtId)
            }
        }
    }

    // MARK: - Library section

    private var librarySection: some View {
        let local = container?.offlineLibrary.snapshot ?? OfflineBrowsingSnapshot()
        return VStack(alignment: .leading, spacing: MinidiscSpacing.s) {
            VStack(spacing: 0) {
                if container?.localMusic.snapshot.folders.isEmpty == false {
                    NavigationLink { LocalMusicView() } label: {
                        HomeLibraryRowLabel(title: "Local Files", systemImage: "folder.fill", tableName: "LocalMusic")
                    }
                    .buttonStyle(.plain)
                    Divider().padding(.leading, 52)
                }
                if isOnline || (!local.playlists.isEmpty) {
                    NavigationLink(value: HomeDestination.libraryPlaylists) {
                        HomeLibraryRowLabel(title: "Playlists", systemImage: "music.note.list")
                    }
                    .buttonStyle(.plain)
                    Divider().padding(.leading, 52)
                }
                if isOnline || (!local.albums.isEmpty) {
                    NavigationLink(value: HomeDestination.libraryAlbums) {
                        HomeLibraryRowLabel(title: "Albums", systemImage: "square.stack")
                    }
                    .buttonStyle(.plain)
                    Divider().padding(.leading, 52)
                }
                if isOnline || (!local.artists.isEmpty) {
                    NavigationLink(value: HomeDestination.libraryArtists) {
                        HomeLibraryRowLabel(title: "Artists", systemImage: "music.mic")
                    }
                    .buttonStyle(.plain)
                    Divider().padding(.leading, 52)
                }
                if isOnline || (!local.songs.isEmpty) {
                    NavigationLink(value: HomeDestination.librarySongs) {
                        HomeLibraryRowLabel(title: "Songs", systemImage: "music.note")
                    }
                    .buttonStyle(.plain)
                    Divider().padding(.leading, 52)
                }
                // Labels come from the indexed albums, which offline browsing does not filter to downloads.
                if isOnline {
                    NavigationLink(value: HomeDestination.libraryRecordLabels) {
                        HomeLibraryRowLabel(title: "Labels", systemImage: "building.2")
                    }
                    .buttonStyle(.plain)
                    Divider().padding(.leading, 52)
                }
                if isOnline || (!local.favorites.songs.isEmpty || !local.favorites.albums.isEmpty || !local.favorites.artists.isEmpty) {
                    NavigationLink(value: HomeDestination.libraryFavorites) {
                        HomeLibraryRowLabel(title: "Favorites", systemImage: "heart.fill")
                    }
                    .buttonStyle(.plain)
                    Divider().padding(.leading, 52)
                }
                if isOnline || (local.songs.contains(where: \.isDownloaded)) {
                    NavigationLink(value: HomeDestination.libraryDownloads) {
                        HomeLibraryRowLabel(title: "Downloads", systemImage: "arrow.down.circle.fill")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - HomeLibraryRowLabel

private struct HomeLibraryRowLabel: View {
    let title: LocalizedStringKey
    let systemImage: String
    var tableName: String? = nil

    var body: some View {
        HStack(spacing: MinidiscSpacing.m) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.minidiscAccent)
                    .frame(width: 30, height: 30)
                Image(systemName: systemImage)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
            }
            Text(title, tableName: tableName)
                .font(.minidiscCellTitle)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, MinidiscSpacing.m)
        .padding(.vertical, MinidiscSpacing.m)
        .contentShape(Rectangle())
    }
}
