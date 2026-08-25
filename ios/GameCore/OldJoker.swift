import Foundation

/// THE OLD JOKER — a worn joker card who sometimes turns up at a mystery ("?")
/// node instead of the plain outcome, speaks, and makes an OFFER.
///
/// Design rules baked into this file:
///  • He always offers; DECLINE is always present and always free, and for
///    several offers declining is the correct play.
///  • His appearance and the whole shape of his offer are seeded from
///    (runSeed, nodeId) on his OWN substream — so a refresh mid-decision
///    replays the identical offer, and adding him never disturbed the byte
///    stream the ordinary mystery outcomes roll on.
///  • Only ELIGIBLE offers are rolled: no equipped items → no Buyout/Swap/
///    Refund; a full Same charge → no Insurance; no store ahead → no Ride.
///  • Every number lives in items.js `oldJoker`; nothing is hardcoded here.
public enum OldJoker {

    /// Which offer he is making. The associated values are everything the UI
    /// needs to draw the offer WITHOUT re-rolling anything.
    public enum Offer: Equatable {
        /// Two of your equipped items, EACH independently priced lowball or
        /// premium (v6.80 — the cheap/rich labels are historical: they mean
        /// "first/second", and either side can carry either kind of price).
        case buyout(cheap: Holding, cheapCoins: Int, rich: Holding, richCoins: Int)
        /// He takes `taken` and leaves `given` behind — shown before you accept.
        case swap(taken: Holding, given: String)
        /// Remove `removeCount` cards you choose; `curses` (pre-rolled from
        /// the shared weighted pool, path "purge") land on as many others.
        case purge(removeCount: Int, curses: [String])
        /// Skip ahead to the next store this stage. Everything between is forfeit.
        case ride(storeNodeId: Int, skipped: Int, cost: Int)
        /// One card leaves: free if he picks, `chooseCost` to pick it yourself.
        case cut(chooseCost: Int)
        /// Coins now, `repay` back when he next comes collecting.
        case marker(coins: Int, repay: Int)
        /// A common item of yours for something better, neither side revealed.
        case blindSwap(from: Holding, to: String)
        /// Two face-down doors; exactly one is the boon.
        case twoDoors(goodKey: String, badKey: String, goodIsLeft: Bool)
        /// Charge the empty Same shield for `cost`.
        case insurance(cost: Int)
        /// He points at up to `count` of your equipped items (rolled, never
        /// the whole loadout) and names a price for EACH — 2–3× what it
        /// cost. The player sells one or walks.
        case refund(options: [Holding], values: [Int])
        /// He is here to collect the marker, not to offer. No decline.
        case collect(owed: Int)
        /// He NAMES one equipped item: hand it over and the next store visit
        /// is on him, until you refresh that shelf.
        case freeShop(taken: Holding, currentPrice: Int)
        /// Wind the Purge slot's price ladder back to its base price.
        case purgeReset(from: Int, to: Int, cost: Int)
        /// A Joker, and every card at one of `from` becomes `to`.
        case eights(from: [Int], to: Int, affected: Int)
        /// Drink money — the player names the amount, zero included.
        case thirsty(purse: Int)
        /// He comes back for what the drink bought (or didn't).
        case thirstReturn(paid: Int, reward: Int)
        /// Copy a card of your choosing; the copy carries `sticker` and
        /// replaces another card you pick.
        case duplicate(sticker: String)
        /// EVERY equipped Pillar leaves; a ★ Joker joins the deck. Only
        /// offered with at least one Pillar up and joker-cap room.
        case jokerForPillars(pillars: [Holding])

        /// The stable key used for weights, telemetry and the UI's art/copy.
        public var key: String {
            switch self {
            case .buyout: return "buyout"
            case .swap: return "swap"
            case .purge: return "purge"
            case .ride: return "ride"
            case .cut: return "cut"
            case .marker: return "marker"
            case .blindSwap: return "blindSwap"
            case .twoDoors: return "twoDoors"
            case .insurance: return "insurance"
            case .refund: return "refund"
            case .collect: return "collect"
            case .freeShop: return "freeShop"
            case .purgeReset: return "purgeReset"
            case .eights: return "eights"
            case .thirsty: return "thirsty"
            case .thirstReturn: return "thirstReturn"
            case .duplicate: return "duplicate"
            case .jokerForPillars: return "jokerForPillars"
            }
        }
    }

