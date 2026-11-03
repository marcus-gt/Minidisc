import Foundation

/// A radio built from a list of picks (#60, #69): the first part queues at once, the rest arrives
/// through the player's refill as the queue runs low, and once the picks run out it carries on with
/// similar songs (Navidrome's Instant Mix, so AudioMuse when the server has it) around the seeds.
nonisolated enum RadioQueue {
    /// Queued up front.
    static let initialCount = 50

    static func initialTracks(_ tracks: [DisplayableSong]) -> [DisplayableSong] {
        Array(tracks.prefix(initialCount))
    }

    static func refill(after tracks: [DisplayableSong], seedIDs: [String], library: any PlaybackQueueBuilding) -> QueueRefill {
        let rest = Array(tracks.dropFirst(initialCount))
        return { excluded, count in
            let next = rest.lazy.filter { !excluded.contains($0.id) }.prefix(count)
            if !next.isEmpty { return Array(next) }
            for seed in seedIDs.shuffled() {
                try Task.checkCancellation()
                let similar = try await library.instantMix(from: .song(id: seed), count: count * 2)
                    .filter { !excluded.contains($0.id) }
                if !similar.isEmpty { return Array(similar.prefix(count)) }
            }
            return []
        }
    }
}

extension Array {
    /// A shuffle where heavier elements tend to come first (Efraimidis–Spirakis): each draws
    /// `u^(1/weight)` and the largest draws lead. A track played ten times usually comes early, one
    /// played once can still turn up anywhere.
    nonisolated func weightedShuffled(weight: (Element) -> Double,
                                      using generator: inout some RandomNumberGenerator) -> [Element] {
        map { element in (element, pow(Double.random(in: Double.ulpOfOne..<1, using: &generator), 1 / Swift.max(weight(element), 1))) }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }
}
