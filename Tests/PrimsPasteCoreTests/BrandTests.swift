import AppKit
import XCTest

final class BrandTests: XCTestCase {
    private var brand: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("brand")
    }

    func testIconPngIs1024Square() throws {
        let url = brand.appendingPathComponent("icon.png")
        let img = try XCTUnwrap(NSImage(contentsOf: url))
        XCTAssertEqual(Int(img.size.width.rounded()), 1024)
        XCTAssertEqual(Int(img.size.height.rounded()), 1024)
    }

    func testAppIconIcnsHasDockSizes() throws {
        let url = brand.appendingPathComponent("AppIcon.icns")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let img = try XCTUnwrap(NSImage(contentsOf: url))
        let widths = Set(img.representations.map { Int($0.pixelsWide) })
        for size in [16, 32, 128, 256, 512, 1024] {
            XCTAssertTrue(widths.contains(size), "icns missing \(size)px, have \(widths)")
        }
    }

    func testPasteMarkHasAlphaAndGold() throws {
        let url = brand.appendingPathComponent("mark-paste.png")
        let img = try XCTUnwrap(NSImage(contentsOf: url))
        let tiff = try XCTUnwrap(img.tiffRepresentation)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        XCTAssertGreaterThan(rep.pixelsWide, 200)
        XCTAssertGreaterThan(rep.pixelsHigh, 200)
        var gold = 0
        var paper = 0
        var transparent = 0
        for y in stride(from: 0, to: rep.pixelsHigh, by: 4) {
            for x in stride(from: 0, to: rep.pixelsWide, by: 4) {
                guard let c = rep.colorAt(x: x, y: y) else { continue }
                if c.alphaComponent < 0.05 { transparent += 1; continue }
                let r = c.redComponent, g = c.greenComponent, b = c.blueComponent
                if r > 0.75 && g > 0.55 && b < 0.45 { gold += 1 }
                if r > 0.85 && g > 0.85 && b > 0.80 { paper += 1 }
            }
        }
        XCTAssertGreaterThan(transparent, 100, "mark should sit on a clear field")
        XCTAssertGreaterThan(paper, 100, "paper sheets missing")
        XCTAssertGreaterThan(gold, 4, "gold dog-ear missing")
    }

    func testIconHasInkPaperAndGold() throws {
        let url = brand.appendingPathComponent("icon.png")
        let img = try XCTUnwrap(NSImage(contentsOf: url))
        let tiff = try XCTUnwrap(img.tiffRepresentation)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        var ink = 0, paper = 0, gold = 0
        for y in stride(from: 0, to: rep.pixelsHigh, by: 8) {
            for x in stride(from: 0, to: rep.pixelsWide, by: 8) {
                guard let c = rep.colorAt(x: x, y: y) else { continue }
                let r = c.redComponent, g = c.greenComponent, b = c.blueComponent
                if r < 0.12 && g < 0.12 && b < 0.14 { ink += 1 }
                if r > 0.85 && g > 0.85 && b > 0.80 { paper += 1 }
                if r > 0.75 && g > 0.55 && b < 0.45 { gold += 1 }
            }
        }
        XCTAssertGreaterThan(ink, 200, "ink field missing")
        XCTAssertGreaterThan(paper, 40, "paper mark missing")
        XCTAssertGreaterThan(gold, 1, "gold fold missing")
    }

    func testLockupsExist() {
        for name in ["lockup-paper.png", "lockup-ink.png", "mark-ink.svg", "icon.svg"] {
            let url = brand.appendingPathComponent(name)
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), name)
        }
    }

    func testIconSvgKeepsBothSheetsAndGold() throws {
        let svg = try String(contentsOf: brand.appendingPathComponent("icon.svg"), encoding: .utf8)
        XCTAssertEqual(svg.components(separatedBy: "<path ").count - 1, 2)
        XCTAssertTrue(svg.contains("#e8c547"))
        XCTAssertTrue(svg.contains("#0c0c0e"))
        XCTAssertTrue(svg.contains("#f4f3ef"))
    }

    func testInfoPlistNamesTheIcon() throws {
        let plist = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Info.plist")
        let text = try String(contentsOf: plist, encoding: .utf8)
        XCTAssertTrue(text.contains("CFBundleIconFile"))
        XCTAssertTrue(text.contains("AppIcon"))
    }
}
