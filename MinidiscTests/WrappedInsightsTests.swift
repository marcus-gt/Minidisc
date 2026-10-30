import Foundation
import SwiftData
import SwiftSonic
import Testing
@testable import Minidisc

nonisolated private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    calendar.firstWeekday = 2
    return calendar
}

nonisolated private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
    utc.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
}

private func play(_ date: Date, artist: String, track: String = "t", seconds: TimeInterval = 200) -> WrappedPlay {
    WrappedPlay(timestamp: date, trackId: track, trackTitle: "Title", albumId: nil, albumTitle: nil,
                artistId: artist, artistName: artist, genre: nil, durationListened: seconds, trackDuration: seconds)
}

@Suite("Wrapped stats carousel and All Time (#70)")
@MainActor
struct WrappedInsightsTests {
    // MARK: Plays vs last year

    @Test func year_countsPlaysPerMonthAgainstTheYearBefore() {
        let plays = [play(date(2026, 1, 5), artist: "a"), play(date(2026, 1, 9), artist: "a"), play(date(2026, 3, 1), artist: "a")]
        let previous = [play(date(2025, 1, 2), artist: "a"), play(date(2025, 12, 31), artist: "a")]
        let insights = WrappedInsightsBuilder.build(period: .year(2026), plays: plays, previousPlays: previous, calendar: utc)
        #expect(insights.plays.count == 12)
        #expect(insights.plays[0].plays == 2 && insights.plays[0].previous == 1)
        #expect(insights.plays[2].plays == 1)
        #expect(insights.plays[11].previous == 1)
        #expect(insights.totalPlays == 3 && insights.previousTotal == 2)
        #expect(insights.currentLabel == "2026" && insights.previousLabel == "2025")
    }

    @Test func month_countsByDayAndRanksArtistsByWeek() {
        let plays = [play(date(2026, 2, 1), artist: "a"), play(date(2026, 2, 28), artist: "b")]
        let insights = WrappedInsightsBuilder.build(period: .month(year: 2026, month: 2), plays: plays, previousPlays: [], calendar: utc)
        #expect(insights.plays.count == 28)
        #expect(insights.timelineBuckets.map(\.label) == ["1–7", "8–14", "15–21", "22–28"])
        #expect(insights.artists.first { $0.artistId == "a" }?.ranks == [1: 1])
        #expect(insights.artists.first { $0.artistId == "b" }?.ranks == [4: 1])
    }

    /// All Time spans the years with plays and has nothing to compare with.
    @Test func allTime_bucketsByYearWithoutAComparison() {
        let plays = [play(date(2013, 5, 1), artist: "a"), play(date(2016, 5, 1), artist: "a")]
        let insights = WrappedInsightsBuilder.build(period: .allTime, plays: plays, previousPlays: nil, calendar: utc)
        #expect(insights.plays.map(\.bucket.label) == ["2013", "2014", "2015", "2016"])
        #expect(insights.previousLabel == nil && insights.previousTotal == nil)
        #expect(insights.plays.allSatisfy { $0.previous == nil })
        #expect(WrappedInsightsBuilder.comparisonPeriod(for: .allTime) == nil)
        #expect(WrappedInsightsBuilder.comparisonPeriod(for: .month(year: 2026, month: 3)) == .month(year: 2025, month: 3))
    }

    // MARK: Artists over time

    @Test func timeline_ranksByListeningTimePerMonth() {
        let plays = [
            play(date(2026, 1, 1), artist: "a", seconds: 300), play(date(2026, 1, 2), artist: "b", seconds: 100),
            play(date(2026, 2, 1), artist: "b", seconds: 300), play(date(2026, 2, 2), artist: "a", seconds: 100)
        ]
        let insights = WrappedInsightsBuilder.build(period: .year(2026), plays: plays, previousPlays: nil, calendar: utc)
        let a = insights.artists.first { $0.artistId == "a" }
        let b = insights.artists.first { $0.artistId == "b" }
        #expect(a?.ranks == [1: 1, 2: 2])
        #expect(b?.ranks == [1: 2, 2: 1])
    }

    @Test func timeline_keepsTheTopFiveArtists() {
        let plays = (0..<12).map { play(date(2026, 1, 1), artist: "artist\($0)", seconds: Double(100 + $0)) }
        let insights = WrappedInsightsBuilder.build(period: .year(2026), plays: plays, previousPlays: nil, calendar: utc)
        #expect(insights.artists.count == WrappedInsightsBuilder.timelineArtistCount)
        #expect(insights.artists.first?.artistId == "artist11")
    }

    // MARK: Clock

    /// Weekdays follow the calendar's first weekday (Monday here).
    @Test func clock_findsTheBusiestWeekdayAndHour() {
        // 2026-10-30 is a Friday.
        let plays = [play(date(2026, 10, 30, hour: 21), artist: "a"), play(date(2026, 10, 30, hour: 21), artist: "a"),
                     play(date(2026, 10, 26, hour: 8), artist: "a")]
        let insights = WrappedInsightsBuilder.build(period: .year(2026), plays: plays, previousPlays: nil, calendar: utc)
        #expect(insights.weekdayLabels.first == utc.shortStandaloneWeekdaySymbols[1])
        #expect(insights.peak?.weekday == 4)
        #expect(insights.peak?.hour == 21)
        #expect(insights.peakHour == 21)
        #expect(insights.clock[0 * 24 + 8] == 1)
    }

