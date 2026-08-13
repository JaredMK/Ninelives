import Foundation

/// A sticker record riding a card identity. Stickers are stored by TYPE id and
/// stack (a card may carry several of the same type).
public struct StickerRecord: Codable, Equatable, Sendable {
    public let type: String
    public init(type: String) { self.type = type }
}

/// A recorded permanent edit to a card identity (Deck Inspector shows these).
public struct CardModification: Codable, Equatable, Sendable {
    public let op: String       // "increase" | "decrease" | "randomRank" | "changeSuit"
    public let from: JSONValue  // rank number or suit symbol
    public let to: JSONValue
    public init(op: String, from: JSONValue, to: JSONValue) { self.op = op; self.from = from; self.to = to }
}

/// A PERSISTENT card identity — the campaign's base deck. Stable `id` + suit,
/// the rank it started as, the rank it is now, a modification history, and the
/// stickers that ride with this id for the whole campaign.
public struct CardSpec: Codable, Equatable, Sendable {
    public var id: Int
    public var suit: String
    public var originalRank: Int
    public var currentRank: Int
    public var modifications: [CardModification]
    public var stickers: [StickerRecord]
    /// Compound sticker: lifetime correct guesses made against this identity.
    public var compoundHits: Int
    /// Snowball Bury: the per-card bury size X.
    public var snowball: Int
    /// A wild ★ card: ALWAYS a correct guess, banks nothing, takes no stickers.
    public var joker: Bool
    /// A Removal (∅) card: never takes stickers.
    public var blank: Bool

    public init(id: Int, suit: String, originalRank: Int, currentRank: Int,
                modifications: [CardModification] = [], stickers: [StickerRecord] = [],
                compoundHits: Int = 0, snowball: Int = 0, joker: Bool = false, blank: Bool = false) {
        self.id = id; self.suit = suit
        self.originalRank = originalRank; self.currentRank = currentRank
        self.modifications = modifications; self.stickers = stickers
        self.compoundHits = compoundHits; self.snowball = snowball
        self.joker = joker; self.blank = blank
    }

    public static func joker(id: Int) -> CardSpec {
        CardSpec(id: id, suit: "★", originalRank: 0, currentRank: 0, joker: true)
    }
    public static func blank(id: Int) -> CardSpec {
        CardSpec(id: id, suit: "∅", originalRank: 0, currentRank: 0, blank: true)
    }
}

/// A LIVE, playable card — `DeckManager.toCard`'s projection of a `CardSpec`.
///
/// A reference type on purpose: the web's live cards are plain objects held by
/// the deck and the piles, and the engine mutates them in place (`compoundHits`,
/// `snowball`, sticker projection from Same Spark / Wild Sticker). Value
/// semantics would silently drop those writes.
public final class LiveCard {
    public let id: Int
    public var label: String
    public var value: Int
    public var suit: String
    public var red: Bool
    public var joker: Bool
    public var blank: Bool
    /// Rendering badges + every behavior read (`stickers.some(x => x.type === …)`).
    public var stickers: [StickerRecord]
    /// Tie-Safe: any tie involving this card is safe.
    public var tieSafe: Bool
    /// Wild Suit: this card counts as EVERY suit, everywhere suit is checked.
    public var wildSuit: Bool
    /// Scout: placing this card reveals the next deck card.
    public var revealNext: Bool
    /// Suit Guard charges, one per guarded suit, IN APPLICATION ORDER — the web
    /// stores them as a `{ suit: true }` object and `findGuardSave` walks it with
    /// `for…in`, so the first-inserted matching guard is the one that reports the
    /// save. A Swift Dictionary would scramble that, so this is an ordered list.
    public var suitGuards: [String]
    /// Compound: lifetime correct guesses against this identity.
    public var compoundHits: Int
    /// Snowball Bury: the per-card bury size X.
    public var snowball: Int

