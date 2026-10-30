import Charts
import SwiftUI

/// The stats carousel under a recap's hero (#70): plays against the year before, the top artists
/// over time, the listening clock and, with AudioMuse, the period's mood. One card per page.
struct WrappedInsightsCarousel: View {
    let insights: WrappedInsights
    let mood: WrappedMoodProfile?
    let isLoadingMood: Bool
    let accent: Color

    @State private var page: Int? = 0

    private var pageCount: Int { (mood != nil || isLoadingMood) ? 4 : 3 }

    var body: some View {
        VStack(spacing: MinidiscSpacing.s) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: MinidiscSpacing.s) {
                    WrappedPlaysCard(insights: insights, accent: accent).id(0)
                    WrappedArtistTimelineCard(insights: insights).id(1)
                    WrappedListeningClockCard(insights: insights, accent: accent).id(2)
                    if let mood {
                        WrappedMoodCard(mood: mood).id(3)
                    } else if isLoadingMood {
                        WrappedInsightCard(title: "Mood", headline: Text("Asking AudioMuse…")) {
                            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .id(3)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $page)
            .contentMargins(.horizontal, MinidiscSpacing.l, for: .scrollContent)
            .padding(.horizontal, -MinidiscSpacing.l)

            HStack(spacing: MinidiscSpacing.xs) {
                ForEach(0..<pageCount, id: \.self) { index in
                    Circle()
                        .fill(index == (page ?? 0) ? Color.primary : Color.primary.opacity(0.25))
                        .frame(width: 6, height: 6)
                }
            }
            .accessibilityHidden(true)
        }
    }
}

/// The shared frame of a stat card: a title, a one-line takeaway and the chart.
struct WrappedInsightCard<Content: View>: View {
    let title: LocalizedStringKey
    let headline: Text
    @ViewBuilder let content: () -> Content

    static var height: CGFloat { 340 }

    var body: some View {
        VStack(alignment: .leading, spacing: MinidiscSpacing.s) {
            Text(title)
                .font(.minidiscCaption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            headline
                .font(.minidiscSectionTitle)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            content()
                .frame(maxHeight: .infinity)
        }
        .padding(MinidiscSpacing.l)
        .frame(height: Self.height)
        .containerRelativeFrame(.horizontal)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: MinidiscCornerRadius.large, style: .continuous))
    }
}

// MARK: - Plays vs last year

struct WrappedPlaysCard: View {
    let insights: WrappedInsights
    let accent: Color

    private var headline: Text {
        guard let previousLabel = insights.previousLabel, let previous = insights.previousTotal else {
            return Text("\(insights.totalPlays) plays")
        }
        guard previous > 0 else { return Text("\(insights.totalPlays) plays, none in \(previousLabel)") }
        let change = Double(insights.totalPlays - previous) / Double(previous)
        return Text("\(change.formatted(.percent.precision(.fractionLength(0)).sign(strategy: .always()))) on \(previousLabel)")
    }

    /// Label every bucket on a year; thin the days of a month and the years of the whole history.
    private var labelStride: Int { insights.plays.count > 12 ? max(insights.plays.count / 6, 1) : 1 }

    private var axisLabels: [String] {
        insights.plays.enumerated().filter { $0.offset % labelStride == 0 }.map(\.element.bucket.label)
    }

    var body: some View {
        WrappedInsightCard(title: "Plays", headline: headline) {
            Chart {
                ForEach(insights.plays) { bar in
                    // Categorical x: bars on a continuous axis need a unit to get a width.
                    BarMark(x: .value("Period", bar.bucket.label), y: .value("Plays", bar.plays), width: .ratio(0.7))
                        .foregroundStyle(by: .value("Year", insights.currentLabel))
                    if let previous = bar.previous, let label = insights.previousLabel {
                        LineMark(x: .value("Period", bar.bucket.label), y: .value("Plays", previous))
                            .foregroundStyle(by: .value("Year", label))
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 3]))
                            .interpolationMethod(.monotone)
                    }
                }
            }
            .chartForegroundStyleScale(domain: [insights.currentLabel] + [insights.previousLabel].compactMap { $0 },
                                       range: [accent, Color.secondary])
            .chartXScale(domain: insights.plays.map(\.bucket.label))
            .chartXAxis {
                AxisMarks(values: axisLabels) { value in
                    AxisValueLabel {
                        if let label = value.as(String.self) {
                            Text(verbatim: insights.plays.count == 12 ? String(label.prefix(1)) : label)
                        }
                    }
                }
            }
            .chartLegend(insights.previousLabel == nil ? .hidden : .visible)
        }
    }
}

// MARK: - Top artists timeline

struct WrappedArtistTimelineCard: View {
    let insights: WrappedInsights

    private var leader: String? { insights.artists.first?.name }

