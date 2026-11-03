import SwiftUI
#if os(macOS)
import AppKit
typealias PlatformColor = NSColor
#else
import UIKit
typealias PlatformColor = UIColor
#endif

extension PlatformColor {
    /// The colour's red, green, blue and alpha components, or `nil` if it has no RGB form.
    /// `NSColor` only reports components once it's in an RGB colour space, so macOS converts first.
    nonisolated func rgba() -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat)? {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        #if os(macOS)
        guard let rgb = usingColorSpace(.sRGB) else { return nil }
        rgb.getRed(&r, green: &g, blue: &b, alpha: &a)
        #else
        guard getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        #endif
        return (r, g, b, a)
    }

    /// The colour's hue, saturation, brightness and alpha, or `nil` if it has no RGB form.
    nonisolated func hsba() -> (hue: CGFloat, saturation: CGFloat, brightness: CGFloat, alpha: CGFloat)? {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        #if os(macOS)
        guard let rgb = usingColorSpace(.sRGB) else { return nil }
        rgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        #else
        guard getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return nil }
        #endif
        return (h, s, b, a)
    }
}

extension Color {
    init(platformColor: PlatformColor) {
        #if os(macOS)
        self.init(nsColor: platformColor)
        #else
        self.init(uiColor: platformColor)
        #endif
    }
}
