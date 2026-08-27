import Foundation

/// Tiny LRU so the board does not keep every decrypted blob in RAM.
final class BlobCache {
    private let cap: Int
    private var order: [String] = []
    private var values: [String: Data] = [:]

    init(cap: Int = 8) {
        self.cap = cap
    }

    func get(_ id: String) -> Data? {
        guard let v = values[id] else { return nil }
        if let i = order.firstIndex(of: id) {
            order.remove(at: i)
            order.append(id)
        }
        return v
    }

    func set(_ id: String, _ data: Data) {
        if values[id] == nil {
            order.append(id)
        }
        values[id] = data
        while order.count > cap {
            let dead = order.removeFirst()
            values.removeValue(forKey: dead)
        }
    }

    func remove(_ id: String) {
        values.removeValue(forKey: id)
        order.removeAll { $0 == id }
    }

    func removeAll() {
        values.removeAll(keepingCapacity: false)
        order.removeAll(keepingCapacity: false)
    }
}
