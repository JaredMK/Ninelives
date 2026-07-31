import XCTest
@testable import GameCore

/// CROSS-IMPLEMENTATION SEED TESTS.
///
/// Every assertion here compares Swift against output captured from the REAL web
/// engine. If one fails, the same seed no longer plays the same climb on web and
/// iOS — which is the one thing Phase 1 must guarantee.
final class SeedFixtureTests: XCTestCase {

    // MARK: - mulberry32

    func testRNGStreamsAreByteIdentical() {
        let streams = Fixtures.array("rng")
        XCTAssertFalse(streams.isEmpty, "no rng fixtures")
        for s in streams {
            let seed = UInt32(truncatingIfNeeded: s["seed"]?.int ?? 0)
            let expected = s["values"]?.doubleArray ?? []
            let rng = RNG(seed: seed)
            for (i, want) in expected.enumerated() {
                let got = rng.next()
                XCTAssertEqual(got, want, "mulberry32(\(seed)) draw #\(i): got \(got), web says \(want)")
            }
        }
    }

    func testRNGIsWithinUnitInterval() {
        let rng = RNG(seed: 0xDEADBEEF)
        for _ in 0..<20000 {
            let v = rng.next()
            XCTAssertGreaterThanOrEqual(v, 0)
            XCTAssertLessThan(v, 1)
        }
    }

    // MARK: - SeedCode

    func testSeedCodeMatchesWeb() {
        for f in Fixtures.array("seedCode") {
            let seed = UInt32(truncatingIfNeeded: f["seed"]?.int ?? 0)
            let code = f["code"]?.asString ?? ""
            XCTAssertEqual(SeedCode.encode(seed), code, "encode(\(seed))")
            XCTAssertEqual(SeedCode.decode(code), seed, "decode(\(code))")
        }
    }

    func testSeedCodeRejectsMatchWeb() {
        for f in Fixtures.array("seedCodeRejects") {
            let input = f["input"]?.asString ?? ""
            let expected = f["decoded"]
            let got = SeedCode.decode(input)
            if expected == nil || expected!.isNull {
                XCTAssertNil(got, "decode(\"\(input)\") should be nil, got \(String(describing: got))")
            } else {
                XCTAssertEqual(got.map { Int($0) }, expected!.int, "decode(\"\(input)\")")
            }
        }
    }

    // MARK: - Deck shuffle

    func testSeededShuffleMatchesWeb() {
        for f in Fixtures.array("shuffle") {
            let seed = UInt32(truncatingIfNeeded: f["seed"]?.int ?? 0)
            let expected = f["order"]?.intArray ?? []
            let deck = DeckManager.create(DeckManager.buildStandardDeck(), rng: RNG(seed: seed))
            var order: [Int] = []
            while let c = deck.draw() { order.append(c.id) }
            XCTAssertEqual(order, expected, "shuffle order for seed \(seed)")
        }
    }

    func testZenShuffleMatchesWeb() {
        for f in Fixtures.array("zenShuffle") {
            let seed = UInt32(truncatingIfNeeded: f["seed"]?.int ?? 0)
            let suitCount = f["suitCount"]?.int ?? 4
            let expected = f["order"]?.intArray ?? []
            let deck = DeckManager.create(DeckManager.buildZenDeck(suitCount: suitCount), rng: RNG(seed: seed))
            var order: [Int] = []
            while let c = deck.draw() { order.append(c.id) }
            XCTAssertEqual(order, expected, "zen(\(suitCount)) shuffle order")
        }
    }

    // MARK: - Economy

    func testDealFlatMatchesWeb() {
        let eco = Economy()
        for f in Fixtures.array("economy") {
            let stage = f["stage"]?.int ?? 0
            let rating = f["rating"]?.int ?? 0
            let isBoss = f["isBoss"]?.asBool ?? false
            let want = f["flat"]?.asNumber ?? 0
            XCTAssertEqual(eco.dealFlat(stage: stage, rating: rating, isBoss: isBoss), want,
                           "dealFlat(stage: \(stage), rating: \(rating), boss: \(isBoss))")
        }
    }

