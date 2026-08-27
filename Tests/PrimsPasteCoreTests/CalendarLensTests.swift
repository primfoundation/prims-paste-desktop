import XCTest
@testable import PrimsPasteCore

final class CalendarLensTests: XCTestCase {
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        c.firstWeekday = 2
        return c
    }()

    private func date(_ s: String) -> Date {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f.date(from: s)!
    }

    private func item(id: String, at s: String, x: Double = 9, y: Double = 9) -> ItemMeta {
        ItemMeta(
            id: id, kind: .note, x: x, y: y, width: 230, height: 230,
            createdAt: date(s), updatedAt: date(s), bytes: 1,
            caption: id, day: String(s.prefix(10)), tabID: "t"
        )
    }

    func testDayRange() {
        let r = CalendarLens.range(for: date("2026-08-27T15:00:00Z"), span: .day, calendar: cal)
        XCTAssertEqual(r.start, date("2026-08-27T00:00:00Z"))
        XCTAssertEqual(r.end, date("2026-08-28T00:00:00Z"))
    }

    func testWeekStartsMonday() {
        // 2026-08-27 is Thursday. Week is Mon 24 – Mon 31.
        let r = CalendarLens.range(for: date("2026-08-27T12:00:00Z"), span: .week, calendar: cal)
        XCTAssertEqual(r.start, date("2026-08-24T00:00:00Z"))
        XCTAssertEqual(r.end, date("2026-08-31T00:00:00Z"))
    }

    func testMonthAndYear() {
        let m = CalendarLens.range(for: date("2026-08-27T12:00:00Z"), span: .month, calendar: cal)
        XCTAssertEqual(m.start, date("2026-08-01T00:00:00Z"))
        XCTAssertEqual(m.end, date("2026-09-01T00:00:00Z"))
        let y = CalendarLens.range(for: date("2026-08-27T12:00:00Z"), span: .year, calendar: cal)
        XCTAssertEqual(y.start, date("2026-01-01T00:00:00Z"))
        XCTAssertEqual(y.end, date("2027-01-01T00:00:00Z"))
    }

    func testFilterDayExcludesOtherDays() {
        let items = [
            item(id: "a", at: "2026-08-27T10:00:00Z"),
            item(id: "b", at: "2026-08-26T10:00:00Z"),
        ]
        let hit = CalendarLens.filter(items, date: date("2026-08-27T12:00:00Z"), span: .day, calendar: cal)
        XCTAssertEqual(hit.map(\.id), ["a"])
        let all = CalendarLens.filter(items, date: date("2026-08-27T12:00:00Z"), span: nil, calendar: cal)
        XCTAssertEqual(all.count, 2)
    }

    func testLayoutKeepsUserCoordinates() {
        let items = [item(id: "a", at: "2026-08-27T10:00:00Z", x: 111, y: 222)]
        let p = CalendarLens.placed(
            items, mode: .layout, date: date("2026-08-27T12:00:00Z"),
            sticky: CGSize(width: 230, height: 230), calendar: cal
        )
        XCTAssertEqual(p["a"]?.x, 111)
        XCTAssertEqual(p["a"]?.y, 222)
    }

    func testTimelineGroupsByDay() {
        let items = [
            item(id: "a", at: "2026-08-26T10:00:00Z", x: 0, y: 0),
            item(id: "b", at: "2026-08-27T10:00:00Z", x: 0, y: 0),
            item(id: "c", at: "2026-08-27T11:00:00Z", x: 0, y: 0),
        ]
        let p = CalendarLens.placed(
            items, mode: .timeline, date: date("2026-08-27T12:00:00Z"),
            sticky: CGSize(width: 230, height: 230), calendar: cal
        )
        XCTAssertNotEqual(p["a"]?.x, p["b"]?.x)
        XCTAssertEqual(p["b"]?.x, p["c"]?.x)
        XCTAssertLessThan(p["b"]!.y, p["c"]!.y)
    }

    func testWeekPutsThursdayInColumn3() {
        // Mon=0 … Thu=3
        let items = [item(id: "t", at: "2026-08-27T10:00:00Z")]
        let p = CalendarLens.placed(
            items, mode: .week, date: date("2026-08-27T12:00:00Z"),
            sticky: CGSize(width: 230, height: 230), calendar: cal
        )
        XCTAssertEqual(p["t"]?.x, 24 + 3 * (230 + 24))
    }

    func testPersistOnlyInLayout() {
        XCTAssertTrue(CalendarLens.canPersistLayout(.layout))
        XCTAssertFalse(CalendarLens.canPersistLayout(.timeline))
        XCTAssertFalse(CalendarLens.canPersistLayout(.week))
        XCTAssertFalse(CalendarLens.canPersistLayout(.month))
        XCTAssertFalse(CalendarLens.canPersistLayout(.year))
    }
}
