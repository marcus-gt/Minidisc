import Foundation
import OSLog
import SwiftSonic

/// Where Wrapped's plays come from (#16).
nonisolated enum WrappedSourceKind: Sendable, Equatable {
    /// The ListenBrainz history: every device and player that scrobbles there.
    case listenBrainz
    /// Plays this app recorded on this phone.
    case device
}

/// Plays that came from outside the library carry IDs with this prefix, so the screens can show them
/// without trying to open or draw a cover for something the server doesn't have.
nonisolated enum WrappedIDs {
    static let externalPrefix = "lb:"
    static func isLibraryID(_ id: String) -> Bool { !id.hasPrefix(externalPrefix) }
}

/// Matches ListenBrainz listens to library songs: by MusicBrainz recording ID, then by title and artist.
nonisolated struct WrappedLibraryMatcher: Sendable {
    private let byRecording: [String: Song]
    private let byTitleAndArtist: [String: Song]

    init(songs: [Song]) {
        var byRecording: [String: Song] = [:]
        var byTitleAndArtist: [String: Song] = [:]
        for song in songs {
            if let mbid = song.musicBrainzId?.lowercased(), !mbid.isEmpty, byRecording[mbid] == nil {
                byRecording[mbid] = song
            }
            for artist in Self.artistNames(of: song) {
                let key = Self.key(title: song.title, artist: artist)
                if byTitleAndArtist[key] == nil { byTitleAndArtist[key] = song }
            }
        }
        self.byRecording = byRecording
        self.byTitleAndArtist = byTitleAndArtist
    }

    static let empty = WrappedLibraryMatcher(songs: [])

    func song(for listen: LBListen) -> Song? {
        if let mbid = listen.recordingMBID?.lowercased(), let song = byRecording[mbid] { return song }
        return byTitleAndArtist[Self.key(title: listen.trackName, artist: listen.artistName)]
    }

    /// A listen as a Wrapped play. A matched song lends its IDs, genre and length; an unmatched one
    /// still counts, under IDs of its own that group the same title, album and artist together.
    func play(for listen: LBListen) -> WrappedPlay {
        let listenedSeconds = listen.durationMs.map { TimeInterval($0) / 1000 }
        let timestamp = Date(timeIntervalSince1970: TimeInterval(listen.listenedAt))
        if let song = song(for: listen) {
            let length = song.duration.map(TimeInterval.init) ?? listenedSeconds ?? Self.assumedLength
            return WrappedPlay(
                timestamp: timestamp, trackId: song.id, trackTitle: song.title,
                albumId: song.albumId, albumTitle: song.album, artistId: song.artistId,
                artistName: song.artist ?? listen.artistName,
                genre: song.genres?.first?.name ?? song.genre,
                durationListened: length, trackDuration: length
            )
        }
        let artist = NewReleaseMatching.normalisedName(listen.artistName)
        let length = listenedSeconds ?? Self.assumedLength
        return WrappedPlay(
            timestamp: timestamp,
            trackId: WrappedIDs.externalPrefix + "track:" + Self.key(title: listen.trackName, artist: listen.artistName),
            trackTitle: listen.trackName,
            albumId: listen.releaseName.map { WrappedIDs.externalPrefix + "album:" + NewReleaseMatching.normalisedTitle($0) + "|" + artist },
            albumTitle: listen.releaseName,
            artistId: WrappedIDs.externalPrefix + "artist:" + artist,
            artistName: listen.artistName,
            genre: nil,
            durationListened: length, trackDuration: length
        )
    }

    /// Listens without a length (not every player sends one) count as a typical track.
    static let assumedLength: TimeInterval = 210

    private static func key(title: String, artist: String) -> String {
        NewReleaseMatching.normalisedTitle(title) + "|" + NewReleaseMatching.normalisedName(artist)
    }

    /// The song's own artist and each credited artist, so "A & B" also matches a listen credited to "A".
    private static func artistNames(of song: Song) -> [String] {
        var names = [song.artist].compactMap { $0 }
        names.append(contentsOf: song.artists?.map(\.name) ?? [])
        return names
    }
}

