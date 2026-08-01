import UIKit
import GameCore

/// Store/inventory object art — the merchandise itself, in the CRT CASINO
/// language: rarity lives IN the object (die-cut rim, cloth trim, metal tone,
/// pack foil), never in a text tag. Baked once per (kind, id, size) and cached.
public enum ItemArt {

    private static var cache: [String: UIImage] = [:]
    private static func baked(_ key: String, _ make: () -> UIImage) -> UIImage {
        if let c = cache[key] { return c }
        let img = make()
        cache[key] = img
        return img
    }

    /// Tier rim colors: common recedes, uncommon gold, rare phosphor.
    static func tierColor(_ tier: String) -> UIColor {
        switch tier {
        case "rare": return CRT.phosphor
        case "uncommon": return CRT.gold
        default: return CRT.cardFace
        }
    }

    private static func drawIcon(_ cg: CGContext, _ def: ItemDef, at rect: CGRect,
                                 color: UIColor, size: CGFloat) {
        UIGraphicsPushContext(cg)
        let text = (def.icon?.isEmpty == false ? def.icon! : String(def.label.prefix(1))) as NSString
        let font = CRT.Font.of(size)
        let sz = text.size(withAttributes: [.font: font])
        text.draw(at: CGPoint(x: rect.midX - sz.width / 2, y: rect.midY - sz.height / 2),
                  withAttributes: [.font: font, .foregroundColor: color])
        UIGraphicsPopContext()
    }

    /// A sticker: a die-cut octagonal chip, tier-rimmed, icon + label.
    /// Cursed stickers keep the pinned violet face.
    public static func sticker(_ def: ItemDef, size: CGFloat = 56) -> UIImage {
        baked("stk-\(def.id)-\(Int(size))") {
            PixelTexture.image(size: CGSize(width: size + 3, height: size + 3)) { cg in
                let cut = size * 0.22
                func chipPath(_ o: CGFloat) -> CGPath {
                    let p = CGMutablePath()
                    p.move(to: CGPoint(x: o + cut, y: o))
                    p.addLine(to: CGPoint(x: o + size - cut, y: o))
                    p.addLine(to: CGPoint(x: o + size, y: o + cut))
                    p.addLine(to: CGPoint(x: o + size, y: o + size - cut))
                    p.addLine(to: CGPoint(x: o + size - cut, y: o + size))
                    p.addLine(to: CGPoint(x: o + cut, y: o + size))
                    p.addLine(to: CGPoint(x: o, y: o + size - cut))
                    p.addLine(to: CGPoint(x: o, y: o + cut))
                    p.closeSubpath()
                    return p
                }
                // Hard shadow.
                cg.addPath(chipPath(3))
                cg.setFillColor(CRT.shadow.cgColor)
                cg.fillPath()
                // Face: cursed keeps the pinned violet; others aged cream.
                cg.addPath(chipPath(0))
                cg.setFillColor((def.cursed ? UIColor(hex: 0x7a4fd0) : CRT.cardFace).cgColor)
                cg.fillPath()
                // Tier rim.
                cg.addPath(chipPath(0))
                cg.setStrokeColor((def.cursed ? UIColor(hex: 0x46306e) : tierColor(def.tier)).cgColor)
                cg.setLineWidth(3)
                cg.strokePath()
                drawIcon(cg, def, at: CGRect(x: 0, y: -4, width: size, height: size),
                         color: def.cursed ? CRT.cardFace : CRT.ink, size: size * 0.4)
                // The label along the chip's foot.
                UIGraphicsPushContext(cg)
                let name = String(def.label.prefix(9)) as NSString
                let f = CRT.Font.of(12)
                let sz = name.size(withAttributes: [.font: f])
                name.draw(at: CGPoint(x: (size - sz.width) / 2, y: size - sz.height - 5),
                          withAttributes: [.font: f, .foregroundColor: def.cursed ? CRT.cardFace : CRT.ink])
                UIGraphicsPopContext()
            }
        }
    }

