import XCTest
@testable import GameCore

/// PRICE-MODIFIER SCOPE (v6.52) — every modifier in the game, pinned to its
/// intended lifetime. The v6.51 bug class: a visit's state (the shelf and the
/// cast's price twist) was only ever ended by the NEXT `openStore`, and the
/// store screen skips `openStore` whenever an offer exists — so any
/// fresh=false open for a DIFFERENT node (the mystery-detour store, by web
/// parity) inherited the previous shop's leftover shelf AND its price twist.
/// The fix stamps the offer with its owner node (`offerNode`); a mismatch
/// (`storeOfferIsStale(for:)`) rerolls, which re-scopes everything per visit.
final class PriceModifierScopeTests: XCTestCase {

    private func campaign() -> CampaignState {
        let c = CampaignState()
        c.setDeck("pink")
        c.setTier("regular")
        c.setSeedOverride(4242)
        c.startNewRun()
        _ = c.addCoins(100)
        return c
    }

    private func basePrice(_ id: String, _ c: CampaignState) -> Double {
        c.shopPrice(GameData.shared.stickerTypes.get(id)!.price)
    }

    // MARK: - Run teardown (v6.91): pending twists die with the climb

    /// The reported leak: the Queen's priceOne survived a run's END (the UI
    /// reuses the same CampaignState and calls reset()) and discounted the
    /// NEXT climb's first store. Both teardown entry points pinned, all
    /// three leaking twist families.
    func testNextStoreTwistsDieWithTheRun() {
        for (name, teardown) in [("reset", { (c: CampaignState) in c.reset() }),
                                 ("startNewRun", { (c: CampaignState) in c.startNewRun() })] {
            let c = campaign()
            c.applyMysteryEvent("priceOne", nodeId: 3)
            c.applyMysteryEvent("freeRefresh", nodeId: 4)
            c.applyMysteryEvent("freeRedeal", nodeId: 5)
            teardown(c)
            XCTAssertNil(c.storePriceModPending, "\(name): no armed price twist survives")
            let offer = c.openStore()
            XCTAssertNil(c.storePriceModActive, "\(name): the new climb's store has no twist")
            XCTAssertGreaterThan(offer.rerollCost, 0, "\(name): no comped restock leaks")
            XCTAssertFalse(c.consumeFreeRedeal(), "\(name): no free reshuffle leaks")
        }
        // …while a mid-climb SAVE still round-trips an armed twist (the
        // MysteryCastOutcomeTests contract, restated here as the boundary).
        let c = campaign()
        c.applyMysteryEvent("priceOne", nodeId: 3)
        let c2 = CampaignState(store: MemoryStore())
        XCTAssertTrue(c2.restore(c.serialize()))
        XCTAssertEqual(c2.storePriceModPending, "one", "a save is not a run end")
    }

    // MARK: - The cast's price twist (per-visit)

    func testPriceDoubleAppliesToExactlyOneVisit() {
        let c = campaign()
        c.storePriceModPending = "double"
        _ = c.openStore(node: 10)
        XCTAssertEqual(c.storePriceModActive, "double", "the twist arms on the visit it was promised for")
        XCTAssertEqual(c.priceOf("gainCoin"), basePrice("gainCoin", c) * 2, "shop A doubles")
        XCTAssertEqual(c.getStoreOffer()?.offerNode, 10, "the offer knows its owner node")

        // The player leaves shop A (nothing runs), then a DIFFERENT shop opens.
        // The store screen sees the stale stamp and rerolls:
        XCTAssertTrue(c.storeOfferIsStale(for: 99), "shop A's leftover shelf is stale for node 99")
        _ = c.openStore(node: 99)
        XCTAssertNil(c.storePriceModActive, "the twist ended with its visit")
        XCTAssertEqual(c.priceOf("gainCoin"), basePrice("gainCoin", c), "shop B is normal — the v6.51 regression")
    }

    func testPriceOneAppliesToExactlyOneVisit() {
        let c = campaign()
        c.storePriceModPending = "one"
        _ = c.openStore(node: 10)
        XCTAssertEqual(c.priceOf("quickBury"), 1, "Fire Sale flattens to 1")
        _ = c.openStore(node: 11)
        XCTAssertEqual(c.priceOf("quickBury"), basePrice("quickBury", c), "the next shop pays full price")
    }

