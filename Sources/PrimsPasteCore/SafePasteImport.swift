// One-shot move of the old SafePaste GUI notebook into this store.
// Not a runtime coupling: SafePaste CLI stays paste/move/list/expire.

import CoreGraphics
import CryptoKit
import Foundation
import Security

public enum SafePasteImport {
    public static let magic = Data("SPB1".utf8)
    public static let service = "com.eidos.safepaste"
    public static let account = "notebook-aes-256"

    public static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".safepaste/notebook")
    }

    public struct Report: Equatable, Sendable {
        public var imported: Int
        public var skipped: Int
        public var ids: [String]
        public init(imported: Int = 0, skipped: Int = 0, ids: [String] = []) {
            self.imported = imported
            self.skipped = skipped
            self.ids = ids
        }
    }

    public static func loadLegacyKey() throws -> SymmetricKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        guard status == errSecSuccess, let data = out as? Data else {
            throw NotebookError.keychain("legacy safepaste key missing (\(status))")
        }
        return SymmetricKey(data: data)
    }

    public static func run(
        into dest: NotebookStore,
        from root: URL = defaultRoot,
        oldKey: SymmetricKey
    ) throws -> Report {
        let indexURL = root.appendingPathComponent("index.json")
        let blobs = root.appendingPathComponent("blobs")
        guard FileManager.default.fileExists(atPath: indexURL.path) else {
            return Report()
        }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let src = try dec.decode(NotebookIndex.self, from: Data(contentsOf: indexURL))
        var report = Report()
        var destItems = try dest.loadIndex().items

        for item in src.items where shouldImport(item) {
            let blobURL = blobs.appendingPathComponent("\(item.id).enc")
            guard FileManager.default.fileExists(atPath: blobURL.path) else {
                report.skipped += 1
                continue
            }
            if alreadyHave(item, in: destItems) {
                report.skipped += 1
                continue
            }
            let sealed = try Data(contentsOf: blobURL)
            let plain = try CryptoBox.open(blob: sealed, key: oldKey, magic: magic)
            let tabID = try ensureDayTab(dest, day: item.day, title: item.tabID == item.day ? "today" : item.day)
            let meta = try dest.add(
                kind: item.kind,
                plaintext: plain,
                at: CGPoint(x: item.x, y: item.y),
                size: CGSize(width: item.width, height: item.height),
                caption: item.caption,
                looksLikeKey: item.looksLikeKey,
                keyKind: item.keyKind,
                day: item.day,
                tabID: tabID,
                createdAt: item.createdAt,
                z: item.z
            )
            report.imported += 1
            report.ids.append(meta.id)
            destItems.append(meta)
        }
        return report
    }

    public static func alreadyHave(_ item: ItemMeta, in dest: [ItemMeta]) -> Bool {
        dest.contains {
            $0.kind == item.kind
                && $0.bytes == item.bytes
                && $0.caption == item.caption
                && abs($0.createdAt.timeIntervalSince(item.createdAt)) < 2
        }
    }

    public static func shouldImport(_ item: ItemMeta) -> Bool {
        if item.id.hasPrefix("nb_fw_") { return false }
        if item.tabID.contains("features-wanted") { return false }
        return item.kind == .paste || item.kind == .image || item.kind == .audio
            || (item.kind == .note && !item.id.hasPrefix("nb_fw_"))
    }

    private static func ensureDayTab(_ dest: NotebookStore, day: String, title: String) throws -> String {
        let tab = try dest.ensureTab(id: day, title: title.isEmpty ? day : title, colorHex: "#3D3A36")
        return tab.id
    }
}
