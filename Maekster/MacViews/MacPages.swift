import SwiftData
import SwiftSonic
import SwiftUI

/// Cover, title and Play / Shuffle above an album's or playlist's songs, with room for page-specific
/// buttons (a heart, a download button, …) after them.
struct MacPageHeader<Accessories: View>: View {
    let coverArtId: String?
    let title: String
    var subtitle: String?
    /// Makes the subtitle a link (the album's artist).
    var onSubtitle: (() -> Void)?
    var details: [String] = []
    let onPlay: () -> Void
    let onShuffle: () -> Void
    @ViewBuilder var accessories: () -> Accessories

    var body: some View {
        HStack(alignment: .bottom, spacing: MaeksterSpacing.xl) {
            CoverArtCard(id: coverArtId ?? "", size: 200, tier: .hero)
            VStack(alignment: .leading, spacing: MaeksterSpacing.s) {
                Text(title)
                    .font(.largeTitle.bold())
                    .lineLimit(2)
                    .textSelection(.enabled)
                if let subtitle {
                    if let onSubtitle {
                        Button(subtitle, action: onSubtitle)
                            .buttonStyle(.link)
                            .font(.title2)
                    } else {
                        Text(subtitle)
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                }
                if !details.isEmpty {
                    Text(details.joined(separator: " · "))
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: MaeksterSpacing.m) {
                    Button("Play", systemImage: "play.fill", action: onPlay)
                        .buttonStyle(.borderedProminent)
                        .tint(Color.maeksterAccent)
                    Button("Shuffle", systemImage: "shuffle", action: onShuffle)
                        .buttonStyle(.bordered)
                    accessories()
                        .buttonStyle(.bordered)
                        .labelStyle(.iconOnly)
                }
                .controlSize(.large)
                .padding(.top, MaeksterSpacing.s)
            }
            Spacer(minLength: 0)
        }
        .padding(MaeksterSpacing.xl)
    }
}

extension MacPageHeader where Accessories == EmptyView {
    init(coverArtId: String?, title: String, subtitle: String? = nil, details: [String] = [],
         onPlay: @escaping () -> Void, onShuffle: @escaping () -> Void) {
        self.init(coverArtId: coverArtId, title: title, subtitle: subtitle, details: details,
                  onPlay: onPlay, onShuffle: onShuffle) { EmptyView() }
    }
}

/// The total length of some songs, like "1 hr 4 min".
func macTotalDuration(_ songs: [DisplayableSong]) -> String {
    let seconds = songs.reduce(0) { $0 + $1.duration }
    return Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
}

// MARK: - Album

struct MacAlbumView: View {
    let albumId: String

    @Environment(\.appContainer) private var container
    @Environment(MacNavigator.self) private var navigator
    @State private var viewModel: AlbumDetailViewModel?
    @State private var confirmsRemoval = false
    /// Observed, like the iPhone album page, so the heart follows every star and unstar.
    @Query private var favoriteMatches: [FavoriteRecord]

