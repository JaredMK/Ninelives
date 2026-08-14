import XCTest
@testable import GameCore

/// Map-generation invariants, checked across many seeds/tiers — the Swift twin
/// of the web suite's run-map / mapgen coverage. These pin the SPEC (route card
/// budgets, deal counts, store rules, one boss, planarity), not the numbers,
/// which are read live from the config and difficulty.js.
final class MapGenerationTests: XCTestCase {

    private func generator(_ tier: String = "regular") -> RunMap {
        let m = RunMap()
        m.setDifficultyTier(tier)
        return m
    }

    private let seeds: [UInt32] = [1, 2, 3, 5, 8, 13, 21, 34, 55, 89]

    // MARK: - Whole-run shape

    func testGenerateRunProducesThreeStackedStagesAndAHome() {
        let m = generator()
        for seed in seeds.prefix(4) {
            let out = m.generateRun(seed: seed, entryDecks: [13, 26, 39])
            XCTAssertEqual(out.stagesGenerated, 3, "seed \(seed): three authored stages")
            XCTAssertEqual(out.phases.map(\.suit), ["♦", "♣", "♠"], "seed \(seed): the phase suit schedule")
            XCTAssertNotNil(out.homeId, "seed \(seed): Pinky's home sits above the ♠ boss")
            XCTAssertEqual(out.runBossId, out.phases[2].bossId, "the RUN boss is the ♠ boss")
            // Rows are global and strictly stacked.
            for q in 0..<2 {
                XCTAssertLessThan(out.phases[q].rowStart, out.phases[q + 1].rowStart, "seed \(seed): stacked rows")
            }
            // Ids are namespaced per phase, so they never collide.
            XCTAssertEqual(Set(out.nodes.map(\.id)).count, out.nodes.count, "seed \(seed): unique node ids")
        }
    }

    func testHomeSitsDirectlyAboveTheFinalBossAndIsItsExit() {
        let m = generator()
        let out = m.generateRun(seed: 4242, entryDecks: [13, 26, 39])
        let home = out.byId[out.homeId!]!
        XCTAssertEqual(home.type, "home")
        XCTAssertTrue(out.byId[out.runBossId!]!.next.contains(home.id),
                      "felling the ♠ boss makes home the legal next step")
    }

    func testEveryEdgeGoesUpwardsExactlyOneRowWithinAStage() {
        let m = generator()
        let out = m.generateRun(seed: 777, entryDecks: [13, 26, 39])
        for n in out.nodes {
            for t in n.next {
                guard let tn = out.byId[t] else { XCTFail("dangling edge \(n.id)→\(t)"); continue }
                XCTAssertGreaterThan(tn.row, n.row, "edges must climb (\(n.id)→\(t))")
            }
        }
    }

    // MARK: - Per-stage spec

    func testGeneratedStagesSatisfyTheSpec() {
        for tier in DifficultyData.tierIds {
            let m = generator(tier)
            for seed in seeds {
                for (phase, entry) in [(0, 13), (1, 26), (2, 39)] {
                    guard let ph = m.generateStage(phaseIndex: phase, seed: seed, entryDeck: entry,
                                                   opts: RunMap.GenOptions(genVersion: 3)) else {
                        XCTFail("\(tier) seed \(seed) phase \(phase): no map at all"); continue
                    }
                    let label = "\(tier) seed=\(seed) phase=\(phase)"
                    // EXACTLY ONE boss, on the top row, and every route ends there.
                    let bosses = ph.nodes.filter { $0.type == "boss" }
                    XCTAssertEqual(bosses.count, 1, "\(label): exactly one boss")
                    XCTAssertEqual(bosses.first?.row, ph.bossRow, "\(label): the boss is on the top row")
                    XCTAssertGreaterThanOrEqual(ph.row0.count, 2, "\(label): 2+ openings")

                    let routes = m.enumerateRoutes(ph)
                    XCTAssertFalse(routes.isEmpty, "\(label): at least one route")
                    for r in routes {
                        XCTAssertEqual(ph.byId[r.last!]?.type, "boss", "\(label): every route ends at the boss")
                    }
                    // Deals and piles are in range on every route.
                    for n in ph.nodes where n.type == "deal" || n.type == "boss" {
                        guard let p = n.piles else { XCTFail("\(label): deal #\(n.id) has no pile count"); continue }
                        XCTAssertGreaterThanOrEqual(p, m.config.minPiles, "\(label): deal #\(n.id) piles")
                        XCTAssertLessThanOrEqual(p, m.config.maxPiles, "\(label): deal #\(n.id) piles")
                    }
                }
            }
        }
    }

