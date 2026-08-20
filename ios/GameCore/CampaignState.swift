import Foundation

/// CampaignState — the meta layer. It owns ONLY campaign-level data (which node
/// we're on, cross-deal totals, the persistent deck, coins, inventories) and
/// knows nothing about piles or rendering. Per-deal state lives in the
/// GameEngine and is thrown away each deal.
///
/// A campaign is a climb up a seeded node map across 3 stages; losing any deal
/// ends — and wipes — the whole campaign.
public final class CampaignState {
    // MARK: Dependencies
    let data: GameData
    let map: RunMap
    public let stats: Stats
    public let zenStats: ZenStats
    public let deckUnlocks: DeckUnlocks
    public let zenUnlocks: ZenUnlocks
    public let itemUnlocks: ItemUnlocks
    public let saveStore: SaveStore

    /// The map-generator version fresh runs stamp. Saves carry their own `genV`
    /// so a resumed v1/v2 campaign regenerates through its original path.
    public static let runGenVersion = 5   // v5: opening-row spread + variety (v4: pack-merge cap)
    /// The special sentinels a +1 node may lock instead of a real card. Nothing
    /// is minted into the base deck until the special is actually GRANTED.
    public static let specialJoker = -1
    public static let specialBlank = -2

    // MARK: Identity
    public internal(set) var deckId = "pink"
    public internal(set) var difficultyTier = "regular"

    // MARK: Run structure
    public internal(set) var phaseIndex = 0
    /// Base-deck ids in the accumulated deck (the player's DRAFT).
    public internal(set) var ownedIds: [Int] = []
    public internal(set) var runMap: RunMapGraph?
    /// Current node id, or nil = at the run start (below ♦ row 0).
    public internal(set) var nodePos: Int?
    public internal(set) var clearedNodes: [Int] = []
    /// MYSTERY node ids the player has arrived at (display-only).
    public internal(set) var revealedNodes: [Int] = []
    public internal(set) var mystMigrated = false
    public internal(set) var runSeed: UInt32 = 0
    private var pendingSeedOverride: UInt32?
    /// True while the run's seed was player-entered — checkpoints normally but
    /// banks NO progression.
    public internal(set) var exhibition = false
    /// SEED1 action stream position (player-choice randoms).
    public internal(set) var actionCounter = 0
    /// The generator version THIS run was built with. Fresh runs stamp the
    /// current version; a restored save replays the version it was built with.
    public internal(set) var savedGenVersion = CampaignState.runGenVersion
    /// The REAL deck size entering each stage, captured when the stage generates.
    public internal(set) var stageEntryDecks: [Int?] = []
    /// Single-card nodes' committed exact cards (shown == granted).
    public internal(set) var nodeCards: [Int: Int] = [:]
    /// Revealed +2 packs' committed pairs.
    public internal(set) var packCards: [Int: [Int]] = [:]

    // MARK: Deck
    public internal(set) var baseDeck: [CardSpec] = []
    public internal(set) var nextCardId = 52

    // MARK: Totals
    public internal(set) var currentStage = 1
    public internal(set) var currentRunIndex = 1
    public internal(set) var totalCorrectGuesses = 0
    public internal(set) var runsCompleted = 0
    public internal(set) var totalCardsFlipped = 0
    public internal(set) var totalCoinsEarned = 0
    public internal(set) var allGuessesCorrect = 0
    public internal(set) var allGuessesTotal = 0
    public internal(set) var coins = 0
    public internal(set) var playedCounted = false
    public internal(set) var runWonBanked = false
    public internal(set) var cardsFlippedBanked = 0
    public internal(set) var runScore = 0
    public internal(set) var scoreBanked = 0
    public internal(set) var endless = false
    public internal(set) var sameCharge = false

    // MARK: Inventories
    public internal(set) var stickerInventory: [String: Int] = [:]
    public internal(set) var pillarInventory: [String: Int] = [:]
    public internal(set) var baseInventory: [String: Int] = [:]
    public internal(set) var samePowerInventory: [String: Int] = [:]
    public internal(set) var columnPillars: [String?] = Array(repeating: nil, count: CampaignLayout.columnSlots)
    public internal(set) var columnBases: [String?] = Array(repeating: nil, count: CampaignLayout.columnSlots)
    public internal(set) var equippedSamePower: String?
    public internal(set) var storeOffer: StoreOffer?
    public internal(set) var removalSlotEnabled = true
    /// Removals bought this climb — each one lifts the next removal's price by
    /// `store.removal.priceStep`. Resets with the climb, not the shop visit.
    public internal(set) var removalsBought = 0
    /// THE OLD JOKER's purge bargain (see applyPurgeHalving): coins knocked off
    /// the slot's current price, and how much steeper each future step is.
    /// Both reset with the climb, like the ladder itself.
    public internal(set) var purgeDiscount = 0
    public internal(set) var purgeStepBonus = 0
    /// THE OLD JOKER's outstanding marker, in coins. 0 = nothing owed. While
    /// this is positive every mystery node carries a hidden chance he is
    /// waiting to collect instead of dealing.
    public internal(set) var jokerDebt = 0
    /// His comp: the NEXT store visit is on him. Cleared by the first refresh
    /// of that shelf (the gift is that shelf, not the whole visit) and by
    /// leaving the store.
    public internal(set) var freeShopPending = false
    /// He asked for drink money and is coming back about it. `jokerThirstCoins`
    /// is what you actually gave — 0 means you stiffed him, which he remembers.
    public internal(set) var jokerThirstPending = false
    public internal(set) var jokerThirstCoins = 0
    /// THE BEHEADED QUEEN's Restock: the next shop's FIRST refresh is free.
    /// Consumed when that shop opens (the boon is that visit's, used or not).
    public internal(set) var freeRerollPending = false
    /// Her Mulligan: the next deal's FIRST reshuffle is free. Consumed when
    /// that deal starts.
    public internal(set) var freeRedealPending = false
    /// The cast's next-shop price twist: "one" (her Fire Sale — everything
    /// costs 1) or "double" (the Two's Markup). `Pending` arms at the mystery
    /// node; it becomes `Active` when the next shop opens and a REFRESH (or
    /// the shop after) clears it.
    public internal(set) var storePriceModPending: String?
    public internal(set) var storePriceModActive: String?
    /// DEBUG ONLY: the Old Joker offer to force at the NEXT mystery node.
    /// Session state — deliberately not serialized, so it can never follow a
    /// save into a real run.
    public var debugForcedJokerKey: String?
    /// Set when an armed offer could not be built at a node — the flow reads
    /// it to say WHY nothing happened instead of leaving the player guessing.
    public var debugForcedJokerBlocked = false
    public internal(set) var packTray: [CardSpec] = []

    /// TEST/QA hook (like `deck._setNext`): pin the map-special roll so tests can
    /// exercise both the normal-card and the special contracts.
    /// nil = production rule; `true` Joker, `false` Blank, `.some(nil)` normal.
    public var mapSpecialRoll: (() -> Bool?)?

    // MARK: - Init

    public init(data: GameData = .shared, map: RunMap? = nil, store: KeyValueStore = MemoryStore()) {
        self.data = data
        self.map = map ?? RunMap(data: data)
        self.stats = Stats(store: store)
        self.zenStats = ZenStats(store: store, ids: DifficultyData.zenIds)
        self.deckUnlocks = DeckUnlocks(store: store)
        self.zenUnlocks = ZenUnlocks(store: store, ids: DifficultyData.zenIds)
        self.itemUnlocks = ItemUnlocks(store: store, data: data, stats: stats, zenStats: zenStats)
        self.saveStore = SaveStore(store: store)
        self.baseDeck = DeckManager.buildStandardDeck()
        self.stageEntryDecks = [self.map.config.startDeckSize, nil, nil]
    }

    // MARK: - Deck rules

    public func rules() -> DeckRules { data.meta.rules(deckId) }
    /// Shop price with the deck's multiplier applied (Mr. Smith pays 2×).
    public func shopPrice(_ p: Double) -> Double { (p * rules().priceMult).rounded() }
    public var stickersLocked: Bool { rules().noStickers }

    public func setDeck(_ id: String) { deckId = data.meta.deckRules[id] != nil ? id : "pink" }
    public func setTier(_ id: String) {
        difficultyTier = DifficultyData.tierIds.contains(id) ? id : "regular"
    }
    public func setSeedOverride(_ u32: UInt32?) { pendingSeedOverride = u32 }

    /// JOKER3 — the fixed-Joker scheme. It REPLACES the tier's random Joker
    /// rules for the deck/tier pairs difficulty.js lists.
    public func fixedJokerStages() -> [Int]? {
        data.difficulty.fixedJokerStages(deckId: deckId, tierId: difficultyTier)
    }
    public var fixedJokerScheme: Bool { fixedJokerStages() != nil }
    func runGenOpts() -> RunMap.GenOptions {
        RunMap.GenOptions(genVersion: savedGenVersion, postBossJokerStages: fixedJokerStages() ?? [])
    }
    /// The deck size a fresh run ENTERS with: the 13 start cards plus any
    /// starting Jokers.
    public func runStartSize(_ d: String, _ t: String) -> Int {
        map.config.startDeckSize + data.difficulty.startJokers(deckId: d, tierId: t)
    }

    var phaseSuits: [String] { map.config.phaseSuits }
    var startSuit: String { map.config.startSuit }
    var allSuits: [String] { DeckManager.suits.map(\.symbol) }

    /// THE CLIMB-FIXED VARIANT for a variant-rolling Same-Power: Burrow rolls
    /// a suit, Second Sight rolls red-or-black. A pure function of the run
    /// seed, so the roll "happens" the first time the item shows in a shop
    /// and then never changes for the climb — every appearance, the shelf,
    /// the detail sheet and the deal all agree. Nil for the fixed powers.
    public func samePowerVariant(_ id: String?) -> String? {
        guard let id else { return nil }
        var h: UInt32 = 0x9e37
        for b in id.utf8 { h = (h &* 31) &+ UInt32(b) }
        let rng = RNG(seed: runSeed &+ h)
        switch id {
        case "linkBury": return allSuits[rng.index(allSuits.count)]
        case "linkTell": return rng.next() < 0.5 ? "red" : "black"
        default: return nil
        }
    }

    /// RANK-VARIANT PILLARS (Underdog / Crowd Favorite): the rank locks the
    /// first time the pillar shows in a shop this climb, read from the deck
    /// AT THAT MOMENT (fewest / most held, seeded tiebreak), then never moves.
    public internal(set) var pillarRankVariants: [String: Int] = [:]

    /// Lock a rank variant for `def` if it rolls one and hasn't locked yet.
    func lockPillarRankVariant(_ def: ItemDef) {
        guard def.effect == "rankBury" || def.effect == "rankCoin",
              pillarRankVariants[def.id] == nil else { return }
        var counts: [Int: Int] = [:]
        for r in minRank...maxRank { counts[r] = 0 }
        for c in getRunDeck() where !c.joker && !c.blank { counts[c.currentRank, default: 0] += 1 }
        let pick = def.effect == "rankBury" ? counts.values.min() : counts.values.max()
        let tied = counts.filter { $0.value == pick }.keys.sorted()
        guard !tied.isEmpty else { return }
        var h: UInt32 = 0x51ab
        for b in def.id.utf8 { h = (h &* 31) &+ UInt32(b) }
        let rng = RNG(seed: runSeed &+ h)
        pillarRankVariants[def.id] = tied[rng.index(tied.count)]
    }

    /// An item's description with its climb variant substituted in —
    /// `{suit}` / `{color}` / `{rank}` templates come from items.js.
    /// Non-templated descriptions pass through untouched.
    public func itemDescription(_ def: ItemDef) -> String {
        var out = def.description
        if let v = samePowerVariant(def.id) {
            out = out.replacingOccurrences(of: "{suit}", with: v)
                     .replacingOccurrences(of: "{color}", with: v)
        }
        if let r = pillarRankVariants[def.id] {
            let label = DeckManager.ranks.first { $0.value == r }?.label ?? "\(r)"
            out = out.replacingOccurrences(of: "{rank}", with: label)
        } else if out.contains("{rank}") {
            // Not locked yet (unlock popup, pre-shelf display): say what the
            // roll WILL read instead of leaking the raw template (v6.58).
            let words = def.effect == "rankBury" ? "your deck's scarcest rank"
                                                 : "your deck's most common rank"
            out = out.replacingOccurrences(of: "{rank}", with: words)
        }
        return out
    }