    /// Distinct for all eight lines; the default palette repeats before that.
    private static let lineColors: [Color] = [.blue, .green, .orange, .purple, .red, .cyan, .yellow, .mint]

    var body: some View {
        WrappedInsightCard(
            title: "Top Artists Over Time",
            headline: leader.map { Text("\($0) led the way") } ?? Text("Not enough listening yet")
        ) {
            Chart {
                ForEach(insights.artists) { artist in
                    ForEach(insights.timelineBuckets) { bucket in
                        if let rank = artist.ranks[bucket.index] {
                            LineMark(x: .value("Period", bucket.label), y: .value("Rank", rank))
                                .foregroundStyle(by: .value("Artist", artist.name))
                                .interpolationMethod(.monotone)
                            PointMark(x: .value("Period", bucket.label), y: .value("Rank", rank))
                                .foregroundStyle(by: .value("Artist", artist.name))
                                .symbolSize(24)
                        }
                    }
                }
            }
            .chartForegroundStyleScale(domain: insights.artists.map(\.name),
                                       range: Array(Self.lineColors.prefix(max(insights.artists.count, 1))))
            .chartXScale(domain: insights.timelineBuckets.map(\.label))
            .chartYScale(domain: .automatic(includesZero: false, reversed: true))
            .chartYAxis {
                AxisMarks(position: .leading, values: [1, 5, 10]) { value in
                    AxisGridLine()
                    AxisValueLabel { if let rank = value.as(Int.self) { Text(verbatim: "#\(rank)") } }
                }
            }
            .chartXAxis {
                AxisMarks(values: insights.timelineBuckets.enumerated()
                    .filter { $0.offset % max(insights.timelineBuckets.count / 12, 1) == 0 }.map(\.element.label)) { value in
                    AxisValueLabel {
                        if let label = value.as(String.self) {
                            Text(verbatim: insights.timelineBuckets.count == 12 ? String(label.prefix(1)) : label)
                        }
                    }
                }
            }
            .chartLegend(position: .bottom, spacing: MinidiscSpacing.xs)
        }
    }
}

// MARK: - Listening clock

struct WrappedListeningClockCard: View {
    let insights: WrappedInsights
    let accent: Color

    private var maxCount: Int { insights.clock.max() ?? 0 }

    private var headline: Text {
        guard let peak = insights.peak else { return Text("No listening yet") }
        return Text("Most often on \(insights.weekdayNames[peak.weekday]) around \(Self.hourLabel(peak.hour, minutes: true))")
    }

    static func hourLabel(_ hour: Int, minutes: Bool = false) -> String {
        let date = Calendar.current.date(from: DateComponents(hour: hour)) ?? Date()
        return minutes ? date.formatted(date: .omitted, time: .shortened) : date.formatted(.dateTime.hour())
    }

    var body: some View {
        WrappedInsightCard(title: "Listening Clock", headline: headline) {
            Chart {
                ForEach(0..<7, id: \.self) { weekday in
                    ForEach(0..<24, id: \.self) { hour in
                        let count = insights.clock[weekday * 24 + hour]
                        // Explicit start and end: a ratio width needs a unit on a continuous axis.
                        RectangleMark(
                            xStart: .value("Hour", Double(hour) + 0.06),
                            xEnd: .value("Hour", Double(hour) + 0.94),
                            y: .value("Day", insights.weekdayLabels[weekday]),
                            height: .ratio(0.85)
                        )
                        .foregroundStyle(accent.opacity(maxCount == 0 ? 0.08 : 0.08 + 0.92 * Double(count) / Double(maxCount)))
                    }
                }
            }
            .chartYScale(domain: insights.weekdayLabels)
            .chartYAxis {
                AxisMarks(position: .leading) { _ in AxisValueLabel() }
            }
            .chartXScale(domain: 0...24)
            .chartXAxis {
                AxisMarks(values: [0.0, 6, 12, 18]) { value in
                    AxisValueLabel { if let hour = value.as(Double.self) { Text(verbatim: Self.hourLabel(Int(hour))) } }
                }
            }
            .accessibilityLabel(Text("Listening by weekday and hour"))
        }
    }
}

// MARK: - Mood

struct WrappedMoodCard: View {
    let mood: WrappedMoodProfile

    /// Where `value` sits on the zoomed range, 0…1.
    private func fraction(_ value: Double) -> Double {
        let width = range.upperBound - range.lowerBound
        return width > 0 ? (value - range.lowerBound) / width : 1
    }

    private var range: ClosedRange<Double> {
        let values = mood.scores.map(\.value)
        let low = values.min() ?? 0, high = values.max() ?? 1
        // AudioMuse's scores sit close together; zoom in so the differences show.
        return max(0, low - 0.02)...min(1, high + 0.01)
    }

