import Foundation

public struct DeckExtreme: Sendable, Equatable { public var min: Int; public var max: Int }

public struct ForkBranchStats: Sendable {
    public var cardsMin: Int
    public var storesMax: Int
    public var storesMin: Int
    public var deals: [Int]
}

public struct ForkInfo: Sendable {
    public var from: String
    public var branches: [Int]
    public var rejoinRow: Int?
    public var sigs: [String]
    public var segIds: [[Int]]
    public var stats: [ForkBranchStats]
    /// "DISTINCT" | "FAKE" | "DOMINATED"
    public var verdict: String
    public var dominated: Int
    public var distinct: Bool
}

public struct PerDealReport: Sendable {
    public var id: Int
    public var row: Int
    public var type: String
    public var piles: Int
    public var deckMin: Int
    public var deckMax: Int
    public var dMin: Double
    public var dMax: Double
    public var band: [Double]
}

public struct StoreReach: Sendable { public var start: Int; public var reaches: Int; public var of: Int }

public struct StageReport: Sendable {
    public var routes = 0
    public var cards: [Int] = []
    public var dealsPerRoute: [Int] = []
    public var storesPerRoute: [Int] = []
    public var stores = 0
    public var starts = 0
    public var widthPerRow: [Int] = []
    public var forksPerRoute: [Int] = []
    public var crossLinks = 0
    public var pairLinks: [Int] = []
    public var storeReach: [StoreReach] = []
    public var bosses: [(id: Int, piles: Int)] = []
    public var forks: [ForkInfo] = []
    public var perDeal: [PerDealReport] = []
}

public struct StageValidation: Sendable {
    public var ok: Bool
    public var errors: [String]
    public var warnings: [String]
    public var report: StageReport
}

extension RunMap {

    /// Route enumeration: every row0→boss path (arrays of node ids).
    public func enumerateRoutes(_ ph: PhaseMap, cap: Int? = nil) -> [[Int]] {
        let cap = cap ?? config.maxRoutes
        var routes: [[Int]] = []
        var path: [Int] = []
        func walk(_ id: Int) {
            if routes.count >= cap { return }
            guard let n = ph.byId[id] else { return }
            path.append(id)
            if n.next.isEmpty { routes.append(path) }
            else { for t in n.next { walk(t) } }
            path.removeLast()
        }
        for id in ph.row0 { walk(id) }
        return routes
    }

    /// Deck extremes: the MIN and MAX possible deck size ARRIVING at each node
    /// (lightest vs heaviest route from the stage entry). DP over rows.
    public func deckExtremes(_ ph: PhaseMap, entryDeck: Int) -> [Int: DeckExtreme] {
        var ext: [Int: DeckExtreme] = [:]
        for id in ph.row0 { ext[id] = DeckExtreme(min: entryDeck, max: entryDeck) }
        // Stable sort by row (nodes are already in row-major id order).
        let sorted = ph.nodes.sorted { ($0.row, $0.id) < ($1.row, $1.id) }
        for n in sorted {
            guard let e = ext[n.id] else { continue }
            let oMin = e.min + n.addOf, oMax = e.max + n.addOf
            for id in n.next {
                if var t = ext[id] {
                    t.min = Swift.min(t.min, oMin); t.max = Swift.max(t.max, oMax)
                    ext[id] = t
                } else {
                    ext[id] = DeckExtreme(min: oMin, max: oMax)
                }
            }
        }
        return ext
    }

