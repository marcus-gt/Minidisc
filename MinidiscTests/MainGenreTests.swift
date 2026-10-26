import Foundation
import SwiftSonic
import Testing
@testable import Minidisc

@Suite("Main genre (#29)")
struct MainGenreTests {
    @Test func allTrapMusic_belongsToDubstepNotAmbient() {
        // The tag counts on "All Trap Music": Dubstep 13, Ambient 10, Trap 1 (of 21 tracks).
        var tracks: [[String]] = []
        tracks += Array(repeating: ["Dubstep", "Ambient", "Electronic"], count: 10)
        tracks += Array(repeating: ["Dubstep", "Edm"], count: 3)
        tracks += [["Trap", "Hip Hop"]] + Array(repeating: ["Grime"], count: 7)
        #expect(MainGenre.of(trackGenres: tracks, albumGenres: ["Ambient", "Dubstep"]) == "Dubstep")
    }

    @Test func tie_goesToTheAlbumsOwnTagOrder() {
        let tracks = [["Jazz"], ["Soul"]]
        #expect(MainGenre.of(trackGenres: tracks, albumGenres: ["Soul", "Jazz"]) == "Soul")
        #expect(MainGenre.of(trackGenres: tracks, albumGenres: []) == "Jazz")
    }

    @Test func spellings_mergeAndKeepTheFirstOne() {
        let tracks = [["Hip Hop"], ["hip hop "], ["HIP HOP"], ["Jazz"]]
        #expect(MainGenre.of(trackGenres: tracks, albumGenres: []) == "Hip Hop")
    }

    @Test func repeatedTagOnATrack_countsOnce() {
        let tracks = [["Rock", "Rock", "rock"], ["Jazz"], ["Jazz"]]
        #expect(MainGenre.of(trackGenres: tracks, albumGenres: []) == "Jazz")
    }

    @Test func untaggedTracks_fallBackToTheAlbumTag() {
        #expect(MainGenre.of(trackGenres: [[], []], albumGenres: [" ", "Ambient"]) == "Ambient")
        #expect(MainGenre.of(trackGenres: [], albumGenres: []) == nil)
        #expect(MainGenre.of(trackGenres: [[" "]], albumGenres: [""]) == nil)
    }
}

@Suite("Home genre shelves (#29)")
struct HomeGenreShelvesTests {
    private func albums(_ prefix: String, _ count: Int) throws -> [AlbumID3] {
        try (0..<count).map { index in
            try JSONDecoder().decode(AlbumID3.self, from: Data(
                #"{"id":"\#(prefix)\#(index)","name":"\#(prefix) \#(index)","songCount":1,"duration":100}"#.utf8
            ))
        }
    }

    @Test func shelves_areTheBiggestMainGenres() throws {
        let map: [String: [AlbumID3]] = [
            "Jazz": try albums("j", 30), "Techno": try albums("t", 25), "Rock": try albums("r", 10),
            "Ambient": try albums("a", 10), "House": try albums("h", 9), "Folk": try albums("f", 2),
            "Empty": []
        ]
        let shelves = HomeGenreShelves.shelves(byMainGenre: map, day: "2026-10-26")
        // Ambient and Rock tie at 10: alphabetical.
        #expect(shelves.map(\.name) == ["Jazz", "Techno", "Ambient", "Rock", "House"])
        #expect(shelves.allSatisfy { $0.albums.count <= HomeGenreShelves.albumsPerShelf })
        #expect(shelves[0].albums.count == 20)
    }

    @Test func dailyPick_isStableWithinADayAndIndependentOfInputOrder() throws {
        let all = try albums("x", 60)
        let first = HomeGenreShelves.dailyPick(all, genre: "Jazz", day: "2026-10-26")
        let again = HomeGenreShelves.dailyPick(all.reversed(), genre: "jazz", day: "2026-10-26")
        #expect(first.map(\.id) == again.map(\.id))
        #expect(Set(first.map(\.id)).count == 20)
    }

    @Test func dailyPick_changesFromDayToDay() throws {
        let all = try albums("x", 60)
        let days = ["2026-10-26", "2026-10-27", "2026-10-28"]
        let picks = days.map { HomeGenreShelves.dailyPick(all, genre: "Jazz", day: $0).map(\.id) }
        #expect(Set(picks).count > 1)
    }

    @Test func dailyPick_isNotAlphabetical() throws {
        let all = try albums("x", 60)
        let pick = HomeGenreShelves.dailyPick(all, genre: "Jazz", day: "2026-10-26")
        #expect(pick.map(\.id) != Array(all.sorted { $0.name < $1.name }.prefix(20)).map(\.id))
    }

    @Test func dayKey_usesTheLocalCalendarDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Oslo")!
        // 23:30 UTC on 26 October is already 00:30 on the 27th in Oslo; the local day wins.
        let justAfterMidnightInOslo = Date(timeIntervalSince1970: 1_793_057_400)
        #expect(HomeGenreShelves.dayKey(for: justAfterMidnightInOslo, calendar: calendar) == "2026-10-27")
    }
}
