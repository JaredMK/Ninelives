import XCTest
@testable import GameCore

/// THE GOLDEN RECORDER — rewrites `Fixtures/*.json` from GameCore's OWN
/// output. See GoldenSupport.swift for the contract; run it via `make golden`
/// (which drops the `.golden-record` flag — without it this suite skips, so
/// a normal test run can never overwrite the baseline).
///
/// Scenario/corpus INPUTS are preserved from the committed files (seeds,
/// scripts, parameter tables); every OUTPUT is re-captured live. To grow the
/// corpus: add an inputs-only entry to the JSON (or extend the matrices in
/// `recordCampaignFixtures`), run `make golden`, review the diff, commit.
final class GoldenRecorder: XCTestCase {

    func testRecordGoldenBaseline() throws {
        try XCTSkipUnless(Golden.isRecording,
                          "record mode is off — run `make golden` to regenerate the baseline")
        try recordSeedFixtures()
        try recordEngineTraces()
        try recordCampaignFixtures()
    }

    // MARK: - seed-fixtures.json (rng, codes, shuffles, economy, difficulty,
    //         generator corpus, data echo)

    private func recordSeedFixtures() throws {
        var root = try Golden.readRepo("seed-fixtures.json")
        root["generatedBy"] = .string("ios/Tests/GoldenRecorder.swift (GameCore is the source of truth)")

        // Sections below keep each entry's INPUT keys verbatim and rewrite
        // only the recorded output key(s).
        func rewrite(_ key: String, _ transform: (inout [String: JSONValue]) -> Void) {
            let entries = (root[key]?.asArray ?? []).map { v -> JSONValue in
                var o = v.asObject ?? [:]
                transform(&o)
                return .object(o)
            }
            root[key] = .array(entries)
        }

        rewrite("rng") { o in
            let seed = UInt32(truncatingIfNeeded: o["seed"]?.asInt ?? 0)
            let n = o["values"]?.asArray?.count ?? 24
            let rng = RNG(seed: seed)
            o["values"] = .array((0..<n).map { _ in .num(rng.next()) })
        }
        rewrite("seedCode") { o in
            let seed = UInt32(truncatingIfNeeded: o["seed"]?.asInt ?? 0)
            o["code"] = .string(SeedCode.encode(seed))
        }
        rewrite("seedCodeRejects") { o in
            let input = o["input"]?.asString ?? ""
            o["decoded"] = SeedCode.decode(input).map { .num(Int($0)) } ?? .null
        }
        rewrite("shuffle") { o in
            let seed = UInt32(truncatingIfNeeded: o["seed"]?.asInt ?? 0)
            let deck = DeckManager.create(DeckManager.buildStandardDeck(), rng: RNG(seed: seed))
            var order: [Int] = []
            while let c = deck.draw() { order.append(c.id) }
            o["order"] = .ints(order)
        }
        rewrite("zenShuffle") { o in
            let seed = UInt32(truncatingIfNeeded: o["seed"]?.asInt ?? 0)
            let suitCount = o["suitCount"]?.asInt ?? 4
            let deck = DeckManager.create(DeckManager.buildZenDeck(suitCount: suitCount), rng: RNG(seed: seed))
            var order: [Int] = []
            while let c = deck.draw() { order.append(c.id) }
            o["order"] = .ints(order)
        }
        let eco = Economy()
        rewrite("economy") { o in
            o["flat"] = .num(eco.dealFlat(stage: o["stage"]?.asInt ?? 0,
                                          rating: o["rating"]?.asInt ?? 0,
                                          isBoss: o["isBoss"]?.asBool ?? false))
        }
        rewrite("breakdown") { o in
            let s = o["stats"] ?? .object([:])
            var stats = PayoutStats()
            stats.won = s["won"]?.asBool ?? false
            stats.flat = s["flat"]?.asNumber ?? 0
            stats.stage = s["stage"]?.asInt ?? 0
            stats.rating = s["rating"]?.asInt ?? 0
            stats.aliveCount = s["aliveCount"]?.asInt ?? 0
            stats.minAliveCards = s["minAliveCards"]?.asInt ?? 0
            stats.extraCoinUnits = s["extraCoinUnits"]?.asInt ?? 0
            stats.pillarBonus = s["pillarBonus"]?.asNumber ?? 0
            stats.eventBonus = s["eventBonus"]?.asNumber ?? 0
            stats.ambush = s["ambush"]?.asBool ?? false
            let b = eco.breakdown(stats)
            o["out"] = .object(["total": .num(b.total), "product": .num(b.product),
                                "extraCoinBonus": .num(b.extraCoinBonus),
                                "extraCoinValue": .num(b.extraCoinValue)])
        }
        let map = RunMap()
        rewrite("bands") { o in
            map.setDifficultyTier(o["tier"]?.asString ?? "regular")
            let b = map.bandsFor(o["phase"]?.asInt ?? 0)
            o["stage"] = .array(b.stage.map { .num($0) })
            o["boss"] = .array(b.boss.map { .num($0) })
        }
        rewrite("difficultyScore") { o in
            map.setDifficultyTier(o["tier"]?.asString ?? "regular")
            o["score"] = .num(map.difficultyScore(targetD: o["targetD"]?.asNumber ?? 0,
                                                  phaseIndex: o["phase"]?.asInt,
                                                  isBoss: o["isBoss"]?.asBool ?? false))
        }
        rewrite("subsetPiles") { o in
            o["piles"] = .num(map.solveSubsetPiles(surviveCount: o["survive"]?.asInt ?? 0,
                                                   targetD: o["targetD"]?.asNumber ?? 0))
        }
        // The generator sections are a SEED CORPUS — the replay asserts the
        // generator's own promises (determinism, structure), never a node
        // dump — so the entries slim to their inputs.
        rewrite("stages") { o in o.removeValue(forKey: "stage") }
        rewrite("maps") { o in o.removeValue(forKey: "map") }

        // Data echo: the shipped registry surface, verbatim from GameData.
        let d = GameData.shared
        let C = RunMap().config
        root["dataEcho"] = .object([
            "storeSlots": .num(d.items.store.slots),
            "typeCap": .num(d.items.store.typeCap),
            "stickerIds": .strings(d.stickerTypes.ids),
            "pillarIds": .strings(d.pillarTypes.ids),
            "baseIds": .strings(d.baseTypes.ids),
            "samePowerIds": .strings(d.samePowerTypes.ids),
            "packIds": .strings(d.packTypes.ids),
            "cursedStickerIds": .strings(d.items.stickers.filter(\.cursed).map(\.id)),
            "genConfig": .object([
                "startDeckSize": .num(C.startDeckSize),
                "predictedRouteCards": .num(C.predictedRouteCards),
                "minRouteCards": .num(C.minRouteCards),
                "maxLightRouteCards": .num(C.maxLightRouteCards),
                "minPiles": .num(C.minPiles), "maxPiles": .num(C.maxPiles),
                "stores": .ints(C.stores), "rows": .ints(C.rows), "paths": .ints(C.paths),
                "lanes": .num(C.lanes), "attempts": .num(C.attempts),
                "relaxSteps": .num(C.relaxSteps), "seedLadderRungs": .num(C.seedLadderRungs),
                "mysteryTypeWeight": .num(C.mysteryTypeWeight),
                "dealsPerRouteMax": .num(C.dealsPerRouteMax),
                "preBossStoreRows": .num(C.preBossStoreRows),
                "packMax": .num(C.packMax), "relaxBandStep": .num(C.relaxBandStep),
                "structAttempts": .num(C.structAttempts),
            ]),
        ])

        try Golden.write(root, to: "seed-fixtures.json")
    }

