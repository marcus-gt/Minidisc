import Foundation

// MARK: - Player navigation helpers

/// `inCurrentTab` opens the page in the selected tab when it can show it (Library, Search);
/// otherwise, and by default (the player), it opens in Home.
func postNavigateToAlbum(track: DisplayableSong, inCurrentTab: Bool = false) {
    guard let albumId = track.albumId else { return }
    NotificationCenter.default.post(
        name: .minidiscNavigateToAlbum,
        object: nil,
        userInfo: [
            "albumId":   albumId,
            "albumName": track.albumName ?? "",
            "coverArtId": track.coverArtId as Any,
            "inCurrentTab": inCurrentTab
        ]
    )
}

func postNavigateToArtist(track: DisplayableSong, inCurrentTab: Bool = false) {
    guard let artistId = track.artistId else { return }
    postNavigateToArtist(
        artistId: artistId, artistName: track.artist ?? "", coverArtId: track.coverArtId, inCurrentTab: inCurrentTab
    )
}

func postNavigateToArtist(artistId: String, artistName: String, coverArtId: String?, inCurrentTab: Bool = false) {
    NotificationCenter.default.post(
        name: .minidiscNavigateToArtist,
        object: nil,
        userInfo: [
            "artistId":   artistId,
            "artistName": artistName,
            "coverArtId": coverArtId as Any,
            "inCurrentTab": inCurrentTab
        ]
    )
}

func postNavigateToPlaylist(playlistId: String, name: String, coverArtId: String?) {
    NotificationCenter.default.post(
        name: .minidiscNavigateToPlaylist,
        object: nil,
        userInfo: [
            "playlistId": playlistId,
            "name":       name,
            "coverArtId": coverArtId as Any
        ]
    )
}

/// A playlist was deleted (server-confirmed) from a detail surface. The playlist list observes this to reload,
/// so the deleted playlist disappears on return without a manual refresh — and without an `.onAppear` reload.
func postPlaylistDeleted() {
    NotificationCenter.default.post(name: .minidiscPlaylistDeleted, object: nil)
}

extension Notification.Name {
    static let minidiscNavigateToLibrary = Notification.Name("minidiscNavigateToLibrary")
    static let minidiscNavigateToDownloads = Notification.Name("minidiscNavigateToDownloads")
    static let minidiscNavigateToAlbum    = Notification.Name("minidiscNavigateToAlbum")
    static let minidiscNavigateToArtist   = Notification.Name("minidiscNavigateToArtist")
    static let minidiscNavigateToPlaylist = Notification.Name("minidiscNavigateToPlaylist")
    static let minidiscPlaylistDeleted    = Notification.Name("minidisc.playlistDeleted")
    static let minidiscOfflineLibraryChanged = Notification.Name("minidisc.offlineLibraryChanged")
    static let minidiscFavoritesChanged = Notification.Name("minidisc.favoritesChanged")
    static let minidiscPlaylistsChanged   = Notification.Name("minidisc.playlistsChanged")
    static let minidiscMoodPlaylistsChanged = Notification.Name("minidisc.moodPlaylistsChanged")
    /// The library new-releases feed finished a refresh (#15).
    static let minidiscFreshReleasesChanged = Notification.Name("minidisc.freshReleasesChanged")
    static let lidarrLibraryDidChange     = Notification.Name("minidisc.lidarrLibraryDidChange")
    static let lidarrQueueDidChange       = Notification.Name("minidisc.lidarrQueueDidChange")
}

func postOfflineLibraryChanged() {
    NotificationCenter.default.post(name: .minidiscOfflineLibraryChanged, object: nil)
}
