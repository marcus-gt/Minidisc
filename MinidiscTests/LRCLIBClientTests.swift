import Foundation
import Testing
@testable import Minidisc

actor LRCLIBTransportRecorder: LRCLIBTransport {
    private let payload: Data
    private let response: URLResponse
    private let responseDelay: Duration?
    private(set) var requests: [URLRequest] = []
    private(set) var maximumConcurrentRequestCount = 0
    private var activeRequestCount = 0

    init(payload: Data, response: URLResponse, responseDelay: Duration? = nil) {
        self.payload = payload
        self.response = response
        self.responseDelay = responseDelay
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        activeRequestCount += 1
        maximumConcurrentRequestCount = max(maximumConcurrentRequestCount, activeRequestCount)
        defer { activeRequestCount -= 1 }
        if let responseDelay {
            try await Task.sleep(for: responseDelay)
        }
        return (payload, response)
    }
}

/// Answers with a scripted sequence of (status, body) pairs, so a busy server can be followed by success.
actor LRCLIBScriptedTransport: LRCLIBTransport {
    private let steps: [(Int, String)]
    private(set) var requestCount = 0

    init(_ steps: [(Int, String)]) {
        self.steps = steps
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let step = steps[min(requestCount, steps.count - 1)]
        requestCount += 1
        let url = try #require(request.url)
        let response = try #require(HTTPURLResponse(url: url, statusCode: step.0, httpVersion: nil, headerFields: nil))
        return (Data(step.1.utf8), response)
    }
}

@Suite("LRCLIBClient")
struct LRCLIBClientTests {
    private static let record = """
    {"id": 42, "trackName": "Run Boy Run", "artistName": "Woodkid", "albumName": "The Golden Age",
     "duration": 213.42, "instrumental": false, "plainLyrics": "Run boy run", "syncedLyrics": "[00:01.25]Run boy run"}
    """

    private func signature() -> LRCLIBTrackSignature {
        LRCLIBTrackSignature(title: "Run Boy Run", artist: "Woodkid", album: "The Golden Age", duration: 213.42)
    }

    /// LRCLIB's 503 "ServerOverloaded" is common and brief; it must not cost the track its timed lyrics.
    @Test func busyServerIsRetried() async throws {
        let endpoint = try #require(URL(string: "https://lrclib.net/api/get"))
        let busy = #"{"message":"The server is busy, please retry in a moment","name":"ServerOverloaded","statusCode":503}"#
        let transport = LRCLIBScriptedTransport([(503, busy), (200, Self.record)])
        let client = LRCLIBClient(transport: transport, endpoint: endpoint, retryDelay: .zero)

        let result = try await client.lyrics(for: signature())
        #expect(result.id == 42)
        #expect(await transport.requestCount == 2)
    }

    @Test func busyServerGivesUpAfterTheLastAttempt() async throws {
        let endpoint = try #require(URL(string: "https://lrclib.net/api/get"))
        let transport = LRCLIBScriptedTransport([(503, "")])
        let client = LRCLIBClient(transport: transport, endpoint: endpoint, retryDelay: .zero)

        await #expect(throws: (any Error).self) { try await client.lyrics(for: signature()) }
        #expect(await transport.requestCount == LRCLIBClient.maximumAttempts)
    }

    @Test func notFoundIsNotRetried() async throws {
        let endpoint = try #require(URL(string: "https://lrclib.net/api/get"))
        let transport = LRCLIBScriptedTransport([(404, "")])
        let client = LRCLIBClient(transport: transport, endpoint: endpoint, retryDelay: .zero)

        await #expect(throws: LyricsError.notFound) { try await client.lyrics(for: signature()) }
        #expect(await transport.requestCount == 1)
    }

