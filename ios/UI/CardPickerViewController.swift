import UIKit
import GameCore

/// The card picker modal — the web's #stickerApplyModal, all five modes:
///   .applySticker(typeId)      — apply an owned sticker (inventory)
///   .buySticker(slot, typeId)  — store buy: place-then-confirm-THEN-pay
///   .removal(paid:)            — pick a card to permanently remove
///   .strip                     — mystery Cleanse: pick a stickered card
///   .swap(trayIndex)           — swap a held pack card into the deck
///
/// A BOTTOM SHEET over the dimmed store/map (the web's .deck-modal): header
/// row (title + Skip + ✕), the item row (icon + name + registry description),
/// the deck-composition strip (rank histogram + legend + BY SUIT counts), the
/// hint line, then the scrollable ascending card grid. Confirm rides the
/// shared prompt bar.
public final class CardPickerViewController: UIViewController {

    public enum Mode {
        case applySticker(typeId: String)
        case buySticker(slot: Int, typeId: String)
        case removal(price: Int)
        case strip
        case swap(trayIndex: Int, step: String?)
    }

    private let campaign: CampaignState
    private let mode: Mode
    /// (completedCardId or nil on skip/close)
    private let completion: (Int?) -> Void
    /// Forced flows (mystery strip/removal) hide ✕ — no dismiss without choosing.
    public var forced = false
    /// Show a Skip button (pack-keep walk: decline this card).
    public var showsSkip = false

    // Sheet chrome.
    private let scrim = UIControl()
    private let sheetShadow = UIView()
    private let sheet = PixelPanelView(face: CRT.feltMid, border: CRT.ink, shadowOffsetPx: 0)
    private let headerLabel = UILabel()
    private let closeButton = PixelButtonView("✕", role: .plain, fontSize: 16)
    private let skipButton = PixelButtonView("SKIP", role: .plain, fontSize: 14)
    // Item row.
    private let bannerIcon = UIImageView()
    private let bannerName = UILabel()
    private let bannerDesc = UILabel()
    // Composition strip.
    private let histBars = UIView()
    private let legendRow = UIView()
    private let suitRow = UIView()
    private let hintLabel = UILabel()
    // Card grid.
    private let scroll = UIScrollView()
    private let grid = UIView()
    private let prompt = PromptBar()
    private let crt = CRTOverlayUIView()
    private var cardViews: [Int: UIButton] = [:]
    private var selectedId: Int?
    private var busy = false
    /// Width the composition strip was last built for (rebuild guard).
    private var histWidth: CGFloat = -1

    /// The web strip picker is FORCED: no ✕, no backdrop dismiss — the only
    /// exit is a confirmed strip (no-stickers decks never see the modal).
    private var effectivelyForced: Bool {
        if case .strip = mode { return true }
        return forced
    }

