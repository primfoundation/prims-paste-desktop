import CryptoKit
import Foundation

/// A binary envelope makes old JSON-only readers fail, rather than decode an empty board.
enum IndexEnvelope {
    static let magic = Data("PPI3".utf8)
    static let maximumBytes = 16 * 1024 * 1024

    static func seal(_ plaintext: Data, key: SymmetricKey) throws -> Data {
        guard plaintext.count <= maximumBytes else { throw NotebookError.indexCorrupt }
        return magic + (try CryptoBox.seal(plaintext: plaintext, key: key))
    }

    static func plaintext(_ data: Data, key: SymmetricKey) throws -> Data {
        guard data.count <= maximumBytes + 128 else { throw NotebookError.indexCorrupt }
        if data.starts(with: magic) {
            return try CryptoBox.open(blob: Data(data.dropFirst(magic.count)), key: key)
        }
        // Only a recognizable legacy JSON object is eligible for migration.
        guard data.first == UInt8(ascii: "{") || data.first.map({ [9,10,13,32].contains($0) }) == true else {
            throw NotebookError.indexCorrupt
        }
        return data
    }

    static func decode(_ plaintext: Data) throws -> NotebookIndex {
        guard let object = try JSONSerialization.jsonObject(with: plaintext) as? [String: Any],
              object["items"] is [Any] else { throw NotebookError.indexCorrupt }
        try NotebookCompatibility.requireSupported(object)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let index = try decoder.decode(NotebookIndex.self, from: plaintext)
        guard Set(index.items.map(\.id)).count == index.items.count,
              index.items.allSatisfy({ safeID($0.id) && $0.bytes >= 0 }) else { throw NotebookError.indexCorrupt }
        // macOS commonly uses a case-insensitive filesystem. Reject ambiguous body/image paths.
        var names = Set<String>()
        for item in index.items {
            for name in ["\(item.id).enc"] + (item.hasImage ? ["\(item.id)-img.enc"] : []) {
                guard names.insert(name.precomposedStringWithCanonicalMapping.lowercased()).inserted else {
                    throw NotebookError.indexCorrupt
                }
            }
        }
        return index
    }

    static func safeID(_ id: String) -> Bool {
        !id.isEmpty && id.utf8.count <= 512 && id != "." && id != ".."
            && !id.contains("/") && !id.contains("\\") && !id.unicodeScalars.contains(where: { $0.value < 32 })
    }
}

