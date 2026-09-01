import Foundation

/// GameEngine — rules + flow. Pure logic: it emits events and never touches the
/// renderer. `status` is "idle" | "playing" | "won" | "lost".
public final class GameEngine {
    // Construction inputs
    let deckSpecs: [CardSpec]
    let pileCount: Int
    let runConfig: RunConfig
    let data: GameData
    let cols: [Int]?

    // Live state
    public internal(set) var status = "idle"
    public private(set) var deck: Deck!
    public private(set) var board: BoardState!
    public private(set) var run: RunState!
    /// The run's seeded rng, shared by the deck + board shuffles.
    var rng: RNG!
    /// Same Charge — a correct Same banks it (max 1); it auto-fires as the
    /// LAST-priority backstop to save a pile from death.
    public internal(set) var sameCharge: Bool
    /// The equipped Same-Power id, snapshotted from the campaign at deal start.
    var samePowerId: String?
    var samePowerVariant: String?
    var pillarRankVariants: [String: Int] = [:]
    /// The shop-rolled items' climb-locked {rank}/{suit} (v6.76), seeded from
    /// the campaign via RunConfig and handed to each deal's RunState.
    var shopRolls: [String: ShopRoll] = [:]
    /// Scratch: Second Wind rolled and missed for this column (consumed by
    /// the death path's miss emit — presentation only, never rules).
    var secondWindMissCol: Int?

    /// The log entry in-flight cascade lines append to.
    var currentEntry: Int?
    /// Debug logbook: WHAT TRIGGERED the item fire in flight (e.g.
    /// "5♥ on 7♠ · pile 3 · higher"). Set at every action's entry, cleared at
    /// its exit, cited by every ⚡ fire line `recT` writes (v6.55).
    var fireContext: String?

    var listeners: [(EngineEvent) -> Void] = []
    /// Fail-silent telemetry hook (playtest balancing only — never affects play).
    public var telemetry: ((_ klass: String, _ id: String, _ label: String, _ impacts: [String: Double]) -> Void)?

    let economy: Economy

    public init(deckSpecs: [CardSpec], pileCount: Int, runConfig: RunConfig = RunConfig(), data: GameData = .shared) {
        self.deckSpecs = deckSpecs
        self.pileCount = pileCount
        self.runConfig = runConfig
        self.data = data
        self.cols = (runConfig.cols?.isEmpty == false) ? runConfig.cols : nil
        self.sameCharge = runConfig.sameCharge
        self.samePowerId = runConfig.samePower
        self.samePowerVariant = runConfig.samePowerVariant
        self.pillarRankVariants = runConfig.pillarRankVariants
        self.shopRolls = runConfig.shopRolls
        self.economy = Economy(data: data)
    }

    public func on(_ fn: @escaping (EngineEvent) -> Void) { listeners.append(fn) }
    func emit(_ e: EngineEvent) { for fn in listeners { fn(e) } }

    func recT(_ klass: String, _ id: String, _ label: String, _ impacts: [String: Double]) {
        telemetry?(klass, id, label, impacts)
        logFire(klass, label, impacts)
    }

    // MARK: - Probability feedback (v6.57)

    /// Make an item's %-CHANCE roll and REPORT it: emits `.rollResult` (the
    /// structured hit/miss the UI renders) and, on a miss, writes the logbook
    /// line — a silent roll becomes a visible one. Consumes exactly ONE rng
    /// draw, the same draw the inline `rng.next() < chance` it replaces made,
    /// so web-trace parity holds. Call it ONLY where the roll genuinely
    /// happens (a precondition that skips the roll must skip this too).
    func rollChance(_ klass: String, _ id: String, _ label: String, _ chance: Double,
                    index: Int? = nil, col: Int? = nil) -> Bool {
        let hit = rng.next() < chance
        emit(.rollResult(RollResult(id: id, label: label, klass: klass, chance: chance,
                                    hit: hit, index: index, col: col)))
        // The miss rides the same telemetry hook with a `missed` impact, so the
        // balancing feed sees the rolls that did NOTHING too.
        if !hit { telemetry?(klass, id, label, ["missed": 1]); logRollMiss(klass, label, chance) }
        return hit
    }

    /// The miss line — logFire's shape, but there is no fire to itemize:
    /// "⚡ Saboteur [sticker] — rolled, missed (10%) ↩ 5♥ on 7♠ · pile 3 · higher".
    func logRollMiss(_ klass: String, _ label: String, _ chance: Double) {
        let pct = jsNum(chance * 100)
        let line = "⚡ \(label) [\(klass)] — rolled, missed (\(pct)% chance)"
            + (fireContext.map { " ↩ \($0)" } ?? "")
        if currentEntry != nil { logLine(line) } else { logAction(line) }
    }

    /// v6.55: EVERY item fire lands in the debug logbook through here — the
    /// name, its EFFECT (read off the telemetry impacts), and WHAT TRIGGERED
    /// it (`fireContext`). Debug-only: it rides `run.log`, which game logic
    /// never reads, and drains into the DebugEventLog after every action.
    /// Nested under the open action entry when there is one; standalone (with
    /// the context carrying the "when") for the fires that precede it.
    func logFire(_ klass: String, _ label: String, _ impacts: [String: Double]) {
        var parts: [String] = []
        for (k, v) in impacts.sorted(by: { $0.key < $1.key }) where v != 0 {
            switch k {
            case "coins":     parts.append("+\(jsNum(v)) coins")
            case "coinsLost": parts.append("−\(jsNum(v)) coins")
            case "peeks":     parts.append("peek \(Int(v))")
            case "buried":    parts.append("buried \(Int(v))")
            case "saves":     parts.append(v == 1 ? "save" : "\(Int(v)) saves")
            case "shuffled":  parts.append("shuffled \(Int(v))")
            case "moved":     parts.append("moved \(Int(v))")
            case "applied":   parts.append(v > 1 ? "\(Int(v)) stickers applied" : "sticker applied")
            case "hints":     parts.append("\(Int(v)) hint\(v == 1 ? "" : "s")")
            case "kills":     parts.append("kill")
            case "destroyed": parts.append("destroyed \(Int(v))")
            case "purged":    parts.append("purged \(Int(v))")
            case "revived":   parts.append("revived")
            case "copies":    parts.append("copied \(Int(v))")
            case "cards":     parts.append("\(Int(v)) cards")
            case "recolored": parts.append("recolored \(Int(v))")
            case "peeled":    parts.append("peeled \(Int(v))")
            default:          parts.append("\(k) \(Int(v))")
            }
        }
        let line = "⚡ \(label) [\(klass)] — " + (parts.isEmpty ? "fired (no effect)" : parts.joined(separator: ", "))
            + (fireContext.map { " ↩ \($0)" } ?? "")
        if currentEntry != nil { logLine(line) } else { logAction(line) }
    }

    // MARK: - Registry shortcuts

    var stickerTypes: ItemRegistry { data.stickerTypes }
    var pillarTypes: ItemRegistry { data.pillarTypes }
    var baseTypes: ItemRegistry { data.baseTypes }
    var samePowerTypes: ItemRegistry { data.samePowerTypes }

    func matchesSuit(_ c: LiveCard?, _ s: String) -> Bool { CardRules.matchesSuit(c, s, data: data) }

    // MARK: - Columns

    /// Map each pile index to its column. Piles fill DOWN each column in turn, so
    /// e.g. [3,4,3] → [0,0,0,1,1,1,1,2,2,2].
    static func buildPileColumns(_ colSizes: [Int], _ count: Int) -> [Int] {
        var map = [Int](repeating: 0, count: count)
        var p = 0
        for c in 0..<colSizes.count where p < count {
            var k = 0
            while k < colSizes[c] && p < count { map[p] = c; p += 1; k += 1 }
        }
        return map
    }

    /// The EFFECTIVE Pillar def for a column, resolving Ditto: a Ditto column
    /// dynamically mirrors the center column's Pillar (applied to its OWN
    /// column). Every read of "the Pillar on a column" goes through here.
    func resolvePillarDef(_ col: Int?) -> ItemDef? {
        guard let col, let run, let pillars = run.pillars, col >= 0, col < pillars.count else { return nil }
        // JAMMER curse: while a jammer card tops an alive pile in this
        // column, the column's pillar does not function — every read (fires,
        // payout, size hooks, badges) sees no pillar at all.
        if board != nil, columnJammed(col) { return nil }
        guard let pid = pillars[col] else { return nil }
        guard let def = pillarTypes.get(pid) else { return nil }
        if def.effect != "ditto" { return def }
        guard let center = centerColumn(), col != center else { return nil }   // Ditto in/at center → nothing
        guard let cpid = pillars[center], cpid != "ditto" else { return nil }  // center empty / another Ditto
        return pillarTypes.get(cpid)
    }

    func pillarForPile(_ index: Int) -> ItemDef? {
        guard let pc = run?.pileColumns else { return nil }
        return resolvePillarDef(pc[index])
    }

    /// The middle (center) column index for this run, or nil with no layout.
    func centerColumn() -> Int? {
        guard let c = run?.cols else { return nil }
        return c.count / 2
    }

