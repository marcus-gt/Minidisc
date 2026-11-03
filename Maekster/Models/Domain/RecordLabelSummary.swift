import Foundation
import SwiftSonic

/// One row of the Library "Labels" list, built from the OpenSubsonic record labels of indexed albums.
nonisolated struct RecordLabelSummary: Identifiable, Hashable, Sendable {
    let name: String
    let albumCount: Int
    /// Cover of the label's most recently added album.
    let coverArtId: String?
    var id: String { name }

    /// Groups albums by label, matching names the way `albums(recordLabel:)` does (case- and
    /// diacritic-insensitive), so every row opens the same albums it counts. Sorted by name.
    static func summaries(from albums: [AlbumID3]) -> [RecordLabelSummary] {
        struct Group {
            var name: String
            var coverArtId: String?
            var count = 0
        }
        // Newest first, so each label keeps the spelling and cover of its latest album.
        let newestFirst = albums.sorted { ($0.created ?? .distantPast) > ($1.created ?? .distantPast) }
        var groups: [String: Group] = [:]
        for album in newestFirst {
            var seenInAlbum: Set<String> = []
            for label in album.recordLabels ?? [] {
                let name = label.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let key = LibraryIndexText.normalized(name)
                guard !key.isEmpty, seenInAlbum.insert(key).inserted else { continue }
                groups[key, default: Group(name: name, coverArtId: album.coverArt ?? album.id)].count += 1
            }
        }
        return groups.values
            .map { RecordLabelSummary(name: $0.name, albumCount: $0.count, coverArtId: $0.coverArtId) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
