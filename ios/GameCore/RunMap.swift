import Foundation

/// RunMap — the branching map a run travels. A run climbs THREE phase-maps in
/// order (♦ → ♣ → ♠); each phase is a generated layered DAG read bottom→top,
/// ending in a boss.
///
/// This module is PURE DATA + generation. CampaignState owns the live position
/// and the accumulated deck.
///
/// SEED COMPATIBILITY is the hard contract here: same seed + deck + tier must
/// produce the same map on web and iOS, so every `rng()` call below happens in
/// the same order, the same number of times, with the same arithmetic.
public final class RunMap {
    public var config = MapConfig()
    let data: GameData
    var difficulty: DifficultyData { data.difficulty }

    /// Pinky's HOME node id — far above every phase namespace.
    public static let homeNodeId = 900_000
    /// FIXED POST-BOSS JOKER NODES (JOKER3): ids above the phase namespace and
    /// clear of HOME, deterministic per stage so saves always agree.
    public static let jokerNodeBase = 800_000
    /// Id namespace stride per phase.
    static let namespaceStride = 1000

    /// The ACTIVE difficulty tier — set by the campaign before any generation.
    private var activeTier = "regular"
    /// Generation-failure histogram (`__genFails`), for diagnostics.
    public private(set) var genFails: [Int: Int] = [:]

    public init(data: GameData = .shared) { self.data = data }

    public static let shared = RunMap()

    public func setDifficultyTier(_ id: String) {
        activeTier = DifficultyData.tierIds.contains(id) ? id : "regular"
    }
    public func getDifficultyTier() -> String { activeTier }

    /// Per-stage bands, extended UPWARD for endless stages.
    public func bandsFor(_ phaseIndex: Int) -> (stage: [Double], boss: [Double]) {
        let T = difficulty.tier(activeTier)
        let last = T.stageBands.count - 1
        if phaseIndex <= last { return (T.stageBands[phaseIndex], T.bossBands[phaseIndex]) }
        let lift = difficulty.endlessBandStep * Double(phaseIndex - last)
        let s = T.stageBands[last], b = T.bossBands[last]
        return ([s[0] + lift, s[1] + lift], [b[0] + lift, b[1] + lift])
    }

    /// A stage's suit: the authored ♦/♣/♠ schedule, then "★" for endless stages.
    public func suitFor(_ phaseIndex: Int) -> String {
        phaseIndex < config.phaseSuits.count ? config.phaseSuits[phaseIndex] : "★"
    }

    // MARK: - Subset deals

    /// The subset-deal knobs, re-exported from difficulty.js for the UI/tests.
    public var subset: SubsetConfig { difficulty.subset }

    /// The player-facing 1..3 difficulty score for a deal, RELATIVE TO ITS STAGE.
    /// Each stage's band is split into three equal tiers and the node's own
    /// danger is bucketed into them, so the score answers "how hard is this deal
    /// among the choices THIS stage offers".
    public func difficultyScore(targetD: Double, phaseIndex: Int?, isBoss: Bool) -> Int {
        guard targetD > 0 else { return 2 }
        guard let phaseIndex else { return 2 }   // no stage context → neutral
        let b = isBoss ? bandsFor(phaseIndex).boss : bandsFor(phaseIndex).stage
        let lo = b[0], hi = b[1], span = hi - lo
        guard span > 0 else { return 2 }
        let t1 = lo + span / 3, t2 = lo + (2 * span) / 3
        return targetD < t1 ? 1 : (targetD < t2 ? 2 : 3)
    }

    /// The two stage-relative tier edges for a phase's band.
    public func difficultyTiers(phaseIndex: Int, isBoss: Bool) -> (band: [Double], t1: Double, t2: Double) {
        let b = isBoss ? bandsFor(phaseIndex).boss : bandsFor(phaseIndex).stage
        let lo = b[0], hi = b[1], span = hi - lo
        return ([lo, hi], lo + span / 3, lo + (2 * span) / 3)
    }

    /// Solve the pile count for a rolled survive count at a target danger D:
    /// `piles = nearest(S / D)`, clamped to [minP, maxP].
    public func solveSubsetPiles(surviveCount: Int, targetD: Double, minP: Int? = nil, maxP: Int? = nil) -> Int {
        let lo = minP ?? config.minPiles, hi = maxP ?? config.maxPiles
        let raw = targetD > 0 ? Int((Double(surviveCount) / targetD).rounded()) : lo
        return max(lo, min(hi, raw == 0 ? lo : raw))
    }

    @discardableResult
    private func genFail(_ tag: Int) -> PhaseMap? {
        genFails[tag, default: 0] += 1
        return nil
    }

    // MARK: - Node type roll

    /// genV ≥ 3 (MYST3) adds MYSTERY as a first-class entry; genV < 3 uses the
    /// legacy three-way table ONLY. Both draw exactly one `rng()` call, so a
    /// v1/v2 map is bit-identical to the pre-MYST3 generator.
    func rollType(_ rng: RNG, genV: Int) -> String {
        var table = config.typeWeights
        if genV >= 3 { table.append(("mystery", config.mysteryTypeWeight)) }
        return weightedPick(rng, table)
    }

    // MARK: - Structure

