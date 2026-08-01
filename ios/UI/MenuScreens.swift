import UIKit
import GameCore

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
        view.addSubview(scroll)
        scroll.addSubview(content)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        tissue.frame = view.bounds
        scroll.frame = view.bounds
        content.frame = CGRect(x: 0, y: view.safeAreaInsets.top, width: view.bounds.width, height: y)
        scroll.contentSize = CGSize(width: view.bounds.width,
                                    height: y + view.safeAreaInsets.top + view.safeAreaInsets.bottom + 24)
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

    private func build() {
        resetLayout()
        // The web menu, top to bottom: tagline · the gold "=" mark · the
        // two-line mixed-case wordmark · iconed buttons · footer bottom-LEFT.
        addGap(74)
        addText("HIGHER OR LOWER?", size: 12, color: CRT.cardFace)
        let tag = content.subviews.last as? UILabel
        tag?.attributedText = CRTKit.attributed("HIGHER OR LOWER?", size: 11, color: CRT.cardFace, display: true)
        tag?.textAlignment = .center
        addGap(28)
        let logo = UIImageView(image: MapArt.menuLogo(width: 64))
        logo.layer.magnificationFilter = .nearest
        logo.contentMode = .scaleAspectFit
        let holder = UIView()
        logo.frame = CGRect(x: (view.bounds.width - 64) / 2, y: 0, width: 64, height: 40)
        holder.addSubview(logo)
        addView(holder, height: 46)
        addGap(24)
        let line1 = CRTKit.label("Shoulda said", size: 24, color: CRT.cardFace, display: true)
        line1.textAlignment = .center
        addView(wrapCentered(line1), height: 30)
        let line2 = CRTKit.label("same", size: 24, color: CRT.phosphor, display: true, glow: true)
        line2.textAlignment = .center
        addView(wrapCentered(line2), height: 30)
        addGap(22)

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
        if !campaignOpen {
            addText("The CLIMB opens after your first Zen session.", size: 13)
            addGap(4)
        }
        addButton("HOW TO PLAY", icon: MapArt.menuIcon("search")) { [weak self] in self?.showManual() }
        addButton("STATS", icon: MapArt.menuIcon("bars")) { [weak self] in self?.flow.showStats() }
        addButton("COLLECTION", icon: MapArt.menuIcon("box")) { [weak self] in self?.flow.showCollection() }
        addButton("SETTINGS", icon: MapArt.menuIcon("gear")) { [weak self] in
            guard let self else { return }
            self.flow.setScreen(SettingsViewController(flow: self.flow))
        }
        addGap(12)
        // Footer: small, bottom-LEFT like the web build line.
        let foot = CRTKit.label("build ios-phase3 · CRT CASINO · web v5.74 parity", size: 12, color: CRT.muted)
        foot.frame = CGRect(x: 24, y: layoutY, width: view.bounds.width - 48, height: 16)
        content.addSubview(foot)
        addGap(22)
        view.setNeedsLayout()
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

    private func build() {
        resetLayout()
        addGap(150)
        addText("HIGHER OR LOWER?", size: 11, color: CRT.cardFace)
        addGap(20)
        let logo = UIImageView(image: MapArt.menuLogo(width: 64))
        logo.layer.magnificationFilter = .nearest
        logo.contentMode = .scaleAspectFit
        let holder = UIView()
        logo.frame = CGRect(x: (view.bounds.width - 64) / 2, y: 0, width: 64, height: 40)
        holder.addSubview(logo)
        addView(holder, height: 46)
        addGap(18)
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
        addGap(26)
        addButton("SOUND: \(Sound.shared.enabled ? "ON" : "OFF")", icon: MapArt.menuIcon("spark")) { [weak self] in
            Sound.shared.enabled.toggle()
            self?.build()
        }
        addButton("RESET PROGRESS", role: .danger, icon: MapArt.menuIcon("quit")) { [weak self] in
            self?.confirmReset()
        }
        addButton("BACK") { [weak self] in self?.flow.showMenu() }
        addGap(12)
        let foot = CRTKit.label("build ios-phase3 · CRT CASINO", size: 12, color: CRT.muted)
        foot.frame = CGRect(x: 24, y: layoutY, width: view.bounds.width - 48, height: 16)
        content.addSubview(foot)
        addGap(22)
        view.setNeedsLayout()
    }

    /// Double confirm — nothing but the sound pref survives.
    private func confirmReset() {
        flow.prompt.show("Reset ALL progress?", help: "Unlocks, stats and the saved climb are wiped.", actions: [
            .init("Cancel", role: .plain) { [weak self] in self?.flow.prompt.hide() },
            .init("Reset", role: .danger) { [weak self] in
                guard let self else { return }
                self.flow.prompt.show("Really reset everything?", help: "There is no undo.", actions: [
                    .init("Keep my progress", role: .plain) { self.flow.prompt.hide() },
                    .init("Wipe it all", role: .danger) {
                        self.flow.prompt.hide()
                        self.flow.resetAllProgress()
                    },
                ]) { self.flow.prompt.hide() }
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
    private var seedOpen = false

    override func viewDidLoad() {
        super.viewDidLoad()
        // Land on the furthest unlocked deck.
        deckIndex = GameFlowController.decks.lastIndex { deckUnlocked($0) } ?? 0
        // The corner back arrow + a swipe carousel, like the web.
        let back = PixelButtonView("←", role: .plain, fontSize: 16)
        back.onTap = { [weak self] in self?.flow.showMenu() }
        back.frame = CGRect(x: 8, y: 8, width: 34, height: 30)
        view.addSubview(back)
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
        addGap(4)
        let name = CRTKit.label(unlocked ? d.name : "???", size: 21,
                                color: unlocked ? CRT.cardFace : CRT.muted, display: true)
        name.textAlignment = .center
        name.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: 26)
        let nw = UIView(); nw.addSubview(name)
        addView(nw, height: 28)
        addText(unlocked ? d.sub : (d.unlockNote ?? "Locked"), size: 13)
        addGap(14)

        // Tier chips: selected = phosphor outline; locked = dim with the
        // 'Beat X' sub-line.
        let tierRow = UIView()
        let tw = (view.bounds.width - 100) / 3
        let subs = ["", "Beat Regular", "Beat Master"]
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
            chip.frame = CGRect(x: 50 + CGFloat(i) * (tw + 8), y: 0, width: tw, height: 42)
            tierRow.addSubview(chip)
            let tl = CRTKit.label(t.capitalized + (won ? " ✓" : ""), size: 13,
                                  color: open ? CRT.cardFace : CRT.disabledText)
            tl.textAlignment = .center
            tl.frame = CGRect(x: 0, y: open && i == 0 ? 11 : 5, width: tw, height: 16)
            tl.isUserInteractionEnabled = false
            chip.addSubview(tl)
            if i > 0 {
                let sub = UILabel()
                sub.attributedText = NSAttributedString(
                    string: subs[i],
                    attributes: [.font: UIFont(descriptor: CRT.Font.of(11).fontDescriptor.withSymbolicTraits(.traitItalic) ?? CRT.Font.of(11).fontDescriptor, size: 11),
                                 .foregroundColor: open ? CRT.muted : CRT.disabledText])
                sub.textAlignment = .center
                sub.frame = CGRect(x: 0, y: 21, width: tw, height: 14)
                sub.isUserInteractionEnabled = false
                chip.addSubview(sub)
            }
        }
        addView(tierRow, height: 48)
        addGap(16)

        addGap(6)
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
            field.attributedPlaceholder = CRTKit.attributed("ABC2345", size: 16, color: CRT.disabledText)
            field.textAlignment = .center
            field.frame = CGRect(x: 10, y: 6, width: view.bounds.width - 140 - 20, height: 30)
            seedPanel.addSubview(field)
            seedField = field
            seedPanel.frame = CGRect(x: 70, y: layoutY, width: view.bounds.width - 140, height: 42)
            content.addSubview(seedPanel)
            addGap(48)
            addText("A seeded climb is an EXHIBITION — nothing banks.", size: 12)
        }
        addGap(46)

        // Pager dots.
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
        addView(dots, height: 14)
        addGap(10)
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
            link.frame = CGRect(x: 0, y: layoutY, width: view.bounds.width, height: 22)
            content.addSubview(link)
            addGap(30)
        }
        view.setNeedsLayout()
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

    override func viewDidLoad() {
        super.viewDidLoad()
        buildCorner()
        build()
    }

    private func buildCorner() {
        let back = PixelButtonView("←", role: .plain, fontSize: 16)
        back.onTap = { [weak self] in self?.flow.showMenu() }
        back.frame = CGRect(x: 8, y: 8, width: 34, height: 30)
        view.addSubview(back)
    }

    private func build() {
        resetLayout()
        // The web zen select: title mid-page, three ROWS (display-font name,
        // "N cards · M piles", wins line), locked rows dimmed with the ladder
        // note, START enabled only once a row is picked.
        addGap(224)
        addTitle("ZEN", size: 15)
        addGap(6)
        let deckCards = [26, 39, 52]
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
            let sub = CRTKit.label("\(deckCards[safe: i] ?? 52) cards · \(z.piles) piles",
                                   size: 13, color: unlocked ? CRT.muted : CRT.disabledText)
            sub.textAlignment = .center
            sub.frame = CGRect(x: 0, y: 32, width: row.bounds.width, height: 16)
            sub.isUserInteractionEnabled = false
            row.addSubview(sub)
            let third: String
            if !unlocked {
                let prev = GameData.shared.difficulty.zenIds[safe: i - 1] ?? "easy"
                third = "Beat \(GameData.shared.difficulty.zen(prev).label) to unlock"
            } else if e.games == 0 {
                third = "no wins yet"
            } else {
                third = "\(e.wins) win\(e.wins == 1 ? "" : "s")"
            }
            let line3 = CRTKit.label(third, size: 12, color: unlocked ? CRT.cardFace : CRT.disabledText)
            line3.textAlignment = .center
            line3.frame = CGRect(x: 0, y: 48, width: row.bounds.width, height: 16)
            line3.isUserInteractionEnabled = false
            row.addSubview(line3)
            addGap(84)
        }
        addGap(18)
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
    override func viewDidLoad() {
        super.viewDidLoad()
        // Web `#collectionScreen`: corner ← back, display title, gold class
        // heads, 3-col pixel-panel tiles. Locked = ink silhouette + "?" + the
        // unlock hint with its live phosphor progress bar and "n / m" count.
        let back = PixelButtonView("←", role: .plain, fontSize: 16)
        back.onTap = { [weak self] in self?.flow.showMenu() }
        back.frame = CGRect(x: 8, y: 8, width: 34, height: 30)
        view.addSubview(back)
        build()
    }

    private func build() {
        resetLayout()
        addGap(10)
        addTitle("COLLECTION", size: 15)
        addGap(2)
        let data = GameData.shared
        let groups: [(String, [ItemDef], String)] = [
            ("STICKERS", data.items.stickers.filter { !$0.cursed }, "sticker"),
            ("PILLARS", data.items.pillars, "pillar"),
            ("BASES", data.items.bases, "base"),
            ("SAME-POWERS", data.items.samePowers, "samepower"),
            ("PACKS", data.items.packs, "pack"),
        ]
        let unlocks = flow.campaign.itemUnlocks
        for (title, defs, kind) in groups {
            let head = CRTKit.label(title, size: 12, color: CRT.gold, display: true)
            head.frame = CGRect(x: 14, y: layoutY, width: 300, height: 18)
            content.addSubview(head)
            addGap(26)
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
                    let hint = CRTKit.label(unlocks.hint(for: def), size: 11, color: CRT.muted)
                    hint.textAlignment = .center
                    hint.numberOfLines = 2
                    hint.frame = CGRect(x: 4, y: 92, width: cw - 8, height: 28)
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
                        let count = CRTKit.label("\(cur) / \(total)", size: 11, color: CRT.muted)
                        count.textAlignment = .center
                        count.frame = CGRect(x: 0, y: 134, width: cw, height: 13)
                        tile.addSubview(count)
                    }
                }
                if unlocked {
                    tile.addAction(UIAction { [weak self] _ in
                        self?.showDetail(def: def)
                    }, for: .touchUpInside)
                }
                grid.addSubview(tile)
                gy = tile.frame.maxY
            }
            addView(grid, height: gy + 6)
            addGap(8)
        }
        view.setNeedsLayout()
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

    private func showDetail(def: ItemDef) {
        flow.prompt.show("\(def.label) · \(def.tier.uppercased())", help: def.description, actions: [
            .init("OK", role: .plain) { [weak self] in self?.flow.prompt.hide() },
        ]) { [weak self] in self?.flow.prompt.hide() }
    }
}

// MARK: - How to Play

// MARK: - Stats

// (Lifetime stats now ride the StatsSheetView bottom sheet — see Sheets.swift.)
