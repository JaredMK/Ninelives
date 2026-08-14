import Foundation

/// One difficulty tier (Regular / Master / Legendary).
public struct DifficultyTier: Sendable {
    public let id: String
    public let label: String
    /// Max Jokers HELD AT ONCE on this tier. 0 = no Jokers at all.
    public let jokerCap: Int
    /// One visible standalone Joker node somewhere in stages 1-3.
    public let guaranteedMapJoker: Bool
    /// OPTIONAL per-deck Joker-scheme override: deck id → authored stage indices.
    public let fixedJokers: [String: [Int]]
    /// OPTIONAL per-deck starting Jokers: deck id → count.
    public let startJokers: [String: Int]
    /// [[lo,hi] ×3] — regular deals' target-difficulty band per stage.
    public let stageBands: [[Double]]
    /// [[lo,hi] ×3] — the stage bosses' band.
    public let bossBands: [[Double]]
}

public struct ZenConfig: Sendable {
    public let id: String
    public let label: String
    /// Suits kept from the standard deck (1-4).
    public let suitCount: Int
    /// Piles the deck deals onto.
    public let piles: Int
}

public struct SubsetConfig: Sendable {
    /// Deck size past which a REGULAR deal plays a random subset.
    public let threshold: Int
    /// The SURVIVE count range (the draw pile you must outlast).
    public let min: Int
    public let max: Int
}

/// The Swift twin of `DifficultyData` — loads + VALIDATES difficulty.json.
/// The map generator's `bandsFor()` reads the SELECTED tier's bands and the
/// endless lift from here, plus the generator-wide `firstDealBand` and the
/// subset-deal knobs.
public struct DifficultyData: Sendable {
    /// TWO tiers. The ids are STABLE SAVE KEYS, so "regular" keeps its id and
    /// only its label changed (to "Normal"); "master" is retired — a save
    /// holding it falls back to regular on restore, and its deck-unlock key is
    /// migrated forward (see DeckUnlocks).
    public static let tierIds = ["regular", "legendary"]
    /// Retired tier ids, kept only so old saves can be recognised and migrated.
    public static let retiredTierIds = ["master"]
    public static let zenIds = ["easy", "medium", "hard"]

    public let endlessBandStep: Double
    public let firstDealBand: [Double]
    /// The genV≥5 OPENING-ROW band: row-0 deals spread ascending across it
    /// (the first option pinned at the gentle floor). Falls back to
    /// `firstDealBand` when difficulty.js doesn't carry the knob, so older
    /// data files stay valid; genV<5 regeneration never reads it.
    public let firstDealBandV5: [Double]
    public let subset: SubsetConfig
    private let tiers: [String: DifficultyTier]
    private let zenById: [String: ZenConfig]

    public var tierIds: [String] { Self.tierIds }
    public var zenIds: [String] { Self.zenIds }

    /// Unknown ids fall back to Regular / Easy, matching the web accessor.
    public func tier(_ id: String) -> DifficultyTier { tiers[id] ?? tiers["regular"]! }
    public func zen(_ id: String) -> ZenConfig { zenById[id] ?? zenById["easy"]! }

    /// The fixed post-boss Joker stage indices for a deck/tier pair, or nil when
    /// the pair uses the tier's normal jokerCap/guaranteedMapJoker rules.
    /// Deliberately NO unknown-tier fallback — a bogus tier id must not silently
    /// inherit Regular's overrides.
    public func fixedJokerStages(deckId: String, tierId: String) -> [Int]? {
        guard let t = tiers[tierId], let stages = t.fixedJokers[deckId], !stages.isEmpty else { return nil }
        return stages
    }
    /// Jokers a deck STARTS every run with on a tier (0 when unlisted). Same
    /// no-fallback contract as `fixedJokerStages`.
    public func startJokers(deckId: String, tierId: String) -> Int {
        guard let t = tiers[tierId], let n = t.startJokers[deckId], n > 0 else { return 0 }
        return n
    }

    // MARK: Validation

