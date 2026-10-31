import SwiftSonic
import SwiftUI

/// The playlists a long-press on a heart offers (#68), and whether adding there also likes the song.
struct QuickPlaylistsSettingsView: View {
    @Environment(\.appContainer) private var container
    @State private var isPicking = false

    private var serverID: String? { container?.serverState.activeServer?.id.uuidString }

    var body: some View {
        Form {
            if let container, let serverID {
                @Bindable var quick = container.quickPlaylists
                Section {
                    let entries = quick.entries(serverID: serverID)
                    if entries.isEmpty {
                        Text("No quick playlists yet.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(entries) { entry in
                        Text(entry.name)
                    }
                    .onDelete { quick.remove(atOffsets: $0, serverID: serverID) }
                    .onMove { quick.move(fromOffsets: $0, toOffset: $1, serverID: serverID) }
                    Button("Choose Playlists…", systemImage: "plus") { isPicking = true }
                        .disabled(container.serverState.isOnline != true)
                } footer: {
                    Text("Touch and hold a heart to add the song to one of these. Playlists can also be added from their ⋯ menu.")
                }
                Section {
                    Toggle("Also like the song", isOn: $quick.alsoLikes)
                } footer: {
                    Text("Adding a song to a quick playlist likes it as well.")
                }
            } else {
                Text("No server configured.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Quick Playlists")
        .navigationBarTitleDisplayModeInline()
        .toolbar { EditButton() }
        .task { await reconcileNames() }
        .sheet(isPresented: $isPicking) {
            if let container, let serverID {
                QuickPlaylistPicker(quick: container.quickPlaylists, serverID: serverID)
            }
        }
    }

    /// Brings renamed playlists' names up to date and drops deleted ones.
    private func reconcileNames() async {
        guard let container, let serverID, container.serverState.isOnline,
              let playlists = try? await container.playlistService.listPlaylists() else { return }
        container.quickPlaylists.reconcile(with: playlists.map { ($0.id, $0.name) }, serverID: serverID)
    }
}

/// Every playlist, ticked when it's a quick playlist (#68). Loads the server's playlists itself.
struct QuickPlaylistPicker: View {
    let quick: QuickPlaylists
    let serverID: String
    @Environment(\.appContainer) private var container
    @Environment(\.dismiss) private var dismiss
    @State private var playlists: [Playlist]?
    @State private var error: UserFacingError?

    var body: some View {
        NavigationStack {
            Group {
                if let playlists, playlists.isEmpty {
                    EmptyStateView(systemImage: "music.note.list", title: "No Playlists",
                                   subtitle: "Create a playlist first, then mark it here.")
                } else if let playlists {
                    List(playlists, id: \.id) { playlist in
                        row(playlist)
                    }
                } else if let error {
                    EmptyStateView(systemImage: "exclamationmark.triangle", title: "Unable to Load Playlists",
                                   subtitle: LocalizedStringKey(error.displayMessage),
                                   action: .init(label: "Retry") { Task { await load() } })
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Choose Playlists")
            .navigationBarTitleDisplayModeInline()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .task { await load() }
    }

    private func row(_ playlist: Playlist) -> some View {
        let isQuick = quick.contains(playlist.id, serverID: serverID)
        return Button {
            HapticFeedback.light.trigger()
            quick.toggle(id: playlist.id, name: playlist.name, serverID: serverID)
        } label: {
            HStack {
                Text(playlist.name).foregroundStyle(.primary)
                Spacer()
                if isQuick {
                    Image(systemName: "checkmark").foregroundStyle(Color.minidiscAccent)
                }
            }
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(isQuick ? .isSelected : [])
    }

    private func load() async {
        guard let container else { return }
        error = nil
        do {
            let loaded = try await container.playlistService.listPlaylists()
            playlists = loaded.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            quick.reconcile(with: loaded.map { ($0.id, $0.name) }, serverID: serverID)
        } catch {
            guard !UserFacingError.isCancellation(error) else { return }
            self.error = UserFacingError.from(error)
        }
    }
}