    func testBreakdownMatchesWeb() {
        let eco = Economy()
        for f in Fixtures.array("breakdown") {
            guard let s = f["stats"], let out = f["out"] else { continue }
            var stats = PayoutStats()
            stats.won = s["won"]?.asBool ?? false
            stats.flat = s["flat"]?.asNumber ?? 0
            stats.stage = s["stage"]?.int ?? 0
            stats.rating = s["rating"]?.int ?? 0
            stats.aliveCount = s["aliveCount"]?.int ?? 0
            stats.minAliveCards = s["minAliveCards"]?.int ?? 0
            stats.extraCoinUnits = s["extraCoinUnits"]?.int ?? 0
            stats.pillarBonus = s["pillarBonus"]?.asNumber ?? 0
            stats.eventBonus = s["eventBonus"]?.asNumber ?? 0
            stats.ambush = s["ambush"]?.asBool ?? false
            let b = eco.breakdown(stats)
            XCTAssertEqual(b.total, out["total"]?.asNumber ?? -1, "breakdown total")
            XCTAssertEqual(b.product, out["product"]?.int ?? -1, "breakdown product")
            XCTAssertEqual(b.extraCoinBonus, out["extraCoinBonus"]?.asNumber ?? -1, "extraCoinBonus")
            XCTAssertEqual(b.extraCoinValue, out["extraCoinValue"]?.asNumber ?? -1, "extraCoinValue")
        }
    }

    // MARK: - Difficulty-derived generator surface

    func testBandsForMatchWeb() {
        let map = RunMap()
        for f in Fixtures.array("bands") {
            map.setDifficultyTier(f["tier"]?.asString ?? "regular")
            let p = f["phase"]?.int ?? 0
            let b = map.bandsFor(p)
            XCTAssertEqual(b.stage, f["stage"]?.doubleArray ?? [], "stage band \(f["tier"]?.asString ?? "") p\(p)")
            XCTAssertEqual(b.boss, f["boss"]?.doubleArray ?? [], "boss band \(f["tier"]?.asString ?? "") p\(p)")
        }
    }

    func testDifficultyScoreMatchesWeb() {
        let map = RunMap()
        for f in Fixtures.array("difficultyScore") {
            map.setDifficultyTier(f["tier"]?.asString ?? "regular")
            let got = map.difficultyScore(targetD: f["targetD"]?.asNumber ?? 0,
                                          phaseIndex: f["phase"]?.int,
                                          isBoss: f["isBoss"]?.asBool ?? false)
            XCTAssertEqual(got, f["score"]?.int ?? -1,
                           "difficultyScore(\(f["targetD"]?.asNumber ?? 0), p\(f["phase"]?.int ?? -1))")
        }
    }

    func testSolveSubsetPilesMatchesWeb() {
        let map = RunMap()
        for f in Fixtures.array("subsetPiles") {
            let got = map.solveSubsetPiles(surviveCount: f["survive"]?.int ?? 0,
                                           targetD: f["targetD"]?.asNumber ?? 0)
            XCTAssertEqual(got, f["piles"]?.int ?? -1,
                           "solveSubsetPiles(\(f["survive"]?.int ?? 0), \(f["targetD"]?.asNumber ?? 0))")
        }
    }

    // MARK: - Single-stage generation

