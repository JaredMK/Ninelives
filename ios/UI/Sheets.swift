import UIKit
import GameCore

// MARK: - Sheet chrome

/// Web `.sheet-overlay`/`.sheet-panel`: an ink scrim with a felt-mid pixel
/// panel rising from the bottom edge; display-marquee head + the ✕ square.
class SheetView: UIView, UIGestureRecognizerDelegate {
    let panel = UIView()
    private let headLabel = UILabel()
    private let closeButton = UIButton(type: .custom)
    let body = UIView()
    var onClose: (() -> Void)?
    private var bodyH: CGFloat = 300

    init(title: String) {
        super.init(frame: .zero)
        backgroundColor = CRT.ink.withAlphaComponent(0.72)
        // Scrim-only dismissal: the recognizer must never receive (and so
        // never cancel) touches on the panel's controls — the tutorial's
        // cancelsTouchesInView lesson.
        let tap = UITapGestureRecognizer(target: self, action: #selector(scrimTapped(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        addGestureRecognizer(tap)

        panel.backgroundColor = CRT.feltMid
        panel.layer.borderWidth = CRT.px
        panel.layer.borderColor = CRT.ink.cgColor
        addSubview(panel)

        headLabel.attributedText = CRTKit.attributed(title.uppercased(), size: 14,
                                                     color: CRT.phosphor, display: true, glow: true)
        panel.addSubview(headLabel)

        closeButton.setAttributedTitle(CRTKit.attributed("×", size: 18, color: CRT.cardFace), for: .normal)
        closeButton.backgroundColor = CRT.feltDeep
        closeButton.layer.borderWidth = CRT.px
        closeButton.layer.borderColor = CRT.ink.cgColor
        closeButton.addAction(UIAction { [weak self] _ in self?.dismiss() }, for: .touchUpInside)
        panel.addSubview(closeButton)
        panel.addSubview(body)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    func setBodyHeight(_ h: CGFloat) {
        bodyH = h
        setNeedsLayout()
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        touch.view === self
    }

    @objc private func scrimTapped(_ g: UITapGestureRecognizer) {
        if !panel.frame.contains(g.location(in: self)) { dismiss() }
    }

    func dismiss() {
        guard !dismissing else { return }
        dismissing = true   // freezes layoutSubviews — see below
        let target = panel.frame.height
        // The MIRROR of `present`: same duration, easeOut so the travel is
        // front-loaded and actually visible. The old easeIn put ~90% of the
        // movement in the last third while alpha had already reached 0, so the
        // panel never appeared to slide — it just blinked out, reading as a
        // collapse. The scrim fades on its own, slightly behind the panel, so
        // the slide stays legible the whole way down.
        UIView.animate(withDuration: 0.22, delay: 0,
                       options: [.curveEaseOut, .beginFromCurrentState]) {
            self.panel.transform = CGAffineTransform(translationX: 0, y: target)
        }
        UIView.animate(withDuration: 0.16, delay: 0.06,
                       options: [.curveLinear, .beginFromCurrentState]) {
            self.alpha = 0
        } completion: { _ in
            self.removeFromSuperview()
            self.onClose?()
        }
    }

    /// True from `dismiss()` until the panel is gone. Assigning `panel.frame`
    /// while its transform is non-identity re-anchors the box to the bottom and
    /// resizes it mid-flight — a layout pass landing inside the animation
    /// (safe-area propagation, the host's viewDidLayoutSubviews) is exactly
    /// what made the sheet look like it collapsed from the top.
    private var dismissing = false

    /// Present over `host` with the rise-from-the-bottom slide.
    func present(in host: UIView, below topmost: UIView? = nil) {
        frame = host.bounds
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        if let topmost { host.insertSubview(self, belowSubview: topmost) }
        else { host.addSubview(self) }
        layoutIfNeeded()
        panel.transform = CGAffineTransform(translationX: 0, y: panel.frame.height)
        alpha = 0.4
        UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseOut]) {
            self.panel.transform = .identity
            self.alpha = 1
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !dismissing else { return }
        let w = min(bounds.width, 460)
        let safeBottom = safeAreaInsets.bottom
        let panelH = min(bounds.height * 0.86, 14 + 30 + 12 + bodyH + 16 + safeBottom)
        // +px: the bottom border rides off-screen (border-bottom: none).
        panel.frame = CGRect(x: (bounds.width - w) / 2, y: bounds.height - panelH,
                             width: w, height: panelH + CRT.px)
        headLabel.frame = CGRect(x: 16, y: 14, width: w - 70, height: 30)
        closeButton.frame = CGRect(x: w - 46, y: 12, width: 30, height: 30)
        body.frame = CGRect(x: 16, y: 56, width: w - 32, height: panelH - 56 - 16 - safeBottom)
    }
}

// MARK: - Pause menu sheet

/// The in-game pause menu, web `#gameMenu`: the stacked menu buttons.
/// (v6.74: the tap-to-copy seed row was retired — the menu is exactly four
/// entries; the death/victory chips still carry the share string.)
final class PauseSheetView: SheetView {
    struct Item {
        let label: String
        let icon: UIImage?
        let role: PixelButtonView.Role
        let keepOpen: Bool
        let action: () -> Void
        init(_ label: String, icon: UIImage? = nil, role: PixelButtonView.Role = .plain,
             keepOpen: Bool = false, action: @escaping () -> Void) {
            self.label = label; self.icon = icon; self.role = role
            self.keepOpen = keepOpen; self.action = action
        }
    }

    private var items: [Item]

    init(items: [Item]) {
        self.items = items
        super.init(title: "Menu")
        build()
    }

    private func build() {
        body.subviews.forEach { $0.removeFromSuperview() }
        let colW: CGFloat = 300
        var y: CGFloat = 0
        for item in items {
            let b = PixelButtonView(item.label, role: item.role, fontSize: item.role == .cta ? 16 : 15)
            b.setIcon(item.icon)
            b.tag = 72
            b.onTap = { [weak self] in
                guard let self else { return }
                if item.keepOpen { item.action() } else {
                    // Close silently, then act (dismiss() would also fire onClose).
                    self.removeFromSuperview()
                    item.action()
                }
            }
            body.addSubview(b)
            y += (item.role == .cta ? 50 : 46) + 9
        }
        setBodyHeight(y)
        _ = colW
    }

