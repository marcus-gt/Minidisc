import Testing
@testable import Minidisc

/// maekster no longer creates Wrapped playlists (#69); the names are still recognised.
@Suite("WrappedPlaylistService legacy Minidisc names")
struct WrappedLegacyPlaylistNameTests {

    @Test func year_parsesCurrentAndLegacyNamesOnly() {
        #expect(WrappedPlaylistService.playlistName(year: 2026) == "maekster Wrapped 2026")
        #expect(WrappedPlaylistService.year(fromPlaylistName: "maekster Wrapped 2026") == 2026)
        #expect(WrappedPlaylistService.year(fromPlaylistName: "Minidisc Wrapped 2024") == 2024)
        #expect(WrappedPlaylistService.year(fromPlaylistName: "Minidisc Wrapped best of") == nil)
        #expect(WrappedPlaylistService.year(fromPlaylistName: "Wrapped 2026") == nil)
    }

}
