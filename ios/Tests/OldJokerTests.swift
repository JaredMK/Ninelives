import XCTest
@testable import GameCore

/// THE OLD JOKER. One section per offer: what it does when accepted, that
/// declining is always free and changes nothing, and that the whole thing is
/// deterministic and survives a save.
final class OldJokerTests: XCTestCase {

    private let data = GameData.shared

    private func campaign(seed: UInt32 = 4242, deck: String = "pink") -> CampaignState {
        let c = CampaignState()
        c.setDeck(deck); c.setSeedOverride(seed); c.reset()
        return c
    }

    /// Equip something in every slot so the holding-based offers are eligible.
    private func equipEverything(_ c: CampaignState) {
        for (i, p) in data.items.pillars.prefix(CampaignLayout.columnSlots).enumerated() {
            c.setColumnPillar(col: i, typeId: p.id)
        }
        for (i, b) in data.items.bases.prefix(CampaignLayout.columnSlots).enumerated() {
            c.setColumnBase(col: i, typeId: b.id)
        }
        // v6.98 flat rarity: every pillar/base is uncommon now, so BLIND
        // SWAP's common-item pool can only come from the sticker INVENTORY —
        // hold one common sticker, the way a real climb would.
        _ = c.addStickerToInventory("rankUp")
    }

    private var cfg: OldJokerConfig { data.items.oldJoker }

    // MARK: - Data surface

    func testEveryOfferHasAWeightAndTheMixIsSane() {
        for k in OldJokerConfig.offerKeys {
            XCTAssertGreaterThan(cfg.weights[k] ?? 0, 0, "\(k): needs a positive roll weight")
        }
        let cw = data.items.mystery.characterWeights
        for k in MysteryConfig.characterKeys {
            XCTAssertGreaterThan(cw[k] ?? 0, 0, "\(k): needs a positive character weight")
        }
    }

    // MARK: - Appearance roll

    func testHeAppearsDeterministicallyPerNode() {
        let a = campaign(), b = campaign()
        for node in 1...40 {
            XCTAssertEqual(a.rollOldJoker(node)?.key, b.rollOldJoker(node)?.key,
                           "node \(node): the same run+node must produce the same offer")
        }
    }

    func testHeSometimesAppearsAndSometimesDoesNot() {
        let c = campaign()
        var shown = 0
        for node in 1...200 where c.rollOldJoker(node) != nil { shown += 1 }
        XCTAssertGreaterThan(shown, 0, "he never showed up across 200 nodes")
        XCTAssertLessThan(shown, 200, "he took over EVERY node")
    }

    func testOnlyEligibleOffersAreRolled() {
        // A campaign with nothing equipped can never be offered a Buyout,
        // Swap, Blind Swap or Refund.
        let c = campaign()
        c.columnPillars = Array(repeating: nil, count: CampaignLayout.columnSlots)
        c.columnBases = Array(repeating: nil, count: CampaignLayout.columnSlots)
        c.stickerInventory = [:]
        let holdingOffers: Set<String> = ["buyout", "swap", "blindSwap", "refund"]
        for node in 1...300 {
            if let key = c.rollOldJoker(node)?.key {
                XCTAssertFalse(holdingOffers.contains(key),
                               "node \(node): offered \(key) with nothing equipped")
            }
        }
    }

    /// Every one of his offers must be REACHABLE in a run where its
    /// preconditions hold — this is the test that would catch a typo'd key or
    /// an eligibility rule that accidentally excludes an offer forever.
    func testAllOffersAreReachable() {
        let c = campaign()
        equipEverything(c)
        c.addCoins(200)
        c.setSameCharge(false)
        // PURGE RESET only exists once the Purge ladder has actually climbed.
        _ = c.buyRemoval(c.getRunDeck().first!.id)
        if let opening = c.legalNextNodes().first { c.moveToNode(opening.id) }
        var seen = Set<String>()
        for node in 1...4000 {
            guard let o = c.rollOldJoker(node) else { continue }
            seen.insert(o.key)
            if seen.count == OldJokerConfig.offerKeys.count { break }
        }
        let missing = Set(OldJokerConfig.offerKeys).subtracting(seen)
        // Ride needs a store ahead of the current position; if this seed's map
        // has none it is legitimately unreachable here.
        let excusable: Set<String> = c.nextStoreBeforeBoss() == nil ? ["ride"] : []
        XCTAssertEqual(missing.subtracting(excusable), [],
                       "unreachable offers: \(missing.sorted())")
    }

    // MARK: - Declining

    func testDecliningIsAlwaysFreeAndChangesNothing() {
        let c = campaign()
        equipEverything(c)
        c.addCoins(50)
        var seen = Set<String>()
        for node in 1...400 {
            guard let offer = c.rollOldJoker(node), offer.key != "collect" else { continue }
            seen.insert(offer.key)
            let before = (c.coins, c.getRunDeck().count, c.equippedHoldings().count, c.sameCharge, c.jokerDebt)
            let r = c.resolveOldJoker(offer, choice: .decline, nodeId: node)
            XCTAssertNotNil(r, "\(offer.key): declining still reports what happened")
            XCTAssertEqual(before.0, c.coins, "\(offer.key): declining cost coins")
            XCTAssertEqual(before.1, c.getRunDeck().count, "\(offer.key): declining changed the deck")
            XCTAssertEqual(before.2, c.equippedHoldings().count, "\(offer.key): declining moved an item")
            XCTAssertEqual(before.3, c.sameCharge, "\(offer.key): declining touched the shield")
            XCTAssertEqual(before.4, c.jokerDebt, "\(offer.key): declining took on debt")
        }
        XCTAssertGreaterThan(seen.count, 3, "the sweep should meet several different offers")
    }

