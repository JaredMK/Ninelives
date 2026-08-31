import SpriteKit
import UIKit
import GameCore

/// What a finished deal hands back to the campaign flow (the web's onRunEnd
/// payload, flattened).
public struct DealOutcome {
    public var won: Bool
    public var cardsDrawn: Int
    public var correctGuesses: Int
    public var totalGuesses: Int
    public var aliveCount: Int
    public var minAliveCards: Int
    public var extraCoinUnits: Int
    public var pillarPayout: PillarPayout
    public var bonusCoins: Double
    public var bonusEvents: [(label: String, amount: Double)]
    public var sameCharge: Bool
    public var compoundUpdates: [Int: Int]
    public var snowballUpdates: [Int: Int]
    public var stickerPeels: [Int: Int]
    /// The guess that would have survived the fatal draw ("higher"/"lower"/
    /// "same") — the web's `survivingGuessWord(lastResolvedDraw)`; nil on a win.
    public var survivingGuessWord: String?
    /// Cards LANDED this deal, per suit — feeds the suit unlock counters.
    public var suitsLanded: [String: Int] = [:]
}

/// Wires GameCore to the scene. The engine owns every rule; this only listens
/// to its events, plays the matching feedback, and pushes fresh state in.
///
/// Nothing here computes game state — a divergence between the web and iOS can
/// only come from GameCore, which the Phase 1 fixtures already pin.
///
/// Motion follows the web build's causal queue: the triggering draw animates
/// first (priority 0), the effects it caused (a bury, a return) after it
/// (priority 1) — regardless of the order the engine emitted them.
public final class DealController {

    /// Phase 2's debug-launcher parameters (kept: the perf harness runs on it).
    public struct Setup {
        public var deckId: String
        public var tier: String
        public var seed: UInt32
        public var pileCount: Int
        public var pillars: [String?]
        public var bases: [String?]
        public var samePower: String?
        public var sameCharge: Bool
        public var cardCount: Int
        public var reduceMotion: Bool
        public init(deckId: String = "pink", tier: String = "regular", seed: UInt32 = 12345,
                    pileCount: Int = 9, pillars: [String?] = [nil, nil, nil],
                    bases: [String?] = [nil, nil, nil], samePower: String? = nil,
                    sameCharge: Bool = false, cardCount: Int = 39, reduceMotion: Bool = false) {
            self.deckId = deckId; self.tier = tier; self.seed = seed; self.pileCount = pileCount
            self.pillars = pillars; self.bases = bases; self.samePower = samePower
            self.sameCharge = sameCharge; self.cardCount = cardCount; self.reduceMotion = reduceMotion
        }
    }

    public enum Mode {
        case debug(Setup)
        /// A real campaign deal on the SHARED campaign at its current node.
        case campaign(DealPlan)
        /// A Zen deal: fresh suit-limited deck, no items, ZenStats tallies.
        case zen(DealPlan, diff: String)
    }

    private let mode: Mode
    private unowned let scene: DealScene
    private let campaign: CampaignState
    private let runMap: RunMap?
    private var engine: GameEngine!
    private let economy = Economy()
    private let animQueue = AnimQueue()

    private var plan: DealPlan?
    private var interactionLocked = true   // locked during the deal-out cascade
    // ODDS ASSIST deal-out gate (v6.72): holds the glow OFF until the
    // cascade lands (GameCore-testable; opens held, re-armed per re-deal).
    private var assistGate = OddsAssistGate()
    public private(set) var isOver = false
    private var pendingFinish: (() -> Void)?
    private var awaitingDeathFinish = false
    private var reduceMotion: Bool
    private var redealCost: Double = DealPlanner.redealBaseCost
    public private(set) var reshuffleIndex = 0
    /// The deal's initial per-suit composition (the deck band's "8/13").
    private var dealSuitTotals: [String: Int] = [:]
    /// The deal's initial per-rank composition (the histogram's grey ghost).
    private var dealRankTotals: [Int: Int] = [:]
    /// Cards in the run deck that this (subset) deal left out — see
    /// `computeSittingOut`. Empty on full-deck, Zen and debug deals.
    private var sittingOutRank: [Int: Int] = [:]
    private var sittingOutSuit: [String: Int] = [:]
    /// The guess that would have survived the last resolved draw (the web's
    /// `survivingGuessWord(lastResolvedDraw)`), stamped on every resolution.
    private var lastSurvivingWord: String?
    /// Cards LANDED this deal, per suit — the suit unlock counters read this.
    /// A LANDING is what counts, not a draw: the card has to reach a pile.
    private var suitsLanded: [String: Int] = [:]
    /// Deal-end scoring rolls (Gambler's flip) already floated this deal — the
    //  payout is re-read several times at deal end and each read re-rolls.
    private var dealEndRollsShown = Set<String>()

    /// Debug-launcher entry (owns a throwaway campaign).
    public init(setup: Setup, scene: DealScene) {
        self.mode = .debug(setup)
        self.scene = scene
        self.reduceMotion = setup.reduceMotion
        self.campaign = CampaignState()
        self.runMap = nil
        campaign.setDeck(setup.deckId)
        campaign.setTier(setup.tier)
        campaign.setSeedOverride(setup.seed)
        campaign.reset()
        scene.controller = self
        scene.reduceMotion = setup.reduceMotion
    }

    /// Campaign/Zen entry on the SHARED campaign.
    public init(mode: Mode, campaign: CampaignState, runMap: RunMap?, scene: DealScene,
                reduceMotion: Bool = false) {
        self.mode = mode
        self.scene = scene
        self.campaign = campaign
        self.runMap = runMap
        self.reduceMotion = reduceMotion
        if case .campaign(let p) = mode { plan = p; redealCost = p.redealCost; reshuffleIndex = p.reshuffleIndex }
        if case .zen(let p, _) = mode { plan = p }
        scene.controller = self
        scene.reduceMotion = reduceMotion
    }

    private var isZen: Bool { if case .zen = mode { return true }; return false }
    private var isCampaign: Bool { if case .campaign = mode { return true }; return false }

    // MARK: - Boot

    public func sceneReady() {
        switch mode {
        case .debug(let setup):
            bootDebug(setup)
        case .campaign(let p), .zen(let p, _):
            boot(plan: p)
        }
    }

    private func suitTotals(_ specs: [CardSpec]) -> [String: Int] {
        var t: [String: Int] = [:]
        for c in specs where !c.joker && !c.blank { t[c.suit, default: 0] += 1 }
        return t
    }

    /// Rank value → count at deal start. Jokers bank at rank 0 — their own ★
    /// column in the histogram — so a deal that opens holding one shows its
    /// ghost bar like every other rank. Blanks are never dealt.
    private func rankTotals(_ specs: [CardSpec]) -> [Int: Int] {
        var t: [Int: Int] = [:]
        for c in specs where !c.blank { t[c.joker ? 0 : c.currentRank, default: 0] += 1 }
        return t
    }

    /// A SUBSET deal must not betray exactly which cards are in play. The
    /// histogram band therefore describes the WHOLE run deck: the cards sitting
    /// this deal out are folded into both the grey totals and the bright
    /// "still out there" counts, so a full bar and a held-back card look the
    /// same. (The gold count plaque keeps showing this deal's real draws left —
    /// that number is the draw pile, not the deck.)
    // MARK: - External deck mutations (the histogram invalidation hook)

    /// Live-card twins of the boot-time `suitTotals`/`rankTotals` (CardSpec
    /// helpers) — the composition of the deal AS IT STANDS (draw pile + every
    /// pile's cards, buried and dead included: they never leave the deal).
    private func liveSuitTotals(_ cards: [LiveCard]) -> [String: Int] {
        var t: [String: Int] = [:]
        for c in cards where !c.joker && !c.blank { t[c.suit, default: 0] += 1 }
        return t
    }
    private func liveRankTotals(_ cards: [LiveCard]) -> [Int: Int] {
        var t: [Int: Int] = [:]
        for c in cards where !c.blank { t[c.joker ? 0 : c.value, default: 0] += 1 }
        return t
    }

    /// Re-derive the band's cached composition after the campaign deck was
    /// mutated UNDER this deal — an inventory suit sticker (changeSuitTo /
    /// changeSuitRandom) applied from a picker the flow presents over the
    /// deal screen. The web repaints its always-on strip the moment the swap
    /// lands ("the swap changed the deck composition → refresh the histogram
    /// now", index.html:30186); here the band repaints only on engine actions,
    /// so an external apply left the suit counts stale until the next guess.
    ///
    /// The new suit writes through to every live card the deal still holds
    /// (LiveCards are references, so the deck's `remainingSuitCounts` agrees),
    /// then the cached totals re-derive — a subset deal still folds up to the
    /// whole run deck (computeSittingOut's rule). Engine-side suit changes
    /// (a Base's setSuit) already write the campaign first, so the diff is a
    /// no-op on every ordinary refresh.
    private func revalidateComposition() {
        guard let engine, engine.board != nil else { return }
        let specs = Dictionary(uniqueKeysWithValues: campaign.getRunDeck().map { ($0.id, $0) })
        let liveCards = engine.deck.peekAll() + engine.board.piles.flatMap(\.cards)
        for card in liveCards {
            guard let spec = specs[card.id], !card.joker, spec.suit != card.suit else { continue }
            card.suit = spec.suit
            card.red = DeckManager.suits.first { $0.symbol == spec.suit }?.red ?? card.red
        }
        let liveSuit = liveSuitTotals(liveCards)
        let liveRank = liveRankTotals(liveCards)
        if isCampaign, let p = plan, p.subsetIds != nil {
            let fullSuit = suitTotals(campaign.getRunDeck())
            let fullRank = rankTotals(campaign.getRunDeck())
            for (k, v) in fullSuit { sittingOutSuit[k] = max(0, v - (liveSuit[k] ?? 0)) }
            for (k, v) in fullRank { sittingOutRank[k] = max(0, v - (liveRank[k] ?? 0)) }
            dealSuitTotals = fullSuit
            dealRankTotals = fullRank
        } else {
            sittingOutSuit = [:]
            sittingOutRank = [:]
            dealSuitTotals = liveSuit
            dealRankTotals = liveRank
        }
    }

    /// The histogram invalidation hook (v6.57): call the MOMENT an external
    /// path mutates the deck's composition (a suit sticker applied from
    /// inventory) so the band's counts refresh immediately, not on the next
    /// engine action. refreshHUD also revalidates on every campaign refresh,
    /// so any later repaint self-heals too.
    public func noteDeckCompositionChanged() {
        revalidateComposition()
        refreshAll()
    }

    private func computeSittingOut(plan p: DealPlan) {
        sittingOutRank = [:]
        sittingOutSuit = [:]
        guard !isZen, p.subsetIds != nil else { return }
        let full = campaign.getRunDeck()
        let fullRank = rankTotals(full), fullSuit = suitTotals(full)
        for (k, v) in fullRank { sittingOutRank[k] = max(0, v - (dealRankTotals[k] ?? 0)) }
        for (k, v) in fullSuit { sittingOutSuit[k] = max(0, v - (dealSuitTotals[k] ?? 0)) }
        dealRankTotals = fullRank
        dealSuitTotals = fullSuit
    }

    private func bootDebug(_ setup: Setup) {
        // SCREENSHOT HOOKS (EventCaptureUITests, v6.55): `-dealPillar <id>`
        // pins the debug deal's column-0 Pillar and `-dealSamePower <id>` its
        // equipped Same-Power — consent-prompt states (Second Wind, Link
        // Shuffler) that simctl can't reach through the launcher's dials.
        // `-dealBase <id>` (v6.57) does the same for the column-0 Base (the
        // coin-pop evidence fires a real paying Base).
        let d = UserDefaults.standard
        var pillars = setup.pillars
        if let pid = d.string(forKey: "dealPillar"), !pillars.isEmpty { pillars[0] = pid }
        var bases = setup.bases
        if let bid = d.string(forKey: "dealBase"), !bases.isEmpty { bases[0] = bid }
        debugBases = bases
        let samePower = d.string(forKey: "dealSamePower") ?? setup.samePower
        let layout = CampaignLayout.layoutForPiles(setup.pileCount, pillars: pillars)
        let specs = debugDeck(setup)
        dealSuitTotals = suitTotals(specs)
        dealRankTotals = rankTotals(specs)
        sittingOutRank = [:]
        sittingOutSuit = [:]
        dealEndRollsShown = []
        engine = GameEngine(
            deckSpecs: specs,
            pileCount: layout.piles,
            runConfig: RunConfig(cols: layout.cols,
                                 sameCharge: setup.sameCharge,
                                 samePower: samePower,
                                 samePowerVariant: campaign.samePowerVariant(samePower),
                                 pillarRankVariants: campaign.pillarRankVariants,
                                 shopRolls: campaign.shopRolls,
                                 noStickers: campaign.rules().noStickers))
        engine.on { [weak self] in self?.handle($0) }
        engine.telemetry = { TelemetryCore.shared.recordItemFire(klass: $0, id: $1, label: $2, values: $3) }
        engine.purseCoinsProvider = { [campaign] in campaign.getCoins() }
        engine.start(seedOverride: setup.seed)
        engine.startRun(pillars: pillars, bases: bases, samePower: .some(samePower))
        DebugEventLog.shared.resetEngineCursor()
        engine.run.rippleNeedsConsent = onRippleOffer != nil && !reduceMotion
        engine.run.secondWindNeedsConsent = onSecondWindOffer != nil && !reduceMotion
        engine.run.samePowerNeedsConsent = onPowerShuffleOffer != nil && !reduceMotion
        _ = specs
        scene.slotsVisible = true   // debug deals are campaign-shaped
        scene.isZen = false
        scene.buildBoard(pileCount: layout.piles, cols: layout.cols)
        scene.setPillars(pillars, bases: bases, dailySuits: engine.run.dailySuits,
                         rankShieldRank: rankShieldLabel())
        refreshAll()
        startCascade()
    }

