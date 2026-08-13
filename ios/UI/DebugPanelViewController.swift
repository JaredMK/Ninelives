import UIKit
import GameCore

/// The in-app debug panel (playtesting) — a port of the web's debug overlay
/// (markup index.html:6372-6468). Entry: 7 quick taps on the build footer
/// (MenuScreens) or the DEBUG menu button; GameFlowController presents it as a
/// child VC over whatever screen is up (menu / map / store / deal).
///
/// Sections, all riding EXISTING campaign/engine mutators so the normal save
/// path keeps working (debug coins/grants persisting is desired):
///   DEAL     — seed + next-draw display, peek 6, force-next-card rank grid,
///              deck → 1, WIN NOW / LOSE NOW, autopilot + fps toggles
///              (greyed out when no deal is live)
///   ECONOMY  — +10 / +50 / +100 coins
///   DECK     — +1 / +5 / +10 random cards, or one exact suit+rank pick
///   OLD JOKER— arm any one of his visits on the next ? node (and convert a
///              reachable node into a ? so there is one to walk onto)
///   GRANTS   — +Sticker / +Pillar / +Base (to inventory) / equip Same-Power
///   META     — unlock everything, map jump, reset all progress, debug off,
///              build version
final class DebugPanelViewController: UIViewController, UIGestureRecognizerDelegate {

    private unowned let flow: GameFlowController
    private let panel = UIView()
    private let headLabel = UILabel()
    private let closeButton = UIButton(type: .custom)
    private let readoutLabel = UILabel()
    private let scroll = UIScrollView()
    private let content = UIView()
    private var y: CGFloat = 0
    private var builtWidth: CGFloat = 0
    private var entered = false

    /// Grant-selector state (survives rebuilds).
    private var grantIdx = ["sticker": 0, "pillar": 0, "base": 0, "samepower": 0]
    /// Deck-grant card picker state (suit + rank index), also rebuild-proof.
    private var cardIdx = ["suit": 0, "rank": 0]
    /// Old Joker offer-picker index (survives rebuilds).
    private var jokerIdx = 0
    private var mysteryIdx = 0

