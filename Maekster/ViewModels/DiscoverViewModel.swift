import Foundation
import SwiftSonic
import OSLog

@Observable
@MainActor
final class DiscoverViewModel {
    private let libraryService: any ListeningHistoryBrowsing
    private let recommendationService: RecommendationService
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    // MARK: - State

    private(set) var recentlyPlayed: [AlbumID3] = []
    private(set) var mostPlayed: [AlbumID3] = []
    private(set) var stations: [ArtistStation] = []
    private var favorites = HomeFavorites()
    private var generation = 0
    private(set) var isLoading: Bool = false
    private(set) var loadError: Error?
    private(set) var freshReleases: [AlbumRecommendation] = []
    /// Newest releases on the Discover shelf; the rest are behind "See all".
    static let freshReleasesShelfLimit = 20
    /// How far back the shelf looks: the same three months as See All.
    static let freshReleasesWindowDays = 90
    private(set) var isLoadingFreshReleases: Bool = false

    init(
        libraryService: any ListeningHistoryBrowsing,
        recommendationService: RecommendationService,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.libraryService = libraryService
        self.recommendationService = recommendationService
        self.calendar = calendar
        self.now = now
    }

    // MARK: - Derived state

    var isInitialLoading: Bool {
        isLoading && recentlyPlayed.isEmpty && mostPlayed.isEmpty
    }

    var isErrorState: Bool {
        loadError != nil && recentlyPlayed.isEmpty && mostPlayed.isEmpty
    }

    // MARK: - Loading

    func load(forceRefresh: Bool = false) async {
        if !forceRefresh, !stations.isEmpty {
            return
        }

        generation += 1
        let request = generation
        isLoading = true
        defer { if request == generation { isLoading = false } }

        // A history outage must not hide stations derived from favorites, and vice versa.
        async let recent = try? libraryService.recentlyPlayedAlbums(size: 35)
        async let frequent = try? libraryService.mostPlayedAlbums(size: 35)
        async let starred = try? (libraryService as? any StarredBrowsing)?.getStarred2()
        let (recentResult, frequentResult, starredResult) = await (recent, frequent, starred)
        guard request == generation, !Task.isCancelled else { return }
        if let recentResult { recentlyPlayed = recentResult }
        if let frequentResult { mostPlayed = frequentResult }
        if let starredResult {
            favorites = HomeFavorites(songs: starredResult.song ?? [], albums: starredResult.album ?? [], artists: starredResult.artist ?? [])
        }
        stations = ArtistStation.suggestions(favorites: favorites, recent: recentlyPlayed, frequent: mostPlayed)
        loadError = recentResult == nil && frequentResult == nil && starredResult == nil ? URLError(.cannotLoadFromNetwork) : nil
    }

    /// The newest releases of the past `freshReleasesWindowDays` days, as on See All, so the shelf
    /// isn't nearly empty early in a month. Future and undated releases are left out.
    func loadFreshReleases() async {
        isLoadingFreshReleases = true
        defer { isLoadingFreshReleases = false }

        let referenceDate = now()
        let today = calendar.startOfDay(for: referenceDate)
        guard let windowStart = calendar.date(byAdding: .day, value: -(Self.freshReleasesWindowDays - 1), to: today),
              let windowEnd = calendar.date(byAdding: .day, value: 1, to: today) else {
            freshReleases = []
            return
        }

        do {
            let fetched = try await recommendationService.freshReleases(
                limit: .max,
                daysWindow: Self.freshReleasesWindowDays
            )
            let recent = fetched
                .filter { release in
                    guard let releaseDate = release.releaseDate else { return false }
                    return releaseDate >= windowStart && releaseDate < windowEnd
                }
                .sorted {
                    ($0.releaseDate ?? .distantPast) > ($1.releaseDate ?? .distantPast)
                }
            freshReleases = Array(recent.prefix(Self.freshReleasesShelfLimit))
        } catch {
            Logger.discover.error("Failed to load fresh releases: \(error, privacy: .public)")
        }
    }
}