    public func findById(_ id: Int) -> CardSpec? { baseDeck.first { $0.id == id } }
    private func index(of id: Int) -> Int? { baseDeck.firstIndex { $0.id == id } }
    func idsOfSuit(_ suit: String) -> [Int] { baseDeck.filter { $0.suit == suit }.map(\.id) }

    /// Clamped: endless phases read as ♠ for every suit-flavoured display.
    public func phaseSuit() -> String { phaseSuits[min(phaseIndex, phaseSuits.count - 1)] }

    /// How many campaign stages a run has (the web's `phasesTotal()`).
    public func phasesTotal() -> Int { phaseSuits.count }

    /// Suits currently in play (drives item suit-gating). Alt decks are NOT
    /// suit-segmented: all four suits are in play from the very start.
    public func suitsInPlay() -> [String] {
        if rules().altSuits { return [startSuit] + phaseSuits }
        return [startSuit] + Array(phaseSuits.prefix(phaseIndex + 1))
    }

    // MARK: - Seeded substreams

    func rrng(_ keys: RunKey...) -> RNG { runRng(seed: runSeed, keys) }
    /// The ACTION stream: one keyed stream per player-choice random.
    func actRng() -> RNG {
        let r = runRng(seed: runSeed, [.s("act"), .n(actionCounter)])
        actionCounter += 1
        return r
    }

    // MARK: - Card minting

    /// Mint a fresh DUPLICATE card of `suit` (random rank, no stickers/mods) and
    /// return its id. The accumulated deck is a GROWING draft: once a suit's 13
    /// unique cards are spoken for, a pack mints duplicates.
    @discardableResult
    func mintSuitCardId(_ suit: String, rank: Int?, rng: RNG) -> Int {
        let r = rank ?? (minRank + rng.index(maxRank - minRank + 1))
        let card = CardSpec(id: nextCardId, suit: suit, originalRank: r, currentRank: r)
        nextCardId += 1
        baseDeck.append(card)
        return card.id
    }

    /// Mint a JOKER persistent card into the base deck. Only called when a Joker
    /// is GRANTED. Blanks are never minted — they grant a removal, not a card.
    @discardableResult
    func mintJokerId() -> Int {
        let card = CardSpec.joker(id: nextCardId)
        nextCardId += 1
        baseDeck.append(card)
        return card.id
    }

    /// DEBUG: mint `n` fresh RANDOM cards (any of the four suits, any rank, no
    /// stickers) straight into the deck. Uses the same mint path as a pack, so
    /// the ids stay unique and the deck stays serialisable. Returns the new ids.
    @discardableResult
    public func debugAddRandomCards(_ n: Int) -> [Int] {
        guard n > 0 else { return [] }
        let rng = actRng()
        let suits = allSuits
        return (0..<n).map { _ in
            debugOwn(mintSuitCardId(suits[rng.index(suits.count)], rank: nil, rng: rng))
        }
    }

    /// DEBUG: mint ONE card of an exact suit and rank into the deck. Returns
    /// nil for a suit the deck character doesn't use or an out-of-range rank,
    /// so a bad pick fails loudly at the call site instead of minting a card
    /// the board can never deal.
    @discardableResult
    public func debugAddCard(suit: String, rank: Int) -> Int? {
        guard allSuits.contains(suit), rank >= minRank, rank <= maxRank else { return nil }
        return debugOwn(mintSuitCardId(suit, rank: rank, rng: actRng()))
    }

    /// Minting only puts a card in the base deck — OWNERSHIP is what makes it
    /// part of the run deck (`getRunDeck` filters `baseDeck` by `ownedIds`).
    /// A debug grant that skipped this looked like it worked, left the deck
    /// count unmoved, and never dealt the card.
    @discardableResult
    private func debugOwn(_ id: Int) -> Int {
        if !ownedIds.contains(id) { ownedIds.append(id) }
        return id
    }

    /// A transient display card for a locked-but-untaken special.
    public func specialCardFor(_ id: Int) -> CardSpec? {
        if id == Self.specialJoker { return CardSpec.joker(id: Self.specialJoker) }
        if id == Self.specialBlank { return CardSpec.blank(id: Self.specialBlank) }
        return nil
    }

    /// Apply a sticker to a CARD SPEC. Returns false (without attaching) if a
    /// rank sticker is at its boundary.
    @discardableResult
    func applyStickerToCard(_ card: inout CardSpec, _ typeId: String, rng: RNG, suits: [String]? = nil) -> Bool {
        let suitPool = suits ?? allSuits
        guard let t = data.stickerTypes.get(typeId) else { return false }
        guard CardRules.stickerEligible(card, typeId, data: data) else { return false }
        if t.kind == "rank" {
            let delta = t.int("rankDelta", 0)
            if delta > 0 && card.currentRank >= maxRank { return false }
            if delta < 0 && card.currentRank <= minRank { return false }
            let from = card.currentRank
            card.currentRank = max(minRank, min(maxRank, from + delta))
            card.modifications.append(CardModification(op: delta > 0 ? "increase" : "decrease",
                                                       from: .number(Double(from)), to: .number(Double(card.currentRank))))
        } else if t.behavior == "randomFixedValue" {
            let from = card.currentRank
            card.currentRank = minRank + rng.index(maxRank - minRank + 1)
            card.modifications.append(CardModification(op: "randomRank",
                                                       from: .number(Double(from)), to: .number(Double(card.currentRank))))
        } else if t.behavior == "changeSuitTo", let s = t.suit {
            let from = card.suit
            card.suit = s
            card.modifications.append(CardModification(op: "changeSuit", from: .string(from), to: .string(card.suit)))
        } else if t.behavior == "changeSuitRandom" {
            // Pick a random DIFFERENT suit from the allowed set.
            let others = suitPool.filter { $0 != card.suit }
            if !others.isEmpty {
                let from = card.suit
                card.suit = others[rng.index(others.count)]
                card.modifications.append(CardModification(op: "changeSuit", from: .string(from), to: .string(card.suit)))
            }
        }
        card.stickers.append(StickerRecord(type: typeId))
        return true
    }

    /// The grant pool for stickers — cursed never roll (mystery events only),
    /// locked items stay out until their threshold is met.
    public func grantableStickers() -> [ItemDef] {
        data.stickerTypes.grantableBase().filter(itemUnlocks.isUnlocked)
    }

    /// Does ANY card in the run deck accept this sticker right now?
    public func stickerHasTarget(_ typeId: String) -> Bool {
        getRunDeck().contains { canApplySticker($0, typeId) }
    }

    /// The grant pool narrowed to stickers the player could actually PLACE.
    /// Every grant path rolls from here: a sticker with no legal target used to
    /// be handed over anyway and then parked in an invisible inventory the
    /// player could never spend, so it was simply lost (v5.83).
    public func grantableStickersWithTarget() -> [ItemDef] {
        guard !rules().noStickers else { return [] }   // Lammy takes no stickers at all
        return grantableStickers().filter { stickerHasTarget($0.id) }
    }

    /// A freshly-minted NORMAL pack-odds card: a random suit from ALL FOUR
    /// (store cards/packs are deliberately UNGATED), then the shared sticker
    /// distribution, suit-restricted per sticker. Lammy mints none.
    /// `stickerOdds` overrides the pack table (the store's single-card slot
    /// rolls its own, cheaper distribution).
    public func genNormalCard(_ rng: RNG, stickerOdds: [[Double]]? = nil) -> CardSpec {
        let suits = allSuits
        let suit = suits[rng.index(suits.count)]
        let rank = minRank + rng.index(maxRank - minRank + 1)
        var card = CardSpec(id: nextCardId, suit: suit, originalRank: rank, currentRank: rank)
        nextCardId += 1
        let n = rules().noStickers ? 0
            : StoreRoll.stickerCount(rng.next(), odds: stickerOdds ?? data.items.packStickerOdds)
        // The eligible pool is computed ONCE, from the card as minted — a
        // suit-changing sticker applied in this loop must NOT re-narrow the pool
        // for the next roll (the web hoists it out of the loop for exactly this).
        let pool = grantableStickers().filter { CardRules.stickerEligible(card, $0.id, data: data) }
        for _ in 0..<n {
            guard let sid = StoreRoll.rollIds(pool, 1, rng, tierWeights: data.items.store.tierWeights).first else { continue }
            applyStickerToCard(&card, sid, rng: rng, suits: suits)
        }
        return card
    }

    /// A freshly-minted persistent JOKER card (store packs / store card slot).
    public func genJokerCard() -> CardSpec {
        let c = CardSpec.joker(id: nextCardId)
        nextCardId += 1
        return c
    }

    // MARK: - Jokers

    public func jokerCapFor() -> Int { data.difficulty.tier(difficultyTier).jokerCap }

    /// HELD-count logic: every Joker the player currently holds (deck + pack
    /// tray) PLUS the guaranteed map Joker while it still waits on its node,
    /// PLUS an unbought Joker on a store card slot — each is a visible promise.
    public func jokersHeld() -> Int {
        var n = 0
        for id in ownedIds where findById(id)?.joker == true { n += 1 }
        for (k, v) in nodeCards where v == Self.specialJoker && !clearedNodes.contains(k) { n += 1 }
        for c in packTray where c.joker { n += 1 }
        for s in storeOffer?.slots ?? [] where s?.kind == "card" && s?.card?.joker == true { n += 1 }
        return n
    }

    public func jokersAllowed() -> Bool {
        // JOKER3: random Joker sources are OFF entirely — the fixed post-boss
        // nodes are the run's ONLY Jokers.
        if fixedJokerScheme { return false }
        return jokersHeld() < jokerCapFor()
    }

    public func jokerBudget() -> (cap: Int, committed: Int, allowed: Bool) {
        (jokerCapFor(), jokersHeld(), jokersAllowed())
    }

    /// SPECIALS RATE — Joker + Blank each carry weight 0.5 against the FULL
    /// 52-card deck at weight 1 per card, NO MATTER how narrow the pool a normal
    /// pick actually draws from. P(special) = 1/53 per slot.
    static let specialRollSpace = 52.0 + 0.5 + 0.5
    static let specialChance = 1.0 / specialRollSpace

    /// Returns true (Joker) / false (Blank) / nil (normal card).
    /// `allowJoker: false` (map +1 nodes, pack slots) — random pickups NEVER
    /// roll a Joker; Blanks keep their half everywhere.
    func rollMapSpecial(_ rng: RNG, allowJoker: Bool = true) -> Bool? {
        if let hook = mapSpecialRoll { return hook() }
        if rng.next() < Self.specialChance {
            let joker = rng.next() < 0.5
            if !joker { return false }
            // JOKER CAP: while at the cap the joker half falls back to a NORMAL
            // card; removing a held Joker reopens availability on the next roll.
            return (allowJoker && jokersAllowed()) ? true : nil
        }
        return nil
    }

    /// GUARANTEED MAP JOKER: exactly ONE Joker placed as a VISIBLE standalone +1
    /// card node somewhere in stages 1-3. Idempotent.
    func ensureGuaranteedJoker() {
        if fixedJokerScheme { unveilJokerNodes(); return }
        let t = data.difficulty.tier(difficultyTier)
        guard let m = runMap, t.guaranteedMapJoker, jokerCapFor() >= 1 else { unveilJokerNodes(); return }
        if nodeCards.values.contains(Self.specialJoker) { unveilJokerNodes(); return }
        let pickups = m.nodes.filter { $0.type == "pickup" && ($0.phase ?? 0) < phaseSuits.count }
        if pickups.isEmpty { return }
        let rng = RNG(seed: runSeed ^ jokerPlacementSalt)
        let n = pickups[rng.index(pickups.count)]
        nodeCards[n.id] = Self.specialJoker
        unveilJokerNodes()
    }

