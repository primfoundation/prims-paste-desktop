// Date filter (D/W/M/Y) and view placement. Layout mode keeps user x/y.
// Other modes ignore drag positions and space cards by createdAt.

import CoreGraphics
import Foundation

public enum DateSpan: String, CaseIterable, Sendable {
    case day, week, month, year
}

public enum BoardViewMode: String, CaseIterable, Sendable {
    case layout
    case timeline
    case week
    case month
    case year
}

public enum CalendarLens {
    public static func range(
        for date: Date,
        span: DateSpan,
        calendar: Calendar = .current
    ) -> (start: Date, end: Date) {
        var cal = calendar
        cal.timeZone = calendar.timeZone
        switch span {
        case .day:
            let s = cal.startOfDay(for: date)
            let e = cal.date(byAdding: .day, value: 1, to: s) ?? s
            return (s, e)
        case .week:
            let s = startOfWeek(date, calendar: cal)
            let e = cal.date(byAdding: .day, value: 7, to: s) ?? s
            return (s, e)
        case .month:
            let comps = cal.dateComponents([.year, .month], from: date)
            let s = cal.date(from: comps) ?? cal.startOfDay(for: date)
            let e = cal.date(byAdding: .month, value: 1, to: s) ?? s
            return (s, e)
        case .year:
            let comps = cal.dateComponents([.year], from: date)
            let s = cal.date(from: comps) ?? cal.startOfDay(for: date)
            let e = cal.date(byAdding: .year, value: 1, to: s) ?? s
            return (s, e)
        }
    }

    public static func startOfWeek(_ date: Date, calendar: Calendar = .current) -> Date {
        var cal = calendar
        cal.firstWeekday = 2 // Monday
        let start = cal.startOfDay(for: date)
        let weekday = cal.component(.weekday, from: start)
        var delta = weekday - cal.firstWeekday
        if delta < 0 { delta += 7 }
        return cal.date(byAdding: .day, value: -delta, to: start) ?? start
    }

    public static func matches(
        _ item: ItemMeta,
        date: Date,
        span: DateSpan,
        calendar: Calendar = .current
    ) -> Bool {
        let r = range(for: date, span: span, calendar: calendar)
        return item.createdAt >= r.start && item.createdAt < r.end
    }

    public static func filter(
        _ items: [ItemMeta],
        date: Date,
        span: DateSpan?,
        calendar: Calendar = .current
    ) -> [ItemMeta] {
        guard let span else { return items }
        return items.filter { matches($0, date: date, span: span, calendar: calendar) }
    }

    public static func placed(
        _ items: [ItemMeta],
        mode: BoardViewMode,
        date: Date,
        sticky: CGSize,
        calendar: Calendar = .current
    ) -> [String: CGPoint] {
        switch mode {
        case .layout:
            return Dictionary(uniqueKeysWithValues: items.map {
                ($0.id, CGPoint(x: $0.x, y: $0.y))
            })
        case .timeline:
            return timeline(items, sticky: sticky, calendar: calendar)
        case .week:
            return week(items, date: date, sticky: sticky, calendar: calendar)
        case .month:
            return month(items, date: date, sticky: sticky, calendar: calendar)
        case .year:
            return year(items, date: date, sticky: sticky, calendar: calendar)
        }
    }

    public static func canPersistLayout(_ mode: BoardViewMode) -> Bool {
        mode == .layout
    }

    private static func timeline(
        _ items: [ItemMeta],
        sticky: CGSize,
        calendar: Calendar
    ) -> [String: CGPoint] {
        let grouped = Dictionary(grouping: items) { ItemMeta.dayString(from: $0.createdAt, calendar: calendar) }
        let days = grouped.keys.sorted()
        var out: [String: CGPoint] = [:]
        let colW = sticky.width + 28
        let rowH = sticky.height + 20
        for (di, day) in days.enumerated() {
            let stack = (grouped[day] ?? []).sorted { $0.createdAt < $1.createdAt }
            for (i, item) in stack.enumerated() {
                out[item.id] = CGPoint(x: 40 + Double(di) * colW, y: 40 + Double(i) * rowH)
            }
        }
        return out
    }

    private static func week(
        _ items: [ItemMeta],
        date: Date,
        sticky: CGSize,
        calendar: Calendar
    ) -> [String: CGPoint] {
        let start = startOfWeek(date, calendar: calendar)
        let colW = sticky.width + 24
        let rowH = sticky.height + 16
        var stacks = Array(repeating: 0, count: 7)
        var out: [String: CGPoint] = [:]
        for item in items.sorted(by: { $0.createdAt < $1.createdAt }) {
            let dayStart = calendar.startOfDay(for: item.createdAt)
            let diff = calendar.dateComponents([.day], from: start, to: dayStart).day ?? 0
            let col = min(max(diff, 0), 6)
            let row = stacks[col]
            stacks[col] += 1
            out[item.id] = CGPoint(x: 24 + Double(col) * colW, y: 56 + Double(row) * rowH)
        }
        return out
    }

    private static func month(
        _ items: [ItemMeta],
        date: Date,
        sticky: CGSize,
        calendar: Calendar
    ) -> [String: CGPoint] {
        let comps = calendar.dateComponents([.year, .month], from: date)
        let first = calendar.date(from: comps) ?? date
        let startPad = {
            let wd = calendar.component(.weekday, from: first)
            var d = wd - 2
            if d < 0 { d += 7 }
            return d
        }()
        let colW = max(sticky.width * 0.55, 140) + 12
        let rowH = max(sticky.height * 0.55, 120) + 12
        var perDay: [Int: Int] = [:]
        var out: [String: CGPoint] = [:]
        for item in items.sorted(by: { $0.createdAt < $1.createdAt }) {
            let day = calendar.component(.day, from: item.createdAt)
            let slot = startPad + day - 1
            let col = slot % 7
            let row = slot / 7
            let n = perDay[day, default: 0]
            perDay[day] = n + 1
            out[item.id] = CGPoint(
                x: 16 + Double(col) * colW + Double(n) * 8,
                y: 48 + Double(row) * rowH + Double(n) * 8
            )
        }
        return out
    }

    private static func year(
        _ items: [ItemMeta],
        date: Date,
        sticky: CGSize,
        calendar: Calendar
    ) -> [String: CGPoint] {
        let colW = sticky.width + 20
        let rowH = sticky.height + 20
        var perMonth = Array(repeating: 0, count: 12)
        var out: [String: CGPoint] = [:]
        for item in items.sorted(by: { $0.createdAt < $1.createdAt }) {
            let m = calendar.component(.month, from: item.createdAt) - 1
            let n = perMonth[m]
            perMonth[m] = n + 1
            let col = m % 4
            let row = m / 4
            out[item.id] = CGPoint(
                x: 24 + Double(col) * (colW + 40) + Double(n) * 6,
                y: 48 + Double(row) * (rowH + 48) + Double(n) * 6
            )
        }
        return out
    }
}
