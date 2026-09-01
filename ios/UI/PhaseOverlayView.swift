import UIKit
import GameCore

/// THE shared full-screen phase overlay — the web's #overlay in all its modes:
/// deal-cleared (SCORE plaque + the bordered rewards panel + hold-to-peek),
/// game over ("Game over" eyebrow / "Shoulda said <word>" + stat tiles + the
/// dashed seed chip), the "Pinky is home" victory, Zen end, the deck/item
/// unlock pops, and the mystery reveal. Win overlays rim PHOSPHOR, losses rim
/// suit-red — the web's `.overlay.win` / `.overlay.lose` inset 4px bezel.
public final class PhaseOverlayView: UIView {

    private let content = UIView()
    private var y: CGFloat = 0
    /// Autopilot marker: this overlay is the victory screen.
    var victoryTag = false
    /// The inset win/lose bezel (nil = no frame — mystery / unlock pops).
    private let bezel = UIView()
    /// Hold-to-peek (deal-cleared only): fade the whole overlay while a finger
    /// rests anywhere on it, restore on release — the web's `.overlay.peek`.
    private var peekEnabled = false

    /// SHOW MAP (mystery reveals over the map): an EXPLICIT button fades the
    /// panel so the whole map can be scrolled, and a floating ◀ BACK is the
    /// only live control until it's tapped. Outside taps never dismiss.
    private var mapPeekBack: PixelButtonView?
    private var mapPeeking = false
    private var mapPeekChanged: ((Bool) -> Void)?
    private var dimColor: UIColor = .clear

    /// Curse-cell help (v6.55): a cursed card in the reveal's well answers tap
    /// OR hold with the curse's registry description — the deck inspector's
    /// card-help idiom, panel at the top of the screen like every hold-help.
    /// Content is THE SHARED CARD-INFO GRAMMAR (v6.74, CardInfoView).
    private var curseHelpPanel: PixelPanelView?
    private let curseHelpContent = CardInfoView(alignment: .center)
    /// The card whose TAP-opened curse help is currently up (nil = none).
    private var curseHelpShownId: Int?

    private func beginMapPeek() {
        mapPeeking = true
        mapPeekChanged?(true)
        mapPeekBack?.isHidden = false
        UIView.animate(withDuration: 0.18, delay: 0, options: [.beginFromCurrentState]) {
            self.content.alpha = 0
            self.bezel.alpha = 0
            self.backgroundColor = .clear
        }
    }

    private func endMapPeek() {
        mapPeeking = false
        mapPeekChanged?(false)
        mapPeekBack?.isHidden = true
        UIView.animate(withDuration: 0.18, delay: 0, options: [.beginFromCurrentState]) {
            self.content.alpha = 1
            self.bezel.alpha = 1
            self.backgroundColor = self.dimColor
        }
    }

