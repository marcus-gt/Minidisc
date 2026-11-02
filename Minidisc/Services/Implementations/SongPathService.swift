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

    private let makeClient: @Sendable () async -> AudioMuseClient?
    private let resolver: SubsonicTrackResolver?
    private let songsByID: @Sendable ([String]) async -> [Song]

    init(makeClient: @escaping @Sendable () async -> AudioMuseClient?,
         resolver: SubsonicTrackResolver?,
         songsByID: @escaping @Sendable ([String]) async -> [Song]) {
        self.makeClient = makeClient
        self.resolver = resolver
        self.songsByID = songsByID
    }

    init(serverService: any ServerServiceProtocol, serverState: ServerState,
         libraryService: any LibrarySearching, catalog: LibraryCatalog) {
        self.init(
            makeClient: {
                guard let urlString = await MainActor.run(body: { serverState.activeServer?.audioMuseURL }),
                      !urlString.trimmingCharacters(in: .whitespaces).isEmpty,
                      let credentials = try? await serverService.activeConnection().credentials else { return nil }
                return AudioMuseClient(urlString: urlString, token: credentials.audioMuseToken)
            },
            resolver: SubsonicTrackResolver(libraryService: libraryService),
            songsByID: { (try? await catalog.indexedSongs(ids: $0)) ?? [] }
        )
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