    private func boot(plan p: DealPlan) {
        dealSuitTotals = suitTotals(p.deckForDeal)
        dealRankTotals = rankTotals(p.deckForDeal)
        computeSittingOut(plan: p)
        dealEndRollsShown = []
        // Pillars are read BEFORE the layout: a `columnPiles` Pillar (Fourth
        // Seat) widens its own column, so the board's real pile count is the
        // layout's, not the plan's.
        let equippedPillars = isZen
            ? [String?](repeating: nil, count: CampaignLayout.columnSlots) : campaign.columnPillars
        let layout = CampaignLayout.layoutForPiles(p.piles, pillars: equippedPillars)
        let pillars = Array(equippedPillars.prefix(layout.cols.count))
        let bases = isZen
            ? [String?](repeating: nil, count: layout.cols.count)
            : Array(campaign.columnBases.prefix(layout.cols.count))
        let samePower = isZen ? nil : campaign.getSamePower()
        engine = GameEngine(
            deckSpecs: p.deckForDeal,
            pileCount: layout.piles,
            runConfig: RunConfig(cols: layout.cols,
                                 sameCharge: isZen ? false : campaign.getSameCharge(),
                                 samePower: samePower,
                                 samePowerVariant: campaign.samePowerVariant(samePower),
                                 pillarRankVariants: campaign.pillarRankVariants,
                                 // SHOP-ROLLED values (v6.76, R2): the climb-locked
                                 // {rank}/{suit} every shopRoll item agreed on at the
                                 // shelf — the deal reads them from here.
                                 shopRolls: isZen ? [:] : campaign.shopRolls,
                                 noStickers: campaign.rules().noStickers,
                                 // Escape Hatch gates on this…
                                 isAmbush: p.isAmbush,
                                 // …and Last Resort seals itself on this.
                                 isBoss: p.isBoss))
        engine.on { [weak self] in self?.handle($0) }
        // TELEMETRY (v6.92): the engine's one instrumentation stream (recT)
        // feeds the remote sink through its long-dormant hook — item_fired,
        // base_fired and conditional_outcome all derive from this line.
        engine.telemetry = { TelemetryCore.shared.recordItemFire(klass: $0, id: $1, label: $2, values: $3) }
        // PAUPER family (v6.76): the engine reads the LIVE campaign purse through
        // this closure — never a snapshot (captures the shared campaign, not self,
        // so no retain cycle).
        engine.purseCoinsProvider = { [campaign] in campaign.getCoins() }
        if isCampaign { Telemetry.loadout(campaign) }
        // FULL-DECK composition hook (v6.78, web setCompositionHook parity):
        // campaign deals read composition off the LIVE owned deck — the deck
        // the histogram shows — even on subset deals. Zen keeps the deal-deck
        // fallback (its drill deck IS its whole world). Set BEFORE startRun:
        // Rank Shield and Crazy Eights read it there.
        if !isZen {
            engine.fullDeckProvider = { [campaign] in
                campaign.getRunDeck().map { DeckManager.toCard($0, data: GameData.shared) }
            }
        }
        engine.start(seedOverride: p.seed)
        engine.startRun(pillars: pillars, bases: bases, samePower: .some(samePower))
        DebugEventLog.shared.resetEngineCursor()
        // FIRST-RUN TUTORIAL: the guided Zen deal rearranges its opening (a 3
        // on pile 1, an Ace on the deck) BEFORE anything renders.
        if isZen { preDealArrange?(engine) }
        engine.run.rippleNeedsConsent = onRippleOffer != nil && !reduceMotion
        engine.run.secondWindNeedsConsent = onSecondWindOffer != nil && !reduceMotion
        engine.run.samePowerNeedsConsent = onPowerShuffleOffer != nil && !reduceMotion
        // MID-DEAL RESUME (anti-savescum): a kill mid-deal left an exact
        // snapshot. Restore it over the freshly-dealt engine (same plan, same
        // seed) and the deal CONTINUES — same piles, same remaining deck
        // order, same charges, same RNG position — instead of replaying as a
        // fresh attempt. The seed guard drops a stale blob from another deal
        // rather than corrupting this one.
        var restoredMidDeal = false
        if isCampaign, let blob = resumeMidDeal {
            if blob["run"]?["seed"]?.asNumber == Double(p.seed), engine.restoreSnapshot(blob) {
                restoredMidDeal = true
                pendingReviveCol = blob["uiPendingReviveCol"]?.asNumber.map(Int.init)
            }
            resumeMidDeal = nil
        }
        // RANK SHIELD (v6.78): adopt the deal's protected-rank pick as the
        // climb's incumbent (after any snapshot restore, so a resumed deal
        // adopts its true rank, not a fresh re-roll).
        if isCampaign { campaign.adoptRankShieldPick(engine.run.shopRolls["rankShield"]) }
        scene.slotsVisible = !isZen   // Zen collapses the artifact slot rows
        scene.isZen = isZen
        // Every boot deals out (first deal AND reshuffle re-deals route
        // here): hold the assist glow until the cascade lands.
        assistGate.dealOutStarted()
        scene.buildBoard(pileCount: layout.piles, cols: layout.cols)
        scene.setPillars(pillars, bases: bases, dailySuits: engine.run.dailySuits,
                         rankShieldRank: rankShieldLabel())
        refreshAll()
        onCheckpoint?(self)   // "run" durability point: a kill now resumes this deal
        if restoredMidDeal {
            // The board is already mid-deal: no composition reveal, no deal
            // cascade. Hand control straight back and re-surface any prompt
            // the kill interrupted (a paid bury, a shuffle offer, a ripple /
            // second-wind / shuffler consent, a revive target).
            interactionLocked = false
            // No cascade coming — the restored board is live right now, so
            // release the assist gate and repaint the glow it suppressed.
            assistGate.dealOutFinished()
            refreshBoard()
            drainPrompts()
            return
        }
        // DEAL REVEAL: the anonymous composition count, shown before EVERY
        // deal — full-deck ones included — and BEFORE the cascade, so the
        // count is read first and the piles land into a clear board.
        // Zen is a fixed drill, not a hand drawn from a deck you built — it has
        // no composition to state, so it deals straight away (as on the web).
        if isZen {
            startCascade()
        } else {
            interactionLocked = true   // held across the reveal AND the cascade
            scene.playDealReveal(inPlay: p.deckForDeal.count, total: p.fullDeckCount) { [weak self] in
                self?.startCascade()
            }
        }
    }

    /// The deal's first reshuffle is on the Queen (her Mulligan boon set this
    /// deal's redeal cost to 0): true only until the first guess or the first
    /// reshuffle spends the offer.
    private var freeRedealAvailable: Bool {
        isCampaign && redealCost == 0 && reshuffleIndex == 0
            && engine != nil && engine.run.totalGuesses == 0
    }

    /// The deal-out cascade: blank beat, then each pile's card flies in from
    /// the deck character. Control is handed over when the last card lands.
    private func startCascade() {
        interactionLocked = true
        assistGate.dealOutStarted()   // idempotent — boot armed it already
        scene.charReset()
        if !reduceMotion { Sound.shared.deal() }
        let n = engine.board.size
        let tops: [CardArt.Face?] = (0..<n).map { engine.board.top($0).map(CardArt.Face.init) }
        scene.dealCascade(tops: tops) { [weak self] in
            guard let self else { return }
            self.interactionLocked = false
            // The board is live: open the assist gate BEFORE the refresh so
            // the glow's first appearance is this post-deal repaint.
            self.assistGate.dealOutFinished()
            self.refreshAll()
            // The Queen's Mulligan announces itself once, at deal start.
            if self.freeRedealAvailable { self.scene.announceFreeRedeal() }
        }
    }

    /// The debug deal's deck: the campaign's 13-card start, topped up from the
    /// standard 52 to the dialled depth.
    private func debugDeck(_ setup: Setup) -> [CardSpec] {
        let owned = campaign.getRunDeck()
        guard setup.cardCount > owned.count else { return Array(owned.prefix(setup.cardCount)) }
        var out = owned
        let ownedIds = Set(owned.map(\.id))
        for spec in DeckManager.buildStandardDeck() where !ownedIds.contains(spec.id) {
            if out.count >= setup.cardCount { break }
            out.append(spec)
        }
        return out
    }

    // MARK: - Engine events → feedback

