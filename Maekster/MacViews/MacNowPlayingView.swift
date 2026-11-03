import SwiftData
import SwiftSonic
import SwiftUI

/// What the player bar opens: Now Playing over the content, and the side panel with the queue or
/// the lyrics.
@Observable
final class MacPlayerPanels {
    enum SidePanel: Hashable {
        case queue, lyrics
    }

    var showsNowPlaying = false
    var sidePanel: SidePanel?

    /// The player bar's Queue and Lyrics buttons: open that tab, or close the panel if it's showing.
    func toggle(_ panel: SidePanel) {
        sidePanel = sidePanel == panel ? nil : panel
    }
}

/// The right-hand panel beside the page, below the toolbar: Queue and Lyrics tabs, like the Music app.
struct MacSidePanel: View {
    @Environment(MacPlayerPanels.self) private var panels

    var body: some View {
        VStack(spacing: 0) {
            Picker("Queue", selection: Binding(
                get: { panels.sidePanel ?? .queue },
                set: { panels.sidePanel = $0 }
            )) {
                Text("Queue").tag(MacPlayerPanels.SidePanel.queue)
                Text("Lyrics").tag(MacPlayerPanels.SidePanel.lyrics)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(MaeksterSpacing.m)

            switch panels.sidePanel {
            case .lyrics?:
                // Part of the same panel as the queue, so the same surface and text colour.
                MacLyricsContent()
                    .padding(.horizontal, MaeksterSpacing.m)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .environment(\.maeksterLyricsColor, .primary)
                    .environment(\.maeksterLyricsFont, .system(.title3, weight: .bold))
            default:
                MacQueueView()
            }
        }
    }
}

/// The playing song's artwork colours as a gradient, like the iPhone player (the shared
/// `FullPlayerViewModel` and `PlayerBackgroundPalette`).
struct MacArtworkBackground: View {
    @Environment(\.appContainer) private var container
    @Environment(DominantColorExtractor.self) private var colorExtractor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var colors = FullPlayerViewModel()

    var body: some View {
        LinearGradient(colors: PlayerBackgroundPalette.colors(from: colors.backgroundColors),
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
            .task(id: coverArtId) {
                await colors.updateColors(for: coverArtId, colorExtractor: colorExtractor,
                                          container: container, reduceMotion: reduceMotion)
            }
    }

    private var coverArtId: String? {
        guard let state = container?.playerState else { return nil }
        return macCoverArtId(state)
    }
}

/// The cover of what's playing: the radio's or the song's.
@MainActor
func macCoverArtId(_ state: PlayerState) -> String? {
    state.isLiveStream ? state.currentRadio?.coverArt : (state.currentTrack?.coverArtId ?? state.currentTrack?.id)
}

/// Synced lyrics for the playing song (LRCLIB or server, per the lyrics setting) through the shared
/// `LyricsView`: one view model per song, like the iPhone player. White text on the artwork
/// background unless `maeksterLyricsColor` says otherwise.
struct MacLyricsContent: View {
    @Environment(\.appContainer) private var container
    @State private var viewModel: LyricsViewModel?

    var body: some View {
        Group {
            if container?.playerState.currentTrack?.isLocalFile == true || container?.playerState.isLiveStream == true {
                EmptyStateView(systemImage: "music.note.list", title: "No lyrics available")
            } else if let viewModel {
                LyricsView(viewModel: viewModel)
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
        .task(id: loadKey) { await load() }
    }

    private var loadKey: String {
        "\(container?.playerState.currentTrack?.id ?? "")|\(container?.lyricsSettings.source.rawValue ?? "")"
    }

    private func load() async {
        guard let container, let track = container.playerState.currentTrack, !track.isLocalFile,
              let serverId = container.serverState.activeServer?.id else {
            viewModel = nil
            return
        }
        let vm = LyricsViewModel(
            track: track,
            serverId: serverId,
            source: container.lyricsSettings.source,
            lyricsService: container.lyricsService,
            playerService: container.playerService,
            playerState: container.playerState,
            settings: container.lyricsSettings
        )
        viewModel = vm
        await vm.load()
    }
}

/// Over the page, beside the side panel: large artwork on the artwork-coloured background, like the
/// iPhone player, with the song (links to its artist and album), a heart, Smart Shuffle and Instant
/// Mix, and the synced lyrics beside the cover unless the side panel already shows them. × or Esc
/// closes it.
struct MacNowPlayingView: View {
    @Environment(\.appContainer) private var container
    @Environment(MacNavigator.self) private var navigator
    @Environment(MacPlayerPanels.self) private var panels

    var body: some View {
        if let state = container?.playerState {
            content(state)
                .background { MacArtworkBackground() }
                .overlay(alignment: .topTrailing) { closeButton }
                .environment(\.colorScheme, .dark)
        }
    }

    private func content(_ state: PlayerState) -> some View {
        HStack(spacing: MaeksterSpacing.xxxl) {
            VStack(alignment: .leading, spacing: MaeksterSpacing.l) {
                CoverArtView(id: macCoverArtId(state) ?? "", size: 1200, tier: .hero,
                             cornerRadius: MaeksterCornerRadius.large)
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: 520, maxHeight: 520)
                    .shadow(radius: 24, y: 8)
                if let track = state.currentTrack {
                    details(track)
                }
            }
            .frame(maxWidth: .infinity)

            if panels.sidePanel != .lyrics {
                MacLyricsContent()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(MaeksterSpacing.xxxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    /// Closes Now Playing; Esc does too.
    private var closeButton: some View {
        Button {
            panels.showsNowPlaying = false
        } label: {
            Label("Close", systemImage: "xmark")
                .labelStyle(.iconOnly)
                .font(.title3.weight(.semibold))
                .frame(width: 32, height: 32)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.cancelAction)
        .help("Close")
        .padding(MaeksterSpacing.l)
    }

    /// Opens an artist or album page, leaving Now Playing.
    private func open(_ route: MacRoute) {
        panels.showsNowPlaying = false
        navigator.open(route)
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
