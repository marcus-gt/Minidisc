import SwiftUI

/// Moods are radios now (#60). Earlier versions kept a server playlist per mood; this removes them.
struct MoodPlaylistSettingsSection: View {
    @Environment(\.appContainer) private var container
    @State private var request: DeletionRequest?
    @State private var outcome: MoodDeletionOutcome?
    @State private var showDeleteConfirmation = false

    private struct DeletionRequest: Equatable {
        let id = UUID()
        let serverId: String
    }

    private var serverId: String? { container?.serverState.activeServer?.id.uuidString }

    var body: some View {
        Section {
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                HStack {
                    Text("Delete old mood playlists")
                    if request != nil {
                        Spacer()
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .accessibilityIdentifier("mood-delete-playlists")
            .disabled(request != nil || serverId == nil)
            if let outcome {
                MoodDeletionResult(outcome: outcome)
                    .font(.minidiscCaption)
                    .foregroundStyle(.secondary)
            }
            if serverId == nil {
                Text("No server configured.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Moods")
        } footer: {
            Text("Moods on Discover play as radios. Earlier versions saved a playlist per mood on your server; they are no longer updated and can be deleted here.")
        }
        .task(id: request) {
            guard let request, let service = container?.moodPlaylistService else { return }
            let result = await service.deletePlaylists(serverId: request.serverId)
            self.request = nil
            guard !Task.isCancelled, serverId == request.serverId else { return }
            outcome = result
        }
        .onChange(of: serverId) {
            request = nil
            outcome = nil
        }
        .confirmationDialog("Delete old mood playlists?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                guard let serverId else { return }
                outcome = nil
                request = DeletionRequest(serverId: serverId)
            }
        } message: {
            Text("This removes the mood playlists from your server. Mood radios are not affected.")
        }
    }
}

private struct MoodDeletionResult: View {
    let outcome: MoodDeletionOutcome

    var body: some View {
        switch outcome {
        case .finished(0, 0):
            Text("There were no mood playlists to delete.")
        case .finished(_, let failed) where failed == 0:
            Text("Mood playlists deleted.")
        case .finished(let deleted, _) where deleted > 0:
            Text("Some mood playlists could not be deleted. Try again later.")
        case .inProgress:
            Text("Mood playlists are already being deleted.")
        case .cancelled:
            Text("Deletion cancelled.")
        default:
            Text("Could not delete mood playlists. Check your connection and permissions, then try again.")
        }
    }
}
