import SwiftUI
import SwiftSonic
import OSLog

struct FavoritesView: View {
    @Environment(\.appContainer) private var container
    @Environment(PlaylistAddition.self) private var playlistAddition
    @State private var viewModel: FavoritesViewModel?
    @State private var filterText = ""
    @AppStorage("minidisc.favoritesSort") private var sort: FavoritesListSort = .name
    @State private var recentlyPlayed = RecentlyPlayedOrder()

    var body: some View {
        Group {
            if let vm = viewModel {
                content(vm)
            } else {
                LoadingStateView()
            }
        }
        .minidiscContentWidth()
        .navigationTitle("Favorites")
        .toolbarTitleDisplayMode(.inline)
        .minidiscFilterable(text: $filterText, prompt: "Filter favorites")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                LibrarySortMenu(sort: $sort)
                    .tint(.primary)
            }
        }
        .recentlyPlayedOrder($recentlyPlayed, when: sort == .recentlyPlayed)
        .task(id: container?.serverState.accessSnapshot) {
            guard let svc = container?.libraryService else { return }
            if viewModel == nil { viewModel = FavoritesViewModel(libraryService: svc) }
            if container?.serverState.isOnline == true { await viewModel?.load() }
        }
    }

    @ViewBuilder
    private func content(_ vm: FavoritesViewModel) -> some View {
        let offline = container?.serverState.isOnline == false
        let favorites = offline ? container?.offlineLibrary.snapshot.favorites ?? HomeFavorites()
            : HomeFavorites(songs: vm.songs, albums: vm.albums, artists: vm.artists)
        let isEmpty = favorites.songs.isEmpty && favorites.albums.isEmpty && favorites.artists.isEmpty
        if !offline && vm.isLoading && isEmpty {
            LoadingStateView()
        } else if offline && isEmpty {
            OfflineBrowsingEmptyView()
        } else if let error = vm.error, isEmpty {
            EmptyStateView(
                systemImage: "exclamationmark.triangle",
                title: "Unable to Load Favorites",
                subtitle: LocalizedStringKey(error.displayMessage),
                action: .init(label: "Retry") { Task { await vm.load() } }
            )
        } else if isEmpty {
            EmptyStateView(
                systemImage: "heart",
                title: "No favorites yet",
                subtitle: "Songs, albums, and artists you favorite will appear here."
            )
        } else {
            let displayableSongs = sortedSongs(LibraryFilter.filter(favorites.songs, by: filterText) {
                [$0.title, $0.artist, $0.album]
            }).map { DisplayableSong(from: $0) }
            let albums = sortedAlbums(LibraryFilter.filter(favorites.albums, by: filterText) { [$0.name, $0.artist] })
            let artists = sortedArtists(LibraryFilter.filter(favorites.artists, by: filterText) { [$0.name] })
            if displayableSongs.isEmpty && albums.isEmpty && artists.isEmpty {
                FilterNoResultsView(query: filterText)
            } else {
                favoritesList(songs: displayableSongs, albums: albums, artists: artists, viewModel: vm, offline: offline)
            }
        }
    }

    private func favoritesList(songs displayableSongs: [DisplayableSong], albums: [AlbumID3], artists: [ArtistID3],
                               viewModel vm: FavoritesViewModel, offline: Bool) -> some View {
        let index = displayableSongs.map { AlphabetScrollEntry(id: $0.favoriteScrollID, name: $0.title) }
            + albums.map { AlphabetScrollEntry(id: $0.favoriteScrollID, name: $0.sortName ?? $0.name) }
            + artists.map { AlphabetScrollEntry(id: $0.favoriteScrollID, name: $0.sortName ?? $0.name) }
        // The A–Z bar jumps by name, so using it switches to the name order.
        return AlphabetIndexedContent(entries: index, prepareJump: sort == .name ? nil : { sort = .name }) {
            List {
                songsSection(displayableSongs)
                albumsSection(albums)
                artistsSection(artists)
            }
            .listStyle(.plain)
            .refreshable {
                if offline { await container?.offlineLibrary.refresh() }
                else { await vm.load() }
            }
        }
    }

    // MARK: - Sorting

    private func sortedSongs(_ songs: [Song]) -> [Song] {
        switch sort {
        case .name: SongSort.title.sorted(songs)
        case .recentlyFavorited: RecentlyPlayedOrder.byDateThenName(songs, date: \.starred, name: \.title)
        case .recentlyPlayed: SongSort.recentlyPlayed.sorted(songs)
        }
    }

    private func sortedAlbums(_ albums: [AlbumID3]) -> [AlbumID3] {
        switch sort {
        case .name: AlbumSort.name.sorted(albums)
        case .recentlyFavorited: RecentlyPlayedOrder.byDateThenName(albums, date: \.starred) { $0.sortName ?? $0.name }
        case .recentlyPlayed: AlbumSort.recentlyPlayed.sorted(albums, recentlyPlayed: recentlyPlayed)
        }
    }

    private func sortedArtists(_ artists: [ArtistID3]) -> [ArtistID3] {
        switch sort {
        case .name: ArtistSort.name.sorted(artists)
        case .recentlyFavorited: RecentlyPlayedOrder.byDateThenName(artists, date: \.starred) { $0.sortName ?? $0.name }
        case .recentlyPlayed: ArtistSort.recentlyPlayed.sorted(artists, recentlyPlayed: recentlyPlayed)
        }
    }

    @ViewBuilder
    private func songsSection(_ songs: [DisplayableSong]) -> some View {
        if !songs.isEmpty {
            Section {
                HStack(spacing: MinidiscSpacing.m) {
                    Button {
                        HapticFeedback.medium.trigger()
                        Task {
                            await container?.toastService.perform { try await container?.playerService.play(tracks: songs, startIndex: 0, source: .favorites) }
                        }
                    } label: {
                        Label("Play", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, MinidiscSpacing.s)
                    }

                    Button {
                        HapticFeedback.medium.trigger()
                        Task {
                            let idx = Int.random(in: 0..<songs.count)
                            await container?.toastService.perform { try await container?.playerService.play(tracks: songs, startIndex: idx, source: .favorites) }
                            if container?.playerState.isShuffled != true {
                                await container?.playerService.toggleShuffle()
                            }
                        }
                    } label: {
                        Label("Shuffle", systemImage: "shuffle")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, MinidiscSpacing.s)
                    }
                }
                .buttonStyle(.bordered)
                .tint(.minidiscAccent)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .padding(.vertical, 4)

                ForEach(Array(songs.enumerated()), id: \.element.favoriteScrollID) { index, song in
                    SongRow(song: song, index: index + 1, showCoverArt: true, isFavorite: true, onAddToPlaylist: playlistAddition.present)
                        .id(song.favoriteScrollID)
                        .accessibilityIdentifier("favorites.song.\(song.id)")
                        .contentShape(Rectangle())
                        .onTapGesture {
                            Task {
                                do {
                                    try await container?.playerService.play(tracks: songs, startIndex: index, source: .favorites)
                                } catch {
                                    Logger.player.error("[PLAYBACK] play failed: \(error, privacy: .public)")
                                    if !UserFacingError.isCancellation(error) {
                                        container?.toastService.showError(UserFacingError.from(error).displayMessage)
                                    }
                                }
                            }
                        }
                }
            }
        }
    }

    @ViewBuilder
    private func albumsSection(_ albums: [AlbumID3]) -> some View {
        if !albums.isEmpty {
            Section("Albums") {
                ForEach(albums, id: \.favoriteScrollID) { album in
                    NavigationLink(value: HomeDestination.album(album)) {
                        AlbumRow(
                            albumId: album.id,
                            name: album.name,
                            artist: album.artist,
                            year: album.year,
                            coverArtId: album.coverArt
                        )
                    }
                    .id(album.favoriteScrollID)
                }
            }
        }
    }

    @ViewBuilder
    private func artistsSection(_ artists: [ArtistID3]) -> some View {
        if !artists.isEmpty {
            Section("Artists") {
                ForEach(artists, id: \.favoriteScrollID) { artist in
                    NavigationLink(value: HomeDestination.artist(artist)) {
                        ArtistRow(artist: artist)
                    }
                    .id(artist.favoriteScrollID)
                }
            }
        }
    }
}

private extension DisplayableSong {
    var favoriteScrollID: String { "song:\(id)" }
}

private extension AlbumID3 {
    var favoriteScrollID: String { "album:\(id)" }
}

private extension ArtistID3 {
    var favoriteScrollID: String { "artist:\(id)" }
}
