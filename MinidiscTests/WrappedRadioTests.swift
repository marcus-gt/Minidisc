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

    /// Over many shuffles, a track played ten times leads far more often than one played once.
    @Test func weightedShuffle_favoursTheMostPlayed() {
        var generator = SystemRandomNumberGenerator()
        let items = [("often", 10.0), ("once", 1.0)]
        var oftenFirst = 0
        for _ in 0..<2_000 {
            let order = items.weightedShuffled(weight: { $0.1 }, using: &generator)
            #expect(order.count == 2)
            if order.first?.0 == "often" { oftenFirst += 1 }
        }
        // Expected share 10/11 ≈ 91 %.
        #expect(oftenFirst > 1_600)
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

    @Test func radio_holdsThePeriodsLibraryTracksAndSeedsFromTheTop() async throws {
        let library = [
            Song(id: "often", title: "Often", artist: "Bill Evans", duration: 200, musicBrainzId: "rec-often"),
            Song(id: "once", title: "Once", artist: "Bill Evans", duration: 200, musicBrainzId: "rec-once")
        ]
        let listens = [listen(2, "Often", mbid: "rec-often"), listen(3, "Often", mbid: "rec-often"),
                       listen(4, "Once", mbid: "rec-once"), listen(5, "Elsewhere", mbid: "rec-elsewhere")]
        let source = try source(listens: listens, library: library)
        let radio = await source.radio(for: .month(year: 2026, month: 3), serverId: "s", calendar: utc)
        #expect(Set(radio.tracks.map(\.id)) == ["often", "once"])
        #expect(radio.seedIDs == ["often", "once"])
    }

    // MARK: Matching imported listens

    private func imported(_ title: String, _ artist: String, release: String? = nil) -> LBListen {
        LBListen(listenedAt: 1, trackName: title, artistName: artist, releaseName: release, durationMs: nil, recordingMBID: nil)
    }

    /// Real listens from the ListenBrainz archive importer against how the library names them.
    @Test func matcher_matchesImportedSpotifyTitlesAndCredits() {
        let matcher = WrappedLibraryMatcher(songs: [
            Song(id: "koln1", title: "Köln, January 24, 1975, Part I", album: "The Köln Concert", artist: "Keith Jarrett", artistId: "kj"),
            Song(id: "koln2a", title: "Köln, January 24, 1975, Part IIa", album: "The Köln Concert", artist: "Keith Jarrett", artistId: "kj"),
            Song(id: "koln2c", title: "Köln, January 24, 1975, Part IIc", album: "The Köln Concert", artist: "Keith Jarrett", artistId: "kj"),
            Song(id: "youandi", title: "You And I, Part II", album: "Tango In The Night", artist: "Fleetwood Mac"),
            Song(id: "debby1", title: "Waltz for Debby (take 1)", album: "Waltz for Debby", artist: "Bill Evans Trio"),
            Song(id: "debby2", title: "Waltz for Debby (take 2)", album: "Waltz for Debby", artist: "Bill Evans Trio"),
            Song(id: "leaves-norway", title: "Autumn Leaves", album: "Bill Evans in Norway", artist: "Bill Evans"),
            Song(id: "leaves", title: "Autumn Leaves", album: "Portrait in Jazz", artist: "Bill Evans Trio"),
            Song(id: "marooned", title: "Marooned In S.E.6", album: "Displaced Diaspora",
                 artist: "Moses Boyd Exodus Feat. Kevin Haynes Grupo Elegua"),
            Song(id: "pata", title: "Pata Pata", album: "Y-Otis", artist: "Otis Sandsjö")
        ])
        #expect(matcher.song(for: imported("Köln, January 24, 1975, Part I - Live", "Keith Jarrett"))?.id == "koln1")
        #expect(matcher.song(for: imported("Köln, January 24, 1975, Part II c - Live", "Keith Jarrett"))?.id == "koln2c")
        #expect(matcher.song(for: imported("Köln, January 24, 1975, Part II a - Live", "Keith Jarrett"))?.id == "koln2a")
        #expect(matcher.song(for: imported("You And I, Pt. II - Remastered", "Fleetwood Mac"))?.id == "youandi")
        #expect(matcher.song(for: imported("Waltz For Debby - Live / Take 2", "Bill Evans Trio"))?.id == "debby2")
        #expect(matcher.song(for: imported("Autumn Leaves - Album Version - (Take 1)", "Bill Evans Trio",
                                           release: "Portrait In Jazz"))?.id == "leaves")
        #expect(matcher.song(for: imported("Marooned In S.E.6", "Moses Boyd, Kevin Haynes"))?.id == "marooned")
        #expect(matcher.song(for: imported("pata pata", "Otis Sandsjö, Petter Eldh, Elias Stemeseder, Tilo Weber"))?.id == "pata")
        // Same title by someone else stays unmatched.
        #expect(matcher.song(for: imported("Autumn Leaves", "Cannonball Adderley")) == nil)
    }

    /// A listen that matches no song still credits the library's artist, so it can be opened.
    @Test func unmatchedListen_creditsTheLibraryArtist() {
        let matcher = WrappedLibraryMatcher(songs: [
            Song(id: "koln1", title: "Köln, January 24, 1975, Part I", album: "The Köln Concert", artist: "Keith Jarrett",
                 albumId: "kc", artistId: "kj")
        ])
        let play = matcher.play(for: imported("Encore from Tokyo", "Keith Jarrett", release: "The Köln Concert"))
        #expect(!WrappedIDs.isLibraryID(play.trackId))
        #expect(play.artistId == "kj")
        #expect(play.albumId == "kc")
    }
}