    /// Pile indices that belong to column `col` (in board order).
    func colPiles(_ col: Int?) -> [Int] {
        guard let col, let pc = run?.pileColumns else { return [] }
        return (0..<pc.count).filter { pc[$0] == col }
    }
    func colAlivePiles(_ col: Int?) -> [Int] { colPiles(col).filter { board.isActive($0) } }
    func colDeadPiles(_ col: Int?) -> [Int] { colPiles(col).filter { !board.isActive($0) } }
    func allAlivePiles() -> [Int] { (0..<board.size).filter { board.isActive($0) } }
    func allDeadPiles() -> [Int] { (0..<board.size).filter { !board.isActive($0) } }

    // MARK: - Debug logbook

    /// Display-only ring buffer: keep the newest LOG_CAP entries, trimmed in
    /// batches so the prune is amortized O(1) per append.
    static let logCap = 200, logSlack = 64

    func pushLog(_ entry: LogEntry) {
        guard let run else { return }
        run.log.append(entry)
        if run.log.count > Self.logCap + Self.logSlack {
            run.log.removeFirst(run.log.count - Self.logCap)
        }
    }
    @discardableResult
    func logBegin(_ title: String) -> Int {
        pushLog(LogEntry(title: title, lines: []))
        currentEntry = run.log.count - 1
        return currentEntry!
    }
    func logLine(_ text: String) {
        guard let i = currentEntry, let run, i < run.log.count else { return }
        run.log[i].lines.append(text)
    }
    /// Append a complete standalone entry (system / UI actions).
    func logAction(_ title: String, _ lines: [String] = []) {
        pushLog(LogEntry(title: title, lines: lines))
    }
    func cardName(_ c: LiveCard?) -> String {
        guard let c else { return "?" }
        return c.joker ? "★ Joker" : (c.label + c.suit)
    }

    // MARK: - Shared effect primitives

    /// Bury `count` cards from the deck's BOTTOM under pile `index` (hidden).
    /// Returns how many were actually buried. The cards never appear in any event
    /// payload — composition shifts only, draw order is never revealed.
    @discardableResult
    func buryTribute(_ index: Int, _ count: Int, _ source: String) -> Int {
        var buried = 0
        var k = 0
        while k < count && !deck.isEmpty {
            board.pushBottom(index, deck.drawFromBottom())
            buried += 1
            k += 1
        }
        if buried > 0 {
            logLine((source.isEmpty ? "" : source + ": ") + "\(buried) card\(buried > 1 ? "s" : "") buried, deck −\(buried)")
            emit(.buried(index: index, count: buried, source: source))
        }
        return buried
    }

    /// Add (or subtract) live bonus coins and itemize them by label, so both the
    /// HUD counter and the run-end breakdown read one source.
    func addBonus(_ label: String, _ amount: Double) {
        guard let run, amount != 0 else { return }
        run.bonusCoins += amount
        run.bonusEvents.add(label, amount)
        logLine("\(amount >= 0 ? "+" : "")\(jsNum(amount)) coins — \(label)")
    }

    /// Presentation hook: announce that a Pillar effect fired on a column. PURE
    /// SIGNAL — it changes no state, value, or timing.
    func firePillar(_ col: Int?, _ effect: String, _ label: String, _ amount: Double,
                    moves: [(from: Int, to: Int)] = []) {
        guard let col else { return }
        emit(.pillarFired(col: col, effect: effect, label: label, amount: amount, moves: moves))
    }

    /// Pay a Pillar's coins live: tally + UI fire. The single chokepoint for a
    /// live Pillar coin payout.
    func payPillar(_ col: Int?, _ effect: String, _ label: String, _ amount: Double) {
        addBonus(label, amount)
        firePillar(col, effect, label, amount)
        if let pdef = resolvePillarDef(col) {
            recT("pillar", pdef.id, pdef.label, amount > 0 ? ["coins": amount] : ["coinsLost": -amount])
        }
    }

    /// Arm a column-scoped peek Pillar (Unearth / Last Rites / Static): reveal
    /// the next upcoming card via the EXISTING deck-reveal path and pulse the
    /// firing column.
    func peekPillar(_ col: Int?, _ def: ItemDef?) {
        guard let col, let def else { return }
        run.revealNextActive = true
        firePillar(col, def.effect ?? "", def.label, 0)
        recT("pillar", def.id, def.label, ["peeks": 1])
        logLine("\(def.label.isEmpty ? "Peek" : def.label): peeking the next upcoming card")
    }

    /// The alive pile with the smallest (weighted) size, excluding `not`. Ties
    /// break to the lowest index. nil if no other alive pile.
    func smallestAlivePileExcept(_ not: Int) -> Int? {        var best: Int? = nil, bestSize = Int.max
        for i in 0..<board.size {
            if i == not || !board.isActive(i) { continue }
            let sz = board.pileSize(i)
            if sz < bestSize { bestSize = sz; best = i }
        }
        return best
    }

    /// Pick one element from a list using the run rng (uniform).
    func pick<T>(_ list: [T]) -> T? {
        list.isEmpty ? nil : list[rng.index(list.count)]
    }

    // MARK: - Sticker pools + projection

    /// The "safe" random-sticker pool a Base may apply: no suit-locked stickers
    /// and nothing that changes a card's suit, not the setup-only Duplicate, and
    /// never a CURSED sticker.
    func baseStickerPool() -> [ItemDef] {
        grantableStickers().filter { $0.suit == nil && $0.behavior != "changeSuitRandom" && $0.behavior != "duplicate" }
    }

    /// The grant pool — cursed stickers excluded, item-unlock gates applied by
    /// the injected predicate (the campaign supplies the live unlock record).
    public var isStickerUnlocked: (ItemDef) -> Bool = { _ in true }
    func grantableStickers() -> [ItemDef] {
        stickerTypes.grantableBase().filter(isStickerUnlocked)
    }

    /// PAUPER family (v6.76): the LIVE campaign purse, threaded in by the flow
    /// — coins are not engine state (the Empty Purse / `purseCoins` precedent),
    /// and the gate re-evaluates at EVERY landing, so a closure, not a snapshot.
    /// nil (unwired flows, fixtures, legacy tests) reads as "not broke": the
    /// paupers sleep and legacy rng streams stay untouched.
    public var purseCoinsProvider: (() -> Int)?
    /// Is the purse under this def's `purseBelow` ceiling RIGHT NOW?
    func purseBelow(_ def: ItemDef) -> Bool {
        guard let provider = purseCoinsProvider else { return false }
        return provider() < def.int("purseBelow", 0)
    }

    // MARK: - Full-deck composition (v6.76 archetype batch, R3)

    /// FULL-OWNED-DECK hook (v6.78, the web's setCompositionHook parity):
    /// campaign deals inject the LIVE owned deck here, so composition
    /// conditions read the whole collection even on SUBSET deals — the
    /// deck the histogram shows. Unset (zen, bare engine runs) falls back
    /// to the deal's own cards, the pre-hook behaviour.
    public var fullDeckProvider: (() -> [LiveCard])?

    /// EVERY card the composition conditions count: the injected full
    /// owned deck when the campaign provides it; otherwise the remaining
    /// draw deck + every pile's cards (alive AND dead — a dead pile's
    /// cards are buried in the board, not gone) + a parked Second Wind's
    /// held-out killer. Read LIVE at each check, so mid-deal purges and
    /// deck changes all move them.
    func fullDeckCards() -> [LiveCard] {
        if let provider = fullDeckProvider { return provider() }
        var out = deck.peekAll()
        for p in board.piles { out.append(contentsOf: p.cards) }
        if let sw = run?.pendingSecondWind { out.append(sw.killingCard) }
        return out
    }

    /// Ranks with ZERO copies in the full deck — the Empty Ranks family's
    /// shared CONDITION (v6.87: three legs, three effect keys — bury /
    /// coins / pile size — nothing else shared).
    func zeroCopyRankCount() -> Int {
        let counts = fullDeckRankCounts()
        return (minRank...maxRank).filter { (counts[$0] ?? 0) == 0 }.count
    }

    /// Rank → copies among the full deck's RANKED cards (jokers/blanks are
    /// rankless and never count).
    func fullDeckRankCounts() -> [Int: Int] {
        var out: [Int: Int] = [:]
        for c in fullDeckCards() where !c.joker && !c.blank { out[c.value, default: 0] += 1 }
        return out
    }

    /// Suit → copies by PRINTED suit (jokers/blanks excluded; a Wild Suit
    /// sticker counts as its printed suit here — the campaign's
    /// `suitComposition()` reads composition the same way).
    func fullDeckSuitCounts() -> [String: Int] {
        var out: [String: Int] = [:]
        for c in fullDeckCards() where !c.joker && !c.blank { out[c.suit, default: 0] += 1 }
        return out
    }

    /// The full deck's most-copied rank; TIES BREAK TO THE LOWEST RANK (the
    /// ascending scan keeps the incumbent). nil when no ranked cards remain.
    /// Public (v6.89): the Chorus confirm prompt names this before firing.
    public func mostCopiedRank() -> Int? {
        let counts = fullDeckRankCounts()
        var best: Int? = nil
        for r in minRank...maxRank {
            let n = counts[r] ?? 0
            if n > 0 && (best == nil || n > (counts[best!] ?? 0)) { best = r }
        }
        return best
    }