    /// While map-peeking, every touch except ◀ BACK falls through to the map
    /// so it can actually scroll; travel stays blocked via mapPeekChanged.
    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard mapPeeking else { return super.hitTest(point, with: event) }
        if let b = mapPeekBack, !b.isHidden, b.frame.contains(point) {
            return b.hitTest(convert(point, to: b), with: event) ?? b
        }
        return nil
    }

    /// The guess that would have SURVIVED the fatal draw ("higher" / "lower" /
    /// "same") — the web's `survivingGuessWord(lastResolvedDraw)`. DealController
    /// stamps this the moment a resolution proves fatal; the loss overlays read
    /// it (GameFlowController stays out of the loop). nil falls back to "lower"
    /// (the web's own null-default is "same", but its fatal draws are never
    /// null in practice and the reference capture shows "lower").
    public static var survivingGuessWord: String?

    /// The bezel idiom: phosphor for wins, suit-red for losses (web
    /// `.overlay.win` / `.overlay.lose` box-shadow insets).
    private enum FrameStyle { case none, win, lose }

    private init(dim: CGFloat = 0.93, frame: FrameStyle = .none) {
        super.init(frame: .zero)
        // The web scrim is INK (rgba(16,16,14,·)), never a felt wash.
        dimColor = CRT.ink.withAlphaComponent(dim)
        backgroundColor = dimColor
        bezel.isUserInteractionEnabled = false
        bezel.layer.borderWidth = CRT.px * 2
        switch frame {
        case .none: bezel.layer.borderColor = nil
        case .win:  bezel.layer.borderColor = CRT.phosphor.cgColor
        case .lose: bezel.layer.borderColor = CRT.suitRed.cgColor
        }
        addSubview(bezel)
        addSubview(content)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    public override func layoutSubviews() {
        super.layoutSubviews()
        // The map-peek's way back rides the bottom, clear of the map chrome.
        mapPeekBack?.frame = CGRect(x: (bounds.width - 300) / 2,
                                    y: bounds.height - max(safeAreaInsets.bottom, 12) - 56,
                                    width: 300, height: 48)
        // Inset by half the border width so the 4px bezel lands INSIDE the
        // screen edge (a CSS inset box-shadow), not centred on it.
        bezel.frame = bounds.insetBy(dx: CRT.px, dy: CRT.px)
        content.transform = .identity
        content.frame = CGRect(x: 0, y: 0, width: min(360, bounds.width - 24), height: y)
        // Centre-ish, but a tall overlay never reaches under the notch/Dynamic
        // Island or the home indicator — it clamps INTO the safe area.
        let topPad = max(safeAreaInsets.top + 8, 40)
        let botPad = max(safeAreaInsets.bottom, 12) + 8
        // There is no scroll view here, so a breakdown with many bonus lines
        // (or a short screen) has to be scaled to fit rather than run off both
        // ends. Uniform, so the pixel grid stays square.
        let available = bounds.height - topPad - botPad
        var shown = y
        if y > available, available > 0 {
            content.transform = CGAffineTransform(scaleX: available / y, y: available / y)
            shown = available
        }
        var cy = max(shown / 2 + topPad, bounds.midY - 20)
        let maxCy = bounds.height - botPad - shown / 2
        if maxCy >= shown / 2 + topPad { cy = min(cy, maxCy) }
        content.center = CGPoint(x: bounds.midX, y: cy)
    }

    // MARK: - Hold-to-peek (deal-cleared)

    private func enablePeek() {
        let lp = UILongPressGestureRecognizer(target: self, action: #selector(peekHold(_:)))
        lp.minimumPressDuration = 0.15
        addGestureRecognizer(lp)
    }

    @objc private func peekHold(_ g: UILongPressGestureRecognizer) {
        switch g.state {
        case .began:
            // 0.02 not 0: a fully transparent view stops hit-testing, which
            // would cancel the very gesture driving the peek.
            UIView.animate(withDuration: 0.12) { self.alpha = 0.02 }
        case .ended, .cancelled, .failed:
            UIView.animate(withDuration: 0.12) { self.alpha = 1 }
        default:
            break
        }
    }

    // MARK: - Curse-cell help (mystery reveal)

    /// Wire the well's curse cells to the help panel + a tap-away collapse.
    /// Called once per reveal build — the recognizers ride the cells and die
    /// with them (the panel is reused across cells, never rebuilt).
    private func wireCurseCells(in wellView: UIView) {
        for case let cell as CurseCardCell in wellView.subviews {
            cell.onTapCell = { [weak self] c in self?.curseCellTapped(c) }
            cell.onHoldCell = { [weak self] c, began in
                if began { self?.showCurseHelp(for: c) } else { self?.hideCurseHelp() }
            }
        }
        let away = UITapGestureRecognizer(target: self, action: #selector(curseHelpAwayTapped(_:)))
        away.cancelsTouchesInView = false
        addGestureRecognizer(away)
    }

    /// TAP (v6.53 idiom): tap a cursed card → its help stays up; tap the same
    /// card again, another card, or empty felt → it collapses/switches. The
    /// hold keeps its press-to-peek behaviour.
    private func curseCellTapped(_ cell: CurseCardCell) {
        if curseHelpShownId == cell.card.id, curseHelpPanel?.isHidden == false {
            hideCurseHelp()
        } else {
            showCurseHelp(for: cell)
        }
    }

    @objc private func curseHelpAwayTapped(_ g: UITapGestureRecognizer) {
        guard curseHelpPanel?.isHidden == false else { return }
        if let hit = hitTest(g.location(in: self), with: nil) {
            var v: UIView? = hit
            while let cur = v {
                if cur is CurseCardCell { return }   // cell taps are the cell's business
                v = cur.superview
            }
        }
        hideCurseHelp()
    }

    private func showCurseHelp(for cell: CurseCardCell) {
        let panel: PixelPanelView
        if let existing = curseHelpPanel {
            panel = existing
        } else {
            let p = PixelPanelView()
            p.addSubview(curseHelpContent)
            addSubview(p)
            curseHelpPanel = p
            panel = p
        }
        // One row per curse (v6.74 grammar): the card's rank+suit LARGEST on
        // top, then each curse's NAME in the display face — blood-red — with
        // its registry description in cream. Copy is NEVER hand-written.
        curseHelpContent.show(
            title: CardInfo.title(for: cell.card), titleGlow: true,
            rows: cell.curses.map { def in
                CardInfo.Row(name: def.label, color: CRT.suitRed,
                             desc: def.description
                                + CardInfo.provenance(onType: def.id, of: cell.card.stickers))
            })
        // TOP, over the panel — the same place every other screen puts
        // hold-help. Framed at show time: the overlay is in the hierarchy by
        // then, so the safe area is real.
        let w = min(bounds.width - 28, 400)
        let contentH = curseHelpContent.sizeThatFits(CGSize(width: w - 24, height: 600)).height
        panel.frame = CGRect(x: (bounds.width - w) / 2, y: safeAreaInsets.top + 8,
                             width: w, height: contentH + 26)
        curseHelpContent.frame = CGRect(x: 12, y: 13, width: w - 24, height: contentH)
        panel.isHidden = false
        curseHelpShownId = cell.card.id
    }

    private func hideCurseHelp() {
        curseHelpPanel?.isHidden = true
        curseHelpShownId = nil
    }

    // MARK: - Shared builders

    private func addTitle(_ text: String, color: UIColor = CRT.phosphor, size: CGFloat = 17,
                          uppercase: Bool = true) {
        let l = CRTKit.label(uppercase ? text.uppercased() : text,
                             size: size, color: color, display: true, glow: color == CRT.phosphor)
        l.textAlignment = .center
        l.frame = CGRect(x: 0, y: y, width: 360, height: size + 12)
        content.addSubview(l)
        y += size + 18
    }

    /// A tracked (letter-spaced) attributed string — the web's run-progress /
    /// tile-label / seed-chip treatments all kern VT323.
    static func tracked(_ text: String, size: CGFloat, color: UIColor,
                        display: Bool = false, kern: CGFloat = 1.5,
                        glow: Bool = false, hardShadow: Bool = false) -> NSAttributedString {
        var attrs: [NSAttributedString.Key: Any] = [
            .font: CRT.Font.of(size, display: display),
            .foregroundColor: color,
            .kern: kern,
        ]
        if glow || hardShadow {
            let s = NSShadow()
            if glow {
                s.shadowColor = CRT.phosphor.withAlphaComponent(CRT.glowAlpha)
                s.shadowBlurRadius = CRT.glowRadius
            } else {
                s.shadowColor = CRT.shadow
                s.shadowBlurRadius = 0
            }
            s.shadowOffset = hardShadow ? CGSize(width: 2, height: 2) : .zero
            attrs[.shadow] = s
        }
        return NSAttributedString(string: text, attributes: attrs)
    }

    /// A coin glyph + value pair. ONE glyph game-wide (v6.97): the ◉ text
    /// mark — the pxi-coin art is retired.
    static func coinAttr(_ value: String, size: CGFloat, color: UIColor,
                         display: Bool = false, glow: Bool = false) -> NSAttributedString {
        let out = NSMutableAttributedString()
        out.append(CRTKit.attributed("◉ ", size: size, color: color, display: display, glow: glow))
        out.append(CRTKit.attributed(value, size: size, color: color, display: display, glow: glow))
        return out
    }

    private func addCentered(_ attr: NSAttributedString, spacingAfter: CGFloat = 8) {
        let l = UILabel()
        l.attributedText = attr
        l.textAlignment = .center
        l.numberOfLines = 0
        let h = ceil(attr.boundingRect(with: CGSize(width: 340, height: 400),
                                       options: .usesLineFragmentOrigin, context: nil).height)
        l.frame = CGRect(x: 10, y: y, width: 340, height: h)
        content.addSubview(l)
        y += h + spacingAfter
    }

    /// The .run-progress line: bold tracked VT323 12, phosphor, uppercase.
    private func addProgress(_ text: String, spacingAfter: CGFloat = 8) {
        addCentered(PhaseOverlayView.tracked(text.uppercased(), size: 14,
                                             color: CRT.phosphor, kern: 1.5),
                    spacingAfter: spacingAfter)
    }

    private func addGap(_ g: CGFloat) { y += g }

    @discardableResult
    private func addButton(_ title: String, role: PixelButtonView.Role = .cta,
                           width: CGFloat = 250, height: CGFloat = 48,
                           fontSize: CGFloat = CRT.Font.bodySize,
                           handler: @escaping () -> Void) -> PixelButtonView {
        let b = PixelButtonView(title, role: role, fontSize: fontSize)
        b.playsClick = false          // it owns the louder CTA confirm instead
        b.onTap = { Sound.shared.continueTap(); handler() }
        b.frame = CGRect(x: (360 - width) / 2, y: y, width: width, height: height)
        content.addSubview(b)
        y += height + 10
        return b
    }

    private func addSprite(_ image: UIImage, size: CGSize) {
        let iv = UIImageView(image: image)
        iv.contentMode = .scaleAspectFit
        iv.layer.magnificationFilter = .nearest
        iv.frame = CGRect(x: (360 - size.width) / 2, y: y, width: size.width, height: size.height)
        content.addSubview(iv)
        y += size.height + 12
    }

    /// The dashed-gold tap-to-copy seed chip (the web's `.ov-seed`).
    private func addSeedBox(_ seed: String) {
        let chip = SeedChip(seed: seed)
        chip.frame = CGRect(x: 0, y: y, width: chip.idealWidth, height: chip.idealHeight)
        chip.center = CGPoint(x: 180, y: chip.frame.midY)
        chip.frame = chip.frame.integral
        content.addSubview(chip)
        y += chip.idealHeight + 10
    }

    /// A row of run-stat tiles (the web's `.summary-tiles` flex row).
    private func addTileRow(_ tiles: [StatTileView], height: CGFloat,
                            gap: CGFloat = 10, width: CGFloat = 320) {
        let row = UIView(frame: CGRect(x: (360 - width) / 2, y: y, width: width, height: height))
        let tw = ((width - gap * CGFloat(tiles.count - 1)) / CGFloat(tiles.count)).rounded(.down)
        for (i, t) in tiles.enumerated() {
            t.frame = CGRect(x: CGFloat(i) * (tw + gap), y: 0, width: tw, height: height)
            row.addSubview(t)
        }
        content.addSubview(row)
        y += height + 10
    }

    // MARK: - Shared campaign context

    /// The live campaign, reached through the flow shell (the overlays' extra
    /// lines — REACHED / run totals / score tiles / seed — all read it, the
    /// same way the web reads `campaign` inside showOverlay).
    private static var campaign: CampaignState? {
        (PersistenceHolder.shared as? GameFlowController)?.campaign
    }

    /// The web's stageRunShort(): "♦ PHASE 1/3 · DECK 13", endless-labelled
    /// past the base phases.
    private static func stageRunShort(_ c: CampaignState) -> String {
        let pi = c.phaseIndex
        let total = c.phasesTotal()
        if pi >= total { return "ENDLESS stage \(pi - total + 1) · Deck \(c.deckSize())" }
        return "\(c.phaseSuit()) phase \(pi + 1)/\(total) · Deck \(c.deckSize())"
    }

    /// The web's runSeedShareStr(): DECK-TIER-CODE, squashed alphanumerics.
    private static func seedShareStr(_ c: CampaignState) -> String {
        let squash: (String) -> String = { $0.uppercased().filter { $0.isLetter || $0.isNumber } }
        let name = GameFlowController.decks.first(where: { $0.id == c.deckId })?.name ?? c.deckId
        let tierLabel = GameData.shared.difficulty.tier(c.difficultyTier).label
        return "\(squash(name))-\(squash(tierLabel))-\(SeedCode.encode(c.runSeed))"
    }

    /// The score/best tile pair: ONE continuous run score (endless keeps
    /// accruing into it, v6.47) and its one record. Bests never claim a
    /// record on exhibition runs.
    private static func scoreTiles(_ c: CampaignState) -> [StatTileView] {
        let s = c.stats.get()
        let exhibition = c.isExhibition()
        let dtKey = "\(c.deckId).\(c.difficultyTier)"
        return [
            StatTileView(value: tileValue("\(c.getRunScore())", size: 18), name: "Score"),
            StatTileView(value: tileValue(exhibition ? "—" : "\(s.deckTierBest[dtKey] ?? 0)", size: 18),
                         name: exhibition ? "Best · not recorded" : "Best"),
        ]
    }

    static func tileValue(_ text: String, size: CGFloat) -> NSAttributedString {
        CRTKit.attributed(text, size: size, color: CRT.phosphor, display: true, glow: true)
    }

    // MARK: - Deal cleared (SCORE plaque + rewards panel)

    static func dealCleared(info: GameFlowController.SummaryInfo,
                            onContinue: @escaping () -> Void) -> PhaseOverlayView {
        let v = PhaseOverlayView(frame: .win)
        v.addTitle("DEAL CLEARED", size: 22)
        // No stage/deck progress line here (v6.52) — the map the player is
        // about to return to says it better, and it read as clutter between
        // the title and the score.
        v.y += 14

        // The reveal cadence: the plaque, then each reward line ONE BY ONE,
        // each with its rising coin ping — the deal-won payoff moment.
        var delay = 0.35

        // SCORE is its own distinct plaque, ABOVE the rewards panel — never a
        // line in the coin list. A cleared deal always scores ≥ 1; product 0
        // means an ambush (coins only) and no plaque.
        if info.product > 0 {
            let plaque = PixelPanelView(face: CRT.feltMid, border: CRT.ink)
            let plaqueH: CGFloat = 94
            plaque.frame = CGRect(x: 20, y: v.y, width: 320, height: plaqueH)
            let val = UILabel()
            val.attributedText = PhaseOverlayView.tracked("SCORE +\(info.product)", size: 24,
                                                          color: CRT.phosphor, display: true,
                                                          kern: 0.5, glow: true)
            val.textAlignment = .center
            val.frame = CGRect(x: 0, y: 10, width: 320, height: 32)
            plaque.addSubview(val)
            let sub = UILabel()
            sub.attributedText = PhaseOverlayView.tracked(
                "\(info.aliveCount) piles × \(info.minAlive) smallest".uppercased(),
                size: 14, color: CRT.muted, kern: 1)
            sub.textAlignment = .center
            sub.frame = CGRect(x: 0, y: 44, width: 320, height: 20)
            plaque.addSubview(sub)
            // The RUNNING total sits under the deal's own score, exactly the
            // way the purse sits under the coin total below — and at the SAME
            // relative weight (v6.52: 16 plain read as a footnote; 20 display
            // mirrors Purse's 20 against Total's 22).
            let tot = UILabel()
            tot.attributedText = PhaseOverlayView.tracked("TOTAL SCORE \(info.totalScore)",
                                                          size: 20, color: CRT.phosphor,
                                                          display: true, kern: 0.5)
            tot.textAlignment = .center
            tot.frame = CGRect(x: 0, y: 64, width: 320, height: 26)
            plaque.addSubview(tot)
            plaque.alpha = 0
            v.content.addSubview(plaque)
            v.y += plaqueH + 10
            UIView.animate(withDuration: 0.25, delay: delay) { plaque.alpha = 1 }
            delay += 0.28
        }

        // The rewards PANEL (the web's .overlay-coins / coinBreakdownHtml):
        // "Deal reward" leads (an ambush has no flat base — its sub-row says
        // so), then "Sticker rewards" and "Pillar rewards" as their OWN main
        // rows with each bonus line as an italic sub-bullet ("None" when
        // empty), then the deal's "Payout" and the "Coins held" balance
        // AFTER these earnings.
        let flatLine = info.lines.first(where: { $0.source == .flat })
        // summaryLines omits the flat row when it's 0 — only ambush/subset
        // deals have no flat base (Economy.dealFlat guards stage > 0).
        let ambush = flatLine == nil
        var extras = info.lines.filter { $0.source != .flat }
        // An AMBUSH's bounty IS its deal reward — it was being paid as a plain
        // bonus event, so it landed in the sticker bucket while the reward row
        // said "no flat reward". Lift it onto the reward row where the player
        // looks for it (v5.83).
        var flat = flatLine?.amount ?? 0
        var ambushBounty = 0
        if ambush, let i = extras.firstIndex(where: { $0.label == "Ambush" }) {
            ambushBounty = extras[i].amount
            flat = ambushBounty
            extras.remove(at: i)
        }
        // Each line already knows where it came from — no label matching.
        func bullets(_ src: GameFlowController.RewardSource) -> [(String, Int)] {
            extras.filter { $0.source == src }.map { ($0.label, $0.amount) }
        }
        let stickerBullets = bullets(.sticker)
        let pillarBullets = bullets(.pillar)
        let baseBullets = bullets(.base)
        let sameBullets = bullets(.same)
        let stickerTotal = stickerBullets.reduce(0) { $0 + $1.1 }
        let pillarTotal = pillarBullets.reduce(0) { $0 + $1.1 }
        let baseTotal = baseBullets.reduce(0) { $0 + $1.1 }
        let sameTotal = sameBullets.reduce(0) { $0 + $1.1 }
        let sign: (Int) -> String = { ($0 >= 0 ? "+" : "−") + String(abs($0)) }
        // The flat "Extra Coin" line prints the sticker's registry label
        // (web: StickerTypes.get("extraCoin").label) — never a hardcoded name.
        let payoutLabel = GameData.shared.stickerTypes.get("extraCoin")?.label ?? "Extra Coin"
        let bulletLabel: (String) -> String = { $0 == "Extra Coin" ? payoutLabel : $0 }

        let panel = PixelPanelView(face: CRT.feltMid, border: CRT.ink)
        let px: CGFloat = 16
        let pw: CGFloat = 340
        var py: CGFloat = 14
        var rows: [UIView] = []

        func mainRow(_ label: String, _ value: Int) -> UIView {
            let rowH: CGFloat = 26
            let row = UIView(frame: CGRect(x: px, y: py, width: pw - px * 2, height: rowH))
            let lab = UILabel()
            lab.attributedText = CRTKit.attributed(label, size: 18, color: CRT.cardFace)
            lab.frame = CGRect(x: 0, y: 0, width: 190, height: rowH)
            row.addSubview(lab)
            let val = UILabel()
            val.attributedText = PhaseOverlayView.coinAttr("\(value)", size: 18, color: CRT.gold)
            val.textAlignment = .right
            val.frame = CGRect(x: pw - px * 2 - 130, y: 0, width: 130, height: rowH)
            row.addSubview(val)
            py += rowH
            return row
        }

        /// A hairline that closes the earnings list — everything above it adds
        /// up to the row below it.
        func ruleRow() -> UIView {
            let row = UIView(frame: CGRect(x: px, y: py, width: pw - px * 2, height: 9))
            let line = UIView(frame: CGRect(x: 0, y: 4, width: pw - px * 2, height: CRT.px))
            line.backgroundColor = CRT.cardFace.withAlphaComponent(0.35)
            row.addSubview(line)
            py += 9
            return row
        }

        /// The two closing rows: bigger than a reward line, and coloured for
        /// what they mean — phosphor for what this deal paid, gold for what
        /// you now hold.
        func summaryRow(_ label: String, _ value: Int,
                        color: UIColor, size: CGFloat, glow: Bool) -> UIView {
            let rowH: CGFloat = size + 10
            let rowW = pw - px * 2
            let row = UIView(frame: CGRect(x: px, y: py, width: rowW, height: rowH))
            // The value box takes what the number needs; the label gets the
            // rest. A fixed 220/150 split clipped "Total earned" to "Total ea…"
            // at display weight.
            let valAttr = PhaseOverlayView.coinAttr("\(value)", size: size,
                                                    color: color, display: true, glow: glow)
            let valW = min(rowW * 0.45,
                           max(70, ceil(valAttr.boundingRect(
                               with: CGSize(width: rowW, height: rowH),
                               options: .usesLineFragmentOrigin, context: nil).width) + 10))
            let lab = CRTKit.label(label, size: size, color: color, display: true, glow: glow)
            lab.adjustsFontSizeToFitWidth = false
            lab.frame = CGRect(x: 0, y: 0, width: rowW - valW - 8, height: rowH)
            row.addSubview(lab)
            let val = UILabel()
            val.attributedText = valAttr
            val.textAlignment = .right
            val.frame = CGRect(x: rowW - valW, y: 0, width: valW, height: rowH)
            row.addSubview(val)
            py += rowH
            return row
        }

        func subRow(_ label: String, _ value: String?) -> UIView {
            let subH: CGFloat = 20
            let row = UIView(frame: CGRect(x: px + 14, y: py, width: pw - px * 2 - 14, height: subH))
            let lab = UILabel()
            var attrs: [NSAttributedString.Key: Any] = [
                .font: CRT.Font.of(14),
                .foregroundColor: CRT.muted,
                .obliqueness: 0.18,   // VT323 has no italic cut — the web's .dc-sub slant
            ]
            lab.attributedText = NSAttributedString(string: label, attributes: attrs)
            lab.frame = CGRect(x: 0, y: 0, width: 200, height: subH)
            row.addSubview(lab)
            if let value {
                attrs[.obliqueness] = 0
                attrs[.foregroundColor] = CRT.cardFace
                let val = UILabel()
                val.attributedText = NSAttributedString(string: value, attributes: attrs)
                val.textAlignment = .right
                val.frame = CGRect(x: pw - px * 2 - 14 - 100, y: 0, width: 100, height: subH)
                row.addSubview(val)
            }
            py += subH
            return row
        }

        /// Sound per row kind: main rows ping in sequence, the Total lands
        /// HIGH (web coinTallyLine(6)), the balance gets a soft tick
        /// (web Sound.coin()), sub-bullets stay silent.
        enum RowKind { case main, sub, total, balance }
        var kinds: [RowKind] = []

        rows.append(mainRow("Deal reward", flat)); kinds.append(.main)
        if ambush {
            rows.append(subRow(ambushBounty > 0 ? "Ambush bounty" : "Ambush",
                               ambushBounty > 0 ? sign(ambushBounty) : "no flat reward"))
            kinds.append(.sub)
        }
        // One section per SOURCE, so a Base or Same-Power payout is credited to
        // the thing that earned it instead of being filed under stickers.
        // Sections with nothing to report are omitted rather than printing
        // "None" — five empty rows made the panel unreadable.
        func section(_ title: String, _ total: Int, _ bullets: [(String, Int)], showEmpty: Bool = false) {
            guard !bullets.isEmpty || showEmpty else { return }
            py += 12
            rows.append(mainRow(title, total)); kinds.append(.main)
            py += 3
            if bullets.isEmpty {
                rows.append(subRow("None", nil)); kinds.append(.sub)
            } else {
                for (label, amount) in bullets {
                    rows.append(subRow(bulletLabel(label), sign(amount))); kinds.append(.sub)
                }
            }
        }
        // ONE "Item rewards" block (v6.52): kind · name · amount per line —
        // the four per-family sections hid Base and Same-Power payouts when
        // their empty sections were skipped, and four headings for a handful
        // of lines buried the numbers.
        _ = section   // the per-family builder is retired; kept for diffs
        let itemBullets: [(kind: String, label: String, amount: Int)] =
            stickerBullets.map { ("Sticker", $0.0, $0.1) }
            + pillarBullets.map { ("Pillar", $0.0, $0.1) }
            + baseBullets.map { ("Base", $0.0, $0.1) }
            + sameBullets.map { ("Same Power", $0.0, $0.1) }
        let itemTotal = stickerTotal + pillarTotal + baseTotal + sameTotal
        py += 12
        rows.append(mainRow("Item rewards", itemTotal)); kinds.append(.main)
        py += 3
        if itemBullets.isEmpty {
            rows.append(subRow("None", nil)); kinds.append(.sub)
        } else {
            for b in itemBullets {
                rows.append(subRow("\(b.kind) · \(bulletLabel(b.label))", sign(b.amount)))
                kinds.append(.sub)
            }
        }
        // THE TWO SUMMARY ROWS READ DIFFERENTLY FROM THE EARNINGS ABOVE THEM.
        // Both used the same `mainRow` as every reward line, so the row that
        // SUMS the list and the row that reports your new purse looked like
        // two more rewards. A rule closes the tally, "Total earned" is the
        // brightest thing in the panel, and the purse sits apart in gold with
        // its own wording.
        py += 10
        rows.append(ruleRow()); kinds.append(.sub)
        // Short labels: the display face is wide, and "Total earned" clipped
        // at this size. The rule above already says these sum the list.
        // GOLD, not phosphor (router batch): this number is COINS — green is
        // the score's colour and was claiming the wrong family.
        // glow OFF (v6.52): the halo smudged the display face at this size —
        // Purse below was crisp for exactly this reason. Size keeps the rank.
        rows.append(summaryRow("Payout", info.earned,
                               color: CRT.gold, size: 22, glow: false)); kinds.append(.total)
        py += 6
        rows.append(summaryRow("Purse", info.balance,
                               color: CRT.gold, size: 20, glow: false)); kinds.append(.balance)

        // Size to the rows themselves — the old 224pt floor padded short
        // breakdowns with dead space that the bigger type now needs.
        let panelH = py + 10
        panel.frame = CGRect(x: 10, y: v.y, width: pw, height: panelH)
        v.content.addSubview(panel)
        for row in rows {
            row.alpha = 0
            panel.addSubview(row)
        }
        // Reveal line by line, with the web's per-kind tally sounds.
        for (i, row) in rows.enumerated() {
            UIView.animate(withDuration: 0.22, delay: delay) { row.alpha = 1 }
            let at = delay
            switch kinds[i] {
            case .sub: break
            case .main:
                let lineIndex = i
                DispatchQueue.main.asyncAfter(deadline: .now() + at) {
                    Sound.shared.coinTallyLine(lineIndex)
                }
                delay += 0.28
            case .total:
                DispatchQueue.main.asyncAfter(deadline: .now() + at) { Sound.shared.coinTallyLine(6) }
                delay += 0.28
            case .balance:
                DispatchQueue.main.asyncAfter(deadline: .now() + at) { Sound.shared.coin() }
                delay += 0.28
            }
        }
        v.y += panelH + 12

        v.addButton("CONTINUE") { onContinue() }

        // Hold-to-peek hint (web #peekHint): eye glyph + copy, dim.
        let hint = NSMutableAttributedString()
        let eye = NSTextAttachment()
        eye.image = PhaseOverlayView.glyphEye(size: 14, color: CRT.muted)
        eye.bounds = CGRect(x: 0, y: -2, width: 14, height: 14)
        hint.append(NSAttributedString(attachment: eye))
        hint.append(PhaseOverlayView.tracked("  Hold to peek board",
                                             size: 14, color: CRT.muted, kern: 0))
        let hintLabel = UILabel()
        hintLabel.attributedText = hint
        hintLabel.textAlignment = .center
        hintLabel.alpha = 0.8
        // Wraps rather than truncating — it no longer fits one line at 14pt on
        // a narrow phone.
        hintLabel.numberOfLines = 0
        let hintH = max(18, ceil(hint.boundingRect(with: CGSize(width: 340, height: 200),
                                                   options: .usesLineFragmentOrigin,
                                                   context: nil).height))
        hintLabel.frame = CGRect(x: 10, y: v.y, width: 340, height: hintH)
        v.content.addSubview(hintLabel)
        v.y += hintH
        v.enablePeek()
        return v
    }

    // MARK: - Game over

    static func gameOver(info: GameFlowController.FailedInfo, seed: String,
                         nearest: [ItemUnlocks.NearMiss],
                         onNewClimb: @escaping () -> Void) -> PhaseOverlayView {
        // `nearest` is kept for the callers, but the web no longer renders the
        // "almost there" unlock rows anywhere: showOverlay's opts.unlocks is
        // vestigial (CSS + comments only, zero call sites), so end screens
        // show stat tiles and nothing else.
        let v = PhaseOverlayView(frame: .lose)
        let c = PhaseOverlayView.campaign

        v.addGap(6)
        // The header: a small red "GAME OVER" eyebrow over the menu's title
        // treatment, whose last word is the guess that would have survived.
        v.addCentered(PhaseOverlayView.tracked("GAME OVER", size: 14, color: CRT.suitRed,
                                               display: true, kern: 2), spacingAfter: 4)
        v.addCentered(PhaseOverlayView.tracked("Shoulda said", size: 20, color: CRT.cardFace,
                                               display: true, kern: 0, hardShadow: true),
                      spacingAfter: 2)
        v.addCentered(PhaseOverlayView.tracked(PhaseOverlayView.survivingGuessWord ?? "lower",
                                               size: 20, color: CRT.phosphor, display: true,
                                               kern: 0, glow: true), spacingAfter: 8)
        // THE SCORE IS THE SCREEN. It used to be one 17pt tile among eight,
        // with the stage/deck progress line and the seed box above it — so the
        // number the run is judged on was the least prominent thing here.
        // Everything else is now secondary and the seed sits at the very
        // bottom, where it's available to share without competing.
        let score = c?.getRunScore() ?? 0
        v.addGap(4)
        v.addCentered(PhaseOverlayView.tracked("SCORE", size: 14, color: CRT.muted,
                                               display: true, kern: 3), spacingAfter: 2)
        v.addCentered(PhaseOverlayView.tracked("\(score)", size: 52, color: CRT.phosphor,
                                               display: true, kern: 0, glow: true), spacingAfter: 2)
        if let c, !c.isExhibition() {
            let best = c.stats.get().deckTierBest["\(c.deckId).\(c.difficultyTier)"] ?? 0
            let beat = score >= best && score > 0
            v.addCentered(PhaseOverlayView.tracked(beat ? "NEW BEST" : "BEST \(best)",
                                                   size: 14,
                                                   color: beat ? CRT.gold : CRT.muted,
                                                   display: true, kern: 2), spacingAfter: 10)
        } else {
            v.addGap(10)
        }

        // The three secondary numbers, and nothing else.
        let cards = c?.totalCardsFlipped ?? info.cardsFlipped
        let coins = c?.totalCoinsEarned ?? info.coinsEarned
        let correct = c?.allGuessesCorrect ?? info.correct
        let total = c.map { $0.allGuessesTotal } ?? (info.correct + info.wrong)
        let pct = total > 0 ? Int((Double(correct) / Double(total) * 100).rounded()) : 0
        v.addTileRow([
            StatTileView(value: tileValue("\(cards)", size: 18), name: "Cards Played"),
            StatTileView(value: tileValue("\(pct)%", size: 18), name: "Correct"),
            // GOLD, never phosphor (router batch 2): a green glowing number
            // directly under the score read as the score printed twice.
            StatTileView(value: PhaseOverlayView.coinAttr("\(coins)", size: 18,
                                                          color: CRT.gold,
                                                          display: true, glow: false),
                         name: "Coins Earned"),
        ], height: 64)

        v.addGap(10)
        v.addButton("MAIN MENU") { onNewClimb() }
        // The seed goes LAST — there to copy if you want it, out of the way
        // of the result if you don't.
        v.addGap(6)
        v.addSeedBox(seed)
        return v
    }

    // MARK: - Victory

    static func pinkyHome(deckName: String, score: Int, coins: Int, cards: Int, bestScore: Int,
                          onEndless: @escaping () -> Void,
                          onMenu: @escaping () -> Void) -> PhaseOverlayView {
        let v = PhaseOverlayView(frame: .win)
        v.victoryTag = true
        let c = PhaseOverlayView.campaign

        v.addGap(10)
        // GLYPHS.complete — the cream ★. The web has NO character art here.
        v.addSprite(PhaseOverlayView.glyphStar(size: 34, color: CRT.cardFace),
                    size: CGSize(width: 34, height: 34))
        v.addTitle("\(deckName) is home", size: 18, uppercase: false)
        let runs = c?.runsCompleted ?? 1
        let deckSize = c?.deckSize() ?? 0
        v.addProgress("\(runs) deal\(runs == 1 ? "" : "s") · \(cards) cards played · Deck \(deckSize)",
                      spacingAfter: 8)
        if let c {
            v.addSeedBox(PhaseOverlayView.seedShareStr(c))
            v.addGap(2)
            // No standing "best" section (router batch): the score simply
            // announces NEW HIGH SCORE when it is one. The endless tiles are
            // gone too — endless is a choice below, not a stat here.
            let exhibition = c.isExhibition()
            let newBest = !exhibition && score > 0 && score >= bestScore
            v.addTileRow([
                StatTileView(value: tileValue("\(score)", size: 14),
                             name: newBest ? "Score · NEW HIGH SCORE!" : "Score"),
                StatTileView(value: tileValue("\(cards)", size: 14), name: "Cards Played"),
                StatTileView(value: PhaseOverlayView.coinAttr("\(coins)", size: 14,
                                                              color: CRT.gold,
                                                              display: true, glow: false),
                             name: "Coins"),
            ], height: 56)
            let correct = c.allGuessesCorrect
            let total = c.allGuessesTotal
            let wrong = max(0, total - correct)
            let pct = total > 0 ? Int((Double(correct) / Double(total) * 100).rounded()) : 0
            v.addTileRow([
                StatTileView(value: tileValue("\(correct)", size: 14), name: "Correct"),
                StatTileView(value: tileValue("\(wrong)", size: 14), name: "Wrong"),
                StatTileView(value: tileValue("\(pct)%", size: 14), name: "Accuracy"),
            ], height: 56)
        }
        v.addGap(8)
        let primary = v.addButton("CONTINUE · ENDLESS MODE", role: .cta,
                                  width: 300, height: 64, fontSize: 16) { onEndless() }
        // The web's primary wraps to two lines; PixelButtonView's label is
        // single-line by default.
        if let label = primary.subviews.compactMap({ $0 as? UILabel }).first {
            label.numberOfLines = 0
            label.lineBreakMode = .byWordWrapping
        }
        v.addButton("GO TO MAIN MENU", role: .plain, fontSize: 16) { onMenu() }
        return v
    }

    // MARK: - Zen end

    static func zenEnd(won: Bool, flips: Int, correct: Int,
                       outcomeCount: Int? = nil, unlockLabel: String? = nil,
                       onAgain: @escaping () -> Void,
                       onMenu: @escaping () -> Void) -> PhaseOverlayView {
        // SIZED TO THE CAMPAIGN END SCREENS (v6.68): this used to be a
        // miniature — no bezel, 17pt title, 14pt values in a 260pt tile row —
        // next to gameOver's framed 20pt header, 52pt hero number and 18pt
        // tiles at 320. Every metric below is REUSED from gameOver /
        // dealCleared above; nothing new is invented.
        let v = PhaseOverlayView(frame: won ? .win : .lose)
        v.addGap(6)
        if won {
            // dealCleared's title metric (22), the win bezel to match.
            v.addTitle("DECK CLEARED", size: 22)
        } else {
            // The web's onZenEnd loss header: the same "Shoulda said <word>"
            // treatment as the campaign death screen (gameOverTitleHtml).
            v.addCentered(PhaseOverlayView.tracked("GAME OVER", size: 14, color: CRT.suitRed,
                                                   display: true, kern: 2), spacingAfter: 4)
            v.addCentered(PhaseOverlayView.tracked("Shoulda said", size: 20, color: CRT.cardFace,
                                                   display: true, kern: 0, hardShadow: true),
                          spacingAfter: 2)
            v.addCentered(PhaseOverlayView.tracked(PhaseOverlayView.survivingGuessWord ?? "lower",
                                                   size: 20, color: CRT.phosphor, display: true,
                                                   kern: 0, glow: true), spacingAfter: 8)
        }
        // A first win's ladder beat rides the progress line (web opts.progress:
        // "<Next> unlocked!", the label resolved live from DifficultyData).
        if let unlockLabel {
            v.addProgress("\(unlockLabel) unlocked!", spacingAfter: 10)
        }
        // THE ACCURACY IS THE SCREEN — zen has no score, so its one big
        // number gets gameOver's exact hero treatment (14pt eyebrow, 52pt
        // glowing figure). Correct/wrong counts came off in v6.35: the
        // percentage already tells that story in one number.
        let pct = flips > 0 ? Int((Double(correct) / Double(flips) * 100).rounded()) : 0
        v.addGap(4)
        v.addCentered(PhaseOverlayView.tracked("ACCURACY", size: 14, color: CRT.muted,
                                               display: true, kern: 3), spacingAfter: 2)
        v.addCentered(PhaseOverlayView.tracked("\(pct)%", size: 52, color: CRT.phosphor,
                                               display: true, kern: 0, glow: true),
                      spacingAfter: 8)
        // The secondary numbers, at gameOver's tile metrics (18pt values,
        // 64pt tiles, the default 320pt row): cards guessed and the
        // outcome-specific count (piles standing on a win, cards left in the
        // deck on a loss).
        v.addTileRow([
            StatTileView(value: tileValue("\(flips)", size: 18), name: "Guessed"),
            StatTileView(value: tileValue(outcomeCount.map { "\($0)" } ?? "—", size: 18),
                         name: won ? "Piles remaining" : "Remaining"),
        ], height: 64)
        v.addGap(10)
        v.addButton("PLAY AGAIN", role: .cta) { onAgain() }
        v.addButton("MENU", role: .plain) { onMenu() }
        return v
    }

    // MARK: - Unlock pops

    static func deckUnlock(name: String, deckId: String, prevName: String? = nil,
                           onContinue: @escaping () -> Void) -> PhaseOverlayView {
        let v = PhaseOverlayView()
        v.addGap(10)
        // The web's maybeShowUnlockCelebration: eyebrow over the character,
        // the name hidden behind "???" for an 800ms breath, then the reveal.
        v.addCentered(PhaseOverlayView.tracked("NEW DECK UNLOCKED", size: 14,
                                               color: CRT.gold, display: true, kern: 2),
                      spacingAfter: 10)
        v.addSprite(DeckCharacter.image(deckId: deckId, mood: .happy, scale: 5),
                    size: CGSize(width: 96, height: 96))
        let nameLabel = UILabel()
        nameLabel.attributedText = PhaseOverlayView.tracked("???", size: 16, color: CRT.gold,
                                                            display: true, kern: 1, glow: false)
        nameLabel.textAlignment = .center
        nameLabel.frame = CGRect(x: 0, y: v.y, width: 360, height: 22)
        v.content.addSubview(nameLabel)
        v.y += 28
        // The previous deck hands off: "<Prev> made it home — say hello to
        // <Name>!" (web duc-copy; a nil prev reads "You", like the web).
        v.addCentered(CRTKit.attributed("\(prevName ?? "You") made it home. Say hello to \(name)!",
                                        size: 16, color: CRT.cardFace), spacingAfter: 12)
        v.addButton("CONTINUE") { onContinue() }
        // The entrance bounce first (color floods in), then the name reveal
        // lands the sparkly ta-daa — one-shot, transform/opacity only.
        v.content.transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
        UIView.animate(withDuration: 0.5, delay: 0.05, usingSpringWithDamping: 0.55,
                       initialSpringVelocity: 0.4) {
            v.content.transform = .identity
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            nameLabel.attributedText = PhaseOverlayView.tracked(name.uppercased(), size: 16,
                                                                color: CRT.gold, display: true,
                                                                kern: 1, glow: false)
            Sound.shared.deckUnlock()
        }
        return v
    }

    /// The web's itemKindOf + KIND_LABEL: registry lookup → class noun.
    static func itemKindLabel(_ id: String) -> String {
        let d = GameData.shared
        if d.stickerTypes.get(id) != nil { return "Sticker" }
        if d.pillarTypes.get(id) != nil { return "Pillar" }
        if d.baseTypes.get(id) != nil { return "Base" }
        if d.samePowerTypes.get(id) != nil { return "Same-Power" }
        return "Pack"
    }

    /// The web itemKindOf key (ItemArt.forSlot's kind strings).
    private static func itemKindKey(_ id: String) -> String {
        let d = GameData.shared
        if d.stickerTypes.get(id) != nil { return "sticker" }
        if d.pillarTypes.get(id) != nil { return "pillar" }
        if d.baseTypes.get(id) != nil { return "base" }
        if d.samePowerTypes.get(id) != nil { return "samepower" }
        return "pack"
    }

    /// The item's own tile art at unlock-pop size (web unlockObjectHtml, the
    /// store's class renderers via ItemArt.forSlot).
    private static func unlockArt(_ id: String) -> UIImage {
        ItemArt.forSlot(kind: itemKindKey(id), id: id, card: nil,
                        deckId: campaign?.deckId ?? "pink")
    }

    /// `onSkipAll`, when given, adds a quiet SKIP ALL beside CONTINUE — a
    /// long unlock walk after a good climb is a wall of taps otherwise.
    static func itemUnlock(title: String, body: String,
                           itemId: String? = nil, hint: String? = nil,
                           onSkipAll: (() -> Void)? = nil,
                           onContinue: @escaping () -> Void) -> PhaseOverlayView {
        let v = PhaseOverlayView()
        guard let itemId, let def = itemDef(itemId) else {
            // No item context (the 4+ summary pop): the plain pop stays.
            v.addTitle(title, color: CRT.gold, size: 16)
            v.addCentered(CRTKit.attributed(body, size: 16, color: CRT.cardFace), spacingAfter: 12)
            v.addButton("CONTINUE") { onContinue() }
            if let onSkipAll {
                v.addButton("SKIP ALL", role: .plain, fontSize: 14) { onSkipAll() }
            }
            v.content.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
            UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.6,
                           initialSpringVelocity: 0.3) {
                v.content.transform = .identity
            }
            return v
        }
        // The web's showItemUnlockPop ceremony: kind eyebrow over the item's
        // own art as a SILHOUETTE under a padlock; after an 800ms breath the
        // reveal floods the colour in, "???" becomes the label, the copy
        // swaps from the earn hint to the registry description, and the hint
        // stays as the small "Earned:" footnote.
        v.addGap(6)
        v.addCentered(PhaseOverlayView.tracked("New \(itemKindLabel(itemId)) unlocked",
                                               size: 14, color: CRT.gold, display: true, kern: 2),
                      spacingAfter: 10)

        let art = unlockArt(itemId)
        let artH: CGFloat = 110
        let artW = art.size.height > 0 ? artH * art.size.width / art.size.height : artH
        let artView = UIImageView(image: art.withRenderingMode(.alwaysTemplate))
        artView.tintColor = CRT.ink   // the silhouette: a flat ink cutout
        artView.contentMode = .scaleAspectFit
        artView.layer.magnificationFilter = .nearest
        artView.frame = CGRect(x: (360 - artW) / 2, y: v.y, width: artW, height: artH)
        v.content.addSubview(artView)
        // The padlock + reveal sparkles ride over the art (web duc-lock /
        // duc-spark; emoji glyphs exactly as the web renders them).
        let lock = CRTKit.label("🔒", size: 22, color: CRT.cardFace)
        lock.textAlignment = .center
        lock.frame = CGRect(x: artView.frame.midX - 16, y: artView.frame.midY - 16,
                            width: 32, height: 32)
        v.content.addSubview(lock)
        var sparks: [UILabel] = []
        for (dx, dy) in [(-30.0, -8.0), (30.0, -14.0), (-26.0, 26.0), (28.0, 22.0)] as [(CGFloat, CGFloat)] {
            let s = CRTKit.label("✦", size: 16, color: CRT.gold)
            s.textAlignment = .center
            s.frame = CGRect(x: artView.frame.midX + dx - 10, y: artView.frame.midY + dy - 10,
                             width: 20, height: 20)
            s.alpha = 0
            v.content.addSubview(s)
            sparks.append(s)
        }
        v.y += artH + 12

        let nameLabel = UILabel()
        nameLabel.attributedText = PhaseOverlayView.tracked("???", size: 16, color: CRT.gold,
                                                            display: true, kern: 1)
        nameLabel.textAlignment = .center
        nameLabel.frame = CGRect(x: 0, y: v.y, width: 360, height: 22)
        v.content.addSubview(nameLabel)
        v.y += 28

        // This label shows the earn HINT first, then swaps to the item's full
        // description on reveal. Its box has to be sized for the LONGER of the
        // two up front: sizing it for the hint alone clipped every description
        // that ran longer (the layout cursor `v.y` is fixed at build time, so
        // it can't be re-measured after the swap without shoving the rest of
        // the screen down mid-animation).
        let copyW: CGFloat = 320
        func measure(_ text: String, size: CGFloat) -> CGFloat {
            guard !text.isEmpty else { return 0 }
            return ceil(CRTKit.attributed(text, size: size, color: CRT.cardFace).boundingRect(
                with: CGSize(width: copyW, height: 600),
                options: .usesLineFragmentOrigin, context: nil).height)
        }
        let copyLabel = UILabel()
        copyLabel.attributedText = CRTKit.attributed(hint ?? body, size: 14, color: CRT.cardFace)
        copyLabel.textAlignment = .center
        copyLabel.numberOfLines = 0
        let copyH = max(measure(hint ?? body, size: 14), measure(body, size: 14))
        copyLabel.frame = CGRect(x: 20, y: v.y, width: copyW, height: max(18, copyH))
        v.content.addSubview(copyLabel)
        v.y += max(18, copyH) + 6

        // (The "Earned: <hint>" footnote is gone — the reveal keeps just the
        // name and the registry description. The earn condition still shows
        // during the pre-reveal tease, then the description takes over.)
        v.y += 12

        v.addButton("CONTINUE") { onContinue() }
        if let onSkipAll {
            v.addButton("SKIP ALL", role: .plain, fontSize: 14) { onSkipAll() }
        }

        // The reveal: 800ms of silhouette tease, then colour + name +
        // description + footnote + the ta-daa (one-shot, opacity/transform
        // only — never an always-on animation).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            artView.image = art.withRenderingMode(.alwaysOriginal)
            artView.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
            UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.55,
                           initialSpringVelocity: 0.3) {
                artView.transform = .identity
            }
            UIView.animate(withDuration: 0.2) { lock.alpha = 0 }
            for (i, s) in sparks.enumerated() {
                s.transform = CGAffineTransform(scaleX: 0.4, y: 0.4)
                UIView.animate(withDuration: 0.3, delay: Double(i) * 0.05) {
                    s.alpha = 1
                    s.transform = .identity
                }
            }
            nameLabel.attributedText = PhaseOverlayView.tracked(def.label.uppercased(), size: 16,
                                                                color: CRT.gold, display: true,
                                                                kern: 1)
            // The CALLER's body, not raw def.description — the caller runs it
            // through itemDescription so {rank}/{suit}/{color} never leak.
            if !body.isEmpty {
                copyLabel.attributedText = CRTKit.attributed(body, size: 14, color: CRT.cardFace)
            }
            // An ITEM unlock — the deck ta-daa's shorter cousin, so the two
            // never get confused with each other.
            Sound.shared.itemUnlock()
        }
        return v
    }

    /// Resolve an item id to its label/description across every registry.
    static func itemDef(_ id: String) -> ItemDef? {
        let d = GameData.shared
        return d.stickerTypes.get(id) ?? d.pillarTypes.get(id) ?? d.baseTypes.get(id)
            ?? d.samePowerTypes.get(id) ?? d.packTypes.get(id)
    }
    static func itemLabel(_ id: String) -> String { itemDef(id)?.label ?? id }

    // MARK: - Web glyphs (GLYPHS, 24×24 viewBox)

    /// GLYPHS.complete — the five-point star, filled.
    static func glyphStar(size: CGFloat, color: UIColor) -> UIImage {
        let s = size / 24
        func pt(_ x: CGFloat, _ yy: CGFloat) -> CGPoint { CGPoint(x: x * s, y: yy * s) }
        let pts = [pt(12, 2), pt(14.6, 8.6), pt(21, 10), pt(16, 14.4), pt(17.6, 21),
                   pt(12, 17.3), pt(6.4, 21), pt(8, 14.4), pt(3, 10), pt(9.4, 8.6)]
        return UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { _ in
            let p = UIBezierPath()
            p.move(to: pts[0])
            for q in pts.dropFirst() { p.addLine(to: q) }
            p.close()
            color.setFill()
            p.fill()
        }
    }

    /// GLYPHS.eye — the stroked eye outline + filled pupil, for the peek hint.
    static func glyphEye(size: CGFloat, color: UIColor) -> UIImage {
        let s = size / 24
        func pt(_ x: CGFloat, _ yy: CGFloat) -> CGPoint { CGPoint(x: x * s, y: yy * s) }
        return UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { _ in
            let p = UIBezierPath()
            p.move(to: pt(2, 12))
            p.addCurve(to: pt(12, 5), controlPoint1: pt(2, 12), controlPoint2: pt(6, 5))
            p.addCurve(to: pt(22, 12), controlPoint1: pt(18, 5), controlPoint2: pt(22, 12))
            p.addCurve(to: pt(12, 19), controlPoint1: pt(22, 12), controlPoint2: pt(18, 19))
            p.addCurve(to: pt(2, 12), controlPoint1: pt(6, 19), controlPoint2: pt(2, 12))
            p.close()
            p.lineWidth = 2 * s
            color.setStroke()
            p.stroke()
            let r: CGFloat = 2.6 * s
            let pupil = UIBezierPath(ovalIn: CGRect(x: 12 * s - r, y: 12 * s - r,
                                                    width: r * 2, height: r * 2))
            color.setFill()
            pupil.fill()
        }
    }

    // MARK: - Mystery reveal

    /// The web MYSTERY EVENT modal (MYST1): a centred felt panel whose top rim
    /// reads the polarity (phosphor good / red bad), the GOLD display title, a
    /// cream art well centring what the outcome granted, the muted caption,
    /// and the phosphor CONTINUE.
    static func mystery(outcome: MysteryOutcome,
                        presenter: MysteryCast.Presenter? = nil,
                        deckId: String = "pink",
                        mapPeek: Bool = false,
                        /// The Old Joker's purge reveal (v6.62): one caption row
                        /// per AFFLICTED CARD ("7♦ · Leech · …") instead of one
                        /// per unique curse.
                        curseRowsPerCard: Bool = false,
                        onPeekChanged: ((Bool) -> Void)? = nil,
                        onDeck: (() -> Void)? = nil,
                        onContinue: @escaping () -> Void) -> PhaseOverlayView {
        let v = PhaseOverlayView(dim: 0.6)
        let panelW: CGFloat = 320
        let px = (360 - panelW) / 2

        let panel = PixelPanelView(face: CRT.feltMid, border: CRT.ink, shadowOffsetPx: 4)
        v.content.addSubview(panel)
        let rim = UIView()
        rim.backgroundColor = outcome.good ? CRT.phosphor : CRT.suitRed
        var py: CGFloat = 18

        // WHO is delivering the news — the Old Joker's header grammar (card
        // on the left, gold name and a spoken line beside it), above the
        // outcome panel proper. Absent for outcomes nobody delivers.
        if let p = presenter {
            let art = UIImageView(image: p.art)
            art.contentMode = .scaleAspectFit
            art.layer.magnificationFilter = .nearest
            art.frame = CGRect(x: 18, y: py, width: 56, height: 80)
            panel.addSubview(art)
            let textX: CGFloat = 18 + 56 + 12
            // The corner MAP chip claims the top-right when present.
            let textW = panelW - textX - 18 - (mapPeek ? 58 : 0)
            let name = CRTKit.label(p.name.uppercased(), size: 14, color: CRT.gold, display: true)
            // "THE BEHEADED QUEEN" is the longest name the slot must seat —
            // it shrinks to fit rather than truncating to "QU…".
            name.adjustsFontSizeToFitWidth = true
            name.minimumScaleFactor = 0.65
            name.frame = CGRect(x: textX, y: py, width: textW, height: 18)
            panel.addSubview(name)
            let speech = UILabel()
            speech.numberOfLines = 0
            speech.lineBreakMode = .byWordWrapping
            speech.attributedText = CRTKit.attributed("\u{201C}\(p.line)\u{201D}", size: 14,
                                                      color: CRT.cardFace)
            let sh = ceil(speech.sizeThatFits(CGSize(width: textW, height: 300)).height)
            speech.frame = CGRect(x: textX, y: py + 21, width: textW, height: sh)
            panel.addSubview(speech)
            py += max(80, 21 + sh) + 12
        }

        // The web renders the event name AS AUTHORED ("Cache") — no uppercase
        // transform on .fd-title.
        let title = CRTKit.label(outcome.title, size: 14, color: CRT.gold, display: true)
        title.textAlignment = .center
        title.frame = CGRect(x: 10, y: py, width: panelW - 20, height: 18)
        panel.addSubview(title)
        py += 30

        // The cream art well — the shared RESULT CONTAINER (OutcomeWell), only
        // when there is something REAL to show in it. The flag-arming outcomes
        // (Fire Sale, Markup, Restock, Mulligan, the shield turns) used to
        // draw a big empty well with a lone glyph; now they simply skip it and
        // the panel tightens up.
        if let well = OutcomeWell.from(outcome, deckId: deckId) {
            let art = well.build(width: panelW - 36)
            art.frame.origin = CGPoint(x: 18, y: py)
            panel.addSubview(art)
            py += art.frame.height + 12
            // A curse application: the afflicted cards are live (tap/hold
            // still answers with the full registry help), and the curse's
            // description now prints DIRECTLY under the well (v6.57) — one
            // caption per afflicting curse, red display name + cream registry
            // copy ("Cursed. " stripped; the reveal already said so). The old
            // "Tap or hold a marked card…" say-so line is gone: the say-so IS
            // the text. Static content sized up front — the panel never moves.
            if case .cursed(let pairs) = well {
                v.wireCurseCells(in: art)
                // One caption builder, two groupings: per unique curse (the
                // Two's reveal) or per afflicted card (the Joker's purge).
                func addCaption(_ cap: NSAttributedString) {
                    let label = UILabel()
                    label.attributedText = cap
                    label.textAlignment = .center
                    label.numberOfLines = 0
                    label.lineBreakMode = .byWordWrapping
                    let capH = max(18, ceil(label.sizeThatFits(
                        CGSize(width: panelW - 36, height: 300)).height))
                    label.frame = CGRect(x: 18, y: py, width: panelW - 36, height: capH)
                    panel.addSubview(label)
                    py += capH + 4
                }
                if curseRowsPerCard {
                    for pair in pairs {
                        for def in pair.curses {
                            let cap = NSMutableAttributedString()
                            cap.append(CRTKit.attributed(CurseCardCell.cardName(pair.card) + " · ",
                                                         size: CardInfo.nameSize, color: CRT.gold, display: true))
                            cap.append(CRTKit.attributed(def.label + " · ",
                                                         size: CardInfo.nameSize, color: CRT.suitRed, display: true))
                            cap.append(CRTKit.attributed(
                                def.description.replacingOccurrences(of: "Cursed. ", with: "")
                                    + CardInfo.provenance(onType: def.id, of: pair.card.stickers),
                                size: CardInfo.descSize, color: CRT.cardFace))
                            addCaption(cap)
                        }
                    }
                } else {
                    var seen = Set<String>()
                    for def in pairs.flatMap({ $0.curses }) where seen.insert(def.id).inserted {
                        let cap = NSMutableAttributedString()
                        cap.append(CRTKit.attributed(def.label.uppercased() + " — ",
                                                     size: CardInfo.nameSize, color: CRT.suitRed, display: true))
                        cap.append(CRTKit.attributed(
                            def.description.replacingOccurrences(of: "Cursed. ", with: ""),
                            size: CardInfo.descSize, color: CRT.cardFace))
                        addCaption(cap)
                    }
                }
                py += 8
            }
        }

        // 16pt, brighter (router batch): "Leech torn off your 7♥" was the
        // smallest line on the panel while being the entire news. Skipped
        // when the outcome has nothing to add (the coin reveals — the well's
        // signed figure already says it, v6.64).
        // THE QUEEN'S IMPRINT (v6.64): under the granted sticker's chip the
        // caption is its NAME (display type) over its registry description —
        // never a hand-written "A X sticker to place on a card".
        let subText: NSAttributedString?
        if outcome.key == "stickerPack", let sid = outcome.stickerId,
           let def = GameData.shared.stickerTypes.get(sid) {
            // CANONICAL STICKER NAME (v6.72, sized on the v6.74 info scale):
            // description-sized (16), BOLD (display face), gold — suit-red for
            // a curse. Never oversized.
            let t = NSMutableAttributedString()
            t.append(CRTKit.attributed(def.label, size: CardInfo.nameSize,
                                       color: def.cursed ? CRT.suitRed : CRT.gold,
                                       display: true))
            t.append(CRTKit.attributed("\n\(def.description)", size: CardInfo.descSize,
                                       color: CRT.cardFace.withAlphaComponent(0.9)))
            subText = t
        } else {
            subText = outcome.desc.isEmpty ? nil
                : CRTKit.attributed(outcome.desc, size: 16, color: CRT.cardFace.withAlphaComponent(0.9))
        }
        if let subText {
        let sub = UILabel()
        sub.attributedText = subText
        sub.textAlignment = .center
        sub.numberOfLines = 0
        sub.lineBreakMode = .byWordWrapping
        // sizeThatFits, NOT boundingRect: the pixel font's real line height
        // runs taller than its measured fragments, so a boundingRect-sized
        // frame rendered "…until you…" instead of wrapping (v6.20).
        let subH = ceil(sub.sizeThatFits(CGSize(width: panelW - 36, height: 300)).height)
        sub.frame = CGRect(x: 18, y: py, width: panelW - 36, height: subH)
        panel.addSubview(sub)
        py += subH + 14
        }

        let go = PixelButtonView("CONTINUE", role: .cta, fontSize: 16)
        go.playsClick = false         // it owns the louder CTA confirm instead
        go.onTap = { Sound.shared.continueTap(); onContinue() }
        go.frame = CGRect(x: (panelW - 170) / 2, y: py, width: 170, height: 44)
        panel.addSubview(go)
        py += 44 + 20

        // MAP: a small corner chip (a pause-button cousin, never one of the
        // choices) — the explicit look-around with an explicit way back.
        // Travel stays blocked while peeking; outside taps never dismiss.
        if mapPeek {
            v.mapPeekChanged = onPeekChanged
            let peek = PixelButtonView("MAP", role: .plain, fontSize: 14)
            peek.onTap = { [weak v] in v?.beginMapPeek() }
            peek.frame = CGRect(x: panelW - 60, y: 8, width: 52, height: 26)
            panel.addSubview(peek)
            if let onDeck {
                // DECK under MAP (router batch 2): the shop's deck inspector.
                let deck = PixelButtonView("DECK", role: .plain, fontSize: 14)
                deck.onTap = { onDeck() }
                deck.frame = CGRect(x: panelW - 60, y: 38, width: 52, height: 26)
                panel.addSubview(deck)
            }
            let back = PixelButtonView("◀ BACK", role: .gold, fontSize: 16)
            back.onTap = { [weak v] in v?.endMapPeek() }
            back.isHidden = true
            v.addSubview(back)
            v.mapPeekBack = back
        }

        panel.frame = CGRect(x: px, y: 0, width: panelW, height: py)
        // The polarity rim, a 4px band under the panel's top border.
        rim.frame = CGRect(x: px + CRT.px, y: CRT.px, width: panelW - CRT.px * 2, height: 4)
        v.content.addSubview(rim)
        v.y = py
        // The modal announces itself with the outcome's own sound at open
        // (web MYSTERY_SOUND, fired as the panel unhides; Sound self-gates
        // on the enabled pref).
        switch outcome.key {
        // Coin GAINS ring the rising ting like every other gain (the flat
        // single `coin()` here made a windfall sound like small change).
        case "coinBonus", "coinDouble": Sound.shared.coinBonus()
        case "coinLoss": Sound.shared.coinLoss()
        case "cards", "giftCard": Sound.shared.mysteryCards()
        case "joker": Sound.shared.jokerReward()
        case "store": Sound.shared.mysteryStore()
        case "stickerPack": Sound.shared.sticker()
        // A strip or a theft REMOVES a sticker — the peel-off crumple, not
        // the cheerful apply-press (sound audit: polarity).
        case "stickerStrip", "stickerTheft": Sound.shared.stripSticker()
        case "freeRemoval": Sound.shared.freeRemoval()
        case "cursedSticker": Sound.shared.bad()
        case "ambush": Sound.shared.ambush()
        case "itemTheft", "shieldDrain", "priceDouble": Sound.shared.bad()
        // A Same-shield charge granted sounds like the shield family, not
        // like a shop appearing.
        case "shieldCharge": Sound.shared.sameBanked()
        case "priceOne", "freeRefresh", "freeRedeal": Sound.shared.mysteryStore()
        default: break
        }
        return v
    }
}