    var body: some View {
        WrappedInsightCard(
            title: "Mood",
            headline: mood.dominant.map { Text("Top mood: \(Text($0.title))") } ?? Text("Mood")
        ) {
            VStack(alignment: .leading, spacing: MinidiscSpacing.s) {
                VStack(spacing: 6) {
                    ForEach(mood.scores) { score in
                        HStack(spacing: MinidiscSpacing.s) {
                            Text(score.mood.title)
                                .font(.minidiscCaption)
                                .frame(width: 84, alignment: .leading)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            GeometryReader { proxy in
                                Capsule()
                                    .fill(score.mood.wrappedColor)
                                    .frame(width: max(6, proxy.size.width * fraction(score.value)))
                            }
                            .frame(height: 8)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }

                Text("Stood out")
                    .font(.minidiscCaption.weight(.semibold))
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: min(max(mood.shifts.count, 1), 12)),
                          spacing: MinidiscSpacing.xs) {
                    ForEach(mood.shifts) { shift in
                        VStack(spacing: 2) {
                            Image(systemName: shift.mood?.wrappedSymbol ?? "minus")
                                .font(.minidiscCaption)
                                .foregroundStyle(shift.mood?.wrappedColor ?? .secondary)
                            Text(verbatim: Self.shortLabel(shift.bucket.label))
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(verbatim: shift.bucket.label))
                        .accessibilityValue(shift.mood.map { Text($0.title) } ?? Text("Not enough plays"))
                    }
                }

                Text("From the \(mood.scoredPlays) of \(mood.totalPlays) plays AudioMuse has analysed.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

extension WrappedMoodCard {
    /// "Jan" stays, a year becomes "’11", a week ("1–7") stays.
    static func shortLabel(_ label: String) -> String {
        if label.count == 4, Int(label) != nil { return "\u{2019}" + label.suffix(2) }
        return String(label.prefix(3))
    }
}

extension QueueBuilderMood {
    var wrappedSymbol: String {
        switch self {
        case .happy: "sun.max.fill"
        case .sad: "cloud.rain.fill"
        case .relaxed: "leaf.fill"
        case .aggressive: "flame.fill"
        case .party: "party.popper.fill"
        case .danceable: "figure.dance"
        }
    }

    var wrappedColor: Color {
        switch self {
        case .happy: .yellow
        case .sad: .blue
        case .relaxed: .green
        case .aggressive: .red
        case .party: .pink
        case .danceable: .purple
        }
    }
}

private enum WrappedInsightsPreviewData {
    static let calendar = Calendar.current
    static let plays: [WrappedPlay] = {
        let artists = ["Keith Jarrett", "Bill Evans", "Steely Dan", "Chet Baker", "nthng", "Barker", "Moses Boyd", "Sam Gendel"]
        let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        return (0..<400).map { index in
            let artist = artists[(index * index) % 37 % 8]
            let date = start.addingTimeInterval(Double(index) * 64_800 + Double(index % 5) * 3_600)
            return WrappedPlay(timestamp: date, trackId: "t\(index % 90)", trackTitle: "Track", albumId: nil, albumTitle: nil,
                               artistId: artist, artistName: artist, genre: nil, durationListened: 240, trackDuration: 240)
        }
    }()
    static let insights = WrappedInsightsBuilder.build(
        period: .year(2026), plays: plays,
        previousPlays: plays.prefix(330).map { play in
            var earlier = play
            earlier.timestamp = calendar.date(byAdding: .year, value: -1, to: play.timestamp)!
            return earlier
        },
        calendar: calendar
    )
    static let mood = WrappedMoodBuilder.build(
        plays: plays,
        scores: Dictionary(uniqueKeysWithValues: (0..<90).map { index in
            ("t\(index)", AudioMuseMoodScores(values: Dictionary(uniqueKeysWithValues: QueueBuilderMood.allCases.enumerated().map {
                ($0.element.rawValue, 0.55 + Double(($0.offset * 7 + index) % 11) / 100)
            })))
        }),
        period: .year(2026), buckets: insights.timelineBuckets, calendar: calendar
    )
    static let accent = WrappedYearPalette.colors(for: 2026)[0]
}

#Preview("Plays") {
    WrappedPlaysCard(insights: WrappedInsightsPreviewData.insights, accent: WrappedInsightsPreviewData.accent)
        .padding().preferredColorScheme(.dark)
}

#Preview("Artists") {
    WrappedArtistTimelineCard(insights: WrappedInsightsPreviewData.insights)
        .padding().preferredColorScheme(.dark)
}

#Preview("Clock") {
    WrappedListeningClockCard(insights: WrappedInsightsPreviewData.insights, accent: WrappedInsightsPreviewData.accent)
        .padding().preferredColorScheme(.dark)
}

#Preview("Mood") {
    if let mood = WrappedInsightsPreviewData.mood {
        WrappedMoodCard(mood: mood).padding().preferredColorScheme(.dark)
    }
}
