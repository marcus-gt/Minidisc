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

/// Records which artists were fetched and the peak number of requests in flight.
private actor FanOutRecorder {
    private(set) var fetched: [String] = []
    private(set) var peakInFlight = 0
    private var inFlight = 0

    func begin(_ artist: String) {
        fetched.append(artist)
        inFlight += 1
        peakInFlight = max(peakInFlight, inFlight)
    }

    func end() { inFlight -= 1 }
}

private enum FanOutTestError: Error { case unreachable }

@Suite("Instant Mix fan-out (#8)")
struct InstantMixFanOutTests {
    private func song(_ id: String, artist: String) throws -> Song {
        try JSONDecoder().decode(Song.self, from: Data(
            "{\"id\":\"\(id)\",\"title\":\"\(id)\",\"isDir\":false,\"artist\":\"\(artist)\",\"artistId\":\"\(artist)\"}".utf8
        ))
    }

    private let artists = ["a1", "a2", "a3", "a4", "a5", "a6", "a7", "a8"]

    @Test func emptyProbe_skipsTheRemainingArtistsAndReportsNothingFound() async throws {
        let recorder = FanOutRecorder()
        let result = try await LibraryService.runInstantMixFanOut(artists: artists, maxInFlight: 3, probeCount: 3) { artist in
            await recorder.begin(artist)
            await recorder.end()
            return []
        }

        #expect(result.probeFoundNothing)
        #expect(result.songs.isEmpty)
        #expect(Set(await recorder.fetched) == ["a1", "a2", "a3"])
    }

    @Test func productiveProbe_fetchesEveryArtist() async throws {
        let recorder = FanOutRecorder()
        let hit = try song("s1", artist: "a2")
        let result = try await LibraryService.runInstantMixFanOut(artists: artists, maxInFlight: 3, probeCount: 3) { artist in
            await recorder.begin(artist)
            await recorder.end()
            return artist == "a2" ? [hit] : []
        }

        #expect(!result.probeFoundNothing)
        #expect(result.songs.map(\.id) == ["s1"])
        #expect(Set(await recorder.fetched) == Set(artists))
        #expect(result.callMs.count == artists.count)
    }

    @Test func failedProbe_stopsButDoesNotReportTheServerAsEmpty() async throws {
        let recorder = FanOutRecorder()
        let result = try await LibraryService.runInstantMixFanOut(artists: artists, maxInFlight: 3, probeCount: 3) { artist in
            await recorder.begin(artist)
            await recorder.end()
            if artist == "a1" { throw FanOutTestError.unreachable }
            return []
        }

        #expect(!result.probeFoundNothing)
        #expect(result.songs.isEmpty)
        #expect(await recorder.fetched.count == 3)
    }

    @Test func neverRunsMoreThanMaxInFlight() async throws {
        let recorder = FanOutRecorder()
        let hit = try song("s1", artist: "a1")
        _ = try await LibraryService.runInstantMixFanOut(artists: artists, maxInFlight: 3, probeCount: 3) { artist in
            await recorder.begin(artist)
            for _ in 0..<5 { await Task.yield() }
            await recorder.end()
            return [hit]
        }

        #expect(await recorder.peakInFlight <= 3)
        #expect(await recorder.fetched.count == artists.count)
    }

    @Test func noArtists_makesNoRequests() async throws {
        let result = try await LibraryService.runInstantMixFanOut(artists: [], maxInFlight: 3, probeCount: 3) { _ in
            Issue.record("No request expected")
            return []
        }

        #expect(!result.probeFoundNothing)
        #expect(result.callMs.isEmpty)
    }

    @Test func cancellation_propagates() async throws {
        let task = Task {
            try await LibraryService.runInstantMixFanOut(artists: ["a1", "a2", "a3", "a4"], maxInFlight: 3, probeCount: 3) { _ in
                throw CancellationError()
            }
        }
        await #expect(throws: CancellationError.self) { _ = try await task.value }
    }
}