    /// The stickers Wild Sticker may roll for THIS top: never onto a Joker or
    /// Removal card, `suits` restrictions respected, and never a rank sticker at
    /// its boundary (+1 on an Ace / −1 on a 2 — the campaign-side persist would
    /// refuse it and the sticker would silently vanish).
    func wildStickerPoolFor(_ top: LiveCard?) -> [ItemDef] {
        guard let top, !runConfig.noStickers else { return [] }
        return baseStickerPool().filter { t in
            guard CardRules.stickerEligible(top, t.id, data: data) else { return false }
            guard t.kind == "rank" else { return true }
            let delta = t.num("rankDelta", 0)
            return (delta <= 0 || top.value < 14) && (delta >= 0 || top.value > 2)
        }
    }

    /// Project a sticker's LIVE effect onto a board card in place (rank → value;
    /// behavior → flags). This mutates the run-deck/board card only (effective
    /// for this deal); it does NOT write the sticker back to the campaign card.
    @discardableResult
    func projectStickerOntoCard(_ card: LiveCard?, _ typeId: String) -> Bool {
        guard let card, let t = stickerTypes.get(typeId) else { return false }
        if runConfig.noStickers { return false }                              // Rocko
        guard CardRules.stickerEligible(card, typeId, data: data) else { return false }
        card.stickers.append(StickerRecord(type: typeId))
        func setRank(_ v: Int) {
            card.value = max(2, min(14, v))
            if let rk = DeckManager.ranks.first(where: { $0.value == card.value }) { card.label = rk.label }
        }
        if t.kind == "rank" { setRank(card.value + t.int("rankDelta", 0)) }
        else if t.behavior == "randomFixedValue" { setRank(2 + rng.index(13)) }
        else if t.behavior == "tieSafe" { card.tieSafe = true }
        else if t.behavior == "wildSuit" { card.wildSuit = true }
        else if t.behavior == "revealNext" { card.revealNext = true }
        else if t.behavior == "suitImmunity", let s = t.suit, !card.suitGuards.contains(s) {
            card.suitGuards.append(s)
        }
        return true
    }

    /// The "tally value" of a card for Suit Tally: number cards score their
    /// value; face cards (J/Q/K) and the Ace score 10.
    func tallyValue(_ card: LiveCard?) -> Int {
        guard let card else { return 10 }
        return card.value <= 10 ? card.value : 10
    }

    // MARK: - Start / startRun

    /// Run Start phase: new seed, seeded shuffle, deal. `seedOverride` lets a
    /// caller re-deal a known board (resume replays the saved board; Redeal
    /// reshuffles with a fresh RANDOM seed). The shuffle order itself is never
    /// surfaced — only the seed travels.
    public func start(seedOverride: UInt32? = nil) {
        let seed = seedOverride ?? RNG.generateSeed()
        let pileColumns = cols.map { GameEngine.buildPileColumns($0, pileCount) }
        run = RunState(seed: seed, cols: cols, pileColumns: pileColumns,
                       pileCount: pileCount, samePower: samePowerId)
        run.samePowerVariant = samePowerVariant
        run.pillarRankVariants = pillarRankVariants
        run.shopRolls = shopRolls
        currentEntry = nil
        fireContext = nil
        // A shuffled COPY of the campaign deck — deterministic per seed.
        rng = RNG(seed: seed)
        deck = DeckManager.create(deckSpecs, rng: rng, data: data)
        board = BoardState(size: pileCount, data: data)
        status = "playing"
        // Deal one face-up card into each pile.
        for i in 0..<board.size { board.push(i, deck.draw()) }
        logAction("Climb dealt — \(board.size) piles, \(deck.remaining()) cards in deck")
        // Roll this deal's Base randomizers. Only when columns are in play (so a
        // legacy/test run's rng sequence is untouched). The Suit Tally suit is
        // picked from the suits actually PRESENT this deal.
        if cols != nil {
            var present: [String] = []                 // insertion-ordered, like a JS Set
            for i in 0..<board.size {
                if let t = board.top(i), !present.contains(t.suit) { present.append(t.suit) }
            }
            for c in deck.peek(deck.remaining()) where !present.contains(c.suit) { present.append(c.suit) }
            run.baseRandom = (value: 2 + rng.index(13),
                              suit: present.isEmpty ? nil : present[rng.index(present.count)])
        }
        // Sticker phase: dealt, awaiting Start Run. `phase` stays "start".
        emit(.dealt)
    }

    /// End the sticker phase and begin active play. Idempotent; only valid while
    /// playing and not already started. Closes the sticker window (anti-exploit)
    /// and emits `runStarted`.
    public func startRun(pillars: [String?]? = nil, bases: [String?]? = nil, samePower: String?? = nil) {
        guard status == "playing", let run, !run.started else { return }
        run.started = true
        run.stickerWindow = false
        run.phase = "active"
        // Snapshot the initial deal's draws so "cards drawn during play" excludes
        // the face-up pile cards dealt before active play began.
        run.dealDraws = deck.drawn()
        // Lock the per-column Pillar binding for the run (a snapshot — later
        // campaign edits can't affect a run in progress).
        run.pillars = pillars
        // Install the board's PILLAR size/anchor hooks. They read LIVE run state
        // each call, so Heavy Diamond, Streak Size and Diamond Anchor stay
        // correct as cards/streaks change. Board sizing itself stays generic.
        board.setPillarSizeHook { [weak self] pileIndex in
            guard let self, let col = self.run.pileColumns?[pileIndex],
                  let def = self.resolvePillarDef(col) else { return 0 }
            if def.effect == "heavyDiamond" {
                var n = 0
                for c in self.board.piles[pileIndex].cards where self.matchesSuit(c, "♦") { n += 1 }
                return n * def.int("value", 1)
            }
            if def.effect == "streakSize" {
                let s = self.run.colStreak?[col] ?? 0
                let th = def.int("threshold", 3)
                return s >= th ? (s - th + 1) : 0
            }
            return 0
        }
        board.setPillarAnchorHook { [weak self] pileIndex in
            guard let self, let col = self.run.pileColumns?[pileIndex],
                  let def = self.resolvePillarDef(col), def.effect == "diamondAnchor" else { return false }
            return self.matchesSuit(self.board.top(pileIndex), "♦")
        }
        run.bases = bases
        // Lock the equipped Same-Power. Finalized HERE from the setup, exactly
        // like Pillars/Bases — the engine was created at deal entry, BEFORE the
        // setup equip window. Only override when explicitly passed (engine tests
        // seed it via runConfig at create).
        if let sp = samePower { run.samePower = sp }
        // GAMBLER: roll the deal-end coin flip ONCE per Gambler column, here at
        // Start Run, and memoize it (run.gamblerFlips). Every later payout read
        // — the mid-deal HUD projection AND the deal-cleared summary — shows
        // the SAME result, and no read consumes the action-stream rng. A column
        // JAMMED at Start Run (resolvePillarDef sees no pillar) rolls on its
        // first payout read instead — the old behavior, confined to that edge.
        if let pillars = run.pillars {
            for c in 0..<pillars.count {
                if let def = resolvePillarDef(c), def.effect == "gambler" {
                    run.gamblerFlips?[c] = rollChance("pillar", def.id, def.label,
                                                      def.num("chance", 0.5), col: c)
                }
            }
        }
        // SCARCE SUIT (v6.81 — the Daily Suit rework): the shielded suit is
        // no longer a roll. Each deal start reads the FULL deck and shields
        // the suit it holds the FEWEST of. A suit you hold NONE of counts as
        // the scarcest and IS chosen (v6.82, user's call — zero is the
        // smallest number; the shield then simply has nothing to catch until
        // that suit re-enters the deck). Ties break by the canonical suit
        // order, deterministically, so no rng is ever drawn. Recomputed here
        // every Start Run (a redeal re-runs it; a mid-deal restore keeps the
        // snapshot's value).
        if let pillars = run.pillars, run.dailySuits != nil {
            let counts = fullDeckSuitCounts()
            let scarce = DeckManager.suits.map(\.symbol)
                .min { (counts[$0] ?? 0) < (counts[$1] ?? 0) }
            for c in 0..<pillars.count {
                if let def = resolvePillarDef(c), def.effect == "suitShieldDaily", let scarce {
                    run.dailySuits?[c] = scarce
                    recT("pillar", def.id, def.label, ["fires": 1])
                }
            }
        }
        // RANK SHIELD (dynamic, v6.78): at Start Run the shield re-reads the
        // FULL deck and protects its most common rank, writing the pick into
        // `run.shopRolls["rankShield"]` — the slot `landingSave` already
        // reads, so the save rule itself is untouched. TIE RULE: the
        // INCUMBENT (the entry carried in from the campaign — the rank
        // that's been most common longest) keeps the shield until STRICTLY
        // surpassed; a tie with no surviving incumbent picks among the
        // leaders off the deal's seeded stream (the Daily Suit precedent —
        // only deals carrying the pillar ever draw, and only on a real
        // multi-way tie). The controller adopts the pick back into the
        // campaign after startRun, so the incumbent persists across deals;
        // a mid-deal restore overwrites run.shopRolls from the snapshot.
        if let pillars = run.pillars,
           (0..<pillars.count).contains(where: { resolvePillarDef($0)?.effect == "rankShield" }) {
            let counts = fullDeckRankCounts()
            if let maxCount = counts.values.max(), maxCount > 0 {
                let incumbent = run.shopRolls["rankShield"]?.rank
                let chosen: Int
                if let inc = incumbent, (counts[inc] ?? 0) >= maxCount {
                    chosen = inc                       // never strictly surpassed
                } else {
                    let leaders = (minRank...maxRank).filter { (counts[$0] ?? 0) == maxCount }
                    chosen = leaders.count == 1 ? leaders[0] : leaders[rng.index(leaders.count)]
                }
                run.shopRolls["rankShield"] = ShopRoll(rank: chosen,
                                                       suit: run.shopRolls["rankShield"]?.suit)
                if let def = pillarTypes.get("rankShield") {
                    recT("pillar", def.id, def.label, ["fires": 1])
                }
            }
        }
        // CRAZY EIGHTS (v6.76): if 8s are the full deck's most common rank
        // (ties → lowest rank), each pile in the pillar's column STARTS at
        // pile SIZE 8 — latched as a per-pile size bonus at Start Run (the
        // Same Heavy mechanism: it rides the pile object and the snapshot's
        // sizeBonus). The "8" is the mechanic itself — the data has no knob.
        if let pillars = run.pillars, mostCopiedRank() == 8 {
            for c in 0..<pillars.count {
                guard let def = resolvePillarDef(c), def.effect == "startPileSizeEight" else { continue }
                for i in colAlivePiles(c) {
                    let boost = max(0, 8 - board.pileSize(i))
                    if boost > 0 { board.addSizeBonus(i, boost) }
                }
                firePillar(c, def.effect ?? "startPileSizeEight", def.label, 0)
                logLine("\(def.label): 8s lead the deck — column \(c + 1) opens at pile size 8")
                recT("pillar", def.id, def.label, ["fires": 1])
            }
        }
        let bound = (run.pillars ?? []).enumerated().compactMap { c, pid -> String? in
            guard let pid else { return nil }
            return "col \(c + 1)=\(pillarTypes.get(pid)?.label ?? pid)"
        }
        let boundBases = (run.bases ?? []).enumerated().compactMap { c, bid -> String? in
            guard let bid else { return nil }
            return "col \(c + 1)=\(baseTypes.get(bid)?.label ?? bid)"
        }
        logAction("Start Climb", [
            bound.isEmpty ? "No Pillars bound" : "Pillars: " + bound.joined(separator: ", "),
            boundBases.isEmpty ? "No Bases bound" : "Bases: " + boundBases.joined(separator: ", "),
        ])
        // A deal NEVER starts pre-peeked: Scout fires only when its card LANDS
        // during play.
        run.revealNextActive = false
        emit(.runStarted)
    }

