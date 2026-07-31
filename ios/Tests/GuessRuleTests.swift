import XCTest
@testable import GameCore

/// The core rules the web suite pins: ace-high, strict comparison, the tie rule,
/// Jokers, and the full save-priority chain.
final class GuessRuleTests: XCTestCase {

    /// A board built from EXACT cards, so a rule can be exercised in isolation.
    /// The deck is stacked by id order (the shuffle is bypassed by handing the
    /// engine one spec per pile plus the draws, then forcing the next card).
    private func engine(piles: Int = 3, cols: [Int]? = nil, sameCharge: Bool = false,
                        samePower: String? = nil, specs: [CardSpec]? = nil) -> GameEngine {
        let e = GameEngine(deckSpecs: specs ?? DeckManager.buildStandardDeck(),
                           pileCount: piles,
                           runConfig: RunConfig(cols: cols, sameCharge: sameCharge, samePower: samePower))
        e.start(seedOverride: 12345)
        e.startRun(pillars: cols.map { Array(repeating: nil, count: $0.count) },
                   bases: cols.map { Array(repeating: nil, count: $0.count) },
                   samePower: .some(samePower))
        return e
    }

    /// Force pile 0's top to `topValue` and the next draw to `drawValue`.
    private func stage(_ e: GameEngine, top topValue: Int, next drawValue: Int) {
        e.board.piles[0].cards = [DeckManager.cardForValue(topValue)]
        e.debug.setNextCard(drawValue)
    }

    // MARK: - Ace high

    func testAceIsHigh() {
        XCTAssertEqual(DeckManager.ranks.last?.label, "A")
        XCTAssertEqual(DeckManager.ranks.last?.value, 14)
        XCTAssertEqual(DeckManager.ranks.first?.value, 2)
        // K < A
        let e = engine()
        stage(e, top: 13, next: 14)
        e.guess(0, .higher)
        XCTAssertTrue(e.board.isActive(0), "A must beat K on a HIGHER call")
    }

    func testAceLosesToNothingOnHigher() {
        let e = engine()
        stage(e, top: 14, next: 13)
        e.guess(0, .higher)
        XCTAssertFalse(e.board.isActive(0), "nothing is higher than an Ace")
    }

    // MARK: - Strict comparison + the tie rule

    func testHigherAndLowerAreStrict() {
        for (top, drawn, call, survives) in [
            (5, 9, Guess.higher, true), (9, 5, .higher, false),
            (9, 5, .lower, true), (5, 9, .lower, false),
        ] as [(Int, Int, Guess, Bool)] {
            let e = engine()
            stage(e, top: top, next: drawn)
            e.guess(0, call)
            XCTAssertEqual(e.board.isActive(0), survives, "\(call.rawValue) \(top)→\(drawn)")
        }
    }

    func testTieKillsOnHigherAndLower() {
        for call in [Guess.higher, Guess.lower] {
            let e = engine()
            stage(e, top: 7, next: 7)
            e.guess(0, call)
            XCTAssertFalse(e.board.isActive(0), "a tie must kill on a \(call.rawValue) guess")
        }
    }

    func testTieSurvivesOnlyOnCorrectSame() {
        let e = engine()
        stage(e, top: 7, next: 7)
        e.guess(0, .same)
        XCTAssertTrue(e.board.isActive(0), "a correct Same survives a tie")
        XCTAssertTrue(e.sameCharge, "a correct Same banks a charge")
    }

    func testWrongSameKills() {
        let e = engine()
        stage(e, top: 7, next: 9)
        e.guess(0, .same)
        XCTAssertFalse(e.board.isActive(0))
    }

    func testSameChargeCapsAtOne() {
        let e = engine()
        stage(e, top: 7, next: 7)
        e.guess(0, .same)
        XCTAssertTrue(e.sameCharge)
        stage(e, top: 4, next: 4)
        e.guess(0, .same)
        XCTAssertTrue(e.sameCharge, "a second Same at full charge does not stack")
    }

    // MARK: - Joker

    func testDrawnJokerIsAlwaysCorrect() {
        for call in Guess.allCases {
            let e = engine()
            e.board.piles[0].cards = [DeckManager.cardForValue(7)]
            e.debug.setNextCardObj(LiveCard(id: -99, label: "★", value: 0, suit: "★", red: false, joker: true))
            e.guess(0, call)
            XCTAssertTrue(e.board.isActive(0), "a drawn Joker must survive a \(call.rawValue) call")
        }
    }

