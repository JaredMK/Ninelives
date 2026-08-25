import XCTest
@testable import GameCore

/// Payout + score rules. Tests pin RULES and read tunables live from the data
/// files, so a retune in items.js never breaks the suite.
final class EconomyAndScoreTests: XCTestCase {
    private let data = GameData.shared
    private lazy var eco = Economy(data: data)

    // MARK: - dealFlat

    func testDealFlatFormula() {
        let base = data.items.economy.dealBase
        let bossBonus = data.items.economy.bossBonus
        let cap = Int(data.items.economy.num("stageCap", 3))
        for stage in 1...5 {
            let s = min(stage, cap)   // ENDLESS FREEZE (v6.78): the stage term caps
            for rating in 1...3 {
                XCTAssertEqual(eco.dealFlat(stage: stage, rating: rating, isBoss: false),
                               base + Double(s) * Double(1 + rating),
                               "dealBase + min(stage, stageCap) × (1 + rating)")
            }
            // A boss forces rating 3 and adds bossBonus.
            XCTAssertEqual(eco.dealFlat(stage: stage, rating: 0, isBoss: true),
                           base + Double(s) * 4 + bossBonus)
            XCTAssertEqual(eco.dealFlat(stage: stage, rating: 1, isBoss: true),
                           eco.dealFlat(stage: stage, rating: 3, isBoss: true),
                           "a boss ignores the node's own rating")
        }
    }

    func testNoStageContextPaysNoFlatBase() {
        // Ambush / subset deals arrive with no stage or no rating.
        XCTAssertEqual(eco.dealFlat(stage: 0, rating: 3, isBoss: false), 0)
        XCTAssertEqual(eco.dealFlat(stage: 0, rating: 3, isBoss: true), 0)
        XCTAssertEqual(eco.dealFlat(stage: 2, rating: 0, isBoss: false), 0)
    }

    /// ENDLESS FREEZE (v6.78): past phase 3 the per-deal payout stops
    /// growing — every endless stage pays exactly the phase-3 rate for its
    /// difficulty, boss or not.
    func testEndlessStagesFreezeAtPhaseThreeRates() {
        for rating in 1...3 {
            let phase3 = eco.dealFlat(stage: 3, rating: rating, isBoss: false)
            for stage in [4, 6, 12, 40] {
                XCTAssertEqual(eco.dealFlat(stage: stage, rating: rating, isBoss: false), phase3,
                               "stage \(stage) pays phase-3 rates, forever")
            }
            XCTAssertEqual(eco.dealFlat(stage: 9, rating: rating, isBoss: true),
                           eco.dealFlat(stage: 3, rating: rating, isBoss: true),
                           "endless bosses freeze too")
        }
        // …while the climb itself still grows to the cap.
        XCTAssertLessThan(eco.dealFlat(stage: 2, rating: 2, isBoss: false),
                          eco.dealFlat(stage: 3, rating: 2, isBoss: false))
    }

    // MARK: - breakdown

    private func stats(_ build: (inout PayoutStats) -> Void) -> PayoutStats {
        var s = PayoutStats(); build(&s); return s
    }

    func testALossPaysNothing() {
        let b = eco.breakdown(stats { $0.won = false; $0.flat = 20; $0.aliveCount = 5; $0.minAliveCards = 4
                                      $0.extraCoinUnits = 9; $0.pillarBonus = 7; $0.eventBonus = 3 })
        XCTAssertEqual(b.total, 0)
        XCTAssertEqual(b.product, 0)
        XCTAssertEqual(b.flat, 0)
    }

    func testTotalIsFlatPlusExtraCoinPlusPillarsPlusEvents() {
        let s = stats { $0.won = true; $0.flat = 10; $0.extraCoinUnits = 3; $0.pillarBonus = 4; $0.eventBonus = 2 }
        let b = eco.breakdown(s)
        XCTAssertEqual(b.total, 10 + Double(3) * eco.extraCoinValue + 4 + 2)
    }

    func testTotalClampsAtZeroWhenTributeCostsOutweighTheReward() {
        let b = eco.breakdown(stats { $0.won = true; $0.flat = 4; $0.eventBonus = -500 })
        XCTAssertEqual(b.total, 0, "a win must never charge the player coins")
    }

    func testProductIsPilesTimesSmallestAndIsScoreNotCoins() {
        let s = stats { $0.won = true; $0.flat = 0; $0.aliveCount = 6; $0.minAliveCards = 4 }
        let b = eco.breakdown(s)
        XCTAssertEqual(b.product, 24, "the score is alive piles × smallest alive pile")
        XCTAssertEqual(b.total, 0, "the product no longer feeds the coin total")
    }