    // MARK: - engine-traces.json (137 scripted deals, step-for-step)

    private func recordEngineTraces() throws {
        let old = try Golden.readRepo("engine-traces.json")
        let scenarios = (old["scenarios"]?.asArray ?? []).map { sc -> JSONValue in
            var o = sc.asObject ?? [:]
            o.removeValue(forKey: "events")   // never replayed — dead weight
            var trace: [JSONValue] = []
            let eng = TraceRunner.run(sc) { step, pile, call, eng in
                var snap = TraceSnapshot.fields(eng)
                if step >= 0 {
                    snap["pile"] = .maybeNum(pile)
                    snap["call"] = .maybeString(call?.rawValue)
                }
                trace.append(.object(snap))
            }
            o["baseRandom"] = TraceSnapshot.baseRandom(eng)
            o["trace"] = .array(trace)
            o["final"] = TraceSnapshot.final(eng)
            return .object(o)
        }
        try Golden.write([
            "generatedBy": .string("ios/Tests/GoldenRecorder.swift (GameCore is the source of truth)"),
            "scenarios": .array(scenarios),
        ], to: "engine-traces.json")
    }

    // MARK: - campaign-fixtures.json (starts, stores, mystery, packs,
    //         store cards, round-trips, layouts — the FULL iOS roster)

    private let seeds = [11, 4242, 777777, 3141592]
    private var decks: [String] {
        let preferred = ["pink", "mamma", "slyrex", "garden", "rocko"]
        let known = Set(GameData.shared.meta.deckRules.keys)
        return preferred.filter(known.contains)
            + known.subtracting(preferred).sorted()
    }
    /// The two shipping difficulty tiers (the deck-select ladder).
    private let tiers = ["regular", "legendary"]

    private func campaign(deck: String, tier: String, seed: Int) -> CampaignState {
        let c = CampaignState()
        c.setDeck(deck)
        c.setTier(tier)
        c.setSeedOverride(UInt32(truncatingIfNeeded: seed))
        c.reset()
        return c
    }

