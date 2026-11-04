import SwiftUI

/// The queue panel: where the music is playing from, then the songs up next. Drag to reorder,
/// double-click to jump to a song, right-click to remove it (with Undo, as on iPhone), and Clear
/// to drop everything after the playing song.
struct MacQueueView: View {
    @Environment(\.appContainer) private var container
    @State private var selection = Set<Entry.ID>()

    /// An upcoming song and the captured intent to act on it, like the iPhone queue rows: a stale
    /// selection (the queue changed meanwhile) is rejected by the player instead of hitting the
    /// wrong song.
    private struct Entry: Identifiable {
        struct ID: Hashable {
            let generation: UInt64
            let songID: String
            let occurrence: Int
        }
        let id: ID
        let song: DisplayableSong
        let selection: QueueTrackSelection
    }

    var body: some View {
        if let state = container?.playerState {
            let entries = Self.entries(state)
            VStack(alignment: .leading, spacing: 0) {
                header(state, hasUpcoming: !entries.isEmpty)
                if entries.isEmpty {
                    EmptyStateView(systemImage: "list.bullet", title: "Nothing up next",
                                   subtitle: "Tracks you add to the queue appear here.")
                } else {
                    list(entries, queueCount: state.queue.count)
                }
            }
        }
    }

    private func header(_ state: PlayerState, hasUpcoming: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Now playing")
                    .font(.headline)
                if let label = state.playingFromLabel {
                    Text(label.title)
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            Spacer()
            if hasUpcoming {
                Button("Clear") {
                    Task { await container?.playerService.clearUpcoming() }
                }
                .buttonStyle(.link)
            }
        }
        .padding(MaeksterSpacing.m)
    }

    /// Selection-based double-click and menu, so a row drag stays free for reordering.
    private func list(_ entries: [Entry], queueCount: Int) -> some View {
        List(selection: $selection) {
            ForEach(entries) { entry in
                row(entry.song)
                    .tag(entry.id)
            }
            .onMove { sources, destination in
                guard let source = sources.first, entries.indices.contains(source) else { return }
                let entry = entries[source]
                let target = entries.indices.contains(destination)
                    ? entries[destination].selection.destinationIndex
                    : queueCount
                Task { await container?.playerService.moveQueueTrack(entry.selection, toIndex: target) }
            }
        }
        // The side panel's material shows through, like the left sidebar.
        .scrollContentBackground(.hidden)
        .contextMenu(forSelectionType: Entry.ID.self) { ids in
            if let entry = entries.first(where: { ids.contains($0.id) }) {
                Button("Play", systemImage: "play.fill") { select(entry) }
                Button("Remove from Queue", systemImage: "minus.circle", role: .destructive) { remove(entry) }
            }
        } primaryAction: { ids in
            guard let entry = entries.first(where: { ids.contains($0.id) }) else { return }
            select(entry)
        }
    }

    private func row(_ song: DisplayableSong) -> some View {
        HStack(spacing: MaeksterSpacing.m) {
            CoverArtCard(id: song.coverArtId ?? "", size: 36, cornerRadius: MaeksterCornerRadius.xs)
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                Text(song.artist ?? "")
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            Spacer(minLength: MaeksterSpacing.s)
            Text(MacTrackTable.time(song.duration))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func select(_ entry: Entry) {
        guard let container else { return }
        Task {
            await container.toastService.perform {
                _ = try await container.playerService.selectQueueTrack(entry.selection)
            }
        }
    }

    private func remove(_ entry: Entry) {
        guard let container else { return }
        Task {
            guard let removal = await container.playerService.removeQueueTrack(entry.selection) else { return }
            container.toastService.show(String(localized: "Removed from queue"), subtitle: removal.song.title,
                                        style: .success, duration: 6, coverArtId: removal.song.coverArtId,
                                        action: .undoQueueRemoval(removal))
        }
    }

    private static func entries(_ state: PlayerState) -> [Entry] {
        var occurrences: [String: Int] = [:]
        return state.queue.enumerated().compactMap { index, song in
            let occurrence = occurrences[song.id, default: 0]
            occurrences[song.id] = occurrence + 1
            guard index > state.currentIndex,
                  let selection = QueueTrackSelection(playerState: state, destinationIndex: index,
                                                      destinationTrackID: song.id) else { return nil }
            return Entry(id: Entry.ID(generation: state.queueGeneration, songID: song.id, occurrence: occurrence),
                         song: song, selection: selection)
        }
    }
}
