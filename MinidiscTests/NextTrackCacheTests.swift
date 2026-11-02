import Testing
@testable import Minidisc

/// When the next queue item starts caching ahead (#56).
@Suite("PlayerService.shouldCacheNextTrack")
struct NextTrackCacheTests {
    private func should(position: Double = 60, duration: Double = 240, crossfade: Double = 0,
                        next: String? = "next", lastTried: String? = nil,
                        repeatOne: Bool = false, busy: Bool = false,
                        cellularStream: Bool = false, buffered: Double = 0) -> Bool {
        PlayerService.shouldCacheNextTrack(position: position, duration: duration, crossfadeDuration: crossfade,
                                           nextSongID: next, lastTriedSongID: lastTried,
                                           isRepeatOne: repeatOne, isBusy: busy,
                                           streamsOnCellular: cellularStream, bufferedUntil: buffered)
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

    /// On cellular the next song waits until the current stream has fully loaded (#9).
    @Test func cellularStream_waitsUntilFullyBuffered() {
        #expect(!should(cellularStream: true, buffered: 120))
        #expect(should(cellularStream: true, buffered: 239.5))
        // Playing from disk on cellular, or streaming on Wi-Fi, doesn't wait.
        #expect(should(cellularStream: false, buffered: 0))
    }
}

/// The shown elapsed time stops at the song's length (#4).
@Suite("PlaybackClock")
struct PlaybackClockTests {
    @Test func shownElapsed_stopsAtTheEnd() {
        #expect(PlaybackClock.shownElapsed(183.4, duration: 180) == 180)
        #expect(PlaybackClock.shownElapsed(90, duration: 180) == 90)
        #expect(PlaybackClock.shownElapsed(-1, duration: 180) == 0)
        // Before the length is known, the clock runs as reported.
        #expect(PlaybackClock.shownElapsed(12, duration: 0) == 12)
    }
}