    public init(campaign: CampaignState, mode: Mode, completion: @escaping (Int?) -> Void) {
        self.campaign = campaign
        self.mode = mode
        self.completion = completion
        super.init(nibName: nil, bundle: nil)
        // Bottom sheet over the dimmed screen below — the presenter stays put.
        modalPresentationStyle = .overFullScreen
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    public override var prefersStatusBarHidden: Bool { true }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        // The web .deck-modal scrim: flat black at 0.7, tap = cancel (unless forced).
        scrim.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        scrim.addTarget(self, action: #selector(scrimTapped), for: .touchUpInside)
        view.addSubview(scrim)

        // box-shadow: 0 -4px 0 shadow — the 4px strip above the sheet's top edge.
        sheetShadow.backgroundColor = CRT.shadow
        view.addSubview(sheetShadow)
        view.addSubview(sheet)

        headerLabel.attributedText = CRTKit.attributed(headerText(), size: 15, color: CRT.cardFace)
        sheet.addSubview(headerLabel)

        closeButton.onTap = { [weak self] in self?.closeTapped() }
        closeButton.isHidden = effectivelyForced
        sheet.addSubview(closeButton)
        skipButton.onTap = { [weak self] in self?.skipTapped() }
        skipButton.isHidden = !showsSkip
        sheet.addSubview(skipButton)

        bannerIcon.contentMode = .scaleAspectFit
        bannerIcon.layer.magnificationFilter = .nearest
        sheet.addSubview(bannerIcon)
        bannerName.numberOfLines = 1
        sheet.addSubview(bannerName)
        bannerDesc.numberOfLines = 0
        sheet.addSubview(bannerDesc)
        configureBanner()

        sheet.addSubview(histBars)
        sheet.addSubview(legendRow)
        sheet.addSubview(suitRow)

        hintLabel.numberOfLines = 0
        hintLabel.attributedText = CRTKit.attributed(hintText(), size: 12, color: CRT.muted)
        sheet.addSubview(hintLabel)

        scroll.alwaysBounceVertical = true
        sheet.addSubview(scroll)
        scroll.addSubview(grid)

        crt.isUserInteractionEnabled = false
        view.addSubview(crt)
        view.addSubview(prompt)

        renderGrid()
    }

    // MARK: - Layout

    /// Grid metrics: a fixed 6-column mini-card grid (the web .sa-cards),
    /// cards shrinking only if the sheet is too narrow for 6×50pt.
    private func gridMetrics(width w: CGFloat) -> (cw: CGFloat, ch: CGFloat, cols: Int) {
        let cw = min(50, floor((w - 5 * 8) / 6))
        return (cw, round(cw * 82 / 50), 6)
    }

    private func gridContentHeight(width w: CGFloat) -> CGFloat {
        let m = gridMetrics(width: w)
        let rows = (deck.count + m.cols - 1) / m.cols
        return 16 + CGFloat(rows) * (m.ch + 6)
    }

    private func descHeight(width w: CGFloat) -> CGFloat {
        guard let s = bannerDesc.attributedText else { return 16 }
        return ceil(s.boundingRect(with: CGSize(width: w, height: 120),
                                   options: .usesLineFragmentOrigin, context: nil).height)
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let b = view.bounds
        scrim.frame = b

        let sheetW = min(b.width, 460)   // web: width min(100%, 460px)
        let sheetX = (b.width - sheetW) / 2
        let pad: CGFloat = 16
        let innerW = sheetW - pad * 2
        let descH = descHeight(width: innerW)

        // Fixed content above the scrollable grid (bars 64 + ticks 16 = 80).
        let fixedH: CGFloat = 112 + descH + 8 + 80 + 5 + 18 + 8 + 22 + 8 + 16 + 8
        let gridH = min(gridContentHeight(width: innerW), b.height * 0.5)   // web: .sa-cards max-height 50vh
        var sheetH = fixedH + gridH + 2
        sheetH = min(sheetH, b.height * 0.8)   // web: .deck-modal-panel max-height 80vh

        // The sheet runs 4pt past the bottom edge so its bottom border/shadow
        // stay offscreen (the web panel has no bottom border).
        sheet.frame = CGRect(x: sheetX, y: b.height - sheetH, width: sheetW, height: sheetH + 4)
        sheetShadow.frame = CGRect(x: sheetX, y: sheet.frame.minY - 4, width: sheetW, height: 4)

        headerLabel.frame = CGRect(x: pad, y: 14, width: innerW - 120, height: 22)
        closeButton.frame = CGRect(x: sheetW - pad - 32, y: 12, width: 32, height: 30)
        skipButton.frame = CGRect(x: sheetW - pad - 32 - 8 - 64, y: 12, width: 64, height: 30)

        bannerIcon.frame = CGRect(x: pad, y: 50, width: 44, height: 56)
        bannerName.frame = CGRect(x: pad + 54, y: 50, width: innerW - 54, height: 56)
        bannerDesc.frame = CGRect(x: pad, y: 112, width: innerW, height: descH)

        var y: CGFloat = 112 + descH + 8
        histBars.frame = CGRect(x: pad, y: y, width: innerW, height: 80)
        y += 80 + 5
        legendRow.frame = CGRect(x: pad, y: y, width: innerW, height: 18)
        y += 18 + 8
        suitRow.frame = CGRect(x: pad, y: y, width: innerW, height: 22)
        y += 22 + 8
        hintLabel.frame = CGRect(x: pad, y: y, width: innerW, height: 16)
        y += 16 + 8
        scroll.frame = CGRect(x: pad, y: y, width: innerW, height: sheetH - y)

        crt.frame = b
        prompt.frame = b
        // The strip builds off the laid-out widths — once per real width.
        if histWidth != innerW {
            histWidth = innerW
            buildHistogram()
        }
        layoutGrid()
    }

    // MARK: - Copy (web-verbatim)

    private func headerText() -> String {
        switch mode {
        case .applySticker(let t):
            // Owned sticker (post-deal gain): "Apply <label>".
            return "Apply " + (GameData.shared.stickerTypes.get(t)?.label ?? "Sticker")
        case .buySticker(_, let t):
            // Store buy (place-then-pay): "Place <label>".
            return "Place " + (GameData.shared.stickerTypes.get(t)?.label ?? "Sticker")
        case .removal: return "Removal"
        case .strip: return "Cleanse"
        case .swap(let trayIndex, let step):
            let tray = campaign.getPackTray()
            let name = trayIndex < tray.count ? trayCardName(tray[trayIndex]) : ""
            return "Swap in \(name)" + (step ?? "")
        }
    }

    private func trayCardName(_ c: CardSpec) -> String {
        c.joker ? "★ Joker" : (c.blank ? "∅ Removal" : "\(rankLabel(c)) \(c.suit)")
    }

    private func setBanner(name: String, desc: String) {
        bannerName.attributedText = CRTKit.attributed(name, size: 15, color: CRT.phosphor,
                                                      display: true, glow: true)
        bannerDesc.attributedText = CRTKit.attributed(desc, size: 12, color: CRT.muted)
    }

    private func configureBanner() {
        switch mode {
        case .applySticker(let t), .buySticker(_, let t):
            if let def = GameData.shared.stickerTypes.get(t) {
                bannerIcon.image = ItemArt.sticker(def)
                setBanner(name: def.label, desc: def.description)
            }
        case .removal(let price):
            bannerIcon.image = ItemArt.removal()
            setBanner(name: "∅ Removal",
                      desc: price > 0
                        ? "Pick a card to permanently remove (◉ \(price)). The slot stays."
                        : "Pick a card to permanently remove from your deck.")
        case .strip:
            bannerIcon.image = ItemArt.removal()
            setBanner(name: "Cleanse",
                      desc: "Pick a card — one random sticker is stripped from it, free. The stripped sticker is destroyed.")
        case .swap(let trayIndex, _):
            let tray = campaign.getPackTray()
            if trayIndex < tray.count {
                let c = tray[trayIndex]
                bannerIcon.image = CardArt.image(CardArt.Face(c), scale: .half)
                if c.blank {
                    setBanner(name: "∅ Removal",
                              desc: "Pick a card to permanently remove from your deck.")
                } else {
                    setBanner(name: trayCardName(c),
                              desc: "Pick a card to replace with this one (the old card is removed; deck stays 52).")
                }
            }
        }
    }

    private func hintText() -> String {
        switch mode {
        case .applySticker(let t), .buySticker(_, let t):
            let label = GameData.shared.stickerTypes.get(t)?.label ?? "this sticker"
            return "Tap a card to apply \(label) to it."
        case .removal: return "Tap the card to remove."
        case .strip: return "Tap a stickered card — you must strip one to continue."
        case .swap: return showsSkip ? "Tap the card to replace — or Skip to decline this card." : "Tap the card to replace."
        }
    }

    private func rankLabel(_ c: CardSpec) -> String {
        DeckManager.ranks.first { $0.value == c.currentRank }?.label ?? "\(c.currentRank)"
    }

    private func eligible(_ c: CardSpec) -> Bool {
        switch mode {
        case .applySticker(let t), .buySticker(_, let t): return campaign.canApplySticker(c, t)
        case .removal: return true
        case .strip: return !c.stickers.isEmpty
        case .swap: return true
        }
    }

    // MARK: - Composition strip (histogram + legend + BY SUIT)

    /// The picker's composition view (the web's DeckInspector.renderCompositionInto):
    /// opened from the store/map, never mid-deal, so every card is "remaining"
    /// (the web's not-playing rule: remaining == full). Counts only, live from
    /// the campaign deck — never hardcoded.
    private func buildHistogram() {
        histBars.subviews.forEach { $0.removeFromSuperview() }
        legendRow.subviews.forEach { $0.removeFromSuperview() }
        suitRow.subviews.forEach { $0.removeFromSuperview() }

        var counts: [Int: Int] = [:]
        var suitCounts: [String: Int] = [:]
        for c in deck where !c.joker && !c.blank {
            counts[c.currentRank, default: 0] += 1
            suitCounts[c.suit, default: 0] += 1
        }
        let scaleMax = max(1, counts.values.max() ?? 1)

        // Rank bars 2..A: feltDeep track = total this stage, cardFace fill = remaining.
        let barH: CGFloat = 64
        let barW = (histBars.bounds.width - CGFloat(DeckManager.ranks.count - 1) * 3)
            / CGFloat(DeckManager.ranks.count)
        for (i, r) in DeckManager.ranks.enumerated() {
            let n = counts[r.value] ?? 0
            let x = CGFloat(i) * (barW + 3)
            if n > 0 {
                let totalH = max(4, CGFloat(n) / CGFloat(scaleMax) * barH)
                let track = UIView(frame: CGRect(x: x, y: barH - totalH, width: barW, height: totalH))
                track.backgroundColor = CRT.feltDeep
                histBars.addSubview(track)
                // remaining == total here, so the fill covers the track.
                let fill = UIView(frame: track.bounds)
                fill.backgroundColor = CRT.cardFace
                track.addSubview(fill)
            }
            let tick = CRTKit.label(r.label, size: 12, color: CRT.muted)
            tick.textAlignment = .center
            tick.frame = CGRect(x: x, y: barH + 2, width: barW, height: 14)
            histBars.addSubview(tick)
        }

        // Legend: cream swatch "remaining", deep swatch "total this stage".
        let remText = CRTKit.attributed("remaining", size: 12, color: CRT.muted)
        let allText = CRTKit.attributed("total this stage", size: 12, color: CRT.muted)
        let remW = ceil(remText.size().width), allW = ceil(allText.size().width)
        let totalW = 9 + 5 + remW + 8 + 9 + 5 + allW
        var lx = (legendRow.bounds.width - totalW) / 2
        func swatch(_ color: UIColor, _ y: CGFloat) -> UIView {
            let v = UIView(frame: CGRect(x: lx, y: y, width: 9, height: 9))
            v.backgroundColor = color
            return v
        }
        legendRow.addSubview(swatch(CRT.cardFace, 4)); lx += 9 + 5
        let remL = UILabel(frame: CGRect(x: lx, y: 0, width: remW, height: 18))
        remL.attributedText = remText
        legendRow.addSubview(remL); lx += remW + 8
        legendRow.addSubview(swatch(CRT.feltDeep, 4)); lx += 9 + 5
        let allL = UILabel(frame: CGRect(x: lx, y: 0, width: allW, height: 18))
        allL.attributedText = allText
        legendRow.addSubview(allL)

        // BY SUIT: feltDeep chips, suit-entry order (♦ ♥ ♣ ♠), red suits red.
        // remaining == total here, so each chip reads N/N.
        let bySuitText = CRTKit.attributed("BY SUIT", size: 12, color: CRT.muted)
        let bySuitW = ceil(bySuitText.size().width)
        var chips: [(label: UILabel, w: CGFloat)] = []
        for s in DeckManager.suits {
            let n = suitCounts[s.symbol] ?? 0
            let str = NSMutableAttributedString()
            str.append(CRTKit.attributed(s.symbol, size: 14,
                                         color: s.red ? CRT.suitRed : CRT.cardFace))
            str.append(CRTKit.attributed(" \(n)", size: 13, color: CRT.cardFace))
            str.append(CRTKit.attributed("/\(n)", size: 12, color: CRT.muted))
            let l = UILabel()
            l.attributedText = str
            chips.append((l, ceil(str.size().width) + 18))   // 9px padding each side
        }
        let chipsW = chips.reduce(0) { $0 + $1.w } + CGFloat(chips.count - 1) * 6
        var sx = (suitRow.bounds.width - bySuitW - 2 - 6 - chipsW) / 2
        let bySuitL = UILabel(frame: CGRect(x: sx, y: 0, width: bySuitW, height: 22))
        bySuitL.attributedText = bySuitText
        suitRow.addSubview(bySuitL)
        sx += bySuitW + 2 + 6
        for (l, w) in chips {
            let chip = UIView(frame: CGRect(x: sx, y: 0, width: w, height: 22))
            chip.backgroundColor = CRT.feltDeep
            l.frame = CGRect(x: 9, y: 0, width: w - 18, height: 22)
            chip.addSubview(l)
            suitRow.addSubview(chip)
            sx += w + 6
        }
    }

    // MARK: - Grid

    private var deck: [CardSpec] = []

    private func renderGrid() {
        // Ascending 2→A, ties by the web picker's SUIT_ORDER (♠ ♥ ♣ ♦).
        deck = campaign.getRunDeck().sorted { a, b in
            if a.currentRank != b.currentRank { return a.currentRank < b.currentRank }
            let order: [String: Int] = ["♠": 0, "♥": 1, "♣": 2, "♦": 3]
            return (order[a.suit] ?? 4) < (order[b.suit] ?? 4)
        }
        grid.subviews.forEach { $0.removeFromSuperview() }
        cardViews.removeAll()
        for c in deck {
            let b = UIButton(type: .custom)
            b.setImage(CardArt.image(CardArt.Face(c), scale: .half), for: .normal)
            b.imageView?.layer.magnificationFilter = .nearest
            b.adjustsImageWhenHighlighted = false
            b.tag = c.id
            b.addTarget(self, action: #selector(cardTapped(_:)), for: .touchUpInside)
            let ok = eligible(c)
            b.alpha = ok ? 1 : 0.35
            b.isEnabled = ok
            // Sticker count pips under the card.
            if !c.stickers.isEmpty {
                let pip = CRTKit.label(String(repeating: "▪", count: min(4, c.stickers.count)),
                                       size: 12, color: CRT.gold)
                pip.frame = CGRect(x: 0, y: 68, width: 50, height: 12)
                pip.textAlignment = .center
                b.addSubview(pip)
            }
            grid.addSubview(b)
            cardViews[c.id] = b
        }
        layoutGrid()
    }

    private func layoutGrid() {
        let gw = scroll.bounds.width
        guard gw > 0 else { return }
        let m = gridMetrics(width: gw)
        let rowW = CGFloat(m.cols) * (m.cw + 8) - 8
        let x0 = (gw - rowW) / 2
        for (i, c) in deck.enumerated() {
            guard let b = cardViews[c.id] else { continue }
            let row = i / m.cols, col = i % m.cols
            b.frame = CGRect(x: x0 + CGFloat(col) * (m.cw + 8), y: 8 + CGFloat(row) * (m.ch + 6),
                             width: m.cw, height: m.ch)
        }
        let rows = (deck.count + m.cols - 1) / m.cols
        let h = 16 + CGFloat(rows) * (m.ch + 6)
        grid.frame = CGRect(x: 0, y: 0, width: gw, height: h)
        scroll.contentSize = CGSize(width: gw,
                                    height: h + (view.safeAreaInsets.bottom + 20))
    }

    // MARK: - Selection + confirm

    /// Card name as the web prompt bars print it: "2 ♥", "★ Joker".
    private func cardName(_ c: CardSpec) -> String {
        c.joker ? "★ Joker" : "\(rankLabel(c)) \(c.suit)"
    }

    @objc private func cardTapped(_ b: UIButton) {
        guard !busy else { return }
        let id = b.tag
        guard let card = deck.first(where: { $0.id == id }) else { return }
        selectedId = id
        highlight(id)
        let name = cardName(card)
        let stickerWarn = card.stickers.isEmpty ? "" :
            " It carries \(card.stickers.count) sticker\(card.stickers.count > 1 ? "s" : ""), destroyed forever."
        switch mode {
        case .applySticker(let t), .buySticker(_, let t):
            let label = GameData.shared.stickerTypes.get(t)?.label ?? t
            var text = "Add \(label) to \(name)?"
            var applyLabel = "Apply"
            if case .buySticker = mode {
                // When buying, the confirm is also the PURCHASE — name it so.
                text += " (◉ \(Int(campaign.priceOf(t))))"
                applyLabel = "Buy & Apply"
            }
            prompt.show(text, actions: [
                .init("Back", role: .plain) { [weak self] in self?.cancelChoice() },
                .init(applyLabel, role: .cta) { [weak self] in self?.confirm() },
            ]) { [weak self] in self?.cancelChoice() }
        case .removal(let price):
            var text = "Permanently REMOVE \(name) from your deck?"
            if price > 0 { text += " (◉ \(price))" }
            text += stickerWarn
            prompt.show(text, actions: [
                .init("Back", role: .plain) { [weak self] in self?.cancelChoice() },
                .init("Remove", role: .danger) { [weak self] in self?.confirm() },
            ]) { [weak self] in self?.cancelChoice() }
        case .strip:
            prompt.show("Strip ONE random sticker from \(name)? It carries \(card.stickers.count) — the stripped one is destroyed.",
                        actions: [
                .init("Back", role: .plain) { [weak self] in self?.cancelChoice() },
                .init("Strip", role: .cta) { [weak self] in self?.confirm() },
            ]) { [weak self] in self?.cancelChoice() }
        case .swap(let trayIndex, _):
            let tray = campaign.getPackTray()
            guard trayIndex < tray.count else { return }
            let tc = tray[trayIndex]
            if tc.blank {
                prompt.show("Permanently REMOVE \(name) from your deck?\(stickerWarn)", actions: [
                    .init("Back", role: .plain) { [weak self] in self?.cancelChoice() },
                    .init("Remove", role: .danger) { [weak self] in self?.confirm() },
                ]) { [weak self] in self?.cancelChoice() }
            } else {
                prompt.show("Replace \(name) with \(cardName(tc))?", actions: [
                    .init("Back", role: .plain) { [weak self] in self?.cancelChoice() },
                    .init("Swap", role: .danger) { [weak self] in self?.confirm() },
                ]) { [weak self] in self?.cancelChoice() }
            }
        }
    }

    private func highlight(_ id: Int?) {
        for (cid, b) in cardViews {
            b.layer.borderWidth = cid == id ? 3 : 0
            b.layer.borderColor = CRT.phosphor.cgColor
        }
    }

    private func cancelChoice() {
        selectedId = nil
        highlight(nil)
        prompt.hide()
    }

    private func confirm() {
        guard let id = selectedId, !busy else { return }
        prompt.hide()
        busy = true
        var ok = false
        switch mode {
        case .applySticker(let t):
            // applySticker consumes the inventory copy itself.
            ok = campaign.applySticker(id, t)
        case .buySticker(let slot, let t):
            // Place-then-confirm-THEN-pay: buyOfferedSticker charges + banks
            // one to inventory; applySticker consumes that one.
            if campaign.buyOfferedSticker(slot) {
                ok = campaign.applySticker(id, t)
            }
        case .removal(let price):
            ok = price > 0 ? campaign.buyRemoval(id) : campaign.removeDeckCard(id)
        case .strip:
            ok = campaign.removeRandomStickerFrom(id) != nil
        case .swap(let trayIndex, _):
            ok = campaign.replaceDeckCard(id, trayIndex: trayIndex) != nil
        }
        guard ok else { busy = false; return }
        switch mode {
        case .applySticker, .buySticker: Sound.shared.sticker()
        default: Sound.shared.purchase()
        }
        PersistenceHolder.shared?.checkpoint(campaign)
        // The chosen card plays its web animation, then the picker closes.
        let cardBtn = cardViews[id]
        switch mode {
        case .applySticker, .buySticker:
            flyStickerThenPop(onto: cardBtn, cardId: id)
        case .removal, .swap, .strip:
            crumpleThenClose(cardBtn, cardId: id)
        }
    }

    /// Web `flyStickerToCard` + `saFlash`/`saSpark`: the banner's sticker chip
    /// flies to the chosen card (0.45s, straight line, shrink to 0.55), the
    /// card repaints with its new badge and pops (1 → 1.22 → 1.08 → 1 over
    /// 0.85s) with a rising ✨, and the picker closes 0.4s after landing.
    private func flyStickerThenPop(onto btn: UIButton?, cardId id: Int) {
        guard let btn else { close(after: 0.4, cardId: id); return }
        let start = bannerIcon.convert(bannerIcon.bounds, to: view)
        let ghost = UIImageView(image: bannerIcon.image)
        ghost.frame = start
        ghost.contentMode = .scaleAspectFit
        ghost.layer.magnificationFilter = .nearest
        view.addSubview(ghost)
        let target = btn.convert(btn.bounds, to: view)
        let fly = UIViewPropertyAnimator(duration: 0.45,
                                         controlPoint1: CGPoint(x: 0.3, y: 0.7),
                                         controlPoint2: CGPoint(x: 0.3, y: 1)) {
            ghost.center = CGPoint(x: target.midX, y: target.midY)
            ghost.transform = CGAffineTransform(scaleX: 0.55, y: 0.55)
            ghost.alpha = 0.85
        }
        fly.addCompletion { [weak self] _ in
            guard let self else { return }
            ghost.removeFromSuperview()
            self.repaintCard(id)
            self.popCard(btn)
            self.close(after: 0.4, cardId: id)
        }
        fly.startAnimation()
    }

    /// Re-show the card with its just-applied sticker (fresh face + pips) so
    /// the player SEES the sticker land before the picker drops.
    private func repaintCard(_ id: Int) {
        guard let btn = cardViews[id],
              let fresh = campaign.getRunDeck().first(where: { $0.id == id }) else { return }
        btn.setImage(CardArt.image(CardArt.Face(fresh), scale: .half), for: .normal)
        btn.subviews.filter { $0 is UILabel }.forEach { $0.removeFromSuperview() }
        if !fresh.stickers.isEmpty {
            let pip = CRTKit.label(String(repeating: "▪", count: min(4, fresh.stickers.count)),
                                   size: 12, color: CRT.gold)
            pip.frame = CGRect(x: 0, y: 68, width: 50, height: 12)
            pip.textAlignment = .center
            btn.addSubview(pip)
        }
    }

    /// `saFlash` + `saSpark`: the landing pop and a drifting sparkle.
    private func popCard(_ btn: UIButton) {
        UIView.animateKeyframes(withDuration: 0.85, delay: 0, options: [.calculationModeCubic]) {
            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.22) {
                btn.transform = CGAffineTransform(scaleX: 1.22, y: 1.22)
            }
            UIView.addKeyframe(withRelativeStartTime: 0.22, relativeDuration: 0.33) {
                btn.transform = CGAffineTransform(scaleX: 1.08, y: 1.08)
            }
            UIView.addKeyframe(withRelativeStartTime: 0.55, relativeDuration: 0.45) {
                btn.transform = .identity
            }
        }
        let spark = CRTKit.label("✨", size: 18, color: CRT.gold)
        spark.frame = CGRect(x: btn.bounds.width - 18, y: -6, width: 24, height: 24)
        btn.addSubview(spark)
        UIView.animate(withDuration: 0.85, delay: 0, options: [.curveEaseOut]) {
            spark.transform = CGAffineTransform(translationX: 4, y: -20)
            spark.alpha = 0
        } completion: { _ in spark.removeFromSuperview() }
    }

    /// Web `saRemove`: a brief grow+tilt, then the crumple — scale 0.2,
    /// rotate −10°, fade — over 0.72s, then close.
    private func crumpleThenClose(_ btn: UIButton?, cardId id: Int) {
        UIView.animateKeyframes(withDuration: 0.72, delay: 0, options: [.calculationModeCubic]) {
            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.28) {
                btn?.transform = CGAffineTransform(scaleX: 1.12, y: 1.12).rotated(by: .pi / 60)
            }
            UIView.addKeyframe(withRelativeStartTime: 0.28, relativeDuration: 0.72) {
                btn?.transform = CGAffineTransform(scaleX: 0.2, y: 0.2).rotated(by: -.pi / 18)
                btn?.alpha = 0
            }
        } completion: { [weak self] _ in
            self?.close(after: 0, cardId: id)
        }
    }

