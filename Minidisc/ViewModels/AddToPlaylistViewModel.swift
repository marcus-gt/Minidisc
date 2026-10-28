import Foundation
import SwiftSonic

enum AddToPlaylistResult { case added, duplicate, failed }

/// What tapping a playlist's checkbox did, or asks for (#14).
enum PlaylistToggleResult { case added, removed, needsRemovalConfirmation, failed }

/// How much of the selection a playlist already holds, for the checkbox beside it (#14).
nonisolated enum PlaylistMembership: Equatable, Sendable {
    /// Not looked up yet.
    case unknown
    case absent
    case partial
    case all
}

@MainActor
@Observable
final class AddToPlaylistViewModel {
    private(set) var playlists: [Playlist] = []
    private(set) var isLoading = false
    private(set) var addingToPlaylistIds: Set<String> = []
    private(set) var error: UserFacingError?
    private(set) var recentIDs: [String]
    private(set) var createdPlaylist: Playlist?
    private(set) var isCreating = false
    /// Playlist id → how much of the selection it holds. Filled in as rows come into view (#14).
    private(set) var membership: [String: PlaylistMembership] = [:]
    var newPlaylistName = ""
    let songs: [DisplayableSong]

    private let playlistService: any PlaylistServiceProtocol
    private let toastService: ToastService
    private let recents: RecentPlaylistDestinations
    private let recordUse: (String) -> Void
    private var intents: [String: PlaylistAppendIntent] = [:]
    private var completed: Set<String> = []
    /// The song ids each inspected playlist holds, in playlist order.
    private var entryIDs: [String: [String]] = [:]
    private var membershipLookups: Set<String> = []

    init(songs: [DisplayableSong], playlistService: any PlaylistServiceProtocol,
         toastService: ToastService, recents: RecentPlaylistDestinations,
         recordUse: @escaping (String) -> Void = { _ in }) {
        self.songs = songs
        self.playlistService = playlistService
        self.toastService = toastService
        self.recents = recents
        self.recordUse = recordUse
        self.recentIDs = recents.ids
    }

    var isSaving: Bool { isCreating || !addingToPlaylistIds.isEmpty }
    var canCreate: Bool { !newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving }

    func destinations(query: String, recent: Bool) -> [Playlist] {
        let query = LibrarySearchRanking.normalized(query)
        let filtered = playlists.filter { query.isEmpty || LibrarySearchRanking.normalized($0.name).contains(query) }
        if recent { return recentIDs.compactMap { id in filtered.first { $0.id == id } } }
        return filtered.filter { !recentIDs.contains($0.id) }.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    // MARK: - Membership

    func membership(of playlist: Playlist) -> PlaylistMembership {
        membership[playlist.id] ?? .unknown
    }

    /// Looks the playlist's songs up once, when its row appears, so a long list costs only what is seen.
    func loadMembership(of playlist: Playlist) async {
        guard membership[playlist.id] == nil, membershipLookups.insert(playlist.id).inserted else { return }
        do {
            let detail = try await playlistService.getPlaylist(id: playlist.id)
            apply(entryIDs: detail.entry?.map(\.id) ?? [], for: playlist.id)
        } catch {
            // An unreachable playlist simply shows no checkbox; the next appearance tries again.
            membershipLookups.remove(playlist.id)
        }
    }

    private func apply(entryIDs ids: [String], for playlistID: String) {
        entryIDs[playlistID] = ids
        let held = Set(ids)
        let selected = Set(songs.map(\.id))
        let found = selected.intersection(held)
        membership[playlistID] = found.isEmpty ? .absent : (found.count == selected.count ? .all : .partial)
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do { playlists = try await playlistService.listPlaylists() }
        catch { report(error) }
    }

    // MARK: - Toggling

    /// Ticks or unticks a playlist: a playlist that already holds the whole selection gives it up,
    /// anything else is filled up with the songs it is missing. Removing several songs at once asks
    /// first, through `needsRemovalConfirmation`.
    func toggle(_ playlist: Playlist) async -> PlaylistToggleResult {
        guard !isSaving else { return .failed }
        if membership(of: playlist) == .all {
            guard songs.count == 1 else { return .needsRemovalConfirmation }
            return await remove(from: playlist)
        }
        // Filling a checkbox never duplicates what is already there.
        return await forceAdd(to: playlist, skippingDuplicates: true) ? .added : .failed
    }

    /// Takes every occurrence of the selected songs out of the playlist.
    @discardableResult
    func remove(from playlist: Playlist) async -> PlaylistToggleResult {
        guard !songs.isEmpty, !isSaving else { return .failed }
        addingToPlaylistIds.insert(playlist.id)
        error = nil
        defer { addingToPlaylistIds.remove(playlist.id) }
        do {
            // Indices come from the playlist as it is now: a stale list would remove the wrong tracks.
            let current = try await playlistService.getPlaylist(id: playlist.id)
            let ids = current.entry?.map(\.id) ?? []
            let selected = Set(songs.map(\.id))
            let indices = ids.enumerated().filter { selected.contains($0.element) }.map(\.offset)
            guard !indices.isEmpty else {
                apply(entryIDs: ids, for: playlist.id)
                return .removed
            }
            try await playlistService.removeTracks(playlistId: playlist.id, indices: indices)
            let remaining = ids.enumerated().filter { !indices.contains($0.offset) }.map(\.element)
            apply(entryIDs: remaining, for: playlist.id)
            // A later tap on the same playlist starts a fresh append.
            completed.remove(playlist.id)
            intents[playlist.id] = nil
            recordUse(playlist.id)
            let message = songs.count == 1
                ? String(localized: "Removed from playlist")
                : String(localized: "\(indices.count) songs removed")
            toastService.showConfirmation(message, subtitle: playlist.name, coverArtId: playlist.coverArt,
                action: .navigateToPlaylist(id: playlist.id, name: playlist.name, coverArtId: playlist.coverArt))
            return .removed
        } catch {
            report(error)
            return .failed
        }
    }

    func checkAndAdd(to playlist: Playlist) async -> AddToPlaylistResult {
        await add(to: playlist, duplicatePolicy: nil)
    }

    @discardableResult
    func forceAdd(to playlist: Playlist, skippingDuplicates: Bool = false) async -> Bool {
        await add(to: playlist, duplicatePolicy: skippingDuplicates) == .added
    }

    /// Retry finishes the created playlist after an append failure, keeping its name and selection.
    func createAndAdd() async -> Bool {
        guard canCreate else { return false }
        error = nil
        if createdPlaylist == nil {
            isCreating = true
            do {
                let created = try await playlistService.createPlaylist(
                    name: newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines), description: nil)
                let summary = Playlist(id: created.id, name: created.name, songCount: created.songCount,
                                       duration: created.duration, comment: created.comment, owner: created.owner,
                                       isPublic: created.isPublic, created: created.created,
                                       changed: created.changed, coverArt: created.coverArt)
                createdPlaylist = summary
                playlists.insert(summary, at: 0)
                intents[summary.id] = PlaylistAppendIntent(songs: songs, existingIDs: created.entry?.map(\.id) ?? [])
            } catch { report(error) }
            isCreating = false
        }
        guard let createdPlaylist else { return false }
        return await forceAdd(to: createdPlaylist)
    }

    /// nil asks for a decision; true skips existing IDs; false preserves requested occurrences.
    private func add(to playlist: Playlist, duplicatePolicy: Bool?) async -> AddToPlaylistResult {
        guard !songs.isEmpty, !isSaving else { return .failed }
        if completed.contains(playlist.id) { return .added }
        addingToPlaylistIds.insert(playlist.id)
        error = nil
        defer { addingToPlaylistIds.remove(playlist.id) }
        do {
            let current = try await playlistService.getPlaylist(id: playlist.id)
            let ids = current.entry?.map(\.id) ?? []
            if intents[playlist.id] == nil {
                let existing = Set(ids)
                if duplicatePolicy == nil, songs.contains(where: { existing.contains($0.id) }) { return .duplicate }
                let desired = duplicatePolicy == true ? songs.filter { !existing.contains($0.id) } : songs
                intents[playlist.id] = PlaylistAppendIntent(songs: desired, existingIDs: ids)
            }
            guard let intent = intents[playlist.id] else { return .failed }
            let remaining = intent.remaining(after: ids)
            if !remaining.isEmpty {
                try await playlistService.addTracks(playlistId: playlist.id, songs: remaining.map { $0.asSong() })
            }
            apply(entryIDs: ids + remaining.map(\.id), for: playlist.id)
            completed.insert(playlist.id)
            recents.record(playlist.id)
            recordUse(playlist.id)
            recentIDs = recents.ids
            let message = intent.songs.isEmpty ? String(localized: "These songs are already in the playlist.")
                : String(localized: "\(intent.songs.count) songs added")
            toastService.showConfirmation(message, subtitle: playlist.name, coverArtId: playlist.coverArt,
                action: .navigateToPlaylist(id: playlist.id, name: playlist.name, coverArtId: playlist.coverArt))
            return .added
        } catch {
            report(error)
            return .failed
        }
    }

    private func report(_ error: Error) {
        guard !UserFacingError.isCancellation(error) else { return }
        self.error = UserFacingError.from(error)
    }
}
