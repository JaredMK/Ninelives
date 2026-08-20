import Foundation

/// Applying the Old Joker's offers. Every mutation the player agreed to happens
/// here and nowhere else, so the UI is pure presentation.
extension CampaignState {

    /// Resolve `offer` with the player's `choice`. Returns what happened, or
    /// nil for a decline that changes nothing (the caller just closes).
    ///
    /// `nodeId` seeds any detail the CHOICE needs (which card he cuts, which
    /// leech targets) — same node, same result, so a refresh can't re-roll it.
    @discardableResult
    public func resolveOldJoker(_ offer: OldJoker.Offer, choice: OldJoker.Choice,
                                nodeId: Int) -> OldJoker.Result? {
        let rng = RNG(seed: mysterySeed(seed: runSeed, nodeId: nodeId, salt: oldJokerResolveSalt))
        let cfg = data.items.oldJoker

        // Declining is ALWAYS free and always changes nothing — except that he
        // never lets you decline a collection.
        if case .decline = choice, offer.key != "collect" {
            return OldJoker.Result(key: offer.key, headline: "You keep walking",
                                   detail: "He watches you go.", good: true)
        }

        switch offer {

        // ── 1. THE BUYOUT ────────────────────────────────────────────────────
        case .buyout(let cheap, let cheapCoins, let rich, let richCoins):
            let take: (OldJoker.Holding, Int)
            switch choice {
            case .takeCheap: take = (cheap, cheapCoins)
            case .takeRich:  take = (rich, richCoins)
            default: return nil
            }
            guard removeHolding(take.0) else { return nil }
            _ = earnCoins(take.1)
            return OldJoker.Result(
                key: "buyout", headline: "Sold",
                detail: "\(holdingLabel(take.0)) is his now.",
                coins: take.1, lost: take.0)

        // ── 2. THE SWAP ──────────────────────────────────────────────────────
        case .swap(let taken, let given):
            guard removeHolding(taken) else { return nil }
            placeHolding(kind: taken.kind, id: given, col: taken.col)
            return OldJoker.Result(
                key: "swap", headline: "Traded",
                detail: "\(holdingLabel(taken)) out, \(labelOf(kind: taken.kind, id: given)) in.",
                lost: taken, gained: given)

        // ── 3. THE PURGE ─────────────────────────────────────────────────────
        // The removal itself is a PICKER the UI drives; the leech lands after.
        case .purge(let removeCount, let curses):
            var r = OldJoker.Result(
                key: "purge", headline: "Pick your three",
                detail: "Then he takes his due.",
                removeCount: removeCount, leechCount: curses.count, good: false)
            r.curseStickers = curses
            return r

        // ── 4. THE RIDE ──────────────────────────────────────────────────────
        case .ride(let storeNodeId, let skipped, let cost):
            // The fare is charged HERE, not on arrival: a lift you couldn't
            // pay for must fail before the map starts moving.
            guard coins >= cost, spendCoins(cost) else { return nil }
            return OldJoker.Result(
                key: "ride", headline: "Get in",
                detail: skipped == 1 ? "One stop passes you by."
                                     : "\(skipped) stops pass you by.",
                coins: -cost, travelTo: storeNodeId)

        // ── 5. THE CUT ───────────────────────────────────────────────────────
        case .cut(let chooseCost):
            switch choice {
            case .accept:
                // He picks — free.
                let deck = getRunDeck()
                guard let victim = deck[safe: rng.index(max(1, deck.count))] else { return nil }
                _ = removeDeckCard(victim.id)
                var r = OldJoker.Result(
                    key: "cut", headline: "His pick",
                    detail: "\(cardName(victim)) purged.",
                    cardId: victim.id, good: false)
                r.cards = [victim]   // snapshotted — the card no longer exists to look up
                return r
            case .payToChoose:
                guard coins >= chooseCost else { return nil }
                _ = spendCoins(chooseCost)
                // removeCount 1 tells the UI to open the picker.
                return OldJoker.Result(
                    key: "cut", headline: "Your pick",
                    detail: "Choose the one that leaves.",
                    coins: -chooseCost, removeCount: 1)
            default: return nil
            }

        // ── 6. THE MARKER ────────────────────────────────────────────────────
        case .marker(let coinsGiven, let repay):
            _ = earnCoins(coinsGiven)
            jokerDebt = repay
            return OldJoker.Result(
                key: "marker", headline: "Take it",
                detail: "He'll want it back with interest. Sometime.",
                coins: coinsGiven)

        // ── 7. THE BLIND SWAP ────────────────────────────────────────────────
        case .blindSwap(let from, let to):
            guard removeHolding(from) else { return nil }
            placeHolding(kind: from.kind, id: to, col: from.col)
            return OldJoker.Result(
                key: "blindSwap", headline: "Done blind",
                detail: "\(holdingLabel(from)) for \(labelOf(kind: from.kind, id: to)).",
                lost: from, gained: to)

        // ── 8. TWO DOORS ─────────────────────────────────────────────────────
        case .twoDoors(let goodKey, let badKey, let goodIsLeft):
            let pickedLeft: Bool
            switch choice {
            case .left: pickedLeft = true
            case .right: pickedLeft = false
            default: return nil
            }
            let won = pickedLeft == goodIsLeft
            let key = won ? goodKey : badKey
            return OldJoker.Result(
                key: "twoDoors", headline: won ? "Good door" : "Wrong door",
                detail: won ? "This one was kind." : "This one was not.",
                chainedMysteryKey: key, good: won)

        // ── 9. INSURANCE ─────────────────────────────────────────────────────
        case .insurance(let cost):
            guard !sameCharge, coins >= cost else { return nil }
            _ = spendCoins(cost)
            sameCharge = true
            return OldJoker.Result(
                key: "insurance", headline: "Covered",
                detail: "The shield hums back to life.", coins: -cost)

        // ── 10. THE REFUND ───────────────────────────────────────────────────
        case .refund(let options, let values):
            guard case .pick(let i) = choice, let h = options[safe: i],
                  let value = values[safe: i] else { return nil }
            guard removeHolding(h) else { return nil }
            _ = earnCoins(value)
            return OldJoker.Result(
                key: "refund", headline: "Bought back",
                detail: "\(holdingLabel(h)) for \(value).",
                coins: value, lost: h)

        // ── COLLECTION ───────────────────────────────────────────────────────
        // Not an offer — he is here for the money. Never takes you below zero,
        // and the debt is settled either way.
        case .collect(let owed):
            let taken = min(coins, owed)
            if taken > 0 { _ = spendCoins(taken) }
            jokerDebt = 0
            return OldJoker.Result(
                key: "collect", headline: "Settled",
                detail: taken >= owed ? "He counts it twice and nods."
                                      : "You're short. He'll accept it this time. Debts are settled.",
                coins: -taken, good: false)

        // ── 12. THE FREE SHOP ────────────────────────────────────────────────
        // He names one slotted item. Hand it over and the NEXT shelf is his
        // treat; the Purge slot still charges, and a refresh ends the comp.
        case .freeShop(let taken, _):
            guard removeHolding(taken) else { return nil }
            freeShopPending = true
            return OldJoker.Result(
                key: "freeShop", headline: "On the house",
                detail: "All items in the next shop are free.",
                lost: taken)

        // ── 13. THE PURGE RESET ──────────────────────────────────────────────
        case .purgeReset(_, _, let cost):
            guard removalsBought > 0 else { return nil }
            guard cost <= 0 || spendCoins(cost) else { return nil }
            let step = cfg.int("purgeReset", "stepIncrease", 1)
            let (from, to) = applyPurgeHalving(stepIncrease: step)
            return OldJoker.Result(
                key: "purgeReset", headline: "Halved",
                detail: "Purge drops from \(from) to \(to). It climbs faster now.",
                coins: -cost)

        // ── 14. THE EIGHTS ───────────────────────────────────────────────────
        // Every Ace and 2 in the deck becomes an 8. Both edges of the deck
        // collapse into the middle — that IS the whole offer; he pays nothing
        // for it, so taking it is a bet on a flatter deck being easier to read.
        case .eights(let from, let to, _):
            let ranks = Set(from)
            var changed: [CardSpec] = []
            for i in baseDeck.indices where ownedIds.contains(baseDeck[i].id) {
                guard !baseDeck[i].joker, !baseDeck[i].blank,
                      ranks.contains(baseDeck[i].currentRank), baseDeck[i].currentRank != to
                else { continue }
                baseDeck[i].currentRank = to
                changed.append(baseDeck[i])
            }
            guard !changed.isEmpty else { return nil }
            var r = OldJoker.Result(
                key: "eights", headline: "Eights",
                detail: "\(changed.count) card\(changed.count == 1 ? "" : "s") flattened to \(to).",
                good: true)
            r.cards = changed   // the flattened cards, shown in the result container
            return r

        // ── 15. THIRSTY ──────────────────────────────────────────────────────
        // He asks for drink money. ANY amount is a legal answer, zero included,
        // and zero is remembered. Either way he comes back at the next mystery.
        case .thirsty:
            guard case .give(let asked) = choice else { return nil }
            let given = max(0, min(asked, coins))
            if given > 0 { _ = spendCoins(given) }
            jokerThirstPending = true
            jokerThirstCoins = given
            return OldJoker.Result(
                key: "thirsty",
                headline: given > 0 ? "Bought" : "Refused",
                detail: given > 0
                    ? "\(given) coin\(given == 1 ? "" : "s") for his drink. He'll find you again."
                    : "You gave him nothing. He'll find you again.",
                coins: -given, good: given > 0)

        // ── 16. THE DRINK, RETURNED ──────────────────────────────────────────
        // Not an offer — a promise being kept. Paid: items worth twice the
        // drink, handed over one at a time. Stiffed: an ambush.
        case .thirstReturn(let paid, let reward):
            jokerThirstPending = false
            jokerThirstCoins = 0
            if paid > 0 {
                return OldJoker.Result(
                    key: "thirstReturn", headline: "Thanks for the drink",
                    detail: "He starts emptying his coat.",
                    giftBudget: reward, good: true)
            }
            return OldJoker.Result(
                key: "thirstReturn", headline: "About that drink",
                detail: "He is not asking this time.",
                good: false)

        // ── 18. A STAR FOR YOUR FLAGS ────────────────────────────────────────
        // Every equipped Pillar comes down; one ★ Joker joins the deck. The
        // eligibility gate (≥1 Pillar, joker-cap room) re-checks here so a
        // stale offer can never overfill the cap.
        case .jokerForPillars(let pillars):
            guard !pillars.isEmpty, jokersHeld() < jokerCapFor() else { return nil }
            var taken = 0
            for p in pillars where removeHolding(p) { taken += 1 }
            guard taken > 0 else { return nil }
            let jid = mintJokerId()
            ownedIds.append(jid)
            var r = OldJoker.Result(
                key: "jokerForPillars", headline: "A star for your flags",
                detail: "\(taken) Pillar\(taken == 1 ? "" : "s") lost; a ★ Joker joins your deck.",
                cardId: jid)
            r.lostMany = pillars   // the GAVE side of the closing trade row
            r.cards = findById(jid).map { [$0] } ?? []   // the star, in the result container
            return r

        // ── 17. THE DUPLICATE ────────────────────────────────────────────────
        // The copy is made by the UI's pickers (choose a card, then choose the
        // card it replaces); resolve only agrees to it.
        case .duplicate(let sticker):
            guard getRunDeck().contains(where: { !$0.joker && !$0.blank }) else { return nil }
            // No detail (v6.52): the offer already said a curse is coming; the
            // pickers carry their own single instruction each.
            return OldJoker.Result(
                key: "duplicate", headline: "Twice over",
                detail: "",
                leechSticker: sticker)
        }
    }

