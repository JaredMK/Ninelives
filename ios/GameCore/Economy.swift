import Foundation

/// One itemized bonus line in a payout breakdown.
public struct PayoutLine: Equatable, Sendable {
    public let label: String
    public let detail: String
    public let amount: Double
    public let col: Int?
    public let effect: String?
    public var id: String?
    public init(label: String, detail: String, amount: Double, col: Int? = nil,
                effect: String? = nil, id: String? = nil) {
        self.label = label; self.detail = detail; self.amount = amount
        self.col = col; self.effect = effect; self.id = id
    }
}

/// The inputs a payout is computed from — the Swift twin of the web `stats`
/// object handed to `Economy.breakdown`.
public struct PayoutStats: Sendable {
    public var won = false
    /// The `dealFlat()` base (0 for ambush/subset deals).
    public var flat: Double = 0
    /// 1-based map phase (endless phases keep counting: 4, 5, …).
    public var stage: Int = 0
    /// The deal's 1..3 stage-relative difficulty score.
    public var rating: Int = 0
    public var aliveCount: Int = 0
    public var minAliveCards: Int = 0
    public var extraCoinUnits: Int = 0
    public var pillarBonus: Double = 0
    public var pillarLines: [PayoutLine] = []
    /// The live in-run bonus tally (Middle Reward, Lucky Coin, Tribute costs …).
    /// It CAN be negative.
    public var eventBonus: Double = 0
    public var eventLines: [PayoutLine] = []
    /// An AMBUSH pays no flat stage base — its bounty IS the reward. It DOES
    /// score like any other battle (v5.82); the caller zeroes `flat`, not the
    /// product.
    public var ambush = false
    /// Only read by `liveBonus`.
    public var liveBonusCoins: Double = 0
    public init() {}
}

public struct PayoutBreakdown: Equatable, Sendable {
    public let won: Bool
    public let flat: Double
    public let stage: Int
    public let rating: Int
    public let alivePiles: Int
    public let minPileCards: Int
    /// alive piles × smallest alive pile — the deal SCORE, not coins.
    public let product: Int
    public let extraCoinUnits: Int
    public let extraCoinValue: Double
    public let extraCoinBonus: Double
    public let pillarBonus: Double
    public let pillarLines: [PayoutLine]
    public let eventBonus: Double
    public let eventLines: [PayoutLine]
    public let total: Double
}

/// Economy — pure coin payout (no state). Coins are awarded on a WIN only.
///
/// ECON1: a cleared deal pays a FLAT amount by stage and difficulty plus
/// item-driven bonuses; the old piles×smallest product survives as the SCORE
/// (the breakdown still reports it) but no longer feeds the coin total. Every
/// coefficient is a named knob in items.js.
public struct Economy: Sendable {
    /// × Extra Coin units (Σ stickers × that pile's cards) — the unit value is
    /// the Payout sticker's `value` knob in items.js.
    public let extraCoinValue: Double
    private let economyConfig: EconomyConfig

    public init(data: GameData = .shared) {
        self.extraCoinValue = data.stickerTypes.get("extraCoin")?.num("value", 1) ?? 1
        self.economyConfig = data.items.economy
    }

    /// The FLAT coin payout for clearing a deal (ECON2, v6.86): a ladder
    /// read straight from items.js `economy` — `dealPayouts[rating-1]`
    /// (4/5/6 by the deal's 1..3 stage-relative difficulty), `bossPayout`
    /// (7) flat for any boss. There is no stage term: endless deals rate
    /// against their own phase's lifted band, so they pay these same flat
    /// rates forever (the v6.78 stageCap freeze is subsumed — phase-3
    /// rates ARE the rates). No stage context (ambush/subset deals, a
    /// missing rating) still pays NO flat base — returns 0.
    public func dealFlat(stage: Int, rating: Int, isBoss: Bool) -> Double {
        guard stage > 0 else { return 0 }
        if isBoss { return economyConfig.bossPayout }
        guard rating > 0 else { return 0 }
        let ladder = economyConfig.dealPayouts
        guard !ladder.isEmpty else { return 0 }
        return ladder[min(rating, ladder.count) - 1]
    }

    /// The itemized payout, so the UI can show where coins came from without
    /// recomputing. `computeRunPayout()` is just `breakdown().total`.
    public func breakdown(_ stats: PayoutStats) -> PayoutBreakdown {
        let won = stats.won
        let flat = won ? stats.flat : 0
        let stage = won ? stats.stage : 0
        let rating = won ? stats.rating : 0
        let alivePiles = won ? stats.aliveCount : 0
        let minPileCards = won ? stats.minAliveCards : 0
        let extraCoinUnits = won ? stats.extraCoinUnits : 0
        // Pillar contributions arrive already itemized from the engine.
        let pillarBonus = won ? stats.pillarBonus : 0
        let pillarLines = won ? stats.pillarLines : []
        let eventBonus = won ? stats.eventBonus : 0
        let eventLines = won ? stats.eventLines : []
        // The guard keeps the product 0 (never NaN) when no piles are alive.
        // EVERY battle scores, ambushes included (v5.82) — an ambush still pays
        // no flat base (`stats.flat` is 0 for one), but its piles count.
        let product = alivePiles > 0 ? alivePiles * minPileCards : 0
        let extraCoinBonus = Double(extraCoinUnits) * extraCoinValue
        return PayoutBreakdown(
            won: won, flat: flat, stage: stage, rating: rating,
            alivePiles: alivePiles, minPileCards: minPileCards, product: product,
            extraCoinUnits: extraCoinUnits, extraCoinValue: extraCoinValue,
            extraCoinBonus: extraCoinBonus,
            pillarBonus: pillarBonus, pillarLines: pillarLines,
            eventBonus: eventBonus, eventLines: eventLines,
            // The flat base can't go negative, but a Tribute cost can drag the
            // bonus below zero; clamp the TOTAL at 0 so a win never charges coins.
            total: max(0, flat + extraCoinBonus + pillarBonus + eventBonus))
    }

    /// Coins earned (the total of `breakdown()`).
    public func computeRunPayout(_ stats: PayoutStats) -> Double { breakdown(stats).total }

    /// LIVE bonus tracker — coins items have paid DURING the deal only
    /// (v6.94). Deal-end awards (scoring-pillar payouts, Payout sticker
    /// units) are deliberately EXCLUDED: they don't exist until the final
    /// turn resolves, so they never show in the running tracker — and
    /// Devil's Deal / Bonus Reset, which operate on this same tally, can
    /// never double or zero money that hasn't been earned yet.
    public func liveBonus(_ stats: PayoutStats) -> Double {
        stats.liveBonusCoins
    }
}
