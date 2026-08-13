import UIKit
import GameCore

/// The map's node art, ported glyph-for-glyph from the web's SVG/CSS markup:
/// deal/boss synapse clusters, the shop stall, pack stacks, exact card faces,
/// the mystery "?" card, the home hut. Everything is baked once into UIImages
/// (cached) and shown by plain UIImageViews.
public enum MapArt {

    // NODE_HALF — the obstacle half-extents per type, verbatim.
    public static func nodeHalf(_ type: String) -> (w: CGFloat, h: CGFloat) {
        switch type {
        case "pickup", "card": return (25, 31)
        case "pack":    return (25, 29)
        case "deal":    return (30, 27)
        case "boss":    return (40, 35)
        case "store":   return (26, 26)
        case "home":    return (30, 30)
        // The live "?" art is the 10×13 pxi sprite at k=4 in a +2 canvas =
        // 42×54. It used to be measured against the 38×48 procedural FALLBACK,
        // so dashed route edges were routed straight through the card.
        case "mystery": return (21, 27)
        default:        return (25, 29)
        }
    }

    private static var cache: [String: UIImage] = [:]
    private static func baked(_ key: String, _ make: () -> UIImage) -> UIImage {
        if let c = cache[key] { return c }
        let img = make()
        cache[key] = img
        return img
    }

    // MARK: - Deal / boss synapse cluster

