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

    /// The store sub-flows: shelf → detail → (sticker buy) apply picker, then
    /// the deck inspect off the shell's deck band. Evidence stills only — the
    /// taps after the first are tolerant (offer contents are seed-dependent).
    func testStoreFlowWalk() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetAll", "1", "-autoStore", "1", "-coins", "30", "-seed", "909"]
        app.launch()
        let tile = app.buttons["shelf-0"].firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 8), "store shelf missing")
        shot(app, "20-store")
        tile.tap()
        sleep(1)
        shot(app, "21-store-detail")

        // The BUY button's label carries the price ("BUY · ◉ 5") — match by prefix.
        let buy = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'BUY'")).firstMatch
        if buy.waitForExistence(timeout: 3) {
            buy.tap()
            sleep(1)
            shot(app, "22-card-picker")
        }
        // Back out of whatever the buy opened (picker / pack reveal / detail)
        // — close buttons ride the prompt bar's confirm, so tap through.
        for _ in 0..<3 {
            let close = app.buttons["✕"].firstMatch
            guard close.waitForExistence(timeout: 2) else { break }
            close.tap()
            sleep(1)
            let confirm = app.buttons["SKIP"].firstMatch
            if confirm.exists { confirm.tap(); sleep(1) }
        }

        // The detail must really be gone (a stuck detail covers the deck band).
        XCTAssertFalse(app.buttons["✕"].firstMatch.waitForExistence(timeout: 1),
                       "store detail did not close")
        let deck = app.buttons["DECK"].firstMatch
        XCTAssertTrue(deck.waitForExistence(timeout: 3), "deck band missing")
        XCTAssertTrue(deck.isHittable, "deck band covered")
        deck.tap()
        let inspectClose = app.buttons["✕"].firstMatch
        XCTAssertTrue(inspectClose.waitForExistence(timeout: 3), "deck inspect did not open")
        sleep(1)
        shot(app, "23-deck-inspect")
        sleep(1)
        shot(app, "23b-deck-inspect-settled")
    }
}
