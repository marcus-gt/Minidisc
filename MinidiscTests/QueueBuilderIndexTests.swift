import Foundation
import SwiftSonic
import Testing
@testable import Minidisc

@Suite("QueueBuilderIndex")
struct QueueBuilderIndexTests {
    private func track(_ id: String, _ genres: [String], year: Int? = nil) throws -> QueueBuilderTrack {
        let song = try JSONDecoder().decode(Song.self, from: Data(
            "{\"id\":\"\(id)\",\"title\":\"\(id)\",\"isDir\":false}".utf8
        ))
        return QueueBuilderTrack(song: song, genres: genres, year: year)
    }

    private func index(_ tracks: [QueueBuilderTrack]) -> QueueBuilderIndex {
        QueueBuilderIndex(tracks: tracks, taxonomy: .discogs)
    }

    private func column(_ name: String, in index: QueueBuilderIndex) -> QueueBuilderIndex.Column? {
        index.columns.first { $0.id == name }
    }

    @Test func songWithTagsInTwoMains_isACandidateForBoth() throws {
        let idx = index([try track("a", ["Fusion", "Alternative Rock"]), try track("b", ["Techno"])])
        let fusion = GenreTaxonomy.discogs.resolve("Fusion").key
        let altRock = GenreTaxonomy.discogs.resolve("Alternative Rock").key

        #expect(idx.matchingSongs(QueueBuilderSelection(mains: ["Jazz"])).map(\.id) == ["a"])
        #expect(idx.matchingSongs(QueueBuilderSelection(mains: ["Rock"])).map(\.id) == ["a"])
        #expect(idx.matchingSongs(QueueBuilderSelection(tags: [fusion])).map(\.id) == ["a"])
        #expect(idx.matchingSongs(QueueBuilderSelection(tags: [altRock])).map(\.id) == ["a"])
    }

    @Test func songWithTwoTagsOfOneMain_showsUnderBothPillsButCountsOnceForTheMain() throws {
        let idx = index([try track("a", ["Modal", "Fusion"]), try track("b", ["Fusion"])])
        let jazz = try #require(column("Jazz", in: idx))

        #expect(jazz.songCount == 2)
        #expect(jazz.pills.first { $0.name == "Fusion" }?.songCount == 2)
        #expect(jazz.pills.first { $0.name == "Modal" }?.songCount == 1)
        let modal = GenreTaxonomy.discogs.resolve("Modal").key
        let fusion = GenreTaxonomy.discogs.resolve("Fusion").key
        // Picking both pills still queues each song once.
        #expect(idx.matchingSongs(QueueBuilderSelection(tags: [modal, fusion])).map(\.id) == ["a", "b"])
    }

    @Test func variants_mergeIntoOnePillWithTheirCombinedCount() throws {
        let idx = index([try track("a", ["Modal Jazz"]), try track("b", ["Modal"]), try track("c", ["modal jazz"])])
        let jazz = try #require(column("Jazz", in: idx))
        #expect(jazz.pills.map(\.name) == ["Modal"])
        #expect(jazz.pills.first?.songCount == 3)
    }

    @Test func mainGenreTag_countsForTheColumnWithoutItsOwnPill() throws {
        let idx = index([try track("a", ["Jazz"]), try track("b", ["Modal"])])
        let jazz = try #require(column("Jazz", in: idx))
        #expect(jazz.songCount == 2)
        #expect(jazz.pills.map(\.name) == ["Modal"])
    }

    @Test func columns_biggestFirstAndOtherLast() throws {
        let idx = index([
            try track("a", ["Techno"]), try track("b", ["House"]), try track("c", ["Modal"]), try track("d", ["Norway"]),
        ])
        #expect(idx.columns.map(\.id) == ["Electronic", "Jazz", GenreTaxonomy.otherGenre])
    }

    @Test func decades_filterByYearAndCombineWithGenre() throws {
        let idx = index([
            try track("a", ["Modal"], year: 1959), try track("b", ["Modal"], year: 1972),
            try track("c", ["Techno"], year: 1992), try track("d", ["Modal"], year: nil),
        ])
        #expect(idx.decadeCounts == [1950: 1, 1970: 1, 1990: 1])
        #expect(idx.matchingSongs(QueueBuilderSelection(decades: [1950, 1990])).map(\.id) == ["a", "c"])
        #expect(idx.matchingSongs(QueueBuilderSelection(mains: ["Jazz"], decades: [1970])).map(\.id) == ["b"])
    }

    @Test func emptySelection_matchesEverything() throws {
        let idx = index([try track("a", ["Modal"]), try track("b", [])])
        #expect(idx.matchCount(QueueBuilderSelection()) == 2)
    }

    @Test func build_respectsCountAndSkipsQueuedSongs() throws {
        let idx = index(try (1...20).map { try track("s\($0)", ["Techno"]) })
        let queue = idx.build(QueueBuilderSelection(mains: ["Electronic"]), count: 5, excluding: ["s1", "s2"])
        #expect(queue.count == 5)
        #expect(Set(queue.map(\.id)).count == 5)
        #expect(!queue.contains { $0.id == "s1" || $0.id == "s2" })
    }
}