    /// 52×46 (boss 72×62): four cream nodes linked to a hub, a suit-red crack
    /// burst at the centre; the boss wears the gold pixel crown.
    public static func synapseCluster(big: Bool) -> UIImage {
        baked("syn-\(big)") {
            let w: CGFloat = big ? 72 : 52, h: CGFloat = big ? 62 : 46
            let crownH: CGFloat = big ? 15 : 0
            return PixelTexture.image(size: CGSize(width: w, height: h + crownH)) { cg in
                let sx = w / 48, sy = h / 44, oy = crownH
                func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * sx, y: y * sy + oy) }
                // Links.
                cg.setStrokeColor(CRT.cardFace.cgColor)
                cg.setLineWidth(2)
                for (a, b) in [((24.0, 22.0), (9.0, 9.0)), ((24, 22), (39, 8)), ((24, 22), (7, 35)), ((24, 22), (41, 33))] {
                    cg.move(to: pt(a.0, a.1)); cg.addLine(to: pt(b.0, b.1))
                }
                cg.strokePath()
                cg.setStrokeColor(CRT.cardFace.withAlphaComponent(0.35).cgColor)
                cg.setLineWidth(1.4)
                cg.move(to: pt(9, 9)); cg.addLine(to: pt(39, 8))
                cg.move(to: pt(7, 35)); cg.addLine(to: pt(41, 33))
                cg.strokePath()
                // Nodes.
                cg.setFillColor(CRT.cardFace.cgColor)
                for (x, y, r) in [(9.0, 9.0, 4.0), (39, 8, 3.4), (7, 35, 3.4), (41, 33, 4)] {
                    cg.fillEllipse(in: CGRect(x: pt(x, y).x - r, y: pt(x, y).y - r, width: r * 2, height: r * 2))
                }
                // The crack burst.
                let crack: [(CGFloat, CGFloat)] = [(24, 10), (26.5, 17.5), (34, 13), (28.5, 21), (37, 25), (28, 26),
                                                   (29, 34), (23.5, 27.5), (17, 33), (20, 25.5), (11, 24), (19.5, 20), (16, 11), (23, 16.5)]
                cg.move(to: pt(crack[0].0, crack[0].1))
                for p in crack.dropFirst() { cg.addLine(to: pt(p.0, p.1)) }
                cg.closePath()
                cg.setFillColor(CRT.suitRed.cgColor)
                cg.setStrokeColor(CRT.ink.cgColor)
                cg.setLineWidth(1.2)
                cg.drawPath(using: .fillStroke)
                // Boss crown: the stepped gold pixel path.
                if big {
                    let cw: CGFloat = 22, ch: CGFloat = 15
                    let cx = w / 2 - cw / 2
                    let px = cw / 16, py = ch / 11
                    cg.setFillColor(CRT.gold.cgColor)
                    // The crown silhouette as filled pixel columns (from the SVG path).
                    let cols: [(CGFloat, CGFloat)] = [(0, 3), (1, 3), (2, 4), (3, 5), (4, 5), (5, 4), (6, 2), (7, 1), (8, 1), (9, 2), (10, 4), (11, 5), (12, 5), (13, 4), (14, 3), (15, 3)]
                    for (i, top) in cols {
                        cg.fill(CGRect(x: cx + i * px, y: top * py, width: px + 0.5, height: ch - top * py))
                    }
                }
            }
        }
    }

    /// The gold coin-reward chip under a deal/boss cluster.
    public static func rewardChip(_ amount: Int) -> UIImage {
        baked("chip-\(amount)") {
            let text = "◉\(amount)" as NSString
            // The approaching-deal coin counter: sized to actually be read at
            // a glance on the map, not a decorative tick.
            let font = CRT.Font.of(18)
            let sz = text.size(withAttributes: [.font: font])
            let w = ceil(sz.width) + 14, h: CGFloat = 22
            return PixelTexture.image(size: CGSize(width: w + 2, height: h + 2)) { cg in
                cg.setFillColor(CRT.shadow.cgColor)
                cg.fill(CGRect(x: 2, y: 2, width: w, height: h))
                cg.setFillColor(CRT.gold.cgColor)
                cg.fill(CGRect(x: 0, y: 0, width: w, height: h))
                cg.setFillColor(CRT.ink.cgColor)
                for r in [CGRect(x: 0, y: 0, width: w, height: 2), CGRect(x: 0, y: h - 2, width: w, height: 2),
                          CGRect(x: 0, y: 0, width: 2, height: h), CGRect(x: w - 2, y: 0, width: 2, height: h)] { cg.fill(r) }
                UIGraphicsPushContext(cg)
                text.draw(at: CGPoint(x: 6, y: (h - sz.height) / 2), withAttributes: [.font: font, .foregroundColor: CRT.ink])
                UIGraphicsPopContext()
            }
        }
    }

    // MARK: - Shop stall

    /// 44×40: cream body, ink door, striped suit-red/cream awning.
    public static func shopStall() -> UIImage {
        baked("shop") {
            PixelTexture.image(size: CGSize(width: 44, height: 40)) { cg in
                // Body.
                cg.setFillColor(CRT.cardFace.cgColor)
                cg.fill(CGRect(x: 7, y: 15, width: 30, height: 21))
                cg.setStrokeColor(CRT.ink.cgColor)
                cg.setLineWidth(2)
                cg.stroke(CGRect(x: 7, y: 15, width: 30, height: 21))
                // Door — centred on the BODY (x 7…37, centre 22). It used to sit
                // at 18.5…27.5 (centre 23), one pixel right of the awning apex,
                // which is what read as "the roof is offset".
                cg.setFillColor(CRT.ink.cgColor)
                cg.fill(CGRect(x: 17.5, y: 23, width: 9, height: 13))
                // Awning stripes from the apex. The colours MIRROR about the
                // centre (red · cream · cream · red) — plain `i % 2` alternation
                // put red on the left edge and cream on the right, so the dark
                // mass sat left of centre even though the outline was centred.
                let apex = CGPoint(x: 22, y: 3)
                let stops: [CGFloat] = [4, 13, 22, 31, 40]
                for i in 0..<4 {
                    let mirrored = min(i, 3 - i)   // 0,1,1,0
                    cg.setFillColor((mirrored % 2 == 0 ? CRT.suitRed : CRT.cardFace).cgColor)
                    cg.move(to: apex)
                    cg.addLine(to: CGPoint(x: stops[i], y: 16))
                    cg.addLine(to: CGPoint(x: stops[i + 1], y: 16))
                    cg.closePath()
                    cg.fillPath()
                }
            }
        }
    }

    // MARK: - Pack stack

    /// Per-deck back dithers: pink = red⊕cream, mamma = red⊕gold,
    /// smith = gold⊕deep-felt, lammy = ink⊕cream (§1 optical mixes).
    static func packDither(_ deckId: String) -> (UIColor, UIColor) {
        switch deckId {
        case "mamma": return (CRT.suitRed, CRT.gold)
        case "smith": return (CRT.gold, CRT.feltDeep)
        case "lammy": return (CRT.ink, CRT.cardFace)
        default:      return (CRT.suitRed, CRT.cardFace)
        }
    }

    /// 42×50 sealed pack: three fanned card backs in the deck's colour.
    public static func packStack(deckId: String) -> UIImage {
        baked("pack-\(deckId)") {
            PixelTexture.image(size: CGSize(width: 46, height: 54)) { cg in
                let (a, b) = packDither(deckId)
                func back(rot: CGFloat, dx: CGFloat, dy: CGFloat, shadow: Bool) {
                    cg.saveGState()
                    cg.translateBy(x: 23 + dx, y: 26 + dy)
                    cg.rotate(by: rot * .pi / 180)
                    let r = CGRect(x: -15, y: -20, width: 30, height: 40)
                    if shadow {
                        cg.setFillColor(CRT.shadow.cgColor)
                        cg.fill(r.offsetBy(dx: 2, dy: 2))
                    }
                    // Dither fill.
                    for y in stride(from: r.minY, to: r.maxY, by: 2) {
                        for x in stride(from: r.minX, to: r.maxX, by: 2) {
                            cg.setFillColor(((Int(x - r.minX) + Int(y - r.minY)) / 2 % 2 == 0 ? a : b).cgColor)
                            cg.fill(CGRect(x: x, y: y, width: 2, height: 2))
                        }
                    }
                    cg.setStrokeColor(CRT.ink.cgColor)
                    cg.setLineWidth(2)
                    cg.stroke(r)
                    cg.restoreGState()
                }
                back(rot: -8, dx: -4, dy: 2, shadow: false)
                back(rot: 8, dx: 4, dy: -2, shadow: false)
                back(rot: 0, dx: 0, dy: 0, shadow: true)
            }
        }
    }

    /// The gold "+N" loot badge (packs).
    public static func lootBadge(_ text: String) -> UIImage {
        baked("loot-\(text)") {
            let ns = text as NSString
            let font = CRT.Font.of(16)
            let sz = ns.size(withAttributes: [.font: font])
            let w = ceil(sz.width) + 14, h: CGFloat = 21
            return PixelTexture.image(size: CGSize(width: w + 2, height: h + 2)) { cg in
                cg.setFillColor(CRT.shadow.cgColor)
                cg.fill(CGRect(x: 2, y: 2, width: w, height: h))
                cg.setFillColor(CRT.gold.cgColor)
                cg.fill(CGRect(x: 0, y: 0, width: w, height: h))
                cg.setFillColor(CRT.ink.cgColor)
                for r in [CGRect(x: 0, y: 0, width: w, height: 2), CGRect(x: 0, y: h - 2, width: w, height: 2),
                          CGRect(x: 0, y: 0, width: 2, height: h), CGRect(x: w - 2, y: 0, width: 2, height: h)] { cg.fill(r) }
                UIGraphicsPushContext(cg)
                ns.draw(at: CGPoint(x: 6, y: (h - sz.height) / 2), withAttributes: [.font: font, .foregroundColor: CRT.ink])
                UIGraphicsPopContext()
            }
        }
    }

    // MARK: - Mystery "?"

    /// The web's exact mystery card face (ink card, PHOSPHOR "?"), gold-framed;
    /// `open` lights the frame phosphor while the gamble resolves.
    public static func mysteryCard(open: Bool) -> UIImage {
        if let art = ArtBundle.image("pxi-mystery") {
            return baked("mystx-\(open)") {
                let k: CGFloat = 4
                let w = art.size.width * k, h = art.size.height * k
                // A `+2` canvas with the card at (1,1), like every sibling art
                // (rewardChip, lootBadge). The old `+6` canvas left margins of
                // 1 and 5, so the card sat 2pt up-and-left of the node point
                // while MapNodeView centred the CANVAS — which is why the
                // state ring looked off-register around the "?".
                return PixelTexture.image(size: CGSize(width: w + 2, height: h + 2)) { cg in
                    cg.setFillColor(CRT.shadow.cgColor)
                    cg.fill(CGRect(x: 2, y: 2, width: w, height: h))
                    UIGraphicsPushContext(cg)
                    art.draw(in: CGRect(x: 0, y: 0, width: w, height: h))
                    UIGraphicsPopContext()
                    // Inset by half the line width so the 2pt frame lands INSIDE
                    // the card instead of straddling its edge and eating a pixel
                    // of artwork on every side.
                    cg.setStrokeColor((open ? CRT.phosphor : CRT.gold).cgColor)
                    cg.setLineWidth(2)
                    cg.stroke(CGRect(x: 1, y: 1, width: w - 2, height: h - 2))
                }
            }
        }
        return baked("myst-\(open)") {
            let w: CGFloat = 38, h: CGFloat = 48
            return PixelTexture.image(size: CGSize(width: w + 2, height: h + 2)) { cg in
                cg.setFillColor(CRT.shadow.cgColor)
                cg.fill(CGRect(x: 2, y: 2, width: w, height: h))
                cg.setFillColor(CRT.ink.cgColor)
                cg.fill(CGRect(x: 0, y: 0, width: w, height: h))
                let frame = open ? CRT.phosphor : CRT.gold
                cg.setFillColor(frame.cgColor)
                for r in [CGRect(x: 0, y: 0, width: w, height: 2), CGRect(x: 0, y: h - 2, width: w, height: 2),
                          CGRect(x: 0, y: 0, width: 2, height: h), CGRect(x: w - 2, y: 0, width: 2, height: h)] { cg.fill(r) }
                // Dashed cream inner frame.
                cg.setStrokeColor(CRT.cardFace.withAlphaComponent(0.5).cgColor)
                cg.setLineWidth(1)
                cg.setLineDash(phase: 0, lengths: [3, 3])
                cg.stroke(CGRect(x: 4.5, y: 4.5, width: w - 9, height: h - 9))
                cg.setLineDash(phase: 0, lengths: [])
                UIGraphicsPushContext(cg)
                let q = "?" as NSString
                let font = CRT.Font.of(26)
                let sz = q.size(withAttributes: [.font: font])
                if open {
                    let s = NSShadow()
                    s.shadowColor = CRT.phosphor.withAlphaComponent(CRT.glowAlpha)
                    s.shadowBlurRadius = CRT.glowRadius
                    q.draw(at: CGPoint(x: (w - sz.width) / 2, y: (h - sz.height) / 2),
                           withAttributes: [.font: font, .foregroundColor: CRT.phosphor, .shadow: s])
                } else {
                    q.draw(at: CGPoint(x: (w - sz.width) / 2, y: (h - sz.height) / 2),
                           withAttributes: [.font: font, .foregroundColor: CRT.gold])
                }
                UIGraphicsPopContext()
            }
        }
    }

    // MARK: - Home hut

    /// The base-camp hut: suit-red gable, cream body, ♥ on the door.
    /// `mama` = the top-of-map finish line (bigger, extra ♥).
    public static func homeHut(mama: Bool) -> UIImage {
        baked("home-\(mama)") {
            let w: CGFloat = mama ? 58 : 50, h: CGFloat = mama ? 50 : 42
            return PixelTexture.image(size: CGSize(width: w + 6, height: h + 8)) { cg in
                let oy: CGFloat = 7
                let roofS: CGFloat = mama ? 32 : 26
                let bodyW: CGFloat = mama ? 44 : 36, bodyH: CGFloat = mama ? 30 : 26
                // Centre on the CANVAS, not on `w`: the bitmap is `w + 6` wide,
                // so centring on `w / 2` put the whole hut 3pt left of centre
                // while MapNodeView centres the canvas on the node point.
                let cx = (w + 6) / 2
                // Roof: rotated square.
                cg.saveGState()
                cg.translateBy(x: cx, y: oy + roofS * 0.72)
                cg.rotate(by: .pi / 4)
                let rr = CGRect(x: -roofS / 2, y: -roofS / 2, width: roofS, height: roofS)
                cg.setFillColor(CRT.suitRed.cgColor)
                cg.fill(rr)
                cg.setStrokeColor(CRT.ink.cgColor)
                cg.setLineWidth(2)
                cg.stroke(rr)
                cg.restoreGState()
                // Body.
                let br = CGRect(x: cx - bodyW / 2, y: oy + h - bodyH, width: bodyW, height: bodyH)
                cg.setFillColor(CRT.shadow.cgColor)
                cg.fill(br.offsetBy(dx: 2, dy: 2))
                cg.setFillColor(CRT.cardFace.cgColor)
                cg.fill(br)
                cg.setStrokeColor(CRT.ink.cgColor)
                cg.stroke(br)
                UIGraphicsPushContext(cg)
                let heart = "♥" as NSString
                let font = CRT.Font.of(mama ? 15 : 13)
                let sz = heart.size(withAttributes: [.font: font])
                heart.draw(at: CGPoint(x: cx - sz.width / 2, y: br.maxY - sz.height - 2),
                           withAttributes: [.font: font, .foregroundColor: CRT.suitRed])
                if mama {
                    heart.draw(at: CGPoint(x: w - sz.width, y: 0),
                               withAttributes: [.font: font, .foregroundColor: CRT.suitRed])
                }
                UIGraphicsPopContext()
            }
        }
    }

    // MARK: - Pass point

    public static func passDot(done: Bool) -> UIImage {
        baked("pass-\(done)") {
            PixelTexture.image(size: CGSize(width: 10, height: 10)) { cg in
                cg.setFillColor((done ? CRT.feltDeep : CRT.feltMid).cgColor)
                cg.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
                cg.setStrokeColor(CRT.ink.cgColor)
                cg.setLineWidth(2)
                cg.stroke(CGRect(x: 1, y: 1, width: 8, height: 8))
            }
        }
    }

    // MARK: - The map background tile

    /// The web's `.map-bg`: a 96×96 sparse pixel-dot field over the felt
    /// dither. Redrawn (not decoded) so it stays palette-pure.
    public static func backgroundTile() -> UIImage {
        baked("bg") {
            PixelTexture.image(size: CGSize(width: 96, height: 96)) { cg in
                // Felt dither underlay (mid⊕deep 2×2).
                for y in stride(from: 0, to: 96, by: 2) {
                    for x in stride(from: 0, to: 96, by: 2) {
                        cg.setFillColor(((x + y) / 2 % 2 == 0 ? CRT.feltMid : CRT.feltDeep).cgColor)
                        cg.fill(CGRect(x: x, y: y, width: 2, height: 2))
                    }
                }
                // A sparse deterministic dot field (stable — no live RNG).
                var h: UInt32 = 0x9e3779b9
                func rnd() -> CGFloat {
                    h ^= h << 13; h ^= h >> 17; h ^= h << 5
                    return CGFloat(h % 1000) / 1000
                }
                cg.setFillColor(CRT.feltDeep.cgColor)
                for _ in 0..<26 {
                    let x = (rnd() * 92).rounded(), y = (rnd() * 92).rounded()
                    cg.fill(CGRect(x: x, y: y, width: 4, height: 4))
                }
                cg.setFillColor(CRT.cardFace.withAlphaComponent(0.06).cgColor)
                for _ in 0..<10 {
                    let x = (rnd() * 94).rounded(), y = (rnd() * 94).rounded()
                    cg.fill(CGRect(x: x, y: y, width: 2, height: 2))
                }
            }
        }
    }

    /// The menu logo: the gold "=" synapse mark, verbatim from icons/logo.svg
    /// (viewBox 100): two gold bars at y=40/y=60 (stroke-width 9, round caps,
    /// no outline) with r=8 circles on each end — the bone shape — and an r=3
    /// phosphor dot centred on each bar at (52,40) / (48,60). The mark spans
    /// x 22…78, y 31…69 in viewBox units.
    public static func menuLogo(width: CGFloat = 96) -> UIImage {
        baked("logo-\(Int(width))") {
            let s = min(width / 56, width * 0.62 / 38)
            let h = 38 * s
            return PixelTexture.image(size: CGSize(width: width, height: h)) { cg in
                let ox = (width - 56 * s) / 2 - 22 * s
                func X(_ u: CGFloat) -> CGFloat { ox + u * s }
                func Y(_ v: CGFloat) -> CGFloat { (v - 31) * s }
                cg.setFillColor(CRT.gold.cgColor)
                for v in [40.0, 60.0] as [CGFloat] {
                    // The round-cap stroke body + the r8 end circles.
                    cg.fill(CGRect(x: X(30), y: Y(v - 4.5), width: 40 * s, height: 9 * s))
                    for u in [30.0, 70.0] as [CGFloat] {
                        cg.fillEllipse(in: CGRect(x: X(u) - 8 * s, y: Y(v) - 8 * s,
                                                  width: 16 * s, height: 16 * s))
                    }
                }
                cg.setFillColor(CRT.phosphor.cgColor)
                for (u, v) in [(52.0, 40.0), (48.0, 60.0)] as [(CGFloat, CGFloat)] {
                    cg.fillEllipse(in: CGRect(x: X(u) - 3 * s, y: Y(v) - 3 * s,
                                              width: 6 * s, height: 6 * s))
                }
            }
        }
    }

    /// Tiny 9×9 pixel glyphs for the menu buttons (the web's inline icons).
    public static func menuIcon(_ key: String) -> UIImage {
        baked("mi-\(key)") {
            PixelTexture.image(size: CGSize(width: 9, height: 9)) { cg in
                func px(_ x: Int, _ y: Int, _ c: UIColor = CRT.cardFace) {
                    cg.setFillColor(c.cgColor)
                    cg.fill(CGRect(x: x, y: y, width: 1, height: 1))
                }
                switch key {
                case "spark":       // ✦ climb (web `spark`: 4-point star)
                    for (x, y) in [(4,0),(4,1),(4,2),(4,3),(4,5),(4,6),(4,7),(4,8),
                                   (0,4),(1,4),(2,4),(3,4),(5,4),(6,4),(7,4),(8,4),
                                   (3,3),(5,3),(3,5),(5,5),(4,4)] { px(x,y) }
                case "sun":         // continue (web `win`: disc + 8 rays)
                    for (x, y) in [(4,0),(4,8),(0,4),(8,4),(1,1),(7,1),(1,7),(7,7)] { px(x,y) }
                    for x in 3...5 { for y in 3...5 { px(x,y) } }
                case "zen":         // ◎ circle-dot (web `swirl`)
                    for (x, y) in [(3,0),(4,0),(5,0),(2,1),(6,1),(1,2),(7,2),(0,3),(8,3),(0,4),(8,4),
                                   (0,5),(8,5),(1,6),(7,6),(2,7),(6,7),(3,8),(4,8),(5,8)] { px(x,y) }
                    px(4,4)
                case "search":      // magnifier
                    for (x, y) in [(2,0),(3,0),(4,0),(1,1),(5,1),(0,2),(6,2),(0,3),(6,3),(1,4),(5,4),(2,5),(3,5),(4,5),(6,6),(7,7),(8,8)] { px(x,y) }
                case "bars":        // stats
                    for y in 5...8 { px(1,y) }
                    for y in 3...8 { px(4,y) }
                    for y in 1...8 { px(7,y) }
                case "box":         // collection (web `die`: rounded square, 3 pips)
                    for x in 2...6 { px(x,0); px(x,8) }
                    for y in 2...6 { px(0,y); px(8,y) }
                    for (x, y) in [(1,1),(7,1),(1,7),(7,7)] { px(x,y) }
                    for (x, y) in [(2,2),(4,4),(6,6)] { px(x,y) }
                case "gear":        // settings (web `reroll`: circular arrow)
                    for (x, y) in [(2,1),(1,2),(0,3),(0,4),(0,5),(1,6),(2,7),(3,8),(4,8),(5,8),
                                   (6,7),(7,6),(8,5),(8,4),(8,3),(7,2)] { px(x,y) }
                    for (x, y) in [(6,0),(6,1),(6,2),(5,2),(4,2)] { px(x,y) }
                case "back":        // ← (web `back`)
                    for x in 2...8 { px(x,4) }
                    for (x, y) in [(4,1),(3,2),(2,3),(1,4),(2,5),(3,6),(4,7)] { px(x,y) }
                case "quit":        // ⃠
                    for (x, y) in [(3,0),(4,0),(5,0),(1,1),(7,1),(0,3),(0,4),(0,5),(8,3),(8,4),(8,5),(1,7),(7,7),(3,8),(4,8),(5,8),(2,6),(3,5),(4,4),(5,3),(6,2)] { px(x, y, CRT.cardFace) }
                default: break
                }
            }
        }
    }

    /// The warm spotlight that rides the character: a radial gold wash
    /// (one of the sanctioned radial halos), baked once.
    public static func spotlight(diameter: CGFloat) -> UIImage {
        baked("spot-\(Int(diameter))") {
            PixelTexture.image(size: CGSize(width: diameter, height: diameter)) { cg in
                let c = diameter / 2
                let steps = 14
                for i in (0..<steps).reversed() {
                    let t = CGFloat(i + 1) / CGFloat(steps)
                    cg.setFillColor(CRT.gold.withAlphaComponent(0.16 * (1 - t)).cgColor)
                    cg.fillEllipse(in: CGRect(x: c - c * t, y: c - c * t, width: c * t * 2, height: c * t * 2))
                }
            }
        }
    }
}
