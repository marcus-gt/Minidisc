import Foundation
import OSLog
import SwiftSonic

/// Home's "Artists for You" shelf (#63): a daily blend of the artists you play most, ones you
/// used to play but haven't lately, and ones in the library you've barely tried.
actor ArtistShelfService {
    /// The library's artists and its play history, from the server.
    nonisolated struct Sources: Sendable {
        /// Albums by play count, most played first (`getAlbumList2` frequent).
        var mostPlayedAlbums: @Sendable () async throws -> [AlbumID3]
        /// Albums by last play, newest first (`getAlbumList2` recent).
        var recentlyPlayedAlbums: @Sendable () async throws -> [AlbumID3]
        var libraryArtists: @Sendable () async throws -> [ArtistID3]
    }

    private let sources: Sources
    /// One pick per server and day, so Home doesn't reshuffle on every visit.
    private var cached: (key: String, artists: [ArtistID3])?

    init(sources: Sources) {
        self.sources = sources
    }

    init(libraryService: any LibraryServiceProtocol) {
        self.init(sources: Sources(
            mostPlayedAlbums: { try await libraryService.mostPlayedAlbums(size: 200) },
            recentlyPlayedAlbums: { try await libraryService.recentlyPlayedAlbums(size: 100) },
            libraryArtists: { try await libraryService.artists().flatMap(\.artist) }
        ))
    }

    /// Today's artists for `serverID`. Throws only when nothing could be loaded at all.
    func artists(serverID: UUID, now: Date = .now, calendar: Calendar = .current) async throws -> [ArtistID3] {
        let key = "\(serverID.uuidString)|\(HomeGenreShelves.dayKey(for: now, calendar: calendar))"
        if let cached, cached.key == key { return cached.artists }

        async let frequent = sources.mostPlayedAlbums()
        async let recent = sources.recentlyPlayedAlbums()
        async let library = sources.libraryArtists()
        let libraryArtists = try await library
        let picked = ArtistShelfPicker.pick(
            mostPlayed: (try? await frequent) ?? [],
            recentlyPlayed: (try? await recent) ?? [],
            library: libraryArtists,
            now: now,
            seed: key
        )
        try Task.checkCancellation()
        Logger.library.info("[ARTIST-SHELF] \(picked.count, privacy: .public) artists from \(libraryArtists.count, privacy: .public)")
        cached = (key, picked)
        return picked
    }

    /// Forgets today's pick, for pull-to-refresh after the library changed.
    func invalidate() {
        cached = nil
    }
}

/// The shelf's selection, kept apart from loading so it can be tested.
nonisolated enum ArtistShelfPicker {
    static let shelfSize = 12
    /// Roughly half favourites, a third "not in a while" and the rest new to you.
    static let favoriteCount = 6
    static let dormantCount = 4
    /// No plays for this long counts as "not in a while"...
    static let dormantAfter: TimeInterval = 90 * day
    /// ...or for half the play history, when the server has kept less than twice that, but never
    /// less than this.
    static let shortestDormancy: TimeInterval = 14 * day
    private static let day: TimeInterval = 24 * 60 * 60
    /// Artists with at most this many plays still count as barely tried.
    static let barelyPlayed = 2
    /// The most played artists the favourites are drawn from.
    static let favoritePool = 18
    /// The most played dormant artists the "not in a while" picks are drawn from.
    static let dormantPool = 20

    struct Listening: Equatable {
        var plays = 0
        var lastPlayed: Date?
    }

    /// Plays and last play per artist, from the albums' counters. An album in both lists counts once.
    static func listening(from albums: [AlbumID3]) -> [String: Listening] {
        var result: [String: Listening] = [:]
        var seen = Set<String>()
        for album in albums where seen.insert(album.id).inserted {
            guard let artistID = album.artistId, !artistID.isEmpty else { continue }
            var entry = result[artistID, default: Listening()]
            entry.plays += album.playCount ?? 0
            if let played = album.played {
                entry.lastPlayed = max(entry.lastPlayed ?? played, played)
            }
            result[artistID] = entry
        }
        return result
    }

    static func pick(mostPlayed: [AlbumID3], recentlyPlayed: [AlbumID3], library: [ArtistID3],
                     now: Date, seed: String) -> [ArtistID3] {
        var generator = SeededRandomGenerator(seed: stableHash(seed))
        let artists = library.filter(isRealArtist)
        let byID = Dictionary(artists.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let listening = listening(from: mostPlayed + recentlyPlayed)
        let cutoff = now.addingTimeInterval(-dormancy(listening: listening, now: now))

        // Recent: played after the cutoff. Servers that don't report when an album was played
        // fall back to the order of the recently played list.
        let recentIDs = Set(recentlyPlayed.enumerated().compactMap { index, album -> String? in
            guard let id = album.artistId else { return nil }
            if let played = album.played { return played >= cutoff ? id : nil }
            return index < 50 ? id : nil
        })

        // Sorted by plays, then ID, so the seed alone decides the shuffle.
        let played = listening.filter { $0.value.plays > barelyPlayed && byID[$0.key] != nil }
            .sorted { $0.value.plays != $1.value.plays ? $0.value.plays > $1.value.plays : $0.key < $1.key }
            .map(\.key)
        let favorites = Array(played.prefix(favoritePool)).shuffled(using: &generator)
        let dormant = Array(played.filter { !recentIDs.contains($0) && !favorites.prefix(favoriteCount).contains($0) }
            .prefix(dormantPool)).shuffled(using: &generator)
        let fresh = artists.filter { (listening[$0.id]?.plays ?? 0) <= barelyPlayed }
            .map(\.id).sorted().shuffled(using: &generator)

        var chosen: [String] = []
        func take(_ pool: [String], _ count: Int) {
            var added = 0
            for id in pool where added < count && chosen.count < shelfSize && !chosen.contains(id) {
                chosen.append(id)
                added += 1
            }
        }
        take(favorites, favoriteCount)
        take(dormant, dormantCount)
        take(fresh, shelfSize - chosen.count)
        // A small or new library fills up from whatever is left.
        for pool in [favorites, dormant, played, fresh] { take(pool, shelfSize) }

        return chosen.shuffled(using: &generator).compactMap { byID[$0] }
    }

    /// How long without plays counts as dormant: a server that has only kept a few months of
    /// plays would otherwise have no dormant artists at all.
    static func dormancy(listening: [String: Listening], now: Date) -> TimeInterval {
        guard let earliest = listening.values.compactMap(\.lastPlayed).min() else { return dormantAfter }
        return min(dormantAfter, max(shortestDormancy, now.timeIntervalSince(earliest) / 2))
    }

    /// Compilations' "Various Artists" and unknown artists aren't anyone to discover.
    private static func isRealArtist(_ artist: ArtistID3) -> Bool {
        let name = artist.name.trimmingCharacters(in: .whitespaces).lowercased()
        return !name.isEmpty && name != "various artists" && name != "[unknown artist]" && (artist.albumCount ?? 1) > 0
    }

    /// FNV-1a: stable across launches, unlike `Hasher`.
    private static func stableHash(_ text: String) -> UInt64 {
        text.utf8.reduce(0xcbf2_9ce4_8422_2325) { ($0 ^ UInt64($1)) &* 0x0000_0100_0000_01b3 }
    }
}