    private func recordCampaignFixtures() throws {
        var root: [String: JSONValue] = [
            "generatedBy": .string("ios/Tests/GoldenRecorder.swift (GameCore is the source of truth)"),
        ]

        // STARTS — every deck × tier × seed: the exact opening state.
        var starts: [JSONValue] = []
        for seed in seeds {
            for deck in decks {
                for tier in tiers {
                    let c = campaign(deck: deck, tier: tier, seed: seed)
                    starts.append(.object([
                        "seed": .num(seed), "deck": .string(deck), "tier": .string(tier),
                        "runSeed": .num(Int(c.runSeed)),
                        "exhibition": .bool(c.exhibition),
                        "ownedIds": .ints(c.getRunDeck().map(\.id)),
                        "deckSize": .num(c.deckSize()),
                        "columnPillars": .array(c.columnPillars.map { .maybeString($0) }),
                        "columnBases": .array(c.columnBases.map { .maybeString($0) }),
                        "startCards": .array(c.getRunDeck().map { g in
                            .object(["id": .num(g.id), "suit": .string(g.suit),
                                     "currentRank": .num(g.currentRank),
                                     "originalRank": .num(g.originalRank),
                                     "joker": .bool(g.joker),
                                     "stickers": .strings(g.stickers.map(\.type))])
                        }),
                        "jokerBudget": .object(["cap": .num(c.jokerCapFor()),
                                                "committed": .num(c.jokersHeld()),
                                                "allowed": .bool(c.jokersAllowed())]),
                    ]))
                }
            }
        }
        root["starts"] = .array(starts)

        // STORES — a seed corpus (the replay asserts the shop's own rules);
        // the recorded nodePos pins the travel step it rolls from.
        var stores: [JSONValue] = []
        for seed in seeds {
            for deck in decks {
                let c = campaign(deck: deck, tier: "regular", seed: seed)
                if let first = c.legalNextNodes().first { c.moveToNode(first.id) }
                stores.append(.object(["seed": .num(seed), "deck": .string(deck),
                                       "nodePos": .maybeNum(c.nodePos)]))
            }
        }
        root["stores"] = .array(stores)

        // MYSTERY — the runSeed derivation per seed (the roll corpus is
        // enumerated by the replay itself).
        root["mystery"] = .array(seeds.map { seed in
            .object(["seed": .num(seed),
                     "runSeed": .num(Int(campaign(deck: "pink", tier: "regular", seed: seed).runSeed))])
        })

        // PACKS — every pack × deck × seed: reveal size + cards minted.
        var packs: [JSONValue] = []
        for seed in seeds {
            for deck in decks {
                for packId in GameData.shared.packTypes.ids {
                    let c = campaign(deck: deck, tier: "regular", seed: seed)
                    let idBefore = c.nextCardId
                    let kind = GameData.shared.packTypes.get(packId)?.kind ?? "?"
                    let out = c.revealPack(packId, rng: RNG(seed: UInt32(truncatingIfNeeded: seed) ^ 0xabcdef))
                    let count = kind == "card" ? out.cards.count : out.stickers.count
                    packs.append(.object(["seed": .num(seed), "deck": .string(deck),
                                          "packId": .string(packId), "kind": .string(kind),
                                          "count": .num(count),
                                          "minted": .num(c.nextCardId - idBefore)]))
                }
            }
        }
        root["packs"] = .array(packs)

        // STORE CARDS — a seed corpus for the individual-card mint rules.
        var storeCards: [JSONValue] = []
        for seed in seeds {
            for deck in decks {
                storeCards.append(.object(["seed": .num(seed), "deck": .string(deck)]))
            }
        }
        root["storeCards"] = .array(storeCards)

        // ROUND TRIPS — the save's EXACT key set (the schema law) + the
        // restored surface.
        var roundTrips: [JSONValue] = []
        for seed in [11, 4242] {
            for deck in decks {
                let tier = "legendary"
                let c = campaign(deck: deck, tier: tier, seed: seed)
                if let first = c.legalNextNodes().first { c.moveToNode(first.id) }
                c.addCoins(250)
                c.addRunScore(37)
                let blob = c.serialize()
                let c2 = CampaignState()
                let ok = c2.restore(blob)
                roundTrips.append(.object([
                    "seed": .num(seed), "deck": .string(deck), "tier": .string(tier),
                    "blobKeys": .strings(blob.keys.sorted()),
                    "ok": .bool(ok),
                    "after": .object([
                        "deckId": .string(c2.deckId),
                        "tier": .string(c2.difficultyTier),
                        "runSeed": .num(Int(c2.runSeed)),
                        "nodePos": .maybeNum(c2.nodePos),
                        "coins": .num(c2.coins),
                        "runScore": .num(c2.runScore),
                        "ownedIds": .ints(c2.getRunDeck().map(\.id)),
                        "deckSize": .num(c2.deckSize()),
                    ]),
                ]))
            }
        }
        root["roundTrips"] = .array(roundTrips)

        // LAYOUTS — the pile → column-split table.
        root["layouts"] = .array((1...14).map { n in
            let l = CampaignLayout.layoutForPiles(n)
            return .object(["piles": .num(n), "cols": .ints(l.cols),
                            "sum": .num(l.piles), "rows": .num(l.rows)])
        })

        try Golden.write(root, to: "campaign-fixtures.json")
    }
}
