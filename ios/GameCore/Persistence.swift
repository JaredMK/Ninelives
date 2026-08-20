import Foundation

/// The storage seam. The web build talks to `localStorage` under `ninelives.*`
/// keys (mirrored to Capacitor Preferences on iOS); GameCore stays DOM-free and
/// platform-free by talking to this instead. Every store below degrades to a
/// silent no-op when storage is unavailable, exactly like the web's private-mode
/// behaviour.
public protocol KeyValueStore: AnyObject {
    func string(forKey key: String) -> String?
    func set(_ value: String, forKey key: String)
    func remove(forKey key: String)
    /// Every key this store holds under the `ninelives.` prefix.
    func ninelivesKeys() -> [String]
}

/// The default, in-memory store — used by tests and by any host that hasn't
/// wired real storage yet.
public final class MemoryStore: KeyValueStore {
    private var values: [String: String] = [:]
    public init() {}
    public func string(forKey key: String) -> String? { values[key] }
    public func set(_ value: String, forKey key: String) { values[key] = value }
    public func remove(forKey key: String) { values[key] = nil }
    public func ninelivesKeys() -> [String] { values.keys.filter { $0.hasPrefix("ninelives.") }.sorted() }
}

/// A `UserDefaults`-backed store — the iOS analogue of `localStorage`.
public final class UserDefaultsStore: KeyValueStore {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public func string(forKey key: String) -> String? { defaults.string(forKey: key) }
    public func set(_ value: String, forKey key: String) { defaults.set(value, forKey: key) }
    public func remove(forKey key: String) { defaults.removeObject(forKey: key) }
    public func ninelivesKeys() -> [String] {
        defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("ninelives.") }.sorted()
    }
}

// MARK: - JSON helpers

public enum JSONStore {
    public static func read(_ store: KeyValueStore, _ key: String) -> [String: JSONValue]? {
        guard let s = store.string(forKey: key), let d = s.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([String: JSONValue].self, from: d)
    }
    public static func write(_ store: KeyValueStore, _ key: String, _ value: [String: JSONValue]) {
        guard let d = try? JSONEncoder().encode(value), let s = String(data: d, encoding: .utf8) else { return }
        store.set(s, forKey: key)
    }
}

// MARK: - Stats

/// The lifetime campaign record (`ninelives.stats.v1`). Absent/corrupted storage
/// always reads as the defaults; unknown fields are ignored on read, so the shape
/// can grow without a migration.
public struct StatsRecord: Sendable, Equatable {
    public var gamesPlayed = 0
    public var campaignsWon = 0
    public var runsCleared = 0
    public var bestRunDopamine = 0
    public var bestCampaignDopamine = 0
    public var lifetimeDopamine = 0
    public var lifetimeCardsFlipped = 0
    public var lifetimeCardsDrawn = 0
    public var lifetimeCorrectGuesses = 0
    public var lifetimeGuesses = 0
    public var furthestStage = 0
    public var furthestRun = 0
    /// Deepest ENDLESS stage ever entered (0 = never went endless).
    public var bestEndless = 0
    /// Best CONTINUOUS run score, any deck (v6.47: endless is a continuation
    /// of the climb, so there is ONE score per run and one best; the retired
    /// separate endless best folded in at decode, keeping the higher).
    public var bestCampaignScore = 0
    // UNLOCK1 item-unlock counters — all additive.
    public var bossesBeaten = 0
    public var cardsBuried = 0
    public var samesCalled = 0
    public var correctSames = 0
    public var jokersPlayed = 0
    public var stickersApplied = 0
    public var pillarsPlaced = 0
    public var basesPlaced = 0
    public var removalsUsed = 0
    public var pilesLost = 0
    // UNLOCK2 — the wider gate vocabulary. Cards LANDED by suit, so a player
    // who leans on one colour earns that colour's items.
    public var heartsPlayed = 0
    public var diamondsPlayed = 0
    public var clubsPlayed = 0
    public var spadesPlayed = 0
    /// Deals cleared without a single wrong guess.
    public var perfectDeals = 0
    /// Deals cleared per CAMPAIGN tier — "beat one on Legendary" is a
    /// different ask from "clear 40 deals", and gates the top-end items.
    public var dealsWonRegular = 0
    public var dealsWonMaster = 0
    public var dealsWonLegendary = 0
    /// Runs in which the player found the map's bottom quip (the Pinky tip
    /// easter egg). Counted once per run, so it rewards curiosity repeated
    /// across climbs rather than one long rubber-band.
    public var pinkyTipsSeen = 0
    /// Ambush deals CLEARED (Escape Hatch's instant win counts — it runs the
    /// same end check a real clear does).
    public var ambushesWon = 0
    /// Climbs LOST before the stage-1 boss fell. A "welcome to the game"
    /// gate: it can only tick early, so its item finds the player who needs it.
    public var earlyLosses = 0
    /// The most coins ever EARNED inside a single climb (not the purse — the
    /// purse gets spent). A high-water mark, like the score bests.
    public var bestCoinsInClimb = 0
    /// LIFETIME per-deck/tier win log: `["lammy.master": true, …]`.
    public var deckTierWins: [String: Bool] = [:]
    /// LIFETIME per-deck/tier best CONTINUOUS run score:
    /// `["pink.regular": 128, …]` (native-only — the web has no per-character
    /// score). ONE record per combo: endless continues the climb's total, so
    /// there is no separate endless best (v6.47; the old endless-best key is
    /// folded in at decode, keeping the higher).
    public var deckTierBest: [String: Int] = [:]
    /// LIFETIME times each shop item has been BOUGHT, keyed by item id
    /// (native-only, like `deckTierBest` — the web keeps no such tally). The
    /// Collection prints it under an unlocked tile, so the screen says what
    /// you actually reach for and not just what you've seen once. Exhibition
    /// buys are excluded, exactly as they are for the unlock counters.
    public var itemsBought: [String: Int] = [:]

