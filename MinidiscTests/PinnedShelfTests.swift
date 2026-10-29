import Foundation
import SwiftData
import SwiftSonic
import Testing
@testable import Minidisc

@Suite("Pinned shelf (#44)")
@MainActor
struct PinnedShelfTests {
    private func service() throws -> (PinService, ModelContainer) {
        let container = try ModelContainer.minidisc(inMemory: true)
        return (PinService(modelContainer: container), container)
    }

    @Test func albumsPlaylistsAndArtists_pinTogetherInPinOrder() throws {
        let (pins, container) = try service()
        let server = UUID()
        pins.pin(itemType: .artist, itemId: "ar1", displayName: "Kraftwerk", displaySubtitle: "", coverArtId: "c-ar1", serverId: server)
        pins.pin(itemType: .album, itemId: "al1", displayName: "Computerwelt", displaySubtitle: "Kraftwerk", coverArtId: "c-al1", serverId: server)
        pins.pin(itemType: .playlist, itemId: "pl1", displayName: "Morning", displaySubtitle: "", coverArtId: nil, serverId: server)

        let stored = try ModelContext(container).fetch(FetchDescriptor<PinnedItem>(sortBy: [SortDescriptor(\.sortOrder)]))
        #expect(stored.map(\.id) == ["artist:ar1", "album:al1", "playlist:pl1"])
        #expect(pins.isPinned(itemType: .artist, itemId: "ar1"))
        // An artist and an album with the same server id are different pins.
        #expect(!pins.isPinned(itemType: .album, itemId: "ar1"))

        pins.unpin(itemType: .album, itemId: "al1")
        let remaining = try ModelContext(container).fetch(FetchDescriptor<PinnedItem>(sortBy: [SortDescriptor(\.sortOrder)]))
        #expect(remaining.map(\.id) == ["artist:ar1", "playlist:pl1"])
        #expect(remaining.map(\.sortOrder) == [0, 1])
    }

    /// Each pin leads to its own detail page, built from the pin's snapshot.
    @Test func destinations_followTheKindOfPin() {
        let server = UUID()
        let album = PinnedItem(itemType: .album, itemId: "al1", displayName: "Computerwelt", displaySubtitle: "Kraftwerk",
                               coverArtId: "c-al1", serverId: server, sortOrder: 0)
        let artist = PinnedItem(itemType: .artist, itemId: "ar1", displayName: "Kraftwerk", displaySubtitle: "",
                                coverArtId: "c-ar1", serverId: server, sortOrder: 1)
        let playlist = PinnedItem(itemType: .playlist, itemId: "pl1", displayName: "Morning", displaySubtitle: "",
                                  coverArtId: nil, serverId: server, sortOrder: 2)

        guard case .album(let a) = PinnedShelf.destination(for: album) else { Issue.record("album"); return }
        #expect(a.id == "al1"); #expect(a.name == "Computerwelt"); #expect(a.artist == "Kraftwerk"); #expect(a.coverArt == "c-al1")
        guard case .artist(let ar) = PinnedShelf.destination(for: artist) else { Issue.record("artist"); return }
        #expect(ar.id == "ar1"); #expect(ar.name == "Kraftwerk")
        guard case .playlist(let p) = PinnedShelf.destination(for: playlist) else { Issue.record("playlist"); return }
        #expect(p.id == "pl1"); #expect(p.name == "Morning")
    }

    @Test func unknownPinKind_isSkipped() {
        let item = PinnedItem(itemType: .album, itemId: "x", displayName: "X", displaySubtitle: "",
                              coverArtId: nil, serverId: UUID(), sortOrder: 0)
        item.itemType = "fromTheFuture"
        #expect(PinnedShelf.destination(for: item) == nil)
    }
}
