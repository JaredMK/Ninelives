import Foundation

/// DeckManager — responsible only for the cards themselves.
public enum DeckManager {
    /// Rank value: Ace high. 2..10 = face value, J=11, Q=12, K=13, A=14.
    public static let ranks: [(label: String, value: Int)] = [
        ("2", 2), ("3", 3), ("4", 4), ("5", 5), ("6", 6), ("7", 7), ("8", 8),
        ("9", 9), ("10", 10), ("J", 11), ("Q", 12), ("K", 13), ("A", 14),
    ]

    /// Suits are purely cosmetic (rank is all that matters). ARRAY ORDER is the
    /// suit-introduction schedule: `suitsForStage` slices the first (stage+1),
    /// so Stage 1 = ♦+♥, Stage 2 adds ♣, Stage 3 adds ♠.
    public static let suits: [(symbol: String, red: Bool)] = [
        ("♦", true), ("♥", true), ("♣", false), ("♠", false),
    ]

    /// ZEN's own suit order (not the stage schedule) so Easy reads red-vs-black.
    public static let zenSuitOrder = ["♥", "♠", "♦", "♣"]

    /// Build the standard 52-card deck of PERSISTENT identities.
    public static func buildStandardDeck() -> [CardSpec] {
        var cards: [CardSpec] = []
        var id = 0
        for s in suits {
            for r in ranks {
                cards.append(CardSpec(id: id, suit: s.symbol, originalRank: r.value, currentRank: r.value))
                id += 1
            }
        }
        return cards  // 52 cards
    }

    /// ZEN MODE deck: a fresh, UNMODIFIED standard deck kept to the first
    /// `suitCount` suits of the fixed Zen order — always suitCount × 13 cards,
    /// never a joker or sticker.
    public static func buildZenDeck(suitCount: Int) -> [CardSpec] {
        let n = max(1, min(zenSuitOrder.count, suitCount))
        let wanted = Set(zenSuitOrder.prefix(n))
        return buildStandardDeck().filter { wanted.contains($0.suit) }
    }

    /// Materialize a playable card from a persistent card (uses currentRank).
    /// Behavior stickers are projected onto run-local fields the engine reads;
    /// these reset on every deal, so a guard charge refreshes per run.
    public static func toCard(_ card: CardSpec, data: GameData = .shared) -> LiveCard {
        if card.joker {
            // JOKER: always a correct guess. value 0 so it triggers no rank
            // effects; suit "★" renders a star. No stickers/behaviors.
            return LiveCard(id: card.id, label: "★", value: 0, suit: "★", red: false, joker: true)
        }
        let r = ranks.first { $0.value == card.currentRank } ?? ranks[0]
        let s = suits.first { $0.symbol == card.suit } ?? suits[0]
        // One charge per guarded suit — duplicate guards of one suit don't stack.
        var guards: [String] = []
        for x in card.stickers {
            if let t = data.stickerTypes.get(x.type), t.behavior == "suitImmunity", let suit = t.suit,
               !guards.contains(suit) {
                guards.append(suit)
            }
        }
        return LiveCard(
            id: card.id, label: r.label, value: r.value, suit: s.symbol, red: s.red,
            joker: false, blank: card.blank,
            stickers: card.stickers,
            tieSafe: card.stickers.contains { $0.type == "tieSafe" },
            wildSuit: card.stickers.contains { $0.type == "wildSuit" },
            revealNext: card.stickers.contains { $0.type == "revealNext" },
            suitGuards: guards,
            compoundHits: card.compoundHits,
            snowball: card.snowball)
    }

    /// Fisher–Yates shuffle (in place), driven by a seeded rng.
    @discardableResult
    public static func shuffle(_ deck: inout [LiveCard], rng: RNG) -> [LiveCard] {
        var i = deck.count - 1
        while i > 0 {
            let j = rng.index(i + 1)
            deck.swapAt(i, j)
            i -= 1
        }
        return deck
    }

    /// Build a single card of a given rank value (used by debug overrides).
    public static func cardForValue(_ value: Int) -> LiveCard {
        let r = ranks.first { $0.value == value } ?? ranks[0]
        let s = suits[0]
        return LiveCard(id: -value, label: r.label, value: r.value, suit: s.symbol, red: s.red)
    }

    /// Create a run deck from a list of base-deck specs. The specs are copied +
    /// materialized, so playing a run never mutates the campaign deck.
    public static func create(_ specs: [CardSpec], rng: RNG, data: GameData = .shared) -> Deck {
        var cards = specs.map { toCard($0, data: data) }
        shuffle(&cards, rng: rng)
        return Deck(cards: cards, rng: rng)
    }
}

/// The run's draw deck.
public final class Deck {
    private var cards: [LiveCard]
    private let rng: RNG
    /// Lifetime counter: how many cards have been pulled OUT (top or bottom)
    /// since creation. Pure observation — a `returnCard` reinsertion is NOT
    /// un-counted, so a re-drawn card counts each time it leaves the deck.
    private var drawnCount = 0

    init(cards: [LiveCard], rng: RNG) { self.cards = cards; self.rng = rng }

