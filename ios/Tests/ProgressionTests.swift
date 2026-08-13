import XCTest
@testable import GameCore

/// Unlocks, persistence, deck rules and the GameCore purity invariant.
final class ProgressionTests: XCTestCase {
    private let data = GameData.shared

    private func fresh() -> (store: MemoryStore, stats: Stats, zen: ZenStats, unlocks: ItemUnlocks) {
        let store = MemoryStore()
        let stats = Stats(store: store)
        let zen = ZenStats(store: store, ids: DifficultyData.zenIds)
        return (store, stats, zen, ItemUnlocks(store: store, data: data, stats: stats, zenStats: zen))
    }

    // MARK: - Item-unlock drip

    func testUngatedItemsAreAlwaysAvailable() {
        let (_, _, _, u) = fresh()
        for d in u.allDefs() where d.unlock == nil {
            XCTAssertTrue(u.isUnlocked(d), "'\(d.id)' has no gate and must always be available")
        }
    }

    func testEveryUnlockStatHasALiveReader() {
        let (_, stats, _, u) = fresh()
        var s = StatsRecord()
        // Move every additive counter so a missing reader shows as a 0.
        for k in StatsRecord.unlockCounters { s[k] = 11 }
        s.runsCleared = 12; s.gamesPlayed = 13; s.campaignsWon = 14
        s.bestEndless = 15; s.lifetimeDopamine = 16
        // The two HIGH-WATER marks aren't additive counters, so `bump` can't
        // reach them — they still need a live reader.
        s.bestCampaignScore = 17; s.bestCoinsInClimb = 18
        stats.put(s)
        for name in data.meta.itemUnlockStats where !name.hasPrefix("zen") {
            XCTAssertGreaterThan(u.statValue(name), 0, "stat '\(name)' has no reader")
        }
    }

    func testZenGatesReadTheZenRecordNotTheCampaignStats() {
        let (_, stats, zen, u) = fresh()
        stats.put(StatsRecord())                     // no campaign progress at all
        var e = ZenEntry(); e.games = 4; e.wins = 2
        zen.put("easy", e)
        XCTAssertEqual(u.statValue("zenGamesPlayed"), 4)
        XCTAssertEqual(u.statValue("zenEasyWon"), 2)
        XCTAssertEqual(u.statValue("zenMediumWon"), 0)
    }

    func testAGatedItemUnlocksWhenItsThresholdIsMet() {
        let (_, stats, _, u) = fresh()
        guard let gated = u.allDefs().first(where: { $0.unlock?.stat == "cardsBuried" }) else {
            // No cardsBuried gate today — use whatever additive gate exists.
            guard let any = u.allDefs().first(where: { g in
                g.unlock.map { StatsRecord.unlockCounters.contains($0.stat) } ?? false
            }) else { return }
            var s = StatsRecord(); s[any.unlock!.stat] = Int(any.unlock!.count)
            stats.put(s)
            XCTAssertTrue(u.isUnlocked(any))
            return
        }
        var s = StatsRecord()
        s.cardsBuried = Int(gated.unlock!.count) - 1
        stats.put(s)
        XCTAssertFalse(u.isUnlocked(gated), "one short of the threshold is still locked")
        s.cardsBuried = Int(gated.unlock!.count)
        stats.put(s)
        XCTAssertTrue(u.isUnlocked(gated), "meeting the threshold unlocks it")
    }

    /// The FIRST load stamps the derived set SILENTLY (retroactive, no toast
    /// spam) — a veteran's already-earned items must not all pop at once.
    func testFirstLoadPrimesTheKnownSetSilently() {
        let (_, stats, _, u) = fresh()
        var s = StatsRecord()
        for k in StatsRecord.unlockCounters { s[k] = 100_000 }
        s.runsCleared = 999; s.gamesPlayed = 999; s.campaignsWon = 999; s.lifetimeDopamine = 999_999
        stats.put(s)
        u.primeKnown()
        XCTAssertEqual(u.checkNewUnlocks().count, 0, "priming stamps the baseline before any play")
    }

