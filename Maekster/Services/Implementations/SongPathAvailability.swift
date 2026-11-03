import Foundation

/// Song Path needs AudioMuse on the active server, and the server itself (#65).
@MainActor
enum SongPathAvailability {
    static func isAvailable(_ container: AppContainer?) -> Bool {
        guard let container, container.serverState.isOnline else { return false }
        return container.serverState.activeServer?.audioMuseURL?.trimmingCharacters(in: .whitespaces).isEmpty == false
    }
}
