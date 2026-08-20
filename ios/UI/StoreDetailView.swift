import UIKit
import GameCore

/// The store's focused detail popup — web `#storeDetail`: a CENTRED pixel
/// panel (never a sheet) with the object large up top; an object caption only
/// where the web object carries one (pack `.pf-name`, Removal `.ro-lab`); the
/// centred rarity line (common = dim cream · uncommon = gold · rare =
/// phosphor); the display-font name; the registry description; then, for the
/// placement kinds (pillar / base / Same-Power), the place-then-confirm
/// chooser ("COL 1 / empty" slots), the EQUIPPED→NEW comparison and the
/// explicit question, all over the gold Buy bar. The equipped loadout chips
/// reuse it read-only with Sell. ✕ closes; a tap outside the panel dismisses.
final class StoreDetailView: UIView {

    private let campaign: CampaignState
    private let panel = PixelPanelView(face: CRT.feltMid, border: CRT.ink)
    private let objView = UIImageView()
    /// The suit-restriction row, parked ABOVE the chip (ItemArt.suitCaption
    /// contract) — only ever present for a restricted sticker.
    private var restrictionIcon: UIImageView?
    private let captionLabel = UILabel()
    private let tierLabel = UILabel()
    private let nameLabel = UILabel()
    private let descLabel = UILabel()
    private let placeDivider = UIView()
    private let placeHeader = UILabel()
    private var colButtons: [ColButton] = []
    private let comparePanel = UIView()
    private var cmpOld: CompareSideView!
    private var cmpNew: CompareSideView!
    private let cmpArrow = UILabel()
    private let questionLabel = UILabel()
    private let buyButton = PixelButtonView("BUY", role: .gold, fontSize: 14)
    private let sellButton = PixelButtonView("SELL", role: .danger, fontSize: 16)
    private let closeButton = PixelButtonView("✕", role: .plain, fontSize: 16)

    var onClose: (() -> Void)?
    /// Buy confirmed; the chosen column (nil for kinds without placement).
    var onBuy: ((Int?) -> Void)?
    var onSell: (() -> Void)?

    private var kind: String
    private var itemId: String
    private var price = 0
    private var placeCol: Int?
    private let isEquippedView: Bool
    private let card: CardSpec?
    /// A mystery Same-Power OFFER slot (unknown until bought).
    private let isMystery: Bool
    /// REVEAL mode: the read-only answer to a mystery buy — no buy, no sell,
    /// no ✕; Keep/Discard rides the host's prompt bar.
    private let isReveal: Bool

    /// Offer detail.
    init(campaign: CampaignState, slot: Int, storeSlot s: StoreSlot) {
        self.campaign = campaign
        self.kind = s.kind
        self.itemId = s.id
        self.card = s.card
        self.isEquippedView = false
        self.isMystery = s.mystery
        self.isReveal = false
        super.init(frame: .zero)
        price = Int(campaign.priceOfMixed(slot))
        // There is only ONE Same slot, so asking which one to use was a step
        // with a single answer. It defaults to picked; the current → new
        // comparison shows straight away and the player just confirms. The
        // MYSTERY slot has nothing to compare yet — its pick happens after.
        if kind == "samepower" && !s.mystery { placeCol = 0 }
        common()
        refresh()
    }

    /// Equipped (read-only + Sell) detail.
    init(campaign: CampaignState, equippedKind: String, id: String, col: Int?) {
        self.campaign = campaign
        self.kind = equippedKind
        self.itemId = id
        self.card = nil
        self.isEquippedView = true
        self.isMystery = false
        self.isReveal = false
        super.init(frame: .zero)
        common()
        refresh()
        sellButton.isHidden = false
        buyButton.isHidden = true
    }

    /// Mystery Same-Power REVEAL: the just-rolled power over the equipped→new
    /// comparison, with KEEP / DISCARD living INSIDE the panel (v6.52 — the
    /// prompt-bar version put the decision at the far end of the screen from
    /// the thing being decided).
    init(campaign: CampaignState, revealedSamePower def: ItemDef) {
        self.campaign = campaign
        self.kind = "samepower"
        self.itemId = def.id
        self.card = nil
        self.isEquippedView = false
        self.isMystery = false
        self.isReveal = true
        super.init(frame: .zero)
        common()
        refresh()
        buyButton.isHidden = true
        closeButton.isHidden = true   // Keep/Discard are the only exits
        keepButton.isHidden = false
        discardButton.isHidden = false
    }

