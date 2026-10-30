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

    /// "PLAYING FROM ALBUM": what kind of thing the source is.
    var kind: String {
        switch self {
        case .album: String(localized: "Album")
        case .playlist: String(localized: "Playlist")
        case .artist: String(localized: "Artist")
        case .artistRadio, .moodRadio, .wrappedRadio: String(localized: "Radio")
        case .instantMix, .smartShuffle, .queueBuilder: String(localized: "Mix")
        case .wrapped: String(localized: "Wrapped")
        case .genre: String(localized: "Genre")
        case .recordLabel: String(localized: "Label")
        case .search: String(localized: "Search")
        case .favorites, .downloads, .recentlyAdded, .songs, .localFolder: String(localized: "Library")
        }
    }

    /// The source's own name: "Kind of Blue", "Chill radio", "Bill Evans radio".
    var title: String {
        switch self {
        case .album(_, let name), .playlist(_, let name), .artist(_, let name), .genre(let name),
             .recordLabel(let name), .localFolder(let name):
            name
        case .artistRadio(_, let name): String(localized: "\(name) radio")
        case .instantMix(let title): String(localized: "Instant Mix: \(title)")
        case .smartShuffle: String(localized: "Smart Shuffle")
        case .queueBuilder: String(localized: "Queue Builder")
        case .moodRadio(let raw):
            Mood(rawValue: raw).map { String(localized: "\(String(localized: $0.title)) radio") } ?? String(localized: "Mood radio")
        case .wrappedRadio(let period): String(localized: "Wrapped \(period.displayName) radio")
        case .wrapped(let period): String(localized: "Wrapped \(period.displayName)")
        case .search(let query): String(localized: "“\(query)”")
        case .favorites: String(localized: "Favorites")
        case .downloads: String(localized: "Downloads")
        case .recentlyAdded: String(localized: "Recently Added")
        case .songs: String(localized: "Songs")
        }
    }

    /// The label once auto-extend has taken over from a source that ended (#71, 3a).
    var similarTitle: String { String(localized: "Similar to \(title)") }

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
    let kind: String
    let title: String
    /// False once the label describes auto-extended tracks: those aren't the source's page.
    let opensSource: Bool

    /// `index` is the track the label is for; tracks at `extensionStart` and after were added by
    /// auto-extend.
    init?(source: QueueSource?, index: Int, extensionStart: Int?) {
        guard let source else { return nil }
        if !source.isEndless, let extensionStart, index >= extensionStart {
            kind = String(localized: "Autoplay")
            title = source.similarTitle
            opensSource = false
        } else {
            kind = source.kind
            title = source.title
            opensSource = source.destination != nil
        }
    }
}
