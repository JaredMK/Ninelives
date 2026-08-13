import XCTest
@testable import GameCore

/// v6.49 BUGFIXES: a removed card must leave the card UNIVERSE (never to be
/// re-offered by a pack or +1 node), and every store purchase must charge the
/// slot's RESOLVED price — the one the shelf displays (Freebie's 0 included).
final class RemovalAndFreebieTests: XCTestCase {

    private func campaign() -> CampaignState {
        let c = CampaignState(store: MemoryStore())
        c.setDeck("pink"); c.setTier("regular"); c.reset()
        return c
    }

    // MARK: - 1. Purged cards can never come back

    func testPurgedCardNeverAppearsInAnyDraftPoolAgain() {
        let c = campaign()
        // Curse + sticker the victim, exactly like the reported repro (the
        // returned card carried its old stickers — the stale-spec signature).
        let victim = c.getRunDeck().first { !$0.joker && !$0.blank }!
        _ = c.applyStickerDirect(victim.id, "leech")
        XCTAssertTrue(c.removeDeckCard(victim.id))

        XCTAssertNil(c.findById(victim.id), "the spec left the universe, stickers and all")
        XCTAssertFalse(c.getRunDeck().contains { $0.id == victim.id })

        // Every draft source, hammered: the id must never surface.
        let rng = RNG(seed: 1234)
        for _ in 0..<300 {
            XCTAssertNotEqual(c.pickDraftId(mixed: true, rng: rng), victim.id)
            XCTAssertNotEqual(c.pickDraftId(mixed: false, rng: rng), victim.id)
            XCTAssertNotEqual(c.pickSuitDraftId(victim.suit, rng: rng), victim.id)
        }
        // +1 node rolls across many node ids.
        if let m = c.runMap {
            for node in m.nodes where node.type == "pickup" {
                XCTAssertNotEqual(c.draftIdForNode(node), victim.id,
                                  "node \(node.id) re-offered the purged card")
            }
        }
    }

    func testEveryRemovalPathLeavesTheUniverse() {
        // The Old Joker's DUPLICATE replaces a card — the replaced identity
        // must leave the universe exactly like a purge does.
        let c = campaign()
        let cards = c.getRunDeck().filter { !$0.joker && !$0.blank }
        let source = cards[0], replaced = cards[1]
        _ = c.applyStickerDirect(replaced.id, "trapdoor")
        XCTAssertNotNil(c.applyJokerDuplicate(sourceId: source.id, replaceId: replaced.id,
                                              sticker: "leech"))
        XCTAssertNil(c.findById(replaced.id), "the replaced card left the universe")
        let rng = RNG(seed: 99)
        for _ in 0..<200 {
            XCTAssertNotEqual(c.pickDraftId(mixed: true, rng: rng), replaced.id)
        }
    }

    func testRemovalSurvivesTheSaveRoundTrip() {
        let c = campaign()
        let victim = c.getRunDeck().first { !$0.joker && !$0.blank }!
        XCTAssertTrue(c.removeDeckCard(victim.id))
        let c2 = CampaignState(store: MemoryStore())
        XCTAssertTrue(c2.restore(c.serialize()))
        XCTAssertNil(c2.findById(victim.id), "the removal persists across save/restore")
        let rng = RNG(seed: 5)
        for _ in 0..<200 {
            XCTAssertNotEqual(c2.pickDraftId(mixed: true, rng: rng), victim.id)
        }
    }

    // MARK: - 2. The shelf price IS the charged price

    /// Force a store offer whose freeSlot is a given kind; returns the slot
    /// index, or nil if the roll never produced one (caller skips).
    private func freebieCampaign() -> (CampaignState, Int)? {
        // Roll stores until the freebie lands somewhere: equip the pillar,
        // then walk seeds.
        for seed: UInt32 in 1...80 {
            let c = CampaignState(store: MemoryStore())
            c.setDeck("pink"); c.setTier("regular")
            c.setSeedOverride(seed)
            c.reset()
            // Equip the freebie pillar directly (inventory + column).
            c.pillarInventory["freebie", default: 0] += 1
            c.setColumnPillar(col: 0, typeId: "freebie")
            _ = c.openStore()
            if let i = c.storeOffer?.freeSlot { return (c, i) }
        }
        return nil
    }

    func testFreeSlotChargesZeroEvenOnAnEmptyPurse() {
        guard let (c, i) = freebieCampaign() else {
            return XCTFail("no seed in 1...80 rolled a freebie slot")
        }
        let slot = c.storeOffer!.slots[i]!
        XCTAssertEqual(c.priceOfMixed(i), 0, "the shelf shows the gifted slot at 0")
        // THE reported repro: an EMPTY purse must not block a 0-cost buy.
        while c.getCoins() > 0 { _ = c.spendCoins(1) }
        switch slot.kind {
        case "sticker":
            XCTAssertTrue(c.buyOfferedSticker(i), "a free sticker buys with 0 coins")
            XCTAssertEqual(c.stickerInventory[slot.id], 1)
        case "pack":
            let r = c.buyMixedSlot(i)
            XCTAssertTrue(r.ok, "a free pack opens with 0 coins")
        default:
            let r = c.buyMixedSlot(i)
            XCTAssertTrue(r.ok, "a free \(slot.kind) buys with 0 coins")
        }
        XCTAssertEqual(c.getCoins(), 0, "nothing was charged")
    }

    func testEveryShelfKindChargesItsDisplayedPrice() {
        // No freebie: charge must equal priceOfMixed exactly for each kind.
        let c = campaign()
        _ = c.addCoins(500)
        _ = c.openStore()
        guard let slots = c.storeOffer?.slots else { return XCTFail("no offer") }
        for (i, s) in slots.enumerated() {
            guard let s else { continue }
            guard s.kind != "removal" else { continue }   // its own repeatable flow
            let displayed = c.priceOfMixed(i)
            let before = c.getCoins()
            let ok: Bool
            if s.kind == "sticker" { ok = c.buyOfferedSticker(i) }
            else { ok = c.buyMixedSlot(i).ok }
            guard ok else { continue }   // e.g. equipped-dupe guards
            XCTAssertEqual(Double(before - c.getCoins()), displayed,
                           "\(s.kind) \(s.id): charged what the shelf displayed")
        }
    }
}
