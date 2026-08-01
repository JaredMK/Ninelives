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
    public static let runGenVersion = 3
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

    /// A freshly-minted NORMAL pack-odds card: a random suit from ALL FOUR
    /// (store cards/packs are deliberately UNGATED), then the shared sticker
    /// distribution, suit-restricted per sticker. Lammy mints none.
    public func genNormalCard(_ rng: RNG) -> CardSpec {
        let suits = allSuits
        let suit = suits[rng.index(suits.count)]
        let rank = minRank + rng.index(maxRank - minRank + 1)
        var card = CardSpec(id: nextCardId, suit: suit, originalRank: rank, currentRank: rank)
        nextCardId += 1
        let n = rules().noStickers ? 0 : StoreRoll.packStickerCount(rng.next(), data: data)
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

    /// PACK2 — DETERMINISTIC roll for ONE slot of a revealed +2 pack.
    func packSlotIdFor(_ node: MapNode, slot: Int) -> Int {
        let rng = RNG(seed: packSlotSeed(seed: runSeed, nodeId: node.id, slot: slot))
        let special = rollMapSpecial(rng, allowJoker: false)
        // Only a Blank may lock (a `true` can only come from the pinned TEST hook).
        if special == false { return Self.specialBlank }
        let taken = reservedSet(except: nil)   // owned + all locks incl. this pack's earlier slot
        let endlessNode = node.suit == "★" || (node.phase ?? 0) >= phaseSuits.count || rules().altSuits
        let suit = endlessNode ? allSuits[rng.index(allSuits.count)]
            : ((node.suit != nil && node.suit != "★") ? node.suit! : suitForNode(node))
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
        // SEED1 — the run's seed is established FIRST, before ANY start roll.
        let entered = pendingSeedOverride
        pendingSeedOverride = nil   // one-shot
        exhibition = entered != nil
        runSeed = entered ?? RNG.generateSeed()
        savedGenVersion = Self.runGenVersion   // fresh seed → current generator
        let startRng = rrng(.s("start"))
        if rules().altSuits {
            // One card of EACH RANK at a random suit.
            ownedIds = DeckManager.ranks.map { r in
                let four = baseDeck.filter { !$0.joker && !$0.blank && $0.originalRank == r.value }
                return four[startRng.index(four.count)].id
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

    @discardableResult
    public func moveToNode(_ id: Int) -> Bool {
        guard legalNextNodes().contains(where: { $0.id == id }) else { return false }
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
        return true
    }
    public func nodeCleared(_ id: Int) -> Bool { clearedNodes.contains(id) }
    public func nodeHidden(_ id: Int) -> Bool {
        guard let n = runMap?.byId[id] else { return false }
        return n.mystery && !revealedNodes.contains(id) && !clearedNodes.contains(id)
    }
    public func revealNode(_ id: Int) { if !revealedNodes.contains(id) { revealedNodes.append(id) } }

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
            let endlessNode = node.suit == "★" || (node.phase ?? 0) >= phaseSuits.count || rules().altSuits
            for _ in 0..<count {
                let suit = endlessNode ? allSuits[rng.index(allSuits.count)]
                    : ((node.suit != nil && node.suit != "★") ? node.suit! : suitForNode(node))
                granted.append(pickSuitDraftId(suit, rng: rng))
            }
        }
        var out: [CardSpec] = []
        for id in granted {
            if id == Self.specialBlank { continue }        // a Blank grants a removal, not a card
            let realId = id == Self.specialJoker ? mintJokerId() : id
            if !ownedIds.contains(realId) { ownedIds.append(realId) }
            if let c = findById(realId) { out.append(c) }
        }
        markNodeCleared(node.id)
        return out
    }

    /// The seeded outcome KEY for a mystery node — PURE (no state change). Same
    /// (runSeed, nodeId) → same key, always. Weights read live from items.js.
    public func rollMysteryEvent(_ nodeId: Int) -> String {
        let w = data.items.mystery.weights
        let keys = MysteryConfig.outcomeKeys
        let totalRaw = keys.reduce(0.0) { $0 + (w[$1] ?? 0) }
        let total = totalRaw == 0 ? 1 : totalRaw
        let rng = RNG(seed: mysterySeed(seed: runSeed, nodeId: nodeId, salt: mysteryKeySalt))
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
    /// Permanently remove a card from the accumulated deck.
    @discardableResult
    public func removeDeckCard(_ id: Int) -> Bool {
        guard let i = ownedIds.firstIndex(of: id) else { return false }
        ownedIds.remove(at: i)
        return true
    }

    // MARK: - Coins + score

    public func getCoins() -> Int { coins }
    @discardableResult
    public func addCoins(_ n: Int) -> Int { coins += n; return coins }
    /// Coins earned by play (feeds the lifetime tally); `addCoins` is the raw mover.
    @discardableResult
    public func earnCoins(_ n: Int) -> Int { coins += n; totalCoinsEarned += n; return coins }
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
    /// The CAMPAIGN score: the banked total once the ♠ boss falls, else live.
    public func getCampaignScore() -> Int { runWonBanked ? scoreBanked : runScore }
    /// The ENDLESS score: everything earned AFTER the bank.
    public func getEndlessScore() -> Int { runWonBanked ? max(0, runScore - scoreBanked) : 0 }
    public func unbankedCardsFlipped() -> Int { max(0, totalCardsFlipped - cardsFlippedBanked) }
    public func addCardsFlipped(_ n: Int) { totalCardsFlipped += n }
    public func addRunGuesses(correct: Int, total: Int) {
        allGuessesCorrect += correct
        allGuessesTotal += total
    }
    public func markPlayed() { playedCounted = true }
    public func isPlayedCounted() -> Bool { playedCounted }

    public func isEndless() -> Bool { endless }
    /// Enter endless mode: stages stack above Pinky's home.
    public func startEndless() {
        endless = true
        extendEndless()
    }
    public func endlessStagesReached() -> Int { max(0, stageEntryDecks.count - phaseSuits.count) }

    public func getSameCharge() -> Bool { sameCharge }
    public func setSameCharge(_ v: Bool) { sameCharge = v }

    // MARK: - Inventories

    public func priceOf(_ typeId: String) -> Double {
        data.stickerTypes.get(typeId).map { shopPrice($0.price) } ?? .infinity
    }
    public func priceOfPillar(_ typeId: String) -> Double {
        data.pillarTypes.get(typeId).map { shopPrice($0.price) } ?? .infinity
    }
    public func priceOfBase(_ typeId: String) -> Double {
        data.baseTypes.get(typeId).map { shopPrice($0.price) } ?? .infinity
    }
    public func priceOfSamePower(_ typeId: String) -> Double {
        data.samePowerTypes.get(typeId).map { shopPrice($0.price) } ?? .infinity
    }
    public func priceOfPack(_ packId: String) -> Double {
        data.packTypes.get(packId).map { shopPrice($0.price) } ?? .infinity
    }
    public func removalPrice() -> Double { shopPrice(data.items.store.removal.price) }

    public func inventoryCount(_ typeId: String) -> Int { stickerInventory[typeId] ?? 0 }
    @discardableResult
    public func buySticker(_ typeId: String) -> Bool {
        guard !rules().noStickers, data.stickerTypes.get(typeId) != nil else { return false }
        let price = priceOf(typeId)
        guard price.isFinite, spendCoins(Int(price)) else { return false }
        stickerInventory[typeId, default: 0] += 1
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

    public func columnPillar(_ col: Int) -> String? { columnPillars[safe: col] ?? nil }
    public func pillarCount() -> Int { columnPillars.compactMap { $0 }.count }
    public func firstEmptyColumn() -> Int? { columnPillars.firstIndex { $0 == nil } }
    @discardableResult
    public func buyPillarToInventory(_ typeId: String) -> Bool {
        guard data.pillarTypes.get(typeId) != nil else { return false }
        let price = priceOfPillar(typeId)
        guard price.isFinite, spendCoins(Int(price)) else { return false }
        pillarInventory[typeId, default: 0] += 1
        return true
    }
    @discardableResult
    public func placePillar(_ typeId: String, col: Int) -> Bool {
        guard col >= 0, col < columnPillars.count, (pillarInventory[typeId] ?? 0) > 0 else { return false }
        pillarInventory[typeId]! -= 1
        if pillarInventory[typeId] == 0 { pillarInventory[typeId] = nil }
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
    public func buyBaseToInventory(_ typeId: String) -> Bool {
        guard data.baseTypes.get(typeId) != nil else { return false }
        let price = priceOfBase(typeId)
        guard price.isFinite, spendCoins(Int(price)) else { return false }
        baseInventory[typeId, default: 0] += 1
        return true
    }
    @discardableResult
    public func placeBase(_ typeId: String, col: Int) -> Bool {
        guard col >= 0, col < columnBases.count, (baseInventory[typeId] ?? 0) > 0 else { return false }
        baseInventory[typeId]! -= 1
        if baseInventory[typeId] == 0 { baseInventory[typeId] = nil }
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
    public func buySamePowerToInventory(_ typeId: String) -> Bool {
        guard data.samePowerTypes.get(typeId) != nil else { return false }
        let price = priceOfSamePower(typeId)
        guard price.isFinite, spendCoins(Int(price)) else { return false }
        samePowerInventory[typeId, default: 0] += 1
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
    public func removalSlotOn() -> Bool { removalSlotEnabled }

    /// (Re)open the store for a new visit: a fresh offer at base reroll cost.
    @discardableResult
    public func openStore(rng: RNG? = nil) -> StoreOffer {
        // The visit's offer keys to the NODE — the store node's id, or a mystery
        // node's id for a detour — so a store's contents depend on the seed +
        // node, never on visit order. (Two keys, matching the web's opener; the
        // reroll adds the ladder index as a third.)
        let r = rng ?? (nodePos != nil ? rrng(.s("store"), .n(nodePos!)) : RNG(seed: RNG.generateSeed()))
        storeOffer = StoreRoll.freshOffer(r, data: data, removalOn: removalSlotEnabled,
                                          isUnlocked: itemUnlocks.isUnlocked,
                                          genCard: { [weak self] rr in self?.genStoreCard(rr) })
        return storeOffer!
    }
    public func getStoreOffer() -> StoreOffer? { storeOffer }
    public func storeRerollCost() -> Double { storeOffer?.rerollCost ?? .infinity }
    public func canReroll() -> Bool { storeOffer.map { Double(coins) >= $0.rerollCost } ?? false }

    /// Reroll ALL offered slots for the current cost; the cost then climbs.
    @discardableResult
    public func rerollStore() -> Bool {
        guard var offer = storeOffer, Double(coins) >= offer.rerollCost else { return false }
        coins -= Int(offer.rerollCost)
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
                                                 genCard: { [weak self] rr in self?.genStoreCard(rr) })
        if removalSlotEnabled { offer.slots.append(StoreSlot(kind: "removal", id: "removal")) }
        offer.rerollCost += step
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
        return genNormalCard(rng)
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

    /// Price of a shelf slot's item (dispatches by kind). 0 for an empty slot.
    public func priceOfMixed(_ i: Int) -> Double {
        guard let s = storeOffer?.slots[safe: i] ?? nil else { return 0 }
        switch s.kind {
        case "sticker":   return priceOf(s.id)
        case "pillar":    return priceOfPillar(s.id)
        case "base":      return priceOfBase(s.id)
        case "samepower": return priceOfSamePower(s.id)
        case "removal":   return data.items.store.removal.price
        case "card":      return shopPrice(s.card?.joker == true
                                           ? data.items.store.card.jokerPrice
                                           : data.items.store.card.price)
        default:          return priceOfPack(s.id)
        }
    }

    /// Buy the offered sticker in slot `i` (to inventory); empties that slot only.
    @discardableResult
    public func buyOfferedSticker(_ i: Int) -> Bool {
        guard !rules().noStickers else { return false }   // Lammy: stickers unusable
        guard var offer = storeOffer, let slot = offer.slots[safe: i] ?? nil,
              slot.kind == "sticker", buySticker(slot.id) else { return false }
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
    }

    /// Buy shelf slot `i`, dispatching by its kind. Pillars/Bases/Same-Powers go
    /// to inventory; Packs charge and OPEN; the card slot moves the exact shown
    /// card into the pack tray.
    @discardableResult
    public func buyMixedSlot(_ i: Int) -> BuyResult {
        guard var offer = storeOffer, let s = offer.slots[safe: i] ?? nil else { return BuyResult(ok: false) }
        if s.kind == "sticker" { return BuyResult(ok: false) }   // stickers buy via buyOfferedSticker
        // Lammy: sticker packs still roll into the shelf but can't be bought.
        if rules().noStickers, s.kind == "pack", data.packTypes.get(s.id)?.kind == "sticker" {
            return BuyResult(ok: false)
        }
        switch s.kind {
        case "pillar":
            guard buyPillarToInventory(s.id) else { return BuyResult(ok: false) }
        case "base":
            guard buyBaseToInventory(s.id) else { return BuyResult(ok: false) }
        case "samepower":
            guard buySamePowerToInventory(s.id) else { return BuyResult(ok: false) }
        case "pack":
            guard let t = data.packTypes.get(s.id), Double(coins) >= t.price else { return BuyResult(ok: false) }
            coins -= Int(t.price)
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
        let pool = grantableStickers()
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
        return applyStickerToCard(&baseDeck[i], typeId, rng: actRng())
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
