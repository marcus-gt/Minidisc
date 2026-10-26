import Foundation
import SwiftSonic

/// An album's main genre: the tag the most of its tracks carry (#29). A compilation tagged with ten
/// genres belongs to one shelf instead of all ten.
nonisolated enum MainGenre {
    /// - Parameters:
    ///   - trackGenres: every track's genre tags.
    ///   - albumGenres: the album's own tags, in server order; they break ties and stand in when no
    ///     track has a tag.
    /// - Returns: the main genre in its first spelling, or `nil` when nothing is tagged.
    static func of(trackGenres: [[String]], albumGenres: [String]) -> String? {
        var counts: [String: Int] = [:]
        var spelling: [String: String] = [:]
        var firstSeen: [String: Int] = [:]
        for tags in trackGenres {
            // A track counts once per genre, however often the tag repeats.
            for key in Set(tags.compactMap(Self.key)) { counts[key, default: 0] += 1 }
            for tag in tags {
                guard let key = Self.key(tag) else { continue }
                if spelling[key] == nil { spelling[key] = tag.trimmingCharacters(in: .whitespacesAndNewlines) }
                if firstSeen[key] == nil { firstSeen[key] = firstSeen.count }
            }
        }
        let albumOrder = Dictionary(
            albumGenres.compactMap(Self.key).enumerated().map { ($0.element, $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )
        guard let best = counts.keys.min(by: { lhs, rhs in
            if counts[lhs] != counts[rhs] { return counts[lhs, default: 0] > counts[rhs, default: 0] }
            let left = albumOrder[lhs] ?? Int.max, right = albumOrder[rhs] ?? Int.max
            if left != right { return left < right }
            return firstSeen[lhs, default: 0] < firstSeen[rhs, default: 0]
        }) else {
            return albumGenres.lazy.compactMap { tag -> String? in
                Self.key(tag) == nil ? nil : tag.trimmingCharacters(in: .whitespacesAndNewlines)
            }.first
        }
        return spelling[best]
    }

    /// Case- and spacing-insensitive key; `nil` for an empty tag.
    static func key(_ tag: String) -> String? {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed.lowercased()
    }
}

/// Picks Home's genre shelves and their albums.
nonisolated enum HomeGenreShelves {
    static let shelfCount = 5
    static let albumsPerShelf = 20

    /// The biggest main genres, each with a daily selection of its albums.
    static func shelves(byMainGenre: [String: [AlbumID3]], day: String) -> [(name: String, albums: [AlbumID3])] {
        byMainGenre
            .filter { !$0.value.isEmpty }
            .sorted { lhs, rhs in
                lhs.value.count != rhs.value.count
                    ? lhs.value.count > rhs.value.count
                    : lhs.key.localizedStandardCompare(rhs.key) == .orderedAscending
            }
            .prefix(shelfCount)
            .map { (name: $0.key, albums: dailyPick($0.value, genre: $0.key, day: day)) }
    }

    /// A shuffle that stays the same for one genre during one day, so Home doesn't reshuffle on every
    /// refresh, and changes the next day.
    static func dailyPick(_ albums: [AlbumID3], genre: String, day: String, count: Int = albumsPerShelf) -> [AlbumID3] {
        // Sort first so the result doesn't depend on the order the albums arrived in.
        let ordered = albums.sorted { $0.id < $1.id }
        var generator = SeededRandomGenerator(seed: stableHash("\(day)|\(genre.lowercased())"))
        return Array(ordered.shuffled(using: &generator).prefix(count))
    }

    /// The local calendar day, e.g. "2026-10-26".
    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// FNV-1a: stable across launches, unlike `Hasher`.
    private static func stableHash(_ text: String) -> UInt64 {
        text.utf8.reduce(0xcbf2_9ce4_8422_2325) { ($0 ^ UInt64($1)) &* 0x0000_0100_0000_01b3 }
    }
}

/// SplitMix64, for reproducible shuffles.
nonisolated struct SeededRandomGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
