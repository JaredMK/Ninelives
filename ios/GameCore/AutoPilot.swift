import Foundation

/// The autopilot's decision rule — pure, so it is unit-testable and carries no
/// dependency on the scene or the controller. The UI layer gathers the board
/// facts into `Input`; everything strategic happens here.
///
/// Ported from the web build's pilot (index.html `apCandidates`/`apChooseMove`)
/// and extended with the coin and score tiebreaks the native build wanted.
///
/// Priority, in order:
///  1. SURVIVAL. Certainties first (a Joker top, a Tell, a live peek), then the
///     remaining-card histogram. Jokers count toward EVERY direction — they are
///     safe whatever you call, so they belong in all three numerators.
///  2. BANK A SHIELD. Among moves within `tieEps` of the best odds, prefer one
///     that banks a Same charge; a free Joker Same is always taken when the
///     shield is empty.
///  3. HOLD THE JOKER. While a shield is already banked, a Joker-topped pile is
///     held back so its guaranteed Same is still available once the shield is
///     spent — unless it is all that is left.
///  4. COINS. Still tied? Take the move that pays more.
///  5. SCORE. Still tied? Feed the SMALLEST pile: score is alive × smallest, so
///     that is where one card is worth the most.
///  6. Lowest index, so the choice is deterministic.
public enum AutoPilot {

    /// Odds within this of the best count as "the same odds" for tiebreaking.
    public static let tieEps: Double = 0.05
    /// Reshuffle before the first guess when the best survival odds are worse
    /// than this and the redeal is cheap enough.
    public static let reshuffleOdds: Double = 0.65
    public static let reshuffleCostCap: Double = 12

    /// One alive pile, as the pilot sees it.
    public struct PileView {
        public var index: Int
        public var topValue: Int
        public var topIsJoker: Bool
        /// Weighted pile size — what the score and the payout actually read.
        public var size: Int
        /// A guaranteed direction from Tell / Spade Whispers, if armed.
        public var hint: Guess?
        /// Rough coins for playing here at all (sticker payouts on the card).
        public var coinValue: Int
        /// Extra coins if the call is specifically `.same` (a paying Same-Power).
        public var sameCoinValue: Int

        public init(index: Int, topValue: Int, topIsJoker: Bool, size: Int,
                    hint: Guess? = nil, coinValue: Int = 0, sameCoinValue: Int = 0) {
            self.index = index; self.topValue = topValue; self.topIsJoker = topIsJoker
            self.size = size; self.hint = hint
            self.coinValue = coinValue; self.sameCoinValue = sameCoinValue
        }
    }

    public struct Input {
        public var piles: [PileView]
        /// Rank value → remaining count. Key 0 is the JOKER bucket.
        public var deckCounts: [Int: Int]
        public var sameCharged: Bool
        /// The next card's rank when a peek/reveal is live, else nil.
        public var peekedValue: Int?
        public var peekedIsJoker: Bool

        public init(piles: [PileView], deckCounts: [Int: Int], sameCharged: Bool,
                    peekedValue: Int? = nil, peekedIsJoker: Bool = false) {
            self.piles = piles; self.deckCounts = deckCounts
            self.sameCharged = sameCharged
            self.peekedValue = peekedValue; self.peekedIsJoker = peekedIsJoker
        }
    }

    public struct Move: Equatable {
        public var pile: Int
        public var call: Guess
        /// Survival probability (1 for a certainty).
        public var p: Double
        /// This move banks a Same charge if it lands.
        public var banks: Bool
        /// Held back — a guaranteed Same that would be wasted at full charge.
        public var avoid: Bool
        public var size: Int
        public var coins: Int
    }

    public struct Decision: Equatable {
        public var move: Move
        /// Best odds ignoring avoidance — what the reshuffle check reads.
        public var bestRaw: Double
    }

    // MARK: - Candidates

    public static func candidates(_ input: Input) -> [Move] {
        let charged = input.sameCharged
        let jokers = input.deckCounts[0] ?? 0
        let total = input.deckCounts.values.reduce(0, +)
        var out: [Move] = []

        for p in input.piles {
            func move(_ call: Guess, _ prob: Double, avoid: Bool = false) -> Move {
                let banks = call == .same && !charged
                let coins = p.coinValue + (call == .same ? p.sameCoinValue : 0)
                return Move(pile: p.index, call: call, p: prob, banks: banks,
                            avoid: avoid, size: p.size, coins: coins)
            }

            // 1. A Joker on top: every call survives. Same banks the shield, so
            //    take it when empty and hold the pile back when it is full.
            if p.topIsJoker {
                out.append(move(.same, 1, avoid: charged))
                continue
            }
            // 2. A Tell hint is a guarantee.
            if let hint = p.hint {
                out.append(move(hint, 1))
                continue
            }
            // 3. A live peek makes the next card known. A known Joker draw is
            //    safe on anything, so spend it on a Same while the shield is
            //    empty — the "charge the shield on a peek" rule.
            if let next = input.peekedValue {
                let call: Guess
                if input.peekedIsJoker {
                    call = charged ? .higher : .same
                } else if next > p.topValue {
                    call = .higher
                } else if next < p.topValue {
                    call = .lower
                } else {
                    call = .same
                }
                out.append(move(call, 1))
                continue
            }
            // 4. No certainty — read the histogram.
            guard total > 0 else { continue }
            var above = 0, below = 0, equal = 0
            for (rank, n) in input.deckCounts where rank != 0 {
                if rank > p.topValue { above += n } else if rank < p.topValue { below += n } else { equal += n }
            }
            let pH = Double(above + jokers) / Double(total)
            let pL = Double(below + jokers) / Double(total)
            let pS = Double(equal + jokers) / Double(total)
            var call: Guess = .higher
            var prob = pH
            if pL > prob { call = .lower; prob = pL }
            // On a dead-even choice prefer SAME while the shield is empty: a
            // correct Same banks a charge on top of merely surviving.
            if pS > prob || (pS == prob && !charged) { call = .same; prob = pS }
            out.append(move(call, prob))
        }
        return out
    }

    // MARK: - Choice

    public static func choose(_ input: Input) -> Decision? {
        let all = candidates(input)
        guard !all.isEmpty else { return nil }
        let usable = all.filter { !$0.avoid }
        // Every remaining pile is a held-back Joker → play one anyway.
        let pool = usable.isEmpty ? all : usable
        let bestP = pool.map(\.p).max() ?? 0
        let ranked = pool.filter { $0.p >= bestP - tieEps }.sorted { a, b in
            if a.banks != b.banks { return a.banks }            // bank a shield
            if a.coins != b.coins { return a.coins > b.coins }   // then the coins
            if a.size != b.size { return a.size < b.size }       // then the score
            return a.pile < b.pile
        }
        return Decision(move: ranked[0], bestRaw: all.map(\.p).max() ?? 0)
    }

    /// Before the first guess, a bad deal-out is worth paying to re-roll.
    public static func shouldReshuffle(guessesMade: Int, bestRaw: Double,
                                       redealCost: Double, coins: Int) -> Bool {
        guessesMade == 0 && bestRaw < reshuffleOdds
            && redealCost <= reshuffleCostCap && Double(coins) >= redealCost
    }
}
