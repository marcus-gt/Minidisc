import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

extension PlatformImage {
    /// Returns a copy scaled down so neither dimension exceeds maxDimension.
    /// Returns self unchanged if already within bounds.
    nonisolated func resized(maxDimension: CGFloat) -> PlatformImage {
        let maxSide = max(size.width, size.height)
        guard maxSide > maxDimension else { return self }
        let scale = maxDimension / maxSide
        let newSize = CGSize(
            width: (size.width * scale).rounded(),
            height: (size.height * scale).rounded()
        )
        #if os(macOS)
        return NSImage(size: newSize, flipped: false) { rect in
            self.draw(in: rect)
            return true
        }
        #else
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: newSize)) }
        #endif
    }

    nonisolated func jpgData(quality: CGFloat) -> Data? {
        #if os(macOS)
        guard let cgImage else { return nil }
        return NSBitmapImageRep(cgImage: cgImage)
            .representation(using: .jpeg, properties: [.compressionFactor: quality])
        #else
        return jpegData(compressionQuality: quality)
        #endif
    }
}
