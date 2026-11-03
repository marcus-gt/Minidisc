import SwiftUI

extension Color {
    nonisolated static var maeksterSystemBackground: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(.systemBackground)
        #endif
    }

    nonisolated static let maeksterAccentText = Color.white

    nonisolated static let maeksterCoverShadow = Color(red: 0, green: 0, blue: 0, opacity: 0.15)

    nonisolated static let maeksterCoverBorder = Color.white.opacity(0.08)
}