    func testJokerOnTheTopIsAlwaysCorrect() {
        for call in Guess.allCases {
            let e = engine()
            e.board.piles[0].cards = [LiveCard(id: -98, label: "★", value: 0, suit: "★", red: false, joker: true)]
            e.debug.setNextCard(9)
            e.guess(0, call)
            XCTAssertTrue(e.board.isActive(0), "any card landing ON a Joker must survive a \(call.rawValue) call")
        }
    }

    func testJokerGrantsNothingOnHigherOrLower() {
        let e = engine()
        e.board.piles[0].cards = [DeckManager.cardForValue(7)]
        e.debug.setNextCardObj(LiveCard(id: -97, label: "★", value: 0, suit: "★", red: false, joker: true))
        e.guess(0, .higher)
        XCTAssertFalse(e.sameCharge, "a Joker on a HIGHER call banks no charge")
    }

    func testJokerOnASameCallCountsAsAFullyCorrectSame() {
        let e = engine()
        e.board.piles[0].cards = [DeckManager.cardForValue(7)]
        e.debug.setNextCardObj(LiveCard(id: -96, label: "★", value: 0, suit: "★", red: false, joker: true))
        e.guess(0, .same)
        XCTAssertTrue(e.sameCharge, "SAME with a Joker involved banks a charge like any correct Same")
    }

    // MARK: - The save-priority chain

    /// Same Charge is the LAST-priority backstop: it is spent only when nothing
    /// above it saved, and it saves BOTH death types.
    func testSameChargeSavesAWrongDirectionalGuess() {
        let e = engine(sameCharge: true)
        stage(e, top: 5, next: 3)
        e.guess(0, .higher)
        XCTAssertTrue(e.board.isActive(0), "the charge saves the pile")
        XCTAssertFalse(e.sameCharge, "the charge is spent")
        XCTAssertEqual(e.board.top(0)?.value, 3, "the would-be-killing card lands as the new pile card")
    }

    func testSameChargeSavesALethalTie() {
        let e = engine(sameCharge: true)
        stage(e, top: 6, next: 6)
        e.guess(0, .higher)
        XCTAssertTrue(e.board.isActive(0))
        XCTAssertFalse(e.sameCharge)
    }

    func testSameChargeIsNotSpentOnACorrectGuess() {
        let e = engine(sameCharge: true)
        stage(e, top: 5, next: 9)
        e.guess(0, .higher)
        XCTAssertTrue(e.sameCharge, "a correct guess never spends the charge")
    }

    /// A Suit Guard sits ABOVE the charge in the chain: with both available the
    /// guard absorbs the miss and the charge survives.
    func testGuardOutranksSameCharge() {
        var specs = DeckManager.buildStandardDeck()
        // Give the ♦ 5 a ♥ guard: a ♥ landing on it is absorbed.
        guard let guardType = GameData.shared.items.stickers.first(where: { $0.behavior == "suitImmunity" && $0.suit == "♥" })
        else { XCTFail("items.js must ship a ♥ Suit Guard"); return }
        let carrier = specs.firstIndex { $0.suit == "♦" && $0.currentRank == 5 }!
        specs[carrier].stickers.append(StickerRecord(type: guardType.id))

        let e = GameEngine(deckSpecs: specs, pileCount: 3, runConfig: RunConfig(sameCharge: true))
        e.start(seedOverride: 999)
        e.startRun()
        e.board.piles[0].cards = [DeckManager.toCard(specs[carrier])]
        let heart = specs.first { $0.suit == "♥" && $0.currentRank == 3 }!
        e.debug.setNextCardObj(DeckManager.toCard(heart))
        let before = e.deck.remaining()
        e.guess(0, .higher)                                  // 5 → 3 is wrong
        XCTAssertTrue(e.board.isActive(0), "the guard absorbs the miss")
        XCTAssertTrue(e.sameCharge, "the charge is untouched — the guard outranks it")
        XCTAssertEqual(e.board.top(0)?.value, 5, "the pile keeps its top")
        XCTAssertEqual(e.deck.remaining(), before, "the drawn card is reshuffled back in")
    }

