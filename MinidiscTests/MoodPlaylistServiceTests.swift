import Testing
import Foundation
import SwiftSonic
@testable import Minidisc

// Moods play as radios (#60). The service only removes the playlists earlier versions created;
// MoodRadioService builds the radios and RadioQueue keeps them going.

// MARK: - Stubs

private final class ProviderStub: MoodTrackProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var _requested: [Mood] = []
    private var _prepares = 0
    var matches: [String] = []
    var fails = false
    var kind: MoodSourceKind = .sonic

    var requested: [Mood] { lock.withLock { _requested } }
    var prepares: Int { lock.withLock { _prepares } }

    func prepare() async { lock.withLock { _prepares += 1 } }

    func trackIds(for mood: Mood, limit: Int) async throws -> [String] {
        lock.withLock { _requested.append(mood) }
        if fails { throw AudioMuseError.transport("stubbed failure") }
        return Array(matches.prefix(limit))
    }
}

private final class PlaylistStub: MoodPlaylistClient, @unchecked Sendable {
    var existing: [Playlist] = []
    var failReads = false
    var failDeletes: Set<String> = []
    private(set) var deleted: [String] = []

    func getPlaylists(username: String?) async throws -> [Playlist] {
        if failReads { throw URLError(.notConnectedToInternet) }
        return existing
    }

    func deletePlaylist(id: String) async throws {
        if failDeletes.contains(id) { throw URLError(.cannotConnectToHost) }
        deleted.append(id)
        existing.removeAll { $0.id == id }
    }

    func renamePlaylist(id: String, to name: String) async throws {}

    func createPlaylist(name: String?, playlistId: String?, songIds: [String]) async throws -> PlaylistWithSongs {
        Issue.record("Moods no longer write playlists")
        throw URLError(.badServerResponse)
    }
}

private final class SimilarSongsStub: PlaybackQueueBuilding, @unchecked Sendable {
    private let lock = NSLock()
    private var _seeds: [String] = []
    var similar: [DisplayableSong] = []
    var seeds: [String] { lock.withLock { _seeds } }

    func smartShuffleQueue(targetSize: Int) async throws -> [DisplayableSong] { [] }
    func similarBackfillQueue(targetSize: Int, excludedIds: Set<String>) async throws -> [DisplayableSong] { [] }
    func endlessExtension(seedTrackId: String?, targetSize: Int, excludedIds: Set<String>) async throws -> [DisplayableSong] { [] }
    func instantMix(from seed: InstantMixSeed, count: Int) async throws -> [DisplayableSong] {
        if case .song(let id) = seed { lock.withLock { _seeds.append(id) } }
        return similar
    }
}

private func song(_ id: String) -> DisplayableSong {
    DisplayableSong(from: Song(id: id, title: id, artist: "Artist", duration: 200))
}

private func playlist(_ id: String, _ name: String, owner: String) -> Playlist {
    Playlist(id: id, name: name, songCount: 4, duration: 100, owner: owner)
}

// MARK: - Old playlists

@Suite("Mood playlists — removing the old ones")
struct MoodPlaylistServiceTests {
    private let serverId = "server"

    @Test("Deletion removes the user's current and pre-rebrand mood playlists, and nothing else")
    func deletionTargetsOnlyOwnedMoods() async {
        let playlists = PlaylistStub()
        let service = MoodPlaylistService(playlistClientFactory: { playlists }, playlistOwner: "me")
        playlists.existing = [
            playlist("night", Mood.night.playlistName, owner: "me"),
            playlist("duplicate-night", Mood.night.playlistName, owner: "me"),
            playlist("legacy-chill", Mood.chill.legacyPlaylistName, owner: "me"),
            playlist("shared-night", Mood.night.playlistName, owner: "someone-else"),
            playlist("wrapped", "Minidisc Wrapped 2025", owner: "me"),
            playlist("custom", "Minidisc · My favourites", owner: "me")
        ]
        #expect(await service.deletePlaylists(serverId: serverId) == .finished(deleted: 3, failed: 0))
        #expect(Set(playlists.deleted) == ["night", "duplicate-night", "legacy-chill"])
    }

    @Test("Failed deletions are counted, and a second attempt finishes the job")
    func partialDeletionCanBeRetried() async {
        let playlists = PlaylistStub()
        let service = MoodPlaylistService(playlistClientFactory: { playlists }, playlistOwner: "me")
        playlists.existing = Mood.allCases.map { playlist($0.rawValue, $0.playlistName, owner: "me") }
        playlists.failDeletes = ["night"]
        #expect(await service.deletePlaylists(serverId: serverId) == .finished(deleted: 4, failed: 1))
        playlists.failDeletes = []
        #expect(await service.deletePlaylists(serverId: serverId) == .finished(deleted: 1, failed: 0))
        #expect(await service.deletePlaylists(serverId: serverId) == .finished(deleted: 0, failed: 0))
    }

