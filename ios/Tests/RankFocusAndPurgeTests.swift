import XCTest
@testable import GameCore

/// v6.98 BATCH — the purge economy re-base (start 3, step +1, every floor 3,
/// Bulk Rate zeroes the climb) and the Rank Focus bench's LIVE most-held-rank
/// trigger (recompute mid-deal; the ties and Ace/2 edges live in the Tier-1
/// scenarios).
final class RankFocusAndPurgeTests: XCTestCase {
    let data = GameData.shared

    private func campaign() -> CampaignState {
        let c = CampaignState(store: MemoryStore())
        c.setDeck("pink"); c.setSeedOverride(4242); c.reset()
        return c
    }

    // MARK: - Purge economy (items 4–6)

    func testPurgeLadderStartsAtThreeAndClimbsByOne() {
        let c = campaign(); _ = c.addCoins(500)
        XCTAssertEqual(c.removalPrice(), 3, "the ladder opens at 3 (v6.98)")
        XCTAssertTrue(c.buyRemoval(c.getRunDeck()[0].id))
        XCTAssertEqual(c.removalPrice(), 4, "one purchase climbs the ladder by 1")
        XCTAssertTrue(c.buyRemoval(c.getRunDeck()[0].id))
        XCTAssertEqual(c.removalPrice(), 5, "…and again — base 3 + 1 per purchase")
    }

    func testPurgeCouponFloorIsThree() {
        let c = campaign(); _ = c.addCoins(500)
        // Climb a few rungs, then bank an oversized Coupon cut: the price
        // must stop at the Coupon def's `min` — 3 now — never below.
        for _ in 0..<4 { XCTAssertTrue(c.buyRemoval(c.getRunDeck()[0].id)) }
        XCTAssertEqual(c.removalPrice(), 7)
        _ = c.addPurgeDiscount(50)
        let couponMin = data.baseTypes.get("purgeDiscount")?.num("min", 0)
        XCTAssertEqual(couponMin, 3, "the Coupon's data floor moved to 3")
        XCTAssertEqual(c.removalPrice(), 3, "an oversized cut floors at the Coupon min (3)")
    }

    func testFlatPurgeFloorIsThree() {
        // The data knob the on-purchase halve floors at (the campaign check in
        // ItemValidationTests exercises the full buy path against it live).
        XCTAssertEqual(data.pillarTypes.get("purgeFlatFive")?.num("value", 0), 3,
                       "Flat Purge halves to a minimum of 3 (v6.98)")
        XCTAssertTrue(data.pillarTypes.get("purgeFlatFive")?.description.contains("minimum 3") == true,
                      "…and its help text says so")
    }

    func testBulkRateStopsTheLadderEntirely() {
        let c = campaign(); _ = c.addCoins(500)
        guard let bulk = data.items.pillars.first(where: { $0.effect == "purgeStepDiscount" }) else {
            return XCTFail("no Bulk Rate in the registry")
        }
        c.setColumnPillar(col: 0, typeId: bulk.id)
        XCTAssertEqual(c.removalPrice(), 3)
        for i in 1...3 {
            XCTAssertTrue(c.buyRemoval(c.getRunDeck()[0].id))
            XCTAssertEqual(c.removalPrice(), 3,
                           "purchase \(i): step 1 − Bulk Rate's 1 = 0 — the price never climbs")
        }
        // Unequip: the full ladder snaps back (derived pricing, no state).
        c.setColumnPillar(col: 0, typeId: nil)
        XCTAssertEqual(c.removalPrice(), 6, "unequipped: base 3 + 1 × the 3 removals bought")
    }

    // MARK: - The most-held trigger recomputes LIVE (items 11–13)

