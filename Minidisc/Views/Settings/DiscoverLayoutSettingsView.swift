import SwiftUI

/// Settings → Discover: which Discover sections show and in what order.
struct DiscoverLayoutSettingsView: View {
    @AppStorage(DiscoverLayoutConfiguration.storageKey)
    private var configuration: DiscoverLayoutConfiguration = .default

    var body: some View {
        List {
            Section {
                ForEach(configuration.order) { section in
                    DiscoverLayoutSettingsRow(
                        section: section,
                        isVisible: Binding(
                            get: { configuration.isVisible(section) },
                            set: { configuration.setVisible($0, for: section) }
                        )
                    )
                }
                .onMove { source, destination in
                    var order = configuration.order
                    order.move(fromOffsets: source, toOffset: destination)
                    configuration.setOrder(order)
                }
            } footer: {
                Text("Tap a section to show or hide it, and drag to change the order.")
            }

            Section {
                Button("Reset to Default") {
                    configuration = .default
                }
            } footer: {
                Text("Shows every section in the original order.")
            }
        }
        // Always in edit mode so the drag handles show without an Edit button.
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Discover Screen")
        .navigationBarTitleDisplayModeInline()
    }
}

private struct DiscoverLayoutSettingsRow: View {
    let section: DiscoverSection
    @Binding var isVisible: Bool

    var body: some View {
        Button {
            isVisible.toggle()
        } label: {
            HStack(spacing: MinidiscSpacing.m) {
                Image(systemName: isVisible ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isVisible ? Color.minidiscAccent : Color.secondary)
                Text(section.title)
                    .foregroundStyle(isVisible ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isVisible ? Text("Shown") : Text("Hidden"))
        .accessibilityHint("Shows or hides this section on Discover")
        .accessibilityIdentifier("settings.discoverLayout.\(section.rawValue)")
    }
}

#if DEBUG
#Preview("Discover Screen Settings") {
    NavigationStack {
        DiscoverLayoutSettingsView()
    }
}
#endif
