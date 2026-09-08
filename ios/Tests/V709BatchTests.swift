import XCTest
@testable import GameCore

/// v7.09 BATCH — live value previews (the Snowballs, Flat Purge / Bulk Rate /
/// Rare Hunter), Dense Bury on any 2+-sticker card, the Bonus Reset rework
/// (bury per 3 bonus coins, spread across the column, then peek, then
/// reset), Rare Hunter's per-climb sticker count, and the event feed's
/// outcome wording.
final class V709BatchTests: XCTestCase {
    private let data = GameData.shared

    private func spec(_ id: Int, _ rank: Int, _ suit: String = "♠",
                      _ stickers: [String] = []) -> CardSpec {
        IV.spec(id, rank, suit, stickers)
    }
    private func campaign() -> CampaignState {
        let c = CampaignState(store: MemoryStore())
        c.setDeck("pink"); c.setTier("regular"); c.setSeedOverride(7); c.reset()
        return c
    }

    // MARK: - 1/2. The Snowballs preview their CURRENT next-landing value

    func testSnowballPreviewsShowTheCurrentX() {
        let coins = data.stickerTypes.get("snowballCoins")!
        let bury = data.stickerTypes.get("snowball")!
        XCTAssertEqual(CampaignState.stickerLandingPreview(coins, snowball: 3), "(earn 3 coins on next landing)")
        XCTAssertEqual(CampaignState.stickerLandingPreview(coins, snowball: 1), "(earn 1 coin on next landing)")
        XCTAssertEqual(CampaignState.stickerLandingPreview(bury, snowball: 3), "(bury 3 on next landing)")
        XCTAssertEqual(CampaignState.stickerLandingPreview(bury, snowball: 0), "(bury 0 on next landing)")
        XCTAssertNil(CampaignState.stickerLandingPreview(data.stickerTypes.get("anchor")!, snowball: 3),
                     "only the Snowballs carry a live value")
    }

    // MARK: - 3/4. Flat Purge / Bulk Rate (and Rare Hunter) preview their deal-end coins

    func testPayoutPreviewsResolveTheLiveStoreNumbers() {
        let c = campaign()
        let flat = data.pillarTypes.get("purgeFlatFive")!
        let bulk = data.pillarTypes.get("bulkRate")!
        let hunter = data.pillarTypes.get("rareHunter")!
        XCTAssertEqual(c.pillarPayoutPreview(flat), "(+\(Int(c.removalPrice())) coins at deal end)",
                       "Flat Purge resolves X from the store's CURRENT Purge price")
        XCTAssertEqual(c.pillarPayoutPreview(bulk), "(+0 coins at deal end)", "no purges yet")
        c.addCoins(100)
        let deck = c.getRunDeck()
        XCTAssertTrue(c.buyRemoval(deck[0].id)); XCTAssertTrue(c.buyRemoval(deck[1].id))
        XCTAssertEqual(c.pillarPayoutPreview(bulk), "(+2 coins at deal end)", "Bulk Rate resolves X from purges bought")
        XCTAssertEqual(c.pillarPayoutPreview(flat), "(+\(Int(c.removalPrice())) coins at deal end)",
                       "…and Flat Purge tracks the price as the ladder climbs")
        c.recordBuy("tell")
        XCTAssertEqual(c.pillarPayoutPreview(hunter), "(+1 coin at deal end)", "singular at 1")
        XCTAssertNil(c.pillarPayoutPreview(data.pillarTypes.get("envy")!), "no live value → no preview")
    }

    // MARK: - 5. Dense Bury: ANY card with 2+ stickers

    func testDenseBuryTriggersOnAnySuitWithTwoOrMoreStickers() {
        XCTAssertNil(data.pillarTypes.get("denseBury")?.raw["iconSuit"], "no suit target any more — no badge")
        func land(_ suit: String, _ stickers: [String]) -> Int {
            let e = IV.engine(tops: [spec(1, 5, "♠"), spec(2, 6, "♥"), spec(3, 7, "♦")],
                              deckOrder: [spec(50, 9, suit, stickers), spec(51, 2), spec(52, 3)],
                              pillars: ["denseBury", nil, nil])
            e.guess(0, .higher)
            return e.board.piles[0].cards.count   // 2 = landing only, 3 = landing + 1 buried
        }
        XCTAssertEqual(land("♥", ["anchor", "extraCoin"]), 3, "a ♥ with 2 stickers buries")
        XCTAssertEqual(land("♠", ["anchor", "extraCoin"]), 3, "any suit")
        XCTAssertEqual(land("♣", ["anchor", "extraCoin"]), 3, "♣ still works")
        XCTAssertEqual(land("♥", ["anchor"]), 2, "one sticker is not enough")
        XCTAssertEqual(land("♣", []), 2, "no stickers, no bury — even on a ♣")
    }

