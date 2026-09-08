import CryptoKit
import XCTest
@testable import PrimsPasteCore

final class NotebookRecoveryTests: XCTestCase {
    private func root() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("primboard-recovery-\(UUID().uuidString)")
    }

    private func encode(_ index: NotebookIndex) throws -> Data {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(index)
    }

    private func add(_ store: NotebookStore) throws -> ItemMeta {
        try store.add(kind: .paste, plaintext: Data("private payload".utf8), at: .zero, size: .zero,
            caption: "private caption", looksLikeKey: true, keyKind: "private classification")
    }

    func testIndexMetadataIsEncryptedAndOldJSONReaderFails() throws {
        let dir = root(); defer { try? FileManager.default.removeItem(at: dir) }
        let key = SymmetricKey(size: .bits256)
        let store = try NotebookStore(root: dir, key: key)
        let item = try add(store)
        _ = try store.addTab(title: "private tab", colorHex: "#123456")
        let before = try store.loadIndex()
        let bytes = try Data(contentsOf: store.indexURL)
        XCTAssertTrue(bytes.starts(with: IndexEnvelope.magic))
        for secret in [item.id, item.caption, "private tab", "private classification", "private payload"] {
            XCTAssertNil(bytes.range(of: Data(secret.utf8)))
        }
        let oldReader = JSONDecoder(); oldReader.dateDecodingStrategy = .iso8601
        XCTAssertThrowsError(try oldReader.decode(NotebookIndex.self, from: bytes))
        XCTAssertEqual(try NotebookStore(root: dir, key: key).loadIndex(), before)
    }

    func testLegacyMigrationKeepsExactEncryptedBackupAndIdentity() throws {
        let dir = root(); defer { try? FileManager.default.removeItem(at: dir) }
        let key = SymmetricKey(size: .bits256)
        let store = try NotebookStore(root: dir, key: key)
        _ = try add(store)
        _ = try store.addTab(title: "keep this tab", colorHex: "#ffffff")
        let before = try store.loadIndex()
        let legacy = try encode(before) + Data("\n  \n".utf8)
        try legacy.write(to: store.indexURL)
        XCTAssertEqual(try store.loadIndex(), before)
        let saved = try Data(contentsOf: dir.appendingPathComponent("index.migration.enc"))
        XCTAssertEqual(try IndexEnvelope.plaintext(saved, key: key), legacy)
        XCTAssertTrue(try Data(contentsOf: store.indexURL).starts(with: IndexEnvelope.magic))
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent("index.migration.enc").path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        try FileManager.default.removeItem(at: store.indexURL)
        XCTAssertThrowsError(try store.loadIndex())
    }

    func testWrongKeyAndTamperedIndexNeverRewritePrimary() throws {
        let dir = root(); defer { try? FileManager.default.removeItem(at: dir) }
        let key = SymmetricKey(size: .bits256)
        let store = try NotebookStore(root: dir, key: key)
        _ = try add(store)
        let before = try Data(contentsOf: store.indexURL)
        let wrong = try NotebookStore(root: dir, key: SymmetricKey(size: .bits256))
        XCTAssertThrowsError(try wrong.loadIndex())
        XCTAssertEqual(try Data(contentsOf: store.indexURL), before)
        var corrupt = before; corrupt[corrupt.count - 1] ^= 1
        try corrupt.write(to: store.indexURL)
        XCTAssertThrowsError(try store.loadIndex())
        XCTAssertEqual(try Data(contentsOf: store.indexURL), corrupt)
    }

    func testWrongKeyCannotMigrateLegacyIndex() throws {
        let dir = root(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = try NotebookStore(root: dir, key: SymmetricKey(size: .bits256))
        _ = try add(store)
        let legacy = try encode(store.loadIndex())
        try legacy.write(to: store.indexURL)
        let wrong = try NotebookStore(root: dir, key: SymmetricKey(size: .bits256))
        XCTAssertThrowsError(try wrong.loadIndex())
        XCTAssertEqual(try Data(contentsOf: store.indexURL), legacy)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("index.migration.enc").path))
    }

    func testBackupRestoresTextImageMetadataAndPrivatePermissions() throws {
        let dir = root(); defer { try? FileManager.default.removeItem(at: dir) }
        let key = SymmetricKey(size: .bits256)
        let store = try NotebookStore(root: dir.appendingPathComponent("original"), key: key)
        let item = try add(store)
        let image = Data([137, 80, 78, 71, 13, 10, 26, 10, 1, 2, 3])
        try store.writeImage(item.id, png: image)
        _ = try store.addTab(title: "private tab", colorHex: "#123456")
        let before = try store.loadIndex()
        let originalBytes = try Data(contentsOf: store.indexURL)
        let backup = dir.appendingPathComponent("recovery.pboard")
        try store.exportBackup(to: backup)
        let archive = try Data(contentsOf: backup)
        XCTAssertTrue(archive.starts(with: CryptoBox.magic))
        XCTAssertNil(archive.range(of: Data("private caption".utf8)))
        let restored = dir.appendingPathComponent("restored")
        try NotebookStore.restoreBackup(from: backup, to: restored, key: key)
        let reopened = try NotebookStore(root: restored, key: key)
        XCTAssertEqual(try reopened.loadIndex(), before)
        XCTAssertEqual(try reopened.readBlob(id: item.id), Data("private payload".utf8))
        XCTAssertEqual(try reopened.readImage(item.id), image)
        XCTAssertEqual(try Data(contentsOf: store.indexURL), originalBytes)
        for file in [backup, reopened.indexURL, reopened.blobURL(id: item.id), reopened.imageURL(id: item.id)] {
            XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        }
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: restored.path)[.posixPermissions] as? NSNumber)?.intValue, 0o700)
    }

    func testRecoveryNeverOverwritesExistingFilesOrDirectories() throws {
        let dir = root(); defer { try? FileManager.default.removeItem(at: dir) }
        let key = SymmetricKey(size: .bits256)
        let store = try NotebookStore(root: dir.appendingPathComponent("original"), key: key)
        _ = try add(store)
        let backup = dir.appendingPathComponent("recovery.pboard")
        try store.exportBackup(to: backup)
        let originalArchive = try Data(contentsOf: backup)
        XCTAssertThrowsError(try store.exportBackup(to: backup))
        XCTAssertEqual(try Data(contentsOf: backup), originalArchive)
        let indexBefore = try Data(contentsOf: store.indexURL)
        XCTAssertThrowsError(try NotebookStore.restoreBackup(from: backup, to: store.root, key: key))
        XCTAssertEqual(try Data(contentsOf: store.indexURL), indexBefore)
    }

    func testWrongKeyTamperingAndIncompleteBackupLeaveNoDestination() throws {
        let dir = root(); defer { try? FileManager.default.removeItem(at: dir) }
        let key = SymmetricKey(size: .bits256)
        let store = try NotebookStore(root: dir.appendingPathComponent("original"), key: key)
        _ = try add(store)
        let backup = dir.appendingPathComponent("recovery.pboard")
        let destination = dir.appendingPathComponent("restored")
        try store.exportBackup(to: backup)
        let original = try Data(contentsOf: backup)
        XCTAssertThrowsError(try NotebookStore.restoreBackup(from: backup, to: destination, key: SymmetricKey(size: .bits256)))
        var corrupt = original; corrupt[corrupt.count - 1] ^= 1
        try corrupt.write(to: backup)
        XCTAssertThrowsError(try NotebookStore.restoreBackup(from: backup, to: destination, key: key))
        let decoded = try CryptoBox.open(blob: original, key: key)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: decoded) as? [String: Any])
        object["blobs"] = [String: String]()
        let incomplete = try CryptoBox.seal(plaintext: JSONSerialization.data(withJSONObject: object), key: key)
        try incomplete.write(to: backup)
        XCTAssertThrowsError(try NotebookStore.restoreBackup(from: backup, to: destination, key: key))
        object["blobs"] = ["../escape.enc": Data("bad".utf8).base64EncodedString()]
        try CryptoBox.seal(plaintext: JSONSerialization.data(withJSONObject: object), key: key).write(to: backup)
        XCTAssertThrowsError(try NotebookStore.restoreBackup(from: backup, to: destination, key: key))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: dir.path).contains { $0.hasPrefix(".primboard-restore-") })
    }

    func testInvalidLegacyPathsAndCollisionsFailBeforeMigration() throws {
        let dir = root(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = try NotebookStore(root: dir, key: SymmetricKey(size: .bits256))
        let item = try add(store)
        let good = try store.loadIndex()
        for badID in ["../outside", "dir/name", "dir\\name", ".."] {
            var invalid = good; invalid.items[0].id = badID
            let bytes = try encode(invalid); try bytes.write(to: store.indexURL)
            XCTAssertThrowsError(try store.loadIndex())
            XCTAssertEqual(try Data(contentsOf: store.indexURL), bytes)
        }
        var collision = good
        collision.items[0].hasImage = true
        var second = item; second.id = item.id + "-img"
        collision.items.append(second)
        XCTAssertThrowsError(try IndexEnvelope.decode(encode(collision)))
        second.id = item.id.uppercased(); collision.items[1] = second
        XCTAssertThrowsError(try IndexEnvelope.decode(encode(collision)))
        XCTAssertThrowsError(try IndexEnvelope.decode(Data(#"{"version":3,"items":[]}"#.utf8)))
    }

    func testBackupRejectsMissingOrChangedPayload() throws {
        let dir = root(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = try NotebookStore(root: dir, key: SymmetricKey(size: .bits256))
        let item = try add(store)
        let backup = dir.appendingPathComponent("backup.pboard")
        // Simulate external corruption. The public writeBlob API now updates its
        // corresponding metadata transactionally and cannot create this mismatch.
        let altered = try CryptoBox.seal(plaintext: Data("different length".utf8), key: store.key)
        try altered.write(to: store.blobURL(id: item.id))
        XCTAssertThrowsError(try store.exportBackup(to: backup))
        try FileManager.default.removeItem(at: store.blobURL(id: item.id))
        XCTAssertThrowsError(try store.exportBackup(to: backup))
        XCTAssertFalse(FileManager.default.fileExists(atPath: backup.path))
    }

    func testRecoveryCLIRequiresExplicitNewDestination() {
        XCTAssertEqual(CLIParser.parse(["backup", "saved.pboard"]), .success(.backup(path: "saved.pboard")))
        XCTAssertEqual(CLIParser.parse(["restore", "saved.pboard", "--to", "restored"]), .success(.restore(path: "saved.pboard", destination: "restored")))
        for args in [["backup"], ["backup", "one", "two"], ["restore", "saved.pboard"], ["restore", "saved.pboard", "--force", "live"]] {
            if case .success = CLIParser.parse(args) { XCTFail("Unsafe or incomplete recovery invocation accepted") }
        }
    }
}
