import SwiftUI
import SwiftData

struct DownloadedView: View {
    @Environment(\.appContainer) private var container
    @State private var filterText = ""
    @AppStorage("minidisc.downloadsSort") private var sort: DownloadsListSort = .name

    var body: some View {
        Group {
            if let serverId = container?.serverState.activeServer?.id {
                DownloadedContent(serverId: serverId, filterText: filterText, sort: $sort)
            } else {
                EmptyStateView(
                    systemImage: "arrow.down.circle",
                    title: "No Server",
                    subtitle: "Connect to a server to manage downloads."
                )
            }
        }
        .minidiscContentWidth()
        .navigationTitle("Downloads")
        .toolbarTitleDisplayMode(.inline)
        .minidiscFilterable(text: $filterText, prompt: "Filter downloads")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                LibrarySortMenu(sort: $sort)
                    .tint(.primary)
            }
        }
    }
}

// MARK: - Content

private struct DownloadedContent: View {
    @Environment(\.appContainer) private var container
    let serverId: UUID
    let filterText: String
    @Binding var sort: DownloadsListSort
    @Query private var albums: [DownloadedAlbum]
    @Query private var playlists: [DownloadedPlaylist]
    @Query private var tracks: [DownloadedTrack]

    init(serverId: UUID, filterText: String, sort: Binding<DownloadsListSort>) {
        self.serverId = serverId
        self.filterText = filterText
        _sort = sort
        let sid = serverId
        _albums = Query(
            filter: #Predicate<DownloadedAlbum> { album in album.serverId == sid },
            sort: [SortDescriptor(\DownloadedAlbum.name)]
        )
        _playlists = Query(
            filter: #Predicate<DownloadedPlaylist> { playlist in playlist.serverId == sid },
            sort: [SortDescriptor(\DownloadedPlaylist.name)]
        )
        _tracks = Query(filter: #Predicate<DownloadedTrack> { track in track.serverId == sid })
    }

    private var displayAlbums: [DownloadedAlbumDisplay] {
        DownloadedAlbumMerger.merge(records: albums, tracks: tracks)
    }

    private var standaloneSongs: [DisplayableSong] {
        let standalone = tracks.filter { $0.albumId == nil }
        let ordered = switch sort {
        case .name: standalone.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .recentlyDownloaded: RecentlyPlayedOrder.byDateThenName(standalone, date: \.downloadedAt, name: \.title)
        }
        return ordered.map { DisplayableSong(from: $0) }
    }

    private func sorted(_ albums: [DownloadedAlbumDisplay]) -> [DownloadedAlbumDisplay] {
        switch sort {
        case .name: albums
        case .recentlyDownloaded: RecentlyPlayedOrder.byDateThenName(albums, date: \.lastDownloadedAt, name: \.name)
        }
    }

    private func sorted(_ playlists: [DownloadedPlaylist]) -> [DownloadedPlaylist] {
        switch sort {
        case .name: playlists.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .recentlyDownloaded: RecentlyPlayedOrder.byDateThenName(playlists, date: \.downloadedAt, name: \.name)
        }
    }

    var body: some View {
        if displayAlbums.isEmpty && playlists.isEmpty && standaloneSongs.isEmpty &&
            container?.downloadActivity.transfers.contains(where: { $0.serverId == serverId }) != true {
            EmptyStateView(
                systemImage: "arrow.down.circle",
                title: "Nothing downloaded",
                subtitle: "Albums and playlists you download will be available here, even offline."
            )
        } else {
            let songs = LibraryFilter.filter(standaloneSongs, by: filterText) { [$0.title, $0.artist, $0.albumName] }
            let albums = sorted(LibraryFilter.filter(displayAlbums, by: filterText) { [$0.name, $0.artist] })
            let orderedPlaylists = sorted(LibraryFilter.filter(playlists, by: filterText) { [$0.name] })
            if LibraryFilter.query(filterText) != nil && songs.isEmpty && albums.isEmpty && orderedPlaylists.isEmpty {
                FilterNoResultsView(query: filterText)
            } else {
                downloadedList(songs: songs, albums: albums, orderedPlaylists: orderedPlaylists)
            }
        }
    }

    private func downloadedList(songs: [DisplayableSong], albums: [DownloadedAlbumDisplay],
                                orderedPlaylists: [DownloadedPlaylist]) -> some View {
        let index = songs.map { AlphabetScrollEntry(id: $0.downloadScrollID, name: $0.title) }
            + albums.map { AlphabetScrollEntry(id: $0.downloadScrollID, name: $0.name) }
            + orderedPlaylists.map { AlphabetScrollEntry(id: $0.downloadScrollID, name: $0.name) }
        // The A–Z bar jumps by name, so using it switches to the name order.
        return AlphabetIndexedContent(entries: index, prepareJump: sort == .name ? nil : { sort = .name }) {
            List {
                DownloadActivitySection(serverID: serverId)
                if !songs.isEmpty {
                    Section("Songs") {
                        ForEach(songs, id: \.downloadScrollID) { song in
                            Button {
                                guard let index = songs.firstIndex(where: { $0.id == song.id }) else { return }
                                Task { await container?.toastService.perform {
                                    try await container?.playerService.play(tracks: songs, startIndex: index, source: .downloads)
                                } }
                            } label: {
                                VStack(alignment: .leading, spacing: MinidiscSpacing.xs) {
                                    Text(song.title).foregroundStyle(.primary)
                                    if let artist = song.artist {
                                        Text(artist).font(.subheadline).foregroundStyle(.secondary)
                                    }
                                }
                                .frame(minHeight: 44, alignment: .leading)
                            }
                            .id(song.downloadScrollID)
                            .accessibilityIdentifier("downloads.song.\(song.id)")
                            .contextMenu {
                                Button("Remove Download", systemImage: "trash", role: .destructive) {
                                    Task { await container?.toastService.perform {
                                        try await container?.downloadService.remove(songId: song.id, serverId: serverId)
                                    } }
                                }
                            }
                        }
                    }
                }
                if !albums.isEmpty {
                    Section("Albums") {
                        ForEach(albums, id: \.downloadScrollID) { display in
                            NavigationLink(value: HomeDestination.downloadedAlbum(display)) {
                                HStack(spacing: MinidiscSpacing.m) {
                                    CoverArtCard(id: display.coverArtId ?? display.albumId, size: 56)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(display.name)
                                            .font(.minidiscCellTitle)
                                            .lineLimit(1)
                                        if let artist = display.artist {
                                            Text(artist)
                                                .font(.minidiscCellSubtitle)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                        Text("\(display.downloadedTracksCount) tracks")
                                            .font(.minidiscCaption)
                                            .foregroundStyle(.tertiary)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.vertical, MinidiscSpacing.xs)
                            }
                            .id(display.downloadScrollID)
                            .accessibilityIdentifier("downloads.album.\(display.albumId)")
                        }
                    }
                }

                if !orderedPlaylists.isEmpty {
                    Section("Playlists") {
                        ForEach(orderedPlaylists, id: \.downloadScrollID) { playlist in
                            NavigationLink(value: HomeDestination.playlistById(id: playlist.playlistId, name: playlist.name, coverArtId: playlist.coverArtId)) {
                                HStack(spacing: MinidiscSpacing.m) {
                                    CoverArtCard(id: playlist.coverArtId ?? playlist.playlistId, size: 56)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(playlist.name)
                                            .font(.minidiscCellTitle)
                                            .lineLimit(1)
                                        Text("\(playlist.tracksCount) tracks\(playlist.isComplete ? "" : " (incomplete)")")
                                            .font(.minidiscCaption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.vertical, MinidiscSpacing.xs)
                            }
                            .id(playlist.downloadScrollID)
                            .accessibilityIdentifier("downloads.playlist.\(playlist.playlistId)")
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }
}

// List must know the same IDs before offscreen rows are created. Giving only
// their child views prefixed anchors leaves those targets unresolved during a jump.
private extension DisplayableSong {
    var downloadScrollID: String { "song:\(id)" }
}

private extension DownloadedAlbumDisplay {
    var downloadScrollID: String { "album:\(id)" }
}

private extension DownloadedPlaylist {
    var downloadScrollID: String { "playlist:\(playlistId)" }
}
