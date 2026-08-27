import XCTest
@testable import GameCore

/// v6.76 ARCHETYPE BATCH — the cross-cutting contracts the per-item IV
/// scenarios don't cover: the shared tolerated-Same resolution's EVENTS
/// (R1: `.resolved(correct: true)` is where the flow's correctSames bump
/// reads from, `.sameBanked` charges the shield, `.samePower` fires), the
/// sameTolerance family one-per-column placement guard, the shop-rolled
/// offer → lock → save/restore chain (R2), and the Daily Suit / Rank Flood
/// deal-level edges. Tunables are read LIVE from the data, never hardcoded.
final class ArchetypeBatchTests: XCTestCase {
    private let data = GameData.shared

    private func spec(_ id: Int, _ rank: Int, _ suit: String = "♠") -> CardSpec {
        CardSpec(id: id, suit: suit, originalRank: rank, currentRank: rank)
    }

    private func campaign(seed: UInt32 = 5) -> CampaignState {
        let c = CampaignState(store: MemoryStore())
        c.setDeck("pink"); c.setTier("regular"); c.setSeedOverride(seed); c.reset()
        return c
    }

    // MARK: - R1: SURVIVED-SAME = FULL SAME, one shared path

    /// All four tolerances: a wrong Same the pillar tolerates comes out the
    /// FULL correct-Same path — correct resolution, shield charge, power fire.
    func testEveryToleranceResolvesAsAFullCorrectSame() {
        let power = data.samePowerTypes.get("linkCoins")!
        let per = power.num("value", 1) == 0 ? 1 : power.value
        // (pillar id, top, tolerated draw)
        let cases: [(String, CardSpec, CardSpec)] = [
            ("sameTolNear",  spec(1, 5, "♠"),  spec(50, 6, "♥")),   // ±1 in value
            ("sameTolRoyal", spec(1, 11, "♠"), spec(50, 12, "♥")),  // royal on royal
            ("sameTolSum10", spec(1, 4, "♠"),  spec(50, 6, "♥")),   // ranks sum to 10
            ("sameTolSuit",  spec(1, 5, "♠"),  spec(50, 9, "♠")),   // same-suit landing
        ]
        for (id, top, drawn) in cases {
            let e = IV.engine(tops: [top, spec(2, 6, "♦"), spec(3, 7, "♣")],
                              deckOrder: [drawn, spec(51, 3, "♦")],
                              pillars: [id, nil, nil], samePower: power.id)
            var sawResolvedSame = false, sawBanked = false, sawPower = false
            e.on { ev in
                if case .resolved(_, let g, _, _, let ok) = ev, g == .same, ok { sawResolvedSame = true }
                if case .sameBanked(_, let charged) = ev, charged { sawBanked = true }
                if case .samePower(let r) = ev, r.power == power.id { sawPower = true }
            }
            e.guess(0, .same)
            XCTAssertTrue(sawResolvedSame, "\(id): resolved as a CORRECT Same "
                          + "(the flow's correctSames bump reads exactly this event)")
            XCTAssertTrue(sawBanked, "\(id): charged the Same Shield")
            XCTAssertTrue(e.sameCharge, "\(id)")
            XCTAssertTrue(sawPower, "\(id): fired the equipped Same-Power")
            XCTAssertEqual(e.run.bonusCoins, per * 3, "\(id): Dividend paid for 3 alive piles")
            XCTAssertEqual(e.run.correctGuesses, 1, "\(id): the guess counts correct")
            XCTAssertEqual(e.board.top(0)?.id, drawn.id, "\(id): the tolerated card landed")
        }
    }

