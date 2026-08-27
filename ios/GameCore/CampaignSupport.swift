import Foundation

/// Board layouts. `cols` is the column-size array; `piles` is their sum; `rows`
/// is the tallest column. Plain data — the renderer maps it to grid positions.
public struct BoardLayout: Sendable, Equatable {
    public let cols: [Int]
    public let piles: Int
    public let rows: Int
}

public enum CampaignLayout {
    /// Column sizes per run index (1-based).
    public static let runLayouts: [[Int]] = [[3, 3, 3], [3, 4, 3], [4, 4, 4], [4, 5, 4]]
    public static let maxStages = 3
    public static let maxRunsPerStage = 4
    public static let columnSlots = runLayouts[0].count
    public static let totalRuns = maxStages * maxRunsPerStage

    public static func layoutForRun(_ runIndex: Int) -> BoardLayout {
        let i = min(max(runIndex, 1), runLayouts.count) - 1
        let cols = runLayouts[i]
        return BoardLayout(cols: cols, piles: cols.reduce(0, +), rows: cols.max() ?? 0)
    }

    /// The board layout with the equipped Pillars applied. A `columnPiles`
    /// Pillar (Fourth Seat) adds ONE seat to its column, capped at `value` —
    /// so a 1-pile column opens with 2 and a column already at the cap is left
    /// alone. It only ever adds; the balanced split runs first.
    ///
    /// DITTO is resolved here too. It mirrors the centre column's Pillar, and
    /// mirroring a Fourth Seat has to widen the mirroring column as well —
    /// the engine resolved Ditto for every OTHER effect but the layout didn't,
    /// so a Ditto beside a Fourth Seat silently got no extra pile.
    public static func layoutForPiles(_ n0: Int, pillars: [String?],
                                      data: GameData = .shared) -> BoardLayout {
        var cols = layoutForPiles(n0).cols
        guard !cols.isEmpty else { return layoutForPiles(n0) }
        let center = pillars.count / 2
        func effectiveDef(_ c: Int) -> ItemDef? {
            guard let id = pillars[safe: c] ?? nil, let def = data.pillarTypes.get(id) else { return nil }
            guard def.effect == "ditto" else { return def }
            // Ditto at/in the centre mirrors nothing, and never another Ditto.
            guard c != center, let cid = pillars[safe: center] ?? nil,
                  let cdef = data.pillarTypes.get(cid), cdef.effect != "ditto" else { return nil }
            return cdef
        }
        for c in 0..<cols.count {
            guard let def = effectiveDef(c), def.effect == "columnPiles" else { continue }
            let cap = max(1, Int(def.value))
            // NEVER shrink: a column already past the cap keeps its seats.
            cols[c] = max(cols[c], min(cap, cols[c] + 1))
        }
        return BoardLayout(cols: cols, piles: cols.reduce(0, +), rows: cols.max() ?? 0)
    }

    /// Derive a board layout for an ARBITRARY pile count (a map node sets the
    /// pile count). Splits n into up to 3 balanced columns.
    public static func layoutForPiles(_ n0: Int) -> BoardLayout {
        let n = max(1, n0)
        var cols: [Int]
        if n <= 3 {
            cols = Array(repeating: 1, count: n)               // 1 per column
        } else {
            let base = n / 3, rem = n % 3
            cols = rem == 1 ? [base, base + 1, base]
                 : rem == 2 ? [base + 1, base, base + 1]
                 : [base, base, base]
            cols = cols.filter { $0 > 0 }
        }
        return BoardLayout(cols: cols, piles: cols.reduce(0, +), rows: cols.max() ?? 0)
    }

    /// Active suits enter in canonical SUITS order. Stage s (1-based) uses the
    /// first (s + 1) suits.
    public static func suitsForStage(_ stage: Int) -> [String] {
        DeckManager.suits.prefix(max(0, stage + 1)).map(\.symbol)
    }
}

public let minRank = 2    // 2 is the floor for Decrease
public let maxRank = 14   // Ace is the ceiling for Increase

/// A SHOP-ROLLED value, locked for the climb (v6.76 archetype batch). Items
/// carrying `shopRoll: "rank"/"suit"` (and optionally `shopRoll2`) in items.js
/// roll their {rank}/{suit} the FIRST time they show on a shelf, hold it all
/// climb, and hand it to the engine at deal time. `rank` is a card value
/// (2…14); `suit` a suit symbol.
public struct ShopRoll: Sendable, Equatable {
    public var rank: Int?
    public var suit: String?
    public init(rank: Int? = nil, suit: String? = nil) { self.rank = rank; self.suit = suit }
}

