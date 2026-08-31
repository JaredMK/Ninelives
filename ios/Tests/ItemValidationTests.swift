import XCTest
@testable import GameCore

/// ITEM VALIDATION — the driver. Enumerates EVERY item from the data file
/// (never a hand-written list), maps each to its Tier-1 scenarios or
/// campaign-level checks, runs them with frame + snapshot verification, and
/// prints the per-item pass table (`IVTABLE|...` lines — the report scrapes
/// them). An unmapped item id is itself a failure: nothing ships unvalidated.
final class ItemValidationTests: IVCase {

    let data = GameData.shared

    // MARK: - Campaign-level checks (apply-time stickers + store pillars)

    private func campaign(seed: UInt32 = 11) -> CampaignState {
        let c = CampaignState(store: MemoryStore())
        c.setDeck("pink"); c.setTier("regular"); c.setSeedOverride(seed); c.reset()
        return c
    }

    /// Checks for items whose effect is a DECK/STORE mutation, not a board
    /// behavior. Returns nil when the id isn't campaign-level.
    // swiftlint:disable:next cyclomatic_complexity
    func campaignCheck(_ def: ItemDef) -> (() -> Void)? {
        switch def.id {
        case "rankUp", "rankDown", "rankUp2", "rankDown2":
            return {
                let step = def.id.hasSuffix("2") ? 2 : 1
                let up = def.id.hasPrefix("rankUp")
                let c = self.campaign()
                let card = c.getRunDeck().first { !$0.joker && !$0.blank
                    && $0.currentRank > 3 && $0.currentRank < 13 }!
                let before = card.currentRank
                c.stickerInventory[def.id, default: 0] += 1
                XCTAssertTrue(c.applySticker(card.id, def.id), "\(def.id): applies")
                let after = c.findById(card.id)!.currentRank
                XCTAssertEqual(after, before + (up ? step : -step),
                               "\(def.id): rank moves by \(step) \(up ? "up" : "down")")
                // The record rides the card (deck-inspect shows the chip) and
                // the modification history names the change.
                XCTAssertTrue(c.findById(card.id)!.stickers.contains { $0.type == def.id },
                              "\(def.id): the chip stays on the card")
                XCTAssertTrue(c.findById(card.id)!.modifications.contains {
                    $0.op == (up ? "increase" : "decrease") }, "\(def.id): history recorded")
                // Edge: the rank floor/ceiling refuses an impossible apply.
                let edge = self.campaign()
                let capped = edge.getRunDeck().first { !$0.joker && !$0.blank
                    && $0.currentRank == (up ? 14 : 2) }
                if let capped {
                    edge.stickerInventory[def.id, default: 0] += step > 1 ? 1 : 1
                    XCTAssertFalse(edge.applySticker(capped.id, def.id),
                                   "\(def.id): refused at the rank \(up ? "ceiling" : "floor")")
                }
            }
        case "randomFixedValue":
            return {
                let c = self.campaign()
                let card = c.getRunDeck().first { !$0.joker && !$0.blank }!
                c.stickerInventory[def.id, default: 0] += 1
                XCTAssertTrue(c.applySticker(card.id, def.id), "\(def.id): applies")
                let after = c.findById(card.id)!.currentRank
                XCTAssertTrue((2...14).contains(after), "\(def.id): a legal rank (\(after))")
            }
        case "changeSuitRandom", "changeSuitSpade", "changeSuitHeart",
             "changeSuitDiamond", "changeSuitClub":
            return {
                let want = ["changeSuitSpade": "♠", "changeSuitHeart": "♥",
                            "changeSuitDiamond": "♦", "changeSuitClub": "♣"][def.id]
                let c = self.campaign()
                let card = c.getRunDeck().first { !$0.joker && !$0.blank
                    && (want == nil || $0.suit != want) }!
                c.stickerInventory[def.id, default: 0] += 1
                XCTAssertTrue(c.applySticker(card.id, def.id), "\(def.id): applies")
                let after = c.findById(card.id)!.suit
                if let want {
                    XCTAssertEqual(after, want, "\(def.id): the suit is exactly \(want)")
                } else {
                    XCTAssertTrue(["♠", "♥", "♦", "♣"].contains(after), "\(def.id)")
                }
            }
        case "freebie":
            return {
                // The store rolls exactly one gifted slot; it costs 0 through
                // BOTH the display chokepoint and the charge (the v6.49 bug).
                for seed: UInt32 in 1...80 {
                    let c = self.campaign(seed: seed)
                    c.pillarInventory["freebie", default: 0] += 1
                    c.setColumnPillar(col: 0, typeId: "freebie")
                    _ = c.openStore()
                    guard let i = c.storeOffer?.freeSlot else { continue }
                    XCTAssertEqual(c.priceOfMixed(i), 0, "freebie: the gifted slot displays 0")
                    while c.getCoins() > 0 { _ = c.spendCoins(1) }
                    let kind = c.storeOffer!.slots[i]!.kind
                    let ok = kind == "sticker" ? c.buyOfferedSticker(i)
                        : c.buyMixedSlot(i, mysteryRng: RNG(seed: seed &+ 5000)).ok
                    XCTAssertTrue(ok, "freebie: a 0-coin purse completes the free buy (\(kind))")
                    XCTAssertEqual(c.getCoins(), 0, "freebie: charged nothing")
                    return
                }
                XCTFail("freebie: no seed in 1...80 rolled a gift")
            }
        case "bulkRate":
            return {
                // Two ladders, one with the pillar: its second rung climbs
                // `value` less than the bare ladder's.
                let def = self.data.pillarTypes.get("bulkRate")!
                let bare = self.campaign(); _ = bare.addCoins(1000)
                XCTAssertTrue(bare.buyRemoval(bare.getRunDeck()[0].id))
                let with = self.campaign(); _ = with.addCoins(1000)
                with.pillarInventory["bulkRate", default: 0] += 1
                with.setColumnPillar(col: 0, typeId: "bulkRate")
                XCTAssertTrue(with.buyRemoval(with.getRunDeck()[0].id))
                XCTAssertEqual(bare.removalPrice() - with.removalPrice(), def.value,
                               "bulkRate: the second rung is \(def.value) cheaper")
            }
        case "rareHunter":
            return {
                let c = self.campaign()
                c.pillarInventory["rareHunter", default: 0] += 1
                c.setColumnPillar(col: 0, typeId: "rareHunter")
                let def = self.data.pillarTypes.get("rareHunter")!
                let mult = max(1, def.value)
                let w = c.effectiveTierWeights()
                let raw = self.data.items.store.tierWeights
                XCTAssertEqual(w["rare"], (raw["rare"] ?? 1) * mult,
                               "rareHunter: rare weight x\(mult)")
                XCTAssertEqual(w["common"], raw["common"], "rareHunter: commons untouched")
            }
        case "twoWard":
            return {
                let c = self.campaign()
                c.pillarInventory["twoWard", default: 0] += 1
                c.setColumnPillar(col: 0, typeId: "twoWard")
                let def = self.data.pillarTypes.get("twoWard")!
                let chance = def.num("chance", 0.3)
                var wards = 0
                let n = 400
                for node in 0..<n where c.twoWardNegates(node) { wards += 1 }
                XCTAssertEqual(Double(wards) / Double(n), chance, accuracy: 0.08,
                               "twoWard: ~\(Int(chance * 100))% of nodes warded")
                // v6.87: no 2s in the deck → the bounce is CERTAIN.
                XCTAssertGreaterThan(c.getRunDeck().filter { $0.currentRank == 2 }.count, 0,
                                     "setup: the fresh deck holds 2s (the ~30%% leg above was real)")
                _ = c.addCoins(1000)
                for two in c.getRunDeck().filter({ $0.currentRank == 2 }) {
                    XCTAssertTrue(c.buyRemoval(two.id), "setup: purge every 2")
                }
                XCTAssertTrue((0..<n).allSatisfy { c.twoWardNegates($0) },
                              "twoWard: an empty 2-rank makes every ward certain")
                // Must-not: without the pillar equipped, no ward at all.
                let bare = self.campaign()
                XCTAssertFalse((0..<50).contains { bare.twoWardNegates($0) },
                               "twoWard: no pillar, no ward")
            }
        case "queenFinder":
            return {
                // QUEEN-FINDER: one extra `chance` shot at the queen/two
                // split on its OWN substream — the un-equipped stream is
                // untouched byte for byte. Queens STRICTLY most common →
                // certainty, and the Old Joker passes the node too; a TIE
                // earns nothing.
                let def = self.data.pillarTypes.get("queenFinder")!
                let chance = def.num("chance", 0.3)
                let n = 400
                func queenShare(_ camp: CampaignState) -> Double {
                    var q = 0
                    for node in 0..<n where MysteryConfig.queenKeys.contains(camp.rollMysteryEvent(node)) { q += 1 }
                    return Double(q) / Double(n)
                }
                let bare = self.campaign()
                let base = queenShare(bare)
                let c = self.campaign()
                c.pillarInventory[def.id, default: 0] += 1
                c.setColumnPillar(col: 0, typeId: def.id)
                let boosted = queenShare(c)
                XCTAssertEqual(boosted, base + (1 - base) * chance, accuracy: 0.08,
                               "queenFinder: +\(Int(chance * 100))%% on the lost splits")
                for node in 0..<50 where MysteryConfig.queenKeys.contains(bare.rollMysteryEvent(node)) {
                    XCTAssertTrue(MysteryConfig.queenKeys.contains(c.rollMysteryEvent(node)),
                                  "queenFinder: a won split is never lost — the boost only adds")
                }
                // The 100% branch: six extra Queens make rank 12 the strict leader.
                for i in 0..<6 {
                    c.baseDeck.append(CardSpec(id: 9200 + i, suit: "♥", originalRank: 12, currentRank: 12))
                    c.ownedIds.append(9200 + i)
                }
                XCTAssertTrue(c.queensAreStrictlyMostCommon(), "setup: Queens strictly rule")
                XCTAssertTrue((0..<n).allSatisfy { MysteryConfig.queenKeys.contains(c.rollMysteryEvent($0)) },
                              "queenFinder: a Queen deck finds her EVERY time")
                XCTAssertTrue((0..<50).allSatisfy { c.rollOldJoker($0) == nil },
                              "queenFinder: …and the Old Joker passes the node")
                // A TIE doesn't count: match the leader with another rank.
                let qCount = c.getRunDeck().filter { $0.currentRank == 12 }.count
                let sevens = c.getRunDeck().filter { $0.currentRank == 7 }.count
                for i in 0..<max(0, qCount - sevens) {
                    c.baseDeck.append(CardSpec(id: 9300 + i, suit: "♣", originalRank: 7, currentRank: 7))
                    c.ownedIds.append(9300 + i)
                }
                XCTAssertFalse(c.queensAreStrictlyMostCommon(),
                               "queenFinder: a tied rank is nobody's majority")
            }
        // ── v6.76 archetype batch (store-side / on-purchase items) ──────────
        case "purgeFlatFive":
            return {
                // FLAT PURGE (v6.87 rework): ON PURCHASE the Purge ladder's
                // CURRENT price halves (odd rounds up), never below `value`,
                // exactly once — and the cut persists while the ladder keeps
                // stepping from the cut price.
                let floorVal = def.num("value", 5)
                let c = self.campaign(); _ = c.addCoins(1000)
                while c.removalPrice() < floorVal * 2 + 2 {
                    XCTAssertTrue(c.buyRemoval(c.getRunDeck()[0].id), "setup: climb the ladder")
                }
                let before = c.removalPrice()
                let expected = max(floorVal, Double((Int(before) + 1) / 2))
                _ = c.openStore()
                c.storeOffer = StoreOffer(slots: [StoreSlot(kind: "pillar", id: def.id)],
                                          rerollCost: 0)
                XCTAssertTrue(c.buyMixedSlot(0).ok, "\(def.id): the buy completes")
                XCTAssertEqual(c.removalPrice(), expected,
                               "\(def.id): the CURRENT price halved on purchase (min \(jsNum(floorVal)))")
                // One-time: the cut survives save/restore but never re-fires.
                let c2 = CampaignState(store: MemoryStore())
                XCTAssertTrue(c2.restore(c.serialize()))
                XCTAssertEqual(c2.removalPrice(), expected, "\(def.id): the cut persists")
                let priceBefore = c2.removalPrice()
                XCTAssertTrue(c2.buyRemoval(c2.getRunDeck()[0].id))
                XCTAssertGreaterThan(c2.removalPrice(), priceBefore,
                                     "\(def.id): the ladder steps ON from the cut — no ongoing flat")
                // The floor: a cheap ladder never halves below `value`.
                let cheap = self.campaign(); _ = cheap.addCoins(1000)
                XCTAssertLessThanOrEqual(cheap.removalPrice(), floorVal * 2)
                _ = cheap.openStore()
                cheap.storeOffer = StoreOffer(slots: [StoreSlot(kind: "pillar", id: def.id)],
                                              rerollCost: 0)
                XCTAssertTrue(cheap.buyMixedSlot(0).ok)
                XCTAssertGreaterThanOrEqual(cheap.removalPrice(), floorVal,
                                            "\(def.id): never below the \(jsNum(floorVal)) floor")
            }
        case "firstFree":
            return {
                // ON THE HOUSE: the first restock of EVERY store visit and the
                // first reshuffle of EVERY deal are free while equipped.
                let c = self.campaign(); _ = c.addCoins(1000)
                c.pillarInventory[def.id, default: 0] += 1
                c.setColumnPillar(col: 0, typeId: def.id)
                XCTAssertEqual(c.openStore().rerollCost, 0, "\(def.id): the first restock is free")
                XCTAssertEqual(c.openStore().rerollCost, 0, "\(def.id): …at EVERY store, not just the first")
                c.noteDealStarted()
                XCTAssertTrue(c.consumeFreeRedeal(), "\(def.id): the deal's first reshuffle is free")
                XCTAssertFalse(c.consumeFreeRedeal(), "\(def.id): …exactly once per deal")
                c.noteDealStarted()
                XCTAssertTrue(c.consumeFreeRedeal(), "\(def.id): the next deal re-arms it")
                // Must-not: the bare campaign pays the base cost and gets nothing.
                let bare = self.campaign()
                XCTAssertEqual(bare.openStore().rerollCost, self.data.items.store.reroll.baseCost)
                bare.noteDealStarted()
                XCTAssertFalse(bare.consumeFreeRedeal(), "\(def.id): no pillar, no free reshuffle")
            }
        case "purgeRank":
            return {
                // RANK PURGE: on purchase every full-deck card of the rolled
                // rank leaves — NO ladder charge. Also: restore MID-STORE, the
                // restored offer's slot still carries the roll and the buy
                // purges the same rank.
                let c = self.campaign(); _ = c.addCoins(1000)
                _ = c.openStore()
                let rolled = 4
                c.storeOffer = StoreOffer(slots: [StoreSlot(kind: "pillar", id: def.id, rollRank: rolled)],
                                          rerollCost: 0)
                // If the open shelf already locked a rank for this item, the
                // purchase honors THE LOCK (first appearance wins the climb).
                let effective = c.shopRolls[def.id]?.rank ?? rolled
                let ladderBefore = c.removalsBought
                let priceBefore = c.removalPrice()
                let heldBefore = c.getRunDeck().filter { $0.currentRank == effective }.count
                let blob = c.serialize()
                let r = c.buyMixedSlot(0)
                XCTAssertTrue(r.ok, "\(def.id): the buy completes")
                XCTAssertEqual(r.purgedCount, heldBefore, "\(def.id): every \(effective) left the deck")
                XCTAssertEqual(c.getRunDeck().filter { $0.currentRank == effective }.count, 0, "\(def.id)")
                XCTAssertEqual(c.removalsBought, ladderBefore, "\(def.id): NO ladder charge")
                XCTAssertEqual(c.removalPrice(), priceBefore, "\(def.id): the Purge price never moved")
                XCTAssertEqual(c.shopRolls[def.id]?.rank, effective, "\(def.id): the roll locked")
                // Restore mid-store: the slot's OWN roll rides the saved
                // offer (the climb lock may legitimately differ — first
                // appearance wins, and the purchase honors THE LOCK).
                let c2 = CampaignState(store: MemoryStore())
                XCTAssertTrue(c2.restore(blob), "\(def.id): the mid-store save restores")
                let slot = c2.storeOffer?.slots[0] ?? nil
                XCTAssertEqual(slot?.rollRank, rolled, "\(def.id): the slot's roll rides the saved offer")
                let r2 = c2.buyMixedSlot(0)
                XCTAssertEqual(r2.purgedCount, heldBefore, "\(def.id): the restored buy purges identically")
                XCTAssertEqual(c2.getRunDeck().filter { $0.currentRank == effective }.count, 0, "\(def.id)")
            }
        case "transmute":
            return {
                // TRANSMUTE (v6.78): on purchase every full-deck card of the
                // LIVE most common rank (ties → lowest — exactly what the
                // shelf text names) takes the shop-rolled suit. Restore
                // mid-store replays it (the deck is part of the save, so the
                // most-common read replays too).
                let c = self.campaign(); _ = c.addCoins(1000)
                _ = c.openStore()
                let suit = "♣"
                c.storeOffer = StoreOffer(slots: [StoreSlot(kind: "base", id: def.id,
                                                            rollSuit: suit)],
                                          rerollCost: 0)
                let effectiveSuit = c.shopRolls[def.id]?.suit ?? suit
                guard let targetRank = c.mostCommonRank() else {
                    return XCTFail("\(def.id): a fresh deck always has a most common rank")
                }
                // The shelf text names the live target rank, never a template.
                let text = c.itemDescription(def)
                let rankLabel = DeckManager.ranks.first { $0.value == targetRank }?.label ?? "?"
                XCTAssertTrue(text.contains(rankLabel),
                              "\(def.id): the shelf text names the live most common rank")
                XCTAssertFalse(text.contains("{rank}"), "\(def.id): no leaked template")
                let blob = c.serialize()
                let heldBefore = c.getRunDeck().filter { $0.currentRank == targetRank }.count
                let r = c.buyMixedSlot(0)
                XCTAssertTrue(r.ok, "\(def.id): the buy completes")
                XCTAssertEqual(r.transmutedCount, heldBefore, "\(def.id)")
                XCTAssertTrue(c.getRunDeck().filter { $0.currentRank == targetRank }
                                .allSatisfy { $0.suit == effectiveSuit },
                              "\(def.id): every \(targetRank) is now \(effectiveSuit)")
                XCTAssertEqual(c.baseInventory[def.id], 1, "\(def.id): the base still lands in inventory")
                // …and it NEVER activates in a deal.
                let e = IVBases.baseEngine(def)
                XCTAssertNil(e.baseActivate(col: 0), "\(def.id): never fires in-deal")
                XCTAssertNotNil(e.baseUnavailableReason(0), "\(def.id): the amber tap says why")
                // Restore mid-store: identical recolor.
                let c2 = CampaignState(store: MemoryStore())
                XCTAssertTrue(c2.restore(blob), "\(def.id)")
                let r2 = c2.buyMixedSlot(0)
                XCTAssertEqual(r2.transmutedCount, heldBefore, "\(def.id): the restored buy matches")
            }
        case "purgeDiscount":
            return {
                // PURGE COUPON (v6.93): the engine activation REPORTS the cut
                // (perDiamond × ♦-TOPPED alive piles in the column) + floor;
                // applying it to the campaign cuts the store Purge price,
                // never below the floor, for the rest of the climb.
                let per = def.int("perDiamond", 1), floor = def.int("min", 5)
                let e = IVBases.baseEngine(def, tops: [IV.spec(1, 5, "♦"), IV.spec(2, 8, "♦"),
                                                       IV.spec(3, 6, "♦")])
                let res = e.baseActivate(col: 0)
                // col 0 holds piles 1-2 (cols [2,1]) — pile 3's ♦ is another
                // column's and must NOT count.
                XCTAssertEqual(res?.purgePriceCut, 2 * per,
                               "\(def.id): the cut is per ♦-topped pile IN THIS COLUMN")
                XCTAssertEqual(res?.purgePriceFloor, floor, "\(def.id): the floor is the data's min")
                XCTAssertEqual(e.run.basesUsed?[0], true, "\(def.id): the charge is spent")
                XCTAssertNil(e.baseActivate(col: 0), "\(def.id): …and stays spent")
                // The gate: no ♦-topped pile in the column → amber, and the
                // fire refuses (a 0-cut activation would waste the charge).
                let g = IVBases.baseEngine(def)   // default tops: ♠/♥/♣ — no ♦
                XCTAssertFalse(g.baseCanActivate(0), "\(def.id): no ♦ top, no fire")
                XCTAssertNotNil(g.baseUnavailableReason(0), "\(def.id): the amber tap says why")
                XCTAssertNil(g.baseActivate(col: 0), "\(def.id): the refused fire keeps the charge")
                XCTAssertEqual(g.run.basesUsed?[0], false, "\(def.id)")
                // The live badge previews the exact cut.
                let badge = IVBases.baseEngine(def, tops: [IV.spec(1, 5, "♦"), IV.spec(2, 8, "♦"),
                                                           IV.spec(3, 6, "♦")])
                XCTAssertEqual(badge.baseLiveCounter(0), 2 * per,
                               "\(def.id): the badge is the fire's own math")
                // Applying the reported cut: −cut, floored at the Coupon's min.
                let cut = 2 * per
                let c = self.campaign(); _ = c.addCoins(1000)
                let base0 = c.removalPrice()
                c.addPurgeDiscount(cut)
                XCTAssertEqual(c.removalPrice(), max(Double(floor), base0 - Double(cut)),
                               "\(def.id): −\(cut), floored at the Coupon's min")
                c.addPurgeDiscount(999)
                XCTAssertEqual(c.removalPrice(), Double(floor),
                               "\(def.id): the cut can NEVER drag Purge below \(floor)")
                // The accumulated CUT persists across save/restore (the floor
                // re-derives from the def at price time — it is never saved)…
                let c2 = CampaignState(store: MemoryStore())
                XCTAssertTrue(c2.restore(c.serialize()))
                XCTAssertEqual(c2.removalPrice(), Double(floor), "\(def.id): the cut survives the save")
                // …and reset with the climb.
                c2.startNewRun()
                XCTAssertEqual(c2.removalPrice(), c2.shopPrice(self.data.items.store.removal.price),
                               "\(def.id): a new climb restarts the ladder")
            }
        default:
            return nil
        }
    }
    // MARK: - TIER 1: every item, every scenario

