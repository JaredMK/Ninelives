import UIKit
import GameCore

/// A shared base for the shell's menu-family screens: felt background, a
/// display-font title, a back button, content laid out top-down.
class MenuScreenBase: UIViewController {
    unowned let flow: GameFlowController
    let scroll = UIScrollView()
    let content = UIView()
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
        scroll.alwaysBounceVertical = true
        view.addSubview(scroll)
        scroll.addSubview(content)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
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
    func addButton(_ title: String, role: PixelButtonView.Role = .plain, height: CGFloat = 48,
                   enabled: Bool = true, handler: @escaping () -> Void) -> PixelButtonView {
        let b = PixelButtonView(title, role: role, fontSize: 17)
        b.isEnabled = enabled
        b.onTap = handler
        b.frame = CGRect(x: 40, y: y, width: view.bounds.width - 80, height: height)
        content.addSubview(b)
        y += height + 12
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
        addGap(36)
        // The character over the wordmark.
        let sprite = UIImageView(image: DeckCharacter.image(deckId: "pink", mood: .idle, scale: 5))
        sprite.contentMode = .scaleAspectFit
        sprite.layer.magnificationFilter = .nearest
        let holder = UIView()
        holder.addSubview(sprite)
        sprite.frame = CGRect(x: (view.bounds.width - 80) / 2, y: 0, width: 80, height: 80)
        addView(holder, height: 84)
        addTitle("SHOULDA SAID SAME", size: 17)
        addText("Ace high · suits don't matter", size: 14)
        addGap(18)

        let campaignOpen = flow.campaignUnlocked()
        if canContinue {
            addButton("CONTINUE CLIMB", role: .cta) { [weak self] in self?.resumeSave() }
        }
        if campaignOpen {
            addButton(canContinue ? "NEW CLIMB" : "START CLIMB",
                      role: canContinue ? .plain : .cta) { [weak self] in
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
        addButton("ZEN MODE", role: campaignOpen ? .plain : .cta) { [weak self] in
            self?.flow.showZenSelect()
        }
        if !campaignOpen {
            addText("The CLIMB opens after your first Zen session.", size: 13)
            addGap(4)
        }
        addButton("COLLECTION") { [weak self] in self?.flow.showCollection() }
        addButton("STATS") { [weak self] in self?.flow.showStats() }
        addButton("SOUND · \(Sound.shared.enabled ? "ON" : "OFF")") { [weak self] in
            Sound.shared.enabled.toggle()
            self?.build()
        }
        addButton("RESET PROGRESS", role: .plain) { [weak self] in self?.confirmReset() }
        addGap(16)
        addText("build ios-phase3 · CRT CASINO", size: 12)
        view.setNeedsLayout()
    }

    private func resumeSave() {
        // Re-enter through the boot path so the phase routing is shared.
        flow.resumeFromMenu()
    }

    /// Double confirm — only the sound pref survives.
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

    override func viewDidLoad() {
        super.viewDidLoad()
        // Land on the furthest unlocked deck.
        deckIndex = GameFlowController.decks.lastIndex { deckUnlocked($0) } ?? 0
        build()
    }

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
        addGap(14)
        addButton("← BACK", role: .plain, height: 38) { [weak self] in self?.flow.showMenu() }
        addTitle("CHOOSE YOUR CLIMBER", size: 13)

        let d = GameFlowController.decks[deckIndex]
        let unlocked = deckUnlocked(d)

        // The carousel: ‹ character › with name + tagline.
        let row = UIView()
        let left = PixelButtonView("‹", role: .plain, fontSize: 20)
        left.onTap = { [weak self] in self?.cycleDeck(-1) }
        left.frame = CGRect(x: 22, y: 40, width: 44, height: 60)
        row.addSubview(left)
        let right = PixelButtonView("›", role: .plain, fontSize: 20)
        right.onTap = { [weak self] in self?.cycleDeck(1) }
        right.frame = CGRect(x: view.bounds.width - 66, y: 40, width: 44, height: 60)
        row.addSubview(right)
        let sprite = UIImageView(image: DeckCharacter.image(deckId: d.id, mood: unlocked ? .happy : .idle,
                                                            scale: 6, tier: tiers[tierIndex]))
        sprite.contentMode = .scaleAspectFit
        sprite.layer.magnificationFilter = .nearest
        sprite.alpha = unlocked ? 1 : 0.25
        sprite.frame = CGRect(x: (view.bounds.width - 110) / 2, y: 6, width: 110, height: 110)
        row.addSubview(sprite)
        if !unlocked {
            let q = CRTKit.label("?", size: 44, color: CRT.muted, display: true)
            q.textAlignment = .center
            q.frame = CGRect(x: (view.bounds.width - 60) / 2, y: 30, width: 60, height: 60)
            row.addSubview(q)
        }
        // Pager dots.
        for (i, deck) in GameFlowController.decks.enumerated() {
            let dot = UIView(frame: CGRect(x: view.bounds.width / 2 - 30 + CGFloat(i) * 16, y: 122, width: 8, height: 8))
            dot.backgroundColor = i == deckIndex ? CRT.phosphor : CRT.feltMid
            dot.layer.borderWidth = 1
            dot.layer.borderColor = CRT.ink.cgColor
            _ = deck
            row.addSubview(dot)
        }
        addView(row, height: 134)

        addTitle(unlocked ? d.name : "???", size: 14, color: unlocked ? CRT.cardFace : CRT.muted)
        addText(unlocked ? d.sub : (d.unlockNote ?? "Locked"), size: 14)
        addGap(10)

        // Difficulty ladder.
        let tierRow = UIView()
        let tw = (view.bounds.width - 48 - 20) / 3
        for (i, t) in tiers.enumerated() {
            let open = unlocked && tierUnlocked(t, deck: d)
            let won = flow.campaign.deckUnlocks.wonWithTier(d.id, t)
            let b = PixelButtonView(t.uppercased() + (won ? " ✓" : ""),
                                    role: i == tierIndex ? .charged : .plain, fontSize: 13)
            b.isEnabled = open
            b.onTap = { [weak self] in
                self?.tierIndex = i
                self?.build()
            }
            b.frame = CGRect(x: 24 + CGFloat(i) * (tw + 10), y: 0, width: tw, height: 44)
            tierRow.addSubview(b)
        }
        addView(tierRow, height: 50)
        if tierIndex > 0, unlocked, !tierUnlocked(tiers[tierIndex], deck: d) {
            addText("Win \(tiers[tierIndex - 1].uppercased()) with \(d.name) first.", size: 13)
        }
        addGap(6)

        // Seed entry (exhibition rule).
        let seedPanel = PixelPanelView(face: CRT.feltMid, border: CRT.ink)
        let seedLabel = CRTKit.label("SEED (optional)", size: 13, color: CRT.muted)
        seedLabel.frame = CGRect(x: 10, y: 6, width: 200, height: 16)
        seedPanel.addSubview(seedLabel)
        let field = UITextField()
        field.font = CRT.Font.of(18)
        field.textColor = CRT.gold
        field.autocapitalizationType = .allCharacters
        field.autocorrectionType = .no
        field.attributedPlaceholder = CRTKit.attributed("e.g. ABC2345", size: 16, color: CRT.disabledText)
        field.frame = CGRect(x: 10, y: 24, width: view.bounds.width - 68 - 20, height: 30)
        seedPanel.addSubview(field)
        seedField = field
        let holder = UIView()
        seedPanel.frame = CGRect(x: 24, y: 0, width: view.bounds.width - 48, height: 62)
        holder.addSubview(seedPanel)
        addView(holder, height: 68)
        addText("A seeded climb is an EXHIBITION — nothing banks.", size: 12)
        addGap(8)

        addButton("START CLIMB", role: .cta, enabled: unlocked && tierUnlocked(tiers[tierIndex], deck: d)) { [weak self] in
            guard let self else { return }
            let d = GameFlowController.decks[self.deckIndex]
            let entered = self.seedField?.text?.trimmingCharacters(in: .whitespaces) ?? ""
            var seedU32: UInt32?
            if !entered.isEmpty {
                guard let decoded = SeedCode.decode(entered) else {
                    self.flow.prompt.show("That seed doesn't parse.",
                                          help: "Seeds are 7 characters, like ABC2345.", actions: [
                        .init("OK", role: .plain) { self.flow.prompt.hide() },
                    ]) { self.flow.prompt.hide() }
                    return
                }
                seedU32 = decoded
            }
            self.view.endEditing(true)
            self.flow.startCampaign(deckId: d.id, tier: self.tiers[self.tierIndex], seedU32: seedU32)
        }
        view.setNeedsLayout()
    }

    private func cycleDeck(_ dir: Int) {
        deckIndex = (deckIndex + dir + GameFlowController.decks.count) % GameFlowController.decks.count
        tierIndex = 0
        build()
    }
}

// MARK: - Zen select

final class ZenSelectViewController: MenuScreenBase {
    private var picked: String?