    /// The guaranteed Joker is always face-up: strip the mystery flag from any
    /// node carrying the Joker sentinel (mystery re-rolls on regeneration).
    func unveilJokerNodes() {
        guard let m = runMap else { return }
        for (k, v) in nodeCards where v == Self.specialJoker {
            m.byId[k]?.mystery = false
        }
    }

    // MARK: - Drafting

    /// Cards that are SPOKEN FOR: every owned card + every card a +1 node has
    /// locked to display + every card a revealed +2 pack committed.
    func reservedSet(except nodeId: Int?) -> Set<Int> {
        var s = Set(ownedIds)
        for (k, v) in nodeCards where nodeId == nil || k != nodeId! { s.insert(v) }
        for (k, ids) in packCards {
            if let nodeId, k == nodeId { continue }
            for id in ids { s.insert(id) }
        }
        return s
    }

    /// Choose a card id to draft for a PACK. Prefers the current phase's suit;
    /// `mixed` (or an exhausted suit) lets it pull any card.
    func pickDraftId(mixed: Bool, rng: RNG) -> Int {
        let taken = reservedSet(except: nil)
        var pool = idsOfSuit(phaseSuit()).filter { !taken.contains($0) }
        if mixed || pool.isEmpty {
            // any-card fallback: never a Joker/Blank.
            let any = baseDeck.filter { !taken.contains($0.id) && !$0.joker && !$0.blank }.map(\.id)
            if !any.isEmpty { pool = any }
        }
        if pool.isEmpty { return mintSuitCardId(phaseSuit(), rank: nil, rng: rng) }
        return pool[rng.index(pool.count)]
    }

    /// Draft a card of EXACTLY `suit` for a PACK: prefer an unowned card already
    /// in the deck, else MINT a fresh duplicate. Never off-suit, never nil.
    func pickSuitDraftId(_ suit: String, rng: RNG) -> Int {
        let taken = reservedSet(except: nil)
        let pool = idsOfSuit(suit).filter { !taken.contains($0) }
        if pool.isEmpty { return mintSuitCardId(suit, rank: nil, rng: rng) }
        return pool[rng.index(pool.count)]
    }

    /// The suit a draft NODE pulls from — its own phase's suit, so a
    /// not-yet-reached node previews from the right pool.
    func suitForNode(_ node: MapNode?) -> String {
        guard let p = node?.phase, p < phaseSuits.count else { return phaseSuit() }
        return phaseSuits[p]
    }

    /// DETERMINISTIC roll for a specific +1 node, seeded by (runSeed, node.id)
    /// over the unclaimed pool, so each +1 node locks a DISTINCT card and the
    /// same node always rolls the same one.
    func draftIdForNode(_ node: MapNode) -> Int? {
        let rng = RNG(seed: nodeDraftSeed(seed: runSeed, nodeId: node.id))
        if let special = rollMapSpecial(rng, allowJoker: false) {   // +1 nodes: Blanks only
            return special ? Self.specialJoker : Self.specialBlank
        }
        let taken = reservedSet(except: node.id)
        // ENDLESS stages (and alt decks): +1 nodes grant ALL FOUR suits at random.
        let endlessNode = (node.phase ?? 0) >= phaseSuits.count || rules().altSuits
        var pool: [Int]
        if endlessNode {
            let suit = allSuits[rng.index(allSuits.count)]
            pool = idsOfSuit(suit).filter { !taken.contains($0) }
            if pool.isEmpty { pool = [mintSuitCardId(suit, rank: nil, rng: rng)] }
        } else {
            pool = idsOfSuit(suitForNode(node)).filter { !taken.contains($0) }
            if node.mixed == true {
                // explicit any-card node: never a Joker/Blank
                let any = baseDeck.filter { !taken.contains($0.id) && !$0.joker && !$0.blank }.map(\.id)
                if !any.isEmpty { pool = any }
                else if pool.isEmpty { return mintSuitCardId(suitForNode(node), rank: nil, rng: rng) }
            } else if pool.isEmpty {
                // A stage can carry MORE +1 nodes than its suit has unique cards —
                // MINT a duplicate of the node's suit so pickups never show off-suit.
                return mintSuitCardId(suitForNode(node), rank: nil, rng: rng)
            }
        }
        if pool.isEmpty { return nil }
        return pool[rng.index(pool.count)]
    }

    /// Resolve a node's optional `forceCard` (e.g. "K♦") to a base-deck id,
    /// minting a duplicate at that rank when every existing copy is claimed.
    func forcedCardId(_ node: MapNode) -> Int? {
        guard let label = node.forceCard?.trimmingCharacters(in: .whitespaces), !label.isEmpty else { return nil }
        let suitChar = String(label.suffix(1))
        let rankLabel = String(label.dropLast()).trimmingCharacters(in: .whitespaces)
        guard let rank = DeckManager.ranks.first(where: { $0.label == rankLabel }) else { return nil }
        let taken = reservedSet(except: node.id)
        if let match = baseDeck.first(where: { $0.suit == suitChar && $0.currentRank == rank.value && !taken.contains($0.id) }) {
            return match.id
        }
        // The author's pin is the source of truth — MINT a duplicate at the exact
        // rank (idempotent through commitNodeCard).
        return mintSuitCardId(suitChar, rank: rank.value, rng: RNG(seed: runSeed))
    }

    /// The card a +1 node is locked to (assigns + caches it on first call).
    @discardableResult
    public func commitNodeCard(_ node: MapNode?) -> Int? {
        guard let node else { return nil }
        if nodeCards[node.id] == nil {
            // JOKER3: a fixed post-boss corridor node ALWAYS locks the Joker
            // sentinel — no roll, no cap check (the node IS the guarantee).
            let id: Int? = node.jokerNode ? Self.specialJoker : (forcedCardId(node) ?? draftIdForNode(node))
            guard let id else { return nil }
            nodeCards[node.id] = id
        }
        return nodeCards[node.id]
    }

    /// v6.57 DEBUG toggle (the debug panel's "1-SUIT PACKS" row): while on,
    /// EVERY pack grants cards of ONE seeded suit per node and the map badge
    /// shows that suit. Persisted as a `ninelives.pref.*` flag — dev-only,
    /// reachable only with debug access; a run without the pref rolls exactly
    /// as before.
    public func debugSingleSuitPacksOn() -> Bool {
        saveStore.pref("debugSingleSuitPacks") == "1"
    }
    public func setDebugSingleSuitPacks(_ on: Bool) {
        saveStore.setPref("debugSingleSuitPacks", on ? "1" : "0")
    }

    /// The ONE suit a pack node's slots all draw from while the debug toggle
    /// is on — its own keyed substream (SEED1), so the roll is stable per node
    /// for the whole run and the map badge and the grant can never disagree.
    public func debugPackSuit(for node: MapNode) -> String {
        let rng = rrng(.s("debugpacksuit"), .n(node.id))
        return allSuits[rng.index(allSuits.count)]
    }

    /// v6.61 — the suits ACTUALLY present in this pack node's contents. The
    /// v6.57 version returned the draw POOL (all four suits for endless/alt
    /// packs), so every such badge showed ♥♦♣♠ whatever the pack held. The
    /// contents are seeded per node, so the real set is knowable before the
    /// player arrives: replay the resolution stream's draws — per slot,
    /// `packSlotSuit`'s roll then EXACTLY one card-pick draw (pickSuitDraftId
    /// spends one `index` whether it drafts from the pool or mints). WHICH
    /// card that draw lands on varies with the collection; the suit sequence
    /// never does, so the badge cannot drift from what `resolvePack` deals.
    /// Revealed +2 packs read their committed pair (a Blank contributes no
    /// suit — it grants a removal, not a card). Deduped, fixed suit order:
    /// the player learns WHICH suits are present, never how many of each.
    public func packSuits(for node: MapNode) -> [String] {
        var suits: [String]
        if node.addOf == 2, let pair = commitPackCards(node) {
            suits = pair.compactMap { id in
                id == Self.specialBlank ? nil : (specialCardFor(id) ?? findById(id))?.suit
            }
        } else {
            let rng = rrng(.s("pack"), .n(node.id))
            suits = (0..<node.addOf).map { _ in
                let s = packSlotSuit(node, rng: rng)
                _ = rng.next()              // pickSuitDraftId's one card draw
                return s
            }
        }
        return allSuits.filter { suits.contains($0) }
    }

    /// The suit ONE pack slot draws from — the grant rule `packSuits(for:)`
    /// describes. Flag-off draws are byte-identical to before v6.57.
    func packSlotSuit(_ node: MapNode, rng: RNG) -> String {
        if debugSingleSuitPacksOn() { return debugPackSuit(for: node) }
        let endlessNode = node.suit == "★" || (node.phase ?? 0) >= phaseSuits.count || rules().altSuits
        return endlessNode ? allSuits[rng.index(allSuits.count)]
            : ((node.suit != nil && node.suit != "★") ? node.suit! : suitForNode(node))
    }

    /// PACK2 — DETERMINISTIC roll for ONE slot of a revealed +2 pack.
    func packSlotIdFor(_ node: MapNode, slot: Int) -> Int {
        let rng = RNG(seed: packSlotSeed(seed: runSeed, nodeId: node.id, slot: slot))
        let special = rollMapSpecial(rng, allowJoker: false)
        // Only a Blank may lock (a `true` can only come from the pinned TEST hook).
        if special == false { return Self.specialBlank }
        let taken = reservedSet(except: nil)   // owned + all locks incl. this pack's earlier slot
        let suit = packSlotSuit(node, rng: rng)
        let pool = idsOfSuit(suit).filter { !taken.contains($0) }
        if pool.isEmpty { return mintSuitCardId(suit, rank: nil, rng: rng) }
        return pool[rng.index(pool.count)]
    }

    /// The two exact cards a REVEALED +2 pack is locked to (slot 1's roll sees
    /// slot 0 through reservedSet since the partial array is stored live).
    @discardableResult
    public func commitPackCards(_ node: MapNode?) -> [Int]? {
        guard let node else { return nil }
        if packCards[node.id] == nil {
            packCards[node.id] = []
            for slot in 0..<2 {
                packCards[node.id]!.append(packSlotIdFor(node, slot: slot))
            }
        }
        return packCards[node.id]
    }

    /// Lock a card onto EVERY +1 node up front (at map generation). Forced-card
    /// nodes claim first, then the rest roll distinct cards in id order.
    func lockAllPickupCards() {
        guard let m = runMap else { return }
        let pickups = m.nodes.filter { $0.type == "pickup" }
            .stableSorted { a, b in
                let ka = a.forceCard != nil ? 0 : 1, kb = b.forceCard != nil ? 0 : 1
                return ka != kb ? ka < kb : a.id < b.id
            }
        for n in pickups { commitNodeCard(n) }
        // Every REVEALED +2 pack commits its exact pair right after the pickups.
        let packs = m.nodes.filter { $0.type == "pack" && $0.packCount == 2 && !clearedNodes.contains($0.id) }
            .stableSorted { $0.id < $1.id }
        for n in packs { commitPackCards(n) }
        unveilJokerNodes()
    }

    // MARK: - Map generation

    func genRunMap() {
        map.setDifficultyTier(difficultyTier)   // bands follow this campaign's tier
        // THE WHOLE RUN generates up front (all 3 stages, rendered from the
        // start). Later stages use PREDICTED entry decks — entry + the average
        // route collection per stage — and the map stays FIXED for the run.
        let entry0 = ownedIds.isEmpty ? runStartSize(deckId, difficultyTier) : ownedIds.count
        let prc = map.config.predictedRouteCards
        stageEntryDecks = [entry0, entry0 + prc, entry0 + 2 * prc]
        runMap = map.generateRun(seed: runSeed, entryDecks: stageEntryDecks, opts: runGenOpts())
        nodePos = nil
        clearedNodes = []
        revealedNodes = []
        nodeCards = [:]
        packCards = [:]
        mystMigrated = false
        // Drop UNOWNED Jokers left over from an earlier run (a granted Joker is
        // minted into baseDeck; a new run resets ownedIds, so a stale one is
        // unreachable junk). Blanks never enter baseDeck at all.
        let own = Set(ownedIds)
        baseDeck = baseDeck.filter { !($0.joker || $0.blank) || own.contains($0.id) }
        lockAllPickupCards()
        ensureGuaranteedJoker()   // cap ≥ 1 tiers always meet one standalone map Joker
    }