    private func handle(_ event: EngineEvent) {
        scene.breadcrumb = String(describing: event).prefix(60).description
        switch event {
        case .resolved(let index, let guess, let current, let drawn, let correct):
            handleResolved(index: index, guess: guess, current: current, drawn: drawn, correct: correct)

        case .pileKilled:
            // Stats only (web parity): the death VISUAL comes from the resolved
            // or base-fired handler that carries the context.
            if isCampaign, !campaign.isExhibition() { campaign.stats.bump("pilesLost") }

        case .guarded(let index, _, _, let drawn):
            Haptics2.medium()   // web: MEDIUM on every save
            animQueue.add(priority: 0) { [weak self] done in
                guard let self else { done(); return }
                self.scene.flyDraw(face: CardArt.Face(drawn), to: index) {
                    Sound.shared.place()
                    self.scene.pileLandPop(index)
                    Sound.shared.saveGuard()
                    self.scene.savedIndicator(at: index, label: "Guard")
                    self.scene.flyToDeck(face: CardArt.Face(drawn), from: index, delay: 0.12) { done() }
                }
            }

        case .secondWind(let index, _, _):
            Haptics2.medium()   // web: MEDIUM on every save
            Sound.shared.saveSecondWind()
            let swCol = engine?.run.pileColumns?[safe: index] ?? nil
            animQueue.add(priority: 1) { [weak self] done in
                self?.scene.savedIndicator(at: index, label: "Second Wind")
                // …and the verdict by the pillar itself (router batch 2).
                if let c = swCol { self?.scene.floatCueAtPillar("SAVED", col: c, color: CRT.phosphor) }
                done()
            }

        case .stickerConverted(let index, let cardId, let from, let to):
            // v6.85: a conditional sticker's failed bet — durable on the
            // campaign card (the sticker leaves, the curse arrives). Zen and
            // debug boards live on the LiveCard alone.
            if isCampaign { _ = campaign.convertStickerOnCard(cardId, from: from, to: to) }
            // v6.89: the card LANDS still wearing the OLD sticker — the
            // engine's truth converted at the landing, but the scene shows
            // the pre-conversion look until the queued morph beat (sound +
            // badge pop + red ring), the Flypaper timing's mirror.
            if let top = engine?.board.top(index), top.id == cardId {
                var shown = scene.badgeOverride(for: index) ?? top.stickers
                if let to { shown.removeAll { $0.type == to } }
                shown.append(StickerRecord(type: from))
                scene.setBadgeOverride(index, shown)
            }
            let morphLabel = to.flatMap { GameData.shared.stickerTypes.get($0)?.label }
            animQueue.add(priority: 1) { [weak self] done in
                guard let self else { done(); return }
                self.scene.run(.sequence([.wait(forDuration: 0.35), .run { [weak self] in
                    guard let self else { return }
                    self.scene.setBadgeOverride(index, nil)
                    self.refreshBoard()
                    Sound.shared.stripSticker()
                    self.scene.badgeMorphFlash(at: index)
                    if let morphLabel { self.scene.curseIndicator(at: index, label: morphLabel) }
                    done()
                }]))
            }
        case .coverCursed(let index, let cardId, let typeId, _):
            // v6.85 COVER PUNISH: the card that landed on Payout/Anchor
            // keeps its new curse for the rest of the climb.
            if isCampaign { _ = campaign.convertStickerOnCard(cardId, from: nil, to: typeId) }
            Sound.shared.stripSticker()
            if let label = GameData.shared.stickerTypes.get(typeId)?.label {
                animQueue.add(priority: 1) { [weak self] done in
                    self?.scene.curseIndicator(at: index, label: label)
                    done()
                }
            }
        case .pillarSticker(let col, let pileIndex, let cardId, let typeId):
            // Flypaper's catch: persist the sticker durably. v6.89: the card
            // LANDS bare — the catch (sound + badge pop + pulse) plays a
            // beat later, so the sticker visibly ARRIVES instead of the
            // card landing pre-dressed.
            _ = campaign.applyStickerDirect(cardId, typeId)
            _ = col
            if let top = engine?.board.top(pileIndex), top.id == cardId {
                var shown = scene.badgeOverride(for: pileIndex) ?? top.stickers
                if let i = shown.lastIndex(where: { $0.type == typeId }) { shown.remove(at: i) }
                scene.setBadgeOverride(pileIndex, shown)
            }
            animQueue.add(priority: 1) { [weak self] done in
                guard let self else { done(); return }
                self.scene.run(.sequence([.wait(forDuration: 0.35), .run { [weak self] in
                    guard let self else { return }
                    self.scene.setBadgeOverride(pileIndex, nil)
                    self.refreshBoard()
                    Sound.shared.sticker()
                    self.scene.badgeMorphFlash(at: pileIndex)
                    self.scene.goodPulse(at: pileIndex)
                    done()
                }]))
            }

        case .tieSafeSaved(let index):
            // v6.50: the sticker's tie-save gets the same SAVED idiom every
            // other save has (it used to land as a plain correct).
            // NO cue here (sound audit): the accompanying `.resolved` lands
            // through handleResolved, whose tieSafeSave branch already rings
            // `saveTieSafe()` for this same flip — a cue here would double it.
            Haptics2.medium()
            animQueue.add(priority: 1) { [weak self] done in
                self?.scene.savedIndicator(at: index, label: "Tie-Safe")
                done()
            }

        case .wildAceFlipped(let index, let col):
            // v6.50: the Ace playing LOW is announced at the pillar, so the
            // flip reads as the pillar's doing and not a rules glitch.
            Sound.shared.aceLow()
            animQueue.add(priority: 1) { [weak self] done in
                self?.scene.floatCueAtPillar("ACE LOW", col: col, color: CRT.phosphor)
                self?.scene.savedIndicator(at: index, label: "Wild Aces")
                done()
            }

        // ── CURSES ──────────────────────────────────────────────────────────
        case .curseFired(let index, _, _, let detail):
            // Shield Drain / Base Drain / Spoiler: a red verdict at the pile;
            // the drained state itself repaints on the next refresh (shield
            // alpha, base light, bonus tally).
            Haptics2.medium()
            Sound.shared.coinLoss()
            animQueue.add(priority: 1) { [weak self] done in
                self?.scene.curseIndicator(at: index, label: detail)
                done()
            }

        case .malfunction(let index, let cardLabel):
            // The named death: the pile shakes, and a red banner says exactly
            // which card blew it, so a "correct guess died" reads as the
            // curse and not a rules bug.
            Haptics2.heavy()
            Sound.shared.death()
            animQueue.add(priority: 0) { [weak self] done in
                guard let self else { done(); return }
                self.scene.shuffleWiggle(at: index)
                self.scene.curseIndicator(at: index, label: "MALFUNCTION")
                self.scene.showHelp(title: "MALFUNCTION",
                                    body: "\(cardLabel) malfunctioned. The correct guess killed the pile.")
                done()
            }

        case .pillarBlocked(let col):
            // Jammer: the pillar wanted to matter and couldn't.
            Sound.shared.blocked()
            animQueue.add(priority: 1) { [weak self] done in
                self?.scene.floatCueAtPillar("BLOCKED", col: col, color: CRT.suitRed)
                done()
            }

        case .cursePeeled(let index, let cardId, let types):
            // Peeler / Cleanse: the campaign identity loses the SAME
            // stickers the live card just lost, so the peel outlives the
            // deal. v6.91: the card keeps SHOWING them until a queued beat
            // — then the crumple sound (the strip cue, not the apply cue
            // this handler wrongly played before), a badge pop, and the
            // red PEELED ring, the deferred-reveal idiom.
            if isCampaign {
                var counts: [String: Int] = [:]
                for t in types { counts[t, default: 0] += 1 }
                for (t, n) in counts { _ = campaign.removeStickerInstances(cardId, t, n) }
            }
            if let top = engine?.board.top(index), top.id == cardId {
                var shown = scene.badgeOverride(for: index) ?? top.stickers
                shown.append(contentsOf: types.map { StickerRecord(type: $0) })
                scene.setBadgeOverride(index, shown)
            }
            animQueue.add(priority: 1) { [weak self] done in
                guard let self else { done(); return }
                self.scene.run(.sequence([.wait(forDuration: 0.35), .run { [weak self] in
                    guard let self else { return }
                    self.scene.setBadgeOverride(index, nil)
                    self.refreshBoard()
                    Sound.shared.stripSticker()
                    self.scene.badgeMorphFlash(at: index)
                    self.scene.curseIndicator(at: index, label: "PEELED")
                    done()
                }]))
            }

        case .sabotaged(let col, let kind, let itemId):
            // Saboteur: the destruction must stick on the campaign (the
            // engine already cleared its own copy), and the plaque must go
            // dark NOW, not at the next boot.
            if isCampaign {
                if kind == "pillar" {
                    campaign.setColumnPillar(col: col, typeId: nil)
                    _ = campaign.discardPillarFromInventory(itemId)
                } else {
                    campaign.setColumnBase(col: col, typeId: nil)
                    _ = campaign.discardBaseFromInventory(itemId)
                }
                onCheckpoint?(self)
            }
            Haptics2.heavy()
            Sound.shared.death()
            animQueue.add(priority: 0) { [weak self] done in
                guard let self else { done(); return }
                self.scene.floatCueAtPillar("DESTROYED", col: col, color: CRT.suitRed)
                self.scene.setPillars(self.isZen ? [] : self.campaign.columnPillars,
                                      bases: self.isZen ? [] : self.campaign.columnBases,
                                      dailySuits: self.engine?.run.dailySuits ?? nil,
                                      rankShieldRank: self.rankShieldLabel())
                done()
            }

        case .secondWindMiss(_, let col):
            animQueue.add(priority: 1) { [weak self] done in
                self?.scene.floatCueAtPillar("✕", col: col, color: CRT.suitRed)
                done()
            }

        case .sameSaved(let index, _, _, let drawn, _):
            Haptics2.medium()   // web: MEDIUM on same-saved
            scene.beginHold(index)
            animQueue.add(priority: 0) { [weak self] done in
                guard let self else { done(); return }
                self.scene.flyDraw(face: CardArt.Face(drawn), to: index) {
                    self.scene.endHold(index)
                    Sound.shared.place()
                    self.scene.pileLandPop(index)
                    Sound.shared.saveSameCharge()
                    self.scene.savedIndicator(at: index, label: "Same Charge")
                    done()
                }
            }

        case .sameBanked(let index, let charged):
            if charged {
                Haptics2.medium()   // web: MEDIUM on same-banked
                Sound.shared.sameBanked()
                scene.floatCue("＝ CHARGED", at: index, color: CRT.gold)
            }

        case .stickerCoins(let index, _, let amount):
            if amount != 0 {
                scene.floatCue(amount > 0 ? "+\(Int(amount))" : "−\(Int(abs(amount)))",
                               at: index, color: amount > 0 ? CRT.gold : CRT.suitRed)
                // The audible coin ring, a beat after the resolution blip
                // (throttling lives in the engine's own emit cadence).
                let gain = amount > 0
                scene.run(.sequence([.wait(forDuration: 0.11), .run {
                    if gain { Sound.shared.coinBonus() } else { Sound.shared.coinLoss() }
                }]))
            } else {
                scene.floatCue("+0", at: index, color: CRT.muted)
            }

        case .buried(let index, let count, _):
            if isCampaign, !campaign.isExhibition() { campaign.stats.bump("cardsBuried", count) }
            animQueue.add(priority: 1) { [weak self] done in
                guard let self else { done(); return }
                self.scene.flyFaceDown(to: index) {
                    Sound.shared.bury()
                    self.scene.buryTuck(at: index, count: count)
                    done()
                }
            }

        case .donateEqualized(let index, let moves):
            // Donate (v6.86): the equalize used to happen silently between
            // two repaints — the counts just changed. The buried cards now
            // visibly fly pile → pile (face down, composition stays hidden)
            // behind the landing flight, with a riffle cue and the float.
            scene.floatCue("DONATE", at: index, color: CRT.gold)
            if !moves.isEmpty {
                let capped = Array(moves.prefix(8))
                animQueue.add(priority: 1) { [weak self] done in
                    guard let self else { done(); return }
                    Sound.shared.shufflePile()
                    var landed = 0
                    let fin = { [weak self] in
                        landed += 1
                        if landed == capped.count { self?.refreshBoard(); done() }
                    }
                    for (k, m) in capped.enumerated() {
                        self.scene.run(.sequence([.wait(forDuration: Double(k) * 0.09), .run {
                            self.scene.flyPileToPile(from: m.from, to: m.to) { fin() }
                        }]))
                    }
                }
            }

        case .finalCutPurged(let col, let cardId):
            // FINAL CUT (v6.88): the killer leaves the campaign deck for
            // good — the durable write happens HERE (the engine reports).
            if isCampaign { _ = campaign.removeDeckCard(cardId) }
            Sound.shared.removeCard()
            if let p = firstPile(inColumn: col) {
                animQueue.add(priority: 1) { [weak self] done in
                    self?.scene.floatCue("PURGED", at: p, color: CRT.suitRed)
                    done()
                }
            }

        case .trapdoorDropped(let index, let count):
            // Trapdoor (v6.86): the drop was invisible — the pile count just
            // shrank mid-landing. Each dropped card now slips from the pile
            // back into the deck, face down, under the curse's red ring.
            animQueue.add(priority: 1) { [weak self] done in
                guard let self else { done(); return }
                self.scene.curseIndicator(at: index, label: "TRAPDOOR")
                Sound.shared.shuffleDeck()
                for k in 0..<count {
                    self.scene.flyToDeck(face: nil, from: index, delay: 0.1 + Double(k) * 0.095)
                }
                self.scene.run(.sequence([
                    .wait(forDuration: 0.1 + Double(count) * 0.095 + 0.35),
                    .run { done() },
                ]))
            }

        case .pillarFired(let col, let effect, _, let amount, let moves):
            scene.pulseColumn(col, base: false)
            if effect == "shuffler" {
                // A shuffle the player can SEE (Shuffler Pillar / Diamond Snob /
                // Diamond Ripple). Every firer is COLUMN-scoped, so only that
                // column wiggles — the whole board doing the dance claimed
                // piles the engine never touched (router batch).
                Sound.shared.shufflePile()
                for i in alivePiles() where engine?.run.pileColumns?[safe: i] == col {
                    scene.shuffleWiggle(at: i)
                }
            } else {
                Sound.shared.pillarFire()
            }
            if amount != 0, let p = firstPile(inColumn: col) {
                scene.floatCue(amount > 0 ? "+\(Int(amount))" : "−\(Int(abs(amount)))",
                               at: p, color: amount > 0 ? CRT.gold : CRT.suitRed)
            }
            if effect == "diamondDistribution", !moves.isEmpty {
                let capped = Array(moves.prefix(8))
                animQueue.add(priority: 1) { [weak self] done in
                    guard let self else { done(); return }
                    var landed = 0
                    let fin = { [weak self] in
                        landed += 1
                        if landed == capped.count { self?.refreshBoard(); done() }
                    }
                    for (k, m) in capped.enumerated() {
                        self.scene.run(.sequence([.wait(forDuration: Double(k) * 0.09), .run {
                            self.scene.flyPileToPile(from: m.from, to: m.to) { fin() }
                        }]))
                    }
                }
            }

        case .cardDuplicated(let cardId, _):
            // Copy the card into the campaign inventory (pack tray).
            if isCampaign, campaign.duplicateCard(cardId) != nil {
                Sound.shared.duplicate()
                if let sel = scene.currentSelection { scene.floatCue("DUPLICATED", at: sel, color: CRT.gold) }
                onCheckpoint?(self)
            }

        case .baseFired(let res):
            handleBaseFired(res)

        case .samePower(let res):
            Sound.shared.samePower()
            // Any sticker the power put on a board card is written through to
            // the CAMPAIGN card, so it survives the deal (Sticker Spray).
            for s in res.stickersApplied { _ = campaign.applySticker(s.cardId, s.typeId) }
            // RANK FLOOD (v6.76): the permanent rank rewrites ride the same
            // durable-write contract as a Base's valueApplied (Chorus, Rank
            // Setter) — without this they vanished when the deal ended.
            for r in res.rankApplied { _ = campaign.randomizeCard(r.cardId, to: r.value) }
            // A coin-granting power (linkCoins: +value per alive pile) carries
            // its total in res.amount — float the grant on the hub so it pops
            // like every other coin source (v6.57 resource pops).
            if res.effect == "linkCoins", res.amount > 0 {
                scene.floatCue("+\(res.amount)", at: res.hub, color: CRT.gold)
            }
            animQueue.add(priority: 1) { [weak self] done in
                self?.scene.powerFeedback(hub: res.hub, targets: res.targets, label: res.label)
                done()
            }

        case .reviveOffer(let col, _):
            // Surfaced after the triggering guess settles (drainPrompts).
            pendingReviveCol = col

        case .secondWindOffer(let index, _, _, _, let drawn, _):
            // v6.56 SEQUENCING: the killer's draw and the dying beat play
            // FIRST; the save prompt surfaces only once the card has landed
            // (drainPrompts gates on secondWindDrawInFlight). Reduced motion
            // skips the flight, so nothing gates there.
            guard !reduceMotion else { break }
            flySecondWindKiller(drawn: drawn, to: index)

        case .rollResult(let r):
            // v6.57 probability feedback, relocated v6.74: every item %-roll
            // announces its outcome ON THE ITEM that rolled (the pillar
            // plaque / the sticker chip / the HUD power chip) — a one-shot
            // one-word verdict, hit AND miss (on a hit the effect's own cue
            // follows; on a miss this is the whole story). Priority 0 keeps
            // the engine's emission order: the roll reports BEFORE its
            // effect's cue.
            //
            // A COLUMN-ONLY roll (no pile) is a deal-end scoring flip
            // (Gambler). The live-bonus read recomputes the scoring payout on
            // every refresh, which would re-roll (and re-float) mid-deal — so
            // column-only rolls render only once the deal is actually over,
            // and only ONCE per item: finish() re-reads the payout for the
            // reward line and the outcome fold, and each read re-flips.
            guard r.index != nil || (isOver && !dealEndRollsShown.contains(r.id)) else { break }
            if r.index == nil { dealEndRollsShown.insert(r.id) }
            floatRollIndicator(r)

        case .revived(_, let index):
            scene.floatCue("REVIVED", at: index, color: CRT.phosphor)
            Sound.shared.revive()
            animQueue.add(priority: 1) { [weak self] done in
                self?.scene.goodPulse(at: index)
                self?.scene.refreshWeb()
                done()
            }

        case .won:
            finish(win: true)

        case .lost:
            if awaitingDeathFinish {
                pendingFinish = { [weak self] in self?.finish(win: false) }
            } else {
                finish(win: false)
            }

        default:
            break
        }
    }

