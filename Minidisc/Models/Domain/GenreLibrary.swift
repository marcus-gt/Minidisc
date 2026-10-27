import Foundation
import SwiftSonic

/// One style (sub-genre) under a main genre in Library → Genres (#49).
nonisolated struct GenreStyleSummary: Identifiable, Hashable, Sendable {
    let name: String
    /// The library's own spellings behind this style ("Hip-Hop", "hip hop"); its albums carry any of them.
    let tags: [String]
    let albumCount: Int
    /// Cover of the style's most recently added album.
    let coverArtId: String?
    var id: String { name }
}

/// One main genre (a Discogs genre, or "Other") in Library → Genres.
nonisolated struct MainGenreSummary: Identifiable, Hashable, Sendable {
    let name: String
    /// Every library tag that belongs to this main genre, for "All <genre>".
    let tags: [String]
    /// Distinct albums: an album tagged with two styles of one genre counts once.
    let albumCount: Int
    let coverArtId: String?
    let styles: [GenreStyleSummary]
    var id: String { name }

    var isOther: Bool { name == GenreTaxonomy.otherGenre }
}

nonisolated enum GenreLibrary {
    /// Groups the albums' genre tags under main genres and styles. An album with several tags counts
    /// under each, like the server's own genre lists. Main genres: biggest first, "Other" last.
    static func summaries(from albums: [AlbumID3], taxonomy: GenreTaxonomy = .discogs) -> [MainGenreSummary] {
        struct StyleGroup {
            var name: String
            var tags: [String] = []
            var albumIDs: Set<String> = []
            var coverArtId: String?
        }
        struct MainGroup {
            var tags: [String] = []
            var albumIDs: Set<String> = []
            var coverArtId: String?
            var styles: [String: StyleGroup] = [:]
        }
        // Newest first, so each row keeps the cover of its latest album.
        let newestFirst = albums.sorted { ($0.created ?? .distantPast) > ($1.created ?? .distantPast) }
        var mains: [String: MainGroup] = [:]
        for album in newestFirst {
            let cover = album.coverArt ?? album.id
            for tag in tags(of: album) {
                let resolved = taxonomy.resolve(tag)
                for main in resolved.mains {
                    var group = mains[main, default: MainGroup()]
                    if !group.tags.contains(tag) { group.tags.append(tag) }
                    if group.albumIDs.insert(album.id).inserted, group.coverArtId == nil { group.coverArtId = cover }
                    if !resolved.isMainTag {
                        var style = group.styles[resolved.key, default: StyleGroup(name: resolved.styleName ?? tag)]
                        if !style.tags.contains(tag) { style.tags.append(tag) }
                        if style.albumIDs.insert(album.id).inserted, style.coverArtId == nil { style.coverArtId = cover }
                        group.styles[resolved.key] = style
                    }
                    mains[main] = group
                }
            }
        }
        return mains.map { name, group in
            MainGenreSummary(
                name: name,
                tags: group.tags,
                albumCount: group.albumIDs.count,
                coverArtId: group.coverArtId,
                styles: group.styles.values
                    .map { GenreStyleSummary(name: $0.name, tags: $0.tags, albumCount: $0.albumIDs.count, coverArtId: $0.coverArtId) }
                    .sorted(by: biggestFirst)
            )
        }
        .sorted { lhs, rhs in
            if lhs.isOther != rhs.isOther { return rhs.isOther }
            return biggestFirst((lhs.name, lhs.albumCount), (rhs.name, rhs.albumCount))
        }
    }

    /// Whether the album carries any of `tags` (case- and spacing-insensitive).
    static func album(_ album: AlbumID3, hasAnyOf tags: [String]) -> Bool {
        let wanted = Set(tags.compactMap(MainGenre.key))
        return Self.tags(of: album).contains { MainGenre.key($0).map(wanted.contains) ?? false }
    }

    /// The album's genre tags: OpenSubsonic `genres`, else the legacy `genre`. Trimmed, de-duplicated.
    static func tags(of album: AlbumID3) -> [String] {
        let raw = album.genres?.map(\.name) ?? album.genre.map { [$0] } ?? []
        var seen: Set<String> = []
        return raw.compactMap { tag in
            let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let key = MainGenre.key(trimmed), seen.insert(key).inserted else { return nil }
            return trimmed
        }
    }

    private static func biggestFirst(_ lhs: GenreStyleSummary, _ rhs: GenreStyleSummary) -> Bool {
        biggestFirst((lhs.name, lhs.albumCount), (rhs.name, rhs.albumCount))
    }

    private static func biggestFirst(_ lhs: (name: String, count: Int), _ rhs: (name: String, count: Int)) -> Bool {
        lhs.count != rhs.count ? lhs.count > rhs.count : lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}