    override func viewDidLoad() {
        super.viewDidLoad()
        picked = GameData.shared.difficulty.zenIds.first
        build()
    }

    private func build() {
        resetLayout()
        addGap(14)
        addButton("← BACK", role: .plain, height: 38) { [weak self] in self?.flow.showMenu() }
        addTitle("ZEN MODE", size: 15)
        addText("One deck, one board, no items — pure survival.", size: 14)
        addGap(10)
        for id in GameData.shared.difficulty.zenIds {
            let z = GameData.shared.difficulty.zen(id)
            let e = flow.campaign.zenStats.get(id)
            let won = flow.campaign.zenUnlocks.won(id)
            let label = "\(z.label.uppercased())\(won ? " ✓" : "") · \(z.suitCount)♦ \(z.piles) PILES" +
                (e.games > 0 ? " · \(e.wins)/\(e.games)" : "")
            addButton(label, role: picked == id ? .charged : .plain) { [weak self] in
                self?.picked = id
                self?.build()
            }
        }
        addGap(10)
        addButton("START", role: .cta) { [weak self] in
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
        build()
    }

    private func build() {
        resetLayout()
        addGap(14)
        addButton("← BACK", role: .plain, height: 38) { [weak self] in self?.flow.showMenu() }
        addTitle("COLLECTION", size: 15)
        let data = GameData.shared
        let groups: [(String, [ItemDef], String)] = [
            ("STICKERS", data.items.stickers.filter { !$0.cursed }, "sticker"),
            ("PILLARS", data.items.pillars, "pillar"),
            ("BASES", data.items.bases, "base"),
            ("SAME-POWERS", data.items.samePowers, "samepower"),
            ("PACKS", data.items.packs, "pack"),
        ]
        let unlocks = flow.campaign.itemUnlocks
        var totalUnlocked = 0, total = 0
        for (_, defs, _) in groups {
            total += defs.count
            totalUnlocked += defs.filter { unlocks.isUnlocked($0) }.count
        }
        addText("\(totalUnlocked) of \(total) discovered", size: 14, color: CRT.gold)
        addGap(6)
        for (title, defs, kind) in groups {
            addText(title, size: 14, color: CRT.phosphor, align: .left)
            let grid = UIView()
            let cols = 4
            let cw = (view.bounds.width - 48 - CGFloat(cols - 1) * 10) / CGFloat(cols)
            var gy: CGFloat = 0
            for (i, def) in defs.enumerated() {
                let r = i / cols, c = i % cols
                let unlocked = unlocks.isUnlocked(def)
                let tile = UIControl(frame: CGRect(x: 24 + CGFloat(c) * (cw + 10), y: CGFloat(r) * (cw + 26),
                                                   width: cw, height: cw + 20))
                let art = UIImageView(image: ItemArt.forSlot(kind: kind, id: def.id, card: nil,
                                                             deckId: flow.campaign.deckId))
                art.contentMode = .scaleAspectFit
                art.layer.magnificationFilter = .nearest
                art.frame = CGRect(x: 4, y: 0, width: cw - 8, height: cw - 8)
                // Locked = silhouette: the art dims to a black shape.
                if !unlocked {
                    art.alpha = 0.18
                    let q = CRTKit.label("?", size: 22, color: CRT.muted)
                    q.textAlignment = .center
                    q.frame = CGRect(x: 0, y: (cw - 30) / 2, width: cw, height: 24)
                    tile.addSubview(q)
                }
                tile.addSubview(art)
                let name = CRTKit.label(unlocked ? String(def.label.prefix(10)) : "???",
                                        size: 12, color: unlocked ? CRT.cardFace : CRT.disabledText)
                name.textAlignment = .center
                name.frame = CGRect(x: 0, y: cw - 6, width: cw, height: 14)
                tile.addSubview(name)
                tile.addAction(UIAction { [weak self] _ in
                    self?.showDetail(def: def, unlocked: unlocked)
                }, for: .touchUpInside)
                grid.addSubview(tile)
                gy = tile.frame.maxY
            }
            addView(grid, height: gy + 4)
        }
        view.setNeedsLayout()
    }

    private func showDetail(def: ItemDef, unlocked: Bool) {
        if unlocked {
            flow.prompt.show("\(def.label) · \(def.tier.uppercased())", help: def.description, actions: [
                .init("OK", role: .plain) { [weak self] in self?.flow.prompt.hide() },
            ]) { [weak self] in self?.flow.prompt.hide() }
        } else {
            // Locked: the unlock hint + live progress.
            let u = flow.campaign.itemUnlocks
            let hint = u.hint(for: def)
            var progress = ""
            if let gate = def.unlock {
                progress = " (\(u.statValue(gate.stat))/\(Int(gate.count)))"
            }
            flow.prompt.show("???", help: hint + progress, actions: [
                .init("OK", role: .plain) { [weak self] in self?.flow.prompt.hide() },
            ]) { [weak self] in self?.flow.prompt.hide() }
        }
    }
}

// MARK: - Stats

final class StatsViewController: MenuScreenBase {
    override func viewDidLoad() {
        super.viewDidLoad()
        build()
    }

