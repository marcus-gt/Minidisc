import SwiftUI

/// Rasterizes each mood once to avoid mesh rendering during scrolling.
struct MoodArtwork: View {
    let mood: Mood
    @State private var artwork: PlatformImage?

    var body: some View {
        ZStack {
            mood.gradientSpec.baseColor
            if let artwork {
                Image(platformImage: artwork)
                    .resizable()
                    .scaledToFill()
            }
        }
        .clipped()
        .accessibilityHidden(true)
        .task(id: mood) { artwork = MoodArtworkRenderer.image(for: mood) }
    }
}

@MainActor
private enum MoodArtworkRenderer {
    private static var images: [Mood: PlatformImage] = [:]

    static func image(for mood: Mood) -> PlatformImage? {
        if let image = images[mood] { return image }
        let side: CGFloat = 420
        let renderer = ImageRenderer(content:
            ZStack {
                PlaylistGradientView(spec: mood.gradientSpec)
                LinearGradient(colors: [.black.opacity(0.04), .black.opacity(0.30)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: mood.symbolName)
                    .font(.system(size: side * 0.30, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.18), radius: side * 0.035, y: side * 0.015)
            }
            .frame(width: side, height: side)
        )
        renderer.scale = 1
        let image = renderer.platformImage
        images[mood] = image
        return image
    }
}
