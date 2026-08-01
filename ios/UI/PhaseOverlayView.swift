import UIKit
import GameCore

/// THE shared full-screen phase overlay — the web's #overlay in all its modes:
/// deal-cleared (coin tally line by line + the score plaque), game over
/// ("Shoulda said…" + guess tiles + unlock progress), the "Pinky is home"
/// victory, Zen end, the deck/item unlock pops, and the mystery reveal.
public final class PhaseOverlayView: UIView {

    private let content = UIView()
    private var y: CGFloat = 0
    /// Autopilot marker: this overlay is the victory screen.
    var victoryTag = false

    private init(dim: CGFloat = 0.92) {
        super.init(frame: .zero)
        backgroundColor = CRT.feltDeep.withAlphaComponent(dim)
        addSubview(content)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    public override func layoutSubviews() {
        super.layoutSubviews()
        content.frame = CGRect(x: 0, y: 0, width: min(360, bounds.width - 24), height: y)
        content.center = CGPoint(x: bounds.midX, y: max(y / 2 + 40, bounds.midY - 20))
    }

    // MARK: - Builders

    private func addTitle(_ text: String, color: UIColor = CRT.phosphor, size: CGFloat = 17) {
        let l = CRTKit.label(text.uppercased(), size: size, color: color, display: true, glow: color == CRT.phosphor)
        l.textAlignment = .center
        l.frame = CGRect(x: 0, y: y, width: 360, height: size + 12)
        content.addSubview(l)
        y += size + 18
    }

    private func addBody(_ text: String, color: UIColor = CRT.cardFace, size: CGFloat = 15) {
        let l = CRTKit.label(text, size: size, color: color)
        l.textAlignment = .center
        let h = ceil(l.attributedText!.boundingRect(with: CGSize(width: 330, height: 400),
                                                    options: .usesLineFragmentOrigin, context: nil).height)
        l.frame = CGRect(x: 15, y: y, width: 330, height: h)
        content.addSubview(l)
        y += h + 10
    }

    private func addGap(_ g: CGFloat) { y += g }

    @discardableResult
    private func addButton(_ title: String, role: PixelButtonView.Role = .cta,
                           handler: @escaping () -> Void) -> PixelButtonView {
        let b = PixelButtonView(title, role: role, fontSize: 17)
        b.onTap = { Sound.shared.continueTap(); handler() }
        b.frame = CGRect(x: 55, y: y, width: 250, height: 48)
        content.addSubview(b)
        y += 58
        return b
    }

    private func addSprite(_ image: UIImage, size: CGSize) {
        let iv = UIImageView(image: image)
        iv.contentMode = .scaleAspectFit
        iv.layer.magnificationFilter = .nearest
        iv.frame = CGRect(x: (360 - size.width) / 2, y: y, width: size.width, height: size.height)
        content.addSubview(iv)
        y += size.height + 12
    }

    // MARK: - Deal cleared (the coin tally)

    static func dealCleared(info: GameFlowController.SummaryInfo,
                            onContinue: @escaping () -> Void) -> PhaseOverlayView {
        let v = PhaseOverlayView()
        v.addTitle("DEAL CLEARED")
        v.addBody(info.progress, color: CRT.muted, size: 14)
        v.addGap(6)
        // The reward lines appear ONE BY ONE, each with its RISING coin ping,
        // building to the total — the deal-won payoff moment.
        var delay = 0.35
        for (i, (label, amount)) in info.lines.enumerated() {
            let row = UILabel()
            row.attributedText = CRTKit.attributed("\(label)  +\(amount)", size: 16, color: CRT.gold)
            row.textAlignment = .center
            row.frame = CGRect(x: 15, y: v.y, width: 330, height: 20)
            row.alpha = 0
            v.content.addSubview(row)
            v.y += 22
            let lineIndex = i
            UIView.animate(withDuration: 0.22, delay: delay) { row.alpha = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                Sound.shared.coinTallyLine(lineIndex)
            }
            delay += 0.28
        }
        v.addGap(6)
        let total = UILabel()
        total.attributedText = CRTKit.attributed("◉ +\(info.earned)   ·   BALANCE \(info.balance)",
                                                 size: 19, color: CRT.gold)
        total.textAlignment = .center
        total.frame = CGRect(x: 15, y: v.y, width: 330, height: 24)
        total.alpha = 0
        v.content.addSubview(total)
        v.y += 30
        UIView.animate(withDuration: 0.25, delay: delay) { total.alpha = 1 }
        // SCORE is its own distinct plaque — never a line in the coin list.
        if info.product > 0 {
            let plaque = PixelPanelView(face: CRT.feltMid, border: CRT.phosphor)
            plaque.frame = CGRect(x: 60, y: v.y, width: 240, height: 46)
            let s = CRTKit.label("SCORE  \(info.aliveCount) × \(info.minAlive) = \(info.product)",
                                 size: 16, color: CRT.phosphor, glow: true)
            s.textAlignment = .center
            s.frame = CGRect(x: 0, y: 0, width: 240, height: 46)
            plaque.addSubview(s)
            plaque.alpha = 0
            v.content.addSubview(plaque)
            v.y += 56
            UIView.animate(withDuration: 0.25, delay: delay + 0.24) { plaque.alpha = 1 }
        }
        v.addGap(10)
        v.addButton("CONTINUE") { onContinue() }
        return v
    }

    // MARK: - Game over

    static func gameOver(info: GameFlowController.FailedInfo, seed: String,
                         nearest: [ItemUnlocks.NearMiss],
                         onNewClimb: @escaping () -> Void) -> PhaseOverlayView {
        let v = PhaseOverlayView()
        v.addTitle(info.wasEndless ? "THE CLIMB ENDS" : "SHOULDA SAID SAME", color: CRT.suitRed, size: 15)
        v.addBody(info.wasEndless ? "Endless depth reached — the win was already banked."
                                  : "The climb resets. Every card remembers.", color: CRT.muted, size: 14)
        v.addGap(8)
        // Guess tiles: correct / wrong / accuracy.
        let pct = info.correct + info.wrong > 0
            ? Int((Double(info.correct) / Double(info.correct + info.wrong) * 100).rounded()) : 0
        v.addBody("RIGHT \(info.correct)   ·   WRONG \(info.wrong)   ·   \(pct)%", size: 16)
        v.addBody("Cards played \(info.cardsFlipped)   ·   ◉ \(info.coinsEarned) earned", color: CRT.muted, size: 14)
        v.addGap(4)
        v.addBody("SEED · \(seed)", color: CRT.gold, size: 14)
        // Upcoming-unlock progress rows.
        if !nearest.isEmpty {
            v.addGap(8)
            for n in nearest {
                let label = PhaseOverlayView.itemLabel(n.id)
                v.addBody("\(label): \(n.current)/\(Int(n.count)) — \(n.hint)", color: CRT.muted, size: 13)
            }
        }
        v.addGap(12)
        v.addButton("NEW CLIMB") { onNewClimb() }
        return v
    }

    // MARK: - Victory

    static func pinkyHome(deckName: String, score: Int, coins: Int, cards: Int, bestScore: Int,
                          onEndless: @escaping () -> Void,
                          onMenu: @escaping () -> Void) -> PhaseOverlayView {
        let v = PhaseOverlayView()
        v.victoryTag = true
        v.addGap(8)
        v.addSprite(DeckCharacter.image(deckId: "pink", mood: .win, scale: 5),
                    size: CGSize(width: 96, height: 96))
        v.addTitle("\(deckName.uppercased()) IS HOME", size: 16)
        v.addBody("Mama ♥ was waiting at the top.", color: CRT.cardFace, size: 15)
        v.addGap(6)
        v.addBody("SCORE \(score)" + (bestScore > 0 ? "  ·  BEST \(bestScore)" : ""), color: CRT.phosphor, size: 16)
        v.addBody("◉ \(coins) earned  ·  \(cards) cards played", color: CRT.muted, size: 14)
        v.addGap(14)
        v.addButton("CONTINUE — ENDLESS MODE", role: .ctaOutline) { onEndless() }
        v.addButton("GO TO MAIN MENU", role: .plain) { onMenu() }
        return v
    }

    // MARK: - Zen end

    static func zenEnd(won: Bool, flips: Int, correct: Int,
                       onAgain: @escaping () -> Void,
                       onMenu: @escaping () -> Void) -> PhaseOverlayView {
        let v = PhaseOverlayView()
        v.addTitle(won ? "DECK CLEARED" : "THE PILES FELL", color: won ? CRT.phosphor : CRT.suitRed)
        let pct = flips > 0 ? Int((Double(correct) / Double(flips) * 100).rounded()) : 0
        v.addBody("\(flips) cards flipped  ·  \(correct) correct  ·  \(pct)%", size: 16)
        v.addGap(14)
        v.addButton("PLAY AGAIN", role: .cta) { onAgain() }
        v.addButton("MENU", role: .plain) { onMenu() }
        return v
    }

    // MARK: - Unlock pops

    static func deckUnlock(name: String, deckId: String,
                           onContinue: @escaping () -> Void) -> PhaseOverlayView {
        let v = PhaseOverlayView()
        v.addGap(10)
        v.addSprite(DeckCharacter.image(deckId: deckId, mood: .happy, scale: 5),
                    size: CGSize(width: 96, height: 96))
        v.addTitle("\(name.uppercased()) UNLOCKED", color: CRT.gold, size: 15)
        v.addBody("A new character joins the roster.", color: CRT.cardFace)
        v.addGap(12)
        v.addButton("CONTINUE") { onContinue() }
        // The color floods in with a bounce, to the sparkly ta-daa.
        Sound.shared.deckUnlock()
        v.content.transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
        UIView.animate(withDuration: 0.5, delay: 0.05, usingSpringWithDamping: 0.55,
                       initialSpringVelocity: 0.4) {
            v.content.transform = .identity
        }
        return v
    }

    static func itemUnlock(title: String, body: String,
                           onContinue: @escaping () -> Void) -> PhaseOverlayView {
        let v = PhaseOverlayView()
        v.addTitle(title, color: CRT.gold, size: 13)
        v.addBody(body, size: 14)
        v.addGap(12)
        v.addButton("CONTINUE") { onContinue() }
        v.content.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.6,
                       initialSpringVelocity: 0.3) {
            v.content.transform = .identity
        }
        return v
    }

