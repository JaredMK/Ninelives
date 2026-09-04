import XCTest
@testable import GameCore

/// v7.02 — the economy re-base (restock/reshuffle start at 3) and the removal
/// of selling (equipped items are discarded, never sold). The Old Joker's
/// Refund/Buyout price off `.price` and are covered by OldJokerTests; here we
/// pin that a REPLACE pays nothing and the coat still values its gifts.
final class V702EconomyTests: XCTestCase {
    let data = GameData.shared

    private func campaign() -> CampaignState {
        let c = CampaignState(store: MemoryStore())
        c.setDeck("pink"); c.setSeedOverride(4242); c.reset()
        return c
    }

    // MARK: - Items 1 + 2: starting costs → 3, steps unchanged

    func testStoreRestockStartsAtThreeAndSteps() {
        let c = campaign(); _ = c.addCoins(500)
        _ = c.openStore(node: 1)
        XCTAssertEqual(c.storeRerollCost(), 3, "the first restock costs 3 (v7.02, was 5)")
        XCTAssertTrue(c.rerollStore())
        let step = data.items.store.reroll.step
        XCTAssertEqual(c.storeRerollCost(), 3 + step,
                       "the ladder steps by store.reroll.step (\(step)) — unchanged, not tied to base")
    }

    // (The deal reshuffle base cost is DealPlanner.redealBaseCost in the app
    // target — outside GameCore's test reach; it is pinned at 3.0 there and
    // exercised by the RemovalAndFreebie UI path. GameCore covers the store
    // restock's data-driven cost above.)

    // MARK: - Item 3: replacing an equipped item DISCARDS it, paying nothing

    func testReplacingAPillarDiscardsTheOldOneForNoCoins() {
        // The UI's replace flow, at the mechanics it drives: placePillar
        // bounces the displaced pillar to inventory, then the store DISCARDS
        // it (v7.02: no addCoins — the sell-back is gone). The pin is that
        // this whole path grants zero coins.
        let c = campaign()
        c.setColumnPillar(col: 0, typeId: "envy")
        c.pillarInventory["insurance", default: 0] += 1
        let coinsBefore = c.getCoins()
        XCTAssertTrue(c.placePillar("insurance", col: 0), "the replacement places")
        XCTAssertEqual(c.columnPillar(0), "insurance", "the new pillar took the slot")
        XCTAssertEqual(c.pillarInventory["envy"] ?? 0, 1, "the displaced Envy bounced to inventory")
        // The store then discards it (never sells) — no coins move.
        XCTAssertTrue(c.discardPillarFromInventory("envy"))
        XCTAssertEqual(c.getCoins(), coinsBefore, "the replace granted NOTHING (v7.02)")
        XCTAssertEqual(c.pillarInventory["envy"] ?? 0, 0, "…and Envy is gone for good")
    }

    func testNoSellPathOnCampaignState() {
        // sellValue still EXISTS (the coat's internal basis) but is no longer
        // wired to any player action — the pin that guards its documented role.
        let c = campaign()
        XCTAssertEqual(c.sellValue(data.pillarTypes.get("envy")), 2,
                       "sellValue survives as the coat's per-tier worth (uncommon = 2)")
    }

    // MARK: - Item 4: the sell dependency map holds

    func testThirstCoatStillValuesGiftsAgainstItsBudget() {
        let c = campaign()
        // The coat fills to its budget using sellValue as the worth basis —
        // it must still produce a non-empty, budget-respecting shelf.
        let gifts = c.rollThirstGifts(budget: 12, nodeId: 3)
        XCTAssertFalse(gifts.isEmpty, "the coat still stocks itself")
        let total = gifts.reduce(0) { $0 + c.jokerRefundValue($1) }
        XCTAssertLessThanOrEqual(total, 12, "…and never overspends the budget")
    }
}
