import Foundation
import SwiftSonic
import Testing
@testable import Minidisc

private actor HomeFeedSource: PlaylistBrowsing, RecentlyAddedAlbumBrowsing, ListeningHistoryBrowsing, GenreBrowsing {
    private let failHistory: Bool
    private let waitForGenres: Bool
    private let mainGenres: [String: [AlbumID3]]?
    private var genreWaiter: CheckedContinuation<Void, Never>?
    private(set) var calls = 0
    private(set) var serverGenreCalls = 0
    var waiting: Bool { genreWaiter != nil }

    init(failHistory: Bool = false, waitForGenres: Bool = false, mainGenres: [String: [AlbumID3]]? = nil) {
        self.failHistory = failHistory
        self.waitForGenres = waitForGenres
        self.mainGenres = mainGenres
    }
    func albumsByMainGenre() async throws -> [String: [AlbumID3]]? { mainGenres }
    func playlists() async throws -> [Playlist] {
        calls += 1
        return [Playlist(id: "p", name: "Saved", songCount: 1, duration: 100)]
    }
    func playlist(id: String) async throws -> PlaylistWithSongs { throw URLError(.unsupportedURL) }
    func recentlyAddedAlbums(size: Int, offset: Int) async throws -> [AlbumID3] {
        calls += 1
        return [try JSONDecoder().decode(AlbumID3.self, from: Data(#"{"id":"a","name":"Album","songCount":1,"duration":100}"#.utf8))]
    }
    func recentlyPlayedAlbums(size: Int) async throws -> [AlbumID3] {
        calls += 1
        if failHistory { throw URLError(.timedOut) }
        return []
    }
    func mostPlayedAlbums(size: Int) async throws -> [AlbumID3] { [] }
    func genres() async throws -> [Genre] {
        calls += 1
        serverGenreCalls += 1
        if waitForGenres { await withCheckedContinuation { genreWaiter = $0 } }
        return []
    }
    func albumsByGenre(_ genre: String, size: Int) async throws -> [AlbumID3] { [] }
    func release() { genreWaiter?.resume(); genreWaiter = nil }
}

@Suite @MainActor
struct HomeFeedContinuityTests {
    @Test func aSlowGenreDoesNotBlockAlbumsAndAHistoryFailureKeepsOtherSections() async throws {
        let source = HomeFeedSource(failHistory: true, waitForGenres: true)
        let model = HomeFeedViewModel(libraryService: source)
        let load = Task { await model.load() }
        // A ceiling, not a timing assumption: the loop ends as soon as the state is reached (#11).
        let deadline = ContinuousClock.now + .seconds(30)
        while (!(await source.waiting) || model.recentlyAdded.isEmpty), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.recentlyAdded.map(\.id) == ["a"])
        #expect(model.isLoading)
        await source.release()
        await load.value
        #expect(model.topPicks.map(\.id) == ["p"])
        #expect(model.hasPartialFailure)
        #expect(!model.isEmpty)
    }

    @Test func genreShelves_useMainGenresFromTheIndexWhenAvailable() async throws {
        func album(_ id: String) throws -> AlbumID3 {
            try JSONDecoder().decode(AlbumID3.self, from: Data(#"{"id":"\#(id)","name":"\#(id)","songCount":1,"duration":100}"#.utf8))
        }
        let source = HomeFeedSource(mainGenres: [
            "Dubstep": [try album("trap")],
            "Jazz": [try album("j1"), try album("j2")]
        ])
        let model = HomeFeedViewModel(libraryService: source)
        await model.load()

        #expect(model.genreShelves.map(\.name) == ["Jazz", "Dubstep"])
        #expect(Set(model.genreShelves[0].albums.map(\.id)) == ["j1", "j2"])
        #expect(await source.serverGenreCalls == 0)
    }

    @Test func homeSurvivesRelaunchOfflineAndIsScopedToItsServer() async throws {
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = HomeFeedSource()
        let serverID = UUID()
        let cache = HomeFeedCache(directory: directory)
        let online = HomeFeedViewModel(libraryService: source, cache: cache, serverID: serverID)
        await online.load()
        let calls = await source.calls
        let offline = HomeFeedViewModel(libraryService: source, cache: HomeFeedCache(directory: directory), serverID: serverID)
        await offline.load(isOnline: false)
        #expect(offline.topPicks.map(\.id) == ["p"])
        #expect(offline.recentlyAdded.map(\.id) == ["a"])
        #expect(await source.calls == calls)
        #expect(await cache.load(serverID: UUID()) == nil)
    }

    @Test func cappedPlaylists_keepsPinnedPlaylistsPastTheLimit() {
        let playlists = (0..<5).map { Playlist(id: "p\($0)", name: "P\($0)", songCount: 1, duration: 100) }
        let capped = HomePersonalization.cappedPlaylists(playlists, limit: 2, keeping: ["p4"])
        #expect(capped.map(\.id) == ["p0", "p1", "p4"])
    }

    @Test func shelfPlaylists_pinnedOnly_showsPinnedInPinOrder() {
        let playlists = (0..<3).map { Playlist(id: "p\($0)", name: "P\($0)", songCount: 1, duration: 100) }
        let all = HomePersonalization.shelfPlaylists(playlists, pinnedIDs: ["p2", "gone", "p0"], pinnedOnly: false)
        let pinned = HomePersonalization.shelfPlaylists(playlists, pinnedIDs: ["p2", "gone", "p0"], pinnedOnly: true)
        #expect(all.map(\.id) == ["p0", "p1", "p2"])
        #expect(pinned.map(\.id) == ["p2", "p0"])
    }

    @Test func cancellingALoadPreservesVisibleContent() async throws {
        let source = HomeFeedSource(waitForGenres: true)
        let model = HomeFeedViewModel(libraryService: source)
        let load = Task { await model.load() }
        let deadline = ContinuousClock.now + .seconds(30)
        while (!(await source.waiting) || model.recentlyAdded.isEmpty), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        load.cancel()
        await source.release()
        await load.value
        #expect(model.recentlyAdded.map(\.id) == ["a"])
        #expect(!model.isLoading)
        #expect(model.error == nil)
    }
}
