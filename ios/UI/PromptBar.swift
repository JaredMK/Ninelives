import UIKit
import GameCore

/// The shared bottom prompt bar — EVERY confirmation in the game rides this
/// (AGENTS Convention 3): buy, sell, remove, reroll, destructive choices.
/// Question on top, an optional help line, buttons in a row. Never a system
/// alert, never a one-off dialog.
public final class PromptBar: UIView {

    private let panel = PixelPanelView(face: CRT.feltMid, border: CRT.ink)
    private let textLabel = UILabel()
    private let helpLabel = UILabel()
    private var buttons: [PixelButtonView] = []
    private var onDismiss: (() -> Void)?
    /// A full-screen dim behind the bar; tapping it dismisses (cancel).
    private let scrim = UIControl()

    public struct Action {
        public var label: String
        public var role: PixelButtonView.Role
        public var handler: () -> Void
        public init(_ label: String, role: PixelButtonView.Role = .plain, handler: @escaping () -> Void) {
            self.label = label; self.role = role; self.handler = handler
        }
    }

    public init() {
        super.init(frame: .zero)
        isHidden = true
        scrim.backgroundColor = CRT.ink.withAlphaComponent(0.35)
        scrim.addTarget(self, action: #selector(scrimTapped), for: .touchUpInside)
        addSubview(scrim)
        addSubview(panel)
        textLabel.numberOfLines = 0
        textLabel.textAlignment = .center
        panel.addSubview(textLabel)
        helpLabel.numberOfLines = 0
        helpLabel.textAlignment = .center
        panel.addSubview(helpLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    /// Show the bar. `dismiss` fires on an outside tap (cancel semantics).
    public func show(_ text: String, help: String? = nil, actions: [Action],
                     dismiss: (() -> Void)? = nil) {
        textLabel.attributedText = CRTKit.attributed(text, size: 17, color: CRT.cardFace)
        helpLabel.attributedText = help.map { CRTKit.attributed($0, size: 13, color: CRT.muted) }
        helpLabel.isHidden = help == nil
        buttons.forEach { $0.removeFromSuperview() }
        buttons = actions.map { a in
            let b = PixelButtonView(a.label, role: a.role, fontSize: 16)
            b.onTap = { a.handler() }
            panel.addSubview(b)
            return b
        }
        onDismiss = dismiss
        isHidden = false
        superview?.bringSubviewToFront(self)
        setNeedsLayout()
        layoutIfNeeded()
        // Slide up from the bottom edge.
        panel.transform = CGAffineTransform(translationX: 0, y: 40)
        scrim.alpha = 0
        UIView.animate(withDuration: 0.18) {
            self.panel.transform = .identity
            self.scrim.alpha = 1
        }
    }

    public func hide() {
        isHidden = true
        onDismiss = nil
    }

    public var isShowing: Bool { !isHidden }

    @objc private func scrimTapped() {
        let d = onDismiss
        hide()
        d?()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        scrim.frame = bounds
        let w = bounds.width - 16
        let textH = textLabel.attributedText?.boundingRect(
            with: CGSize(width: w - 24, height: 300), options: .usesLineFragmentOrigin, context: nil
        ).height ?? 20
        let helpH: CGFloat = helpLabel.isHidden ? 0 : (helpLabel.attributedText?.boundingRect(
            with: CGSize(width: w - 24, height: 200), options: .usesLineFragmentOrigin, context: nil
        ).height ?? 0) + 6
        let btnH: CGFloat = buttons.isEmpty ? 0 : 44
        let safeB = superview?.safeAreaInsets.bottom ?? 0
        let panelH = 12 + ceil(textH) + helpH + (btnH > 0 ? btnH + 12 : 0) + 12
        panel.frame = CGRect(x: 8, y: bounds.height - safeB - panelH - 8, width: w, height: panelH)
        textLabel.frame = CGRect(x: 12, y: 10, width: w - 24, height: ceil(textH))
        helpLabel.frame = CGRect(x: 12, y: textLabel.frame.maxY + 4, width: w - 24, height: max(0, helpH - 6))
        let bw = min(150, (w - 24 - CGFloat(max(0, buttons.count - 1)) * 10) / CGFloat(max(1, buttons.count)))
        let total = bw * CGFloat(buttons.count) + CGFloat(max(0, buttons.count - 1)) * 10
        var x = (w - total) / 2
        for b in buttons {
            b.frame = CGRect(x: x, y: panelH - btnH - 10, width: bw, height: btnH)
            x += bw + 10
        }
    }

    /// Route touches: only the scrim + panel are interactive; the rest passes
    /// through so the screen behind stays inert while dimmed.
    public override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        !isHidden
    }
}
