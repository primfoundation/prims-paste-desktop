import CryptoKit
import Darwin
import Foundation

/// Encrypted redo record. Publication is the commit point; replay is idempotent.
/// Contains only sealed indexes/blobs, then encrypts the entire record again.
struct NotebookTransaction: Codable {
    var version: Int = 1
    var previousIndex: Data?
    var nextIndex: Data
    var writes: [String: Data]
    var deletes: [String]
}

enum TransactionJournal {
    static let magic = Data("PPJ1".utf8)
    static let maximumBytes = 128 * 1024 * 1024
    static let maximumWriteBytes = 64 * 1024 * 1024

    static func seal(_ transaction: NotebookTransaction, key: SymmetricKey) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let payload = try encoder.encode(transaction)
        guard payload.count <= maximumBytes else { throw NotebookError.transactionTooLarge }
        return magic + (try CryptoBox.seal(plaintext: payload, key: key))
    }

    static func open(_ data: Data, key: SymmetricKey) throws -> NotebookTransaction {
        guard data.count <= maximumBytes + 128, data.starts(with: magic) else {
            throw NotebookError.transactionInvalid
        }
        let payload = try CryptoBox.open(blob: Data(data.dropFirst(magic.count)), key: key)
        let transaction = try JSONDecoder().decode(NotebookTransaction.self, from: payload)
        guard transaction.version == 1 else { throw NotebookError.transactionInvalid }
        return transaction
    }

    static func normalized(_ name: String) -> String {
        name.precomposedStringWithCanonicalMapping.lowercased()
    }

    static func files(_ index: NotebookIndex) -> Set<String> {
        Set(index.items.flatMap { ["\($0.id).enc"] + ($0.hasImage ? ["\($0.id)-img.enc"] : []) })
    }

    static func requiredWrites(from previous: NotebookIndex, to next: NotebookIndex) -> Set<String> {
        var required = files(next).subtracting(files(previous))
        let old = Dictionary(uniqueKeysWithValues: previous.items.map { ($0.id, $0) })
        for item in next.items {
            if let before = old[item.id], before.bytes != item.bytes || before.fingerprint != item.fingerprint || before.kind != item.kind {
                required.insert("\(item.id).enc")
            }
        }
        return required
    }
}

/// Internal fault seam for tests, never configured through production CLI/env.
enum TransactionCheckpoint: Equatable {
    case beforeJournal
    case journalPersisted
    case blobWritten(String)
    case indexWritten
    case blobDeleted(String)
    case journalRemoved
}

extension NotebookStore {
    var journalURL: URL { root.appendingPathComponent(".transaction.enc") }

    /// Called only while storeLock is held, including before raw payload access.
    func recoverPendingTransaction() throws {
        guard let data = try readRegularFile(journalURL, maximumBytes: TransactionJournal.maximumBytes + 128) else { return }
        let transaction: NotebookTransaction
        do {
            transaction = try TransactionJournal.open(data, key: key)
            try validateTransaction(transaction)
        } catch {
            throw NotebookError.transactionInvalid
        }
        // An earlier write could have failed after publication but before its barrier.
        try syncDirectory(root)
        try fullSyncFile(journalURL)
        try applyTransaction(transaction)
    }

