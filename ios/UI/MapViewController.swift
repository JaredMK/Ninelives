import UIKit
import GameCore

/// What the map hands back to the flow that owns it. The map renders, gates,
/// travels and reveals; the OWNER dispatches what a node actually does
/// (launch a deal, open the store, resolve a pickup…).
public protocol MapScreenDelegate: AnyObject {
    /// The marker has arrived on `node` (mystery reveal, if any, already played).
    func mapArrived(at node: MapNode, on map: MapViewController)
    /// The corner menu button.
    func mapWantsMenu(_ map: MapViewController)
    /// The bottom-left STORE return (standing on a store node).
    func mapWantsStoreReturn(_ map: MapViewController)
    /// The deck chip — open the deck inspection.
    func mapWantsDeckInspect(_ map: MapViewController)
}

public extension MapScreenDelegate {
    func mapWantsStoreReturn(_ map: MapViewController) {}
    func mapWantsDeckInspect(_ map: MapViewController) {}
}

/// The progression map — the climb. Ported surface-for-surface from the web:
/// suit-tinted stage bands, routed dashed trail edges (travelled = phosphor),
/// node plaques per type/state, one-stage-at-a-time scroll gating with the fog
/// veil, elastic overscroll with the bottom Easter egg, the parallax dot-field
/// background, the spotlight riding the character, and the travel animation
/// along the exact routed curves.
public final class MapViewController: UIViewController, UIScrollViewDelegate {

    // Layout constants, verbatim from the web.
    static let rowH: CGFloat = 104
    static let pad: CGFloat = 46
    static let mapW: CGFloat = 348
    static let minGap: CGFloat = 60
    static let homeGap: CGFloat = 40

    public let campaign: CampaignState
    public weak var delegate: MapScreenDelegate?
    private let runMap: RunMap
    private let economy = Economy()

    private let scroll = UIScrollView()
    private let track = UIView()          // the .phase-map — MAP_W wide, centred
    private let bgView = UIImageView()    // parallax dot field
    private let edgesView = UIImageView() // all trail edges, baked per render
    private let dimView = UIView()        // the map-wide dim above the nodes
    private let spotView = UIImageView()  // warm spotlight riding the character
    private let veilView = UIView()       // fog over not-yet-unlocked stages
    private let eggLabel = UILabel()      // the bottom-overscroll Easter egg
    private let avatar = MapAvatarView()
    private let crt = CRTOverlayUIView()
    private let tissue = TissueView()     // #tissue, visible at the scroll's bounce edges
    private var nodeViews: [Int: MapNodeView] = [:]
    private let keyButton = PixelButtonView("?", role: .plain, fontSize: 16)
    private let storeButton = PixelButtonView("STORE", role: .gold, fontSize: 14)
    private var keyPanel: UIView?
    private let shell = TopShellView()

    private var scrollLock: CGFloat = 0
    private var traveling = false
    private var layoutX: [Int: CGFloat] = [:]   // buildMapLayout cache
    /// One egg phrase per deal: session salt + deals completed.
    private static let eggSalt = Int.random(in: 0..<MapViewController.eggLines.count)
    /// Debug: long-press any node to jump straight to it.
    public var debugJumpEnabled = false

    public init(campaign: CampaignState) {
        self.campaign = campaign
        self.runMap = RunMap(data: GameData.shared)
        runMap.setDifficultyTier(campaign.difficultyTier)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    public override var prefersStatusBarHidden: Bool { true }

    // MARK: - View setup

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = CRT.feltDeep

        tissue.frame = view.bounds
        tissue.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(tissue)

        scroll.delegate = self
        scroll.alwaysBounceVertical = true
        scroll.showsVerticalScrollIndicator = false
        scroll.contentInsetAdjustmentBehavior = .never
        view.addSubview(scroll)

        bgView.image = nil
        bgView.backgroundColor = UIColor(patternImage: MapArt.backgroundTile())
        scroll.addSubview(bgView)

        track.clipsToBounds = false
        scroll.addSubview(track)

        edgesView.contentMode = .topLeft
        edgesView.layer.magnificationFilter = .nearest
        track.addSubview(edgesView)

        dimView.backgroundColor = CRT.ink.withAlphaComponent(0.3)
        dimView.isUserInteractionEnabled = false
        spotView.isUserInteractionEnabled = false

        veilView.backgroundColor = CRT.feltDeep.withAlphaComponent(0.94)
        veilView.isUserInteractionEnabled = false

        eggLabel.font = CRT.Font.of(15)
        eggLabel.textColor = CRT.muted
        eggLabel.textAlignment = .center
        scroll.addSubview(eggLabel)

        // The persistent top shell: HUD line + deck/histogram band.
        shell.onMenu = { [weak self] in
            guard let self else { return }
            self.delegate?.mapWantsMenu(self)
        }
        shell.onDeckTap = { [weak self] in self?.deckTapped() }
        view.addSubview(shell)
        keyButton.onTap = { [weak self] in self?.toggleKey() }
        view.addSubview(keyButton)
        storeButton.isHidden = true
        storeButton.onTap = { [weak self] in
            guard let self else { return }
            self.delegate?.mapWantsStoreReturn(self)
        }
        view.addSubview(storeButton)

        crt.isUserInteractionEnabled = false
        view.addSubview(crt)

        render()
    }

