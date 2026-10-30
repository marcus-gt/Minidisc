import Foundation
import SwiftData
import SwiftSonic
import Testing
@testable import Minidisc

@Suite("Queue source (#71)")
struct QueueSourceTests {
    private let album = QueueSource.album(id: "al", name: "Kind of Blue")

    @Test func label_followsTheSourceUntilAutoExtendBegins() {
        let playlist = QueueSource.playlist(id: "p", name: "Techno – chill")
        #expect(QueueSourceLabel(source: nil, index: 0, extensionStart: nil) == nil)
        let before = QueueSourceLabel(source: playlist, index: 2, extensionStart: 3)
        #expect(before?.title == "Techno – chill")
        #expect(before?.opensSource == true)
        let after = QueueSourceLabel(source: playlist, index: 3, extensionStart: 3)
        #expect(after?.title == playlist.similarTitle)
        #expect(after?.opensSource == false)
        // No boundary: nothing was auto-extended.
        #expect(QueueSourceLabel(source: playlist, index: 40, extensionStart: nil)?.title == "Techno – chill")
    }

    /// The player already names the track's album, so an album alone gets no label, until
    /// auto-extend takes over and "Similar to" is news.
    @Test func album_isLabelledOnlyOnceAutoExtendTakesOver() {
        #expect(QueueSourceLabel(source: album, index: 0, extensionStart: nil) == nil)
        #expect(QueueSourceLabel(source: album, index: 2, extensionStart: 3) == nil)
        #expect(QueueSourceLabel(source: album, index: 3, extensionStart: 3)?.title == album.similarTitle)
    }

    @Test func endlessSources_neverTurnIntoSimilarSongs() {
        for source in [QueueSource.moodRadio(.focus), .smartShuffle, .queueBuilder, .artistRadio(id: "a", name: "Bill Evans"),
                       .instantMix(title: "Peace Piece"), .wrappedRadio(.year(2026))] {
            #expect(source.isEndless)
            #expect(QueueSourceLabel(source: source, index: 99, extensionStart: 1)?.title == source.title)
        }
        #expect(!album.isEndless)
    }

    @Test func destinations_coverThePagesThatExist() {
        #expect(album.destination == .album(id: "al"))
        #expect(QueueSource.playlist(id: "p", name: "Techno – chill").destination == .playlist(id: "p", name: "Techno – chill"))
        #expect(QueueSource.artistRadio(id: "a", name: "Bill Evans").destination == .artist(id: "a"))
        #expect(QueueSource.moodRadio(.chill).destination == nil)
        #expect(QueueSource.search(query: "jarrett").destination == nil)
    }

    @Test func instantMix_isAnArtistsRadioOrNamedAfterItsSeed() {
        #expect(QueueSource.instantMix(seed: .artist(id: "a"), title: "Bill Evans") == .artistRadio(id: "a", name: "Bill Evans"))
        #expect(QueueSource.instantMix(seed: .song(id: "s"), title: "Peace Piece") == .instantMix(title: "Peace Piece"))
        #expect(QueueSource.instantMix(seed: .album(id: "al"), title: nil) == nil)
    }

    @Test func everySource_survivesBeingSaved() throws {
        let sources: [QueueSource] = [
            album, .playlist(id: "p", name: "n"), .artist(id: "a", name: "n"), .artistRadio(id: "a", name: "n"),
            .instantMix(title: "t"), .smartShuffle, .queueBuilder, .moodRadio(.night), .wrappedRadio(.month(year: 2026, month: 3)),
            .wrapped(.allTime), .genre(name: "Jazz"), .recordLabel(name: "ECM"), .search(query: "q"), .favorites,
            .downloads, .recentlyAdded, .songs, .localFolder(name: "Phone")
        ]
        for source in sources {
            let decoded = try JSONDecoder().decode(QueueSource.self, from: JSONEncoder().encode(source))
            #expect(decoded == source)
            #expect(!source.title.isEmpty)
        }
    }

    /// Sessions keep the source and the auto-extend boundary across a relaunch.
    @Test func session_restoresTheSourceAndBoundary() async throws {
        let service = PlaybackSessionService(modelContainer: try ModelContainer.session(inMemory: true))
        let queue = (1...4).map { DisplayableSong(from: try! JSONDecoder().decode(Song.self, from: Data(
            "{\"id\":\"s\($0)\",\"title\":\"t\",\"isDir\":false,\"duration\":120}".utf8))) }
        await service.save(playerState: SessionPayload(
            currentIndex: 1, currentPosition: 10, queue: queue, currentTrack: queue[1], repeatMode: .off,
            queueSource: album, originalQueueEndIndex: 3
        ))
        let restored = await service.loadRestoredSession()
        #expect(restored?.queueSource == album)
        #expect(restored?.originalQueueEndIndex == 3)
    }

    /// A boundary beyond the saved queue would mislabel it, so it is dropped.
    @Test func session_dropsABoundaryOutsideTheQueue() async throws {
        let service = PlaybackSessionService(modelContainer: try ModelContainer.session(inMemory: true))
        let queue = [DisplayableSong(from: try JSONDecoder().decode(Song.self, from: Data(
            "{\"id\":\"s1\",\"title\":\"t\",\"isDir\":false,\"duration\":120}".utf8)))]
        await service.save(playerState: SessionPayload(
            currentIndex: 0, currentPosition: 0, queue: queue, currentTrack: queue[0], repeatMode: .off,
            queueSource: album, originalQueueEndIndex: 9
        ))
        #expect(await service.loadRestoredSession()?.originalQueueEndIndex == nil)
    }
}
