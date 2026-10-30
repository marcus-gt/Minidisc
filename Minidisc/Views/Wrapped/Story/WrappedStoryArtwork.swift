import SwiftUI

/// A slide's background from its #1's artwork (#75): the cover, blurred and darkened over the
/// slide's gradient. Without artwork (outside the library, or none on the server) the gradient stays.
struct WrappedArtBackdrop: View {
    let artworkID: String?
    let palette: [Color]

    @Environment(ArtworkImageCache.self) private var artworkImageCache
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var image: PlatformImage?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                MeshGradientBackground(palette: palette, animated: !reduceMotion)
                if let image {
                    Image(platformImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .blur(radius: 40, opaque: true)
                        .opacity(0.9)
                        .transition(.opacity)
                    LinearGradient(colors: [.black.opacity(0.2), .black.opacity(0.65)], startPoint: .top, endPoint: .bottom)
                }
            }
        }
        .ignoresSafeArea()
        .task(id: artworkID) {
            guard let artworkID, WrappedIDs.isLibraryID(artworkID) else { image = nil; return }
            let loaded = await artworkImageCache.load(coverArtId: artworkID, tier: .hero)
            withAnimation(.easeIn(duration: 0.3)) { image = loaded }
        }
    }
}

/// A tilted wall of the year's top album covers behind the intro and closing slides (#75).
struct WrappedCoverMosaic: View {
    let artworkIDs: [String]
    let palette: [Color]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let columns = 3
    private static let tileCount = 15

    /// The covers repeated to fill the wall when there are fewer than it holds.
    private var tiles: [String] {
        let library = artworkIDs.filter(WrappedIDs.isLibraryID)
        guard !library.isEmpty else { return [] }
        return (0..<Self.tileCount).map { library[$0 % library.count] }
    }

    var body: some View {
        GeometryReader { proxy in
            let side = proxy.size.width / CGFloat(Self.columns) * 1.15
            ZStack {
                MeshGradientBackground(palette: palette, animated: !reduceMotion)
                if !tiles.isEmpty {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(side), spacing: MinidiscSpacing.s), count: Self.columns),
                              spacing: MinidiscSpacing.s) {
                        ForEach(tiles.indices, id: \.self) { index in
                            CoverArtCard(id: tiles[index], size: side, cornerRadius: MinidiscCornerRadius.standard)
                        }
                    }
                    .rotationEffect(.degrees(-12))
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .opacity(0.45)
                    LinearGradient(colors: [.black.opacity(0.35), .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                }
            }
            .clipped()
        }
        .ignoresSafeArea()
    }
}

/// The maekster mark on the story (#75). The slides are colourful and photographic, so the brand
/// rules call for the one-colour white mark rather than the full-colour one.
struct WrappedBrandMark: View {
    let width: CGFloat

    /// The mark's own proportions (947 × 434).
    static let aspectRatio: CGFloat = 947 / 434

    var body: some View {
        Image("BrandMarkMono")
            .resizable()
            .renderingMode(.template)
            .foregroundStyle(.white)
            .aspectRatio(Self.aspectRatio, contentMode: .fit)
            .frame(width: max(width, 20))
            .accessibilityHidden(true)
    }
}

/// The mark and name at the foot of the middle slides (#75).
struct WrappedBrandFooter: View {
    let year: Int

    var body: some View {
        HStack(spacing: MinidiscSpacing.s) {
            WrappedBrandMark(width: 28)
            Text(verbatim: "maekster · \(year)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
        }
        .accessibilityHidden(true)
    }
}

/// One of #2–5 under a slide's #1 (#75).
struct WrappedRunnerUpRow: View {
    let rank: Int
    let artworkID: String
    let title: String
    let subtitle: String?
    let detail: String
    var isArtist = false

    private static let thumbnail: CGFloat = 44

