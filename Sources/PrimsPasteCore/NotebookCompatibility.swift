import Foundation

/// Codable drops unrecognized fields. Refuse an upgrade that cannot retain them.
/// This is a compatibility boundary, not a repair or a lossy migration.
enum NotebookCompatibility {
    static func requireSupported(_ object: [String: Any]) throws {
        func keys(_ value: [String: Any], _ allowed: Set<String>) throws {
            guard Set(value.keys).isSubset(of: allowed) else { throw NotebookError.indexUnsupported }
        }
        try keys(object, Set(NotebookIndex.CodingKeys.allCases.map(\.rawValue)))
        if let version = object["version"] as? Int, ![1, 2].contains(version) {
            throw NotebookError.indexUnsupported
        }
        for item in object["items"] as? [[String: Any]] ?? [] {
            try keys(item, Set(ItemMeta.CodingKeys.allCases.map(\.rawValue)))
            if let kind = item["kind"] as? String, ItemKind(rawValue: kind) == nil {
                throw NotebookError.indexUnsupported
            }
            if let origin = item["captionSource"] as? String, CaptionSource(rawValue: origin) == nil {
                throw NotebookError.indexUnsupported
            }
            // The old description spelling has a defined caption migration.
            // Conflicting simultaneous spellings would otherwise discard a value.
            if let description = item["description"] as? String,
               let caption = item["caption"] as? String, description != caption {
                throw NotebookError.indexUnsupported
            }
            if let conversion = item["conversion"] as? [String: Any] {
                try keys(conversion, ["target", "ref", "title", "createdAt", "lastComment"])
                if let comment = conversion["lastComment"], !(comment is NSNull) {
                    // Refuse nonportable numeric/depth values before Codable could round them.
                    _ = try PrimJSON.parse(JSONSerialization.data(withJSONObject: comment, options: [.fragmentsAllowed]), maximum: IndexEnvelope.maximumBytes)
                }
                if let target = conversion["target"] as? String, ConvertTarget(rawValue: target) == nil {
                    throw NotebookError.indexUnsupported
                }
            }
            if let pin = item["primPin"] as? [String: Any] {
                try keys(pin, ["profile_id", "version", "definition_sha256"])
            }
        }
        for worker in object["workers"] as? [[String: Any]] ?? [] {
            try keys(worker, ["id", "kind", "stickyID", "title", "status", "detail", "createdAt", "updatedAt"])
        }
        for tab in object["tabs"] as? [[String: Any]] ?? [] {
            try keys(tab, ["id", "title", "colorHex", "createdAt"])
        }
        if let chat = object["chat"] as? [String: Any] {
            try keys(chat, ["engine", "endpoint", "model", "modelPath"])
        }
    }
}

