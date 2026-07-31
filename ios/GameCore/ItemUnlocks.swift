import Foundation

/// The item-unlock drip (`ninelives.itemunlocks.v1`).
///
/// An items.js `unlock: { type, stat, count }` keeps an item out of EVERY roll
/// pool (store classes, sticker grants, sticker packs, Lammy's pre-equip) until
/// the LIFETIME counter `stat` reaches `count`. Absent = a starting item.
public final class ItemUnlocks {
    public static let key = "ninelives.itemunlocks.v1"

    private let store: KeyValueStore
    private let data: GameData
    private let stats: Stats
    private let zenStats: ZenStats
    private var knownCache: [String]?

    public init(store: KeyValueStore, data: GameData = .shared, stats: Stats, zenStats: ZenStats) {
        self.store = store; self.data = data; self.stats = stats; self.zenStats = zenStats
    }

    /// Every gateable item across the five registries.
    public func allDefs() -> [ItemDef] {
        data.items.stickers + data.items.pillars + data.items.bases
            + data.items.samePowers + data.items.packs
    }

    /// stat name → its live value. ONE reader per `ITEM_UNLOCK_STATS` entry: the
    /// aliases point at pre-existing counters, the rest at the additive Stats
    /// fields. Zen readers ignore the Stats record entirely — Zen keeps its own
    /// per-difficulty store, so a veteran's Zen record counts retroactively.
    public func statValue(_ name: String) -> Int {
        let s = stats.get()
        switch name {
        case "dealsSurvived":        return s.runsCleared
        case "runsPlayed":           return s.gamesPlayed
        case "runsWon":              return s.campaignsWon
        case "bossesBeaten":         return s.bossesBeaten
        case "endlessStagesReached": return s.bestEndless
        case "coinsEarnedLifetime":  return s.lifetimeDopamine
        case "cardsBuried":          return s.cardsBuried
        case "samesCalled":          return s.samesCalled
        case "correctSames":         return s.correctSames
        case "jokersPlayed":         return s.jokersPlayed
        case "stickersApplied":      return s.stickersApplied
        case "pillarsPlaced":        return s.pillarsPlaced
        case "basesPlaced":          return s.basesPlaced
        case "removalsUsed":         return s.removalsUsed
        case "pilesLost":            return s.pilesLost
        case "zenGamesPlayed":       return zenStats.totalGames()
        case "zenEasyWon":           return zenStats.get("easy").wins
        case "zenMediumWon":         return zenStats.get("medium").wins
        case "zenHardWon":           return zenStats.get("hard").wins
        default:                     return 0
        }
    }

    /// An ungated item is always available; a gated one needs its threshold met.
    public func isUnlocked(_ def: ItemDef) -> Bool {
        guard let u = def.unlock else { return true }
        return Double(statValue(u.stat)) >= u.count
    }

    /// "How to earn it" phrasing — the ONE place this copy lives.
    public func hint(for def: ItemDef) -> String {
        guard let u = def.unlock else { return "" }
        let n = Int(u.count)
        func pl(_ one: String, _ many: String? = nil) -> String {
            "\(n) " + (n == 1 ? one : (many ?? one + "s"))
        }
        switch u.stat {
        case "dealsSurvived":        return "Clear " + pl("deal")
        case "runsPlayed":           return "Play " + pl("climb")
        case "runsWon":              return "Win " + pl("climb")
        case "bossesBeaten":         return "Beat " + pl("boss", "bosses")
        case "endlessStagesReached": return "Reach endless stage \(n)"
        case "coinsEarnedLifetime":  return "Earn \(n) lifetime coins"
        case "cardsBuried":          return "Bury " + pl("card")
        case "samesCalled":          return "Call Same " + pl("time")
        case "correctSames":         return "Win \(n) Same " + (n == 1 ? "call" : "calls")
        case "jokersPlayed":         return "Play " + pl("Joker")
        case "stickersApplied":      return "Apply " + pl("sticker")
        case "pillarsPlaced":        return "Place " + pl("Pillar")
        case "basesPlaced":          return "Place " + pl("Base")
        case "removalsUsed":         return "Remove " + pl("card")
        case "pilesLost":            return "Lose " + pl("pile")
        case "zenGamesPlayed":       return "Play " + pl("Zen game")
        case "zenEasyWon":           return n == 1 ? "Beat Zen on Easy" : "Beat Zen Easy \(n) times"
        case "zenMediumWon":         return n == 1 ? "Beat Zen on Medium" : "Beat Zen Medium \(n) times"
        case "zenHardWon":           return n == 1 ? "Beat Zen on Hard" : "Beat Zen Hard \(n) times"
        default:                     return ""
        }
    }

    /// The known-set, lazy. FIRST LOAD (no stored blob): initialized SILENTLY to
    /// the full derived unlocked set — retroactive, no toast spam — and persisted.
    private func knownSet() -> [String] {
        if let knownCache { return knownCache }
        if let stored = JSONStore.read(store, Self.key)?["known"]?.asArray?.compactMap(\.asString) {
            knownCache = stored
            return stored
        }
        let fresh = allDefs().filter(isUnlocked).map(\.id)
        knownCache = fresh
        persist(fresh)
        return fresh
    }
    private func persist(_ arr: [String]) {
        JSONStore.write(store, Self.key, ["known": .array(arr.map { .string($0) })])
    }

    public struct Unlocked: Sendable, Equatable {
        public var id: String
        public var hint: String
    }

    /// Derived-unlocked items not yet in the known-set: stamp them and return
    /// their descriptors. Call at deal end / run end ONLY — never mid-guess
    /// (a mid-run call stamps the known-set and swallows the pops).
    @discardableResult
    public func checkNewUnlocks() -> [Unlocked] {
        var known = knownSet()
        let fresh = allDefs().filter { $0.unlock != nil && isUnlocked($0) && !known.contains($0.id) }
        if !fresh.isEmpty {
            known.append(contentsOf: fresh.map(\.id))
            knownCache = known
            persist(known)
        }
        return fresh.map { Unlocked(id: $0.id, hint: hint(for: $0)) }
    }

    public struct NearMiss: Sendable, Equatable {
        public var id: String
        public var current: Int
        public var count: Double
        public var fraction: Double
        public var hint: String
    }

    /// The n LOCKED items closest to unlocking, by progress fraction desc.
    public func nearestLocked(_ n: Int = 1) -> [NearMiss] {
        allDefs()
            .filter { $0.unlock != nil && !isUnlocked($0) }
            .map { d -> NearMiss in
                let u = d.unlock!
                let current = statValue(u.stat)
                return NearMiss(id: d.id, current: current, count: u.count,
                                fraction: u.count > 0 ? min(1, Double(current) / u.count) : 0,
                                hint: hint(for: d))
            }
            .stableSorted { $0.fraction > $1.fraction }
            .prefix(max(0, n))
            .map { $0 }
    }

    /// BOOT-TIME known-set priming: pins the baseline BEFORE any play, so the
    /// first checkpoint sees the session's crossings. Do not remove.
    public func primeKnown() { _ = knownSet() }

    public func reset() {
        knownCache = nil
        store.remove(forKey: Self.key)
    }
}