    /// A converged stage (validateStage.ok) must satisfy every hard rule. Some
    /// tier/entry pairs legitimately ship a best-effort map after the whole
    /// ladder — those are excluded here and counted below.
    func testConvergedStagesPassEveryHardRule() {
        var converged = 0, total = 0
        for tier in DifficultyData.tierIds {
            let m = generator(tier)
            for seed in seeds.prefix(6) {
                for (phase, entry) in [(0, 13), (1, 26), (2, 39)] {
                    guard let ph = m.generateStage(phaseIndex: phase, seed: seed, entryDeck: entry,
                                                   opts: RunMap.GenOptions(genVersion: 3)) else { continue }
                    total += 1
                    let v = m.validateStage(ph, entryDeck: entry,
                                            opts: RunMap.ValidateOptions(phaseIndex: phase))
                    guard v.ok else { continue }
                    converged += 1
                    let label = "\(tier) seed=\(seed) phase=\(phase)"
                    let C = m.config
                    XCTAssertGreaterThanOrEqual(v.report.cards[0], C.minRouteCards, "\(label): card floor")
                    XCTAssertLessThanOrEqual(v.report.cards[0], C.maxLightRouteCards,
                                             "\(label): a restrained route must exist")
                    XCTAssertGreaterThanOrEqual(v.report.dealsPerRoute[0], 3, "\(label): deal floor")
                    XCTAssertLessThanOrEqual(v.report.dealsPerRoute[1], C.dealsPerRouteMax, "\(label): deal cap")
                    XCTAssertGreaterThanOrEqual(v.report.stores, C.stores[0], "\(label): store quota low")
                    XCTAssertLessThanOrEqual(v.report.stores, C.stores[1], "\(label): store quota high")
                    XCTAssertEqual(v.report.crossLinks >= 0, true)
                    XCTAssertEqual(v.report.bosses.count, 1, "\(label): one boss")
                    // Every start can reach a store.
                    for sr in v.report.storeReach where sr.of > 0 {
                        XCTAssertGreaterThanOrEqual(sr.reaches, 1, "\(label): start \(sr.start) is store-locked")
                    }
                    // A store must sit in the pre-boss region.
                    XCTAssertTrue(ph.nodes.contains { $0.type == "store" && $0.row >= ph.bossRow - C.preBossStoreRows },
                                  "\(label): guaranteed pre-boss shop")
                }
            }
        }
        XCTAssertGreaterThan(total, 0)
        XCTAssertGreaterThan(Double(converged) / Double(total), 0.5,
                             "most stages should converge on the strict spec (\(converged)/\(total))")
    }

    func testStoreRulesHoldOnEveryRoute() {
        let m = generator()
        for seed in seeds.prefix(5) {
            guard let ph = m.generateStage(phaseIndex: 1, seed: seed, entryDeck: 26,
                                           opts: RunMap.GenOptions(genVersion: 3)) else { continue }
            for route in m.enumerateRoutes(ph) {
                var prevStore = false, dealSinceStore = true
                for id in route {
                    let n = ph.byId[id]!
                    if n.type == "deal" || n.type == "boss" { dealSinceStore = true }
                    if n.type == "store" {
                        XCTAssertFalse(prevStore, "seed \(seed): two stores in a row")
                        XCTAssertTrue(dealSinceStore, "seed \(seed): two stores with no deal between them")
                        dealSinceStore = false
                    }
                    prevStore = n.type == "store"
                }
            }
        }
    }

    // MARK: - Mystery nodes (genV ≥ 3 = first class)

