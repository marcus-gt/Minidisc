import SwiftUI

struct WrappedTopGenreSlide: View {
    let data: WrappedData
    let palette: [Color]
    /// The top five genres (#75); empty until the story's details load, or without genre tags.
    var genres: [TopGenreEntry] = []

    private var topName: String { genres.first?.name ?? data.dominantGenre ?? String(localized: "Mixed") }
    private var runnersUp: ArraySlice<TopGenreEntry> { genres.dropFirst().prefix(4) }

    /// The top genre's own albums when it has enough for a wall, the year's otherwise.
    private var artworkIDs: [String] {
        let own = genres.first?.albumIDs ?? []
        return own.count >= 3 ? own : data.topAlbums.map(\.albumId)
    }

    var body: some View {
        ZStack {
            WrappedCoverMosaic(artworkIDs: artworkIDs, palette: palette)

            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: MinidiscSpacing.xxxxl)
                WrappedSlideLabel("YOUR SOUND")
                Spacer()

                Text("Your most-played genre was")
                    .font(.system(size: 22, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
                Text(topName)
                    .font(.system(size: 64, weight: .black, design: .rounded))
                    .kerning(-1.5)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                if let top = genres.first {
                    Text("\(top.share.formatted(.percent.precision(.fractionLength(0)))) of your listening")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.8))
                }

                Spacer(minLength: MinidiscSpacing.xl)

                VStack(spacing: MinidiscSpacing.m) {
                    ForEach(runnersUp) { genre in
                        genreRow(genre)
                    }
                }

                Spacer(minLength: MinidiscSpacing.xxxxl)
            }
            .padding(.horizontal, MinidiscSpacing.xl)
            .wrappedSlideEntrance()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Rank, name and share, with a bar scaled to the top genre so the gaps read at a glance.
    private func genreRow(_ genre: TopGenreEntry) -> some View {
        let lead = genres.first?.share ?? 1
        return VStack(alignment: .leading, spacing: MinidiscSpacing.xs) {
            HStack {
                Text(verbatim: "\(genre.rank)")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 22, alignment: .leading)
                Text(genre.name)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(genre.share.formatted(.percent.precision(.fractionLength(0))))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                    .monospacedDigit()
            }
            GeometryReader { proxy in
                Capsule()
                    .fill(.white.opacity(0.8))
                    .frame(width: max(6, proxy.size.width * genre.share / max(lead, 0.001)))
            }
            .frame(height: 6)
            .padding(.leading, 22 + MinidiscSpacing.s)
        }
        .accessibilityElement(children: .combine)
    }
}
