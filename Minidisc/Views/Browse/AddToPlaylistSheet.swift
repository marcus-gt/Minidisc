import SwiftUI
import SwiftSonic

struct AddToPlaylistSheet: View {
    let request: PlaylistAdditionRequest
    var onAdded: (() -> Void)? = nil
    @Environment(\.appContainer) private var container
    @Environment(\.dismiss) private var dismiss
    @State private var vm: AddToPlaylistViewModel?
    @State private var searchText = ""
    @State private var showCreate = false
    @State private var pendingRemoval: Playlist?
    /// Toggles apply straight away, so the caller is only told once the sheet closes.
    @State private var didChange = false

    var body: some View {
        NavigationStack {
            Group {
                if let vm {
                    PlaylistDestinationsList(vm: vm, query: searchText, onCreate: { showCreate = true }) { playlist in
                        Task {
                            switch await vm.toggle(playlist) {
                            case .added, .removed: didChange = true
                            case .needsRemovalConfirmation: pendingRemoval = playlist
                            case .failed: break
                            }
                        }
                    }
                } else { ProgressView() }
            }
            .navigationTitle("Add to Playlist")
            .navigationBarTitleDisplayModeInline()
            .searchable(text: $searchText, prompt: "Find a playlist")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { finish() }.disabled(vm?.isSaving == true)
                }
            }
            .navigationDestination(isPresented: $showCreate) {
                if let vm { NewPlaylistDestinationForm(vm: vm, onSaved: { didChange = true; finish() }) }
            }
        }
        .interactiveDismissDisabled(vm?.isSaving == true)
        .task {
            guard vm == nil, let container else { return }
            let serverID = container.serverState.activeServer?.id.uuidString ?? ""
            let usage = container.playlistUsage
            let model = AddToPlaylistViewModel(songs: request.songs, playlistService: container.playlistService,
                toastService: container.toastService,
                recents: RecentPlaylistDestinations(serverID: serverID),
                recordUse: { usage.recordUse(playlistID: $0, serverID: serverID) })
            vm = model
            showCreate = request.createsPlaylist
            await model.load()
        }
        .confirmationDialog("Remove from Playlist", isPresented: Binding(
            get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }
        ), titleVisibility: .visible, presenting: pendingRemoval) { playlist in
            Button("Remove", role: .destructive) { remove(from: playlist) }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: { playlist in
            Text("\(vm?.songs.count ?? 0) songs will be taken out of \(playlist.name).")
        }
        .tint(.primary)
    }

    private func finish() {
        dismiss()
        if didChange { onAdded?() }
    }

    private func remove(from playlist: Playlist) {
        pendingRemoval = nil
        Task { if await vm?.remove(from: playlist) == .removed { didChange = true } }
    }
}

private struct PlaylistDestinationsList: View {
    let vm: AddToPlaylistViewModel
    let query: String
    let onCreate: () -> Void
    let onSelect: (Playlist) -> Void

    var body: some View {
        List {
            Section {
                Button("New Playlist", systemImage: "plus.circle", action: onCreate)
                    .foregroundStyle(Color.minidiscAccent)
                    .accessibilityIdentifier("playlist.destination.new")
            } footer: {
                Text("\(vm.songs.count) songs selected")
            }
            if let error = vm.error {
                Section {
                    Text(error.displayMessage).font(.subheadline)
                    if vm.playlists.isEmpty { Button("Retry") { Task { await vm.load() } } }
                    else { Text("Your selection is kept. Tap the playlist to try again.").font(.subheadline).foregroundStyle(.secondary) }
                }
            }
            if vm.isLoading && vm.playlists.isEmpty { ProgressView() }
            let destinations = vm.destinations(query: query)
            if !destinations.isEmpty {
                Section {
                    ForEach(destinations) { playlist in destination(playlist) }
                }
            }
            if destinations.isEmpty && !vm.isLoading && vm.error == nil {
                Text(query.isEmpty ? LocalizedStringResource("No playlists yet. Create one above.") : LocalizedStringResource("No matching playlists"))
                    .foregroundStyle(.secondary)
            }
        }
        .minidiscSheetListStyle()
        .disabled(vm.isSaving)
        .refreshable { await vm.load() }
    }

    private func destination(_ playlist: Playlist) -> some View {
        let membership = vm.membership(of: playlist)
        return Button { onSelect(playlist) } label: {
            HStack(spacing: MinidiscSpacing.m) {
                PlaylistCoverThumbnail(playlistId: playlist.id, serverId: nil,
                    coverArtId: playlist.coverArt ?? playlist.id, title: playlist.name, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(playlist.name).font(.minidiscCellTitle).lineLimit(2)
                    Text("\(playlist.songCount) tracks").font(.minidiscCaption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if vm.addingToPlaylistIds.contains(playlist.id) {
                    ProgressView()
                } else {
                    membershipMark(membership)
                }
            }
            .padding(.vertical, MinidiscSpacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("playlist.destination.\(playlist.id)")
        .accessibilityValue(membershipLabel(membership))
        .task { await vm.loadMembership(of: playlist) }
    }

    /// Which part of the selection this playlist already holds (#14).
    @ViewBuilder
    private func membershipMark(_ membership: PlaylistMembership) -> some View {
        switch membership {
        case .unknown:
            Color.clear.frame(width: 22, height: 22)
        case .absent:
            Image(systemName: "circle")
                .font(.title3)
                .foregroundStyle(.tertiary)
        case .partial:
            Image(systemName: "minus.circle.fill")
                .font(.title3)
                .foregroundStyle(Color.minidiscAccent.opacity(0.6))
        case .all:
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(Color.minidiscAccent)
        }
    }

    private func membershipLabel(_ membership: PlaylistMembership) -> Text {
        switch membership {
        case .unknown: Text("")
        case .absent: Text("Not in this playlist")
        case .partial: Text("Some songs already in this playlist")
        case .all: Text(vm.songs.count == 1 ? "Already in this playlist" : "All songs already in this playlist")
        }
    }
}

private struct NewPlaylistDestinationForm: View {
    @Bindable var vm: AddToPlaylistViewModel
    let onSaved: () -> Void

    var body: some View {
        Form {
            Section {
                TextField("Playlist Title", text: $vm.newPlaylistName)
                    .disabled(vm.createdPlaylist != nil || vm.isSaving)
                    .accessibilityIdentifier("playlist.new.name")
            } footer: { Text("\(vm.songs.count) songs selected") }
            if let error = vm.error {
                Section {
                    Text(error.displayMessage)
                    if vm.createdPlaylist != nil {
                        Text("The playlist was created. Retry to finish adding your songs.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                Button {
                    Task { if await vm.createAndAdd() { onSaved() } }
                } label: {
                    if vm.isSaving { ProgressView() }
                    else { Text(vm.createdPlaylist == nil ? LocalizedStringResource("Create Playlist") : LocalizedStringResource("Retry")) }
                }
                .disabled(!vm.canCreate)
                .accessibilityIdentifier("playlist.new.save")
            }
        }
        .navigationTitle("New Playlist")
        .navigationBarTitleDisplayModeInline()
        .navigationBarBackButtonHidden(vm.isSaving)
    }
}
