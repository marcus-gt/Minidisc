import Foundation
import SwiftData
import OSLog
import SwiftSonic

@MainActor
final class PinService: PinServiceProtocol {
    private let modelContext: ModelContext

    init(modelContainer: ModelContainer) {
        // Keep pin writes out of the main SwiftData observation graph.
        let ctx = ModelContext(modelContainer)
        ctx.autosaveEnabled = false
        self.modelContext = ctx
    }

    // MARK: - Query

    func isPinned(itemType: PinnedItemType, itemId: String) -> Bool {
        let compositeId = "\(itemType.rawValue):\(itemId)"
        var descriptor = FetchDescriptor<PinnedItem>(
            predicate: #Predicate<PinnedItem> { $0.id == compositeId }
        )
        descriptor.fetchLimit = 1
        return (try? modelContext.fetchCount(descriptor)) ?? 0 > 0
    }

    func currentPinnedCount() -> Int {
        let descriptor = FetchDescriptor<PinnedItem>()
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    func pinnedItemIds(itemType: PinnedItemType, serverId: UUID) -> [String] {
        let type = itemType.rawValue
        let descriptor = FetchDescriptor<PinnedItem>(
            predicate: #Predicate<PinnedItem> { $0.itemType == type && $0.serverId == serverId },
            sortBy: [SortDescriptor(\PinnedItem.sortOrder)]
        )
        return ((try? modelContext.fetch(descriptor)) ?? []).map(\.itemId)
    }

    // MARK: - Pin

    func pin(
        itemType: PinnedItemType,
        itemId: String,
        displayName: String,
        displaySubtitle: String,
        coverArtId: String?,
        serverId: UUID
    ) {
        let compositeId = "\(itemType.rawValue):\(itemId)"
        var existingDescriptor = FetchDescriptor<PinnedItem>(
            predicate: #Predicate<PinnedItem> { $0.id == compositeId }
        )
        existingDescriptor.fetchLimit = 1
        if (try? modelContext.fetchCount(existingDescriptor)) ?? 0 > 0 { return }

        let count = currentPinnedCount()

        let item = PinnedItem(
            itemType: itemType,
            itemId: itemId,
            displayName: displayName,
            displaySubtitle: displaySubtitle,
            coverArtId: coverArtId,
            serverId: serverId,
            sortOrder: count
        )
        modelContext.insert(item)
        try? modelContext.save()
        Logger.pin.info("Pinned \(itemType.rawValue, privacy: .public) \(itemId, privacy: .public) at position \(count, privacy: .public)")
    }

    // MARK: - Unpin

    func unpin(itemType: PinnedItemType, itemId: String) {
        let compositeId = "\(itemType.rawValue):\(itemId)"
        var descriptor = FetchDescriptor<PinnedItem>(
            predicate: #Predicate<PinnedItem> { $0.id == compositeId }
        )
        descriptor.fetchLimit = 1
        guard let item = try? modelContext.fetch(descriptor).first else { return }

        modelContext.delete(item)

        let allDescriptor = FetchDescriptor<PinnedItem>(
            sortBy: [SortDescriptor(\PinnedItem.sortOrder)]
        )
        let remaining = (try? modelContext.fetch(allDescriptor)) ?? []
        for (index, pinned) in remaining.enumerated() {
            pinned.sortOrder = index
        }

        try? modelContext.save()
        Logger.pin.info("Unpinned \(itemType.rawValue, privacy: .public) \(itemId, privacy: .public)")
    }

    // MARK: - Update

    func updateCoverArtId(itemType: PinnedItemType, itemId: String, newCoverArtId: String?) {
        let compositeId = "\(itemType.rawValue):\(itemId)"
        var descriptor = FetchDescriptor<PinnedItem>(
            predicate: #Predicate<PinnedItem> { $0.id == compositeId }
        )
        descriptor.fetchLimit = 1
        guard let item = try? modelContext.fetch(descriptor).first else { return }
        item.coverArtId = newCoverArtId
        try? modelContext.save()
        Logger.pin.debug("Updated coverArtId for \(itemType.rawValue, privacy: .public) \(itemId, privacy: .public) → \(newCoverArtId ?? "<nil>", privacy: .public)")
    }

    func updateDisplayName(itemType: PinnedItemType, itemId: String, displayName: String) {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let compositeId = "\(itemType.rawValue):\(itemId)"
        var descriptor = FetchDescriptor<PinnedItem>(
            predicate: #Predicate<PinnedItem> { $0.id == compositeId }
        )
        descriptor.fetchLimit = 1
        guard !name.isEmpty, let item = try? modelContext.fetch(descriptor).first, item.displayName != name else { return }
        item.displayName = name
        try? modelContext.save()
        Logger.pin.debug("Updated name for \(itemType.rawValue, privacy: .public) \(itemId, privacy: .public)")
    }

    func reconcilePinnedPlaylists(with playlists: [Playlist], serverId: UUID) {
        let type = PinnedItemType.playlist.rawValue
        let descriptor = FetchDescriptor<PinnedItem>(
            predicate: #Predicate<PinnedItem> { $0.itemType == type && $0.serverId == serverId }
        )
        let byID = Dictionary(playlists.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var changed = 0
        for item in (try? modelContext.fetch(descriptor)) ?? [] {
            guard let playlist = byID[item.itemId], !playlist.name.isEmpty, playlist.name != item.displayName else { continue }
            item.displayName = playlist.name
            changed += 1
        }
        guard changed > 0 else { return }
        try? modelContext.save()
        Logger.pin.info("Caught \(changed, privacy: .public) pinned playlist name(s) up with the server")
    }

    // MARK: - Reorder

    func reorder(items: [PinnedItem]) {
        for (index, item) in items.enumerated() {
            item.sortOrder = index
        }
        try? modelContext.save()
        Logger.pin.info("Reordered \(items.count, privacy: .public) pinned items")
    }
}
