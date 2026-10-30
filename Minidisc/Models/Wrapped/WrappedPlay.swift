import Foundation

/// One play, whichever source recorded it: this phone's playback events or ListenBrainz listens (#16).
/// Wrapped is aggregated from these, so both sources produce the same recap.
nonisolated struct WrappedPlay: Sendable, Equatable {
    var timestamp: Date
    var trackId: String
    var trackTitle: String
    var albumId: String?
    var albumTitle: String?
    var artistId: String?
    var artistName: String
    var genre: String?
    var durationListened: TimeInterval
    var trackDuration: TimeInterval
}

/// Builds `WrappedData` from plays. Pure, so it can run anywhere.
nonisolated enum WrappedAggregator {

    static func aggregate(
        plays: [WrappedPlay],
        period: WrappedPeriod,
        serverId: String,
        periodRange: (start: Date, end: Date),
        calendar: Calendar
    ) -> WrappedData {
        guard !plays.isEmpty else {
            return WrappedData(
                period: period, serverId: serverId, generatedAt: Date(),
                totalSecondsListened: 0, totalTracksPlayed: 0,
                totalUniqueTracks: 0, totalUniqueArtists: 0, totalUniqueAlbums: 0,
                topTracks: [], topAlbums: [], topArtists: [],
                dominantGenre: nil, streakDays: 0,
                firstTrackOfPeriod: nil, lastTrackOfPeriod: nil
            )
        }

        let totalSecondsListened = plays.reduce(0.0) { $0 + effectiveDuration(for: $1) }
        let totalUniqueTracks = Set(plays.map(\.trackId)).count
        let totalUniqueArtists = Set(plays.compactMap(\.artistId)).count
        let totalUniqueAlbums = Set(plays.compactMap(\.albumId)).count

        let topTracks = buildTopTracks(from: plays)
        let topAlbums = buildTopAlbums(from: plays)
        let topArtists = buildTopArtists(from: plays)
        let dominantGenre = buildDominantGenre(from: plays)
        let streak = buildStreak(from: plays, periodRange: periodRange, calendar: calendar)
        let (first, last) = buildFirstLast(from: plays)

        return WrappedData(
            period: period,
            serverId: serverId,
            generatedAt: Date(),
            totalSecondsListened: totalSecondsListened,
            totalTracksPlayed: plays.count,
            totalUniqueTracks: totalUniqueTracks,
            totalUniqueArtists: totalUniqueArtists,
            totalUniqueAlbums: totalUniqueAlbums,
            topTracks: topTracks,
            topAlbums: topAlbums,
            topArtists: topArtists,
            dominantGenre: dominantGenre,
            streakDays: streak,
            firstTrackOfPeriod: first,
            lastTrackOfPeriod: last
        )
    }

    static func buildTopTracks(from plays: [WrappedPlay]) -> [TopTrackEntry] {
        var groups: [String: (duration: TimeInterval, count: Int, title: String, artist: String, album: String?)] = [:]
        for e in plays {
            let d = effectiveDuration(for: e)
            if var g = groups[e.trackId] {
                g.duration += d
                g.count += 1
                groups[e.trackId] = g
            } else {
                groups[e.trackId] = (d, 1, e.trackTitle, e.artistName, e.albumTitle)
            }
        }
        let sorted = groups.sorted {
            if $0.value.count != $1.value.count { return $0.value.count > $1.value.count }
            if $0.value.duration != $1.value.duration { return $0.value.duration > $1.value.duration }
            return $0.key < $1.key
        }
        return sorted.prefix(10).enumerated().map { idx, pair in
            TopTrackEntry(
                rank: idx + 1,
                trackId: pair.key,
                title: pair.value.title,
                artistName: pair.value.artist,
                albumTitle: pair.value.album,
                totalSecondsListened: pair.value.duration,
                playCount: pair.value.count
            )
        }
    }

    static func buildTopAlbums(from plays: [WrappedPlay]) -> [TopAlbumEntry] {
        var groups: [String: (duration: TimeInterval, count: Int, tracks: Set<String>, title: String, artist: String)] = [:]
        for e in plays {
            guard let albumId = e.albumId else { continue }
            let d = effectiveDuration(for: e)
            if var g = groups[albumId] {
                g.duration += d
                g.count += 1
                g.tracks.insert(e.trackId)
                groups[albumId] = g
            } else {
                groups[albumId] = (d, 1, [e.trackId], e.albumTitle ?? "", e.artistName)
            }
        }
        let sorted = groups.sorted {
            if $0.value.count != $1.value.count { return $0.value.count > $1.value.count }
            if $0.value.duration != $1.value.duration { return $0.value.duration > $1.value.duration }
            return $0.key < $1.key
        }
        return sorted.prefix(10).enumerated().map { idx, pair in
            TopAlbumEntry(
                rank: idx + 1,
                albumId: pair.key,
                title: pair.value.title,
                artistName: pair.value.artist,
                totalSecondsListened: pair.value.duration,
                playCount: pair.value.count,
                uniqueTracks: pair.value.tracks.count
            )
        }
    }

    static func buildTopArtists(from plays: [WrappedPlay]) -> [TopArtistEntry] {
        var groups: [String: (duration: TimeInterval, count: Int, tracks: Set<String>, name: String)] = [:]
        for e in plays {
            guard let artistId = e.artistId else { continue }
            let d = effectiveDuration(for: e)
            if var g = groups[artistId] {
                g.duration += d
                g.count += 1
                g.tracks.insert(e.trackId)
                groups[artistId] = g
            } else {
                groups[artistId] = (d, 1, [e.trackId], e.artistName)
            }
        }
        let sorted = groups.sorted {
            if $0.value.duration != $1.value.duration { return $0.value.duration > $1.value.duration }
            if $0.value.count != $1.value.count { return $0.value.count > $1.value.count }
            return $0.key < $1.key
        }
        return sorted.prefix(10).enumerated().map { idx, pair in
            TopArtistEntry(
                rank: idx + 1,
                artistId: pair.key,
                name: pair.value.name,
                totalSecondsListened: pair.value.duration,
                playCount: pair.value.count,
                uniqueTracks: pair.value.tracks.count
            )
        }
    }

    static func buildDominantGenre(from plays: [WrappedPlay]) -> String? {
        var durations: [String: TimeInterval] = [:]
        for e in plays {
            guard let genre = e.genre else { continue }
            durations[genre, default: 0] += effectiveDuration(for: e)
        }
        guard !durations.isEmpty else { return nil }
        return durations.max {
            if $0.value != $1.value { return $0.value < $1.value }
            return $0.key > $1.key
        }?.key
    }

    static func buildStreak(
        from plays: [WrappedPlay],
        periodRange: (start: Date, end: Date),
        calendar: Calendar
    ) -> Int {
        let eventDays = Set(plays.map { calendar.startOfDay(for: $0.timestamp) })
        let today = calendar.startOfDay(for: Date())
        let referenceDay: Date
        if today >= periodRange.start && today < periodRange.end {
            referenceDay = today
        } else {
            let lastInstant = calendar.date(byAdding: .second, value: -1, to: periodRange.end)!
            referenceDay = calendar.startOfDay(for: lastInstant)
        }
        guard eventDays.contains(referenceDay) else { return 0 }
        var streak = 0
        var day = referenceDay
        while eventDays.contains(day) {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return streak
    }

    /// Caps a single event's contribution at its track duration.
    /// Prevents wall-clock inflation (paused time counted as listened time) from
    /// distorting Wrapped totals for existing data. Falls back to a 600 s ceiling
    /// when trackDuration was not recorded (value of 0).
    static func effectiveDuration(for play: WrappedPlay) -> TimeInterval {
        guard play.trackDuration > 0 else {
            return min(play.durationListened, 600)
        }
        return min(play.durationListened, play.trackDuration)
    }

    static func buildFirstLast(from plays: [WrappedPlay]) -> (first: TopTrackEntry?, last: TopTrackEntry?) {
        guard !plays.isEmpty,
              let earliest = plays.min(by: { $0.timestamp < $1.timestamp }),
              let latest = plays.max(by: { $0.timestamp < $1.timestamp })
        else { return (nil, nil) }
        let first = TopTrackEntry(
            rank: 0, trackId: earliest.trackId, title: earliest.trackTitle,
            artistName: earliest.artistName, albumTitle: earliest.albumTitle,
            totalSecondsListened: effectiveDuration(for: earliest), playCount: 1
        )
        let last = TopTrackEntry(
            rank: 0, trackId: latest.trackId, title: latest.trackTitle,
            artistName: latest.artistName, albumTitle: latest.albumTitle,
            totalSecondsListened: effectiveDuration(for: latest), playCount: 1
        )
        return (first, last)
    }

    /// The most played tracks of a period, for the yearly Wrapped playlist.
    static func topTracks(from plays: [WrappedPlay], limit: Int) -> [TopTrackEntry] {
        var groups: [String: (duration: TimeInterval, count: Int, title: String, artist: String, album: String?)] = [:]
        for e in plays {
            let d = effectiveDuration(for: e)
            if var g = groups[e.trackId] {
                g.duration += d
                g.count += 1
                groups[e.trackId] = g
            } else {
                groups[e.trackId] = (d, 1, e.trackTitle, e.artistName, e.albumTitle)
            }
        }
        let sorted = groups.sorted {
            if $0.value.duration != $1.value.duration { return $0.value.duration > $1.value.duration }
            return $0.key < $1.key
        }
        return sorted.prefix(limit).enumerated().map { idx, pair in
            TopTrackEntry(
                rank: idx + 1,
                trackId: pair.key,
                title: pair.value.title,
                artistName: pair.value.artist,
                albumTitle: pair.value.album,
                totalSecondsListened: pair.value.duration,
                playCount: pair.value.count
            )
        }
    }
}
