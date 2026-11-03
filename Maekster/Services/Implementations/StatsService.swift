import Foundation
import SwiftData
import OSLog

/// Stores playback events on a private ModelContext; only DTOs leave the actor.
actor StatsService {
    private let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    // MARK: - Public API

    func recordPlayback(_ event: PlaybackEventDTO, trigger: String = "") async {
        let context = ModelContext(modelContainer)
        let model = PlaybackEvent(
            trackId: event.trackId,
            trackTitle: event.trackTitle,
            albumId: event.albumId,
            albumTitle: event.albumTitle,
            artistId: event.artistId,
            artistName: event.artistName,
            genre: event.genre,
            timestamp: event.timestamp,
            durationListened: event.durationListened,
            trackDuration: event.trackDuration,
            wasCompleted: event.wasCompleted,
            serverId: event.serverId
        )
        context.insert(model)
        do {
            try context.save()
            let artistIdForLog = event.artistId ?? "nil"
            let durationForLog = String(format: "%.1f", event.durationListened)
            Logger.stats.debug(
                "[INSERT] trigger=\(trigger, privacy: .public) trackId=\(event.trackId, privacy: .public) artistId=\(artistIdForLog, privacy: .public) durationListened=\(durationForLog, privacy: .public)s startedAt=\(event.timestamp, privacy: .public) completed=\(event.wasCompleted, privacy: .public) serverId=\(event.serverId, privacy: .public)"
            )
        } catch {
            Logger.stats.error("Failed to save playback event: \(error, privacy: .public)")
        }
    }

    func eventCount(forServer serverId: String) async -> Int {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<PlaybackEvent>(
            predicate: #Predicate { $0.serverId == serverId }
        )
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    /// Most recent playback events (≥30s listens, as recorded), newest first.
    /// Returns Sendable DTOs — PlaybackEvent instances never leave this actor.
    func recentEvents(limit: Int, serverId: String) async -> [PlaybackEventDTO] {
        let context = ModelContext(modelContainer)
        var descriptor = FetchDescriptor<PlaybackEvent>(
            predicate: #Predicate { $0.serverId == serverId },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        let events = (try? context.fetch(descriptor)) ?? []
        return events.map { event in
            PlaybackEventDTO(
                trackId: event.trackId,
                trackTitle: event.trackTitle,
                albumId: event.albumId,
                albumTitle: event.albumTitle,
                artistId: event.artistId,
                artistName: event.artistName,
                genre: event.genre,
                timestamp: event.timestamp,
                durationListened: event.durationListened,
                trackDuration: event.trackDuration,
                wasCompleted: event.wasCompleted,
                serverId: event.serverId
            )
        }
    }

    func deleteAllEvents(forServer serverId: String) async {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<PlaybackEvent>(
            predicate: #Predicate { $0.serverId == serverId }
        )
        do {
            let events = try context.fetch(descriptor)
            guard !events.isEmpty else { return }
            for event in events {
                context.delete(event)
            }
            try context.save()
            Logger.stats.info("Deleted \(events.count) event(s) for serverId=\(serverId, privacy: .public)")
        } catch {
            Logger.stats.error("Failed to delete events for serverId=\(serverId, privacy: .public): \(error, privacy: .public)")
        }
    }

    // MARK: - Wrapped aggregation

    func hasEventsInPeriod(_ period: WrappedPeriod, serverId: String, calendar: Calendar) async -> Bool {
        let range = period.dateRange(in: calendar)
        let start = range.start
        let end = range.end
        let sid = serverId
        let context = ModelContext(modelContainer)
        var descriptor = FetchDescriptor<PlaybackEvent>(
            predicate: #Predicate { $0.serverId == sid && $0.timestamp >= start && $0.timestamp < end }
        )
        descriptor.fetchLimit = 1
        return ((try? context.fetchCount(descriptor)) ?? 0) > 0
    }

    func wrappedData(for period: WrappedPeriod, serverId: String, calendar: Calendar) async -> WrappedData {
        #if DEBUG
        let t0 = CFAbsoluteTimeGetCurrent()
        #endif

        let range = period.dateRange(in: calendar)
        let start = range.start
        let end = range.end
        let sid = serverId
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<PlaybackEvent>(
            predicate: #Predicate { $0.serverId == sid && $0.timestamp >= start && $0.timestamp < end }
        )

        let events: [PlaybackEvent]
        do {
            events = try context.fetch(descriptor)
        } catch {
            Logger.stats.error("wrappedData fetch failed for serverId=\(sid, privacy: .public): \(error, privacy: .public)")
            events = []
        }

        let data = WrappedAggregator.aggregate(plays: events.map(Self.play), period: period, serverId: serverId,
                                               periodRange: range, calendar: calendar)

        #if DEBUG
        let elapsed = CFAbsoluteTimeGetCurrent() - t0
        Logger.stats.debug(
            "wrappedData: \(events.count, privacy: .public) events aggregated in \(String(format: "%.1f", elapsed * 1000), privacy: .public)ms period=\(period.displayName, privacy: .public)"
        )
        #endif

        return data
    }

    func topTracks(forPeriod period: WrappedPeriod, serverId: String, limit: Int, calendar: Calendar) async -> [TopTrackEntry] {
        let range = period.dateRange(in: calendar)
        let start = range.start
        let end = range.end
        let sid = serverId
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<PlaybackEvent>(
            predicate: #Predicate { $0.serverId == sid && $0.timestamp >= start && $0.timestamp < end }
        )
        let events: [PlaybackEvent]
        do {
            events = try context.fetch(descriptor)
        } catch {
            Logger.stats.error("topTracks fetch failed for serverId=\(sid, privacy: .public): \(error, privacy: .public)")
            return []
        }
        return WrappedAggregator.topTracks(from: events.map(Self.play), limit: limit)
    }

    /// The local record of a play, in the shape Wrapped aggregates.
    private static func play(_ event: PlaybackEvent) -> WrappedPlay {
        WrappedPlay(
            timestamp: event.timestamp, trackId: event.trackId, trackTitle: event.trackTitle,
            albumId: event.albumId, albumTitle: event.albumTitle, artistId: event.artistId,
            artistName: event.artistName, genre: event.genre,
            durationListened: event.durationListened, trackDuration: event.trackDuration
        )
    }

    /// Every local play in a period, for Wrapped when ListenBrainz isn't the source.
    func plays(for period: WrappedPeriod, serverId: String, calendar: Calendar) async -> [WrappedPlay] {
        let range = period.dateRange(in: calendar)
        let start = range.start
        let end = range.end
        let sid = serverId
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<PlaybackEvent>(
            predicate: #Predicate { $0.serverId == sid && $0.timestamp >= start && $0.timestamp < end }
        )
        return ((try? context.fetch(descriptor)) ?? []).map(Self.play)
    }
}
