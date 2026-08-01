import XCTest

/// Evidence stills for the fidelity pass: real-tap walks through every menu
/// surface, attaching a screenshot per screen (extracted from the xcresult).
final class ScreenshotUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    private func tap(_ app: XCUIApplication, _ label: String, timeout: TimeInterval = 4) {
        let b = app.buttons[label].firstMatch
        XCTAssertTrue(b.waitForExistence(timeout: timeout), "missing button \(label)")
        b.tap()
    }

    func testMenuSurfacesWalk() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetAll", "1", "-skipGate", "1"]
        app.launch()
        XCTAssertTrue(app.buttons["CLIMB"].waitForExistence(timeout: 8))
        shot(app, "01-menu")

        tap(app, "CLIMB")
        XCTAssertTrue(app.buttons["START CLIMB"].waitForExistence(timeout: 4))
        shot(app, "02-deckselect")

        tap(app, "START CLIMB")
        XCTAssertTrue(app.buttons["≡"].waitForExistence(timeout: 6))
        sleep(1)
        shot(app, "03-map-fresh")

        tap(app, "≡")
        XCTAssertTrue(app.buttons["RESUME"].waitForExistence(timeout: 4))
        shot(app, "04-pause-sheet")
        tap(app, "QUIT TO MENU")

        XCTAssertTrue(app.buttons["CONTINUE"].waitForExistence(timeout: 4))
        shot(app, "05-menu-continue")

        tap(app, "HOW TO PLAY")
        XCTAssertTrue(app.buttons["NEXT"].waitForExistence(timeout: 4))
        shot(app, "06-howto-1")
        tap(app, "NEXT")
        shot(app, "07-howto-2")
        tap(app, "×")

        tap(app, "ZEN", timeout: 2)
        sleep(1)
        shot(app, "08-zen-select")
        tap(app, "←")

        tap(app, "STATS")
        sleep(1)
        shot(app, "09-stats-sheet")
        tap(app, "×")

        tap(app, "COLLECTION")
        sleep(1)
        shot(app, "10-collection")
        tap(app, "←")

        tap(app, "SETTINGS")
        sleep(1)
        shot(app, "11-settings")
    }
}
