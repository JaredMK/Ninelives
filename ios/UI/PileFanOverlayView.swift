import UIKit
import GameCore

/// The pile fan-out viewer — the web's `openPileFan` (index.html:19097, CSS
/// `.pile-fan` index.html:4498). While the FAN hint is armed, tapping a pile
/// opens this overlay: that pile's full contents FACE UP, top card first,
/// lightly staggered rotations, in a horizontally scrolling row (the web
/// wraps into rows + scrolls vertically; the phone's thumb wants a
/// side-scroll). Pure memory aid — nothing here is new information, and the
/// deal underneath is never blocked after dismissal: the full-screen scrim
/// eats every touch while it's open, so no guess can slip through.
///
/// Rendered ONCE per open from a snapshot of the pile (baked UIImages — no
/// live layers, no animations), exactly like the web's one-shot innerHTML.
public final class PileFanOverlayView: UIView {

    public var onDismiss: (() -> Void)?

    private let cards: [LiveCard]   // TOP first
    private let scrim = UIControl()
    private let panel = PixelPanelView(face: CRT.feltMid, border: CRT.ink)
    private let titleLabel: UILabel
    private let orderLabel = CRTKit.label("TOP → BOTTOM", size: 14, color: CRT.muted)
    private let noteLabel = CRTKit.label("HOLD A CARD FOR INFO · TAP OUTSIDE TO CLOSE", size: 14, color: CRT.muted)
    private let closeButton = PixelButtonView("✕", role: .plain, fontSize: 14)
    private let scroll = UIScrollView()
    private var boxes: [UIView] = []
    private var rowHeight: CGFloat = 0
    private var built = false
    /// The hold-for-info card panel (rank/suit + sticker help), shown while a
    /// finger holds a fanned card, hidden on release.
    private let infoPanel = PixelPanelView(face: CRT.feltDeep, border: CRT.phosphor)
    private let infoTitle = UILabel()
    private let infoScroll = UIScrollView()
    private let infoBody = UILabel()

    /// `.three` (72×100) — big enough to READ the ranks, small enough that a
    /// big pile invites the scroll. The pitch adds the web's 12pt card gap.
    private static let pitch: CGFloat = 88
    private static let sidePad: CGFloat = 13
    /// The web's light alternating tilts (.pf-card:nth-child 4n cycle).
    private static let tilts: [CGFloat] = [-3, 2.2, -1.6, 3]

