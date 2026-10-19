import XCTest

/// Records frames for docs/demo.gif: a phone screenshot and the file text
/// after each edit. Only runs when PHONELIST_DEMO_DIR is set in the test
/// runner's environment (TEST_RUNNER_PHONELIST_DEMO_DIR for xcodebuild).
/// See scripts/record_demo.sh.
final class DemoRecording: XCTestCase {

    let seed = """
    ==========================================
    OVERVIEW

    paper
    observing
    code


    ==========================================
    PAPER

    * Finish the introduction
    * Make figure 3
        * Rerun the fit with the new priors
        * Regenerate the plot
    * Reply to co-author comments
      (they are in the shared doc)


    ==========================================
    OBSERVING

    * Submit the Keck proposal
    * Check the weather for Thursday

    """

    var app: XCUIApplication!
    var dumpPath: String!
    var demoDir: String!
    var frame = 0

    override func setUpWithError() throws {
        guard let dir = ProcessInfo.processInfo.environment["PHONELIST_DEMO_DIR"] else {
            throw XCTSkip("PHONELIST_DEMO_DIR not set")
        }
        demoDir = dir
        continueAfterFailure = false
        dumpPath = NSTemporaryDirectory() + "rdo-demo-dump.txt"
        app = XCUIApplication()
        app.launchArguments = ["-lastSectionTitle", "PAPER"]
        app.launchEnvironment = ["PHONELIST_SEED_TEXT": seed, "PHONELIST_DUMP_PATH": dumpPath]
        app.launch()
    }

    func capture(_ label: String) {
        RunLoop.current.run(until: Date().addingTimeInterval(0.7))
        let base = String(format: "%@/frame-%02d", demoDir, frame)
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: base + ".png"))
        let text = (try? String(contentsOfFile: dumpPath, encoding: .utf8)) ?? seed
        try? text.write(toFile: base + ".txt", atomically: true, encoding: .utf8)
        try? label.write(toFile: base + ".label", atomically: true, encoding: .utf8)
        frame += 1
    }

    func testRecord() {
        let checkboxes = app.buttons.matching(identifier: "checkbox")
        let texts = app.staticTexts.matching(identifier: "itemText")
        XCTAssertTrue(checkboxes.element(boundBy: 0).waitForExistence(timeout: 5))
        capture("The file, as a checklist")

        checkboxes.element(boundBy: 0).tap()
        capture("Tap: * becomes -")

        texts.element(boundBy: 4).swipeLeft()
        let wont = app.buttons["Won't do"]
        XCTAssertTrue(wont.waitForExistence(timeout: 3))
        wont.tap()
        capture("Swipe: * becomes ~")

        app.buttons["newItem"].tap()
        let editor = app.descendants(matching: .any).matching(identifier: "itemEditor").firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.typeText("Email the referee")
        app.buttons["doneEditing"].tap()
        capture("New item: appended to the section")

        texts.element(boundBy: 3).tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        app.buttons["outdent"].tap()
        app.buttons["doneEditing"].tap()
        capture("Outdent: two spaces removed")
    }
}
