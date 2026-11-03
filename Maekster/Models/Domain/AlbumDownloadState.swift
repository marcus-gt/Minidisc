import Foundation

/// How much of an album is downloaded, and what the album page's download button does about it.
nonisolated enum AlbumDownloadState {
    case notDownloaded
    case partiallyDownloaded
    case fullyDownloaded

    init(songs: [DisplayableSong]) {
        guard !songs.isEmpty else {
            self = .notDownloaded
            return
        }
        let downloaded = songs.lazy.filter(\.isDownloaded).count
        if downloaded == 0 {
            self = .notDownloaded
        } else if downloaded == songs.count {
            self = .fullyDownloaded
        } else {
            self = .partiallyDownloaded
        }
    }
}

nonisolated enum AlbumDownloadControlState: Equatable {
    case unavailable
    case download
    case downloadMissing
    case cancel
    case removeDownloaded

    var systemImage: String {
        switch self {
        case .unavailable, .download, .downloadMissing:
            "arrow.down"
        case .cancel:
            "xmark"
        case .removeDownloaded:
            "trash"
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .unavailable, .download: "Download Album"
        case .downloadMissing: "Download Missing Tracks"
        case .cancel: "Cancel Download"
        case .removeDownloaded: "Remove Download"
        }
    }
}

extension AlbumDownloadControlState {
    /// The album page's download button for an album loaded from the server.
    init(songs: [DisplayableSong], isOffline: Bool, isDownloading: Bool) {
        guard !isOffline else { self = .unavailable; return }
        if isDownloading { self = .cancel; return }
        switch AlbumDownloadState(songs: songs) {
        case .notDownloaded: self = songs.isEmpty ? .unavailable : .download
        case .partiallyDownloaded: self = .downloadMissing
        case .fullyDownloaded: self = .removeDownloaded
        }
    }
}
