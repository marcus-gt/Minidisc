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
        #expect(Set(result.emptyArtists) == Set(artists).subtracting(["a2"]))
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

@Suite("Instant Mix fan-out memory (#8)")
struct InstantMixFanOutMemoryTests {
    @Test func oneEmptyProbe_keepsTheFanOutButSkipsThoseArtists() {
        var memory = InstantMixFanOutMemory()
        memory.record(emptyArtists: ["a1", "a2", "a3"], probeFoundNothing: true, productive: false)

        #expect(!memory.isDisabled)
        #expect(memory.candidates(["a1", "a4", "a2", "a5"]) == ["a4", "a5"])
    }

    @Test func twoEmptyProbesInARow_disableTheFanOut() {
        var memory = InstantMixFanOutMemory()
        memory.record(emptyArtists: ["a1"], probeFoundNothing: true, productive: false)
        memory.record(emptyArtists: ["b1"], probeFoundNothing: true, productive: false)

        #expect(memory.isDisabled)
        #expect(memory.candidates(["c1", "c2"]).isEmpty)
    }

    @Test func aProductiveMix_resetsTheCount() {
        var memory = InstantMixFanOutMemory()
        memory.record(emptyArtists: ["a1"], probeFoundNothing: true, productive: false)
        memory.record(emptyArtists: ["b1"], probeFoundNothing: false, productive: true)
        memory.record(emptyArtists: ["c1"], probeFoundNothing: true, productive: false)

        #expect(!memory.isDisabled)
        #expect(memory.candidates(["a1", "b1", "c1", "d1"]) == ["d1"])
    }

    @Test func aFailedProbe_leavesTheCountUnchanged() {
        var memory = InstantMixFanOutMemory()
        memory.record(emptyArtists: [], probeFoundNothing: true, productive: false)
        memory.record(emptyArtists: [], probeFoundNothing: false, productive: false)

        #expect(memory.consecutiveEmptyProbes == 1)
        #expect(!memory.isDisabled)
    }
}

// MARK: - Fallback without server similarity (#43)

@Suite("Instant Mix fallback")
struct InstantMixFallbackTests {
    private func song(_ id: String, artist: String, genre: String? = "Jazz") -> DisplayableSong {
        DisplayableSong(
            id: id, title: id, artist: artist, albumId: nil, albumName: nil, artistId: artist,
            genre: genre, duration: 200, trackNumber: nil, isDownloaded: false, coverArtId: nil,
            audioFormat: nil, replayGainTrackGain: nil, replayGainTrackPeak: nil, replayGainAlbumGain: nil,
            replayGainAlbumPeak: nil, replayGainBaseGain: nil, replayGainFallbackGain: nil
        )
    }

    @Test func mixesTheSeedArtistIntoItsGenre() {
        let own = (0..<20).map { song("own\($0)", artist: "seed") }
        let genre = (0..<40).map { song("g\($0)", artist: "a\($0 % 10)") }
        let mix = LibraryService.fallbackMix(artistSongs: own, genreSongs: genre, excluding: [], count: 20, maxPerArtist: 4)

        #expect(mix.count == 20)
        #expect(mix.filter { $0.artistId == "seed" }.count == 5)
        #expect(Set(mix.map(\.id)).count == 20)
        // The seed artist recurs through the mix instead of filling the start.
        #expect(mix.first?.artistId == "seed")
        #expect(mix.prefix(4).filter { $0.artistId == "seed" }.count == 1)
    }

    @Test func capsEachOtherArtist() {
        let genre = (0..<30).map { song("g\($0)", artist: $0 < 20 ? "prolific" : "other\($0)") }
        let mix = LibraryService.fallbackMix(artistSongs: [], genreSongs: genre, excluding: [], count: 30, maxPerArtist: 4)
        #expect(mix.filter { $0.artistId == "prolific" }.count == 4)
    }

    @Test func noGenre_playsTheArtistAlone() {
        let own = (0..<12).map { song("own\($0)", artist: "seed") }
        let mix = LibraryService.fallbackMix(artistSongs: own, genreSongs: [], excluding: [], count: 10, maxPerArtist: 4)
        #expect(mix.count == 10)
        #expect(mix.allSatisfy { $0.artistId == "seed" })
    }

    /// A song seed already plays first, so it is never repeated inside the mix.
    @Test func leavesOutTheSeedSong() {
        let own = [song("seedSong", artist: "seed"), song("other", artist: "seed")]
        let mix = LibraryService.fallbackMix(artistSongs: own, genreSongs: [], excluding: ["seedSong"], count: 10, maxPerArtist: 4)
        #expect(mix.map(\.id) == ["other"])
    }

    @Test func dominantGenre_isTheMostCommonTag() {
        let songs = [song("1", artist: "x", genre: "Jazz"), song("2", artist: "x", genre: "Soul"),
                     song("3", artist: "x", genre: "Jazz"), song("4", artist: "x", genre: nil)]
        #expect(LibraryService.dominantGenre(of: songs) == "Jazz")
        #expect(LibraryService.dominantGenre(of: []) == nil)
    }
}
