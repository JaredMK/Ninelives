import XCTest
@testable import GameCore

/// v7.05 — On the House's new deal-end coin leg, and the frozen toolbar
/// high score (the display holds at the pre-climb best while the live stat
/// folds this run's score in per cleared deal).
final class V705BatchTests: XCTestCase {
    let data = GameData.shared

    // MARK: - On the House pays +value at deal end

    func testOnTheHousePaysItsFlatBonusAtDealEnd() {
        guard let def = data.pillarTypes.get("firstFree") else { return XCTFail("no On the House") }
        let v = def.num("value", 2)
        XCTAssertEqual(v, 2, "the coin leg is +2 (items.js)")
        // Equipped on column 0; the payout pays regardless of survival.
        let e = IV.engine(tops: [IV.spec(1, 5, "♠"), IV.spec(2, 6, "♥"), IV.spec(3, 7, "♣")],
                          deckOrder: [IV.spec(50, 9)],
                          pillars: ["firstFree", nil, nil])
        let line = e.computePillarPayout().lines.first { $0.label == def.label }
        XCTAssertEqual(line?.amount, v, "On the House pays +\(Int(v)) at the deal-end payout")
        // Not equipped → no line.
        let bare = IV.engine(tops: [IV.spec(1, 5, "♠"), IV.spec(2, 6, "♥"), IV.spec(3, 7, "♣")],
                             deckOrder: [IV.spec(50, 9)], pillars: [nil, nil, nil])
        XCTAssertNil(bare.computePillarPayout().lines.first { $0.label == def.label },
                     "no pillar, no bonus")
    }

    // MARK: - The toolbar high score freezes for the climb

    func testHudBestScoreFreezesAtClimbStart() {
        let c = CampaignState(store: MemoryStore())
        c.setDeck("pink"); c.setTier("regular")
        // Seed a prior record for this deck+tier.
        var s = c.stats.get()
        s.deckTierBest["pink.regular"] = 120
        c.stats.put(s)
        // A fresh climb freezes the DISPLAY best at that 120.
        c.setSeedOverride(4242); c.reset()
        XCTAssertEqual(c.hudBestScore, 120, "the toolbar HI freezes at the pre-climb best")
        // The live stat folding this run's score higher does NOT move the frozen display.
        var s2 = c.stats.get()
        s2.deckTierBest["pink.regular"] = 200   // the per-deal live fold
        c.stats.put(s2)
        XCTAssertEqual(c.hudBestScore, 120, "the display holds while the run is live")
        // Only the NEXT climb re-reads it.
        c.setSeedOverride(777); c.reset()
        XCTAssertEqual(c.hudBestScore, 200, "the next climb picks up the new record")
    }

    func testHudBestScoreSurvivesAMidClimbResume() {
        let c = CampaignState(store: MemoryStore())
        c.setDeck("pink"); c.setTier("regular")
        var s = c.stats.get(); s.deckTierBest["pink.regular"] = 88; c.stats.put(s)
        c.setSeedOverride(4242); c.reset()
        XCTAssertEqual(c.hudBestScore, 88)
        let twin = CampaignState(store: MemoryStore())
        XCTAssertTrue(twin.restore(c.serialize()))
        XCTAssertEqual(twin.hudBestScore, 88, "a resumed climb keeps the frozen HI")
    }
}
