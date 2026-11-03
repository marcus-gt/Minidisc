import SwiftUI

/// Songs in a table, like the Music app. Double-click (or Return) plays from the clicked song; the
/// context menu has the song actions (`MacSongMenu`). The playing song shows a speaker in the first
/// column, and downloaded songs a small arrow after their title.
///
/// Rows are identified by position, not song ID, because a playlist can hold the same song twice.
struct MacTrackTable: View {
    let songs: [DisplayableSong]
    var showsAlbum = true
    /// Album pages group multi-disc albums under "Disc 1", "Disc 2", … headers.
    var groupsByDisc = false
    var discTitles: [Int: String] = [:]
    /// Plays `songs` starting at the given index.
    let onPlay: (Int) -> Void
    /// Set on playlist pages, for "Remove from Playlist". Receives the rows' indices.
    var onRemove: ((IndexSet) -> Void)?
    /// Set on playlist pages: dragging rows moves them before the row they're dropped on.
    var onMove: ((IndexSet, Int) -> Void)?

    @Environment(\.appContainer) private var container
    @State private var selection = Set<Row.ID>()

    struct Row: Identifiable {
        let index: Int
        let song: DisplayableSong
        var id: Int { index }
    }

    private struct Disc: Identifiable {
        let number: Int
        let rows: [Row]
        var id: Int { number }
    }

    /// Marks drags that started in a track table, so text dropped from elsewhere isn't a move.
    private static let dragPrefix = "maekster-track-row:"

    private var rows: [Row] {
        songs.enumerated().map { Row(index: $0.offset, song: $0.element) }
    }

    private var discs: [Disc] {
        guard groupsByDisc else { return [] }
        let grouped = Dictionary(grouping: rows) { $0.song.discNumber ?? 1 }
        guard grouped.count > 1 else { return [] }
        return grouped.keys.sorted().map { Disc(number: $0, rows: grouped[$0] ?? []) }
    }

    var body: some View {
        Table(of: Row.self, selection: $selection) {
            // The track number column has no words to translate.
            TableColumn(Text(verbatim: "#")) { row in
                if row.song.id == container?.playerState.currentTrack?.id {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundStyle(Color.maeksterAccent)
                } else if let number = onMove == nil ? row.song.trackNumber : row.index + 1 {
                    Text(number, format: .number)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .width(32)

            TableColumn("Title") { row in
                HStack(spacing: MaeksterSpacing.xs) {
                    Text(row.song.title)
                    if row.song.isDownloaded {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(.secondary)
                            .imageScale(.small)
                            .accessibilityLabel("Downloaded")
                    }
                }
            }

            TableColumn("Artist") { row in
                Text(row.song.artist ?? "")
            }

            if showsAlbum {
                TableColumn("Album") { row in
                    Text(row.song.albumName ?? "")
                }
            }

            TableColumn("Duration") { row in
                Text(Self.time(row.song.duration))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .width(56)
        } rows: {
            if onMove != nil {
                ForEach(rows) { row in
                    TableRow(row)
                        .draggable(Self.dragPrefix + String(row.index))
                        .dropDestination(for: String.self) { items in
                            move(items, before: row.index)
                        }
                }
            } else if discs.isEmpty {
                ForEach(rows) { TableRow($0) }
            } else {
                ForEach(discs) { disc in
                    Section {
                        ForEach(disc.rows) { TableRow($0) }
                    } header: {
                        DiscHeader(discNumber: disc.number, title: discTitles[disc.number])
                    }
                }
            }
        }
        .contextMenu(forSelectionType: Row.ID.self) { ids in
            let indices = ids.sorted()
            if let first = indices.first, songs.indices.contains(first) {
                MacSongMenu(
                    songs: indices.filter(songs.indices.contains).map { songs[$0] },
                    onPlay: { onPlay(first) },
                    onRemove: onRemove.map { remove in { _ in remove(IndexSet(indices)) } }
                )
            }
        } primaryAction: { ids in
            guard let index = ids.min(), songs.indices.contains(index) else { return }
            onPlay(index)
        }
    }

    /// Moves the dragged rows (and the rest of the selection, if a selected row was dragged).
    private func move(_ items: [String], before destination: Int) {
        let dragged = items.compactMap { item -> Int? in
            guard item.hasPrefix(Self.dragPrefix) else { return nil }
            return Int(item.dropFirst(Self.dragPrefix.count))
        }
        guard let onMove, let first = dragged.first else { return }
        let moving = selection.contains(first) ? selection : Set(dragged)
        let source = IndexSet(moving.filter(songs.indices.contains))
        guard !source.isEmpty, !(source.count == 1 && source.first == destination) else { return }
        selection.removeAll()
        onMove(source, destination)
    }

    static func time(_ seconds: TimeInterval) -> String {
        Duration.seconds(max(0, seconds)).formatted(.time(pattern: .minuteSecond))
    }
}
