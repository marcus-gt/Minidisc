import Foundation
import SwiftSonic
import Synchronization
import Testing
@testable import Minidisc

// MARK: - Matching

@Suite("New releases: matching (#15)")
struct NewReleaseMatchingTests {
    @Test func normalisedTitle_foldsTheDifferencesTwoCataloguesHave() {
        // Examples from the NAS job's notes.
        #expect(NewReleaseMatching.normalisedTitle("Tomorrow\u{2019}s Harvest") == NewReleaseMatching.normalisedTitle("Tomorrow's Harvest"))
        #expect(NewReleaseMatching.normalisedTitle("Amygdala (deluxe edition)") == "amygdala")
        #expect(NewReleaseMatching.normalisedTitle("Blue Train - 2003 Remaster") == "blue train")
        #expect(NewReleaseMatching.normalisedTitle("The Dark Side of the Moon") == "dark side of moon")
        #expect(NewReleaseMatching.normalisedTitle("Røyksopp’s Night Out") == NewReleaseMatching.normalisedTitle("Royksopp's Night Out"))
        #expect(NewReleaseMatching.normalisedTitle("DONDA 2") != NewReleaseMatching.normalisedTitle("Donda"))
    }

    @Test func musicBrainzID_rejectsDiscogsIntegers() {
        #expect(NewReleaseMatching.isMusicBrainzID("a6623d39-2d8e-4f70-8242-0a9553b91e50"))
        #expect(!NewReleaseMatching.isMusicBrainzID("4654"))
        #expect(!NewReleaseMatching.isMusicBrainzID(""))
        #expect(!NewReleaseMatching.isMusicBrainzID(nil))
    }

    @Test func partialDates_parseAndCompare() {
        #expect(NewReleaseMatching.isReleased("2026-10", today: "2026-10-27"))
        #expect(NewReleaseMatching.isReleased("2026-10-27", today: "2026-10-27"))
        #expect(!NewReleaseMatching.isReleased("2026-11-02", today: "2026-10-27"))
        #expect(!NewReleaseMatching.isReleased("2027", today: "2026-10-27"))
        #expect(NewReleaseMatching.isReleased(nil, today: "2026-10-27"))
        let date = try! #require(NewReleaseMatching.date(fromMusicBrainz: "2026-09"))
        #expect(NewReleaseMatching.musicBrainzDay(date) == "2026-09-01")
    }

    @Test func typeLabel_joinsPrimaryAndSecondaryTypes() {
        #expect(NewReleaseMatching.typeLabel(primary: "Single", secondary: ["Remix"]) == "Single · Remix")
        #expect(NewReleaseMatching.typeLabel(primary: nil, secondary: []) == "Release")
    }

    @Test func watchlist_followsAlbumArtistsWithTheirOwnedTitles() {
        let artists = [
            ArtistID3(id: "av", name: "The Avalanches", albumCount: 2, musicBrainzId: "A6623D39-2D8E-4F70-8242-0A9553B91E50"),
            ArtistID3(id: "kw", name: "Kraftwerk", albumCount: 1, musicBrainzId: "4654"),
            ArtistID3(id: "guest", name: "Guest Only", albumCount: 0)
        ]
        let albums = [
            AlbumID3(id: "1", name: "Since I Left You", songCount: 1, duration: 1, artistId: "av"),
            AlbumID3(id: "2", name: "Wildflower (Deluxe Edition)", songCount: 1, duration: 1, artistId: "av"),
            AlbumID3(id: "3", name: "Computerwelt", songCount: 1, duration: 1, artistId: "kw")
        ]
        let watchlist = NewReleaseWatchlist.build(artists: artists, albums: albums)
        #expect(watchlist.artists.map(\.name) == ["Kraftwerk", "The Avalanches"])
        #expect(watchlist.artists[1].musicBrainzID == "a6623d39-2d8e-4f70-8242-0a9553b91e50")
        #expect(watchlist.artists[1].ownedTitles == ["since i left you", "wildflower"])
        // The Discogs integer is not used; the name is looked up instead.
        #expect(watchlist.artists[0].musicBrainzID == nil)
    }
}

// MARK: - Store links

