import OSLog
import SwiftData
import SwiftSonic
import SwiftUI

/// The Home section: the iPhone's Home feed as shelves of covers, in the order and with the
/// sections chosen in the iPhone's Settings › Home Screen. Offline it shows what's saved here.
struct MacHomeView: View {
    @Environment(\.appContainer) private var container
    @State private var viewModel: HomeFeedViewModel?
    @State private var loadedServerID: UUID?
    @AppStorage(HomeLayoutConfiguration.storageKey) private var homeLayout: HomeLayoutConfiguration = .default
    @Query(sort: \PinnedItem.sortOrder) private var pinnedItems: [PinnedItem]
    @State private var artistPicks: [ArtistID3] = []
    @State private var editsLayout = false

    private var isOnline: Bool { container?.serverState.isOnline == true }

    private struct LoadIdentity: Equatable {
        let serverID: UUID?
        let online: Bool
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
        .toolbar {
            Button {
                editsLayout = true
            } label: {
                Label("Home Screen", systemImage: "slider.horizontal.3")
            }
            .help("Home Screen")
            Button {
                Task { await viewModel?.load(isOnline: isOnline, preserveLayout: true) }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r")
            .help("Refresh")
            .disabled(viewModel?.isLoading != false)
        }
        .task(id: LoadIdentity(serverID: container?.serverState.activeServer?.id, online: isOnline)) {
            guard let c = container, let serverID = c.serverState.activeServer?.id else { return }
            // A server switch builds a new feed, so one server's shelves never show for another.
            if viewModel == nil || loadedServerID != serverID {
                loadedServerID = serverID
                let pinService = c.pinService
                viewModel = HomeFeedViewModel(
                    libraryService: c.libraryService, cache: HomeFeedCache.shared, serverID: serverID,
                    diagnostics: c.playbackDiagnostics,
                    pinnedPlaylistIDs: { Set(pinService.pinnedItemIds(itemType: .playlist, serverId: serverID)) }
                )
            }
            await viewModel?.load(isOnline: isOnline)
        }
        .task(id: LoadIdentity(serverID: container?.serverState.activeServer?.id, online: isOnline)) {
            await loadArtistPicks()
        }
        .sheet(isPresented: $editsLayout) {
            MacHomeLayoutSheet()
        }
        .task {
            // Playlists created, renamed or deleted anywhere refresh the playlist shelf.
            for await _ in NotificationCenter.default.notifications(named: .maeksterPlaylistsChanged) {
                await viewModel?.load(isOnline: isOnline, preserveLayout: true)
            }
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
        let favorites = isOnline ? vm.favorites : container?.offlineLibrary.snapshot.favorites ?? HomeFavorites()
        if !vm.isLoading, vm.isEmpty, !isOnline {
            ScrollView {
                VStack(alignment: .leading, spacing: MaeksterSpacing.section) {
                    favoriteSongs(favorites.songs)
                    albumShelf(Text("Albums"), albums: container?.offlineLibrary.snapshot.albums ?? [])
                }
                .padding(.vertical, MaeksterSpacing.l)
            }
        } else if let error = vm.error, vm.isEmpty, !vm.isLoading {
            EmptyStateView(
                systemImage: "exclamationmark.triangle",
                title: "Unable to Load",
                subtitle: LocalizedStringKey(error.displayMessage),
                action: .init(label: "Retry") { Task { await vm.load(isOnline: isOnline) } }
            )
        } else if vm.isEmpty, !vm.isLoading {
            EmptyStateView(
                systemImage: "music.note.list",
                title: "No music yet",
                subtitle: "Add some music to your server to get started"
            )
        } else if vm.isEmpty {
            LoadingStateView()
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: MaeksterSpacing.section) {
                    if isOnline, vm.hasPartialFailure {
                        HStack {
                            Text("Some sections could not be refreshed. Your saved library is still available.")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Retry") { Task { await vm.load(isOnline: isOnline, preserveLayout: true) } }
                        }
                        .padding(.horizontal, MaeksterSpacing.xl)
                    }
                    ForEach(homeLayout.visibleSections) { section in
                        feedSection(section, vm: vm, favorites: favorites)
                    }
                }
                .padding(.vertical, MaeksterSpacing.l)
            }
        }
    }

