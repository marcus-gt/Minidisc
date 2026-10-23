import Observation
import SwiftSonic

@Observable
@MainActor
final class HomeViewModel {
    let recentPager: RecentlyAddedAlbumPager
    var recentAlbums: [AlbumID3] { recentPager.albums }
    private(set) var recentlyPlayed: [AlbumID3] = []
    private(set) var mostPlayed: [AlbumID3] = []
    var isLoading = false
    var error: UserFacingError?

    private let libraryService: any RecentlyAddedAlbumBrowsing & ListeningHistoryBrowsing

    init(libraryService: any RecentlyAddedAlbumBrowsing & ListeningHistoryBrowsing) {
        self.libraryService = libraryService
        recentPager = RecentlyAddedAlbumPager(libraryService: libraryService)
    }

    func load() async {
        isLoading = true
        error = nil
        do {
            async let added = libraryService.recentlyAddedAlbums(size: RecentlyAddedAlbumPager.pageSize)
            async let played = libraryService.recentlyPlayedAlbums(size: 20)
            async let most = libraryService.mostPlayedAlbums(size: 20)
            let (a, p, m) = try await (added, played, most)
            recentPager.reset(firstPage: a)
            recentlyPlayed = p
            mostPlayed = m
        } catch {
            self.error = UserFacingError.from(error)
        }
        isLoading = false
    }
}
