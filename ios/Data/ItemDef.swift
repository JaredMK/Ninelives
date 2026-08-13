import Foundation

/// An item-unlock gate (`items.js` `unlock: { type, stat, count }`).
public struct UnlockGate: Equatable, Sendable {
    public let type: String   // "milestone" | "behavior" — documentary only
    public let stat: String   // one of GameMeta.itemUnlockStats
    public let count: Double
}

/// ONE entry from any items.js group (sticker / pillar / base / same-power / pack).
///
/// The typed fields mirror the shared shape the validator enforces; every OTHER
/// field stays reachable through `raw` / `num(_:_:)`, because items.js is
/// explicitly a file where "any other numeric field is an effect knob" and the
/// engine reads them by name (`itemNum(def, "digCount", 1)`).
public struct ItemDef: Equatable, Sendable {
    public let id: String
    public let label: String
    public let icon: String?
    /// "rank" | "behavior" (stickers), "scoring" | "guess" | "composition"
    /// (pillars), "active" (bases), pack kind. Absent on same-powers.
    public let kind: String?
    /// The behavior key GameEngine dispatches on (pillars / bases / same-powers).
    public let effect: String?
    /// The sticker behavior key GameEngine reads off a card.
    public let behavior: String?
    public let tier: String
    public let price: Double
    public let description: String
    /// The description OUTSIDE a climb (the Collection), where a variant
    /// template ({suit} / {color}) has no run to resolve against: it reads
    /// generically instead of leaking the placeholder.
    public var genericDescription: String {
        description
            .replacingOccurrences(of: "{suit}", with: "rolled suit")
            .replacingOccurrences(of: "{color}", with: "rolled red-or-black")
    }
    /// Optional store-offer weight override (replaces the tier weight).
    public let weight: Double?
    /// The single suit an effect is keyed to (Suit Guard, Suit Bounty, …).
    public let suit: String?
    /// Optional sticker application restriction — printed suits it may attach to.
    public let suits: [String]?
    /// Cursed stickers never enter a grant pool (curses are inflicted).
    public let cursed: Bool
    /// The shared curse roll's weight (cursed stickers only; > 0 required).
    public let curseWeight: Double
    /// Pathways this curse may NOT come from ("mystery" / "purge" /
    /// "duplicate" / "doors").
    public let curseExclude: [String]
    /// "pile" when a Base needs the player to pick a pile in its column.
    public let target: String?
    public let unlock: UnlockGate?
    /// The whole decoded entry, key → value.
    public let raw: [String: JSONValue]

    /// `itemNum(def, key, fallback)` — read a numeric effect tunable with an
    /// explicit fallback. 0 is a VALID hand-edited value, so this never treats
    /// it as "missing" (the web helper avoids `||` for exactly that reason).
    public func num(_ key: String, _ fallback: Double) -> Double {
        raw[key]?.asNumber ?? fallback
    }
    /// Integer flavour of `num` (JS knobs are whole numbers wherever the engine
    /// uses them as counts). Truncates toward zero like `|0` would.
    public func int(_ key: String, _ fallback: Int) -> Int {
        guard let d = raw[key]?.asNumber else { return fallback }
        return Int(d)
    }
    /// The `value` coefficient, defaulting to 0 — the web reads `t.value || 0`
    /// in payout sites and `def.value || 1` in Echo/Same-Power sites, so callers
    /// pick the fallback explicitly.
    public var value: Double { raw["value"]?.asNumber ?? 0 }

    public init(raw: [String: JSONValue]) {
        self.raw = raw
        self.id = raw["id"]?.asString ?? ""
        self.label = raw["label"]?.asString ?? ""
        self.icon = raw["icon"]?.asString
        self.kind = raw["kind"]?.asString
        self.effect = raw["effect"]?.asString
        self.behavior = raw["behavior"]?.asString
        self.tier = raw["tier"]?.asString ?? ""
        self.price = raw["price"]?.asNumber ?? 0
        self.description = raw["description"]?.asString ?? ""
        self.weight = raw["weight"]?.asNumber
        self.suit = raw["suit"]?.asString
        self.suits = raw["suits"]?.asArray?.compactMap(\.asString)
        self.cursed = raw["cursed"]?.asBool ?? false
        self.curseWeight = raw["curseWeight"]?.asNumber ?? 0
        self.curseExclude = raw["curseExclude"]?.asArray?.compactMap(\.asString) ?? []
        self.target = raw["target"]?.asString
        if let u = raw["unlock"]?.asObject {
            self.unlock = UnlockGate(
                type: u["type"]?.asString ?? "",
                stat: u["stat"]?.asString ?? "",
                count: u["count"]?.asNumber ?? 0
            )
        } else {
            self.unlock = nil
        }
    }
}

extension ItemDef: Codable {
    public init(from decoder: Decoder) throws {
        let dict = try decoder.singleValueContainer().decode([String: JSONValue].self)
        self.init(raw: dict)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(raw)
    }
}

/// The standard registry API over one items.js group — the Swift twin of
/// `makeRegistry(list)`. Order is the items.js order (it drives `ids`, the store
/// roll, and every "all()" walk), so this keeps the array and indexes beside it.
public struct ItemRegistry: Sendable {
    public let ids: [String]
    private let byId: [String: ItemDef]
    private let ordered: [ItemDef]

    public init(_ list: [ItemDef]) {
        self.ordered = list
        self.ids = list.map(\.id)
        self.byId = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
    public func get(_ id: String?) -> ItemDef? {
        guard let id else { return nil }
        return byId[id]
    }
    public func all() -> [ItemDef] { ordered }
    /// Cursed entries never enter the normal grant pools. `get(id)` still finds
    /// them and the apply path accepts them (the mystery cursedSticker event
    /// applies one directly). Item-unlock gating is layered on by the caller,
    /// which reads the LIVE unlock record — see `CampaignEnvironment.grantable`.
    public func grantableBase() -> [ItemDef] { ordered.filter { !$0.cursed } }

    /// THE shared curse pool for one inflicting pathway — every cursed
    /// sticker whose `curseExclude` doesn't name it, with its hand-tuned
    /// weight. All four cursing pathways (mystery, purge, duplicate, doors)
    /// pick from this via `rollCurse`.
    public func cursePool(path: String) -> [ItemDef] {
        ordered.filter { $0.cursed && $0.curseWeight > 0 && !$0.curseExclude.contains(path) }
    }

    /// One weighted pick from `cursePool(path:)`. `roll` is a uniform [0,1)
    /// draw from the CALLER's rng — the registry stays deterministic and
    /// side-effect free, so offer pre-rolls replay exactly.
    public func rollCurse(path: String, roll: Double) -> ItemDef? {
        let pool = cursePool(path: path)
        guard !pool.isEmpty else { return nil }
        let total = pool.reduce(0) { $0 + $1.curseWeight }
        var t = roll * total
        for def in pool {
            t -= def.curseWeight
            if t < 0 { return def }
        }
        return pool.last
    }
}