    /// Toggle rows (Sound / Odds Assist) relabel in place.
    func setItems(_ items: [Item]) {
        self.items = items
        build()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let colW: CGFloat = min(300, body.bounds.width)
        let x = (body.bounds.width - colW) / 2
        var y: CGFloat = 0
        for v in body.subviews {
            if let b = v as? PixelButtonView {
                let h: CGFloat = b.title.contains("RESUME") ? 50 : 46
                b.frame = CGRect(x: x, y: y, width: colW, height: h)
                y += h + 9
            }
        }
    }
}

// MARK: - How-to-play sheet (the paged manual)

/// Web `showManual`: 8 mock-art slides with Skip · pager dots · Back/Next and
/// the Replay-tutorial secondary action.
final class ManualSheetView: SheetView {
    private struct Slide {
        let art: () -> UIView
        let lead: String
        let body: [(String, Bool)]   // (text, accent)
    }

    private var slides: [Slide] = []
    private var index = 0
    private let stage = UIView()
    private let artHolder = UIView()
    private let capLabel = UILabel()
    private let skipButton = UIButton(type: .custom)
    private let backButton = UIButton(type: .custom)
    private let nextButton = UIButton(type: .custom)
    private let dotsView = UIView()
    private let replayButton = UIButton(type: .custom)
    var onReplayTutorial: (() -> Void)?

    init(deckId: String) {
        super.init(title: "How to Play")
        slides = ManualSheetView.buildSlides(deckId: deckId)

        stage.backgroundColor = CRT.feltDeep
        stage.layer.borderWidth = CRT.px
        stage.layer.borderColor = CRT.ink.cgColor
        stage.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(stageTapped)))
        body.addSubview(stage)
        stage.addSubview(artHolder)
        capLabel.numberOfLines = 0
        capLabel.textAlignment = .center
        stage.addSubview(capLabel)

        styleNav(skipButton, "Skip", ghost: true)
        skipButton.addAction(UIAction { [weak self] _ in self?.dismiss() }, for: .touchUpInside)
        styleNav(backButton, "Back", ghost: false)
        backButton.addAction(UIAction { [weak self] _ in self?.go(-1) }, for: .touchUpInside)
        styleNav(nextButton, "Next", ghost: false, primary: true)
        nextButton.addAction(UIAction { [weak self] _ in self?.go(1) }, for: .touchUpInside)
        // Footer row + Replay ride the PANEL (not body): the web sheet stacks
        // them to the panel's bottom edge, below the shared body reservation.
        panel.addSubview(skipButton)
        panel.addSubview(backButton)
        panel.addSubview(nextButton)
        panel.addSubview(dotsView)

        replayButton.setAttributedTitle(CRTKit.attributed("↻ Replay tutorial", size: 16, color: CRT.cardFace), for: .normal)
        replayButton.backgroundColor = CRT.feltDeep
        replayButton.layer.borderWidth = 1
        replayButton.layer.borderColor = CRT.ink.cgColor
        replayButton.addAction(UIAction { [weak self] _ in
            self?.removeFromSuperview()
            self?.onReplayTutorial?()
        }, for: .touchUpInside)
        panel.addSubview(replayButton)

