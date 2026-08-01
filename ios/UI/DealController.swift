import SpriteKit
import UIKit
import GameCore

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

    public struct Setup {
        public var deckId: String
        public var tier: String
        public var seed: UInt32
        public var pileCount: Int
        public var pillars: [String?]
        public var bases: [String?]
        public var samePower: String?
        public var sameCharge: Bool
        /// How many cards the deal plays. A real campaign deck grows from 13 to
        /// 40+ across a climb; the launcher lets that be dialled directly so the
        /// board can be exercised at a realistic depth.
        public var cardCount: Int
        /// Skip all motion (auto-play verification runs).
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

    private let setup: Setup
    private unowned let scene: DealScene
    private let campaign: CampaignState
    private var engine: GameEngine!
    private let economy = Economy()
    private let animQueue = AnimQueue()

    /// Coins/score the deal has banked so far (the campaign owns the totals).
    private var dealBase: Double = 0
    private var interactionLocked = true   // locked during the deal-out cascade
    public private(set) var isOver = false
    /// A fatal guess defers the end-of-deal banner until its death has played.
    private var pendingFinish: (() -> Void)?
    private var awaitingDeathFinish = false

    public init(setup: Setup, scene: DealScene) {
        self.setup = setup
        self.scene = scene
        self.campaign = CampaignState()
        campaign.setDeck(setup.deckId)
        campaign.setTier(setup.tier)
        campaign.setSeedOverride(setup.seed)
        campaign.reset()
        scene.controller = self
        scene.reduceMotion = setup.reduceMotion
    }

    // MARK: - Boot

    public func sceneReady() {
        let layout = CampaignLayout.layoutForPiles(setup.pileCount)
        engine = GameEngine(
            deckSpecs: dealDeck(),
            pileCount: setup.pileCount,
            runConfig: RunConfig(cols: layout.cols,
                                 sameCharge: setup.sameCharge,
                                 samePower: setup.samePower,
                                 noStickers: campaign.rules().noStickers))
        engine.on { [weak self] in self?.handle($0) }
        engine.start(seedOverride: setup.seed)
        engine.startRun(pillars: setup.pillars, bases: setup.bases, samePower: .some(setup.samePower))

        // The flat reward this deal pays if cleared (stage 1, rating 2 — the
        // debug launcher has no map node to read a real rating from).
        dealBase = economy.dealFlat(stage: 1, rating: 2, isBoss: false)

        scene.buildBoard(pileCount: setup.pileCount)
        scene.setPillars(setup.pillars, bases: setup.bases)
        refreshAll()
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

    /// The specs this deal is dealt from. The campaign's own 13-card start is
    /// used as-is when it is big enough; beyond that the deck is topped up from
    /// the standard 52 in suit order, the same way a climb accumulates cards.
    private func dealDeck() -> [CardSpec] {
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
            break

        case .guarded(let index, _, _, let drawn):
            // The drawn card flies in, taps the shielded pile, and bounces BACK
            // to the deck — the pile keeps its top. Sequenced after the draw
            // that triggered it (a guard IS the resolution, priority 0).
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
            // The charge is spent, the would-be-killer LANDS as the new top.
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
            // A consequence of the draw — animates AFTER it lands (priority 1):
            // a face-down card travels deck → pile, then the tuck plays.
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
            // Diamond Distribution: fly a face-down card along each net move,
            // staggered, after the triggering ♦ lands.
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

        case .cardDuplicated:
            if let sel = scene.currentSelection { scene.floatCue("DUPLICATED", at: sel, color: CRT.gold) }

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
                // The fatal guess's death presentation flushes this.
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
        // A directional guess that survived a TIE can only be a Tie-Safe save.
        let tieSafeSave = correct && guess != .same && drawn.value == current.value
        // A directional guess that DIED on a tie earns the nudge.
        let fatalTie = !correct && guess != .same && drawn.value == current.value

        // Deck character reaction: HAPPY on a won Same, GLAD on any other
        // correct guess, SAD when a pile is lost.
        if correct && guess == .same { scene.charReact(.happy) }
        else if correct { scene.charReact(.glad) }
        else { scene.charReact(.sad) }

        let land: () -> Void = { [weak self] in
            guard let self else { return }
            self.scene.endHold(index, suppressDead: !correct)
            self.scene.pileLandPop(index)
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
                        // Hold the recap a beat longer on a fatal tie so the
                        // "Shoulda said same" line is read first.
                        let beat = fatalTie ? 1.1 : 0.36
                        self.scene.run(.sequence([.wait(forDuration: beat), .run {
                            self.flushPendingFinish()
                        }]))
                    }
                }
            }
        }

        if setup.reduceMotion {
            land()
            if fatal { flushPendingFinish() }
            return
        }
        // The pile's visible top stays for the whole flight; the drawn face is
        // painted on landing. Priority 0 — the triggering draw.
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
            // Phoenix: revive flourish, THEN the buried cards travel back to
            // the deck (the killer stays as the fresh top).
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
        case "shuffleColumn", "evenOut":
            // The column reshuffled — pulse its alive piles.
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
        refreshAll()
        let payout = win ? currentPayout() : 0
        scene.showResultBanner(win ? "DEAL CLEARED · +\(Int(payout))" : "DEAL LOST", win: win)
        writeDealReceipt(win: win, payout: payout)
        onFinish?(win, Int(payout), currentScore())
    }

    /// Called when the deal ends: (won, coins, score).
    public var onFinish: ((Bool, Int, Int) -> Void)?

    /// Phase 2 has no summary screen yet, so the deal writes what it did — and
    /// crucially its FRAME TIMINGS — to `Documents/deal-receipt.json`. That is
    /// the measurement the perf claims are read from, on simulator or device.
    private func writeDealReceipt(win: Bool, payout: Double) {
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
        // Drain any queued prompts. Phase 2 has no prompt UI yet, so the
        // deterministic default is DECLINE — never silently spend the player's
        // coins on an offer they were never shown.
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
            deckId: setup.deckId)
        scene.syncBoard(snap)
    }

    private func refreshHUD() {
        guard let engine else { return }
        scene.syncHUD(stageLabel: "STG 1",
                      suitsInPlay: campaign.suitsInPlay(),
                      sameCharged: engine.sameCharge,
                      samePower: engine.equippedSamePower(),
                      coins: campaign.getCoins(),
                      deckCount: engine.deck.remaining(),
                      score: currentScore())
        scene.syncDeckPanel(counts: engine.deck.remainingCounts(),
                            suitCounts: engine.deck.remainingSuitCounts(),
                            total: engine.deck.remaining(),
                            remaining: engine.deck.remaining(),
                            deckId: setup.deckId,
                            mood: mood())
        // The peek chip: Scout / peek Pillars reveal the next upcoming draw.
        let peeking = engine.run.revealNextActive || engine.run.kamikazeRevealLeft > 0
        scene.syncDeckPeek(peeking ? engine.deck.peek(1).first.map(CardArt.Face.init) : nil)
        scene.syncReward(base: dealBase, bonus: liveBonus(), score: currentScore())
    }

    private func refreshControls() {
        let canGuess = !interactionLocked && !isOver
            && scene.currentSelection != nil && !engine.deck.isEmpty
        scene.syncControls(canGuess: canGuess,
                           showReshuffle: !isOver && engine.run.totalGuesses == 0 && !interactionLocked)
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
        s.flat = dealBase
        s.stage = 1
        s.rating = 2
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

    /// Re-deal the piles from the same deck (before the FIRST guess only).
    public func reshuffle() {
        guard !isOver, engine.run.totalGuesses == 0 else { return }
        interactionLocked = true
        animQueue.clear()
        engine.start(seedOverride: RNG.generateSeed())
        engine.startRun(pillars: setup.pillars, bases: setup.bases, samePower: .some(setup.samePower))
        scene.setSelected(nil)
        refreshAll()
        startCascade()
    }
}