    @Test func exactRequestIncludesRecommendedMetadataAndClientIdentity() async throws {
        let endpoint = try #require(URL(string: "https://lrclib.net/api/get"))
        let response = try #require(HTTPURLResponse(
            url: endpoint,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        ))
        let payload = Data("""
        {
          "id": 42,
          "trackName": "Run Boy Run",
          "artistName": "Woodkid",
          "albumName": "The Golden Age",
          "duration": 213.42,
          "instrumental": false,
          "plainLyrics": "Run boy run",
          "syncedLyrics": "[00:01.25]Run boy run"
        }
        """.utf8)
        let transport = LRCLIBTransportRecorder(payload: payload, response: response)
        let client = LRCLIBClient(
            transport: transport,
            endpoint: endpoint,
            clientIdentifier: "MinidiscTests/1.0"
        )

        let record = try await client.lyrics(for: LRCLIBTrackSignature(
            title: "Run Boy Run",
            artist: "Woodkid",
            album: "The Golden Age",
            duration: 213.42
        ))

        #expect(record.id == 42)
        let requests = await transport.requests
        let request = try #require(requests.first)
        let requestURL = try #require(request.url)
        let components = try #require(URLComponents(url: requestURL, resolvingAgainstBaseURL: false))
        var query: [String: String] = [:]
        for item in components.queryItems ?? [] {
            query[item.name] = item.value
        }
        #expect(query["track_name"] == "Run Boy Run")
        #expect(query["artist_name"] == "Woodkid")
        #expect(query["album_name"] == "The Golden Age")
        #expect(query["duration"] == "213.420")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "MinidiscTests/1.0")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
    }

    @Test func notFoundResponseMapsToLyricsError() async throws {
        let endpoint = try #require(URL(string: "https://lrclib.net/api/get"))
        let response = try #require(HTTPURLResponse(
            url: endpoint,
            statusCode: 404,
            httpVersion: nil,
            headerFields: nil
        ))
        let transport = LRCLIBTransportRecorder(payload: Data(), response: response)
        let client = LRCLIBClient(transport: transport, endpoint: endpoint)

        await #expect(throws: LyricsError.notFound) {
            try await client.lyrics(for: LRCLIBTrackSignature(
                title: "Missing",
                artist: "Artist",
                album: nil,
                duration: nil
            ))
        }
    }

    @Test func retryAfterPreventsImmediateSecondRequest() async throws {
        let endpoint = try #require(URL(string: "https://lrclib.net/api/get"))
        let response = try #require(HTTPURLResponse(
            url: endpoint,
            statusCode: 429,
            httpVersion: nil,
            headerFields: ["Retry-After": "120"]
        ))
        let transport = LRCLIBTransportRecorder(payload: Data(), response: response)
        let now = Date(timeIntervalSince1970: 1_000)
        let client = LRCLIBClient(
            transport: transport,
            endpoint: endpoint,
            now: { now }
        )
        let signature = LRCLIBTrackSignature(
            title: "Rate limited",
            artist: "Artist",
            album: nil,
            duration: nil
        )

        await #expect(throws: LyricsError.self) {
            try await client.lyrics(for: signature)
        }
        await #expect(throws: LyricsError.self) {
            try await client.lyrics(for: signature)
        }
        let requests = await transport.requests
        #expect(requests.count == 1)
    }

    @Test func concurrentCallersAreSerialized() async throws {
        let endpoint = try #require(URL(string: "https://lrclib.net/api/get"))
        let response = try #require(HTTPURLResponse(
            url: endpoint,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        ))
        let payload = Data("""
        {
          "id": 1,
          "trackName": "Song",
          "artistName": "Artist",
          "albumName": "Album",
          "duration": 180,
          "instrumental": false,
          "plainLyrics": "Lyrics",
          "syncedLyrics": null
        }
        """.utf8)
        let transport = LRCLIBTransportRecorder(
            payload: payload,
            response: response,
            responseDelay: .milliseconds(30)
        )
        let client = LRCLIBClient(transport: transport, endpoint: endpoint)
        let firstSignature = LRCLIBTrackSignature(
            title: "First",
            artist: "Artist",
            album: "Album",
            duration: 180
        )
        let secondSignature = LRCLIBTrackSignature(
            title: "Second",
            artist: "Artist",
            album: "Album",
            duration: 180
        )

        async let first = client.lyrics(for: firstSignature)
        async let second = client.lyrics(for: secondSignature)
        _ = try await (first, second)

        #expect(await transport.maximumConcurrentRequestCount == 1)
    }
}