/// THE RESULT CONTAINER — the cream bordered art well every event family
/// shares. When an effect resolves, what changed is SHOWN here as art (a card
/// strip, an item tile, a sticker chip, a coin figure), never only named in a
/// sentence. One component, three voices: the mystery reveal (the Queen and
/// the Two), the Old Joker's conversation modal, and the chained reveals.
/// `from(_:)` maps a MysteryOutcome to its content; the Old Joker's closing
/// modals build cases directly from OldJoker.Result.
enum OutcomeWell {
    /// The ambush, depicted: the piles you'll face, face down.
    case ambush(piles: Int, deckId: String)
    /// A card strip (grants, cuts, curses) plus any torn-off sticker chips
    /// beside it, so what left is seen and not just named.
    case cards([CardSpec], torn: [ItemDef])
    /// The cards that LEFT the deck (the Old Joker's cut/purge results) —
    /// drawn TORN, never intact (v6.56): a purged card can't keep posing for
    /// its portrait. The art is the v6.53 blank-pickup treatment
    /// (`ItemArt.removal`, the torn Purge card).
    case purged([CardSpec])
    /// Cursed cards (v6.55): each afflicted card drawn with ALL its sticker
    /// chips riding the top-right corner exactly as on the board (v6.65 —
    /// the new curse no longer hides the card's paid stickers). Cells answer
    /// tap AND hold with the curse's registry help (wired by the mystery
    /// reveal). `curses` is the AFFLICTING set only: it drives the captions.
    case cursed([(card: CardSpec, curses: [ItemDef])])
    /// One sticker chip (granted or inflicted).
    case sticker(ItemDef)
    /// An equipped item's own tile art (traded / taken / sold).
    case item(kind: String, id: String, deckId: String)
    /// The shop stall (detours, comped shelves).
    case shop
    /// The torn-card removal art (a Purge/Cleanse picker still to come).
    case removal
    /// A signed coin figure.
    case coins(amount: Int, positive: Bool)

