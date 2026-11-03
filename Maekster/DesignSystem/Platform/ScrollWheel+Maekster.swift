import SwiftUI
#if os(macOS)
import AppKit
#endif

extension View {
    /// Runs `action` when the user scrolls this view with a trackpad or mouse wheel (macOS). A
    /// scroll view's phase callback doesn't report those reliably on the Mac. A no-op on iOS, where
    /// `onScrollPhaseChange` sees touch drags.
    func maeksterOnScrollWheel(_ action: @escaping () -> Void) -> some View {
        #if os(macOS)
        modifier(ScrollWheelMonitor(action: action))
        #else
        self
        #endif
    }
}

#if os(macOS)
/// Watches scroll-wheel events while the pointer is over the view.
private struct ScrollWheelMonitor: ViewModifier {
    let action: () -> Void
    @State private var isHovering = false
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onHover { isHovering = $0 }
            .onAppear(perform: install)
            .onDisappear(perform: remove)
    }

    private func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            if isHovering, event.scrollingDeltaY != 0 { action() }
            return event
        }
    }

    private func remove() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
#endif
