import Foundation
import OSLog
import SwiftSonic

/// A song path (#65): AudioMuse's smooth sequence from one song (or mood) to another, as a queue.
actor SongPathService {
    /// The moods AudioMuse can start or end a path at (no "party": it has no path centroid).
    nonisolated static let moods: [QueueBuilderMood] = [.happy, .sad, .aggressive, .relaxed, .danceable]
    nonisolated static let lengthRange = 5...50
    nonisolated static let defaultLength = 25

    /// One end of a path, as the sheet shows it.
    nonisolated enum End: Sendable, Equatable {
        case song(DisplayableSong)
        case mood(QueueBuilderMood)

        var isMood: Bool { if case .mood = self { true } else { false } }

        /// For "Song Path · Peace Piece → Relaxed".
        var name: String {
            switch self {
            case .song(let song): song.title
            case .mood(let mood): String(localized: mood.title)
            }
        }

        fileprivate var pathEnd: AudioMuseClient.PathEnd {
            switch self {
            case .song(let song): .song(id: song.id)
            case .mood(let mood): .mood(mood.rawValue)
            }
        }
    }

    nonisolated enum PathError: Error, Equatable {
        /// AudioMuse isn't set up for the active server.
        case unavailable
        /// Both ends are moods, or the same song.
        case invalidEnds
        /// AudioMuse found no path, or none of it is in the library.
        case noPath
    }

    /// Where the picker's suggestions come from, before anything is typed.
    nonisolated struct SuggestionSources: Sendable {
        /// Plays on the active server, newest first.
        var recentPlays: @Sendable () async -> [PlaybackEventDTO] = { [] }
        /// Most played on the active server in a period.
        var topTracks: @Sendable (WrappedPeriod) async -> [TopTrackEntry] = { _ in [] }
        var favorites: @Sendable () async throws -> [Song] = { [] }
        var randomSongs: @Sendable (Int) async throws -> [Song] = { _ in [] }
    }

    /// The picker's suggested songs (#65).
    nonisolated struct Suggestions: Sendable, Equatable {
        var recent: [DisplayableSong] = []
        var top: [DisplayableSong] = []
        var favorites: [DisplayableSong] = []

        var isEmpty: Bool { recent.isEmpty && top.isEmpty && favorites.isEmpty }
    }

    nonisolated static let suggestionsPerList = 8
    /// A month with fewer top songs than this falls back to the year.
    nonisolated static let minimumMonthTopSongs = 5

    private let makeClient: @Sendable () async -> AudioMuseClient?
    private let resolver: SubsonicTrackResolver?
    private let songsByID: @Sendable ([String]) async -> [Song]
    private let sources: SuggestionSources

    init(makeClient: @escaping @Sendable () async -> AudioMuseClient?,
         resolver: SubsonicTrackResolver?,
         songsByID: @escaping @Sendable ([String]) async -> [Song],
         sources: SuggestionSources = SuggestionSources()) {
        self.makeClient = makeClient
        self.resolver = resolver
        self.songsByID = songsByID
        self.sources = sources
    }

    init(serverService: any ServerServiceProtocol, serverState: ServerState,
         libraryService: any LibraryServiceProtocol, catalog: LibraryCatalog, statsService: StatsService) {
        let serverID: @Sendable () async -> String? = {
            await MainActor.run { serverState.activeServer?.id.uuidString }
        }
        self.init(
            makeClient: {
                guard let urlString = await MainActor.run(body: { serverState.activeServer?.audioMuseURL }),
                      !urlString.trimmingCharacters(in: .whitespaces).isEmpty,
                      let credentials = try? await serverService.activeConnection().credentials else { return nil }
                return AudioMuseClient(urlString: urlString, token: credentials.audioMuseToken)
            },
            resolver: SubsonicTrackResolver(libraryService: libraryService),
            songsByID: { (try? await catalog.indexedSongs(ids: $0)) ?? [] },
            sources: SuggestionSources(
                recentPlays: {
                    guard let id = await serverID() else { return [] }
                    return await statsService.recentEvents(limit: 100, serverId: id)
                },
                topTracks: { period in
                    guard let id = await serverID() else { return [] }
                    return await statsService.topTracks(forPeriod: period, serverId: id,
                                                        limit: Self.suggestionsPerList, calendar: .current)
                },
                favorites: { try await libraryService.getStarred2().song ?? [] },
                randomSongs: { try await libraryService.randomSongs(size: $0) }
            )
        )
    }

    /// Recently played, top songs (this month, or this year when the month is thin) and favourites,
    /// each without repeats or local files. Lists that fail to load come back empty.
    func suggestions() async -> Suggestions {
        let limit = Self.suggestionsPerList
        async let plays = sources.recentPlays()
        async let monthTop = sources.topTracks(.currentMonth())
        async let starred = (try? sources.favorites()) ?? []

        var seen = Set<String>()
        let recent = await plays.map { (id: $0.trackId, title: $0.trackTitle, artist: $0.artistName, album: $0.albumTitle) }
            .filter { Self.isLibraryID($0.id) && seen.insert($0.id).inserted }
            .prefix(limit)
        var top = await monthTop
        if top.count < Self.minimumMonthTopSongs {
            top = await sources.topTracks(.currentYear())
        }
        let topEntries = top.filter { Self.isLibraryID($0.trackId) }.prefix(limit)
        let favorites = await starred.filter { !($0.isDir ?? false) }.shuffled().prefix(limit)

        let ids = recent.map(\.id) + topEntries.map(\.trackId)
        let indexed = Dictionary(await songsByID(ids).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        func song(_ id: String, title: String, artist: String, album: String?) -> DisplayableSong {
            indexed[id].map { DisplayableSong(from: $0) }
                ?? DisplayableSong(from: Song(id: id, title: title, album: album, artist: artist, coverArt: id))
        }
        return Suggestions(
            recent: recent.map { song($0.id, title: $0.title, artist: $0.artist, album: $0.album) },
            top: topEntries.map { song($0.trackId, title: $0.title, artist: $0.artistName, album: $0.albumTitle) },
            favorites: favorites.map { DisplayableSong(from: $0) }
        )
    }

    /// A random library song, for "Surprise Me"; never `avoiding` (the other end).
    func surpriseSong(avoiding id: String?) async throws -> DisplayableSong? {
        let songs = try await sources.randomSongs(5)
        return songs.first { !($0.isDir ?? false) && $0.id != id }.map { DisplayableSong(from: $0) }
    }

    private nonisolated static func isLibraryID(_ id: String) -> Bool {
        !id.isEmpty && !id.hasPrefix("local:")
    }

    /// Valid ends: at most one mood, and not the same song twice.
    nonisolated static func canBuild(from start: End?, to end: End?) -> Bool {
        guard let start, let end else { return false }
        if start.isMood && end.isMood { return false }
        if case .song(let a) = start, case .song(let b) = end, a.id == b.id { return false }
        return true
    }

    func path(from start: End, to end: End, length: Int) async throws -> [DisplayableSong] {
        guard Self.canBuild(from: start, to: end) else { throw PathError.invalidEnds }
        guard let client = await makeClient() else { throw PathError.unavailable }
        let tracks: [AudioMuseTrack]
        do {
            tracks = try await client.findPath(from: start.pathEnd, to: end.pathEnd, length: length)
        } catch AudioMuseError.notFound {
            throw PathError.noPath
        }
        try Task.checkCancellation()

        // Library IDs keep their place; AudioMuse's internal fp_ IDs are looked up by name.
        var ids: [String] = []
        for track in tracks {
            if !track.hasInternalId {
                ids.append(track.itemId)
            } else if let resolver, let descriptor = track.descriptor, let id = await resolver.resolve(descriptor) {
                ids.append(id)
            }
        }
        let indexed = Dictionary(await songsByID(ids).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let byTrack = Dictionary(tracks.map { ($0.itemId, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        let songs = ids.filter { seen.insert($0).inserted }.map { id in
            indexed[id].map { DisplayableSong(from: $0) } ?? Self.basicSong(id: id, track: byTrack[id])
        }
        Logger.moodPlaylists.info("[SONG-PATH] \(tracks.count, privacy: .public) steps → \(songs.count, privacy: .public) playable")
        guard !songs.isEmpty else { throw PathError.noPath }
        return songs
    }

    /// A song the index doesn't know yet plays from its ID; AudioMuse supplies the names.
    private nonisolated static func basicSong(id: String, track: AudioMuseTrack?) -> DisplayableSong {
        DisplayableSong(
            id: id, title: track?.title ?? "", artist: track?.author, albumId: nil, albumName: track?.album,
            artistId: nil, genre: nil, duration: 0, trackNumber: nil, isDownloaded: false, coverArtId: id,
            audioFormat: nil, replayGainTrackGain: nil, replayGainTrackPeak: nil, replayGainAlbumGain: nil,
            replayGainAlbumPeak: nil, replayGainBaseGain: nil, replayGainFallbackGain: nil
        )
    }
}