    func testCrossingAThresholdAfterPrimingPops() {
        let (_, stats, _, u) = fresh()
        stats.put(StatsRecord())
        u.primeKnown()
        XCTAssertEqual(u.checkNewUnlocks().count, 0)
        guard let gated = u.allDefs().first(where: { g in
            g.unlock.map { StatsRecord.unlockCounters.contains($0.stat) } ?? false
        }) else { return }
        var s = StatsRecord()
        s[gated.unlock!.stat] = Int(gated.unlock!.count)
        stats.put(s)
        let popped = u.checkNewUnlocks()
        XCTAssertTrue(popped.contains { $0.id == gated.id }, "crossing the threshold pops the item")
        XCTAssertFalse(popped.first { $0.id == gated.id }!.hint.isEmpty, "every pop carries its hint copy")
        XCTAssertEqual(u.checkNewUnlocks().count, 0, "a pop fires exactly once")
    }

    func testNearestLockedRanksByProgress() {
        let (_, stats, _, u) = fresh()
        stats.put(StatsRecord())
        let near = u.nearestLocked(3)
        XCTAssertLessThanOrEqual(near.count, 3)
        for i in 1..<max(1, near.count) {
            XCTAssertGreaterThanOrEqual(near[i - 1].fraction, near[i].fraction, "sorted by progress desc")
        }
        for n in near { XCTAssertFalse(n.hint.isEmpty, "'\(n.id)' has no hint copy") }
    }

    func testEveryClassKeepsAtLeastTwoStartingItems() {
        // The store's class roll starves if a class has no ungated items.
        let (_, _, _, u) = fresh()
        for (name, list) in [("stickers", data.items.stickers), ("pillars", data.items.pillars),
                             ("bases", data.items.bases), ("samePowers", data.items.samePowers),
                             ("packs", data.items.packs)] {
            let starting = list.filter { $0.unlock == nil && !$0.cursed }
            XCTAssertGreaterThanOrEqual(starting.count, 2, "\(name) must keep ≥2 starting items")
            _ = u
        }
    }

    // MARK: - Deck unlocks

    func testDeckWinRecordingAndTheChain() {
        let store = MemoryStore()
        let du = DeckUnlocks(store: store)
        XCTAssertFalse(du.wonWith("pink"))
        XCTAssertTrue(du.recordWin(deckId: "pink", tier: "regular"), "the FIRST win reports true")
        XCTAssertFalse(du.recordWin(deckId: "pink", tier: "regular"), "a repeat win reports false")
        XCTAssertTrue(du.wonWith("pink"))
        XCTAssertTrue(du.wonWithTier("pink", "regular"), "regular reads the LEGACY key")
        XCTAssertFalse(du.wonWithTier("pink", "master"))
        du.recordWin(deckId: "pink", tier: "master")
        XCTAssertTrue(du.wonWithTier("pink", "master"))
    }

    func testDeckUnlockRetroactiveDownwardCompletion() {
        let store = MemoryStore()
        let du = DeckUnlocks(store: store)
        du.recordWin(deckId: "lammy", tier: "legendary")
        var s = StatsRecord()
        s.deckTierWins = ["smith.master": true]
        du.grantRetroactive(s)
        XCTAssertTrue(du.wonWithTier("lammy", "master"), "legendary implies master")
        XCTAssertTrue(du.wonWith("lammy"), "master implies the base key")
        XCTAssertTrue(du.wonWith("smith"), "a win in the Stats log re-grants its key")
    }

    func testLegacyPinkyCreditOnAnEmptyStore() {
        let store = MemoryStore()
        let du = DeckUnlocks(store: store)
        var s = StatsRecord(); s.campaignsWon = 3
        du.grantRetroactive(s)
        XCTAssertTrue(du.wonWith("pink"), "a pre-tracking lifetime win could only have been Pinky's")
    }

