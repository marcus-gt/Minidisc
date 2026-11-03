import Foundation

nonisolated enum MusicStore: String, CaseIterable, Sendable {
    case bandcamp
    case qobuz
    case beatport

    var name: String {
        switch self {
        case .bandcamp: "Bandcamp"
        case .qobuz: "Qobuz"
        case .beatport: "Beatport"
        }
    }
}

/// A store page for a release: the record itself (from MusicBrainz) or a store search for it.
nonisolated struct StoreLink: Identifiable, Hashable, Sendable {
    let store: MusicStore
    let url: URL
    let isSearch: Bool
    var id: String { "\(store.rawValue)|\(isSearch)" }
}

nonisolated enum ReleaseStoreLinks {
    /// Picks one record page per store from MusicBrainz' URL relations. Record pages beat artist pages.
    static func recordPages(from urls: [URL]) -> [MusicStore: URL] {
        var best: [MusicStore: (url: URL, rank: Int)] = [:]
        for url in urls {
            guard let (store, rank) = classify(url) else { continue }
            if let current = best[store], current.rank >= rank { continue }
            best[store] = (url, rank)
        }
        return best.mapValues(\.url)
    }

    /// Bandcamp, Qobuz, Beatport in that order: the record when MusicBrainz knows it, otherwise a search
    /// for Bandcamp and Qobuz. Beatport is shown only with a record page.
    static func links(recordPages: [MusicStore: URL], artist: String, title: String, region: String?) -> [StoreLink] {
        MusicStore.allCases.compactMap { store in
            if let url = recordPages[store] { return StoreLink(store: store, url: url, isSearch: false) }
            guard store != .beatport, let url = searchURL(store: store, artist: artist, title: title, region: region) else { return nil }
            return StoreLink(store: store, url: url, isSearch: true)
        }
    }

    static func searchURL(store: MusicStore, artist: String, title: String, region: String?) -> URL? {
        let query = "\(artist) \(title)".trimmingCharacters(in: .whitespaces)
        switch store {
        case .bandcamp:
            var components = URLComponents(string: "https://bandcamp.com/search")
            components?.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "item_type", value: "a")]
            return components?.url
        case .qobuz:
            guard let path = query.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(["/"])) else { return nil }
            return URL(string: "https://www.qobuz.com/\(qobuzStorefront(region: region))/search/albums/\(path)")
        case .beatport:
            var components = URLComponents(string: "https://www.beatport.com/search/releases")
            components?.queryItems = [URLQueryItem(name: "q", value: query)]
            return components?.url
        }
    }

    /// Qobuz serves search per storefront ("no-en", "gb-en"). Unknown regions use the US store.
    static func qobuzStorefront(region: String?) -> String {
        let markets: Set<String> = ["us", "gb", "ie", "fr", "de", "at", "ch", "be", "nl", "lu", "it", "es", "pt",
                                    "se", "no", "dk", "fi", "au", "nz", "jp", "ca", "br", "ar", "cl", "co", "mx"]
        let code = (region ?? "").lowercased()
        return "\(markets.contains(code) ? code : "us")-en"
    }

    /// The store and how specific the page is (2 = the record, 1 = anything else on the store).
    private static func classify(_ url: URL) -> (MusicStore, Int)? {
        guard let host = url.host?.lowercased() else { return nil }
        let path = url.path.lowercased()
        if host == "bandcamp.com" || host.hasSuffix(".bandcamp.com") {
            return (.bandcamp, path.contains("/album/") || path.contains("/track/") ? 2 : 1)
        }
        if host == "qobuz.com" || host.hasSuffix(".qobuz.com") {
            return path.contains("/album/") ? (.qobuz, 2) : nil
        }
        if host == "beatport.com" || host.hasSuffix(".beatport.com") {
            return path.contains("/release/") ? (.beatport, 2) : nil
        }
        return nil
    }
}
