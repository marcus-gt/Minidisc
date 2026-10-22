import Foundation

/// How one library genre tag is grouped in the Queue Builder.
nonisolated struct ResolvedGenreTag: Sendable, Equatable {
    /// Spelling variants share a key ("Hip-Hop", "hip hop"), and "Modal Jazz" shares the "Modal" style's key.
    let key: String
    /// Main genres the tag belongs to. A Discogs style listed under two genres belongs to both.
    let mains: [String]
    /// The Discogs style name when the tag is one, so the pill uses the canonical spelling.
    let styleName: String?
    /// The tag names a main genre itself ("Jazz"): it counts towards that column but gets no pill of its own.
    let isMainTag: Bool
}

/// Groups free-form library genre tags under the Discogs main genres, as sketched in #17.
///
/// Order of resolution: exact Discogs style → main genre name → alias → "<style> <main>" spelling
/// ("Modal Jazz" → Modal) → keyword ("East Coast Hip Hop" → Hip Hop) → "Other".
nonisolated struct GenreTaxonomy: Sendable {
    static let otherGenre = "Other"

    /// Main genres in Discogs order.
    let mainGenres: [String]
    private let stylesByKey: [String: (name: String, mains: [String])]
    private let mainsByKey: [String: String]

    init(genres: [(main: String, styles: [String])]) {
        mainGenres = genres.map(\.main)
        var styles: [String: (name: String, mains: [String])] = [:]
        for (main, mainStyles) in genres {
            for style in mainStyles {
                let key = Self.normalized(style)
                if var existing = styles[key] {
                    if !existing.mains.contains(main) { existing.mains.append(main) }
                    styles[key] = existing
                } else {
                    styles[key] = (style, [main])
                }
            }
        }
        stylesByKey = styles
        mainsByKey = Dictionary(genres.map { (Self.normalized($0.main), $0.main) }, uniquingKeysWith: { first, _ in first })
    }

    /// The bundled Discogs taxonomy (`Resources/DiscogsGenres.json`).
    static let discogs: GenreTaxonomy = {
        guard let url = Bundle.main.url(forResource: "DiscogsGenres", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(BundledFile.self, from: data)
        else { return GenreTaxonomy(genres: []) }
        return GenreTaxonomy(genres: file.genres.map { ($0.key, $0.value) }.sorted { $0.0 < $1.0 })
    }()

    func resolve(_ tag: String) -> ResolvedGenreTag {
        resolve(tag, followAliases: true)
    }

    private func resolve(_ tag: String, followAliases: Bool) -> ResolvedGenreTag {
        let key = Self.normalized(tag)
        // Main names first: Discogs also has an Electronic style called "Hip Hop", which must not
        // capture the Hip Hop main genre.
        if let main = mainsByKey[key] {
            return ResolvedGenreTag(key: "main:\(key)", mains: [main], styleName: nil, isMainTag: true)
        }
        if let style = stylesByKey[key] {
            return ResolvedGenreTag(key: key, mains: style.mains, styleName: style.name, isMainTag: false)
        }
        if followAliases, let alias = Self.aliases[key] {
            return resolve(alias, followAliases: false)
        }
        if let main = Self.knownSubgenres[key] {
            return ResolvedGenreTag(key: key, mains: [main], styleName: nil, isMainTag: false)
        }
        if let style = styleWithMainWord(key) {
            return style
        }
        if let main = Self.keywords.first(where: { key.contains($0.fragment) })?.main, mainsByKey[Self.normalized(main)] != nil {
            return ResolvedGenreTag(key: key, mains: [main], styleName: nil, isMainTag: false)
        }
        return ResolvedGenreTag(key: key, mains: [Self.otherGenre], styleName: nil, isMainTag: false)
    }

    /// A main genre for a track with no usable tags, from AudioMuse's style labels (best first): the
    /// first label that names a genre. Decades, voices and feel ("60s", "female vocalists",
    /// "chillout") are skipped, as are labels that only map to "Other".
    func mainGenre(fromAudioMuseStyles labels: [String]) -> String? {
        for label in labels {
            let key = Self.normalized(label)
            guard !Self.audioMuseNonGenreLabels.contains(key), !Self.isDecadeLabel(key) else { continue }
            if let main = resolve(label).mains.first, main != Self.otherGenre { return main }
        }
        return nil
    }

    /// "60s", "00s".
    private static func isDecadeLabel(_ key: String) -> Bool {
        key.hasSuffix("s") && key.count > 1 && key.dropLast().allSatisfy(\.isNumber)
    }

    /// AudioMuse labels (Last.fm top tags) that describe voice, feel or era rather than a genre.
    private static let audioMuseNonGenreLabels: Set<String> = [
        "femalevocalists", "femalevocalist", "malevocalists", "instrumental", "chillout", "chill",
        "easylistening", "beautiful", "mellow", "sexy", "catchy", "happy", "sad", "party", "guitar",
        "acoustic", "oldies",
    ]

    /// "Modal Jazz" / "Jazz Fusion" → the Modal / Fusion style when that style sits under Jazz.
    private func styleWithMainWord(_ key: String) -> ResolvedGenreTag? {
        for (word, main) in Self.mainWords {
            let remainder: Substring
            if key.hasSuffix(word) {
                remainder = key.dropLast(word.count)
            } else if key.hasPrefix(word) {
                remainder = key.dropFirst(word.count)
            } else {
                continue
            }
            guard !remainder.isEmpty, let style = stylesByKey[String(remainder)], style.mains.contains(main) else { continue }
            return ResolvedGenreTag(key: String(remainder), mains: style.mains, styleName: style.name, isMainTag: false)
        }
        return nil
    }

    /// Lowercased, accents folded, `&` read as "and", everything but letters and digits removed.
    static func normalized(_ tag: String) -> String {
        tag.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "&", with: "and")
            .filter { $0.isLetter || $0.isNumber }
    }

    // MARK: - Tables

    private struct BundledFile: Decodable {
        let genres: [String: [String]]
    }

    /// Synonyms: the tag means exactly this Discogs style or main genre, so it merges into it.
    private static let aliases: [String: String] = [
        "rap": "Hip Hop", "randb": "Rhythm & Blues", "rnb": "Rhythm & Blues", "soul": "Funk / Soul", "funk": "Funk / Soul",
        "alternative": "Alternative Rock", "indie": "Indie Rock", "merseybeat": "Beat", "beatmusic": "Beat",
        "electronica": "Electronic", "electronique": "Electronic", "edm": "Electronic", "electronicdancemusic": "Electronic",
        "dance": "Electronic", "drumandbass": "Drum n Bass", "dnb": "Drum n Bass", "futuregarage": "UK Garage",
        "oldies": "Pop", "folk": "Folk, World, & Country", "country": "Folk, World, & Country",
        "world": "Folk, World, & Country", "worldmusic": "Folk, World, & Country",
        "chansonfrancaise": "Chanson", "metal": "Heavy Metal", "videogamemusic": "Soundtrack",
    ]

    /// Sub-genres Discogs has no style for: their own pill, under this main genre.
    private static let knownSubgenres: [String: String] = [
        "thirdstream": "Jazz", "spiritualjazz": "Jazz", "dirtysouth": "Hip Hop", "staxvolt": "Funk / Soul",
        "rave": "Electronic", "complextro": "Electronic", "singersongwriter": "Folk, World, & Country",
        "worldfusion": "Folk, World, & Country", "klezmer": "Folk, World, & Country",
        "concerto": "Classical", "orchestra": "Classical", "programmusic": "Classical",
    ]

    /// Words a tag may add to a style name: "<style> Jazz", "Jazz <style>".
    private static let mainWords: [(word: String, main: String)] = [
        ("jazz", "Jazz"), ("hiphop", "Hip Hop"), ("rap", "Hip Hop"), ("rock", "Rock"), ("blues", "Blues"),
        ("reggae", "Reggae"), ("pop", "Pop"), ("latin", "Latin"), ("soul", "Funk / Soul"), ("funk", "Funk / Soul"),
        ("electronic", "Electronic"), ("classical", "Classical"),
    ]

    /// Fragment → main genre, most specific first; the first match wins.
    private static let keywords: [(fragment: String, main: String)] = [
        ("hiphop", "Hip Hop"), ("rap", "Hip Hop"), ("jazz", "Jazz"), ("bebop", "Jazz"), ("bop", "Jazz"), ("swing", "Jazz"),
        ("blues", "Blues"), ("reggae", "Reggae"), ("punk", "Rock"), ("metal", "Rock"), ("rock", "Rock"), ("grunge", "Rock"),
        ("house", "Electronic"), ("techno", "Electronic"), ("trance", "Electronic"), ("electro", "Electronic"),
        ("ambient", "Electronic"), ("bass", "Electronic"), ("dance", "Electronic"), ("synth", "Electronic"), ("idm", "Electronic"),
        ("soul", "Funk / Soul"), ("funk", "Funk / Soul"), ("disco", "Funk / Soul"), ("gospel", "Funk / Soul"),
        ("bluegrass", "Folk, World, & Country"), ("folk", "Folk, World, & Country"), ("country", "Folk, World, & Country"),
        ("latin", "Latin"), ("salsa", "Latin"), ("bossa", "Latin"),
        ("classical", "Classical"), ("baroque", "Classical"), ("opera", "Classical"), ("symphon", "Classical"),
        ("pop", "Pop"), ("soundtrack", "Stage & Screen"), ("score", "Stage & Screen"),
    ]
}
