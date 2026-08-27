// Projection of a docket-prim Task. Sticky payload never belongs here.

import Foundation

public struct DocketCard: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var status: String
    public var priority: String?
    public var notes: String
    public var requirements: [String]
    public var testCases: [String]
    public var acceptance: [String]
    public var due: String?
    public var blockedReason: String?
    public var cites: [String]?

    public init(
        id: String,
        title: String,
        status: String = "To Do",
        priority: String? = nil,
        notes: String = "",
        requirements: [String] = [],
        testCases: [String] = [],
        acceptance: [String] = [],
        due: String? = nil,
        blockedReason: String? = nil,
        cites: [String]? = nil
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.priority = priority
        self.notes = notes
        self.requirements = requirements
        self.testCases = testCases
        self.acceptance = acceptance
        self.due = due
        self.blockedReason = blockedReason
        self.cites = cites
    }

    enum CodingKeys: String, CodingKey {
        case id, title, status, priority, notes, requirements, due, cites
        case testCases = "test-cases"
        case acceptance = "acceptance-criteria"
        case blockedReason = "blocked_reason"
    }

    public static func lines(_ text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
