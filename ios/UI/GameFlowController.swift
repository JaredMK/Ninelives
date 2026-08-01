import UIKit
import GameCore

/// THE campaign shell — the app's root. Owns the ONE persistent CampaignState,
/// the save blob, and every screen transition:
///
///   menu → deck select → map ⇄ store ⇄ deal → summary → … → home → endless
///        → zen · collection · stats
///
/// Screens are swapped as single child view controllers; phase overlays and
/// the pause menu ride ON TOP as views. The CRT layer sits above everything.
public final class GameFlowController: UIViewController {

    // MARK: - The persistent world

    let store = UserDefaultsStore()
    private(set) var campaign: CampaignState
    private(set) var runMap: RunMap
    private let economy = Economy()

    /// The deck roster, verbatim from the web.
    struct DeckInfo {
        let id: String
        let name: String
        let requires: String?
        let sub: String
        let unlockNote: String?
    }
    static let decks: [DeckInfo] = [
        DeckInfo(id: "pink", name: "Pinky", requires: nil, sub: "Get Pinky home", unlockNote: nil),
        DeckInfo(id: "mamma", name: "Mamma", requires: "pink", sub: "Mamma sets off",
                 unlockNote: "Win a climb with Pinky to unlock"),
        DeckInfo(id: "smith", name: "Mr. Smith", requires: "mamma", sub: "Everything costs more",
                 unlockNote: "Win a climb with Mamma to unlock"),
        DeckInfo(id: "lammy", name: "Lammy", requires: "smith", sub: "Stickers don't stick",
                 unlockNote: "Win a climb with Mr. Smith to unlock"),
    ]

    // Deal-session state (persisted in the save blob).
    private var reshuffleIndex = 0
    private var redealCost = DealPlanner.redealBaseCost
    private var currentPhase = "menu"          // menu | map | store | run
    private var pendingAmbushNodeId: Int?
    private var currentAmbush: DealPlanner.AmbushSpec?
    /// The deck newly unlocked by this run's first win — celebration armed at
    /// the ♠-boss win, consumed at run termination. Session-only by design.
    private var pendingUnlockCelebration: DeckInfo?
    /// A mystery "store" detour's one-shot continuation.
    private var mysteryStoreContinue: (() -> Void)?

    // Zen session state.
    private var zenDiff: String?
    private var zenCounted = false
    private var zenFlips = 0
    private var zenCorrect = 0
    var tutorialReplayArmed = false
    private var tutorialRanThisSession = false

    private var current: UIViewController?
    private let crt = CRTOverlayUIView()
    let prompt = PromptBar()
    private var autopilot: FlowAutopilot?

    public init() {
        self.campaign = CampaignState(store: store)
        self.runMap = RunMap(data: GameData.shared)
        super.init(nibName: nil, bundle: nil)
        PersistenceHolder.shared = self
        campaign.itemUnlocks.primeKnown()   // first-session unlocks must not be swallowed
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    public override var prefersStatusBarHidden: Bool { true }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = CRT.feltDeep
        crt.isUserInteractionEnabled = false
        view.addSubview(crt)
        view.addSubview(prompt)
        boot()
        // Screenshot harness: `-showOverlay cleared|dead|victory|mystery`
        // renders that overlay with sample data (debug evidence stills only).
        if let which = UserDefaults.standard.string(forKey: "showOverlay") {
            showDebugOverlay(which)
        }
    }

    private func showDebugOverlay(_ which: String) {
        switch which {
        case "cleared":
            let info = SummaryInfo(earned: 9, balance: 21,
                                   lines: [("Deal reward", 7), ("Pillar bonus", 2)],
                                   product: 12, aliveCount: 4, minAlive: 3,
                                   progress: "STAGE 1 · DEAL 2")
            presentOverlay(PhaseOverlayView.dealCleared(info: info) { [weak self] in self?.dismissOverlay() })
        case "dead":
            let info = FailedInfo(correct: 11, wrong: 1, cardsFlipped: 12, coinsEarned: 6, wasEndless: false)
            presentOverlay(PhaseOverlayView.gameOver(
                info: info, seed: "PINK-REGULAR-ABC2345",
                nearest: campaign.itemUnlocks.nearestLocked(2)) { [weak self] in self?.dismissOverlay() })
        case "victory":
            presentOverlay(PhaseOverlayView.pinkyHome(
                deckName: "Pinky", score: 44, coins: 31, cards: 19, bestScore: 51,
                onEndless: { [weak self] in self?.dismissOverlay() },
                onMenu: { [weak self] in self?.dismissOverlay() }))
        case "mystery":
            if let o = campaign.applyMysteryEvent("coinBonus", nodeId: 7) {
                presentOverlay(PhaseOverlayView.mystery(outcome: o) { [weak self] in self?.dismissOverlay() })
            }
        default:
            break
        }
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        crt.frame = view.bounds
        prompt.frame = view.bounds
        current?.view.frame = view.bounds
    }

    // MARK: - Screen swapping