    @Test("An unreachable server is a failure, not a success")
    func offlineDeletionFails() async {
        let playlists = PlaylistStub()
        playlists.failReads = true
        let service = MoodPlaylistService(playlistClientFactory: { playlists }, playlistOwner: "me")
        #expect(await service.deletePlaylists(serverId: serverId) == .failed)
        #expect(playlists.deleted.isEmpty)
    }

    @Test("every mood carries a distinct English prompt for the sonic provider")
    func promptsAreDistinct() {
        let queries = Mood.allCases.map(\.query)
        #expect(Set(queries).count == queries.count)
        #expect(queries.allSatisfy { $0.allSatisfy(\.isASCII) })
    }

    @Test func names_currentAndLegacy_areRecognised() {
        #expect(Mood.night.playlistName == "maekster · Night")
        #expect(Mood.night.legacyPlaylistName == "Minidisc · Night")
        #expect(Mood.forPlaylistName("maekster · Night") == .night)
        #expect(Mood.forPlaylistName("Minidisc · Night") == .night)
        #expect(Mood.forPlaylistName("Minidisc · My favourites") == nil)
        #expect(Mood.forPlaylistName("Night") == nil)
        #expect(MusicIntentService.matchesPlaylist("Minidisc · Night", term: "night"))
    }
}

// MARK: - Radio

@Suite("Mood radio (#60)")
struct MoodRadioServiceTests {
    private func service(_ provider: ProviderStub?, indexed: Set<String>? = nil) -> MoodRadioService {
        MoodRadioService(
            providerFactory: { provider },
            songsByID: { ids in ids.filter { indexed?.contains($0) ?? true }.map { Song(id: $0, title: $0, duration: 200) } }
        )
    }

    @Test("A radio holds the mood's matches, warms the source up first and seeds from the best")
    func radioHoldsTheMatches() async throws {
        let provider = ProviderStub()
        provider.matches = (0..<30).map { "m\($0)" }
        let radio = try await service(provider).radio(for: .chill)
        #expect(provider.requested == [.chill])
        #expect(provider.prepares == 1)
        #expect(Set(radio.tracks.map(\.id)) == Set(provider.matches))
        #expect(radio.seedIDs == Array(provider.matches.prefix(MoodRadioService.seedCount)))
    }

    @Test("Songs the library index doesn't know are left out, seeds included")
    func unknownSongsAreSkipped() async throws {
        let provider = ProviderStub()
        provider.matches = ["a", "missing", "b"]
        let radio = try await service(provider, indexed: ["a", "b"]).radio(for: .focus)
        #expect(Set(radio.tracks.map(\.id)) == ["a", "b"])
        #expect(radio.seedIDs == ["a", "b"])
    }

    @Test("No source means an empty radio; a failing source throws")
    func emptyAndFailing() async throws {
        #expect(try await service(nil).radio(for: .night).tracks.isEmpty)
        let failing = ProviderStub()
        failing.fails = true
        await #expect(throws: AudioMuseError.self) { try await service(failing).radio(for: .night) }
    }

    /// The best match leads far more often than the last, yet the radio differs between starts.
    @Test("The order favours the best matches without being fixed")
    func orderFavoursTheBest() {
        var generator = SystemRandomNumberGenerator()
        let matches = (0..<50).map { "m\($0)" }
        var bestFirst = 0, worstFirst = 0
        var orders = Set<[String]>()
        for _ in 0..<500 {
            let order = MoodRadioService.order(matches, using: &generator)
            #expect(Set(order) == Set(matches))
            if order.first == "m0" { bestFirst += 1 }
            if order.first == "m49" { worstFirst += 1 }
            orders.insert(order)
        }
        #expect(bestFirst > worstFirst)
        #expect(orders.count > 1)
    }
}

// MARK: - Keeping a radio going

@Suite("Radio queue (#60, #69)")
struct RadioQueueTests {
    @Test("The rest of the picks come first, skipping what's queued; then similar songs around the seeds")
    func refillUsesPicksThenSimilarSongs() async throws {
        let picks = (0..<(RadioQueue.initialCount + 3)).map { song("p\($0)") }
        let library = SimilarSongsStub()
        library.similar = [song("queued"), song("similar")]
        let refill = RadioQueue.refill(after: picks, seedIDs: ["seed"], library: library)

        #expect(RadioQueue.initialTracks(picks).count == RadioQueue.initialCount)
        let queued = Set(picks.prefix(RadioQueue.initialCount).map(\.id) + ["p50"])
        #expect(try await refill(queued, 10).map(\.id) == ["p51", "p52"])
        #expect(library.seeds.isEmpty)

        let all = Set(picks.map(\.id) + ["queued"])
        #expect(try await refill(all, 10).map(\.id) == ["similar"])
        #expect(library.seeds == ["seed"])
    }
}
