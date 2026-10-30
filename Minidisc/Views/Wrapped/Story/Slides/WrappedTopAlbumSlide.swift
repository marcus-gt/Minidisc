import SwiftUI

struct WrappedTopAlbumSlide: View {
    let data: WrappedData
    let palette: [Color]

    private var topAlbum: TopAlbumEntry? { data.topAlbums.first }
    private var runnersUp: ArraySlice<TopAlbumEntry> { data.topAlbums.dropFirst().prefix(4) }

    var body: some View {
        ZStack {
            WrappedArtBackdrop(artworkID: topAlbum?.albumId, palette: palette)

            VStack(spacing: 0) {
                Spacer(minLength: MinidiscSpacing.xxxxl)
                WrappedSlideLabel("YOUR #1 ALBUM")
                Spacer(minLength: MinidiscSpacing.l)

                if let album = topAlbum {
                    WrappedSlideCover(artworkID: album.albumId)

                    VStack(spacing: MinidiscSpacing.xs) {
                        Text(album.title)
                            .font(.system(size: 28, weight: .black, design: .rounded))
                            .kerning(-0.5)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                        Text(verbatim: "\(album.artistName) · \(album.playCount.plural("play", "plays"))")
                            .font(.system(size: 17, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, MinidiscSpacing.xl)
                    .padding(.top, MinidiscSpacing.l)

                    Spacer(minLength: MinidiscSpacing.l)

                    VStack(spacing: MinidiscSpacing.s) {
                        ForEach(runnersUp) { entry in
                            WrappedRunnerUpRow(rank: entry.rank, artworkID: entry.albumId, title: entry.title,
                                               subtitle: entry.artistName, detail: entry.playCount.plural("play", "plays"))
                        }
                    }
                    .padding(.horizontal, MinidiscSpacing.xl)
                } else {
                    Text("No album data yet")
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
