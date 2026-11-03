import Foundation
import OSLog

/// A release group from MusicBrainz' search, trimmed to what the new-releases feed needs.
nonisolated struct MBReleaseGroup: Decodable, Sendable, Equatable {
    struct Credit: Decodable, Sendable, Equatable {
        struct Artist: Decodable, Sendable, Equatable {
            let id: String
            let name: String
        }
        let name: String
        let joinphrase: String?
        let artist: Artist
    }

    let id: String
    let title: String
    let primaryType: String?
    let secondaryTypes: [String]?
    let firstReleaseDate: String?
    let artistCredit: [Credit]?

    enum CodingKeys: String, CodingKey {
        case id, title
        case primaryType = "primary-type"
        case secondaryTypes = "secondary-types"
        case firstReleaseDate = "first-release-date"
        case artistCredit = "artist-credit"
    }

    /// "The Avalanches & John Glacier": the credit as MusicBrainz writes it.
    var creditName: String {
        (artistCredit ?? []).map { $0.name + ($0.joinphrase ?? "") }.joined()
    }
}

nonisolated enum MusicBrainzError: Error, Equatable {
    case http(Int)
}

/// MusicBrainz requests for the new-releases feed. Every request waits for the shared rate limiter:
/// MusicBrainz allows one request per second per application.
actor MusicBrainzReleaseClient {
    private let httpClient: any ArtistImageHTTPClient
    private let rateLimiter: MusicBrainzRateLimiter
    private let retryDelay: Duration
    private static let base = "https://musicbrainz.org/ws/2/"
    /// Artist ids per release-group search; keeps the query URL short.
    static let artistsPerQuery = 25
    /// Attempts per request when MusicBrainz answers 503, with waits of 2, 4, 8 and 16 seconds.
    static let maxAttempts = 5

    init(httpClient: any ArtistImageHTTPClient = URLSession.shared, rateLimiter: MusicBrainzRateLimiter, retryDelay: Duration = .seconds(2)) {
        self.httpClient = httpClient
        self.rateLimiter = rateLimiter
        self.retryDelay = retryDelay
    }

    /// Release groups by any of `artistIDs` first released in `from...to` ("YYYY-MM-DD"), all pages.
    func releaseGroups(artistIDs: [String], from: String, to: String) async throws -> [MBReleaseGroup] {
        guard !artistIDs.isEmpty else { return [] }
        let ids = artistIDs.map { "arid:\($0)" }.joined(separator: " OR ")
        let query = "(\(ids)) AND firstreleasedate:[\(from) TO \(to)]"
        struct Page: Decodable {
            let count: Int?
            let releaseGroups: [MBReleaseGroup]?
            enum CodingKeys: String, CodingKey { case count; case releaseGroups = "release-groups" }
        }
        var all: [MBReleaseGroup] = []
        var offset = 0
        while true {
            let page: Page = try await get("release-group", [
                "query": query, "limit": "100", "offset": String(offset)
            ])
            let groups = page.releaseGroups ?? []
            all.append(contentsOf: groups)
            offset += groups.count
            guard !groups.isEmpty, offset < (page.count ?? 0) else { break }
        }
        return all
    }

    /// The MusicBrainz artist for a name, only when the match is certain: score ≥ 90 and the same name
    /// once case, diacritics and punctuation are ignored. A guess would follow the wrong artist.
    func artistID(named name: String) async throws -> String? {
        struct Response: Decodable {
            struct Artist: Decodable { let id: String; let name: String; let score: Int? }
            let artists: [Artist]?
        }
        let escaped = name.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let response: Response = try await get("artist", ["query": "artist:\"\(escaped)\"", "limit": "3"])
        let wanted = NewReleaseMatching.normalisedName(name)
        return response.artists?.first { candidate in
            (candidate.score ?? 0) >= 90 && NewReleaseMatching.normalisedName(candidate.name) == wanted
        }?.id
    }

    /// Every URL MusicBrainz links from the releases in a release group (stores, streaming, …).
    func releaseURLs(releaseGroupID: String) async throws -> [URL] {
        struct Response: Decodable {
            struct Release: Decodable {
                struct Relation: Decodable { struct Target: Decodable { let resource: String }; let url: Target? }
                let relations: [Relation]?
            }
            let releases: [Release]?
        }
        let response: Response = try await get("release", [
            "release-group": releaseGroupID, "inc": "url-rels", "limit": "25"
        ])
        return (response.releases ?? []).flatMap { $0.relations ?? [] }.compactMap { $0.url.flatMap { URL(string: $0.resource) } }
    }

    private func get<T: Decodable>(_ path: String, _ parameters: [String: String]) async throws -> T {
        var components = URLComponents(string: Self.base + path)
        components?.queryItems = parameters.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
            + [URLQueryItem(name: "fmt", value: "json")]
        guard let url = components?.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue(MaeksterBrand.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        // 503 is MusicBrainz busy or asking to slow down, and it comes and goes; back off and retry.
        for attempt in 0..<Self.maxAttempts {
            try await rateLimiter.waitForPermit()
            let (data, response) = try await httpClient.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 200
            if status == 503, attempt < Self.maxAttempts - 1 {
                try await Task.sleep(for: retryDelay * (1 << attempt))
                continue
            }
            guard (200..<300).contains(status) else { throw MusicBrainzError.http(status) }
            return try JSONDecoder().decode(T.self, from: data)
        }
        throw MusicBrainzError.http(503)
    }
}
