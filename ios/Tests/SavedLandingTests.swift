import XCTest
@testable import GameCore

/// STICKERS ON SAVED LANDINGS (v6.57) — the complement of the v6.52/53
/// fatal-landing audit. The gate is now:
///
///   CORRECT landing (incl. tie-safe, which RESOLVES as correct)
///       → landing stickers fire (unchanged).
///   WRONG landing, pile SAVED by the SAME-CHARGE backstop (the card lands and
///       becomes the new top) → the card's BENEFICIAL landing stickers fire.
///   WRONG landing, pile saved by a GUARD or by SECOND WIND → the card never
///       lands (it returns to / recycles into the deck) → NOTHING fires.
///   FATAL landing (incl. a declined Second Wind and the malfunction kill's
///       non-curse effects) → NOTHING fires (the audit's rule stands).
///   CURSES (Peeler / drains / Spoiler / Saboteur) and Trapdoor stay
///       CORRECT-only even on a saved landing — a wrong guess never springs
///       them. PILLAR landing effects (Fibonacci, Prime, tributes…) reward a
///       CORRECT landing and stay correct-only too.
final class SavedLandingTests: XCTestCase {
    private let data = GameData.shared

    /// Wrong-guess Same-Charge save: top 9♠, drawn 2 (carrying `stickers`),
    /// HIGHER. The charge saves the pile and the 2 lands as the new top.
    /// `drawnSuit` matters to the v6.85 conditionals — the default ♠ matches
    /// the other piles' 6♠ tops so a conditional carrier FIRES; pass "♥" to
    /// make its bet miss. `deckFiller` pads the draw deck behind the killer
    /// (for effects that read the deck's size, e.g. Deep Pockets).
    private func savedEngine(drawnStickers: [String], topStickers: [String] = [],
                             topSuit: String = "♠", drawnSuit: String = "♥",
                             pillars: [String?]? = nil, bases: [String?]? = nil,
                             deckFiller: Int = 0) -> GameEngine {
        let filler = (0..<deckFiller).map { IV.spec(60 + $0, 2 + ($0 % 5) * 2, $0 % 2 == 0 ? "♣" : "♦") }
        return IV.engine(tops: [IV.spec(1, 9, topSuit, topStickers), IV.spec(2, 6), IV.spec(3, 6)],
                         deckOrder: [IV.spec(50, 2, drawnSuit, drawnStickers), IV.spec(51, 3)] + filler,
                         pillars: pillars, bases: bases, sameCharge: true)
    }
    private func logLines(_ e: GameEngine) -> [String] {
        e.run.log.flatMap { [$0.title] + $0.lines }
    }

    // MARK: - The matrix: beneficial landing stickers FIRE on the saved landing

    func testCoinStickersPayOnASameChargeSave() {
        // ♠ carrier over the two 6♠ tops → the conditional pays per matching
        // pile, own included = ×3.
        let e = savedEngine(drawnStickers: ["gainCoin"], drawnSuit: "♠")
        let v = data.stickerTypes.get("gainCoin")!.value
        e.guess(0, .higher)
        XCTAssertTrue(e.board.isActive(0), "the charge saved the pile")
        XCTAssertEqual(e.run.bonusCoins, v * 3, "Bonus Coin pays — the card LANDED and its bet hit")
    }

    func testDeepPocketsPaysOnASameChargeSave() {
        let e = savedEngine(drawnStickers: ["deepPockets"],
                            deckFiller: 12)   // per = remaining ÷ `per` — needs a real deck
        e.guess(0, .higher)
        XCTAssertGreaterThan(e.run.bonusCoins, 0, "Deep Pockets pays on the saved landing")
        XCTAssertTrue(logLines(e).contains { $0.contains("⚡ Deep Pockets [sticker]") })
    }

    func testQuickBuryCarrierFiresOnASameChargeSave() {
        // LANDING-FIRED (v6.78): the DRAWN carrier still LANDS on a
        // Same-Charge save (a saved landing IS a landing — the v6.57 rule),
        // so its own landing fires the bury.
        let e = savedEngine(drawnStickers: ["quickBury"], drawnSuit: "♠")   // the bet must hit
        let deckBefore = e.deck.remaining()
        e.guess(0, .higher)
        XCTAssertTrue(e.board.isActive(0))
        XCTAssertEqual(e.deck.remaining(), deckBefore - 2, "the draw + the burial both left the deck")
        XCTAssertEqual(e.board.piles[0].cards.count, 3, "9 + buried card + the landed 2")
    }

