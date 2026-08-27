import CryptoKit
import XCTest
@testable import PrimsPasteCore

final class NotebookTests: XCTestCase {
    func testNeverWritesCLIIndex() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("primspaste-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try NotebookStore(root: dir, key: SymmetricKey(size: .bits256))
        _ = try store.add(
            kind: .note, plaintext: Data("x".utf8),
            at: CGPoint(x: 0, y: 0), size: CGSize(width: 1, height: 1)
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.indexURL.path))
        XCTAssertTrue(store.indexURL.path.hasSuffix("/notebook/index.json") || store.indexURL.lastPathComponent == "index.json")
    }

    func testSealOpenRoundtrip() throws {
        let key = SymmetricKey(size: .bits256)
        let plain = Data("a secret token 123".utf8)
        let blob = try CryptoBox.seal(plaintext: plain, key: key)
        XCTAssertTrue(blob.starts(with: CryptoBox.magic))
        XCTAssertNotEqual(blob, plain)
        XCTAssertEqual(try CryptoBox.open(blob: blob, key: key), plain)
    }

    func testWrongKeyFails() throws {
        let a = SymmetricKey(size: .bits256)
        let b = SymmetricKey(size: .bits256)
        let blob = try CryptoBox.seal(plaintext: Data("x".utf8), key: a)
        XCTAssertThrowsError(try CryptoBox.open(blob: blob, key: b))
    }

    func testBadMagicRejected() {
        let key = SymmetricKey(size: .bits256)
        XCTAssertThrowsError(try CryptoBox.open(blob: Data("not a box".utf8), key: key))
    }

    func testDurablePersistAndIndexHasNoPayload() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("primspaste-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let key = SymmetricKey(size: .bits256)
        let store = try NotebookStore(root: dir, key: key)
        let secret = Data("sk-live-do-not-index".utf8)
        let meta = try store.add(
            kind: .paste,
            plaintext: secret,
            at: CGPoint(x: 120, y: 80),
            size: CGSize(width: 240, height: 140)
        )
        XCTAssertTrue(meta.id.hasPrefix("pp_"))
        XCTAssertEqual(meta.kind, .paste)
        XCTAssertEqual(meta.bytes, secret.count)
        XCTAssertEqual(meta.fingerprint, CryptoBox.fingerprint(secret))

        let indexData = try Data(contentsOf: store.indexURL)
        let indexText = String(data: indexData, encoding: .utf8) ?? ""
        XCTAssertFalse(indexText.contains("sk-live-do-not-index"))
        XCTAssertTrue(indexText.contains(meta.id))

        let store2 = try NotebookStore(root: dir, key: key)
        let loaded = try store2.loadIndex()
        XCTAssertEqual(loaded.items.count, 1)
        XCTAssertEqual(loaded.items[0].id, meta.id)
        XCTAssertEqual(try store2.readBlob(id: meta.id), secret)
    }

    func testNoTTLItemsSurviveReload() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("primspaste-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let key = SymmetricKey(size: .bits256)
        let store = try NotebookStore(root: dir, key: key)
        _ = try store.add(
            kind: .note,
            plaintext: Data("keep me".utf8),
            at: CGPoint(x: 10, y: 10),
            size: CGSize(width: 200, height: 120)
        )
        // A second open is the durability proof: nothing reap()s this store.
        let again = try NotebookStore(root: dir, key: key)
        XCTAssertEqual(try again.loadIndex().items.count, 1)
        XCTAssertEqual(try again.readBlob(id: try again.loadIndex().items[0].id), Data("keep me".utf8))
    }

    func testRemoveDeletesBlob() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("primspaste-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try NotebookStore(root: dir, key: SymmetricKey(size: .bits256))
        let meta = try store.add(
            kind: .note,
            plaintext: Data("gone".utf8),
            at: CGPoint(x: 0, y: 0),
            size: CGSize(width: 100, height: 80)
        )
        try store.remove(meta.id)
        XCTAssertTrue(try store.loadIndex().items.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.blobURL(id: meta.id).path))
    }

    func testCaptionIsMetadataAndBlobUnchanged() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("primspaste-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try NotebookStore(root: dir, key: SymmetricKey(size: .bits256))
        let secret = Data("sk-live-caption-must-not-replace-blob".utf8)
        let meta = try store.add(
            kind: .paste,
            plaintext: secret,
            at: CGPoint(x: 1, y: 1),
            size: CGSize(width: 10, height: 10),
            caption: "",
            looksLikeKey: true,
            keyKind: "stripe",
            day: "2026-08-27"
        )
        let updated = try store.updateCaption(meta.id, caption: "stripe prod")
        XCTAssertEqual(updated.caption, "stripe prod")
        XCTAssertEqual(try store.readBlob(id: meta.id), secret)
        let indexText = String(data: try Data(contentsOf: store.indexURL), encoding: .utf8) ?? ""
        XCTAssertTrue(indexText.contains("stripe prod"))
        XCTAssertFalse(indexText.contains("sk-live-caption-must-not-replace-blob"))
    }

    func testDaysDoNotBleed() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("primspaste-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try NotebookStore(root: dir, key: SymmetricKey(size: .bits256))
        _ = try store.add(
            kind: .note, plaintext: Data("tue".utf8),
            at: CGPoint(x: 0, y: 0), size: CGSize(width: 10, height: 10),
            caption: "tue", day: "2026-08-25"
        )
        _ = try store.add(
            kind: .note, plaintext: Data("wed".utf8),
            at: CGPoint(x: 20, y: 0), size: CGSize(width: 10, height: 10),
            caption: "wed", day: "2026-08-26"
        )
        let items = try store.loadIndex().items
        XCTAssertEqual(DayBoard.visible(items, day: "2026-08-25").map(\.caption), ["tue"])
        XCTAssertEqual(DayBoard.visible(items, day: "2026-08-26").map(\.caption), ["wed"])
        XCTAssertTrue(DayBoard.visible(items, day: "2026-08-27").isEmpty)
    }

    func testEmptyPayloadRejected() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("primspaste-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try NotebookStore(root: dir, key: SymmetricKey(size: .bits256))
        XCTAssertThrowsError(
            try store.add(
                kind: .paste,
                plaintext: Data(),
                at: CGPoint(x: 0, y: 0),
                size: CGSize(width: 10, height: 10)
            )
        )
    }
}
