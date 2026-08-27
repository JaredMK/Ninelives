import Foundation

/// One pile — a life.
public final class Pile {
    public let index: Int
    public var cards: [LiveCard] = []
    public var dead = false
    /// Same Heavy (linkHeavy) adds a flat per-pile size bonus that rides this
    /// deal's board pile object.
    public var sizeBonus = 0
    init(index: Int) { self.index = index }
}

/// BoardState — the piles. Pile count is per-run (the campaign supplies it).
public final class BoardState {
    public static let defaultSize = 9

    public let size: Int
    public private(set) var piles: [Pile]
    private let data: GameData

    /// Optional PILLAR hooks (set by the engine after startRun): extra size a
    /// column Pillar grants a pile, and forced anchoring. Board-only
    /// sizing/anchor stays pillar-agnostic; the engine injects context.
    var pillarSize: ((Int) -> Int)?
    var pillarAnchor: ((Int) -> Bool)?

    public init(size: Int = BoardState.defaultSize, data: GameData = .shared) {
        self.size = size
        self.data = data
        self.piles = (0..<size).map { Pile(index: $0) }
    }

    /// SHRINK curse: the card counts against its pile's size. (The Heavy
    /// family's passive weight retired in v6.85 — Heavy is a conditional
    /// LANDING effect now, latched through sizeBonus like Same Heavy.)
    private func cardWeight(_ c: LiveCard) -> Int {
        var w = 1
        for s in c.stickers {
            guard let t = data.stickerTypes.get(s.type) else { continue }
            if t.behavior == "shrink" { w -= t.int("value", 1) }
        }
        return w
    }

    private func sizeOf(_ p: Pile) -> Int {
        // FLATLINE curse: while it's the top card, the pile counts as 1 —
        // covering it restores the true size.
        if let top = p.cards.last,
           top.stickers.contains(where: { data.stickerTypes.get($0.type)?.behavior == "flatline" }) {
            return 1
        }
        let n = p.cards.reduce(0) { $0 + cardWeight($1) } + (pillarSize?(p.index) ?? 0) + p.sizeBonus
        // Shrink can never drag a real pile below 1.
        return p.cards.isEmpty ? n : Swift.max(1, n)
    }

    /// Add a persistent (this-deal) size bonus to a pile — Same Heavy.
    public func addSizeBonus(_ index: Int, _ n: Int) { piles[index].sizeBonus += n }

    public func setPillarSizeHook(_ fn: ((Int) -> Int)?) { pillarSize = fn }
    public func setPillarAnchorHook(_ fn: ((Int) -> Bool)?) { pillarAnchor = fn }
    func forcedAnchor(_ index: Int) -> Bool { pillarAnchor?(index) ?? false }

    /// Weighted pile size (Heavy counts extra). The single source for every
    /// pile-size read — payout factors, Extra Coin, and the count badge.
    public func pileSize(_ index: Int) -> Int { sizeOf(piles[index]) }

    /// Place a starting/next card on a pile.
    public func push(_ index: Int, _ card: LiveCard?) {
        guard let card else { return }
        piles[index].cards.append(card)
    }
    /// Insert a card at the BOTTOM of a pile (under everything), never shown.
    public func pushBottom(_ index: Int, _ card: LiveCard?) {
        guard let card else { return }
        piles[index].cards.insert(card, at: 0)
    }
    /// Remove and return ALL of a pile's cards, leaving it empty but ALIVE.
    @discardableResult
    public func drain(_ index: Int) -> [LiveCard] {
        let c = piles[index].cards
        piles[index].cards = []
        return c
    }
    /// Pull the BOTTOM card (Trapdoor). Never the last one — the pile always
    /// keeps its top.
    public func removeBottom(_ index: Int) -> LiveCard? {
        guard piles[index].cards.count > 1 else { return nil }
        return piles[index].cards.removeFirst()
    }
    /// TUTORIAL arrangement: swap the TOP cards of two piles.
    public func swapTops(_ a: Int, _ b: Int) {
        guard a != b, !piles[a].cards.isEmpty, !piles[b].cards.isEmpty else { return }
        let ca = piles[a].cards.removeLast()
        let cb = piles[b].cards.removeLast()
        piles[a].cards.append(cb)
        piles[b].cards.append(ca)
    }
    public func top(_ index: Int) -> LiveCard? { piles[index].cards.last }
    public func isActive(_ index: Int) -> Bool { !piles[index].dead }
    public func kill(_ index: Int) { piles[index].dead = true }
    /// Bring a dead pile back to life. Keeps its existing cards.
    public func revive(_ index: Int) { piles[index].dead = false }