    /// Remove and return the top card, or nil if empty.
    @discardableResult
    public func draw() -> LiveCard? {
        guard !cards.isEmpty else { return nil }
        drawnCount += 1
        return cards.removeFirst()
    }

    /// Remove and return the BOTTOM card, or nil if empty. Used by burials: the
    /// card is re-seated WITHOUT ever being revealed, so composition shifts
    /// while order stays hidden.
    @discardableResult
    public func drawFromBottom() -> LiveCard? {
        guard !cards.isEmpty else { return nil }
        drawnCount += 1
        return cards.removeLast()
    }

    public func remaining() -> Int { cards.count }
    public func drawn() -> Int { drawnCount }
    public var isEmpty: Bool { cards.isEmpty }

    /// Mid-deal snapshot support: the remaining cards, top first.
    func snapshotCards() -> [LiveCard] { cards }
    /// …and the exact-resume restore of both the order and the counter.
    func restoreSnapshot(cards: [LiveCard], drawn: Int) {
        self.cards = cards
        self.drawnCount = drawn
    }

    /// Count of remaining cards per rank value (order-free, no leak).
    public func remainingCounts() -> [Int: Int] {
        var counts: [Int: Int] = [:]
        for c in cards { counts[c.value, default: 0] += 1 }
        return counts
    }

    /// Count of remaining cards per SUIT (order-free, no leak).
    public func remainingSuitCounts() -> [String: Int] {
        var counts = ["♥": 0, "♦": 0, "♣": 0, "♠": 0]
        for c in cards where counts[c.suit] != nil { counts[c.suit]! += 1 }
        return counts
    }

    /// Look at the next n cards without drawing them.
    public func peek(_ n: Int = 1) -> [LiveCard] { Array(cards.prefix(max(0, n))) }

    /// Shuffle a (previously drawn) card back in at a random position, using the
    /// seeded rng — so a save happens without changing composition or revealing
    /// order.
    public func returnCard(_ card: LiveCard?) {
        guard let card else { return }
        let i = rng.index(cards.count + 1)
        cards.insert(card, at: i)
    }

    /// TUTORIAL arrangement: pull the first card matching `match` out of the
    /// deck (nil if none). Order is otherwise untouched.
    public func takeFirst(where match: (LiveCard) -> Bool) -> LiveCard? {
        guard let i = cards.firstIndex(where: match) else { return nil }
        return cards.remove(at: i)
    }

    /// TUTORIAL arrangement: make `card` the NEXT draw.
    public func putNext(_ card: LiveCard) { cards.insert(card, at: 0) }

    // MARK: Deck-modification hooks

    public func peekAll() -> [LiveCard] { cards }
    public func inject(_ extra: [LiveCard]) {
        cards.append(contentsOf: extra)
        DeckManager.shuffle(&cards, rng: rng)
    }

    // MARK: debug-only deck overrides

    /// Move an existing card of this rank to the top; when every copy is already
    /// OUT of the deck, SWAP the next card for a synthesized one instead of
    /// adding it — the deck count must never change here.
    @discardableResult
    public func setNext(value: Int) -> LiveCard {
        if let i = cards.firstIndex(where: { $0.value == value }) {
            let card = cards.remove(at: i)
            cards.insert(card, at: 0)
            return card
        }
        let card = DeckManager.cardForValue(value)
        if cards.isEmpty { cards.insert(card, at: 0) } else { cards[0] = card }
        return card
    }

    /// Inject an arbitrary card object as the next draw (QA — e.g. a Joker).
    @discardableResult
    public func setNextCard(_ card: LiveCard) -> LiveCard {
        cards.insert(card, at: 0)
        return card
    }

    @discardableResult
    public func trim(to n: Int) -> Int {
        if cards.count > n { cards.removeLast(cards.count - max(0, n)) }
        return cards.count
    }

    /// Remove ONE random card from what is still to be drawn, and report it.
    /// Never touches the board — only the future. Used by the Long Odds
    /// Same-Power; the RNG is passed in so the removal stays seeded.
    @discardableResult
    public func removeRandomRemaining(_ rng: RNG) -> LiveCard? {
        guard !cards.isEmpty else { return nil }
        return cards.remove(at: rng.index(cards.count))
    }

    @discardableResult
    public func drain() -> Int {
        let n = cards.count
        cards.removeAll()
        return n
    }
}

/// DeckStats — turns an order-free { rankValue: count } map into a display-ready
/// breakdown. It never sees or exposes card order, so it cannot leak draw order.
public enum DeckStats {
    public struct Row: Equatable, Sendable {
        public let value: Int
        public let label: String
        public let count: Int
        /// Chance of drawing this rank next, as a percentage.
        public let pct: Double
    }
    public struct Result: Equatable, Sendable {
        public let total: Int
        public let rows: [Row]
    }

    public static func fromCounts(_ counts: [Int: Int]) -> Result {
        let total = counts.values.reduce(0, +)
        let rows = DeckManager.ranks.map { r -> Row in
            let count = counts[r.value] ?? 0
            return Row(value: r.value, label: r.label, count: count,
                       pct: total != 0 ? Double(count) / Double(total) * 100 : 0)
        }
        return Result(total: total, rows: rows)
    }
}
