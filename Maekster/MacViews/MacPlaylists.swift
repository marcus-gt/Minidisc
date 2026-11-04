import OSLog
import SwiftData
import SwiftSonic
import SwiftUI

// MARK: - List

/// The playlists, with New Playlist in the toolbar and Play, Shuffle, Rename and Delete on each row.
struct MacPlaylistsView: View {
    @Environment(\.appContainer) private var container
    @Environment(MacNavigator.self) private var navigator
    @State private var viewModel: PlaylistListViewModel?
    @State private var createsPlaylist = false
    /// Opened once the New Playlist sheet has closed; pushing while it closes left the list drawn
    /// underneath the new page.
    @State private var createdPlaylistId: String?
    @State private var renameRequest: PlaylistRenameRequest?

    var body: some View {
        Group {
            if let vm = viewModel {
                MacListState(
                    isLoading: vm.isLoading, error: vm.error, isEmpty: vm.playlists.isEmpty,
                    errorTitle: "Unable to Load Playlists", emptyImage: "music.note.list", emptyTitle: "No Playlists",
                    emptySubtitle: nil, retry: vm.load
                ) {
                    List(vm.playlists, id: \.id) { playlist in
                        NavigationLink(value: MacRoute.playlist(id: playlist.id)) {
                            MacPlaylistRow(
                                playlist: playlist,
                                onRename: {
                                    renameRequest = PlaylistRenameRequest(
                                        playlistId: playlist.id, currentName: playlist.name, coverArtId: playlist.coverArt
                                    )
                                },
                                onDeleted: { Task { await vm.load() } }
                            )
                        }
                    }
                }
            } else {
                LoadingStateView()
            }
        }
        .navigationTitle("Playlists")
        .toolbar {
            Button("New Playlist", systemImage: "plus") { createsPlaylist = true }
        }
        .sheet(isPresented: $createsPlaylist, onDismiss: openCreatedPlaylist) {
            MacNewPlaylistSheet { created in
                createdPlaylistId = created.id
                Task { await viewModel?.load() }
            }
        }
        .playlistRenameAlert($renameRequest) { Task { await viewModel?.load() } }
        .onReceive(NotificationCenter.default.publisher(for: .maeksterPlaylistDeleted)) { _ in
            Task { await viewModel?.load() }
        }
        // File › New Playlist (⌘N).
        .onChange(of: navigator.requestsNewPlaylist, initial: true) { _, requested in
            guard requested else { return }
            navigator.requestsNewPlaylist = false
            createsPlaylist = true
        }
        // Returning from a playlist picks up its new name or song count.
        .onAppear {
            guard let viewModel else { return }
            Task { await viewModel.load() }
        }
        .task {
            guard viewModel == nil, let container else { return }
            let vm = PlaylistListViewModel(libraryService: container.libraryService)
            viewModel = vm
            await vm.load()
        }
    }

    private func openCreatedPlaylist() {
        guard let id = createdPlaylistId else { return }
        createdPlaylistId = nil
        navigator.open(.playlist(id: id))
    }
}

/// One playlist in the list, with its context menu and delete confirmation.
private struct MacPlaylistRow: View {
    let playlist: Playlist
    let onRename: () -> Void
    let onDeleted: () -> Void

    @Environment(\.appContainer) private var container
    @Query private var downloadedMatches: [DownloadedPlaylist]
    @State private var confirmsDelete = false

