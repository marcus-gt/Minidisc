import Foundation
import Observation
import OSLog
import SwiftSonic

/// Pages through the server's newest albums so "Recently Added" grids scroll without a fixed cap.
@Observable
@MainActor
final class RecentlyAddedAlbumPager {
    nonisolated static let pageSize = 60
    /// How close to the end of the list an appearing album triggers the next page.
    static let prefetchDistance = 12

    private(set) var albums: [AlbumID3] = []
    private(set) var hasMore = false
    private(set) var isLoadingMore = false

    private let libraryService: any RecentlyAddedAlbumBrowsing
    /// Raw rows fetched so far. The next page starts here, even when duplicates were dropped.
    private var fetchedCount = 0
    private var seenIDs: Set<String> = []
    private var generation: UInt64 = 0

    init(libraryService: any RecentlyAddedAlbumBrowsing, firstPage: [AlbumID3] = []) {
        self.libraryService = libraryService
        reset(firstPage: firstPage)
    }

    /// Replaces the list with a freshly loaded first page and drops any page still in flight.
    func reset(firstPage: [AlbumID3]) {
        generation &+= 1
        isLoadingMore = false
        fetchedCount = firstPage.count
        seenIDs = []
        albums = firstPage.filter { seenIDs.insert($0.id).inserted }
        hasMore = firstPage.count >= Self.pageSize
    }

    /// Call from each album's `onAppear`; loads the next page once the user nears the end.
    func loadMoreIfNeeded(after album: AlbumID3) async {
        guard let index = albums.lastIndex(where: { $0.id == album.id }),
              index >= albums.count - Self.prefetchDistance else { return }
        await loadMore()
    }

    func loadMore() async {
        guard hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        let requestGeneration = generation
        let offset = fetchedCount
        do {
            let page = try await libraryService.recentlyAddedAlbums(size: Self.pageSize, offset: offset)
            guard requestGeneration == generation else { return }
            fetchedCount += page.count
            // Albums added on the server between pages shift the offsets; skip the repeats.
            albums += page.filter { seenIDs.insert($0.id).inserted }
            hasMore = page.count >= Self.pageSize
        } catch {
            guard requestGeneration == generation else { return }
            if !UserFacingError.isCancellation(error) {
                Logger.library.error("[RecentlyAdded] page at offset \(offset, privacy: .public) failed: \(UserFacingError.from(error).id, privacy: .public)")
            }
        }
        isLoadingMore = false
    }
}
