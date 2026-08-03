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
    /// The inset win/lose bezel (nil = no frame — mystery / zen / unlock pops).
    private let bezel = UIView()
    /// Hold-to-peek (deal-cleared only): fade the whole overlay while a finger
    /// rests anywhere on it, restore on release — the web's `.overlay.peek`.
    private var peekEnabled = false

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
        backgroundColor = CRT.ink.withAlphaComponent(dim)
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
        // Inset by half the border width so the 4px bezel lands INSIDE the
        // screen edge (a CSS inset box-shadow), not centred on it.
        bezel.frame = bounds.insetBy(dx: CRT.px, dy: CRT.px)
        content.frame = CGRect(x: 0, y: 0, width: min(360, bounds.width - 24), height: y)
        content.center = CGPoint(x: bounds.midX, y: max(y / 2 + 40, bounds.midY - 20))
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

    /// A coin glyph + value pair (the web's COIN_SVG inline in a value).
    static func coinAttr(_ value: String, size: CGFloat, color: UIColor,
                         display: Bool = false, glow: Bool = false) -> NSAttributedString {
        let out = NSMutableAttributedString()
        if let coin = ArtBundle.image("pxi-coin") {
            let att = NSTextAttachment()
            att.image = coin
            let h = size * 0.95
            att.bounds = CGRect(x: 0, y: -2, width: h, height: h)
            out.append(NSAttributedString(attachment: att))
            out.append(NSAttributedString(string: " "))
        }
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
        addCentered(PhaseOverlayView.tracked(text.uppercased(), size: 12,
                                             color: CRT.phosphor, kern: 1.5),
                    spacingAfter: spacingAfter)
    }

    private func addGap(_ g: CGFloat) { y += g }

    @discardableResult
    private func addButton(_ title: String, role: PixelButtonView.Role = .cta,
                           width: CGFloat = 250, height: CGFloat = 48,
                           fontSize: CGFloat = 17,
                           handler: @escaping () -> Void) -> PixelButtonView {
        let b = PixelButtonView(title, role: role, fontSize: fontSize)
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
        return "\(squash(name))-\(squash(c.difficultyTier))-\(SeedCode.encode(c.runSeed))"
    }

    /// The score/best (+endless) tile set, the web's endScoreTilesHtml: bests
    /// never claim a record on exhibition runs.
    private static func scoreTiles(_ c: CampaignState) -> [StatTileView] {
        let s = c.stats.get()
        let exhibition = c.isExhibition()
        var tiles = [
            StatTileView(value: tileValue("\(c.getCampaignScore())", size: 17), name: "Score"),
            StatTileView(value: tileValue(exhibition ? "—" : "\(s.bestCampaignScore)", size: 17),
                         name: exhibition ? "Best · not recorded" : "Best"),
        ]
        if c.runWonBanked {
            tiles.append(StatTileView(value: tileValue("\(c.getEndlessScore())", size: 17),
                                      name: "Endless"))
            tiles.append(StatTileView(value: tileValue(exhibition ? "—" : "\(s.bestEndlessScore)", size: 17),
                                      name: exhibition ? "Best · not recorded" : "Endless best"))
        }
        return tiles
    }

    static func tileValue(_ text: String, size: CGFloat) -> NSAttributedString {
        CRTKit.attributed(text, size: size, color: CRT.phosphor, display: true, glow: true)
    }

    // MARK: - Deal cleared (SCORE plaque + rewards panel)

    static func dealCleared(info: GameFlowController.SummaryInfo,
                            onContinue: @escaping () -> Void) -> PhaseOverlayView {
        let v = PhaseOverlayView(frame: .win)
        v.addTitle("DEAL CLEARED")
        v.addProgress(info.progress, spacingAfter: 14)

        // The reveal cadence: the plaque, then each reward line ONE BY ONE,
        // each with its rising coin ping — the deal-won payoff moment.
        var delay = 0.35

        // SCORE is its own distinct plaque, ABOVE the rewards panel — never a
        // line in the coin list. A cleared deal always scores ≥ 1; product 0
        // means an ambush (coins only) and no plaque.
        if info.product > 0 {
            let plaque = PixelPanelView(face: CRT.feltMid, border: CRT.ink)
            plaque.frame = CGRect(x: 20, y: v.y, width: 320, height: 56)
            let val = UILabel()
            val.attributedText = PhaseOverlayView.tracked("SCORE +\(info.product)", size: 17,
                                                          color: CRT.phosphor, display: true,
                                                          kern: 0.5, glow: true)
            val.textAlignment = .center
            val.frame = CGRect(x: 0, y: 8, width: 320, height: 22)
            plaque.addSubview(val)
            let sub = UILabel()
            sub.attributedText = PhaseOverlayView.tracked(
                "\(info.aliveCount) piles × \(info.minAlive) smallest".uppercased(),
                size: 12, color: CRT.muted, kern: 1)
            sub.textAlignment = .center
            sub.frame = CGRect(x: 0, y: 32, width: 320, height: 16)
            plaque.addSubview(sub)
            plaque.alpha = 0
            v.content.addSubview(plaque)
            v.y += 56 + 10
            UIView.animate(withDuration: 0.25, delay: delay) { plaque.alpha = 1 }
            delay += 0.28
        }

        // The rewards PANEL (the web's .overlay-coins / coinBreakdownHtml):
        // "Deal reward" leads (an ambush has no flat base — its sub-row says
        // so), then "Sticker rewards" and "Pillar rewards" as their OWN main
        // rows with each bonus line as an italic sub-bullet ("None" when
        // empty), then the deal's "Total" and the "Coins held" balance AFTER
        // these earnings.
        let flatLine = info.lines.first(where: { $0.0 == "Deal reward" })
        let flat = flatLine?.1 ?? 0
        // summaryLines omits the flat row when it's 0 — only ambush/subset
        // deals have no flat base (Economy.dealFlat guards stage > 0).
        let ambush = flatLine == nil
        let extras = info.lines.filter { $0.0 != "Deal reward" }
        // Web partition (coinBreakdownHtml): an event line whose label names
        // a Pillar counts as a PILLAR reward; the "⚡ …" self-destruct statics
        // ride the pillar row too. Everything else is a sticker/event reward.
        let pillarLabels = Set(GameData.shared.pillarTypes.all().map(\.label))
        let isPillar: (String) -> Bool = { pillarLabels.contains($0) || $0.hasPrefix("⚡") }
        let pillarBullets = extras.filter { isPillar($0.0) }
        let stickerBullets = extras.filter { !isPillar($0.0) }
        let stickerTotal = stickerBullets.reduce(0) { $0 + $1.1 }
        let pillarTotal = pillarBullets.reduce(0) { $0 + $1.1 }
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
            let row = UIView(frame: CGRect(x: px, y: py, width: pw - px * 2, height: 20))
            let lab = UILabel()
            lab.attributedText = CRTKit.attributed(label, size: 15, color: CRT.cardFace)
            lab.frame = CGRect(x: 0, y: 0, width: 200, height: 20)
            row.addSubview(lab)
            let val = UILabel()
            val.attributedText = PhaseOverlayView.coinAttr("\(value)", size: 15, color: CRT.gold)
            val.textAlignment = .right
            val.frame = CGRect(x: pw - px * 2 - 120, y: 0, width: 120, height: 20)
            row.addSubview(val)
            py += 20
            return row
        }

        func subRow(_ label: String, _ value: String?) -> UIView {
            let row = UIView(frame: CGRect(x: px + 14, y: py, width: pw - px * 2 - 14, height: 15))
            let lab = UILabel()
            var attrs: [NSAttributedString.Key: Any] = [
                .font: CRT.Font.of(12),
                .foregroundColor: CRT.muted,
                .obliqueness: 0.18,   // VT323 has no italic cut — the web's .dc-sub slant
            ]
            lab.attributedText = NSAttributedString(string: label, attributes: attrs)
            lab.frame = CGRect(x: 0, y: 0, width: 220, height: 15)
            row.addSubview(lab)
            if let value {
                attrs[.obliqueness] = 0
                attrs[.foregroundColor] = CRT.cardFace
                let val = UILabel()
                val.attributedText = NSAttributedString(string: value, attributes: attrs)
                val.textAlignment = .right
                val.frame = CGRect(x: pw - px * 2 - 14 - 90, y: 0, width: 90, height: 15)
                row.addSubview(val)
            }
            py += 15
            return row
        }

        /// Sound per row kind: main rows ping in sequence, the Total lands
        /// HIGH (web coinTallyLine(6)), the balance gets a soft tick
        /// (web Sound.coin()), sub-bullets stay silent.
        enum RowKind { case main, sub, total, balance }
        var kinds: [RowKind] = []

        rows.append(mainRow("Deal reward", flat)); kinds.append(.main)
        if ambush { rows.append(subRow("Ambush", "no flat reward")); kinds.append(.sub) }
        py += 12
        rows.append(mainRow("Sticker rewards", stickerTotal)); kinds.append(.main)
        py += 3
        if stickerBullets.isEmpty {
            rows.append(subRow("None", nil)); kinds.append(.sub)
        } else {
            for (label, amount) in stickerBullets {
                rows.append(subRow(bulletLabel(label), sign(amount))); kinds.append(.sub)
            }
        }
        py += 12
        rows.append(mainRow("Pillar rewards", pillarTotal)); kinds.append(.main)
        py += 3
        if pillarBullets.isEmpty {
            rows.append(subRow("None", nil)); kinds.append(.sub)
        } else {
            for (label, amount) in pillarBullets {
                rows.append(subRow(bulletLabel(label), sign(amount))); kinds.append(.sub)
            }
        }
        py += 12
        rows.append(mainRow("Total", info.earned)); kinds.append(.total)
        rows.append(mainRow("Coins held", info.balance)); kinds.append(.balance)

        // Fixed shell (the capture's panel is one stable height; it only grows
        // when the bullet list genuinely needs more).
        let panelH = max(224, py + 2)
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
        hint.append(PhaseOverlayView.tracked("  Hold anywhere to peek the board",
                                             size: 12, color: CRT.muted, kern: 0))
        let hintLabel = UILabel()
        hintLabel.attributedText = hint
        hintLabel.textAlignment = .center
        hintLabel.alpha = 0.8
        hintLabel.frame = CGRect(x: 10, y: v.y, width: 340, height: 16)
        v.content.addSubview(hintLabel)
        v.y += 16
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
        v.addCentered(PhaseOverlayView.tracked("GAME OVER", size: 12, color: CRT.suitRed,
                                               display: true, kern: 2), spacingAfter: 4)
        v.addCentered(PhaseOverlayView.tracked("Shoulda said", size: 20, color: CRT.cardFace,
                                               display: true, kern: 0, hardShadow: true),
                      spacingAfter: 2)
        v.addCentered(PhaseOverlayView.tracked(PhaseOverlayView.survivingGuessWord ?? "lower",
                                               size: 20, color: CRT.phosphor, display: true,
                                               kern: 0, glow: true), spacingAfter: 8)
        if let c {
            v.addProgress("Reached " + PhaseOverlayView.stageRunShort(c), spacingAfter: 8)
        }

        v.addSeedBox(seed)
        v.addGap(4)

        // Stat tiles: SCORE / BEST (+ ENDLESS / ENDLESS BEST once banked),
        // then CARDS PLAYED / COINS, then the guess recap.
        if let c {
            v.addTileRow(PhaseOverlayView.scoreTiles(c), height: 64)
            v.addTileRow([
                StatTileView(value: tileValue("\(c.totalCardsFlipped)", size: 17), name: "Cards Played"),
                StatTileView(value: PhaseOverlayView.coinAttr("\(c.totalCoinsEarned)", size: 17,
                                                              color: CRT.phosphor,
                                                              display: true, glow: true),
                             name: "Coins"),
            ], height: 64)
            let correct = c.allGuessesCorrect
            let total = c.allGuessesTotal
            let wrong = max(0, total - correct)
            let pct = total > 0 ? Int((Double(correct) / Double(total) * 100).rounded()) : 0
            v.addTileRow([
                StatTileView(value: tileValue("\(correct)", size: 17), name: "Correct"),
                StatTileView(value: tileValue("\(wrong)", size: 17), name: "Wrong"),
                StatTileView(value: tileValue("\(pct)%", size: 17), name: "Accuracy"),
            ], height: 64)
        } else {
            // No campaign reachable (shouldn't happen in-app): the deal's own
            // numbers still give a coherent screen.
            let total = info.correct + info.wrong
            let pct = total > 0 ? Int((Double(info.correct) / Double(total) * 100).rounded()) : 0
            v.addTileRow([
                StatTileView(value: tileValue("\(info.cardsFlipped)", size: 17), name: "Cards Played"),
                StatTileView(value: PhaseOverlayView.coinAttr("\(info.coinsEarned)", size: 17,
                                                              color: CRT.phosphor,
                                                              display: true, glow: true),
                             name: "Coins"),
            ], height: 64)
            v.addTileRow([
                StatTileView(value: tileValue("\(info.correct)", size: 17), name: "Correct"),
                StatTileView(value: tileValue("\(info.wrong)", size: 17), name: "Wrong"),
                StatTileView(value: tileValue("\(pct)%", size: 17), name: "Accuracy"),
            ], height: 64)
        }

        v.addGap(8)
        v.addButton("MAIN MENU") { onNewClimb() }
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
            // The victory screen is post-boss (banked), so the endless pair
            // always shows — SCORE / BEST / ENDLESS / ENDLESS BEST.
            let s = c.stats.get()
            let exhibition = c.isExhibition()
            v.addTileRow([
                StatTileView(value: tileValue("\(score)", size: 14), name: "Score"),
                StatTileView(value: tileValue(exhibition ? "—" : "\(bestScore)", size: 14),
                             name: exhibition ? "Best · not recorded" : "Best"),
                StatTileView(value: tileValue("\(c.getEndlessScore())", size: 14), name: "Endless"),
                StatTileView(value: tileValue(exhibition ? "—" : "\(s.bestEndlessScore)", size: 14),
                             name: exhibition ? "Best · not recorded" : "Endless best"),
            ], height: 56)
            v.addTileRow([
                StatTileView(value: tileValue("\(cards)", size: 14), name: "Cards Played"),
                StatTileView(value: PhaseOverlayView.coinAttr("\(coins)", size: 14,
                                                              color: CRT.phosphor,
                                                              display: true, glow: true),
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
        let primary = v.addButton("CONTINUE — ENDLESS MODE", role: .cta,
                                  width: 300, height: 64, fontSize: 15) { onEndless() }
        // The web's primary wraps to two lines; PixelButtonView's label is
        // single-line by default.
        if let label = primary.subviews.compactMap({ $0 as? UILabel }).first {
            label.numberOfLines = 0
            label.lineBreakMode = .byWordWrapping
        }
        v.addButton("GO TO MAIN MENU", role: .plain, fontSize: 15) { onMenu() }
        return v
    }

    // MARK: - Zen end

    static func zenEnd(won: Bool, flips: Int, correct: Int,
                       outcomeCount: Int? = nil, unlockLabel: String? = nil,
                       onAgain: @escaping () -> Void,
                       onMenu: @escaping () -> Void) -> PhaseOverlayView {
        let v = PhaseOverlayView()
        if won {
            v.addTitle("DECK CLEARED", color: CRT.phosphor)
        } else {
            // The web's onZenEnd loss header: the same "Shoulda said <word>"
            // treatment as the campaign death screen (gameOverTitleHtml).
            v.addCentered(PhaseOverlayView.tracked("GAME OVER", size: 12, color: CRT.suitRed,
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
        // The per-game tiles (web zenStatsHtml): THIS game only — cards
        // guessed / correct / wrong / accuracy, then the outcome-specific
        // count (piles standing on a win, cards left in the deck on a loss).
        // Wrong and accuracy derive locally; outcomeCount stays "—" until the
        // caller wires the live board count.
        let wrong = max(0, flips - correct)
        let pct = flips > 0 ? Int((Double(correct) / Double(flips) * 100).rounded()) : 0
        v.addTileRow([
            StatTileView(value: tileValue("\(flips)", size: 14), name: "Cards guessed"),
            StatTileView(value: tileValue("\(correct)", size: 14), name: "Correct"),
            StatTileView(value: tileValue("\(wrong)", size: 14), name: "Wrong"),
            StatTileView(value: tileValue("\(pct)%", size: 14), name: "Accuracy"),
            StatTileView(value: tileValue(outcomeCount.map { "\($0)" } ?? "—", size: 14),
                         name: won ? "Piles remaining" : "Cards left in deck"),
        ], height: 64, gap: 6, width: 340)
        v.addGap(6)
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
        v.addCentered(PhaseOverlayView.tracked("NEW DECK UNLOCKED", size: 12,
                                               color: CRT.gold, display: true, kern: 2),
                      spacingAfter: 10)
        v.addSprite(DeckCharacter.image(deckId: deckId, mood: .happy, scale: 5),
                    size: CGSize(width: 96, height: 96))
        let nameLabel = UILabel()
        nameLabel.attributedText = PhaseOverlayView.tracked("???", size: 15, color: CRT.gold,
                                                            display: true, kern: 1, glow: false)
        nameLabel.textAlignment = .center
        nameLabel.frame = CGRect(x: 0, y: v.y, width: 360, height: 22)
        v.content.addSubview(nameLabel)
        v.y += 28
        // The previous deck hands off: "<Prev> made it home — say hello to
        // <Name>!" (web duc-copy; a nil prev reads "You", like the web).
        v.addCentered(CRTKit.attributed("\(prevName ?? "You") made it home — say hello to \(name)!",
                                        size: 15, color: CRT.cardFace), spacingAfter: 12)
        v.addButton("CONTINUE") { onContinue() }
        // The entrance bounce first (color floods in), then the name reveal
        // lands the sparkly ta-daa — one-shot, transform/opacity only.
        v.content.transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
        UIView.animate(withDuration: 0.5, delay: 0.05, usingSpringWithDamping: 0.55,
                       initialSpringVelocity: 0.4) {
            v.content.transform = .identity
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            nameLabel.attributedText = PhaseOverlayView.tracked(name.uppercased(), size: 15,
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

    static func itemUnlock(title: String, body: String,
                           itemId: String? = nil, hint: String? = nil,
                           onContinue: @escaping () -> Void) -> PhaseOverlayView {
        let v = PhaseOverlayView()
        guard let itemId, let def = itemDef(itemId) else {
            // No item context (the 4+ summary pop): the plain pop stays.
            v.addTitle(title, color: CRT.gold, size: 13)
            v.addCentered(CRTKit.attributed(body, size: 14, color: CRT.cardFace), spacingAfter: 12)
            v.addButton("CONTINUE") { onContinue() }
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
                                               size: 12, color: CRT.gold, display: true, kern: 2),
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
        nameLabel.attributedText = PhaseOverlayView.tracked("???", size: 15, color: CRT.gold,
                                                            display: true, kern: 1)
        nameLabel.textAlignment = .center
        nameLabel.frame = CGRect(x: 0, y: v.y, width: 360, height: 22)
        v.content.addSubview(nameLabel)
        v.y += 28

        let copyLabel = UILabel()
        copyLabel.attributedText = CRTKit.attributed(hint ?? body, size: 14, color: CRT.cardFace)
        copyLabel.textAlignment = .center
        copyLabel.numberOfLines = 0
        let copyH = ceil(copyLabel.attributedText!.boundingRect(
            with: CGSize(width: 320, height: 200),
            options: .usesLineFragmentOrigin, context: nil).height)
        copyLabel.frame = CGRect(x: 20, y: v.y, width: 320, height: copyH)
        v.content.addSubview(copyLabel)
        v.y += copyH + 6

        // "Earned: <hint>" — the footnote that keeps the earn condition
        // visible after the copy swaps to the description.
        let earnedLabel = UILabel()
        let earnedH: CGFloat = 16
        earnedLabel.frame = CGRect(x: 20, y: v.y, width: 320, height: earnedH)
        earnedLabel.textAlignment = .center
        earnedLabel.alpha = 0
        v.content.addSubview(earnedLabel)
        v.y += earnedH + 12

        v.addButton("CONTINUE") { onContinue() }

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
            nameLabel.attributedText = PhaseOverlayView.tracked(def.label.uppercased(), size: 15,
                                                                color: CRT.gold, display: true,
                                                                kern: 1)
            let desc = def.description
            if !desc.isEmpty {
                copyLabel.attributedText = CRTKit.attributed(desc, size: 14, color: CRT.cardFace)
                if let hint {
                    earnedLabel.attributedText = PhaseOverlayView.tracked("Earned: \(hint)",
                                                                          size: 12, color: CRT.muted,
                                                                          kern: 0.5)
                    UIView.animate(withDuration: 0.2, delay: 0.15) { earnedLabel.alpha = 1 }
                }
            }
            Sound.shared.deckUnlock()
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
                        onContinue: @escaping () -> Void) -> PhaseOverlayView {
        let v = PhaseOverlayView(dim: 0.6)
        let panelW: CGFloat = 320
        let px = (360 - panelW) / 2

        let panel = PixelPanelView(face: CRT.feltMid, border: CRT.ink, shadowOffsetPx: 4)
        v.content.addSubview(panel)
        let rim = UIView()
        rim.backgroundColor = outcome.good ? CRT.phosphor : CRT.suitRed
        var py: CGFloat = 18

        // The web renders the event name AS AUTHORED ("Cache") — no uppercase
        // transform on .fd-title.
        let title = CRTKit.label(outcome.title, size: 12, color: CRT.gold, display: true)
        title.textAlignment = .center
        title.frame = CGRect(x: 10, y: py, width: panelW - 20, height: 18)
        panel.addSubview(title)
        py += 30

        // The cream art well.
        let art = UIView()
        art.backgroundColor = CRT.cardFace
        art.layer.borderWidth = CRT.px
        art.layer.borderColor = CRT.ink.cgColor
        var artH: CGFloat = 96
        if !outcome.cards.isEmpty {
            let n = min(outcome.cards.count, 4)
            let w: CGFloat = 58
            let rowW = CGFloat(n) * (w + 8) - 8
            artH = 100
            for (i, c) in outcome.cards.prefix(4).enumerated() {
                let iv = UIImageView(image: CardArt.image(CardArt.Face(c), scale: .half))
                iv.contentMode = .scaleAspectFit
                iv.layer.magnificationFilter = .nearest
                iv.frame = CGRect(x: (panelW - 36 - rowW) / 2 + CGFloat(i) * (w + 8), y: 10, width: w, height: 80)
                art.addSubview(iv)
            }
        } else if let sid = outcome.stickerId, let def = GameData.shared.stickerTypes.get(sid) {
            let iv = UIImageView(image: ItemArt.sticker(def, size: 64))
            iv.contentMode = .scaleAspectFit
            iv.layer.magnificationFilter = .nearest
            iv.frame = CGRect(x: (panelW - 36 - 64) / 2, y: 16, width: 64, height: 64)
            art.addSubview(iv)
        } else if outcome.key == "store" {
            let iv = UIImageView(image: MapArt.shopStall())
            iv.contentMode = .scaleAspectFit
            iv.layer.magnificationFilter = .nearest
            iv.frame = CGRect(x: (panelW - 36 - 64) / 2, y: 20, width: 64, height: 56)
            art.addSubview(iv)
        } else if outcome.key == "freeRemoval" || outcome.key == "stickerStrip" {
            // Purge/Cleanse: the torn-card REMOVAL art, never the generic ★.
            let iv = UIImageView(image: ItemArt.removal(width: 56, height: 72))
            iv.contentMode = .scaleAspectFit
            iv.layer.magnificationFilter = .nearest
            iv.frame = CGRect(x: (panelW - 36 - 56) / 2, y: 12, width: 56, height: 72)
            art.addSubview(iv)
        } else if let amount = outcome.amount {
            let sign = outcome.good ? "+" : "−"
            let coins = UILabel()
            let text = NSMutableAttributedString()
            if let coin = ArtBundle.image("pxi-coin") {
                let att = NSTextAttachment()
                att.image = coin
                att.bounds = CGRect(x: 0, y: -3, width: 28, height: 28)
                text.append(NSAttributedString(attachment: att))
                text.append(NSAttributedString(string: " "))
            }
            text.append(NSAttributedString(string: "\(sign)\(abs(amount))",
                                           attributes: [.font: CRT.Font.of(34), .foregroundColor: CRT.gold]))
            coins.attributedText = text
            coins.textAlignment = .center
            coins.frame = CGRect(x: 0, y: 28, width: panelW - 36, height: 40)
            art.addSubview(coins)
        } else {
            let glyph = CRTKit.label(outcome.good ? "★" : "☠", size: 44,
                                     color: outcome.good ? CRT.gold : CRT.suitRed)
            glyph.textAlignment = .center
            glyph.frame = CGRect(x: 0, y: 24, width: panelW - 36, height: 50)
            art.addSubview(glyph)
        }
        art.frame = CGRect(x: 18, y: py, width: panelW - 36, height: artH)
        panel.addSubview(art)
        py += artH + 12

        let sub = CRTKit.label(outcome.desc, size: 13, color: CRT.muted)
        sub.textAlignment = .center
        sub.numberOfLines = 0
        let subH = ceil(sub.attributedText!.boundingRect(with: CGSize(width: panelW - 36, height: 200),
                                                         options: .usesLineFragmentOrigin, context: nil).height)
        sub.frame = CGRect(x: 18, y: py, width: panelW - 36, height: subH)
        panel.addSubview(sub)
        py += subH + 14

        let go = PixelButtonView("CONTINUE", role: .cta, fontSize: 15)
        go.onTap = { Sound.shared.continueTap(); onContinue() }
        go.frame = CGRect(x: (panelW - 170) / 2, y: py, width: 170, height: 44)
        panel.addSubview(go)
        py += 44 + 20

        panel.frame = CGRect(x: px, y: 0, width: panelW, height: py)
        // The polarity rim, a 4px band under the panel's top border.
        rim.frame = CGRect(x: px + CRT.px, y: CRT.px, width: panelW - CRT.px * 2, height: 4)
        v.content.addSubview(rim)
        v.y = py
        // The modal announces itself with the outcome's own sound at open
        // (web MYSTERY_SOUND, fired as the panel unhides; Sound self-gates
        // on the enabled pref).
        switch outcome.key {
        case "coinBonus": Sound.shared.coin()
        case "coinLoss": Sound.shared.coinLoss()
        case "cards": Sound.shared.mapAdd()
        case "joker": Sound.shared.deckUnlock()
        case "store": Sound.shared.refresh()
        case "stickerPack", "stickerStrip": Sound.shared.sticker()
        case "freeRemoval": Sound.shared.pack()
        case "cursedSticker": Sound.shared.bad()
        case "ambush": Sound.shared.deal()
        default: break
        }
        return v
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
        nameLabel.attributedText = PhaseOverlayView.tracked(name.uppercased(), size: 12,
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
        let labelAttr = PhaseOverlayView.tracked("SEED · \(seed)", size: 12,
                                                 color: CRT.cardFace, kern: 1.1)
        let hintAttr = PhaseOverlayView.tracked("tap to copy", size: 12,
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
        hint.attributedText = PhaseOverlayView.tracked("copied ✓", size: 12,
                                                       color: CRT.gold, kern: 1.1)
        setNeedsLayout()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self else { return }
            self.border.lineDashPattern = [6, 4]
            self.hint.attributedText = PhaseOverlayView.tracked("tap to copy", size: 12,
                                                                color: CRT.muted, kern: 1.1)
            self.setNeedsLayout()
        }
    }
}
