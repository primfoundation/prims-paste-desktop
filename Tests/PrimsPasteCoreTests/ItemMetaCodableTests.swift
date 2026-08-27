import XCTest
@testable import PrimsPasteCore

final class ItemMetaCodableTests: XCTestCase {
    func testOldIndexWithoutNewFieldsStillLoads() throws {
        let json = """
        {
          "version": 1,
          "items": [{
            "id": "nb_old",
            "kind": "paste",
            "x": 1, "y": 2, "width": 3, "height": 4,
            "createdAt": "2026-08-27T21:04:11Z",
            "updatedAt": "2026-08-27T21:04:11Z",
            "bytes": 16,
            "fingerprint": "791d86ce8720"
          }]
        }
        """.data(using: .utf8)!
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let idx = try dec.decode(NotebookIndex.self, from: json)
        XCTAssertEqual(idx.items[0].caption, "")
        XCTAssertFalse(idx.items[0].looksLikeKey)
        XCTAssertNil(idx.items[0].keyKind)
        XCTAssertFalse(idx.items[0].hasImage)
        let created = ISO8601DateFormatter().date(from: "2026-08-27T21:04:11Z")!
        XCTAssertEqual(idx.items[0].day, ItemMeta.dayString(from: created))
    }

    func testRoundtripCaptionAndKeyFlags() throws {
        let meta = ItemMeta(
            id: "nb_x", kind: .paste, x: 8, y: 9, width: 10, height: 11,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            bytes: 5,
            fingerprint: "deadbeef",
            caption: "pypi token",
            looksLikeKey: true,
            keyKind: "entropy",
            day: "2023-11-14"
        )
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        let data = try enc.encode(NotebookIndex(items: [meta]))
        let text = String(data: data, encoding: .utf8) ?? ""
        XCTAssertFalse(text.contains("sk-"))
        XCTAssertTrue(text.contains("pypi token"))
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let back = try dec.decode(NotebookIndex.self, from: data)
        XCTAssertEqual(back.items[0], meta)
    }

    func testTiltIsStableAndSmall() {
        let a = ItemMeta(
            id: "nb_abc", kind: .note, x: 0, y: 0, width: 1, height: 1,
            createdAt: Date(), updatedAt: Date(), bytes: 1, day: "2026-08-27"
        )
        let b = ItemMeta(
            id: "nb_abc", kind: .note, x: 0, y: 0, width: 1, height: 1,
            createdAt: Date(), updatedAt: Date(), bytes: 1, day: "2026-08-27"
        )
        XCTAssertEqual(a.tilt, b.tilt)
        XCTAssertGreaterThanOrEqual(a.tilt, -4)
        XCTAssertLessThanOrEqual(a.tilt, 4)
    }
}
