import Foundation

/// GEN_CONFIG — every tunable of the random stage generator.
///
/// `difficulty = (deck − piles) / piles`, checked at BOTH deck extremes
/// (lightest and heaviest possible route into each deal).
public struct MapConfig: Sendable {
    /// Traveled phases, in order. Hearts are NOT here — they are pre-held.
    public var phaseSuits = ["♦", "♣", "♠"]
    public var startSuit = "♥"
    /// 13 hearts pre-held at run start.
    public var startDeckSize = 13

    /// MYSTERY ("?") nodes. genV ≥ 3 (MYST3): mystery is a FIRST-CLASS node type
    /// rolled INSIDE rollType at this weight (25/125 ≈ 20%).
    public var mysteryTypeWeight: Double = 25
    /// LEGACY genV < 3 ONLY: the retired cosmetic mask's per-node chance.
    public var mysteryChance: Double = 0.2

    /// Graph shape (per stage): nodes sit on a 3-lane grid.
    public var lanes = 3
    public var laneX: [Double] = [0.17, 0.50, 0.83]
    /// Total rows per stage INCLUDING the boss row.
    public var rows = [14, 14]
    /// Random bottom→top paths drawn per stage; their union is the DAG.
    public var paths = [4, 6]
    /// SOFT/report only — braiding is emergent from overlapping paths.
    public var minForksPerRoute = 2

    /// Node-type roll weights (genV ≥ 3 adds MYSTERY at mysteryTypeWeight).
    public var typeWeights: [(String, Double)] = [("deal", 26), ("pack", 32), ("card", 42)]
    /// The +N pack-size distribution: [value, weight] pairs.
    public var packWeights: [(Int, Double)] = [(2, 4), (3, 2)]

    /// Hard cap validated on every route (excl. boss).
    public var dealsPerRouteMax = 5
    /// Stores per stage.
    public var stores = [3, 4]
    /// GUARANTEED PRE-BOSS SHOP: ≥1 store must sit in the last N body rows.
    public var preBossStoreRows = 3

    /// Every route totals ≥ minRouteCards; at least one route stays ≤ maxLight.
    public var minRouteCards = 11
    public var maxLightRouteCards = 15
    /// FULL-MAP GENERATION: later stages need a PREDICTED entry-deck size.
    public var predictedRouteCards = 13
    public var addOptions = [1, 2, 3, 4, 5]
    public var packMax = 5

    /// Pile bounds for any deal.
    public var minPiles = 3
    public var maxPiles = 12

    /// Generation control.
    public var attempts = 60
    public var structAttempts = 40
    public var relaxSteps = 3
    public var relaxBandStep = 0.15
    public var seedLadderRungs = 8
    public var maxRoutes = 40000

    public init() {}
}

/// One node in a phase map. A reference type: generation mutates node types,
/// pack sizes and pile counts in place across a dozen repair passes, exactly as
/// the JS does on its plain objects.
public final class MapNode {
    public var id: Int
    /// GLOBAL row once the stages are stacked; the per-stage row before that.
    public var row: Int
    /// Row within the node's own stage (set when the map is stacked).
    public var localRow: Int?
    public var lane: Int?
    public var x: Double
    /// "deal" | "boss" | "store" | "pack" | "pickup" | "mystery" | "pass" | "home"
    public var type: String
    public var next: [Int]
    public var piles: Int?
    public var targetD: Double?
    public var packCount: Int?
    /// Mirrors packCount for packs / 1 for pickups (the authored-format field).
    public var add: Int?
    public var suit: String?
    public var mixed: Bool?
    /// Authored maps may pin an exact card ("K♦").
    public var forceCard: String?
    /// A fixed post-boss corridor node the campaign locks a Joker onto.
    public var jokerNode: Bool = false
    /// LEGACY genV < 3 cosmetic mask.
    public var mystery: Bool = false
    public var phase: Int?

    public init(id: Int, row: Int, lane: Int? = nil, x: Double = 0.5,
                type: String = "", next: [Int] = []) {
        self.id = id; self.row = row; self.lane = lane; self.x = x
        self.type = type; self.next = next
    }

    /// Cards a node adds to the deck (0 for deals/stores/boss).
    /// `packCount || 2` — a 0/absent count reads as 2, exactly like the JS.
    public var addOf: Int {
        switch type {
        case "pickup": return 1
        case "pack": return (packCount ?? 0) != 0 ? packCount! : 2
        default: return 0
        }
    }
}

