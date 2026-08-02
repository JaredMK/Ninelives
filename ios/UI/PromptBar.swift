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
    private var buttonWidths: [CGFloat] = []
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
        // Web .ap-text: LEFT-aligned title (.ap-q, phosphor) over the muted
        // multi-line body (.ap-desc); buttons ride the right side.
        textLabel.numberOfLines = 0
        textLabel.textAlignment = .left
        panel.addSubview(textLabel)
        helpLabel.numberOfLines = 0
        helpLabel.textAlignment = .left
        panel.addSubview(helpLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    /// Show the bar. `dismiss` fires on an outside tap (cancel semantics).
    public func show(_ text: String, help: String? = nil, actions: [Action],
                     dismiss: (() -> Void)? = nil) {
        textLabel.attributedText = CRTKit.attributed(text, size: 13, color: CRT.phosphor)
        helpLabel.attributedText = help.map { helpAttributed($0) }
        helpLabel.isHidden = help == nil
        buttons.forEach { $0.removeFromSuperview() }
        buttonWidths = actions.map {
            ceil(CRTKit.attributed($0.label.uppercased(), size: 13, color: CRT.cardFace)
                .size().width) + 30   // web .ap-btn padding 15px per side
        }
        buttons = actions.map { a in
            let b = PixelButtonView(a.label, role: a.role, fontSize: 13)
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

    /// Web .ap-desc: 12.5px lh 1.4, muted, pre-line.
    private func helpAttributed(_ help: String) -> NSAttributedString {
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 5
        let s = NSMutableAttributedString(
            string: help, attributes: [.font: CRT.Font.of(12), .foregroundColor: CRT.muted])
        s.addAttribute(.paragraphStyle, value: para, range: NSRange(location: 0, length: s.length))
        return s
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
        // Web .action-prompt: one flex row — the left-aligned text block takes
        // the slack, the hug-content buttons sit right, vertically centred.
        let btnH: CGFloat = buttons.isEmpty ? 0 : 38
        let btnsW = buttonWidths.reduce(0, +) + CGFloat(max(0, buttons.count - 1)) * 8
        let textW = w - 24 - (btnsW > 0 ? btnsW + 10 : 0)
        let textH = textLabel.attributedText?.boundingRect(
            with: CGSize(width: textW, height: 300), options: .usesLineFragmentOrigin, context: nil
        ).height ?? 20
        let helpH: CGFloat = helpLabel.isHidden ? 0 : (helpLabel.attributedText?.boundingRect(
            with: CGSize(width: textW, height: 200), options: .usesLineFragmentOrigin, context: nil
        ).height ?? 0) + 1
        let textBlockH = ceil(textH) + helpH
        let contentH = max(textBlockH, btnH)
        let safeB = superview?.safeAreaInsets.bottom ?? 0
        let panelH = 8 + contentH + 8
        panel.frame = CGRect(x: 8, y: bounds.height - safeB - panelH - 8, width: w, height: panelH)
        textLabel.frame = CGRect(x: 12, y: 8, width: textW, height: ceil(textH))
        helpLabel.frame = CGRect(x: 12, y: textLabel.frame.maxY + 1, width: textW, height: max(0, helpH - 1))
        var x = w - 12 - btnsW
        for (i, b) in buttons.enumerated() {
            b.frame = CGRect(x: x, y: 8 + (contentH - btnH) / 2, width: buttonWidths[i], height: btnH)
            x += buttonWidths[i] + 8
        }
    }

    /// Route touches: only the scrim + panel are interactive; the rest passes
    /// through so the screen behind stays inert while dimmed.
    public override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        !isHidden
    }
}
