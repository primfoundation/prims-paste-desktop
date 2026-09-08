import Foundation

/// Bounded JSON data, never executable profile instructions.
public indirect enum PrimJSON: Codable, Equatable, Sendable {
    case object([String: PrimJSON]), array([PrimJSON]), string(String), number(Double), bool(Bool), null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([String: PrimJSON].self) { self = .object(v) }
        else if let v = try? c.decode([PrimJSON].self) { self = .array(v) }
        else { self = .number(try c.decode(Double.self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }

    public var object: [String: PrimJSON]? { if case .object(let v) = self { return v }; return nil }
    public var array: [PrimJSON]? { if case .array(let v) = self { return v }; return nil }
    public var string: String? { if case .string(let v) = self { return v }; return nil }
    public var number: Double? { if case .number(let v) = self { return v }; return nil }
    public subscript(_ key: String) -> PrimJSON { object?[key] ?? .null }

    public func encoded() throws -> Data {
        try bounded()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(self)
        guard data.count <= 512 * 1024 else { throw PrimLibraryError.invalid("Record exceeds 512 KiB.") }
        return data
    }

    public static func parse(_ data: Data, maximum: Int = 512 * 1024) throws -> PrimJSON {
        guard data.count <= maximum else { throw PrimLibraryError.invalid("JSON size limit exceeded.") }
        // JSONDecoder collapses duplicate keys. Check decoded key spelling before decoding.
        // The decoder remains responsible for full JSON syntax validation.
        struct Frame { var keys: Set<String>?; var expectingKey: Bool }
        let bytes = Array(data); var frames: [Frame] = []; var i = 0
        while i < bytes.count {
            switch bytes[i] {
            case 123, 91:
                frames.append(Frame(keys: bytes[i] == 123 ? [] : nil, expectingKey: bytes[i] == 123))
                guard frames.count <= 24 else { throw PrimLibraryError.invalid("JSON nesting limit exceeded.") }
            case 125, 93:
                guard !frames.isEmpty else { throw PrimLibraryError.invalid("Invalid JSON.") }
                frames.removeLast()
            case 44:
                if !frames.isEmpty, frames[frames.count - 1].keys != nil { frames[frames.count - 1].expectingKey = true }
            case 34:
                let start = i; i += 1
                while i < bytes.count {
                    if bytes[i] == 92 { i += 2; continue }
                    if bytes[i] == 34 { break }
                    i += 1
                }
                guard i < bytes.count else { throw PrimLibraryError.invalid("Invalid JSON string.") }
                if !frames.isEmpty, frames[frames.count - 1].expectingKey {
                    let key = try JSONDecoder().decode(String.self, from: Data(bytes[start...i]))
                    guard frames[frames.count - 1].keys!.insert(key).inserted else {
                        throw PrimLibraryError.invalid("Duplicate JSON field.")
                    }
                    frames[frames.count - 1].expectingKey = false
                }
            default: break
            }
            i += 1
        }
        let value = try JSONDecoder().decode(PrimJSON.self, from: data)
        try value.bounded()
        return value
    }

    func bounded(_ depth: Int = 0) throws {
        guard depth <= 24 else { throw PrimLibraryError.invalid("JSON nesting limit exceeded.") }
        switch self {
        case .object(let v):
            guard v.count <= 2048 else { throw PrimLibraryError.invalid("Too many fields.") }
            for child in v.values { try child.bounded(depth + 1) }
        case .array(let v):
            guard v.count <= 2048 else { throw PrimLibraryError.invalid("Too many entries.") }
            for child in v { try child.bounded(depth + 1) }
        case .number(let v):
            guard v.isFinite, abs(v) <= 9_007_199_254_740_991 else {
                throw PrimLibraryError.invalid("Number exceeds the host's exact integer range.")
            }
        default: break
        }
    }
}

public enum PrimLibraryError: Error, LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case .invalid(let text) = self { return text }; return nil }
}
