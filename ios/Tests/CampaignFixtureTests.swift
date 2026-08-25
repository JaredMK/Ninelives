import XCTest
@testable import GameCore

/// CAMPAIGN-LAYER GOLDEN TESTS. Every expectation here is the committed
/// GOLDEN BASELINE captured from GameCore itself by `GoldenRecorder`
/// (see GoldenSupport.swift; regenerate with `make golden`).
final class CampaignFixtureTests: XCTestCase {

    static let root: [String: JSONValue] = {
        let bundle = Bundle(for: CampaignFixtureTests.self)
        guard let url = bundle.url(forResource: "campaign-fixtures", withExtension: "json") else {
            fatalError("campaign-fixtures.json is not in the test bundle — run `make golden`")
        }
        let data = try! Data(contentsOf: url)
        return try! JSONDecoder().decode([String: JSONValue].self, from: data)
    }()
    static func list(_ key: String) -> [JSONValue] { root[key]?.asArray ?? [] }

    private func campaign(deck: String, tier: String, seed: Int) -> CampaignState {
        let c = CampaignState()
        c.setDeck(deck)
        c.setTier(tier)
        c.setSeedOverride(UInt32(truncatingIfNeeded: seed))
        c.reset()
        return c
    }

    /// The fixture encodes a locked special as "J"/"B" and a real card as its id.
    private func sentinel(_ v: JSONValue?) -> String? {
        guard let v, !v.isNull else { return nil }
        if let s = v.asString { return s }
        if let n = v.asInt { return String(n) }
        return nil
    }
    private func sentinel(forCardId id: Int) -> String {
        id == CampaignState.specialJoker ? "J" : (id == CampaignState.specialBlank ? "B" : String(id))
    }

    // MARK: - Fresh starts

    func testStartNewRunMatchesGolden() {
        var checked = 0
        for f in Self.list("starts") {
            let seed = f["seed"]?.asInt ?? 0
            let deck = f["deck"]?.asString ?? "pink"
            let tier = f["tier"]?.asString ?? "regular"
            let label = "start seed=\(seed) deck=\(deck) tier=\(tier)"
            let c = campaign(deck: deck, tier: tier, seed: seed)

            XCTAssertEqual(Int(c.runSeed), f["runSeed"]?.asInt, "\(label): runSeed")
            XCTAssertEqual(c.exhibition, f["exhibition"]?.asBool, "\(label): exhibition")
            XCTAssertEqual(c.getRunDeck().map(\.id), f["ownedIds"]?.intArray ?? [], "\(label): run deck ids")
            XCTAssertEqual(c.deckSize(), f["deckSize"]?.asInt, "\(label): deckSize")
            // baseDeck also holds the MAP's pre-minted cards (node locks, pack
            // pairs) — map-shaped, so no web pin; it must simply cover the
            // owned deck and regenerate identically (checked below).
            XCTAssertGreaterThanOrEqual(c.baseDeck.count, c.deckSize(), "\(label): baseDeck covers the deck")
            XCTAssertEqual(c.columnPillars, f["columnPillars"]?.asArray?.map { $0.asString } ?? [],
                           "\(label): columnPillars")
            XCTAssertEqual(c.columnBases, f["columnBases"]?.asArray?.map { $0.asString } ?? [],
                           "\(label): columnBases")

            // The start cards — including the
            // alt decks' one-of-each-rank random suits.
            let wantCards = f["startCards"]?.asArray ?? []
            let gotCards = c.getRunDeck()
            XCTAssertEqual(gotCards.count, wantCards.count, "\(label): start card count")
            for (i, w) in wantCards.enumerated() where i < gotCards.count {
                let g = gotCards[i]
                XCTAssertEqual(g.id, w["id"]?.asInt, "\(label) card[\(i)]: id")
                XCTAssertEqual(g.suit, w["suit"]?.asString, "\(label) card[\(i)]: suit")
                XCTAssertEqual(g.currentRank, w["currentRank"]?.asInt, "\(label) card[\(i)]: currentRank")
                XCTAssertEqual(g.originalRank, w["originalRank"]?.asInt, "\(label) card[\(i)]: originalRank")
                XCTAssertEqual(g.joker, w["joker"]?.asBool, "\(label) card[\(i)]: joker")
                XCTAssertEqual(g.stickers.map(\.type), w["stickers"]?.stringArray ?? [],
                               "\(label) card[\(i)]: stickers")
            }

            // The +1 node locks and the pack pairs ride the MAP, which has
            // deliberately grown native rules (per-node deal danger, the +4
            // pack) — web captures no longer compare. The surviving promise
            // is DETERMINISM: the same seed locks the same cards every time.
            let c2 = campaign(deck: deck, tier: tier, seed: seed)
            XCTAssertEqual(c.nodeCards, c2.nodeCards, "\(label): node-card determinism")
            XCTAssertEqual(c.packCards, c2.packCards, "\(label): pack-pair determinism")
            XCTAssertFalse(c.nodeCards.isEmpty, "\(label): the map must lock SOME node cards")
            XCTAssertEqual(c.baseDeck.count, c2.baseDeck.count, "\(label): baseDeck determinism")
            XCTAssertEqual(c.nextCardId, c2.nextCardId, "\(label): nextCardId determinism")

            if let jb = f["jokerBudget"] {
                XCTAssertEqual(c.jokerCapFor(), jb["cap"]?.asInt, "\(label): joker cap")
                XCTAssertEqual(c.jokersHeld(), jb["committed"]?.asInt, "\(label): jokers held")
                XCTAssertEqual(c.jokersAllowed(), jb["allowed"]?.asBool, "\(label): jokers allowed")
            }
            checked += 1
        }
        XCTAssertGreaterThan(checked, 0, "no start fixtures were exercised")
    }

