// File-backed encrypted notebook. Journaled multi-file changes, 0700/0600 perms.
// Blobs decrypt on demand. This store has no TTL.

import Darwin
import CoreGraphics
import CryptoKit
import Foundation

public final class NotebookStore: @unchecked Sendable {
    public let root: URL
    public let key: SymmetricKey

    let storeLock: StoreLock
    var transactionCheckpoint: ((TransactionCheckpoint) throws -> Void)?
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
        self.storeLock = try StoreLock(root: root)
    }

    public var indexURL: URL { root.appendingPathComponent("index.json") }
    public var blobsDir: URL { root.appendingPathComponent("blobs") }

    public func blobURL(id: String) -> URL {
        blobsDir.appendingPathComponent("\(id).enc")
    }

    public func imageURL(id: String) -> URL {
        blobsDir.appendingPathComponent("\(id)-img.enc")
    }

    public func loadIndex() throws -> NotebookIndex {
        return try storeLock.withLock {
            try recoverPendingTransaction()
            guard let data = try readRegularFile(indexURL, maximumBytes: IndexEnvelope.maximumBytes + 128) else {
                if fm.fileExists(atPath: root.appendingPathComponent("index.migration.enc").path) {
                    throw NotebookError.indexCorrupt
                }
                return NotebookIndex()
            }
            do {
                let plaintext = try IndexEnvelope.plaintext(data, key: key)
                let index = try IndexEnvelope.decode(plaintext)
                if !data.starts(with: IndexEnvelope.magic) {
                    // Prove this is the existing payload key before changing a legacy index.
                    for item in index.items {
                        let blob = try readBlob(id: item.id)
                        guard blob.count == item.bytes else { throw NotebookError.indexCorrupt }
                        if item.hasImage {
                            guard try readImage(item.id) != nil else { throw NotebookError.indexCorrupt }
                        }
                    }
                    // Preserve the exact old bytes, encrypted, before atomically replacing the index.
                    let backup = root.appendingPathComponent("index.migration.enc")
                    let sealed = try IndexEnvelope.seal(plaintext, key: key)
                    if !fm.fileExists(atPath: backup.path) {
                        try atomicWrite(sealed, to: backup, mode: 0o600, overwrite: false)
                    } else {
                        let previous = try Data(contentsOf: backup)
                        if try IndexEnvelope.plaintext(previous, key: key) != plaintext {
                            try atomicWrite(sealed, to: root.appendingPathComponent("index.migration-\(UUID().uuidString).enc"), mode: 0o600, overwrite: false)
                        }
                    }
                    guard try IndexEnvelope.plaintext(sealed, key: key) == plaintext else { throw NotebookError.indexCorrupt }
                    try atomicWrite(sealed, to: indexURL, mode: 0o600)
                }
                return index
            } catch {
                throw NotebookError.indexCorrupt
            }
        }
    }

    public func saveIndex(_ index: NotebookIndex) throws {
        return try storeLock.withLock {
            try commit(index)
        }
    }

    public func readBlob(id: String) throws -> Data {
        return try storeLock.withLock {
            guard IndexEnvelope.safeID(id) else { throw NotebookError.transactionInvalid }
            try recoverPendingTransaction()
            let url = blobURL(id: id)
            guard fm.fileExists(atPath: url.path) else {
                throw NotebookError.missingBlob(id)
            }
            let sealed = try Data(contentsOf: url)
            return try CryptoBox.open(blob: sealed, key: key)
        }
    }

    public func writeBlob(id: String, plaintext: Data) throws {
        return try storeLock.withLock {
            guard IndexEnvelope.safeID(id) else { throw NotebookError.transactionInvalid }
            let index = try loadIndex()
            if index.items.contains(where: { $0.id == id }) {
                _ = try updatePayload(id, plaintext: plaintext)
                return
            }
            try validateRawNames(["\(id).enc"], index: index)
            let sealed = try sealTransactionBlob(plaintext)
            try atomicWrite(sealed, to: blobURL(id: id), mode: 0o600)
        }
    }

    public func deleteBlob(id: String) throws {
        return try storeLock.withLock {
            guard IndexEnvelope.safeID(id) else { throw NotebookError.transactionInvalid }
            let index = try loadIndex()
            if index.items.contains(where: { $0.id == id }) {
                try remove(id)
                return
            }
            try validateRawNames(["\(id).enc", "\(id)-img.enc"], index: index)
            let url = blobURL(id: id)
            if fm.fileExists(atPath: url.path) {
                try fm.removeItem(at: url)
            }
            let img = imageURL(id: id)
            if fm.fileExists(atPath: img.path) {
                try fm.removeItem(at: img)
            }
            try syncDirectory(blobsDir)
        }
    }

    public func writeImage(_ id: String, png: Data) throws {
        return try storeLock.withLock {
            var index = try loadIndex()
            guard let i = index.items.firstIndex(where: { $0.id == id }) else { throw NotebookError.missingBlob(id) }
            let sealed = try sealTransactionBlob(png)
            index.items[i].hasImage = true
            index.items[i].updatedAt = Date()
            try commit(index, writes: ["\(id)-img.enc": sealed])
        }
    }

    public func readImage(_ id: String) throws -> Data? {
        return try storeLock.withLock {
            guard IndexEnvelope.safeID(id) else { throw NotebookError.transactionInvalid }
            try recoverPendingTransaction()
            let url = imageURL(id: id)
            guard fm.fileExists(atPath: url.path) else { return nil }
            return try CryptoBox.open(blob: try Data(contentsOf: url), key: key)
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
        tabID: String? = nil,
        createdAt: Date? = nil,
        z: Int = 0
    ) throws -> ItemMeta {
        return try storeLock.withLock {
            guard !plaintext.isEmpty else { throw NotebookError.emptyPayload }
            let now = Date()
            let made = createdAt ?? now
            let id = "pp_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            var index = try loadIndex()
            let sealed = try sealTransactionBlob(plaintext)
            let meta = ItemMeta(
                id: id,
                kind: kind,
                x: point.x,
                y: point.y,
                width: size.width,
                height: size.height,
                createdAt: made,
                updatedAt: now,
                bytes: plaintext.count,
                fingerprint: kind == .paste ? CryptoBox.fingerprint(plaintext) : nil,
                caption: caption,
                looksLikeKey: looksLikeKey,
                keyKind: keyKind,
                day: day ?? ItemMeta.dayString(from: made),
                tabID: tabID,
                z: z
            )
            index.items.append(meta)
            try commit(index, writes: ["\(id).enc": sealed])
            return meta
        }
    }

    public func updateCaption(_ id: String, caption: String) throws -> ItemMeta {
        return try storeLock.withLock {
            var index = try loadIndex()
            guard let i = index.items.firstIndex(where: { $0.id == id }) else {
                throw NotebookError.missingBlob(id)
            }
            index.items[i].caption = caption
            index.items[i].updatedAt = Date()
            try saveIndex(index)
            return index.items[i]
        }
    }

    public func updatePayload(_ id: String, plaintext: Data) throws -> ItemMeta {
        return try storeLock.withLock {
            var index = try loadIndex()
            guard let i = index.items.firstIndex(where: { $0.id == id }) else {
                throw NotebookError.missingBlob(id)
            }
            let sealed = try sealTransactionBlob(plaintext)
            index.items[i].bytes = plaintext.count
            index.items[i].updatedAt = Date()
            if index.items[i].kind == .paste {
                index.items[i].fingerprint = CryptoBox.fingerprint(plaintext)
            }
            try commit(index, writes: ["\(id).enc": sealed])
            return index.items[i]
        }
    }

    public func updateFrame(_ id: String, x: Double, y: Double, width: Double, height: Double) throws {
        return try storeLock.withLock {
            var index = try loadIndex()
            guard let i = index.items.firstIndex(where: { $0.id == id }) else { return }
            index.items[i].x = x
            index.items[i].y = y
            index.items[i].width = width
            index.items[i].height = height
            index.items[i].updatedAt = Date()
            try saveIndex(index)
        }
    }

    public func convert(_ id: String, conversion: Conversion) throws -> ItemMeta {
        return try storeLock.withLock {
            var index = try loadIndex()
            guard let i = index.items.firstIndex(where: { $0.id == id }) else {
                throw NotebookError.missingBlob(id)
            }
            index.items[i].conversion = conversion
            index.items[i].updatedAt = Date()
            try saveIndex(index)
            return index.items[i]
        }
    }

    public func clearConversion(_ id: String) throws -> ItemMeta {
        return try storeLock.withLock {
            var index = try loadIndex()
            guard let i = index.items.firstIndex(where: { $0.id == id }) else {
                throw NotebookError.missingBlob(id)
            }
            index.items[i].conversion = nil
            index.items[i].updatedAt = Date()
            try saveIndex(index)
            return index.items[i]
        }
    }

    public func bringToFront(_ id: String) throws -> ItemMeta {
        return try storeLock.withLock {
            var index = try loadIndex()
            guard let i = index.items.firstIndex(where: { $0.id == id }) else {
                throw NotebookError.missingBlob(id)
            }
            index.items[i].z = DragMath.nextZ(index.items)
            index.items[i].updatedAt = Date()
            try saveIndex(index)
            return index.items[i]
        }
    }

    public func assignTab(_ id: String, tabID: String) throws -> ItemMeta {
        return try storeLock.withLock {
            var index = try loadIndex()
            guard let i = index.items.firstIndex(where: { $0.id == id }) else {
                throw NotebookError.missingBlob(id)
            }
            index.items[i].tabID = tabID
            index.items[i].updatedAt = Date()
            try saveIndex(index)
            return index.items[i]
        }
    }

    public func addTab(title: String, colorHex: String) throws -> BoardTab {
        return try storeLock.withLock {
            try ensureTab(
                id: "tab_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(),
                title: title,
                colorHex: colorHex
            )
        }
    }

    public func ensureTab(id: String, title: String, colorHex: String) throws -> BoardTab {
        return try storeLock.withLock {
            var index = try loadIndex()
            if let existing = index.tabs.first(where: { $0.id == id }) {
                return existing
            }
            let tab = BoardTab(id: id, title: title, colorHex: colorHex)
            index.tabs.append(tab)
            try saveIndex(index)
            return tab
        }
    }

    public func seedBugs() throws {
        return try storeLock.withLock {
            var index = try loadIndex()
            if !index.tabs.contains(where: { $0.id == Bugs.tabID }) {
                index.tabs.append(BoardTab(id: Bugs.tabID, title: Bugs.tabTitle, colorHex: Bugs.tabColor))
            }
            var writes: [String: Data] = [:]
            var x: Double = 40
            var y: Double = 40
            for bug in Bugs.all {
                if index.items.contains(where: { $0.id == bug.bugStickyID }) { continue }
                let body = Data(bug.body.utf8)
                guard !body.isEmpty else { continue }
                writes["\(bug.bugStickyID).enc"] = try sealTransactionBlob(body)
                let now = Date()
                index.items.append(
                    ItemMeta(
                        id: bug.bugStickyID,
                        kind: .note,
                        x: x,
                        y: y,
                        width: NotebookLayout.sticky,
                        height: NotebookLayout.sticky,
                        createdAt: now,
                        updatedAt: now,
                        bytes: bug.body.utf8.count,
                        caption: bug.title,
                        day: ItemMeta.today(),
                        tabID: Bugs.tabID
                    )
                )
                x += 250
                if x > 1600 {
                    x = 40
                    y += 250
                }
            }
            try commit(index, writes: writes)
        }
    }

    public func saveChat(_ chat: ChatSettings) throws {
        return try storeLock.withLock {
            var index = try loadIndex()
            index.chat = chat
            try saveIndex(index)
        }
    }

    public func seedFeaturesWanted() throws {
        return try storeLock.withLock {
            var index = try loadIndex()
            var writes: [String: Data] = [:]
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
                let body = Data(f.body.utf8)
                guard !body.isEmpty else { continue }
                let now = Date()
                writes["\(f.stickyID).enc"] = try sealTransactionBlob(body)
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
            try commit(index, writes: writes)
        }
    }

    public func remove(_ id: String) throws {
        return try storeLock.withLock {
            var index = try loadIndex()
            guard index.items.contains(where: { $0.id == id }) else { return }
            index.items.removeAll { $0.id == id }
            try saveIndex(index)
        }
    }

    func atomicWrite(_ data: Data, to url: URL, mode: Int, overwrite: Bool = true) throws {
        let tmp = url.deletingLastPathComponent().appendingPathComponent(".write-" + UUID().uuidString)
        let fd = Darwin.open(tmp.path, O_CREAT | O_EXCL | O_WRONLY | O_CLOEXEC | O_NOFOLLOW, mode_t(mode))
        guard fd >= 0 else { throw StoreLock.posixError() }
        defer { Darwin.close(fd); try? fm.removeItem(at: tmp) }
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 {
                    if errno == EINTR { continue }
                    throw StoreLock.posixError()
                }
                guard count > 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(EIO)) }
                offset += count
            }
        }
        guard fsync(fd) == 0 else { throw StoreLock.posixError() }
        // rename replaces the directory entry atomically; the old file is never unlinked first.
        if overwrite {
            guard Darwin.rename(tmp.path, url.path) == 0 else { throw StoreLock.posixError() }
        } else {
            // Exclusive publication: never overwrite an existing backup, even in a race.
            guard Darwin.link(tmp.path, url.path) == 0 else { throw StoreLock.posixError() }
        }
        let directory = Darwin.open(url.deletingLastPathComponent().path, O_RDONLY | O_CLOEXEC)
        guard directory >= 0 else { throw StoreLock.posixError() }
        defer { Darwin.close(directory) }
        guard fsync(directory) == 0 else { throw StoreLock.posixError() }
        // macOS fsync alone does not flush volatile device caches. Require the
        // stronger barrier after both file data and the directory entry are synced.
        guard fcntl(fd, F_FULLFSYNC) == 0 else { throw StoreLock.posixError() }
    }
}