    /// The mystery reveal's content precedence, unchanged from when this
    /// lived inline: ambush > cards > sticker > item > stall > removal > coins.
    static func from(_ outcome: MysteryOutcome, deckId: String) -> OutcomeWell? {
        if outcome.key == "ambush" {
            return .ambush(piles: outcome.ambushPiles ?? 4, deckId: deckId)
        }
        // A curse application shows the afflicted CARDS, each wearing all its
        // sticker chips (v6.55/v6.65) — the chip alone ("a Leech exists
        // somewhere") never landed which card was marked. The Just a Two
        // outcome arrives with the card resolved by the caller; the Old
        // Joker's "His marks" reveal already carries every marked card.
        if outcome.key == "cursedSticker", !outcome.cards.isEmpty {
            let pairs: [(card: CardSpec, curses: [ItemDef])] = outcome.cards.compactMap { c in
                let curses = c.stickers
                    .compactMap { GameData.shared.stickerTypes.get($0.type) }
                    .filter(\.cursed)
                return curses.isEmpty ? nil : (c, curses)
            }
            if !pairs.isEmpty { return .cursed(pairs) }
        }
        if !outcome.cards.isEmpty {
            let torn = outcome.stickerIds.compactMap { GameData.shared.stickerTypes.get($0) }
            return .cards(outcome.cards, torn: torn)
        }
        if let sid = outcome.stickerId, let def = GameData.shared.stickerTypes.get(sid) {
            return .sticker(def)
        }
        if let ik = outcome.itemKind, let iid = outcome.itemId {
            // itemTheft: the repossessed Pillar/Base, so the loss is SEEN.
            return .item(kind: ik, id: iid, deckId: "")
        }
        if outcome.key == "store" { return .shop }
        // Purge/Cleanse: the torn-card REMOVAL art, never the generic ★.
        if outcome.key == "freeRemoval" || outcome.key == "stickerStrip" { return .removal }
        if let amount = outcome.amount {
            return .coins(amount: abs(amount), positive: outcome.good)
        }
        // Nothing worth a picture — no well at all.
        return nil
    }

