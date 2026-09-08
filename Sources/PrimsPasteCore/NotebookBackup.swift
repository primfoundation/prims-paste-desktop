import CryptoKit
import Darwin
import Foundation

private struct BackupSnapshot: Codable {
    let format: String
    let version: Int
    let index: Data
    let blobs: [String: Data]
}

extension NotebookStore {
    /// The key stays in Keychain; this backup requires that same key to restore.
    /// Export is exclusive and is limited to 128 MiB of sealed source files.
    public func exportBackup(to destination: URL) throws {
        try storeLock.withLock {
            let index = try loadIndex()
            if !FileManager.default.fileExists(atPath: indexURL.path) { try saveIndex(index) }
            let indexData = try Data(contentsOf: indexURL)
            var blobs: [String: Data] = [:]
            var total = indexData.count
            for item in index.items {
                let names = ["\(item.id).enc"] + (item.hasImage ? ["\(item.id)-img.enc"] : [])
                for name in names {
                    guard blobs[name] == nil else { throw NotebookError.backupInvalid }
                    let url = blobsDir.appendingPathComponent(name)
                    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                    guard attributes[.type] as? FileAttributeType == .typeRegular,
                          let size = attributes[.size] as? NSNumber, size.intValue <= 128 * 1024 * 1024 - total else {
                        throw NotebookError.backupInvalid
                    }
                    let sealed = try Data(contentsOf: url)
                    let plain = try CryptoBox.open(blob: sealed, key: key)
                    if name == "\(item.id).enc" && plain.count != item.bytes { throw NotebookError.backupInvalid }
                    total += sealed.count; blobs[name] = sealed
                }
            }
            let snapshot = BackupSnapshot(format: "primboard-backup", version: 1, index: indexData, blobs: blobs)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let payload = try encoder.encode(snapshot)
            let sealed = try CryptoBox.seal(plaintext: payload, key: key)
            try atomicWrite(sealed, to: destination, mode: 0o600, overwrite: false)
        }
    }

    /// Validate everything first; publish only into a new directory. Never replace a live store.
    public static func restoreBackup(from source: URL, to destination: URL, key: SymmetricKey) throws {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: destination.path) else { throw NotebookError.restoreDestinationExists }
        let attributes = try fm.attributesOfItem(atPath: source.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber, size.intValue <= 256 * 1024 * 1024 else { throw NotebookError.backupInvalid }
        let payload = try CryptoBox.open(blob: Data(contentsOf: source), key: key)
        let snapshot = try JSONDecoder().decode(BackupSnapshot.self, from: payload)
        guard snapshot.format == "primboard-backup", snapshot.version == 1,
              snapshot.index.starts(with: IndexEnvelope.magic) else { throw NotebookError.backupInvalid }
        let index = try IndexEnvelope.decode(IndexEnvelope.plaintext(snapshot.index, key: key))
        var expected = Set<String>()
        for item in index.items {
            let name = "\(item.id).enc"
            guard expected.insert(name).inserted else { throw NotebookError.backupInvalid }
            guard let blob = snapshot.blobs[name], try CryptoBox.open(blob: blob, key: key).count == item.bytes else { throw NotebookError.backupInvalid }
            if item.hasImage {
                let image = "\(item.id)-img.enc"
                guard expected.insert(image).inserted else { throw NotebookError.backupInvalid }
                guard let blob = snapshot.blobs[image] else { throw NotebookError.backupInvalid }
                _ = try CryptoBox.open(blob: blob, key: key)
            }
        }
        guard expected == Set(snapshot.blobs.keys()) else { throw NotebookError.backupInvalid }
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".primboard-restore-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: staging) }
        let store = try NotebookStore(root: staging, key: key)
        for (name, data) in snapshot.blobs { try store.atomicWrite(data, to: store.blobsDir.appendingPathComponent(name), mode: 0o600, overwrite: false) }
        try store.atomicWrite(snapshot.index, to: store.indexURL, mode: 0o600, overwrite: false)
        _ = try store.loadIndex()
        try fm.moveItem(at: staging, to: destination)
        let directory = Darwin.open(destination.deletingLastPathComponent().path, O_RDONLY | O_CLOEXEC)
        guard directory >= 0 else { throw StoreLock.posixError() }
        defer { Darwin.close(directory) }
        guard fsync(directory) == 0 else { throw StoreLock.posixError() }
    }
}
