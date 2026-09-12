import CryptoKit
import XCTest
@testable import PrimsPasteCore

final class LegacyNotebookTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("legacy-notebook-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        return url
    }

    func testMediaMetadataPayloadJournalAndBackupRoundTrip() throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let key = SymmetricKey(size: .bits256)
        let store = try NotebookStore(root: dir.appendingPathComponent("source"), key: key)
        let payload = Data([0, 255, 0, 12, 102, 116, 121, 112, 9])
        for kind in [ItemKind.video, .file] {
            _ = try store.add(kind: kind, plaintext: payload, at: .zero, size: .zero, caption: "Synthetic media")
        }
        var index = try store.loadIndex()
        index.items[0].captionSource = .heard
        index.items[0].lane = "custom-future-column"
        index.items[1].captionSource = .typed
        index.fillDefaultID = index.items[1].id
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        index.workers = [RetainedWorker(id: "job-synthetic", kind: "transcribe", stickyID: index.items[0].id,
            title: "Synthetic", status: "running", detail: "retain status", createdAt: date, updatedAt: date)]
        let comment = PrimJSON.object(["body": .string("  Preserve spacing 漢字  "), "author": .object(["name": .string("Synthetic")])])
        index.items[0].conversion = Conversion(target: .docketTask, ref: "local#TASK-SYNTHETIC", title: "Synthetic", createdAt: date, lastComment: comment)
        try store.saveIndex(index)
        let expected = try store.loadIndex()
        XCTAssertEqual(expected.items[0].lane, "custom-future-column")
        XCTAssertEqual(expected.items[0].captionSource, .heard)
        XCTAssertEqual(expected.items[0].conversion?.lastComment, comment)
        XCTAssertEqual(expected.workers[0].status, "running")
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let legacy = try encoder.encode(expected)
        try legacy.write(to: store.indexURL)
        XCTAssertTrue(try store.loadIndex() == expected)
        XCTAssertEqual(try IndexEnvelope.plaintext(Data(contentsOf: store.root.appendingPathComponent("index.migration.enc")), key: key), legacy)
        let backup = dir.appendingPathComponent("copy.pboard")
        try store.exportBackup(to: backup)
        let restored = dir.appendingPathComponent("restored")
        try NotebookStore.restoreBackup(from: backup, to: restored, key: key)
        let reopened = try NotebookStore(root: restored, key: key)
        XCTAssertTrue(try reopened.loadIndex() == expected)
        for item in expected.items { XCTAssertTrue(try reopened.readBlob(id: item.id) == payload) }
    }

    func testLegacyCaptionDefaultsMatchInstalledSemanticsAndKeepExplicitOrigin() throws {
        let date = "2026-09-12T00:00:00Z"
        for kind in ["audio", "video", "file", "note"] {
            var item: [String: Any] = ["id": "synthetic", "kind": kind, "x": 0, "y": 0, "width": 230, "height": 230,
                "createdAt": date, "updatedAt": date, "bytes": 1, "caption": "Synthetic caption"]
            func decode() throws -> ItemMeta {
                let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
                return try d.decode(ItemMeta.self, from: JSONSerialization.data(withJSONObject: item))
            }
            XCTAssertEqual(try decode().captionSource, ["audio", "video"].contains(kind) ? .heard : .typed)
            XCTAssertEqual(try decode().lane, "inbox")
            item["captionSource"] = "typed"; item["lane"] = ""
            XCTAssertEqual(try decode().captionSource, .typed)
            XCTAssertEqual(try decode().lane, "")
        }
    }

    func testFutureWorkerFieldsAndCaptionOriginsStillFailClosed() throws {
        for object: [String: Any] in [
            ["version": 2, "items": [], "workers": [["new_execution_scope": "retain"]]],
            ["version": 2, "items": [["kind": "video", "captionSource": "future-origin"]]]
        ] {
            XCTAssertThrowsError(try NotebookCompatibility.requireSupported(object)) {
                XCTAssertEqual($0 as? NotebookError, .indexUnsupported)
            }
        }
    }

    /// Explicit operator-only integration; the ordinary suite never reads Keychain or private records.
    /// Input is a previously retained snapshot, never the active notebook. No record contents are logged.
    func testOptInPrivateSnapshotRoundTrip() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["PRIMBOARD_PRIVATE_SNAPSHOT_CHECK"] == "1", let path = env["PRIMBOARD_SNAPSHOT_ROOT"] else {
            throw XCTSkip("Private snapshot integration requires an explicit isolated snapshot and existing-key opt-in")
        }
        let original = URL(fileURLWithPath: path).standardizedFileURL
        XCTAssertNotEqual(original.resolvingSymlinksInPath(), Paths.defaultRoot.resolvingSymlinksInPath())
        guard original.resolvingSymlinksInPath() != Paths.defaultRoot.resolvingSymlinksInPath() else { return }
        guard let key = try KeychainKey.load() else { throw NotebookError.keychain("Original key is unavailable; no key was created") }
        let indexBytes = try Data(contentsOf: original.appendingPathComponent("index.json"))
        let expected = try IndexEnvelope.decode(IndexEnvelope.plaintext(indexBytes, key: key))
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let copied = dir.appendingPathComponent("copy")
        try FileManager.default.copyItem(at: original, to: copied)
        let store = try NotebookStore(root: copied, key: key)
        XCTAssertTrue(try store.loadIndex() == expected, "Metadata changed during migration")
        let backup = dir.appendingPathComponent("backup.pboard")
        try store.exportBackup(to: backup)
        let restored = dir.appendingPathComponent("restored")
        try NotebookStore.restoreBackup(from: backup, to: restored, key: key)
        let reopened = try NotebookStore(root: restored, key: key)
        XCTAssertTrue(try reopened.loadIndex() == expected, "Metadata changed during restore")
        for item in expected.items {
            let source = try Data(contentsOf: original.appendingPathComponent("blobs/\(item.id).enc"))
            XCTAssertTrue(try Data(contentsOf: reopened.blobURL(id: item.id)) == source, "Encrypted payload changed")
            XCTAssertTrue(try reopened.readBlob(id: item.id).count == item.bytes, "Payload authentication or size failed")
            if item.hasImage {
                XCTAssertTrue(try Data(contentsOf: reopened.imageURL(id: item.id)) == Data(contentsOf: original.appendingPathComponent("blobs/\(item.id)-img.enc")), "Encrypted image changed")
            }
        }
        XCTAssertTrue(try Data(contentsOf: original.appendingPathComponent("index.json")) == indexBytes, "Snapshot was modified")
    }
}
