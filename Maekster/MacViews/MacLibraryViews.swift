import SwiftSonic
import SwiftUI

/// Loading, error and empty states for the Mac lists, in the iPhone app's words.
struct MacListState<Content: View>: View {
    let isLoading: Bool
    let error: UserFacingError?
    let isEmpty: Bool
    let errorTitle: LocalizedStringKey
    let emptyImage: String
    let emptyTitle: LocalizedStringKey
    var emptySubtitle: LocalizedStringKey? = "Your library appears to be empty."
    let retry: () async -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        if isLoading && isEmpty {
            LoadingStateView()
        } else if let error, isEmpty {
            EmptyStateView(
                systemImage: "exclamationmark.triangle",
                title: errorTitle,
                subtitle: LocalizedStringKey(error.displayMessage),
                action: .init(label: "Retry") { Task { await retry() } }
            )
        } else if isEmpty {
            EmptyStateView(systemImage: emptyImage, title: emptyTitle, subtitle: emptySubtitle)
        } else {
            content()
        }
    }
}

// MARK: - Albums

struct MacAlbumsView: View {
    @Environment(\.appContainer) private var container
    @State private var viewModel: AlbumListViewModel?

    var body: some View {
        Group {
            if let vm = viewModel {
                MacListState(
                    isLoading: vm.isLoading, error: vm.error, isEmpty: vm.albums.isEmpty,
                    errorTitle: "Unable to Load Albums", emptyImage: "square.stack", emptyTitle: "No Albums",
                    retry: vm.load
                ) {
                    MacAlbumGrid(albums: vm.albums)
                }
            } else {
                LoadingStateView()
            }
        }
        .navigationTitle("Albums")
        .task {
            guard viewModel == nil, let container else { return }
            let vm = AlbumListViewModel(libraryService: container.libraryService)
            viewModel = vm
            await vm.load()
        }
    }
}

/// Album covers in a scrolling adaptive grid; each opens its album page.
struct MacAlbumGrid: View {
    let albums: [AlbumID3]

    var body: some View {
        ScrollView {
            MacAlbumGridContent(albums: albums)
                .padding(MaeksterSpacing.l)
        }
    }
}

