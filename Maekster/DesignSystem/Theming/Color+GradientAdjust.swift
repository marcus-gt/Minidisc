import SwiftUI

extension Color {
    /// sRGB components in `0...1`, or `nil` if the color can't be resolved to RGB.
    var rgbComponents: (red: Double, green: Double, blue: Double)? {
        guard let rgba = PlatformColor(self).rgba() else { return nil }
        return (Double(rgba.red), Double(rgba.green), Double(rgba.blue))
    }

    /// An HSB-adjusted variant — hue wraps, saturation/brightness clamp to `0...1`. Used to derive gradient
    /// stops (lighter/darker/hue-shifted) from a single base color. Returns `self` if the color can't resolve.
    func adjusted(hue dh: Double = 0, saturation ds: Double = 0, brightness db: Double = 0) -> Color {
        guard let (h, s, b, _) = PlatformColor(self).hsba() else { return self }
        var hue = (Double(h) + dh).truncatingRemainder(dividingBy: 1)
        if hue < 0 { hue += 1 }
        return Color(
            hue: hue,
            saturation: min(max(Double(s) + ds, 0), 1),
            brightness: min(max(Double(b) + db, 0), 1)
        )
    }

    /// Boosts low saturation more than high saturation, with a brightness floor for dark averages.
    /// Returns self when HSB conversion fails.
    func vibranceBoosted(_ k: Double = 0.5) -> Color {
        guard let (h, s, b, _) = PlatformColor(self).hsba() else { return self }
        let boosted = Double(s) + (1 - Double(s)) * max(0, k)
        return Color(
            hue: Double(h),
            saturation: min(boosted, 1),
            brightness: min(max(Double(b), 0.30), 1)
        )
    }
}