    /// Extend the map by one endless stage above the current top.
    func extendEndless() {
        stageEntryDecks.append(ownedIds.count)
        map.setDifficultyTier(difficultyTier)
        runMap = map.generateRun(seed: runSeed, entryDecks: stageEntryDecks, opts: runGenOpts())
        lockAllPickupCards()
        ensureGuaranteedJoker()
    }

    /// Start a fresh run: the deck's 13 starting cards, phase 0, a new map.
    public func startNewRun() {
        phaseIndex = 0
        removalsBought = 0   // the removal price ladder is per climb
        purgeDiscount = 0
        purgeStepBonus = 0
        jokerDebt = 0        // …and no debt follows you into a new climb
        freeShopPending = false
        jokerThirstPending = false
        jokerThirstCoins = 0
        // SEED1 — the run's seed is established FIRST, before ANY start roll.
        let entered = pendingSeedOverride
        pendingSeedOverride = nil   // one-shot
        exhibition = entered != nil
        runSeed = entered ?? RNG.generateSeed()
        savedGenVersion = Self.runGenVersion   // fresh seed → current generator
        let startRng = rrng(.s("start"))
        if rules().altSuits {
            // One card of EACH RANK, suits spread EVENLY: 13 ranks over 4 suits
            // is 4/3/3/3, so the hand always shows every suit instead of
            // whatever a per-rank coin flip happened to produce. Both the suit
            // that gets the extra card and the rank each suit lands on are
            // seeded — same seed, same hand.
            var bag: [String] = []
            let suits = DeckManager.suits.map(\.symbol)
            let extra = startRng.index(suits.count)
            for (i, su) in suits.enumerated() {
                for _ in 0..<(3 + (i == extra ? 1 : 0)) { bag.append(su) }
            }
            var i = bag.count - 1
            while i > 0 {                      // seeded Fisher-Yates
                let j = startRng.index(i + 1)
                bag.swapAt(i, j)
                i -= 1
            }
            ownedIds = DeckManager.ranks.enumerated().map { idx, r in
                let four = baseDeck.filter { !$0.joker && !$0.blank && $0.originalRank == r.value }
                let want = four.filter { $0.suit == bag[safe: idx] }
                let pool = want.isEmpty ? four : want   // defensive: never empty
                return pool[startRng.index(pool.count)].id
            }
        } else {
            ownedIds = idsOfSuit(startSuit)   // the 13 hearts
        }
        // STARTING JOKERS: minted + owned BEFORE the map generates, so the run's
        // entry deck size counts them.
        let startJokers = data.difficulty.startJokers(deckId: deckId, tierId: difficultyTier)
        for _ in 0..<startJokers { ownedIds.append(mintJokerId()) }
        genRunMap()
        if rules().startStickers {
            // One random sticker per starting card, drawn ONLY from the stickers
            // that card may take.
            for id in ownedIds {
                guard let i = index(of: id) else { continue }
                baseDeck[i].stickers = []   // idempotent: a re-rolled start never stacks
                let card = baseDeck[i]
                let elig = grantableStickers().filter { t in
                    guard CardRules.stickerEligible(card, t.id, data: data) else { return false }
                    guard t.kind == "rank" else { return true }
                    return t.num("rankDelta", 0) > 0 ? card.currentRank < maxRank : card.currentRank > minRank
                }
                if elig.isEmpty { continue }
                let t = elig[startRng.index(elig.count)]
                applyStickerToCard(&baseDeck[i], t.id, rng: startRng)
            }
        }
        if rules().preEquip {
            // 3 random DISTINCT Pillars + 3 random distinct Bases straight into
            // the six column slots. The sticker-centric Bases are excluded —
            // under noStickers they could never do anything.
            func roll3(_ ids: [String]) -> [String?] {
                var pool = ids
                var i = pool.count - 1
                while i > 0 {
                    let j = startRng.index(i + 1)
                    pool.swapAt(i, j)
                    i -= 1
                }
                return (0..<CampaignLayout.columnSlots).map { $0 < pool.count ? pool[$0] : nil }
            }
            columnPillars = roll3(data.pillarTypes.all().filter(itemUnlocks.isUnlocked).map(\.id))
            columnBases = roll3(data.baseTypes.all()
                .filter { itemUnlocks.isUnlocked($0) && $0.effect != "randomSticker" && $0.effect != "stickerHarvest" }
                .map(\.id))
        }
    }

    // MARK: - Map traversal

    public func getNode(_ id: Int) -> MapNode? { runMap?.byId[id] }
    public func currentNode() -> MapNode? { nodePos.flatMap { runMap?.byId[$0] } }

    /// The nodes the player may step onto next: the map's openings at the run
    /// start, else the current node's out-edges (minus anything already cleared).
    public func legalNextNodes() -> [MapNode] {
        guard let m = runMap else { return [] }
        guard let pos = nodePos else { return m.row0.compactMap { m.byId[$0] } }
        guard let n = m.byId[pos] else { return [] }
        return n.next.compactMap { m.byId[$0] }
    }

    /// Move to `id`. Normally the node must be a LEGAL NEXT step — that rule is
    /// what stops a player wandering the map. `teleport: true` is the one
    /// sanctioned bypass (THE OLD JOKER's ride, which is sold precisely as
    /// skipping several stops); it still refuses an unknown node.
    ///
    /// Without this the ride quietly did nothing: `travel` called moveToNode,
    /// the adjacency check rejected a destination several rows up, and the
    /// whole animation bailed on the guard.
    @discardableResult
    public func moveToNode(_ id: Int, teleport: Bool = false) -> Bool {
        if teleport {
            guard runMap?.byId[id] != nil else { return false }
        } else {
            guard legalNextNodes().contains(where: { $0.id == id }) else { return false }
        }
        nodePos = id
        if let n = runMap?.byId[id] {
            phaseIndex = n.phase ?? phaseIndex
            if n.mystery && !revealedNodes.contains(id) { revealedNodes.append(id) }
        }
        return true
    }

    @discardableResult
    public func markNodeCleared(_ id: Int) -> Bool {
        guard !clearedNodes.contains(id) else { return false }
        clearedNodes.append(id)
        // ENDLESS: the TOP endless stage's boss falling generates the next
        // stage — lazily, from the REAL deck size at that moment (the web's
        // grow-as-you-go rule above home, index.html:15861-15867). Without
        // this the climb dead-ends after the first endless stage.
        if endless, let m = runMap, m.phases.count > phaseSuits.count,
           let top = m.phases.last, top.phase >= phaseSuits.count,
           (top.bossIds.isEmpty ? [top.bossId] : top.bossIds).contains(id) {
            extendEndless()
        }
        return true
    }
    public func nodeCleared(_ id: Int) -> Bool { clearedNodes.contains(id) }
    public func nodeHidden(_ id: Int) -> Bool {
        guard let n = runMap?.byId[id] else { return false }
        return n.mystery && !revealedNodes.contains(id) && !clearedNodes.contains(id)
    }
    public func revealNode(_ id: Int) { if !revealedNodes.contains(id) { revealedNodes.append(id) } }
    public func isNodeCleared(_ id: Int) -> Bool { clearedNodes.contains(id) }

    /// DEBUG ONLY (the panel's MAP JUMP) — teleport so node `id` becomes the
    /// next PLAYABLE node: every node on a lower global row is marked cleared,
    /// the position sits on a direct predecessor (nil for an opening-row node),
    /// and the phase syncs to the target. Simplification vs the web's
    /// `debugJumpToNode` (index.html:15894): NO catch-up draft cards are
    /// granted for skipped rows — the deck stays as-is. Fine for playtesting
    /// map/item states; the jumped-to stage may be harder than a real route's.

    /// DEBUG: retype a node as a MYSTERY so an armed Old Joker offer has
    /// somewhere to land. Marks it revealed-as-mystery, never concealed, so
    /// walking onto it fires the "?" flow immediately.
    @discardableResult
    public func debugSetNodeMystery(_ id: Int) -> Bool {
        guard let m = runMap, let n = m.byId[id], n.type != "boss", n.type != "home" else { return false }
        n.type = "mystery"
        n.mystery = true
        if !revealedNodes.contains(id) { revealedNodes.append(id) }
        return true
    }

    @discardableResult
    public func debugJumpToNode(_ id: Int) -> Bool {
        guard let m = runMap, let target = m.byId[id] else { return false }
        for n in m.nodes where n.row < target.row {
            if !clearedNodes.contains(n.id) { clearedNodes.append(n.id) }
        }
        nodePos = m.nodes.first { $0.next.contains(id) }?.id
        phaseIndex = target.phase ?? phaseIndex
        revealNode(id)
        return true
    }

    public func isRunBoss(_ id: Int) -> Bool {
        guard let m = runMap else { return false }
        if let ids = m.runBossIds { return ids.contains(id) }
        return id == m.runBossId
    }
    public func isRunComplete() -> Bool {
        guard let m = runMap, let ids = m.runBossIds else { return phaseIndex >= phaseSuits.count }
        return phaseIndex >= phaseSuits.count || ids.contains { clearedNodes.contains($0) }
    }

    /// The card a node grants (or shows), resolving the special sentinels.
    public func nodeCard(_ node: MapNode?) -> CardSpec? {
        guard let node, let id = nodeCards[node.id] else { return nil }
        return specialCardFor(id) ?? findById(id)
    }
    public func previewPickupCard(_ node: MapNode?) -> CardSpec? {
        guard let id = commitNodeCard(node) else { return nil }
        return specialCardFor(id) ?? findById(id)
    }
    public func packNodeCards(_ node: MapNode?) -> [CardSpec] {
        guard let node, let ids = packCards[node.id] else { return [] }
        return ids.compactMap { specialCardFor($0) ?? findById($0) }
    }

    /// Take a +1 pickup node's card into the deck. A Joker sentinel mints a real
    /// Joker; a Blank sentinel grants a removal instead of a card.
    @discardableResult
    public func resolvePickup(_ node: MapNode?) -> CardSpec? {
        guard let node, let id = commitNodeCard(node) else { return nil }
        if id == Self.specialBlank { markNodeCleared(node.id); return CardSpec.blank(id: Self.specialBlank) }
        let realId = id == Self.specialJoker ? mintJokerId() : id
        if id == Self.specialJoker { nodeCards[node.id] = realId }
        if !ownedIds.contains(realId) { ownedIds.append(realId) }
        markNodeCleared(node.id)
        return findById(realId)
    }

    /// Grant a pack node's cards. A revealed +2 pack grants exactly the pair it
    /// committed; larger packs roll at resolution.
    @discardableResult
    public func resolvePack(_ node: MapNode?) -> [CardSpec] {
        guard let node else { return [] }
        let count = node.addOf
        var granted: [Int] = []
        if count == 2, let pair = commitPackCards(node) {
            granted = pair
        } else {
            let rng = rrng(.s("pack"), .n(node.id))
            for _ in 0..<count {
                let suit = packSlotSuit(node, rng: rng)
                let id = pickSuitDraftId(suit, rng: rng)
                granted.append(id)
                // Reserve IN THE LOOP (the web pushes ownedIds per slot) —
                // without this the next slot's pickSuitDraftId re-rolls the
                // same unowned card and a +N pack grants N identical cards.
                if !ownedIds.contains(id) { ownedIds.append(id) }
            }
        }
        var out: [CardSpec] = []
        for id in granted {
            // A Blank grants a removal, not a card (web index.html:28450): it
            // stays in the returned list so the flow can show it and open one
            // removal picker per Blank — it NEVER joins the deck.
            if id == Self.specialBlank { out.append(CardSpec.blank(id: Self.specialBlank)); continue }
            let realId = id == Self.specialJoker ? mintJokerId() : id
            if !ownedIds.contains(realId) { ownedIds.append(realId) }
            if let c = findById(realId) { out.append(c) }
        }
        markNodeCleared(node.id)
        return out
    }