    func testAmbushScoresLikeEveryOtherBattle() {
        let b = eco.breakdown(stats { $0.won = true; $0.aliveCount = 8; $0.minAliveCards = 5; $0.ambush = true })
        XCTAssertEqual(b.product, 40, "every battle scores — an ambush is no exception (v5.82)")
        let plain = eco.breakdown(stats { $0.won = true; $0.aliveCount = 8; $0.minAliveCards = 5 })
        XCTAssertEqual(b.product, plain.product, "the ambush flag no longer touches the product")
    }

    func testProductIsZeroWithNoAlivePiles() {
        let b = eco.breakdown(stats { $0.won = true; $0.aliveCount = 0; $0.minAliveCards = 7 })
        XCTAssertEqual(b.product, 0)
    }

    func testLiveBonusEqualsTotalMinusFlat() {
        var s = PayoutStats()
        s.won = true; s.flat = 12; s.extraCoinUnits = 2; s.pillarBonus = 5; s.eventBonus = 3
        s.liveBonusCoins = s.eventBonus
        let b = eco.breakdown(s)
        XCTAssertEqual(eco.liveBonus(s), b.total - b.flat,
                       "the above-board 'base + bonus' line and the summary can never disagree")
    }

    func testExtraCoinValueComesFromItemsJs() {
        XCTAssertEqual(eco.extraCoinValue, data.stickerTypes.get("extraCoin")?.num("value", 1))
    }

    // MARK: - Board-side payout inputs

    func testMinAliveCardsExcludesAnchoredPiles() {
        let board = BoardState(size: 3, data: data)
        board.push(0, DeckManager.cardForValue(5))                        // 1 card, anchored below
        board.push(1, DeckManager.cardForValue(6)); board.push(1, DeckManager.cardForValue(7))
        board.push(2, DeckManager.cardForValue(8)); board.push(2, DeckManager.cardForValue(9))
        board.push(2, DeckManager.cardForValue(10))
        XCTAssertEqual(board.minAliveCards(), 1)
        board.top(0)?.stickers.append(StickerRecord(type: "anchor"))
        XCTAssertTrue(board.isAnchored(0))
        XCTAssertEqual(board.minAliveCards(), 2, "an anchored pile can't drag the product down")
        XCTAssertEqual(board.trueMinAliveCards(), 1, "the true minimum still sees it")
    }

    func testEveryAlivePileAnchoredFallsBackToTheTrueSmallest() {
        let board = BoardState(size: 2, data: data)
        board.push(0, DeckManager.cardForValue(5))
        board.push(1, DeckManager.cardForValue(6)); board.push(1, DeckManager.cardForValue(7))
        board.top(0)?.stickers.append(StickerRecord(type: "anchor"))
        board.top(1)?.stickers.append(StickerRecord(type: "anchor"))
        XCTAssertEqual(board.minAliveCards(), 1)
    }

    func testMinAliveCardsIsZeroWithNoAlivePiles() {
        let board = BoardState(size: 2, data: data)
        board.push(0, DeckManager.cardForValue(5)); board.push(1, DeckManager.cardForValue(6))
        board.kill(0); board.kill(1)
        XCTAssertEqual(board.minAliveCards(), 0)
    }

    // MARK: - Min-pile highlight states (the score-dictating pile's gold chip)

    func testMinPileStatesHighlightEveryTiedSmallest() {
        let board = BoardState(size: 4, data: data)
        board.push(0, DeckManager.cardForValue(5))                        // 1
        board.push(1, DeckManager.cardForValue(6))                        // 1 (tie)
        board.push(2, DeckManager.cardForValue(7)); board.push(2, DeckManager.cardForValue(8))
        board.push(3, DeckManager.cardForValue(9)); board.push(3, DeckManager.cardForValue(10))
        board.push(3, DeckManager.cardForValue(11))                       // 3
        XCTAssertEqual(board.minPileStates(), [.min, .min, .none, .none],
                       "every pile at the payout minimum highlights, ties included")
    }

    func testMinPileStatesLinesAnAnchoredTrueLowest() {
        let board = BoardState(size: 3, data: data)
        board.push(0, DeckManager.cardForValue(5))                        // 1, anchored
        board.push(1, DeckManager.cardForValue(6)); board.push(1, DeckManager.cardForValue(7))
        board.push(2, DeckManager.cardForValue(8)); board.push(2, DeckManager.cardForValue(9))
        board.top(0)?.stickers.append(StickerRecord(type: "anchor"))
        XCTAssertEqual(board.minPileStates(), [.minAnchored, .min, .min],
                       "the anchored 1-card pile is the true lowest but can't set the score")
    }

    func testMinPileStatesAllAnchoredFallsBackToSolidMin() {
        let board = BoardState(size: 2, data: data)
        board.push(0, DeckManager.cardForValue(5))
        board.push(1, DeckManager.cardForValue(6)); board.push(1, DeckManager.cardForValue(7))
        board.top(0)?.stickers.append(StickerRecord(type: "anchor"))
        board.top(1)?.stickers.append(StickerRecord(type: "anchor"))
        XCTAssertEqual(board.minPileStates(), [.min, .none],
                       "when every alive pile is anchored the smallest COUNTS — gold, never lined")
    }

