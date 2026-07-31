import Foundation

extension RunMap {

    /// A stage map: the designated authored definition if one exists, else the
    /// random generator (with the REAL entry deck size for difficulty).
    func buildPhase(phaseIndex: Int, seed: UInt32, entryDeck: Int?, opts: GenOptions) -> PhaseMap? {
        if let def = authored[phaseIndex] {
            let ph = definitionToPhase(def, phaseIndex: phaseIndex)
            mergeForcedPackChains(ph)   // authored maps get the same corridor collapse
            _ = validateStage(ph, entryDeck: entryDeck ?? config.startDeckSize,
                              opts: ValidateOptions(phaseIndex: phaseIndex))
            return ph
        }
        return generateStage(phaseIndex: phaseIndex, seed: seed, entryDeck: entryDeck, opts: opts)
    }

    /// STAGE-CHUNKED RUN GENERATION: `step()` builds the next stage (returns
    /// true while more remain); `finish()` drains any remainder, runs the
    /// post-pass wiring (boss→openings, home, joker corridors) and returns the
    /// map. `generateRun(...) === makeRunStepper(...).finish()`.
    public final class RunStepper {
        private let owner: RunMap
        private let seed: UInt32
        private let entryDecks: [Int?]
        private let opts: GenOptions
        private let postBossJokerStages: [Int]
        private let genV: Int

        private var phases: [PhaseMeta] = []
        private var nodes: [MapNode] = []
        private var byId: [Int: MapNode] = [:]
        private var rowOffset = 0
        private var homeNode: MapNode?
        private var p = 0                 // next stage to build
        private var halted = false        // null entry / failed stage / drained

        /// Authored stages (3); p ≥ base = ENDLESS.
        private var base: Int { owner.config.phaseSuits.count }

        init(owner: RunMap, seed: UInt32, entryDecks: [Int?]?, opts: GenOptions) {
            self.owner = owner
            self.seed = seed
            self.entryDecks = entryDecks ?? [owner.config.startDeckSize]
            self.opts = opts
            self.postBossJokerStages = opts.postBossJokerStages
            self.genV = opts.genVersion
        }

        /// Build ONE stage. Returns true while more stages remain to build.
        @discardableResult
        public func step() -> Bool {
            if halted { return false }
            // Later stages: not yet entered.
            if p >= entryDecks.count || entryDecks[p] == nil { halted = true; return false }
            guard let ph = owner.buildPhase(phaseIndex: p, seed: seed, entryDeck: entryDecks[p], opts: opts) else {
                halted = true; return false   // truly unsatisfiable → stop growing
            }
            let NS = RunMap.namespaceStride
            func remap(_ id: Int) -> Int { p * NS + id }
            for n in ph.nodes {
                n.id = remap(n.id)
                n.next = n.next.map(remap)
                n.phase = p
                n.localRow = n.row
                n.row = rowOffset + n.row                     // GLOBAL row (stacked)
                // MYSTERY mask (genV < 3 ONLY — legacy saves): display-only
                // hiding, deterministic per (runSeed, global id), so extending
                // the map or regenerating on resume hides the SAME nodes.
                if genV < 3 && n.type != "boss" && n.type != "pass" && n.type != "home" {
                    let mr = RNG(seed: mysteryMaskSeed(seed: seed, nodeId: n.id))
                    if mr.next() < owner.config.mysteryChance { n.mystery = true }
                }
                nodes.append(n)
                byId[n.id] = n
            }
            var meta = PhaseMeta(phase: p, suit: ph.suit,
                                 bossId: remap(ph.bossId),
                                 bossIds: ph.bossIds.map(remap),
                                 row0: ph.row0.map(remap),
                                 rowStart: rowOffset, rows: ph.rows,
                                 jokerNodeId: nil)
            rowOffset += ph.rows
            // PINKY'S HOME — one node directly ABOVE the final (♠) boss, the
            // run's true finish line. Endless stages stack ABOVE home.
            if p == base - 1 {
                let home = MapNode(id: RunMap.homeNodeId, row: rowOffset, lane: 1, x: 0.5, type: "home")
                home.localRow = ph.rows
                home.suit = "♥"
                home.phase = p
                homeNode = home
                nodes.append(home); byId[home.id] = home
                byId[meta.bossId]?.next.append(home.id)
                rowOffset += 1
            }
            // FIXED POST-BOSS JOKER: one forced corridor +1 CARD node directly
            // above this stage's boss. Created OUTSIDE the mystery roll so it is
            // ALWAYS visible; the Joker lock happens campaign-side.
            if postBossJokerStages.contains(p) {
                let jn = MapNode(id: RunMap.jokerNodeBase + p, row: rowOffset, lane: 1, x: 0.5, type: "pickup")
                jn.jokerNode = true
                jn.add = 1
                jn.localRow = ph.rows
                jn.suit = "★"
                jn.phase = p
                nodes.append(jn); byId[jn.id] = jn
                byId[meta.bossId]?.next.append(jn.id)
                meta.jokerNodeId = jn.id
                rowOffset += 1
            }
            phases.append(meta)
            p += 1
            return p < entryDecks.count && entryDecks[p] != nil
        }

