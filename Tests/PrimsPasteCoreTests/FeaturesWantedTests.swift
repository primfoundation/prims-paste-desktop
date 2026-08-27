import XCTest
@testable import PrimsPasteCore

final class FeaturesWantedTests: XCTestCase {
    func testListHasTheConversation() {
        let ids = FeaturesWanted.all.map(\.id)
        let need = [
            "durable", "touchid", "llc-sign", "stickies", "timestamps",
            "pastes", "key-detect", "voice-caption", "notes", "audio",
            "pictures", "big-tabs", "new-tab", "drag-tag", "drag-feel",
            "idle-cover", "local-ai", "low-mem", "no-capture",
            "calendar-drawer", "filter-dwmy", "view-layout", "view-timeline",
            "view-week", "view-month", "convert-to", "cli",
        ]
        for id in need {
            XCTAssertTrue(ids.contains(id), "missing \(id)")
        }
        XCTAssertEqual(FeaturesWanted.all.count, need.count)
    }

    func testStableIdsAndNoDuplicateStickies() {
        let ids = FeaturesWanted.all.map(\.stickyID)
        XCTAssertEqual(ids.count, Set(ids).count)
        XCTAssertTrue(FeaturesWanted.all.allSatisfy { $0.stickyID.hasPrefix("pp_fw_") })
    }

    func testTabIdentity() {
        XCTAssertEqual(FeaturesWanted.tabID, "tab_features-wanted")
        XCTAssertEqual(FeaturesWanted.tabTitle, "features-wanted")
    }

    func testTitlesAreTheList() {
        let titles = FeaturesWanted.all.map(\.title)
        XCTAssertTrue(titles.contains("Pictures and screenshots"))
        XCTAssertTrue(titles.contains("Drag onto a tab to tag"))
        XCTAssertTrue(titles.contains("Cover when idle"))
        XCTAssertTrue(titles.contains("Local chat with notes"))
        XCTAssertTrue(titles.contains("Big browser tabs"))
    }
}