    /// One equipped thing he can point at: a pillar/base in a column slot, or
    /// a sticker sitting in the inventory.
    public struct Holding: Equatable {
        public enum Kind: String { case pillar, base, sticker }
        public var kind: Kind
        public var id: String
        /// Column slot for pillars/bases; nil for stickers.
        public var col: Int?
        public init(kind: Kind, id: String, col: Int? = nil) {
            self.kind = kind; self.id = id; self.col = col
        }
    }

    /// What the player chose. `decline` is always legal except on `collect`.
    public enum Choice: Equatable {
        case decline
        /// Buyout: take the low offer or the high one.
        case takeCheap, takeRich
        /// The single-accept offers (swap / purge / ride / marker / blindSwap /
        /// insurance) and Cut's free branch.
        case accept
        /// Cut: pay to choose the card yourself.
        case payToChoose
        /// Two Doors: left or right.
        case left, right
        /// Refund: sell the holding at this index of `options`.
        case pick(Int)
        /// Thirsty: hand him this many coins (0 is a legal, and pointed, answer).
        case give(Int)
    }

    /// What actually happened, for the UI to animate and narrate.
    public struct Result: Equatable {
        public var key: String
        public var headline: String
        public var detail: String
        /// Coins moved (positive in, negative out).
        public var coins: Int = 0
        /// A holding that left the player.
        public var lost: Holding?
        /// EVERYTHING that left the player, when one offer takes several
        /// (A Star for Your Flags strips every equipped Pillar) — the closing
        /// modal's GAVE side needs the whole list, not just one.
        public var lostMany: [Holding] = []
        /// An item id that arrived.
        public var gained: String?
        /// Cards the player must now choose to remove (the UI opens a picker).
        public var removeCount: Int = 0
        /// Cards that got leeched, resolved after the removal picker.
        public var leechCount: Int = 0
        public var leechSticker: String?
        /// PURGE's pre-rolled curses — one per afflicted card, in land order.
        public var curseStickers: [String]?
        /// Ride: where to teleport to.
        public var travelTo: Int?
        /// Two Doors / Cut-free: a mystery outcome key to run afterwards.
        public var chainedMysteryKey: String?
        /// Cut-free: the card he took.
        public var cardId: Int?
        /// SNAPSHOTS of the cards the result touched (cut victims, Eights'
        /// flattened ranks, the minted ★) — captured at resolve time because
        /// a removed card leaves the universe and can't be looked up later.
        /// The closing modal draws these in the shared result container.
        public var cards: [CardSpec] = []
        /// The drink returned: how much SELL value his coat is worth this visit.
        public var giftBudget: Int = 0
        public var good: Bool = true
    }
}

// MARK: - Rolling the offer

extension CampaignState {