    // MARK: - Guess resolution

    /// Resolve a guess on a pile.
    public func guess(_ index: Int, _ g: Guess) {
        guard status == "playing", let run, run.started else { return }
        guard board.isActive(index), !deck.isEmpty else { return }
        // MAGNET: while any magnet card is a top, only magnet piles take a
        // guess (with several up, any of them satisfies the pull).
        let magnets = magnetPiles()
        if !magnets.isEmpty, !magnets.contains(index) { return }
        // MUTE: Same cannot be called on a muted pile. The draw must not be
        // consumed by a refused call, so both gates sit before it.
        if g == .same, pileMuted(index) { return }

        // v6.85: a new landing — last landing's fresh-curse ledger expires.
        run.freshCurses.removeAll()
        guard let current = board.top(index), let drawn = deck.draw() else { return }
        // Scout: drawing this card consumes any active reveal. It may be re-armed
        // below if a Scout card lands.
        run.revealNextActive = false
        // Tell: a flip consumes the deck's NEXT card — the very card every armed
        // Tell hint predicts. So ONE draw on ANY pile spends every active hint.
        run.tellPiles.removeAll()
        // Spade Whispers: this draw consumes one whispered hint. When the
        // window closes the whispering piles go dark with it.
        if run.tellDrawsLeft > 0 {
            run.tellDrawsLeft -= 1
            if run.tellDrawsLeft == 0 { run.whisperPiles.removeAll() }
        }
        // Kamikaze deck-reveal counts down one per draw.
        if run.kamikazeRevealLeft > 0 { run.kamikazeRevealLeft -= 1 }
        let pillar = pillarForPile(index)
        // Debug logbook: the trigger every item fire this guess cites (v6.55).
        fireContext = "\(cardName(drawn)) on \(cardName(current)) · pile \(index + 1) · \(g.rawValue)"

        // Strict comparisons: an equal rank only wins on a "same" guess.
        let isTie = drawn.value == current.value
        var correct: Bool
        switch g {
        case .higher: correct = drawn.value > current.value
        case .lower:  correct = drawn.value < current.value
        case .same:   correct = drawn.value == current.value
        }
        // Wild Aces: an Ace landing in this column counts as HIGH or LOW — pick
        // the value(s) for any Ace involved that make the guess correct.
        if let pillar, pillar.effect == "wildAces", drawn.value == 14 || current.value == 14 {
            let plainCorrect = correct
            let dAce = drawn.value == 14, cAce = current.value == 14
            switch g {
            case .higher: correct = (dAce ? 14 : drawn.value) > (cAce ? 1 : current.value)
            case .lower:  correct = (dAce ? 1 : drawn.value) < (cAce ? 14 : current.value)
            case .same:   correct = (dAce && cAce) ? true
                                  : (dAce ? (current.value == 14 || current.value == 1)
                                          : (drawn.value == 14 || drawn.value == 1))
            }
            // The FLIP is shown (v6.50): an Ace playing low without a cue
            // read as a rules glitch, the one silent save in the audit.
            if correct, !plainCorrect, let wc = run.pileColumns?[index] {
                emit(.wildAceFlipped(index: index, col: wc))
                recT("pillar", pillar.id, pillar.label, ["saves": 1])
            }
        }
        // Same-Safe (CONDITIONAL, v6.86 — the first of the held-back rank
        // conditionals to go live): a tie involving a Same-Safe card is safe
        // — and counts as a "same" guess, whatever the call — ONLY when
        // another alive pile's top shows this rank too (the v6.85 contract on
        // the rank axis). Exempt (no other alive pile) saves nothing, the
        // shared rule. The Column Tie-Safe PILLAR stays unconditional.
        let stickerTieSafe = (current.tieSafe || drawn.tieSafe)
            && !(conditionalRankMatches(index, drawn) ?? []).isEmpty
        let tieSafe = stickerTieSafe || (pillar?.effect == "columnTieSafe")
        if isTie && tieSafe { correct = true }
        // JOKER: never wrong — a correct guess for ANY call, whichever SIDE it's
        // on (a rankless ★ can't be compared, so a guess against it must be safe).
        if drawn.joker || current.joker { correct = true }
        // SAME-TOLERANCE + LANDING SHIELDS (v6.76 archetype batch, R1): the
        // column pillar can make an otherwise-WRONG call safe. A tolerated
        // SAME counts as a FULL correct Same — the shared correct branch below
        // banks the Same Charge, fires the equipped Same-Power and reports
        // `.resolved(correct: true)`, which is also where the flow's
        // correctSames bump reads from. ONE shared resolution for the whole
        // family (and the sameSuit tolerance additionally shields ANY call on
        // a same-suit landing).
        if !correct, let pillar, let pcol = run.pileColumns?[index],
           let saveEffect = landingSave(pillar: pillar, g: g, current: current, drawn: drawn, col: pcol) {
            correct = true
            firePillar(pcol, saveEffect, pillar.label, 0)
            recT("pillar", pillar.id, pillar.label, ["saves": 1])
        }
        // A Same-Safe STICKER turned a directional tie into a save — SAY SO
        // (v6.50: the only save with no cue; the pillar version always had
        // one). v6.86: only when the sticker's rank bet actually held.
        if isTie && correct && g != .same && stickerTieSafe {
            emit(.tieSafeSaved(index: index))
            recT("sticker", "tieSafe", "Tie-Safe", ["saves": 1])
        }

        run.totalGuesses += 1
        if correct { run.correctGuesses += 1 }

        let col = run.pileColumns?[index]

        // Static: a ♠ landing correctly in this column has a `chance` of peeking
        // the next upcoming card. Set AFTER the reveal reset above so it persists.
        if let pillar, pillar.effect == "static", correct, matchesSuit(drawn, "♠"),
           rollChance("pillar", pillar.id, pillar.label, pillar.num("chance", 0.5), index: index, col: col) {
            peekPillar(col, pillar)
        }

        // (Fibonacci retired in v6.78 — entry removed from items.js; restore
        // strips the id from old saves.)

        // Column Tie-Safe Pillar: feedback only — the save already happened.
        // v6.86: the pillar takes the credit whenever the STICKER's bet did
        // not (a worn-but-unfed Same-Safe saves nothing).
        if isTie, correct, g != .same, let pillar, pillar.effect == "columnTieSafe",
           !stickerTieSafe {
            firePillar(col, "columnTieSafe", pillar.label, 0)
            recT("pillar", pillar.id, pillar.label, ["saves": 1])
        }

        let bonusBefore = run.bonusCoins
        logBegin("Guess \(g.rawValue.uppercased()) on pile \(index + 1)"
                 + (col != nil ? " (column \(col! + 1))" : ""))
        logLine("drew \(cardName(drawn)) — \(correct ? (isTie ? "tie (safe)" : "correct") : "wrong")")

        // Streaks: a guess in ANY other column resets those columns' streaks;
        // this column grows on a correct guess and resets on a wrong one.
        if run.colStreak != nil, let col {
            for c in 0..<run.colStreak!.count where c != col { run.colStreak![c] = 0 }
            if correct {
                run.colStreak![col] += 1
                let s = run.colStreak![col]
                // Streak Size adds PILE SIZE, not coins — read live via the board
                // size hook, so nothing is paid here; just pulse on the 3rd step.
                if let pillar, pillar.effect == "streakSize", s == pillar.int("threshold", 3) {
                    firePillar(col, "streakSize", pillar.label, 0)
                }
                // Streak Bury: from the threshold-th correct in a row, bury a FLAT
                // digCount per correct guess — no escalation.
                if let pillar, pillar.effect == "streakTribute", s >= pillar.int("threshold", 3) {
                    let nb = buryTribute(index, pillar.int("digCount", 1), pillar.label)
                    firePillar(col, "streakTribute", pillar.label, 0)
                    if nb > 0 { recT("pillar", pillar.id, pillar.label, ["buried": Double(nb)]) }
                }
            } else {
                run.colStreak![col] = 0
            }
        }

        // Compound: every correct guess against a Compound card pays on the spot —
        // +0 the first correct use, +1 the next, … (compoundHits − 1). The running
        // total persists on the card's identity (written back on a win).
        if correct, current.stickers.contains(where: { $0.type == "compound" }) {
            current.compoundHits += 1
            run.compoundUpdates[current.id] = current.compoundHits
            let pay = Double(current.compoundHits - 1) * (stickerTypes.get("compound")?.num("step", 1) ?? 1)
            if pay > 0 { addBonus("Compound", pay) }
            recT("sticker", "compound", "Compound", ["coins": pay > 0 ? pay : 0])
        }

        // Suit Bounty: a matching-suit card LANDING on a surviving pile in this
        // column earns the column its bounty. Paid LIVE into the bonus tally.
        if correct, let pillar, pillar.effect == "suitBounty",
           let psuit = pillar.suit, matchesSuit(drawn, psuit),
           run.suitBountyHits != nil, let pcol = run.pileColumns?[index] {
            run.suitBountyHits![pcol] += 1
            addBonus(pillar.label, pillar.value)
            firePillar(pcol, "suitBounty", pillar.label, pillar.value)
            recT("pillar", pillar.id, pillar.label, ["coins": pillar.value])
        }

        // Snowball Bury: ANY wrong placement of the carrying card resets its X to
        // 0 (even when a Guard/Second Wind saves the pile).
        if !correct, drawn.stickers.contains(where: { $0.type == "snowball" }) {
            drawn.snowball = 0
            run.snowballUpdates[drawn.id] = 0
        }

        // Compound (v6.51): a WRONG guess against a pile whose TOP card carries
        // Compound resets that card's banked total to 0 — Snowball's semantics,
        // keyed off the pile-TOP card the guess was made AGAINST rather than
        // the drawn one. The reset rides the same write-back (`compoundUpdates`).
        if !correct, current.stickers.contains(where: { $0.type == "compound" }) {
            current.compoundHits = 0
            run.compoundUpdates[current.id] = 0
        }

        // MALFUNCTION: guessing correctly against the cursed top rolls the
        // card blowing the pile anyway. The guess stays correct in the
        // tallies; the death bypasses every save (nothing malfunctions
        // politely). Rolled BEFORE the landing branch so the branch order
        // stays legible. The roll reports its HIT/MISS (v6.57).
        let malfunctioned = correct && malfunctionTriggers(current: current, index: index, col: col)

        // JAMMER feedback: the landing pile's column has a pillar the curse
        // is holding down — say so once per guess (the gate itself lives in
        // resolvePillarDef, which returned nil for every read above).
        if columnJammed(col), let col, run.pillars?[safe: col] ?? nil != nil {
            emit(.pillarBlocked(col: col))
            let jdef = stickerTypes.all().first { $0.behavior == "jammer" }
            recT("sticker", jdef?.id ?? "jammer", jdef?.label ?? "Jammer", ["fires": 1])
        }

        if malfunctioned {
            board.push(index, drawn)
            curseTouch(index: index, current: current, drawn: drawn)
            board.kill(index)
            let t = stickerTypes.all().first { $0.behavior == "malfunction" }
            logLine("MALFUNCTION: \(cardName(current)) blew the pile on a correct guess")
            recT("sticker", "malfunction", t?.label ?? "Malfunction", ["kills": 1])
            emit(.malfunction(index: index, cardLabel: cardName(current)))
            emit(.pileKilled(index: index))
            emit(.resolved(index: index, guess: g, current: current, drawn: drawn, correct: false))
        } else if correct {
            board.push(index, drawn)
            curseTouch(index: index, current: current, drawn: drawn)
            // Scout: the placed card reveals the next deck card (display-only).
            if drawn.revealNext { run.revealNextActive = true; recT("sticker", "revealNext", "Scout", ["peeks": 1]) }
            // Tell (CONDITIONAL, v6.85): the carrier's suit is the bet.
            maybeConditionalTell(index, drawn)
            // Tribute Pillars: pull card(s) from the deck's BOTTOM and bury them
            // under this pile — never revealed.
            maybeTribute(index, pillar, drawn, isTie)
            maybeLandingBonus(index, drawn)
            maybeExpansionStickers(index, current, drawn, col)
            maybeLivePillarExtras(index, pillar, drawn, g, isTie, col)
            maybeBoardWideSizeEffects(index, drawn)
            maybeDuplicate(index, current, drawn, g)
            maybeStickerTribute(index, drawn)
            maybeStickerActions(index, drawn)
            // Trapdoor: the landed curse opens under the pile — its BOTTOM
            // card slips back into the deck (hidden), one per Trapdoor on the
            // drawn card. The pile always keeps its top. v6.85: a Trapdoor
            // that a conversion appended DURING this landing is dormant (the
            // freshCurses ledger) — it opens from the card's NEXT landing.
            let doors = drawn.stickers.filter { st in
                guard stickerTypes.get(st.type)?.behavior == "trapdoor" else { return false }
                return !run.freshCurses.contains { $0.cardId == drawn.id && $0.type == st.type }
            }
            if !doors.isEmpty {
                var dropped = 0
                for _ in doors {
                    guard let fell = board.removeBottom(index) else { break }
                    deck.returnCard(fell)
                    dropped += 1
                }
                if dropped > 0 {
                    let def = stickerTypes.get(doors[0].type)
                    logLine("Trapdoor: \(dropped) card\(dropped == 1 ? "" : "s") fell out of the pile's bottom, back into the deck (hidden)")
                    recT("sticker", doors[0].type, def?.label ?? "Trapdoor", ["cards": Double(dropped)])
                    emit(.trapdoorDropped(index: index, count: dropped))
                }
            }
            logLine("→ \(cardName(drawn)) landed on \(cardName(current)) · pile survived (\(board.piles[index].cards.count) cards)")
            emit(.resolved(index: index, guess: g, current: current, drawn: drawn, correct: true))
            surfaceActionOffer()
            // Revive: if a pile in this column just reached 10 and a dead pile
            // exists, offer to revive one.
            maybeReviveTrigger(col)
            // SAME: a correct Same does EXACTLY TWO things — bank a Same Charge
            // (max 1) and trigger the equipped Same-Power. A Joker on either side
            // makes any call safe but grants NOTHING extra on higher/lower; call
            // SAME with a Joker involved and it counts as a fully correct Same.
            if g == .same {
                sameCharge = true
                if run.samePowerNeedsConsent, let sp = run.samePower,
                   samePowerTypes.get(sp)?.effect == "linkShuffle" {
                    // Consent mode (iOS, v6.55): the board-wide shuffle is the
                    // player's call — park the fire until `answerPowerShuffle`.
                    // The Same Charge banks either way (the call was correct).
                    run.pendingPowerShuffle = index
                    logLine("\(samePowerTypes.get(sp)?.label ?? "Link Shuffler") (Same-Power): parked for the player's confirm")
                } else {
                    fireSamePower(index)
                }
                emit(.sameBanked(index: index, sameCharge: sameCharge))
            }
        } else if guardConditionalSave(index, drawn) {
            // GUARD (v6.85): carrier-only and CONDITIONAL — the wrong-landing
            // carrier is absorbed (returned to the deck, unlimited, unspent)
            // when another alive pile's top matches ITS suit. The old
            // bidirectional any-♠ save retired with the rework; the failed
            // bet converts below instead.
            deck.returnCard(drawn)
            logLine("Guard saved the pile (\(drawn.suit) matched another top; card returned to the deck)")
            emit(.guarded(index: index, guess: g, current: current, drawn: drawn))
            let gdef = stickerTypes.all().first { $0.behavior == "suitImmunity" }
            recT("sticker", gdef?.id ?? "suitImmunity", gdef?.label ?? "Guard", ["saves": 1])
        } else if let pillar, pillar.effect == "secondWind", let col,
                  { let saved = rollChance("pillar", pillar.id, pillar.label,
                                           pillar.num("saveChance", 0.25), index: index, col: col)
                    if !saved { secondWindMissCol = col }
                    return saved }() {
            // Second Wind: EVERY pile death in this column rolls `saveChance`
            // to revive (no once-per-run gate). On a save the pile's TOP CARD
            // STAYS in place (v6.93 — the Phoenix shape): only the buried
            // cards shuffle back into the deck, and the killing card — which
            // never landed — returns with them. No fresh top is dealt. The
            // used-flag stays recorded for the trace/debug surface only —
            // nothing gates on it.
            if run.secondWindNeedsConsent {
                // Consent mode (iOS, v6.55): the roll HIT, but the save is now
                // the player's call — park the exact state (the killing card is
                // held out of the deck) until `answerSecondWind`. The turn's
                // log entry closes below with the choice still open; the
                // fire/decline lines land on the answer's own entry.
                run.pendingSecondWind = PendingSecondWind(
                    index: index, col: col, guess: g,
                    killingCard: drawn, recycleCount: board.pileSize(index))
                logLine("Second Wind: the save roll hit — parked for the player (saving shuffles \(board.pileSize(index)) cards back into the deck)")
                // v6.56 SEQUENCING: the draw visibly PRECEDES the save prompt.
                // The killer came off the deck above; this offer event is the
                // UI's cue to show that drawn card and the dying moment FIRST,
                // then ask. No .resolved/.pileKilled yet — the pile's fate is
                // undecided until `answerSecondWind` (which emits them).
                emit(.secondWindOffer(index: index, col: col, guess: g,
                                      current: current, drawn: drawn,
                                      recycleCount: board.pileSize(index)))
            } else {
                applySecondWindSave(index: index, col: col, pillar: pillar, g: g,
                                    current: current, killingCard: drawn)
            }
        } else if sameCharge {
            // Second Wind rolled and MISSED before this rescue — say so.
            if let mc = secondWindMissCol { emit(.secondWindMiss(index: index, col: mc)); secondWindMissCol = nil }
            // SAME CHARGE — the LAST-priority backstop. Reached only after Guard,
            // Shield and Second Wind all declined to save, and spent only when it
            // actually saves. Works for BOTH death types. The would-be-killing
            // card LANDS normally and becomes the new pile card.
            sameCharge = false
            board.push(index, drawn)
            // No curseTouch here (v6.52): the guess was WRONG, and CURSES fire
            // only on correct landings (the fatal-landing audit's rule). But a
            // SAVED landing is still a LANDING (v6.57): the card became the
            // pile's new top, so its own beneficial landing stickers fire.
            fireSavedLandingStickers(index: index, current: current, drawn: drawn, col: col)
            logLine("Same Shield consumed — pile saved (\(cardName(drawn)) landed on \(cardName(current)) as the new pile card)")   // v6.96 rename
            emit(.sameSaved(index: index, guess: g, current: current, drawn: drawn, sameCharge: sameCharge))
            // A saved landing can queue the same optional offers a correct one
            // can (Shuffle / Donate) — surface them through the same path.
            surfaceActionOffer()
        } else {
            applyPileDeath(index: index, g: g, current: current, drawn: drawn, col: col)
        }

        let net = run.bonusCoins - bonusBefore
        logLine("Coins this turn: \(net >= 0 ? "+" : "")\(jsNum(net)) → bonus tally \(jsNum(run.bonusCoins))")
        currentEntry = nil
        fireContext = nil
        // A PARKED Second Wind defers end-of-deal evaluation to the answer:
        // the killing card is held out of the deck, so `deck.isEmpty` would
        // read one short and could call a premature win while the pile's fate
        // is still the player's to decide (answerSecondWind re-evaluates).
        if run.pendingSecondWind == nil { evaluateEnd() }
    }

