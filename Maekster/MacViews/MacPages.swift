import AppKit
import SwiftData
import SwiftSonic
import SwiftUI

/// The top of an album or playlist page, like the Music app: a large cover; the title, the
/// artist (a link) and a details line; the description (three lines, the rest in a popover);
/// capsule Play / Shuffle buttons and page-specific round buttons (a heart, a download button, …).
struct MacPageHeader<Accessories: View>: View {
    let coverArtId: String?
    let title: String
    var subtitle: String?
    /// Makes the subtitle a link (the album's artist).
    var onSubtitle: (() -> Void)?
    var details: [String] = []
    /// The album's description from the server.
    var notes: String?
    let onPlay: () -> Void
    let onShuffle: () -> Void
    @ViewBuilder var accessories: () -> Accessories

    @State private var showsNotes = false

    init(coverArtId: String?, title: String, subtitle: String? = nil, onSubtitle: (() -> Void)? = nil,
         details: [String] = [], notes: String? = nil, onPlay: @escaping () -> Void,
         onShuffle: @escaping () -> Void, @ViewBuilder accessories: @escaping () -> Accessories) {
        self.coverArtId = coverArtId
        self.title = title
        self.subtitle = subtitle
        self.onSubtitle = onSubtitle
        self.details = details
        self.notes = notes
        self.onPlay = onPlay
        self.onShuffle = onShuffle
        self.accessories = accessories
    }

    var body: some View {
        HStack(alignment: .top, spacing: MaeksterSpacing.xl) {
            CoverArtCard(id: coverArtId ?? "", size: MacPageHeaderMetrics.coverSize, tier: .hero)
            VStack(alignment: .leading, spacing: MaeksterSpacing.xs) {
                Text(title)
                    .font(.largeTitle.bold())
                    .lineLimit(2)
                    .textSelection(.enabled)
                if let subtitle {
                    if let onSubtitle {
                        Button(subtitle, action: onSubtitle)
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.maeksterAccent)
                            .font(.title2)
                            .onHover { inside in
                                if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                            }
                    } else {
                        Text(subtitle)
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                }
                if !details.isEmpty {
                    Text(details.joined(separator: " · "))
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                if let notes, !notes.isEmpty {
                    notesView(notes)
                        .padding(.top, MaeksterSpacing.m)
                }
                Spacer(minLength: MaeksterSpacing.m)
                HStack(spacing: MaeksterSpacing.m) {
                    Button(action: onPlay) {
                        Label("Play", systemImage: "play.fill")
                            .frame(minWidth: MacPageHeaderMetrics.capsuleMinWidth)
                    }
                    Button(action: onShuffle) {
                        Label("Shuffle", systemImage: "shuffle")
                            .frame(minWidth: MacPageHeaderMetrics.capsuleMinWidth)
                    }
                    accessories()
                        .labelStyle(.iconOnly)
                        .buttonBorderShape(.circle)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .foregroundStyle(Color.maeksterAccent)
                .fontWeight(.semibold)
            }
            .frame(minHeight: MacPageHeaderMetrics.coverSize, alignment: .topLeading)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, MaeksterSpacing.xl)
        .padding(.top, MaeksterSpacing.xl)
        .padding(.bottom, MaeksterSpacing.l)
    }

    /// Three lines; More (or a click) shows the rest in a popover.
    private func notesView(_ notes: String) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: MaeksterSpacing.xs) {
            Text(notes)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .frame(maxWidth: MacPageHeaderMetrics.notesWidth, alignment: .leading)
            Button("More") { showsNotes = true }
                .buttonStyle(.plain)
                .font(.callout.weight(.semibold))
                .popover(isPresented: $showsNotes) {
                    ScrollView {
                        Text(notes)
                            .textSelection(.enabled)
                            .padding(MaeksterSpacing.l)
                    }
                    .frame(width: 420)
                    .frame(maxHeight: 480)
                }
        }
    }
}

extension MacPageHeader where Accessories == EmptyView {
    init(coverArtId: String?, title: String, subtitle: String? = nil, details: [String] = [],
         onPlay: @escaping () -> Void, onShuffle: @escaping () -> Void) {
        self.init(coverArtId: coverArtId, title: title, subtitle: subtitle, details: details,
                  onPlay: onPlay, onShuffle: onShuffle) { EmptyView() }
    }
}

enum MacPageHeaderMetrics {
    static let coverSize: CGFloat = 240
    static let capsuleMinWidth: CGFloat = 96
    static let notesWidth: CGFloat = 620
}

/// Under an album's songs: the release date, song count and length, and the record label.
struct MacAlbumFooter: View {
    let releaseDate: String?
    let summary: String
    let recordLabel: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let releaseDate { Text(verbatim: releaseDate) }
            Text(verbatim: summary)
            if let recordLabel { Text(verbatim: recordLabel) }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, MaeksterSpacing.xl)
        .padding(.vertical, MaeksterSpacing.l)
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
    @State private var notes: String?
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
                    MacSongList(
                        songs: vm.songs,
                        // Only guest artists: the album's own artist is in the header.
                        showsArtist: { $0.artist != nil && $0.artist != vm.artistName },
                        groupsByDisc: true,
                        discTitles: vm.discTitles,
                        onPlay: { index in play(vm.songs, from: index, source: source(vm)) }
                    ) {
                        header(vm)
                    } footer: {
                        footer(vm)
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
        .task(id: albumId) {
            // The description is extra: the page shows without it, offline or on servers without notes.
            guard container?.serverState.isOnline == true, let library = container?.libraryService else { return }
            do {
                notes = try await library.albumNotes(albumID: albumId)?.strippingArtistBioMarkup
            } catch {
                notes = nil
            }
        }
    }

    private func header(_ vm: AlbumDetailViewModel) -> some View {
        var details: [String] = []
        if let genre = vm.genres.first ?? vm.genre { details.append(genre) }
        if let year = vm.year { details.append(String(year)) }
        if let format = Self.format(of: vm.songs) { details.append(format) }
        return MacPageHeader(
            coverArtId: vm.coverArtId,
            title: vm.albumName,
            subtitle: vm.artistName,
            onSubtitle: vm.artistId.map { artistId in
                { navigator.open(.artist(id: artistId, name: vm.artistName ?? "")) }
            },
            details: details,
            notes: notes,
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

    private func footer(_ vm: AlbumDetailViewModel) -> some View {
        MacAlbumFooter(
            releaseDate: Self.releaseDate(vm.releaseDate),
            summary: [String(localized: "\(vm.songs.count) songs"), macTotalDuration(vm.songs)].joined(separator: ", "),
            recordLabel: vm.recordLabels.first
        )
    }

    /// The songs' file format when they share one ("FLAC"), like the Music app's "Lossless".
    private static func format(of songs: [DisplayableSong]) -> String? {
        let formats = Set(songs.compactMap { $0.audioFormat?.uppercased() })
        return formats.count == 1 ? formats.first : nil
    }

    /// A full release date as "4 November 2026"; just a year isn't repeated (the header has it).
    private static func releaseDate(_ date: ItemDate?) -> String? {
        guard let year = date?.year, let month = date?.month, let day = date?.day,
              let value = Calendar.current.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
        return value.formatted(date: .long, time: .omitted)
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
