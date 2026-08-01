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
    private var controller: DealController!
    private let setup: DealController.Setup

    private var dragPile: Int?
    private var dragArmed: Guess?
    private var dragMoved = false
    private var pressedButton: PixelButton?
    private var holdShown = false

    /// Set by the launcher so a finished deal can pop back with its result.
    public var onExit: ((Bool, Int, Int) -> Void)?

    public init(setup: DealController.Setup) {
        self.setup = setup
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
            controller = DealController(setup: setup, scene: scene)
            controller.onFinish = { [weak self] win, coins, score in
                guard let self else { return }
                // Let the banner play, then hand back to the launcher.
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
                    self.onExit?(win, coins, score)
                }
            }
            scene.showsFrameHUD = UserDefaults.standard.bool(forKey: "fps")
            skView.presentScene(scene)
            if UserDefaults.standard.bool(forKey: "autoPlay") { startAutoPlay() }
            // The slow variant keeps ANIMATIONS ON — the screenshot pass for
            // the travel/pulse/death motion (real autoPlay renders instantly).
            if UserDefaults.standard.bool(forKey: "autoPlaySlow") { startAutoPlay(interval: 1.1) }
            // `-demoOverlay fan|help` opens an overlay for a screenshot pass,
            // since simctl cannot deliver a real touch.
            if let demo = UserDefaults.standard.string(forKey: "demoOverlay") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
                    guard let self else { return }
                    if demo == "fan" {
                        self.scene.showPileFan(self.controller.pileCards(0), pile: 0)
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

    // MARK: - Coordinate conversion

    /// UIKit points → scene space (scene anchor is top-left, y negative down).
    private func scenePoint(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x, y: -p.y)
    }

    // MARK: - Tap

    @objc private func onTap(_ g: UITapGestureRecognizer) {
        let p = scenePoint(g.location(in: view))

        if scene.isPileFanOpen { scene.closePileFan(); return }
        if scene.isHelpVisible { scene.hideHelp(); return }

        if let b = scene.button(at: p) {
            fire(button: b)
            return
        }
        if let pile = scene.pileIndex(at: p) {
            // With the fan hint on, tapping a pile opens its FULL face-up fan.
            if scene.isFanHintOn {
                scene.showPileFan(controller.pileCards(pile), pile: pile)
            } else {
                controller.select(pile: pile)
            }
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
        default: break
        }
    }

    // MARK: - Swipe guessing

    @objc private func onPan(_ g: UIPanGestureRecognizer) {
        let p = scenePoint(g.location(in: view))
        switch g.state {
        case .began:
            if scene.isPileFanOpen || scene.isHelpVisible { return }
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
        case "fan":    return "Fan the piles out for a look at what is buried. Tap a pile while fanned to see all of its cards."
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
}
