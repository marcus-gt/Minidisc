import Foundation
import SwiftSonic
import OSLog

nonisolated protocol MoodPlaylistClient: PlaylistSyncClient {
    func deletePlaylist(id: String) async throws
}

extension SwiftSonicClient: MoodPlaylistClient {}

nonisolated enum MoodDeletionOutcome: Sendable, Equatable {
    case finished(deleted: Int, failed: Int)
    case inProgress
    case failed
    case cancelled
}

// MARK: - MoodPlaylistService

/// The server playlists earlier versions created for each mood ("maekster · Chill"). Moods are radios
/// now (#60) and nothing creates these any more; this only removes them when asked.
actor MoodPlaylistService {
    private var isDeleting = false
    private let makePlaylistClient: @Sendable (String) async throws -> (client: any MoodPlaylistClient, owner: String?)
    private let recordMutation: (@Sendable (String, PlaylistWithSongs?, String?) async -> Void)?

    init(playlistClientFactory: @escaping @Sendable () async throws -> any MoodPlaylistClient, playlistOwner: String? = nil) {
        self.makePlaylistClient = { _ in (try await playlistClientFactory(), playlistOwner) }
        self.recordMutation = nil
    }

    init(serverService: any ServerServiceProtocol, catalog: LibraryCatalog) {
        self.makePlaylistClient = { serverId in
            let connection = try await serverService.activeConnection()
            guard connection.server.id.uuidString == serverId else { throw CancellationError() }
            return (connection.makeSwiftSonicClient(), connection.server.username)
        }
        self.recordMutation = { serverId, detail, deletedID in
            guard await serverService.activeConnectionVersion()?.serverID.uuidString == serverId else { return }
            await catalog.recordPlaylistMutation(summary: nil, detail: detail, deletedID: deletedID)
        }
    }

    /// Deletes the user's mood playlists under the current and the pre-rebrand names. Other users'
    /// playlists are left alone; one that is already gone counts as deleted.
    func deletePlaylists(serverId: String) async -> MoodDeletionOutcome {
        guard !Task.isCancelled else { return .cancelled }
        guard !isDeleting else { return .inProgress }
        isDeleting = true
        defer { isDeleting = false }
        do {
            let (client, owner) = try await makePlaylistClient(serverId)
            let playlists = try await client.getPlaylists(username: nil)
            try Task.checkCancellation()
            var deleted = 0
            var failed = 0
            for playlist in playlists where Mood.forPlaylistName(playlist.name) != nil
                && (owner == nil || playlist.owner == nil || playlist.owner == owner) {
                try Task.checkCancellation()
                do {
                    do { try await client.deletePlaylist(id: playlist.id) }
                    catch let error as SwiftSonicError {
                        switch error {
                        case .api(let apiError) where apiError.code == .notFound: break
                        case .httpError(let code, _, _) where code == 404: break
                        default: throw error
                        }
                    }
                    deleted += 1
                    await recordMutation?(serverId, nil, playlist.id)
                } catch is CancellationError { throw CancellationError() }
                catch { failed += 1 }
            }
            Logger.moodPlaylists.info("[MOOD] deleted \(deleted, privacy: .public) old mood playlists, \(failed, privacy: .public) failed")
            if deleted > 0 {
                Task { @MainActor in NotificationCenter.default.post(name: .minidiscPlaylistsChanged, object: nil) }
            }
            return .finished(deleted: deleted, failed: failed)
        } catch is CancellationError { return .cancelled }
        catch { return .failed }
    }
}