    func testGuardIsBidirectionalAndUnlimited() {
        var specs = DeckManager.buildStandardDeck()
        guard let guardType = GameData.shared.items.stickers.first(where: { $0.behavior == "suitImmunity" && $0.suit == "♥" })
        else { XCTFail("items.js must ship a ♥ Suit Guard"); return }
        // The DRAWN card carries the guard; the pile top is the matching suit.
        let carrier = specs.firstIndex { $0.suit == "♦" && $0.currentRank == 4 }!
        specs[carrier].stickers.append(StickerRecord(type: guardType.id))
        let e = GameEngine(deckSpecs: specs, pileCount: 3)
        e.start(seedOverride: 4321)
        e.startRun()
        let heartTop = specs.first { $0.suit == "♥" && $0.currentRank == 10 }!
        for _ in 0..<3 {                                      // guards never spend
            e.board.piles[0].cards = [DeckManager.toCard(heartTop)]
            e.debug.setNextCardObj(DeckManager.toCard(specs[carrier]))
            e.guess(0, .higher)                               // 10 → 4 is wrong
            XCTAssertTrue(e.board.isActive(0), "a matching guard saves repeatedly")
        }
    }

    // MARK: - Win / loss

    func testEmptyingTheDeckWins() {
        let e = engine(piles: 3)
        e.debug.drainDeck()
        e.debug.evaluate()
        XCTAssertEqual(e.status, "won")
        XCTAssertEqual(e.run.result, "win")
    }

    func testAllPilesDeadLoses() {
        let e = engine(piles: 2)
        e.board.kill(0)
        e.board.kill(1)
        e.debug.evaluate()
        XCTAssertEqual(e.status, "lost")
        XCTAssertEqual(e.run.result, "loss")
    }

    /// Death is checked BEFORE the end-of-deck clear: if the FINAL deck card
    /// kills the last alive pile, that is a LOSS, never a clear.
    func testFinalCardKillingTheLastPileIsALoss() {
        let e = engine(piles: 2)
        e.board.kill(1)
        e.board.piles[0].cards = [DeckManager.cardForValue(10)]
        e.debug.trimDeck(to: 0)
        e.debug.setNextCard(2)                                // exactly one card left
        XCTAssertEqual(e.deck.remaining(), 1)
        e.guess(0, .higher)                                   // wrong → the last pile dies
        XCTAssertEqual(e.status, "lost", "an empty deck must not turn a wipe into a win")
    }

    func testNoGuessesBeforeStartRun() {
        let e = GameEngine(deckSpecs: DeckManager.buildStandardDeck(), pileCount: 3)
        e.start(seedOverride: 7)
        XCTAssertTrue(e.canApplyStickers(), "the sticker window is open before Start Run")
        let before = e.deck.remaining()
        e.guess(0, .higher)
        XCTAssertEqual(e.deck.remaining(), before, "a guess during the sticker phase is a no-op")
        e.startRun()
        XCTAssertFalse(e.canApplyStickers(), "Start Run closes the sticker window")
        XCTAssertTrue(e.isRunStarted())
    }

    func testGuessOnADeadPileIsANoOp() {
        let e = engine()
        e.board.kill(0)
        let before = e.deck.remaining()
        e.guess(0, .higher)
        XCTAssertEqual(e.deck.remaining(), before)
    }

    // MARK: - Deal shape

    func testTheDealPutsOneCardOnEveryPile() {
        let e = engine(piles: 9)
        XCTAssertEqual(e.board.size, 9)
        for i in 0..<9 { XCTAssertEqual(e.board.piles[i].cards.count, 1) }
        XCTAssertEqual(e.deck.remaining(), 52 - 9)
    }

    func testSameSeedDealsTheSameBoard() {
        let a = engine(), b = engine()
        XCTAssertEqual(a.board.piles.map { $0.cards.first?.id },
                       b.board.piles.map { $0.cards.first?.id })
    }

    func testCardsDrawnExcludesTheInitialDeal() {
        let e = engine(piles: 4)
        XCTAssertEqual(e.run.dealDraws, 4, "the deal's own draws are snapshotted at Start Run")
        stage(e, top: 5, next: 9)
        e.guess(0, .higher)
        XCTAssertEqual(e.run.cardsDrawn, 1, "only play draws count")
    }
}
