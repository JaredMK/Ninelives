import XCTest
@testable import GameCore

/// The autopilot's decision rule. Each test pins one of the behaviours the
/// pilot is supposed to have: survive first, bank the shield, hoard the Joker,
/// then chase coins, then score.
final class AutoPilotTests: XCTestCase {

    /// A deck of one card at each of the given ranks (key 0 = jokers).
    private func deck(_ pairs: [Int: Int]) -> [Int: Int] { pairs }

    private func pile(_ i: Int, top: Int, size: Int = 3, joker: Bool = false,
                      hint: Guess? = nil, coins: Int = 0, sameCoins: Int = 0) -> AutoPilot.PileView {
        AutoPilot.PileView(index: i, topValue: top, topIsJoker: joker, size: size,
                           hint: hint, coinValue: coins, sameCoinValue: sameCoins)
    }

    // MARK: - Survival

    func testJokersCountTowardEveryDirectionNotJustLower() {
        // 4 jokers and nothing else: every call is certain, so no direction may
        // look worse than another. The old pilot bucketed jokers as rank 0 and
        // read them as "lower than everything", skewing every call to LOWER.
        let input = AutoPilot.Input(piles: [pile(0, top: 7)], deckCounts: [0: 4],
                                    sameCharged: true)
        let cands = AutoPilot.candidates(input)
        XCTAssertEqual(cands.count, 1)
        XCTAssertEqual(cands[0].p, 1.0, accuracy: 0.0001,
                       "a deck of only jokers survives any call")
    }

    func testItPlaysTheHighestSurvivalOdds() {
        // Pile 0 tops a 2 (almost everything is higher); pile 1 tops an Ace.
        let counts = deck([3: 4, 4: 4, 5: 4, 14: 1])
        let input = AutoPilot.Input(piles: [pile(0, top: 2), pile(1, top: 14)],
                                    deckCounts: counts, sameCharged: true)
        let d = AutoPilot.choose(input)
        XCTAssertEqual(d?.move.pile, 0)
        XCTAssertEqual(d?.move.call, .higher, "12 of 13 cards beat a 2")
    }

    func testACertaintyBeatsMerelyGoodOdds() {
        // Pile 1 has a Tell (guaranteed), pile 0 only has strong odds.
        // Deck: eight 3s and two 10s. A pile topping a 5 is 80% (lower), good
        // but not certain. Pile 1 carries a Tell, which IS certain.
        let counts = deck([3: 8, 10: 2])
        let input = AutoPilot.Input(piles: [pile(0, top: 5), pile(1, top: 9, hint: .lower)],
                                    deckCounts: counts, sameCharged: true)
        let d = AutoPilot.choose(input)
        XCTAssertEqual(d?.move.pile, 1)
        XCTAssertEqual(d?.move.call, .lower)
        XCTAssertEqual(d?.move.p ?? 0, 1.0, accuracy: 0.0001)
    }

    // MARK: - The Same shield

    func testAJokerTopBanksTheShieldWhenEmpty() {
        let input = AutoPilot.Input(piles: [pile(0, top: 0, joker: true)],
                                    deckCounts: deck([5: 4]), sameCharged: false)
        let d = AutoPilot.choose(input)
        XCTAssertEqual(d?.move.call, .same, "a Joker Same is free — always bank it")
        XCTAssertTrue(d?.move.banks ?? false)
    }

    func testAJokerIsHeldBackWhileTheShieldIsAlreadyCharged() {
        // Joker on pile 0, an ordinary pile 1 that is also perfectly safe.
        // The Joker must be saved for after the shield is spent.
        let input = AutoPilot.Input(piles: [pile(0, top: 0, joker: true), pile(1, top: 2)],
                                    deckCounts: deck([5: 4]), sameCharged: true)
        let d = AutoPilot.choose(input)
        XCTAssertEqual(d?.move.pile, 1, "don't waste a guaranteed Same at full charge")
    }

    func testAHeldJokerIsPlayedWhenItIsTheOnlyPileLeft() {
        let input = AutoPilot.Input(piles: [pile(0, top: 0, joker: true)],
                                    deckCounts: deck([5: 4]), sameCharged: true)
        XCTAssertEqual(AutoPilot.choose(input)?.move.pile, 0,
                       "forced: play the Joker rather than stall")
    }

    func testEqualOddsPreferTheChargeBankingCall() {
        // 4 above, 4 below, 4 equal — all three calls are 1/3. Uncharged, the
        // Same is strictly better because it also banks a shield.
        let counts = deck([2: 4, 7: 4, 9: 4])
        let input = AutoPilot.Input(piles: [pile(0, top: 7)], deckCounts: counts,
                                    sameCharged: false)
        let d = AutoPilot.choose(input)
        XCTAssertEqual(d?.move.call, .same)
        XCTAssertTrue(d?.move.banks ?? false)
    }

    // MARK: - Peeks

    func testAPeekedTieIsSpentOnChargingTheShield() {
        // The next card is known to be a 7; pile 1 tops a 7, so Same is certain.
        let input = AutoPilot.Input(piles: [pile(0, top: 2), pile(1, top: 7)],
                                    deckCounts: deck([7: 4]), sameCharged: false,
                                    peekedValue: 7)
        let d = AutoPilot.choose(input)
        XCTAssertEqual(d?.move.pile, 1)
        XCTAssertEqual(d?.move.call, .same, "a peeked tie is a free shield")
        XCTAssertTrue(d?.move.banks ?? false)
    }

