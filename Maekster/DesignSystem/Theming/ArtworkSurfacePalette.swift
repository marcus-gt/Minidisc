import SwiftUI

/// The shared dark, cover-tinted surface behind artwork-led screens (album, artist, player).
/// These screens are always dark, whatever the system appearance: the cover's hue is kept, its luminance
/// capped so white text stays at least 7:1 and 70% white secondary text above 4.5:1.
enum ArtworkSurfacePalette {
    /// Luminance cap for the top of the surface. White on 0.1 is 7:1.
    static let maxTintLuminance = 0.1
    /// The bottom of the surface is the tint at this fraction, close to black.
    static let baseDepth = 0.32
    /// Used before the cover colour is known, and for monochrome or missing artwork.
    static let neutral = Color(white: 0.09)

    /// The tinted top colour for a cover's dominant colour.
    static func tint(from coverColor: Color) -> Color {
        guard coverColor != .clear, let rgb = coverColor.rgbComponents else { return neutral }

        let hsba = PlatformColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1).hsba()
        let (hue, saturation, brightness) = (hsba?.hue ?? 0, hsba?.saturation ?? 0, hsba?.brightness ?? 0)

        // Near-grey covers stay neutral; chromatic ones get a little more colour so the tint reads after darkening.
        let isChromatic = saturation >= 0.08
        let adjustedSaturation = isChromatic ? min(saturation * 1.3, 0.85) : saturation
        let color = PlatformColor(hue: hue, saturation: adjustedSaturation, brightness: max(brightness, 0.2), alpha: 1)

        let rgba = color.rgba()
        var red = Double(rgba?.red ?? 0), green = Double(rgba?.green ?? 0), blue = Double(rgba?.blue ?? 0)
        while PlayerBackgroundPalette.luminance(red: red, green: green, blue: blue) > maxTintLuminance {
            red *= 0.95
            green *= 0.95
            blue *= 0.95
        }
        return Color(platformColor: PlatformColor(red: red, green: green, blue: blue, alpha: 1))
    }

    /// The near-black bottom colour that pairs with `tint(from:)`.
    static func base(from tint: Color) -> Color {
        guard let rgb = tint.rgbComponents else { return .black }
        return Color(red: rgb.red * baseDepth, green: rgb.green * baseDepth, blue: rgb.blue * baseDepth)
    }
}

/// The page background for artwork-led screens: tint at the top fading to the base.
struct ArtworkSurfaceBackground: View {
    let tint: Color

    var body: some View {
        LinearGradient(
            stops: [
                .init(color: tint, location: 0),
                .init(color: tint, location: 0.15),
                .init(color: ArtworkSurfacePalette.base(from: tint), location: 0.75)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}
