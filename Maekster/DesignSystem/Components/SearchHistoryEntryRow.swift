import SwiftUI
import SwiftData

/// A value snapshot avoids SwiftData observation in each row. PersistentIdentifier
/// preserves row identity across query refreshes.
struct SearchHistoryRowData: Identifiable, Equatable {
    let id: PersistentIdentifier
    let coverArtId: String?
    let itemId: String
    let itemType: String
    let displayName: String

    init(entry: SearchHistoryEntry) {
        self.id = entry.persistentModelID
        self.coverArtId = entry.coverArtId
        self.itemId = entry.itemId
        self.itemType = entry.itemType
        self.displayName = entry.displayName
    }
}

/// Equatable skips row updates when a refreshed query yields unchanged values.
struct SearchHistoryEntryRow: View, Equatable {
    let data: SearchHistoryRowData

    var body: some View {
        HStack(spacing: MaeksterSpacing.m) {
            CoverArtView(id: data.coverArtId ?? data.itemId, size: 88)
                .frame(width: 44, height: 44)
                .clipShape(
                    data.itemType == "artist"
                        ? AnyShape(Circle())
                        : AnyShape(RoundedRectangle(cornerRadius: MaeksterCornerRadius.standard))
                )
            Text(data.displayName)
                .font(.maeksterCellTitle)
                .lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: "arrow.up.left")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, MaeksterSpacing.xs)
        .padding(.horizontal, MaeksterSpacing.m)
        .contentShape(Rectangle())
    }
}
