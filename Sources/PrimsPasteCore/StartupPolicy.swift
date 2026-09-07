import Foundation

public enum StartupPolicy {
    /// Product-development fixtures are opt-in. Normal app startup must never
    /// write Primboard's own feature/bug backlog into a user's durable notebook.
    public static func developerSeedsEnabled(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        environment["PRIMBOARD_DEVELOPER_SEEDS"] == "1"
    }

    /// Prefer today's tab without deleting or hiding any historical/custom tab.
    /// Existing feature/bug tabs from earlier builds remain user data unless the
    /// user chooses to remove them.
    public static func initialTabID(
        _ tabs: [BoardTab],
        today: String = ItemMeta.today()
    ) -> String {
        if tabs.contains(where: { $0.id == today }) {
            return today
        }
        return tabs.first?.id ?? today
    }
}
