import XCTest
@testable import GameCore

/// v6.99 BATCH — the carrier-lands Malfunction (bug 2), Crowd Favorite's
/// surviving-landing pay (bug 3), the whole-column Shuffler (item 10), and
/// the Old Joker's full-variety debt repayment (item 17).
final class V699BatchTests: XCTestCase {
    let data = GameData.shared

    // MARK: - Bug 2: Malfunction fires when the CARRIER lands

    func testMalfunctionRollsForTheCarrierNotTheLandedUpon() {
        // A cursed TOP no longer rolls anything: land a clean card on it over
        // many seeds — the pile must survive every time.
        for seed: UInt32 in 1...120 {
            let e = IV.engine(tops: [IV.spec(1, 5, "♠", ["malfunction"]), IV.spec(2, 6), IV.spec(3, 6)],
                              deckOrder: [IV.spec(50, 9, "♥"), IV.spec(51, 3)], seed: seed)
            e.guess(0, .higher)
            XCTAssertTrue(e.board.isActive(0),
                          "seed \(seed): a clean card on a cursed top never malfunctions (v6.99)")
        }
        // …and the cursed CARRIER landing correctly is what rolls now.
        var blew = false
        for seed: UInt32 in 1...200 where !blew {
            let e = IV.engine(tops: [IV.spec(1, 5, "♠"), IV.spec(2, 6), IV.spec(3, 6)],
                              deckOrder: [IV.spec(50, 9, "♥", ["malfunction"]), IV.spec(51, 3)], seed: seed)
            var named: String?
            e.on { if case .malfunction(_, let label) = $0 { named = label } }
            e.guess(0, .higher)
            if !e.board.isActive(0) {
                blew = true
                XCTAssertEqual(named, "9♥", "the banner names the CARRIER that blew")
                XCTAssertEqual(e.run.correctGuesses, 1, "the guess itself stays correct")
            }
        }
        XCTAssertTrue(blew, "no seed in 1...200 rolled the 10% — statistically broken")
    }

    // MARK: - Bug 3: Crowd Favorite pays on a SURVIVING landing

    private func crowdEngine(deckOrder: [CardSpec], sameCharge: Bool = false,
                             pillar: String = "crowdFavorite") -> GameEngine {
        IV.engine(tops: [IV.spec(1, 5, "♠"), IV.spec(2, 6, "♥"), IV.spec(3, 6, "♣")],
                  deckOrder: deckOrder,
                  pillars: [pillar, nil, nil], sameCharge: sameCharge,
                  pillarRankVariants: ["crowdFavorite": 9])
    }

    func testCrowdFavoritePaysOnTheSameChargeSavedLanding() {
        guard let def = data.pillarTypes.get("crowdFavorite") else { return XCTFail() }
        let v = def.num("value", 2)
        // The locked rank (9) lands WRONG (called lower on a 5) — the banked
        // Same Charge saves the pile, the 9 becomes its top: a real landing,
        // so the pillar pays (v6.99).
        let e = crowdEngine(deckOrder: [IV.spec(50, 9, "♦"), IV.spec(51, 3)], sameCharge: true)
        e.guess(0, .lower)
        XCTAssertTrue(e.board.isActive(0), "setup: the backstop saved the pile")
        XCTAssertEqual(e.board.top(0)?.id, 50, "setup: the 9 landed")
        XCTAssertEqual(e.run.bonusCoins, v, "the saved landing pays the locked-rank bounty")
    }

    func testCrowdFavoriteStillPaysOnPlainCorrectAndNotOnDeath() {
        guard let def = data.pillarTypes.get("crowdFavorite") else { return XCTFail() }
        let v = def.num("value", 2)
        let e = crowdEngine(deckOrder: [IV.spec(50, 9, "♦"), IV.spec(51, 3)])
        e.guess(0, .higher)    // plain correct
        XCTAssertEqual(e.run.bonusCoins, v)
        // A FATAL landing of the rank pays nothing — the card never survives.
        let dead = crowdEngine(deckOrder: [IV.spec(50, 9, "♦"), IV.spec(51, 3)])
        dead.guess(0, .lower)  // wrong, no save available
        XCTAssertFalse(dead.board.isActive(0))
        XCTAssertEqual(dead.run.bonusCoins, 0, "a killed landing is not a landing that pays")
    }

    // MARK: - Item 10: the Shuffler shuffles its own trigger pile too

