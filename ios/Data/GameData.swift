import Foundation

/// Per-deck gameplay modifiers (the deck characters). Pinky is the baseline and
/// carries NO modifiers. Lifted from index.html's `DECK_RULES` by
/// `ios/Tools/export-data.mjs` so Swift never hardcodes them either.
public struct DeckRules: Sendable, Equatable {
    /// 13-card start with one card of each rank at a RANDOM suit; stages are
    /// plain 1/2/3 (not suit-segmented) — every pickup/pack rolls all four suits.
    public let altSuits: Bool
    /// Shop price multiplier (every item price, incl. Removal).
    public let priceMult: Double
    /// A random ELIGIBLE sticker on each of the 13 starting cards.
    public let startStickers: Bool
    /// Stickers unusable: store sticker slots grey out, card packs mint no
    /// stickered cards, and no effect can sticker a card.
    public let noStickers: Bool
    /// 3 random Pillars + 3 random Bases fill the six column slots at run
    /// start — and a random Same-Power rides along (v6.67, Rocko).
    public let preEquip: Bool
    /// EVERY card carries a random sticker (v6.67, Mr. Garden): the whole
    /// draft pool at run start and every card minted later — so store cards,
    /// packs and map pickups all SHOW their sticker before they're taken.
    public let stickerEverything: Bool
    /// Pillars and Bases don't exist for this deck (v6.67, Mr. Garden): they
    /// can't be equipped and the store never offers them (Same-Powers stay).
    public let noPillarsBases: Bool
    /// Fixed-rank start deck (v6.67, Slyrex): rank value → count. Empty means
    /// the standard one-of-each-rank start. Cards beyond a rank's four suits
    /// are minted as duplicates.
    public let startRanks: [Int: Int]

    public init(altSuits: Bool, priceMult: Double, startStickers: Bool, noStickers: Bool,
                preEquip: Bool, stickerEverything: Bool = false, noPillarsBases: Bool = false,
                startRanks: [Int: Int] = [:]) {
        self.altSuits = altSuits; self.priceMult = priceMult
        self.startStickers = startStickers; self.noStickers = noStickers
        self.preEquip = preEquip; self.stickerEverything = stickerEverything
        self.noPillarsBases = noPillarsBases; self.startRanks = startRanks
    }
}

/// index.html-sourced constants that are neither items.js nor difficulty.js.
public struct GameMeta: Sendable {
    /// The 19 lifetime counters an items.js `unlock.stat` may name.
    public let itemUnlockStats: [String]
    public let deckRules: [String: DeckRules]
    /// `deckRulesFor(id)` — unknown ids fall back to Pinky.
    public func rules(_ id: String) -> DeckRules { deckRules[id] ?? deckRules["pink"]! }
    /// Deck ids in their canonical unlock-chain order (v6.67: Slyrex joins
    /// after Mamma; Mr. Smith is Mr. Garden now, Lammy is Rocko, Rocko last).
    public static let deckOrder = ["pink", "mamma", "slyrex", "garden", "rocko"]
}

/// The loaded + validated data layer: the three data files plus the registries
/// built over them. One instance is the process-wide `GameData.shared`, exactly
/// as the web build's `ItemData` / `StickerTypes` / … are module globals.
public final class GameData: @unchecked Sendable {
    public let items: ItemData
    public let difficulty: DifficultyData
    public let tutorial: TutorialData
    public let meta: GameMeta

    public let stickerTypes: ItemRegistry
    public let pillarTypes: ItemRegistry
    public let baseTypes: ItemRegistry
    public let samePowerTypes: ItemRegistry
    public let packTypes: ItemRegistry

    public init(items: ItemData, difficulty: DifficultyData, tutorial: TutorialData, meta: GameMeta) {
        self.items = items
        self.difficulty = difficulty
        self.tutorial = tutorial
        self.meta = meta
        self.stickerTypes = ItemRegistry(items.stickers)
        self.pillarTypes = ItemRegistry(items.pillars)
        self.baseTypes = ItemRegistry(items.bases)
        self.samePowerTypes = ItemRegistry(items.samePowers)
        self.packTypes = ItemRegistry(items.packs)
    }

    // MARK: - Loading

    public enum LoadError: Error, CustomStringConvertible {
        case missingResource(String, Bundle)
        public var description: String {
            switch self {
            case .missingResource(let name, let b):
                return "\(name) did not load — it is not in \(b.bundleURL.lastPathComponent). "
                     + "Run `node ios/Tools/export-data.mjs` and rebuild."
            }
        }
    }

    /// The bundle GameCore's resources live in (the framework itself).
    public static var resourceBundle: Bundle { Bundle(for: GameData.self) }

    public static func load(from bundle: Bundle) throws -> GameData {
        func read(_ name: String) throws -> Data {
            guard let url = bundle.url(forResource: name, withExtension: "json") else {
                throw LoadError.missingResource("\(name).json", bundle)
            }
            return try Data(contentsOf: url)
        }
        let metaRoot = try JSONDecoder().decode([String: JSONValue].self, from: try read("meta"))
        let unlockStats = metaRoot["itemUnlockStats"]?.asArray?.compactMap(\.asString) ?? []
        var rules: [String: DeckRules] = [:]
        for (id, v) in metaRoot["deckRules"]?.asObject ?? [:] {
            guard let o = v.asObject else { continue }
            var startRanks: [Int: Int] = [:]
            for (r, n) in o["startRanks"]?.asObject ?? [:] {
                if let rv = Int(r), let nv = n.asNumber { startRanks[rv] = Int(nv) }
            }
            rules[id] = DeckRules(
                altSuits: o["altSuits"]?.asBool ?? false,
                priceMult: o["priceMult"]?.asNumber ?? 1,
                startStickers: o["startStickers"]?.asBool ?? false,
                noStickers: o["noStickers"]?.asBool ?? false,
                preEquip: o["preEquip"]?.asBool ?? false,
                stickerEverything: o["stickerEverything"]?.asBool ?? false,
                noPillarsBases: o["noPillarsBases"]?.asBool ?? false,
                startRanks: startRanks)
        }
        guard rules["pink"] != nil else {
            throw DataValidationError(file: "meta.json", problems: ["[meta.json] deckRules.pink: missing (the baseline deck)"])
        }
        let meta = GameMeta(itemUnlockStats: unlockStats, deckRules: rules)
        return GameData(
            items: try ItemData.decode(try read("items"), unlockStats: unlockStats),
            difficulty: try DifficultyData.decode(try read("difficulty")),
            tutorial: try TutorialData.decode(try read("tutorial")),
            meta: meta)
    }

    /// Load from GameCore's own bundle. Throws exactly like the web build's
    /// boot-time validation does.
    public static func loadBundled() throws -> GameData { try load(from: resourceBundle) }

    /// The process-wide instance the engine reads, mirroring the web globals.
    /// A validation failure here is fatal by design — the web build throws at
    /// script load and the game never boots.
    public static let shared: GameData = {
        do { return try loadBundled() }
        catch { fatalError("GameCore data validation FAILED:\n\(error)") }
    }()
}
