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
    /// Game Center: the GameKit half + the testable policy half. The game
    /// never gates on either — see GameCenterService's header.
    let gameCenter = GameCenterService()
    lazy var leaderboards = Leaderboards(store: store, submitter: gameCenter)
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
    /// Cards the Zen deck holds AFTER the initial deal (fullDeckCount − piles)
    /// — the loss screen's "cards left in deck" derives from it.
    private var zenDeckPlayable = 0
    var tutorialReplayArmed = false
    private var tutorialRanThisSession = false

    private var current: UIViewController?
    private let tissue = TissueView()
    private let crt = CRTOverlayUIView()
    let prompt = PromptBar()
    private var autopilot: FlowAutopilot?

    /// The debug panel entry point on EVERY screen while debug access is on
    /// (the menu's own DEBUG row only exists on the menu). Bottom-right —
    /// clear of the map's bottom-left store chip and the deal's rail.
    /// THE OLD JOKER's modal while it is on screen.
    private var oldJokerView: OldJokerView?

    private lazy var debugFloatButton: PixelButtonView = {
        let b = PixelButtonView("🐞", role: .charged, fontSize: 16)
        b.onTap = { [weak self] in self?.showDebugPanel() }
        return b
    }()

    /// Debug-autopilot transport (v5.81): while the odds guesser is on, a
    /// pause + speed pair rides the bottom-LEFT (the debug float owns the
    /// right). Pause holds the guess timer; speed cycles 1×→2×→4×.
    private var debugPilotPaused = false
    private var debugPilotSpeed = 1
    private lazy var pilotPauseButton: PixelButtonView = {
        let b = PixelButtonView("❚❚", role: .plain, fontSize: 14)
        b.onTap = { [weak self] in self?.togglePilotPause() }
        return b
    }()
    private lazy var pilotSpeedButton: PixelButtonView = {
        let b = PixelButtonView("1×", role: .plain, fontSize: 14)
        b.onTap = { [weak self] in self?.cyclePilotSpeed() }
        return b
    }()

    public init() {
        self.campaign = CampaignState(store: store)
        self.runMap = RunMap(data: GameData.shared)
        super.init(nibName: nil, bundle: nil)
        PersistenceHolder.shared = self
        campaign.itemUnlocks.primeKnown()   // first-session unlocks must not be swallowed
        gameCenter.onAuthenticated = { [weak self] in self?.leaderboards.flush() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    public override var prefersStatusBarHidden: Bool { true }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = CRT.feltDeep
        tissue.frame = view.bounds
        tissue.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(tissue)          // the #tissue atmosphere, bottommost
        crt.isUserInteractionEnabled = false
        view.addSubview(crt)
        view.addSubview(prompt)
        debugFloatButton.isHidden = !debugAccess
        view.addSubview(debugFloatButton)   // topmost; rides over every screen
        pilotPauseButton.isHidden = true
        pilotSpeedButton.isHidden = true
        view.addSubview(pilotPauseButton)
        view.addSubview(pilotSpeedButton)
        boot()
        // Game Center: silent launch authentication (GameKit may present ONE
        // system sign-in sheet; declining is remembered — we never re-ask).
        gameCenter.authenticate(presenting: self)
        // A debug autopilot left on last session re-arms at boot.
        if debugAutopilotOn() { setDebugAutopilot(true) }
        // Screenshot harness: `-typeRamp 1` overlays the type-scale specimen
        // (the styleguide §3b readability ramp) for the floor-picking test.
        if UserDefaults.standard.bool(forKey: "typeRamp") {
            showTypeRamp()
        }
        // Screenshot harness: `-curseSheet 1` overlays every cursed sticker's
        // chip art + label + help text (per-curse art evidence).
        if UserDefaults.standard.bool(forKey: "curseSheet") {
            showCurseSheet()
        }
        // Screenshot harness: `-showJoker <offerKey>` forces one of THE OLD
        // JOKER's offers with sample state, for per-event evidence stills.
        if let which = UserDefaults.standard.string(forKey: "showJoker") {
            showDebugJoker(which)
        }
        // Screenshot harness: `-showOverlay cleared|dead|victory|mystery|unlock`
        // renders that overlay with sample data (debug evidence stills only).
        if let which = UserDefaults.standard.string(forKey: "showOverlay") {
            showDebugOverlay(which)
        }
    }

    /// Force one Old Joker offer on screen with plausible sample state.
    private func showDebugJoker(_ key: String) {
        let data = GameData.shared
        // Give him something to point at.
        for (i, p) in data.items.pillars.prefix(CampaignLayout.columnSlots).enumerated() {
            campaign.setColumnPillar(col: i, typeId: p.id)
        }
        for (i, b) in data.items.bases.prefix(CampaignLayout.columnSlots).enumerated() {
            campaign.setColumnBase(col: i, typeId: b.id)
        }
        campaign.addCoins(60)
        campaign.setSameCharge(false)
        if let opening = campaign.legalNextNodes().first { campaign.moveToNode(opening.id) }
        let holdings = campaign.equippedHoldings()
        let commons = holdings.filter { campaign.holdingDef($0)?.tier == "common" }
        let pillars = data.items.pillars
        let offer: OldJoker.Offer?
        switch key {
        case "buyout":
            offer = holdings.count >= 2 ? .buyout(cheap: holdings[0], cheapCoins: 3,
                                                  rich: holdings[1], richCoins: 14) : nil
        case "swap":
            offer = holdings.first.map { .swap(taken: $0, given: pillars.last?.id ?? $0.id) }
        case "purge":
            // Debug forced offer: a fixed roll so the picker is exercisable —
            // one mild, one medium, one mild (the shared pool's own ids).
            offer = .purge(removeCount: 3, curses: ["leech", "jammer", "shrink"])
        case "ride":
            let fare = GameData.shared.items.oldJoker.int("ride", "cost", 5)
            offer = campaign.nextStoreBeforeBoss()
                .map { .ride(storeNodeId: $0.id, skipped: $0.skipped, cost: fare) }
                ?? .ride(storeNodeId: 0, skipped: 2, cost: fare)
        case "cut":    offer = .cut(chooseCost: 4)
        case "marker": offer = .marker(coins: 16, repay: 24)
        case "blindSwap":
            offer = (commons.first ?? holdings.first).map {
                .blindSwap(from: $0, to: pillars.first(where: { $0.tier == "rare" })?.id ?? "greedy")
            }
        case "twoDoors": offer = .twoDoors(goodKey: "coinBonus", badKey: "coinLoss", goodIsLeft: true)
        case "insurance": offer = .insurance(cost: 2)
        case "refund":
            let two = Array(holdings.prefix(2))
            offer = two.isEmpty ? nil
                : .refund(options: two,
                          values: two.map { Int(((campaign.holdingDef($0)?.price ?? 1) * 2.5).rounded()) })
        case "collect":
            campaign.setJokerDebt(24)
            offer = .collect(owed: 24)
        // UNLOCK-era offers. Sample state above already equips a Pillar and a
        // Base in every slot and hands over 60 coins, so each of these has
        // something real to point at.
        case "freeShop":
            let slotted = holdings.filter { $0.kind != .sticker }
            offer = slotted.first.map {
                .freeShop(taken: $0, currentPrice: Int(campaign.holdingDef($0)?.price ?? 1))
            }
        case "purgeReset":
            offer = .purgeReset(from: 9, to: 5, cost: 0)
        case "eights":
            offer = .eights(from: campaign.eightsFromRanks(), to: 8,
                            affected: max(1, campaign.eightsAffectedCount()))
        case "thirsty":
            offer = .thirsty(purse: campaign.getCoins())
        case "thirstReturn":
            offer = .thirstReturn(paid: 3, reward: 6)
        case "thirstAmbush":
            offer = .thirstReturn(paid: 0, reward: 0)
        case "duplicate":
            offer = .duplicate(sticker: GameData.shared.items.oldJoker
                                 .string("duplicate", "sticker", "leech"))
        default: offer = nil
        }
        guard let offer else { return }
        presentOldJoker(offer, nodeId: campaign.nodePos ?? 1, map: nil)
    }

    private func showDebugOverlay(_ which: String) {
        switch which {
        case "cleared":
            let info = SummaryInfo(earned: 9, balance: 21,
                                   lines: [RewardLine(label: "Deal reward", amount: 7, source: .flat),
                                           RewardLine(label: "Envy (col 2)", amount: 2, source: .pillar)],
                                   product: 12, aliveCount: 4, minAlive: 3,
                                   progress: "♦ phase 1/3 · Deck 13", totalScore: 47)
            presentOverlay(PhaseOverlayView.dealCleared(info: info) { [weak self] in self?.dismissOverlay() })
        case "dead":
            let info = FailedInfo(correct: 11, wrong: 1, cardsFlipped: 12, coinsEarned: 6, wasEndless: false)
            presentOverlay(PhaseOverlayView.gameOver(
                info: info, seed: "PINKY-REGULAR-ABC2345",
                nearest: campaign.itemUnlocks.nearestLocked(2)) { [weak self] in self?.dismissOverlay() })
        case "victory":
            presentOverlay(PhaseOverlayView.pinkyHome(
                deckName: "Pinky", score: 44, coins: 31, cards: 19, bestScore: 51,
                onEndless: { [weak self] in self?.dismissOverlay() },
                onMenu: { [weak self] in self?.dismissOverlay() }))
        case let s where s.hasPrefix("mystery"):
            // "-showOverlay mystery[:key]" — any outcome's reveal with enough
            // sample state to actually apply ("mysteryBad" = mystery:coinLoss).
            let key = s.contains(":") ? String(s.split(separator: ":").last!)
                : (s == "mysteryBad" ? "coinLoss" : "coinBonus")
            campaign.addCoins(12)
            if key == "stickerTheft", let id = campaign.getRunDeck().first?.id {
                _ = campaign.applyStickerDirect(id, "rankUp")
                _ = campaign.applyStickerDirect(id, "extraCoin")
            }
            if key == "itemTheft" {
                campaign.setColumnPillar(col: 0, typeId: GameData.shared.items.pillars[0].id)
            }
            if let o = campaign.applyMysteryEvent(key, nodeId: 7) {
                presentOverlay(PhaseOverlayView.mystery(outcome: o,
                                                        presenter: MysteryCast.presenter(for: o),
                                                        deckId: campaign.deckId) { [weak self] in self?.dismissOverlay() })
            }
        case "unlock":
            // The item-unlock pop, using the LONGEST-described gated item —
            // the case that used to clip its description.
            let gated = (GameData.shared.items.stickers + GameData.shared.items.pillars
                         + GameData.shared.items.bases)
                .filter { $0.unlock != nil }
                .max { $0.description.count < $1.description.count }
            if let def = gated {
                presentOverlay(PhaseOverlayView.itemUnlock(
                    title: "Unlocked", body: def.description, itemId: def.id,
                    hint: campaign.itemUnlocks.hint(for: def)) { [weak self] in self?.dismissOverlay() })
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
        let inset = max(view.safeAreaInsets.bottom, 12)
        debugFloatButton.frame = CGRect(x: view.bounds.width - 54,
                                        y: view.bounds.height - inset - 44,
                                        width: 44, height: 36)
        // The autopilot transport mirrors the float on the bottom-left.
        pilotPauseButton.frame = CGRect(x: 10, y: view.bounds.height - inset - 44,
                                        width: 52, height: 36)
        pilotSpeedButton.frame = CGRect(x: 70, y: view.bounds.height - inset - 44,
                                        width: 52, height: 36)
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
        // Boot always lands on the MAIN MENU — an in-progress climb is
        // offered as the menu's CONTINUE button, never auto-resumed into
        // (the web boots to the menu the same way).
        if UserDefaults.standard.bool(forKey: "autoClimb") {
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
        // No climb in progress → no save (defense-in-depth: a save must only
        // ever exist while a climb is active, or the menu offers a phantom
        // CONTINUE). Zen checkpoints are already detached at the source.
        guard campaign.runMap != nil else { return }
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
        clearMidDeal()
    }

    // MARK: - Mid-deal persistence (anti-savescum)

    /// The mid-deal snapshot's own key — deliberately SEPARATE from the
    /// campaign blob: the per-action write stays a few KB of engine state
    /// instead of re-serializing the whole campaign every tap.
    static let midDealKey = "ninelives.midDeal.v1"
    /// STKPERF1: synchronous per-tap storage writes caused the sticker lag,
    /// so the mid-deal save NEVER touches storage on the main thread. The
    /// capture is a cheap value copy handed here; this serial queue does the
    /// JSON encode + write, and `midDealPending` is latest-wins — a burst of
    /// fast actions collapses to however many writes the queue can retire,
    /// each one a complete consistent snapshot.
    private let midDealQueue = DispatchQueue(label: "ninelives.middeal", qos: .utility)
    private let midDealLock = NSLock()
    private var midDealPending: [String: JSONValue]?
    private var midDealDraining = false

    func saveMidDeal(_ blob: [String: JSONValue]) {
        midDealLock.lock()
        midDealPending = blob
        let startDrain = !midDealDraining
        if startDrain { midDealDraining = true }
        midDealLock.unlock()
        guard startDrain else { return }
        midDealQueue.async { [weak self] in
            guard let self else { return }
            while true {
                self.midDealLock.lock()
                guard let next = self.midDealPending else {
                    self.midDealDraining = false
                    self.midDealLock.unlock()
                    return
                }
                self.midDealPending = nil
                self.midDealLock.unlock()
                // UserDefaults hands the value to cfprefsd on set — a crash
                // right after this line loses nothing.
                JSONStore.write(self.store, Self.midDealKey, next)
            }
        }
    }

    func loadMidDeal() -> [String: JSONValue]? {
        JSONStore.read(store, Self.midDealKey)
    }

    /// Drop the blob THROUGH the writer queue, so a clear can never lose the
    /// race against an in-flight write and resurrect a finished deal.
    func clearMidDeal() {
        midDealLock.lock()
        midDealPending = nil
        midDealLock.unlock()
        midDealQueue.async { [weak self] in
            self?.store.remove(forKey: Self.midDealKey)
        }
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
            startDeal(resumeSeed: seed, resumeSubsetIds: subsetIds, resumePiles: subsetPiles,
                      midDeal: loadMidDeal())
        case "store":
            showStore(fresh: false)
        default:
            showMap()
        }
    }

    // MARK: - Menu

    /// The title sequence plays for the FIRST menu of a launch only — coming
    /// back from a climb should not replay it.
    private var titleSequencePlayed = false

    func showMenu() {
        currentPhase = "menu"
        let menu = MainMenuViewController(flow: self, canContinue: campaign.saveStore.hasSave)
        menu.playsIntro = !titleSequencePlayed
        titleSequencePlayed = true
        setScreen(menu)
        // THE ONE-TIME NUDGE (router batch 2): the tutorial is done, the
        // player is back on the menu — point them at the Climb, exactly once.
        if campaign.saveStore.pref("tutorial2") == "1",
           campaign.saveStore.pref("tutorialNudgeShown") != "1",
           campaign.stats.get().gamesPlayed == 0,   // veterans skip it
           !UserDefaults.standard.bool(forKey: "skipGate") {
            campaign.saveStore.setPref("tutorialNudgeShown", "1")
            presentOverlay(PhaseOverlayView.itemUnlock(
                title: "You're ready",
                body: "Now that you understand how to play, try a Climb.") { [weak self] in
                self?.dismissOverlay()
            })
        }
    }

    /// CONTINUE CLIMB from the menu: restore + route by the saved phase.
    func resumeFromMenu() {
        // A fresh CampaignState guarantees no menu-session state bleeds in.
        campaign = CampaignState(store: store)
        campaign.itemUnlocks.primeKnown()
        runMap = RunMap(data: GameData.shared)
        resumeSavedGame()
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
        // Game Center: the entry point ALWAYS shows (Apple's sheet handles
        // its own signed-out state); the rank line only when a read succeeds.
        let boardID = LeaderboardID.identifier(deck: "pink", tier: "legendary")!
        sheet.onLeaderboards = { [weak self] in
            guard let self else { return }
            self.gameCenter.presentLeaderboard(boardID, from: self)
        }
        gameCenter.loadLocalEntry(leaderboardID: boardID) { [weak sheet] entry in
            if let entry { sheet?.gcLocalEntry = entry }
        }
        sheet.onReset = { [weak self, weak sheet] in
            guard let self else { return }
            // The confirm bar must clear the sheet it was summoned from.
            self.view.insertSubview(self.prompt, belowSubview: self.crt)
            self.prompt.show("Reset lifetime stats?", help: "Unlock progress derives from stats.", actions: [
                .init("Cancel", role: .plain) { [weak self] in self?.prompt.hide() },
                .init("Reset", role: .danger) { [weak self] in
                    self?.prompt.hide()
                    // Web index.html:32342-32345: the reset wipes ZenStats too
                    // (ZenUnlocks stays — a stats reset never re-locks).
                    self?.campaign.stats.reset()
                    self?.campaign.zenStats.reset()
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
    /// NOTE: reset() ends in its own (discarded) startNewRun(), and the seed
    /// override is one-shot — so the override must be (re)set AFTER reset(),
    /// or the real run rolls a random non-exhibition seed instead.
    func startCampaign(deckId: String, tier: String, seedU32: UInt32?) {
        clearSave()
        campaign.setDeck(deckId)
        campaign.setTier(tier)
        campaign.reset()
        campaign.setDeck(deckId)
        campaign.setTier(tier)
        campaign.setSeedOverride(seedU32)
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
        // A STAGED GIFT SHELF outranks the map. It is persisted state, so it
        // survived a relaunch and appeared on Continue — but on the turn it
        // was staged, something navigated here instead and the player reached
        // the map with items they were never shown. Whatever routed us here,
        // the coat is still owed: open it.
        if campaign.isGiftShelf, campaign.getStoreOffer()?.slots.isEmpty == false {
            let nodeId = campaign.nodePos
            // …and it gets an exit, since the line above just cleared the one
            // the original hand-over installed.
            mysteryStoreContinue = { [weak self] in
                guard let self else { return }
                self.campaign.discardStoreOffer()
                self.campaign.endFreeShop()
                if let nodeId { _ = self.campaign.markNodeCleared(nodeId) }
                self.persist(phase: "map")
            }
            showStore(fresh: false, nodeId: nodeId)
            return
        }
        defer { resumeUnresolvedMystery() }
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
        // A shop someone has TAMPERED WITH announces its tamperer first: the
        // character who twisted the prices restates the twist at the door,
        // then the shelf opens. Fresh visits only — a re-entry skips it.
        if fresh, let (presenter, outcome) = storeTwistAnnouncement() {
            presentOverlay(PhaseOverlayView.mystery(outcome: outcome,
                                                    presenter: presenter,
                                                    deckId: campaign.deckId) { [weak self] in
                self?.dismissOverlay()
                self?.reallyShowStore(fresh: fresh, nodeId: nodeId)
            })
            Sound.shared.mysteryStore()
            return
        }
        reallyShowStore(fresh: fresh, nodeId: nodeId)
    }

    private func reallyShowStore(fresh: Bool, nodeId: Int?) {
        currentPhase = "store"
        if fresh { campaign.discardStoreOffer() }
        let sv = StoreViewController(campaign: campaign)
        sv.offerNodeId = nodeId
        sv.delegate = self
        setScreen(sv)
        persist(phase: "store")
    }

    /// The doorway announcement for a twisted shop, if one is owed. Keys
    /// reuse the mystery family so the rim tint follows good/bad for free.
    private func storeTwistAnnouncement() -> (MysteryCast.Presenter, MysteryOutcome)? {
        if campaign.freeShopPending {
            return (MysteryCast.Presenter(name: OldJokerCopy.name,
                                          art: ItemArt.oldJoker(scale: 4),
                                          line: "Told you. Tonight the shelf forgets how to charge."),
                    MysteryOutcome(key: "store", title: "On the House",
                                   desc: "Everything here costs nothing"))
        }
        switch campaign.storePriceModPending {
        case "double":
            return (MysteryCast.Presenter(name: "Just a Two",
                                          art: ItemArt.justATwo(scale: 4),
                                          line: "Remember me? I had a word with the shop. Enjoy the prices."),
                    MysteryOutcome(key: "priceDouble", title: "Markup",
                                   desc: "Every item here costs DOUBLE"))
        case "one":
            return (MysteryCast.Presenter(name: "The Beheaded Queen",
                                          art: ItemArt.beheadedQueen(scale: 4),
                                          line: "I told the shopkeep you'd come. Everything is a coin."),
                    MysteryOutcome(key: "priceOne", title: "Fire Sale",
                                   desc: "Every item here costs 1 coin"))
        default:
            return nil
        }
    }

    // MARK: - Deals

    func startDeal(resumeSeed: UInt32? = nil, resumeSubsetIds: [Int]? = nil, resumePiles: Int? = nil,
                   midDeal: [String: JSONValue]? = nil) {
        if resumeSeed == nil {
            // A FRESH deal invalidates any older mid-deal snapshot — a killed
            // deal must resume, never be re-entered as new with a stale blob
            // waiting to bite the node after it.
            clearMidDeal()
            reshuffleIndex = 0
            // The Queen's Mulligan: the deal that claims it opens with a free
            // first RESHUFFLE (the ladder resumes at base once it's spent).
            redealCost = campaign.consumeFreeRedeal() ? 0 : DealPlanner.redealBaseCost
        }
        let plan = DealPlanner.plan(campaign: campaign, runMap: runMap,
                                    reshuffleIndex: reshuffleIndex, redealCost: redealCost,
                                    ambush: currentAmbush,
                                    resumeSeed: resumeSeed, resumeSubsetIds: resumeSubsetIds,
                                    resumePiles: resumePiles)
        currentPhase = "run"
        let vc = DealViewController(mode: .campaign(plan), campaign: campaign, runMap: runMap)
        vc.resumeMidDeal = midDeal
        vc.onMidDealSnapshot = { [weak self] blob in self?.saveMidDeal(blob) }
        vc.onOutcome = { [weak self] outcome in self?.onRunEnd(outcome) }
        vc.onMenu = { [weak self] in self?.showPauseMenu() }
        setScreen(vc)
        persist(phase: "run")
    }

    /// The web's onRunEnd — every fold, ported.
    /// Fold this climb's score into the lifetime bests — the global one and the
    /// per-character/tier one behind the deck-select carousel's BEST line.
    /// Called on BOTH endings: a score you reached counts whether or not you
    /// went on to beat the ♠ boss. Callers gate on `!isExhibition()`.
    ///
    /// Records are DECK+TIER scoped (router batch 2): a Straight climb must
    /// never show a Jokers best. The global fields stay updated for the
    /// unlock gates; every display reads the per-combo entries.
    private func foldBestScore(into s: inout StatsRecord) {
        // ONE SCORE (v6.47): the run's continuous total — endless keeps
        // accruing into the same number, so there is exactly one best.
        let score = campaign.getRunScore()
        s.bestCampaignScore = max(s.bestCampaignScore, score)
        let dtKey = "\(campaign.deckId).\(campaign.difficultyTier)"
        s.deckTierBest[dtKey] = max(s.deckTierBest[dtKey] ?? 0, score)
    }

    private func onRunEnd(_ o: DealOutcome) {
        // The deal is OVER — its mid-deal snapshot must never resume it again.
        clearMidDeal()
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
            // UNLOCK2 — the suits actually LANDED this deal, so suit-gated
            // items follow how the player really plays.
            s.heartsPlayed += o.suitsLanded["♥"] ?? 0
            s.diamondsPlayed += o.suitsLanded["♦"] ?? 0
            s.clubsPlayed += o.suitsLanded["♣"] ?? 0
            s.spadesPlayed += o.suitsLanded["♠"] ?? 0
            // A cleared deal with no wrong guess at all. Ambushes count —
            // they are the hardest place to manage it.
            if o.won, o.totalGuesses > 0, o.correctGuesses == o.totalGuesses {
                s.perfectDeals += 1
            }
            // …and which difficulty it was cleared on.
            if o.won {
                switch campaign.difficultyTier {
                case "legendary": s.dealsWonLegendary += 1
                default:          s.dealsWonRegular += 1
                }
            }
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
                    s.bestEndless = max(s.bestEndless, campaign.endlessStagesReached())
                } else {
                    s.lifetimeCardsFlipped += campaign.totalCardsFlipped
                    s.furthestStage = max(s.furthestStage, campaign.phaseIndex + 1)
                    // Still on stage 1 when the climb died: the stage-1 boss
                    // was never beaten (beating it advances the phase).
                    if campaign.phaseIndex == 0 { s.earlyLosses += 1 }
                }
                // A climb you DIED on still set a score — bank the best of it
                // (v5.82). Previously only a full ♠-boss win folded these, so a
                // deep-but-fatal Pinky climb recorded nothing. Post-boss the
                // campaign half is already banked, so this is a no-op max.
                foldBestScore(into: &s)
                campaign.stats.put(s)
            }
            // Leaderboards: a death ends the run — submit the final
            // continuous total. A banked run already sent its running total
            // at the boss; this send can only raise it (GC keeps the best).
            leaderboards.reportRunEnd(deck: campaign.deckId, tier: campaign.difficultyTier,
                                      exhibition: exhibition,
                                      score: campaign.getRunScore())
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
            if wasAmbush { st.ambushesWon += 1 }
            st.lifetimeDopamine += Int(payout.total)
            // The best single CLIMB's earnings — a high-water mark like the
            // score bests, so spending it doesn't undo the record.
            st.bestCoinsInClimb = max(st.bestCoinsInClimb, campaign.coinsEarnedThisClimb())
            st.bestRunDopamine = max(st.bestRunDopamine, Int(payout.total))
            // Every cleared deal advances the run's one continuous score —
            // fold it live so an endless run killed mid-map keeps its record.
            foldBestScore(into: &st)
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
            // Submit the RUNNING total at the bank: if endless never
            // concludes, this send protects the record; the death send can
            // only raise it (Game Center keeps the best).
            leaderboards.reportRunEnd(deck: campaign.deckId, tier: campaign.difficultyTier,
                                      exhibition: exhibition,
                                      score: campaign.getRunScore())
            campaign.markRunWon()
            var st = campaign.stats.get()
            st.campaignsWon += 1
            st.lifetimeCardsFlipped += campaign.totalCardsFlipped
            st.bestCampaignDopamine = max(st.bestCampaignDopamine, campaign.totalCoinsEarned)
            foldBestScore(into: &st)
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
            // (The retired Master rung is no longer granted — the chain is
            // Normal → Legendary.)
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
        var staticLines: [RewardLine] = []
        for c in 0..<campaign.columnPillars.count {
            guard let id = campaign.columnPillars[c],
                  let t = GameData.shared.pillarTypes.get(id) else { continue }
            let chance = t.num("selfDestruct", 0)
            guard chance > 0 else { continue }
            let destroyed = campaign.actionRng().next() < chance
            if destroyed {
                campaign.setColumnPillar(col: c, typeId: nil)
                _ = campaign.discardPillarFromInventory(id)
                staticLines.append(RewardLine(label: "⚡ \(t.label) blew up", amount: 0, source: .pillar))
            } else {
                staticLines.append(RewardLine(label: "⚡ \(t.label) held", amount: 0, source: .pillar))
            }
        }

        persist(phase: wasAmbush ? "run" : "map")
        let summary = SummaryInfo(earned: Int(payout.total),
                                  balance: campaign.getCoins(),
                                  lines: summaryLines(payout, flat: s.flat) + staticLines,
                                  product: Int(payout.product),
                                  aliveCount: o.aliveCount,
                                  minAlive: o.minAliveCards,
                                  progress: stageRunShort(),
                                  totalScore: campaign.getRunScore())
        // POST-DEAL SPOILS (web showPostDealPlacement, index.html:30574-30599,
        // invoked after every won deal): anything GAINED mid-deal — a
        // Duplicated card waiting in the pack tray, a copied sticker in the
        // hold — is still unplaced. Walk the player through placing it before
        // the summary returns to the map.
        showPostDealWalk { [weak self] in self?.showRunComplete(summary) }
    }

    /// The spoils walk: held tray cards get the store's swap picker, held
    /// stickers the apply picker, back to back, until both drain. A pure
    /// cancel (nothing placed/discarded) ENDS the walk — stragglers wait for
    /// the next store's gate instead of trapping the player in a loop.
    private func showPostDealWalk(_ done: @escaping () -> Void) {
        if campaign.packTrayCount() > 0 {
            let before = campaign.packTrayCount()
            let picker = CardPickerViewController(campaign: campaign,
                                                  mode: .swap(trayIndex: 0, step: nil)) { [weak self] _ in
                guard let self else { return }
                guard self.campaign.packTrayCount() < before else { done(); return }
                self.showPostDealWalk(done)
            }
            picker.showsSkip = true
            present(picker, animated: false)
            return
        }
        // Only walk stickers that can actually be placed — an unplaceable one
        // would open a fully greyed grid (the store gate has always filtered
        // this; the post-deal walk never did).
        if let typeId = campaign.stickerInventory
            .first(where: { $0.value > 0 && campaign.stickerHasTarget($0.key) })?.key {
            let picker = CardPickerViewController(campaign: campaign,
                                                  mode: .applySticker(typeId: typeId)) { [weak self] picked in
                guard let self else { return }
                guard picked != nil else { done(); return }   // cancelled out of the walk
                self.showPostDealWalk(done)
            }
            present(picker, animated: false)
            return
        }
        done()
    }

    private func summaryLines(_ p: PayoutBreakdown, flat: Double) -> [RewardLine] {
        var lines: [RewardLine] = []
        if flat > 0 { lines.append(RewardLine(label: "Deal reward", amount: Int(flat), source: .flat)) }
        // Bonus EVENTS carry a bare item label, so the registry the label came
        // from is what identifies them. ("⚡ …" is a self-destruct static — a
        // Pillar effect.)
        let baseLabels = Set(GameData.shared.baseTypes.all().map(\.label))
        let sameLabels = Set(GameData.shared.samePowerTypes.all().map(\.label))
        let pillarLabels = Set(GameData.shared.pillarTypes.all().map(\.label))
        for l in p.eventLines where l.amount != 0 {
            let src: RewardSource
            if l.label.hasPrefix("⚡") || pillarLabels.contains(l.label) { src = .pillar }
            else if baseLabels.contains(l.label) { src = .base }
            else if sameLabels.contains(l.label) { src = .same }
            else { src = .sticker }
            lines.append(RewardLine(label: l.label, amount: Int(l.amount), source: src))
        }
        // Pillar payouts are Pillars BY CONSTRUCTION — never re-derived from the
        // printed label, which carries a column suffix.
        for l in p.pillarLines where l.amount != 0 {
            lines.append(RewardLine(label: l.col.map { "\(l.label) (col \($0 + 1))" } ?? l.label,
                                    amount: Int(l.amount), source: .pillar))
        }
        if p.extraCoinBonus > 0 {
            lines.append(RewardLine(label: "Extra Coin", amount: Int(p.extraCoinBonus), source: .sticker))
        }
        return lines
    }

    private func stageRunShort() -> String {
        let pi = campaign.phaseIndex
        let total = campaign.phasesTotal()
        if pi >= total { return "ENDLESS stage \(pi - total + 1) · Deck \(campaign.deckSize())" }
        return "\(campaign.phaseSuit()) phase \(pi + 1)/\(total) · Deck \(campaign.deckSize())"
    }

    // MARK: - Summary + end screens

    /// Where a reward line came from. Tagged at the point the line is BUILT —
    /// the summary used to re-derive this by matching the printed label against
    /// the registries, which quietly misfiled every Pillar the moment its label
    /// gained a " (col N)" suffix (Envy showed up under Sticker rewards).
    enum RewardSource { case flat, sticker, pillar, base, same }

    struct RewardLine {
        var label: String
        var amount: Int
        var source: RewardSource
    }

    struct SummaryInfo {
        var earned: Int
        var balance: Int
        var lines: [RewardLine]
        var product: Int
        var aliveCount: Int
        var minAlive: Int
        var progress: String
        /// The climb's RUNNING score after this deal — printed under the
        /// deal's own score, the way the purse sits under the coin total.
        var totalScore: Int = 0
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
            // MAIN MENU ends the climb → the TERMINATION checkpoint re-checks
            // item unlocks (web maybeShowUnlockCelebration, index.html:24835-
            // 24843): gates crossed by run-end stat folds land after the
            // deal-end drain. Stamps the known-set; [] → straight through.
            self.runUnlockPops { self.showMenu() }
        }
        presentOverlay(overlay)
        crt.flicker()
    }

    func showPinkyHome() {
        currentPhase = "map"
        let s = campaign.stats.get()
        let overlay = PhaseOverlayView.pinkyHome(
            deckName: Self.decks.first { $0.id == campaign.deckId }?.name ?? "Pinky",
            score: campaign.getRunScore(),
            coins: campaign.totalCoinsEarned,
            cards: campaign.totalCardsFlipped,
            bestScore: s.deckTierBest["\(campaign.deckId).\(campaign.difficultyTier)"] ?? 0,
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
            // "<Prev> made it home" — prev = the ladder deck before the new one
            // (web DECKS.find(requires)); robust even after campaign.reset().
            let prevName = Self.decks.firstIndex(where: { $0.id == deckPop.id })
                .flatMap { $0 > 0 ? Self.decks[$0 - 1].name : nil }
            let overlay = PhaseOverlayView.deckUnlock(name: deckPop.name, deckId: deckPop.id, prevName: prevName) { [weak self] in
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
            // Every unlock gets its OWN celebration screen, chained one by
            // one (v5.82 — the 4+ summary collapse is gone).
            let u = queue.removeFirst()
            // SKIP ALL only appears while there is actually a queue behind
            // this one — on the last pop it would just be a second CONTINUE.
            let skipAll: (() -> Void)? = queue.isEmpty ? nil : { [weak self] in
                queue.removeAll()
                self?.dismissOverlay()
                done()
            }
            let overlay = PhaseOverlayView.itemUnlock(
                title: "\(PhaseOverlayView.itemLabel(u.id)) UNLOCKED",
                body: PhaseOverlayView.itemDef(u.id)?.description ?? u.hint,
                itemId: u.id, hint: u.hint,
                onSkipAll: skipAll) { [weak self] in
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

    // MARK: - Debug panel

    /// Debug access (7 footer taps; the web's `body.debug-access`). Persisted so
    /// a playtester keeps it across relaunches; cleared from the panel.
    private(set) var debugAccess = UserDefaults.standard.bool(forKey: "debugAccess")
    func debugAccessEnabled() -> Bool { debugAccess }
    func setDebugAccess(_ on: Bool) {
        debugAccess = on
        UserDefaults.standard.set(on, forKey: "debugAccess")
        debugFloatButton.isHidden = !on
        if !on { dismissDebugPanel() }
    }

    private var debugTapCount = 0
    private var debugTapStart = Date.distantPast
    /// The web's `wireVersionTapDebug`: 7 footer taps within ~2s toggle debug
    /// access (and open the panel on activation, like the web's setDebug(true)).
    /// Returns true when the toggle FIRED on this tap, so the caller can flash
    /// the footer and rebuild the menu (the DEBUG button appears/disappears).
    @discardableResult
    func noteFooterTap() -> Bool {
        let now = Date()
        if now.timeIntervalSince(debugTapStart) > 2.0 { debugTapCount = 0 }
        if debugTapCount == 0 { debugTapStart = now }
        debugTapCount += 1
        guard debugTapCount >= 7 else { return false }
        debugTapCount = 0
        setDebugAccess(!debugAccess)
        if debugAccess { showDebugPanel() }
        return true
    }

    private var debugPanel: DebugPanelViewController?
    /// The panel rides as a child VC over whatever screen is up (menu, map,
    /// store, deal) — like the sheets, below the CRT layer.
    func showDebugPanel() {
        guard debugAccess, debugPanel == nil else { return }
        let vc = DebugPanelViewController(flow: self)
        addChild(vc)
        vc.view.frame = view.bounds
        vc.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.insertSubview(vc.view, belowSubview: crt)
        vc.didMove(toParent: self)
        debugPanel = vc
    }
    func dismissDebugPanel() {
        guard let vc = debugPanel else { return }
        debugPanel = nil
        vc.willMove(toParent: nil)
        vc.view.removeFromSuperview()
        vc.removeFromParent()
    }

    /// The live deal's controller (nil when no deal is on screen or it's over).
    func debugLiveDeal() -> DealController? {
        guard let dealVC = current as? DealViewController, let c = dealVC.controller, !c.isOver else { return nil }
        return c
    }

    /// Persist after a debug mutation — only while a climb is live (a menu-phase
    /// save blob would be bogus).
    func debugPersist() {
        if campaign.runMap != nil { persist(phase: currentPhase) }
    }

    /// DEBUG: turn a REACHABLE node into a mystery, so an armed Old Joker
    /// offer has somewhere to fire without walking the map hunting for a "?".
    /// Returns false when there is nothing legal to convert (at the boss, or
    /// no map yet).
    @discardableResult
    func debugMakeNextNodeMystery() -> Bool {
        guard let target = campaign.legalNextNodes().first(where: { $0.type != "boss" })
        else { return false }
        guard campaign.debugSetNodeMystery(target.id) else { return false }
        debugPersist()
        if let map = current as? MapViewController { map.render() }
        return true
    }

    /// MAP JUMP: teleport via CampaignState.debugJumpToNode, then re-show the
    /// map at the jumped position. Refused mid-deal (an orphaned deal would
    /// leave a dead "run" checkpoint).
    @discardableResult
    func debugMapJump(to id: Int) -> Bool {
        guard !(current is DealViewController) else { return false }
        guard campaign.debugJumpToNode(id) else { return false }
        dismissDebugPanel()
        showMap()
        return true
    }

    /// RESET ALL PROGRESS from the panel: the shared double-confirm bar, raised
    /// above the panel (the StatsSheetView pattern), then the full wipe.
    func debugConfirmResetAll() {
        view.insertSubview(prompt, belowSubview: crt)   // the bar must clear the panel
        prompt.show("Reset ALL progress?",
                    help: "Campaign, decks, unlocks, stats and the tutorial are wiped. This can't be undone.",
                    actions: [
            .init("Cancel", role: .plain) { [weak self] in self?.prompt.hide() },
            .init("Erase everything", role: .danger) { [weak self] in
                guard let self else { return }
                self.prompt.hide()
                self.dismissDebugPanel()
                self.resetAllProgress()
            },
        ]) { [weak self] in self?.prompt.hide() }
    }

    // MARK: - Debug autopilot + fps

    /// The panel's autopilot: an odds-based guesser ticking against the live
    /// deal (the web's "autopilot (odds-based guesser)" checkbox). Runtime-
    /// settable, unlike the `-autoPlay` launch flag — DealViewController reads
    /// that flag only at scene creation, and its scripted player is a private
    /// verification harness, so the panel drives its own timer instead.
    private var debugPilotTimer: Timer?
    func debugAutopilotOn() -> Bool { UserDefaults.standard.bool(forKey: "debugAutopilot") }
    func setDebugAutopilot(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: "debugAutopilot")
        debugPilotTimer?.invalidate()
        debugPilotTimer = nil
        debugPilotPaused = false
        debugPilotSpeed = 1
        pilotPauseButton.isHidden = !on
        pilotSpeedButton.isHidden = !on
        pilotPauseButton.setTitle("❚❚")
        pilotSpeedButton.setTitle("1×")
        guard on else { return }
        armDebugPilotTimer()
    }

    private func armDebugPilotTimer() {
        debugPilotTimer?.invalidate()
        debugPilotTimer = Timer.scheduledTimer(withTimeInterval: 0.45 / Double(debugPilotSpeed),
                                               repeats: true) { [weak self] _ in
            self?.debugPilotTick()
        }
    }

    private func togglePilotPause() {
        debugPilotPaused.toggle()
        pilotPauseButton.setTitle(debugPilotPaused ? "▶" : "❚❚")
    }

    private func cyclePilotSpeed() {
        debugPilotSpeed = debugPilotSpeed == 1 ? 2 : (debugPilotSpeed == 2 ? 4 : 1)
        pilotSpeedButton.setTitle("\(debugPilotSpeed)×")
        armDebugPilotTimer()
    }
    /// One move per tick, decided by AutoPilotBrain: survival first, then
    /// banking a Same shield, then coins, then score.
    private func debugPilotTick() {
        guard !debugPilotPaused else { return }
        guard let dealVC = current as? DealViewController, let c = dealVC.controller,
              c.canAcceptGuess else { return }
        guard let pick = AutoPilotBrain.choose(c) else { return }
        // A bad deal-out is worth re-rolling before the first card is played.
        if AutoPilotBrain.shouldReshuffle(c, bestRaw: pick.bestRaw, coins: campaign.getCoins()) {
            c.reshuffle()
            return
        }
        c.guess(pick.move.call, pile: pick.move.pile)
    }

    func debugFPSOn() -> Bool { UserDefaults.standard.bool(forKey: "fps") }
    /// Toggle the deal scene's frame readout (the `-fps` launch-flag path).
    /// DealViewController reads the flag only at scene creation; the scene's
    /// update loop reads `showsFrameHUD` per frame, so flip the live scene too.
    /// Its `scene` property is private — reflection rather than widening the
    /// production API for a debug toggle.
    func setDebugFPS(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: "fps")
        guard let dealVC = current as? DealViewController,
              let scene = Mirror(reflecting: dealVC).children
                .first(where: { $0.label == "scene" })?.value as? DealScene else { return }
        scene.showsFrameHUD = on
    }

    // MARK: - Pause menu

    /// The web `#gameMenu` bottom sheet: seed row (tap-to-copy) over Resume /
    /// How to Play (or Restart in Zen) / Sound / New Climb / Quit to Menu.
    func showPauseMenu() {
        let isZenGame = zenDiff != nil
        // The FULL share string (web showGameMenu's copy payload, index.html:
        // 31694-31702) — the death/victory chips already pass seedShareString().
        let sheet = PauseSheetView(seed: isZenGame ? nil : seedShareString(),
                                   exhibition: !isZenGame && campaign.isExhibition(),
                                   items: [])
        func makeItems() -> [PauseSheetView.Item] {
            var items: [PauseSheetView.Item] = [
                .init("RESUME", role: .cta) {},
            ]
            if isZenGame {
                items.append(.init("RESTART") { [weak self] in
                    guard let self, let d = self.zenDiff else { return }
                    self.startZen(diff: d)
                })
            } else {
                items.append(.init("HOW TO PLAY", keepOpen: true) { [weak self, weak sheet] in
                    sheet?.removeFromSuperview()
                    self?.showManualSheet()
                })
            }
            items.append(.init("SOUND: \(Sound.shared.enabled ? "ON" : "OFF")",
                               keepOpen: true) { [weak sheet] in
                Sound.shared.enabled.toggle()
                sheet?.setItems(makeItems())
            })
            if !isZenGame {
                items.append(.init("NEW CLIMB") { [weak self] in
                    self?.confirmNewClimb()
                })
            }
            items.append(.init("QUIT TO MENU", role: .danger) { [weak self] in
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
                    help: "The current climb, coins and items are wiped. This can't be undone.", actions: [
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
        zenDeckPlayable = plan.fullDeckCount - plan.piles
        let vc = DealViewController(mode: .zen(plan, diff: diff), campaign: campaign, runMap: runMap)
        // FIRST-RUN TOUR: the guided first Zen deal teaches the core
        // mechanics INTERACTIVELY — a scripted opening (a 3 on pile 1, an
        // Ace on the deck), event-gated steps, milestone tips between free
        // play. Completing OR skipping stamps the pref; a replay re-arms
        // one-shot; quitting mid-tour leaves it unstamped to re-offer.
        var tourRef: TutorialView? = nil
        if campaign.saveStore.pref("tutorial2") != "1" || tutorialReplayArmed {
            tutorialReplayArmed = false
            tutorialRanThisSession = true
            let tour = TutorialView(steps: GameData.shared.tutorial.steps("deal")) { [weak self] _ in
                self?.campaign.saveStore.setPref("tutorial2", "1")
            }
            vc.tutorialGuided = true
            tour.anchorProvider = { [weak vc] key in vc?.tutorialAnchorRect(key) }
            vc.onTutorialEvent = { [weak tour] e in tour?.handle(e) }
            vc.view.addSubview(tour)
            tour.frame = vc.view.bounds
            tour.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            tourRef = tour
        }
        vc.onOutcome = { [weak self] o in
            // A deal that ends mid-tour takes the tour with it (unstamped).
            tourRef?.abort()
            tourRef = nil
            self?.onZenEnd(o)
        }
        vc.onZenGuess = { [weak self] correct in
            guard let self, let d = self.zenDiff else { return }
            // The tour counts every resolved guess (milestone waits, the
            // wrong-guess lesson, the "pick another pile" gate).
            tourRef?.handle(.guessResolved(correct: correct))
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
        var unlockLabel: String? = nil
        // Draw pile left at the death (loss) — the killing draw already
        // resolved, so this is the true remaining count (web index.html:
        // 31478-31480: payload.deck.remaining()). cardsDrawn excludes the
        // initial deal, so the playable pool is fullDeckCount − piles.
        let cardsLeft = max(0, zenDeckPlayable - o.cardsDrawn)
        if o.won {
            e.wins += 1
            e.winPiles[o.aliveCount, default: 0] += 1
            // THE LADDER'S GRANT: the first win at a difficulty permanently
            // opens the next one (ZenUnlocks — its own store, so a stats reset
            // never re-locks). Only that NEW grant carries the overlay line.
            let firstWin = campaign.zenUnlocks.recordWin(d)
            let ids = DifficultyData.zenIds
            if firstWin, let i = ids.firstIndex(of: d), i + 1 < ids.count {
                unlockLabel = GameData.shared.difficulty.zen(ids[i + 1]).label
            }
        } else {
            // A loss folds cards-left into the lossCards distribution (bucketed
            // by the Stats histogram at render — forward-only).
            e.lossCards[cardsLeft, default: 0] += 1
        }
        campaign.zenStats.put(d, e)
        // The one passive zenEnd bubble, the first time only: names the unlock.
        if tutorialRanThisSession {
            tutorialRanThisSession = false
            _ = campaignUnlocked()   // stamps the pref once both halves are done
        }
        // UNLOCK2: Zen results move the zen* gate stats, so the Zen end is an
        // item-unlock checkpoint too — the pop queue drains BEFORE the overlay
        // (web index.html:31523; [] → no UI, straight through).
        runUnlockPops { [weak self] in
            guard let self else { return }
            let overlay = PhaseOverlayView.zenEnd(won: o.won, flips: self.zenFlips, correct: self.zenCorrect,
                                                  outcomeCount: o.won ? o.aliveCount : cardsLeft,
                                                  unlockLabel: unlockLabel,
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
            self.presentOverlay(overlay)
            self.crt.flicker()
        }
    }

    private func zenTeardown() {
        zenDiff = nil
    }
}

// MARK: - Map delegate

extension GameFlowController: MapScreenDelegate {
    /// RECOVERY: standing ON an unresolved mystery with no flow in progress
    /// means its offer was lost — the modal was dismissed, or a screen swap
    /// took it away — and the node can never be re-entered, so the run was
    /// stuck. Re-running the node's event is safe: every mystery, THE OLD
    /// JOKER included, is seeded from (runSeed, nodeId), so it replays the
    /// identical offer rather than re-rolling a new one.
    private func resumeUnresolvedMystery() {
        guard oldJokerView == nil, overlay == nil, presentedViewController == nil,
              let node = campaign.currentNode(), node.type == "mystery",
              !campaign.isNodeCleared(node.id),
              let map = current as? MapViewController else { return }
        runMysteryEvent(node: node, on: map)
    }

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
            // BLANK pickup: nothing was added — it grants a REMOVAL. Open the
            // choose-a-card-to-remove flow (web index.html:28430-28434); the
            // Blank never flies into the deck.
            if let card, card.blank {
                map.render()
                openMapBlankRemovals(1)
                return
            }
            map.collectCards(card.map { [$0] } ?? []) { map.render() }
        case "pack":
            let cards = campaign.resolvePack(node)
            persist(phase: "map")
            // Any BLANK revealed in the pack grants a removal instead of a
            // card — its choose flow runs after the reveal closes, one picker
            // per Blank (web index.html:28449-28470).
            let gained = cards.filter { !$0.blank }
            let blanks = cards.count - gained.count
            let vc = PackRevealViewController(campaign: campaign, title: "Pack",
                                              content: .cards(cards), mode: .show) { [weak self, weak map] _ in
                guard let map else { return }
                map.collectCards(gained) { map.render() }
                self?.persist(phase: "map")
                if blanks > 0 { self?.openMapBlankRemovals(blanks) }
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

    public func storeWantsMenu(_ store: StoreViewController) {
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
        // THE OLD JOKER gets first refusal on a mystery node. His roll runs on
        // its own seeded substream, so this never shifts the ordinary outcome.
        // (An armed debug mystery key skips him — the point of arming one is
        // reaching a specific Queen/Two outcome, not losing it to his roll.)
        if campaign.debugForcedMysteryKey == nil,
           let offer = campaign.rollOldJoker(node.id) {
            presentOldJoker(offer, nodeId: node.id, map: map)
            return
        }
        // DEBUG: an armed offer that could NOT be built here. Say so — this
        // used to look identical to the arming being ignored, because the node
        // just ran an ordinary mystery instead. The key stays armed, so fixing
        // the state and walking onto the next ? works.
        if campaign.debugForcedJokerBlocked, let key = campaign.debugForcedJokerKey {
            campaign.debugForcedJokerBlocked = false
            presentOverlay(PhaseOverlayView.itemUnlock(
                title: "\(key.uppercased()) CAN'T BUILD HERE",
                body: "That offer needs state this run doesn't have: a shop ahead for a ride, "
                    + "an item to point at for a trade. It stays armed for the next ? node.") {
                [weak self] in
                self?.dismissOverlay()
                self?.completeMystery(node.id)
            })
            return
        }
        let key: String
        let wasForced = campaign.debugForcedMysteryKey != nil
        if let forced = campaign.debugForcedMysteryKey {
            campaign.debugForceMystery(nil)          // one-shot, like the joker's
            key = forced
        } else {
            key = campaign.rollMysteryEvent(node.id)
        }
        // BOUNCER (router batch 2): an equipped ward can turn the Two away —
        // he shows up, takes nothing, leaves. Debug-forced keys bypass it so
        // the picker still reaches every outcome.
        if MysteryConfig.twoKeys.contains(key), !wasForced,
           campaign.twoWardNegates(node.id) {
            let out = MysteryOutcome(key: "twoWarded", title: "Turned Away",
                                     desc: "Your pillar saved you.")
            presentOverlay(PhaseOverlayView.mystery(
                outcome: out,
                presenter: MysteryCast.Presenter(name: "Just a Two",
                                                 art: ItemArt.justATwo(scale: 4),
                                                 line: "Ah, nothing for you today."),
                deckId: campaign.deckId,
                mapPeek: true,
                onPeekChanged: { [weak map] p in map?.travelBlocked = p },
                onDeck: { [weak self] in self?.presentDeckInspect() }) { [weak self] in
                self?.dismissOverlay()
                self?.completeMystery(node.id)
            })
            Sound.shared.mysteryStore()
            return
        }
        autopilot?.noteMystery(key)
        guard let outcome = campaign.applyMysteryEvent(key, nodeId: node.id) else {
            _ = campaign.markNodeCleared(node.id)
            persist(phase: "map")
            map.render()
            return
        }
        persist(phase: "map")
        // THE CON is a conversation, not a reveal — the Two makes its one
        // offer in person (and it is lying).
        if outcome.key == "mammaLie" {
            presentMammaCon(outcome, node: node, map: map)
            return
        }
        // THE TWO'S GAME is also a conversation: it wants a call, not a reveal.
        if outcome.key == "twoGame" {
            presentTwoGame(outcome, node: node, map: map)
            return
        }
        // The news arrives in person: the Beheaded Queen hands over anything
        // good, Just a Two delivers anything bad. (The Old Joker's own
        // chained reveals stay his — see runChainedMystery.)
        let overlay = PhaseOverlayView.mystery(outcome: outcome,
                                               presenter: MysteryCast.presenter(for: outcome),
                                               deckId: campaign.deckId,
                                               mapPeek: true,
                                               onPeekChanged: { [weak map] p in map?.travelBlocked = p },
                                               onDeck: { [weak self] in self?.presentDeckInspect() }) { [weak self, weak map] in
            guard let self else { return }
            self.dismissOverlay()
            self.continueMystery(outcome, node: node, map: map)
        }
        presentOverlay(overlay)
    }

    /// JUST A TWO'S CON — its first spoken offer, run through the Old
    /// Joker's conversation modal with the Two's own card. It claims it can
    /// take you to Mamma for every coin or a ★ Joker. It cannot. Whatever
    /// you hand over is simply gone; walking away costs nothing, which is
    /// the only honest number on the table.
    private func presentMammaCon(_ o: MysteryOutcome, node: MapNode, map: MapViewController?) {
        let purse = o.amount ?? 0
        let options: [OldJokerView.Option] = [
            .init(label: "GIVE ALL YOUR COINS", detail: "−\(purse) coins",
                  role: .danger, choice: .pick(0), enabled: purse > 0),
            .init(label: "GIVE A ★ JOKER", detail: "one leaves your deck",
                  role: .danger, choice: .pick(1)),
            .init(label: "WALK AWAY", detail: nil, role: .plain, choice: .decline),
        ]
        let view = OldJokerView(
            title: "Just a Two",
            line: "I know Mamma. Personally. I can take you to her. For every coin you've got, or one of them stars.",
            offer: "Pay what it asks, and Just a Two says it will bring you to Mamma. It seems very sure of itself.",
            options: options,
            art: ItemArt.justATwo(scale: 5),
            backLabel: "◀ BACK TO THE TWO") { [weak self, weak map] choice in
            guard let self else { return }
            self.oldJokerView?.dismiss { [weak self] in
                guard let self else { return }
                self.oldJokerView = nil
                guard case .pick(let i) = choice else {
                    self.completeMystery(node.id)
                    return
                }
                let r = self.campaign.resolveMammaLie(givingCoins: i == 0)
                self.persist(phase: "map")
                map?.render()
                Sound.shared.bad()
                let paid = r.jokerTaken ? "Your ★ Joker"
                    : "\(r.coinsTaken) coin\(r.coinsTaken == 1 ? "" : "s")"
                let after = MysteryOutcome(
                    key: "mammaLie", title: "The Long Walk",
                    desc: "\(paid), gone. It walked you in one big circle and wandered off. Mamma never came.")
                self.presentOverlay(PhaseOverlayView.mystery(
                    outcome: after,
                    presenter: MysteryCast.presenter(for: after),
                    deckId: self.campaign.deckId,
                    mapPeek: true,
                    onPeekChanged: { [weak map] p in map?.travelBlocked = p }) { [weak self] in
                    self?.dismissOverlay()
                    self?.completeMystery(node.id)
                })
            }
        }
        view.onPeekChanged = { [weak map] peeking in map?.travelBlocked = peeking }
        view.onDeck = { [weak self] in self?.presentDeckInspect() }
        oldJokerView?.removeFromSuperview()
        oldJokerView = view
        view.present(in: view.superview ?? self.view)
        Sound.shared.mysteryStore()
    }

    /// THE TWO'S GAME — one higher/lower/same call against its hidden card
    /// and the pivot rank. It only turns up when the Same shield is charged,
    /// because that is the stake: winning pays NOTHING, losing drains the
    /// shield. There is no walking away from a two with a grudge.
    private func presentTwoGame(_ o: MysteryOutcome, node: MapNode, map: MapViewController?) {
        let pivot = Int(GameData.shared.items.mystery.raw["twoGame"]?.asObject?["pivot"]?.asNumber ?? 8)
        let calls = ["higher", "lower", "same"]
        let options: [OldJokerView.Option] = [
            .init(label: "HIGHER", detail: nil, role: .plain, choice: .pick(0)),
            .init(label: "LOWER", detail: nil, role: .plain, choice: .pick(1)),
            .init(label: "SAME", detail: nil, role: .plain, choice: .pick(2)),
        ]
        let view = OldJokerView(
            title: "Just a Two",
            line: "I'm thinking of a card. Higher or lower than an \(pivot)? Twos always know. Let's see if you do.",
            offer: "One call against its hidden card. Win and you get nothing. Lose and your Same shield is drained.",
            options: options,
            art: ItemArt.justATwo(scale: 5),
            backLabel: "◀ BACK TO THE TWO") { [weak self, weak map] choice in
            guard let self else { return }
            self.oldJokerView?.dismiss { [weak self] in
                guard let self else { return }
                self.oldJokerView = nil
                guard case .pick(let i) = choice else {
                    self.completeMystery(node.id)
                    return
                }
                let rank = o.amount ?? 0
                let won = self.campaign.resolveTwoGame(rank: rank, guess: calls[i])
                self.persist(phase: "map")
                map?.render()
                if won { Sound.shared.good() } else { Sound.shared.bad() }
                let after = MysteryOutcome(
                    key: "twoGame",
                    title: won ? "Nothing" : "Punctured",
                    desc: won ? "You called it. You win nothing. It seems pleased anyway."
                              : "Wrong. Your Same shield is drained.",
                    cards: o.cards)
                self.presentOverlay(PhaseOverlayView.mystery(
                    outcome: after,
                    presenter: MysteryCast.presenter(for: after),
                    deckId: self.campaign.deckId,
                    mapPeek: true,
                    onPeekChanged: { [weak map] p in map?.travelBlocked = p }) { [weak self] in
                    self?.dismissOverlay()
                    self?.completeMystery(node.id)
                })
            }
        }
        view.onPeekChanged = { [weak map] peeking in map?.travelBlocked = peeking }
        view.onDeck = { [weak self] in self?.presentDeckInspect() }
        oldJokerView?.removeFromSuperview()
        oldJokerView = view
        view.present(in: view.superview ?? self.view)
        Sound.shared.mysteryStore()
    }

    // MARK: - The Old Joker

    private func presentOldJoker(_ offer: OldJoker.Offer, nodeId: Int, map: MapViewController?) {
        persist(phase: "map")
        // Item decisions draw the trade (the store's EQUIPPED→NEW block);
        // the itemKey text stands in only when there is nothing to draw.
        let compares = OldJokerCopy.compareRows(for: offer, in: campaign)
        let view = OldJokerView(title: OldJokerCopy.name,
                                line: OldJokerCopy.line(for: offer),
                                offer: OldJokerCopy.offerText(for: offer, in: campaign),
                                items: compares.isEmpty
                                    ? OldJokerCopy.itemKey(for: offer, in: campaign) : [],
                                compares: compares,
                                options: OldJokerCopy.options(for: offer, in: campaign),
                                // The Ride spends stops the player hasn't seen —
                                // they get to look at the map first.
                                // SHOW MAP on EVERY offer now (it used to be
                                // the Ride's alone) — the hold-peek is gone.
                                // THIRSTY names its own amount on a stepper.
                                givePurse: { if case .thirsty(let p) = offer { return p }; return nil }()
                               ) { [weak self] choice in
            self?.resolveOldJoker(offer, choice: choice, nodeId: nodeId, map: map)
        }
        // A peek looks at the map; it never moves you along it.
        view.onPeekChanged = { [weak map] peeking in map?.travelBlocked = peeking }
        view.onDeck = { [weak self] in self?.presentDeckInspect() }
        oldJokerView?.removeFromSuperview()
        oldJokerView = view
        view.present(in: view.superview ?? self.view)
        Sound.shared.mysteryStore()
    }

    private func resolveOldJoker(_ offer: OldJoker.Offer, choice: OldJoker.Choice,
                                 nodeId: Int, map: MapViewController?) {
        // `.accept` on a collection means "pay up" — the engine treats it the
        // same as any other resolution, and never lets it go below zero.
        let result = campaign.resolveOldJoker(offer, choice: choice, nodeId: nodeId)
        persist(phase: "map")
        // Repaint the shell NOW, while his modal is still dismissing: coins and
        // the Same shield both move on his offers, and the bar behind him
        // should already read true by the time it is uncovered.
        map?.render()
        oldJokerView?.dismiss { [weak self] in
            guard let self, let result else { self?.completeMystery(nodeId); return }
            self.oldJokerView = nil
            self.afterOldJoker(result, nodeId: nodeId, map: map)
        }
    }

    /// The follow-through: pickers, teleports and chained outcomes all happen
    /// AFTER his modal is gone, so nothing is presented under a dismissal.
    private func afterOldJoker(_ r: OldJoker.Result, nodeId: Int, map: MapViewController?) {
        if r.coins != 0 { Sound.shared.coinBonus() }

        // PURGE / paid CUT — the player now picks the cards that leave.
        if r.removeCount > 0 {
            var left = r.removeCount
            var lastRemoved: String?
            func pickNext() {
                guard left > 0 else {
                    // The paid Cut's closing modal NAMES the card that left —
                    // "Choose the one that leaves." after the choice was made
                    // read as a stale instruction.
                    var done = r
                    if r.key == "cut", let name = lastRemoved {
                        done.detail = "\(name) purged."
                    }
                    finishJokerRemovals(done, nodeId: nodeId, map: map)
                    return
                }
                left -= 1
                let picker = CardPickerViewController(campaign: campaign, mode: .removal(price: 0)) { [weak self] removedId in
                    guard let self else { return }
                    if let id = removedId, let c = self.campaign.findById(id) {
                        let rank = DeckManager.ranks.first { $0.value == c.currentRank }?.label
                            ?? "\(c.currentRank)"
                        lastRemoved = c.joker ? "★ Joker" : "\(rank)\(c.suit)"
                    }
                    self.persist(phase: "map")
                    pickNext()
                }
                picker.forced = true   // he does not take "never mind" here
                present(picker, animated: false)
            }
            pickNext()
            return
        }
        // THE DUPLICATE — two picks: the card he copies, then the card the
        // copy replaces. Nothing is committed until both are made, so backing
        // out of either leaves the deck exactly as it was.
        if r.key == "duplicate", let sticker = r.leechSticker {
            let copyPicker = CardPickerViewController(
                campaign: campaign,
                mode: .choose(title: "Copy a card", verb: "Copy",
                              prompt: "Pick the card he copies, stickers and all.",
                              allowJokers: false)) { [weak self] sourceId in
                guard let self, let sourceId else { self?.showJokerResult(r, nodeId: nodeId, map: map); return }
                // NAME THE COPY. The second pick decides what the duplicate
                // replaces, and you can't weigh that against a card you can no
                // longer see — the banner used to show only his own mark.
                let copied = self.campaign.getRunDeck().first { $0.id == sourceId }
                let mark = GameData.shared.items.oldJoker.string("duplicate", "sticker", "leech")
                let markName = GameData.shared.stickerTypes.get(mark)?.label ?? mark
                let copyName = copied.map { c -> String in
                    let rank = DeckManager.ranks.first { $0.value == c.currentRank }?.label
                        ?? "\(c.currentRank)"
                    let extra = c.stickers.count > 1
                        ? " + \(c.stickers.count - 1) sticker\(c.stickers.count == 2 ? "" : "s")" : ""
                    return "\(rank)\(c.suit)\(extra)"
                } ?? "the copy"
                let replacePicker = CardPickerViewController(
                    campaign: self.campaign,
                    mode: .choose(title: "Replace with \(copyName)", verb: "Replace",
                                  prompt: "The copy of \(copyName) carries a \(markName). Pick the card it takes the place of.",
                                  allowJokers: true,
                                  subjectCardId: sourceId,
                                  subjectExtraSticker: sticker)) { [weak self] replaceId in
                    guard let self else { return }
                    if let replaceId, replaceId != sourceId {
                        _ = self.campaign.applyJokerDuplicate(sourceId: sourceId,
                                                              replaceId: replaceId,
                                                              sticker: sticker)
                        Sound.shared.swapCard()
                        self.persist(phase: "map")
                    }
                    self.showJokerResult(r, nodeId: nodeId, map: map)
                }
                replacePicker.forced = true    // the copy has to go somewhere
                self.present(replacePicker, animated: false)
            }
            present(copyPicker, animated: false)
            return
        }
        // THE DRINK, RETURNED — he pays in things, or he collects in blood.
        if r.key == "thirstReturn" {
            deliverThirstReturn(r, nodeId: nodeId, map: map)
            return
        }
        // TWO DOORS / anything that hands off to an ordinary mystery outcome.
        if let chained = r.chainedMysteryKey {
            runChainedMystery(chained, nodeId: nodeId, map: map)
            return
        }
        // THE RIDE.
        if let dest = r.travelTo, let map {
            _ = campaign.markNodeCleared(nodeId)
            persist(phase: "map")
            map.render()
            // He drives: the character is led up the map, he peels off, and the
            // shop opens behind him.
            map.travel(to: dest, escortedByOldJoker: true)
            return
        }
        showJokerResult(r, nodeId: nodeId, map: map)
    }

    private func finishJokerRemovals(_ r: OldJoker.Result, nodeId: Int, map: MapViewController?) {
        guard let curses = r.curseStickers, !curses.isEmpty else {
            showJokerResult(r, nodeId: nodeId, map: map); return
        }
        let hit = campaign.applyJokerCurses(curses, nodeId: nodeId)
        persist(phase: "map")
        // The other half of the bargain has to be SEEN. The cards were being
        // marked silently, so the deal read as "remove three, free" — the
        // player only met the curses later, mid-deal, with no idea why.
        guard !hit.isEmpty else { showJokerResult(r, nodeId: nodeId, map: map); return }
        // The reveal names the curses that landed (they can differ per card
        // now); the card strip shows each afflicted card with its new chip.
        let labels = hit.map { GameData.shared.stickerTypes.get($0.curse)?.label ?? $0.curse }
        let uniqueLabels = labels.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        let hitIds = hit.map(\.cardId)
        let marked = campaign.getRunDeck().filter { hitIds.contains($0.id) }
        let outcome = MysteryOutcome(
            key: "cursedSticker",
            title: uniqueLabels.count == 1 ? (uniqueLabels[0]) : "His marks",
            desc: uniqueLabels.count == 1
                ? "\(hit.count) card\(hit.count == 1 ? "" : "s") took his mark."
                : "His due: " + uniqueLabels.joined(separator: ", "),
            stickerId: hit[0].curse, stickerLabel: uniqueLabels.joined(separator: ", "),
            cards: marked)
        presentOverlay(PhaseOverlayView.mystery(outcome: outcome, deckId: campaign.deckId,
                                                mapPeek: true,
                                                onPeekChanged: { [weak map] p in map?.travelBlocked = p }) { [weak self] in
            self?.dismissOverlay()
            self?.showJokerResult(r, nodeId: nodeId, map: map)
        })
        Sound.shared.sticker()
    }

    /// THE DRINK, RETURNED. Paid: he empties his coat one item at a time and
    /// each must be PLACED or DISCARDED before the next appears — no silent
    /// inventory dump. Stiffed: he sets about you instead.
    private func deliverThirstReturn(_ r: OldJoker.Result, nodeId: Int, map: MapViewController?) {
        guard r.good else {
            // He wants it out of your hide: a short, ugly deal.
            let cfg = GameData.shared.items.oldJoker
            _ = campaign.markNodeCleared(nodeId)
            persist(phase: "map")
            currentAmbush = DealPlanner.AmbushSpec(cards: cfg.int("thirsty", "ambushCards", 18),
                                                   piles: cfg.int("thirsty", "ambushPiles", 4),
                                                   bounty: Double(cfg.int("thirsty", "ambushBounty", 1)),
                                                   nodeId: nodeId)
            startDeal()
            return
        }
        // HIS COAT, LAID OUT. One modal per item made a six-item payout a
        // six-tap walk with no way to compare them; the shop already knows how
        // to show a shelf, price it, explain each tile on hold and place a
        // Pillar or Base on a column — so the gifts go through that instead,
        // at zero cost, and the player takes what they want.
        let gifts = campaign.rollThirstGifts(budget: r.giftBudget, nodeId: nodeId)
        guard !gifts.isEmpty else { showJokerResult(r, nodeId: nodeId, map: map); return }
        campaign.openGiftShelf(gifts)
        persist(phase: "map")
        mysteryStoreContinue = { [weak self] in
            guard let self else { return }
            // The coat closes with the visit — a leftover free shelf must not
            // follow the player into the next real shop.
            self.campaign.discardStoreOffer()
            self.campaign.endFreeShop()
            self.showJokerResult(r, nodeId: nodeId, map: map)
        }
        showStore(fresh: false, nodeId: nodeId)
    }

    private func runChainedMystery(_ key: String, nodeId: Int, map: MapViewController?) {
        // A chained outcome is THE OLD JOKER's doing (Two Doors' bad door) —
        // its cursedSticker draws from the "doors" pool, not the mystery one.
        guard let outcome = campaign.applyMysteryEvent(key, nodeId: nodeId, cursePath: "doors"),
              let node = campaign.getNode(nodeId) else {
            completeMystery(nodeId); return
        }
        persist(phase: "map")
        presentOverlay(PhaseOverlayView.mystery(outcome: outcome, deckId: campaign.deckId,
                                                mapPeek: true,
                                                onPeekChanged: { [weak map] p in map?.travelBlocked = p }) { [weak self, weak map] in
            guard let self else { return }
            self.dismissOverlay()
            self.continueMystery(outcome, node: node, map: map)
        })
    }

    private func showJokerResult(_ r: OldJoker.Result, nodeId: Int, map: MapViewController?) {
        // His ONE closing statement, then the plain fact of what changed —
        // never a second quip saying the same thing in different words.
        // A settled BLIND SWAP finally shows its two faces: both items, drawn
        // with a two-way arrow between them (router batch) — the reveal the
        // whole offer was building to.
        var compares: [OldJokerView.CompareRow] = []
        if r.key == "blindSwap", let lost = r.lost, let gained = r.gained {
            func side(_ kind: OldJoker.Holding.Kind, _ id: String, tag: String) -> OldJokerView.CompareSide {
                let def = campaign.holdingDef(OldJoker.Holding(kind: kind, id: id))
                return .init(tag: tag,
                             art: ItemArt.forSlot(kind: kind.rawValue, id: id,
                                                  card: nil, deckId: campaign.deckId),
                             name: def?.label ?? id,
                             desc: def?.description ?? "")
            }
            compares = [.init(old: side(lost.kind, lost.id, tag: "GAVE"),
                              new: side(lost.kind, gained, tag: "GOT"),
                              twoWay: true)]
        }
        let view = OldJokerView(title: OldJokerCopy.name,
                                line: OldJokerCopy.closingLine(for: r),
                                offer: r.detail,
                                compares: compares,
                                options: [.init(label: "GO ON", detail: nil, role: .cta, choice: .decline)]) { [weak self] _ in
            self?.oldJokerView?.dismiss { [weak self] in
                self?.oldJokerView = nil
                self?.completeMystery(nodeId)
            }
        }
        view.onPeekChanged = { [weak map] peeking in map?.travelBlocked = peeking }
        view.onDeck = { [weak self] in self?.presentDeckInspect() }
        oldJokerView = view
        view.present(in: self.view)
        map?.render()
    }

    /// The shop's deck inspector, opened from a mystery popup's DECK chip.
    private func presentDeckInspect() {
        present(DeckInspectViewController(campaign: campaign), animated: false)
    }

    private func completeMystery(_ nodeId: Int) {
        _ = campaign.markNodeCleared(nodeId)
        persist(phase: "map")
        if let map = current as? MapViewController { map.render() }
        else { showMap() }
    }

    /// A Blank (∅ Removal) grant: one FREE removal picker per Blank, chained
    /// (the web's openMapBlankRemove). Declining is allowed — the picker keeps
    /// its ✕; the grant is simply passed up. Checkpointed per confirm by the
    /// picker's own PersistenceHolder hook.
    private func openMapBlankRemovals(_ count: Int) {
        guard count > 0 else { return }
        let picker = CardPickerViewController(campaign: campaign, mode: .removal(price: 0)) { [weak self] _ in
            self?.openMapBlankRemovals(count - 1)
        }
        picker.forced = false
        present(picker, animated: false)
    }

    private func continueMystery(_ o: MysteryOutcome, node: MapNode, map: MapViewController?) {
        switch o.key {
        case "cards", "joker":
            if let map { map.collectCards(o.cards) { [weak self] in self?.completeMystery(node.id) } }
            else { completeMystery(node.id) }
        case "giftCard":
            // Her keepsake swaps in through the tray picker — SKIP is legal
            // (the card waits in the tray for the next store gate).
            if let cid = o.cardId,
               let idx = campaign.getPackTray().firstIndex(where: { $0.id == cid }) {
                let picker = CardPickerViewController(campaign: campaign,
                                                      mode: .swap(trayIndex: idx, step: nil)) { [weak self] _ in
                    self?.completeMystery(node.id)
                }
                picker.showsSkip = true
                present(picker, animated: false)
            } else { completeMystery(node.id) }
        case "stickerPack":
            if let sid = o.stickerId {
                let picker = CardPickerViewController(campaign: campaign,
                                                      mode: .applySticker(typeId: sid)) { [weak self] _ in
                    self?.completeMystery(node.id)
                }
                // The gift may be DECLINED (router batch): Skip discards the
                // sticker after the shared confirm. No forcing — a player who
                // doesn't want the mark on any card shouldn't have to place it.
                picker.showsSkip = true
                present(picker, animated: false)
            } else { completeMystery(node.id) }
        case "freeRemoval":
            let picker = CardPickerViewController(campaign: campaign, mode: .removal(price: 0)) { [weak self] _ in
                self?.completeMystery(node.id)
            }
            // A Purge must LAND. It used to be dismissable, so the outcome
            // could be taken and then walked away from — the node was spent and
            // the deck was untouched. Same rule the granted sticker follows.
            // Guarded on there being more than one card: forcing a pick on a
            // one-card deck would demand the player delete their whole deck.
            picker.forced = campaign.deckSize() > 1
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
            // fresh=false (web index.html:28351-28369) — a saved offer is never
            // clobbered (no free reroll off a refresh); the detour offer keys
            // to the MYSTERY node's id.
            mysteryStoreContinue = { [weak self] in self?.completeMystery(node.id) }
            showStore(fresh: false, nodeId: node.id)
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
        // His comp was for THIS visit. Walking out ends it whether or not you
        // spent it — otherwise a declined shop would bank a free one forever.
        campaign.endFreeShop()
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

    /// The curse specimen (debug, `-curseSheet 1`): every cursed sticker's
    /// chip + label + description, two columns — the per-curse art and help
    /// text on one evidence still.
    private func showCurseSheet() {
        let panel = UIScrollView()
        panel.backgroundColor = CRT.feltDeep
        panel.frame = view.bounds
        panel.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        let curses = GameData.shared.stickerTypes.all().filter(\.cursed)
        let colW = view.bounds.width / 2
        var y: CGFloat = 70
        for (i, def) in curses.enumerated() {
            let x = CGFloat(i % 2) * colW
            let chip = UIImageView(image: ItemArt.sticker(def, size: 56))
            chip.layer.magnificationFilter = .nearest
            chip.contentMode = .scaleAspectFit
            chip.frame = CGRect(x: x + 14, y: y, width: 56, height: 56)
            panel.addSubview(chip)
            let name = CRTKit.label(def.label, size: 16, color: CRT.gold)
            name.frame = CGRect(x: x + 80, y: y, width: colW - 92, height: 20)
            panel.addSubview(name)
            let desc = CRTKit.label(def.description.replacingOccurrences(of: "Cursed. ", with: ""),
                                    size: 14, color: CRT.muted)
            desc.frame = CGRect(x: x + 80, y: y + 20, width: colW - 92, height: 96)
            panel.addSubview(desc)
            if i % 2 == 1 { y += 126 }
        }
        panel.contentSize = CGSize(width: view.bounds.width, height: y + 120)
        view.insertSubview(panel, belowSubview: crt)
    }

    /// The type-scale specimen (debug, `-typeRamp 1`): every candidate size as
    /// a real caption in the real fonts on the real felt, for the on-device
    /// floor-picking test. Text renders through the SAME clamp the game uses,
    /// so the raw UIFont path here is deliberate — the ramp must show sizes
    /// BELOW the floor to prove where readability dies.
    private func showTypeRamp() {
        let panel = UIView()
        panel.backgroundColor = CRT.feltDeep
        panel.frame = view.bounds
        panel.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        var y: CGFloat = 70
        func row(_ size: CGFloat) {
            let sample = "Costs ◉5. Decline and nothing happens. K♠ 10♦ +3"
            for (dx, color) in [(12, CRT.cardFace), (12, CRT.muted)] as [(CGFloat, UIColor)] {
                let l = UILabel()
                l.attributedText = NSAttributedString(string: (color == CRT.muted ? "muted · " : "\(Int(size))pt · ") + sample,
                                                      attributes: [.font: UIFont(name: CRT.Font.body, size: size)!,
                                                                   .foregroundColor: color])
                l.frame = CGRect(x: dx, y: y, width: 380, height: size + 8)
                panel.addSubview(l)
                y += size + 8
            }
            y += 10
        }
        for s in [11, 12, 13, 14, 15, 16, 17, 18] as [CGFloat] { row(s) }
        view.insertSubview(panel, belowSubview: crt)
    }
}
