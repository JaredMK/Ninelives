import XCTest
@testable import GameCore

/// UNLOCK SYSTEM AUDIT (mega-batch §7) — registry-driven invariants over the
/// redesigned items.js unlock table. No pinned thresholds: every assertion is
/// a DESIGN RULE the data must keep obeying as counts are retuned.
final class UnlockSystemTests: XCTestCase {
    private let data = GameData.shared

    private func fresh() -> (store: MemoryStore, stats: Stats, zen: ZenStats, unlocks: ItemUnlocks) {
        let store = MemoryStore()
        let stats = Stats(store: store)
        let zen = ZenStats(store: store, ids: DifficultyData.zenIds)
        return (store, stats, zen, ItemUnlocks(store: store, data: data, stats: stats, zenStats: zen))
    }

    private var allGroups: [(String, [ItemDef])] {
        [("stickers", data.items.stickers), ("pillars", data.items.pillars),
         ("bases", data.items.bases), ("samePowers", data.items.samePowers),
         ("packs", data.items.packs)]
    }
    private var allDefs: [ItemDef] { allGroups.flatMap(\.1) }
    private var gated: [ItemDef] { allDefs.filter { $0.unlock != nil } }

    /// Stats a FRESH SAVE (Pinky only, zero progress, no items) can move with
    /// core play alone — no shop item required. Each entry is justified by a
    /// real, always-available source:
    ///   dealsSurvived/runsPlayed/runsWon/bossesBeaten/perfectDeals/
    ///   dealsWonRegular — playing/clearing deals (GameFlowController.onRunEnd);
    ///   dealsWonLegendary — the Legendary tier is selectable from the start;
    ///   endlessStagesReached — offered after any run win (continue = endless);
    ///   coinsEarnedLifetime/bestCoinsInClimb/bestCampaignScore — every climb;
    ///   pilesLost/earlyLosses — losing is always available;
    ///   jokersPlayed — Pinky-Regular's two guaranteed corridor Jokers;
    ///   removalsUsed — the store's permanent Purge slot (default-ON, asserted
    ///   below) plus mystery freeRemoval;
    ///   pinkyTipsSeen — the map's bottom-tip easter egg (MapViewController);
    ///   ambushesWon — mystery ambush deals;
    ///   hearts/diamonds/clubs/spadesPlayed — suits land every single deal;
    ///   zen* — Zen mode is open from the first session (its ladder included).
    private static let coreMovableStats: Set<String> = [
        "dealsSurvived", "runsPlayed", "runsWon", "bossesBeaten",
        "endlessStagesReached", "coinsEarnedLifetime", "bestCoinsInClimb",
        "bestCampaignScore", "pilesLost", "perfectDeals", "dealsWonRegular",
        "dealsWonLegendary", "jokersPlayed", "removalsUsed", "pinkyTipsSeen",
        "ambushesWon", "earlyLosses",
        "heartsPlayed", "diamondsPlayed", "clubsPlayed", "spadesPlayed",
        "zenGamesPlayed", "zenEasyWon", "zenMediumWon", "zenHardWon",
    ]

    /// Every unlock counter with a VERIFIED live bump/write site in the app
    /// (grep-checked for this audit — the site is listed beside each name).
    /// `dealsWonMaster` is deliberately ABSENT: the Master tier is retired and
    /// GameFlowController's per-tier switch writes only legendary/default, so
    /// the counter can never move — no item may gate on it.
    private static let verifiedBumpableStats: Set<String> = [
        "dealsSurvived",         // GameFlowController.onRunEnd: runsCleared += 1
        "runsPlayed",            // DealController: gamesPlayed += 1 on first guess
        "runsWon",               // GameFlowController: campaignsWon += 1
        "bossesBeaten",          // GameFlowController: bump("bossesBeaten")
        "endlessStagesReached",  // GameFlowController: bestEndless = max(...)
        "coinsEarnedLifetime",   // GameFlowController: lifetimeDopamine += ...
        "bestCoinsInClimb",      // GameFlowController: bestCoinsInClimb = max(...)
        "bestCampaignScore",     // GameFlowController.foldBestScore
        "cardsBuried",           // DealController: bump("cardsBuried", count)
        "samesCalled",           // DealController.handleResolved deltas
        "correctSames",          // DealController.handleResolved deltas
        "jokersPlayed",          // DealController.handleResolved deltas
        "stickersApplied",       // CampaignState.applySticker / applyStickerDirect
        "pillarsPlaced",         // CampaignState: bump("pillarsPlaced")
        "basesPlaced",           // CampaignState: bump("basesPlaced")
        "removalsUsed",          // CampaignState: bump("removalsUsed")
        "pilesLost",             // DealController: bump("pilesLost")
        "heartsPlayed", "diamondsPlayed", "clubsPlayed", "spadesPlayed",
                                 // GameFlowController.onRunEnd: suitsLanded fold
        "perfectDeals",          // GameFlowController.onRunEnd
        "dealsWonRegular",       // GameFlowController.onRunEnd (default tier arm)
        "dealsWonLegendary",     // GameFlowController.onRunEnd ("legendary" arm)
        "pinkyTipsSeen",         // MapViewController: bump("pinkyTipsSeen")
        "ambushesWon",           // GameFlowController: ambushesWon += 1
        "earlyLosses",           // GameFlowController: earlyLosses += 1
        "zenGamesPlayed", "zenEasyWon", "zenMediumWon", "zenHardWon",
                                 // ZenStats (games/wins per difficulty)
    ]

