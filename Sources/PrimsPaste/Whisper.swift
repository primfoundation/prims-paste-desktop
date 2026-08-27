import Foundation
import PrimsPasteCore

/// Local whisper.cpp tiny.en. Only the voice wav is sent — never the paste.
enum Whisper {
    static var modelURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".prims-paste")
            .appendingPathComponent("models")
            .appendingPathComponent("ggml-tiny.en.bin")
    }

    static var binary: String { "/opt/homebrew/bin/whisper-cli" }

    static func transcribe(wav: URL) async -> String? {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(returning: run(wav: wav))
            }
        }
    }

    private static func run(wav: URL) -> String? {
        guard FileManager.default.fileExists(atPath: modelURL.path),
              FileManager.default.fileExists(atPath: binary)
        else { return nil }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binary)
        proc.arguments = WhisperCommand.arguments(model: modelURL.path, wav: wav.path)
        let out = Pipe()
        let err = Pipe()
        proc.standardOutput = out
        proc.standardError = err
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return nil
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        return WhisperCommand.parseStdout(text)
    }
}