    /// GUARD (v6.85): does the landing CARRIER hold a Guard whose bet is ON
    /// — another alive pile's top matching the carrier's suit? Exempt (no
    /// other alive pile) saves nothing: the sticker neither fires nor
    /// converts there, per the shared conditional rule.
    func guardConditionalSave(_ index: Int, _ drawn: LiveCard?) -> Bool {
        guard let drawn,
              drawn.stickers.contains(where: { stickerTypes.get($0.type)?.behavior == "suitImmunity" })
        else { return false }
        guard let m = conditionalSuitMatches(index, drawn) else { return false }
        return !m.isEmpty
    }

    /// Tell (CONDITIONAL, v6.85): a hit arms the one-draw hint on the
    /// carrier's pile; a missed bet converts, per instance. Shared by the
    /// correct-landing and saved-landing paths.
    func maybeConditionalTell(_ index: Int, _ drawn: LiveCard) {
        let tellCount = drawn.stickers.filter { $0.type == "tell" }.count
        guard tellCount > 0, let tdef = stickerTypes.get("tell") else { return }
        guard let m = conditionalSuitMatches(index, drawn) else { return }
        if m.isEmpty {
            for _ in 0..<tellCount { convertStickerToCurse(index, drawn, tdef) }
        } else {
            run.tellPiles.insert(index)
            recT("sticker", "tell", tdef.label, ["peeks": 1])
        }
    }

