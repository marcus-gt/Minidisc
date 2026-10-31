import Foundation

/// Where the queue came from (#71), shown as "Playing from" in the player and "Next from" above the
/// queue. Set by whatever started playback and saved with the session.
nonisolated enum QueueSource: Codable, Sendable, Hashable {
    case album(id: String, name: String)
    case playlist(id: String, name: String)
    /// An artist's songs: top songs, shuffle or best of.
    case artist(id: String, name: String)
    /// An artist station: Instant Mix around the artist.
    case artistRadio(id: String, name: String)
    /// Instant Mix around a song or album.
    case instantMix(title: String)
    case smartShuffle
    case queueBuilder
    case moodRadio(moodRawValue: String)
    case wrappedRadio(WrappedPeriod)
    /// Wrapped's top tracks for a period.
    case wrapped(WrappedPeriod)
    case genre(name: String)
    case recordLabel(name: String)
    case search(query: String)
    case favorites
    case downloads
    case recentlyAdded
    case songs
    case localFolder(name: String)

    static func moodRadio(_ mood: Mood) -> QueueSource { .moodRadio(moodRawValue: mood.rawValue) }

    /// An album, playlist or artist from a collection menu or shelf.
    static func collection(_ type: PinnedItemType, id: String, name: String) -> QueueSource {
        switch type {
        case .album: .album(id: id, name: name)
        case .playlist: .playlist(id: id, name: name)
        case .artist: .artist(id: id, name: name)
        }
    }

    /// A single song played on its own counts as playing from its album, when it has one.
    static func album(of song: DisplayableSong) -> QueueSource? {
        guard let id = song.albumId, let name = song.albumName else { return nil }
        return .album(id: id, name: name)
    }

    /// An Instant Mix: an artist's is that artist's radio, a song's or album's is named after it.
    static func instantMix(seed: InstantMixSeed, title: String?) -> QueueSource? {
        guard let title, !title.isEmpty else { return nil }
        if case .artist(let id) = seed { return .artistRadio(id: id, name: title) }
        return .instantMix(title: title)
    }

    /// Radios and mixes refill with picks of their own, so the label stays when they extend.
    /// Anything else ends, and what follows is "Similar to" it.
    var isEndless: Bool {
        switch self {
        case .artistRadio, .instantMix, .smartShuffle, .queueBuilder, .moodRadio, .wrappedRadio: true
        default: false
        }
    }

    /// An album needs no label: the player already names the playing track's album.
    var isSelfEvident: Bool {
        if case .album = self { return true }
        return false
    }

    /// The source's own name, without what kind it is: "Jazz tunes", "Bill Evans".
    var name: String {
        switch self {
        case .album(_, let name), .playlist(_, let name), .artist(_, let name), .genre(let name),
             .recordLabel(let name), .localFolder(let name):
            name
        default:
            title
        }
    }

    /// One line that says what kind it is and which (#71): "Playlist: Jazz tunes",
    /// "Instant Mix: Peace Piece", "Chill radio".
    var title: String {
        switch self {
        case .album(_, let name), .localFolder(let name): name
        case .playlist(_, let name): String(localized: "Playlist: \(name)")
        case .artist(_, let name): String(localized: "Artist: \(name)")
        case .genre(let name): String(localized: "Genre: \(name)")
        case .recordLabel(let name): String(localized: "Label: \(name)")
        case .artistRadio(_, let name): String(localized: "\(name) radio")
        case .instantMix(let title): String(localized: "Instant Mix: \(title)")
        case .smartShuffle: String(localized: "Smart Shuffle")
        case .queueBuilder: String(localized: "Queue Builder")
        case .moodRadio(let raw):
            Mood(rawValue: raw).map { String(localized: "\(String(localized: $0.title)) radio") } ?? String(localized: "Mood radio")
        case .wrappedRadio(let period): String(localized: "Wrapped \(period.displayName) radio")
        case .wrapped(let period): String(localized: "Wrapped \(period.displayName)")
        case .search(let query): String(localized: "Search: \(query)")
        case .favorites: String(localized: "Favorites")
        case .downloads: String(localized: "Downloads")
        case .recentlyAdded: String(localized: "Recently Added")
        case .songs: String(localized: "Songs")
        }
    }

    /// The label once auto-extend has taken over from a source that ended (#71, 3a).
    var similarTitle: String { String(localized: "Similar to \(name)") }

    /// What tapping "Playing from" opens; nil when the source has no page.
    var destination: Destination? {
        switch self {
        case .album(let id, _): .album(id: id)
        case .playlist(let id, let name): .playlist(id: id, name: name)
        case .artist(let id, _), .artistRadio(let id, _): .artist(id: id)
        default: nil
        }
    }

    nonisolated enum Destination: Sendable, Hashable {
        case album(id: String)
        case playlist(id: String, name: String)
        case artist(id: String)
    }
}

/// What the player shows for the playing track and the next one, given the queue's source and
/// where auto-extended tracks begin.
nonisolated struct QueueSourceLabel: Sendable, Equatable {
    let title: String
    /// False once the label describes auto-extended tracks: those aren't the source's page.
    let opensSource: Bool

    /// `index` is the track the label is for; tracks at `extensionStart` and after were added by
    /// auto-extend. A plain album shows nothing until auto-extend takes over from it.
    init?(source: QueueSource?, index: Int, extensionStart: Int?) {
        guard let source else { return nil }
        if !source.isEndless, let extensionStart, index >= extensionStart {
            title = source.similarTitle
            opensSource = false
        } else {
            guard !source.isSelfEvident else { return nil }
            title = source.title
            opensSource = source.destination != nil
        }
    }
}
