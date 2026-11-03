import SwiftUI

/// Songs in a table, like the Music app. Double-click (or Return) plays from the
/// clicked song; the context menu adds to the queue. The playing song shows a speaker in the first
/// column.
struct MacTrackTable: View {
    let songs: [DisplayableSong]
    var showsAlbum = true
    /// Plays `songs` starting at the given index.
    let onPlay: (Int) -> Void

    @Environment(\.appContainer) private var container
    @State private var selection = Set<DisplayableSong.ID>()

    var body: some View {
        Table(songs, selection: $selection) {
            // The track number column has no words to translate.
            TableColumn(Text(verbatim: "#")) { song in
                if song.id == container?.playerState.currentTrack?.id {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundStyle(Color.maeksterAccent)
                } else if let number = song.trackNumber {
                    Text(number, format: .number)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .width(32)

            TableColumn("Title", value: \.title)

            TableColumn("Artist") { song in
                Text(song.artist ?? "")
            }

            if showsAlbum {
                TableColumn("Album") { song in
                    Text(song.albumName ?? "")
                }
            }

            TableColumn("Duration") { song in
                Text(Self.time(song.duration))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .width(56)
        }
        .contextMenu(forSelectionType: DisplayableSong.ID.self) { ids in
            menu(for: ids)
        } primaryAction: { ids in
            guard let id = ids.first, let index = songs.firstIndex(where: { $0.id == id }) else { return }
            onPlay(index)
        }
    }

    @ViewBuilder
    private func menu(for ids: Set<DisplayableSong.ID>) -> some View {
        let chosen = songs.filter { ids.contains($0.id) }
        if let first = chosen.first, let index = songs.firstIndex(where: { $0.id == first.id }) {
            Button("Play", systemImage: "play.fill") { onPlay(index) }
            Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") {
                Task { await container?.playerService.playNext(chosen) }
            }
            Button("Add to Queue", systemImage: "text.append") {
                Task { await container?.playerService.addToQueue(chosen) }
            }
        }
    }

    static func time(_ seconds: TimeInterval) -> String {
        Duration.seconds(max(0, seconds)).formatted(.time(pattern: .minuteSecond))
    }
}
