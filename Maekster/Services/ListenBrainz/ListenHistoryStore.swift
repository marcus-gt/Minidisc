import Foundation
import OSLog

/// A user's ListenBrainz listens, cached per calendar month on disk (#16).
///
/// A month that has ended (plus a couple of days for late submissions) is fetched once and kept; the
/// current month only fetches listens newer than its newest cached one, usually a single request.
/// Fetching walks backwards with `max_ts` in pages of 1,000 and pauses when ListenBrainz asks it to.
actor ListenHistoryStore {
    typealias PageFetch = @Sendable (_ user: String, _ maxTs: Int) async throws -> [LBListen]
    typealias OldestFetch = @Sendable (_ user: String) async throws -> LBListen?
    /// Listens fetched so far in the current request, for the first load of a long range.
    typealias Progress = @Sendable (_ fetched: Int) -> Void

    /// Listens can arrive after the fact (offline players, imports); a month counts as final after this.
    static let lateSubmissionGrace: TimeInterval = 2 * 86_400
    static let maxRateLimitRetries = 3

    nonisolated struct MonthKey: Hashable, Comparable, Sendable {
        let year: Int
        let month: Int
        static func < (lhs: MonthKey, rhs: MonthKey) -> Bool { (lhs.year, lhs.month) < (rhs.year, rhs.month) }
        var fileName: String { String(format: "%04d-%02d.json", year, month) }
    }

    private struct MonthFile: Codable {
        var listens: [LBListen]
        var complete: Bool
    }

    private let directory: URL
    private let fetchPage: PageFetch
    private let fetchOldest: OldestFetch
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (TimeInterval) async throws -> Void
    private var oldestByUser: [String: Int] = [:]

    init(
        directory: URL,
        fetchPage: @escaping PageFetch,
        fetchOldest: @escaping OldestFetch,
        now: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }
    ) {
        self.directory = directory
        self.fetchPage = fetchPage
        self.fetchOldest = fetchOldest
        self.now = now
        self.sleep = sleep
    }

    // MARK: - Reading

    /// Every listen in `[start, end)`, newest first. `refresh` refetches months already held as final.
    func listens(user: String, from start: Date, to end: Date, calendar: Calendar, refresh: Bool = false,
                 progress: Progress? = nil) async throws -> [LBListen] {
        let months = Self.months(from: start, to: min(end, now()), calendar: calendar)
        guard !months.isEmpty else { return [] }
        let cached = Dictionary(uniqueKeysWithValues: months.map { ($0, load(user: user, month: $0)) })
        let missing = months.filter { refresh || cached[$0]??.complete != true }

        if let newest = missing.max(), let oldest = missing.min() {
            let upper = min(Self.end(of: newest, calendar: calendar), now())
            let lower = Self.start(of: oldest, calendar: calendar)
            // Only the newest month missing, with some of it cached: stop at what's already held.
            let stopAt = missing.count == 1 && !refresh
                ? cached[newest]??.listens.map(\.listenedAt).max()
                : nil
            let fetched = try await walk(user: user, upper: upper, lower: lower, stopAt: stopAt, progress: progress)
            for month in missing {
                let range = (Self.start(of: month, calendar: calendar), Self.end(of: month, calendar: calendar))
                let inMonth = fetched.filter { Self.contains(range, $0) }
                let kept = refresh ? [] : (cached[month]??.listens ?? [])
                let merged = Self.deduplicated(inMonth + kept)
                let complete = range.1.addingTimeInterval(Self.lateSubmissionGrace) < now()
                save(MonthFile(listens: merged, complete: complete), user: user, month: month)
            }
        }

        let range = (start, end)
        return months
            .flatMap { load(user: user, month: $0)?.listens ?? [] }
            .filter { Self.contains(range, $0) }
            .sorted { $0.listenedAt > $1.listenedAt }
    }

    /// The year of the first listen, so Wrapped knows how far back to offer. Asked once per user.
    func firstYear(user: String, calendar: Calendar) async throws -> Int? {
        if let cached = oldestByUser[user] ?? storedOldest(user: user) {
            oldestByUser[user] = cached
            return calendar.component(.year, from: Date(timeIntervalSince1970: TimeInterval(cached)))
        }
        guard let oldest = try await fetchOldest(user) else { return nil }
        oldestByUser[user] = oldest.listenedAt
        storeOldest(oldest.listenedAt, user: user)
        return calendar.component(.year, from: Date(timeIntervalSince1970: TimeInterval(oldest.listenedAt)))
    }

    // MARK: - Fetching

    /// Listens from `upper` back to `lower`, stopping early at `stopAt` (exclusive), newest first.
    private func walk(user: String, upper: Date, lower: Date, stopAt: Int?, progress: Progress?) async throws -> [LBListen] {
        var collected: [LBListen] = []
        var maxTs = Int(upper.timeIntervalSince1970) + 1
        let floor = Int(lower.timeIntervalSince1970)
        var requests = 0
        var retries = 0
        while true {
            try Task.checkCancellation()
            let page: [LBListen]
            do {
                page = try await fetchPage(user, maxTs)
                retries = 0
            } catch ListenBrainzError.rateLimited(let wait) {
                retries += 1
                guard retries <= Self.maxRateLimitRetries else { throw ListenBrainzError.rateLimited(retryAfter: wait) }
                try await sleep(max(1, wait ?? 5))
                continue
            }
            requests += 1
            guard !page.isEmpty else { break }
            var reachedEnd = false
            for listen in page {
                if listen.listenedAt < floor || (stopAt.map { listen.listenedAt <= $0 } ?? false) {
                    reachedEnd = true
                    break
                }
                collected.append(listen)
            }
            progress?(collected.count)
            guard !reachedEnd, let last = page.last, last.listenedAt < maxTs else { break }
            maxTs = last.listenedAt
        }
        Logger.listenBrainz.info("[HISTORY] fetched \(collected.count, privacy: .public) listens in \(requests, privacy: .public) requests")
        return collected
    }

    // MARK: - Months

    nonisolated static func months(from start: Date, to end: Date, calendar: Calendar) -> [MonthKey] {
        guard start < end else { return [] }
        var result: [MonthKey] = []
        var cursor = calendar.dateInterval(of: .month, for: start)?.start ?? start
        while cursor < end {
            let parts = calendar.dateComponents([.year, .month], from: cursor)
            if let year = parts.year, let month = parts.month { result.append(MonthKey(year: year, month: month)) }
            guard let next = calendar.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    nonisolated static func start(of month: MonthKey, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: month.year, month: month.month, day: 1)) ?? .distantPast
    }

    nonisolated static func end(of month: MonthKey, calendar: Calendar) -> Date {
        calendar.date(byAdding: .month, value: 1, to: start(of: month, calendar: calendar)) ?? .distantFuture
    }

    private nonisolated static func contains(_ range: (Date, Date), _ listen: LBListen) -> Bool {
        let date = Date(timeIntervalSince1970: TimeInterval(listen.listenedAt))
        return date >= range.0 && date < range.1
    }

    /// One listen per timestamp, track and artist: page boundaries and partial months can overlap.
    nonisolated static func deduplicated(_ listens: [LBListen]) -> [LBListen] {
        var seen = Set<String>()
        return listens.filter { seen.insert("\($0.listenedAt)|\($0.trackName)|\($0.artistName)").inserted }
    }

    // MARK: - Disk

    private func userDirectory(_ user: String) -> URL {
        // Usernames are [A-Za-z0-9_.-]; anything else would only come from a bug, never a path.
        let safe = user.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || "_.-".unicodeScalars.contains($0) }
        return directory.appendingPathComponent(String(String.UnicodeScalarView(safe)), isDirectory: true)
    }

    private func load(user: String, month: MonthKey) -> MonthFile? {
        let url = userDirectory(user).appendingPathComponent(month.fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(MonthFile.self, from: data)
    }

    private func save(_ file: MonthFile, user: String, month: MonthKey) {
        let folder = userDirectory(user)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try JSONEncoder().encode(file).write(to: folder.appendingPathComponent(month.fileName), options: .atomic)
        } catch {
            Logger.listenBrainz.warning("[HISTORY] could not cache a month: \(error, privacy: .public)")
        }
    }

    private func storedOldest(user: String) -> Int? {
        guard let data = try? Data(contentsOf: userDirectory(user).appendingPathComponent("oldest.json")) else { return nil }
        return try? JSONDecoder().decode(Int.self, from: data)
    }

    private func storeOldest(_ timestamp: Int, user: String) {
        let folder = userDirectory(user)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? JSONEncoder().encode(timestamp).write(to: folder.appendingPathComponent("oldest.json"), options: .atomic)
    }
}