    // MARK: Mood

    @Test func mood_averagesByPlaysAndNamesWhatStoodOutEachMonth() {
        var plays = (1...5).map { play(date(2026, 1, $0), artist: "a", track: "calm") }
        plays += (1...5).map { play(date(2026, 2, $0), artist: "a", track: "loud") }
        plays.append(play(date(2026, 3, 1), artist: "a", track: "loud"))
        let scores = [
            "calm": AudioMuseMoodScores(values: ["relaxed": 0.7, "aggressive": 0.5, "happy": 0.6]),
            "loud": AudioMuseMoodScores(values: ["relaxed": 0.5, "aggressive": 0.7, "happy": 0.6])
        ]
        let buckets = WrappedInsightsBuilder.buckets(for: .year(2026), chart: .timeline, years: nil, calendar: utc)
        let mood = WrappedMoodBuilder.build(plays: plays, scores: scores, period: .year(2026), buckets: buckets, calendar: utc)
        #expect(mood?.scoredPlays == 11)
        #expect(mood?.dominant == .aggressive)
        #expect(mood?.shifts[0].mood == .relaxed)
        #expect(mood?.shifts[1].mood == .aggressive)
        // One play isn't enough to say.
        #expect(mood?.shifts[2].mood == nil)
    }

    @Test func mood_isNilWithoutScores() {
        let mood = WrappedMoodBuilder.build(plays: [play(date(2026, 1, 1), artist: "a")], scores: [:], period: .year(2026),
                                            buckets: [], calendar: utc)
        #expect(mood == nil)
    }

    @Test func moodLabels_shortenYears() {
        #expect(WrappedMoodCard.shortLabel("2013") == "\u{2019}13")
        #expect(WrappedMoodCard.shortLabel("January") == "Jan")
        #expect(WrappedMoodCard.shortLabel("1–7") == "1–7")
    }

    // MARK: Data source

    nonisolated private final class Requests: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        private var maxTs: [Int] = []
        func record(_ ts: Int) { lock.withLock { count += 1; maxTs.append(ts) } }
        var total: Int { lock.withLock { count } }
        var bounds: [Int] { lock.withLock { maxTs } }
    }

    private func source(listens: [LBListen], requests: Requests, firstYear: Int = 2024) throws -> WrappedDataSource {
        let sorted = listens.sorted { $0.listenedAt > $1.listenedAt }
        let oldest = sorted.last
        let history = ListenHistoryStore(
            directory: URL.temporaryDirectory.appendingPathComponent("wrapped-insights-\(UUID())"),
            fetchPage: { _, maxTs in requests.record(maxTs); return Array(sorted.filter { $0.listenedAt < maxTs }.prefix(2)) },
            fetchOldest: { _ in oldest },
            now: { date(2026, 10, 30) },
            sleep: { _ in }
        )
        return WrappedDataSource(stats: StatsService(modelContainer: try ModelContainer.minidisc(inMemory: true)),
                                 history: history, username: { "u" }, librarySongs: { [] }, now: { date(2026, 10, 30) })
    }

    private func listen(_ date: Date, _ title: String) -> LBListen {
        LBListen(listenedAt: Int(date.timeIntervalSince1970), trackName: title, artistName: "Artist",
                 releaseName: nil, durationMs: 200_000, recordingMBID: nil)
    }

    /// All Time starts at the first listen, reports progress, and the recap and cards share one fetch.
    @Test func allTime_loadsFromTheFirstListenWithProgressAndOneFetch() async throws {
        let requests = Requests()
        let listens = [listen(date(2024, 3, 1), "Old"), listen(date(2025, 6, 1), "Mid"), listen(date(2026, 9, 1), "New")]
        let source = try source(listens: listens, requests: requests)
        let progress = Requests()
        let result = await source.wrappedData(for: .allTime, serverId: "s", calendar: utc, progress: { progress.record($0) })
        #expect(result.data.totalTracksPlayed == 3)
        #expect(result.source == .listenBrainz)
        #expect(progress.bounds.last == 3)
        let afterRecap = requests.total
        let insights = await source.insights(for: .allTime, serverId: "s", calendar: utc)
        #expect(insights.plays.map(\.bucket.label) == ["2024", "2025", "2026"])
        #expect(requests.total == afterRecap)
    }

    @Test func insights_compareWithTheYearBefore() async throws {
        let requests = Requests()
        let listens = [listen(date(2025, 2, 1), "Before"), listen(date(2026, 2, 1), "Now"), listen(date(2026, 3, 1), "Now")]
        let source = try source(listens: listens, requests: requests)
        let insights = await source.insights(for: .year(2026), serverId: "s", calendar: utc)
        #expect(insights.totalPlays == 2)
        #expect(insights.previousTotal == 1)
    }

    /// Without AudioMuse the mood card is left out.
    @Test func moodProfile_isNilWithoutAudioMuse() async throws {
        let source = try source(listens: [listen(date(2026, 2, 1), "Now")], requests: Requests())
        #expect(await source.moodProfile(for: .year(2026), serverId: "s", calendar: utc) == nil)
    }

    @Test func allTimePeriod_isNamedAndPicked() {
        #expect(WrappedPeriod.allTime.displayName == String(localized: "All Time"))
        #expect(WrappedView.periods(inYear: 2026, now: date(2026, 10, 30), calendar: utc).first == .year(2026))
    }
}
