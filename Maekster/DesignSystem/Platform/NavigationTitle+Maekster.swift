import SwiftUI

/// macOS has no navigation bar title modes, so both are no-ops there.
extension View {
    func navigationBarTitleDisplayModeInline() -> some View {
        #if os(macOS)
        self
        #else
        self.navigationBarTitleDisplayMode(.inline)
        #endif
    }

    func navigationBarTitleDisplayModeLarge() -> some View {
        #if os(macOS)
        self
        #else
        self.navigationBarTitleDisplayMode(.large)
        #endif
    }
}

extension ToolbarItemPlacement {
    /// The bottom toolbar on iOS; the window toolbar on macOS, which has no bottom bar.
    static var maeksterBottomBar: ToolbarItemPlacement {
        #if os(macOS)
        .automatic
        #else
        .bottomBar
        #endif
    }
}