@Suite("New releases: store links (#15)")
struct ReleaseStoreLinksTests {
    @Test func recordPages_keepsStoresAndIgnoresStreamingServices() {
        // The url-rels MusicBrainz returned for "Far Away" (The Avalanches), 2026-10-27.
        let urls = [
            "https://music.apple.com/gb/album/6786910825",
            "https://www.qobuz.com/gb-en/album/far-away-the-avalanches-john-glacier-khadija-al-hanafi/jdt61sgm1dzx2",
            "https://tidal.com/album/559192053"
        ].compactMap(URL.init(string:))
        let pages = ReleaseStoreLinks.recordPages(from: urls)
        #expect(pages.keys.sorted { $0.rawValue < $1.rawValue } == [.qobuz])
        #expect(pages[.qobuz]?.absoluteString.contains("/album/far-away") == true)
    }

    @Test func recordPages_preferTheRecordOverTheArtistPage() {
        let urls = ["https://theavalanches.bandcamp.com/", "https://theavalanches.bandcamp.com/album/no-bad-memories",
                    "https://www.beatport.com/release/no-bad-memories/123", "https://www.beatport.com/artist/the-avalanches/1"]
            .compactMap(URL.init(string:))
        let pages = ReleaseStoreLinks.recordPages(from: urls)
        #expect(pages[.bandcamp]?.path == "/album/no-bad-memories")
        #expect(pages[.beatport]?.path == "/release/no-bad-memories/123")
    }

    @Test func links_fallBackToSearchesForBandcampAndQobuzOnly() {
        let links = ReleaseStoreLinks.links(recordPages: [:], artist: "Ezra Collective", title: "Here Because Of Hope", region: "NO")
        #expect(links.map(\.store) == [.bandcamp, .qobuz])
        #expect(links.allSatisfy { $0.isSearch })
        #expect(links[0].url.absoluteString == "https://bandcamp.com/search?q=Ezra%20Collective%20Here%20Because%20Of%20Hope&item_type=a")
        #expect(links[1].url.absoluteString == "https://www.qobuz.com/no-en/search/albums/Ezra%20Collective%20Here%20Because%20Of%20Hope")
    }

    @Test func links_useRecordPagesFirst() {
        let qobuz = URL(string: "https://www.qobuz.com/gb-en/album/x/1")!
        let beatport = URL(string: "https://www.beatport.com/release/x/2")!
        let links = ReleaseStoreLinks.links(recordPages: [.qobuz: qobuz, .beatport: beatport], artist: "A", title: "T", region: nil)
        #expect(links.map(\.store) == [.bandcamp, .qobuz, .beatport])
        #expect(links.map(\.isSearch) == [true, false, false])
    }

    @Test func qobuzStorefront_fallsBackToTheUSStore() {
        #expect(ReleaseStoreLinks.qobuzStorefront(region: "GB") == "gb-en")
        #expect(ReleaseStoreLinks.qobuzStorefront(region: "KR") == "us-en")
        #expect(ReleaseStoreLinks.qobuzStorefront(region: nil) == "us-en")
    }
}

// MARK: - Service

/// Answers MusicBrainz requests from closures and records every URL it was asked for.
private final class StubMusicBrainz: ArtistImageHTTPClient, Sendable {
    private let log = Mutex<[URL]>([])
    private let handler: @Sendable (URLComponents) -> (Int, String)

    init(_ handler: @escaping @Sendable (URLComponents) -> (Int, String)) {
        self.handler = handler
    }

