import UIKit
import GameCore

/// The ONE build stamp (the web's APP_VERSION footer line) — every footer and
/// the debug panel read it here, never a retyped literal.
enum BuildStamp {
    static let version = "v5.76"
    static let note = "ios: bottom gaps on map/deal, help-text footer removed, no zen reshuffle, zen save leak fixed"
    static let line = "build \(version) · \(note)"
    /// Deal-screen footer: just the build stamp, word-wrapped (~44 cols).
    static var dealLines: [String] {
        var lines: [String] = []
        var cur = ""
        for w in line.split(separator: " ") {
            if !cur.isEmpty, cur.count + 1 + w.count > 44 { lines.append(cur); cur = "" }
            cur += (cur.isEmpty ? "" : " ") + w
        }
        if !cur.isEmpty { lines.append(cur) }
        return lines
    }
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
        tissue.frame = view.bounds
        scroll.frame = view.bounds
        let top = centersContentVertically
            ? max(view.safeAreaInsets.top, (view.bounds.height - y) / 2)
            : contentTopInset
        content.frame = CGRect(x: 0, y: top, width: view.bounds.width, height: y)
        scroll.contentSize = CGSize(width: view.bounds.width,
                                    height: y + top + view.safeAreaInsets.bottom + 24)
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
    func addButton(_ title: String, role: PixelButtonView.Role = .plain, height: CGFloat = 46,
                   enabled: Bool = true, icon: UIImage? = nil,
                   handler: @escaping () -> Void) -> PixelButtonView {
        let b = PixelButtonView(title, role: role, fontSize: 15)
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
        label.attributedText = CRTKit.attributed(BuildStamp.line, size: 12, color: CRT.phosphor, glow: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak label] in
            label?.attributedText = normal
        }
    }
}

// MARK: - Main menu

final class MainMenuViewController: MenuScreenBase {
    private let canContinue: Bool

    init(flow: GameFlowController, canContinue: Bool) {
        self.canContinue = canContinue
        super.init(flow: flow)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        build()
    }

    override var centersContentVertically: Bool { true }

