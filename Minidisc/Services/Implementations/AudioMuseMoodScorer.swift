import Foundation
import OSLog

/// Mood scores for the Queue Builder. Absent from the builder when AudioMuse is not set up.
nonisolated protocol MoodScoring: Sendable {
    /// Whether AudioMuse is configured for the active server, so the mood section should show.
    func isAvailable() async -> Bool
    /// Scores for the given song IDs. Songs AudioMuse never analysed are simply missing.
    /// Throws when AudioMuse cannot be reached at all, so the caller can build without moods.
    func scores(for songIDs: [String]) async throws -> [String: AudioMuseMoodScores]
}

/// Fetches per-track mood scores from AudioMuse (`/external/get_score`), five at a time, and keeps
/// them in a per-server disk cache: a track's analysis does not change, so each is fetched once.
actor AudioMuseMoodScorer: MoodScoring {
    static let maxConcurrentRequests = 5

    private let serverService: any ServerServiceProtocol
    private let cacheDirectory: URL
    private let session: URLSession

    private var client: (key: String, client: AudioMuseClient)?
    private var cache: [String: AudioMuseMoodScores] = [:]
    private var cacheServerID: UUID?
    /// Tracks AudioMuse has no analysis for, this session; asked again after a relaunch.
    private var notAnalysed: Set<String> = []

    init(
        serverService: any ServerServiceProtocol,
        cacheDirectory: URL = URL.cachesDirectory.appendingPathComponent("minidisc-audiomuse-moods", isDirectory: true),
        session: URLSession = .shared
    ) {
        self.serverService = serverService
        self.cacheDirectory = cacheDirectory
        self.session = session
    }

    func isAvailable() async -> Bool {
        guard let connection = try? await serverService.activeConnection() else { return false }
        return connection.server.audioMuseURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    func scores(for songIDs: [String]) async throws -> [String: AudioMuseMoodScores] {
        let connection = try await serverService.activeConnection()
        let serverID = connection.server.id
        guard let urlString = connection.server.audioMuseURL,
              let client = client(urlString: urlString, token: connection.credentials.audioMuseToken)
        else { throw AudioMuseError.badURL }
        loadCacheIfNeeded(serverID: serverID)

        let wanted = songIDs.filter { cache[$0] == nil && !notAnalysed.contains($0) }
        if !wanted.isEmpty {
            let fetched = try await fetch(wanted, with: client)
            // A server switch during the requests must not mix its scores into another server's cache.
            guard await serverService.activeConnectionVersion()?.serverID == serverID, cacheServerID == serverID else {
                throw CancellationError()
            }
            for (id, scores) in fetched.scores { cache[id] = scores }
            notAnalysed.formUnion(fetched.notAnalysed)
            if !fetched.scores.isEmpty { saveCache(serverID: serverID) }
            Logger.library.info("[QUEUE-BUILDER] AudioMuse scores: \(fetched.scores.count, privacy: .public) fetched, \(fetched.notAnalysed.count, privacy: .public) not analysed, \(songIDs.count - wanted.count, privacy: .public) cached")
        }
        return songIDs.reduce(into: [:]) { result, id in
            if let scores = cache[id] { result[id] = scores }
        }
    }

    // MARK: - Requests

    private func fetch(
        _ ids: [String],
        with client: AudioMuseClient
    ) async throws -> (scores: [String: AudioMuseMoodScores], notAnalysed: Set<String>) {
        var scores: [String: AudioMuseMoodScores] = [:]
        var missing = Set<String>()
        var firstFailure: (any Error)?

        try await withThrowingTaskGroup(of: (String, Result<AudioMuseMoodScores, any Error>).self) { group in
            var pending = ids[...]
            func addNext() {
                guard let id = pending.popFirst() else { return }
                group.addTask {
                    do {
                        return (id, .success(try await client.moodScores(itemId: id)))
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        return (id, .failure(error))
                    }
                }
            }
            for _ in 0..<Self.maxConcurrentRequests { addNext() }
            while let (id, result) = try await group.next() {
                switch result {
                case .success(let value):
                    scores[id] = value
                case .failure(AudioMuseError.notFound):
                    missing.insert(id)
                case .failure(let error):
                    firstFailure = firstFailure ?? error
                }
                addNext()
            }
        }
        // Nothing answered: AudioMuse is down or rejected us. A few failures among answers are tolerated.
        if scores.isEmpty, missing.isEmpty, let firstFailure { throw firstFailure }
        return (scores, missing)
    }

    private func client(urlString: String, token: String?) -> AudioMuseClient? {
        let key = "\(urlString)|\(token ?? "")"
        if let client, client.key == key { return client.client }
        guard let made = AudioMuseClient(urlString: urlString, token: token, session: session) else { return nil }
        client = (key, made)
        return made
    }

    // MARK: - Disk cache

    private func cacheFile(serverID: UUID) -> URL {
        // v2 adds the style labels; older files lack them and are simply refetched.
        cacheDirectory.appendingPathComponent("v2-\(serverID.uuidString).json")
    }

    private func loadCacheIfNeeded(serverID: UUID) {
        guard cacheServerID != serverID else { return }
        cacheServerID = serverID
        notAnalysed = []
        cache = (try? Data(contentsOf: cacheFile(serverID: serverID)))
            .flatMap { try? JSONDecoder().decode([String: AudioMuseMoodScores].self, from: $0) } ?? [:]
    }

    private func saveCache(serverID: UUID) {
        do {
            try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            try JSONEncoder().encode(cache).write(to: cacheFile(serverID: serverID), options: .atomic)
        } catch {
            Logger.library.warning("[QUEUE-BUILDER] could not save AudioMuse scores: \(error, privacy: .public)")
        }
    }
}
