import XCTest
@testable import GameCore

/// ODDS ASSIST (v6.71, single-recommendation v6.72, all-best v6.78): the
/// display-only safest-call computation, its deal-out gate, and its
/// Straight-win unlock gate. The engine promise under test:
/// `assistRecommendations()` returns EVERY (pile, call) pair whose survival
/// probability against the remaining deck ties the maximum — no tie-break
/// ladder of any kind — respecting guess()'s legality gates (no SAME on a
/// muted pile; only magnet piles while a Magnet is up), and reads nothing
/// but `remainingCounts()`: it never moves the rng, the deck order, or any
/// run state.
final class OddsAssistTests: XCTestCase {

    /// Order-insensitive comparison key.
    private func keys(_ recs: [(pile: Int, call: Guess)]) -> Set<String> {
        Set(recs.map { "\($0.pile):\($0.call.rawValue)" })
    }

    private func assertRecs(_ e: GameEngine, _ expected: [(Int, Guess)],
                            _ message: String = "", file: StaticString = #filePath,
                            line: UInt = #line) {
        let got = keys(e.assistRecommendations())
        let want = Set(expected.map { "\($0.0):\($0.1.rawValue)" })
        XCTAssertEqual(got, want, message, file: file, line: line)
    }

    // MARK: - Probability correctness on constructed boards