    private func pixelImage(_ image: UIImage) -> UIImageView {
        let iv = UIImageView(image: image)
        iv.contentMode = .scaleAspectFit
        iv.layer.magnificationFilter = .nearest
        return iv
    }

    /// Build the well at `width`, frame sized to its content (fixed heights —
    /// the container never grows past one row; strips cap at 4 cards, chips
    /// at the per-card sticker ceiling).
    func build(width: CGFloat) -> UIView {
        let box = UIView()
        box.backgroundColor = CRT.cardFace
        box.layer.borderWidth = CRT.px
        box.layer.borderColor = CRT.ink.cgColor
        var h: CGFloat = 96
        switch self {
        case .ambush(let piles, let deckId):
            let n = max(1, min(piles, 4))
            let w: CGFloat = 58
            let rowW = CGFloat(n) * (w + 8) - 8
            h = 100
            let backFace = CardArt.Face(label: "", suit: "", kind: .back(deckId: deckId))
            for i in 0..<n {
                let iv = pixelImage(CardArt.image(backFace, scale: .half))
                iv.frame = CGRect(x: (width - rowW) / 2 + CGFloat(i) * (w + 8), y: 10,
                                  width: w, height: 80)
                box.addSubview(iv)
            }
        case .cards(let cards, let torn):
            let n = min(cards.count, 4)
            let w: CGFloat = 58
            let chipS: CGFloat = 34
            // EVERY torn sticker shows, up to the per-card cap (v6.72 — the
            // old 3-chip cap silently hid the 4th sticker a Cleanse tore
            // off). The row compresses into an overlap when the well runs
            // tight, chips never shrink below recognizability.
            let chips = Array(torn.prefix(GameData.shared.items.maxStickersPerCard))
            let cardsW = CGFloat(n) * (w + 8) - 8
            let chipAvail = width - 16 - cardsW - 8
            let chipStep = chips.count > 1
                ? min(chipS + 4, max(chipS * 0.4, (chipAvail - chipS) / CGFloat(chips.count - 1)))
                : chipS + 4
            let chipsW = chips.isEmpty ? 0 : chipS + chipStep * CGFloat(chips.count - 1) + 8
            let rowW = cardsW + chipsW
            h = 100
            for (i, c) in cards.prefix(4).enumerated() {
                // A BLANK card in the strip is a Purge — the v6.53 torn card,
                // same as the map's blank pickups.
                let iv = c.blank
                    ? pixelImage(ItemArt.removal(width: w, height: 80))
                    : pixelImage(CardArt.image(CardArt.Face(c), scale: .half))
                iv.frame = CGRect(x: (width - rowW) / 2 + CGFloat(i) * (w + 8), y: 10,
                                  width: w, height: 80)
                box.addSubview(iv)
            }
            // Reversed ADD order keeps the first torn chip on top without
            // sibling zPositions (the trap CardComposite's header documents).
            for (i, def) in chips.enumerated().reversed() {
                let iv = pixelImage(ItemArt.sticker(def, size: chipS))
                iv.frame = CGRect(x: (width - rowW) / 2 + cardsW + 8
                                     + CGFloat(i) * chipStep,
                                  y: 10 + (80 - chipS) / 2, width: chipS, height: chipS)
                box.addSubview(iv)
            }
        case .purged(let cards):
            // v6.91: the ACTUAL purged cards — face + full sticker fan via
            // CardComposite (the one UIKit renderer) — beside the Purge
            // logo, so the player sees WHAT left. (The old cells drew N
            // identical torn placeholders and never read the payload.)
            let shownCap = 3   // + the logo cell = the well's 4-cell row
            let shown = Array(cards.prefix(shownCap))
            let w: CGFloat = 58
            let cells = shown.count + 1   // the logo leads the row
            let rowW = CGFloat(cells) * (w + 8) - 8
            h = 104
            let logo = pixelImage(ItemArt.removal(width: w, height: 80))
            logo.frame = CGRect(x: (width - rowW) / 2, y: 12, width: w, height: 80)
            box.addSubview(logo)
            for (i, c) in shown.enumerated() {
                let iv = pixelImage(CardComposite.image(c))
                iv.frame = CGRect(x: (width - rowW) / 2 + CGFloat(i + 1) * (w + 8),
                                  y: 12 - StickerChipLayout.topRaise,
                                  width: w + StickerChipLayout.rightOverhang,
                                  height: 80 + StickerChipLayout.topRaise)
                box.addSubview(iv)
            }
        case .cursed(let pairs):
            // One cell per afflicted card (cap 4, the .cards strip's rule).
            let n = min(pairs.count, 4)
            let cellW: CGFloat = 62, cellH: CGFloat = 84
            let rowW = CGFloat(n) * (cellW + 8) - 8
            h = 104
            for (i, pair) in pairs.prefix(4).enumerated() {
                let cell = CurseCardCell(card: pair.card, curses: pair.curses)
                cell.frame = CGRect(x: (width - rowW) / 2 + CGFloat(i) * (cellW + 8),
                                    y: (h - cellH) / 2, width: cellW, height: cellH)
                box.addSubview(cell)
            }
        case .sticker(let def):
            let iv = pixelImage(ItemArt.sticker(def, size: 64))
            iv.frame = CGRect(x: (width - 64) / 2, y: 16, width: 64, height: 64)
            box.addSubview(iv)
        case .item(let kind, let id, let deckId):
            let iv = pixelImage(ItemArt.forSlot(kind: kind, id: id, card: nil, deckId: deckId))
            iv.frame = CGRect(x: (width - 64) / 2, y: 16, width: 64, height: 64)
            box.addSubview(iv)
        case .shop:
            let iv = pixelImage(MapArt.shopStall())
            iv.frame = CGRect(x: (width - 64) / 2, y: 20, width: 64, height: 56)
            box.addSubview(iv)
        case .removal:
            let iv = pixelImage(ItemArt.removal(width: 56, height: 72))
            iv.frame = CGRect(x: (width - 56) / 2, y: 12, width: 56, height: 72)
            box.addSubview(iv)
        case .coins(let amount, let positive):
            let coins = UILabel()
            let text = NSMutableAttributedString()
            text.append(NSAttributedString(string: "◉ ",
                                           attributes: [.font: CRT.Font.of(34),
                                                        .foregroundColor: CRT.gold]))
            text.append(NSAttributedString(string: "\(positive ? "+" : "−")\(amount)",
                                           attributes: [.font: CRT.Font.of(34),
                                                        .foregroundColor: CRT.gold]))
            coins.attributedText = text
            coins.textAlignment = .center
            coins.frame = CGRect(x: 0, y: 28, width: width, height: 40)
            box.addSubview(coins)
        }
        box.frame = CGRect(x: 0, y: 0, width: width, height: h)
        return box
    }
}

