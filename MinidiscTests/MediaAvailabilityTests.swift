import Foundation
import SwiftData
import SwiftSonic
import Testing
@testable import Minidisc

@Suite("Media availability")
@MainActor
struct MediaAvailabilityTests {
    private func serverError(code: Int) async throws -> any Error {
        let client = SwiftSonicClient(
            configuration: ServerConfiguration(
                serverURL: URL(string: "https://example.invalid")!, username: "test", password: "test"
            ),
            transport: StubHTTPTransport(outcome: .response(data: Data("""
                {"subsonic-response":{"status":"failed","version":"1.16.1","error":{"code":\(code),"message":"test"}}}
                """.utf8), statusCode: 200)),
            retryPolicy: .none
        )
        do {
            _ = try await client.getSong(id: "deleted")
            throw MinidiscError.notImplemented
        } catch { return error }
    }

    @Test func structuredMissingSongResponseIsRecognized() async throws {
        let error = try await serverError(code: 70)
        #expect(MediaResolver.availability(after: error) == .missing)
    }

    @Test(arguments: [0, 40, 50])
    func otherServerErrorsDoNotImplyDeletion(code: Int) async throws {
        let error = try await serverError(code: code)
        #expect(MediaResolver.availability(after: error) == .unknown)
    }

    @Test func networkHTTPAndCancellationFailuresDoNotImplyDeletion() {
        let errors: [any Error] = [
            URLError(.timedOut), CancellationError(),
            SwiftSonicError.httpError(statusCode: 404, endpoint: "getSong", serverHost: nil),
            SwiftSonicError.httpError(statusCode: 403, endpoint: "getSong", serverHost: nil),
            SwiftSonicError.httpError(statusCode: 500, endpoint: "getSong", serverHost: nil)
        ]
        for error in errors {
            #expect(MediaResolver.availability(after: error) == .unknown)
        }
    }

    @Test func cachedSongRemainsAvailableAfterServerDeletionEvenOffline() async throws {
        let container = try ModelContainer.minidisc(inMemory: true)
        let server = MockServerService()
        server.state.isOnline = false
        let cache = MockAudioStreamCache()
        cache.localURL = URL(fileURLWithPath: "/cached-song.m4a")
        let resolver = MediaResolver(
            downloadService: DownloadService(serverService: server, modelContainer: container, toastService: ToastService()),
            audioStreamCache: cache, serverService: server, serverState: server.state,
            streamSettings: StreamSettings(defaults: UserDefaults(suiteName: "media-availability.\(UUID())")!),
            songLookup: { _, _ in Issue.record("Local playback must not query the server") }
        )
        let serverID = UUID()
        #expect(await resolver.availability(songId: "deleted", serverId: serverID) == .available)
        let source = try await resolver.resolve(songId: "deleted", serverId: serverID)
        #expect(source.url == cache.localURL)
    }

    @Test func authoritativeLookupUsesTheRequestedServer() async throws {
        let container = try ModelContainer.minidisc(inMemory: true)
        let server = MockServerService()
        let snapshot = ServerSnapshot(from: ServerConfig(displayName: "Test", baseURL: "https://example.invalid", username: "test"))
        server.connection = try ServerConnection(
            version: .init(serverID: snapshot.id, revision: 1), server: snapshot,
            credentials: .init(password: "test", customHeaders: [:])
        )
        let error = try await serverError(code: 70)
        let resolver = MediaResolver(
            downloadService: DownloadService(serverService: server, modelContainer: container, toastService: ToastService()),
            audioStreamCache: MockAudioStreamCache(), serverService: server, serverState: server.state,
            streamSettings: StreamSettings(defaults: UserDefaults(suiteName: "media-availability.\(UUID())")!),
            songLookup: { _, _ in throw error }
        )
        #expect(await resolver.availability(songId: "deleted", serverId: snapshot.id) == .missing)
        #expect(await resolver.availability(songId: "deleted", serverId: UUID()) == .unknown)
    }

    // MARK: - Empty song ids (#7)

    private func onlineResolver(songLookup: @escaping @Sendable (ServerConnection, String) async throws -> Void) throws -> (MediaResolver, UUID) {
        let container = try ModelContainer.minidisc(inMemory: true)
        let server = MockServerService()
        let snapshot = ServerSnapshot(from: ServerConfig(displayName: "Test", baseURL: "https://example.invalid", username: "test"))
        server.connection = try ServerConnection(
            version: .init(serverID: snapshot.id, revision: 1), server: snapshot,
            credentials: .init(password: "test", customHeaders: [:])
        )
        let resolver = MediaResolver(
            downloadService: DownloadService(serverService: server, modelContainer: container, toastService: ToastService()),
            audioStreamCache: MockAudioStreamCache(), serverService: server, serverState: server.state,
            streamSettings: StreamSettings(defaults: UserDefaults(suiteName: "media-availability.\(UUID())")!),
            songLookup: songLookup
        )
        return (resolver, snapshot.id)
    }

    @Test func isValidSongID_rejectsEmptyAndBlankIDs() {
        #expect(MediaResolver.isValidSongID("song-1"))
        #expect(!MediaResolver.isValidSongID(""))
        #expect(!MediaResolver.isValidSongID("   "))
        #expect(!MediaResolver.isValidSongID("\n\t"))
    }

    @Test(arguments: ["", "  ", "\n"])
    func availability_emptyID_neverQueriesTheServer(songId: String) async throws {
        let (resolver, serverID) = try onlineResolver { _, _ in Issue.record("An empty id must not reach getSong") }
        #expect(await resolver.availability(songId: songId, serverId: serverID) == .unknown)
    }

    @Test(arguments: ["", "  "])
    func resolve_emptyID_throwsInsteadOfBuildingAStreamURL(songId: String) async throws {
        let (resolver, serverID) = try onlineResolver { _, _ in }
        await #expect {
            _ = try await resolver.resolve(songId: songId, serverId: serverID)
        } throws: { error in
            guard case .mediaNotFound = error as? MinidiscError else { return false }
            return true
        }
    }

    @Test func resolve_validID_stillStreams() async throws {
        let (resolver, serverID) = try onlineResolver { _, _ in }
        let source = try await resolver.resolve(songId: "song-1", serverId: serverID)
        guard case .stream(let url, _) = source else {
            Issue.record("Expected a stream source, got \(source)")
            return
        }
        #expect(url.absoluteString.contains("id=song-1"))
    }
}
