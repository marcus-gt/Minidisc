import SwiftUI

/// The Mac window's root. The macOS build leaves out `Views/` (the iPhone interface), so this
/// takes the place of the iOS `RootView` under the same name and `MaeksterApp` needs no `#if`.
///
/// For now it only proves that the shared service graph boots on macOS; the real Mac interface
/// (sidebar, library, player bar) comes with #102.
struct RootView: View {
    @Environment(\.appContainer) private var container

    var body: some View {
        EmptyStateView(
            systemImage: "macbook",
            title: "maekster for Mac is on its way",
            subtitle: subtitle
        )
        .frame(minWidth: 480, minHeight: 320)
    }

    private var subtitle: LocalizedStringKey {
        guard let server = container?.serverState.activeServer else {
            return "No server is set up yet."
        }
        return "Connected to \(server.displayName)."
    }
}
