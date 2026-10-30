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

// MARK: - WrappedYearlyPlaylist

nonisolated struct WrappedYearlyPlaylist: Sendable, Identifiable {
    let id: String
    let year: Int
    let name: String
    let coverArtId: String?
}

// MARK: - SyncResult

nonisolated enum SyncResult: Sendable, Equatable {
    case upToDate
    case updated(tracksCount: Int)
    case skippedNoData
    case serverError(String)
    case cancelled
}

// MARK: - WrappedPlaylistService

/// Refreshes the annual top-100 playlist monthly using createPlaylist replacement.
actor WrappedPlaylistService {
    nonisolated static let wrappedPlaylistNamePrefix = "maekster Wrapped "

    /// Prefix used before the rebrand. Playlists named with it stay recognised and are renamed
    /// to the current prefix by the monthly sync.
    nonisolated static let legacyWrappedPlaylistNamePrefix = "Minidisc Wrapped "

    nonisolated static func playlistName(year: Int) -> String {
        "\(wrappedPlaylistNamePrefix)\(year)"
    }

    /// The year of a Wrapped playlist under the current or the legacy name; nil for any other playlist.
    nonisolated static func year(fromPlaylistName name: String) -> Int? {
        for prefix in [wrappedPlaylistNamePrefix, legacyWrappedPlaylistNamePrefix] where name.hasPrefix(prefix) {
            return Int(name.dropFirst(prefix.count))
        }
        return nil
    }

    private let statsService: StatsService
    /// The year's most played library tracks. ListenBrainz-backed in the app (#16), local in tests.
    typealias TopTracksProvider = @Sendable (_ year: Int, _ serverId: String, _ limit: Int, _ calendar: Calendar) async -> [TopTrackEntry]
    private let topTracks: TopTracksProvider
    private let preferences: WrappedPreferences
    private let makeClient: @Sendable () async throws -> any PlaylistSyncClient
    private let serverService: (any ServerServiceProtocol)?
    /// Username of the active account, so only the user's own legacy playlists are renamed.
    private let currentOwner: @Sendable () async -> String?

    init(
        serverService: any ServerServiceProtocol,
        statsService: StatsService,
        preferences: WrappedPreferences = WrappedPreferences(),
        topTracks: TopTracksProvider? = nil
    ) {
        self.statsService = statsService
        self.topTracks = topTracks ?? Self.localTopTracks(statsService)
        self.preferences = preferences
        self.serverService = serverService
        self.makeClient = { try await serverService.activeConnection().makeSwiftSonicClient() }
        self.currentOwner = { await MainActor.run { serverService.state.activeServer?.username } }
    }

    init(
        clientFactory: @escaping @Sendable () async throws -> any PlaylistSyncClient,
        statsService: StatsService,
        preferences: WrappedPreferences,
        owner: String? = nil
    ) {
        self.statsService = statsService
        self.topTracks = Self.localTopTracks(statsService)
        self.preferences = preferences
        self.serverService = nil
        self.makeClient = clientFactory
        self.currentOwner = { owner }
    }

    private static func localTopTracks(_ stats: StatsService) -> TopTracksProvider {
        { year, serverId, limit, calendar in
            await stats.topTracks(forPeriod: .year(year), serverId: serverId, limit: limit, calendar: calendar)
        }
    }

    // MARK: - Public API

    /// Replaces the annual "maekster Wrapped <year>" playlist with the top 100
    /// tracks listened to so far this year. Idempotent within a calendar month:
    /// a second call in the same month returns `.upToDate` without a server round-trip.
    func runYearlyPlaylistSyncIfNeeded(
        serverId: String,
        calendar: Calendar,
        currentDate: Date = Date()
    ) async -> SyncResult {
        do {
            return try await runYearlyPlaylistSyncIfNeededCancellable(
                serverId: serverId,
                calendar: calendar,
                currentDate: currentDate
            )
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .serverError(error.localizedDescription)
        }
    }

    /// Cancellation-preserving entry point used by BackgroundSyncCoordinator.
    /// Completion markers are written only after the final cancellation check.
    func runYearlyPlaylistSyncIfNeededCancellable(
        serverId: String,
        calendar: Calendar,
        currentDate: Date = Date()
    ) async throws -> SyncResult {
        try Task.checkCancellation()
        let year = calendar.component(.year, from: currentDate)
        let currentYearMonth = YearMonth(year: year, month: calendar.component(.month, from: currentDate))

        if let last = preferences.lastUpdatedMonth(serverId: serverId), last >= currentYearMonth {
            Logger.wrapped.debug("[WRAPPED-SYNC] up-to-date last=\(last, privacy: .public) current=\(currentYearMonth, privacy: .public)")
            return .upToDate
        }

        Logger.wrapped.debug("[WRAPPED-SYNC] start year=\(year, privacy: .public) serverId=\(serverId, privacy: .public)")

        let tracks = await topTracks(year, serverId, 100, calendar)
        try Task.checkCancellation()
        Logger.wrapped.debug("[WRAPPED-SYNC] top tracks count=\(tracks.count, privacy: .public)")

        guard !tracks.isEmpty else {
            try Task.checkCancellation()
            preferences.setLastUpdatedMonth(currentYearMonth, serverId: serverId)
            Logger.wrapped.debug("[WRAPPED-SYNC] no data for year=\(year, privacy: .public) — skipped")
            return .skippedNoData
        }

        let client: any PlaylistSyncClient
        do {
            client = try await makeClient()
        } catch {
            if error is CancellationError { throw CancellationError() }
            try Task.checkCancellation()
            Logger.wrapped.error("[WRAPPED-SYNC] client init failed: \(error, privacy: .public)")
            return .serverError(error.localizedDescription)
        }
        try Task.checkCancellation()

        let owner = await currentOwner()
        try Task.checkCancellation()

        let pid: String
        let livePlaylists: [Playlist]
        do {
            (pid, livePlaylists) = try await getOrCreatePlaylist(for: year, serverId: serverId, owner: owner, client: client)
        } catch {
            if error is CancellationError { throw CancellationError() }
            try Task.checkCancellation()
            Logger.wrapped.error("[WRAPPED-SYNC] getOrCreatePlaylist failed: \(error, privacy: .public)")
            return .serverError(error.localizedDescription)
        }
        try Task.checkCancellation()

        let trackIds = tracks.map(\.trackId)
        do {
            try await replacePlaylistTracks(playlistId: pid, trackIds: trackIds, client: client)
        } catch {
            if error is CancellationError { throw CancellationError() }
            try Task.checkCancellation()
            Logger.wrapped.error("[WRAPPED-SYNC] replace playlist failed: \(error, privacy: .public)")
            return .serverError(error.localizedDescription)
        }
        try Task.checkCancellation()

        try await uploadWrappedCover(year: year, playlistId: pid)
        try await renameLegacyPastYearPlaylists(livePlaylists, currentYear: year, owner: owner, client: client)

        try Task.checkCancellation()
        preferences.setLastUpdatedMonth(currentYearMonth, serverId: serverId)
        preferences.setLastWrappedYear(year, serverId: serverId)
        Logger.wrapped.info("[WRAPPED-SYNC] updated year=\(year, privacy: .public) tracks=\(tracks.count, privacy: .public) playlist=\(pid, privacy: .public)")
        return .updated(tracksCount: tracks.count)
    }

    func playlistId(year: Int, serverId: String) -> String? {
        preferences.playlistId(year: year, serverId: serverId)
    }

    /// Checks whether the calendar year has advanced since the last recorded marker.
    /// When it has, clears the monthly idempotence key so the sync runs fresh for
    /// the new year, then updates the year marker. No-op if already current.
    func handleYearTransitionIfNeeded(
        serverId: String,
        calendar: Calendar,
        currentDate: Date = Date()
    ) async {
        try? await handleYearTransitionIfNeededCancellable(
            serverId: serverId,
            calendar: calendar,
            currentDate: currentDate
        )
    }

    func handleYearTransitionIfNeededCancellable(
        serverId: String,
        calendar: Calendar,
        currentDate: Date = Date()
    ) async throws {
        try Task.checkCancellation()
        let currentYear = calendar.component(.year, from: currentDate)
        if let last = preferences.lastWrappedYear(serverId: serverId), last >= currentYear { return }
        try Task.checkCancellation()
        preferences.clearLastUpdatedMonth(serverId: serverId)
        preferences.setLastWrappedYear(currentYear, serverId: serverId)
        Logger.wrapped.info("Year marker → \(currentYear, privacy: .public) (serverId=\(serverId, privacy: .public))")
    }

    func fetchYearlyPlaylists(
        serverId: String,
        calendar: Calendar = .current,
        currentDate: Date = Date()
    ) async -> [WrappedYearlyPlaylist] {
        let client: any PlaylistSyncClient
        do {
            client = try await makeClient()
        } catch {
            Logger.wrapped.error("[WRAPPED] fetchYearlyPlaylists client init failed: \(error, privacy: .public)")
            return []
        }
        do {
            let all = try await client.getPlaylists(username: nil)
            // Clear stale identity and cadence markers so a deleted playlist can be recreated.
            reconcileCurrentYearPlaylist(serverId: serverId, livePlaylists: all, calendar: calendar, currentDate: currentDate)
            var byYear: [Int: WrappedYearlyPlaylist] = [:]
            for playlist in all {
                guard let year = Self.year(fromPlaylistName: playlist.name) else { continue }
                // If a legacy and a current playlist exist for one year, show the current one.
                if let shown = byYear[year], shown.name == Self.playlistName(year: year) { continue }
                byYear[year] = WrappedYearlyPlaylist(id: playlist.id, year: year, name: playlist.name, coverArtId: playlist.coverArt)
            }
            return byYear.values.sorted { $0.year > $1.year }
        } catch {
            Logger.wrapped.error("[WRAPPED] fetchYearlyPlaylists failed: \(error, privacy: .public)")
            return []
        }
    }

    // MARK: - Replace playlist tracks

    private func replacePlaylistTracks(
        playlistId: String,
        trackIds: [String],
        client: any PlaylistSyncClient
    ) async throws {
        _ = try await client.createPlaylist(name: nil, playlistId: playlistId, songIds: trackIds)
        Logger.wrapped.debug("[WRAPPED-SYNC] replaced playlist=\(playlistId, privacy: .public) with \(trackIds.count, privacy: .public) tracks")
    }

    // MARK: - Cover art upload

    private func uploadWrappedCover(year: Int, playlistId: String) async throws {
        try Task.checkCancellation()
        guard let serverService else { return }
        let snapshot = await MainActor.run { serverService.state.activeServer }
        try Task.checkCancellation()
        guard let snapshot, let baseURL = URL(string: snapshot.baseURL) else { return }

        let jpegData = await MainActor.run {
            WrappedCoverRenderer.generateCoverData(year: year)
        }
        try Task.checkCancellation()
        guard let jpegData else {
            Logger.wrapped.warning("[WRAPPED] Cover generation failed for \(year, privacy: .public)")
            return
        }

        do {
            let connection = try await serverService.activeConnection()
            let api = NavidromeNativeAPI(
                transport: CustomHeadersTransport(headers: connection.credentials.customHeaders)
            )
            let token = try await api.authenticate(
                baseURL: baseURL,
                username: snapshot.username,
                password: connection.credentials.password
            )
            try await api.uploadPlaylistCover(
                baseURL: baseURL,
                token: token,
                playlistId: playlistId,
                imageData: jpegData,
                mimeType: "image/jpeg"
            )
            try Task.checkCancellation()
            Logger.wrapped.info("[WRAPPED] Cover uploaded for \(year, privacy: .public) playlist")
        } catch {
            if error is CancellationError { throw CancellationError() }
            try Task.checkCancellation()
            Logger.wrapped.warning("[WRAPPED] Cover upload failed — \(error, privacy: .public)")
        }
    }

    /// Invalidates the current-year sync markers when its cached playlist is absent from the server.
    private func reconcileCurrentYearPlaylist(
        serverId: String,
        livePlaylists: [Playlist],
        calendar: Calendar,
        currentDate: Date
    ) {
        let year = calendar.component(.year, from: currentDate)
        guard let cached = preferences.playlistId(year: year, serverId: serverId) else { return }
        guard !livePlaylists.contains(where: { $0.id == cached }) else { return }
        preferences.clearPlaylistId(year: year, serverId: serverId)
        preferences.clearLastUpdatedMonth(serverId: serverId)
        Logger.wrapped.info("[WRAPPED] \(year, privacy: .public) playlist \(cached, privacy: .public) gone from server — cleared markers so it rebuilds next launch")
    }

    // MARK: - Get-or-create annual playlist

    /// Returns the playlist id for `year` together with the live playlist list it was resolved from.
    /// A playlist that still has the legacy name is reused and renamed in place, never duplicated.
    private func getOrCreatePlaylist(
        for year: Int,
        serverId: String,
        owner: String?,
        client: any PlaylistSyncClient
    ) async throws -> (id: String, playlists: [Playlist]) {
        try Task.checkCancellation()
        let name = Self.playlistName(year: year)
        // Validate cached IDs against the live list before replacing playlist contents.
        let playlists = try await client.getPlaylists(username: nil)
        try Task.checkCancellation()

        if let cached = preferences.playlistId(year: year, serverId: serverId),
           let existing = playlists.first(where: { $0.id == cached }) {
            try await renameIfLegacy(existing, year: year, owner: owner, client: client)
            return (cached, playlists)
        }

        let sameYear = playlists.filter { Self.year(fromPlaylistName: $0.name) == year }
        if let existing = sameYear.first(where: { $0.name == name }) ?? sameYear.first {
            preferences.setPlaylistId(existing.id, year: year, serverId: serverId)
            Logger.wrapped.info("Found '\(existing.name, privacy: .public)' id=\(existing.id, privacy: .public)")
            try await renameIfLegacy(existing, year: year, owner: owner, client: client)
            return (existing.id, playlists)
        }

        let created = try await client.createPlaylist(name: name, playlistId: nil, songIds: [])
        try Task.checkCancellation()
        preferences.setPlaylistId(created.id, year: year, serverId: serverId)
        Logger.wrapped.info("Created '\(name, privacy: .public)' id=\(created.id, privacy: .public) (serverId=\(serverId, privacy: .public))")
        return (created.id, playlists)
    }

    // MARK: - Legacy names

    /// Earlier years are never synced again, so their legacy playlists are renamed here and get a
    /// cover with the current name.
    private func renameLegacyPastYearPlaylists(
        _ playlists: [Playlist],
        currentYear: Int,
        owner: String?,
        client: any PlaylistSyncClient
    ) async throws {
        for playlist in playlists where playlist.name.hasPrefix(Self.legacyWrappedPlaylistNamePrefix) {
            guard let year = Self.year(fromPlaylistName: playlist.name), year != currentYear,
                  // Leave a legacy duplicate alone when the year already has a current-name playlist.
                  !playlists.contains(where: { $0.name == Self.playlistName(year: year) })
            else { continue }
            try Task.checkCancellation()
            if try await renameIfLegacy(playlist, year: year, owner: owner, client: client) {
                try await uploadWrappedCover(year: year, playlistId: playlist.id)
            }
        }
    }

    /// Renames a playlist that still has the legacy name, if it belongs to the user. Returns whether it
    /// was renamed. A failure is logged and ignored: the legacy name stays recognised.
    @discardableResult
    private func renameIfLegacy(
        _ playlist: Playlist,
        year: Int,
        owner: String?,
        client: any PlaylistSyncClient
    ) async throws -> Bool {
        guard playlist.name.hasPrefix(Self.legacyWrappedPlaylistNamePrefix),
              owner == nil || playlist.owner == nil || playlist.owner == owner
        else { return false }
        do {
            try await client.renamePlaylist(id: playlist.id, to: Self.playlistName(year: year))
            try Task.checkCancellation()
            Logger.wrapped.info("[WRAPPED-SYNC] renamed legacy \(year, privacy: .public) playlist id=\(playlist.id, privacy: .public)")
            return true
        } catch {
            if error is CancellationError { throw CancellationError() }
            try Task.checkCancellation()
            Logger.wrapped.warning("[WRAPPED-SYNC] rename of legacy \(year, privacy: .public) playlist failed: \(error, privacy: .public)")
            return false
        }
    }
}
