import UIKit
import GameCore

/// THE ONE UIKit RENDERER for "a card face wearing its sticker chips" —
/// face + full chip fan BAKED into a single UIImage, drawn back-to-front so
/// the first sticker sits on top. Every UIKit surface that shows a stickered
/// card goes through here (deck inspect, pile fan, pack reveal, store card
/// tiles, picker banner).
///
/// WHY a baked image and never sibling chip views (v6.81 — the root cause of
/// the twice-recurring "deck view shows one sticker" bug): the view-based
/// idiom copied the fan's z-order from SpriteKit as
/// `chip.layer.zPosition = -i`, but a UIKit layer's zPosition competes with
/// EVERY sibling — so when chips sat next to the card faces in one container
/// (deck grid, fan box), chips 2…4 (z −1…−3) rendered UNDERNEATH all the
/// zPosition-0 card faces and only the first chip survived. The deal board
/// never had the bug because SpriteKit chips are children of their card
/// node; the shelf/pack surfaces never had it because they used this bake.
/// A single flattened image has no z to get wrong.
enum CardComposite {

    /// `extra` appends a sticker the card is ABOUT to gain (the picker
    /// banner's preview). The canvas grows by the fan's overhang/raise so
    /// nothing clips; a chipless card returns the bare face.
    static func image(_ c: CardSpec, extra: String? = nil,
                      scale: CardArt.Scale = .half) -> UIImage {
        bake(face: CardArt.image(CardArt.Face(c), scale: scale),
             stickers: c.stickers, extra: extra, scale: scale)
    }

    /// The BOARD-card overload (the pile fan shows LiveCards).
    static func image(_ c: LiveCard, scale: CardArt.Scale = .half) -> UIImage {
        bake(face: CardArt.image(CardArt.Face(c), scale: scale),
             stickers: c.stickers, extra: nil, scale: scale)
    }

    private static func bake(face: UIImage, stickers: [StickerRecord],
                             extra: String?, scale: CardArt.Scale) -> UIImage {
        var defs = stickers.compactMap { GameData.shared.stickerTypes.get($0.type) }
        if let extra, let d = GameData.shared.stickerTypes.get(extra) { defs.append(d) }
        defs = Array(defs.prefix(GameData.shared.items.maxStickersPerCard))
        guard !defs.isEmpty else { return face }
        // The card BOX is the canvas minus the baked hard shadow.
        let cardW = scale.size.width
        let placed = StickerChipLayout.frames(count: defs.count, cardWidth: cardW)
        let canvas = CGSize(width: face.size.width + StickerChipLayout.rightOverhang,
                            height: face.size.height + StickerChipLayout.topRaise)
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = UIScreen.main.scale
        return UIGraphicsImageRenderer(size: canvas, format: fmt).image { ctx in
            let cg = ctx.cgContext
            face.draw(at: CGPoint(x: 0, y: StickerChipLayout.topRaise))
            // First sticker on TOP: draw the fan back-to-front.
            for (i, d) in defs.enumerated().reversed() {
                let (rect, deg) = placed[i]
                let r = rect.offsetBy(dx: 0, dy: StickerChipLayout.topRaise)
                cg.saveGState()
                cg.translateBy(x: r.midX, y: r.midY)
                cg.rotate(by: deg * .pi / 180)
                cg.interpolationQuality = .none
                ItemArt.sticker(d, size: r.width).draw(
                    in: CGRect(x: -r.width / 2, y: -r.height / 2,
                               width: r.width, height: r.height))
                cg.restoreGState()
            }
        }
    }
}
