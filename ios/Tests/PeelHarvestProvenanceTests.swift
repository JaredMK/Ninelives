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

    func testPurgeCouponTextNamesTheLiveLadder() {
        let def = data.baseTypes.get("purgeDiscount")!
        XCTAssertEqual(def.int("value", 0), 2, "the approved v6.91 cut")
        let c = CampaignState(store: MemoryStore())
        c.setDeck("pink"); c.setTier("regular"); c.setSeedOverride(7); c.reset()
        let cur = Int(c.removalPrice())
        let target = max(5, cur - 2)
        let out = c.itemDescription(def)
        XCTAssertFalse(out.contains("{current}"), "the tokens substitute")
        XCTAssertTrue(out.contains("◉\(cur) → ◉\(target)"), "…with the LIVE ladder: \(out)")
        XCTAssertTrue(out.contains("Minimum 5"))
        // The floor shows when the ladder is already at it.
        c.addPurgeDiscount(999)
        let floored = c.itemDescription(def)
        XCTAssertTrue(floored.contains("◉5 → ◉5"), "at the floor, both sides read 5: \(floored)")
    }
}
