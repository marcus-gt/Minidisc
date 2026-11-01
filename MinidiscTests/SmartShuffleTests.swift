import Foundation
import SwiftSonic
import Testing
@testable import Minidisc

@Suite("Smart Shuffle blend (#66)")
struct SmartShuffleTests {
    private func songs(_ prefix: String, _ count: Int, artists: Int? = nil) -> [DisplayableSong] {
        (0..<count).map { index in
            let artist = "\(prefix)-artist\(index % (artists ?? count))"
            return DisplayableSong(from: Song(id: "\(prefix)\(index)", title: "t", artist: artist, duration: 200, artistId: artist))
        }
    }

    private func blend(_ sources: [[DisplayableSong]], excluded: Set<String> = [], target: Int, maxPerArtist: Int = 3) -> [DisplayableSong] {
        var generator = SystemRandomNumberGenerator()
        return LibraryService.blendSmartShuffle(sources: sources, excludedIds: excluded, targetSize: target,
                                                maxPerArtist: maxPerArtist, using: &generator)
    }

    /// Favourites, recent taste and rediscovery take turns, so each gets about a third.
    @Test func sources_takeTurns() {
        let queue = blend([songs("fav", 20), songs("recent", 20), songs("random", 20)], target: 9)
        #expect(queue.count == 9)
        let prefixes = queue.map { String($0.id.prefix { $0.isLetter }) }
        #expect(prefixes == ["fav", "recent", "random", "fav", "recent", "random", "fav", "recent", "random"])
    }

    @Test func recentPlays_areSkipped() {
        let favorites = songs("fav", 5)
        let queue = blend([favorites, songs("random", 10)], excluded: ["fav0", "fav1"], target: 15)
        #expect(!queue.contains { $0.id == "fav0" || $0.id == "fav1" })
        #expect(Set(queue.map(\.id)).count == queue.count)
    }

    @Test func noArtist_getsMoreThanItsShare() {
        // One artist with 20 songs and nothing else to draw from.
        let queue = blend([songs("one", 20, artists: 1)], target: 20, maxPerArtist: 3)
        #expect(queue.count == 3)
    }

    /// A new listener has no favourites or history; random songs fill the whole queue.
    @Test func emptySources_leaveTheirTurnsToTheOthers() {
        let queue = blend([[], [], songs("random", 30)], target: 12)
        #expect(queue.count == 12)
        #expect(queue.allSatisfy { $0.id.hasPrefix("random") })
    }

    /// In a tiny library everything may have been played lately; better to repeat than to play nothing.
    @Test func everythingRecent_stillPlaysSomething() {
        let library = songs("small", 4)
        let queue = blend([library], excluded: Set(library.map(\.id)), target: 10)
        #expect(queue.count == 4)
    }

    @Test func nothingAtAll_isEmpty() {
        #expect(blend([[], [], []], target: 10).isEmpty)
    }
}