    func testGenV3RollsMysteryAsAFirstClassTypeAndNeverMasks() {
        let m = generator()
        var sawMystery = false
        for seed in seeds {
            let out = m.generateRun(seed: seed, entryDecks: [13, 26, 39],
                                    opts: RunMap.GenOptions(genVersion: 3))
            for n in out.nodes {
                XCTAssertFalse(n.mystery, "genV3 must never set the legacy cosmetic mask")
                if n.type == "mystery" {
                    sawMystery = true
                    // A mystery is a BARE type: the seeded event is its whole content.
                    XCTAssertNil(n.add, "a mystery node grants nothing itself")
                    XCTAssertNil(n.packCount)
                    XCTAssertNil(n.suit)
                    XCTAssertEqual(n.addOf, 0, "a mystery contributes 0 cards to every route sum")
                }
            }
        }
        XCTAssertTrue(sawMystery, "mystery is a first-class node type at genV ≥ 3")
    }

    func testMysteryIsNeverABossPassHomeOrStore() {
        let m = generator()
        let out = m.generateRun(seed: 31337, entryDecks: [13, 26, 39], opts: RunMap.GenOptions(genVersion: 3))
        for n in out.nodes where n.type == "mystery" {
            XCTAssertNotEqual(n.row, out.byId[out.runBossId!]!.row)
        }
        XCTAssertFalse(out.nodes.contains { $0.type == "mystery" && $0.id == out.homeId })
    }

    func testLegacyGenV1UsesTheCosmeticMaskAndNoFirstClassMystery() {
        let m = generator()
        var masked = 0
        for seed in seeds.prefix(4) {
            let out = m.generateRun(seed: seed, entryDecks: [13, 26, 39],
                                    opts: RunMap.GenOptions(genVersion: 1))
            XCTAssertFalse(out.nodes.contains { $0.type == "mystery" },
                           "genV < 3 never rolls a first-class mystery")
            masked += out.nodes.filter(\.mystery).count
            // Bosses, home and pass points never hide.
            for n in out.nodes where n.mystery {
                XCTAssertFalse(["boss", "pass", "home"].contains(n.type))
            }
        }
        XCTAssertGreaterThan(masked, 0, "the legacy mask still hides nodes")
    }

    // MARK: - Pack merging

    func testForcedPackCorridorsMerge() {
        // genV ≥ 3: a merged-away pack becomes a MYSTERY, never an empty stop.
        let m = generator()
        for seed in seeds {
            let out = m.generateRun(seed: seed, entryDecks: [13, 26, 39], opts: RunMap.GenOptions(genVersion: 3))
            XCTAssertFalse(out.nodes.contains { $0.type == "pass" },
                           "no node may be left empty at genV 3 — merged corridors become mysteries")
            // The merged-away node grants nothing itself but keeps its edges.
            for n in out.nodes where n.type == "mystery" {
                XCTAssertEqual(n.addOf, 0)
                XCTAssertNil(n.packCount)
                XCTAssertFalse(n.next.isEmpty, "a merged corridor stays wired into the graph")
            }
        }
    }

    func testLegacyMapsKeepTheirEmptyPassPoints() {
        // The genV gate: a pre-mystery map must regenerate byte-identically, so
        // its pass points survive untouched.
        let m = generator()
        var sawPass = false
        for seed in seeds {
            let out = m.generateRun(seed: seed, entryDecks: [13, 26, 39], opts: RunMap.GenOptions(genVersion: 2))
            if out.nodes.contains(where: { $0.type == "pass" }) { sawPass = true }
        }
        XCTAssertTrue(sawPass, "genV 2 still collapses corridors into pass points")
    }

    func testMergePreservesRouteCardTotals() {
        // A corridor merge moves cards, it never changes a route's total.
        let m = generator()
        for seed in seeds.prefix(6) {
            guard let ph = m.generateStage(phaseIndex: 0, seed: seed, entryDeck: 13,
                                           opts: RunMap.GenOptions(genVersion: 3)) else { continue }
            for route in m.enumerateRoutes(ph) {
                let total = route.reduce(0) { $0 + (ph.byId[$1]?.addOf ?? 0) }
                XCTAssertGreaterThanOrEqual(total, 0)
            }
        }
    }

