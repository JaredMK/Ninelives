import SpriteKit
import GameCore

/// §5 Cards — the numeral IS the card.
///
/// *"Corner pips are decoration at 100% ONLY — at ≤75% the oversized centered
/// numeral carries everything (deals reach 40+ cards). Readability beats pip
/// fidelity."* Every face is baked once into a texture and reused.
public enum CardArt {

    /// The three sanctioned sizes from the styleguide, in points.
    public enum Scale {
        case full    // c100: 96×134, rank 64, suit 26, pips
        case three   // c75:  72×100, rank 48, suit 20
        case half    // c50:  48×67,  rank 34, suit 14, 2px border + 2px shadow

        var size: CGSize {
            switch self {
            case .full:  return CGSize(width: 96, height: 134)
            case .three: return CGSize(width: 72, height: 100)
            case .half:  return CGSize(width: 48, height: 67)
            }
        }
        var rankSize: CGFloat {
            switch self { case .full: return 64; case .three: return 48; case .half: return 34 }
        }
        var suitSize: CGFloat {
            // half 14 → 18, three 20 → 22 (v6.52): at the 12-pile scale the
            // ♣/♠ silhouettes blurred together — the suit mark is the ONE
            // thing a guess hangs on, so it grows before anything else does.
            switch self { case .full: return 26; case .three: return 22; case .half: return 18 }
        }
        /// c50 halves the border AND the shadow.
        var shadow: CGFloat { self == .half ? 2 : CRT.shadowOffset }
        var border: CGFloat { CRT.px }
        /// Corner pips are 100%-only decoration.
        var showsPips: Bool { self == .full }
    }

    /// What a face looks like, independent of which live card it came from.
    public struct Face: Hashable {
        public var label: String      // "10", "K", "A", "★", "?"
        public var suit: String       // "♦" … "★" (joker) / "∅" (removal)
        public var kind: Kind
        public enum Kind: Hashable { case normal, joker, blank, back(deckId: String) }

        public init(label: String, suit: String, kind: Kind = .normal) {
            self.label = label; self.suit = suit; self.kind = kind
        }

        public init(_ card: LiveCard) {
            if card.joker { self.init(label: "★", suit: "★", kind: .joker) }
            else if card.blank { self.init(label: "?", suit: "∅", kind: .blank) }
            else { self.init(label: card.label, suit: card.suit, kind: .normal) }
        }
        public init(_ spec: CardSpec) {
            if spec.joker { self.init(label: "★", suit: "★", kind: .joker) }
            else if spec.blank { self.init(label: "?", suit: "∅", kind: .blank) }
            else {
                let r = DeckManager.ranks.first { $0.value == spec.currentRank }
                self.init(label: r?.label ?? "?", suit: spec.suit, kind: .normal)
            }
        }
    }

    private struct Key: Hashable { let face: Face; let scale: Scale }
    private static var cache: [Key: SKTexture] = [:]
    private static var imageCache: [Key: UIImage] = [:]

    /// COLORFUL CARDS (v6.96): the cache key carries no colour component, so
    /// a suit-recolour toggle must drop every baked face — the next bake
    /// reads the new scheme.
    public static func flushColorCaches() {
        cache.removeAll()
        imageCache.removeAll()
    }

    public static func texture(_ face: Face, scale: Scale) -> SKTexture {
        let key = Key(face: face, scale: scale)
        if let c = cache[key] { return c }
        let tex = PixelTexture.texture(from: image(face, scale: scale))
        cache[key] = tex
        return tex
    }