    /// Resolve an item id to its label/description across every registry.
    static func itemDef(_ id: String) -> ItemDef? {
        let d = GameData.shared
        return d.stickerTypes.get(id) ?? d.pillarTypes.get(id) ?? d.baseTypes.get(id)
            ?? d.samePowerTypes.get(id) ?? d.packTypes.get(id)
    }
    static func itemLabel(_ id: String) -> String { itemDef(id)?.label ?? id }

    // MARK: - Mystery reveal

    static func mystery(outcome: MysteryOutcome,
                        onContinue: @escaping () -> Void) -> PhaseOverlayView {
        let v = PhaseOverlayView()
        v.addGap(6)
        // The "?" card art, rim-tinted by the outcome family.
        v.addSprite(MapArt.mysteryCard(open: true), size: CGSize(width: 60, height: 76))
        v.addTitle(outcome.title, color: outcome.good ? CRT.phosphor : CRT.suitRed, size: 15)
        v.addBody(outcome.desc, size: 15)
        if !outcome.cards.isEmpty {
            v.addGap(4)
            let row = UIView()
            let n = min(outcome.cards.count, 5)
            let w: CGFloat = 44
            for (i, c) in outcome.cards.prefix(5).enumerated() {
                let iv = UIImageView(image: CardArt.image(CardArt.Face(c), scale: .half))
                iv.contentMode = .scaleAspectFit
                iv.layer.magnificationFilter = .nearest
                iv.frame = CGRect(x: CGFloat(i) * (w + 8), y: 0, width: w, height: 61)
                row.addSubview(iv)
            }
            let rowW = CGFloat(n) * (w + 8) - 8
            row.frame = CGRect(x: (360 - rowW) / 2, y: v.y, width: rowW, height: 61)
            v.content.addSubview(row)
            v.y += 70
        }
        v.addGap(12)
        v.addButton("CONTINUE") { onContinue() }
        return v
    }
}
