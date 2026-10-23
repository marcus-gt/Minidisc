import Testing
import Foundation
import SwiftData
import SwiftSonic
@testable import Minidisc

// MARK: - Test infrastructure

enum WrappedTestError: Error { case generic }

final actor MockPlaylistSyncClient: PlaylistSyncClient {
    var playlists: [Playlist] = []

    var getPlaylistsError: Error?
    var createPlaylistError: Error?
    var renamePlaylistError: Error?

    private(set) var getPlaylistsCalls: Int = 0
    private(set) var createPlaylistCalls: [(name: String?, playlistId: String?, songIds: [String])] = []
    private(set) var renameCalls: [(id: String, name: String)] = []

    private var createCount = 0

    func getPlaylists(username: String?) async throws -> [Playlist] {
        getPlaylistsCalls += 1
        if let err = getPlaylistsError { throw err }
        return playlists
    }

    func createPlaylist(name: String?, playlistId: String?, songIds: [String]) async throws -> PlaylistWithSongs {
        if let err = createPlaylistError { throw err }
        createPlaylistCalls.append((name: name, playlistId: playlistId, songIds: songIds))
        // Replace mode: preserve the given id. Create mode: generate a new one and, like a real
        // server, make it visible to subsequent getPlaylists calls.
        let returnId: String
        if let pid = playlistId {
            returnId = pid
        } else {
            createCount += 1
            returnId = "pl-created-\(createCount)"
            playlists.append(Playlist(id: returnId, name: name ?? "", songCount: songIds.count, duration: 0))
        }
        return PlaylistWithSongs(id: returnId, name: name ?? "", songCount: songIds.count, duration: 0)
    }

    func renamePlaylist(id: String, to name: String) async throws {
        if let err = renamePlaylistError { throw err }
        renameCalls.append((id: id, name: name))
        playlists = playlists.map {
            $0.id == id ? Playlist(id: $0.id, name: name, songCount: $0.songCount, duration: $0.duration, owner: $0.owner, coverArt: $0.coverArt) : $0
        }
    }
}

// MARK: - File-scope helpers

private var wrappedCal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

private func wDate(year: Int, month: Int, day: Int, hour: Int = 12) -> Date {
    var c = DateComponents()
    c.year = year; c.month = month; c.day = day; c.hour = hour
    c.timeZone = TimeZone(identifier: "UTC")!
    return Calendar(identifier: .gregorian).date(from: c)!
}

private func makeStats() throws -> StatsService {
    let container = try ModelContainer.minidisc(inMemory: true)
    return StatsService(modelContainer: container)
}

