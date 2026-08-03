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
    /// The guess that would have survived the last resolved draw (the web's
    /// `survivingGuessWord(lastResolvedDraw)`), stamped on every resolution.
    private var lastSurvivingWord: String?

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

    /// Rank value → count at deal start (jokers/blanks never join the histogram).
    private func rankTotals(_ specs: [CardSpec]) -> [Int: Int] {
        var t: [Int: Int] = [:]
        for c in specs where !c.joker && !c.blank { t[c.currentRank, default: 0] += 1 }
        return t
    }

    private func bootDebug(_ setup: Setup) {
        let layout = CampaignLayout.layoutForPiles(setup.pileCount)
        let specs = debugDeck(setup)
        dealSuitTotals = suitTotals(specs)
        dealRankTotals = rankTotals(specs)
        engine = GameEngine(
            deckSpecs: specs,
            pileCount: setup.pileCount,
            runConfig: RunConfig(cols: layout.cols,
                                 sameCharge: setup.sameCharge,
                                 samePower: setup.samePower,
                                 noStickers: campaign.rules().noStickers))
        engine.on { [weak self] in self?.handle($0) }
        engine.start(seedOverride: setup.seed)
        engine.startRun(pillars: setup.pillars, bases: setup.bases, samePower: .some(setup.samePower))
        _ = specs
        scene.slotsVisible = true   // debug deals are campaign-shaped
        scene.isZen = false
        scene.buildBoard(pileCount: setup.pileCount)
        scene.setPillars(setup.pillars, bases: setup.bases)
        refreshAll()
        startCascade()
    }

    private func boot(plan p: DealPlan) {
        dealSuitTotals = suitTotals(p.deckForDeal)
        dealRankTotals = rankTotals(p.deckForDeal)
        let layout = CampaignLayout.layoutForPiles(p.piles)
        let pillars = isZen ? [String?](repeating: nil, count: layout.cols.count) : campaign.columnPillars
        let bases = isZen ? [String?](repeating: nil, count: layout.cols.count) : campaign.columnBases
        let samePower = isZen ? nil : campaign.getSamePower()
        engine = GameEngine(
            deckSpecs: p.deckForDeal,
            pileCount: p.piles,
            runConfig: RunConfig(cols: layout.cols,
                                 sameCharge: isZen ? false : campaign.getSameCharge(),
                                 samePower: samePower,
                                 noStickers: campaign.rules().noStickers))
        engine.on { [weak self] in self?.handle($0) }
        engine.start(seedOverride: p.seed)
        engine.startRun(pillars: pillars, bases: bases, samePower: .some(samePower))
        scene.slotsVisible = !isZen   // Zen collapses the artifact slot rows
        scene.isZen = isZen
        scene.buildBoard(pileCount: p.piles)
        scene.setPillars(pillars, bases: bases)
        refreshAll()
        onCheckpoint?(self)   // "run" durability point: a kill now resumes this deal
        // SUBSET REVEAL: the anonymous "X of Y in play" flourish for fresh
        // subset deals (never bosses or full-deck).
        if p.subsetIds != nil && !reduceMotion {
            scene.playSubsetReveal(inPlay: p.deckForDeal.count, total: p.fullDeckCount)
        }
        startCascade()
    }

    /// The deal-out cascade: blank beat, then each pile's card flies in from
    /// the deck character. Control is handed over when the last card lands.
    private func startCascade() {
        interactionLocked = true
        scene.charReset()
        if !reduceMotion { Sound.shared.deal() }
        let n = engine.board.size
        let tops: [CardArt.Face?] = (0..<n).map { engine.board.top($0).map(CardArt.Face.init) }
        scene.dealCascade(tops: tops) { [weak self] in
            self?.interactionLocked = false
            self?.refreshAll()
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
                    self.scene.pileLandPop(index)
                    self.scene.savedIndicator(at: index, label: "Guard")
                    self.scene.flyToDeck(face: CardArt.Face(drawn), from: index, delay: 0.12) { done() }
                }
            }

        case .secondWind(let index, _, _):
            Haptics2.medium()   // web: MEDIUM on every save
            animQueue.add(priority: 1) { [weak self] done in
                self?.scene.savedIndicator(at: index, label: "Second Wind")
                done()
            }

        case .sameSaved(let index, _, _, let drawn, _):
            Haptics2.medium()   // web: MEDIUM on same-saved
            scene.beginHold(index)
            animQueue.add(priority: 0) { [weak self] done in
                guard let self else { done(); return }
                self.scene.flyDraw(face: CardArt.Face(drawn), to: index) {
                    self.scene.endHold(index)
                    self.scene.pileLandPop(index)
                    self.scene.savedIndicator(at: index, label: "Same Charge")
                    done()
                }
            }

        case .sameBanked(let index, let charged):
            if charged {
                Haptics2.medium()   // web: MEDIUM on same-banked
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
                    self.scene.buryTuck(at: index, count: count)
                    done()
                }
            }

        case .pillarFired(let col, let effect, _, let amount, let moves):
            scene.pulseColumn(col, base: false)
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
                if let sel = scene.currentSelection { scene.floatCue("DUPLICATED", at: sel, color: CRT.gold) }
                onCheckpoint?(self)
            }

        case .baseFired(let res):
            handleBaseFired(res)

        case .samePower(let res):
            Sound.shared.samePower()
            animQueue.add(priority: 1) { [weak self] done in
                self?.scene.powerFeedback(hub: res.hub, targets: res.targets, label: res.label)
                done()
            }

        case .reviveOffer(let col, _):
            // Surfaced after the triggering guess settles (drainPrompts).
            pendingReviveCol = col

        case .revived(_, let index):
            scene.floatCue("REVIVED", at: index, color: CRT.phosphor)
            Sound.shared.good()
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
            self.scene.pileLandPop(index)
            Haptics2.land(correct: correct)
            if correct {
                if tieSafeSave {
                    self.scene.savedIndicator(at: index, label: "Tie-Safe")
                    Sound.shared.save()
                } else {
                    self.scene.goodPulse(at: index)
                    Sound.shared.good()
                }
                self.scene.refreshWeb()
                self.scene.synapsePulse(from: index)
                if drawn.joker { self.scene.floatCue("★", at: index, color: CRT.gold) }
            } else {
                Sound.shared.death()
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
        switch res.effect {
        case "kamikaze":
            if let i = res.index { scene.playImmediateDeath(at: i) }
        case "heartDemolish":
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
            if isCampaign, let dcol = res.demolishedCol {
                campaign.setColumnPillar(col: dcol, typeId: nil)
                if let old = res.demolishedPillar { _ = campaign.discardPillarFromInventory(old) }
                scene.setPillars(campaign.columnPillars, bases: campaign.columnBases)
            }
        case "shuffleColumn", "evenOut":
            for i in pilesInColumn(res.col) where engine.board.isActive(i) {
                scene.goodPulse(at: i)
            }
        case "randomSticker":
            if let s = res.stickerApplied { scene.goodPulse(at: s.pileIndex) }
        case "setValue", "setSuit":
            for i in pilesInColumn(res.col) where engine.board.isActive(i) {
                scene.goodPulse(at: i)
            }
        default:
            break
        }
        // Durable card modifications last the REST OF THE RUN — write the same
        // change onto the persistent campaign card (web parity).
        if isCampaign {
            for v in res.valueApplied ?? [] { _ = campaign.randomizeCard(v.cardId, to: v.value) }
            for s in res.suitApplied ?? [] { _ = campaign.setCardSuit(s.cardId, to: s.suit) }
            if let s = res.stickerApplied { _ = campaign.applySticker(s.cardId, s.typeId) }
            onCheckpoint?(self)
        }
        refreshBoard()
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
            survivingGuessWord: win ? nil : lastSurvivingWord)
    }

    /// Debug path result: (won, coins, score).
    public var onFinish: ((Bool, Int, Int) -> Void)?
    /// Campaign/Zen path: the full outcome for the run-end fold.
    public var onOutcome: ((DealOutcome) -> Void)?
    /// A Zen guess resolved (correct?) — ZenStats tallies live in the flow.
    public var onZenGuess: ((Bool) -> Void)?
    /// Durability points ("run" checkpoints) — the flow persists here.
    public var onCheckpoint: ((DealController) -> Void)?

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

    // MARK: - Player actions

    public func select(pile: Int) {
        guard !interactionLocked, !isOver else { return }
        guard engine.board.isActive(pile) else { return }
        let selecting = scene.currentSelection != pile
        scene.setSelected(selecting ? pile : nil)
        if selecting { scene.charLookAt(pile: pile) } else { scene.charReleaseLook() }
        refreshControls()
    }

    public func guess(_ g: Guess, pile: Int? = nil) {
        guard !interactionLocked, !isOver, !promptActive else { return }
        guard let target = pile ?? scene.currentSelection else { return }
        guard engine.board.isActive(target), !engine.deck.isEmpty else { return }
        engine.guess(target, g)
        drainPrompts()
        if !isOver { scene.setSelected(nil); scene.charReleaseLook() }
        refreshAll()
    }

    // MARK: - In-deal offers (the paid-bury / shuffle / donate prompts)

    /// Ask the player a tribute question: (offer, answer-callback).
    public var onTributeOffer: ((TributeOffer, @escaping (Bool) -> Void) -> Void)?
    /// Ask about an optional post-landing action (shuffle / donate).
    public var onActionOffer: ((PendingAction, @escaping (Bool) -> Void) -> Void)?
    /// Revive targeting: (dead piles, fire(target?) — nil = skip).
    public var onReviveOffer: (([Int], @escaping (Int?) -> Void) -> Void)?
    private var promptActive = false
    private var pendingReviveCol: Int?

    /// Surface queued offers ONE at a time; with no UI handler installed
    /// (debug/auto-play) the deterministic default is DECLINE — never silently
    /// spend the player's coins on an offer they were never shown.
    private func drainPrompts() {
        guard !isOver else {
            while !engine.run.pendingTributes.isEmpty { engine.answerTribute(false) }
            while !engine.run.pendingActions.isEmpty { engine.answerAction(false) }
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
                if accept, a.kind == "shuffle" { Sound.shared.shuffle() }
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

    // MARK: - Base activation (tap-to-fire)

    /// Confirm + fire a charged Base: (label, description, needsTarget?, fire).
    public var onBasePrompt: ((String, String, @escaping () -> Void) -> Void)?
    /// Phoenix-style target pick: (dead piles, fire(target)).
    public var onBaseTarget: (([Int], @escaping (Int?) -> Void) -> Void)?

    public func basePlaqueTapped(col: Int) {
        guard !interactionLocked, !isOver, !promptActive else { return }
        guard engine.baseCanActivate(col) else { return }
        guard let id = (isCampaign || isZen) ? campaign.columnBase(col) : currentBaseId(col),
              let def = GameData.shared.baseTypes.get(id) else { return }
        if def.effect == "reviveBase" {
            let dead = deadPiles()
            guard !dead.isEmpty, let handler = onBaseTarget else { return }
            promptActive = true
            handler(dead) { [weak self] target in
                guard let self else { return }
                self.promptActive = false
                if let target {
                    _ = self.engine.baseActivate(col: col, targetIndex: target)
                    Sound.shared.samePower()
                }
                self.refreshAll()
            }
            return
        }
        guard let handler = onBasePrompt else {
            _ = engine.baseActivate(col: col)
            refreshAll()
            return
        }
        promptActive = true
        handler(def.label, def.description) { [weak self] in
            guard let self else { return }
            self.promptActive = false
            _ = self.engine.baseActivate(col: col)
            self.refreshAll()
        }
    }

    /// Notify the VC a prompt was dismissed without an answer path (cancel).
    public func promptDismissed() { promptActive = false }

    private func currentBaseId(_ col: Int) -> String? {
        if case .debug(let setup) = mode { return setup.bases[safe: col] ?? nil }
        return campaign.columnBase(col)
    }

    /// Which columns' bases can fire RIGHT NOW (drives the plaque pulse).
    public func activatableBaseColumns() -> [Int] {
        guard engine != nil, !isOver else { return [] }
        let cols = engine.run.cols?.count ?? 0
        return (0..<cols).filter { engine.baseCanActivate($0) }
    }

    /// Board reads the auto-play harness needs.
    public func alivePiles() -> [Int] {
        (0..<engine.board.size).filter { engine.board.isActive($0) }
    }
    public func topValue(_ index: Int) -> Int? { engine.board.top(index)?.value }
    /// Remaining rank counts — the odds-scripted player counts cards with this.
    public func deckCounts() -> [Int: Int] { engine.deck.remainingCounts() }
    /// Ids still in the draw pile — DeckInspect's remaining-vs-full shadow.
    public func remainingCardIds() -> Set<Int> { Set(engine.deck.peekAll().map(\.id)) }
    public var deckIsEmpty: Bool { engine.deck.isEmpty }
    public var promptIsUp: Bool { promptActive }

    public func pileCards(_ index: Int) -> [LiveCard] {
        guard index < engine.board.piles.count else { return [] }
        return engine.board.piles[index].cards
    }

    /// The web's hold-peek (`cardPeekHtml`): the card id on line 1, then the
    /// sticker/effect state — never pile trivia or swipe instructions.
    public func helpText(forPile index: Int) -> (String, String)? {
        guard let top = engine.board.top(index) else { return nil }
        // JOKER: its own one-line help (it can't carry stickers).
        if top.joker { return ("★ Joker", "Always safe on any guess") }
        let title = "Card \(top.label)\(top.suit)"
        guard !top.stickers.isEmpty else { return (title, "No stickers on this card.") }
        var counts: [String: Int] = [:]
        for s in top.stickers { counts[s.type, default: 0] += 1 }
        var rows: [String] = []
        for t in GameData.shared.stickerTypes.all() {
            guard let n = counts[t.id] else { continue }
            var row = t.label + (n > 1 ? " ×\(n)" : "") + " — " + t.description
            // The live state line, when the sticker type carries one.
            if t.behavior == "suitImmunity", let suit = t.suit {
                row += "\nAlways safe when a \(suit) is involved"
            } else if t.id == "compound" {
                row += "\nBanked: +\(max(0, top.compoundHits - 1)) coins"
            } else if t.id == "snowball" {
                row += "\nBuries next: \(top.snowball) card\(top.snowball == 1 ? "" : "s")"
            }
            rows.append(row)
        }
        return (title, rows.joined(separator: "\n"))
    }

    /// The top-bar chips' hold-for-help (web attachInput HUD copy, verbatim).
    public func helpText(forHUDChip id: String) -> (String, String)? {
        switch id {
        case "sameCharge":
            return ("Same Charge",
                    "Same Charge — a correct Same banks it (max 1); it auto-saves a pile from death as a last resort")
        case "samePower":
            guard let pid = engine?.equippedSamePower(),
                  let def = GameData.shared.samePowerTypes.get(pid) else { return nil }
            return (def.label, def.description)
        case "stageRun":
            return ("The climb",
                    "3 stages, each ending at a boss deal. Clear the stage-3 boss to win the campaign — losing any deal ends it.")
        case "dealStatus":
            return ("Reward & Score",
                    "Reward: base + bonus. The base is the flat coins this deal pays on a clear — set by its stage & difficulty (harder pays more), fixed for the deal. The bonus is what your items have piled on top so far (stickers, pillars, bases — live, and a Tribute can drag it negative). Score: surviving piles × the smallest surviving pile if you cleared right now — personal bests only, never coins.")
        case "score":
            return ("Score",
                    "Your score: surviving piles × the smallest pile on each cleared deal, added up over the climb. Banked as your campaign score when the ♠ boss falls — deals after that build your endless score. Chased for personal bests only; it never changes coins or play.")
        case "coins":
            return ("Coins",
                    "Coins — what you spend in the store on stickers, Pillars, Bases, cards and packs. Earned by clearing deals (base + bonus), plus Payout stickers, Pillar payouts and events. They carry for the whole climb; unlike Score, they change what you can buy.")
        default:
            return nil
        }
    }

    public func pushLinks(_ adj: [Int: [Int]]) { engine?.setLinks(adj) }

    // MARK: - Refresh

    public func refreshAll() {
        guard engine != nil else { return }
        refreshBoard()
        refreshHUD()
        refreshControls()
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
        scene.syncPillarBadges(pillarBadges())
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
                out[col] = .secondWind(spent: engine.run.secondWindUsed?[safe: col] ?? false)
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
        scene.syncHUD(phaseIndex: campaign.phaseIndex,
                      altSuits: campaign.rules().altSuits,
                      phasesTotal: campaign.phasesTotal(),
                      showTrack: !isZen,   // web hides the suit track in zen
                      sameCharged: engine.sameCharge,
                      samePower: engine.equippedSamePower(),
                      coins: campaign.getCoins(),
                      score: currentScore(),
                      zen: isZen)          // web hides score/coins/Same in zen
        scene.syncDeckPanel(counts: engine.deck.remainingCounts(),
                            suitCounts: engine.deck.remainingSuitCounts(),
                            total: engine.deck.remaining(),
                            remaining: engine.deck.remaining(),
                            deckId: campaign.deckId,
                            mood: mood(),
                            tier: isZen ? "regular" : campaign.difficultyTier,
                            suitTotals: dealSuitTotals,
                            rankTotals: dealRankTotals)
        let peeking = engine.run.revealNextActive || engine.run.kamikazeRevealLeft > 0
        scene.syncDeckPeek(peeking ? engine.deck.peek(1).first.map(CardArt.Face.init) : nil)
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
        // The web names the price on the button: `↺ RESHUFFLE · ◉ 10`
        // (campaign only — Zen has no reshuffle; debug deals are free).
        scene.setReshuffleTitle(isCampaign ? "↺ RESHUFFLE · ◉ \(Int(redealCost))" : "↺ RESHUFFLE")
        // Web parity (renderReshuffleBtn): the offer hides only once the first
        // guess is made; an UNAFFORDABLE price shows the button disabled, not
        // hidden.
        scene.syncControls(canGuess: canGuess,
                           showReshuffle: !isZen && !isOver && engine.run.totalGuesses == 0
                               && !interactionLocked,
                           reshuffleEnabled: canAffordReshuffle)
        scene.syncSpentBases(spentBaseColumns())
        scene.syncActivatableBases(activatableBaseColumns())
    }

    private func mood() -> DeckCharacter.Mood {
        if isOver { return engine.status == "won" ? .win : .sad }
        if engine.board.aliveCount() <= 2 { return .sad }
        return .idle
    }

    private func liveBonus() -> Double {
        var s = PayoutStats()
        s.liveBonusCoins = engine.run.bonusCoins
        s.pillarBonus = engine.pillarPayout().bonus
        s.extraCoinUnits = engine.board.extraCoinUnits()
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
        switch mode {
        case .debug(let setup):
            interactionLocked = true
            animQueue.clear()
            engine.start(seedOverride: RNG.generateSeed())
            engine.startRun(pillars: setup.pillars, bases: setup.bases, samePower: .some(setup.samePower))
            scene.setSelected(nil)
            refreshAll()
            startCascade()

        case .zen:
            Sound.shared.shuffle()
            interactionLocked = true
            animQueue.clear()
            let p = DealPlanner.zenPlan(diff: GameData.shared.difficulty.zen(zenDiffId ?? "easy"))
            plan = p
            boot(plan: p)

        case .campaign:
            guard let runMap, campaign.spendCoins(Int(redealCost)) else { return }
            Sound.shared.shuffle()
            interactionLocked = true
            animQueue.clear()
            reshuffleIndex += 1
            redealCost += DealPlanner.redealStep
            let ambush: DealPlanner.AmbushSpec? = (plan?.isAmbush == true && plan?.ambushNodeId != nil)
                ? DealPlanner.AmbushSpec(cards: 0, piles: plan!.piles,
                                         bounty: plan!.ambushBounty, nodeId: plan!.ambushNodeId!)
                : nil
            var p = DealPlanner.plan(campaign: campaign, runMap: runMap,
                                     reshuffleIndex: reshuffleIndex, redealCost: redealCost,
                                     ambush: ambush)
            // An ambush reshuffle keeps its fixed shape (cards+piles from spec).
            if plan?.isAmbush == true { p.isAmbush = true; p.ambushBounty = plan!.ambushBounty; p.ambushNodeId = plan!.ambushNodeId }
            plan = p
            scene.setSelected(nil)
            boot(plan: p)
        }
    }

    private var zenDiffId: String? {
        if case .zen(_, let d) = mode { return d }
        return nil
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
}
