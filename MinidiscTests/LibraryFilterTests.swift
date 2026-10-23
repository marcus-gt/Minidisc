import Testing
@testable import Minidisc

@Suite("LibraryFilter")
struct LibraryFilterTests {
    private let names = ["Sigur Rós", "Röyksopp", "Boards of Canada"]

    @Test func filter_blankQuery_returnsEverything() {
        #expect(LibraryFilter.filter(names, by: "   ") { [$0] } == names)
    }

    @Test func filter_ignoresCaseDiacriticsAndSurroundingSpaces() {
        #expect(LibraryFilter.filter(names, by: " ROS ") { [$0] } == ["Sigur Rós"])
        #expect(LibraryFilter.filter(names, by: "royk") { [$0] } == ["Röyksopp"])
    }

    @Test func filter_matchesAnyField_andSkipsMissingOnes() {
        let items: [(title: String, artist: String?)] = [("Roygbiv", "Boards of Canada"), ("Untitled", nil)]

        let matches = LibraryFilter.filter(items, by: "canada") { [$0.title, $0.artist] }

        #expect(matches.map(\.title) == ["Roygbiv"])
    }

    @Test func query_trimsAndTreatsBlankAsNoFilter() {
        #expect(LibraryFilter.query("  ") == nil)
        #expect(LibraryFilter.query(" jazz ") == "jazz")
    }
}