    func setScreen(_ vc: UIViewController) {
        // A screen change ends any phase overlay's moment — without this the
        // old overlay view lingers invisibly UNDER the new screen (and keeps
        // eating the autopilot's taps).
        dismissOverlay()
        let old = current
        addChild(vc)
        vc.view.frame = view.bounds
        view.insertSubview(vc.view, belowSubview: crt)
        vc.didMove(toParent: self)
        current = vc
        old?.willMove(toParent: nil)
        old?.view.removeFromSuperview()
        old?.removeFromParent()
    }

    // MARK: - Boot + persistence

    private func boot() {
        // Harness override: `-resetAll 1` = a factory-fresh install (the UI
        // tests use it so the zen-first tutorial arms).
        if UserDefaults.standard.bool(forKey: "resetAll") {
            for key in store.ninelivesKeys() { store.remove(forKey: key) }
            campaign = CampaignState(store: store)
            campaign.itemUnlocks.primeKnown()
        }
        // Harness override: `-skipGate 1` opens the campaign without the
        // zen-first gate (simulator verification runs).
        if UserDefaults.standard.bool(forKey: "skipGate") {
            campaign.saveStore.setPref("tutorial2", "1")
            campaign.saveStore.setPref("campaignUnlocked", "1")
        }
        let auto = UserDefaults.standard.integer(forKey: "autoCampaign")
        if auto > 0, autopilot == nil {
            campaign.saveStore.setPref("tutorial2", "1")
            campaign.saveStore.setPref("campaignUnlocked", "1")
            clearSave()
            autopilot = FlowAutopilot(flow: self, attempts: auto)
        }
        if campaign.saveStore.hasSave {
            resumeSavedGame()
        } else if UserDefaults.standard.bool(forKey: "autoClimb") {
            // Harness: straight into a fresh climb (simulator verification).
            let deck = UserDefaults.standard.string(forKey: "deck") ?? "pink"
            let tier = UserDefaults.standard.string(forKey: "tier") ?? "regular"
            let seed = UserDefaults.standard.object(forKey: "seed") != nil
                ? UInt32(truncatingIfNeeded: UserDefaults.standard.integer(forKey: "seed")) : nil
            startCampaign(deckId: deck, tier: tier, seedU32: seed)
        } else {
            showMenu()
        }
    }

    /// The save blob: phase + the campaign serialization + the live deal
    /// identity, so a kill resumes exactly where the player was.
    func persist(phase: String) {
        currentPhase = phase
        var blob = campaign.serialize()
        blob["phase"] = .string(phase)
        blob["reshuffleIndex"] = .number(Double(reshuffleIndex))
        blob["redealCost"] = .number(redealCost)
        if phase == "run", let dealVC = current as? DealViewController,
           let c = dealVC.controller {
            blob["dealSeed"] = .number(Double(c.currentSeed))
            if let p = c.currentPlan {
                var subset: [String: JSONValue] = ["piles": .number(Double(p.piles))]
                if let ids = p.subsetIds { subset["ids"] = .array(ids.map { .number(Double($0)) }) }
                if p.isAmbush {
                    subset["forced"] = .bool(true)
                    subset["bounty"] = .number(p.ambushBounty)
                    if let nid = p.ambushNodeId { subset["ambushNodeId"] = .number(Double(nid)) }
                }
                blob["dealSubset"] = .object(subset)
            }
        }
        if let nid = pendingAmbushNodeId { blob["pendingAmbushNodeId"] = .number(Double(nid)) }
        campaign.saveStore.save(blob)
    }

    func clearSave() {
        campaign.saveStore.clear()
    }

    private func resumeSavedGame() {
        guard let blob = campaign.saveStore.load(), campaign.restore(blob) else {
            clearSave()
            showMenu()
            return
        }
        runMap.setDifficultyTier(campaign.difficultyTier)
        reshuffleIndex = Int(blob["reshuffleIndex"]?.asNumber ?? 0)
        redealCost = blob["redealCost"]?.asNumber ?? DealPlanner.redealBaseCost
        pendingAmbushNodeId = blob["pendingAmbushNodeId"]?.asNumber.map(Int.init)
        let phase = blob["phase"]?.asString ?? "map"
        switch phase {
        case "run":
            // Replay the persisted deal exactly: saved seed + subset order.
            let seed = blob["dealSeed"]?.asNumber.map { UInt32($0) }
            let sub = blob["dealSubset"]?.asObject
            let subsetIds = sub?["ids"]?.asArray?.compactMap { $0.asNumber.map(Int.init) }
            let subsetPiles = sub?["piles"]?.asNumber.map(Int.init)
            var ambush: DealPlanner.AmbushSpec?
            if sub?["forced"]?.asBool == true {
                ambush = DealPlanner.AmbushSpec(cards: 0, piles: subsetPiles ?? 9,
                                                bounty: sub?["bounty"]?.asNumber ?? 0,
                                                nodeId: sub?["ambushNodeId"]?.asNumber.map(Int.init)
                                                    ?? campaign.nodePos ?? 0)
            }
            currentAmbush = ambush
            startDeal(resumeSeed: seed, resumeSubsetIds: subsetIds, resumePiles: subsetPiles)
        case "store":
            showStore(fresh: false)
        default:
            showMap()
        }
    }