    /// SAME SUIT SAFE's extra reach: ANY call is safe on a same-suit
    /// landing — but only a SAME call banks the charge / fires the power.
    func testSameSuitToleranceShieldsDirectionalCallsWithoutBanking() {
        let e = IV.engine(tops: [spec(1, 5, "♠"), spec(2, 6, "♦"), spec(3, 7, "♣")],
                          deckOrder: [spec(50, 3, "♠"), spec(51, 4, "♦")],
                          pillars: ["sameTolSuit", nil, nil], samePower: "linkCoins")
        var sawPower = false
        e.on { if case .samePower = $0 { sawPower = true } }
        e.guess(0, .higher)   // 3 on 5 called higher — wrong, but same-suit
        XCTAssertTrue(e.board.isActive(0), "the same-suit landing survived a directional call")
        XCTAssertEqual(e.run.correctGuesses, 1)
        XCTAssertFalse(e.sameCharge, "only a SAME call banks the charge")
        XCTAssertFalse(sawPower, "…and only a SAME call fires the power")
        // …and an off-suit landing is still fatal.
        let e2 = IV.engine(tops: [spec(1, 5, "♠"), spec(2, 6, "♦"), spec(3, 7, "♣")],
                           deckOrder: [spec(50, 3, "♥"), spec(51, 4, "♦")],
                           pillars: ["sameTolSuit", nil, nil])
        e2.guess(0, .higher)   // 3♥ on 5♠ — wrong call, wrong suit
        XCTAssertFalse(e2.board.isActive(0), "an off-suit landing is unprotected")
    }

    /// The family placement guard lives engine-side, with a reason the UI can
    /// show — and placePillar enforces it, not just reports it.
    func testSameToleranceFamilyGuardOnePerColumn() {
        let c = campaign()
        c.pillarInventory["sameTolNear"] = 1
        c.pillarInventory["sameTolSum10"] = 1
        c.pillarInventory["eightPeek"] = 1
        XCTAssertTrue(c.placePillar("sameTolNear", col: 0))
        let denied = c.canPlacePillar("sameTolSum10", col: 0)
        XCTAssertFalse(denied.ok, "a second sameTolerance in one column is rejected")
        XCTAssertFalse((denied.reason ?? "").isEmpty, "…with a reason string for the UI")
        XCTAssertFalse(c.placePillar("sameTolSum10", col: 0), "the placement itself refuses")
        XCTAssertEqual(c.pillarInventory["sameTolSum10"], 1, "…and the inventory copy survives")
        XCTAssertTrue(c.canPlacePillar("sameTolNear", col: 0).ok,
                      "swapping the SAME pillar back onto its column stays legal")
        XCTAssertTrue(c.canPlacePillar("eightPeek", col: 0).ok, "a non-family pillar is fine")
        XCTAssertTrue(c.canPlacePillar("sameTolSum10", col: 1).ok, "another column is fine")
        XCTAssertTrue(c.placePillar("sameTolSum10", col: 1), "family pillars coexist ACROSS columns")
        // The guard survives save/restore with the loadout.
        let c2 = CampaignState(store: MemoryStore())
        XCTAssertTrue(c2.restore(c.serialize()))
        c2.pillarInventory["sameTolRoyal"] = 1
        XCTAssertFalse(c2.canPlacePillar("sameTolRoyal", col: 0).ok)
        XCTAssertFalse(c2.canPlacePillar("sameTolRoyal", col: 1).ok)
        XCTAssertTrue(c2.canPlacePillar("sameTolRoyal", col: 2).ok)
    }

    // MARK: - R2: shop-rolled values

