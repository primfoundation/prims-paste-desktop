// Local-only chat. Online hosts are rejected.

import Foundation

public struct ChatSettings: Codable, Equatable, Sendable {
    public var engine: String
    public var endpoint: String
    public var model: String
    public var modelPath: String

    public static let none = ChatSettings(engine: "none", endpoint: "", model: "", modelPath: "")

    public init(engine: String, endpoint: String, model: String, modelPath: String) {
        self.engine = engine
        self.endpoint = endpoint
        self.model = model
        self.modelPath = modelPath
    }

    public static let localEngines = ["none", "ollama", "llamacpp", "mlx"]

    public static func isLoopback(_ url: String) -> Bool {
        let t = url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t.isEmpty { return true }
        guard let u = URL(string: t), let host = u.host?.lowercased() else { return false }
        return host == "127.0.0.1" || host == "localhost" || host == "::1"
            || host.hasSuffix(".localhost")
    }

    public var rejectedBecauseOnline: Bool {
        engine != "none" && !endpoint.isEmpty && !Self.isLoopback(endpoint)
    }
}

public enum CoverPolicy {
    public static let idleSeconds: TimeInterval = 45

    public static let resignGrace: TimeInterval = 2

    /// Cover only when you are not working. Touch ID / switching apps
    /// must not black the board the instant the window resigns.
    public static func shouldCover(
        working: Bool,
        windowActive: Bool,
        idleFor: TimeInterval,
        unlocked: Bool = true
    ) -> Bool {
        if !unlocked { return false }
        if working { return false }
        if !windowActive { return idleFor >= resignGrace }
        return idleFor >= idleSeconds
    }
}
