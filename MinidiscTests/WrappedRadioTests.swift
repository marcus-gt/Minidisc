import Foundation
import SwiftData
import SwiftSonic
import Testing
@testable import Minidisc

nonisolated private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

nonisolated private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
    utc.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
}

nonisolated private func listen(_ day: Int, _ title: String, mbid: String) -> LBListen {
    LBListen(listenedAt: Int(date(2026, 3, day).timeIntervalSince1970), trackName: title,
             artistName: "Bill Evans", releaseName: nil, durationMs: 200_000, recordingMBID: mbid)
}

private func entry(_ id: String, rank: Int) -> TopTrackEntry {
    TopTrackEntry(rank: rank, trackId: id, title: "Title \(id)", artistName: "Artist", albumTitle: nil,
                  totalSecondsListened: 100, playCount: 1)
}

@Suite("Wrapped radio and periods (#69)")
@MainActor
struct WrappedRadioTests {
    private func source(listens: [LBListen], library: [Song]) throws -> WrappedDataSource {
        let pages = listens.sorted { $0.listenedAt > $1.listenedAt }
        let history = ListenHistoryStore(
            directory: URL.temporaryDirectory.appendingPathComponent("wrapped-radio-\(UUID())"),
            fetchPage: { _, maxTs in pages.filter { $0.listenedAt < maxTs } },
            fetchOldest: { _ in nil },
            now: { date(2026, 10, 30) },
            sleep: { _ in }
        )
        return WrappedDataSource(
            stats: StatsService(modelContainer: try ModelContainer.minidisc(inMemory: true)),
            history: history,
            username: { "u" },
            librarySongs: { library },
            songsByID: { ids in ids.compactMap { id in library.first { $0.id == id } } }
        )
    }

    @Test func periods_putTheYearFirstThenMonthsNewestFirst() {
        let current = WrappedView.periods(inYear: 2026, now: date(2026, 10, 30), calendar: utc)
        #expect(current.first == .year(2026))
        #expect(Array(current.dropFirst().prefix(2)) == [.month(year: 2026, month: 10), .month(year: 2026, month: 9)])
        #expect(current.last == .month(year: 2026, month: 1))
        #expect(current.count == 11)
        #expect(WrappedView.periods(inYear: 2024, now: date(2026, 10, 30), calendar: utc).count == 13)
    }

    @Test func years_runNewestFirstBackToTheFirstListen() {
        #expect(WrappedYears.years(firstYear: 2023, calendar: utc).prefix(1) == [Calendar.current.component(.year, from: Date())])
        #expect(WrappedYears.years(firstYear: 2023, calendar: utc).last == 2023)
        #expect(WrappedYears.years(firstYear: nil, calendar: utc).count == 1)
    }

    @Test func radioOrder_keepsTheTopTracksThenShufflesTheRest() {
        let ranked = (1...50).map { "t\($0)" }
        let order = WrappedDataSource.radioOrder(ranked, topCount: 10, limit: 30)
        #expect(Array(order.prefix(10)) == Array(ranked.prefix(10)))
        #expect(order.count == 30)
        #expect(Set(order).count == 30)
        #expect(Set(order.dropFirst(10)).isSubset(of: Set(ranked.dropFirst(10))))
    }

    /// The list plays as a queue in the order shown; rows outside the library are left out.
    @Test func topTracksQueue_keepsTheListOrderAndSkipsExternalRows() async throws {
        let library = [Song(id: "s2", title: "Two", artist: "Artist", duration: 180, albumId: "al2")]
        let source = try source(listens: [], library: library)
        let queue = await source.songs([entry("s1", rank: 1), entry("lb:track:x", rank: 2), entry("s2", rank: 3)])
        #expect(queue.map(\.id) == ["s1", "s2"])
        // Indexed songs carry their full metadata; the rest play from the ID alone.
        #expect(queue.last?.albumId == "al2")
        #expect(queue.first?.albumId == nil)
    }

    @Test func radioQueue_startsWithTheMostPlayedLibraryTrack() async throws {
        let library = [
            Song(id: "often", title: "Often", artist: "Bill Evans", duration: 200, musicBrainzId: "rec-often"),
            Song(id: "once", title: "Once", artist: "Bill Evans", duration: 200, musicBrainzId: "rec-once")
        ]
        let listens = [listen(2, "Often", mbid: "rec-often"), listen(3, "Often", mbid: "rec-often"),
                       listen(4, "Once", mbid: "rec-once"), listen(5, "Elsewhere", mbid: "rec-elsewhere")]
        let source = try source(listens: listens, library: library)
        let queue = await source.radioQueue(for: .month(year: 2026, month: 3), serverId: "s", calendar: utc)
        #expect(queue.map(\.id) == ["often", "once"])
    }
}
