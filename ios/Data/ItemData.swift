import Foundation

/// Thrown when a bundled data file fails validation. Mirrors the web build's
/// contract: every problem is reported (naming the file, the group, the item id
/// and the field), then load throws — items are never silently dropped.
public struct DataValidationError: Error, CustomStringConvertible {
    public let file: String
    public let problems: [String]
    public var description: String {
        problems.joined(separator: "\n")
        + "\n\(file) validation FAILED — \(problems.count) problem\(problems.count == 1 ? "" : "s")"
    }
}

// MARK: - Store / mystery / economy config blocks

public struct RerollConfig: Sendable { public let baseCost: Double; public let step: Double }

public struct StoreCardConfig: Sendable {
    public let label: String, icon: String, description: String
    public let price: Double, jokerPrice: Double
    /// Added to `price` for EACH sticker the minted card carries.
    public let stickerStep: Double
    /// The card slot's own sticker distribution ([maxRoll, count] pairs, same
    /// shape as packStickerOdds) — store singles roll stickers on these odds,
    /// not the pack table.
    public let stickerOdds: [[Double]]
}

public struct StoreRemovalConfig: Sendable {
    public let id: String, label: String, icon: String, description: String
    public let price: Double
    /// Added to the price for each removal already bought this climb (0 = flat).
    public let priceStep: Double
}

public struct StoreConfig: Sendable {
    /// Shelf slot count.
    public let slots: Int
    /// Max slots of one item type per visit.
    public let typeCap: Int
    public let reroll: RerollConfig
    /// CLASS-FIRST store roll: every slot picks its class by these weights.
    public let classWeights: [String: Double]
    public let tierWeights: [String: Double]
    public let card: StoreCardConfig
    public let removal: StoreRemovalConfig
    public let raw: [String: JSONValue]
}

public struct AmbushConfig: Sendable { public let cards: Double, piles: Double, bounty: Double }

/// THE OLD JOKER — every knob for the recurring "?"-node character. Nothing
/// about him is hardcoded in logic; this is the whole tuning surface.
public struct OldJokerConfig: Sendable {
    /// Relative odds per offer; only ELIGIBLE offers are rolled.
    /// (His SHARE of ? nodes lives in `mystery.characterWeights`.)
    public let weights: [String: Double]
    /// The whole decoded section — per-event knobs are read via `num`/`ints`.
    public let raw: [String: JSONValue]

    /// The offer keys, in the fixed order the weighted roll walks them.
    public static let offerKeys = [
        "buyout", "swap", "purge", "ride", "cut",
        "marker", "blindSwap", "twoDoors", "insurance", "refund",
        "freeShop", "purgeReset", "eights", "thirsty", "duplicate",
        "jokerForPillars",
    ]

    /// A numeric knob inside one offer's block, e.g. `num("marker", "repayMult", 1.5)`.
    public func num(_ event: String, _ key: String, _ fallback: Double) -> Double {
        raw[event]?.asObject?[key]?.asNumber ?? fallback
    }
    public func int(_ event: String, _ key: String, _ fallback: Int) -> Int {
        Int(num(event, key, Double(fallback)))
    }
    public func string(_ event: String, _ key: String, _ fallback: String) -> String {
        raw[event]?.asObject?[key]?.asString ?? fallback
    }
    public func strings(_ event: String, _ key: String) -> [String] {
        raw[event]?.asObject?[key]?.asArray?.compactMap(\.asString) ?? []
    }
}

