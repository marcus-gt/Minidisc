import SwiftUI

/// The library sections in the sidebar.
enum MacSidebarItem: String, CaseIterable, Identifiable, Hashable {
    case albums, artists, songs, playlists, genres

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .albums: "Albums"
        case .artists: "Artists"
        case .songs: "Songs"
        case .playlists: "Playlists"
        case .genres: "Genres"
        }
    }

    var systemImage: String {
        switch self {
        case .albums: "square.stack"
        case .artists: "music.mic"
        case .songs: "music.note"
        case .playlists: "music.note.list"
        case .genres: "guitars"
        }
    }
}

/// Pages pushed onto a section's navigation stack.
enum MacRoute: Hashable {
    case album(id: String)
    case artist(id: String, name: String)
    case playlist(id: String)
    /// Every album tagged with any of `tags`: a whole genre or one of its styles.
    case genreAlbums(name: String, tags: [String])
}

/// The main window: library sections in the sidebar, the chosen section (and the pages opened from
/// it) on the right, and the player bar along the bottom.
struct MacMainView: View {
    @SceneStorage("mac.sidebarSelection") private var selection: MacSidebarItem = .albums
    @State private var navigator = MacNavigator()
    @State private var playlistAddition = PlaylistAddition()
    @State private var panels = MacPlayerPanels()
    @State private var searchText = ""
    @State private var searchSubmitCount = 0
    @FocusState private var isSearchFocused: Bool
    @Environment(\.appContainer) private var container

    var body: some View {
        NavigationSplitView {
            List(selection: sidebarSelection) {
                Section("Library") {
                    ForEach(MacSidebarItem.allCases) { item in
                        Label(item.title, systemImage: item.systemImage)
                            .tag(item)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            // The queue sits beside the page, below the toolbar, so it stays open on every page and
            // beside Now Playing, which covers the page whatever is open.
            HStack(spacing: 0) {
                // Now Playing replaces the page rather than drawing over it: a track table is an AppKit
                // view and drew above a SwiftUI overlay. The page stays loaded, only hidden.
                ZStack {
                    NavigationStack(path: $navigator.path) {
                        Group {
                            if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                                section(selection)
                            } else {
                                MacSearchView(query: searchText, submitCount: searchSubmitCount)
                            }
                        }
                        .navigationDestination(for: MacRoute.self, destination: page)
                    }
                    .opacity(panels.showsNowPlaying ? 0 : 1)
                    .allowsHitTesting(!panels.showsNowPlaying)
                    .accessibilityHidden(panels.showsNowPlaying)

                    if panels.showsNowPlaying {
                        MacNowPlayingView()
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if panels.showsQueue {
                    Divider()
                    MacQueuePanel()
                        .frame(width: 340)
                        .transition(.move(edge: .trailing))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: panels.showsQueue)
            .animation(.easeInOut(duration: 0.25), value: panels.showsNowPlaying)
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "Artists, albums, songs, playlists…")
        .searchFocused($isSearchFocused)
        .searchSuggestions {
            if searchText.isEmpty, let serverId = container?.serverState.activeServer?.id.uuidString {
                MacRecentSearches(serverId: serverId) { route in
                    isSearchFocused = false
                    navigator.open(route)
                }
            }
        }
        .onSubmit(of: .search) { searchSubmitCount += 1 }
        .onChange(of: searchText) { _, _ in
            // A new search starts from its results, not from a page opened from the last one.
            if !navigator.path.isEmpty { navigator.path = NavigationPath() }
            panels.showsNowPlaying = false
        }
        .background {
            // ⌘F focuses the search field, as in the Music app.
            Button("Search") { isSearchFocused = true }
                .keyboardShortcut("f")
                .opacity(0)
                .accessibilityHidden(true)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            MacPlayerBar()
        }
        .environment(navigator)
        .environment(playlistAddition)
        .environment(panels)
        .sheet(item: $playlistAddition.request) { request in
            AddToPlaylistSheet(request: request)
                .frame(minWidth: 420, minHeight: 480)
        }
        .modifier(MacSpacebarPlayPause())
    }

    /// Picking a section starts it from its list, not from a page opened earlier.
    private var sidebarSelection: Binding<MacSidebarItem?> {
        Binding(
            get: { selection },
            set: { newValue in
                guard let newValue else { return }
                // Picking a section leaves search and Now Playing, even the section already selected.
                searchText = ""
                panels.showsNowPlaying = false
                guard newValue != selection else { return }
                selection = newValue
                navigator.path = NavigationPath()
            }
        )
    }

    @ViewBuilder
    private func section(_ item: MacSidebarItem) -> some View {
        switch item {
        case .albums: MacAlbumsView()
        case .artists: MacArtistsView()
        case .songs: MacSongsView()
        case .playlists: MacPlaylistsView()
        case .genres: MacGenresView()
        }
    }

    @ViewBuilder
    private func page(_ route: MacRoute) -> some View {
        switch route {
        case .album(let id): MacAlbumView(albumId: id)
        case .artist(let id, let name): MacArtistView(artistId: id, artistName: name)
        case .playlist(let id): MacPlaylistView(playlistId: id)
        case .genreAlbums(let name, let tags): MacGenreAlbums(title: name, tags: tags)
        }
    }
}
