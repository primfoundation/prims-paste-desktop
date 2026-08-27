import XCTest
@testable import PrimsPasteCore

final class CLIParserTests: XCTestCase {
    func testHelpAndOpen() {
        XCTAssertEqual(try CLIParser.parse(["help"]).get(), .help)
        XCTAssertEqual(try CLIParser.parse(["open"]).get(), .open)
        XCTAssertEqual(try CLIParser.parse(["tabs"]).get(), .tabs)
    }

    func testAddAndList() {
        let add = try? CLIParser.parse(["add", "--tab", "bugs", "--title", "cover blacks board", "--body", "detail"]).get()
        XCTAssertEqual(add, .add(tab: "bugs", title: "cover blacks board", body: "detail"))
        XCTAssertEqual(try CLIParser.parse(["list", "--tab", "bugs"]).get(), .list(tab: "bugs"))
        XCTAssertEqual(try CLIParser.parse(["list"]).get(), .list(tab: nil))
    }

    func testConvert() {
        XCTAssertEqual(
            try CLIParser.parse(["convert", "pp_bug_x", "docket"]).get(),
            .convert(id: "pp_bug_x", target: .docketTask)
        )
        XCTAssertEqual(
            try CLIParser.parse(["convert", "pp_1", "paseo"]).get(),
            .convert(id: "pp_1", target: .paseoAgent)
        )
    }

    func testBugsVerbs() {
        XCTAssertEqual(try CLIParser.parse(["bugs", "file"]).get(), .bugsFile)
        XCTAssertEqual(try CLIParser.parse(["bugs", "tasks"]).get(), .bugsTasks)
    }

    func testResolveTabByNameOrId() {
        let tabs = [
            BoardTab(id: "tab_bugs", title: "bugs", colorHex: "#8B2E2E"),
            BoardTab(id: "tab_x", title: "features-wanted", colorHex: "#C45C26"),
        ]
        XCTAssertEqual(CLIParser.resolveTab("bugs", tabs: tabs)?.id, "tab_bugs")
        XCTAssertEqual(CLIParser.resolveTab("tab_x", tabs: tabs)?.title, "features-wanted")
        XCTAssertNil(CLIParser.resolveTab("nope", tabs: tabs))
    }

    func testUnknownIsUsage() {
        if case .failure = CLIParser.parse(["wat"]) { } else { XCTFail("expected failure") }
        if case .failure = CLIParser.parse([]) { } else { XCTFail("expected failure") }
    }
}
