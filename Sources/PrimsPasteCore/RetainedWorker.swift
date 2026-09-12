import Foundation

/// Historical job state is retained as data. No scheduler or execution is implied.
public struct RetainedWorker: Codable, Equatable, Sendable {
    public var id: String
    public var kind: String
    public var stickyID: String
    public var title: String
    public var status: String
    public var detail: String
    public var createdAt: Date
    public var updatedAt: Date
}
