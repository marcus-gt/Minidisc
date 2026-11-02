import Foundation
import SwiftSonic
import Synchronization
import Testing
@testable import Minidisc

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
}
