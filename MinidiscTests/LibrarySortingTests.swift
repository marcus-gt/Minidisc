import Foundation
import SwiftSonic
import Testing
@testable import Minidisc

@Suite("Library sorting (#43)")
struct LibrarySortingTests {
    private func album(_ id: String, _ name: String, artist: String? = nil, played: Date? = nil) -> AlbumID3 {
        AlbumID3(id: id, name: name, songCount: 1, duration: 1, artistId: artist, played: played)
    }

    private func song(_ id: String, played: TimeInterval?) throws -> Song {
        var json: [String: Any] = ["id": id, "title": id, "isDir": false]
        if let played { json["played"] = ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: played)) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Song.self, from: JSONSerialization.data(withJSONObject: json))
    }

    @Test func recentlyPlayedOrder_ranksArtistsByTheirLatestAlbum() {
        let order = RecentlyPlayedOrder(recentlyPlayedAlbums: [
            album("a2", "B", artist: "x"), album("a1", "A", artist: "y"), album("a3", "C", artist: "x")
        ])
        #expect(order.albumIDs == ["a2", "a1", "a3"])
        #expect(order.artistIDs == ["x", "y"])
    }

    /// The server's recently-played list leads; the rest follow by their own last-played date, then name.
    @Test func albums_recentlyPlayed_followTheServerThenTheirDates() {
        let order = RecentlyPlayedOrder(recentlyPlayedAlbums: [album("c", "C"), album("a", "A")])
        let albums = [album("a", "A"), album("b", "B", played: Date(timeIntervalSince1970: 100)),
                      album("c", "C"), album("d", "D"), album("e", "E", played: Date(timeIntervalSince1970: 200))]
        let sorted = AlbumSort.recentlyPlayed.sorted(albums, recentlyPlayed: order)
        #expect(sorted.map(\.id) == ["c", "a", "e", "b", "d"])
    }

    @Test func artists_recentlyPlayed_followTheirAlbumsThenName() {
        let order = RecentlyPlayedOrder(recentlyPlayedAlbums: [album("1", "One", artist: "z"), album("2", "Two", artist: "b")])
        let artists = [ArtistID3(id: "a", name: "Abba"), ArtistID3(id: "b", name: "Bowie"), ArtistID3(id: "z", name: "Zappa"),
                       ArtistID3(id: "c", name: "Cream")]
        #expect(ArtistSort.recentlyPlayed.sorted(artists, recentlyPlayed: order).map(\.id) == ["z", "b", "a", "c"])
    }

    @Test func songs_recentlyPlayed_newestFirstUnplayedLast() throws {
        let songs = [try song("never", played: nil), try song("old", played: 100), try song("new", played: 500)]
        #expect(SongSort.recentlyPlayed.sorted(songs).map(\.id) == ["new", "old", "never"])
    }

    @Test func genres_keepOtherLastInEitherOrder() {
        let genres = [
            MainGenreSummary(name: GenreTaxonomy.otherGenre, tags: [], albumCount: 99, coverArtId: nil, styles: []),
            MainGenreSummary(name: "Rock", tags: [], albumCount: 10, coverArtId: nil, styles: []),
            MainGenreSummary(name: "Jazz", tags: [], albumCount: 40, coverArtId: nil, styles: [])
        ]
        #expect(GenreListSort.mostAlbums.sorted(genres).map(\.name) == ["Jazz", "Rock", GenreTaxonomy.otherGenre])
        #expect(GenreListSort.name.sorted(genres).map(\.name) == ["Jazz", "Rock", GenreTaxonomy.otherGenre])
    }

    @Test func labels_sortByNameOrSize() {
        let labels = [RecordLabelSummary(name: "Warp", albumCount: 3, coverArtId: nil),
                      RecordLabelSummary(name: "Blue Note", albumCount: 12, coverArtId: nil),
                      RecordLabelSummary(name: "ECM", albumCount: 12, coverArtId: nil)]
        #expect(RecordLabelListSort.name.sorted(labels).map(\.name) == ["Blue Note", "ECM", "Warp"])
        #expect(RecordLabelListSort.mostAlbums.sorted(labels).map(\.name) == ["Blue Note", "ECM", "Warp"])
        #expect(RecordLabelListSort.mostAlbums.sorted(labels.reversed()).first?.albumCount == 12)
    }
}
