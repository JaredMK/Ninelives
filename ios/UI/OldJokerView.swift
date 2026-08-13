import UIKit
import GameCore

/// THE OLD JOKER's modal. Deliberately UNLIKE the ordinary mystery reveal: that
/// one is a centred card that flips and tells you what happened. This is a
/// conversation — he stands on the left, speaks on the right, and the choices
/// stack under him. He never takes an action you did not pick.
///
/// Motion is compositor-only (alpha + transform on existing views), one-shot,
/// and nothing animates while the modal just sits there.
final class OldJokerView: UIView {

    /// One button on the offer.
    struct Option {
        var label: String
        var detail: String?
        var role: PixelButtonView.Role
        var choice: OldJoker.Choice
        /// A choice he SHOWS you but won't let you take — the ride you can't
        /// cover the fare on. It stays on the card, greyed, so the offer reads
        /// as a thing you missed rather than a thing that never happened.
        var enabled = true
    }

    /// One half of a YOURS→HIS comparison — art for real items, a glyph for
    /// sides with nothing to draw (coins, the blind swap's face-down card).
    struct CompareSide {
        var tag: String
        var art: UIImage?
        var glyph: String?
        var glyphColor: UIColor = CRT.gold
        var name: String
        var desc: String
    }

    /// What leaves → what arrives. The store's EQUIPPED→NEW block, spoken
    /// in his grammar: every item decision shows both sides before a button
    /// is offered.
    struct CompareRow {
        var old: CompareSide
        var new: CompareSide
        /// A settled two-sided trade draws ↔ instead of →.
        var twoWay = false
    }

    private let scrim = UIView()
    private let panel = PixelPanelView(face: CRT.feltMid, border: CRT.gold)
    /// The panel's content SCROLLS. An offer that names four items (Refund)
    /// plus their descriptions is taller than a phone, and this modal has no
    /// other way out of that — capping the text would hide the very thing the
    /// key was added to show.
    private let scroll = UIScrollView()
    private let content = UIView()
    private let art = UIImageView()
    private let nameLabel = UILabel()
    private let speech = UILabel()
    private let offerLabel = UILabel()
    private var buttons: [PixelButtonView] = []
    private let onChoose: (OldJoker.Choice) -> Void