    func testAPeekedJokerBanksTheShieldWhenEmptyAndIsPlayedSafeWhenFull() {
        let uncharged = AutoPilot.Input(piles: [pile(0, top: 5)], deckCounts: deck([0: 1]),
                                        sameCharged: false, peekedValue: 0, peekedIsJoker: true)
        XCTAssertEqual(AutoPilot.choose(uncharged)?.move.call, .same)

        let charged = AutoPilot.Input(piles: [pile(0, top: 5)], deckCounts: deck([0: 1]),
                                      sameCharged: true, peekedValue: 0, peekedIsJoker: true)
        XCTAssertEqual(AutoPilot.choose(charged)?.move.call, .higher,
                       "already charged — the Joker's Same would be wasted")
    }

    func testAPeekResolvesTheDirectionExactly() {
        let input = AutoPilot.Input(piles: [pile(0, top: 5)], deckCounts: deck([9: 1]),
                                    sameCharged: true, peekedValue: 9)
        XCTAssertEqual(AutoPilot.choose(input)?.move.call, .higher)
        let low = AutoPilot.Input(piles: [pile(0, top: 5)], deckCounts: deck([2: 1]),
                                  sameCharged: true, peekedValue: 2)
        XCTAssertEqual(AutoPilot.choose(low)?.move.call, .lower)
    }

    // MARK: - Tiebreaks: coins, then score

    func testEquallySafePilesPreferTheOneThatPaysCoins() {
        // Identical tops and sizes; pile 1 carries a payout sticker.
        let counts = deck([9: 8])
        let input = AutoPilot.Input(
            piles: [pile(0, top: 2, size: 4), pile(1, top: 2, size: 4, coins: 5)],
            deckCounts: counts, sameCharged: true)
        XCTAssertEqual(AutoPilot.choose(input)?.move.pile, 1, "same odds → take the coins")
    }

    func testWithNothingElseToSeparateThemItFeedsTheSmallestPile() {
        // Score is alive × smallest pile, so a card is worth most on the runt.
        let counts = deck([9: 8])
        let input = AutoPilot.Input(
            piles: [pile(0, top: 2, size: 7), pile(1, top: 2, size: 2)],
            deckCounts: counts, sameCharged: true)
        XCTAssertEqual(AutoPilot.choose(input)?.move.pile, 1, "grow the smallest pile")
    }

    func testCoinsOutrankScoreButSurvivalOutranksBoth() {
        // Deck: eight 3s and two 10s.
        let counts = deck([3: 8, 10: 2])
        // Both tops are 2 → both certain. Pile 0 is tiny (better for score),
        // pile 1 pays. Coins win the tiebreak.
        let tie = AutoPilot.Input(
            piles: [pile(0, top: 2, size: 2), pile(1, top: 2, size: 9, coins: 6)],
            deckCounts: counts, sameCharged: true)
        XCTAssertEqual(AutoPilot.choose(tie)?.move.pile, 1)

        // Now the paying pile tops a 5 — 80%, outside the tie window. Survival
        // wins no matter how much it pays.
        let unsafe = AutoPilot.Input(
            piles: [pile(0, top: 2, size: 2), pile(1, top: 5, size: 9, coins: 60)],
            deckCounts: counts, sameCharged: true)
        XCTAssertEqual(AutoPilot.choose(unsafe)?.move.pile, 0,
                       "no payout is worth dying for")
    }

    func testTheChoiceIsDeterministic() {
        let counts = deck([9: 8])
        let input = AutoPilot.Input(
            piles: [pile(0, top: 2, size: 4), pile(1, top: 2, size: 4)],
            deckCounts: counts, sameCharged: true)
        let a = AutoPilot.choose(input), b = AutoPilot.choose(input)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a?.move.pile, 0, "fully tied → lowest index")
    }

    // MARK: - Reshuffle policy

    func testItReshufflesOnlyBeforeTheFirstGuessAndOnlyWhenAffordable() {
        XCTAssertTrue(AutoPilot.shouldReshuffle(guessesMade: 0, bestRaw: 0.4,
                                                redealCost: 5, coins: 10))
        XCTAssertFalse(AutoPilot.shouldReshuffle(guessesMade: 1, bestRaw: 0.4,
                                                 redealCost: 5, coins: 10),
                       "the board is already in play")
        XCTAssertFalse(AutoPilot.shouldReshuffle(guessesMade: 0, bestRaw: 0.9,
                                                 redealCost: 5, coins: 10),
                       "the deal-out is fine")
        XCTAssertFalse(AutoPilot.shouldReshuffle(guessesMade: 0, bestRaw: 0.4,
                                                 redealCost: 5, coins: 2),
                       "can't afford it")
        XCTAssertFalse(AutoPilot.shouldReshuffle(guessesMade: 0, bestRaw: 0.4,
                                                 redealCost: 40, coins: 999),
                       "too expensive to be worth it")
    }

    func testNoAlivePilesMeansNoMove() {
        XCTAssertNil(AutoPilot.choose(AutoPilot.Input(piles: [], deckCounts: deck([5: 4]),
                                                      sameCharged: false)))
    }
}
