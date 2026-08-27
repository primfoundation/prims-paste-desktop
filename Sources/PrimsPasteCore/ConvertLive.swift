// Talks to local docket-prim / paseo. Never given the sticky payload.

import Foundation

public struct ConvertLive: ConvertRunning, Sendable {
    public var docketBin: String
    public var paseoBin: String
    public var packDir: URL
    public var run: @Sendable ([String]) throws -> (Int32, Data)

    public init(
        docketBin: String = "/Users/dshanklinbv/.local/bin/docket-prim",
        paseoBin: String = "/Users/dshanklinbv/bin/paseo",
        packDir: URL = Paths.docketPack,
        run: @escaping @Sendable ([String]) throws -> (Int32, Data) = ConvertLive.process
    ) {
        self.docketBin = docketBin
        self.paseoBin = paseoBin
        self.packDir = packDir
        self.run = run
    }

    public static let shared = ConvertLive()

    public func convert(target: ConvertTarget, stickyID: String, caption: String) throws -> Conversion {
        let title = Convert.title(from: caption, target: target)
        switch target {
        case .docketTask:
            return try createDocket(stickyID: stickyID, title: title)
        case .paseoAgent:
            return try createPaseo(stickyID: stickyID, title: title)
        case .note:
            throw NotebookError.convert("note is revert, not create")
        }
    }

    public func viewTask(id: String) throws -> DocketCard {
        let (code, out) = try run([
            docketBin, "task-view", id, "--dir", packDir.path, "--json",
        ])
        if code != 0 {
            throw NotebookError.convert("docket task-view failed: \(stderrish(out))")
        }
        guard let data = lastJSON(out) else {
            throw NotebookError.convert("docket task-view returned no json")
        }
        do {
            return try JSONDecoder().decode(DocketCard.self, from: data)
        } catch {
            throw NotebookError.convert("docket task-view decode: \(error)")
        }
    }

    public func saveTask(_ card: DocketCard) throws {
        var argv = [
            docketBin, "task-edit", card.id, "--dir", packDir.path, "--json",
            "--title", card.title,
            "--status", card.status,
            "--notes", card.notes,
        ]
        argv += ["--priority", card.priority ?? ""]
        argv += ["--due", card.due ?? ""]
        argv += ["--blocked", card.blockedReason ?? ""]
        let req = card.requirements.isEmpty ? ["Keep the brief honest.", "Name the work."] : card.requirements
        let accept = card.acceptance.isEmpty ? ["A stranger can mark it done.", "The sticky still cites this card."] : card.acceptance
        let cases = card.testCases.isEmpty ? ["Open the editor and the fields persist."] : card.testCases
        for r in req { argv += ["--req", r] }
        for c in cases { argv += ["--case", c] }
        for a in accept { argv += ["--accept", a] }
        let (code, out) = try run(argv)
        if code != 0 {
            throw NotebookError.convert("docket task-edit failed: \(stderrish(out))")
        }
    }

    func lastJSON(_ data: Data) -> Data? {
        guard let s = String(data: data, encoding: .utf8) else { return nil }
        if let start = s.lastIndex(of: "{") {
            return String(s[start...]).data(using: .utf8)
        }
        return data
    }

    /// Unlink. Docket cards are archived, not deleted.
    public func revert(_ conv: Conversion) throws {
        switch conv.target {
        case .docketTask:
            guard let id = Convert.docketID(from: conv.ref) else { return }
            let (code, out) = try run([
                docketBin, "task-archive", id, "--dir", packDir.path, "--json",
            ])
            if code != 0 {
                throw NotebookError.convert("docket task-archive failed: \(stderrish(out))")
            }
        case .paseoAgent, .note:
            break
        }
    }

    private func createDocket(stickyID: String, title: String) throws -> Conversion {
        try FileManager.default.createDirectory(at: packDir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: packDir.appendingPathComponent("tasks.jsonl").path) {
            let (code, out) = try run([
                docketBin, "init", "--dir", packDir.path, "--name", "Prims Paste", "--id", "prims-paste", "--json",
            ])
            if code != 0 {
                throw NotebookError.convert("docket init failed: \(stderrish(out))")
            }
        }
        let notes = Convert.docketNotes(title: title)
        let (code, out) = try run([
            docketBin, "task-create", "--dir", packDir.path, "--json",
            "--title", title,
            "--notes", notes,
            "--req", "Keep the Prims Paste sticky linked to this docket card.",
            "--req", "Do not copy secret payloads from the sticky into this pack.",
            "--case", "The sticky shows a DOCKET badge and this task id after convert.",
            "--accept", "conversion.ref points at this docket card.",
            "--accept", "The docket title matches the sticky caption.",
            "--tags", "prims-paste,converted",
            "--cite", "prims-paste:\(stickyID)",
        ])
        if code != 0 {
            throw NotebookError.convert("docket task-create failed: \(stderrish(out))")
        }
        guard let id = jsonString(out, key: "id") else {
            throw NotebookError.convert("docket task-create returned no id")
        }
        return Conversion(target: .docketTask, ref: "docket:\(packDir.path)#\(id)", title: title)
    }

    private func createPaseo(stickyID: String, title: String) throws -> Conversion {
        let prompt = """
        You are working a Prims Paste sticky.
        Title: \(title)
        Sticky id: \(stickyID)
        Do the work described by the title. Do not ask for a secret payload; it is not in this prompt.
        """
        let (code, out) = try run([
            paseoBin, "run", "--json", "--background",
            "--title", title,
            "--cwd", packDir.deletingLastPathComponent().path,
            prompt,
        ])
        if code != 0 {
            throw NotebookError.convert("paseo run failed: \(stderrish(out))")
        }
        let id = jsonString(out, key: "agentId") ?? jsonString(out, key: "id")
        guard let id else {
            throw NotebookError.convert("paseo run returned no agent id")
        }
        return Conversion(target: .paseoAgent, ref: "paseo:\(id)", title: title)
    }

    public static func process(_ argv: [String]) throws -> (Int32, Data) {
        guard let bin = argv.first else { return (127, Data("empty argv".utf8)) }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: bin)
        proc.arguments = Array(argv.dropFirst())
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        try proc.run()
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (proc.terminationStatus, data)
    }

    private func jsonString(_ data: Data, key: String) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // paseo may wrap or prefix logs; take last JSON object
            guard let s = String(data: data, encoding: .utf8) else { return nil }
            if let start = s.lastIndex(of: "{"),
               let blob = s[start...].data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: blob) as? [String: Any] {
                return obj[key] as? String
            }
            return nil
        }
        return obj[key] as? String
    }

    private func stderrish(_ data: Data) -> String {
        let s = String(data: data, encoding: .utf8) ?? ""
        return String(s.prefix(400))
    }
}
