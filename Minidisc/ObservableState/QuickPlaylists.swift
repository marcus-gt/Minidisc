import Foundation
import Observation
import SwiftUI

/// Playlists one long-press away from the heart (#68): the few a listener adds to all the time.
/// Kept per server, in the order chosen, apart from pinned items.
@MainActor @Observable
final class QuickPlaylists {
    nonisolated struct Entry: Codable, Hashable, Identifiable, Sendable {
        let id: String
        var name: String
    }

    static let alsoLikesKey = "minidisc.quickPlaylists.alsoLikes"

    /// Like the song as well when it's added from the heart's menu. On by default: the flow this
    /// replaces was "like, then add to a playlist".
    var alsoLikes: Bool {
        didSet { defaults.set(alsoLikes, forKey: Self.alsoLikesKey) }
    }

    private let defaults: UserDefaults
    private var byServer: [String: [Entry]] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        alsoLikes = defaults.object(forKey: Self.alsoLikesKey) as? Bool ?? true
    }

    static func key(serverID: String) -> String { "minidisc.quickPlaylists.\(serverID)" }

    func entries(serverID: String) -> [Entry] {
        if let loaded = byServer[serverID] { return loaded }
        let stored = defaults.data(forKey: Self.key(serverID: serverID))
            .flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? []
        byServer[serverID] = stored
        return stored
    }

    func contains(_ playlistID: String, serverID: String) -> Bool {
        entries(serverID: serverID).contains { $0.id == playlistID }
    }

    /// Adds the playlist at the end, or takes it off the list.
    func toggle(id: String, name: String, serverID: String) {
        var list = entries(serverID: serverID)
        if list.contains(where: { $0.id == id }) {
            list.removeAll { $0.id == id }
        } else {
            list.append(Entry(id: id, name: name))
        }
        save(list, serverID: serverID)
    }

    func remove(atOffsets offsets: IndexSet, serverID: String) {
        var list = entries(serverID: serverID)
        list.remove(atOffsets: offsets)
        save(list, serverID: serverID)
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int, serverID: String) {
        var list = entries(serverID: serverID)
        list.move(fromOffsets: source, toOffset: destination)
        save(list, serverID: serverID)
    }

    /// Follows renames and drops playlists that no longer exist, given the server's current list.
    func reconcile(with playlists: [(id: String, name: String)], serverID: String) {
        let current = Dictionary(playlists.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let list = entries(serverID: serverID).compactMap { entry in
            current[entry.id].map { Entry(id: entry.id, name: $0) }
        }
        if list != entries(serverID: serverID) { save(list, serverID: serverID) }
    }

    private func save(_ list: [Entry], serverID: String) {
        byServer[serverID] = list
        defaults.set(try? JSONEncoder().encode(list), forKey: Self.key(serverID: serverID))
    }
}