        setBodyHeight(325)
        render()
    }

    private func styleNav(_ b: UIButton, _ title: String, ghost: Bool, primary: Bool = false) {
        let color: UIColor = primary ? CRT.ink : (ghost ? CRT.muted : CRT.cardFace)
        b.setAttributedTitle(CRTKit.attributed(title.uppercased(), size: 14, color: color), for: .normal)
        if primary {
            b.backgroundColor = CRT.phosphor
            b.layer.borderWidth = CRT.px
            b.layer.borderColor = CRT.ink.cgColor
            b.layer.shadowColor = CRT.phosphor.cgColor
            b.layer.shadowRadius = 6
            b.layer.shadowOpacity = 0.5
            b.layer.shadowOffset = .zero
        } else if !ghost {
            b.backgroundColor = CRT.feltDeep
            b.layer.borderWidth = CRT.px
            b.layer.borderColor = CRT.ink.cgColor
        }
    }

    @objc private func stageTapped() { go(1) }

    private func go(_ step: Int) {
        let ni = index + step
        if ni < 0 { return }
        if ni >= slides.count { dismiss(); return }
        index = ni
        render()
    }

    private func render() {
        let s = slides[index]
        artHolder.subviews.forEach { $0.removeFromSuperview() }
        let art = s.art()
        artHolder.addSubview(art)
        // 15/16pt (v6.39): the old 12/13 was the smallest reading text in
        // the game, on the one screen a NEW player must actually read.
        let cap = NSMutableAttributedString(
            string: s.lead + "\n", attributes: [.font: CRT.Font.of(16, display: true),
                                                .foregroundColor: CRT.phosphor])
        for (text, accent) in s.body {
            cap.append(NSAttributedString(string: text, attributes: [
                .font: CRT.Font.of(16),
                .foregroundColor: accent ? CRT.phosphor : CRT.cardFace,
            ]))
        }
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.lineSpacing = 3
        para.paragraphSpacing = 6
        cap.addAttribute(.paragraphStyle, value: para, range: NSRange(location: 0, length: cap.length))
        capLabel.attributedText = cap

        // Dots.
        dotsView.subviews.forEach { $0.removeFromSuperview() }
        for (i, _) in slides.enumerated() {
            let d = UIView(frame: CGRect(x: CGFloat(i) * 13, y: 0, width: 7, height: 7))
            d.layer.cornerRadius = 3.5   // the sanctioned pager-dot circle
            d.backgroundColor = i == index ? CRT.phosphor : CRT.cardFace.withAlphaComponent(0.35)
            dotsView.addSubview(d)
        }
        let last = index == slides.count - 1
        nextButton.setAttributedTitle(CRTKit.attributed(last ? "GOT IT" : "NEXT", size: 14, color: CRT.ink), for: .normal)
        backButton.isHidden = index == 0
        skipButton.isHidden = last
        setNeedsLayout()
        layoutIfNeeded()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = body.bounds.width
        let pw = panel.bounds.width
        let ph = panel.bounds.height
        // Web showManual sheet (~49% of screen): stage · footer row
        // (SKIP · dots · BACK/NEXT) · Replay tutorial, the footer and replay
        // stacked to the panel's bottom edge (body top is 56 in panel coords).
        let replayH: CGFloat = 27
        // 23pt above the panel's bottom edge on no-inset phones (web parity);
        // on home-indicator phones the replay row lifts clear of the zone.
        let replayY = ph - max(23, safeAreaInsets.bottom + 8) - replayH
        let footerH: CGFloat = 33
        let footerY = replayY - 10 - footerH
        let stageH = footerY - 16 - 56
        stage.frame = CGRect(x: 0, y: 0, width: w, height: stageH)
        artHolder.frame = CGRect(x: 10, y: 14, width: w - 20, height: 152)
        if let art = artHolder.subviews.first {
            art.center = CGPoint(x: artHolder.bounds.midX, y: artHolder.bounds.midY)
        }
        capLabel.frame = CGRect(x: 16, y: 172, width: w - 32, height: stageH - 178)
        skipButton.frame = CGRect(x: 20, y: footerY, width: 60, height: footerH)
        let dotsW = CGFloat(slides.count) * 13 - 6
        dotsView.frame = CGRect(x: (pw - dotsW) / 2, y: footerY + (footerH - 7) / 2, width: dotsW, height: 7)
        nextButton.frame = CGRect(x: pw - 17 - 54, y: footerY, width: 54, height: footerH)
        backButton.frame = CGRect(x: pw - 17 - 54 - 7 - 56, y: footerY, width: 56, height: footerH)
        replayButton.frame = CGRect(x: (pw - 130) / 2, y: replayY, width: 130, height: replayH)
    }

    // MARK: Slide art (mock components, matching the web tour)

    private static func card(_ label: String, _ suit: String, w: CGFloat = 48) -> UIImageView {
        let kind: CardArt.Face.Kind = label == "★" ? .joker : .normal
        let iv = UIImageView(image: CardArt.image(CardArt.Face(label: label, suit: suit, kind: kind), scale: .half))
        iv.layer.magnificationFilter = .nearest
        iv.frame = CGRect(x: 0, y: 0, width: w, height: w * 67 / 48)
        return iv
    }

    private static func tag(_ text: String, good: Bool) -> UILabel {
        let l = CRTKit.label(text, size: 14, color: CRT.ink)
        l.backgroundColor = good ? CRT.phosphor : CRT.suitRed
        l.textColor = good ? CRT.ink : CRT.cardFace
        l.textAlignment = .center
        l.layer.borderWidth = 1
        l.layer.borderColor = CRT.ink.cgColor
        l.frame = CGRect(x: 0, y: 0, width: 84, height: 20)
        return l
    }

    private static func buildSlides(deckId: String) -> [Slide] {
        [
            Slide(art: {
                let v = UIView(frame: CGRect(x: 0, y: 0, width: 176, height: 142))
                let faces: [(String, String)] = [("7", "♠"), ("K", "♥"), ("4", "♣"),
                                                 ("A", "♦"), ("9", "♠"), ("Q", "♥")]
                for (i, f) in faces.enumerated() {
                    let c = card(f.0, f.1, w: 48)
                    c.frame.origin = CGPoint(x: CGFloat(i % 3) * 62, y: CGFloat(i / 3) * 74)
                    v.addSubview(c)
                }
                return v
            }, lead: "This is your board", body: [
                ("A grid of ", false), ("piles", true), (", each showing one ", false),
                ("card", true), (" on top. Keep as many piles alive as you can.", false),
            ]),
            Slide(art: {
                let v = UIView(frame: CGRect(x: 0, y: 0, width: 220, height: 140))
                // The face-down deck stack + count.
                for k in 0..<3 {
                    let off = CGFloat(2 - k) * 3
                    let b = UIImageView(image: CardArt.image(CardArt.Face(label: "", suit: "", kind: .back(deckId: deckId)), scale: .half))
                    b.layer.magnificationFilter = .nearest
                    b.frame = CGRect(x: off, y: 30 + off, width: 50, height: 68)
                    v.addSubview(b)
                }
                let ct = CRTKit.label("52", size: 14, color: CRT.ink)
                ct.backgroundColor = CRT.phosphor
                ct.textAlignment = .center
                ct.layer.borderWidth = 1
                ct.layer.borderColor = CRT.ink.cgColor
                ct.frame = CGRect(x: 40, y: 92, width: 26, height: 17)
                v.addSubview(ct)
                let arrow = CRTKit.label("→", size: 22, color: CRT.cardFace)
                arrow.frame = CGRect(x: 78, y: 55, width: 28, height: 26)
                v.addSubview(arrow)
                let faces: [(String, String)] = [("7", "♠"), ("K", "♥"), ("A", "♦"), ("9", "♠")]
                for (i, f) in faces.enumerated() {
                    let c = card(f.0, f.1, w: 34)
                    c.frame.origin = CGPoint(x: 116 + CGFloat(i % 2) * 44, y: 18 + CGFloat(i / 2) * 54)
                    v.addSubview(c)
                }
                return v
            }, lead: "Work through the deck", body: [
                ("You climb with a ", false), ("deck", true), (" of cards. Each turn the ", false),
                ("next card", true), (" is drawn and placed on a pile you pick. Clear the ", false),
                ("whole deck", true), (" to win the deal.", false),
            ]),
            Slide(art: {
                let v = UIView(frame: CGRect(x: 0, y: 0, width: 160, height: 150))
                let c = card("7", "♥", w: 44)
                c.frame.origin = CGPoint(x: 58, y: 0)
                v.addSubview(c)
                let names = [("HIGHER", CRT.cardFace), ("SAME", CRT.phosphor), ("LOWER", CRT.cardFace)]
                for (i, n) in names.enumerated() {
                    let b = CRTKit.label(n.0, size: 14, color: n.1)
                    b.textAlignment = .center
                    b.backgroundColor = CRT.feltMid
                    b.layer.borderWidth = 2
                    b.layer.borderColor = CRT.ink.cgColor
                    b.frame = CGRect(x: 8 + CGFloat(i) * 50, y: 74, width: 44, height: 24)
                    v.addSubview(b)
                }
                return v
            }, lead: "Make a guess", body: [
                ("Will the next card be ", false), ("Higher", true), (", ", false), ("Same", true),
                (", or ", false), ("Lower", true), (" than that pile's ", false), ("top card", true),
                ("? ", false), ("Swipe a pile", true),
                (" to guess (up = Higher, down = Lower, sideways = Same), or tap it and use the buttons. ", false),
                ("Hold", true), (" a pile for card info. (Aces are high.)", false),
            ]),
            Slide(art: {
                let v = UIView(frame: CGRect(x: 0, y: 0, width: 210, height: 150))
                let good = tag("Correct", good: true)
                good.frame.origin = CGPoint(x: 8, y: 0)
                v.addSubview(good)
                for (i, f) in [("2", "♣"), ("5", "♦"), ("7", "♥")].enumerated() {
                    let c = card(f.0, f.1, w: 44)
                    c.frame.origin = CGPoint(x: 20, y: 28 + CGFloat(2 - i) * 11)
                    v.addSubview(c)
                }
                let grow = CRTKit.label("+1", size: 14, color: CRT.phosphor)
                grow.frame = CGRect(x: 74, y: 34, width: 30, height: 18)
                v.addSubview(grow)
                let bad = tag("Wrong", good: false)
                bad.frame.origin = CGPoint(x: 118, y: 0)
                v.addSubview(bad)
                let dead = card("7", "♥", w: 44)
                dead.alpha = 0.5
                dead.frame.origin = CGPoint(x: 130, y: 28)
                v.addSubview(dead)
                let x = CRTKit.label("✕", size: 30, color: CRT.suitRed)
                x.frame = CGRect(x: 142, y: 42, width: 30, height: 34)
                v.addSubview(x)
                return v
            }, lead: "Grow it or lose it", body: [
                ("Guess ", false), ("right", true),
                (" and the card joins the pile, so it grows taller. Guess ", false), ("wrong", true),
                (" and the whole pile ", false), ("dies", true), (". A tie counts as ", false),
                ("Same", true), (", so a tie ", false), ("kills", true),
                (" a Higher or Lower guess. \u{201C}Close\u{201D} is never good enough.", false),
            ]),
            Slide(art: {
                let v = UIView(frame: CGRect(x: 0, y: 0, width: 250, height: 90))
                let reward = CRTKit.label("◉ \(Int(Economy().dealFlat(stage: 2, rating: 2, isBoss: false)))",
                                          size: 22, color: CRT.gold)
                reward.textAlignment = .center
                reward.frame = CGRect(x: 0, y: 10, width: 110, height: 26)
                v.addSubview(reward)
                let rl = CRTKit.label("stage-2 coin reward", size: 14, color: CRT.muted)
                rl.textAlignment = .center
                rl.frame = CGRect(x: -8, y: 40, width: 126, height: 15)
                v.addSubview(rl)
                let dot = CRTKit.label("·", size: 16, color: CRT.muted)
                dot.frame = CGRect(x: 118, y: 16, width: 10, height: 20)
                v.addSubview(dot)
                let score = CRTKit.label("4 × 3 = 12", size: 22, color: CRT.cardFace)
                score.textAlignment = .center
                score.frame = CGRect(x: 136, y: 10, width: 110, height: 26)
                v.addSubview(score)
                let sl = CRTKit.label("score", size: 14, color: CRT.muted)
                sl.textAlignment = .center
                sl.frame = CGRect(x: 128, y: 40, width: 126, height: 15)
                v.addSubview(sl)
                return v
            }, lead: "Clear the deck, earn coins", body: [
                ("Survive the whole ", false), ("deck", true), (" to win the deal. The coin ", false),
                ("reward", true), (" is a flat amount set by the ", false), ("stage", true),
                (" and the deal's ", false), ("difficulty", true),
                (". Harder deals pay more. ", false),
                ("Surviving piles × the cards in your smallest pile", true), (" is your ", false),
                ("score", true), (", chased for personal bests, not coins.", false),
            ]),
            Slide(art: {
                let v = UIView(frame: CGRect(x: 0, y: 0, width: 170, height: 150))
                let rows: [(String, UIColor)] = [("⌂ Mama's home", CRT.gold), ("Deal", CRT.cardFace),
                                                 ("+ Card", CRT.phosphor), ("Store", CRT.cardFace),
                                                 ("Start", CRT.muted)]
                var y: CGFloat = 0
                for (i, r) in rows.enumerated() {
                    let n = CRTKit.label(r.0, size: 14, color: r.1)
                    n.textAlignment = .center
                    n.backgroundColor = CRT.feltMid
                    n.layer.borderWidth = 1
                    n.layer.borderColor = CRT.ink.cgColor
                    n.frame = CGRect(x: 25, y: y, width: 120, height: 22)
                    v.addSubview(n)
                    y += 22
                    if i < rows.count - 1 {
                        let l = CRTKit.label("┆", size: 14, color: CRT.muted)
                        l.textAlignment = .center
                        l.frame = CGRect(x: 25, y: y - 2, width: 120, height: 12)
                        v.addSubview(l)
                        y += 9
                    }
                }
                return v
            }, lead: "Climb the map home", body: [
                ("A climb takes you up a ", false), ("map", true),
                (" of nodes (deals, stores and card pickups) to ", false), ("Mama's home", true),
                (" at the top. ", false), ("Card & pack nodes grow your deck", true),
                (", so later deals run longer and harder. Lose a single deal and the ", false),
                ("climb ends", true), (".", false),
            ]),
            Slide(art: {
                let v = UIView(frame: CGRect(x: 0, y: 0, width: 280, height: 140))
                let lines: [(String, String)] = [
                    ("Sticker", "attaches to one card, rides the climb"),
                    ("Pillar", "powers a whole column from the top"),
                    ("Base", "a once-per-deal tap power"),
                    ("Card", "a single card to swap in"),
                    ("Pack", "sealed; keep 1–2 of several"),
                    ("Same-Power", "fires on a correct Same"),
                    (GameData.shared.items.store.removal.label, "strips a card from your deck"),
                ]
                for (i, l) in lines.enumerated() {
                    let text = NSMutableAttributedString(
                        string: l.0, attributes: [.font: CRT.Font.of(16), .foregroundColor: CRT.phosphor])
                    text.append(NSAttributedString(
                        string: " · \(l.1)", attributes: [.font: CRT.Font.of(16), .foregroundColor: CRT.cardFace]))
                    let lab = UILabel()
                    lab.attributedText = text
                    lab.frame = CGRect(x: 0, y: CGFloat(i) * 19, width: 280, height: 17)
                    v.addSubview(lab)
                }
                return v
            }, lead: "Spend coins in the store", body: [
                ("Stores on the map sell upgrades in seven classes. Buy with coins, then place them: a sticker on a ", false),
                ("card", true), (", a pillar on a ", false), ("column", true),
                (" top, a base at its foot.", false),
            ]),
            Slide(art: {
                let v = UIView(frame: CGRect(x: 0, y: 0, width: 170, height: 90))
                let c = card("★", "★", w: 56)
                c.frame.origin = CGPoint(x: 8, y: 4)
                v.addSubview(c)
                let t = tag("always safe", good: true)
                t.frame = CGRect(x: 78, y: 34, width: 88, height: 20)
                v.addSubview(t)
                return v
            }, lead: "Good to know", body: [
                ("★ Jokers", true), (" never miss. Any guess on a Joker is safe. ", false),
                ("Difficulty tiers", true), (" (Jokers, then Straight) raise the stakes as you win. And ", false),
                ("Zen", true), (" mode, from the menu, is free practice. No coins, no map, no consequences.", false),
            ]),
        ]
    }
}

