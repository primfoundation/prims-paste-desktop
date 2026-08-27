import CryptoKit
import XCTest
@testable import PrimsPasteCore

final class SafePasteImportTests: XCTestCase {
    func testOpensSPB1WithLegacyMagic() throws {
        let key = SymmetricKey(size: .bits256)
        let plain = Data("mem0-space-not-a-real-secret".utf8)
        let sealed = try AES.GCM.seal(plain, using: key)
        var blob = SafePasteImport.magic
        blob.append(sealed.combined!)
        let out = try CryptoBox.open(blob: blob, key: key, magic: SafePasteImport.magic)
        XCTAssertEqual(out, plain)
        XCTAssertThrowsError(try CryptoBox.open(blob: blob, key: key))
    }

    func testSkipsFeatureWantedSeeds() {
        let fw = ItemMeta(
            id: "nb_fw_durable", kind: .note, x: 0, y: 0, width: 1, height: 1,
            createdAt: Date(), updatedAt: Date(), bytes: 4, caption: "Durable notebook",
            tabID: "tab_features-wanted"
        )
        let paste = ItemMeta(
            id: "nb_abc", kind: .paste, x: 0, y: 0, width: 1, height: 1,
            createdAt: Date(), updatedAt: Date(), bytes: 16, tabID: "2026-08-27"
        )
        XCTAssertFalse(SafePasteImport.shouldImport(fw))
        XCTAssertTrue(SafePasteImport.shouldImport(paste))
    }

    func testImportResealsAsPPB1AndKeepsCaption() throws {
        let oldKey = SymmetricKey(size: .bits256)
        let newKey = SymmetricKey(size: .bits256)
        let fm = FileManager.default
        let src = fm.temporaryDirectory.appendingPathComponent("sp-src-\(UUID().uuidString)")
        let dst = fm.temporaryDirectory.appendingPathComponent("pp-dst-\(UUID().uuidString)")
        defer {
            try? fm.removeItem(at: src)
            try? fm.removeItem(at: dst)
        }
        try fm.createDirectory(at: src.appendingPathComponent("blobs"), withIntermediateDirectories: true)
        let made = ISO8601DateFormatter().date(from: "2026-08-27T21:21:09Z")!
        let item = ItemMeta(
            id: "nb_mem0",
            kind: .paste,
            x: 80, y: 90, width: 230, height: 230,
            createdAt: made, updatedAt: made,
            bytes: 11,
            caption: "This was a mem0 key called mem0 space default space key.",
            looksLikeKey: true,
            keyKind: "entropy",
            day: "2026-08-27",
            tabID: "2026-08-27"
        )
        let plain = Data("hello-world".utf8)
        let sealed = try AES.GCM.seal(plain, using: oldKey)
        var blob = SafePasteImport.magic
        blob.append(sealed.combined!)
        try blob.write(to: src.appendingPathComponent("blobs/nb_mem0.enc"))
        var idx = NotebookIndex()
        idx.version = 2
        idx.items = [item]
        idx.tabs = [BoardTab(id: "2026-08-27", title: "today", colorHex: "#3D3A36")]
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        try enc.encode(idx).write(to: src.appendingPathComponent("index.json"))

        let dest = try NotebookStore(root: dst, key: newKey)
        let report = try SafePasteImport.run(into: dest, from: src, oldKey: oldKey)
        XCTAssertEqual(report.imported, 1)
        let got = try dest.loadIndex().items.first
        XCTAssertEqual(got?.caption, item.caption)
        XCTAssertEqual(got?.looksLikeKey, true)
        XCTAssertEqual(got?.tabID, "2026-08-27")
        let round = try dest.readBlob(id: got!.id)
        XCTAssertEqual(round, plain)
        let onDisk = try Data(contentsOf: dest.blobURL(id: got!.id))
        XCTAssertEqual(onDisk.prefix(4), CryptoBox.magic)
        let again = try SafePasteImport.run(into: dest, from: src, oldKey: oldKey)
        XCTAssertEqual(again.imported, 0)
        XCTAssertEqual(again.skipped, 1)
    }

    func testCLIParsesImport() {
        XCTAssertEqual(try CLIParser.parse(["import-safepaste"]).get(), .importSafepaste)
    }
}
