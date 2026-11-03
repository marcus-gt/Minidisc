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
            NavigationStack(path: $navigator.path) {
                section(selection)
                    .navigationDestination(for: MacRoute.self, destination: page)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            MacPlayerBar()
        }
        .environment(navigator)
        .environment(playlistAddition)
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
                guard let newValue, newValue != selection else { return }
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