        /// Drain remaining stages, run the post-pass wiring, return the map.
        public func finish() -> RunMapGraph {
            while step() {}
            // Wire each phase's single boss → all of the next phase's openings.
            // A post-boss Joker corridor takes the boss's place as the stage exit.
            if phases.count > 1 {
                for q in 0..<(phases.count - 1) {
                    let opens = phases[q + 1].row0.compactMap { byId[$0] }
                        .stableSorted { ($0.lane ?? 1) < ($1.lane ?? 1) }
                    if q == base - 1, let home = homeNode {
                        home.next = opens.map(\.id)
                    } else if let jid = phases[q].jokerNodeId {
                        byId[jid]?.next = opens.map(\.id)
                    } else {
                        byId[phases[q].bossId]?.next = opens.map(\.id)
                    }
                }
            }
            if phases.isEmpty {
                // Stage 0 failed to generate (should be unreachable).
                return RunMapGraph(nodes: [], phases: [], row0: [], homeId: nil,
                                   totalRows: 0, runBossId: nil, runBossIds: nil, stagesGenerated: 0)
            }
            return RunMapGraph(
                nodes: nodes, phases: phases, row0: phases[0].row0,
                homeId: homeNode?.id, totalRows: rowOffset,
                runBossId: phases.count >= base ? phases[base - 1].bossId : nil,
                runBossIds: phases.count >= base ? phases[base - 1].bossIds : nil,
                stagesGenerated: phases.count)
        }
    }

    /// entryDecks[p] = the REAL deck size entering stage p. A nil entry means
    /// that stage hasn't been entered yet — it is NOT generated.
    public func makeRunStepper(seed: UInt32, entryDecks: [Int?]?, opts: GenOptions = GenOptions()) -> RunStepper {
        RunStepper(owner: self, seed: seed, entryDecks: entryDecks, opts: opts)
    }

    /// The synchronous whole-run generation — drain the stepper in one call.
    public func generateRun(seed: UInt32, entryDecks: [Int?]? = nil, opts: GenOptions = GenOptions()) -> RunMapGraph {
        makeRunStepper(seed: seed, entryDecks: entryDecks, opts: opts).finish()
    }
}

// MARK: - The authoring seam

/// The hand-editable EXPLICIT MAP SPEC — a node list + a separate edge list.
public struct MapSpec {
    public struct Node {
        public var id: String
        /// "start" | "deal" | "boss" | "store" | "card" | "pack"
        public var type: String
        public var tier: Int
        public var x: Double
        public var piles: Int?
        public var add: Int?
        public var suit: String?
        public var mixed: Bool
        /// `card:"K♦"` pins that exact card; "random" = any draft.
        public var card: String?
        public init(id: String, type: String, tier: Int, x: Double = 0.5, piles: Int? = nil,
                    add: Int? = nil, suit: String? = nil, mixed: Bool = false, card: String? = nil) {
            self.id = id; self.type = type; self.tier = tier; self.x = x
            self.piles = piles; self.add = add; self.suit = suit; self.mixed = mixed; self.card = card
        }
    }
    public var suit: String
    public var nodes: [Node]
    public var edges: [(String, String)]
    public init(suit: String, nodes: [Node], edges: [(String, String)]) {
        self.suit = suit; self.nodes = nodes; self.edges = edges
    }
}

extension RunMap {
    /// AUTHORED override designation. Stages GENERATE by default — this is empty
    /// in the shipping build, exactly like the web's `const AUTHORED = {}`.
    public var authored: [Int: MapSpec] {
        get { _authoredStorage }
        set { _authoredStorage = newValue }
    }

    /// Adapt the explicit node+edge spec into the internal phase shape.
    /// `tier` = vertical row, smallest = bottom; normalized so the lowest real
    /// node renders at row 0. `x` = 0..1 horizontal slot within the tier.
    public func parseMapSpec(_ spec: MapSpec, phaseIndex: Int) -> PhaseMap {
        let suit = spec.suit
        var num: [String: Int] = [:]
        for (i, d) in spec.nodes.enumerated() { num[d.id] = i }
        var out: [String: [String]] = [:]
        for e in spec.edges { out[e.0, default: []].append(e.1) }
        let start = spec.nodes.first { $0.type == "start" }
        let reals = spec.nodes.filter { $0.type != "start" }
        let minTier = reals.map(\.tier).min() ?? 0
        var nodes: [MapNode] = []
        for d in reals {
            let n = MapNode(id: num[d.id]!, row: d.tier - minTier, lane: nil, x: d.x,
                            next: (out[d.id] ?? []).compactMap { num[$0] })
            switch d.type {
            case "deal", "boss": n.type = d.type; n.piles = d.piles; n.suit = suit
            case "store":        n.type = "store"
            case "pack":         n.type = "pack"; n.packCount = d.add; n.suit = suit; n.mixed = d.mixed
            default:             // "card" → single +1 pickup
                n.type = "pickup"; n.suit = suit; n.mixed = d.mixed
                if let c = d.card, c != "random" { n.forceCard = c }
            }
            nodes.append(n)
        }
        let boss = nodes.first { $0.type == "boss" } ?? nodes[nodes.count - 1]
        let bossIds = nodes.filter { $0.type == "boss" }.map(\.id)
        let rows = (nodes.map(\.row).max() ?? 0) + 1
        let row0: [Int] = start.map { s in (out[s.id] ?? []).compactMap { num[$0] } }
            ?? nodes.filter { $0.row == 0 }.map(\.id)
        return PhaseMap(phaseIndex: phaseIndex, suit: suit, rows: rows, bossRow: boss.row,
                        nodes: nodes, bossId: boss.id,
                        bossIds: bossIds.isEmpty ? [boss.id] : bossIds, row0: row0)
    }

    /// Adapt a data definition into the internal phase-map shape.
    public func definitionToPhase(_ def: MapSpec, phaseIndex: Int) -> PhaseMap {
        parseMapSpec(def, phaseIndex: phaseIndex)
    }
}

/// Storage for the (normally empty) authored-stage override.
private var _authoredStorage: [Int: MapSpec] = [:]
