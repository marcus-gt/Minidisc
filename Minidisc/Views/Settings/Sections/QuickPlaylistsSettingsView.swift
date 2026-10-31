import SwiftSonic
import SwiftUI

/// The playlists a long-press on a heart offers (#68), and whether adding there also likes the song.
struct QuickPlaylistsSettingsView: View {
    @Environment(\.appContainer) private var container
    @State private var allPlaylists: [Playlist] = []
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
        .task { await loadPlaylists() }
        .sheet(isPresented: $isPicking) {
            if let container, let serverID {
                QuickPlaylistPicker(playlists: allPlaylists, quick: container.quickPlaylists, serverID: serverID)
            }
        }
    }

    /// Also brings renamed playlists' names up to date and drops deleted ones.
    private func loadPlaylists() async {
        guard let container, let serverID, container.serverState.isOnline,
              let playlists = try? await container.playlistService.listPlaylists() else { return }
        allPlaylists = playlists.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        container.quickPlaylists.reconcile(with: playlists.map { ($0.id, $0.name) }, serverID: serverID)
    }
}

/// Every playlist, ticked when it's a quick playlist.
private struct QuickPlaylistPicker: View {
    let playlists: [Playlist]
    let quick: QuickPlaylists
    let serverID: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(playlists, id: \.id) { playlist in
                Button {
                    quick.toggle(id: playlist.id, name: playlist.name, serverID: serverID)
                } label: {
                    HStack {
                        Text(playlist.name).foregroundStyle(.primary)
                        Spacer()
                        if quick.contains(playlist.id, serverID: serverID) {
                            Image(systemName: "checkmark").foregroundStyle(Color.minidiscAccent)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .accessibilityAddTraits(quick.contains(playlist.id, serverID: serverID) ? .isSelected : [])
            }
            .overlay {
                if playlists.isEmpty { ProgressView() }
            }
            .navigationTitle("Choose Playlists")
            .navigationBarTitleDisplayModeInline()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
