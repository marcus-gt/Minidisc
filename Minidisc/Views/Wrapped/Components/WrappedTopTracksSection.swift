import SwiftUI
import OSLog

struct WrappedTopTracksSection: View {
    let tracks: [TopTrackEntry]

    @Environment(\.appContainer) private var container

    var body: some View {
        VStack(alignment: .leading, spacing: MinidiscSpacing.s) {
            Text("Top Tracks")
                .font(.minidiscSectionTitle)
            if tracks.isEmpty {
                emptyLabel("No track data for this period.")
            } else {
                let visible = Array(tracks.prefix(10))
                VStack(spacing: 0) {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, track in
                        trackRow(track)
                        if index < visible.count - 1 {
                            Divider()
                                .padding(.leading, MinidiscSpacing.m + 28 + MinidiscSpacing.m + 44 + MinidiscSpacing.m)
                        }
                    }
                }
            }
        }
    }

    private func trackRow(_ track: TopTrackEntry) -> some View {
        Button {
            Task { await play(from: track) }
        } label: {
            HStack(spacing: MinidiscSpacing.m) {
                ZStack {
                    Circle()
                        .fill(track.rank <= 3 ? medalColor(for: track.rank) : Color.minidiscAccent.opacity(0.15))
                        .frame(width: 28, height: 28)
                    Text("\(track.rank)")
                        .font(.system(.caption, design: .rounded, weight: .heavy))
                        .foregroundStyle(track.rank <= 3 ? Color.black : Color.minidiscAccent)
                }
                .frame(width: 28)
                CoverArtCard(id: track.trackId, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.minidiscCellTitle)
                        .lineLimit(1)
                    Text(track.artistName)
                        .font(.minidiscCaption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(track.playCount.plural("play", "plays"))
                    .font(.minidiscCaption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, MinidiscSpacing.s)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Plays the list as the queue, starting at `track`, the way albums and playlists do (#69).
    /// Rows outside the library can't be played and are left out of the queue.
    private func play(from track: TopTrackEntry) async {
        guard let container, WrappedIDs.isLibraryID(track.trackId) else { return }
        let queue = await container.wrappedDataSource.songs(Array(tracks.prefix(10)))
        guard let start = queue.firstIndex(where: { $0.id == track.trackId }) else { return }
        do {
            try await container.playerService.play(tracks: queue, startIndex: start)
        } catch {
            Logger.player.error("[PLAYBACK] play failed: \(error, privacy: .public)")
        }
    }

    private func medalColor(for rank: Int) -> Color {
        switch rank {
        case 1: return WrappedYearPalette.medalGold
        case 2: return WrappedYearPalette.medalSilver
        case 3: return WrappedYearPalette.medalBronze
        default: return MinidiscColors.accent
        }
    }

    private func emptyLabel(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.minidiscCaption)
            .foregroundStyle(.secondary)
    }
}
