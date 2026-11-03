import Foundation
import OSLog

/// A release kept between refreshes.
nonisolated struct StoredNewRelease: Codable, Sendable, Equatable {
    let id: String
    let title: String
    let artistName: String
    let firstReleaseDate: String?
    let typeLabel: String
}

/// What one server's feed remembers: the last result, and the artist names it already looked up.
nonisolated struct NewReleasesState: Codable, Sendable, Equatable {
    struct NameResolution: Codable, Sendable, Equatable {
        let musicBrainzID: String?
        let triedAt: Date
    }

    var refreshedAt: Date?
    var releases: [StoredNewRelease] = []
    /// `NewReleaseMatching.normalisedName` → the MusicBrainz artist, or `nil` when no certain match was found.
    var resolvedNames: [String: NameResolution] = [:]
}

/// "New releases by artists in your library that you don't own" (#15), from MusicBrainz, the way the
/// owner's NAS `new-releases` job finds them. Refreshed in the background about once a day.
actor LibraryNewReleasesService {
    static let windowDays = 90
    static let refreshInterval: TimeInterval = 20 * 3600
    /// Name lookups per refresh, so a big library's first runs stay short; the rest follow next time.
    static let nameLookupsPerRefresh = 120
    static let retryUnresolvedAfter: TimeInterval = 30 * 86_400
    /// Least time between automatic attempts, so a failing or skipped run isn't retried on every reload.
    static let retryFailedAfter: TimeInterval = 15 * 60

    private let watchlist: @Sendable () async throws -> NewReleaseWatchlist?
    private let activeServerID: @Sendable () async -> String?
    private let client: MusicBrainzReleaseClient
    private let directory: URL
    private let now: @Sendable () -> Date
    private let onChange: @Sendable () async -> Void

    private var states: [String: NewReleasesState] = [:]
    private var refreshTask: Task<Void, Never>?
    private var lastAutomaticStart: Date?
    private var storeLinkCache: [String: [StoreLink]] = [:]

    init(
        watchlist: @escaping @Sendable () async throws -> NewReleaseWatchlist?,
        activeServerID: @escaping @Sendable () async -> String?,
        client: MusicBrainzReleaseClient,
        directory: URL,
        now: @escaping @Sendable () -> Date = { Date() },
        onChange: @escaping @Sendable () async -> Void = {}
    ) {
        self.watchlist = watchlist
        self.activeServerID = activeServerID
        self.client = client
        self.directory = directory
        self.now = now
        self.onChange = onChange
    }

    // MARK: - Reading

    /// The last result for the active server, newest first. Starts a background refresh when it is stale.
    func releases() async -> [AlbumRecommendation] {
        guard let serverID = await activeServerID() else { return [] }
        let state = loadState(serverID: serverID)
        let date = now()
        if Self.isStale(state, now: date),
           lastAutomaticStart.map({ date.timeIntervalSince($0) >= Self.retryFailedAfter }) ?? true,
           refreshTask == nil {
            lastAutomaticStart = date
            startRefresh()
        }
        return state.releases.map(Self.recommendation)
    }

    /// Whether a first result is still being prepared (nothing stored yet, refresh running).
    func isPreparing() async -> Bool {
        guard let serverID = await activeServerID() else { return false }
        return loadState(serverID: serverID).refreshedAt == nil && refreshTask != nil
    }

    nonisolated static func isStale(_ state: NewReleasesState, now: Date) -> Bool {
        guard let refreshedAt = state.refreshedAt else { return true }
        return now.timeIntervalSince(refreshedAt) >= refreshInterval
    }

    nonisolated static func recommendation(_ release: StoredNewRelease) -> AlbumRecommendation {
        AlbumRecommendation(
            id: release.id,
            title: release.title,
            artistName: release.artistName,
            releaseDate: NewReleaseMatching.date(fromMusicBrainz: release.firstReleaseDate),
            coverArtURL: URL(string: "https://coverartarchive.org/release-group/\(release.id)/front-250"),
            inLibrary: false,
            typeLabel: release.typeLabel
        )
    }

    // MARK: - Refreshing

    func startRefresh() {
        guard refreshTask == nil else { return }
        refreshTask = Task {
            do {
                try await refresh()
            } catch is CancellationError {
            } catch {
                Logger.recommendations.warning("[NEW-RELEASES] refresh failed: \(String(describing: error), privacy: .public)")
            }
            refreshTask = nil
            // Also after a failed or skipped run (index not ready), so a screen waiting for the first
            // result stops showing it as being prepared.
            await onChange()
        }
    }

    /// One full refresh, in two passes so the first result comes quickly: artists whose MusicBrainz ID is
    /// already known are searched and published first; artists still to be looked up by name follow.
    /// A failed search keeps the previous result. Name lookups are saved as they go, and one that fails
    /// is skipped and tried again next time.
    func refresh() async throws {
        guard let serverID = await activeServerID(), let watchlist = try await watchlist() else { return }
        var state = loadState(serverID: serverID)
        let today = now()
        let from = NewReleaseMatching.musicBrainzDay(today.addingTimeInterval(-Double(Self.windowDays) * 86_400))
        let to = NewReleaseMatching.musicBrainzDay(today)

        // Which MusicBrainz artists to follow, and what is owned by each.
        var owned: [String: Set<String>] = [:]
        var toLookUp: [WatchedArtist] = []
        for artist in watchlist.artists {
            var mbid = artist.musicBrainzID
            if mbid == nil {
                if let known = state.resolvedNames[NewReleaseMatching.normalisedName(artist.name)],
                   known.musicBrainzID != nil || today.timeIntervalSince(known.triedAt) < Self.retryUnresolvedAfter {
                    mbid = known.musicBrainzID
                } else {
                    toLookUp.append(artist)
                }
            }
            if let mbid { Self.follow(mbid, owning: artist.ownedTitles, in: &owned) }
        }

        var found = try await releaseGroups(artistIDs: owned.keys.sorted(), from: from, to: to)
        guard try await publish(found, owned: owned, today: to, refreshedAt: today, in: &state, serverID: serverID) else { return }

        var lookups = 0
        var resolved: [String: Set<String>] = [:]
        for artist in toLookUp.prefix(Self.nameLookupsPerRefresh) {
            try Task.checkCancellation()
            let mbid: String?
            do {
                mbid = try await client.artistID(named: artist.name)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                Logger.recommendations.warning("[NEW-RELEASES] name lookup failed: \(String(describing: error), privacy: .public)")
                continue
            }
            lookups += 1
            state.resolvedNames[NewReleaseMatching.normalisedName(artist.name)] = .init(musicBrainzID: mbid, triedAt: today)
            if lookups.isMultiple(of: 20) { try save(state, serverID: serverID) }
            guard let mbid else { continue }
            if owned[mbid] != nil {
                Self.follow(mbid, owning: artist.ownedTitles, in: &owned)
            } else {
                Self.follow(mbid, owning: artist.ownedTitles, in: &resolved)
            }
        }
        guard await activeServerID() == serverID else { return }
        if lookups > 0 { try save(state, serverID: serverID) }
        Logger.recommendations.info("[NEW-RELEASES] \(lookups, privacy: .public) name lookups, \(resolved.count, privacy: .public) new artists")

        // Ownership may have grown through a looked-up name, so the second publish re-filters everything.
        guard !resolved.isEmpty || lookups > 0 else { return }
        found += try await releaseGroups(artistIDs: resolved.keys.sorted(), from: from, to: to)
        owned.merge(resolved) { $0.union($1) }
        _ = try await publish(found, owned: owned, today: to, refreshedAt: today, in: &state, serverID: serverID)
    }

    private nonisolated static func follow(_ mbid: String, owning titles: Set<String>, in owned: inout [String: Set<String>]) {
        guard !NewReleaseWatchlist.specialPurposeArtistIDs.contains(mbid) else { return }
        owned[mbid, default: []].formUnion(titles)
    }

    private func releaseGroups(artistIDs ids: [String], from: String, to: String) async throws -> [MBReleaseGroup] {
        var found: [MBReleaseGroup] = []
        for start in stride(from: 0, to: ids.count, by: MusicBrainzReleaseClient.artistsPerQuery) {
            try Task.checkCancellation()
            let batch = Array(ids[start..<min(start + MusicBrainzReleaseClient.artistsPerQuery, ids.count)])
            found += try await client.releaseGroups(artistIDs: batch, from: from, to: to)
        }
        return found
    }

    /// Stores and announces a result. `false` when the active server changed meanwhile: this server's
    /// result must not be stored under another one, and the refresh should stop.
    private func publish(_ found: [MBReleaseGroup], owned: [String: Set<String>], today: String, refreshedAt: Date,
                         in state: inout NewReleasesState, serverID: String) async throws -> Bool {
        let releases = Self.newReleases(from: found, owned: owned, today: today)
        guard await activeServerID() == serverID else { return false }
        state.releases = releases
        state.refreshedAt = refreshedAt
        try save(state, serverID: serverID)
        Logger.recommendations.info("[NEW-RELEASES] \(releases.count, privacy: .public) new releases from \(owned.count, privacy: .public) artists")
        await onChange()
        return true
    }

    /// Released, credited to a followed artist, not owned, newest first. One entry per release group, and
    /// one per title and date: MusicBrainz sometimes has a record twice under two credit spellings.
    nonisolated static func newReleases(from groups: [MBReleaseGroup], owned: [String: Set<String>], today: String) -> [StoredNewRelease] {
        var seen: Set<String> = []
        var seenTitles: Set<String> = []
        let kept = groups.filter { group in
            guard seen.insert(group.id).inserted,
                  NewReleaseMatching.isReleased(group.firstReleaseDate, today: today) else { return false }
            let credited = (group.artistCredit ?? []).map { $0.artist.id.lowercased() }.filter { owned[$0] != nil }
            guard !credited.isEmpty else { return false }
            let title = NewReleaseMatching.normalisedTitle(group.title)
            guard !credited.contains(where: { owned[$0]?.contains(title) == true }) else { return false }
            return seenTitles.insert("\(title)|\(group.firstReleaseDate ?? "")").inserted
        }
        return kept
            .sorted { ($0.firstReleaseDate ?? "") > ($1.firstReleaseDate ?? "") }
            .map { group in
                StoredNewRelease(
                    id: group.id,
                    title: group.title,
                    artistName: group.creditName,
                    firstReleaseDate: group.firstReleaseDate,
                    typeLabel: NewReleaseMatching.typeLabel(primary: group.primaryType, secondary: group.secondaryTypes ?? [])
                )
            }
    }

    // MARK: - Store links

    /// Store pages for one release: MusicBrainz' links when it has them, store searches otherwise.
    func storeLinks(releaseGroupID: String, artist: String, title: String, region: String?) async -> [StoreLink] {
        if let cached = storeLinkCache[releaseGroupID] { return cached }
        var pages: [MusicStore: URL] = [:]
        do {
            pages = ReleaseStoreLinks.recordPages(from: try await client.releaseURLs(releaseGroupID: releaseGroupID))
        } catch is CancellationError {
            return ReleaseStoreLinks.links(recordPages: [:], artist: artist, title: title, region: region)
        } catch {
            Logger.recommendations.warning("[NEW-RELEASES] store links failed for \(releaseGroupID, privacy: .public): \(String(describing: error), privacy: .public)")
            return ReleaseStoreLinks.links(recordPages: [:], artist: artist, title: title, region: region)
        }
        let links = ReleaseStoreLinks.links(recordPages: pages, artist: artist, title: title, region: region)
        storeLinkCache[releaseGroupID] = links
        return links
    }

    // MARK: - Persistence

    private func loadState(serverID: String) -> NewReleasesState {
        if let state = states[serverID] { return state }
        let state = (try? Data(contentsOf: fileURL(serverID: serverID)))
            .flatMap { try? JSONDecoder().decode(NewReleasesState.self, from: $0) } ?? NewReleasesState()
        states[serverID] = state
        return state
    }

    private func save(_ state: NewReleasesState, serverID: String) throws {
        states[serverID] = state
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(state).write(to: fileURL(serverID: serverID), options: .atomic)
    }

    private func fileURL(serverID: String) -> URL {
        directory.appendingPathComponent("\(serverID).json")
    }
}

/// Fresh Releases from the library feed. Similar artists come from the other providers.
actor LibraryNewReleasesProvider: RecommendationProvider {
    private let service: LibraryNewReleasesService

    init(service: LibraryNewReleasesService) {
        self.service = service
    }

    func similarArtists(toArtistID: String, limit: Int) async throws -> [SimilarArtistRecommendation] { [] }

    func freshReleases(limit: Int, daysWindow: Int) async throws -> [AlbumRecommendation] {
        let cutoff = Date().addingTimeInterval(-Double(daysWindow) * 86_400)
        return Array(await service.releases().filter { ($0.releaseDate ?? .distantFuture) >= cutoff }.prefix(limit))
    }
}
