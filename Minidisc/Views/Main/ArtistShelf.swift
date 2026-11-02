import OSLog
import SwiftSonic
import SwiftUI

/// Home's "Artist Picks" (#63): today's blend of favourite, dormant and untried artists, as
/// round portraits. Tapping one opens the artist; the menu starts their radio or shuffles them.
struct ArtistShelf: View {
    @Environment(\.appContainer) private var container
    @State private var artists: [ArtistID3] = []
    @State private var isLoading = true

    private var serverID: UUID? { container?.serverState.activeServer?.id }

    var body: some View {
        Group {
            if isLoading && artists.isEmpty {
                placeholder
            } else if !artists.isEmpty {
                MaeksterShelf {
                    header
                } content: {
                    ForEach(artists, id: \.id) { artist in
                        ArtistShelfCell(artist: artist)
                    }
                }
            }
        }
        .accessibilityIdentifier(HomeSection.artists.shelfIdentifier)
        .task(id: serverID) { await load() }
    }

    private var header: some View {
        MaeksterCarouselHeader(HomeSection.artists.title, showsChevron: false)
            .accessibilityAddTraits(.isHeader)
    }

    private var placeholder: some View {
        VStack(alignment: .leading, spacing: MaeksterSpacing.s) {
            header
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: MaeksterSpacing.m) {
                    ForEach(0..<6, id: \.self) { _ in
                        VStack(spacing: MaeksterSpacing.xs) {
                            SkeletonBlock(width: MaeksterCarouselMetrics.artistArtwork,
                                          height: MaeksterCarouselMetrics.artistArtwork,
                                          cornerRadius: MaeksterCarouselMetrics.artistArtwork / 2)
                            SkeletonBlock(width: 72, height: 11, cornerRadius: 4)
                        }
                    }
                }
                .padding(.horizontal, MaeksterSpacing.l)
            }
            .scrollDisabled(true)
        }
        .allowsHitTesting(false)
    }

    private func load() async {
        guard let container, let serverID else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let picked = try await container.artistShelfService.artists(serverID: serverID)
            // A server switch while loading leaves this pick to the next task.
            guard !Task.isCancelled, container.serverState.activeServer?.id == serverID else { return }
            artists = picked
        } catch {
            guard !UserFacingError.isCancellation(error) else { return }
            Logger.library.error("[ARTIST-SHELF] load failed: \(error, privacy: .public)")
        }
    }
}

/// One portrait: opens the artist; long-press for radio, shuffle and pin.
private struct ArtistShelfCell: View {
    let artist: ArtistID3
    @Environment(\.appContainer) private var container

    private static let size = MaeksterCarouselMetrics.artistArtwork

    var body: some View {
        NavigationLink(value: HomeDestination.artist(artist)) {
            ArtistPortraitCell(name: artist.name, size: Self.size) {
                CoverArtView(id: artist.coverArt ?? artist.id, size: Int(Self.size * 2), placeholderSystemImage: "person.fill")
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.artists.\(artist.id)")
        .contextMenu {
            Button("Artist Radio", systemImage: instantMixSymbol) {
                startInstantMix(from: .artist(id: artist.id), using: container, titled: artist.name)
            }
            Button("Shuffle", systemImage: "shuffle") {
                Task { await shuffle() }
            }
            PinMenuButton(itemType: .artist, itemId: artist.id, displayName: artist.name,
                          displaySubtitle: "", coverArtId: artist.coverArt)
        }
    }

    private func shuffle() async {
        guard let container else { return }
        do {
            let tracks = try await container.libraryService.fetchAllTracks(forArtistID: artist.id)
            try await container.playerService.play(tracks: tracks.shuffled(), startIndex: 0,
                                                    source: .artist(id: artist.id, name: artist.name))
        } catch MaeksterError.artistTracksUnavailable {
            container.toastService.showError(String(localized: "Unable to load artist tracks. Please check your connection and try again."))
        } catch {
            guard !UserFacingError.isCancellation(error) else { return }
            container.toastService.showError(String(localized: "Playback failed. Please try again."))
        }
    }
}