    init(albumId: String) {
        self.albumId = albumId
        let compositeId = "\(FavoriteType.album.rawValue):\(albumId)"
        _favoriteMatches = Query(filter: #Predicate<FavoriteRecord> { $0.id == compositeId })
    }

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
                        header(vm)
                        MacTrackTable(
                            songs: vm.songs, showsAlbum: false, groupsByDisc: true, discTitles: vm.discTitles
                        ) { index in
                            play(vm.songs, from: index, source: source(vm))
                        }
                    }
                }
            } else {
                LoadingStateView()
            }
        }
        .navigationTitle(viewModel?.albumName ?? "")
        .alert("Remove downloaded album?", isPresented: $confirmsRemoval) {
            Button("Remove", role: .destructive) { Task { await viewModel?.deleteDownload() } }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The audio files will be deleted from this device.")
        }
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

    private func header(_ vm: AlbumDetailViewModel) -> some View {
        var details: [String] = []
        if let year = vm.year { details.append(String(year)) }
        if let genre = vm.genres.first ?? vm.genre { details.append(genre) }
        if !vm.songs.isEmpty {
            details.append(String(localized: "\(vm.songs.count) songs"))
            details.append(macTotalDuration(vm.songs))
        }
        return MacPageHeader(
            coverArtId: vm.coverArtId,
            title: vm.albumName,
            subtitle: vm.artistName,
            onSubtitle: vm.artistId.map { artistId in
                { navigator.open(.artist(id: artistId, name: vm.artistName ?? "")) }
            },
            details: details,
            onPlay: { play(vm.songs, from: 0, source: source(vm)) },
            onShuffle: { play(vm.songs.shuffled(), from: 0, source: source(vm)) }
        ) {
            favoriteButton
            downloadButton(vm)
        }
    }

    @ViewBuilder
    private var favoriteButton: some View {
        if let favorites = container?.favoritesService {
            let isFavorite = !favoriteMatches.isEmpty
            Button(isFavorite ? "Remove from Favorites" : "Add to Favorites",
                   systemImage: isFavorite ? "heart.fill" : "heart") {
                Task {
                    if isFavorite {
                        try? await favorites.unstar(itemType: .album, itemId: albumId)
                    } else {
                        try? await favorites.star(itemType: .album, itemId: albumId)
                    }
                }
            }
            .foregroundStyle(isFavorite ? Color.maeksterAccent : .primary)
            .help(isFavorite ? "Remove from Favorites" : "Add to Favorites")
        }
    }

    /// The same states as the iPhone album page (`AlbumDownloadControlState`).
    private func downloadButton(_ vm: AlbumDetailViewModel) -> some View {
        let state = AlbumDownloadControlState(
            songs: vm.songs, isOffline: vm.isOffline, isDownloading: vm.isDownloadingAlbum
        )
        return Button {
            switch state {
            case .unavailable: break
            case .download: Task { await vm.downloadAlbum() }
            case .downloadMissing: Task { await vm.downloadMissingTracks() }
            case .cancel: Task { await vm.cancelAlbumDownload() }
            case .removeDownloaded: confirmsRemoval = true
            }
        } label: {
            Label(state.title, systemImage: state.systemImage)
        }
        .disabled(state == .unavailable)
        .help(Text(state.title))
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

// MARK: - Artist

/// Portrait, Play / Shuffle and the biography, then top songs, the artist's releases by category,
/// albums they appear on, and similar artists in the library.
struct MacArtistView: View {
    let artistId: String
    let artistName: String

    @Environment(\.appContainer) private var container
    @State private var viewModel: ArtistDetailViewModel?

    private var source: QueueSource { .artist(id: artistId, name: artistName) }

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
                } else {
                    content(vm)
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
            // Same order as the iPhone artist page.
            await vm.load()
            await vm.loadAppearances()
            async let artistInfo: Void = vm.loadArtistInfo()
            await vm.loadTopSongs()
            await vm.loadSimilarArtists()
            await artistInfo
        }
    }

    private func content(_ vm: ArtistDetailViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MaeksterSpacing.xxl) {
                header(vm)

                if !vm.topSongs.isEmpty {
                    section("Top Songs") {
                        let songs = Array(vm.topSongs.prefix(10))
                        MacSongRows(songs: songs) { index in play(songs, from: index) }
                    }
                }

                ForEach(vm.releaseShelves) { shelf in
                    section(shelf.category.title) {
                        MacAlbumGridContent(albums: shelf.albums)
                    }
                }

                if !vm.appearsOn.isEmpty {
                    section("Appears On") {
                        MacAlbumGridContent(albums: vm.appearsOn)
                    }
                }

                let similar = vm.similarArtists.filter(\.inLibrary)
                if !similar.isEmpty {
                    section("Similar Artists") {
                        ScrollView(.horizontal) {
                            HStack(alignment: .top, spacing: MaeksterSpacing.l) {
                                ForEach(similar) { artist in
                                    NavigationLink(value: MacRoute.artist(id: artist.id, name: artist.name)) {
                                        SimilarArtistCell(
                                            recommendation: artist, externalImageURL: nil, size: 120,
                                            onOutOfLibraryTap: {}
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .scrollIndicators(.never)
                    }
                }
            }
            .padding(MaeksterSpacing.xl)
        }
    }

    private func header(_ vm: ArtistDetailViewModel) -> some View {
        HStack(alignment: .center, spacing: MaeksterSpacing.xl) {
            CoverArtView(id: vm.artist?.coverArt ?? artistId, size: 360, placeholderSystemImage: "person.fill")
                .frame(width: 180, height: 180)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: MaeksterSpacing.s) {
                Text(vm.artist?.name ?? artistName)
                    .font(.largeTitle.bold())
                    .textSelection(.enabled)
                if let count = vm.artist?.albumCount, count > 0 {
                    Text("\(count) albums")
                        .foregroundStyle(.secondary)
                }
                if let biography = vm.biography {
                    Text(biography)
                        .lineLimit(4)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 640, alignment: .leading)
                        .help(biography)
                }
                HStack(spacing: MaeksterSpacing.m) {
                    Button("Play", systemImage: "play.fill") { Task { await playAll(vm, shuffled: false) } }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.maeksterAccent)
                    Button("Shuffle", systemImage: "shuffle") { Task { await playAll(vm, shuffled: true) } }
                        .buttonStyle(.bordered)
                    if vm.isPlayLoading { ProgressView().controlSize(.small) }
                }
                .controlSize(.large)
                .padding(.top, MaeksterSpacing.s)
            }
        }
    }

    private func section<Content: View>(
        _ title: LocalizedStringResource, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: MaeksterSpacing.m) {
            Text(title)
                .font(.title2.bold())
            content()
        }
    }

    private func play(_ songs: [DisplayableSong], from index: Int) {
        guard let container, songs.indices.contains(index) else { return }
        Task {
            await container.toastService.perform {
                try await container.playerService.play(tracks: songs, startIndex: index, source: source)
            }
        }
    }

    /// Like the iPhone artist page: downloaded tracks offline, credited tracks for a credit-only
    /// artist, otherwise every track the server has for the artist.
    private func playAll(_ vm: ArtistDetailViewModel, shuffled: Bool) async {
        guard let container else { return }
        vm.isPlayLoading = true
        defer { vm.isPlayLoading = false }
        var tracks: [DisplayableSong]
        if vm.isOffline, !vm.offlineTracks.isEmpty {
            tracks = vm.offlineTracks
        } else if vm.isCreditOnly, !vm.appearanceSongs.isEmpty {
            tracks = vm.appearanceSongs
        } else {
            do {
                tracks = try await container.libraryService.fetchAllTracks(forArtistID: artistId)
            } catch MaeksterError.artistTracksUnavailable {
                container.toastService.showError(
                    String(localized: "Unable to load artist tracks. Please check your connection and try again.")
                )
                return
            } catch {
                if !UserFacingError.isCancellation(error) {
                    container.toastService.showError(String(localized: "Playback failed. Please try again."))
                }
                return
            }
        }
        if shuffled { tracks.shuffle() }
        await container.toastService.perform {
            try await container.playerService.play(tracks: tracks, startIndex: 0, source: source)
        }
    }
}
