import SwiftUI

// The shared top-right items (#43). Tab roots carry Settings; list screens carry Sort, then More;
// detail pages carry More. Building them here keeps the icon, label and placement identical.

/// The ⋯ menu for a screen's secondary actions and view options.
struct MinidiscMoreMenu<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        Menu("More options", systemImage: "ellipsis", content: content)
    }
}

/// Settings in the top-right corner of a tab root, opening the settings sheet.
private struct SettingsToolbarModifier: ViewModifier {
    @State private var isPresented = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Settings", systemImage: "gearshape.fill") { isPresented = true }
                        .tint(.primary)
                        .accessibilityIdentifier("toolbar.settings")
                }
            }
            .sheet(isPresented: $isPresented) { SettingsSheet() }
    }
}

extension View {
    /// Adds the Settings button every tab root shares.
    func minidiscSettingsToolbar() -> some View {
        modifier(SettingsToolbarModifier())
    }
}

// MARK: - Recently Played order

/// Fetches the server's recently-played order while a list is sorted by it, so the order is
/// current each time the sort is picked or the list opens. Nothing is fetched for other sorts.
private struct RecentlyPlayedOrderModifier: ViewModifier {
    @Binding var order: RecentlyPlayedOrder
    let isActive: Bool
    @Environment(\.appContainer) private var container

    func body(content: Content) -> some View {
        content.task(id: isActive) {
            guard isActive, let library = container?.libraryService, container?.serverState.isOnline == true else { return }
            order = await RecentlyPlayedOrder.load(from: library)
        }
    }
}

extension View {
    func recentlyPlayedOrder(_ order: Binding<RecentlyPlayedOrder>, when isActive: Bool) -> some View {
        modifier(RecentlyPlayedOrderModifier(order: order, isActive: isActive))
    }
}