    private func handleResolved(index: Int, guess: Guess, current: LiveCard,
                                drawn: LiveCard, correct: Bool) {
        let fatal = !correct && engine.board.aliveCount() == 0
        awaitingDeathFinish = fatal
        // The web's lastResolvedDraw: stamped on EVERY resolution; the loss
        // screens read the guess that would have survived the fatal one.
        lastSurvivingWord = drawn.value > current.value ? "higher"
            : (drawn.value < current.value ? "lower" : "same")
        if fatal { PhaseOverlayView.survivingGuessWord = lastSurvivingWord }
        // The drawn card has landed on the pile — bank its suit. Jokers and
        // Blanks belong to no suit and are skipped.
        if !drawn.joker, !drawn.blank { suitsLanded[drawn.suit, default: 0] += 1 }
        let tieSafeSave = correct && guess != .same && drawn.value == current.value
        let fatalTie = !correct && guess != .same && drawn.value == current.value

        // First guess: the run counts as played (campaign), or the Zen game
        // counts (its own store). Exhibition banks nothing.
        if isZen {
            onZenGuess?(correct)
        } else if isCampaign, !campaign.isPlayedCounted() {
            campaign.markPlayed()
            if !campaign.isExhibition() {
                var s = campaign.stats.get()
                s.gamesPlayed += 1
                campaign.stats.put(s)
            }
            onCheckpoint?(self)
        }
        if isCampaign, !campaign.isExhibition() {
            var deltas: [String: Int] = [:]
            if guess == .same { deltas["samesCalled"] = 1; if correct { deltas["correctSames"] = 1 } }
            if drawn.joker || current.joker { deltas["jokersPlayed"] = 1 }
            campaign.stats.bumpAll(deltas)
        }

        if correct && guess == .same { scene.charReact(.happy) }
        else if correct { scene.charReact(.glad) }
        else { scene.charReact(.sad) }

        let land: () -> Void = { [weak self] in
            guard let self else { return }
            self.scene.endHold(index, suppressDead: !correct)
            // The PHYSICAL layer first — paper on felt — then the outcome tone
            // rides on top of it.
            Sound.shared.place()
            self.scene.pileLandPop(index)
            Haptics2.land(correct: correct)
            if correct {
                if tieSafeSave {
                    self.scene.savedIndicator(at: index, label: "Tie-Safe")
                    Sound.shared.saveTieSafe()
                } else {
                    self.scene.goodPulse(at: index)
                    Sound.shared.good()
                }
                self.scene.refreshWeb()
                // COMPOUND pays live (recT only, no dedicated engine event) —
                // pop the grant so EVERY coin source floats (v6.57 resource
                // pops). `current` is a LiveCard reference: the engine has
                // already bumped compoundHits, so the pay is (hits−1)×step,
                // read from the registry — never a hardcoded number.
                if current.stickers.contains(where: { $0.type == "compound" }) {
                    let step = GameData.shared.stickerTypes.get("compound")?.num("step", 1) ?? 1
                    let pay = Double(current.compoundHits - 1) * step
                    if pay > 0 { self.scene.floatCue("+\(Int(pay))", at: index, color: CRT.gold) }
                }
                if drawn.joker {
                    Sound.shared.joker()
                    self.scene.floatCue("★", at: index, color: CRT.gold)
                }
            } else {
                Sound.shared.death()
                // LAST COIN (deathBounty): the killing card pays its
                // consolation with no dedicated engine event — float it as
                // the pile dies (v6.57 resource pops).
                let bounties = drawn.stickers.filter { $0.type == "deathBounty" }.count
                if bounties > 0 {
                    let each = GameData.shared.stickerTypes.get("deathBounty")?.value ?? 0
                    let amt = Double(bounties) * each
                    if amt > 0 { self.scene.floatCue("+\(Int(amt))", at: index, color: CRT.gold) }
                }
                if fatalTie {
                    self.scene.shouldaNudge(at: index)
                    self.scene.run(.sequence([.wait(forDuration: 0.34), .run { Sound.shared.sameMiss() }]))
                }
                self.scene.playDeathSequence(at: index) { [weak self] in
                    guard let self else { return }
                    if fatal {
                        let beat = fatalTie ? 1.1 : 0.36
                        self.scene.run(.sequence([.wait(forDuration: beat), .run {
                            self.flushPendingFinish()
                        }]))
                    }
                }
            }
        }

        if reduceMotion {
            land()
            if fatal { flushPendingFinish() }
            return
        }
        // A declined Second Wind replays `.resolved` for the killer the offer
        // already flew to the pile (v6.56) — land it in place, never fly twice.
        if skipResolvedFlightFor == index {
            skipResolvedFlightFor = nil
            land()
            return
        }
        scene.beginHold(index)
        animQueue.add(priority: 0) { [weak self] done in
            guard let self else { done(); return }
            self.scene.flyDraw(face: CardArt.Face(drawn), to: index) {
                land()
                done()
            }
        }
    }

    private func handleBaseFired(_ res: BaseResult) {
        scene.pulseColumn(res.col, base: true)
        if let gained = res.gained, gained != 0, let p = firstPile(inColumn: res.col) {
            scene.floatCue(gained > 0 ? "+\(Int(gained))" : "−\(Int(abs(gained)))",
                           at: p, color: gained > 0 ? CRT.gold : CRT.suitRed)
        }
        // Every base activation announces itself in the arcane family; the
        // destructive ones swap in the heavier destroy-family cue below.
        switch res.effect {
        case "kamikaze", "heartDemolish", "demolish": break
        case "reviveBase": Sound.shared.reviveBase()
        default: Sound.shared.baseFire()
        }
        switch res.effect {
        case "kamikaze":
            Sound.shared.pileDestroyed()
            if let i = res.index { scene.playImmediateDeath(at: i) }
        case "heartDemolish":
            Sound.shared.pileDestroyed()
            for i in res.destroyedPiles ?? [] { scene.playImmediateDeath(at: i) }
        case "reviveBase":
            if let i = res.index {
                scene.goodPulse(at: i)
                let count = res.returnedCount ?? 0
                if count > 0 {
                    animQueue.add(priority: 1) { [weak self] done in
                        guard let self else { done(); return }
                        for k in 0..<count {
                            self.scene.flyToDeck(face: nil, from: i, delay: 0.43 + Double(k) * 0.095)
                        }
                        self.scene.run(.sequence([
                            .wait(forDuration: 0.43 + Double(count) * 0.095 + 0.3),
                            .run { done() },
                        ]))
                    }
                }
            }
        case "demolish":
            // The Base destroyed a Pillar for good — clear the campaign binding.
            Sound.shared.demolish()
            if isCampaign, let dcol = res.demolishedCol {
                campaign.setColumnPillar(col: dcol, typeId: nil)
                if let old = res.demolishedPillar { _ = campaign.discardPillarFromInventory(old) }
                scene.setPillars(campaign.columnPillars, bases: campaign.columnBases,
                                 dailySuits: engine?.run.dailySuits ?? nil,
                                 rankShieldRank: rankShieldLabel())
            }
        case "shuffleColumn", "evenOut":
            // A column being reshuffled is still a SHUFFLE — the riffle's
            // little sibling, layered over the base's own fire cue. Upheaval
            // gets a visible CHURN (rock + hop): a quiet goodPulse read as
            // "nothing happened" whenever the same card stayed on top.
            if res.effect == "shuffleColumn" { Sound.shared.shufflePile() }
            if res.effect == "evenOut", let mv = res.movedCards, !mv.isEmpty {
                // BALLAST (v6.88): board-wide now — the buried cards visibly
                // fly pile → pile, the Donate idiom, identities hidden.
                let capped = Array(mv.prefix(8))
                animQueue.add(priority: 1) { [weak self] done in
                    guard let self else { done(); return }
                    Sound.shared.shufflePile()
                    var landed = 0
                    let fin = { [weak self] in
                        landed += 1
                        if landed == capped.count { self?.refreshBoard(); done() }
                    }
                    for (k, m) in capped.enumerated() {
                        self.scene.run(.sequence([.wait(forDuration: Double(k) * 0.09), .run {
                            self.scene.flyPileToPile(from: m.from, to: m.to) { fin() }
                        }]))
                    }
                }
            } else {
                for i in pilesInColumn(res.col) where engine.board.isActive(i) {
                    if res.effect == "shuffleColumn" { scene.shuffleChurn(at: i) }
                    else { scene.goodPulse(at: i) }
                }
            }
        case "randomSticker":
            if let s = res.stickerApplied {
                Sound.shared.sticker()   // the application itself, over the base's fire cue
                scene.goodPulse(at: s.pileIndex)
            }
        case "clubTell":
            // The oracle ARMS tell markers engine-side (run.tellPiles); the
            // per-pile hint chips repaint in the refreshAll below and stay up
            // until the next draw. A one-second float was the whole show in
            // v6.51 and it read as nothing happening — now the marked piles
            // just pulse to say "look here".
            for t in res.tells ?? [] { scene.goodPulse(at: t.pile) }
        case "sameTell":
            // Same Tell with no match floats nothing — the silence IS the answer.
            if let dir = res.tellDirection, let pile = res.tellPile {
                let glyph = dir == .higher ? "▲ HIGHER" : dir == .lower ? "▼ LOWER" : "= SAME"
                scene.floatCue(glyph, at: pile,
                               color: dir == .same ? CRT.gold : CRT.phosphor)
            }
        case "emptyPurse":
            // The purse is campaign state — drained here, shown draining.
            // Drain EXACTLY what the engine counted with (v6.74), so the
            // spend can never disagree with the peek count.
            let spent = res.purseSpent ?? campaign.getCoins()
            if spent > 0 {
                _ = campaign.spendCoins(spent)
                Sound.shared.coinLoss()   // coins leaving must fall (sound audit)
            }
            if let pp = firstPile(inColumn: res.col) {
                scene.floatCue("−\(spent) ◉", at: pp, color: CRT.suitRed)
            }
        case "lastResort":
            // Self-destructs and takes the neighbouring base(s) with it: an
            // edge column claims the middle, the middle claims both edges.
            if isCampaign {
                let victims = [res.col] + (res.col == 1 ? [0, 2] : [1])
                for c in victims where campaign.columnBase(c) != nil {
                    campaign.setColumnBase(col: c, typeId: nil)
                }
                scene.setPillars(campaign.columnPillars, bases: campaign.columnBases,
                                 dailySuits: engine?.run.dailySuits ?? nil,
                                 rankShieldRank: rankShieldLabel())
            }
            if let target = res.index {
                Sound.shared.bury()
                scene.buryTuck(at: target, count: min(8, res.buried ?? 0))
            }
        case "setValue", "setSuit", "chorus":
            for i in pilesInColumn(res.col) where engine.board.isActive(i) {
                scene.goodPulse(at: i)
            }
        case "sacrifice":
            // The pile dies WITH its top card purged from the deck for good —
            // the same immediate-death idiom Kamikaze uses, then the durable
            // write-back below strikes the identity from the campaign deck.
            Sound.shared.pileDestroyed()
            if let i = res.index { scene.playImmediateDeath(at: i) }
        case "devilsDeal":
            // The bonus doubling floats through the generic `gained` path
            // above; here the curse's arrival gets its sticker cue + pulse.
            if let s = res.stickerApplied {
                Sound.shared.sticker()
                scene.goodPulse(at: s.pileIndex)
            }
        case "cleanseColumn":
            // Each peel already announced itself through `.cursePeeled` (the
            // durable write-back rides that event) — the plaque pulse and the
            // count are the whole summary.
            if let n = res.cleansed, n > 0, let p = firstPile(inColumn: res.col) {
                scene.floatCue("CLEANSED ×\(n)", at: p, color: CRT.phosphor)
            }
        case "diamondBoost":
            // v6.78: column-wide — every boosted ♦ pile pulses.
            for i in res.boostedPiles ?? [] { scene.goodPulse(at: i) }
        case "purgeDiscount":
            // v6.93: the post-fire OK popup is gone — the pre-fire confirm
            // already quoted the cut (liveBaseDescription's ladder preview),
            // so the fire just pulses the column and banks the discount (the
            // write-back below applies it to the campaign's Purge pricing).
            if let cut = res.purgePriceCut, cut > 0, let p = firstPile(inColumn: res.col) {
                Sound.shared.coinBonus()
                scene.floatCue("PURGE −◉\(cut)", at: p, color: CRT.phosphor)
            }
        default:
            break
        }
        // Durable card modifications last the REST OF THE RUN — write the same
        // change onto the persistent campaign card (web parity).
        if isCampaign {
            for v in res.valueApplied ?? [] { _ = campaign.randomizeCard(v.cardId, to: v.value) }
            for s in res.suitApplied ?? [] { _ = campaign.setCardSuit(s.cardId, to: s.suit) }
            if let s = res.stickerApplied {
                // DEVIL'S DEAL (v6.76): the curse is ENGINE-granted (rolled off
                // the shared curse pool) — it never passed through the sticker
                // inventory, so the write-back must not consume one
                // (applyStickerDirect — the Flypaper contract, v6.55).
                if res.effect == "devilsDeal" { _ = campaign.applyStickerDirect(s.cardId, s.typeId) }
                else { _ = campaign.applySticker(s.cardId, s.typeId) }
            }
            // SACRIFICE (v6.76): the purged top card leaves the campaign deck
            // permanently — the pile's death above was only the board half.
            if let purged = res.purgedCardId { _ = campaign.removeDeckCard(purged) }
            // PURGE COUPON (v6.76): the climb-permanent Purge price cut — the
            // campaign owns all pricing; the floor re-derives from the def.
            if let cut = res.purgePriceCut {
                campaign.addPurgeDiscount(cut)
            }
            onCheckpoint?(self)
        }
        // A Base that pays (Heart Tax, Heart Demolish …) has already folded its
        // coins into `run.bonusCoins`, so the TOP reward line is stale until the
        // HUD repaints. The web repaints from the `base-fired` handler itself
        // (renderHud) precisely so every activation path is covered — do the
        // same here rather than trusting each caller to follow up.
        refreshAll()
    }

    private func flushPendingFinish() {
        guard let f = pendingFinish else { return }
        pendingFinish = nil
        f()
    }

    private func firstPile(inColumn col: Int) -> Int? {
        engine.run.pileColumns?.firstIndex(of: col)
    }

    private func pilesInColumn(_ col: Int) -> [Int] {
        guard let cols = engine.run.pileColumns else { return [] }
        return cols.enumerated().filter { $0.element == col }.map(\.offset)
    }

    private func finish(win: Bool) {
        // TELEMETRY (v6.92): a deal ending with a CHARGED base never fired —
        // the "they don't know bases exist" signal. Read here, while the
        // engine is alive (DealOutcome never carried basesUsed).
        if isCampaign {
            TelemetryCore.shared.recordUnfiredBases(bases: engine?.run.bases,
                                                    used: engine?.run.basesUsed)
        }
        isOver = true
        interactionLocked = true
        scene.crtFlicker()               // the ONE-SHOT flicker, deal end only
        scene.setSelected(nil)
        scene.charReact(win ? .celebrate : .sad)
        Haptics2.dealEnd(won: win)
        // WIN MUSIC timed to the dance; a run clear gets the grand tune.
        if !reduceMotion {
            if win {
                let isRunBossWin = isCampaign && campaign.currentNode().map {
                    $0.type == "boss" && campaign.isRunBoss($0.id)
                } == true
                if isRunBossWin { Sound.shared.runClear() } else { Sound.shared.dealWon() }
            } else {
                Sound.shared.dealLost()
            }
        }
        refreshAll()
        let payout = win ? currentPayout() : 0
        if case .debug = mode {
            scene.showResultBanner(win ? "DEAL CLEARED · +\(Int(payout))" : "DEAL LOST", win: win)
            writeDealReceipt(win: win, payout: payout)
        }
        onFinish?(win, Int(payout), currentScore())
        onOutcome?(outcome(win: win))
    }

