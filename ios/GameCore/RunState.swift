import Foundation

/// An ordered label→amount tally. The web keeps `run.bonusEvents` as a plain
/// object and itemizes it in insertion order; a Swift Dictionary would scramble
/// that, so this preserves first-seen order.
public struct OrderedTally: Sendable, Equatable {
    public private(set) var keys: [String] = []
    private var values: [String: Double] = [:]

    public init() {}
    public subscript(key: String) -> Double {
        get { values[key] ?? 0 }
        set {
            if values[key] == nil { keys.append(key) }
            values[key] = newValue
        }
    }
    public mutating func add(_ key: String, _ amount: Double) { self[key] = self[key] + amount }
    public var pairs: [(label: String, amount: Double)] { keys.map { ($0, values[$0]!) } }
    public var isEmpty: Bool { keys.isEmpty }
}

/// A queued paid-bury offer awaiting the player's Yes/No.
public struct TributeOffer: Sendable, Equatable {
    public var index: Int
    public var count: Int
    public var cost: Double
    public var label: String
    public var type: String
}

/// A queued optional post-landing action awaiting the player's Yes/No.
public struct PendingAction: Sendable, Equatable {
    public var kind: String   // "shuffle" | "donate"
    public var index: Int
    public var target: Int?
}

/// One debug-logbook entry — ground-truth, appended where effects execute.
public struct LogEntry: Sendable, Equatable {
    public var title: String
    public var lines: [String]
}

/// The formal run-state wrapper: phase, the run's seed, and summary stats.
public final class RunState {
    /// "start" | "active" | "ended"
    public var phase = "start"
    public var seed: UInt32
    /// "win" | "loss" once ended.
    public var result: String?
    public var correctGuesses = 0
    public var totalGuesses = 0
    /// Draws made by the initial deal, so "cards drawn during play" excludes them.
    public var dealDraws = 0
    public var cardsDrawn = 0
    /// The run deals into the STICKER phase: `started` false, sticker window open.
    public var started = false
    public var stickerWindow = true

    /// Column sizes (e.g. [3,4,3]); nil for column-agnostic legacy/test runs.
    public var cols: [Int]?
    /// pile index → its column index.
    public var pileColumns: [Int]?
    /// Per-column Pillar binding, locked at startRun.
    public var pillars: [String?]?
    /// The equipped Same-Power for this deal.
    public var samePower: String?
    /// The power's climb-fixed variant, when it rolls one (Burrow's suit,
    /// Second Sight's red/black). Nil for the fixed powers.
    public var samePowerVariant: String?
    /// The rank-variant pillars' locked ranks, by pillar id.
    public var pillarRankVariants: [String: Int] = [:]
    /// Synapse-link adjacency the UI pushes in (pile → directly linked piles).
    public var links: [Int: [Int]] = [:]

    public var suitBountyHits: [Int]?
    public var eightTributesUsed: [Int]?
    public var sameTributesUsed: [Int]?
    public var denseBuryUsed: [Int]?
    /// Revive (one-shot per deal, per column).
    public var reviveUsed: [Bool]?

    /// Per-column Base binding, locked at Start Run.
    public var bases: [String?]?
    /// `basesUsed[col]` — false means charged (ready), true means already fired.
    public var basesUsed: [Bool]?
    /// This deal's Base randomizers (Set Value's value, Suit Tally's suit).
    public var baseRandom: (value: Int, suit: String?)?

    /// How many of the NEXT draws still show the upcoming card on the deck.
    public var kamikazeRevealLeft = 0
    public var pendingActions: [PendingAction] = []
    public var pendingTributes: [TributeOffer] = []
    /// Opt-in Diamond Ripple consent (iOS UI): when true, a landing that would
    /// auto-shuffle every ♦-topped pile instead records `pendingRipple` and
    /// waits for `answerRipple`. DEFAULT FALSE — the web's auto-shuffle, and
    /// every fixture/trace runs with it unset.
    public var rippleNeedsConsent = false
    /// The ♦-top piles a consented Diamond Ripple would shuffle (captured at
    /// the landing) + the landing pile's column (for the fired pulse).
    public var pendingRipple: (piles: [Int], col: Int?)?

    /// Live bonus-coin tally + its itemization.
    public var bonusCoins: Double = 0
    public var bonusEvents = OrderedTally()

