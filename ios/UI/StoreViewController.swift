import UIKit
import GameCore

public protocol StoreScreenDelegate: AnyObject {
    /// GO TO MAP — the visit is over.
    func storeDone(_ store: StoreViewController)
    /// The shell's ☰ — the pause menu, same as from the map or a deal.
    func storeWantsMenu(_ store: StoreViewController)
}

/// The store — ONE fixed screen (AGENTS UX): a unified 6-slot shelf (5 rolled
/// + the permanent Removal), the reroll button with its escalating cost, the
/// equipped-loadout reference, and GO TO MAP. Sub-flows (detail, card picker,
/// pack reveal) open above it and return to the same screen.
public final class StoreViewController: UIViewController {

    private let campaign: CampaignState
    public weak var delegate: StoreScreenDelegate?

    private let shell = TopShellView()
    private let titleLabel = UILabel()
    private let balanceLabel = UILabel()
    private let helpButton = PixelButtonView("?", role: .plain, fontSize: 16)
    private let msgLabel = UILabel()
    private let shelf = UIView()
    private var tiles: [StoreTileView] = []
    private let rerollButton = PixelButtonView("RESTOCK", role: .gold, fontSize: 16)
    /// The Queen's Restock reminder line, shown only while this visit's first
    /// restock is still free (v6.55). Fixed slot under the title row — the
    /// shelf's frame never depends on it (stable containers).
    private let boonLabel = UILabel()
    private let loadoutPanel = PixelPanelView(face: CRT.feltMid, border: CRT.ink)
    private let loadoutTitle = UILabel()
    private var loadoutChips: [UIView] = []
    private let goButton = PixelButtonView("GO TO MAP", role: .cta, fontSize: 18)
    private let prompt = PromptBar()
    private let crt = CRTOverlayUIView()
    private let tissue = TissueView()
    private var detail: StoreDetailView?
    private var keyPanel: UIView?
    private var holdHelp = PixelPanelView()
    /// One check per visit for the first-ever-shop legend auto-open (task 13);
    /// the PERSISTENT gate is the `storeHelpSeen` pref.
    private var didCheckAutoHelp = false

    /// A mystery "store" detour keys the offer to the mystery node.
    public var offerNodeId: Int?

    public init(campaign: CampaignState) {
        self.campaign = campaign
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    public override var prefersStatusBarHidden: Bool { true }

    public override func viewDidLoad() {
        super.viewDidLoad()
        Sound.shared.storeOpen()   // the shop door-chime, once per visit
        view.backgroundColor = CRT.feltDeep
        tissue.frame = view.bounds
        tissue.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(tissue)          // #tissue atmosphere, bottommost

        // Fresh visit rolls a new offer; a resume of THIS visit keeps the
        // saved one (a restock while shopping can never hand out a free
        // reroll). SEED1: the offer keys to the node id. v6.52: an offer
        // stamped for a DIFFERENT node is the previous shop's leftover — the
        // mystery-detour store opens with fresh=false and used to inherit
        // both that stale shelf and its per-visit price twist — so a
        // mismatch rerolls. A nil stamp (gift shelf, pre-v6.52 save) keeps
        // the saved offer.
        let d = UserDefaults.standard
        let keyId = offerNodeId ?? campaign.nodePos
        // SCREENSHOT HOOK (EventCaptureUITests, v6.55): `-storeFreeRefresh 1`
        // arms the Queen's Restock before this visit's offer opens — the
        // real openStore consumption path, so the shelf is genuinely free.
        if d.bool(forKey: "storeFreeRefresh") { campaign.debugGrantFreeRefresh() }
        if campaign.getStoreOffer() == nil || campaign.storeOfferIsStale(for: keyId) {
            if let keyId {
                _ = campaign.openStore(rng: runRng(seed: campaign.runSeed, [.s("store"), .n(keyId)]),
                                       node: keyId)
            } else {
                _ = campaign.openStore()
            }
            logShopRolls()   // v6.76: the fresh shelf's rolled values hit the debug log
        }

        // The persistent top shell (HUD line + deck band), same as the map.
        shell.showsDeckStack = true
        // The ☰ was never wired here, so it looked live and did nothing — the
        // store was the one screen you couldn't pause from.
        shell.onMenu = { [weak self] in
            guard let self else { return }
            self.delegate?.storeWantsMenu(self)
        }
        shell.onDeckTap = { [weak self] in
            guard let self else { return }
            self.present(DeckInspectViewController(campaign: self.campaign), animated: false)
        }
        view.addSubview(shell)

        // "Shop" + the balance beneath; Restock + ? clustered on the right.
        titleLabel.attributedText = CRTKit.attributed("Shop", size: 22, color: CRT.cardFace, display: true)
        view.addSubview(titleLabel)
        view.addSubview(balanceLabel)
        helpButton.onTap = { [weak self] in self?.toggleKey() }
        view.addSubview(helpButton)

        msgLabel.isHidden = true
        view.addSubview(msgLabel)
        boonLabel.isHidden = true
        boonLabel.clipsToBounds = true   // a 16pt slot — never into the tiles
        view.addSubview(boonLabel)
        view.addSubview(shelf)

        rerollButton.onTap = { [weak self] in self?.rerollTapped() }
        view.addSubview(rerollButton)

        view.addSubview(loadoutPanel)
        loadoutTitle.attributedText = CRTKit.attributed("EQUIPPED", size: 14, color: CRT.muted, display: true)
        loadoutPanel.addSubview(loadoutTitle)

        goButton.onTap = { [weak self] in self?.goTapped() }
        view.addSubview(goButton)

        crt.isUserInteractionEnabled = false
        view.addSubview(crt)
        view.addSubview(prompt)

        setMessage("Buy from the offer, restock, then head for the map.")
        render()
        // Autopilot: browse a beat, then GO TO MAP (buys are exercised by the
        // picker flows the mystery outcomes drive).
        if UserDefaults.standard.integer(forKey: "autoCampaign") > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.goTapped()
            }
        }
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let b = view.bounds
        let shellH = TopShellView.height(safeTop: view.safeAreaInsets.top)
        shell.frame = CGRect(x: 0, y: 0, width: b.width, height: shellH)

        // Title row: Shop + balance left; Restock + ? right.
        // "Shop" and the purse sit on ONE line: the balance is the number every
        // decision here is measured against, so it rides beside the title
        // instead of under it, where the eye skipped it.
        titleLabel.frame = CGRect(x: 12, y: shellH + 8, width: 92, height: 30)
        balanceLabel.frame = CGRect(x: 108, y: shellH + 10, width: b.width - 108 - 190, height: 28)
        helpButton.frame = CGRect(x: b.width - 42, y: shellH + 16, width: 32, height: 32)
        rerollButton.frame = CGRect(x: b.width - 42 - 8 - 130, y: shellH + 14, width: 130, height: 36)
        // The boon reminder rides the fixed gap between the title row and the
        // shelf (shelfTop = shellH + 60) — nothing else is laid out from it.
        // Width stops short of the Restock/? cluster on the right.
        boonLabel.frame = CGRect(x: 12, y: shellH + 43, width: b.width - 198, height: 15)

