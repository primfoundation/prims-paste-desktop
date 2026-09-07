import Foundation
import XCTest
@testable import PrimsPasteCore

final class StartupPolicyTests: XCTestCase {
    func testDeveloperSeedsAreOffByDefault() {
        XCTAssertFalse(StartupPolicy.developerSeedsEnabled(environment: [:]))
        XCTAssertFalse(StartupPolicy.developerSeedsEnabled(environment: ["PRIMBOARD_DEVELOPER_SEEDS": "0"]))
        XCTAssertFalse(StartupPolicy.developerSeedsEnabled(environment: ["PRIMBOARD_DEVELOPER_SEEDS": "true"]))
        XCTAssertTrue(StartupPolicy.developerSeedsEnabled(environment: ["PRIMBOARD_DEVELOPER_SEEDS": "1"]))
    }

    func testStartupPrefersTodayWithoutDeletingHistoricalTabs() {
        let now = Date(timeIntervalSince1970: 0)
        let tabs = [
            BoardTab(id: FeaturesWanted.tabID, title: "features-wanted", colorHex: "#C45C26", createdAt: now),
            BoardTab(id: "2026-09-07", title: "today", colorHex: "#3D3A36", createdAt: now),
            BoardTab(id: "custom", title: "custom", colorHex: "#000000", createdAt: now),
        ]
        XCTAssertEqual(StartupPolicy.initialTabID(tabs, today: "2026-09-07"), "2026-09-07")
        XCTAssertEqual(tabs.count, 3)
        XCTAssertTrue(tabs.contains(where: { $0.id == FeaturesWanted.tabID }))
    }

    func testStartupFallsBackToExistingTabThenTodayForEmptyNotebook() {
        let now = Date(timeIntervalSince1970: 0)
        let custom = BoardTab(id: "custom", title: "custom", colorHex: "#000000", createdAt: now)
        XCTAssertEqual(StartupPolicy.initialTabID([custom], today: "2026-09-07"), "custom")
        XCTAssertEqual(StartupPolicy.initialTabID([], today: "2026-09-07"), "2026-09-07")
    }
}
