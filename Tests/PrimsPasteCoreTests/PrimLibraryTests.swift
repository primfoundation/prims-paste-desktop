import CryptoKit
import XCTest
@testable import PrimsPasteCore

final class PrimLibraryTests: XCTestCase {
    private func root() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("prim-host-\(UUID().uuidString)") }
    private func op() -> String { "prim_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased() }

    func testBundledDefinitionsArePinnedAndGenericallyCreatable() throws {
        let library = try PrimLibrary.bundled()
        XCTAssertEqual(library.kits.count, 4)
        for kit in library.kits {
            let draft = try kit.draft(title: "Local draft 👩🏽‍💻")
            XCTAssertTrue(kit.validate(draft).isEmpty)
            XCTAssertEqual(try library.kit(for: kit.pin).pin, kit.pin)
            let wrong = PrimDefinitionPin(profileID: kit.pin.profileID, version: kit.pin.version, definitionSHA256: String(repeating: "0", count: 64))
            XCTAssertThrowsError(try library.kit(for: wrong))
        }
    }

    func testBadCatalogPinAndUnknownSchemaFailClosed() throws {
        XCTAssertThrowsError(try PrimLibrary(data: Data("{}".utf8), expectedSHA256: String(repeating: "0", count: 64)))
        XCTAssertThrowsError(try PrimSchema.check(.object(["$ref": .string("https://example.invalid/schema")])))
        XCTAssertThrowsError(try PrimSchema.check(.object(["pattern": .string(".*")])))
        XCTAssertThrowsError(try PrimSchema.check(.object(["required": .string("id")])))
    }

    func testJSONRejectsDuplicatesIncludingEscapedKeysAndExcessiveDepth() throws {
        for raw in [#"{"a":1,"a":2}"#, #"{"a":1,"\u0061":2}"#, #"{"nested":{"x":1,"x":2}}"#,
                    #"{"a":NaN}"#, #"{"n":9007199254740993}"#,
                    String(repeating: "[", count: 25) + "0" + String(repeating: "]", count: 25)] {
            XCTAssertThrowsError(try PrimJSON.parse(Data(raw.utf8)), raw)
        }
        let value = try PrimJSON.parse(Data(#"{"a":{"x":1},"b":{"x":2},"quote":"\""}"#.utf8))
        XCTAssertEqual(value["a"]["x"], .number(1))
    }

    func testPythonConformanceCasesAgreeWithNativeValidation() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/prim-host-cases.json")
        let corpus = try PrimJSON.parse(Data(contentsOf: file), maximum: 8 * 1024 * 1024)
        let library = try PrimLibrary.bundled()
        let cases = try XCTUnwrap(corpus["cases"].array)
        XCTAssertGreaterThan(cases.count, 40)
        for test in cases {
            let kit = try XCTUnwrap(library.kits.first { $0.pin.profileID == test["profile_id"].string })
            XCTAssertEqual(kit.pin.definitionSHA256, test["definition_sha256"].string)
            XCTAssertEqual(kit.validate(test["record"]).isEmpty, test["valid"] == .bool(true), test["name"].string ?? "case")
        }
    }

    func testEncryptedCreatePreservesSourceAndRetryIsIdempotent() throws {
        let dir = root(); defer { try? FileManager.default.removeItem(at: dir) }
        let key = SymmetricKey(size: .bits256), store = try NotebookStore(root: dir, key: key)
        let secret = Data("never copy the secret sticky payload".utf8)
        let source = try store.add(kind: .paste, plaintext: secret, at: .zero, size: .zero, caption: "Context")
        let kit = try PrimLibrary.bundled().kits[0], draft = try kit.draft(title: "New local record")
        let operation = op()
        let made = try store.createPrim(sourceID: source.id, kit: kit, record: draft, operationID: operation)
        XCTAssertEqual(try store.createPrim(sourceID: source.id, kit: kit, record: draft, operationID: operation), made)
        XCTAssertEqual(try store.loadIndex().items.count, 2)
        XCTAssertEqual(try store.readBlob(id: source.id), secret)
        XCTAssertNil(try store.readBlob(id: made.id).range(of: secret))
        let reopened = try NotebookStore(root: dir, key: key).loadIndex().items.first { $0.id == made.id }
        XCTAssertEqual(reopened?.primPin, kit.pin)
        XCTAssertEqual(reopened?.primSourceID, source.id)
        XCTAssertNil(try Data(contentsOf: store.blobURL(id: made.id)).range(of: Data("New local record".utf8)))
        XCTAssertNil(try Data(contentsOf: store.indexURL).range(of: Data(kit.pin.profileID.utf8)))
    }

    func testPrimAndNoteEditsRejectStaleWriters() throws {
        let dir = root(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = try NotebookStore(root: dir, key: SymmetricKey(size: .bits256))
        let kit = try PrimLibrary.bundled().kits[0]
        let draft = try kit.draft(title: "before")
        let item = try store.createPrim(sourceID: nil, kit: kit, record: draft, operationID: op())
        let before = try store.readBlob(id: item.id)
        var a = draft.object!; a[kit.titleField] = .string("writer A")
        _ = try store.updatePrim(item.id, kit: kit, record: .object(a), expected: before)
        var b = draft.object!; b[kit.titleField] = .string("writer B")
        XCTAssertThrowsError(try store.updatePrim(item.id, kit: kit, record: .object(b), expected: before))
        XCTAssertEqual(try PrimJSON.parse(store.readBlob(id: item.id))[kit.titleField], .string("writer A"))
        let note = try store.add(kind: .note, plaintext: Data("before".utf8), at: .zero, size: .zero)
        _ = try store.updatePayload(note.id, plaintext: Data("A".utf8), expected: Data("before".utf8))
        XCTAssertThrowsError(try store.updatePayload(note.id, plaintext: Data("B".utf8), expected: Data("before".utf8)))
    }

    func testAllProfilesExportImportPreserveUnknownFieldsAndRefuseOverwrite() throws {
        let dir = root(); try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: dir) }
        let library = try PrimLibrary.bundled()
        for kit in library.kits {
            var draft = try kit.draft(title: "Title\n---\nnot: frontmatter").object!
            draft["external_extension"] = .object(["keep": .array([.bool(true), .string("漢字")])])
            let record = PrimJSON.object(draft), target = dir.appendingPathComponent(UUID().uuidString)
            try PrimPack.write(record: record, kit: kit, to: target)
            let (loaded, restored) = try PrimPack.read(target, library: library)
            XCTAssertEqual(loaded.pin, kit.pin); XCTAssertEqual(restored, record)
            XCTAssertThrowsError(try PrimPack.write(record: record, kit: kit, to: target))
            let pin = target.appendingPathComponent("prim-definition.lock.json")
            try Data("{}".utf8).write(to: pin)
            XCTAssertThrowsError(try PrimPack.read(target, library: library))
        }
    }

    func testPackRejectsSymlinksAndUnsafeTargets() throws {
        let dir = root(); try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: dir) }
        let library = try PrimLibrary.bundled(), kit = library.kits[0]
        let pack = dir.appendingPathComponent("record.prim")
        try PrimPack.write(record: kit.draft(title: nil), kit: kit, to: pack)
        let link = dir.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: pack)
        XCTAssertThrowsError(try PrimPack.read(link, library: library))
        XCTAssertThrowsError(try PrimPack.write(record: kit.draft(title: nil), kit: kit, to: link.appendingPathComponent("child")))
    }

    func testPrimCLIRequiresExactVersionsAndRejectsAmbiguousOptions() throws {
        XCTAssertEqual(try CLIParser.parse(["profiles"]).get(), .profiles)
        XCTAssertThrowsError(try CLIParser.parse(["prim", "create", "primfoundation/person"]).get())
        XCTAssertThrowsError(try CLIParser.parse(["prim", "create", "primfoundation/person", "--version", "a", "--version", "b"]).get())
        XCTAssertEqual(try CLIParser.parse(["prim", "export", "id", "--to", "new"]).get(), .primExport(id: "id", destination: "new"))
    }
}