    struct Structure {
        var R: Int
        var bossRow: Int
        var cells: [(row: Int, lane: Int)]
        var edges: [(r: Int, from: Int, to: Int)]
        var bossLane: Int
    }

    /// Draw `paths` random monotone lane-walks bottom→top; their union is the
    /// graph. PLANAR-BY-CONSTRUCTION: start lanes are sorted, every path
    /// converges on the ONE boss lane, and each step forbids any lane that would
    /// cross an already-committed edge.
    func drawStructure(_ rng: RNG, phaseIndex: Int) -> Structure? {
        let C = config
        let L = C.lanes
        let R = randInt(rng, C.rows)
        let bossRow = R - 1
        // EXACTLY ONE boss per stage: all routes converge.
        let bossLane = pickOne(rng, [0, 1, 2])
        let P = randInt(rng, C.paths)
        for _ in 0..<C.structAttempts {
            var trans: [[(Int, Int)]] = Array(repeating: [], count: max(0, bossRow))
            var startLanes: [Int] = []
            for _ in 0..<P { startLanes.append(pickOne(rng, [0, 1, 2])) }
            startLanes.sort()
            var paths: [[Int]] = []
            var bad = false
            var i = 0
            while i < P && !bad {
                var lane = [Int](repeating: 0, count: R)
                lane[0] = startLanes[i]
                var r = 1
                while r <= bossRow {
                    let prev = lane[r - 1]
                    let remain = bossRow - r
                    var cands: [Int] = []
                    for d in -1...1 {
                        let nl = prev + d
                        if nl < 0 || nl >= L { continue }
                        if abs(bossLane - nl) > remain { continue }   // must still reach the boss
                        var crosses = false
                        for e in trans[r - 1] where (prev < e.0 && nl > e.1) || (prev > e.0 && nl < e.1) {
                            crosses = true; break
                        }
                        if crosses { continue }
                        cands.append(nl)
                    }
                    if cands.isEmpty { bad = true; break }
                    let nl = pickOne(rng, cands)
                    lane[r] = nl
                    if !trans[r - 1].contains(where: { $0.0 == prev && $0.1 == nl }) { trans[r - 1].append((prev, nl)) }
                    r += 1
                }
                if bad { break }
                paths.append(lane)
                i += 1
            }
            if bad { continue }
            let starts = Set(paths.map { $0[0] })
            if starts.count < 2 { continue }                          // ≥2 distinct openings
            var cellSet = Set<Int>(), edgeSet = Set<Int>()
            var cells: [(row: Int, lane: Int)] = [], edges: [(r: Int, from: Int, to: Int)] = []
            for path in paths {
                for r in 0...bossRow {
                    let key = r * 16 + path[r]
                    if cellSet.insert(key).inserted { cells.append((r, path[r])) }
                }
                if bossRow > 0 {
                    for r in 0..<bossRow {
                        let key = (r * 16 + path[r]) * 16 + path[r + 1]
                        if edgeSet.insert(key).inserted { edges.append((r, path[r], path[r + 1])) }
                    }
                }
            }
            return Structure(R: R, bossRow: bossRow, cells: cells, edges: edges, bossLane: bossLane)
        }
        return nil
    }

    // MARK: - One build attempt

    public struct GenOptions {
        /// 1-2 replay the exact legacy path; ≥3 makes mystery a first-class node.
        public var genVersion = 1
        /// Stage indices whose boss is followed by ONE forced corridor +1 CARD
        /// node (the campaign locks a Joker onto it).
        public var postBossJokerStages: [Int] = []
        public init(genVersion: Int = 1, postBossJokerStages: [Int] = []) {
            self.genVersion = genVersion; self.postBossJokerStages = postBossJokerStages
        }
    }

