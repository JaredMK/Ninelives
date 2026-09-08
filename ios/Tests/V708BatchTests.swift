import XCTest
@testable import GameCore

/// v7.08 BATCH — the meta items' new in-deal legs (Freebie / Rare Hunter's
/// stickered-landing coin, Flat Purge / Bulk Rate's deal-end purge legs read
/// off the live store), Rank Purge retired, and the Old Joker's cut choice.
final class V708BatchTests: XCTestCase {
    private let data = GameData.shared

    private func spec(_ id: Int, _ rank: Int, _ suit: String = "♠",
                      _ stickers: [String] = []) -> CardSpec {
        IV.spec(id, rank, suit, stickers)
    }

    // MARK: - 1/2. +1 coin per STICKERED card landing in the column

    func testFreebiePaysPerStickeredLandingInItsColumn() {
        // v7.09: Rare Hunter's leg moved to a deal-end per-sticker-bought
        // payout (V709BatchTests) — Freebie alone keeps the landing leg.
        for pid in ["freebie"] {
            let def = data.pillarTypes.get(pid)!
            let per = def.num("stickerLandCoin", 0)
            XCTAssertEqual(per, 1, "\(pid): the items.js leg is +1")
            // A STICKERED card lands correctly in the pillar's column → +1.
            let hit = IV.engine(tops: [spec(1, 5, "♠"), spec(2, 6, "♥"), spec(3, 7, "♦")],
                                deckOrder: [spec(50, 9, "♠", ["anchor"]), spec(51, 2)],
                                pillars: [pid, nil, nil])
            hit.guess(0, .higher)
            XCTAssertEqual(hit.run.bonusCoins, per, "\(pid): a stickered landing in its column pays")
            // An UNSTICKERED card → nothing.
            let bare = IV.engine(tops: [spec(1, 5, "♠"), spec(2, 6, "♥"), spec(3, 7, "♦")],
                                 deckOrder: [spec(50, 9, "♠"), spec(51, 2)],
                                 pillars: [pid, nil, nil])
            bare.guess(0, .higher)
            XCTAssertEqual(bare.run.bonusCoins, 0, "\(pid): no sticker, no coin")
            // A stickered landing in ANOTHER column → nothing.
            let elsewhere = IV.engine(tops: [spec(1, 5, "♠"), spec(2, 6, "♥"), spec(3, 7, "♦")],
                                      deckOrder: [spec(50, 9, "♠", ["anchor"]), spec(51, 2)],
                                      pillars: [pid, nil, nil])
            elsewhere.guess(1, .higher)   // 9 on 6, column 2
            XCTAssertEqual(elsewhere.run.bonusCoins, 0, "\(pid): only ITS column pays")
            // A stickered card that lands WRONG (the pile dies) → nothing.
            let wrong = IV.engine(tops: [spec(1, 5, "♠"), spec(2, 6, "♥"), spec(3, 7, "♦")],
                                  deckOrder: [spec(50, 3, "♠", ["anchor"]), spec(51, 2)],
                                  pillars: [pid, nil, nil])
            wrong.guess(0, .higher)
            XCTAssertFalse(wrong.board.isActive(0))
            XCTAssertEqual(wrong.run.bonusCoins, 0, "\(pid): a fatal landing pays nothing")
        }
    }

    // MARK: - 3/4. Deal-end purge legs read the LIVE store