    init(title: String, line: String, offer: String, items: [(String, String)] = [],
         compares: [CompareRow] = [],
         options: [Option], mapPeek: Bool = true, givePurse purse: Int? = nil,
         art artImage: UIImage? = nil,
         backLabel: String = "◀ BACK TO THE JOKER",
         onChoose: @escaping (OldJoker.Choice) -> Void) {
        self.onChoose = onChoose
        super.init(frame: .zero)
        // Another character can borrow his conversation modal wholesale —
        // JUST A TWO's con runs through here with its own card.
        defer { if let artImage { art.image = artImage } }
        backButton.setTitle(backLabel)

        scrim.backgroundColor = CRT.ink.withAlphaComponent(0.9)
        addSubview(scrim)
        // (The old hold-anywhere-to-peek is gone: an accidental press made
        // the whole offer vanish under the player's finger, which read as
        // the popup dismissing. SHOW MAP is now an explicit button on every
        // offer, with an explicit way back — nothing else moves this modal.)
        addSubview(panel)
        scroll.showsVerticalScrollIndicator = true
        panel.addSubview(scroll)
        scroll.addSubview(content)

        art.image = ItemArt.oldJoker(scale: 5)
        art.contentMode = .scaleAspectFit
        art.layer.magnificationFilter = .nearest
        art.layer.minificationFilter = .nearest
        content.addSubview(art)

        // GOLD, not phosphor: he is not a system message, he is a person.
        nameLabel.attributedText = CRTKit.attributed(title.uppercased(), size: 16,
                                                     color: CRT.gold, display: true)
        // The corner MAP chip narrows the name's slot — shrink, never "JOK…".
        nameLabel.adjustsFontSizeToFitWidth = true
        nameLabel.minimumScaleFactor = 0.6
        content.addSubview(nameLabel)

        speech.numberOfLines = 0
        speech.attributedText = CRTKit.attributed("\u{201C}\(line)\u{201D}", size: 16, color: CRT.cardFace)
        content.addSubview(speech)

        offerLabel.numberOfLines = 0
        // 16pt cream (router batch 2): this line IS the event ("8♠ purged.")
        // and read as a footnote at 14pt muted.
        offerLabel.attributedText = CRTKit.attributed(offer, size: 16,
                                                      color: CRT.cardFace.withAlphaComponent(0.9))
        content.addSubview(offerLabel)

        // WHAT THE NAMED ITEMS DO — gold name, cream effect, straight from the
        // registry. Without this the offer is two proper nouns and a shrug.
        for (label, text) in items {
            let n = CRTKit.label(label, size: 14, color: CRT.gold)
            let d = CRTKit.label(text, size: 14, color: CRT.cardFace)
            d.alpha = 0.85
            content.addSubview(n)
            content.addSubview(d)
            itemLabels.append((n, d))
        }

        // THE TRADE, DRAWN — the store's EQUIPPED→NEW comparison. What
        // leaves on the left, what arrives on the right, gold arrow between,
        // one row per thing he'd take. The item key above is for offers that
        // only NAME items; a trade shows them instead.
        for row in compares {
            let oldV = CompareSideView(tag: row.old.tag, isNew: false)
            let newV = CompareSideView(tag: row.new.tag, isNew: true)
            for (side, view) in [(row.old, oldV), (row.new, newV)] {
                if let g = side.glyph {
                    view.showGlyph(g, color: side.glyphColor, name: side.name, desc: side.desc)
                } else if let a = side.art {
                    view.show(art: a, name: side.name, desc: side.desc)
                } else {
                    view.showEmpty(name: side.name, desc: side.desc)
                }
            }
            let arrow = UILabel()
            arrow.attributedText = CRTKit.attributed(row.twoWay ? "↔" : "→", size: 16, color: CRT.gold)
            arrow.textAlignment = .center
            content.addSubview(oldV)
            content.addSubview(arrow)
            content.addSubview(newV)
            compareViews.append((oldV, arrow, newV))
        }

        for (i, o) in options.enumerated() {
            let b = PixelButtonView(o.label, role: o.role, fontSize: 16)
            b.onTap = { [weak self] in self?.pick(o.choice) }
            b.accessibilityLabel = o.label
            b.isEnabled = o.enabled
            content.addSubview(b)
            buttons.append(b)
            _ = i
        }
        self.optionDetails = options.map(\.detail)

        if let purse {
            giveEnabled = true
            givePurseMax = max(0, purse)
            giveAmount = min(1, givePurseMax)   // opens on a single coin
            giveLabel.textAlignment = .center
            givePurse.textAlignment = .center
            giveMinus.onTap = { [weak self] in self?.stepGive(-1) }
            givePlus.onTap = { [weak self] in self?.stepGive(1) }
            giveButton.onTap = { [weak self] in
                guard let self else { return }
                self.pick(.give(self.giveAmount))
            }
            for v in [giveMinus, givePlus, giveButton] { content.addSubview(v) }
            content.addSubview(giveLabel)
            content.addSubview(givePurse)
            refreshGive()
        }

        peekEnabled = mapPeek
        if mapPeek {
            peekButton.onTap = { [weak self] in self?.beginPeek() }
            content.addSubview(peekButton)
            // DECK rides just under MAP (router batch 2): the same inspector
            // the shop's Pinky tap opens — cards AND the equipped loadout.
            deckButton.onTap = { [weak self] in self?.onDeck?() }
            deckButton.isHidden = true
            content.addSubview(deckButton)
            backButton.onTap = { [weak self] in self?.endPeek() }
            backButton.isHidden = true
            addSubview(backButton)
        }
    }