/// One afflicted card in the curse reveal's well (v6.55): the card face with
/// EVERY sticker it wears riding the top-right corner — the board's badge
/// idiom (fanning leftward, −11° + idx·8° lean), same as the deal screen and
/// the deck inspector. (v6.65: the cell used to draw only the new curse, so a
/// card carrying paid stickers showed up oddly bare; curses render their own
/// corruption art via `ItemArt.sticker`, plain stickers their normal chips.)
/// `curses` still drives the captions and the help panel. Cells answer tap
/// AND hold with the curse's registry help (wired by the mystery reveal).
private final class CurseCardCell: UIView {
    let card: CardSpec
    let curses: [ItemDef]
    var onTapCell: ((CurseCardCell) -> Void)?
    var onHoldCell: ((CurseCardCell, Bool) -> Void)?

    init(card: CardSpec, curses: [ItemDef]) {
        self.card = card
        self.curses = curses
        super.init(frame: .zero)
        // ONE renderer (v6.86): face + FULL chip fan baked by CardComposite.
        // The hand-placed sibling chips this cell used to draw were the last
        // surviving copy of the negative-zPosition trap (CardComposite's
        // header): chips 2…4 sank beneath the sibling card face, so a card
        // that already wore a sticker showed only ONE mark on the Old
        // Joker's reveal. A baked image has no z to get wrong; the canvas
        // grows by the fan's overhang/raise so nothing clips.
        let cardFrame = CGRect(x: 0, y: 4, width: 58, height: 80)
        let iv = UIImageView(image: CardComposite.image(card))
        iv.contentMode = .scaleAspectFit
        iv.layer.magnificationFilter = .nearest
        iv.frame = CGRect(x: cardFrame.minX,
                          y: cardFrame.minY - StickerChipLayout.topRaise,
                          width: cardFrame.width + StickerChipLayout.rightOverhang,
                          height: cardFrame.height + StickerChipLayout.topRaise)
        addSubview(iv)
        // The tap/hold pair, exactly the deck inspector's card-help idiom.
        isUserInteractionEnabled = true
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))
        hold.minimumPressDuration = 0.4
        addGestureRecognizer(hold)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityIdentifier = "curseCell"
        accessibilityLabel = "\(Self.cardName(card)), cursed: \(curses.map(\.label).joined(separator: ", "))"
        accessibilityHint = "Tap or hold to read the curse"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    /// "K♠" / "★ Joker" — the deck inspector's naming, inlined (GameCore's
    /// own stays internal to the engine).
    static func cardName(_ c: CardSpec) -> String {
        if c.joker { return "★ Joker" }
        if c.blank { return "∅ Purge" }
        let label = DeckManager.ranks.first { $0.value == c.currentRank }?.label ?? "\(c.currentRank)"
        return "\(label)\(c.suit)"
    }

    @objc private func tapped(_ g: UITapGestureRecognizer) {
        onTapCell?(self)
    }

    @objc private func held(_ g: UILongPressGestureRecognizer) {
        switch g.state {
        case .began: onHoldCell?(self, true)
        case .ended, .cancelled, .failed: onHoldCell?(self, false)
        default: break
        }
    }
}

