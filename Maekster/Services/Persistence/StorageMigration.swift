import Foundation
import OSLog
import Security

/// The one-shot move of everything stored under the pre-rebrand "minidisc" names (#46): files and
/// SwiftData stores, UserDefaults keys and Keychain items. It runs before the container opens any
/// of them, copies before it deletes, and never overwrites something already stored under the new
/// name, so running it again (after a crash or a locked Keychain) is safe.
nonisolated enum StorageMigration {
    /// Files and defaults are done.
    static let doneKey = "maekster.storageMigration_v1"
    /// Keychain items are done. Separate, because the Keychain can be locked during a background
    /// launch; that part then retries on the next launch.
    static let keychainDoneKey = "maekster.storageMigration_v1.keychain"

    static let legacyKeychainService = "app.minidisc.server-credentials"
    static let keychainService = "app.maekster.server-credentials"

    struct Locations {
        var directories: [URL]
        var legacyKeychainService: String
        var keychainService: String

        static var live: Locations {
            let fileManager = FileManager.default
            return Locations(
                directories: [
                    fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0],
                    fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0],
                    URL.applicationSupportDirectory
                ],
                legacyKeychainService: StorageMigration.legacyKeychainService,
                keychainService: StorageMigration.keychainService
            )
        }
    }

    static func runIfNeeded(defaults: UserDefaults = .standard, locations: Locations = .live) {
        if !defaults.bool(forKey: doneKey) {
            let filesMoved = moveFiles(in: locations.directories)
            migrateDefaults(defaults)
            if filesMoved {
                defaults.set(true, forKey: doneKey)
                Logger.migration.notice("[StorageMigration] files and settings moved to maekster names")
            }
        }
        if !defaults.bool(forKey: keychainDoneKey),
           migrateKeychain(from: locations.legacyKeychainService, to: locations.keychainService) {
            defaults.set(true, forKey: keychainDoneKey)
            Logger.migration.notice("[StorageMigration] keychain items moved to maekster names")
        }
    }

    /// The maekster name for a stored minidisc one, or nil when the name isn't one of ours.
    static func renamed(_ name: String) -> String? {
        for (old, new) in [("app.minidisc", "app.maekster"), (".minidisc", ".maekster"), ("minidisc", "maekster")]
        where name.hasPrefix(old) {
            return new + name.dropFirst(old.count)
        }
        return nil
    }

    // MARK: - Files

    /// Renames the top-level items of each directory. Returns false if anything couldn't be moved.
    static func moveFiles(in directories: [URL]) -> Bool {
        var succeeded = true
        for directory in directories {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
            for name in names {
                guard let newName = renamed(name) else { continue }
                if !move(directory.appendingPathComponent(name), to: directory.appendingPathComponent(newName)) {
                    succeeded = false
                }
            }
        }
        return succeeded
    }

    /// Moves `source` to `destination`. A directory that already exists there gets the source's
    /// missing items; a file that already exists there wins and the source stays where it is.
    private static func move(_ source: URL, to destination: URL) -> Bool {
        let fileManager = FileManager.default
        var destinationIsDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: destination.path, isDirectory: &destinationIsDirectory) else {
            do {
                try fileManager.moveItem(at: source, to: destination)
                return true
            } catch {
                Logger.migration.error("[StorageMigration] couldn't move '\(source.lastPathComponent, privacy: .public)': \(error, privacy: .public)")
                return false
            }
        }
        var sourceIsDirectory: ObjCBool = false
        fileManager.fileExists(atPath: source.path, isDirectory: &sourceIsDirectory)
        guard sourceIsDirectory.boolValue, destinationIsDirectory.boolValue else {
            Logger.migration.error("[StorageMigration] '\(destination.lastPathComponent, privacy: .public)' already exists; kept '\(source.lastPathComponent, privacy: .public)'")
            return true
        }
        var succeeded = true
        for child in (try? fileManager.contentsOfDirectory(atPath: source.path)) ?? [] {
            if !move(source.appendingPathComponent(child), to: destination.appendingPathComponent(child)) {
                succeeded = false
            }
        }
        if (try? fileManager.contentsOfDirectory(atPath: source.path))?.isEmpty == true {
            try? fileManager.removeItem(at: source)
        }
        return succeeded
    }

    // MARK: - Defaults

    static func migrateDefaults(_ defaults: UserDefaults) {
        for (key, value) in defaults.dictionaryRepresentation() {
            guard let newKey = renamed(key) else { continue }
            if defaults.object(forKey: newKey) == nil {
                defaults.set(value, forKey: newKey)
            }
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: - Keychain

    /// Moves every item of the legacy service to the new one, under its renamed account. Returns
    /// false when the Keychain couldn't be read or an item couldn't be written; those stay put.
    static func migrateKeychain(from legacyService: String, to service: String) -> Bool {
        var result: AnyObject?
        let status = SecItemCopyMatching([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: legacyService,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true
        ] as CFDictionary, &result)
        if status == errSecItemNotFound { return true }
        guard status == errSecSuccess, let items = result as? [[String: Any]] else {
            Logger.migration.error("[StorageMigration] keychain not readable yet (OSStatus \(status)); retrying next launch")
            return false
        }

        var succeeded = true
        for item in items {
            guard let account = item[kSecAttrAccount as String] as? String else { continue }
            let legacyQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: legacyService,
                kSecAttrAccount as String: account
            ]
            var data: AnyObject?
            var readQuery = legacyQuery
            readQuery[kSecReturnData as String] = true
            readQuery[kSecMatchLimit as String] = kSecMatchLimitOne
            guard SecItemCopyMatching(readQuery as CFDictionary, &data) == errSecSuccess, let data = data as? Data else {
                succeeded = false
                continue
            }
            let addStatus = SecItemAdd([
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: renamed(account) ?? account,
                kSecValueData as String: data,
                kSecAttrAccessible as String: item[kSecAttrAccessible as String]
                    ?? kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ] as CFDictionary, nil)
            // Something already stored under the new name is newer; the old copy just goes.
            guard addStatus == errSecSuccess || addStatus == errSecDuplicateItem else {
                Logger.migration.error("[StorageMigration] keychain write failed (OSStatus \(addStatus)); kept the old item")
                succeeded = false
                continue
            }
            SecItemDelete(legacyQuery as CFDictionary)
        }
        return succeeded
    }
}