    /// Per-column consecutive-correct-guess streak.
    public var colStreak: [Int]?
    public var secondWindUsed: [Bool]?

    /// Accrued this run, written back to the persistent card on a WIN.
    public var compoundUpdates: [Int: Int] = [:]
    public var snowballUpdates: [Int: Int] = [:]
    public var stickerPeels: [Int: Int] = [:]

    /// Display-only: the next deck card is revealed.
    public var revealNextActive = false
    /// Pile indices with an active directional hint (display only).
    public var tellPiles = Set<Int>()
    /// Piles armed by SPADE WHISPERS. Kept apart from `tellPiles` because a
    /// Tell hint is spent by the very next draw, while a whisper lasts for
    /// `tellDrawsLeft` draws — on ITS OWN pile, never board-wide.
    public var whisperPiles = Set<Int>()
    /// How many upcoming DRAWS still carry a whole-board Tell-style hint.
    public var tellDrawsLeft = 0

    /// Debug logbook — dev tooling only, never read by game logic.
    public var log: [LogEntry] = []

    init(seed: UInt32, cols: [Int]?, pileColumns: [Int]?, pileCount: Int, samePower: String?) {
        self.seed = seed
        self.cols = cols
        self.pileColumns = pileColumns
        self.samePower = samePower
        if let cols {
            let n = cols.count
            suitBountyHits = Array(repeating: 0, count: n)
            eightTributesUsed = Array(repeating: 0, count: n)
            sameTributesUsed = Array(repeating: 0, count: n)
            denseBuryUsed = Array(repeating: 0, count: n)
            reviveUsed = Array(repeating: false, count: n)
            basesUsed = Array(repeating: false, count: n)
            colStreak = Array(repeating: 0, count: n)
            secondWindUsed = Array(repeating: false, count: n)
        }
    }
}

/// Per-run layout/modifier data handed to `GameEngine.create`.
public struct RunConfig {
    /// The column-size array (e.g. [3,4,3]) — teaches the otherwise
    /// column-agnostic engine which piles belong to which COLUMN. Omitted/empty
    /// → no column info and no Pillar effects.
    public var cols: [Int]?
    /// Same Charge, seeded from the campaign (it persists across deals).
    public var sameCharge = false
    /// The equipped Same-Power id.
    public var samePower: String?
    /// Its climb-fixed variant (Burrow's suit / Second Sight's colour).
    public var samePowerVariant: String?
    /// The rank-variant pillars' locked ranks, by pillar id.
    public var pillarRankVariants: [String: Int] = [:]
    /// Lammy: stickers unusable — no effect may sticker a card.
    public var noStickers = false
    /// This deal is an AMBUSH. The engine is otherwise blind to it (an ambush
    /// is a flow-level shape), but a Base can now gate on it.
    public var isAmbush = false
    /// This deal is a BOSS. Last Resort seals itself during one.
    public var isBoss = false
    public init(cols: [Int]? = nil, sameCharge: Bool = false, samePower: String? = nil,
                samePowerVariant: String? = nil, pillarRankVariants: [String: Int] = [:],
                noStickers: Bool = false, isAmbush: Bool = false, isBoss: Bool = false) {
        self.cols = cols; self.sameCharge = sameCharge
        self.samePower = samePower; self.samePowerVariant = samePowerVariant
        self.pillarRankVariants = pillarRankVariants
        self.noStickers = noStickers
        self.isAmbush = isAmbush
        self.isBoss = isBoss
    }
}