    // MARK: - 1. Buyout

    func testBuyoutPaysAndTakesTheItem() {
        let c = campaign()
        equipEverything(c)
        guard case .buyout(let cheap, let cheapCoins, let rich, let richCoins)? =
                firstOffer(c, key: "buyout") else { return XCTFail("no buyout offered") }
        XCTAssertGreaterThan(cheapCoins, 0)
        XCTAssertGreaterThan(richCoins, 0)
        let coinsBefore = c.coins
        let held = c.equippedHoldings().count
        _ = c.resolveOldJoker(.buyout(cheap: cheap, cheapCoins: cheapCoins, rich: rich, richCoins: richCoins),
                              choice: .takeRich, nodeId: 1)
        XCTAssertEqual(c.coins, coinsBefore + richCoins, "the rich offer pays what it said")
        XCTAssertEqual(c.equippedHoldings().count, held - 1, "…and takes exactly one holding")
    }

    /// v6.80: EACH offered item independently rolls lowball (1…price) or
    /// premium (2×price…3×price) — so a corpus of buyouts must show all
    /// three mixes (both lowball, both premium, one of each), and every
    /// price must land inside its own item's two legal bands (which never
    /// overlap, so classification is unambiguous).
    func testBuyoutPricesEachItemIndependently() {
        let c = campaign()
        equipEverything(c)
        var lowlow = 0, hihi = 0, mixed = 0, sampled = 0
        for node in 1...1200 {
            guard let o = c.rollOldJoker(node), o.key == "buyout",
                  case .buyout(let a, let aCoins, let b, let bCoins) = o else { continue }
            func classify(_ h: OldJoker.Holding, _ coins: Int) -> Bool? {   // true = premium
                let p = c.holdingDef(h)?.price ?? 1
                if Double(coins) <= p, coins >= 1 { return false }
                if Double(coins) >= 2 * p, Double(coins) <= 3 * p { return true }
                XCTFail("buyout price \(coins) for \(h.id) (price \(p)) is outside both bands")
                return nil
            }
            guard let aHigh = classify(a, aCoins), let bHigh = classify(b, bCoins) else { continue }
            sampled += 1
            switch (aHigh, bHigh) {
            case (true, true): hihi += 1
            case (false, false): lowlow += 1
            default: mixed += 1
            }
        }
        XCTAssertGreaterThan(sampled, 20, "expected a real buyout corpus")
        XCTAssertGreaterThan(lowlow, 0, "both-lowball must occur (~25%)")
        XCTAssertGreaterThan(hihi, 0, "both-premium must occur (~25%)")
        XCTAssertGreaterThan(mixed, 0, "one-of-each must occur (~50%)")
    }

    // MARK: - 2. Swap

    func testSwapReplacesTheItemInTheSameSlot() {
        let c = campaign()
        equipEverything(c)
        guard case .swap(let taken, let given)? = firstOffer(c, key: "swap")
        else { return XCTFail("no swap offered") }
        XCTAssertNotEqual(taken.id, given, "he never leaves the same item behind")
        _ = c.resolveOldJoker(.swap(taken: taken, given: given), choice: .accept, nodeId: 1)
        let slot = taken.kind == .pillar ? c.columnPillars[taken.col!] : c.columnBases[taken.col!]
        XCTAssertEqual(slot, given, "the new item lands in the slot the old one left")
    }

    // MARK: - 3. Purge

    func testPurgeAsksForRemovalsThenCurses() {
        let c = campaign()
        guard case .purge(let removeCount, let curses)? = firstOffer(c, key: "purge")
        else { return XCTFail("no purge offered") }
        let r = c.resolveOldJoker(.purge(removeCount: removeCount, curses: curses),
                                  choice: .accept, nodeId: 1)
        XCTAssertEqual(r?.removeCount, removeCount, "the UI is told how many to pick")
        XCTAssertEqual(r?.curseStickers, curses)
        // The curse half lands on OTHER cards and is seeded per node.
        let hit = c.applyJokerCurses(curses, nodeId: 1)
        XCTAssertEqual(hit.count, curses.count, "every curse found a home")
        for (id, curse) in hit {
            XCTAssertTrue(c.findById(id)?.stickers.contains { $0.type == curse } ?? false,
                          "card \(id) should carry \(curse)")
        }
    }

    func testTheCursesAreDeterministicPerNode() {
        let a = campaign(), b = campaign()
        let ha = a.applyJokerCurses(["leech", "shrink", "mute"], nodeId: 9)
        let hb = b.applyJokerCurses(["leech", "shrink", "mute"], nodeId: 9)
        XCTAssertEqual(ha.map(\.cardId), hb.map(\.cardId))
        XCTAssertEqual(ha.map(\.curse), hb.map(\.curse))
    }

    // MARK: - 4. Ride

    func testRideNeverCarriesYouPastABoss() {
        let c = campaign()
        guard let opening = c.legalNextNodes().first else { return XCTFail("no opening") }
        c.moveToNode(opening.id)
        guard let target = c.nextStoreBeforeBoss() else { return }   // none this run — nothing to assert
        let node = c.getNode(target.id)
        XCTAssertEqual(node?.type, "store", "the ride always ends at a store")
        XCTAssertNotEqual(node?.type, "boss")
    }