    // MARK: - Zen unlocks

    func testZenLadderOpensOneDifficultyAtATime() {
        let store = MemoryStore()
        let zu = ZenUnlocks(store: store, ids: DifficultyData.zenIds)
        XCTAssertTrue(zu.unlocked("easy"), "the first difficulty is always open")
        XCTAssertFalse(zu.unlocked("medium"))
        zu.recordWin("easy")
        XCTAssertTrue(zu.unlocked("medium"))
        XCTAssertFalse(zu.unlocked("hard"))
        zu.recordWin("medium")
        XCTAssertTrue(zu.unlocked("hard"))
    }

    /// A stats reset empties the Zen tallies; it must never RE-LOCK a difficulty
    /// — the ladder reads only its own store, and retroactively re-grants.
    func testZenUnlocksRegrantRetroactivelyFromZenStats() {
        let store = MemoryStore()
        let zen = ZenStats(store: store, ids: DifficultyData.zenIds)
        var e = ZenEntry(); e.wins = 1
        zen.put("easy", e)
        let zu = ZenUnlocks(store: store, ids: DifficultyData.zenIds)
        XCTAssertFalse(zu.won("easy"))
        zu.grantRetroactive(zen)
        XCTAssertTrue(zu.won("easy"), "a recorded Zen win re-grants at load")
    }

    // MARK: - Storage keys

    func testEveryStoreUsesTheNinelivesPrefix() {
        let store = MemoryStore()
        let stats = Stats(store: store)
        let zen = ZenStats(store: store, ids: DifficultyData.zenIds)
        let du = DeckUnlocks(store: store)
        let zu = ZenUnlocks(store: store, ids: DifficultyData.zenIds)
        let save = SaveStore(store: store)
        let iu = ItemUnlocks(store: store, data: data, stats: stats, zenStats: zen)

        stats.put(StatsRecord())
        zen.put("easy", ZenEntry())
        du.recordWin(deckId: "pink", tier: "regular")
        zu.recordWin("easy")
        save.save(["schema": .number(2)])
        save.setPref("tutorial2", "1")
        iu.primeKnown()

        let keys = Set(store.ninelivesKeys())
        XCTAssertTrue(keys.contains(Stats.key))
        XCTAssertTrue(keys.contains(ZenStats.key))
        XCTAssertTrue(keys.contains(DeckUnlocks.key))
        XCTAssertTrue(keys.contains(ZenUnlocks.key))
        XCTAssertTrue(keys.contains(SaveStore.key))
        XCTAssertTrue(keys.contains(ItemUnlocks.key))
        XCTAssertTrue(keys.contains("ninelives.pref.tutorial2"))
        // The native bridge mirrors ONLY the ninelives.* namespace.
        for k in keys { XCTAssertTrue(k.hasPrefix("ninelives."), "key '\(k)' escapes the mirrored namespace") }
    }

    func testMissingOrCorruptStorageReadsAsDefaultsAndNeverThrows() {
        let store = MemoryStore()
        store.set("}{not json", forKey: Stats.key)
        store.set("5", forKey: ZenUnlocks.key)
        XCTAssertEqual(Stats(store: store).get(), StatsRecord())
        XCTAssertFalse(ZenUnlocks(store: store, ids: DifficultyData.zenIds).won("easy"))
        XCTAssertNil(SaveStore(store: store).load())
    }

    func testStatsBumpOnlyMovesTheUnlockCounters() {
        let store = MemoryStore()
        let stats = Stats(store: store)
        var s = StatsRecord(); s.campaignsWon = 7
        stats.put(s)
        stats.bump("cardsBuried", 3)
        stats.bump("campaignsWon", 99)          // NOT an unlock counter — ignored
        XCTAssertEqual(stats.get().cardsBuried, 3)
        XCTAssertEqual(stats.get().campaignsWon, 7, "bump must never touch the legacy tallies")
    }