    func testQuickBuryTopDoesNotFireOnASameChargeSave() {
        // A saved landing ON a Quick Bury top fires nothing (v6.78 — the
        // v6.75 pile-top trigger is retired).
        let e = savedEngine(drawnStickers: [], topStickers: ["quickBury"])
        let deckBefore = e.deck.remaining()
        e.guess(0, .higher)
        XCTAssertTrue(e.board.isActive(0))
        XCTAssertEqual(e.deck.remaining(), deckBefore - 1, "only the draw — a landing ON the carrier fires nothing")
        XCTAssertEqual(e.board.piles[0].cards.count, 2, "9 + the landed 2, nothing buried")
    }

    func testSnowballGrowsFromZeroOnASameChargeSave() {
        // The wrong placement resets X to 0 BEFORE the branch (pinned rule);
        // the landing then grows it by `step` — no burial at X=0.
        let e = savedEngine(drawnStickers: ["snowball"])
        let step = data.stickerTypes.get("snowball")?.int("step", 1) ?? 1
        e.guess(0, .higher)
        XCTAssertEqual(e.run.snowballUpdates[50], step, "reset to 0, then the landing grew it")
    }

    func testTellAndScoutArmOnASameChargeSave() {
        let e = savedEngine(drawnStickers: ["tell", "revealNext"], drawnSuit: "♠")
        e.guess(0, .higher)
        XCTAssertTrue(e.board.isActive(0))
        XCTAssertTrue(e.run.tellPiles.contains(0), "Tell arms — the card landed and stays on top")
        XCTAssertTrue(e.run.revealNextActive, "Scout reveals — the card landed")
    }

    func testSnobsFireBothDirectionsOnASameChargeSave() {
        // Snob on the pile top, matching-suit card lands (wrongly) on it.
        let v = data.stickerTypes.get("heartSnob")?.num("value", 4) ?? 4
        let e = savedEngine(drawnStickers: [], topStickers: ["heartSnob"])
        e.guess(0, .higher)   // 2♥ lands on the ♥-snob top, wrong but saved
        XCTAssertTrue(e.board.isActive(0))
        XCTAssertEqual(e.run.bonusCoins, v, "the top's snob fires — a ♥ LANDED on it")
        // Reverse: the DRAWN card carries the snob, the top wears the suit.
        let e2 = savedEngine(drawnStickers: ["heartSnob"], topSuit: "♥")
        e2.guess(0, .higher)
        XCTAssertEqual(e2.run.bonusCoins, v, "the drawn card's snob fires — it landed on a ♥ top")
    }

    func testRechargeShieldRebanksOnASameChargeSave() {
        // v6.90: the rank bet must be FED — pile 3 shows another 2, so the
        // saved landing's re-bank still fires under the conditional.
        let e = IV.engine(tops: [IV.spec(1, 9, "♠"), IV.spec(2, 6), IV.spec(3, 2, "♦")],
                          deckOrder: [IV.spec(50, 2, "♥", ["rechargeSameShield"]), IV.spec(51, 3)],
                          sameCharge: true)
        e.guess(0, .higher)
        XCTAssertTrue(e.board.isActive(0))
        XCTAssertTrue(e.sameCharge, "the save spent the charge; the landed sticker re-banked it")
    }

    func testShuffleOfferQueuesOnASameChargeSave() {
        // Pile 0 grows first so the landed pile has >1 card to shuffle.
        let e = savedEngine(drawnStickers: ["shuffle"])
        e.board.piles[0].cards.insert(DeckManager.toCard(IV.spec(7, 3), data: data), at: 0)
        var offered = false
        e.on { if case .actionOffer = $0 { offered = true } }
        e.guess(0, .higher)
        XCTAssertTrue(e.board.isActive(0))
        XCTAssertTrue(offered || !e.run.pendingActions.isEmpty, "the Shuffle offer queues")
        e.answerAction(false)   // drain
    }

    // MARK: - The exceptions: CURSES + Trapdoor stay correct-only on a save