    var requests: [URL] { log.withLock { $0 } }
    func requests(to path: String) -> [URLComponents] {
        requests.compactMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }.filter { $0.path.hasSuffix(path) }
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let url = try #require(request.url)
        log.withLock { $0.append(url) }
        let (status, body) = handler(URLComponents(url: url, resolvingAgainstBaseURL: false)!)
        return (Data(body.utf8), HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

private final class ServerBox: Sendable {
    let id = Mutex<String?>("server-1")
}

@Suite("New releases: library feed (#15)")
struct LibraryNewReleasesServiceTests {
    private static let avalanches = "a6623d39-2d8e-4f70-8242-0a9553b91e50"
    private let today = Date(timeIntervalSince1970: 1_793_102_400) // 2026-10-27 12:00 UTC

    private func group(_ id: String, _ title: String, date: String, artist: String = avalanches,
                       name: String = "The Avalanches", primary: String = "Album", secondary: [String] = []) -> String {
        let types = secondary.map { "\"\($0)\"" }.joined(separator: ",")
        return #"{"id":"\#(id)","title":"\#(title)","primary-type":"\#(primary)","secondary-types":[\#(types)],"first-release-date":"\#(date)","artist-credit":[{"name":"\#(name)","joinphrase":"","artist":{"id":"\#(artist)","name":"\#(name)"}}]}"#
    }

    private func makeService(watchlist: NewReleaseWatchlist, http: StubMusicBrainz, server: ServerBox = ServerBox(),
                             directory: URL) -> LibraryNewReleasesService {
        LibraryNewReleasesService(
            watchlist: { watchlist },
            activeServerID: { server.id.withLock { $0 } },
            client: MusicBrainzReleaseClient(httpClient: http, rateLimiter: MusicBrainzRateLimiter(minimumInterval: .zero), retryDelay: .zero),
            directory: directory,
            now: { [today] in today }
        )
    }

    private func tempDirectory() -> URL {
        URL.temporaryDirectory.appendingPathComponent("new-releases-tests-\(UUID().uuidString)")
    }

    @Test func refresh_keepsNewUnownedReleasedRecordsNewestFirst() async throws {
        let body = #"{"count":4,"release-groups":["# + [
            group("rg-1", "No Bad Memories", date: "2026-10-16"),
            group("rg-2", "Wildflower (Deluxe Edition)", date: "2026-09-01"),
            group("rg-3", "Together (Remixes)", date: "2026-10-02", primary: "Single", secondary: ["Remix"]),
            group("rg-4", "Next Year's Album", date: "2026-12-01")
        ].joined(separator: ",") + "]}"
        let http = StubMusicBrainz { _ in (200, body) }
        let watchlist = NewReleaseWatchlist(artists: [
            WatchedArtist(name: "The Avalanches", musicBrainzID: Self.avalanches, ownedTitles: ["wildflower"])
        ])
        let service = makeService(watchlist: watchlist, http: http, directory: tempDirectory())
        try await service.refresh()
        let releases = await service.releases()

        #expect(releases.map(\.id) == ["rg-1", "rg-3"])
        #expect(releases[1].typeLabel == "Single · Remix")
        #expect(releases[0].coverArtURL?.absoluteString == "https://coverartarchive.org/release-group/rg-1/front-250")
        let query = try #require(http.requests(to: "release-group").first?.queryItems?.first { $0.name == "query" }?.value)
        #expect(query == "(arid:\(Self.avalanches)) AND firstreleasedate:[2026-07-29 TO 2026-10-27]")
    }

    @Test func refresh_batchesTwentyFiveArtistsPerSearch() async throws {
        let http = StubMusicBrainz { _ in (200, #"{"count":0,"release-groups":[]}"#) }
        let artists = (0..<30).map { index in
            WatchedArtist(name: "Artist \(index)", musicBrainzID: String(format: "00000000-0000-0000-0000-%012d", index), ownedTitles: ["x"])
        }
        let service = makeService(watchlist: NewReleaseWatchlist(artists: artists), http: http, directory: tempDirectory())
        try await service.refresh()
        #expect(http.requests(to: "release-group").count == 2)
    }

    @Test func refresh_looksUpMissingIDsOnceAndOnlyAcceptsCertainMatches() async throws {
        let http = StubMusicBrainz { components in
            if components.path.hasSuffix("artist") {
                let query = components.queryItems?.first { $0.name == "query" }?.value ?? ""
                if query.contains("Kraftwerk") {
                    return (200, #"{"artists":[{"id":"5700dcd4-c139-4f31-aa3e-6382b9af9032","name":"Kraftwerk","score":100}]}"#)
                }
                // Close, but not the same name: not followed.
                return (200, #"{"artists":[{"id":"11111111-1111-1111-1111-111111111111","name":"Bill Evans Trio","score":95}]}"#)
            }
            return (200, #"{"count":0,"release-groups":[]}"#)
        }
        let watchlist = NewReleaseWatchlist(artists: [
            WatchedArtist(name: "Kraftwerk", musicBrainzID: nil, ownedTitles: ["computerwelt"]),
            WatchedArtist(name: "Bill Evans", musicBrainzID: nil, ownedTitles: ["portrait in jazz"])
        ])
        let directory = tempDirectory()
        try await makeService(watchlist: watchlist, http: http, directory: directory).refresh()
        let query = try #require(http.requests(to: "release-group").first?.queryItems?.first { $0.name == "query" }?.value)
        #expect(query.contains("arid:5700dcd4-c139-4f31-aa3e-6382b9af9032"))
        #expect(!query.contains("11111111"))

        // A new service (a relaunch) reuses both answers: no new name lookups.
        try await makeService(watchlist: watchlist, http: http, directory: directory).refresh()
        #expect(http.requests(to: "artist").count == 2)
    }

    @Test func refresh_capsNameLookupsPerRun() async throws {
        let http = StubMusicBrainz { components in
            components.path.hasSuffix("artist") ? (200, #"{"artists":[]}"#) : (200, #"{"count":0,"release-groups":[]}"#)
        }
        let artists = (0..<(LibraryNewReleasesService.nameLookupsPerRefresh + 10)).map {
            WatchedArtist(name: "Unknown \($0)", musicBrainzID: nil, ownedTitles: ["x"])
        }
        try await makeService(watchlist: NewReleaseWatchlist(artists: artists), http: http, directory: tempDirectory()).refresh()
        #expect(http.requests(to: "artist").count == LibraryNewReleasesService.nameLookupsPerRefresh)
    }

    @Test func refresh_failedSearchKeepsThePreviousResult() async throws {
        let failing = Mutex(false)
        let body = #"{"count":1,"release-groups":["# + group("rg-1", "No Bad Memories", date: "2026-10-16") + "]}"
        let http = StubMusicBrainz { _ in failing.withLock { $0 } ? (500, "") : (200, body) }
        let watchlist = NewReleaseWatchlist(artists: [WatchedArtist(name: "The Avalanches", musicBrainzID: Self.avalanches, ownedTitles: [])])
        let service = makeService(watchlist: watchlist, http: http, directory: tempDirectory())
        try await service.refresh()
        failing.withLock { $0 = true }
        await #expect(throws: MusicBrainzError.http(500)) { try await service.refresh() }
        #expect(await service.releases().map(\.id) == ["rg-1"])
    }

    @Test func refresh_serverSwitchDuringRunIsNotStored() async throws {
        let server = ServerBox()
        let body = #"{"count":1,"release-groups":["# + group("rg-1", "No Bad Memories", date: "2026-10-16") + "]}"
        let http = StubMusicBrainz { _ in
            server.id.withLock { $0 = "server-2" }
            return (200, body)
        }
        let watchlist = NewReleaseWatchlist(artists: [WatchedArtist(name: "The Avalanches", musicBrainzID: Self.avalanches, ownedTitles: [])])
        let service = makeService(watchlist: watchlist, http: http, server: server, directory: tempDirectory())
        try await service.refresh()
        server.id.withLock { $0 = "server-1" }
        #expect(await service.releases().isEmpty)
    }

    @Test func staleness_isAboutADay() {
        var state = NewReleasesState()
        #expect(LibraryNewReleasesService.isStale(state, now: today))
        state.refreshedAt = today.addingTimeInterval(-3600)
        #expect(!LibraryNewReleasesService.isStale(state, now: today))
        state.refreshedAt = today.addingTimeInterval(-LibraryNewReleasesService.refreshInterval)
        #expect(LibraryNewReleasesService.isStale(state, now: today))
    }

    @Test func storeLinks_useMusicBrainzAndFallBackToSearch() async throws {
        let http = StubMusicBrainz { components in
            #expect(components.queryItems?.contains(URLQueryItem(name: "release-group", value: "rg-1")) == true)
            return (200, #"{"releases":[{"relations":[{"url":{"resource":"https://theavalanches.bandcamp.com/album/no-bad-memories"}},{"url":{"resource":"https://tidal.com/album/1"}}]}]}"#)
        }
        let service = makeService(watchlist: NewReleaseWatchlist(artists: []), http: http, directory: tempDirectory())
        let links = await service.storeLinks(releaseGroupID: "rg-1", artist: "The Avalanches", title: "No Bad Memories", region: "NO")
        #expect(links.map(\.store) == [.bandcamp, .qobuz])
        #expect(links.map(\.isSearch) == [false, true])
        // Cached: a second look doesn't ask MusicBrainz again.
        _ = await service.storeLinks(releaseGroupID: "rg-1", artist: "The Avalanches", title: "No Bad Memories", region: "NO")
        #expect(http.requests.count == 1)
    }
}

@Suite("New releases: MusicBrainz client (#15)")
struct MusicBrainzReleaseClientTests {
    @Test func busyServer_isRetriedUntilItAnswers() async throws {
        let calls = Mutex(0)
        let http = StubMusicBrainz { _ in
            let call = calls.withLock { $0 += 1; return $0 }
            return call < 3 ? (503, #"{"error":"busy"}"#) : (200, #"{"count":0,"release-groups":[]}"#)
        }
        let client = MusicBrainzReleaseClient(httpClient: http, rateLimiter: MusicBrainzRateLimiter(minimumInterval: .zero), retryDelay: .zero)
        _ = try await client.releaseGroups(artistIDs: ["x"], from: "2026-01-01", to: "2026-01-02")
        #expect(calls.withLock { $0 } == 3)
    }

    @Test func busyServer_givesUpAfterTheLastAttempt() async throws {
        let http = StubMusicBrainz { _ in (503, #"{"error":"busy"}"#) }
        let client = MusicBrainzReleaseClient(httpClient: http, rateLimiter: MusicBrainzRateLimiter(minimumInterval: .zero), retryDelay: .zero)
        await #expect(throws: MusicBrainzError.http(503)) {
            _ = try await client.releaseGroups(artistIDs: ["x"], from: "2026-01-01", to: "2026-01-02")
        }
        #expect(http.requests.count == MusicBrainzReleaseClient.maxAttempts)
    }
}

@Suite("New releases: what is followed (#15)")
struct NewReleaseFollowingTests {
    @Test func variousArtistsAndOtherPlaceholders_areNeverFollowed() {
        let artists = [
            ArtistID3(id: "va", name: "Various Artists", albumCount: 40, musicBrainzId: "89ad4ac3-39f7-470e-963a-56509c546377"),
            ArtistID3(id: "va2", name: "Various", albumCount: 3),
            ArtistID3(id: "unknown", name: "[unknown]", albumCount: 1, musicBrainzId: "125ec42a-7229-4250-afc5-e057484327fe"),
            ArtistID3(id: "ezra", name: "Ezra Collective", albumCount: 1, musicBrainzId: "d51acca9-a88b-4f5c-a2fe-f069de70ca1d")
        ]
        let albums = ["va", "va2", "unknown", "ezra"].enumerated().map { index, artist in
            AlbumID3(id: "al\(index)", name: "Album \(index)", songCount: 1, duration: 1, artistId: artist)
        }
        #expect(NewReleaseWatchlist.build(artists: artists, albums: albums).artists.map(\.name) == ["Ezra Collective"])
    }

    @Test func sameTitleOnTheSameDay_isListedOnce() {
        func group(_ id: String, credit: String) -> MBReleaseGroup {
            MBReleaseGroup(id: id, title: "Do Our Thing", primaryType: "EP", secondaryTypes: nil, firstReleaseDate: "2026-10-23",
                           artistCredit: [.init(name: credit, joinphrase: nil, artist: .init(id: "beyer", name: "Adam Beyer"))])
        }
        let releases = LibraryNewReleasesService.newReleases(
            from: [group("a", credit: "Adam Beyer & Mark Reeve"), group("b", credit: "Adam Beyer X Mark Reeve")],
            owned: ["beyer": []], today: "2026-10-27"
        )
        #expect(releases.map(\.id) == ["a"])
    }
}
