import XCTest

/// ADDITIVE parity-audit capture pass (web-vs-native screenshot reference).
/// Drives the states simctl launch args alone cannot reach: map scrolling,
/// store sub-flows (column chooser / pack reveal / pickers), the rich fan
/// tray, the collection detail prompt and the shared confirm bar.
/// Every screenshot is attached to the xcresult; the harness renames them
/// into ios/reference/native/ per the capture contract.
final class ParityCaptureUITests: XCTestCase {

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

    private func buttonStarting(_ app: XCUIApplication, _ prefix: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    private func buttonContaining(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    // MARK: - Map scroll positions (top / mid / mystery / boss candidates)

    func testMapScrollPositions() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetAll", "1", "-skipGate", "1",
                               "-autoClimb", "1", "-deck", "pink", "-tier", "regular", "-seed", "909"]
        app.launch()
        XCTAssertTrue(app.buttons["≡"].waitForExistence(timeout: 10), "map shell missing")
        sleep(2)
        shot(app, "map-scroll-0-bottom")
        for i in 1...4 {
            app.swipeUp()
            sleep(1)
            shot(app, "map-scroll-\(i)")
        }
    }

    // MARK: - In-place fan peek (some cards already buried under piles)

    func testDealFanRich() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetAll", "1", "-autoDeal", "1",
                               "-piles", "9", "-cards", "39", "-seed", "777",
                               "-deck", "pink", "-autoPlaySlow", "1"]
        app.launch()
        sleep(14)   // let the slow autopilot bury cards under several piles
        // FAN toggle (top-left rail button) — scene buttons have no a11y label.
        // The fan is now an IN-PLACE peek (no modal tray): the toggle alone
        // is the state to capture.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.096, dy: 0.287)).tap()
        sleep(1)
        shot(app, "deal-fan-rich")
    }

    // MARK: - Collection detail prompt + shared confirm bar

    func testCollectionDetailAndPromptBar() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetAll", "1", "-skipGate", "1"]
        app.launch()
        XCTAssertTrue(app.buttons["CLIMB"].waitForExistence(timeout: 10))

        tap(app, "COLLECTION")
        sleep(1)
        // An always-unlocked starting sticker; its label sits inside the tile.
        let tile = app.staticTexts["+1 Rank"].firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 4), "collection tile missing")
        tile.tap()
        sleep(1)
        shot(app, "collection-detail")
        // The detail is now the web's centered panel (scrim-tap closes, no OK).
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        sleep(1)
        tap(app, "←")

        tap(app, "SETTINGS")
        sleep(1)
        tap(app, "RESET PROGRESS")
        sleep(1)
        shot(app, "prompt-bar")
        // Tolerant cleanup — the capture above is the point of this test.
        let cancel = app.buttons["Cancel"].firstMatch
        if cancel.waitForExistence(timeout: 2) { cancel.tap() }
    }

    // MARK: - Deep map (stage-1 boss + upper scroll range)

    /// The launcher map demo auto-travels 20 hops (deals/stores/bosses clear
    /// inline), ending mid-climb. Map geometry: the climb's top is SMALLER
    /// content-y, so swipeDown scrolls toward the boss row; the scroll lock
    /// keeps the CURRENT stage's boss row reachable (the veil only hides
    /// stages above it), so the clamp frame shows the stage boss at the top.
    func testMapDeepPositions() {
        let app = XCUIApplication()
        app.launchArguments = ["-autoMap", "1", "-autoTravel", "20",
                               "-seed", "909", "-deck", "pink", "-tier", "regular"]
        app.launch()
        XCTAssertTrue(app.buttons["≡"].waitForExistence(timeout: 15), "map shell missing")
        sleep(36)   // 20 auto-travel hops at 1.6s each + margin
        shot(app, "map-deep-0")
        for i in 1...6 {
            app.swipeDown()
            sleep(1)
            shot(app, "map-deep-\(i)")
        }
        // From the top clamp, a short drag up centers the crowned boss node.
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62))
        let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.47))
        from.press(forDuration: 0.2, thenDragTo: to)
        sleep(1)
        shot(app, "map-deep-boss")
    }

    // MARK: - Unlock toast (item unlock pop at run termination)

    /// Seeded via the NSArgumentDomain: stats just over two unlock thresholds
    /// (ditto: runsWon≥1 · greedy: endlessStagesReached≥1) plus an EMPTY
    /// unlock known-set, so the first run termination fires real item pops.
    /// (-resetAll clears only the app domain; launch-arg values still shadow.)
    /// The -autoPlay script plays the deal to a loss with instant rendering.
    /// NOTE: -seed is honored on the autoClimb path (fixed after the v1
    /// captures), so the map layout is seeded — the deal probe below stays
    /// coordinate-dense under -debugMap 1 anyway (every node interactive).
    func testUnlockToast() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetAll", "1", "-skipGate", "1", "-debugMap", "1",
                               "-autoClimb", "1", "-deck", "pink", "-tier", "legendary", "-seed", "909",
                               "-autoPlay", "1",
                               "-ninelives.stats.v1", #"{"campaignsWon":1,"bestEndless":1}"#,
                               "-ninelives.itemunlocks.v1", #"{"known":[]}"#]
        app.launch()
        XCTAssertTrue(app.buttons["≡"].waitForExistence(timeout: 30), "map shell missing")
        sleep(2)
        // Tap nodes until one dispatches a DEAL (the ≡ shell button vanishes —
        // a deal is SpriteKit-only). With -debugMap every node is tappable, so
        // a dense grid over the map area lands quickly. Modals that intercept:
        // mystery/pack (CONTINUE / SKIP), store (GO TO MAP), details (✕).
        func probeForDeal() {
            let ys: [CGFloat] = [0.30, 0.40, 0.50, 0.60, 0.70, 0.80, 0.89]
            let xs: [CGFloat] = [0.2, 0.35, 0.5, 0.65, 0.8]
            for y in ys {
                for x in xs {
                    app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)).tap()
                    sleep(1)
                    if !app.buttons["≡"].exists { return }    // a deal started
                    let cont = app.buttons["CONTINUE"].firstMatch
                    if cont.exists { cont.tap(); sleep(1) }
                    if !app.buttons["≡"].exists { return }    // mystery → ambush
                    let skip = app.buttons["SKIP"].firstMatch
                    if skip.exists { skip.tap(); sleep(1) }
                    let goMap = app.buttons["GO TO MAP"].firstMatch
                    if goMap.exists { goMap.tap(); sleep(1) }
                    let close = app.buttons["✕"].firstMatch
                    if close.exists { close.tap(); sleep(1) }
                }
            }
        }
        probeForDeal()
        sleep(2)
        shot(app, "unlock-deal-live")
        // The scripted player grinds each deal. Termination is the goal: a
        // LOSS fires the item pops BEFORE the death screen and they wait for
        // their own tap (no autopilot taps overlays here); a campaign WIN
        // parks on the victory overlay, whose "GO TO MAIN MENU" also runs the
        // pops. Between deals the flow idles on the map (the ≡ shell button
        // exists and no modal is up) — probe straight into the next deal.
        let popped = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS 'UNLOCKED'")).firstMatch
        for _ in 0..<15 {
            var waited: TimeInterval = 0
            while !popped.exists && waited < 120 {
                if app.buttons["≡"].exists { break }          // map idle
                if popped.exists { break }                    // pop just appeared
                let menu = app.buttons["GO TO MAIN MENU"].firstMatch
                if menu.exists { menu.tap(); sleep(2); break } // victory → pops
                // The pop's OWN dismiss button is also "CONTINUE" — only tap
                // it for deal-cleared summaries, never while a pop is up.
                let cont = app.buttons["CONTINUE"].firstMatch
                if cont.exists, !popped.exists { cont.tap(); sleep(1) }
                sleep(2); waited += 2
            }
            if popped.exists {
                sleep(1)
                shot(app, "unlock-toast")
                break
            }
            guard app.buttons["≡"].exists else { break }       // stalled, give up
            probeForDeal()
        }
        sleep(2)
        shot(app, "unlock-aftermath")
    }

    // MARK: - Store sub-flows

    /// One store visit, classified by the detail view's buy-button label:
    ///   pillar/base → "PICK A COLUMN"   samepower → "BUY & EQUIP"
    ///   removal → "REMOVE A CARD"       card → "BUY & SWAP IN"
    ///   sticker → "PLACE STICKER"       pack → "BUY · ◉" (the default label)
    func testStoreSubflows() {
        // Factory-clean first (launcher mode ignores -resetAll): boot the real
        // shell once so stats/unlocks are at the starting set, then relaunch
        // into the store demo.
        let wipe = XCUIApplication()
        wipe.launchArguments = ["-resetAll", "1", "-skipGate", "1"]
        wipe.launch()
        XCTAssertTrue(wipe.buttons["CLIMB"].waitForExistence(timeout: 10))
        wipe.terminate()

        let app = XCUIApplication()
        app.launchArguments = ["-autoStore", "1", "-coins", "99", "-seed", "909"]
        app.launch()
        XCTAssertTrue(app.buttons["shelf-0"].waitForExistence(timeout: 10), "store shelf missing")
        sleep(1)
        shot(app, "store-shelf-rich")

        var kinds = scanShelf(app)
        NSLog("[STORE] initial kinds: %@", kinds.sorted { $0.key < $1.key }.map { "\($0.value)@\($0.key)" }.joined(separator: ","))
        var packCaptured = false
        var rerolls = 0
        var missing = true
        while missing, rerolls < 10 {
            // Buy a pack THE MOMENT one shows — a later reroll would roll the
            // slot away before the dedicated capture below ever sees it.
            if !packCaptured, let idx = kinds.first(where: { $0.value == "pack" })?.key {
                NSLog("[STORE] pack at shelf-%d — buying", idx)
                app.buttons["shelf-\(idx)"].firstMatch.tap()
                sleep(1)
                let buy = buttonStarting(app, "BUY · ")
                if buy.waitForExistence(timeout: 2) {
                    buy.tap()
                    sleep(2)
                    shot(app, "store-pack-reveal")
                    packCaptured = true
                    // Decline the pick; the reveal is the surface we needed.
                    let skip = app.buttons["SKIP"].firstMatch
                    if skip.waitForExistence(timeout: 2) { skip.tap(); sleep(1) }
                    closeModal(app)
                    kinds = scanShelf(app)
                } else {
                    NSLog("[STORE] pack buy button NOT found; detail buttons: %@",
                          app.buttons.allElementsBoundByIndex.map { $0.label }.joined(separator: " | "))
                    closeDetail(app)
                }
            }
            let hasPlacement = kinds.values.contains("pillar") || kinds.values.contains("base")
            missing = !(packCaptured && hasPlacement && kinds.values.contains("card"))
            guard missing else { break }
            // The header RESTOCK pill is a PixelButtonView — tap its measured
            // center, then CONFIRM on the prompt bar ("Restock the shelf for
            // ◉N?" → RESTOCK; PromptBar action labels are UPPERCASED).
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.763, dy: 0.250)).tap()
            sleep(1)
            let confirm = app.buttons["RESTOCK"].firstMatch
            let confirmFound = confirm.waitForExistence(timeout: 2)
            NSLog("[STORE] reroll %d: prompt confirm found=%d", rerolls + 1, confirmFound ? 1 : 0)
            if confirmFound { confirm.tap() }
            sleep(1)
            kinds = scanShelf(app)
            NSLog("[STORE] after reroll %d kinds: %@", rerolls + 1,
                  kinds.sorted { $0.key < $1.key }.map { "\($0.value)@\($0.key)" }.joined(separator: ","))
            rerolls += 1
        }
        // A pack is the only slot class that can dodge a dozen rerolls; if it
        // never showed, the pack-reveal capture is simply skipped (the harness
        // records it as NOT CAPTURED rather than faking the surface).
        shot(app, "store-shelf-scanned")

        // store-column-chooser: a pillar/base detail shows "Choose a column".
        if let idx = kinds.first(where: { $0.value == "pillar" || $0.value == "base" })?.key {
            app.buttons["shelf-\(idx)"].firstMatch.tap()
            sleep(1)
            shot(app, "store-column-chooser")
            let col = buttonStarting(app, "C2")
            if col.waitForExistence(timeout: 2) {
                col.tap()
                sleep(1)
                shot(app, "store-column-chosen")
            }
            closeDetail(app)
        }

        // picker-sticker: buy a sticker → apply picker.
        if let idx = kinds.first(where: { $0.value == "sticker" })?.key {
            app.buttons["shelf-\(idx)"].firstMatch.tap()
            sleep(1)
            let buy = buttonStarting(app, "PLACE STICKER")
            if buy.waitForExistence(timeout: 2) {
                buy.tap()
                sleep(1)
                shot(app, "picker-sticker")
                closeModal(app)
            } else { closeDetail(app) }
            kinds = scanShelf(app)
        }

        // picker-removal: the removal slot is always present.
        if let idx = kinds.first(where: { $0.value == "removal" })?.key {
            app.buttons["shelf-\(idx)"].firstMatch.tap()
            sleep(1)
            let buy = buttonStarting(app, "REMOVE A CARD")
            if buy.waitForExistence(timeout: 2) {
                buy.tap()
                sleep(1)
                shot(app, "picker-removal")
                closeModal(app)
            } else { closeDetail(app) }
            kinds = scanShelf(app)
        }

        // store-pack-reveal fallback: buy a pack → the reveal screen (usually
        // already captured opportunistically inside the reroll loop above).
        if !packCaptured, let idx = kinds.first(where: { $0.value == "pack" })?.key {
            app.buttons["shelf-\(idx)"].firstMatch.tap()
            sleep(1)
            let buy = buttonStarting(app, "BUY · ")
            if buy.waitForExistence(timeout: 2) {
                buy.tap()
                sleep(2)
                shot(app, "store-pack-reveal")
                // Decline the pick; the reveal is the surface we needed.
                let skip = app.buttons["SKIP"].firstMatch
                if skip.waitForExistence(timeout: 2) { skip.tap(); sleep(1) }
                closeModal(app)
            } else { closeDetail(app) }
            kinds = scanShelf(app)
        }

        // picker-swap: buy a card slot → the swap-in walk opens.
        if let idx = kinds.first(where: { $0.value == "card" })?.key {
            app.buttons["shelf-\(idx)"].firstMatch.tap()
            sleep(1)
            let buy = buttonStarting(app, "BUY & SWAP IN")
            if buy.waitForExistence(timeout: 2) {
                buy.tap()
                sleep(1)
                shot(app, "picker-swap")
                closeModal(app)
            } else { closeDetail(app) }
        }
    }

    // MARK: - Store diagnostics (temporary — ground truth for the pack hunt)

    /// Dumps every shelf tile's detail-view button labels to the test log.
    /// Diagnoses why no "pack" kind is ever classified: either packs never
    /// roll in the demo store, or their buy label isn't the expected default.
    func testStoreDump() {
        let app = XCUIApplication()
        app.launchArguments = ["-autoStore", "1", "-coins", "99", "-seed", "909"]
        app.launch()
        XCTAssertTrue(app.buttons["shelf-0"].waitForExistence(timeout: 10), "store shelf missing")
        sleep(1)
        NSLog("[DUMP] all buttons: %@", app.buttons.allElementsBoundByIndex.map { $0.label }.joined(separator: " | "))
        for i in 0..<8 {
            let tile = app.buttons["shelf-\(i)"].firstMatch
            guard tile.waitForExistence(timeout: 1) else { break }
            NSLog("[DUMP] tile %d label=%@", i, tile.label)
            tile.tap()
            sleep(1)
            let labels = app.buttons.allElementsBoundByIndex.map { $0.label }
            NSLog("[DUMP] tile %d detail buttons: %@", i, labels.joined(separator: " | "))
            closeDetail(app)
        }
        // One reroll, verified step by step.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.763, dy: 0.250)).tap()
        sleep(1)
        NSLog("[DUMP] after pill tap buttons: %@", app.buttons.allElementsBoundByIndex.map { $0.label }.joined(separator: " | "))
        let confirm = app.buttons["RESTOCK"].firstMatch
        NSLog("[DUMP] RESTOCK exists=%d", confirm.exists ? 1 : 0)
        if confirm.exists { confirm.tap() }
        sleep(2)
        NSLog("[DUMP] after reroll buttons: %@", app.buttons.allElementsBoundByIndex.map { $0.label }.joined(separator: " | "))
        for i in 0..<8 {
            let tile = app.buttons["shelf-\(i)"].firstMatch
            guard tile.waitForExistence(timeout: 1) else { break }
            tile.tap()
            sleep(1)
            NSLog("[DUMP] post-reroll tile %d detail buttons: %@", i,
                  app.buttons.allElementsBoundByIndex.map { $0.label }.joined(separator: " | "))
            closeDetail(app)
        }
    }

    // MARK: - Store helpers

    /// Per-class store DETAIL stills (sticker / same-power / pack) for the
    /// web-parity set — screenshots the detail only, never buys.
    func testStoreDetailStills() {
        let wipe = XCUIApplication()
        wipe.launchArguments = ["-resetAll", "1", "-skipGate", "1"]
        wipe.launch()
        XCTAssertTrue(wipe.buttons["CLIMB"].waitForExistence(timeout: 10))
        wipe.terminate()

        let app = XCUIApplication()
        app.launchArguments = ["-autoStore", "1", "-coins", "99", "-seed", "909"]
        app.launch()
        XCTAssertTrue(app.buttons["shelf-0"].waitForExistence(timeout: 10), "store shelf missing")
        sleep(1)

        var wanted: [String: String] = ["sticker": "store-detail-sticker",
                                        "samepower": "store-detail-same",
                                        "pack": "store-detail-pack"]
        var kinds = scanShelf(app)
        for _ in 0..<12 {
            for (kind, name) in wanted {
                guard let idx = kinds.first(where: { $0.value == kind })?.key else { continue }
                app.buttons["shelf-\(idx)"].firstMatch.tap()
                sleep(1)
                shot(app, name)
                wanted.removeValue(forKey: kind)
                closeDetail(app)
            }
            guard !wanted.isEmpty else { break }
            // Reroll for the missing classes (RESTOCK pill + prompt confirm).
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.763, dy: 0.250)).tap()
            sleep(1)
            let confirm = app.buttons["RESTOCK"].firstMatch
            if confirm.waitForExistence(timeout: 2) { confirm.tap() }
            sleep(1)
            kinds = scanShelf(app)
        }
        NSLog("[STILLS] uncaptured classes: %@", wanted.keys.joined(separator: ","))
    }

    /// The GATED title menu (fresh install, boot gate not skipped): after the
    /// first-run tutorial the campaign is still closed, so the menu leads with
    /// ZEN — the state web/menu-fresh.png shows.
    func testMenuFreshGated() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetAll", "1"]
        app.launch()
        // First run boots into the tutorial; skip it to reach the gated menu.
        let skip = app.buttons["SKIP TIPS"].firstMatch
        if skip.waitForExistence(timeout: 10) { skip.tap(); sleep(1) }
        sleep(1)
        shot(app, "menu-fresh-gated")
    }

    // MARK: - Store helpers

    /// Taps every shelf tile, reads the detail's buy-button label, closes.
    @discardableResult
    private func scanShelf(_ app: XCUIApplication) -> [Int: String] {
        var kinds: [Int: String] = [:]
        for i in 0..<8 {
            let tile = app.buttons["shelf-\(i)"].firstMatch
            guard tile.waitForExistence(timeout: 1) else { break }
            tile.tap()
            var waited: TimeInterval = 0
            while !app.buttons["✕"].firstMatch.exists, waited < 2 {
                usleep(200_000); waited += 0.2
            }
            kinds[i] = classifyDetail(app)
            closeDetail(app)
        }
        return kinds
    }

    private func classifyDetail(_ app: XCUIApplication) -> String {
        if buttonStarting(app, "PICK A COLUMN").exists { return "pillar" }
        if buttonStarting(app, "BUY & PLACE").exists { return "pillar" }
        if buttonStarting(app, "BUY & EQUIP").exists { return "samepower" }
        if buttonStarting(app, "REMOVE A CARD").exists { return "removal" }
        if buttonStarting(app, "BUY & SWAP IN").exists { return "card" }
        if buttonStarting(app, "PLACE STICKER").exists { return "sticker" }
        if buttonStarting(app, "BUY · ").exists { return "pack" }
        return "unknown"
    }

    private func closeDetail(_ app: XCUIApplication) {
        let close = app.buttons["✕"].firstMatch
        if close.waitForExistence(timeout: 2) {
            close.tap()
            sleep(1)
        }
    }

    /// Pickers / reveals: ✕ when not forced, SKIP when offered.
    private func closeModal(_ app: XCUIApplication) {
        for _ in 0..<3 {
            let skip = app.buttons["SKIP"].firstMatch
            if skip.exists { skip.tap(); sleep(1); continue }
            let close = app.buttons["✕"].firstMatch
            if close.exists { close.tap(); sleep(1); continue }
            break
        }
        // Back on the shelf: nothing modal may cover shelf-0.
        _ = app.buttons["shelf-0"].waitForExistence(timeout: 3)
    }
}
