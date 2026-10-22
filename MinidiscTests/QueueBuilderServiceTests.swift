import Foundation
import SwiftSonic
import Synchronization
import Testing
@testable import Minidisc

private func song(_ id: String, genres: [String] = [], year: Int? = nil) -> Song {
    let genreJSON = genres.map { "{\"name\":\"\($0)\"}" }.joined(separator: ",")
    let yearJSON = year.map { ",\"year\":\($0)" } ?? ""
    return try! JSONDecoder().decode(Song.self, from: Data(
        "{\"id\":\"\(id)\",\"title\":\"\(id)\",\"isDir\":false,\"genres\":[\(genreJSON)]\(yearJSON)}".utf8
    ))
}

private nonisolated final class FakeQueueBuilderSource: QueueBuilderLibrarySource {
    private struct State {
        var stamp: String?
        var tracks: [QueueBuilderTrack] = []
        var trackReads = 0
    }
    private let state = Mutex(State())

    func set(stamp: String?, tracks: [QueueBuilderTrack] = []) {
        state.withLock { $0.stamp = stamp; $0.tracks = tracks }
    }
    var trackReads: Int { state.withLock { $0.trackReads } }

    func queueBuilderStamp() async throws -> String? { state.withLock { $0.stamp } }
    func queueBuilderTracks() async throws -> [QueueBuilderTrack]? {
        state.withLock {
            $0.trackReads += 1
            return $0.stamp == nil ? nil : $0.tracks
        }
    }
}

private nonisolated final class FakeGenreLibrary: GenreBrowsing, MoodTrackSourcing {
    private struct State {
        var genres: [Genre] = []
        var songsByGenre: [String: [Song]] = [:]
        var requested: [String] = []
    }
    private let state = Mutex(State())

    func set(genres: [(String, Int)], songs: [String: [Song]]) {
        let decoded = genres.map { name, count in
            try! JSONDecoder().decode(Genre.self, from: Data(
                "{\"value\":\"\(name)\",\"songCount\":\(count),\"albumCount\":1}".utf8
            ))
        }
        state.withLock { $0.genres = decoded; $0.songsByGenre = songs }
    }
    var requested: [String] { state.withLock { $0.requested.sorted() } }

    func genres() async throws -> [Genre] { state.withLock { $0.genres } }
    func albumsByGenre(_ genre: String, size: Int) async throws -> [AlbumID3] { [] }
    func songsByGenre(_ genre: String, count: Int) async throws -> [Song] {
        state.withLock {
            $0.requested.append(genre)
            return $0.songsByGenre[genre] ?? []
        }
    }
    func randomSongs(size: Int) async throws -> [Song] { [] }
}

private nonisolated final class FakeMoodScorer: MoodScoring {
    private let available: Bool
    private let scores: [String: AudioMuseMoodScores]
    private let failure: (any Error)?
    private let asked = Mutex<Int>(0)

    init(available: Bool = true, scores: [String: AudioMuseMoodScores] = [:], failure: (any Error)? = nil) {
        self.available = available
        self.scores = scores
        self.failure = failure
    }
    var askedCount: Int { asked.withLock { $0 } }

    func isAvailable() async -> Bool { available }
    func scores(for songIDs: [String]) async throws -> [String: AudioMuseMoodScores] {
        asked.withLock { $0 += songIDs.count }
        if let failure { throw failure }
        return scores.filter { songIDs.contains($0.key) }
    }
}

@Suite("QueueBuilderService")
struct QueueBuilderServiceTests {
    @Test func indexedLibrary_isExactAndReadOncePerSync() async throws {
        let source = FakeQueueBuilderSource()
        source.set(stamp: "v1", tracks: [
            QueueBuilderTrack(song: song("a"), genres: ["Modal", "Fusion"], year: 1959),
            QueueBuilderTrack(song: song("b"), genres: ["Techno"], year: 1994),
        ])
        let service = QueueBuilderService(source: source, library: FakeGenreLibrary())

        let first = try await service.index()
        _ = try await service.index()
        #expect(!first.isApproximate)
        #expect(first.columns.first { $0.id == "Jazz" }?.songCount == 1)
        #expect(source.trackReads == 1)

        source.set(stamp: "v2", tracks: [QueueBuilderTrack(song: song("c"), genres: ["Techno"], year: 2001)])
        let refreshed = try await service.index()
        #expect(source.trackReads == 2)
        #expect(refreshed.columns.map(\.id) == ["Electronic"])
    }

