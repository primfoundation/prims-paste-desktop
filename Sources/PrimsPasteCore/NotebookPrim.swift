import CryptoKit
import Foundation

extension NotebookStore {
    /// Create a separate encrypted Prim; retain the source sticky and its exact payload.
    /// A caller-generated operation ID makes a retry after an uncertain commit idempotent.
    public func createPrim(sourceID: String?, kit: PrimKit, record: PrimJSON, operationID: String) throws -> ItemMeta {
        try kit.requireValid(record)
        let data = try record.encoded()
        guard operationID.range(of: "^prim_[a-f0-9]{32}\\z", options: .regularExpression) != nil else {
            throw PrimLibraryError.invalid("Invalid creation operation ID.")
        }
        return try storeLock.withLock {
            var index = try loadIndex()
            if let existing = index.items.first(where: { $0.id == operationID }) {
                guard existing.primPin == kit.pin, existing.primSourceID == sourceID,
                      try readBlob(id: operationID) == data else { throw NotebookError.staleIndex }
                return existing
            }
            let source = index.items.first { $0.id == sourceID }
            if sourceID != nil && source == nil { throw NotebookError.missingBlob(sourceID!) }
            let now = Date()
            let item = ItemMeta(id: operationID, kind: .note, x: (source?.x ?? 20) + 35,
                                y: (source?.y ?? 20) + 35, width: NotebookLayout.sticky, height: NotebookLayout.sticky,
                                createdAt: now, updatedAt: now, bytes: data.count,
                                caption: record[kit.titleField].string ?? kit.name, tabID: source?.tabID,
                                z: DragMath.nextZ(index.items), primPin: kit.pin, primSourceID: sourceID)
            index.items.append(item)
            try commit(index, writes: ["\(operationID).enc": try sealTransactionBlob(data)])
            // Return the persisted timestamp precision so an idempotent retry matches.
            guard let persisted = try loadIndex().items.first(where: { $0.id == operationID }) else {
                throw NotebookError.missingBlob(operationID)
            }
            return persisted
        }
    }

    /// Compare the actual content and pin while holding the process lock.
    /// Unrelated notebook edits do not conflict, while concurrent record edits do.
    public func updatePrim(_ id: String, kit: PrimKit, record: PrimJSON, expected: Data) throws -> ItemMeta {
        try kit.requireValid(record)
        let data = try record.encoded()
        return try storeLock.withLock {
            var index = try loadIndex()
            guard let i = index.items.firstIndex(where: { $0.id == id }), index.items[i].primPin == kit.pin else {
                throw PrimLibraryError.invalid("Record or pinned definition changed. Reload before saving.")
            }
            let current = try readBlob(id: id)
            if current == data { return index.items[i] }
            guard current == expected else { throw NotebookError.staleIndex }
            index.items[i].bytes = data.count
            index.items[i].caption = record[kit.titleField].string ?? kit.name
            index.items[i].updatedAt = Date()
            try commit(index, writes: ["\(id).enc": try sealTransactionBlob(data)])
            return index.items[i]
        }
    }

    public func exportPrim(_ id: String, library: PrimLibrary, to destination: URL) throws {
        try storeLock.withLock {
            let index = try loadIndex()
            guard let item = index.items.first(where: { $0.id == id }), let pin = item.primPin else {
                throw PrimLibraryError.invalid("Select a Prim record to export.")
            }
            let kit = try library.kit(for: pin)
            let record = try PrimJSON.parse(readBlob(id: id))
            try kit.requireValid(record)
            try PrimPack.write(record: record, kit: kit, to: destination)
        }
    }
}

/// Same directory pack consumed by the Foundation Python and TypeScript readers.
/// Export is an explicit plaintext operation; it never overwrites an existing pack.
public enum PrimPack {
    private static func localURL(_ url: URL) -> URL {
        var path = url.standardizedFileURL.path
        // macOS exposes temporary folders through OS-owned aliases.
        // Arbitrary user-created symlinks remain rejected below.
        for alias in ["/var", "/tmp"] where path.hasPrefix(alias + "/") {
            let link = try? FileManager.default.destinationOfSymbolicLink(atPath: alias)
            if link == "/private" + alias || link == "private" + alias {
                path = "/private" + path
                break
            }
        }
        return URL(fileURLWithPath: path)
    }

    public static func write(record: PrimJSON, kit: PrimKit, to destination: URL) throws {
        try kit.requireValid(record)
        let fm = FileManager.default
        let target = localURL(destination)
        var parent = (target.path as NSString).deletingLastPathComponent
        while parent != "/" {
            let attributes = try fm.attributesOfItem(atPath: parent)
            guard attributes[.type] as? FileAttributeType == .typeDirectory else {
                throw PrimLibraryError.invalid("Export parent must be a real directory: \(parent)")
            }
            parent = (parent as NSString).deletingLastPathComponent
        }
        guard !fm.fileExists(atPath: target.path), (try? fm.destinationOfSymbolicLink(atPath: target.path)) == nil else {
            throw PrimLibraryError.invalid("Export requires a new folder.")
        }
        let temp = target.deletingLastPathComponent().appendingPathComponent(".prim-export-\(UUID().uuidString)")
        try fm.createDirectory(at: temp, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: temp) }
        func write(_ name: String, _ data: Data) throws {
            let path = temp.appendingPathComponent(name)
            guard fm.createFile(atPath: path.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
                throw PrimLibraryError.invalid("Could not write the exported Prim.")
            }
            let handle = try FileHandle(forWritingTo: path); defer { try? handle.close() }
            try handle.synchronize()
        }
        try write(kit.authorityFile, record.encoded())
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try write("prim-definition.lock.json", encoder.encode(kit.pin))
        func quote(_ s: String) throws -> String { String(decoding: try encoder.encode(s), as: UTF8.self) }
        let title = record[kit.titleField].string ?? kit.name
        let face = "---\nprofile: \(try quote(kit.pin.profileID))\nprofile_version: \(try quote(kit.pin.version))\ntype: \(try quote(kit.pin.profileID.split(separator: "/").last.map(String.init) ?? "prim"))\ntitle: \(try quote(title))\nauthority: \(kit.authorityFile)\n---\n\nThe authoritative record is in `\(kit.authorityFile)`.\n"
        try write("index.md", Data(face.utf8))
        try write("log.md", Data("# Log\n\n- Exported locally from Primboard using a pinned definition. Structural checks do not verify facts or authority.\n".utf8))
        try fm.moveItem(at: temp, to: target)
    }

    public static func read(_ source: URL, library: PrimLibrary) throws -> (PrimKit, PrimJSON) {
        let root = localURL(source)
        guard try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]).isDirectory == true,
              root.resolvingSymlinksInPath().path == root.path else { throw PrimLibraryError.invalid("Choose a local Prim folder without symbolic links.") }
        func read(_ name: String) throws -> Data {
            let url = root.appendingPathComponent(name)
            let a = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard a.isRegularFile == true, a.isSymbolicLink != true, (a.fileSize ?? Int.max) <= 512 * 1024 else {
                throw PrimLibraryError.invalid("Invalid or oversized Prim file.")
            }
            return try Data(contentsOf: url)
        }
        let pinBytes = try read("prim-definition.lock.json")
        _ = try PrimJSON.parse(pinBytes)
        let pin = try JSONDecoder().decode(PrimDefinitionPin.self, from: pinBytes)
        let kit = try library.kit(for: pin)
        let record = try PrimJSON.parse(read(kit.authorityFile))
        try kit.requireValid(record)
        return (kit, record)
    }
}