    /// One section of the feed.
    @ViewBuilder
    private func feedSection(_ section: HomeSection, vm: HomeFeedViewModel, favorites: HomeFavorites) -> some View {
        switch section {
        case .pinned:
            pinnedShelf
        case .playlists:
            let picks = container?.visiblePlaylists(vm.topPicks) ?? []
            MacShelf(
                title: Text(section.title),
                items: Array(picks.prefix(MacShelfMetrics.limit)),
                seeAll: picks.count > MacShelfMetrics.limit
                    ? .playlistCollection(title: String(localized: section.title), playlists: picks) : nil
            ) { MacPlaylistShelfCell(playlist: $0) }
        case .favoriteSongs:
            favoriteSongs(favorites.songs)
        case .favoriteAlbums:
            albumShelf(section, albums: favorites.albums, source: .favorites)
        case .recentlyPlayed:
            albumShelf(section, albums: container?.visibleAlbums(vm.recentlyPlayed) ?? [])
        case .heavyRotation:
            albumShelf(section, albums: container?.visibleAlbums(vm.heavyRotation) ?? [])
        case .artists:
            if isOnline {
                MacShelf(title: Text(section.title), items: artistPicks, cellWidth: MacShelfMetrics.artistWidth) {
                    MacArtistShelfCell(artist: $0)
                }
            }
        case .rediscover:
            albumShelf(section, albums: container?.visibleAlbums(vm.rediscovery) ?? [])
        case .recentlyAdded:
            albumShelf(section, albums: container?.visibleAlbums(vm.recentlyAdded) ?? [], source: .recentlyAdded,
                       continuesRecentlyAdded: true)
        case .genres:
            ForEach(vm.genreShelves) { shelf in
                albumShelf(Text(verbatim: shelf.name), title: shelf.name,
                           albums: container?.visibleAlbums(shelf.albums) ?? [], source: .genre(name: shelf.name))
            }
        case .queueBuilder:
            if isOnline, let queueBuilder = container?.queueBuilderViewModel() {
                // The cards pad themselves by `l`; the page margin is `xl`.
                QueueBuilderCard(viewModel: queueBuilder, isPanel: true)
                    .padding(.horizontal, MaeksterSpacing.xl - MaeksterSpacing.l)
            }
        case .songPath:
            if SongPathAvailability.isAvailable(container) {
                SongPathCard()
                    .padding(.horizontal, MaeksterSpacing.xl - MaeksterSpacing.l)
            }
        }
    }

    private func albumShelf(_ section: HomeSection, albums: [AlbumID3], source: QueueSource? = nil,
                            continuesRecentlyAdded: Bool = false) -> some View {
        albumShelf(Text(section.title), title: String(localized: section.title), albums: albums, source: source,
                   continuesRecentlyAdded: continuesRecentlyAdded)
    }

    /// See All appears when the shelf holds back albums, and always for Recently Added, which keeps
    /// loading older albums there.
    private func albumShelf(_ label: Text, title: String = "", albums: [AlbumID3], source: QueueSource? = nil,
                            continuesRecentlyAdded: Bool = false) -> some View {
        let showsAll = albums.count > MacShelfMetrics.limit || (continuesRecentlyAdded && isOnline)
        return MacShelf(
            title: label,
            items: Array(albums.prefix(MacShelfMetrics.limit)),
            seeAll: showsAll && !title.isEmpty
                ? .albumCollection(title: title, albums: albums, continuesRecentlyAdded: continuesRecentlyAdded) : nil,
            // Play and Shuffle take the albums the shelf shows.
            onPlay: { shuffled in
                macPlayAlbums(Array(albums.prefix(MacShelfMetrics.limit)), shuffled: shuffled, source: source,
                              container: container)
            }
        ) { MacAlbumShelfCell(album: $0) }
    }

    // MARK: - Pinned

    /// Pins on the active server, in pin order, drawn from their snapshots (so they show offline).
    @ViewBuilder
    private var pinnedShelf: some View {
        let serverID = container?.serverState.activeServer?.id
        MacShelf(title: Text(HomeSection.pinned.title), items: pinnedItems.filter { $0.serverId == serverID }) { item in
            switch PinnedItemType(rawValue: item.itemType) {
            case .album:
                MacAlbumShelfCell(album: AlbumID3(
                    id: item.itemId, name: item.displayName, songCount: 0, duration: 0,
                    artist: item.displaySubtitle.isEmpty ? nil : item.displaySubtitle, coverArt: item.coverArtId
                ))
            case .playlist:
                // The pin keeps no track count: take it from the loaded playlists, else say "Playlist".
                if let loaded = viewModel?.topPicks.first(where: { $0.id == item.itemId }) {
                    MacPlaylistShelfCell(playlist: loaded)
                } else {
                    MacPlaylistShelfCell(
                        playlist: Playlist(id: item.itemId, name: item.displayName, songCount: 0, duration: 0,
                                           coverArt: item.coverArtId),
                        subtitle: String(localized: "Playlist")
                    )
                }
            case .artist:
                MacArtistShelfCell(artist: ArtistID3(id: item.itemId, name: item.displayName, coverArt: item.coverArtId))
            case nil:
                EmptyView()
            }
        }
    }

