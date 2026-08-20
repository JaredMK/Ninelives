import XCTest
@testable import GameCore

/// ODDS ASSIST (v6.71): the display-only safest-pile computation and its
/// Straight-win unlock gate. The engine promise under test: `assistPiles()`
/// returns the argmax set of best-call survival probability against the
/// remaining deck, reads nothing but `remainingCounts()`, and never moves
/// the rng, the deck order, or any run state.
final class OddsAssistTests: XCTestCase {

    // MARK: - Probability correctness on constructed boards

    /// Deck of 9,9,11 against tops 5, 12 and 10: pile 5's HIGHER (3/3) and
    /// pile 12's LOWER (3/3) tie and both glow; pile 10's best is LOWER at
    /// 2/3 and drops out.
    func testClearWinnerAndTies() {
        let e = IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 12), IV.spec(3, 10)],
                          deckOrder: [IV.spec(50, 9), IV.spec(51, 9), IV.spec(52, 11)])
        XCTAssertEqual(e.assistPiles(), [0, 1], "5-higher and 12-lower tie at 3/3; 10 (2/3) is out")
    }

    /// A strict single winner: top 3's HIGHER call sweeps a 9,9,4 deck (3/3)
    /// while top 8's best (higher: 9,9) reaches only 2/3.
    func testSingleWinnerSweep() {
        let e = IV.engine(tops: [IV.spec(1, 3), IV.spec(2, 8)],
                          deckOrder: [IV.spec(50, 9), IV.spec(51, 9), IV.spec(52, 4)])
        XCTAssertEqual(e.assistPiles(), [0], "3-higher sweeps (3/3); 8's best is 2/3")
    }

    /// Dead piles never glow, whatever their top would have scored.
    func testDeadPilesExcluded() {
        let e = IV.engine(tops: [nil, IV.spec(2, 7)],
                          deckOrder: [IV.spec(50, 9), IV.spec(51, 3)])
        XCTAssertEqual(e.assistPiles(), [1], "the dead pile is out even though a 2-top would sweep")
    }

    /// A ★ top makes every call safe — p = 1 beats any uncertain pile.
    func testJokerTopIsAlwaysSafest() {
        let e = IV.engine(tops: [IV.spec(1, 0, joker: true), IV.spec(2, 8)],
                          deckOrder: [IV.spec(50, 8), IV.spec(51, 3)])
        XCTAssertEqual(e.assistPiles(), [0], "★ p=1 beats 8's best (same or lower, 1/2)")
    }

    /// …and when another pile also reaches p = 1, they tie.
    func testJokerTiesWithACertainCall() {
        let e = IV.engine(tops: [IV.spec(1, 0, joker: true), IV.spec(2, 8)],
                          deckOrder: [IV.spec(50, 8), IV.spec(51, 8)])
        // 8-same sweeps the all-8s deck: p = 1, tying the ★ pile.
        XCTAssertEqual(e.assistPiles(), [0, 1])
    }

    /// Jokers REMAINING IN THE DECK count as a success for every call — a
    /// drawn ★ is never wrong.
    func testDeckJokersCountForEveryCall() {
        // Deck: one 9, one ★. Top 5: higher = (1+1)/2 = 1. Top 12: lower =
        // (1+1)/2 = 1. Top 9: same = (1+1)/2 = 1. All tie at certainty.
        let e = IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 12), IV.spec(3, 9)],
                          deckOrder: [IV.spec(50, 9), .joker(id: 51)])
        XCTAssertEqual(e.assistPiles(), [0, 1, 2], "the deck ★ lifts every best call to 1")
    }

    /// Subset deals ARE the constructed case: the visible deck differs from
    /// any full 52 — the computation must use exactly what remains.
    func testSubsetDeckIsTheOnlyTruth() {
        // A skewed subset: four kings and a 3 remain. Top 12: higher = 4/5;
        // top 4: lower = 1/5, higher = 4/5 ties pile 0's.
        let e = IV.engine(tops: [IV.spec(1, 12), IV.spec(2, 4)],
                          deckOrder: [IV.spec(50, 13), IV.spec(51, 13), IV.spec(52, 13),
                                      IV.spec(53, 13), IV.spec(54, 3)])
        XCTAssertEqual(e.assistPiles(), [0, 1], "both best calls read 4/5 off the subset")
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
        for _ in 0..<50 { _ = e.assistPiles() }
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
            _ = a.assistPiles()                      // only A consults the assist
            let pile = step % 6
            if a.board.isActive(pile), !a.deck.isEmpty { a.guess(pile, .higher) }
            if b.board.isActive(pile), !b.deck.isEmpty { b.guess(pile, .higher) }
        }
        XCTAssertEqual(a.rng.state, b.rng.state, "assist on/off: identical runs")
        XCTAssertEqual(a.deck.snapshotCards().map(\.id), b.deck.snapshotCards().map(\.id))
        XCTAssertEqual((0..<6).map { a.board.top($0)?.id }, (0..<6).map { b.board.top($0)?.id })
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
