import SwiftUI

/// The last slide: the year on one page, under the maekster mark (#75).
struct WrappedClosingSlide: View {
    let year: Int
    let data: WrappedData
    let palette: [Color]

    var body: some View {
        ZStack {
            WrappedCoverMosaic(artworkIDs: data.topAlbums.map(\.albumId), palette: palette)

            VStack(spacing: 0) {
                Spacer(minLength: MinidiscSpacing.xxxxl)

                VStack(spacing: MinidiscSpacing.m) {
                    WrappedBrandMark(width: 84)
                    // The year goes in as text: a number would be grouped ("2 026") in some locales.
                    Text("Your \(String(year)) Wrapped")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .kerning(-0.5)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                Spacer(minLength: MinidiscSpacing.xl)

                HStack(alignment: .top, spacing: MinidiscSpacing.l) {
                    topList("TOP ARTISTS", data.topArtists.prefix(5).map(\.name))
                    topList("TOP SONGS", data.topTracks.prefix(5).map(\.title))
                }
                .padding(.horizontal, MinidiscSpacing.xl)

                Spacer(minLength: MinidiscSpacing.xl)

                HStack(spacing: MinidiscSpacing.m) {
                    statCard(value: data.totalSecondsListened.wrappedCompactLabel(), label: String(localized: "listened"))
                    statCard(value: "\(data.totalTracksPlayed)", label: data.totalTracksPlayed == 1 ? String(localized: "play") : String(localized: "plays"))
                    statCard(value: data.dominantGenre ?? "–", label: String(localized: "top genre"))
                }
                .padding(.horizontal, MinidiscSpacing.xl)

                Spacer(minLength: MinidiscSpacing.l)

                Text("Thanks for listening.")
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))

                // Space reserved for the share button overlay rendered by WrappedStoryPlayerView
                Spacer(minLength: MinidiscSpacing.xxxxl * 2)
            }
            .wrappedSlideEntrance()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func topList(_ title: LocalizedStringKey, _ names: [String]) -> some View {
        VStack(alignment: .leading, spacing: MinidiscSpacing.s) {
            WrappedSlideLabel(title)
            ForEach(Array(names.enumerated()), id: \.offset) { index, name in
                HStack(alignment: .firstTextBaseline, spacing: MinidiscSpacing.s) {
                    Text(verbatim: "\(index + 1)")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 14, alignment: .leading)
                    Text(name)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Stat card

    private func statCard(value: String, label: String) -> some View {
        VStack(spacing: MinidiscSpacing.xs) {
            Text(value)
                .font(.system(size: 22, weight: .black, design: .rounded))
                .kerning(-0.5)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(label)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, MinidiscSpacing.m)
        .padding(.horizontal, MinidiscSpacing.xs)
        .background(Color.white.opacity(0.15), in: RoundedRectangle(cornerRadius: MinidiscCornerRadius.large, style: .continuous))
    }
}