// MARK: - Lifetime stats sheet

/// Web `#statsSheet`: the CLIMBS stat-tile grid (big phosphor number over a
/// muted label), the ZEN panel (scope filter · summary · twin histograms),
/// and the full-width RESET STATS danger action.
/// SETTINGS as a bottom sheet (v6.68, batch 2.3) — the separate Settings PAGE
/// is retired; this rides the same SheetView chrome the stats sheet uses, so
/// the menu (and its wordmark) stays visible behind it. Sound toggle + the
/// double-confirmed full reset + the build line.
final class SettingsSheetView: SheetView {
    /// Wired by the flow: runs the double-confirm reset through the shared
    /// prompt bar (the sheet itself never owns destructive flow).
    var onResetProgress: (() -> Void)?

    private let campaign: CampaignState
    private let soundButton = PixelButtonView("", role: .plain, fontSize: 16)
    /// ODDS ASSIST (v6.71): visible even while LOCKED — the locked row is a
    /// goal, not a secret. Unlocks on the first Straight (Legendary) win with
    /// any deck; the state derives from DeckUnlocks, so it persists like
    /// every other unlock and survives save/restore and the deck renames.
    private let assistButton = PixelButtonView("", role: .plain, fontSize: 16)
    private let assistHint = CRTKit.label("", size: 14, color: CRT.muted)
    private let resetButton = PixelButtonView("RESET PROGRESS", role: .danger, fontSize: 16)
    private let foot = CRTKit.label(BuildStamp.line, size: 14, color: CRT.muted)