    private func build() {
        resetLayout()
        addGap(14)
        addButton("← BACK", role: .plain, height: 38) { [weak self] in self?.flow.showMenu() }
        addTitle("LIFETIME STATS", size: 14)
        let s = flow.campaign.stats.get()
        let rows: [(String, String)] = [
            ("Climbs played", "\(s.gamesPlayed)"),
            ("Climbs won", "\(s.campaignsWon)"),
            ("Deals cleared", "\(s.runsCleared)"),
            ("Best climb score", "\(s.bestCampaignScore)"),
            ("Best endless score", "\(s.bestEndlessScore)"),
            ("Deepest endless stage", "\(s.bestEndless)"),
            ("Cards flipped", "\(s.lifetimeCardsFlipped)"),
            ("Correct guesses", "\(s.lifetimeCorrectGuesses) / \(s.lifetimeGuesses)"),
            ("Coins earned", "\(s.lifetimeDopamine)"),
            ("Bosses beaten", "\(s.bossesBeaten)"),
            ("Cards buried", "\(s.cardsBuried)"),
            ("Sames called", "\(s.samesCalled) (\(s.correctSames) hit)"),
            ("Jokers played", "\(s.jokersPlayed)"),
            ("Piles lost", "\(s.pilesLost)"),
        ]
        for (label, value) in rows {
            let row = UIView()
            let l = CRTKit.label(label, size: 15, color: CRT.muted)
            l.frame = CGRect(x: 28, y: 0, width: 220, height: 20)
            row.addSubview(l)
            let v = CRTKit.label(value, size: 15, color: CRT.cardFace)
            v.textAlignment = .right
            v.frame = CGRect(x: view.bounds.width - 178, y: 0, width: 150, height: 20)
            row.addSubview(v)
            addView(row, height: 24)
        }
        // Zen block.
        addGap(10)
        addText("ZEN", size: 14, color: CRT.phosphor, align: .left)
        for id in GameData.shared.difficulty.zenIds {
            let e = flow.campaign.zenStats.get(id)
            let row = UIView()
            let l = CRTKit.label(GameData.shared.difficulty.zen(id).label, size: 15, color: CRT.muted)
            l.frame = CGRect(x: 28, y: 0, width: 200, height: 20)
            row.addSubview(l)
            let v = CRTKit.label("\(e.wins)/\(e.games) won · \(e.cardsFlipped) flipped",
                                 size: 15, color: CRT.cardFace)
            v.textAlignment = .right
            v.frame = CGRect(x: view.bounds.width - 238, y: 0, width: 210, height: 20)
            row.addSubview(v)
            addView(row, height: 24)
        }
        addGap(12)
        addButton("RESET STATS", role: .danger, height: 40) { [weak self] in
            guard let self else { return }
            self.flow.prompt.show("Reset lifetime stats?", help: "Unlock progress derives from stats.", actions: [
                .init("Cancel", role: .plain) { self.flow.prompt.hide() },
                .init("Reset", role: .danger) {
                    self.flow.prompt.hide()
                    self.flow.campaign.stats.reset()
                    self.build()
                },
            ]) { self.flow.prompt.hide() }
        }
        view.setNeedsLayout()
    }
}
