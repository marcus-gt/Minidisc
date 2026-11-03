import SwiftUI
import SwiftData

/// Pin / Unpin for a detail page's "…" menu (#44). Observes the pin itself, so the label follows
/// pins made anywhere in the app.
struct PinMenuButton: View {
    let itemType: PinnedItemType
    let itemId: String
    let displayName: String
    let displaySubtitle: String
    let coverArtId: String?

    @Environment(\.appContainer) private var container
    @Query private var matches: [PinnedItem]

    init(itemType: PinnedItemType, itemId: String, displayName: String, displaySubtitle: String, coverArtId: String?) {
        self.itemType = itemType
        self.itemId = itemId
        self.displayName = displayName
        self.displaySubtitle = displaySubtitle
        self.coverArtId = coverArtId
        let pinnedID = "\(itemType.rawValue):\(itemId)"
        _matches = Query(filter: #Predicate<PinnedItem> { $0.id == pinnedID })
    }

    var body: some View {
        if !matches.isEmpty {
            Button(itemType.unpinLabel, systemImage: "pin.slash") {
                HapticFeedback.light.trigger()
                container?.pinService.unpin(itemType: itemType, itemId: itemId)
            }
        } else {
            Button(itemType.pinLabel, systemImage: "pin") {
                guard let serverId = container?.serverState.activeServer?.id,
                      let pin = container?.pinService else { return }
                pin.pin(itemType: itemType, itemId: itemId, displayName: displayName,
                        displaySubtitle: displaySubtitle, coverArtId: coverArtId, serverId: serverId)
                HapticFeedback.success.trigger()
                container?.toastService.showConfirmation("Pinned to Home")
            }
        }
    }
}