    // MARK: - Store

    /// THE STORE ROLL. This used to replay offers captured from the WEB engine
    /// slot-for-slot. iOS is the only build now, and it has deliberately grown
    /// store rules the web never had — most recently "an item you already have
    /// equipped is not offered" — so a web-captured shelf is no longer ground
    /// truth for what iOS should roll. Pinning to it blocked exactly the
    /// changes we want to make.
    ///
    /// The fixtures are still used, as a SEED CORPUS: every recorded (deck,
    /// seed, node) is replayed and the shelf is checked against the rules iOS
    /// actually promises. That keeps the coverage — determinism, the class cap,
    /// unlock gating, the equipped exclusion, the Purge slot — without pinning
    /// it to an engine we no longer ship.
    func testStoreOffersFollowTheRules() {
        let cap = GameData.shared.items.store.typeCap
        let slots = GameData.shared.items.store.slots
        var checked = 0
        for f in Self.list("stores") {
            let seed = f["seed"]?.asInt ?? 0
            let deck = f["deck"]?.asString ?? "pink"
            let label = "store seed=\(seed) deck=\(deck)"
            let c = campaign(deck: deck, tier: "regular", seed: seed)
            if let first = c.legalNextNodes().first { c.moveToNode(first.id) }
            XCTAssertEqual(c.nodePos, f["nodePos"]?.asInt, "\(label): nodePos")
            c.addCoins(10000)

            // DETERMINISM: the same campaign at the same node rolls the same
            // shelf every time. This is the property the fixture replay was
            // really protecting, and it survives any rule change.
            let a = c.openStore()
            let b = campaign(deck: deck, tier: "regular", seed: seed)
            if let first = b.legalNextNodes().first { b.moveToNode(first.id) }
            b.addCoins(10000)
            let a2 = b.openStore()
            XCTAssertEqual(a.slots.map { $0?.kind }, a2.slots.map { $0?.kind },
                           "\(label): the same seed must roll the same shelf")
            XCTAssertEqual(a.slots.map { $0?.id }, a2.slots.map { $0?.id }, "\(label): …same ids")
            XCTAssertEqual(a.rerollCost, a2.rerollCost, "\(label): …same reroll cost")

            // …and every shelf, fresh or rerolled, obeys the shop's own rules.
            var offer = a
            for visit in 0..<3 {
                XCTAssertEqual(offer.slots.count, slots, "\(label) visit \(visit): slot count")
                var perKind: [String: Int] = [:]
                for slot in offer.slots.compactMap({ $0 }) {
                    perKind[slot.kind, default: 0] += 1
                    // LOCKED items never reach the shelf…
                    if let def = Self.defFor(slot) {
                        XCTAssertTrue(c.itemUnlocks.isUnlocked(def),
                                      "\(label) visit \(visit): offered locked '\(slot.id)'")
                    }
                    // …and neither does something already equipped.
                    XCTAssertFalse(c.isEquipped(kind: slot.kind, id: slot.id),
                                   "\(label) visit \(visit): offered equipped '\(slot.id)'")
                }
                for (kind, n) in perKind where kind != "removal" {
                    XCTAssertLessThanOrEqual(n, cap, "\(label) visit \(visit): \(kind) exceeds the class cap")
                }
                // No shelf repeats an ITEM (cards exempt: each is minted fresh).
                let itemIds = offer.slots.compactMap { $0 }.filter { $0.kind != "card" && $0.kind != "removal" }
                    .map { "\($0.kind).\($0.id)" }
                XCTAssertEqual(itemIds.count, Set(itemIds).count,
                               "\(label) visit \(visit): the shelf offered the same item twice")
                XCTAssertEqual(offer.slots.contains { $0?.kind == "removal" }, c.removalSlotOn(),
                               "\(label) visit \(visit): the Purge slot follows its toggle")
                guard visit < 2 else { break }
                XCTAssertTrue(c.rerollStore(), "\(label): reroll \(visit + 1) should succeed")
                offer = c.getStoreOffer()!
            }
            checked += 1
        }
        XCTAssertGreaterThan(checked, 0, "no store fixtures were exercised")
    }

