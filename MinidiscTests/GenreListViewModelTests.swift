import Foundation
import SwiftSonic
import Testing
@testable import Minidisc

@Suite("Genre list")
@MainActor
struct GenreListViewModelTests {
    @Test func load_showsTheGenresFromTheIndex() async {
        let library = GenreListStub()
        library.result = [MainGenreSummary(name: "Jazz", tags: ["Jazz"], albumCount: 3, coverArtId: nil, styles: [])]
        let vm = GenreListViewModel(library: library)
        await vm.load()
        #expect(vm.state == .loaded)
        #expect(vm.genres.map(\.name) == ["Jazz"])
    }

    @Test func load_withIncompleteIndex_waitsForIndex() async {
        let library = GenreListStub()
        library.result = nil
        let vm = GenreListViewModel(library: library)
        await vm.load()
        #expect(vm.state == .waitingForIndex)
    }

    @Test func load_failure_mapsToUserFacingError() async {
        let library = GenreListStub()
        library.error = URLError(.notConnectedToInternet)
        let vm = GenreListViewModel(library: library)
        await vm.load()
        #expect(vm.state == .failed(.noNetwork))
    }
}

@MainActor
private final class GenreListStub: GenreBrowsing {
    var result: [MainGenreSummary]? = []
    var error: (any Error)?

    func genres() async throws -> [Genre] { [] }
    func albumsByGenre(_ genre: String, size: Int) async throws -> [AlbumID3] { [] }
    @MainActor
    func genreLibrary() async throws -> [MainGenreSummary]? {
        if let error { throw error }
        return result
    }
}
