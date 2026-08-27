import XCTest
@testable import PrimsPasteCore

final class DayBoardTests: XCTestCase {
    private func item(id: String, day: String, key: Bool = false) -> ItemMeta {
        ItemMeta(
            id: id,
            kind: .paste,
            x: 0, y: 0, width: 10, height: 10,
            createdAt: Date(),
            updatedAt: Date(),
            bytes: 4,
            caption: "c",
            looksLikeKey: key,
            day: day
        )
    }

    func testTodayAlwaysPresentEvenIfEmpty() {
        XCTAssertEqual(DayBoard.days(from: [], today: "2026-08-27"), ["2026-08-27"])
    }

    func testDaysSortedNewestFirstAndIncludeToday() {
        let items = [
            item(id: "a", day: "2026-08-20"),
            item(id: "b", day: "2026-08-25"),
        ]
        XCTAssertEqual(
            DayBoard.days(from: items, today: "2026-08-27"),
            ["2026-08-27", "2026-08-25", "2026-08-20"]
        )
    }

    func testVisibleFiltersByDayNotByAnythingElse() {
        let items = [
            item(id: "a", day: "2026-08-27"),
            item(id: "b", day: "2026-08-26"),
            item(id: "c", day: "2026-08-27"),
        ]
        let vis = DayBoard.visible(items, day: "2026-08-27")
        XCTAssertEqual(vis.map(\.id), ["a", "c"])
    }

    func testCompanyIsNotAGroupingAxis() {
        // There is no company field. Two stickies the same day stay together
        // even if captions mention different companies.
        let a = ItemMeta(
            id: "1", kind: .note, x: 0, y: 0, width: 1, height: 1,
            createdAt: Date(), updatedAt: Date(), bytes: 1,
            caption: "Greenmark haul", day: "2026-08-27"
        )
        let b = ItemMeta(
            id: "2", kind: .note, x: 10, y: 10, width: 1, height: 1,
            createdAt: Date(), updatedAt: Date(), bytes: 1,
            caption: "Jetta invoice", day: "2026-08-27"
        )
        XCTAssertEqual(DayBoard.visible([a, b], day: "2026-08-27").count, 2)
        XCTAssertTrue(DayBoard.visible([a, b], day: "2026-08-26").isEmpty)
    }

    func testHasKeyOnlyLooksAtThatDay() {
        let items = [
            item(id: "k", day: "2026-08-26", key: true),
            item(id: "n", day: "2026-08-27", key: false),
        ]
        XCTAssertFalse(DayBoard.hasKey(items, day: "2026-08-27"))
        XCTAssertTrue(DayBoard.hasKey(items, day: "2026-08-26"))
    }

    func testShutterAfterPasteOnlyForKeys() {
        XCTAssertTrue(DayBoard.shutterAfterPaste(isKey: true))
        XCTAssertFalse(DayBoard.shutterAfterPaste(isKey: false))
    }

    func testUncoverNeverAsksFingerprint() {
        XCTAssertFalse(DayBoard.uncoverRequiresAuth(dayHasKey: true))
        XCTAssertFalse(DayBoard.uncoverRequiresAuth(dayHasKey: false))
    }

    func testTodayTitle() {
        XCTAssertEqual(DayBoard.title(for: "2026-08-27", today: "2026-08-27"), "today")
    }

    func testParseDay() {
        let d = DayBoard.parse("2026-08-27")
        XCTAssertNotNil(d)
        XCTAssertEqual(ItemMeta.dayString(from: d!), "2026-08-27")
    }

    func testBadDayParse() {
        XCTAssertNil(DayBoard.parse("nope"))
        XCTAssertNil(DayBoard.parse(""))
    }
}