    /// Behavior/effect keys that BURY cards (feed `cardsBuried`), verified
    /// against the engine dispatch (buryTribute / maybeStickerActions /
    /// suitDig / stickerHarvest / linkBury / lastResort).
    private static let burySources: Set<String> = [
        "quickBury", "snowball", "clubSnob", "clubRoots",       // stickers
        "clubTribute", "streakTribute", "denseBury", "rankBury", // pillars
        "suitDig", "stickerHarvest", "lastResort",               // bases
        "linkBury",                                              // same-power
    ]

    private func isBurySource(_ d: ItemDef) -> Bool {
        Self.burySources.contains(d.behavior ?? "") || Self.burySources.contains(d.effect ?? "")
    }
    private func isDuplicateRankSource(_ d: ItemDef) -> Bool {
        // Same calls need duplicate ranks in the deck. Card packs mint extra
        // cards (duplicating ranks), and rank stickers move a card onto an
        // occupied rank.
        (d.kind == "card") || (d.kind == "rank")
    }

    // MARK: - (1) Reachability closure from a fresh save

    /// Every gated item must be obtainable starting from ONLY the ungated pool:
    /// movable stats grow as items unlock, unlocked items add new stat sources,
    /// repeat to a fixpoint. A gate on a stat the fixpoint can't move is a
    /// deadlock and fails here with the item named.
    func testEveryGatedItemIsReachableFromAFreshSave() {
        // The Purge slot must be ON by default or removalsUsed has no core source.
        XCTAssertTrue(CampaignState(store: MemoryStore()).removalSlotOn(),
                      "the store's Purge slot must default ON (removalsUsed's core source)")

        var movable = Self.coreMovableStats
        var obtainable = Set(allDefs.filter { $0.unlock == nil && !$0.cursed }.map(\.id))

        func recomputeMovable() {
            let pool = allDefs.filter { obtainable.contains($0.id) }
            let stickers = data.items.stickers.filter { obtainable.contains($0.id) && !$0.cursed }
            if !stickers.isEmpty { movable.insert("stickersApplied") }
            if data.items.pillars.contains(where: { obtainable.contains($0.id) }) { movable.insert("pillarsPlaced") }
            if data.items.bases.contains(where: { obtainable.contains($0.id) }) { movable.insert("basesPlaced") }
            if pool.contains(where: isBurySource) { movable.insert("cardsBuried") }
            if pool.contains(where: isDuplicateRankSource) {
                movable.insert("samesCalled"); movable.insert("correctSames")
            }
        }

        recomputeMovable()
        var grew = true
        while grew {
            grew = false
            for d in gated where !obtainable.contains(d.id) {
                if movable.contains(d.unlock!.stat) {
                    obtainable.insert(d.id)
                    grew = true
                }
            }
            recomputeMovable()
        }
        for d in gated {
            XCTAssertTrue(obtainable.contains(d.id),
                          "'\(d.id)' gates on '\(d.unlock!.stat)' which a fresh save can never move — deadlock")
        }
        // The documented chicken-and-egg guard: cardsBuried gates exist, so at
        // least one bury source must be UNGATED (Quick Bury is the seed —
        // items.js documents this on the entry itself).
        if gated.contains(where: { $0.unlock!.stat == "cardsBuried" }) {
            XCTAssertTrue(allDefs.contains { $0.unlock == nil && !$0.cursed && isBurySource($0) },
                          "cardsBuried gates exist but every bury source is itself gated")
        }
        // Same for the Same ladder: duplicate-rank sources must start ungated.
        if gated.contains(where: { ["samesCalled", "correctSames"].contains($0.unlock!.stat) }) {
            XCTAssertTrue(allDefs.contains { $0.unlock == nil && !$0.cursed && isDuplicateRankSource($0) },
                          "sames gates exist but every duplicate-rank source is gated")
        }
    }

    // MARK: - (2) No two gates are identical

    func testNoTwoGatedItemsShareAStatCountPair() {
        var seen: [String: String] = [:]
        for d in gated {
            let key = "\(d.unlock!.stat)@\(d.unlock!.count)"
            XCTAssertNil(seen[key],
                         "'\(d.id)' and '\(seen[key] ?? "")' share the identical gate \(key) — they would pop in the same breath")
            seen[key] = d.id
        }
    }

    // MARK: - (3) Starting variety

    /// Every class keeps ≥2 ungated, non-cursed starters (the store's class
    /// roll must never starve at zero stats — same contract the web suite pins).
    func testEveryClassKeepsStartingItems() {
        for (name, list) in allGroups {
            let starters = list.filter { $0.unlock == nil && !$0.cursed }
            XCTAssertGreaterThanOrEqual(starters.count, 2,
                                        "\(name): \(starters.count) starting item(s) — the class roll starves")
        }
    }

