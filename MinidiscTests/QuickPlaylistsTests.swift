import Foundation
import Testing
@testable import Minidisc

@Suite("Quick playlists (#68)")
@MainActor
struct QuickPlaylistsTests {
    private func store() -> (QuickPlaylists, UserDefaults) {
        let defaults = UserDefaults(suiteName: "quick-playlists.\(UUID())")!
        return (QuickPlaylists(defaults: defaults), defaults)
    }

    @Test func toggle_addsInOrderAndRemoves() {
        let (quick, _) = store()
        quick.toggle(id: "jazz", name: "Jazz tunes", serverID: "s")
        quick.toggle(id: "techno", name: "Techno – chill", serverID: "s")
        #expect(quick.entries(serverID: "s").map(\.id) == ["jazz", "techno"])
        #expect(quick.contains("jazz", serverID: "s"))
        quick.toggle(id: "jazz", name: "Jazz tunes", serverID: "s")
        #expect(quick.entries(serverID: "s").map(\.id) == ["techno"])
    }

    @Test func lists_arePerServerAndSurviveARelaunch() {
        let (quick, defaults) = store()
        quick.toggle(id: "jazz", name: "Jazz tunes", serverID: "home")
        #expect(quick.entries(serverID: "work").isEmpty)
        let relaunched = QuickPlaylists(defaults: defaults)
        #expect(relaunched.entries(serverID: "home") == [QuickPlaylists.Entry(id: "jazz", name: "Jazz tunes")])
    }

    @Test func moveAndDelete_keepTheChosenOrder() {
        let (quick, _) = store()
        for id in ["a", "b", "c"] { quick.toggle(id: id, name: id.uppercased(), serverID: "s") }
        quick.move(fromOffsets: [2], toOffset: 0, serverID: "s")
        #expect(quick.entries(serverID: "s").map(\.id) == ["c", "a", "b"])
        quick.remove(atOffsets: [1], serverID: "s")
        #expect(quick.entries(serverID: "s").map(\.id) == ["c", "b"])
    }

    /// The server's list renames entries and drops playlists that were deleted.
    @Test func reconcile_followsRenamesAndDeletions() {
        let (quick, _) = store()
        quick.toggle(id: "jazz", name: "Jazz", serverID: "s")
        quick.toggle(id: "gone", name: "Old", serverID: "s")
        quick.reconcile(with: [(id: "jazz", name: "Jazz tunes"), (id: "other", name: "Other")], serverID: "s")
        #expect(quick.entries(serverID: "s") == [QuickPlaylists.Entry(id: "jazz", name: "Jazz tunes")])
    }

    @Test func alsoLikes_defaultsToOnAndIsRemembered() {
        let (quick, defaults) = store()
        #expect(quick.alsoLikes)
        quick.alsoLikes = false
        #expect(QuickPlaylists(defaults: defaults).alsoLikes == false)
    }
}
