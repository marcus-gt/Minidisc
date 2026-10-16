import SwiftUI

/// Settings → Application → Home Screen: which Home sections show, their order and their style.
/// Style writes the same per-shelf keys as the shelf "…" menus, so both stay in sync.
struct HomeLayoutSettingsView: View {
    @AppStorage(HomeLayoutConfiguration.storageKey) private var configuration: HomeLayoutConfiguration = .default
    @AppStorage(HomeLayoutConfiguration.pinnedPlaylistsOnlyKey) private var pinnedPlaylistsOnly = false

    var body: some View {
        List {
            Section {
                ForEach(configuration.order) { section in
                    HomeLayoutSettingsRow(
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
                Toggle("Pinned Playlists Only", isOn: $pinnedPlaylistsOnly)
                    .accessibilityIdentifier("settings.homeLayout.pinnedOnly")
            } header: {
                Text("Your Playlists")
            } footer: {
                Text("Show only the playlists you've pinned, in the order you pinned them.")
            }

            Section {
                Button("Reset to Default") {
                    configuration = .default
                    pinnedPlaylistsOnly = false
                    for section in HomeSection.allCases where section.supportsLayoutChoice {
                        UserDefaults.standard.removeObject(forKey: HomeShelfLayout.storageKey(for: section.shelfIdentifier))
                    }
                }
            } footer: {
                Text("Shows every section in the original order, as carousels, with all playlists.")
            }
        }
        // Always in edit mode so the drag handles show without an Edit button.
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Home Screen")
        .navigationBarTitleDisplayModeInline()
    }
}

private struct HomeLayoutSettingsRow: View {
    let section: HomeSection
    @Binding var isVisible: Bool
    @AppStorage private var layout: HomeShelfLayout

    init(section: HomeSection, isVisible: Binding<Bool>) {
        self.section = section
        _isVisible = isVisible
        _layout = AppStorage(wrappedValue: .carousel, HomeShelfLayout.storageKey(for: section.shelfIdentifier))
    }

    var body: some View {
        HStack(spacing: MinidiscSpacing.m) {
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
            .accessibilityHint("Shows or hides this section on Home")

            if section.supportsLayoutChoice {
                Picker("Style", selection: $layout) {
                    Text("Carousel").tag(HomeShelfLayout.carousel)
                    Text("Grid").tag(HomeShelfLayout.grid)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .tint(.secondary)
                .disabled(!isVisible)
                .accessibilityLabel(Text("Style for \(section.title)"))
            }
        }
    }
}

#if DEBUG
#Preview("Home Screen Settings") {
    NavigationStack {
        HomeLayoutSettingsView()
    }
}
#endif