    // MARK: - Menu

    func showMenu() {
        currentPhase = "menu"
        let menu = MainMenuViewController(flow: self, canContinue: campaign.saveStore.hasSave)
        setScreen(menu)
    }

    /// CONTINUE CLIMB from the menu: restore + route by the saved phase.
    func resumeFromMenu() {
        // A fresh CampaignState guarantees no menu-session state bleeds in.
        campaign = CampaignState(store: store)
        campaign.itemUnlocks.primeKnown()
        runMap = RunMap(data: GameData.shared)
        boot()
    }

    /// The double-confirmed full wipe — only preferences survive by design
    /// choice of the sound pref; here everything under ninelives.* goes.
    func resetAllProgress() {
        for key in store.ninelivesKeys() { store.remove(forKey: key) }
        campaign = CampaignState(store: store)
        campaign.itemUnlocks.primeKnown()
        runMap = RunMap(data: GameData.shared)
        showMenu()
    }

    func showDeckSelect() {
        setScreen(DeckSelectViewController(flow: self))
    }

    func showZenSelect() {
        setScreen(ZenSelectViewController(flow: self))
    }

    func showCollection() {
        setScreen(CollectionViewController(flow: self))
    }

    /// Lifetime stats ride a bottom sheet over whatever's showing (web parity).
    func showStats() {
        let sheet = StatsSheetView(campaign: campaign)
        sheet.onReset = { [weak self, weak sheet] in
            guard let self else { return }
            // The confirm bar must clear the sheet it was summoned from.
            self.view.insertSubview(self.prompt, belowSubview: self.crt)
            self.prompt.show("Reset lifetime stats?", help: "Unlock progress derives from stats.", actions: [
                .init("Cancel", role: .plain) { [weak self] in self?.prompt.hide() },
                .init("Reset", role: .danger) { [weak self] in
                    self?.prompt.hide()
                    self?.campaign.stats.reset()
                    sheet?.refresh()
                },
            ]) { [weak self] in self?.prompt.hide() }
        }
        sheet.present(in: view, below: crt)
    }

    /// Campaign appears on the menu only after the tutorial + a first Zen
    /// session (the web's zen-first gate).
    func campaignUnlocked() -> Bool {
        if campaign.saveStore.pref("campaignUnlocked") == "1" { return true }
        let done = campaign.saveStore.pref("tutorial2") == "1" && campaign.zenStats.totalGames() >= 1
        if done { campaign.saveStore.setPref("campaignUnlocked", "1") }
        return done
    }

    // MARK: - Campaign lifecycle

    /// START CLIMB from deck select. A player-entered seed flags EXHIBITION.
    func startCampaign(deckId: String, tier: String, seedU32: UInt32?) {
        clearSave()
        campaign.setDeck(deckId)
        campaign.setTier(tier)
        campaign.setSeedOverride(seedU32)
        campaign.reset()
        campaign.setDeck(deckId)
        campaign.setTier(tier)
        campaign.startNewRun()
        runMap.setDifficultyTier(tier)
        reshuffleIndex = 0
        redealCost = DealPlanner.redealBaseCost
        pendingAmbushNodeId = nil
        currentAmbush = nil
        persist(phase: "map")
        showMap()
    }

    func showMap() {
        currentPhase = "map"
        mysteryStoreContinue = nil   // a detour never survives leaving the store
        // Pinky home with nowhere further to go → the victory screen IS this state.
        if let cur = campaign.currentNode(), cur.type == "home",
           campaign.legalNextNodes().isEmpty {
            showPinkyHome()
            return
        }
        let map = MapViewController(campaign: campaign)
        map.delegate = self
        map.debugJumpEnabled = UserDefaults.standard.bool(forKey: "debugMap")
        setScreen(map)
        persist(phase: "map")
    }

    func showStore(fresh: Bool, nodeId: Int? = nil) {
        currentPhase = "store"
        if fresh { campaign.discardStoreOffer() }
        let sv = StoreViewController(campaign: campaign)
        sv.offerNodeId = nodeId
        sv.delegate = self
        setScreen(sv)
        persist(phase: "store")
    }

    // MARK: - Deals

    func startDeal(resumeSeed: UInt32? = nil, resumeSubsetIds: [Int]? = nil, resumePiles: Int? = nil) {
        if resumeSeed == nil { reshuffleIndex = 0; redealCost = DealPlanner.redealBaseCost }
        let plan = DealPlanner.plan(campaign: campaign, runMap: runMap,
                                    reshuffleIndex: reshuffleIndex, redealCost: redealCost,
                                    ambush: currentAmbush,
                                    resumeSeed: resumeSeed, resumeSubsetIds: resumeSubsetIds,
                                    resumePiles: resumePiles)
        currentPhase = "run"
        let vc = DealViewController(mode: .campaign(plan), campaign: campaign, runMap: runMap)
        vc.onOutcome = { [weak self] outcome in self?.onRunEnd(outcome) }
        vc.onMenu = { [weak self] in self?.showPauseMenu() }
        setScreen(vc)
        persist(phase: "run")
    }

