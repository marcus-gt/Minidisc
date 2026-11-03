import Foundation
import SwiftSonic

/// One album artist the new-releases feed follows, with what the library already has by them.
nonisolated struct WatchedArtist: Sendable, Equatable {
    let name: String
    /// A real MusicBrainz UUID from the tags, if there is one.
    let musicBrainzID: String?
    /// `NewReleaseMatching.normalisedTitle` of every library album by this artist.
    let ownedTitles: Set<String>
}

nonisolated struct NewReleaseWatchlist: Sendable, Equatable {
    let artists: [WatchedArtist]

    /// MusicBrainz' special-purpose artists. Following "Various Artists" because the library has
    /// compilations would list every new compilation on MusicBrainz.
    static let specialPurposeArtistIDs: Set<String> = [
        "89ad4ac3-39f7-470e-963a-56509c546377", // Various Artists
        "125ec42a-7229-4250-afc5-e057484327fe", // [unknown]
        "f731ccc4-e22a-43af-a747-64213329e088", // [anonymous]
        "9be7f096-97ec-4615-8957-8d40b5dcbc41", // [traditional]
        "eec63d3c-3b81-4ad4-b1e4-7c147d4d2b61", // [no artist]
        "33cf029c-63b0-41a0-9855-be2a3665fb3b", // [data]
        "314e1c25-dde7-4e4d-b2f4-0a7b9f7c56dc", // [dialogue]
    ]
    static let specialPurposeNames: Set<String> = ["various artists", "various", "va", "unknown artist", "unknown"]

    /// Album artists with at least one album, from indexed artists and albums.
    static func build(artists: [ArtistID3], albums: [AlbumID3]) -> NewReleaseWatchlist {
        var titles: [String: Set<String>] = [:]
        for album in albums {
            guard let artistID = album.artistId else { continue }
            titles[artistID, default: []].insert(NewReleaseMatching.normalisedTitle(album.name))
        }
        let watched = artists.compactMap { artist -> WatchedArtist? in
            guard let owned = titles[artist.id], !owned.isEmpty,
                  !specialPurposeNames.contains(NewReleaseMatching.normalisedName(artist.name)) else { return nil }
            let mbid = NewReleaseMatching.isMusicBrainzID(artist.musicBrainzId) ? artist.musicBrainzId?.lowercased() : nil
            if let mbid, specialPurposeArtistIDs.contains(mbid) { return nil }
            return WatchedArtist(name: artist.name, musicBrainzID: mbid, ownedTitles: owned)
        }
        return NewReleaseWatchlist(artists: watched.sorted { $0.name < $1.name })
    }
}
