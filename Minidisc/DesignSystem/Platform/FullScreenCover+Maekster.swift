import SwiftUI

extension View {
    @ViewBuilder
    func maeksterFullScreenCover<Content: View>(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        self.fullScreenCover(isPresented: isPresented, onDismiss: onDismiss, content: content)
    }
}
