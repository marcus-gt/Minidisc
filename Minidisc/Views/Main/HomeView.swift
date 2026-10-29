import SwiftUI
import SwiftData
import SwiftSonic

struct HomeView: View {
    @Environment(\.appContainer) private var container
    @Environment(ArtworkImageCache.self) private var artworkImageCache
    @State private var viewModel: HomeFeedViewModel?
    @State private var loadedServerID: UUID?
    @AppStorage(HomeShelfLayout.storageKey(for: HomeSection.playlists.shelfIdentifier)) private var playlistShelfLayout: HomeShelfLayout = .carousel
    @AppStorage(HomeLayoutConfiguration.storageKey) private var homeLayout: HomeLayoutConfiguration = .default
    @Query(sort: \PinnedItem.sortOrder) private var pinnedItems: [PinnedItem]

    private struct LoadIdentity: Hashable { let serverID: UUID?; let online: Bool }
    @Namespace private var homeZoomNamespace

    private var isOnline: Bool { container?.serverState.isOnline == true }

    /// Everything pinned on the active server, in pin order.
    private var pinnedOnServer: [PinnedItem] {
        let serverID = container?.serverState.activeServer?.id
        return pinnedItems.filter { $0.serverId == serverID }
    }

    /// `viewModel` is for Previews: a supplied model is loaded instead of one built from the container.
    init(viewModel: HomeFeedViewModel? = nil) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        Group {
            if let vm = viewModel {
                content(vm)
            } else {
                LoadingStateView()
            }
        }
        .navigationTitle("Home")
        .toolbarTitleDisplayMode(.inlineLarge)
        .minidiscSettingsToolbar()
        .navigationDestination(for: HomeDestination.self) { destination in
            resolve(destination)
        }
        .task(id: LoadIdentity(serverID: container?.serverState.activeServer?.id, online: isOnline)) {
            guard let c = container, let serverID = c.serverState.activeServer?.id else { return }
            // A model built here always records its server, so a nil loadedServerID with a model present
            // means it was injected (Previews) and is kept. A server switch still rebuilds a built model.
            if viewModel == nil || (loadedServerID != nil && loadedServerID != serverID) {
                loadedServerID = serverID
                let pinService = c.pinService
                viewModel = HomeFeedViewModel(libraryService: c.libraryService, cache: HomeFeedCache.shared, serverID: serverID,
                                              diagnostics: c.playbackDiagnostics,
                                              pinnedPlaylistIDs: { Set(pinService.pinnedItemIds(itemType: .playlist, serverId: serverID)) })
            }
            await viewModel?.load(isOnline: isOnline)
        }
        .onReceive(NotificationCenter.default.publisher(for: .minidiscPlaylistsChanged)) { _ in
            Task { await viewModel?.load(isOnline: isOnline, preserveLayout: true) }
        }
        // Pins keep a snapshot of the name; a playlist renamed elsewhere catches up here.
        .onChange(of: viewModel?.topPicks.map { "\($0.id)\u{1F}\($0.name)" } ?? []) { _, _ in
            guard let c = container, let serverID = c.serverState.activeServer?.id, let picks = viewModel?.topPicks,
                  !picks.isEmpty else { return }
            c.pinService.reconcilePinnedPlaylists(with: picks, serverId: serverID)
        }

    }

    // MARK: - Feed

    @ViewBuilder
    private func content(_ vm: HomeFeedViewModel) -> some View {
        let picks = container?.visiblePlaylists(vm.topPicks) ?? []
        let favorites = isOnline ? vm.favorites : container?.offlineLibrary.snapshot.favorites ?? HomeFavorites()
        let genres = vm.genreShelves.compactMap { shelf -> HomeFeedViewModel.GenreShelf? in
            let albums = container?.visibleAlbums(shelf.albums) ?? []
            return albums.isEmpty ? nil : .init(name: shelf.name, albums: albums)
        }
        if !vm.isLoading, vm.isEmpty, !isOnline {
            ScrollView {
                VStack(alignment: .leading, spacing: MinidiscSpacing.section) {
                    OfflineHomeInfo()
                    HomeFavoriteSongsSection(songs: favorites.songs)
                    HomeAlbumSection(title: "Albums", albums: container?.offlineLibrary.snapshot.albums ?? [], identifier: "home.offlineAlbums")
                }
            }
        } else if let error = vm.error, vm.isEmpty, !vm.isLoading {
            EmptyStateView(
                systemImage: "exclamationmark.triangle",
                title: "Unable to Load",
                subtitle: LocalizedStringKey(error.displayMessage),
                action: .init(label: "Retry") { Task { await vm.load() } }
            )
        } else if vm.isEmpty && !vm.isLoading {
            EmptyStateView(
                systemImage: "music.note.list",
                title: "No music yet",
                subtitle: "Add some music to your server to get started"
            )
        } else {
            ScrollView {
                // A stable VStack height avoids lazy-height estimates leaving the refresh inset open.
                VStack(alignment: .leading, spacing: MinidiscSpacing.section) {
                    if !isOnline {
                        OfflineHomeInfo()
                    } else if vm.hasPartialFailure {
                        HStack(alignment: .center) {
                            Text("Some sections could not be refreshed. Your saved library is still available.")
                                .font(.subheadline)
                            Spacer()
                            Button("Retry") { Task { await vm.load(isOnline: isOnline, preserveLayout: true) } }
                                .frame(minHeight: 44)
                        }
                        .padding(.horizontal, MinidiscSpacing.l)
                    }
                    ForEach(homeLayout.visibleSections) { section in
                        feedSection(section, vm: vm, picks: picks, favorites: favorites, genres: genres)
                    }
                }
                .padding(.top, MinidiscSpacing.m)
                .padding(.bottom, MinidiscSpacing.xl)
            }
            .minidiscSongSwipeContainer()
            .refreshable { await vm.load(isOnline: isOnline, preserveLayout: true) }
        }
    }

    /// One section of the feed, in the order and visibility chosen in Settings → Application → Home Screen.
    @ViewBuilder
    private func feedSection(
        _ section: HomeSection,
        vm: HomeFeedViewModel,
        picks: [Playlist],
        favorites: HomeFavorites,
        genres: [HomeFeedViewModel.GenreShelf]
    ) -> some View {
        switch section {
        case .pinned:
            PinnedShelf(items: pinnedOnServer)
        case .playlists:
            if isOnline, picks.isEmpty, vm.pendingSections.contains(.playlists) {
                HomeShelfPlaceholder(title: section.title, side: 250)
            }
            if !picks.isEmpty {
                playlistShelf(picks)
            }
        case .queueBuilder:
            if isOnline, let queueBuilder = container?.queueBuilderViewModel() {
                QueueBuilderCard(viewModel: queueBuilder)
            }
        case .favoriteSongs:
            HomeFavoriteSongsSection(songs: favorites.songs)
        case .favoriteAlbums:
            albumSection(section, albums: favorites.albums)
        case .recentlyPlayed:
            if isOnline, vm.recentlyPlayed.isEmpty, vm.pendingSections.contains(.history) {
                HomeShelfPlaceholder(title: section.title, side: 160)
            }
            albumSection(section, albums: container?.visibleAlbums(vm.recentlyPlayed) ?? [])
        case .heavyRotation:
            albumSection(section, albums: container?.visibleAlbums(vm.heavyRotation) ?? [])
        case .rediscover:
            albumSection(section, albums: container?.visibleAlbums(vm.rediscovery) ?? [])
        case .relevantAdditions:
            albumSection(section, albums: container?.visibleAlbums(vm.relevantAdditions) ?? [])
        case .recentlyAdded:
            if isOnline, vm.recentlyAdded.isEmpty, vm.pendingSections.contains(.recent) {
                HomeShelfPlaceholder(title: section.title, side: 160)
            }
            // The full newest list, even albums also shown under "Recently Added from Your Artists".
            HomeAlbumSection(title: section.title, albums: container?.visibleAlbums(vm.recentlyAdded) ?? [],
                             identifier: section.shelfIdentifier, continuesRecentlyAdded: true)
        case .genres:
            ForEach(genres) { shelf in
                HomeAlbumSection(verbatim: shelf.name, albums: shelf.albums, identifier: "home.genre.\(shelf.name)",
                                 layoutIdentifier: section.shelfIdentifier)
            }
        }
    }

    private func albumSection(_ section: HomeSection, albums: [AlbumID3]) -> some View {
        HomeAlbumSection(title: section.title, albums: albums, identifier: section.shelfIdentifier)
    }

    // MARK: - Playlist shelf

    @ViewBuilder
    private func playlistShelf(_ shown: [Playlist]) -> some View {
        let title: LocalizedStringResource = "Your Playlists"
        switch playlistShelfLayout {
        case .carousel:
            MinidiscShelf {
                playlistShelfHeader(title, shown: shown)
            } content: {
                ForEach(Array(shown.prefix(MinidiscCarouselMetrics.previewLimit))) { playlist in
                    TopPickCard(playlist: playlist, namespace: homeZoomNamespace)
                }
            }
            .accessibilityIdentifier("home.playlists")
        case .grid:
            VStack(alignment: .leading, spacing: MinidiscSpacing.s) {
                playlistShelfHeader(title, shown: shown)
                HomeShelfGrid(shown.prefix(HomeShelfLayout.gridLimit)) { playlist in
                    PlaylistGridTile(playlist: playlist, namespace: homeZoomNamespace)
                }
            }
            .accessibilityIdentifier("home.playlists")
        }
    }

    private func playlistShelfHeader(_ title: LocalizedStringResource, shown: [Playlist]) -> some View {
        MinidiscCarouselHeaderLink(title, itemCount: shown.count, visibleLimit: playlistShelfLayout.visibleLimit) {
            PlaylistCarouselCollectionView(title, playlists: shown)
        }
    }

    // MARK: - Destination resolver

    @ViewBuilder
    private func resolve(_ destination: HomeDestination) -> some View {
        switch destination {
        case .libraryAlbums:
            AlbumsListView()
        case .libraryArtists:
            ArtistListView()
        case .librarySongs:
            SongsListView()
        case .libraryPlaylists:
            PlaylistListView()
        case .libraryFavorites:
            FavoritesView()
        case .libraryDownloads:
            DownloadedView()
        case .libraryRecordLabels:
            RecordLabelListView()
        case .libraryGenres:
            GenreListView()
        case .album(let album):
            AlbumDetailView(album: album)
        case .artist(let artist):
            ArtistDetailView(artist: artist)
        case .playlist(let playlist):
            PlaylistDetailView(
                playlist: playlist,
                coverArtId: playlist.coverArt ?? playlist.id,
                initialCoverImage: artworkImageCache.cachedImage(for: playlist.coverArt ?? playlist.id),
                zoomSourceId: playlist.id,
                zoomNamespace: homeZoomNamespace
            )
        case .downloadedAlbum(let display):
            AlbumDetailView(albumId: display.albumId, albumName: display.name, coverArtId: display.coverArtId, mode: .downloadedOnly)
        case .albumById(let id, let name, _, let coverArtId):
            AlbumDetailView(albumId: id, albumName: name, coverArtId: coverArtId)
        case .playlistById(let id, let name, let coverArtId):
            PlaylistDetailView(
                playlistId: id,
                name: name,
                coverArtId: coverArtId,
                initialCoverImage: artworkImageCache.cachedImage(for: coverArtId ?? id)
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

// MARK: - Playlist grid tile (compact, two per row)

private struct PlaylistGridTile: View {
    let playlist: Playlist
    let namespace: Namespace.ID

    var body: some View {
        NavigationLink(value: HomeDestination.playlist(playlist)) {
            HomeGridTileChrome {
                PlaylistCoverThumbnail(
                    playlistId: playlist.id,
                    serverId: nil,
                    coverArtId: playlist.coverArt ?? playlist.id,
                    title: playlist.name,
                    size: HomeShelfLayout.gridTileCoverSide
                )
                .minidiscMatchedTransitionSource(id: playlist.id, in: namespace)
            } detail: {
                Text(playlist.name)
                    .font(.minidiscCellTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
        }
        .buttonStyle(.plain)
        .collectionContextMenu(itemType: .playlist, itemId: playlist.id, displayName: playlist.name,
                               displaySubtitle: playlist.owner ?? "", coverArtId: playlist.coverArt)
        .accessibilityIdentifier("home.playlist.\(playlist.id)")
    }
}

// MARK: - Top pick card (large, Apple-Music style)

private struct TopPickCard: View {
    let playlist: Playlist
    let namespace: Namespace.ID

    private let side: CGFloat = 250

    var body: some View {
        NavigationLink(value: HomeDestination.playlist(playlist)) {
            VStack(alignment: .leading, spacing: MinidiscSpacing.s) {
                PlaylistCoverThumbnail(
                    playlistId: playlist.id,
                    serverId: nil,
                    coverArtId: playlist.coverArt ?? playlist.id,
                    title: playlist.name,
                    size: side
                )
                .minidiscMatchedTransitionSource(id: playlist.id, in: namespace)
                CoverCardMetadata(
                    title: playlist.name,
                    subtitle: playlist.changed.map { String(localized: "Updated \($0.formatted(.relative(presentation: .named)))") },
                    detail: String(localized: "\(playlist.songCount) tracks")
                )
            }
            .frame(width: side, alignment: .leading)
        }
        .buttonStyle(.plain)
        .collectionContextMenu(itemType: .playlist, itemId: playlist.id, displayName: playlist.name,
                               displaySubtitle: playlist.owner ?? "", coverArtId: playlist.coverArt)
        .accessibilityIdentifier("home.playlist.\(playlist.id)")
    }
}

private struct OfflineHomeInfo: View {
    @Environment(\.appContainer) private var container

    var body: some View {
        VStack(alignment: .leading, spacing: MinidiscSpacing.s) {
            OfflineHomeCard(
                isManual: container?.serverState.isOfflineModeEnabled == true,
                songCount: container?.offlineLibrary.snapshot.songs.count ?? 0,
                isLoading: container?.offlineLibrary.isLoading == true,
                onDisable: { container?.serverState.isOfflineModeEnabled = false }
            )
            Text("While offline, the app only shows content available on this device.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, MinidiscSpacing.m)
        }
        .padding(.horizontal, MinidiscSpacing.l)
    }
}

private struct HomeShelfPlaceholder: View {
    let title: LocalizedStringResource
    let side: CGFloat
    var body: some View {
        MinidiscShelf {
            MinidiscCarouselHeader(title, showsChevron: false)
        } content: {
            ForEach(0..<3) { _ in
                VStack(alignment: .leading, spacing: MinidiscSpacing.s) {
                    RoundedRectangle(cornerRadius: MinidiscCornerRadius.standard)
                        .fill(.quaternary).frame(width: side, height: side)
                    Text("Loading…").font(.subheadline)
                    Text("Loading…").font(.caption)
                }
                .redacted(reason: .placeholder)
                .frame(width: side, alignment: .leading)
            }
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue("Loading")
    }
}

#if DEBUG
#Preview("Home") {
    MinidiscPreview(container: .preview()) {
        NavigationStack {
            HomeView(viewModel: .preview())
        }
    }
}
#endif