    /// Deck of 9,9,11 against tops 5, 12 and 10: pile 5's HIGHER (3/3) and
    /// pile 12's LOWER (3/3) tie at the top — BOTH return (v6.78: no
    /// first-by-index winner). Pile 10's best is LOWER at 2/3 and never
    /// contends.
    func testDirectionalTieReturnsBoth() {
        let e = IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 12), IV.spec(3, 10)],
                          deckOrder: [IV.spec(50, 9), IV.spec(51, 9), IV.spec(52, 11)])
        assertRecs(e, [(0, .higher), (1, .lower)],
                   "5-higher and 12-lower tie at 3/3 — both glow; 10 (2/3) is out")
    }

    /// A strict single winner: top 3's HIGHER call sweeps a 9,9,4 deck (3/3)
    /// while top 8's best (higher: 9,9) reaches only 2/3.
    func testSingleWinnerSweep() {
        let e = IV.engine(tops: [IV.spec(1, 3), IV.spec(2, 8)],
                          deckOrder: [IV.spec(50, 9), IV.spec(51, 9), IV.spec(52, 4)])
        assertRecs(e, [(0, .higher)], "3-higher sweeps (3/3); 8's best is 2/3")
    }

    /// Dead piles never win, whatever their top would have scored.
    func testDeadPilesExcluded() {
        let e = IV.engine(tops: [nil, IV.spec(2, 7)],
                          deckOrder: [IV.spec(50, 9), IV.spec(51, 3)])
        let piles = Set(e.assistRecommendations().map(\.pile))
        XCTAssertEqual(piles, [1], "the dead pile is out even though a 2-top would sweep")
    }

    /// A ★ top makes every call safe — all THREE calls are certainties and
    /// all three return (v6.78: the truth, not a SAME summary).
    func testJokerTopAllThreeCallsCertain() {
        let e = IV.engine(tops: [IV.spec(1, 0, joker: true), IV.spec(2, 8)],
                          deckOrder: [IV.spec(50, 8), IV.spec(51, 3)])
        assertRecs(e, [(0, .higher), (0, .lower), (0, .same)],
                   "★ p=1 on every call beats 8's best (1/2)")
    }

    /// Jokers REMAINING IN THE DECK count as a success for every call — a
    /// drawn ★ is never wrong. Every pile's best call reaches 1 and ALL of
    /// them return together.
    func testDeckJokersCountForEveryCall() {
        // Deck: one 9, one ★. Top 5: higher = (1+1)/2 = 1. Top 12: lower =
        // (1+1)/2 = 1. Top 9: same = (1+1)/2 = 1. All tie at certainty.
        let e = IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 12), IV.spec(3, 9)],
                          deckOrder: [IV.spec(50, 9), .joker(id: 51)])
        assertRecs(e, [(0, .higher), (1, .lower), (2, .same)],
                   "the deck ★ lifts every best call to 1; all three glow")
    }

    /// Subset deals ARE the constructed case: the visible deck differs from
    /// any full 52 — the computation must use exactly what remains.
    func testSubsetDeckIsTheOnlyTruth() {
        // A skewed subset: four kings and a 3 remain. Top 12: higher = 4/5;
        // top 4: higher = 4/5 ties it — both return.
        let e = IV.engine(tops: [IV.spec(1, 12), IV.spec(2, 4)],
                          deckOrder: [IV.spec(50, 13), IV.spec(51, 13), IV.spec(52, 13),
                                      IV.spec(53, 13), IV.spec(54, 3)])
        assertRecs(e, [(0, .higher), (1, .higher)],
                   "both best calls read 4/5 off the subset; both glow")
    }

    // MARK: - The ladder is gone (v6.78)

    /// The old rule (a) case — SAME used to outrank directional calls at
    /// equal p. Now every tied pair returns: deck 8,8,3,3 puts pile 0
    /// (top 5) at higher 2/4 / lower 2/4 and pile 1 (top 8) at lower 2/4 /
    /// same 2/4 — all four glow.
    func testNoSamePreferenceAllTiedPairsReturn() {
        let e = IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 8)],
                          deckOrder: [IV.spec(50, 8), IV.spec(51, 8),
                                      IV.spec(52, 3), IV.spec(53, 3)])
        assertRecs(e, [(0, .higher), (0, .lower), (1, .lower), (1, .same)],
                   "every 1/2 candidate returns — no SAME preference, no index pick")
    }

    /// The old rule (b) case — the smaller pile used to win among tied
    /// SAMEs. Now pile size is irrelevant: both 8-tops' SAME calls return.
    func testNoSmallestPileTieBreak() {
        let e = IV.engine(tops: [IV.spec(1, 8, "♠"), IV.spec(2, 8, "♥")],
                          deckOrder: [IV.spec(50, 8), IV.spec(51, 8), IV.spec(52, 3)])
        for spec in [IV.spec(60, 4), IV.spec(61, 5)] {
            e.board.piles[0].cards.insert(DeckManager.toCard(spec, data: GameData.shared), at: 0)
        }
        XCTAssertEqual(e.board.pileSize(0), 3)
        XCTAssertEqual(e.board.pileSize(1), 1)
        assertRecs(e, [(0, .same), (1, .same)],
                   "equal SAME odds: both piles glow, sizes 3 and 1 alike")
    }

    // MARK: - Legality (v6.78): a glow the player cannot play is a wrong glow

    /// MUTE: guess() refuses SAME on a muted pile, so a muted pile's SAME is
    /// never a candidate — even when it would have topped the board.
    func testMutedPileSameIsNeverRecommended() {
        // Top 8 muted over an all-8s deck: its SAME would be 2/2 = 1 but is
        // unplayable. The best PLAYABLE call is pile 1's higher (5 → 8s, 1).
        let e = IV.engine(tops: [IV.spec(1, 8, "♠", ["mute"]), IV.spec(2, 5)],
                          deckOrder: [IV.spec(50, 8), IV.spec(51, 8)])
        assertRecs(e, [(1, .higher)],
                   "the muted SAME (p=1) is out; the playable certainty glows")
    }

    /// MAGNET: while a magnet top is up only magnet piles take a guess —
    /// every other pile's calls are unplayable and never glow.
    func testMagnetRestrictsRecommendationsToMagnetPiles() {
        // Pile 0's higher would sweep (top 2), but pile 1 wears the magnet.
        let e = IV.engine(tops: [IV.spec(1, 2), IV.spec(2, 8, "♠", ["magnet"])],
                          deckOrder: [IV.spec(50, 9), IV.spec(51, 9)])
        let piles = Set(e.assistRecommendations().map(\.pile))
        XCTAssertEqual(piles, [1], "only the magnet pile may be recommended")
    }

    // MARK: - Brute-force cross-check

    /// An INDEPENDENT reference: for every legal (pile, call), count the
    /// remaining cards (read straight off the deck order, not
    /// remainingCounts) that guess()'s base comparison would score correct —
    /// strict compare, either-side ★ always safe — then take every pair at
    /// the max. Runs over a spread of seeded random boards (jokers, mutes,
    /// magnets included) and demands set equality with the engine on each.
    func testBruteForceReferenceAgreesOnRandomBoards() {
        var state: UInt64 = 0x5EED_CAFE
        func rnd(_ bound: Int) -> Int {   // splitmix64 — self-contained
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            z ^= z >> 31
            return Int(z % UInt64(bound))
        }
        let suits = ["♠", "♥", "♦", "♣"]
        for round in 0..<300 {
            var id = 1
            var tops: [CardSpec?] = []
            let pileCount = 2 + rnd(5)
            for _ in 0..<pileCount {
                if rnd(100) < 4 { tops.append(.joker(id: id)); id += 1; continue }
                var stickers: [String] = []
                if rnd(100) < 12 { stickers.append("mute") }
                if rnd(100) < 6 { stickers.append("magnet") }
                tops.append(IV.spec(id, 2 + rnd(13), suits[rnd(4)], stickers)); id += 1
            }
            var deck: [CardSpec] = []
            for _ in 0..<(3 + rnd(12)) {
                if rnd(100) < 8 { deck.append(.joker(id: id)) }
                else { deck.append(IV.spec(id, 2 + rnd(13), suits[rnd(4)])) }
                id += 1
            }
            let e = IV.engine(tops: tops, deckOrder: deck)
            // The reference, from first principles.
            let remaining = e.deck.snapshotCards()
            let magnets = (0..<e.board.size).filter {
                e.board.isActive($0) && (e.board.top($0)?.stickers.contains { $0.type == "magnet" } ?? false)
            }
            var best = -1.0
            var expect: Set<String> = []
            for i in 0..<e.board.size where e.board.isActive(i) {
                guard let top = e.board.top(i) else { continue }
                if !magnets.isEmpty, !magnets.contains(i) { continue }
                let muted = top.stickers.contains { $0.type == "mute" }
                for call in [Guess.higher, .lower, .same] {
                    if call == .same, muted { continue }
                    var wins = 0
                    for card in remaining {
                        let correct: Bool
                        if card.joker || top.joker { correct = true }
                        else {
                            switch call {
                            case .higher: correct = card.value > top.value
                            case .lower: correct = card.value < top.value
                            case .same: correct = card.value == top.value
                            }
                        }
                        if correct { wins += 1 }
                    }
                    let p = Double(wins) / Double(remaining.count)
                    if p > best + 1e-9 { best = p; expect = ["\(i):\(call.rawValue)"] }
                    else if abs(p - best) <= 1e-9 { expect.insert("\(i):\(call.rawValue)") }
                }
            }
            XCTAssertEqual(keys(e.assistRecommendations()), expect,
                           "round \(round): the engine disagrees with the reference count")
        }
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
        for _ in 0..<50 { _ = e.assistRecommendations() }
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
            _ = a.assistRecommendations()            // only A consults the assist
            let pile = step % 6
            if a.board.isActive(pile), !a.deck.isEmpty { a.guess(pile, .higher) }
            if b.board.isActive(pile), !b.deck.isEmpty { b.guess(pile, .higher) }
        }
        XCTAssertEqual(a.rng.state, b.rng.state, "assist on/off: identical runs")
        XCTAssertEqual(a.deck.snapshotCards().map(\.id), b.deck.snapshotCards().map(\.id))
        XCTAssertEqual((0..<6).map { a.board.top($0)?.id }, (0..<6).map { b.board.top($0)?.id })
    }

    /// Deterministic: a second read returns the identical set, in the
    /// identical order — no rng anywhere in the enumeration.
    func testRepeatedReadsAgree() {
        let e = IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 12)],
                          deckOrder: [IV.spec(50, 9), IV.spec(51, 9), IV.spec(52, 11)])
        let first = e.assistRecommendations()
        let second = e.assistRecommendations()
        XCTAssertEqual(first.map { "\($0.pile):\($0.call.rawValue)" },
                       second.map { "\($0.pile):\($0.call.rawValue)" })
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