    // MARK: - 6. Bonus Reset: bury floor(bonus/3) across the column, peek, reset

    func testBonusResetBuriesPerThreeAcrossTheColumnThenPeeksAndResets() {
        // cols [2, 1]: piles 0+1 are column 1 (the base's), pile 2 is column 2.
        let e = IV.engine(tops: [spec(1, 5, "♠"), spec(2, 6, "♥"), spec(3, 7, "♦")],
                          deckOrder: [spec(50, 9), spec(51, 3), spec(52, 4), spec(53, 8)],
                          cols: [2, 1], bases: ["bonusResetPeek", nil])
        e.addBonus("test", 7)
        XCTAssertTrue(e.baseAvailable(0), "7 banked → fireable")
        let sizes = (0..<3).map { e.board.piles[$0].cards.count }
        guard let res = e.baseActivate(col: 0) else { return XCTFail("Bonus Reset did not fire") }
        XCTAssertEqual(res.buried, 2, "floor(7 / 3) = 2 cards buried")
        XCTAssertEqual(e.board.piles[0].cards.count, sizes[0] + 1, "spread round-robin: one under pile 1…")
        XCTAssertEqual(e.board.piles[1].cards.count, sizes[1] + 1, "…one under pile 2")
        XCTAssertEqual(e.board.piles[2].cards.count, sizes[2], "the other column is untouched")
        XCTAssertEqual(res.peekCount, 1)
        XCTAssertTrue(e.run.revealNextActive, "then the peek")
        XCTAssertEqual(e.run.bonusCoins, 0, "then the bonus resets to 0")
    }

    func testBonusResetGateIsUnchangedAtMoreThanOneCoin() {
        let e = IV.engine(tops: [spec(1, 5, "♠"), spec(2, 6, "♥"), spec(3, 7, "♦")],
                          deckOrder: [spec(50, 9), spec(51, 3)],
                          bases: ["bonusResetPeek", nil, nil])
        XCTAssertFalse(e.baseAvailable(0), "0 banked → amber")
        e.addBonus("test", 1)
        XCTAssertFalse(e.baseAvailable(0), "1 banked → still amber (needs more than 1)")
        e.addBonus("test", 1)
        XCTAssertTrue(e.baseAvailable(0), "2 banked → fireable (buries 0 at /3, still peeks + resets)")
        XCTAssertEqual(e.baseLiveCounter(0), 0, "the badge shows the cards it would bury: 2/3 → 0")
        e.addBonus("test", 4)
        XCTAssertEqual(e.baseLiveCounter(0), 2, "6/3 → 2")
    }

    // MARK: - 7. Rare Hunter: +1 per sticker bought this climb, at deal end

    func testRareHunterCountsStickersBoughtPerClimbAndPaysAtDealEnd() {
        let c = campaign()
        XCTAssertEqual(c.stickersBought, 0)
        c.recordBuy("tell"); c.recordBuy("anchor")
        c.recordBuy("prime")          // a pillar — not a sticker
        c.recordBuy("cardPack")       // a pack id (or unknown) — not a sticker
        XCTAssertEqual(c.stickersBought, 2, "standalone sticker purchases only")
        let twin = CampaignState(store: MemoryStore())
        XCTAssertTrue(twin.restore(c.serialize()))
        XCTAssertEqual(twin.stickersBought, 2, "survives the save")
        twin.setSeedOverride(8); twin.reset()
        XCTAssertEqual(twin.stickersBought, 0, "a new climb starts at 0")
        // The deal-end leg reads the live count through the store provider.
        let tops = [spec(1, 5, "♠"), spec(2, 6, "♥"), spec(3, 7, "♦")]
        let e = IV.engine(tops: tops, deckOrder: [spec(50, 9)], pillars: ["rareHunter", nil, nil], stickersBought: 3)
        XCTAssertEqual(e.computePillarPayout().lines.first { $0.label == "Rare Hunter" }?.amount, 3)
        let zero = IV.engine(tops: tops, deckOrder: [spec(50, 9)], pillars: ["rareHunter", nil, nil], stickersBought: 0)
        XCTAssertNil(zero.computePillarPayout().lines.first { $0.label == "Rare Hunter" }, "0 bought → no leg")
        // …and the old in-deal stickered-landing leg is GONE.
        let land = IV.engine(tops: tops, deckOrder: [spec(50, 9, "♠", ["anchor"]), spec(51, 2)],
                             pillars: ["rareHunter", nil, nil])
        land.guess(0, .higher)
        XCTAssertEqual(land.run.bonusCoins, 0, "no per-landing coin any more")
        XCTAssertNil(data.pillarTypes.get("rareHunter")?.raw["stickerLandCoin"])
        XCTAssertEqual(data.pillarTypes.get("freebie")?.num("stickerLandCoin", 0), 1, "Freebie keeps its landing leg")
    }

