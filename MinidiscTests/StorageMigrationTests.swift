import Foundation
import Security
import Testing
@testable import Minidisc

/// Moving data stored under the pre-rebrand names (#46).
@Suite("Storage migration")
struct StorageMigrationTests {
    private func temporaryDirectory() throws -> URL {
        let url = URL.temporaryDirectory.appendingPathComponent("storage-migration-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func read(_ url: URL) -> String? {
        (try? Data(contentsOf: url)).map { String(decoding: $0, as: UTF8.self) }
    }

    @Test func names_mapToMaekster() {
        #expect(StorageMigration.renamed("minidisc.cache.format") == "maekster.cache.format")
        #expect(StorageMigration.renamed("app.minidisc.lidarr.baseURL") == "app.maekster.lidarr.baseURL")
        #expect(StorageMigration.renamed("app.minidisc") == "app.maekster")
        #expect(StorageMigration.renamed("minidisc-session.store-wal") == "maekster-session.store-wal")
        #expect(StorageMigration.renamed(".minidisc-session_SUPPORT") == ".maekster-session_SUPPORT")
        #expect(StorageMigration.renamed("minidisc.server.1234") == "maekster.server.1234")
        #expect(StorageMigration.renamed("default.store") == nil)
        #expect(StorageMigration.renamed("maekster.homeLayout") == nil)
    }

    /// Stores move with their -wal and -shm files; folders move whole or merge into one that exists.
    @Test func files_moveOrMerge_neverOverwrite() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        for suffix in ["", "-wal", "-shm"] {
            try write("session\(suffix)", to: directory.appendingPathComponent("minidisc-session.store\(suffix)"))
        }
        try write("song", to: directory.appendingPathComponent("app.minidisc/downloads/a.flac"))
        try write("old cover", to: directory.appendingPathComponent("app.minidisc/coverarts/x.jpg"))
        // Already under the new name (created by something that ran first): it wins.
        try write("new cover", to: directory.appendingPathComponent("app.maekster/coverarts/x.jpg"))
        try write("other app data", to: directory.appendingPathComponent("default.store"))

        #expect(StorageMigration.moveFiles(in: [directory]))

        for suffix in ["", "-wal", "-shm"] {
            #expect(read(directory.appendingPathComponent("maekster-session.store\(suffix)")) == "session\(suffix)")
        }
        #expect(read(directory.appendingPathComponent("app.maekster/downloads/a.flac")) == "song")
        #expect(read(directory.appendingPathComponent("app.maekster/coverarts/x.jpg")) == "new cover")
        #expect(read(directory.appendingPathComponent("default.store")) == "other app data")
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("minidisc-session.store").path))
        // A second run has nothing left to do.
        #expect(StorageMigration.moveFiles(in: [directory]))
    }

    @Test func defaults_moveWithoutOverwriting() throws {
        let suite = "storage-migration-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("flac", forKey: "minidisc.cache.format")
        defaults.set("https://lidarr", forKey: "app.minidisc.lidarr.baseURL")
        defaults.set(true, forKey: "minidisc.audioExtMigration_v1")
        defaults.set("old", forKey: "minidisc.homeLayout")
        defaults.set("new", forKey: "maekster.homeLayout")

        StorageMigration.migrateDefaults(defaults)

        #expect(defaults.string(forKey: "maekster.cache.format") == "flac")
        #expect(defaults.string(forKey: "app.maekster.lidarr.baseURL") == "https://lidarr")
        // Finished one-shot migrations stay finished.
        #expect(defaults.bool(forKey: "maekster.audioExtMigration_v1"))
        #expect(defaults.string(forKey: "maekster.homeLayout") == "new")
        #expect(defaults.object(forKey: "minidisc.cache.format") == nil)
        #expect(defaults.object(forKey: "minidisc.homeLayout") == nil)
    }

    /// Server logins and tokens move to the new service and account names, and the old items go.
    @Test func keychain_itemsMoveToTheNewService() throws {
        let legacy = "test.minidisc.\(UUID())"
        let current = "test.maekster.\(UUID())"
        defer {
            for service in [legacy, current] {
                SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary)
            }
        }
        func add(_ account: String, _ value: String, service: String) {
            SecItemAdd([
                kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                kSecAttrAccount as String: account, kSecValueData as String: Data(value.utf8),
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ] as CFDictionary, nil)
        }
        func value(_ account: String, service: String) -> String? {
            var result: AnyObject?
            let status = SecItemCopyMatching([
                kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                kSecAttrAccount as String: account, kSecReturnData as String: true
            ] as CFDictionary, &result)
            guard status == errSecSuccess, let data = result as? Data else { return nil }
            return String(decoding: data, as: UTF8.self)
        }
        add("minidisc.server.A", "password", service: legacy)
        add("app.minidisc.listenbrainz.token", "token", service: legacy)
        add("app.minidisc.lidarr.credentials", "old key", service: legacy)
        add("app.maekster.lidarr.credentials", "new key", service: current)

        #expect(StorageMigration.migrateKeychain(from: legacy, to: current))

        #expect(value("maekster.server.A", service: current) == "password")
        #expect(value("app.maekster.listenbrainz.token", service: current) == "token")
        #expect(value("app.maekster.lidarr.credentials", service: current) == "new key")
        #expect(value("minidisc.server.A", service: legacy) == nil)
        #expect(value("app.minidisc.lidarr.credentials", service: legacy) == nil)
        // Nothing left: a second run is a no-op.
        #expect(StorageMigration.migrateKeychain(from: legacy, to: current))
    }

    @Test func run_marksItselfDone() throws {
        let suite = "storage-migration-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        defaults.set(42, forKey: "minidisc.lastVolume")

        StorageMigration.runIfNeeded(defaults: defaults, locations: .init(
            directories: [directory],
            legacyKeychainService: "test.minidisc.\(UUID())",
            keychainService: "test.maekster.\(UUID())"
        ))

        #expect(defaults.integer(forKey: "maekster.lastVolume") == 42)
        #expect(defaults.bool(forKey: StorageMigration.doneKey))
        #expect(defaults.bool(forKey: StorageMigration.keychainDoneKey))
    }
}
