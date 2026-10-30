import SwiftUI

struct WrappedTopTrackSlide: View {
    let data: WrappedData
    let palette: [Color]

    private var topTrack: TopTrackEntry? { data.topTracks.first }
    private var runnersUp: ArraySlice<TopTrackEntry> { data.topTracks.dropFirst().prefix(4) }

    var body: some View {
        ZStack {
            WrappedArtBackdrop(artworkID: topTrack?.trackId, palette: palette)

            VStack(spacing: 0) {
                Spacer(minLength: MinidiscSpacing.xxxxl)
                WrappedSlideLabel("YOUR #1 TRACK")
                Spacer(minLength: MinidiscSpacing.l)

                if let track = topTrack {
                    WrappedSlideCover(artworkID: track.trackId)

                    VStack(spacing: MinidiscSpacing.xs) {
                        Text(track.title)
                            .font(.system(size: 28, weight: .black, design: .rounded))
                            .kerning(-0.5)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                        Text(verbatim: "\(track.artistName) · \(track.playCount.plural("play", "plays"))")
                            .font(.system(size: 17, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, MinidiscSpacing.xl)
                    .padding(.top, MinidiscSpacing.l)

                    Spacer(minLength: MinidiscSpacing.l)

                    VStack(spacing: MinidiscSpacing.s) {
                        ForEach(runnersUp) { entry in
                            WrappedRunnerUpRow(rank: entry.rank, artworkID: entry.trackId, title: entry.title,
                                               subtitle: entry.artistName, detail: entry.playCount.plural("play", "plays"))
                        }
                    }
                    .padding(.horizontal, MinidiscSpacing.xl)
                } else {
                    Text("No track data yet")
                        .font(.system(.title2, design: .rounded, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }

                Spacer(minLength: MinidiscSpacing.xxxxl)
            }
            .wrappedSlideEntrance()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The #1's cover on a slide, with a shadow to lift it off its own blurred copy.
struct WrappedSlideCover: View {
    let artworkID: String
    var isArtist = false

    static let size: CGFloat = 220

    var body: some View {
        CoverArtCard(id: artworkID, size: Self.size, tier: .hero,
                     cornerRadius: isArtist ? Self.size / 2 : MinidiscCornerRadius.large,
                     placeholderSystemImage: isArtist ? "person.fill" : "music.note")
            .shadow(color: .black.opacity(0.4), radius: 24, y: 12)
    }
}
