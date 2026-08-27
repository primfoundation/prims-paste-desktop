// File-backed encrypted notebook. Atomic index writes, 0700/0600 perms.
// Blobs decrypt on demand. This store has no TTL.

import CoreGraphics
import CryptoKit
import Foundation

public final class NotebookStore: @unchecked Sendable {
    public let root: URL
    public let key: SymmetricKey

    private let fm = FileManager.default
    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    public init(root: URL, key: SymmetricKey) throws {
        self.root = root
        self.key = key
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("blobs"),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: root.path
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: root.appendingPathComponent("blobs").path
        )
    }

    public var indexURL: URL { root.appendingPathComponent("index.json") }
    public var blobsDir: URL { root.appendingPathComponent("blobs") }

    public func blobURL(id: String) -> URL {
        blobsDir.appendingPathComponent("\(id).enc")
    }

    public func loadIndex() throws -> NotebookIndex {
        guard fm.fileExists(atPath: indexURL.path) else {
            return NotebookIndex()
        }
        let data = try Data(contentsOf: indexURL)
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        do {
            return try dec.decode(NotebookIndex.self, from: data)
        } catch {
            throw NotebookError.indexCorrupt
        }
    }

    public func saveIndex(_ index: NotebookIndex) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        let data = try enc.encode(index)
        try atomicWrite(data, to: indexURL, mode: 0o600)
    }

    public func readBlob(id: String) throws -> Data {
        let url = blobURL(id: id)
        guard fm.fileExists(atPath: url.path) else {
            throw NotebookError.missingBlob(id)
        }
        let sealed = try Data(contentsOf: url)
        return try CryptoBox.open(blob: sealed, key: key)
    }

    public func writeBlob(id: String, plaintext: Data) throws {
        guard !plaintext.isEmpty else { throw NotebookError.emptyPayload }
        let sealed = try CryptoBox.seal(plaintext: plaintext, key: key)
        try atomicWrite(sealed, to: blobURL(id: id), mode: 0o600)
    }

    public func deleteBlob(id: String) throws {
        let url = blobURL(id: id)
        if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
    }

    public func add(
        kind: ItemKind,
        plaintext: Data,
        at point: CGPoint,
        size: CGSize,
        caption: String = "",
        looksLikeKey: Bool = false,
        keyKind: String? = nil,
        day: String? = nil,
        tabID: String? = nil
    ) throws -> ItemMeta {
        guard !plaintext.isEmpty else { throw NotebookError.emptyPayload }
        let now = Date()
        let id = "pp_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        try writeBlob(id: id, plaintext: plaintext)
        var index = try loadIndex()
        let meta = ItemMeta(
            id: id,
            kind: kind,
            x: point.x,
            y: point.y,
            width: size.width,
            height: size.height,
            createdAt: now,
            updatedAt: now,
            bytes: plaintext.count,
            fingerprint: kind == .paste ? CryptoBox.fingerprint(plaintext) : nil,
            caption: caption,
            looksLikeKey: looksLikeKey,
            keyKind: keyKind,
            day: day ?? ItemMeta.dayString(from: now),
            tabID: tabID
        )
        index.items.append(meta)
        try saveIndex(index)
        return meta
    }

    public func updateCaption(_ id: String, caption: String) throws -> ItemMeta {
        var index = try loadIndex()
        guard let i = index.items.firstIndex(where: { $0.id == id }) else {
            throw NotebookError.missingBlob(id)
        }
        index.items[i].caption = caption
        index.items[i].updatedAt = Date()
        try saveIndex(index)
        return index.items[i]
    }

    public func updatePayload(_ id: String, plaintext: Data) throws -> ItemMeta {
        var index = try loadIndex()
        guard let i = index.items.firstIndex(where: { $0.id == id }) else {
            throw NotebookError.missingBlob(id)
        }
        try writeBlob(id: id, plaintext: plaintext)
        index.items[i].bytes = plaintext.count
        index.items[i].updatedAt = Date()
        if index.items[i].kind == .paste {
            index.items[i].fingerprint = CryptoBox.fingerprint(plaintext)
        }
        try saveIndex(index)
        return index.items[i]
    }

    public func updateFrame(_ id: String, x: Double, y: Double, width: Double, height: Double) throws {
        var index = try loadIndex()
        guard let i = index.items.firstIndex(where: { $0.id == id }) else { return }
        index.items[i].x = x
        index.items[i].y = y
        index.items[i].width = width
        index.items[i].height = height
        index.items[i].updatedAt = Date()
        try saveIndex(index)
    }

    public func convert(_ id: String, conversion: Conversion) throws -> ItemMeta {
        var index = try loadIndex()
        guard let i = index.items.firstIndex(where: { $0.id == id }) else {
            throw NotebookError.missingBlob(id)
        }
        index.items[i].conversion = conversion
        index.items[i].updatedAt = Date()
        try saveIndex(index)
        return index.items[i]
    }

    public func bringToFront(_ id: String) throws -> ItemMeta {
        var index = try loadIndex()
        guard let i = index.items.firstIndex(where: { $0.id == id }) else {
            throw NotebookError.missingBlob(id)
        }
        index.items[i].z = DragMath.nextZ(index.items)
        index.items[i].updatedAt = Date()
        try saveIndex(index)
        return index.items[i]
    }

    public func assignTab(_ id: String, tabID: String) throws -> ItemMeta {
        var index = try loadIndex()
        guard let i = index.items.firstIndex(where: { $0.id == id }) else {
            throw NotebookError.missingBlob(id)
        }
        index.items[i].tabID = tabID
        index.items[i].updatedAt = Date()
        try saveIndex(index)
        return index.items[i]
    }

    public func addTab(title: String, colorHex: String) throws -> BoardTab {
        var index = try loadIndex()
        let tab = BoardTab(
            id: "tab_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(),
            title: title,
            colorHex: colorHex
        )
        index.tabs.append(tab)
        try saveIndex(index)
        return tab
    }

    public func saveChat(_ chat: ChatSettings) throws {
        var index = try loadIndex()
        index.chat = chat
        try saveIndex(index)
    }

    public func seedFeaturesWanted() throws {
        var index = try loadIndex()
        if !index.tabs.contains(where: { $0.id == FeaturesWanted.tabID }) {
            index.tabs.insert(
                BoardTab(
                    id: FeaturesWanted.tabID,
                    title: FeaturesWanted.tabTitle,
                    colorHex: FeaturesWanted.tabColor
                ),
                at: 0
            )
        }
        var x: Double = 40
        var y: Double = 40
        for f in FeaturesWanted.all {
            if index.items.contains(where: { $0.id == f.stickyID }) { continue }
            let now = Date()
            try writeBlob(id: f.stickyID, plaintext: Data(f.body.utf8))
            index.items.append(
                ItemMeta(
                    id: f.stickyID,
                    kind: .note,
                    x: x,
                    y: y,
                    width: NotebookLayout.sticky,
                    height: NotebookLayout.sticky,
                    createdAt: now,
                    updatedAt: now,
                    bytes: f.body.utf8.count,
                    caption: f.title,
                    day: ItemMeta.today(),
                    tabID: FeaturesWanted.tabID
                )
            )
            x += 250
            if x > 1600 {
                x = 40
                y += 250
            }
        }
        index.seededFeaturesWanted = true
        try saveIndex(index)
    }

    public func remove(_ id: String) throws {
        var index = try loadIndex()
        index.items.removeAll { $0.id == id }
        try saveIndex(index)
        try deleteBlob(id: id)
    }

    private func atomicWrite(_ data: Data, to url: URL, mode: Int) throws {
        let tmp = url.appendingPathExtension("tmp")
        if fm.fileExists(atPath: tmp.path) {
            try fm.removeItem(at: tmp)
        }
        try data.write(to: tmp, options: .atomic)
        try fm.setAttributes([.posixPermissions: mode], ofItemAtPath: tmp.path)
        if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
        try fm.moveItem(at: tmp, to: url)
        try fm.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
    }
}