    /// Draw structure → roll node types (weighted) with vetoes → place stores to
    /// quota → assign pack sizes + deal piles. Returns a phase map or nil; the
    /// caller re-validates and retries.
    func tryBuildStage(phaseIndex: Int, rng: RNG, entryDeck: Int, relax: Int, opts: GenOptions) -> PhaseMap? {
        let C = config
        let genV = opts.genVersion
        let suit = suitFor(phaseIndex)
        let bandHiExtra = Double(relax) * C.relaxBandStep

        // ── CARD-BUDGET anchor (STRUCTURE-FREE, so infeasible relax rungs fail
        //    in microseconds). Pick the window and derive the LIGHT TARGET and
        //    the HEAVY CAP; the repairs push the roll into that window.
        let bossBand0 = bandsFor(phaseIndex).boss
        let bHiA = bossBand0[1] + bandHiExtra
        var lightTarget = C.minRouteCards
        var heavyCap = Int.max
        var bestScore = -Double.infinity
        var bestSlack = -1
        for p2 in C.minPiles...C.maxPiles {
            let lm = max(Double(C.minRouteCards), ((bossBand0[0] + 1) * Double(p2) - Double(entryDeck) - 1e-9).rounded(.up))
            let hm = ((bHiA + 1) * Double(p2) - Double(entryDeck) + 1e-9).rounded(.down)
            if lm > Double(C.maxLightRouteCards) || hm < lm { continue }
            // Widest window first, but prefer LOW light targets and heavily
            // penalize lm == maxLight windows (brittle; only used when sole option).
            let score = (hm - lm) * 2 - (lm - Double(C.minRouteCards)) - (lm >= Double(C.maxLightRouteCards) ? 6 : 0)
            if score > bestScore {
                bestScore = score; lightTarget = Int(lm); heavyCap = Int(hm); bestSlack = Int(hm - lm)
            }
        }
        if bestSlack < 2 { return genFail(6) }   // no workable window at this relax rung

        guard let st = drawStructure(rng, phaseIndex: phaseIndex) else { return genFail(1) }
        let R = st.R, bossRow = st.bossRow

        // ── nodes, id row-major (row asc, lane asc) ──
        var rowsArr: [[Int]] = Array(repeating: [], count: R)
        for c in st.cells { rowsArr[c.row].append(c.lane) }
        var nid = 0
        var cellId: [Int: Int] = [:]
        var all: [MapNode] = []
        for r in 0..<R {
            rowsArr[r].sort()
            for l in rowsArr[r] {
                let isBoss = r == bossRow
                let n = MapNode(id: nid, row: r, lane: l, x: isBoss ? 0.5 : C.laneX[l])
                cellId[r * 16 + l] = nid
                all.append(n); nid += 1
            }
        }
        var byId: [Int: MapNode] = [:]
        for n in all { byId[n.id] = n }
        for e in st.edges {
            byId[cellId[e.r * 16 + e.from]!]!.next.append(cellId[(e.r + 1) * 16 + e.to]!)
        }
        for n in all { n.next.sort { (byId[$0]!.lane ?? 0) < (byId[$1]!.lane ?? 0) } }

        let bossNodes = all.filter { $0.row == bossRow }
        for n in bossNodes { n.type = "boss"; n.suit = suit }
        let body = all.filter { $0.row < bossRow }
        let firstRowDeal = phaseIndex == 0   // stage 0 opens on the run's first deal(s)

        // ── PER-ROUTE SUM CACHE (output-preserving speed). Every node TYPE/ADD
        //    mutation flows through noteChange, which keeps per-route sums
        //    incrementally. Values, selection order and rng draws are IDENTICAL
        //    to the re-walk this replaces.
        var routesAt: [Int: [Int]]? = nil
        var cardSum: [Int] = [], dealCnt: [Int] = []
        func noteChange(_ n: MapNode, _ fn: () -> Void) {
            guard let ra = routesAt else { fn(); return }
            let a0 = n.addOf, d0 = n.type == "deal" ? 1 : 0
            fn()
            let dA = n.addOf - a0, dD = (n.type == "deal" ? 1 : 0) - d0
            if dA != 0 || dD != 0 {
                for i in ra[n.id] ?? [] { cardSum[i] += dA; dealCnt[i] += dD }
            }
        }

        // ── roll types; stage-0 row-0 forced to deal. A mystery rolls to a bare
        //    type: no add/packCount/suit — the seeded event is its whole content.
        func setType(_ n: MapNode, _ t: String) {
            noteChange(n) {
                n.type = t
                if t == "pack" {
                    n.packCount = weightedPick(rng, C.packWeights)
                    n.add = n.packCount; n.suit = suit; n.mixed = false
                } else if t == "card" {
                    n.type = "pickup"; n.add = 1; n.suit = suit; n.mixed = false; n.packCount = nil
                } else if t == "mystery" {
                    n.add = nil; n.packCount = nil; n.suit = nil; n.mixed = nil
                } else {
                    n.add = nil; n.packCount = nil
                    if t == "deal" { n.suit = suit }
                }
            }
        }
        for n in body {
            if firstRowDeal && n.row == 0 { setType(n, "deal"); continue }
            setType(n, rollType(rng, genV: genV))
        }

        // ── VETOES: no uniform row; a parent's children not all one type. Run
        //    BEFORE store placement so a reroll can never re-open a store gap.
        func isStore(_ n: MapNode) -> Bool { n.type == "store" }
        func rowTypeKey(_ n: MapNode) -> String { n.type == "pickup" ? "card" : n.type }
        for _ in 0..<3 {
            // uniform rows (skip stage-0 forced opening row, boss row, 1-node rows)
            var r = firstRowDeal ? 1 : 0
            while r < bossRow {
                defer { r += 1 }
                let row = all.filter { $0.row == r }
                if row.count < 2 { continue }
                if Set(row.map(rowTypeKey)).count > 1 { continue }
                let flip = row.filter { !isStore($0) }   // never reroll a placed store
                if flip.isEmpty { continue }
                let n = pickOne(rng, flip)
                var t = ""
                var guardN = 0
                repeat { t = rollType(rng, genV: genV) }
                while t == row[0].type && rowTypeKey(row[0]) != "card" && { let ok = guardN < 8; guardN += 1; return ok }()
                setType(n, t)
            }
            // sibling children all one type
            for par in all {
                if par.next.count < 2 { continue }
                let kids = par.next.map { byId[$0]! }
                if Set(kids.map(rowTypeKey)).count > 1 { continue }
                let flip = kids.filter { !isStore($0) && $0.type != "boss" }
                if flip.isEmpty { continue }
                let n = pickOne(rng, flip)
                var t = ""
                var guardN = 0
                repeat { t = rollType(rng, genV: genV) }
                while rowTypeKey(n) == t && { let ok = guardN < 8; guardN += 1; return ok }()
                setType(n, t)
            }
        }

        // The STRUCTURE is fixed for the whole attempt — only node TYPES/values
        // change below — so the route list is enumerated ONCE and reused.
        var ROUTES: [[Int]] = []
        do {
            var path: [Int] = []
            func walk(_ id: Int) {
                path.append(id)
                let nx = byId[id]!.next
                if nx.isEmpty { ROUTES.append(path) } else { for t in nx { walk(t) } }
                path.removeLast()
            }
            for l in rowsArr[0] { walk(cellId[l]!) }
        }
        var ra: [Int: [Int]] = [:]
        for n in all { ra[n.id] = [] }
        cardSum = [Int](repeating: 0, count: ROUTES.count)
        dealCnt = [Int](repeating: 0, count: ROUTES.count)
        for (i, rt) in ROUTES.enumerated() {
            var cs = 0, dc = 0
            for id in rt {
                ra[id]!.append(i)
                cs += byId[id]!.addOf
                dc += byId[id]!.type == "deal" ? 1 : 0
            }
            cardSum[i] = cs; dealCnt[i] = dc
        }
        routesAt = ra

        // ── DEAL-COUNT repair. Cap the repair target at 4 (not the hard max 5):
        //    a 5-deal route with a store stop leaves too few card slots.
        let dealCap = min(4, C.dealsPerRouteMax)
        for _ in 0..<60 {
            var over: [[Int]] = [], under: [[Int]] = []
            for i in 0..<ROUTES.count {
                if dealCnt[i] > dealCap { over.append(ROUTES[i]) }
                else if dealCnt[i] < 3 { under.append(ROUTES[i]) }
            }
            if over.isEmpty && under.isEmpty { break }
            if !over.isEmpty {
                let rt = pickOne(rng, over)
                let cand = rt.filter { byId[$0]!.type == "deal" && !(firstRowDeal && byId[$0]!.row == 0) }
                if !cand.isEmpty { setType(byId[pickOne(rng, cand)]!, "pack") } else { break }
            } else {
                let rt = pickOne(rng, under)
                let cand = rt.filter { let n = byId[$0]!; return n.type == "pack" || n.type == "pickup" }
                if !cand.isEmpty { setType(byId[pickOne(rng, cand)]!, "deal") } else { break }
            }
        }

        // ── place STORES to quota over eligible nodes.
        let desiredStores = randInt(rng, C.stores)
        func edgeAdjToStore(_ n: MapNode) -> Bool {
            all.contains { m in isStore(m) && (n.next.contains(m.id) || m.next.contains(n.id)) }
        }
        func rowHasStore(_ row: Int) -> Bool { all.contains { isStore($0) && $0.row == row } }
        /// Is there a DEAL-FREE directed path srcId → targetId? (deals fill the
        /// gap so they block; an intervening store blocks too.)
        func dealFreeReaches(_ srcId: Int, _ targetId: Int) -> Bool {
            var seen = Set<Int>()
            var stack = byId[srcId]!.next
            while let id = stack.popLast() {
                if seen.contains(id) { continue }
                seen.insert(id)
                if id == targetId { return true }
                let nd = byId[id]!
                if nd.type == "store" || nd.type == "deal" || nd.type == "boss" { continue }
                stack.append(contentsOf: nd.next)
            }
            return false
        }
        func gapOK(_ c: MapNode) -> Bool {
            all.filter(isStore).allSatisfy { s in !dealFreeReaches(c.id, s.id) && !dealFreeReaches(s.id, c.id) }
        }
        func storeCands() -> [MapNode] {
            body.filter { n in
                !isStore(n) && n.type != "boss" && n.type != "deal"
                && n.type != "mystery"   // genV ≥ 3: its event may BE a store visit
                && !(firstRowDeal && n.row == 0)
                && !edgeAdjToStore(n) && !rowHasStore(n.row) && gapOK(n)
            }
        }
        func makeStore(_ n: MapNode) {
            noteChange(n) { n.add = nil; n.packCount = nil; n.suit = nil; n.type = "store" }
        }
        var placed = 0
        let lateRowMin = bossRow - C.preBossStoreRows
        func hasLateStore() -> Bool { all.contains { isStore($0) && $0.row >= lateRowMin } }
        while placed < desiredStores {
            var cands = storeCands()
            if cands.isEmpty { break }
            // The FIRST store goes low + central so every start can reach it; the
            // SECOND is forced into the pre-boss region if none is there yet.
            if placed == 0 {
                let minRow = cands.map(\.row).min()!
                cands = cands.filter { $0.row <= minRow + 1 }
            } else if !hasLateStore() {
                let late = cands.filter { $0.row >= lateRowMin }
                if late.isEmpty { break }   // no legal pre-boss slot → this attempt fails below
                cands = late
            }
            makeStore(pickOne(rng, cands))
            placed += 1
        }
        if placed < C.stores[0] { return genFail(2) }
        if !hasLateStore() { return genFail(7) }   // pre-boss shop guarantee unmet

        // ── The two tail repairs ALTERNATE until both ends of the window hold.
        func raiseNode(_ n: MapNode) {
            noteChange(n) {
                let nv = n.addOf + 1
                n.type = "pack"; n.packCount = nv; n.add = nv; n.suit = suit; n.mixed = false
            }
        }
        for _ in 0..<6 {
            do {
                var lo0 = Int.max, hi0 = Int.min
                for c0 in cardSum { lo0 = min(lo0, c0); hi0 = max(hi0, c0) }
                if lo0 >= lightTarget && hi0 <= heavyCap { break }   // both ends inside the window
            }
            // BULK PRE-SCALE: nudge the AVERAGE route into the anchor window first.
            do {
                let mid = Swift.min(Double(lightTarget + heavyCap) / 2, Double(C.maxLightRouteCards + 2))
                for _ in 0..<90 {
                    let tot = cardSum.reduce(0, +)
                    let mean = Double(tot) / Double(cardSum.count)
                    if mean >= mid - 0.5 { break }
                    let cand = body.filter { ($0.type == "pack" || $0.type == "pickup") && $0.addOf < C.packMax }
                    if cand.isEmpty { break }
                    raiseNode(pickOne(rng, cand))
                }
            }
            // ── CARD-FLOOR repair.
            for _ in 0..<120 {
                var lo = Int.max, loIdx = -1, hi = Int.min
                for (i, c) in cardSum.enumerated() {
                    if c < lo { lo = c; loIdx = i }
                    if c > hi { hi = c }
                }
                if lo >= lightTarget { break }
                let loRt = ROUTES[loIdx]
                var raisable = loRt.map { byId[$0]! }.filter { ($0.type == "pack" || $0.type == "pickup") && $0.addOf < C.packMax }
                // prefer raising a node the HEAVIEST routes don't share
                if hi >= heavyCap - 1 && raisable.count > 1 {
                    var heavyIds = Set<Int>()
                    for (i, c) in cardSum.enumerated() where c >= heavyCap - 1 { heavyIds.formUnion(ROUTES[i]) }
                    let safe = raisable.filter { !heavyIds.contains($0.id) }
                    if !safe.isEmpty { raisable = safe }
                }
                if !raisable.isEmpty && (dealCnt[loIdx] <= 3 || rng.next() < 0.55) {
                    raiseNode(pickOne(rng, raisable))
                } else {
                    // free a card slot: convert a (non-opening) deal on this route to a pack
                    let dealCand = loRt.filter { byId[$0]!.type == "deal" && !(firstRowDeal && byId[$0]!.row == 0) }
                    if !dealCand.isEmpty && dealCnt[loIdx] > 3 {
                        setType(byId[pickOne(rng, dealCand)]!, "pack")
                    } else if !raisable.isEmpty {
                        raiseNode(pickOne(rng, raisable))
                    } else { break }
                }
            }
            // final deal-min top-up (a conversion may have dropped a route under 3).
            for _ in 0..<12 {
                var under: [[Int]] = []
                for i in 0..<ROUTES.count where dealCnt[i] < 3 { under.append(ROUTES[i]) }
                if under.isEmpty { break }
                let rt = pickOne(rng, under)
                let cand = rt.filter { id in
                    let n = byId[id]!
                    if n.type != "pack" && n.type != "pickup" { return false }
                    // "no route through this node may exceed the cap"
                    return (routesAt?[id] ?? []).allSatisfy { dealCnt[$0] < C.dealsPerRouteMax }
                }
                if !cand.isEmpty { setType(byId[pickOne(rng, cand)]!, "deal") } else { break }
            }
            // ── HEAVY-ROUTE repair.
            for _ in 0..<120 {
                var hi = Int.min, hiIdx = -1, lo2 = Int.max
                for (i, cds) in cardSum.enumerated() {
                    if cds > hi { hi = cds; hiIdx = i }
                    if cds < lo2 { lo2 = cds }
                }
                if hi <= heavyCap { break }
                var shrinkable = ROUTES[hiIdx].map { byId[$0]! }.filter { $0.type == "pack" }
                // prefer shrinking a node the LIGHTEST routes don't share
                if lo2 <= lightTarget && shrinkable.count > 1 {
                    var lightIds = Set<Int>()
                    for (i, c) in cardSum.enumerated() where c <= lightTarget { lightIds.formUnion(ROUTES[i]) }
                    let safe = shrinkable.filter { !lightIds.contains($0.id) }
                    if !safe.isEmpty { shrinkable = safe }
                }
                if shrinkable.isEmpty { break }                       // validation will arbitrate
                let n = shrinkable.stableSorted { $0.addOf > $1.addOf }[0]   // biggest pack first
                let nv = n.addOf - 1
                if nv <= 1 { setType(n, "card") }                     // +2 pack → a +1 CARD node
                else { noteChange(n) { n.packCount = nv; n.add = nv } }
            }
        }

        // ── FINAL UNIFORM-ROW veto (re-asserted after the repairs).
        func kindOf(_ n: MapNode) -> String { n.type == "pickup" ? "card" : n.type }
        @discardableResult
        func safeFlip(_ n: MapNode, _ t: String) -> Bool {
            let saveType = n.type, saveAdd = n.add, savePack = n.packCount
            setType(n, t)
            var ok = true
            for i in 0..<ROUTES.count {
                if cardSum[i] < C.minRouteCards || dealCnt[i] < 3 || dealCnt[i] > C.dealsPerRouteMax { ok = false; break }
            }
            if !ok {
                noteChange(n) { n.type = saveType; n.add = saveAdd; n.packCount = savePack }
            }
            return ok
        }
        var fr = firstRowDeal ? 1 : 0
        while fr < bossRow {
            defer { fr += 1 }
            let row = all.filter { $0.row == fr && $0.type != "store" }
            if row.count < 2 { continue }
            let kinds = Set(all.filter { $0.row == fr }.map(kindOf))
            if kinds.count > 1 { continue }                       // already mixed
            let kind = kindOf(row[0])
            let alt = kind == "pack" ? "card" : (kind == "card" ? "pack" : "pack")
            safeFlip(pickOne(rng, row), alt)
        }
        // genV ≥ 5: the OPENING ROW joins the variety rule with its own guard.
        // Row 0 is all-deals by construction; when it is wide enough (3+
        // doors) ONE non-leftmost door may flip to a MYSTERY — the first
        // decision stops being deal-vs-deal-vs-deal while the row always
        // keeps ≥2 deal openings (and safeFlip re-validates every route
        // guarantee, reverting a flip that would starve one). MYSTERY
        // deliberately, never a pickup/pack: a card add at the root of every
        // route through it shifts the deck extremes the WHOLE stage was
        // budgeted around, and the converge ladder thrashed ~120x when row 0
        // grew cards (measured v6.52); a mystery adds nothing and costs
        // nothing. Old maps (genV < 5) regenerate with the row untouched.
        if genV >= 5, firstRowDeal {
            let row0 = all.filter { $0.row == 0 }
            let deals0 = row0.filter { $0.type == "deal" }
            if row0.count >= 3, deals0.count == row0.count {
                // Leftmost door excluded: the gentle floor opening stays a deal.
                // A door's deal usually counts toward its routes' 3-deal floor,
                // so the direct flip mostly reverts (measured 1-in-19). When it
                // does, PROMOTE one later mystery into a deal first — a
                // mystery↔deal swap moves deal counts without moving a single
                // card, so every budget the stage converged on stays intact —
                // then retry the door.
                var doors = Array(deals0.dropFirst())
                while !doors.isEmpty {
                    let d = pickOne(rng, doors)
                    doors.removeAll { $0 === d }
                    if safeFlip(d, "mystery") { break }
                    var opened = false
                    for m in all where m.type == "mystery" && m.row > 0 && m.row < bossRow {
                        guard safeFlip(m, "deal") else { continue }
                        if safeFlip(d, "mystery") { opened = true; break }
                        _ = safeFlip(m, "mystery")   // promotion alone didn't free the door — undo
                    }
                    if opened { break }
                }
            }
        }

        let bossIds = bossNodes.map(\.id)
        let ph = PhaseMap(phaseIndex: phaseIndex, suit: suit, rows: R, bossRow: bossRow,
                          nodes: all, bossId: bossIds[0], bossIds: bossIds,
                          row0: rowsArr[0].map { cellId[$0]! })

        // ── DEAL PILES: bands hold at both deck extremes; distinct within a row.
        let stageBand = bandsFor(phaseIndex).stage
        let sLo = stageBand[0], sHi = stageBand[1]
        let regHi = sHi
        for restart in 0..<4 {
            let ext = deckExtremes(ph, entryDeck: entryDeck)
            var converted = false
            var dealRowsAsc: [Int] = []
            for r in 0..<bossRow where all.contains(where: { $0.row == r && $0.type == "deal" }) { dealRowsAsc.append(r) }
            var k = 0
            while k < dealRowsAsc.count && !converted {
                defer { k += 1 }
                let r = dealRowsAsc[k]
                let isFirst = firstRowDeal && r == 0
                // genV ≥ 5: the opening row reads its own WIDER band
                // (firstDealBandV5) and each door takes an ASCENDING target
                // across it with DISTINCT pile counts, so the run's first
                // choice is a real spread of difficulty and reward. genV < 5
                // keeps the narrow band, the shared midpoint target and tied
                // pile counts — bit-identical to the maps old saves regenerate.
                let v5First = isFirst && genV >= 5
                let firstBand = v5First ? difficulty.firstDealBandV5 : difficulty.firstDealBand
                let band = isFirst ? firstBand : [sLo, sHi]
                let capHi = isFirst ? firstBand[1] : regHi
                let targetD = isFirst
                    ? (firstBand[0] + firstBand[1]) / 2
                    : sLo + (regHi - sLo) * (Double(k + 1) / Double(dealRowsAsc.count + 1))   // ascending by row
                let group = all.filter { $0.row == r && $0.type == "deal" }
                var used = Set<Int>()
                for (gi, n) in group.enumerated() {
                    // v5 opening: door gi's target steps floor → ceiling across
                    // the row; a lone door sits at the gentle floor. Other rows
                    // (and genV < 5) keep the row-shared target.
                    let nodeTarget = v5First
                        ? (group.count > 1
                            ? firstBand[0] + (firstBand[1] - firstBand[0]) * Double(gi) / Double(group.count - 1)
                            : firstBand[0])
                        : targetD
                    let e = ext[n.id] ?? DeckExtreme(min: entryDeck, max: entryDeck)
                    let pMin = max(Double(C.minPiles),
                                   (Double(e.max) / (band[1] + 1) - 1e-9).rounded(.up),
                                   ((Double(e.min) + Double(e.max)) / 2 / (capHi + 1) - 1e-9).rounded(.up))
                    let pMax = min(Double(C.maxPiles), (Double(e.min) / (band[0] + 1) + 1e-9).rounded(.down))
                    if pMin > pMax {
                        if isFirst { return genFail(3) }              // the openings must stay deals
                        setType(n, "card"); converted = true; break   // no in-band pile count → +1 CARD
                    }
                    let pT = max(Int(pMin), min(Int(pMax), Int((((Double(e.min) + Double(e.max)) / 2) / (nodeTarget + 1)).rounded())))
                    // The genV<5 stage-0 opening deals are band-locked so they
                    // may tie; every other same-row deal (and the v5 opening)
                    // takes a DISTINCT in-band value.
                    var p: Int? = nil
                    var d = 0
                    while d <= C.maxPiles && p == nil {
                        for cand in [pT + d, pT - d] where Double(cand) >= pMin && Double(cand) <= pMax
                            && ((isFirst && genV < 5) || !used.contains(cand)) {
                            p = cand; break
                        }
                        d += 1
                    }
                    if p == nil, v5First {
                        // Distinct impossible on the opening row — accept a
                        // DUPLICATE rather than convert or fail: the openings
                        // must stay deals, tied doors are the lesser evil.
                        var d2 = 0
                        while d2 <= C.maxPiles && p == nil {
                            for cand in [pT + d2, pT - d2] where Double(cand) >= pMin && Double(cand) <= pMax {
                                p = cand; break
                            }
                            d2 += 1
                        }
                        if p == nil { return genFail(3) }
                    }
                    if p == nil {                                    // distinct value impossible on this row
                        // Convert to a +1 CARD — unless that would starve a route
                        // below 3 deals; then accept a DUPLICATE pile value.
                        let starves = (routesAt?[n.id] ?? []).contains { dealCnt[$0] <= 3 }
                        if !starves { setType(n, "card"); converted = true; break }
                        var d2 = 0
                        while d2 <= C.maxPiles && p == nil {
                            for cand in [pT + d2, pT - d2] where Double(cand) >= pMin && Double(cand) <= pMax {
                                p = cand; break
                            }
                            d2 += 1
                        }
                        if p == nil { setType(n, "card"); converted = true; break }
                    }
                    used.insert(p!)
                    n.piles = p!
                    // The node's OWN danger, not the row's shared target: the
                    // reward chip, the deal's 1–3 rating and the subset solve
                    // all derive from targetD, and two same-row deals with
                    // different pile counts are genuinely different deals —
                    // the 4-pile one should pay more than its 6-pile
                    // neighbour. (The row target still steers pT above, so
                    // difficulty still ascends through the stage.)
                    n.targetD = (Double(e.min) + Double(e.max)) / 2 / Double(p!) - 1
                }
            }
            if !converted { break }                                  // all deals piled cleanly
            if restart == 3 { return genFail(4) }                    // conversions didn't settle
        }
        if !assignBossPiles(ph, entryDeck: entryDeck, phaseIndex: phaseIndex, bandHiExtra: bandHiExtra) {
            return genFail(5)
        }
        return ph
    }