extension ItemDef {
    /// v6.76: this entry's shop-rolled axis ("rank" / "suit"), rolled at its
    /// first shelf appearance of the climb; `shopRoll2` is the second axis
    /// (Transmute's suit). Nil when the entry rolls nothing.
    public var shopRoll: String? { raw["shopRoll"]?.asString }
    public var shopRoll2: String? { raw["shopRoll2"]?.asString }
    /// v6.76: the placement family tag — "sameTolerance" pillars share a
    /// one-per-column rule, enforced by `CampaignState.canPlacePillar`.
    public var family: String? { raw["family"]?.asString }
    /// v6.76: which tolerance rule a sameTolerance pillar runs
    /// ("near" / "royalPair" / "sum10" / "sameSuit").
    public var tol: String? { raw["tol"]?.asString }
}

/// One shelf slot in a store offer.
public struct StoreSlot: Sendable, Equatable {
    /// "sticker" | "pillar" | "base" | "pack" | "samepower" | "card" | "removal"
    public var kind: String
    public var id: String
    /// MYSTERY SAME-POWER (v6.51): a "samepower" slot with NO concrete id — the
    /// actual Same-Power is rolled (seeded) at BUY time. Legacy saves decode
    /// with `false` and keep their concrete same-power slots.
    public var mystery: Bool
    /// The generated playing card, for the "card" class only.
    public var card: CardSpec?
    /// SHOP-ROLLED VALUES (v6.76): the {rank}/{suit} a shopRoll item rolled at
    /// OFFER time off the seeded store stream. Ride the slot (persisted in the
    /// offer save) and transfer to the climb lock on purchase. Nil for items
    /// that roll nothing.
    public var rollRank: Int?
    public var rollSuit: String?
    /// The shelf id a mystery Same-Power slot carries (names no registry entry).
    public static let mysteryId = "mystery"
    public init(kind: String, id: String, mystery: Bool = false, card: CardSpec? = nil,
                rollRank: Int? = nil, rollSuit: String? = nil) {
        self.kind = kind; self.id = id; self.mystery = mystery; self.card = card
        self.rollRank = rollRank; self.rollSuit = rollSuit
    }
}

public struct StoreOffer: Sendable, Equatable {
    public var slots: [StoreSlot?]
    public var rerollCost: Double
    /// FREEBIE's gift: the one rolled slot this visit that costs 0 (nil
    /// without the pillar). Persisted with the offer.
    public var freeSlot: Int? = nil
    /// The NODE this offer was rolled for (v6.52). The store screen rerolls
    /// when it opens for a DIFFERENT node, so a leftover shelf — and the
    /// per-visit price twist scoped by openStore — can never follow the
    /// player from one shop into another (the mystery-detour store opens
    /// with fresh=false by web parity and used to inherit both). nil for a
    /// gift shelf and for pre-v6.52 saves (legacy lingering behaviour).
    public var offerNode: Int? = nil
}

/// The store roll + shared item helpers. Kept beside CampaignState so both the
/// live campaign and the tests reach the same code the web build uses.
public enum StoreRoll {
    /// Pick `n` ids from a registry list, WITH replacement, by rarity weight. A
    /// type's `weight` (if set) wins; otherwise its `tier` maps through
    /// tierWeights; otherwise a flat 1.
    public static func rollIds(_ types: [ItemDef], _ n: Int, _ rng: RNG,
                               distinct: Bool = false, tierWeights: [String: Double]) -> [String] {
        let pool = types.map { (id: $0.id, weight: $0.weight ?? tierWeights[$0.tier] ?? 1) }
        var out: [String] = []
        for _ in 0..<n {
            // `distinct` draws WITHOUT replacement (the pack section, whose slot
            // count equals its type count).
            let avail = distinct ? pool.filter { !out.contains($0.id) } : pool
            if avail.isEmpty { break }
            let total = avail.reduce(0) { $0 + $1.weight }
            let denom = total == 0 ? 1 : total
            var r = rng.next() * denom
            var chosen = avail[avail.count - 1].id
            for x in avail {
                r -= x.weight
                if r < 0 { chosen = x.id; break }
            }
            out.append(chosen)
        }
        return out
    }

    /// The TYPE a slot counts against for the per-visit cap. Card packs and
    /// sticker packs are DIFFERENT types.
    public static func slotTypeKey(_ kind: String, _ id: String, data: GameData) -> String {
        guard kind == "pack" else { return kind }
        return data.packTypes.get(id)?.kind == "card" ? "cardpack" : "stickerpack"
    }