    func testRideReportsWhereToTravel() {
        let c = campaign()
        guard let opening = c.legalNextNodes().first else { return XCTFail("no opening") }
        c.moveToNode(opening.id)
        guard let t = c.nextStoreBeforeBoss() else { return }
        let fare = cfg.int("ride", "cost", 5)
        c.addCoins(fare)
        let before = c.getCoins()
        let r = c.resolveOldJoker(.ride(storeNodeId: t.id, skipped: t.skipped, cost: fare),
                                  choice: .accept, nodeId: 1)
        XCTAssertEqual(r?.travelTo, t.id)
        XCTAssertEqual(r?.coins, -fare, "the lift reports its fare")
        XCTAssertEqual(c.getCoins(), before - fare, "…and charges it")
    }

    /// No fare, no lift — the ride must fail before the map starts moving.
    func testRideIsRefusedWithoutTheFare() {
        let c = campaign()
        guard let opening = c.legalNextNodes().first else { return XCTFail("no opening") }
        c.moveToNode(opening.id)
        guard let t = c.nextStoreBeforeBoss() else { return }
        let fare = cfg.int("ride", "cost", 5)
        c.spendCoins(c.getCoins())            // broke
        let r = c.resolveOldJoker(.ride(storeNodeId: t.id, skipped: t.skipped, cost: fare),
                                  choice: .accept, nodeId: 1)
        XCTAssertNil(r, "he does not drive on credit")
        XCTAssertEqual(c.nodePos, opening.id, "…and the player has not moved")
        // He still MAKES the offer while broke — being shown the ride you
        // can't afford is deliberate. The refusal is at the point of choosing,
        // both in the UI (GET IN is dead) and here in resolve.
        XCTAssertTrue(OldJoker.offerKeysEligible(in: c).contains("ride"),
                      "the lift is still offered — you just can't take it")
    }

    // MARK: - 5. Cut

    func testCutFreeBranchTakesACardHeChose() {
        let c = campaign()
        let before = c.getRunDeck().count
        let r = c.resolveOldJoker(.cut(chooseCost: 4), choice: .accept, nodeId: 1)
        XCTAssertEqual(c.getRunDeck().count, before - 1, "one card leaves, free")
        XCTAssertNotNil(r?.cardId, "…and he says which")
        XCTAssertEqual(r?.coins, 0, "his pick costs nothing")
        // The result container needs the CARD, not just its id: the removal
        // deletes the spec from the universe, so it must ride on the Result.
        XCTAssertEqual(r?.cards.count, 1, "the victim's spec is snapshotted for the reveal")
        XCTAssertEqual(r?.cards.first?.id, r?.cardId)
        XCTAssertNil(c.findById(r?.cardId ?? -1),
                     "…because the card itself no longer exists to look up")
    }

    func testCutPaidBranchChargesAndOpensThePicker() {
        let c = campaign()
        c.addCoins(20)
        let before = c.coins, deck = c.getRunDeck().count
        let r = c.resolveOldJoker(.cut(chooseCost: 4), choice: .payToChoose, nodeId: 1)
        XCTAssertEqual(c.coins, before - 4, "paying to choose costs the knob's price")
        XCTAssertEqual(r?.removeCount, 1, "the UI opens a one-card picker")
        XCTAssertEqual(c.getRunDeck().count, deck, "…and nothing has left the deck YET")
    }

    func testCutIsRefusedWhenYouCannotPay() {
        let c = campaign()
        while c.coins > 0 { _ = c.spendCoins(1) }
        XCTAssertNil(c.resolveOldJoker(.cut(chooseCost: 4), choice: .payToChoose, nodeId: 1),
                     "he does not extend credit here")
    }

    // MARK: - 6. Marker + collection

    func testMarkerPaysNowAndRecordsTheDebt() {
        let c = campaign()
        let before = c.coins
        let r = c.resolveOldJoker(.marker(coins: 15, repay: 23), choice: .accept, nodeId: 1)
        XCTAssertEqual(c.coins, before + 15, "the loan lands")
        XCTAssertEqual(c.jokerDebt, 23, "…and the debt is recorded")
        XCTAssertEqual(r?.coins, 15)
    }

    func testAMarkerIsNeverOfferedWhileOneIsOutstanding() {
        let c = campaign()
        c.jokerDebt = 20
        XCTAssertFalse(OldJoker.offerKeysEligible(in: c).contains("marker"),
                       "he only lends once at a time")
    }

    func testHeEventuallyComesToCollectAndThenTheDebtIsSettled() {
        let c = campaign()
        c.jokerDebt = 18
        c.addCoins(100)
        var collected = false
        for node in 1...200 {
            if case .collect(let owed)? = c.rollOldJoker(node) {
                XCTAssertEqual(owed, 18)
                let before = c.coins
                _ = c.resolveOldJoker(.collect(owed: owed), choice: .decline, nodeId: node)
                XCTAssertEqual(c.coins, before - 18, "he takes what he is owed")
                XCTAssertEqual(c.jokerDebt, 0, "…and the debt is settled")
                collected = true
                break
            }
        }
        XCTAssertTrue(collected, "he never came to collect across 200 nodes")
    }

    func testCollectionNeverTakesYouBelowZero() {
        let c = campaign()
        c.jokerDebt = 999
        while c.coins > 3 { _ = c.spendCoins(1) }
        let had = c.coins
        let r = c.resolveOldJoker(.collect(owed: 999), choice: .decline, nodeId: 1)
        XCTAssertEqual(c.coins, 0, "he cannot take more than there is")
        XCTAssertEqual(r?.coins, -had)
        XCTAssertEqual(c.jokerDebt, 0, "the slate is clean either way")
    }

    func testCollectionCannotBeDeclined() {
        // `.decline` on a collect still collects — that is the point of a marker.
        let c = campaign()
        c.jokerDebt = 10
        c.addCoins(50)
        let before = c.coins
        _ = c.resolveOldJoker(.collect(owed: 10), choice: .decline, nodeId: 1)
        XCTAssertEqual(c.coins, before - 10)
    }

