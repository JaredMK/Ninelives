import UIKit
import SpriteKit
import GameCore

/// THE exact web pixel art, extracted from the web build's boot-baked
/// `--spr-*` / `--pxi-*` data-URIs and bundled as PNGs (Assets/PixelArt).
/// Characters are the four 32×32 jar sprites × six states with tier overlay
/// sheets; icons are the hand-authored item faces. Everything scales
/// nearest-neighbour — the bitmap IS the pixel grid.
public enum ArtBundle {

    private static var cache: [String: UIImage] = [:]

    /// A bundled asset by its web var name (e.g. "spr-pink-idle",
    /// "pxi-mystery", "pxi-stk-rankUp"). Nil when the sheet has no such name.
    public static func image(_ name: String) -> UIImage? {
        if let c = cache[name] { return c }
        guard let path = Bundle.main.path(forResource: name, ofType: "png"),
              let img = UIImage(contentsOfFile: path) else { return nil }
        cache[name] = img
        return img
    }

    /// Character sheet state names, mapped from the renderer's moods.
    public static func stateName(_ mood: DeckCharacter.Mood) -> String {
        switch mood {
        case .idle, .blink: return "idle"
        case .looking: return "look"
        case .happy, .glad: return "happy"
        case .sad: return "sad"
        case .celebrate, .win: return "dance"
        }
    }

    private static var charCache: [String: UIImage] = [:]

    /// The character sprite with its tier accessory composited — exactly the
    /// web's base + `ov-<tier>` overlay pair.
    public static func character(deckId: String, mood: DeckCharacter.Mood,
                                 tier: String = "regular", trail: Bool = false) -> UIImage? {
        let state = trail ? "trail" : stateName(mood)
        let key = "\(deckId)|\(state)|\(tier)"
        if let c = charCache[key] { return c }
        guard let base = image("spr-\(deckId)-\(state)") else { return nil }
        let overlay = tier == "regular" ? nil : image("spr-\(deckId)-ov-\(tier)")
        guard let overlay else { charCache[key] = base; return base }
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        let out = UIGraphicsImageRenderer(size: base.size, format: fmt).image { ctx in
            ctx.cgContext.interpolationQuality = .none
            base.draw(at: .zero)
            overlay.draw(at: .zero)
        }
        charCache[key] = out
        return out
    }

    /// The sticker's own hand-authored face icon (`pxi-stk-<id>`), the
    /// cursed faces, or nil for stickers without one.
    public static func stickerIcon(_ def: ItemDef) -> UIImage? {
        if def.cursed {
            return image(def.id.hasSuffix("2") ? "pxi-stickerCursed2" : "pxi-stickerCursed")
        }
        return image("pxi-stk-\(def.id)")
    }

    /// A pack's packet art by its kind/size.
    public static func packArt(_ def: ItemDef) -> UIImage? {
        if def.kind == "sticker" { return image("pxi-packSticker") }
        if def.int("size", 1) >= 5 { return image("pxi-packLarge") }
        return image("pxi-packCard")
    }

    /// An SKTexture wrapper (nearest) for scene use.
    public static func texture(_ name: String) -> SKTexture? {
        guard let img = image(name) else { return nil }
        return PixelTexture.texture(from: img)
    }

    /// A UIImageView pre-configured for pixel scaling.
    public static func view(_ name: String, scale: CGFloat = 1) -> UIImageView {
        let iv = UIImageView(image: image(name))
        iv.layer.magnificationFilter = .nearest
        iv.contentMode = .scaleAspectFit
        if let img = iv.image {
            iv.frame = CGRect(x: 0, y: 0, width: img.size.width * scale, height: img.size.height * scale)
        }
        return iv
    }
}
