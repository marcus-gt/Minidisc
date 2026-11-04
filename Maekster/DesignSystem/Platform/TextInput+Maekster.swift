import SwiftUI

extension View {
    /// For identifiers typed exactly as given (URLs, user names, header names): no autocorrection,
    /// and no automatic capitalisation on iOS. macOS doesn't capitalise text fields.
    func maeksterPlainTextInput() -> some View {
        #if os(macOS)
        self.autocorrectionDisabled()
        #else
        self.autocorrectionDisabled()
            .textInputAutocapitalization(.never)
        #endif
    }

    /// The ASCII keyboard on iOS (tokens, keys); a no-op on macOS, which has no software keyboard.
    func maeksterASCIIInput() -> some View {
        #if os(macOS)
        self
        #else
        self.keyboardType(.asciiCapable)
        #endif
    }

    /// The URL keyboard on iOS; a no-op on macOS, which has no software keyboard.
    func maeksterURLInput() -> some View {
        #if os(macOS)
        self
        #else
        self.keyboardType(.URL)
        #endif
    }
}
