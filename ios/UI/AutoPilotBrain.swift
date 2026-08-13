import Foundation
import GameCore

/// Adapter between the live deal and `AutoPilot`, the pure decision rule in
/// GameCore. Everything strategic lives there (and is unit-tested); this only
/// gathers board facts and scores the coin heuristic off the registry.
enum AutoPilotBrain {

    static func choose(_ c: DealController) -> AutoPilot.Decision? {
        guard var d = AutoPilot.choose(input(c)) else { return nil }
        // MUTE curse: the engine refuses Same on a muted pile — a pilot that
        // insisted would stall retrying the same refused call forever. Fall
        // back to the direction with more survivors in the deck.
        if d.move.call == .same, c.pileIsMuted(d.move.pile) {
            let top = c.pileCards(d.move.pile).last?.value ?? 8
            let counts = c.deckCounts()
            let higher = counts.filter { $0.key > top }.values.reduce(0, +)
            let lower = counts.filter { $0.key < top && $0.key > 0 }.values.reduce(0, +)
            d.move.call = higher >= lower ? .higher : .lower
        }
        return d
    }

    static func input(_ c: DealController) -> AutoPilot.Input {
        let peek = c.peekedNextCard()
        // A paying Same-Power fires on a correct Same — worth chasing when two
        // moves are equally safe.
        var samePowerCoins = 0
        if let power = c.equippedSamePowerDef(), power.effect == "linkCoins" {
            samePowerCoins = max(1, Int(power.value)) * max(1, c.aliveCount())
        }
        // MAGNET curse: while a magnet tops the board, the engine only takes
        // guesses on magnet piles — the pilot must see the same board the
        // player does or it stalls retrying refused moves.
        let magnets = c.magnetPileSet()
        let playable = magnets.isEmpty ? c.alivePiles()
                                       : c.alivePiles().filter { magnets.contains($0) }
        let piles: [AutoPilot.PileView] = playable.compactMap { i in
            guard let top = c.pileCards(i).last else { return nil }
            return AutoPilot.PileView(
                index: i,
                topValue: top.value,
                topIsJoker: top.joker,
                size: c.pileSize(i),
                hint: c.hint(forPile: i),
                coinValue: coinValue(of: top),
                sameCoinValue: samePowerCoins)
        }
        return AutoPilot.Input(piles: piles,
                               deckCounts: c.deckCounts(),
                               sameCharged: c.sameChargeBanked,
                               peekedValue: peek?.value,
                               peekedIsJoker: peek?.joker ?? false)
    }

    static func shouldReshuffle(_ c: DealController, bestRaw: Double, coins: Int) -> Bool {
        AutoPilot.shouldReshuffle(guessesMade: c.totalGuessesMade, bestRaw: bestRaw,
                                  redealCost: c.currentRedealCost, coins: coins)
    }

    /// Roughly what this card is worth in coins. An ORDERING heuristic, not an
    /// exact payout — it only has to rank equally-safe moves. Values come from
    /// the registry, so a retune in items.js moves the pilot's taste with it.
    private static func coinValue(of card: LiveCard) -> Int {
        var coins = 0
        for s in card.stickers {
            guard let def = GameData.shared.stickerTypes.get(s.type) else { continue }
            switch def.behavior {
            case "gainCoin", "extraCoin", "collector", "deathBounty",
                 "heartChoir", "looseChange", "deepPockets", "compound":
                coins += max(1, Int(def.value))
            case "tributeCoin":
                coins -= max(1, Int(def.value))   // a cursed drain is a reason to look elsewhere
            default:
                break
            }
        }
        return coins
    }
}
