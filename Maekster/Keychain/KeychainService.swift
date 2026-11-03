import Foundation
import Security
import OSLog

actor KeychainService: KeychainServiceProtocol {
    private let service = "app.maekster.server-credentials"

    func store<T: Codable & Sendable>(_ value: T, forKey key: String) async throws {
        let data = try JSONEncoder().encode(value)

        let itemQuery = self.itemQuery(forKey: key)
        let attributes: [String: Any] = [
            kSecValueData as String:      data,
            // AfterFirstUnlock allows Keychain reads while the screen is locked,
            // required for auto-next playback transitions triggered in lock screen.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        // Update in place so a failed write preserves the existing credential.
        let updateStatus = SecItemUpdate(itemQuery as CFDictionary, attributes as CFDictionary)
        let status: OSStatus
        if updateStatus == errSecItemNotFound {
            var addQuery = itemQuery
            attributes.forEach { addQuery[$0.key] = $0.value }
            status = SecItemAdd(addQuery as CFDictionary, nil)
        } else {
            status = updateStatus
        }

        guard status == errSecSuccess else {
            // Never log `data` — it may contain credentials.
            Logger.keychain.error("Keychain write failed for key '\(key, privacy: .public)' — OSStatus \(status)")
            throw MaeksterError.keychainWriteFailed(status)
        }
    }

    func retrieve<T: Codable & Sendable>(_ type: T.Type, forKey key: String) async throws -> T? {
        var query = itemQuery(forKey: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status != errSecItemNotFound else { return nil }
        guard status == errSecSuccess else {
            Logger.keychain.error("Keychain read failed for key '\(key, privacy: .public)' — OSStatus \(status)")
            throw MaeksterError.keychainReadFailed(status)
        }

        guard let data = result as? Data else { return nil }
        return try JSONDecoder().decode(type, from: data)
    }

    func delete(forKey key: String) async throws {
        let query = itemQuery(forKey: key)

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            Logger.keychain.error("Keychain delete failed for key '\(key, privacy: .public)' — OSStatus \(status)")
            throw MaeksterError.keychainDeleteFailed(status)
        }
    }

    /// Identifies one credential. On macOS this asks for the data protection keychain, the one iOS
    /// always uses: without it a Mac app reads the legacy login keychain and can't see credentials
    /// saved by maekster's iPhone build running on the same Mac (#102).
    private func itemQuery(forKey key: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        #if os(macOS)
        query[kSecUseDataProtectionKeychain as String] = true
        #endif
        return query
    }
}
