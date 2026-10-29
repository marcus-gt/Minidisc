import Foundation
import SwiftSonic

@MainActor
protocol PinServiceProtocol: AnyObject {
    func pin(
        itemType: PinnedItemType,
        itemId: String,
        displayName: String,
        displaySubtitle: String,
        coverArtId: String?,
        serverId: UUID
    )
    func unpin(itemType: PinnedItemType, itemId: String)
    func isPinned(itemType: PinnedItemType, itemId: String) -> Bool
    func reorder(items: [PinnedItem])
    func currentPinnedCount() -> Int
    /// IDs of the items of one type pinned on a server, in pin order.
    func pinnedItemIds(itemType: PinnedItemType, serverId: UUID) -> [String]
    func updateCoverArtId(itemType: PinnedItemType, itemId: String, newCoverArtId: String?)
    /// Brings a pin's snapshot name up to date after a rename. No-op when the item isn't pinned.
    func updateDisplayName(itemType: PinnedItemType, itemId: String, displayName: String)
    /// Catches the pinned playlists up with the server's names, so a rename made in another app or
    /// on the server also reaches the Pinned shelf.
    func reconcilePinnedPlaylists(with playlists: [Playlist], serverId: UUID)
}
