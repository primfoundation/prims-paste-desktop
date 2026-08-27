import CryptoKit
import XCTest
@testable import PrimsPasteCore

final class TabDragCoverTests: XCTestCase {
    func testPaintOrderPutsHigherZLastAndDraggedOnTop() {
        let a = ItemMeta(
            id: "a", kind: .note, x: 0, y: 0, width: 1, height: 1,
            createdAt: Date(timeIntervalSince1970: 1), updatedAt: Date(), bytes: 1,
            tabID: "t", z: 1
        )
        let b = ItemMeta(
            id: "b", kind: .note, x: 0, y: 0, width: 1, height: 1,
            createdAt: Date(timeIntervalSince1970: 2), updatedAt: Date(), bytes: 1,
            tabID: "t", z: 3
        )
        let c = ItemMeta(
            id: "c", kind: .note, x: 0, y: 0, width: 1, height: 1,
            createdAt: Date(timeIntervalSince1970: 3), updatedAt: Date(), bytes: 1,
            tabID: "t", z: 2
        )
        XCTAssertEqual(DragMath.paintOrder([a, b, c], draggingID: nil).map(\.id), ["a", "c", "b"])
        XCTAssertEqual(DragMath.paintOrder([a, b, c], draggingID: "a").map(\.id), ["c", "b", "a"])
        XCTAssertEqual(DragMath.nextZ([a, b, c]), 4)
    }

    func testBringToFrontPersistsHighestZ() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("primspaste-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try NotebookStore(root: dir, key: SymmetricKey(size: .bits256))
        let first = try store.add(
            kind: .note, plaintext: Data("one".utf8),
            at: CGPoint(x: 0, y: 0), size: CGSize(width: 10, height: 10)
        )
        let second = try store.add(
            kind: .note, plaintext: Data("two".utf8),
            at: CGPoint(x: 1, y: 1), size: CGSize(width: 10, height: 10)
        )
        _ = try store.bringToFront(first.id)
        let items = try store.loadIndex().items
        let z1 = items.first { $0.id == first.id }!.z
        let z2 = items.first { $0.id == second.id }!.z
        XCTAssertGreaterThan(z1, z2)
        XCTAssertEqual(DragMath.paintOrder(items, draggingID: nil).last?.id, first.id)
    }

    func testOldItemsDefaultZZero() throws {
        let json = """
        {"version":1,"items":[{"id":"nb_old","kind":"note","x":1,"y":2,"width":3,"height":4,"createdAt":"2026-08-27T21:04:11Z","updatedAt":"2026-08-27T21:04:11Z","bytes":1}]}
        """.data(using: .utf8)!
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let idx = try dec.decode(NotebookIndex.self, from: json)
        XCTAssertEqual(idx.items[0].z, 0)
    }

    func testDragCommitsOnlyOnEnd() {
        XCTAssertFalse(DragMath.shouldPersist(ended: false))
        XCTAssertTrue(DragMath.shouldPersist(ended: true))
    }

    func testPositionIsStartPlusTranslation() {
        let p = DragMath.position(start: CGPoint(x: 10, y: 20), translation: CGSize(width: 5, height: -3))
        XCTAssertEqual(p.x, 15)
        XCTAssertEqual(p.y, 17)
    }

    func testTabHit() {
        let frames = [
            "tab_a": CGRect(x: 0, y: 0, width: 160, height: 56),
            "tab_b": CGRect(x: 180, y: 0, width: 160, height: 56),
        ]
        XCTAssertEqual(DragMath.tabHit(CGPoint(x: 20, y: 20), frames: frames), "tab_a")
        XCTAssertEqual(DragMath.tabHit(CGPoint(x: 200, y: 10), frames: frames), "tab_b")
        XCTAssertNil(DragMath.tabHit(CGPoint(x: 900, y: 900), frames: frames))
    }

    func testAssignTabDoesNotCopyPayloadToIndex() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("primspaste-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try NotebookStore(root: dir, key: SymmetricKey(size: .bits256))
        let meta = try store.add(
            kind: .note,
            plaintext: Data("secret-body".utf8),
            at: CGPoint(x: 0, y: 0),
            size: CGSize(width: 10, height: 10),
            caption: "note",
            tabID: "today"
        )
        _ = try store.addTab(title: "features-wanted", colorHex: "#C45C26")
        let moved = try store.assignTab(meta.id, tabID: FeaturesWanted.tabID)
        XCTAssertEqual(moved.tabID, FeaturesWanted.tabID)
        let text = String(data: try Data(contentsOf: store.indexURL), encoding: .utf8) ?? ""
        XCTAssertFalse(text.contains("secret-body"))
    }

    func testSeedFeaturesWantedOnce() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("primspaste-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try NotebookStore(root: dir, key: SymmetricKey(size: .bits256))
        try store.seedFeaturesWanted()
        try store.seedFeaturesWanted()
        let idx = try store.loadIndex()
        XCTAssertTrue(idx.tabs.contains { $0.id == FeaturesWanted.tabID })
        let onTab = idx.items.filter { $0.tabID == FeaturesWanted.tabID }
        XCTAssertEqual(onTab.count, FeaturesWanted.all.count)
        XCTAssertEqual(Set(onTab.map(\.id)).count, FeaturesWanted.all.count)
    }

    func testLoopbackChatOnly() {
        XCTAssertTrue(ChatSettings.isLoopback("http://127.0.0.1:11434"))
        XCTAssertTrue(ChatSettings.isLoopback("http://localhost:8080"))
        XCTAssertFalse(ChatSettings.isLoopback("https://api.openai.com/v1"))
        XCTAssertFalse(ChatSettings.isLoopback("https://api.anthropic.com"))
        var s = ChatSettings.none
        s.engine = "ollama"
        s.endpoint = "https://api.openai.com"
        XCTAssertTrue(s.rejectedBecauseOnline)
    }

    func testCoverOnlyWhenNotWorking() {
        XCTAssertFalse(CoverPolicy.shouldCover(working: true, windowActive: true, idleFor: 999))
        XCTAssertFalse(CoverPolicy.shouldCover(working: true, windowActive: false, idleFor: 999))
        XCTAssertFalse(CoverPolicy.shouldCover(working: false, windowActive: false, idleFor: 0))
        XCTAssertFalse(CoverPolicy.shouldCover(working: false, windowActive: false, idleFor: 1))
        XCTAssertTrue(CoverPolicy.shouldCover(working: false, windowActive: false, idleFor: 2))
        XCTAssertFalse(CoverPolicy.shouldCover(working: false, windowActive: true, idleFor: 10))
        XCTAssertTrue(CoverPolicy.shouldCover(working: false, windowActive: true, idleFor: 45))
        XCTAssertFalse(CoverPolicy.shouldCover(working: false, windowActive: false, idleFor: 99, unlocked: false))
    }

    func testOldItemGetsTabIDFromDay() throws {
        let json = """
        {"version":1,"items":[{"id":"nb_old","kind":"note","x":1,"y":2,"width":3,"height":4,"createdAt":"2026-08-27T21:04:11Z","updatedAt":"2026-08-27T21:04:11Z","bytes":1,"caption":"hi"}]}
        """.data(using: .utf8)!
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let idx = try dec.decode(NotebookIndex.self, from: json)
        XCTAssertEqual(idx.items[0].tabID, idx.items[0].day)
        XCTAssertFalse(idx.tabs.isEmpty)
    }
}
