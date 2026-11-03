import SwiftUI
import SwiftSonic

/// One discography group on an artist page ("Albums", "Live Albums", "Appears On"): a header that
/// collapses the list, Play and Shuffle for the whole group, and every album as a vertical row.
struct DiscographySection: View {
    let title: LocalizedStringResource
    let albums: [AlbumID3]
    @Binding var isExpanded: Bool
    /// Other artists' albums: rows name the album artist next to the year.
    var showsAlbumArtist = false
    var isPlayLoading = false
    let onPlay: () -> Void
    let onShuffle: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: MaeksterSpacing.s) {
            header
            if isExpanded {
                LazyVStack(spacing: 0) {
                    ForEach(albums) { album in
                        DiscographyAlbumRow(album: album, showsAlbumArtist: showsAlbumArtist)
                    }
                }
                .transition(.opacity)
            }
        }
    }

    private var header: some View {
        HStack(spacing: MaeksterSpacing.m) {
            Button {
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: MaeksterSpacing.s) {
                    Text(title)
                        .font(.maeksterShelfTitle)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Image(systemName: "chevron.down")
                        .font(.maeksterCaption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isExpanded ? Text("Expanded") : Text("Collapsed"))
            .accessibilityHint(Text("Shows or hides these albums"))
            .accessibilityAddTraits(.isHeader)

            Spacer(minLength: MaeksterSpacing.s)

            Button("Play", systemImage: "play.fill") { onPlay() }
                .buttonStyle(.maeksterCircle(diameter: MaeksterControlSize.compact, isProminent: true))
                .disabled(isPlayLoading || albums.isEmpty)
            Button("Shuffle", systemImage: "shuffle") { onShuffle() }
                .buttonStyle(.maeksterCircle(diameter: MaeksterControlSize.compact))
                .disabled(isPlayLoading || albums.isEmpty)
        }
        .padding(.horizontal, MaeksterSpacing.l)
    }
}

/// Cover, title, "year · N songs" and a chevron; opens the album.
struct DiscographyAlbumRow: View {
    let album: AlbumID3
    var showsAlbumArtist = false

    private static let artworkSize: CGFloat = 56

    private var subtitle: String {
        var parts: [String] = []
        if showsAlbumArtist, let artist = album.artist, !artist.isEmpty { parts.append(artist) }
        if let year = album.year { parts.append(String(year)) }
        if album.songCount > 0 { parts.append(String(localized: "\(album.songCount) songs")) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        NavigationLink(value: HomeDestination.album(album)) {
            HStack(spacing: MaeksterSpacing.m) {
                CoverArtCard(id: album.coverArt ?? album.id, size: Self.artworkSize)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: album.name)
                        .font(.maeksterTrackTitle)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    if !subtitle.isEmpty {
                        Text(verbatim: subtitle)
                            .font(.maeksterMetadata)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: MaeksterSpacing.s)
                Image(systemName: "chevron.right")
                    .font(.maeksterCaption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, MaeksterSpacing.l)
            .padding(.vertical, MaeksterSpacing.s)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("discography.album.\(album.id)")
    }
}

#if DEBUG
#Preview {
    @Previewable @State var albumsExpanded = true
    @Previewable @State var singlesExpanded = false
    MaeksterPreview(container: .preview()) {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: MaeksterSpacing.section) {
                    DiscographySection(
                        title: "Albums",
                        albums: [PreviewFixtures.tidalRooms, PreviewFixtures.paperLanterns].map(PreviewFixtures.withoutSongs),
                        isExpanded: $albumsExpanded,
                        onPlay: {},
                        onShuffle: {}
                    )
                    DiscographySection(
                        title: "Singles",
                        albums: [PreviewFixtures.withoutSongs(PreviewFixtures.glasshouse)],
                        isExpanded: $singlesExpanded,
                        onPlay: {},
                        onShuffle: {}
                    )
                    DiscographySection(
                        title: "Appears On",
                        albums: [PreviewFixtures.withoutSongs(PreviewFixtures.midnightTransit)],
                        isExpanded: .constant(true),
                        showsAlbumArtist: true,
                        onPlay: {},
                        onShuffle: {}
                    )
                }
                .padding(.vertical, MaeksterSpacing.l)
            }
            .background(ArtworkSurfaceBackground(tint: ArtworkSurfacePalette.tint(from: .teal)))
        }
        .environment(\.colorScheme, .dark)
    }
}
#endif
