import Foundation

nonisolated struct AlbumRecommendation: Sendable, Equatable, Hashable {
    let id: String?
    let title: String
    let artistName: String
    let releaseDate: Date?
    let coverArtURL: URL?
    let inLibrary: Bool
    /// "Album", "Single · Remix": what kind of record it is (library feed only).
    var typeLabel: String? = nil
}
