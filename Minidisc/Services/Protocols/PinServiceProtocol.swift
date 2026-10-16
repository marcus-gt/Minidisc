import Foundation

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
}