    @Test func indexedLibrary_buildsFromThePicks() async throws {
        let source = FakeQueueBuilderSource()
        source.set(stamp: "v1", tracks: [
            QueueBuilderTrack(song: song("a"), genres: ["Modal"], year: 1959),
            QueueBuilderTrack(song: song("b"), genres: ["Modal"], year: 1975),
            QueueBuilderTrack(song: song("c"), genres: ["Techno"], year: 1994),
        ])
        let service = QueueBuilderService(source: source, library: FakeGenreLibrary())

        let queue = try await service.buildQueue(QueueBuilderSelection(mains: ["Jazz"], decades: [1950]), count: 10).songs
        #expect(queue.map(\.id) == ["a"])
    }

    @Test func incompleteIndex_usesServerGenresAndMatchesTheSample() async throws {
        let source = FakeQueueBuilderSource()
        source.set(stamp: nil)
        let library = FakeGenreLibrary()
        library.set(
            genres: [("Modal Jazz", 2), ("Fusion", 3), ("Techno", 5)],
            songs: [
                "Modal Jazz": [song("m1", genres: ["Modal Jazz"], year: 1961)],
                "Fusion": [song("f1", genres: ["Fusion"], year: 1975), song("f2", genres: ["Fusion"], year: 1961)],
                "Techno": [song("t1", genres: ["Techno"])],
            ]
        )
        let service = QueueBuilderService(source: source, library: library)

        let index = try await service.index()
        #expect(index.isApproximate)
        #expect(index.columns.first { $0.id == "Jazz" }?.songCount == 5)

        let queue = try await service.buildQueue(QueueBuilderSelection(mains: ["Jazz"], decades: [1960]), count: 10).songs
        #expect(library.requested == ["Fusion", "Modal Jazz"])
        #expect(Set(queue.map(\.id)) == ["m1", "f2"])
    }

    // MARK: Moods

    private func technoSource(_ count: Int) -> FakeQueueBuilderSource {
        let source = FakeQueueBuilderSource()
        source.set(stamp: "v1", tracks: (1...count).map { QueueBuilderTrack(song: song("s\($0)"), genres: ["Techno"], year: 1995) })
        return source
    }

    @Test func moods_keepTheBestScoringSongsAndDropUnanalysedOnes() async throws {
        // s1…s10 score 0.1…1.0 for happy; s11 and s12 were never analysed.
        let scores = Dictionary(uniqueKeysWithValues: (1...10).map { ("s\($0)", AudioMuseMoodScores(values: ["happy": Double($0) / 10])) })
        let scorer = FakeMoodScorer(scores: scores)
        let service = QueueBuilderService(source: technoSource(12), library: FakeGenreLibrary(), moodScorer: scorer)

        let result = try await service.buildQueue(QueueBuilderSelection(mains: ["Electronic"], moods: [.happy]), count: 3)

        #expect(!result.ignoredMoods)
        #expect(Set(result.songs.map(\.id)) == ["s8", "s9", "s10"])
        #expect(scorer.askedCount == 12)
    }

    @Test func moods_unreachableAudioMuseStillBuildsWithoutThem() async throws {
        let scorer = FakeMoodScorer(failure: AudioMuseError.transport("down"))
        let service = QueueBuilderService(source: technoSource(6), library: FakeGenreLibrary(), moodScorer: scorer)

        let result = try await service.buildQueue(QueueBuilderSelection(moods: [.relaxed]), count: 4)

        #expect(result.ignoredMoods)
        #expect(result.songs.count == 4)
    }

    @Test func moods_withoutAScorerAreUnavailable() async throws {
        let service = QueueBuilderService(source: technoSource(3), library: FakeGenreLibrary())
        #expect(await service.isMoodAvailable() == false)
        let configured = QueueBuilderService(source: technoSource(3), library: FakeGenreLibrary(), moodScorer: FakeMoodScorer())
        #expect(await configured.isMoodAvailable())
    }

    @Test func noMoodPicked_neverAsksAudioMuse() async throws {
        let scorer = FakeMoodScorer()
        let service = QueueBuilderService(source: technoSource(5), library: FakeGenreLibrary(), moodScorer: scorer)
        _ = try await service.buildQueue(QueueBuilderSelection(), count: 5)
        #expect(scorer.askedCount == 0)
    }

    // MARK: AudioMuse genre fallback

