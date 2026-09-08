import CryptoKit
import Foundation

public struct PrimDefinitionPin: Codable, Equatable, Hashable, Sendable {
    public let profileID: String
    public let version: String
    public let definitionSHA256: String
    public init(profileID: String, version: String, definitionSHA256: String) {
        self.profileID = profileID; self.version = version; self.definitionSHA256 = definitionSHA256
    }
    enum CodingKeys: String, CodingKey {
        case profileID = "profile_id", version, definitionSHA256 = "definition_sha256"
    }
}

public struct PrimKit: Identifiable, Sendable {
    public let pin: PrimDefinitionPin
    public let name: String
    public let authorityFile: String
    public let identityField: String
    public let titleField: String
    public let schema: PrimJSON
    public let template: PrimJSON
    public let rules: PrimJSON
    public var id: String { pin.profileID + "@" + pin.version }

    init(_ value: PrimJSON) throws {
        guard let profileID = value["profile_id"].string, let version = value["version"].string,
              let hash = value["definition_sha256"].string,
              profileID.range(of: "^[a-z][a-z0-9-]{0,63}/[a-z][a-z0-9-]{0,63}\\z", options: .regularExpression) != nil,
              hash.range(of: "^[0-9a-f]{64}\\z", options: .regularExpression) != nil,
              let file = value["authority_file"].string,
              file.range(of: "^[a-z][a-z0-9-]*\\.json\\z", options: .regularExpression) != nil,
              let identity = value["identity_field"].string, let title = value["title_field"].string,
              value["template"].object != nil else { throw PrimLibraryError.invalid("Invalid creation kit.") }
        pin = PrimDefinitionPin(profileID: profileID, version: version, definitionSHA256: hash)
        name = value["name"].string ?? profileID
        authorityFile = file; identityField = identity; titleField = title
        schema = value["schema"]; template = value["template"]; rules = value["rules"]
        try PrimSchema.check(schema)
        let supported: Set<String> = ["unique_ids", "token_fields", "root_references", "references", "required_links"]
        guard let ruleObject = rules.object, Set(ruleObject.keys).isSubset(of: supported) else {
            throw PrimLibraryError.invalid("This profile needs reference rules this host does not support.")
        }
        for (key, entry) in ruleObject {
            guard let entries = entry.array else { throw PrimLibraryError.invalid("Invalid reference rules.") }
            for rule in entries {
                if ["unique_ids", "token_fields"].contains(key) {
                    guard rule.string != nil else { throw PrimLibraryError.invalid("Invalid field rule.") }
                } else {
                    let fields = key == "root_references" ? ["field", "target"] : key == "references" ? ["collection", "field", "target"] : ["collection", "when_field", "when_value", "links", "reference_field", "relation"]
                    guard let o = rule.object, Set(o.keys) == Set(fields), fields.allSatisfy({ o[$0]?.string != nil }) else {
                        throw PrimLibraryError.invalid("Invalid link rule.")
                    }
                }
            }
        }
        _ = try draft(title: nil)
    }

    public func draft(title: String?) throws -> PrimJSON {
        var record = template.object!
        record[identityField] = .string("prim-" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())
        if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { record[titleField] = .string(title) }
        let result = PrimJSON.object(record)
        try requireValid(result)
        return result
    }

    public func validate(_ record: PrimJSON) -> [PrimProblem] {
        var errors = PrimSchema.validate(record, schema: schema)
        guard errors.isEmpty, record.object != nil else { return errors }
        func fail(_ path: String, _ rule: String) { errors.append(PrimProblem(path: path, rule: rule)) }
        func rows(_ field: String) -> [PrimJSON] { record[field].array ?? [] }
        func ids(_ field: String) -> Set<PrimJSONID> { Set(rows(field).compactMap { $0["id"].string.map(PrimJSONID.init) }) }
        for field in rules["unique_ids"].array?.compactMap(\.string) ?? [] {
            if ids(field).count != rows(field).count { fail(field, "duplicate_id") }
        }
        for field in rules["token_fields"].array?.compactMap(\.string) ?? [] {
            if record[field].string?.range(of: "^[a-z][a-z0-9.-]*\\z", options: .regularExpression) == nil { fail(field, "invalid_token") }
        }
        for rule in rules["root_references"].array ?? [] {
            let field = rule["field"].string!; let ref = record[field]
            if ref != .null, !ids(rule["target"].string!).contains(PrimJSONID(ref.string ?? "")) { fail(field, "unresolved_reference") }
        }
        for rule in rules["references"].array ?? [] {
            let field = rule["field"].string!; let collection = rule["collection"].string!
            let targets = ids(rule["target"].string!)
            for (i, row) in rows(collection).enumerated() {
                if row[field] != .null, !targets.contains(PrimJSONID(row[field].string ?? "")) { fail("\(collection)/\(i)/\(field)", "unresolved_reference") }
            }
        }
        for rule in rules["required_links"].array ?? [] {
            let collection = rule["collection"].string!
            for (i, row) in rows(collection).enumerated() {
                if row[rule["when_field"].string!] == rule["when_value"], !rows(rule["links"].string!).contains(where: {
                    $0[rule["reference_field"].string!] == row["id"] && $0["relation"] == rule["relation"]
                }) { fail("\(collection)/\(i)", "missing_declared_support") }
            }
        }
        return Array(errors.prefix(100))
    }

    public func requireValid(_ record: PrimJSON) throws {
        _ = try record.encoded()
        let problems = validate(record)
        guard problems.isEmpty else {
            // Paths and rule names only. Never include the private values.
            throw PrimLibraryError.invalid(problems.prefix(8).map { "\($0.path): \($0.rule)" }.joined(separator: "\n"))
        }
    }
}

private struct PrimJSONID: Hashable { let value: String; init(_ value: String) { self.value = value } }

public struct PrimLibrary: Sendable {
    public let kits: [PrimKit]
    public let sourceCommit: String
    public let catalogSHA256: String

    public init(data: Data, expectedSHA256: String) throws {
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == expectedSHA256 else { throw PrimLibraryError.invalid("Library checksum mismatch.") }
        let catalog = try PrimJSON.parse(data, maximum: 8 * 1024 * 1024)
        guard catalog["format"] == .string("prim-host-catalog"), catalog["version"] == .number(1),
              let entries = catalog["kits"].array, !entries.isEmpty else { throw PrimLibraryError.invalid("Unsupported host catalog.") }
        sourceCommit = catalog["source_commit"].string ?? "unrecorded"
        catalogSHA256 = digest
        var output: [PrimKit] = []; var identities = Set<String>()
        for entry in entries {
            let kit = try PrimKit(entry)
            guard identities.insert(kit.id).inserted else { throw PrimLibraryError.invalid("Duplicate profile version.") }
            output.append(kit)
        }
        kits = output.sorted { $0.name < $1.name }
    }

    public static func bundled() throws -> PrimLibrary {
        guard let data = Data(base64Encoded: PrimLibraryBundled.base64) else { throw PrimLibraryError.invalid("Bundled library is unreadable.") }
        return try PrimLibrary(data: data, expectedSHA256: PrimLibraryBundled.sha256)
    }

    public func kit(for pin: PrimDefinitionPin) throws -> PrimKit {
        guard let kit = kits.first(where: { $0.pin == pin }) else {
            throw PrimLibraryError.invalid("The exact pinned definition is unavailable. The record has been preserved; no upgrade was applied.")
        }
        return kit
    }
}