    /// BOUNCER: does an equipped ward turn this node's Two away? Seeded per
    /// (runSeed, nodeId) on its own salt — a reload replays the verdict.
    public func twoWardNegates(_ nodeId: Int) -> Bool {
        guard let def = columnPillars.compactMap({ $0.flatMap { data.pillarTypes.get($0) } })
                .first(where: { $0.effect == "twoWard" }) else { return false }
        let rng = RNG(seed: mysterySeed(seed: runSeed, nodeId: nodeId, salt: twoWardSalt))
        return rng.next() < def.num("chance", 0.3)
    }

    /// The seeded outcome KEY for a mystery node — PURE (no state change). Same
    /// (runSeed, nodeId) → same key, always. Weights read live from items.js.
    ///
    /// CHARACTER-FIRST: the Old Joker's takeover already rolled (and missed)
    /// on his own stream by the time this runs, so the first draw here splits
    /// the node between THE BEHEADED QUEEN and JUST A TWO by their
    /// characterWeights shares; the second draw picks the action WITHIN the
    /// winner's pool by the ordinary outcome weights.
    public func rollMysteryEvent(_ nodeId: Int) -> String {
        let rng = RNG(seed: mysterySeed(seed: runSeed, nodeId: nodeId, salt: mysteryKeySalt))
        let cw = data.items.mystery.characterWeights
        let qw = max(0, cw["queen"] ?? 0), tw = max(0, cw["two"] ?? 0)
        let queenWins = qw + tw <= 0 || rng.next() < qw / (qw + tw)
        let keys = queenWins ? MysteryConfig.queenKeys : MysteryConfig.twoKeys
        let w = data.items.mystery.weights
        let totalRaw = keys.reduce(0.0) { $0 + (w[$1] ?? 0) }
        let total = totalRaw == 0 ? 1 : totalRaw
        var r = rng.next() * total
        var chosen = keys[keys.count - 1]
        for k in keys {
            r -= (w[k] ?? 0)
            if r < 0 { chosen = k; break }
        }
        return chosen
    }

    // MARK: - Deck reads

    public func getDeck() -> [CardSpec] { baseDeck }
    public func deckSize() -> Int { ownedIds.count }
    /// The deck dealt THIS deal: the player's ACCUMULATED DRAFT (every owned
    /// card), in BASE-DECK order — not the order ids were acquired in. The deal
    /// shuffles it seeded, so this order is part of seed compatibility.
    public func getRunDeck() -> [CardSpec] {
        let own = Set(ownedIds)
        return baseDeck.filter { own.contains($0.id) }
    }

    public func composition() -> [Int: Int] {
        var out: [Int: Int] = [:]
        for c in getRunDeck() where !c.joker && !c.blank { out[c.currentRank, default: 0] += 1 }
        return out
    }
    public func suitComposition() -> [String: Int] {
        var out = ["♥": 0, "♦": 0, "♣": 0, "♠": 0]
        for c in getRunDeck() where out[c.suit] != nil { out[c.suit]! += 1 }
        return out
    }
    public func jokerCount() -> Int { getRunDeck().filter(\.joker).count }

    // MARK: - Card edits

    @discardableResult
    public func increaseCard(_ id: Int) -> Bool {
        guard let i = index(of: id), !baseDeck[i].joker, !baseDeck[i].blank,
              baseDeck[i].currentRank < maxRank else { return false }
        let from = baseDeck[i].currentRank
        baseDeck[i].currentRank = from + 1
        baseDeck[i].modifications.append(CardModification(op: "increase", from: .number(Double(from)),
                                                          to: .number(Double(baseDeck[i].currentRank))))
        return true
    }
    @discardableResult
    public func decreaseCard(_ id: Int) -> Bool {
        guard let i = index(of: id), !baseDeck[i].joker, !baseDeck[i].blank,
              baseDeck[i].currentRank > minRank else { return false }
        let from = baseDeck[i].currentRank
        baseDeck[i].currentRank = from - 1
        baseDeck[i].modifications.append(CardModification(op: "decrease", from: .number(Double(from)),
                                                          to: .number(Double(baseDeck[i].currentRank))))
        return true
    }
    @discardableResult
    public func setCardSuit(_ id: Int, to suit: String) -> Bool {
        guard let i = index(of: id), !baseDeck[i].joker, !baseDeck[i].blank,
              allSuits.contains(suit), baseDeck[i].suit != suit else { return false }
        let from = baseDeck[i].suit
        baseDeck[i].suit = suit
        baseDeck[i].modifications.append(CardModification(op: "changeSuit", from: .string(from), to: .string(suit)))
        return true
    }
    /// Permanently remove a card from the accumulated deck — and from the
    /// CARD UNIVERSE. `baseDeck` doubles as the draft pool (+1 nodes and
    /// packs offer unowned universe cards), so dropping only the OWNED id
    /// quietly returned every purged card — stickers and all — to the very
    /// next card node (v6.49 bugfix). Deleting the spec is what
    /// `replaceDeckCard` already did; every removal path (purge, store
    /// removal, Old Joker cut, joker strip) funnels through here.
    @discardableResult
    public func removeDeckCard(_ id: Int) -> Bool {
        guard let i = ownedIds.firstIndex(of: id) else { return false }
        ownedIds.remove(at: i)
        if let bi = baseDeck.firstIndex(where: { $0.id == id }) { baseDeck.remove(at: bi) }
        if !isExhibition() { stats.bump("removalsUsed") }
        return true
    }

    // MARK: - Coins + score

    public func getCoins() -> Int { coins }
    @discardableResult
    public func addCoins(_ n: Int) -> Int { coins += n; return coins }
    /// Coins earned by play (feeds the lifetime tally); `addCoins` is the raw mover.
    @discardableResult
    public func earnCoins(_ n: Int) -> Int { coins += n; totalCoinsEarned += n; return coins }
    /// Coins EARNED so far this climb — the figure `bestCoinsInClimb` records.
    /// Distinct from the purse, which shrinks every time you shop.
    public func coinsEarnedThisClimb() -> Int { totalCoinsEarned }
    @discardableResult
    public func spendCoins(_ n: Int) -> Bool {
        guard coins >= n else { return false }
        coins -= n
        return true
    }

    @discardableResult
    public func addRunScore(_ n: Int) -> Int { runScore += max(0, n); return runScore }
    public func getRunScore() -> Int { runScore }
    /// Bank the ♠-boss win: an endless death can neither undo nor duplicate it.
    public func markRunWon() {
        runWonBanked = true
        cardsFlippedBanked = totalCardsFlipped
        scoreBanked = runScore
    }
    // ONE SCORE (v6.47): a run's score is `runScore`, one continuous total —
    // endless simply keeps accruing into it. The old campaign/endless slicers
    // (frozen-at-boss / after-the-bank) are gone so nothing can display or
    // record a partial figure again; `getRunScore()` is THE accessor. The
    // bank itself stays (`markRunWon`) — phase logic and the cards-flipped
    // bookkeeping still pivot on it.
    public func unbankedCardsFlipped() -> Int { max(0, totalCardsFlipped - cardsFlippedBanked) }
    public func addCardsFlipped(_ n: Int) { totalCardsFlipped += n }
    public func addRunGuesses(correct: Int, total: Int) {
        allGuessesCorrect += correct
        allGuessesTotal += total
    }
    public func markPlayed() { playedCounted = true }
    public func isPlayedCounted() -> Bool { playedCounted }

    public func isEndless() -> Bool { endless }
    /// Enter endless mode: home is cleared, and the FIRST endless stage
    /// generates right now from the REAL deck size. Every later stage
    /// generates as its predecessor's boss falls (markNodeCleared).
    public func startEndless() {
        guard !endless else { return }
        endless = true
        if let homeId = runMap?.homeId, !clearedNodes.contains(homeId) {
            clearedNodes.append(homeId)
        }
        extendEndless()
    }
    public func endlessStagesReached() -> Int { max(0, stageEntryDecks.count - phaseSuits.count) }

    public func getSameCharge() -> Bool { sameCharge }
    public func setSameCharge(_ v: Bool) { sameCharge = v }

    // MARK: - Inventories

    // Each price accessor honours the Old Joker's comp itself, rather than only
    // the shelf label doing so: every buy path charges through THESE, so a
    // comp applied at the label alone would show 0 and still take the coins.
    // The cast's next-shop price twist rides the same chokepoint: the Queen's
    // Fire Sale flattens every ITEM to 1 coin, the Two's Markup doubles it.
    // Purge stays a service, not an item — removalPrice is untouched.
    func storeModPrice(_ p: Double) -> Double {
        switch storePriceModActive {
        case "one": return min(p, 1)
        case "double": return p * 2
        default: return p
        }
    }
    public func priceOf(_ typeId: String) -> Double {
        guard data.stickerTypes.get(typeId) != nil else { return .infinity }
        if freeShopCovers("sticker") { return 0 }
        return data.stickerTypes.get(typeId).map { storeModPrice(shopPrice($0.price)) } ?? .infinity
    }
    public func priceOfPillar(_ typeId: String) -> Double {
        guard data.pillarTypes.get(typeId) != nil else { return .infinity }
        if freeShopCovers("pillar") { return 0 }
        return data.pillarTypes.get(typeId).map { storeModPrice(shopPrice($0.price)) } ?? .infinity
    }
    public func priceOfBase(_ typeId: String) -> Double {
        guard data.baseTypes.get(typeId) != nil else { return .infinity }
        if freeShopCovers("base") { return 0 }
        return data.baseTypes.get(typeId).map { storeModPrice(shopPrice($0.price)) } ?? .infinity
    }
    public func priceOfSamePower(_ typeId: String) -> Double {
        guard data.samePowerTypes.get(typeId) != nil else { return .infinity }
        if freeShopCovers("samepower") { return 0 }
        return data.samePowerTypes.get(typeId).map { storeModPrice(shopPrice($0.price)) } ?? .infinity
    }
    public func priceOfPack(_ packId: String) -> Double {
        guard data.packTypes.get(packId) != nil else { return .infinity }
        if freeShopCovers("pack") { return 0 }
        return data.packTypes.get(packId).map { storeModPrice(shopPrice($0.price)) } ?? .infinity
    }
    /// The removal slot climbs: base + `priceStep` per removal already bought
    /// this climb. The deck price multiplier applies on top, as for every item.
    public func removalPrice() -> Double {
        let cfg = data.items.store.removal
        // BULK RATE: each equipped copy flattens the ladder's step by its
        // value (never below 0). Derived live from the loadout + counters,
        // so save/restore needs nothing extra and unequipping restores the
        // full climb instantly.
        let stepCut = equippedPillarDefs().filter { $0.effect == "purgeStepDiscount" }
            .reduce(0.0) { $0 + $1.value }
        let step = max(0, cfg.priceStep + Double(purgeStepBonus) - stepCut)
        let raw = cfg.price + step * Double(removalsBought)
        return max(1, (shopPrice(raw) - Double(purgeDiscount)).rounded())
    }

    /// The registry defs of every equipped Pillar (meta-effect checks).
    func equippedPillarDefs() -> [ItemDef] {
        columnPillars.compactMap { $0.flatMap { data.pillarTypes.get($0) } }
    }

    /// The store's SELL value for an item — items.js `store.sell` by tier
    /// (v6.50: the UI used to hardcode these; the data file is the source).
    public func sellValue(_ def: ItemDef?) -> Int {
        let table = data.items.store.raw["sell"]?.asObject ?? [:]
        let fallback: [String: Double] = ["common": 1, "uncommon": 2, "rare": 3]
        let tier = def?.tier ?? "common"
        return Int(table[tier]?.asNumber ?? fallback[tier] ?? 1)
    }

    /// RARE HUNTER: the store's tier weights with the rare tier multiplied
    /// by each equipped copy's value. Class weights are untouched — only the
    /// rarity mix WITHIN each class shifts.
    func effectiveTierWeights() -> [String: Double] {
        var w = data.items.store.tierWeights
        for def in equippedPillarDefs() where def.effect == "rareHunter" {
            w["rare"] = (w["rare"] ?? 1) * max(1, def.value)
        }
        return w
    }

