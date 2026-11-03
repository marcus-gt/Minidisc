import Foundation

/// Downloaded albums and artists, as offline browsing lists them.
nonisolated struct OfflineAlbumSummary: Sendable, Identifiable, Hashable {
    let albumId: String
    let albumName: String
    let artistName: String?
    let coverArtId: String?
    let trackCount: Int
    var id: String { albumId }
}

nonisolated struct OfflineArtistSummary: Sendable, Identifiable, Hashable {
    let name: String
    let albums: [OfflineAlbumSummary]
    /// Server artist id when the downloaded tracks carried one. Present → the row can open the real
    /// artist screen (which rebuilds itself from downloads); absent → it falls back to the flat album list.
    var artistId: String?
    var coverArtId: String?
    var id: String { artistId ?? name }
}