    /// Fork analysis (NO-FAKE-FORKS + NO-DOMINATED-ROUTES). Report/warning only —
    /// the randomness + vetoes replaced the old hard gates.
    public func analyzeForks(_ ph: PhaseMap) -> [ForkInfo] {
        var reach: [Int: Set<Int>] = [:]
        let nodesDesc = ph.nodes.sorted { ($0.row, -$0.id) > ($1.row, -$1.id) }
        for n in nodesDesc {
            var s: Set<Int> = [n.id]
            for t in n.next { if let r = reach[t] { s.formUnion(r) } }
            reach[n.id] = s
        }
        func nodeSig(_ id: Int) -> String {
            guard let n = ph.byId[id] else { return "" }
            return n.type
                + (n.addOf != 0 ? "+\(n.addOf)" : "")
                + (n.piles.map { $0 != 0 ? "(\($0)p)" : "" } ?? "")
        }
        func branchStats(_ c: Int, rejoinRow: Int) -> (ids: [Int], sig: String, stats: ForkBranchStats) {
            func inSeg(_ id: Int) -> Bool { (ph.byId[id]?.row ?? 0) < rejoinRow }
            // Inclusive for the card/store DPs: a store sitting exactly ON the
            // rejoin node still separates the branches.
            func inStat(_ id: Int) -> Bool { (ph.byId[id]?.row ?? 0) <= rejoinRow }
            var mMin: [Int: Int] = [:], mStoreMax: [Int: Int] = [:], mStoreMin: [Int: Int] = [:]
            func cardsMin(_ id: Int) -> Int {
                if let v = mMin[id] { return v }
                let n = ph.byId[id]!
                let nx = n.next.filter(inStat)
                let v = n.addOf + (nx.isEmpty ? 0 : nx.map(cardsMin).min()!)
                mMin[id] = v; return v
            }
            func storesMax(_ id: Int) -> Int {
                if let v = mStoreMax[id] { return v }
                let n = ph.byId[id]!
                let nx = n.next.filter(inStat)
                let v = (n.type == "store" ? 1 : 0) + (nx.isEmpty ? 0 : nx.map(storesMax).max()!)
                mStoreMax[id] = v; return v
            }
            func storesMin(_ id: Int) -> Int {
                if let v = mStoreMin[id] { return v }
                let n = ph.byId[id]!
                let nx = n.next.filter(inStat)
                let v = (n.type == "store" ? 1 : 0) + (nx.isEmpty ? 0 : nx.map(storesMin).min()!)
                mStoreMin[id] = v; return v
            }
            let ids = Array((reach[c] ?? []).filter(inSeg))
            let deals = ids.compactMap { ph.byId[$0] }
                .filter { $0.type == "deal" || $0.type == "boss" }
                .map { $0.piles ?? 0 }.sorted()
            let sig = ids.map(nodeSig).sorted().joined(separator: " ")
            return (ids, sig.isEmpty ? "(empty)" : sig,
                    ForkBranchStats(cardsMin: cardsMin(c), storesMax: storesMax(c),
                                    storesMin: storesMin(c), deals: deals))
        }
        var forks: [ForkInfo] = []
        var parents: [(id: String, next: [Int])] = [("start", ph.row0)]
        parents += ph.nodes.map { (String($0.id), $0.next) }
        for p in parents where p.next.count >= 2 {
            for a in 0..<p.next.count {
                for b in (a + 1)..<p.next.count {
                    let c1 = p.next[a], c2 = p.next[b]
                    let common = (reach[c1] ?? []).filter { reach[c2]?.contains($0) ?? false }
                    let rejoinRow = common.isEmpty ? Int.max
                        : common.compactMap { ph.byId[$0]?.row }.min()!
                    let sA = branchStats(c1, rejoinRow: rejoinRow)
                    let sB = branchStats(c2, rejoinRow: rejoinRow)
                    var verdict = "DISTINCT", dominated = -1
                    if sA.sig == sB.sig { verdict = "FAKE" }
                    else if sA.stats.deals.count == sB.stats.deals.count && !sA.stats.deals.isEmpty {
                        func harder(_ x: ForkBranchStats, _ y: ForkBranchStats) -> Bool {
                            x.deals.enumerated().allSatisfy { $1 <= y.deals[$0] }
                            && x.deals.enumerated().contains { $1 < y.deals[$0] }
                        }
                        func noEdge(_ x: ForkBranchStats, _ y: ForkBranchStats) -> Bool {
                            x.cardsMin >= y.cardsMin && x.storesMax <= y.storesMax && x.storesMin <= y.storesMin
                        }
                        if harder(sA.stats, sB.stats) && noEdge(sA.stats, sB.stats) { verdict = "DOMINATED"; dominated = 0 }
                        else if harder(sB.stats, sA.stats) && noEdge(sB.stats, sA.stats) { verdict = "DOMINATED"; dominated = 1 }
                    }
                    forks.append(ForkInfo(
                        from: p.id, branches: [c1, c2],
                        rejoinRow: rejoinRow == Int.max ? nil : rejoinRow,
                        sigs: [sA.sig, sB.sig], segIds: [sA.ids, sB.ids],
                        stats: [sA.stats, sB.stats],
                        verdict: verdict, dominated: dominated, distinct: verdict == "DISTINCT"))
                }
            }
        }
        return forks
    }