    /// THE DUPLICATE, applied: copy `sourceId` (stickers and all), stamp the
    /// copy with `sticker`, and have it REPLACE `replaceId` in the deck. The
    /// deck's size never moves — this is a substitution, not a growth.
    /// Returns the new card's id.
    @discardableResult
    public func applyJokerDuplicate(sourceId: Int, replaceId: Int, sticker: String) -> Int? {
        guard let si = baseDeck.firstIndex(where: { $0.id == sourceId }),
              !baseDeck[si].joker, !baseDeck[si].blank,
              ownedIds.contains(sourceId), ownedIds.contains(replaceId) else { return nil }
        var copy = baseDeck[si]
        copy.id = nextCardId
        nextCardId += 1
        // The mark rides ON TOP of whatever the original was carrying — a
        // duplicate of a well-built card is strong, and this is its price.
        copy.stickers.append(StickerRecord(type: sticker))
        baseDeck.append(copy)
        guard let ri = ownedIds.firstIndex(of: replaceId) else { return nil }
        ownedIds[ri] = copy.id
        // The replaced card leaves the UNIVERSE too — same rule as every
        // removal: a card that left the run can never be re-offered by a
        // pack or +1 node (v6.49 bugfix).
        if let bi = baseDeck.firstIndex(where: { $0.id == replaceId }) { baseDeck.remove(at: bi) }
        return copy.id
    }

