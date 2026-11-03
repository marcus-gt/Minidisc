import SwiftUI

/// A short list of songs inside a scrolling page (an artist's top songs), where a `Table` can't sit
/// because it scrolls on its own. Double-click plays; right-click shows `MacSongMenu`.
struct MacSongRows: View {
    let songs: [DisplayableSong]
    /// Plays `songs` starting at the given index.
    let onPlay: (Int) -> Void

    @Environment(\.appContainer) private var container

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 320), spacing: MaeksterSpacing.xl, alignment: .leading)],
            alignment: .leading,
            spacing: MaeksterSpacing.s
        ) {
            ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                row(song)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { onPlay(index) }
                    .contextMenu {
                        MacSongMenu(songs: [song], onPlay: { onPlay(index) })
                    }
            }
        }
    }

    private func row(_ song: DisplayableSong) -> some View {
        HStack(spacing: MaeksterSpacing.m) {
            CoverArtCard(id: song.coverArtId ?? "", size: 40, cornerRadius: MaeksterCornerRadius.xs)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: MaeksterSpacing.xs) {
                    if song.id == container?.playerState.currentTrack?.id {
                        Image(systemName: "speaker.wave.2.fill")
                            .foregroundStyle(Color.maeksterAccent)
                            .imageScale(.small)
                    }
                    Text(song.title)
                }
                Text(song.albumName ?? "")
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            Spacer(minLength: MaeksterSpacing.s)
            Text(MacTrackTable.time(song.duration))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}
