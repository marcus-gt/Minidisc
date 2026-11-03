import Foundation

// MARK: - Player navigation helpers

/// `inCurrentTab` opens the page in the selected tab when it can show it (Library, Search);
/// otherwise, and by default (the player), it opens in Home.
func postNavigateToAlbum(track: DisplayableSong, inCurrentTab: Bool = false) {
    guard let albumId = track.albumId else { return }
    NotificationCenter.default.post(
        name: .maeksterNavigateToAlbum,
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
        name: .maeksterNavigateToArtist,
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
        name: .maeksterNavigateToPlaylist,
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
    NotificationCenter.default.post(name: .maeksterPlaylistDeleted, object: nil)
}

extension Notification.Name {
    static let maeksterNavigateToLibrary = Notification.Name("maeksterNavigateToLibrary")
    static let maeksterNavigateToDownloads = Notification.Name("maeksterNavigateToDownloads")
    static let maeksterNavigateToAlbum    = Notification.Name("maeksterNavigateToAlbum")
    static let maeksterNavigateToArtist   = Notification.Name("maeksterNavigateToArtist")
    static let maeksterNavigateToPlaylist = Notification.Name("maeksterNavigateToPlaylist")
    static let maeksterPlaylistDeleted    = Notification.Name("maekster.playlistDeleted")
    static let maeksterOfflineLibraryChanged = Notification.Name("maekster.offlineLibraryChanged")
    static let maeksterFavoritesChanged = Notification.Name("maekster.favoritesChanged")
    static let maeksterPlaylistsChanged   = Notification.Name("maekster.playlistsChanged")
    /// The library new-releases feed finished a refresh (#15).
    static let maeksterFreshReleasesChanged = Notification.Name("maekster.freshReleasesChanged")
    static let lidarrLibraryDidChange     = Notification.Name("maekster.lidarrLibraryDidChange")
    static let lidarrQueueDidChange       = Notification.Name("maekster.lidarrQueueDidChange")
}

func postOfflineLibraryChanged() {
    NotificationCenter.default.post(name: .maeksterOfflineLibraryChanged, object: nil)
}
