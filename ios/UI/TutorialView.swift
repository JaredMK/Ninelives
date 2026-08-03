import UIKit
import GameCore

/// The first-run tutorial — the Zen-first tour. Bubbles step through the core
/// mechanics over the FIRST Zen deal; copy comes from tutorial.js verbatim
/// (writer markup: *bold* renders gold). Dismissing the last bubble stamps the
/// pref; "Skip tips" ends everything (stamped, same as completing). Guessing
/// is never gated — the tour floats above, and the first resolved guess steps
/// the bubble aside UNSTAMPED (`stepAside()`), so the tour offers itself
/// again next deal (the web's Tutorial.onGuessResolved).
///
/// Placement mirrors the web's Tutorial.place(): each bubble anchors to its
/// target region (tutorial.js `anchor` keys → the deal layout's rects, the
/// web's ANCHORS map), the phosphor ring hugs the anchor, and the bubble sits
/// BELOW the anchor when it fits (arrow up), ABOVE it otherwise (arrow down);
/// an anchor-less step centres at 40% height with no arrow.
public final class TutorialView: UIView {

    private let steps: [TutorialStep]
    private var index = 0
    private let panel = PixelPanelView(face: CRT.feltMid, border: CRT.phosphor)
    private let textLabel = UILabel()
    private let nextButton = PixelButtonView("NEXT", role: .cta, fontSize: 15)
    /// The web's `.tut-skip`: an underlined TEXT LINK, not a boxed button.
    private let skipLink = UIButton(type: .custom)
    private let onDone: (_ completed: Bool) -> Void
    /// The web's `.tut-ring`: phosphor border around the anchor region.
    private let ring = UIView()
    /// The web's `.tut-bubble::before`: a rotated felt-mid square on the
    /// panel edge pointing at the anchor (half hidden behind the panel).
    private let arrow = UIView()
    private var arrowOnTop = true
    private var arrowX: CGFloat = 0
    private var finished = false

