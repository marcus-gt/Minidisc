import Foundation

/// A mood the Queue Builder can rank by, backed by AudioMuse's per-track scores (`other_features`).
/// Raw values are AudioMuse's own keys.
nonisolated enum QueueBuilderMood: String, CaseIterable, Codable, Identifiable, Hashable, Sendable {
    case happy
    case sad
    case relaxed
    case aggressive
    case party
    case danceable

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .happy: "Happy"
        case .sad: "Sad"
        case .relaxed: "Relaxed"
        case .aggressive: "Aggressive"
        case .party: "Party"
        case .danceable: "Danceable"
        }
    }
}

extension QueueBuilderMood {
    /// AudioMuse's scores sit close together (one song scored 0.56–0.65 on all six), so moods rank
    /// candidates instead of filtering them: the average of the picked moods, highest first. Songs
    /// AudioMuse never analysed are left out once a mood is picked.
    nonisolated static func rank<Song: Identifiable>(
        _ candidates: [Song],
        scores: [Song.ID: AudioMuseMoodScores],
        moods: Set<QueueBuilderMood>,
        keeping count: Int
    ) -> [Song] {
        guard !moods.isEmpty else { return Array(candidates.prefix(count)) }
        let scored: [(song: Song, score: Double)] = candidates.compactMap { song in
            guard let values = scores[song.id]?.values else { return nil }
            let picked = moods.compactMap { values[$0.rawValue] }
            guard picked.count == moods.count else { return nil }
            return (song, picked.reduce(0, +) / Double(picked.count))
        }
        return scored
            .sorted { $0.score > $1.score }
            .prefix(count)
            .map(\.song)
    }
}
