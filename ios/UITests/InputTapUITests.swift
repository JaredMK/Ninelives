import XCTest

/// v6.93 INPUT ROUTER REGRESSION — after a pile tap brings up its card-info
/// panel, the FIRST tap on a call button must register the guess, not be
/// spent dismissing the info. `DealViewController.onTap`'s isHelpVisible
/// gate used to `return` on any non-pile tap, so the first HIGHER tap after
/// viewing a pile's info was eaten.
///
/// The deal board is SpriteKit — none of it sits in the accessibility tree —
/// so the test taps fixed window coordinates derived from DealScene's layout
/// constants for the harness deal (`-piles 9 -cards 39` → a 3×3 grid) on the
/// iPhone 17 simulator (402×874pt, safe-area 62 top / 34 bottom):
///
///   layoutChrome: rail at x 8…60; HIGHER slab y 286…444  → tap (34, 365)
///   rebuildBoardLayout (.full 96×134 cards): pile 1's card
///     x 70…166, y 290…424                               → tap (118, 357)
///
/// and OBSERVES the engine's truth through the `-guessReceipt 1` staging
/// hook (DealViewController): a UIKit label counting the "Guess …" entries
/// drained from the engine logbook after every action. A tap eaten by the
/// router never reaches the engine, so the counter stays at 0 — that is what
/// makes the reverted gate FAIL this test.
final class InputTapUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Same `-autoDeal` harness shape as DealFeedbackUITests.launchDeal.
    private func launchDeal(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-resetAll", "1", "-autoDeal", "1",
                               "-piles", "9", "-cards", "39",
                               "-deck", "pink", "-tier", "regular", "-seed", "909"] + extra
        app.launch()
        return app
    }

    private func tap(_ app: XCUIApplication, x: CGFloat, y: CGFloat) {
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: x, dy: y)).tap()
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    func testFirstCallButtonTapAfterPileInfoRegisters() {
        let app = launchDeal(["-guessReceipt", "1"])
        let receipt = app.staticTexts["guessReceipt"]
        XCTAssertTrue(receipt.waitForExistence(timeout: 15),
                      "the -guessReceipt hook label never appeared")
        sleep(5)   // the deal-out cascade settles (input locks while it runs)
        XCTAssertEqual(receipt.label, "guesses:0")

        // Tap pile 1: selects it AND surfaces its card-info panel (v6.88) —
        // the exact state the bug ate the next call-button tap from.
        tap(app, x: 118, y: 357)
        usleep(400_000)
        XCTAssertEqual(receipt.label, "guesses:0",
                       "selecting a pile must not register a guess")
        shot(app, "inputtap__1-pile-info")

        // THE GUARD: this FIRST tap on ▲ HIGHER must fire the guess. With the
        // old gate it only dismissed the info and the counter never moved.
        tap(app, x: 34, y: 365)
        let registered = NSPredicate(format: "label == %@", "guesses:1")
        let exp = XCTNSPredicateExpectation(predicate: registered, object: receipt)
        XCTAssertEqual(XCTWaiter.wait(for: [exp], timeout: 5), .completed,
                       "the first HIGHER tap after the pile info never reached the engine")
        shot(app, "inputtap__2-guess-registered")
    }
}