    /// THE OLD JOKER's purge bargain: halve what the slot costs RIGHT NOW, and
    /// make every future step steeper for the rest of the climb. An odd price
    /// rounds UP (9 → 5) — the offer quotes the ceiling, so the charge must
    /// match it (v6.62).
    @discardableResult
    public func applyPurgeHalving(stepIncrease: Int) -> (from: Int, to: Int) {
        let before = Int(removalPrice())
        let target = max(1, (before + 1) / 2)
        // Steepen FIRST, then discount down to the promised number — otherwise
        // the steeper step immediately claws back part of the halving and the
        // player is quoted a price they never actually see.
        purgeStepBonus += max(0, stepIncrease)
        purgeDiscount += max(0, Int(removalPrice()) - target)
        return (before, Int(removalPrice()))
    }

    public func inventoryCount(_ typeId: String) -> Int { stickerInventory[typeId] ?? 0 }
    @discardableResult
    /// DEBUG: arm the next mystery node with a specific Old Joker offer, or
    /// pass nil to disarm. Every key in `OldJokerConfig.offerKeys` works, plus
    /// "collect", "thirstReturn" and "thirstAmbush" — the visits he makes on
    /// his own terms, which are otherwise unreachable without setting up a
    /// marker or a drink first.
    public func debugForceJoker(_ key: String?) {
        debugForcedJokerKey = key
        debugForcedJokerBlocked = false
        if let key { debugPrimeForJoker(key) }
    }

    /// DEBUG: arm the next mystery node with a specific Queen/Two outcome, or
    /// pass nil to disarm. Any key in `MysteryConfig.outcomeKeys` works; the
    /// flow skips the Old Joker's takeover roll while one is armed. Consumed
    /// by the flow, never rolled — `rollMysteryEvent` stays pure.
    public var debugForcedMysteryKey: String?
    public func debugForceMystery(_ key: String?) {
        debugForcedMysteryKey = key
        if let key { debugPrimeForMystery(key) }
    }

    /// Give an armed outcome the state it needs to LAND instead of folding to
    /// a Toll/Cache. Each of these is exactly what applyMysteryEvent guards on.
    private func debugPrimeForMystery(_ key: String) {
        switch key {
        case "shieldDrain", "twoGame":
            sameCharge = true                        // both only land on a charged shield
        case "shieldCharge":
            sameCharge = false                       // only fills an empty one
        case "coinDouble":
            if coins == 0 { coins = 5 }              // doubling zero folds to a Cache
        case "itemTheft":
            if !columnPillars.contains(where: { $0 != nil }),
               !columnBases.contains(where: { $0 != nil }),
               let p = data.items.pillars.first(where: { itemUnlocks.isUnlocked($0) }) {
                columnPillars[0] = p.id              // something on the board to take
            }
        case "stickerTheft":
            // Needs a stickered card to peel.
            if !getRunDeck().contains(where: { !$0.stickers.isEmpty }),
               let t = data.items.stickers.first(where: { !$0.cursed }),
               let i = baseDeck.firstIndex(where: {
                   ownedIds.contains($0.id) && CardRules.stickerEligible($0, t.id, data: data) }) {
                _ = applyStickerToCard(&baseDeck[i], t.id, rng: RNG(seed: UInt32(i + 1)))
            }
        case "stickerStrip":
            if !getRunDeck().contains(where: { !$0.stickers.isEmpty }),
               let t = data.items.stickers.first(where: { !$0.cursed }),
               let i = baseDeck.firstIndex(where: {
                   ownedIds.contains($0.id) && CardRules.stickerEligible($0, t.id, data: data) }) {
                _ = applyStickerToCard(&baseDeck[i], t.id, rng: RNG(seed: UInt32(i + 1)))
            }
        case "mammaLie":
            // The Con needs a ★ to covet and something to lose.
            if !getRunDeck().contains(where: { $0.joker }) { ownedIds.append(mintJokerId()) }
            if coins == 0 { coins = 5 }
        case "joker":
            break                                    // at cap it folds to coins; that fold is worth seeing too
        default:
            break
        }
    }

    /// Give an armed offer the state it NEEDS to build, so arming actually
    /// produces the offer instead of failing a precondition and falling
    /// through. Each of these is exactly what that offer's builder guards on.
    private func debugPrimeForJoker(_ key: String) {
        switch key {
        case "buyout", "swap", "refund", "blindSwap", "freeShop":
            // He needs something of yours to point at — and Blind Swap needs
            // a COMMON specifically.
            if equippedHoldings().filter({ $0.kind != .sticker }).isEmpty {
                if let p = data.items.pillars.first(where: { itemUnlocks.isUnlocked($0) }) {
                    columnPillars[0] = p.id
                }
                if let b = data.items.bases.first(where: { itemUnlocks.isUnlocked($0) }) {
                    columnBases[0] = b.id
                }
            }
            if key == "blindSwap",
               !equippedHoldings().contains(where: { holdingDef($0)?.tier == "common" }),
               let common = data.items.pillars.first(where: {
                   $0.tier == "common" && itemUnlocks.isUnlocked($0) }) {
                columnPillars[1] = common.id
            }
        case "purgeReset":
            // The ladder has to have climbed for there to be anything to halve.
            if removalsBought == 0 { removalsBought = 2 }
        case "insurance":
            sameCharge = false                       // only offered on an empty shield
            // …and he won't offer a charge you couldn't pay for.
            let insCost = data.items.oldJoker.int("insurance", "cost", 2)
            if coins < insCost { coins = insCost }
        case "marker":
            jokerDebt = 0                            // never offered while one is open
        case "eights":
            // Needs at least one Ace or 2 left to flatten.
            if eightsAffectedCount() == 0 {
                _ = debugAddCard(suit: allSuits[0], rank: maxRank)
            }
        case "ride":
            // The map decides whether this can build at all; the fare at least
            // shouldn't be what stops you taking it.
            let fare = data.items.oldJoker.int("ride", "cost", 5)
            if coins < fare { coins = fare }
        case "cut":
            let cutCost = data.items.oldJoker.int("cut", "chooseCost", 4)
            if coins < cutCost { coins = cutCost }
        case "thirsty", "duplicate", "purge", "twoDoors":
            break                                    // these build from the deck
        case "jokerForPillars":
            // He needs at least one flag to take down.
            if !columnPillars.contains(where: { $0 != nil }),
               let p = data.items.pillars.first(where: { itemUnlocks.isUnlocked($0) }) {
                columnPillars[0] = p.id
            }
        default:
            break
        }
    }

    /// Bank one BUY against the Collection's lifetime tally. Every purchase
    /// path funnels through here so the count can't drift between the shelf,
    /// the detail sheet and the pack tray. Exhibition banks nothing, exactly
    /// as it banks no unlock progress.
    func recordBuy(_ typeId: String) {
        DebugEventLog.shared.add("store: bought \(typeId) · purse \(coins)")
        guard !isExhibition() else { return }
        stats.bumpItemBought(typeId)
    }

    /// `priceOverride`: a SHELF purchase passes its slot's resolved price
    /// (`priceOfMixed`) so the Freebie/comp zero the shelf displays is the
    /// price actually charged — the raw type price here silently re-billed a
    /// gifted slot (v6.49 bugfix).
    public func buySticker(_ typeId: String, priceOverride: Double? = nil) -> Bool {
        guard !rules().noStickers, data.stickerTypes.get(typeId) != nil else { return false }
        let price = priceOverride ?? priceOf(typeId)
        guard price.isFinite, spendCoins(Int(price)) else { return false }
        stickerInventory[typeId, default: 0] += 1
        recordBuy(typeId)
        return true
    }
    @discardableResult
    public func useStickerFromInventory(_ typeId: String) -> Bool {
        guard (stickerInventory[typeId] ?? 0) > 0 else { return false }
        stickerInventory[typeId]! -= 1
        if stickerInventory[typeId] == 0 { stickerInventory[typeId] = nil }
        return true
    }
    public func debugGrantSticker(_ typeId: String) {
        guard data.stickerTypes.get(typeId) != nil else { return }
        stickerInventory[typeId, default: 0] += 1
    }
    /// DEBUG panel grants: a free inventory copy (no cost, no placement — the
    /// player places it from the tray/HUD like a bought one).
    public func debugGrantPillar(_ typeId: String) {
        guard data.pillarTypes.get(typeId) != nil else { return }
        pillarInventory[typeId, default: 0] += 1
    }
    public func debugGrantBase(_ typeId: String) {
        guard data.baseTypes.get(typeId) != nil else { return }
        baseInventory[typeId, default: 0] += 1
    }
    public func debugGrantSamePower(_ typeId: String) {
        guard data.samePowerTypes.get(typeId) != nil else { return }
        samePowerInventory[typeId, default: 0] += 1
    }

    public func columnPillar(_ col: Int) -> String? { columnPillars[safe: col] ?? nil }
    public func pillarCount() -> Int { columnPillars.compactMap { $0 }.count }
    public func firstEmptyColumn() -> Int? { columnPillars.firstIndex { $0 == nil } }
    @discardableResult
    public func buyPillarToInventory(_ typeId: String, priceOverride: Double? = nil) -> Bool {
        guard data.pillarTypes.get(typeId) != nil else { return false }
        let price = priceOverride ?? priceOfPillar(typeId)
        guard price.isFinite, spendCoins(Int(price)) else { return false }
        pillarInventory[typeId, default: 0] += 1
        recordBuy(typeId)
        return true
    }
    @discardableResult
    public func placePillar(_ typeId: String, col: Int) -> Bool {
        guard col >= 0, col < columnPillars.count, (pillarInventory[typeId] ?? 0) > 0 else { return false }
        pillarInventory[typeId]! -= 1
        if pillarInventory[typeId] == 0 { pillarInventory[typeId] = nil }
        if !isExhibition() { stats.bump("pillarsPlaced") }
        if let displaced = columnPillars[col] { pillarInventory[displaced, default: 0] += 1 }
        columnPillars[col] = typeId
        return true
    }
    @discardableResult
    public func unplacePillar(col: Int) -> Bool {
        guard col >= 0, col < columnPillars.count, let id = columnPillars[col] else { return false }
        columnPillars[col] = nil
        pillarInventory[id, default: 0] += 1
        return true
    }
    public func setColumnPillar(col: Int, typeId: String?) {
        guard col >= 0, col < columnPillars.count else { return }
        columnPillars[col] = typeId
    }
    public func swapColumnPillars(_ a: Int, _ b: Int) {
        guard a >= 0, b >= 0, a < columnPillars.count, b < columnPillars.count else { return }
        columnPillars.swapAt(a, b)
    }

    public func columnBase(_ col: Int) -> String? { columnBases[safe: col] ?? nil }
    public func baseCount() -> Int { columnBases.compactMap { $0 }.count }
    public func firstEmptyBaseColumn() -> Int? { columnBases.firstIndex { $0 == nil } }
    @discardableResult
    public func buyBaseToInventory(_ typeId: String, priceOverride: Double? = nil) -> Bool {
        guard data.baseTypes.get(typeId) != nil else { return false }
        let price = priceOverride ?? priceOfBase(typeId)
        guard price.isFinite, spendCoins(Int(price)) else { return false }
        baseInventory[typeId, default: 0] += 1
        recordBuy(typeId)
        return true
    }
    @discardableResult
    public func placeBase(_ typeId: String, col: Int) -> Bool {
        guard col >= 0, col < columnBases.count, (baseInventory[typeId] ?? 0) > 0 else { return false }
        baseInventory[typeId]! -= 1
        if baseInventory[typeId] == 0 { baseInventory[typeId] = nil }
        if !isExhibition() { stats.bump("basesPlaced") }
        if let displaced = columnBases[col] { baseInventory[displaced, default: 0] += 1 }
        columnBases[col] = typeId
        return true
    }
    @discardableResult
    public func unplaceBase(col: Int) -> Bool {
        guard col >= 0, col < columnBases.count, let id = columnBases[col] else { return false }
        columnBases[col] = nil
        baseInventory[id, default: 0] += 1
        return true
    }
    public func setColumnBase(col: Int, typeId: String?) {
        guard col >= 0, col < columnBases.count else { return }
        columnBases[col] = typeId
    }
    public func swapColumnBases(_ a: Int, _ b: Int) {
        guard a >= 0, b >= 0, a < columnBases.count, b < columnBases.count else { return }
        columnBases.swapAt(a, b)
    }

