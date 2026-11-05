import OSLog
import SwiftUI

struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SettingsView()
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Close", systemImage: "xmark") { dismiss() }
                            .tint(.primary)
                    }
                }
        }
    }
}

struct SettingsView: View {
    @Environment(\.appContainer) private var container
    @State private var downloadsVM: DownloadsViewModel?

    var body: some View {
        Group {
            if let downloadsVM {
                form(downloadsVM: downloadsVM)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .maeksterContentWidth()
        .navigationTitle("Settings")
        .task {
            guard let container else { return }
            if downloadsVM == nil {
                downloadsVM = DownloadsViewModel(
                    modelContainer: container.modelContainer,
                    downloadService: container.downloadService,
                    serverState: container.serverState,
                    toastService: container.toastService
                )
            }
            await downloadsVM?.loadData()
        }
    }

    private func form(downloadsVM: DownloadsViewModel) -> some View {
        Form {
            serverSection()
            Section {
                NavigationLink {
                    ApplicationSettingsView()
                } label: {
                    Label("Application", systemImage: "paintbrush")
                        .foregroundStyle(.primary)
                }
                NavigationLink {
                    PlaybackSettingsView()
                } label: {
                    Label("Playback", systemImage: "play.circle")
                        .foregroundStyle(.primary)
                }
                NavigationLink {
                    StorageSettingsView(vm: downloadsVM)
                } label: {
                    Label("Storage", systemImage: "internaldrive")
                        .foregroundStyle(.primary)
                }
                NavigationLink {
                    LocalMusicFoldersView()
                } label: {
                    Label { Text("Local Files", tableName: "LocalMusic") } icon: {
                        Image(systemName: "folder")
                    }
                    .foregroundStyle(.primary)
                }
                NavigationLink {
                    IntegrationsSettingsView()
                } label: {
                    Label("Integrations", systemImage: "puzzlepiece.extension")
                        .foregroundStyle(.primary)
                }
            }
            aboutSection()
        }
        .formStyle(.grouped)
        .refreshable {
            await downloadsVM.loadData()
        }
    }

    // MARK: - Sections

    private func serverSection() -> some View {
        Section {
            if let server = container?.serverState.activeServer,
               let serverService = container?.serverService {
                NavigationLink {
                    EditServerDestinationView(server: server, serverService: serverService)
                } label: {
                    HStack {
                        Text(server.displayName)
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            } else {
                Text("No server configured.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Server")
        }
    }

    private static var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }

    private func aboutSection() -> some View {
        Section {
            // "Leave a Review" and "Share the App" return once maekster has its own App Store listing.
            Link(destination: MaeksterURLs.repoIssues) {
                Label("Report an Issue", systemImage: "exclamationmark.bubble")
            }
            .foregroundStyle(.primary)
            Button {
                ExternalLinkOpener.open(MaeksterURLs.repo)
            } label: {
                Label("View on GitHub", systemImage: "link")
            }
            .foregroundStyle(.primary)
            NavigationLink {
                AcknowledgementsView()
            } label: {
                Label("Acknowledgements", systemImage: "text.badge.star")
                    .foregroundStyle(.primary)
            }
        } header: {
            Text("About")
        } footer: {
            Text("Version \(Self.appVersion)")
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
        }
    }
}

// MARK: - Application

private struct ApplicationSettingsView: View {
    @Environment(\.appContainer) private var container
    @AppStorage("maekster.appTheme") private var theme: AppTheme = .system

    var body: some View {
        Form {
            if let container {
                @Bindable var state = container.serverState
                Section {
                    Toggle("Offline Mode", isOn: $state.isOfflineModeEnabled)
                        .accessibilityIdentifier("offline-mode-toggle")
                } footer: {
                    Text("Only show and play music saved on this device, even when connected to the internet.")
                }
            }
            Section {
                Picker("Theme", selection: $theme) {
                    ForEach(AppTheme.allCases, id: \.self) { option in
                        Text(option.label).tag(option)
                    }
                }
                .tint(.primary)
            } header: {
                Text("Appearance")
            } footer: {
                Text("System follows your device's light or dark setting.")
            }
            Section {
                NavigationLink {
                    HomeLayoutSettingsView()
                } label: {
                    Label("Home Screen", systemImage: "rectangle.grid.1x2")
                        .foregroundStyle(.primary)
                }
                .accessibilityIdentifier("settings.homeLayout")
            } header: {
                Text("Home")
            } footer: {
                Text("Choose which sections appear on Home, their order and their style.")
            }
            Section {
                NavigationLink {
                    DiscoverLayoutSettingsView()
                } label: {
                    Label("Discover Screen", systemImage: "square.grid.2x2")
                        .foregroundStyle(.primary)
                }
                .accessibilityIdentifier("settings.discoverLayout")
            } header: {
                Text("Discover")
            } footer: {
                Text("Choose which sections appear on Discover and their order.")
            }
            Section {
                NavigationLink {
                    QuickPlaylistsSettingsView()
                } label: {
                    Label("Quick Playlists", systemImage: "bolt")
                        .foregroundStyle(.primary)
                }
                .accessibilityIdentifier("settings.quickPlaylists")
            } header: {
                Text("Playlists")
            } footer: {
                Text("Choose the playlists a long-press on a heart adds to.")
            }
            MoodPlaylistSettingsSection()
            if SiriSettingsSection.isAvailable {
                SiriSettingsSection()
            }
            ApplicationDebugSection()
        }
        .formStyle(.grouped)
        .navigationTitle("Application")
        .navigationBarTitleDisplayModeInline()
    }
}

private struct ApplicationDebugSection: View {
    var body: some View {
        Section("Debug") {
            NavigationLink {
                PlaybackDiagnosticsView()
            } label: {
                Label("Playback Diagnostics", systemImage: "waveform.badge.magnifyingglass")
                    .foregroundStyle(.primary)
            }
        }
    }
}
