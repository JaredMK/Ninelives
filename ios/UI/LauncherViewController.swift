import UIKit
import GameCore

/// TEMPORARY Phase 2 entry point — a debug launcher, not a game screen.
///
/// Picks a deck / tier / seed / pile count and starts a deal, so the board can
/// be exercised without the campaign shell. The real menu → deck select → map
/// flow is Phase 3; this whole file is expected to be deleted then.
public final class LauncherViewController: UIViewController {

    private let decks = GameMeta.deckOrder
    private let tiers = DifficultyData.tierIds
    private var deckIndex = 0
    private var tierIndex = 0
    private var pileCount = 9
    private var cardCount = 39
    private var seedText = "12345"
    private var withItems = false

    private let stack = UIStackView()
    private var deckButton = UIButton(type: .system)
    private var tierButton = UIButton(type: .system)
    private var pilesButton = UIButton(type: .system)
    private var cardsButton = UIButton(type: .system)
    private var itemsButton = UIButton(type: .system)
    private let seedField = UITextField()
    private let resultLabel = UILabel()

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = CRT.feltDeep

        let title = UILabel()
        title.text = "SHOULDA SAID SAME"
        title.font = CRT.Font.of(16, display: true)
        title.textColor = CRT.phosphor
        title.textAlignment = .center

        let sub = UILabel()
        sub.text = "phase 2 · deal board · debug launcher"
        sub.font = CRT.Font.of(16)
        sub.textColor = CRT.muted
        sub.textAlignment = .center