    func testTier1EveryItemValidates() {
        var table: [(String, String, Bool)] = []   // (group.id, scenario, passed)
        var unmapped: [String] = []

        func runScenarios(_ group: String, _ def: ItemDef, _ scenarios: [IV.Scenario]?) {
            if let check = campaignCheck(def) {
                let before = IV.failureTally
                check()
                table.append(("\(group).\(def.id)", "campaign", IV.failureTally == before))
                return
            }
            guard let scenarios, !scenarios.isEmpty else {
                unmapped.append("\(group).\(def.id)")
                return
            }
            XCTAssertGreaterThanOrEqual(scenarios.count, 3,
                "\(group).\(def.id): needs >=3 scenarios (has \(scenarios.count))")
            for s in scenarios {
                let ok = IV.run(s, item: "\(group).\(def.id)")
                table.append(("\(group).\(def.id)", s.name, ok))
            }
        }

        for def in data.stickerTypes.all() {
            runScenarios("sticker", def, IVStickers.scenarios(for: def))
        }
        for def in data.pillarTypes.all() {
            runScenarios("pillar", def, IVPillarsBases.scenarios(for: def))
        }
        for def in data.baseTypes.all() {
            runScenarios("base", def, IVBases.scenarios(for: def))
        }
        for def in data.samePowerTypes.all() {
            runScenarios("power", def, IVBases.powerScenarios(for: def))
        }

        XCTAssertTrue(unmapped.isEmpty,
            "UNVALIDATED ITEMS (add scenarios before shipping them): \(unmapped)")

        // The machine-readable table for the report.
        var byItem: [String: (pass: Int, fail: Int)] = [:]
        for (item, _, ok) in table {
            var e = byItem[item] ?? (0, 0)
            if ok { e.pass += 1 } else { e.fail += 1 }
            byItem[item] = e
        }
        for (item, r) in byItem.sorted(by: { $0.key < $1.key }) {
            print("IVTABLE|\(item)|\(r.pass)|\(r.fail)")
        }
        print("IVTOTAL|items=\(byItem.count)|scenarios=\(table.count)|fails=\(table.filter { !$0.2 }.count)")
    }