    public init(steps: [TutorialStep], onDone: @escaping (_ completed: Bool) -> Void) {
        self.steps = steps
        self.onDone = onDone
        super.init(frame: .zero)
        // The board stays playable — only the bubble itself eats touches.
        ring.isUserInteractionEnabled = false
        ring.layer.borderWidth = 2.5
        ring.layer.borderColor = CRT.phosphor.cgColor
        ring.layer.shadowColor = CRT.phosphor.cgColor
        ring.layer.shadowRadius = CRT.glowRadius
        ring.layer.shadowOpacity = 0.8
        ring.layer.shadowOffset = .zero
        addSubview(ring)
        // The ring's pulse is opacity-only over the static glow (the web's
        // THERMAL-safe tutPulse) and dies with this view.
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 0.55
        pulse.toValue = 1.0
        pulse.duration = 0.75
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        ring.layer.add(pulse, forKey: "tutPulse")

        arrow.isUserInteractionEnabled = false
        arrow.backgroundColor = CRT.feltMid
        arrow.layer.borderWidth = CRT.px
        arrow.layer.borderColor = CRT.phosphor.cgColor
        arrow.transform = CGAffineTransform(rotationAngle: .pi / 4)
        addSubview(arrow)

        addSubview(panel)
        textLabel.numberOfLines = 0
        panel.addSubview(textLabel)
        nextButton.onTap = { [weak self] in self?.advance() }
        panel.addSubview(nextButton)
        skipLink.setAttributedTitle(NSAttributedString(
            string: "Skip tips",
            attributes: [.font: CRT.Font.of(12), .foregroundColor: CRT.muted,
                         .underlineStyle: NSUnderlineStyle.single.rawValue]), for: .normal)
        skipLink.accessibilityLabel = "SKIP TIPS"
        skipLink.addTarget(self, action: #selector(skipTapped), for: .touchUpInside)
        panel.addSubview(skipLink)
        show()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    /// Only the bubble is interactive; everything else passes through to the deal.
    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let v = super.hitTest(point, with: event)
        return v === self ? nil : v
    }

    /// tutorial.js writer markup: *bold* segments render gold.
    static func attributed(_ text: String) -> NSAttributedString {
        let out = NSMutableAttributedString()
        var bold = false
        for part in text.components(separatedBy: "*") {
            out.append(CRTKit.attributed(part, size: 15, color: bold ? CRT.gold : CRT.cardFace))
            bold.toggle()
        }
        return out
    }

    /// The web's ANCHORS map, resolved against the native deal layout
    /// (DealScene.layoutChrome in Zen mode: HUD 40 → deck band 78 → board,
    /// left rail ~64 wide, reshuffle bar + footer zone at the bottom).
    private func anchorRect(_ key: String) -> CGRect? {
        let w = bounds.width, h = bounds.height
        guard w > 0, h > 0 else { return nil }
        let safe = safeAreaInsets
        let top = safe.top + 8
        let hudH: CGFloat = 40, bandH: CGFloat = 78
        let bandY = top + hudH + 6
        switch key {
        case "dealBoard":
            let railW: CGFloat = 64 + 10   // FAN + ▲＝▼ rail, plus its gap
            let y0 = bandY + bandH + 6
            // Above the reshuffle bar + footer zone (34) and their margins.
            let bottom = h - safe.bottom - 4 - 34 - 46 - 12
            return CGRect(x: railW, y: y0, width: w - railW - 8,
                          height: max(80, bottom - y0))
        case "dealPile":
            // A living pile: the board's top-centre card.
            guard let b = anchorRect("dealBoard") else { return nil }
            return CGRect(x: b.midX - 36, y: b.minY + 8, width: 72, height: 100)
        case "dealDeckChar":
            // The deck character stands at the band's right end.
            return CGRect(x: w - 8 - 84, y: bandY, width: 84, height: bandH)
        case "sameShield":
            // The Same-shield chip rides the HUD's centre.
            return CGRect(x: w / 2 - 20, y: top + 8, width: 40, height: 24)
        case "dealHistogram":
            // The rank histogram: band middle, between the suit counts and
            // the character.
            return CGRect(x: 8 + 64, y: bandY, width: w - 16 - 64 - 84, height: bandH)
        default:
            return nil
        }
    }

    private func show() {
        guard index < steps.count else { finish(completed: true); return }
        let step = steps[index]
        textLabel.attributedText = TutorialView.attributed(step.text)
        nextButton.setTitle((step.button ?? (index == steps.count - 1 ? "GO" : "NEXT")).uppercased())
        panel.alpha = 0
        panel.transform = CGAffineTransform(translationX: 0, y: 12)
        UIView.animate(withDuration: 0.22) {
            self.panel.alpha = 1
            self.panel.transform = .identity
        }
        setNeedsLayout()
        layoutIfNeeded()
    }

    @objc private func skipTapped() { finish(completed: false) }

    private func advance() {
        index += 1
        if index >= steps.count { finish(completed: true) } else { show() }
    }

    private func finish(completed: Bool) {
        guard !finished else { return }
        finished = true
        UIView.animate(withDuration: 0.18, animations: { self.alpha = 0 }) { _ in
            self.removeFromSuperview()
            self.onDone(completed)
        }
    }

    /// The web's Tutorial.onGuessResolved: a resolved guess mid-tour means
    /// the player is playing — the bubble steps aside UNSTAMPED (onDone never
    /// fires, so the pref stays unset and the tour offers itself again on the
    /// next deal). Wire from the first resolved guess of the guided deal.
    public func stepAside() {
        guard !finished else { return }
        finished = true
        UIView.animate(withDuration: 0.18, animations: { self.alpha = 0 }) { _ in
            self.removeFromSuperview()
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        let w = min(300, bounds.width - 28)   // the web's .tut-bubble max-width
        let textH = ceil(textLabel.attributedText?.boundingRect(
            with: CGSize(width: w - 24, height: 400),
            options: .usesLineFragmentOrigin, context: nil).height ?? 20)
        let h = textH + 20 + 44 + 12

        // The web's place(): prefer BELOW the anchor (arrow up); above when
        // it doesn't fit (arrow down); anchor-less steps centre at 40% with
        // no ring and no arrow.
        let anchor = index < steps.count ? steps[index].anchor.flatMap(anchorRect) : nil
        if let a = anchor {
            ring.isHidden = false
            ring.frame = a.insetBy(dx: -7, dy: -7)
            let x = min(max(a.midX - w / 2, 10), bounds.width - w - 10)
            let py: CGFloat
            if a.maxY + 16 + h < bounds.height - 10 {
                py = a.maxY + 16
                arrowOnTop = true
            } else {
                py = max(10, a.minY - h - 16)
                arrowOnTop = false
            }
            arrowX = min(max(a.midX, x + 18), x + w - 18)
            panel.frame = CGRect(x: x, y: py, width: w, height: h)
            arrow.isHidden = false
            let edge = arrowOnTop ? panel.frame.minY : panel.frame.maxY
            arrow.center = CGPoint(x: arrowX, y: edge)
            arrow.bounds = CGRect(x: 0, y: 0, width: 12, height: 12)
        } else {
            ring.isHidden = true
            arrow.isHidden = true
            panel.frame = CGRect(x: (bounds.width - w) / 2, y: bounds.height * 0.40,
                                 width: w, height: h)
        }
        textLabel.frame = CGRect(x: 12, y: 10, width: w - 24, height: textH)
        nextButton.frame = CGRect(x: w - 120, y: h - 50, width: 108, height: 40)
        skipLink.frame = CGRect(x: 12, y: h - 46, width: 100, height: 34)
    }
}
