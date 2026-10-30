import Foundation

/// The charts in Wrapped's stats carousel (#70): plays against the year before, the top artists'
/// ranks over time and when in the week the listening happened.
nonisolated struct WrappedInsights: Sendable, Equatable {
    /// A slice of the period: a month of a year, a day (plays) or week (timeline) of a month, or a
    /// year of the whole history.
    nonisolated struct Bucket: Sendable, Hashable, Identifiable {
        let index: Int
        let label: String
        var id: Int { index }
    }

    nonisolated struct PlaysBar: Sendable, Hashable, Identifiable {
        let bucket: Bucket
        let plays: Int
        /// The same slice a year earlier; nil for All Time, which has nothing to compare with.
        let previous: Int?
        var id: Int { bucket.index }
    }

    nonisolated struct ArtistLine: Sendable, Hashable, Identifiable {
        let artistId: String
        let name: String
        /// Rank per timeline bucket index, only where the artist made the top `rankCutoff`.
        let ranks: [Int: Int]
        var id: String { artistId }
    }

    let plays: [PlaysBar]
    let currentLabel: String
    /// "2025" next to "2026"; nil without a comparison.
    let previousLabel: String?
    let timelineBuckets: [Bucket]
    let artists: [ArtistLine]
    /// Plays per weekday and hour: `clock[weekday * 24 + hour]`, weekdays in the calendar's order.
    let clock: [Int]
    let weekdayLabels: [String]
    /// Full names in the same order, for the headline.
    let weekdayNames: [String]

    var totalPlays: Int { plays.reduce(0) { $0 + $1.plays } }
    var previousTotal: Int? { previousLabel == nil ? nil : plays.reduce(0) { $0 + ($1.previous ?? 0) } }

    /// The busiest weekday and hour, nil without plays.
    var peak: (weekday: Int, hour: Int)? {
        guard let best = clock.indices.max(by: { clock[$0] < clock[$1] }), clock[best] > 0 else { return nil }
        return (best / 24, best % 24)
    }

    /// The busiest hour of the day across the week.
    var peakHour: Int? {
        let hours = (0..<24).map { hour in (0..<7).reduce(0) { $0 + clock[$1 * 24 + hour] } }
        guard let best = hours.indices.max(by: { hours[$0] < hours[$1] }), hours[best] > 0 else { return nil }
        return best
    }
}

