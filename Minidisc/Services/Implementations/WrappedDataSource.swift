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
///
/// Listens imported from other services (Spotify through the ListenBrainz importer) carry no recording
/// ID and their own title furniture ("Part I - Live", "Waltz For Debby - Live / Take 2") and artist
/// credits ("Moses Boyd, Kevin Haynes"), so a looser title-and-artist pass follows the exact one.
nonisolated struct WrappedLibraryMatcher: Sendable {
    private let byRecording: [String: Song]
    private let byTitleAndArtist: [String: Song]
    private let byBaseTitle: [String: [Song]]
    /// Library artists by normalised name, so a listen that matches no song still credits the artist.
    private let artistsByName: [String: (id: String, name: String)]
    /// Library albums by base title, for crediting an unmatched listen's album.
    private let albumsByTitle: [String: [Song]]

    init(songs: [Song]) {
        var byRecording: [String: Song] = [:]
        var byTitleAndArtist: [String: Song] = [:]
        var byBaseTitle: [String: [Song]] = [:]
        var artistsByName: [String: (id: String, name: String)] = [:]
        var albumsByTitle: [String: [Song]] = [:]
        for song in songs {
            if let mbid = song.musicBrainzId?.lowercased(), !mbid.isEmpty, byRecording[mbid] == nil {
                byRecording[mbid] = song
            }
            for artist in Self.artistNames(of: song) {
                let key = Self.key(title: song.title, artist: artist)
                if byTitleAndArtist[key] == nil { byTitleAndArtist[key] = song }
            }
            byBaseTitle[Self.baseTitle(song.title), default: []].append(song)
            for (id, name) in Self.artistCredits(of: song) {
                let key = NewReleaseMatching.normalisedName(name)
                if !key.isEmpty, artistsByName[key] == nil { artistsByName[key] = (id, name) }
            }
            if let album = song.album, song.albumId != nil {
                let key = Self.baseTitle(album)
                if albumsByTitle[key]?.contains(where: { $0.albumId == song.albumId }) != true {
                    albumsByTitle[key, default: []].append(song)
                }
            }
        }
        self.byRecording = byRecording
        self.byTitleAndArtist = byTitleAndArtist
        self.byBaseTitle = byBaseTitle
        self.artistsByName = artistsByName
        self.albumsByTitle = albumsByTitle
    }

    static let empty = WrappedLibraryMatcher(songs: [])

    func song(for listen: LBListen) -> Song? {
        if let mbid = listen.recordingMBID?.lowercased(), let song = byRecording[mbid] { return song }
        if let song = byTitleAndArtist[Self.key(title: listen.trackName, artist: listen.artistName)] { return song }
        return looseMatch(for: listen)
    }

    /// Same base title, an artist in common, and the best fit on album and take number.
    private func looseMatch(for listen: LBListen) -> Song? {
        guard let candidates = byBaseTitle[Self.baseTitle(listen.trackName)] else { return nil }
        let credited = Self.creditedNames(listen.artistName)
        let album = listen.releaseName.map(Self.baseTitle)
        let take = Self.takeNumber(listen.trackName)
        var best: (song: Song, score: Int)?
        for song in candidates {
            let artistScore = Self.artistScore(Self.artistNames(of: song).flatMap(Self.creditedNames), credited)
            guard artistScore > 0 else { continue }
            var score = artistScore * 10
            if let album, let songAlbum = song.album, Self.baseTitle(songAlbum) == album { score += 5 }
            if let take, Self.takeNumber(song.title) == take { score += 2 }
            if score > (best?.score ?? 0) { best = (song, score) }
        }
        return best?.song
    }

    /// A listen as a Wrapped play. A matched song lends its IDs, genre and length; an unmatched one
    /// still counts, under IDs of its own that group the same title, album and artist together, and
    /// credits the library's artist and album when their names match.
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
        let credited = Self.creditedNames(listen.artistName)
        let libraryArtist = credited.lazy.compactMap { artistsByName[$0] }.first
        let libraryAlbum = listen.releaseName.flatMap { release in
            albumsByTitle[Self.baseTitle(release)]?.first {
                Self.artistScore(Self.artistNames(of: $0).flatMap(Self.creditedNames), credited) > 0
            }
        }
        let artist = NewReleaseMatching.normalisedName(listen.artistName)
        let length = listenedSeconds ?? Self.assumedLength
        return WrappedPlay(
            timestamp: timestamp,
            trackId: WrappedIDs.externalPrefix + "track:" + Self.key(title: listen.trackName, artist: listen.artistName),
            trackTitle: listen.trackName,
            albumId: libraryAlbum?.albumId
                ?? listen.releaseName.map { WrappedIDs.externalPrefix + "album:" + NewReleaseMatching.normalisedTitle($0) + "|" + artist },
            albumTitle: libraryAlbum?.album ?? listen.releaseName,
            artistId: libraryArtist?.id ?? WrappedIDs.externalPrefix + "artist:" + artist,
            artistName: libraryArtist?.name ?? listen.artistName,
            genre: libraryAlbum.flatMap { $0.genres?.first?.name ?? $0.genre },
            durationListened: length, trackDuration: length
        )
    }

    /// Listens without a length (not every player sends one) count as a typical track.
    static let assumedLength: TimeInterval = 210

    private static func key(title: String, artist: String) -> String {
        NewReleaseMatching.normalisedTitle(title) + "|" + NewReleaseMatching.normalisedName(artist)
    }

    /// The title without Spotify's " - Live" style suffix or any bracketed part, "Pt." spelled out and
    /// spaces removed so "Part II c" equals "Part IIc": "Waltz For Debby - Live / Take 2" and
    /// "Waltz for Debby (take 2)" both become "waltzfordebby".
    static func baseTitle(_ title: String) -> String {
        var text = title
        if let dash = text.range(of: #"\s[-–—]\s"#, options: .regularExpression), dash.lowerBound > text.startIndex {
            text = String(text[..<dash.lowerBound])
        }
        text = text.replacingOccurrences(of: #"[\(\[][^\)\]]*[\)\]]"#, with: " ", options: .regularExpression)
        // Name folding, not title folding: that one drops "a" as an article, and "Part II a" needs it.
        return NewReleaseMatching.normalisedName(text)
            .replacingOccurrences(of: #"\bpt\b"#, with: "part", options: .regularExpression)
            .replacingOccurrences(of: " ", with: "")
    }

    /// "Take 2" in "Waltz for Debby (take 2)" or "… - Live / Take 2".
    static func takeNumber(_ title: String) -> Int? {
        guard let range = title.range(of: #"(?i)\btake\s*(\d+)"#, options: .regularExpression) else { return nil }
        return Int(title[range].filter(\.isNumber))
    }

    /// Each credited name of an artist string, normalised: "Moses Boyd, Kevin Haynes" and
    /// "Moses Boyd Exodus Feat. Kevin Haynes Grupo Elegua" both split into their names.
    static func creditedNames(_ artist: String) -> [String] {
        let parts = artist.replacingOccurrences(
            of: #"(?i)\s*(,|&|;|/|\s(feat\.?|ft\.?|featuring|with|and|x)\s)\s*"#,
            with: "\u{1F}", options: .regularExpression
        ).split(separator: "\u{1F}").map { NewReleaseMatching.normalisedName(String($0)) }
        var names = [NewReleaseMatching.normalisedName(artist)]
        for part in parts where !part.isEmpty && !names.contains(part) { names.append(part) }
        return names
    }

    /// 2 for a credited name in common, 1 when one contains the other ("Moses Boyd" in
    /// "Moses Boyd Exodus"), 0 otherwise. Short names only count when equal.
    private static func artistScore(_ songNames: [String], _ listenNames: [String]) -> Int {
        if !Set(songNames).isDisjoint(with: listenNames) { return 2 }
        let contained = songNames.contains { song in
            listenNames.contains { listen in
                min(song.count, listen.count) >= 4 && (song.contains(listen) || listen.contains(song))
            }
        }
        return contained ? 1 : 0
    }

    /// The song's own artist and each credited artist, so "A & B" also matches a listen credited to "A".
    private static func artistNames(of song: Song) -> [String] {
        var names = [song.artist].compactMap { $0 }
        names.append(contentsOf: song.artists?.map(\.name) ?? [])
        return names
    }

    private static func artistCredits(of song: Song) -> [(String, String)] {
        var credits: [(String, String)] = []
        if let id = song.artistId, let name = song.artist { credits.append((id, name)) }
        credits.append(contentsOf: song.artists?.map { ($0.id, $0.name) } ?? [])
        return credits
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
    private let songsByID: @Sendable ([String]) async -> [Song]
    private var matcher: (serverId: String, matcher: WrappedLibraryMatcher)?

    init(stats: StatsService, history: ListenHistoryStore,
         username: @escaping @Sendable () async -> String?,
         librarySongs: @escaping @Sendable () async -> [Song]?,
         songsByID: @escaping @Sendable ([String]) async -> [Song] = { _ in [] }) {
        self.stats = stats
        self.history = history
        self.username = username
        self.librarySongs = librarySongs
        self.songsByID = songsByID
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

    /// A Wrapped radio: the period's library tracks in a play-count-weighted shuffle, and the
    /// period's top tracks as seeds for similar songs once those run out (#69).
    nonisolated struct Radio: Sendable {
        let tracks: [DisplayableSong]
        let seedIDs: [String]
    }

    static let radioSeedCount = 10

    /// The period's most played library tracks, most listened first. Listens that don't match a
    /// library song can't be played, so they are left out.
    func topLibraryTracks(for period: WrappedPeriod, serverId: String, limit: Int, calendar: Calendar) async -> [TopTrackEntry] {
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

    func radio(for period: WrappedPeriod, serverId: String, calendar: Calendar) async -> Radio {
        let ranked = await topLibraryTracks(for: period, serverId: serverId, limit: .max, calendar: calendar)
        var generator = SystemRandomNumberGenerator()
        let order = Self.weightedShuffle(ranked, weight: { Double($0.playCount) }, using: &generator)
        let tracks = await songs(order)
        Logger.wrapped.info("[WRAPPED] radio for \(period.displayName, privacy: .public): \(ranked.count, privacy: .public) tracks played, \(tracks.count, privacy: .public) queued")
        return Radio(tracks: tracks, seedIDs: ranked.prefix(Self.radioSeedCount).map(\.trackId))
    }

    /// Top Tracks rows as a queue, in the order shown. Entries outside the library are skipped.
    func songs(_ entries: [TopTrackEntry]) async -> [DisplayableSong] {
        let library = entries.filter { WrappedIDs.isLibraryID($0.trackId) }
        let indexed = Dictionary(await songsByID(library.map(\.trackId)).map { ($0.id, $0) },
                                 uniquingKeysWith: { first, _ in first })
        return library.map { entry in
            indexed[entry.trackId].map { DisplayableSong(from: $0) } ?? Self.basicSong(entry)
        }
    }

    /// A shuffle where heavier items tend to come first (Efraimidis–Spirakis): each item draws
    /// `u^(1/weight)` and the largest draws lead. A track played ten times usually comes early, one
    /// played once can still turn up anywhere.
    nonisolated static func weightedShuffle<T>(_ items: [T], weight: (T) -> Double,
                                               using generator: inout some RandomNumberGenerator) -> [T] {
        items
            .map { item in (item, pow(Double.random(in: Double.ulpOfOne..<1, using: &generator), 1 / max(weight(item), 1))) }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    /// A song the index doesn't know yet; the player resolves the stream from the ID alone.
    private nonisolated static func basicSong(_ entry: TopTrackEntry) -> DisplayableSong {
        DisplayableSong(
            id: entry.trackId, title: entry.title, artist: entry.artistName, albumId: nil,
            albumName: entry.albumTitle, artistId: nil, genre: nil, duration: 0, trackNumber: nil,
            isDownloaded: false, coverArtId: entry.trackId, audioFormat: nil,
            replayGainTrackGain: nil, replayGainTrackPeak: nil, replayGainAlbumGain: nil,
            replayGainAlbumPeak: nil, replayGainBaseGain: nil, replayGainFallbackGain: nil
        )
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