    /// The roll happens AT OFFER TIME in rollUnifiedSlots, off the seeded
    /// store stream: every shelved shopRoll item carries valid rolled values
    /// for exactly the axes its def declares.
    func testShopRollsRollAtOfferTimeOffTheSeededStream() {
        var found: [String: StoreSlot] = [:]
        for seed: UInt32 in 1...300 {
            let rng = RNG(seed: seed)
            let slots = StoreRoll.rollUnifiedSlots(rng, count: 30, data: data,
                                                   isUnlocked: { _ in true }, genCard: nil)
            for s in slots.compactMap({ $0 }) {
                let def = data.pillarTypes.get(s.id) ?? data.baseTypes.get(s.id)
                guard let def, def.shopRoll != nil else { continue }
                found[def.id] = s
                if def.shopRoll == "rank" || def.shopRoll2 == "rank" {
                    XCTAssertTrue((minRank...maxRank).contains(s.rollRank ?? -1),
                                  "\(def.id): the rank axis rolled in range")
                } else {
                    XCTAssertNil(s.rollRank, "\(def.id): an undeclared rank axis stays nil")
                }
                if def.shopRoll == "suit" || def.shopRoll2 == "suit" {
                    XCTAssertTrue(DeckManager.suits.contains { $0.symbol == s.rollSuit },
                                  "\(def.id): the suit axis rolled a real suit")
                } else {
                    XCTAssertNil(s.rollSuit, "\(def.id): an undeclared suit axis stays nil")
                }
            }
        }
        // v6.87: Void Tribute retired — a retired shopRoll item never
        // shelves; Majority Rule keeps the pillar suit axis exercised.
        XCTAssertNil(found["absentSuitClubBury"], "Void Tribute retired — never shelves")
        XCTAssertNotNil(found["suitMajoritySafe"], "the sweep shelved Majority Rule")
        XCTAssertNotNil(found["purgeRank"], "…Rank Purge")
        XCTAssertNotNil(found["transmute"], "…Transmute")
        // v6.78: Transmute's rank is COMPOSITION-DRIVEN (live most common) —
        // only the suit rolls at the shop; Rank Shield left the shopRoll
        // system entirely (dynamic per-deal rank).
        XCTAssertNil(found["transmute"]?.rollRank, "Transmute rolls no rank any more")
        XCTAssertNotNil(found["transmute"]?.rollSuit, "…just the suit")
        XCTAssertNil(found["rankShield"], "Rank Shield no longer rolls at the shop")
    }

    /// First shelf appearance locks the roll for the climb; later shelves
    /// re-show the LOCK (never a fresh roll); the lock survives save/restore.
    func testShopRollLocksHoldForTheClimb() {
        let c = campaign()
        _ = c.addCoins(2000)
        var first: (id: String, rank: Int?, suit: String?)?
        var seed: UInt32 = 100
        while first == nil, seed < 300 {
            let offer = c.openStore(rng: RNG(seed: seed)); seed += 1
            if let s = offer.slots.compactMap({ $0 }).first(where: {
                (data.pillarTypes.get($0.id) ?? data.baseTypes.get($0.id))?.shopRoll != nil
            }) {
                first = (s.id, s.rollRank, s.rollSuit)
            }
        }
        guard let first else { return XCTFail("no shopRoll item shelved in 200 seeded stores") }
        XCTAssertEqual(c.shopRolls[first.id]?.rank, first.rank, "first sighting locked the rank")
        XCTAssertEqual(c.shopRolls[first.id]?.suit, first.suit, "…and the suit")
        var recurred = false
        for s2 in seed..<(seed + 300) {
            let offer = c.openStore(rng: RNG(seed: s2))
            if let s = offer.slots.compactMap({ $0 }).first(where: { $0.id == first.id }) {
                XCTAssertEqual(s.rollRank, first.rank, "the climb lock wins over the fresh roll")
                XCTAssertEqual(s.rollSuit, first.suit)
                recurred = true
                break
            }
        }
        XCTAssertTrue(recurred, "the item re-shelved within 300 visits")
        let c2 = CampaignState(store: MemoryStore())
        XCTAssertTrue(c2.restore(c.serialize()))
        XCTAssertEqual(c2.shopRolls[first.id]?.rank, first.rank, "the lock rides the save")
        XCTAssertEqual(c2.shopRolls[first.id]?.suit, first.suit)
    }

    /// The rolled values ride the StoreSlot through the offer save: a
    /// mid-store kill restores the identical shelf, roll included.
    func testShopRollOfferSurvivesSaveRestoreMidStore() {
        let c = campaign()
        _ = c.addCoins(2000)
        _ = c.openStore()
        c.storeOffer = StoreOffer(slots: [
            StoreSlot(kind: "pillar", id: "absentSuitClubBury", rollSuit: "♦"),
            StoreSlot(kind: "base", id: "transmute", rollSuit: "♣"),
            StoreSlot(kind: "pillar", id: "eightPeek"),     // no axes: stays bare
        ], rerollCost: 0)
        let c2 = CampaignState(store: MemoryStore())
        XCTAssertTrue(c2.restore(c.serialize()))
        let slots = c2.storeOffer?.slots ?? []
        XCTAssertEqual(slots[0]?.rollSuit, "♦")
        XCTAssertNil(slots[0]?.rollRank)
        XCTAssertEqual(slots[1]?.rollSuit, "♣")
        XCTAssertNil(slots[1]?.rollRank, "Transmute rolls no rank (v6.78 — live most common)")
        XCTAssertNil(slots[2]?.rollRank, "a non-shopRoll item never grows a roll")
        // The purchase transfers the slot's roll to the climb lock — unless
        // the (random) open shelf already locked a suit for the item, in
        // which case the LOCK wins (first appearance rules the climb).
        XCTAssertTrue(c2.buyMixedSlot(0).ok)
        XCTAssertNotNil(c2.shopRolls["absentSuitClubBury"]?.suit,
                        "the bought slot's suit locked for the climb")
    }