    @objc private func deckTapped() {
        delegate?.mapWantsDeckInspect(self)
    }

    private var didInitialCenter = false
    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let b = view.bounds
        let shellH = TopShellView.height(safeTop: view.safeAreaInsets.top)
        shell.frame = CGRect(x: 0, y: 0, width: b.width, height: shellH)
        scroll.frame = CGRect(x: 0, y: shellH, width: b.width, height: b.height - shellH)
        crt.frame = b
        keyButton.frame = CGRect(x: b.width - 48, y: shellH + 8, width: 40, height: 34)
        storeButton.frame = CGRect(x: 10, y: b.height - view.safeAreaInsets.bottom - 46,
                                   width: 86, height: 38)
        layoutContent()
        if !didInitialCenter, campaign.runMap != nil {
            didInitialCenter = true
            centerOnAvatar(animated: false)
        }
    }

    private func layoutContent() {
        guard let map = campaign.runMap else { return }
        let height = MapViewController.mapHeight(rows: map.totalRows)
        let x = (view.bounds.width - MapViewController.mapW) / 2
        track.frame = CGRect(x: x, y: 0, width: MapViewController.mapW, height: height)
        scroll.contentSize = CGSize(width: view.bounds.width, height: height)
        bgView.frame = CGRect(x: 0, y: -480, width: view.bounds.width, height: height + 960)
        eggLabel.frame = CGRect(x: 0, y: height + 16, width: view.bounds.width, height: 22)
        // One-stage-at-a-time: the minimum offset is the lock line, and the
        // native rubber band operates AT it (fog shows above during the pull).
        scroll.contentInset = UIEdgeInsets(top: -scrollLock, left: 0, bottom: 0, right: 0)
    }

    // MARK: - Layout math (ported verbatim)

    public static func mapHeight(rows R: Int) -> CGFloat {
        pad * 2 + CGFloat(R - 1) * rowH + homeGap
    }
    public static func homeXY(rows R: Int) -> CGPoint {
        CGPoint(x: mapW / 2, y: mapHeight(rows: R) - pad * 0.55)
    }

    /// Per-row spacing: push same-row nodes to MIN_GAP apart, re-centre.
    static func buildLayout(_ map: RunMapGraph) -> [Int: CGFloat] {
        let usable = mapW - 2 * pad, lo = pad, hi = mapW - pad
        var byRow: [Int: [MapNode]] = [:]
        for n in map.nodes { byRow[n.row, default: []].append(n) }
        var xById: [Int: CGFloat] = [:]
        for (_, rowNodes) in byRow {
            let row = rowNodes.sorted { $0.x < $1.x }
            var px = row.map { lo + CGFloat($0.x) * usable }
            for i in 1..<max(1, px.count) where px[i] < px[i - 1] + minGap { px[i] = px[i - 1] + minGap }
            let span = (px.last ?? lo) - (px.first ?? lo)
            var shift = (lo + hi) / 2 - ((px.first ?? lo) + span / 2)
            if let f = px.first, f + shift < lo { shift = lo - f }
            if let l = px.last, l + shift > hi { shift = hi - l }
            for (i, n) in row.enumerated() { xById[n.id] = px[i] + shift }
        }
        return xById
    }

    func nodeXY(_ n: MapNode, rows R: Int) -> CGPoint {
        let x = layoutX[n.id] ?? (MapViewController.pad + CGFloat(n.x) * (MapViewController.mapW - 2 * MapViewController.pad))
        return CGPoint(x: x, y: MapViewController.pad + CGFloat(R - 1 - n.row) * MapViewController.rowH)
    }

    /// Edge routing: quadratic control point clear of every non-endpoint node.
    func routeControl(_ A: CGPoint, _ B: CGPoint, fromId: Int?, toId: Int?) -> CGPoint {
        guard let map = campaign.runMap else { return CGPoint(x: (A.x + B.x) / 2, y: (A.y + B.y) / 2) }
        let R = map.totalRows
        let avoid = map.nodes.filter { $0.id != fromId && $0.id != toId }.map { n -> (CGPoint, CGFloat, CGFloat) in
            let h = MapArt.nodeHalf(n.type)
            return (nodeXY(n, rows: R), h.w, h.h)
        }
        func hits(_ Q: CGPoint) -> Bool {
            for i in 1..<24 {
                let t = CGFloat(i) / 24, it = 1 - t
                let px = it * it * A.x + 2 * it * t * Q.x + t * t * B.x
                let py = it * it * A.y + 2 * it * t * Q.y + t * t * B.y
                for (o, hw, hh) in avoid where abs(px - o.x) < hw && abs(py - o.y) < hh { return true }
            }
            return false
        }
        let mx = (A.x + B.x) / 2, my = (A.y + B.y) / 2
        let dx = B.x - A.x, dy = B.y - A.y
        let len = max(1, hypot(dx, dy))
        let nx = -dy / len, ny = dx / len
        let sign: CGFloat = ((Int(A.x) + Int(A.y)) % 2 != 0) ? 1 : -1
        var cands: [CGFloat] = [min(13, len * 0.12) * sign]
        var mag: CGFloat = 26
        while mag <= 175 { cands.append(mag * sign); cands.append(-mag * sign); mag += 16 }
        for c in cands {
            let Q = CGPoint(x: mx + nx * c, y: my + ny * c)
            if !hits(Q) { return Q }
        }
        return CGPoint(x: mx + nx * 175 * sign, y: my + ny * 175 * sign)
    }

    // MARK: - Render

    public func render(arrivedAt: Int? = nil) {
        guard isViewLoaded, let map = campaign.runMap else { return }
        layoutX = MapViewController.buildLayout(map)
        let R = map.totalRows
        let height = MapViewController.mapHeight(rows: R)
        let cleared = Set(campaign.clearedNodes)
        let legal = Set(campaign.legalNextNodes().map(\.id))
        let pos = campaign.nodePos

        // ---- stage bands ----
        track.subviews.filter { $0.tag == 901 }.forEach { $0.removeFromSuperview() }
        for ph in map.phases {
            let topRow = ph.rowStart + ph.rows - 1, botRow = ph.rowStart
            let yTop = MapViewController.pad + CGFloat(R - 1 - topRow) * MapViewController.rowH - MapViewController.rowH * 0.5
            let yBot = MapViewController.pad + CGFloat(R - 1 - botRow) * MapViewController.rowH + MapViewController.rowH * 0.55
            let top = max(0, yTop), h = min(height, yBot) - top
            let band = UIView(frame: CGRect(x: 0, y: top, width: MapViewController.mapW, height: h))
            band.tag = 901
            band.isUserInteractionEnabled = false
            // Flat felt-mid lifts, alpha stepping up the climb (♦ .14 → ♣ .24 → ♠ .34).
            band.backgroundColor = CRT.feltMid.withAlphaComponent(MapViewController.bandFillAlpha(ph.suit))
            track.insertSubview(band, at: 0)
            // The hand-off label: LEFT-pinned, uppercase, in the phase's suit colour.
            let label = CRTKit.label(MapViewController.bandLabel(campaign: campaign, ph: ph).uppercased(),
                                     size: 13, color: MapViewController.bandLabelColor(ph.suit))
            label.tag = 901
            label.alpha = 0.8
            label.sizeToFit()
            label.frame.origin = CGPoint(x: 10, y: min(height, yBot) - 24)
            track.addSubview(label)
        }

        // ---- edges (one baked image) ----
        edgesView.frame = CGRect(x: 0, y: 0, width: MapViewController.mapW, height: height)
        edgesView.image = bakeEdges(map: map, cleared: cleared, pos: pos, R: R, height: height)

        // ---- nodes ----
        var seen = Set<Int>()
        for n in map.nodes {
            seen.insert(n.id)
            let p = nodeXY(n, rows: R)
            let state: MapNodeView.State = cleared.contains(n.id) ? .done
                : (n.id == pos ? .here : (legal.contains(n.id) ? .legal : .far))
            let v = nodeViews[n.id] ?? {
                let v = MapNodeView(id: n.id)
                v.onTap = { [weak self] id in self?.nodeTapped(id) }
                v.onLongPress = { [weak self] id in self?.nodeLongPressed(id) }
                nodeViews[n.id] = v
                track.addSubview(v)
                return v
            }()
            v.center = p
            v.configure(art: artFor(node: n, state: state), state: state,
                        hidden: campaign.nodeHidden(n.id),
                        interactive: state == .legal || debugJumpEnabled)
            if arrivedAt == n.id { v.playArrive() }
        }
        // The HOME/origin node.
        let homeId = -9999
        seen.insert(homeId)
        let home = nodeViews[homeId] ?? {
            let v = MapNodeView(id: homeId)
            nodeViews[homeId] = v
            track.addSubview(v)
            return v
        }()
        home.center = MapViewController.homeXY(rows: R)
        home.configure(art: MapArt.homeHut(mama: false), state: pos == nil ? .here : .done,
                       hidden: false, interactive: false)
        // Drop views for nodes that vanished (endless regeneration).
        for (id, v) in nodeViews where !seen.contains(id) {
            v.removeFromSuperview()
            nodeViews.removeValue(forKey: id)
        }

        // ---- dim + spotlight + avatar (persistent, re-attached on top) ----
        dimView.frame = CGRect(x: 0, y: 0, width: MapViewController.mapW, height: height)
        track.addSubview(dimView)
        let spotD: CGFloat = 240
        spotView.image = MapArt.spotlight(diameter: spotD)
        spotView.bounds = CGRect(x: 0, y: 0, width: spotD, height: spotD)
        track.addSubview(spotView)
        avatar.configure(deckId: campaign.deckId, tier: campaign.difficultyTier)
        avatar.setCount(campaign.deckSize())
        avatar.setWorried(reachIsThreatening())
        track.addSubview(avatar)
        if !traveling {
            let xy = avatarXY()
            avatar.center = xy
            spotView.center = xy
        }

        // ---- stage gating + fog veil ----
        // ONE STAGE AT A TIME: scroll is clamped so nothing above the current
        // stage can be brought into view; the boss falling unlocks the next
        // stage's range. Applies from the very start (phase 0) — only standing
        // ON a home node (post-win wander) lifts it.
        scrollLock = 0
        let curNode = pos.flatMap { map.byId[$0] }
        if curNode?.type != "home" {
            let curPhase = curNode?.phase ?? 0
            let curMeta = map.phases.first { $0.phase == curPhase }
            let bossDown = (curMeta?.bossIds.isEmpty == false)
                && curMeta!.bossIds.allSatisfy { cleared.contains($0) }
            let unlockPhase = (bossDown && map.phases.contains { $0.phase == curPhase + 1 })
                ? curPhase + 1 : curPhase
            if let ph = map.phases.first(where: { $0.phase == unlockPhase }) {
                let topRow = ph.rowStart + ph.rows - 1
                var lockY = MapViewController.pad + CGFloat(R - 1 - topRow) * MapViewController.rowH - MapViewController.rowH * 0.55
                for id in legal {
                    guard let n = map.byId[id] else { continue }
                    lockY = min(lockY, nodeXY(n, rows: R).y - 52)
                }
                scrollLock = max(0, lockY.rounded())
            }
        }
        veilView.removeFromSuperview()
        if scrollLock > 0 {
            veilView.frame = CGRect(x: -60, y: -600, width: MapViewController.mapW + 120, height: scrollLock + 600)
            track.addSubview(veilView)
        }

        // ---- shell + egg + the store-return button ----
        storeButton.isHidden = campaign.currentNode()?.type != "store"
        shell.sync(campaign: campaign)
        eggLabel.text = MapViewController.eggLines[
            (MapViewController.eggSalt + campaign.runsCompleted) % MapViewController.eggLines.count]

        layoutContent()
        if scroll.contentOffset.y < scrollLock {
            scroll.contentOffset.y = scrollLock
        }
    }

    static func bandLabel(campaign: CampaignState, ph: PhaseMeta) -> String {
        if campaign.rules().altSuits {
            return ph.phase >= campaign.phasesTotal() ? "Endless ★" : "Stage \(ph.phase + 1)"
        }
        return "\(suitName(ph.suit)) \(ph.suit)"
    }

    static func suitName(_ s: String) -> String {
        switch s {
        case "♦": return "Diamonds"; case "♣": return "Clubs"
        case "♠": return "Spades"; case "♥": return "Hearts"
        default: return "Endless"
        }
    }
    static func suitTint(_ s: String) -> UIColor {
        switch s {
        case "♦", "♥": return CRT.suitRed
        case "♣": return CRT.phosphor
        case "♠": return CRT.cardFace
        default: return CRT.gold
        }
    }
    /// Web `.pm-band` fills: felt-mid at .14/.24/.34, stepping up the climb.
    static func bandFillAlpha(_ s: String) -> CGFloat {
        switch s {
        case "♣": return 0.24
        case "♠": return 0.34
        default: return 0.14
        }
    }
    /// Web `.pm-band-label` colours: ♦ suit-red · ♣ card-face · ♠ gold.
    static func bandLabelColor(_ s: String) -> UIColor {
        switch s {
        case "♣": return CRT.cardFace
        case "♠": return CRT.gold
        case "♥": return CRT.cardFace
        default: return CRT.suitRed
        }
    }

    private func reachIsThreatening() -> Bool {
        campaign.legalNextNodes().contains { n in
            !campaign.nodeHidden(n.id)
                && (n.type == "boss" || (n.type == "deal" && (n.piles ?? 99) <= 4))
        }
    }

    // MARK: - Node art

    private func artFor(node n: MapNode, state: MapNodeView.State) -> UIImage {
        if campaign.nodeHidden(n.id) || n.type == "mystery" {
            return MapArt.mysteryCard(open: state == .here)
        }
        switch n.type {
        case "boss": return composeDeal(n, big: true)
        case "deal": return composeDeal(n, big: false)
        case "store": return MapArt.shopStall()
        case "home": return MapArt.homeHut(mama: true)
        case "pass": return MapArt.passDot(done: campaign.nodeCleared(n.id))
        case "pack":
            let pair = campaign.packNodeCards(n)
            if pair.count == 2 { return composePack2(pair) }
            return composePackStack(n)
        default:
            if let card = campaign.nodeCard(n) ?? campaign.previewPickupCard(n) {
                return CardArt.image(CardArt.Face(card), scale: .half)
            }
            return MapArt.packStack(deckId: campaign.deckId)
        }
    }

    private func composeDeal(_ n: MapNode, big: Bool) -> UIImage {
        let cluster = MapArt.synapseCluster(big: big)
        let stage = (n.phase ?? 0) + 1
        let rating = big ? 3 : runMap.difficultyScore(targetD: n.targetD ?? 0, phaseIndex: n.phase, isBoss: false)
        let chip = MapArt.rewardChip(Int(economy.dealFlat(stage: stage, rating: rating, isBoss: big)))
        let w = max(cluster.size.width, chip.size.width)
        let h = cluster.size.height + chip.size.height - 6
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: fmt).image { _ in
            cluster.draw(at: CGPoint(x: (w - cluster.size.width) / 2, y: 0))
            chip.draw(at: CGPoint(x: (w - chip.size.width) / 2, y: cluster.size.height - 6))
        }
    }

    private func composePackStack(_ n: MapNode) -> UIImage {
        let stack = MapArt.packStack(deckId: campaign.deckId)
        let anySuit = campaign.rules().altSuits
        let badge = MapArt.lootBadge("+\(n.packCount ?? 3)" + (anySuit ? "" : " \(n.suit ?? "")"))
        let w = max(stack.size.width, badge.size.width)
        let h = stack.size.height + 8
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: fmt).image { _ in
            stack.draw(at: CGPoint(x: (w - stack.size.width) / 2, y: 0))
            badge.draw(at: CGPoint(x: (w - badge.size.width) / 2, y: h - badge.size.height))
        }
    }

    private func composePack2(_ pair: [CardSpec]) -> UIImage {
        let a = CardArt.image(CardArt.Face(pair[0]), scale: .half)
        let b = CardArt.image(CardArt.Face(pair[1]), scale: .half)
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 64, height: 62), format: fmt).image { ctx in
            let cg = ctx.cgContext
            cg.saveGState()
            cg.translateBy(x: 20, y: 31); cg.rotate(by: -9 * .pi / 180)
            a.draw(in: CGRect(x: -19, y: -27, width: 38, height: 54))
            cg.restoreGState()
            cg.saveGState()
            cg.translateBy(x: 44, y: 31); cg.rotate(by: 9 * .pi / 180)
            b.draw(in: CGRect(x: -19, y: -27, width: 38, height: 54))
            cg.restoreGState()
        }
    }

    // MARK: - Edges

    private func bakeEdges(map: RunMapGraph, cleared: Set<Int>, pos: Int?, R: Int, height: CGFloat) -> UIImage {
        PixelTexture.image(size: CGSize(width: MapViewController.mapW, height: height)) { cg in
            func draw(_ a: CGPoint, _ b: CGPoint, active: Bool, done: Bool, fromId: Int?, toId: Int?) {
                let Q = routeControl(a, b, fromId: fromId, toId: toId)
                let color = done ? CRT.phosphor
                    : CRT.cardFace.withAlphaComponent(active ? 0.55 : 0.3)
                cg.setStrokeColor(color.cgColor)
                cg.setLineWidth(4)
                cg.setLineDash(phase: 0, lengths: [8, 6])
                cg.move(to: a)
                cg.addQuadCurve(to: b, control: Q)
                cg.strokePath()
                // The small square signal dot at the curve's midpoint.
                cg.setLineDash(phase: 0, lengths: [])
                cg.setFillColor(color.cgColor)
                let dx = 0.25 * a.x + 0.5 * Q.x + 0.25 * b.x
                let dy = 0.25 * a.y + 0.5 * Q.y + 0.25 * b.y
                cg.fill(CGRect(x: dx - 2, y: dy - 2, width: 4, height: 4))
            }
            for n in map.nodes {
                let a = nodeXY(n, rows: R)
                for mid in n.next {
                    guard let m = map.byId[mid] else { continue }
                    draw(a, nodeXY(m, rows: R), active: n.id == pos,
                         done: cleared.contains(n.id) && cleared.contains(mid),
                         fromId: n.id, toId: mid)
                }
            }
            let homeXY = MapViewController.homeXY(rows: R)
            for id in map.row0 {
                guard let m = map.byId[id] else { continue }
                draw(homeXY, nodeXY(m, rows: R), active: pos == nil,
                     done: cleared.contains(id), fromId: nil, toId: id)
            }
        }
    }

    // MARK: - Position + camera

    private func avatarXY() -> CGPoint {
        guard let map = campaign.runMap else { return .zero }
        let R = map.totalRows
        guard let pos = campaign.nodePos, let n = map.byId[pos] else {
            return MapViewController.homeXY(rows: R)
        }
        return nodeXY(n, rows: R)
    }

    public func centerOnAvatar(animated: Bool) {
        let y = avatar.center.y - scroll.bounds.height / 2
        let maxY = max(scrollLock, scroll.contentSize.height - scroll.bounds.height)
        scroll.setContentOffset(CGPoint(x: 0, y: min(maxY, max(scrollLock, y))), animated: animated)
    }

    public func scrollViewDidScroll(_ s: UIScrollView) {
        // One-speed parallax: the dot field trails the scroll.
        bgView.transform = CGAffineTransform(translationX: 0, y: s.contentOffset.y * 0.35)
    }

    // MARK: - Node interaction

    private func nodeTapped(_ id: Int) {
        guard !traveling else { return }
        guard campaign.legalNextNodes().contains(where: { $0.id == id }) else { return }
        Sound.shared.tap()
        travel(to: id)
    }

    private func nodeLongPressed(_ id: Int) {
        guard debugJumpEnabled, !traveling else { return }
        // Debug jump: teleport the run to the node (no travel, no resolution).
        _ = campaign.moveToNode(id)
        campaign.revealNode(id)
        render()
        centerOnAvatar(animated: true)
    }

    /// Tap a legal node → glide over any pass points, ride each routed edge,
    /// then reveal (mystery) and hand arrival to the delegate.
    public func travel(to id: Int) {
        guard let map = campaign.runMap, let node = campaign.getNode(id) else { return }
        let fromId = campaign.nodePos
        let fromXY = avatarXY()
        let glide = passPath(to: id, from: fromId)
        let wasHidden = campaign.nodeHidden(id)
        guard campaign.moveToNode(id) else { return }
        if wasHidden { campaign.revealNode(id) }
        for pid in glide { _ = campaign.markNodeCleared(pid) }
        let R = map.totalRows
        var legs: [(id: Int, xy: CGPoint)] = glide.compactMap { pid in
            map.byId[pid].map { (pid, nodeXY($0, rows: R)) }
        }
        legs.append((id, nodeXY(node, rows: R)))

        traveling = true
        var idx = 0
        var curId = fromId
        var curXY = fromXY
        func next() {
            if idx >= legs.count {
                traveling = false
                if wasHidden {
                    playMysteryReveal(id) { [weak self] in
                        guard let self else { return }
                        self.delegate?.mapArrived(at: node, on: self)
                    }
                } else {
                    render(arrivedAt: id)
                    delegate?.mapArrived(at: node, on: self)
                }
                return
            }
            let leg = legs[idx]; idx += 1
            let pId = curId, pXY = curXY
            curId = leg.id; curXY = leg.xy
            animateTravel(from: pXY, to: leg.xy, fromId: pId, toId: leg.id, completion: next)
        }
        next()
    }

    private func passPath(to targetId: Int, from fromId: Int?) -> [Int] {
        guard let map = campaign.runMap else { return [] }
        let startIds = fromId == nil ? map.row0 : (map.byId[fromId!]?.next ?? [])
        if startIds.contains(targetId) { return [] }
        for pid in startIds {
            var path: [Int] = []
            var cur = map.byId[pid]
            while let c = cur, c.type == "pass" {
                path.append(c.id)
                if c.next.contains(targetId) { return path }
                cur = c.next.count == 1 ? map.byId[c.next[0]] : nil
            }
        }
        return []
    }

    /// The 420ms hop along the routed curve; the spotlight glides the same
    /// curve without the hop.
    private func animateTravel(from: CGPoint, to: CGPoint, fromId: Int?, toId: Int?,
                               completion: @escaping () -> Void) {
        let Q = routeControl(from, to, fromId: fromId, toId: toId)
        var hopPts: [CGPoint] = []
        var glidePts: [CGPoint] = []
        for i in 0...12 {
            let t = CGFloat(i) / 12, it = 1 - t
            let px = it * it * from.x + 2 * it * t * Q.x + t * t * to.x
            let py = it * it * from.y + 2 * it * t * Q.y + t * t * to.y
            hopPts.append(CGPoint(x: px, y: py - sin(t * .pi) * 4))
            glidePts.append(CGPoint(x: px, y: py))
        }
        avatar.walkBounce(on: true)
        let anim = CAKeyframeAnimation(keyPath: "position")
        anim.values = hopPts.map { NSValue(cgPoint: $0) }
        anim.duration = 0.42
        anim.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0.05, 0.3, 1)
        avatar.layer.add(anim, forKey: "travel")
        let spotAnim = CAKeyframeAnimation(keyPath: "position")
        spotAnim.values = glidePts.map { NSValue(cgPoint: $0) }
        spotAnim.duration = 0.42
        spotAnim.timingFunction = anim.timingFunction
        spotView.layer.add(spotAnim, forKey: "travel")
        avatar.center = to
        spotView.center = to
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.44) { [weak self] in
            self?.avatar.walkBounce(on: false)
            completion()
        }
        // Keep the camera with the character.
        let targetY = to.y - scroll.bounds.height / 2
        let maxY = max(scrollLock, scroll.contentSize.height - scroll.bounds.height)
        let clamped = min(maxY, max(scrollLock, targetY))
        if abs(clamped - scroll.contentOffset.y) > 40 {
            scroll.setContentOffset(CGPoint(x: 0, y: clamped), animated: true)
        }
    }

    /// The mystery reveal pop: the "?" flips in from small + tilted, holds a
    /// beat so the surprise reads, then continues.
    private func playMysteryReveal(_ id: Int, completion: @escaping () -> Void) {
        render()
        guard let v = nodeViews[id] else { completion(); return }
        v.transform = CGAffineTransform(scaleX: 0.3, y: 0.3).rotated(by: -12 * .pi / 180)
        UIView.animate(withDuration: 0.36, delay: 0, usingSpringWithDamping: 0.6,
                       initialSpringVelocity: 0.4) {
            v.transform = .identity
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.72, execute: completion)
    }

    /// Fly collected card(s) into the character: bounce, tick the badge up.
    public func collectCards(_ cards: [CardSpec], completion: (() -> Void)? = nil) {
        let total = campaign.deckSize()
        var shown = max(0, total - cards.count)
        avatar.setCount(shown)
        avatar.collectBounce()
        if !cards.isEmpty { Sound.shared.mapAdd() }
        let toPt = avatar.center
        for (i, card) in cards.prefix(5).enumerated() {
            let img = UIImageView(image: CardArt.image(CardArt.Face(card), scale: .half))
            img.bounds = CGRect(x: 0, y: 0, width: 24, height: 33)
            img.contentMode = .scaleAspectFit
            UIFly.fly(img, in: track, from: CGPoint(x: toPt.x, y: toPt.y + 18), to: toPt,
                      duration: 0.3, delay: Double(i) * 0.07, startScale: 0.65) { [weak self] in
                shown = min(total, shown + 1)
                self?.avatar.setCount(shown)
                self?.avatar.bumpBadge()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3 + Double(min(cards.count, 5)) * 0.07 + 0.2) {
            completion?()
        }
    }

    // MARK: - Map key

    private func toggleKey() {
        if let k = keyPanel { k.removeFromSuperview(); keyPanel = nil; return }
        let panel = PixelPanelView(face: CRT.feltMid, border: CRT.ink)
        let rows: [(UIImage, String, String)] = [
            (MapArt.synapseCluster(big: false), "Deal", "Survive the piles · reward on the chip"),
            (MapArt.synapseCluster(big: true), "Boss", "Full deck · clears the stage"),
            (MapArt.shopStall(), "Shop", "Spend coins between deals"),
            (MapArt.packStack(deckId: campaign.deckId), "Pack", "Pick from hidden cards"),
            (CardArt.image(CardArt.Face(label: "7", suit: "♦", kind: .normal), scale: .half), "Card", "Joins your deck"),
            (MapArt.mysteryCard(open: false), "Mystery", "A gamble — good or bad"),
            (MapArt.homeHut(mama: true), "Home", "Mama ♥ is waiting"),
        ]
        var y: CGFloat = 12
        for (img, name, sub) in rows {
            let iv = UIImageView(image: img)
            iv.contentMode = .scaleAspectFit
            iv.layer.magnificationFilter = .nearest
            iv.frame = CGRect(x: 12, y: y, width: 44, height: 40)
            panel.addSubview(iv)
            let nameL = CRTKit.label(name, size: 16, color: CRT.cardFace)
            nameL.frame = CGRect(x: 66, y: y + 2, width: 200, height: 18)
            panel.addSubview(nameL)
            let subL = CRTKit.label(sub, size: 13, color: CRT.muted)
            subL.frame = CGRect(x: 66, y: y + 20, width: 210, height: 16)
            panel.addSubview(subL)
            y += 46
        }
        panel.frame = CGRect(x: (view.bounds.width - 300) / 2,
                             y: TopShellView.height(safeTop: view.safeAreaInsets.top) + 46,
                             width: 300, height: y + 8)
        view.insertSubview(panel, belowSubview: crt)
        keyPanel = panel
        let tap = UITapGestureRecognizer(target: self, action: #selector(closeKey))
        panel.addGestureRecognizer(tap)
    }

    @objc private func closeKey() {
        keyPanel?.removeFromSuperview()
        keyPanel = nil
    }

    // MARK: - Egg lines (verbatim)

    static let eggLines = [
        "Up is home.",
        "Calling Same on a Joker always lands — it banks the Same shield AND fires your Same-Power.",
        "Mama's waiting at the top.",
        "A correct Same banks a shield that saves a pile from death. It never stacks — spend it.",
        "Nothing down here but felt.",
        "Ties kill on Higher or Lower — call Same, or carry a Same-Safe.",
        "Anchor a tiny pile and it stops dragging your payout down.",
        "Pinky believes in you.",
        "Rerolls climb in price within a shop visit — next store, fresh price.",
        "Bosses always deal your whole deck. Keep it lean.",
    ]
}

// MARK: - Node view

/// One node plaque: baked art + the state chrome (gold legal ring with its
/// compositor-only pulse, phosphor here ring + glow, the done ✓, far/done dim).
final class MapNodeView: UIView {
    enum State { case far, legal, here, done }

    let id: Int
    private let art = UIImageView()
    private let ringDim = CALayer()
    private let ringBright = CALayer()
    private var check: UILabel?
    var onTap: ((Int) -> Void)?
    var onLongPress: ((Int) -> Void)?
    private var state: State = .far

    init(id: Int) {
        self.id = id
        super.init(frame: CGRect(x: 0, y: 0, width: 60, height: 60))
        art.contentMode = .center
        art.layer.magnificationFilter = .nearest
        addSubview(art)
        ringDim.borderColor = CRT.gold.cgColor
        ringBright.borderColor = CRT.gold.cgColor
        ringDim.isHidden = true
        ringBright.isHidden = true
        layer.addSublayer(ringDim)
        layer.addSublayer(ringBright)
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        addGestureRecognizer(tap)
        let long = UILongPressGestureRecognizer(target: self, action: #selector(pressed(_:)))
        long.minimumPressDuration = 0.5
        addGestureRecognizer(long)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    @objc private func tapped() { onTap?(id) }
    @objc private func pressed(_ g: UILongPressGestureRecognizer) {
        if g.state == .began { onLongPress?(id) }
    }

    func configure(art image: UIImage, state: State, hidden: Bool, interactive: Bool) {
        self.state = state
        let size = image.size
        bounds = CGRect(x: 0, y: 0, width: max(44, size.width), height: max(44, size.height))
        art.image = image
        art.frame = bounds
        isUserInteractionEnabled = interactive

        // far/done recede; here pops.
        switch state {
        case .far, .done: alpha = 0.5
        case .legal: alpha = 1
        case .here: alpha = 1
        }
        transform = state == .here ? CGAffineTransform(scaleX: 1.1, y: 1.1) : .identity

        // Rings.
        let inset: CGFloat = state == .here ? -8 : -7
        let color = state == .here ? CRT.phosphor : CRT.gold
        ringDim.frame = bounds.insetBy(dx: inset, dy: inset)
        ringBright.frame = bounds.insetBy(dx: inset, dy: inset)
        ringDim.borderColor = color.withAlphaComponent(state == .here ? 1 : 0.5).cgColor
        ringBright.borderColor = color.cgColor
        ringDim.borderWidth = state == .here ? 3 : 2
        ringBright.borderWidth = state == .here ? 4 : 3
        let showRing = state == .legal || state == .here
        ringDim.isHidden = !showRing
        ringBright.isHidden = !showRing
        ringBright.removeAnimation(forKey: "pulse")
        if showRing {
            // The web's pmPulseFade: opacity 0↔1, compositor-only.
            let a = CABasicAnimation(keyPath: "opacity")
            a.fromValue = 0; a.toValue = 1
            a.duration = state == .here ? 0.8 : 0.7
            a.autoreverses = true
            a.repeatCount = .infinity
            a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            ringBright.add(a, forKey: "pulse")
        }

        // Done ✓ chip.
        if state == .done {
            if check == nil {
                let c = CRTKit.label("✓", size: 14, color: CRT.phosphor)
                c.backgroundColor = CRT.ink
                c.textAlignment = .center
                addSubview(c)
                check = c
            }
            check?.frame = CGRect(x: bounds.width - 12, y: -8, width: 18, height: 18)
            check?.isHidden = false
        } else {
            check?.isHidden = true
        }
    }

    /// The arrival pop: the marker "lands" on the node it just travelled to.
    func playArrive() {
        transform = CGAffineTransform(translationX: 0, y: 22).scaledBy(x: 0.7, y: 0.7)
        alpha = 0.6
        UIView.animate(withDuration: 0.42, delay: 0, usingSpringWithDamping: 0.55,
                       initialSpringVelocity: 0.5) {
            self.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
            self.alpha = 1
        }
    }
}

// MARK: - Avatar

/// The traveling character box: the deck character sprite + the live deck-count
/// badge, with blink, worried/happy moods, the walk bounce and collect pop.
final class MapAvatarView: UIView {
    private let sprite = UIImageView()
    private let badge = UILabel()
    private var deckId = "pink"
    private var tier = "regular"
    private var worried = false
    private var blinkTimer: Timer?

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 44, height: 48))
        sprite.contentMode = .scaleAspectFit
        sprite.layer.magnificationFilter = .nearest
        sprite.frame = CGRect(x: 6, y: 0, width: 32, height: 32)
        addSubview(sprite)
        badge.font = CRT.Font.of(13)
        badge.textColor = CRT.ink
        badge.backgroundColor = CRT.gold
        badge.textAlignment = .center
        badge.layer.borderColor = CRT.ink.cgColor
        badge.layer.borderWidth = 2
        badge.frame = CGRect(x: 8, y: 32, width: 28, height: 16)
        addSubview(badge)
        isUserInteractionEnabled = false
        let t = Timer.scheduledTimer(withTimeInterval: 4.2, repeats: true) { [weak self] _ in
            self?.blink()
        }
        blinkTimer = t
        t.tolerance = 1.5
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    deinit { blinkTimer?.invalidate() }

    func configure(deckId: String, tier: String) {
        self.deckId = deckId
        self.tier = tier
        refresh()
    }

    func setCount(_ n: Int) { badge.text = "\(n)" }

    func setWorried(_ w: Bool) {
        guard w != worried else { return }
        worried = w
        refresh()
    }

    private func refresh() {
        sprite.image = DeckCharacter.image(deckId: deckId, mood: worried ? .sad : .idle, scale: 2, tier: tier)
    }

    private func blink() {
        sprite.image = DeckCharacter.image(deckId: deckId, mood: .blink, scale: 2, tier: tier)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.refresh() }
    }

    func bumpBadge() {
        badge.transform = CGAffineTransform(scaleX: 1.3, y: 1.3)
        UIView.animate(withDuration: 0.18) { self.badge.transform = .identity }
    }

    func collectBounce() {
        sprite.image = DeckCharacter.image(deckId: deckId, mood: .happy, scale: 2, tier: tier)
        transform = CGAffineTransform(scaleX: 1.15, y: 1.15)
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.5,
                       initialSpringVelocity: 0.4) { self.transform = .identity }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.88) { [weak self] in self?.refresh() }
    }

    func walkBounce(on: Bool) {
        if on {
            let a = CABasicAnimation(keyPath: "transform.rotation.z")
            a.fromValue = -0.06; a.toValue = 0.06
            a.duration = 0.12
            a.autoreverses = true
            a.repeatCount = .infinity
            sprite.layer.add(a, forKey: "walk")
        } else {
            sprite.layer.removeAnimation(forKey: "walk")
        }
    }
}