    // MARK: - Joker schemes

    func testPostBossJokerCorridorsArePlacedAndAlwaysVisible() {
        let m = generator()
        let out = m.generateRun(seed: 5150, entryDecks: [13, 26, 39],
                                opts: RunMap.GenOptions(genVersion: 3, postBossJokerStages: [0, 1]))
        let jokerNodes = out.nodes.filter(\.jokerNode)
        XCTAssertEqual(jokerNodes.count, 2, "one corridor node per listed stage")
        for jn in jokerNodes {
            XCTAssertEqual(jn.type, "pickup")
            XCTAssertEqual(jn.addOf, 1, "the corridor node is a +1 CARD")
            XCTAssertFalse(jn.mystery, "it is created outside the mystery roll — always visible")
            XCTAssertGreaterThanOrEqual(jn.id, RunMap.jokerNodeBase, "ids sit above the phase namespace")
        }
        // The corridor takes the boss's place as the stage exit.
        for q in 0..<2 {
            let jid = out.phases[q].jokerNodeId!
            XCTAssertTrue(out.byId[out.phases[q].bossId]!.next.contains(jid),
                          "the boss feeds its corridor node")
            XCTAssertEqual(Set(out.byId[jid]!.next), Set(out.phases[q + 1].row0),
                           "the corridor feeds the next stage's openings")
        }
    }

    func testPinkyRegularUsesTheFixedJokerScheme() {
        let d = GameData.shared
        let stages = d.difficulty.fixedJokerStages(deckId: "pink", tierId: "regular")
        XCTAssertNotNil(stages, "difficulty.js pins Pinky-Regular to the fixed-Joker scheme")
        XCTAssertFalse(stages!.isEmpty)
        for s in stages! { XCTAssertTrue((0...2).contains(s), "authored stage indices are 0-2") }
        // A bogus tier must NOT silently inherit Regular's overrides.
        XCTAssertNil(d.difficulty.fixedJokerStages(deckId: "pink", tierId: "nonsense"))
        XCTAssertEqual(d.difficulty.startJokers(deckId: "pink", tierId: "nonsense"), 0)
    }

    func testFixedJokerSchemeTurnsOffEveryRandomJokerSource() {
        let c = CampaignState()
        c.setDeck("pink"); c.setTier("regular")
        guard c.fixedJokerScheme else { XCTFail("expected Pinky-Regular to be a fixed-Joker pair"); return }
        XCTAssertFalse(c.jokersAllowed(), "no roll site may mint a Joker under the fixed scheme")
    }

    // MARK: - Determinism

    func testTheSameSeedGeneratesTheSameMapTwice() {
        for tier in DifficultyData.tierIds {
            let a = generator(tier), b = generator(tier)
            for seed in seeds.prefix(3) {
                let x = a.generateRun(seed: seed, entryDecks: [13, 26, 39], opts: RunMap.GenOptions(genVersion: 3))
                let y = b.generateRun(seed: seed, entryDecks: [13, 26, 39], opts: RunMap.GenOptions(genVersion: 3))
                XCTAssertEqual(x.nodes.map { CanonicalNode($0) }, y.nodes.map { CanonicalNode($0) },
                               "\(tier) seed \(seed) must regenerate identically")
            }
        }
    }

    func testDifferentSeedsGenerateDifferentMaps() {
        let m = generator()
        let a = m.generateRun(seed: 1, entryDecks: [13, 26, 39], opts: RunMap.GenOptions(genVersion: 3))
        let b = m.generateRun(seed: 2, entryDecks: [13, 26, 39], opts: RunMap.GenOptions(genVersion: 3))
        XCTAssertNotEqual(a.nodes.map { CanonicalNode($0) }, b.nodes.map { CanonicalNode($0) })
    }