public struct MysteryConfig: Sendable {
    public let weights: [String: Double]
    /// WHO takes a ? node — the character rolls FIRST (oldJoker / queen /
    /// two), then the winner's own pool rolls by `weights`.
    public let characterWeights: [String: Double]
    /// [min,max] coin bonus per stage index.
    public let coinRangeByStage: [[Double]]
    /// [min,max] integer card grant.
    public let cardGrantRange: [Int]
    public let ambush: AmbushConfig
    public let raw: [String: JSONValue]
    /// The mystery outcome keys, in the fixed order the validator enforces —
    /// which is also the order the weighted roll walks them in.
    public static let outcomeKeys = [
        "coinBonus", "cards", "stickerPack", "freeRemoval", "stickerStrip",
        "joker", "store", "cursedSticker", "coinLoss", "ambush",
        "stickerTheft", "itemTheft", "priceDouble", "shieldDrain",
        "priceOne", "freeRefresh", "freeRedeal", "shieldCharge",
        "coinDouble", "giftCard", "mammaLie", "twoGame",
    ]
    /// The characterWeights keys, in the fixed order the character roll
    /// walks them.
    public static let characterKeys = ["oldJoker", "queen", "two"]
    /// THE BEHEADED QUEEN's pool — every boon except the Windfall.
    public static let queenKeys = [
        "coinBonus", "stickerPack", "freeRemoval", "stickerStrip",
        "joker", "store", "priceOne", "freeRefresh", "freeRedeal",
        "shieldCharge", "coinDouble", "giftCard",
    ]
    /// JUST A TWO's pool — every bane, plus the Windfall (deck bloat is
    /// exactly the gift a two would give).
    public static let twoKeys = [
        "cards", "cursedSticker", "coinLoss", "ambush", "stickerTheft",
        "itemTheft", "priceDouble", "shieldDrain", "mammaLie", "twoGame",
    ]
}

public struct EconomyConfig: Sendable {
    public let dealBase: Double
    public let bossBonus: Double
    public let raw: [String: JSONValue]
    public func num(_ key: String, _ fallback: Double) -> Double { raw[key]?.asNumber ?? fallback }
}

// MARK: - ItemData

/// The Swift twin of `ItemData` — loads + VALIDATES items.json (the JSON mirror
/// of items.js, produced by `ios/Tools/export-data.mjs`). Every registry and the
/// store's weights/prices source from here.
public struct ItemData: Sendable {
    public let stickers: [ItemDef]
    public let pillars: [ItemDef]
    public let bases: [ItemDef]
    public let samePowers: [ItemDef]
    public let packs: [ItemDef]
    public let store: StoreConfig
    /// [maxRoll, stickerCount] pairs, checked in order against a uniform 0..1
    /// roll; maxRoll strictly ascends.
    public let packStickerOdds: [[Double]]
    public let mystery: MysteryConfig
    public let oldJoker: OldJokerConfig
    public let economy: EconomyConfig
    /// The hard ceiling on stickers per card (items.js `maxStickersPerCard`).
    /// Every grant path checks it; the pickers grey out a full card.
    public let maxStickersPerCard: Int

    public static let tiers = ["common", "uncommon", "rare"]
    static let suitSymbols = ["♠", "♥", "♦", "♣"]

    // MARK: Validation

