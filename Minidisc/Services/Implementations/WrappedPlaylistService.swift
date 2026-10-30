import Foundation
import SwiftSonic
import OSLog

// MARK: - PlaylistSyncClient

nonisolated protocol PlaylistSyncClient: Sendable {
    func getPlaylists(username: String?) async throws -> [Playlist]
    func createPlaylist(name: String?, playlistId: String?, songIds: [String]) async throws -> PlaylistWithSongs
    /// Changes only the name; the id and the tracks stay as they are.
    func renamePlaylist(id: String, to name: String) async throws
}

extension SwiftSonicClient: PlaylistSyncClient {
    func renamePlaylist(id: String, to name: String) async throws {
        try await updatePlaylist(id: id, name: name)
    }
}

// MARK: - WrappedPlaylistService

/// Names of the yearly Wrapped playlists earlier versions created on the server. maekster no longer
/// creates or updates them (#69); the names are kept so those playlists are still recognised.
nonisolated enum WrappedPlaylistService {
    static let wrappedPlaylistNamePrefix = "maekster Wrapped "

    /// Prefix used before the rebrand.
    static let legacyWrappedPlaylistNamePrefix = "Minidisc Wrapped "

    static func playlistName(year: Int) -> String {
        "\(wrappedPlaylistNamePrefix)\(year)"
    }

    /// The year of a Wrapped playlist under the current or the legacy name; nil for any other playlist.
    static func year(fromPlaylistName name: String) -> Int? {
        for prefix in [wrappedPlaylistNamePrefix, legacyWrappedPlaylistNamePrefix] where name.hasPrefix(prefix) {
            return Int(name.dropFirst(prefix.count))
        }
        return nil
    }
}
