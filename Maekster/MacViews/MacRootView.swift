import SwiftUI

/// The Mac window's root. The macOS build leaves out `Views/` (the iPhone interface), so this
/// takes the place of the iOS `RootView` under the same name and `MaeksterApp` needs no `#if`.
struct RootView: View {
    @Environment(\.appContainer) private var container

    var body: some View {
        Group {
            if let serverState = container?.serverState {
                if serverState.isLoadingPersistedState {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if serverState.activeServer != nil {
                    MacMainView()
                } else {
                    MacSignInView()
                }
            }
        }
        .frame(minWidth: 900, minHeight: 560)
    }
}
