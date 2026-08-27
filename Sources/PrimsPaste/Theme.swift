import SwiftUI
import PrimsPasteCore

/// prim.brand paper palette (`tokens/dtcg.json`). Do not invent hex.
enum Ink {
    static let board = Color(hex: "#f4f3ef")
    static let surface = Color(hex: "#e8e7e3")
    static let raised = Color(hex: "#fafaf8")
    static let ink = Color(hex: "#0c0c0e")
    static let mute = Color(hex: "#6a6a66")
    static let subtle = Color(hex: "#9a9a96")
    static let line = Color(hex: "#d4d3cf")
    static let accent = Color(hex: "#e8c547")
    static let accentInk = Color(hex: "#0c0c0e")
    static let inkBg = Color(hex: "#0c0c0e")
    static let cream = Color(hex: "#f4f3ef")

    static let bar = raised
    static let grid = line
    static let tabOn = ink
    /// Functional, not a brand token — keys are not Prim gold.
    static let keyTape = Color(red: 0.72, green: 0.18, blue: 0.14)
    static let listen = accent
    static let radius: CGFloat = 2

    static let display = Font.custom("Instrument Sans", size: 32).weight(.semibold)
    static let title = Font.custom("Instrument Sans", size: 18).weight(.medium)
    static let serif = title
    static let body = Font.custom("Instrument Sans", size: 15)
    static let tab = Font.custom("Instrument Sans", size: 17).weight(.medium)
    static let mono = Font.custom("IBM Plex Mono", size: 11)
    static let small = Font.custom("IBM Plex Mono", size: 10)

    /// Quiet paper chips — still stickies, sitting on Prim paper.
    static let papers: [Color] = [
        Color(hex: "#efe6c4"),
        Color(hex: "#dce6d2"),
        Color(hex: "#ead9d4"),
        Color(hex: "#d9e1e6"),
        Color(hex: "#eadcc0"),
        Color(hex: "#e4dce6"),
    ]

    static func paper(for item: ItemMeta) -> Color {
        if item.looksLikeKey {
            return Color(hex: "#e6d48a")
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