    // MARK: - 7. Blind swap

    func testBlindSwapTradesACommonForSomethingBetter() {
        let c = campaign()
        equipEverything(c)
        guard case .blindSwap(let from, let to)? = firstOffer(c, key: "blindSwap")
        else { return XCTFail("no blind swap offered") }
        XCTAssertEqual(c.holdingDef(from)?.tier, cfg.string("blindSwap", "fromTier", "common"),
                       "he only takes a common")
        let toTier = OldJoker.Holding(kind: from.kind, id: to)
        XCTAssertTrue(cfg.strings("blindSwap", "toTiers").contains(c.holdingDef(toTier)?.tier ?? ""),
                      "…and gives back something rarer")
        _ = c.resolveOldJoker(.blindSwap(from: from, to: to), choice: .accept, nodeId: 1)
        if let col = from.col {
            let slot = from.kind == .pillar ? c.columnPillars[col] : c.columnBases[col]
            XCTAssertEqual(slot, to)
        }
    }

    // MARK: - 8. Two doors

    func testTwoDoorsRewardsExactlyOneSide() {
        let c = campaign()
        let offer = OldJoker.Offer.twoDoors(goodKey: "coinBonus", badKey: "coinLoss", goodIsLeft: true)
        let win = c.resolveOldJoker(offer, choice: .left, nodeId: 1)
        XCTAssertEqual(win?.chainedMysteryKey, "coinBonus")
        XCTAssertEqual(win?.good, true)
        let lose = c.resolveOldJoker(offer, choice: .right, nodeId: 1)
        XCTAssertEqual(lose?.chainedMysteryKey, "coinLoss")
        XCTAssertEqual(lose?.good, false)
    }

    func testTwoDoorsSidesAreSeededNotAlwaysLeft() {
        let c = campaign()
        var leftGood = 0, total = 0
        for node in 1...400 {
            if case .twoDoors(_, _, let goodIsLeft)? = c.rollOldJoker(node) {
                total += 1
                if goodIsLeft { leftGood += 1 }
            }
        }
        guard total >= 8 else { return }   // too few samples to assert a split
        XCTAssertGreaterThan(leftGood, 0, "the boon is never on the left")
        XCTAssertLessThan(leftGood, total, "the boon is always on the left")
    }

    func testEveryTwoDoorsOutcomeKeyIsARealMysteryOutcome() {
        for side in ["good", "bad"] {
            let keys = cfg.strings("twoDoors", side)
            XCTAssertFalse(keys.isEmpty, "twoDoors.\(side) must not be empty")
            for k in keys {
                XCTAssertTrue(MysteryConfig.outcomeKeys.contains(k), "\(k) is not a mystery outcome")
            }
        }
    }

    // MARK: - 9. Insurance

    func testInsuranceChargesTheShieldForItsPrice() {
        let c = campaign()
        c.addCoins(10)
        c.setSameCharge(false)
        let before = c.coins
        _ = c.resolveOldJoker(.insurance(cost: 2), choice: .accept, nodeId: 1)
        XCTAssertTrue(c.sameCharge, "the shield is charged")
        XCTAssertEqual(c.coins, before - 2)
    }

    func testInsuranceIsOnlyOfferedWithTheShieldEmpty() {
        let c = campaign()
        c.addCoins(10)
        c.setSameCharge(true)
        XCTAssertFalse(OldJoker.offerKeysEligible(in: c).contains("insurance"),
                       "no point selling cover you already have")
        c.setSameCharge(false)
        XCTAssertTrue(OldJoker.offerKeysEligible(in: c).contains("insurance"))
    }

    // MARK: - 10. Refund

    func testRefundBuysTheChosenItemAtItsOfferedPrice() {
        let c = campaign()
        equipEverything(c)
        let options = Array(c.equippedHoldings().prefix(2))
        let values = [9, 7]
        let target = options[0]
        let before = c.coins
        _ = c.resolveOldJoker(.refund(options: options, values: values), choice: .pick(0), nodeId: 1)
        XCTAssertEqual(c.coins, before + values[0], "paid the OFFER's own price")
        XCTAssertFalse(c.equippedHoldings().contains(target), "…and the item is gone")
    }

    /// The built offer: exactly ONE item (v6.62 — he points at a single
    /// thing, no longer a choice of two), priced minMult–maxMult × its cost.
    func testRefundOffersOneItemAtTwoToThreeTimesItsPrice() {
        let c = campaign()
        equipEverything(c)
        let all = c.equippedHoldings().count
        XCTAssertGreaterThan(all, 1, "setup: more equipped than he points at")
        var seen = false
        for node in 1...200 {
            guard case .refund(let options, let values)? = c.rollOldJoker(node) else { continue }
            seen = true
            XCTAssertEqual(options.count, 1, "node \(node): he points at exactly ONE item")
            XCTAssertEqual(options.count, values.count, "node \(node): one price per item")
            let lo = cfg.num("refund", "minMult", 2), hi = cfg.num("refund", "maxMult", 3)
            for (h, v) in zip(options, values) {
                let price = c.holdingDef(h)?.price ?? 1
                XCTAssertGreaterThanOrEqual(Double(v) + 0.5, price * lo,
                                            "node \(node): \(h.id) under \(lo)× its price")
                XCTAssertLessThanOrEqual(Double(v) - 0.5, price * hi,
                                         "node \(node): \(h.id) over \(hi)× its price")
            }
        }
        XCTAssertTrue(seen, "200 nodes must roll at least one Refund")
    }

    // MARK: - Persistence