    func testMostHeldTriggerRecomputesMidDeal() {
        guard let def = data.pillarTypes.get("heartZeroRanksCoin") else {
            return XCTFail("no Empty Ranks Coins in the registry")
        }
        // Two 8s and one 4 beyond the tops: 8 is the most-held. The injected
        // full-deck hook is the live read — swap it mid-deal and the SAME
        // rank landing flips from firing to silent.
        let tops = [IV.spec(1, 5, "♠"), IV.spec(2, 6, "♥"), IV.spec(3, 7, "♣")]
        let e = IV.engine(tops: tops,
                          deckOrder: [IV.spec(50, 8, "♦"), IV.spec(51, 8, "♥"), IV.spec(52, 9, "♠")],
                          pillars: [def.id, nil, nil])
        var hookDeck = (tops + [IV.spec(50, 8, "♦"), IV.spec(51, 8, "♥"), IV.spec(52, 9, "♠")])
            .map { DeckManager.toCard($0, data: GameData.shared) }
        e.fullDeckProvider = { hookDeck }
        let before = e.run.bonusCoins
        e.guess(0, .higher)   // the 8♦ lands — 8 is most-held → pays
        XCTAssertGreaterThan(e.run.bonusCoins, before,
                             "the most-held 8 landing pays while 8 leads")
        // A purge-shaped composition change: the 8s leave the full deck —
        // the hook now says 9 leads. The next 8 landing must stay silent.
        hookDeck = hookDeck.filter { $0.value != 8 } +
            [DeckManager.toCard(IV.spec(60, 9, "♦"), data: GameData.shared)]
        let mid = e.run.bonusCoins
        e.guess(0, .same)     // the second 8 lands (a correct Same on the 8 top)
        XCTAssertTrue(e.board.isActive(0), "setup: the Same landed correctly")
        XCTAssertEqual(e.run.bonusCoins, mid,
                       "the SAME rank landing is silent after the live recompute")
    }

    // MARK: - The live {rank} template (Rank Focus bench)

    func testMostHeldRankTemplateNamesTheLiveLeader() {
        let c = campaign()
        guard let rank = c.mostCommonRank(),
              let label = DeckManager.ranks.first(where: { $0.value == rank })?.label else {
            return XCTFail("a fresh deck has a most common rank")
        }
        for id in ["heartZeroRanksCoin", "mostHeldRankBury", "mostHeldRankTell"] {
            guard let def = c.data.pillarTypes.get(id) else { return XCTFail("\(id) missing") }
            let text = c.itemDescription(def)
            XCTAssertFalse(text.contains("{rank}"), "\(id): the template must be substituted")
            XCTAssertTrue(text.contains("(\(label))"), "\(id): names the live leader \(label)")
        }
    }

    // MARK: - The Pauper purge offer resolves through the action queue

    func testPauperPurgeDeclineByDefaultAndKillOnLastCard() {
        guard let def = data.pillarTypes.get("pauperDiamondEqualize") else {
            return XCTFail("no Pauper's Diamond in the registry")
        }
        // Flat broke ♦ landing queues the offer; purging a ONE-card pile's
        // top kills the pile (documented choice) — and the loss check runs.
        let tops = [IV.spec(1, 5, "♠"), IV.spec(2, 4, "♥"), IV.spec(3, 6, "♣")]
        let e = IV.engine(tops: tops,
                          deckOrder: [IV.spec(50, 7, "♦"), IV.spec(51, 3, "♠")],
                          pillars: [nil, def.id, nil], purse: 0)
        e.guess(1, .higher)
        XCTAssertEqual(e.run.pendingActions.first?.kind, "pauperPurge")
        var purged: (index: Int, cardId: Int)? = nil
        e.on { if case .pauperPurged(let i, let id) = $0 { purged = (i, id) } }
        e.answerAction(true, pickedPile: 2)   // pile 3 holds ONE card
        XCTAssertEqual(purged?.index, 2, "the event reports the picked pile")
        XCTAssertEqual(purged?.cardId, 3, "…and the purged card")
        XCTAssertFalse(e.board.isActive(2), "a one-card pile dies with its card")
        XCTAssertEqual(e.status, "playing", "other piles alive — the deal goes on")
        // A pick-less accept can never mis-fire: it reads as a decline.
        let e2 = IV.engine(tops: tops,
                           deckOrder: [IV.spec(50, 7, "♦"), IV.spec(51, 3, "♠")],
                           pillars: [nil, def.id, nil], purse: 0)
        e2.guess(1, .higher)
        let counts = (0..<3).map { e2.board.piles[$0].cards.count }
        e2.answerAction(true, pickedPile: nil)
        XCTAssertEqual((0..<3).map { e2.board.piles[$0].cards.count }, counts,
                       "accept without a pick purges nothing")
    }
}
