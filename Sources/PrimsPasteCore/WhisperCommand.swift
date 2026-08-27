// Pure bits of the local whisper.cpp call. The paste/secret never appears here.

import Foundation

public enum WhisperCommand {
    public static let defaultBinary = "/opt/homebrew/bin/whisper-cli"

    public static func arguments(model: String, wav: String) -> [String] {
        ["-m", model, "-f", wav, "-nt", "-l", "en", "-t", "4", "-np"]
    }

    public static func parseStdout(_ text: String) -> String? {
        let cleaned = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .filter { line in
                let l = line.lowercased()
                return !l.hasPrefix("whisper_")
                    && !l.hasPrefix("system_")
                    && !l.hasPrefix("main:")
                    && !l.hasPrefix("ggml_")
            }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    /// Voice wav lives next to the notebook, never in a world-readable spot.
    public static func wavURL(in dir: URL, id: String) -> URL {
        dir.appendingPathComponent("ask-\(id).wav")
    }
}
