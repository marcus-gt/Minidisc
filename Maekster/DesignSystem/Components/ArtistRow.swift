import SwiftUI
import SwiftSonic

struct ArtistRow: View {
    let artist: ArtistID3

    var body: some View {
        HStack(spacing: MaeksterSpacing.m) {
            CoverArtView(
                id: artist.coverArt ?? artist.id,
                size: 88,
                placeholderSystemImage: "person.fill"
            )
            .frame(width: 44, height: 44)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(artist.name)
                    .font(.maeksterCellTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let count = artist.albumCount {
                    Text("\(count) albums")
                        .font(.maeksterCaption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, MaeksterSpacing.xs)
        .contentShape(Rectangle())
    }
}
