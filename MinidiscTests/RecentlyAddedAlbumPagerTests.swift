import Foundation
import Testing
import SwiftSonic
@testable import Minidisc

/// Serves `albums` newest-first by offset and records each requested offset.
private actor PagedRecentAlbumsService: RecentlyAddedAlbumBrowsing {
    private(set) var albums: [AlbumID3]
    private(set) var offsets: [Int] = []
    /// Runs before the page is returned, so a test can change state mid-request.
    private var beforeReturning: (@MainActor @Sendable () -> Void)?

    init(albums: [AlbumID3]) { self.albums = albums }

    func insert(_ album: AlbumID3, at index: Int) { albums.insert(album, at: index) }
    func setBeforeReturning(_ action: @escaping @MainActor @Sendable () -> Void) { beforeReturning = action }

    func recentlyAddedAlbums(size: Int, offset: Int) async throws -> [AlbumID3] {
        offsets.append(offset)
        if let beforeReturning { await beforeReturning() }
        return Array(albums.dropFirst(offset).prefix(size))
    }
}

private func album(_ id: String) throws -> AlbumID3 {
    try JSONDecoder().decode(AlbumID3.self, from: Data(#"{"id":"\#(id)","name":"\#(id)","songCount":1,"duration":60}"#.utf8))
}

private func albums(_ range: Range<Int>) throws -> [AlbumID3] {
    try range.map { try album("a\($0)") }
}

@Suite("RecentlyAddedAlbumPager") @MainActor
struct RecentlyAddedAlbumPagerTests {
    @Test func loadMore_fullFirstPage_appendsNextPageFromOffset() async throws {
        let size = RecentlyAddedAlbumPager.pageSize
        let service = PagedRecentAlbumsService(albums: try albums(0..<(size + 10)))
        let pager = RecentlyAddedAlbumPager(libraryService: service, firstPage: Array(await service.albums.prefix(size)))

        #expect(pager.hasMore)
        await pager.loadMore()

        #expect(await service.offsets == [size])
        #expect(await pager.albums.map(\.id) == service.albums.map(\.id))
        #expect(!pager.hasMore, "A short page means the server has no older albums.")
    }

    @Test func init_shortFirstPage_doesNotRequestMore() async throws {
        let service = PagedRecentAlbumsService(albums: try albums(0..<5))
        let pager = RecentlyAddedAlbumPager(libraryService: service, firstPage: await service.albums)

        await pager.loadMore()

        #expect(!pager.hasMore)
        #expect(await service.offsets.isEmpty)
    }

    @Test func loadMore_albumAddedBetweenPages_skipsShiftedDuplicate() async throws {
        let size = RecentlyAddedAlbumPager.pageSize
        let service = PagedRecentAlbumsService(albums: try albums(0..<(size * 2)))
        let pager = RecentlyAddedAlbumPager(libraryService: service, firstPage: Array(await service.albums.prefix(size)))
        // A new album at the top pushes the last first-page album into the next page.
        await service.insert(try album("new"), at: 0)

        await pager.loadMore()

        #expect(pager.albums.count == Set(pager.albums.map(\.id)).count)
        // 60 from the first page, plus the next page minus the repeated a59.
        #expect(pager.albums.count == size * 2 - 1)
    }

    @Test func loadMoreIfNeeded_albumFarFromEnd_doesNotLoad() async throws {
        let size = RecentlyAddedAlbumPager.pageSize
        let service = PagedRecentAlbumsService(albums: try albums(0..<(size * 2)))
        let pager = RecentlyAddedAlbumPager(libraryService: service, firstPage: Array(await service.albums.prefix(size)))

        await pager.loadMoreIfNeeded(after: pager.albums[0])
        #expect(await service.offsets.isEmpty)

        await pager.loadMoreIfNeeded(after: pager.albums[size - 1])
        #expect(await service.offsets == [size])
    }

    @Test func reset_whilePageInFlight_discardsStalePage() async throws {
        let size = RecentlyAddedAlbumPager.pageSize
        let service = PagedRecentAlbumsService(albums: try albums(0..<(size * 2)))
        let pager = RecentlyAddedAlbumPager(libraryService: service, firstPage: Array(await service.albums.prefix(size)))
        let fresh = [try album("fresh")]
        await service.setBeforeReturning { pager.reset(firstPage: fresh) }

        await pager.loadMore()

        #expect(pager.albums.map(\.id) == ["fresh"])
        #expect(!pager.isLoadingMore)
    }
}