    /// Second Wind (v6.93 — the Phoenix shape): the pile's TOP CARD STAYS in
    /// place; only the cards beneath it shuffle back into the draw deck at
    /// random positions (no reveal, stickers/identity intact), and the
    /// killing card — which never landed — returns with them. The pile stays
    /// alive with the same top; no fresh card is dealt.
    func reviveSecondWind(_ index: Int, _ killingCard: LiveCard) {
        var removed = board.drain(index)             // [bottom … top]; empties, stays alive
        let top = removed.popLast()                  // the top card STAYS
        for c in removed { deck.returnCard(c) }      // the buried cards → deck (hidden)
        deck.returnCard(killingCard)                 // the killer never landed — back it goes
        if let top { board.push(index, top) }
        logLine("Second Wind: pile saved, top card stays; \(removed.count + 1) cards shuffled back into the deck (hidden)")
    }

    /// The Second Wind save itself — shared by the auto path (default, web
    /// parity) and a consented accept.
    func applySecondWindSave(index: Int, col: Int, pillar: ItemDef, g: Guess,
                             current: LiveCard, killingCard: LiveCard) {
        if run.secondWindUsed != nil { run.secondWindUsed![col] = true }
        reviveSecondWind(index, killingCard)
        firePillar(col, "secondWind", pillar.label, 0)
        emit(.secondWind(index: index, guess: g, current: current))
        recT("pillar", pillar.id, pillar.label, ["saves": 1, "revived": 1])
    }

    /// The fatal landing — shared by the inline death branch and a DECLINED
    /// Second Wind choice (the death the parked save interrupted, run late).
    func applyPileDeath(index: Int, g: Guess, current: LiveCard, drawn: LiveCard, col: Int?) {
        // Second Wind rolled and MISSED on the way to this death — say so.
        if let mc = secondWindMissCol { emit(.secondWindMiss(index: index, col: mc)); secondWindMissCol = nil }
        // Show the card that killed the pile as its (final) top, then kill it.
        // No curseTouch (v6.52): a FATAL landing is not a correct landing —
        // Spoiler and friends must not fire while the pile dies (the
        // fatal-landing audit; Death Bounty below is the one deliberate
        // on-death payout).
        board.push(index, drawn)
        // v6.85: a Guard that failed exactly when it was needed converts
        // even on the fatal landing — the card is buried wearing its new
        // curse (a revive surfaces it). Exempt landings (no other alive
        // pile) convert nothing, the shared rule.
        let fatalGuards = drawn.stickers.compactMap { st -> ItemDef? in
            guard let t = stickerTypes.get(st.type), t.behavior == "suitImmunity" else { return nil }
            return t
        }
        if !fatalGuards.isEmpty, let gm = conditionalSuitMatches(index, drawn), gm.isEmpty {
            for t in fatalGuards { convertStickerToCurse(index, drawn, t) }
        }
        // v6.86: Same-Safe converts the same way — an unfed tie that KILLED
        // the pile is exactly the bet the sticker missed.
        let fatalTieSafes = drawn.stickers.compactMap { st -> ItemDef? in
            guard let t = stickerTypes.get(st.type), t.behavior == "tieSafe" else { return nil }
            return t
        }
        if !fatalTieSafes.isEmpty, let rm = conditionalRankMatches(index, drawn), rm.isEmpty {
            for t in fatalTieSafes { convertStickerToCurse(index, drawn, t) }
            drawn.tieSafe = drawn.stickers.contains {
                stickerTypes.get($0.type)?.behavior == "tieSafe"
            }
        }
        board.kill(index)
        emit(.pileKilled(index: index))
        logLine("→ \(cardName(drawn)) landed on \(cardName(current)) · pile died")
        // FINAL CUT (v6.88): the column's LAST pile just fell — the killer
        // is purged from the campaign deck, durably (the flow commits it on
        // the event; the engine only reports). Jokers/Blanks can't be cut.
        if let pdef = resolvePillarDef(col), pdef.effect == "finalPilePurge",
           colAlivePiles(col).isEmpty, !drawn.joker, !drawn.blank {
            firePillar(col, "finalPilePurge", pdef.label, 0)
            recT("pillar", pdef.id, pdef.label, ["purged": 1])
            logLine("\(pdef.label): \(cardName(drawn)) killed the column's last pile — purged from the deck")
            emit(.finalCutPurged(col: col ?? 0, cardId: drawn.id))
        }
        // Last Rites: a pile in this column just died — peek the next card.
        if let pillar = resolvePillarDef(col), pillar.effect == "lastRites" { peekPillar(col, pillar) }
        // Death Bounty: the DRAWN (killing) card pays a consolation.
        let db = drawn.stickers.filter { $0.type == "deathBounty" }.count
        if db > 0 {
            let t = stickerTypes.get("deathBounty")
            let amt = Double(db) * (t?.value ?? 0)
            addBonus("Last Coin", amt)
            recT("sticker", "deathBounty", t?.label ?? "Last Coin", ["coins": amt])
        }
        emit(.resolved(index: index, guess: g, current: current, drawn: drawn, correct: false))
    }