    func testCursesStayDarkOnASameChargeSave() {
        let e = savedEngine(drawnStickers: ["spoiler", "peeler"],
                            topStickers: ["gainCoin", "tell"],
                            pillars: ["columnGuardian", nil, nil], bases: ["shuffleColumn", nil, nil])
        e.run.bonusCoins = 5
        var rolls = 0
        e.on { if case .rollResult = $0 { rolls += 1 } }
        e.guess(0, .higher)
        XCTAssertTrue(e.board.isActive(0), "saved")
        XCTAssertEqual(e.run.bonusCoins, 5, "Spoiler does not wipe on a WRONG landing, saved or not")
        XCTAssertEqual(e.board.top(0)?.stickers.count ?? -1, 2,
                       "the landed card keeps its own two curses (Peeler never ran)")
        let touched = e.board.piles[0].cards.first { $0.id == 1 }
        XCTAssertEqual(touched?.stickers.count, 2, "the card landed ON keeps its stickers")
        XCTAssertEqual(e.run.pillars?[0], "columnGuardian", "Saboteur not on the card, pillar intact")
        XCTAssertEqual(rolls, 0, "no % roll belongs to this landing")
    }

    func testSaboteurDoesNotRollOnASameChargeSave() {
        let e = savedEngine(drawnStickers: ["saboteur"],
                            pillars: ["columnGuardian", nil, nil], bases: ["shuffleColumn", nil, nil])
        var rolls = 0
        e.on { if case .rollResult = $0 { rolls += 1 } }
        e.guess(0, .higher)
        XCTAssertTrue(e.board.isActive(0))
        XCTAssertEqual(e.run.pillars?[0], "columnGuardian")
        XCTAssertEqual(e.run.bases?[0], "shuffleColumn")
        XCTAssertEqual(rolls, 0, "the saboteur roll needs a CORRECT landing")
    }

    func testTrapdoorStaysShutOnASameChargeSave() {
        let e = IV.engine(tops: [IV.spec(1, 9, "♠"), IV.spec(2, 6), IV.spec(3, 6)],
                          deckOrder: [IV.spec(49, 10, "♥"),
                                      IV.spec(50, 2, "♥", ["trapdoor"]), IV.spec(51, 3)],
                          sameCharge: true)
        e.guess(0, .higher)                       // 10 on 9 → correct, pile grows to 2
        let count = e.board.piles[0].cards.count
        let deckBefore = e.deck.remaining()
        e.guess(0, .higher)                       // 2 on 10 → wrong → Same Charge saves
        XCTAssertTrue(e.board.isActive(0))
        XCTAssertEqual(e.board.piles[0].cards.count, count + 1,
                       "the trapdoor stays shut on a saved-wrong landing (+1 = the landed card)")
        XCTAssertEqual(e.deck.remaining(), deckBefore - 1, "no bottom card slipped back in")
    }

    // MARK: - The exceptions: PILLAR landing effects reward a CORRECT landing

    func testPillarLandingEffectsStayCorrectOnlyOnASave() {
        // Prime pays on a correct prime-rank landing; 2 qualifies, but the
        // guess was WRONG — the saved landing must not pay it. (This case
        // rode Fibonacci until its v6.78 retirement.)
        let e = savedEngine(drawnStickers: [], pillars: ["prime", nil, nil])
        e.guess(0, .higher)
        XCTAssertTrue(e.board.isActive(0))
        XCTAssertEqual(e.run.bonusCoins, 0, "Prime is the column's reward for a CORRECT landing")
    }

    // MARK: - Non-landing saves: the card never lands, so NOTHING fires

    func testGuardSaveFiresNoLandingStickers() {
        // Drawn 2♥ carries the Guard; pile 2's ♥ top feeds its condition →
        // the guard absorbs the wrong guess and the card RETURNS TO THE DECK
        // without landing — so the OTHER conditionals it carries neither
        // fire nor convert (no landing, no bet resolved).
        let e = IV.engine(tops: [IV.spec(1, 9, "♠"), IV.spec(2, 6, "♥"), IV.spec(3, 6)],
                          deckOrder: [IV.spec(50, 2, "♥", ["suitImmunity", "gainCoin", "tell", "quickBury"]),
                                      IV.spec(51, 3)],
                          sameCharge: true)
        let deckBefore = e.deck.remaining()
        e.guess(0, .higher)
        XCTAssertTrue(e.board.isActive(0), "the guard saved the pile")
        XCTAssertTrue(e.sameCharge, "the charge was never spent — the guard went first")
        XCTAssertEqual(e.board.top(0)?.id, 1, "the top never changed — no landing")
        XCTAssertEqual(e.deck.remaining(), deckBefore, "the drawn card returned; no burial")
        XCTAssertEqual(e.run.bonusCoins, 0, "Bonus Coin does not pay — the card never landed")
        XCTAssertTrue(e.run.tellPiles.isEmpty, "Tell does not arm")
    }