    public static func decode(_ data: Data, unlockStats: [String]) throws -> ItemData {
        let root: [String: JSONValue]
        do {
            root = try JSONDecoder().decode([String: JSONValue].self, from: data)
        } catch {
            throw DataValidationError(file: "[items.js]", problems: ["[items.js] not valid JSON: \(error)"])
        }
        var problems: [String] = []

        // ── group validation (the shared entry shape + per-group `required`) ──
        func checkGroup(_ name: String, _ value: JSONValue?, required: [String]) -> [ItemDef] {
            guard let list = value?.asArray else {
                problems.append("[items.js] \(name): must be an array")
                return []
            }
            var seen = Set<String>()
            var defs: [ItemDef] = []
            for (i, entryValue) in list.enumerated() {
                guard let entry = entryValue.asObject else {
                    problems.append("[items.js] \(name) '\(name)[\(i)]': entry is not an object")
                    continue
                }
                let idField = entry["id"]?.asString
                let id = (idField?.isEmpty == false) ? idField! : "\(name)[\(i)]"
                func bad(_ msg: String) { problems.append("[items.js] \(name) '\(id)': \(msg)") }

                if idField == nil || idField!.isEmpty { bad("missing/invalid `id` (string)") }
                else if seen.contains(idField!) { bad("duplicate id") }
                else { seen.insert(idField!) }

                if (entry["label"]?.asString ?? "").isEmpty { bad("missing/invalid `label` (string)") }
                let tier = entry["tier"] ?? .null
                if !tiers.contains(tier.asString ?? "") {
                    bad("`tier` must be one of \(tiers.joined(separator: "|")) (got \(tier.jsDescription))")
                }
                let price = entry["price"] ?? .null
                if !(price.asNumber.map { $0 >= 0 } ?? false) {
                    bad("`price` must be a non-negative number (got \(price.jsDescription))")
                }
                if (entry["description"]?.asString ?? "").isEmpty { bad("missing/invalid `description` (string)") }
                if let w = entry["weight"], !w.isNull, !(w.asNumber.map { $0 > 0 } ?? false) {
                    bad("`weight` must be a positive number when set")
                }
                // UNLOCK1: optional item-unlock gate — a fully formed { type, stat, count }.
                if let u = entry["unlock"], !u.isNull {
                    guard let uo = u.asObject else {
                        bad("`unlock` must be an object { type, stat, count }")
                        defs.append(ItemDef(raw: entry)); continue
                    }
                    let t = uo["type"] ?? .null
                    if t.asString != "milestone" && t.asString != "behavior" {
                        bad("`unlock.type` must be \"milestone\" or \"behavior\" (got \(t.jsDescription))")
                    }
                    let s = uo["stat"] ?? .null
                    if !unlockStats.contains(s.asString ?? "") {
                        bad("`unlock.stat` must be one of \(unlockStats.joined(separator: " | ")) (got \(s.jsDescription))")
                    }
                    let c = uo["count"] ?? .null
                    if !(c.asNumber.map { $0 > 0 } ?? false) {
                        bad("`unlock.count` must be a positive finite number (got \(c.jsDescription))")
                    }
                }
                if let s = entry["suits"], !s.isNull {
                    guard let arr = s.asArray, !arr.isEmpty else {
                        bad("`suits` must be a non-empty array of suit symbols when set")
                        defs.append(ItemDef(raw: entry)); continue
                    }
                    for sym in arr where !suitSymbols.contains(sym.asString ?? "") {
                        bad("`suits` entry \(sym.jsDescription) is not one of \(suitSymbols.joined(separator: " "))")
                    }
                }
                for f in required where (entry[f]?.asString ?? "").isEmpty {
                    bad("missing/invalid `\(f)` (string)")
                }
                defs.append(ItemDef(raw: entry))
            }
            return defs
        }

        let stickers = checkGroup("stickers", root["stickers"], required: ["kind"])
        let pillars = checkGroup("pillars", root["pillars"], required: ["kind", "effect"])
        let bases = checkGroup("bases", root["bases"], required: ["kind", "effect"])
        let samePowers = checkGroup("samePowers", root["samePowers"], required: ["effect"])
        let packs = checkGroup("packs", root["packs"], required: ["kind"])

        // A [maxRoll, stickerCount] odds table — shared shape between
        // packStickerOdds and store.card.stickerOdds.
        func parseOddsTable(_ v: JSONValue?, _ label: String) -> [[Double]] {
            var out: [[Double]] = []
            guard let rows = v?.asArray, !rows.isEmpty else {
                problems.append("[items.js] \(label): must be a non-empty array of [maxRoll, stickerCount] pairs")
                return out
            }
            var prevCap = -Double.infinity
            for (i, pair) in rows.enumerated() {
                func bad(_ msg: String) { problems.append("[items.js] \(label)[\(i)]: \(msg)") }
                guard let p = pair.asArray, p.count == 2,
                      let maxRoll = p[0].asNumber, maxRoll > 0, maxRoll <= 1,
                      let count = p[1].asNumber, count >= 0, count.rounded(.down) == count
                else {
                    bad("must be a [maxRoll, stickerCount] pair — maxRoll in (0,1], stickerCount an integer ≥ 0")
                    continue
                }
                if maxRoll <= prevCap { bad("maxRoll must strictly ascend through the table") }
                prevCap = maxRoll
                out.append([maxRoll, count])
            }
            return out
        }

        // ── store ────────────────────────────────────────────────────────────
        var store = StoreConfig(
            slots: 0, typeCap: 0, reroll: RerollConfig(baseCost: 0, step: 0),
            classWeights: [:], tierWeights: [:],
            card: StoreCardConfig(label: "", icon: "", description: "", price: 0, jokerPrice: 0,
                                  stickerStep: 0, stickerOdds: []),
            removal: StoreRemovalConfig(id: "", label: "", icon: "", description: "", price: 0, priceStep: 0),
            raw: [:]
        )
        if let s = root["store"]?.asObject {
            func posInt(_ v: JSONValue?) -> Bool {
                guard let n = v?.asNumber else { return false }
                return n.rounded(.down) == n && n > 0
            }
            if !posInt(s["slots"]) { problems.append("[items.js] store.slots: must be a positive integer (shelf slot count)") }
            if !posInt(s["typeCap"]) { problems.append("[items.js] store.typeCap: must be a positive integer (max slots of one item type per visit)") }
            let rr = s["reroll"]?.asObject
            let rrBase = rr?["baseCost"]?.asNumber, rrStep = rr?["step"]?.asNumber
            if rr == nil || !((rrBase ?? -1) >= 0) || !((rrStep ?? -1) >= 0) {
                problems.append("[items.js] store.reroll: needs numeric `baseCost` and `step` (≥ 0)")
            }
            let tw = s["tierWeights"]?.asObject ?? [:]
            for t in tiers where !((tw[t]?.asNumber ?? 0) > 0) {
                problems.append("[items.js] store.tierWeights.\(t): must be a positive number")
            }
            let rm = s["removal"]?.asObject
            if rm == nil || !((rm?["price"]?.asNumber ?? -1) >= 0) || rm?["description"]?.asString == nil {
                problems.append("[items.js] store.removal: needs a numeric `price` and a `description`")
            }
            let cw = s["classWeights"]?.asObject ?? [:]
            for k in ["sticker", "pillar", "base", "pack", "card", "samepower"] where !((cw[k]?.asNumber ?? -1) >= 0) {
                problems.append("[items.js] store.classWeights.\(k): must be a number ≥ 0")
            }
            let cd = s["card"]?.asObject
            if cd == nil || !((cd?["price"]?.asNumber ?? -1) >= 0) || !((cd?["jokerPrice"]?.asNumber ?? -1) >= 0) {
                problems.append("[items.js] store.card: needs numeric `price` and `jokerPrice`")
            }
            if !((cd?["stickerStep"]?.asNumber ?? -1) >= 0) {
                problems.append("[items.js] store.card: needs numeric `stickerStep` (≥ 0, added to price per sticker)")
            }
            let cardOdds = parseOddsTable(cd?["stickerOdds"], "store.card.stickerOdds")
            store = StoreConfig(
                slots: Int(s["slots"]?.asNumber ?? 0),
                typeCap: Int(s["typeCap"]?.asNumber ?? 0),
                reroll: RerollConfig(baseCost: rrBase ?? 0, step: rrStep ?? 0),
                classWeights: cw.compactMapValues(\.asNumber),
                tierWeights: tw.compactMapValues(\.asNumber),
                card: StoreCardConfig(
                    label: cd?["label"]?.asString ?? "Card", icon: cd?["icon"]?.asString ?? "",
                    description: cd?["description"]?.asString ?? "",
                    price: cd?["price"]?.asNumber ?? 0, jokerPrice: cd?["jokerPrice"]?.asNumber ?? 0,
                    stickerStep: cd?["stickerStep"]?.asNumber ?? 0, stickerOdds: cardOdds),
                removal: StoreRemovalConfig(
                    id: rm?["id"]?.asString ?? "removal", label: rm?["label"]?.asString ?? "Removal",
                    icon: rm?["icon"]?.asString ?? "", description: rm?["description"]?.asString ?? "",
                    price: rm?["price"]?.asNumber ?? 0,
                    priceStep: rm?["priceStep"]?.asNumber ?? 0),
                raw: s
            )
        } else {
            problems.append("[items.js] store: missing config object")
        }

        // ── packStickerOdds ──────────────────────────────────────────────────
        let packStickerOdds = parseOddsTable(root["packStickerOdds"], "packStickerOdds")

        // ── mystery ──────────────────────────────────────────────────────────
        var mystery = MysteryConfig(weights: [:], characterWeights: [:],
                                    coinRangeByStage: [], cardGrantRange: [1, 1],
                                    ambush: AmbushConfig(cards: 0, piles: 0, bounty: 0), raw: [:])
        if let my = root["mystery"]?.asObject {
            let mw = my["weights"]?.asObject ?? [:]
            for k in MysteryConfig.outcomeKeys where !((mw[k]?.asNumber ?? 0) > 0) {
                problems.append("[items.js] mystery.weights.\(k): must be a positive number")
            }
            let cw = my["characterWeights"]?.asObject ?? [:]
            for k in MysteryConfig.characterKeys where !((cw[k]?.asNumber ?? 0) > 0) {
                problems.append("[items.js] mystery.characterWeights.\(k): must be a positive number")
            }
            // The two character pools must partition outcomeKeys exactly — a
            // key in neither pool would be unrollable, a key in both double-
            // counted. Checked here so a future outcome can't be added to
            // outcomeKeys without being assigned a deliverer.
            let pooled = Set(MysteryConfig.queenKeys + MysteryConfig.twoKeys)
            if pooled.count != MysteryConfig.queenKeys.count + MysteryConfig.twoKeys.count
                || pooled != Set(MysteryConfig.outcomeKeys) {
                problems.append("[ItemData] mystery pools: queenKeys + twoKeys must partition outcomeKeys exactly")
            }
            var coinRange: [[Double]] = []
            if let cr = my["coinRangeByStage"]?.asArray, !cr.isEmpty {
                for (i, pair) in cr.enumerated() {
                    guard let p = pair.asArray, p.count == 2,
                          let lo = p[0].asNumber, lo >= 0,
                          let hi = p[1].asNumber, hi >= lo else {
                        problems.append("[items.js] mystery.coinRangeByStage[\(i)]: must be a [min,max] pair of numbers with 0 ≤ min ≤ max")
                        continue
                    }
                    coinRange.append([lo, hi])
                }
            } else {
                problems.append("[items.js] mystery.coinRangeByStage: must be a non-empty array of [min,max] pairs")
            }
            var cardGrant = [1, 1]
            if let cg = my["cardGrantRange"]?.asArray, cg.count == 2,
               let lo = cg[0].asNumber, lo.rounded(.down) == lo, lo >= 1,
               let hi = cg[1].asNumber, hi.rounded(.down) == hi, hi >= lo {
                cardGrant = [Int(lo), Int(hi)]
            } else {
                problems.append("[items.js] mystery.cardGrantRange: must be a [min,max] pair of integers with 1 ≤ min ≤ max")
            }
            let am = my["ambush"]?.asObject ?? [:]
            for k in ["cards", "piles", "bounty"] where !((am[k]?.asNumber ?? 0) > 0) {
                problems.append("[items.js] mystery.ambush.\(k): must be a positive number")
            }
            // The shared curse roll draws from the stickers flagged `cursed:
            // true`. Fail loud on a malformed pool: every curse needs a
            // positive hand-tuned weight, exclusions must name real pathways,
            // and every pathway must have at least one curse left to roll.
            if !stickers.contains(where: { $0.cursed }) {
                problems.append("[items.js] stickers: at least one entry must carry `cursed: true` (the curse roll's pool)")
            }
            let cursePaths = ["mystery", "purge", "duplicate", "doors"]
            for s in stickers where s.cursed {
                if !(s.curseWeight > 0) {
                    problems.append("[items.js] stickers.\(s.id): cursed entries need `curseWeight` > 0")
                }
                for p in s.curseExclude where !cursePaths.contains(p) {
                    problems.append("[items.js] stickers.\(s.id): curseExclude '\(p)' is not a pathway (\(cursePaths.joined(separator: "/")))")
                }
            }
            for p in cursePaths where !stickers.contains(where: {
                $0.cursed && $0.curseWeight > 0 && !$0.curseExclude.contains(p)
            }) {
                problems.append("[items.js] stickers: the curse pool for pathway '\(p)' is empty")
            }
            mystery = MysteryConfig(
                weights: mw.compactMapValues(\.asNumber),
                characterWeights: cw.compactMapValues(\.asNumber),
                coinRangeByStage: coinRange, cardGrantRange: cardGrant,
                ambush: AmbushConfig(cards: am["cards"]?.asNumber ?? 0,
                                     piles: am["piles"]?.asNumber ?? 0,
                                     bounty: am["bounty"]?.asNumber ?? 0),
                raw: my)
        } else {
            problems.append("[items.js] mystery: missing config object")
        }

        // ── oldJoker ─────────────────────────────────────────────────────────
        var oldJoker = OldJokerConfig(weights: [:], raw: [:])
        if let oj = root["oldJoker"]?.asObject {
            let ow = oj["weights"]?.asObject ?? [:]
            for k in OldJokerConfig.offerKeys where !((ow[k]?.asNumber ?? 0) > 0) {
                problems.append("[items.js] oldJoker.weights.\(k): must be a positive number")
            }
            // Every offer needs its own knob block — a missing one would
            // silently fall back to a hardcoded default, which is exactly what
            // the data-file convention forbids.
            for k in OldJokerConfig.offerKeys where !["swap", "ride"].contains(k) {
                if oj[k]?.asObject == nil {
                    problems.append("[items.js] oldJoker.\(k): missing its knob block")
                }
            }
            if let sid = oj["purge"]?.asObject?["leechSticker"]?.asString,
               !stickers.contains(where: { $0.id == sid }) {
                problems.append("[items.js] oldJoker.purge.leechSticker: no sticker with id `\(sid)`")
            }
            for side in ["good", "bad"] {
                let keys = oj["twoDoors"]?.asObject?[side]?.asArray?.compactMap(\.asString) ?? []
                if keys.isEmpty {
                    problems.append("[items.js] oldJoker.twoDoors.\(side): must be a non-empty array of mystery outcome keys")
                }
                for k in keys where !MysteryConfig.outcomeKeys.contains(k) {
                    problems.append("[items.js] oldJoker.twoDoors.\(side): `\(k)` is not a mystery outcome key")
                }
            }
            oldJoker = OldJokerConfig(weights: ow.compactMapValues(\.asNumber), raw: oj)
        } else {
            problems.append("[items.js] oldJoker: missing config object")
        }

        // ── economy ──────────────────────────────────────────────────────────
        var economy = EconomyConfig(dealBase: 0, bossBonus: 0, raw: [:])
        if let eco = root["economy"]?.asObject {
            for k in ["dealBase", "bossBonus"] where !((eco[k]?.asNumber ?? 0) > 0) {
                problems.append("[items.js] economy.\(k): must be a positive finite number")
            }
            economy = EconomyConfig(dealBase: eco["dealBase"]?.asNumber ?? 0,
                                    bossBonus: eco["bossBonus"]?.asNumber ?? 0, raw: eco)
        } else {
            problems.append("[items.js] economy: missing config object")
        }

        if !problems.isEmpty { throw DataValidationError(file: "items.js", problems: problems) }
        return ItemData(stickers: stickers, pillars: pillars, bases: bases,
                        samePowers: samePowers, packs: packs, store: store,
                        packStickerOdds: packStickerOdds, mystery: mystery,
                        oldJoker: oldJoker, economy: economy,
                        maxStickersPerCard: Int(root["maxStickersPerCard"]?.asNumber ?? 4))
    }
}