        // The shelf GROWS to fill everything between the title row and the
        // equipped panel — tall tiles, the merchandise breathes (web parity).
        let goH: CGFloat = 46
        // 96 was sized for single-line loadout chips. The chips WRAP to two
        // lines now (so "Diamond Distribution" reads in full), which makes a
        // column 85pt tall — at 96 the second row was clipped and ran into
        // GO TO MAP. 118 = 24 top inset + 85 + 9 breathing room.
        let loH: CGFloat = 118
        let goTop = b.height - view.safeAreaInsets.bottom - goH - 10
        let loTop = goTop - loH - 8
        let shelfTop = shellH + 60
        let tw = (b.width - 12 * 2 - 11 * 2) / 3
        let th = (loTop - 8 - shelfTop - 11) / 2
        shelf.frame = CGRect(x: 12, y: shelfTop, width: b.width - 24, height: th * 2 + 11)
        for (i, t) in tiles.enumerated() {
            let r = i / 3, c = i % 3
            t.frame = CGRect(x: CGFloat(c) * (tw + 11), y: CGFloat(r) * (th + 11), width: tw, height: th)
        }
        loadoutPanel.frame = CGRect(x: 12, y: loTop, width: b.width - 24, height: loH)
        loadoutTitle.frame = CGRect(x: 10, y: 6, width: 200, height: 16)
        layoutLoadout()
        goButton.frame = CGRect(x: 12, y: goTop, width: b.width - 24, height: goH)
        crt.frame = b
        tissue.frame = b
        prompt.frame = b
        detail?.frame = b
        // FIRST-EVER shop: the "?" legend opens itself once, pref-stamped even
        // if closed instantly (the map-key idiom, MapViewController). A gift
        // shelf is the joker's coat, not a store — it never counts. After the
        // stamp, only the "?" button opens it.
        if !didCheckAutoHelp {
            didCheckAutoHelp = true
            if !campaign.isGiftShelf, campaign.saveStore.pref("storeHelpSeen") != "1" {
                campaign.saveStore.setPref("storeHelpSeen", "1")
                toggleKey()
            }
        }
    }

    private func setMessage(_ s: String) {
        msgLabel.attributedText = CRTKit.attributed(s, size: 14, color: CRT.muted)
    }

    // MARK: - Render

    public func render() {
        shell.sync(campaign: campaign)
        let bal = NSMutableAttributedString(
            string: "\(campaign.getCoins()) ", attributes: [.font: CRT.Font.of(26), .foregroundColor: CRT.gold])
        // The coin mark is GOLD like every other coin readout in the game,
        // at the number's own size (v6.97 — the "to spend" tail is gone).
        bal.append(NSAttributedString(
            string: "◉", attributes: [.font: CRT.Font.of(26), .foregroundColor: CRT.gold]))
        balanceLabel.attributedText = campaign.isGiftShelf
            ? CRTKit.attributed("everything here is free", size: 16, color: CRT.muted)
            : bal

        // Shelf tiles.
        tiles.forEach { $0.removeFromSuperview() }
        tiles.removeAll()
        let slots = campaign.getStoreOffer()?.slots ?? []
        for (i, s) in slots.enumerated() {
            let tile = StoreTileView(slot: i)
            if let s {
                let locked = campaign.stickersLocked
                    && (s.kind == "sticker" || (s.kind == "pack" && GameData.shared.packTypes.get(s.id)?.kind == "sticker"))
                let price = Int(campaign.priceOfMixed(i))
                // Web `.ti-obj.obj-removal`: the shelf removal object is the
                // bare torn card — its "REMOVAL" caption (.ro-lab) is LIVE text
                // under the art (the tile caption below), never baked in.
                let art: UIImage
                if s.kind == "removal" {
                    art = ItemArt.removal(width: 52, height: 66)
                } else if s.mystery {
                    art = ItemArt.mysterySamePower(width: 56, height: 58)
                } else if s.kind == "card", let c = s.card, !c.stickers.isEmpty {
                    // A card single is shown WITH its sticker chips (v6.72) —
                    // the canonical top-right corner fan (StickerChipLayout,
                    // master comment in PileNode.swift), the same composite
                    // the picker banner and pack reveal use. A stickered card
                    // whose tile showed a bare face read as a bug.
                    art = CardPickerViewController.cardWithStickers(c, extra: nil)
                } else {
                    art = ItemArt.forSlot(kind: s.kind, id: s.id, card: s.card, deckId: campaign.deckId)
                }
                // EVERY tile names itself (v6.80 consistency pass — packs,
                // Purge and rolled items used to carry a caption while
                // pillar/base/sticker/card tiles sat bare, which read as
                // random). The label always comes from the registry (the
                // store config for the mystery slot); a SHOP-ROLLED item
                // appends its rolled value ("TRANSMUTE — ♠", suits render as
                // pixel pips through CRTKit's substitution); the card slot
                // names the card itself.
                let caption = s.kind == "pack" ? GameData.shared.packTypes.get(s.id)?.label
                    : s.kind == "removal" ? GameData.shared.items.store.removal.label
                    : s.mystery ? GameData.shared.items.store.mysterySamePower.label
                    : rolledCaption(s) ?? plainCaption(s)
                tile.configure(art: art, kind: s.kind, caption: caption,
                               restriction: s.kind == "sticker"
                                   ? GameData.shared.stickerTypes.get(s.id)
                                       .flatMap { ItemArt.suitCaption($0, width: 40) }
                                   : nil,
                               price: price,
                               affordable: campaign.getCoins() >= price,
                               tier: tierOf(s),
                               locked: locked)
                tile.onTap = { [weak self] in self?.openDetail(slot: i) }
                // No hold-for-help on shelf items (v6.53 batch 3): the tap
                // already opens the detail sheet with the same registry copy —
                // the hold was a second door to the same room.
            } else {
                tile.configureSold()
            }
            shelf.addSubview(tile)
            tiles.append(tile)
        }
        // A GIFT SHELF is the Old Joker emptying his coat: no restock, no
        // prices, and the exit says you're done taking rather than shopping.
        // The title reads in the Give/Get grammar (v6.62) — this is the GET.
        if campaign.isGiftShelf {
            rerollButton.isHidden = true
            titleLabel.attributedText = CRTKit.attributed("Get…", size: 22,
                                                          color: CRT.gold, display: true)
            goButton.setTitle("DONE")
            setMessage("Take what you want. It's all paid for.")
        } else {
            rerollButton.isHidden = false
            let cost = Int(campaign.storeRerollCost())
            // The Queen's Restock (v6.55): while this visit's first restock is
            // still free, the button says FREE and wears the charged (phosphor)
            // glow, and the boon line names her. One static treatment — no
            // animation, so the pause-behind-overlay contract is untouched.
            let freeRefresh = cost == 0
            rerollButton.setTitle(freeRefresh ? "↻ RESTOCK · FREE" : "↻ RESTOCK · ◉\(cost)")
            rerollButton.setRole(freeRefresh ? .charged : .gold)
            rerollButton.isEnabled = campaign.canReroll()
            boonLabel.isHidden = !freeRefresh
            if freeRefresh {
                boonLabel.attributedText = CRTKit.attributed(
                    "The Queen will restock for free.",
                    size: 12, color: CRT.phosphor)
            }
        }

        renderLoadout()
        view.setNeedsLayout()
        PersistenceHolder.shared?.checkpoint(campaign)
    }

    private func tierOf(_ s: StoreSlot) -> String {
        if s.mystery { return "" }   // the mystery slot has no rarity to hint at
        let data = GameData.shared
        switch s.kind {
        case "pillar": return data.pillarTypes.get(s.id)?.tier ?? "common"
        case "base": return data.baseTypes.get(s.id)?.tier ?? "common"
        case "pack": return data.packTypes.get(s.id)?.tier ?? "common"
        case "samepower": return data.samePowerTypes.get(s.id)?.tier ?? "common"
        case "sticker": return data.stickerTypes.get(s.id)?.tier ?? "common"
        default: return ""
        }
    }

    /// A rank VALUE → its registry label ("9", "K", "A") — never a hand-mapped
    /// string (a rank retune moves this with it).
    private func rankLabel(_ value: Int?) -> String? {
        guard let value else { return nil }
        return DeckManager.ranks.first { $0.value == value }?.label ?? "\(value)"
    }

    /// The registry def behind a shop-rolled slot (only pillars and bases roll).
    private func shopRolledDef(_ s: StoreSlot) -> ItemDef? {
        s.kind == "pillar" ? GameData.shared.pillarTypes.get(s.id)
            : s.kind == "base" ? GameData.shared.baseTypes.get(s.id) : nil
    }

    /// The rolled {rank}/{suit} as short shelf text: "9S", "♠", "9S→♠" (R2).
    /// Reads the SLOT's rolled values — the climb lock has already reconciled
    /// them (openStore), so the shelf, the detail and the purchase agree.
    /// TRANSMUTE (v6.78): its rank is the deck's LIVE most common, so the
    /// tile computes it fresh — "9s→♣" tracks the deck of the moment.
    private func rolledText(_ s: StoreSlot) -> String? {
        guard s.rollRank != nil || s.rollSuit != nil else { return nil }
        var out = ""
        if GameData.shared.baseTypes.get(s.id)?.effect == "transmute",
           let live = rankLabel(campaign.mostCommonRank()) {
            out = live + "s"
        } else if let r = rankLabel(s.rollRank) {
            out = r + "s"
        }
        if let suit = s.rollSuit { out += out.isEmpty ? suit : "→" + suit }
        return out
    }

    /// The shop-rolled tile's name-and-roll caption (v6.76, R2) — nil for
    /// slots that rolled nothing (those fall through to `plainCaption`).
    private func rolledCaption(_ s: StoreSlot) -> String? {
        guard let rolled = rolledText(s), let def = shopRolledDef(s) else { return nil }
        return "\(def.label) — \(rolled)"
    }

    /// The plain name caption every un-rolled tile wears (v6.80): the
    /// registry label for items, the card's own face for the card slot.
    private func plainCaption(_ s: StoreSlot) -> String? {
        let d = GameData.shared
        switch s.kind {
        case "sticker":   return d.stickerTypes.get(s.id)?.label
        case "pillar":    return d.pillarTypes.get(s.id)?.label
        case "base":      return d.baseTypes.get(s.id)?.label
        case "samepower": return d.samePowerTypes.get(s.id)?.label
        case "card":
            guard let c = s.card else { return d.items.store.card.label }
            return c.joker ? "★ Joker" : "\(rankLabel(c.currentRank) ?? "?")\(c.suit)"
        default:          return nil
        }
    }

    /// SHOP-ROLLED values in the debug log (v6.76, R2): when a fresh shelf
    /// rolls (open or restock), each rolled slot's locked {rank}/{suit} gets a
    /// line — the same ground-truth the tile and detail show the player.
    private func logShopRolls() {
        guard let offer = campaign.getStoreOffer() else { return }
        for s in offer.slots.compactMap({ $0 }) {
            guard let rolled = rolledText(s), let def = shopRolledDef(s) else { continue }
            DebugEventLog.shared.add("store: \(def.label) rolled \(rolled)")
        }
    }

    private func renderLoadout() {
        loadoutChips.forEach { $0.removeFromSuperview() }
        loadoutChips.removeAll()
        let data = GameData.shared
        let pillars = campaign.columnPillars
        let bases = campaign.columnBases
        for c in 0..<max(pillars.count, bases.count, 3) {
            let col = makeLoadoutColumn(
                title: "COL \(c + 1)",
                rows: [
                    (pillars[safe: c].flatMap { $0 }.flatMap { data.pillarTypes.get($0) }, "pillar", c),
                    (bases[safe: c].flatMap { $0 }.flatMap { data.baseTypes.get($0) }, "base", c),
                ])
            loadoutPanel.addSubview(col)
            loadoutChips.append(col)
        }
        let sp = campaign.getSamePower().flatMap { data.samePowerTypes.get($0) }
        let sameCol = makeLoadoutColumn(title: "SAME", rows: [(sp, "samepower", nil)])
        loadoutPanel.addSubview(sameCol)
        loadoutChips.append(sameCol)
        layoutLoadout()
    }

    private func makeLoadoutColumn(title: String, rows: [(ItemDef?, String, Int?)]) -> UIView {
        let v = UIView()
        let t = CRTKit.label(title, size: 14, color: CRT.muted)
        t.alpha = 0.9
        t.textAlignment = .center
        t.frame = CGRect(x: 0, y: 0, width: 82, height: 16)
        v.addSubview(t)
        var y: CGFloat = 17
        for (def, kind, col) in rows {
            // Web `.lo-chip`: a recessed deep-felt slab, ink border; class
            // identity by TEXT colour — pillar gold · base cream · Same phosphor.
            let tint: UIColor = kind == "pillar" ? CRT.gold
                : kind == "samepower" ? CRT.phosphor : CRT.cardFace
            if let def {
                let b = UIButton(type: .custom)
                // The label WRAPS instead of being chopped at 9 characters —
                // "Diamond Distribution" used to read "Diamond D", which names
                // no item the player can find again in the shop.
                b.setAttributedTitle(CRTKit.attributed(def.label, size: 14, color: tint), for: .normal)
                b.titleLabel?.numberOfLines = 2
                b.titleLabel?.textAlignment = .center
                b.titleLabel?.lineBreakMode = .byWordWrapping
                b.backgroundColor = CRT.feltDeep
                b.layer.borderWidth = 1
                b.layer.borderColor = CRT.ink.cgColor
                b.frame = CGRect(x: 0, y: y, width: 82, height: 32)
                b.addAction(UIAction { [weak self] _ in
                    self?.openEquippedDetail(kind: kind, id: def.id, col: col)
                }, for: .touchUpInside)
                // No hold-for-help here either (v6.53 batch 3): the tap opens
                // the equipped detail with the identical copy.
                v.addSubview(b)
            } else {
                let e = CRTKit.label("empty", size: 14, color: CRT.disabledText)
                e.textAlignment = .center
                e.backgroundColor = CRT.feltDeep
                e.layer.borderWidth = 1
                e.layer.borderColor = CRT.ink.cgColor
                e.frame = CGRect(x: 0, y: y, width: 82, height: 32)
                v.addSubview(e)
            }
            y += 36
        }
        return v
    }

    private func layoutLoadout() {
        let n = loadoutChips.count
        guard n > 0 else { return }
        let w = (loadoutPanel.bounds.width - 20) / CGFloat(n)
        for (i, v) in loadoutChips.enumerated() {
            v.frame = CGRect(x: 10 + CGFloat(i) * w, y: 24, width: w - 4,
                             height: loadoutPanel.bounds.height - 30)
        }
    }

    // MARK: - Hold-for-help

    private func addHold(to v: UIView, _ show: @escaping () -> Void) {
        let g = UILongPressGestureRecognizer(target: self, action: #selector(holdFired(_:)))
        // Web attachStoreHoldHelp: 500ms — 350/450 was short enough that an
        // ordinary mobile tap could trip it and swallow the buy tap.
        g.minimumPressDuration = 0.5
        v.addGestureRecognizer(g)
        holdActions[ObjectIdentifier(v)] = show
    }
    private var holdActions: [ObjectIdentifier: () -> Void] = [:]
    @objc private func holdFired(_ g: UILongPressGestureRecognizer) {
        guard let v = g.view else { return }
        switch g.state {
        case .began: holdActions[ObjectIdentifier(v)]?()
        case .ended, .cancelled, .failed: hideHoldHelp()
        default: break
        }
    }

    /// HOLD-HELP LIVES AT THE TOP, over the shell's deck band — the same place
    /// the deal, the deck overview and the card pickers put it. The store used
    /// the bottom prompt bar, so the one gesture that works everywhere answered
    /// in a different corner here.
    private func showHoldHelp(title: String, body: String) {
        holdHelp.removeFromSuperview()
        holdHelp = PixelPanelView(face: CRT.feltDeep, border: CRT.phosphor)
        let t = CRTKit.label(title, size: 18, color: CRT.phosphor, display: true, glow: true)
        let b = CRTKit.label(body, size: 16, color: CRT.cardFace)
        t.textAlignment = .center
        b.textAlignment = .center
        t.numberOfLines = 0
        b.numberOfLines = 0
        let w = min(view.bounds.width - 24, 400)
        let titleH = ceil(t.sizeThatFits(CGSize(width: w - 24, height: 200)).height)
        let bodyH = ceil(b.sizeThatFits(CGSize(width: w - 24, height: 600)).height)
        let h = titleH + bodyH + 26
        // OVER the shell's deck band, not above it — the band IS the histogram
        // container, and floating clear of it left the help in the gap between
        // the notch and the HUD.
        let band = shell.frame
        holdHelp.frame = CGRect(x: (view.bounds.width - w) / 2,
                                y: max(view.safeAreaInsets.top + 4,
                                       band.maxY - h - 6),
                                width: w, height: h)
        t.frame = CGRect(x: 12, y: 8, width: w - 24, height: titleH)
        b.frame = CGRect(x: 12, y: 12 + titleH, width: w - 24, height: bodyH)
        holdHelp.addSubview(t)
        holdHelp.addSubview(b)
        view.insertSubview(holdHelp, belowSubview: crt)
    }

    private func hideHoldHelp() { holdHelp.removeFromSuperview() }

    private func showHelp(kind: String, id: String, card: CardSpec?) {
        let data = GameData.shared
        var title = "", tier = "", desc = "", suitLine: String? = nil
        // The MYSTERY Same-Power slot's help comes from the store config —
        // there is no registry entry behind it until the buy reveals one.
        if kind == "samepower" && id == StoreSlot.mysteryId {
            let cfg = data.items.store.mysterySamePower
            showHoldHelp(title: cfg.label, body: cfg.description)
            return
        }
        switch kind {
        case "card":
            title = card?.joker == true ? "★ Joker" : "Card"
            desc = "Buy it to swap into your deck, replacing a card of your choice."
        case "removal":
            title = data.items.store.removal.label
            desc = data.items.store.removal.description
        default:
            let def = kind == "pillar" ? data.pillarTypes.get(id)
                : kind == "base" ? data.baseTypes.get(id)
                : kind == "pack" ? data.packTypes.get(id)
                : kind == "samepower" ? data.samePowerTypes.get(id)
                : data.stickerTypes.get(id)
            guard let def else { return }
            title = def.label; tier = def.tier; desc = campaign.itemDescription(def)
            if kind == "sticker" {
                let suits = def.suits ?? []
                suitLine = suits.isEmpty ? "Add to any card"
                    : "Add to any \(suits.joined(separator: " or ")) card"
            }
        }
        var text = title + (tier.isEmpty ? "" : " · \(tier.uppercased())")
        if let s = suitLine { text += "\n\(s)" }
        showHoldHelp(title: text, body: desc)
    }

    // MARK: - Detail + buy

    private func openDetail(slot: Int) {
        guard let offer = campaign.getStoreOffer(), let s = offer.slots[safe: slot] ?? nil else { return }
        Sound.shared.tap()   // the tile is a raw UIControl — it makes no click of its own
        let d = StoreDetailView(campaign: campaign, slot: slot, storeSlot: s)
        d.onClose = { [weak self] in self?.closeDetail() }
        d.onBuy = { [weak self] col in self?.buy(slot: slot, storeSlot: s, placeCol: col) }
        // A family-blocked column (v6.76 sameTolerance) answers its tap with
        // the engine's reason, on the shared prompt bar.
        d.onBlocked = { [weak self] reason in
            self?.prompt.show(reason, help: "Pick another column, or move the pillar that's there first.",
                              actions: [.init("OK", role: .plain) { [weak self] in self?.prompt.hide() }])
        }
        d.frame = view.bounds
        view.insertSubview(d, belowSubview: crt)
        detail = d
    }

    private func openEquippedDetail(kind: String, id: String, col: Int?) {
        Sound.shared.tap()
        let d = StoreDetailView(campaign: campaign, equippedKind: kind, id: id, col: col)
        d.onClose = { [weak self] in self?.closeDetail() }
        d.onSell = { [weak self] in self?.sellEquipped(kind: kind, id: id, col: col) }
        let data = GameData.shared
        let def = kind == "pillar" ? data.pillarTypes.get(id)
            : kind == "base" ? data.baseTypes.get(id) : data.samePowerTypes.get(id)
        d.setSellValue(sellValue(def))
        d.frame = view.bounds
        view.insertSubview(d, belowSubview: crt)
        detail = d
    }

    private func closeDetail() {
        detail?.removeFromSuperview()
        detail = nil
    }

    /// v6.50: the sell table lives in items.js (`store.sell`) — the UI reads
    /// it through the campaign, never hardcodes it (the same bypass class as
    /// the freebie price bug).
    private func sellValue(_ def: ItemDef?) -> Int { campaign.sellValue(def) }

    private func sellEquipped(kind: String, id: String, col: Int?) {
        let data = GameData.shared
        let def = kind == "pillar" ? data.pillarTypes.get(id)
            : kind == "base" ? data.baseTypes.get(id)
            : data.samePowerTypes.get(id)
        guard let def else { return }
        let value = sellValue(def)
        prompt.show("Sell \(def.label) for ◉ \(value)?", help: "It won't return to your inventory.", actions: [
            .init("Cancel", role: .plain) { [weak self] in self?.prompt.hide() },
            .init("Sell", role: .danger) { [weak self] in
                guard let self else { return }
                self.prompt.hide()
                var ok = false
                if kind == "samepower", self.campaign.getSamePower() == id {
                    _ = self.campaign.unequipSamePower()
                    ok = self.campaign.discardSamePowerFromInventory(id)
                } else if kind == "pillar", let c = col, self.campaign.columnPillar(c) == id {
                    // Sell-and-destroy: empty the slot, never back to inventory.
                    self.campaign.setColumnPillar(col: c, typeId: nil)
                    ok = true
                } else if kind == "base", let c = col, self.campaign.columnBase(c) == id {
                    self.campaign.setColumnBase(col: c, typeId: nil)
                    ok = true
                }
                guard ok else { return }
                _ = self.campaign.addCoins(value)
                Haptics.sell()
                self.setMessage("\(def.label) sold for \(value) coins.")
                self.closeDetail()
                self.render()
            },
        ]) { [weak self] in self?.prompt.hide() }
    }

    private func buy(slot: Int, storeSlot s: StoreSlot, placeCol: Int?) {
        switch s.kind {
        case "sticker":
            // Place-then-confirm-then-pay: the picker opens first; payment
            // happens on the confirmed card.
            closeDetail()
            let picker = CardPickerViewController(campaign: campaign,
                                                  mode: .buySticker(slot: slot, typeId: s.id)) { [weak self] picked in
                guard let self else { return }
                if picked != nil {
                    Haptics.purchase()
                    self.setMessage("\(GameData.shared.stickerTypes.get(s.id)?.label ?? "Sticker") applied.")
                }
                self.render()
            }
            present(picker, animated: false)

        case "removal":
            closeDetail()
            let price = Int(campaign.removalPrice())
            guard campaign.getCoins() >= price else { return }
            let picker = CardPickerViewController(campaign: campaign,
                                                  mode: .removal(price: price)) { [weak self] picked in
                guard let self else { return }
                if picked != nil {
                    Haptics.purchase()
                    self.setMessage("A card was purged. The deck is thinner.")
                }
                self.render()
            }
            present(picker, animated: false)

        case "samepower" where s.mystery:
            // MYSTERY SAME-POWER: the concrete id rolls NOW, seeded to
            // (node, slot) — the storepack keying — then the reveal offers
            // Keep (equip) or Discard on the shared prompt bar.
            let keyId = offerNodeId ?? campaign.nodePos ?? 0
            let rng = runRng(seed: campaign.runSeed, [.s("mysterysamepower"), .n(keyId), .n(slot)])
            let res = campaign.buyMixedSlot(slot, mysteryRng: rng)
            guard res.ok, let revealed = res.revealed,
                  let def = GameData.shared.samePowerTypes.get(revealed) else { return }
            Haptics.purchase()
            closeDetail()
            render()
            revealMysterySamePower(def)

        case "pillar", "base", "samepower":
            guard let col = placeCol else { return }
            // ON-PURCHASE items (v6.76): Rank Purge and Transmute fire AT BUY
            // TIME, on the whole deck — a blind BUY tap must never do that.
            // The confirm rides the shared prompt bar and names the rolled
            // rank (and suit), then the result notice says what happened.
            if let pdef = s.kind == "pillar" ? GameData.shared.pillarTypes.get(s.id) : nil,
               pdef.effect == "purgeRank" {
                let rl = rankLabel(campaign.shopRolls[s.id]?.rank ?? s.rollRank) ?? "?"
                prompt.show("Purge all \(rl)s from your deck?",
                            help: "\(pdef.label) fires the moment you buy it — every \(rl) in your deck is gone for good. It does nothing during a deal.",
                            actions: [
                                .init("Cancel", role: .plain) { [weak self] in self?.prompt.hide() },
                                .init("Purge \(rl)s", role: .danger) { [weak self] in
                                    self?.prompt.hide()
                                    self?.completePlacementBuy(slot: slot, storeSlot: s, col: col)
                                },
                            ]) { [weak self] in self?.prompt.hide() }
                return
            }
            if let bdef = s.kind == "base" ? GameData.shared.baseTypes.get(s.id) : nil,
               bdef.effect == "transmute" {
                // v6.78: the rank is the deck's LIVE most common — exactly
                // what the buy will target this instant.
                let lock = campaign.shopRolls[s.id]
                let rl = rankLabel(campaign.mostCommonRank()) ?? "?"
                let suit = lock?.suit ?? s.rollSuit ?? "?"
                prompt.show("Set all \(rl)s to \(suit)?",
                            help: "\(bdef.label) fires the moment you buy it — every \(rl) in your deck becomes \(suit), for good. It never activates in a deal.",
                            actions: [
                                .init("Cancel", role: .plain) { [weak self] in self?.prompt.hide() },
                                .init("Transmute", role: .danger) { [weak self] in
                                    self?.prompt.hide()
                                    self?.completePlacementBuy(slot: slot, storeSlot: s, col: col)
                                },
                            ]) { [weak self] in self?.prompt.hide() }
                return
            }
            completePlacementBuy(slot: slot, storeSlot: s, col: col)

        case "pack":
            let res = campaign.buyMixedSlot(slot)
            guard res.ok, let packId = res.packId else { return }
            Haptics.purchase()
            closeDetail()
            render()
            openPackReveal(packId: packId, slot: slot, keep: res.keep ?? 1)

        case "card":
            let res = campaign.buyMixedSlot(slot)
            guard res.ok, let trayIndex = res.trayIndex else { return }
            Haptics.purchase()
            closeDetail()
            render()
            startPackKeepWalk(from: trayIndex)

        default:
            break
        }
    }

    /// The pillar/base/Same-Power buy: charge, place (or equip), sell back the
    /// displaced occupant — then, for an ON-PURCHASE item (v6.76), the prompt
    /// bar reports what the buy already did to the deck (the counts ride the
    /// BuyResult; the rolled values are the climb lock's by now).
    private func completePlacementBuy(slot: Int, storeSlot s: StoreSlot, col: Int) {
        let res = campaign.buyMixedSlot(slot)
        guard res.ok else { return }
        let data = GameData.shared
        if s.kind == "samepower" {
            let prev = campaign.getSamePower()
            _ = campaign.equipSamePower(s.id)
            if let prev, prev != s.id {
                _ = campaign.discardSamePowerFromInventory(prev)
                _ = campaign.addCoins(sellValue(data.samePowerTypes.get(prev)))
            }
        } else {
            // A displaced occupant is sold (coins back) and DESTROYED —
            // placePillar/placeBase bounce it to inventory, so drop it there.
            let old = s.kind == "pillar" ? campaign.columnPillar(col) : campaign.columnBase(col)
            if s.kind == "pillar" { _ = campaign.placePillar(s.id, col: col) }
            else { _ = campaign.placeBase(s.id, col: col) }
            if let old, old != s.id {
                let reg = s.kind == "pillar" ? data.pillarTypes : data.baseTypes
                if s.kind == "pillar" { _ = campaign.discardPillarFromInventory(old) }
                else { _ = campaign.discardBaseFromInventory(old) }
                _ = campaign.addCoins(sellValue(reg.get(old)))
            }
        }
        Haptics.purchase()
        closeDetail()
        render()
        if let n = res.purgedCount {
            let rl = rankLabel(campaign.shopRolls[s.id]?.rank ?? s.rollRank) ?? "?"
            let label = data.pillarTypes.get(s.id)?.label ?? "Rank Purge"
            prompt.show("\(label): purged \(n) × \(rl)s from your deck.",
                        help: n == 0 ? "No \(rl)s were in your deck — the slot is yours anyway."
                                     : "Your deck is \(n) card\(n == 1 ? "" : "s") thinner, permanently.",
                        actions: [.init("OK", role: .plain) { [weak self] in self?.prompt.hide() }])
        } else if let n = res.transmutedCount {
            // v6.78: transmute recolors without re-ranking, so the deck's
            // most common rank after the buy is still the rank it targeted.
            let lock = campaign.shopRolls[s.id]
            let rl = rankLabel(campaign.mostCommonRank()) ?? "?"
            let suit = lock?.suit ?? s.rollSuit ?? "?"
            let label = data.baseTypes.get(s.id)?.label ?? "Transmute"
            prompt.show("\(label): \(n) × \(rl)s became \(suit).",
                        help: "Every \(rl) in your deck is now \(suit), permanently.",
                        actions: [.init("OK", role: .plain) { [weak self] in self?.prompt.hide() }])
        }
    }

    // MARK: - Mystery Same-Power reveal

    /// The buy revealed a concrete Same-Power: show it (detail panel, read-only)
    /// and ask KEEP (equip through the usual same-power purchase flow, incl.
    /// the displaced sell-back) or DISCARD (gone, no refund) on the shared
    /// prompt bar. MODAL — the money is spent; there is no backing out.
    private func revealMysterySamePower(_ def: ItemDef) {
        // v6.52: the decision lives INSIDE the reveal panel (Keep/Discard
        // buttons under the equipped→new comparison) — no prompt bar, no
        // "It's …" prefix; the panel names the power once.
        let d = StoreDetailView(campaign: campaign, revealedSamePower: def)
        d.onDiscard = { [weak self] in
            guard let self else { return }
            _ = self.campaign.discardSamePowerFromInventory(def.id)
            self.setMessage("\(def.label) discarded. The coins are spent either way.")
            self.closeDetail()
            self.render()
        }
        d.onKeep = { [weak self] in
            guard let self else { return }
            // The existing same-power purchase flow: equip, and a displaced
            // power is SOLD BACK (coins in, card destroyed).
            let prev = self.campaign.getSamePower()
            _ = self.campaign.equipSamePower(def.id)
            if let prev, prev != def.id {
                _ = self.campaign.discardSamePowerFromInventory(prev)
                _ = self.campaign.addCoins(self.sellValue(GameData.shared.samePowerTypes.get(prev)))
            }
            self.setMessage("\(def.label) equipped as your Same-Power.")
            self.closeDetail()
            self.render()
        }
        d.frame = view.bounds
        guard !UIAccessibility.isReduceMotionEnabled else {
            view.insertSubview(d, belowSubview: crt)
            detail = d
            return
        }
        // SHAKE-AND-LIGHT-UP first (v6.55): the bought "?" mark reappears
        // centre-screen over the scrim, shakes and flashes, and ONLY then
        // swaps to the revealed power — the gamble resolving on screen.
        playMysteryRevealFlash { [weak self] in
            guard let self else { return }
            self.view.insertSubview(d, belowSubview: self.crt)
            self.detail = d
            d.alpha = 0
            UIView.animate(withDuration: 0.15) { d.alpha = 1 }
        }
    }

    /// The mystery Same-Power's pre-reveal beat: the "?" mark over the
    /// store's own scrim (the detail sheet is already closed; nothing else is
    /// up), a scale-shake with a rotation wobble plus a phosphor flash, then
    /// `show` hands over to the reveal panel. One-shot keyframe tween,
    /// transform/alpha ONLY, self-terminating (§10) — ~0.6s total.
    private func playMysteryRevealFlash(_ show: @escaping () -> Void) {
        let cover = UIView(frame: view.bounds)
        cover.backgroundColor = CRT.ink.withAlphaComponent(0.72)   // the .confirm-overlay scrim
        let side: CGFloat = 96
        let art = UIImageView(image: ItemArt.mysterySamePower(width: side, height: side))
        art.layer.magnificationFilter = .nearest
        art.contentMode = .center
        art.frame = CGRect(x: (view.bounds.width - side) / 2,
                           y: (view.bounds.height - side) / 2,
                           width: side, height: side)
        // The light-up: a phosphor plate flaring past the mark's edges whose
        // alpha strobes over it — brightness via opacity, never a filter (§10).
        let flash = UIView(frame: art.bounds.insetBy(dx: -12, dy: -12))
        flash.backgroundColor = CRT.phosphor
        flash.alpha = 0
        flash.isUserInteractionEnabled = false
        art.addSubview(flash)
        cover.addSubview(art)
        view.insertSubview(cover, belowSubview: crt)
        // Screenshot harness: -revealHold 1 strikes the mid-shake pose (kick +
        // flash) and HOLDS it quiescent for a beat instead of tweening — the
        // XCUI screenshot daemon waits out in-flight animations, so a live
        // tween can never be captured mid-flight; a held frame can.
        if UserDefaults.standard.bool(forKey: "revealHold") {
            art.transform = CGAffineTransform(rotationAngle: -0.07).scaledBy(x: 1.14, y: 1.14)
            flash.alpha = 0.85
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                cover.removeFromSuperview()
                show()
            }
            return
        }
        UIView.animateKeyframes(withDuration: 0.45, delay: 0, options: [.calculationModeCubic]) {
            // The shake: two scale kicks with a wobble, settling to identity.
            UIView.addKeyframe(withRelativeStartTime: 0.0, relativeDuration: 0.22) {
                art.transform = CGAffineTransform(rotationAngle: -0.07).scaledBy(x: 1.14, y: 1.14)
            }
            UIView.addKeyframe(withRelativeStartTime: 0.22, relativeDuration: 0.22) {
                art.transform = CGAffineTransform(rotationAngle: 0.07).scaledBy(x: 0.93, y: 0.93)
            }
            UIView.addKeyframe(withRelativeStartTime: 0.44, relativeDuration: 0.24) {
                art.transform = CGAffineTransform(rotationAngle: -0.04).scaledBy(x: 1.08, y: 1.08)
            }
            UIView.addKeyframe(withRelativeStartTime: 0.68, relativeDuration: 0.32) {
                art.transform = .identity
            }
            // The flash rides the shake's back half, peaking just before the swap.
            UIView.addKeyframe(withRelativeStartTime: 0.4, relativeDuration: 0.3) {
                flash.alpha = 0.85
            }
            UIView.addKeyframe(withRelativeStartTime: 0.7, relativeDuration: 0.3) {
                flash.alpha = 0
            }
        } completion: { _ in
            cover.removeFromSuperview()
            show()
        }
    }

    // MARK: - Packs

    private func openPackReveal(packId: String, slot: Int, keep: Int) {
        // SEED1: a pack buy's contents key to (store node, slot).
        let keyId = offerNodeId ?? campaign.nodePos ?? 0
        let rng = runRng(seed: campaign.runSeed, [.s("storepack"), .n(keyId), .n(slot)])
        let result = campaign.revealPack(packId, rng: rng)
        let title = GameData.shared.packTypes.get(packId)?.label ?? "Pack"
        if result.kind == "card" {
            let vc = PackRevealViewController(campaign: campaign, title: title,
                                              content: .cards(result.cards),
                                              mode: .pick(keep: result.keep)) { [weak self] chosen in
                guard let self else { return }
                guard !chosen.isEmpty else { self.render(); return }
                for i in chosen { _ = self.campaign.addPackCard(result.cards[i]) }
                self.render()
                self.startPackKeepWalk(from: 0)
            }
            present(vc, animated: false)
        } else {
            let vc = PackRevealViewController(campaign: campaign, title: title,
                                              content: .stickers(result.stickers),
                                              mode: .pick(keep: result.keep)) { [weak self] chosen in
                guard let self else { return }
                guard !chosen.isEmpty else { self.render(); return }
                for i in chosen { _ = self.campaign.addStickerToInventory(result.stickers[i]) }
                self.render()
                // Only the JUST-PICKED stickers auto-walk (web index.html:
                // 30528-30537): stickers held from EARLIER visits stay for the
                // explicit GO TO MAP gate.
                self.walkNewStickers(chosen.map { result.stickers[$0] })
            }
            present(vc, animated: false)
        }
    }

    private func applyOwnedSticker(_ typeId: String) {
        let picker = CardPickerViewController(campaign: campaign,
                                              mode: .applySticker(typeId: typeId)) { [weak self] _ in
            self?.render()
        }
        present(picker, animated: false)
    }

    /// Apply pickers for a pack's just-granted stickers, back to back. The
    /// placement is COMMITTED: no ✕, and the scrim routes into the confirmed
    /// Skip — each sticker is either applied or explicitly discarded (no
    /// refund), so the walk always drains and the store never re-gates on it.
    private func walkNewStickers(_ ids: [String]) {
        guard let typeId = ids.first else { return }
        guard campaign.inventoryCount(typeId) > 0 else {
            walkNewStickers(Array(ids.dropFirst()))
            return
        }
        // Never open a picker with nothing to pick. A sticker no card can take
        // (Rocko's no-stickers rule, a suit the deck no longer holds, +1 Rank
        // with every card at Ace) used to show an all-greyed grid with no
        // explanation — the "I picked a sticker and couldn't apply it" case.
        // It stays in the inventory and the shelf keeps offering it.
        guard stickerHasTarget(typeId) else {
            let label = GameData.shared.stickerTypes.get(typeId)?.label ?? "That sticker"
            setMessage("\(label) has no card it can go on, so it's kept in your stickers.")
            walkNewStickers(Array(ids.dropFirst()))
            return
        }
        let picker = CardPickerViewController(campaign: campaign,
                                              mode: .applySticker(typeId: typeId)) { [weak self] _ in
            guard let self else { return }
            self.render()
            // Applied or confirm-discarded, the walk moves on either way —
            // the picker has no silent exit here (hidesClose + skip routing).
            self.walkNewStickers(Array(ids.dropFirst()))
        }
        picker.showsSkip = true
        picker.hidesClose = true
        present(picker, animated: false)
    }

    /// The PACK-KEEP walk: every held tray card gets a swap picker, back to
    /// back, until the tray drains. COMMITTED like the sticker walk: no ✕,
    /// scrim routes into the confirmed Skip, and a confirmed Skip DISCARDS
    /// that tray card (no refund) — every held card is resolved here, never
    /// parked for a later gate.
    private func startPackKeepWalk(from index: Int) {
        guard campaign.packTrayCount() > 0 else { render(); return }
        let total = campaign.packTrayCount()
        let stepNum = max(1, total - campaign.packTrayCount() + 1)
        let step = total > 1 ? " (\(stepNum) OF \(total))" : nil
        let picker = CardPickerViewController(campaign: campaign,
                                              mode: .swap(trayIndex: 0, step: step)) { [weak self] _ in
            guard let self else { return }
            self.render()
            // Chain to the next held card (the tray compacts to the front).
            if self.campaign.packTrayCount() > 0 {
                self.startPackKeepWalk(from: 0)
            }
        }
        picker.showsSkip = true
        picker.hidesClose = true
        present(picker, animated: false)
    }

    // MARK: - Reroll

    private func rerollTapped() {
        let cost = Int(campaign.storeRerollCost())
        let free = cost == 0
        prompt.show(free ? "Restock the shelf — the first one is free?"
                         : "Restock the shelf for ◉ \(cost)?",
                    help: free ? "The Queen's Restock covers it. Later restocks this visit climb in price."
                               : "Restocks climb in price within a shop visit.", actions: [
            .init("Cancel", role: .plain) { [weak self] in self?.prompt.hide() },
            .init("Restock", role: .gold) { [weak self] in
                guard let self else { return }
                self.prompt.hide()
                if self.campaign.rerollStore() {
                    Sound.shared.refresh()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    self.logShopRolls()   // the restocked shelf's rolls, climb-locked
                    self.render()
                }
            },
        ]) { [weak self] in self?.prompt.hide() }
    }

    private func goTapped() {
        // GO TO MAP locks while anything placeable is unplaced.
        if campaign.packTrayCount() > 0 {
            setMessage("Place your held cards first.")
            startPackKeepWalk(from: 0)
            return
        }
        // The gate keys off stickers that can actually BE placed (the web's
        // pendingBlockCount, index.html:30507-30520): a sticker with no legal
        // target (e.g. +1 Rank when every card is an Ace) must never bar exit.
        if let typeId = campaign.stickerInventory.first(where: { $0.value > 0 && stickerHasTarget($0.key) })?.key {
            setMessage("Apply your stickers first.")
            applyOwnedSticker(typeId)
            return
        }
        PersistenceHolder.shared?.checkpoint(campaign)
        delegate?.storeDone(self)
    }

    /// Read-only eligibility scan (the picker's `eligible` rule): does any deck
    /// card accept this sticker right now?
    private func stickerHasTarget(_ typeId: String) -> Bool {
        campaign.getRunDeck().contains { campaign.canApplySticker($0, typeId) }
    }

    // MARK: - Store key legend

    private func toggleKey() {
        if keyPanel != nil { closeKey(); return }
        let data = GameData.shared
        let panel = PixelPanelView(face: CRT.feltMid, border: CRT.ink)
        // The legend copy is FIXED, one line per kind (item batch 12) — the
        // icons still come from the registry, the words never do.
        var rows: [(UIImage, String)] = []
        if let d = data.items.stickers.first {
            rows.append((ItemArt.sticker(d, size: 40),
                         "Sticker: Sticks to one card. Fires when the card lands."))
        }
        if let d = data.items.pillars.first {
            rows.append((ItemArt.pillar(d, width: 34, height: 44),
                         "Pillar: Sits on a column. Always on."))
        }
        if let d = data.items.bases.first {
            rows.append((ItemArt.base(d, width: 44, height: 30),
                         "Base: Sits under a column. Tap to fire"))
        }
        if let d = data.items.samePowers.first {
            rows.append((ItemArt.samePower(d, width: 40, height: 40),
                         "Same-Power: Fires when you call Same correctly."))
        }
        rows.append((ItemArt.removal(width: 34, height: 44),
                     "Purge: Remove a card from the deck."))
        let panelW: CGFloat = min(view.bounds.width - 24, 340)
        let textW = panelW - 66 - 12
        var y: CGFloat = 12
        for (img, line) in rows {
            let iv = UIImageView(image: img)
            iv.contentMode = .scaleAspectFit
            iv.layer.magnificationFilter = .nearest
            iv.frame = CGRect(x: 12, y: y, width: 44, height: 44)
            panel.addSubview(iv)
            let l = CRTKit.label(line, size: 14, color: CRT.cardFace)
            l.numberOfLines = 0
            let h = ceil(l.sizeThatFits(CGSize(width: textW, height: 200)).height)
            let rowH = max(44, h)
            l.frame = CGRect(x: 66, y: y + (rowH - h) / 2, width: textW, height: h)
            panel.addSubview(l)
            y += rowH + 6
        }
        panel.frame = CGRect(x: (view.bounds.width - panelW) / 2,
                             y: TopShellView.height(safeTop: view.safeAreaInsets.top) + 52,
                             width: panelW, height: y + 8)
        // A clear full-screen catcher under the panel: a tap ANYWHERE — on the
        // legend or away from it — collapses it, and the tap goes nowhere else.
        let catcher = UIView(frame: view.bounds)
        catcher.backgroundColor = .clear
        catcher.addSubview(panel)
        catcher.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(closeKey)))
        view.insertSubview(catcher, belowSubview: crt)
        keyPanel = catcher
    }

    @objc private func closeKey() {
        keyPanel?.removeFromSuperview()
        keyPanel = nil
    }
}

