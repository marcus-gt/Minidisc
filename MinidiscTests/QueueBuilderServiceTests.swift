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

    @Test func moodPool_scalesWithLengthWithinBounds() {
        #expect(QueueBuilderService.moodPoolSize(for: 15) == 120)
        #expect(QueueBuilderService.moodPoolSize(for: 50) == 200)
        #expect(QueueBuilderService.moodPoolSize(for: 120) == 400)
    }
}