    /// The Collection's lifetime "BOUGHT ×N" tally.
    func testItemsBoughtTallyAccumulatesAndPersists() {
        let store = MemoryStore()
        let stats = Stats(store: store)
        stats.bumpItemBought("tieSafe")
        stats.bumpItemBought("tieSafe")
        stats.bumpItemBought("columnGuardian", 3)
        stats.bumpItemBought("")            // no id → nothing banked
        stats.bumpItemBought("ghost", 0)    // no-op count → no key minted
        XCTAssertEqual(stats.get().itemsBought["tieSafe"], 2)
        XCTAssertEqual(stats.get().itemsBought["columnGuardian"], 3)
        XCTAssertNil(stats.get().itemsBought["ghost"], "a zero bump must not mint a key")
        XCTAssertEqual(Stats(store: store).get().itemsBought, stats.get().itemsBought,
                       "the tally survives a reload")
    }

    /// A BUY banks a tally; an exhibition buy banks nothing (same rule the
    /// unlock counters follow), and a failed buy banks nothing either.
    func testBuyingBanksTheCollectionTally() {
        let store = MemoryStore()
        let c = CampaignState(store: store)
        c.reset()
        c.addCoins(500)
        let pillar = GameData.shared.items.pillars[0].id
        XCTAssertTrue(c.buyPillarToInventory(pillar))
        XCTAssertTrue(c.buyPillarToInventory(pillar))
        XCTAssertEqual(c.stats.get().itemsBought[pillar], 2, "each buy banks one")

        let broke = CampaignState(store: MemoryStore())
        broke.reset()
        XCTAssertFalse(broke.buyPillarToInventory(pillar), "no coins → no buy")
        XCTAssertNil(broke.stats.get().itemsBought[pillar], "a failed buy banks nothing")
    }

    /// DEBUG deck grants: bulk-random and exact-pick both land real, unique,
    /// serialisable cards in the deck.
    func testDebugDeckGrants() {
        let c = CampaignState(store: MemoryStore())
        c.reset()
        let before = c.deckSize()
        let ids = c.debugAddRandomCards(5)
        XCTAssertEqual(ids.count, 5)
        XCTAssertEqual(Set(ids).count, 5, "every minted card gets its own id")
        XCTAssertEqual(c.deckSize(), before + 5)
        XCTAssertTrue(c.debugAddRandomCards(0).isEmpty, "a zero ask mints nothing")
        XCTAssertTrue(c.debugAddRandomCards(-3).isEmpty, "a negative ask mints nothing")

        guard let id = c.debugAddCard(suit: "♠", rank: 11) else {
            XCTFail("an exact pick of J♠ should mint"); return
        }
        let minted = c.getRunDeck().first { $0.id == id }
        XCTAssertEqual(minted?.suit, "♠")
        XCTAssertEqual(minted?.currentRank, 11)
        XCTAssertNil(c.debugAddCard(suit: "★", rank: 5), "an unknown suit is refused")
        XCTAssertNil(c.debugAddCard(suit: "♠", rank: 99), "an out-of-range rank is refused")
        XCTAssertNil(c.debugAddCard(suit: "♠", rank: 1), "below the rank floor is refused")

        // The deck still round-trips through the save with the grants in it.
        let c2 = CampaignState(store: MemoryStore())
        XCTAssertTrue(c2.restore(c.serialize()))
        XCTAssertEqual(c2.deckSize(), c.deckSize(), "debug-granted cards survive a save")
    }

    func testStatsSurviveARoundTrip() {
        let store = MemoryStore()
        var s = StatsRecord()
        s.gamesPlayed = 12; s.campaignsWon = 3; s.bestCampaignScore = 88
        s.deckTierWins = ["lammy.master": true]
        for k in StatsRecord.unlockCounters { s[k] = 5 }
        Stats(store: store).put(s)
        XCTAssertEqual(Stats(store: store).get(), s)
    }

    // MARK: - Deck rules

