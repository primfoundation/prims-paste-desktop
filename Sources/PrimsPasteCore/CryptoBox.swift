// AES-GCM sealed blobs. Magic prefix so we refuse to open random files.
// Combined nonce+ciphertext+tag; key never written next to the blob.

import CryptoKit
import Foundation

public enum CryptoBox {
    public static let magic = Data("PPB1".utf8)

    public static func fingerprint(_ data: Data, prefix: Int = 12) -> String {
        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(prefix))
    }

    public static func seal(plaintext: Data, key: SymmetricKey) throws -> Data {
        let box = try AES.GCM.seal(plaintext, using: key)
        guard let combined = box.combined else {
            throw NotebookError.badMagic
        }
        return magic + combined
    }

    public static func open(blob: Data, key: SymmetricKey) throws -> Data {
        try open(blob: blob, key: key, magic: magic)
    }

    public static func open(blob: Data, key: SymmetricKey, magic: Data) throws -> Data {
        guard blob.count > magic.count, blob.prefix(magic.count) == magic else {
            throw NotebookError.badMagic
        }
        let combined = blob.suffix(from: magic.count)
        let box = try AES.GCM.SealedBox(combined: Data(combined))
        return try AES.GCM.open(box, using: key)
    }
}
