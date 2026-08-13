import UIKit
import SpriteKit
import GameCore

/// Hosts the deal scene and owns every gesture.
///
/// The thresholds are ported EXACTLY from the web's swipe input so the feel
/// carries over: an 8pt tap slop, a 26pt dead-zone before a guess arms, commit
/// on release, cancel inside the dead-zone, and a 350ms hold for card help.
/// Native recognizers replace the pointer-event bookkeeping the webview needed.
public final class DealViewController: UIViewController {

    /// travel to arm a guess (past the dead-zone) — web: DRAG_THRESH
    private static let dragThreshold: CGFloat = 26
    /// movement under this is a tap (selects) — web: TAP_SLOP
    private static let tapSlop: CGFloat = 8
    /// pile hold → card peek — web: INFO_HOLD_MS
    private static let holdSeconds: TimeInterval = 0.35

    private var skView: SKView!
    private var scene: DealScene!
    public private(set) var controller: DealController!
    private let mode: DealController.Mode
    private let sharedCampaign: CampaignState?
    private let runMap: RunMap?

    private var dragPile: Int?
    private var dragArmed: Guess?
    private var dragMoved = false
    /// The histogram drag-scrub (odds readout) is active.
    private var scrubbing = false
    private var pressedButton: PixelButton?
    private var holdShown = false
    /// The shared bottom prompt bar (offers, base confirms) over the SKView.
    private let promptBar = PromptBar()
    /// Piles armed as tap TARGETS (revive / Phoenix), with the answer callback.
    private var targetPick: (targets: [Int], kind: TargetKind, answer: (Int?) -> Void)?

    /// Set by the launcher so a finished deal can pop back with its result.
    public var onExit: ((Bool, Int, Int) -> Void)?
    /// Campaign/Zen: the rich outcome, delivered after the end presentation.
    public var onOutcome: ((DealOutcome) -> Void)?
    public var onZenGuess: ((Bool) -> Void)?
    /// FIRST-RUN TUTORIAL: set before presenting to script the Zen opening.
    public var tutorialGuided = false
    /// …and the tour's event feed (pile taps, the ▲ press, swipe-guesses).
    public var onTutorialEvent: ((TutorialView.Event) -> Void)?

    /// LIVE anchor rects for the tour's ring — the REAL pile 1 and ▲ button,
    /// in this view's coordinates (the SKView fills it).
    public func tutorialAnchorRect(_ key: String) -> CGRect? {
        switch key {
        case "dealPileFirst": return scene?.pileRectInView(0)
        case "dealRailUp": return scene?.railUpRectInView()
        case "pileCount":
            // The count badge rides the pile's bottom-left corner.
            guard let p = scene?.pileRectInView(0) else { return nil }
            return CGRect(x: p.minX - 8, y: p.maxY - 30, width: 46, height: 42)
        default: return nil
        }
    }
    /// The corner menu button (campaign/zen only).
    public var onMenu: (() -> Void)?
    /// MID-DEAL PERSISTENCE: the snapshot to resume from (set by the flow
    /// before presentation) and the per-action snapshot sink (the flow's
    /// background writer). Campaign mode only — Zen never persists.
    public var resumeMidDeal: [String: JSONValue]?
    public var onMidDealSnapshot: (([String: JSONValue]) -> Void)?

    public init(setup: DealController.Setup) {
        self.mode = .debug(setup)
        self.sharedCampaign = nil
        self.runMap = nil
        super.init(nibName: nil, bundle: nil)
    }

