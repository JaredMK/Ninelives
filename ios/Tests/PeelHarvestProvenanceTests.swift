import XCTest
@testable import GameCore

/// v6.91 batch pins: Curse Harvest's trigger precision, the Peeler's
/// cover-only rework (its deep pins live in CurseTests), conversion
/// provenance across BOTH persistence layers, and the Coupon's live text.
final class PeelHarvestProvenanceTests: XCTestCase {
    private let data = GameData.shared

    func testCurseHarvestIgnoresASameLandingConversion() {
        // The Tell carrier's ♠ bet misses on a ♥/♦ board — it CONVERTS at
        // this landing. Curse Harvest must stay quiet: the card landed
        // clean and left cursed; the conversion is not a cursed landing.
        let e = IV.engine(tops: [IV.spec(1, 5, "♠"), IV.spec(2, 6, "♥"), IV.spec(3, 7, "♦")],
                          deckOrder: [IV.spec(50, 3, "♠", ["tell"]), IV.spec(51, 4, "♥"),
                                      IV.spec(52, 8, "♥")],
                          pillars: ["curseHarvest", nil, nil])
        let deckBefore = e.deck.remaining()
        e.guess(0, .lower)                       // lands correct, then converts
        XCTAssertFalse(e.board.top(0)!.stickers.isEmpty, "setup: the conversion happened")
        XCTAssertFalse(e.run.revealNextActive, "no Harvest peek — the curse arrived AFTER landing")
        XCTAssertEqual(e.deck.remaining(), deckBefore - 1, "…and no Harvest bury either")
        // Contrast: a card that lands ALREADY cursed fires it.
        let cursed = IV.engine(tops: [IV.spec(1, 5, "♠"), IV.spec(2, 6, "♥"), IV.spec(3, 7, "♦")],
                               deckOrder: [IV.spec(50, 9, "♠", ["mute"]), IV.spec(51, 4, "♥"),
                                           IV.spec(52, 8, "♥")],
                               pillars: ["curseHarvest", nil, nil])
        cursed.guess(0, .higher)
        XCTAssertTrue(cursed.run.revealNextActive, "an already-cursed landing fires the Harvest")
    }

    func testConversionProvenanceSurvivesBothPersistenceLayers() {
        // ENGINE snapshot: convert, snapshot, restore into a twin — the
        // curse still knows what it used to be.
        let build = {
            IV.engine(tops: [IV.spec(1, 5, "♠"), IV.spec(2, 6, "♥"), IV.spec(3, 7, "♦")],
                      deckOrder: [IV.spec(50, 3, "♠", ["tell"]), IV.spec(51, 4, "♥")])
        }
        let e = build()
        e.guess(0, .lower)                       // the Tell converts
        let converted = e.board.top(0)!.stickers.first!
        XCTAssertEqual(converted.convertedFrom, "tell", "the live record carries provenance")
        let twin = build()
        XCTAssertTrue(twin.restoreSnapshot(e.snapshot()))
        XCTAssertEqual(twin.board.top(0)!.stickers.first?.convertedFrom, "tell",
                       "…and it survives the mid-deal snapshot")
        // CAMPAIGN save: the durable conversion write + serialize/restore.
        let c = CampaignState(store: MemoryStore())
        c.setDeck("pink"); c.setTier("regular"); c.setSeedOverride(7); c.reset()
        let victim = c.getRunDeck().first!
        XCTAssertTrue(c.applySticker(victim.id, "tell") || c.applyStickerDirect(victim.id, "tell"))
        XCTAssertTrue(c.convertStickerOnCard(victim.id, from: "tell", to: "leech"))
        let rec = c.getRunDeck().first { $0.id == victim.id }!.stickers.first { $0.type == "leech" }
        XCTAssertEqual(rec?.convertedFrom, "tell", "the durable record carries provenance")
        let c2 = CampaignState(store: MemoryStore())
        XCTAssertTrue(c2.restore(c.serialize()))
        let rec2 = c2.getRunDeck().first { $0.id == victim.id }!.stickers.first { $0.type == "leech" }
        XCTAssertEqual(rec2?.convertedFrom, "tell", "…and it survives the campaign save")
    }

    func testPurgeCouponTextIsTokenFreeAndThePreviewRidesTheLadder() {
        let def = data.baseTypes.get("purgeDiscount")!
        // v6.93: the data text carries NO {current}/{new} tokens — the cut is
        // a live board read (♦-topped piles in the column), so the deal UI
        // computes the price preview at fire time. No path can leak a raw
        // token again (the Collection / post-fire popup leaks this replaces).
        XCTAssertFalse(def.description.contains("{"),
                       "no template tokens in the shared text: \(def.description)")
        XCTAssertTrue(def.description.contains("♦"), "the per-diamond rule is stated")
        XCTAssertTrue(def.description.contains("minimum \(def.int("min", 5))"),
                      "the floor is stated: \(def.description)")
        // PRICE BASIS (the {current} rule): removalPrice() is the NEXT
        // visit's price — the ladder term for purchases already made this
        // climb is in it, not the price last paid.
        let cfg = data.items.store.removal
        // The default deck (multiplier 1 — the ladder suite's setup) keeps
        // the equality exact.
        let c = CampaignState(store: MemoryStore())
        c.setSeedOverride(7); c.reset()
        c.addCoins(10_000)
        let p0 = c.removalPrice()
        XCTAssertTrue(c.buyRemoval(c.ownedIds[0]))
        XCTAssertTrue(c.buyRemoval(c.ownedIds[0]))
        let next = c.removalPrice()
        XCTAssertGreaterThan(next, p0, "two purchases this climb moved the quote")
        XCTAssertEqual(next, p0 + cfg.priceStep * 2,
                       "…by exactly one step per purchase — the NEXT visit's price")
        // The {new} rule: the preview is removalPrice with the fire's cut
        // banked — the SAME ladder, so the preview can never disagree with
        // what the register charges after the fire.
        let cut = 2 * def.int("perDiamond", 1)
        let preview = c.removalPrice(extraCut: cut)
        c.addPurgeDiscount(cut)
        XCTAssertEqual(c.removalPrice(), preview,
                       "the preview equals the post-fire price, through the same ladder")
        // …and the floor holds inside the preview too.
        XCTAssertEqual(c.removalPrice(extraCut: 999),
                       max(1, c.shopPrice(def.num("min", 5)).rounded()),
                       "the preview never quotes below the Coupon's min")
    }
}
