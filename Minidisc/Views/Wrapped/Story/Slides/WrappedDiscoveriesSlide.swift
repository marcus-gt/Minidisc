import SwiftUI

struct WrappedDiscoveriesSlide: View {
    let data: WrappedData
    let palette: [Color]


    var body: some View {
        ZStack {
            WrappedCoverMosaic(artworkIDs: data.topAlbums.reversed().map(\.albumId), palette: palette)

            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: MaeksterSpacing.xxxxl)

                Text("DISCOVERIES")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .tracking(2.5)
                    .foregroundStyle(.white.opacity(0.7))

                Spacer()

                VStack(alignment: .leading, spacing: 4) {
                    Text("You explored")
                        .font(.system(size: 26, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.8))
                    Text("your library.")
                        .font(.system(size: 26, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.8))
                }

                Spacer(minLength: MaeksterSpacing.xl)

                VStack(alignment: .leading, spacing: MaeksterSpacing.m) {
                    discoveryRow(count: data.totalUniqueTracks, label: "different songs")
                    discoveryRow(count: data.totalUniqueArtists, label: "different artists")
                    discoveryRow(count: data.totalUniqueAlbums, label: "different albums")
                }

                Spacer()
            }
            .padding(.horizontal, MaeksterSpacing.xl)
            .wrappedSlideEntrance()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func discoveryRow(count: Int, label: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: MaeksterSpacing.s) {
            Text("\(count)")
                .font(.system(size: 48, weight: .black, design: .rounded))
                .kerning(-1)
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 20, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
        }
    }
}
