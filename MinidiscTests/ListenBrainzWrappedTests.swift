import Foundation
import SwiftData
import SwiftSonic
import Testing
@testable import Minidisc

/// Serves a fixed listen history newest first, the way `/listens?max_ts=` pages it, and counts requests.
nonisolated private final class FakeListenHistory: @unchecked Sendable {
    private let lock = NSLock()
    private var listens: [LBListen]
    private(set) var requests = 0
    var rateLimitOnce = false
    let pageSize: Int

    init(_ listens: [LBListen], pageSize: Int = 2) {
        self.listens = listens.sorted { $0.listenedAt > $1.listenedAt }
        self.pageSize = pageSize
    }

    func add(_ listen: LBListen) {
        lock.withLock { listens = (listens + [listen]).sorted { $0.listenedAt > $1.listenedAt } }
    }

    func page(maxTs: Int) throws -> [LBListen] {
        try lock.withLock {
            requests += 1
            if rateLimitOnce { rateLimitOnce = false; throw ListenBrainzError.rateLimited(retryAfter: 0) }
            return Array(listens.filter { $0.listenedAt < maxTs }.prefix(pageSize))
        }
    }

    var requestCount: Int { lock.withLock { requests } }
}

nonisolated private func listen(_ ts: Date, _ title: String, artist: String = "Bill Evans", mbid: String? = nil) -> LBListen {
    LBListen(listenedAt: Int(ts.timeIntervalSince1970), trackName: title, artistName: artist,
             releaseName: "Sunday at the Village Vanguard", durationMs: 300_000, recordingMBID: mbid)
}

nonisolated private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

nonisolated private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
    utc.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
}

@Suite("ListenBrainz Wrapped (#16)")
@MainActor struct ListenBrainzWrappedTests {
    private func store(_ fake: FakeListenHistory, now: Date) -> ListenHistoryStore {
        ListenHistoryStore(
            directory: URL.temporaryDirectory.appendingPathComponent("lb-history-\(UUID())"),
            fetchPage: { _, maxTs in try fake.page(maxTs: maxTs) },
            fetchOldest: { _ in nil },
            now: { now },
            sleep: { _ in }
        )
    }

    // MARK: History store

    /// A month that has ended is fetched once; asking again reads the cache.
    @Test func pastMonth_isFetchedOnce() async throws {
        let fake = FakeListenHistory([listen(date(2026, 3, 2), "A"), listen(date(2026, 3, 20), "B"), listen(date(2026, 2, 27), "Older")])
        let history = store(fake, now: date(2026, 10, 29))
        let first = try await history.listens(user: "u", from: date(2026, 3, 1), to: date(2026, 4, 1), calendar: utc)
        let afterFirst = fake.requestCount
        let second = try await history.listens(user: "u", from: date(2026, 3, 1), to: date(2026, 4, 1), calendar: utc)
        #expect(first.map(\.trackName) == ["B", "A"])
        #expect(second.map(\.trackName) == ["B", "A"])
        #expect(fake.requestCount == afterFirst)
    }

    /// The current month only fetches what is newer than its newest cached listen.
    @Test func currentMonth_fetchesOnlyNewListens() async throws {
        let fake = FakeListenHistory((1...6).map { listen(date(2026, 10, $0), "T\($0)") }, pageSize: 2)
        let history = store(fake, now: date(2026, 10, 29))
        _ = try await history.listens(user: "u", from: date(2026, 10, 1), to: date(2026, 11, 1), calendar: utc)
        let afterCold = fake.requestCount
        fake.add(listen(date(2026, 10, 28), "New"))
        let updated = try await history.listens(user: "u", from: date(2026, 10, 1), to: date(2026, 11, 1), calendar: utc)
        #expect(updated.first?.trackName == "New")
        #expect(updated.count == 7)
        // One page reaches the newest cached listen and stops.
        #expect(fake.requestCount - afterCold == 1)
    }

    @Test func refresh_refetchesAFinalMonth() async throws {
        let fake = FakeListenHistory([listen(date(2026, 3, 2), "A")])
        let history = store(fake, now: date(2026, 10, 29))
        _ = try await history.listens(user: "u", from: date(2026, 3, 1), to: date(2026, 4, 1), calendar: utc)
        fake.add(listen(date(2026, 3, 5), "Imported later"))
        let refreshed = try await history.listens(user: "u", from: date(2026, 3, 1), to: date(2026, 4, 1), calendar: utc, refresh: true)
        #expect(refreshed.map(\.trackName) == ["Imported later", "A"])
    }

    @Test func rateLimit_isWaitedOutAndContinued() async throws {
        let fake = FakeListenHistory([listen(date(2026, 3, 2), "A")])
        fake.rateLimitOnce = true
        let history = store(fake, now: date(2026, 10, 29))
        let listens = try await history.listens(user: "u", from: date(2026, 3, 1), to: date(2026, 4, 1), calendar: utc)
        #expect(listens.map(\.trackName) == ["A"])
    }

    @Test func overlappingPages_areDeduplicated() {
        let one = listen(date(2026, 3, 2), "A")
        #expect(ListenHistoryStore.deduplicated([one, one, listen(date(2026, 3, 3), "B")]).count == 2)
    }

    // MARK: Decoding

