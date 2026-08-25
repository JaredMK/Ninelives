import UIKit
import GameCore

/// The ONE build stamp (the web's APP_VERSION footer line) — every footer and
/// the debug panel read it here, never a retyped literal.
enum BuildStamp {
    static let version = "v6.78"
    static let note = "odds assist glows EVERY best call (inset strips, mute/magnet-aware); dynamic Rank Shield; live-most-common Transmute; Quick Bury fires on its own landing; Rank Roots; one-draw Second Sight; column-wide Diamond Boost; Fibonacci retired; endless payouts freeze at phase 3."
    static let line = "build \(version) · \(note)"
}

/// A shared base for the shell's menu-family screens: felt background, a
/// display-font title, a back button, content laid out top-down.
class MenuScreenBase: UIViewController {
    unowned let flow: GameFlowController
    let scroll = UIScrollView()
    let content = UIView()
    private let tissue = TissueView()
    private var y: CGFloat = 0

    init(flow: GameFlowController) {
        self.flow = flow
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override var prefersStatusBarHidden: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = CRT.feltDeep
        tissue.frame = view.bounds
        tissue.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(tissue)          // #tissue atmosphere under everything
        scroll.alwaysBounceVertical = true
        // The content frame already clears the safe area — without this the
        // automatic adjusted inset doubles the top offset and the whole block
        // sags ~60pt below the web's positions.
        scroll.contentInsetAdjustmentBehavior = .never
        view.addSubview(scroll)
        scroll.addSubview(content)
        installBackEdgeSwipe()
    }

    // ── `-splashFrame 1` (harness): bake the LAUNCH IMAGE source.
    // The static launch screen must look identical to the menu's first frame
    // (felt + tissue atmosphere, nothing else), so the boot hold reads as the
    // game already sitting there. This writes the same TissueView bake the
    // menu itself displays to Documents/splash-frame.png;
    // App/Assets.xcassets/LaunchBackdrop.imageset is regenerated from that
    // file whenever the atmosphere changes. The canvas is the LARGEST iPhone
    // point size: UILaunchScreen centres the image at intrinsic size, so an
    // oversized bake centre-CROPS on smaller phones instead of letterboxing
    // (the bake is 1x-per-point, exactly like the menu's own stretched bake).
    private var splashFrameWritten = false

    func writeSplashFrameIfAsked() {
        guard UserDefaults.standard.bool(forKey: "splashFrame"), !splashFrameWritten,
              view.bounds.width > 0 else { return }
        splashFrameWritten = true
        let canvas = CGSize(width: 440, height: 956)
        guard let png = TissueView.bake(size: canvas).pngData(),
              let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        else { return }
        try? png.write(to: dir.appendingPathComponent("splash-frame.png"))
        NSLog("[ShouldaSaidSame] splash frame written (%dx%d)", Int(canvas.width), Int(canvas.height))
    }

    /// Screens with a back control opt into the left-edge back swipe by
    /// overriding this. There is no UINavigationController anywhere in the app
    /// (screens are child-VC swaps), so the system pop gesture doesn't exist —
    /// this is the one place that behaviour comes from.
    var backGestureAction: (() -> Void)? { nil }

    /// THE corner ← control. Every menu-family screen puts back in the SAME
    /// place: top-left, just under the safe-area inset. Settings used to carry
    /// its back as a row in the button list instead, which made "back" mean two
    /// different gestures depending on which screen you were looking at.
    private(set) var cornerBack: PixelButtonView?

    func addCornerBack(_ action: @escaping () -> Void) {
        let b = PixelButtonView("←", role: .plain, fontSize: 20)
        b.onTap = action
        b.frame = CGRect(x: 8, y: 8, width: 48, height: 40)
        view.addSubview(b)
        cornerBack = b
    }

    /// The recognizer, exposed so a screen with its own horizontal swipes (the
    /// deck carousel) can make them yield to an edge drag.
    private(set) var backEdgePan: UIScreenEdgePanGestureRecognizer?

    private func installBackEdgeSwipe() {
        guard backGestureAction != nil else { return }
        let g = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(backEdgePanned))
        g.edges = .left
        view.addGestureRecognizer(g)
        backEdgePan = g
    }

    @objc private func backEdgePanned(_ g: UIScreenEdgePanGestureRecognizer) {
        guard g.state == .ended else { return }
        // Only a real leftward-to-rightward drag pops; a stalled touch doesn't.
        let t = g.translation(in: view), v = g.velocity(in: view)
        guard t.x > 40 || v.x > 320 else { return }
        backGestureAction?()
    }

    /// The web menu-family column is vertically CENTRED on the screen; opt in
    /// per screen (menu / settings / zen-select). Top-down screens (deck
    /// select, collection) keep the safe-area top anchor.
    var centersContentVertically: Bool { false }

    /// Top anchor for top-down screens. The web collection header rides at the
    /// very top of the screen (title at ~24pt, above the safe area), so the
    /// collection opts out of the safe-area anchor here.
    var contentTopInset: CGFloat { view.safeAreaInsets.top }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Web `.nav-btn`: the corner ← always sits just BELOW the safe area.
        cornerBack?.frame = CGRect(x: 8, y: view.safeAreaInsets.top + 4, width: 48, height: 40)
        tissue.frame = view.bounds
        scroll.frame = view.bounds
        content.transform = .identity
        // A screen that has turned scrolling OFF must show everything at once,
        // so its block SCALES to fit instead of overflowing. Uniform, so the
        // pixel grid stays square; only ever shrinks.
        var scale: CGFloat = 1
        if !scroll.isScrollEnabled {
            let avail = view.bounds.height - view.safeAreaInsets.top - view.safeAreaInsets.bottom - 16
            if y > avail, avail > 0 { scale = avail / y }
        }
        let shown = y * scale
        let top = centersContentVertically
            ? max(view.safeAreaInsets.top, (view.bounds.height - shown) / 2)
            : contentTopInset
        content.frame = CGRect(x: 0, y: top, width: view.bounds.width, height: y)
        if scale < 1 {
            content.transform = CGAffineTransform(scaleX: scale, y: scale)
            content.frame.origin = CGPoint(x: (view.bounds.width - view.bounds.width * scale) / 2, y: top)
        }
        scroll.contentSize = CGSize(width: view.bounds.width,
                                    height: shown + top + view.safeAreaInsets.bottom + 24)
    }

    // Layout helpers — every menu screen builds top-down through these.
    func resetLayout() {
        content.subviews.forEach { $0.removeFromSuperview() }
        y = 0
    }
    func addGap(_ g: CGFloat) { y += g }
    func addTitle(_ text: String, size: CGFloat = 16, color: UIColor = CRT.phosphor) {
        let l = CRTKit.label(text.uppercased(), size: size, color: color, display: true, glow: color == CRT.phosphor)
        l.textAlignment = .center
        l.frame = CGRect(x: 16, y: y, width: view.bounds.width - 32, height: size + 12)
        content.addSubview(l)
        y += size + 20
    }
    func addText(_ text: String, size: CGFloat = 14, color: UIColor = CRT.muted,
                 align: NSTextAlignment = .center) {
        let l = CRTKit.label(text, size: size, color: color)
        l.textAlignment = align
        let w = view.bounds.width - 48
        let h = ceil(l.attributedText!.boundingRect(with: CGSize(width: w, height: 600),
                                                    options: .usesLineFragmentOrigin, context: nil).height)
        l.frame = CGRect(x: 24, y: y, width: w, height: h)
        content.addSubview(l)
        y += h + 8
    }
    @discardableResult
    func addButton(_ title: String, role: PixelButtonView.Role = .plain, height: CGFloat = 56,
                   enabled: Bool = true, icon: UIImage? = nil,
                   handler: @escaping () -> Void) -> PixelButtonView {
        let b = PixelButtonView(title, role: role, fontSize: 20)
        b.isEnabled = enabled
        b.onTap = handler
        b.setIcon(icon)
        b.frame = CGRect(x: 46, y: y, width: view.bounds.width - 92, height: height)
        content.addSubview(b)
        y += height + 11
        return b
    }
    func addView(_ v: UIView, height: CGFloat) {
        v.frame = CGRect(x: 0, y: y, width: view.bounds.width, height: height)
        content.addSubview(v)
        y += height + 8
    }
    var layoutY: CGFloat { y }

    /// The subtle "debug toggled" signal (web: `body.debug-access` reveals the
    /// 🐞): the build footer flashes phosphor, then settles back to muted.
    func flashFooterPhosphor(_ label: UILabel) {
        let normal = label.attributedText
        label.attributedText = CRTKit.attributed(BuildStamp.line, size: 14, color: CRT.phosphor, glow: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak label] in
            label?.attributedText = normal
        }
    }
}

// MARK: - Main menu

final class MainMenuViewController: MenuScreenBase {
    private let canContinue: Bool
    /// THE ICON STRIP (v6.67): Settings · How to Play · Stats · Rankings as
    /// pixel-glyph buttons pinned along the screen bottom — the front door's
    /// rows are just CLIMB / ZEN / COLLECTION now. On `view`, not `content`:
    /// a fixed strip outside the centred menu column.
    private var iconStrip: [PixelButtonView] = []

    init(flow: GameFlowController, canContinue: Bool) {
        self.canContinue = canContinue
        super.init(flow: flow)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // The front door shows everything at once — no scrolling, no bounce.
        // MenuScreenBase scales the block down if a short phone needs it.
        scroll.isScrollEnabled = false
        scroll.alwaysBounceVertical = false
        build()
        buildIconStrip()
    }