    // MARK: - Rank Shield (dynamic, v6.78)

    /// At Start Run the shield reads the FULL deck and protects its most
    /// common rank — no shop roll anywhere in the path.
    func testRankShieldProtectsTheMostCommonRankAtDealStart() {
        // 9 is strictly most common across tops + deck (three copies).
        let e = IV.engine(tops: [spec(1, 5, "♠"), spec(2, 6, "♥"), spec(3, 7, "♣")],
                          deckOrder: [spec(50, 9, "♥"), spec(51, 9, "♦"), spec(52, 9, "♣"),
                                      spec(53, 3, "♦")],
                          pillars: ["rankShield", nil, nil])
        XCTAssertEqual(e.run.shopRolls["rankShield"]?.rank, 9,
                       "the deal-start pick is the full deck's most common rank")
        // …and a 9 landing WRONG in the column survives.
        e.guess(0, .lower)                        // 9 on 5 called lower: wrong
        XCTAssertTrue(e.board.isActive(0), "the most-common rank is safe here")
        XCTAssertEqual(e.run.correctGuesses, 1, "the save counts as correct")
    }

    /// TIE RULE 1: the incumbent keeps the shield until STRICTLY surpassed.
    func testRankShieldIncumbentKeepsTheShieldOnATie() {
        // 6 and 9 tie at two copies each; the incumbent (6) stays.
        let e = IV.engine(tops: [spec(1, 6, "♠"), spec(2, 9, "♥"), spec(3, 5, "♣")],
                          deckOrder: [spec(50, 6, "♥"), spec(51, 9, "♦"), spec(52, 3, "♦")],
                          pillars: ["rankShield", nil, nil],
                          shopRolls: ["rankShield": ShopRoll(rank: 6)])
        XCTAssertEqual(e.run.shopRolls["rankShield"]?.rank, 6,
                       "tied at the top → the incumbent holds")
    }

    /// TIE RULE 2: a rank strictly ahead of the incumbent takes the shield.
    func testRankShieldIncumbentFallsWhenStrictlySurpassed() {
        // 9 has three copies, the incumbent 6 has two.
        let e = IV.engine(tops: [spec(1, 6, "♠"), spec(2, 9, "♥"), spec(3, 5, "♣")],
                          deckOrder: [spec(50, 6, "♥"), spec(51, 9, "♦"), spec(52, 9, "♣")],
                          pillars: ["rankShield", nil, nil],
                          shopRolls: ["rankShield": ShopRoll(rank: 6)])
        XCTAssertEqual(e.run.shopRolls["rankShield"]?.rank, 9,
                       "strictly surpassed → the new leader takes the shield")
    }

    /// TIE RULE 3: a tie with NO incumbent picks among the leaders off the
    /// deal's seeded stream — in the tied set, and identical per seed.
    func testRankShieldTieWithoutIncumbentPicksSeededAmongLeaders() {
        let build = {
            IV.engine(tops: [self.spec(1, 6, "♠"), self.spec(2, 9, "♥"), self.spec(3, 5, "♣")],
                      deckOrder: [self.spec(50, 6, "♥"), self.spec(51, 9, "♦"), self.spec(52, 3, "♦")],
                      pillars: ["rankShield", nil, nil])
        }
        let a = build().run.shopRolls["rankShield"]?.rank
        let b = build().run.shopRolls["rankShield"]?.rank
        XCTAssertTrue([6, 9].contains(a ?? -1), "the pick is one of the tied leaders")
        XCTAssertEqual(a, b, "same seed → same pick (deal-seeded, never bare rng)")
    }