    /// The web's onRunEnd — every fold, ported.
    private func onRunEnd(_ o: DealOutcome) {
        let wasAmbush = currentAmbush != nil
        let ambushBounty = currentAmbush?.bounty ?? 0
        let ambushNodeId = currentAmbush?.nodeId
        let exhibition = campaign.isExhibition()

        campaign.addCardsFlipped(o.cardsDrawn)
        campaign.addRunGuesses(correct: o.correctGuesses, total: o.totalGuesses)
        if !exhibition {
            var s = campaign.stats.get()
            s.lifetimeCardsDrawn += o.cardsDrawn
            s.lifetimeCorrectGuesses += o.correctGuesses
            s.lifetimeGuesses += o.totalGuesses
            campaign.stats.put(s)
        }

        if !o.won {
            currentAmbush = nil
            pendingAmbushNodeId = nil
            if !exhibition {
                var s = campaign.stats.get()
                s.lifetimeDopamine += max(0, Int(o.bonusCoins))
                if campaign.runWonBanked {
                    s.lifetimeCardsFlipped += campaign.unbankedCardsFlipped()
                    s.bestEndlessScore = max(s.bestEndlessScore, campaign.getEndlessScore())
                    s.bestEndless = max(s.bestEndless, campaign.endlessStagesReached())
                } else {
                    s.lifetimeCardsFlipped += campaign.totalCardsFlipped
                    s.furthestStage = max(s.furthestStage, campaign.phaseIndex + 1)
                }
                campaign.stats.put(s)
            }
            clearSave()   // a loss wipes the campaign — no resume of a dead run
            let failed = FailedInfo(correct: o.correctGuesses,
                                    wrong: o.totalGuesses - o.correctGuesses,
                                    cardsFlipped: campaign.totalCardsFlipped,
                                    coinsEarned: campaign.totalCoinsEarned,
                                    wasEndless: campaign.runWonBanked)
            runUnlockPops { [weak self] in self?.showCampaignFailed(failed) }
            return
        }

        // WIN: durable write-backs, coins, score, node clear, banking.
        for (id, n) in o.compoundUpdates { campaign.setCompoundHits(id, n) }
        for (id, n) in o.snowballUpdates { campaign.setSnowball(id, n) }
        for (id, n) in o.stickerPeels { _ = campaign.removeStickerInstances(id, "quickBury", n) }
        campaign.setSameCharge(o.sameCharge)

        var bonusEvents = o.bonusEvents
        var eventBonus = o.bonusCoins
        if wasAmbush, ambushBounty > 0 {
            eventBonus += ambushBounty
            bonusEvents.append(("Ambush", ambushBounty))
        }
        let node = campaign.currentNode()
        let payoutBoss = !wasAmbush && node?.type == "boss"
        let payoutStage = !wasAmbush ? ((node?.phase ?? -1) + 1) : 0
        let payoutRating = payoutBoss ? 3
            : (payoutStage > 0 && (node?.targetD ?? 0) > 0
               ? runMap.difficultyScore(targetD: node!.targetD!, phaseIndex: node!.phase, isBoss: false)
               : 0)
        var s = PayoutStats()
        s.won = true
        s.flat = economy.dealFlat(stage: payoutStage, rating: payoutRating, isBoss: payoutBoss)
        if wasAmbush { s.flat = 0 }
        s.stage = payoutStage
        s.rating = payoutRating
        s.ambush = wasAmbush
        s.aliveCount = o.aliveCount
        s.minAliveCards = o.minAliveCards
        s.extraCoinUnits = o.extraCoinUnits
        s.pillarBonus = o.pillarPayout.bonus
        s.pillarLines = o.pillarPayout.lines
        s.eventBonus = eventBonus
        s.eventLines = bonusEvents.map { PayoutLine(label: $0.label, detail: "", amount: $0.amount) }
        let payout = economy.breakdown(s)
        if payout.total > 0 { _ = campaign.earnCoins(Int(payout.total)) }
        campaign.addRunScore(Int(payout.product))

        if !exhibition {
            var st = campaign.stats.get()
            st.runsCleared += 1
            st.lifetimeDopamine += Int(payout.total)
            st.bestRunDopamine = max(st.bestRunDopamine, Int(payout.total))
            if campaign.runWonBanked {
                st.bestEndlessScore = max(st.bestEndlessScore, campaign.getEndlessScore())
            }
            campaign.stats.put(st)
        }

        let clearedNode = campaign.currentNode()
        if let clearedNode, !wasAmbush {
            _ = campaign.markNodeCleared(clearedNode.id)
            if !exhibition, clearedNode.type == "boss" { campaign.stats.bump("bossesBeaten") }
        }
        if campaign.isEndless(), !exhibition {
            var st = campaign.stats.get()
            st.bestEndless = max(st.bestEndless, campaign.endlessStagesReached())
            campaign.stats.put(st)
        }
        let runWon = !wasAmbush && clearedNode?.type == "boss"
            && campaign.isRunBoss(clearedNode!.id)

        if wasAmbush {
            pendingAmbushNodeId = ambushNodeId
            currentAmbush = nil
        }

        if runWon, !exhibition {
            campaign.markRunWon()
            var st = campaign.stats.get()
            st.campaignsWon += 1
            st.lifetimeCardsFlipped += campaign.totalCardsFlipped
            st.bestCampaignDopamine = max(st.bestCampaignDopamine, campaign.totalCoinsEarned)
            st.bestCampaignScore = max(st.bestCampaignScore, campaign.getCampaignScore())
            st.furthestStage = max(st.furthestStage, campaign.phasesTotal())
            st.deckTierWins["\(campaign.deckId).\(campaign.difficultyTier)"] = true
            campaign.stats.put(st)
            let wonTier = campaign.difficultyTier
            if campaign.deckUnlocks.recordWin(deckId: campaign.deckId, tier: wonTier), wonTier == "regular" {
                if let idx = Self.decks.firstIndex(where: { $0.id == campaign.deckId }),
                   idx + 1 < Self.decks.count {
                    pendingUnlockCelebration = Self.decks[idx + 1]
                }
            }
            if wonTier == "legendary" { _ = campaign.deckUnlocks.recordWin(deckId: campaign.deckId, tier: "master") }
            if wonTier != "regular",
               campaign.deckUnlocks.recordWin(deckId: campaign.deckId, tier: "regular"),
               pendingUnlockCelebration == nil,
               let idx = Self.decks.firstIndex(where: { $0.id == campaign.deckId }),
               idx + 1 < Self.decks.count {
                pendingUnlockCelebration = Self.decks[idx + 1]
            }
        }

        // STATIC volatility: every self-destruct Pillar rolls at deal end —
        // the roll rides the ACTION stream so a refresh replays the outcome.
        var staticLines: [(String, Int)] = []
        for c in 0..<campaign.columnPillars.count {
            guard let id = campaign.columnPillars[c],
                  let t = GameData.shared.pillarTypes.get(id) else { continue }
            let chance = t.num("selfDestruct", 0)
            guard chance > 0 else { continue }
            let destroyed = campaign.actionRng().next() < chance
            if destroyed {
                campaign.setColumnPillar(col: c, typeId: nil)
                _ = campaign.discardPillarFromInventory(id)
                staticLines.append(("⚡ \(t.label) blew up", 0))
            } else {
                staticLines.append(("⚡ \(t.label) held", 0))
            }
        }

        persist(phase: wasAmbush ? "run" : "map")
        let summary = SummaryInfo(earned: Int(payout.total),
                                  balance: campaign.getCoins(),
                                  lines: summaryLines(payout, flat: s.flat) + staticLines,
                                  product: Int(payout.product),
                                  aliveCount: o.aliveCount,
                                  minAlive: o.minAliveCards,
                                  progress: stageRunShort())
        showRunComplete(summary)
    }