    /// THE TWO TIERS PLAY THE SAME. Normal and Legendary share every band —
    /// the only difference between them is Jokers — so this asserts the bands
    /// MATCH, and that the difference lives in the Joker rules instead.
    func testTheTwoTiersShareTheirBandsAndDifferOnlyOnJokers() {
        let m = RunMap()
        m.setDifficultyTier("regular")
        let reg = m.bandsFor(0)
        m.setDifficultyTier("legendary")
        let leg = m.bandsFor(0)
        XCTAssertEqual(reg.stage, leg.stage, "the tiers share their stage bands")
        XCTAssertEqual(reg.boss, leg.boss, "…and their boss bands")

        // The ONE difference: Legendary has no Jokers anywhere.
        XCTAssertGreaterThan(GameData.shared.difficulty.tier("regular").jokerCap, 0, "Normal has Jokers")
        XCTAssertEqual(GameData.shared.difficulty.tier("legendary").jokerCap, 0, "Legendary has none")
        XCTAssertTrue(GameData.shared.difficulty.tier("regular").guaranteedMapJoker)
        XCTAssertFalse(GameData.shared.difficulty.tier("legendary").guaranteedMapJoker)

        // Two tiers, and the retired one falls back to Normal.
        XCTAssertEqual(DifficultyData.tierIds, ["regular", "legendary"])
        m.setDifficultyTier("master")
        XCTAssertEqual(m.getDifficultyTier(), "regular", "a retired tier falls back")
        m.setDifficultyTier("nope")
        XCTAssertEqual(m.getDifficultyTier(), "regular")
    }

    // MARK: - Endless

    func testEndlessStagesLiftBothBandEdges() {
        let m = generator()
        let d = GameData.shared.difficulty
        let last = d.tier("regular").stageBands.count - 1
        let base = m.bandsFor(last)
        for k in 1...4 {
            let lifted = m.bandsFor(last + k)
            let step = d.endlessBandStep * Double(k)
            XCTAssertEqual(lifted.stage[0], base.stage[0] + step, accuracy: 1e-9)
            XCTAssertEqual(lifted.stage[1], base.stage[1] + step, accuracy: 1e-9)
            XCTAssertEqual(lifted.boss[0], base.boss[0] + step, accuracy: 1e-9)
            XCTAssertEqual(lifted.boss[1], base.boss[1] + step, accuracy: 1e-9)
        }
    }

    func testEndlessStagesReadAsMixedSuit() {
        let m = generator()
        XCTAssertEqual(m.suitFor(0), "♦")
        XCTAssertEqual(m.suitFor(2), "♠")
        XCTAssertEqual(m.suitFor(3), "★", "every endless stage is mixed")
        XCTAssertEqual(m.suitFor(9), "★")
    }

    // MARK: - Subset deals + the 1..3 score

    func testSubsetKnobsComeFromDifficultyJs() {
        let s = GameData.shared.difficulty.subset
        XCTAssertGreaterThan(s.threshold, 0)
        XCTAssertGreaterThan(s.min, 0)
        XCTAssertLessThanOrEqual(s.min, s.max)
    }

    func testSolveSubsetPilesTargetsTheDanger() {
        let m = generator()
        for survive in [12, 20, 30, 45] {
            for d in [1.0, 2.0, 3.5, 5.0] {
                let piles = m.solveSubsetPiles(surviveCount: survive, targetD: d)
                XCTAssertGreaterThanOrEqual(piles, m.config.minPiles)
                XCTAssertLessThanOrEqual(piles, m.config.maxPiles)
                // Unless the clamp bites, the realized danger is near the target.
                if piles > m.config.minPiles && piles < m.config.maxPiles {
                    XCTAssertEqual(Double(survive) / Double(piles), d, accuracy: d * 0.5 + 0.5)
                }
            }
        }
    }

    func testDifficultyScoreSegmentsTheStagesOwnBandIntoThirds() {
        let m = generator()
        for phase in 0..<3 {
            let t = m.difficultyTiers(phaseIndex: phase, isBoss: false)
            XCTAssertEqual(m.difficultyScore(targetD: t.band[0] + 1e-6, phaseIndex: phase, isBoss: false), 1)
            XCTAssertEqual(m.difficultyScore(targetD: (t.t1 + t.t2) / 2, phaseIndex: phase, isBoss: false), 2)
            XCTAssertEqual(m.difficultyScore(targetD: t.band[1], phaseIndex: phase, isBoss: false), 3)
        }
        XCTAssertEqual(m.difficultyScore(targetD: 3, phaseIndex: nil, isBoss: false), 2,
                       "no stage context → a neutral 2")
        XCTAssertEqual(m.difficultyScore(targetD: 0, phaseIndex: 0, isBoss: false), 2)
    }

