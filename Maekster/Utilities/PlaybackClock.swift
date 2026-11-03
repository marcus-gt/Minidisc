import Foundation

/// What the player shows as elapsed time (#4). AVPlayer's clock on an uncached raw FLAC stream is
/// estimated from an average bitrate and can run a few seconds past the song's length before the
/// audio ends. The position itself stays as reported (see `PlayerService.performProgressTick`);
/// only what's shown stops at the end.
nonisolated enum PlaybackClock {
    static func shownElapsed(_ position: TimeInterval, duration: TimeInterval) -> TimeInterval {
        let elapsed = max(position, 0)
        return duration > 0 ? min(elapsed, duration) : elapsed
    }
}