    func testTheFourDeckCharacters() {
        XCTAssertEqual(Set(data.meta.deckRules.keys), Set(GameMeta.deckOrder))
        // Pinky is the baseline: no price/sticker/pre-equip modifiers. Since
        // v5.87 she uses the MIXED start (one of each rank, suits spread) —
        // MAMMA is the suit-staged climb now.
        let pink = data.meta.rules("pink")
        XCTAssertTrue(pink.altSuits); XCTAssertEqual(pink.priceMult, 1)
        XCTAssertFalse(pink.startStickers); XCTAssertFalse(pink.noStickers); XCTAssertFalse(pink.preEquip)
        XCTAssertFalse(data.meta.rules("mamma").altSuits, "Mamma is the suit-staged deck")
        XCTAssertEqual(data.meta.rules("smith").priceMult, 2)
        XCTAssertTrue(data.meta.rules("smith").startStickers)
        XCTAssertTrue(data.meta.rules("lammy").noStickers)
        XCTAssertTrue(data.meta.rules("lammy").preEquip)
        // An unknown deck falls back to Pinky.
        XCTAssertEqual(data.meta.rules("nope"), pink)
    }

    /// v5.74: no deck is gifted a starting Joker. v5.87: MAMMA is the deck that
    /// opens on the 13 hearts and climbs a suit-staged map.
    func testMammaStartsOnTheThirteenHearts() {
        for tier in DifficultyData.tierIds {
            let c = CampaignState()
            c.setDeck("mamma"); c.setTier(tier); c.setSeedOverride(1234); c.reset()
            let start = c.getRunDeck()
            XCTAssertEqual(start.count, 13, "\(tier): the run opens on exactly the 13 hearts")
            XCTAssertTrue(start.allSatisfy { $0.suit == "♥" }, "\(tier): every start card is a ♥")
            XCTAssertEqual(Set(start.map(\.currentRank)).count, 13, "\(tier): one of each rank")
            XCTAssertEqual(start.filter(\.joker).count, 0, "\(tier): no Joker is gifted")
        }
    }

    /// Pinky now opens on a MIXED hand and is still gifted no Joker.
    func testPinkyStartsMixedWithNoGiftedJoker() {
        for tier in DifficultyData.tierIds {
            let c = CampaignState()
            c.setDeck("pink"); c.setTier(tier); c.setSeedOverride(1234); c.reset()
            let start = c.getRunDeck()
            XCTAssertEqual(data.difficulty.startJokers(deckId: "pink", tierId: tier), 0,
                           "\(tier): difficulty.js ships no startJokers")
            XCTAssertEqual(start.count, 13, "\(tier): 13 start cards")
            XCTAssertEqual(c.runStartSize("pink", tier), 13,
                           "\(tier): runStartSize must agree with the real deck")
            XCTAssertEqual(Set(start.map(\.currentRank)).count, 13, "\(tier): one of each rank")
            XCTAssertEqual(Set(start.map(\.suit)).count, 4, "\(tier): every suit is represented")
            XCTAssertEqual(start.filter(\.joker).count, 0, "\(tier): no Joker is gifted")
        }
    }

    /// The mixed start spreads suits EVENLY — 13 over 4 is 4/3/3/3, never a
    /// lopsided 6/3/2/2 the way a per-rank coin flip could produce.
    func testTheMixedStartSpreadsSuitsEvenly() {
        // Mr Smith is excluded on purpose: his start stickers roll suit-CHANGERS
        // onto the dealt cards, so his final hand is deliberately uneven. The
        // rule under test is how the hand is DEALT.
        for deck in ["pink", "lammy"] {
            for seed: UInt32 in [1, 555, 4242, 99999] {
                let c = CampaignState()
                c.setDeck(deck); c.setSeedOverride(seed); c.reset()
                guard c.rules().altSuits, !c.rules().startStickers else { continue }
                var per: [String: Int] = [:]
                for card in c.getRunDeck() { per[card.suit, default: 0] += 1 }
                XCTAssertEqual(per.values.sorted(), [3, 3, 3, 4],
                               "\(deck) seed \(seed): 13 ranks spread 4/3/3/3 across the suits")
            }
        }
    }