    init(campaign: CampaignState) {
        self.campaign = campaign
        super.init(title: "Settings")
        setBodyHeight(292)
        soundButton.setTitle("SOUND: \(Sound.shared.enabled ? "ON" : "OFF")")
        soundButton.onTap = { [weak self] in
            Sound.shared.enabled.toggle()
            self?.soundButton.setTitle("SOUND: \(Sound.shared.enabled ? "ON" : "OFF")")
        }
        assistButton.onTap = { [weak self] in
            guard let self, self.campaign.deckUnlocks.wonAnyStraight() else { return }
            let on = self.campaign.saveStore.pref("oddsAssist") == "1"
            self.campaign.saveStore.setPref("oddsAssist", on ? "0" : "1")
            self.refreshAssistRow()
        }
        refreshAssistRow()
        assistHint.textAlignment = .center
        resetButton.onTap = { [weak self] in self?.onResetProgress?() }
        foot.textAlignment = .center
        foot.numberOfLines = 2
        foot.alpha = 0.6
        body.addSubview(soundButton)
        body.addSubview(assistButton)
        body.addSubview(assistHint)
        body.addSubview(resetButton)
        body.addSubview(foot)
    }

    private func refreshAssistRow() {
        if campaign.deckUnlocks.wonAnyStraight() {
            let on = campaign.saveStore.pref("oddsAssist") == "1"
            assistButton.isEnabled = true
            assistButton.setTitle("ODDS ASSIST: \(on ? "ON" : "OFF")")
            assistHint.attributedText = CRTKit.attributed(
                "Glows the pile with the best survival odds.", size: 14, color: CRT.muted)
        } else {
            assistButton.isEnabled = false
            assistButton.setTitle("ODDS ASSIST · LOCKED")
            assistHint.attributedText = CRTKit.attributed(
                "Beat a Straight climb with any deck to unlock.", size: 14, color: CRT.muted)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = body.bounds.width - 28
        guard w > 0 else { return }
        soundButton.frame = CGRect(x: 14, y: 8, width: w, height: 48)
        assistButton.frame = CGRect(x: 14, y: 66, width: w, height: 48)
        assistHint.frame = CGRect(x: 14, y: 118, width: w, height: 16)
        resetButton.frame = CGRect(x: 14, y: 146, width: w, height: 48)
        foot.frame = CGRect(x: 14, y: 206, width: w, height: 34)
    }
}

final class StatsSheetView: SheetView {
    private let campaign: CampaignState
    private let scroll = UIScrollView()
    private var zenScope = "all"
    /// The Zen histogram's ephemeral drill state (web zenView.drill): nil =
    /// the two tappable totals, "wins"/"losses" = the per-bucket breakdown.
    private var zenDrill: String?
    private static let zenPanelTag = 6101
    var onReset: (() -> Void)?
    /// Opens Apple's Game Center sheet (wired by the flow; button hides
    /// when nil — the no-Game-Center path shows nothing).
    var onLeaderboards: (() -> Void)? { didSet { build() } }
    /// The local player's (rank, best) read back from Game Center, when
    /// cheap to have. Set async by the flow; nil shows nothing.
    var gcLocalEntry: (rank: Int, score: Int)? { didSet { build() } }

    init(campaign: CampaignState) {
        self.campaign = campaign
        super.init(title: "Lifetime Stats")
        scroll.showsVerticalScrollIndicator = false
        body.addSubview(scroll)
        // Web #statsSheet fills ~83% of the screen so the full content —
        // through the RESET STATS button — is visible without scrolling.
        setBodyHeight(619)
        build()
    }

    /// `wrapLabel` lets a long caption (the per-deck HIGH SCORE tiles) break
    /// onto a second 14pt line instead of truncating — the type floor is
    /// hard, so the CONTAINER gives room, never the font.
    private func statTile(value: String, pct: String?, label: String, width: CGFloat,
                          wrapLabel: Bool = false) -> UIView {
        let v = PixelPanelView(face: CRT.feltMid, border: CRT.ink, shadowOffsetPx: 0)
        v.frame = CGRect(x: 0, y: 0, width: width, height: 60)
        let num = NSMutableAttributedString(
            string: value, attributes: [.font: CRT.Font.of(16, display: true), .foregroundColor: CRT.phosphor])
        if let pct {
            // 16pt full-cream (was 14pt muted): the win-rate/accuracy figure is
            // a headline stat, not a caption — muted 14 disappeared next to the
            // glowing value. The caption below keeps muted 14 for hierarchy.
            num.append(NSAttributedString(
                string: "  \(pct)", attributes: [.font: CRT.Font.of(16), .foregroundColor: CRT.cardFace]))
        }
        let nl = UILabel()
        nl.attributedText = num
        nl.textAlignment = .center
        nl.layer.shadowColor = CRT.phosphor.cgColor
        nl.layer.shadowRadius = 5
        nl.layer.shadowOpacity = 0.5
        nl.layer.shadowOffset = .zero
        nl.frame = CGRect(x: 4, y: wrapLabel ? 5 : 10, width: width - 8, height: 20)
        v.addSubview(nl)
        let ll = CRTKit.label(label.uppercased(), size: 14, color: CRT.muted)
        ll.textAlignment = .center
        if wrapLabel {
            ll.numberOfLines = 2
            ll.frame = CGRect(x: 2, y: 26, width: width - 4, height: 32)
        } else {
            ll.frame = CGRect(x: 2, y: 34, width: width - 4, height: 15)
        }
        v.addSubview(ll)
        return v
    }