    /// Shuffle a pile's cards in place with a seeded rng. A COMPOSITION shuffle
    /// only — the order is never surfaced; the new top is whatever lands last.
    public func shufflePile(_ index: Int, _ rng: RNG) {
        var c = piles[index].cards
        var i = c.count - 1
        while i > 0 {
            let j = rng.index(i + 1)
            c.swapAt(i, j)
            i -= 1
        }
        piles[index].cards = c
    }

    /// Move ONE card from the BOTTOM of `from` to the BOTTOM of `to` (Donate).
    /// Composition shift only. Returns true if a card moved.
    @discardableResult
    public func moveBottomCard(_ from: Int, _ to: Int) -> Bool {
        guard !piles[from].cards.isEmpty, from != to else { return false }
        let c = piles[from].cards.removeFirst()
        piles[to].cards.insert(c, at: 0)
        return true
    }

    public func aliveCount() -> Int { piles.filter { !$0.dead }.count }
    public func anyAlive() -> Bool { piles.contains { !$0.dead } }

    /// True if pile `index` is alive and its TOP card carries Anchor. Anchor only
    /// counts while it's the current top (a later card buries it).
    public func isAnchored(_ index: Int) -> Bool {
        let p = piles[index]
        if p.dead { return false }
        if let top = p.cards.last, top.stickers.contains(where: { $0.type == "anchor" }) { return true }
        return forcedAnchor(index)   // Diamond Anchor (a ♦ top in a Diamond-Anchor column)
    }

    /// Smallest card count among ALL alive piles (anchors ignored). 0 if none.
    public func trueMinAliveCards() -> Int {
        var minV = Int.max
        for p in piles where !p.dead { minV = Swift.min(minV, sizeOf(p)) }
        return minV == Int.max ? 0 : minV
    }

    /// The "smallest alive pile" value used in the payout: the minimum card count
    /// among NON-anchored alive piles, so a deliberately-small anchored pile
    /// can't drag the product down. Fallback: if EVERY alive pile is anchored,
    /// revert to the true smallest. 0 if no piles are alive.
    public func minAliveCards() -> Int {
        var minNonAnchored = Int.max, minAll = Int.max
        for i in 0..<piles.count {
            let p = piles[i]
            if p.dead { continue }
            let len = sizeOf(p)
            minAll = Swift.min(minAll, len)
            if !isAnchored(i) { minNonAnchored = Swift.min(minNonAnchored, len) }
        }
        if minAll == Int.max { return 0 }                          // no alive piles
        return minNonAnchored == Int.max ? minAll : minNonAnchored
    }

    /// How a pile's count chip highlights relative to the score-dictating
    /// minimum (the web's `.pile-count` / `.min` / `.min-anchored`).
    public enum MinState: String {
        case none
        /// Score-dictating smallest (solid gold chip). Ties all highlight.
        case min
        /// True lowest but ANCHORED, so excluded from the payout (gold-lined).
        case minAnchored
    }

    /// Per-pile min highlight states, same rule as `minAliveCards()`: the
    /// payout minimum is the smallest NON-anchored alive pile (anchored piles
    /// can't drag the product down) — unless EVERY alive pile is anchored,
    /// when the true smallest counts (and highlights `.min`, never lined).
    public func minPileStates() -> [MinState] {
        var minNonAnchored = Int.max, minAll = Int.max
        for i in 0..<piles.count {
            let p = piles[i]
            if p.dead { continue }
            let len = sizeOf(p)
            minAll = Swift.min(minAll, len)
            if !isAnchored(i) { minNonAnchored = Swift.min(minNonAnchored, len) }
        }
        let allAnchored = minNonAnchored == Int.max
        return (0..<piles.count).map { i in
            let p = piles[i]
            if p.dead || minAll == Int.max { return .none }
            let len = sizeOf(p)
            if allAnchored { return len == minAll ? .min : .none }
            if !isAnchored(i) { return len == minNonAnchored ? .min : .none }
            return (len == minAll && minAll < minNonAnchored) ? .minAnchored : .none
        }
    }

    /// Extra Coin payout UNITS: for each alive top card carrying Extra Coin,
    /// (number of Extra Coin stickers on it) × (cards in that pile). Only alive
    /// top cards count.
    public func extraCoinUnits() -> Int {
        var units = 0
        for p in piles {
            if p.dead { continue }
            guard let top = p.cards.last else { continue }
            let n = top.stickers.filter { $0.type == "extraCoin" }.count
            if n > 0 { units += n * sizeOf(p) }
        }
        return units
    }
}
