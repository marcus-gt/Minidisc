import Foundation

/// When each playlist was last used on this device: songs added to it, or playback started from it.
/// Kept per server; the Playlists list sorts by it ("Last Used").
nonisolated final class PlaylistUsageStore: Sendable {
    /// Oldest entries are dropped beyond this, so the dictionary stays small.
    static let maxEntries = 500

    private let defaults: LockedUserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = LockedUserDefaults(defaults)
    }

    static func key(serverID: String) -> String {
        "minidisc.playlistLastUsed.\(serverID)"
    }

    func lastUsed(serverID: String) -> [String: Date] {
        (defaults.doubleDictionary(forKey: Self.key(serverID: serverID)) ?? [:])
            .mapValues { Date(timeIntervalSinceReferenceDate: $0) }
    }

    func recordUse(playlistID: String, serverID: String, at date: Date = Date()) {
        guard !playlistID.isEmpty, !serverID.isEmpty else { return }
        defaults.updateDoubleDictionary(forKey: Self.key(serverID: serverID)) { current in
            var entries = current
            entries[playlistID] = date.timeIntervalSinceReferenceDate
            guard entries.count > Self.maxEntries else { return entries }
            let keep = entries.sorted { $0.value > $1.value }.prefix(Self.maxEntries)
            return Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
    }
}
