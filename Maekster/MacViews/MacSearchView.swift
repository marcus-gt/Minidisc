import SwiftData
import SwiftSonic
import SwiftUI

/// What the window shows while the toolbar search field has text: the same ranked matches as the
/// iPhone search (`SearchViewModel`, `LibrarySearchRanking`) in one list, so arrow keys move through
/// them. Return or double-click plays a song or opens an album, artist or playlist; Return in the
/// search field opens the top result.
struct MacSearchView: View {
    let query: String
    /// Bumped by the window when Return is pressed in the search field.
    let submitCount: Int

    @Environment(\.appContainer) private var container
    @Environment(MacNavigator.self) private var navigator
    @State private var viewModel: SearchViewModel?
    @State private var scope: LibrarySearchScope = .all
    @State private var selection = Set<String>()

    var body: some View {
        VStack(spacing: 0) {
            Picker("Search", selection: $scope) {
                ForEach(LibrarySearchScope.allCases) { scope in
                    Text(scope.title).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(MaeksterSpacing.m)

            content
        }
        .navigationTitle("Search")
        .task {
            guard viewModel == nil, let container else { return }
            let vm = SearchViewModel(libraryService: container.libraryService, serverState: container.serverState,
                                     playlistBrowser: container.libraryService)
            viewModel = vm
            await vm.loadPlaylists()
        }
        // Debounced and generation-checked inside the view model; a newer query cancels this one.
        .task(id: query) {
            await viewModel?.search(query: query)
        }
        .onChange(of: submitCount) { _, _ in
            if let top = viewModel?.matches.first { activate(top) }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let vm = viewModel {
            let matches = vm.matches
            if let error = vm.searchError, matches.isEmpty {
                EmptyStateView(
                    systemImage: "exclamationmark.triangle",
                    title: "No Results",
                    subtitle: LocalizedStringKey(error.displayMessage)
                )
            } else if matches.isEmpty {
                if vm.isSearching || vm.resultsQuery != query.trimmingCharacters(in: .whitespaces) {
                    LoadingStateView()
                } else {
                    EmptyStateView(systemImage: "magnifyingglass", title: "No Results")
                }
            } else {
                results(matches)
            }
        } else {
            LoadingStateView()
        }
    }

    private func results(_ matches: [LibrarySearchMatch]) -> some View {
        let best = scope == .all ? matches.first : nil
        var seen = Set<LibrarySearchScope>()
        let groups = matches.map(\.scope).filter { seen.insert($0).inserted }
        return List(selection: $selection) {
            if let best {
                Section("Top Result") { row(best) }
            }
            ForEach(scope == .all ? groups : [scope]) { group in
                let values = matches.filter { $0.scope == group && $0.id != best?.id }
                if !values.isEmpty {
                    Section {
                        ForEach(scope == .all ? Array(values.prefix(5)) : values) { row($0) }
                        if scope == .all, values.count > 5 {
                            Button("See All") { scope = group }
                                .buttonStyle(.link)
                        }
                    } header: {
                        Text(group.title)
                    }
                }
            }
        }
        .contextMenu(forSelectionType: String.self) { ids in
            menu(for: ids, in: matches)
        } primaryAction: { ids in
            guard let match = matches.first(where: { ids.contains($0.id) }) else { return }
            activate(match)
        }
    }

    private func row(_ match: LibrarySearchMatch) -> some View {
        HStack(spacing: MaeksterSpacing.m) {
            artwork(match)
            VStack(alignment: .leading, spacing: 2) {
                Text(match.title)
                Text(match.detail)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
        }
        .tag(match.id)
    }

    @ViewBuilder
    private func artwork(_ match: LibrarySearchMatch) -> some View {
        switch match {
        case .song(let song):
            CoverArtCard(id: song.coverArtId ?? "", size: 40, cornerRadius: MaeksterCornerRadius.xs)
        case .album(let album):
            CoverArtCard(id: album.coverArt ?? album.id, size: 40, cornerRadius: MaeksterCornerRadius.xs)
        case .artist(let artist):
            CoverArtView(id: artist.coverArt ?? artist.id, size: 80, placeholderSystemImage: "person.fill")
                .frame(width: 40, height: 40)
                .clipShape(Circle())
        case .playlist(let playlist):
            PlaylistCoverThumbnail(playlistId: playlist.id, serverId: nil,
                                   coverArtId: playlist.coverArt ?? playlist.id, title: playlist.name, size: 40)
        }
    }

    @ViewBuilder
    private func menu(for ids: Set<String>, in matches: [LibrarySearchMatch]) -> some View {
        let chosen = matches.filter { ids.contains($0.id) }
        let songs = chosen.compactMap { if case .song(let song) = $0 { song } else { nil } }
        if !songs.isEmpty, songs.count == chosen.count, let first = chosen.first {
            MacSongMenu(songs: songs, onPlay: { activate(first) })
        } else if chosen.count == 1, case .artist(let artist) = chosen[0] {
            MacArtistMenu(artistId: artist.id, artistName: artist.name)
        }
    }

    /// Plays a song among the song results (as on iPhone), or opens the item and records it in
    /// Recent.
    private func activate(_ match: LibrarySearchMatch) {
        guard let container, let vm = viewModel else { return }
        switch match {
        case .song(let song):
            let songs = vm.matches.compactMap { if case .song(let value) = $0 { value } else { nil } }
            let start = songs.firstIndex { $0.id == song.id } ?? 0
            let source = QueueSource.search(query: query)
            Task {
                await container.toastService.perform {
                    try await container.playerService.play(tracks: songs, startIndex: start, source: source)
                }
            }
        case .album(let album):
            record(itemId: album.id, itemType: "album", name: album.name, coverArtId: album.coverArt)
            navigator.open(.album(id: album.id))
        case .artist(let artist):
            record(itemId: artist.id, itemType: "artist", name: artist.name, coverArtId: artist.coverArt)
            navigator.open(.artist(id: artist.id, name: artist.name))
        case .playlist(let playlist):
            record(itemId: playlist.id, itemType: "playlist", name: playlist.name, coverArtId: playlist.coverArt)
            navigator.open(.playlist(id: playlist.id))
        }
    }

    private func record(itemId: String, itemType: String, name: String, coverArtId: String?) {
        guard let container, let serverId = container.serverState.activeServer?.id.uuidString else { return }
        Task {
            await container.searchHistoryService.record(
                itemId: itemId, itemType: itemType, displayName: name, coverArtId: coverArtId, serverId: serverId
            )
        }
    }
}

/// Recent albums, artists and playlists opened from search, as suggestions under the empty search
/// field. Choosing one opens it again and moves it to the top.
struct MacRecentSearches: View {
    let serverId: String
    let onOpen: (MacRoute) -> Void

    @Environment(\.appContainer) private var container
    @Query private var entries: [SearchHistoryEntry]

    init(serverId: String, onOpen: @escaping (MacRoute) -> Void) {
        self.serverId = serverId
        self.onOpen = onOpen
        var descriptor = FetchDescriptor<SearchHistoryEntry>(
            predicate: #Predicate { $0.serverId == serverId },
            sortBy: [SortDescriptor(\.visitedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 10
        _entries = Query(descriptor)
    }

    var body: some View {
        ForEach(entries) { entry in
            if let route = route(for: entry) {
                Button {
                    let id = entry.itemId, type = entry.itemType, name = entry.displayName, cover = entry.coverArtId
                    Task {
                        await container?.searchHistoryService.record(
                            itemId: id, itemType: type, displayName: name, coverArtId: cover, serverId: serverId
                        )
                    }
                    onOpen(route)
                } label: {
                    Label(entry.displayName, systemImage: symbol(for: entry))
                }
            }
        }
    }

    private func route(for entry: SearchHistoryEntry) -> MacRoute? {
        switch entry.itemType {
        case "album": .album(id: entry.itemId)
        case "artist": .artist(id: entry.itemId, name: entry.displayName)
        case "playlist": .playlist(id: entry.itemId)
        default: nil
        }
    }

    private func symbol(for entry: SearchHistoryEntry) -> String {
        switch entry.itemType {
        case "artist": "music.mic"
        case "playlist": "music.note.list"
        default: "square.stack"
        }
    }
}