    /// THE DRINK, RETURNED: roll a random assortment of items whose combined
    /// SELL value comes to `budget` (what you gave him, doubled). He pays in
    /// things, not coins, so the budget is spent in item tiers — cheapest tier
    /// last, so a small drink still buys something rather than rounding to
    /// nothing. Seeded per node: a refresh mid-delivery replays the same gifts.
    public func rollThirstGifts(budget: Int, nodeId: Int) -> [OldJoker.Holding] {
        guard budget > 0 else { return [] }
        let rng = RNG(seed: mysterySeed(seed: runSeed, nodeId: nodeId, salt: oldJokerLeechSalt))
        // ANYTHING he could plausibly be carrying — Pillars, Bases and
        // Stickers alike, minus whatever is already on the board.
        var pool: [(OldJoker.Holding, Int)] = []
        for d in data.items.pillars where itemUnlocks.isUnlocked(d)
                && !isEquipped(kind: "pillar", id: d.id) {
            let h = OldJoker.Holding(kind: .pillar, id: d.id)
            pool.append((h, jokerRefundValue(h)))
        }
        for d in data.items.bases where itemUnlocks.isUnlocked(d)
                && !isEquipped(kind: "base", id: d.id) {
            let h = OldJoker.Holding(kind: .base, id: d.id)
            pool.append((h, jokerRefundValue(h)))
        }
        for d in data.items.stickers where !d.cursed && itemUnlocks.isUnlocked(d) {
            let h = OldJoker.Holding(kind: .sticker, id: d.id)
            pool.append((h, jokerRefundValue(h)))
        }
        guard !pool.isEmpty else { return [] }

        // THE SHELF IS 1–6 ITEMS, never more. A bigger debt buys a WIDER shelf
        // first and then a DEARER one: past six items he stops adding rows and
        // starts reaching for costlier things instead. Under-spending the
        // budget is fine and expected — he pays in what he happens to carry.
        let maxRows = min(6, max(1, Int((Double(budget) / 2.0).rounded(.up))))
        // The cheapest tier he'll consider, so a large debt stops offering
        // commons: budget 12+ skips tier-1 items entirely.
        let floorValue = budget >= 12 ? 3 : (budget >= 7 ? 2 : 1)

        var left = budget
        var out: [OldJoker.Holding] = []
        var seen = Set<String>()
        while out.count < maxRows {
            let affordable = pool.filter {
                $0.1 <= left && $0.1 >= min(floorValue, left)
                    && !seen.contains("\($0.0.kind.rawValue).\($0.0.id)")
            }
            guard !affordable.isEmpty else { break }
            // Reach for the DEAREST thing still affordable most of the time, so
            // a heavy debt reads as generosity rather than a pile of commons.
            let sorted = affordable.sorted { $0.1 > $1.1 }
            let topSlice = sorted.prefix(max(1, sorted.count / 3))
            let pick = rng.next() < 0.7
                ? Array(topSlice)[rng.index(topSlice.count)]
                : sorted[rng.index(sorted.count)]
            out.append(pick.0)
            seen.insert("\(pick.0.kind.rawValue).\(pick.0.id)")
            left -= pick.1
        }
        return out
    }