    private func close(after delay: TimeInterval, cardId id: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.dismiss(animated: false)
            self.completion(id)
        }
    }

    private func closeTapped() {
        guard !busy else { return }
        dismiss(animated: false)
        completion(nil)
    }

    /// Backdrop tap = cancel, exactly like ✕ (never when forced).
    @objc private func scrimTapped() {
        guard !effectivelyForced, !busy, !prompt.isShowing else { return }
        closeTapped()
    }

    /// Autopilot: select the first eligible card and confirm straight through.
    func autopilotConfirm() {
        guard !busy else { return }
        guard let card = deck.first(where: { eligible($0) }) else {
            dismiss(animated: false)
            completion(nil)
            return
        }
        selectedId = card.id
        prompt.hide()
        confirm()
    }

    private func skipTapped() {
        guard !busy, !prompt.isShowing else { return }
        // Use-or-confirmed-skip: declining a held card is destructive (no
        // refund), so it rides the shared bottom prompt bar like every other
        // confirmation — never a one-tap dismiss.
        prompt.show("Skip this card?", actions: [
            .init("Back", role: .plain) { [weak self] in self?.prompt.hide() },
            .init("Skip", role: .danger) { [weak self] in self?.confirmSkip() },
        ]) { [weak self] in self?.prompt.hide() }
    }

    private func confirmSkip() {
        guard !busy else { return }
        prompt.hide()
        // Pack-keep walk decline: drop the tray card (no refund) and advance.
        if case .swap(let trayIndex, _) = mode { _ = campaign.discardPackCard(trayIndex) }
        dismiss(animated: false)
        completion(nil)
    }
}

/// A hook the flows use to checkpoint after a mutation. Chunk D's campaign
/// shell installs the real persistence; screens call through this so they
/// never need to know whether a save layer exists yet.
public protocol CampaignCheckpointing: AnyObject {
    func checkpoint(_ campaign: CampaignState)
}
public enum PersistenceHolder {
    public static weak var shared: CampaignCheckpointing?
}