        seedField.text = seedText
        seedField.font = CRT.Font.of(20)
        seedField.textColor = CRT.cardFace
        seedField.backgroundColor = CRT.feltMid
        seedField.keyboardType = .numberPad
        seedField.textAlignment = .center
        seedField.layer.borderWidth = CRT.px
        seedField.layer.borderColor = CRT.ink.cgColor
        seedField.heightAnchor.constraint(equalToConstant: 40).isActive = true
        seedField.addTarget(self, action: #selector(seedChanged), for: .editingChanged)

        deckButton = makeButton(#selector(cycleDeck))
        tierButton = makeButton(#selector(cycleTier))
        pilesButton = makeButton(#selector(cyclePiles))
        cardsButton = makeButton(#selector(cycleCards))
        itemsButton = makeButton(#selector(toggleItems))

        let play = makeButton(#selector(startDeal), role: .cta)
        play.setTitle("START DEAL", for: .normal)
        play.heightAnchor.constraint(equalToConstant: 54).isActive = true

        resultLabel.font = CRT.Font.of(17)
        resultLabel.textColor = CRT.gold
        resultLabel.textAlignment = .center
        resultLabel.numberOfLines = 2

        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        [title, sub, deckButton, tierButton, pilesButton, cardsButton, itemsButton,
         labelled("SEED", seedField), play, resultLabel].forEach { stack.addArrangedSubview($0) }
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
        ])

        let dismissTap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        dismissTap.cancelsTouchesInView = false
        view.addGestureRecognizer(dismissTap)

        refresh()
        applyLaunchArguments()
    }

    /// Launch-argument overrides, so a deal can be started headlessly for
    /// screenshots and frame-timing runs:
    ///
    ///     -autoDeal 1 -piles 12 -seed 4242 -deck pink -tier regular -items 1 -fps 1
    private func applyLaunchArguments() {
        let d = UserDefaults.standard
        if let deck = d.string(forKey: "deck"), let i = decks.firstIndex(of: deck) { deckIndex = i }
        if let tier = d.string(forKey: "tier"), let i = tiers.firstIndex(of: tier) { tierIndex = i }
        if d.object(forKey: "piles") != nil { pileCount = max(1, min(12, d.integer(forKey: "piles"))) }
        if d.object(forKey: "cards") != nil { cardCount = max(13, min(52, d.integer(forKey: "cards"))) }
        if d.object(forKey: "seed") != nil { seedText = String(d.integer(forKey: "seed")); seedField.text = seedText }
        if d.object(forKey: "items") != nil { withItems = d.bool(forKey: "items") }
        refresh()
        if d.bool(forKey: "autoDeal") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.startDeal() }
        }
    }

    public override var prefersStatusBarHidden: Bool { true }

    private func labelled(_ text: String, _ field: UIView) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 10
        let l = UILabel()
        l.text = text
        l.font = CRT.Font.of(18)
        l.textColor = CRT.muted
        l.setContentHuggingPriority(.required, for: .horizontal)
        row.addArrangedSubview(l)
        row.addArrangedSubview(field)
        return row
    }

    private func makeButton(_ action: Selector, role: PixelButton.Role = .plain) -> UIButton {
        let b = UIButton(type: .system)
        b.titleLabel?.font = CRT.Font.of(19)
        b.backgroundColor = role == .cta ? CRT.phosphor : CRT.feltMid
        b.setTitleColor(role == .cta ? CRT.ink : CRT.cardFace, for: .normal)
        b.layer.borderWidth = CRT.px
        b.layer.borderColor = CRT.ink.cgColor
        b.heightAnchor.constraint(equalToConstant: 44).isActive = true
        b.addTarget(self, action: action, for: .touchUpInside)
        return b
    }

    @objc private func dismissKeyboard() { view.endEditing(true) }
    @objc private func seedChanged() { seedText = seedField.text ?? "" }
    @objc private func cycleDeck() { deckIndex = (deckIndex + 1) % decks.count; refresh() }
    @objc private func cycleTier() { tierIndex = (tierIndex + 1) % tiers.count; refresh() }
    @objc private func cyclePiles() {
        // 3 → 6 → 9 → 12, so the 12-pile worst case is one tap away.
        let options = [3, 6, 9, 12]
        pileCount = options[((options.firstIndex(of: pileCount) ?? 2) + 1) % options.count]
        refresh()
    }
    @objc private func cycleCards() {
        let options = [13, 26, 39, 52]
        cardCount = options[((options.firstIndex(of: cardCount) ?? 2) + 1) % options.count]
        refresh()
    }
    @objc private func toggleItems() { withItems.toggle(); refresh() }

    private func refresh() {
        deckButton.setTitle("DECK · \(decks[deckIndex].uppercased())", for: .normal)
        tierButton.setTitle("TIER · \(tiers[tierIndex].uppercased())", for: .normal)
        pilesButton.setTitle("PILES · \(pileCount)", for: .normal)
        cardsButton.setTitle("CARDS · \(cardCount)", for: .normal)
        itemsButton.setTitle("ITEMS · \(withItems ? "PILLARS + BASES + SAME-POWER" : "NONE")", for: .normal)
    }

    @objc private func startDeal() {
        view.endEditing(true)
        let data = GameData.shared
        // With items on, bind one of each class so the board's item visuals and
        // their live effects are all exercised.
        let pillars: [String?] = withItems
            ? [data.items.pillars.first(where: { $0.effect == "fibonacci" })?.id ?? data.pillarTypes.ids.first,
               data.items.pillars.first(where: { $0.effect == "columnAllAlive" })?.id,
               data.items.pillars.first(where: { $0.effect == "clubTribute" })?.id]
            : [nil, nil, nil]
        let bases: [String?] = withItems
            ? [data.items.bases.first(where: { $0.effect == "shuffleColumn" })?.id ?? data.baseTypes.ids.first,
               nil, nil]
            : [nil, nil, nil]

        let setup = DealController.Setup(
            deckId: decks[deckIndex],
            tier: tiers[tierIndex],
            seed: UInt32(truncatingIfNeeded: Int(seedText) ?? 12345),
            pileCount: pileCount,
            pillars: pillars,
            bases: bases,
            samePower: withItems ? data.samePowerTypes.ids.first : nil,
            sameCharge: false,
            cardCount: cardCount)

        let vc = DealViewController(setup: setup)
        vc.modalPresentationStyle = .fullScreen
        vc.onExit = { [weak self] win, coins, score in
            self?.resultLabel.text = win
                ? "DEAL CLEARED · +\(coins) coins · score \(score)"
                : "DEAL LOST · score \(score)"
            self?.dismiss(animated: false)
        }
        present(vc, animated: false)
    }
}