    /// The same baked face as a UIImage — the UIKit screens (map node cards,
    /// store shelf, pickers) draw with this so a card looks identical everywhere.
    public static func image(_ face: Face, scale: Scale) -> UIImage {
        let key = Key(face: face, scale: scale)
        if let c = imageCache[key] { return c }

        let box = scale.size
        let canvas = CGSize(width: box.width + scale.shadow, height: box.height + scale.shadow)

        // Face + ink colors per kind (styleguide §5).
        let faceColor: UIColor
        var borderColor = CRT.ink
        let inkColor: UIColor
        switch face.kind {
        case .normal:
            faceColor = CRT.cardFace
            inkColor = CRT.color(forSuit: face.suit)
        case .joker:
            // .pcard.joker — deep felt face, gold rank AND gold border.
            faceColor = CRT.feltDeep; borderColor = CRT.gold; inkColor = CRT.gold
        case .blank:
            // .pcard.blank — felt mid, 50% cream.
            faceColor = CRT.feltMid; inkColor = CRT.cardFace.withAlphaComponent(0.5)
        case .back:
            faceColor = CRT.feltDeep; inkColor = .clear
        }

        let img = PixelTexture.image(size: canvas) { cg in
            // Hard shadow, down-right, zero blur.
            cg.setFillColor(CRT.shadow.cgColor)
            cg.fill(CGRect(x: scale.shadow, y: scale.shadow, width: box.width, height: box.height))
            // Face.
            cg.setFillColor(faceColor.cgColor)
            cg.fill(CGRect(origin: .zero, size: box))

            // A card BACK is a dither tile per deck (§5) — the deck's own skin.
            if case .back(let deckId) = face.kind {
                let (a, b) = backDither(deckId)
                for y in 0..<Int(box.height) {
                    for x in 0..<Int(box.width) {
                        cg.setFillColor(((x + y) % 2 == 0 ? a : b).cgColor)
                        cg.fill(CGRect(x: x, y: y, width: 1, height: 1))
                    }
                }
            }

            // Border.
            cg.setFillColor(borderColor.cgColor)
            let b = scale.border
            cg.fill(CGRect(x: 0, y: 0, width: box.width, height: b))
            cg.fill(CGRect(x: 0, y: box.height - b, width: box.width, height: b))
            cg.fill(CGRect(x: 0, y: 0, width: b, height: box.height))
            cg.fill(CGRect(x: box.width - b, y: 0, width: b, height: box.height))

            if case .back = face.kind { return }

            UIGraphicsPushContext(cg)
            defer { UIGraphicsPopContext() }

            // Corner pips — decoration at 100% only, 0.8 alpha. v6.68: the
            // game's own 8px pixel suit mark (PixelGlyph) — the text draw fell
            // through to the SYSTEM font (neither game font carries U+2660–6),
            // which is exactly where ♠ and ♣ blurred together.
            if scale.showsPips, face.kind == .normal,
               let pip = PixelGlyph.suitImage(face.suit, size: 14, color: inkColor) {
                pip.draw(at: CGPoint(x: 4, y: 4), blendMode: .normal, alpha: 0.8)
                pip.draw(at: CGPoint(x: box.width - pip.size.width - 4,
                                     y: box.height - pip.size.height - 4),
                         blendMode: .normal, alpha: 0.8)
            }

            // THE NUMERAL — oversized, centred, bold. line-height 0.8 in the CSS,
            // so the rank and the suit sit tight together as one block.
            let rankFont = CRT.Font.of(scale.rankSize)
            let rankAttrs: [NSAttributedString.Key: Any] = [.font: rankFont, .foregroundColor: inkColor]
            let rank = face.label as NSString
            let rankSz = rank.size(withAttributes: rankAttrs)

            // The suit under the numeral — v6.68: a normal card's ♠♥♦♣ is the
            // game's own pixel suit mark (PixelGlyph.suitImage — sized off
            // Scale.suitSize, red suits self-tint suit-red, black suits take
            // the card ink). The text path fell through to the system font,
            // where ♠/♣ blur together at card scale. JOKER's caption and the
            // blank "?" stay text.
            let suitMark: UIImage? = face.kind == .normal
                ? PixelGlyph.suitImage(face.suit, size: scale.suitSize, color: inkColor)
                : nil

            let suitText = face.kind == .joker ? "JOKER" : face.suit
            let suitFont = CRT.Font.of(face.kind == .joker ? scale.suitSize * 0.5 : scale.suitSize)
            let suitAttrs: [NSAttributedString.Key: Any] = [.font: suitFont, .foregroundColor: inkColor]
            let suit = suitText as NSString
            let suitSz: CGSize
            if let mark = suitMark { suitSz = mark.size }
            else if face.kind == .blank { suitSz = .zero }
            else { suitSz = suit.size(withAttributes: suitAttrs) }

            // VT323 carries a lot of internal leading; 0.72 packs the block the
            // way `line-height: 0.8` does in the web card. The pixel mark is
            // leading-free, so it buys a small explicit gap to sit where the
            // text glyph's built-in leading used to put it — the rank+suit
            // block stays centred as one unit either way.
            let suitGap: CGFloat = suitMark != nil ? (scale.suitSize * 0.15).rounded() : 0
            let blockH = rankSz.height * 0.72 + suitGap + suitSz.height
            var y = (box.height - blockH) / 2
            rank.draw(at: CGPoint(x: (box.width - rankSz.width) / 2, y: y - rankSz.height * 0.14),
                      withAttributes: rankAttrs)
            y += rankSz.height * 0.72 + suitGap
            if let mark = suitMark {
                mark.draw(at: CGPoint(x: ((box.width - suitSz.width) / 2).rounded(), y: y.rounded()))
            } else if suitSz != .zero {
                suit.draw(at: CGPoint(x: (box.width - suitSz.width) / 2, y: y), withAttributes: suitAttrs)
            }
        }

        imageCache[key] = img
        return img
    }

    /// Card backs = dither tile per deck (§5). Pinky's "pink" is the canonical
    /// red⊕cream checker; the others take their own two-palette mix.
    private static func backDither(_ deckId: String) -> (UIColor, UIColor) {
        switch deckId {
        case "pink":   return (CRT.suitRed, CRT.cardFace)    // "pink"
        case "garden": return (CRT.gold, CRT.feltDeep)       // "brass"
        case "rocko":  return (CRT.ink, CRT.cardFace)        // piebald check
        case "slyrex": return (CRT.phosphor, CRT.feltDeep)   // dino hide
        default:       return (CRT.feltMid, CRT.ink)
        }
    }
}

/// One rendered card on the board. A plain sprite — no shape nodes, no effects.
public final class CardNode: SKSpriteNode {
    public private(set) var face: CardArt.Face
    public private(set) var scale2: CardArt.Scale

    public init(face: CardArt.Face, scale: CardArt.Scale) {
        self.face = face
        self.scale2 = scale
        let tex = CardArt.texture(face, scale: scale)
        super.init(texture: tex, color: .clear, size: tex.size())
        // Anchor at the card box's top-left, ignoring the shadow bleed, so pile
        // stacking maths never has to think about the shadow.
        anchorPoint = CGPoint(x: 0, y: 1)
        zPosition = Layer.card
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    /// The card box WITHOUT the shadow — what layout measures against.
    public var boxSize: CGSize { scale2.size }

    public func setFace(_ face: CardArt.Face, scale: CardArt.Scale? = nil) {
        let s = scale ?? scale2
        guard face != self.face || s != scale2 else { return }
        self.face = face; self.scale2 = s
        let tex = CardArt.texture(face, scale: s)
        self.texture = tex
        self.size = tex.size()
    }
}
