import Foundation

/// Matching rules for "new releases by artists you own" (#15), ported from the owner's NAS script
/// (`new-releases`), which has run against this library since September 2026.
nonisolated enum NewReleaseMatching {
    /// beets' Discogs plugin writes Discogs integers into MusicBrainz id fields; only real UUIDs are usable.
    static func isMusicBrainzID(_ value: String?) -> Bool {
        guard let value else { return false }
        return value.range(of: #"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"#,
                           options: .regularExpression) != nil
    }

    /// Folds a title down to something two catalogues agree on: diacritics, curly quotes, articles and
    /// edition furniture ("(Deluxe Edition)", " - 2011 Remaster") are dropped. "Tomorrow's Harvest" with
    /// U+2019 equals the ASCII spelling, "Amygdala (deluxe edition)" equals "Amygdala".
    static func normalisedTitle(_ title: String) -> String {
        var text = folded(title)
        text = text.replacingOccurrences(of: "\u{2019}", with: "'").replacingOccurrences(of: "\u{2018}", with: "'")
        text = text.replacingOccurrences(of: "\u{201C}", with: "\"").replacingOccurrences(of: "\u{201D}", with: "\"")
        text = text.replacingOccurrences(of: #"\b(the|a|an)\b"#, with: " ", options: .regularExpression)
        let furniture = #"(deluxe|expanded|remaster(ed)?|edition|anniversary|reissue|bonus|version|mono|stereo)"#
        text = text.replacingOccurrences(of: #"[\(\[][^\)\]]*\b"# + furniture + #"\b[^\)\]]*[\)\]]"#,
                                         with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\s[-–—]\s.*\b(deluxe|remaster(ed)?|edition|reissue)\b.*$"#,
                                         with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
        return text.split(separator: " ").joined(separator: " ")
    }

    /// Artist names compared for a name lookup: case, diacritics and punctuation don't matter.
    static func normalisedName(_ name: String) -> String {
        folded(name)
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .split(separator: " ").joined(separator: " ")
    }

    /// Lowercased, accents removed, and the letters accent folding leaves alone spelled out: "Røyksopp"
    /// matches "Royksopp", "Lindstrøm" matches "Lindstrom" (the NAS job's `_FOLD` table).
    private static func folded(_ text: String) -> String {
        let letters: [Character: String] = ["ø": "o", "æ": "ae", "ß": "ss", "đ": "d", "ð": "d", "ł": "l", "þ": "th", "œ": "oe"]
        let lowered = text.lowercased()
        let spelled = lowered.reduce(into: "") { result, character in result += letters[character] ?? String(character) }
        return spelled.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// "Album", "Single · Remix", "Album · Live".
    static func typeLabel(primary: String?, secondary: [String]) -> String {
        ([primary ?? "Release"] + secondary).joined(separator: " · ")
    }

    /// MusicBrainz dates are partial ("2026", "2026-09", "2026-09-22"); a string comparison handles all of
    /// them. Unknown dates count as released.
    static func isReleased(_ date: String?, today: String) -> Bool {
        guard let date, !date.isEmpty else { return true }
        return date <= today
    }

    /// "2026-09" → 1 September 2026, at noon UTC so no time zone moves it to another day.
    static func date(fromMusicBrainz value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard let year = parts.first else { return nil }
        var components = DateComponents()
        components.year = year
        components.month = parts.count > 1 ? parts[1] : 1
        components.day = parts.count > 2 ? parts[2] : 1
        components.hour = 12
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar.date(from: components)
    }

    /// "2026-10-27" in UTC, the format MusicBrainz' date range queries take.
    static func musicBrainzDay(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
