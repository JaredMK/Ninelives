import UIKit
import GameCore

/// The pack reveal — web `#packReveal` (a `.confirm-overlay`): a CENTERED pixel
/// panel over the ink scrim (the store/map stays visible behind it), the
/// phosphor marquee title, the revealed items in ONE row, the "View cards in
/// play" deck aid (card packs only), the phosphor CONFIRM (disabled until
/// exactly `keep` items are picked), and the "Skip (take nothing)" link under
/// it. FORCED PICK — the web has no backdrop dismiss (index.html:22124 "Forced
/// pick — no backdrop dismiss"); tapping off an item only closes the
/// item-info slot.
///
/// Modes:
///   .pick   — store pack: choose `keep`, the rest are lost
///   .show   — map pack: cards are ALREADY granted; Continue-only
public final class PackRevealViewController: UIViewController {

    public enum Content {
        case cards([CardSpec])
        case stickers([String])
    }
    public enum Mode { case pick(keep: Int), show }

    private let campaign: CampaignState
    private let content: Content
    private let mode: Mode
    /// Kept for API compatibility — the web's title derives from the PICK
    /// ("Pick 1 card to keep"), never from the pack's label (index.html:29473).
    private let titleText: String
    /// Picked indices (empty on skip; all indices in .show mode).
    private let completion: ([Int]) -> Void

    private let panel = PixelPanelView(face: CRT.feltMid, border: CRT.ink)
    /// `.pack-show` rim: the map reveal's 4px phosphor top border.
    private let showRim = UIView()
    private let titleLabel = UILabel()
    private let itemsRow = UIView()
    private let msgLabel = UILabel()
    private let deckButton = UIButton(type: .custom)
    private let deckDot = UIView()
    private let confirmButton = PixelButtonView("Confirm", role: .cta, fontSize: 14)
    private let skipButton = UIButton(type: .custom)
    private let infoPanel = PixelPanelView(face: CRT.feltMid, border: CRT.ink)
    /// Fixed shell, scrolling content (v6.74): the shared CardInfoView measures
    /// itself; whatever exceeds the panel scrolls inside it — the shell never
    /// moves and nothing clips (the old fixed-height body label clipped long
    /// sticker rows and the whole Joker paragraph silently).
    private let infoScroll = UIScrollView()
    private let infoView = CardInfoView(alignment: .left)
    private let crt = CRTOverlayUIView()
    /// The shared bottom prompt bar — the skip confirmation rides it
    /// (Convention 3: every confirmation, never a one-off dialog).
    private let prompt = PromptBar()
    private var itemButtons: [UIButton] = []
    /// Picked indices (.pick mode only). In .show mode this stays EMPTY: the
    /// web's reveal cards are tap-for-info, NOT selectable — `packItemButton(
    /// …, false)` never paints the keep-outline (index.html:29430-29445).
    private var chosen: [Int] = []

