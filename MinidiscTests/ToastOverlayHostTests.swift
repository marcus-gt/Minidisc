import Foundation
import Testing
@testable import Minidisc

/// Only one toast overlay shows a toast at a time (#82).
@Suite("Toast overlay hosts")
@MainActor
struct ToastOverlayHostTests {
    @Test func newestOverlay_showsTheToast_untilItGoes() {
        let toasts = ToastService()
        let root = UUID()
        let player = UUID()

        toasts.overlayDidAppear(root)
        #expect(toasts.isActiveOverlay(root))

        // The full player opens over the root: only its overlay shows toasts.
        toasts.overlayDidAppear(player)
        #expect(toasts.isActiveOverlay(player))
        #expect(!toasts.isActiveOverlay(root))

        // It closes, and the root's overlay takes over again.
        toasts.overlayDidDisappear(player)
        #expect(toasts.isActiveOverlay(root))
    }

    @Test func overlayAppearingAgain_doesNotRegisterTwice() {
        let toasts = ToastService()
        let root = UUID()
        let player = UUID()
        toasts.overlayDidAppear(root)
        toasts.overlayDidAppear(player)
        toasts.overlayDidAppear(root)
        #expect(toasts.overlayHosts == [player, root])
        toasts.overlayDidDisappear(root)
        #expect(toasts.isActiveOverlay(player))
    }
}
