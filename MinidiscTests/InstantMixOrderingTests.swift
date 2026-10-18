import Foundation
import SwiftSonic
import Testing
@testable import Minidisc

@Suite("Instant Mix ordering")
struct InstantMixOrderingTests {
    private func song(_ id: String, artist: String) throws -> Song {
        try JSONDecoder().decode(Song.self, from: Data(
            "{\"id\":\"\(id)\",\"title\":\"\(id)\",\"isDir\":false,\"artist\":\"\(artist)\",\"artistId\":\"\(artist)\"}".utf8
        ))
    }

    @Test func songSeed_keepsServerRankingAheadOfFanOut() throws {
        let base = [try song("b1", artist: "A"), try song("b2", artist: "B"), try song("b3", artist: "C")]
        let fanOut = [try song("f1", artist: "X"), try song("f2", artist: "Y")]

        let mix = LibraryService.orderInstantMix(seed: .song(id: "seed"), base: base, expansions: fanOut, maxPerArtist: 4)

        #expect(mix.map(\.id) == ["b1", "b2", "b3", "f1", "f2"])
    }

    @Test func songSeed_capsArtistsAcrossBaseAndFanOut() throws {
        let base = [try song("b1", artist: "A"), try song("b2", artist: "A"), try song("b3", artist: "B")]
        let fanOut = [try song("f1", artist: "A"), try song("f2", artist: "C")]

        let mix = LibraryService.orderInstantMix(seed: .song(id: "seed"), base: base, expansions: fanOut, maxPerArtist: 2)

        // A already used its quota in the ranked list, so its fan-out song is dropped.
        #expect(mix.map(\.id) == ["b1", "b2", "b3", "f2"])
    }

    @Test func songSeed_dropsFanOutDuplicatesOfBaseSongs() throws {
        let base = [try song("b1", artist: "A")]
        let fanOut = [try song("b1", artist: "A"), try song("f1", artist: "B")]

        let mix = LibraryService.orderInstantMix(seed: .song(id: "seed"), base: base, expansions: fanOut, maxPerArtist: 4)

        #expect(mix.map(\.id) == ["b1", "f1"])
    }

    @Test func artistSeed_stillRoundRobinsAcrossArtists() throws {
        let base = [try song("a1", artist: "A"), try song("a2", artist: "A"), try song("b1", artist: "B")]

        let mix = LibraryService.orderInstantMix(seed: .artist(id: "A"), base: base, expansions: [], maxPerArtist: 4)

        #expect(mix.map(\.id) == ["a1", "b1", "a2"])
    }

    @Test func endlessExtensionMixCount_growsWithQueuedSongsAndIsBounded() {
        #expect(LibraryService.endlessExtensionMixCount(targetSize: 50, excludedCount: 0) == 50)
        #expect(LibraryService.endlessExtensionMixCount(targetSize: 50, excludedCount: 121) == 171)
        #expect(LibraryService.endlessExtensionMixCount(targetSize: 50, excludedCount: 2_000) == 500)
    }
}
