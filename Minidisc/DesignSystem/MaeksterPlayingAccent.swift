import SwiftUI

private struct MaeksterPlayingAccentKey: EnvironmentKey {
    static let defaultValue: Color = MaeksterColors.accent
}

extension EnvironmentValues {
    /// Override with accentForeground(on:) when indicators sit on artwork-derived backgrounds.
    var maeksterPlayingAccent: Color {
        get { self[MaeksterPlayingAccentKey.self] }
        set { self[MaeksterPlayingAccentKey.self] = newValue }
    }
}
