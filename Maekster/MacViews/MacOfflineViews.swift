import SwiftUI

// MARK: - Downloads

/// The Downloaded section: transfers in progress, then the downloaded albums and playlists (open
/// them, or right-click to remove the download), with the space they use.
struct MacDownloadsView: View {
    @Environment(\.appContainer) private var container
    @State private var viewModel: DownloadsViewModel?

    var body: some View {
        Group {
            if let vm = viewModel, let serverID = container?.serverState.activeServer?.id {
                if vm.displayAlbums.isEmpty && vm.downloadedPlaylists.isEmpty
                    && container?.downloadActivity.transfers.isEmpty != false {
                    EmptyStateView(
                        systemImage: "arrow.down.circle",
                        title: "Nothing downloaded",
                        subtitle: "Albums and playlists you download will be available here, even offline."
                    )
                } else {
                    list(vm, serverID: serverID)
                }
            } else {
                LoadingStateView()
            }
        }
        .navigationTitle("Downloads")
        .task(id: container?.downloadActivity.transfers.count) {
            // Reloads as transfers finish, so new downloads appear.
            guard let container else { return }
            if viewModel == nil {
                viewModel = DownloadsViewModel(
                    modelContainer: container.modelContainer,
                    downloadService: container.downloadService,
                    serverState: container.serverState,
                    toastService: container.toastService
                )
            }
            await viewModel?.loadData()
        }
    }

    private func list(_ vm: DownloadsViewModel, serverID: UUID) -> some View {
        List {
            DownloadActivitySection(serverID: serverID)

            if !vm.displayAlbums.isEmpty {
                Section("Albums") {
                    ForEach(vm.displayAlbums) { album in
                        NavigationLink(value: MacRoute.album(id: album.albumId)) {
                            HStack(spacing: MaeksterSpacing.m) {
                                CoverArtCard(id: album.coverArtId ?? album.albumId, size: 40,
                                             cornerRadius: MaeksterCornerRadius.xs)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(album.name)
                                    Text(album.artist ?? "")
                                        .foregroundStyle(.secondary)
                                }
                                .lineLimit(1)
                                Spacer()
                                Text("\(album.downloadedTracksCount) tracks")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contextMenu {
                            Button("Remove Download", systemImage: "trash", role: .destructive) {
                                Task { await vm.removeAlbum(album) }
                            }
                        }
                    }
                }
            }

            if !vm.downloadedPlaylists.isEmpty {
                Section("Playlists") {
                    ForEach(vm.downloadedPlaylists, id: \.id) { playlist in
                        NavigationLink(value: MacRoute.playlist(id: playlist.playlistId)) {
                            HStack {
                                Text(playlist.name)
                                Spacer()
                                Text("\(playlist.tracksCount) tracks")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contextMenu {
                            Button("Remove Download", systemImage: "trash", role: .destructive) {
                                Task { await vm.removePlaylist(playlist) }
                            }
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Text(verbatim: vm.usedBytesFormatted)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(MaeksterSpacing.s)
        }
    }
}

// MARK: - Local files

/// The Local Files section: every song in the music folders added through Files, newest first, in a
/// track table, with Manage Folders for adding and removing folders. The files stay where they are.
struct MacLocalFilesView: View {
    @Environment(\.appContainer) private var container
    @State private var managesFolders = false

    private var tracks: [LocalMusicTrack] {
        (container?.localMusic.snapshot.tracks ?? []).sorted(by: LocalMusicTrack.mostRecentFirst)
    }

    var body: some View {
        Group {
            if container?.localMusic.snapshot.folders.isEmpty != false {
                EmptyStateView(
                    systemImage: "folder",
                    title: LocalizedStringKey(String(localized: "Local Files", table: "LocalMusic")),
                    subtitle: LocalizedStringKey(String(localized: "Add music folders from Files. Your audio stays where it is.", table: "LocalMusic")),
                    action: .init(label: LocalizedStringKey(String(localized: "Manage Folders", table: "LocalMusic"))) {
                        managesFolders = true
                    }
                )
            } else if tracks.isEmpty {
                if container?.localMusic.isRefreshing == true {
                    LoadingStateView()
                } else {
                    EmptyStateView(
                        systemImage: "folder",
                        title: LocalizedStringKey(String(localized: "No audio files found. Check your folders in Files, then refresh.", table: "LocalMusic"))
                    )
                }
            } else {
                MacTrackTable(songs: tracks.map(\.song)) { index in
                    play(from: index)
                }
            }
        }
        .navigationTitle(Text("Local Files", tableName: "LocalMusic"))
        .toolbar {
            Button {
                managesFolders = true
            } label: {
                Label { Text("Manage Folders", tableName: "LocalMusic") } icon: { Image(systemName: "folder") }
            }
        }
        .sheet(isPresented: $managesFolders) {
            NavigationStack {
                LocalMusicFoldersView()
                    .formStyle(.grouped)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { managesFolders = false }
                        }
                    }
            }
            .frame(minWidth: 460, minHeight: 360)
        }
    }

    private func play(from index: Int) {
        guard let container else { return }
        let songs = tracks.map(\.song)
        let source = QueueSource.localFolder(name: String(localized: "Local Files", table: "LocalMusic"))
        Task {
            await container.toastService.perform {
                try await container.playerService.play(tracks: songs, startIndex: index, source: source)
            }
        }
    }
}
