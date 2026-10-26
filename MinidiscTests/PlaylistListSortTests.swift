import Foundation
import SwiftSonic
import Testing
@testable import Minidisc

@Suite("Playlists list sort")
struct PlaylistListSortTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func playlist(_ id: String, _ name: String, created: TimeInterval? = nil, changed: TimeInterval? = nil) -> Playlist {
        Playlist(
            id: id, name: name, songCount: 1, duration: 60,
            created: created.map { now.addingTimeInterval($0) },
            changed: changed.map { now.addingTimeInterval($0) }
        )
    }

    @Test func lastUsed_localUseBeatsServerChanges() {
        let playlists = [
            playlist("a", "Road trip", changed: -60),
            playlist("b", "Focus", changed: -3_600)
        ]
        let sorted = PlaylistListSort.lastUsed.sorted(playlists, lastUsed: ["b": now])
        #expect(sorted.map(\.id) == ["b", "a"])
    }

    @Test func lastUsed_fallsBackToServerChangedDate() {
        let playlists = [
            playlist("old", "Old", changed: -86_400),
            playlist("new", "New", changed: -60)
        ]
        #expect(PlaylistListSort.lastUsed.sorted(playlists, lastUsed: [:]).map(\.id) == ["new", "old"])
    }

    @Test func lastUsed_generatedPlaylistsDontRiseOnTheirSyncDate() {
        let playlists = [
            playlist("mood", Mood.night.playlistName, changed: -1),
            playlist("legacy-mood", Mood.focus.legacyPlaylistName, changed: -2),
            playlist("wrapped", WrappedPlaylistService.playlistName(year: 2026), changed: -3),
            playlist("mine", "Mine", changed: -86_400)
        ]
        let sorted = PlaylistListSort.lastUsed.sorted(playlists, lastUsed: [:])
        #expect(sorted.first?.id == "mine")
    }

    @Test func lastUsed_generatedPlaylistCountsWhenPlayedHere() {
        let playlists = [
            playlist("mood", Mood.night.playlistName, changed: -1),
            playlist("mine", "Mine", changed: -60)
        ]
        let sorted = PlaylistListSort.lastUsed.sorted(playlists, lastUsed: ["mood": now])
        #expect(sorted.map(\.id) == ["mood", "mine"])
    }

    @Test func lastUsed_noDatesSortByNameLast() {
        let playlists = [
            playlist("z", "Zebra"),
            playlist("a", "alpha"),
            playlist("dated", "Dated", changed: -60)
        ]
        #expect(PlaylistListSort.lastUsed.sorted(playlists, lastUsed: [:]).map(\.id) == ["dated", "a", "z"])
    }

    @Test func recentlyCreated_newestFirst() {
        let playlists = [
            playlist("older", "Older", created: -86_400),
            playlist("newer", "Newer", created: -60),
            playlist("unknown", "Unknown")
        ]
        #expect(PlaylistListSort.recentlyCreated.sorted(playlists, lastUsed: [:]).map(\.id) == ["newer", "older", "unknown"])
    }

    @Test func name_isCaseInsensitive() {
        let playlists = [playlist("b", "beta"), playlist("a", "Alpha"), playlist("c", "Gamma")]
        #expect(PlaylistListSort.name.sorted(playlists, lastUsed: [:]).map(\.id) == ["a", "b", "c"])
    }
}

@Suite("Playlist usage store")
struct PlaylistUsageStoreTests {
    private func makeStore() -> (PlaylistUsageStore, UserDefaults, String) {
        let suite = "playlist-usage.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (PlaylistUsageStore(defaults: defaults), defaults, suite)
    }

    @Test func recordUse_isKeptPerServer() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let date = Date(timeIntervalSinceReferenceDate: 1_000)
        store.recordUse(playlistID: "p1", serverID: "server-a", at: date)

        #expect(store.lastUsed(serverID: "server-a") == ["p1": date])
        #expect(store.lastUsed(serverID: "server-b").isEmpty)
    }

    @Test func recordUse_overwritesWithTheLatestDate() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        store.recordUse(playlistID: "p1", serverID: "s", at: Date(timeIntervalSinceReferenceDate: 1_000))
        store.recordUse(playlistID: "p1", serverID: "s", at: Date(timeIntervalSinceReferenceDate: 2_000))

        #expect(store.lastUsed(serverID: "s")["p1"] == Date(timeIntervalSinceReferenceDate: 2_000))
    }

    @Test func recordUse_ignoresEmptyIDs() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        store.recordUse(playlistID: "", serverID: "s")
        store.recordUse(playlistID: "p1", serverID: "")

        #expect(store.lastUsed(serverID: "s").isEmpty)
        #expect(store.lastUsed(serverID: "").isEmpty)
    }

    @Test func recordUse_dropsTheOldestBeyondTheLimit() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        for index in 0...PlaylistUsageStore.maxEntries {
            store.recordUse(playlistID: "p\(index)", serverID: "s", at: Date(timeIntervalSinceReferenceDate: Double(index)))
        }
        let entries = store.lastUsed(serverID: "s")

        #expect(entries.count == PlaylistUsageStore.maxEntries)
        #expect(entries["p0"] == nil)
        #expect(entries["p\(PlaylistUsageStore.maxEntries)"] != nil)
    }
}