/// Builds `WrappedInsights` from plays. Pure, so it can be tested and run off the main actor.
nonisolated enum WrappedInsightsBuilder {
    static let timelineArtistCount = 8
    static let rankCutoff = 10

    static func build(period: WrappedPeriod, plays: [WrappedPlay], previousPlays: [WrappedPlay]?,
                      calendar: Calendar) -> WrappedInsights {
        // Calendar lookups dominate on a whole history (72k plays); each play is broken down once.
        let stamps = plays.map { Stamp($0.timestamp, calendar: calendar) }
        let years = yearSpan(of: stamps)
        let playBuckets = buckets(for: period, chart: .plays, years: years, calendar: calendar)
        let timelineBuckets = buckets(for: period, chart: .timeline, years: years, calendar: calendar)

        let current = counts(stamps, period: period, chart: .plays)
        let previous = previousPlays.map { earlier in
            counts(earlier.map { Stamp($0.timestamp, calendar: calendar) }, period: period, chart: .plays)
        }
        let bars = playBuckets.map { bucket in
            WrappedInsights.PlaysBar(bucket: bucket, plays: current[bucket.index] ?? 0,
                                     previous: previous.map { $0[bucket.index] ?? 0 })
        }

        return WrappedInsights(
            plays: bars,
            currentLabel: label(for: period),
            previousLabel: previousPlays == nil ? nil : previousLabel(for: period),
            timelineBuckets: timelineBuckets,
            artists: artistLines(plays, stamps: stamps, period: period, buckets: timelineBuckets),
            clock: clock(stamps, calendar: calendar),
            weekdayLabels: weekdays(calendar.shortStandaloneWeekdaySymbols, calendar: calendar),
            weekdayNames: weekdays(calendar.standaloneWeekdaySymbols, calendar: calendar)
        )
    }

    /// The period a year earlier, for "plays vs last year"; nil for All Time.
    static func comparisonPeriod(for period: WrappedPeriod) -> WrappedPeriod? {
        switch period {
        case let .year(year): .year(year - 1)
        case let .month(year, month): .month(year: year - 1, month: month)
        case .allTime: nil
        }
    }

    // MARK: - Buckets

    enum Chart { case plays, timeline }

    /// A play's date, broken down once.
    struct Stamp {
        let year: Int
        let month: Int
        let day: Int
        let hour: Int
        let weekday: Int

        init(_ date: Date, calendar: Calendar) {
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .weekday], from: date)
            year = parts.year ?? 0
            month = parts.month ?? 1
            day = parts.day ?? 1
            hour = parts.hour ?? 0
            weekday = parts.weekday ?? 1
        }
    }

    /// The bucket a play falls in: month of the year; day (plays) or week (timeline) of the month;
    /// year for All Time.
    static func bucketIndex(_ stamp: Stamp, period: WrappedPeriod, chart: Chart) -> Int {
        switch period {
        case .year: stamp.month
        case .month: chart == .plays ? stamp.day : (stamp.day - 1) / 7 + 1
        case .allTime: stamp.year
        }
    }

    static func buckets(for period: WrappedPeriod, chart: Chart, years: ClosedRange<Int>?,
                        calendar: Calendar) -> [WrappedInsights.Bucket] {
        switch period {
        case .year:
            let symbols = calendar.shortStandaloneMonthSymbols
            return (1...12).map { .init(index: $0, label: symbols[$0 - 1]) }
        case let .month(year, month):
            let start = calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? Date()
            let days = calendar.range(of: .day, in: .month, for: start)?.count ?? 30
            if chart == .plays {
                return (1...days).map { .init(index: $0, label: String($0)) }
            }
            return stride(from: 1, through: days, by: 7).enumerated().map { offset, first in
                .init(index: offset + 1, label: "\(first)–\(min(first + 6, days))")
            }
        case .allTime:
            guard let years else { return [] }
            return years.map { .init(index: $0, label: String($0)) }
        }
    }

    static func yearSpan(of stamps: [Stamp]) -> ClosedRange<Int>? {
        guard let first = stamps.map(\.year).min(), let last = stamps.map(\.year).max() else { return nil }
        return first...last
    }

    private static func counts(_ stamps: [Stamp], period: WrappedPeriod, chart: Chart) -> [Int: Int] {
        stamps.reduce(into: [:]) { result, stamp in
            result[bucketIndex(stamp, period: period, chart: chart), default: 0] += 1
        }
    }

    private static func label(for period: WrappedPeriod) -> String {
        switch period {
        case let .year(year), let .month(year, _): String(year)
        case .allTime: period.displayName
        }
    }

    private static func previousLabel(for period: WrappedPeriod) -> String? {
        switch period {
        case let .year(year), let .month(year, _): String(year - 1)
        case .allTime: nil
        }
    }

    // MARK: - Artists

    /// The period's top artists by listening time, each with its rank per bucket among all artists.
    static func artistLines(_ plays: [WrappedPlay], stamps: [Stamp], period: WrappedPeriod,
                            buckets: [WrappedInsights.Bucket]) -> [WrappedInsights.ArtistLine] {
        func key(_ play: WrappedPlay) -> String { play.artistId ?? "name:" + play.artistName }
        var totals: [String: (time: TimeInterval, name: String)] = [:]
        var perBucket: [Int: [String: TimeInterval]] = [:]
        for (play, stamp) in zip(plays, stamps) {
            let time = WrappedAggregator.effectiveDuration(for: play)
            totals[key(play), default: (0, play.artistName)].time += time
            let bucket = bucketIndex(stamp, period: period, chart: .timeline)
            perBucket[bucket, default: [:]][key(play), default: 0] += time
        }
        let top = totals.sorted { $0.value.time != $1.value.time ? $0.value.time > $1.value.time : $0.key < $1.key }
            .prefix(timelineArtistCount)
        var ranks: [String: [Int: Int]] = [:]
        for bucket in buckets {
            guard let times = perBucket[bucket.index] else { continue }
            let ordered = times.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            for (offset, entry) in ordered.prefix(rankCutoff).enumerated() {
                ranks[entry.key, default: [:]][bucket.index] = offset + 1
            }
        }
        return top.map { .init(artistId: $0.key, name: $0.value.name, ranks: ranks[$0.key] ?? [:]) }
    }

    // MARK: - Clock

    static func weekdayIndex(_ weekday: Int, calendar: Calendar) -> Int {
        (weekday - calendar.firstWeekday + 7) % 7
    }

    private static func clock(_ stamps: [Stamp], calendar: Calendar) -> [Int] {
        var grid = [Int](repeating: 0, count: 7 * 24)
        for stamp in stamps {
            grid[weekdayIndex(stamp.weekday, calendar: calendar) * 24 + stamp.hour] += 1
        }
        return grid
    }

    /// Weekday symbols (Sunday first) in the calendar's order.
    private static func weekdays(_ symbols: [String], calendar: Calendar) -> [String] {
        (0..<7).map { symbols[($0 + calendar.firstWeekday - 1) % 7] }
    }
}

