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
        infoPanel.addSubview(infoBody)
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
        let chipSize: CGFloat = 16, chipGap: CGFloat = 2, chipsPerRow = 3, chipsMax = 6

        for (i, c) in cards.enumerated() {
            let box = UIView()
            let iv = UIImageView(image: CardArt.image(CardArt.Face(c), scale: .three))
            let artH = iv.image?.size.height ?? 104   // 100 + the baked 4px shadow
            iv.layer.magnificationFilter = .nearest
            iv.contentMode = .scaleAspectFit
            iv.frame = CGRect(x: 0, y: topPad, width: artW, height: artH)
            box.addSubview(iv)

            // The web's marker chips: a loud phosphor TOP on the first card,
            // a muted felt-deep BOTTOM under the last.
            var chipsY = topPad + artH + 4
            if i == 0 {
                let pill = Self.pill("TOP", bg: CRT.phosphor, fg: CRT.ink)
                pill.frame.origin = CGPoint(x: (artW - pill.bounds.width) / 2, y: topPad - 8)
                box.addSubview(pill)
            }
            let bottomPill = (i == cards.count - 1 && cards.count > 1)
            if bottomPill {
                chipsY += 10   // the BOTTOM pill hangs under the card — clear it
            }

            // Sticker chips below the card, the DeckInspect idiom (rows of 3,
            // capped at 2 rows), so the fan shows WHAT a card carries.
            let stickers = Array(c.stickers.prefix(chipsMax))
            for (s, rec) in stickers.enumerated() {
                guard let def = GameData.shared.stickerTypes.get(rec.type) else { continue }
                let sRow = s / chipsPerRow, sCol = s % chipsPerRow
                let inRow = min(chipsPerRow, stickers.count - sRow * chipsPerRow)
                let lineW = CGFloat(inRow) * chipSize + CGFloat(inRow - 1) * chipGap
                let chip = UIImageView(image: ItemArt.sticker(def, size: chipSize))
                chip.layer.magnificationFilter = .nearest
                chip.contentMode = .scaleAspectFit
                chip.frame = CGRect(x: (artW - lineW) / 2 + CGFloat(sCol) * (chipSize + chipGap),
                                    y: chipsY + CGFloat(sRow) * (chipSize + chipGap),
                                    width: chipSize, height: chipSize)
                box.addSubview(chip)
            }
            let chipRows = (stickers.count + chipsPerRow - 1) / chipsPerRow
            var boxH = chipsY + CGFloat(chipRows) * (chipSize + chipGap)
            if bottomPill {
                let pill = Self.pill("BOTTOM", bg: CRT.feltDeep, fg: CRT.cardFace)
                pill.frame.origin = CGPoint(x: (artW - pill.bounds.width) / 2,
                                            y: topPad + artH - 7)
                box.addSubview(pill)
                boxH = max(boxH, topPad + artH + 8)
            }
            box.frame = CGRect(x: 0, y: 0, width: artW, height: boxH)
            // The fan tilt — rotates the whole card unit like the web's
            // .pf-card (chips ride along); a static transform, no animation.
            box.transform = CGAffineTransform(rotationAngle: Self.tilts[i % 4] * .pi / 180)
            // Hold a fanned card → its info (rank/suit + sticker help), the
            // same cardPeekHtml idiom as the board's pile hold.
            let hold = UILongPressGestureRecognizer(target: self, action: #selector(cardHeld(_:)))
            hold.minimumPressDuration = 0.35
            box.tag = i
            box.addGestureRecognizer(hold)
            scroll.addSubview(box)
            boxes.append(box)
            rowHeight = max(rowHeight, boxH)
        }
    }

    @objc private func cardHeld(_ g: UILongPressGestureRecognizer) {
        switch g.state {
        case .began:
            let i = g.view?.tag ?? -1
            guard i >= 0, i < cards.count else { return }
            showInfo(for: cards[i])
        case .ended, .cancelled, .failed:
            infoPanel.isHidden = true
        default: break
        }
    }

    private func showInfo(for card: LiveCard) {
        let info = CardInfoText.make(card)
        infoTitle.attributedText = CRTKit.attributed(info.title, size: 14, color: CRT.phosphor)
        infoBody.attributedText = CRTKit.attributed(info.body, size: 14, color: CRT.cardFace)
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
            // The plaque may take over half the overlay before the body has to
            // scroll-clip: an effect line that doesn't finish is worse than a
            // tall plaque over a fan the player is already reading past.
            let bodyH = min(measure(infoBody.attributedText), floor(bounds.height * 0.55))
            let h = 8 + titleH + 2 + bodyH + 8
            infoPanel.frame = CGRect(x: (bounds.width - w) / 2,
                                     y: (bounds.height - h) / 2,
                                     width: w, height: h)
            infoTitle.frame = CGRect(x: 10, y: 8, width: textW, height: titleH)
            infoBody.frame = CGRect(x: 10, y: 8 + titleH + 2, width: textW, height: bodyH)
        }
        if !built {
            built = true
            scroll.flashScrollIndicators()
        }
    }
}