    /// A pillar: a hanging cloth banner (pointed foot), tier trim, icon + name.
    public static func pillar(_ def: ItemDef, width: CGFloat = 52, height: CGFloat = 68) -> UIImage {
        baked("pil-\(def.id)-\(Int(width))") {
            PixelTexture.image(size: CGSize(width: width + 3, height: height + 3)) { cg in
                func banner(_ o: CGFloat) -> CGPath {
                    let p = CGMutablePath()
                    p.move(to: CGPoint(x: o, y: o))
                    p.addLine(to: CGPoint(x: o + width, y: o))
                    p.addLine(to: CGPoint(x: o + width, y: o + height - 12))
                    p.addLine(to: CGPoint(x: o + width / 2, y: o + height))
                    p.addLine(to: CGPoint(x: o, y: o + height - 12))
                    p.closeSubpath()
                    return p
                }
                cg.addPath(banner(3))
                cg.setFillColor(CRT.shadow.cgColor)
                cg.fillPath()
                cg.addPath(banner(0))
                cg.setFillColor(CRT.feltMid.cgColor)
                cg.fillPath()
                cg.addPath(banner(0))
                cg.setStrokeColor(CRT.ink.cgColor)
                cg.setLineWidth(2)
                cg.strokePath()
                // Tier trim bar under the hanger.
                cg.setFillColor(tierColor(def.tier).cgColor)
                cg.fill(CGRect(x: 2, y: 3, width: width - 4, height: 3))
                drawIcon(cg, def, at: CGRect(x: 0, y: 6, width: width, height: height * 0.5),
                         color: CRT.gold, size: 22)
                UIGraphicsPushContext(cg)
                let name = String(def.label.prefix(8)) as NSString
                let f = CRT.Font.of(12)
                let sz = name.size(withAttributes: [.font: f])
                name.draw(at: CGPoint(x: (width - sz.width) / 2, y: height * 0.58),
                          withAttributes: [.font: f, .foregroundColor: CRT.cardFace])
                UIGraphicsPopContext()
            }
        }
    }

    /// A base: a squat metal plate with charge LEDs, tier tone, name.
    public static func base(_ def: ItemDef, width: CGFloat = 58, height: CGFloat = 40) -> UIImage {
        baked("bas-\(def.id)-\(Int(width))") {
            PixelTexture.image(size: CGSize(width: width + 3, height: height + 3)) { cg in
                let r = CGRect(x: 0, y: 0, width: width, height: height)
                cg.setFillColor(CRT.shadow.cgColor)
                cg.fill(r.offsetBy(dx: 3, dy: 3))
                cg.setFillColor(CRT.feltDeep.cgColor)
                cg.fill(r)
                cg.setStrokeColor(tierColor(def.tier).cgColor)
                cg.setLineWidth(2)
                cg.stroke(r.insetBy(dx: 1, dy: 1))
                // Charge LEDs (the sanctioned status dots).
                cg.setFillColor(CRT.phosphor.cgColor)
                cg.fillEllipse(in: CGRect(x: 6, y: 6, width: 5, height: 5))
                cg.fillEllipse(in: CGRect(x: width - 11, y: 6, width: 5, height: 5))
                drawIcon(cg, def, at: CGRect(x: 0, y: 2, width: width, height: height * 0.55),
                         color: CRT.cardFace, size: 16)
                UIGraphicsPushContext(cg)
                let name = String(def.label.prefix(9)) as NSString
                let f = CRT.Font.of(12)
                let sz = name.size(withAttributes: [.font: f])
                name.draw(at: CGPoint(x: (width - sz.width) / 2, y: height - sz.height - 3),
                          withAttributes: [.font: f, .foregroundColor: CRT.cardFace])
                UIGraphicsPopContext()
            }
        }
    }

    /// A pack: a foil packet — card packs wear the deck dither, sticker packs
    /// a phosphor-flecked foil; the size pips ride the foot.
    public static func pack(_ def: ItemDef, deckId: String, width: CGFloat = 46, height: CGFloat = 60) -> UIImage {
        baked("pak-\(def.id)-\(deckId)") {
            PixelTexture.image(size: CGSize(width: width + 3, height: height + 3)) { cg in
                let r = CGRect(x: 0, y: 4, width: width, height: height - 4)
                cg.setFillColor(CRT.shadow.cgColor)
                cg.fill(r.offsetBy(dx: 3, dy: 3))
                // Foil body.
                let isSticker = def.kind == "sticker"
                let (a, b) = isSticker ? (CRT.feltMid, CRT.feltDeep) : MapArt.packDither(deckId)
                for y in stride(from: r.minY, to: r.maxY, by: 2) {
                    for x in stride(from: r.minX, to: r.maxX, by: 2) {
                        cg.setFillColor(((Int(x) + Int(y)) / 2 % 2 == 0 ? a : b).cgColor)
                        cg.fill(CGRect(x: x, y: y, width: 2, height: 2))
                    }
                }
                if isSticker {
                    // Phosphor flecks mark the sticker foil.
                    cg.setFillColor(CRT.phosphor.cgColor)
                    for (fx, fy) in [(8, 18), (30, 26), (16, 40), (34, 46), (12, 30)] {
                        cg.fill(CGRect(x: CGFloat(fx), y: CGFloat(fy), width: 3, height: 3))
                    }
                }
                cg.setStrokeColor(CRT.ink.cgColor)
                cg.setLineWidth(2)
                cg.stroke(r)
                // The crimped top.
                cg.setFillColor(CRT.ink.cgColor)
                cg.fill(CGRect(x: 0, y: 0, width: width, height: 6))
                // Label plate.
                let plate = CGRect(x: 4, y: height * 0.36, width: width - 8, height: 16)
                cg.setFillColor(CRT.cardFace.cgColor)
                cg.fill(plate)
                cg.setStrokeColor(CRT.ink.cgColor)
                cg.stroke(plate)
                UIGraphicsPushContext(cg)
                let name = String(def.label.prefix(7)) as NSString
                let f = CRT.Font.of(12)
                var sz = name.size(withAttributes: [.font: f])
                name.draw(at: CGPoint(x: plate.midX - sz.width / 2, y: plate.midY - sz.height / 2),
                          withAttributes: [.font: f, .foregroundColor: CRT.ink])
                let pips = String(repeating: "▪", count: max(1, def.int("size", 1))) as NSString
                sz = pips.size(withAttributes: [.font: f])
                pips.draw(at: CGPoint(x: (width - sz.width) / 2, y: height - sz.height - 4),
                          withAttributes: [.font: f, .foregroundColor: CRT.cardFace])
                UIGraphicsPopContext()
            }
        }
    }