    /// FIRST-RUN TUTORIAL: rearrange the freshly-dealt opening so pile 0's
    /// top is a 3 and the next draw is an Ace — the scripted "tap the 3,
    /// guess higher, an Ace lands" first exchange. Pure swaps of cards the
    /// deal already contains: counts, composition and the histogram all stay
    /// exactly true. Call between startRun and the first render.
    public func arrangeTutorialOpening() {
        // A 3 onto pile 0's top…
        if board.top(0)?.value != 3 {
            if let other = (1..<board.piles.count).first(where: { board.top($0)?.value == 3 }) {
                board.swapTops(0, other)
            } else if let three = deck.takeFirst(where: { $0.value == 3 }),
                      let old = board.piles[0].cards.popLast() {
                board.piles[0].cards.append(three)
                deck.returnCard(old)
            }
        }
        // …and an Ace as the next draw.
        if let ace = deck.takeFirst(where: { $0.value == 14 }) {
            deck.putNext(ace)
        } else if let other = (1..<board.piles.count).first(where: { board.top($0)?.value == 14 }),
                  let swap = deck.takeFirst(where: { $0.value != 3 }),
                  let ace = board.piles[other].cards.popLast() {
            // Every Ace was dealt as a pile top: trade one for a deck card.
            board.piles[other].cards.append(swap)
            deck.putNext(ace)
        }
        logLine("Tutorial opening arranged: a 3 waits on pile 1; an Ace rides the deck")
    }

    func evaluateEnd() {
        guard status == "playing" else { return }
        // Cards drawn during active play (excludes the initial deal).
        run.cardsDrawn = deck.drawn() - run.dealDraws
        // Death is checked BEFORE the end-of-deck clear: if the final deck card
        // kills the last alive pile, all-piles-dead is a LOSS — never a clear.
        if !board.anyAlive() {
            status = "lost"
            run.phase = "ended"
            run.result = "loss"
            logAction("CLIMB LOST — all piles in play are dead (no payout)")
            emit(.lost)
        } else if deck.isEmpty {
            status = "won"
            run.phase = "ended"
            run.result = "win"
            // Collector and Compound pay LIVE during play; the only end-of-run
            // scoring left is the column Pillars (and Payout).
            logBegin("CLIMB WON — end-of-climb bonuses")
            let pp = computePillarPayout()
            for ln in pp.lines {
                logLine("\(ln.label): +\(jsNum(ln.amount))" + (ln.detail.isEmpty ? "" : " (\(ln.detail))"))
            }
            let extra = board.extraCoinUnits()
            if extra > 0 { logLine("Payout: +\(extra)") }
            logLine("Bonus total: live \(jsNum(run.bonusCoins)) + Pillars \(jsNum(pp.bonus)) + Payout \(extra) = \(jsNum(run.bonusCoins + pp.bonus + Double(extra)))")
            currentEntry = nil
            emit(.won(pillarPayout: pp))
        }
    }

    // MARK: - Pending offers

    /// Surface the head pending-action offer, but only once any paid-bury
    /// prompts have drained (so dialogs never stack).
    func surfaceActionOffer() {
        guard run.pendingTributes.isEmpty, let a = run.pendingActions.first else { return }
        emit(.actionOffer(a))
    }

    /// Resolve the head pending-action (Shuffle / Donate).
    public func answerAction(_ accept: Bool) {
        guard let run, !run.pendingActions.isEmpty else { return }
        let a = run.pendingActions.removeFirst()
        fireContext = "\(a.kind) offer · pile \(a.index + 1) · \(accept ? "accepted" : "declined")"
        logBegin((a.kind == "shuffle" ? "Shuffle" : a.kind == "pillarShuffle" ? "Shuffler" : a.kind == "suitRipple" ? "Ripple" : "Donate") + (accept ? " — accepted" : " — declined"))
        if accept {
            if a.kind == "pillarShuffle" {
                // SHUFFLER (v6.91): the accepted offer — every OTHER alive
                // pile in the pillar's column, the old auto-fire's exact set.
                var n = 0
                if let col = a.target {
                    for i in colAlivePiles(col) where i != a.index { board.shufflePile(i, rng); n += 1 }
                    if n > 0 {
                        let pdef = resolvePillarDef(col)
                        firePillar(col, "shuffler", pdef?.label ?? "Shuffler", 0)
                        recT("pillar", pdef?.id ?? "royalCourt", pdef?.label ?? "Shuffler",
                             ["shuffled": Double(n)])
                    }
                }
                logLine("\(n) pile\(n == 1 ? "" : "s") shuffled (order hidden)")
            } else if a.kind == "suitRipple" {
                // Ripple (v6.85): shuffle every alive pile whose top matches
                // the carrier's suit — the carrier is still this pile's top
                // (prompts drain before any further landing), own pile
                // included.
                var shuffled = 0
                if let suit = board.top(a.index)?.suit {
                    for i in 0..<board.size where board.isActive(i) && matchesSuit(board.top(i), suit) {
                        board.shufflePile(i, rng)
                        shuffled += 1
                    }
                }
                let rdef = stickerTypes.get("diamondSnob")
                recT("sticker", "diamondSnob", rdef?.label ?? "Ripple", ["shuffled": Double(shuffled)])
                logLine("\(shuffled) pile\(shuffled == 1 ? "" : "s") shuffled (order hidden)")
            } else if a.kind == "shuffle" {
                board.shufflePile(a.index, rng)
                logLine("pile \(a.index + 1) shuffled (order hidden)")
                let sdef = stickerTypes.get("shuffle")
                recT("sticker", "shuffle", sdef?.label ?? "Shuffle", ["shuffled": 1])
            } else if a.kind == "donate", let target = a.target,
                      board.isActive(a.index), board.isActive(target) {
                let dn = stickerTypes.get("donate")?.int("count", 1) ?? 1
                var moved = 0
                for _ in 0..<dn where board.moveBottomCard(a.index, target) { moved += 1 }
                if moved > 0 {
                    logLine("moved \(moved) card\(moved == 1 ? "" : "s") from pile \(a.index + 1) to pile \(target + 1) (hidden)")
                }
            }
        }
        currentEntry = nil
        fireContext = nil
        emit(.actionResolved(kind: a.kind, index: a.index, target: a.target, accepted: accept))
        surfaceActionOffer()
    }

    /// Resolve the head of the paid-bury queue. On accept we bury (from the deck
    /// bottom, hidden) and charge the cost into the live bonus tally; on decline
    /// nothing moves.
    public func answerTribute(_ accept: Bool) {
        guard let run, !run.pendingTributes.isEmpty else { return }
        let offer = run.pendingTributes.removeFirst()
        fireContext = "\(offer.label) bury offer · pile \(offer.index + 1) · \(accept ? "accepted" : "declined")"
        logBegin((offer.label.isEmpty ? "Bury" : offer.label) + (accept ? " — accepted" : " — declined"))
        if accept {
            let buried = buryTribute(offer.index, offer.count, offer.label)
            if buried > 0 {
                addBonus("Bury cost", -offer.cost)
                recT("sticker", offer.type, offer.label, ["buried": Double(buried), "coinsLost": offer.cost])
            }
        } else {
            logLine("Bury declined — no cards buried, no charge")
        }
        currentEntry = nil
        fireContext = nil
        emit(.tributeResolved(index: offer.index, accepted: accept))
        // Chain the next queued offer (e.g. a card carrying two paid stickers).
        if let next = run.pendingTributes.first {
            emit(.tributeOffer(next))
        } else {
            surfaceActionOffer()
        }
    }

    /// Resolve a consent-mode Second Wind (v6.55): the roll had ALREADY hit
    /// when the choice was parked — `save` applies it (v6.93: the pile's top
    /// card STAYS; its buried cards and the held killing card shuffle back
    /// into the deck — no fresh top is dealt), `!save` lets the pile die the
    /// death the roll interrupted. The pile is untouched while parked, so
    /// its top is still the guess's `current`. A no-op with nothing pending.
    public func answerSecondWind(_ save: Bool) {
        guard let run, let pending = run.pendingSecondWind else { return }
        run.pendingSecondWind = nil
        fireContext = "Second Wind save roll · pile \(pending.index + 1) · \(save ? "saved" : "declined")"
        logBegin("Second Wind — " + (save ? "saved" : "declined"))
        if save, let pillar = resolvePillarDef(pending.col), pillar.effect == "secondWind",
           board.isActive(pending.index), let current = board.top(pending.index) {
            applySecondWindSave(index: pending.index, col: pending.col, pillar: pillar,
                                g: pending.guess, current: current, killingCard: pending.killingCard)
        } else if !save, board.isActive(pending.index), let current = board.top(pending.index) {
            logLine("the player let the pile die (\(pending.recycleCount + 1) cards stay out of the deck)")
            applyPileDeath(index: pending.index, g: pending.guess, current: current,
                           drawn: pending.killingCard, col: pending.col)
        }
        // (If the board somehow moved on while parked, the choice just lapses —
        // the held card stays out of play rather than resurrecting a dead pile.)
        currentEntry = nil
        fireContext = nil
        // The save returns the held killer to the deck (the win check) and a
        // declined save kills the pile (the loss check) — end-of-deal
        // evaluation belongs here now.
        evaluateEnd()
    }

