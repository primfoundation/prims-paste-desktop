import CryptoKit
import Darwin
import XCTest
@testable import PrimsPasteCore

final class StoreConcurrencyTests: XCTestCase {
    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("primboard-lock-\(UUID().uuidString)")
    }

    func testIndependentWritersDoNotLoseItems() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let key = SymmetricKey(size: .bits256)
        let stores = try (0..<8).map { _ in try NotebookStore(root: root, key: key) }
        DispatchQueue.concurrentPerform(iterations: 80) { n in
            do {
                _ = try stores[n % stores.count].add(kind: .note, plaintext: Data("item \(n)".utf8),
                    at: .zero, size: CGSize(width: 100, height: 100), caption: "item \(n)")
            } catch { XCTFail("Concurrent add failed: \(error)") }
        }
        let index = try stores[0].loadIndex()
        XCTAssertEqual(index.items.count, 80)
        XCTAssertEqual(Set(index.items.map(\.id)).count, 80)
        XCTAssertEqual(index.revision, 80)
        for item in index.items { XCTAssertEqual(try stores[0].readBlob(id: item.id), Data(item.caption.utf8)) }
    }

    func testStaleWholeIndexCannotEraseAnotherWriter() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let key = SymmetricKey(size: .bits256)
        let first = try NotebookStore(root: root, key: key)
        let second = try NotebookStore(root: root, key: key)
        let stale = try first.loadIndex()
        _ = try second.add(kind: .note, plaintext: Data("keep".utf8), at: .zero, size: .zero)
        XCTAssertThrowsError(try first.saveIndex(stale)) { XCTAssertEqual($0 as? NotebookError, .staleIndex) }
        XCTAssertEqual(try first.loadIndex().items.count, 1)
    }

    func testLegacyIndexRemainsReadableAndGainsRevisionOnWrite() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try NotebookStore(root: root, key: SymmetricKey(size: .bits256))
        try Data(#"{"version":2,"items":[],"tabs":[],"seededFeaturesWanted":true}"#.utf8).write(to: store.indexURL)
        let old = try store.loadIndex()
        XCTAssertEqual(old.revision, 0)
        try store.saveIndex(old)
        let current = try store.loadIndex()
        XCTAssertEqual(current.revision, 1)
        XCTAssertTrue(current.seededFeaturesWanted)
    }

    func testFileReplacementKeepsOldReaderValidAndPrivatePermissions() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try NotebookStore(root: root, key: SymmetricKey(size: .bits256))
        _ = try store.add(kind: .note, plaintext: Data("keep".utf8), at: .zero, size: .zero)
        let reader = try FileHandle(forReadingFrom: store.indexURL)
        defer { try? reader.close() }
        let before = try Data(contentsOf: store.indexURL)
        _ = try store.add(kind: .note, plaintext: Data("new".utf8), at: .zero, size: .zero)
        XCTAssertEqual(try reader.readToEnd(), before)
        let attrs = try FileManager.default.attributesOfItem(atPath: store.indexURL.path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".write-") })
    }

    func testLockRejectsSymbolicLink() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let target = root.appendingPathComponent("other")
        try Data("untouched".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent(".store.lock"), withDestinationURL: target)
        XCTAssertThrowsError(try NotebookStore(root: root, key: SymmetricKey(size: .bits256)))
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "untouched")
    }
}