    /// One square pixel-glyph button per doorway, in a fixed order. Icons are
    /// the game's own 8×8 marks (styleguide §3b: never a system glyph).
    private func buildIconStrip() {
        func iconButton(_ rows: [String], label: String, onTap: @escaping () -> Void) -> PixelButtonView {
            let b = PixelButtonView("", role: .plain, fontSize: 14)
            b.accessibilityLabel = label
            let icon = UIImageView(image: PixelGlyph.image(rows, color: CRT.cardFace, scale: 3))
            icon.contentMode = .center
            icon.layer.magnificationFilter = .nearest
            icon.isUserInteractionEnabled = false
            icon.frame = CGRect(x: 0, y: 0, width: 56, height: 48)
            b.addSubview(icon)
            b.onTap = onTap
            view.addSubview(b)
            return b
        }
        iconStrip = [
            iconButton(PixelGlyph.gear, label: "SETTINGS") { [weak self] in
                // A sheet over the menu (v6.68) — never a separate page.
                self?.flow.showSettings()
            },
            iconButton(PixelGlyph.question, label: "HOW TO PLAY") { [weak self] in
                guard let self else { return }
                // v6.67: the door launches the TUTORIAL (the old manual code
                // stays in showManual(), unused but kept deliberately).
                self.flow.prompt.show("Would you like to play the Zen tutorial?", actions: [
                    .init("Cancel", role: .plain) { self.flow.prompt.hide() },
                    .init("Play", role: .cta) {
                        self.flow.prompt.hide()
                        self.flow.tutorialReplayArmed = true
                        self.flow.startZen(diff: "easy")
                    },
                ]) { self.flow.prompt.hide() }
            },
            iconButton(PixelGlyph.bars, label: "STATS") { [weak self] in
                self?.flow.showStats()
            },
            iconButton(PixelGlyph.trophy, label: "RANKINGS") { [weak self] in
                guard let self, let board = Leaderboards.enabledBoards.sorted().first else { return }
                self.flow.gameCenter.presentLeaderboard(board, from: self.flow)
            },
        ]
    }

    // MARK: - Title sequence

    /// THE BOOT TITLE. Set by the flow for the FIRST menu after launch only.
    /// The jar/JarHead splash hands over to the menu's own felt, and the title
    /// builds itself a piece at a time before settling into the header.
    var playsIntro = false

    private weak var introTagline: UIView?
    private weak var introLogo: UIView?
    private var introWordmark: [UIView] = []
    private var introRest: [UIView] = []
    private var introRan = false
    /// "by" + the JarHead Labs mark, shown UNDER the wordmark for a beat
    /// before the menu arrives. Lives on `view`, not `content`, so it never
    /// disturbs the menu's own layout.
    private var introCredit: UIView?

    /// Run it once, AFTER the first real layout pass — the pieces animate from
    /// a staged offset back to `.identity`, so wherever the menu lays them out
    /// is exactly where they land. No duplicated layout, no drift.
    private func runIntroIfNeeded() {
        guard playsIntro, !introRan, view.bounds.width > 0 else { return }
        introRan = true
        let header = ([introTagline, introLogo] + introWordmark.map { Optional($0) }).compactMap { $0 }
        guard !header.isEmpty else { return }
        // Reduced motion gets the finished frame, not a light show.
        guard !UIAccessibility.isReduceMotionEnabled else { return }

        // Staged: the block sits a little low and a little large, like a title
        // card, then rises into its header position.
        let staged = CGAffineTransform(translationX: 0, y: 40).scaledBy(x: 1.14, y: 1.14)
        for v in header { v.alpha = 0; v.transform = staged }
        for v in introRest { v.alpha = 0 }
        for b in iconStrip { b.alpha = 0 }   // arrives with the buttons, not the title

        // One piece at a time: tagline, then the = mark, then the wordmark.
        flickerOn(introTagline, at: 0.20)
        flickerOn(introLogo, at: 0.75)
        for v in introWordmark { flickerOn(v, at: 1.30) }
        // …and "same" SWIVELS — a little side-to-side waggle, the word
        // mocking the player (it used to bob; the wag reads more like a
        // taunt). Only "same": juddering the whole wordmark read as the
        // screen glitching.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.62) { [weak self] in
            guard let self else { return }
            if let same = self.introWordmark.last { self.swivel(same, base: staged) }
        }
        // THE BYLINE: "by" + the JarHead Labs mark, under the finished title.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.30) { [weak self] in
            self?.showIntroCredit()
        }
        // Then the credit clears, the title settles into the real header, and
        // the menu takes its place.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.80) { [weak self] in
            guard let self else { return }
            UIView.animate(withDuration: 0.28) {
                self.introCredit?.alpha = 0
            } completion: { _ in
                self.introCredit?.removeFromSuperview()
                self.introCredit = nil
            }
            UIView.animate(withDuration: 0.42, delay: 0.12, usingSpringWithDamping: 0.78,
                           initialSpringVelocity: 0.5) {
                for v in header { v.transform = .identity }
            }
            UIView.animate(withDuration: 0.34, delay: 0.34, options: [.curveEaseOut]) {
                for v in self.introRest { v.alpha = 1 }
                for b in self.iconStrip { b.alpha = 1 }
            }
        }
    }

    /// The byline, built where the wordmark currently sits (transform included,
    /// so it tracks the staged title rather than the final header).
    private func showIntroCredit() {
        guard let anchor = introWordmark.last, let parent = anchor.superview else { return }
        let below = parent.convert(anchor.frame, to: view).maxY
        // The credit is the second thing on this screen, not a footnote — it
        // was set at footer scale and read as one.
        let box = UIView(frame: CGRect(x: 0, y: below + 30, width: view.bounds.width, height: 232))
        box.alpha = 0
        let by = CRTKit.label("by", size: 22, color: CRT.cardFace)
        by.textAlignment = .center
        by.frame = CGRect(x: 0, y: 0, width: box.bounds.width, height: 26)
        box.addSubview(by)
        if let logo = UIImage(named: "LaunchLogo") {
            let iv = UIImageView(image: logo)
            iv.contentMode = .scaleAspectFit
            iv.layer.magnificationFilter = .nearest
            let w: CGFloat = 244
            iv.frame = CGRect(x: (box.bounds.width - w) / 2, y: 36, width: w, height: 170)
            box.addSubview(iv)
        } else {
            let name = CRTKit.label("JARHEAD LABS", size: 30, color: CRT.gold, display: true)
            name.textAlignment = .center
            name.frame = CGRect(x: 0, y: 44, width: box.bounds.width, height: 38)
            box.addSubview(name)
        }
        view.addSubview(box)
        introCredit = box
        UIView.animate(withDuration: 0.34, delay: 0, options: [.curveEaseOut]) { box.alpha = 1 }
    }

    /// A CRT power-on: the piece stutters alight rather than fading in.
    private func flickerOn(_ v: UIView?, at delay: TimeInterval) {
        guard let v else { return }
        UIView.animateKeyframes(withDuration: 0.30, delay: delay, options: [.calculationModeDiscrete]) {
            UIView.addKeyframe(withRelativeStartTime: 0.00, relativeDuration: 0.2) { v.alpha = 1 }
            UIView.addKeyframe(withRelativeStartTime: 0.20, relativeDuration: 0.2) { v.alpha = 0.15 }
            UIView.addKeyframe(withRelativeStartTime: 0.40, relativeDuration: 0.2) { v.alpha = 1 }
            UIView.addKeyframe(withRelativeStartTime: 0.60, relativeDuration: 0.2) { v.alpha = 0.45 }
            UIView.addKeyframe(withRelativeStartTime: 0.80, relativeDuration: 0.2) { v.alpha = 1 }
        }
    }

    /// The 8-bit taunt: WHOLE-frame rotation steps with no interpolation
    /// (discrete keyframes), so "same" wags side to side like a sprite
    /// flipping between two mocking frames — never a smooth tween.
    private func swivel(_ v: UIView, base: CGAffineTransform) {
        let steps: [CGFloat] = [-0.10, 0.09, -0.12, 0.09, -0.06, 0.04, 0]
        UIView.animateKeyframes(withDuration: 0.84, delay: 0, options: [.calculationModeDiscrete]) {
            for (i, angle) in steps.enumerated() {
                UIView.addKeyframe(withRelativeStartTime: Double(i) / Double(steps.count),
                                   relativeDuration: 1.0 / Double(steps.count)) {
                    v.transform = base.rotated(by: angle)
                }
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // The icon strip: centred row of squares just above the home bar.
        let side: CGFloat = 56, gap: CGFloat = 18
        let total = CGFloat(iconStrip.count) * side + CGFloat(max(0, iconStrip.count - 1)) * gap
        let x0 = (view.bounds.width - total) / 2
        let y = view.bounds.height - view.safeAreaInsets.bottom - side - 10
        for (i, b) in iconStrip.enumerated() {
            b.frame = CGRect(x: x0 + CGFloat(i) * (side + gap), y: y, width: side, height: 48)
        }
        writeSplashFrameIfAsked()
        runIntroIfNeeded()
    }


    override var centersContentVertically: Bool { true }

    private func build() {
        resetLayout()
        // The web menu, top to bottom: tagline · the gold "=" mark · the
        // two-line mixed-case wordmark · iconed buttons · the build footer.
        // The whole block is vertically centred (centersContentVertically);
        // the gaps below are the web's INTERNAL rhythm (measured on the
        // captures: tagline→logo 82pt, logo→wordmark 82pt, buttons 57pt).
        addText("HIGHER OR LOWER?", size: 14, color: CRT.cardFace)
        let tag = content.subviews.last as? UILabel
        introTagline = tag
        tag?.attributedText = CRTKit.attributed("HIGHER OR LOWER?", size: 14, color: CRT.cardFace, display: true)
        tag?.textAlignment = .center
        // The gaps pay for the bigger type: the web's generous rhythm doesn't
        // survive 19pt buttons on a phone without either scrolling (now off)
        // or scaling the whole block down.
        addGap(26)
        let logo = UIImageView(image: MapArt.menuLogo(width: 64))
        logo.layer.magnificationFilter = .nearest
        logo.contentMode = .scaleAspectFit
        let holder = UIView()
        logo.frame = CGRect(x: (view.bounds.width - 64) / 2, y: 0, width: 64, height: 40)
        holder.addSubview(logo)
        addView(holder, height: 46)
        introLogo = holder
        addGap(22)
        let line1 = CRTKit.label("Shoulda said", size: 28, color: CRT.cardFace, display: true)
        line1.textAlignment = .center
        let w1 = wrapCentered(line1)
        addView(w1, height: 36)
        let line2 = CRTKit.label("same", size: 28, color: CRT.phosphor, display: true, glow: true)
        line2.textAlignment = .center
        let w2 = wrapCentered(line2)
        addView(w2, height: 36)
        introWordmark = [w1, w2]
        // Everything added from here down (buttons, footer) waits for the
        // title sequence to finish.
        let headerCount = content.subviews.count
        defer { introRest = Array(content.subviews.dropFirst(headerCount)) }
        addGap(22)

        // THE FRONT DOOR (v6.67): exactly three rows — CLIMB, ZEN, COLLECTION.
        // Settings / How to Play / Stats / Rankings live in the icon strip
        // pinned along the screen bottom (built once in viewDidLoad).
        let campaignOpen = flow.campaignUnlocked()
        if campaignOpen {
            addButton("CLIMB", role: .cta) { [weak self] in
                guard let self else { return }
                if self.canContinue {
                    // One row serves both: resume the save, or burn it for a
                    // fresh climb — the choice rides the prompt bar.
                    self.flow.prompt.show("Continue your saved climb?",
                                          help: "NEW CLIMB starts over. The saved climb is lost.",
                                          actions: [
                        .init("Continue", role: .cta) {
                            self.flow.prompt.hide()
                            self.resumeSave()
                        },
                        .init("New climb", role: .danger) {
                            self.flow.prompt.hide()
                            self.flow.clearSave()
                            self.flow.showDeckSelect()
                        },
                    ]) { self.flow.prompt.hide() }
                } else {
                    self.flow.showDeckSelect()
                }
            }
        }
        // ZEN is a standard menu row, first open included — the phosphor CTA
        // role is reserved for CLIMB (styleguide: phosphor is "CTAs,
        // highlights, score", and the front door's one CTA is the climb).
        addButton("ZEN", role: .plain) { [weak self] in
            self?.flow.showZenSelect()
        }
        addButton("COLLECTION") { [weak self] in self?.flow.showCollection() }
        // Debug has no menu row: the 🐞 button in the bottom-right corner is
        // the single entry point once 7 footer taps unlock access.
        addGap(20)
        // Footer: the web's exact build line ("build " + APP_VERSION) — small,
        // muted, centred, wrapping to two lines right under the last button.
        // 7 quick taps toggle debug access (the web's wireVersionTapDebug).
        let foot = CRTKit.label(BuildStamp.line, size: 14, color: CRT.muted)
        foot.textAlignment = .center
        foot.numberOfLines = 2
        foot.alpha = 0.6              // web .menu-foot opacity
        foot.frame = CGRect(x: 24, y: layoutY, width: view.bounds.width - 48, height: 30)
        foot.isUserInteractionEnabled = true
        foot.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(buildFooterTapped)))
        content.addSubview(foot)
        buildFoot = foot
        addGap(38)
        view.setNeedsLayout()
    }

    private weak var buildFoot: UILabel?

    /// 7 quick footer taps toggle debug access (GameFlowController counts);
    /// on the toggle the menu rebuilds (the DEBUG button appears/disappears)
    /// and the fresh footer flashes phosphor.
    @objc private func buildFooterTapped() {
        guard flow.noteFooterTap() else { return }
        build()
        if let f = buildFoot { flashFooterPhosphor(f) }
    }

    private func wrapCentered(_ l: UILabel) -> UIView {
        let v = UIView()
        l.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: 30)
        v.addSubview(l)
        return v
    }

    private func resumeSave() {
        // Re-enter through the boot path so the phase routing is shared.
        flow.resumeFromMenu()
    }

    /// The old HOW TO PLAY instruction sheet. UNWIRED in v6.67 (the front-door
    /// icon launches the Zen tutorial instead) but kept deliberately — it may
    /// come back.
    private func showManual() {
        flow.showManualSheet()
    }
}