    /// Resolve a consent-mode Link Shuffler (v6.55): confirm fires the equipped
    /// power on the parked hub (its own recT/log lines nest under this entry);
    /// decline skips the shuffle — the Same Charge the call banked stays banked.
    /// A no-op with nothing pending.
    public func answerPowerShuffle(_ accept: Bool) {
        guard let run, let hub = run.pendingPowerShuffle else { return }
        run.pendingPowerShuffle = nil
        let label = run.samePower.flatMap { samePowerTypes.get($0)?.label } ?? "Link Shuffler"
        fireContext = "\(label) confirm · pile \(hub + 1) · \(accept ? "confirmed" : "declined")"
        logBegin("\(label) — " + (accept ? "confirmed" : "declined"))
        if !accept { logLine("the piles keep their order") }
        if accept { fireSamePower(hub) }
        currentEntry = nil
        fireContext = nil
    }

    // MARK: - Public reads (the renderer's window into the run)

    /// True while the pre-run sticker window is open.
    public func canApplyStickers() -> Bool { status == "playing" && run?.stickerWindow == true }
    /// True once Start Run has been pressed (active play has begun).
    public func isRunStarted() -> Bool { run?.started == true }
    /// The seed that produced the current deal — persist it to replay the exact
    /// same starting board on resume (no free redeal via refresh).
    public func getSeed() -> UInt32? { run?.seed }
    /// The equipped Same-Power id for this deal (or nil).
    public func equippedSamePower() -> String? { run?.samePower ?? samePowerId }
    /// Last Resort's seal reads this (the config is internal).
    public var isBossDeal: Bool { runConfig.isBoss }

    /// Scout look-ahead: the next card to be drawn while a reveal is active, or
    /// nil. Read-only peek of the REAL next card — never changes draw order.
    public func revealedNextCard() -> LiveCard? {
        guard let run, run.revealNextActive || run.kamikazeRevealLeft > 0, let deck else { return nil }
        return deck.peek(1).first
    }

    /// Push the synapse-link adjacency the UI computed (pile → linked piles).
    public func setLinks(_ map: [Int: [Int]]) { run?.links = map }
    public func getLinks() -> [Int: [Int]] { run?.links ?? [:] }

    /// Tell: the directional hint for an armed pile, or nil. Returns the REAL
    /// next card's rank direction vs this pile's top card. DISPLAY ONLY — a pure
    /// read that never changes draw order/RNG.
    public func pileHint(_ index: Int) -> Guess? {
        guard let run, let board, index >= 0, index < board.size else { return nil }
        // A hint belongs to an ARMED pile, always. Spade Whispers arms its own
        // pile and `tellDrawsLeft` only decides how many draws that pile keeps
        // hinting for — it never lights the rest of the board.
        guard run.tellPiles.contains(index)
                || (run.tellDrawsLeft > 0 && run.whisperPiles.contains(index)) else { return nil }
        guard let deck, !deck.isEmpty, board.isActive(index) else { return nil }
        guard let top = board.top(index), let next = deck.peek(1).first else { return nil }
        // A Joker pile can never be called wrong — its hint is always SAME
        // (router batch), not a meaningless arrow.
        if top.joker || next.joker { return .same }
        return next.value > top.value ? .higher : (next.value < top.value ? .lower : .same)
    }

    /// ODDS ASSIST (v6.72, all-best v6.78): EVERY (pile, call) pair whose
    /// survival probability against the REMAINING deck ties the maximum —
    /// exactly the information the histogram already offers, folded per
    /// pile, with no tie-break ladder: at equal odds every best call glows.
    /// DISPLAY ONLY: a pure read off `remainingCounts()` (order-free),
    /// never touching the rng, the deck order, or any state — identical
    /// seeds play identical runs with the assist on or off. Rules mirrored
    /// from `guess(_:_:)`'s comparison: a ★ TOP makes every call safe
    /// (all three calls at p = 1), and a DRAWN ★ is never wrong, so jokers
    /// left in the deck (value 0) count as a success for every call.
    /// Deliberately histogram-blind to pillar/sticker PROBABILITY modifiers
    /// (Tie-Safe, Wild Aces, the tolerance family) — the assist shows what
    /// counting shows, not what the build engineers. LEGALITY is respected,
    /// though (v6.78): `guess()` refuses a SAME on a muted pile and any
    /// call off the magnet piles while a Magnet is up, so those calls are
    /// never candidates — a glow the player cannot play is a wrong glow.
    ///
    /// Pairs return in ascending (pile, higher→lower→same) enumeration
    /// order — deterministic, never rng. Empty when nothing is drawable.
    public func assistRecommendations() -> [(pile: Int, call: Guess)] {
        guard let run, run.started, status == "playing", let deck, let board,
              !deck.isEmpty else { return [] }
        let counts = deck.remainingCounts()
        let total = counts.values.reduce(0, +)
        guard total > 0 else { return [] }
        let jokers = counts[0] ?? 0
        // MAGNET: while any magnet top is up, only magnet piles take a guess.
        let magnets = magnetPiles()
        var cands: [(pile: Int, call: Guess, p: Double)] = []
        var bestP = 0.0
        for i in 0..<board.size where board.isActive(i) {
            guard let top = board.top(i) else { continue }
            if !magnets.isEmpty, !magnets.contains(i) { continue }
            let muted = pileMuted(i)
            // This pile's (call, probability) candidates. A ★ top is a
            // certainty on ANY call.
            var higher = 0.0, lower = 0.0, same = 0.0
            if top.joker {
                higher = 1; lower = 1; same = 1
            } else {
                var h = 0, l = 0, s = 0
                for (v, n) in counts where v != 0 {
                    if v > top.value { h += n }
                    else if v < top.value { l += n }
                    else { s += n }
                }
                higher = Double(h + jokers) / Double(total)
                lower = Double(l + jokers) / Double(total)
                same = Double(s + jokers) / Double(total)
            }
            cands.append((i, .higher, higher))
            cands.append((i, .lower, lower))
            // MUTE: Same cannot be called on a muted pile — not a candidate.
            if !muted { cands.append((i, .same, same)) }
        }
        for c in cands where c.p > bestP { bestP = c.p }
        return cands.filter { abs($0.p - bestP) <= 1e-9 }
                    .map { (pile: $0.pile, call: $0.call) }
    }

    /// Debug logbook: append a standalone entry for a non-engine action.
    public func log(action title: String, lines: [String] = []) { logAction(title, lines) }
    /// Itemized scoring-Pillar payout for the current board.
    public func pillarPayout() -> PillarPayout { computePillarPayout() }

    // MARK: - Debug namespace

    /// Kept separate from the real rules. The engine still owns all state
    /// transitions; debug just nudges the same deck/board + re-evaluates.
    public struct Debug {
        unowned let e: GameEngine
        /// Force the next drawn card to be a given rank value (2..14).
        @discardableResult
        public func setNextCard(_ value: Int) -> LiveCard? {
            (e.deck != nil && e.status == "playing") ? e.deck.setNext(value: value) : nil
        }
        /// Force the next draw to be a raw card object (QA — e.g. a Joker).
        @discardableResult
        public func setNextCardObj(_ card: LiveCard) -> LiveCard? {
            (e.deck != nil && e.status == "playing") ? e.deck.setNextCard(card) : nil
        }
        public func setSamePower(_ id: String?) { e.run?.samePower = id }
        @discardableResult
        public func trimDeck(to n: Int) -> Int { e.deck?.trim(to: n) ?? 0 }
        @discardableResult
        public func drainDeck() -> Int { e.deck?.drain() ?? 0 }
        public func evaluate() { e.evaluateEnd() }
        /// Jump straight to a loss: kill every pile, then re-evaluate (the web's
        /// `debug.loseNow`, index.html:14406-14411). The same board/evaluate
        /// path a real death runs — no special-cased state writes.
        public func loseNow() {
            guard let board = e.board, e.status == "playing" else { return }
            for i in 0..<board.size { board.kill(i) }
            e.evaluateEnd()
        }
    }
    public var debug: Debug { Debug(e: self) }
}

/// ODDS ASSIST deal-out gate (v6.72): the assist glow must stay OFF while a
/// deal-out cascade is still flying cards in — the board isn't live yet —
/// and light up on the first refresh AFTER the cascade lands. The animation
/// is UI-side (the engine can't see it), so the CONTROLLER owns the flag;
/// this pure little state machine holds the decision where the unit bundle
/// can reach it (tests see only GameCore). A fresh gate opens HELD — every
/// deal opens with its cascade pending — and a reshuffle's re-deal re-arms
/// it via `dealOutStarted()`; a mid-deal restore (no cascade) releases it
/// straight away via `dealOutFinished()`.
public struct OddsAssistGate {
    /// True while a deal-out cascade is pending or in flight.
    public private(set) var dealing = true
    public init() {}
    /// A deal-out (first deal or reshuffle re-deal) is queued/animating.
    public mutating func dealOutStarted() { dealing = true }
    /// The cascade's last card landed (or a mid-deal restore skipped it).
    public mutating func dealOutFinished() { dealing = false }
    /// THE decision: show the assist only when it's enabled AND the board
    /// is live (no cascade in flight).
    public func allows(_ enabled: Bool) -> Bool { enabled && !dealing }
}