    init(playlist: Playlist, onRename: @escaping () -> Void, onDeleted: @escaping () -> Void) {
        self.playlist = playlist
        self.onRename = onRename
        self.onDeleted = onDeleted
        let pid = playlist.id
        _downloadedMatches = Query(filter: #Predicate<DownloadedPlaylist> { $0.playlistId == pid })
    }

    var body: some View {
        HStack(spacing: MaeksterSpacing.m) {
            PlaylistCoverThumbnail(
                playlistId: playlist.id, serverId: nil,
                coverArtId: playlist.coverArt ?? playlist.id, title: playlist.name, size: 40
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.name)
                Text("\(playlist.songCount) tracks")
                    .foregroundStyle(.secondary)
            }
        }
        .contextMenu {
            Button("Play", systemImage: "play.fill") { play(shuffled: false) }
            Button("Shuffle", systemImage: "shuffle") { play(shuffled: true) }
            Divider()
            Button("Rename Playlist", systemImage: "character.cursor.ibeam", action: onRename)
            Button("Delete Playlist", systemImage: "trash", role: .destructive) { confirmsDelete = true }
        }
        .deletePlaylistConfirmation(
            playlistName: playlist.name,
            isPresented: $confirmsDelete,
            hasDownloads: !downloadedMatches.isEmpty
        ) { purgeDownloads in
            Task { await macDeletePlaylist(id: playlist.id, purgeDownloads: purgeDownloads, container: container, then: onDeleted) }
        }
    }

    /// Reads the playlist from the server when Play is chosen, so the queue is current.
    private func play(shuffled: Bool) {
        guard let container else { return }
        let service = container.playlistService
        let source = QueueSource.playlist(id: playlist.id, name: playlist.name)
        let id = playlist.id
        Task {
            await container.toastService.perform {
                try await container.playerService.play(preparingQueue: {
                    let loaded = try await service.getPlaylist(id: id)
                    let songs = (loaded.entry ?? []).map { DisplayableSong(from: $0) }
                    guard !songs.isEmpty else { throw UserFacingError.contentRemoved }
                    return PreparedPlaybackQueue(tracks: shuffled ? songs.shuffled() : songs, startIndex: 0, source: source)
                })
            }
            container.recordPlaylistUse(id)
        }
    }
}

/// Deletes a playlist the way the iPhone list does: server first, then the cache, with a toast either way.
@MainActor
func macDeletePlaylist(id: String, purgeDownloads: Bool, container: AppContainer?,
                       then onDeleted: @escaping () -> Void) async {
    guard let container else { return }
    do {
        try await container.playlistService.deletePlaylist(id: id, purgeDownloads: purgeDownloads)
        onDeleted()
        container.toastService.showConfirmation("Playlist deleted")
    } catch {
        Logger.playlist.error("[PLAYLIST] delete failed id=\(id, privacy: .public): \(error, privacy: .public)")
        container.toastService.showError("Couldn't delete playlist. Please try again.")
    }
}

/// Names a new, empty playlist.
private struct MacNewPlaylistSheet: View {
    let onCreated: (PlaylistWithSongs) -> Void

    @Environment(\.appContainer) private var container
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: CreatePlaylistViewModel?

    var body: some View {
        Form {
            if let viewModel {
                @Bindable var vm = viewModel
                TextField("Playlist Title", text: $vm.name)
                    .onSubmit(create)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("New Playlist")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Create Playlist", action: create)
                    .disabled(viewModel?.canCreate != true)
            }
        }
        .frame(minWidth: 360)
        .task {
            guard viewModel == nil, let container else { return }
            viewModel = CreatePlaylistViewModel(
                playlistService: container.playlistService, toastService: container.toastService
            )
        }
    }

    private func create() {
        guard let viewModel, viewModel.canCreate else { return }
        Task {
            guard let created = await viewModel.create() else { return }
            dismiss()
            onCreated(created)
        }
    }
}

// MARK: - Page

/// A playlist's songs: drag rows to reorder, remove from the context menu, rename or delete from
/// the header.
struct MacPlaylistView: View {
    let playlistId: String

    @Environment(\.appContainer) private var container
    @Environment(MacNavigator.self) private var navigator
    @State private var viewModel: PlaylistDetailViewModel?
    @State private var renameRequest: PlaylistRenameRequest?
    @State private var confirmsDelete = false
    @Query private var downloadedMatches: [DownloadedPlaylist]