    /// The registry def behind a shelf slot, when the slot names one.
    private static func defFor(_ slot: StoreSlot) -> ItemDef? {
        let d = GameData.shared
        switch slot.kind {
        case "sticker":   return d.stickerTypes.get(slot.id)
        case "pillar":    return d.pillarTypes.get(slot.id)
        case "base":      return d.baseTypes.get(slot.id)
        case "pack":      return d.packTypes.get(slot.id)
        case "samepower": return d.samePowerTypes.get(slot.id)
        default:          return nil          // card / removal carry no def
        }
    }

    // MARK: - Mystery

    /// THE MYSTERY ROLL. Same story as the shelf: it used to replay the web's
    /// rolls key-for-key, but the native build has grown outcome keys the web
    /// never rolled (the Queen's gifts, the Two's tricks), so a web-captured
    /// sequence is no longer ground truth. The fixtures stay as a SEED CORPUS;
    /// the assertions are the roll's own promises: the runSeed derivation is
    /// still web-exact, every rolled key is registered, and the same run+node
    /// rolls the same key every time.
    func testMysteryRollsFollowTheRules() {
        for f in Self.list("mystery") {
            let seed = f["seed"]?.asInt ?? 0
            let c = campaign(deck: "pink", tier: "regular", seed: seed)
            XCTAssertEqual(Int(c.runSeed), f["runSeed"]?.asInt, "mystery seed \(seed): runSeed")
            let c2 = campaign(deck: "pink", tier: "regular", seed: seed)
            let nodes = Array(0..<40) + [1000, 2003, 800000, 900000]
            for nodeId in nodes {
                let key = c.rollMysteryEvent(nodeId)
                XCTAssertTrue(MysteryConfig.outcomeKeys.contains(key),
                              "seed \(seed) node \(nodeId): unregistered key '\(key)'")
                XCTAssertEqual(key, c2.rollMysteryEvent(nodeId),
                               "seed \(seed) node \(nodeId): the same run+node must roll the same key")
            }
        }
    }

    // MARK: - Packs + store cards

