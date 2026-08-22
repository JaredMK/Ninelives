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

/// A Second Wind save roll that HIT, parked for the player's call (iOS
/// consent mode): save the pile (its cards + the killer recycle into the deck)
/// or let it die. The killing card is HELD here — out of deck and piles —
/// until `answerSecondWind` settles it.
public struct PendingSecondWind {
    public var index: Int
    public var col: Int
    public var guess: Guess
    public var killingCard: LiveCard
    /// Cards the save would recycle into the deck (the pile + the killer) —
    /// the X the prompt states.
    public var recycleCount: Int
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
    /// SHOP-ROLLED pillar/base values (v6.76): item id → its climb-locked
    /// {rank}/{suit} (Rank Shield, Void Tribute, Majority Rule…). Threaded
    /// from the campaign at deal creation via RunConfig; round-trips the
    /// mid-deal snapshot.
    public var shopRolls: [String: ShopRoll] = [:]
    /// DAILY SUIT (v6.76): column → the suit its Daily Suit pillar shields
    /// THIS deal, rolled at Start Run off the deal's seeded stream. A redeal
    /// re-creates the engine with a fresh seed, which re-rolls it — no reset
    /// needed. Nil for column-agnostic legacy/test runs. Round-trips the
    /// mid-deal snapshot.
    public var dailySuits: [Int: String]?
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
    /// Same consent discipline as `rippleNeedsConsent`, for the two effects
    /// v6.55 turns into player choices: Second Wind's save (save it or let it
    /// die) and the Link Shuffler Same-Power (shuffle or keep the order).
    /// DEFAULT FALSE — the web auto-applies both, and every fixture/trace runs
    /// with them unset.
    public var secondWindNeedsConsent = false
    public var samePowerNeedsConsent = false
    /// A Second Wind roll that hit, awaiting `answerSecondWind`.
    public var pendingSecondWind: PendingSecondWind?
    /// A correct Same with the Link Shuffler equipped, awaiting
    /// `answerPowerShuffle` — the value is the hub pile the Same was called on.
    public var pendingPowerShuffle: Int?

    /// Live bonus-coin tally + its itemization.
    public var bonusCoins: Double = 0
    public var bonusEvents = OrderedTally()

    /// Per-column consecutive-correct-guess streak.
    public var colStreak: [Int]?
    public var secondWindUsed: [Bool]?
    /// Gambler: the deal-end coin flip is rolled ONCE per Gambler column at
    /// Start Run and memoized here (column → won), so every payout PROJECTION
    /// (the HUD re-reads `pillarPayout()` per render) shows the SAME result the
    /// deal end pays — no read ever consumes the action-stream rng. Nil for
    /// column-agnostic legacy/test runs. Round-trips the mid-deal snapshot.
    public var gamblerFlips: [Int: Bool]?

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
    /// SECOND SIGHT window (v6.58): for this many upcoming draws the hint
    /// shows on ONE pile only — the most recently landed top card.
    public var sightDrawsLeft = 0
    /// The pile whose LIVING top most recently landed (nil after a death,
    /// a revive's fresh deal, or before any landing). Second Sight's anchor.
    public var lastLandedPile: Int? = nil

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
            gamblerFlips = [:]
            dailySuits = [:]
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
    /// The shop-rolled items' climb-locked {rank}/{suit}, by item id (v6.76).
    public var shopRolls: [String: ShopRoll] = [:]
    /// Rocko: stickers unusable — no effect may sticker a card.
    public var noStickers = false
    /// This deal is an AMBUSH. The engine is otherwise blind to it (an ambush
    /// is a flow-level shape), but a Base can now gate on it.
    public var isAmbush = false
    /// This deal is a BOSS. Last Resort seals itself during one.
    public var isBoss = false
    public init(cols: [Int]? = nil, sameCharge: Bool = false, samePower: String? = nil,
                samePowerVariant: String? = nil, pillarRankVariants: [String: Int] = [:],
                shopRolls: [String: ShopRoll] = [:],
                noStickers: Bool = false, isAmbush: Bool = false, isBoss: Bool = false) {
        self.cols = cols; self.sameCharge = sameCharge
        self.samePower = samePower; self.samePowerVariant = samePowerVariant
        self.pillarRankVariants = pillarRankVariants
        self.shopRolls = shopRolls
        self.noStickers = noStickers
        self.isAmbush = isAmbush
        self.isBoss = isBoss
    }
}