    private func summaryLines(_ p: PayoutBreakdown, flat: Double) -> [(String, Int)] {
        var lines: [(String, Int)] = []
        if flat > 0 { lines.append(("Deal reward", Int(flat))) }
        for l in p.eventLines where l.amount != 0 { lines.append((l.label, Int(l.amount))) }
        for l in p.pillarLines where l.amount != 0 { lines.append((l.label, Int(l.amount))) }
        if p.extraCoinBonus > 0 { lines.append(("Extra Coin", Int(p.extraCoinBonus))) }
        return lines
    }

    private func stageRunShort() -> String {
        let pi = campaign.phaseIndex
        let total = campaign.phasesTotal()
        if pi >= total { return "ENDLESS stage \(pi - total + 1) · Deck \(campaign.deckSize())" }
        return "\(campaign.phaseSuit()) phase \(pi + 1)/\(total) · Deck \(campaign.deckSize())"
    }

    // MARK: - Summary + end screens

    struct SummaryInfo {
        var earned: Int
        var balance: Int
        var lines: [(String, Int)]
        var product: Int
        var aliveCount: Int
        var minAlive: Int
        var progress: String
    }

    struct FailedInfo {
        var correct: Int
        var wrong: Int
        var cardsFlipped: Int
        var coinsEarned: Int
        var wasEndless: Bool
    }

    private func showRunComplete(_ info: SummaryInfo) {
        let overlay = PhaseOverlayView.dealCleared(info: info) { [weak self] in
            self?.continueCampaign()
        }
        presentOverlay(overlay)
    }

    private func showCampaignFailed(_ info: FailedInfo) {
        let seedStr = seedShareString()
        let overlay = PhaseOverlayView.gameOver(info: info, seed: seedStr,
                                               nearest: campaign.itemUnlocks.nearestLocked(2)) { [weak self] in
            guard let self else { return }
            self.campaign.reset()
            self.showMenu()
        }
        presentOverlay(overlay)
        crt.flicker()
    }

