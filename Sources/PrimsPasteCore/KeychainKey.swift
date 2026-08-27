// 256-bit notebook key in the login keychain.
// Accessible when this Mac is unlocked; not in iCloud, not in the notebook dir.

import CryptoKit
import Foundation
import Security

public enum KeychainKey {
    public static let service = "sh.prims.paste"
    public static let account = "notebook-aes-256"

    public static func loadOrCreate() throws -> SymmetricKey {
        if let existing = try load() {
            return existing
        }
        let key = SymmetricKey(size: .bits256)
        try save(key)
        return key
    }

    public static func load() throws -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = out as? Data else {
            throw NotebookError.keychain("read failed (\(status))")
        }
        return SymmetricKey(data: data)
    }

    public static func save(_ key: SymmetricKey) throws {
        let data = key.withUnsafeBytes { Data($0) }
        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: data,
        ]
        let status = SecItemAdd(attrs as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let update: [String: Any] = [kSecValueData as String: data]
            let q: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
            let u = SecItemUpdate(q as CFDictionary, update as CFDictionary)
            guard u == errSecSuccess else {
                throw NotebookError.keychain("update failed (\(u))")
            }
            return
        }
        guard status == errSecSuccess else {
            throw NotebookError.keychain("save failed (\(status))")
        }
    }
}
