import Foundation
import SwiftData
import SwiftSonic
import Testing
@testable import Minidisc

private actor CancellationBlockingPlaylistClient: PlaylistSyncClient {
    private let livePlaylist = Playlist(
        id: "pl-existing",
        name: "maekster Wrapped 2026",
        songCount: 0,
        duration: 0
    )
    private var didStartWrite = false
    private var writeWaiters: [CheckedContinuation<Void, Never>] = []

    func getPlaylists(username: String?) async throws -> [Playlist] {
        _ = username
        return [livePlaylist]
    }

    func createPlaylist(
        name: String?,
        playlistId: String?,
        songIds: [String]
    ) async throws -> PlaylistWithSongs {
        _ = name
        _ = playlistId
        _ = songIds
        didStartWrite = true
        let waiters = writeWaiters
        writeWaiters.removeAll()
        waiters.forEach { $0.resume() }
        try await Task.sleep(for: .seconds(60))
        return PlaylistWithSongs(
            id: "pl-existing",
            name: "maekster Wrapped 2026",
            songCount: songIds.count,
            duration: 0
        )
    }

    func renamePlaylist(id: String, to name: String) async throws {
        _ = id
        _ = name
    }

    func waitUntilWriteStarted() async {
        if didStartWrite { return }
        await withCheckedContinuation { writeWaiters.append($0) }
    }
}

private actor CancellationBlockingMoodProvider: MoodTrackProvider {
    nonisolated let kind: MoodSourceKind = .sonic

    private var didStartSearch = false
    private var searchWaiters: [CheckedContinuation<Void, Never>] = []

    func prepare() async {}

    func trackIds(for mood: Mood, limit: Int) async throws -> [String] {
        _ = mood
        _ = limit
        didStartSearch = true
        let waiters = searchWaiters
        searchWaiters.removeAll()
        waiters.forEach { $0.resume() }
        try await Task.sleep(for: .seconds(60))
        return ["track-after-cancellation"]
    }

    func waitUntilSearchStarted() async {
        if didStartSearch { return }
        await withCheckedContinuation { searchWaiters.append($0) }
    }
}

private actor RecordingPlaylistClient: MoodPlaylistClient {
    private var writeCount = 0

    func getPlaylists(username: String?) async throws -> [Playlist] {
        _ = username
        return []
    }

    func createPlaylist(
        name: String?,
        playlistId: String?,
        songIds: [String]
    ) async throws -> PlaylistWithSongs {
        writeCount += 1
        return PlaylistWithSongs(
            id: playlistId ?? "created",
            name: name ?? "",
            songCount: songIds.count,
            duration: 0
        )
    }

    func deletePlaylist(id: String) async throws {}

    func renamePlaylist(id: String, to name: String) async throws {
        _ = id
        _ = name
    }

    func writes() -> Int {
        writeCount
    }
}

private func cancellationCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

private func cancellationDate() -> Date {
    ISO8601DateFormatter().date(from: "2026-05-04T12:00:00Z")!
}

@Suite("Playlist sync cancellation")
struct PlaylistSyncCancellationTests {
    @Test("Mood propagates cancellation without attempt, source, or cycle markers")
    func moodCancellationDoesNotCommitMarkers() async {
        let provider = CancellationBlockingMoodProvider()
        let playlists = RecordingPlaylistClient()
        let preferences = MoodPreferences(
            userDefaults: UserDefaults(suiteName: "mood.cancel.\(UUID().uuidString)")!
        )
        let service = MoodPlaylistService(
            playlistClientFactory: { playlists },
            providerFactory: { provider },
            preferences: preferences
        )
        let calendar = cancellationCalendar()
        let now = cancellationDate()

        let sync = Task {
            do {
                _ = try await service.runWeeklySyncIfNeededCancellable(
                    serverId: "srv",
                    calendar: calendar,
                    currentDate: now
                )
                return false
            } catch is CancellationError {
                return true
            } catch {
                return false
            }
        }

        await provider.waitUntilSearchStarted()
        sync.cancel()
        let propagatedCancellation = await sync.value
        let writes = await playlists.writes()

        #expect(propagatedCancellation)
        #expect(writes == 0)
        #expect(preferences.lastAttempt(serverId: "srv") == nil)
        #expect(preferences.lastSource(serverId: "srv") == nil)
        for mood in Mood.allCases {
            #expect(preferences.syncedCycle(mood: mood, serverId: "srv") == nil)
        }
    }
}