    init(playlistId: String) {
        self.playlistId = playlistId
        _downloadedMatches = Query(filter: #Predicate<DownloadedPlaylist> { $0.playlistId == playlistId })
    }

    var body: some View {
        Group {
            if let vm = viewModel, !(vm.isLoading && vm.songs.isEmpty) {
                if let error = vm.error, vm.songs.isEmpty {
                    EmptyStateView(
                        systemImage: "exclamationmark.triangle",
                        title: "Unable to Load Playlist",
                        subtitle: LocalizedStringKey(error.displayMessage),
                        action: .init(label: "Retry") { Task { await vm.load() } }
                    )
                } else {
                    VStack(spacing: 0) {
                        header(vm)
                        if vm.songs.isEmpty {
                            EmptyStateView(
                                systemImage: "music.note.list",
                                title: "Empty Playlist",
                                subtitle: "This playlist doesn't have any tracks yet."
                            )
                        } else {
                            MacTrackTable(
                                songs: vm.songs,
                                onPlay: { play(vm.songs, from: $0) },
                                onRemove: { offsets in Task { await vm.removeTracks(at: offsets) } },
                                onMove: { source, destination in Task { await vm.moveTracks(from: source, to: destination) } }
                            )
                        }
                    }
                }
            } else {
                LoadingStateView()
            }
        }
        .navigationTitle(viewModel?.name ?? "")
        .playlistRenameAlert($renameRequest) { Task { await viewModel?.load() } }
        .deletePlaylistConfirmation(
            playlistName: viewModel?.name ?? "",
            isPresented: $confirmsDelete,
            hasDownloads: !downloadedMatches.isEmpty
        ) { purgeDownloads in
            Task {
                await macDeletePlaylist(id: playlistId, purgeDownloads: purgeDownloads, container: container) {
                    postPlaylistDeleted()
                    if !navigator.path.isEmpty { navigator.path.removeLast() }
                }
            }
        }
        .task {
            guard viewModel == nil, let container else { return }
            let vm = PlaylistDetailViewModel(
                playlistId: playlistId,
                libraryService: container.libraryService,
                downloadService: container.downloadService,
                playlistService: container.playlistService,
                toastService: container.toastService,
                serverState: container.serverState,
                offlineReader: container.offlineBrowsingReader
            )
            viewModel = vm
            await vm.load()
        }
    }

    private func header(_ vm: PlaylistDetailViewModel) -> some View {
        var details: [String] = []
        if !vm.songs.isEmpty {
            details.append(String(localized: "\(vm.songs.count) songs"))
            details.append(macTotalDuration(vm.songs))
        }
        return MacPageHeader(
            coverArtId: vm.coverArtId ?? playlistId,
            title: vm.name,
            details: details,
            onPlay: { play(vm.songs, from: 0) },
            onShuffle: { play(vm.songs.shuffled(), from: 0) }
        ) {
            Menu {
                Button("Rename Playlist", systemImage: "character.cursor.ibeam") {
                    renameRequest = PlaylistRenameRequest(
                        playlistId: playlistId, currentName: vm.name, coverArtId: vm.coverArtId
                    )
                }
                Button("Delete Playlist", systemImage: "trash", role: .destructive) { confirmsDelete = true }
            } label: {
                Label("Edit Playlist", systemImage: "ellipsis")
            }
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Edit Playlist")
        }
    }

    /// Like the iPhone playlist page: the queue is re-read from the server first, so songs removed
    /// elsewhere aren't played, and a late result can't override Pause or another Play.
    private func play(_ requested: [DisplayableSong], from index: Int) {
        guard requested.indices.contains(index), let vm = viewModel, let container else { return }
        let selectedID = requested[index].id
        let source = QueueSource.playlist(id: playlistId, name: vm.name)
        Task {
            do {
                try await container.playerService.play(preparingQueue: {
                    let refreshed = await vm.playbackSongs(from: requested)
                    guard let start = refreshed.firstIndex(where: { $0.id == selectedID }) else {
                        throw UserFacingError.contentRemoved
                    }
                    return PreparedPlaybackQueue(tracks: refreshed, startIndex: start, source: source)
                })
                container.recordPlaylistUse(playlistId)
            } catch {
                if !UserFacingError.isCancellation(error), !vm.isRemovedFromServer {
                    container.toastService.showError(UserFacingError.from(error).displayMessage)
                }
            }
        }
    }
}