    // MARK: - TIER 2: lifecycle — the price is ONE number at every stage

    func testTier2EveryPurchasableChargesItsDisplayedPriceOnForcedShelves() {
        // Force EVERY purchasable item through a shelf slot (the rolls would
        // take thousands of visits to cover the catalog) and assert shelf
        // display == charge, then placement + persistence.
        var checked = 0
        func forceAndBuy(_ kind: String, _ def: ItemDef) {
            let c = campaign()
            _ = c.addCoins(2000)
            _ = c.openStore()
            c.storeOffer!.slots[0] = StoreSlot(kind: kind, id: def.id)
            c.storeOffer!.freeSlot = nil
            let displayed = c.priceOfMixed(0)
            guard displayed.isFinite else { return }
            let before = c.getCoins()
            let ok = kind == "sticker" ? c.buyOfferedSticker(0) : c.buyMixedSlot(0).ok
            guard ok else {
                return XCTFail("\(kind).\(def.id): the forced shelf buy refused")
            }
            XCTAssertEqual(Double(before - c.getCoins()), displayed,
                           "\(kind).\(def.id): charged EXACTLY the displayed price")
            // Inventory landed?
            switch kind {
            case "sticker": XCTAssertEqual(c.stickerInventory[def.id], 1, "\(def.id) in inventory")
            case "pillar":
                XCTAssertEqual(c.pillarInventory[def.id], 1, "\(def.id) in inventory")
                // Placement completes and persists.
                c.setColumnPillar(col: 1, typeId: def.id)
                let c2 = CampaignState(store: MemoryStore())
                XCTAssertTrue(c2.restore(c.serialize()))
                XCTAssertEqual(c2.columnPillars[1], def.id, "\(def.id): placement survives the save")
            case "base":
                XCTAssertEqual(c.baseInventory[def.id], 1)
                c.setColumnBase(col: 1, typeId: def.id)
                let c2 = CampaignState(store: MemoryStore())
                XCTAssertTrue(c2.restore(c.serialize()))
                XCTAssertEqual(c2.columnBases[1], def.id, "\(def.id): placement survives the save")
            case "samepower":
                XCTAssertEqual(c.samePowerInventory[def.id], 1)
            default: break
            }
            checked += 1
        }
        for def in data.stickerTypes.all() where !def.cursed { forceAndBuy("sticker", def) }
        for def in data.pillarTypes.all() { forceAndBuy("pillar", def) }
        for def in data.baseTypes.all() { forceAndBuy("base", def) }
        for def in data.samePowerTypes.all() { forceAndBuy("samepower", def) }
        for def in data.packTypes.all() { forceAndBuy("pack", def) }
        print("IVTIER2|purchasables=\(checked)")
        XCTAssertGreaterThan(checked, 100, "the forced-shelf sweep covered the catalog")
    }