    func testShufflerAcceptShufflesTheWholeColumnIncludingTheTrigger() {
        // Column 0 holds two piles; the ♦ lands on pile 0 and the offer
        // queues. Accept — BOTH piles shuffle (the trigger included): pile
        // 0's two known cards can swap, which the old exclusion made
        // impossible over any number of seeds.
        var sawTriggerTopChange = false
        for seed: UInt32 in 1...60 where !sawTriggerTopChange {
            let e = IV.engine(tops: [IV.spec(1, 5, "♠"), IV.spec(2, 6, "♥"), IV.spec(3, 6, "♣")],
                              deckOrder: [IV.spec(50, 9, "♦"), IV.spec(51, 3)],
                              cols: [2, 1], pillars: ["royalCourt", nil], seed: seed)
            e.guess(0, .higher)
            XCTAssertEqual(e.run.pendingActions.first?.kind, "pillarShuffle",
                           "seed \(seed): the ♦ landing queues the offer")
            e.answerAction(true)
            if e.board.top(0)?.id != 50 { sawTriggerTopChange = true }
        }
        XCTAssertTrue(sawTriggerTopChange,
                      "over 60 seeds the TRIGGER pile's own order never changed — it isn't being shuffled")
    }

    func testShufflerDeclineLeavesEveryPileAlone() {
        let e = IV.engine(tops: [IV.spec(1, 5, "♠"), IV.spec(2, 6, "♥"), IV.spec(3, 6, "♣")],
                          deckOrder: [IV.spec(50, 9, "♦"), IV.spec(51, 3)],
                          cols: [2, 1], pillars: ["royalCourt", nil])
        e.guess(0, .higher)
        e.answerAction(false)
        XCTAssertEqual(e.board.top(0)?.id, 50, "declined — the landing stays put")
        XCTAssertEqual(e.board.top(1)?.id, 2, "…and so does its neighbour")
    }

    // MARK: - Item 17: the coat pays in the full variety

    func testThirstGiftsDrawFromEveryClass() {
        let c = CampaignState(store: MemoryStore())
        c.setDeck("pink"); c.setSeedOverride(4242); c.reset()
        // Across many nodes at a modest budget (floor 1 — nothing excluded),
        // the coat must produce at least one of EACH kind — pillars, bases,
        // stickers, Same-Powers, packs and the plain card.
        var seen = Set<String>()
        for node in 1...400 {
            for g in c.rollThirstGifts(budget: 6, nodeId: node) { seen.insert(g.kind.rawValue) }
            if seen.count >= 6 { break }
        }
        XCTAssertEqual(seen, ["pillar", "base", "sticker", "samepower", "pack", "card"],
                       "the debt draws from the FULL variety (v6.99) — got \(seen.sorted())")
    }

    // v7.06: a MULTI-ROW debt reads as VARIETY, not a stack of pillars. Before
    // this, flat rarity (v6.98) + the tier floor collapsed big debts to the
    // deck's one or two rare pillars — a wide shelf was ~80% pillars and a
    // budget-12+ shelf was 100% pillars. The coat now spreads across classes.
    func testThirstShelfSpreadsAcrossClassesNotJustPillars() {
        let c = CampaignState(store: MemoryStore())
        c.setDeck("pink"); c.setSeedOverride(4242); c.reset()
        // A generous debt: every shelf should show a MIX, and not one shelf in
        // the sample may come back pillars-only.
        var pillarOnly = 0, multiRow = 0
        for node in 1...200 {
            let gifts = c.rollThirstGifts(budget: 12, nodeId: node)
            guard gifts.count >= 2 else { continue }
            multiRow += 1
            if Set(gifts.map { $0.kind }) == [.pillar] { pillarOnly += 1 }
        }
        XCTAssertGreaterThan(multiRow, 100, "budget 12 should build wide shelves")
        XCTAssertEqual(pillarOnly, 0,
                       "no multi-row debt is pillars-only any more (was 100% at budget 12+)")
    }

    func testGiftShelfMintsTheCardAndOffersItFree() {
        let c = CampaignState(store: MemoryStore())
        c.setDeck("pink"); c.setSeedOverride(7); c.reset()
        c.openGiftShelf([OldJoker.Holding(kind: .card, id: "card"),
                         OldJoker.Holding(kind: .samepower, id: "linkCoins")])
        guard let offer = c.getStoreOffer() else { return XCTFail("no offer") }
        let cardSlot = offer.slots.compactMap { $0 }.first { $0.kind == "card" }
        XCTAssertNotNil(cardSlot?.card, "the card gift minted a real playing card at shelf time")
        let spSlot = offer.slots.compactMap { $0 }.first { $0.kind == "samepower" }
        XCTAssertEqual(spSlot?.id, "linkCoins", "a CONCRETE Same-Power gift, never the mystery slot")
        XCTAssertEqual(spSlot?.mystery, false)
        XCTAssertTrue(c.isGiftShelf)
    }

    func testThirstGiftsNeverIncludeTheEquippedSamePower() {
        let c = CampaignState(store: MemoryStore())
        c.setDeck("pink"); c.setSeedOverride(99); c.reset()
        c.samePowerInventory["linkCoins", default: 0] += 1
        XCTAssertTrue(c.equipSamePower("linkCoins"))
        for node in 1...200 {
            for g in c.rollThirstGifts(budget: 20, nodeId: node) where g.kind == .samepower {
                XCTAssertNotEqual(g.id, "linkCoins", "node \(node): the equipped power stays out of the coat")
            }
        }
    }
}
