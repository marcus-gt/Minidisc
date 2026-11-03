import SwiftSonic
import SwiftUI

/// Cover, title and Play / Shuffle above an album's or playlist's songs.
struct MacPageHeader: View {
    let coverArtId: String?
    let title: String
    var subtitle: String?
    var detail: String?
    let onPlay: () -> Void
    let onShuffle: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: MaeksterSpacing.xl) {
            CoverArtCard(id: coverArtId ?? "", size: 180, tier: .hero)
            VStack(alignment: .leading, spacing: MaeksterSpacing.s) {
                Text(title)
                    .font(.largeTitle.bold())
                    .lineLimit(2)
                if let subtitle {
                    Text(subtitle)
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                if let detail {
                    Text(detail)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button("Play", systemImage: "play.fill", action: onPlay)
                        .buttonStyle(.borderedProminent)
                        .tint(Color.maeksterAccent)
                    Button("Shuffle", systemImage: "shuffle", action: onShuffle)
                        .buttonStyle(.bordered)
                }
                .controlSize(.large)
                .padding(.top, MaeksterSpacing.s)
            }
            Spacer(minLength: 0)
        }
        .padding(MaeksterSpacing.xl)
    }
}

// MARK: - Album

struct MacAlbumView: View {
    let albumId: String

    @Environment(\.appContainer) private var container
    @State private var viewModel: AlbumDetailViewModel?

    var body: some View {
        Group {
            if let vm = viewModel, !(vm.isLoading && vm.songs.isEmpty) {
                if let error = vm.error, vm.songs.isEmpty {
                    EmptyStateView(
                        systemImage: "exclamationmark.triangle",
                        title: "Unable to Load Album",
                        subtitle: LocalizedStringKey(error.displayMessage),
                        action: .init(label: "Retry") { Task { await vm.load() } }
                    )
                } else {
                    VStack(spacing: 0) {
                        MacPageHeader(
                            coverArtId: vm.coverArtId,
                            title: vm.albumName,
                            subtitle: vm.artistName,
                            detail: vm.year.map(String.init),
                            onPlay: { play(vm.songs, from: 0, source: source(vm)) },
                            onShuffle: { play(vm.songs.shuffled(), from: 0, source: source(vm)) }
                        )
                        MacTrackTable(songs: vm.songs, showsAlbum: false) { index in
                            play(vm.songs, from: index, source: source(vm))
                        }
                    }
                }
            } else {
                LoadingStateView()
            }
        }
        .navigationTitle(viewModel?.albumName ?? "")
        .task {
            guard viewModel == nil, let container else { return }
            let vm = AlbumDetailViewModel(
                albumId: albumId,
                libraryService: container.libraryService,
                downloadService: container.downloadService,
                toastService: container.toastService,
                serverState: container.serverState,
                offlineFavorites: container.offlineFavoritesStore
            )
            viewModel = vm
            await vm.load()
        }
    }

    private func source(_ vm: AlbumDetailViewModel) -> QueueSource {
        .album(id: albumId, name: vm.albumName)
    }

    private func play(_ songs: [DisplayableSong], from index: Int, source: QueueSource) {
        guard let container, songs.indices.contains(index) else { return }
        Task {
            await container.toastService.perform {
                try await container.playerService.play(tracks: songs, startIndex: index, source: source)
            }
        }
    }
}

// MARK: - Playlist

struct MacPlaylistView: View {
    let playlistId: String

    @Environment(\.appContainer) private var container
    @State private var viewModel: PlaylistDetailViewModel?

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
                        MacPageHeader(
                            coverArtId: vm.coverArtId ?? playlistId,
                            title: vm.name,
                            onPlay: { play(vm.songs, from: 0) },
                            onShuffle: { play(vm.songs.shuffled(), from: 0) }
                        )
                        MacTrackTable(songs: vm.songs) { index in
                            play(vm.songs, from: index)
                        }
                    }
                }
            } else {
                LoadingStateView()
            }
        }
        .navigationTitle(viewModel?.name ?? "")
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

// MARK: - Artist

/// The artist's albums for now; top songs, similar artists and the rest come with #103.
struct MacArtistView: View {
    let artistId: String
    let artistName: String

    @Environment(\.appContainer) private var container
    @State private var viewModel: ArtistDetailViewModel?

    var body: some View {
        Group {
            if let vm = viewModel, !(vm.isLoading && vm.artist == nil) {
                if let error = vm.error, vm.artist == nil {
                    EmptyStateView(
                        systemImage: "exclamationmark.triangle",
                        title: "Unable to Load Artist",
                        subtitle: LocalizedStringKey(error.displayMessage),
                        action: .init(label: "Retry") { Task { await vm.load() } }
                    )
                } else if let albums = vm.artist?.album, !albums.isEmpty {
                    MacAlbumGrid(albums: albums)
                } else {
                    EmptyStateView(
                        systemImage: "square.stack",
                        title: "No Albums",
                        subtitle: "This artist has no albums in the library."
                    )
                }
            } else {
                LoadingStateView()
            }
        }
        .navigationTitle(artistName)
        .task {
            guard viewModel == nil, let container else { return }
            let vm = ArtistDetailViewModel(
                artistId: artistId,
                artistName: artistName,
                libraryService: container.libraryService,
                downloadService: container.downloadService,
                recommendationService: container.recommendationService,
                imageResolver: container.externalArtistImageResolver,
                serverState: container.serverState,
                offlineReader: container.offlineBrowsingReader
            )
            viewModel = vm
            await vm.load()
        }
    }
}