/// Wrapped's data: ListenBrainz when an account is set, the phone's own plays otherwise (#16).
actor WrappedDataSource {
    struct Result: Sendable {
        let data: WrappedData
        let source: WrappedSourceKind
        /// ListenBrainz couldn't be reached and nothing was cached, so the phone's plays are shown.
        let fellBack: Bool
    }

    private let stats: StatsService
    private let history: ListenHistoryStore
    private let username: @Sendable () async -> String?
    private let librarySongs: @Sendable () async -> [Song]?
    private var matcher: (serverId: String, matcher: WrappedLibraryMatcher)?

    init(stats: StatsService, history: ListenHistoryStore,
         username: @escaping @Sendable () async -> String?,
         librarySongs: @escaping @Sendable () async -> [Song]?) {
        self.stats = stats
        self.history = history
        self.username = username
        self.librarySongs = librarySongs
    }

    func source() async -> WrappedSourceKind {
        await username() == nil ? .device : .listenBrainz
    }

    func wrappedData(for period: WrappedPeriod, serverId: String, calendar: Calendar, refresh: Bool = false) async -> Result {
        let range = period.dateRange(in: calendar)
        if let plays = await listenBrainzPlays(range: range, serverId: serverId, calendar: calendar, refresh: refresh) {
            let data = WrappedAggregator.aggregate(plays: plays, period: period, serverId: serverId,
                                                   periodRange: range, calendar: calendar)
            return Result(data: data, source: .listenBrainz, fellBack: false)
        }
        let fellBack = await username() != nil
        let plays = await stats.plays(for: period, serverId: serverId, calendar: calendar)
        let data = WrappedAggregator.aggregate(plays: plays, period: period, serverId: serverId,
                                               periodRange: range, calendar: calendar)
        return Result(data: data, source: .device, fellBack: fellBack)
    }

    /// The most played library tracks of a year, for the yearly Wrapped playlist. Listens that don't
    /// match a library song can't go into a server playlist, so they are left out.
    func topLibraryTracks(year: Int, serverId: String, limit: Int, calendar: Calendar) async -> [TopTrackEntry] {
        let period = WrappedPeriod.year(year)
        let range = period.dateRange(in: calendar)
        // `??` can't take an async right-hand side.
        let plays: [WrappedPlay]
        if let fromListenBrainz = await listenBrainzPlays(range: range, serverId: serverId, calendar: calendar, refresh: false) {
            plays = fromListenBrainz
        } else {
            plays = await stats.plays(for: period, serverId: serverId, calendar: calendar)
        }
        let libraryPlays = plays.filter { WrappedIDs.isLibraryID($0.trackId) }
        return WrappedAggregator.topTracks(from: libraryPlays, limit: limit)
    }

    /// The first year with listens: the ListenBrainz history's, or the current year for the phone.
    func firstYear(calendar: Calendar) async -> Int {
        let current = calendar.component(.year, from: Date())
        guard let user = await username(),
              let year = try? await history.firstYear(user: user, calendar: calendar) else { return current }
        return min(year, current)
    }

    private func listenBrainzPlays(range: (start: Date, end: Date), serverId: String, calendar: Calendar,
                                   refresh: Bool) async -> [WrappedPlay]? {
        guard let user = await username() else { return nil }
        do {
            let listens = try await history.listens(user: user, from: range.start, to: range.end,
                                                    calendar: calendar, refresh: refresh)
            let matcher = await libraryMatcher(serverId: serverId)
            return listens.map(matcher.play)
        } catch is CancellationError {
            return nil
        } catch {
            Logger.wrapped.warning("[WRAPPED] ListenBrainz history unavailable: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Built once per server; listens are matched against that server's library.
    private func libraryMatcher(serverId: String) async -> WrappedLibraryMatcher {
        if let matcher, matcher.serverId == serverId { return matcher.matcher }
        // An incomplete index matches nothing yet; try again next time rather than keeping the gap.
        guard let songs = await librarySongs() else { return .empty }
        let built = WrappedLibraryMatcher(songs: songs)
        matcher = (serverId, built)
        return built
    }
}
