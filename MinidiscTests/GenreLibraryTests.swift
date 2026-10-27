import Foundation
import SwiftSonic
import Testing
@testable import Minidisc

@Suite("Library genres (#49)")
struct GenreLibraryTests {
    /// A small fixed taxonomy, so the tests don't depend on the bundled Discogs file.
    private let taxonomy = GenreTaxonomy(genres: [
        (main: "Electronic", styles: ["Techno", "Ambient", "Dubstep"]),
        (main: "Jazz", styles: ["Hard Bop", "Modal"])
    ])

    private func album(_ id: String, genres: [String], daysAgo: Double = 0) -> AlbumID3 {
        AlbumID3(
            id: id, name: id, songCount: 1, duration: 60, coverArt: "cover-\(id)",
            created: Date(timeIntervalSinceReferenceDate: 800_000_000 - daysAgo * 86_400),
            genres: genres.map { ItemGenre(name: $0) }
        )
    }

    @Test func mainGenres_groupStylesAndCountDistinctAlbums() {
        let albums = [
            album("blue-train", genres: ["Hard Bop", "Jazz"]),
            album("kind-of-blue", genres: ["Modal", "Hard Bop"]),
            album("selected", genres: ["Ambient", "Techno"]),
            album("music-for-airports", genres: ["Ambient"])
        ]
        let summaries = GenreLibrary.summaries(from: albums, taxonomy: taxonomy)

        #expect(summaries.map(\.name) == ["Electronic", "Jazz"])
        let jazz = try! #require(summaries.first { $0.name == "Jazz" })
        // "Kind of Blue" carries two Jazz styles but counts once for Jazz.
        #expect(jazz.albumCount == 2)
        #expect(jazz.styles.map(\.name) == ["Hard Bop", "Modal"])
        #expect(jazz.styles.map(\.albumCount) == [2, 1])
        #expect(Set(jazz.tags) == ["Hard Bop", "Jazz", "Modal"])
        let electronic = try! #require(summaries.first { $0.name == "Electronic" })
        #expect(electronic.styles.map(\.name) == ["Ambient", "Techno"])
    }

    @Test func mainGenreTag_countsForTheMainButIsNoStyle() {
        let summaries = GenreLibrary.summaries(from: [album("a", genres: ["Jazz"])], taxonomy: taxonomy)
        #expect(summaries.first?.albumCount == 1)
        #expect(summaries.first?.styles.isEmpty == true)
    }

    @Test func unknownTags_goUnderOther_whichComesLast() {
        let albums = [
            album("a", genres: ["Shoegaze Revival"]),
            album("b", genres: ["Shoegaze Revival"]),
            album("c", genres: ["Techno"])
        ]
        let summaries = GenreLibrary.summaries(from: albums, taxonomy: taxonomy)
        #expect(summaries.map(\.name) == ["Electronic", GenreTaxonomy.otherGenre])
        #expect(summaries.last?.isOther == true)
        #expect(summaries.last?.styles.map(\.name) == ["Shoegaze Revival"])
    }

    @Test func spellingVariants_shareOneStyleAndKeepEveryTag() {
        let albums = [album("a", genres: ["Hard Bop"]), album("b", genres: ["hard bop"])]
        let jazz = GenreLibrary.summaries(from: albums, taxonomy: taxonomy).first
        #expect(jazz?.styles.count == 1)
        #expect(jazz?.styles.first?.albumCount == 2)
        #expect(Set(jazz?.styles.first?.tags ?? []) == ["Hard Bop", "hard bop"])
    }

    @Test func cover_isTheNewestAlbums() {
        let albums = [album("old", genres: ["Techno"], daysAgo: 30), album("new", genres: ["Techno"], daysAgo: 1)]
        let electronic = GenreLibrary.summaries(from: albums, taxonomy: taxonomy).first
        #expect(electronic?.coverArtId == "cover-new")
        #expect(electronic?.styles.first?.coverArtId == "cover-new")
    }

    @Test func albumHasAnyOf_ignoresCaseAndSpacing() {
        let blueTrain = album("blue-train", genres: ["Hard Bop", "Jazz"])
        #expect(GenreLibrary.album(blueTrain, hasAnyOf: ["hard bop "]))
        #expect(!GenreLibrary.album(blueTrain, hasAnyOf: ["Modal"]))
    }

    @Test func tags_preferOpenSubsonicGenresAndDropDuplicates() {
        let both = AlbumID3(id: "x", name: "x", songCount: 1, duration: 1, genre: "Legacy",
                            genres: [ItemGenre(name: "Jazz"), ItemGenre(name: " jazz "), ItemGenre(name: "")])
        #expect(GenreLibrary.tags(of: both) == ["Jazz"])
        let legacy = AlbumID3(id: "y", name: "y", songCount: 1, duration: 1, genre: "Rock")
        #expect(GenreLibrary.tags(of: legacy) == ["Rock"])
    }
}