    /// `stackOrder` is the pile's own storage order (bottom…top, same as the
    /// web's `pile.cards`); the fan shows TOP first, so it's reversed here.
    public init(pileIndex: Int, stackOrder: [LiveCard]) {
        self.cards = stackOrder.reversed()
        let n = stackOrder.count
        self.titleLabel = CRTKit.label("PILE \(pileIndex + 1) · \(n) CARD\(n == 1 ? "" : "S")",
                                       size: 14, color: CRT.phosphor, display: true, glow: true)
        super.init(frame: .zero)
        autoresizingMask = [.flexibleWidth, .flexibleHeight]

        scrim.backgroundColor = CRT.ink.withAlphaComponent(0.6)
        scrim.accessibilityLabel = "Close pile fan"
        scrim.addTarget(self, action: #selector(scrimTapped), for: .touchUpInside)
        addSubview(scrim)

        panel.isUserInteractionEnabled = true
        addSubview(panel)
        panel.addSubview(titleLabel)
        panel.addSubview(orderLabel)
        panel.addSubview(noteLabel)
        closeButton.onTap = { [weak self] in self?.close() }
        panel.addSubview(closeButton)

        scroll.alwaysBounceHorizontal = true
        scroll.showsHorizontalScrollIndicator = false
        panel.addSubview(scroll)

        // The hold-for-info panel: a floating card-info plaque over the fan.
        infoPanel.isHidden = true
        // Both WRAP. The title was pinned to one line and the body truncated
        // its tail, so a long item name lost its ending and a long effect line
        // stopped mid-sentence — on the one panel whose whole job is to explain.
        infoTitle.numberOfLines = 0
        infoTitle.lineBreakMode = .byWordWrapping
        infoBody.numberOfLines = 0
        infoBody.lineBreakMode = .byWordWrapping
        infoPanel.addSubview(infoTitle)
        // v6.74: the body rides a scroll view — a long effect line scrolls
        // instead of clipping at the 55% cap (stable shell, scrolling content).
        infoScroll.showsVerticalScrollIndicator = true
        infoScroll.addSubview(infoBody)
        infoPanel.addSubview(infoScroll)
        addSubview(infoPanel)

        buildCards()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    public func show(in host: UIView) {
        frame = host.bounds
        host.addSubview(self)
        setNeedsLayout()
        layoutIfNeeded()
        scroll.flashScrollIndicators()
    }

    public func close() {
        removeFromSuperview()
        onDismiss?()
    }

    @objc private func scrimTapped() { close() }

    // MARK: - Content (built once per open)

    private func buildCards() {
        let artW: CGFloat = 76   // 72 + the baked 4px hard shadow
        let topPad: CGFloat = 12 // clears the TOP pill above the first card

        for (i, c) in cards.enumerated() {
            let box = UIView()
            // ONE renderer (v6.81): face + chips baked by CardComposite —
            // the hand-placed chip views this fan used until v6.80 carried
            // the same negative-zPosition trap the deck view did (chips 2…4
            // sank beneath the card face; see CardComposite's header).
            let iv = UIImageView(image: CardComposite.image(c, scale: .three))
            let artH = iv.image?.size.height ?? 104   // 100 + the baked 4px shadow
            iv.layer.magnificationFilter = .nearest
            iv.contentMode = .scaleAspectFit
            iv.frame = CGRect(x: 0, y: topPad - StickerChipLayout.topRaise,
                              width: artW + StickerChipLayout.rightOverhang,
                              height: artH + StickerChipLayout.topRaise)
            box.addSubview(iv)

            // The web's marker chips: a loud phosphor TOP on the first card,
            // a muted felt-deep BOTTOM under the last.
            if i == 0 {
                let pill = Self.pill("TOP", bg: CRT.phosphor, fg: CRT.ink)
                pill.frame.origin = CGPoint(x: (artW - pill.bounds.width) / 2, y: topPad - 8)
                box.addSubview(pill)
            }
            let bottomPill = (i == cards.count - 1 && cards.count > 1)

            var boxH = topPad + artH + 8
            if bottomPill {
                let pill = Self.pill("BOTTOM", bg: CRT.feltDeep, fg: CRT.cardFace)
                pill.frame.origin = CGPoint(x: (artW - pill.bounds.width) / 2,
                                            y: topPad + artH - 7)
                box.addSubview(pill)
                boxH = max(boxH, topPad + artH + 12)
            }
            box.frame = CGRect(x: 0, y: 0, width: artW, height: boxH)
            // The fan tilt — rotates the whole card unit like the web's
            // .pf-card (chips ride along); a static transform, no animation.
            box.transform = CGAffineTransform(rotationAngle: Self.tilts[i % 4] * .pi / 180)
            // Hold a fanned card → its info (rank/suit + sticker help), the
            // same cardPeekHtml idiom as the board's pile hold. A plain TAP
            // (v6.78) shows the same info as a toggle — tap again (or tap
            // another card) to move on; both gestures work.
            let hold = UILongPressGestureRecognizer(target: self, action: #selector(cardHeld(_:)))
            hold.minimumPressDuration = 0.35
            box.tag = i
            box.addGestureRecognizer(hold)
            let tap = UITapGestureRecognizer(target: self, action: #selector(cardTapped(_:)))
            box.addGestureRecognizer(tap)
            scroll.addSubview(box)
            boxes.append(box)
            rowHeight = max(rowHeight, boxH)
        }
    }

    /// The card a TAP pinned the info panel open for (nil = hold-driven).
    private var tappedInfoIndex: Int?

    @objc private func cardHeld(_ g: UILongPressGestureRecognizer) {
        switch g.state {
        case .began:
            let i = g.view?.tag ?? -1
            guard i >= 0, i < cards.count else { return }
            tappedInfoIndex = nil            // a hold takes over from any tap-pin
            showInfo(for: cards[i])
        case .ended, .cancelled, .failed:
            if tappedInfoIndex == nil { infoPanel.isHidden = true }
        default: break
        }
    }

    /// TAP = the same info as the hold, pinned open (v6.78): tap the same
    /// card again to dismiss, or tap another card to switch.
    @objc private func cardTapped(_ g: UITapGestureRecognizer) {
        let i = g.view?.tag ?? -1
        guard i >= 0, i < cards.count else { return }
        if tappedInfoIndex == i, !infoPanel.isHidden {
            infoPanel.isHidden = true
            tappedInfoIndex = nil
            return
        }
        tappedInfoIndex = i
        showInfo(for: cards[i])
    }

    private func showInfo(for card: LiveCard) {
        let info = CardInfoText.make(card)
        // v6.74: the shared CardInfo scale (title one display step up).
        infoTitle.attributedText = CRTKit.attributed(info.title, size: 20, color: CRT.phosphor, display: true)
        infoBody.attributedText = CRTKit.attributed(info.body, size: 16, color: CRT.cardFace)
        infoPanel.isHidden = false
        setNeedsLayout()
    }

    /// Screenshot-harness hook (simctl can't deliver a hold): the info panel
    /// as a real hold on the top card would show it.
    public func demoShowInfo() {
        guard let first = cards.first else { return }
        showInfo(for: first)
    }

    private static func pill(_ text: String, bg: UIColor, fg: UIColor) -> UILabel {
        let l = CRTKit.label(text, size: 14, color: fg)
        l.backgroundColor = bg
        l.textAlignment = .center
        let w = ceil(l.attributedText?.size().width ?? 20) + 10
        l.frame = CGRect(x: 0, y: 0, width: w, height: 15)
        return l
    }

    // MARK: - Layout

    public override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0 else { return }
        scrim.frame = bounds

        // Panel: web .pile-fan — felt-mid, 2px ink border, hard ↘ shadow,
        // centred, capped width, sized to its content.
        let padTop: CGFloat = 12, padBottom: CGFloat = 10
        let titleH: CGFloat = 16, orderH: CGFloat = 15, noteH: CGFloat = 15
        let contentH = padTop + titleH + 3 + orderH + 8 + rowHeight + 8 + noteH + padBottom
        let panelW = min(bounds.width - 28, 400)
        // Safe-area capped: a giant pile's panel still clears notch + indicator.
        let panelH = min(contentH, bounds.height - safeAreaInsets.top
                         - max(safeAreaInsets.bottom, 12) - 24)
        panel.frame = CGRect(x: (bounds.width - panelW) / 2,
                             y: (bounds.height - panelH) / 2,
                             width: panelW, height: panelH)

        let innerW = panelW - Self.sidePad * 2
        titleLabel.frame = CGRect(x: Self.sidePad, y: padTop, width: innerW - 44, height: titleH)
        closeButton.frame = CGRect(x: panelW - Self.sidePad - 34, y: padTop - 2, width: 34, height: 24)
        orderLabel.frame = CGRect(x: Self.sidePad, y: padTop + titleH + 3, width: innerW, height: orderH)

        let scrollY = padTop + titleH + 3 + orderH + 8
        scroll.frame = CGRect(x: 0, y: scrollY, width: panelW, height: min(rowHeight, panelH - scrollY - 8 - noteH - padBottom))
        let contentW = CGFloat(boxes.count) * Self.pitch - (Self.pitch - 76) + Self.sidePad * 2
        // A short row centres inside the panel; a long one scrolls.
        let x0 = max(Self.sidePad, (innerW - (contentW - Self.sidePad * 2)) / 2)
        for (i, box) in boxes.enumerated() {
            box.frame.origin = CGPoint(x: x0 + CGFloat(i) * Self.pitch, y: 0)
        }
        scroll.contentSize = CGSize(width: max(contentW, scroll.bounds.width + 1),
                                    height: scroll.bounds.height)
        noteLabel.frame = CGRect(x: Self.sidePad, y: panelH - padBottom - noteH,
                                 width: innerW, height: noteH)
        noteLabel.textAlignment = .center
        // The hold-for-info plaque floats centred over the fan.
        if !infoPanel.isHidden {
            let w = min(bounds.width - 32, 340)
            let textW = w - 20
            func measure(_ a: NSAttributedString?) -> CGFloat {
                ceil(a?.boundingRect(with: CGSize(width: textW, height: 2000),
                                     options: .usesLineFragmentOrigin, context: nil).height ?? 0)
            }
            let titleH = max(18, measure(infoTitle.attributedText))
            // The plaque may take over half the overlay; the body SCROLLS
            // inside its capped band rather than clipping (v6.74).
            let fullBodyH = measure(infoBody.attributedText)
            let bodyH = min(fullBodyH, floor(bounds.height * 0.55))
            let h = 8 + titleH + 2 + bodyH + 8
            infoPanel.frame = CGRect(x: (bounds.width - w) / 2,
                                     y: (bounds.height - h) / 2,
                                     width: w, height: h)
            infoTitle.frame = CGRect(x: 10, y: 8, width: textW, height: titleH)
            infoScroll.frame = CGRect(x: 10, y: 8 + titleH + 2, width: textW, height: bodyH)
            infoBody.frame = CGRect(x: 0, y: 0, width: textW, height: fullBodyH)
            infoScroll.contentSize = CGSize(width: textW, height: fullBodyH)
        }
        if !built {
            built = true
            scroll.flashScrollIndicators()
        }
    }
}
