import Foundation
import SwiftData
import SwiftSonic
import Testing
@testable import Minidisc

@MainActor
private final class DownloadedFileStub: DownloadServiceProtocol {
    var albumData: LocalAlbumData?
    var fileURL: URL?

    let progressStream: AsyncStream<[DownloadProgress]> = AsyncStream { $0.finish() }
    func localAlbumData(albumId: String, serverId: UUID) async -> LocalAlbumData? { albumData }
    func downloadedURL(forSongId songId: String, serverId: UUID) async -> URL? { fileURL }
    func isDownloaded(songId: String, serverId: UUID) async -> Bool { fileURL != nil }
    func downloadedSongIds(serverId: UUID) async -> Set<String> { [] }
    func localCoverArtURL(forId coverArtId: String) async -> URL? { nil }
    func persistCover(_ data: Data, forId coverArtId: String) async {}
    func removeCover(forId coverArtId: String) async {}
    func garbageCollectOrphanedCovers(referencedIds: Set<String>) async -> Int { 0 }
    func coverCacheStats() async -> (count: Int, bytes: Int64) { (0, 0) }
    func clearAllCovers() async {}
    func localPlaylistData(playlistId: String, serverId: UUID) async -> LocalPlaylistData? { nil }
    func localArtistData(artistId: String, artistName: String?, serverId: UUID) async -> LocalArtistData? { nil }
    func backfillPlaylistSongIds(playlistId: String, serverId: UUID, orderedSongIds: [String]) async {}
    func download(song: Song, serverId: UUID) async throws { throw URLError(.unknown) }
    func download(album: AlbumID3, serverId: UUID) async throws { throw URLError(.unknown) }
    func download(playlist: PlaylistWithSongs, serverId: UUID) async throws { throw URLError(.unknown) }
    func isDownloading(songId: String, serverId: UUID) async -> Bool { false }
    func isDownloadingAlbum(_ albumId: String) async -> Bool { false }
    func isDownloadingPlaylist(_ playlistId: String) async -> Bool { false }
    func cancelDownload(songId: String, serverId: UUID) async {}
    func remove(songId: String, serverId: UUID) async throws { throw URLError(.unknown) }
    func remove(albumId: String, serverId: UUID) async throws { throw URLError(.unknown) }
    func remove(playlistId: String, serverId: UUID) async throws { throw URLError(.unknown) }
    func removeAll() async throws { throw URLError(.unknown) }
}

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

    // MARK: - Streaming instead of a download

    private func downloadResolver(online: Bool, cellular: Bool, wifiStream: Bool, cellularStream: Bool,
                                  cached: Bool = false) throws -> (MediaResolver, UUID, URL) {
        let server = MockServerService()
        let snapshot = ServerSnapshot(from: ServerConfig(displayName: "Test", baseURL: "https://example.invalid", username: "test"))
        server.connection = try ServerConnection(
            version: .init(serverID: snapshot.id, revision: 1), server: snapshot,
            credentials: .init(password: "test", customHeaders: [:])
        )
        server.state.isOnline = online
        let downloads = DownloadedFileStub()
        let file = URL(fileURLWithPath: "/downloads/song.flac")
        downloads.fileURL = file
        let cache = MockAudioStreamCache()
        if cached { cache.localURL = URL(fileURLWithPath: "/cache/song.flac") }
        let settings = StreamSettings(defaults: UserDefaults(suiteName: "media-stream-instead.\(UUID())")!)
        settings.streamsOverDownloadsOnWifi = wifiStream
        settings.streamsOverDownloadsOnCellular = cellularStream
        settings.networkPathDidChange(isCellular: cellular)
        let resolver = MediaResolver(downloadService: downloads, audioStreamCache: cache, serverService: server,
                                     serverState: server.state, streamSettings: settings, songLookup: { _, _ in })
        return (resolver, snapshot.id, file)
    }

    @Test func downloadIsPlayedWhenStreamingInsteadIsOff() async throws {
        let (resolver, serverID, file) = try downloadResolver(online: true, cellular: false, wifiStream: false, cellularStream: false)
        let source = try await resolver.resolve(songId: "song", serverId: serverID)
        #expect(source.url == file)
    }

    @Test func downloadIsPassedOverForAStreamOnWifi() async throws {
        let (resolver, serverID, _) = try downloadResolver(online: true, cellular: false, wifiStream: true, cellularStream: false)
        guard case .stream = try await resolver.resolve(songId: "song", serverId: serverID) else {
            Issue.record("Expected a stream"); return
        }
    }

    /// Each network has its own switch.
    @Test func wifiSettingDoesNotApplyOnCellular() async throws {
        let (resolver, serverID, file) = try downloadResolver(online: true, cellular: true, wifiStream: true, cellularStream: false)
        #expect(try await resolver.resolve(songId: "song", serverId: serverID).url == file)
        let (cellular, cellularID, _) = try downloadResolver(online: true, cellular: true, wifiStream: false, cellularStream: true)
        guard case .stream = try await cellular.resolve(songId: "song", serverId: cellularID) else {
            Issue.record("Expected a stream on cellular"); return
        }
    }

    @Test func downloadStillPlaysOffline() async throws {
        let (resolver, serverID, file) = try downloadResolver(online: false, cellular: false, wifiStream: true, cellularStream: true)
        #expect(try await resolver.resolve(songId: "song", serverId: serverID).url == file)
    }

    /// The cache holds what was streamed before, so it is used ahead of a new request.
    @Test func cachedCopyIsUsedBeforeStreamingAgain() async throws {
        let (resolver, serverID, _) = try downloadResolver(online: true, cellular: false, wifiStream: true, cellularStream: false, cached: true)
        guard case .cached = try await resolver.resolve(songId: "song", serverId: serverID) else {
            Issue.record("Expected the cached copy"); return
        }
    }

    /// Without a usable connection the download still plays rather than failing.
    @Test func downloadPlaysWhenNoStreamCanBeBuilt() async throws {
        let (resolver, serverID, file) = try downloadResolver(online: true, cellular: false, wifiStream: true, cellularStream: false)
        let broken = MockServerService()
        broken.state.isOnline = true
        let fallback = MediaResolver(downloadService: { let d = DownloadedFileStub(); d.fileURL = file; return d }(),
                                     audioStreamCache: MockAudioStreamCache(), serverService: broken,
                                     serverState: broken.state,
                                     streamSettings: { let s = StreamSettings(defaults: UserDefaults(suiteName: "media-stream-instead.\(UUID())")!); s.streamsOverDownloadsOnWifi = true; return s }(),
                                     songLookup: { _, _ in })
        _ = resolver
        #expect(try await fallback.resolve(songId: "song", serverId: serverID).url == file)
    }
}
