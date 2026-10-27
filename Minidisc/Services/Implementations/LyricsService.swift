import Foundation
import SwiftData
import SwiftSonic
import OSLog

/// Creates a private ModelContext for each lyrics persistence operation.
actor LyricsService {
    private let serverService: any ServerServiceProtocol
    private let modelContainer: ModelContainer
    private let lrclibClient: any LRCLIBLyricsFetching

    init(
        serverService: any ServerServiceProtocol,
        modelContainer: ModelContainer,
        lrclibClient: any LRCLIBLyricsFetching = LRCLIBClient()
    ) {
        self.serverService = serverService
        self.modelContainer = modelContainer
        self.lrclibClient = lrclibClient
    }

    // MARK: - Fetch

    /// Returns lyrics from the configured source. Cache entries remain provider-specific so changing
    /// the picker never leaks a response from a provider the user disabled.
    func fetchLyrics(
        for track: DisplayableSong,
        serverId: UUID,
        source: LyricsSource
    ) async throws -> LyricsList {
        switch source {
        case .automatic:
            let fromServer: LyricsList
            do {
                fromServer = try await fetchLyrics(for: track, serverId: serverId, provider: .navidrome)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                Logger.lyrics.info(
                    "Navidrome lyrics unavailable; trying LRCLIB — songId=\(track.id, privacy: .public)"
                )
                return try await fetchLyrics(for: track, serverId: serverId, provider: .lrclib)
            }
            // Most tagged lyrics are plain text. LRCLIB often has the same song with timings, which is
            // what makes the lyrics follow the music, so ask it too and keep the server's as a fallback.
            guard !fromServer.structuredLyrics.contains(where: \.synced) else { return fromServer }
            do {
                let fromLRCLIB = try await fetchLyrics(for: track, serverId: serverId, provider: .lrclib)
                let synced = fromLRCLIB.structuredLyrics.filter(\.synced)
                guard !synced.isEmpty else {
                    Logger.lyrics.info("LRCLIB has no timed lyrics either — songId=\(track.id, privacy: .public)")
                    return fromServer
                }
                Logger.lyrics.info("Using LRCLIB synced lyrics over the server's plain ones — songId=\(track.id, privacy: .public)")
                return LyricsList(structuredLyrics: synced + fromServer.structuredLyrics)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                Logger.lyrics.info(
                    "LRCLIB lookup for timed lyrics failed, keeping the server's — songId=\(track.id, privacy: .public): \(String(describing: error), privacy: .public)"
                )
                return fromServer
            }
        case .navidrome:
            return try await fetchLyrics(for: track, serverId: serverId, provider: .navidrome)
        case .lrclib:
            return try await fetchLyrics(for: track, serverId: serverId, provider: .lrclib)
        }
    }

    // MARK: - Language Selection

    /// Picks the best StructuredLyrics set for the given locale and optional user preference.
    ///
    /// Priority:
    /// 1. User-selected `preferred` language — synced variant if available, else unsynced.
    /// 2. A synced set: the locale's language first, then any. Lyrics that follow the music beat a
    ///    plain set in the listener's own language; only an explicit choice overrides that.
    /// 3. The locale's language, then the first set.
    ///
    /// "xxx" is normalised to "und" per OpenSubsonic spec (both mean unspecified language).
    nonisolated func selectBestLanguage(
        from list: LyricsList,
        locale: Locale = .current,
        preferred: String? = nil
    ) -> StructuredLyrics? {
        let entries = list.structuredLyrics
        guard !entries.isEmpty else { return nil }

        func normalized(_ lang: String?) -> String? {
            lang == "xxx" ? "und" : lang
        }

        func best(among candidates: [StructuredLyrics]) -> StructuredLyrics? {
            candidates.first(where: { $0.synced }) ?? candidates.first
        }

        if let preferred {
            let matching = entries.filter { normalized($0.lang) == preferred }
            if let hit = best(among: matching) { return hit }
        }

        let langCode = locale.language.languageCode?.identifier ?? ""
        let inLocale = langCode.isEmpty ? [] : entries.filter { normalized($0.lang) == langCode }

        if let hit = inLocale.first(where: \.synced) ?? entries.first(where: \.synced) { return hit }
        return inLocale.first ?? entries.first
    }

    // MARK: - Private cache

    private func fetchLyrics(
        for track: DisplayableSong,
        serverId: UUID,
        provider: LyricsProvider
    ) async throws -> LyricsList {
        if let cached = await cachedLyrics(songId: track.id, serverId: serverId, provider: provider) {
            Logger.lyrics.debug(
                "Cache hit — provider=\(provider.rawValue, privacy: .public) songId=\(track.id, privacy: .public)"
            )
            return cached
        }

        let list: LyricsList
        switch provider {
        case .navidrome:
            list = try await fetchNavidromeLyrics(songId: track.id)
        case .lrclib:
            list = try await fetchLRCLIBLyrics(for: track)
        }

        await persistLyrics(list, songId: track.id, serverId: serverId, provider: provider)
        return list
    }

    private func fetchNavidromeLyrics(songId: String) async throws -> LyricsList {
        do {
            let client = try await serverService.activeConnection().makeSwiftSonicClient()
            let capabilities = try await client.loadCapabilities()
            guard capabilities.supports(.songLyrics) else {
                throw LyricsError.notSupportedByServer
            }

            let list = try await client.getLyricsBySongId(id: songId)
            guard !list.structuredLyrics.isEmpty else {
                throw LyricsError.notFound
            }
            return list
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as LyricsError {
            throw error
        } catch {
            Logger.lyrics.error(
                "Navidrome lyrics fetch failed — songId=\(songId, privacy: .public): \(error, privacy: .public)"
            )
            throw LyricsError.networkError(underlying: error.localizedDescription)
        }
    }

    private func fetchLRCLIBLyrics(for track: DisplayableSong) async throws -> LyricsList {
        let title = track.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = track.artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let album = track.albumName?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !artist.isEmpty else {
            throw LyricsError.notFound
        }

        let record = try await lrclibClient.lyrics(for: LRCLIBTrackSignature(
            title: title,
            artist: artist,
            album: album?.isEmpty == false ? album : nil,
            duration: (1...3_600).contains(track.duration) ? track.duration : nil
        ))
        guard let list = Self.lyricsList(from: record) else {
            throw LyricsError.notFound
        }
        return list
    }

    nonisolated static func lyricsList(from record: LRCLIBLyricsRecord) -> LyricsList? {
        var entries: [StructuredLyrics] = []

        if let synced = record.syncedLyrics,
           let parsed = LRCParser.parse(synced) {
            entries.append(StructuredLyrics(
                lang: "und",
                synced: true,
                line: parsed.lines.map {
                    Line(value: $0.value, start: $0.startMilliseconds)
                },
                offset: parsed.offsetMilliseconds
            ))
        }

        if let plain = record.plainLyrics {
            let lines = plain
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map { Line(value: $0) }
            if !lines.isEmpty {
                entries.append(StructuredLyrics(lang: "und", synced: false, line: lines))
            }
        }

        if entries.isEmpty, record.instrumental {
            entries.append(StructuredLyrics(
                lang: "und",
                synced: false,
                line: [Line(value: String(localized: "Instrumental"))]
            ))
        }

        return entries.isEmpty ? nil : LyricsList(structuredLyrics: entries)
    }

    private func cachedLyrics(
        songId: String,
        serverId: UUID,
        provider: LyricsProvider
    ) async -> LyricsList? {
        let key = CachedLyrics.key(songId: songId, serverId: serverId, provider: provider)
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<CachedLyrics>(
            predicate: #Predicate { $0.compositeKey == key }
        )
        guard let entry = (try? context.fetch(descriptor))?.first else { return nil }
        do {
            let payload = entry.jsonPayload
            return try await MainActor.run { try JSONDecoder().decode(LyricsList.self, from: payload) }
        } catch {
            Logger.lyrics.error("Cache corrupted — key=\(key, privacy: .public): \(error, privacy: .public)")
            return nil
        }
    }

    private func persistLyrics(
        _ list: LyricsList,
        songId: String,
        serverId: UUID,
        provider: LyricsProvider
    ) async {
        let data = try? await MainActor.run { try JSONEncoder().encode(list) }
        guard let data else { return }
        let key = CachedLyrics.key(songId: songId, serverId: serverId, provider: provider)
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<CachedLyrics>(
            predicate: #Predicate { $0.compositeKey == key }
        )
        if let existing = (try? context.fetch(descriptor))?.first {
            context.delete(existing)
        }
        context.insert(CachedLyrics(
            songId: songId,
            serverId: serverId,
            jsonPayload: data,
            provider: provider
        ))
        try? context.save()
        Logger.lyrics.debug(
            "Persisted lyrics — provider=\(provider.rawValue, privacy: .public) songId=\(songId, privacy: .public)"
        )
    }
}
