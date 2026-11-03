import Foundation
import SwiftSonic
import Testing
@testable import Maekster

@Suite("Home personalization")
@MainActor
struct HomePersonalizationTests {
    @Test("Rediscovery removes duplicates and the latest listening history")
    func rediscovery() throws {
        let a = try album("a", artistID: "artist")
        let b = try album("b", artistID: "artist")
        let c = try album("c", artistID: "artist")
        #expect(HomePersonalization.rediscovery(favorites: [a, b], frequent: [b, c], recent: [a]).map(\.id) == ["b", "c"])
    }

    @Test("The earlier offline Home cache still decodes after the new shelves")
    func oldCacheRemainsReadable() throws {
        let data = Data(#"{"playlists":[],"recentlyPlayed":[],"recentlyAdded":[],"genres":[]}"#.utf8)
        let snapshot = try JSONDecoder().decode(HomeFeedSnapshot.self, from: data)
        #expect(snapshot.favorites == nil)
        #expect(snapshot.mostPlayed == nil)
    }

    @Test("Personal shelves survive serialization for an offline relaunch")
    func cacheRoundTrip() throws {
        let favorite = try album("favorite", artistID: "a")
        let source = HomeFeedSnapshot(favorites: HomeFavorites(albums: [favorite]), mostPlayed: [favorite])
        let restored = try JSONDecoder().decode(HomeFeedSnapshot.self, from: JSONEncoder().encode(source))
        #expect(restored.favorites?.albums.map(\.id) == ["favorite"])
        #expect(restored.mostPlayed?.map(\.id) == ["favorite"])
    }

    private func album(_ id: String, artistID: String?, artist: String = "Artist") throws -> AlbumID3 {
        var object: [String: Any] = ["id": id, "name": id, "artist": artist, "songCount": 1, "duration": 180]
        object["artistId"] = artistID
        return try JSONDecoder().decode(AlbumID3.self, from: JSONSerialization.data(withJSONObject: object))
    }
}