    public init(campaign: CampaignState, title: String, content: Content, mode: Mode,
                completion: @escaping ([Int]) -> Void) {
        self.campaign = campaign
        self.titleText = title
        self.content = content
        self.mode = mode
        self.completion = completion
        super.init(nibName: nil, bundle: nil)
        // overFullScreen: the store/map stays VISIBLE behind the scrim (the web
        // reveal is an overlay, not a takeover). .fullScreen would drop the
        // presenter's view and the scrim would show black.
        modalPresentationStyle = .overFullScreen
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    public override var prefersStatusBarHidden: Bool { true }

    private var count: Int {
        switch content {
        case .cards(let c): return c.count
        case .stickers(let s): return s.count
        }
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        // Web `.confirm-overlay` scrim: rgba(16,16,14,0.72).
        view.backgroundColor = CRT.ink.withAlphaComponent(0.72)

        view.addSubview(panel)
        showRim.backgroundColor = CRT.phosphor
        showRim.isHidden = true
        panel.addSubview(showRim)

        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        panel.addSubview(titleLabel)
        panel.addSubview(itemsRow)
        msgLabel.textAlignment = .center
        msgLabel.numberOfLines = 0
        panel.addSubview(msgLabel)

        // `.pack-deck-btn`: full-width felt-deep button, cream 13px — opens the
        // read-only deck composition (DeckInspector.openFull on the web).
        deckButton.backgroundColor = CRT.feltDeep
        deckButton.layer.borderWidth = CRT.px
        deckButton.layer.borderColor = CRT.ink.cgColor
        deckButton.setAttributedTitle(CRTKit.attributed("View cards in play", size: 14, color: CRT.cardFace), for: .normal)
        deckButton.accessibilityLabel = "VIEW CARDS IN PLAY"
        deckButton.addTarget(self, action: #selector(deckTapped), for: .touchUpInside)
        deckDot.backgroundColor = CRT.cardFace
        deckDot.isUserInteractionEnabled = false
        deckButton.addSubview(deckDot)
        panel.addSubview(deckButton)

        confirmButton.onTap = { [weak self] in self?.confirmTapped() }
        panel.addSubview(confirmButton)

        // `.pack-skip-btn`: full-width felt-deep, muted 12px, MIXED CASE (the web
        // never uppercases it) — so a plain UIButton, not a PixelButtonView.
        skipButton.backgroundColor = CRT.feltDeep
        skipButton.layer.borderWidth = CRT.px
        skipButton.layer.borderColor = CRT.ink.cgColor
        skipButton.setAttributedTitle(CRTKit.attributed("Skip (take nothing)", size: 14, color: CRT.muted), for: .normal)
        skipButton.accessibilityLabel = "SKIP"   // legacy label the UI tests tap
        skipButton.addTarget(self, action: #selector(skipTapped), for: .touchUpInside)
        panel.addSubview(skipButton)

        // The item-info help slot (web `.item-help.pack-item-help`): a floating
        // bottom-anchored panel ABOVE the overlay; shown on select, hidden on
        // deselect or any off-item tap.
        infoPanel.isHidden = true
        infoScroll.showsVerticalScrollIndicator = false
        infoScroll.addSubview(infoView)
        infoPanel.addSubview(infoScroll)
        view.addSubview(infoPanel)

        // Off-item taps close ONLY the info slot — never the reveal itself.
        let bg = UITapGestureRecognizer(target: self, action: #selector(backgroundTapped(_:)))
        bg.cancelsTouchesInView = false
        view.addGestureRecognizer(bg)

        crt.isUserInteractionEnabled = false
        view.addSubview(crt)
        view.addSubview(prompt)

        Sound.shared.pack()
        buildItems()
        refreshChrome()
    }

    private func buildItems() {
        for i in 0..<count {
            let b = UIButton(type: .custom)
            switch content {
            case .cards(let cards):
                // Web `.mini-card` is 52px wide; the nearest native baked face
                // is c50 (48×67) — baked crisp beats a shimmering upscale.
                // Drawn WITH its sticker chips: a granted card's marks must be
                // visible on the face, not only in the hold-help text.
                b.setImage(CardPickerViewController.cardWithStickers(cards[i], extra: nil), for: .normal)
            case .stickers(let ids):
                // Web `.pk-sticker`: a recessed felt well (64px, ink border)
                // holding the 46px vinyl + the sticker's name.
                if let def = GameData.shared.stickerTypes.get(ids[i]) {
                    b.backgroundColor = CRT.feltDeep
                    b.layer.borderWidth = 1
                    b.layer.borderColor = CRT.ink.cgColor
                    let iv = UIImageView(image: ItemArt.sticker(def, size: 46))
                    iv.layer.magnificationFilter = .nearest
                    iv.contentMode = .scaleAspectFit
                    iv.isUserInteractionEnabled = false
                    iv.tag = 101
                    b.addSubview(iv)
                    // The suit restriction rides ABOVE the chip (ItemArt
                    // placement contract), never baked into it (v5.81).
                    if let cap = ItemArt.suitCaptionView(def, width: 40) {
                        cap.isUserInteractionEnabled = false
                        cap.tag = 103
                        b.addSubview(cap)
                    }
                    let name = UILabel()
                    // Sticker names read GOLD (suit-red for a curse) — v6.72.
                    name.attributedText = CRTKit.attributed(
                        def.label, size: 14, color: def.cursed ? CRT.suitRed : CRT.gold)
                    name.textAlignment = .center
                    name.numberOfLines = 2
                    name.isUserInteractionEnabled = false
                    name.tag = 102
                    b.addSubview(name)
                }
            }
            b.imageView?.layer.magnificationFilter = .nearest
            b.adjustsImageWhenHighlighted = false
            b.tag = i
            b.addTarget(self, action: #selector(itemTapped(_:)), for: .touchUpInside)
            itemsRow.addSubview(b)
            itemButtons.append(b)
            // The staggered deal-in pop (packDealIn: rise + overshoot).
            b.alpha = 0
            b.transform = CGAffineTransform(translationX: 0, y: 14).scaledBy(x: 0.86, y: 0.86)
            UIView.animate(withDuration: 0.36, delay: 0.055 * Double(i),
                           usingSpringWithDamping: 0.7, initialSpringVelocity: 0.4) {
                b.alpha = 1
                b.transform = .identity
            }
        }
        // .show mode leaves `chosen` empty — granted cards render unbordered.
        // The completion contract ("all indices in .show") is restored at
        // confirm time in confirmTapped().
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let b = view.bounds
        // Web `.pack-panel`: width min(94vw, 420px), padding 16 top/bottom, 14 sides.
        let pw = min(420, b.width * 0.94)
        let m: CGFloat = 14
        let cw = pw - m * 2
        var y: CGFloat = 16

        let titleH = max(18, measure(titleLabel, width: cw))
        titleLabel.frame = CGRect(x: m, y: y, width: cw, height: titleH)
        y += titleH + 12

        // `.pack-items`: one no-wrap row, 6px gaps, each item centred in its cell.
        let n = max(1, count)
        let gap: CGFloat = 6
        let cellW = (cw - gap * CGFloat(n - 1)) / CGFloat(n)
        var rowH: CGFloat = 0
        for (i, btn) in itemButtons.enumerated() {
            // ROW-LOCAL coordinates: these buttons are children of `itemsRow`,
            // which is itself placed at (m, y). Adding the panel margin here
            // too shifted every card right by `m` (and down by `y`) — that was
            // the right-skewed row. Cells tile the row exactly:
            // n*cellW + (n-1)*gap == cw.
            let cellX = CGFloat(i) * (cellW + gap)
            switch content {
            case .cards:
                let w = min(48, cellW), h = w * 67 / 48
                btn.frame = CGRect(x: cellX + (cellW - w) / 2, y: (max(67, rowH) - h) / 2, width: w, height: h)
                rowH = max(rowH, h)
            case .stickers:
                let w = min(64, cellW), h: CGFloat = 96
                btn.frame = CGRect(x: cellX + (cellW - w) / 2, y: 0, width: w, height: h)
                if let iv = btn.viewWithTag(101) { iv.frame = CGRect(x: (w - 46) / 2, y: 18, width: 46, height: 46) }
                if let nl = btn.viewWithTag(102) { nl.frame = CGRect(x: 2, y: 66, width: w - 4, height: 26) }
                if let cap = btn.viewWithTag(103) {
                    // Bottom edge 2pt over the chip's drawn top (ItemArt contract).
                    cap.center = CGPoint(x: w / 2, y: 18 - 2 - cap.bounds.height / 2)
                }
                rowH = max(rowH, h)
            }
        }
        // Re-centre card buttons vertically once the final row height is known.
        if case .cards = content {
            for btn in itemButtons { btn.frame.origin.y = (rowH - btn.frame.height) / 2 }
        }
        itemsRow.frame = CGRect(x: m, y: y, width: cw, height: rowH)
        // The row breathes on BOTH sides — the cards read centred between the
        // title and the confirm button, never crowding it (v5.81).
        y += rowH + 18

        // `.pack-msg` keeps its min-height even when empty — the panel never moves.
        msgLabel.frame = CGRect(x: m, y: y, width: cw, height: max(14, measure(msgLabel, width: cw)))
        y += msgLabel.frame.height + 14

        if !deckButton.isHidden {
            deckButton.frame = CGRect(x: m, y: y, width: cw, height: 34)
            // The little cream pip leading the label (web `.ico-slot`).
            let tw = deckButton.attributedTitle(for: .normal)?.size().width ?? 0
            deckDot.frame = CGRect(x: (cw - tw) / 2 - 12, y: (34 - 5) / 2, width: 5, height: 5)
            y += 34 + 10
        }
        confirmButton.frame = CGRect(x: m, y: y, width: cw, height: 40)
        y += 40 + 8
        if !skipButton.isHidden {
            skipButton.frame = CGRect(x: m, y: y, width: cw, height: 30)
            y += 30
        }
        let panelH = y + 16
        panel.frame = CGRect(x: (b.width - pw) / 2, y: (b.height - panelH) / 2, width: pw, height: panelH)
        showRim.frame = CGRect(x: 0, y: 0, width: pw, height: 4)

        // `.item-help.pack-item-help`: fixed 162px, bottom-anchored, min(92vw, 340px).
        let iw = min(340, b.width * 0.92)
        infoPanel.frame = CGRect(x: (b.width - iw) / 2,
                                 y: b.height - view.safeAreaInsets.bottom - 14 - 162,
                                 width: iw, height: 162)
        // The content scrolls INSIDE the fixed shell (stable containers): the
        // view takes its measured height, the scroll clips nothing.
        let contentW = iw - 28
        infoScroll.frame = CGRect(x: 14, y: 10, width: contentW, height: 162 - 20)
        let fit = infoView.sizeThatFits(CGSize(width: contentW, height: .greatestFiniteMagnitude))
        infoView.frame = CGRect(x: 0, y: 0, width: contentW, height: fit.height)
        infoScroll.contentSize = CGSize(width: contentW, height: fit.height)
        infoScroll.setContentOffset(.zero, animated: false)
        crt.frame = b
        prompt.frame = b
    }

    private func measure(_ l: UILabel, width: CGFloat) -> CGFloat {
        guard let t = l.attributedText, t.length > 0 else { return 0 }
        return ceil(t.boundingRect(with: CGSize(width: width, height: 200),
                                   options: .usesLineFragmentOrigin, context: nil).height)
    }

    private func refreshChrome() {
        switch mode {
        case .show:
            // Web map reveal (index.html:29430-29444): "N card(s) added",
            // "Add to deck" always enabled, no Skip, no deck aid, phosphor rim.
            showRim.isHidden = false
            let m = count
            titleLabel.attributedText = CRTKit.attributed(
                "\(m) card\(m > 1 ? "s" : "") added", size: 14,
                color: CRT.phosphor, display: true, glow: true)
            // No subline — it overlapped the revealed cards and duplicated
            // what "Add to deck" already says.
            msgLabel.attributedText = nil
            deckButton.isHidden = true
            confirmButton.setTitle("Add to deck")
            confirmButton.accessibilityLabel = "CONTINUE"   // legacy a11y (UI tests)
            confirmButton.isEnabled = true
            skipButton.isHidden = true
        case .pick(let keep):
            // Web pick (index.html:29472-29475): "Pick N noun(s) to keep", EMPTY
            // msg line, "Confirm" disabled until exactly `keep` are chosen.
            showRim.isHidden = true
            let noun: String
            switch content {
            case .cards: noun = "card"
            case .stickers: noun = "sticker"
            }
            titleLabel.attributedText = CRTKit.attributed(
                "Pick \(keep) \(noun)\(keep > 1 ? "s" : "") to keep", size: 14,
                color: CRT.phosphor, display: true, glow: true)
            msgLabel.attributedText = nil
            if case .cards = content { deckButton.isHidden = false } else { deckButton.isHidden = true }
            confirmButton.setTitle("Confirm")
            // Legacy dynamic a11y preserved under the web's static visual.
            confirmButton.accessibilityLabel = keep == 1 ? "TAKE" : "TAKE \(chosen.count)/\(keep)"
            confirmButton.isEnabled = chosen.count == keep
            skipButton.isHidden = false
        }
        // `.pack-item.chosen`: the phosphor keep-outline.
        for (i, b) in itemButtons.enumerated() {
            let sel = chosen.contains(i)
            b.layer.borderWidth = sel ? CRT.px : (b.backgroundColor != nil ? 1 : 0)
            b.layer.borderColor = sel ? CRT.phosphor.cgColor : CRT.ink.cgColor
        }
    }

    @objc private func itemTapped(_ b: UIButton) {
        let i = b.tag
        if case .pick(let keep) = mode {
            // Web packSelect: tap toggles; single-pick replaces; multi adds to
            // the cap. A SELECT shows the info slot; a DESELECT hides it.
            if let at = chosen.firstIndex(of: i) {
                chosen.remove(at: at)
                infoPanel.isHidden = true
                // A deselect stays quiet — silence is the un-pick.
            } else {
                if keep == 1 { chosen = [i] }
                else if chosen.count < keep { chosen.append(i) }
                if chosen.contains(i) {
                    Sound.shared.tap()
                    showInfo(i)
                }
            }
        } else {
            // Reveal-only (map pack): tap = info (web `data-info`).
            Sound.shared.tap()
            showInfo(i)
        }
        refreshChrome()
    }

    @objc private func backgroundTapped(_ g: UITapGestureRecognizer) {
        let p = g.location(in: view)
        if infoPanel.frame.contains(p) { return }
        for b in itemButtons where b.convert(b.bounds, to: view).contains(p) { return }
        infoPanel.isHidden = true
    }

    private func showInfo(_ i: Int) {
        // THE SHARED CARD-INFO GRAMMAR (v6.74 — see CardInfoView): the subject
        // LARGEST on top (rank+suit / ★ Joker / ∅ Purge / the sticker's own
        // name), then per sticker its bold colored name + registry description.
        switch content {
        case .cards(let cards):
            let c = cards[i]
            if c.joker {
                // items.js has NO joker entry (the joker isn't a sellable
                // item) — the web itself hardcodes this copy
                // (index.html:29565), so the native mirrors it verbatim.
                infoView.show(title: "★ Joker", body: "A wild card. Any guess it's part of is SAFE: when it's drawn and placed on a pile, and when you guess on top of it (higher, lower, or same), it can never be wrong. Call SAME with a Joker involved and it counts as a true Same: banks the Same Charge AND fires your equipped Same-Power.")
            } else if c.blank {
                // Registry-derived (items.js store.removal), price line
                // dropped (v6.86): a pack Blank is FREE — the store's
                // climbing-price sentence doesn't apply here.
                infoView.show(title: "∅ Purge",
                              body: GameData.shared.items.store.removal.description
                                  .components(separatedBy: ". ").first ?? "")
            } else {
                infoView.show(title: CardInfo.title(for: c),
                              body: c.stickers.isEmpty ? "A plain card, no stickers." : nil,
                              rows: CardInfo.rows(for: c))
            }
        case .stickers(let ids):
            if let t = GameData.shared.stickerTypes.get(ids[i]) {
                // A lone sticker IS the subject: its name takes the title slot
                // in its canonical colours — gold, suit-red for a curse (v6.72).
                infoView.show(title: t.label,
                              titleColor: t.cursed ? CRT.suitRed : CRT.gold,
                              body: t.description)
            }
        }
        infoPanel.isHidden = false
        view.setNeedsLayout()
    }

    @objc private func deckTapped() {
        present(DeckInspectViewController(campaign: campaign), animated: false)
    }

    private func confirmTapped() {
        guard confirmButton.isEnabled else { return }
        // .show keeps `chosen` empty for display; the completion contract
        // still reports every granted index.
        let picked = chosen.isEmpty && isShow ? Array(0..<count) : chosen
        // The completion runs AFTER this modal is fully gone. It typically
        // presents the next one (the sticker's card picker / the pack-keep
        // walk), and presenting on a controller whose dismissal is still in
        // flight is silently dropped by UIKit — which is exactly how a picked
        // sticker ended up with nowhere to go.
        let done = completion
        dismiss(animated: false) { done(picked) }
    }

    private var isShow: Bool { if case .show = mode { return true }; return false }

    /// Autopilot: pick the first `keep` items and confirm (Continue in .show).
    func autopilotConfirm() {
        if case .pick(let keep) = mode, chosen.count < keep {
            chosen = Array(0..<min(keep, count))
            refreshChrome()
        }
        confirmTapped()
    }

    @objc private func skipTapped() {
        // Use-or-confirmed-skip: "take nothing" forfeits the pack, so it
        // confirms through the shared bottom prompt bar like every other
        // destructive choice — never a one-tap dismiss.
        prompt.show("Skip this pack?", actions: [
            .init("Back", role: .plain) { [weak self] in self?.prompt.hide() },
            .init("Skip", role: .danger) { [weak self] in self?.confirmSkip() },
        ]) { [weak self] in self?.prompt.hide() }
    }

    private func confirmSkip() {
        prompt.hide()
        dismiss(animated: false)
        completion([])
    }
}