    private func styles(_ labels: String...) -> AudioMuseMoodScores {
        AudioMuseMoodScores(values: [:], styles: labels.enumerated().map { .init(label: $1, score: 1 - Double($0) / 10) })
    }

    @Test func genreFallback_givesUntaggedTracksAMainGenreAndLeavesTaggedOnesAlone() async throws {
        let source = FakeQueueBuilderSource()
        source.set(stamp: "v1", tracks: [
            QueueBuilderTrack(song: song("joni"), genres: [], year: 1977),
            QueueBuilderTrack(song: song("odd"), genres: ["Norway"], year: 2015),
            QueueBuilderTrack(song: song("bbng"), genres: ["Jazz"], year: 2016),
        ])
        let scorer = FakeMoodScorer(scores: [
            "joni": styles("female vocalists", "jazz", "soul"),
            "odd": styles("60s", "rock"),
            "bbng": styles("electronic"),
        ])
        let service = QueueBuilderService(source: source, library: FakeGenreLibrary(), moodScorer: scorer)
        _ = try await service.index()

        #expect(await service.fillUntaggedGenres())
        let filled = try await service.index()

        // Only the two untagged/"Other" tracks were scored; BADBADNOTGOOD keeps its Jazz tag.
        #expect(scorer.askedCount == 2)
        #expect(filled.columns.first { $0.id == "Jazz" }?.songCount == 2)
        #expect(filled.columns.first { $0.id == "Rock" }?.songCount == 1)
        #expect(filled.columns.first { $0.id == "Electronic" } == nil)
        // No sub-genre is invented for the filled tracks.
        #expect(filled.columns.first { $0.id == "Jazz" }?.pills.isEmpty == true)
        let jazz = try await service.buildQueue(QueueBuilderSelection(mains: ["Jazz"]), count: 10).songs
        #expect(Set(jazz.map(\.id)) == ["joni", "bbng"])
    }

    @Test func genreFallback_runsOncePerSync() async throws {
        let source = FakeQueueBuilderSource()
        source.set(stamp: "v1", tracks: [QueueBuilderTrack(song: song("u"), genres: [], year: nil)])
        let scorer = FakeMoodScorer(scores: ["u": styles("jazz")])
        let service = QueueBuilderService(source: source, library: FakeGenreLibrary(), moodScorer: scorer)
        _ = try await service.index()

        #expect(await service.fillUntaggedGenres())
        #expect(await service.fillUntaggedGenres() == false)
        #expect(scorer.askedCount == 1)
    }

    @Test func genreFallback_withoutAudioMuseChangesNothing() async throws {
        let source = FakeQueueBuilderSource()
        source.set(stamp: "v1", tracks: [QueueBuilderTrack(song: song("u"), genres: [], year: nil)])
        let service = QueueBuilderService(source: source, library: FakeGenreLibrary())
        _ = try await service.index()
        #expect(await service.fillUntaggedGenres() == false)
        let unavailable = QueueBuilderService(
            source: source, library: FakeGenreLibrary(), moodScorer: FakeMoodScorer(available: false, scores: ["u": styles("jazz")])
        )
        _ = try await unavailable.index()
        #expect(await unavailable.fillUntaggedGenres() == false)
    }

    @Test func moodPool_scalesWithLengthWithinBounds() {
        #expect(QueueBuilderService.moodPoolSize(for: 15) == 120)
        #expect(QueueBuilderService.moodPoolSize(for: 50) == 200)
        #expect(QueueBuilderService.moodPoolSize(for: 120) == 400)
    }
}

// MARK: - Discover card and shared picks

