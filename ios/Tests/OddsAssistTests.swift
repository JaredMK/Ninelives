import XCTest
@testable import GameCore

/// ODDS ASSIST (v6.71, single-recommendation v6.72): the display-only
/// safest-call computation, its tie-break ladder, its deal-out gate, and its
/// Straight-win unlock gate. The engine promise under test:
/// `assistRecommendation()` returns the SINGLE (pile, call) whose survival
/// probability against the remaining deck is highest, breaking ties
/// (a) SAME over directional, (b) smallest pileSize, (c) first-by-index —
/// never rng — and reads nothing but `remainingCounts()`: it never moves the
/// rng, the deck order, or any run state.
final class OddsAssistTests: XCTestCase {

    private func assertRec(_ e: GameEngine, _ pile: Int?, _ call: Guess?,
                           _ message: String = "", file: StaticString = #filePath,
                           line: UInt = #line) {
        let rec = e.assistRecommendation()
        XCTAssertEqual(rec?.pile, pile, message, file: file, line: line)
        XCTAssertEqual(rec?.call, call, message, file: file, line: line)
    }

    // MARK: - Probability correctness on constructed boards

    /// Deck of 9,9,11 against tops 5, 12 and 10: pile 5's HIGHER (3/3) and
    /// pile 12's LOWER (3/3) tie at the top; neither is a SAME and both piles
    /// weigh 1, so first-by-index picks pile 0's HIGHER. Pile 10's best is
    /// LOWER at 2/3 and never contends.
    func testClearWinnerAndDirectionalTieFallsToIndex() {
        let e = IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 12), IV.spec(3, 10)],
                          deckOrder: [IV.spec(50, 9), IV.spec(51, 9), IV.spec(52, 11)])
        assertRec(e, 0, .higher, "5-higher and 12-lower tie at 3/3; index breaks it; 10 (2/3) is out")
    }

    /// A strict single winner: top 3's HIGHER call sweeps a 9,9,4 deck (3/3)
    /// while top 8's best (higher: 9,9) reaches only 2/3.
    func testSingleWinnerSweep() {
        let e = IV.engine(tops: [IV.spec(1, 3), IV.spec(2, 8)],
                          deckOrder: [IV.spec(50, 9), IV.spec(51, 9), IV.spec(52, 4)])
        assertRec(e, 0, .higher, "3-higher sweeps (3/3); 8's best is 2/3")
    }

    /// Dead piles never win, whatever their top would have scored.
    func testDeadPilesExcluded() {
        let e = IV.engine(tops: [nil, IV.spec(2, 7)],
                          deckOrder: [IV.spec(50, 9), IV.spec(51, 3)])
        XCTAssertEqual(e.assistRecommendation()?.pile, 1,
                       "the dead pile is out even though a 2-top would sweep")
    }

    /// A ★ top makes every call safe — p = 1 beats any uncertain pile, and
    /// the certainty is DISPLAYED as a SAME call.
    func testJokerTopIsAlwaysSafestAndReadsAsSame() {
        let e = IV.engine(tops: [IV.spec(1, 0, joker: true), IV.spec(2, 8)],
                          deckOrder: [IV.spec(50, 8), IV.spec(51, 3)])
        assertRec(e, 0, .same, "★ p=1 beats 8's best (same or lower, 1/2); shown as SAME")
    }

    /// …and when another pile also reaches p = 1 WITH a SAME call, both are
    /// SAME candidates at equal size — first-by-index keeps the ★ pile.
    func testJokerTiesWithACertainSameCall() {
        let e = IV.engine(tops: [IV.spec(1, 0, joker: true), IV.spec(2, 8)],
                          deckOrder: [IV.spec(50, 8), IV.spec(51, 8)])
        // 8-same sweeps the all-8s deck: p = 1, tying the ★ pile — index wins.
        assertRec(e, 0, .same)
    }

    /// Jokers REMAINING IN THE DECK count as a success for every call — a
    /// drawn ★ is never wrong. Every best call reaches 1; among the tied
    /// candidates the SAME (pile 2, top 9 vs the deck's 9) is preferred.
    func testDeckJokersCountForEveryCallAndSameWinsTheTie() {
        // Deck: one 9, one ★. Top 5: higher = (1+1)/2 = 1. Top 12: lower =
        // (1+1)/2 = 1. Top 9: same = (1+1)/2 = 1. All tie at certainty.
        let e = IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 12), IV.spec(3, 9)],
                          deckOrder: [IV.spec(50, 9), .joker(id: 51)])
        assertRec(e, 2, .same, "the deck ★ lifts every best call to 1; rule (a) hands it to the SAME")
    }

    /// Subset deals ARE the constructed case: the visible deck differs from
    /// any full 52 — the computation must use exactly what remains.
    func testSubsetDeckIsTheOnlyTruth() {
        // A skewed subset: four kings and a 3 remain. Top 12: higher = 4/5;
        // top 4: higher = 4/5 ties it — both directional, equal sizes, so
        // first-by-index keeps pile 0.
        let e = IV.engine(tops: [IV.spec(1, 12), IV.spec(2, 4)],
                          deckOrder: [IV.spec(50, 13), IV.spec(51, 13), IV.spec(52, 13),
                                      IV.spec(53, 13), IV.spec(54, 3)])
        assertRec(e, 0, .higher, "both best calls read 4/5 off the subset; index breaks it")
    }

    // MARK: - Tie-break ladder

    /// (a) SAME over directional: deck 8,8,3,3. Pile 0 (top 5): higher 2/4,
    /// lower 2/4. Pile 1 (top 8): SAME 2/4, lower 2/4. Everything ties at
    /// 1/2 — the SAME candidate wins even though it sits at the HIGHER index
    /// (proving rule (a) outranks the index fallback).
    func testTieBreakSameBeatsDirectional() {
        let e = IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 8)],
                          deckOrder: [IV.spec(50, 8), IV.spec(51, 8),
                                      IV.spec(52, 3), IV.spec(53, 3)])
        assertRec(e, 1, .same, "at equal p the SAME call outranks pile 0's directional calls")
    }

    /// (b) two SAME candidates tie → the SMALLER pile wins: both tops are
    /// 8s over a deck of two 8s (same = 2/3 each), but pile 0 carries two
    /// extra buried cards (pileSize 3 vs 1) — the light goes to pile 1,
    /// beating the lowest-index fallback.
    func testTieBreakSmallerPileWinsAmongSames() {
        let e = IV.engine(tops: [IV.spec(1, 8, "♠"), IV.spec(2, 8, "♥")],
                          deckOrder: [IV.spec(50, 8), IV.spec(51, 8), IV.spec(52, 3)])
        for spec in [IV.spec(60, 4), IV.spec(61, 5)] {
            e.board.piles[0].cards.insert(DeckManager.toCard(spec, data: GameData.shared), at: 0)
        }
        XCTAssertEqual(e.board.pileSize(0), 3)
        XCTAssertEqual(e.board.pileSize(1), 1)
        assertRec(e, 1, .same, "equal SAME odds: the 1-card pile outranks the 3-card pile")
    }

    /// (c) a FULL tie (equal p, no SAME, equal sizes) resolves to the lowest
    /// pile index — "any" is implemented as first-by-index, never rng, so a
    /// second read returns the identical answer.
    func testTieBreakFullTieIsLowestIndexDeterministically() {
        let e = IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 12)],
                          deckOrder: [IV.spec(50, 9), IV.spec(51, 9), IV.spec(52, 11)])
        assertRec(e, 0, .higher, "5-higher and 12-lower both sweep; lowest index wins")
        assertRec(e, 0, .higher, "…and the second read agrees — deterministic, no rng")
    }

    // MARK: - Display-only

    /// The computation consumes NOTHING: rng position, deck order, and the
    /// board are byte-identical after any number of calls — so identical
    /// seeds play identical runs with the assist on or off.
    func testAssistIsAPureRead() {
        let e = GameEngine(deckSpecs: DeckManager.buildStandardDeck(), pileCount: 6,
                           runConfig: RunConfig(cols: [2, 2, 2]))
        e.start(seedOverride: 777)
        e.startRun(pillars: [nil, nil, nil], bases: [nil, nil, nil], samePower: nil)
        let rngBefore = e.rng.state
        let orderBefore = e.deck.snapshotCards().map(\.id)
        for _ in 0..<50 { _ = e.assistRecommendation() }
        XCTAssertEqual(e.rng.state, rngBefore, "no rng draw, ever")
        XCTAssertEqual(e.deck.snapshotCards().map(\.id), orderBefore, "deck order untouched")
        // And interleaved with real play, the run is unchanged vs a twin that
        // never computes the assist.
        let a = GameEngine(deckSpecs: DeckManager.buildStandardDeck(), pileCount: 6,
                           runConfig: RunConfig(cols: [2, 2, 2]))
        let b = GameEngine(deckSpecs: DeckManager.buildStandardDeck(), pileCount: 6,
                           runConfig: RunConfig(cols: [2, 2, 2]))
        for e2 in [a, b] {
            e2.start(seedOverride: 4242)
            e2.startRun(pillars: [nil, nil, nil], bases: [nil, nil, nil], samePower: nil)
        }
        for step in 0..<10 {
            _ = a.assistRecommendation()             // only A consults the assist
            let pile = step % 6
            if a.board.isActive(pile), !a.deck.isEmpty { a.guess(pile, .higher) }
            if b.board.isActive(pile), !b.deck.isEmpty { b.guess(pile, .higher) }
        }
        XCTAssertEqual(a.rng.state, b.rng.state, "assist on/off: identical runs")
        XCTAssertEqual(a.deck.snapshotCards().map(\.id), b.deck.snapshotCards().map(\.id))
        XCTAssertEqual((0..<6).map { a.board.top($0)?.id }, (0..<6).map { b.board.top($0)?.id })
    }

    // MARK: - The deal-out gate

    /// The controller's cascade gate, as a pure state machine: the assist is
    /// suppressed from birth (every deal opens with its cascade pending),
    /// released by the deal-out completion callback, and RE-ARMED by a
    /// reshuffle's re-deal. The pref stays the outer switch: an open gate
    /// never shows a disabled assist.
    func testDealOutGateSuppressesUntilCascadeLands() {
        var g = OddsAssistGate()
        XCTAssertTrue(g.dealing, "a fresh gate opens HELD — the first cascade is pending")
        XCTAssertFalse(g.allows(true), "no glow while the deal-out flies, even with the pref on")
        g.dealOutFinished()                    // the cascade's completion callback
        XCTAssertTrue(g.allows(true), "board live: the first post-deal refresh may glow")
        XCTAssertFalse(g.allows(false), "an open gate never shows a disabled assist")
        g.dealOutStarted()                     // a reshuffle queues a re-deal cascade
        XCTAssertFalse(g.allows(true), "the redeal's cascade holds the gate again")
        g.dealOutFinished()
        XCTAssertTrue(g.allows(true), "…and its completion re-opens it")
    }

    /// A mid-deal restore skips the cascade entirely — the controller calls
    /// `dealOutFinished()` straight away and the glow may show at once.
    func testDealOutGateMidDealRestoreReleasesImmediately() {
        var g = OddsAssistGate()
        g.dealOutStarted()
        g.dealOutFinished()
        XCTAssertTrue(g.allows(true))
    }

    // MARK: - The unlock gate

    func testUnlockGateLockedUntilAnyStraightWinThenPersists() {
        let store = MemoryStore()
        let wins = DeckUnlocks(store: store)
        XCTAssertFalse(wins.wonAnyStraight(), "fresh save: locked")
        wins.recordWin(deckId: "pink", tier: "regular")
        XCTAssertFalse(wins.wonAnyStraight(), "a Jokers win does not unlock it")
        wins.recordWin(deckId: "mamma", tier: "legendary")
        XCTAssertTrue(wins.wonAnyStraight(), "any deck's Straight win unlocks")
        // Persists like every unlock: a fresh reader over the same store agrees.
        XCTAssertTrue(DeckUnlocks(store: store).wonAnyStraight())
        // …and survives the deck-id migration (the .legendary suffix is what
        // the gate reads; ids may rename around it).
        SaveMigrations.migrateDeckIds(store)
        XCTAssertTrue(DeckUnlocks(store: store).wonAnyStraight())
    }
}