/// What the engine emits. The renderer subscribes; the engine never touches it.
public enum EngineEvent {
    case dealt
    case runStarted
    case resolved(index: Int, guess: Guess, current: LiveCard, drawn: LiveCard, correct: Bool)
    case guarded(index: Int, guess: Guess, current: LiveCard, drawn: LiveCard)
    case secondWind(index: Int, guess: Guess, current: LiveCard)
    case sameSaved(index: Int, guess: Guess, current: LiveCard, drawn: LiveCard, sameCharge: Bool)
    case sameBanked(index: Int, sameCharge: Bool)
    case pileKilled(index: Int)
    case buried(index: Int, count: Int, source: String)
    case stickerCoins(index: Int, label: String, amount: Double)
    case pillarFired(col: Int, effect: String, label: String, amount: Double, moves: [(from: Int, to: Int)])
    case cardDuplicated(cardId: Int, index: Int)
    case tributeOffer(TributeOffer)
    case tributeResolved(index: Int, accepted: Bool)
    case actionOffer(PendingAction)
    case actionResolved(kind: String, index: Int, target: Int?, accepted: Bool)
    case reviveOffer(col: Int, dead: [Int])
    case revived(col: Int, index: Int)
    case baseFired(BaseResult)
    case samePower(SamePowerResult)
    /// Second Wind rolled on a dying pile in its column and did NOT save it.
    case secondWindMiss(index: Int, col: Int)
    /// Flypaper stuck a random sticker to the card that just landed.
    case pillarSticker(col: Int, pileIndex: Int, cardId: Int, typeId: String)
    /// A Tie-Safe STICKER turned a directional tie into a save (v6.50: it
    /// used to land silently — the one save in the game with no cue).
    case tieSafeSaved(index: Int)
    /// Wild Aces played an Ace LOW to make this guess correct (v6.50: the
    /// flip looked like a rules glitch without a cue).
    case wildAceFlipped(index: Int, col: Int)
    /// A landing-time curse fired (Shield Drain / Base Drain / Spoiler).
    /// `detail` is the ready-made float text.
    case curseFired(index: Int, curse: String, label: String, detail: String)
    /// MALFUNCTION: a correct guess against the cursed top killed the pile.
    case malfunction(index: Int, cardLabel: String)
    /// JAMMER: the column's pillar would have mattered on this landing but a
    /// jammer top is blocking it.
    case pillarBlocked(col: Int)
    /// PEELER tore every sticker off a touched card — the flow must remove
    /// the same stickers from the campaign identity.
    case cursePeeled(index: Int, cardId: Int, types: [String])
    /// SABOTEUR destroyed a column item — the flow must remove it from the
    /// campaign loadout (the engine already cleared its own copy).
    case sabotaged(col: Int, kind: String, itemId: String)
    case won(pillarPayout: PillarPayout)
    case lost
}

/// The three calls.
public enum Guess: String, Sendable, CaseIterable {
    case higher, lower, same
}

/// The itemized Pillar payout for the current board state.
public struct PillarPayout: Sendable, Equatable {
    public var bonus: Double
    public var lines: [PayoutLine]
}

/// What a Base activation did (for the UI + tests).
public struct BaseResult {
    public var col: Int
    public var effect: String
    public var label: String
    public var index: Int?
    public var hub: Int?
    public var cards: [LiveCard]?
    public var peekCount: Int?
    public var shuffled: Int?
    public var moves: Int?
    public var harvested: Int?
    public var buried: Int?
    public var refreshed: [Int]?
    public var piles: Int?
    public var destroyedPiles: [Int]?
    public var demolishedCol: Int?
    public var demolishedPillar: String?
    public var gained: Double?
    public var returnedCount: Int?
    public var sameCharge: Bool?
    public var stickerApplied: (pileIndex: Int, cardId: Int, typeId: String)?
    public var valueApplied: [(cardId: Int, value: Int)]?
    public var suitApplied: [(cardId: Int, suit: String)]?
    public var sourceValue: Int?
    public var sourceSuit: String?
    /// Club Oracle: the ♣ pile it read, and the next card's direction vs it.
    public var tellPile: Int?
    public var tellDirection: Guess?
    /// Net coins this Base moved (for the UI float).
    public var coins: Double = 0
}

public struct SamePowerResult: Sendable, Equatable {
    public var power: String
    public var label: String
    public var hub: Int
    public var effect: String
    public var targets: [Int] = []
    public var amount: Int = 0
    /// Stickers this power put on BOARD cards, as (cardId, typeId). The
    /// engine only ever marks the live card; the campaign copy is written by
    /// the flow, exactly as a Base's `stickerApplied` is — without this the
    /// stickers vanished the moment the deal ended.
    public var stickersApplied: [(cardId: Int, typeId: String)] = []

    public static func == (a: SamePowerResult, b: SamePowerResult) -> Bool {
        a.power == b.power && a.label == b.label && a.hub == b.hub && a.effect == b.effect
            && a.targets == b.targets && a.amount == b.amount
            && a.stickersApplied.map(\.cardId) == b.stickersApplied.map(\.cardId)
            && a.stickersApplied.map(\.typeId) == b.stickersApplied.map(\.typeId)
    }
}