/// A run-stat tile (the web's `.run-stat`): felt-mid pixel plaque, phosphor
/// display readout over a small muted uppercase label.
private final class StatTileView: UIView {
    private let panel = PixelPanelView(face: CRT.feltMid, border: CRT.ink)
    private let valueLabel = UILabel()
    private let nameLabel = UILabel()

    init(value: NSAttributedString, name: String) {
        super.init(frame: .zero)
        addSubview(panel)
        valueLabel.attributedText = value
        valueLabel.textAlignment = .center
        addSubview(valueLabel)
        nameLabel.attributedText = PhaseOverlayView.tracked(name.uppercased(), size: 14,
                                                            color: CRT.muted, kern: 1)
        nameLabel.textAlignment = .center
        nameLabel.numberOfLines = 2
        addSubview(nameLabel)
        isAccessibilityElement = true
        accessibilityTraits = .staticText
        accessibilityLabel = "\(name): \(value.string)"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        panel.frame = bounds
        let nameH = min(30, ceil(nameLabel.sizeThatFits(
            CGSize(width: bounds.width - 8, height: 30)).height))
        nameLabel.frame = CGRect(x: 4, y: bounds.height - 6 - nameH,
                                 width: bounds.width - 8, height: nameH)
        valueLabel.frame = CGRect(x: 0, y: 0, width: bounds.width,
                                  height: nameLabel.frame.minY - 2)
    }
}