    // MARK: - (4) Thresholds are monotone (strictly distinct) within a stat

    /// Two items on the same counter must sit at DIFFERENT counts — the later
    /// one strictly higher — so a ladder drips instead of dumping.
    func testThresholdsAreStrictlyOrderedWithinEachStat() {
        var byStat: [String: [(String, Double)]] = [:]
        for d in gated { byStat[d.unlock!.stat, default: []].append((d.id, d.unlock!.count)) }
        for (stat, entries) in byStat {
            let counts = entries.map(\.1)
            XCTAssertEqual(Set(counts).count, counts.count,
                           "\(stat): duplicate thresholds in \(entries.map { "\($0.0)@\(Int($0.1))" }.sorted())")
        }
    }

    // MARK: - (5) Legal vocabulary + live counters only

    func testEveryGateUsesALegalAndActuallyBumpedStat() {
        let legal = Set(data.meta.itemUnlockStats)
        for d in gated {
            let stat = d.unlock!.stat
            XCTAssertTrue(legal.contains(stat),
                          "'\(d.id)': unlock.stat '\(stat)' is outside meta.itemUnlockStats")
            XCTAssertTrue(Self.verifiedBumpableStats.contains(stat),
                          "'\(d.id)': unlock.stat '\(stat)' has no verified bump site (dead counter?)")
            XCTAssertGreaterThan(d.unlock!.count, 0, "'\(d.id)': non-positive threshold")
        }
        // The retired Master tier's counter must stay unused until it has a
        // bump site again.
        XCTAssertFalse(gated.contains { $0.unlock!.stat == "dealsWonMaster" },
                       "dealsWonMaster has no bump site (Master tier retired) — no item may gate on it")
    }

    // MARK: - Plumbing: hints, toast dedup, persistence, rename migration

    /// The Collection's lock hints and the unlock toasts read the same
    /// condition data through ItemUnlocks.hint — every gated item must
    /// produce non-empty copy.
    func testEveryGatedItemHasHintCopy() {
        let (_, _, _, u) = fresh()
        for d in gated {
            XCTAssertFalse(u.hint(for: d).isEmpty, "'\(d.id)' (\(d.unlock!.stat)) renders no hint copy")
        }
    }

    /// Unlock state (the known-set) persists: a crossing pops once, then a
    /// RELOADED ItemUnlocks on the same store stays silent.
    func testKnownSetSurvivesAReload() {
        let (store, stats, zen, u) = fresh()
        stats.put(StatsRecord())
        u.primeKnown()
        guard let target = gated.first(where: { g in
            StatsRecord.unlockCounters.contains(g.unlock!.stat)
        }) else { return }
        var s = StatsRecord()
        s[target.unlock!.stat] = Int(target.unlock!.count)
        stats.put(s)
        XCTAssertTrue(u.checkNewUnlocks().contains { $0.id == target.id })
        let reloaded = ItemUnlocks(store: store, data: data, stats: stats, zenStats: zen)
        XCTAssertEqual(reloaded.checkNewUnlocks().count, 0,
                       "a reload must read the persisted known-set, not re-pop")
    }

    /// The v6.67 smith/lammy → garden/rocko rename never touches the item
    /// unlock blob (item ids are stable across the rename by contract), and
    /// the stats the gates read DO migrate.
    func testDeckRenameMigrationLeavesItemUnlocksIntact() {
        let store = MemoryStore()
        let unlockBlob = #"{"known":["rankUp2","greedy","sameTell"]}"#
        store.set(unlockBlob, forKey: ItemUnlocks.key)
        store.set(#"{"deckTierBest":{"smith.regular":100},"cardsBuried":40}"#, forKey: Stats.key)
        SaveMigrations.migrateDeckIds(store)
        XCTAssertEqual(store.string(forKey: ItemUnlocks.key), unlockBlob,
                       "item ids are rename-stable — the known-set must ride through untouched")
        let stats = Stats(store: store)
        XCTAssertEqual(stats.get().cardsBuried, 40, "unlock counters survive the migration")
        XCTAssertEqual(stats.get().deckTierBest["garden.regular"], 100)
        // No item id contains the renamed deck tokens (the migration's
        // quoted-token replace relies on this).
        for d in allDefs {
            XCTAssertFalse(d.id.contains("smith") || d.id.contains("lammy"),
                           "'\(d.id)' collides with the deck-id rename tokens")
        }
    }

    /// Deck-rule sanity for the audit's reachability model: Garden refuses
    /// Pillars/Bases and Rocko refuses stickers, so those counters MUST have
    /// sources on the other decks — i.e. the intended progression's FIRST deck
    /// (Pinky) must have none of these restrictions.
    func testPinkyCarriesNoRestrictionsThatWouldStallCounters() {
        let pink = data.meta.rules("pink")
        XCTAssertFalse(pink.noStickers)
        XCTAssertFalse(pink.noPillarsBases)
        XCTAssertFalse(pink.preEquip)
    }
}
