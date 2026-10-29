import SwiftUI
import SwiftData
import SwiftSonic
import OSLog

struct PlaylistListView: View {
    var zoomNamespace: Namespace.ID? = nil
    @Environment(\.appContainer) private var container
    @State private var viewModel: PlaylistListViewModel?
    @State private var showCreateSheet = false
    @State private var filterText = ""
    @AppStorage("minidisc.playlistListSort") private var sort: PlaylistListSort = .lastUsed
    /// Snapshot of local "added to or played" dates, refreshed whenever the list appears.
    @State private var lastUsed: [String: Date] = [:]
    /// Set once a playlist is created, to open it so songs and a cover can be added.
    @State private var createdPlaylist: PlaylistWithSongs?

    var body: some View {
        Group {
            if let vm = viewModel {
                content(vm)
            } else {
                LoadingStateView()
            }
        }
        .minidiscContentWidth()
        .navigationTitle("Playlists")
        .toolbarTitleDisplayMode(.inline)
        .minidiscFilterable(text: $filterText, prompt: "Filter playlists")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                PlaylistListSortMenu(sort: $sort)
                    .tint(.primary)
            }
            ToolbarItem(placement: .primaryAction) {
                MinidiscMoreMenu {
                    Button("New Playlist", systemImage: "plus") {
                        showCreateSheet = true
                    }
                    .disabled(container?.serverState.isOnline != true)
                }
                .tint(.primary)
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            CreatePlaylistSheet { created in
                createdPlaylist = created
                Task { await viewModel?.load() }
            }
        }
        .navigationDestination(item: $createdPlaylist) { playlist in
            PlaylistDetailView(playlistId: playlist.id, name: playlist.name, coverArtId: playlist.coverArt)
        }
        .task(id: container?.serverState.isOnline) {
            guard let svc = container?.libraryService else { return }
            refreshLastUsed()
            if viewModel == nil { viewModel = PlaylistListViewModel(libraryService: svc) }
            guard container?.serverState.isOnline == true else { return }
            await viewModel?.load()
        }
        .onAppear { refreshLastUsed() }
        // Reload after confirmed deletion without refetching on every navigation.
        .onReceive(NotificationCenter.default.publisher(for: .minidiscPlaylistDeleted)) { _ in
            Task { await viewModel?.load() }
        }
    }

    private func allPlaylists(_ vm: PlaylistListViewModel) -> [Playlist] {
        container?.serverState.isOnline == false ? container?.offlineLibrary.snapshot.playlists ?? [] : vm.playlists
    }

    private func displayedPlaylists(_ vm: PlaylistListViewModel) -> [Playlist] {
        sort.sorted(LibraryFilter.filter(allPlaylists(vm), by: filterText) { [$0.name] }, lastUsed: lastUsed)
    }

    private func refreshLastUsed() {
        guard let container, let serverID = container.serverState.activeServer?.id.uuidString else {
            lastUsed = [:]
            return
        }
        lastUsed = container.playlistUsage.lastUsed(serverID: serverID)
    }

    @ViewBuilder
    private func content(_ vm: PlaylistListViewModel) -> some View {
        if container?.serverState.isOnline != false && vm.isLoading && allPlaylists(vm).isEmpty {
            LoadingStateView()
        } else if container?.serverState.isOnline == false && allPlaylists(vm).isEmpty {
            OfflineBrowsingEmptyView()
        } else if let error = vm.error, allPlaylists(vm).isEmpty {
            EmptyStateView(
                systemImage: "exclamationmark.triangle",
                title: "Unable to Load Playlists",
                subtitle: LocalizedStringKey(error.displayMessage),
                action: .init(label: "Retry") { Task { await vm.load() } }
            )
        } else if allPlaylists(vm).isEmpty {
            EmptyStateView(
                systemImage: "list.bullet",
                title: "No Playlists",
                subtitle: "Tap + to create your first playlist."
            )
        } else if displayedPlaylists(vm).isEmpty {
            FilterNoResultsView(query: filterText)
        } else {
            List {
                serverPlaylistRows(vm)
            }
            .listStyle(.plain)
            .refreshable { await vm.load() }
        }
    }

    @ViewBuilder
    private func serverPlaylistRows(_ vm: PlaylistListViewModel) -> some View {
        ForEach(displayedPlaylists(vm)) { playlist in
            NavigationLink(value: HomeDestination.playlist(playlist)) {
                OnlinePlaylistRow(
                    playlist: playlist,
                    namespace: zoomNamespace,
                    onActionCompleted: { Task { await vm.load() } }
                )
            }
        }
    }
}

// MARK: - Online playlist row

private struct OnlinePlaylistRow: View {
    let playlist: Playlist
    var namespace: Namespace.ID? = nil
    var onActionCompleted: (() -> Void)? = nil

    @Environment(\.appContainer) private var container
    @Environment(ArtworkImageCache.self) private var artworkImageCache
    @State private var coverImage: PlatformImage?
    @State private var showDeleteConfirm = false
    @Query private var downloadedMatches: [DownloadedPlaylist]

    init(playlist: Playlist, namespace: Namespace.ID? = nil, onActionCompleted: (() -> Void)? = nil) {
        self.playlist = playlist
        self.namespace = namespace
        self.onActionCompleted = onActionCompleted
        let pid = playlist.id
        _downloadedMatches = Query(filter: #Predicate<DownloadedPlaylist> { $0.playlistId == pid })
    }

    var body: some View {
        HStack(spacing: MinidiscSpacing.m) {
            PlaylistCoverThumbnail(playlistId: playlist.id, serverId: nil, coverArtId: playlist.coverArt ?? playlist.id, title: playlist.name, size: 56)
                .minidiscMatchedTransitionSource(id: playlist.id, in: namespace)
            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.name)
                    .font(.minidiscCellTitle)
                    .lineLimit(1)
                Text("\(playlist.songCount) tracks")
                    .font(.minidiscCaption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, MinidiscSpacing.xs)
        .task(id: playlist.id) {
            coverImage = await artworkImageCache.load(coverArtId: playlist.coverArt ?? playlist.id)
        }
        .collectionContextMenu(
            itemType: .playlist,
            itemId: playlist.id,
            displayName: playlist.name,
            displaySubtitle: "Playlist",
            coverArtId: playlist.coverArt,
            coverImage: coverImage,
            onDelete: { showDeleteConfirm = true }
        )
        .deletePlaylistConfirmation(
            playlistName: playlist.name,
            isPresented: $showDeleteConfirm,
            hasDownloads: !downloadedMatches.isEmpty
        ) { purgeDownloads in
            Task {
                guard let container else { return }
                do {
                    // The service deletes server-side first and rolls its own cache back on failure, so it is
                    // safe to refresh the (server-fresh) list only AFTER a confirmed success.
                    try await container.playlistService.deletePlaylist(id: playlist.id, purgeDownloads: purgeDownloads)
                    onActionCompleted?()
                    container.toastService.showConfirmation("Playlist deleted")
                } catch {
                    Logger.playlist.error("[PLAYLIST] delete failed id=\(playlist.id, privacy: .public): \(error, privacy: .public)")
                    container.toastService.showError("Couldn't delete playlist. Please try again.")
                }
            }
        }
    }
}

// MARK: - Offline Playlists
