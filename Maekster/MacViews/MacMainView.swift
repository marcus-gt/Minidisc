import SwiftSonic
import SwiftUI

/// The sections in the sidebar: the server library, then what's on this Mac.
enum MacSidebarItem: String, CaseIterable, Identifiable, Hashable {
    case home
    case albums, artists, songs, playlists, genres
    case downloads, localFiles

    var id: String { rawValue }

    static let top: [Self] = [.home]
    static let library: [Self] = [.albums, .artists, .songs, .playlists, .genres]
    static let onThisMac: [Self] = [.downloads, .localFiles]

    var title: Text {
        switch self {
        case .home: Text("Home")
        case .albums: Text("Albums")
        case .artists: Text("Artists")
        case .songs: Text("Songs")
        case .playlists: Text("Playlists")
        case .genres: Text("Genres")
        case .downloads: Text("Downloaded")
        case .localFiles: Text("Local Files", tableName: "LocalMusic")
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .albums: "square.stack"
        case .artists: "music.mic"
        case .songs: "music.note"
        case .playlists: "music.note.list"
        case .genres: "guitars"
        case .downloads: "arrow.down.circle"
        case .localFiles: "folder"
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
    /// A shelf's See All: every album it holds (Recently Added keeps loading older ones).
    case albumCollection(title: String, albums: [AlbumID3], continuesRecentlyAdded: Bool)
    case playlistCollection(title: String, playlists: [Playlist])
}

/// The main window: library sections in the sidebar, the chosen section (and the pages opened from
/// it) on the right, and the player bar along the bottom.
struct MacMainView: View {
    @SceneStorage("mac.sidebarSelection") private var selection: MacSidebarItem = .home
    @State private var navigator = MacNavigator()
    @State private var playlistAddition = PlaylistAddition()
    @State private var panels = MacPlayerPanels()
    @State private var searchText = ""
    @State private var searchSubmitCount = 0
    @FocusState private var isSearchFocused: Bool
    @Environment(\.appContainer) private var container
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        // The player bar sits below the split view rather than in a safe-area inset: track tables
        // (AppKit tables) ignore the inset, so their last rows ended up behind the bar.
        VStack(spacing: 0) {
            splitView
            MacPlayerBar()
        }
        .environment(navigator)
        .environment(playlistAddition)
        .environment(panels)
        .onAppear { panels.navigator = navigator }
        // Picks up files added to or removed from the local music folders, like the iPhone app.
        .task(id: scenePhase) {
            guard scenePhase == .active, let library = container?.localMusic else { return }
            while !Task.isCancelled {
                await library.refresh()
                do { try await Task.sleep(for: .seconds(30)) } catch { break }
            }
        }
        .focusedSceneValue(\.macPanels, panels)
        .focusedSceneValue(\.macNavigator, navigator)
        .onChange(of: navigator.requestedSection) { _, section in
            // The menu bar asked for a section (File › New Playlist opens Playlists).
            guard let section else { return }
            navigator.requestedSection = nil
            searchText = ""
            panels.showsNowPlaying = false
            selection = section
            navigator.path = NavigationPath()
        }
        .sheet(item: $playlistAddition.request) { request in
            AddToPlaylistSheet(request: request)
                .frame(minWidth: 420, minHeight: 480)
        }
        .modifier(MacSpacebarPlayPause())
    }

    private var splitView: some View {
        NavigationSplitView {
            List(selection: sidebarSelection) {
                ForEach(MacSidebarItem.top) { item in
                    Label { item.title } icon: { Image(systemName: item.systemImage) }
                        .tag(item)
                }
                Section("Library") {
                    ForEach(MacSidebarItem.library) { item in
                        Label { item.title } icon: { Image(systemName: item.systemImage) }
                            .tag(item)
                    }
                }
                Section("Downloads") {
                    ForEach(MacSidebarItem.onThisMac) { item in
                        Label { item.title } icon: { Image(systemName: item.systemImage) }
                            .tag(item)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            // The queue sits beside the page, below the toolbar, so it stays open on every page and
            // beside Now Playing, which covers the page whatever is open.
            HStack(spacing: 0) {
                // Now Playing takes the page's place. The navigator sets the open pages aside while it
                // shows (the split view would keep drawing them on top) and restores them after.
                Group {
                    if panels.showsNowPlaying {
                        MacNowPlayingView()
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
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
            panels.showsNowPlaying = false
            if !navigator.path.isEmpty { navigator.path = NavigationPath() }
        }
        .background {
            // ⌘F focuses the search field, as in the Music app.
            Button("Search") { isSearchFocused = true }
                .keyboardShortcut("f")
                .opacity(0)
                .accessibilityHidden(true)
        }
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
        case .home: MacHomeView()
        case .albums: MacAlbumsView()
        case .artists: MacArtistsView()
        case .songs: MacSongsView()
        case .playlists: MacPlaylistsView()
        case .genres: MacGenresView()
        case .downloads: MacDownloadsView()
        case .localFiles: MacLocalFilesView()
        }
    }

    @ViewBuilder
    private func page(_ route: MacRoute) -> some View {
        switch route {
        case .album(let id): MacAlbumView(albumId: id)
        case .artist(let id, let name): MacArtistView(artistId: id, artistName: name)
        case .playlist(let id): MacPlaylistView(playlistId: id)
        case .genreAlbums(let name, let tags): MacGenreAlbums(title: name, tags: tags)
        case .albumCollection(let title, let albums, let continuesRecentlyAdded):
            MacAlbumCollection(title: title, albums: albums, continuesRecentlyAdded: continuesRecentlyAdded)
        case .playlistCollection(let title, let playlists):
            MacPlaylistCollection(title: title, playlists: playlists)
        }
    }
}
