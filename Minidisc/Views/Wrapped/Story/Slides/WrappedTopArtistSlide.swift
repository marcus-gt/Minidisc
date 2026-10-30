import SwiftUI

struct WrappedTopArtistSlide: View {
    let data: WrappedData
    let palette: [Color]

    private var topArtist: TopArtistEntry? { data.topArtists.first }
    private var runnersUp: ArraySlice<TopArtistEntry> { data.topArtists.dropFirst().prefix(4) }

    var body: some View {
        ZStack {
            WrappedArtBackdrop(artworkID: topArtist?.artistId, palette: palette)

            VStack(spacing: 0) {
                Spacer(minLength: MinidiscSpacing.xxxxl)
                WrappedSlideLabel("TOP ARTIST")
                Spacer(minLength: MinidiscSpacing.l)

                if let artist = topArtist {
                    if WrappedIDs.isLibraryID(artist.artistId) {
                        WrappedSlideCover(artworkID: artist.artistId, isArtist: true)
                    }

                    VStack(spacing: MinidiscSpacing.s) {
                        Text(artist.name)
                            .font(.system(size: 44, weight: .black, design: .rounded))
                            .kerning(-1)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.5)
                        HStack(spacing: MinidiscSpacing.s) {
                            statBadge(artist.playCount.plural("play", "plays"))
                            statBadge(artist.uniqueTracks.plural("track", "tracks"))
                        }
                    }
                    .padding(.horizontal, MinidiscSpacing.xl)
                    .padding(.top, MinidiscSpacing.l)

                    Spacer(minLength: MinidiscSpacing.l)

                    VStack(spacing: MinidiscSpacing.s) {
                        ForEach(runnersUp) { entry in
                            WrappedRunnerUpRow(rank: entry.rank, artworkID: entry.artistId, title: entry.name,
                                               subtitle: nil, detail: entry.playCount.plural("play", "plays"), isArtist: true)
                        }
                    }
                    .padding(.horizontal, MinidiscSpacing.xl)
                } else {
                    Text("No artist data yet")
                        .font(.system(.title2, design: .rounded, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }

                Spacer(minLength: MinidiscSpacing.xxxxl)
            }
            .wrappedSlideEntrance()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func statBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, MinidiscSpacing.m)
            .padding(.vertical, MinidiscSpacing.s)
            .background(Color.white.opacity(0.2), in: Capsule())
    }
}