    func testMinPileStatesIgnoresDeadPiles() {
        let board = BoardState(size: 3, data: data)
        board.push(0, DeckManager.cardForValue(5))
        board.push(1, DeckManager.cardForValue(6)); board.push(1, DeckManager.cardForValue(7))
        board.push(2, DeckManager.cardForValue(8))
        board.kill(2)
        XCTAssertEqual(board.minPileStates(), [.min, .none, .none],
                       "a dead pile never highlights, even at the minimum")
    }

    func testExtraCoinUnitsCountOnlyAliveTops() {
        let board = BoardState(size: 2, data: data)
        for i in 0..<2 {
            board.push(i, DeckManager.cardForValue(5))
            board.push(i, DeckManager.cardForValue(6))
            board.top(i)?.stickers.append(StickerRecord(type: "extraCoin"))
        }
        XCTAssertEqual(board.extraCoinUnits(), 4, "2 piles × 2 cards each")
        board.kill(1)
        XCTAssertEqual(board.extraCoinUnits(), 2, "a dead pile pays nothing")
    }

    func testExtraCoinStacksPerSticker() {
        let board = BoardState(size: 1, data: data)
        board.push(0, DeckManager.cardForValue(5))
        board.push(0, DeckManager.cardForValue(6))
        board.top(0)?.stickers.append(StickerRecord(type: "extraCoin"))
        board.top(0)?.stickers.append(StickerRecord(type: "extraCoin"))
        XCTAssertEqual(board.extraCoinUnits(), 4, "2 stickers × 2 cards")
    }

    func testHeavyStickersWeightPileSize() {
        guard let heavy = data.items.stickers.first(where: { $0.behavior == "heavy" }) else {
            XCTFail("items.js must ship a heavy sticker"); return
        }
        let board = BoardState(size: 1, data: data)
        board.push(0, DeckManager.cardForValue(5))
        XCTAssertEqual(board.pileSize(0), 1)
        board.top(0)?.stickers.append(StickerRecord(type: heavy.id))
        XCTAssertEqual(board.pileSize(0), 1 + heavy.int("value", 1),
                       "a heavy card counts as 1 + its items.js value")
        XCTAssertEqual(board.piles[0].cards.count, 1, "the physical count is unchanged")
    }

    // MARK: - One continuous score (v6.47)

    func testScoreIsOneContinuousTotalAcrossTheBank() {
        let c = CampaignState()
        c.addRunScore(40)
        XCTAssertEqual(c.getRunScore(), 40)
        c.markRunWon()
        c.addRunScore(25)
        XCTAssertEqual(c.getRunScore(), 65,
                       "endless continues the climb's total — one score, never a reset")
    }

    func testTheBankStillFreezesTheBookkeepingSlice() {
        // The bank survives for phase logic and cards-flipped accounting —
        // scoreBanked must not move once the ♠ boss falls.
        let c = CampaignState()
        c.addRunScore(100)
        c.markRunWon()
        c.addRunScore(10)
        XCTAssertEqual(c.getRunScore(), 110)
        XCTAssertTrue(c.runWonBanked)
    }

    func testAddRunScoreClampsNegatives() {
        let c = CampaignState()
        c.addRunScore(-50)
        XCTAssertEqual(c.getRunScore(), 0)
    }

    func testCoinsSpendAndEarn() {
        let c = CampaignState()
        c.addCoins(10)
        XCTAssertEqual(c.getCoins(), 10)
        XCTAssertFalse(c.spendCoins(11), "an unaffordable spend must fail without moving coins")
        XCTAssertEqual(c.getCoins(), 10)
        XCTAssertTrue(c.spendCoins(4))
        XCTAssertEqual(c.getCoins(), 6)
        c.earnCoins(5)
        XCTAssertEqual(c.getCoins(), 11)
        XCTAssertEqual(c.totalCoinsEarned, 5, "only earnCoins feeds the lifetime tally")
    }

    /// v6.67: no deck carries a price multiplier today (Mr. Garden shops at
    /// Pinky prices), but the mechanism must keep honoring whatever the data
    /// declares — every deck's shelf price is its Pinky price × its own mult.
    func testPriceMultiplierFlowsFromTheDeckRules() {
        let pink = CampaignState(); pink.setDeck("pink")
        for deck in GameMeta.deckOrder {
            let c = CampaignState(); c.setDeck(deck)
            let mult = c.rules().priceMult
            for id in data.pillarTypes.ids.prefix(6) {
                XCTAssertEqual(c.priceOfPillar(id), (pink.priceOfPillar(id) * mult).rounded(),
                               "\(deck) pillar \(id)")
            }
            XCTAssertEqual(c.removalPrice(), (pink.removalPrice() * mult).rounded(),
                           "\(deck): the multiplier covers Removal too")
        }
    }
}