    func testGenerateStageMatchesWeb() {
        let map = RunMap()
        var checked = 0
        for f in Fixtures.array("stages") {
            let seed = UInt32(truncatingIfNeeded: f["seed"]?.int ?? 0)
            let tier = f["tier"]?.asString ?? "regular"
            let phase = f["phase"]?.int ?? 0
            let entry = f["entry"]?.int ?? 13
            map.setDifficultyTier(tier)
            let ph = map.generateStage(phaseIndex: phase, seed: seed, entryDeck: entry,
                                       opts: RunMap.GenOptions(genVersion: 3))
            guard let want = f["stage"], !want.isNull else {
                XCTAssertNil(ph, "stage(\(seed), \(tier), p\(phase)) should be nil")
                continue
            }
            guard let ph else {
                XCTFail("stage(\(seed), \(tier), p\(phase), entry \(entry)) generated nil; web produced a map")
                continue
            }
            let label = "stage seed=\(seed) tier=\(tier) phase=\(phase) entry=\(entry)"
            XCTAssertEqual(ph.rows, want["rows"]?.int ?? -1, "\(label): rows")
            XCTAssertEqual(ph.bossRow, want["bossRow"]?.int ?? -1, "\(label): bossRow")
            XCTAssertEqual(ph.bossId, want["bossId"]?.int ?? -1, "\(label): bossId")
            XCTAssertEqual(ph.row0, want["row0"]?.intArray ?? [], "\(label): row0")
            let got = ph.nodes.map(CanonicalNode.init)
            let expected = (want["nodes"]?.asArray ?? []).map(CanonicalNode.init(fixture:))
            assertNodesEqual(got, expected, label: label)
            checked += 1
        }
        XCTAssertGreaterThan(checked, 0, "no stage fixtures were exercised")
    }

    // MARK: - Whole-run maps (the headline)

    func testGenerateRunMatchesWeb() {
        let map = RunMap()
        var checked = 0
        for f in Fixtures.array("maps") {
            let seed = UInt32(truncatingIfNeeded: f["seed"]?.int ?? 0)
            let deck = f["deck"]?.asString ?? "pink"
            let tier = f["tier"]?.asString ?? "regular"
            let entries = f["entries"]?.intArray ?? []
            let stages = f["opts"]?["postBossJokerStages"]?.intArray ?? []
            let genV = f["opts"]?["genVersion"]?.int ?? 3
            map.setDifficultyTier(tier)
            let out = map.generateRun(seed: seed, entryDecks: entries.map { Optional($0) },
                                      opts: RunMap.GenOptions(genVersion: genV, postBossJokerStages: stages))
            guard let want = f["map"] else { continue }
            let label = "run seed=\(seed) deck=\(deck) tier=\(tier)"
            XCTAssertEqual(out.totalRows, want["totalRows"]?.int ?? -1, "\(label): totalRows")
            XCTAssertEqual(out.stagesGenerated, want["stagesGenerated"]?.int ?? -1, "\(label): stagesGenerated")
            XCTAssertEqual(out.homeId, want["homeId"]?.int, "\(label): homeId")
            XCTAssertEqual(out.runBossId, want["runBossId"]?.int, "\(label): runBossId")
            XCTAssertEqual(out.row0, want["row0"]?.intArray ?? [], "\(label): row0")

            let wantPhases = want["phases"]?.asArray ?? []
            XCTAssertEqual(out.phases.count, wantPhases.count, "\(label): phase count")
            for (i, wp) in wantPhases.enumerated() where i < out.phases.count {
                let gp = out.phases[i]
                XCTAssertEqual(gp.phase, wp["phase"]?.int ?? -1, "\(label) phase[\(i)]: index")
                XCTAssertEqual(gp.suit, wp["suit"]?.asString ?? "", "\(label) phase[\(i)]: suit")
                XCTAssertEqual(gp.bossId, wp["bossId"]?.int ?? -1, "\(label) phase[\(i)]: bossId")
                XCTAssertEqual(gp.bossIds, wp["bossIds"]?.intArray ?? [], "\(label) phase[\(i)]: bossIds")
                XCTAssertEqual(gp.row0, wp["row0"]?.intArray ?? [], "\(label) phase[\(i)]: row0")
                XCTAssertEqual(gp.rowStart, wp["rowStart"]?.int ?? -1, "\(label) phase[\(i)]: rowStart")
                XCTAssertEqual(gp.rows, wp["rows"]?.int ?? -1, "\(label) phase[\(i)]: rows")
                XCTAssertEqual(gp.jokerNodeId, wp["jokerNodeId"]?.int, "\(label) phase[\(i)]: jokerNodeId")
            }
            let got = out.nodes.map(CanonicalNode.init)
            let expected = (want["nodes"]?.asArray ?? []).map(CanonicalNode.init(fixture:))
            assertNodesEqual(got, expected, label: label)
            checked += 1
        }
        XCTAssertGreaterThan(checked, 0, "no map fixtures were exercised")
    }

