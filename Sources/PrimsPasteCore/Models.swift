// Durable notebook items. Metadata only — never the payload.
// Stickies (pp_*) live in ~/.prims-paste/notebook/.

import Foundation

public enum NotebookLayout {
    public static let sticky: Double = 230
}

public enum ItemKind: String, Codable, CaseIterable, Sendable {
    case paste
    case note
    case audio
    case image
}

public struct BoardTab: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var colorHex: String
    public var createdAt: Date

    public init(id: String, title: String, colorHex: String, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.colorHex = colorHex
        self.createdAt = createdAt
    }

    public static func todayTab(calendar: Calendar = .current) -> BoardTab {
        let day = ItemMeta.today(calendar: calendar)
        return BoardTab(id: day, title: "today", colorHex: "#3D3A36")
    }
}

public struct ItemMeta: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var kind: ItemKind
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var createdAt: Date
    public var updatedAt: Date
    public var bytes: Int
    public var fingerprint: String?
    /// Spoken / typed caption. Metadata only — never the payload.
    public var caption: String
    public var looksLikeKey: Bool
    public var keyKind: String?
    /// Local calendar day `YYYY-MM-DD`. Kept so old files still load.
    public var day: String
    /// Tab this sticky belongs to. Drag onto a tab to set this.
    public var tabID: String
    /// Paint order. Higher sits on top. Bumped when the card is dragged.
    public var z: Int
    /// If set, this sticky is also a docket task / paseo agent / …
    public var conversion: Conversion?

    public init(
        id: String,
        kind: ItemKind,
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        createdAt: Date,
        updatedAt: Date,
        bytes: Int,
        fingerprint: String? = nil,
        caption: String = "",
        looksLikeKey: Bool = false,
        keyKind: String? = nil,
        day: String? = nil,
        tabID: String? = nil,
        z: Int = 0,
        conversion: Conversion? = nil
    ) {
        self.id = id
        self.kind = kind
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.bytes = bytes
        self.fingerprint = fingerprint
        self.caption = caption
        self.looksLikeKey = looksLikeKey
        self.keyKind = keyKind
        let d = day ?? Self.dayString(from: createdAt)
        self.day = d
        self.tabID = tabID ?? d
        self.z = z
        self.conversion = conversion
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = try c.decode(ItemKind.self, forKey: .kind)
        x = try c.decode(Double.self, forKey: .x)
        y = try c.decode(Double.self, forKey: .y)
        width = try c.decode(Double.self, forKey: .width)
        height = try c.decode(Double.self, forKey: .height)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        bytes = try c.decode(Int.self, forKey: .bytes)
        fingerprint = try c.decodeIfPresent(String.self, forKey: .fingerprint)
        caption = try c.decodeIfPresent(String.self, forKey: .caption)
            ?? c.decodeIfPresent(String.self, forKey: .description)
            ?? ""
        looksLikeKey = try c.decodeIfPresent(Bool.self, forKey: .looksLikeKey) ?? false
        keyKind = try c.decodeIfPresent(String.self, forKey: .keyKind)
        day = try c.decodeIfPresent(String.self, forKey: .day) ?? Self.dayString(from: createdAt)
        tabID = try c.decodeIfPresent(String.self, forKey: .tabID) ?? day
        z = try c.decodeIfPresent(Int.self, forKey: .z) ?? 0
        conversion = try c.decodeIfPresent(Conversion.self, forKey: .conversion)
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, x, y, width, height, createdAt, updatedAt, bytes, fingerprint
        case caption, description, looksLikeKey, keyKind, day, tabID, z, conversion
    }

    public static func dayString(from date: Date, calendar: Calendar = .current) -> String {
        let p = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", p.year ?? 0, p.month ?? 0, p.day ?? 0)
    }

    public static func today(calendar: Calendar = .current) -> String {
        dayString(from: Date(), calendar: calendar)
    }

    public var tilt: Double {
        let h = abs(id.unicodeScalars.reduce(0) { $0 &+ Int($1.value) })
        return Double(h % 9) - 4
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encode(x, forKey: .x)
        try c.encode(y, forKey: .y)
        try c.encode(width, forKey: .width)
        try c.encode(height, forKey: .height)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(bytes, forKey: .bytes)
        try c.encodeIfPresent(fingerprint, forKey: .fingerprint)
        try c.encode(caption, forKey: .caption)
        try c.encode(looksLikeKey, forKey: .looksLikeKey)
        try c.encodeIfPresent(keyKind, forKey: .keyKind)
        try c.encode(day, forKey: .day)
        try c.encode(tabID, forKey: .tabID)
        try c.encode(z, forKey: .z)
        try c.encodeIfPresent(conversion, forKey: .conversion)
    }
}

public struct NotebookIndex: Codable, Equatable, Sendable {
    public var version: Int
    public var items: [ItemMeta]
    public var tabs: [BoardTab]
    public var chat: ChatSettings
    public var seededFeaturesWanted: Bool

    public init(
        version: Int = 2,
        items: [ItemMeta] = [],
        tabs: [BoardTab] = [],
        chat: ChatSettings = .none,
        seededFeaturesWanted: Bool = false
    ) {
        self.version = version
        self.items = items
        self.tabs = tabs
        self.chat = chat
        self.seededFeaturesWanted = seededFeaturesWanted
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        items = try c.decodeIfPresent([ItemMeta].self, forKey: .items) ?? []
        tabs = try c.decodeIfPresent([BoardTab].self, forKey: .tabs) ?? []
        chat = try c.decodeIfPresent(ChatSettings.self, forKey: .chat) ?? .none
        seededFeaturesWanted = try c.decodeIfPresent(Bool.self, forKey: .seededFeaturesWanted) ?? false
        if tabs.isEmpty {
            tabs = Self.tabsFromDays(items)
        }
        for i in items.indices where items[i].tabID.isEmpty {
            items[i].tabID = items[i].day
        }
    }

    enum CodingKeys: String, CodingKey {
        case version, items, tabs, chat, seededFeaturesWanted
    }

    public static func tabsFromDays(_ items: [ItemMeta]) -> [BoardTab] {
        var seen = Set<String>()
        var out: [BoardTab] = []
        let today = ItemMeta.today()
        if !seen.contains(today) {
            seen.insert(today)
            out.append(.todayTab())
        }
        for it in items {
            if seen.insert(it.tabID.isEmpty ? it.day : it.tabID).inserted {
                let id = it.tabID.isEmpty ? it.day : it.tabID
                out.append(BoardTab(id: id, title: id == today ? "today" : id, colorHex: "#6B645C"))
            }
        }
        return out
    }
}

public enum NotebookError: Error, Equatable, CustomStringConvertible {
    case badMagic
    case missingBlob(String)
    case indexCorrupt
    case keychain(String)
    case emptyPayload
    case convert(String)

    public var description: String {
        switch self {
        case .badMagic: return "blob is not a Prims Paste sealed box"
        case .missingBlob(let id): return "missing blob for \(id)"
        case .indexCorrupt: return "notebook index is corrupt"
        case .keychain(let s): return "keychain: \(s)"
        case .emptyPayload: return "empty payload"
        case .convert(let s): return s
        }
    }
}

public enum Paths {
    public static var home: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".prims-paste")
    }

    public static var defaultRoot: URL {
        home.appendingPathComponent("notebook")
    }

    public static var docketPack: URL {
        home.appendingPathComponent("docket")
    }
}
