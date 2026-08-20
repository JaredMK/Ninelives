import XCTest

/// v6.57 DEAL-FEEDBACK EVIDENCE — one screenshot per shipped behaviour:
///
///  - `roll-indicator__hit` / `__miss`: every item %-roll floats its verdict
///    at the pile it concerned (TASK 1-UI). Staged through the REAL
///    presentation path via `-demoRollFX hit|miss` — simctl can't make a
///    genuine 10%/50% roll land on cue (the `-demoCurseFX` precedent).
///  - `coin-pop__*`: resource grants pop "+N" at the pile (TASK 9). The base
///    shot is a REAL Heart Tax fire (`-dealBase tax` + `-demoBaseFire 1`).
///  - `landing-nosparks__after`: a played board after several landings, with
///    the green synapse spark burst REMOVED (TASK 10). The pre-change
///    `curse-art3__dealscale` frame (already in this folder) shows the burst.
///  - `secondwind-seq__1-draw` / `__2-prompt`: the parked Second Wind's
///    killer card visibly flies to the pile BEFORE the save prompt surfaces
///    (TASK 4-UI) — the staged `-demoPrompt secondWind` path plays the same
///    sequencing as a live offer.
///  - `histogram-wide__13-27`: the widest suit tally a deal can show, pushed
///    through the real deck-panel sync (TASK 15) — it must not touch the "2"
///    rank column.
///  - `histogram-sticker-refresh__*`: a changeSuitTo sticker applied to a
///    draw-pile card refreshes the band's suit counts the moment it lands
///    (TASK 16), via the real campaign mutation + invalidation hook.
///
/// Attachment names are the final filenames under `event-shots/v657/`.
final class DealFeedbackUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Debug-deal launcher (the `-autoDeal` dials), same shape as
    /// EventCaptureUITests.launchDealPrompt.
    private func launchDeal(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-resetAll", "1", "-autoDeal", "1",
                               "-piles", "9", "-cards", "39",
                               "-deck", "pink", "-tier", "regular", "-seed", "909"] + extra
        app.launch()
        return app
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
        NSLog("[EVENTSHOT] %@", name)
    }

    /// A burst of frames around a one-shot float's ~1s life (the demo hooks
    /// fire at 4.2s app-time; launch-to-layout latency runs ~0.5–1s). The
    /// keeper frame is picked at export time.
    private func burst(_ app: XCUIApplication, _ name: String) {
        var elapsed = 0.0
        for (i, t) in [3.35, 3.65, 3.95, 4.25].enumerated() {
            usleep(UInt32((t - elapsed) * 1_000_000))
            elapsed = t
            shot(app, "\(name)__t\(i + 1)")
        }
    }

    // MARK: - TASK 1-UI: roll indicators

    func testRollIndicatorHit() {
        let app = launchDeal(["-demoRollFX", "hit"])
        burst(app, "roll-indicator__hit")
    }

    func testRollIndicatorMiss() {
        let app = launchDeal(["-demoRollFX", "miss"])
        burst(app, "roll-indicator__miss")
    }

    // MARK: - TASK 9: resource-grant pops

    /// A REAL paying Base: Heart Tax (+1 per ♥ in the column) fires on its
    /// plaque tap and the "+N" grant floats over the column's first pile.
    /// No `-demoPrompt`, so the plaque fires without a confirm — the demo
    /// hook performs the tap path's controller call at the settled board.
    func testCoinPopBaseTax() {
        let app = launchDeal(["-dealBase", "tax", "-demoBaseFire", "1"])
        burst(app, "coin-pop__1-base-tax")
    }

    // MARK: - TASK 10: the landing spark burst is gone

    /// The scripted player (animations ON) has landed several cards by the
    /// shot: pre-change, every correct landing burst phosphor dots along the
    /// web edges; now nothing green leaves the pile.
    func testLandingNoSparks() {
        let app = launchDeal(["-autoPlaySlow", "1"])
        sleep(8)   // ~6 guesses in: multiple correct landings have happened
        shot(app, "landing-nosparks__after")
    }

    // MARK: - TASK 4-UI: Second Wind sequencing

    /// The staged offer (real parked engine state) plays the killer's flight
    /// FIRST — slowed to 1.5s on the staged path so the draw frame lands
    /// mid-flight — and the prompt ("SAVE · RECYCLE N") exists only AFTER the
    /// landing. The `!save.exists` at draw-shot time pins the ordering.
    func testSecondWindSequencing() {
        let app = launchDeal(["-dealPillar", "secondWind", "-demoPrompt", "secondWind"])
        let save = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "SAVE · RECYCLE")).firstMatch
        // Staging fires at 4.2s app-time (~3.4s test-time); the slowed flight
        // runs until ~5.7s app-time. These frames land mid-flight.
        sleep(4); shot(app, "secondwind-seq__1-draw")
        usleep(400_000)
        XCTAssertFalse(save.exists,
                       "the prompt must not exist while the killer is still flying")
        XCTAssertTrue(save.waitForExistence(timeout: 8),
                      "the Second Wind prompt never surfaced after the draw")
        sleep(1)
        shot(app, "secondwind-seq__2-prompt")
    }

    // MARK: - TASK 15: histogram suit-count overlap

    /// The worst case: two-digit remaining over two-digit totals ("13/27").
    /// The tally column is measured off the label's own font, so the first
    /// rank bar ("2") starts clear of the text at ANY count width.
    func testHistogramWideSuitCounts() {
        let app = launchDeal(["-demoSuitCounts", "1"])
        sleep(5)
        shot(app, "histogram-wide__13-27")
    }

    // MARK: - TASK 16: histogram refresh on a suit-sticker apply

    /// Frame 1 is the dealt board's true counts; the hook then applies a
    /// changeSuitTo to a draw-pile card through the real campaign mutation,
    /// and frame 2 shows the band repainted in the same beat — no guess, no
    /// other trigger in between.
    func testHistogramStickerRefresh() {
        let app = launchDeal(["-demoSuitRefresh", "1"])
        sleep(3)   // cascade done (~2s), the hook has NOT fired yet (4.2s)
        shot(app, "histogram-sticker-refresh__1-before")
        sleep(3)   // the hook fired at 4.2s and repainted immediately
        shot(app, "histogram-sticker-refresh__2-after")
    }
}