/// One generated (or authored) stage map.
public final class PhaseMap {
    public var phaseIndex: Int
    public var suit: String
    public var rows: Int
    public var bossRow: Int
    public var nodes: [MapNode]
    public var byId: [Int: MapNode]
    public var bossId: Int
    public var bossIds: [Int]
    public var row0: [Int]
    /// Diagnostics from the winning attempt (`_gen` in the JS).
    public var gen: GenReport?

    public init(phaseIndex: Int, suit: String, rows: Int, bossRow: Int,
                nodes: [MapNode], bossId: Int, bossIds: [Int], row0: [Int]) {
        self.phaseIndex = phaseIndex; self.suit = suit
        self.rows = rows; self.bossRow = bossRow
        self.nodes = nodes
        self.byId = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        self.bossId = bossId; self.bossIds = bossIds; self.row0 = row0
    }

    public func reindex() {
        byId = Dictionary(nodes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }
}

public struct GenReport: Sendable {
    public var attempt: Int
    public var relax: Int
    public var entryDeck: Int
    public var warnings: [String]
    public var report: StageReport
}

/// Per-stage metadata in a stacked run map.
public struct PhaseMeta: Sendable {
    public var phase: Int
    public var suit: String
    public var bossId: Int
    public var bossIds: [Int]
    public var row0: [Int]
    public var rowStart: Int
    public var rows: Int
    /// The fixed post-boss Joker corridor node, when this stage has one.
    public var jokerNodeId: Int?
}

/// The whole run as ONE continuous graph.
public final class RunMapGraph {
    public var nodes: [MapNode]
    public var byId: [Int: MapNode]
    public var phases: [PhaseMeta]
    public var row0: [Int]
    public var homeId: Int?
    public var totalRows: Int
    /// The RUN boss is ALWAYS the ♠ (stage-3) boss — endless bosses above it
    /// never end the run.
    public var runBossId: Int?
    public var runBossIds: [Int]?
    public var stagesGenerated: Int

    init(nodes: [MapNode], phases: [PhaseMeta], row0: [Int], homeId: Int?,
         totalRows: Int, runBossId: Int?, runBossIds: [Int]?, stagesGenerated: Int) {
        self.nodes = nodes
        self.byId = Dictionary(nodes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        self.phases = phases; self.row0 = row0; self.homeId = homeId
        self.totalRows = totalRows; self.runBossId = runBossId
        self.runBossIds = runBossIds; self.stagesGenerated = stagesGenerated
    }
}

// MARK: - JS-shaped random helpers

/// `ri(rng, range)` = `range[0] + Math.floor(rng() * (range[1] - range[0] + 1))`.
@inlinable
public func randInt(_ rng: RNG, _ range: [Int]) -> Int {
    range[0] + Int(rng.next() * Double(range[1] - range[0] + 1))
}

/// `pick(rng, arr)` = `arr[Math.floor(rng() * arr.length)]`.
@inlinable
public func pickOne<T>(_ rng: RNG, _ arr: [T]) -> T {
    arr[Int(rng.next() * Double(arr.count))]
}

/// `wpick(rng, entries)` — weighted pick over `[[value, weight], …]`, walked in
/// order. Exactly one `rng()` call, whatever the table.
public func weightedPick<T>(_ rng: RNG, _ entries: [(T, Double)]) -> T {
    var total = 0.0
    for e in entries { total += e.1 }
    var x = rng.next() * total
    for e in entries {
        x -= e.1
        if x < 0 { return e.0 }
    }
    return entries[entries.count - 1].0
}

extension Array {
    /// A STABLE sort — JS's `Array.prototype.sort` has been stable since ES2019
    /// and the generator relies on it (e.g. "biggest pack first" ties fall back
    /// to route order).
    func stableSorted(by areInIncreasingOrder: (Element, Element) throws -> Bool) rethrows -> [Element] {
        try enumerated()
            .sorted { a, b in
                if try areInIncreasingOrder(a.element, b.element) { return true }
                if try areInIncreasingOrder(b.element, a.element) { return false }
                return a.offset < b.offset
            }
            .map(\.element)
    }
}
