import CoreGraphics
import Foundation
import PrimsPasteCore

@main
enum PrimsPasteCLI {
    static func main() {
        let argv = Array(CommandLine.arguments.dropFirst())
        switch CLIParser.parse(argv) {
        case .failure(let usage):
            fputs(usage.message + "\n", stderr)
            exit(argv.isEmpty ? 0 : 2)
        case .success(let cmd):
            do {
                try run(cmd)
            } catch {
                fputs("error: \(error)\n", stderr)
                exit(1)
            }
        }
    }

    static func run(_ cmd: CLICommand) throws {
        switch cmd {
        case .help:
            print(CLIParser.usage, terminator: "")
        case .open:
            let app = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications/Prims Paste.app")
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            proc.arguments = ["-a", app.path]
            try proc.run()
            proc.waitUntilExit()
            if proc.terminationStatus != 0 { throw NotebookError.convert("open failed") }
        case .tabs, .tabAdd, .add, .list, .convert, .bugsFile, .bugsTasks:
            let store = try notebook()
            try runStore(cmd, store: store)
        }
    }

    static func notebook() throws -> NotebookStore {
        let key = try KeychainKey.loadOrCreate()
        return try NotebookStore(root: Paths.defaultRoot, key: key)
    }

    static func runStore(_ cmd: CLICommand, store: NotebookStore) throws {
        switch cmd {
        case .tabs:
            let idx = try store.loadIndex()
            if idx.tabs.isEmpty { print("(no tabs)"); return }
            for t in idx.tabs {
                print("\(t.id)  \(t.title)  \(t.colorHex)")
            }
        case .tabAdd(let title, let color):
            let tab = try store.addTab(title: title, colorHex: color)
            print("\(tab.id)  \(tab.title)")
        case .add(let tabQ, let title, let body):
            let idx = try store.loadIndex()
            guard let tab = CLIParser.resolveTab(tabQ, tabs: idx.tabs) else {
                throw NotebookError.convert("unknown tab \(tabQ)")
            }
            let meta = try store.add(
                kind: .note,
                plaintext: Data(body.utf8),
                at: CGPoint(x: 40, y: 40),
                size: CGSize(width: NotebookLayout.sticky, height: NotebookLayout.sticky),
                caption: title,
                tabID: tab.id
            )
            print("\(meta.id)  \(tab.title)  \(title)")
        case .list(let tabQ):
            let idx = try store.loadIndex()
            var items = idx.items
            if let tabQ {
                guard let tab = CLIParser.resolveTab(tabQ, tabs: idx.tabs) else {
                    throw NotebookError.convert("unknown tab \(tabQ)")
                }
                items = items.filter { $0.tabID == tab.id }
            }
            if items.isEmpty { print("(no stickies)"); return }
            for it in items {
                let conv = it.conversion.map { "  \($0.target.rawValue)=\($0.ref)" } ?? ""
                print("\(it.id)  \(it.tabID)  \(it.caption)\(conv)")
            }
        case .convert(let id, let target):
            let idx = try store.loadIndex()
            guard let item = idx.items.first(where: { $0.id == id }) else {
                throw NotebookError.missingBlob(id)
            }
            let conv = try ConvertLive.shared.convert(
                target: target,
                stickyID: id,
                caption: item.caption
            )
            let meta = try store.convert(id, conversion: conv)
            print("\(meta.id)  \(conv.target.rawValue)  \(conv.ref)")
        case .bugsFile:
            try store.seedBugs()
            let idx = try store.loadIndex()
            let n = idx.items.filter { $0.tabID == Bugs.tabID }.count
            print("bugs tab \(Bugs.tabID)  stickies=\(n)")
        case .bugsTasks:
            try store.seedBugs()
            let idx = try store.loadIndex()
            let pending = idx.items.filter {
                $0.tabID == Bugs.tabID && $0.conversion?.target != .docketTask
            }
            if pending.isEmpty { print("(no pending bug stickies)"); return }
            for item in pending {
                let conv = try ConvertLive.shared.convert(
                    target: .docketTask,
                    stickyID: item.id,
                    caption: item.caption
                )
                _ = try store.convert(item.id, conversion: conv)
                print("\(item.id)  docket  \(conv.ref)")
            }
        default:
            break
        }
    }
}
