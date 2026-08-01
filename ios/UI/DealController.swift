import SpriteKit
import UIKit
import GameCore

/// Wires GameCore to the scene. The engine owns every rule; this only listens
/// to its events, plays the matching feedback, and pushes fresh state in.
///
/// Nothing here computes game state — a divergence between the web and iOS can
/// only come from GameCore, which the Phase 1 fixtures already pin.
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
        public init(deckId: String = "pink", tier: String = "regular", seed: UInt32 = 12345,
                    pileCount: Int = 9, pillars: [String?] = [nil, nil, nil],
                    bases: [String?] = [nil, nil, nil], samePower: String? = nil,
                    sameCharge: Bool = false, cardCount: Int = 39) {
            self.deckId = deckId; self.tier = tier; self.seed = seed; self.pileCount = pileCount
            self.pillars = pillars; self.bases = bases; self.samePower = samePower
            self.sameCharge = sameCharge; self.cardCount = cardCount
        }
    }

    private let setup: Setup
    private unowned let scene: DealScene
    private let campaign: CampaignState
    private var engine: GameEngine!
    private let economy = Economy()

    /// Coins/score the deal has banked so far (the campaign owns the totals).
    private var dealBase: Double = 0
    private var interactionLocked = true   // locked during the deal-out cascade
    public private(set) var isOver = false

    public init(setup: Setup, scene: DealScene) {
        self.setup = setup
        self.scene = scene
        self.campaign = CampaignState()
        campaign.setDeck(setup.deckId)
        campaign.setTier(setup.tier)
        campaign.setSeedOverride(setup.seed)
        campaign.reset()
        scene.controller = self
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
        // Deal-out cascade from the deck panel, then hand over control.
        scene.dealOutAnimation(from: CGPoint(x: scene.size.width - 60, y: -120)) { [weak self] in
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
        case .resolved(let index, _, _, let drawn, let correct):
            if correct {
                scene.pileLandPop(index)
                if drawn.joker { scene.floatCue("★", at: index, color: CRT.gold) }
            } else {
                scene.pileWince(index)
            }
            refreshBoard()

        case .pileKilled(let index):
            scene.pileWince(index)
            scene.floatCue("DEAD", at: index, color: CRT.suitRed)

        case .guarded(let index, _, _, _):
            scene.floatCue("GUARD", at: index, color: CRT.phosphor)

        case .secondWind(let index, _, _):
            scene.floatCue("SECOND WIND", at: index, color: CRT.phosphor)

        case .sameSaved(let index, _, _, _, _):
            scene.floatCue("SAVED", at: index, color: CRT.phosphor)

        case .sameBanked(let index, let charged):
            if charged { scene.floatCue("＝", at: index, color: CRT.gold) }

        case .stickerCoins(let index, _, let amount):
            scene.floatCue(amount >= 0 ? "+\(Int(amount))" : "\(Int(amount))",
                           at: index, color: amount >= 0 ? CRT.gold : CRT.suitRed)

        case .buried(let index, let count, _):
            scene.floatCue("⤓\(count)", at: index, color: CRT.muted)

        case .pillarFired(let col, _, _, let amount, _):
            scene.pulseColumn(col, base: false)
            if amount != 0, let p = firstPile(inColumn: col) {
                scene.floatCue(amount > 0 ? "+\(Int(amount))" : "\(Int(amount))",
                               at: p, color: amount > 0 ? CRT.gold : CRT.suitRed)
            }

        case .baseFired(let res):
            scene.pulseColumn(res.col, base: true)

        case .samePower(let res):
            for t in res.targets { scene.floatCue("◆", at: t, color: CRT.phosphor) }

        case .revived(_, let index):
            scene.floatCue("REVIVED", at: index, color: CRT.phosphor)

        case .won:
            finish(win: true)

        case .lost:
            finish(win: false)

        default:
            break
        }
    }

    private func firstPile(inColumn col: Int) -> Int? {
        engine.run.pileColumns?.firstIndex(of: col)
    }

    private func finish(win: Bool) {
        isOver = true
        interactionLocked = true
        scene.crtFlicker()               // the ONE-SHOT flicker, deal end only
        scene.setSelected(nil)
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
        scene.setSelected(scene.currentSelection == pile ? nil : pile)
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
        if !isOver { scene.setSelected(nil) }
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
        let alive = engine.board.aliveCount()
        if alive <= 2 { return .sad }
        if engine.sameCharge { return .happy }
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
        engine.start(seedOverride: RNG.generateSeed())
        engine.startRun(pillars: setup.pillars, bases: setup.bases, samePower: .some(setup.samePower))
        scene.setSelected(nil)
        refreshAll()
        scene.dealOutAnimation(from: CGPoint(x: scene.size.width - 60, y: -120)) { [weak self] in
            self?.interactionLocked = false
            self?.refreshAll()
        }
    }
}