    /// Does the Old Joker take this mystery node, and with what offer?
    /// Deterministic per (runSeed, nodeId); nil = the ordinary mystery runs.
    ///
    /// Collection outranks everything: if a marker is outstanding and his
    /// collect roll hits, he is here for the money, not to deal.
    public func rollOldJoker(_ nodeId: Int) -> OldJoker.Offer? {
        let cfg = data.items.oldJoker
        let rng = RNG(seed: mysterySeed(seed: runSeed, nodeId: nodeId, salt: oldJokerSalt))

        // DEBUG: an armed key takes THIS node, bypassing both the appearance
        // roll and the eligibility filter — the point is to reach an offer you
        // can't easily set up for. One-shot: it clears whether or not the
        // offer could actually be built (an unbuildable one, e.g. a Swap with
        // nothing equipped, falls through to the ordinary mystery).
        if let forced = debugForcedJokerKey {
            if forced == "collect" {
                debugForcedJokerKey = nil
                return .collect(owed: max(1, jokerDebt))
            }
            if forced == "thirstReturn" {
                debugForcedJokerKey = nil
                let paid = max(1, jokerThirstCoins)
                return .thirstReturn(paid: paid, reward: paid * cfg.int("thirsty", "rewardMult", 2))
            }
            if forced == "thirstAmbush" {
                debugForcedJokerKey = nil
                return .thirstReturn(paid: 0, reward: 0)
            }
            if let built = buildOffer(forced, rng: rng) {
                debugForcedJokerKey = nil
                return built
            }
            // It could NOT be built in this state — a Swap with nothing
            // equipped, a Ride with no shop ahead. Staying armed is the useful
            // behaviour: clearing it silently handed back a random mystery and
            // looked exactly like the arming had done nothing at all.
            debugForcedJokerBlocked = true
            return nil
        }

        // 1. Outstanding marker? He may be waiting. The player is never told
        //    these odds — the warning at loan time is the only signal.
        if jokerDebt > 0 {
            let collectChance = cfg.num("marker", "collectChance", 0.2)
            if rng.next() < collectChance {
                return .collect(owed: jokerDebt)
            }
        }
        // 2. He is OWED a drink, or owes you one. He settles it eventually, but
        //    not on a schedule: every mystery node rolls `returnChance` until
        //    the one where he turns up — so buying the drink is a bet on WHEN,
        //    not just whether.
        if jokerThirstPending {
            if rng.next() < cfg.num("thirsty", "returnChance", 0.25) {
                let paid = jokerThirstCoins
                return .thirstReturn(paid: paid,
                                     reward: paid * cfg.int("thirsty", "rewardMult", 2))
            }
        }
        // 3. Otherwise the CHARACTER roll decides who takes the node: his
        //    share of mystery.characterWeights (40 / (40+30+30) by default).
        //    Losing this roll hands the node to the Queen or the Two — their
        //    split happens in rollMysteryEvent, on ITS own stream.
        let cw = data.items.mystery.characterWeights
        let jokerW = max(0, cw["oldJoker"] ?? 0)
        let othersW = max(0, cw["queen"] ?? 0) + max(0, cw["two"] ?? 0)
        let totalW = jokerW + othersW
        guard totalW > 0, rng.next() < jokerW / totalW else { return nil }

        // 4. Weighted pick over the offers that are ELIGIBLE right now.
        let eligible = OldJoker.offerKeysEligible(in: self)
        guard !eligible.isEmpty else { return nil }
        var total = 0.0
        for k in eligible { total += max(0, cfg.weights[k] ?? 0) }
        guard total > 0 else { return nil }
        var roll = rng.next() * total
        var picked = eligible[eligible.count - 1]
        for k in eligible {
            roll -= max(0, cfg.weights[k] ?? 0)
            if roll < 0 { picked = k; break }
        }
        return buildOffer(picked, rng: rng)
    }

    /// The offers whose preconditions hold right now, in `offerKeys` order.
    static func offerKeysEligibleList(_ c: CampaignState) -> [String] {
        OldJoker.offerKeysEligible(in: c)
    }

    // MARK: Offer construction

