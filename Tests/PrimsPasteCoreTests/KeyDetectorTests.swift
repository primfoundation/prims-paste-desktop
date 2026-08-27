import XCTest
@testable import PrimsPasteCore

final class KeyDetectorTests: XCTestCase {
    func testEnglishStaysProseEvenIfItSaysKey() {
        let g = KeyDetector.inspect("The API key is in 1Password, not here.")
        XCTAssertFalse(g.isKey)
        XCTAssertEqual(g.kind, "prose")
    }

    func testOpenAISecret() {
        let g = KeyDetector.inspect("sk-proj-abcdefghijklmnopqrstuvwxyz0123456789ABCD")
        XCTAssertTrue(g.isKey)
        XCTAssertEqual(g.kind, "openai")
    }

    func testStripeLive() {
        let g = KeyDetector.inspect("sk-live-abcdefghijklmnopqrstuvwx")
        XCTAssertTrue(g.isKey)
        XCTAssertEqual(g.kind, "stripe")
    }

    func testGitHubPAT() {
        let g = KeyDetector.inspect("ghp_abcdefghijklmnopqrstuvwxyz0123456789")
        XCTAssertTrue(g.isKey)
        XCTAssertEqual(g.kind, "github")
    }

    func testAWSAccessKey() {
        let g = KeyDetector.inspect("AKIAIOSFODNN7EXAMPLEAAA")
        XCTAssertTrue(g.isKey)
        XCTAssertEqual(g.kind, "aws")
    }

    func testPEM() {
        let g = KeyDetector.inspect("-----BEGIN OPENSSH PRIVATE KEY-----\nabc\n-----END OPENSSH PRIVATE KEY-----")
        XCTAssertTrue(g.isKey)
        XCTAssertEqual(g.kind, "pem")
    }

    func testJWT() {
        let g = KeyDetector.inspect(
            "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4ifQ.w1WJ7v5QhF8"
        )
        XCTAssertTrue(g.isKey)
        XCTAssertEqual(g.kind, "jwt")
    }

    func testHexBlob() {
        let g = KeyDetector.inspect("0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef")
        XCTAssertTrue(g.isKey)
        XCTAssertEqual(g.kind, "hex")
    }

    func testHighEntropyNoSpaces() {
        let g = KeyDetector.inspect("vQ8nR2wL9xP4sB7kM1dF6hJ3cA0yU5tZ8e")
        XCTAssertTrue(g.isKey)
        XCTAssertEqual(g.kind, "entropy")
    }

    func testMeetingNoteIsNotAKey() {
        let g = KeyDetector.inspect("Call Jane at 3pm about the invoice and the dumpster route.")
        XCTAssertFalse(g.isKey)
    }

    func testSkInASentenceDoesNotFireWithoutALongTail() {
        let g = KeyDetector.inspect("we should skip the meeting")
        XCTAssertFalse(g.isKey)
    }

    func testGuessDoesNotEchoTheSecret() {
        let secret = "sk-live-DO-NOT-ECHO-THIS-VALUE-123456"
        let g = KeyDetector.inspect(secret)
        XCTAssertTrue(g.isKey)
        XCTAssertFalse(g.reason.contains("DO-NOT-ECHO"))
        XCTAssertFalse(g.label.contains("DO-NOT-ECHO"))
    }

    func testAnthropic() {
        let g = KeyDetector.inspect("sk-ant-api03-abcdefghijklmnopqrstuvwxyz012345")
        XCTAssertTrue(g.isKey)
        XCTAssertEqual(g.kind, "anthropic")
    }

    func testSlackBot() {
        let g = KeyDetector.inspect("xoxb-EXAMPLE-not-a-real-token-abcdefghijk")
        XCTAssertTrue(g.isKey)
        XCTAssertEqual(g.kind, "slack")
    }

    func testGitLab() {
        let g = KeyDetector.inspect("glpat-abcdefghijklmnopqrst")
        XCTAssertTrue(g.isKey)
        XCTAssertEqual(g.kind, "gitlab")
    }

    func testXAI() {
        let g = KeyDetector.inspect("xai-abcdefghijklmnopqrstuvwxyz0123456789")
        XCTAssertTrue(g.isKey)
        XCTAssertEqual(g.kind, "xai")
    }

    func testGoogle() {
        let g = KeyDetector.inspect("AIzaSyAbcdefghijklmnopqrstuvwxy01234567")
        XCTAssertTrue(g.isKey)
        XCTAssertEqual(g.kind, "google")
    }

    func testRepeatedLetterTokenIsNotEntropy() {
        // 40×'a' is hex-shaped (SHA-1 length). Use a non-hex letter and a
        // length that isn't 32/40/64 so only the entropy gate can fire.
        let g = KeyDetector.inspect(String(repeating: "z", count: 41))
        XCTAssertFalse(g.isKey, "low shannon must not look like a key")
    }

    func testFortyHexAsIsStillHexShaped() {
        let g = KeyDetector.inspect(String(repeating: "a", count: 40))
        XCTAssertTrue(g.isKey)
        XCTAssertEqual(g.kind, "hex")
    }

    func testShortSkPrefixIsNotAKey() {
        XCTAssertFalse(KeyDetector.inspect("sk-short").isKey)
    }

    func testWhitespaceOnlyIsNotAKey() {
        XCTAssertFalse(KeyDetector.inspect("   \n\t").isKey)
    }

    func testVendorAfterEquals() {
        let g = KeyDetector.inspect("OPENAI_API_KEY=sk-proj-abcdefghijklmnopqrstuvwxyz0123456789ABCD")
        XCTAssertTrue(g.isKey)
        XCTAssertEqual(g.kind, "openai")
    }

    func testTwoPartJWTIsNotJWTKind() {
        let g = KeyDetector.inspect("eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0")
        XCTAssertNotEqual(g.kind, "jwt")
    }

    func testKeepStyleMeetingNote() {
        let g = KeyDetector.inspect("remind me to send the W-9 after lunch")
        XCTAssertFalse(g.isKey)
        XCTAssertEqual(g.kind, "prose")
    }

    func testLabelForStripe() {
        XCTAssertEqual(KeyDetector.inspect("sk-live-abcdefghijklmnopqrstuvwx").label, "Stripe secret")
    }

    func testHexWrongLengthIsNotHexKind() {
        let g = KeyDetector.inspect("0123456789abcdef")
        XCTAssertNotEqual(g.kind, "hex")
    }
}
