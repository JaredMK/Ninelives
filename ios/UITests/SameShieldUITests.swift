import XCTest

/// v6.96 SAME SHIELD / EMPTY SAME-POWER SLOT (batch items 4+5) — the deal
/// HUD's top-bar chips are pure SpriteKit, so the tests observe through the
/// `-helpReceipt 1` staging hook (DealViewController, the `-guessReceipt`
/// precedent): a UIKit label mirroring the scene's help panel
/// ("help:<title>|<body>") and, while no panel is up, the registered HUD
/// chip ids ("help:none chips=sameCharge,samePower,…").
///
/// Fixed window coordinates on the iPhone 17 simulator (402×874pt, safe-area
/// 62 top / 34 bottom), derived from DealScene.layoutChrome + DealTopBar.sync
/// for the harness deal (`-piles 9 -cards 39`, a fresh climb → NO Same-Power
/// equipped, so the dashed-gold EMPTY SLOT draws beside the shield mark):
///
///   HUD bar: y 70…110 (safeTop+8, height 40) → chip taps at y 90
///   sameCharge chip  x 167…199 (width/2-34 … width/2-2)  → tap (183, 90)
///   samePower slot   x 195…221 (empty slot is 26 wide)   → tap (214, 90)
///     (the 4pt hit inset overlaps the two frames, but chipId checks
///      sameCharge FIRST — x 183 hits only the shield, x 214 only the slot)
///   empty felt (201, 840): below the RESHUFFLE bar (y 776…810), inside the
///     reserved bottom gap — no pile, button, plaque, band or chip there.
final class SameShieldUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Same `-autoDeal` harness shape as InputTapUITests.launchDeal.
    private func launchDeal() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-resetAll", "1", "-autoDeal", "1",
                               "-piles", "9", "-cards", "39",
                               "-deck", "pink", "-tier", "regular", "-seed", "909",
                               "-helpReceipt", "1"]
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

    private func waitLabel(_ receipt: XCUIElement, _ pred: String,
                           _ args: String..., timeout: TimeInterval = 5,
                           message: String) {
        let p = NSPredicate(format: pred, argumentArray: args)
        let exp = XCTNSPredicateExpectation(predicate: p, object: receipt)
        XCTAssertEqual(XCTWaiter.wait(for: [exp], timeout: timeout), .completed, message)
    }

    /// Launch + settle helper: the deal-out cascade locks input while it runs.
    private func settledReceipt() -> (XCUIApplication, XCUIElement) {
        let app = launchDeal()
        let receipt = app.staticTexts["helpReceipt"]
        XCTAssertTrue(receipt.waitForExistence(timeout: 15),
                      "the -helpReceipt hook label never appeared")
        sleep(5)
        return (app, receipt)
    }

    // MARK: - item 5: the empty Same-Power slot is a registered chip

    /// With NO Same-Power equipped (a fresh climb), the top bar must register
    /// BOTH chips: the Same Shield mark AND the empty power slot beside it
    /// (the slot draws dashed-gold and hit-tests like a live chip). The chip
    /// ids ride the receipt's idle line; a harmless empty-felt tap primes it.
    func testEmptySamePowerSlotRegistersBesideSameShield() {
        let (app, receipt) = settledReceipt()
        tap(app, x: 201, y: 840)   // empty felt: clears selection, no help
        waitLabel(receipt, "label BEGINSWITH %@", "help:none chips=",
                  message: "the receipt never settled to the idle chip list")
        XCTAssertTrue(receipt.label.contains("sameCharge"),
                      "the Same Shield chip is not registered: \(receipt.label)")
        XCTAssertTrue(receipt.label.contains("samePower"),
                      "the empty Same-Power slot is not registered: \(receipt.label)")
        shot(app, "sameshield__empty-slot-registered")
    }

    // MARK: - item 4: TAP on the Same Shield chip shows its help

    /// Tap the shield chip → "Same Shield / Charges by a correct same call…";
    /// a tap on empty felt collapses the panel (the isHelpVisible gate).
    func testTapSameShieldShowsHelpAndFeltTapCollapses() {
        let (app, receipt) = settledReceipt()
        tap(app, x: 183, y: 90)
        waitLabel(receipt, "label == %@",
                  "help:Same Shield|Charges by a correct same call. Auto-saves a pile",
                  message: "tapping the Same Shield chip never showed its help")
        shot(app, "sameshield__tap-help")

        tap(app, x: 201, y: 840)   // empty felt: the collapse tap is consumed
        waitLabel(receipt, "label BEGINSWITH %@", "help:none",
                  message: "the empty-felt tap never collapsed the help panel")
        shot(app, "sameshield__tap-collapsed")
    }

    // MARK: - item 4: HOLD on the Same Shield chip shows the same help

    /// press(forDuration:) BLOCKS until the finger lifts (and event synthesis
    /// must run on the main thread — a background-queue press raises
    /// NSInternalInconsistencyException), so the panel can never be observed
    /// mid-hold. Instead the receipt hook LATCHES the last help it mirrored:
    /// after the press returns, "last=<title>|<body>" proves the hold path
    /// (onHold → hudChip → showHelp) showed exactly the shield's help, and
    /// the "help:none" prefix proves releasing hid it again.
    func testHoldSameShieldShowsHelp() {
        let (app, receipt) = settledReceipt()
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: 183, dy: 90)).press(forDuration: 1.0)
        waitLabel(receipt, "label BEGINSWITH %@", "help:none",
                  message: "releasing the hold never hid the help panel")
        XCTAssertTrue(receipt.label.contains(
            "last=Same Shield|Charges by a correct same call. Auto-saves a pile"),
                      "the hold never showed the Same Shield help: \(receipt.label)")
        shot(app, "sameshield__hold-help-latched")
    }

    // MARK: - item 5: TAP on the empty Same-Power slot

    /// The empty slot answers a tap like a live chip: "Same Power /
    /// None equipped".
    func testTapEmptySamePowerSlotShowsNoneEquipped() {
        let (app, receipt) = settledReceipt()
        tap(app, x: 214, y: 90)
        waitLabel(receipt, "label == %@",
                  "help:Same Power|None equipped",
                  message: "tapping the empty Same-Power slot never showed its help")
        shot(app, "sameshield__empty-slot-help")
    }
}