/// The grid itself, for pages that scroll several sections together.
struct MacAlbumGridContent: View {
    let albums: [AlbumID3]

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: MaeksterSpacing.l)],
            spacing: MaeksterSpacing.l
        ) {
            ForEach(albums, id: \.id) { album in
                NavigationLink(value: MacRoute.album(id: album.id)) {
                    AlbumGridCell(album: album)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Artists

struct MacArtistsView: View {
    @Environment(\.appContainer) private var container
    @State private var viewModel: ArtistListViewModel?

    var body: some View {
        Group {
            if let vm = viewModel {
                MacListState(
                    isLoading: vm.isLoading, error: vm.error, isEmpty: vm.indexes.isEmpty,
                    errorTitle: "Unable to Load Artists", emptyImage: "music.mic", emptyTitle: "No Artists",
                    retry: vm.load
                ) {
                    List {
                        ForEach(vm.indexes, id: \.name) { index in
                            Section(index.name) {
                                ForEach(index.artist, id: \.id) { artist in
                                    NavigationLink(value: MacRoute.artist(id: artist.id, name: artist.name)) {
                                        ArtistRow(artist: artist)
                                    }
                                    .contextMenu { MacArtistMenu(artistId: artist.id, artistName: artist.name) }
                                }
                            }
                        }
                    }
                }
            } else {
                LoadingStateView()
            }
        }
        .navigationTitle("Artists")
        .task {
            guard viewModel == nil, let container else { return }
            let vm = ArtistListViewModel(libraryService: container.libraryService)
            viewModel = vm
            await vm.load()
        }
    }
}

// MARK: - Songs

struct MacSongsView: View {
    @Environment(\.appContainer) private var container
    @State private var viewModel: SongsListViewModel?

    var body: some View {
        Group {
            if let vm = viewModel {
                MacListState(
                    isLoading: vm.isLoading, error: vm.error, isEmpty: vm.displaySongs.isEmpty,
                    errorTitle: "Unable to Load Songs", emptyImage: "music.note", emptyTitle: "No Songs",
                    retry: { await vm.load(sort: .title) }
                ) {
                    MacTrackTable(songs: vm.displaySongs) { index in
                        play(vm.displaySongs, from: index)
                    }
                }
            } else {
                LoadingStateView()
            }
        }
        .navigationTitle("Songs")
        .task {
            guard viewModel == nil, let container else { return }
            let vm = SongsListViewModel(libraryService: container.libraryService)
            viewModel = vm
            await vm.load(sort: .title)
        }
    }

    private func play(_ songs: [DisplayableSong], from index: Int) {
        guard let container else { return }
        Task {
            await container.toastService.perform {
                try await container.playerService.play(tracks: songs, startIndex: index, source: .songs)
            }
        }
    }
}

// MARK: - Genres

/// Genres and their album counts; each opens its genre page.
struct MacGenresView: View {
    @Environment(\.appContainer) private var container
    @State private var viewModel: GenreListViewModel?

    var body: some View {
        Group {
            switch viewModel?.state {
            case nil, .loading?:
                LoadingStateView()
            case .waitingForIndex?:
                EmptyStateView(
                    systemImage: "guitars",
                    title: "Still Indexing Your Library",
                    subtitle: "Genres appear once maekster has indexed every album. Try again shortly."
                )
            case .failed(let error)?:
                EmptyStateView(
                    systemImage: "exclamationmark.triangle",
                    title: "Unable to Load Genres",
                    subtitle: LocalizedStringKey(error.displayMessage),
                    action: .init(label: "Retry") { Task { await viewModel?.load() } }
                )
            case .loaded?:
                if let genres = viewModel?.genres, !genres.isEmpty {
                    List(genres) { genre in
                        NavigationLink(value: MacRoute.genre(genre)) {
                            GenreRow(
                                title: GenreRow.title(genre.isOther ? nil : genre.name),
                                albumCount: genre.albumCount, coverArtId: genre.coverArtId
                            )
                        }
                    }
                } else {
                    EmptyStateView(
                        systemImage: "guitars",
                        title: "No Genres",
                        subtitle: "None of your albums are tagged with a genre."
                    )
                }
            }
        }
        .navigationTitle("Genres")
        .task {
            guard viewModel == nil, let container else { return }
            let vm = GenreListViewModel(library: container.libraryService)
            viewModel = vm
            await vm.load()
        }
    }
}

/// One main genre, like the iPhone page: "All <genre>", then its styles with their own sort. Each
/// opens its albums.
struct MacGenreView: View {
    let genre: MainGenreSummary
    @AppStorage("maekster.genreStyleSort") private var sort: GenreListSort = .mostAlbums

    private var title: String { genre.isOther ? String(localized: "Other") : genre.name }

    var body: some View {
        List {
            Section {
                NavigationLink(value: MacRoute.genreAlbums(name: title, tags: genre.tags)) {
                    GenreRow(
                        title: genre.isOther ? Text("All Other Genres") : Text("All \(genre.name)"),
                        albumCount: genre.albumCount,
                        coverArtId: genre.coverArtId
                    )
                }
            }
            if !genre.styles.isEmpty {
                Section("Styles") {
                    ForEach(sort.sorted(genre.styles)) { style in
                        NavigationLink(value: MacRoute.genreAlbums(name: style.name, tags: style.tags)) {
                            GenreRow(title: GenreRow.title(style.name), albumCount: style.albumCount,
                                     coverArtId: style.coverArtId)
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
        .toolbar {
            if genre.styles.count > 1 {
                LibrarySortMenu(sort: $sort)
            }
        }
    }
}

/// The albums tagged with any of `tags` (a whole genre or one style), through the same view model
/// as the iPhone genre pages.
struct MacGenreAlbumsView: View {
    let title: String
    let tags: [String]

    @Environment(\.appContainer) private var container
    @State private var viewModel: AlbumCollectionViewModel?

    var body: some View {
        Group {
            switch viewModel?.state {
            case nil, .loading?:
                LoadingStateView()
            case .waitingForIndex?:
                EmptyStateView(
                    systemImage: "guitars",
                    title: "Still Indexing Your Library",
                    subtitle: "Genres appear once maekster has indexed every album. Try again shortly."
                )
            case .failed(let error)?:
                EmptyStateView(
                    systemImage: "exclamationmark.triangle",
                    title: "Unable to Load Albums",
                    subtitle: LocalizedStringKey(error.displayMessage),
                    action: .init(label: "Retry") { Task { await viewModel?.load() } }
                )
            case .loaded?:
                MacAlbumGrid(albums: viewModel?.albums ?? [])
            }
        }
        .navigationTitle(title)
        .task {
            guard viewModel == nil, let container else { return }
            let vm = AlbumCollectionViewModel(kind: .genreGroup(name: title, tags: tags), library: container.libraryService)
            viewModel = vm
            await vm.load()
        }
    }
}