    /// The FULL-OWNED-DECK hook rules the count: a campaign subset deal
    /// reads the whole collection, not the subset in play. (The hook must
    /// be installed BEFORE startRun — the pick happens there.)
    func testRankShieldReadsTheFullOwnedDeckThroughTheHook() {
        // The owned deck says 4s dominate, whatever the deal subset holds
        // (its own cards lean 9).
        let owned = (0..<4).map { DeckManager.toCard(spec(90 + $0, 4, "♦"), data: GameData.shared) }
            + [DeckManager.toCard(spec(99, 9, "♥"), data: GameData.shared)]
        let e = GameEngine(deckSpecs: [spec(1, 5, "♠"), spec(2, 6, "♥"), spec(3, 7, "♣"),
                                       spec(50, 9, "♥"), spec(51, 9, "♦"), spec(52, 3, "♦")],
                           pileCount: 3,
                           runConfig: RunConfig(cols: [1, 1, 1]))
        e.fullDeckProvider = { owned }
        e.start(seedOverride: 7)
        e.startRun(pillars: ["rankShield", nil, nil], bases: [nil, nil, nil], samePower: nil)
        XCTAssertEqual(e.run.shopRolls["rankShield"]?.rank, 4,
                       "the hook's owned deck (4s dominate) rules the pick")
    }

    // MARK: - Scarce Suit (v6.81 — deal-start fewest-suit read, snapshot
    //         round-trip; was "Daily Suit", a per-deal random roll)

    /// v6.82 (user's rule): a suit you hold NONE of IS the scarcest and is
    /// chosen — zero is the smallest number. Tops ♠♥♣ + draw ♠♥ leaves ♦
    /// absent, so ♦ takes the shield whatever the seed.
    func testScarceSuitPrefersASuitYouHoldNoneOf() {
        for seed: UInt32 in [7, 99, 4242] {
            let e = IV.engine(tops: [spec(1, 5, "♠"), spec(2, 6, "♥"), spec(3, 6, "♣")],
                              deckOrder: [spec(50, 9, "♠"), spec(51, 3, "♥")],
                              pillars: ["suitShield", nil, nil], seed: seed)
            XCTAssertEqual(e.run.dailySuits?[0], "♦",
                           "seed \(seed): a suit held zero times is the scarcest")
        }
    }

    /// v6.86 regression pin for the batch report: ZERO beats one — a suit at
    /// zero copies is never excluded from candidacy — and a two-zero tie
    /// takes the FIRST zero suit in canonical ♦♥♣♠ order.
    func testScarceSuitZeroCountIsEligibleAndWinsOutright() {
        // ♥ absent, ♦ held once: the shield must read ♥ (0 < 1), not ♦.
        let e = IV.engine(tops: [spec(1, 5, "♠"), spec(2, 6, "♦"), spec(3, 6, "♣")],
                          deckOrder: [spec(50, 9, "♠"), spec(51, 3, "♣")],
                          pillars: ["suitShield", nil, nil])
        XCTAssertEqual(e.run.dailySuits?[0], "♥", "zero copies beats one copy")
        // ♥ AND ♣ both absent: the first zero in canonical ♦♥♣♠ order wins.
        let tie = IV.engine(tops: [spec(1, 5, "♠"), spec(2, 6, "♦"), spec(3, 6, "♠")],
                            deckOrder: [spec(50, 9, "♦"), spec(51, 3, "♠")],
                            pillars: ["suitShield", nil, nil])
        XCTAssertEqual(tie.run.dailySuits?[0], "♥", "the canonical order breaks a zero-zero tie")
    }

    /// With every suit present it takes the strict minimum — and re-reads the
    /// deck each deal, so a different deck shields a different suit.
    func testScarceSuitPicksTheFewestPresentSuitAndRecomputesPerDeal() {
        // ♠2 ♥2 ♦2 ♣1 → ♣ (third in canonical order, so it cannot be an
        // artifact of the tie-break).
        let a = IV.engine(tops: [spec(1, 5, "♠"), spec(2, 6, "♥"), spec(3, 6, "♦")],
                          deckOrder: [spec(50, 9, "♠"), spec(51, 3, "♥"),
                                      spec(52, 4, "♦"), spec(53, 2, "♣")],
                          pillars: ["suitShield", nil, nil])
        XCTAssertEqual(a.run.dailySuits?[0], "♣", "the strict minimum takes the shield")
        // The NEXT deal (a different deck) re-reads: ♠2 ♥2 ♣2 ♦1 → ♦.
        let b = IV.engine(tops: [spec(1, 5, "♠"), spec(2, 6, "♥"), spec(3, 6, "♣")],
                          deckOrder: [spec(50, 9, "♠"), spec(51, 3, "♥"),
                                      spec(52, 4, "♣"), spec(53, 2, "♦")],
                          pillars: ["suitShield", nil, nil])
        XCTAssertEqual(b.run.dailySuits?[0], "♦", "each deal re-reads the deck")
    }

