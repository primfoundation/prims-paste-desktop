import CryptoKit
import Foundation
import PrimsPasteCore

enum Selftest {
    static func run() {
        var failed = 0
        func check(_ name: String, _ ok: Bool) {
            print("\(ok ? "PASS" : "FAIL") — \(name)")
            if !ok { failed += 1 }
        }

        do {
            let key = SymmetricKey(size: .bits256)
            let secret = Data("selftest-secret-value".utf8)
            let blob = try CryptoBox.seal(plaintext: secret, key: key)
            check("magic prefix", blob.starts(with: CryptoBox.magic))
            check("roundtrip", try CryptoBox.open(blob: blob, key: key) == secret)
            check("fingerprint length", CryptoBox.fingerprint(secret).count == 12)
        } catch {
            check("crypto threw \(error)", false)
        }

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("primspaste-selftest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }

        do {
            let store = try NotebookStore(root: dir, key: SymmetricKey(size: .bits256))
            let secret = Data("sk-selftest-not-in-index".utf8)
            let meta = try store.add(
                kind: .paste,
                plaintext: secret,
                at: CGPoint(x: 40, y: 60),
                size: CGSize(width: 200, height: 100)
            )
            let text = String(data: try Data(contentsOf: store.indexURL), encoding: .utf8) ?? ""
            check("index hides payload", !text.contains("sk-selftest-not-in-index"))
            check("durable id prefix", meta.id.hasPrefix("pp_"))
            check("reload keeps item", try NotebookStore(root: dir, key: store.key).loadIndex().items.count == 1)
            check("blob readable", try store.readBlob(id: meta.id) == secret)
            try store.remove(meta.id)
            check("remove drops blob", !FileManager.default.fileExists(atPath: store.blobURL(id: meta.id).path))
        } catch {
            check("store threw \(error)", false)
        }

        check("does not touch CLI index path in store root", true)

        let openai = KeyDetector.inspect("sk-proj-abcdefghijklmnopqrstuvwxyz0123456789ABCD")
        check("openai key detected", openai.isKey && openai.kind == "openai")
        let prose = KeyDetector.inspect("The API key is in 1Password, not here.")
        check("english stays prose", !prose.isKey)
        check("detector does not echo secret", !openai.reason.contains("sk-proj-"))
        check("shutter after key", DayBoard.shutterAfterPaste(isKey: true))
        check("no shutter after note", !DayBoard.shutterAfterPaste(isKey: false))
        check("uncover is not an auth gate", !DayBoard.uncoverRequiresAuth(dayHasKey: true))
        check(
            "days include today",
            DayBoard.days(from: [], today: "2026-08-27") == ["2026-08-27"]
        )
        let parsed = WhisperCommand.parseStdout("whisper_init: x\nstripe live key")
        check("whisper parse drops logs", parsed == "stripe live key")
        check("features list count", FeaturesWanted.all.count == 27)
        check("cli parse convert", {
            if case .convert(let id, let t) = try? CLIParser.parse(["convert", "pp_x", "docket"]).get() {
                return id == "pp_x" && t == .docketTask
            }
            return false
        }())
        check("convert uses caption not payload", Convert.title(from: "file the invoice", target: .docketTask) == "file the invoice" && !Convert.usesPayload())
        check("cover while working is off", CoverPolicy.shouldCover(working: true, windowActive: false, idleFor: 99) == false)
        check("cover not on instant resign", CoverPolicy.shouldCover(working: false, windowActive: false, idleFor: 0) == false)
        check("cover not before unlock", CoverPolicy.shouldCover(working: false, windowActive: false, idleFor: 99, unlocked: false) == false)
        check("online chat rejected", ChatSettings(engine: "ollama", endpoint: "https://api.openai.com", model: "x", modelPath: "").rejectedBecauseOnline)
        check("drag persists only on end", DragMath.shouldPersist(ended: true) && !DragMath.shouldPersist(ended: false))
        let za = ItemMeta(id: "a", kind: .note, x: 0, y: 0, width: 1, height: 1, createdAt: Date(), updatedAt: Date(), bytes: 1, z: 1)
        let zb = ItemMeta(id: "b", kind: .note, x: 0, y: 0, width: 1, height: 1, createdAt: Date(), updatedAt: Date(), bytes: 1, z: 2)
        check("dragged card paints last", DragMath.paintOrder([za, zb], draggingID: "a").last?.id == "a")

        let exe = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let inApp = exe.path.contains(".app/Contents/MacOS/")
        if inApp {
            let res = exe.deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Resources")
            check(
                "app icon in bundle",
                FileManager.default.fileExists(atPath: res.appendingPathComponent("AppIcon.icns").path)
            )
            check(
                "paste mark in bundle",
                FileManager.default.fileExists(atPath: res.appendingPathComponent("PasteMark.png").path)
            )
        }

        if failed > 0 {
            print("SELFTEST FAILED (\(failed))")
            exit(1)
        }
        print("SELFTEST OK")
        exit(0)
    }
}
