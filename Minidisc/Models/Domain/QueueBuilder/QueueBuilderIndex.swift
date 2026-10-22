import Foundation
import SwiftSonic

/// One library song as the Queue Builder sees it.
nonisolated struct QueueBuilderTrack: Sendable {
    let song: Song
    /// Every genre tag on the song; it counts under each of them.
    let genres: [String]
    /// The original release year when known (reissues carry a later tagged year), else the tagged year.
    let year: Int?
}

/// What the listener picked. Several genres or decades match any of them; nothing picked matches everything.
nonisolated struct QueueBuilderSelection: Hashable, Sendable {
    /// Whole main-genre columns.
    var mains: Set<String> = []
    /// Individual pills, by `ResolvedGenreTag.key`.
    var tags: Set<String> = []
    /// Decades as their first year (1990 for the 1990s).
    var decades: Set<Int> = []

    var hasGenre: Bool { !mains.isEmpty || !tags.isEmpty }
}

/// Genre columns with distinct song counts, and matching for a selection.
nonisolated struct QueueBuilderIndex: Sendable {
    nonisolated struct Pill: Identifiable, Hashable, Sendable {
        let id: String
        let name: String
        let songCount: Int
    }

    nonisolated struct Column: Identifiable, Hashable, Sendable {
        let id: String
        var name: String { id }
        /// Songs with any of the column's tags, each counted once.
        let songCount: Int
        let pills: [Pill]
    }

    let columns: [Column]
    /// Decade (first year) → number of songs, for the decades present in the library.
    let decadeCounts: [Int: Int]
    let trackCount: Int
    /// Built from the server's per-genre counts while the library index is incomplete: a song with
    /// two tags of one main genre is counted twice there, and there are no songs to match locally.
    let isApproximate: Bool
    /// Pill key → the library's own genre names behind it, for server requests in approximate mode.
    let genreNamesByTag: [String: [String]]
    /// Main genre → the library's own genre names under it, for server requests in approximate mode.
    let genreNamesByMain: [String: [String]]

    private let tracks: [QueueBuilderTrack]
    private let tracksByMain: [String: Set<Int>]
    private let tracksByTag: [String: Set<Int>]

    /// Approximate columns from `getGenres` counts, used until the library index is complete.
    init(genreCounts: [(name: String, songCount: Int)], taxonomy: GenreTaxonomy) {
        var mainCounts: [String: Int] = [:]
        var tagCounts: [String: Int] = [:]
        var tagMains: [String: Set<String>] = [:]
        var names: [String: String] = [:]
        var namesByTag: [String: [String]] = [:]
        var namesByMain: [String: [String]] = [:]
        for (name, count) in genreCounts where count > 0 {
            let resolved = taxonomy.resolve(name)
            for main in resolved.mains {
                mainCounts[main, default: 0] += count
                namesByMain[main, default: []].append(name)
            }
            guard !resolved.isMainTag else { continue }
            tagCounts[resolved.key, default: 0] += count
            tagMains[resolved.key, default: []].formUnion(resolved.mains)
            namesByTag[resolved.key, default: []].append(name)
            if names[resolved.key] == nil || resolved.styleName != nil {
                names[resolved.key] = resolved.styleName ?? name
            }
        }
        var pillsByMain: [String: [Pill]] = [:]
        for (key, mains) in tagMains {
            let pill = Pill(id: key, name: names[key] ?? key, songCount: tagCounts[key] ?? 0)
            for main in mains { pillsByMain[main, default: []].append(pill) }
        }
        columns = Self.sortedColumns(mainCounts.map { main, count in
            Column(id: main, songCount: count, pills: Self.sortedPills(pillsByMain[main] ?? []))
        })
        decadeCounts = [:]
        trackCount = 0
        isApproximate = true
        genreNamesByTag = namesByTag
        genreNamesByMain = namesByMain
        tracks = []
        tracksByMain = [:]
        tracksByTag = [:]
    }

    /// Library genre names a selection asks the server for (approximate mode).
    func serverGenreNames(for selection: QueueBuilderSelection) -> [String] {
        var names = Set<String>()
        for main in selection.mains { names.formUnion(genreNamesByMain[main] ?? []) }
        for tag in selection.tags { names.formUnion(genreNamesByTag[tag] ?? []) }
        return names.sorted()
    }

    private static func sortedPills(_ pills: [Pill]) -> [Pill] {
        pills.sorted { $0.songCount == $1.songCount ? $0.name < $1.name : $0.songCount > $1.songCount }
    }

    /// "Other" always last; otherwise the biggest genres first.
    private static func sortedColumns(_ columns: [Column]) -> [Column] {
        columns.sorted { lhs, rhs in
            if (lhs.id == GenreTaxonomy.otherGenre) != (rhs.id == GenreTaxonomy.otherGenre) {
                return rhs.id == GenreTaxonomy.otherGenre
            }
            return lhs.songCount == rhs.songCount ? lhs.id < rhs.id : lhs.songCount > rhs.songCount
        }
    }

    init(tracks: [QueueBuilderTrack], taxonomy: GenreTaxonomy) {
        self.tracks = tracks
        trackCount = tracks.count
        isApproximate = false
        genreNamesByTag = [:]
        genreNamesByMain = [:]

        var byMain: [String: Set<Int>] = [:]
        var byTag: [String: Set<Int>] = [:]
        var tagMains: [String: Set<String>] = [:]
        var styleNames: [String: String] = [:]
        var spellings: [String: [String: Int]] = [:]
        var decades: [Int: Int] = [:]

        for (index, track) in tracks.enumerated() {
            for raw in track.genres {
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                let resolved = taxonomy.resolve(trimmed)
                for main in resolved.mains { byMain[main, default: []].insert(index) }
                guard !resolved.isMainTag else { continue }
                byTag[resolved.key, default: []].insert(index)
                tagMains[resolved.key, default: []].formUnion(resolved.mains)
                if let style = resolved.styleName { styleNames[resolved.key] = style }
                spellings[resolved.key, default: [:]][trimmed, default: 0] += 1
            }
            if let year = track.year, year > 0 {
                decades[year / 10 * 10, default: 0] += 1
            }
        }

        func pillName(_ key: String) -> String {
            if let style = styleNames[key] { return style }
            // The most common spelling in the library, ties broken alphabetically for stability.
            return spellings[key]?.max { $0.value == $1.value ? $0.key > $1.key : $0.value < $1.value }?.key ?? key
        }

        var pillsByMain: [String: [Pill]] = [:]
        for (key, mains) in tagMains {
            let pill = Pill(id: key, name: pillName(key), songCount: byTag[key]?.count ?? 0)
            for main in mains { pillsByMain[main, default: []].append(pill) }
        }

        columns = Self.sortedColumns(byMain.map { main, members in
            Column(id: main, songCount: members.count, pills: Self.sortedPills(pillsByMain[main] ?? []))
        })
        tracksByMain = byMain
        tracksByTag = byTag
        decadeCounts = decades
    }

    /// Songs matching the selection: any picked genre, and any picked decade (songs without a year
    /// are left out once a decade is picked).
    func matchingSongs(_ selection: QueueBuilderSelection) -> [Song] {
        matchingIndices(selection).map { tracks[$0].song }
    }

    func matchCount(_ selection: QueueBuilderSelection) -> Int {
        matchingIndices(selection).count
    }

    /// A shuffled queue of up to `count` matching songs, skipping `excludedIDs` (songs already queued).
    func build<R: RandomNumberGenerator>(
        _ selection: QueueBuilderSelection,
        count: Int,
        excluding excludedIDs: Set<String> = [],
        using generator: inout R
    ) -> [Song] {
        var seen = excludedIDs
        var result: [Song] = []
        for index in matchingIndices(selection).shuffled(using: &generator) {
            let song = tracks[index].song
            guard seen.insert(song.id).inserted else { continue }
            result.append(song)
            if result.count == count { break }
        }
        return result
    }

    func build(_ selection: QueueBuilderSelection, count: Int, excluding excludedIDs: Set<String> = []) -> [Song] {
        var generator = SystemRandomNumberGenerator()
        return build(selection, count: count, excluding: excludedIDs, using: &generator)
    }

    private func matchingIndices(_ selection: QueueBuilderSelection) -> [Int] {
        var candidates: Set<Int>
        if selection.hasGenre {
            candidates = []
            for main in selection.mains { candidates.formUnion(tracksByMain[main] ?? []) }
            for tag in selection.tags { candidates.formUnion(tracksByTag[tag] ?? []) }
        } else {
            candidates = Set(tracks.indices)
        }
        if !selection.decades.isEmpty {
            candidates = candidates.filter { index in
                guard let year = tracks[index].year, year > 0 else { return false }
                return selection.decades.contains(year / 10 * 10)
            }
        }
        return candidates.sorted()
    }
}