    /// While PEEKING, this view is a floating BACK button and nothing else —
    /// every other touch falls through to the map so the player can actually
    /// scroll it. Without this the overlay stayed full-screen and invisible,
    /// and the map they were sent to inspect couldn't be moved.
    /// While PEEKING every touch except the BACK button falls through to the
    /// map, so it can be scrolled. Travel is blocked separately — the map
    /// refuses node taps while `onPeekChanged` says a peek is open — because
    /// letting touches through is what makes scrolling work, and a tap and a
    /// drag arrive the same way.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isPeeking else { return super.hitTest(point, with: event) }
        if !backButton.isHidden, backButton.frame.contains(point) {
            return backButton.hitTest(convert(point, to: backButton), with: event) ?? backButton
        }
        return nil
    }

    /// Fires whenever a peek opens or closes — the host uses it to freeze
    /// travel while the offer is still on the table.
    var onPeekChanged: ((Bool) -> Void)?

    // (peekHeld / heldPeek removed with the hold gesture.)

    private func stepGive(_ d: Int) {
        giveAmount = max(0, min(givePurseMax, giveAmount + d))
        refreshGive()
    }

    private func refreshGive() {
        giveLabel.attributedText = CRTKit.attributed("\(giveAmount)", size: 26, color: CRT.gold)
        givePurse.attributedText = CRTKit.attributed(
            givePurseMax > 0 ? "you have \(givePurseMax)" : "you have nothing",
            size: 14, color: CRT.muted)
        giveButton.setTitle(giveAmount > 0 ? "GIVE \(giveAmount)" : "GIVE HIM NOTHING")
        giveButton.setRole(giveAmount > 0 ? .gold : .plain)
        giveMinus.isEnabled = giveAmount > 0
        givePlus.isEnabled = giveAmount < givePurseMax
    }

    private func beginPeek() {
        isPeeking = true
        onPeekChanged?(true)
        backButton.isHidden = false
        // beginFromCurrentState + no hidden-flag juggling: the old completion
        // set `isHidden` AFTER the fade, and a fast peek/return left the
        // scrim stuck invisible.
        UIView.animate(withDuration: 0.18, delay: 0, options: [.beginFromCurrentState]) {
            self.scrim.alpha = 0
            self.panel.alpha = 0
        }
    }

    private func endPeek() {
        isPeeking = false
        onPeekChanged?(false)
        backButton.isHidden = true
        UIView.animate(withDuration: 0.18, delay: 0, options: [.beginFromCurrentState]) {
            self.scrim.alpha = 1
            self.panel.alpha = 1
        }
    }

    private var optionDetails: [String?] = []
    private var detailLabels: [UILabel] = []
    private var itemLabels: [(UILabel, UILabel)] = []
    private var compareViews: [(CompareSideView, UILabel, CompareSideView)] = []
    /// MAP PEEK. A small CORNER chip — like a pause button, deliberately
    /// apart from the decision stack (a full-width SHOW MAP under the options
    /// read as one of them). It hides him without dismissing him; the
    /// floating back button returns.
    private let peekButton = PixelButtonView("MAP", role: .plain, fontSize: 14)
    private let deckButton = PixelButtonView("DECK", role: .plain, fontSize: 14)
    /// Open the deck inspector (wired by the flow; hidden when nil).
    var onDeck: (() -> Void)? {
        didSet { deckButton.isHidden = onDeck == nil }
    }
    private let backButton = PixelButtonView("◀ BACK TO THE JOKER", role: .gold, fontSize: 16)
    private var peekEnabled = false
    private(set) var isPeeking = false
    /// THIRSTY's amount picker: − / + over a live figure, floored at 0 and
    /// capped at the purse. Zero is a legal answer and a pointed one, so the
    /// GIVE button never disables — it just says GIVE HIM NOTHING.
    private let giveMinus = PixelButtonView("−", role: .plain, fontSize: 20)
    private let givePlus = PixelButtonView("+", role: .plain, fontSize: 20)
    private let giveLabel = UILabel()
    private let givePurse = UILabel()
    private let giveButton = PixelButtonView("GIVE", role: .gold, fontSize: 16)
    private var givePurseMax = 0
    private var giveAmount = 0
    private var giveEnabled = false

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    private func pick(_ c: OldJoker.Choice) {
        // Lock the row so a double-tap can't resolve twice.
        buttons.forEach { $0.isEnabled = false }
        Sound.shared.continueTap()
        onChoose(c)
    }

    /// Rise-and-settle, one shot. Nothing animates after this.
    func present(in host: UIView) {
        frame = host.bounds
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.addSubview(self)
        layoutIfNeeded()
        alpha = 0
        panel.transform = CGAffineTransform(translationX: 0, y: 18)
        UIView.animate(withDuration: 0.24, delay: 0, options: [.curveEaseOut]) {
            self.alpha = 1
            self.panel.transform = .identity
        }
        // He leans in once as he speaks — a single 260ms beat, then still.
        art.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        UIView.animate(withDuration: 0.26, delay: 0.12, usingSpringWithDamping: 0.6,
                       initialSpringVelocity: 0.4) {
            self.art.transform = .identity
        }
    }

    func dismiss(_ done: @escaping () -> Void) {
        UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseIn]) {
            self.alpha = 0
            self.panel.transform = CGAffineTransform(translationX: 0, y: 12)
        } completion: { _ in
            self.removeFromSuperview()
            done()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrim.frame = bounds
        let w = min(360, bounds.width - 24)
        let pad: CGFloat = 14
        let artW: CGFloat = 78
        var y: CGFloat = pad

        // Header row: the card on the left, name + speech to the right of it.
        // The MAP chip rides the top-right CORNER, clear of the choices.
        let textX = pad + artW + 12
        let chipW: CGFloat = peekEnabled ? 52 : 0
        if peekEnabled {
            peekButton.frame = CGRect(x: w - pad - 52, y: pad, width: 52, height: 26)
            deckButton.frame = CGRect(x: w - pad - 52, y: pad + 30, width: 52, height: 26)
        }
        let textW = w - textX - pad - (chipW > 0 ? chipW + 6 : 0)
        nameLabel.frame = CGRect(x: textX, y: y, width: textW, height: 20)
        // sizeThatFits, not boundingRect — the pixel font renders taller than
        // it measures and a fragment-sized frame truncates instead of wrapping.
        let speechH = ceil(speech.sizeThatFits(CGSize(width: textW, height: 400)).height)
        speech.frame = CGRect(x: textX, y: y + 24, width: textW, height: speechH)
        let headerH = max(artW * 20 / 14, 24 + speechH)
        art.frame = CGRect(x: pad, y: y, width: artW, height: artW * 20 / 14)
        y += headerH + 12

        // What he is actually proposing.
        let offerH = ceil(offerLabel.sizeThatFits(CGSize(width: w - pad * 2, height: 400)).height)
        offerLabel.frame = CGRect(x: pad, y: y, width: w - pad * 2, height: offerH)
        y += offerH + 12

        // The item key: each named item's effect, indented under its name.
        let keyW = w - pad * 2
        func measure(_ l: UILabel, _ width: CGFloat) -> CGFloat {
            ceil(l.sizeThatFits(CGSize(width: width, height: 2000)).height)
        }
        for (n, d) in itemLabels {
            let nh = measure(n, keyW)
            n.frame = CGRect(x: pad, y: y, width: keyW, height: nh)
            y += nh + 2
            let dh = measure(d, keyW - 10)
            d.frame = CGRect(x: pad + 10, y: y, width: keyW - 10, height: dh)
            y += dh + 10
        }
        if !itemLabels.isEmpty { y += 2 }

        // The YOURS→HIS rows, the store detail's compare geometry.
        if !compareViews.isEmpty {
            let arrowW: CGFloat = 16, gap: CGFloat = 7
            let sideW = (keyW - arrowW - gap * 2) / 2
            for (oldV, arrow, newV) in compareViews {
                let h = max(oldV.layout(width: sideW), newV.layout(width: sideW))
                oldV.frame = CGRect(x: pad, y: y, width: sideW, height: h)
                arrow.frame = CGRect(x: pad + sideW + gap, y: y, width: arrowW, height: h)
                newV.frame = CGRect(x: pad + sideW + gap + arrowW + gap, y: y,
                                    width: sideW, height: h)
                y += h + 8
            }
            y += 4
        }

        // THIRSTY's amount picker sits ABOVE the choices: pick the number,
        // then commit to it.
        if giveEnabled {
            let bw: CGFloat = 54
            giveMinus.frame = CGRect(x: pad, y: y, width: bw, height: 46)
            givePlus.frame = CGRect(x: w - pad - bw, y: y, width: bw, height: 46)
            giveLabel.frame = CGRect(x: pad + bw, y: y, width: w - pad * 2 - bw * 2, height: 30)
            givePurse.frame = CGRect(x: pad + bw, y: y + 30, width: w - pad * 2 - bw * 2, height: 16)
            y += 46 + 10
            giveButton.frame = CGRect(x: pad, y: y, width: w - pad * 2, height: 50)
            y += 50 + 8
        }

        // The choices — full width, generous, decline last.
        detailLabels.forEach { $0.removeFromSuperview() }
        detailLabels = []
        for (i, b) in buttons.enumerated() {
            b.frame = CGRect(x: pad, y: y, width: w - pad * 2, height: 50)
            y += 50
            if let d = optionDetails[safe: i] ?? nil, !d.isEmpty {
                let l = CRTKit.label(d, size: 14, color: CRT.muted)
                l.textAlignment = .center
                l.frame = CGRect(x: pad, y: y + 2, width: w - pad * 2, height: 16)
                content.addSubview(l)
                detailLabels.append(l)
                y += 18
            }
            y += 8
        }
        y += pad - 8

        // The panel takes the height it needs, up to what the screen allows;
        // past that the content scrolls rather than running off the bottom.
        let contentH = y
        let maxH = bounds.height - safeAreaInsets.top - safeAreaInsets.bottom - 16
        let panelH = min(contentH, max(160, maxH))
        panel.frame = CGRect(x: (bounds.width - w) / 2,
                             y: max(safeAreaInsets.top + 8, (bounds.height - panelH) / 2),
                             width: w, height: panelH)
        scroll.frame = panel.bounds
        content.frame = CGRect(x: 0, y: 0, width: w, height: contentH)
        scroll.contentSize = CGSize(width: w, height: contentH)

        // The way back rides at the bottom, clear of the map's own chrome.
        backButton.frame = CGRect(x: (bounds.width - w) / 2,
                                  y: bounds.height - safeAreaInsets.bottom - 62,
                                  width: w, height: 48)
    }
}
