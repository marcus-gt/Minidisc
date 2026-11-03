import Foundation
import SwiftSonic
import Synchronization
import Testing
@testable import Maekster

/// Answers `/api/servers` and `/api/find_path`, and records the path request's query.
private nonisolated final class PathStubProtocol: URLProtocol, @unchecked Sendable {
    private struct State: Sendable {
        var pathStatus = 200
        var pathBody = "{}"
        var lastQuery: [String: String] = [:]
    }
    private static let state = Mutex(State())

    static func stub(status: Int = 200, body: String) {
        state.withLock { $0.pathStatus = status; $0.pathBody = body; $0.lastQuery = [:] }
    }
    static var lastQuery: [String: String] { state.withLock { $0.lastQuery } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        var status = 200
        var body = #"{"servers":[{"server_id":"nav","name":"Navidrome"}],"default_id":"nav"}"#
        if url.path == "/api/find_path" {
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            Self.state.withLock { state in
                state.lastQuery = Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { _, last in last })
                status = state.pathStatus
                body = state.pathBody
            }
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!,
                            cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private func song(_ id: String, _ title: String) -> DisplayableSong {
    DisplayableSong(from: Song(id: id, title: title, artist: "Artist", duration: 200, albumId: "al-\(id)"))
}

@Suite("Song Path (#65)", .serialized)
struct SongPathTests {
    private func client() -> AudioMuseClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PathStubProtocol.self]
        return AudioMuseClient(urlString: "https://audiomuse.test", token: "t", session: URLSession(configuration: config))!
    }

    private func service(indexed: [String] = []) -> SongPathService {
        let client = client()
        return SongPathService(makeClient: { client }, resolver: nil, songsByID: { ids in
            ids.filter(indexed.contains).map { Song(id: $0, title: "Indexed \($0)", artist: "Artist", duration: 200, albumId: "al") }
        })
    }

    private func pathBody(_ ids: [String]) -> String {
        let items = ids.map { #"{"item_id":"\#($0)","title":"T \#($0)","author":"A","album":"B","embedding_vector":[0.1]}"# }
        return #"{"path":[\#(items.joined(separator: ","))],"total_distance":0.5}"#
    }

    @Test func request_asksForAFixedLengthPathOnTheServer() async throws {
        PathStubProtocol.stub(body: pathBody(["a", "b"]))
        _ = try await client().findPath(from: .song(id: "a"), to: .mood("relaxed"), length: 20)
        let query = PathStubProtocol.lastQuery
        #expect(query["start_song_id"] == "a")
        #expect(query["end_mood"] == "relaxed")
        #expect(query["max_steps"] == "20")
        #expect(query["path_fix_size"] == "true")
        #expect(query["server"] == "nav")
    }

    /// The queue keeps the path's order without repeats; indexed songs bring their metadata.
    @Test func path_keepsOrderDropsRepeatsAndUsesTheIndex() async throws {
        PathStubProtocol.stub(body: pathBody(["a", "b", "b", "c"]))
        let songs = try await service(indexed: ["b"]).path(from: .song(song("a", "Start")), to: .song(song("c", "End")), length: 4)
        #expect(songs.map(\.id) == ["a", "b", "c"])
        #expect(songs[1].title == "Indexed b")
        // Not in the index: AudioMuse's names, playable from the ID.
        #expect(songs[0].title == "T a")
    }

    @Test func noPath_isReported() async {
        PathStubProtocol.stub(status: 404, body: #"{"error":"No path found"}"#)
        await #expect(throws: SongPathService.PathError.noPath) {
            try await service().path(from: .song(song("a", "A")), to: .song(song("b", "B")), length: 10)
        }
    }

    @Test func ends_needASongOnAtLeastOneSideAndTwoDifferentSongs() {
        let a = SongPathService.End.song(song("a", "A"))
        #expect(SongPathService.canBuild(from: a, to: .mood(.relaxed)))
        #expect(SongPathService.canBuild(from: .mood(.happy), to: a))
        #expect(!SongPathService.canBuild(from: .mood(.happy), to: .mood(.sad)))
        #expect(!SongPathService.canBuild(from: a, to: a))
        #expect(!SongPathService.canBuild(from: a, to: nil))
        #expect(!SongPathService.moods.contains(.party))
    }

    @Test func source_namesBothEnds() {
        #expect(QueueSource.songPath(from: "Peace Piece", to: "Relaxed").title == "Song Path · Peace Piece → Relaxed")
    }

    /// Home gets Song Path hidden, also in a layout saved before it existed; Discover shows it.
    @Test func layouts_hideSongPathOnHomeOnly() {
        #expect(!HomeLayoutConfiguration.default.isVisible(.songPath))
        let saved = #"{"order":["recentlyPlayed","pinned"],"hidden":[]}"#
        let restored = HomeLayoutConfiguration(rawValue: saved)
        #expect(restored?.isVisible(.songPath) == false)
        #expect(restored?.isVisible(.recentlyPlayed) == true)
        #expect(DiscoverLayoutConfiguration.default.isVisible(.songPath))
    }

    private nonisolated static func play(_ id: String) -> PlaybackEventDTO {
        PlaybackEventDTO(trackId: id, trackTitle: "Played \(id)", albumId: nil, albumTitle: nil, artistId: nil,
                         artistName: "Artist", genre: nil, timestamp: .now, durationListened: 200, trackDuration: 200,
                         wasCompleted: true, serverId: "s")
    }

    private nonisolated static func top(_ ids: [String]) -> [TopTrackEntry] {
        ids.enumerated().map { TopTrackEntry(rank: $0.offset + 1, trackId: $0.element, title: "Top \($0.element)",
                                             artistName: "Artist", albumTitle: nil, totalSecondsListened: 600, playCount: 3) }
    }

    /// Recent plays without repeats or local files, the month's top songs and favourites; indexed
    /// songs bring their details.
    @Test func suggestions_recentTopAndFavorites() async {
        let monthTop = Self.top(["t1", "t2", "t3", "t4", "t5"])
        let service = SongPathService(makeClient: { nil }, resolver: nil, songsByID: { ids in
            ids.filter { $0 == "a" }.map { Song(id: $0, title: "Indexed a", artist: "Artist", coverArt: "cover-a") }
        }, sources: .init(
            recentPlays: { ["a", "b", "a", "local:ff", "c"].map(Self.play) },
            topTracks: { period in if case .month = period { monthTop } else { [] } },
            favorites: { [Song(id: "f1", title: "Fav")] }
        ))
        let suggestions = await service.suggestions()
        #expect(suggestions.recent.map(\.id) == ["a", "b", "c"])
        #expect(suggestions.recent[0].title == "Indexed a")
        #expect(suggestions.recent[1].title == "Played b")
        #expect(suggestions.top.map(\.id) == ["t1", "t2", "t3", "t4", "t5"])
        #expect(suggestions.favorites.map(\.id) == ["f1"])
    }

    /// Early in a month the year's top songs stand in; a failing list comes back empty.
    @Test func suggestions_thinMonthUsesTheYear() async {
        struct Failure: Error {}
        let service = SongPathService(makeClient: { nil }, resolver: nil, songsByID: { _ in [] }, sources: .init(
            topTracks: { period in if case .year = period { Self.top(["y1", "y2"]) } else { Self.top(["m1"]) } },
            favorites: { throw Failure() }
        ))
        let suggestions = await service.suggestions()
        #expect(suggestions.top.map(\.id) == ["y1", "y2"])
        #expect(suggestions.favorites.isEmpty)
    }

    @Test func surprise_avoidsTheOtherEnd() async throws {
        let service = SongPathService(makeClient: { nil }, resolver: nil, songsByID: { _ in [] }, sources: .init(
            randomSongs: { _ in [Song(id: "a", title: "A"), Song(id: "b", title: "B")] }
        ))
        #expect(try await service.surpriseSong(avoiding: "a")?.id == "b")
        #expect(try await service.surpriseSong(avoiding: nil)?.id == "a")
    }
}
