import CryptoKit
import XCTest
@testable import PrimsPasteCore

final class UpgradeBoundaryTests: XCTestCase {
    private func root() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("upgrade-boundary-\(UUID().uuidString)")
    }

    func testUnsupportedLegacyDataIsClassifiedWithoutMigrationOrDataLoss() throws {
        let dir = root(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = try NotebookStore(root: dir, key: SymmetricKey(size: .bits256))
        let item = try store.add(kind: .note, plaintext: Data("synthetic original".utf8), at: .zero, size: .zero)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let original = try encoder.encode(store.loadIndex())
        let baseline = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
        let blob = try Data(contentsOf: store.blobURL(id: item.id))
        for change in ["kind", "item", "root", "tab", "chat", "conversion", "pin", "version", "caption"] {
            var value = baseline
            var items = try XCTUnwrap(value["items"] as? [[String: Any]])
            switch change {
            case "kind": items[0]["kind"] = "future-media"
            case "item": items[0]["future_layout"] = "retain this"
            case "root": value["future_root"] = NSNull()
            case "tab":
                var tabs = try XCTUnwrap(value["tabs"] as? [[String: Any]])
                if tabs.isEmpty { tabs = [["id": "synthetic", "title": "tab", "colorHex": "#000000", "createdAt": "2026-09-12T00:00:00Z"]] }
                tabs[0]["future_tab"] = true; value["tabs"] = tabs
            case "chat": value["chat"] = ["future_chat": "retain"]
            case "conversion": items[0]["conversion"] = ["future_conversion": "retain"]
            case "pin": items[0]["primPin"] = ["future_pin": "retain"]
            case "version": value["version"] = 3
            case "caption": items[0]["caption"] = "current"; items[0]["description"] = "different legacy text"
            default: XCTFail("Missing mutation")
            }
            value["items"] = items
            let legacy = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
            try legacy.write(to: store.indexURL)
            XCTAssertThrowsError(try store.loadIndex(), change) {
                XCTAssertEqual($0 as? NotebookError, .indexUnsupported, change)
            }
            XCTAssertEqual(try Data(contentsOf: store.indexURL), legacy, change)
            XCTAssertEqual(try Data(contentsOf: store.blobURL(id: item.id)), blob, change)
            XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("index.migration.enc").path))
        }
    }

    func testUnsupportedEncryptedIndexIsNotRewritten() throws {
        let dir = root(); defer { try? FileManager.default.removeItem(at: dir) }
        let key = SymmetricKey(size: .bits256), store = try NotebookStore(root: dir, key: key)
        let raw = Data(#"{"version":2,"items":[],"new_setting":true}"#.utf8)
        let sealed = try IndexEnvelope.seal(raw, key: key); try sealed.write(to: store.indexURL)
        XCTAssertThrowsError(try store.loadIndex()) { XCTAssertEqual($0 as? NotebookError, .indexUnsupported) }
        XCTAssertEqual(try Data(contentsOf: store.indexURL), sealed)
    }

    func testPackWithAdditionalFilesIsRefusedWithoutChangingOriginals() throws {
        let dir = root(); try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: dir) }
        let library = try PrimLibrary.bundled(), kit = library.kits[0]
        let pack = dir.appendingPathComponent("record.prim")
        try PrimPack.write(record: kit.draft(title: "Synthetic"), kit: kit, to: pack)
        let authority = try Data(contentsOf: pack.appendingPathComponent(kit.authorityFile))
        let attachment = pack.appendingPathComponent("original.bin")
        let bytes = Data([0, 255, 1, 2, 3]); try bytes.write(to: attachment)
        XCTAssertThrowsError(try PrimPack.read(pack, library: library))
        XCTAssertEqual(try Data(contentsOf: attachment), bytes)
        XCTAssertEqual(try Data(contentsOf: pack.appendingPathComponent(kit.authorityFile)), authority)
    }

    func testCapturedResearchCannotBecomeAnAttachmentlessNativeRecord() throws {
        let dir = root(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = try NotebookStore(root: dir, key: SymmetricKey(size: .bits256))
        let library = try PrimLibrary.bundled()
        let kit = try XCTUnwrap(library.kits.first { $0.pin.profileID == "primfoundation/research" })
        var draft = try kit.draft(title: "Synthetic capture").object!
        draft["sources"] = .array([.object([
            "id": .string("source-a"), "kind": .string("artifact"), "locator": .string("local:synthetic"),
            "artifact": .object(["path": .string("artifacts/original.bin"), "bytes": .number(3), "sha256": .string(String(repeating: "a", count: 64))])
        ])])
        let record = PrimJSON.object(draft)
        XCTAssertTrue(kit.validate(record).isEmpty)
        let operation = "prim_" + String(repeating: "a", count: 32)
        XCTAssertThrowsError(try store.createPrim(sourceID: nil, kit: kit, record: record, operationID: operation))
        XCTAssertTrue(try store.loadIndex().items.isEmpty)
        let destination = dir.appendingPathComponent("incomplete.prim")
        XCTAssertThrowsError(try PrimPack.write(record: record, kit: kit, to: destination))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }
}

