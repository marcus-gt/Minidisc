import AppKit
import SwiftUI
import Vision

/// The image behind the artist page's hero: the artist's photo, cropped to keep the face in view,
/// or, when there's no photo, a cover blurred into a colour wash.
///
/// Navidrome serves an album cover as the artist image when it has no photo, under an ID that
/// doesn't change, so "has a photo" can't be read from the ID. A server image that matches one of
/// the artist's album covers is treated as no photo.
struct MacArtistHeroImage: View {
    let photoID: String?
    let fallbackID: String?
    /// The artist's album covers, to recognise a server image that is really one of them.
    let albumCoverIDs: [String]

    @Environment(\.appContainer) private var container
    @State private var hero: Hero?

    private struct Hero {
        let image: PlatformImage
        let isPhoto: Bool
        /// Where the face is, from 0 (top) to 1 (bottom), when one was found.
        let faceCenter: CGFloat?
    }

    private struct LoadKey: Equatable {
        let photoID: String?
        let fallbackID: String?
        let albumCount: Int
    }

    var body: some View {
        GeometryReader { geometry in
            if let hero {
                let frame = Self.frame(of: hero, in: geometry.size)
                Image(platformImage: hero.image)
                    .resizable()
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
                    .blur(radius: hero.isPhoto ? 0 : 40)
                    .saturation(hero.isPhoto ? 1 : 1.2)
            } else {
                Color.secondary.opacity(0.15)
            }
        }
        .clipped()
        .task(id: LoadKey(photoID: photoID, fallbackID: fallbackID, albumCount: albumCoverIDs.count)) {
            await load()
        }
    }

    /// Fills the hero, centred across; down the image, the face sits a little above the middle of
    /// what shows (photos without a face are cropped around their upper middle).
    private static func frame(of hero: Hero, in size: CGSize) -> CGRect {
        let imageSize = hero.image.size
        guard imageSize.width > 0, imageSize.height > 0, size.width > 0, size.height > 0 else {
            return CGRect(origin: .zero, size: size)
        }
        let scale = max(size.width / imageSize.width, size.height / imageSize.height)
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        let focus = hero.isPhoto ? (hero.faceCenter ?? MacArtistHeroMetrics.defaultFocus) : 0.5
        let top = min(max(focus * height - MacArtistHeroMetrics.faceLine * size.height, 0), height - size.height)
        return CGRect(x: -(width - size.width) / 2, y: -top, width: width, height: height)
    }

    private func load() async {
        guard let cache = container?.artworkImageCache else { return }
        if let photoID, let image = await cache.load(coverArtId: photoID, tier: .hero),
           let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let isAlbumCover = await matchesAlbumCover(cgImage, cache: cache)
            guard !Task.isCancelled else { return }
            if isAlbumCover {
                hero = Hero(image: image, isPhoto: false, faceCenter: nil)
            } else {
                hero = Hero(image: image, isPhoto: true, faceCenter: await Self.faceCenter(in: cgImage))
            }
            return
        }
        if let fallbackID, let image = await cache.load(coverArtId: fallbackID, tier: .thumb) {
            guard !Task.isCancelled else { return }
            hero = Hero(image: image, isPhoto: false, faceCenter: nil)
        }
    }

    private func matchesAlbumCover(_ image: CGImage, cache: ArtworkImageCache) async -> Bool {
        guard let hash = Self.averageHash(image) else { return false }
        for id in albumCoverIDs {
            guard !Task.isCancelled else { return false }
            guard let cover = await cache.load(coverArtId: id, tier: .thumb),
                  let cgCover = cover.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  let coverHash = Self.averageHash(cgCover) else { continue }
            if (hash ^ coverHash).nonzeroBitCount <= MacArtistHeroMetrics.sameImageDistance { return true }
        }
        return false
    }

    /// An 8 × 8 average hash: one bit per cell, set when the cell is lighter than the image's mean.
    /// Two sizes of the same picture land within a few bits of each other.
    private nonisolated static func averageHash(_ image: CGImage) -> UInt64? {
        let side = 8
        var pixels = [UInt8](repeating: 0, count: side * side)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }
        let mean = pixels.reduce(0) { $0 + Int($1) } / pixels.count
        return pixels.enumerated().reduce(UInt64(0)) { hash, pixel in
            Int(pixel.element) > mean ? hash | (UInt64(1) << UInt64(pixel.offset)) : hash
        }
    }

    /// The vertical centre of the faces in the photo (0 is the top), or nil when there are none.
    private nonisolated static func faceCenter(in image: CGImage) async -> CGFloat? {
        await Task.detached(priority: .utility) {
            let request = VNDetectFaceRectanglesRequest()
            let handler = VNImageRequestHandler(cgImage: image)
            guard (try? handler.perform([request])) != nil,
                  let faces = request.results, let first = faces.first else { return nil }
            let box = faces.dropFirst().reduce(first.boundingBox) { $0.union($1.boundingBox) }
            // Vision's origin is the bottom left.
            return 1 - box.midY
        }.value
    }
}

private enum MacArtistHeroMetrics {
    /// Where a photo without a face is cropped: 0 is the top, 0.5 the middle.
    static let defaultFocus: CGFloat = 0.3
    /// Where the face sits in the hero: this far down from its top.
    static let faceLine: CGFloat = 0.4
    /// Bits two average hashes may differ by and still be the same picture.
    static let sameImageDistance = 6
}