// MARK: - Shelf tile

/// One shelf tile, web `.store-tile`: a pixel plaque (felt-mid face, ink
/// border, hard shadow) with a 4px rarity strip under the top edge
/// (common = quiet cream · uncommon = gold · rare = phosphor), the object
/// SMALL and centred on the shelf (web caps it per kind — sticker ≤68px,
/// base ≤46px, pack ≈100px, …), an optional name caption (packs + Removal
/// ONLY, web `.pf-name` / `.ro-lab`), and the gold-on-ink price chip — the
/// art/caption/price stack centres as one group. Unaffordable dims but stays
/// tappable.
final class StoreTileView: UIControl {
    private let art = UIImageView()
    /// The suit-restriction row — a SEPARATE little view parked ABOVE the
    /// chip (ItemArt.suitCaption contract); the chip's frame never changes.
    private let restrictionIcon = UIImageView()
    private let captionLabel = UILabel()
    private let priceLabel = UILabel()
    private let panel = PixelPanelView(face: CRT.feltMid, border: CRT.ink, shadowOffsetPx: 4)
    private let tierStrip = UIView()
    /// Web `.ti-obj` per-kind height caps (the object never fills the tile).
    private var artCap: CGFloat = 90
    var onTap: (() -> Void)?
    var onHold: (() -> Void)?
    var onHoldEnded: (() -> Void)?

