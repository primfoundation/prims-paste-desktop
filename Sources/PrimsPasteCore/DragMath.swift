// dnd-kit shape: live transform, commit on drop, hit-test tabs.

import CoreGraphics
import Foundation

public struct StickyDrag: Equatable, Sendable {
    public var id: String
    public var start: CGPoint
    public var translation: CGSize
    public var location: CGPoint

    public init(id: String, start: CGPoint, translation: CGSize = .zero, location: CGPoint = .zero) {
        self.id = id
        self.start = start
        self.translation = translation
        self.location = location
    }

    public var current: CGPoint {
        DragMath.position(start: start, translation: translation)
    }
}

public enum DragMath {
    public static let activation: CGFloat = 10

    public static func position(start: CGPoint, translation: CGSize) -> CGPoint {
        CGPoint(x: start.x + translation.width, y: start.y + translation.height)
    }

    public static func clamp(_ p: CGPoint, board: CGSize, sticky: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(0, p.x), max(0, board.width - sticky.width)),
            y: min(max(0, p.y), max(0, board.height - sticky.height))
        )
    }

    public static func tabHit(_ point: CGPoint, frames: [String: CGRect]) -> String? {
        for (id, frame) in frames {
            if frame.insetBy(dx: -4, dy: -4).contains(point) { return id }
        }
        return nil
    }

    /// Persist only on end. Live drag must not rewrite the index.
    public static func shouldPersist(ended: Bool) -> Bool { ended }

    public static func nextZ(_ items: [ItemMeta]) -> Int {
        (items.map(\.z).max() ?? 0) + 1
    }

    /// Low z under high z. The dragged id is always last (on top).
    public static func paintOrder(_ items: [ItemMeta], draggingID: String?) -> [ItemMeta] {
        let sorted = items.sorted { a, b in
            if a.z != b.z { return a.z < b.z }
            if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
            return a.id < b.id
        }
        guard let id = draggingID else { return sorted }
        return sorted.filter { $0.id != id } + sorted.filter { $0.id == id }
    }
}