    /// Reveal-mode exits (wired by the store screen).
    var onKeep: (() -> Void)?
    var onDiscard: (() -> Void)?
    private let keepButton = PixelButtonView("KEEP & EQUIP", role: .gold, fontSize: 14)
    private let discardButton = PixelButtonView("DISCARD", role: .danger, fontSize: 14)

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    private func common() {
        backgroundColor = CRT.ink.withAlphaComponent(0.72)   // web scrim: rgba(16,16,14,0.72)
        let outside = UITapGestureRecognizer(target: self, action: #selector(outsideTapped(_:)))
        // The recognizer fires for taps ANYWHERE on the detail — including the
        // panel's own buttons — and a recognized tap cancels touch delivery to
        // them (the Sheets/tutorial cancelsTouchesInView lesson). Don't.
        outside.cancelsTouchesInView = false
        addGestureRecognizer(outside)
        addSubview(panel)
        objView.contentMode = .scaleAspectFit
        objView.layer.magnificationFilter = .nearest
        panel.addSubview(objView)
        for l in [captionLabel, tierLabel, nameLabel, descLabel, placeHeader, questionLabel] {
            l.numberOfLines = 0
            l.textAlignment = .center
            panel.addSubview(l)
        }
        // Web `.sd-place`: a hairline break after the description, then the
        // chooser.
        placeDivider.backgroundColor = CRT.cardFace.withAlphaComponent(0.18)
        placeDivider.isHidden = true
        panel.addSubview(placeDivider)
        // The EQUIPPED→NEW comparison (web `.sd-compare`): the empty-slot
        // silhouette is sized per item family (`.cmp-pillar/base/samepower`).
        let emptySize: CGSize = kind == "samepower" ? CGSize(width: 46, height: 46)
            : kind == "base" ? CGSize(width: 78, height: 32) : CGSize(width: 46, height: 54)
        cmpOld = CompareSideView(tag: "EQUIPPED", isNew: false, emptySize: emptySize)
        cmpNew = CompareSideView(tag: "NEW", isNew: true, emptySize: emptySize)
        cmpArrow.attributedText = CRTKit.attributed("→", size: 16, color: CRT.gold)
        cmpArrow.textAlignment = .center
        comparePanel.addSubview(cmpOld)
        comparePanel.addSubview(cmpArrow)
        comparePanel.addSubview(cmpNew)
        comparePanel.isHidden = true
        panel.addSubview(comparePanel)
        questionLabel.isHidden = true
        buyButton.onTap = { [weak self] in
            guard let self else { return }
            self.onBuy?(self.placeCol)
        }
        panel.addSubview(buyButton)
        keepButton.isHidden = true
        keepButton.onTap = { [weak self] in self?.onKeep?() }
        panel.addSubview(keepButton)
        discardButton.isHidden = true
        discardButton.onTap = { [weak self] in self?.onDiscard?() }
        panel.addSubview(discardButton)
        sellButton.isHidden = true
        sellButton.onTap = { [weak self] in self?.onSell?() }
        panel.addSubview(sellButton)
        closeButton.onTap = { [weak self] in self?.onClose?() }
        panel.addSubview(closeButton)
    }

    @objc private func outsideTapped(_ g: UITapGestureRecognizer) {
        if !panel.frame.contains(g.location(in: self)) { onClose?() }
    }

    private func def() -> ItemDef? {
        let data = GameData.shared
        switch kind {
        case "pillar": return data.pillarTypes.get(itemId)
        case "base": return data.baseTypes.get(itemId)
        case "pack": return data.packTypes.get(itemId)
        case "samepower": return data.samePowerTypes.get(itemId)
        case "sticker": return data.stickerTypes.get(itemId)
        default: return nil
        }
    }

    /// Web `.sd-tier`: common recedes to dim cream; uncommon is gold; rare is
    /// phosphor with the one sanctioned glow.
    private func tierText(_ tier: String) -> NSAttributedString {
        switch tier {
        case "uncommon":
            return CRTKit.attributed(tier.uppercased(), size: 14, color: CRT.gold)
        case "rare":
            return CRTKit.attributed(tier.uppercased(), size: 14, color: CRT.phosphor, glow: true)
        default:
            return CRTKit.attributed(tier.uppercased(), size: 14,
                                     color: CRT.cardFace.withAlphaComponent(0.55))
        }
    }

    private func refresh() {
        let data = GameData.shared
        // Object + identity. The caption rides ONLY the objects whose web
        // component carries live name text (pack `.pf-name`, Removal `.ro-lab`).
        switch kind {
        case "card":
            objView.image = card.map { CardArt.image(CardArt.Face($0), scale: .three) }
            let name: String
            if let c = card {
                name = c.joker ? "★ Joker"
                    : "\(DeckManager.ranks.first { r in r.value == c.currentRank }?.label ?? "?") \(c.suit)"
            } else {
                name = "Card"
            }
            nameLabel.attributedText = CRTKit.attributed(name, size: 14, color: CRT.cardFace, display: true)
            captionLabel.attributedText = nil
            tierLabel.attributedText = nil
            var desc = card?.joker == true
                ? "A Joker. Always safe on any guess. Buy it to swap it into your deck, replacing a card of your choice."
                : data.items.store.card.description
            if let stks = card?.stickers, !stks.isEmpty {
                let names = stks.compactMap { data.stickerTypes.get($0.type)?.label }.joined(separator: ", ")
                desc += " Comes with \(names)."
            }
            descLabel.attributedText = CRTKit.attributed(desc, size: 14,
                                                         color: CRT.cardFace.withAlphaComponent(0.86))
        case "samepower" where isMystery:
            // The MYSTERY slot: unknown-item art, the config label as the
            // name, the config description — no registry def exists yet.
            let cfg = data.items.store.mysterySamePower
            objView.image = ItemArt.mysterySamePower(width: 56, height: 58)
            captionLabel.attributedText = nil
            tierLabel.attributedText = nil
            nameLabel.attributedText = CRTKit.attributed(cfg.label, size: 14, color: CRT.cardFace, display: true)
            descLabel.attributedText = CRTKit.attributed(cfg.description, size: 14,
                                                         color: CRT.cardFace.withAlphaComponent(0.86))
        case "removal":
            objView.image = ItemArt.removal(width: 60, height: 84)
            // No caption: the name prints once, below (v6.35 — every detail
            // sheet says its name exactly once).
            captionLabel.attributedText = nil
            tierLabel.attributedText = nil
            nameLabel.attributedText = CRTKit.attributed(
                data.items.store.removal.label, size: 14, color: CRT.cardFace, display: true)
            descLabel.attributedText = CRTKit.attributed(
                data.items.store.removal.description, size: 14,
                color: CRT.cardFace.withAlphaComponent(0.86))
        default:
            guard let d = def() else { return }
            objView.image = ItemArt.forSlot(kind: kind, id: itemId, card: nil, deckId: campaign.deckId)
            if restrictionIcon?.superview != nil { restrictionIcon?.removeFromSuperview() }
            restrictionIcon = kind == "sticker" ? ItemArt.suitCaptionView(d, width: 46) : nil
            if let restrictionIcon { panel.addSubview(restrictionIcon) }
            captionLabel.attributedText = nil   // the name prints ONCE, below the tier
            tierLabel.attributedText = tierText(d.tier)
            nameLabel.attributedText = CRTKit.attributed(d.label, size: 14, color: CRT.cardFace, display: true)
            // Same-Power descriptions are plain single-line effect text (v6.65
            // dropped the "Trigger: …\nEffect: …" preamble).
            // The REVEAL reads at label size (16): it is the one moment the
            // description IS the content, not fine print (v6.52).
            descLabel.attributedText = CRTKit.attributed(campaign.itemDescription(d), size: isReveal ? 16 : 14,
                                                         color: CRT.cardFace.withAlphaComponent(0.86))
        }

        // Placement chooser (pillars / bases / Same-Power). A mystery offer
        // and the reveal panel place NOTHING — the reveal's Keep equips.
        colButtons.forEach { $0.removeFromSuperview() }
        colButtons.removeAll()
        let placement = !isEquippedView && !isMystery && !isReveal
            && (kind == "pillar" || kind == "base" || kind == "samepower")
        // No header copy at all (v6.36): the pulsing slots ARE the ask — a
        // "choose a column first" line was help text for a step the highlight
        // already teaches.
        placeHeader.isHidden = true
        placeDivider.isHidden = !placement
        if placement {
            if kind == "samepower" {
                // No slot-picker row at all — the swap comparison below is the
                // whole story, and there was never a second slot to choose.
                placeDivider.isHidden = true
            } else {
                let awaiting = placeCol == nil
                let occ = kind == "pillar" ? campaign.columnPillars : campaign.columnBases
                let reg = kind == "pillar" ? GameData.shared.pillarTypes : GameData.shared.baseTypes
                for c in 0..<occ.count {
                    let cur = occ[c].flatMap { reg.get($0)?.label }
                    let b = ColButton(name: "COL \(c + 1)", occupant: cur, selected: placeCol == c,
                                      a11y: "C\(c + 1)·\(cur.map { String($0.prefix(6)) } ?? "empty")".uppercased())
                    b.onTap = { [weak self] in self?.pick(col: c) }
                    b.setAwaiting(awaiting)
                    panel.addSubview(b)
                    colButtons.append(b)
                }
            }
        }
        refreshCompare()
        refreshBuy()
        setNeedsLayout()
    }

    private func pick(col: Int) {
        placeCol = col
        refresh()
    }

    /// The id the current pick would DISPLACE (occupied slot / equipped Same).
    private func replacingOldId() -> String? {
        if kind == "samepower" {
            let cur = campaign.getSamePower()
            return cur != itemId ? cur : nil
        }
        guard kind == "pillar" || kind == "base", let c = placeCol else { return nil }
        let occ = kind == "pillar" ? campaign.columnPillar(c) : campaign.columnBase(c)
        return occ
    }

    /// Web `renderSdCompare`: whenever a target slot is picked, the EQUIPPED
    /// item (or a same-sized "None equipped" placeholder) sits beside the
    /// INCOMING one over an explicit question — identical layout for filling
    /// and replacing.
    private func refreshCompare() {
        // The REVEAL keeps the comparison (v6.52): equipped → revealed, same
        // layout the pillar/base placement uses, with the question under it.
        let placement = !isEquippedView && !isMystery
            && (kind == "pillar" || kind == "base" || kind == "samepower")
        let targetPicked = kind == "samepower" || placeCol != nil
        guard placement, targetPicked, let nt = def() else {
            comparePanel.isHidden = true
            questionLabel.isHidden = true
            questionLabel.attributedText = nil
            return
        }
        let reg = kind == "pillar" ? GameData.shared.pillarTypes
            : kind == "base" ? GameData.shared.baseTypes : GameData.shared.samePowerTypes
        let old = replacingOldId().flatMap { reg.get($0) }
        if let old {
            cmpOld.show(art: ItemArt.forSlot(kind: kind, id: old.id, card: nil, deckId: campaign.deckId),
                        name: old.label, desc: campaign.itemDescription(old))
        } else {
            cmpOld.showEmpty(name: "None equipped",
                             desc: kind == "samepower" ? "No Same-Power equipped yet." : "This slot is empty.")
        }
        cmpNew.show(art: ItemArt.forSlot(kind: kind, id: nt.id, card: nil, deckId: campaign.deckId),
                    name: nt.label, desc: campaign.itemDescription(nt))
        comparePanel.isHidden = false

        // `.sd-replace-q` — the names read gold, the rest dim cream.
        let cream = CRT.cardFace.withAlphaComponent(0.9)
        let q = NSMutableAttributedString()
        func part(_ s: String, _ c: UIColor) { q.append(CRTKit.attributed(s, size: 14, color: c)) }
        if let old {
            part("Replace ", cream); part(old.label, CRT.gold); part(" with ", cream)
            part(nt.label, CRT.gold)
            part(kind == "samepower" ? " as your Same-Power?" : " on column \((placeCol ?? 0) + 1)?", cream)
        } else {
            part(kind == "samepower" ? "Equip " : "Place ", cream)
            part(nt.label, CRT.gold)
            part(kind == "samepower" ? " as your Same-Power?" : " on column \((placeCol ?? 0) + 1)?", cream)
        }
        questionLabel.attributedText = q
        questionLabel.isHidden = false
    }

    private func refreshBuy() {
        guard !isEquippedView, !isReveal else { return }
        let afford = campaign.getCoins() >= price
        let needSlot = (kind == "pillar" || kind == "base") && placeCol == nil
        buyButton.isEnabled = afford && !needSlot
        let label: String
        if !afford { label = "NEED ◉ \(price)" }
        else if needSlot { label = "PICK A COLUMN" }
        else if isMystery { label = "BUY & REVEAL · ◉ \(price)" }
        else if replacingOldId() != nil { label = "BUY & REPLACE · ◉ \(price)" }
        else if kind == "samepower" { label = "BUY & EQUIP · ◉ \(price)" }
        else if kind == "pillar" || kind == "base" { label = "BUY & PLACE · ◉ \(price)" }
        else if kind == "removal" { label = "PURGE A CARD · ◉ \(price)" }
        else if kind == "card" { label = "BUY & SWAP IN · ◉ \(price)" }
        else if kind == "sticker" { label = "PLACE STICKER · ◉ \(price)" }
        else { label = "BUY · ◉ \(price)" }
        buyButton.setTitle(label)
    }

    /// The equipped view's sell price rides its own button.
    func setSellValue(_ v: Int) {
        sellButton.setTitle("SELL FOR ◉\(v)")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w: CGFloat = min(330, bounds.width * 0.86)
        let x = (bounds.width - w) / 2
        let m: CGFloat = 12
        let cw = w - m * 2
        var y: CGFloat = 14
        if let cap = restrictionIcon {
            // The restriction row sits ABOVE the chip; the chip keeps its
            // full 96pt object frame underneath it.
            cap.frame = CGRect(x: (w - cap.frame.width) / 2, y: y,
                               width: cap.frame.width, height: cap.frame.height)
            y += cap.frame.height + 2
        }
        objView.frame = CGRect(x: (w - 150) / 2, y: y, width: 150, height: 96)
        closeButton.frame = CGRect(x: w - 44, y: 8, width: 36, height: 30)
        y += 98
        if captionLabel.attributedText != nil {
            captionLabel.frame = CGRect(x: m, y: y, width: cw, height: 14)
            y += 16
        }
        if tierLabel.attributedText != nil {
            tierLabel.frame = CGRect(x: m, y: y, width: cw, height: 14)
            y += 16
        }
        let nameH = max(18, heightOf(nameLabel, width: cw))
        nameLabel.frame = CGRect(x: m, y: y, width: cw, height: nameH)
        y += nameH + 3
        let descH = heightOf(descLabel, width: cw)
        descLabel.frame = CGRect(x: m, y: y, width: cw, height: descH)
        y += descH + 8
        if !colButtons.isEmpty {
            placeDivider.frame = CGRect(x: m, y: y, width: cw, height: 1)
            y += 11
            if colButtons.count == 1 {
                // The lone Same slot centres at the web's 130px max width.
                let bw: CGFloat = 130
                colButtons[0].frame = CGRect(x: (w - bw) / 2, y: y, width: bw, height: 52)
            } else {
                let gap: CGFloat = 7
                let bw = (cw - gap * CGFloat(max(0, colButtons.count - 1))) / CGFloat(max(1, colButtons.count))
                for (i, b) in colButtons.enumerated() {
                    b.frame = CGRect(x: m + CGFloat(i) * (bw + gap), y: y, width: bw, height: 52)
                }
            }
            y += 60
            if !comparePanel.isHidden {
                let arrowW: CGFloat = 16, gap: CGFloat = 7
                let sideW = (cw - arrowW - gap * 2) / 2
                let h = max(cmpOld.layout(width: sideW), cmpNew.layout(width: sideW))
                comparePanel.frame = CGRect(x: m, y: y, width: cw, height: h)
                cmpOld.frame = CGRect(x: 0, y: 0, width: sideW, height: h)
                cmpArrow.frame = CGRect(x: sideW + gap, y: 0, width: arrowW, height: h)
                cmpNew.frame = CGRect(x: sideW + gap + arrowW + gap, y: 0, width: sideW, height: h)
                y += h + 6
            }
            if !questionLabel.isHidden {
                let qH = heightOf(questionLabel, width: cw)
                questionLabel.frame = CGRect(x: m, y: y, width: cw, height: qH)
                y += qH + 6
            }
        }
        if !buyButton.isHidden {
            buyButton.frame = CGRect(x: m, y: y, width: cw, height: 46)
            y += 54
        }
        if !keepButton.isHidden {
            // The reveal's decision row, INSIDE the panel: discard left,
            // keep right — the destructive exit never sits under the thumb
            // that just tapped BUY.
            let gap: CGFloat = 8
            let bw = (cw - gap) / 2
            discardButton.frame = CGRect(x: m, y: y, width: bw, height: 46)
            keepButton.frame = CGRect(x: m + bw + gap, y: y, width: bw, height: 46)
            y += 54
        }
        if !sellButton.isHidden {
            sellButton.frame = CGRect(x: m, y: y, width: cw, height: 42)
            y += 50
        }
        let h = y + 8
        // Centred, but never under the notch/Dynamic Island or into the
        // home-indicator zone when the content runs tall.
        let topMin = max(40, safeAreaInsets.top + 12)
        var py = max(topMin, (bounds.height - h) / 2)
        let bottomMax = bounds.height - max(safeAreaInsets.bottom, 12) - 8 - h
        if bottomMax >= 8 { py = min(py, max(topMin, bottomMax)) }
        panel.frame = CGRect(x: x, y: py, width: w, height: h)
    }

    private func heightOf(_ l: UILabel, width: CGFloat) -> CGFloat {
        guard let t = l.attributedText, t.length > 0 else { return 0 }
        return ceil(t.boundingRect(with: CGSize(width: width, height: 600),
                                   options: .usesLineFragmentOrigin, context: nil).height)
    }
}

/// A placement slot in the chooser — web `.sd-col`: the slot name ("COL 1" /
/// "SAME") over the occupant ("empty" when free, dimmed). Picked lights the
/// phosphor selection fill + border (`.sd-col-sel`). The a11y label keeps the
/// legacy "C1·EMPTY" shape the UI tests tap.
private final class ColButton: UIControl {
    private let nameL = UILabel()
    private let occL = UILabel()
    /// The "pick me" ring shown while NO column is chosen yet — the same
    /// phosphor pulse the tutorial ring and the map's current node use, so the
    /// column step reads as the live affordance the way a sticker's PLACE bar
    /// or a pack's BUY bar does.
    private let ring = UIView()
    var onTap: (() -> Void)?

