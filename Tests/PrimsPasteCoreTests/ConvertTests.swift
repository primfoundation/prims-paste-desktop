import CryptoKit
import XCTest
@testable import PrimsPasteCore

final class ConvertTests: XCTestCase {
    func testNeverTouchesPayload() {
        XCTAssertFalse(Convert.usesPayload())
        XCTAssertEqual(Convert.title(from: "watch the haul", target: .paseoAgent), "watch the haul")
        XCTAssertEqual(Convert.title(from: "  ", target: .docketTask), "Docket task")
        XCTAssertTrue(Convert.docketNotes(title: "x").count >= 160)
    }

    func testStoreConvertWritesCaptionNotBlob() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("primspaste-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try NotebookStore(root: dir, key: SymmetricKey(size: .bits256))
        let meta = try store.add(
            kind: .note,
            plaintext: Data("sk-live-do-not-send-to-docket".utf8),
            at: CGPoint(x: 0, y: 0),
            size: CGSize(width: 10, height: 10),
            caption: "invoice follow-up"
        )
        let conv = Conversion(target: .docketTask, ref: "docket:/tmp#TASK-0001", title: "invoice follow-up")
        let done = try store.convert(meta.id, conversion: conv)
        XCTAssertEqual(done.conversion?.target, .docketTask)
        XCTAssertEqual(done.conversion?.ref, "docket:/tmp#TASK-0001")
        let text = String(data: try Data(contentsOf: store.indexURL), encoding: .utf8) ?? ""
        XCTAssertFalse(text.contains("sk-live-do-not-send-to-docket"))
        XCTAssertTrue(text.contains("invoice follow-up"))
        XCTAssertEqual(try store.readBlob(id: meta.id), Data("sk-live-do-not-send-to-docket".utf8))
    }

    func testLiveDocketCreate() throws {
        let pack = FileManager.default.temporaryDirectory
            .appendingPathComponent("primspaste-docket-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: pack) }
        let live = ConvertLive(packDir: pack)
        let conv = try live.convert(target: .docketTask, stickyID: "pp_test", caption: "invoice follow-up")
        XCTAssertEqual(conv.target, .docketTask)
        XCTAssertEqual(conv.title, "invoice follow-up")
        XCTAssertTrue(conv.ref.contains("TASK-"), conv.ref)
        XCTAssertTrue(FileManager.default.fileExists(atPath: pack.appendingPathComponent("tasks.jsonl").path))
    }

    func testPaseoRunnerGetsNoPayload() throws {
        var seen: [[String]] = []
        let live = ConvertLive(packDir: URL(fileURLWithPath: "/tmp/pp-docket")) { argv in
            seen.append(argv)
            let json = #"{"agentId":"agt_test"}"#
            return (0, Data(json.utf8))
        }
        let conv = try live.convert(target: .paseoAgent, stickyID: "pp_1", caption: "watch the haul")
        XCTAssertEqual(conv.ref, "paseo:agt_test")
        let flat = seen.flatMap { $0 }.joined(separator: " ")
        XCTAssertFalse(flat.contains("sk-"))
        XCTAssertTrue(flat.contains("paseo"))
        XCTAssertTrue(flat.contains("watch the haul"))
    }

    func testTargetsAreTheOnesWeNamed() {
        XCTAssertEqual(ConvertTarget.allCases.map(\.menuLabel), ["Docket task", "Paseo agent", "Note"])
    }

    func testDocketIDFromRef() {
        XCTAssertEqual(Convert.docketID(from: "docket:/tmp/pack#TASK-0007"), "TASK-0007")
        XCTAssertNil(Convert.docketID(from: "paseo:agt_1"))
    }

    func testClearConversionUnlinks() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("primspaste-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try NotebookStore(root: dir, key: SymmetricKey(size: .bits256))
        let meta = try store.add(
            kind: .note,
            plaintext: Data("keep-me".utf8),
            at: CGPoint(x: 0, y: 0),
            size: CGSize(width: 10, height: 10),
            caption: "invoice follow-up"
        )
        _ = try store.convert(meta.id, conversion: Conversion(target: .docketTask, ref: "docket:/tmp#TASK-0001", title: "invoice follow-up"))
        let back = try store.clearConversion(meta.id)
        XCTAssertNil(back.conversion)
        XCTAssertEqual(try store.readBlob(id: meta.id), Data("keep-me".utf8))
    }

    func testDocketCardDecodesKebabFields() throws {
        let json = """
        {"id":"TASK-0001","title":"Ship login","status":"To Do","notes":"A real brief lives here. Second sentence for the floor.","requirements":["Keep the sticky linked.","Do not copy secrets."],"test-cases":["Editor opens."],"acceptance-criteria":["Ref points at this card.","Title matches caption."]}
        """.data(using: .utf8)!
        let card = try JSONDecoder().decode(DocketCard.self, from: json)
        XCTAssertEqual(card.id, "TASK-0001")
        XCTAssertEqual(card.testCases, ["Editor opens."])
        XCTAssertEqual(card.acceptance.count, 2)
    }

    func testViewAndSaveTaskNeverSeePayload() throws {
        var seen: [[String]] = []
        let json = #"{"id":"TASK-0009","title":"Ship login","status":"To Do","notes":"Brief one. Brief two for length and a second sentence.","requirements":["Keep the sticky linked to this card.","Do not copy secret payloads from the sticky."],"test-cases":["The editor opens."],"acceptance-criteria":["conversion.ref points at this docket card.","The docket title matches the sticky caption."]}"#
        let live = ConvertLive(packDir: URL(fileURLWithPath: "/tmp/pp-docket")) { argv in
            seen.append(argv)
            return (0, Data(json.utf8))
        }
        let card = try live.viewTask(id: "TASK-0009")
        XCTAssertEqual(card.id, "TASK-0009")
        var draft = card
        draft.title = "Ship login for real"
        try live.saveTask(draft)
        let flat = seen.flatMap { $0 }.joined(separator: " ")
        XCTAssertFalse(flat.contains("sk-live"))
        XCTAssertFalse(flat.contains("do-not-send"))
        XCTAssertTrue(flat.contains("task-edit"))
        XCTAssertTrue(flat.contains("Ship login for real"))
    }

    func testRevertArchivesDocketCard() throws {
        let pack = FileManager.default.temporaryDirectory
            .appendingPathComponent("primspaste-docket-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: pack) }
        let live = ConvertLive(packDir: pack)
        let conv = try live.convert(target: .docketTask, stickyID: "pp_test", caption: "invoice follow-up")
        try live.revert(conv)
        let lines = try String(contentsOf: pack.appendingPathComponent("tasks.jsonl"), encoding: .utf8)
        XCTAssertTrue(lines.contains("\"archived\":true") || lines.contains("\"archived\": true"), lines)
    }
}