    /// The PACK-CARD sticker distribution — how many stickers one freshly
    /// granted card carries. The odds table lives in items.js.
    public static func packStickerCount(_ roll: Double, data: GameData) -> Int {
        stickerCount(roll, odds: data.items.packStickerOdds)
    }

    /// One roll against a [maxRoll, count] odds table (packStickerOdds and
    /// store.card.stickerOdds share the shape).
    public static func stickerCount(_ roll: Double, odds: [[Double]]) -> Int {
        for pair in odds where roll < pair[0] { return Int(pair[1]) }
        return 0
    }

    /// Roll store slots CLASS-FIRST: each slot picks its item CLASS by
    /// `store.classWeights`, THEN an item within that class weighted by rarity.
    /// A draw that would put a class past the type cap is rejected and redrawn.
    /// A class whose unlocked pool is EMPTY drops to weight 0, so the total
    /// renormalizes over the remaining classes instead of rolling dead slots.
    /// `isEquipped(classKey, id)` removes what the player is ALREADY wearing
    /// from the shelf — a second Guardian you can't hold is a wasted slot.
    /// It takes the class key because ids are only unique within a class
    /// (the Pillar "revive" and the Base "revive" are different items).
    /// `shopRolls` is the campaign's climb-lock map (v6.76, R2), mutated as
    /// first-time rolls lock.
    public static func rollUnifiedSlots(_ rng: RNG, count: Int, data: GameData,
                                        isUnlocked: (ItemDef) -> Bool,
                                        isEquipped: ((String, String) -> Bool)? = nil,
                                        tierWeights: [String: Double]? = nil,
                                        genCard: ((RNG) -> CardSpec?)?,
                                        shopRolls: inout [String: ShopRoll]) -> [StoreSlot?] {
        let effectiveTierWeights = tierWeights ?? data.items.store.tierWeights
        let CW = data.items.store.classWeights
        let cap = data.items.store.typeCap
        func cls(_ key: String, _ w: Double, _ types: [ItemDef]) -> (key: String, w: Double, types: [ItemDef]) {
            let pool = types.filter { isUnlocked($0) && !(isEquipped?(key, $0.id) ?? false) }
            return (key, pool.isEmpty ? 0 : w, pool)
        }
        // v6.87: EVERY class pools through grantableBase() — `inactive`
        // (and, for stickers, `cursed`) never reaches a shelf. Before this,
        // only stickers had the filter, so a retired pillar kept rolling.
        let classes: [(key: String, w: Double, types: [ItemDef])] = [
            cls("sticker", CW["sticker"] ?? 0, data.stickerTypes.grantableBase()),
            cls("pillar", CW["pillar"] ?? 0, data.pillarTypes.grantableBase()),
            cls("base", CW["base"] ?? 0, data.baseTypes.grantableBase()),
            cls("pack", CW["pack"] ?? 0, data.packTypes.grantableBase()),
            ("card", genCard != nil ? (CW["card"] ?? 0) : 0, []),
            cls("samepower", CW["samepower"] ?? 0, data.samePowerTypes.grantableBase()),
        ]
        let cwTotalRaw = classes.reduce(0) { $0 + $1.w }
        let cwTotal = cwTotalRaw == 0 ? 1 : cwTotalRaw
        var slots: [StoreSlot?] = []
        var perType: [String: Int] = [:]
        // One shelf never repeats an ITEM: a duplicate draw is rejected and
        // redrawn, exactly like a class over its cap. Cards are exempt (each
        // minted card is its own thing).
        var seenIds = Set<String>()
        for _ in 0..<count {
            var pick: StoreSlot? = nil
            // Reject-and-redraw over the class cap; 80 tries is a paranoid ceiling.
            var attempt = 0
            while attempt < 80 && pick == nil {
                attempt += 1
                var r = rng.next() * cwTotal
                var chosen = classes[classes.count - 1]
                for c in classes {
                    r -= c.w
                    if r < 0 { chosen = c; break }
                }
                if chosen.key == "card" {
                    if (perType["card"] ?? 0) >= cap { continue }   // cap check BEFORE minting
                    guard let card = genCard?(rng) else { continue }
                    pick = StoreSlot(kind: "card", id: "card", card: card)
                } else if chosen.key == "samepower" {
                    // MYSTERY SAME-POWER (v6.51): the class yields ONE unknown
                    // slot — the concrete Same-Power is rolled (seeded) at BUY
                    // time. The shelf roll draws ONLY the class pick, never a
                    // per-item roll. The shared id caps it at one per shelf
                    // through the same no-repeat rule every item obeys.
                    if seenIds.contains("samepower.\(StoreSlot.mysteryId)") { continue }
                    if (perType["samepower"] ?? 0) >= cap { continue }
                    pick = StoreSlot(kind: "samepower", id: StoreSlot.mysteryId, mystery: true)
                } else {
                    guard let id = rollIds(chosen.types, 1, rng, tierWeights: effectiveTierWeights).first
                    else { continue }
                    if seenIds.contains("\(chosen.key).\(id)") { continue }
                    if (perType[slotTypeKey(chosen.key, id, data: data)] ?? 0) >= cap { continue }
                    var slot = StoreSlot(kind: chosen.key, id: id)
                    applyShopRolls(&slot, def: chosen.types.first { $0.id == id }, rng: rng,
                                   shopRolls: &shopRolls)
                    pick = slot
                }
            }
            guard let p = pick else { slots.append(nil); continue }   // unreachable in practice
            let key = p.kind == "card" ? "card" : slotTypeKey(p.kind, p.id, data: data)
            perType[key, default: 0] += 1
            if p.kind != "card" { seenIds.insert("\(p.kind).\(p.id)") }
            slots.append(p)
        }
        return slots
    }