    /// Boss pile assignment from CURRENT deck extremes: the SINGLE boss's band
    /// must hold at both the lightest and heaviest arriving deck.
    func assignBossPiles(_ ph: PhaseMap, entryDeck: Int, phaseIndex: Int, bandHiExtra: Double) -> Bool {
        let C = config
        let band = bandsFor(phaseIndex).boss
        let hi = band[1] + bandHiExtra
        let ext = deckExtremes(ph, entryDeck: entryDeck)
        for boss in ph.nodes where boss.type == "boss" {
            let e = ext[boss.id] ?? DeckExtreme(min: entryDeck, max: entryDeck)
            let pMin = max(Double(C.minPiles), (Double(e.max) / (hi + 1) - 1e-9).rounded(.up))
            let pMax = min(Double(C.maxPiles), (Double(e.min) / (band[0] + 1) + 1e-9).rounded(.down))
            if pMin > pMax { return false }
            boss.piles = Int(((pMin + pMax) / 2).rounded())
            boss.targetD = (band[0] + hi) / 2   // intended boss danger (drives the 1-3 score)
        }
        return true
    }

    /// FORCED PACK-CHAIN MERGE. If pack A's ONLY edge leads to pack B and A is
    /// B's ONLY parent (a corridor), the packs MERGE: A's count grows by B's and
    /// B becomes a PASS-THROUGH point, kept in the graph with its edges intact.
    /// Deterministic (no rng), so a resume's regeneration merges identically.
    @discardableResult
    public func mergeForcedPackChains(_ ph: PhaseMap, genV: Int = 1) -> PhaseMap {
        var parents: [Int: [Int]] = [:]
        for n in ph.nodes { for id in n.next { parents[id, default: []].append(n.id) } }
        for a in ph.nodes {
            if a.type != "pack" { continue }
            var cur = a
            while cur.next.count == 1 {
                guard let b = ph.byId[cur.next[0]] else { break }
                if b.type == "pass" { cur = b; continue }   // glide over already-freed links
                if b.type != "pack" || (parents[b.id]?.count ?? 0) != 1 { break }
                let aCount = (a.packCount ?? 0) != 0 ? a.packCount! : 2
                let bCount = (b.packCount ?? 0) != 0 ? b.packCount! : 2
                // genV ≥ 4: a merge may never build a MEGA-PACK. Past packMax
                // the chain simply stops absorbing — B stays its own pack, so
                // the cards spread across nodes instead of piling into one
                // 10-card drop. Gated on genV: an old save's map must
                // regenerate byte-identically.
                if genV >= 4, aCount + bCount > config.packMax { break }
                a.packCount = aCount + bCount
                a.add = a.packCount
                b.type = "pass"
                b.packCount = nil; b.add = nil; b.mixed = nil
                cur = b
            }
        }
        // No node may be EMPTY. A merged-away pack leaves a stop that grants
        // nothing, so at genV ≥ 3 it becomes a MYSTERY — the trail still has a
        // reason to stop there. Done AFTER the merge so the loop above keeps
        // gliding on "pass"; gated on genV so a resumed pre-mystery map still
        // regenerates byte-identically (the save-compat contract).
        //
        // Safe against the validator and the generator: mystery has addOf 0 and
        // is neither deal nor store, so it is transparent to the route sums and
        // the store-gap walk exactly as pass was — and store placement has
        // already run by this point, so the "a mystery may never become a
        // store" rule cannot be violated.
        if genV >= 3 {
            for n in ph.nodes where n.type == "pass" {
                n.type = "mystery"
                // The mystery contract (see `setType`): its event IS its whole
                // content, so it carries no add / packCount / suit / mixed.
                n.add = nil; n.packCount = nil; n.suit = nil; n.mixed = nil
            }
        }
        return ph
    }

