import XCTest
@testable import PrimsPasteCore

final class WhisperCommandTests: XCTestCase {
    func testArgsNeverIncludeASecret() {
        let args = WhisperCommand.arguments(
            model: "/tmp/ggml-tiny.en.bin",
            wav: "/tmp/ask.wav"
        )
        XCTAssertEqual(args, [
            "-m", "/tmp/ggml-tiny.en.bin",
            "-f", "/tmp/ask.wav",
            "-nt", "-l", "en", "-t", "4", "-np",
        ])
        XCTAssertFalse(args.contains { $0.contains("sk-") })
    }

    func testParseDropsGgmlNoise() {
        let raw = """
        whisper_init: loading
        ggml_metal: ok
        main: processing
        Stripe production token
        """
        XCTAssertEqual(WhisperCommand.parseStdout(raw), "Stripe production token")
    }

    func testParseEmptyIsNil() {
        XCTAssertNil(WhisperCommand.parseStdout("\nwhisper_init: hi\n"))
        XCTAssertNil(WhisperCommand.parseStdout(""))
    }

    func testParseJoinsLines() {
        XCTAssertEqual(
            WhisperCommand.parseStdout("github\npersonal access token"),
            "github personal access token"
        )
    }

    func testWavNameDoesNotUseTheSecret() {
        let url = WhisperCommand.wavURL(in: URL(fileURLWithPath: "/tmp"), id: "nb_abc")
        XCTAssertEqual(url.lastPathComponent, "ask-nb_abc.wav")
        XCTAssertFalse(url.lastPathComponent.contains("sk-live"))
        XCTAssertFalse(url.lastPathComponent.contains("ghp_"))
    }
}