    /// UNLOCKED variant (legacy/test callers): like the web's map-less path,
    /// every offer re-rolls — the scratch lock dies with the call.
    public static func rollUnifiedSlots(_ rng: RNG, count: Int, data: GameData,
                                        isUnlocked: (ItemDef) -> Bool,
                                        isEquipped: ((String, String) -> Bool)? = nil,
                                        tierWeights: [String: Double]? = nil,
                                        genCard: ((RNG) -> CardSpec?)?) -> [StoreSlot?] {
        var scratch: [String: ShopRoll] = [:]
        return rollUnifiedSlots(rng, count: count, data: data, isUnlocked: isUnlocked,
                                isEquipped: isEquipped, tierWeights: tierWeights,
                                genCard: genCard, shopRolls: &scratch)
    }

    /// SHOP-ROLLED VALUES (v6.76, R2): an item def carrying `shopRoll` (and
    /// maybe `shopRoll2`) locks its rolled rank/suit the FIRST time it shows
    /// on a shelf this climb. The draw comes off THIS seeded store stream —
    /// exactly one draw per axis, in slot order, `shopRoll` before
    /// `shopRoll2` — and ONLY while that axis is still unlocked (a locked
    /// re-shelf consumes NO draw — the web's `roll == null` check). Either
    /// way the value rides the slot, so a saved offer restores it as-shown.
    static func applyShopRolls(_ slot: inout StoreSlot, def: ItemDef?, rng: RNG,
                               shopRolls: inout [String: ShopRoll]) {
        guard let def, def.shopRoll != nil else { return }
        var lock = shopRolls[def.id] ?? ShopRoll()
        if def.shopRoll == "rank" {
            if lock.rank == nil { lock.rank = minRank + rng.index(maxRank - minRank + 1) }
            slot.rollRank = lock.rank
        } else if def.shopRoll == "suit" {
            if lock.suit == nil { lock.suit = DeckManager.suits[rng.index(DeckManager.suits.count)].symbol }
            slot.rollSuit = lock.suit
        }
        if def.shopRoll2 == "rank" {
            if lock.rank == nil { lock.rank = minRank + rng.index(maxRank - minRank + 1) }
            slot.rollRank = lock.rank
        } else if def.shopRoll2 == "suit" {
            if lock.suit == nil { lock.suit = DeckManager.suits[rng.index(DeckManager.suits.count)].symbol }
            slot.rollSuit = lock.suit
        }
        shopRolls[def.id] = lock
    }

    /// A fresh offering: `store.slots` class-first slots, reroll at base cost.
    /// When the Removal slot is on it permanently occupies the LAST slot.
    public static func freshOffer(_ rng: RNG, data: GameData, removalOn: Bool,
                                  isUnlocked: (ItemDef) -> Bool,
                                  isEquipped: ((String, String) -> Bool)? = nil,
                                  tierWeights: [String: Double]? = nil,
                                  genCard: ((RNG) -> CardSpec?)?,
                                  shopRolls: inout [String: ShopRoll]) -> StoreOffer {
        let rolled = removalOn ? data.items.store.slots - 1 : data.items.store.slots
        var slots = rollUnifiedSlots(rng, count: rolled, data: data, isUnlocked: isUnlocked,
                                     isEquipped: isEquipped, tierWeights: tierWeights,
                                     genCard: genCard, shopRolls: &shopRolls)
        if removalOn { slots.append(StoreSlot(kind: "removal", id: "removal")) }
        return StoreOffer(slots: slots, rerollCost: data.items.store.reroll.baseCost)
    }