    var body: some View {
        HStack(spacing: MinidiscSpacing.m) {
            Text(verbatim: "\(rank)")
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 22)
            Group {
                if WrappedIDs.isLibraryID(artworkID) {
                    CoverArtCard(id: artworkID, size: Self.thumbnail,
                                 cornerRadius: isArtist ? Self.thumbnail / 2 : MinidiscCornerRadius.s,
                                 placeholderSystemImage: isArtist ? "person.fill" : "music.note")
                } else {
                    RoundedRectangle(cornerRadius: isArtist ? Self.thumbnail / 2 : MinidiscCornerRadius.s)
                        .fill(.white.opacity(0.15))
                        .frame(width: Self.thumbnail, height: Self.thumbnail)
                        .overlay {
                            Image(systemName: isArtist ? "person.fill" : "music.note").foregroundStyle(.white.opacity(0.6))
                        }
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Text(detail)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

/// The slide header ("YOUR #1 TRACK").
struct WrappedSlideLabel: View {
    let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .heavy, design: .rounded))
            .tracking(2.5)
            .foregroundStyle(.white.opacity(0.7))
    }
}

private enum WrappedStoryPreviewData {
    static let data: WrappedData = {
        let calendar = Calendar.current
        let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let artists = ["Keith Jarrett", "Bill Evans Trio", "Steely Dan", "Chet Baker", "Moses Boyd", "nthng"]
        let plays = (0..<300).map { index in
            let artist = artists[(index * index) % 23 % artists.count]
            return WrappedPlay(timestamp: start.addingTimeInterval(Double(index) * 80_000), trackId: "\(artist)-\(index % 4)",
                               trackTitle: "Köln, January 24, 1975, Part \(index % 4 + 1)", albumId: "\(artist)-album",
                               albumTitle: "The \(artist) Album", artistId: artist, artistName: artist,
                               genre: ["Jazz", "Jazz", "Electronic", "Ambient", "Rock", "Soul", "Jazz"][index % 7],
                               durationListened: 300, trackDuration: 300)
        }
        return WrappedAggregator.aggregate(plays: plays, period: .year(2026), serverId: "s",
                                           periodRange: WrappedPeriod.year(2026).dateRange(in: calendar), calendar: calendar)
    }()
    static let palette = WrappedYearPalette.colors(for: 2026)
    static let genres: [TopGenreEntry] = {
        let calendar = Calendar.current
        let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let plays = (0..<300).map { index in
            WrappedPlay(timestamp: start.addingTimeInterval(Double(index) * 80_000), trackId: "t", trackTitle: "t",
                        albumId: "a\(index % 5)", albumTitle: nil, artistId: nil, artistName: "a",
                        genre: ["Jazz", "Jazz", "Jazz", "Electronic", "Electronic", "Ambient", "Rock", "Soul", "Hip-Hop"][index % 9],
                        durationListened: 200, trackDuration: 200)
        }
        return WrappedAggregator.topGenres(from: plays, limit: 5)
    }()
    static let container = try? AppContainer(inMemory: true, userDefaults: UserDefaults(suiteName: "wrapped-story-preview")!)
}

private extension View {
    /// Covers need the artwork cache; without a server they show their placeholders.
    func wrappedStoryPreviewEnvironment() -> some View {
        environment(WrappedStoryPreviewData.container!.artworkImageCache)
            .environment(WrappedStoryPreviewData.container!.dominantColorExtractor)
    }
}

#Preview("Top track") {
    WrappedTopTrackSlide(data: WrappedStoryPreviewData.data, palette: WrappedStoryPreviewData.palette)
        .wrappedStoryPreviewEnvironment()
}

#Preview("Top artist") {
    WrappedTopArtistSlide(data: WrappedStoryPreviewData.data, palette: WrappedStoryPreviewData.palette)
        .wrappedStoryPreviewEnvironment()
}

#Preview("Intro") {
    WrappedIntroSlide(year: 2026, palette: WrappedStoryPreviewData.palette,
                      artworkIDs: WrappedStoryPreviewData.data.topAlbums.map(\.albumId))
        .wrappedStoryPreviewEnvironment()
}

#Preview("Genre") {
    WrappedTopGenreSlide(data: WrappedStoryPreviewData.data, palette: WrappedStoryPreviewData.palette,
                         genres: WrappedStoryPreviewData.genres)
        .wrappedStoryPreviewEnvironment()
}

#Preview("Summary") {
    WrappedClosingSlide(year: 2026, data: WrappedStoryPreviewData.data, palette: WrappedStoryPreviewData.palette)
        .wrappedStoryPreviewEnvironment()
}