    // MARK: - The attempt / relax / seed ladder

    struct AttemptResult {
        var ok: PhaseMap?
        var best: PhaseMap?
        var bestErrs: Int = Int.max
        var lastErrors: [String]?
        var hist: [String: Int] = [:]
    }

    /// One full attempt×relax ladder at ONE seed. Every attempt derives its own
    /// rng from (seed, phase, attempt), so runs at different seeds are fully
    /// independent.
    func stageAttemptLoop(phaseIndex: Int, seed: UInt32, entryDeck: Int, opts: GenOptions) -> AttemptResult {
        let C = config
        var out = AttemptResult()
        for attempt in 0..<(C.attempts * (1 + C.relaxSteps)) {
            let relax = min(C.relaxSteps, attempt / C.attempts)
            let rng = RNG(seed: stageSeed(seed: seed, phaseIndex: phaseIndex, attempt: attempt))
            guard let ph = tryBuildStage(phaseIndex: phaseIndex, rng: rng, entryDeck: entryDeck, relax: relax, opts: opts) else {
                out.hist["build-null", default: 0] += 1
                continue
            }
            mergeForcedPackChains(ph, genV: opts.genVersion)   // corridors collapse BEFORE validation
            let bandX = Double(relax) * C.relaxBandStep
            let v = validateStage(ph, entryDeck: entryDeck,
                                  opts: ValidateOptions(phaseIndex: phaseIndex, bandHiExtra: bandX,
                                                        genVersion: opts.genVersion))
            ph.gen = GenReport(attempt: attempt, relax: relax, entryDeck: entryDeck,
                               warnings: v.warnings, report: v.report)
            if v.ok { out.ok = ph; return out }
            let cat = Self.failCategory(v.errors.first)
            out.hist[cat, default: 0] += 1
            if v.errors.count < out.bestErrs {
                out.best = ph; out.bestErrs = v.errors.count; out.lastErrors = v.errors
            }
        }
        return out
    }

