import XCTest
@testable import GameCore

/// v6.55 — the debug EVENT LOG's item-fire feed (recT → logbook) and the
/// regression pins for four field reports:
///   1. every pillar/sticker/base/Same-Power/curse fire lands in the logbook
///      with its name, its effect, and WHAT triggered it;
///   2. Deep Pockets' logged fire, the live tally, and every display input
///      agree (the "log +2, reward line +7" report);
///   3. a Tell arms a direction hint and NEVER a peek;
///   4. a tell/hint belongs to its PILE — across shuffles and pile deaths;
///   5. the purge's curses roll PER CARD (the "three cards, same curse"
///      report) — statistically, from the data's weights.
final class ItemFireLogTests: XCTestCase {
    private let data = GameData.shared
    private var economy: Economy { Economy(data: data) }

    private func engine(cols: [Int] = [3, 3, 3], pillars: [String?]? = nil,
                        bases: [String?]? = nil, samePower: String? = nil,
                        seed: UInt32 = 8080) -> GameEngine {
        let e = GameEngine(deckSpecs: DeckManager.buildStandardDeck(),
                           pileCount: cols.reduce(0, +),
                           runConfig: RunConfig(cols: cols, samePower: samePower))
        e.start(seedOverride: seed)
        e.startRun(pillars: pillars ?? Array(repeating: nil, count: cols.count),
                   bases: bases ?? Array(repeating: nil, count: cols.count),
                   samePower: .some(samePower))
        return e
    }

    /// Force a card carrying `sticker` to land correctly on pile 0 (over a 4).
    @discardableResult
    private func landCarrier(_ e: GameEngine, sticker: String, suit: String = "♠",
                             rank: Int = 9) -> LiveCard {
        let live = DeckManager.toCard(
            CardSpec(id: 4242, suit: suit, originalRank: rank, currentRank: rank,
                     stickers: [StickerRecord(type: sticker)]), data: data)
        e.board.piles[0].cards = [DeckManager.cardForValue(4)]
        e.debug.setNextCardObj(live)
        e.guess(0, .higher)   // rank ≥ 9 over a 4 — correct
        return live
    }

    private func logLines(_ e: GameEngine) -> [String] {
        e.run.log.flatMap { [$0.title] + $0.lines }
    }

    // MARK: - 1. The fire feed (Task 1)

    /// A sticker fire lands in the logbook with name, effect and trigger.
    func testStickerFireLogsNameEffectAndTrigger() {
        let e = engine()
        let per = data.stickerTypes.get("deepPockets")?.num("per", 10) ?? 10
        landCarrier(e, sticker: "deepPockets")
        let paid = Int(Double(e.deck.remaining()) / per)   // one instance
        let lines = logLines(e)
        XCTAssertTrue(lines.contains {
            $0.contains("⚡ Deep Pockets [sticker]") && $0.contains("+\(paid) coins")
                && $0.contains("↩") && $0.contains("pile 1") && $0.contains("higher")
        }, "the fire line must name the item, its effect and the trigger — got:\n\(lines.joined(separator: "\n"))")
    }

    /// A Base activation logs through the same feed (baseActivate's recT).
    func testBaseFireLogsThroughTheSameFeed() {
        guard let shuffle = data.baseTypes.all().first(where: { $0.effect == "shuffleColumn" })
        else { return XCTFail("no shuffle-column base in the data") }
        let e = engine(bases: [shuffle.id, nil, nil])
        XCTAssertNotNil(e.baseActivate(col: 0))
        XCTAssertTrue(logLines(e).contains {
            $0.contains("⚡ \(shuffle.label) [base]") && $0.contains("↩ \(shuffle.label) activated · column 1")
        }, "the base fire must log with its activation context")
    }

    /// A Same-Power fire (previously un-instrumented branches) logs too.
    func testSamePowerFireLogsThroughTheSameFeed() {
        guard let power = data.samePowerTypes.all().first(where: { $0.effect == "linkShuffle" })
        else { return XCTFail("no linkShuffle same-power in the data") }
        let e = engine(samePower: power.id)
        e.board.piles[0].cards = [DeckManager.cardForValue(7)]
        e.debug.setNextCard(7)
        e.guess(0, .same)   // a correct Same fires the equipped power
        XCTAssertTrue(logLines(e).contains {
            $0.contains("⚡ \(power.label) [samePower]") && $0.contains("shuffled")
        }, "the same-power fire must log — got:\n\(logLines(e).joined(separator: "\n"))")
    }

