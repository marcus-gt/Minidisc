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
    private let byBaseTitle: [String: [Candidate]]
    /// Library artists by normalised name, so a listen that matches no song still credits the artist.
    private let artistsByName: [String: (id: String, name: String)]
    /// Library albums by base title, for crediting an unmatched listen's album.
    private let albumsByTitle: [String: [Candidate]]

    /// A library song with what the loose pass compares, worked out once rather than per listen.
    private struct Candidate: Sendable {
        let song: Song
        let names: [String]
        let albumBase: String?
        let take: Int?

        init(_ song: Song) {
            self.song = song
            names = WrappedLibraryMatcher.artistNames(of: song).flatMap(WrappedLibraryMatcher.creditedNames)
            albumBase = song.album.map(WrappedLibraryMatcher.baseTitle)
            take = WrappedLibraryMatcher.takeNumber(song.title)
        }
    }

    init(songs: [Song]) {
        var byRecording: [String: Song] = [:]
        var byTitleAndArtist: [String: Song] = [:]
        var byBaseTitle: [String: [Candidate]] = [:]
        var artistsByName: [String: (id: String, name: String)] = [:]
        var albumsByTitle: [String: [Candidate]] = [:]
        for song in songs {
            if let mbid = song.musicBrainzId?.lowercased(), !mbid.isEmpty, byRecording[mbid] == nil {
                byRecording[mbid] = song
            }
            for artist in Self.artistNames(of: song) {
                let key = Self.key(title: song.title, artist: artist)
                if byTitleAndArtist[key] == nil { byTitleAndArtist[key] = song }
            }
            let candidate = Candidate(song)
            byBaseTitle[Self.baseTitle(song.title), default: []].append(candidate)
            for (id, name) in Self.artistCredits(of: song) {
                let key = NewReleaseMatching.normalisedName(name)
                if !key.isEmpty, artistsByName[key] == nil { artistsByName[key] = (id, name) }
            }
            if let key = candidate.albumBase, song.albumId != nil,
               albumsByTitle[key]?.contains(where: { $0.song.albumId == song.albumId }) != true {
                albumsByTitle[key, default: []].append(candidate)
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
        for candidate in candidates {
            let artistScore = Self.artistScore(candidate.names, credited)
            guard artistScore > 0 else { continue }
            var score = artistScore * 10
            if let album, candidate.albumBase == album { score += 5 }
            if let take, candidate.take == take { score += 2 }
            if score > (best?.score ?? 0) { best = (candidate.song, score) }
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
            albumsByTitle[Self.baseTitle(release)]?.first { Self.artistScore($0.names, credited) > 0 }?.song
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

    /// Plays for many listens. A history repeats the same listen often (one song played 40 times),
    /// so each distinct listen is matched once and its play reused with the listen's own time.
    func plays(for listens: [LBListen]) -> [WrappedPlay] {
        var matched: [String: WrappedPlay] = [:]
        return listens.map { listen in
            let key = [listen.trackName, listen.artistName, listen.releaseName ?? "", listen.recordingMBID ?? "",
                       listen.durationMs.map(String.init) ?? ""].joined(separator: "\u{1F}")
            if var play = matched[key] {
                play.timestamp = Date(timeIntervalSince1970: TimeInterval(listen.listenedAt))
                return play
            }
            let play = play(for: listen)
            matched[key] = play
            return play
        }
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
        if let dash = Patterns.dash.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           dash.range.location > 0, let range = Range(dash.range, in: text) {
            text = String(text[..<range.lowerBound])
        }
        text = Patterns.replace(Patterns.brackets, in: text, with: " ")
        // Name folding, not title folding: that one drops "a" as an article, and "Part II a" needs it.
        return Patterns.replace(Patterns.part, in: NewReleaseMatching.normalisedName(text), with: "part")
            .replacingOccurrences(of: " ", with: "")
    }

    /// "Take 2" in "Waltz for Debby (take 2)" or "… - Live / Take 2".
    static func takeNumber(_ title: String) -> Int? {
        guard let match = Patterns.take.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
              let range = Range(match.range(at: 1), in: title) else { return nil }
        return Int(title[range])
    }

    /// Compiled once: matching a whole history runs these tens of thousands of times.
    private enum Patterns {
        static let dash = try! NSRegularExpression(pattern: #"\s[-–—]\s"#)
        static let brackets = try! NSRegularExpression(pattern: #"[\(\[][^\)\]]*[\)\]]"#)
        static let part = try! NSRegularExpression(pattern: #"\bpt\b"#)
        static let take = try! NSRegularExpression(pattern: #"\btake\s*(\d+)"#, options: .caseInsensitive)
        static let credits = try! NSRegularExpression(
            pattern: #"\s*(,|&|;|/|\s(feat\.?|ft\.?|featuring|with|and|x)\s)\s*"#, options: .caseInsensitive
        )

        static func replace(_ pattern: NSRegularExpression, in text: String, with template: String) -> String {
            pattern.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
        }
    }

    /// Each credited name of an artist string, normalised: "Moses Boyd, Kevin Haynes" and
    /// "Moses Boyd Exodus Feat. Kevin Haynes Grupo Elegua" both split into their names.
    static func creditedNames(_ artist: String) -> [String] {
        let parts = Patterns.replace(Patterns.credits, in: artist, with: "\u{1F}")
            .split(separator: "\u{1F}").map { NewReleaseMatching.normalisedName(String($0)) }
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
    fileprivate static func artistNames(of song: Song) -> [String] {
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
    private let moodScorer: (any MoodScoring)?
    private let now: @Sendable () -> Date
    private var matcher: (serverId: String, matcher: WrappedLibraryMatcher)?

    /// The plays behind a recap, kept briefly: the recap, its stat cards, the mood and the radio all
    /// read the same period one after the other (#70).
    private struct CachedPlays {
        let key: String
        let plays: Plays
        let storedAt: Date
    }
    private var playsCache: [CachedPlays] = []
    static let playsCacheLifetime: TimeInterval = 60
    static let playsCacheSize = 4

    nonisolated struct Plays: Sendable {
        let plays: [WrappedPlay]
        let range: (start: Date, end: Date)
        let source: WrappedSourceKind
        let fellBack: Bool
    }

    init(stats: StatsService, history: ListenHistoryStore,
         username: @escaping @Sendable () async -> String?,
         librarySongs: @escaping @Sendable () async -> [Song]?,
         songsByID: @escaping @Sendable ([String]) async -> [Song] = { _ in [] },
         moodScorer: (any MoodScoring)? = nil,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.stats = stats
        self.history = history
        self.username = username
        self.librarySongs = librarySongs
        self.songsByID = songsByID
        self.moodScorer = moodScorer
        self.now = now
    }

    func source() async -> WrappedSourceKind {
        await username() == nil ? .device : .listenBrainz
    }

    func wrappedData(for period: WrappedPeriod, serverId: String, calendar: Calendar, refresh: Bool = false,
                     progress: ListenHistoryStore.Progress? = nil) async -> Result {
        let loaded = await plays(for: period, serverId: serverId, calendar: calendar, refresh: refresh, progress: progress)
        let data = WrappedAggregator.aggregate(plays: loaded.plays, period: period, serverId: serverId,
                                               periodRange: loaded.range, calendar: calendar)
        return Result(data: data, source: loaded.source, fellBack: loaded.fellBack)
    }

    /// The stat cards' charts (#70). A year or month is compared with the same one a year earlier.
    func insights(for period: WrappedPeriod, serverId: String, calendar: Calendar) async -> WrappedInsights {
        let current = await plays(for: period, serverId: serverId, calendar: calendar)
        var previous: [WrappedPlay]?
        if let earlier = WrappedInsightsBuilder.comparisonPeriod(for: period) {
            previous = await plays(for: earlier, serverId: serverId, calendar: calendar).plays
        }
        return WrappedInsightsBuilder.build(period: period, plays: current.plays, previousPlays: previous, calendar: calendar)
    }

    /// How many of the period's most played library tracks get mood scores; covers most plays while
    /// keeping the first load (AudioMuse answers one track per request) to seconds.
    static let moodTrackLimit = 300

    /// The period's mood from AudioMuse; nil when AudioMuse isn't set up or has no scores (#70).
    func moodProfile(for period: WrappedPeriod, serverId: String, calendar: Calendar) async -> WrappedMoodProfile? {
        guard let moodScorer, await moodScorer.isAvailable() else { return nil }
        let loaded = await plays(for: period, serverId: serverId, calendar: calendar)
        let library = loaded.plays.filter { WrappedIDs.isLibraryID($0.trackId) }
        let ids = WrappedAggregator.topTracks(from: library, limit: Self.moodTrackLimit).map(\.trackId)
        let scores: [String: AudioMuseMoodScores]
        do {
            scores = try await moodScorer.scores(for: ids)
        } catch {
            Logger.wrapped.warning("[WRAPPED] mood scores unavailable: \(String(describing: error), privacy: .public)")
            return nil
        }
        let years = WrappedInsightsBuilder.yearSpan(of: loaded.plays.map { WrappedInsightsBuilder.Stamp($0.timestamp, calendar: calendar) })
        let buckets = WrappedInsightsBuilder.buckets(for: period, chart: .timeline, years: years, calendar: calendar)
        return WrappedMoodBuilder.build(plays: loaded.plays, scores: scores, period: period, buckets: buckets, calendar: calendar)
    }

    /// The song behind each story slide (#75), and the songs themselves for their lengths.
    nonisolated struct StorySoundtrack: Sendable {
        let trackIDs: [WrappedStorySlideKind: String]
        let songs: [String: DisplayableSong]

        static let empty = StorySoundtrack(trackIDs: [:], songs: [:])
    }

    func storySoundtrack(for data: WrappedData, serverId: String, calendar: Calendar) async -> StorySoundtrack {
        let plays = await plays(for: data.period, serverId: serverId, calendar: calendar).plays
        let picks = Self.soundtrack(plays: plays, data: data)
        let ids = Array(Set(picks.values))
        let indexed = await songsByID(ids)
        let songs = Dictionary(indexed.map { ($0.id, DisplayableSong(from: $0)) }, uniquingKeysWith: { first, _ in first })
        return StorySoundtrack(trackIDs: picks.filter { songs[$0.value] != nil }, songs: songs)
    }

    /// Library tracks only, as only those can play: the #1 song on Top Track, the top artist's and
    /// album's most played songs on theirs, the dominant genre's on Top Genre, the next top songs on
    /// the other slides, and the #1 again to close.
    nonisolated static func soundtrack(plays: [WrappedPlay], data: WrappedData) -> [WrappedStorySlideKind: String] {
        let library = plays.filter { WrappedIDs.isLibraryID($0.trackId) }
        let ranked = WrappedAggregator.topTracks(from: library, limit: .max).map(\.trackId)
        guard let first = ranked.first else { return [:] }
        func top(where include: (WrappedPlay) -> Bool) -> String? {
            WrappedAggregator.topTracks(from: library.filter(include), limit: 1).first?.trackId
        }
        var picks: [WrappedStorySlideKind: String] = [.topTrack: first, .closing: first]
        if let artist = data.topArtists.first?.artistId { picks[.topArtist] = top { $0.artistId == artist } }
        if let album = data.topAlbums.first?.albumId { picks[.topAlbum] = top { $0.albumId == album } }
        if let genre = data.dominantGenre { picks[.topGenre] = top { $0.genre == genre } }
        let used = Set(picks.values)
        var spare = ranked.filter { !used.contains($0) }.makeIterator()
        for kind in [WrappedStorySlideKind.intro, .minutes, .discoveries] {
            picks[kind] = spare.next() ?? first
        }
        return picks
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
        let plays = await plays(for: period, serverId: serverId, calendar: calendar).plays
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

    /// The period's plays from ListenBrainz when an account is set, else from this phone.
    func plays(for period: WrappedPeriod, serverId: String, calendar: Calendar, refresh: Bool = false,
               progress: ListenHistoryStore.Progress? = nil) async -> Plays {
        let user = await username()
        let key = "\(serverId)|\(user ?? "-")|\(period)|\(calendar.timeZone.identifier)"
        let date = now()
        playsCache.removeAll { date.timeIntervalSince($0.storedAt) > Self.playsCacheLifetime }
        if !refresh, let hit = playsCache.first(where: { $0.key == key }) { return hit.plays }

        let range = await range(for: period, user: user, calendar: calendar)
        let loaded: Plays
        if let user, let plays = await listenBrainzPlays(user: user, range: range, serverId: serverId, calendar: calendar,
                                                         refresh: refresh, progress: progress) {
            loaded = Plays(plays: plays, range: range, source: .listenBrainz, fellBack: false)
        } else {
            let plays = await stats.plays(for: period, serverId: serverId, calendar: calendar)
            loaded = Plays(plays: plays, range: range, source: .device, fellBack: user != nil)
        }
        // A fallback is retried next time rather than kept.
        if !loaded.fellBack {
            playsCache.removeAll { $0.key == key }
            playsCache.insert(CachedPlays(key: key, plays: loaded, storedAt: date), at: 0)
            playsCache = Array(playsCache.prefix(Self.playsCacheSize))
        }
        return loaded
    }

    /// All Time starts at the first ListenBrainz listen rather than the period's open-ended start, so
    /// the history isn't walked through decades before it began.
    private func range(for period: WrappedPeriod, user: String?, calendar: Calendar) async -> (start: Date, end: Date) {
        let range = period.dateRange(in: calendar)
        guard case .allTime = period, let user,
              let year = try? await history.firstYear(user: user, calendar: calendar),
              let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) else { return range }
        return (start, range.end)
    }

    private func listenBrainzPlays(user: String, range: (start: Date, end: Date), serverId: String, calendar: Calendar,
                                   refresh: Bool, progress: ListenHistoryStore.Progress?) async -> [WrappedPlay]? {
        do {
            let listens = try await history.listens(user: user, from: range.start, to: range.end,
                                                    calendar: calendar, refresh: refresh, progress: progress)
            let matcher = await libraryMatcher(serverId: serverId)
            return matcher.plays(for: listens)
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