    func testSecondWindSaveFiresNoLandingStickers() {
        // Auto mode (web parity): the roll hits — the pile's TOP STAYS, its
        // buried cards AND the killer shuffle back into the deck (v6.93), so
        // no card lands on the pile at all.
        var state: UInt32?
        for s: UInt32 in 1...400 {
            let e = IV.engine(tops: [IV.spec(1, 9, "♠"), IV.spec(2, 6), IV.spec(3, 6)],
                              deckOrder: [IV.spec(50, 2, "♥", ["gainCoin", "tell", "quickBury"]),
                                          IV.spec(51, 3), IV.spec(52, 4), IV.spec(53, 7)],
                              pillars: ["secondWind", nil, nil])
            e.rng.state = s
            e.guess(0, .higher)
            if e.board.isActive(0) { state = s; break }
        }
        guard let s = state else { return XCTFail("no saving state in 1...400") }
        let e = IV.engine(tops: [IV.spec(1, 9, "♠"), IV.spec(2, 6), IV.spec(3, 6)],
                          deckOrder: [IV.spec(50, 2, "♥", ["gainCoin", "tell", "quickBury"]),
                                      IV.spec(51, 3), IV.spec(52, 4), IV.spec(53, 7)],
                          pillars: ["secondWind", nil, nil])
        e.rng.state = s
        e.guess(0, .higher)
        XCTAssertTrue(e.board.isActive(0), "Second Wind saved the pile")
        XCTAssertEqual(e.board.top(0)?.id, 1, "the pile keeps its top — no fresh card is dealt")
        XCTAssertEqual(e.board.piles[0].cards.count, 1, "…and its buried cards shuffled back")
        XCTAssertEqual(e.run.bonusCoins, 0, "Bonus Coin does not pay — no card landed")
        XCTAssertTrue(e.run.tellPiles.isEmpty, "Tell does not arm — no card landed")
    }

    // MARK: - Tie-safe: RESOLVES as correct, so it already fires (pin the route)

    func testTieSafeSaveFiresLandingStickersViaTheCorrectBranch() {
        // v6.86: Same-Safe is rank-conditional — pile 3's 9♦ feeds the tie
        // save. gainCoin's suit bet then matches pile 2's 6♠ only → ×2.
        let e = IV.engine(tops: [IV.spec(1, 9, "♠"), IV.spec(2, 6), IV.spec(3, 9, "♦")],
                          deckOrder: [IV.spec(50, 9, "♠", ["tieSafe", "gainCoin"]), IV.spec(51, 3)])
        let v = data.stickerTypes.get("gainCoin")!.value
        var tieSaved = false
        e.on { if case .tieSafeSaved = $0 { tieSaved = true } }
        e.guess(0, .higher)   // 9♠ on 9♠ — a FED tie the sticker makes SAFE = correct
        XCTAssertTrue(tieSaved)
        XCTAssertTrue(e.board.isActive(0))
        XCTAssertEqual(e.run.bonusCoins, v * 2,
                       "a tie-safe save IS a correct landing — the coin conditional fires ×2 here")
    }

    // MARK: - Fatal stays fatal (one representative; FatalLandingTests pins the rest)

    func testFatalLandingStillFiresNothing() {
        let e = IV.engine(tops: [IV.spec(1, 9, "♠"), IV.spec(2, 6), IV.spec(3, 6)],
                          deckOrder: [IV.spec(50, 2, "♥", ["gainCoin", "tell", "quickBury"]),
                                      IV.spec(51, 3)])
        let deckBefore = e.deck.remaining()
        e.guess(0, .higher)   // no charge, no guard — the pile dies
        XCTAssertFalse(e.board.isActive(0))
        XCTAssertEqual(e.run.bonusCoins, 0)
        XCTAssertTrue(e.run.tellPiles.isEmpty)
        XCTAssertEqual(e.deck.remaining(), deckBefore - 1, "only the draw left the deck")
    }
}