    /// All referenced multi-file changes go through this operation under storeLock.
    func commit(_ proposed: NotebookIndex, writes supplied: [String: Data] = [:]) throws {
        let previous = try loadIndex()
        guard previous.revision == proposed.revision, previous.revision < UInt64.max else {
            throw NotebookError.staleIndex
        }
        var next = proposed
        next.revision += 1
        // Persist derived tabs once, so reads do not synthesize fresh metadata.
        if next.tabs.isEmpty { next.tabs = NotebookIndex.tabsFromDays(next.items) }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let payload = try encoder.encode(next)
        _ = try IndexEnvelope.decode(payload)
        var writes = supplied
        var capturedBytes = 0
        for data in writes.values {
            guard data.count <= TransactionJournal.maximumWriteBytes - capturedBytes else { throw NotebookError.transactionTooLarge }
            capturedBytes += data.count
        }
        // Whole-index callers can reference a previously written, unreferenced blob.
        // Capture such data in the redo record before publishing the new reference.
        for name in TransactionJournal.requiredWrites(from: previous, to: next).subtracting(Set(writes.keys)) {
            guard let data = try readRegularFile(blobsDir.appendingPathComponent(name), maximumBytes: TransactionJournal.maximumWriteBytes - capturedBytes) else {
                throw NotebookError.transactionInvalid
            }
            capturedBytes += data.count
            writes[name] = data
        }
        let transaction = NotebookTransaction(
            previousIndex: try readRegularFile(indexURL, maximumBytes: IndexEnvelope.maximumBytes + 128),
            nextIndex: try IndexEnvelope.seal(payload, key: key), writes: writes,
            deletes: TransactionJournal.files(previous).subtracting(TransactionJournal.files(next)).sorted())
        try validateTransaction(transaction)
        let sealed = try TransactionJournal.seal(transaction, key: key)
        try transactionCheckpoint?(.beforeJournal)
        // Never replace a pending record. All earlier work is read-only preparation.
        do {
            try atomicWrite(sealed, to: journalURL, mode: 0o600, overwrite: false)
            try transactionCheckpoint?(.journalPersisted)
            try applyTransaction(transaction)
        } catch {
            // The operation might already be committed. Do not blindly repeat an add.
            throw NotebookError.transactionPending
        }
    }

    private func validateTransaction(_ transaction: NotebookTransaction) throws {
        guard transaction.version == 1, transaction.nextIndex.starts(with: IndexEnvelope.magic) else {
            throw NotebookError.transactionInvalid
        }
        let next = try IndexEnvelope.decode(IndexEnvelope.plaintext(transaction.nextIndex, key: key))
        var previous = NotebookIndex()
        if let data = transaction.previousIndex {
            guard data.starts(with: IndexEnvelope.magic) else { throw NotebookError.transactionInvalid }
            previous = try IndexEnvelope.decode(IndexEnvelope.plaintext(data, key: key))
        }
        guard previous.revision < UInt64.max, next.revision == previous.revision + 1 else {
            throw NotebookError.transactionInvalid
        }
        let current = try readRegularFile(indexURL, maximumBytes: IndexEnvelope.maximumBytes + 128)
        guard current == transaction.previousIndex || current == transaction.nextIndex else {
            // Another revision, missing primary, or external alteration: preserve evidence.
            throw NotebookError.transactionInvalid
        }
        let oldFiles = TransactionJournal.files(previous), newFiles = TransactionJournal.files(next)
        guard Set(transaction.deletes).count == transaction.deletes.count,
              Set(transaction.deletes) == oldFiles.subtracting(newFiles),
              Set(transaction.writes.keys).isSubset(of: newFiles),
              TransactionJournal.requiredWrites(from: previous, to: next).isSubset(of: Set(transaction.writes.keys)) else {
            throw NotebookError.transactionInvalid
        }
        // Reject spelling/case/Unicode aliases across revisions, including body/image aliases.
        var spellings: [String: String] = [:]
        for name in oldFiles.union(newFiles) {
            let normalized = TransactionJournal.normalized(name)
            if let spelling = spellings[normalized], spelling != name { throw NotebookError.transactionInvalid }
            spellings[normalized] = name
        }
        let bodies = Dictionary(uniqueKeysWithValues: next.items.map { ("\($0.id).enc", $0) })
        var total = 0
        for (name, data) in transaction.writes {
            guard data.count <= TransactionJournal.maximumWriteBytes - total else { throw NotebookError.transactionTooLarge }
            total += data.count
            let plaintext = try CryptoBox.open(blob: data, key: key)
            guard !plaintext.isEmpty else { throw NotebookError.emptyPayload }
            if let item = bodies[name] {
                guard plaintext.count == item.bytes,
                      item.kind != .paste || item.fingerprint == CryptoBox.fingerprint(plaintext) else {
                    throw NotebookError.transactionInvalid
                }
            }
        }
        // Validate all affected destinations before replay writes even the first file.
        try requireDirectory(blobsDir)
        for name in Set(transaction.writes.keys).union(transaction.deletes) {
            try requireRegularFileOrAbsent(blobsDir.appendingPathComponent(name))
        }
    }