    /// A Same-Power: the phosphor "=" class mark over the name plate.
    public static func samePower(_ def: ItemDef, width: CGFloat = 56, height: CGFloat = 58) -> UIImage {
        baked("sp-\(def.id)") {
            PixelTexture.image(size: CGSize(width: width, height: height)) { cg in
                // The = mark: two phosphor bars with node dots at the ends.
                cg.setFillColor(CRT.phosphor.cgColor)
                cg.fill(CGRect(x: 12, y: 12, width: width - 24, height: 5))
                cg.fill(CGRect(x: 12, y: 23, width: width - 24, height: 5))
                for (x, y) in [(8, 11), (Int(width) - 12, 11), (8, 22), (Int(width) - 12, 22)] {
                    cg.fillEllipse(in: CGRect(x: CGFloat(x) - 2, y: CGFloat(y), width: 7, height: 7))
                }
                UIGraphicsPushContext(cg)
                let name = String(def.label.prefix(10)) as NSString
                let f = CRT.Font.of(13)
                let sz = name.size(withAttributes: [.font: f])
                name.draw(at: CGPoint(x: (width - sz.width) / 2, y: height - sz.height - 2),
                          withAttributes: [.font: f, .foregroundColor: CRT.cardFace])
                UIGraphicsPopContext()
            }
        }
    }

    /// The Removal slot object: the stitched-grey ∅ card.
    public static func removal(width: CGFloat = 44, height: CGFloat = 58) -> UIImage {
        baked("removal") {
            PixelTexture.image(size: CGSize(width: width + 3, height: height + 3)) { cg in
                let r = CGRect(x: 0, y: 0, width: width, height: height)
                cg.setFillColor(CRT.shadow.cgColor)
                cg.fill(r.offsetBy(dx: 3, dy: 3))
                cg.setFillColor(CRT.feltMid.cgColor)
                cg.fill(r)
                cg.setStrokeColor(CRT.ink.cgColor)
                cg.setLineWidth(2)
                cg.stroke(r)
                // Stitched inner frame.
                cg.setStrokeColor(CRT.cardFace.withAlphaComponent(0.4).cgColor)
                cg.setLineWidth(1)
                cg.setLineDash(phase: 0, lengths: [3, 3])
                cg.stroke(r.insetBy(dx: 5, dy: 5))
                cg.setLineDash(phase: 0, lengths: [])
                UIGraphicsPushContext(cg)
                let sym = "∅" as NSString
                let f = CRT.Font.of(24)
                var sz = sym.size(withAttributes: [.font: f])
                sym.draw(at: CGPoint(x: (width - sz.width) / 2, y: height * 0.2),
                         withAttributes: [.font: f, .foregroundColor: CRT.cardFace])
                let lab = "Removal" as NSString
                let lf = CRT.Font.of(12)
                sz = lab.size(withAttributes: [.font: lf])
                lab.draw(at: CGPoint(x: (width - sz.width) / 2, y: height - sz.height - 5),
                         withAttributes: [.font: lf, .foregroundColor: CRT.muted])
                UIGraphicsPopContext()
            }
        }
    }

    /// Shelf art for any store slot kind.
    public static func forSlot(kind: String, id: String, card: CardSpec?, deckId: String) -> UIImage {
        let data = GameData.shared
        switch kind {
        case "card":
            if let card { return CardArt.image(CardArt.Face(card), scale: .half) }
            return removal()
        case "removal": return removal()
        case "pillar": if let d = data.pillarTypes.get(id) { return pillar(d) }
        case "base": if let d = data.baseTypes.get(id) { return base(d) }
        case "pack": if let d = data.packTypes.get(id) { return pack(d, deckId: deckId) }
        case "samepower": if let d = data.samePowerTypes.get(id) { return samePower(d) }
        default: if let d = data.stickerTypes.get(id) { return sticker(d) }
        }
        return removal()
    }
}
