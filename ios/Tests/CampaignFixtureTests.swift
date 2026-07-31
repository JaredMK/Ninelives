import XCTest
@testable import GameCore

/// CAMPAIGN-LAYER CROSS-IMPLEMENTATION TESTS. Every expectation here was
/// captured from the REAL web CampaignState by `ios/Tools/export-campaign.mjs`.
final class CampaignFixtureTests: XCTestCase {

    static let root: [String: JSONValue] = {
        let bundle = Bundle(for: CampaignFixtureTests.self)
        guard let url = bundle.url(forResource: "campaign-fixtures", withExtension: "json") else {
            fatalError("campaign-fixtures.json is not in the test bundle — run `node ios/Tools/export-campaign.mjs`")
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

    func testStartNewRunMatchesWeb() {
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
            XCTAssertEqual(c.baseDeck.count, f["baseDeckSize"]?.asInt, "\(label): baseDeck size")
            XCTAssertEqual(c.columnPillars, f["columnPillars"]?.asArray?.map { $0.asString } ?? [],
                           "\(label): columnPillars")
            XCTAssertEqual(c.columnBases, f["columnBases"]?.asArray?.map { $0.asString } ?? [],
                           "\(label): columnBases")

            // The start cards — including Mr. Smith's rolled stickers and the
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

            // Every +1 node's locked card (shown == granted) and every revealed
            // +2 pack's committed pair.
            let wantNodes = f["nodeCards"]?.asObject ?? [:]
            for (k, want) in wantNodes {
                guard let nodeId = Int(k) else { continue }
                let got = c.nodeCards[nodeId].map(sentinel(forCardId:))
                XCTAssertEqual(got, sentinel(want), "\(label): node \(nodeId) locked card")
            }
            XCTAssertEqual(c.nodeCards.count, wantNodes.count, "\(label): locked node count")

            let wantPacks = f["packCards"]?.asObject ?? [:]
            for (k, want) in wantPacks {
                guard let nodeId = Int(k) else { continue }
                let got = (c.packCards[nodeId] ?? []).map(sentinel(forCardId:))
                XCTAssertEqual(got, want.asArray?.compactMap(sentinel) ?? [], "\(label): pack \(nodeId) pair")
            }

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

    func testStoreOffersMatchWeb() {
        var checked = 0
        for f in Self.list("stores") {
            let seed = f["seed"]?.asInt ?? 0
            let deck = f["deck"]?.asString ?? "pink"
            let label = "store seed=\(seed) deck=\(deck)"
            let c = campaign(deck: deck, tier: "regular", seed: seed)
            let opens = c.legalNextNodes()
            if let first = opens.first { c.moveToNode(first.id) }
            XCTAssertEqual(c.nodePos, f["nodePos"]?.asInt, "\(label): nodePos")
            c.addCoins(10000)

            let visits = f["visits"]?.asArray ?? []
            var offer = c.openStore()
            for (v, want) in visits.enumerated() {
                if v > 0 {
                    XCTAssertTrue(c.rerollStore(), "\(label): reroll \(v) should succeed")
                    offer = c.getStoreOffer()!
                }
                XCTAssertEqual(offer.rerollCost, want["rerollCost"]?.asNumber, "\(label) visit \(v): rerollCost")
                let wantSlots = want["slots"]?.asArray ?? []
                XCTAssertEqual(offer.slots.count, wantSlots.count, "\(label) visit \(v): slot count")
                for (i, ws) in wantSlots.enumerated() where i < offer.slots.count {
                    let gs = offer.slots[i]
                    if ws.isNull { XCTAssertNil(gs, "\(label) visit \(v) slot \(i): expected empty"); continue }
                    XCTAssertEqual(gs?.kind, ws["kind"]?.asString, "\(label) visit \(v) slot \(i): kind")
                    XCTAssertEqual(gs?.id, ws["id"]?.asString, "\(label) visit \(v) slot \(i): id")
                    if let wc = ws["card"], !wc.isNull {
                        XCTAssertEqual(gs?.card?.suit, wc["suit"]?.asString, "\(label) v\(v) s\(i): card suit")
                        XCTAssertEqual(gs?.card?.currentRank, wc["currentRank"]?.asInt, "\(label) v\(v) s\(i): card rank")
                        XCTAssertEqual(gs?.card?.joker, wc["joker"]?.asBool, "\(label) v\(v) s\(i): card joker")
                        XCTAssertEqual(gs?.card?.stickers.map(\.type), wc["stickers"]?.stringArray ?? [],
                                       "\(label) v\(v) s\(i): card stickers")
                    } else {
                        XCTAssertNil(gs?.card, "\(label) v\(v) s\(i): unexpected card")
                    }
                }
            }
            XCTAssertEqual(c.coins, f["coinsAfter"]?.asInt, "\(label): coins after rerolls")
            XCTAssertEqual(c.nextCardId, f["nextCardId"]?.asInt, "\(label): nextCardId after minting")
            checked += 1
        }
        XCTAssertGreaterThan(checked, 0, "no store fixtures were exercised")
    }

    // MARK: - Mystery

    func testMysteryRollsMatchWeb() {
        for f in Self.list("mystery") {
            let seed = f["seed"]?.asInt ?? 0
            let c = campaign(deck: "pink", tier: "regular", seed: seed)
            XCTAssertEqual(Int(c.runSeed), f["runSeed"]?.asInt, "mystery seed \(seed): runSeed")
            let want = f["rolls"]?.stringArray ?? []
            var got: [String] = []
            for nodeId in 0..<40 { got.append(c.rollMysteryEvent(nodeId)) }
            for nodeId in [1000, 2003, 800000, 900000] { got.append(c.rollMysteryEvent(nodeId)) }
            XCTAssertEqual(got, want, "mystery outcome keys for seed \(seed)")
        }
    }

    // MARK: - Packs + store cards

    func testPackRevealsMatchWeb() {
        for f in Self.list("packs") {
            let seed = f["seed"]?.asInt ?? 0
            let deck = f["deck"]?.asString ?? "pink"
            let packId = f["packId"]?.asString ?? ""
            let label = "pack \(packId) seed=\(seed) deck=\(deck)"
            let c = campaign(deck: deck, tier: "regular", seed: seed)
            XCTAssertEqual(c.nextCardId, f["nextCardIdBefore"]?.asInt, "\(label): nextCardId before")
            let rng = RNG(seed: UInt32(truncatingIfNeeded: seed) ^ 0xabcdef)
            let out = c.revealPack(packId, rng: rng)
            let wantItems = f["items"]?.asArray ?? []
            if f["kind"]?.asString == "card" {
                XCTAssertEqual(out.cards.count, wantItems.count, "\(label): card count")
                for (i, w) in wantItems.enumerated() where i < out.cards.count {
                    XCTAssertEqual(out.cards[i].suit, w["suit"]?.asString, "\(label) [\(i)]: suit")
                    XCTAssertEqual(out.cards[i].currentRank, w["currentRank"]?.asInt, "\(label) [\(i)]: rank")
                    XCTAssertEqual(out.cards[i].joker, w["joker"]?.asBool, "\(label) [\(i)]: joker")
                    XCTAssertEqual(out.cards[i].blank, w["blank"]?.asBool, "\(label) [\(i)]: blank")
                    XCTAssertEqual(out.cards[i].stickers.map(\.type), w["stickers"]?.stringArray ?? [],
                                   "\(label) [\(i)]: stickers")
                }
            } else {
                XCTAssertEqual(out.stickers, wantItems.compactMap(\.asString), "\(label): sticker ids")
            }
            XCTAssertEqual(c.nextCardId, f["nextCardIdAfter"]?.asInt, "\(label): nextCardId after")
        }
    }

    func testStoreCardMintsMatchWeb() {
        for f in Self.list("storeCards") {
            let seed = f["seed"]?.asInt ?? 0
            let deck = f["deck"]?.asString ?? "pink"
            let label = "storeCard seed=\(seed) deck=\(deck)"
            let c = campaign(deck: deck, tier: "regular", seed: seed)
            let rng = RNG(seed: UInt32(truncatingIfNeeded: seed) ^ 0x51ca5d)
            let want = f["cards"]?.asArray ?? []
            for (i, w) in want.enumerated() {
                guard let got = c.genStoreCard(rng) else { XCTFail("\(label)[\(i)]: nil card"); continue }
                XCTAssertEqual(got.id, w["id"]?.asInt, "\(label)[\(i)]: id")
                XCTAssertEqual(got.suit, w["suit"]?.asString, "\(label)[\(i)]: suit")
                XCTAssertEqual(got.currentRank, w["currentRank"]?.asInt, "\(label)[\(i)]: rank")
                XCTAssertEqual(got.joker, w["joker"]?.asBool, "\(label)[\(i)]: joker")
                XCTAssertEqual(got.stickers.map(\.type), w["stickers"]?.stringArray ?? [], "\(label)[\(i)]: stickers")
            }
        }
    }

    // MARK: - Serialize / restore

    func testSerializeRestoreRoundTripMatchesWeb() {
        for f in Self.list("roundTrips") {
            let seed = f["seed"]?.asInt ?? 0
            let deck = f["deck"]?.asString ?? "pink"
            let label = "roundTrip seed=\(seed) deck=\(deck)"
            let c = campaign(deck: deck, tier: "master", seed: seed)
            if let first = c.legalNextNodes().first { c.moveToNode(first.id) }
            c.addCoins(250)
            c.addRunScore(37)
            let blob = c.serialize()
            // The save shape must match the web's key set exactly, or a save
            // written on one platform loses fields on the other.
            XCTAssertEqual(blob.keys.sorted(), f["blobKeys"]?.stringArray ?? [], "\(label): save key set")

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
            XCTAssertEqual(c2.runMap?.nodes.count, after["mapNodeCount"]?.asInt, "\(label): regenerated map node count")
            XCTAssertEqual(c2.runMap?.totalRows, after["mapTotalRows"]?.asInt, "\(label): regenerated map rows")
        }
    }

    // MARK: - Layout

    func testLayoutForPilesMatchesWeb() {
        for f in Self.list("layouts") {
            let n = f["piles"]?.asInt ?? 0
            let l = CampaignLayout.layoutForPiles(n)
            XCTAssertEqual(l.cols, f["cols"]?.intArray ?? [], "layoutForPiles(\(n)): cols")
            XCTAssertEqual(l.piles, f["sum"]?.asInt, "layoutForPiles(\(n)): piles")
            XCTAssertEqual(l.rows, f["rows"]?.asInt, "layoutForPiles(\(n)): rows")
        }
    }
}
