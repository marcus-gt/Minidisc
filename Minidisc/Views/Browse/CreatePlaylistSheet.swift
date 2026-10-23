import SwiftUI
import SwiftSonic

/// Names a new playlist. Songs and a cover are added afterwards, on the playlist itself.
struct CreatePlaylistSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appContainer) private var container
    @State private var viewModel: CreatePlaylistViewModel?
    @FocusState private var isNameFocused: Bool

    var onCreated: ((PlaylistWithSongs) -> Void)? = nil

    private var isCreating: Bool { viewModel?.isCreating == true }

    var body: some View {
        NavigationStack {
            Form {
                if let viewModel {
                    Section("Playlist Name") {
                        TextField("Name", text: Bindable(viewModel).name)
                            .focused($isNameFocused)
                            .submitLabel(.done)
                            .onSubmit(create)
                            .disabled(isCreating)
                            .onAppear { isNameFocused = true }
                    }
                }
            }
            .navigationTitle("New Playlist")
            .navigationBarTitleDisplayModeInline()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isCreating)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isCreating {
                        ProgressView()
                    } else {
                        Button("Add", action: create)
                            .disabled(viewModel?.canCreate != true)
                    }
                }
            }
        }
        .interactiveDismissDisabled(isCreating)
        .task {
            guard viewModel == nil, let container else { return }
            viewModel = CreatePlaylistViewModel(
                playlistService: container.playlistService,
                toastService: container.toastService
            )
        }
    }

    private func create() {
        guard let viewModel, viewModel.canCreate else { return }
        Task {
            guard let created = await viewModel.create() else { return }
            onCreated?(created)
            dismiss()
        }
    }
}

#if DEBUG
#Preview {
    MinidiscPreview(container: .preview()) {
        Color.clear.sheet(isPresented: .constant(true)) { CreatePlaylistSheet() }
    }
}
#endif
