import SwiftData
import SwiftUI

/// The Settings window (⌘,). Each tab hosts the iPhone's settings pages (`SharedViews/Settings`) in
/// its own navigation stack, so their links to sub-pages (ListenBrainz, Lidarr, …) keep working.
struct MacSettingsView: View {
    let container: AppContainer?

    var body: some View {
        if let container {
            TabView {
                Tab("Server", systemImage: "server.rack") {
                    MacServerSettings()
                }
                Tab("Playback", systemImage: "play.circle") {
                    NavigationStack { PlaybackSettingsView() }
                }
                Tab("Storage", systemImage: "internaldrive") {
                    MacStorageSettings()
                }
                Tab("Integrations", systemImage: "puzzlepiece.extension") {
                    NavigationStack { IntegrationsSettingsView() }
                }
                Tab("About", systemImage: "info.circle") {
                    NavigationStack { MacAboutSettings() }
                }
            }
            .frame(minWidth: 560, idealWidth: 620, minHeight: 460, idealHeight: 560)
            .environment(\.appContainer, container)
            .environment(container.dominantColorExtractor)
            .environment(container.artworkImageCache)
            .environment(container.toastService)
            .modelContainer(container.modelContainer)
        } else {
            ProgressView()
                .frame(width: 560, height: 460)
        }
    }
}

/// The servers: a picker to switch the active one, its details, and Edit, Add Server and Remove.
private struct MacServerSettings: View {
    @Environment(\.appContainer) private var container
    @State private var editing: ServerSnapshot?
    @State private var addsServer = false
    @State private var removing: ServerSnapshot?

    var body: some View {
        if let container {
            let state = container.serverState
            Form {
                Section {
                    if state.servers.isEmpty {
                        Text("No server configured.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Server", selection: Binding(
                            get: { state.activeServer?.id },
                            set: { id in
                                guard let id, id != state.activeServer?.id else { return }
                                Task {
                                    await container.toastService.perform {
                                        try await container.serverService.setActiveServer(id: id)
                                    }
                                }
                            }
                        )) {
                            ForEach(state.servers, id: \.id) { server in
                                Text(verbatim: server.displayName).tag(Optional(server.id))
                            }
                        }
                        if let active = state.activeServer {
                            LabeledContent("Active") {
                                Text(verbatim: active.baseURL)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
                Section {
                    HStack {
                        Button("Edit") { editing = state.activeServer }
                            .disabled(state.activeServer == nil)
                        Button("Add Server") { addsServer = true }
                        Spacer()
                        Button("Remove", role: .destructive) { removing = state.activeServer }
                            .disabled(state.activeServer == nil)
                    }
                }
            }
            .formStyle(.grouped)
            .sheet(isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
                if let server = editing {
                    NavigationStack {
                        EditServerDestinationView(server: server, serverService: container.serverService, isSheet: true)
                    }
                    .frame(minWidth: 480, minHeight: 520)
                }
            }
            .sheet(isPresented: $addsServer) {
                MacAddServerSheet()
                    .frame(minWidth: 480, minHeight: 520)
            }
            .alert(Text("Remove \(removing?.displayName ?? "")?"),
                   isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                   presenting: removing) { server in
                Button("Remove", role: .destructive) {
                    Task {
                        await container.toastService.perform {
                            try await container.serverService.removeServer(id: server.id)
                            // Switch to another server rather than leaving none active.
                            if container.serverState.activeServer == nil,
                               let next = container.serverState.servers.first {
                                try await container.serverService.setActiveServer(id: next.id)
                            }
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}

/// The add-server form from onboarding; closes once the server is saved.
private struct MacAddServerSheet: View {
    @Environment(\.appContainer) private var container
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: OnboardingViewModel?
    @State private var serverCount = 0

    var body: some View {
        NavigationStack {
            if let viewModel {
                ServerFormView(viewModel: viewModel)
                    .formStyle(.grouped)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { dismiss() }
                        }
                    }
            }
        }
        .task {
            guard viewModel == nil, let container else { return }
            serverCount = container.serverState.servers.count
            viewModel = OnboardingViewModel(serverService: container.serverService)
        }
        .onChange(of: container?.serverState.servers.count ?? 0) { _, count in
            if count > serverCount { dismiss() }
        }
    }
}

/// Storage, with the downloads view model the iPhone settings list creates.
private struct MacStorageSettings: View {
    @Environment(\.appContainer) private var container
    @State private var downloadsVM: DownloadsViewModel?

    var body: some View {
        NavigationStack {
            if let downloadsVM {
                StorageSettingsView(vm: downloadsVM)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
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
}

/// The brand, version, links and acknowledgements, like the iPhone's About section.
private struct MacAboutSettings: View {
    private static var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: MaeksterSpacing.l) {
                    Image("BrandMark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: "maekster")
                            .font(.title2.bold())
                        Text("Version \(Self.appVersion)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                Link(destination: MaeksterURLs.repoIssues) {
                    Label("Report an Issue", systemImage: "exclamationmark.bubble")
                }
                Link(destination: MaeksterURLs.repo) {
                    Label("View on GitHub", systemImage: "link")
                }
                NavigationLink {
                    AcknowledgementsView()
                } label: {
                    Label("Acknowledgements", systemImage: "text.badge.star")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("About")
    }
}