    /// A landing curse logs through the same feed.
    func testCurseFireLogsThroughTheSameFeed() {
        let e = engine()
        e.sameCharge = true
        landCarrier(e, sticker: "drainShield")
        XCTAssertFalse(e.sameCharge, "Shield Drain empties the banked charge")
        XCTAssertTrue(logLines(e).contains { $0.contains("⚡ Shield Drain [sticker]") },
                      "the curse fire must log — got:\n\(logLines(e).joined(separator: "\n"))")
    }

    /// …and the DebugEventLog's drain carries the fire lines out of the engine.
    func testEventLogDrainCarriesTheFireLines() {
        DebugEventLog.shared.clear()
        defer { DebugEventLog.shared.clear() }
        let e = engine()
        landCarrier(e, sticker: "deepPockets")
        DebugEventLog.shared.drainEngine(e.run)
        XCTAssertTrue(DebugEventLog.shared.lines.contains { $0.contains("⚡ Deep Pockets [sticker]") },
                      "the drained event log must carry the fire line")
    }

    // MARK: - 2. Deep Pockets: tally vs every displayed number (Task 2)

    /// The report: log showed "+2 coins — Deep Pockets / bonus tally 2" while
    /// the deal's reward line read +7. Pin the whole chain the display reads
    /// from: the live tally, its itemization, the reward line's bonus term
    /// (Economy.liveBonus over the exact inputs DealController feeds it), and
    /// the deal-end breakdown. With Deep Pockets the only item in play, ALL of
    /// them must equal the logged fire.
    func testDeepPocketsTallyMatchesEveryDisplayInput() {
        let e = engine()
        let per = data.stickerTypes.get("deepPockets")?.num("per", 10) ?? 10
        landCarrier(e, sticker: "deepPockets")
        let paid = Double(Int(Double(e.deck.remaining()) / per))   // 1 instance × per
        XCTAssertGreaterThan(paid, 0, "the scenario must actually pay")
        // The actual tally + its itemization (what the deal-cleared summary lists).
        XCTAssertEqual(e.run.bonusCoins, paid)
        XCTAssertEqual(e.run.bonusEvents["Deep Pockets"], paid)
        // The in-deal reward line's bonus term — the exact inputs
        // DealController.liveBonus() assembles.
        var live = PayoutStats()
        live.liveBonusCoins = e.run.bonusCoins
        live.pillarBonus = e.pillarPayout().bonus
        live.extraCoinUnits = e.board.extraCoinUnits()
        XCTAssertEqual(economy.liveBonus(live), paid,
                       "with no scoring pillar and no Extra Coin, the reward line's bonus IS the tally")
        // The deal-end fold (what GameFlowController hands Economy.breakdown).
        var s = PayoutStats()
        s.won = true
        s.flat = economy.dealFlat(stage: 1, rating: 2, isBoss: false)
        s.stage = 1
        s.rating = 2
        s.aliveCount = e.board.aliveCount()
        s.minAliveCards = e.board.minAliveCards()
        s.extraCoinUnits = e.board.extraCoinUnits()
        let pp = e.pillarPayout()
        s.pillarBonus = pp.bonus
        s.pillarLines = pp.lines
        s.eventBonus = e.run.bonusCoins
        s.eventLines = e.run.bonusEvents.pairs.map { PayoutLine(label: $0.label, detail: "", amount: $0.amount) }
        let b = economy.breakdown(s)
        XCTAssertEqual(b.eventBonus, paid)
        XCTAssertEqual(b.eventLines.first { $0.label == "Deep Pockets" }?.amount, paid)
        XCTAssertEqual(b.total, s.flat + paid, "no other source in play — the total is flat + the one fire")
    }

