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

    private func notesView(_ notes: String) -> some View {
        MacExpandableText(text: notes, lineLimit: 3)
            .frame(maxWidth: MacPageHeaderMetrics.notesWidth, alignment: .leading)
    }
}

/// Text cut to `lineLimit` lines, with More opening the whole text in a popover.
struct MacExpandableText: View {
    let text: String
    let lineLimit: Int

    @State private var showsAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: MaeksterSpacing.xs) {
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(lineLimit)
            Button("More") { showsAll = true }
                .buttonStyle(.plain)
                .font(.callout.weight(.semibold))
                .popover(isPresented: $showsAll) {
                    ScrollView {
                        Text(text)
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
            VStack(alignment: .leading, spacing: MaeksterSpacing.section) {
                hero(vm)

                latestAndTopSongs(vm)

                ForEach(vm.releaseShelves) { shelf in
                    MacShelf(
                        title: Text(shelf.category.title),
                        items: Array(shelf.albums.prefix(MacShelfMetrics.limit)),
                        seeAll: shelf.albums.count > MacShelfMetrics.limit
                            ? .albumCollection(title: String(localized: shelf.category.title), albums: shelf.albums,
                                               continuesRecentlyAdded: false)
                            : nil
                    ) { MacAlbumShelfCell(album: $0) }
                }

                MacShelf(
                    title: Text("Appears On"),
                    items: Array(vm.appearsOn.prefix(MacShelfMetrics.limit)),
                    seeAll: vm.appearsOn.count > MacShelfMetrics.limit
                        ? .albumCollection(title: String(localized: "Appears On"), albums: vm.appearsOn,
                                           continuesRecentlyAdded: false)
                        : nil
                ) { MacAlbumShelfCell(album: $0) }

                if let biography = vm.biography {
                    about(biography, vm: vm)
                }

                MacShelf(title: Text("Similar Artists"), items: vm.similarArtists.filter(\.inLibrary),
                         cellWidth: MacShelfMetrics.artistWidth) { artist in
                    MacArtistShelfCell(artist: ArtistID3(id: artist.id, name: artist.name, coverArt: artist.coverArt))
                }
            }
            .padding(.bottom, MaeksterSpacing.xl)
        }
    }

    // MARK: Hero

    /// The artist's photo across the page, fading into the page at the bottom, with the name and
    /// Play / Shuffle over it. Without a photo, the newest album's cover, blurred, fills it instead.
    private func hero(_ vm: ArtistDetailViewModel) -> some View {
        let photo = vm.artist?.coverArt
        let fallback = Self.latestRelease(vm)?.coverArt
        return Color.clear
            .frame(height: MacArtistMetrics.heroHeight)
            .frame(maxWidth: .infinity)
            .background {
                // The (square) image as wide as the page, cropped to the hero's height a little
                // below its top, where faces usually are.
                GeometryReader { geometry in
                    let side = max(geometry.size.width, MacArtistMetrics.heroHeight)
                    Group {
                        if let photo {
                            CoverArtView(id: photo, size: MacArtistMetrics.heroImageSize, tier: .hero,
                                         placeholderSystemImage: "person.fill")
                        } else if let fallback {
                            CoverArtView(id: fallback, size: 600, tier: .hero)
                                .blur(radius: 40)
                                .saturation(1.2)
                        } else {
                            Color.secondary.opacity(0.2)
                        }
                    }
                    .frame(width: geometry.size.width, height: side)
                    .offset(y: -(side - MacArtistMetrics.heroHeight) * MacArtistMetrics.heroFocus)
                }
                .clipped()
            }
            .overlay {
                // Darkens toward the bottom so the name reads, then melts into the page.
                LinearGradient(
                    stops: [.init(color: .clear, location: 0.35),
                            .init(color: .black.opacity(0.55), location: 0.8),
                            .init(color: Color(nsColor: .windowBackgroundColor), location: 1)],
                    startPoint: .top, endPoint: .bottom
                )
            }
            .overlay(alignment: .bottomLeading) {
                HStack(alignment: .center, spacing: MaeksterSpacing.m) {
                    Button { Task { await playAll(vm, shuffled: false) } } label: {
                        Label("Play", systemImage: "play.fill")
                    }
                    .buttonStyle(.maeksterCircle(diameter: MaeksterControlSize.large, isProminent: true))
                    .help("Play")
                    Text(vm.artist?.name ?? artistName)
                        .font(.system(size: MacArtistMetrics.nameSize, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.4), radius: 8, y: 2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .textSelection(.enabled)
                    Button { Task { await playAll(vm, shuffled: true) } } label: {
                        Label("Shuffle", systemImage: "shuffle")
                    }
                    .buttonStyle(.maeksterCircle(diameter: MaeksterControlSize.regular))
                    .help("Shuffle")
                    if vm.isPlayLoading { ProgressView().controlSize(.small) }
                    Spacer(minLength: 0)
                    MacArtistFavoriteButton(artistId: artistId)
                }
                .padding(.horizontal, MaeksterSpacing.xl)
                .padding(.bottom, MaeksterSpacing.l)
            }
            .clipped()
    }

    // MARK: Latest release and top songs

    @ViewBuilder
    private func latestAndTopSongs(_ vm: ArtistDetailViewModel) -> some View {
        let latest = Self.latestRelease(vm)
        let songs = Array(vm.topSongs.prefix(9))
        if latest != nil || !songs.isEmpty {
            HStack(alignment: .top, spacing: MaeksterSpacing.xl) {
                if let latest {
                    VStack(alignment: .leading, spacing: MaeksterSpacing.s) {
                        Text("Latest Release")
                            .font(.maeksterShelfTitle)
                        NavigationLink(value: MacRoute.album(id: latest.id)) {
                            HStack(alignment: .top, spacing: MaeksterSpacing.m) {
                                CoverArtCard(id: latest.coverArt ?? latest.id, size: MacArtistMetrics.latestCover)
                                VStack(alignment: .leading, spacing: 2) {
                                    if let year = latest.year {
                                        Text(verbatim: String(year))
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(latest.name)
                                        .font(.maeksterCellTitle)
                                        .lineLimit(3)
                                    Text("\(latest.songCount) songs")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(width: MacArtistMetrics.latestTextWidth, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                if !songs.isEmpty {
                    VStack(alignment: .leading, spacing: MaeksterSpacing.s) {
                        Text("Top Songs")
                            .font(.maeksterShelfTitle)
                        MacSongRows(songs: songs) { index in play(songs, from: index) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, MaeksterSpacing.xl)
        }
    }

    /// The artist's newest album, single or EP by year (then by when it was added).
    private static func latestRelease(_ vm: ArtistDetailViewModel) -> AlbumID3? {
        vm.releaseShelves.flatMap(\.albums).max { lhs, rhs in
            ((lhs.year ?? 0), lhs.created ?? .distantPast) < ((rhs.year ?? 0), rhs.created ?? .distantPast)
        }
    }

    // MARK: About

    private func about(_ biography: String, vm: ArtistDetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: MaeksterSpacing.s) {
            Text("About")
                .font(.maeksterShelfTitle)
            HStack(alignment: .top, spacing: MaeksterSpacing.xxl) {
                MacExpandableText(text: biography, lineLimit: 6)
                    .frame(maxWidth: MacPageHeaderMetrics.notesWidth, alignment: .leading)
                if let count = vm.artist?.albumCount, count > 0 {
                    Text("\(count) albums")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, MaeksterSpacing.xl)
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

/// The heart on the artist page, observed like the album page's so it follows every change.
private struct MacArtistFavoriteButton: View {
    let artistId: String

    @Environment(\.appContainer) private var container
    @Query private var favoriteMatches: [FavoriteRecord]

    init(artistId: String) {
        self.artistId = artistId
        let compositeId = "\(FavoriteType.artist.rawValue):\(artistId)"
        _favoriteMatches = Query(filter: #Predicate<FavoriteRecord> { $0.id == compositeId })
    }

    var body: some View {
        if let favorites = container?.favoritesService {
            let isFavorite = !favoriteMatches.isEmpty
            Button {
                Task {
                    if isFavorite {
                        try? await favorites.unstar(itemType: .artist, itemId: artistId)
                    } else {
                        try? await favorites.star(itemType: .artist, itemId: artistId)
                    }
                }
            } label: {
                Label(isFavorite ? "Remove from Favorites" : "Add to Favorites",
                      systemImage: isFavorite ? "heart.fill" : "heart")
            }
            .buttonStyle(.maeksterCircle(diameter: MaeksterControlSize.regular))
            .help(isFavorite ? "Remove from Favorites" : "Add to Favorites")
        }
    }
}

private enum MacArtistMetrics {
    static let heroHeight: CGFloat = 380
    /// How far down the image the hero's crop sits: 0 is the top, 0.5 the middle.
    static let heroFocus: CGFloat = 0.2
    /// Pixels asked of the server for the photo: wide windows need a large one.
    static let heroImageSize = 1600
    static let nameSize: CGFloat = 40
    static let latestCover: CGFloat = 140
    static let latestTextWidth: CGFloat = 150
}
