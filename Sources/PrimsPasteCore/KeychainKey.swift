// 256-bit notebook key in the login keychain.
// Accessible when this Mac is unlocked; not in iCloud, not in the notebook dir.

import CryptoKit
import Foundation
import Security

public enum KeychainKey {
    public static let service = "sh.prims.paste"
    public static let account = "notebook-aes-256"

    public static func loadOrCreate() throws -> SymmetricKey {
        try resolve(notebookRoot: Paths.defaultRoot, read: load, insert: insertIfAbsent)
    }

    // Injectable operations let regression tests use synthetic keys, never Keychain.
    static func resolve(notebookRoot: URL, read: () throws -> SymmetricKey?,
                        insert: (SymmetricKey) throws -> Bool) throws -> SymmetricKey {
        if let existing = try read() { return existing }
        let fm = FileManager.default
        if fm.fileExists(atPath: notebookRoot.path) ||
            (try? fm.destinationOfSymbolicLink(atPath: notebookRoot.path)) != nil {
            let attributes = try fm.attributesOfItem(atPath: notebookRoot.path)
            guard attributes[.type] as? FileAttributeType == .typeDirectory,
                  try fm.contentsOfDirectory(atPath: notebookRoot.path).isEmpty else {
                throw NotebookError.keychain("the original notebook key is missing; no replacement key was created")
            }
        }
        let candidate = SymmetricKey(size: .bits256)
        if try insert(candidate) { return candidate }
        // Another app/CLI process won first creation. Use its key; never overwrite it.
        guard let winner = try read() else {
            throw NotebookError.keychain("key creation changed concurrently; no existing key was replaced")
        }
        return winner
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
        guard data.count == 32 else { throw NotebookError.keychain("stored notebook key has an unsupported length") }
        return SymmetricKey(data: data)
    }

    /// An explicit save also refuses replacement. Key rotation requires its own migration.
    public static func save(_ key: SymmetricKey) throws {
        guard try insertIfAbsent(key) else {
            throw NotebookError.keychain("an existing notebook key was not replaced")
        }
    }

    private static func insertIfAbsent(_ key: SymmetricKey) throws -> Bool {
        let data = key.withUnsafeBytes { Data($0) }
        guard data.count == 32 else { throw NotebookError.keychain("notebook key must be 256 bits") }
        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: data,
        ]
        let status = SecItemAdd(attrs as CFDictionary, nil)
        if status == errSecDuplicateItem { return false }
        guard status == errSecSuccess else {
            throw NotebookError.keychain("save failed (\(status))")
        }
        return true
    }
}