/// The structured outcome of one item's %-CHANCE roll (v6.57 probability
/// feedback). Emitted at the moment the roll is made — BEFORE the effect's
/// own events on a hit — so the UI can show the roll and then its verdict.
/// A roll that never happens (its precondition failed, e.g. Saboteur with no
/// Pillar/Base left to destroy) emits NOTHING: only real draws are reported.
public struct RollResult: Sendable, Equatable {
    /// The item's registry id ("saboteur", "secondWind", "linkPurge", …).
    public var id: String
    /// Its player-facing label (from the item def).
    public var label: String
    /// "sticker" | "pillar" | "samePower" — the telemetry class.
    public var klass: String
    /// The probability the roll was made against (0–1), read live from the def.
    public var chance: Double
    public var hit: Bool
    /// The pile the roll concerns, when pile-scoped.
    public var index: Int?
    /// The column the roll concerns, when column-scoped.
    public var col: Int?
    public init(id: String, label: String, klass: String, chance: Double, hit: Bool,
                index: Int? = nil, col: Int? = nil) {
        self.id = id; self.label = label; self.klass = klass
        self.chance = chance; self.hit = hit; self.index = index; self.col = col
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
    /// An item's %-chance roll was made — the structured HIT/MISS the UI
    /// renders as a roll indicator (v6.57). Emitted at roll time; on a hit the
    /// effect's own events follow.
    case rollResult(RollResult)
    /// Second Wind's save roll HIT in consent mode and the choice is parked
    /// (v6.56 sequencing): the killing card was drawn and is HELD OUT of the
    /// deck; the pile is untouched. The UI shows the drawn card and the dying
    /// moment FIRST, then asks save-or-die; `answerSecondWind` produces the
    /// `.secondWind` (accept) or `.pileKilled` + `.resolved` (decline) events.
    case secondWindOffer(index: Int, col: Int, guess: Guess, current: LiveCard, drawn: LiveCard, recycleCount: Int)
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
    /// Same Tell: the pile it read, and the next card's direction vs it.
    public var tellPile: Int?
    public var tellDirection: Guess?
    /// Club Oracle (v6.51): one tell per alive ♣-topped pile in the column —
    /// (pile, the next card's direction vs that pile's top). No random pick.
    public var tells: [(pile: Int, direction: Guess)]?
    /// Net coins this Base moved (for the UI float).
    public var coins: Double = 0
    /// EMPTY PURSE (v6.74): the purse size the activation counted with — the
    /// caller drains EXACTLY this from the campaign purse, so the spend can
    /// never disagree with the peek count.
    public var purseSpent: Int?
    /// SACRIFICE (v6.76): the purged top card's identity — the flow removes
    /// it from the campaign deck permanently (removeDeckCard).
    public var purgedCardId: Int?
    /// PURGE COUPON (v6.76): the store Purge price cut (and its floor) the
    /// flow applies via `CampaignState.addPurgeDiscount` — the engine never
    /// touches the campaign purse/pricing itself.
    public var purgePriceCut: Int?
    public var purgePriceFloor: Int?
    /// CLEANSE (v6.76): how many curses came off the column's top cards.
    public var cleansed: Int?
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
    /// RANK FLOOD (v6.76): the permanent rank rewrites, as (cardId, value) —
    /// same durable-write contract as a Base's `valueApplied`: the flow
    /// writes them onto the campaign cards.
    public var rankApplied: [(cardId: Int, value: Int)] = []

    public static func == (a: SamePowerResult, b: SamePowerResult) -> Bool {
        a.power == b.power && a.label == b.label && a.hub == b.hub && a.effect == b.effect
            && a.targets == b.targets && a.amount == b.amount
            && a.stickersApplied.map(\.cardId) == b.stickersApplied.map(\.cardId)
            && a.stickersApplied.map(\.typeId) == b.stickersApplied.map(\.typeId)
            && a.rankApplied.map(\.cardId) == b.rankApplied.map(\.cardId)
            && a.rankApplied.map(\.value) == b.rankApplied.map(\.value)
    }
}
