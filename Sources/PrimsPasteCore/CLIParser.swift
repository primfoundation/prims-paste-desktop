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
    case backup(path: String)
    case restore(path: String, destination: String)
    case profiles
    case primCreate(profile: String, version: String, source: String?, input: String?, operation: String?)
    case primValidate(id: String)
    case primExport(id: String, destination: String)
    case primImport(path: String)
}

public struct CLIUsage: Error, Equatable, Sendable {
    public var message: String
    public init(_ message: String) { self.message = message }
}

public enum CLIParser {
    public static let usage = """
    usage: prims-paste <open|tabs|tab|add|list|convert|bugs|import-safepaste|wanted|backup|restore|help> [args...]
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
      prims-paste backup <new-file.pboard>
      prims-paste restore <file.pboard> --to <new-directory>
      prims-paste profiles
      prims-paste prim create <namespace/name> --version <exact-version> [--from <sticky-id>] [--input <record.json>] [--operation <prim_32hex>]
      prims-paste prim validate <id>
      prims-paste prim export <id> --to <new-folder>
      prims-paste prim import <folder>
    """

    public static func parse(_ argv: [String]) -> Result<CLICommand, CLIUsage> {
        guard let cmd = argv.first else { return .failure(CLIUsage(usage)) }
        let rest = Array(argv.dropFirst())
        switch cmd {
        case "profiles":
            guard rest.isEmpty else { return .failure(CLIUsage("usage: prims-paste profiles")) }
            return .success(.profiles)
        case "prim":
            if rest.count == 2 && rest[0] == "validate" { return .success(.primValidate(id: rest[1])) }
            if rest.count == 2 && rest[0] == "import" { return .success(.primImport(path: rest[1])) }
            if rest.count == 4 && rest[0] == "export" && rest[2] == "--to" { return .success(.primExport(id: rest[1], destination: rest[3])) }
            if rest.count >= 4 && rest[0] == "create" {
                var flags: [String: String] = [:]
                let pairs = Array(rest.dropFirst(2))
                guard pairs.count % 2 == 0 else { return .failure(CLIUsage("Prim creation requires flag/value pairs.")) }
                for i in stride(from: 0, to: pairs.count, by: 2) {
                    guard ["--version", "--from", "--input", "--operation"].contains(pairs[i]), flags[pairs[i]] == nil else {
                        return .failure(CLIUsage("Unknown or repeated Prim creation option."))
                    }
                    flags[pairs[i]] = pairs[i + 1]
                }
                guard let version = flags["--version"] else { return .failure(CLIUsage("An exact --version is required.")) }
                return .success(.primCreate(profile: rest[1], version: version, source: flags["--from"], input: flags["--input"], operation: flags["--operation"]))
            }
            return .failure(CLIUsage(usage))
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
        case "backup":
            guard rest.count == 1 else { return .failure(CLIUsage("usage: prims-paste backup <new-file.pboard>")) }
            return .success(.backup(path: rest[0]))
        case "restore":
            guard rest.count == 3, rest[1] == "--to" else { return .failure(CLIUsage("usage: prims-paste restore <file.pboard> --to <new-directory>")) }
            return .success(.restore(path: rest[0], destination: rest[2]))
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