    /// The two fixed corridor nodes are untouched: Pinky-Regular still gets
    /// exactly two Jokers, reserved from node one and EARNED by clearing the
    /// stage-1 and stage-2 bosses.
    func testPinkyRegularStillEarnsExactlyTwoCorridorJokers() {
        let c = CampaignState()
        c.setDeck("pink"); c.setTier("regular"); c.setSeedOverride(4242); c.reset()
        XCTAssertTrue(c.fixedJokerScheme, "Pinky-Regular runs the fixed-Joker scheme")
        let corridors = c.runMap!.nodes.filter(\.jokerNode).sorted { ($0.phase ?? 0) < ($1.phase ?? 0) }
        XCTAssertEqual(corridors.count, 2, "two fixed post-boss corridor nodes")
        XCTAssertEqual(corridors.map { $0.phase }, [0, 1], "after the stage-1 and stage-2 bosses")
        XCTAssertTrue(corridors.allSatisfy { c.nodeCard($0)?.joker == true }, "both locked to a Joker")
        // Held from node one = the two reservations only (no gifted Joker).
        XCTAssertEqual(c.jokersHeld(), 2, "only the corridor reservations count as held")
        XCTAssertFalse(c.jokersAllowed(), "the fixed scheme keeps every random Joker source off")
        // Earning them grows the deck 13 → 15.
        XCTAssertEqual(c.deckSize(), 13)
        for n in corridors { XCTAssertEqual(c.resolvePickup(n)?.joker, true, "the corridor grants a real Joker") }
        XCTAssertEqual(c.deckSize(), 15, "13 + the 2 earned Jokers")
        XCTAssertEqual(c.getRunDeck().filter(\.joker).count, 2)
    }

    func testAltDecksStartWithOneOfEachRankAtRandomSuits() {
        for deck in ["pink", "smith", "lammy"] {
            let c = CampaignState()
            c.setDeck(deck); c.setSeedOverride(555); c.reset()
            let start = c.getRunDeck()
            XCTAssertEqual(start.count, 13, "\(deck): 13 start cards")
            XCTAssertEqual(Set(start.map(\.originalRank)), Set(DeckManager.ranks.map(\.value)),
                           "\(deck): one card of EACH rank")
            XCTAssertEqual(Set(start.map(\.suit)).count, 4, "\(deck): every suit is represented")
        }
    }

    func testMrSmithStartsEveryCardStickered() {
        let c = CampaignState()
        c.setDeck("smith"); c.setSeedOverride(909); c.reset()
        for card in c.getRunDeck() {
            XCTAssertFalse(card.stickers.isEmpty, "Smith's card \(card.id) should carry a rolled sticker")
        }
    }

    func testLammyPreEquipsThreePillarsAndThreeBases() {
        let c = CampaignState()
        c.setDeck("lammy"); c.setSeedOverride(31415); c.reset()
        XCTAssertEqual(c.columnPillars.compactMap { $0 }.count, CampaignLayout.columnSlots)
        XCTAssertEqual(c.columnBases.compactMap { $0 }.count, CampaignLayout.columnSlots)
        XCTAssertEqual(Set(c.columnPillars.compactMap { $0 }).count, CampaignLayout.columnSlots, "distinct Pillars")
        XCTAssertEqual(Set(c.columnBases.compactMap { $0 }).count, CampaignLayout.columnSlots, "distinct Bases")
        // The sticker-centric Bases could never do anything under noStickers.
        for id in c.columnBases.compactMap({ $0 }) {
            let effect = data.baseTypes.get(id)?.effect
            XCTAssertNotEqual(effect, "randomSticker")
            XCTAssertNotEqual(effect, "stickerHarvest")
        }
    }