    public init() {}

    /// The ONLY fields `bump` may touch — never the legacy tallies.
    public static let unlockCounters = [
        "bossesBeaten", "cardsBuried", "samesCalled", "correctSames", "jokersPlayed",
        "stickersApplied", "pillarsPlaced", "basesPlaced", "removalsUsed", "pilesLost",
        "heartsPlayed", "diamondsPlayed", "clubsPlayed", "spadesPlayed",
        "perfectDeals", "dealsWonRegular", "dealsWonMaster", "dealsWonLegendary",
        "pinkyTipsSeen", "ambushesWon", "earlyLosses",
    ]

    public subscript(counter: String) -> Int {
        get {
            switch counter {
            case "bossesBeaten": return bossesBeaten
            case "cardsBuried": return cardsBuried
            case "samesCalled": return samesCalled
            case "correctSames": return correctSames
            case "jokersPlayed": return jokersPlayed
            case "stickersApplied": return stickersApplied
            case "pillarsPlaced": return pillarsPlaced
            case "basesPlaced": return basesPlaced
            case "removalsUsed": return removalsUsed
            case "pilesLost": return pilesLost
            case "heartsPlayed": return heartsPlayed
            case "diamondsPlayed": return diamondsPlayed
            case "clubsPlayed": return clubsPlayed
            case "spadesPlayed": return spadesPlayed
            case "perfectDeals": return perfectDeals
            case "dealsWonRegular": return dealsWonRegular
            case "dealsWonMaster": return dealsWonMaster
            case "dealsWonLegendary": return dealsWonLegendary
            case "pinkyTipsSeen": return pinkyTipsSeen
            case "ambushesWon": return ambushesWon
            case "earlyLosses": return earlyLosses
            default: return 0
            }
        }
        set {
            switch counter {
            case "bossesBeaten": bossesBeaten = newValue
            case "cardsBuried": cardsBuried = newValue
            case "samesCalled": samesCalled = newValue
            case "correctSames": correctSames = newValue
            case "jokersPlayed": jokersPlayed = newValue
            case "stickersApplied": stickersApplied = newValue
            case "pillarsPlaced": pillarsPlaced = newValue
            case "basesPlaced": basesPlaced = newValue
            case "removalsUsed": removalsUsed = newValue
            case "pilesLost": pilesLost = newValue
            case "heartsPlayed": heartsPlayed = newValue
            case "diamondsPlayed": diamondsPlayed = newValue
            case "clubsPlayed": clubsPlayed = newValue
            case "spadesPlayed": spadesPlayed = newValue
            case "perfectDeals": perfectDeals = newValue
            case "dealsWonRegular": dealsWonRegular = newValue
            case "dealsWonMaster": dealsWonMaster = newValue
            case "dealsWonLegendary": dealsWonLegendary = newValue
            case "pinkyTipsSeen": pinkyTipsSeen = newValue
            case "ambushesWon": ambushesWon = newValue
            case "earlyLosses": earlyLosses = newValue
            default: break
            }
        }
    }

