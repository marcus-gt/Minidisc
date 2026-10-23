import SwiftUI

extension View {
    /// A filter field pinned under the navigation title, for narrowing a Library list in place.
    /// The navigation-bar drawer placement is iOS-only; elsewhere this uses the default placement.
    func minidiscFilterable(text: Binding<String>, prompt: LocalizedStringKey) -> some View {
        #if os(iOS)
        searchable(text: text, placement: .navigationBarDrawer(displayMode: .always), prompt: Text(prompt))
        #else
        searchable(text: text, prompt: Text(prompt))
        #endif
    }
}