    /// A full standard deck ties all four at 13 → the canonical suit order
    /// breaks it, deterministically, with no rng draw.
    func testScarceSuitTieBreaksCanonically() {
        let tie = GameEngine(deckSpecs: DeckManager.buildStandardDeck(), pileCount: 3,
                             runConfig: RunConfig(cols: [1, 1, 1]))
        tie.start(seedOverride: 7)
        tie.startRun(pillars: ["suitShield", nil, nil], bases: [nil, nil, nil], samePower: nil)
        XCTAssertEqual(tie.run.dailySuits?[0], DeckManager.suits[0].symbol,
                       "a full tie breaks to the first canonical suit")
    }

    func testScarceSuitReadsTheFullOwnedDeckThroughTheHook() {
        // The OWNED deck holds all four suits with ♦ fewest — the deal's own
        // cards (no ♦ at all) must not decide it.
        let owned = [spec(90, 4, "♠"), spec(91, 5, "♠"), spec(92, 6, "♥"),
                     spec(93, 7, "♥"), spec(94, 8, "♣"), spec(95, 9, "♣"),
                     spec(96, 10, "♦")]
            .map { DeckManager.toCard($0, data: GameData.shared) }
        let e = GameEngine(deckSpecs: [spec(1, 5, "♠"), spec(2, 6, "♥"), spec(3, 6, "♣"),
                                       spec(50, 9, "♠")],
                           pileCount: 3, runConfig: RunConfig(cols: [1, 1, 1]))
        e.fullDeckProvider = { owned }
        e.start(seedOverride: 7)
        e.startRun(pillars: ["suitShield", nil, nil], bases: [nil, nil, nil], samePower: nil)
        XCTAssertEqual(e.run.dailySuits?[0], "♦",
                       "the hook's owned deck rules the scarce-suit read")
    }

    func testScarceSuitRoundTripsSnapshotAndStillShields() {
        let build = {
            IV.engine(tops: [self.spec(1, 5, "♠"), self.spec(2, 6, "♥"), self.spec(3, 6, "♣")],
                      deckOrder: [self.spec(50, 9, "♠"), self.spec(51, 3, "♥")],
                      pillars: ["suitShield", nil, nil])
        }
        let e = build()
        guard let shielded = e.run.dailySuits?[0] else { return XCTFail("the suit computed at Start Run") }
        // Snapshot → twin: the suit survives the mid-deal save…
        let twin = build()
        XCTAssertTrue(twin.restoreSnapshot(e.snapshot()))
        XCTAssertEqual(twin.run.dailySuits?[0], shielded)
        // …and still shields it: craft a wrong-call landing of that suit.
        var cards = twin.deck.snapshotCards()
        cards[0] = DeckManager.toCard(spec(90, 9, shielded), data: data)
        twin.deck.restoreSnapshot(cards: cards, drawn: twin.deck.drawn())
        twin.guess(0, .lower)   // 9 on 5 called lower: wrong, but shielded
        XCTAssertTrue(twin.board.isActive(0), "the restored engine still shields the scarce suit")
    }

    // MARK: - Crazy Eights latch (deal-start composition condition)