    private func buildOffer(_ key: String, rng: RNG) -> OldJoker.Offer? {
        let cfg = data.items.oldJoker
        switch key {
        case "buyout":
            // TWO different holdings, EACH priced by its OWN independent roll
            // (v6.80): `premiumChance` (items.js oldJoker.buyout, 0.5) of a
            // premium offer (highMinMult..highMaxMult × the item's price),
            // else a lowball (lowMin..lowMaxMult × price). So one-of-each
            // 50%, both lowball 25%, both premium 25%. The enum's cheap/rich
            // labels are just "first/second" now — either side can be either.
            var pool = equippedHoldings()
            guard pool.count >= 1 else { return nil }
            let premiumChance = cfg.num("buyout", "premiumChance", 0.5)
            func rollPrice(for h: OldJoker.Holding) -> Int {
                let p = holdingPrice(h)
                if rng.next() < premiumChance {
                    let lo = p * cfg.num("buyout", "highMinMult", 2)
                    let hi = p * cfg.num("buyout", "highMaxMult", 3)
                    return Int(max(1, (lo + rng.next() * max(0, hi - lo)).rounded()))
                }
                let lowMin = cfg.num("buyout", "lowMin", 1)
                return Int(max(lowMin, (lowMin + rng.next()
                    * max(0, p * cfg.num("buyout", "lowMaxMult", 1) - lowMin)).rounded()))
            }
            let a = pool.remove(at: rng.index(pool.count))
            // With only ONE thing to point at he names ONE price — a single
            // independent roll, lowball or premium alike.
            guard !pool.isEmpty else {
                let only = rollPrice(for: a)
                return .buyout(cheap: a, cheapCoins: only, rich: a, richCoins: only)
            }
            let b = pool.remove(at: rng.index(pool.count))
            return .buyout(cheap: a, cheapCoins: rollPrice(for: a), rich: b, richCoins: rollPrice(for: b))

        case "swap":
            let pool = equippedHoldings().filter { $0.kind != .sticker }
            guard let taken = pool[safe: rng.index(max(1, pool.count))] else { return nil }
            let reg = taken.kind == .pillar ? data.pillarTypes : data.baseTypes
            // Never hand over something already on the board — a straight swap
            // for a duplicate leaves the player holding two of one item and one
            // fewer distinct effect, which is a downgrade dressed as a trade.
            let kindKey = taken.kind.rawValue
            let others = reg.all().filter {
                itemUnlocks.isUnlocked($0) && $0.id != taken.id
                    && !isEquipped(kind: kindKey, id: $0.id)
            }
            guard let given = others[safe: rng.index(max(1, others.count))] else { return nil }
            return .swap(taken: taken, given: given.id)

        case "purge":
            let n = cfg.int("purge", "removeCount", 3)
            let leech = cfg.int("purge", "leechCount", 3)
            guard getRunDeck().count > n + leech else { return nil }
            // WHICH curses land is rolled NOW, with the node rng, so the
            // offer replays identically after a refresh. Path "purge": the
            // shared pool minus its exclusions (no Saboteur here).
            let curses = (0..<leech).compactMap { _ in
                data.stickerTypes.rollCurse(path: "purge", roll: rng.next())?.id
            }
            guard !curses.isEmpty else { return nil }
            // One weighted roll PER card (v6.55: logged so a repeat-heavy
            // purge can be told apart from a single reused roll).
            DebugEventLog.shared.add("purge: curses rolled = [\(curses.joined(separator: ", "))]")
            return .purge(removeCount: n, curses: curses)

        case "ride":
            guard let target = nextStoreBeforeBoss() else { return nil }
            return .ride(storeNodeId: target.id, skipped: target.skipped,
                         cost: cfg.int("ride", "cost", 5))

        case "cut":
            guard getRunDeck().count > 1 else { return nil }
            return .cut(chooseCost: cfg.int("cut", "chooseCost", 4))

        case "marker":
            let lo = cfg.int("marker", "min", 12), hi = cfg.int("marker", "max", 20)
            let coins = lo + rng.index(max(1, hi - lo + 1))
            let repay = Int((Double(coins) * cfg.num("marker", "repayMult", 1.5)).rounded())
            return .marker(coins: coins, repay: repay)

        case "blindSwap":
            let fromTier = cfg.string("blindSwap", "fromTier", "common")
            let commons = equippedHoldings().filter { holdingDef($0)?.tier == fromTier }
            guard let from = commons[safe: rng.index(max(1, commons.count))] else { return nil }
            let toTiers = Set(cfg.strings("blindSwap", "toTiers"))
            let reg = from.kind == .pillar ? data.pillarTypes
                : (from.kind == .base ? data.baseTypes : data.stickerTypes)
            // Same rule blind: he can't secretly hand back a duplicate either.
            let fromKind = from.kind.rawValue
            let better = reg.all().filter {
                toTiers.contains($0.tier) && itemUnlocks.isUnlocked($0)
                    && !isEquipped(kind: fromKind, id: $0.id)
            }
            guard let to = better[safe: rng.index(max(1, better.count))] else { return nil }
            return .blindSwap(from: from, to: to.id)

        case "twoDoors":
            let good = cfg.strings("twoDoors", "good")
            let bad = cfg.strings("twoDoors", "bad")
            guard let g = good[safe: rng.index(max(1, good.count))],
                  let b = bad[safe: rng.index(max(1, bad.count))] else { return nil }
            return .twoDoors(goodKey: g, badKey: b, goodIsLeft: rng.next() < 0.5)

        case "insurance":
            guard !sameCharge else { return nil }
            let cost = cfg.int("insurance", "cost", 2)
            guard coins >= cost else { return nil }
            return .insurance(cost: cost)

        case "refund":
            // ONE item, rolled — never the whole loadout (v6.62: he used to
            // point at two) — at 2–3× the price paid for it.
            var pool = equippedHoldings()
            guard !pool.isEmpty else { return nil }
            let take = min(cfg.int("refund", "count", 1), pool.count)
            var options: [OldJoker.Holding] = []
            var values: [Int] = []
            let lo = cfg.num("refund", "minMult", 2), hi = cfg.num("refund", "maxMult", 3)
            for _ in 0..<take {
                let h = pool.remove(at: rng.index(pool.count))
                options.append(h)
                let mult = lo + rng.next() * max(0, hi - lo)
                values.append(max(1, Int((holdingPrice(h) * mult).rounded())))
            }
            return .refund(options: options, values: values)

        case "freeShop":
            // He names ONE slotted item — a sticker in the inventory isn't
            // something he can point at across a table.
            let slotted = equippedHoldings().filter { $0.kind != .sticker }
            guard let taken = slotted[safe: rng.index(max(1, slotted.count))] else { return nil }
            return .freeShop(taken: taken, currentPrice: Int(holdingPrice(taken)))

        case "purgeReset":
            let now = Int(removalPrice())
            let base = Int(shopPrice(data.items.store.removal.price))
            guard now > base else { return nil }
            // He HALVES what it costs today — an odd price rounds UP (9 → 5),
            // matching applyPurgeHalving's target — and the ladder gets
            // steeper for it.
            return .purgeReset(from: now, to: max(1, (now + 1) / 2), cost: cfg.int("purgeReset", "cost", 0))

        case "eights":
            let affected = eightsAffectedCount()
            guard affected > 0 else { return nil }
            return .eights(from: eightsFromRanks(), to: cfg.int("eights", "to", 8),
                           affected: affected)

        case "thirsty":
            return .thirsty(purse: coins)

        case "duplicate":
            // The copy's curse comes from the shared roll, path "duplicate"
            // (mild band only — the curse is a free card's price, not a trap).
            guard let curse = data.stickerTypes.rollCurse(path: "duplicate", roll: rng.next())
            else { return nil }
            return .duplicate(sticker: curse.id)

        case "jokerForPillars":
            let pillars = columnPillars.enumerated().compactMap { c, id in
                id.map { OldJoker.Holding(kind: .pillar, id: $0, col: c) }
            }
            // Held-vs-cap, NOT jokersAllowed(): a fixed-joker tier turns off
            // RANDOM joker sources, but a trade — like the mystery Wild Card —
            // only needs room under the cap.
            guard !pillars.isEmpty, jokersHeld() < jokerCapFor() else { return nil }
            return .jokerForPillars(pillars: pillars)

        default:
            return nil
        }
    }

