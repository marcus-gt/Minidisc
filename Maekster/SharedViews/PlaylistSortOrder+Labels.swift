import SwiftUI

extension PlaylistSortOrder {
    var label: LocalizedStringKey {
        switch self {
        case .playlistOrder: "Playlist Order"
        case .title: "Title"
        case .artist: "Artist"
        case .album: "Album"
        }
    }

    /// Direction labels follow the field: positions read as first/last, text fields as A to Z.
    func label(for direction: PlaylistSortDirection) -> LocalizedStringKey {
        switch (self, direction) {
        case (.playlistOrder, .ascending): "First to Last"
        case (.playlistOrder, .descending): "Last to First"
        case (_, .ascending): "A to Z"
        case (_, .descending): "Z to A"
        }
    }
}