    /// The size-8 opening is latched at Start Run and GROWS from there: a
    /// landing on the pile takes it to 9, and later composition shifts never
    /// take the opening size away.
    func testEightStartLatchesAndGrows() {
        guard data.pillarTypes.get("eightStart") != nil else { return XCTFail("eightStart missing") }
        // 8s are the most common rank (3 of 6 cards).
        let specs = [spec(1, 8, "♠"), spec(2, 8, "♥"), spec(3, 8, "♦"),
                     spec(4, 5, "♣"), spec(5, 9, "♠"), spec(6, 14, "♥")]
        let e = GameEngine(deckSpecs: specs, pileCount: 3,
                           runConfig: RunConfig(cols: [1, 1, 1]))
        e.start(seedOverride: 7)
        e.startRun(pillars: ["eightStart", nil, nil], bases: [nil, nil, nil], samePower: .some(nil))
        XCTAssertEqual(e.board.pileSize(0), 8, "the column opens at pile size 8")
        // Force a correct landing onto pile 0: it grows FROM 8, to 9.
        let top = e.board.top(0)
        let next = e.deck.peek(1).first
        if let top, let next, !top.joker, !next.joker {
            let call: Guess = next.value > top.value ? .higher
                            : next.value < top.value ? .lower : .same
            e.guess(0, call)
            XCTAssertEqual(e.board.pileSize(0), 9, "the pile grows from its size-8 opening")
        }
        // The latch rides the snapshot's per-pile sizeBonus (Same Heavy's key).
        let twin = GameEngine(deckSpecs: specs, pileCount: 3,
                              runConfig: RunConfig(cols: [1, 1, 1]))
        twin.start(seedOverride: 7)
        twin.startRun(pillars: ["eightStart", nil, nil], bases: [nil, nil, nil], samePower: .some(nil))
        XCTAssertTrue(twin.restoreSnapshot(e.snapshot()))
        XCTAssertEqual(twin.board.pileSize(0), e.board.pileSize(0), "the latched size round-trips")
    }

    // MARK: - Rank Flood (same-power) joker rules

    private final class PowerBox { var result: SamePowerResult? }

    /// Fire Rank Flood on pile 0 whose (bottom…top) stack is `hub`.
    private func flood(_ hub: [CardSpec]) -> (GameEngine, PowerBox) {
        let e = IV.engine(tops: [spec(1, 5, "♠"), spec(2, 6, "♦"), spec(3, 7, "♥")],
                          deckOrder: [spec(50, 9, "♣")], samePower: "rankFlood")
        e.board.piles[0].cards = hub.map { DeckManager.toCard($0, data: data) }
        let box = PowerBox()
        e.on { if case .samePower(let r) = $0 { box.result = r } }
        e.debugFireSamePower(0)
        return (e, box)
    }

    func testRankFloodRanksEveryAliveTopByTheCalledCard() {
        let (e, box) = flood([spec(1, 5, "♠"), spec(60, 9, "♥")])   // called card: 9
        XCTAssertEqual(e.board.top(1)?.value, 9)
        XCTAssertEqual(e.board.top(2)?.value, 9)
        XCTAssertEqual(e.board.top(1)?.label, "9", "the label follows the rank")
        XCTAssertEqual(box.result?.amount, 3, "all three alive piles rewrote")
        XCTAssertEqual(box.result?.rankApplied.count, 3, "…and report for the durable write-back")
    }

    func testRankFloodJokerOnEitherSideRanksByTheRankedCard() {
        // Joker on TOP, ranked card beneath (the Same's other side).
        let (e1, _) = flood([spec(1, 9, "♠"), .joker(id: 60)])
        XCTAssertEqual(e1.board.top(1)?.value, 9, "the joker top ranks them by the ranked card")
        XCTAssertEqual(e1.board.top(2)?.value, 9)
        XCTAssertTrue(e1.board.top(0)?.joker ?? false, "joker tops stay rankless wildcards")
        // Joker BENEATH, ranked card on top.
        let (e2, _) = flood([.joker(id: 60), spec(1, 12, "♠")])
        XCTAssertEqual(e2.board.top(1)?.value, 12)
        XCTAssertEqual(e2.board.top(2)?.value, 12)
    }

    func testRankFloodJokerOnJokerMakesAces() {
        let (e, _) = flood([.joker(id: 60), .joker(id: 61)])
        XCTAssertEqual(e.board.top(1)?.value, maxRank, "joker-on-joker → Aces")
        XCTAssertEqual(e.board.top(2)?.value, maxRank)
        XCTAssertEqual(e.board.top(1)?.label, "A")
    }
}
