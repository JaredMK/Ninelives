import UIKit
import GameCore

/// THE ONE CARD-INFO RENDERER (v6.74). Every surface that explains a card or a
/// sticker — the pack-reveal info slot, the pickers' hold-help, the deck
/// inspector's help, the store detail's card display, the event overlays'
/// curse help — renders the SAME grammar at the SAME sizes:
///
///   CARD RANK+SUIT (or ★ Joker / ∅ Purge) LARGEST on top — `heading` (20),
///   display face, phosphor (gold/red when the subject IS a sticker/curse);
///   then, per sticker, its NAME in the bold display face — gold, suit-red
///   for a curse — followed by its registry description, both at `label`
///   (16). Names stay description-sized (the v6.72 canonical-name rule):
///   bold + colored, never oversized — the SIZE hierarchy belongs to the
///   card title alone.
///
/// Descriptions come from the registry, never hand-written. The component
/// measures itself with UILabel.sizeThatFits (boundingRect under-measures
/// VT323 — the v6.20 lesson), so a host that sizes to `sizeThatFits` can
/// never clip; hosts with a fixed shell embed it in a scroll view instead.
enum CardInfo {

    /// One sticker line: bold colored name, then its description.
    struct Row {
        let name: String
        let color: UIColor
        let desc: String
    }

    // The standard card-info steps on the house type scale (CRT.Font §3b).
    static let titleSize = CRT.Font.heading   // 20 — rank+suit, the largest
    // v6.83: the sticker NAME reads at the description's own size AND face,
    // set apart by COLOUR (gold, or curse-red) and faux BOLD instead. It used
    // to be drawn in the display face, which at the same point size renders
    // roughly twice the visual weight — the names read as a much bigger,
    // shoutier type step than the copy under them.
    static let nameSize = CRT.Font.label      // 16 — sticker name, body face + bold
    static let descSize = CRT.Font.label      // 16 — description, cream

    /// The canonical card title: "7 ♥" / "★ Joker" / "∅ Purge".
    static func title(for c: CardSpec) -> String {
        if c.joker { return "★ Joker" }
        if c.blank { return "∅ Purge" }
        let r = DeckManager.ranks.first { $0.value == c.currentRank }?.label ?? "\(c.currentRank)"
        return "\(r) \(c.suit)"
    }

    /// v6.91 PROVENANCE: the per-instance conversion note a converted
    /// curse carries — appended to its help text everywhere it appears.
    static func provenance(_ rec: StickerRecord) -> String {
        guard let from = rec.convertedFrom,
              let label = GameData.shared.stickerTypes.get(from)?.label else { return "" }
        return "\n(Converted from \(label))"
    }
    /// The first worn instance of `type` that carries a provenance note.
    static func provenance(onType type: String, of stickers: [StickerRecord]) -> String {
        stickers.first { $0.type == type && $0.convertedFrom != nil }
            .map(provenance) ?? ""
    }

    /// One row per sticker ON THE CARD, in worn order, copy from the registry.
    static func rows(for c: CardSpec) -> [Row] {
        c.stickers.compactMap { rec in
            guard let def = GameData.shared.stickerTypes.get(rec.type) else { return nil }
            return Row(name: def.label,
                       color: def.cursed ? CRT.suitRed : CRT.gold,
                       desc: def.description + provenance(rec))
        }
    }

    /// The LIVE-card variant (picker hold-help): duplicate instances fold to
    /// "×N" and the sticker's live state line rides under its description —
    /// the same content DealController's CardInfoText composes for the pile
    /// hold, structured so the names keep their bold display face.
    static func rows(for card: LiveCard) -> [Row] {
        var counts: [String: Int] = [:]
        for s in card.stickers { counts[s.type, default: 0] += 1 }
        var rows: [Row] = []
        for t in GameData.shared.stickerTypes.all() {
            guard let n = counts[t.id] else { continue }
            var desc = t.description
            // The live state line, when the sticker type carries one.
            if t.behavior == "suitImmunity", let suit = t.suit {
                desc += "\nAlways safe when a \(suit) is involved"
            } else if t.id == "compound" {
                desc += "\nBanked: +\(max(0, card.compoundHits - 1)) coins"
            } else if t.id == "snowball" {
                desc += "\nBuries next: \(card.snowball) card\(card.snowball == 1 ? "" : "s")"
            }
            rows.append(Row(name: t.label + (n > 1 ? " ×\(n)" : ""),
                            color: t.cursed ? CRT.suitRed : CRT.gold,
                            desc: desc + provenance(onType: t.id, of: card.stickers)))
        }
        return rows
    }

