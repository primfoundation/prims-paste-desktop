// Convert a sticky into something else (docket task, paseo agent, …).
// The payload is never copied into the link. Caption/title only.
// Real create is not wired yet — we store the intent and a local ref.

import Foundation

public enum ConvertTarget: String, Codable, CaseIterable, Sendable, Identifiable {
    case docketTask = "docket"
    case paseoAgent = "paseo"
    case note = "note"

    public var id: String { rawValue }

    public var menuLabel: String {
        switch self {
        case .docketTask: return "Docket task"
        case .paseoAgent: return "Paseo agent"
        case .note: return "Note"
        }
    }

    public var badge: String {
        switch self {
        case .docketTask: return "DOCKET"
        case .paseoAgent: return "PASEO"
        case .note: return "NOTE"
        }
    }
}

public struct Conversion: Codable, Equatable, Sendable {
    public var target: ConvertTarget
    public var ref: String
    public var title: String
    public var createdAt: Date

    public init(target: ConvertTarget, ref: String, title: String, createdAt: Date = Date()) {
        self.target = target
        self.ref = ref
        self.title = title
        self.createdAt = createdAt
    }
}

public enum Convert {
    public static func usesPayload() -> Bool { false }

    public static func title(from caption: String, target: ConvertTarget) -> String {
        let t = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? target.menuLabel : t
    }

    public static func docketID(from ref: String) -> String? {
        guard let hash = ref.split(separator: "#").last else { return nil }
        let id = String(hash)
        return id.hasPrefix("TASK-") ? id : nil
    }

    public static func docketNotes(title: String) -> String {
        """
        Converted from a Prims Paste sticky titled '\(title)'. This docket card is the working record for that sticky. Expand the brief here before treating the work as planned. The sticky keeps a link back to this card and does not copy secret payloads into the pack.
        """
    }
}

public protocol ConvertRunning: Sendable {
    func convert(target: ConvertTarget, stickyID: String, caption: String) throws -> Conversion
}
