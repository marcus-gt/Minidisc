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

    // MARK: - Renaming

    @Test func rename_updatesThePinnedName() throws {
        let (pins, container) = try service()
        let server = UUID()
        pins.pin(itemType: .playlist, itemId: "pl1", displayName: "Techno - Chill", displaySubtitle: "", coverArtId: nil, serverId: server)
        pins.updateDisplayName(itemType: .playlist, itemId: "pl1", displayName: "  Techno – Chill  ")
        let stored = try ModelContext(container).fetch(FetchDescriptor<PinnedItem>())
        #expect(stored.first?.displayName == "Techno – Chill")
        // Not pinned: nothing is created.
        pins.updateDisplayName(itemType: .playlist, itemId: "unpinned", displayName: "X")
        #expect(try ModelContext(container).fetch(FetchDescriptor<PinnedItem>()).count == 1)
    }

    /// A playlist renamed in another app or on the server reaches the Pinned shelf too.
    @Test func reconcile_catchesPinnedPlaylistsUpWithTheServer() throws {
        let (pins, container) = try service()
        let server = UUID(), other = UUID()
        pins.pin(itemType: .playlist, itemId: "pl1", displayName: "Old", displaySubtitle: "", coverArtId: nil, serverId: server)
        pins.pin(itemType: .album, itemId: "pl1", displayName: "An album", displaySubtitle: "", coverArtId: nil, serverId: server)
        pins.pin(itemType: .playlist, itemId: "pl2", displayName: "Elsewhere", displaySubtitle: "", coverArtId: nil, serverId: other)

        pins.reconcilePinnedPlaylists(with: [
            Playlist(id: "pl1", name: "New", songCount: 1, duration: 1),
            Playlist(id: "pl2", name: "Not this server", songCount: 1, duration: 1)
        ], serverId: server)

        let names = Dictionary(uniqueKeysWithValues: try ModelContext(container).fetch(FetchDescriptor<PinnedItem>()).map { ($0.id, $0.displayName) })
        #expect(names["playlist:pl1"] == "New")
        #expect(names["album:pl1"] == "An album")
        #expect(names["playlist:pl2"] == "Elsewhere")
    }

    /// Mood and Wrapped playlists are named by the app and would be renamed back.
    @Test func generatedPlaylists_cannotBeRenamed() {
        #expect(PlaylistRenamer.canRename(playlistName: "Techno - Chill"))
        #expect(!PlaylistRenamer.canRename(playlistName: WrappedPlaylistService.playlistName(year: 2025)))
        #expect(!PlaylistRenamer.canRename(playlistName: Mood.allCases[0].playlistName))
    }
}