    private func outcome(win: Bool) -> DealOutcome {
        DealOutcome(
            won: win,
            cardsDrawn: engine.run.cardsDrawn,
            correctGuesses: engine.run.correctGuesses,
            totalGuesses: engine.run.totalGuesses,
            aliveCount: engine.board.aliveCount(),
            minAliveCards: engine.board.minAliveCards(),
            extraCoinUnits: engine.board.extraCoinUnits(),
            pillarPayout: engine.pillarPayout(),
            bonusCoins: engine.run.bonusCoins,
            bonusEvents: engine.run.bonusEvents.keys.map { ($0, engine.run.bonusEvents[$0]) },
            sameCharge: engine.sameCharge,
            compoundUpdates: engine.run.compoundUpdates,
            snowballUpdates: engine.run.snowballUpdates,
            stickerPeels: engine.run.stickerPeels,
            survivingGuessWord: win ? nil : lastSurvivingWord,
            suitsLanded: suitsLanded)
    }

    /// Debug path result: (won, coins, score).
    public var onFinish: ((Bool, Int, Int) -> Void)?
    /// Campaign/Zen path: the full outcome for the run-end fold.
    public var onOutcome: ((DealOutcome) -> Void)?
    /// A Zen guess resolved (correct?) — ZenStats tallies live in the flow.
    public var onZenGuess: ((Bool) -> Void)?
    /// FIRST-RUN TUTORIAL: rearrange the freshly-dealt Zen opening before the
    /// first render (nil for every ordinary deal).
    public var preDealArrange: ((GameEngine) -> Void)?
    /// Durability points ("run" checkpoints) — the flow persists here.
    public var onCheckpoint: ((DealController) -> Void)?
    /// MID-DEAL PERSISTENCE (anti-savescum): fired from refreshAll with the
    /// engine's exact-state snapshot after every player action. The capture is
    /// a cheap main-thread value copy; the flow does the JSON encode and the
    /// storage write on a background queue (STKPERF1: never a synchronous
    /// per-tap storage write).
    public var onActionSnapshot: (([String: JSONValue]) -> Void)?
    /// A snapshot to resume from, set before sceneReady(). boot() consumes it
    /// once; a reshuffle's re-boot therefore always deals fresh.
    public var resumeMidDeal: [String: JSONValue]?

    /// The persisted-deal identity for the save blob.
    public var currentSeed: UInt32 { engine.run.seed }
    public var currentPlan: DealPlan? { plan }
    public var currentRedealCost: Double { redealCost }

    private func writeDealReceipt(win: Bool, payout: Double) {
        guard case .debug(let setup) = mode else { return }
        let f = scene.frameStats
        let receipt: [String: Any] = [
            "won": win,
            "piles": setup.pileCount,
            "cards": setup.cardCount,
            "seed": Int(setup.seed),
            "deck": setup.deckId,
            "items": setup.pillars.contains { $0 != nil },
            "coins": Int(payout),
            "score": currentScore(),
            "guesses": engine.run.totalGuesses,
            "correct": engine.run.correctGuesses,
            "alivePiles": engine.board.aliveCount(),
            "deckLeft": engine.deck.remaining(),
            "frames": f.count,
            "meanMS": (f.meanMS * 100).rounded() / 100,
            "worstMS": (f.worstMS * 100).rounded() / 100,
            "fps": (f.fps * 10).rounded() / 10,
            "framesOver60HzBudget": f.over60,
            "hitches": scene.hitchLog,
            "device": UIDevice.current.model + " / iOS " + UIDevice.current.systemVersion,
        ]
        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
              let data = try? JSONSerialization.data(withJSONObject: receipt,
                                                     options: [.sortedKeys, .prettyPrinted])
        else { return }
        try? data.write(to: dir.appendingPathComponent("deal-receipt.json"))
    }

    /// Ripple (v6.85): the piles the pending suitRipple offer would shuffle —
    /// every alive pile whose top matches the landing pile's top suit. The
    /// prompt highlights exactly what the engine will touch on accept.
    /// SHUFFLER (v6.91): the piles the pending offer would shuffle — every
    /// OTHER alive pile in the pillar's column.
    public func shufflerTargets(landing index: Int, col: Int) -> [Int] {
        guard let engine else { return [] }
        return pilesInColumn(col).filter { $0 != index && engine.board.isActive($0) }
    }

    public func rippleTargets(for index: Int) -> [Int] {
        guard let engine, let suit = engine.board.top(index)?.suit else { return [index] }
        return (0..<engine.board.size).filter {
            engine.board.isActive($0) && CardRules.matchesSuit(engine.board.top($0), suit)
        }
    }

    // MARK: - Player actions

    public func select(pile: Int) {
        guard !interactionLocked, !isOver else { return }
        guard engine.board.isActive(pile) else { return }
        // MAGNET curse: while any magnet tops the board, only magnet piles
        // take a selection — a refused tap pulses the pull so the refusal
        // reads as the curse, not a dead screen.
        let magnets = engine.magnetPiles()
        if !magnets.isEmpty, !magnets.contains(pile) {
            for m in magnets { scene.curseIndicator(at: m, label: "MAGNET") }
            Sound.shared.tap()
            return
        }
        let selecting = scene.currentSelection != pile
        // PILE SELECTION: the light UI tick. Deselecting is a non-event and
        // stays silent so tapping around the felt never chatters.
        if selecting { Sound.shared.tap() }
        scene.setSelected(selecting ? pile : nil)
        if selecting { scene.charLookAt(pile: pile) } else { scene.charReleaseLook() }
        refreshControls()
    }

    public func guess(_ g: Guess, pile: Int? = nil) {
        guard !interactionLocked, !isOver, !promptActive, !secondWindDrawInFlight else { return }
        guard let target = pile ?? scene.currentSelection else { return }
        guard engine.board.isActive(target), !engine.deck.isEmpty else { return }
        // The DIRECTIONAL guess cue lives here, not in the button handler, so a
        // swipe and a button press sound identical. Rises / holds / falls with
        // the call itself.
        switch g {
        case .higher: Sound.shared.guessHigher()
        case .same: Sound.shared.guessSame()
        case .lower: Sound.shared.guessLower()
        }
        engine.guess(target, g)
        // Deselect BEFORE the prompts drain: an action offer highlights its
        // target piles, and the old order cleared that highlight the instant
        // it was set — "shuffle the highlighted pile" with nothing lit.
        if !isOver { scene.setSelected(nil); scene.charReleaseLook() }
        drainPrompts()
        refreshAll()
    }

    // MARK: - In-deal offers (the paid-bury / shuffle / donate prompts)

    /// Ask the player a tribute question: (offer, answer-callback).
    public var onTributeOffer: ((TributeOffer, @escaping (Bool) -> Void) -> Void)?
    /// Ask about an optional post-landing action (shuffle / donate).
    public var onActionOffer: ((PendingAction, @escaping (Bool) -> Void) -> Void)?
    /// Diamond Ripple consent: (the piles it would shuffle, answer-callback).
    public var onRippleOffer: (([Int], @escaping (Bool) -> Void) -> Void)?
    /// Second Wind consent (v6.55): (dying pile, cards the save recycles,
    /// answer-callback) — save it or let it die.
    public var onSecondWindOffer: ((Int, Int, @escaping (Bool) -> Void) -> Void)?
    /// Link Shuffler consent (v6.55): (power label, alive piles it would
    /// shuffle, answer-callback).
    public var onPowerShuffleOffer: ((String, Int, @escaping (Bool) -> Void) -> Void)?
    /// Revive targeting: (dead piles, fire(target?) — nil = skip).
    public var onReviveOffer: (([Int], @escaping (Int?) -> Void) -> Void)?
    private var promptActive = false
    private var pendingReviveCol: Int?
    /// v6.56 sequencing: a parked Second Wind offer's killer card is still
    /// flying to the pile. The save prompt waits for the landing, and guesses
    /// are locked while the pile's fate is visibly undecided.
    private var secondWindDrawInFlight = false
    /// A DECLINED Second Wind replays `.resolved` for the killer the offer
    /// already flew to the pile — the pile index whose re-flight to skip.
    private var skipResolvedFlightFor: Int?

    /// Surface queued offers ONE at a time; with no UI handler installed
    /// (debug/auto-play) the deterministic default is DECLINE — never silently
    /// spend the player's coins on an offer they were never shown.
    private func drainPrompts() {
        guard !isOver else {
            while !engine.run.pendingTributes.isEmpty { engine.answerTribute(false) }
            while !engine.run.pendingActions.isEmpty { engine.answerAction(false) }
            // Choices the deal-end cut short resolve the web's way (auto).
            engine.answerRipple(true)
            engine.answerSecondWind(true)
            engine.answerPowerShuffle(true)
            scene.setRippleTargets([])
            return
        }
        if let t = engine.run.pendingTributes.first {
            guard let handler = onTributeOffer, !reduceMotion else {
                engine.answerTribute(false)
                drainPrompts()
                return
            }
            promptActive = true
            handler(t) { [weak self] accept in
                guard let self else { return }
                self.promptActive = false
                self.engine.answerTribute(accept)
                if accept { Sound.shared.coinLoss() }
                self.drainPrompts()
                self.refreshAll()
            }
            return
        }
        if let a = engine.run.pendingActions.first {
            guard let handler = onActionOffer, !reduceMotion else {
                engine.answerAction(false)
                drainPrompts()
                return
            }
            promptActive = true
            handler(a) { [weak self] accept in
                guard let self else { return }
                self.promptActive = false
                self.engine.answerAction(accept)
                if accept, a.kind == "shuffle" {
                    Sound.shared.shufflePile()   // one pile, not the whole deck
                    self.scene.shuffleWiggle(at: a.index)
                }
                if accept, a.kind == "pillarShuffle", let col = a.target {
                    Sound.shared.shufflePile()
                    for i in self.shufflerTargets(landing: a.index, col: col) {
                        self.scene.shuffleWiggle(at: i)
                    }
                }
                self.drainPrompts()
                self.refreshAll()
            }
            return
        }
        // Diamond Ripple consent: the engine parked its ♦-top shuffle for a
        // player decision. With no UI (auto-play) resolve the web's way — AUTO.
        if let pending = engine.run.pendingRipple {
            guard let handler = onRippleOffer, !reduceMotion else {
                engine.answerRipple(true)
                drainPrompts()
                return
            }
            promptActive = true
            let piles = pending.piles
            // The board-side half of the question: ring the piles on offer.
            // They stay lit while the player fan-inspects, and clear only on
            // an explicit answer (never on a FAN or scrim tap).
            scene.setRippleTargets(piles)
            handler(piles) { [weak self] accept in
                guard let self else { return }
                self.promptActive = false
                self.scene.setRippleTargets([])
                self.engine.answerRipple(accept)
                if accept {
                    Sound.shared.ripple()        // Diamond Ripple: a travelling riffle
                    for i in piles { self.scene.shuffleWiggle(at: i) }
                }
                self.drainPrompts()
                self.refreshAll()
            }
            return
        }
        // Second Wind consent (v6.55): the save roll hit; the player chooses
        // the recycle-save or the death. No-UI default is the web's way — SAVE.
        if let pending = engine.run.pendingSecondWind {
            // The killer's draw is still animating (v6.56 sequencing): the
            // prompt waits for the landing — the offer flight's completion
            // re-drains. Guesses stay locked meanwhile (secondWindDrawInFlight
            // is checked in guess()).
            guard !secondWindDrawInFlight else { return }
            guard let handler = onSecondWindOffer, !reduceMotion else {
                engine.answerSecondWind(true)
                drainPrompts()
                return
            }
            promptActive = true
            scene.setActionTargets([pending.index])
            handler(pending.index, pending.recycleCount) { [weak self] accept in
                guard let self else { return }
                self.promptActive = false
                self.scene.setActionTargets([])
                // The killer already flew and settled when the offer arrived —
                // a decline's replayed `.resolved` must not fly it twice.
                if !accept { self.skipResolvedFlightFor = pending.index }
                if accept {
                    // v6.93: the killer never landed — it flies back to the
                    // deck with the buried cards; the pile keeps its old top.
                    self.scene.flyToDeck(face: CardArt.Face(pending.killingCard),
                                         from: pending.index, delay: 0) {}
                }
                self.engine.answerSecondWind(accept)
                self.drainPrompts()
                self.refreshAll()
            }
            return
        }
        // Link Shuffler consent (v6.55): a correct Same parked the board-wide
        // shuffle. No-UI default is the web's way — FIRE.
        if engine.run.pendingPowerShuffle != nil {
            guard let handler = onPowerShuffleOffer, !reduceMotion else {
                engine.answerPowerShuffle(true)
                drainPrompts()
                return
            }
            promptActive = true
            let alive = alivePiles()
            let label = engine.run.samePower
                .flatMap { GameData.shared.samePowerTypes.get($0)?.label } ?? "Link Shuffler"
            scene.setActionTargets(alive)
            handler(label, alive.count) { [weak self] accept in
                guard let self else { return }
                self.promptActive = false
                self.scene.setActionTargets([])
                self.engine.answerPowerShuffle(accept)
                if accept {
                    Sound.shared.shufflePile()
                    for i in alive { self.scene.shuffleWiggle(at: i) }
                }
                self.drainPrompts()
                self.refreshAll()
            }
            return
        }
        if let col = pendingReviveCol {
            pendingReviveCol = nil
            let dead = (0..<engine.board.size).filter { !engine.board.isActive($0) }
            guard let handler = onReviveOffer, !reduceMotion, !dead.isEmpty else { return }
            promptActive = true
            handler(dead) { [weak self] target in
                guard let self else { return }
                self.promptActive = false
                if let target {
                    _ = self.engine.reviveDeadPile(col: col, targetIndex: target)
                }
                self.refreshAll()
            }
        }
    }

    /// The revive-offer piles for tap routing while targeting.
    public func deadPiles() -> [Int] {
        (0..<engine.board.size).filter { !engine.board.isActive($0) }
    }

    // MARK: - Second Wind sequencing (v6.56)

