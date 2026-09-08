import CryptoKit
import Darwin
import XCTest
@testable import PrimsPasteCore

final class NotebookJournalTests: XCTestCase {
    private let key = SymmetricKey(data: Data(repeating: 0x42, count: 32)) // Synthetic fixture only.
    private let oldBody = Data("original private payload".utf8)
    private let newBody = Data("replacement private payload with a different length".utf8)
    private let image = Data([137, 80, 78, 71, 13, 10, 26, 10, 1, 2])
    private struct Interrupted: Error {}

    private func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("primboard-journal-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func item(_ store: NotebookStore) throws -> ItemMeta {
        try store.add(kind: .paste, plaintext: oldBody, at: .zero, size: .zero, caption: "private caption")
    }

    private func interrupt(_ store: NotebookStore, at target: TransactionCheckpoint) {
        store.transactionCheckpoint = { if $0 == target { throw Interrupted() } }
    }

    private func assertRecovered(_ store: NotebookStore, id: String, revision: UInt64, body: Data) throws {
        let index = try store.loadIndex()
        let item = try XCTUnwrap(index.items.first { $0.id == id })
        XCTAssertEqual(index.revision, revision)
        XCTAssertEqual(try store.readBlob(id: id), body)
        XCTAssertEqual(item.bytes, body.count)
        XCTAssertEqual(item.fingerprint, CryptoBox.fingerprint(body))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.journalURL.path))
        // A second independent reopen neither duplicates the operation nor increments revision.
        XCTAssertEqual(try NotebookStore(root: store.root, key: key).loadIndex(), index)
    }

    func testBeforeCommitFailurePreservesExactIndexAndBlob() throws {
        let store = try NotebookStore(root: root(), key: key)
        let meta = try item(store)
        let index = try Data(contentsOf: store.indexURL), blob = try Data(contentsOf: store.blobURL(id: meta.id))
        interrupt(store, at: .beforeJournal)
        XCTAssertThrowsError(try store.updatePayload(meta.id, plaintext: newBody))
        XCTAssertEqual(try Data(contentsOf: store.indexURL), index)
        XCTAssertEqual(try Data(contentsOf: store.blobURL(id: meta.id)), blob)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.journalURL.path))
    }

    func testPayloadUpdateRecoversAtEveryDurableBoundary() throws {
        for stage in 0..<4 {
            let store = try NotebookStore(root: root(), key: key)
            let meta = try item(store)
            let revision = try store.loadIndex().revision
            let points: [TransactionCheckpoint] = [.journalPersisted, .blobWritten("\(meta.id).enc"), .indexWritten, .journalRemoved]
            interrupt(store, at: points[stage])
            XCTAssertThrowsError(try store.updatePayload(meta.id, plaintext: newBody))
            let reopened = try NotebookStore(root: store.root, key: key)
            // Raw payload reads must recover too, without requiring loadIndex first.
            XCTAssertEqual(try reopened.readBlob(id: meta.id), newBody)
            try assertRecovered(reopened, id: meta.id, revision: revision + 1, body: newBody)
        }
    }

    func testNewNotebookAddRecoversExactlyOnceBeforeIndexExists() throws {
        let store = try NotebookStore(root: root(), key: key)
        interrupt(store, at: .journalPersisted)
        XCTAssertThrowsError(try item(store))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.indexURL.path))
        let reopened = try NotebookStore(root: store.root, key: key)
        let index = try reopened.loadIndex()
        XCTAssertEqual(index.items.count, 1)
        try assertRecovered(reopened, id: try XCTUnwrap(index.items.first).id, revision: 1, body: oldBody)
    }

    func testImageAttachmentAndReplacementRecoverWithMetadata() throws {
        for replacing in [false, true] {
            for stage in 0..<3 {
                let store = try NotebookStore(root: root(), key: key)
                let meta = try item(store)
                if replacing { try store.writeImage(meta.id, png: Data("previous image".utf8)) }
                let revision = try store.loadIndex().revision
                let points: [TransactionCheckpoint] = [.journalPersisted, .blobWritten("\(meta.id)-img.enc"), .indexWritten]
                interrupt(store, at: points[stage])
                XCTAssertThrowsError(try store.writeImage(meta.id, png: image))
                let reopened = try NotebookStore(root: store.root, key: key)
                XCTAssertEqual(try reopened.readImage(meta.id), image)
                XCTAssertTrue(try reopened.loadIndex().items[0].hasImage)
                try assertRecovered(reopened, id: meta.id, revision: revision + 1, body: oldBody)
            }
        }
    }

    func testRemovalRecoversBetweenBodyAndImageDeletion() throws {
        for stage in 0..<5 {
            let store = try NotebookStore(root: root(), key: key)
            let meta = try item(store)
            try store.writeImage(meta.id, png: image)
            let revision = try store.loadIndex().revision
            let points: [TransactionCheckpoint] = [.journalPersisted, .indexWritten,
                .blobDeleted("\(meta.id)-img.enc"), .blobDeleted("\(meta.id).enc"), .journalRemoved]
            interrupt(store, at: points[stage])
            XCTAssertThrowsError(try store.remove(meta.id))
            let reopened = try NotebookStore(root: store.root, key: key)
            let index = try reopened.loadIndex()
            XCTAssertTrue(index.items.isEmpty)
            XCTAssertEqual(index.revision, revision + 1)
            XCTAssertFalse(FileManager.default.fileExists(atPath: reopened.blobURL(id: meta.id).path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: reopened.imageURL(id: meta.id).path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: reopened.journalURL.path))
        }
    }

    func testBatchedSeedsRecoverAllItemsAfterFirstBlob() throws {
        for bugs in [false, true] {
            let store = try NotebookStore(root: root(), key: key)
            store.transactionCheckpoint = { if case .blobWritten = $0 { throw Interrupted() } }
            if bugs { XCTAssertThrowsError(try store.seedBugs()) }
            else { XCTAssertThrowsError(try store.seedFeaturesWanted()) }
            let reopened = try NotebookStore(root: store.root, key: key)
            let index = try reopened.loadIndex()
            let expected = bugs ? Set(Bugs.all.map(\.bugStickyID)) : Set(FeaturesWanted.all.map(\.stickyID))
            XCTAssertEqual(Set(index.items.map(\.id)), expected)
            for item in index.items { XCTAssertEqual(try reopened.readBlob(id: item.id).count, item.bytes) }
            XCTAssertEqual(index.revision, 1)
            XCTAssertFalse(FileManager.default.fileExists(atPath: reopened.journalURL.path))
        }
    }

    func testRecoveryCanBeInterruptedAndReplayedAgain() throws {
        let store = try NotebookStore(root: root(), key: key)
        let meta = try item(store)
        interrupt(store, at: .journalPersisted)
        XCTAssertThrowsError(try store.updatePayload(meta.id, plaintext: newBody))
        let recovering = try NotebookStore(root: store.root, key: key)
        interrupt(recovering, at: .blobWritten("\(meta.id).enc"))
        XCTAssertThrowsError(try recovering.loadIndex())
        let reopened = try NotebookStore(root: store.root, key: key)
        try assertRecovered(reopened, id: meta.id, revision: 2, body: newBody)
    }

    func testStaleWriterCannotOverwriteRecoveredCommit() throws {
        let store = try NotebookStore(root: root(), key: key)
        let meta = try item(store)
        let stale = try store.loadIndex()
        let other = try NotebookStore(root: store.root, key: key)
        interrupt(store, at: .journalPersisted)
        XCTAssertThrowsError(try store.updatePayload(meta.id, plaintext: newBody))
        XCTAssertThrowsError(try other.saveIndex(stale)) { XCTAssertEqual($0 as? NotebookError, .staleIndex) }
        try assertRecovered(other, id: meta.id, revision: 2, body: newBody)
    }

    func testBackupFinishesRecoveryBeforeTakingSnapshot() throws {
        let parent = try root()
        let store = try NotebookStore(root: parent.appendingPathComponent("notebook"), key: key)
        let meta = try item(store)
        interrupt(store, at: .blobWritten("\(meta.id).enc"))
        XCTAssertThrowsError(try store.updatePayload(meta.id, plaintext: newBody))
        let reopened = try NotebookStore(root: store.root, key: key)
        let backup = parent.appendingPathComponent("backup.pboard"), restored = parent.appendingPathComponent("restored")
        try reopened.exportBackup(to: backup)
        try NotebookStore.restoreBackup(from: backup, to: restored, key: key)
        try assertRecovered(NotebookStore(root: restored, key: key), id: meta.id, revision: 2, body: newBody)
    }

    func testJournalConfidentialityPermissionsAndWrongKeyFailure() throws {
        let store = try NotebookStore(root: root(), key: key)
        let meta = try item(store)
        let before = try Data(contentsOf: store.indexURL), blob = try Data(contentsOf: store.blobURL(id: meta.id))
        interrupt(store, at: .journalPersisted)
        XCTAssertThrowsError(try store.updatePayload(meta.id, plaintext: newBody))
        let journal = try Data(contentsOf: store.journalURL)
        XCTAssertTrue(journal.starts(with: TransactionJournal.magic))
        for secret in [newBody, oldBody, Data(meta.id.utf8), Data(meta.caption.utf8)] { XCTAssertNil(journal.range(of: secret)) }
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: store.journalURL.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        let wrong = try NotebookStore(root: store.root, key: SymmetricKey(size: .bits256))
        XCTAssertThrowsError(try wrong.loadIndex())
        XCTAssertThrowsError(try wrong.readBlob(id: meta.id))
        XCTAssertEqual(try Data(contentsOf: store.journalURL), journal)
        XCTAssertEqual(try Data(contentsOf: store.indexURL), before)
        XCTAssertEqual(try Data(contentsOf: store.blobURL(id: meta.id)), blob)
    }

    func testInvalidJournalNeverMutatesFilesOrDiscardsRecoveryEvidence() throws {
        let store = try NotebookStore(root: root(), key: key)
        let meta = try item(store)
        let before = try Data(contentsOf: store.indexURL), blob = try Data(contentsOf: store.blobURL(id: meta.id))
        interrupt(store, at: .journalPersisted)
        XCTAssertThrowsError(try store.updatePayload(meta.id, plaintext: newBody))
        let original = try Data(contentsOf: store.journalURL)
        let transaction = try TransactionJournal.open(original, key: key)
        var corrupt = original; corrupt[corrupt.count - 1] ^= 1
        var fixtures = [corrupt, Data("truncated".utf8)]
        var unsupported = transaction; unsupported.version = 999
        fixtures.append(try TransactionJournal.seal(unsupported, key: key))
        var badPath = transaction; badPath.writes["../../outside.enc"] = blob
        fixtures.append(try TransactionJournal.seal(badPath, key: key))
        var unexpectedDelete = transaction; unexpectedDelete.deletes = ["unrelated.enc"]
        fixtures.append(try TransactionJournal.seal(unexpectedDelete, key: key))
        var missing = transaction; missing.writes = [:]
        fixtures.append(try TransactionJournal.seal(missing, key: key))
        var wrongInnerKey = transaction
        wrongInnerKey.writes["\(meta.id).enc"] = try CryptoBox.seal(plaintext: newBody, key: SymmetricKey(size: .bits256))
        fixtures.append(try TransactionJournal.seal(wrongInnerKey, key: key))
        var wrongLength = transaction
        wrongLength.writes["\(meta.id).enc"] = try CryptoBox.seal(plaintext: Data("short".utf8), key: key)
        fixtures.append(try TransactionJournal.seal(wrongLength, key: key))
        var wrongFingerprint = transaction
        wrongFingerprint.writes["\(meta.id).enc"] = try CryptoBox.seal(plaintext: Data(repeating: 65, count: newBody.count), key: key)
        fixtures.append(try TransactionJournal.seal(wrongFingerprint, key: key))
        for fixture in fixtures {
            try fixture.write(to: store.journalURL)
            let reopened = try NotebookStore(root: store.root, key: key)
            XCTAssertThrowsError(try reopened.loadIndex())
            XCTAssertEqual(try Data(contentsOf: store.indexURL), before)
            XCTAssertEqual(try Data(contentsOf: store.blobURL(id: meta.id)), blob)
            XCTAssertEqual(try Data(contentsOf: store.journalURL), fixture)
        }
    }

    func testUnrelatedIndexRevisionCannotBeOverwrittenByPendingJournal() throws {
        let store = try NotebookStore(root: root(), key: key)
        let meta = try item(store)
        let old = try Data(contentsOf: store.indexURL)
        interrupt(store, at: .journalPersisted)
        XCTAssertThrowsError(try store.updatePayload(meta.id, plaintext: newBody))
        // Same decoded old index but different authenticated bytes is still external interference.
        let unrelated = try IndexEnvelope.seal(IndexEnvelope.plaintext(old, key: key), key: key)
        try unrelated.write(to: store.indexURL)
        XCTAssertThrowsError(try NotebookStore(root: store.root, key: key).loadIndex())
        XCTAssertEqual(try Data(contentsOf: store.indexURL), unrelated)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.journalURL.path))
    }

    func testJournalAndAffectedBlobSymlinksFailWithoutFollowingTarget() throws {
        let store = try NotebookStore(root: root(), key: key)
        let meta = try item(store)
        interrupt(store, at: .journalPersisted)
        XCTAssertThrowsError(try store.updatePayload(meta.id, plaintext: newBody))
        let journal = try Data(contentsOf: store.journalURL)
        let outside = store.root.appendingPathComponent("preserve-outside")
        try Data("keep".utf8).write(to: outside)
        try FileManager.default.removeItem(at: store.blobURL(id: meta.id))
        try FileManager.default.createSymbolicLink(at: store.blobURL(id: meta.id), withDestinationURL: outside)
        XCTAssertThrowsError(try NotebookStore(root: store.root, key: key).loadIndex())
        XCTAssertEqual(try Data(contentsOf: outside), Data("keep".utf8))
        XCTAssertEqual(try Data(contentsOf: store.journalURL), journal)
        try FileManager.default.removeItem(at: store.journalURL)
        try FileManager.default.createSymbolicLink(at: store.journalURL, withDestinationURL: outside)
        XCTAssertThrowsError(try NotebookStore(root: store.root, key: key).loadIndex())
        XCTAssertEqual(try Data(contentsOf: outside), Data("keep".utf8))
    }

    func testPublicBlobWritesAndDeletesKeepReferencedMetadataConsistent() throws {
        let store = try NotebookStore(root: root(), key: key)
        let meta = try item(store)
        try store.writeBlob(id: meta.id, plaintext: newBody)
        try assertRecovered(store, id: meta.id, revision: 2, body: newBody)
        try store.deleteBlob(id: meta.id)
        XCTAssertTrue(try store.loadIndex().items.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.blobURL(id: meta.id).path))
    }

    func testOversizedChangeFailsBeforePublishingJournalOrMutatingNotebook() throws {
        let store = try NotebookStore(root: root(), key: key)
        let meta = try item(store)
        let original = try Data(contentsOf: store.indexURL)
        XCTAssertThrowsError(try store.updatePayload(meta.id, plaintext: Data(repeating: 1, count: TransactionJournal.maximumWriteBytes))) {
            XCTAssertEqual($0 as? NotebookError, .transactionTooLarge)
        }
        XCTAssertEqual(try Data(contentsOf: store.indexURL), original)
        XCTAssertEqual(try store.readBlob(id: meta.id), oldBody)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.journalURL.path))
    }

    func testRawPathAndImageAliasesCannotOverwriteAnotherItem() throws {
        let store = try NotebookStore(root: root(), key: key)
        let meta = try item(store)
        try store.writeImage(meta.id, png: image)
        for id in ["../outside", meta.id.uppercased(), meta.id + "-img"] {
            XCTAssertThrowsError(try store.writeBlob(id: id, plaintext: newBody))
            XCTAssertThrowsError(try store.deleteBlob(id: id))
        }
        XCTAssertEqual(try store.readBlob(id: meta.id), oldBody)
        XCTAssertEqual(try store.readImage(meta.id), image)
        var renamed = try store.loadIndex()
        renamed.items[0].id = meta.id.uppercased()
        XCTAssertThrowsError(try store.saveIndex(renamed))
        XCTAssertEqual(try store.readBlob(id: meta.id), oldBody)
    }

    func testDeletingItemPreservesAnotherItemsImageShapedBody() throws {
        let store = try NotebookStore(root: root(), key: key)
        let meta = try item(store), secondID = meta.id + "-img"
        try store.writeBlob(id: secondID, plaintext: oldBody)
        var index = try store.loadIndex()
        var second = meta; second.id = secondID
        index.items.append(second)
        try store.saveIndex(index)
        try store.remove(meta.id)
        try assertRecovered(store, id: secondID, revision: 3, body: oldBody)
    }

    func testLegacyDerivedTabsHaveStableSourceBasedCreationDates() throws {
        let store = try NotebookStore(root: root(), key: key)
        let meta = try item(store)
        var index = try store.loadIndex(); index.tabs = []
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let bytes = try encoder.encode(index)
        let decoded = try IndexEnvelope.decode(bytes)
        XCTAssertEqual(try IndexEnvelope.decode(bytes), decoded)
        XCTAssertEqual(decoded.tabs.first { $0.id == meta.tabID }?.createdAt, decoded.items[0].createdAt)
        let empty = try IndexEnvelope.decode(Data(#"{"version":2,"items":[],"tabs":[]}"#.utf8))
        XCTAssertEqual(empty.tabs[0].createdAt, Date(timeIntervalSince1970: 0))
    }

    func testAbruptProcessExitReleasesLockAndRecoversCommittedChange() throws {
        // These are real subprocess exits: no Swift error unwinding or deferred cleanup.
        for mode in ["before", "journal", "blob", "index", "delete"] {
            let store = try NotebookStore(root: root(), key: key)
            let meta = try item(store)
            if mode == "delete" { try store.writeImage(meta.id, png: image) }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = ["xctest", "-XCTest", "PrimsPasteCoreTests.NotebookJournalTests/testCrashWorker",
                                 Bundle(for: NotebookJournalTests.self).bundleURL.path]
            var environment = ProcessInfo.processInfo.environment
            environment["PRIMBOARD_CRASH_WORKER"] = "1"
            environment["PRIMBOARD_CRASH_ROOT"] = store.root.path
            environment["PRIMBOARD_CRASH_MODE"] = mode
            process.environment = environment
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            let exited = expectation(description: "Crash worker \(mode) exited")
            process.terminationHandler = { _ in exited.fulfill() }
            try process.run()
            wait(for: [exited], timeout: 30)
            if process.isRunning { kill(process.processIdentifier, SIGKILL); process.waitUntilExit(); XCTFail("Crash worker hung"); return }
            XCTAssertEqual(process.terminationStatus, 86, "Worker must reach the requested commit boundary: \(mode)")
            let reopened = try NotebookStore(root: store.root, key: key)
            if mode == "delete" {
                XCTAssertTrue(try reopened.loadIndex().items.isEmpty)
                XCTAssertFalse(FileManager.default.fileExists(atPath: reopened.imageURL(id: meta.id).path))
                XCTAssertFalse(FileManager.default.fileExists(atPath: reopened.blobURL(id: meta.id).path))
            } else {
                try assertRecovered(reopened, id: meta.id, revision: mode == "before" ? 1 : 2, body: mode == "before" ? oldBody : newBody)
            }
        }
    }

    func testCrashWorker() throws {
        guard ProcessInfo.processInfo.environment["PRIMBOARD_CRASH_WORKER"] == "1" else {
            throw XCTSkip("Invoked only by the real process-crash test")
        }
        let environment = ProcessInfo.processInfo.environment
        let path = try XCTUnwrap(environment["PRIMBOARD_CRASH_ROOT"])
        guard URL(fileURLWithPath: path).lastPathComponent.hasPrefix("primboard-journal-") else { XCTFail("Non-fixture root"); return }
        let store = try NotebookStore(root: URL(fileURLWithPath: path), key: key)
        let meta = try XCTUnwrap(store.loadIndex().items.first)
        let mode = try XCTUnwrap(environment["PRIMBOARD_CRASH_MODE"])
        store.transactionCheckpoint = { checkpoint in
            let matched: Bool
            switch (mode, checkpoint) {
            case ("before", .beforeJournal), ("journal", .journalPersisted), ("blob", .blobWritten),
                 ("index", .indexWritten), ("delete", .blobDeleted): matched = true
            default: matched = false
            }
            if matched { Darwin._exit(86) }
        }
        if mode == "delete" { try store.remove(meta.id) }
        else { _ = try store.updatePayload(meta.id, plaintext: newBody) }
        XCTFail("Requested crash checkpoint was not reached")
    }
}