    func showPinkyHome() {
        currentPhase = "map"
        let s = campaign.stats.get()
        let overlay = PhaseOverlayView.pinkyHome(
            deckName: Self.decks.first { $0.id == campaign.deckId }?.name ?? "Pinky",
            score: campaign.getCampaignScore(),
            coins: campaign.totalCoinsEarned,
            cards: campaign.totalCardsFlipped,
            bestScore: s.bestCampaignScore,
            onEndless: { [weak self] in self?.enterEndless() },
            onMenu: { [weak self] in
                guard let self else { return }
                self.dismissOverlay()
                self.clearSave()
                self.campaign.reset()
                self.runUnlockPops { self.showMenu() }
            })
        setScreen(UIViewController())   // blank felt under the victory screen
        presentOverlay(overlay)
    }

    private func enterEndless() {
        campaign.startEndless()
        persist(phase: "map")
        dismissOverlay()
        showMap()
    }

    private func continueCampaign() {
        dismissOverlay()
        // AMBUSH aftermath: the mystery node completes now.
        if let nid = pendingAmbushNodeId {
            pendingAmbushNodeId = nil
            _ = campaign.markNodeCleared(nid)
            persist(phase: "map")
        }
        showMap()
    }

    // MARK: - Unlock pops

    /// Run TERMINATION: the deck celebration (if armed), then the item pops.
    private func runUnlockPops(_ done: @escaping () -> Void) {
        let deckPop = pendingUnlockCelebration
        pendingUnlockCelebration = nil
        let items = campaign.itemUnlocks.checkNewUnlocks()
        func itemPops() {
            guard !items.isEmpty else { done(); return }
            self.showItemUnlockPops(items, done: done)
        }
        if let deckPop {
            let overlay = PhaseOverlayView.deckUnlock(name: deckPop.name, deckId: deckPop.id) { [weak self] in
                self?.dismissOverlay()
                itemPops()
            }
            presentOverlay(overlay)
        } else {
            itemPops()
        }
    }

    private func showItemUnlockPops(_ items: [ItemUnlocks.Unlocked], done: @escaping () -> Void) {
        var queue = items
        func next() {
            guard !queue.isEmpty else { done(); return }
            // 4+ unlocks collapse into one summary pop (the web's MAX_SOLO_POPS).
            if queue.count > 3 {
                let names = queue.map { PhaseOverlayView.itemLabel($0.id) }.joined(separator: ", ")
                queue.removeAll()
                let overlay = PhaseOverlayView.itemUnlock(title: "NEW ITEMS UNLOCKED",
                                                          body: names) { [weak self] in
                    self?.dismissOverlay()
                    next()
                }
                presentOverlay(overlay)
                return
            }
            let u = queue.removeFirst()
            let overlay = PhaseOverlayView.itemUnlock(
                title: "\(PhaseOverlayView.itemLabel(u.id)) UNLOCKED",
                body: PhaseOverlayView.itemDef(u.id)?.description ?? u.hint) { [weak self] in
                self?.dismissOverlay()
                next()
            }
            presentOverlay(overlay)
        }
        next()
    }

    // MARK: - Overlay plumbing

    private var overlay: UIView?
    func presentOverlay(_ v: UIView) {
        overlay?.removeFromSuperview()
        v.frame = view.bounds
        view.insertSubview(v, belowSubview: crt)
        overlay = v
    }
    func dismissOverlay() {
        overlay?.removeFromSuperview()
        overlay = nil
    }
    func currentOverlayView() -> PhaseOverlayView? { overlay as? PhaseOverlayView }

    // MARK: - Pause menu

    /// The web `#gameMenu` bottom sheet: seed row (tap-to-copy) over Resume /
    /// How to Play (or Restart in Zen) / Sound / New Climb / Quit to Menu.
    func showPauseMenu() {
        let isZenGame = zenDiff != nil
        let sheet = PauseSheetView(seed: isZenGame ? nil : SeedCode.encode(campaign.runSeed),
                                   exhibition: !isZenGame && campaign.isExhibition(),
                                   items: [])
        func makeItems() -> [PauseSheetView.Item] {
            var items: [PauseSheetView.Item] = [
                .init("RESUME", icon: MapArt.menuIcon("sun"), role: .cta) {},
            ]
            if isZenGame {
                items.append(.init("RESTART", icon: MapArt.menuIcon("zen")) { [weak self] in
                    guard let self, let d = self.zenDiff else { return }
                    self.startZen(diff: d)
                })
            } else {
                items.append(.init("HOW TO PLAY", icon: MapArt.menuIcon("search"), keepOpen: true) { [weak self, weak sheet] in
                    sheet?.removeFromSuperview()
                    self?.showManualSheet()
                })
            }
            items.append(.init("SOUND: \(Sound.shared.enabled ? "ON" : "OFF")",
                               icon: MapArt.menuIcon("spark"), keepOpen: true) { [weak sheet] in
                Sound.shared.enabled.toggle()
                sheet?.setItems(makeItems())
            })
            if !isZenGame {
                items.append(.init("NEW CLIMB", icon: MapArt.menuIcon("spark")) { [weak self] in
                    self?.confirmNewClimb()
                })
            }
            items.append(.init("QUIT TO MENU", icon: MapArt.menuIcon("quit"), role: .danger) { [weak self] in
                guard let self else { return }
                if isZenGame {
                    self.zenTeardown()
                } else {
                    // Navigational only — the climb persists; Continue resumes it.
                    self.persist(phase: self.currentPhase)
                }
                self.showMenu()
            })
            return items
        }
        sheet.setItems(makeItems())
        sheet.present(in: view, below: crt)
    }