    /// The parked Second Wind's killer card flies to the pile and the pile
    /// takes its dying beat; the save prompt surfaces ON LANDING. Shared by
    /// the live `.secondWindOffer` event and the staged `-demoPrompt` path so
    /// both demonstrate the v6.56 sequencing identically. The STAGED path
    /// flies at 6× draw speed so a screenshot can land mid-draw (evidence
    /// still); live offers fly at draw speed.
    private func flySecondWindKiller(drawn: LiveCard, to index: Int, staged: Bool = false) {
        secondWindDrawInFlight = true
        animQueue.add(priority: 0) { [weak self] done in
            guard let self else { done(); return }
            self.scene.flyDraw(face: CardArt.Face(drawn), to: index,
                               stickers: drawn.stickers, counters: drawn,
                               duration: staged ? 1.5 : nil) {
                Sound.shared.place()
                self.scene.pileLandPop(index)
                self.scene.pileWince(index)   // the dying beat — fate undecided
                self.secondWindDrawInFlight = false
                done()
                self.drainPrompts()           // NOW ask: save or let it die
            }
        }
    }

    // MARK: - Roll indicators (v6.57 probability feedback, relocated v6.74)

    /// The verdict moved OFF the landed card/pile float and ONTO THE ITEM
    /// that rolled (v6.74): a PILLAR roll centres on the column's pillar
    /// plaque (Second Wind, Static, Flypaper, Gambler), a STICKER roll sits
    /// beside the sticker chip on its card (Saboteur, Malfunction), a
    /// SAME-POWER roll sits beside the HUD power chip (Long Odds). One word
    /// — "HIT" (gold) / "MISS" (muted) — held a beat longer than the coin
    /// float. Priority 0 preserves the engine's emission order through the
    /// animation queue: the roll reports BEFORE its effect's own cue.
    private func floatRollIndicator(_ r: RollResult) {
        animQueue.add(priority: 0) { [weak self] done in
            guard let self else { done(); return }
            switch r.klass {
            case "sticker":
                if let i = r.index { self.scene.rollVerdictAtSticker(hit: r.hit, pile: i) }
                else if let c = r.col { self.scene.rollVerdictAtPillar(hit: r.hit, col: c) }
            case "samePower":
                if !self.scene.rollVerdictAtSamePower(hit: r.hit), let i = r.index {
                    self.scene.rollVerdict(hit: r.hit, atPile: i)
                }
            default:   // "pillar"
                if let c = r.col { self.scene.rollVerdictAtPillar(hit: r.hit, col: c) }
                else if let i = r.index { self.scene.rollVerdict(hit: r.hit, atPile: i) }
            }
            done()
        }
    }

    // MARK: - Screenshot staging (DealFeedbackUITests' hooks, v6.57)

    /// `-demoRollFX hit|miss`: ONE roll indicator through the real
    /// presentation path (v6.74: ON the item — the pillar plaque / the
    /// sticker chip), since simctl can't make a genuine 10%/50% roll land on
    /// cue — the `-demoCurseFX` precedent.
    public func debugStageRollIndicator(hit: Bool) {
        floatRollIndicator(hit
            ? RollResult(id: "static", label: "Static", klass: "pillar",
                         chance: 0.5, hit: true, index: 1, col: 0)
            : RollResult(id: "saboteur", label: "Saboteur", klass: "sticker",
                         chance: 0.1, hit: false, index: 2, col: 2))
    }

    /// `-demoSuitCounts 1`: push the WORST-CASE suit tallies ("13/27" —
    /// two-digit remaining over two-digit total) through the real deck-panel
    /// sync, so the histogram-overlap fix has pixel evidence at the widest
    /// the tally text can get.
    public func debugStressSuitCounts() {
        guard let engine else { return }
        scene.syncDeckPanel(counts: engine.deck.remainingCounts(),
                            suitCounts: ["♥": 13, "♦": 9, "♣": 12, "♠": 7],
                            total: engine.deck.remaining(),
                            remaining: engine.deck.remaining(),
                            deckId: campaign.deckId,
                            mood: mood(),
                            tier: isZen ? "regular" : campaign.difficultyTier,
                            suitTotals: ["♥": 27, "♦": 18, "♣": 21, "♠": 13],
                            rankTotals: dealRankTotals,
                            showJoker: !isZen)
    }

    /// `-demoSuitRefresh 1`: apply a changeSuitTo sticker to a card still in
    /// the draw pile through the REAL campaign mutation + invalidation hook —
    /// the screenshot proves the band's suit counts refresh the moment the
    /// sticker lands (task 16's fix), no second trigger needed.
    public func debugApplySuitStickerToDeckCard() {
        guard let engine else { return }
        let runIds = Set(campaign.getRunDeck().map(\.id))
        guard let card = engine.deck.peekAll().first(where: {
            runIds.contains($0.id) && !$0.joker && !$0.blank
        }), let def = GameData.shared.stickerTypes.all().first(where: {
            $0.behavior == "changeSuitTo" && $0.suit != nil && $0.suit != card.suit
        }) else { return }
        _ = campaign.applyStickerDirect(card.id, def.id)
        noteDeckCompositionChanged()
    }

    // MARK: - Screenshot staging (EventCaptureUITests' `-demoPrompt …` hooks)

    /// Stage + surface the parked Diamond Ripple consent (the engine hook
    /// builds the real pending state); returns the offered piles so the demo
    /// can open the fan overlay on one.
    @discardableResult
    public func debugSurfaceRipple() -> [Int] {
        let piles = engine.debugStageRipplePending()
        drainPrompts()
        return piles
    }

    /// Stage + surface the parked Second Wind save/die choice. v6.56: the
    /// staged offer plays the SAME sequencing as a live one — the staged
    /// killer (the engine really drew it) flies to the pile first, and the
    /// prompt surfaces on its landing.
    public func debugSurfaceSecondWind() {
        engine.debugStageSecondWindPending()
        if let pending = engine.run.pendingSecondWind, !reduceMotion {
            flySecondWindKiller(drawn: pending.killingCard, to: pending.index, staged: true)
        } else {
            drainPrompts()
        }
    }

    /// Stage + surface the parked Link Shuffler confirm.
    public func debugSurfacePowerShuffle() {
        engine.debugStagePowerShufflePending()
        drainPrompts()
    }

    /// Stage + surface the Revive pillar's targeting offer (v6.56): the
    /// repaint lands BEFORE the prompt arms, so the stage-killed pile reads
    /// dead (and highlighted) when the player is asked to tap it.
    public func debugSurfaceRevive() {
        _ = engine.debugStageReviveOffer()
        refreshAll()
        drainPrompts()
    }

    // MARK: - Base activation (tap-to-fire)

    /// Confirm + fire a charged Base: (label, description, needsTarget?, fire).
    public var onBasePrompt: ((String, String, @escaping () -> Void) -> Void)?
    /// Pile-targeted Base (Sticker Harvest): (legal piles, prompt, fire(pile)).
    public var onBaseTarget: (([Int], String, @escaping (Int?) -> Void) -> Void)?
    /// "That can't fire right now" — a notice, not a prompt.
    public var onBaseNotice: ((String, String) -> Void)?

    /// Alive piles in this Base's OWN column — the legal targets for a
    /// pile-targeted Base (Sticker Harvest). Bases are column-scoped, so a
    /// board-wide list would offer targets the engine then rejects.
    public func baseTargetPiles(col: Int) -> [Int] {
        guard let engine, let cols = engine.run.pileColumns else { return [] }
        return (0..<engine.board.size).filter { cols[safe: $0] == col && engine.board.isActive($0) }
    }

    public func basePlaqueTapped(col: Int) {
        guard !interactionLocked, !isOver, !promptActive else { return }
        guard let id = (isCampaign || isZen) ? campaign.columnBase(col) : currentBaseId(col),
              let def = GameData.shared.baseTypes.get(id) else { return }
        // A SPENT (red) Base says nothing at all — its light already told you,
        // and a popup offering to activate what can't be activated is noise.
        if engine.run.basesUsed?[safe: col] == true { return }
        // Escape Hatch outside an ambush is red for the whole deal too.
        if def.effect == "ambushWin", !engine.baseCanActivate(col) { return }
        // AMBER (charged, criteria unmet) still says so out loud — that state
        // can change mid-deal, so silence would read as "the Base is broken".
        // v6.52: the notice names the ACTUAL unmet condition when the engine
        // has words for it — the generic line made a boss-sealed Last Resort
        // indistinguishable from a broken base.
        guard engine.baseCanActivate(col) else {
            onBaseNotice?(engine.baseUnavailableReason(col)
                            ?? "\(def.label) can't do anything right now.",
                          liveBaseDescription(def, col: col))
            return
        }

        // TARGETED Bases. `baseActivate` REQUIRES an index for these and
        // returns nil without one — which is why Sticker Harvest silently did
        // nothing on native: the confirm path never passed a target (v5.83).
        // Phoenix is NOT one of these: it carries no `target`, the engine
        // random-picks a dead pile in its own column, so it takes the plain
        // confirm below. Demolish lost its pick in v6.51 (own column only).
        if def.target == "pile" {
            var targets = baseTargetPiles(col: col)
            // v6.76 archetype bases: the pick list offers only piles the engine
            // itself would accept — a pile the effect can't touch is never
            // highlighted (Devil's Deal would otherwise silently curse the
            // FIRST eligible pile when the pick was a joker/blank top).
            // (Diamond Boost lost its pick in v6.78 — it fires column-wide.)
            switch def.effect {
            case "devilsDeal":
                targets = targets.filter {
                    guard let t = engine.board.top($0) else { return false }
                    return !t.joker && !t.blank
                }
            default: break
            }
            let prompt: String
            switch def.effect {
            case "sacrifice":
                prompt = "Sacrifice: tap a pile — its top card leaves your deck for good, and the pile dies."
            case "devilsDeal":
                prompt = "Devil's Deal: tap a top card to take the curse."
            default:
                prompt = "\(def.label): tap a pile in this column."
            }
            guard !targets.isEmpty, let handler = onBaseTarget else {
                onBaseNotice?("\(def.label) has nothing to target.", liveBaseDescription(def, col: col))
                return
            }
            promptActive = true
            handler(targets, prompt) { [weak self] target in
                guard let self else { return }
                self.promptActive = false
                if let target { _ = self.engine.baseActivate(col: col, targetIndex: target) }
                self.refreshAll()
            }
            return
        }

        guard let handler = onBasePrompt else {
            _ = engine.baseActivate(col: col, purseCoins: campaign.getCoins())
            refreshAll()
            return
        }
        promptActive = true
        var confirmDesc = liveBaseDescription(def, col: col)
        if def.effect == "emptyPurse" {
            // v6.74: the yield AND the cost, brutally clear — the exact peek
            // count and the exact number about to vanish, both computed live.
            let purse = campaign.getCoins()
            let peeks = 1 + purse / 10
            confirmDesc += "\nPeek \(peeks) card\(peeks == 1 ? "" : "s"). This spends ALL your coins: ◉ \(purse). Every one."
        }
        if def.effect == "setValue" || def.effect == "setSuit" {
            // Live preview: the exact count about to change, and to what —
            // mirrors the engine's skip-if-already-matching rule, so the
            // number is computed from the board, never hardcoded.
            let alive = baseTargetPiles(col: col)
            if let srcPile = alive.last, let src = engine.board.top(srcPile) {
                let isRank = def.effect == "setValue"
                let n = alive.filter { p in
                    guard let t = engine.board.top(p) else { return false }
                    return isRank ? t.value != src.value : t.suit != src.suit
                }.count
                confirmDesc += "\nSet \(n) card\(n == 1 ? "" : "s") to \(isRank ? src.label : src.suit)"
            }
        }
        if def.effect == "chorus", let r = engine.mostCopiedRank(),
           let label = DeckManager.ranks.first(where: { $0.value == r })?.label {
            // CHORUS (v6.89): the live count, the setValue idiom — the rank
            // itself is already substituted by liveBaseDescription.
            let n = baseTargetPiles(col: col).filter { p in
                guard let t = engine.board.top(p) else { return false }
                return !t.joker && !t.blank && t.value != r
            }.count
            confirmDesc += "\nSet \(n) card\(n == 1 ? "" : "s") to \(label)"
        }
        // (v6.53 batch 3: Last Resort's destruction warning now lives in its
        // registry description — appending it here printed it twice.)
        handler(def.label, confirmDesc) { [weak self] in
            guard let self else { return }
            self.promptActive = false
            _ = self.engine.baseActivate(col: col, purseCoins: self.campaign.getCoins())
            self.refreshAll()
        }
    }

    /// Notify the VC a prompt was dismissed without an answer path (cancel).
    public func promptDismissed() { promptActive = false }

    private func currentBaseId(_ col: Int) -> String? {
        // Debug deals: the `-dealBase` override resolved at boot, NOT the raw
        // setup dials — reading setup here left the staged plaque unfireable.
        if case .debug = mode { return debugBases?[safe: col] ?? nil }
        return campaign.columnBase(col)
    }

    /// The debug deal's `-dealBase`-resolved bases (set in bootDebug).
    private var debugBases: [String?]?

    /// Board reads the auto-play harness needs.
    public func alivePiles() -> [Int] {
        (0..<engine.board.size).filter { engine.board.isActive($0) }
    }
    public func topValue(_ index: Int) -> Int? { engine.board.top(index)?.value }
    /// Remaining rank counts — the odds-scripted player counts cards with this.
    public func deckCounts() -> [Int: Int] { engine.deck.remainingCounts() }
    /// Ids still in the draw pile — DeckInspect's remaining-vs-full shadow.
    public func remainingCardIds() -> Set<Int> { Set(engine.deck.peekAll().map(\.id)) }
    /// Ids of every card in THIS deal (draw pile + board piles) — the
    /// subset-deal boundary DeckInspect's shadow respects (v6.78): a card
    /// outside the deal entirely is never shadowed, matching the histogram's
    /// full-deck framing.
    public func dealCardIds() -> Set<Int> {
        var out = Set(engine.deck.peekAll().map(\.id))
        for p in engine.board.piles { for c in p.cards { out.insert(c.id) } }
        if let sw = engine.run.pendingSecondWind { out.insert(sw.killingCard.id) }
        return out
    }
    public var deckIsEmpty: Bool { engine.deck.isEmpty }
    public var promptIsUp: Bool { promptActive }

    public func pileCards(_ index: Int) -> [LiveCard] {
        guard index < engine.board.piles.count else { return [] }
        return engine.board.piles[index].cards
    }

    // MARK: - Autopilot reads
    //
    // The decision logic lives in AutoPilotBrain; these are the engine facts it
    // needs. All read-only — the brain never reaches past them.

