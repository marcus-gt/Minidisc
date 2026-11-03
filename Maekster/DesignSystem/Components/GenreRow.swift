import SwiftUI

/// A genre or style: its newest cover, name and album count (Library → Genres on both apps).
struct GenreRow: View {
    let title: Text
    let albumCount: Int
    let coverArtId: String?

    /// A tag spelled as in the library; `nil` stands for the localized "Other".
    static func title(_ name: String?) -> Text {
        name.map { Text(verbatim: $0) } ?? Text("Other")
    }

    var body: some View {
        HStack(spacing: MaeksterSpacing.m) {
            if let coverArtId {
                CoverArtCard(id: coverArtId, size: 56)
            }
            VStack(alignment: .leading, spacing: 2) {
                title
                    .font(.maeksterCellTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("\(albumCount) albums")
                    .font(.maeksterCellSubtitle)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, MaeksterSpacing.xs)
        .contentShape(Rectangle())
    }
}