    /// PACK REVEALS. This used to replay web-captured reveals item-for-item,
    /// but the sticker roll's weights are a live tuning surface (the
    /// changeSuit family was de-weighted in v6.36), so the captured ids are
    /// no longer ground truth. The fixtures stay a SEED CORPUS; the
    /// assertions are the reveal's own promises: same seed → same reveal,
    /// the item count matches the capture, every rolled id is a real
    /// registered item, every card obeys the sticker rules (including
    /// no-duplicates), and the mint delta is unchanged.
    func testPackRevealsFollowTheRules() {
        let data = GameData.shared
        for f in Self.list("packs") {
            let seed = f["seed"]?.asInt ?? 0
            let deck = f["deck"]?.asString ?? "pink"
            let packId = f["packId"]?.asString ?? ""
            let label = "pack \(packId) seed=\(seed) deck=\(deck)"
            let c = campaign(deck: deck, tier: "regular", seed: seed)
            let c2 = campaign(deck: deck, tier: "regular", seed: seed)
            let idBefore = c.nextCardId
            let rng = RNG(seed: UInt32(truncatingIfNeeded: seed) ^ 0xabcdef)
            let rng2 = RNG(seed: UInt32(truncatingIfNeeded: seed) ^ 0xabcdef)
            let out = c.revealPack(packId, rng: rng)
            let again = c2.revealPack(packId, rng: rng2)
            let wantCount = f["count"]?.asInt ?? -1
            if f["kind"]?.asString == "card" {
                XCTAssertEqual(out.cards.count, wantCount, "\(label): card count")
                XCTAssertEqual(out.cards.map(\.suit), again.cards.map(\.suit), "\(label): determinism (suits)")
                XCTAssertEqual(out.cards.map(\.currentRank), again.cards.map(\.currentRank),
                               "\(label): determinism (ranks)")
                XCTAssertEqual(out.cards.map { $0.stickers.map(\.type) },
                               again.cards.map { $0.stickers.map(\.type) },
                               "\(label): determinism (stickers)")
                for card in out.cards where !card.joker && !card.blank {
                    let ids = card.stickers.map(\.type)
                    XCTAssertEqual(ids.count, Set(ids).count, "\(label): a card rolled the same sticker twice")
                    XCTAssertLessThanOrEqual(ids.count, data.items.maxStickersPerCard, "\(label): over the cap")
                    for sid in ids {
                        XCTAssertNotNil(data.stickerTypes.get(sid), "\(label): unregistered sticker '\(sid)'")
                    }
                }
            } else {
                XCTAssertEqual(out.stickers.count, wantCount, "\(label): sticker count")
                XCTAssertEqual(out.stickers, again.stickers, "\(label): determinism (sticker ids)")
                for sid in out.stickers {
                    XCTAssertNotNil(data.stickerTypes.get(sid), "\(label): unregistered sticker '\(sid)'")
                }
            }
            XCTAssertEqual(c.nextCardId - idBefore, f["minted"]?.asInt ?? -1,
                           "\(label): cards minted by the reveal")
        }
    }

    /// THE STORE CARD SLOT. Same story as the shelf above: these used to
    /// replay web-captured mints byte-for-byte, but the card slot now rolls
    /// its OWN sticker table (`store.card.stickerOdds`) and prices the card
    /// by what it carries — rules the web never had. The fixtures stay as a
    /// SEED CORPUS; the assertions are iOS's own promises: determinism, the
    /// odds table's ceiling, per-deck rules, and sticker-stepped pricing.
    func testStoreCardMintsFollowTheRules() {
        let cardCfg = GameData.shared.items.store.card
        let maxStickers = Int(cardCfg.stickerOdds.map { $0[1] }.max() ?? 0)
        var stickeredMints = 0
        for f in Self.list("storeCards") {
            let seed = f["seed"]?.asInt ?? 0
            let deck = f["deck"]?.asString ?? "pink"
            let label = "storeCard seed=\(seed) deck=\(deck)"
            let c = campaign(deck: deck, tier: "regular", seed: seed)
            let c2 = campaign(deck: deck, tier: "regular", seed: seed)
            let rng = RNG(seed: UInt32(truncatingIfNeeded: seed) ^ 0x51ca5d)
            let rng2 = RNG(seed: UInt32(truncatingIfNeeded: seed) ^ 0x51ca5d)
            for i in 0..<12 {
                guard let got = c.genStoreCard(rng), let again = c2.genStoreCard(rng2) else {
                    XCTFail("\(label)[\(i)]: nil card"); continue
                }
                // DETERMINISM: the same seed mints the same card.
                XCTAssertEqual(got.suit, again.suit, "\(label)[\(i)]: suit")
                XCTAssertEqual(got.currentRank, again.currentRank, "\(label)[\(i)]: rank")
                XCTAssertEqual(got.joker, again.joker, "\(label)[\(i)]: joker")
                XCTAssertEqual(got.stickers.map(\.type), again.stickers.map(\.type),
                               "\(label)[\(i)]: stickers")
                // The card slot's own odds table bounds the sticker count…
                XCTAssertLessThanOrEqual(got.stickers.count, maxStickers,
                                         "\(label)[\(i)]: more stickers than the table allows")
                // …and the no-sticker rule still holds at the mint.
                if c.rules().noStickers {
                    XCTAssertEqual(got.stickers.count, 0, "\(label)[\(i)]: no-sticker mints take no stickers")
                }
                if got.stickers.count > 0 { stickeredMints += 1 }
                // PRICING: base + stickerStep per sticker; Jokers keep their
                // own flat price. Quoted through the one shelf chokepoint.
                c.storeOffer = StoreOffer(slots: [StoreSlot(kind: "card", id: "card", card: got)],
                                          rerollCost: 5)
                let raw = got.joker ? cardCfg.jokerPrice
                    : cardCfg.price + Double(got.stickers.count) * cardCfg.stickerStep
                XCTAssertEqual(c.priceOfMixed(0), c.shopPrice(raw), "\(label)[\(i)]: price")
            }
        }
        XCTAssertGreaterThan(stickeredMints, 0,
                             "across the whole corpus SOME mint must carry a sticker")
    }