    init(id: Int, label: String, value: Int, suit: String, red: Bool,
         joker: Bool = false, blank: Bool = false, stickers: [StickerRecord] = [],
         tieSafe: Bool = false, wildSuit: Bool = false, revealNext: Bool = false,
         suitGuards: [String] = [], compoundHits: Int = 0, snowball: Int = 0) {
        self.id = id; self.label = label; self.value = value; self.suit = suit; self.red = red
        self.joker = joker; self.blank = blank; self.stickers = stickers
        self.tieSafe = tieSafe; self.wildSuit = wildSuit; self.revealNext = revealNext
        self.suitGuards = suitGuards; self.compoundHits = compoundHits; self.snowball = snowball
    }
}

extension LiveCard: Equatable {
    public static func == (a: LiveCard, b: LiveCard) -> Bool { a === b }
}

// MARK: - The shared card predicates (data-driven, never hardcoded ids)

public enum CardRules {
    /// Does this card count as EVERY suit? True when it carries a Wild Suit
    /// sticker — detected by items.js BEHAVIOR, on both card shapes: live cards
    /// get a `wildSuit` flag, persistent specs only carry the sticker record.
    public static func isWildSuit(_ card: LiveCard?, data: GameData = .shared) -> Bool {
        guard let card else { return false }
        if card.wildSuit { return true }
        return card.stickers.contains { data.stickerTypes.get($0.type)?.behavior == "wildSuit" }
    }
    public static func isWildSuit(_ spec: CardSpec, data: GameData = .shared) -> Bool {
        spec.stickers.contains { data.stickerTypes.get($0.type)?.behavior == "wildSuit" }
    }

    /// THE single suit-membership test for item effects: does `card` count as
    /// `suit`? True on a printed-suit match OR when the card is Wild Suit.
    /// EVERY suit-gated effect goes through here.
    public static func matchesSuit(_ card: LiveCard?, _ suit: String, data: GameData = .shared) -> Bool {
        guard let card else { return false }
        return card.suit == suit || isWildSuit(card, data: data)
    }
    public static func matchesSuit(_ spec: CardSpec, _ suit: String, data: GameData = .shared) -> Bool {
        spec.suit == suit || isWildSuit(spec, data: data)
    }

    /// The GLOBAL sticker-application gate — may `card` receive sticker `typeId`?
    /// Three rules, enforced at EVERY application path:
    ///   1. Jokers and Removal cards NEVER take stickers, from any source.
    ///   2. A sticker with a `suits` restriction only attaches to cards of those
    ///      printed suits. EXCEPTION: a WILD SUIT card counts as every suit.
    ///   3. A card never carries TWO of the same sticker (v6.36) — the pickers
    ///      grey such cards out, and rolls skip them.
    /// Rank-boundary rules (no +1 on an Ace…) stay with the callers.
    public static func stickerEligible(_ card: LiveCard?, _ typeId: String, data: GameData = .shared) -> Bool {
        guard let card, !card.joker, !card.blank else { return false }
        guard let t = data.stickerTypes.get(typeId) else { return false }
        // A FULL card takes nothing more, from any source.
        guard card.stickers.count < data.items.maxStickersPerCard else { return false }
        guard !card.stickers.contains(where: { $0.type == typeId }) else { return false }
        guard let suits = t.suits, !suits.isEmpty else { return true }  // unrestricted
        if isWildSuit(card, data: data) { return true }                 // wild = all suits
        return suits.contains(card.suit)
    }
    public static func stickerEligible(_ spec: CardSpec, _ typeId: String, data: GameData = .shared) -> Bool {
        guard !spec.joker, !spec.blank else { return false }
        guard let t = data.stickerTypes.get(typeId) else { return false }
        guard spec.stickers.count < data.items.maxStickersPerCard else { return false }
        guard !spec.stickers.contains(where: { $0.type == typeId }) else { return false }
        guard let suits = t.suits, !suits.isEmpty else { return true }
        if isWildSuit(spec, data: data) { return true }
        return suits.contains(spec.suit)
    }
}
