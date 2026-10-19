import Foundation
import OSLog
import SwiftSonic

/// Where the Queue Builder reads the whole library from. `LibraryCatalog` answers from its index.
nonisolated protocol QueueBuilderLibrarySource: Sendable {
    /// Changes whenever the indexed library changes; `nil` while the index is incomplete.
    func queueBuilderStamp() async throws -> String?
    func queueBuilderTracks() async throws -> [QueueBuilderTrack]?
}

extension LibraryCatalog: QueueBuilderLibrarySource {}

/// Builds Queue Builder queues (#17) from the local library index, or from the server while the
/// index is still incomplete (approximate counts, a sample of each picked genre).
actor QueueBuilderService {
    /// Server genres requested per build in approximate mode, and songs asked for per genre.
    static let fallbackGenreLimit = 12
    static let fallbackSongsPerGenre = 300

    private let source: any QueueBuilderLibrarySource
    private let library: any GenreBrowsing & MoodTrackSourcing
    private let taxonomy: GenreTaxonomy
    private var cached: (stamp: String, index: QueueBuilderIndex)?

    init(
        source: any QueueBuilderLibrarySource,
        library: any GenreBrowsing & MoodTrackSourcing,
        taxonomy: GenreTaxonomy = .discogs
    ) {
        self.source = source
        self.library = library
        self.taxonomy = taxonomy
    }

    /// The genre columns and decades to pick from. Exact once the library is indexed.
    func index() async throws -> QueueBuilderIndex {
        if let stamp = try await source.queueBuilderStamp() {
            if let cached, cached.stamp == stamp { return cached.index }
            if let tracks = try await source.queueBuilderTracks() {
                try Task.checkCancellation()
                let index = QueueBuilderIndex(tracks: tracks, taxonomy: taxonomy)
                cached = (stamp, index)
                Logger.library.info("[QUEUE-BUILDER] indexed \(tracks.count, privacy: .public) tracks into \(index.columns.count, privacy: .public) genres")
                return index
            }
        }
        let genres = try await library.genres()
        try Task.checkCancellation()
        Logger.library.info("[QUEUE-BUILDER] library index incomplete — approximate genres from the server")
        return QueueBuilderIndex(genreCounts: genres.map { ($0.value, $0.songCount) }, taxonomy: taxonomy)
    }

    /// Up to `count` shuffled songs matching `selection`, skipping `excludedIDs`.
    func buildQueue(
        _ selection: QueueBuilderSelection,
        count: Int,
        excluding excludedIDs: Set<String> = []
    ) async throws -> [Song] {
        let index = try await index()
        guard index.isApproximate else {
            return index.build(selection, count: count, excluding: excludedIDs)
        }
        let sample = try await serverSample(for: selection, index: index)
        try Task.checkCancellation()
        // Matching the sample with the same rules keeps multi-tag and decade behaviour identical.
        let tracks = sample.map { song in
            QueueBuilderTrack(song: song, genres: song.genres?.map(\.name) ?? song.genre.map { [$0] } ?? [], year: song.year)
        }
        return QueueBuilderIndex(tracks: tracks, taxonomy: taxonomy)
            .build(selection, count: count, excluding: excludedIDs)
    }

    private func serverSample(for selection: QueueBuilderSelection, index: QueueBuilderIndex) async throws -> [Song] {
        let names = Array(index.serverGenreNames(for: selection).shuffled().prefix(Self.fallbackGenreLimit))
        guard !names.isEmpty else {
            return try await library.randomSongs(size: 500)
        }
        let library = library
        var songs: [Song] = []
        try await withThrowingTaskGroup(of: [Song].self) { group in
            var pending = names[...]
            func addNext() {
                guard let name = pending.popFirst() else { return }
                group.addTask {
                    do {
                        return try await library.songsByGenre(name, count: Self.fallbackSongsPerGenre)
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        return []
                    }
                }
            }
            for _ in 0..<5 { addNext() }
            while let batch = try await group.next() {
                songs.append(contentsOf: batch)
                addNext()
            }
        }
        return songs
    }
}