    static func decode(_ o: [String: JSONValue]) -> StatsRecord {
        var s = StatsRecord()
        func i(_ k: String) -> Int? { o[k]?.asNumber.map { Int($0) } }
        s.gamesPlayed = i("gamesPlayed") ?? 0
        s.campaignsWon = i("campaignsWon") ?? 0
        s.runsCleared = i("runsCleared") ?? 0
        s.bestRunDopamine = i("bestRunDopamine") ?? 0
        s.bestCampaignDopamine = i("bestCampaignDopamine") ?? 0
        s.lifetimeDopamine = i("lifetimeDopamine") ?? 0
        s.lifetimeCardsFlipped = i("lifetimeCardsFlipped") ?? 0
        s.lifetimeCardsDrawn = i("lifetimeCardsDrawn") ?? 0
        s.lifetimeCorrectGuesses = i("lifetimeCorrectGuesses") ?? 0
        s.lifetimeGuesses = i("lifetimeGuesses") ?? 0
        s.furthestStage = i("furthestStage") ?? 0
        s.furthestRun = i("furthestRun") ?? 0
        s.bestEndless = i("bestEndless") ?? 0
        // ONE-SCORE MIGRATION (v6.47): the retired separate endless bests
        // fold into the continuous best, keeping the higher — a device that
        // recorded either kind of record keeps it. Old builds reading a new
        // blob simply see no endless keys (their decode tolerates that).
        s.bestCampaignScore = max(i("bestCampaignScore") ?? 0, i("bestEndlessScore") ?? 0)
        s.bestCoinsInClimb = i("bestCoinsInClimb") ?? 0
        for k in unlockCounters { s[k] = i(k) ?? 0 }
        for (k, v) in o["deckTierWins"]?.asObject ?? [:] where v.asBool == true { s.deckTierWins[k] = true }
        for (k, v) in o["deckTierBest"]?.asObject ?? [:] { if let n = v.asNumber { s.deckTierBest[k] = Int(n) } }
        for (k, v) in o["deckTierBestEndless"]?.asObject ?? [:] {
            if let n = v.asNumber { s.deckTierBest[k] = max(s.deckTierBest[k] ?? 0, Int(n)) }
        }
        for (k, v) in o["itemsBought"]?.asObject ?? [:] { if let n = v.asNumber, n > 0 { s.itemsBought[k] = Int(n) } }
        return s
    }

    func encoded() -> [String: JSONValue] {
        var o: [String: JSONValue] = [
            "gamesPlayed": .number(Double(gamesPlayed)),
            "campaignsWon": .number(Double(campaignsWon)),
            "runsCleared": .number(Double(runsCleared)),
            "bestRunDopamine": .number(Double(bestRunDopamine)),
            "bestCampaignDopamine": .number(Double(bestCampaignDopamine)),
            "lifetimeDopamine": .number(Double(lifetimeDopamine)),
            "lifetimeCardsFlipped": .number(Double(lifetimeCardsFlipped)),
            "lifetimeCardsDrawn": .number(Double(lifetimeCardsDrawn)),
            "lifetimeCorrectGuesses": .number(Double(lifetimeCorrectGuesses)),
            "lifetimeGuesses": .number(Double(lifetimeGuesses)),
            "furthestStage": .number(Double(furthestStage)),
            "furthestRun": .number(Double(furthestRun)),
            "bestEndless": .number(Double(bestEndless)),
            "bestCampaignScore": .number(Double(bestCampaignScore)),
            "bestCoinsInClimb": .number(Double(bestCoinsInClimb)),
        ]
        for k in Self.unlockCounters { o[k] = .number(Double(self[k])) }
        o["deckTierWins"] = .object(deckTierWins.mapValues { .bool($0) })
        o["deckTierBest"] = .object(deckTierBest.mapValues { .number(Double($0)) })
        o["itemsBought"] = .object(itemsBought.mapValues { .number(Double($0)) })
        return o
    }
}

