// prims-paste CLI. Same notebook as the app. No GUI required.

import Foundation

public enum CLICommand: Equatable, Sendable {
    case help
    case open
    case tabs
    case tabAdd(title: String, color: String)
    case add(tab: String, title: String, body: String)
    case list(tab: String?)
    case convert(id: String, target: ConvertTarget)
    case bugsFile
    case bugsTasks
    case importSafepaste
    case wantedSeed
}

public struct CLIUsage: Error, Equatable, Sendable {
    public var message: String
    public init(_ message: String) { self.message = message }
}

public enum CLIParser {
    public static let usage = """
    usage: prims-paste <open|tabs|tab|add|list|convert|bugs|import-safepaste|help> [args...]
      prims-paste open
      prims-paste tabs
      prims-paste tab add <title> [--color #HEX]
      prims-paste add --tab <name-or-id> --title <text> [--body <text>]
      prims-paste list [--tab <name-or-id>]
      prims-paste convert <id> <docket|paseo|note>
      prims-paste bugs file
      prims-paste bugs tasks
      prims-paste import-safepaste
      prims-paste wanted
    """

    public static func parse(_ argv: [String]) -> Result<CLICommand, CLIUsage> {
        guard let cmd = argv.first else { return .failure(CLIUsage(usage)) }
        let rest = Array(argv.dropFirst())
        switch cmd {
        case "help", "-h", "--help":
            return .success(CLICommand.help)
        case "open":
            return .success(CLICommand.open)
        case "tabs":
            return .success(CLICommand.tabs)
        case "tab":
            guard rest.first == "add", rest.count >= 2 else {
                return .failure(CLIUsage("usage: prims-paste tab add <title> [--color #HEX]"))
            }
            let title = rest[1]
            let color = flag(rest, "--color") ?? "#8B2E2E"
            return .success(CLICommand.tabAdd(title: title, color: color))
        case "add":
            guard let tab = flag(rest, "--tab"), let title = flag(rest, "--title") else {
                return .failure(CLIUsage("usage: prims-paste add --tab <name-or-id> --title <text> [--body <text>]"))
            }
            return .success(CLICommand.add(tab: tab, title: title, body: flag(rest, "--body") ?? title))
        case "list":
            return .success(CLICommand.list(tab: flag(rest, "--tab")))
        case "convert":
            guard rest.count >= 2, let target = ConvertTarget(rawValue: rest[1]) else {
                return .failure(CLIUsage("usage: prims-paste convert <id> <docket|paseo|note>"))
            }
            return .success(CLICommand.convert(id: rest[0], target: target))
        case "bugs":
            switch rest.first {
            case "file": return .success(CLICommand.bugsFile)
            case "tasks": return .success(CLICommand.bugsTasks)
            default: return .failure(CLIUsage("usage: prims-paste bugs file|tasks"))
            }
        case "import-safepaste":
            return .success(CLICommand.importSafepaste)
        case "wanted":
            return .success(CLICommand.wantedSeed)
        default:
            return .failure(CLIUsage(usage))
        }
    }

    public static func resolveTab(_ query: String, tabs: [BoardTab]) -> BoardTab? {
        let q = query.lowercased()
        return tabs.first { $0.id.lowercased() == q || $0.title.lowercased() == q }
    }

    private static func flag(_ args: [String], _ name: String) -> String? {
        guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
}