    // MARK: - Favourite songs

    /// Columns of four songs that scroll sideways, like the Music app's song shelves.
    private struct SongColumn: Identifiable {
        let id: Int
        let songs: ArraySlice<DisplayableSong>
    }

    @ViewBuilder
    private func favoriteSongs(_ songs: [Song]) -> some View {
        let tracks = songs.map { DisplayableSong(from: $0) }
        let columns = stride(from: 0, to: tracks.count, by: 4).map {
            SongColumn(id: $0, songs: tracks[$0..<min($0 + 4, tracks.count)])
        }
        MacShelf(title: Text(HomeSection.favoriteSongs.title), items: columns,
                 cellWidth: MacShelfMetrics.songColumnWidth,
                 onPlay: { shuffled in
                     playFavorites(shuffled ? tracks.shuffled() : tracks, from: 0)
                 }) { column in
            MacSongRows(songs: Array(column.songs)) { index in
                playFavorites(tracks, from: column.id + index)
            }
        }
    }

    private func playFavorites(_ tracks: [DisplayableSong], from index: Int) {
        guard let container else { return }
        Task {
            await container.toastService.perform {
                try await container.playerService.play(tracks: tracks, startIndex: index, source: .favorites)
            }
        }
    }

    // MARK: - Artist picks

    /// "Artist Picks": today's blend of favourite, dormant and untried artists (#63). Loaded here
    /// rather than by the shelf, which draws nothing (and so never runs a task) until it has artists.
    private func loadArtistPicks() async {
        guard isOnline, let container, let serverID = container.serverState.activeServer?.id else { return }
        do {
            let picked = try await container.artistShelfService.artists(serverID: serverID)
            // A server switch while loading leaves this pick to the next task.
            guard !Task.isCancelled, container.serverState.activeServer?.id == serverID else { return }
            artistPicks = picked
        } catch {
            // The shelf stays hidden; the rest of Home doesn't depend on it.
            guard !UserFacingError.isCancellation(error) else { return }
            Logger.library.error("[ARTIST-SHELF] load failed: \(error, privacy: .public)")
        }
    }
}

/// Home › Home Screen: which sections show and in what order (the iPhone's Settings › Home Screen).
private struct MacHomeLayoutSheet: View {
    @AppStorage(HomeLayoutConfiguration.storageKey) private var configuration: HomeLayoutConfiguration = .default

    var body: some View {
        MacSectionLayoutSheet(
            title: "Home Screen",
            sections: configuration.order,
            label: \.title,
            isVisible: { configuration.isVisible($0) },
            setVisible: { configuration.setVisible($0, for: $1) },
            setListedOrder: { configuration.setOrder($0) },
            reset: { configuration = .default }
        )
    }
}

/// A sheet that shows or hides a page's sections and reorders them by dragging.
struct MacSectionLayoutSheet<Section: LayoutSection>: View {
    let title: LocalizedStringKey
    /// The sections listed, in their current order.
    let sections: [Section]
    let label: (Section) -> LocalizedStringResource
    let isVisible: (Section) -> Bool
    let setVisible: (Bool, Section) -> Void
    /// Saves a new order of the listed sections.
    let setListedOrder: ([Section]) -> Void
    let reset: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                SwiftUI.Section {
                    ForEach(sections) { section in
                        Toggle(isOn: Binding(get: { isVisible(section) }, set: { setVisible($0, section) })) {
                            Text(label(section))
                        }
                        .toggleStyle(.checkbox)
                        .padding(.vertical, MaeksterSpacing.xs)
                    }
                    .onMove { source, destination in
                        var order = sections
                        order.move(fromOffsets: source, toOffset: destination)
                        setListedOrder(order)
                    }
                } footer: {
                    Text("Check a section to show it, and drag to change the order.")
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .destructiveAction) {
                    Button("Reset to Default", action: reset)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 380, minHeight: 460)
    }
}