    private func applyTransaction(_ transaction: NotebookTransaction) throws {
        for name in transaction.writes.keys.sorted() {
            try atomicWrite(transaction.writes[name]!, to: blobsDir.appendingPathComponent(name), mode: 0o600)
            try transactionCheckpoint?(.blobWritten(name))
        }
        try atomicWrite(transaction.nextIndex, to: indexURL, mode: 0o600)
        try transactionCheckpoint?(.indexWritten)
        for name in transaction.deletes.sorted() {
            let url = blobsDir.appendingPathComponent(name)
            if Darwin.unlink(url.path) != 0, errno != ENOENT { throw StoreLock.posixError() }
            try syncDirectory(blobsDir)
            try transactionCheckpoint?(.blobDeleted(name))
        }
        // Flush deletions before clearing the durable intent. Replay after any failure is safe.
        try fullSyncFile(indexURL)
        guard Darwin.unlink(journalURL.path) == 0 else { throw StoreLock.posixError() }
        try syncDirectory(root)
        try fullSyncFile(indexURL)
        try transactionCheckpoint?(.journalRemoved)
    }

    /// Bound allocation, reject symlinks/FIFOs, and read from the same checked descriptor.
    func readRegularFile(_ url: URL, maximumBytes: Int) throws -> Data? {
        let fd = Darwin.open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        if fd < 0 {
            if errno == ENOENT { return nil }
            throw StoreLock.posixError()
        }
        defer { Darwin.close(fd) }
        var attributes = stat()
        guard fstat(fd, &attributes) == 0 else { throw StoreLock.posixError() }
        guard attributes.st_mode & S_IFMT == S_IFREG, attributes.st_size >= 0,
              attributes.st_size <= Int64(maximumBytes) else { throw NotebookError.transactionInvalid }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count < 0 {
                if errno == EINTR { continue }
                throw StoreLock.posixError()
            }
            if count == 0 { return data }
            guard count <= maximumBytes - data.count else { throw NotebookError.transactionInvalid }
            data.append(contentsOf: buffer.prefix(count))
        }
    }

    func requireRegularFileOrAbsent(_ url: URL) throws {
        var attributes = stat()
        if lstat(url.path, &attributes) != 0 {
            if errno == ENOENT { return }
            throw StoreLock.posixError()
        }
        guard attributes.st_mode & S_IFMT == S_IFREG else { throw NotebookError.transactionInvalid }
    }

    func requireDirectory(_ url: URL) throws {
        var attributes = stat()
        guard lstat(url.path, &attributes) == 0, attributes.st_mode & S_IFMT == S_IFDIR else {
            throw NotebookError.transactionInvalid
        }
    }

    func syncDirectory(_ url: URL) throws {
        let fd = Darwin.open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard fd >= 0 else { throw StoreLock.posixError() }
        defer { Darwin.close(fd) }
        guard fsync(fd) == 0 else { throw StoreLock.posixError() }
    }

    func fullSyncFile(_ url: URL) throws {
        let fd = Darwin.open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard fd >= 0 else { throw StoreLock.posixError() }
        defer { Darwin.close(fd) }
        // fsync alone permits volatile device write caches on macOS. Fail if this
        // filesystem cannot provide the requested barrier; do not silently weaken it.
        guard fcntl(fd, F_FULLFSYNC) == 0 else { throw StoreLock.posixError() }
    }

    func sealTransactionBlob(_ plaintext: Data) throws -> Data {
        guard !plaintext.isEmpty else { throw NotebookError.emptyPayload }
        guard plaintext.count <= TransactionJournal.maximumWriteBytes - 128 else { throw NotebookError.transactionTooLarge }
        return try CryptoBox.seal(plaintext: plaintext, key: key)
    }

    func validateRawNames(_ names: [String], index: NotebookIndex) throws {
        let referenced = Set(TransactionJournal.files(index).map(TransactionJournal.normalized))
        guard names.allSatisfy({ !referenced.contains(TransactionJournal.normalized($0)) }) else {
            throw NotebookError.transactionInvalid
        }
    }
}
