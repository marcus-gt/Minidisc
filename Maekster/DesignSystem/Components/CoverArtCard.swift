import SwiftUI

struct CoverArtCard: View {
    let id: String
    let size: CGFloat
    /// Overrides size-based tier selection, for example when small cards need hero-resolution artwork.
    var tier: ArtworkTier? = nil
    var cornerRadius: CGFloat = MaeksterCornerRadius.standard
    var placeholderSystemImage: String = "music.note"
    var initialImage: PlatformImage? = nil

    var body: some View {
        CoverArtView(id: id, size: Int(size * 2), tier: tier, cornerRadius: cornerRadius, placeholderSystemImage: placeholderSystemImage, initialImage: initialImage)  // 2× for @2x sharpness
            .frame(width: size, height: size)
            .maeksterCoverStyle(cornerRadius: cornerRadius)
    }
}

#Preview("Light") {
    HStack(spacing: MaeksterSpacing.l) {
        CoverArtCard(id: "preview-small", size: 44)
        CoverArtCard(id: "preview-medium", size: 60)
        CoverArtCard(id: "preview-large", size: 160, cornerRadius: MaeksterCornerRadius.large)
    }
    .padding()
}

#Preview("Dark") {
    HStack(spacing: MaeksterSpacing.l) {
        CoverArtCard(id: "preview-small", size: 44)
        CoverArtCard(id: "preview-medium", size: 60)
        CoverArtCard(id: "preview-large", size: 160, cornerRadius: MaeksterCornerRadius.large)
    }
    .padding()
    .preferredColorScheme(.dark)
}