    public init(mode: DealController.Mode, campaign: CampaignState, runMap: RunMap?) {
        self.mode = mode
        self.sharedCampaign = campaign
        self.runMap = runMap
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    public override func loadView() {
        skView = SKView(frame: .zero)
        skView.isMultipleTouchEnabled = false
        // The pixel grid must never be resampled.
        skView.preferredFramesPerSecond = 60
        skView.ignoresSiblingOrder = true
        view = skView
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = CRT.feltDeep

        let pan = UIPanGestureRecognizer(target: self, action: #selector(onPan))
        pan.maximumNumberOfTouches = 1
        let tap = UITapGestureRecognizer(target: self, action: #selector(onTap))
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(onHold))
        hold.minimumPressDuration = Self.holdSeconds
        // A thumb resting on a card rolls well past UIKit's 10pt default before
        // 0.35s is up, which failed the recognizer outright — and the pan then
        // armed a swipe, so a sloppy hold could PLAY A MOVE instead of showing
        // help. 24pt still leaves the swipe-guess its 26pt dead-zone.
        hold.allowableMovement = 24
        // A pan must be able to start even after the hold recognizer engages,
        // and a tap must not wait on the pan.
        pan.delegate = self
        hold.delegate = self
        tap.delegate = self
        [pan, tap, hold].forEach { view.addGestureRecognizer($0) }
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard view.bounds.width > 0, view.bounds.height > 0 else { return }
        // The scene is created HERE, not in viewDidLoad: at viewDidLoad the
        // view has no bounds yet, and a scene laid out at zero size would hand
        // the deal-out animation stale target positions that then stomp the
        // real layout when they land.
        if scene == nil {
            scene = DealScene(size: view.bounds.size)
            scene.safeInsets = view.safeAreaInsets
            switch mode {
            case .debug(let setup):
                controller = DealController(setup: setup, scene: scene)
                controller.onFinish = { [weak self] win, coins, score in
                    guard let self else { return }
                    // Let the banner play, then hand back to the launcher.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
                        self.onExit?(win, coins, score)
                    }
                }
            case .campaign, .zen:
                controller = DealController(mode: mode, campaign: sharedCampaign!,
                                            runMap: runMap, scene: scene,
                                            reduceMotion: UserDefaults.standard.bool(forKey: "autoPlay"))
                controller.onOutcome = { [weak self] outcome in
                    guard let self else { return }
                    // Let the end presentation read, then hand the fold up.
                    DispatchQueue.main.asyncAfter(deadline: .now() + (outcome.won ? 1.4 : 1.2)) {
                        self.onOutcome?(outcome)
                    }
                }
                controller.onZenGuess = { [weak self] correct in self?.onZenGuess?(correct) }
                // FIRST-RUN TUTORIAL: the guided deal's scripted opening.
                if tutorialGuided {
                    controller.preDealArrange = { $0.arrangeTutorialOpening() }
                }
                // "run" checkpoints are a CLIMB durability mechanism — a Zen
                // deal must never write the campaign save (a Zen session would
                // otherwise mint a bogus save and the menu would offer
                // CONTINUE with no climb in progress).
                if case .campaign = mode {
                    controller.onCheckpoint = { [weak self] _ in
                        guard let self, let c = self.sharedCampaign else { return }
                        PersistenceHolder.shared?.checkpoint(c)
                    }
                    // MID-DEAL PERSISTENCE (anti-savescum): every action's
                    // exact-state snapshot rides up to the flow's background
                    // writer; a resume's blob rides down into the boot.
                    controller.resumeMidDeal = resumeMidDeal
                    resumeMidDeal = nil
                    controller.onActionSnapshot = { [weak self] blob in
                        self?.onMidDealSnapshot?(blob)
                    }
                }
                scene.showsMenuButton = true
                scene.onMenuTapped = { [weak self] in self?.onMenu?() }
                wireOffers()
            }
            view.addSubview(promptBar)
            promptBar.frame = view.bounds
            promptBar.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            scene.showsFrameHUD = UserDefaults.standard.bool(forKey: "fps")
            skView.presentScene(scene)
            if UserDefaults.standard.bool(forKey: "autoPlay") { startAutoPlay() }
            // The campaign autopilot plays every deal with card-counted odds
            // (the web autopilot's strategy: best survival move over all piles).
            if UserDefaults.standard.integer(forKey: "autoCampaign") > 0,
               sharedCampaign != nil {
                startOddsPlayer()
            }
            // The slow variant keeps ANIMATIONS ON — the screenshot pass for
            // the travel/pulse/death motion (real autoPlay renders instantly).
            if UserDefaults.standard.bool(forKey: "autoPlaySlow") { startAutoPlay(interval: 1.1) }
            // `-demoCurseFX 1`: fire every curse feedback idiom with sample
            // data on the live board (evidence stills — simctl can't set up
            // each curse's real trigger cheaply).
            if UserDefaults.standard.bool(forKey: "demoCurseFX") {
                // AFTER the reveal + cascade settle — their completion
                // refreshes controls, which would wipe the demo state.
                DispatchQueue.main.asyncAfter(deadline: .now() + 4.2) { [weak self] in
                    guard let self else { return }
                    self.scene.curseIndicator(at: 0, label: "MALFUNCTION")
                    self.scene.showHelp(title: "MALFUNCTION",
                                        body: "K♠ malfunctioned. The correct guess killed the pile.")
                    self.scene.floatCueAtPillar("BLOCKED", col: 1, color: CRT.suitRed)
                    self.scene.curseIndicator(at: 2, label: "PEELED")
                    self.scene.setMagnetTargets([3])
                    self.scene.setSelected(4)
                    self.scene.syncControls(canGuess: true, showReshuffle: false,
                                            reshuffleEnabled: false, sameBlocked: true)
                }
            }
            // `-demoOverlay fan|pilefan|pilefaninfo|help|swipe` opens an
            // overlay for a screenshot pass, since simctl cannot deliver a
            // real touch.
            if let demo = UserDefaults.standard.string(forKey: "demoOverlay") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
                    guard let self else { return }
                    if demo == "fan" {
                        if !self.scene.isFanHintOn { self.scene.toggleFanHint() }
                    } else if demo == "pilefan" || demo == "pilefaninfo" {
                        if !self.scene.isFanHintOn { self.scene.toggleFanHint() }
                        self.showPileFanOverlay(0)
                        if demo == "pilefaninfo" { self.pileFan?.demoShowInfo() }
                    } else if demo == "help", let (t, b) = self.controller.helpText(forPile: 0) {
                        self.scene.showHelp(title: t, body: b)
                    } else if demo == "swipe" {
                        self.scene.setSelected(0)
                        self.scene.showSwipeDirection(.same)
                    }
                }
            }
        } else {
            scene.size = view.bounds.size
            scene.safeInsets = view.safeAreaInsets
        }
    }

    public override var prefersStatusBarHidden: Bool { true }
    public override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }

    // MARK: - Keep-awake (web: KeepAwake while a deal runs)

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        UIApplication.shared.isIdleTimerDisabled = true
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        UIApplication.shared.isIdleTimerDisabled = false
    }

    // MARK: - In-deal offers (PROMPT1: everything rides the shared bottom bar)

    private func wireOffers() {
        controller.onTributeOffer = { [weak self] offer, answer in
            guard let self else { answer(false); return }
            self.scene.setActionTargets([offer.index])
            self.promptBar.show(
                "\(offer.label): bury \(offer.count) card\(offer.count == 1 ? "" : "s") under the highlighted pile?",
                help: "Costs ◉\(Int(offer.cost)). Decline and nothing happens.",
                actions: [
                    .init("Decline", role: .plain) { [weak self] in
                        self?.promptBar.hide(); self?.clearTargets(); answer(false)
                    },
                    .init("Pay ◉\(Int(offer.cost))", role: .gold) { [weak self] in
                        self?.promptBar.hide(); self?.clearTargets(); answer(true)
                    },
                ]) { [weak self] in self?.clearTargets(); answer(false) }
        }
        controller.onActionOffer = { [weak self] action, answer in
            guard let self else { answer(false); return }
            // The board says WHICH pile — a pile number was never something the
            // player could point at. Donate names two, so those wear FROM / TO.
            let text: String
            if action.kind == "donate", let t = action.target {
                self.scene.setDonateTargets(from: action.index, to: t)
                text = "Donate the FROM pile's bottom card to the TO pile?"
            } else {
                self.scene.setActionTargets([action.index])
                text = "Shuffle the highlighted pile's cards?"
            }
            // NO outside-tap dismiss: the offer leaves only through Decline
            // or the action button — a stray board tap used to silently
            // decline it (v6.25).
            self.promptBar.show(text, help: "Optional. Decline keeps things as they are.", actions: [
                .init("Decline", role: .plain) { [weak self] in
                    self?.promptBar.hide(); self?.clearTargets(); answer(false)
                },
                .init(action.kind == "donate" ? "Donate" : "Shuffle", role: .cta) { [weak self] in
                    self?.promptBar.hide(); self?.clearTargets(); answer(true)
                },
            ])
        }
        controller.onReviveOffer = { [weak self] dead, fire in
            guard let self else { fire(nil); return }
            self.armTargetPick(dead, prompt: "Revive: tap a dead pile to bring it back.", fire: fire)
        }
        controller.onBaseTarget = { [weak self] piles, prompt, fire in
            guard let self else { fire(nil); return }
            self.armTargetPick(piles, prompt: prompt, fire: fire)
        }
        controller.onBasePillarTarget = { [weak self] cols, prompt, fire in
            guard let self else { fire(nil); return }
            self.armTargetPick(cols, prompt: prompt, kind: .pillar, fire: fire)
        }
        controller.onBaseNotice = { [weak self] title, help in
            guard let self else { return }
            self.promptBar.show(title, help: help, actions: [
                .init("OK", role: .plain) { [weak self] in
                    self?.promptBar.hide(); self?.controller.promptDismissed()
                },
            ]) { [weak self] in self?.controller.promptDismissed() }
        }
        controller.onBasePrompt = { [weak self] label, desc, fire in
            guard let self else { return }
            self.promptBar.show("Activate \(label)?", help: desc, actions: [
                .init("Not yet", role: .plain) { [weak self] in
                    self?.promptBar.hide(); self?.controller.promptDismissed()
                },
                .init("Fire", role: .cta) { [weak self] in
                    self?.promptBar.hide(); fire()
                },
            ]) { [weak self] in self?.controller.promptDismissed() }
        }
        // Diamond Ripple: the sticker asks before shuffling every ♦-top pile.
        controller.onRippleOffer = { [weak self] count, answer in
            guard let self else { answer(true); return }
            self.promptBar.show(
                "Diamond Ripple: shuffle \(count) diamond-top pile\(count == 1 ? "" : "s")?",
                help: "Optional. Keep leaves those piles exactly as they are.",
                actions: [
                    .init("Keep", role: .plain) { [weak self] in
                        self?.promptBar.hide(); answer(false)
                    },
                    .init("Shuffle", role: .cta) { [weak self] in
                        self?.promptBar.hide(); answer(true)
                    },
                ]) { answer(false) }
        }
    }

    /// What an armed target tap is picking: a pile on the board, or one of the
    /// player's Pillars (by column).
    enum TargetKind { case pile, pillar }

    private func armTargetPick(_ piles: [Int], prompt: String, kind: TargetKind = .pile,
                               fire: @escaping (Int?) -> Void) {
        targetPick = (piles, kind, fire)
        // Highlight whichever KIND is being asked for — piles for a pile pick,
        // Pillar plaques for a Pillar pick. Marking neither left Demolish
        // asking for a target with nothing on screen indicating one.
        scene.setActionTargets(kind == .pile ? piles : [])
        scene.setPillarTargets(kind == .pillar ? piles : [])
        promptBar.show(prompt, help: nil, actions: [
            .init("Skip", role: .plain) { [weak self] in
                self?.promptBar.hide()
                self?.finishTargetPick(nil)
            },
        ]) { [weak self] in self?.finishTargetPick(nil) }
    }

    private func finishTargetPick(_ target: Int?) {
        guard let tp = targetPick else { return }
        targetPick = nil
        promptBar.hide()
        clearTargets()
        tp.answer(target)
    }

    private func clearTargets() {
        scene.setPillarTargets([])
        scene.setActionTargets([])
        scene.setSelected(nil)
    }

    // MARK: - Auto-play (verification only)

    /// Plays a deal with the SAME deterministic script the Phase 1 engine traces
    /// use — pile `(step*7+3) % alive`, and a call read off the pile's visible
    /// top, with every 5th call a SAME. Used to exercise the whole loop
    /// (guess → resolve → death → deal end) without a human thumb.
    private var autoStep = 0
    private func startAutoPlay(interval: TimeInterval = 0.42) {
        Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] t in
            guard let self, let c = self.controller else { t.invalidate(); return }
            if c.isOver { t.invalidate(); return }
            let alive = c.alivePiles()
            guard !alive.isEmpty else { t.invalidate(); return }
            let pile = alive[(self.autoStep * 7 + 3) % alive.count]
            let v = c.topValue(pile) ?? 8
            let call: Guess = self.autoStep % 5 == 4 ? .same : (v <= 8 ? .higher : .lower)
            self.autoStep += 1
            self.scene.setSelected(pile)
            c.guess(call, pile: pile)
        }
    }

    /// The smart player used by `-autoCampaign`: AutoPilotBrain decides, this
    /// only paces the moves. (The `-autoPlay` script above stays deliberately
    /// dumb — ParityCaptureUITests depends on it losing deals.)
    private func startOddsPlayer() {
        Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] t in
            guard let self, let c = self.controller else { t.invalidate(); return }
            if c.isOver { t.invalidate(); return }
            // Idle (don't invalidate) through the cascade, prompts and offers —
            // a transient block is not the end of the deal.
            guard c.canAcceptGuess else { return }
            guard let pick = AutoPilotBrain.choose(c) else { return }
            self.scene.setSelected(pick.move.pile)
            c.guess(pick.move.call, pile: pick.move.pile)
        }
    }

    // MARK: - Coordinate conversion

    /// UIKit points → scene space (scene anchor is top-left, y negative down).
    private func scenePoint(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x, y: -p.y)
    }

    // MARK: - Tap

    @objc private func onTap(_ g: UITapGestureRecognizer) {
        let p = scenePoint(g.location(in: view))

        if scene.isHelpVisible { scene.hideHelp(); return }

        // Target-pick mode (revive / Phoenix): a tap on an armed pile fires.
        if let tp = targetPick {
            switch tp.kind {
            case .pile:
                if let pile = scene.pileIndex(at: p), tp.targets.contains(pile) { finishTargetPick(pile) }
            case .pillar:
                if let col = scene.pillarCol(at: p), tp.targets.contains(col) { finishTargetPick(col) }
            }
            return
        }

        if let b = scene.button(at: p) {
            fire(button: b)
            return
        }
        // A charged Base plaque fires on tap.
        if let col = scene.baseCol(at: p) {
            Sound.shared.plaqueFire()
            controller.basePlaqueTapped(col: col)
            return
        }
        if let pile = scene.pileIndex(at: p) {
            // Fan hint ARMED: a pile tap opens that pile's full face-up fan
            // OVERLAY (the web's openPileFan) instead of selecting. The sliver
            // peek stays as the armed indicator. Hint off: a tap still just
            // selects the pile.
            if scene.isFanHintOn {
                showPileFanOverlay(pile)
                return
            }
            controller.select(pile: pile)
            onTutorialEvent?(.pileTapped(pile))
            return
        }
        // Tap the deck stack → the full deck inspection (campaign/zen).
        if scene.isDeckPanel(p), sharedCampaign != nil {
            if case .campaign = mode {
                // Live deal: pass what's still in the draw pile so the page
                // shows remaining-vs-full and shadows the dealt-away cards.
                present(DeckInspectViewController(campaign: sharedCampaign!,
                                                  remainingIds: controller.remainingCardIds(),
                                                  remainingRanks: controller.deckCounts()),
                        animated: false)
            } else {
                present(DeckInspectViewController(campaign: sharedCampaign!), animated: false)
            }
            return
        }
        // A tap on empty felt clears the selection.
        scene.setSelected(nil)
        controller.refreshAll()
    }

    // MARK: - Pile fan overlay (the web's openPileFan)

    private var pileFan: PileFanOverlayView?

    /// The armed-hint pile tap: the pile's full contents face-up in a centered
    /// overlay — top card first, horizontally scrollable when the pile
    /// outgrows the panel. Dismiss = tap outside (the scrim eats every touch,
    /// so a tap meant for ANOTHER pile just closes; the player retaps) or the
    /// ✕. This replaces the old in-place `DealScene.showPileFan` splay, which
    /// is now uncalled (dead code by design — DealScene is untouched).
    private func showPileFanOverlay(_ pile: Int) {
        let cards = controller.pileCards(pile)
        guard !cards.isEmpty else { return }
        pileFan?.close()
        let fan = PileFanOverlayView(pileIndex: pile, stackOrder: cards)
        fan.onDismiss = { [weak self] in self?.pileFan = nil }
        fan.show(in: view)
        pileFan = fan
        Sound.shared.fanOpen()
    }

    private func fire(button b: PixelButton) {
        guard b.isEnabled else { return }
        scene.press(b, down: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) { [weak self] in self?.scene.press(nil, down: false) }
        // HIGHER / SAME / LOWER own directional cues, fired from
        // `DealController.guess` so a SWIPE sounds identical to a button press.
        // Everything else in the rail gets the shared UI click.
        switch b.id {
        case "higher", "same", "lower": break
        default: Sound.shared.button()
        }
        switch b.id {
        case "fan":       scene.toggleFanHint()
        case "higher":    onTutorialEvent?(.higherTapped); controller.guess(.higher)
        case "same":      controller.guess(.same)
        case "lower":     controller.guess(.lower)
        case "reshuffle": controller.reshuffle()
        case "menu":      scene.onMenuTapped?()
        default: break
        }
    }

    // MARK: - Swipe guessing

    @objc private func onPan(_ g: UIPanGestureRecognizer) {
        let p = scenePoint(g.location(in: view))
        switch g.state {
        case .began:
            if scene.isHelpVisible {
                // A drag that starts ON the histogram while its band help is
                // up is a scrub, not a stuck screen: drop the help, track on.
                if scene.histogramRank(at: p) != nil { scene.hideHelp(); holdShown = false }
                else { return }
            }
            dragPile = scene.pileIndex(at: p)
            dragArmed = nil
            dragMoved = false
            if let dp = dragPile {
                controller.select(pile: dp)
            } else if let r = scene.histogramRank(at: p) {
                // The histogram drag-scrub: show the odds line for the rank
                // under the finger (the web's deckStrip scrubber).
                scrubbing = true
                scene.showScrub(value: r.value, label: r.label)
            }

        case .changed:
            if scrubbing {
                // Once armed, the scrub tracks x until finger-up — even when
                // the finger wanders off the histogram (clamped fallback).
                if let r = scene.histogramRank(at: p) ?? scene.histogramRank(nearX: p.x) {
                    scene.showScrub(value: r.value, label: r.label)
                }
                return
            }
            guard let dp = dragPile else { return }
            let t = g.translation(in: view)
            // The web's dy is UP-positive; UIKit's is DOWN-positive.
            let dx = t.x, dy = -t.y
            if max(abs(dx), abs(dy)) > Self.tapSlop { dragMoved = true }
            // Press feedback tracks the finger: the card nudges toward the drag.
            scene.dragNudge(pile: dp, dx: dx, dy: dy)
            let armed = Self.direction(dx: dx, dy: dy)
            if armed != dragArmed {
                dragArmed = armed
                scene.showSwipeDirection(armed)
            }

        case .ended:
            // Clear the moved latch HERE. It was only ever reset in `.began`,
            // and a still hold never starts a pan — so after the player's first
            // swipe-guess `dragMoved` stayed true for the rest of the deal and
            // `onHold`'s `guard !dragMoved` silently ate every hold. That is the
            // "help sometimes shows and sometimes doesn't" bug (v5.83).
            defer { dragMoved = false }
            if scrubbing { scrubbing = false; scene.hideScrub() }
            defer { dragPile = nil; dragArmed = nil; scene.clearSwipeDirection(); scene.clearDragNudge() }
            guard let pile = dragPile else { return }
            if let armed = dragArmed {
                onTutorialEvent?(.swipeGuess)
                controller.guess(armed, pile: pile)
            } else if dragMoved {
                // Swiped but released in the dead-zone: cancel AND deselect —
                // the card must not stay armed after an aborted swipe.
                scene.setSelected(nil)
                controller.refreshAll()
            }
            // else: a plain tap — the tap recognizer owns selection.

        case .cancelled, .failed:
            if scrubbing { scrubbing = false; scene.hideScrub() }
            dragMoved = false
            dragPile = nil; dragArmed = nil; scene.clearSwipeDirection(); scene.clearDragNudge()

        default: break
        }
    }

    /// The guess a drag delta arms. Dominant axis decides: sideways (either
    /// way) = Same, up = Higher, down = Lower; inside the dead-zone = nil.
    /// Ported verbatim from `dirFromDelta`.
    static func direction(dx: CGFloat, dy: CGFloat) -> Guess? {
        let adx = abs(dx), ady = abs(dy)
        if max(adx, ady) < dragThreshold { return nil }   // dead-zone → cancel
        if adx > ady { return .same }                     // sideways = Same
        return dy > 0 ? .higher : .lower                  // up / down
    }

    // MARK: - Hold for help

    @objc private func onHold(_ g: UILongPressGestureRecognizer) {
        let p = scenePoint(g.location(in: view))
        switch g.state {
        case .began:
            // A hold that turned into a drag is a guess, not a help request —
            // and a hold DURING a histogram scrub must not pop the band help
            // over the bars the finger is reading.
            guard !dragMoved, !scrubbing else { return }
            // The top-bar chips take hold-help too (Same Charge, Same-Power,
            // the stage track, the reward/score line, score, coins).
            if let chip = scene.hudChip(at: p),
               let (title, body) = controller.helpText(forHUDChip: chip) {
                holdShown = true
                scene.showHelp(title: title, body: body)
            } else if let pile = scene.pileIndex(at: p), let (title, body) = controller.helpText(forPile: pile) {
                holdShown = true
                scene.showHelp(title: title, body: body)
            } else if let col = scene.pillarCol(at: p), let (title, body) = controller.helpText(forPillar: col) {
                holdShown = true
                scene.showHelp(title: title, body: body)
            } else if let col = scene.baseCol(at: p), let (title, body) = controller.helpText(forBase: col) {
                holdShown = true
                scene.showHelp(title: title, body: body)
            } else if let b = scene.button(at: p) {
                holdShown = true
                scene.showHelp(title: helpTitle(b.id), body: helpBody(b.id))
            } else if scene.isDeckPanel(p) {
                holdShown = true
                scene.showHelp(title: "Deck", body: "Cards left in the draw pile. Empty the deck before every pile dies to clear the deal. Tap for the full deck list.")
            } else if scene.isDeckBand(p) {
                holdShown = true
                scene.showHelp(title: "Deck tracker",
                               body: "What's left in the draw pile: the suit counts, and one bar per rank (grey = the deal's starting count, bright = still drawable). Hold and drag across the bars for the exact higher / same / lower odds of any rank.")
            }
        case .ended, .cancelled, .failed:
            if holdShown { scene.hideHelp(); holdShown = false }
        default: break
        }
    }

    private func helpTitle(_ id: String) -> String {
        switch id {
        case "fan": return "Fan"
        case "higher": return "Higher"
        case "same": return "Same"
        case "lower": return "Lower"
        case "reshuffle": return "Reshuffle"
        case "menu": return "Menu"
        default: return id
        }
    }

    private func helpBody(_ id: String) -> String {
        switch id {
        case "fan":    return "Fan: spreads every living pile so the cards underneath peek out, a reminder of what each pile is holding. Tap again to collapse. Pure memory aid: it changes nothing about the deal, and guessing stays live."
        case "higher": return "The next card is higher in rank. Ace is high; suits never matter."
        case "same":   return "The next card matches this rank. A correct Same banks a charge that saves your next miss."
        case "lower":  return "The next card is lower in rank. A tie kills on Higher or Lower."
        case "reshuffle": return "Gather every pile back into the deck and re-deal. Only before your first guess. In a climb it costs coins, more each time."
        case "menu":   return "Pause: leave the deal for the map or options. The deal waits exactly as you left it."
        default:       return ""
        }
    }
}

extension DealViewController: UIGestureRecognizerDelegate {
    public func gestureRecognizer(_ g: UIGestureRecognizer,
                                  shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        // The hold and the pan must coexist: a press that becomes a swipe is a
        // guess, and the hold's own `dragMoved` check suppresses the help.
        true
    }

    public func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // THE TUTORIAL-STUCK BUG: these recognizers live on the whole SKView,
        // and a recognized tap CANCELS touch delivery to any UIKit subview
        // (cancelsTouchesInView) — so the tutorial's NEXT button and the
        // prompt bar's Decline/Pay could never fire. The scene's own touches
        // hit the bare SKView; anything else is a UIKit overlay (tutorial
        // bubble, prompt bar, deck-inspect) and the recognizers must stay out.
        touch.view === view
    }
}
