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

    func testIconIsGoldFolioOnInk() throws {
        let url = brand.appendingPathComponent("icon.png")
        let img = try XCTUnwrap(NSImage(contentsOf: url))
        let tiff = try XCTUnwrap(img.tiffRepresentation)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        var ink = 0, gold = 0, cream = 0
        for y in stride(from: 0, to: rep.pixelsHigh, by: 8) {
            for x in stride(from: 0, to: rep.pixelsWide, by: 8) {
                guard let c = rep.colorAt(x: x, y: y) else { continue }
                let r = c.redComponent, g = c.greenComponent, b = c.blueComponent
                if r < 0.12 && g < 0.12 && b < 0.14 { ink += 1 }
                if r > 0.75 && g > 0.55 && b < 0.45 { gold += 1 }
                if r > 0.85 && g > 0.85 && b > 0.80 { cream += 1 }
            }
        }
        XCTAssertGreaterThan(ink, 200, "ink field missing")
        XCTAssertGreaterThan(gold, 20, "gold folio missing")
        XCTAssertLessThan(cream, gold, "icon should be gold folio, not cream sheets")
    }

    func testFolioSvgKeepsSpineAndFold() throws {
        let svg = try String(contentsOf: brand.appendingPathComponent("folio.svg"), encoding: .utf8)
        XCTAssertTrue(svg.contains("rect"))
        XCTAssertTrue(svg.contains("M72 30h50l24 24v116H72Z") || svg.contains("l24 24"))
        let icon = try String(contentsOf: brand.appendingPathComponent("icon.svg"), encoding: .utf8)
        XCTAssertTrue(icon.contains("#e8c547"))
        XCTAssertTrue(icon.contains("#0c0c0e"))
        XCTAssertTrue(icon.contains("M72 30h50l24 24v116H72Z"))
    }

    func testLockupsExist() {
        for name in ["lockup-paper.png", "lockup-ink.png", "folio-gold.svg", "folio-ink.svg"] {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: brand.appendingPathComponent(name).path),
                name
            )
        }
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
        XCTAssertTrue(text.contains("ATSApplicationFontsPath"))
    }

    func testBrandFontsVendored() {
        let fonts = brand.appendingPathComponent("fonts")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fonts.appendingPathComponent("InstrumentSans-Variable.ttf").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fonts.appendingPathComponent("IBMPlexMono-Regular.ttf").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fonts.appendingPathComponent("IBMPlexMono-Medium.ttf").path))
    }
}