    private func build() {
        scroll.subviews.forEach { $0.removeFromSuperview() }
        let w = body.bounds.width > 0 ? body.bounds.width : 350
        var y: CGFloat = 0

        let climbs = CRTKit.label("CLIMBS", size: 14, color: CRT.gold, display: true)
        climbs.frame = CGRect(x: 2, y: y, width: 200, height: 16)
        scroll.addSubview(climbs)
        y += 24

        let s = campaign.stats.get()
        func pct(_ a: Int, _ b: Int) -> String { b > 0 ? "\(Int((Double(a) / Double(b) * 100).rounded()))%" : "0%" }
        // Per-deck-and-tier high scores LEAD the grid (v6.68) — the same
        // "<deckId>.<tierId>" store the deck-select HIGH SCORE readout reads.
        // Only combos with a recorded score get a tile (a wall of zeros helps
        // nobody), except Pinky's pair, which always shows — it's the pair
        // every player has from climb one. Deck-major, tier-minor, roster
        // order: each deck's Jokers tile leads its Straight tile.
        var tiles: [(String, String?, String, Bool)] = []
        for deckId in GameMeta.deckOrder {
            let deckName = GameFlowController.decks.first { $0.id == deckId }?.name ?? deckId
            for tierId in DifficultyData.tierIds {
                guard let best = s.deckTierBest["\(deckId).\(tierId)"] ?? (deckId == "pink" ? 0 : nil)
                else { continue }
                let tierName = GameData.shared.difficulty.tier(tierId).label
                tiles.append(("\(best)", nil, "High Score (\(tierName) – \(deckName))", true))
            }
        }
        // (v6.68, batch 5.3: the "High score (all decks)" aggregate is GONE —
        // the per-deck-and-tier rows above carry the records now.)
        tiles += [
            ("\(s.gamesPlayed)", nil, "Climbs played", false),
            ("\(s.campaignsWon)", pct(s.campaignsWon, s.gamesPlayed), "Climbs won", false),
            ("\(s.lifetimeCardsDrawn)", nil, "Cards drawn", false),
            ("\(s.lifetimeCorrectGuesses)", pct(s.lifetimeCorrectGuesses, s.lifetimeGuesses), "Correct draws", false),
            ("\(s.lifetimeDopamine)", nil, "Lifetime coins", false),
            // bestCoinsInClimb, NOT bestCampaignDopamine: the latter only ever
            // recorded on a WON climb, so dying with a fat purse counted for
            // nothing and the tile looked broken.
            ("\(s.bestCoinsInClimb)", nil, "Most coins in a climb", false),
        ]
        let tw = (w - 10) / 2
        for (i, t) in tiles.enumerated() {
            let tile = statTile(value: t.0, pct: t.1, label: t.2, width: tw, wrapLabel: t.3)
            tile.frame.origin = CGPoint(x: CGFloat(i % 2) * (tw + 10), y: y + CGFloat(i / 2) * 68)
            scroll.addSubview(tile)
        }
        y += CGFloat((tiles.count + 1) / 2) * 68 + 6

        // ---- ZEN panel ----
        let zen = PixelPanelView(face: CRT.feltMid, border: CRT.ink, shadowOffsetPx: 0)
        zen.tag = StatsSheetView.zenPanelTag
        let zenHead = CRTKit.label("ZEN", size: 14, color: CRT.gold, display: true)
        zenHead.frame = CGRect(x: 10, y: 10, width: 100, height: 16)
        zen.addSubview(zenHead)

        // Scope chips: All + each difficulty.
        var scopes: [(String, String)] = [("all", "All")]
        for id in DifficultyData.zenIds {
            scopes.append((id, GameData.shared.difficulty.zen(id).label))
        }
        let chipW = (w - 20 - CGFloat(scopes.count - 1) * 8) / CGFloat(scopes.count)
        for (i, sc) in scopes.enumerated() {
            let active = sc.0 == zenScope
            let chip = UIButton(type: .custom)
            chip.setAttributedTitle(CRTKit.attributed(sc.1, size: 14, color: active ? CRT.ink : CRT.cardFace), for: .normal)
            chip.backgroundColor = active ? CRT.phosphor : CRT.feltDeep
            chip.layer.borderWidth = CRT.px
            chip.layer.borderColor = CRT.ink.cgColor
            chip.frame = CGRect(x: 10 + CGFloat(i) * (chipW + 8), y: 32, width: chipW, height: 28)
            chip.addAction(UIAction { [weak self] _ in
                self?.zenScope = sc.0
                self?.build()
            }, for: .touchUpInside)
            zen.addSubview(chip)
        }

        // Aggregate the scoped entries.
        let ids = zenScope == "all" ? DifficultyData.zenIds : [zenScope]
        var games = 0, wins = 0, cards = 0, correct = 0
        var winPiles: [Int: Int] = [:], lossCards: [Int: Int] = [:]
        for id in ids {
            let e = campaign.zenStats.get(id)
            games += e.games; wins += e.wins
            cards += e.cardsFlipped; correct += e.correctGuesses
            for (k, v) in e.winPiles { winPiles[k, default: 0] += v }
            for (k, v) in e.lossCards { lossCards[k, default: 0] += v }
        }
        let sum = NSMutableAttributedString()
        // Numbers at 16 (were 14): the phosphor figures are the payload of this
        // line; the muted captions stay a step down at the 14 floor.
        func seg(_ n: Int, _ label: String, last: Bool = false) {
            sum.append(NSAttributedString(string: "\(n)", attributes: [.font: CRT.Font.of(16), .foregroundColor: CRT.phosphor]))
            sum.append(NSAttributedString(string: " \(label)\(last ? "" : " · ")",
                                          attributes: [.font: CRT.Font.of(14), .foregroundColor: CRT.muted]))
        }
        seg(games, "played"); seg(wins, "won"); seg(cards, "cards"); seg(correct, "correct", last: true)
        let sumLabel = UILabel()
        sumLabel.attributedText = sum
        sumLabel.frame = CGRect(x: 10, y: 66, width: w - 20, height: 20)
        zen.addSubview(sumLabel)

        // Zen drill (web zenSectionInner/zenSetDrill): tapping ANYWHERE on the
        // Wins or Losses column expands that outcome's per-bucket distribution
        // with bucket labels, an axis caption and a Back chip — the other
        // outcome collapses to a single lead bar. The swap is ANIMATED (the
        // panel grows and the new region slides in, v5.81). Wins break down
        // by piles remaining, Losses by cards left in the deck (bucketed like
        // zenLossBuckets). Bars ride a felt-deep track, so empty buckets
        // still read as structure.
        let tW = winPiles.values.reduce(0, +), tL = lossCards.values.reduce(0, +)
        // Axis extents for the scope (web zenScope): a single difficulty reads
        // its own config; "All" spans the widest ladder rung.
        var pilesMax = 0, deckMax = 0
        for id in ids {
            let z = GameData.shared.difficulty.zen(id)
            pilesMax = max(pilesMax, z.piles)
            deckMax = max(deckMax, z.suitCount * 13)
        }
        let histTop: CGFloat = 92
        let regionH: CGFloat
        if let drill = zenDrill {
            regionH = drawZenDrill(in: zen, x0: 10, y0: histTop, width: w - 20, drill: drill,
                                   wins: tW, losses: tL, winPiles: winPiles, lossCards: lossCards,
                                   pilesMax: pilesMax, deckMax: deckMax)
        } else {
            regionH = drawZenTotals(in: zen, x0: 10, y0: histTop, width: w - 20,
                                    wins: tW, losses: tL)
        }
        let zenH = histTop + regionH + 10
        zen.frame = CGRect(x: 0, y: y, width: w, height: zenH)
        scroll.addSubview(zen)
        y += zenH + 14

        // GAME CENTER — the CRT-styled doorway to Apple's stock sheet.
        if onLeaderboards != nil {
            let lb = PixelButtonView("🏆 LEADERBOARDS", role: .gold, fontSize: 14)
            lb.onTap = { [weak self] in self?.onLeaderboards?() }
            lb.frame = CGRect(x: 0, y: y, width: w, height: 38)
            scroll.addSubview(lb)
            y += 44
            if let e = gcLocalEntry {
                let line = CRTKit.label("Pinky · Straight: rank #\(e.rank) · best \(e.score)",
                                        size: 14, color: CRT.muted)
                line.textAlignment = .center
                line.frame = CGRect(x: 0, y: y, width: w, height: 16)
                scroll.addSubview(line)
                y += 22
            } else {
                y += 6
            }
        }

        let reset = PixelButtonView("RESET STATS", role: .danger, fontSize: 14)
        reset.onTap = { [weak self] in self?.onReset?() }
        reset.frame = CGRect(x: 0, y: y, width: w, height: 38)
        scroll.addSubview(reset)
        y += 50

        scroll.contentSize = CGSize(width: w, height: y)
    }