    public static func decode(_ data: Data) throws -> DifficultyData {
        let root: [String: JSONValue]
        do {
            root = try JSONDecoder().decode([String: JSONValue].self, from: data)
        } catch {
            throw DataValidationError(file: "[difficulty.js]", problems: ["[difficulty.js] not valid JSON: \(error)"])
        }
        var problems: [String] = []

        let step = root["endlessBandStep"]?.asNumber
        if !((step ?? 0) > 0) { problems.append("[difficulty.js] endlessBandStep: must be a positive number") }

        var firstDealBand: [Double] = [0, 0]
        if let fb = root["firstDealBand"]?.asArray, fb.count == 2,
           let lo = fb[0].asNumber, let hi = fb[1].asNumber {
            if lo > hi { problems.append("[difficulty.js] firstDealBand: has lo > hi (\(fmt(lo)) > \(fmt(hi)))") }
            firstDealBand = [lo, hi]
        } else {
            problems.append("[difficulty.js] firstDealBand: must be a [lo, hi] pair of numbers")
        }

        // OPTIONAL v5 opening band — absent falls back to firstDealBand; a
        // PRESENT-but-malformed knob still fails loud like everything else.
        var firstDealBandV5 = firstDealBand
        if let raw = root["firstDealBandV5"] {
            if let fb = raw.asArray, fb.count == 2,
               let lo = fb[0].asNumber, let hi = fb[1].asNumber, lo <= hi {
                firstDealBandV5 = [lo, hi]
            } else {
                problems.append("[difficulty.js] firstDealBandV5: must be a [lo, hi] pair of numbers with lo <= hi")
            }
        }

        var subset = SubsetConfig(threshold: 0, min: 0, max: 0)
        if let sub = root["subset"]?.asObject {
            for k in ["threshold", "min", "max"] {
                let v = sub[k]?.asNumber
                if !(v.map { $0.rounded(.down) == $0 && $0 > 0 } ?? false) {
                    problems.append("[difficulty.js] subset.\(k): must be a positive integer")
                }
            }
            if let mn = sub["min"]?.asNumber, let mx = sub["max"]?.asNumber, mn > mx {
                problems.append("[difficulty.js] subset: has min > max (\(fmt(mn)) > \(fmt(mx)))")
            }
            subset = SubsetConfig(threshold: Int(sub["threshold"]?.asNumber ?? 0),
                                  min: Int(sub["min"]?.asNumber ?? 0),
                                  max: Int(sub["max"]?.asNumber ?? 0))
        } else {
            problems.append("[difficulty.js] subset: missing object")
        }

        var tiers: [String: DifficultyTier] = [:]
        if let tRoot = root["tiers"]?.asObject {
            for id in tierIds {
                func bad(_ msg: String) { problems.append("[difficulty.js] tiers.\(id): \(msg)") }
                guard let t = tRoot[id]?.asObject else { bad("missing tier entry"); continue }
                if (t["label"]?.asString ?? "").isEmpty { bad("missing/invalid `label` (string)") }
                let cap = t["jokerCap"]?.asNumber
                if !(cap.map { $0 >= 0 && $0.rounded(.down) == $0 } ?? false) {
                    bad("missing/invalid `jokerCap` (integer ≥ 0 — max Jokers held at once on this tier)")
                }
                if t["guaranteedMapJoker"]?.asBool == nil {
                    bad("missing/invalid `guaranteedMapJoker` (boolean — one visible standalone Joker node in stages 1-3)")
                }
                var fixedJokers: [String: [Int]] = [:]
                if let fjValue = t["fixedJokers"] {
                    guard let fj = fjValue.asObject else {
                        bad("invalid `fixedJokers` (object mapping deck ids to stage-index arrays)")
                        continue
                    }
                    for deckKey in fj.keys.sorted() {
                        guard let stages = fj[deckKey]?.asArray, !stages.isEmpty else {
                            bad("`fixedJokers.\(deckKey)` must be a non-empty array of stage indices"); continue
                        }
                        var out: [Int] = []
                        for (i, s) in stages.enumerated() {
                            guard let n = s.asNumber, n.rounded(.down) == n, n >= 0, n <= 2 else {
                                bad("`fixedJokers.\(deckKey)[\(i)]` must be an integer stage index 0-2 (got \(s.jsDescription))")
                                continue
                            }
                            out.append(Int(n))
                        }
                        fixedJokers[deckKey] = out
                    }
                }
                var startJokers: [String: Int] = [:]
                if let sjValue = t["startJokers"] {
                    guard let sj = sjValue.asObject else {
                        bad("invalid `startJokers` (object mapping deck ids to positive integer counts)")
                        continue
                    }
                    for deckKey in sj.keys.sorted() {
                        let n = sj[deckKey]?.asNumber
                        guard let n, n.rounded(.down) == n, n > 0 else {
                            bad("`startJokers.\(deckKey)` must be a positive integer (got \(sj[deckKey]?.jsDescription ?? "undefined"))")
                            continue
                        }
                        startJokers[deckKey] = Int(n)
                    }
                }
                var bands: [String: [[Double]]] = ["stageBands": [], "bossBands": []]
                for key in ["stageBands", "bossBands"] {
                    guard let b = t[key]?.asArray, b.count == 3 else {
                        bad("`\(key)` must be an array of exactly 3 [lo, hi] pairs"); continue
                    }
                    var out: [[Double]] = []
                    for (i, pair) in b.enumerated() {
                        guard let p = pair.asArray, p.count == 2,
                              let lo = p[0].asNumber, let hi = p[1].asNumber else {
                            bad("`\(key)[\(i)]` must be a [lo, hi] pair of numbers"); continue
                        }
                        if lo > hi { bad("`\(key)[\(i)]` has lo > hi (\(fmt(lo)) > \(fmt(hi)))") }
                        out.append([lo, hi])
                    }
                    bands[key] = out
                }
                tiers[id] = DifficultyTier(
                    id: id, label: t["label"]?.asString ?? "",
                    jokerCap: Int(cap ?? 0),
                    guaranteedMapJoker: t["guaranteedMapJoker"]?.asBool ?? false,
                    fixedJokers: fixedJokers, startJokers: startJokers,
                    stageBands: bands["stageBands"]!, bossBands: bands["bossBands"]!)
            }
        } else {
            problems.append("[difficulty.js] tiers: missing object")
        }

        var zen: [String: ZenConfig] = [:]
        if let zRoot = root["zen"]?.asObject {
            for id in zenIds {
                func bad(_ msg: String) { problems.append("[difficulty.js] zen.\(id): \(msg)") }
                guard let z = zRoot[id]?.asObject else { bad("missing zen entry"); continue }
                if (z["label"]?.asString ?? "").isEmpty { bad("missing/invalid `label` (non-empty string)") }
                let sc = z["suitCount"]?.asNumber
                if !(sc.map { $0.rounded(.down) == $0 && $0 >= 1 && $0 <= 4 } ?? false) {
                    bad("missing/invalid `suitCount` (integer 1-4 — suits kept from the standard deck)")
                }
                let pl = z["piles"]?.asNumber
                if !(pl.map { $0.rounded(.down) == $0 && $0 >= 1 } ?? false) {
                    bad("missing/invalid `piles` (positive integer — piles the deck deals onto)")
                }
                zen[id] = ZenConfig(id: id, label: z["label"]?.asString ?? "",
                                    suitCount: Int(sc ?? 1), piles: Int(pl ?? 1))
            }
        } else {
            problems.append("[difficulty.js] zen: missing object")
        }

        if !problems.isEmpty { throw DataValidationError(file: "difficulty.js", problems: problems) }
        return DifficultyData(endlessBandStep: step ?? 0, firstDealBand: firstDealBand,
                              firstDealBandV5: firstDealBandV5,
                              subset: subset, tiers: tiers, zenById: zen)
    }

    /// Numbers interpolate into JS strings without a trailing ".0".
    private static func fmt(_ d: Double) -> String {
        d == d.rounded() && abs(d) < 1e15 ? String(Int64(d)) : String(d)
    }
}