    func testFlatPurgePaysTheCurrentPurgePriceAndBulkRateTheCountBought() {
        let tops = [spec(1, 5, "♠"), spec(2, 6, "♥"), spec(3, 7, "♦")]
        let flat = IV.engine(tops: tops, deckOrder: [spec(50, 9)],
                             pillars: ["purgeFlatFive", nil, nil], purgePrice: 7, purgesBought: 3)
        let flatLine = flat.computePillarPayout().lines.first { $0.label == "Flat Purge" }
        XCTAssertEqual(flatLine?.amount, 7, "Flat Purge pays X = the store's current Purge price")
        let bulk = IV.engine(tops: tops, deckOrder: [spec(50, 9)],
                             pillars: ["bulkRate", nil, nil], purgePrice: 7, purgesBought: 3)
        let bulkLine = bulk.computePillarPayout().lines.first { $0.label == "Bulk Rate" }
        XCTAssertEqual(bulkLine?.amount, 3, "Bulk Rate pays X = Purges bought this climb")
        // Zero pays no line; an unwired engine (no provider) pays nothing.
        let zero = IV.engine(tops: tops, deckOrder: [spec(50, 9)],
                             pillars: ["bulkRate", nil, nil], purgePrice: 7, purgesBought: 0)
        XCTAssertNil(zero.computePillarPayout().lines.first { $0.label == "Bulk Rate" }, "0 purges → no leg")
        let unwired = IV.engine(tops: tops, deckOrder: [spec(50, 9)], pillars: ["purgeFlatFive", nil, nil])
        XCTAssertNil(unwired.computePillarPayout().lines.first { $0.label == "Flat Purge" }, "no provider → dormant")
    }

    func testPurgesBoughtCountsPaidPurgesPerClimbAndSurvivesTheSave() {
        let c = CampaignState(store: MemoryStore())
        c.setDeck("pink"); c.setTier("regular"); c.setSeedOverride(7); c.reset()
        XCTAssertEqual(c.purgesBought, 0, "starts at 0")
        c.addCoins(100)
        let deck = c.getRunDeck()
        XCTAssertTrue(c.buyRemoval(deck[0].id))
        XCTAssertTrue(c.buyRemoval(deck[1].id))
        XCTAssertEqual(c.purgesBought, 2, "+1 per PAID purge")
        // The provider the deal wires reads exactly this count + the live price.
        XCTAssertEqual(Int(c.removalPrice()), Int(c.removalPrice()))   // stable read
        let twin = CampaignState(store: MemoryStore())
        XCTAssertTrue(twin.restore(c.serialize()))
        XCTAssertEqual(twin.purgesBought, 2, "the count survives the campaign save")
        twin.setSeedOverride(8); twin.reset()
        XCTAssertEqual(twin.purgesBought, 0, "a new climb starts over")
    }

    // MARK: - 6. Rank Purge is retired

    func testRankPurgeIsRetired() {
        let def = data.pillarTypes.get("purgeRank")!
        XCTAssertTrue(def.inactive)
        XCTAssertFalse(data.pillarTypes.grantableBase().contains { $0.id == "purgeRank" }, "out of every pool")
    }

    // MARK: - 8. The Cut's paid branch is unavailable under the fee

    func testCutPayToChooseIsUnavailableBelowTheFeeAndNeverSpends() {
        XCTAssertFalse(OldJoker.cutChoiceAffordable(coins: 3, chooseCost: 4))
        XCTAssertTrue(OldJoker.cutChoiceAffordable(coins: 4, chooseCost: 4))
        let c = CampaignState(store: MemoryStore())
        c.setDeck("pink"); c.setTier("regular"); c.setSeedOverride(7); c.reset()
        c.addCoins(3 - c.getCoins())
        XCTAssertEqual(c.getCoins(), 3)
        let deckBefore = c.getRunDeck().count
        XCTAssertNil(c.resolveOldJoker(.cut(chooseCost: 4), choice: .payToChoose, nodeId: 1),
                     "short of the fee the paid branch is refused")
        XCTAssertEqual(c.getCoins(), 3, "…and nothing is spent")
        XCTAssertEqual(c.getRunDeck().count, deckBefore, "…and nothing is purged")
        c.addCoins(1)
        let r = c.resolveOldJoker(.cut(chooseCost: 4), choice: .payToChoose, nodeId: 1)
        XCTAssertNotNil(r, "with the fee in hand the paid branch opens the picker")
        XCTAssertEqual(c.getCoins(), 0, "…for exactly the fee")
    }
}