    /// The paged How-to-Play sheet (web `showManual`) over whatever's showing.
    func showManualSheet() {
        let sheet = ManualSheetView(deckId: campaign.deckId)
        sheet.onReplayTutorial = { [weak self] in
            guard let self else { return }
            self.tutorialReplayArmed = true
            if let first = DifficultyData.zenIds.first {
                self.startZen(diff: first)
            }
        }
        sheet.present(in: view, below: crt)
    }

    private func confirmNewClimb() {
        prompt.show("Abandon this campaign and start a fresh one?",
                    help: "The current climb, coins and items are wiped — this can't be undone.", actions: [
            .init("Cancel", role: .plain) { [weak self] in self?.prompt.hide() },
            .init("New Climb", role: .danger) { [weak self] in
                guard let self else { return }
                self.prompt.hide()
                self.clearSave()
                self.campaign.reset()
                self.showDeckSelect()
            },
        ]) { [weak self] in self?.prompt.hide() }
    }

    func seedShareString() -> String {
        "\(campaign.deckId.uppercased())-\(campaign.difficultyTier.uppercased())-\(SeedCode.encode(campaign.runSeed))"
    }

    // MARK: - Zen

    func startZen(diff: String) {
        zenDiff = diff
        zenCounted = false
        zenFlips = 0
        zenCorrect = 0
        let plan = DealPlanner.zenPlan(diff: GameData.shared.difficulty.zen(diff))
        let vc = DealViewController(mode: .zen(plan, diff: diff), campaign: campaign, runMap: runMap)
        // FIRST-RUN TOUR: the guided first Zen deal teaches the core mechanics.
        // Completing OR skipping stamps the pref; a replay re-arms one-shot.
        if campaign.saveStore.pref("tutorial2") != "1" || tutorialReplayArmed {
            tutorialReplayArmed = false
            tutorialRanThisSession = true
            let tour = TutorialView(steps: GameData.shared.tutorial.steps("deal")) { [weak self] _ in
                self?.campaign.saveStore.setPref("tutorial2", "1")
            }
            vc.view.addSubview(tour)
            tour.frame = vc.view.bounds
            tour.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        }
        vc.onOutcome = { [weak self] o in self?.onZenEnd(o) }
        vc.onZenGuess = { [weak self] correct in
            guard let self, let d = self.zenDiff else { return }
            if !self.zenCounted {
                self.zenCounted = true
                var e = self.campaign.zenStats.get(d)
                e.games += 1
                self.campaign.zenStats.put(d, e)
            }
            var e = self.campaign.zenStats.get(d)
            e.cardsFlipped += 1
            if correct { e.correctGuesses += 1 }
            self.campaign.zenStats.put(d, e)
            self.zenFlips += 1
            if correct { self.zenCorrect += 1 }
        }
        vc.onMenu = { [weak self] in self?.showPauseMenu() }
        setScreen(vc)
    }

    private func onZenEnd(_ o: DealOutcome) {
        guard let d = zenDiff else { return }
        var e = campaign.zenStats.get(d)
        if o.won {
            e.wins += 1
            e.winPiles[o.aliveCount, default: 0] += 1
            _ = campaign.zenUnlocks.recordWin(d)
        }
        campaign.zenStats.put(d, e)
        // The one passive zenEnd bubble, the first time only: names the unlock.
        if tutorialRanThisSession {
            tutorialRanThisSession = false
            _ = campaignUnlocked()   // stamps the pref once both halves are done
        }
        let overlay = PhaseOverlayView.zenEnd(won: o.won, flips: zenFlips, correct: zenCorrect,
                                              onAgain: { [weak self] in
            guard let self, let d = self.zenDiff else { return }
            self.dismissOverlay()
            self.startZen(diff: d)
        }, onMenu: { [weak self] in
            guard let self else { return }
            self.dismissOverlay()
            self.zenTeardown()
            // First Zen session done → the campaign may have just appeared.
            self.showMenu()
        })
        presentOverlay(overlay)
        crt.flicker()
    }

    private func zenTeardown() {
        zenDiff = nil
    }
}

// MARK: - Map delegate

