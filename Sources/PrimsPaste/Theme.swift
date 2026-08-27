import SwiftUI
import PrimsPasteCore

enum Ink {
    static let board = Color(red: 0.89, green: 0.88, blue: 0.84)
    static let grid = Color(red: 0.62, green: 0.60, blue: 0.56).opacity(0.45)
    static let bar = Color(red: 0.97, green: 0.97, blue: 0.95)
    static let ink = Color(red: 0.18, green: 0.16, blue: 0.12)
    static let mute = Color(red: 0.45, green: 0.42, blue: 0.36)
    static let tabOn = Color(red: 0.16, green: 0.15, blue: 0.12)
    static let keyTape = Color(red: 0.72, green: 0.18, blue: 0.14)
    static let listen = Color(red: 0.82, green: 0.22, blue: 0.18)

    static let serif = Font.system(.title3, design: .serif)
    static let body = Font.system(size: 15, weight: .regular, design: .serif)
    static let mono = Font.system(size: 11, weight: .medium, design: .monospaced)
    static let small = Font.system(size: 10, weight: .regular, design: .monospaced)

    static let papers: [Color] = [
        Color(red: 0.99, green: 0.93, blue: 0.52),
        Color(red: 0.79, green: 0.93, blue: 0.72),
        Color(red: 0.99, green: 0.78, blue: 0.72),
        Color(red: 0.72, green: 0.86, blue: 0.96),
        Color(red: 0.98, green: 0.84, blue: 0.62),
        Color(red: 0.90, green: 0.80, blue: 0.96),
    ]

    static func paper(for item: ItemMeta) -> Color {
        if item.looksLikeKey {
            return Color(red: 0.98, green: 0.86, blue: 0.52)
        }
        let h = item.id.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return papers[abs(h) % papers.count]
    }
}

enum BoardMetrics {
    static let width: CGFloat = 4800
    static let height: CGFloat = 3200
    static let stickySize = CGSize(width: 230, height: 230)
    static let audioSize = CGSize(width: 230, height: 150)
}

func stamp(_ date: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "HH:mm"
    return f.string(from: date)
}
