import Foundation
import SwiftData

/// Singleton session (id = "current"). Duplicated track metadata renders the mini-player
/// before the saved queue is decoded.
@Model
final class PlaybackSession {
    @Attribute(.unique) var id: String
    var currentIndex: Int
    var currentPosition: TimeInterval
    var queueData: Data

    var currentTrackId: String?
    var currentTrackTitle: String?
    var currentTrackArtist: String?
    var currentTrackCoverArtId: String?
    var currentTrackDuration: TimeInterval
    var currentTrackIsDownloaded: Bool

    var lastUpdated: Date
    var repeatModeRaw: String = RepeatMode.off.rawValue
    /// The queue's source as JSON (#71); nil for sessions saved before it existed.
    var queueSourceData: Data?
    /// Where auto-extended tracks begin, so "Similar to" survives a relaunch.
    var originalQueueEndIndex: Int?

    init(
        currentIndex: Int = 0,
        currentPosition: TimeInterval = 0,
        queue: [DisplayableSong] = [],
        currentTrack: DisplayableSong? = nil,
        repeatMode: RepeatMode = .off
    ) {
        self.id = "current"
        self.currentIndex = currentIndex
        self.currentPosition = currentPosition
        self.queueData = (try? JSONEncoder().encode(queue)) ?? Data()
        self.currentTrackId = currentTrack?.id
        self.currentTrackTitle = currentTrack?.title
        self.currentTrackArtist = currentTrack?.artist
        self.currentTrackCoverArtId = currentTrack?.coverArtId
        self.currentTrackDuration = currentTrack?.duration ?? 0
        self.currentTrackIsDownloaded = currentTrack?.isDownloaded ?? false
        self.lastUpdated = Date()
        self.repeatModeRaw = repeatMode.rawValue
    }

    func decodedQueue() -> [DisplayableSong] {
        (try? JSONDecoder().decode([DisplayableSong].self, from: queueData)) ?? []
    }

    func decodedRepeatMode() -> RepeatMode {
        RepeatMode(rawValue: repeatModeRaw) ?? .off
    }

    func decodedQueueSource() -> QueueSource? {
        queueSourceData.flatMap { try? JSONDecoder().decode(QueueSource.self, from: $0) }
    }

    func update(
        currentIndex: Int,
        currentPosition: TimeInterval,
        queue: [DisplayableSong],
        currentTrack: DisplayableSong?,
        repeatMode: RepeatMode,
        queueSource: QueueSource?,
        originalQueueEndIndex: Int?
    ) {
        self.queueSourceData = queueSource.flatMap { try? JSONEncoder().encode($0) }
        self.originalQueueEndIndex = originalQueueEndIndex
        self.currentIndex = currentIndex
        self.currentPosition = currentPosition
        self.queueData = (try? JSONEncoder().encode(queue)) ?? Data()
        self.currentTrackId = currentTrack?.id
        self.currentTrackTitle = currentTrack?.title
        self.currentTrackArtist = currentTrack?.artist
        self.currentTrackCoverArtId = currentTrack?.coverArtId
        self.currentTrackDuration = currentTrack?.duration ?? 0
        self.currentTrackIsDownloaded = currentTrack?.isDownloaded ?? false
        self.lastUpdated = Date()
        self.repeatModeRaw = repeatMode.rawValue
    }
}
