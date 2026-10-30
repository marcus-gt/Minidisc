import SwiftUI

struct WrappedIntroSlide: View {
    let year: Int
    let palette: [Color]
    /// The year's top album covers for the mosaic behind; empty until the recap has loaded.
    var artworkIDs: [String] = []

    var body: some View {
        ZStack {
            WrappedCoverMosaic(artworkIDs: artworkIDs, palette: palette)

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: MinidiscSpacing.xs) {
                    WrappedBrandMark(width: 120)
                        .padding(.bottom, MinidiscSpacing.l)
                    Text("YOUR")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .tracking(4)
                        .foregroundStyle(.white.opacity(0.7))

                    Text(verbatim: String(year))
                        .font(.system(size: 120, weight: .black, design: .rounded))
                        .kerning(-3)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)

                    Text("Wrapped")
                        .font(.system(size: 52, weight: .heavy, design: .rounded))
                        .kerning(-1)
                        .foregroundStyle(.white)
                }

                Spacer()
                Spacer()

                Text("Your year in music.")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.bottom, MinidiscSpacing.xxxxl)
            }
            .padding(.horizontal, MinidiscSpacing.xl)
            .wrappedSlideEntrance()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