// MARK: - Settings

/// SOUND + RESET live under SETTINGS (the web tucks them off the main menu).
/// UNWIRED in v6.68 (batch 2.3): Settings opens as SettingsSheetView now —
/// this full-page screen is kept deliberately (it may come back) but nothing
/// navigates here.
final class SettingsViewController: MenuScreenBase {
    /// Left-edge swipe = the ← control.
    override var backGestureAction: (() -> Void)? { { [weak self] in self?.flow.showMenu() } }

    override func viewDidLoad() {
        super.viewDidLoad()
        addCornerBack { [weak self] in self?.flow.showMenu() }
        build()
    }

    override var centersContentVertically: Bool { true }

    private func build() {
        resetLayout()
        // The header block at the MAIN MENU's exact sizes and rhythm (v6.67,
        // batch item 9): tagline 14 → gap 26 → 64pt logo → gap 22 → wordmark
        // at 28pt in 36pt rows — the two screens used to disagree (24pt lines,
        // 46/39/27 gaps) and the mark visibly jumped between them.
        addText("HIGHER OR LOWER?", size: 14, color: CRT.cardFace)
        addGap(26)
        let logo = UIImageView(image: MapArt.menuLogo(width: 64))
        logo.layer.magnificationFilter = .nearest
        logo.contentMode = .scaleAspectFit
        let holder = UIView()
        logo.frame = CGRect(x: (view.bounds.width - 64) / 2, y: 0, width: 64, height: 40)
        holder.addSubview(logo)
        addView(holder, height: 46)
        addGap(22)
        let line1 = CRTKit.label("Shoulda said", size: 28, color: CRT.cardFace, display: true)
        line1.textAlignment = .center
        line1.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: 36)
        let w1 = UIView(); w1.addSubview(line1)
        addView(w1, height: 36)
        let line2 = CRTKit.label("same", size: 28, color: CRT.phosphor, display: true, glow: true)
        line2.textAlignment = .center
        line2.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: 36)
        let w2 = UIView(); w2.addSubview(line2)
        addView(w2, height: 36)
        addGap(22)
        addButton("SOUND: \(Sound.shared.enabled ? "ON" : "OFF")") { [weak self] in
            Sound.shared.enabled.toggle()
            self?.build()
        }
        // (STATS left Settings in v6.67 — it has its own front-door icon now.)
        addButton("RESET PROGRESS", role: .danger) { [weak self] in
            self?.confirmReset()
        }
        addGap(20)
        // The web's exact build line (same stamp as the main menu footer) —
        // 7 quick taps toggle debug access here too (both web footers wire it).
        let foot = CRTKit.label(BuildStamp.line, size: 14, color: CRT.muted)
        foot.textAlignment = .center
        foot.numberOfLines = 2
        foot.alpha = 0.6
        foot.frame = CGRect(x: 24, y: layoutY, width: view.bounds.width - 48, height: 30)
        foot.isUserInteractionEnabled = true
        foot.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(buildFooterTapped)))
        content.addSubview(foot)
        buildFoot = foot
        addGap(38)
        view.setNeedsLayout()
    }

    private weak var buildFoot: UILabel?

    @objc private func buildFooterTapped() {
        guard flow.noteFooterTap() else { return }
        if let f = buildFoot { flashFooterPhosphor(f) }
    }

    /// Double-confirmed through the shared bar — the web's destructive idiom
    /// (index.html:31645-31653 chains two showMenuConfirms, both commits
    /// phosphor .primary). Nothing but the sound pref survives.
    private func confirmReset() {
        flow.prompt.show("Reset ALL progress?",
                         help: "Campaign, decks, unlocks, stats and the tutorial are wiped. Only the sound setting survives.",
                         actions: [
            .init("Cancel", role: .plain) { [weak self] in self?.flow.prompt.hide() },
            .init("Reset", role: .cta) { [weak self] in self?.confirmResetFinal() },
        ]) { [weak self] in self?.flow.prompt.hide() }
    }

    private func confirmResetFinal() {
        flow.prompt.show("Really erase everything?",
                         help: "The campaign, decks, unlocks, stats and tutorial all reset. This can't be undone.",
                         actions: [
            .init("Cancel", role: .plain) { [weak self] in self?.flow.prompt.hide() },
            .init("Erase everything", role: .cta) { [weak self] in
                guard let self else { return }
                self.flow.prompt.hide()
                self.flow.resetAllProgress()
            },
        ]) { [weak self] in self?.flow.prompt.hide() }
    }
}

// MARK: - Deck select

final class DeckSelectViewController: MenuScreenBase {
    /// Left-edge swipe = the ← control.
    override var backGestureAction: (() -> Void)? { { [weak self] in self?.flow.showMenu() } }

    private var deckIndex = 0
    private var tierIndex = 0
    private let tiers = DifficultyData.tierIds
    private var seedField: UITextField?
    private var seedNote: UILabel?
    private var startButton: PixelButtonView?
    private let backButton = PixelButtonView("←", role: .plain, fontSize: 20)

