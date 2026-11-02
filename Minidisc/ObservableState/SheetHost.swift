import SwiftUI

/// Where a sheet asked for from a menu is presented: over the tabs, or over the full player that
/// covers them. Each presents only its own requests, so the same sheet never opens twice.
nonisolated enum SheetHost: Sendable, Hashable {
    case main, player
}

extension EnvironmentValues {
    /// The full player sets `.player` for the menus inside it.
    @Entry var sheetHost: SheetHost = .main
}

/// Opens the Song Path sheet from anywhere: Discover, Home, a song's menu or the player (#65).
@MainActor @Observable
final class SongPathLauncher {
    struct Request: Identifiable {
        let id = UUID()
        let host: SheetHost
        var from: SongPathService.End?
    }

    var request: Request?

    func open(from: SongPathService.End? = nil, in host: SheetHost) {
        request = Request(host: host, from: from)
    }
}