    @discardableResult
    public func buySamePowerToInventory(_ typeId: String, priceOverride: Double? = nil) -> Bool {
        guard data.samePowerTypes.get(typeId) != nil else { return false }
        let price = priceOverride ?? priceOfSamePower(typeId)
        guard price.isFinite, spendCoins(Int(price)) else { return false }
        samePowerInventory[typeId, default: 0] += 1
        recordBuy(typeId)
        return true
    }
    /// Exactly ONE Same-Power is equipped at a time; equipping returns the old
    /// one to the inventory.
    @discardableResult
    public func equipSamePower(_ typeId: String) -> Bool {
        guard (samePowerInventory[typeId] ?? 0) > 0 else { return false }
        samePowerInventory[typeId]! -= 1
        if samePowerInventory[typeId] == 0 { samePowerInventory[typeId] = nil }
        if let old = equippedSamePower { samePowerInventory[old, default: 0] += 1 }
        equippedSamePower = typeId
        return true
    }
    @discardableResult
    public func unequipSamePower() -> Bool {
        guard let old = equippedSamePower else { return false }
        samePowerInventory[old, default: 0] += 1
        equippedSamePower = nil
        return true
    }
    public func getSamePower() -> String? { equippedSamePower }

    // MARK: - Store

    public func setRemovalSlot(_ on: Bool) { removalSlotEnabled = on }
    /// TEST/DEBUG hook: seed an outstanding Old Joker marker.
    public func setJokerDebt(_ n: Int) { jokerDebt = max(0, n) }
    public func removalSlotOn() -> Bool { removalSlotEnabled }

    /// The Queen's Mulligan, claimed by the next deal: true exactly once.
    @discardableResult
    public func consumeFreeRedeal() -> Bool {
        guard freeRedealPending else { return false }
        freeRedealPending = false
        return true
    }

    /// SCREENSHOT HOOK (EventCaptureUITests' `-storeFreeRefresh 1`): arm the
    /// Queen's Restock so the next `openStore` spends it through the real
    /// consumption path. Debug/demo only — never called by play code.
    public func debugGrantFreeRefresh() { freeRerollPending = true }

    /// (Re)open the store for a new visit: a fresh offer at base reroll cost.
    /// `node` stamps the offer's owner (defaults to the current position) so
    /// the store screen can tell a resume of THIS visit from a different shop.
    @discardableResult
    public func openStore(rng: RNG? = nil, node: Int? = nil) -> StoreOffer {
        // The visit's offer keys to the NODE — the store node's id, or a mystery
        // node's id for a detour — so a store's contents depend on the seed +
        // node, never on visit order. (Two keys, matching the web's opener; the
        // reroll adds the ladder index as a third.)
        let r = rng ?? (nodePos != nil ? rrng(.s("store"), .n(nodePos!)) : RNG(seed: RNG.generateSeed()))
        storeOffer = StoreRoll.freshOffer(r, data: data, removalOn: removalSlotEnabled,
                                          isUnlocked: itemUnlocks.isUnlocked,
                                          isEquipped: { [weak self] kind, id in
                                              self?.isEquipped(kind: kind, id: id) ?? false
                                          },
                                          tierWeights: effectiveTierWeights(),
                                          genCard: { [weak self] rr in self?.genStoreCard(rr) })
        // Stamp the visit's owner node (v6.52) — the store screen rerolls on a
        // mismatch, so this shelf and this visit's price twist end with it.
        storeOffer!.offerNode = node ?? nodePos
        DebugEventLog.shared.add("store: opened for node \(storeOffer!.offerNode.map(String.init) ?? "?")"
                                 + (storePriceModActive.map { " · price twist ACTIVE (\($0))" } ?? ""))
        // The Queen's Restock spends itself on THIS visit's ladder: the first
        // refresh is free, used or not. And the cast's price twist arms for
        // exactly one shop — whatever was pending becomes this visit's rule.
        if freeRerollPending {
            storeOffer!.rerollCost = 0
            freeRerollPending = false
        }
        storePriceModActive = storePriceModPending
        storePriceModPending = nil
        // A rank-variant pillar on the shelf locks its rank NOW — first
        // appearance defines it for the climb (see lockPillarRankVariant).
        for slot in storeOffer!.slots.compactMap({ $0 }) where slot.kind == "pillar" {
            if let def = data.pillarTypes.get(slot.id) { lockPillarRankVariant(def) }
        }
        // FREEBIE: one random rolled slot per visit costs 0. Drawn from the
        // SAME seeded stream so a reload re-gifts the identical item.
        if equippedPillarDefs().contains(where: { $0.effect == "freebie" }) {
            let candidates = storeOffer!.slots.enumerated()
                .filter { $0.element != nil && $0.element!.kind != "removal" }.map(\.offset)
            if !candidates.isEmpty {
                storeOffer!.freeSlot = candidates[r.index(candidates.count)]
            }
        }
        return storeOffer!
    }
    /// Is this exact item already on the board / equipped? The shelf skips it —
    /// a duplicate you have nowhere to put is a dead slot.
    public func isEquipped(kind: String, id: String) -> Bool {
        switch kind {
        case "pillar":    return columnPillars.contains(id)
        case "base":      return columnBases.contains(id)
        case "samepower": return equippedSamePower == id
        default:          return false
        }
    }

    /// Stage a FIXED shelf the player picks from for free — THE OLD JOKER
    /// emptying his coat. It reuses the shop wholesale (tiles, hold-help,
    /// detail sheets, column placement) rather than inventing a second
    /// item-granting UI, so a gift behaves exactly like a purchase at 0.
    ///
    /// The Purge slot is deliberately absent: this is him giving, not a shop.
    public func openGiftShelf(_ gifts: [OldJoker.Holding]) {
        let slots: [StoreSlot?] = gifts.map { StoreSlot(kind: $0.kind.rawValue, id: $0.id) }
        storeOffer = StoreOffer(slots: slots, rerollCost: .infinity)   // never rerollable
        freeShopPending = true
        // A rank-variant pillar in his coat locks its rank exactly like a
        // shelf appearance would — the gift tile must show the REAL rank,
        // never a raw "{rank}" template (v6.58, the thirsty-debt leak).
        for slot in slots.compactMap({ $0 }) where slot.kind == "pillar" {
            if let def = data.pillarTypes.get(slot.id) { lockPillarRankVariant(def) }
        }
    }

    /// True while a gift shelf is the current offer — the store hides its
    /// Purge slot and its REFRESH for it.
    public var isGiftShelf: Bool { freeShopPending && storeOffer?.rerollCost == .infinity }

    public func getStoreOffer() -> StoreOffer? { storeOffer }
    /// True when the saved offer belongs to a DIFFERENT node than `key` — the
    /// store screen rerolls instead of resuming it (v6.52), which is what ends
    /// a visit's shelf and its price twist at the door. A nil stamp (gift
    /// shelf, pre-v6.52 save) is never stale.
    public func storeOfferIsStale(for key: Int?) -> Bool {
        guard let owner = storeOffer?.offerNode else { return false }
        return owner != key
    }
    public func storeRerollCost() -> Double { storeOffer?.rerollCost ?? .infinity }
    public func canReroll() -> Bool { storeOffer.map { Double(coins) >= $0.rerollCost } ?? false }

    /// Reroll ALL offered slots for the current cost; the cost then climbs.
    @discardableResult
    public func rerollStore() -> Bool {
        guard var offer = storeOffer, Double(coins) >= offer.rerollCost else { return false }
        let wasFree = offer.rerollCost == 0
        coins -= Int(offer.rerollCost)
        // His treat was THIS shelf. Refresh it and you are paying again.
        freeShopPending = false
        // …and the cast's price twist ends with the shelf it was cast on.
        storePriceModActive = nil
        // (A spent Purge slot returns on its own: the reroll below rebuilds
        // the whole shelf through freshOffer, which re-appends the slot.)
        let rolled = removalSlotEnabled ? data.items.store.slots - 1 : data.items.store.slots
        // The outgoing shelf's Jokers vanish first (they'd otherwise count as
        // held during the re-roll).
        offer.slots = []
        storeOffer = offer
        // The reroll keys to (store node, reroll index) — the index derived from
        // the PERSISTED cost ladder, so a restored offer continues the sequence.
        let step = data.items.store.reroll.step
        let rerollIndex = step > 0
            ? max(0, Int(((offer.rerollCost - data.items.store.reroll.baseCost) / step).rounded()))
            : 0
        let rng = nodePos != nil ? rrng(.s("store"), .n(nodePos!), .n(rerollIndex)) : RNG(seed: RNG.generateSeed())
        offer.slots = StoreRoll.rollUnifiedSlots(rng, count: rolled, data: data,
                                                 isUnlocked: itemUnlocks.isUnlocked,
                                                 isEquipped: { [weak self] kind, id in
                                                     self?.isEquipped(kind: kind, id: id) ?? false
                                                 },
                                                 tierWeights: effectiveTierWeights(),
                                                 genCard: { [weak self] rr in self?.genStoreCard(rr) })
        if removalSlotEnabled { offer.slots.append(StoreSlot(kind: "removal", id: "removal")) }
        // The rerolled shelf re-runs the meta effects: rank variants lock,
        // and FREEBIE re-gifts one slot from the same stream.
        for slot in offer.slots.compactMap({ $0 }) where slot.kind == "pillar" {
            if let def = data.pillarTypes.get(slot.id) { lockPillarRankVariant(def) }
        }
        offer.freeSlot = nil
        if equippedPillarDefs().contains(where: { $0.effect == "freebie" }) {
            let candidates = offer.slots.enumerated()
                .filter { $0.element != nil && $0.element!.kind != "removal" }.map(\.offset)
            if !candidates.isEmpty { offer.freeSlot = candidates[rng.index(candidates.count)] }
        }
        // A FREE refresh (the Queen's Restock) stands in for the ladder's
        // first rung: the next one prices as if the free one had been bought.
        // (Not baseCost — the ladder index derives from the cost, and two
        // rerolls at index 0 would roll the identical shelf twice.)
        offer.rerollCost = wasFree
            ? data.items.store.reroll.baseCost + step
            : offer.rerollCost + step
        storeOffer = offer
        return true
    }

    /// A STORE CARD-slot card: rolled with the same odds it would have inside a
    /// card pack — same pool, same sticker distribution — except: Removal
    /// (Blank) cards NEVER appear here, and a Joker rolls at the plain any-card
    /// rate (1/53) rather than the pack's half-share, gated by the joker cap.
    /// ONE `rng()` call for the special check, then `genNormalCard`.
    public func genStoreCard(_ rng: RNG) -> CardSpec? {
        if rng.next() < 1.0 / Self.specialRollSpace && jokersAllowed() { return genJokerCard() }
        return genNormalCard(rng, stickerOdds: data.items.store.card.stickerOdds)
    }

    /// A CARD-PACK slot: Joker + Blank at the shared full-52 rule — weight 0.5
    /// each against the whole 52-card deck. P(special) = 1/53 per slot, then a
    /// 50/50 Joker or Blank. At the joker cap a Joker roll falls through to a
    /// normal card (Blanks keep their half — only Jokers are capped).
    public func genPackCard(_ rng: RNG) -> CardSpec {
        if rng.next() < Self.specialChance {
            let isJoker = rng.next() < 0.5
            if isJoker && jokersAllowed() { return genJokerCard() }
            if !isJoker {
                let c = CardSpec.blank(id: nextCardId)
                nextCardId += 1
                return c
            }
        }
        return genNormalCard(rng)
    }

    /// End the Old Joker's comp — the visit is over (or the shelf refreshed).
    public func endFreeShop() { freeShopPending = false }

