import UIKit
import GameCore

/// One side of an OLD→NEW comparison (web `.sdc-side`): the tag, the object —
/// or the dashed empty silhouette when the slot is free, or a single glyph for
/// a side with no art (coins, the blind swap's unrevealed item) — the name,
/// and the description. The NEW side reads phosphor (the sanctioned accent).
///
/// Shared by the store's detail popup and the Old Joker's trade modal, so
/// "what you have → what you'd get" looks identical wherever it is asked.
final class CompareSideView: UIView {
    private let tagL = UILabel()
    private let objView = UIImageView()
    private let glyphL = UILabel()
    private let emptyBox = UIView()
    private let dash = CAShapeLayer()
    private let nameL = UILabel()
    private let descL = UILabel()
    private let emptySize: CGSize

    init(tag: String, isNew: Bool, emptySize: CGSize = CGSize(width: 46, height: 54)) {
        self.emptySize = emptySize
        super.init(frame: .zero)
        backgroundColor = CRT.feltDeep
        layer.borderWidth = isNew ? CRT.px : 1
        layer.borderColor = (isNew ? CRT.phosphor : CRT.ink).cgColor
        tagL.attributedText = CRTKit.attributed(tag, size: 14, color: CRT.muted)
        tagL.textAlignment = .center
        addSubview(tagL)
        objView.contentMode = .scaleAspectFit
        objView.layer.magnificationFilter = .nearest
        addSubview(objView)
        glyphL.textAlignment = .center
        glyphL.isHidden = true
        addSubview(glyphL)
        dash.fillColor = nil
        dash.strokeColor = CRT.cardFace.withAlphaComponent(0.35).cgColor
        dash.lineWidth = 2
        dash.lineDashPattern = [4, 3]
        emptyBox.layer.addSublayer(dash)
        addSubview(emptyBox)
        nameL.textAlignment = .center
        nameL.numberOfLines = 2
        descL.textAlignment = .center
        descL.numberOfLines = 0
        addSubview(nameL)
        addSubview(descL)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    func show(art: UIImage, name: String, desc: String) {
        objView.image = art
        objView.isHidden = false
        glyphL.isHidden = true
        emptyBox.isHidden = true
        nameL.attributedText = CRTKit.attributed(name, size: 14, color: CRT.cardFace)
        descL.attributedText = CRTKit.attributed(desc, size: 14, color: CRT.muted)
    }

    func showEmpty(name: String, desc: String) {
        objView.image = nil
        objView.isHidden = true
        glyphL.isHidden = true
        emptyBox.isHidden = false
        // `.sdc-none`: the "None equipped" line recedes to muted (italic in the
        // web — the pixel faces have no italic cut, muted carries it).
        nameL.attributedText = CRTKit.attributed(name, size: 14, color: CRT.muted)
        descL.attributedText = CRTKit.attributed(desc, size: 14, color: CRT.muted)
    }

    /// A side with no object to draw: the Old Joker's coins, or the blind
    /// swap's face-down "?" — one big glyph where the art would sit.
    func showGlyph(_ glyph: String, color: UIColor, name: String, desc: String) {
        objView.image = nil
        objView.isHidden = true
        emptyBox.isHidden = true
        glyphL.isHidden = false
        glyphL.attributedText = CRTKit.attributed(glyph, size: 34, color: color, display: true)
        nameL.attributedText = CRTKit.attributed(name, size: 14, color: CRT.cardFace)
        descL.attributedText = CRTKit.attributed(desc, size: 14, color: CRT.muted)
    }

    /// Lays the side out inside a fixed width; returns the height it needs.
    @discardableResult
    func layout(width w: CGFloat) -> CGFloat {
        var y: CGFloat = 7
        tagL.frame = CGRect(x: 4, y: y, width: w - 8, height: 14)
        y += 17
        objView.frame = CGRect(x: 6, y: y, width: w - 12, height: 58)
        glyphL.frame = objView.frame
        emptyBox.frame = CGRect(x: (w - emptySize.width) / 2, y: y + (58 - emptySize.height) / 2,
                                width: emptySize.width, height: emptySize.height)
        dash.path = UIBezierPath(rect: CGRect(origin: .zero, size: emptySize).insetBy(dx: 1, dy: 1)).cgPath
        y += 61
        let nameH = min(30, max(14, Self.measure(nameL, width: w - 8)))
        nameL.frame = CGRect(x: 4, y: y, width: w - 8, height: nameH)
        y += nameH + 3
        // v6.99: UNCLAMPED — the 62pt cap clipped the two-row v6.98 texts
        // mid-line in the Old Joker's trades (read as "doesn't wrap"). Both
        // hosts (store detail, the Joker modal) size rows from this return,
        // and the Joker modal scrolls.
        let descH = Self.measure(descL, width: w - 8)
        descL.frame = CGRect(x: 4, y: y, width: w - 8, height: descH)
        y += descH + 8
        return y
    }

    private static func measure(_ l: UILabel, width: CGFloat) -> CGFloat {
        guard let t = l.attributedText, t.length > 0 else { return 0 }
        return ceil(t.boundingRect(with: CGSize(width: width, height: 200),
                                   options: .usesLineFragmentOrigin, context: nil).height)
    }
}
