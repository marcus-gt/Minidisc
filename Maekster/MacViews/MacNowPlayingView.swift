import SwiftData
import SwiftSonic
import SwiftUI

/// What the player bar opens: the Now Playing view in the content area, its lyrics, and the queue
/// inspector.
@Observable
final class MacPlayerPanels {
    var showsNowPlaying = false
    var showsLyrics = false
    var showsQueue = false
}

/// Large artwork on the artwork-coloured background, like the iPhone player: the song with links to
/// its artist and album, a heart, Smart Shuffle and Instant Mix, and synced lyrics beside the cover
/// when they're switched on.
struct MacNowPlayingView: View {
    @Environment(\.appContainer) private var container
    @Environment(DominantColorExtractor.self) private var colorExtractor
    @Environment(MacNavigator.self) private var navigator
    @Environment(MacPlayerPanels.self) private var panels
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var colors = FullPlayerViewModel()
    @State private var lyricsViewModel: LyricsViewModel?

    var body: some View {
        if let state = container?.playerState {
            content(state)
                .background {
                    LinearGradient(colors: PlayerBackgroundPalette.colors(from: colors.backgroundColors),
                                   startPoint: .top, endPoint: .bottom)
                        .ignoresSafeArea()
                }
                .environment(\.colorScheme, .dark)
                .task(id: coverArtId(state)) {
                    await colors.updateColors(for: coverArtId(state), colorExtractor: colorExtractor,
                                              container: container, reduceMotion: reduceMotion)
                }
                .task(id: lyricsKey(state)) { await loadLyrics(state) }
        }
    }

    private func content(_ state: PlayerState) -> some View {
        HStack(spacing: MaeksterSpacing.xxxl) {
            VStack(alignment: .leading, spacing: MaeksterSpacing.l) {
                CoverArtView(id: coverArtId(state) ?? "", size: 1200, tier: .hero, cornerRadius: MaeksterCornerRadius.large)
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: 520, maxHeight: 520)
                    .shadow(radius: 24, y: 8)
                if let track = state.currentTrack {
                    details(track)
                }
            }
            .frame(maxWidth: .infinity)

            if panels.showsLyrics {
                lyrics(state)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
            }
        }
        .padding(MaeksterSpacing.xxxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.2), value: panels.showsLyrics)
    }

    private func details(_ track: DisplayableSong) -> some View {
        VStack(alignment: .leading, spacing: MaeksterSpacing.s) {
            Text(track.title)
                .font(.title.bold())
                .lineLimit(2)
                .textSelection(.enabled)
            HStack(spacing: MaeksterSpacing.xs) {
                if let artist = track.artist {
                    if let artistId = track.artistId {
                        Button(artist) { open(.artist(id: artistId, name: artist)) }
                    } else {
                        Text(artist)
                    }
                }
                if track.artist != nil, track.albumName != nil {
                    Text(verbatim: "·")
                }
                if let album = track.albumName {
                    if let albumId = track.albumId {
                        Button(album) { open(.album(id: albumId)) }
                    } else {
                        Text(album)
                    }
                }
            }
            .buttonStyle(.plain)
            .font(.title3)
            .foregroundStyle(.secondary)
            .lineLimit(1)

            HStack(spacing: MaeksterSpacing.m) {
                MacFavoriteSongButton(songId: track.id)
                Button("Smart Shuffle", systemImage: "shuffle") {
                    guard let container else { return }
                    Task { await container.toastService.perform { try await container.playerService.playSmartShuffle() } }
                }
                if !track.isLocalFile {
                    Button("Instant Mix", systemImage: instantMixSymbol) {
                        startInstantMix(from: .song(id: track.id), using: container, startingWith: track)
                    }
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .padding(.top, MaeksterSpacing.s)
        }
        .frame(maxWidth: 520, alignment: .leading)
    }

    @ViewBuilder
    private func lyrics(_ state: PlayerState) -> some View {
        if state.currentTrack?.isLocalFile == true {
            EmptyStateView(systemImage: "quote.bubble", title: "Lyrics")
        } else if let lyricsViewModel {
            LyricsView(viewModel: lyricsViewModel)
                .mask(
                    LinearGradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.06),
                        .init(color: .black, location: 0.92),
                        .init(color: .clear, location: 1)
                    ], startPoint: .top, endPoint: .bottom)
                )
        } else {
            LoadingStateView()
        }
    }

    /// Opens an artist or album page, leaving Now Playing.
    private func open(_ route: MacRoute) {
        panels.showsNowPlaying = false
        navigator.open(route)
    }

    private func coverArtId(_ state: PlayerState) -> String? {
        state.isLiveStream ? state.currentRadio?.coverArt : (state.currentTrack?.coverArtId ?? state.currentTrack?.id)
    }

    private func lyricsKey(_ state: PlayerState) -> String {
        "\(panels.showsLyrics)|\(state.currentTrack?.id ?? "")|\(container?.lyricsSettings.source.rawValue ?? "")"
    }

    /// One view model per song, like the iPhone player; only while lyrics are shown.
    private func loadLyrics(_ state: PlayerState) async {
        guard panels.showsLyrics, let track = state.currentTrack, !track.isLocalFile, let container,
              let serverId = container.serverState.activeServer?.id else {
            lyricsViewModel = nil
            return
        }
        let vm = LyricsViewModel(
            track: track,
            serverId: serverId,
            source: container.lyricsSettings.source,
            lyricsService: container.lyricsService,
            playerService: container.playerService,
            playerState: state,
            settings: container.lyricsSettings
        )
        lyricsViewModel = vm
        await vm.load()
    }
}

/// A heart for the playing song that follows every star and unstar (a query on its favourite record).
struct MacFavoriteSongButton: View {
    let songId: String

    @Environment(\.appContainer) private var container
    @Query private var favoriteMatches: [FavoriteRecord]

    init(songId: String) {
        self.songId = songId
        let compositeId = "\(FavoriteType.song.rawValue):\(songId)"
        _favoriteMatches = Query(filter: #Predicate<FavoriteRecord> { $0.id == compositeId })
    }

    var body: some View {
        let isFavorite = !favoriteMatches.isEmpty
        Button(isFavorite ? "Remove from Favorites" : "Add to Favorites",
               systemImage: isFavorite ? "heart.fill" : "heart") {
            guard let favorites = container?.favoritesService else { return }
            Task {
                if isFavorite {
                    try? await favorites.unstar(itemType: .song, itemId: songId)
                } else {
                    try? await favorites.star(itemType: .song, itemId: songId)
                }
            }
        }
        .labelStyle(.iconOnly)
        .foregroundStyle(isFavorite ? Color.maeksterAccent : .primary)
        .help(isFavorite ? "Remove from Favorites" : "Add to Favorites")
    }
}