    // MARK: Eligibility + helpers

    /// Everything currently equipped that he could point at.
    public func equippedHoldings() -> [OldJoker.Holding] {
        var out: [OldJoker.Holding] = []
        for (c, id) in columnPillars.enumerated() {
            if let id { out.append(OldJoker.Holding(kind: .pillar, id: id, col: c)) }
        }
        for (c, id) in columnBases.enumerated() {
            if let id { out.append(OldJoker.Holding(kind: .base, id: id, col: c)) }
        }
        for (id, n) in stickerInventory.sorted(by: { $0.key < $1.key }) where n > 0 {
            out.append(OldJoker.Holding(kind: .sticker, id: id))
        }
        return out
    }

    public func holdingDef(_ h: OldJoker.Holding) -> ItemDef? {
        switch h.kind {
        case .pillar: return data.pillarTypes.get(h.id)
        case .base: return data.baseTypes.get(h.id)
        case .sticker: return data.stickerTypes.get(h.id)
        }
    }

    func holdingPrice(_ h: OldJoker.Holding) -> Double { holdingDef(h)?.price ?? 1 }

    /// The sale price he pays on a Refund — by tier, from the data file.
    /// The tier value HIS ledger prices a holding at — the store's own SELL
    /// table (items.js `store.sell`). v6.50: this used to read per-tier
    /// fields duplicated inside the refund config; three copies of one table
    /// (UI hardcode, refund config, sell table) are now exactly one.
    public func jokerRefundValue(_ h: OldJoker.Holding) -> Int {
        sellValue(holdingDef(h))
    }