    func testRefreshEndsTheTwistMidVisit() {
        let c = campaign()
        c.storePriceModPending = "double"
        _ = c.openStore(node: 10)
        XCTAssertEqual(c.storePriceModActive, "double")
        _ = c.rerollStore()
        XCTAssertNil(c.storePriceModActive, "the twist dies on the first REFRESH (its documented end)")
    }

    func testSameNodeReentryKeepsTheVisitAndItsTwist() {
        let c = campaign()
        c.storePriceModPending = "double"
        _ = c.openStore(node: 10)
        // Stepping out to the map and back to the SAME node must not reroll —
        // no free shelf, and no dodging the markup by using the door.
        XCTAssertFalse(c.storeOfferIsStale(for: 10), "same node = same visit")
        XCTAssertEqual(c.storePriceModActive, "double", "the markup survives a re-entry")
    }

    func testGiftShelfAndLegacyOffersAreNeverStale() {
        let c = campaign()
        c.openGiftShelf([])   // gift shelves carry no owner stamp
        XCTAssertFalse(c.storeOfferIsStale(for: 123), "an unstamped offer keeps legacy lingering behaviour")
    }

    // MARK: - Bulk Rate (run-long while equipped) — the reported sequence

    func testBulkRateFlattensThePurgeLadderStep() {
        let c = campaign()
        let cfg = GameData.shared.items.store.removal
        c.debugGrantPillar("bulkRate")
        XCTAssertTrue(c.placePillar("bulkRate", col: 0), "Bulk Rate equips to a column")
        // The reported sequence: equip, buy one purge, look at the next store.
        c.removalsBought = 1
        let discounted = c.removalPrice()
        XCTAssertEqual(discounted, max(1, c.shopPrice(cfg.price + (cfg.priceStep - 1) * 1).rounded()),
                       "the ladder climbs step−1 per purge while Bulk Rate is up")
        // Unequip → the full climb returns instantly (derived live).
        _ = c.unplacePillar(col: 0)
        XCTAssertEqual(c.removalPrice(), max(1, c.shopPrice(cfg.price + cfg.priceStep * 1).rounded()),
                       "without Bulk Rate the full step returns")
    }

    /// The Old Joker's purge-halving STEEPENS the ladder (+1 step for the
    /// climb) — with Bulk Rate equipped the two cancel and the ladder climbs
    /// at the base step again. Pinned so "my discount did nothing" reads as
    /// this interaction, not a broken pillar.
    func testJokerHalvingAndBulkRateCancelOut() {
        let c = campaign()
        let cfg = GameData.shared.items.store.removal
        c.debugGrantPillar("bulkRate")
        _ = c.placePillar("bulkRate", col: 0)
        c.removalsBought = 1
        _ = c.applyPurgeHalving(stepIncrease: 1)   // his bargain steepens…
        c.removalsBought = 2
        let step = cfg.priceStep + 1 - 1           // …and Bulk Rate flattens: net base step
        let expected = max(1, (c.shopPrice(cfg.price + step * 2) - Double(c.purgeDiscount)).rounded())
        XCTAssertEqual(c.removalPrice(), expected,
                       "steepen(+1) and Bulk Rate(−1) cancel — the ladder climbs at the base step")
    }

    // MARK: - Run-long modifiers stay run-long

    func testFreeShopCompIsPerVisit() {
        let c = campaign()
        c.freeShopPending = true
        _ = c.openStore(node: 10)
        XCTAssertEqual(c.priceOf("gainCoin"), 0, "his comp zeroes the shelf")
        _ = c.rerollStore()
        XCTAssertGreaterThan(c.priceOf("gainCoin"), 0, "the comp dies on the first REFRESH")
    }

    func testRemovalLadderPersistsAcrossVisits() {
        let c = campaign()
        c.removalsBought = 2
        _ = c.openStore(node: 10)
        let atShopA = c.removalPrice()
        _ = c.openStore(node: 11)
        XCTAssertEqual(c.removalPrice(), atShopA, "the purge ladder is per CLIMB, not per visit")
    }
}
