import XCTest
@testable import PrimsPasteCore

final class SecretFaceTests: XCTestCase {
    func testKeyStaysHiddenUntilReveal() {
        XCTAssertTrue(SecretFace.hidesPayload(looksLikeKey: true, revealed: false, shuttered: false))
        XCTAssertFalse(SecretFace.hidesPayload(looksLikeKey: true, revealed: true, shuttered: false))
    }

    func testProseShowsWithoutReveal() {
        XCTAssertFalse(SecretFace.hidesPayload(looksLikeKey: false, revealed: false, shuttered: false))
    }

    func testCoverHidesEvenIfRevealed() {
        XCTAssertTrue(SecretFace.hidesPayload(looksLikeKey: true, revealed: true, shuttered: true))
        XCTAssertTrue(SecretFace.hidesPayload(looksLikeKey: false, revealed: true, shuttered: true))
    }

    func testButtonsOnlyOnUncoveredKeys() {
        XCTAssertTrue(SecretFace.showsCopyReveal(looksLikeKey: true, shuttered: false))
        XCTAssertFalse(SecretFace.showsCopyReveal(looksLikeKey: true, shuttered: true))
        XCTAssertFalse(SecretFace.showsCopyReveal(looksLikeKey: false, shuttered: false))
    }
}