    /// The next STORE node reachable from here that is still before this
    /// stage's boss — the Ride target. Returns the node and how many stops
    /// would be forfeited getting there. nil = nothing to ride to.
    public func nextStoreBeforeBoss() -> (id: Int, skipped: Int)? {
        guard let m = runMap, let posId = nodePos, let here = m.byId[posId] else { return nil }
        // Walk forward breadth-first within THIS stage, stopping at the boss:
        // he never rides you past a boss.
        var frontier = here.next.compactMap { m.byId[$0] }
        var seen = Set<Int>([posId])
        var depth = 0
        while !frontier.isEmpty, depth < 24 {
            depth += 1
            var next: [MapNode] = []
            for n in frontier where !seen.contains(n.id) {
                seen.insert(n.id)
                if n.type == "boss" { continue }          // never past a boss
                if n.type == "store" { return (n.id, max(0, depth - 1)) }
                next.append(contentsOf: n.next.compactMap { m.byId[$0] })
            }
            frontier = next
        }
        return nil
    }
}

extension CampaignState {
    /// The ranks EIGHTS converts (Ace is 14, so it eats your highest and lowest).
    public func eightsFromRanks() -> [Int] {
        let raw = data.items.oldJoker.raw["eights"]?.asObject?["from"]?.asArray ?? []
        let ranks = raw.compactMap { $0.asNumber.map(Int.init) }
        return ranks.isEmpty ? [14, 2] : ranks
    }

    /// How many cards EIGHTS would actually change. Zero means the offer would
    /// be a no-op, and a no-op is not an offer.
    public func eightsAffectedCount() -> Int {
        let from = Set(eightsFromRanks())
        let to = data.items.oldJoker.int("eights", "to", 8)
        return getRunDeck().filter { !$0.joker && !$0.blank && from.contains($0.currentRank) && $0.currentRank != to }.count
    }

}

extension OldJoker {
    /// The offers whose preconditions currently hold, in the fixed key order.
    static func offerKeysEligible(in c: CampaignState) -> [String] {
        let holdings = c.equippedHoldings()
        let slotted = holdings.filter { $0.kind != .sticker }
        let cfg = c.data.items.oldJoker
        let purgeNeed = cfg.int("purge", "removeCount", 3) + cfg.int("purge", "leechCount", 3)
        let fromTier = cfg.string("blindSwap", "fromTier", "common")
        return OldJokerConfig.offerKeys.filter { key in
            switch key {
            case "buyout":    return !holdings.isEmpty
            case "swap":      return !slotted.isEmpty
            case "purge":     return c.getRunDeck().count > purgeNeed
            // He offers the lift whether or not you can cover the fare — being
            // shown the ride you can't afford is the point. The UI refuses the
            // choice (the GET IN button is dead), and `resolve` refuses it too.
            case "ride":      return c.nextStoreBeforeBoss() != nil
            case "cut":       return c.getRunDeck().count > 1
            case "marker":    return c.jokerDebt == 0
            case "blindSwap": return holdings.contains { c.holdingDef($0)?.tier == fromTier }
            case "twoDoors":  return true
            case "insurance": return !c.sameCharge && c.coins >= cfg.int("insurance", "cost", 2)
            // He can only comp a shop you haven't already been comped for,
            // and only if he has something of yours to name.
            case "freeShop":  return !slotted.isEmpty && !c.freeShopPending
            // Nothing to wind back until the ladder has actually climbed.
            case "purgeReset": return c.removalsBought > 0
                                      && c.coins >= cfg.int("purgeReset", "cost", 0)
            // Needs at least one card he would actually change.
            case "eights":    return c.eightsAffectedCount() > 0
            // He'll ask for a drink whether or not you have one to give —
            // being asked with an empty purse is part of it. But never a
            // SECOND drink while the first is still unsettled (reachable now
            // that the return is a per-node roll, not the very next node).
            case "thirsty":   return !c.jokerThirstPending
            case "duplicate": return c.getRunDeck().contains { !$0.joker && !$0.blank }
            case "refund":    return !holdings.isEmpty
            // At least one Pillar to take, and room under the tier's joker cap
            // (held-vs-cap, like the mystery Wild Card — a fixed-joker tier
            // silences random sources, not trades).
            case "jokerForPillars":
                return holdings.contains { $0.kind == .pillar }
                    && c.jokersHeld() < c.jokerCapFor()
            default:          return false
            }
        }
    }
}