    /// Is the Old Joker's comp covering this slot's kind right now?
    /// The Purge slot is deliberately outside it: a free REPEATABLE card-delete
    /// would let one visit strip the deck to nothing.
    public func freeShopCovers(_ kind: String) -> Bool {
        guard freeShopPending else { return false }
        let raw = data.items.oldJoker.raw["freeShop"]?.asObject?["freeKinds"]?.asArray ?? []
        let kinds = raw.compactMap(\.asString)
        return kinds.isEmpty ? kind != "removal" : kinds.contains(kind)
    }

    /// Price of a shelf slot's item (dispatches by kind). 0 for an empty slot.
    public func priceOfMixed(_ i: Int) -> Double {
        guard let s = storeOffer?.slots[safe: i] ?? nil else { return 0 }
        // The comp zeroes the shelf at the ONE chokepoint every buy path and
        // every price label already funnels through.
        if freeShopCovers(s.kind) { return 0 }
        // FREEBIE's gifted slot is free, same chokepoint.
        if storeOffer?.freeSlot == i { return 0 }
        switch s.kind {
        case "sticker":   return priceOf(s.id)
        case "pillar":    return priceOfPillar(s.id)
        case "base":      return priceOfBase(s.id)
        case "samepower":
            // The MYSTERY slot has no concrete id: it prices from its own
            // store config block, through the same shopPrice/mod chokepoint.
            return s.mystery ? storeModPrice(shopPrice(data.items.store.mysterySamePower.price))
                             : priceOfSamePower(s.id)
        // The shelf tile must quote what the picker will actually charge —
        // both the climb ladder and the deck multiplier.
        case "removal":   return removalPrice()
        // A single card is priced by what it carries: base plus stickerStep
        // for every sticker on it (Jokers keep their own flat price).
        case "card":
            if s.card?.joker == true { return storeModPrice(shopPrice(data.items.store.card.jokerPrice)) }
            let stickers = Double(s.card?.stickers.count ?? 0)
            return storeModPrice(shopPrice(data.items.store.card.price
                                           + stickers * data.items.store.card.stickerStep))
        default:          return priceOfPack(s.id)
        }
    }

    /// Buy the offered sticker in slot `i` (to inventory); empties that slot
    /// only. Charges the SLOT's resolved price (Freebie/comp included) — the
    /// same number the shelf and the detail sheet display.
    @discardableResult
    public func buyOfferedSticker(_ i: Int) -> Bool {
        guard !rules().noStickers else { return false }   // Lammy: stickers unusable
        guard var offer = storeOffer, let slot = offer.slots[safe: i] ?? nil,
              slot.kind == "sticker",
              buySticker(slot.id, priceOverride: priceOfMixed(i)) else { return false }
        offer.slots[i] = nil
        storeOffer = offer
        return true
    }

    public struct BuyResult {
        public var ok: Bool
        public var kind: String?
        public var card: CardSpec?
        public var trayIndex: Int?
        public var packId: String?
        public var packKind: String?
        public var keep: Int?
        /// MYSTERY SAME-POWER: the concrete Same-Power id the buy revealed.
        public var revealed: String?
    }

    /// Buy shelf slot `i`, dispatching by its kind. Pillars/Bases/Same-Powers go
    /// to inventory; Packs charge and OPEN; the card slot moves the exact shown
    /// card into the pack tray. A MYSTERY samepower slot reveals its concrete
    /// Same-Power at buy time via `mysteryRng` — the UI keys that stream to
    /// ["mysterysamepower", nodeId, slot], mirroring the storepack keying.
    @discardableResult
    public func buyMixedSlot(_ i: Int, mysteryRng: RNG? = nil) -> BuyResult {
        guard var offer = storeOffer, let s = offer.slots[safe: i] ?? nil else { return BuyResult(ok: false) }
        if s.kind == "sticker" { return BuyResult(ok: false) }   // stickers buy via buyOfferedSticker
        // Lammy: sticker packs still roll into the shelf but can't be bought.
        if rules().noStickers, s.kind == "pack", data.packTypes.get(s.id)?.kind == "sticker" {
            return BuyResult(ok: false)
        }
        // EVERY slot charges `priceOfMixed(i)` — the ONE resolved price the
        // shelf tile and the detail sheet display (Freebie's gifted slot and
        // the free-shop comp both zero there). Charging the raw type price
        // here re-billed gifted slots and blocked them on an empty purse
        // (v6.49 bugfix — the sticker path had the same hole).
        switch s.kind {
        case "pillar":
            guard buyPillarToInventory(s.id, priceOverride: priceOfMixed(i)) else { return BuyResult(ok: false) }
        case "base":
            guard buyBaseToInventory(s.id, priceOverride: priceOfMixed(i)) else { return BuyResult(ok: false) }
        case "samepower":
            if s.mystery {
                // MYSTERY SAME-POWER (v6.51): charge the config price, empty
                // the slot, then ONE uniform draw (`Int(rng()*pool.count)`)
                // over the unlocked, un-equipped pool reveals the concrete
                // Same-Power. An empty pool refunds and fails (unreachable in
                // practice: the slot only rolls while the pool is non-empty).
                let price = priceOfMixed(i)
                guard Double(coins) >= price else { return BuyResult(ok: false) }
                coins -= Int(price)
                let pool = data.samePowerTypes.all().filter {
                    itemUnlocks.isUnlocked($0) && equippedSamePower != $0.id
                }
                guard let rng = mysteryRng, !pool.isEmpty else {
                    coins += Int(price)
                    return BuyResult(ok: false)
                }
                let revealed = pool[rng.index(pool.count)].id
                offer.slots[i] = nil
                storeOffer = offer
                samePowerInventory[revealed, default: 0] += 1
                recordBuy(revealed)
                return BuyResult(ok: true, kind: "samepower", revealed: revealed)
            }
            guard buySamePowerToInventory(s.id, priceOverride: priceOfMixed(i)) else { return BuyResult(ok: false) }
        case "pack":
            guard let t = data.packTypes.get(s.id) else { return BuyResult(ok: false) }
            let packPrice = priceOfMixed(i)
            guard Double(coins) >= packPrice else { return BuyResult(ok: false) }
            coins -= Int(packPrice)
            recordBuy(s.id)   // packs are a Collection group too
            offer.slots[i] = nil
            storeOffer = offer
            return BuyResult(ok: true, kind: "pack", packId: s.id, packKind: t.kind, keep: t.int("keep", 1))
        case "card":
            let price = priceOfMixed(i)
            guard let card = s.card, Double(coins) >= price else { return BuyResult(ok: false) }
            coins -= Int(price)
            offer.slots[i] = nil
            storeOffer = offer
            packTray.append(card)
            baseDeck.append(card)
            return BuyResult(ok: true, kind: "card", card: card, trayIndex: packTray.count - 1)
        default:
            return BuyResult(ok: false)   // removal is bought via buyRemoval
        }
        offer.slots[i] = nil
        storeOffer = offer
        return BuyResult(ok: true, kind: s.kind)
    }

    /// Buy a Removal: charge the fixed price and permanently remove card `id`.
    /// The offer slot is NOT consumed (repeatable).
    @discardableResult
    public func buyRemoval(_ id: Int) -> Bool {
        let price = removalPrice()
        guard Double(coins) >= price, removeDeckCard(id) else { return false }
        coins -= Int(price)
        removalsBought += 1   // the next one costs `priceStep` more
        // The slot is SPENT for this shelf. It used to be endlessly repeatable
        // inside one visit, which let a full purse strip the deck to nothing
        // in a single stop. A REFRESH puts it back (see rerollStore).
        if var offer = storeOffer,
           let i = offer.slots.firstIndex(where: { $0?.kind == "removal" }) {
            offer.slots[i] = nil
            storeOffer = offer
        }
        return true
    }

    /// Reveal a pack's items. Card packs mint pack-odds cards; sticker packs roll
    /// grantable sticker ids.
    public func revealPack(_ packId: String, rng: RNG) -> (kind: String, keep: Int, cards: [CardSpec], stickers: [String]) {
        guard let t = data.packTypes.get(packId) else { return ("card", 0, [], []) }
        let size = t.int("size", 1), keep = t.int("keep", 1)
        if t.kind == "card" {
            var cards: [CardSpec] = []
            for _ in 0..<size { cards.append(genPackCard(rng)) }
            return ("card", keep, cards, [])
        }
        // Sticker packs prefer stickers with a legal target — a pack pick the
        // player cannot place is a wasted purchase (v5.83). If NOTHING is
        // placeable (a no-stickers deck), fall back to the plain pool rather
        // than handing over an empty pack.
        let targeted = grantableStickersWithTarget()
        let pool = targeted.isEmpty ? grantableStickers() : targeted
        let ids = StoreRoll.rollIds(pool, size, rng, tierWeights: data.items.store.tierWeights)
        return ("sticker", keep, [], ids)
    }

    // MARK: - Sticker application to the persistent deck

    /// May sticker `typeId` be applied to card `id`? The GLOBAL gate plus the
    /// rank-boundary rule.
    public func canApplySticker(_ card: CardSpec?, _ typeId: String) -> Bool {
        guard let card, !rules().noStickers, let t = data.stickerTypes.get(typeId) else { return false }
        guard CardRules.stickerEligible(card, typeId, data: data) else { return false }
        guard t.kind == "rank" else { return true }
        let delta = t.num("rankDelta", 0)
        if delta > 0 && card.currentRank >= maxRank { return false }
        if delta < 0 && card.currentRank <= minRank { return false }
        return true
    }
    public func canApplyStickerById(_ id: Int, _ typeId: String) -> Bool {
        canApplySticker(findById(id), typeId)
    }

    /// Apply a sticker from the inventory to a persistent card.
    @discardableResult
    public func applySticker(_ id: Int, _ typeId: String) -> Bool {
        guard let i = index(of: id), canApplySticker(baseDeck[i], typeId) else { return false }
        guard useStickerFromInventory(typeId) else { return false }
        let applied = applyStickerToCard(&baseDeck[i], typeId, rng: actRng())
        // UNLOCK1: the player-applied sticker counter. This method is the
        // chokepoint every apply flow funnels through (pickers, store buys,
        // pack reveals), so it is the one right place for the bump — it was
        // missing on native, which left `stickersApplied` pinned at 0 and its
        // gated items permanently unreachable. Exhibition banks nothing.
        if applied, !isExhibition() { stats.bump("stickersApplied") }
        return applied
    }

    /// Apply a sticker WITHOUT consuming an inventory copy — for engine-side
    /// grants that never went through the inventory (the Wild Sticker Base
    /// writing its durable copy onto the campaign card). Still counted.
    @discardableResult
    public func applyStickerDirect(_ id: Int, _ typeId: String) -> Bool {
        guard let i = index(of: id), canApplySticker(baseDeck[i], typeId) else { return false }
        let applied = applyStickerToCard(&baseDeck[i], typeId, rng: actRng())
        if applied, !isExhibition() { stats.bump("stickersApplied") }
        return applied
    }

    // MARK: - Reset

    /// A New Campaign resets everything to a vanilla start; nothing carries
    /// across attempts.
    public func reset() {
        baseDeck = DeckManager.buildStandardDeck()
        currentStage = 1
        currentRunIndex = 1
        totalCorrectGuesses = 0
        runsCompleted = 0
        totalCardsFlipped = 0
        totalCoinsEarned = 0
        allGuessesCorrect = 0
        allGuessesTotal = 0
        coins = 0
        playedCounted = false
        runWonBanked = false
        cardsFlippedBanked = 0
        runScore = 0
        scoreBanked = 0
        endless = false
        sameCharge = false
        pillarRankVariants = [:]
        stickerInventory = [:]
        pillarInventory = [:]
        baseInventory = [:]
        columnPillars = Array(repeating: nil, count: CampaignLayout.columnSlots)
        columnBases = Array(repeating: nil, count: CampaignLayout.columnSlots)
        samePowerInventory = [:]
        equippedSamePower = nil
        storeOffer = nil
        packTray = []
        nextCardId = 52
        nodeCards = [:]
        packCards = [:]
        actionCounter = 0   // the action stream restarts with the campaign
        startNewRun()
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { i >= 0 && i < count ? self[i] : nil }
}
