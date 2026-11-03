import AppKit
import SwiftUI

/// Space plays and pauses, like the Music app, except while typing: a focused text field keeps the
/// space. A local key monitor sees the key before the focused view does, so it can check that first.
struct MacSpacebarPlayPause: ViewModifier {
    @Environment(\.appContainer) private var container
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear(perform: install)
            .onDisappear(perform: remove)
    }

    private func install() {
        guard monitor == nil, let playerService = container?.playerService else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard event.charactersIgnoringModifiers == " ", modifiers.isEmpty, !event.isARepeat,
                  !(event.window?.firstResponder is NSText) else { return event }
            Task { await playerService.togglePlayPause() }
            return nil
        }
    }

    private func remove() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
