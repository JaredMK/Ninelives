import XCTest

/// MYSTERY-EVENT CHARACTER EVIDENCE — one screenshot per interaction state of
/// THE OLD JOKER, THE BEHEADED QUEEN and JUST A TWO, for design review.
///
/// Three driving routes, all EXISTING harness hooks (no app code added):
///   1. `-showJoker <offerKey>`  — forces one Old Joker offer at boot with
///      sample state (GameFlowController.showDebugJoker). The offer's own
///      buttons drive the resolution; one launch per branch (hooks fire once).
///   2. `-showOverlay mystery:<key>` — forces a Queen/Two mystery reveal at
///      boot (GameFlowController.showDebugOverlay). Reveal-only: its CONTINUE
///      just dismisses, so outcomes with a real follow-up (pickers, the store
///      detour, the ambush, the con/game conversations, folds that need state)
///      go through route 3.
///   3. The debug panel (`-debugAccess 1` → 🐞 float): arm a forced
///      mystery/joker key (primes the state each outcome guards on), convert a
///      reachable node to "?", walk onto it. This is the real map flow, so
///      follow-up screens (pickers, store, deal, conversations) actually run.
///
/// Attachment names are the final filenames: `<event>__<n>-<state>`.
final class EventCaptureUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Primitives

    private let baseArgs = ["-resetAll", "1", "-autoClimb", "1",
                            "-deck", "pink", "-tier", "regular", "-seed", "909"]

    @discardableResult
    private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = baseArgs + extra
        app.launch()
        XCTAssertTrue(app.buttons["≡"].waitForExistence(timeout: 20), "map shell missing")
        return app
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
        NSLog("[EVENTSHOT] %@", name)
    }

    @discardableResult
    private func tap(_ app: XCUIApplication, _ label: String, timeout: TimeInterval = 6) -> Bool {
        let b = app.buttons[label].firstMatch
        guard b.waitForExistence(timeout: timeout) else {
            XCTFail("missing button \(label)")
            return false
        }
        b.tap()
        return true
    }

    @discardableResult
    private func tapIfExists(_ app: XCUIApplication, _ label: String,
                             timeout: TimeInterval = 1.5) -> Bool {
        let b = app.buttons[label].firstMatch
        guard b.waitForExistence(timeout: timeout) else { return false }
        b.tap()
        return true
    }

    /// Every hittable button with EXACTLY this label (XCUI's `["label"]`
    /// subscript collapses to one element; this keeps them all).
    private func allButtons(_ app: XCUIApplication, _ label: String) -> [XCUIElement] {
        app.buttons.matching(NSPredicate(format: "label == %@", label))
            .allElementsBoundByIndex.filter { $0.exists && $0.isHittable }
    }

    /// Nth button whose label starts with `prefix` (top-to-bottom order), for
    /// the dynamically-labelled SELL rows on the Buyout/Refund offers.
    @discardableResult
    private func tapPrefixed(_ app: XCUIApplication, _ prefix: String, index: Int,
                             timeout: TimeInterval = 6) -> Bool {
        let q = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix))
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let els = q.allElementsBoundByIndex.filter { $0.exists && $0.isHittable }
                .sorted { $0.frame.minY < $1.frame.minY }
            if els.count > index { els[index].tap(); return true }
            usleep(250_000)
        }
        XCTFail("missing button \(prefix)[\(index)]")
        return false
    }

    /// Tap the Nth ENABLED card cell in a CardPickerViewController grid. The
    /// cells are unlabeled image buttons (~50×70); everything else on those
    /// screens is either labelled or a different size.
    @discardableResult
    private func tapCardCell(_ app: XCUIApplication, index: Int = 0,
                             timeout: TimeInterval = 8) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let cells = app.buttons.allElementsBoundByIndex.filter { b in
                guard b.exists, b.isHittable, b.isEnabled, b.label.isEmpty else { return false }
                let f = b.frame
                return (35...80).contains(f.width) && (50...110).contains(f.height)
            }.sorted {
                $0.frame.minY == $1.frame.minY ? $0.frame.minX < $1.frame.minX
                                               : $0.frame.minY < $1.frame.minY
            }
            if cells.count > index { cells[index].tap(); return true }
            usleep(300_000)
        }
        XCTFail("no card cell found")
        return false
    }

    // MARK: - Route 1: -showJoker

    /// Boot straight into a forced Old Joker offer; the map is behind him.
    private func launchJoker(_ key: String, marker: String) -> XCUIApplication {
        let app = launch(["-showJoker", key])
        XCTAssertTrue(app.buttons[marker].firstMatch.waitForExistence(timeout: 8),
                      "joker offer \(key) did not present")
        sleep(1)   // settle the present animation
        return app
    }

    /// The offer still, then `button`, then his return-line modal (GO ON).
    private func jokerOfferAndResult(_ key: String, marker: String,
                                     offerShot: String, button: String,
                                     resultShot: String) {
        let app = launchJoker(key, marker: marker)
        shot(app, offerShot)
        tap(app, button)
        XCTAssertTrue(app.buttons["GO ON"].firstMatch.waitForExistence(timeout: 8),
                      "\(key): no return-line modal after \(button)")
        sleep(1)
        shot(app, resultShot)
    }

    private func jokerOfferAndDecline(_ key: String, marker: String,
                                      resultShot: String) {
        let app = launchJoker(key, marker: marker)
        tap(app, "WALK AWAY")
        XCTAssertTrue(app.buttons["GO ON"].firstMatch.waitForExistence(timeout: 8),
                      "\(key): no decline modal")
        sleep(1)
        shot(app, resultShot)
    }

    // MARK: Old Joker — the offers

    func testJokerBuyoutOfferAcceptRich() {
        let app = launchJoker("buyout", marker: "WALK AWAY")
        shot(app, "buyout__1-offer")
        tapPrefixed(app, "SELL", index: 0)   // the rich row rides on top
        XCTAssertTrue(app.buttons["GO ON"].firstMatch.waitForExistence(timeout: 8))
        sleep(1)
        shot(app, "buyout__2-accept-rich")
    }

    func testJokerBuyoutAcceptCheap() {
        let app = launchJoker("buyout", marker: "WALK AWAY")
        tapPrefixed(app, "SELL", index: 1)
        XCTAssertTrue(app.buttons["GO ON"].firstMatch.waitForExistence(timeout: 8))
        sleep(1)
        shot(app, "buyout__3-accept-cheap")
    }

    func testJokerBuyoutDecline() {
        jokerOfferAndDecline("buyout", marker: "WALK AWAY",
                             resultShot: "buyout__4-decline")
    }

    func testJokerSwapOfferAccept() {
        jokerOfferAndResult("swap", marker: "TRADE",
                            offerShot: "swap__1-offer", button: "TRADE",
                            resultShot: "swap__2-accept")
    }

    func testJokerSwapDecline() {
        jokerOfferAndDecline("swap", marker: "TRADE", resultShot: "swap__3-decline")
    }

    func testJokerPurgeOfferAccept() {
        let app = launchJoker("purge", marker: "WALK AWAY")
        shot(app, "purge__1-offer")
        tapPrefixed(app, "PURGE", index: 0)          // "PURGE 3"
        sleep(2)
        shot(app, "purge__2-picker")
        for _ in 0..<3 {
            tapCardCell(app)
            tap(app, "PURGE")                        // the prompt-bar confirm
            sleep(2)
        }
        // His due: the curse reveal, then the return line.
        XCTAssertTrue(app.buttons["CONTINUE"].firstMatch.waitForExistence(timeout: 8),
                      "purge: no curse reveal")
        sleep(1)
        shot(app, "purge__3-curse-reveal")
        tap(app, "CONTINUE")
        XCTAssertTrue(app.buttons["GO ON"].firstMatch.waitForExistence(timeout: 8),
                      "purge: no return-line modal")
        sleep(1)
        shot(app, "purge__4-return-line")
    }

    func testJokerPurgeDecline() {
        jokerOfferAndDecline("purge", marker: "WALK AWAY",
                             resultShot: "purge__5-decline")
    }

    func testJokerRideOfferAccept() {
        // NOTE: the -showJoker path passes map: nil, so GET IN resolves to the
        // result modal; the real escorted travel is captured separately
        // (testDebugJokerRideTravel).
        jokerOfferAndResult("ride", marker: "GET IN",
                            offerShot: "ride__1-offer", button: "GET IN",
                            resultShot: "ride__2-accept")
    }

    func testJokerRideDecline() {
        jokerOfferAndDecline("ride", marker: "GET IN", resultShot: "ride__3-decline")
    }

    func testJokerCutOfferFreePick() {
        jokerOfferAndResult("cut", marker: "LET HIM PICK",
                            offerShot: "cut__1-offer", button: "LET HIM PICK",
                            resultShot: "cut__2-accept-free")
    }

    func testJokerCutPaidPick() {
        let app = launchJoker("cut", marker: "LET HIM PICK")
        tap(app, "PICK IT YOURSELF")
        sleep(2)
        shot(app, "cut__3-accept-paid-picker")
        tapCardCell(app)
        tap(app, "PURGE")
        XCTAssertTrue(app.buttons["GO ON"].firstMatch.waitForExistence(timeout: 8),
                      "cut: no return-line modal after paid pick")
        sleep(1)
        shot(app, "cut__4-accept-paid-return")
    }

    func testJokerCutDecline() {
        jokerOfferAndDecline("cut", marker: "LET HIM PICK",
                             resultShot: "cut__5-decline")
    }

    func testJokerMarkerAccept() {
        jokerOfferAndResult("marker", marker: "TAKE THE MARKER",
                            offerShot: "marker__1-offer", button: "TAKE THE MARKER",
                            resultShot: "marker__2-accept")
    }

    func testJokerMarkerDecline() {
        jokerOfferAndDecline("marker", marker: "TAKE THE MARKER",
                             resultShot: "marker__3-decline")
    }

    func testJokerBlindSwapAccept() {
        // The settled blind swap's return modal draws both faces (GAVE ↔ GOT).
        jokerOfferAndResult("blindSwap", marker: "ACCEPT",
                            offerShot: "blindSwap__1-offer", button: "ACCEPT",
                            resultShot: "blindSwap__2-accept-reveal")
    }

    func testJokerBlindSwapDecline() {
        jokerOfferAndDecline("blindSwap", marker: "ACCEPT",
                             resultShot: "blindSwap__3-decline")
    }

    func testJokerTwoDoorsOfferLeft() {
        let app = launchJoker("twoDoors", marker: "LEFT DOOR")
        shot(app, "twoDoors__1-offer")
        tap(app, "LEFT DOOR")   // goodIsLeft in the sample offer → Cache
        XCTAssertTrue(app.buttons["CONTINUE"].firstMatch.waitForExistence(timeout: 8),
                      "twoDoors: no chained reveal after LEFT")
        sleep(1)
        shot(app, "twoDoors__2-door-left")
    }

    func testJokerTwoDoorsRight() {
        let app = launchJoker("twoDoors", marker: "LEFT DOOR")
        tap(app, "RIGHT DOOR")  // the bad door → Toll
        XCTAssertTrue(app.buttons["CONTINUE"].firstMatch.waitForExistence(timeout: 8),
                      "twoDoors: no chained reveal after RIGHT")
        sleep(1)
        shot(app, "twoDoors__3-door-right")
    }

    func testJokerTwoDoorsDecline() {
        jokerOfferAndDecline("twoDoors", marker: "LEFT DOOR",
                             resultShot: "twoDoors__4-decline")
    }

    func testJokerInsuranceAccept() {
        let app = launchJoker("insurance", marker: "WALK AWAY")
        shot(app, "insurance__1-offer")
        tapPrefixed(app, "PAY", index: 0)   // "PAY 2"
        XCTAssertTrue(app.buttons["GO ON"].firstMatch.waitForExistence(timeout: 8))
        sleep(1)
        shot(app, "insurance__2-accept")
    }

    func testJokerInsuranceDecline() {
        jokerOfferAndDecline("insurance", marker: "WALK AWAY",
                             resultShot: "insurance__3-decline")
    }

    /// THE BUYBACK (v6.62): ONE item now — one SELL row, one price.
    func testJokerRefundOfferSellFirst() {
        let app = launchJoker("refund", marker: "WALK AWAY")
        shot(app, "refund__1-offer")
        tapPrefixed(app, "SELL", index: 0)
        XCTAssertTrue(app.buttons["GO ON"].firstMatch.waitForExistence(timeout: 8))
        sleep(1)
        shot(app, "refund__2-accept")
    }

    // (testJokerRefundSellSecond retired v6.62: the Refund now points at ONE
    // item, so there is no second SELL row to take.)

    func testJokerRefundDecline() {
        jokerOfferAndDecline("refund", marker: "WALK AWAY",
                             resultShot: "refund__3-decline")
    }

    func testJokerCollectPayUp() {
        // A collection, not an offer: PAY UP only, no walking away.
        jokerOfferAndResult("collect", marker: "PAY UP",
                            offerShot: "collect__1-offer", button: "PAY UP",
                            resultShot: "collect__2-pay-up")
    }

    func testJokerFreeShopAccept() {
        jokerOfferAndResult("freeShop", marker: "HAND IT OVER",
                            offerShot: "freeShop__1-offer", button: "HAND IT OVER",
                            resultShot: "freeShop__2-accept")
    }

    func testJokerFreeShopDecline() {
        jokerOfferAndDecline("freeShop", marker: "HAND IT OVER",
                             resultShot: "freeShop__3-decline")
    }

    func testJokerPurgeResetOfferDecline() {
        // The -showJoker sample has removalsBought = 0, so HALVE IT would
        // resolve to nothing; the real accept goes through the debug route
        // (testDebugJokerPurgeResetAccept). Here: the offer + the decline.
        let app = launchJoker("purgeReset", marker: "HALVE IT")
        shot(app, "purgeReset__1-offer")
        tap(app, "WALK AWAY")
        XCTAssertTrue(app.buttons["GO ON"].firstMatch.waitForExistence(timeout: 8))
        sleep(1)
        shot(app, "purgeReset__3-decline")
    }

    func testJokerEightsAccept() {
        jokerOfferAndResult("eights", marker: "COME TO THE MIDDLE",
                            offerShot: "eights__1-offer", button: "COME TO THE MIDDLE",
                            resultShot: "eights__2-accept")
    }

    func testJokerEightsDecline() {
        jokerOfferAndDecline("eights", marker: "COME TO THE MIDDLE",
                             resultShot: "eights__3-decline")
    }

    func testJokerThirstyGiveSome() {
        let app = launchJoker("thirsty", marker: "GIVE 1")
        shot(app, "thirsty__1-offer")
        tap(app, "+")
        tap(app, "+")
        tap(app, "GIVE 3")
        XCTAssertTrue(app.buttons["GO ON"].firstMatch.waitForExistence(timeout: 8),
                      "thirsty: no return-line modal after giving")
        sleep(1)
        shot(app, "thirsty__2-give-some")
    }

    func testJokerThirstyGiveNothing() {
        let app = launchJoker("thirsty", marker: "GIVE 1")
        tap(app, "\u{2212}")   // the stepper minus
        tap(app, "GIVE HIM NOTHING")
        XCTAssertTrue(app.buttons["GO ON"].firstMatch.waitForExistence(timeout: 8),
                      "thirsty: no return-line modal after stiffing him")
        sleep(1)
        shot(app, "thirsty__3-give-nothing")
    }

    func testJokerThirstReturnGifts() {
        let app = launchJoker("thirstReturn", marker: "TAKE THEM")
        shot(app, "thirstReturn__1-offer")
        tap(app, "TAKE THEM")
        // He empties his coat: the gift shelf (a free store).
        XCTAssertTrue(app.buttons["DONE"].firstMatch.waitForExistence(timeout: 10),
                      "thirstReturn: no gift shelf")
        sleep(1)
        shot(app, "thirstReturn__2-gift-shelf")
        tap(app, "DONE")
        XCTAssertTrue(app.buttons["GO ON"].firstMatch.waitForExistence(timeout: 8),
                      "thirstReturn: no return-line modal after the shelf")
        sleep(1)
        shot(app, "thirstReturn__3-return-line")
    }

    func testJokerThirstAmbush() {
        let app = launchJoker("thirstAmbush", marker: "FACE HIM")
        shot(app, "thirstAmbush__1-offer")
        tap(app, "FACE HIM")
        // Stiffed on the drink: he sets about you — a short, ugly deal.
        let deadline = Date().addingTimeInterval(12)
        while Date() < deadline, app.buttons["≡"].exists { usleep(400_000) }
        sleep(4)   // let the ambush deal lay out
        shot(app, "thirstAmbush__2-ambush-deal")
    }

    func testJokerDuplicateAccept() {
        let app = launchJoker("duplicate", marker: "COPY A CARD")
        shot(app, "duplicate__1-offer")
        tap(app, "COPY A CARD")
        sleep(2)
        shot(app, "duplicate__2-copy-picker")
        tapCardCell(app, index: 0)
        tap(app, "COPY")
        sleep(2)
        shot(app, "duplicate__3-replace-picker")
        tapCardCell(app, index: 1)   // the copy must replace a DIFFERENT card
        tap(app, "REPLACE")
        XCTAssertTrue(app.buttons["GO ON"].firstMatch.waitForExistence(timeout: 8),
                      "duplicate: no return-line modal")
        sleep(1)
        shot(app, "duplicate__4-return-line")
    }

    func testJokerDuplicateDecline() {
        jokerOfferAndDecline("duplicate", marker: "COPY A CARD",
                             resultShot: "duplicate__5-decline")
    }

    // MARK: - Route 2: -showOverlay mystery:<key> (reveal stills)

    private func mysteryReveal(_ key: String, shotName: String) {
        let app = launch(["-showOverlay", "mystery:\(key)"])
        XCTAssertTrue(app.buttons["CONTINUE"].firstMatch.waitForExistence(timeout: 8),
                      "mystery:\(key) reveal did not present")
        sleep(1)
        shot(app, shotName)
    }

    func testOverlayQueenCoinBonus()   { mysteryReveal("coinBonus",   shotName: "coinBonus__1-reveal") }
    func testOverlayQueenPriceOne()    { mysteryReveal("priceOne",    shotName: "priceOne__1-reveal") }
    func testOverlayQueenFreeRefresh() { mysteryReveal("freeRefresh", shotName: "freeRefresh__1-reveal") }
    func testOverlayQueenFreeRedeal()  { mysteryReveal("freeRedeal",  shotName: "freeRedeal__1-reveal") }
    func testOverlayQueenShieldCharge(){ mysteryReveal("shieldCharge",shotName: "shieldCharge__1-reveal") }
    func testOverlayQueenCoinDouble()  { mysteryReveal("coinDouble",  shotName: "coinDouble__1-reveal") }
    func testOverlayTwoCoinLoss()      { mysteryReveal("coinLoss",    shotName: "coinLoss__1-reveal") }
    func testOverlayTwoPriceDouble()   { mysteryReveal("priceDouble", shotName: "priceDouble__1-reveal") }
    func testOverlayTwoStickerTheft()  { mysteryReveal("stickerTheft",shotName: "stickerTheft__1-reveal") }
    func testOverlayTwoItemTheft()     { mysteryReveal("itemTheft",   shotName: "itemTheft__1-reveal") }

    // MARK: - v6.55 curse presentation evidence

    /// The curse specimen sheet (`-curseSheet 1`): every cursed sticker's
    /// chip + label + help. Run pre- and post-art-change; the extracted PNG
    /// is renamed `curse-art__before` / `curse-art__after` on export.
    func testCurseSheetSpecimen() {
        let app = launch(["-curseSheet", "1"])
        sleep(1)
        shot(app, "curse-art")
    }

    /// JUST A TWO's curse application (v6.55): the reveal shows the afflicted
    /// CARD wearing its curse chip (not a lone chip); tapping the card reads
    /// the curse's registry help.
    func testOverlayTwoCursedSticker() {
        let app = launch(["-showOverlay", "mystery:cursedSticker"])
        XCTAssertTrue(app.buttons["CONTINUE"].firstMatch.waitForExistence(timeout: 8),
                      "mystery:cursedSticker reveal did not present")
        let cell = app.buttons["curseCell"].firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 6), "no cursed-card cell in the well")
        sleep(1)
        shot(app, "two-curse-application__1-cards")
        cell.tap()
        sleep(1)
        shot(app, "two-curse-application__2-curse-help")
    }

    // MARK: - Route 3: the debug panel on a live map

    /// The armed event's own marker buttons, per family.
    private func markersFor(_ family: String) -> [String] {
        switch family {
        case "mysteryOverlay": return ["CONTINUE"]
        case "mammaLie":       return ["GIVE ALL YOUR COINS"]
        case "twoGame":        return ["RED"]
        case "jokerOffer":     return ["WALK AWAY", "PAY UP", "TAKE THEM",
                                       "FACE HIM", "GIVE 1", "TAKE THE JOKER",
                                       "HALVE IT", "GET IN"]
        default:               return ["CONTINUE"]
        }
    }

    private func openDebugPanel(_ app: XCUIApplication) {
        let bug = app.buttons["🐞"].firstMatch
        XCTAssertTrue(bug.waitForExistence(timeout: 6), "debug float missing")
        bug.tap()
        // A tap landing mid-re-render can sink into whatever is behind the
        // float; the panel's own header is the proof it actually opened.
        if !app.staticTexts["🐞 DEBUG"].firstMatch.waitForExistence(timeout: 3) {
            bug.tap()
            XCTAssertTrue(app.staticTexts["🐞 DEBUG"].firstMatch.waitForExistence(timeout: 3),
                          "debug panel never opened")
        }
        sleep(1)
    }

    /// The row's ARM NEXT ? button, identified by Y-ORDER among the EXISTING
    /// (not merely hittable) arm buttons — counting only hittable ones
    /// misidentifies the row the moment the other row is clipped at a
    /// viewport edge. Scrolls page-wise until that button is on screen
    /// (one app-level swipeUp ≈ 685pt, measured; slow drags lose to the
    /// panel's buttons and fast short drags flick ~1200pt on momentum).
    @discardableResult
    private func revealArmRow(_ app: XCUIApplication, row: Int) -> XCUIElement? {
        for _ in 0..<16 {
            let arms = app.buttons.matching(NSPredicate(format: "label == %@", "ARM NEXT ?"))
                .allElementsBoundByIndex.filter { $0.exists }
                .sorted { $0.frame.midY < $1.frame.midY }
            guard arms.count > row else { return nil }
            let target = arms[row]
            if target.isHittable { return target }
            if target.frame.midY > 700 { app.swipeUp() } else { app.swipeDown() }
            usleep(300_000)
        }
        return nil
    }

    /// Cycle a picker row (◀ ▶ + name label) toward `nameLabel`, then tap the
    /// row's ARM NEXT ?. `row` 0 = Old Joker, 1 = Queen/Two mystery. The fast
    /// path fires `taps` cached-cycler taps; the tail re-queries and keeps
    /// tapping until a fresh snapshot shows the label (tap counts are NOT
    /// trusted — synthetic taps on these custom controls can drop or double).
    private func armDebugKey(_ app: XCUIApplication, row: Int, nameLabel: String,
                             taps: Int, backward: Bool) {
        func labelVisible() -> Bool {
            app.staticTexts.allElementsBoundByIndex.contains { $0.label == nameLabel }
        }
        guard let arm = revealArmRow(app, row: row) else {
            // DIAGNOSTIC: what is actually on screen when the row won't show?
            NSLog("[ARMFAIL] hittable buttons: %@",
                  app.buttons.allElementsBoundByIndex
                    .filter { $0.exists && $0.isHittable }
                    .map { "\($0.label)@\(Int($0.frame.midY))" }
                    .joined(separator: " | "))
            shot(app, "armfail")
            XCTFail("arm row \(row) not on screen"); return
        }
        let rowY = arm.frame.midY
        guard let cycler = allButtons(app, backward ? "◀" : "▶")
            .first(where: { abs($0.frame.midY - rowY) < 24 }) else {
            XCTFail("no cycler near arm row"); return
        }
        for _ in 0..<taps { cycler.tap(); usleep(250_000) }
        let deadline = Date().addingTimeInterval(120)
        while !labelVisible(), Date() < deadline {
            guard let c = allButtons(app, backward ? "◀" : "▶")
                .first(where: { abs($0.frame.midY - rowY) < 24 }) else {
                _ = revealArmRow(app, row: row); continue
            }
            c.tap()
            usleep(250_000)
        }
        XCTAssertTrue(labelVisible(), "debug row never reached \(nameLabel)")
        guard let arm2 = revealArmRow(app, row: row) else { XCTFail("arm row gone"); return }
        arm2.tap()
        usleep(300_000)
    }

    /// Convert a reachable node to "?" — the "+? NODE HERE" button just under
    /// the given arm row. If it sits below the viewport's hittable edge the
    /// tap goes through a raw coordinate on the button's own frame (XCUI's
    /// hittability is safe-area-conservative; the app takes the touch fine —
    /// proved on the v6.62 debug-route captures).
    private func convertNodeToMystery(_ app: XCUIApplication, row: Int) {
        guard let arm = revealArmRow(app, row: row) else {
            XCTFail("arm row \(row) not on screen for convert"); return
        }
        let rowY = arm.frame.midY
        let candidates = app.buttons.matching(NSPredicate(format: "label == %@", "+? NODE HERE"))
            .allElementsBoundByIndex
            .filter { $0.exists && $0.frame.midY > rowY }
            .sorted { $0.frame.midY < $1.frame.midY }
        guard let b = candidates.first else {
            XCTFail("no +? NODE HERE under row \(row)"); return
        }
        if b.isHittable { b.tap() } else {
            b.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        usleep(300_000)
    }

    private func closeDebugPanel(_ app: XCUIApplication) {
        if !tapIfExists(app, "×", timeout: 2) {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.04)).tap()
        }
        sleep(1)
    }

    /// One marker of the armed event is on screen.
    private func eventVisible(_ app: XCUIApplication, _ markers: [String]) -> Bool {
        markers.contains { app.buttons[$0].firstMatch.exists }
    }

    /// Pack reveals also carry a CONTINUE — tell them apart from the mystery
    /// reveal and dismiss them, so probing never mistakes one for the event.
    private func dismissPackIfUp(_ app: XCUIApplication) -> Bool {
        guard app.buttons["VIEW CARDS IN PLAY"].firstMatch.exists else { return false }
        _ = tapIfExists(app, "SKIP", timeout: 1)
        _ = tapIfExists(app, "✕", timeout: 1)
        sleep(1)
        return true
    }

    /// Recover from walking a probe tap into a DEAL: the debug panel rides
    /// over the deal, so WIN NOW ends it, the cleared summary returns to the
    /// map, and a fresh reachable node gets converted (the armed key survives
    /// — it is only consumed when a ? node actually fires).
    private func recoverFromDeal(_ app: XCUIApplication, row: Int) -> Bool {
        sleep(4)   // let the deal's cascade finish laying out
        openDebugPanel(app)
        let win = app.buttons["WIN NOW"].firstMatch
        guard win.waitForExistence(timeout: 5), win.isHittable else { return false }
        win.tap()   // the panel closes itself; the cleared summary follows
        sleep(2)
        if !tapIfExists(app, "CONTINUE", timeout: 6) {
            _ = tapIfExists(app, "GO ON", timeout: 2)
        }
        sleep(2)
        guard app.buttons["≡"].firstMatch.waitForExistence(timeout: 6) else { return false }
        openDebugPanel(app)
        convertNodeToMystery(app, row: row)
        closeDebugPanel(app)
        return true
    }

    /// Tap reachable map nodes until the armed event presents. Only legal
    /// next nodes answer a tap, so blind probing is safe — but a wrong one
    /// can walk into a deal (recovered via WIN NOW when `recoverDeals`,
    /// otherwise fatal to this attempt) or a store/pack (recoverable).
    /// `reverse` rotates the probe order between attempts.
    @discardableResult
    private func probeForEvent(_ app: XCUIApplication, markers: [String],
                               reverse: Bool = false, row: Int = 0,
                               recoverDeals: Bool = false) -> Bool {
        var ys: [CGFloat] = [0.72, 0.62, 0.80, 0.52, 0.42, 0.32]
        var xs: [CGFloat] = [0.50, 0.28, 0.72, 0.16, 0.84, 0.40, 0.60]
        if reverse { ys.reverse(); xs.reverse() }
        for y in ys {
            for x in xs {
                app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)).tap()
                let deadline = Date().addingTimeInterval(3)
                while Date() < deadline {
                    if eventVisible(app, markers) { return true }
                    if dismissPackIfUp(app) { break }
                    if !app.buttons["≡"].firstMatch.exists { break }   // left the map
                    usleep(250_000)
                }
                if eventVisible(app, markers) { return true }
                if dismissPackIfUp(app) { continue }
                if tapIfExists(app, "GO TO MAP", timeout: 1) { sleep(1); continue }
                if !app.buttons["≡"].firstMatch.exists {   // walked into a deal
                    if recoverDeals, recoverFromDeal(app, row: row) { continue }
                    return false
                }
            }
        }
        return false
    }

    /// Probing can leave the map's key legend open (the "?" shell button);
    /// close it so aftermath shots show the plain map.
    private func closeMapLegend(_ app: XCUIApplication) {
        if app.staticTexts["Home"].firstMatch.exists {
            _ = tapIfExists(app, "?", timeout: 1)
            sleep(1)
        }
    }

    /// Full debug-route setup: fresh climb → panel → arm `nameLabel` on `row`
    /// (cycled `taps` times, ◀ when `backward`) → convert a reachable node →
    /// close → walk onto it. Retries once with a rotated probe order if the
    /// first walk lands in a deal.
    private func driveToArmedEvent(row: Int, nameLabel: String, taps: Int,
                                   backward: Bool, markers: [String]) -> XCUIApplication {
        for attempt in 0..<2 {
            let app = launch(["-debugAccess", "1"])
            openDebugPanel(app)
            armDebugKey(app, row: row, nameLabel: nameLabel, taps: taps, backward: backward)
            convertNodeToMystery(app, row: row)
            closeDebugPanel(app)
            if probeForEvent(app, markers: markers, reverse: attempt > 0,
                             row: row, recoverDeals: true) {
                sleep(1)
                return app
            }
            app.terminate()
        }
        XCTFail("armed event \(nameLabel) never presented")
        return launch(["-debugAccess", "1"])   // unreachable; keeps the type happy
    }

    /// The reveal + whatever CONTINUE leads to, per follow-up kind.
    private func mysteryViaDebug(nameLabel: String, taps: Int, backward: Bool,
                                 revealShot: String, followUp: String) {
        let app = driveToArmedEvent(row: 1, nameLabel: nameLabel, taps: taps,
                                    backward: backward,
                                    markers: markersFor("mysteryOverlay"))
        shot(app, revealShot)
        tap(app, "CONTINUE")
        switch followUp {
        case "none":
            break
        case "mapCollect":
            usleep(400_000)
            closeMapLegend(app)
            shot(app, revealShot.replacingOccurrences(of: "1-reveal", with: "2-collect"))
        case "applyPicker":
            sleep(2)
            shot(app, revealShot.replacingOccurrences(of: "1-reveal", with: "2-picker"))
            tapCardCell(app)
            tap(app, "APPLY")
            sleep(2)
        case "removalPicker":
            sleep(2)
            shot(app, revealShot.replacingOccurrences(of: "1-reveal", with: "2-picker"))
            tapCardCell(app)
            tap(app, "PURGE")
            sleep(2)
        case "stripPicker":
            sleep(2)
            shot(app, revealShot.replacingOccurrences(of: "1-reveal", with: "2-picker"))
            tapCardCell(app)
            tap(app, "STRIP")
            sleep(2)
        case "swapPicker":
            sleep(2)
            shot(app, revealShot.replacingOccurrences(of: "1-reveal", with: "2-picker"))
            tapCardCell(app)
            tap(app, "SWAP")
            sleep(2)
        case "store":
            XCTAssertTrue(app.buttons["shelf-0"].waitForExistence(timeout: 10),
                          "store detour did not open")
            sleep(1)
            shot(app, revealShot.replacingOccurrences(of: "1-reveal", with: "2-store"))
        case "ambushDeal":
            let deadline = Date().addingTimeInterval(12)
            while Date() < deadline, app.buttons["≡"].exists { usleep(400_000) }
            sleep(4)
            shot(app, revealShot.replacingOccurrences(of: "1-reveal", with: "2-deal"))
        default:
            break
        }
    }

    // MARK: Queen — interactive outcomes (debug route)

    func testMysteryStickerPack() {
        mysteryViaDebug(nameLabel: "♛ stickerPack", taps: 1, backward: false,
                        revealShot: "stickerPack__1-reveal", followUp: "applyPicker")
    }

    func testMysteryFreeRemoval() {
        mysteryViaDebug(nameLabel: "♛ freeRemoval", taps: 2, backward: false,
                        revealShot: "freeRemoval__1-reveal", followUp: "removalPicker")
    }

    func testMysteryGiftCard() {
        mysteryViaDebug(nameLabel: "♛ giftCard", taps: 11, backward: false,
                        revealShot: "giftCard__1-reveal", followUp: "swapPicker")
    }

    func testMysteryStore() {
        mysteryViaDebug(nameLabel: "♛ store", taps: 5, backward: false,
                        revealShot: "store__1-reveal", followUp: "store")
    }

    func testMysteryJoker() {
        mysteryViaDebug(nameLabel: "♛ joker", taps: 4, backward: false,
                        revealShot: "joker__1-reveal", followUp: "mapCollect")
    }

    /// THE CLEANSE only exists while a curse sits on a card — so first let
    /// `-showOverlay mystery:cursedSticker` plant one (the hook APPLIES the
    /// outcome to the live climb, not just shows it), then arm her strip and
    /// walk it. One panel session, one walk. (The older two-walk version —
    /// curse via a debug-armed node, then re-open the panel — flaked on the
    /// second panel open; this route has a single panel session.)
    func testMysteryCleanse() {
        let app = launch(["-showOverlay", "mystery:cursedSticker", "-debugAccess", "1"])
        XCTAssertTrue(app.buttons["CONTINUE"].firstMatch.waitForExistence(timeout: 8),
                      "the cursedSticker reveal did not present")
        sleep(1)
        shot(app, "cursedSticker__1-reveal")
        tap(app, "CONTINUE")
        sleep(2)
        // A curse now sits in the deck — her Cleanse will land for real.
        openDebugPanel(app)
        armDebugKey(app, row: 1, nameLabel: "♛ stickerStrip", taps: 3, backward: false)
        convertNodeToMystery(app, row: 1)
        closeDebugPanel(app)
        XCTAssertTrue(probeForEvent(app, markers: markersFor("mysteryOverlay"),
                                    row: 1, recoverDeals: true),
                      "the Cleanse never presented")
        sleep(1)
        shot(app, "stickerStrip__1-reveal")
        tap(app, "CONTINUE")
        sleep(2)
        shot(app, "stickerStrip__2-picker")
        tapCardCell(app)
        tap(app, "STRIP")
        sleep(2)
    }

    // MARK: Two — interactive outcomes (debug route)

    func testMysteryCards() {
        mysteryViaDebug(nameLabel: "2 cards", taps: 10, backward: true,
                        revealShot: "cards__1-reveal", followUp: "mapCollect")
    }

    func testMysteryAmbush() {
        mysteryViaDebug(nameLabel: "2 ambush", taps: 7, backward: true,
                        revealShot: "ambush__1-reveal", followUp: "ambushDeal")
    }

    func testMysteryShieldDrain() {
        // The -showOverlay hook can't reach this: an empty shield folds the
        // outcome to a Toll. The debug arm primes the charge.
        mysteryViaDebug(nameLabel: "2 shieldDrain", taps: 3, backward: true,
                        revealShot: "shieldDrain__1-reveal", followUp: "none")
    }

    // MARK: Two — THE CON (mammaLie)

    private func mammaCon(branch: String, branchShot: String?) {
        let app = driveToArmedEvent(row: 1, nameLabel: "2 mammaLie",
                                    taps: 2, backward: true,
                                    markers: markersFor("mammaLie"))
        shot(app, "mammaLie__1-con")
        tap(app, branch)
        if let branchShot {
            XCTAssertTrue(app.buttons["CONTINUE"].firstMatch.waitForExistence(timeout: 8),
                          "mammaLie: no aftermath after \(branch)")
            sleep(1)
            shot(app, branchShot)
        } else {
            sleep(2)   // walked away — straight back to the map
            closeMapLegend(app)
            shot(app, "mammaLie__4-walk-away")
        }
    }

    func testMysteryMammaLieCoins() {
        mammaCon(branch: "GIVE ALL YOUR COINS", branchShot: "mammaLie__2-give-coins")
    }

    func testMysteryMammaLieJoker() {
        mammaCon(branch: "GIVE A ★ JOKER", branchShot: "mammaLie__3-give-joker")
    }

    func testMysteryMammaLieWalkAway() {
        mammaCon(branch: "WALK AWAY", branchShot: nil)
    }

    // MARK: Two — THE TWO'S GAME

    /// v6.65: the game is a RED-or-BLACK call on the hidden card's color (the
    /// higher/lower/same pivot call is gone). The hidden card is seeded per
    /// node — seed 909's first armed node rolls K♥ (red), so RED is the
    /// winning call here and BLACK loses; both aftermaths are captured.
    private func twoGame(call: String, resultShot: String) {
        let app = driveToArmedEvent(row: 1, nameLabel: "2 twoGame",
                                    taps: 1, backward: true,
                                    markers: markersFor("twoGame"))
        shot(app, "twoGame__1-con")
        tap(app, call)
        XCTAssertTrue(app.buttons["CONTINUE"].firstMatch.waitForExistence(timeout: 8),
                      "twoGame: no aftermath after \(call)")
        sleep(1)
        shot(app, resultShot)
    }

    func testMysteryTwoGameRed()   { twoGame(call: "RED",   resultShot: "twoGame__2-call-red") }
    func testMysteryTwoGameBlack() { twoGame(call: "BLACK", resultShot: "twoGame__3-call-black") }

    // MARK: - v6.55 review stills (map pack count + mystery Same-Power reveal)

    /// A live map still for the pack-node card-count badge legibility pass.
    /// The badge rides pack nodes with packCount ≥ 3 (the packStack compose);
    /// seed 909's opening rows carry one in frame.
    func testMapPackCountBadge() {
        let app = launch([])
        sleep(1)   // settle the map entrance + edge bake
        closeMapLegend(app)   // the first-visit key legend covers the right lanes
        shot(app, "map-pack-count")
    }

    /// The Mystery Same-Power buy → shake/flash → reveal. Drives the store
    /// demo with deep pockets, refreshing the shelf until the ❓ slot rolls
    /// in (its detail's buy bar reads "BUY & REVEAL · ◉ N"), then buys it and
    /// captures a mid-animation frame plus the settled reveal panel.
    func testMysterySamePowerReveal() {
        mysteryRevealRun(hold: false)
    }

    /// Same flow with `-revealHold 1`: the beat HOLDS its mid-shake pose
    /// quiescent, so the screenshot daemon (which waits out live tweens)
    /// captures a true mid-animation frame.
    func testMysterySamePowerRevealHold() {
        mysteryRevealRun(hold: true)
    }

    private func mysteryRevealRun(hold: Bool) {
        let app = XCUIApplication()
        app.launchArguments = ["-resetAll", "1", "-autoStore", "1", "-coins", "999",
                               "-deck", "pink", "-tier", "regular", "-seed", "909"]
            + (hold ? ["-revealHold", "1"] : [])
        app.launch()
        XCTAssertTrue(app.buttons["shelf-0"].waitForExistence(timeout: 20), "store missing")
        let buyQuery = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "BUY & REVEAL"))
        let refreshQuery = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "↻ RESTOCK"))
        var bought = false
        for _ in 0..<25 where !bought {
            for slot in 0..<6 {
                let tile = app.buttons["shelf-\(slot)"].firstMatch
                guard tile.exists, tile.isHittable else { continue }
                tile.tap()
                usleep(400_000)
                let buy = buyQuery.firstMatch
                if buy.waitForExistence(timeout: 1.5), buy.isEnabled {
                    let t0 = Date()
                    buy.tap()
                    // The screenshot daemon waits out live tweens, so at true
                    // speed this frame lands at the swap; under -revealHold
                    // the mid-shake pose is HELD quiescent and captured.
                    shot(app, hold ? "mystery-reveal__1-shake" : "mystery-reveal__1-swap")
                    let revealed = app.buttons["KEEP & EQUIP"].firstMatch
                    XCTAssertTrue(revealed.waitForExistence(timeout: 12),
                                  "mystery reveal panel never showed")
                    NSLog("[EVENTSHOT] reveal panel appeared %.2fs after buy tap (hold=%@)",
                          Date().timeIntervalSince(t0), hold ? "YES" : "no")
                    sleep(1)
                    shot(app, "mystery-reveal__2-revealed")
                    bought = true
                    break
                }
                _ = tapIfExists(app, "✕", timeout: 1)
                usleep(300_000)
            }
            if !bought {
                let refresh = refreshQuery.firstMatch
                guard refresh.waitForExistence(timeout: 2), refresh.isEnabled else { break }
                refresh.tap()
                // The reroll confirms through the shared prompt bar.
                let yes = app.buttons["RESTOCK"].firstMatch
                guard yes.waitForExistence(timeout: 2) else { break }
                yes.tap()
                usleep(600_000)
            }
        }
        XCTAssertTrue(bought, "no mystery Same-Power slot rolled within the refresh budget")
    }

    // MARK: Old Joker — states the -showJoker hook can't reach (debug route)

    /// jokerForPillars is NOT wired into -showJoker (no case in
    /// showDebugJoker) — the debug panel arm is the only path to the offer.
    func testDebugJokerForPillarsAccept() {
        let app = driveToArmedEvent(row: 0, nameLabel: "jokerForPillars",
                                    taps: 4, backward: true,
                                    markers: markersFor("jokerOffer"))
        shot(app, "jokerForPillars__1-offer")
        tap(app, "TAKE THE JOKER")
        XCTAssertTrue(app.buttons["GO ON"].firstMatch.waitForExistence(timeout: 8),
                      "jokerForPillars: no return-line modal")
        sleep(1)
        shot(app, "jokerForPillars__2-accept")
    }

    func testDebugJokerForPillarsDecline() {
        let app = driveToArmedEvent(row: 0, nameLabel: "jokerForPillars",
                                    taps: 4, backward: true,
                                    markers: markersFor("jokerOffer"))
        tap(app, "WALK AWAY")
        XCTAssertTrue(app.buttons["GO ON"].firstMatch.waitForExistence(timeout: 8))
        sleep(1)
        shot(app, "jokerForPillars__3-decline")
    }

    /// The -showJoker sample has removalsBought = 0, so its HALVE IT silently
    /// folds to nothing; the debug arm primes the ladder (removalsBought = 2)
    /// and the real "Halved" resolution runs.
    func testDebugJokerPurgeResetAccept() {
        let app = driveToArmedEvent(row: 0, nameLabel: "purgeReset",
                                    taps: 11, backward: false,
                                    markers: markersFor("jokerOffer"))
        tapPrefixed(app, "HALVE IT", index: 0)
        XCTAssertTrue(app.buttons["GO ON"].firstMatch.waitForExistence(timeout: 8),
                      "purgeReset: no return-line modal")
        sleep(1)
        shot(app, "purgeReset__2-accept-halved")
    }

    /// The real RIDE follow-up: he drives — the map walks, he peels off, and
    /// the shop opens behind him. (The -showJoker path passes map: nil, which
    /// can only resolve to the result modal.)
    func testDebugJokerRideTravel() {
        let app = driveToArmedEvent(row: 0, nameLabel: "ride",
                                    taps: 3, backward: false,
                                    markers: markersFor("jokerOffer"))
        tap(app, "GET IN")
        XCTAssertTrue(app.buttons["shelf-0"].waitForExistence(timeout: 20),
                      "ride: the shop never opened after the drive")
        sleep(1)
        shot(app, "ride__4-travel-store")
    }

    // MARK: - v6.55 wave 2 stills (consent prompts + Queen-boon reminders)

    /// Debug-deal launcher for the consent-prompt stills. The deal boots with
    /// the launcher's own `-autoDeal` dials; the v6.55 hooks stage the parked
    /// state (DealController `-dealPillar` / `-dealSamePower`, DealViewController
    /// `-demoPrompt`) — simctl can't produce these dice-rolled states on cue.
    private func launchDealPrompt(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-resetAll", "1", "-autoDeal", "1",
                               "-piles", "9", "-cards", "39",
                               "-deck", "pink", "-tier", "regular", "-seed", "909"] + extra
        app.launch()
        return app
    }

    /// TASK 8 — Diamond Ripple consent: the offered piles wear phosphor rings
    /// behind the modal prompt. Then accept: the rings clear and the piles
    /// take the riffle wiggle.
    func testRippleConsentHighlightAndConfirm() {
        let app = launchDealPrompt(["-demoPrompt", "ripple"])
        XCTAssertTrue(app.buttons["SHUFFLE"].firstMatch.waitForExistence(timeout: 15),
                      "the ripple consent never presented")
        sleep(1)
        shot(app, "ripple__1-highlight-prompt")
        tap(app, "SHUFFLE")
        usleep(300_000)   // mid-wiggle
        shot(app, "ripple__3-accepted")
    }

    /// TASK 8 — the FAN inspection mid-question: the staged state is exactly
    /// "prompt open, fan hint armed, first offered pile fanned" — the fan
    /// layers OVER the prompt, and neither it nor a scrim tap settles the
    /// choice.
    func testRippleFanInspect() {
        let app = launchDealPrompt(["-demoPrompt", "rippleFan"])
        XCTAssertTrue(app.buttons["SHUFFLE"].firstMatch.waitForExistence(timeout: 15),
                      "the ripple consent never presented")
        sleep(1)
        shot(app, "ripple__2-fan-inspect")
        // The fan's ✕ closes the inspection; the question must still be open.
        _ = tapIfExists(app, "✕", timeout: 2)
        XCTAssertTrue(app.buttons["SHUFFLE"].firstMatch.exists,
                      "closing the fan must not settle the ripple question")
    }

    /// TASK 9 — Second Wind's choice: the prompt states the recycle count;
    /// SAVE applies the recycle (the engine's real answer path).
    func testSecondWindChoice() {
        let app = launchDealPrompt(["-dealPillar", "secondWind", "-demoPrompt", "secondWind"])
        let save = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "SAVE · RECYCLE")).firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 15),
                      "the Second Wind choice never presented")
        sleep(1)
        shot(app, "secondwind__1-choice")
        save.tap()
        sleep(1)
        shot(app, "secondwind__2-saved")
    }

    /// TASK 10 — Link Shuffler asks before the board-wide shuffle.
    func testShufflerConfirm() {
        let app = launchDealPrompt(["-dealSamePower", "linkShuffle", "-demoPrompt", "shuffler"])
        XCTAssertTrue(app.buttons["SHUFFLE ALL"].firstMatch.waitForExistence(timeout: 15),
                      "the shuffler confirm never presented")
        sleep(1)
        shot(app, "shuffler__1-confirm")
    }

    /// v6.56 — REVIVE TARGETING regression (the third recognizer/overlay
    /// recurrence): the PromptBar's full-screen scrim used to eat the target
    /// tap and resolve the pick as a silent SKIP, so the pile never came
    /// back. The staged offer kills the LAST pile of the 3×3 board for real;
    /// a coordinate tap on it must settle the pick with that pile REVIVED.
    /// Board taps are SpriteKit-level (no XCUI element), so the tap is a raw
    /// coordinate touch — which IS the real hit-test path (scrim vs.
    /// fall-through). The outcome is visual: `revive__2-revived` shows the
    /// pile back with a fresh top. The engine side is pinned in
    /// PendingChoiceTests.testReviveOffer*.
    func testReviveTargeting() {
        let app = launchDealPrompt(["-dealPillar", "revive", "-demoPrompt", "revive"])
        XCTAssertTrue(app.buttons["SKIP"].firstMatch.waitForExistence(timeout: 15),
                      "the revive target prompt never presented")
        sleep(1)
        shot(app, "revive__1-prompt")
        // The stage-killed pile is the LAST slot — bottom-right of the board.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.86, dy: 0.75)).tap()
        sleep(2)
        shot(app, "revive__2-revived")
        XCTAssertFalse(app.buttons["SKIP"].firstMatch.exists,
                       "the target tap must settle the pick")
    }

    /// TASK 11 — the Queen's Restock at the store: the boon line + the FREE
    /// glowing refresh, the free confirm, and the spent state (ladder pricing
    /// back, glow gone). `-storeFreeRefresh 1` arms the boon through the real
    /// openStore consumption path.
    func testStoreFreeRefreshReminder() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetAll", "1", "-autoStore", "1", "-coins", "99",
                               "-deck", "pink", "-tier", "regular", "-seed", "909",
                               "-storeFreeRefresh", "1"]
        app.launch()
        XCTAssertTrue(app.buttons["shelf-0"].waitForExistence(timeout: 20), "store missing")
        sleep(1)
        XCTAssertTrue(app.buttons["↻ RESTOCK · FREE"].firstMatch.exists,
                      "the refresh button never showed FREE")
        shot(app, "freerefresh__1-reminder-glow")
        tap(app, "↻ RESTOCK · FREE")
        XCTAssertTrue(app.buttons["RESTOCK"].firstMatch.waitForExistence(timeout: 4),
                      "the free-refresh confirm never showed")
        sleep(1)
        shot(app, "freerefresh__2-free-confirm")
        tap(app, "RESTOCK")
        sleep(1)
        XCTAssertTrue(app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "↻ RESTOCK · ◉")).firstMatch.exists,
            "after the free one, the ladder should price the next refresh")
        shot(app, "freerefresh__3-spent")
    }

    /// TASK 12 — the Queen's Mulligan at deal start: armed through the debug
    /// panel (the real mystery walk), then the next deal opens with the FREE
    /// glowing reshuffle and the reminder cue.
    func testDealFreeRedealReminder() {
        let app = driveToArmedEvent(row: 1, nameLabel: "♛ freeRedeal",
                                    taps: 7, backward: false,
                                    markers: markersFor("mysteryOverlay"))
        shot(app, "freeredeal__0-boon")
        tap(app, "CONTINUE")
        sleep(1)
        // Walk reachable nodes until one opens a DEAL (the map's ≡ vanishes);
        // the boon is claimed by that deal's start.
        _ = probeForEvent(app, markers: ["￼"])
        sleep(6)   // the composition reveal + the cascade, then the reminder
        shot(app, "freeredeal__1-deal-start")
    }

    // MARK: - v6.56: deck-view item help / icon legibility / torn purge

    /// Decline the forced Old Joker (the `-showJoker cut` sample state equips
    /// EVERY Pillar and Base slot), land back on the map, open the deck
    /// screen from the shell's DECK band and scroll the EQUIPPED rows into
    /// view.
    private func deckScreenShowingEquipped() -> XCUIApplication {
        let app = launchJoker("cut", marker: "LET HIM PICK")
        tap(app, "WALK AWAY")
        XCTAssertTrue(app.buttons["GO ON"].firstMatch.waitForExistence(timeout: 8),
                      "cut: no decline modal")
        tap(app, "GO ON")
        sleep(1)
        let deck = app.buttons["DECK"].firstMatch
        XCTAssertTrue(deck.waitForExistence(timeout: 6), "deck band missing")
        deck.tap()
        sleep(1)
        XCTAssertTrue(app.buttons["✕"].firstMatch.waitForExistence(timeout: 6),
                      "deck inspect missing")
        // The EQUIPPED rows sit below the card grid — scroll them into view.
        for _ in 0..<4 { app.swipeUp(); usleep(200_000) }
        sleep(1)
        return app
    }

    /// TASK 3 evidence, pre-enlargement icons (run against the pre-v6.56
    /// artSize values).
    func testDeckIconsBefore() {
        let app = deckScreenShowingEquipped()
        shot(app, "deck-icons__before")
    }

    /// TASK 2 + 3 — the EQUIPPED icons at their enlarged scale, then a TAP on
    /// an equipped Pillar opens its registry help (tap sticks; hold peeks).
    func testDeckItemHelpTap() {
        let app = deckScreenShowingEquipped()
        shot(app, "deck-icons__after")
        let item = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "deckItem-pillar")).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 6), "no equipped pillar cell found")
        item.tap()
        sleep(1)
        shot(app, "deck-item-help__1-tap")
    }

    /// TASK 4 — a purged card in a character's result container draws TORN,
    /// never intact: the cut's free pick closes on "His pick" / "<card>
    /// purged." with the torn Purge card in the well.
    func testTornPurgeResult() {
        let app = launchJoker("cut", marker: "LET HIM PICK")
        tap(app, "LET HIM PICK")
        XCTAssertTrue(app.buttons["GO ON"].firstMatch.waitForExistence(timeout: 8),
                      "cut: no return-line modal after his pick")
        sleep(1)
        shot(app, "torn-purge__1-result")
    }

    // MARK: - v6.57: deck-select scroll isolation

    /// TASK 17 — swiping the deck carousel moves ONLY the character sprite:
    /// the title, identity, tier chips, START and pager swap in place (fixed
    /// geometry), while the outgoing sprite ghosts out and the fresh one
    /// slides in. Captures deck A settled, an immediate post-swipe frame (the
    /// XCUI capture daemon waits out live tweens, so this lands at the
    /// slide's tail — not a true mid-flight frame), deck B settled, and a
    /// swipe back to A. The pixel proof is deckselect__1 vs deckselect__4:
    /// a full swipe CYCLE later the same deck must be pixel-identical, which
    /// no shifted text or panel could survive.
    func testDeckSelectSwipeIsolatesSprite() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetAll", "1", "-skipGate", "1"]
        app.launch()
        XCTAssertTrue(app.buttons["CLIMB"].waitForExistence(timeout: 20), "menu missing")
        app.buttons["CLIMB"].tap()
        XCTAssertTrue(app.buttons["START CLIMB"].waitForExistence(timeout: 6),
                      "deck select missing")
        sleep(1)   // settle the entrance
        shot(app, "deckselect__1-deckA")
        XCTAssertTrue(app.staticTexts["Pinky"].firstMatch.exists,
                      "deck A should open on Pinky")

        app.swipeLeft()
        shot(app, "deckselect__2-mid-swipe")   // daemon-settled tail of the slide
        sleep(1)
        shot(app, "deckselect__3-deckB")
        // Deck B is Mamma, LOCKED on a fresh save: name "???", sub is her
        // unlock note. Both must hold for the swipe to count.
        // Deck B is Mamma — her name when unlocked, her unlock note when not
        // (simulator state decides which; the swipe is what must hold).
        XCTAssertFalse(app.staticTexts["Pinky"].firstMatch.exists,
                       "the swipe never left Pinky")
        let onMamma = app.staticTexts["Mamma"].firstMatch.exists
            || app.staticTexts["Win a climb with Pinky to unlock"].firstMatch.exists
        XCTAssertTrue(onMamma, "the swipe should land on Mamma (deck B)")

        app.swipeRight()
        sleep(1)
        shot(app, "deckselect__4-return-deckA")
        XCTAssertTrue(app.staticTexts["Pinky"].firstMatch.exists,
                      "the swipe back never returned to Pinky")
    }

    // MARK: - v6.57: store RESTOCK rename + Queen reminder line

    /// TASKS 13+14 — the store's reroll is RESTOCK now, and the free-restock
    /// reminder line reads "The Queen will restock for free."
    ///   1. default shelf: the button is priced (↻ RESTOCK · ◉N), no boon line.
    ///   3. the restock confirm prompt's copy rides the bottom bar.
    func testStoreRestockNaming() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetAll", "1", "-autoStore", "1", "-coins", "99",
                               "-deck", "pink", "-tier", "regular", "-seed", "909"]
        app.launch()
        XCTAssertTrue(app.buttons["shelf-0"].waitForExistence(timeout: 20), "store missing")
        sleep(1)
        let priced = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "↻ RESTOCK · ◉")).firstMatch
        XCTAssertTrue(priced.exists, "the restock button never showed its priced state")
        XCTAssertFalse(app.staticTexts["The Queen will restock for free."].exists,
                       "the boon line must stay hidden without the Queen's Restock")
        shot(app, "store-restock__1-default")
        priced.tap()
        XCTAssertTrue(app.buttons["RESTOCK"].firstMatch.waitForExistence(timeout: 4),
                      "the restock confirm never showed")
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Restock the shelf for ◉"))
            .firstMatch.waitForExistence(timeout: 4),
                      "the priced restock confirm copy missing")
        sleep(1)
        shot(app, "store-restock__3-confirm")
    }

    /// TASK 14 evidence — the free state: the reminder line reads EXACTLY
    /// "The Queen will restock for free." and the button is "↻ RESTOCK · FREE".
    /// `-storeFreeRefresh 1` arms the boon through the real openStore
    /// consumption path (v6.55 hook, unchanged).
    func testStoreRestockFreeLine() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetAll", "1", "-autoStore", "1", "-coins", "99",
                               "-deck", "pink", "-tier", "regular", "-seed", "909",
                               "-storeFreeRefresh", "1"]
        app.launch()
        XCTAssertTrue(app.buttons["shelf-0"].waitForExistence(timeout: 20), "store missing")
        sleep(1)
        XCTAssertTrue(app.staticTexts["The Queen will restock for free."]
                        .firstMatch.waitForExistence(timeout: 4),
                      "the exact Queen reminder line never showed")
        XCTAssertTrue(app.buttons["↻ RESTOCK · FREE"].firstMatch.exists,
                      "the restock button never showed FREE")
        shot(app, "store-restock__2-free")
    }

    // MARK: - v6.57 curse art, third pass (red/black plate) + direct curse copy

    /// TASK 11 — the curse specimen sheet again (`-curseSheet 1`), pre- and
    /// post-rework; the extracted PNG is renamed `curse-art3__before` /
    /// `curse-art3__after` on export. Same harness as testCurseSheetSpecimen,
    /// new attachment name so the v6.55 pair stays untouched.
    func testCurseArt3Sheet() {
        let app = launch(["-curseSheet", "1"])
        sleep(1)
        shot(app, "curse-art3")
    }

    /// TASK 12 — the mystery curse reveal now prints the curse's registry
    /// description DIRECTLY under the marked card(s); the old "Tap or hold…"
    /// say-so line is gone. Tap/hold help still answers on top.
    func testMysteryCurseDirectDesc() {
        let app = launch(["-showOverlay", "mystery:cursedSticker"])
        XCTAssertTrue(app.buttons["CONTINUE"].firstMatch.waitForExistence(timeout: 8),
                      "mystery:cursedSticker reveal did not present")
        let cell = app.buttons["curseCell"].firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 6), "no cursed-card cell in the well")
        sleep(1)
        // Seed 909 curses K♥ with Saboteur ("Cursed. 10% chance the column's
        // Base or Pillar is destroyed") — the caption carries it inline.
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "10% chance"))
            .firstMatch.waitForExistence(timeout: 4),
                      "the curse's description is not printed inline")
        XCTAssertFalse(app.staticTexts["Tap or hold a marked card to read its curse"].exists,
                       "the retired say-so hint line is still on the panel")
        shot(app, "mystery-curse__1-direct-desc")
        // The extra: tap still opens the full registry help panel.
        cell.tap()
        sleep(1)
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Base or Pillar is destroyed"))
            .firstMatch.waitForExistence(timeout: 4),
                      "tap-for-help no longer reads the curse")
    }

    /// TASK 11 deal-scale evidence — the cursed chip on a REAL deal board.
    /// (Board badge chips are a FIXED 30pt scene size on every board —
    /// PileNode.syncStickerBadges — so any live board IS deal-scale for the
    /// chips. The `-autoDeal` launcher can't help: its debug deal owns a
    /// THROWAWAY campaign — DealController.init(setup:) — so a curse applied
    /// to the real climb never reaches it.)
    /// Route: the `-showOverlay mystery:cursedSticker` hook applies Saboteur
    /// to K♥ in the LIVE campaign; CONTINUE returns to the map; we walk into
    /// a deal node. The debug odds pilot (`-debugAutopilot 1` — the deal-
    /// level guesser, NOT `-autoCampaign`, whose FlowAutopilot would drive
    /// the map and blow through the reveal) plays it, but PAUSED first — it
    /// clears a 13-card deal in seconds — then resumed ~1s at a time, so each
    /// cycle draws about two fresh tops and the marked K♥ surfaces. The frame
    /// with K♥ on a pile top is the keeper (`curse-art3__dealscale`).
    func testCurseArt3DealScale() {
        let app = launch(["-showOverlay", "mystery:cursedSticker",
                          "-debugAutopilot", "1", "-debugAccess", "1"])
        XCTAssertTrue(app.buttons["CONTINUE"].firstMatch.waitForExistence(timeout: 8),
                      "mystery:cursedSticker reveal did not present")
        // Pause the pilot BEFORE the deal starts.
        let pause = app.buttons["❚❚"].firstMatch
        XCTAssertTrue(pause.waitForExistence(timeout: 4), "pilot pause button missing")
        pause.tap()   // → ▶
        tap(app, "CONTINUE")
        sleep(1)
        // Walk the opening row until a DEAL opens (the map's ≡ vanishes).
        // Coordinate taps are the map's real hit path; only legal next nodes
        // answer. Seed 909's row 0 is all deals.
        var inDeal = false
        let xs: [CGFloat] = [0.28, 0.50, 0.72]
        for (i, x) in xs.enumerated() where !inDeal {
            app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: 0.72)).tap()
            sleep(2)
            inDeal = !app.buttons["≡"].firstMatch.exists
            if !inDeal, i == xs.count - 1 {
                XCTFail("no opening-row deal opened")
            }
        }
        sleep(5)   // the composition reveal + the cascade settle
        shot(app, "curse-art3__dealscale-t0")
        // ~2 guesses per cycle (the pilot ticks every 0.45s), then settle.
        for t in 1...8 {
            app.buttons["▶"].firstMatch.tap()
            usleep(900_000)
            app.buttons["❚❚"].firstMatch.tap()
            sleep(1)
            shot(app, "curse-art3__dealscale-c\(t)")
        }
    }

    // MARK: - v6.57 pack suit indicators

    /// Default map: every sealed pack badge names the suit(s) its contents
    /// draw from (Pinky regular draws all four; Mamma's stage packs one).
    func testPackSuitIndicatorsDefault() {
        let app = launch([])
        sleep(2)   // map settle
        shot(app, "pack-suits__1-default")
    }

    /// The debug single-suit-pack variant ON: each pack badge shows the ONE
    /// seeded suit its slots all draw from. The pref rides the launch-arg
    /// defaults domain (-resetAll clears only the app domain), so the very
    /// first map render already honors it.
    func testPackSuitIndicatorsSingleSuitOn() {
        let app = launch(["-ninelives.pref.debugSingleSuitPacks", "1"])
        sleep(2)
        shot(app, "pack-suits__2-single-suit-on")
    }

    /// The debug panel's own toggle row, flipped ON in-panel.
    func testPackSuitToggleRow() {
        let app = launch(["-debugAccess", "1"])
        openDebugPanel(app)
        XCTAssertTrue(tap(app, "1-SUIT PACKS: OFF"), "the toggle row is missing")
        usleep(300_000)
        XCTAssertTrue(app.buttons["1-SUIT PACKS: ON"].firstMatch.waitForExistence(timeout: 4),
                      "the toggle did not flip on")
        shot(app, "pack-suits__3-toggle-row")
    }

    // MARK: - v6.62: zen difficulty select, no default pick

    /// First-time ZEN select: NO difficulty row is highlighted any more (the
    /// Easy green default is gone) and START sits disabled until a row is
    /// picked. One still of the untouched screen is the whole evidence.
    func testZenSelectNoDefaultPick() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetAll", "1", "-skipGate", "1"]
        app.launch()
        XCTAssertTrue(app.buttons["ZEN"].waitForExistence(timeout: 20), "menu missing")
        app.buttons["ZEN"].tap()
        let start = app.buttons["START"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 6), "zen select missing")
        sleep(1)   // settle the entrance
        // (XCUI reports this custom control enabled regardless — the pixels
        // are the evidence: no row highlighted, START greyed.)
        shot(app, "zen-select__1-no-pick")
    }
}
