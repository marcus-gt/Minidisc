import SwiftUI

extension View {
    /// The zoom navigation transition on iOS. macOS has no zoom transition, so it's a no-op there.
    @ViewBuilder
    func maeksterZoomTransition(sourceID: String?, in namespace: Namespace.ID?) -> some View {
        #if os(macOS)
        self
        #else
        if let sourceID, let namespace {
            self.navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        } else {
            self
        }
        #endif
    }

    /// Marks this view as the matched transition source for a zoom navigation (iOS 18+).
    /// No-op when either parameter is nil.
    @ViewBuilder
    func maeksterMatchedTransitionSource(id: String?, in namespace: Namespace.ID?) -> some View {
        if let id, let namespace {
            self.matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }
}
