import XCTest

/// Drives the app in the simulator. The app is seeded with `seed` via the
/// PHONELIST_SEED_TEXT hook and mirrors every save to PHONELIST_DUMP_PATH,
/// which these tests read back to check the exact file text produced.
final class PhoneListUITests: XCTestCase {

    let seed = """
    ==========================================
    MSOS

    * Push revision of ur PRs (or merge existing one)
    * M13 airflow transit search results

    * GET ALL CAR-912 M13 THROUGH AIRFLOW (i_car912airflow)
        * Rerun d5 on ones/zeros branch
        * Run sca02
    * Sign up for IPAC mentoring program
      https://example.com/wiki/spaces/ORG/pages/611360780/Mentoring+Program+2026


    ==========================================
    CPVs

    * Finalize CPV target vetting

    """

    var app: XCUIApplication!
    var dumpPath: String!

    override func setUp() {
        continueAfterFailure = false
        dumpPath = NSTemporaryDirectory() + "phonelist-dump-\(UUID().uuidString).txt"
        app = XCUIApplication()
        app.launchArguments = ["-lastSectionTitle", "MSOS"]
        app.launchEnvironment = ["PHONELIST_SEED_TEXT": seed, "PHONELIST_DUMP_PATH": dumpPath]
        app.launch()
    }

    func dump() -> String {
        (try? String(contentsOfFile: dumpPath, encoding: .utf8)) ?? "<no dump>"
    }

    func waitForDump(containing needle: String, timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if dump().contains(needle) { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTFail("dump never contained \(needle.debugDescription); dump:\n\(dump())", file: file, line: line)
    }

    var checkboxes: XCUIElementQuery { app.buttons.matching(identifier: "checkbox") }
    var editorQuery: XCUIElementQuery { app.descendants(matching: .any).matching(identifier: "itemEditor") }

    /// Save a screenshot for inspection. Directory comes from the
    /// PHONELIST_SNAP_DIR environment variable (pass it to xcodebuild as
    /// TEST_RUNNER_PHONELIST_SNAP_DIR); defaults to the temporary directory.
    func snap(_ name: String) {
        let dir = ProcessInfo.processInfo.environment["PHONELIST_SNAP_DIR"] ?? NSTemporaryDirectory()
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/ui-\(name).png"))
    }

    override func tearDown() {
        if let name = self.name.split(separator: " ").last?.replacingOccurrences(of: "]", with: "") {
            snap(name)
        }
    }
    var texts: XCUIElementQuery { app.staticTexts.matching(identifier: "itemText") }

    func testRendersSeed() {
        XCTAssertTrue(app.staticTexts["Push revision of ur PRs (or merge existing one)"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Sign up for IPAC mentoring program https://example.com/wiki/spaces/ORG/pages/611360780/Mentoring+Program+2026"].exists)
        XCTAssertEqual(checkboxes.count, 6)
    }

    func testToggleDoneOnlyTouchesMarkerLine() {
        XCTAssertTrue(checkboxes.element(boundBy: 0).waitForExistence(timeout: 5))
        checkboxes.element(boundBy: 0).tap()
        waitForDump(containing: "- Push revision of ur PRs (or merge existing one)\n* M13 airflow")
        checkboxes.element(boundBy: 0).tap()
        waitForDump(containing: "* Push revision of ur PRs (or merge existing one)\n* M13 airflow")
        // Continuation line of the last item is untouched after toggling it.
        checkboxes.element(boundBy: 5).tap()
        waitForDump(containing: "- Sign up for IPAC mentoring program\n  https://example")
        XCTAssertEqual(dump().components(separatedBy: "\n").count, seed.components(separatedBy: "\n").count)
    }

    func testSwipeLeftMarksWontDo() {
        let row = texts.element(boundBy: 1)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.swipeLeft()
        let btn = app.buttons["Won't do"]
        XCTAssertTrue(btn.waitForExistence(timeout: 3))
        btn.tap()
        waitForDump(containing: "~ M13 airflow transit search results")
    }

    func testEditTextRewrapsOnlyThatItem() {
        let row = texts.element(boundBy: 1)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        let editor = editorQuery.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.typeText(" and this makes the line long enough that it must wrap at eighty columns")
        snap("editing")
        app.buttons["doneEditing"].tap()
        waitForDump(containing: "* M13 airflow transit search results and this makes the line long enough that it\n  must wrap at eighty columns\n")
        // Neighbours untouched.
        XCTAssertTrue(dump().contains("* Push revision of ur PRs (or merge existing one)\n* M13"))
        XCTAssertTrue(dump().contains("columns\n\n* GET ALL"))
    }

    func testReturnKeyInsertsSiblingBelow() {
        let row = texts.element(boundBy: 1)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        let editor = editorQuery.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.typeText("\n")
        // Focus moved to a fresh empty item; type into it.
        let editor2 = editorQuery.firstMatch
        XCTAssertTrue(editor2.waitForExistence(timeout: 3))
        editor2.typeText("second thing")
        app.buttons["doneEditing"].tap()
        waitForDump(containing: "* M13 airflow transit search results\n* second thing\n\n* GET ALL")
    }

    func testNewItemAppendsAtEndOfSection() {
        let add = app.buttons["newItem"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        let editor = editorQuery.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        snap("newitem-empty")
        editor.typeText("brand new item")
        app.buttons["doneEditing"].tap()
        waitForDump(containing: "Mentoring+Program+2026\n* brand new item\n\n\n==========================================\nCPVs")
    }

    func testKeyboardIndentCarriesChildren() {
        let row = texts.element(boundBy: 2)   // GET ALL ...
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(editorQuery.firstMatch.waitForExistence(timeout: 3))
        app.buttons["indent"].firstMatch.tap()
        app.buttons["doneEditing"].tap()
        waitForDump(containing: "  * GET ALL CAR-912 M13 THROUGH AIRFLOW (i_car912airflow)\n      * Rerun d5 on ones/zeros branch\n      * Run sca02\n* Sign up")
    }
}