    private func build() {
        resetLayout()
        // The web menu, top to bottom: tagline · the gold "=" mark · the
        // two-line mixed-case wordmark · iconed buttons · the build footer.
        // The whole block is vertically centred (centersContentVertically);
        // the gaps below are the web's INTERNAL rhythm (measured on the
        // captures: tagline→logo 82pt, logo→wordmark 82pt, buttons 57pt).
        addText("HIGHER OR LOWER?", size: 12, color: CRT.cardFace)
        let tag = content.subviews.last as? UILabel
        // 12pt floor (project convention) — the web's 11px tagline gets the
        // room instead of a smaller font.
        tag?.attributedText = CRTKit.attributed("HIGHER OR LOWER?", size: 12, color: CRT.cardFace, display: true)
        tag?.textAlignment = .center
        addGap(46)
        let logo = UIImageView(image: MapArt.menuLogo(width: 64))
        logo.layer.magnificationFilter = .nearest
        logo.contentMode = .scaleAspectFit
        let holder = UIView()
        logo.frame = CGRect(x: (view.bounds.width - 64) / 2, y: 0, width: 64, height: 40)
        holder.addSubview(logo)
        addView(holder, height: 46)
        addGap(39)
        let line1 = CRTKit.label("Shoulda said", size: 24, color: CRT.cardFace, display: true)
        line1.textAlignment = .center
        addView(wrapCentered(line1), height: 30)
        let line2 = CRTKit.label("same", size: 24, color: CRT.phosphor, display: true, glow: true)
        line2.textAlignment = .center
        addView(wrapCentered(line2), height: 30)
        addGap(27)

        let campaignOpen = flow.campaignUnlocked()
        if canContinue {
            addButton("CONTINUE", role: .cta, icon: MapArt.menuIcon("sun")) { [weak self] in self?.resumeSave() }
        }
        if campaignOpen {
            addButton(canContinue ? "NEW CLIMB" : "CLIMB",
                      role: canContinue ? .plain : .cta,
                      icon: MapArt.menuIcon("spark")) { [weak self] in
                guard let self else { return }
                if self.canContinue {
                    self.flow.prompt.show("Start a NEW climb?", help: "The saved climb is lost.", actions: [
                        .init("Cancel", role: .plain) { self.flow.prompt.hide() },
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
        addButton("ZEN", role: campaignOpen ? .plain : .cta, icon: MapArt.menuIcon("zen")) { [weak self] in
            self?.flow.showZenSelect()
        }
        addButton("HOW TO PLAY", icon: MapArt.menuIcon("search")) { [weak self] in self?.showManual() }
        addButton("STATS", icon: MapArt.menuIcon("bars")) { [weak self] in self?.flow.showStats() }
        addButton("COLLECTION", icon: MapArt.menuIcon("box")) { [weak self] in self?.flow.showCollection() }
        addButton("SETTINGS", icon: MapArt.menuIcon("gear")) { [weak self] in
            guard let self else { return }
            self.flow.setScreen(SettingsViewController(flow: self.flow))
        }
        // Debug access (7 footer taps): the panel opens from here too.
        if flow.debugAccessEnabled() {
            addButton("🐞 DEBUG", icon: MapArt.menuIcon("spark")) { [weak self] in
                self?.flow.showDebugPanel()
            }
        }
        addGap(20)
        // Footer: the web's exact build line ("build " + APP_VERSION) — small,
        // muted, centred, wrapping to two lines right under the last button.
        // 7 quick taps toggle debug access (the web's wireVersionTapDebug).
        let foot = CRTKit.label(BuildStamp.line, size: 12, color: CRT.muted)
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

    private func showManual() {
        flow.showManualSheet()
    }
}

// MARK: - Settings

/// SOUND + RESET live under SETTINGS (the web tucks them off the main menu).
final class SettingsViewController: MenuScreenBase {
    override func viewDidLoad() {
        super.viewDidLoad()
        build()
    }

    override var centersContentVertically: Bool { true }

    private func build() {
        resetLayout()
        // Same centred header block and internal rhythm as the main menu.
        addText("HIGHER OR LOWER?", size: 12, color: CRT.cardFace)
        addGap(46)
        let logo = UIImageView(image: MapArt.menuLogo(width: 64))
        logo.layer.magnificationFilter = .nearest
        logo.contentMode = .scaleAspectFit
        let holder = UIView()
        logo.frame = CGRect(x: (view.bounds.width - 64) / 2, y: 0, width: 64, height: 40)
        holder.addSubview(logo)
        addView(holder, height: 46)
        addGap(39)
        let line1 = CRTKit.label("Shoulda said", size: 24, color: CRT.cardFace, display: true)
        line1.textAlignment = .center
        line1.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: 30)
        let w1 = UIView(); w1.addSubview(line1)
        addView(w1, height: 30)
        let line2 = CRTKit.label("same", size: 24, color: CRT.phosphor, display: true, glow: true)
        line2.textAlignment = .center
        line2.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: 30)
        let w2 = UIView(); w2.addSubview(line2)
        addView(w2, height: 30)
        addGap(27)
        addButton("SOUND: \(Sound.shared.enabled ? "ON" : "OFF")", icon: MapArt.menuIcon("spark")) { [weak self] in
            Sound.shared.enabled.toggle()
            self?.build()
        }
        addButton("RESET PROGRESS", role: .danger, icon: MapArt.menuIcon("quit")) { [weak self] in
            self?.confirmReset()
        }
        addButton("BACK", icon: MapArt.menuIcon("back")) { [weak self] in self?.flow.showMenu() }
        addGap(20)
        // The web's exact build line (same stamp as the main menu footer) —
        // 7 quick taps toggle debug access here too (both web footers wire it).
        let foot = CRTKit.label(BuildStamp.line, size: 12, color: CRT.muted)
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
                         help: "Campaign, decks, unlocks, stats and the tutorial are wiped — only the sound setting survives.",
                         actions: [
            .init("Cancel", role: .plain) { [weak self] in self?.flow.prompt.hide() },
            .init("Reset", role: .cta) { [weak self] in self?.confirmResetFinal() },
        ]) { [weak self] in self?.flow.prompt.hide() }
    }

    private func confirmResetFinal() {
        flow.prompt.show("Really erase everything?",
                         help: "The campaign, decks, unlocks, stats and tutorial all reset — this can't be undone.",
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
    private var deckIndex = 0
    private var tierIndex = 0
    private let tiers = DifficultyData.tierIds
    private var seedField: UITextField?
    private var seedNote: UILabel?
    private var seedOpen = false
    private let backButton = PixelButtonView("←", role: .plain, fontSize: 16)

    override func viewDidLoad() {
        super.viewDidLoad()
        // Web #deckSelect is a FIXED screen (the carousel is touch-action:
        // pan-x) — kill the inherited menu scroll's vertical drag/bounce.
        scroll.isScrollEnabled = false
        scroll.alwaysBounceVertical = false
        // Land on the furthest unlocked deck.
        deckIndex = GameFlowController.decks.lastIndex { deckUnlocked($0) } ?? 0
        // The corner back arrow + a swipe carousel, like the web.
        backButton.onTap = { [weak self] in self?.flow.showMenu() }
        backButton.frame = CGRect(x: 8, y: 8, width: 34, height: 30)  // real y: viewDidLayoutSubviews
        view.addSubview(backButton)
        let left = UISwipeGestureRecognizer(target: self, action: #selector(swipeLeft))
        left.direction = .left
        view.addGestureRecognizer(left)
        let right = UISwipeGestureRecognizer(target: self, action: #selector(swipeRight))
        right.direction = .right
        view.addGestureRecognizer(right)
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
        case "master": return flow.campaign.deckUnlocks.wonWithTier(deck.id, "regular")
        case "legendary": return flow.campaign.deckUnlocks.wonWithTier(deck.id, "master")
        default: return true
        }
    }

    private func build() {
        resetLayout()
        // The web: "CHOOSE YOUR DECK" top · big character mid-page · name +
        // tagline · tier chips with 'Beat X' subs · START CLIMB · pager dots ·
        // 'Have a seed?' link.
        addGap(10)
        addTitle("CHOOSE YOUR DECK", size: 15)

        let d = GameFlowController.decks[deckIndex]
        let unlocked = deckUnlocked(d)

        addGap(160)
        let row = UIView()
        let sprite = UIImageView(image: DeckCharacter.image(deckId: d.id, mood: .idle,
                                                            scale: 4, tier: tiers[tierIndex]))
        sprite.contentMode = .scaleAspectFit
        sprite.layer.magnificationFilter = .nearest
        sprite.alpha = unlocked ? 1 : 0.22
        sprite.frame = CGRect(x: (view.bounds.width - 128) / 2, y: 0, width: 128, height: 128)
        sprite.tag = 777            // cycleDeck finds the sprite for the perk animation
        row.addSubview(sprite)
        if !unlocked {
            let q = CRTKit.label("?", size: 40, color: CRT.muted, display: true)
            q.textAlignment = .center
            q.frame = CGRect(x: (view.bounds.width - 60) / 2, y: 36, width: 60, height: 56)
            row.addSubview(q)
        }
        addView(row, height: 132)
        addGap(20)
        let name = CRTKit.label(unlocked ? d.name : "???", size: 21,
                                color: unlocked ? CRT.cardFace : CRT.muted, display: true)
        name.textAlignment = .center
        name.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: 26)
        let nw = UIView(); nw.addSubview(name)
        addView(nw, height: 28)
        addText(unlocked ? d.sub : (d.unlockNote ?? "Locked"), size: 13)
        addGap(35)

        // Tier chips: selected = phosphor outline; locked = dim with the
        // 'Beat X' sub-line; every chip carries the per-deck/tier BEST score
        // (native-only — the web has no per-character score).
        let tierRow = UIView()
        let tw = (view.bounds.width - 100) / 3
        let subs = ["", "Beat Regular", "Beat Master"]
        let bests = flow.campaign.stats.get().deckTierBest
        for (i, t) in tiers.enumerated() {
            let open = unlocked && tierUnlocked(t, deck: d)
            let won = flow.campaign.deckUnlocks.wonWithTier(d.id, t)
            let chip = PixelButtonView("", role: i == tierIndex ? .charged : .plain, fontSize: 12)
            chip.isEnabled = open
            chip.accessibilityLabel = t.uppercased()
            chip.onTap = { [weak self] in
                self?.tierIndex = i
                self?.build()
            }
            chip.frame = CGRect(x: 50 + CGFloat(i) * (tw + 8), y: 0, width: tw, height: 56)
            tierRow.addSubview(chip)
            let tl = CRTKit.label(t.capitalized + (won ? " ✓" : ""), size: 13,
                                  color: open ? CRT.cardFace : CRT.disabledText)
            tl.textAlignment = .center
            tl.frame = CGRect(x: 0, y: 3, width: tw, height: 17)
            tl.isUserInteractionEnabled = false
            chip.addSubview(tl)
            if i > 0 {
                // 12pt floor: the web's 11px sub rides a taller line box.
                let sub = UILabel()
                sub.attributedText = NSAttributedString(
                    string: subs[i],
                    attributes: [.font: UIFont(descriptor: CRT.Font.of(12).fontDescriptor.withSymbolicTraits(.traitItalic) ?? CRT.Font.of(12).fontDescriptor, size: 12),
                                 .foregroundColor: open ? CRT.muted : CRT.disabledText])
                sub.textAlignment = .center
                sub.frame = CGRect(x: 0, y: 20, width: tw, height: 15)
                sub.isUserInteractionEnabled = false
                chip.addSubview(sub)
            }
            let best = bests["\(d.id).\(t)"]
            let bl = CRTKit.label(best.map { "BEST \($0)" } ?? "BEST —", size: 12,
                                  color: !open ? CRT.disabledText : (best != nil ? CRT.gold : CRT.muted))
            bl.textAlignment = .center
            bl.frame = CGRect(x: 0, y: 36, width: tw, height: 15)
            bl.isUserInteractionEnabled = false
            chip.addSubview(bl)
        }
        addView(tierRow, height: 62)
        addGap(8)

        addGap(3)
        let start = PixelButtonView("START CLIMB", role: .cta, fontSize: 18)
        start.isEnabled = unlocked && tierUnlocked(tiers[tierIndex], deck: d)
        start.onTap = { [weak self] in self?.startClimb() }
        start.frame = CGRect(x: (view.bounds.width - 214) / 2, y: layoutY, width: 214, height: 54)
        content.addSubview(start)
        addGap(66)

        // Seed entry, tucked behind the 'Have a seed?' link (exhibition rule).
        if seedOpen {
            let seedPanel = PixelPanelView(face: CRT.feltMid, border: CRT.ink)
            let field = UITextField()
            field.font = CRT.Font.of(18)
            field.textColor = CRT.gold
            field.autocapitalizationType = .allCharacters
            field.autocorrectionType = .no
            field.spellCheckingType = .no
            field.attributedPlaceholder = CRTKit.attributed("ABC2345", size: 16, color: CRT.disabledText)
            field.textAlignment = .center
            // Web input maxlength=7 (the SeedCode alphabet is fixed-width):
            // enforced live in seedEdited, which also drives the note below.
            field.addTarget(self, action: #selector(seedEdited), for: .editingChanged)
            field.frame = CGRect(x: 10, y: 6, width: view.bounds.width - 140 - 20, height: 30)
            seedPanel.addSubview(field)
            seedField = field
            seedPanel.frame = CGRect(x: 70, y: layoutY, width: view.bounds.width - 140, height: 42)
            content.addSubview(seedPanel)
            addGap(46)
            // Live validation note (web updateSeedNote, index.html:25036):
            // ok on a valid code, err while typing / on a full-but-bad code.
            let note = CRTKit.label("", size: 12, color: CRT.muted)
            note.textAlignment = .center
            note.frame = CGRect(x: 24, y: layoutY, width: view.bounds.width - 48, height: 16)
            content.addSubview(note)
            seedNote = note
            addGap(20)
            addText("A seeded climb is an EXHIBITION — nothing banks.", size: 12)
        }

        // Pager dots + 'Have a seed?' — the web bottom-ANCHORS these (~92% /
        // ~96% of the screen), so they live on the view, not in the content
        // flow; positionPager() pins them on every layout.
        dotsRow?.removeFromSuperview()
        seedLink?.removeFromSuperview()
        seedLink = nil
        let dots = UIView()
        for (i, _) in GameFlowController.decks.enumerated() {
            let dot = UIView(frame: CGRect(x: view.bounds.width / 2 - 30 + CGFloat(i) * 16, y: 0, width: 8, height: 8))
            dot.backgroundColor = i == deckIndex ? CRT.phosphor : CRT.feltMid
            dot.layer.borderWidth = 1
            dot.layer.borderColor = CRT.ink.cgColor
            dot.layer.cornerRadius = 4   // the sanctioned pager-dot circle
            if i == deckIndex { dot.transform = CGAffineTransform(scaleX: 1.25, y: 1.25) }  // web: active dot scale 1.25
            dots.addSubview(dot)
        }
        view.addSubview(dots)
        dotsRow = dots
        if !seedOpen {
            let link = UIButton(type: .custom)
            link.setAttributedTitle(NSAttributedString(
                string: "Have a seed?",
                attributes: [.font: CRT.Font.of(15), .foregroundColor: CRT.cardFace,
                             .underlineStyle: NSUnderlineStyle.single.rawValue]), for: .normal)
            link.addAction(UIAction { [weak self] _ in
                self?.seedOpen = true
                self?.build()
            }, for: .touchUpInside)
            view.addSubview(link)
            seedLink = link
        }
        positionPager()
        view.setNeedsLayout()
    }

    private var dotsRow: UIView?
    private var seedLink: UIButton?

    private func positionPager() {
        let w = view.bounds.width, h = view.bounds.height
        guard w > 0, h > 0 else { return }
        dotsRow?.frame = CGRect(x: 0, y: h * 0.92 - 4, width: w, height: 8)
        seedLink?.frame = CGRect(x: 0, y: h * 0.96 - 11, width: w, height: 22)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Web .nav-btn: always just BELOW the safe-area inset (insets are 0
        // at viewDidLoad, so the floating buttons land here).
        backButton.frame = CGRect(x: 8, y: view.safeAreaInsets.top + 4, width: 34, height: 30)
        positionPager()
    }

    /// Web: the input is maxlength=7 — the SeedCode alphabet is 7 chars — so
    /// typing past the code truncates (and uppercases) on the spot.
    @objc private func seedEdited() {
        guard let field = seedField else { return }
        var v = (field.text ?? "").uppercased()
        if v.count > SeedCode.length { v = String(v.prefix(SeedCode.length)) }
        if field.text != v { field.text = v }
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
            note.attributedText = CRTKit.attributed("Seeded climb — progression disabled",
                                                    size: 12, color: CRT.phosphor)
        } else {
            let msg = v.count < SeedCode.length ? "Keep typing — 7 characters" : "Not a valid seed code"
            note.attributedText = CRTKit.attributed(msg, size: 12, color: CRT.suitRed)
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
        // Carousel slide (web: the deck carousel translates on swipe) —
        // snapshot the old page, slide it out as the fresh build slides in.
        let shift = view.bounds.width * 0.6 * CGFloat(dir > 0 ? 1 : -1)
        let ghost = content.snapshotView(afterScreenUpdates: false)
        if let ghost {
            ghost.frame = content.frame
            scroll.addSubview(ghost)
        }
        build()
        view.layoutIfNeeded()
        content.transform = CGAffineTransform(translationX: shift, y: 0)
        content.alpha = 0.6
        let slide = UIViewPropertyAnimator(duration: 0.28, curve: .easeOut) {
            self.content.transform = .identity
            self.content.alpha = 1
            ghost?.transform = CGAffineTransform(translationX: -shift, y: 0)
            ghost?.alpha = 0
        }
        slide.addCompletion { _ in ghost?.removeFromSuperview() }
        slide.startAnimation()
        // Character perk (web dcPerk: squash-and-stretch) — unlocked decks only.
        let d = GameFlowController.decks[deckIndex]
        if deckUnlocked(d), let sprite = content.viewWithTag(777) {
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
    }
}

// MARK: - Zen select

final class ZenSelectViewController: MenuScreenBase {
    private var picked: String?
    private let backButton = PixelButtonView("←", role: .plain, fontSize: 16)

    override func viewDidLoad() {
        super.viewDidLoad()
        buildCorner()
        build()
    }

    private func buildCorner() {
        backButton.onTap = { [weak self] in self?.flow.showMenu() }
        backButton.frame = CGRect(x: 8, y: 8, width: 34, height: 30)  // real y: viewDidLayoutSubviews
        view.addSubview(backButton)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Web .nav-btn: always just BELOW the safe-area inset.
        backButton.frame = CGRect(x: 8, y: view.safeAreaInsets.top + 4, width: 34, height: 30)
    }

    override var centersContentVertically: Bool { true }

    private func build() {
        resetLayout()
        // The web zen select: the block (title mid-page, three ROWS, START)
        // is vertically centred; rows pitch 79pt, a wider gap before START.
        addTitle("ZEN", size: 15)
        for (i, id) in GameData.shared.difficulty.zenIds.enumerated() {
            let z = GameData.shared.difficulty.zen(id)
            let e = flow.campaign.zenStats.get(id)
            let unlocked = flow.campaign.zenUnlocks.unlocked(id)
            let row = PixelButtonView("", role: picked == id ? .charged : .plain, fontSize: 15)
            row.isEnabled = unlocked
            row.accessibilityLabel = z.label.uppercased()
            row.onTap = { [weak self] in
                self?.picked = id
                self?.build()
            }
            row.frame = CGRect(x: 32, y: layoutY, width: view.bounds.width - 64, height: 72)
            content.addSubview(row)
            let name = CRTKit.label(z.label, size: 17, color: unlocked ? CRT.cardFace : CRT.disabledText, display: true)
            name.textAlignment = .center
            name.frame = CGRect(x: 0, y: 8, width: row.bounds.width, height: 22)
            name.isUserInteractionEnabled = false
            row.addSubview(name)
            // Live off the zen config (web: suitCount × 13) — a difficulty.js
            // retune can never desync the label.
            let sub = CRTKit.label("\(z.suitCount * 13) cards · \(z.piles) piles",
                                   size: 13, color: unlocked ? CRT.muted : CRT.disabledText)
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
            let line3 = CRTKit.label(third, size: 12, color: unlocked ? CRT.cardFace : CRT.disabledText)
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
    /// Web #collectionScreen: the header rides at the very top — title glyphs
    /// at ~24pt, STICKERS head at ~55pt, first tile row at ~77pt.
    override var contentTopInset: CGFloat { 12 }

    private let backButton = PixelButtonView("←", role: .plain, fontSize: 16)

    override func viewDidLoad() {
        super.viewDidLoad()
        // Web `#collectionScreen`: corner ← back, display title, gold class
        // heads, 3-col pixel-panel tiles. Locked = ink silhouette + "?" + the
        // unlock hint with its live phosphor progress bar and "n / m" count.
        backButton.onTap = { [weak self] in self?.flow.showMenu() }
        backButton.frame = CGRect(x: 8, y: 8, width: 34, height: 30)  // real y: viewDidLayoutSubviews
        view.addSubview(backButton)
        build()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Web .nav-btn: always just BELOW the safe-area inset.
        backButton.frame = CGRect(x: 8, y: view.safeAreaInsets.top + 4, width: 34, height: 30)
    }

    private func build() {
        resetLayout()
        tileHelp.removeAll()
        addGap(6)
        addTitle("COLLECTION", size: 15)
        addGap(2)
        let unlocks = flow.campaign.itemUnlocks
        for (title, defs, kind) in CollectionViewController.groups() {
            let head = CRTKit.label(title, size: 12, color: CRT.gold, display: true)
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
                art.frame = CGRect(x: (cw - 44) / 2, y: 14, width: 44, height: 44)
                art.isUserInteractionEnabled = false
                tile.addSubview(art)
                if unlocked {
                    let name = CRTKit.label(def.label, size: 12, color: CRT.cardFace)
                    name.textAlignment = .center
                    name.numberOfLines = 2
                    name.frame = CGRect(x: 4, y: 80, width: cw - 8, height: 30)
                    tile.addSubview(name)
                } else {
                    let q = CRTKit.label("?", size: 13, color: CRT.cardFace)
                    q.textAlignment = .center
                    q.frame = CGRect(x: 0, y: 76, width: cw, height: 16)
                    tile.addSubview(q)
                    let hint = CRTKit.label(unlocks.hint(for: def), size: 12, color: CRT.muted)
                    hint.textAlignment = .center
                    hint.numberOfLines = 2
                    hint.frame = CGRect(x: 4, y: 91, width: cw - 8, height: 30)
                    tile.addSubview(hint)
                    if let gate = def.unlock {
                        let cur = min(unlocks.statValue(gate.stat), Int(gate.count))
                        let total = max(1, Int(gate.count))
                        // The recessed well + phosphor fill.
                        let bar = UIView(frame: CGRect(x: 8, y: 124, width: cw - 16, height: 8))
                        bar.backgroundColor = CRT.feltDeep
                        bar.layer.borderWidth = 1
                        bar.layer.borderColor = CRT.ink.cgColor
                        let fill = UIView(frame: CGRect(x: 1, y: 1, width: (bar.bounds.width - 2) * CGFloat(cur) / CGFloat(total), height: 6))
                        fill.backgroundColor = CRT.phosphor
                        bar.addSubview(fill)
                        tile.addSubview(bar)
                        let count = CRTKit.label("\(cur) / \(total)", size: 12, color: CRT.muted)
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
        flow.prompt.show(text, help: def.description, actions: [
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
/// art top-center, name (left) + rarity (right), the sticker scope line, the
/// registry description, and a ◀ N/total ▶ pager pinned to the bottom. The
/// shell never changes size while paging; only the content swaps. A scrim tap
/// closes (the web shows no ✕).
final class CollectionDetailView: UIView, UIGestureRecognizerDelegate {
    private static let panelW: CGFloat = 360
    private static let panelH: CGFloat = 300

    private let panel = PixelPanelView(face: CRT.feltMid, border: CRT.ink)
    private let artView = UIImageView()
    private let nameLabel = UILabel()
    private let tierLabel = UILabel()
    private let scopeLabel = UILabel()
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
        nameLabel.attributedText = CRTKit.attributed(def.label, size: 15, color: CRT.cardFace)
        tierLabel.attributedText = CRTKit.attributed(def.tier.uppercased(), size: 12,
                                                     color: CRT.cardFace.withAlphaComponent(0.7))
        scopeLabel.attributedText = scopeLine(kind: kind, def: def).map {
            CRTKit.attributed($0, size: 12, color: CRT.cardFace.withAlphaComponent(0.82))
        }
        let desc = NSMutableAttributedString(
            string: def.description, attributes: [.font: CRT.Font.of(13), .foregroundColor: CRT.cardFace])
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 4   // web line-height 1.34
        desc.addAttribute(.paragraphStyle, value: para, range: NSRange(location: 0, length: desc.length))
        descLabel.attributedText = desc
        descScroll.setContentOffset(.zero, animated: false)   // new page reads from the top
        countLabel.attributedText = CRTKit.attributed(
            "\(index + 1) / \(list.count)", size: 12, color: CRT.cardFace.withAlphaComponent(0.65))
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
        let hasScope = scopeLabel.attributedText != nil
        scopeLabel.frame = CGRect(x: 14, y: 119, width: w - 28, height: 16)
        let descY: CGFloat = hasScope ? 139 : 121
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