    // MARK: - 8. The feed states outcomes — end to end for the start-run pillars

    func testScarceSuitAndRankShieldReportTheirOutcomeNotTheirFire() {
        // Scarce Suit: ♥ and ♣ tie for fewest → "will save ♥♣ this deal".
        var captured: [(id: String, label: String, values: [String: Double])] = []
        let e = GameEngine(deckSpecs: [spec(1, 9, "♠"), spec(2, 6, "♠"), spec(3, 7, "♥"),
                                       spec(50, 2, "♣"), spec(51, 9, "♦"), spec(52, 9, "♦")],
                           pileCount: 3, runConfig: RunConfig(cols: [1, 1, 1]))
        e.telemetry = { _, id, label, values in captured.append((id, label, values)) }
        e.start(seedOverride: 7)
        e.startRun(pillars: ["suitShield", nil, nil], bases: [nil, nil, nil], samePower: nil)
        guard let scarce = captured.first(where: { $0.id == "suitShield" }) else { return XCTFail("no Scarce Suit recT") }
        let line = EventFeed.message(klass: "pillar", id: scarce.id, label: scarce.label, values: scarce.values)
        XCTAssertNotNil(line)
        XCTAssertTrue(line!.hasPrefix("Scarce Suit will save "), "states the outcome — got \(line!)")
        XCTAssertTrue(line!.hasSuffix(" this deal"))
        XCTAssertFalse(line!.contains("fired"))
        for s in ["♥", "♣"] { XCTAssertTrue(line!.contains(s), "names \(s)") }
        // Rank Shield: 9s lead → "will save 9 this deal".
        var caught: [(id: String, label: String, values: [String: Double])] = []
        let r = GameEngine(deckSpecs: [spec(1, 9, "♠"), spec(2, 9, "♥"), spec(3, 7, "♦"),
                                       spec(50, 9, "♣"), spec(51, 2, "♦")],
                           pileCount: 3, runConfig: RunConfig(cols: [1, 1, 1]))
        r.telemetry = { _, id, label, values in caught.append((id, label, values)) }
        r.start(seedOverride: 7)
        r.startRun(pillars: ["rankShield", nil, nil], bases: [nil, nil, nil], samePower: nil)
        guard let shield = caught.first(where: { $0.id == "rankShield" }) else { return XCTFail("no Rank Shield recT") }
        XCTAssertEqual(EventFeed.message(klass: "pillar", id: shield.id, label: shield.label, values: shield.values),
                       "Rank Shield will save 9 this deal")
    }

    func testNoEngineRecTFallsThroughToTheBareFireLine() {
        // Every bare-fire site got an outcome key; the fallback is reserved for
        // genuinely bookkeeping-only fires.
        let fires: [[String: Double]] = [
            ["fires": 1, "suits": Double(EventFeed.suitMask("♠"))], ["fires": 1, "rank": 5],
            ["fires": 1, "opensAt": 8], ["fires": 1, "drainedShield": 1], ["fires": 1, "drainedBase": 1],
            ["fires": 1, "blocked": 1], ["fires": 1, "size": 3],
        ]
        for v in fires {
            let line = EventFeed.message(klass: "pillar", id: "x", label: "X", values: v) ?? ""
            XCTAssertFalse(line.hasSuffix(" fired"), "\(v): must state the outcome — got \(line)")
        }
    }
}