extension GameFlowController: MapScreenDelegate {
    public func mapArrived(at node: MapNode, on map: MapViewController) {
        let hidden = campaign.nodeHidden(node.id)   // already revealed by travel; type check instead
        _ = hidden
        if node.type == "mystery" {
            runMysteryEvent(node: node, on: map)
            return
        }
        switch node.type {
        case "card", "pickup":
            let card = campaign.resolvePickup(node)
            persist(phase: "map")
            map.collectCards(card.map { [$0] } ?? []) { map.render() }
        case "pack":
            let cards = campaign.resolvePack(node)
            persist(phase: "map")
            let vc = PackRevealViewController(campaign: campaign, title: "Pack",
                                              content: .cards(cards), mode: .show) { [weak self, weak map] _ in
                guard let map else { return }
                map.collectCards(cards) { map.render() }
                self?.persist(phase: "map")
            }
            present(vc, animated: false)
        case "store":
            // ARRIVAL always rolls fresh (keyed to THIS node); only a resume
            // or the standing re-entry keeps the saved offer.
            autopilot?.noteStore()
            showStore(fresh: true, nodeId: node.id)
        case "deal", "boss":
            currentAmbush = nil
            autopilot?.noteDeal()
            startDeal()
        case "home":
            showPinkyHome()
        default:
            _ = campaign.markNodeCleared(node.id)
            persist(phase: "map")
            map.render()
        }
    }

    public func mapWantsMenu(_ map: MapViewController) {
        showPauseMenu()
    }

    /// Standing on a store node: the bottom-left STORE button re-opens the
    /// SAME visit (fresh=false — a re-entry can never hand out a free reroll).
    public func mapWantsStoreReturn(_ map: MapViewController) {
        guard let node = campaign.currentNode(), node.type == "store" else { return }
        showStore(fresh: false, nodeId: node.id)
    }

    public func mapWantsDeckInspect(_ map: MapViewController) {
        present(DeckInspectViewController(campaign: campaign), animated: false)
    }

    // MARK: Mystery events (rolled + applied here; Chunk E adds the full modal)

    private func runMysteryEvent(node: MapNode, on map: MapViewController) {
        let key = campaign.rollMysteryEvent(node.id)
        autopilot?.noteMystery(key)
        guard let outcome = campaign.applyMysteryEvent(key, nodeId: node.id) else {
            _ = campaign.markNodeCleared(node.id)
            persist(phase: "map")
            map.render()
            return
        }
        persist(phase: "map")
        let overlay = PhaseOverlayView.mystery(outcome: outcome) { [weak self, weak map] in
            guard let self else { return }
            self.dismissOverlay()
            self.continueMystery(outcome, node: node, map: map)
        }
        presentOverlay(overlay)
    }

    private func completeMystery(_ nodeId: Int) {
        _ = campaign.markNodeCleared(nodeId)
        persist(phase: "map")
        if let map = current as? MapViewController { map.render() }
        else { showMap() }
    }

    private func continueMystery(_ o: MysteryOutcome, node: MapNode, map: MapViewController?) {
        switch o.key {
        case "cards", "joker":
            if let map { map.collectCards(o.cards) { [weak self] in self?.completeMystery(node.id) } }
            else { completeMystery(node.id) }
        case "stickerPack":
            if let sid = o.stickerId {
                let picker = CardPickerViewController(campaign: campaign,
                                                      mode: .applySticker(typeId: sid)) { [weak self] _ in
                    self?.completeMystery(node.id)
                }
                present(picker, animated: false)
            } else { completeMystery(node.id) }
        case "freeRemoval":
            let picker = CardPickerViewController(campaign: campaign, mode: .removal(price: 0)) { [weak self] _ in
                self?.completeMystery(node.id)
            }
            picker.forced = false
            present(picker, animated: false)
        case "stickerStrip":
            let hasStickered = campaign.getRunDeck().contains { !$0.stickers.isEmpty }
            if hasStickered {
                let picker = CardPickerViewController(campaign: campaign, mode: .strip) { [weak self] _ in
                    self?.completeMystery(node.id)
                }
                present(picker, animated: false)
            } else { completeMystery(node.id) }
        case "store":
            // The store opens on the spot; the mystery completes on Done.
            mysteryStoreContinue = { [weak self] in self?.completeMystery(node.id) }
            showStore(fresh: true, nodeId: node.id)
        case "ambush":
            currentAmbush = DealPlanner.AmbushSpec(cards: o.ambushCards ?? 15,
                                                   piles: o.ambushPiles ?? 4,
                                                   bounty: o.ambushBounty ?? 0,
                                                   nodeId: node.id)
            startDeal()
        default:
            completeMystery(node.id)
        }
    }
}

// MARK: - Store delegate + checkpointing

extension GameFlowController: StoreScreenDelegate, CampaignCheckpointing {
    public func storeDone(_ storeVC: StoreViewController) {
        // A map store node clears once visited; a mystery detour completes.
        if let cont = mysteryStoreContinue {
            mysteryStoreContinue = nil
            cont()
            showMap()
            return
        }
        if let node = campaign.currentNode(), node.type == "store" {
            _ = campaign.markNodeCleared(node.id)
        }
        persist(phase: "map")
        showMap()
    }

    public func checkpoint(_ campaign: CampaignState) {
        persist(phase: currentPhase)
    }
}