    /// …and the one place the display legitimately EXCEEDS the live tally: a
    /// scoring Pillar's end-of-deal payout projects into the reward line's
    /// bonus term all deal long (the web's documented liveBonus contract —
    /// index.html Economy.liveBonus: "the coins items have put on top of the
    /// flat reward if the deal cleared right now"). That projection, not a
    /// tally desync, is how a "+2" fire can sit beside a "+7" reward line.
    func testRewardLineBonusTermIncludesThePillarProjectionByDesign() {
        guard let guardian = data.pillarTypes.all().first(where: { $0.effect == "columnAllAlive" })
        else { return XCTFail("no all-alive scoring pillar in the data") }
        let e = engine(pillars: [guardian.id, nil, nil])
        landCarrier(e, sticker: "deepPockets")
        let tally = e.run.bonusCoins
        var live = PayoutStats()
        live.liveBonusCoins = e.run.bonusCoins
        live.pillarBonus = e.pillarPayout().bonus
        live.extraCoinUnits = e.board.extraCoinUnits()
        XCTAssertEqual(e.pillarPayout().bonus, guardian.value,
                       "the whole column is alive — the pillar projects its full value")
        XCTAssertEqual(economy.liveBonus(live), tally + guardian.value,
                       "the reward line's bonus term = tally + the pillar's projected payout")
    }

    // MARK: - 3. Tell arms a hint, never a peek (Task 3)

    /// The report: a Jack carrying Tell fired its lower-tell AND the player
    /// could peek the next card. Tell's whole effect is the DIRECTION marker;
    /// every peek surface (deck reveal, peek window, revealedNextCard) must
    /// stay shut.
    func testTellArmsADirectionalHintButNeverAPeek() {
        let e = engine()
        let jack = landCarrier(e, sticker: "tell", suit: "♠", rank: 11)
        XCTAssertEqual(jack.value, 11)
        XCTAssertTrue(e.run.tellPiles.contains(0), "the tell armed on its pile")
        e.debug.setNextCard(3)   // a 3 under a J — the hint must read LOWER
        XCTAssertEqual(e.pileHint(0), .lower)
        // No peek rides along: not the deck reveal, not the peek window.
        XCTAssertFalse(e.run.revealNextActive, "Tell must not arm the deck reveal")
        XCTAssertEqual(e.run.kamikazeRevealLeft, 0, "Tell must not open a peek window")
        XCTAssertNil(e.revealedNextCard(), "Tell reveals a DIRECTION, never the card")
        // The hint is spent by the next draw anywhere — still no peek after.
        e.board.piles[1].cards = [DeckManager.cardForValue(2)]
        e.guess(1, .higher)
        XCTAssertNil(e.pileHint(0))
        XCTAssertFalse(e.run.revealNextActive)
        XCTAssertNil(e.revealedNextCard())
    }

    // MARK: - 4. A hint belongs to its pile (Task 4, engine half)

    /// The marker's identity is the PILE INDEX: a pile shuffle (which reorders
    /// the pile's own cards) keeps the hint on the pile and truthful against
    /// the NEW top, and a kill retires it. (The on-card chip's position is
    /// rendering-side; this pins the data the chip reads.)
    func testTellHintStaysWithItsPileThroughShufflesAndDeaths() {
        let e = engine()
        landCarrier(e, sticker: "tell", suit: "♠", rank: 11)
        e.debug.setNextCard(3)
        XCTAssertEqual(e.pileHint(0), .lower)
        XCTAssertNil(e.pileHint(1), "unarmed piles never hint")

        // A shuffle of the pile's own cards: the marker must not wander to a
        // neighbour, and it must now read against the NEW top.
        e.board.shufflePile(0, e.rng)
        for i in 1..<e.board.size {
            XCTAssertNil(e.pileHint(i), "the shuffle must not move the hint to pile \(i + 1)")
        }
        if let top = e.board.top(0), let next = e.deck.peek(1).first {
            let want: Guess = (top.joker || next.joker) ? .same
                : next.value > top.value ? .higher : next.value < top.value ? .lower : .same
            XCTAssertEqual(e.pileHint(0), want, "the hint re-reads the pile's CURRENT top")
        }

        // A kill retires the marker: the dead pile must never show one.
        e.board.piles[0].cards = [DeckManager.cardForValue(5)]
        e.debug.setNextCard(9)
        e.guess(0, .lower)   // a 9 over a 5 on a lower call — fatal
        XCTAssertFalse(e.board.isActive(0))
        XCTAssertNil(e.pileHint(0), "a dead pile shows no marker")
    }

