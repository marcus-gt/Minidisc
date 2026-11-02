import Testing
@testable import Minidisc

/// When the next queue item starts caching ahead (#56).
@Suite("PlayerService.shouldCacheNextTrack")
struct NextTrackCacheTests {
    private func should(position: Double = 60, duration: Double = 240, crossfade: Double = 0,
                        next: String? = "next", lastTried: String? = nil,
                        repeatOne: Bool = false, busy: Bool = false) -> Bool {
        PlayerService.shouldCacheNextTrack(position: position, duration: duration, crossfadeDuration: crossfade,
                                           nextSongID: next, lastTriedSongID: lastTried,
                                           isRepeatOne: repeatOne, isBusy: busy)
    }

    @Test func startsOnceTheCurrentTrackHasPlayedAWhile() {
        #expect(should())
        #expect(should(position: 30))
        #expect(!should(position: 29.9))
    }

    /// One download at a time: the current track's own cache, or a next one already running, comes first.
    @Test func waitsForTheRunningDownload() {
        #expect(!should(busy: true))
    }

    @Test func triesEachUpcomingSongOnce() {
        #expect(!should(lastTried: "next"))
        #expect(should(lastTried: "previous next"))
    }

    @Test func staysOutOfTheHandOffWindow() {
        #expect(!should(position: 210, duration: 240))
        #expect(should(position: 209, duration: 240))
        // The crossfade widens the window.
        #expect(!should(position: 200, duration: 240, crossfade: 10))
    }

    @Test func nothingToCacheWithoutANextSongOrUnderRepeatOne() {
        #expect(!should(next: nil))
        #expect(!should(repeatOne: true))
        #expect(!should(duration: 0))
    }
}