/// The dashed-gold tap-to-copy seed chip (the web's `.ov-seed`): "SEED ·
/// DECK-TIER-CODE" + the muted "tap to copy" hint; a tap copies and flashes
/// "copied ✓" with a solid border, then reverts.
private final class SeedChip: UIControl {
    private let seed: String
    private let border = CAShapeLayer()
    private let label = UILabel()
    private let hint = UILabel()
    let idealWidth: CGFloat
    let idealHeight: CGFloat = 28

    init(seed: String) {
        self.seed = seed
        let labelAttr = PhaseOverlayView.tracked("SEED · \(seed)", size: 14,
                                                 color: CRT.cardFace, kern: 1.1)
        let hintAttr = PhaseOverlayView.tracked("tap to copy", size: 14,
                                                color: CRT.muted, kern: 1.1)
        let pad: CGFloat = 14, gap: CGFloat = 8
        idealWidth = min(340, pad * 2 + ceil(labelAttr.size().width)
                         + gap + ceil(hintAttr.size().width))
        super.init(frame: .zero)
        border.fillColor = nil
        border.strokeColor = CRT.gold.cgColor
        border.lineWidth = CRT.px
        border.lineDashPattern = [6, 4]
        layer.addSublayer(border)
        label.attributedText = labelAttr
        addSubview(label)
        hint.attributedText = hintAttr
        addSubview(hint)
        addTarget(self, action: #selector(copySeed), for: .touchUpInside)
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = "Seed \(seed)"
        accessibilityHint = "Tap to copy"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        border.path = UIBezierPath(rect: bounds).cgPath
        let pad: CGFloat = 14, gap: CGFloat = 8
        let lw = ceil(label.attributedText!.size().width)
        label.frame = CGRect(x: pad, y: 0, width: lw, height: bounds.height)
        hint.frame = CGRect(x: pad + lw + gap, y: 0,
                            width: bounds.width - pad * 2 - lw - gap, height: bounds.height)
    }

    @objc private func copySeed() {
        UIPasteboard.general.string = seed
        border.lineDashPattern = nil
        hint.attributedText = PhaseOverlayView.tracked("copied ✓", size: 14,
                                                       color: CRT.gold, kern: 1.1)
        setNeedsLayout()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self else { return }
            self.border.lineDashPattern = [6, 4]
            self.hint.attributedText = PhaseOverlayView.tracked("tap to copy", size: 14,
                                                                color: CRT.muted, kern: 1.1)
            self.setNeedsLayout()
        }
    }
}