    func testLammyCannotBuyOrApplyStickers() {
        let c = CampaignState()
        c.setDeck("lammy"); c.setSeedOverride(2718); c.reset()
        c.addCoins(10_000)
        XCTAssertTrue(c.stickersLocked)
        XCTAssertFalse(c.buySticker(data.stickerTypes.ids[0]), "stickers are unusable")
        let card = c.getRunDeck()[0]
        XCTAssertFalse(c.canApplySticker(card, "tieSafe"))
    }

    func testAltDecksAreNotSuitSegmented() {
        let alt = CampaignState(); alt.setDeck("pink")
        XCTAssertEqual(Set(alt.suitsInPlay()).count, 4, "Pinky plays all four suits from the start")
        let staged = CampaignState(); staged.setDeck("mamma")
        XCTAssertEqual(staged.suitsInPlay(), ["♥", "♦"], "Mamma's stage 1 is ♥ + ♦")
    }

    // MARK: - Card edits

    func testRankEditsRespectTheBoundaries() {
        let c = CampaignState()
        c.setSeedOverride(1); c.reset()
        let ace = c.baseDeck.first { $0.currentRank == 14 }!
        XCTAssertFalse(c.increaseCard(ace.id), "an Ace is the ceiling")
        let two = c.baseDeck.first { $0.currentRank == 2 }!
        XCTAssertFalse(c.decreaseCard(two.id), "a 2 is the floor")
        let mid = c.baseDeck.first { $0.currentRank == 7 }!
        XCTAssertTrue(c.increaseCard(mid.id))
        XCTAssertEqual(c.findById(mid.id)?.currentRank, 8)
        XCTAssertEqual(c.findById(mid.id)?.modifications.last?.op, "increase", "the edit is recorded")
        XCTAssertEqual(c.findById(mid.id)?.originalRank, 7, "the original rank is preserved")
    }

    func testJokersAndBlanksRefuseEdits() {
        let c = CampaignState()
        c.setSeedOverride(1); c.reset()
        let jid = c.mintJokerId()
        XCTAssertFalse(c.increaseCard(jid))
        XCTAssertFalse(c.decreaseCard(jid))
        XCTAssertFalse(c.setCardSuit(jid, to: "♠"))
    }

    func testRankStickersRefuseAtTheirBoundary() {
        let c = CampaignState()
        c.setSeedOverride(1); c.reset()
        guard let plus = data.items.stickers.first(where: { $0.kind == "rank" && $0.num("rankDelta", 0) > 0 })
        else { return }
        let ace = c.baseDeck.first { $0.currentRank == 14 && !$0.joker }!
        XCTAssertFalse(c.canApplySticker(ace, plus.id), "no +1 on an Ace")
        let mid = c.baseDeck.first { $0.currentRank == 5 && !$0.joker }!
        XCTAssertTrue(c.canApplySticker(mid, plus.id))
    }

    // MARK: - GameCore purity

    /// GameCore must stay DOM-free / UI-free — that is what makes it testable in
    /// isolation and portable to the Phase 2 renderer.
    func testGameCoreImportsNoUIFrameworks() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // Tests/
            .deletingLastPathComponent()      // ios/
        var checked = 0
        for dir in ["GameCore", "Data"] {
            let base = root.appendingPathComponent(dir)
            let files = try FileManager.default.subpathsOfDirectory(atPath: base.path)
                .filter { $0.hasSuffix(".swift") }
            XCTAssertFalse(files.isEmpty, "\(dir)/ has no Swift files")
            for rel in files {
                let src = try String(contentsOf: base.appendingPathComponent(rel), encoding: .utf8)
                for banned in ["import UIKit", "import SpriteKit", "import SwiftUI", "import AppKit"] {
                    XCTAssertFalse(src.contains(banned), "\(dir)/\(rel) must not `\(banned)`")
                }
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 10, "expected the whole engine to be scanned")
    }
}