    private func seedFieldText() -> String {
        (seedField?.text ?? "").trimmingCharacters(in: .whitespaces)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Web #deckSelect is a FIXED screen (the carousel is touch-action:
        // pan-x) — kill the inherited menu scroll's vertical drag/bounce.
        scroll.isScrollEnabled = false
        scroll.alwaysBounceVertical = false
        // A tap anywhere OFF the seed field puts the keyboard away — the
        // recognizer never cancels the touch, so buttons still fire.
        let dismiss = UITapGestureRecognizer(target: self, action: #selector(tapAnywhere))
        dismiss.cancelsTouchesInView = false
        view.addGestureRecognizer(dismiss)
        // Keyboard avoidance for the seed field: the screen LIFTS by the
        // covered amount while typing, and settles back on dismiss.
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow(_:)),
                                               name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide),
                                               name: UIResponder.keyboardWillHideNotification, object: nil)
        // Always open on PINKY. Landing on the furthest unlocked deck meant a
        // veteran never saw the starter character without swiping back.
        deckIndex = 0
        // The corner back arrow + a swipe carousel, like the web.
        backButton.onTap = { [weak self] in self?.flow.showMenu() }
        backButton.frame = CGRect(x: 8, y: 8, width: 48, height: 40)  // real y: viewDidLayoutSubviews
        view.addSubview(backButton)
        let left = UISwipeGestureRecognizer(target: self, action: #selector(swipeLeft))
        left.direction = .left
        view.addGestureRecognizer(left)
        let right = UISwipeGestureRecognizer(target: self, action: #selector(swipeRight))
        right.direction = .right
        view.addGestureRecognizer(right)
        // A drag that STARTS at the left edge means "go back", not "previous
        // deck" — the carousel yields to it.
        if let edge = backEdgePan { right.require(toFail: edge) }
        build()
    }

    @objc private func swipeLeft() { cycleDeck(1) }
    @objc private func swipeRight() { cycleDeck(-1) }

    private func deckUnlocked(_ d: GameFlowController.DeckInfo) -> Bool {
        guard let req = d.requires else { return true }
        return flow.campaign.deckUnlocks.wonWith(req)
    }

    private func tierUnlocked(_ tier: String, deck: GameFlowController.DeckInfo) -> Bool {
        switch tier {
        // Legendary opens on the deck's NORMAL win (the Master rung is retired).
        case "legendary": return flow.campaign.deckUnlocks.wonWithTier(deck.id, "regular")
        default: return true
        }
    }

    // MARK: - Layout (v6.46 "Marquee")

    private var seedExpanded = false
    /// One-shot: the keyboard may appear ONLY on a direct tap of the seed
    /// affordance. Rebuilds (tier taps, deck swipes) must never re-summon it
    /// just because the expanded field happens to be empty.
    private var seedWantsFocus = false
    /// True during a MEASURING pass (EXACTFIT1) — a throwaway build must
    /// neither consume `seedWantsFocus` nor focus a field it's discarding.
    private var seedSuppressFocus = false

    /// Shared: the deck art + lock state for the current selection.
    private func heroImage(_ d: GameFlowController.DeckInfo, unlocked: Bool, scale: Int) -> UIImage {
        let beatenHere = flow.campaign.deckUnlocks.wonWithTier(d.id, tiers[tierIndex])
        let art = DeckCharacter.image(deckId: d.id, mood: beatenHere ? .idle : .sad,
                                      scale: scale, tier: tiers[tierIndex])
        return unlocked ? art : CollectionViewController.silhouette(art)
    }

    private func addPagerDots() {
        dotsRow?.removeFromSuperview()
        let dots = UIView()
        for (i, _) in GameFlowController.decks.enumerated() {
            let dot = UIView(frame: CGRect(x: view.bounds.width / 2 - 30 + CGFloat(i) * 16, y: 0, width: 8, height: 8))
            dot.backgroundColor = i == deckIndex ? CRT.phosphor : CRT.feltMid
            dot.layer.borderWidth = 1
            dot.layer.borderColor = CRT.ink.cgColor
            dot.layer.cornerRadius = 4   // the sanctioned pager-dot circle
            if i == deckIndex { dot.transform = CGAffineTransform(scaleX: 1.25, y: 1.25) }
            dots.addSubview(dot)
        }
        view.addSubview(dots)
        dotsRow = dots
        positionPager()
        view.setNeedsLayout()
    }

    /// Shared: the seed affordance as a SECONDARY, collapsed-by-default row.
    /// Collapsed: one dim caption link. Expanded: the field + live note. The
    /// exhibition warning lives INSIDE the expanded block, so the resting
    /// screen carries no fine print at all.
    private func addSeedAffordance() {
        let keptSeed = seedFieldText()
        if !keptSeed.isEmpty { seedExpanded = true }
        guard seedExpanded else {
            let link = PixelButtonView("HAVE A SEED?", role: .plain, fontSize: 14)
            link.onTap = { [weak self] in
                self?.seedExpanded = true
                self?.seedWantsFocus = true
                self?.build()
            }
            link.frame = CGRect(x: (view.bounds.width - 170) / 2, y: layoutY, width: 170, height: 34)
            content.addSubview(link)
            addGap(38)
            return
        }
        let seedPanel = PixelPanelView(face: CRT.feltMid, border: CRT.ink)
        let field = UITextField()
        field.font = CRT.Font.of(18)
        field.textColor = CRT.gold
        field.autocapitalizationType = .allCharacters
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.attributedPlaceholder = CRTKit.attributed("ABC2345", size: 16, color: CRT.disabledText)
        field.textAlignment = .center
        field.addTarget(self, action: #selector(seedEdited), for: .editingChanged)
        field.frame = CGRect(x: 10, y: 6, width: view.bounds.width - 160 - 20, height: 30)
        field.text = keptSeed
        seedPanel.addSubview(field)
        seedField = field
        seedPanel.frame = CGRect(x: 80, y: layoutY, width: view.bounds.width - 160, height: 42)
        content.addSubview(seedPanel)
        addGap(48)
        let note = CRTKit.label("", size: 14, color: CRT.muted)
        note.textAlignment = .center
        note.frame = CGRect(x: 24, y: layoutY, width: view.bounds.width - 48, height: 16)
        content.addSubview(note)
        seedNote = note
        updateSeedNote()
        addGap(20)
        addText("Seeded climbs are exhibitions. No records, no unlocks.", size: 14)
        if seedWantsFocus, !seedSuppressFocus {
            seedWantsFocus = false
            field.becomeFirstResponder()
        }
    }

    /// THE deck-select layout (v6.46 "Marquee" redesign): hero on top under
    /// the title with carousel arrows, identity block, arcade BEST readout,
    /// two big tier chips carrying pixel-art marks, a full-width START, seed
    /// collapsed below. Structural gaps are computed from the screen height,
    /// so the composition fills the full screen with deliberate rhythm
    /// instead of pooling low.
    /// SAFEINSET1 + EXACTFIT1: the screen must (a) always be built against
    /// the REAL safe-area insets — viewDidLoad runs with zeros, and seams
    /// baked from them put the title in the Dynamic Island — and (b) fit
    /// `avail` EXACTLY. A hand-kept height budget drifted 48pt once, which
    /// silently engaged the base class's scale-to-fit transform; the old
    /// whole-page carousel slide then stomped that transform to identity,
    /// growing the content around its centre and shoving the title into the
    /// island after every swipe. So: pass 1 builds with floor seams to
    /// MEASURE the natural height, pass 2 distributes the true leftover —
    /// content height == avail, the scale branch never engages. (v6.57: the
    /// swipe now animates the sprite alone and never touches `content`'s
    /// transform — but the exact fit still keeps the scale branch dormant.)
    private func build() {
        builtInsetSignature = currentInsetSignature()
        // The bottom margin RESERVES the pager-dot band: the dots pin to the
        // screen bottom outside the content flow (positionPager), so the
        // content must stop clear of them — 30pt left them touching the seed
        // affordance's shadow on every device (v6.49 bugfix).
        let avail = view.bounds.height - view.safeAreaInsets.top - view.safeAreaInsets.bottom - 54
        buildPass(slack: 0, measuring: true)
        let trueFixed = layoutY - CGFloat(Self.seamShares.count) * 8   // strip the floor seams
        var slack = max(0, avail - trueFixed)
        buildPass(slack: slack, measuring: false)
        // Tiny screens: a seam pinned at its 8pt floor can overshoot — take
        // the overshoot back out of the slack once.
        if layoutY > avail, slack > 0 {
            slack = max(0, slack - (layoutY - avail))
            buildPass(slack: slack, measuring: false)
        }
    }

    /// The section-seam shares, in build order (they sum to 1.0).
    private static let seamShares: [CGFloat] = [0.16, 0.10, 0.22, 0.32, 0.20]

    private func buildPass(slack: CGFloat, measuring: Bool) {
        resetLayout()
        let d = GameFlowController.decks[deckIndex]
        let unlocked = deckUnlocked(d)
        let W = view.bounds.width
        var seamIndex = 0
        func seam(_ share: CGFloat) {
            _ = seamIndex; seamIndex += 1
            addGap(max(8, slack * share))
        }
        self.seedSuppressFocus = measuring

        // Below the corner ← row (v6.67, batch item 15): the title used to
        // sit at the button's height and read as one crowded line with it.
        addGap(50)
        addTitle("CHOOSE YOUR DECK", size: 16)
        seam(0.16)

        // HERO: the character at 5× with the carousel arrows beside it.
        let hero = UIView()
        let sprite = UIImageView(image: heroImage(d, unlocked: unlocked, scale: 5))
        sprite.contentMode = .scaleAspectFit
        sprite.layer.magnificationFilter = .nearest
        sprite.alpha = unlocked ? 1 : 0.72
        sprite.frame = CGRect(x: (W - 160) / 2, y: 0, width: 160, height: 160)
        sprite.tag = 777
        hero.addSubview(sprite)
        if !unlocked {
            let q = CRTKit.label("?", size: 40, color: CRT.muted, display: true)
            q.textAlignment = .center
            q.frame = CGRect(x: (W - 60) / 2, y: 52, width: 60, height: 56)
            hero.addSubview(q)
        }
        let prev = PixelButtonView("‹", role: .plain, fontSize: 22)
        prev.onTap = { [weak self] in self?.cycleDeck(-1) }
        prev.frame = CGRect(x: 22, y: 58, width: 44, height: 44)
        hero.addSubview(prev)
        let next = PixelButtonView("›", role: .plain, fontSize: 22)
        next.onTap = { [weak self] in self?.cycleDeck(1) }
        next.frame = CGRect(x: W - 66, y: 58, width: 44, height: 44)
        hero.addSubview(next)
        addView(hero, height: 168)
        seam(0.10)

        // IDENTITY: name + mission at reading sizes.
        let name = CRTKit.label(unlocked ? d.name : "???", size: 26,
                                color: unlocked ? CRT.cardFace : CRT.muted, display: true)
        name.textAlignment = .center
        name.frame = CGRect(x: 0, y: 0, width: W, height: 32)
        let nw = UIView(); nw.addSubview(name)
        addView(nw, height: 34)
        addGap(4)
        let prevUnlocked = deckIndex == 0 || deckUnlocked(GameFlowController.decks[deckIndex - 1])
        addText(unlocked ? d.sub : (prevUnlocked ? (d.unlockNote ?? "Locked") : "???"),
                size: 16, color: unlocked ? CRT.cardFace : CRT.muted)
        addGap(10)
        // HIGH SCORE: the ARCADE readout — the game-over screen's score
        // treatment (tracked caps label over a big glowing numeral). ONE
        // number (v6.47): the score is a single continuous run total, endless
        // included, so there is exactly one record per deck+tier. Always
        // reserved, so START never shifts between decks; hidden entirely
        // until the combo has recorded a score.
        let bestRow = UIView()
        if unlocked, let best = flow.campaign.stats.get().deckTierBest["\(d.id).\(tiers[tierIndex])"] {
            let cap = UILabel()
            cap.attributedText = NSAttributedString(
                string: "HIGH SCORE",
                attributes: [.font: CRT.Font.of(14, display: true),
                             .foregroundColor: CRT.muted, .kern: 3])
            cap.textAlignment = .center
            cap.frame = CGRect(x: 0, y: 0, width: W, height: 18)
            bestRow.addSubview(cap)
            let num = CRTKit.label("\(best)", size: 34, color: CRT.phosphor,
                                   display: true, glow: true)
            num.textAlignment = .center
            num.frame = CGRect(x: 0, y: 22, width: W, height: 38)
            bestRow.addSubview(num)
        }
        addView(bestRow, height: 62)
        seam(0.22)

        // TIERS: two big chips, pixel-art marks (styleguide §3b: no system
        // glyphs) — gold check cleared, dim cross uncleared, padlock locked.
        let tierRow = UIView()
        let tw: CGFloat = 150
        let rowW = CGFloat(tiers.count) * tw + CGFloat(tiers.count - 1) * 14
        let tierX0 = (W - rowW) / 2
        for (i, t) in tiers.enumerated() {
            let open = unlocked && tierUnlocked(t, deck: d)
            let won = flow.campaign.deckUnlocks.wonWithTier(d.id, t)
            let chip = PixelButtonView("", role: i == tierIndex ? .charged : .plain, fontSize: 14)
            chip.isEnabled = open
            chip.accessibilityLabel = t.uppercased()
            chip.onTap = { [weak self] in
                self?.tierIndex = i
                self?.build()
            }
            chip.frame = CGRect(x: tierX0 + CGFloat(i) * (tw + 14), y: 0, width: tw, height: 100)
            tierRow.addSubview(chip)
            let tl = CRTKit.label(GameData.shared.difficulty.tier(t).label, size: 18,
                                  color: open ? CRT.cardFace : CRT.disabledText)
            tl.textAlignment = .center
            tl.frame = CGRect(x: 0, y: 10, width: tw, height: 22)
            tl.isUserInteractionEnabled = false
            chip.addSubview(tl)
            // Marks: gold check = cleared; empty ring = the slot a check will
            // fill; padlock = locked. Never a system glyph (styleguide §3b).
            let markImg = !open ? PixelGlyph.lockImage() : (won ? PixelGlyph.checkImage() : PixelGlyph.ringImage())
            let mark = UIImageView(image: markImg)
            mark.layer.magnificationFilter = .nearest
            mark.contentMode = .center
            mark.frame = CGRect(x: 0, y: 38, width: tw, height: 30)
            mark.isUserInteractionEnabled = false
            chip.addSubview(mark)
            let subText = !open ? "Beat " + GameData.shared.difficulty.tier(tiers[max(0, i - 1)]).label
                                : (won ? "Cleared" : "Not yet")
            let sub = CRTKit.label(subText, size: 14, color: open ? CRT.muted : CRT.disabledText)
            sub.textAlignment = .center
            sub.frame = CGRect(x: 0, y: 72, width: tw, height: 16)
            sub.isUserInteractionEnabled = false
            chip.addSubview(sub)
        }
        addView(tierRow, height: 100)
        seam(0.32)

        // START: the menu-family full-width CTA.
        let start = PixelButtonView(seedFieldText().isEmpty ? "START CLIMB" : "START SEEDED CLIMB",
                                    role: .cta, fontSize: 20)
        startButton = start
        start.isEnabled = unlocked && tierUnlocked(tiers[tierIndex], deck: d)
        start.onTap = { [weak self] in self?.startClimb() }
        start.frame = CGRect(x: 46, y: layoutY, width: W - 92, height: 58)
        content.addSubview(start)
        addGap(58 + 12)
        seam(0.20)
        addSeedAffordance()
        addPagerDots()
    }

    private var dotsRow: UIView?

    private func positionPager() {
        let w = view.bounds.width, h = view.bounds.height
        guard w > 0, h > 0 else { return }
        // Below the exhibition sentence, above the home indicator.
        dotsRow?.frame = CGRect(x: 0, y: h - max(view.safeAreaInsets.bottom, 12) - 14,
                                width: w, height: 8)
    }

    /// The safe-area signature the CONTENT was last built against. The
    /// structural seams are computed from the insets at build() time, and
    /// viewDidLoad runs with insets 0 — so the first build is laid out for a
    /// notchless screen and the title rides into the Dynamic Island until
    /// something forces a rebuild (which is why a tier tap used to "fix" it).
    /// SAFEINSET1: the same class of bug as the earlier nav-button one — any
    /// value BAKED at build time from `safeAreaInsets` must rebuild when the
    /// real insets arrive. (The base class only repositions; it cannot know
    /// the seams are stale.) Swept the other menu screens: deck select is the
    /// only one that bakes insets into content — the rest read them live.
    private var builtInsetSignature: CGFloat = -1
    private func currentInsetSignature() -> CGFloat {
        view.safeAreaInsets.top * 1000 + view.safeAreaInsets.bottom
    }

    override func viewDidLayoutSubviews() {
        // Rebuild BEFORE super positions the content, so the first rendered
        // frame is already the final layout — no shift, ever.
        if builtInsetSignature != currentInsetSignature() {
            build()
        }
        super.viewDidLayoutSubviews()
        // Web .nav-btn: always just BELOW the safe-area inset (insets are 0
        // at viewDidLoad, so the floating buttons land here).
        backButton.frame = CGRect(x: 8, y: view.safeAreaInsets.top + 4, width: 48, height: 40)
        positionPager()
    }

    /// Web: the input is maxlength=7 — the SeedCode alphabet is 7 chars — so
    /// typing past the code truncates (and uppercases) on the spot.
    /// How far the screen is LIFTED so the seed field clears the keyboard.
    /// Rides `contentTopInset`, so the base layout applies it on every pass —
    /// a transform got silently flattened by the container's layout.
    private var keyboardLift: CGFloat = 0
    override var contentTopInset: CGFloat { super.contentTopInset - keyboardLift }

    @objc private func tapAnywhere(_ g: UITapGestureRecognizer) {
        guard let field = seedField, field.isFirstResponder else { return }
        guard !field.bounds.contains(g.location(in: field)) else { return }
        // THE FIRST TAP ACTS (v6.68, batch 5.5): tapping START with the
        // keyboard up used to only dismiss it — the keyboard-lift relayout
        // slid the button out from under the finger before its touch-up could
        // land. Hit-test the tap ourselves and fire the button along with the
        // dismissal, so one tap starts the run.
        let hitStart = startButton.map {
            $0.isEnabled && $0.superview != nil
                && $0.frame.contains(g.location(in: $0.superview!))
        } ?? false
        view.endEditing(true)
        if hitStart { startClimb() }
    }

    @objc private func keyboardWillShow(_ n: Notification) {
        guard let field = seedField, field.isFirstResponder,
              let kb = (n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
        else { return }
        keyboardLift = 0
        view.setNeedsLayout(); view.layoutIfNeeded()   // measure from the resting layout
        let fieldRect = field.convert(field.bounds, to: view)
        let overlap = fieldRect.maxY + 12 - (view.bounds.height - kb.height)
        guard overlap > 0 else { return }
        keyboardLift = overlap
        UIView.animate(withDuration: 0.25) {
            self.view.setNeedsLayout(); self.view.layoutIfNeeded()
        }
    }

    @objc private func keyboardWillHide() {
        keyboardLift = 0
        UIView.animate(withDuration: 0.25) {
            self.view.setNeedsLayout(); self.view.layoutIfNeeded()
        }
    }

    @objc private func seedEdited() {
        guard let field = seedField else { return }
        var v = (field.text ?? "").uppercased()
        // Room for the full share string ("PINKY-REGULAR-XK4T9QD") — the old
        // 7-char clamp truncated a paste to "PINKY-R" and rejected it.
        if v.count > 24 { v = String(v.prefix(24)) }
        if field.text != v { field.text = v }
        startButton?.setTitle(v.isEmpty ? "START CLIMB" : "START SEEDED CLIMB")
        updateSeedNote()
    }

    /// Web updateSeedNote (index.html:25036): the exhibition label on a valid
    /// code, an inline error on a partial/full-but-invalid one, nothing when
    /// empty. Colors ride the palette (phosphor ok / suit-red err).
    private func updateSeedNote() {
        guard let note = seedNote else { return }
        let v = seedField?.text?.trimmingCharacters(in: .whitespaces) ?? ""
        if v.isEmpty { note.attributedText = nil; return }
        if SeedCode.decode(v) != nil {
            note.attributedText = CRTKit.attributed("Seeded climb · progression disabled",
                                                    size: 14, color: CRT.phosphor)
        } else {
            let tail = v.split(separator: "-").last.map(String.init) ?? v
            let msg = tail.count < SeedCode.length ? "Keep typing. 7 characters" : "Not a valid seed code"
            note.attributedText = CRTKit.attributed(msg, size: 14, color: CRT.suitRed)
        }
    }

    private func startClimb() {
        let d = GameFlowController.decks[deckIndex]
        let entered = seedField?.text?.trimmingCharacters(in: .whitespaces) ?? ""
        var seedU32: UInt32?
        if !entered.isEmpty {
            guard let decoded = SeedCode.decode(entered) else {
                flow.prompt.show("That seed doesn't parse.",
                                 help: "Seeds are 7 characters, like ABC2345.", actions: [
                    .init("OK", role: .plain) { [weak self] in self?.flow.prompt.hide() },
                ]) { [weak self] in self?.flow.prompt.hide() }
                return
            }
            seedU32 = decoded
        }
        view.endEditing(true)
        flow.startCampaign(deckId: d.id, tier: tiers[tierIndex], seedU32: seedU32)
    }

    private func cycleDeck(_ dir: Int) {
        deckIndex = (deckIndex + dir + GameFlowController.decks.count) % GameFlowController.decks.count
        tierIndex = 0
        // v6.57 SCROLL ISOLATION: ONLY the character sprite moves between
        // decks. The old carousel snapshotted the whole `content` page and
        // slid it out — title, identity, high score, tier chips, START and
        // all translated with it. Now the rebuild swaps everything else IN
        // PLACE (the seams are geometry-fixed, so every frame lands exactly
        // where the old one sat) while the outgoing sprite ghosts one way
        // and the fresh sprite slides in from the other. Transform/opacity
        // only, one short self-terminating animator — and `content`'s
        // transform is never touched, so the EXACTFIT1 scale-to-fit branch
        // has nothing left to fight.
        let shift = view.bounds.width * 0.6 * CGFloat(dir > 0 ? 1 : -1)
        let oldSprite = content.viewWithTag(777)
        let ghost = oldSprite?.snapshotView(afterScreenUpdates: false)
        if let ghost, let oldSprite {
            ghost.frame = oldSprite.convert(oldSprite.bounds, to: scroll)
        }
        build()
        view.layoutIfNeeded()
        guard let sprite = content.viewWithTag(777) else { return }
        let d = GameFlowController.decks[deckIndex]
        let unlocked = deckUnlocked(d)
        if let ghost { scroll.addSubview(ghost) }
        sprite.transform = CGAffineTransform(translationX: shift, y: 0)
        sprite.alpha = 0
        let slide = UIViewPropertyAnimator(duration: 0.22, curve: .easeOut) {
            sprite.transform = .identity
            sprite.alpha = unlocked ? 1 : 0.72
            ghost?.transform = CGAffineTransform(translationX: -shift, y: 0)
            ghost?.alpha = 0
        }
        slide.addCompletion { _ in
            ghost?.removeFromSuperview()
            // Character perk (web dcPerk: squash-and-stretch) — unlocked decks
            // only, chained AFTER the slide so the two never fight over the
            // sprite's transform.
            guard unlocked else { return }
            UIView.animateKeyframes(withDuration: 0.45, delay: 0) {
                UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.38) {
                    sprite.transform = CGAffineTransform(translationX: 0, y: -3).scaledBy(x: 0.96, y: 1.06)
                }
                UIView.addKeyframe(withRelativeStartTime: 0.38, relativeDuration: 0.34) {
                    sprite.transform = CGAffineTransform(scaleX: 1.03, y: 0.96)
                }
                UIView.addKeyframe(withRelativeStartTime: 0.72, relativeDuration: 0.28) {
                    sprite.transform = .identity
                }
            }
        }
        slide.startAnimation()
    }
}

// MARK: - Zen select

final class ZenSelectViewController: MenuScreenBase {
    /// Left-edge swipe = the ← control.
    override var backGestureAction: (() -> Void)? { { [weak self] in self?.flow.showMenu() } }

    private var picked: String?
    private let backButton = PixelButtonView("←", role: .plain, fontSize: 20)

    override func viewDidLoad() {
        super.viewDidLoad()
        buildCorner()
        build()
    }

    private func buildCorner() {
        backButton.onTap = { [weak self] in self?.flow.showMenu() }
        backButton.frame = CGRect(x: 8, y: 8, width: 48, height: 40)  // real y: viewDidLayoutSubviews
        view.addSubview(backButton)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Web .nav-btn: always just BELOW the safe-area inset.
        backButton.frame = CGRect(x: 8, y: view.safeAreaInsets.top + 4, width: 48, height: 40)
    }

    override var centersContentVertically: Bool { true }

    private func build() {
        resetLayout()
        // The web zen select: the block (title mid-page, three ROWS, START)
        // is vertically centred; rows pitch 79pt, a wider gap before START.
        addTitle("ZEN", size: 16)
        for (i, id) in GameData.shared.difficulty.zenIds.enumerated() {
            let z = GameData.shared.difficulty.zen(id)
            let e = flow.campaign.zenStats.get(id)
            let unlocked = flow.campaign.zenUnlocks.unlocked(id)
            // v6.62: NO default highlight — nothing is selected until the
            // player picks a row (START stays disabled meanwhile).
            let role: PixelButtonView.Role = picked == id ? .charged : .plain
            let row = PixelButtonView("", role: role, fontSize: 16)
            row.isEnabled = unlocked
            row.accessibilityLabel = z.label.uppercased()
            row.onTap = { [weak self] in
                self?.picked = id
                self?.build()
            }
            row.frame = CGRect(x: 32, y: layoutY, width: view.bounds.width - 64, height: 72)
            content.addSubview(row)
            // The MAIN MENU's button text, not a second style: uppercased,
            // the plain button face, and the ROLE's own text colour (ink on
            // the green) — the rows used to overlay white display-font labels.
            let rowText: UIColor = !unlocked ? CRT.disabledText
                : role == .cta ? CRT.ink
                : role == .charged ? CRT.phosphor : CRT.cardFace
            let name = CRTKit.label(z.label.uppercased(), size: 18, color: rowText)
            name.textAlignment = .center
            name.frame = CGRect(x: 0, y: 8, width: row.bounds.width, height: 22)
            name.isUserInteractionEnabled = false
            row.addSubview(name)
            let secondary: UIColor = !unlocked ? CRT.disabledText
                : role == .cta ? CRT.ink.withAlphaComponent(0.75) : CRT.muted
            // Live off the zen config (web: suitCount × 13) — a difficulty.js
            // retune can never desync the label.
            let sub = CRTKit.label("\(z.suitCount * 13) cards · \(z.piles) piles",
                                   size: 14, color: secondary)
            sub.textAlignment = .center
            sub.frame = CGRect(x: 0, y: 32, width: row.bounds.width, height: 16)
            sub.isUserInteractionEnabled = false
            row.addSubview(sub)
            let third: String
            if !unlocked {
                let prev = GameData.shared.difficulty.zenIds[safe: i - 1] ?? "easy"
                third = "Beat \(GameData.shared.difficulty.zen(prev).label) to unlock"
            } else if e.wins == 0 {
                // Web (index.html:31335): "no wins yet" whenever wins == 0,
                // regardless of games played.
                third = "no wins yet"
            } else {
                third = "\(e.wins) win\(e.wins == 1 ? "" : "s")"
            }
            let line3 = CRTKit.label(third, size: 14, color: unlocked ? CRT.cardFace : CRT.disabledText)
            line3.textAlignment = .center
            line3.frame = CGRect(x: 0, y: 48, width: row.bounds.width, height: 16)
            line3.isUserInteractionEnabled = false
            row.addSubview(line3)
            addGap(79)
        }
        addGap(39)
        addButton("START", role: picked == nil ? .plain : .cta, height: 46,
                  enabled: picked != nil) { [weak self] in
            guard let self, let d = self.picked else { return }
            self.flow.startZen(diff: d)
        }
        view.setNeedsLayout()
    }
}

// MARK: - Collection

final class CollectionViewController: MenuScreenBase {
    /// Left-edge swipe = the ← control.
    override var backGestureAction: (() -> Void)? { { [weak self] in self?.flow.showMenu() } }

    /// Web #collectionScreen: the header rides at the very top — title glyphs
    /// at ~24pt, STICKERS head at ~55pt, first tile row at ~77pt. On notched
    /// phones the header must still start BELOW the Dynamic Island.
    override var contentTopInset: CGFloat { max(12, view.safeAreaInsets.top) }

    private let backButton = PixelButtonView("←", role: .plain, fontSize: 20)

    override func viewDidLoad() {
        super.viewDidLoad()
        // Web `#collectionScreen`: corner ← back, display title, gold class
        // heads, 3-col pixel-panel tiles. Locked = ink silhouette + "?" + the
        // unlock hint with its live phosphor progress bar and "n / m" count.
        backButton.onTap = { [weak self] in self?.flow.showMenu() }
        backButton.frame = CGRect(x: 8, y: 8, width: 48, height: 40)  // real y: viewDidLayoutSubviews
        view.addSubview(backButton)
        build()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Web .nav-btn: always just BELOW the safe-area inset.
        backButton.frame = CGRect(x: 8, y: view.safeAreaInsets.top + 4, width: 48, height: 40)
    }

    private func build() {
        resetLayout()
        tileHelp.removeAll()
        addGap(6)
        addTitle("COLLECTION", size: 16)
        // The first class head ("Stickers") used to start right under the
        // title — at x14 it sat straight across the corner ← button (v6.67,
        // batch item 14). Clear the 40pt nav row before the left-aligned rows.
        addGap(26)
        let unlocks = flow.campaign.itemUnlocks
        let bought = flow.campaign.stats.get().itemsBought
        for (title, defs, kind) in CollectionViewController.groups() {
            let head = CRTKit.label(title, size: 14, color: CRT.gold, display: true)
            head.frame = CGRect(x: 14, y: layoutY, width: 300, height: 18)
            content.addSubview(head)
            addGap(22)
            let grid = UIView()
            let cols = 3
            let cw = (view.bounds.width - 28 - CGFloat(cols - 1) * 10) / CGFloat(cols)
            let th: CGFloat = 150
            var gy: CGFloat = 0
            for (i, def) in defs.enumerated() {
                let r = i / cols, c = i % cols
                let unlocked = unlocks.isUnlocked(def)
                let tile = UIControl(frame: CGRect(x: 14 + CGFloat(c) * (cw + 10),
                                                   y: CGFloat(r) * (th + 10), width: cw, height: th))
                let panel = PixelPanelView(face: CRT.feltMid, border: CRT.ink, shadowOffsetPx: 2)
                panel.isUserInteractionEnabled = false
                panel.frame = tile.bounds
                tile.addSubview(panel)
                let raw = ItemArt.forSlot(kind: kind, id: def.id, card: nil, deckId: flow.campaign.deckId)
                let art = UIImageView(image: unlocked ? raw : CollectionViewController.silhouette(raw))
                art.contentMode = .scaleAspectFit
                art.layer.magnificationFilter = .nearest
                art.alpha = unlocked ? 1 : 0.72
                // Web tiles wear a SMALL pixel icon (~40px) — not a tile-
                // filling blowup. 44pt keeps nearest-neighbour steps even.
                // Suited stickers drop 12pt to make room for the suit
                // caption above the chip (never baked INTO it).
                let cap = (kind == "sticker" && unlocked)
                    ? ItemArt.suitCaptionView(def, width: 36) : nil
                let artY: CGFloat = cap != nil ? 26 : 14
                art.frame = CGRect(x: (cw - 44) / 2, y: artY, width: 44, height: 44)
                art.isUserInteractionEnabled = false
                tile.addSubview(art)
                if let cap {
                    cap.center = CGPoint(x: cw / 2, y: artY - 2 - cap.bounds.height / 2)
                    cap.isUserInteractionEnabled = false
                    tile.addSubview(cap)
                }
                if unlocked {
                    let name = CRTKit.label(def.label, size: 14, color: CRT.cardFace)
                    name.textAlignment = .center
                    name.numberOfLines = 2
                    name.frame = CGRect(x: 4, y: 80, width: cw - 8, height: 30)
                    tile.addSubview(name)
                    // How often you've actually BOUGHT it. Unlocking only says
                    // you met the gate once; this says whether the item earned
                    // a place in your runs. Never bought → the line is absent
                    // rather than a "×0", which would read as a scolding.
                    let times = bought[def.id] ?? 0
                    if times > 0 {
                        let n = CRTKit.label("BOUGHT ×\(times)", size: 14, color: CRT.gold)
                        n.textAlignment = .center
                        n.alpha = 0.85
                        n.frame = CGRect(x: 4, y: 116, width: cw - 8, height: 15)
                        tile.addSubview(n)
                    }
                } else {
                    let q = CRTKit.label("?", size: 14, color: CRT.cardFace)
                    q.textAlignment = .center
                    q.frame = CGRect(x: 0, y: 76, width: cw, height: 16)
                    tile.addSubview(q)
                    let hint = CRTKit.label(unlocks.hint(for: def), size: 14, color: CRT.muted)
                    hint.textAlignment = .center
                    // v6.74: wrap, never truncate with "…" — measure the hint
                    // and seat the progress bar beneath it (was 2-line fixed
                    // 30pt, which clipped longer hints).
                    hint.numberOfLines = 0
                    let hintH = ceil(hint.sizeThatFits(CGSize(width: cw - 8, height: .greatestFiniteMagnitude)).height)
                    hint.frame = CGRect(x: 4, y: 91, width: cw - 8, height: hintH)
                    tile.addSubview(hint)
                    if let gate = def.unlock {
                        let cur = min(unlocks.statValue(gate.stat), Int(gate.count))
                        let total = max(1, Int(gate.count))
                        // The recessed well + phosphor fill.
                        let barY = min(91 + hintH + 6, 150 - 8 - 4)
                        let bar = UIView(frame: CGRect(x: 8, y: barY, width: cw - 16, height: 8))
                        bar.backgroundColor = CRT.feltDeep
                        bar.layer.borderWidth = 1
                        bar.layer.borderColor = CRT.ink.cgColor
                        let fill = UIView(frame: CGRect(x: 1, y: 1, width: (bar.bounds.width - 2) * CGFloat(cur) / CGFloat(total), height: 6))
                        fill.backgroundColor = CRT.phosphor
                        bar.addSubview(fill)
                        tile.addSubview(bar)
                        let count = CRTKit.label("\(cur) / \(total)", size: 14, color: CRT.muted)
                        count.textAlignment = .center
                        count.frame = CGRect(x: 0, y: 133, width: cw, height: 15)
                        tile.addSubview(count)
                    }
                }
                if unlocked {
                    // TAP → the detail pager; HOLD (500ms, the web's
                    // attachStoreHoldHelp on #colList, index.html:22374) →
                    // the item's registry help. The recognizer cancels the
                    // control's touch, so a hold never also fires the tap
                    // (the web's storeHoldSuppress). Locked tiles get
                    // neither — the unlock hint on the tile is their help.
                    tile.addAction(UIAction { [weak self] _ in
                        self?.showDetail(def: def)
                    }, for: .touchUpInside)
                    let hold = UILongPressGestureRecognizer(target: self, action: #selector(tileHeld(_:)))
                    hold.minimumPressDuration = 0.5
                    tile.addGestureRecognizer(hold)
                    tileHelp[ObjectIdentifier(tile)] = (kind, def)
                }
                grid.addSubview(tile)
                gy = tile.frame.maxY
            }
            addView(grid, height: gy + 6)
            addGap(8)
        }
        view.setNeedsLayout()
    }

    /// Web COLLECTION_GROUPS × items.js array order (stickers cursed-filtered,
    /// as the web's grant pools are). The grid AND the detail pager both read
    /// this so they can never disagree about the flat item list.
    static func groups() -> [(String, [ItemDef], String)] {
        let data = GameData.shared
        return [
            ("STICKERS", data.items.stickers.filter { !$0.cursed }, "sticker"),
            ("PILLARS", data.items.pillars, "pillar"),
            ("BASES", data.items.bases, "base"),
            ("SAME-POWERS", data.items.samePowers, "samepower"),
            ("PACKS", data.items.packs, "pack"),
        ]
    }

    /// Web `.silhouette` (brightness 0): the art flattened to an ink shape.
    static func silhouette(_ img: UIImage) -> UIImage {
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = UIScreen.main.scale
        return UIGraphicsImageRenderer(size: img.size, format: fmt).image { ctx in
            img.draw(at: .zero)
            ctx.cgContext.setBlendMode(.sourceIn)
            ctx.cgContext.setFillColor(CRT.ink.cgColor)
            ctx.cgContext.fill(CGRect(origin: .zero, size: img.size))
        }
    }

    /// Live gesture → item map for the collection hold-help (the store's
    /// holdActions idiom); rebuilt with the grid on every build().
    private var tileHelp: [ObjectIdentifier: (kind: String, def: ItemDef)] = [:]

    @objc private func tileHeld(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began, let v = g.view,
              let (kind, def) = tileHelp[ObjectIdentifier(v)] else { return }
        // Registry help through the shared prompt bar (the store idiom):
        // label · TIER, the sticker scope line, then the registry description
        // as the help body — never hand-written duplicates.
        var text = def.label + (def.tier.isEmpty ? "" : " · \(def.tier.uppercased())")
        if kind == "sticker" {
            let suits = def.suits ?? []
            text += "\n" + (suits.isEmpty ? "Add to any card"
                                          : "Add to any \(suits.joined(separator: " or ")) card")
        }
        flow.prompt.show(text, help: def.genericDescription, actions: [
            .init("OK", role: .plain) { [weak self] in self?.flow.prompt.hide() },
        ]) { [weak self] in self?.flow.prompt.hide() }
    }

    private func showDetail(def: ItemDef) {
        let detail = CollectionDetailView(unlocks: flow.campaign.itemUnlocks,
                                          deckId: flow.campaign.deckId, focus: def)
        detail.present(in: view)
    }
}

// MARK: - Collection detail panel

/// Web `#cardInfo.cid-mode`: the centered, FIXED-SHELL detail panel — big item
/// art top-center, name (left) + rarity (right), the meta line (sticker scope
/// left, gold ◉ cost right), the registry description, and a ◀ N/total ▶
/// pager pinned to the bottom. The shell never changes size while paging; only
/// the content swaps. A scrim tap closes (the web shows no ✕).
final class CollectionDetailView: UIView, UIGestureRecognizerDelegate {
    private static let panelW: CGFloat = 360
    private static let panelH: CGFloat = 300

    private let panel = PixelPanelView(face: CRT.feltMid, border: CRT.ink)
    private let artView = UIImageView()
    private let nameLabel = UILabel()
    private let tierLabel = UILabel()
    private let scopeLabel = UILabel()
    private let costLabel = UILabel()
    private let descScroll = UIScrollView()
    private let descLabel = UILabel()
    private let divider = UIView()
    private let prevButton = UIButton(type: .custom)
    private let nextButton = UIButton(type: .custom)
    private let countLabel = UILabel()

    private let deckId: String
    private let list: [(kind: String, def: ItemDef)]
    private var index = 0

    init(unlocks: ItemUnlocks, deckId: String, focus: ItemDef) {
        self.deckId = deckId
        // Web collectionPageList(): the flattened UNLOCKED set in grid order,
        // rebuilt per open so a mid-session unlock pages correctly.
        var flat: [(kind: String, def: ItemDef)] = []
        for (_, defs, kind) in CollectionViewController.groups() {
            for def in defs where unlocks.isUnlocked(def) { flat.append((kind, def)) }
        }
        self.list = flat
        self.index = max(0, flat.firstIndex(where: { $0.def == focus }) ?? 0)
        super.init(frame: .zero)

        backgroundColor = UIColor.black.withAlphaComponent(0.55)
        let tap = UITapGestureRecognizer(target: self, action: #selector(scrimTapped(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        addGestureRecognizer(tap)

        addSubview(panel)
        artView.contentMode = .scaleAspectFit
        artView.layer.magnificationFilter = .nearest
        panel.addSubview(artView)
        nameLabel.textAlignment = .left
        panel.addSubview(nameLabel)
        tierLabel.textAlignment = .right
        panel.addSubview(tierLabel)
        scopeLabel.textAlignment = .left
        panel.addSubview(scopeLabel)
        // The deep-dive also shows the store cost (v5.81) — the gold "◉ N"
        // chip text from the store tile, pinned right on the meta line.
        costLabel.textAlignment = .right
        panel.addSubview(costLabel)
        // Fixed shell, scrolling content (the web scrolls overlong text
        // INSIDE the detail band — the shell and pager never move).
        descScroll.showsVerticalScrollIndicator = false
        descLabel.numberOfLines = 0
        descLabel.textAlignment = .left
        descScroll.addSubview(descLabel)
        panel.addSubview(descScroll)

        divider.backgroundColor = CRT.cardFace.withAlphaComponent(0.14)
        panel.addSubview(divider)
        for b in [prevButton, nextButton] {
            b.backgroundColor = CRT.feltDeep
            b.layer.borderWidth = CRT.px
            b.layer.borderColor = CRT.ink.cgColor
            panel.addSubview(b)
        }
        prevButton.accessibilityLabel = "Previous item"
        nextButton.accessibilityLabel = "Next item"
        prevButton.addAction(UIAction { [weak self] _ in self?.page(-1) }, for: .touchUpInside)
        nextButton.addAction(UIAction { [weak self] _ in self?.page(1) }, for: .touchUpInside)
        countLabel.textAlignment = .center
        panel.addSubview(countLabel)
        render()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    func present(in host: UIView) {
        frame = host.bounds
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.addSubview(self)
    }

    private func dismiss() { removeFromSuperview() }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        touch.view === self   // panel taps (pager) never reach the scrim recognizer
    }

    @objc private func scrimTapped(_ g: UITapGestureRecognizer) {
        if !panel.frame.contains(g.location(in: self)) { dismiss() }
    }

    private func page(_ step: Int) {
        let ni = index + step
        guard ni >= 0, ni < list.count else { return }   // clamped, no wrap
        index = ni
        render()
    }

    /// Web `stickerSuitLine`: stickers only — the restriction read LIVE off
    /// the def's `suits` ("Add to any card" / "Add to any ♠, ♥ or ♦ card").
    private func scopeLine(kind: String, def: ItemDef) -> String? {
        guard kind == "sticker" else { return nil }
        guard let suits = def.suits, !suits.isEmpty else { return "Add to any card" }
        let list = suits.count == 1 ? suits[0]
            : suits.dropLast().joined(separator: ", ") + " or " + suits[suits.count - 1]
        return "Add to any \(list) card"
    }

    private func render() {
        let (kind, def) = list[index]
        artView.image = ItemArt.forSlot(kind: kind, id: def.id, card: nil, deckId: deckId)
        nameLabel.attributedText = CRTKit.attributed(def.label, size: 16, color: CRT.cardFace)
        tierLabel.attributedText = CRTKit.attributed(def.tier.uppercased(), size: 14,
                                                     color: CRT.cardFace.withAlphaComponent(0.7))
        scopeLabel.attributedText = scopeLine(kind: kind, def: def).map {
            CRTKit.attributed($0, size: 14, color: CRT.cardFace.withAlphaComponent(0.82))
        }
        costLabel.attributedText = CRTKit.attributed("◉ \(Int(def.price))", size: 14, color: CRT.gold)
        // Through CRTKit.attributed (v6.72): item descriptions name suits, and
        // the raw-attributes build bypassed the pixel-suit substitution.
        let desc = NSMutableAttributedString(
            attributedString: CRTKit.attributed(def.genericDescription, size: 14, color: CRT.cardFace))
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 4   // web line-height 1.34
        desc.addAttribute(.paragraphStyle, value: para, range: NSRange(location: 0, length: desc.length))
        descLabel.attributedText = desc
        descScroll.setContentOffset(.zero, animated: false)   // new page reads from the top
        countLabel.attributedText = CRTKit.attributed(
            "\(index + 1) / \(list.count)", size: 14, color: CRT.cardFace.withAlphaComponent(0.65))
        styleArrow(prevButton, glyph: "◀", enabled: index > 0)
        styleArrow(nextButton, glyph: "▶", enabled: index < list.count - 1)
        setNeedsLayout()
    }

    private func styleArrow(_ b: UIButton, glyph: String, enabled: Bool) {
        b.isEnabled = enabled
        b.setAttributedTitle(CRTKit.attributed(
            glyph, size: 16, color: enabled ? CRT.phosphor : CRT.cardFace.withAlphaComponent(0.35)),
            for: .normal)
        // Enabled arrows carry the §4 hard 2px ↘ shadow; disabled lose it.
        b.layer.shadowColor = CRT.shadow.cgColor
        b.layer.shadowOffset = CGSize(width: 2, height: 2)
        b.layer.shadowRadius = 0
        b.layer.shadowOpacity = enabled ? 1 : 0
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = min(CollectionDetailView.panelW, bounds.width * 0.92)
        let h = CollectionDetailView.panelH
        panel.frame = CGRect(x: (bounds.width - w) / 2, y: (bounds.height - h) / 2, width: w, height: h)
        // Padding 13 top/bottom, 14 sides; art 72 tall, name row, scope, desc,
        // then the pager pinned to the bottom with its hairline divider.
        let iw = min(w - 28, 72 * max(0.5, artView.image.map { $0.size.width / max(1, $0.size.height) } ?? 1))
        artView.frame = CGRect(x: (w - iw) / 2, y: 15, width: iw, height: 72)
        nameLabel.frame = CGRect(x: 14, y: 97, width: w - 28 - 90, height: 20)
        tierLabel.frame = CGRect(x: w - 14 - 88, y: 100, width: 88, height: 16)
        // The meta line always renders — stickers carry the scope text on the
        // left, and every item carries its cost on the right (v5.81).
        scopeLabel.frame = CGRect(x: 14, y: 119, width: w - 28 - 76, height: 16)
        costLabel.frame = CGRect(x: w - 14 - 74, y: 119, width: 74, height: 16)
        let descY: CGFloat = 139
        let pagerTop = h - 13 - 40 - 8   // arrows 40 + padding-top 8
        divider.frame = CGRect(x: 14, y: pagerTop, width: w - 28, height: 1)
        descScroll.frame = CGRect(x: 14, y: descY, width: w - 28, height: pagerTop - descY - 6)
        // The label takes its natural height; the scroll view clips and
        // scrolls whatever exceeds the band (short text never scrolls).
        let fit = descLabel.sizeThatFits(CGSize(width: descScroll.bounds.width,
                                                height: .greatestFiniteMagnitude))
        descLabel.frame = CGRect(x: 0, y: 0, width: descScroll.bounds.width, height: fit.height)
        descScroll.contentSize = CGSize(width: descScroll.bounds.width, height: fit.height)
        prevButton.frame = CGRect(x: 14, y: pagerTop + 8, width: 44, height: 40)
        nextButton.frame = CGRect(x: w - 14 - 44, y: pagerTop + 8, width: 44, height: 40)
        countLabel.frame = CGRect(x: 14, y: pagerTop + 8, width: w - 28, height: 40)
    }
}

// MARK: - How to Play

// MARK: - Stats

// (Lifetime stats now ride the StatsSheetView bottom sheet — see Sheets.swift.)
