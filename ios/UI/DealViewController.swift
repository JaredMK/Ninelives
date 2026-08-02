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
    private var pressedButton: PixelButton?
    private var holdShown = false
    /// The shared bottom prompt bar (offers, base confirms) over the SKView.
    private let promptBar = PromptBar()
    /// Piles armed as tap TARGETS (revive / Phoenix), with the answer callback.
    private var targetPick: (piles: [Int], answer: (Int?) -> Void)?

    /// Set by the launcher so a finished deal can pop back with its result.
    public var onExit: ((Bool, Int, Int) -> Void)?
    /// Campaign/Zen: the rich outcome, delivered after the end presentation.
    public var onOutcome: ((DealOutcome) -> Void)?
    public var onZenGuess: ((Bool) -> Void)?
    /// The corner menu button (campaign/zen only).
    public var onMenu: (() -> Void)?

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
                controller.onCheckpoint = { [weak self] _ in
                    guard let self, let c = self.sharedCampaign else { return }
                    PersistenceHolder.shared?.checkpoint(c)
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
            // `-demoOverlay fan|help` opens an overlay for a screenshot pass,
            // since simctl cannot deliver a real touch.
            if let demo = UserDefaults.standard.string(forKey: "demoOverlay") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
                    guard let self else { return }
                    if demo == "fan" {
                        if !self.scene.isFanHintOn { self.scene.toggleFanHint() }
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

    // MARK: - In-deal offers (PROMPT1: everything rides the shared bottom bar)

    private func wireOffers() {
        controller.onTributeOffer = { [weak self] offer, answer in
            guard let self else { answer(false); return }
            self.scene.setActionTargets([offer.index])
            self.promptBar.show(
                "\(offer.label) — bury \(offer.count) card\(offer.count == 1 ? "" : "s") under pile \(offer.index + 1)?",
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
            var targets = [action.index]
            if let t = action.target { targets.append(t) }
            self.scene.setActionTargets(targets)
            let text = action.kind == "donate"
                ? "Donate pile \(action.index + 1)'s bottom card to pile \((action.target ?? 0) + 1)?"
                : "Shuffle pile \(action.index + 1)'s cards?"
            self.promptBar.show(text, help: "Optional — Decline keeps things as they are.", actions: [
                .init("Decline", role: .plain) { [weak self] in
                    self?.promptBar.hide(); self?.clearTargets(); answer(false)
                },
                .init(action.kind == "donate" ? "Donate" : "Shuffle", role: .cta) { [weak self] in
                    self?.promptBar.hide(); self?.clearTargets(); answer(true)
                },
            ]) { [weak self] in self?.clearTargets(); answer(false) }
        }
        controller.onReviveOffer = { [weak self] dead, fire in
            guard let self else { fire(nil); return }
            self.armTargetPick(dead, prompt: "Revive — tap a dead pile to bring it back.", fire: fire)
        }
        controller.onBaseTarget = { [weak self] dead, fire in
            guard let self else { fire(nil); return }
            self.armTargetPick(dead, prompt: "Phoenix — tap a dead pile to revive it.", fire: fire)
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
    }

    private func armTargetPick(_ piles: [Int], prompt: String, fire: @escaping (Int?) -> Void) {
        targetPick = (piles, fire)
        scene.setActionTargets(piles)
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

    /// Card-counted best-move player: for every alive pile compute P(higher),
    /// P(lower), P(same) from the remaining rank counts; play the global max.
    private func startOddsPlayer() {
        Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] t in
            guard let self, let c = self.controller else { t.invalidate(); return }
            if c.isOver { t.invalidate(); return }
            guard !c.promptIsUp, !c.deckIsEmpty else { return }
            let counts = c.deckCounts()
            let total = max(1, counts.values.reduce(0, +))
            var best: (pile: Int, call: Guess, p: Double)?
            for pile in c.alivePiles() {
                guard let v = c.topValue(pile) else { continue }
                var higher = 0, lower = 0, same = 0
                for (rank, n) in counts {
                    if rank > v { higher += n }
                    else if rank < v { lower += n }
                    else { same += n }
                }
                // Ties kill directional guesses; jokers (value 0 slot) are free wins
                // either way, so the split above is the survival odds directly.
                let options: [(Guess, Double)] = [
                    (.higher, Double(higher) / Double(total)),
                    (.lower, Double(lower) / Double(total)),
                    (.same, Double(same) / Double(total)),
                ]
                for (g, p) in options where best == nil || p > best!.p {
                    best = (pile, g, p)
                }
            }
            guard let move = best else { t.invalidate(); return }
            self.scene.setSelected(move.pile)
            c.guess(move.call, pile: move.pile)
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
            if let pile = scene.pileIndex(at: p), tp.piles.contains(pile) {
                finishTargetPick(pile)
            }
            return
        }

        if let b = scene.button(at: p) {
            fire(button: b)
            return
        }
        // A charged Base plaque fires on tap.
        if let col = scene.baseCol(at: p) {
            Sound.shared.tap()
            controller.basePlaqueTapped(col: col)
            return
        }
        if let pile = scene.pileIndex(at: p) {
            // The fan hint is non-blocking: a tap still just selects the pile.
            controller.select(pile: pile)
            return
        }
        // Tap the deck stack → the full deck inspection (campaign/zen).
        if scene.isDeckPanel(p), sharedCampaign != nil {
            present(DeckInspectViewController(campaign: sharedCampaign!), animated: false)
            return
        }
        // A tap on empty felt clears the selection.
        scene.setSelected(nil)
        controller.refreshAll()
    }

    private func fire(button b: PixelButton) {
        guard b.isEnabled else { return }
        scene.press(b, down: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) { [weak self] in self?.scene.press(nil, down: false) }
        switch b.id {
        case "fan":       scene.toggleFanHint()
        case "higher":    controller.guess(.higher)
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
            if scene.isHelpVisible { return }
            dragPile = scene.pileIndex(at: p)
            dragArmed = nil
            dragMoved = false
            if let dp = dragPile { controller.select(pile: dp) }

        case .changed:
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
            defer { dragPile = nil; dragArmed = nil; scene.clearSwipeDirection(); scene.clearDragNudge() }
            guard let pile = dragPile else { return }
            // Release inside the dead-zone cancels: no guess, the pile stays selected.
            if let armed = dragArmed { controller.guess(armed, pile: pile) }

        case .cancelled, .failed:
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
            // A hold that turned into a drag is a guess, not a help request.
            guard !dragMoved else { return }
            if let pile = scene.pileIndex(at: p), let (title, body) = controller.helpText(forPile: pile) {
                holdShown = true
                scene.showHelp(title: title, body: body)
            } else if let b = scene.button(at: p) {
                holdShown = true
                scene.showHelp(title: helpTitle(b.id), body: helpBody(b.id))
            } else if scene.isDeckPanel(p) {
                holdShown = true
                scene.showHelp(title: "Deck", body: "Cards left in the draw pile. Empty the deck before every pile dies to clear the deal.")
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
        default: return id
        }
    }

    private func helpBody(_ id: String) -> String {
        switch id {
        case "fan":    return "Fan — spreads every living pile so the cards underneath peek out, a reminder of what each pile is holding. Tap again to collapse. Pure memory aid: it changes nothing about the deal, and guessing stays live."
        case "higher": return "The next card is higher in rank. Ace is high; suits never matter."
        case "same":   return "The next card matches this rank. A correct Same banks a charge that saves your next miss."
        case "lower":  return "The next card is lower in rank. A tie kills on Higher or Lower."
        case "reshuffle": return "Re-deal the piles from the same deck. Only before your first guess."
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