    /// Drill in/out with a smooth transition (v5.81): the old region
    /// cross-fades into the rebuilt one, and everything BELOW the zen panel
    /// (the reset button) slides with the panel's height change instead of
    /// jumping. build() is layout-pure, so the animation rides on a snapshot.
    private func setZenDrillAnimated(_ drill: String?) {
        guard let oldZen = scroll.viewWithTag(StatsSheetView.zenPanelTag) else {
            zenDrill = drill
            build()
            return
        }
        let oldH = oldZen.frame.height
        let snap = oldZen.snapshotView(afterScreenUpdates: false)
        snap?.frame = oldZen.frame
        zenDrill = drill
        build()
        guard let newZen = scroll.viewWithTag(StatsSheetView.zenPanelTag) else { return }
        // Rebuild laid out the final state; rewind below-panel siblings to
        // their pre-drill offsets, then animate them to the new ones.
        let dy = newZen.frame.height - oldH
        var sliders: [(UIView, CGRect)] = []
        for v in scroll.subviews where v != newZen && v.frame.minY >= newZen.frame.maxY - 1 {
            let final = v.frame
            v.frame = final.offsetBy(dx: 0, dy: -dy)
            sliders.append((v, final))
        }
        newZen.clipsToBounds = true
        let finalZen = newZen.frame
        newZen.frame = CGRect(x: finalZen.minX, y: finalZen.minY,
                              width: finalZen.width, height: oldH)
        newZen.alpha = 0
        if let snap { scroll.addSubview(snap) }
        UIView.animate(withDuration: 0.32, delay: 0,
                       options: [.curveEaseInOut, .allowUserInteraction]) {
            newZen.frame = finalZen
            newZen.alpha = 1
            snap?.alpha = 0
            for (v, final) in sliders { v.frame = final }
        } completion: { _ in
            snap?.removeFromSuperview()
        }
    }

    /// Loss-histogram buckets (web zenLossBuckets): singletons 1..5, then
    /// decades 6-10, 11-20, … — the bucket containing deckSize ends there, and
    /// a trailing sliver smaller than a singleton run (< 5 cards) folds into
    /// the previous decade instead of standing alone.
    static func zenLossBuckets(_ deckSize: Int) -> [(lo: Int, hi: Int)] {
        var out: [(lo: Int, hi: Int)] = []
        var n = 1
        while n <= 5 && n <= deckSize { out.append((n, n)); n += 1 }
        var lo = 6
        while lo <= deckSize {
            let decadeEnd = Int(ceil(Double(lo) / 10.0)) * 10   // 6→10, 11→20, 41→50
            if decadeEnd >= deckSize || deckSize - decadeEnd < 5 {
                out.append((lo, deckSize))
                break
            }
            out.append((lo, decadeEnd))
            lo = decadeEnd + 1
        }
        return out
    }

    /// Fold a lossCards distribution into per-bucket totals (web
    /// zenBucketCounts): every loss lands in exactly ONE bucket, its
    /// cards-left clamped into [1, deckSize].
    static func zenBucketCounts(_ lossCards: [Int: Int], buckets: [(lo: Int, hi: Int)],
                                deckSize: Int) -> [Int] {
        var totals = [Int](repeating: 0, count: buckets.count)
        for (k, v) in lossCards {
            let val = max(1, min(deckSize, k))
            for (i, b) in buckets.enumerated() where val >= b.lo && val <= b.hi {
                totals[i] += v
                break
            }
        }
        return totals
    }

