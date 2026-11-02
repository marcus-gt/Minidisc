import Foundation
import SwiftSonic
import Testing
@testable import Minidisc

@Suite("Artists for You (#63)")
struct ArtistShelfTests {
    private nonisolated static let now = Date(timeIntervalSince1970: 1_800_000_000)
    private nonisolated static let day: TimeInterval = 24 * 60 * 60

    private nonisolated static func album(_ id: String, artist: String, plays: Int, daysAgo: Double) -> AlbumID3 {
        AlbumID3(id: id, name: id, songCount: 10, duration: 0, artist: artist, artistId: artist,
                 playCount: plays, played: now.addingTimeInterval(-daysAgo * day))
    }

    private nonisolated static func artist(_ id: String, name: String? = nil) -> ArtistID3 {
        ArtistID3(id: id, name: name ?? "Artist \(id)", albumCount: 1)
    }

    /// 20 played lately (fav*), 10 played a lot but not for 200 days (old*), 30 never played (new*).
    private nonisolated static let library = (0..<20).map { artist("fav\($0)") } + (0..<10).map { artist("old\($0)") }
        + (0..<30).map { artist("new\($0)") }
    private static let mostPlayed = (0..<20).map { album("a-fav\($0)", artist: "fav\($0)", plays: 100 - $0, daysAgo: 2) }
        + (0..<10).map { album("a-old\($0)", artist: "old\($0)", plays: 50 - $0, daysAgo: 200) }
    private static let recent = (0..<20).map { album("a-fav\($0)", artist: "fav\($0)", plays: 100 - $0, daysAgo: 2) }

    private func pick(seed: String = "s|2026-11-02") -> [ArtistID3] {
        ArtistShelfPicker.pick(mostPlayed: Self.mostPlayed, recentlyPlayed: Self.recent, library: Self.library,
                               now: Self.now, seed: seed)
    }

    @Test func pick_blendsFavoritesDormantAndNew() {
        let ids = pick().map(\.id)
        #expect(ids.count == 12)
        #expect(Set(ids).count == 12)
        #expect(ids.filter { $0.hasPrefix("fav") }.count == 6)
        #expect(ids.filter { $0.hasPrefix("old") }.count == 4)
        #expect(ids.filter { $0.hasPrefix("new") }.count == 2)
    }

    @Test func pick_staysForADayAndChangesTheNext() {
        #expect(pick().map(\.id) == pick().map(\.id))
        #expect(pick().map(\.id) != pick(seed: "s|2026-11-03").map(\.id))
    }

    @Test func pick_leavesOutVariousArtistsAndUnknown() {
        let library = [Self.artist("va", name: "Various Artists"), Self.artist("u", name: "[Unknown Artist]"), Self.artist("x")]
        let ids = ArtistShelfPicker.pick(mostPlayed: [], recentlyPlayed: [], library: library, now: Self.now, seed: "s").map(\.id)
        #expect(ids == ["x"])
    }

    /// A new listener with no history still gets a full shelf, from the library.
    @Test func pick_withoutHistory_fillsFromTheLibrary() {
        let ids = ArtistShelfPicker.pick(mostPlayed: [], recentlyPlayed: [], library: Self.library, now: Self.now, seed: "s").map(\.id)
        #expect(ids.count == 12)
    }

    /// An album in both lists counts once.
    @Test func listening_countsEachAlbumOnce() {
        let album = Self.album("a", artist: "x", plays: 5, daysAgo: 1)
        #expect(ArtistShelfPicker.listening(from: [album, album])["x"]?.plays == 5)
    }

    /// A server with only two months of plays still has dormant artists: half its history.
    @Test func dormancy_adaptsToAShortHistory() {
        func listening(_ daysAgo: Double) -> [String: ArtistShelfPicker.Listening] {
            ["x": .init(plays: 3, lastPlayed: Self.now.addingTimeInterval(-daysAgo * Self.day))]
        }
        #expect(ArtistShelfPicker.dormancy(listening: listening(60), now: Self.now) == 30 * Self.day)
        #expect(ArtistShelfPicker.dormancy(listening: listening(400), now: Self.now) == 90 * Self.day)
        #expect(ArtistShelfPicker.dormancy(listening: listening(10), now: Self.now) == 14 * Self.day)
    }

    /// One load per server and day; the history failing still leaves the library's artists.
    @Test func service_cachesTheDaysPick() async throws {
        struct Failure: Error {}
        let loads = LoadCounter()
        let service = ArtistShelfService(sources: .init(
            mostPlayedAlbums: { throw Failure() },
            recentlyPlayedAlbums: { [] },
            libraryArtists: { await loads.increment(); return Self.library }
        ))
        let server = UUID()
        let first = try await service.artists(serverID: server, now: Self.now)
        let again = try await service.artists(serverID: server, now: Self.now.addingTimeInterval(60))
        #expect(first.count == 12)
        #expect(first.map(\.id) == again.map(\.id))
        #expect(await loads.count == 1)
        _ = try await service.artists(serverID: server, now: Self.now.addingTimeInterval(Self.day))
        #expect(await loads.count == 2)
    }
}

private actor LoadCounter {
    private(set) var count = 0
    func increment() { count += 1 }
}