/// `ninelives.stats.v1`.
public final class Stats {
    public static let key = "ninelives.stats.v1"
    private let store: KeyValueStore
    private var cache: StatsRecord?

    public init(store: KeyValueStore) { self.store = store }

    public func get() -> StatsRecord {
        if let cache { return cache }
        let s = JSONStore.read(store, Self.key).map(StatsRecord.decode) ?? StatsRecord()
        cache = s
        return s
    }
    public func put(_ s: StatsRecord) {
        cache = s
        JSONStore.write(store, Self.key, s.encoded())
    }
    /// Bump one item-unlock counter (never the legacy tallies).
    public func bump(_ counter: String, _ n: Int = 1) {
        guard StatsRecord.unlockCounters.contains(counter), n != 0 else { return }
        var s = get()
        s[counter] = s[counter] + n
        put(s)
    }
    /// Record one BUY of shop item `id` (the Collection's lifetime tally).
    /// Keyed by the registry id, which is stable across renames by contract,
    /// so the count survives an item being relabelled.
    public func bumpItemBought(_ id: String, _ n: Int = 1) {
        guard !id.isEmpty, n > 0 else { return }
        var s = get()
        s.itemsBought[id, default: 0] += n
        put(s)
    }
    public func bumpAll(_ counters: [String: Int]) {
        var s = get()
        var moved = false
        for (k, n) in counters where StatsRecord.unlockCounters.contains(k) && n != 0 {
            s[k] = s[k] + n
            moved = true
        }
        if moved { put(s) }
    }
    public func reset() {
        cache = nil
        store.remove(forKey: Self.key)
    }
}

// MARK: - ZenStats

public struct ZenEntry: Sendable, Equatable {
    public var games = 0
    public var wins = 0
    public var cardsFlipped = 0
    public var correctGuesses = 0
    /// Count-keyed distributions (forward-only; never back-filled).
    public var winPiles: [Int: Int] = [:]
    public var lossCards: [Int: Int] = [:]
    public init() {}
}

/// `ninelives.zenstats.v1` — Zen's OWN lifetime record, per difficulty. Zen play
/// never moves a campaign tally and campaign play never moves these.
public final class ZenStats {
    public static let key = "ninelives.zenstats.v1"
    private let store: KeyValueStore
    private let ids: [String]

    public init(store: KeyValueStore, ids: [String] = DifficultyData.zenIds) {
        self.store = store; self.ids = ids
    }

    private func all() -> [String: ZenEntry] {
        let root = JSONStore.read(store, Self.key) ?? [:]
        var out: [String: ZenEntry] = [:]
        for id in ids {
            var e = ZenEntry()
            if let o = root[id]?.asObject {
                e.games = Int(o["games"]?.asNumber ?? 0)
                e.wins = Int(o["wins"]?.asNumber ?? 0)
                e.cardsFlipped = Int(o["cardsFlipped"]?.asNumber ?? 0)
                e.correctGuesses = Int(o["correctGuesses"]?.asNumber ?? 0)
                for (k, v) in o["winPiles"]?.asObject ?? [:] { if let n = Int(k) { e.winPiles[n] = Int(v.asNumber ?? 0) } }
                for (k, v) in o["lossCards"]?.asObject ?? [:] { if let n = Int(k) { e.lossCards[n] = Int(v.asNumber ?? 0) } }
            }
            out[id] = e
        }
        return out
    }

    public func get(_ id: String) -> ZenEntry { all()[id] ?? ZenEntry() }

