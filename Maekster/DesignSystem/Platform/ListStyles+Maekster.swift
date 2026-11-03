import SwiftUI

extension View {
    /// Inset grouped on iOS; macOS has no grouped style, so it uses the inset list.
    func maeksterSheetListStyle() -> some View {
        #if os(macOS)
        self.listStyle(.inset)
        #else
        self.listStyle(.insetGrouped)
        #endif
    }
}