    /// The second half of a PURGE: the player has removed their cards, now the
    /// leech lands on `count` others. Seeded per node, so it replays.
    @discardableResult
    /// PURGE's other half: each pre-rolled curse lands on a DISTINCT random
    /// card that can take it. Node-seeded, so a refresh replays the exact
    /// same afflictions. Returns (cardId, curseId) pairs, in land order.
    public func applyJokerCurses(_ curses: [String], nodeId: Int) -> [(cardId: Int, curse: String)] {
        let rng = RNG(seed: mysterySeed(seed: runSeed, nodeId: nodeId, salt: oldJokerLeechSalt))
        var taken = Set<Int>()
        var hit: [(cardId: Int, curse: String)] = []
        for curse in curses {
            let pool = getRunDeck().filter { !taken.contains($0.id) && canApplySticker($0, curse) }
            guard !pool.isEmpty else { continue }
            let card = pool[rng.index(pool.count)]
            if applyStickerDirect(card.id, curse) {
                taken.insert(card.id)
                hit.append((card.id, curse))
                DebugEventLog.shared.add("curse: \(curse) landed on card #\(card.id)")
            }
        }
        return hit
    }

    // MARK: - Holding mutation

    /// Remove an equipped holding from wherever it sits. False = it moved.
    @discardableResult
    func removeHolding(_ h: OldJoker.Holding) -> Bool {
        switch h.kind {
        case .pillar:
            guard let c = h.col, columnPillars[safe: c] ?? nil == h.id else { return false }
            columnPillars[c] = nil
            return true
        case .base:
            guard let c = h.col, columnBases[safe: c] ?? nil == h.id else { return false }
            columnBases[c] = nil
            return true
        case .sticker:
            guard (stickerInventory[h.id] ?? 0) > 0 else { return false }
            stickerInventory[h.id]! -= 1
            if stickerInventory[h.id] == 0 { stickerInventory[h.id] = nil }
            return true
        }
    }

    public func placeHolding(kind: OldJoker.Holding.Kind, id: String, col: Int?) {
        switch kind {
        case .pillar: if let c = col, c < columnPillars.count { columnPillars[c] = id }
        case .base:   if let c = col, c < columnBases.count { columnBases[c] = id }
        case .sticker: stickerInventory[id, default: 0] += 1
        }
    }

    public func holdingLabel(_ h: OldJoker.Holding) -> String { holdingDef(h)?.label ?? h.id }

    public func labelOf(kind: OldJoker.Holding.Kind, id: String) -> String {
        holdingLabel(OldJoker.Holding(kind: kind, id: id))
    }

}