    public func put(_ id: String, _ e: ZenEntry) {
        var root = JSONStore.read(store, Self.key) ?? [:]
        root[id] = .object([
            "games": .number(Double(e.games)),
            "wins": .number(Double(e.wins)),
            "cardsFlipped": .number(Double(e.cardsFlipped)),
            "correctGuesses": .number(Double(e.correctGuesses)),
            "winPiles": .object(Dictionary(uniqueKeysWithValues: e.winPiles.map { (String($0.key), JSONValue.number(Double($0.value))) })),
            "lossCards": .object(Dictionary(uniqueKeysWithValues: e.lossCards.map { (String($0.key), JSONValue.number(Double($0.value))) })),
        ])
        JSONStore.write(store, Self.key, root)
    }

    /// Total games across every difficulty (the `zenGamesPlayed` unlock reader).
    public func totalGames() -> Int { ids.reduce(0) { $0 + get($1).games } }
    public func reset() { store.remove(forKey: Self.key) }
}

// MARK: - DeckUnlocks

/// `ninelives.deckwins.v1` — which deck/tier pairs have been WON.
public final class DeckUnlocks {
    public static let key = "ninelives.deckwins.v1"
    private let store: KeyValueStore
    public init(store: KeyValueStore) { self.store = store }

    private func get() -> [String: Bool] {
        (JSONStore.read(store, Self.key) ?? [:]).compactMapValues { $0.asBool }
    }
    private func put(_ w: [String: Bool]) {
        JSONStore.write(store, Self.key, w.mapValues { JSONValue.bool($0) })
    }

    /// Regular wins keep the LEGACY key (deck id alone); master/legendary wins
    /// store under "deckId.tier".
    static func key(_ deckId: String, _ tier: String?) -> String {
        (tier == nil || tier == "regular") ? deckId : "\(deckId).\(tier!)"
    }

    /// Returns TRUE only when this is the FIRST recorded win with the deck.
    @discardableResult
    public func recordWin(deckId: String, tier: String?) -> Bool {
        guard !deckId.isEmpty else { return false }
        let k = Self.key(deckId, tier)
        var w = get()
        if w[k] == true { return false }
        w[k] = true
        put(w)
        return true
    }
    public func wonWith(_ deckId: String) -> Bool { get()[deckId] == true }
    public func wonWithTier(_ deckId: String, _ tier: String?) -> Bool { get()[Self.key(deckId, tier)] == true }
    /// ODDS ASSIST gate (v6.71): any deck's Straight (legendary) win. Reads
    /// the stored keys directly, so it needs no roster and — like every win
    /// record — never un-sets and survives save/restore and the deck renames.
    public func wonAnyStraight() -> Bool {
        get().contains { $0.key.hasSuffix(".legendary") && $0.value }
    }
    public func reset() { store.remove(forKey: Self.key) }

    /// Load-time repair + migration, in three passes: legacy Pinky credit,
    /// Stats-log merge, then DOWNWARD COMPLETION (legendary ⇒ master ⇒ base).
    public func grantRetroactive(_ stats: StatsRecord) {
        var w = get()
        var dirty = false
        if stats.campaignsWon > 0 && w.isEmpty { w["pink"] = true; dirty = true }
        for (k, v) in stats.deckTierWins where v {
            let base = k.hasSuffix(".regular") ? String(k.dropLast(".regular".count)) : k
            if w[base] != true { w[base] = true; dirty = true }
        }
        for k in w.keys where k.hasSuffix(".legendary") {
            let k2 = String(k.dropLast("legendary".count)) + "master"
            if w[k2] != true { w[k2] = true; dirty = true }
        }
        for k in w.keys {
            guard let dot = k.firstIndex(of: "."), k.hasSuffix(".master") || k.hasSuffix(".legendary") else { continue }
            let base = String(k[k.startIndex..<dot])
            if w[base] != true { w[base] = true; dirty = true }
        }
        if dirty { put(w) }
    }
}

// MARK: - ZenUnlocks

/// `ninelives.zenunlocks.v1` — which Zen difficulties have been WON. Deliberately
/// SEPARATE from ZenStats: a stats reset must never re-lock a difficulty.
public final class ZenUnlocks {
    public static let key = "ninelives.zenunlocks.v1"
    private let store: KeyValueStore
    private let ids: [String]
    public init(store: KeyValueStore, ids: [String] = DifficultyData.zenIds) {
        self.store = store; self.ids = ids
    }
    private func get() -> [String: Bool] {
        (JSONStore.read(store, Self.key) ?? [:]).compactMapValues { $0.asBool }
    }
    private func put(_ w: [String: Bool]) { JSONStore.write(store, Self.key, w.mapValues { JSONValue.bool($0) }) }