    func testTier2ModifiedPricePaths() {
        // A deck price multiplier flows through every stage (v6.67: no deck
        // carries one today — Garden shops at Pinky prices — so the mult
        // branch idles until a future deck declares one; the ladder and
        // discount paths below still run).
        let smith = CampaignState(store: MemoryStore())
        smith.setDeck("garden"); smith.setTier("regular"); smith.setSeedOverride(3); smith.reset()
        _ = smith.addCoins(2000)
        _ = smith.openStore()
        let mult = data.meta.rules("garden").priceMult
        if mult != 1 {
            smith.storeOffer!.slots[0] = StoreSlot(kind: "pillar", id: "fibonacci")
            smith.storeOffer!.freeSlot = nil
            let displayed = smith.priceOfMixed(0)
            XCTAssertEqual(displayed, (data.pillarTypes.get("fibonacci")!.price * mult).rounded(),
                           accuracy: 1, "smith: the multiplier shows on the shelf")
            let before = smith.getCoins()
            XCTAssertTrue(smith.buyMixedSlot(0).ok)
            XCTAssertEqual(Double(before - smith.getCoins()), displayed,
                           "smith: and charges identically")
        }
        // The escalating removal ladder: display == charge at every rung.
        let c = campaign()
        _ = c.addCoins(2000)
        for _ in 0..<3 {
            let quoted = c.removalPrice()
            let before = c.getCoins()
            XCTAssertTrue(c.buyRemoval(c.getRunDeck()[0].id))
            XCTAssertEqual(Double(before - c.getCoins()), quoted,
                           "removal: rung price charged as quoted")
        }
        // Sell values come from items.js (v6.50: the UI hardcoded 1/2/3 — now
        // the data file is the ONE source, per tier).
        let s = campaign()
        let sellTable = data.items.store.raw["sell"]?.asObject ?? [:]
        for def in [data.pillarTypes.get("allHeartsCoin")!,       // common
                    data.pillarTypes.get("secondWind")!,          // its own tier
                    data.baseTypes.get("demolish")!] {
            let expected = Int(sellTable[def.tier]?.asNumber ?? -1)
            XCTAssertEqual(s.sellValue(def), expected,
                           "sell(\(def.id)): reads store.sell.\(def.tier) from items.js")
        }
        // THE OLD JOKER's refund: pays minMult..maxMult x the SAME sell base.
        let r = campaign()
        _ = r.addCoins(50)
        r.pillarInventory["fibonacci", default: 0] += 1
        r.setColumnPillar(col: 0, typeId: "fibonacci")
        r.debugForcedJokerKey = "refund"
        if case .refund(let options, let values)? = r.rollOldJoker(21) {
            let cfg = data.items.oldJoker.raw["refund"]?.asObject ?? [:]
            let lo = cfg["minMult"]?.asNumber ?? 2, hi = cfg["maxMult"]?.asNumber ?? 3
            for (h, value) in zip(options, values) {
                let def = h.kind == .pillar ? data.pillarTypes.get(h.id)
                    : h.kind == .base ? data.baseTypes.get(h.id) : data.samePowerTypes.get(h.id)
                // The refund is minMult..maxMult x the item's PRICE (the
                // in-code contract; the config's per-tier fields were dead
                // and are removed - see the report).
                let base = def?.price ?? 1
                XCTAssertGreaterThanOrEqual(Double(value), (base * lo).rounded(.down),
                    "refund(\(h.id)): at least minMult x price")
                XCTAssertLessThanOrEqual(Double(value), (base * hi).rounded(.up),
                    "refund(\(h.id)): at most maxMult x price")
            }
        }
    }