    public struct ValidateOptions {
        public var phaseIndex: Int?
        public var bandHiExtra: Double = 0
        /// `opts.firstDeal !== false` gates the stage-0 row-0 firstDealBand.
        public var firstDeal = true
        public init(phaseIndex: Int? = nil, bandHiExtra: Double = 0, firstDeal: Bool = true) {
            self.phaseIndex = phaseIndex; self.bandHiExtra = bandHiExtra; self.firstDeal = firstDeal
        }
    }

    /// Enumerate ALL routes and check the full spec — card totals, deal counts,
    /// store adjacency, and difficulty bands at the min/max deck of every deal.
    /// Applies to GENERATED and AUTHORED stages alike.
    public func validateStage(_ ph: PhaseMap, entryDeck: Int, opts: ValidateOptions = ValidateOptions()) -> StageValidation {
        let C = config
        let p = opts.phaseIndex ?? ph.phaseIndex
        var errors: [String] = [], warnings: [String] = []
        let bandHiX = opts.bandHiExtra
        if bandHiX > 0 {
            warnings.append("boss band top stretched +\(fixed(bandHiX, 2)) (no strict-band solution for this entry deck)")
        }
        let routes = enumerateRoutes(ph, cap: C.maxRoutes)
        if routes.isEmpty { errors.append("no route reaches the boss") }
        var cardMin = Int.max, cardMax = Int.min, dealRMin = Int.max, dealRMax = Int.min, storeAdj = 0
        var storesMin = Int.max, storesMax = Int.min, storeGapViol = 0, badEnd = 0
        for route in routes {
            var cards = 0, deals = 0, stores = 0
            var prevStore = false, dealSinceStore = true
            for id in route {
                guard let n = ph.byId[id] else { continue }
                cards += n.addOf
                if n.type == "deal" { deals += 1 }
                if n.type == "deal" || n.type == "boss" { dealSinceStore = true }
                let isStore = n.type == "store"
                if isStore {
                    stores += 1
                    if prevStore { storeAdj += 1 }
                    if !dealSinceStore { storeGapViol += 1 }   // RULE 2: a deal must sit between stores
                    dealSinceStore = false
                }
                prevStore = isStore
            }
            if ph.byId[route[route.count - 1]]?.type != "boss" { badEnd += 1 }
            cardMin = Swift.min(cardMin, cards); cardMax = Swift.max(cardMax, cards)
            dealRMin = Swift.min(dealRMin, deals); dealRMax = Swift.max(dealRMax, deals)
            storesMin = Swift.min(storesMin, stores); storesMax = Swift.max(storesMax, stores)
        }
        if storeGapViol > 0 { errors.append("\(storeGapViol) route(s) hit two stores with NO deal between them") }
        if badEnd > 0 { errors.append("\(badEnd) route(s) do not end at a boss") }

        // DECISION DENSITY (report only).
        var forkMin = Int.max, forkMax = Int.min
        for route in routes {
            var f = 0
            for id in route where (ph.byId[id]?.next.count ?? 0) >= 2 { f += 1 }
            forkMin = Swift.min(forkMin, f); forkMax = Swift.max(forkMax, f)
        }
        if forkMin < C.minForksPerRoute {
            warnings.append("a route meets only \(forkMin) fork(s) (soft floor \(C.minForksPerRoute) — consider more paths)")
        }
        // Lane cross-links: report only.
        var crossLinks = 0
        let nLanes = C.lanes
        var pairLinks = [Int](repeating: 0, count: Swift.max(0, nLanes - 1))
        for nd in ph.nodes {
            for t in nd.next {
                guard let tn = ph.byId[t] else { continue }
                let a = nd.lane ?? 1, b = tn.lane ?? 1
                if a == b { continue }
                crossLinks += 1
                if tn.row < ph.bossRow && Swift.min(a, b) < pairLinks.count { pairLinks[Swift.min(a, b)] += 1 }
            }
        }
        // STORE ACCESS: no start may be locked out of ALL stores.
        var reachV: [Int: Set<Int>] = [:]
        for nd in ph.nodes.sorted(by: { ($0.row, -$0.id) > ($1.row, -$1.id) }) {
            var st: Set<Int> = [nd.id]
            for t in nd.next { if let r = reachV[t] { st.formUnion(r) } }
            reachV[nd.id] = st
        }
        let storeIds = ph.nodes.filter { $0.type == "store" }.map(\.id)
        let storeReach = ph.row0.map { s0 in
            StoreReach(start: s0, reaches: storeIds.filter { reachV[s0]?.contains($0) ?? false }.count, of: storeIds.count)
        }
        for sr in storeReach where !storeIds.isEmpty && sr.reaches < 1 {
            errors.append("start \(sr.start) cannot reach any store (store-locked)")
        }
        if cardMin < C.minRouteCards { errors.append("a route collects only \(cardMin) cards (< \(C.minRouteCards))") }
        if cardMin > C.maxLightRouteCards {
            errors.append("the lightest route collects \(cardMin) cards (> \(C.maxLightRouteCards)) — no restrained route exists")
        }
        if dealRMin < 3 { errors.append("a route passes only \(dealRMin) regular deals (< 3)") }
        if dealRMax > C.dealsPerRouteMax { errors.append("a route passes \(dealRMax) regular deals (> \(C.dealsPerRouteMax))") }
        if storeAdj > 0 { errors.append("\(storeAdj) route(s) pass two stores in a row") }
        let storeCount = ph.nodes.filter { $0.type == "store" }.count
        if storeCount < C.stores[0] || storeCount > C.stores[1] {
            errors.append("stage has \(storeCount) store(s) (spec: \(C.stores[0])-\(C.stores[1]))")
        }
        // GUARANTEED PRE-BOSS SHOP.
        let bossRowV = ph.nodes.reduce(0) { $1.type == "boss" ? $1.row : $0 }
        if !ph.nodes.contains(where: { $0.type == "store" && $0.row >= bossRowV - C.preBossStoreRows }) {
            errors.append("no store in the final \(C.preBossStoreRows) rows before the boss")
        }
        var widthPerRow = [Int](repeating: 0, count: ph.rows)
        for n in ph.nodes where n.row < widthPerRow.count { widthPerRow[n.row] += 1 }
        if (widthPerRow.first ?? 0) < 2 {
            errors.append("row 0 has \(widthPerRow.first ?? 0) starting node(s) (need 2+)")
        }
        // EXACTLY ONE boss, on the top row.
        let bossNodes = ph.nodes.filter { $0.type == "boss" }
        if bossNodes.count != 1 { errors.append("stage has \(bossNodes.count) boss nodes (spec: exactly 1)") }
        // PLANARITY (hard): no two edges in a transition may cross.
        var crossings = 0
        if ph.bossRow > 0 {
            for r in 0..<ph.bossRow {
                var es: [(Int, Int)] = []
                for n in ph.nodes where n.row == r {
                    for t in n.next {
                        guard let tn = ph.byId[t], tn.row == r + 1 else { continue }
                        es.append((n.lane ?? 1, tn.lane ?? 1))
                    }
                }
                for i in 0..<es.count {
                    for j in (i + 1)..<es.count {
                        if (es[i].0 < es[j].0 && es[i].1 > es[j].1) || (es[j].0 < es[i].0 && es[j].1 > es[i].1) { crossings += 1 }
                    }
                }
            }
        }
        if crossings > 0 { errors.append("\(crossings) edge crossing(s) (map is not planar)") }
        // MERGES RE-SPLIT (soft).
        var inDeg: [Int: Int] = [:]
        for n in ph.nodes { for t in n.next { inDeg[t, default: 0] += 1 } }
        var mergeNoSplit = 0
        for n in ph.nodes where (inDeg[n.id] ?? 0) >= 2 && n.type != "boss" && n.next.count < 2 && n.row < ph.bossRow - 1 {
            mergeNoSplit += 1
        }
        if mergeNoSplit > 0 { warnings.append("\(mergeNoSplit) merge node(s) don't re-split") }
        // LIGHT fork warning.
        let forks = analyzeForks(ph)
        let fakes = forks.filter { $0.verdict == "FAKE" }
        if !fakes.isEmpty {
            warnings.append("\(fakes.count) sibling fork(s) identical until rejoin ("
                + fakes.prefix(3).map { $0.branches.map(String.init).joined(separator: "/") }.joined(separator: ", ") + ")")
        }
        // Difficulty at BOTH deck extremes of every deal + the boss.
        let ext = deckExtremes(ph, entryDeck: entryDeck)
        var perDeal: [PerDealReport] = []
        let dealNodes = ph.nodes.filter { $0.type == "deal" || $0.type == "boss" }
            .sorted { ($0.row, $0.id) < ($1.row, $1.id) }
        var prevRowMid = -Double.infinity, prevRow = -1
        var bossMid: Double? = nil, maxRegMid = -Double.infinity
        for n in dealNodes {
            let e = ext[n.id] ?? DeckExtreme(min: entryDeck, max: entryDeck)
            let pBands = bandsFor(p)
            let band: [Double] = n.type == "boss"
                ? [pBands.boss[0], pBands.boss[1] + bandHiX]
                : (p == 0 && n.row == 0 && opts.firstDeal ? difficulty.firstDealBand : pBands.stage)
            let piles = Double(n.piles ?? 1)
            let dMin = (Double(e.min) - piles) / piles
            let dMax = (Double(e.max) - piles) / piles
            let mid = ((Double(e.min) + Double(e.max)) / 2 - piles) / piles
            let label = "\(n.type == "boss" ? "boss" : "deal")#\(n.id) (row \(n.row), \(n.piles ?? 0) piles)"
            if dMin < band[0] - 1e-6 { errors.append("\(label) too easy on the light route: \(fixed(dMin, 2)) < \(jsNum(band[0]))") }
            if dMax > band[1] + 1e-6 { errors.append("\(label) too hard on the heavy route: \(fixed(dMax, 2)) > \(jsNum(band[1]))") }
            if n.type == "boss" {
                bossMid = bossMid.map { Swift.min($0, mid) } ?? mid
            } else {
                if n.row > prevRow && mid < prevRowMid - 1e-6 {
                    warnings.append("difficulty dips at \(label) (\(fixed(mid, 2)) after \(fixed(prevRowMid, 2)))")
                }
                if n.row > prevRow { prevRowMid = mid; prevRow = n.row } else { prevRowMid = Swift.max(prevRowMid, mid) }
                maxRegMid = Swift.max(maxRegMid, mid)
            }
            perDeal.append(PerDealReport(id: n.id, row: n.row, type: n.type, piles: n.piles ?? 0,
                                         deckMin: e.min, deckMax: e.max,
                                         dMin: round3(dMin), dMax: round3(dMax), band: band))
        }
        if let bm = bossMid, bm < maxRegMid - 1e-6 {
            warnings.append("the boss (\(fixed(bm, 2))) is not the stage's hardest deal (a deal reaches \(fixed(maxRegMid, 2))) — soft")
        }
        var report = StageReport()
        report.routes = routes.count
        report.cards = [cardMin, cardMax]
        report.dealsPerRoute = [dealRMin, dealRMax]
        report.storesPerRoute = [storesMin, storesMax]
        report.stores = storeCount
        report.starts = ph.row0.count
        report.widthPerRow = widthPerRow
        report.forksPerRoute = [forkMin, forkMax]
        report.crossLinks = crossLinks
        report.pairLinks = pairLinks
        report.storeReach = storeReach
        report.bosses = bossNodes.map { (id: $0.id, piles: $0.piles ?? 0) }
        report.forks = forks
        report.perDeal = perDeal
        return StageValidation(ok: errors.isEmpty, errors: errors, warnings: warnings, report: report)
    }