    /// Pile indices are identity: a neighbour's death (a Base kill — no draw,
    /// so no hint is spent) never moves the armed pile's marker.
    func testTellHintSurvivesNeighbourDeathsOnItsOwnIndex() {
        guard let demolish = data.baseTypes.all().first(where: { $0.effect == "heartDemolish" })
        else { return XCTFail("no heartDemolish base in the data") }
        let e = engine(bases: [demolish.id, nil, nil])
        // Arm a Tell on pile 3 (index 2 — same column as pile 1, off-suit top).
        let live = DeckManager.toCard(
            CardSpec(id: 4243, suit: "♠", originalRank: 11, currentRank: 11,
                     stickers: [StickerRecord(type: "tell")]), data: data)
        e.board.piles[2].cards = [DeckManager.cardForValue(4)]
        e.debug.setNextCardObj(live)
        e.guess(2, .higher)
        XCTAssertTrue(e.run.tellPiles.contains(2))

        // Pile 1 (index 0) wears a ♥ top; the column's Heart Demolish kills it
        // WITHOUT a draw, so pile 3's armed hint must survive on its own index.
        e.board.piles[0].cards = [LiveCard(id: 9001, label: "5", value: 5, suit: "♥", red: true)]
        let res = e.baseActivate(col: 0)
        XCTAssertNotNil(res)
        XCTAssertFalse(e.board.isActive(0), "the ♥ pile was demolished")
        XCTAssertTrue(e.run.tellPiles.contains(2), "the neighbour's death must not spend pile 3's marker")
        e.debug.setNextCard(3)
        XCTAssertNotNil(e.pileHint(2), "the marker stays on ITS pile")
        XCTAssertNil(e.pileHint(0))
        XCTAssertNil(e.pileHint(1))
    }

    // MARK: - 5. Purge curses roll PER CARD (Task 5)

    /// The report: a purge cursed three cards with the SAME curse. The roll is
    /// one weighted draw per card from the path's pool (OldJoker.buildOffer →
    /// rollCurse, a fresh rng.next() each). Verify statistically over many
    /// node-seeded offers: the all-same rate must hug Σ(w/W)^leechCount (the
    /// rate at which honest per-card rolls legitimately collide), and every
    /// pool member must show up in proportion to its weight. A
    /// roll-once-and-reuse bug would put the all-same rate at 100%.
    func testPurgeCursesRollPerCard() {
        let c = CampaignState()
        c.setDeck("pink"); c.setSeedOverride(4242); c.reset()
        let leech = data.items.oldJoker.int("purge", "leechCount", 3)
        let pool = data.stickerTypes.cursePool(path: "purge")
        let totalW = pool.reduce(0.0) { $0 + $1.curseWeight }
        XCTAssertGreaterThan(pool.count, 3, "the purge pool should hold several curses")
        // The honest-collision rate for leechCount independent weighted draws.
        let pAllSame = pool.reduce(0.0) { $0 + pow($1.curseWeight / totalW, Double(leech)) }

        var offers = 0, allSame = 0
        var perCurse: [String: Int] = [:]
        for node in 1...12000 {
            guard case .purge(_, let curses) = c.rollOldJoker(node) else { continue }
            offers += 1
            if Set(curses).count == 1 { allSame += 1 }
            for id in curses { perCurse[id, default: 0] += 1 }
        }
        XCTAssertGreaterThanOrEqual(offers, 150, "the sweep must collect a real sample (got \(offers))")

        // THE discriminator: a reused roll makes EVERY offer all-same.
        let allowedAllSame = Int((Double(offers) * pAllSame * 5).rounded(.up)) + 2
        XCTAssertLessThanOrEqual(allSame, allowedAllSame,
                                 "\(allSame)/\(offers) all-same purges vs the honest \(String(format: "%.2f", pAllSame * 100))% collision rate")

        // The pool's members all show up, and the shares track the weights
        // (a degenerate rng — same draw every time — would fail both).
        let draws = perCurse.values.reduce(0, +)
        XCTAssertEqual(draws, offers * leech)
        for def in pool {
            let share = Double(perCurse[def.id, default: 0]) / Double(draws)
            let want = def.curseWeight / totalW
            XCTAssertEqual(share, want, accuracy: max(0.06, want * 0.5),
                           "\(def.id): empirical share \(String(format: "%.3f", share)) vs weighted \(String(format: "%.3f", want))")
        }
    }
}
