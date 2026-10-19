import Testing
import Foundation
import Synchronization
@testable import Minidisc

private nonisolated final class StubProtocol: URLProtocol, @unchecked Sendable {
    private struct StubbedResponse: Sendable {
        let status: Int
        let body: String
    }

    private struct State: Sendable {
        var responses: [String: StubbedResponse] = [:]
        var bodies: [String: Data] = [:]
    }

    private static let state = Mutex(State())

    static func reset() {
        state.withLock { $0 = State() }
    }

    static func stub(_ path: String, status: Int = 200, body: String) {
        state.withLock { $0.responses[path] = StubbedResponse(status: status, body: body) }
    }

    static func requestBody(for path: String) -> Data? {
        state.withLock { $0.bodies[path] }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url?.path ?? ""
        // URLProtocol strips httpBody into httpBodyStream, so it has to be read back out.
        if let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
            stream.close()
            Self.state.withLock { $0.bodies[path] = data }
        }
        let stub = Self.state.withLock { $0.responses[path] }
            ?? StubbedResponse(status: 404, body: "{}")
        let response = HTTPURLResponse(url: request.url!, statusCode: stub.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(stub.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private func makeClient(token: String? = nil) -> AudioMuseClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubProtocol.self]
    return AudioMuseClient(urlString: "http://muse.local:8000", token: token, session: URLSession(configuration: config))!
}

@Suite("AudioMuse client", .serialized)
struct AudioMuseClientTests {

    @Test("a normal search returns the media server's track ids")
    func searchReturnsProviderIds() async throws {
        StubProtocol.reset()
        StubProtocol.stub("/api/servers", body: #"{"servers":[{"server_id":"nav1","name":"Navidrome"}],"default_id":"nav1"}"#)
        StubProtocol.stub("/api/clap/search", body: #"{"results":[{"item_id":"G90Au1giwNr8o1HXhxiXpM","title":"T"}]}"#)

        let tracks = try await makeClient().search(query: "calm", limit: 5)

        #expect(tracks.map(\.itemId) == ["G90Au1giwNr8o1HXhxiXpM"])
    }

    @Test("the search is scoped to the default server")
    func searchScopesToDefaultServer() async throws {
        StubProtocol.reset()
        StubProtocol.stub("/api/servers", body: #"{"servers":[{"server_id":"nav1","name":"Navidrome"}],"default_id":"nav1"}"#)
        StubProtocol.stub("/api/clap/search", body: #"{"results":[{"item_id":"abc","title":"T"}]}"#)

        _ = try await makeClient().search(query: "calm", limit: 5)

        let body = try #require(StubProtocol.requestBody(for: "/api/clap/search"))
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["server"] as? String == "nav1")
    }

    @Test("internal ids are returned with their metadata, not dropped")
    func internalIdsKeepTheirMetadata() async throws {
        // The client must NOT filter them: title and artist are what lets the provider find the
        // track in the library. Dropping them here would throw away a recoverable result.
        StubProtocol.reset()
        StubProtocol.stub("/api/servers", body: #"{"servers":[],"default_id":null}"#)
        StubProtocol.stub("/api/clap/search", body: #"{"results":[{"item_id":"fp_20571691a2d5","title":"Tenere","author":"Tinariwen"}]}"#)

        let tracks = try await makeClient().search(query: "calm", limit: 5)

        #expect(tracks.count == 1)
        #expect(tracks[0].hasInternalId)
        #expect(tracks[0].descriptor == TrackDescriptor(title: "Tenere", artist: "Tinariwen"))
    }

    @Test("a usable id is recognised as such")
    func usableIdIsNotFlaggedInternal() async throws {
        StubProtocol.reset()
        StubProtocol.stub("/api/servers", body: #"{"servers":[],"default_id":null}"#)
        StubProtocol.stub("/api/clap/search", body: #"{"results":[{"item_id":"G90Au1giwNr8o1HXhxiXpM"}]}"#)

        let tracks = try await makeClient().search(query: "calm", limit: 5)

        #expect(tracks[0].hasInternalId == false)
    }

    @Test("an empty result is not mistaken for an internal-id failure")
    func emptyResultIsNotAnIdFailure() async throws {
        StubProtocol.reset()
        StubProtocol.stub("/api/servers", body: #"{"servers":[],"default_id":null}"#)
        StubProtocol.stub("/api/clap/search", body: #"{"results":[]}"#)

        #expect(try await makeClient().search(query: "calm", limit: 5).isEmpty)
    }

    @Test("HTTP status codes map to distinguishable errors")
    func statusCodesMap() async {
        let cases: [(Int, AudioMuseError)] = [
            (503, .notAnalysed),
            (401, .unauthorized),
            (403, .unauthorized),
            (400, .searchDisabled("CLAP text search is disabled.")),
        ]
        for (status, expected) in cases {
            StubProtocol.reset()
            StubProtocol.stub("/api/servers", body: #"{"servers":[],"default_id":null}"#)
            StubProtocol.stub("/api/clap/search", status: status, body: #"{"error":"CLAP text search is disabled."}"#)

            await #expect(throws: expected, "HTTP \(status)") {
                try await makeClient().search(query: "calm", limit: 5)
            }
        }
    }

    @Test("a token is sent as a bearer header, and omitted when absent")
    func tokenIsOptional() async throws {
        StubProtocol.reset()
        StubProtocol.stub("/api/servers", body: #"{"servers":[],"default_id":null}"#)
        StubProtocol.stub("/api/clap/search", body: #"{"results":[{"item_id":"a"}]}"#)

        _ = try await makeClient(token: nil).search(query: "calm", limit: 5)
        _ = try await makeClient(token: "secret").search(query: "calm", limit: 5)
    }

    // MARK: - Provider policy

    @Test("tracks with unusable ids are recovered by name")
    func internalIdsAreRecoveredByName() async throws {
        StubProtocol.reset()
        StubProtocol.stub("/api/servers", body: #"{"servers":[],"default_id":null}"#)
        StubProtocol.stub("/api/clap/search", body: #"{"results":[{"item_id":"fp_dead","title":"Tenere","author":"Tinariwen"}]}"#)
        let library = TagLibraryStub()
        await library.setSearchResults([try song(id: "realId", title: "Tenere", artist: "Tinariwen")])
        let provider = AudioMuseTrackProvider(client: makeClient(), resolver: SubsonicTrackResolver(libraryService: library))

        #expect(try await provider.trackIds(for: .chill, limit: 5) == ["realId"])
    }

    @Test("a track that cannot be found is dropped, not guessed at")
    func unresolvableTracksAreDropped() async throws {
        StubProtocol.reset()
        StubProtocol.stub("/api/servers", body: #"{"servers":[],"default_id":null}"#)
        StubProtocol.stub("/api/clap/search",
                          body: #"{"results":[{"item_id":"good"},{"item_id":"fp_x","title":"Absent","author":"Nobody"}]}"#)
        let library = TagLibraryStub()
        let provider = AudioMuseTrackProvider(client: makeClient(), resolver: SubsonicTrackResolver(libraryService: library))

        #expect(try await provider.trackIds(for: .chill, limit: 5) == ["good"])
    }

    @Test("nothing recoverable at all raises rather than reporting an empty success")
    func nothingRecoverableRaises() async {
        StubProtocol.reset()
        StubProtocol.stub("/api/servers", body: #"{"servers":[],"default_id":null}"#)
        StubProtocol.stub("/api/clap/search", body: #"{"results":[{"item_id":"fp_a","title":"Absent"},{"item_id":"fp_b","title":"Gone"}]}"#)
        let provider = AudioMuseTrackProvider(client: makeClient(), resolver: SubsonicTrackResolver(libraryService: TagLibraryStub()))

        await #expect(throws: AudioMuseError.internalIdsOnly) {
            try await provider.trackIds(for: .chill, limit: 5)
        }
    }

    @Test("a genuinely empty search stays empty and does not raise")
    func emptySearchDoesNotRaise() async throws {
        StubProtocol.reset()
        StubProtocol.stub("/api/servers", body: #"{"servers":[],"default_id":null}"#)
        StubProtocol.stub("/api/clap/search", body: #"{"results":[]}"#)
        let provider = AudioMuseTrackProvider(client: makeClient(), resolver: SubsonicTrackResolver(libraryService: TagLibraryStub()))

        #expect(try await provider.trackIds(for: .chill, limit: 5).isEmpty)
    }

    @Test("a repeated track is only looked up once")
    func resolutionIsCached() async throws {
        StubProtocol.reset()
        StubProtocol.stub("/api/servers", body: #"{"servers":[],"default_id":null}"#)
        StubProtocol.stub("/api/clap/search",
                          body: #"{"results":[{"item_id":"fp_1","title":"Tenere","author":"Tinariwen"},{"item_id":"fp_2","title":"Tenere","author":"Tinariwen"}]}"#)
        let library = TagLibraryStub()
        await library.setSearchResults([try song(id: "realId", title: "Tenere", artist: "Tinariwen")])
        let provider = AudioMuseTrackProvider(client: makeClient(), resolver: SubsonicTrackResolver(libraryService: library))

        _ = try await provider.trackIds(for: .chill, limit: 5)

        #expect(await library.searches.count == 1, "the same track must not be searched twice")
    }

    @Test("an unreachable host is a transport error, not a crash")
    func badURLIsRejectedAtInit() {
        #expect(AudioMuseClient(urlString: "not a url", token: nil) == nil)
        #expect(AudioMuseClient(urlString: "", token: nil) == nil)
        #expect(AudioMuseClient(urlString: "http://muse.local:8000", token: nil) != nil)
    }
}

// MARK: - Mood scores (Queue Builder)

/// Separate from `StubProtocol`: suites run in parallel, and a shared `reset()` would wipe the other
/// suite's stubs mid-test.
private nonisolated final class MoodStubProtocol: URLProtocol, @unchecked Sendable {
    private struct State: Sendable {
        var status = 200
        var body = "{}"
        var requests = 0
        var queries: [String] = []
    }
    private static let state = Mutex(State())

    static func reset(status: Int = 200, body: String = "{}") {
        state.withLock { $0 = State(status: status, body: body) }
    }
    static var requests: Int { state.withLock { $0.requests } }
    static var queries: [String] { state.withLock { $0.queries } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, body) = Self.state.withLock { state -> (Int, String) in
            state.requests += 1
            state.queries.append(request.url?.query ?? "")
            return (state.status, state.body)
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite("AudioMuse mood scores", .serialized)
@MainActor
struct AudioMuseMoodScoreTests {
    private func server(audioMuseURL: String?) throws -> MockServerService {
        let server = MockServerService()
        let snapshot = ServerSnapshot(from: ServerConfig(
            displayName: "Fixture", baseURL: "https://example.invalid", username: "alice", audioMuseURL: audioMuseURL
        ))
        server.state.activeServer = snapshot
        server.state.activeConnectionVersion = .init(serverID: snapshot.id, revision: 1)
        server.connection = try ServerConnection(
            version: server.state.activeConnectionVersion!, server: snapshot,
            credentials: ServerCredentials(password: "fixture", customHeaders: [:], audioMuseToken: "secret")
        )
        return server
    }

    private func stubbedSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MoodStubProtocol.self]
        return URLSession(configuration: config)
    }

    private func temporaryDirectory() -> URL {
        URL.temporaryDirectory.appendingPathComponent("moods-\(UUID().uuidString)", isDirectory: true)
    }

    @Test func otherFeatures_parseIntoNamedScores() {
        let scores = AudioMuseMoodScores(otherFeatures: "danceable:0.65,aggressive:0.60, happy:0.6,party:x")
        #expect(scores.values == ["danceable": 0.65, "aggressive": 0.60, "happy": 0.6])
    }

    @Test func client_readsScoresFromGetScore() async throws {
        MoodStubProtocol.reset(body: #"{"item_id":"abc","other_features":"happy:0.7,sad:0.2"}"#)
        let client = try #require(AudioMuseClient(urlString: "http://muse.local:8000", token: "secret", session: stubbedSession()))

        let scores = try await client.moodScores(itemId: "abc")

        #expect(scores.values == ["happy": 0.7, "sad": 0.2])
        #expect(MoodStubProtocol.queries.last == "id=abc")
    }

    @Test func client_notAnalysedTrackIsNotFound() async throws {
        MoodStubProtocol.reset(status: 404, body: #"{"error":"Score not found"}"#)
        let client = try #require(AudioMuseClient(urlString: "http://muse.local:8000", token: nil, session: stubbedSession()))
        await #expect(throws: AudioMuseError.notFound) {
            _ = try await client.moodScores(itemId: "abc")
        }
    }

    @Test func scorer_unavailableWithoutAudioMuseURL() async throws {
        let scorer = AudioMuseMoodScorer(serverService: try server(audioMuseURL: nil), cacheDirectory: temporaryDirectory())
        #expect(await scorer.isAvailable() == false)
        let configured = AudioMuseMoodScorer(serverService: try server(audioMuseURL: "http://muse.local:8000"), cacheDirectory: temporaryDirectory())
        #expect(await configured.isAvailable())
    }

    @Test func scorer_fetchesOncePerTrackAndPersistsTheCache() async throws {
        MoodStubProtocol.reset(body: #"{"other_features":"happy:0.8"}"#)
        let server = try server(audioMuseURL: "http://muse.local:8000")
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let scorer = AudioMuseMoodScorer(serverService: server, cacheDirectory: directory, session: stubbedSession())
        let first = try await scorer.scores(for: ["a", "b"])
        _ = try await scorer.scores(for: ["a", "b"])
        #expect(first["a"]?.values["happy"] == 0.8)
        #expect(MoodStubProtocol.requests == 2)

        // A new scorer (next launch) reads the same scores from disk without asking AudioMuse.
        let relaunched = AudioMuseMoodScorer(serverService: server, cacheDirectory: directory, session: stubbedSession())
        let cached = try await relaunched.scores(for: ["a"])
        #expect(cached["a"]?.values["happy"] == 0.8)
        #expect(MoodStubProtocol.requests == 2)
    }

    @Test func scorer_unreachableAudioMuseThrows() async throws {
        MoodStubProtocol.reset(status: 500)
        let scorer = AudioMuseMoodScorer(
            serverService: try server(audioMuseURL: "http://muse.local:8000"),
            cacheDirectory: temporaryDirectory(), session: stubbedSession()
        )
        await #expect(throws: AudioMuseError.self) {
            _ = try await scorer.scores(for: ["a", "b"])
        }
    }

    @Test func ranking_ordersByTheAverageOfPickedMoodsAndDropsUnscored() {
        struct Item: Identifiable { let id: String }
        let items = ["low", "high", "mid", "unscored"].map(Item.init)
        let scores: [String: AudioMuseMoodScores] = [
            "low": .init(values: ["happy": 0.2, "party": 0.3]),
            "high": .init(values: ["happy": 0.9, "party": 0.7]),
            "mid": .init(values: ["happy": 0.6, "party": 0.5]),
        ]
        let ranked = QueueBuilderMood.rank(items, scores: scores, moods: [.happy, .party], keeping: 2)
        #expect(ranked.map(\.id) == ["high", "mid"])
    }
}