    init(name: String, occupant: String?, selected: Bool, a11y: String) {
        super.init(frame: .zero)
        layer.borderWidth = CRT.px
        ring.isUserInteractionEnabled = false
        ring.layer.borderWidth = 2
        ring.layer.borderColor = CRT.phosphor.cgColor
        ring.layer.shadowColor = CRT.phosphor.cgColor
        ring.layer.shadowRadius = CRT.glowRadius
        ring.layer.shadowOpacity = 0.8
        ring.layer.shadowOffset = .zero
        ring.isHidden = true
        addSubview(ring)
        nameL.attributedText = CRTKit.attributed(name, size: 14,
                                                 color: CRT.cardFace.withAlphaComponent(0.85))
        nameL.textAlignment = .center
        occL.attributedText = CRTKit.attributed(occupant ?? "empty", size: 14,
                                                color: occupant == nil
                                                    ? CRT.cardFace.withAlphaComponent(0.6) : CRT.cardFace)
        occL.textAlignment = .center
        occL.numberOfLines = 2
        addSubview(nameL)
        addSubview(occL)
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = a11y
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        set(selected)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    func set(_ sel: Bool) {
        layer.borderColor = (sel ? CRT.phosphor : CRT.ink).cgColor
        backgroundColor = sel ? CRT.phosphor.withAlphaComponent(0.16) : CRT.feltDeep
    }

    /// Pulse while the placement is still waiting on a column. Compositor-only
    /// (one opacity animation), stopped the moment a column is picked.
    func setAwaiting(_ on: Bool) {
        guard on != !ring.isHidden else { return }
        ring.isHidden = !on
        if on {
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 0.35
            pulse.toValue = 1.0
            pulse.duration = 0.75
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            ring.layer.add(pulse, forKey: "pickPulse")
        } else {
            ring.layer.removeAnimation(forKey: "pickPulse")
        }
    }

    @objc private func tapped() { onTap?() }

    override func layoutSubviews() {
        super.layoutSubviews()
        ring.frame = bounds
        nameL.frame = CGRect(x: 2, y: 6, width: bounds.width - 4, height: 14)
        occL.frame = CGRect(x: 2, y: 21, width: bounds.width - 4, height: 27)
    }
}

// CompareSideView moved to CompareViews.swift — the Old Joker's trade modal
// shares it now, so "what you have → what you'd get" is one component.