    /// Collapse an error string to a short bucket so the retry loop can report
    /// WHICH constraint blocks convergence.
    static func failCategory(_ err: String?) -> String {
        guard let err else { return "no-candidate" }
        if err.contains("cards (<") { return "cards<11" }
        if err.contains("no restrained") { return "cards>15" }
        if err.contains("regular deals (<") { return "deals<3" }
        if err.contains("regular deals (>") { return "deals>5" }
        if err.contains("too easy") { return "band-too-easy" }
        if err.contains("too hard") { return "band-too-hard" }
        if err.contains("hardest deal") { return "boss-not-hardest" }
        if err.contains("store") { return "store-rule" }
        if err.contains("planar") { return "planarity" }
        if err.contains("boss nodes") { return "boss-count" }
        return "other"
    }
}

// MARK: - JS number formatting for the message strings

/// `n.toFixed(d)`.
func fixed(_ v: Double, _ d: Int) -> String { String(format: "%.\(d)f", v) }
/// `+n.toFixed(3)` — a number rounded to 3 dp, still a number.
func round3(_ v: Double) -> Double { (v * 1000).rounded() / 1000 }
/// How JS interpolates a number into a string (no trailing ".0").
func jsNum(_ v: Double) -> String {
    v == v.rounded() && abs(v) < 1e15 ? String(Int64(v)) : String(v)
}