private func makePrefs() -> WrappedPreferences {
    WrappedPreferences(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
}

private func makeService(
    mock: MockPlaylistSyncClient,
    stats: StatsService,
    prefs: WrappedPreferences,
    owner: String? = nil
) -> WrappedPlaylistService {
    WrappedPlaylistService(clientFactory: { mock }, statsService: stats, preferences: prefs, owner: owner)
}

private func makeEvent(
    trackId: String,
    timestamp: Date,
    serverId: String = "srv",
    durationListened: TimeInterval = 200
) -> PlaybackEventDTO {
    PlaybackEventDTO(
        trackId: trackId,
        trackTitle: "Track \(trackId)",
        albumId: nil,
        albumTitle: nil,
        artistId: nil,
        artistName: "Artist",
        genre: nil,
        timestamp: timestamp,
        durationListened: durationListened,
        trackDuration: durationListened + 10,
        wasCompleted: true,
        serverId: serverId
    )
}

private let testNow = wDate(year: 2026, month: 5, day: 4)

// MARK: - Suite

@Suite("WrappedPlaylistService Yearly Sync")
struct WrappedPlaylistServiceTests {

    @Test func firstSync_createsPlaylist_thenReplacesSetTotal() async throws {
        let mock = MockPlaylistSyncClient()
        let stats = try makeStats()
        let prefs = makePrefs()
        let service = makeService(mock: mock, stats: stats, prefs: prefs)

        for i in 1...3 {
            await stats.recordPlayback(makeEvent(
                trackId: "track-\(i)",
                timestamp: wDate(year: 2026, month: 3, day: i),
                durationListened: TimeInterval(300 - i * 10)
            ))
        }

        let result = await service.runYearlyPlaylistSyncIfNeeded(
            serverId: "srv", calendar: wrappedCal, currentDate: testNow
        )

        #expect(result == .updated(tracksCount: 3))

        let creates = await mock.createPlaylistCalls
        // 2 calls: first creates the empty playlist, second replaces it
        #expect(creates.count == 2)
        #expect(creates[0].name == "maekster Wrapped 2026")
        #expect(creates[0].playlistId == nil)
        #expect(creates[0].songIds.isEmpty)
        #expect(creates[1].name == nil)
        #expect(creates[1].playlistId == prefs.playlistId(year: 2026, serverId: "srv"))
        #expect(creates[1].songIds.count == 3)

        #expect(prefs.lastUpdatedMonth(serverId: "srv") == YearMonth(year: 2026, month: 5))
        #expect(prefs.lastWrappedYear(serverId: "srv") == 2026)
    }

    @Test func idempotence_sameMonth_returnsUpToDate_noServerCalls() async throws {
        let mock = MockPlaylistSyncClient()
        let stats = try makeStats()
        let prefs = makePrefs()
        let service = makeService(mock: mock, stats: stats, prefs: prefs)

        await stats.recordPlayback(makeEvent(trackId: "t1", timestamp: wDate(year: 2026, month: 3, day: 1)))

        _ = await service.runYearlyPlaylistSyncIfNeeded(
            serverId: "srv", calendar: wrappedCal, currentDate: testNow
        )
        let callsAfterFirst = await mock.createPlaylistCalls.count

        let second = await service.runYearlyPlaylistSyncIfNeeded(
            serverId: "srv", calendar: wrappedCal, currentDate: testNow
        )

        #expect(second == .upToDate)
        let callsAfterSecond = await mock.createPlaylistCalls.count
        #expect(callsAfterSecond == callsAfterFirst)
    }

    @Test func setTotal_secondSync_newMonth_replacesExistingPlaylist() async throws {
        let mock = MockPlaylistSyncClient()
        let stats = try makeStats()
        let prefs = makePrefs()
        let service = makeService(mock: mock, stats: stats, prefs: prefs)

        await stats.recordPlayback(makeEvent(trackId: "jan-t", timestamp: wDate(year: 2026, month: 1, day: 15)))
        _ = await service.runYearlyPlaylistSyncIfNeeded(
            serverId: "srv", calendar: wrappedCal, currentDate: wDate(year: 2026, month: 2, day: 1)
        )

        let cachedId = prefs.playlistId(year: 2026, serverId: "srv")
        #expect(cachedId != nil)

        await stats.recordPlayback(makeEvent(trackId: "apr-t", timestamp: wDate(year: 2026, month: 4, day: 15)))
        _ = await service.runYearlyPlaylistSyncIfNeeded(
            serverId: "srv", calendar: wrappedCal, currentDate: testNow
        )

        let creates = await mock.createPlaylistCalls
        let replaceCalls = creates.filter { $0.playlistId == cachedId }
        #expect(replaceCalls.count == 2)
        #expect(replaceCalls.last!.songIds.count == 2)
        // Each sync validates the cached ID against the server’s playlist list.
        let getCount = await mock.getPlaylistsCalls
        #expect(getCount == 2)
    }

    @Test func noEvents_returnsSkippedNoData_flagSet_noServerCalls() async throws {
        let mock = MockPlaylistSyncClient()
        let stats = try makeStats()
        let prefs = makePrefs()
        let service = makeService(mock: mock, stats: stats, prefs: prefs)

        let result = await service.runYearlyPlaylistSyncIfNeeded(
            serverId: "srv", calendar: wrappedCal, currentDate: testNow
        )

        #expect(result == .skippedNoData)
        let creates = await mock.createPlaylistCalls
        #expect(creates.isEmpty)
        // Month is marked even on skip to avoid re-running until next month
        #expect(prefs.lastUpdatedMonth(serverId: "srv") == YearMonth(year: 2026, month: 5))
    }

    @Test func createPlaylistThrows_serverError_monthNotMarked() async throws {
        let mock = MockPlaylistSyncClient()
        let stats = try makeStats()
        let prefs = makePrefs()
        let service = makeService(mock: mock, stats: stats, prefs: prefs)

        // Pre-cache playlist id so only the replace call is made, isolating the failure
        prefs.setPlaylistId("pl-existing", year: 2026, serverId: "srv")
        await mock.setCreatePlaylistError(WrappedTestError.generic)
        await stats.recordPlayback(makeEvent(trackId: "t1", timestamp: wDate(year: 2026, month: 3, day: 1)))

        let result = await service.runYearlyPlaylistSyncIfNeeded(
            serverId: "srv", calendar: wrappedCal, currentDate: testNow
        )

        guard case .serverError = result else {
            Issue.record("Expected serverError, got \(result)")
            return
        }
        #expect(prefs.lastUpdatedMonth(serverId: "srv") == nil)
    }

    @Test func getPlaylistsThrows_serverError_monthNotMarked() async throws {
        let mock = MockPlaylistSyncClient()
        let stats = try makeStats()
        let prefs = makePrefs()
        let service = makeService(mock: mock, stats: stats, prefs: prefs)

        await mock.setGetPlaylistsError(WrappedTestError.generic)
        await stats.recordPlayback(makeEvent(trackId: "t1", timestamp: wDate(year: 2026, month: 3, day: 1)))

        let result = await service.runYearlyPlaylistSyncIfNeeded(
            serverId: "srv", calendar: wrappedCal, currentDate: testNow
        )

        guard case .serverError = result else {
            Issue.record("Expected serverError, got \(result)")
            return
        }
        #expect(prefs.lastUpdatedMonth(serverId: "srv") == nil)
    }

    @Test func multiServerIsolation() async throws {
        let mock = MockPlaylistSyncClient()
        let stats = try makeStats()
        let prefs = makePrefs()
        let service = makeService(mock: mock, stats: stats, prefs: prefs)

        await stats.recordPlayback(makeEvent(
            trackId: "a-t1", timestamp: wDate(year: 2026, month: 3, day: 1), serverId: "srvA"
        ))

        let resultA = await service.runYearlyPlaylistSyncIfNeeded(
            serverId: "srvA", calendar: wrappedCal, currentDate: testNow
        )
        let resultB = await service.runYearlyPlaylistSyncIfNeeded(
            serverId: "srvB", calendar: wrappedCal, currentDate: testNow
        )

        #expect(resultA == .updated(tracksCount: 1))
        #expect(resultB == .skippedNoData)
        #expect(prefs.playlistId(year: 2026, serverId: "srvA") != nil)
        #expect(prefs.playlistId(year: 2026, serverId: "srvB") == nil)
        #expect(prefs.lastUpdatedMonth(serverId: "srvA") == YearMonth(year: 2026, month: 5))
        #expect(prefs.lastUpdatedMonth(serverId: "srvB") == YearMonth(year: 2026, month: 5))
    }

    @Test func top100Limit_moreThan100Tracks_only100InReplaceCall() async throws {
        let mock = MockPlaylistSyncClient()
        let stats = try makeStats()
        let prefs = makePrefs()
        let service = makeService(mock: mock, stats: stats, prefs: prefs)

        for i in 1...110 {
            await stats.recordPlayback(makeEvent(
                trackId: "t\(i)",
                timestamp: wDate(year: 2026, month: 3, day: 1),
                durationListened: TimeInterval(1000 - i)
            ))
        }

        let result = await service.runYearlyPlaylistSyncIfNeeded(
            serverId: "srv", calendar: wrappedCal, currentDate: testNow
        )

        #expect(result == .updated(tracksCount: 100))

        let creates = await mock.createPlaylistCalls
        let replaceCall = creates.first { $0.playlistId != nil }
        #expect(replaceCall?.songIds.count == 100)
    }

    // MARK: - Recovery when the server playlist was deleted (e.g. server rebuild)

    @Test func staleCachedId_playlistDeletedOnServer_recreatesInsteadOfWritingToDeadId() async throws {
        let mock = MockPlaylistSyncClient()
        let stats = try makeStats()
        let prefs = makePrefs()
        let service = makeService(mock: mock, stats: stats, prefs: prefs)

        prefs.setPlaylistId("pl-from-old-server", year: 2026, serverId: "srv")
        await stats.recordPlayback(makeEvent(trackId: "t1", timestamp: wDate(year: 2026, month: 3, day: 1)))

        let result = await service.runYearlyPlaylistSyncIfNeeded(
            serverId: "srv", calendar: wrappedCal, currentDate: testNow
        )

        #expect(result == .updated(tracksCount: 1))
        let creates = await mock.createPlaylistCalls
        #expect(creates.contains { $0.playlistId == nil })
        #expect(!creates.contains { $0.playlistId == "pl-from-old-server" })
        #expect(prefs.playlistId(year: 2026, serverId: "srv") != "pl-from-old-server")
    }

    @Test func cachedId_stillOnServer_isReused() async throws {
        let mock = MockPlaylistSyncClient()
        await mock.seedPlaylists([Playlist(id: "pl-live", name: "maekster Wrapped 2026", songCount: 0, duration: 0)])
        let stats = try makeStats()
        let prefs = makePrefs()
        let service = makeService(mock: mock, stats: stats, prefs: prefs)

        prefs.setPlaylistId("pl-live", year: 2026, serverId: "srv")
        await stats.recordPlayback(makeEvent(trackId: "t1", timestamp: wDate(year: 2026, month: 3, day: 1)))

        _ = await service.runYearlyPlaylistSyncIfNeeded(
            serverId: "srv", calendar: wrappedCal, currentDate: testNow
        )

        let creates = await mock.createPlaylistCalls
        #expect(creates.allSatisfy { $0.playlistId == "pl-live" })
    }

    @Test func fetchYearlyPlaylists_currentYearPlaylistGone_clearsMarkersSoItRebuilds() async throws {
        let mock = MockPlaylistSyncClient()
        let stats = try makeStats()
        let prefs = makePrefs()
        let service = makeService(mock: mock, stats: stats, prefs: prefs)

        prefs.setLastUpdatedMonth(YearMonth(year: 2026, month: 5), serverId: "srv")
        prefs.setPlaylistId("pl-deleted", year: 2026, serverId: "srv")

        _ = await service.fetchYearlyPlaylists(serverId: "srv", calendar: wrappedCal, currentDate: testNow)

        #expect(prefs.lastUpdatedMonth(serverId: "srv") == nil)
        #expect(prefs.playlistId(year: 2026, serverId: "srv") == nil)
    }

    @Test func fetchYearlyPlaylists_currentYearPlaylistPresent_leavesMarkersIntact() async throws {
        let mock = MockPlaylistSyncClient()
        await mock.seedPlaylists([Playlist(id: "pl-live", name: "maekster Wrapped 2026", songCount: 0, duration: 0)])
        let stats = try makeStats()
        let prefs = makePrefs()
        let service = makeService(mock: mock, stats: stats, prefs: prefs)

        prefs.setLastUpdatedMonth(YearMonth(year: 2026, month: 5), serverId: "srv")
        prefs.setPlaylistId("pl-live", year: 2026, serverId: "srv")

        _ = await service.fetchYearlyPlaylists(serverId: "srv", calendar: wrappedCal, currentDate: testNow)

        #expect(prefs.lastUpdatedMonth(serverId: "srv") == YearMonth(year: 2026, month: 5))
        #expect(prefs.playlistId(year: 2026, serverId: "srv") == "pl-live")
    }
}

// MARK: - Legacy names

@Suite("WrappedPlaylistService legacy Minidisc names")
struct WrappedLegacyPlaylistNameTests {

    @Test func year_parsesCurrentAndLegacyNamesOnly() {
        #expect(WrappedPlaylistService.playlistName(year: 2026) == "maekster Wrapped 2026")
        #expect(WrappedPlaylistService.year(fromPlaylistName: "maekster Wrapped 2026") == 2026)
        #expect(WrappedPlaylistService.year(fromPlaylistName: "Minidisc Wrapped 2024") == 2024)
        #expect(WrappedPlaylistService.year(fromPlaylistName: "Minidisc Wrapped best of") == nil)
        #expect(WrappedPlaylistService.year(fromPlaylistName: "Wrapped 2026") == nil)
    }

    @Test func sync_currentYearLegacyPlaylist_isRenamedAndReused() async throws {
        let mock = MockPlaylistSyncClient()
        await mock.seedPlaylists([Playlist(id: "pl-legacy", name: "Minidisc Wrapped 2026", songCount: 0, duration: 0)])
        let stats = try makeStats()
        let prefs = makePrefs()
        let service = makeService(mock: mock, stats: stats, prefs: prefs)
        await stats.recordPlayback(makeEvent(trackId: "t1", timestamp: wDate(year: 2026, month: 3, day: 1)))

        let result = await service.runYearlyPlaylistSyncIfNeeded(serverId: "srv", calendar: wrappedCal, currentDate: testNow)

        #expect(result == .updated(tracksCount: 1))
        let renames = await mock.renameCalls
        #expect(renames.map(\.id) == ["pl-legacy"])
        #expect(renames.map(\.name) == ["maekster Wrapped 2026"])
        let creates = await mock.createPlaylistCalls
        #expect(creates.allSatisfy { $0.playlistId == "pl-legacy" })
        #expect(await mock.playlists.map(\.name) == ["maekster Wrapped 2026"])
        #expect(prefs.playlistId(year: 2026, serverId: "srv") == "pl-legacy")
    }

    @Test func sync_cachedLegacyPlaylist_isRenamed() async throws {
        let mock = MockPlaylistSyncClient()
        await mock.seedPlaylists([Playlist(id: "pl-legacy", name: "Minidisc Wrapped 2026", songCount: 0, duration: 0)])
        let stats = try makeStats()
        let prefs = makePrefs()
        prefs.setPlaylistId("pl-legacy", year: 2026, serverId: "srv")
        let service = makeService(mock: mock, stats: stats, prefs: prefs)
        await stats.recordPlayback(makeEvent(trackId: "t1", timestamp: wDate(year: 2026, month: 3, day: 1)))

        _ = await service.runYearlyPlaylistSyncIfNeeded(serverId: "srv", calendar: wrappedCal, currentDate: testNow)

        #expect(await mock.renameCalls.map(\.id) == ["pl-legacy"])
        #expect(await mock.createPlaylistCalls.allSatisfy { $0.playlistId == "pl-legacy" })
    }

    @Test func sync_pastYearLegacyPlaylists_areRenamed() async throws {
        let mock = MockPlaylistSyncClient()
        await mock.seedPlaylists([
            Playlist(id: "pl-2024", name: "Minidisc Wrapped 2024", songCount: 100, duration: 0),
            Playlist(id: "pl-2025", name: "Minidisc Wrapped 2025", songCount: 100, duration: 0),
            Playlist(id: "pl-mix", name: "Minidisc · My favourites", songCount: 10, duration: 0)
        ])
        let stats = try makeStats()
        let service = makeService(mock: mock, stats: stats, prefs: makePrefs())
        await stats.recordPlayback(makeEvent(trackId: "t1", timestamp: wDate(year: 2026, month: 3, day: 1)))

        _ = await service.runYearlyPlaylistSyncIfNeeded(serverId: "srv", calendar: wrappedCal, currentDate: testNow)

        let renamed = Dictionary(uniqueKeysWithValues: await mock.renameCalls.map { ($0.id, $0.name) })
        #expect(renamed == ["pl-2024": "maekster Wrapped 2024", "pl-2025": "maekster Wrapped 2025"])
    }

    @Test func sync_pastYearLegacyDuplicateOfCurrentName_isLeftAlone() async throws {
        let mock = MockPlaylistSyncClient()
        await mock.seedPlaylists([
            Playlist(id: "pl-2025-new", name: "maekster Wrapped 2025", songCount: 100, duration: 0),
            Playlist(id: "pl-2025-old", name: "Minidisc Wrapped 2025", songCount: 100, duration: 0)
        ])
        let stats = try makeStats()
        let service = makeService(mock: mock, stats: stats, prefs: makePrefs())
        await stats.recordPlayback(makeEvent(trackId: "t1", timestamp: wDate(year: 2026, month: 3, day: 1)))

        _ = await service.runYearlyPlaylistSyncIfNeeded(serverId: "srv", calendar: wrappedCal, currentDate: testNow)

        #expect(await mock.renameCalls.isEmpty)
    }

    @Test func sync_otherUsersLegacyPlaylists_areNotRenamed() async throws {
        let mock = MockPlaylistSyncClient()
        await mock.seedPlaylists([
            Playlist(id: "pl-theirs", name: "Minidisc Wrapped 2025", songCount: 100, duration: 0, owner: "someone-else"),
            Playlist(id: "pl-mine", name: "Minidisc Wrapped 2024", songCount: 100, duration: 0, owner: "me")
        ])
        let stats = try makeStats()
        let service = makeService(mock: mock, stats: stats, prefs: makePrefs(), owner: "me")
        await stats.recordPlayback(makeEvent(trackId: "t1", timestamp: wDate(year: 2026, month: 3, day: 1)))

        _ = await service.runYearlyPlaylistSyncIfNeeded(serverId: "srv", calendar: wrappedCal, currentDate: testNow)

        #expect(await mock.renameCalls.map(\.id) == ["pl-mine"])
    }

    @Test func sync_renameFails_stillUpdatesWithoutADuplicate() async throws {
        let mock = MockPlaylistSyncClient()
        await mock.seedPlaylists([Playlist(id: "pl-legacy", name: "Minidisc Wrapped 2026", songCount: 0, duration: 0)])
        await mock.setRenamePlaylistError(WrappedTestError.generic)
        let stats = try makeStats()
        let prefs = makePrefs()
        let service = makeService(mock: mock, stats: stats, prefs: prefs)
        await stats.recordPlayback(makeEvent(trackId: "t1", timestamp: wDate(year: 2026, month: 3, day: 1)))

        let result = await service.runYearlyPlaylistSyncIfNeeded(serverId: "srv", calendar: wrappedCal, currentDate: testNow)

        #expect(result == .updated(tracksCount: 1))
        #expect(await mock.createPlaylistCalls.allSatisfy { $0.playlistId == "pl-legacy" })
        #expect(prefs.playlistId(year: 2026, serverId: "srv") == "pl-legacy")
    }

    @Test func fetchYearlyPlaylists_includesLegacyAndPrefersCurrentPerYear() async throws {
        let mock = MockPlaylistSyncClient()
        await mock.seedPlaylists([
            Playlist(id: "pl-2024", name: "Minidisc Wrapped 2024", songCount: 100, duration: 0),
            Playlist(id: "pl-2025-new", name: "maekster Wrapped 2025", songCount: 100, duration: 0),
            Playlist(id: "pl-2025-old", name: "Minidisc Wrapped 2025", songCount: 100, duration: 0),
            Playlist(id: "pl-other", name: "Road trip", songCount: 10, duration: 0)
        ])
        let service = makeService(mock: mock, stats: try makeStats(), prefs: makePrefs())

        let yearly = await service.fetchYearlyPlaylists(serverId: "srv", calendar: wrappedCal, currentDate: testNow)

        #expect(yearly.map(\.year) == [2025, 2024])
        #expect(yearly.map(\.id) == ["pl-2025-new", "pl-2024"])
        #expect(await mock.renameCalls.isEmpty)
    }
}

// MARK: - MockPlaylistSyncClient mutation helpers

extension MockPlaylistSyncClient {
    func setGetPlaylistsError(_ error: Error?) { getPlaylistsError = error }
    func setCreatePlaylistError(_ error: Error?) { createPlaylistError = error }
    func setRenamePlaylistError(_ error: Error?) { renamePlaylistError = error }
    func seedPlaylists(_ list: [Playlist]) { playlists = list }
}
