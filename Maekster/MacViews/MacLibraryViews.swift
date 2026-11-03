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

/// Genres as a column browser, like the Music app: genres, then the chosen genre's styles ("All
/// <genre>" first, with the iPhone's style sort), then the albums for that choice. Double-clicking a
/// genre or style opens all its albums on their own page.
struct MacGenresView: View {
    @Environment(\.appContainer) private var container
    @Environment(MacNavigator.self) private var navigator
    @State private var viewModel: GenreListViewModel?
    @SceneStorage("mac.genres.selectedGenre") private var selectedGenreName: String?
    @State private var selectedStyle: StyleChoice? = .all
    @AppStorage("maekster.genreStyleSort") private var styleSort: GenreListSort = .mostAlbums

    /// "All <genre>" or one of its styles, by name.
    enum StyleChoice: Hashable {
        case all
        case style(String)
    }

    private var selectedGenre: MainGenreSummary? {
        viewModel?.genres.first { $0.name == selectedGenreName }
    }

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
                    browser(genres)
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
        .toolbar {
            if (selectedGenre?.styles.count ?? 0) > 1 {
                LibrarySortMenu(sort: $styleSort)
            }
        }
        .task {
            guard viewModel == nil, let container else { return }
            let vm = GenreListViewModel(library: container.libraryService)
            viewModel = vm
            await vm.load()
            if selectedGenre == nil { selectedGenreName = vm.genres.first?.name }
        }
    }

    private func browser(_ genres: [MainGenreSummary]) -> some View {
        HSplitView {
            List(genres, selection: $selectedGenreName) { genre in
                GenreRow(
                    title: GenreRow.title(genre.isOther ? nil : genre.name),
                    albumCount: genre.albumCount, coverArtId: genre.coverArtId
                )
                .tag(genre.name)
            }
            .contextMenu(forSelectionType: String.self) { _ in
                EmptyView()
            } primaryAction: { names in
                guard let genre = genres.first(where: { names.contains($0.name) }) else { return }
                navigator.open(.genreAlbums(name: genre.isOther ? String(localized: "Other") : genre.name, tags: genre.tags))
            }
            .frame(minWidth: 200, idealWidth: 240)

            Group {
                if let genre = selectedGenre {
                    styleColumn(genre)
                } else {
                    Color.clear
                }
            }
            .frame(minWidth: 200, idealWidth: 260)

            Group {
                if let genre = selectedGenre {
                    MacGenreAlbums(title: title(of: genre, selectedStyle), tags: tags(of: genre, selectedStyle))
                        .id(tags(of: genre, selectedStyle))
                } else {
                    Color.clear
                }
            }
            .frame(minWidth: 360, maxWidth: .infinity)
        }
        .onChange(of: selectedGenreName) { _, _ in selectedStyle = .all }
    }

    private func styleColumn(_ genre: MainGenreSummary) -> some View {
        List(selection: $selectedStyle) {
            GenreRow(
                title: genre.isOther ? Text("All Other Genres") : Text("All \(genre.name)"),
                albumCount: genre.albumCount,
                coverArtId: genre.coverArtId
            )
            .tag(StyleChoice.all)

            if !genre.styles.isEmpty {
                Section("Styles") {
                    ForEach(styleSort.sorted(genre.styles)) { style in
                        GenreRow(title: GenreRow.title(style.name), albumCount: style.albumCount,
                                 coverArtId: style.coverArtId)
                            .tag(StyleChoice.style(style.name))
                    }
                }
            }
        }
        .contextMenu(forSelectionType: StyleChoice.self) { _ in
            EmptyView()
        } primaryAction: { choices in
            guard let choice = choices.first else { return }
            navigator.open(.genreAlbums(name: title(of: genre, choice), tags: tags(of: genre, choice)))
        }
    }

    private func title(of genre: MainGenreSummary, _ choice: StyleChoice?) -> String {
        if case .style(let name) = choice { return name }
        return genre.isOther ? String(localized: "Other") : genre.name
    }

    /// The tags whose albums show: the chosen style's, or the whole genre's.
    private func tags(of genre: MainGenreSummary, _ choice: StyleChoice?) -> [String] {
        if case .style(let name) = choice, let style = genre.styles.first(where: { $0.name == name }) {
            return style.tags
        }
        return genre.tags
    }
}

/// The albums tagged with any of `tags` as a cover grid, through the same view model as the iPhone
/// genre pages: the browser's third column (rebuilt by `.id` when the tags change) and the page a
/// double-clicked genre or style opens.
struct MacGenreAlbums: View {
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