    // MARK: - Serialize / restore

    func testSerializeRestoreRoundTripMatchesGolden() {
        for f in Self.list("roundTrips") {
            let seed = f["seed"]?.asInt ?? 0
            let deck = f["deck"]?.asString ?? "pink"
            let tier = f["tier"]?.asString ?? "legendary"
            let label = "roundTrip seed=\(seed) deck=\(deck)"
            let c = campaign(deck: deck, tier: tier, seed: seed)
            if let first = c.legalNextNodes().first { c.moveToNode(first.id) }
            c.addCoins(250)
            c.addRunScore(37)
            let blob = c.serialize()
            // THE SAVE-SHAPE LAW: the blob's key set matches the golden
            // EXACTLY. A dropped key silently loses player state; a new key
            // is a save-format change and must be a deliberate act — make it
            // by re-recording the baseline in the same commit.
            XCTAssertEqual(Set(blob.keys), Set(f["blobKeys"]?.stringArray ?? []),
                           "\(label): the save's key set diverged from the golden — "
                           + "added \(Set(blob.keys).subtracting(f["blobKeys"]?.stringArray ?? []).sorted()), "
                           + "dropped \(Set(f["blobKeys"]?.stringArray ?? []).subtracting(blob.keys).sorted())")

            let c2 = CampaignState()
            XCTAssertEqual(c2.restore(blob), f["ok"]?.asBool, "\(label): restore ok")
            guard let after = f["after"] else { continue }
            XCTAssertEqual(c2.deckId, after["deckId"]?.asString, "\(label): deckId")
            XCTAssertEqual(c2.difficultyTier, after["tier"]?.asString, "\(label): tier")
            XCTAssertEqual(Int(c2.runSeed), after["runSeed"]?.asInt, "\(label): runSeed")
            XCTAssertEqual(c2.nodePos, after["nodePos"]?.asInt, "\(label): nodePos")
            XCTAssertEqual(c2.coins, after["coins"]?.asInt, "\(label): coins")
            XCTAssertEqual(c2.runScore, after["runScore"]?.asInt, "\(label): runScore")
            XCTAssertEqual(c2.getRunDeck().map(\.id), after["ownedIds"]?.intArray ?? [], "\(label): run deck ids")
            XCTAssertEqual(c2.deckSize(), after["deckSize"]?.asInt, "\(label): deckSize")
            // The map is native-shaped now; the round-trip's promise is that
            // the restore REGENERATES the same map the save was made on.
            XCTAssertEqual(c2.runMap?.nodes.count, c.runMap?.nodes.count,
                           "\(label): restore regenerates the same map")
            XCTAssertEqual(c2.runMap?.totalRows, c.runMap?.totalRows,
                           "\(label): …same rows")
        }
    }

    // MARK: - Layout

    func testLayoutForPilesMatchesGolden() {
        for f in Self.list("layouts") {
            let n = f["piles"]?.asInt ?? 0
            let l = CampaignLayout.layoutForPiles(n)
            XCTAssertEqual(l.cols, f["cols"]?.intArray ?? [], "layoutForPiles(\(n)): cols")
            XCTAssertEqual(l.piles, f["sum"]?.asInt, "layoutForPiles(\(n)): piles")
            XCTAssertEqual(l.rows, f["rows"]?.asInt, "layoutForPiles(\(n)): rows")
        }
    }
}