    init(slot: Int) {
        super.init(frame: .zero)
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = "shelf-\(slot)"
        panel.isUserInteractionEnabled = false
        addSubview(panel)
        tierStrip.isUserInteractionEnabled = false
        panel.addSubview(tierStrip)
        art.contentMode = .scaleAspectFit
        art.layer.magnificationFilter = .nearest
        art.isUserInteractionEnabled = false
        addSubview(art)
        restrictionIcon.contentMode = .scaleAspectFit
        restrictionIcon.layer.magnificationFilter = .nearest
        restrictionIcon.isUserInteractionEnabled = false
        restrictionIcon.isHidden = true
        addSubview(restrictionIcon)
        captionLabel.textAlignment = .center
        captionLabel.isUserInteractionEnabled = false
        captionLabel.isHidden = true
        addSubview(captionLabel)
        priceLabel.textAlignment = .center
        priceLabel.backgroundColor = CRT.ink
        priceLabel.layer.borderWidth = 1
        priceLabel.layer.borderColor = CRT.gold.withAlphaComponent(0.4).cgColor
        addSubview(priceLabel)
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))
        hold.minimumPressDuration = 0.5   // the web's 500ms hold (index.html:28850)
        addGestureRecognizer(hold)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    @objc private func tapped() { if isEnabled { onTap?() } }
    @objc private func held(_ g: UILongPressGestureRecognizer) {
        // BOTH ends. The tile only ever reported `.began`, so store hold-help
        // opened and then had nothing to close it — it sat on screen until
        // something else redrew.
        switch g.state {
        case .began: onHold?()
        case .ended, .cancelled, .failed: onHoldEnded?()
        default: break
        }
    }

    func configure(art image: UIImage, kind: String, caption: String?,
                   restriction: UIImage? = nil, price: Int,
                   affordable: Bool, tier: String, locked: Bool) {
        isHidden = false
        art.image = image
        restrictionIcon.image = restriction
        restrictionIcon.isHidden = restriction == nil
        switch kind {
        case "sticker": artCap = 68
        case "base": artCap = 46
        case "pack": artCap = 100
        case "pillar": artCap = 100
        case "removal": artCap = 66
        case "card": artCap = 68
        case "samepower": artCap = 84
        default: artCap = 90
        }
        if let caption {
            // Web `.pf-name` is bright cream; `.ro-lab` hangs dimmer.
            let dim = kind == "removal"
            captionLabel.attributedText = CRTKit.attributed(
                caption.uppercased(), size: 14,
                color: CRT.cardFace.withAlphaComponent(dim ? 0.6 : 1))
            captionLabel.isHidden = false
        } else {
            captionLabel.attributedText = nil
            captionLabel.isHidden = true
        }
        // GREEN MEANS YOU CAN BUY IT. That is the one question this screen is
        // asked, so the whole window answers it: an affordable tile wears a
        // phosphor wash and a phosphor border, an unaffordable one stays plain
        // felt. Green used to encode RARITY here, which looked random —
        // uncommon-and-broke lit up while common-and-affordable did not.
        //
        // RARITY keeps its own quiet channel: the border hue when you can't
        // afford it, using the palette's rarity ramp (felt → cream → gold,
        // the same one the shop's Base gem uses). Never green, so the two
        // signals can't be confused again.
        let rarityHue: UIColor
        switch tier {
        case "rare":     rarityHue = CRT.gold
        case "uncommon": rarityHue = CRT.cardFace.withAlphaComponent(0.75)
        default:         rarityHue = CRT.ink
        }
        if affordable && !locked {
            panel.border = CRT.phosphor
            panel.face = CRT.feltMid.blended(with: CRT.phosphor, amount: 0.26)
        } else {
            panel.border = rarityHue
            panel.face = CRT.feltMid
        }
        tierStrip.isHidden = true
        isHidden = false
        // A zero price is a GIFT (Freebie / the joker's comp) — say FREE in
        // gold instead of quoting "◉ 0".
        priceLabel.attributedText = price == 0
            ? CRTKit.attributed("FREE", size: 18, color: CRT.gold, glow: true)
            : CRTKit.attributed("◉ \(price)", size: 18,
                                color: affordable ? CRT.gold : CRT.disabledText)
        priceLabel.isHidden = false
        // An item you cannot yet afford is still THERE — only its price chip
        // greys out. 0.5 on dark felt read as an empty slot; 0.75 reads as
        // "present, too expensive", which is the actual state.
        alpha = locked ? 0.4 : (affordable ? 1 : 0.75)
        isEnabled = !locked
    }

    func configureSold() {
        // A bought slot keeps its PLACE and says so. It used to set
        // `isHidden = true`, which punched a literal hole in the 3×2 shelf —
        // and with unaffordable tiles dimmed alongside it, one purchase could
        // read as several items "going missing". Now the plaque stays, empty
        // and captioned SOLD, so the shelf is always countable.
        art.image = nil
        restrictionIcon.image = nil
        restrictionIcon.isHidden = true
        captionLabel.attributedText = CRTKit.attributed("SOLD", size: 16, color: CRT.disabledText)
        captionLabel.isHidden = false
        tierStrip.isHidden = true
        panel.border = CRT.ink
        panel.face = CRT.feltMid
        priceLabel.isHidden = true
        isEnabled = false
        isHidden = false
        alpha = 0.45
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        panel.frame = bounds
        tierStrip.frame = CGRect(x: CRT.px, y: CRT.px, width: bounds.width - CRT.px * 2, height: 4)
        // The web tile is a centred flex column: object (capped), optional name
        // caption, price chip — the STACK centres as a group inside the plaque.
        let capH: CGFloat = captionLabel.isHidden ? 0 : 17
        let priceH: CGFloat = 20
        let gap: CGFloat = 6
        var stack = capH > 0 ? capH + gap : 0
        let availArt = bounds.height - 16 - priceH - gap - stack
        let artH = max(24, min(artCap, availArt))
        stack += artH + gap + priceH
        var y = (bounds.height - stack) / 2
        art.frame = CGRect(x: 6, y: y, width: bounds.width - 12, height: artH)
        y += artH + gap
        if capH > 0 {
            captionLabel.frame = CGRect(x: 2, y: y, width: bounds.width - 4, height: capH)
            y += capH + gap
        }
        let pw: CGFloat = 72
        priceLabel.frame = CGRect(x: (bounds.width - pw) / 2, y: y, width: pw, height: priceH)
        // The restriction row rides 2pt ABOVE the chip's aspect-fit rect —
        // the chip frame itself is untouched.
        if !restrictionIcon.isHidden, let img = restrictionIcon.image, let artImg = art.image {
            let fit = min(art.frame.width / artImg.size.width,
                          art.frame.height / artImg.size.height)
            let dw = artImg.size.width * fit, dh = artImg.size.height * fit
            let chipX = art.frame.minX + (art.frame.width - dw) / 2
            let chipTop = art.frame.minY + (art.frame.height - dh) / 2
            restrictionIcon.frame = CGRect(x: chipX + (dw - img.size.width) / 2,
                                           y: chipTop - 2 - img.size.height,
                                           width: img.size.width, height: img.size.height)
        }
    }
}

/// Purchase feedback: the warm cha-ching + a medium haptic thump together.
enum Haptics {
    static func purchase() {
        Sound.shared.purchase()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    /// Sale feedback: the reversed till (confirm, then the rising ting) + the
    /// same medium thump — a sale and a buy must not sound identical.
    static func sell() {
        Sound.shared.sell()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}
