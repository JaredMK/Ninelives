import Foundation
import GameCore

/// Everything one deal needs, computed ONCE at entry — the web `startRun`'s
/// deck/pile/seed derivation, ported exactly. A resume rebuilds the same plan
/// from the persisted seed + subset; a reshuffle re-mints with the stepped
/// reshuffle index.
public struct DealPlan {
    public var deckForDeal: [CardSpec]
    public var piles: Int
    public var seed: UInt32
    public var nodeId: Int
    public var isBoss: Bool
    public var stage: Int
    public var rating: Int
    /// The fixed flat reward shown all deal (0 for an ambush).
    public var flatReward: Double
    public var isAmbush: Bool
    public var ambushBounty: Double
    public var ambushNodeId: Int?
    /// Persisted so a resume rebuilds the exact subset in its exact order.
    public var subsetIds: [Int]?
    public var fullDeckCount: Int
    public var reshuffleIndex: Int
    public var redealCost: Double
}

public enum DealPlanner {

    public static let redealBaseCost = 5.0
    public static let redealStep = 1.0

    public struct AmbushSpec {
        public var cards: Int
        public var piles: Int
        public var bounty: Double
        public var nodeId: Int
        public init(cards: Int, piles: Int, bounty: Double, nodeId: Int) {
            self.cards = cards; self.piles = piles; self.bounty = bounty; self.nodeId = nodeId
        }
    }

    /// Build the plan for entering the CURRENT node's deal (or an ambush).
    /// `resumeSeed`/`resumeSubset` replay a persisted deal exactly.
    public static func plan(campaign: CampaignState, runMap: RunMap,
                            reshuffleIndex: Int, redealCost: Double = redealBaseCost,
                            ambush: AmbushSpec? = nil,
                            resumeSeed: UInt32? = nil, resumeSubsetIds: [Int]? = nil,
                            resumePiles: Int? = nil) -> DealPlan {
        let node = campaign.currentNode()
        let isBoss = node?.type == "boss"
        let nodePiles = node?.piles ?? 9
        let fullDeck = campaign.getRunDeck()
        let ss = runMap.subset
        let wantSubset = !isBoss && (ambush != nil || fullDeck.count > ss.threshold)

        // SEED1 — the deal's keyed substream: everything (subset rolls + the
        // engine seed) draws from this ONE stream.
        let freshMint = resumeSeed == nil
        let dealNodeId = ambush?.nodeId ?? node?.id ?? 0
        let dealRng: RNG? = freshMint
            ? runRng(seed: campaign.runSeed,
                     [.s(ambush != nil ? "ambush" : "deal"), .n(dealNodeId), .n(reshuffleIndex)])
            : nil

        var deckForDeal: [CardSpec] = []
        var piles = nodePiles
        var resolved = false

        if wantSubset, let ids = resumeSubsetIds, let p = resumePiles {
            // RESUME: the exact saved subset IN ITS SAVED ORDER.
            let byId = Dictionary(uniqueKeysWithValues: fullDeck.map { ($0.id, $0) })
            let rebuilt = ids.compactMap { byId[$0] }
            if !rebuilt.isEmpty {
                deckForDeal = rebuilt
                piles = p
                resolved = true
            }
        }
        if wantSubset, !resolved, let a = ambush {
            piles = a.piles
            let n = min(fullDeck.count, a.cards + piles)
            deckForDeal = pickRandomSubset(fullDeck, n, dealRng)
            resolved = true
        }
        if wantSubset, !resolved {
            let targetD = node?.targetD
                ?? (nodePiles > 0 ? Double(fullDeck.count - nodePiles) / Double(nodePiles) : 3)
            let s = ss.min + Int((dealRng?.next() ?? 0.5) * Double(ss.max - ss.min + 1))
            piles = runMap.solveSubsetPiles(surviveCount: s, targetD: targetD)
            let n = min(fullDeck.count, s + piles)
            deckForDeal = pickRandomSubset(fullDeck, n, dealRng)
            resolved = true
        }
        if !wantSubset {
            piles = nodePiles
            deckForDeal = fullDeck
        }

        let stage = ambush != nil ? 0 : ((node?.phase ?? -1) + 1)
        let rating = isBoss ? 3
            : ((node?.targetD ?? 0) > 0
               ? runMap.difficultyScore(targetD: node!.targetD!, phaseIndex: node!.phase, isBoss: false)
               : 0)
        let economy = Economy()
        let flat = ambush != nil ? 0 : economy.dealFlat(stage: stage, rating: rating, isBoss: isBoss)

        // The engine seed: ONE draw from the deal stream, after the subset rolls.
        let seed = resumeSeed ?? UInt32((dealRng?.next() ?? 0.5) * 4294967296.0)

        return DealPlan(deckForDeal: deckForDeal,
                        piles: piles,
                        seed: seed,
                        nodeId: dealNodeId,
                        isBoss: isBoss,
                        stage: stage,
                        rating: rating,
                        flatReward: flat,
                        isAmbush: ambush != nil,
                        ambushBounty: ambush?.bounty ?? 0,
                        ambushNodeId: ambush?.nodeId,
                        subsetIds: wantSubset ? deckForDeal.map(\.id) : nil,
                        fullDeckCount: fullDeck.count,
                        reshuffleIndex: reshuffleIndex,
                        redealCost: redealCost)
    }

    /// A Zen deal's plan: a fresh suit-limited deck, config piles, no items.
    public static func zenPlan(diff: ZenConfig, seed: UInt32? = nil) -> DealPlan {
        let deck = DeckManager.buildZenDeck(suitCount: diff.suitCount)
        return DealPlan(deckForDeal: deck,
                        piles: diff.piles,
                        seed: seed ?? RNG.generateSeed(),
                        nodeId: 0, isBoss: false, stage: 0, rating: 0,
                        flatReward: 0, isAmbush: false, ambushBounty: 0, ambushNodeId: nil,
                        subsetIds: nil, fullDeckCount: deck.count,
                        reshuffleIndex: 0, redealCost: redealBaseCost)
    }

    /// The web's `pickRandomSubset` — n draws without replacement.
    public static func pickRandomSubset(_ deck: [CardSpec], _ n: Int, _ rng: RNG?) -> [CardSpec] {
        var pool = deck
        var out: [CardSpec] = []
        let take = min(n, pool.count)
        for _ in 0..<take {
            let i = rng?.index(pool.count) ?? Int.random(in: 0..<pool.count)
            out.append(pool.remove(at: i))
        }
        return out
    }
}