    /// Is a Same shield currently banked?
    public var sameChargeBanked: Bool { engine?.sameCharge ?? false }
    /// MAGNET/MUTE curse state, for the autopilot and any picker that must
    /// respect the same gates the engine enforces.
    public func magnetPileSet() -> Set<Int> { Set(engine?.magnetPiles() ?? []) }
    public func pileIsMuted(_ index: Int) -> Bool { engine?.pileMuted(index) ?? false }
    /// The guaranteed direction for a pile under Tell / Spade Whispers, if any.
    public func hint(forPile index: Int) -> Guess? { engine?.pileHint(index) }
    /// The next draw, when a peek/reveal is live (Scout, Kamikaze, samePeek).
    public func peekedNextCard() -> LiveCard? { engine?.revealedNextCard() }
    /// The equipped Same-Power's registry entry, if one is equipped.
    public func equippedSamePowerDef() -> ItemDef? {
        guard let id = engine?.equippedSamePower() else { return nil }
        return GameData.shared.samePowerTypes.get(id)
    }
    /// Weighted pile size — what the payout and the score actually read.
    public func pileSize(_ index: Int) -> Int { engine?.board.pileSize(index) ?? 0 }
    public func aliveCount() -> Int { engine?.board.aliveCount() ?? 0 }
    public func minAliveCards() -> Int { engine?.board.minAliveCards() ?? 0 }
    /// Whether a guess would be accepted right now (the cascade lock included).
    public var canAcceptGuess: Bool {
        engine != nil && !interactionLocked && !isOver && !promptActive
            && !secondWindDrawInFlight && !engine.deck.isEmpty
    }
    /// Guesses resolved this deal — 0 means the board is still as dealt.
    public var totalGuessesMade: Int { engine?.run.totalGuesses ?? 0 }

    /// The web's hold-peek (`cardPeekHtml`) for a PILE: the pile's state (card
    /// count + top card) and the top card's own sticker help — copy always from
    /// the registry.
    ///
    /// It deliberately does NOT append the column's Pillar and Base text. Those
    /// two plaques answer their own hold (see helpText(forPillar:) and
    /// helpText(forBase:)), so repeating them here buried the ONE thing the
    /// player held the card to read under two paragraphs about other items.
    public func helpText(forPile index: Int) -> (String, String)? {
        guard index < engine.board.piles.count else { return nil }
        // A dead or drained pile still answers a hold — returning nil here made
        // those piles look like the hold itself was broken.
        guard let top = engine.board.top(index) else {
            return ("Pile \(index + 1)", engine.board.isActive(index)
                    ? "Empty. No card on this pile."
                    : "Dead. This pile is out of the deal.")
        }
        // v6.78: the header IS the top card — "{card} • X buried" (the old
        // "Pile N · Y cards" head and its separate "Top: {card}" line are
        // gone; the sticker list below keeps the card-info law's bold-name +
        // description rows).
        let buried = max(0, engine.board.piles[index].cards.count - 1)
        let info = CardInfoText.make(top)
        let head = top.joker ? "★ Joker" : "\(top.label)\(top.suit)"
        return ("\(head) • \(buried) buried", info.body)
    }

    /// THE RICH PILE HELP (v6.83): the same content `helpText(forPile:)`
    /// composes, but STRUCTURED — so the board's panel draws each sticker
    /// name in its own colour and bold, exactly like the deck view's popup,
    /// instead of one flat cream paragraph. Left-aligned: the panel is a
    /// reading block, not a caption.
    public func richHelp(forPile index: Int) -> (String, NSAttributedString)? {
        guard let (title, _) = helpText(forPile: index) else { return nil }
        guard let top = engine.board.top(index) else {
            return (title, CardInfo.attributed(body: engine.board.isActive(index)
                                               ? "Empty. No card on this pile."
                                               : "Dead. This pile is out of the deal.",
                                               alignment: .left))
        }
        let rows = CardInfo.rows(for: top)
        return (title, CardInfo.attributed(body: rows.isEmpty ? "No stickers on this card." : nil,
                                           rows: rows, alignment: .left))
    }

    /// The Pillar plaque's hold-help (the web's pillarPeekHtml): name + effect,
    /// and the column it governs. Registry copy, never hand-typed.
    public func helpText(forPillar col: Int) -> (String, String)? {
        guard let id = pillarId(for: col), let def = GameData.shared.pillarTypes.get(id) else { return nil }
        // The column rides the NAME (router batch) — "Applies to column N"
        // read like a second sentence of rules.
        var body = campaign.itemDescription(def)
        // SCARCE SUIT (v6.81): the registry copy names the rule (fewest-held
        // suit, per deal) — the hold names THIS deal's read (the plaque
        // shows it too).
        if def.effect == "suitShieldDaily", let suit = engine?.run.dailySuits?[col] {
            body += "\nThis deal shields \(suit)."
        }
        return ("\(def.label) · column \(col + 1)", body)
    }

    /// The Base plaque's hold-help (the web's basePeekHtml): name + effect and
    /// this deal's charged/spent state. v6.53 batch 3: no column number (the
    /// plaque IS on its column) and no "tap the plaque" coaching line.
    public func helpText(forBase col: Int) -> (String, String)? {
        guard let id = currentBaseId(col), let def = GameData.shared.baseTypes.get(id) else { return nil }
        var body = liveBaseDescription(def, col: col)
        var title = def.label
        if engine != nil {
            let spent = engine.run.basesUsed?[safe: col] ?? false
            if spent {
                body += "\nSpent. Already fired this deal."
            } else if engine.baseCanActivate(col) {
                // The word "charged" is now the LIGHT: the same green dot the
                // plaque blinks, riding the name (router batch).
                title = "● " + title
            } else if def.effect == "lastResort", engine.isBossDeal {
                body += "\nSealed during a boss deal."
            }
        }
        return (title, body)
    }

    private func pillarId(for col: Int) -> String? {
        switch mode {
        case .debug(let setup): return setup.pillars[safe: col] ?? nil
        case .zen: return nil
        case .campaign: return campaign.columnPillars[safe: col] ?? nil
        }
    }

    /// The top-bar chips' hold-for-help (web attachInput HUD copy, verbatim).
    public func helpText(forHUDChip id: String) -> (String, String)? {
        switch id {
        case "sameCharge":
            return ("Same Charge",
                    "Same Charge: a correct Same banks it (max 1). It auto-saves a pile from death as a last resort")
        case "samePower":
            guard let pid = engine?.equippedSamePower(),
                  let def = GameData.shared.samePowerTypes.get(pid) else { return nil }
            return (def.label, campaign.itemDescription(def))
        case "stageRun":
            return ("The climb",
                    "3 stages, each ending at a boss deal. Clear the stage-3 boss to win the campaign. Losing any deal ends it.")
        case "dealStatus":
            return ("Reward & Score",
                    "Reward: base + bonus. The base is the flat coins this deal pays on a clear, set by its stage & difficulty (harder pays more), fixed for the deal. The bonus is what your items have piled on top so far (stickers, pillars, bases; live, and a Tribute can drag it negative). Score: surviving piles × the smallest surviving pile if you cleared right now. Personal bests only, never coins.")
        case "score":
            return ("Score",
                    "Your score: surviving piles × the smallest pile on each cleared deal, added up over the climb. Banked as your campaign score when the ♠ boss falls. Deals after that build your endless score. Chased for personal bests only; it never changes coins or play.")
        case "coins":
            return ("Coins",
                    "Coins: what you spend in the store on stickers, Pillars, Bases, cards and packs. Earned by clearing deals (base + bonus), plus Payout stickers, Pillar payouts and events. They carry for the whole climb; unlike Score, they change what you can buy.")
        default:
            return nil
        }
    }

    public func pushLinks(_ adj: [Int: [Int]]) { engine?.setLinks(adj) }

    // MARK: - Refresh

    public func refreshAll() {
        guard engine != nil else { return }
        // Feed the debug EVENT LOG (v6.52): any engine logbook entries the
        // last action appended flow into the run-long record.
        DebugEventLog.shared.drainEngine(engine.run)
        refreshBoard()
        refreshHUD()
        refreshControls()
        emitActionSnapshot()
    }

    /// Hand the mid-deal save its snapshot. refreshAll runs synchronously
    /// right after every engine mutation (guess, prompt answer, base fire),
    /// so the state captured here is the post-action truth even if the app
    /// dies during the landing animation. Campaign deals only, and only
    /// while live — a finished deal's blob is cleared by the flow.
    private func emitActionSnapshot() {
        guard isCampaign, !isOver, let engine, engine.status == "playing",
              let sink = onActionSnapshot else { return }
        var blob = engine.snapshot()
        // UI-side prompt scratch the engine doesn't own: an un-answered
        // revive offer survives the kill too.
        if let col = pendingReviveCol { blob["uiPendingReviveCol"] = .number(Double(col)) }
        sink(blob)
    }

    /// RANK SHIELD (v6.78): the label of the rank the shield protects this
    /// deal — read off the engine's per-deal pick; nil when none was made.
    private func rankShieldLabel() -> String? {
        guard let r = engine?.run.shopRolls["rankShield"]?.rank else { return nil }
        return DeckManager.ranks.first { $0.value == r }?.label
    }

    /// A Base description with LIVE template values (v6.89): Chorus's
    /// {rank} names the deck's current most-copied rank everywhere the deal
    /// shows the text (confirm, amber notice, hold-help). Falls back to the
    /// generic wording when no engine is up.
    private func liveBaseDescription(_ def: ItemDef, col: Int? = nil) -> String {
        var out = def.description
        // PURGE COUPON (v6.93): the data text is token-free (a ♦-count needs
        // a live column), so the ladder preview is appended HERE — both
        // numbers read through removalPrice()'s own ladder: current = the
        // NEXT store visit's price (purchases already made this climb
        // included), new = the same read with this fire's cut banked. The
        // cut itself is the badge's live counter, so preview ≡ fire.
        if def.effect == "purgeDiscount", let cut = engine?.baseLiveCounter(col) {
            let cur = Int(campaign.removalPrice())
            let new = Int(campaign.removalPrice(extraCut: cut))
            out += "\nRight now: the store's Purge ◉\(cur) → ◉\(new)."
        }
        if out.contains("{rank}") {
            if let r = engine?.mostCopiedRank(),
               let label = DeckManager.ranks.first(where: { $0.value == r })?.label {
                out = out.replacingOccurrences(of: "{rank}", with: label)
            } else {
                out = out.replacingOccurrences(of: "{rank}", with: "your deck's most common rank")
            }
        }
        return out
    }

    public func refreshBoard() {
        guard let engine, engine.board != nil else { return }
        let n = engine.board.size
        let snap = DealScene.BoardSnapshot(
            tops: (0..<n).map { engine.board.top($0) },
            counts: (0..<n).map { engine.board.piles[$0].cards.count },
            weighted: (0..<n).map { engine.board.pileSize($0) },
            dead: (0..<n).map { !engine.board.isActive($0) },
            anchored: (0..<n).map { engine.board.isAnchored($0) },
            pileCards: (0..<n).map { engine.board.piles[$0].cards },
            deckId: campaign.deckId,
            minStates: engine.board.minPileStates())
        scene.syncBoard(snap)
        // Tell / Spade Whispers: the display-only directional hint per pile,
        // repainted every board refresh so it tracks the real deck top.
        scene.syncPileHints((0..<n).map { engine.pileHint($0) })
        // ODDS ASSIST (v6.72): recomputed here — once per board change, the
        // same cadence as the hints, never per frame. Off unless the player
        // both UNLOCKED it (first Straight win) and switched it on — and
        // GATED while a deal-out cascade is still flying cards in (the glow
        // waits for the board to be live; the completion callback flips the
        // gate and re-runs this refresh).
        let assistOn = campaign.saveStore.pref("oddsAssist") == "1"
            && campaign.deckUnlocks.wonAnyStraight()
        scene.syncAssist(assistGate.allows(assistOn) ? engine.assistRecommendations() : nil)
        scene.syncPillarBadges(pillarBadges())
        scene.syncBaseBadges(baseBadges())
        scene.syncBaseLights(baseLights())
    }

    /// Each Base plaque's status light. Bases are the one item the player
    /// actually FIRES, so they are where a three-state light means something:
    /// green it can fire now, amber charged but its criteria aren't met (e.g.
    /// Heart Tax with no ♥ in the column), red spent for this deal.
    private func baseLights() -> [Int: DealScene.BaseLight] {
        var out: [Int: DealScene.BaseLight] = [:]
        guard let engine, engine.board != nil, !isZen else { return out }
        let cols = engine.run.cols?.count ?? 0
        for col in 0..<cols {
            guard let bid = currentBaseId(col) else { continue }
            if engine.run.basesUsed?[safe: col] == true { out[col] = .spent }
            else if engine.baseCanActivate(col) { out[col] = .ready }
            // A Base that can NEVER fire in this deal reads RED, not amber:
            // Escape Hatch outside an ambush isn't "waiting for conditions",
            // it's off for the whole deal, same as spent.
            else if GameData.shared.baseTypes.get(bid)?.effect == "ambushWin" { out[col] = .spent }
            else { out[col] = .idle }
        }
        return out
    }

    /// The live "if activated now" figure each still-charged Base carries — the
    /// web's `.base-count-badge` (Heart Tax / Heart Demolish coins, Spade Peeker
    /// peek count, Club Dig cards buried). Spent Bases carry no chip: the plaque
    /// is already dimmed, and a stale number there would read as available.
    private func baseBadges() -> [Int: Int] {
        var out: [Int: Int] = [:]
        guard let engine, engine.board != nil, !isZen else { return out }
        let cols = engine.run.cols?.count ?? 0
        for col in 0..<cols {
            guard engine.run.basesUsed?[safe: col] != true else { continue }
            guard let n = engine.baseLiveCounter(col) else { continue }
            out[col] = n
        }
        return out
    }