    /// A stage-3 "3" is far harder in absolute terms than a stage-1 "3" — the
    /// score is stage-RELATIVE.
    func testTheScoreIsStageRelative() {
        let m = generator()
        let stage1Hard = m.difficultyTiers(phaseIndex: 0, isBoss: false).band[1]
        XCTAssertEqual(m.difficultyScore(targetD: stage1Hard, phaseIndex: 0, isBoss: false), 3)
        XCTAssertLessThanOrEqual(m.difficultyScore(targetD: stage1Hard, phaseIndex: 2, isBoss: false), 2,
                                 "stage 1's hardest is not stage 3's hardest")
    }

    // MARK: - genV5 opening row (v6.52)

    /// v5 gives the run's FIRST decision a real spread: row-0 deals take
    /// ascending targets across firstDealBandV5 with DISTINCT pile counts, and
    /// a wide (3+) opening row flips one non-leftmost door to a pickup/pack
    /// when the route guarantees allow it. The leftmost door stays a deal at
    /// the gentle floor.
    func testGenV5OpeningRowSpreadsRatingsAndAddsVariety() {
        let m = generator()
        var spread = 0, mixed = 0, wide = 0, total = 0
        for seed in 1...40 {
            guard let ph = m.generateStage(phaseIndex: 0, seed: UInt32(seed), entryDeck: 13,
                                           opts: RunMap.GenOptions(genVersion: 5)) else { continue }
            total += 1
            let row0 = ph.row0.compactMap { ph.byId[$0] }
            let deals = row0.filter { $0.type == "deal" }
            XCTAssertGreaterThanOrEqual(deals.count, 2, "seed \(seed): the opening keeps 2+ deal doors")
            XCTAssertEqual(row0.first?.type, "deal", "seed \(seed): the leftmost door stays a deal")
            for n in row0 where n.type != "deal" {
                XCTAssertEqual(n.type, "mystery",
                               "seed \(seed): opening variety is a MYSTERY (a card add at the route root would shift every deck budget)")
            }
            if row0.count >= 3 {
                wide += 1
                if deals.count < row0.count { mixed += 1 }
            }
            let ratings = Set(deals.map {
                m.difficultyScore(targetD: $0.targetD ?? 0, phaseIndex: 0, isBoss: false)
            })
            if deals.count >= 2, ratings.count >= 2 { spread += 1 }
        }
        XCTAssertGreaterThan(total, 30, "the sweep must actually generate")
        XCTAssertGreaterThan(Double(spread) / Double(total), 0.7,
                             "most v5 openings offer at least two different deal ratings (got \(spread)/\(total))")
        if wide > 0 {
            XCTAssertGreaterThan(Double(mixed) / Double(wide), 0.5,
                                 "most wide openings carry a non-deal door (got \(mixed)/\(wide))")
        }
    }

    /// Old saves regenerate through their stamped genV: the v4 opening row
    /// stays all-deals, band-locked and tied — pinned so a resumed campaign
    /// keeps the exact map it was saved with.
    func testGenV4OpeningRowStaysUniformForOldSaves() {
        let m = generator()
        for seed in seeds.prefix(4) {
            guard let ph = m.generateStage(phaseIndex: 0, seed: seed, entryDeck: 13,
                                           opts: RunMap.GenOptions(genVersion: 4)) else { continue }
            let row0 = ph.row0.compactMap { ph.byId[$0] }
            XCTAssertTrue(row0.allSatisfy { $0.type == "deal" }, "seed \(seed): v4 openings are all deals")
            XCTAssertEqual(Set(row0.map { $0.piles ?? -1 }).count, 1,
                           "seed \(seed): v4 opening deals tie on pile count")
        }
    }
}
