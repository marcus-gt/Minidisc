import SwiftUI
#if os(macOS)
import AppKit
typealias PlatformImage = NSImage

extension NSImage {
    /// UIImage's `cgImage`, so image code shared with iOS reads the same on macOS.
    nonisolated var cgImage: CGImage? {
        cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}
#else
import UIKit
typealias PlatformImage = UIImage
#endif

extension ImageRenderer {
    /// The rendered image as the platform's image type.
    var platformImage: PlatformImage? {
        #if os(macOS)
        nsImage
        #else
        uiImage
        #endif
    }
}

extension Image {
    init(platformImage: PlatformImage) {
        #if os(macOS)
        self.init(nsImage: platformImage)
        #else
        self.init(uiImage: platformImage)
        #endif
    }
}