@Suite("QueueBuilderViewModel", .serialized)
@MainActor
struct QueueBuilderViewModelTests {
    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "QueueBuilderViewModelTests.\(UUID())")!
    }

    private func model(defaults: UserDefaults, scope: String = "server-a") async -> QueueBuilderViewModel {
        let source = FakeQueueBuilderSource()
        source.set(stamp: "v1", tracks: [
            QueueBuilderTrack(song: song("m1"), genres: ["Modal"], year: 1959),
            QueueBuilderTrack(song: song("f1"), genres: ["Fusion"], year: 1975),
            QueueBuilderTrack(song: song("t1"), genres: ["Techno"], year: 1994),
            QueueBuilderTrack(song: song("h1"), genres: ["House"], year: 2001),
        ])
        let vm = QueueBuilderViewModel(
            service: QueueBuilderService(source: source, library: FakeGenreLibrary()),
            playerService: MockPlayerService(),
            toastService: ToastService(),
            defaults: defaults,
            storageScope: scope
        )
        await vm.load()
        return vm
    }

    private var modal: String { GenreTaxonomy.discogs.resolve("Modal").key }
    private var fusion: String { GenreTaxonomy.discogs.resolve("Fusion").key }

    @Test func cardMainTap_picksFocusesAndUnpicks() async {
        let vm = await model(defaults: defaults())

        vm.tapMainInCard("Jazz")
        #expect(vm.isSelected(main: "Jazz"))
        #expect(vm.focusedMain == "Jazz")

        // A second genre takes the sub-genre row; Jazz stays picked.
        vm.tapMainInCard("Electronic")
        #expect(vm.focusedMain == "Electronic")
        #expect(vm.isPicked(main: "Jazz"))

        // Tapping picked-but-unfocused Jazz only brings its row back.
        vm.tapMainInCard("Jazz")
        #expect(vm.focusedMain == "Jazz")
        #expect(vm.isPicked(main: "Jazz"))

        // Tapping focused Jazz unpicks it and closes the row.
        vm.tapMainInCard("Jazz")
        #expect(!vm.isPicked(main: "Jazz"))
        #expect(vm.focusedMain == nil)
        #expect(vm.isPicked(main: "Electronic"))
    }

    @Test func subGenreTap_narrowsAWholeGenreToThatSubGenre() async {
        let vm = await model(defaults: defaults())
        vm.tapMainInCard("Jazz")

        vm.toggle(pill: modal, in: "Jazz")
        #expect(vm.selection.mains.isEmpty)
        #expect(vm.selection.tags == [modal])
        #expect(vm.isPicked(main: "Jazz"))
        #expect(vm.matchCount == 1)

        vm.toggle(pill: fusion, in: "Jazz")
        #expect(vm.selection.tags == [modal, fusion])

        // Unpicking the focused genre clears its sub-genres too.
        vm.tapMainInCard("Jazz")
        #expect(vm.selection.tags.isEmpty)
    }

    @Test func reset_clearsPicksButKeepsTheLength() async {
        let vm = await model(defaults: defaults())
        vm.tapMainInCard("Jazz")
        vm.toggle(decade: 1950)
        vm.length = 80

        vm.reset()

        #expect(vm.selection.isEmpty)
        #expect(vm.focusedMain == nil)
        #expect(vm.length == 80)
        #expect(vm.summary == "Anything in your library")
    }

    @Test func picks_areRememberedPerServer() async {
        let store = defaults()
        let first = await model(defaults: store)
        first.tapMainInCard("Jazz")
        first.toggle(decade: 1970)
        first.length = 30

        let relaunched = await model(defaults: store)
        #expect(relaunched.selection.mains == ["Jazz"])
        #expect(relaunched.selection.decades == [1970])
        #expect(relaunched.length == 30)

        let otherServer = await model(defaults: store, scope: "server-b")
        #expect(otherServer.selection.isEmpty)
    }

    @Test func savedPicksThatNoLongerExist_areDropped() async throws {
        let store = defaults()
        let stale = QueueBuilderSelection(mains: ["Jazz", "Polka"], tags: ["nolongerthere"], decades: [1880, 1950], moods: [.happy])
        store.set(try JSONEncoder().encode(stale), forKey: "minidisc.queueBuilder.selection.server-a")

        let vm = await model(defaults: store)

        #expect(vm.selection.mains == ["Jazz"])
        #expect(vm.selection.tags.isEmpty)
        #expect(vm.selection.decades == [1950])
        // No AudioMuse configured here, so a saved mood is dropped too.
        #expect(vm.selection.moods.isEmpty)
    }

    @Test func decades_newestFirst() async {
        let vm = await model(defaults: defaults())
        #expect(vm.decades == [2000, 1990, 1970, 1950])
        vm.toggle(decade: 1950)
        vm.toggle(decade: 2000)
        #expect(vm.summary == "2000s and 1950s")
    }

    @Test func summary_listsPicksInColumnOrder() async {
        let vm = await model(defaults: defaults())
        vm.tapMainInCard("Electronic")
        vm.tapMainInCard("Jazz")
        vm.toggle(pill: modal, in: "Jazz")
        vm.toggle(decade: 1950)
        #expect(vm.summary.contains("Electronic"))
        #expect(vm.summary.contains("Modal"))
        #expect(vm.summary.contains("1950s"))
    }
}
