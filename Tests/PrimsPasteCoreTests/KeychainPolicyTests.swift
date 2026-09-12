import CryptoKit
import XCTest
@testable import PrimsPasteCore

final class KeychainPolicyTests: XCTestCase {
    private func root() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("key-policy-\(UUID().uuidString)")
    }

    func testExistingKeyIsReturnedWithoutCreatingOrInspectingStore() throws {
        let key = SymmetricKey(size: .bits256)
        let loaded = try KeychainKey.resolve(notebookRoot: root(), read: { key }, insert: { _ in
            XCTFail("Existing key must not be replaced"); return true
        })
        XCTAssertEqual(loaded, key)
    }

    func testMissingKeyWithExistingNotebookNeverCreatesReplacement() throws {
        let dir = root(); defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false)
        let original = Data("synthetic sealed index".utf8)
        let index = dir.appendingPathComponent("index.json"); try original.write(to: index)
        XCTAssertThrowsError(try KeychainKey.resolve(notebookRoot: dir, read: { nil }, insert: { _ in
            XCTFail("Missing old key is not permission to create a new key"); return true
        }))
        XCTAssertEqual(try Data(contentsOf: index), original)
    }

    func testFirstCreationUsesExactlyTheInsertedKey() throws {
        var inserted: SymmetricKey?
        let result = try KeychainKey.resolve(notebookRoot: root(), read: { nil }, insert: {
            inserted = $0; return true
        })
        XCTAssertEqual(result, inserted)
        XCTAssertEqual(result.bitCount, 256)
    }

    func testConcurrentFirstCreationUsesWinnerWithoutReplacingIt() throws {
        let winner = SymmetricKey(size: .bits256)
        var reads = 0, inserts = 0
        let result = try KeychainKey.resolve(notebookRoot: root(), read: {
            reads += 1; return reads == 1 ? nil : winner
        }, insert: { candidate in
            inserts += 1; XCTAssertNotEqual(candidate, winner); return false
        })
        XCTAssertEqual(result, winner); XCTAssertEqual(reads, 2); XCTAssertEqual(inserts, 1)
    }

    func testDisappearingWinnerFailsWithoutSecondInsertion() throws {
        var inserts = 0
        XCTAssertThrowsError(try KeychainKey.resolve(notebookRoot: root(), read: { nil }, insert: { _ in
            inserts += 1; return false
        }))
        XCTAssertEqual(inserts, 1)
    }

    func testReadFailureDoesNotCreateAKey() throws {
        XCTAssertThrowsError(try KeychainKey.resolve(notebookRoot: root(), read: {
            throw NotebookError.keychain("synthetic locked keychain")
        }, insert: { _ in XCTFail("Access failure must not create a replacement"); return true }))
    }

    func testMissingKeyRejectsSymlinkRoot() throws {
        let dir = root(); defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createSymbolicLink(at: dir, withDestinationURL: root())
        XCTAssertThrowsError(try KeychainKey.resolve(notebookRoot: dir, read: { nil }, insert: { _ in
            XCTFail("A symlink is not a new notebook"); return true
        }))
    }
}