    /// `generateStage` — build → validate → retry; after the attempt cap, RELAX
    /// the boss band top step by step and keep trying. genVersion ≥ 2 adds the
    /// SEED LADDER: retry at up to `seedLadderRungs` DERIVED seeds. Seeds that
    /// converge on rung 0 are bit-identical under every genVersion.
    public func generateStage(phaseIndex: Int, seed: UInt32, entryDeck: Int? = nil, opts: GenOptions = GenOptions()) -> PhaseMap? {
        let C = config
        let entry = entryDeck ?? C.startDeckSize
        let first = stageAttemptLoop(phaseIndex: phaseIndex, seed: seed, entryDeck: entry, opts: opts)
        if let ok = first.ok { return ok }
        var accepted = first
        if opts.genVersion >= 2 {
            for rung in 1...C.seedLadderRungs {
                // Derived-seed hash: nonzero xor for every rung ≥ 1, so no rung
                // ever replays the base seed's attempt sequence.
                let seed2 = ladderSeed(seed: seed, rung: rung)
                let res = stageAttemptLoop(phaseIndex: phaseIndex, seed: seed2, entryDeck: entry, opts: opts)
                if let ok = res.ok { return ok }
                // All rungs failed → accept the best effort across rungs
                // (fewest validation errors; earliest rung wins ties).
                if res.bestErrs < accepted.bestErrs { accepted = res }
            }
        }
        return accepted.best
    }
}
