import SwiftUI

/// An album's or playlist's songs as a music list rather than a table: the page header scrolls
/// with the songs, rows are tall with thin separators, and the number column shows a speaker for
/// the playing song and a play button on hover. Double-click (or Return) plays from a song; the
/// right-click menu has the song actions (`MacSongMenu`); playlists drag rows to reorder.
///
/// Rows are identified by position, not song ID, because a playlist can hold the same song twice.
struct MacSongList<Header: View, Footer: View>: View {
    let songs: [DisplayableSong]
    /// The number shown before each song; the track number when nil.
    var rowNumbers: [Int]?
    /// Whether a song shows its artist under the title (on albums, only guest artists).
    var showsArtist: (DisplayableSong) -> Bool = { _ in true }
    /// Playlists show each song's album in a column of its own.
    var showsAlbum = false
    /// Album pages group multi-disc albums under "Disc 1", "Disc 2", … headers.
    var groupsByDisc = false
    var discTitles: [Int: String] = [:]
    /// Plays `songs` starting at the given index.
    let onPlay: (Int) -> Void
    /// Set on playlist pages, for "Remove from Playlist". Receives the rows' indices.
    var onRemove: ((IndexSet) -> Void)?
    /// Set on playlist pages: dragging rows moves them, with `Array.move` semantics.
    var onMove: ((IndexSet, Int) -> Void)?
    @ViewBuilder let header: () -> Header
    @ViewBuilder let footer: () -> Footer

    @Environment(\.appContainer) private var container
    @State private var selection = Set<Int>()

    private struct Row: Identifiable {
        let index: Int
        let song: DisplayableSong
        var id: Int { index }
    }

    private struct Disc: Identifiable {
        let number: Int
        let rows: [Row]
        var id: Int { number }
    }

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
        List(selection: $selection) {
            header()
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
            if discs.isEmpty {
                ForEach(rows) { row($0) }
                    .onMove(perform: onMove)
            } else {
                ForEach(discs) { disc in
                    Section {
                        ForEach(disc.rows) { row($0) }
                    } header: {
                        DiscHeader(discNumber: disc.number, title: discTitles[disc.number])
                            .padding(.horizontal, MaeksterSpacing.xl)
                            .padding(.top, MaeksterSpacing.m)
                    }
                }
            }
            footer()
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .contextMenu(forSelectionType: Int.self) { ids in
            let indices = ids.sorted().filter(songs.indices.contains)
            if let first = indices.first {
                MacSongMenu(
                    songs: indices.map { songs[$0] },
                    onPlay: { onPlay(first) },
                    onRemove: onRemove.map { remove in { _ in remove(IndexSet(indices)) } }
                )
            }
        } primaryAction: { ids in
            guard let index = ids.min(), songs.indices.contains(index) else { return }
            onPlay(index)
        }
    }

    private func row(_ row: Row) -> some View {
        MacSongListRow(
            song: row.song,
            number: rowNumbers.flatMap { $0.indices.contains(row.index) ? $0[row.index] : nil } ?? row.song.trackNumber,
            isPlaying: row.song.id == container?.playerState.currentTrack?.id,
            showsArtist: showsArtist(row.song),
            showsAlbum: showsAlbum,
            onPlay: { onPlay(row.index) }
        )
        .tag(row.index)
        .listRowInsets(EdgeInsets(top: 0, leading: MaeksterSpacing.xl, bottom: 0, trailing: MaeksterSpacing.xl))
    }
}

extension MacSongList where Footer == EmptyView {
    init(songs: [DisplayableSong], rowNumbers: [Int]? = nil,
         showsArtist: @escaping (DisplayableSong) -> Bool = { _ in true }, showsAlbum: Bool = false,
         groupsByDisc: Bool = false, discTitles: [Int: String] = [:], onPlay: @escaping (Int) -> Void,
         onRemove: ((IndexSet) -> Void)? = nil, onMove: ((IndexSet, Int) -> Void)? = nil,
         @ViewBuilder header: @escaping () -> Header) {
        self.init(songs: songs, rowNumbers: rowNumbers, showsArtist: showsArtist, showsAlbum: showsAlbum,
                  groupsByDisc: groupsByDisc, discTitles: discTitles, onPlay: onPlay, onRemove: onRemove,
                  onMove: onMove, header: header, footer: { EmptyView() })
    }
}

/// One song: number (or speaker, or a play button on hover), title with the artist under it,
/// the album for playlists, and the duration.
private struct MacSongListRow: View {
    let song: DisplayableSong
    let number: Int?
    let isPlaying: Bool
    let showsArtist: Bool
    let showsAlbum: Bool
    let onPlay: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: MaeksterSpacing.m) {
            leading
                .frame(width: MacSongListMetrics.numberWidth, alignment: .trailing)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: MaeksterSpacing.xs) {
                    Text(song.title)
                        .foregroundStyle(isPlaying ? Color.maeksterAccent : .primary)
                    if song.isDownloaded {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(.secondary)
                            .imageScale(.small)
                            .accessibilityLabel("Downloaded")
                    }
                }
                if showsArtist, let artist = song.artist, !artist.isEmpty {
                    Text(artist)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)

            if showsAlbum {
                Text(song.albumName ?? "")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: MacSongListMetrics.albumColumnWidth, alignment: .leading)
            }

            Text(MacTrackTable.time(song.duration))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, MaeksterSpacing.s)
        .frame(minHeight: MacSongListMetrics.rowHeight)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var leading: some View {
        if isHovered {
            Button(action: onPlay) {
                Image(systemName: "play.fill")
                    .foregroundStyle(Color.maeksterAccent)
            }
            .buttonStyle(.plain)
            .help("Play")
        } else if isPlaying {
            Image(systemName: "speaker.wave.2.fill")
                .foregroundStyle(Color.maeksterAccent)
                .accessibilityLabel("Now Playing")
        } else if let number {
            Text(number, format: .number)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

enum MacSongListMetrics {
    static let numberWidth: CGFloat = 28
    static let rowHeight: CGFloat = 44
    static let albumColumnWidth: CGFloat = 280
}