    // MARK: - INTERACTIONS: the collision classes, enumerated from the code

    /// Risky pairs justified by SHARED RESOURCES in the engine:
    ///  • sameCharge writers: sameBanked / drainShield / rechargeSameShield / insurance
    ///  • bonusCoins writers vs Spoiler's wipe
    ///  • pileSize readers vs heavy/shrink/flatline (score + evenOut targets)
    ///  • sticker mutators: peeler vs flypaper/randomSticker/harvest projections
    ///  • pillar gate: jammer vs every column pillar (resolvePillarDef nil)
    ///  • base drain vs an already-fired base (basesUsed)
    ///  • magnet vs the revive offer's targeting
    func testInteractionsCollisionClasses() {
        // 1. drainShield vs rechargeSameShield on the SAME landing. ORDER OF
        //    RECORD: curses fire at the touch (first), expansion stickers
        //    after — so the drain empties the OLD charge and the recharge
        //    banks a fresh one. The card ends up charged.
        //    v6.90: the recharge is rank-conditional now — pile 2's 9♥
        //    feeds its bet so the collision still plays out.
        let e1 = IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 9, "♥"), IV.spec(3, 6)],
                           deckOrder: [IV.spec(50, 9, "♠", ["rechargeSameShield", "drainShield"]),
                                       IV.spec(51, 2)], sameCharge: true)
        e1.guess(0, .higher)
        XCTAssertTrue(e1.sameCharge, "drain fires first, recharge banks after: net charged")

        // 2. Spoiler + gainCoin on one card. ORDER OF RECORD: the wipe fires
        //    at the touch, the payout after — the card's OWN coin survives
        //    its own curse; only coins earned BEFORE the landing rot.
        let e2 = IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)],
                           deckOrder: [IV.spec(50, 9, "♠", ["gainCoin"]),
                                       IV.spec(51, 11, "♥", ["spoiler"]), IV.spec(52, 2)])
        e2.guess(0, .higher)   // gainCoin pays
        let paid = e2.run.bonusCoins
        XCTAssertGreaterThan(paid, 0)
        e2.guess(0, .higher)   // the spoiler lands NEXT: wipes the earlier pay
        XCTAssertEqual(e2.run.bonusCoins, 0, "the spoiler wiped the earlier bonus")
        let itemized = e2.run.bonusEvents.pairs.reduce(0.0) { $0 + $1.amount }
        XCTAssertEqual(itemized, e2.run.bonusCoins, "the itemization still sums")

        // 3. Shrink + Heavy on one card: weights stack additively.
        let e3 = IV.engine(tops: [IV.spec(1, 5, "♠", ["heavy", "shrink"]), IV.spec(2, 6), IV.spec(3, 6)],
                           deckOrder: [IV.spec(50, 9)])
        XCTAssertEqual(e3.board.pileSize(0), 1, "heavy(+1) + shrink(-1) = net 1, floored")

        // 4. Flatline top beats Heavy buried beneath (the override wins).
        let e4 = IV.engine(tops: [IV.spec(1, 5, "♠", ["heavy"]), IV.spec(2, 6), IV.spec(3, 6)],
                           deckOrder: [IV.spec(50, 9, "♠", ["flatline"]), IV.spec(51, 2)])
        e4.guess(0, .higher)
        XCTAssertEqual(e4.board.pileSize(0), 1, "flatline top pins the pile regardless of weights")

        // 5. Jammer knocks out a SCORING pillar's payout while top.
        let e5 = IV.engine(tops: [IV.spec(1, 5, "♠", ["jammer"]), IV.spec(2, 6), IV.spec(3, 6)],
                           deckOrder: [IV.spec(50, 9)],
                           pillars: ["columnGuardian", nil, nil])
        XCTAssertTrue(e5.computePillarPayout().lines.isEmpty, "a jammed Guardian pays nothing")

        // 6. Peeler strips a flypaper-granted sticker (projection then peel).
        let e6 = IV.engine(tops: [IV.spec(1, 5, "♠", ["peeler"]), IV.spec(2, 6), IV.spec(3, 6)],
                           deckOrder: [IV.spec(50, 9, "♠", ["tell"]), IV.spec(51, 2)])
        e6.guess(0, .higher)
        XCTAssertTrue(e6.board.top(0)!.stickers.isEmpty, "the landing card lost its tell to the peeler")

        // 7. Sticker Harvest on a curse-stickered card: curses harvest too.
        let e7 = IVBases.baseEngine(data.baseTypes.get("stickerHarvest")!,
                                    tops: [IV.spec(1, 5, "♠", ["leech", "magnet"]),
                                           IV.spec(2, 8, "♥"), IV.spec(3, 6)])
        let r7 = e7.baseActivate(col: 0, targetIndex: 0)
        XCTAssertEqual(r7?.harvested, 2, "harvest counts curse stickers")
        XCTAssertTrue(e7.board.top(0)!.stickers.isEmpty, "…and strips them")
        XCTAssertTrue(e7.magnetPiles().isEmpty, "the harvested magnet releases the board")

        // 8. Base Drain then Refresh Bases: the drained base re-arms.
        let e8 = IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 8), IV.spec(3, 6)],
                           deckOrder: [IV.spec(50, 9, "♠", ["drainBase"]), IV.spec(51, 3)],
                           cols: [1, 2],
                           bases: ["spadePeek", "refreshBases"])
        e8.guess(0, .higher)
        XCTAssertEqual(e8.run.basesUsed?[0], true, "the curse drained column 0's base")
        _ = e8.baseActivate(col: 1)
        XCTAssertEqual(e8.run.basesUsed?[0], false, "Refresh Bases re-arms the drained base")

        // 9. Magnet constrains the ENGINE even while a revive offer is up.
        let e9 = IV.engine(tops: [IV.spec(1, 9, "♠", ["magnet"]), IV.spec(2, 6), IV.spec(3, 6)],
                           deckOrder: [IV.spec(50, 11), IV.spec(51, 2)])
        e9.guess(1, .higher)
        XCTAssertEqual(e9.run.totalGuesses, 0, "the magnet holds")
        e9.guess(0, .higher)
        XCTAssertEqual(e9.run.totalGuesses, 1)

        // 10. Economy stack: two coin stickers on one card both pay. The ♠
        //     carrier over two ♠ tops feeds the conditional → ×3.
        let e10 = IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)],
                            deckOrder: [IV.spec(50, 9, "♠", ["gainCoin", "extraCoin"]), IV.spec(51, 2)])
        e10.guess(0, .higher)
        let gc = data.stickerTypes.get("gainCoin")!.value
        XCTAssertEqual(e10.run.bonusCoins, gc * 3, "gainCoin pays now, per matching-top pile")
        // extraCoin units = instances x the PILE's weighted size (2 cards).
        XCTAssertEqual(e10.board.extraCoinUnits(), 2,
                       "extraCoin pays per pile size at the end - both live on one card")

        // 11. Wild Suit feeds the conditional Guard's board read: no plain ♣
        //     top exists, but the wild top on pile 2 counts as every suit.
        let e11 = IV.engine(tops: [IV.spec(1, 9, "♠"), IV.spec(2, 6, "♦", ["wildSuit"]), IV.spec(3, 6, "♦")],
                            deckOrder: [IV.spec(50, 2, "♣", ["suitImmunity"]), IV.spec(51, 3)])
        e11.guess(0, .higher)   // wrong, but the wild top feeds the ♣ carrier's guard
        XCTAssertTrue(e11.board.isActive(0), "a wild top triggers the guard as every suit")

        // 12. Mute on a pile does NOT stop Same Charge auto-save (the backstop
        //     is a save, not a call).
        let e12 = IV.engine(tops: [IV.spec(1, 9, "♠", ["mute"]), IV.spec(2, 6), IV.spec(3, 6)],
                            deckOrder: [IV.spec(50, 2), IV.spec(51, 3)],
                            sameCharge: true)
        e12.guess(0, .higher)   // wrong → the charge saves despite the mute
        XCTAssertTrue(e12.board.isActive(0), "mute blocks the CALL, never the save")
        XCTAssertFalse(e12.sameCharge, "the charge was spent saving")
    }
}