    func testTheMarkerDebtSurvivesASaveRoundTrip() {
        let c = campaign()
        _ = c.resolveOldJoker(.marker(coins: 15, repay: 23), choice: .accept, nodeId: 1)
        XCTAssertEqual(c.jokerDebt, 23)
        let c2 = CampaignState()
        XCTAssertTrue(c2.restore(c.serialize()))
        XCTAssertEqual(c2.jokerDebt, 23, "he remembers what you owe across a resume")
    }

    func testAPreOldJokerSaveOwesNothing() {
        let c = campaign()
        var blob = c.serialize()
        blob.removeValue(forKey: "jokerDebt")
        let c2 = CampaignState()
        XCTAssertTrue(c2.restore(blob), "an older save still restores")
        XCTAssertEqual(c2.jokerDebt, 0)
    }

    func testANewClimbClearsTheDebt() {
        let c = campaign()
        c.jokerDebt = 40
        c.startNewRun()
        XCTAssertEqual(c.jokerDebt, 0, "debt does not follow you into a new climb")
    }

    func testCollectionStateSurvivesARoundTripMidDebt() {
        let c = campaign()
        c.jokerDebt = 12
        let c2 = CampaignState()
        XCTAssertTrue(c2.restore(c.serialize()))
        // The same node must make the same decision on both sides of the save.
        for node in 1...60 {
            let a = c.rollOldJoker(node), b = c2.rollOldJoker(node)
            XCTAssertEqual(a?.key, b?.key, "node \(node): collection state diverged across a save")
        }
    }

