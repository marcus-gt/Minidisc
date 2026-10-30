import Foundation
import OSLog
import SwiftSonic

/// A mood's radio (#60): a fresh set of the mood's best matches each time it starts, from AudioMuse's
/// sonic search when the server has it and from the library's mood, BPM and genre tags otherwise.
/// The best matches tend to come first; the top ones seed similar songs once the set runs out.
actor MoodRadioService {
    nonisolated struct Radio: Sendable {
        let tracks: [DisplayableSong]
        let seedIDs: [String]
    }

    /// How many matches a radio starts from.
    static let poolSize = 200
    static let seedCount = 10

    private let makeProvider: @Sendable () async -> (any MoodTrackProvider)?
    private let songsByID: @Sendable ([String]) async -> [Song]

    init(providerFactory: @escaping @Sendable () async -> (any MoodTrackProvider)?,
         songsByID: @escaping @Sendable ([String]) async -> [Song]) {
        self.makeProvider = providerFactory
        self.songsByID = songsByID
    }

    init(serverService: any ServerServiceProtocol, serverState: ServerState,
         libraryService: any LibrarySearching & MoodTrackSourcing, catalog: LibraryCatalog) {
        self.init(
            providerFactory: {
                if let urlString = await MainActor.run(body: { serverState.activeServer?.audioMuseURL }),
                   let credentials = try? await serverService.activeConnection().credentials,
                   let client = AudioMuseClient(urlString: urlString, token: credentials.audioMuseToken) {
                    return AudioMuseTrackProvider(client: client, resolver: SubsonicTrackResolver(libraryService: libraryService))
                }
                return LibraryTagTrackProvider(libraryService: libraryService)
            },
            songsByID: { (try? await catalog.indexedSongs(ids: $0)) ?? [] }
        )
    }

    /// Empty when nothing matched; throws when the source couldn't be asked at all.
    func radio(for mood: Mood) async throws -> Radio {
        guard let provider = await makeProvider() else { return Radio(tracks: [], seedIDs: []) }
        await provider.prepare()
        let matches = try await provider.trackIds(for: mood, limit: Self.poolSize)
        try Task.checkCancellation()
        var generator = SystemRandomNumberGenerator()
        let order = Self.order(matches, using: &generator)
        let indexed = Dictionary(await songsByID(order).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let tracks = order.compactMap { indexed[$0].map { DisplayableSong(from: $0) } }
        Logger.moodPlaylists.info("[MOOD] radio \(mood.rawValue, privacy: .public) via \(provider.kind.rawValue, privacy: .public): \(matches.count, privacy: .public) matches, \(tracks.count, privacy: .public) queued")
        return Radio(tracks: tracks, seedIDs: Array(matches.filter { indexed[$0] != nil }.prefix(Self.seedCount)))
    }

    /// A shuffle weighted by rank, so the best matches tend to lead without the radio being the
    /// same every time.
    nonisolated static func order(_ matches: [String], using generator: inout some RandomNumberGenerator) -> [String] {
        matches.enumerated()
            .map { (id: $0.element, weight: Double(matches.count - $0.offset)) }
            .weightedShuffled(weight: \.weight, using: &generator)
            .map(\.id)
    }
}
