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

    private func bootDebug(_ setup: Setup) {
        let layout = CampaignLayout.layoutForPiles(setup.pileCount)
        engine = GameEngine(
            deckSpecs: debugDeck(setup),
            pileCount: setup.pileCount,
            runConfig: RunConfig(cols: layout.cols,
                                 sameCharge: setup.sameCharge,
                                 samePower: setup.samePower,
                                 noStickers: campaign.rules().noStickers))
        engine.on { [weak self] in self?.handle($0) }
        engine.start(seedOverride: setup.seed)
        engine.startRun(pillars: setup.pillars, bases: setup.bases, samePower: .some(setup.samePower))
        scene.buildBoard(pileCount: setup.pileCount)
        scene.setPillars(setup.pillars, bases: setup.bases)
        refreshAll()
        startCascade()
    }

    private func boot(plan p: DealPlan) {
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
        switch event {
        case .resolved(let index, let guess, let current, let drawn, let correct):
            handleResolved(index: index, guess: guess, current: current, drawn: drawn, correct: correct)

        case .pileKilled:
            // Stats only (web parity): the death VISUAL comes from the resolved
            // or base-fired handler that carries the context.
            if isCampaign, !campaign.isExhibition() { campaign.stats.bump("pilesLost") }

        case .guarded(let index, _, _, let drawn):
            animQueue.add(priority: 0) { [weak self] done in
                guard let self else { done(); return }
                self.scene.flyDraw(face: CardArt.Face(drawn), to: index) {
                    self.scene.pileLandPop(index)
                    self.scene.savedIndicator(at: index, label: "Guard")
                    self.scene.flyToDeck(face: CardArt.Face(drawn), from: index, delay: 0.12) { done() }
                }
            }

        case .secondWind(let index, _, _):
            animQueue.add(priority: 1) { [weak self] done in
                self?.scene.savedIndicator(at: index, label: "Second Wind")
                done()
            }

        case .sameSaved(let index, _, _, let drawn, _):
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
            if charged { scene.floatCue("＝ CHARGED", at: index, color: CRT.gold) }

        case .stickerCoins(let index, _, let amount):
            if amount != 0 {
                scene.floatCue(amount > 0 ? "+\(Int(amount))" : "−\(Int(abs(amount)))",
                               at: index, color: amount > 0 ? CRT.gold : CRT.suitRed)
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
            animQueue.add(priority: 1) { [weak self] done in
                self?.scene.powerFeedback(hub: res.hub, targets: res.targets, label: res.label)
                done()
            }

        case .revived(_, let index):
            scene.floatCue("REVIVED", at: index, color: CRT.phosphor)
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
                } else {
                    self.scene.goodPulse(at: index)
                }
                self.scene.refreshWeb()
                self.scene.synapsePulse(from: index)
                if drawn.joker { self.scene.floatCue("★", at: index, color: CRT.gold) }
            } else {
                if fatalTie { self.scene.shouldaNudge(at: index) }
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
            stickerPeels: engine.run.stickerPeels)
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
        guard !interactionLocked, !isOver else { return }
        guard let target = pile ?? scene.currentSelection else { return }
        guard engine.board.isActive(target), !engine.deck.isEmpty else { return }
        engine.guess(target, g)
        // Drain any queued prompts. The prompt/offer UI arrives with Chunk E;
        // until then the deterministic default is DECLINE — never silently
        // spend the player's coins on an offer they were never shown.
        while !engine.run.pendingTributes.isEmpty { engine.answerTribute(false) }
        while !engine.run.pendingActions.isEmpty { engine.answerAction(false) }
        if !isOver { scene.setSelected(nil); scene.charReleaseLook() }
        refreshAll()
    }

    /// Board reads the auto-play harness needs.
    public func alivePiles() -> [Int] {
        (0..<engine.board.size).filter { engine.board.isActive($0) }
    }
    public func topValue(_ index: Int) -> Int? { engine.board.top(index)?.value }

    public func pileCards(_ index: Int) -> [LiveCard] {
        guard index < engine.board.piles.count else { return [] }
        return engine.board.piles[index].cards
    }

    public func helpText(forPile index: Int) -> (String, String)? {
        guard let top = engine.board.top(index) else { return nil }
        let name = top.joker ? "★ Joker" : "\(top.label)\(top.suit)"
        var body = "Pile \(index + 1) · \(engine.board.piles[index].cards.count) cards"
        if engine.board.isAnchored(index) { body += " · anchored" }
        let stickers = top.stickers.compactMap { GameData.shared.stickerTypes.get($0.type) }
        if !stickers.isEmpty {
            body += ". " + stickers.map(\.label).joined(separator: ", ") + "."
            if let first = stickers.first { body += " " + first.description }
        } else {
            body += ". Swipe up for Higher, down for Lower, sideways for Same."
        }
        return (name, body)
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
            deckId: campaign.deckId)
        scene.syncBoard(snap)
    }

    private func stageLabel() -> String {
        if isZen { return "ZEN" }
        if case .campaign(let p) = mode { return p.isAmbush ? "AMBUSH" : "STG \(max(1, p.stage))" }
        return "STG 1"
    }

    private func refreshHUD() {
        guard let engine else { return }
        scene.syncHUD(stageLabel: stageLabel(),
                      suitsInPlay: isZen ? [] : campaign.suitsInPlay(),
                      sameCharged: engine.sameCharge,
                      samePower: engine.equippedSamePower(),
                      coins: campaign.getCoins(),
                      deckCount: engine.deck.remaining(),
                      score: currentScore())
        scene.syncDeckPanel(counts: engine.deck.remainingCounts(),
                            suitCounts: engine.deck.remainingSuitCounts(),
                            total: engine.deck.remaining(),
                            remaining: engine.deck.remaining(),
                            deckId: campaign.deckId,
                            mood: mood())
        let peeking = engine.run.revealNextActive || engine.run.kamikazeRevealLeft > 0
        scene.syncDeckPeek(peeking ? engine.deck.peek(1).first.map(CardArt.Face.init) : nil)
        scene.syncReward(base: plan?.flatReward ?? dealBaseDebug(), bonus: liveBonus(), score: currentScore())
    }

    private func dealBaseDebug() -> Double {
        economy.dealFlat(stage: 1, rating: 2, isBoss: false)
    }

    private func refreshControls() {
        let canGuess = !interactionLocked && !isOver
            && scene.currentSelection != nil && !engine.deck.isEmpty
        let canAffordReshuffle = !isCampaign || Double(campaign.getCoins()) >= redealCost
        scene.syncControls(canGuess: canGuess,
                           showReshuffle: !isOver && engine.run.totalGuesses == 0
                               && !interactionLocked && canAffordReshuffle)
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
    public func reshuffle() {
        guard !isOver, engine.run.totalGuesses == 0 else { return }
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
            interactionLocked = true
            animQueue.clear()
            let p = DealPlanner.zenPlan(diff: GameData.shared.difficulty.zen(zenDiffId ?? "easy"))
            plan = p
            boot(plan: p)

        case .campaign:
            guard let runMap, campaign.spendCoins(Int(redealCost)) else { return }
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
}