    /// MusicBrainz' own mapping is preferred over what the player sent.
    @Test func listen_decodesTheAPIShape() throws {
        let json = #"""
        {"listened_at": 1793000000, "track_metadata": {"artist_name": "Bill Evans", "track_name": "Gloria's Step",
         "release_name": "Sunday at the Village Vanguard",
         "additional_info": {"duration_ms": 360000, "recording_mbid": "from-player"},
         "mbid_mapping": {"recording_mbid": "from-musicbrainz"}}}
        """#
        let listen = try JSONDecoder().decode(LBListen.self, from: Data(json.utf8))
        #expect(listen.trackName == "Gloria's Step")
        #expect(listen.durationMs == 360_000)
        #expect(listen.recordingMBID == "from-musicbrainz")
        // The cache's flat shape round-trips.
        let cached = try JSONDecoder().decode(LBListen.self, from: JSONEncoder().encode(listen))
        #expect(cached == listen)
    }

    // MARK: Matching

    private func song(_ id: String, _ title: String, artist: String, mbid: String? = nil) -> Song {
        Song(id: id, title: title, album: "Album", artist: artist, duration: 240, albumId: "al-\(id)",
             artistId: "ar-\(artist)", musicBrainzId: mbid)
    }

    @Test func matcher_prefersTheRecordingIDThenTitleAndArtist() {
        let matcher = WrappedLibraryMatcher(songs: [
            song("s1", "Gloria's Step", artist: "Bill Evans Trio", mbid: "rec-1"),
            song("s2", "Waltz for Debby", artist: "Bill Evans")
        ])
        #expect(matcher.song(for: listen(date(2026, 1, 1), "Gloria’s Step (Take 2)", mbid: "REC-1"))?.id == "s1")
        #expect(matcher.song(for: listen(date(2026, 1, 1), "Waltz For Debby"))?.id == "s2")
        #expect(matcher.song(for: listen(date(2026, 1, 1), "Unknown tune")) == nil)
    }

    /// Listens of music outside the library still count, grouped under IDs of their own.
    @Test func unmatchedListens_countUnderExternalIDs() {
        let plays = [listen(date(2026, 1, 1), "Elsewhere"), listen(date(2026, 1, 2), "elsewhere")].map(WrappedLibraryMatcher.empty.play)
        #expect(plays.allSatisfy { !WrappedIDs.isLibraryID($0.trackId) })
        #expect(Set(plays.map(\.trackId)).count == 1)
        #expect(plays.first?.albumId.map(WrappedIDs.isLibraryID) == false)
        #expect(plays.first?.trackDuration == 300)
    }

    // MARK: Source

    private func source(username: String?, fake: FakeListenHistory, now: Date = date(2026, 10, 29)) throws -> WrappedDataSource {
        let container = try ModelContainer.minidisc(inMemory: true)
        return WrappedDataSource(
            stats: StatsService(modelContainer: container),
            history: store(fake, now: now),
            username: { username },
            librarySongs: { [] }
        )
    }

    @Test @MainActor func source_usesListenBrainzWithAnAccount() async throws {
        let fake = FakeListenHistory([listen(date(2026, 3, 2), "A"), listen(date(2026, 3, 9), "A")])
        let result = try await source(username: "u", fake: fake).wrappedData(for: .month(year: 2026, month: 3), serverId: "s", calendar: utc)
        #expect(result.source == .listenBrainz)
        #expect(!result.fellBack)
        #expect(result.data.totalTracksPlayed == 2)
    }

    @Test @MainActor func source_usesThePhoneWithoutAnAccount() async throws {
        let fake = FakeListenHistory([listen(date(2026, 3, 2), "A")])
        let result = try await source(username: nil, fake: fake).wrappedData(for: .month(year: 2026, month: 3), serverId: "s", calendar: utc)
        #expect(result.source == .device)
        #expect(!result.fellBack)
        #expect(fake.requestCount == 0)
    }

    /// Unreachable ListenBrainz falls back to the phone's plays, and says so.
    @Test @MainActor func source_fallsBackWhenListenBrainzFails() async throws {
        let container = try ModelContainer.minidisc(inMemory: true)
        let failing = ListenHistoryStore(
            directory: URL.temporaryDirectory.appendingPathComponent("lb-history-\(UUID())"),
            fetchPage: { _, _ in throw ListenBrainzError.httpError(statusCode: 503) },
            fetchOldest: { _ in nil }, now: { date(2026, 10, 29) }, sleep: { _ in }
        )
        let source = WrappedDataSource(stats: StatsService(modelContainer: container), history: failing,
                                       username: { "u" }, librarySongs: { [] })
        let result = await source.wrappedData(for: .month(year: 2026, month: 3), serverId: "s", calendar: utc)
        #expect(result.source == .device)
        #expect(result.fellBack)
    }

    /// The yearly playlist can only hold library songs.
    @Test @MainActor func topLibraryTracks_leaveOutMusicOutsideTheLibrary() async throws {
        let fake = FakeListenHistory([listen(date(2026, 3, 2), "In library", mbid: "rec-1"), listen(date(2026, 3, 3), "Not in library")])
        let container = try ModelContainer.minidisc(inMemory: true)
        let librarySong = Song(id: "s1", title: "In library", artist: "Bill Evans", duration: 240, musicBrainzId: "rec-1")
        let source = WrappedDataSource(stats: StatsService(modelContainer: container), history: store(fake, now: date(2026, 10, 29)),
                                       username: { "u" }, librarySongs: { [librarySong] })
        let top = await source.topLibraryTracks(year: 2026, serverId: "s", limit: 10, calendar: utc)
        #expect(top.map(\.trackId) == ["s1"])
    }
}
