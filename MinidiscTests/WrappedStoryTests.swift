import Foundation
import Testing
@testable import Minidisc

@Suite("Wrapped story soundtrack (#75)")
@MainActor
struct WrappedStoryTests {
    private let calendar = Calendar(identifier: .gregorian)

    private func play(_ track: String, artist: String, album: String, genre: String? = nil, times: Int) -> [WrappedPlay] {
        (0..<times).map { index in
            WrappedPlay(timestamp: Date(timeIntervalSince1970: 1_780_000_000 + Double(index) * 3_600), trackId: track,
                        trackTitle: track, albumId: album, albumTitle: album, artistId: artist, artistName: artist,
                        genre: genre, durationListened: 200, trackDuration: 200)
        }
    }

    private func data(_ plays: [WrappedPlay]) -> WrappedData {
        WrappedAggregator.aggregate(plays: plays, period: .year(2026), serverId: "s",
                                    periodRange: WrappedPeriod.year(2026).dateRange(in: calendar), calendar: calendar)
    }

    /// Each slide gets the song that fits it; the rest get the next top songs, without repeats.
    @Test func soundtrack_matchesEachSlide() {
        // Artist b leads on listening time (13 plays) though "anthem" (a) is the most played song,
        // which also puts its album "x" first among the albums.
        let plays = play("anthem", artist: "a", album: "x", genre: "Jazz", times: 10)
            + play("artistHit", artist: "b", album: "y", genre: "Pop", times: 6)
            + play("albumCut", artist: "b", album: "w", genre: "Pop", times: 7)
            + play("other1", artist: "c", album: "z", genre: "Pop", times: 2)
            + play("other2", artist: "c", album: "z", genre: "Pop", times: 1)
        let recap = data(plays)
        #expect(recap.topArtists.first?.artistId == "b")
        #expect(recap.topAlbums.first?.albumId == "x")
        let picks = WrappedDataSource.soundtrack(plays: plays, data: recap)
        #expect(picks[.topTrack] == "anthem")
        #expect(picks[.closing] == "anthem")
        #expect(picks[.topArtist] == "albumCut")
        #expect(picks[.topAlbum] == "anthem")
        #expect(picks[.topGenre] == WrappedAggregator.topTracks(from: plays.filter { $0.genre == recap.dominantGenre }, limit: 1).first?.trackId)
        let used = Set([picks[.topTrack], picks[.topArtist], picks[.topAlbum], picks[.topGenre]].compactMap { $0 })
        let others = [picks[.intro], picks[.minutes], picks[.discoveries]].compactMap { $0 }
        #expect(others.count == 3)
        #expect(others.filter { $0 != "anthem" }.allSatisfy { !used.contains($0) })
    }

    /// Songs outside the library can't play, so they never make the soundtrack.
    @Test func soundtrack_usesLibraryTracksOnly() {
        let plays = play("lb:track:elsewhere", artist: "a", album: "x", times: 20) + play("library", artist: "a", album: "x", times: 1)
        let picks = WrappedDataSource.soundtrack(plays: plays, data: data(plays))
        #expect(picks[.topTrack] == "library")
        #expect(!picks.values.contains { !WrappedIDs.isLibraryID($0) })
    }

    @Test func soundtrack_isEmptyWithoutLibraryPlays() {
        let plays = play("lb:track:elsewhere", artist: "a", album: "x", times: 3)
        #expect(WrappedDataSource.soundtrack(plays: plays, data: data(plays)).isEmpty)
    }

    /// With few songs the extra slides repeat the #1 rather than going silent.
    @Test func soundtrack_fallsBackToTheTopSong() {
        let plays = play("only", artist: "a", album: "x", times: 3)
        let picks = WrappedDataSource.soundtrack(plays: plays, data: data(plays))
        #expect(picks[.intro] == "only" && picks[.minutes] == "only" && picks[.discoveries] == "only")
    }

    // MARK: Genres

    /// Ranked by listening time like the dominant genre, so the slide's #1 is always the recap's.
    @Test func topGenres_rankByTimeWithSharesAndAlbums() {
        let plays = play("a", artist: "x", album: "jazz1", genre: "Jazz", times: 5)
            + play("b", artist: "x", album: "jazz2", genre: "Jazz", times: 1)
            + play("c", artist: "y", album: "rock1", genre: "Rock", times: 3)
            + play("d", artist: "z", album: "lb:album:elsewhere", genre: "Soul", times: 2)
            + play("e", artist: "z", album: "untagged", genre: nil, times: 9)
        let genres = WrappedAggregator.topGenres(from: plays, limit: 5)
        #expect(genres.map(\.name) == ["Jazz", "Rock", "Soul"])
        #expect(genres.first?.name == data(plays).dominantGenre)
        #expect(abs((genres.first?.share ?? 0) - 6.0 / 11.0) < 0.0001)
        #expect(genres.first?.albumIDs == ["jazz1", "jazz2"])
        // Albums outside the library can't be drawn.
        #expect(genres.last?.albumIDs.isEmpty == true)
    }

    @Test func topGenres_keepsTheLimit() {
        let plays = (0..<8).flatMap { play("t\($0)", artist: "a", album: "al", genre: "G\($0)", times: $0 + 1) }
        let genres = WrappedAggregator.topGenres(from: plays, limit: 5)
        #expect(genres.count == 5)
        #expect(genres.map(\.rank) == [1, 2, 3, 4, 5])
        #expect(genres.first?.name == "G7")
    }
}
