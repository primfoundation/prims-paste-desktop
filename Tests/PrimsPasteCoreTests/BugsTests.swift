import CryptoKit
import XCTest
@testable import PrimsPasteCore

final class BugsTests: XCTestCase {
    func testBugIdsAreStableAndDistinctFromFeatures() {
        let ids = Bugs.all.map(\.bugStickyID)
        XCTAssertEqual(ids.count, Set(ids).count)
        XCTAssertTrue(ids.allSatisfy { $0.hasPrefix("pp_bug_") })
        XCTAssertTrue(Set(ids).isDisjoint(with: Set(FeaturesWanted.all.map(\.stickyID))))
    }

    func testSeedBugsThenIdempotent() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("primspaste-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try NotebookStore(root: dir, key: SymmetricKey(size: .bits256))
        try store.seedBugs()
        try store.seedBugs()
        let idx = try store.loadIndex()
        XCTAssertTrue(idx.tabs.contains { $0.id == Bugs.tabID })
        XCTAssertEqual(idx.items.filter { $0.tabID == Bugs.tabID }.count, Bugs.all.count)
    }
}
