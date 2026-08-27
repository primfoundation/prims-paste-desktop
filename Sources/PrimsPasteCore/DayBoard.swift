// Stickies live on a calendar day. Not a company, not a project.

import Foundation

public enum DayBoard {
    public static func days(from items: [ItemMeta], today: String) -> [String] {
        var set = Set(items.map(\.day))
        set.insert(today)
        return set.sorted(by: >)
    }

    public static func visible(_ items: [ItemMeta], day: String) -> [ItemMeta] {
        items.filter { $0.day == day }
    }

    public static func hasKey(_ items: [ItemMeta], day: String) -> Bool {
        visible(items, day: day).contains(where: \.looksLikeKey)
    }

    /// Cover the board after a key lands. Uncovering a day that still
    /// holds a key requires a real unlock; uncovering a prose-only day does not.
    public static func shutterAfterPaste(isKey: Bool) -> Bool { isKey }

    /// Fingerprint is only at app open. Cover/uncover is not an auth gate.
    public static func uncoverRequiresAuth(dayHasKey: Bool) -> Bool {
        _ = dayHasKey
        return false
    }

    public static func title(for day: String, today: String, calendar: Calendar = .current) -> String {
        if day == today { return "today" }
        guard let date = parse(day, calendar: calendar) else { return day }
        if let y = calendar.date(byAdding: .day, value: -1, to: Date()),
           day == ItemMeta.dayString(from: y, calendar: calendar) {
            return "yesterday"
        }
        let f = DateFormatter()
        f.calendar = calendar
        f.dateFormat = "EEE d MMM"
        return f.string(from: date)
    }

    public static func parse(_ day: String, calendar: Calendar = .current) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var c = DateComponents()
        c.year = parts[0]
        c.month = parts[1]
        c.day = parts[2]
        return calendar.date(from: c)
    }
}