    /// UNLOCKED variant — see the rollUnifiedSlots overload.
    public static func freshOffer(_ rng: RNG, data: GameData, removalOn: Bool,
                                  isUnlocked: (ItemDef) -> Bool,
                                  isEquipped: ((String, String) -> Bool)? = nil,
                                  tierWeights: [String: Double]? = nil,
                                  genCard: ((RNG) -> CardSpec?)?) -> StoreOffer {
        var scratch: [String: ShopRoll] = [:]
        return freshOffer(rng, data: data, removalOn: removalOn, isUnlocked: isUnlocked,
                          isEquipped: isEquipped, tierWeights: tierWeights,
                          genCard: genCard, shopRolls: &scratch)
    }
}

// MARK: - Seeded substreams (SEED1)

/// FNV-1a 32-bit — folds a string key into the run substream mix.
public func seedStrHash(_ s: String) -> UInt32 {
    var h: UInt32 = 2166136261
    for b in s.unicodeScalars {
        h ^= UInt32(truncatingIfNeeded: b.value)
        h = h &* 16777619
    }
    return h
}

/// A key in a run substream: a stable label or a stable numeric identifier.
public enum RunKey {
    case s(String)
    case n(Int)
}

/// `runRng(...keys)` — an independent deterministic stream derived from the
/// run's seed, keyed by STABLE identifiers (a stream label, a node id, a
/// visit/reroll index) — never by call order, so a run's content doesn't depend
/// on which nodes the player visited first.
public func runRng(seed: UInt32, _ keys: [RunKey]) -> RNG {
    var mix: UInt32 = 0x9e3779b9
    for k in keys {
        let part: UInt32
        switch k {
        case .s(let str): part = seedStrHash(str)
        case .n(let num): part = jsImul(UInt32(truncatingIfNeeded: num) &+ 1, 0x9e3779b1)
        }
        mix = mix ^ part
    }
    return RNG(seed: seed ^ mix)
}

/// `(runSeed >>> 0) ^ (((node.id + 1) * 0x85ebca6b) >>> 0)` — the node-keyed
/// draft stream. The JS uses a plain `*` here (exact for every reachable node
/// id, then truncated by `>>> 0`), NOT `Math.imul`.
public func nodeDraftSeed(seed: UInt32, nodeId: Int) -> UInt32 {
    seed ^ UInt32(truncatingIfNeeded: Int64(nodeId + 1) &* 0x85ebca6b)
}

/// The pack-slot stream: the node draft seed xor `Math.imul(slot + 1, 0x9e3779b1)`.
public func packSlotSeed(seed: UInt32, nodeId: Int, slot: Int) -> UInt32 {
    nodeDraftSeed(seed: seed, nodeId: nodeId) ^ jsImul(UInt32(truncatingIfNeeded: slot) &+ 1, 0x9e3779b1)
}

/// The mystery streams: `(runSeed) ^ (Math.imul(nodeId + 1, 0x9e3779b1)) ^ salt`.
public func mysterySeed(seed: UInt32, nodeId: Int, salt: UInt32) -> UInt32 {
    seed ^ jsImul(UInt32(truncatingIfNeeded: nodeId) &+ 1, 0x9e3779b1) ^ salt
}

/// "MEVT" — the outcome-key roll (distinct from the map's mystery display salt).
public let mysteryKeySalt: UInt32 = 0x4d455654
/// "MAMT" — amounts / sticker / card picks.
public let mysteryDetailSalt: UInt32 = 0x4d414d54
/// "OJKR" — THE OLD JOKER's appearance + offer roll. A SEPARATE stream from
/// the mystery outcome roll on purpose: he can be retuned, or removed, without
/// shifting a single byte of the ordinary mystery stream.
public let oldJokerSalt: UInt32 = 0x4f4a4b52
/// BOUNCER's ward roll (turning Just a Two away) — its own substream, so
/// equipping the pillar never shifts any other node roll.
public let twoWardSalt: UInt32 = 0x424f554e
/// "QFND" — QUEEN-FINDER's extra shot at the character split (v6.87). Its
/// own substream for the same reason as the Bouncer's.
public let queenFinderSalt: UInt32 = 0x51464e44
/// "OJRS" — details the player's CHOICE needs (which card he cuts).
public let oldJokerResolveSalt: UInt32 = 0x4f4a5253
/// "OJLC" — the Purge's leech targets.
public let oldJokerLeechSalt: UInt32 = 0x4f4a4c43

/// "JOKR" — the guaranteed-map-Joker placement roll.
public let jokerPlacementSalt: UInt32 = 0x4a4f4b52
