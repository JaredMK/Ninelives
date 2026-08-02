import UIKit
import GameCore

/// The first-run tutorial — the Zen-first tour. Bubbles step through the core
/// mechanics over the FIRST Zen deal; copy comes from tutorial.js verbatim
/// (writer markup: *bold* renders gold). Dismissing the last bubble stamps the
/// pref; "Skip tips" ends everything (stamped, same as completing). Guessing
/// is never gated — the tour floats above and steps aside on the last bubble.
public final class TutorialView: UIView {

    private let steps: [TutorialStep]
    private var index = 0
    private let panel = PixelPanelView(face: CRT.feltMid, border: CRT.phosphor)
    private let textLabel = UILabel()
    private let nextButton = PixelButtonView("NEXT", role: .cta, fontSize: 15)
    /// The web's `.tut-skip`: an underlined TEXT LINK, not a boxed button.
    private let skipLink = UIButton(type: .custom)
    private let onDone: (_ completed: Bool) -> Void

    public init(steps: [TutorialStep], onDone: @escaping (_ completed: Bool) -> Void) {
        self.steps = steps
        self.onDone = onDone
        super.init(frame: .zero)
        // The board stays playable — only the bubble itself eats touches.
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
    }

    @objc private func skipTapped() { finish(completed: false) }

    private func advance() {
        index += 1
        if index >= steps.count { finish(completed: true) } else { show() }
    }

    private func finish(completed: Bool) {
        UIView.animate(withDuration: 0.18, animations: { self.alpha = 0 }) { _ in
            self.removeFromSuperview()
            self.onDone(completed)
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        let w = min(300, bounds.width - 28)   // the web's .tut-bubble max-width
        let textH = ceil(textLabel.attributedText?.boundingRect(
            with: CGSize(width: w - 24, height: 400),
            options: .usesLineFragmentOrigin, context: nil).height ?? 20)
        let h = textH + 20 + 44 + 12
        // The bubble anchors at the TOP, just below the tracker band (the web's
        // tutorial-01 placement) — NOT above the bottom control row.
        panel.frame = CGRect(x: (bounds.width - w) / 2,
                             y: safeAreaInsets.top + 8 + 40 + 6 + 78 + 8,
                             width: w, height: h)
        textLabel.frame = CGRect(x: 12, y: 10, width: w - 24, height: textH)
        nextButton.frame = CGRect(x: w - 120, y: h - 50, width: 108, height: 40)
        skipLink.frame = CGRect(x: 12, y: h - 46, width: 100, height: 34)
    }
}