    /// The modal prints an ITEM KEY — every item an offer names, with its
    /// effect (OldJokerCopy.itemKey). That copy is read from the registry, so
    /// it only works if every holding he can trade actually resolves to a def
    /// WITH a description. A silent nil here is a blank line in the offer.
    func testEveryTradeableHoldingCanDescribeItself() {
        let c = campaign()
        equipEverything(c)
        var checked = 0
        for (kind, ids) in [(OldJoker.Holding.Kind.pillar, data.items.pillars.map(\.id)),
                            (.base, data.items.bases.map(\.id)),
                            (.sticker, data.items.stickers.map(\.id))] {
            for id in ids {
                let h = OldJoker.Holding(kind: kind, id: id)
                guard let def = c.holdingDef(h) else {
                    XCTFail("\(kind.rawValue) '\(id)' resolves to no def — the offer would name it and say nothing")
                    continue
                }
                XCTAssertFalse(def.label.isEmpty, "\(kind.rawValue) '\(id)' has no label")
                XCTAssertFalse(def.description.isEmpty,
                               "\(kind.rawValue) '\(id)' has no description — the item key would print a blank")
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 50, "the sweep should cover the whole registry")
    }

    /// The mystery PURGE states the deal plainly — no "free" dressing on an
    /// outcome the player is required to see through.
    func testPurgeOutcomeCopy() {
        let c = campaign()
        guard let o = c.applyMysteryEvent("freeRemoval", nodeId: 1) else {
            XCTFail("freeRemoval should produce an outcome"); return
        }
        XCTAssertEqual(o.title, "Purge")
        XCTAssertEqual(o.desc, "Purge a card from the deck")
        XCTAssertFalse(o.desc.lowercased().contains("free"),
                       "the word 'free' is gone — it is not a bonus, it is a cost you choose")
    }

    // MARK: - 12. Free shop

    func testFreeShopTakesTheItemAndCompsTheNextShelf() {
        let c = campaign()
        equipEverything(c)
        guard case .freeShop(let taken, _)? = firstOffer(c, key: "freeShop")
        else { return XCTFail("no freeShop offered") }
        let held = c.equippedHoldings().count
        _ = c.resolveOldJoker(.freeShop(taken: taken, currentPrice: 3), choice: .accept, nodeId: 1)
        XCTAssertEqual(c.equippedHoldings().count, held - 1, "he takes exactly the item he named")
        XCTAssertTrue(c.freeShopPending, "…and the comp is armed")
        // Every shelf kind is free EXCEPT the Purge slot.
        for kind in ["sticker", "pillar", "base", "samepower", "pack", "card"] {
            XCTAssertTrue(c.freeShopCovers(kind), "\(kind) should be comped")
        }
        XCTAssertFalse(c.freeShopCovers("removal"),
                       "Purge still charges — a free repeatable delete would strip the deck")
        // The item accessors themselves must read 0, not just the shelf label:
        // every buy path charges through these.
        XCTAssertEqual(c.priceOfPillar(data.items.pillars[0].id), 0)
        XCTAssertEqual(c.priceOfBase(data.items.bases[0].id), 0)
        XCTAssertGreaterThan(c.removalPrice(), 0, "the Purge slot still costs")
        c.endFreeShop()
        XCTAssertGreaterThan(c.priceOfPillar(data.items.pillars[0].id), 0, "prices come back")
    }

    // MARK: - 13. Purge reset

    func testPurgeResetWindsTheLadderBack() {
        let c = campaign()
        c.addCoins(200)
        let base = c.removalPrice()
        _ = c.buyRemoval(c.getRunDeck().first!.id)
        _ = c.buyRemoval(c.getRunDeck().first!.id)
        let climbed = c.removalPrice()
        XCTAssertGreaterThan(climbed, base, "the ladder climbed")
        _ = c.resolveOldJoker(.purgeReset(from: Int(climbed), to: Int(climbed) / 2, cost: 0),
                              choice: .accept, nodeId: 1)
        // He HALVES it now rather than resetting it…
        XCTAssertLessThan(c.removalPrice(), climbed, "the price came down")
        XCTAssertLessThanOrEqual(c.removalPrice(), (climbed / 2) + 1, "…to about half")
        // …and every future step is steeper for the rest of the climb.
        let afterOne = c.removalPrice()
        _ = c.buyRemoval(c.getRunDeck().first!.id)
        XCTAssertGreaterThan(c.removalPrice() - afterOne,
                             GameData.shared.items.store.removal.priceStep - 0.01,
                             "the ladder climbs faster after the bargain")
    }

    /// v6.62: halving an ODD price rounds UP (9 → 5), so the offer never
    /// quotes a number the charge then undercuts.
    func testPurgeHalvingRoundsAnOddPriceUp() {
        let c = campaign()
        c.addCoins(200)
        // v6.98 ladder (base 3, step 1): TWO removals put the rung at 5 — odd.
        _ = c.buyRemoval(c.getRunDeck().first!.id)
        _ = c.buyRemoval(c.getRunDeck().first!.id)
        let before = Int(c.removalPrice())
        XCTAssertEqual(before % 2, 1,
                       "setup: the ladder must sit on an ODD rung here (base + step×1) — if a data retune changed the parity, this test needs a new setup")
        guard before % 2 == 1 else { return }
        let r = c.resolveOldJoker(.purgeReset(from: before, to: (before + 1) / 2, cost: 0),
                                  choice: .accept, nodeId: 1)
        XCTAssertNotNil(r)
        XCTAssertEqual(Int(c.removalPrice()), (before + 1) / 2,
                       "half of an odd price rounds UP: \(before) → \((before + 1) / 2), not \(before / 2)")
        XCTAssertTrue(r?.detail.contains("\((before + 1) / 2)") ?? false,
                      "the return line quotes the price actually charged")
    }

    // MARK: - 14. Eights

    func testEightsFlattensAcesAndTwosAndPaysNothing() {
        let c = campaign()
        let from = Set(c.eightsFromRanks())
        let before = c.getRunDeck().filter { !$0.joker && from.contains($0.currentRank) }.count
        XCTAssertGreaterThan(before, 0, "the starting deck should hold some")
        let jokers = c.getRunDeck().filter(\.joker).count
        let size = c.deckSize()
        let r = c.resolveOldJoker(.eights(from: c.eightsFromRanks(), to: 8, affected: before),
                                  choice: .accept, nodeId: 1)
        XCTAssertEqual(c.getRunDeck().filter { !$0.joker && from.contains($0.currentRank) }.count, 0,
                       "every Ace and 2 is gone")
        // He pays NOTHING for it — the flatter deck is the entire offer.
        XCTAssertEqual(c.getRunDeck().filter(\.joker).count, jokers, "no Joker is handed over")
        XCTAssertEqual(c.deckSize(), size, "…and the deck does not grow")
        // The result container shows the flattened cards — every changed spec
        // rides on the Result, already at its new rank.
        XCTAssertEqual(r?.cards.count, before, "one snapshot per changed card")
        XCTAssertTrue(r?.cards.allSatisfy { $0.currentRank == 8 } ?? false,
                      "the snapshots carry the post-change rank")
    }

    // MARK: - 15/16. Thirsty, and the drink returned

    /// The first node (scanning a wide id range) where the pending drink is
    /// settled. The return is a per-node `returnChance` roll, so "eventually,
    /// not at a particular node" is the contract under test.
    private func firstThirstReturn(_ c: CampaignState, in range: Range<Int>) -> OldJoker.Offer? {
        for node in range {
            if case .thirstReturn? = c.rollOldJoker(node) { return c.rollOldJoker(node) }
        }
        return nil
    }

    func testThirstyTakesWhatYouGiveAndBringsHimBackEventually() {
        let c = campaign()
        c.addCoins(20)
        let before = c.getCoins()
        _ = c.resolveOldJoker(.thirsty(purse: before), choice: .give(4), nodeId: 1)
        XCTAssertEqual(c.getCoins(), before - 4, "he took exactly what was offered")
        XCTAssertTrue(c.jokerThirstPending)
        XCTAssertEqual(c.jokerThirstCoins, 4)
        // He returns on a per-node roll — every "?" is a chance, none a promise.
        guard case .thirstReturn(let paid, let reward)? = firstThirstReturn(c, in: 2..<400) else {
            return XCTFail("across 398 nodes the return roll must land")
        }
        XCTAssertEqual(paid, 4)
        XCTAssertEqual(reward, 4 * cfg.int("thirsty", "rewardMult", 2))
        // The old contract was "waiting at the very next node, whatever the
        // roll says" — i.e. EVERY node settles it. The new one settles only
        // returnChance of them, so across 200 nodes: some do, most don't.
        var returns = 0
        for node in 2..<202 {
            if case .thirstReturn? = c.rollOldJoker(node) { returns += 1 }
            // While the drink is unsettled he never asks for a SECOND one.
            if case .thirsty? = c.rollOldJoker(node) {
                XCTFail("node \(node): he asked for a second drink while one is pending")
            }
        }
        XCTAssertGreaterThan(returns, 0, "the roll must land somewhere")
        XCTAssertLessThan(returns, 150, "a guaranteed return at every node is the OLD behaviour")
    }

    func testGivingNothingBringsHimBackAngryEventually() {
        let c = campaign()
        c.addCoins(20)   // a FUNDED purse — the empty purse is the charity branch
        _ = c.resolveOldJoker(.thirsty(purse: c.getCoins()), choice: .give(0), nodeId: 1)
        XCTAssertTrue(c.jokerThirstPending)
        XCTAssertEqual(c.jokerThirstCoins, 0)
        guard case .thirstReturn(let paid, _)? = firstThirstReturn(c, in: 2..<400) else {
            return XCTFail("across 398 nodes the return roll must land")
        }
        XCTAssertEqual(paid, 0)
        let r = c.resolveOldJoker(.thirstReturn(paid: 0, reward: 0), choice: .accept, nodeId: 78)
        XCTAssertEqual(r?.good, false, "no drink, no gifts")
        XCTAssertFalse(c.jokerThirstPending, "the score is settled either way")
    }

    /// v6.81: an EMPTY purse is its own branch — he hands YOU the charity
    /// coins, arms NO comeback, and no ambush ever follows. Distinct from
    /// the funded-but-refused branch, which still brings him back angry.
    func testThirstyEmptyPurseGetsCharityAndNoComeback() {
        let c = campaign()
        _ = c.spendCoins(c.getCoins())
        XCTAssertEqual(c.getCoins(), 0)
        let charity = cfg.int("thirsty", "charity", 3)
        let r = c.resolveOldJoker(.thirsty(purse: 0), choice: .give(0), nodeId: 1)
        XCTAssertEqual(r?.good, true, "shared hard luck, not a refusal")
        XCTAssertEqual(c.getCoins(), charity, "he hands over the charity coins")
        XCTAssertFalse(c.jokerThirstPending, "no comeback is armed")
        XCTAssertEqual(c.jokerThirstCoins, 0)
        // No return — and so no retaliatory ambush — across a long horizon.
        for node in 2..<400 {
            if case .thirstReturn? = c.rollOldJoker(node) {
                return XCTFail("node \(node): he came back about a drink nobody owed")
            }
        }
        // Even ASKING to give from an empty purse lands in the charity
        // branch (there is nothing to take).
        let c2 = campaign()
        _ = c2.spendCoins(c2.getCoins())
        _ = c2.resolveOldJoker(.thirsty(purse: 0), choice: .give(999), nodeId: 1)
        XCTAssertEqual(c2.getCoins(), charity, "an empty purse cannot be drawn on")
        XCTAssertFalse(c2.jokerThirstPending)
    }

    func testHeCannotBeGivenMoreThanYouHold() {
        // A FUNDED purse clamps at what it holds (the empty purse is the
        // charity branch above).
        let c = campaign()
        c.addCoins(7)
        let held = c.getCoins()
        XCTAssertGreaterThan(held, 0)
        _ = c.resolveOldJoker(.thirsty(purse: held), choice: .give(999), nodeId: 1)
        XCTAssertEqual(c.getCoins(), 0, "he takes everything you hold, never more")
        XCTAssertEqual(c.jokerThirstCoins, held, "…and remembers exactly what he got")
    }

    /// THE COAT IS A SHELF: 1–6 rows, never a duplicate, never something you
    /// already have equipped, and a bigger debt buys a WIDER shelf.
    func testTheCoatShelfIsCappedAndScalesWithTheDebt() {
        let c = campaign()
        for budget in [1, 2, 4, 8, 12, 20, 60] {
            let gifts = c.rollThirstGifts(budget: budget, nodeId: 5)
            XCTAssertLessThanOrEqual(gifts.count, 6, "budget \(budget): never more than six rows")
            XCTAssertGreaterThanOrEqual(gifts.count, 1, "budget \(budget): always something")
            let keys = gifts.map { "\($0.kind.rawValue).\($0.id)" }
            XCTAssertEqual(Set(keys).count, keys.count, "budget \(budget): no duplicate rows")
            let value = gifts.reduce(0) { $0 + c.jokerRefundValue($1) }
            XCTAssertLessThanOrEqual(value, budget, "budget \(budget): he never overspends")
        }
        // v7.06: a LARGE debt reads as VARIETY, not a value-floored stack of
        // pillars. It fills all six rows and spreads across classes — the old
        // tier floor (dropped here) collapsed a heavy debt to the deck's one or
        // two rare pillars.
        let rich = c.rollThirstGifts(budget: 20, nodeId: 9)
        XCTAssertEqual(rich.count, 6, "a heavy debt fills the whole shelf")
        XCTAssertGreaterThan(Set(rich.map { $0.kind }).count, 1,
                             "a heavy debt is paid in a MIX of classes, not pillars alone")
        XCTAssertNotEqual(Set(rich.map { $0.kind }), [.pillar],
                          "…and never pillars-only (the v7.06 fix)")
        // …and the roll still replays for the same node.
        XCTAssertEqual(rich, c.rollThirstGifts(budget: 20, nodeId: 9))
    }

    /// Nothing already equipped is ever in the coat.
    func testTheCoatSkipsWhatYouAlreadyHave() {
        let c = campaign()
        equipEverything(c)
        let gifts = c.rollThirstGifts(budget: 30, nodeId: 3)
        for g in gifts {
            XCTAssertFalse(c.isEquipped(kind: g.kind.rawValue, id: g.id),
                           "\(g.id) is already on the board")
        }
    }

    /// The shelf itself: free, unrerollable, and no Purge slot.
    func testGiftShelfIsAFreeUnrerollableShelf() {
        let c = campaign()
        let gifts = c.rollThirstGifts(budget: 10, nodeId: 4)
        c.openGiftShelf(gifts)
        XCTAssertTrue(c.isGiftShelf)
        XCTAssertEqual(c.getStoreOffer()?.slots.count, gifts.count)
        XCTAssertFalse(c.canReroll(), "his coat does not refresh")
        XCTAssertFalse(c.getStoreOffer()!.slots.contains { $0?.kind == "removal" },
                       "a gift shelf carries no Purge slot")
        for i in 0..<gifts.count {
            XCTAssertEqual(c.priceOfMixed(i), 0, "row \(i) is free")
        }
        c.endFreeShop()
        XCTAssertFalse(c.isGiftShelf, "the coat closes with the visit")
    }

    func testTheDrinkComesBackAsItemsWorthDouble() {
        let c = campaign()
        let gifts = c.rollThirstGifts(budget: 6, nodeId: 3)
        XCTAssertFalse(gifts.isEmpty, "6 coins of drink should buy something")
        let value = gifts.reduce(0) { $0 + c.jokerRefundValue($1) }
        XCTAssertLessThanOrEqual(value, 6, "he never overpays the budget")
        XCTAssertEqual(gifts, c.rollThirstGifts(budget: 6, nodeId: 3), "…and the roll replays")
        XCTAssertTrue(c.rollThirstGifts(budget: 0, nodeId: 3).isEmpty, "no drink, no coat")
    }

    // MARK: - 17. Duplicate

    func testDuplicateCopiesStickersAddsTheMarkAndReplacesACard() {
        let c = campaign()
        let deck = c.getRunDeck()
        guard let source = deck.first(where: { !$0.joker && !$0.blank }),
              let victim = deck.last(where: { !$0.joker && $0.id != source.id })
        else { return XCTFail("need two ordinary cards") }
        _ = c.applySticker(source.id, "rankUp")     // give the original something to inherit
        let sourceStickers = c.getRunDeck().first { $0.id == source.id }?.stickers.count ?? 0
        let size = c.deckSize()
        guard let newId = c.applyJokerDuplicate(sourceId: source.id, replaceId: victim.id,
                                                sticker: "leech") else {
            return XCTFail("the duplicate should apply")
        }
        let after = c.getRunDeck()
        XCTAssertEqual(c.deckSize(), size, "a substitution, not a growth")
        XCTAssertNil(after.first { $0.id == victim.id }, "the replaced card is gone")
        guard let copy = after.first(where: { $0.id == newId }) else {
            return XCTFail("the copy should be in the deck")
        }
        XCTAssertEqual(copy.suit, source.suit)
        XCTAssertEqual(copy.currentRank, c.getRunDeck().first { $0.id == source.id }?.currentRank)
        XCTAssertEqual(copy.stickers.count, sourceStickers + 1, "inherits its stickers, plus the mark")
        XCTAssertTrue(copy.stickers.contains { $0.type == "leech" }, "…and the mark is the Leech")
        XCTAssertNotNil(after.first { $0.id == source.id }, "the original stays put")
        XCTAssertNil(c.applyJokerDuplicate(sourceId: -1, replaceId: victim.id, sticker: "leech"),
                     "an unknown source is refused")
    }

    /// DEBUG ARMING: the picked offer takes the very next node, bypassing both
    /// the appearance roll and eligibility, and is spent once.
    func testDebugForcedOfferTakesTheNextNodeExactlyOnce() {
        let c = campaign()
        equipEverything(c)
        c.addCoins(50)
        // Arming PRIMES the state each offer needs, so every key must actually
        // produce ITS offer. The only excusable miss is the Ride, which needs a
        // shop ahead on the map and can't be conjured.
        for key in OldJokerConfig.offerKeys {
            c.debugForceJoker(key)
            let offer = c.rollOldJoker(4242)
            if key == "ride", c.nextStoreBeforeBoss() == nil {
                XCTAssertNil(offer, "ride: no shop ahead, so nothing to build")
                XCTAssertEqual(c.debugForcedJokerKey, key, "…and it stays armed")
                XCTAssertTrue(c.debugForcedJokerBlocked, "…and reports why")
                c.debugForceJoker(nil)
                continue
            }
            XCTAssertEqual(offer?.key, key, "\(key): armed but got \(offer?.key ?? "nothing")")
            XCTAssertNil(c.debugForcedJokerKey, "\(key): a BUILT offer spends the arm")
        }
        // The visits he makes on his own terms are reachable too.
        c.debugForceJoker("collect")
        XCTAssertEqual(c.rollOldJoker(7)?.key, "collect")
        c.debugForceJoker("thirstReturn")
        XCTAssertEqual(c.rollOldJoker(8)?.key, "thirstReturn")
        c.debugForceJoker("thirstAmbush")
        if case .thirstReturn(let paid, _)? = c.rollOldJoker(9) {
            XCTAssertEqual(paid, 0, "the ambush branch is the unpaid one")
        } else { XCTFail("thirstAmbush should arm a thirstReturn") }
        // Disarmed, the node rolls normally again.
        c.debugForceJoker(nil)
        XCTAssertNil(c.debugForcedJokerKey)
    }

    /// THE REAL TEST OF ARMING: a BARE campaign — nothing equipped, no
    /// removals bought, a full shield. Every offer that doesn't depend on the
    /// map must still build, because arming primes what its builder needs.
    /// Without that priming these silently produced a random mystery instead,
    /// which is exactly what "the debug picker does a random one" looked like.
    func testArmingBuildsEvenFromABareCampaign() {
        for key in OldJokerConfig.offerKeys where key != "ride" {
            let c = campaign()          // nothing equipped, nothing spent
            c.debugForceJoker(key)
            let offer = c.rollOldJoker(101)
            XCTAssertEqual(offer?.key, key,
                           "\(key): bare campaign armed but got \(offer?.key ?? "nothing")")
            XCTAssertFalse(c.debugForcedJokerBlocked, "\(key): should not report blocked")
        }
    }

    // MARK: - Helpers

    /// Sweep nodes until he makes the offer we want to exercise.
    private func firstOffer(_ c: CampaignState, key: String) -> OldJoker.Offer? {
        for node in 1...1200 {
            if let o = c.rollOldJoker(node), o.key == key { return o }
        }
        return nil
    }
}