    // MARK: - Data echo

    func testDataSurfaceMatchesWeb() {
        let echo = Fixtures.object("dataEcho")
        let d = GameData.shared
        XCTAssertEqual(d.items.store.slots, echo["storeSlots"]?.int)
        XCTAssertEqual(d.items.store.typeCap, echo["typeCap"]?.int)
        XCTAssertEqual(d.stickerTypes.ids, echo["stickerIds"]?.stringArray ?? [])
        XCTAssertEqual(d.pillarTypes.ids, echo["pillarIds"]?.stringArray ?? [])
        XCTAssertEqual(d.baseTypes.ids, echo["baseIds"]?.stringArray ?? [])
        XCTAssertEqual(d.samePowerTypes.ids, echo["samePowerIds"]?.stringArray ?? [])
        XCTAssertEqual(d.packTypes.ids, echo["packIds"]?.stringArray ?? [])
        XCTAssertEqual(d.items.stickers.filter(\.cursed).map(\.id),
                       echo["cursedStickerIds"]?.stringArray ?? [])
        let gc = echo["genConfig"]!
        let C = RunMap().config
        XCTAssertEqual(C.startDeckSize, gc["startDeckSize"]?.int)
        XCTAssertEqual(C.predictedRouteCards, gc["predictedRouteCards"]?.int)
        XCTAssertEqual(C.minRouteCards, gc["minRouteCards"]?.int)
        XCTAssertEqual(C.maxLightRouteCards, gc["maxLightRouteCards"]?.int)
        XCTAssertEqual(C.minPiles, gc["minPiles"]?.int)
        XCTAssertEqual(C.maxPiles, gc["maxPiles"]?.int)
        XCTAssertEqual(C.stores, gc["stores"]?.intArray ?? [])
        XCTAssertEqual(C.rows, gc["rows"]?.intArray ?? [])
        XCTAssertEqual(C.paths, gc["paths"]?.intArray ?? [])
        XCTAssertEqual(C.lanes, gc["lanes"]?.int)
        XCTAssertEqual(C.attempts, gc["attempts"]?.int)
        XCTAssertEqual(C.relaxSteps, gc["relaxSteps"]?.int)
        XCTAssertEqual(C.seedLadderRungs, gc["seedLadderRungs"]?.int)
        XCTAssertEqual(C.mysteryTypeWeight, gc["mysteryTypeWeight"]?.asNumber)
        XCTAssertEqual(C.dealsPerRouteMax, gc["dealsPerRouteMax"]?.int)
        XCTAssertEqual(C.preBossStoreRows, gc["preBossStoreRows"]?.int)
        XCTAssertEqual(C.packMax, gc["packMax"]?.int)
        XCTAssertEqual(C.relaxBandStep, gc["relaxBandStep"]?.asNumber)
        XCTAssertEqual(C.structAttempts, gc["structAttempts"]?.int)
    }

    // MARK: - Helpers

    /// Compare node lists with a readable first-divergence message.
    private func assertNodesEqual(_ got: [CanonicalNode], _ expected: [CanonicalNode],
                                  label: String, file: StaticString = #filePath, line: UInt = #line) {
        if got == expected { return }
        if got.count != expected.count {
            XCTFail("\(label): node count \(got.count) ≠ web \(expected.count)", file: file, line: line)
        }
        for i in 0..<Swift.min(got.count, expected.count) where got[i] != expected[i] {
            XCTFail("\(label): node[\(i)] diverges\n     swift: \(got[i])\n       web: \(expected[i])",
                    file: file, line: line)
            return
        }
    }
}