    /// The collapsed view: the two tappable totals (web zc-agg columns), one
    /// bar per outcome scaled to their shared max over a baseline rule.
    private func drawZenTotals(in zen: UIView, x0: CGFloat, y0: CGFloat, width: CGFloat,
                               wins: Int, losses: Int) -> CGFloat {
        let maxV = max(1, max(wins, losses))
        let barsH: CGFloat = 64
        // The tap target is the WHOLE half-row, not just the column content —
        // a tap anywhere on the wins/losses side drills in (v5.81).
        let colW = width / 2
        let specs: [(label: String, count: Int, color: UIColor, drill: String)] = [
            ("WINS", wins, CRT.phosphor, "wins"),
            ("LOSSES", losses, CRT.suitRed, "losses"),
        ]
        for (i, spec) in specs.enumerated() {
            let col = UIControl()
            col.frame = CGRect(x: x0 + CGFloat(i) * colW, y: y0,
                               width: colW, height: 18 + 2 + barsH + 8 + 15)
            let drill = spec.drill
            col.addAction(UIAction { [weak self] _ in
                self?.setZenDrillAnimated(drill)
            }, for: .touchUpInside)
            // The WHOLE column is the drill target. Plain UIViews default to
            // interactive and would swallow the touch inside a scroll view
            // (which cancels content touches for non-UIControls), leaving only
            // the two UILabels — the count on top and the caption underneath —
            // actually tappable. That was the "only the bottom registers" bug.
            func decorative(_ v: UIView) -> UIView { v.isUserInteractionEnabled = false; return v }
            let innerW = colW - 24
            // Counts read CREAM at 16 (v6.36 precedent, DeckPanel/TopShell):
            // suitRed digits on felt were "the hardest text on the board", so
            // digits go cardFace and the bar + rule underneath keep carrying
            // the outcome's color.
            let cnt = CRTKit.label("\(spec.count)", size: 16, color: CRT.cardFace)
            cnt.textAlignment = .center
            cnt.frame = CGRect(x: 0, y: 0, width: colW, height: 18)
            col.addSubview(cnt)
            let track = UIView(frame: CGRect(x: (colW - 44) / 2, y: 20, width: 44, height: barsH))
            track.backgroundColor = CRT.feltDeep
            col.addSubview(decorative(track))
            if spec.count > 0 {
                let h = max(3, barsH * CGFloat(spec.count) / CGFloat(maxV))
                let bar = UIView(frame: CGRect(x: (colW - 44) / 2, y: 20 + barsH - h,
                                               width: 44, height: h))
                bar.backgroundColor = spec.color
                col.addSubview(decorative(bar))
            }
            let rule = UIView(frame: CGRect(x: (colW - innerW) / 2, y: 20 + barsH + 2, width: innerW, height: 2))
            rule.backgroundColor = spec.color
            col.addSubview(decorative(rule))
            let lab = CRTKit.label(spec.label, size: 14, color: CRT.muted)
            lab.textAlignment = .center
            lab.frame = CGRect(x: 0, y: 20 + barsH + 8, width: colW, height: 15)
            col.addSubview(lab)
            zen.addSubview(col)
        }
        return 20 + barsH + 8 + 15
    }

    /// The drilled view: a Back chip, the OTHER outcome's total leading at
    /// full height (a win = 0 cards left, a loss = 0 piles left — each total
    /// is the "0" slot of the other axis), then the breakdown columns scaled
    /// to their own max, bucket labels under every bar, and the axis caption.
    private func drawZenDrill(in zen: UIView, x0: CGFloat, y0: CGFloat, width: CGFloat,
                              drill: String, wins: Int, losses: Int,
                              winPiles: [Int: Int], lossCards: [Int: Int],
                              pilesMax: Int, deckMax: Int) -> CGFloat {
        let back = UIButton(type: .custom)
        back.setAttributedTitle(CRTKit.attributed("‹ BACK", size: 14, color: CRT.cardFace),
                                for: .normal)
        back.backgroundColor = CRT.feltDeep
        back.layer.borderWidth = CRT.px
        back.layer.borderColor = CRT.ink.cgColor
        back.frame = CGRect(x: x0, y: y0, width: 64, height: 24)
        back.addAction(UIAction { [weak self] _ in
            self?.setZenDrillAnimated(nil)
        }, for: .touchUpInside)
        zen.addSubview(back)

        struct Col { let label: String; let count: Int; let color: UIColor; let lead: Bool }
        var cols: [Col] = []
        let distColor: UIColor = drill == "wins" ? CRT.phosphor : CRT.suitRed
        if drill == "wins" {
            cols.append(Col(label: "LOSSES", count: losses, color: CRT.suitRed, lead: true))
            for p in 1...max(1, pilesMax) {
                cols.append(Col(label: "\(p)", count: winPiles[p] ?? 0, color: distColor, lead: false))
            }
        } else {
            cols.append(Col(label: "WINS", count: wins, color: CRT.phosphor, lead: true))
            let buckets = StatsSheetView.zenLossBuckets(deckMax)
            let totals = StatsSheetView.zenBucketCounts(lossCards, buckets: buckets, deckSize: deckMax)
            for (i, b) in buckets.enumerated() {
                cols.append(Col(label: b.lo == b.hi ? "\(b.lo)" : "\(b.lo)-\(b.hi)",
                                count: totals[i], color: distColor, lead: false))
            }
        }
        let distMax = max(1, cols.filter { !$0.lead }.map(\.count).max() ?? 1)
        let top = y0 + 24 + 8
        let barsH: CGFloat = 60
        let colW = min(30, width / CGFloat(max(1, cols.count)))
        let start = x0 + (width - colW * CGFloat(cols.count)) / 2
        for (i, c) in cols.enumerated() {
            let cx = start + CGFloat(i) * colW
            // Bar counts read CREAM at 16 (v6.36 precedent, DeckPanel/TopShell):
            // 14pt suitRed digits over felt were unreadable — digits go
            // cardFace, the bar below keeps the outcome's color.
            let cnt = CRTKit.label("\(c.count)", size: 16, color: CRT.cardFace)
            cnt.textAlignment = .center
            cnt.frame = CGRect(x: cx - 7, y: top, width: colW + 14, height: 16)
            zen.addSubview(cnt)
            let bw = colW - 8
            let track = UIView(frame: CGRect(x: cx + 4, y: top + 18, width: bw, height: barsH))
            track.backgroundColor = CRT.feltDeep
            zen.addSubview(track)
            let h: CGFloat = c.lead ? barsH
                : (c.count > 0 ? max(3, barsH * CGFloat(c.count) / CGFloat(distMax)) : 0)
            if h > 0 {
                let bar = UIView(frame: CGRect(x: cx + 4, y: top + 18 + barsH - h,
                                               width: bw, height: h))
                bar.backgroundColor = c.color
                zen.addSubview(bar)
            }
            let lab = CRTKit.label(c.label, size: 14, color: CRT.muted)
            lab.textAlignment = .center
            lab.frame = CGRect(x: cx - 9, y: top + 18 + barsH + 4, width: colW + 18, height: 14)
            zen.addSubview(lab)
        }
        // The axis caption names what the drilled bars MEASURE (web .zh-axis).
        let axis = CRTKit.label(drill == "wins" ? "piles remaining at the win"
                                                : "cards remaining at the loss",
                                size: 14, color: CRT.muted)
        axis.textAlignment = .center
        axis.frame = CGRect(x: x0, y: top + 18 + barsH + 22, width: width, height: 15)
        zen.addSubview(axis)
        return 24 + 8 + 18 + barsH + 22 + 15 + 4
    }

    /// Re-render after an outside change (e.g. the reset confirm).
    func refresh() { build() }

    override func layoutSubviews() {
        super.layoutSubviews()
        scroll.frame = body.bounds
        if abs(scroll.contentSize.width - body.bounds.width) > 1 { build() }
    }
}