    init(flow: GameFlowController) {
        self.flow = flow
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override var prefersStatusBarHidden: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = CRT.ink.withAlphaComponent(0.72)
        // Scrim-only dismissal (the SheetView idiom): the recognizer never
        // receives touches on the panel's controls.
        let tap = UITapGestureRecognizer(target: self, action: #selector(scrimTapped(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        view.addGestureRecognizer(tap)

        panel.backgroundColor = CRT.feltMid
        panel.layer.borderWidth = CRT.px
        panel.layer.borderColor = CRT.ink.cgColor
        view.addSubview(panel)

        headLabel.attributedText = CRTKit.attributed("🐞 DEBUG", size: 14, color: CRT.phosphor,
                                                     display: true, glow: true)
        panel.addSubview(headLabel)

        closeButton.setAttributedTitle(CRTKit.attributed("×", size: 18, color: CRT.cardFace), for: .normal)
        closeButton.backgroundColor = CRT.feltDeep
        closeButton.layer.borderWidth = CRT.px
        closeButton.layer.borderColor = CRT.ink.cgColor
        closeButton.addAction(UIAction { [weak self] _ in self?.close() }, for: .touchUpInside)
        panel.addSubview(closeButton)

        readoutLabel.numberOfLines = 2
        panel.addSubview(readoutLabel)

        scroll.alwaysBounceVertical = true
        panel.addSubview(scroll)
        scroll.addSubview(content)
        note("ride the buttons; everything persists through the normal save")
    }

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        // The sheets' rise-from-the-bottom entrance.
        guard parent != nil, !entered else { return }
        entered = true
        view.layoutIfNeeded()
        panel.transform = CGAffineTransform(translationX: 0, y: panel.frame.height)
        view.alpha = 0.4
        UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseOut]) {
            self.panel.transform = .identity
            self.view.alpha = 1
        }
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        touch.view === view
    }

    @objc private func scrimTapped(_ g: UITapGestureRecognizer) {
        if !panel.frame.contains(g.location(in: view)) { close() }
    }

    private func close() {
        UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseIn]) {
            self.panel.transform = CGAffineTransform(translationX: 0, y: self.panel.frame.height)
            self.view.alpha = 0
        } completion: { _ in
            self.flow.dismissDebugPanel()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let w = min(view.bounds.width, 460)
        let safeBottom = view.safeAreaInsets.bottom
        if builtWidth != w {
            builtWidth = w
            build()
        }
        let headH: CGFloat = 44 + 34   // head row + readout
        let panelH = min(view.bounds.height * 0.86, headH + y + 12 + safeBottom)
        // +px: the bottom border rides off-screen (the sheets' bottom-edge trick).
        panel.frame = CGRect(x: (view.bounds.width - w) / 2, y: view.bounds.height - panelH,
                             width: w, height: panelH + CRT.px)
        headLabel.frame = CGRect(x: 16, y: 12, width: w - 70, height: 30)
        closeButton.frame = CGRect(x: w - 46, y: 10, width: 30, height: 30)
        readoutLabel.frame = CGRect(x: 16, y: 42, width: w - 32, height: 34)
        scroll.frame = CGRect(x: 16, y: 80, width: w - 32, height: panel.frame.height - 80 - 12 - safeBottom)
        content.frame = CGRect(x: 0, y: 0, width: scroll.bounds.width, height: y)
        scroll.contentSize = CGSize(width: scroll.bounds.width, height: y)
    }

    // MARK: - Engine access

    /// The live deal's engine, or nil when no deal is on screen / it's over.
    /// DealController keeps its engine private — reflection rather than
    /// widening the production API for a debug-only accessor.
    private func liveEngine() -> GameEngine? {
        guard let c = flow.debugLiveDeal() else { return nil }
        return Mirror(reflecting: c).children.first { $0.label == "engine" }?.value as? GameEngine
    }

    /// Feedback line (the web's #debugPeekOut).
    private func note(_ text: String) {
        readoutLabel.attributedText = CRTKit.attributed(text, size: 14, color: CRT.gold)
    }

    // MARK: - Layout helpers

    private var contentWidth: CGFloat { builtWidth - 32 }

    private struct Btn {
        let title: String
        var role: PixelButtonView.Role = .plain
        var enabled = true
        let action: () -> Void
        init(_ title: String, role: PixelButtonView.Role = .plain, enabled: Bool = true,
             action: @escaping () -> Void) {
            self.title = title; self.role = role; self.enabled = enabled; self.action = action
        }
    }

    private func header(_ text: String) {
        let l = CRTKit.label(text.uppercased(), size: 14, color: CRT.gold, display: true)
        l.frame = CGRect(x: 0, y: y, width: contentWidth, height: 18)
        content.addSubview(l)
        y += 26
    }

    private func buttonRow(_ btns: [Btn], height: CGFloat = 36) {
        let gap: CGFloat = 8
        let bw = (contentWidth - gap * CGFloat(btns.count - 1)) / CGFloat(btns.count)
        for (i, spec) in btns.enumerated() {
            let b = PixelButtonView(spec.title, role: spec.role, fontSize: 14)
            b.isEnabled = spec.enabled
            b.onTap = spec.action
            b.frame = CGRect(x: CGFloat(i) * (bw + gap), y: y, width: bw, height: height)
            content.addSubview(b)
        }
        y += height + 8
    }

    private func textLine(_ text: String, color: UIColor = CRT.muted) {
        let l = CRTKit.label(text, size: 14, color: color)
        l.frame = CGRect(x: 0, y: y, width: contentWidth, height: 18)
        content.addSubview(l)
        y += 22
    }

    // MARK: - Build

    private func build() {
        content.subviews.forEach { $0.removeFromSuperview() }
        y = 0
        buildDealSection()
        buildEconomySection()
        buildDeckSection()
        buildJokerSection()
        buildGrantsSection()
        buildMetaSection()
        content.frame = CGRect(x: 0, y: 0, width: contentWidth, height: y)
        scroll.contentSize = CGSize(width: contentWidth, height: y)
    }

    private func buildDealSection() {
        header("Deal")
        let engine = liveEngine()
        let dealOn = engine != nil
        if let engine {
            let next = engine.deck.peek(1).first?.label ?? "—"
            textLine("SEED \(flow.seedShareString()) · NEXT \(next)",
                     color: CRT.cardFace)
        } else {
            textLine("no live deal; deal actions greyed out", color: CRT.disabledText)
        }
        // Force next card: the web's rank row (debugRanks), values 2..14.
        let ranks1 = [(2, "2"), (3, "3"), (4, "4"), (5, "5"), (6, "6"), (7, "7"), (8, "8")]
        let ranks2 = [(9, "9"), (10, "10"), (11, "J"), (12, "Q"), (13, "K"), (14, "A")]
        for ranks in [ranks1, ranks2] {
            buttonRow(ranks.map { (v, name) in
                Btn(name, enabled: dealOn) { [weak self] in self?.forceNext(v) }
            }, height: 30)
        }
        buttonRow([
            Btn("peek 6", enabled: dealOn) { [weak self] in self?.peek6() },
            Btn("deck → 1", enabled: dealOn) { [weak self] in self?.trimDeck() },
        ], height: 32)
        buttonRow([
            Btn("win now", role: .cta, enabled: dealOn) { [weak self] in self?.winNow() },
            Btn("lose now", role: .danger, enabled: dealOn) { [weak self] in self?.loseNow() },
        ], height: 36)
        // Global toggles: useful from anywhere, so never greyed out.
        buttonRow([
            Btn("autopilot: \(flow.debugAutopilotOn() ? "on" : "off")",
                role: flow.debugAutopilotOn() ? .charged : .plain) { [weak self] in
                guard let self else { return }
                self.flow.setDebugAutopilot(!self.flow.debugAutopilotOn())
                self.note("autopilot \(self.flow.debugAutopilotOn() ? "on; plays every live deal" : "off")")
                self.build()
            },
            Btn("fps hud: \(flow.debugFPSOn() ? "on" : "off")",
                role: flow.debugFPSOn() ? .charged : .plain) { [weak self] in
                guard let self else { return }
                self.flow.setDebugFPS(!self.flow.debugFPSOn())
                self.note("fps hud \(self.flow.debugFPSOn() ? "on" : "off")")
                self.build()
            },
        ], height: 32)
        y += 6
    }

    private func buildEconomySection() {
        header("Economy")
        buttonRow([10, 50, 100].map { n in
            Btn("+\(n) ◉", role: .gold) { [weak self] in
                guard let self else { return }
                self.flow.campaign.addCoins(n)
                self.flow.debugPersist()
                self.note("+\(n) ◉, balance \(self.flow.campaign.getCoins())")
            }
        }, height: 34)
        textLine("balance ◉ \(flow.campaign.getCoins())")
        y += 6
    }

    /// Cards straight into the deck — the bulk roll for "what does a fat deck
    /// play like", and the exact pick for reproducing one specific card.
    /// Both mint through the campaign's normal pack path, so the deck stays
    /// serialisable and a save written after this still loads.
    private func buildDeckSection() {
        header("Deck")
        textLine("deck: \(flow.campaign.deckSize()) cards", color: CRT.cardFace)
        buttonRow([1, 5, 10].map { n in
            Btn("+\(n) random", role: .gold) { [weak self] in
                guard let self else { return }
                let ids = self.flow.campaign.debugAddRandomCards(n)
                self.flow.debugPersist()
                self.note("+\(ids.count) random → deck \(self.flow.campaign.deckSize())")
                self.build()   // the deck-size line above is now stale
            }
        }, height: 32)
        cardPickRow()
        y += 6
    }

    /// [◀][suit][▶] [◀][rank][▶] over a full-width add — the same stepper
    /// idiom as the grant rows, because a phone has no room for two dropdowns.
    private func cardPickRow() {
        let suits = DeckManager.suits.map(\.symbol)
        let ranks = DeckManager.ranks   // (label, value) — Ace high, 2…A
        let w = contentWidth
        let half = (w - 8) / 2
        let rowY = y
        let suitLabel = UILabel(), rankLabel = UILabel()
        var steppers: [PixelButtonView] = []
        func stepper(_ title: String, x: CGFloat, _ tap: @escaping () -> Void) {
            let b = PixelButtonView(title, role: .plain, fontSize: 14)
            b.frame = CGRect(x: x, y: rowY, width: 30, height: 34)
            b.onTap = tap
            steppers.append(b)
            content.addSubview(b)
        }
        let refresh = { [weak self] in
            guard let self else { return }
            let s = suits[self.cardIdx["suit", default: 0] % suits.count]
            let r = ranks[self.cardIdx["rank", default: 0] % ranks.count]
            suitLabel.attributedText = CRTKit.attributed(s, size: 16, color: CRT.cardFace)
            rankLabel.attributedText = CRTKit.attributed(r.label, size: 16, color: CRT.cardFace)
        }
        let step = { [weak self] (key: String, by: Int, count: Int) in
            guard let self else { return }
            self.cardIdx[key] = (self.cardIdx[key, default: 0] + by + count) % count
            refresh()
        }
        stepper("◀", x: 0) { step("suit", -1, suits.count) }
        stepper("▶", x: half - 30) { step("suit", 1, suits.count) }
        stepper("◀", x: half + 8) { step("rank", -1, ranks.count) }
        stepper("▶", x: w - 30) { step("rank", 1, ranks.count) }
        suitLabel.frame = CGRect(x: 32, y: rowY, width: half - 64, height: 34)
        rankLabel.frame = CGRect(x: half + 40, y: rowY, width: half - 72, height: 34)
        for l in [suitLabel, rankLabel] { l.textAlignment = .center; content.addSubview(l) }
        refresh()
        y += 40
        buttonRow([
            Btn("+ card", role: .gold) { [weak self] in
                guard let self else { return }
                let s = suits[self.cardIdx["suit", default: 0] % suits.count]
                let r = ranks[self.cardIdx["rank", default: 0] % ranks.count]
                guard self.flow.campaign.debugAddCard(suit: s, rank: r.value) != nil else {
                    self.note("\(r.label)\(s) rejected; not a suit this deck uses")
                    return
                }
                self.flow.debugPersist()
                self.note("\(r.label)\(s) → deck \(self.flow.campaign.deckSize())")
                self.build()
            },
        ], height: 34)
    }

    /// THE OLD JOKER: arm any one of his visits on the next ? node. Reaching
    /// them naturally means waiting on a 50% appearance roll AND satisfying
    /// that offer's preconditions — which for Collect and the drink return
    /// means running a whole marker or drink first.
    private func buildJokerSection() {
        header("Old Joker")
        let keys = OldJokerConfig.offerKeys + ["collect", "thirstReturn", "thirstAmbush"]
        let w = contentWidth
        let rowY = y
        let prev = PixelButtonView("◀", role: .plain, fontSize: 14)
        let next = PixelButtonView("▶", role: .plain, fontSize: 14)
        let armB = PixelButtonView("arm next ?", role: .gold, fontSize: 14)
        let name = UILabel()
        prev.frame = CGRect(x: 0, y: rowY, width: 30, height: 34)
        next.frame = CGRect(x: w - 108 - 8 - 30, y: rowY, width: 30, height: 34)
        armB.frame = CGRect(x: w - 108, y: rowY, width: 108, height: 34)
        name.frame = CGRect(x: 38, y: rowY, width: w - 76 - 116, height: 34)
        let refresh = { [weak self] in
            guard let self else { return }
            let i = self.jokerIdx % keys.count
            name.attributedText = CRTKit.attributed(keys[i], size: 14, color: CRT.cardFace)
        }
        prev.onTap = { [weak self] in
            guard let self else { return }
            self.jokerIdx = (self.jokerIdx - 1 + keys.count) % keys.count
            refresh()
        }
        next.onTap = { [weak self] in
            guard let self else { return }
            self.jokerIdx = (self.jokerIdx + 1) % keys.count
            refresh()
        }
        armB.onTap = { [weak self] in
            guard let self else { return }
            let key = keys[self.jokerIdx % keys.count]
            self.flow.campaign.debugForceJoker(key)
            // Collect and the drink return read live state, so give them
            // something to read — otherwise they arm and resolve to nothing.
            if key == "collect", self.flow.campaign.jokerDebt == 0 {
                self.flow.campaign.setJokerDebt(24)
            }
            self.flow.debugPersist()
            self.note("\(key) armed; walk onto the next ? node")
        }
        refresh()
        content.addSubview(prev)
        content.addSubview(next)
        content.addSubview(armB)
        content.addSubview(name)
        y += 42
        buttonRow([
            Btn("disarm") { [weak self] in
                self?.flow.campaign.debugForceJoker(nil)
                self?.note("the next ? rolls normally again")
            },
            Btn("+? node here", role: .plain) { [weak self] in
                guard let self else { return }
                self.note(self.flow.debugMakeNextNodeMystery()
                          ? "a reachable node is now a ?"
                          : "no reachable node to convert")
            },
        ], height: 32)
        y += 6
        buildMysterySection()
    }

    /// THE QUEEN + THE TWO: arm any plain mystery outcome on the next ? node.
    /// Arming one skips the Old Joker's takeover roll, and the state each
    /// outcome guards on is primed so it lands instead of folding to a Toll.
    private func buildMysterySection() {
        header("Beheaded Queen & Just a Two")
        let keys = MysteryConfig.queenKeys.map { ("♛", $0) }
                 + MysteryConfig.twoKeys.map { ("2", $0) }
        let w = contentWidth
        let rowY = y
        let prev = PixelButtonView("◀", role: .plain, fontSize: 14)
        let next = PixelButtonView("▶", role: .plain, fontSize: 14)
        let armB = PixelButtonView("arm next ?", role: .gold, fontSize: 14)
        let name = UILabel()
        prev.frame = CGRect(x: 0, y: rowY, width: 30, height: 34)
        next.frame = CGRect(x: w - 108 - 8 - 30, y: rowY, width: 30, height: 34)
        armB.frame = CGRect(x: w - 108, y: rowY, width: 108, height: 34)
        name.frame = CGRect(x: 38, y: rowY, width: w - 76 - 116, height: 34)
        let refresh = { [weak self] in
            guard let self else { return }
            let (who, key) = keys[self.mysteryIdx % keys.count]
            name.attributedText = CRTKit.attributed("\(who) \(key)", size: 14, color: CRT.cardFace)
        }
        prev.onTap = { [weak self] in
            guard let self else { return }
            self.mysteryIdx = (self.mysteryIdx - 1 + keys.count) % keys.count
            refresh()
        }
        next.onTap = { [weak self] in
            guard let self else { return }
            self.mysteryIdx = (self.mysteryIdx + 1) % keys.count
            refresh()
        }
        armB.onTap = { [weak self] in
            guard let self else { return }
            let (_, key) = keys[self.mysteryIdx % keys.count]
            self.flow.campaign.debugForceMystery(key)
            self.flow.debugPersist()
            self.note("\(key) armed; walk onto the next ? node")
        }
        refresh()
        content.addSubview(prev)
        content.addSubview(next)
        content.addSubview(armB)
        content.addSubview(name)
        y += 42
        buttonRow([
            Btn("disarm") { [weak self] in
                self?.flow.campaign.debugForceMystery(nil)
                self?.note("the next ? rolls normally again")
            },
            Btn("+? node here", role: .plain) { [weak self] in
                guard let self else { return }
                self.note(self.flow.debugMakeNextNodeMystery()
                          ? "a reachable node is now a ?"
                          : "no reachable node to convert")
            },
        ], height: 32)
        y += 6
    }

    private func buildGrantsSection() {
        header("Grants")
        let items = GameData.shared.items
        grantRow(kind: "sticker", items: items.stickers.filter { !$0.cursed },
                 buttonTitle: "+ sticker") { [weak self] id, label in
            guard let self else { return }
            self.flow.campaign.debugGrantSticker(id)
            self.flow.debugPersist()
            self.note("\(label) → sticker inventory")
        }
        // Pillar/Base placement needs a column pick; granting into the
        // inventory (then placing from the HUD) is the simplest working path.
        grantRow(kind: "pillar", items: items.pillars,
                 buttonTitle: "+ pillar") { [weak self] id, label in
            guard let self else { return }
            self.flow.campaign.debugGrantPillar(id)
            self.flow.debugPersist()
            self.note("\(label) → pillar inventory (place it from the tray)")
        }
        grantRow(kind: "base", items: items.bases,
                 buttonTitle: "+ base") { [weak self] id, label in
            guard let self else { return }
            self.flow.campaign.debugGrantBase(id)
            self.flow.debugPersist()
            self.note("\(label) → base inventory (place it from the tray)")
        }
        grantRow(kind: "samepower", items: items.samePowers,
                 buttonTitle: "equip sp") { [weak self] id, label in
            guard let self else { return }
            self.flow.campaign.debugGrantSamePower(id)
            if self.flow.campaign.equipSamePower(id) {
                self.flow.debugPersist()
                self.note("\(label) equipped")
            } else {
                self.note("equip failed for \(label)")
            }
        }
        y += 6
    }

    /// [◀][item label][▶][grant] — the phone-first stand-in for the web's
    /// debug <select> dropdowns.
    private func grantRow(kind: String, items: [ItemDef], buttonTitle: String,
                          grant: @escaping (String, String) -> Void) {
        guard !items.isEmpty else { return }
        let w = contentWidth
        let rowY = y
        let prev = PixelButtonView("◀", role: .plain, fontSize: 14)
        let next = PixelButtonView("▶", role: .plain, fontSize: 14)
        let grantB = PixelButtonView(buttonTitle, role: .gold, fontSize: 14)
        let name = UILabel()
        prev.frame = CGRect(x: 0, y: rowY, width: 30, height: 34)
        next.frame = CGRect(x: w - 96 - 8 - 30, y: rowY, width: 30, height: 34)
        grantB.frame = CGRect(x: w - 96, y: rowY, width: 96, height: 34)
        name.frame = CGRect(x: 38, y: rowY, width: w - 76 - 112, height: 34)
        let refresh = { [weak self] in
            guard let self else { return }
            let i = self.grantIdx[kind, default: 0] % items.count
            name.attributedText = CRTKit.attributed(items[i].label, size: 14, color: CRT.cardFace)
        }
        prev.onTap = { [weak self] in
            guard let self else { return }
            self.grantIdx[kind] = (self.grantIdx[kind, default: 0] - 1 + items.count) % items.count
            refresh()
        }
        next.onTap = { [weak self] in
            guard let self else { return }
            self.grantIdx[kind] = (self.grantIdx[kind, default: 0] + 1) % items.count
            refresh()
        }
        grantB.onTap = { [weak self] in
            guard let self else { return }
            let i = self.grantIdx[kind, default: 0] % items.count
            grant(items[i].id, items[i].label)
        }
        refresh()
        content.addSubview(prev)
        content.addSubview(next)
        content.addSubview(grantB)
        content.addSubview(name)
        y += 42
    }

    private func buildMetaSection() {
        header("Meta")
        buttonRow([
            Btn("🔓 unlock everything", role: .charged) { [weak self] in self?.unlockEverything() },
        ], height: 36)
        buildMapJump()
        buttonRow([
            Btn("reset all progress", role: .danger) { [weak self] in self?.flow.debugConfirmResetAll() },
        ], height: 36)
        buttonRow([
            Btn("debug off") { [weak self] in self?.flow.setDebugAccess(false) },
        ], height: 32)
        textLine(BuildStamp.line)
    }

    /// MAP JUMP (the web's debugJumpSel as a list): every node of the current
    /// climb's map, bottom → top. Tap to teleport — the node becomes the next
    /// PLAYABLE one; tap it on the map to play it.
    private func buildMapJump() {
        header("Map jump")
        guard let m = flow.campaign.runMap else {
            textLine("(no climb in progress)", color: CRT.disabledText)
            y += 4
            return
        }
        let legal = Set(flow.campaign.legalNextNodes().map(\.id))
        let pos = flow.campaign.nodePos
        let nodes = m.nodes.sorted { ($0.row, $0.id) < ($1.row, $1.id) }
        for n in nodes {
            var title = "#\(n.id) · r\(n.row) · \(n.type)"
            if let p = n.piles { title += " \(p)p" }
            else if let pc = n.packCount, pc > 0 { title += " +\(pc)" }
            if n.id == pos { title += " · HERE" }
            else if legal.contains(n.id) { title = "▸ " + title }
            let id = n.id
            buttonRow([
                Btn(title, role: n.id == pos ? .charged : .plain) { [weak self] in
                    guard let self else { return }
                    if !self.flow.debugMapJump(to: id) {
                        self.note("map jump refused mid-deal; finish the deal first")
                    }
                },
            ], height: 28)
        }
        y += 4
    }

    // MARK: - Deal actions

    private func forceNext(_ value: Int) {
        guard let engine = liveEngine() else { return }
        if let card = engine.debug.setNextCard(value) {
            note("next draw forced → \(card.label)")
        } else {
            note("force failed; no live deal")
        }
    }

    private func peek6() {
        guard let engine = liveEngine() else { return }
        let cards = engine.deck.peek(6).map(\.label).joined(separator: " ")
        note(cards.isEmpty ? "deck is empty" : "next 6: \(cards)")
    }

    private func trimDeck() {
        guard let engine = liveEngine() else { return }
        engine.debug.trimDeck(to: 1)
        note("deck trimmed to 1 card")
    }

    private func winNow() {
        guard let engine = liveEngine() else { return }
        engine.debug.drainDeck()
        engine.debug.evaluate()
        close()   // the deal-end presentation takes the screen
    }

    private func loseNow() {
        guard let engine = liveEngine() else { return }
        engine.debug.loseNow()
        close()
    }

    // MARK: - Meta actions

    /// The web's debugUnlockAll (index.html:22741-22752): flood every gate-read
    /// stat, credit the Zen ladder, record a win for every deck×tier, open the
    /// campaign gate, then stamp the item known-set SILENTLY (no pop spam).
    private func unlockEverything() {
        let c = flow.campaign
        var need: [String: Double] = [:]
        for def in c.itemUnlocks.allDefs() {
            if let u = def.unlock { need[u.stat] = max(need[u.stat] ?? 0, u.count) }
        }
        var s = c.stats.get()
        if let n = need["dealsSurvived"] { s.runsCleared = max(s.runsCleared, Int(n)) }
        if let n = need["runsPlayed"] { s.gamesPlayed = max(s.gamesPlayed, Int(n)) }
        if let n = need["runsWon"] { s.campaignsWon = max(s.campaignsWon, Int(n)) }
        if let n = need["endlessStagesReached"] { s.bestEndless = max(s.bestEndless, Int(n)) }
        if let n = need["coinsEarnedLifetime"] { s.lifetimeDopamine = max(s.lifetimeDopamine, Int(n)) }
        for key in StatsRecord.unlockCounters {
            if let n = need[key] { s[key] = max(s[key], Int(n)) }
        }
        c.stats.put(s)
        // The Zen ladder: the web credits 5 games + 5 wins per difficulty; also
        // meet any higher item-gate thresholds (zenGamesPlayed / zen*Won).
        for id in DifficultyData.zenIds {
            var e = c.zenStats.get(id)
            let winKey = "zen" + id.prefix(1).uppercased() + id.dropFirst() + "Won"
            e.games = max(e.games + 5, Int(need["zenGamesPlayed"] ?? 0))
            e.wins = max(e.wins + 5, Int(need[winKey] ?? 0))
            c.zenStats.put(id, e)
            _ = c.zenUnlocks.recordWin(id)
        }
        // A win for every deck × tier (deck chain + difficulty chain).
        for d in GameFlowController.decks {
            for t in DifficultyData.tierIds { _ = c.deckUnlocks.recordWin(deckId: d.id, tier: t) }
        }
        c.saveStore.setPref("campaignUnlocked", "1")
        _ = c.itemUnlocks.checkNewUnlocks()   // silent stamp — everything reads long-known
        note("unlocked: all decks, tiers, items, zen ladder")
    }
}
