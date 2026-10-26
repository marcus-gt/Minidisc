import Testing
@testable import Minidisc

@Suite("Playlist sort (#28)")
struct PlaylistSortTests {
    private func song(_ id: String, title: String, artist: String? = nil, album: String? = nil) -> DisplayableSong {
        DisplayableSong(
            id: id, title: title, artist: artist, albumId: nil, albumName: album, artistId: nil,
            genre: nil, duration: 200, trackNumber: nil, isDownloaded: false, coverArtId: nil, audioFormat: nil,
            replayGainTrackGain: nil, replayGainTrackPeak: nil, replayGainAlbumGain: nil,
            replayGainAlbumPeak: nil, replayGainBaseGain: nil, replayGainFallbackGain: nil
        )
    }

    private var songs: [DisplayableSong] {
        [
            song("1", title: "Since I Left You", artist: "The Avalanches", album: "Since I Left You"),
            song("2", title: "Frontier Psychiatrist", artist: "The Avalanches", album: "Since I Left You"),
            song("3", title: "Bamboo", artist: "Boards of Canada", album: nil),
            song("4", title: "alberto balsalm", artist: "Aphex Twin", album: "…I Care Because You Do")
        ]
    }

    private func ids(_ order: PlaylistSortOrder, _ direction: PlaylistSortDirection) -> [String] {
        let songs = songs
        return PlaylistSort.displayOrder(of: songs, by: order, direction: direction).map { songs[$0].id }
    }

    @Test func playlistOrder_ascendingKeepsStoredOrder() {
        #expect(ids(.playlistOrder, .ascending) == ["1", "2", "3", "4"])
    }

    @Test func playlistOrder_descendingReversesIt() {
        #expect(ids(.playlistOrder, .descending) == ["4", "3", "2", "1"])
    }

    @Test func title_bothDirections_ignoreCase() {
        #expect(ids(.title, .ascending) == ["4", "3", "2", "1"])
        #expect(ids(.title, .descending) == ["1", "2", "3", "4"])
    }

    @Test func artist_tiesKeepPlaylistOrderInBothDirections() {
        #expect(ids(.artist, .ascending) == ["4", "3", "1", "2"])
        #expect(ids(.artist, .descending) == ["1", "2", "3", "4"])
    }

    @Test func album_missingValuesSortLastInBothDirections() {
        #expect(ids(.album, .ascending).last == "3")
        #expect(ids(.album, .descending).last == "3")
    }

    @Test func duplicates_keepDistinctStoredPositions() {
        let songs = [song("x", title: "B"), song("y", title: "A"), song("x", title: "B")]
        let order = PlaylistSort.displayOrder(of: songs, by: .title, direction: .descending)
        #expect(order == [0, 2, 1])
        #expect(Set(order).count == songs.count)
    }

    @Test func emptyPlaylist_hasNoPositions() {
        #expect(PlaylistSort.displayOrder(of: [], by: .title, direction: .descending).isEmpty)
    }
}

@Suite("Playlist sort defaults")
struct PlaylistSortDefaultsTests {
    @Test func playlistOrder_opensLastToFirst() {
        #expect(PlaylistSortOrder.playlistOrder.defaultDirection == .descending)
    }

    @Test(arguments: [PlaylistSortOrder.title, .artist, .album])
    func textFields_startAtA(order: PlaylistSortOrder) {
        #expect(order.defaultDirection == .ascending)
    }
}