/// The mood of a period from AudioMuse's per-track scores (#70). AudioMuse's six scores sit close
/// together, so the profile is shown on a zoomed axis and each bucket names the mood that stood out
/// most against the period as a whole.
nonisolated struct WrappedMoodProfile: Sendable, Equatable {
    nonisolated struct Score: Sendable, Hashable, Identifiable {
        let mood: QueueBuilderMood
        let value: Double
        var id: QueueBuilderMood { mood }
    }

    nonisolated struct Shift: Sendable, Hashable, Identifiable {
        let bucket: WrappedInsights.Bucket
        /// nil when the bucket has too few scored plays to say.
        let mood: QueueBuilderMood?
        var id: Int { bucket.index }
    }

    /// Play-weighted mean per mood, highest first.
    let scores: [Score]
    let shifts: [Shift]
    let scoredPlays: Int
    let totalPlays: Int

    var dominant: QueueBuilderMood? { scores.first?.mood }
}

nonisolated enum WrappedMoodBuilder {
    /// A bucket needs this many scored plays before it names a mood.
    static let minimumBucketPlays = 5

    static func build(plays: [WrappedPlay], scores: [String: AudioMuseMoodScores], period: WrappedPeriod,
                      buckets: [WrappedInsights.Bucket], calendar: Calendar) -> WrappedMoodProfile? {
        let scored = plays.compactMap { play in scores[play.trackId].map { (play, $0.values) } }
        guard !scored.isEmpty else { return nil }
        let overall = means(scored.map(\.1))
        guard !overall.isEmpty else { return nil }

        var byBucket: [Int: [[String: Double]]] = [:]
        for (play, values) in scored {
            let stamp = WrappedInsightsBuilder.Stamp(play.timestamp, calendar: calendar)
            byBucket[WrappedInsightsBuilder.bucketIndex(stamp, period: period, chart: .timeline), default: []].append(values)
        }
        let shifts = buckets.map { bucket -> WrappedMoodProfile.Shift in
            guard let values = byBucket[bucket.index], values.count >= minimumBucketPlays else {
                return .init(bucket: bucket, mood: nil)
            }
            let local = means(values)
            let standout = QueueBuilderMood.allCases
                .compactMap { mood -> (QueueBuilderMood, Double)? in
                    guard let value = local[mood], let base = overall[mood] else { return nil }
                    return (mood, value - base)
                }
                .max { $0.1 < $1.1 }
            return .init(bucket: bucket, mood: standout?.0)
        }
        return WrappedMoodProfile(
            scores: overall.map { .init(mood: $0.key, value: $0.value) }.sorted { $0.value > $1.value },
            shifts: shifts,
            scoredPlays: scored.count,
            totalPlays: plays.count
        )
    }

    private static func means(_ values: [[String: Double]]) -> [QueueBuilderMood: Double] {
        var result: [QueueBuilderMood: Double] = [:]
        for mood in QueueBuilderMood.allCases {
            let present = values.compactMap { $0[mood.rawValue] }
            if !present.isEmpty { result[mood] = present.reduce(0, +) / Double(present.count) }
        }
        return result
    }
}
