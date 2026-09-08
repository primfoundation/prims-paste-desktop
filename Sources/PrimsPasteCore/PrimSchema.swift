import Foundation

public struct PrimProblem: Equatable, Sendable {
    public let path: String
    public let rule: String
}

/// Explicit supported schema vocabulary. Unknown assertions fail at kit load;
/// passing these checks makes no factual, security, or authorization claim.
public enum PrimSchema {
    private static let supported: Set<String> = ["$schema", "$id", "title", "description", "default", "examples", "type", "const", "enum", "properties", "required", "additionalProperties", "items", "minItems", "maxItems", "minLength", "maxLength", "minimum", "maximum", "allOf", "anyOf", "oneOf", "not", "if", "then", "else"]

    public static func check(_ schema: PrimJSON) throws {
        if schema == .bool(true) || schema == .bool(false) { return }
        guard let o = schema.object, Set(o.keys).isSubset(of: supported) else {
            throw PrimLibraryError.invalid("This profile needs schema features this host does not support.")
        }
        if let t = o["type"] {
            let types = t.array ?? [t]
            guard !types.isEmpty, types.allSatisfy({ ["object", "array", "string", "number", "integer", "boolean", "null"].contains($0.string ?? "") }) else {
                throw PrimLibraryError.invalid("Invalid schema types.")
            }
        }
        for name in ["minItems", "maxItems", "minLength", "maxLength", "minimum", "maximum"] {
            if let n = o[name], n.number == nil { throw PrimLibraryError.invalid("Invalid schema limit.") }
        }
        if let required = o["required"], required.array == nil || required.array!.contains(where: { $0.string == nil }) {
            throw PrimLibraryError.invalid("Invalid required fields.")
        }
        if let properties = o["properties"] {
            guard let values = properties.object else { throw PrimLibraryError.invalid("Invalid schema properties.") }
            for s in values.values { try check(s) }
        }
        for name in ["items", "additionalProperties", "not", "if", "then", "else"] {
            if let s = o[name] { try check(s) }
        }
        for name in ["allOf", "anyOf", "oneOf"] {
            if let s = o[name] {
                guard let children = s.array, !children.isEmpty else { throw PrimLibraryError.invalid("Invalid schema alternatives.") }
                for child in children { try check(child) }
            }
        }
        if let values = o["enum"], values.array?.isEmpty != false { throw PrimLibraryError.invalid("Invalid schema choices.") }
    }

    public static func validate(_ record: PrimJSON, schema: PrimJSON) -> [PrimProblem] {
        var budget = 50_000
        return Array(walk(record, schema, "", &budget).prefix(100))
    }

    private static func walk(_ value: PrimJSON, _ schema: PrimJSON, _ path: String, _ budget: inout Int) -> [PrimProblem] {
        budget -= 1
        guard budget >= 0 else { return [PrimProblem(path: path, rule: "validation_budget")] }
        if schema == .bool(true) { return [] }
        if schema == .bool(false) { return [PrimProblem(path: path, rule: "false_schema")] }
        var errors: [PrimProblem] = []
        func fail(_ rule: String) { errors.append(PrimProblem(path: path, rule: rule)) }
        if let type = schema.object?["type"] {
            let types = (type.array ?? [type]).compactMap(\.string)
            let matches = types.contains { type in
                switch (type, value) {
                case ("object", .object), ("array", .array), ("string", .string), ("boolean", .bool), ("null", .null), ("number", .number): return true
                case ("integer", .number(let n)): return n.rounded() == n
                default: return false
                }
            }
            if !matches { fail("type"); return errors }
        }
        if let constant = schema.object?["const"], value != constant { fail("const") }
        if let values = schema["enum"].array, !values.contains(value) { fail("enum") }
        if let string = value.string {
            let count = Double(string.unicodeScalars.count)
            if let min = schema["minLength"].number, count < min { fail("minLength") }
            if let max = schema["maxLength"].number, count > max { fail("maxLength") }
        }
        if let n = value.number {
            if let min = schema["minimum"].number, n < min { fail("minimum") }
            if let max = schema["maximum"].number, n > max { fail("maximum") }
        }
        if let array = value.array {
            if let min = schema["minItems"].number, Double(array.count) < min { fail("minItems") }
            if let max = schema["maxItems"].number, Double(array.count) > max { fail("maxItems") }
            if let item = schema.object?["items"] {
                for (i, v) in array.enumerated() {
                    errors += walk(v, item, path + "/\(i)", &budget)
                    if errors.count >= 100 || budget < 0 { break }
                }
            }
        }
        if let object = value.object {
            for key in schema["required"].array?.compactMap(\.string) ?? [] {
                if object[key] == nil { errors.append(PrimProblem(path: path + "/" + pointer(key), rule: "required")) }
            }
            let properties = schema["properties"].object ?? [:]
            for key in object.keys.sorted() {
                if let child = properties[key] ?? schema.object?["additionalProperties"] {
                    errors += walk(object[key]!, child, path + "/" + pointer(key), &budget)
                }
                if errors.count >= 100 || budget < 0 { break }
            }
        }
        for child in schema["allOf"].array ?? [] {
            errors += walk(value, child, path, &budget)
            if errors.count >= 100 || budget < 0 { break }
        }
        for key in ["anyOf", "oneOf"] {
            if let children = schema[key].array {
                var passed = 0
                for child in children {
                    if walk(value, child, path, &budget).isEmpty { passed += 1 }
                    if budget < 0 { break }
                }
                if key == "anyOf" ? passed == 0 : passed != 1 { fail(key) }
            }
        }
        if let child = schema.object?["not"], walk(value, child, path, &budget).isEmpty { fail("not") }
        if let condition = schema.object?["if"] {
            let passed = walk(value, condition, path, &budget).isEmpty
            if let branch = schema.object?[passed ? "then" : "else"] { errors += walk(value, branch, path, &budget) }
        }
        if budget < 0 { fail("validation_budget") }
        return Array(errors.prefix(100))
    }

    private static func pointer(_ s: String) -> String { s.replacingOccurrences(of: "~", with: "~0").replacingOccurrences(of: "/", with: "~1") }
}