    /// The composed card-info string: title (largest) → optional plain
    /// paragraph → one name+description row per sticker.
    static func attributed(title: String? = nil,
                           titleColor: UIColor = CRT.phosphor,
                           titleGlow: Bool = false,
                           body: String? = nil,
                           rows: [Row] = [],
                           alignment: NSTextAlignment = .center) -> NSAttributedString {
        let out = NSMutableAttributedString()
        func para(_ after: CGFloat) -> NSMutableParagraphStyle {
            let p = NSMutableParagraphStyle()
            p.alignment = alignment
            p.lineBreakMode = .byWordWrapping
            p.paragraphSpacing = after
            return p
        }
        func append(_ attr: NSAttributedString, after: CGFloat) {
            let m = NSMutableAttributedString(attributedString: attr)
            m.addAttribute(.paragraphStyle, value: para(after),
                           range: NSRange(location: 0, length: m.length))
            out.append(m)
        }
        var needsNewline = false
        if let title, !title.isEmpty {
            append(CRTKit.attributed(title, size: titleSize, color: titleColor,
                                     display: true, glow: titleGlow), after: 8)
            needsNewline = true
        }
        if let body, !body.isEmpty {
            if needsNewline { out.append(NSAttributedString(string: "\n")) }
            append(CRTKit.attributed(body, size: descSize, color: CRT.cardFace),
                   after: rows.isEmpty ? 0 : 8)
            needsNewline = true
        }
        for (i, r) in rows.enumerated() {
            if needsNewline || i > 0 { out.append(NSAttributedString(string: "\n")) }
            let row = NSMutableAttributedString()
            row.append(CRTKit.attributed(r.name, size: nameSize, color: r.color,
                                         bold: true))
            row.append(CRTKit.attributed("  \(r.desc)", size: descSize,
                                         color: CRT.cardFace))
            append(row, after: i == rows.count - 1 ? 0 : 6)
            needsNewline = true
        }
        return out
    }
}

/// The self-measuring card-info block: one wrapping label, sized by its host
/// through `sizeThatFits` (never clipped), scrollable when the host's shell
/// is fixed.
final class CardInfoView: UIView {

    private let label = UILabel()
    private let alignment: NSTextAlignment

    init(alignment: NSTextAlignment = .center) {
        self.alignment = alignment
        super.init(frame: .zero)
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    func show(title: String? = nil,
              titleColor: UIColor = CRT.phosphor,
              titleGlow: Bool = false,
              body: String? = nil,
              rows: [CardInfo.Row] = []) {
        label.attributedText = CardInfo.attributed(title: title, titleColor: titleColor,
                                                   titleGlow: titleGlow, body: body,
                                                   rows: rows, alignment: alignment)
    }

    /// A deck card: title + one row per worn sticker (or the empty state).
    func show(card c: CardSpec, glow: Bool = true) {
        show(title: CardInfo.title(for: c), titleGlow: glow,
             body: c.stickers.isEmpty ? "No stickers on this card." : nil,
             rows: CardInfo.rows(for: c))
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        // UILabel, never boundingRect — VT323's real line height runs taller
        // than its measured fragments (v6.20), so a boundingRect-sized frame
        // clips the last line.
        let s = label.sizeThatFits(CGSize(width: size.width, height: .greatestFiniteMagnitude))
        return CGSize(width: size.width, height: ceil(s.height))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds
    }
}