    @discardableResult
    public func recordWin(_ id: String) -> Bool {
        guard ids.contains(id) else { return false }
        var w = get()
        if w[id] == true { return false }
        w[id] = true; put(w)
        return true
    }
    public func won(_ id: String) -> Bool { get()[id] == true }
    /// The ladder: the first difficulty is always open; each later one needs the
    /// previous beaten.
    public func unlocked(_ id: String) -> Bool {
        guard let i = ids.firstIndex(of: id) else { return false }
        return i == 0 || won(ids[i - 1])
    }
    /// RETROACTIVE: wins already recorded in ZenStats re-grant at load.
    public func grantRetroactive(_ zen: ZenStats) {
        var w = get()
        var dirty = false
        for id in ids where zen.get(id).wins >= 1 && w[id] != true { w[id] = true; dirty = true }
        if dirty { put(w) }
    }
    public func reset() { store.remove(forKey: Self.key) }
}

// MARK: - Save migrations

/// One-time, stamped rewrites of stored blobs — run at boot BEFORE anything
/// reads the store.
public enum SaveMigrations {
    /// v6.67 CHARACTER RENAME: deck ids "smith" → "garden", "lammy" → "rocko".
    /// Rewrites every known blob that carries deck ids — deck wins (keys like
    /// "smith" / "smith.legendary"), lifetime stats (deckTierBest keys), the
    /// campaign checkpoint ("deckId":"smith"), and the deck pref — so unlocks,
    /// records and an in-flight climb all survive the rename. The tokens only
    /// ever appear QUOTED as whole JSON keys/values or key prefixes (no item
    /// id, stat name or card field contains either — checked at v6.67), so a
    /// quoted-token replace is exact. Stamped, so it runs once.
    public static let deckIdStamp = "ninelives.migr.deckids.v1"

    public static func migrateDeckIds(_ store: KeyValueStore) {
        guard store.string(forKey: deckIdStamp) == nil else { return }
        store.set("1", forKey: deckIdStamp)
        let renames = [("smith", "garden"), ("lammy", "rocko")]
        for key in [DeckUnlocks.key, Stats.key, SaveStore.key] {
            guard var blob = store.string(forKey: key) else { continue }
            for (old, new) in renames {
                blob = blob.replacingOccurrences(of: "\"\(old)\"", with: "\"\(new)\"")
                blob = blob.replacingOccurrences(of: "\"\(old).", with: "\"\(new).")
            }
            store.set(blob, forKey: key)
        }
        // The remembered deck-select choice, if one is stored as a bare pref.
        for name in ["deck", "lastDeck"] {
            if let v = store.string(forKey: "ninelives.pref.\(name)"),
               let mapped = ["smith": "garden", "lammy": "rocko"][v] {
                store.set(mapped, forKey: "ninelives.pref.\(name)")
            }
        }
    }
}

// MARK: - SaveStore

/// `ninelives.save.v1` — the campaign checkpoint, plus the `ninelives.pref.*`
/// settings namespace.
public final class SaveStore {
    public static let key = "ninelives.save.v1"
    private let store: KeyValueStore
    public init(store: KeyValueStore) { self.store = store }

    public func save(_ blob: [String: JSONValue]) { JSONStore.write(store, Self.key, blob) }
    public func load() -> [String: JSONValue]? { JSONStore.read(store, Self.key) }
    public func clear() { store.remove(forKey: Self.key) }
    public var hasSave: Bool { store.string(forKey: Self.key) != nil }

    public func pref(_ name: String) -> String? { store.string(forKey: "ninelives.pref.\(name)") }
    public func setPref(_ name: String, _ value: String) { store.set(value, forKey: "ninelives.pref.\(name)") }
    public func clearPref(_ name: String) { store.remove(forKey: "ninelives.pref.\(name)") }
}