    /// The live badge each Pillar plaque carries (web `updateStreakCounters` /
    /// `updateScoringCounters` / `updateSecondWind`), computed from the same
    /// engine state and the registry's tunables — the math mirrors the web's
    /// end-of-deal scoring exactly.
    private func pillarBadges() -> [Int: DealScene.PillarBadge] {
        var out: [Int: DealScene.PillarBadge] = [:]
        guard let engine, engine.board != nil, let cols = engine.run.pileColumns else { return out }
        let ids: [String?]
        switch mode {
        case .debug(let setup): ids = setup.pillars
        case .zen: return out
        case .campaign: ids = campaign.columnPillars
        }
        func aliveInColumn(_ col: Int) -> [Int] {
            cols.enumerated().filter { $0.element == col && engine.board.isActive($0.offset) }.map(\.offset)
        }
        for (col, id) in ids.enumerated() {
            guard let id, let def = GameData.shared.pillarTypes.get(id) else { continue }
            let alive = aliveInColumn(col)
            switch def.effect {
            case "streakSize", "streakTribute":
                let s = engine.run.colStreak?[safe: col] ?? 0
                let thr = def.int("threshold", 3)
                out[col] = .streak(s, hot: thr > 0 && s >= thr)
            case "heavyDiamond":
                // +1 pile size per ♦ card in the column's alive piles (buried
                // included), × the registry value (t.value || 1).
                var d = 0
                for i in alive {
                    for c in engine.board.piles[i].cards where CardRules.matchesSuit(c, "♦") { d += 1 }
                }
                let v = def.value
                out[col] = .count(d * Int(v == 0 ? 1 : v))
            case "excavator":
                // value × buried cards in the LARGEST alive ♥-top pile (t.value || 2).
                var best = 0
                for i in alive {
                    if CardRules.matchesSuit(engine.board.top(i), "♥") {
                        best = max(best, engine.board.piles[i].cards.count)
                    }
                }
                let v = def.value
                out[col] = .count(max(0, best - 1) * Int(v == 0 ? 2 : v))
            case "heartPiles":
                // value × alive piles in the column with a ♥ top (t.value || 4).
                var p = 0
                for i in alive where CardRules.matchesSuit(engine.board.top(i), "♥") { p += 1 }
                let v = def.value
                out[col] = .count(p * Int(v == 0 ? 4 : v))
            case "highestHeart":
                // Highest NUMBERED ♥ top: A pays 1, royals 0 (engine parity).
                var payout = 0
                for i in alive {
                    guard let top = engine.board.top(i), CardRules.matchesSuit(top, "♥") else { continue }
                    let coin = top.value == 14 ? 1 : (top.value >= 11 ? 0 : top.value)
                    payout = max(payout, coin)
                }
                out[col] = .count(payout)
            case "secondWind":
                out[col] = .secondWind
            default:
                break
            }
        }
        return out
    }

    /// Columns whose Base has already fired this deal (web `.base-banner.spent`).
    private func spentBaseColumns() -> [Int] {
        guard let used = engine?.run.basesUsed else { return [] }
        return used.enumerated().filter { $0.element }.map(\.offset)
    }

    private func refreshHUD() {
        guard let engine else { return }
        // An inventory suit sticker applied over the deal mutates the campaign
        // deck with no engine event — revalidate so the band's suit counts
        // never repaint stale (v6.57; the no-op diff costs nothing otherwise).
        if isCampaign { revalidateComposition() }
        scene.syncHUD(phaseIndex: campaign.phaseIndex,
                      altSuits: campaign.rules().altSuits,
                      phasesTotal: campaign.phasesTotal(),
                      showTrack: !isZen,   // web hides the suit track in zen
                      sameCharged: engine.sameCharge,
                      samePower: engine.equippedSamePower(),
                      coins: campaign.getCoins(),
                      // The HUD chip is the CLIMB score (what its hold-help
                      // describes, and what the web's #hudScore shows) beside
                      // the lifetime best. The live piles×smallest projection
                      // for THIS deal has its own home in the reward line.
                      score: isZen ? currentScore() : campaign.getRunScore(),
                      best: isZen ? 0
                          : campaign.stats.get().deckTierBest["\(campaign.deckId).\(campaign.difficultyTier)"] ?? 0,
                      zen: isZen)          // web hides score/coins/Same in zen
        // Fold the held-back cards back in so the band reads as the whole deck.
        var histCounts = engine.deck.remainingCounts()
        for (k, v) in sittingOutRank where v > 0 { histCounts[k, default: 0] += v }
        var histSuits = engine.deck.remainingSuitCounts()
        for (k, v) in sittingOutSuit where v > 0 { histSuits[k, default: 0] += v }
        scene.syncDeckPanel(counts: histCounts,
                            suitCounts: histSuits,
                            total: engine.deck.remaining(),
                            remaining: engine.deck.remaining(),
                            deckId: campaign.deckId,
                            mood: mood(),
                            tier: isZen ? "regular" : campaign.difficultyTier,
                            suitTotals: dealSuitTotals,
                            rankTotals: dealRankTotals,
                            showJoker: !isZen)   // Zen never holds a ★
        // v6.94: the engine's peek read carries the REAL card — the peek chip
        // shows its stickers/curses, not just the face.
        scene.syncDeckPeek(engine.revealedNextCard())
        // Zen hides #dealStatus — no reward line at all.
        if !isZen {
            scene.syncReward(base: plan?.flatReward ?? dealBaseDebug(), bonus: liveBonus(),
                             alive: engine.board.aliveCount(), minAlive: engine.board.minAliveCards())
        }
    }

    private func dealBaseDebug() -> Double {
        economy.dealFlat(stage: 1, rating: 2, isBoss: false)
    }

    private func refreshControls() {
        let canGuess = !interactionLocked && !isOver
            && scene.currentSelection != nil && !engine.deck.isEmpty
        let canAffordReshuffle = !isCampaign || Double(campaign.getCoins()) >= redealCost
        // MUTE curse: Same is blocked on the selected pile (the engine
        // refuses it too — the chip is the WHY).
        let sameBlocked = scene.currentSelection.map { engine.pileMuted($0) } ?? false
        // The web names the price on the button: `↺ RESHUFFLE · ◉ 10`
        // (campaign only — Zen has no reshuffle; debug deals are free).
        // The Queen's Mulligan reads FREE and wears the charged (phosphor)
        // glow while the deal's first reshuffle is still unspent (v6.55).
        scene.setReshuffleTitle(isCampaign
            ? (freeRedealAvailable ? "↺ RESHUFFLE · FREE" : "↺ RESHUFFLE · ◉ \(Int(redealCost))")
            : "↺ RESHUFFLE")
        scene.setReshuffleGlow(freeRedealAvailable)
        // Web parity (renderReshuffleBtn): the offer hides only once the first
        // guess is made; an UNAFFORDABLE price shows the button disabled, not
        // hidden.
        scene.syncControls(canGuess: canGuess,
                           showReshuffle: !isZen && !isOver && engine.run.totalGuesses == 0
                               && !interactionLocked,
                           reshuffleEnabled: canAffordReshuffle,
                           sameBlocked: sameBlocked)
        scene.syncSpentBases(spentBaseColumns())
        // MAGNET curse: the pull is SHOWN — magnet piles carry the action
        // outline while everything else refuses selection (the engine gate
        // is the rule; this is its face).
        let magnets = isOver ? [] : engine.magnetPiles()
        scene.setMagnetTargets(magnets)
    }

    private func mood() -> DeckCharacter.Mood {
        if isOver { return engine.status == "won" ? .win : .sad }
        if engine.board.aliveCount() <= 2 { return .sad }
        return .idle
    }

    private func liveBonus() -> Double {
        // v6.94: the tracker counts DURING-deal bonus coins only. Deal-end
        // awards (scoring pillars, Payout sticker units) land at the scoring
        // pass — they must not show here before the final turn resolves.
        var s = PayoutStats()
        s.liveBonusCoins = engine.run.bonusCoins
        return economy.liveBonus(s)
    }

    private func currentPayout() -> Double {
        var s = PayoutStats()
        s.won = true
        s.flat = plan?.flatReward ?? dealBaseDebug()
        s.stage = plan?.stage ?? 1
        s.rating = plan?.rating ?? 2
        s.aliveCount = engine.board.aliveCount()
        s.minAliveCards = engine.board.minAliveCards()
        s.extraCoinUnits = engine.board.extraCoinUnits()
        let pp = engine.pillarPayout()
        s.pillarBonus = pp.bonus
        s.pillarLines = pp.lines
        s.eventBonus = engine.run.bonusCoins
        return economy.breakdown(s).total
    }

    /// The live score projection: alive piles × the smallest alive pile.
    private func currentScore() -> Int {
        engine.board.aliveCount() * engine.board.minAliveCards()
    }

    // MARK: - Reshuffle

    /// Re-deal the piles (before the FIRST guess only). A campaign deal PAYS
    /// the escalating redeal price and re-mints from the deal's keyed stream.
    /// Zen has NO reshuffle (climb deals only — user call, overrides the web's
    /// free zen reshuffle).
    public func reshuffle() {
        guard !isZen, !isOver, engine.run.totalGuesses == 0 else { return }
        // The re-deal's cascade is coming: re-arm the assist gate NOW and
        // clear the stale glow so it doesn't ride the gather-back animation.
        assistGate.dealOutStarted()
        scene.syncAssist(nil)
        switch mode {
        case .debug(let setup):
            interactionLocked = true
            animQueue.clear()
            scene.setSelected(nil)
            // The shuffle is SEEN: the old cards gather back to the deck first,
            // then the fresh deal cascades out (reduceMotion skips the gather).
            scene.gatherToDeck { [weak self] in
                guard let self else { return }
                self.engine.start(seedOverride: RNG.generateSeed())
                // The `-dealPillar`/`-dealBase`/`-dealSamePower` overrides
                // survive a reshuffle too — otherwise the re-deal drops the
                // staged item while its plaque still shows.
                let d = UserDefaults.standard
                var pillars = setup.pillars
                if let pid = d.string(forKey: "dealPillar"), !pillars.isEmpty { pillars[0] = pid }
                self.engine.startRun(pillars: pillars, bases: self.debugBases ?? setup.bases,
                                     samePower: .some(d.string(forKey: "dealSamePower") ?? setup.samePower))
                self.engine.run.rippleNeedsConsent = self.onRippleOffer != nil && !self.reduceMotion
                self.engine.run.secondWindNeedsConsent = self.onSecondWindOffer != nil && !self.reduceMotion
                self.engine.run.samePowerNeedsConsent = self.onPowerShuffleOffer != nil && !self.reduceMotion
                self.refreshAll()
                self.startCascade()
            }

        case .zen:
            Sound.shared.shuffleDeck()
            interactionLocked = true
            animQueue.clear()
            let p = DealPlanner.zenPlan(diff: GameData.shared.difficulty.zen(zenDiffId ?? "easy"))
            plan = p
            boot(plan: p)

        case .campaign:
            guard let runMap, campaign.spendCoins(Int(redealCost)) else { return }
            TelemetryCore.shared.record("redeal_used", [
                "kind": redealCost > 0 ? "paid" : "free",
                "cost": String(Int(redealCost)),
            ])
            // A PAID redeal: the spend falls first, then the riffle (a free
            // one — redealCost 0 — spends nothing and stays a plain shuffle).
            if redealCost > 0 { Sound.shared.coinLoss() }
            Sound.shared.shuffleDeck()
            interactionLocked = true
            animQueue.clear()
            scene.setSelected(nil)
            scene.gatherToDeck { [weak self] in
                guard let self else { return }
                self.reshuffleIndex += 1
                // A FREE reshuffle (the Queen's Mulligan) stood in for the
                // ladder's first rung — the next one prices from base.
                self.redealCost = self.redealCost == 0
                    ? DealPlanner.redealBaseCost : self.redealCost + DealPlanner.redealStep
                let ambush: DealPlanner.AmbushSpec? = (self.plan?.isAmbush == true && self.plan?.ambushNodeId != nil)
                    ? DealPlanner.AmbushSpec(cards: 0, piles: self.plan!.piles,
                                             bounty: self.plan!.ambushBounty, nodeId: self.plan!.ambushNodeId!)
                    : nil
                var p = DealPlanner.plan(campaign: self.campaign, runMap: runMap,
                                         reshuffleIndex: self.reshuffleIndex, redealCost: self.redealCost,
                                         ambush: ambush)
                // An ambush reshuffle keeps its fixed shape (cards+piles from spec).
                if self.plan?.isAmbush == true { p.isAmbush = true; p.ambushBounty = self.plan!.ambushBounty; p.ambushNodeId = self.plan!.ambushNodeId }
                self.plan = p
                self.boot(plan: p)
            }
        }
    }

    private var zenDiffId: String? {
        if case .zen(_, let d) = mode { return d }
        return nil
    }
}

/// The shared hold-for-info copy for a single card (pile hold, fan-overlay
/// hold): the web's `cardPeekHtml` — the card head, then each sticker's label
/// + registry description (+ its live state line). Jokers short-circuit.
enum CardInfoText {
    static func make(_ card: LiveCard) -> (title: String, body: String) {
        // JOKER: its own one-line help (it can't carry stickers).
        if card.joker { return ("★ Joker", "Always safe on any guess") }
        let title = "Card \(card.label)\(card.suit)"
        guard !card.stickers.isEmpty else { return (title, "No stickers on this card.") }
        var counts: [String: Int] = [:]
        for s in card.stickers { counts[s.type, default: 0] += 1 }
        var rows: [String] = []
        for t in GameData.shared.stickerTypes.all() {
            guard let n = counts[t.id] else { continue }
            var row = t.label + (n > 1 ? " ×\(n)" : "") + " · " + t.description
                + CardInfo.provenance(onType: t.id, of: card.stickers)
            // The live state line, when the sticker type carries one.
            if t.behavior == "suitImmunity", let suit = t.suit {
                row += "\nAlways safe when a \(suit) is involved"
            } else if t.id == "compound" {
                row += "\nBanked: +\(max(0, card.compoundHits - 1)) coins"
            } else if t.id == "snowball" {
                row += "\nBuries next: \(card.snowball) card\(card.snowball == 1 ? "" : "s")"
            }
            rows.append(row)
        }
        return (title, rows.joined(separator: "\n"))
    }
}

/// Key-moment haptics (extended by the Chunk E sound pass).
enum Haptics2 {
    static func land(correct: Bool) {
        if correct { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        else { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    }
    static func dealEnd(won: Bool) {
        UINotificationFeedbackGenerator().notificationOccurred(won ? .success : .warning)
    }
    /// Web parity: MEDIUM on every save (guarded / second-wind / same-saved)
    /// and on same-banked.
    static func medium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    /// A curse landing a real blow (malfunction kill, sabotage).
    static func heavy() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }
}
