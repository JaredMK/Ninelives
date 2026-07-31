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
    /// Lammy: stickers unusable — no effect may sticker a card.
    public var noStickers = false
    public init(cols: [Int]? = nil, sameCharge: Bool = false, samePower: String? = nil, noStickers: Bool = false) {
        self.cols = cols; self.sameCharge = sameCharge
        self.samePower = samePower; self.noStickers = noStickers
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
}
