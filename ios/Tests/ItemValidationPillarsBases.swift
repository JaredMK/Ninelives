import XCTest
@testable import GameCore

/// TIER 1 scenario generators — PILLARS, BASES, SAME-POWERS.
enum IVPillarsBases {

    static let data = GameData.shared

    /// A pillar landing family: the pillar sits on column 0, a correct
    /// HIGHER guess lands `drawn` on pile 0.
    static func pillarLanding(_ def: ItemDef, drawn: CardSpec,
                              tops: [CardSpec?]? = nil,
                              variants: [String: Int] = [:],
                              allowed: IV.Allowed,
                              expect: @escaping (GameEngine, IV.Frame, String) -> Void)
        -> (build: () -> GameEngine, fire: (GameEngine) -> Void, scenario: IV.Scenario) {
        let build = {
            IV.engine(tops: tops ?? [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)],
                      deckOrder: [drawn, IV.spec(59, 2)],
                      pillars: [def.id, nil, nil],
                      pillarRankVariants: variants)
        }
        let fire: (GameEngine) -> Void = { $0.guess(0, .higher) }
        return (build, fire,
                IV.Scenario("trigger", allowed: allowed.union([.guesses, .deck, .board]),
                            build: build, fire: fire, expect: expect))
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    static func scenarios(for def: ItemDef) -> [IV.Scenario]? {
        let v = def.value
        switch def.effect {

        // ── live landing pillars ────────────────────────────────────────────
        case "prime":
            let unit = def.num("value", 1) == 0 ? 1 : v
            let t = pillarLanding(def, drawn: IV.spec(50, 7), allowed: .coins) { e, f, c in
                XCTAssertEqual(e.run.bonusCoins, f.bonusCoins + unit, "\(c): a prime (7) landed → +\(unit)")
            }
            return [t.scenario,
                IV.Scenario("edge-aceIsNotPrime", allowed: [.guesses, .deck, .board],
                    build: { IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 14), IV.spec(59, 2)],
                                       pillars: [def.id, nil, nil]) },
                    fire: { $0.guess(0, .higher) },
                    expect: { e, f, c in XCTAssertEqual(e.run.bonusCoins, f.bonusCoins, "\(c)") }),
                IV.Scenario("mustNotFire-otherColumn", allowed: [.guesses, .deck, .board],
                    build: { IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 7), IV.spec(59, 2)],
                                       pillars: [nil, def.id, nil]) },
                    fire: { $0.guess(0, .higher) },
                    expect: { e, f, c in
                        XCTAssertEqual(e.run.bonusCoins, f.bonusCoins, "\(c): a prime in ANOTHER column pays 0")
                    })]

        // ("fibonacci" retired in v6.78 — the registry no longer carries it.)

        case "suitBounty":
            let suit = def.suit ?? "♥"
            let t = pillarLanding(def, drawn: IV.spec(50, 9, suit), allowed: .coins) { e, f, c in
                XCTAssertEqual(e.run.bonusCoins, f.bonusCoins + v, "\(c): a \(suit) landed → +\(v)")
            }
            return [t.scenario,
                IV.Scenario("edge-wildSuitCounts", allowed: [.coins, .guesses, .deck, .board],
                    build: { IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 9, "♣", ["wildSuit"]), IV.spec(59, 2)],
                                       pillars: [def.id, nil, nil]) },
                    fire: { $0.guess(0, .higher) },
                    expect: { e, f, c in
                        XCTAssertEqual(e.run.bonusCoins, f.bonusCoins + v, "\(c): wild = every suit")
                    }),
                IV.Scenario("mustNotFire-offSuit", allowed: [.guesses, .deck, .board],
                    build: { IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 9, "♣"), IV.spec(59, 2)],
                                       pillars: [def.id, nil, nil]) },
                    fire: { $0.guess(0, .higher) },
                    expect: { e, f, c in XCTAssertEqual(e.run.bonusCoins, f.bonusCoins, "\(c)") })]

        case "rankCoin", "rankBury":
            let isCoin = def.effect == "rankCoin"
            let unit = isCoin ? (def.num("value", 2) == 0 ? 2 : v) : 0
            let dig = def.int("digCount", 1)
            return [
                IV.Scenario("trigger-lockedRankLands", allowed: [.coins, .guesses, .deck, .board],
                    build: { IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 9), IV.spec(59, 2)],
                                       pillars: [def.id, nil, nil],
                                       pillarRankVariants: [def.id: 9]) },
                    fire: { $0.guess(0, .higher) },
                    expect: { e, f, c in
                        if isCoin {
                            XCTAssertEqual(e.run.bonusCoins, f.bonusCoins + unit, "\(c): +\(unit) on its rank")
                        } else {
                            XCTAssertEqual(e.board.piles[0].cards.count, f.pileCounts[0] + 1 + dig,
                                           "\(c): buried \(dig) on its rank")
                        }
                    }),
                IV.Scenario("edge-lastDeckCard", allowed: .all,
                    build: { IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 9)],
                                       pillars: [def.id, nil, nil],
                                       pillarRankVariants: [def.id: 9]) },
                    fire: { $0.guess(0, .higher) },
                    expect: { _, _, _ in }, skipSnapshot: true),
                IV.Scenario("mustNotFire-otherRank", allowed: [.guesses, .deck, .board],
                    build: { IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 9), IV.spec(59, 2)],
                                       pillars: [def.id, nil, nil],
                                       pillarRankVariants: [def.id: 4]) },
                    fire: { $0.guess(0, .higher) },
                    expect: { e, f, c in
                        XCTAssertEqual(e.run.bonusCoins, f.bonusCoins, "\(c)")
                        XCTAssertEqual(e.board.piles[0].cards.count, f.pileCounts[0] + 1, "\(c)")
                    }),
            ]

        case "queensEye":
            let t = pillarLanding(def, drawn: IV.spec(50, 12, "♠"), allowed: []) { e, _, c in
                XCTAssertTrue(e.run.revealNextActive, "\(c): a ♠ royal landed → peek")
            }
            return [t.scenario,
                IV.Scenario("edge-redRoyalNo", allowed: [.guesses, .deck, .board],
                    build: { IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 12, "♥"), IV.spec(59, 2)],
                                       pillars: [def.id, nil, nil]) },
                    fire: { $0.guess(0, .higher) },
                    expect: { e, _, c in XCTAssertFalse(e.run.revealNextActive, "\(c): ♥ royal, no eye") }),
                IV.Scenario("mustNotFire-numberCard", allowed: [.guesses, .deck, .board],
                    build: { IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 9, "♠"), IV.spec(59, 2)],
                                       pillars: [def.id, nil, nil]) },
                    fire: { $0.guess(0, .higher) },
                    expect: { e, _, c in XCTAssertFalse(e.run.revealNextActive, "\(c)") })]

        case "shuffler", "diamondDistribution":
            let isDist = def.effect == "diamondDistribution"
            return [
                IV.Scenario("trigger-diamondLands", allowed: [.guesses, .deck, .board],
                    build: {
                        let e = IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)],
                                          deckOrder: [IV.spec(50, 9, "♦"), IV.spec(59, 2)],
                                          cols: [3], pillars: [def.id])
                        // Uneven buried cards so a redistribution is observable.
                        e.board.piles[1].cards.append(DeckManager.toCard(IV.spec(90, 7), data: data))
                        e.board.piles[1].cards.append(DeckManager.toCard(IV.spec(91, 8), data: data))
                        return e
                    },
                    fire: { $0.guess(0, .higher) },
                    expect: { e, f, c in
                        if isDist {
                            let sizes = (0..<3).map { e.board.piles[$0].cards.count }
                            XCTAssertEqual(sizes.reduce(0, +), f.pileCounts.reduce(0, +) + 1,
                                           "\(c): redistribution conserves cards")
                            XCTAssertLessThanOrEqual(sizes.max()! - sizes.min()!, 1,
                                                     "\(c): the column is evened out")
                        } else {
                            XCTAssertEqual(e.board.piles[1].cards.count, f.pileCounts[1],
                                           "\(c): a shuffle moves nothing between piles")
                        }
                    }),
                IV.Scenario("edge-tiePreserved", allowed: .all,
                    build: { IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 9, "♦")],
                                       cols: [3], pillars: [def.id]) },
                    fire: { $0.guess(0, .higher) },
                    expect: { _, _, _ in }, skipSnapshot: true),
                IV.Scenario("mustNotFire-nonDiamond", allowed: [.guesses, .deck, .board],
                    build: { IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 9, "♣"), IV.spec(59, 2)],
                                       cols: [3], pillars: [def.id]) },
                    fire: { $0.guess(0, .higher) },
                    expect: { e, f, c in
                        XCTAssertEqual((0..<3).map { e.board.piles[$0].cards.count },
                                       [f.pileCounts[0] + 1, f.pileCounts[1], f.pileCounts[2]], "\(c)")
                    }),
            ]

        case "flypaper":
            return [
                IV.Scenario("trigger-chanceRoll", allowed: .all,
                    build: { IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 9), IV.spec(59, 2)],
                                       pillars: [def.id, nil, nil]) },
                    fire: { e in
                        // Sweep seeds until the 5% roll hits (deterministic).
                        for seed: UInt32 in 1...600 {
                            e.rng.state = seed
                            var stuck = false
                            e.on { if case .pillarSticker = $0 { stuck = true } }
                            e.guess(0, .higher)
                            if stuck || e.run.totalGuesses > 0 { return }
                        }
                    },
                    expect: { e, _, c in
                        XCTAssertEqual(e.run.totalGuesses, 1, "\(c): the sweep made one guess")
                    }),
                IV.Scenario("edge-jokersTakeNoSticker", allowed: .all,
                    build: { IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 0, joker: true), IV.spec(59, 2)],
                                       pillars: [def.id, nil, nil]) },
                    fire: { $0.guess(0, .higher) },
                    expect: { e, _, c in
                        XCTAssertTrue(e.board.top(0)!.stickers.isEmpty, "\(c): a ★ never takes stickers")
                    }),
                IV.Scenario("mustNotFire-noPillar", allowed: [.guesses, .deck, .board],
                    build: { IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 9), IV.spec(59, 2)]) },
                    fire: { $0.guess(0, .higher) },
                    expect: { e, _, c in
                        XCTAssertTrue(e.board.top(0)!.stickers.isEmpty, "\(c)")
                    }),
            ]

        case "clubTribute", "denseBury":
            let isDense = def.effect == "denseBury"
            let dig = def.int("digCount", 1)
            let minStk = def.int("minStickers", 2)
            // The dense carrier wears exactly minStickers (v6.87: 3) — the
            // load is read live so a retune keeps the trigger honest.
            let denseLoad = Array(["tell", "tieSafe", "anchor", "quickBury"].prefix(minStk))
            let drawnSpec = isDense ? IV.spec(50, 9, "♣", denseLoad) : IV.spec(50, 9, "♣")
            return [
                IV.Scenario("trigger-clubLands", allowed: [.guesses, .deck, .board],
                    build: { IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [drawnSpec, IV.spec(59, 2), IV.spec(60, 3)],
                                       pillars: [def.id, nil, nil]) },
                    fire: { $0.guess(0, .higher) },
                    expect: { e, f, c in
                        XCTAssertEqual(e.board.piles[0].cards.count, f.pileCounts[0] + 1 + dig,
                                       "\(c): buried \(dig) under the ♣ landing")
                    }),
                IV.Scenario("edge-emptyDeckBuriesNothing", allowed: .all,
                    build: { IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [drawnSpec],
                                       pillars: [def.id, nil, nil]) },
                    fire: { $0.guess(0, .higher) },
                    expect: { e, f, c in
                        XCTAssertEqual(e.board.piles[0].cards.count, f.pileCounts[0] + 1,
                                       "\(c): nothing left to bury")
                    }, skipSnapshot: true),
                IV.Scenario(isDense ? "mustNotFire-fewStickers" : "mustNotFire-offSuit",
                    allowed: [.guesses, .deck, .board],
                    build: {
                        let d = isDense ? IV.spec(50, 9, "♣", Array(repeating: "tell", count: max(0, minStk - 2)))
                                        : IV.spec(50, 9, "♥")
                        return IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)],
                                         deckOrder: [d, IV.spec(59, 2)],
                                         pillars: [def.id, nil, nil])
                    },
                    fire: { $0.guess(0, .higher) },
                    expect: { e, f, c in
                        XCTAssertEqual(e.board.piles[0].cards.count, f.pileCounts[0] + 1, "\(c)")
                    }),
            ]

        case "wildAces":
            return [
                IV.Scenario("trigger-aceLandsLow", allowed: [.guesses, .deck, .board],
                    build: { IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 14), IV.spec(59, 2)],
                                       pillars: [def.id, nil, nil]) },
                    fire: { e in
                        var flipped = false
                        e.on { if case .wildAceFlipped = $0 { flipped = true } }
                        e.guess(0, .lower)   // A as 1 < 5: correct here only
                        XCTAssertTrue(flipped, "wildAces: the flip ANNOUNCES itself (v6.50 audit fix)")
                    },
                    expect: { e, _, c in
                        XCTAssertTrue(e.board.isActive(0), "\(c): the Ace played LOW and survived")
                        XCTAssertEqual(e.run.correctGuesses, 1, "\(c)")
                    }),
                IV.Scenario("edge-aceStillHigh", allowed: [.guesses, .deck, .board],
                    build: { IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 14), IV.spec(59, 2)],
                                       pillars: [def.id, nil, nil]) },
                    fire: { $0.guess(0, .higher) },
                    expect: { e, _, c in XCTAssertTrue(e.board.isActive(0), "\(c): 14 > 5 also correct") }),
                IV.Scenario("mustNotFire-noPillarAceLowKills", allowed: [.guesses, .deck, .board, .deaths],
                    build: { IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 14), IV.spec(59, 2)]) },
                    fire: { $0.guess(0, .lower) },
                    expect: { e, _, c in XCTAssertFalse(e.board.isActive(0), "\(c): no pillar, 14 is high") }),
            ]

        case "columnTieSafe":
            return [
                IV.Scenario("trigger-tieSaved", allowed: [.guesses, .deck, .board],
                    build: { IV.engine(tops: [IV.spec(1, 7), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 7), IV.spec(59, 2)],
                                       pillars: [def.id, nil, nil]) },
                    fire: { $0.guess(0, .higher) },
                    expect: { e, _, c in XCTAssertTrue(e.board.isActive(0), "\(c): the column absorbs ties") }),
                IV.Scenario("edge-sameGuessStillBanks", allowed: [.guesses, .deck, .board, .charge, .coins],
                    build: { IV.engine(tops: [IV.spec(1, 7), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 7), IV.spec(59, 2)],
                                       pillars: [def.id, nil, nil]) },
                    fire: { $0.guess(0, .same) },
                    expect: { e, _, c in XCTAssertTrue(e.sameCharge, "\(c): a real Same still banks") }),
                IV.Scenario("mustNotFire-otherColumnTieKills", allowed: [.guesses, .deck, .board, .deaths],
                    build: { IV.engine(tops: [IV.spec(1, 7), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 7), IV.spec(59, 2)],
                                       pillars: [nil, def.id, nil]) },
                    fire: { $0.guess(0, .higher) },
                    expect: { e, _, c in XCTAssertFalse(e.board.isActive(0), "\(c)") }),
            ]

        case "secondWind":
            return [
                IV.Scenario("trigger-savesOnItsRoll", allowed: .all,
                    build: { IV.engine(tops: [IV.spec(1, 9), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 2), IV.spec(59, 3), IV.spec(60, 4)],
                                       pillars: [def.id, nil, nil]) },
                    fire: { e in
                        for seed: UInt32 in 1...300 {
                            e.rng.state = seed
                            e.guess(0, .higher)   // wrong → death unless the roll saves
                            if e.board.isActive(0) { return }
                            return   // either way, one guess: the roll is covered by the sweep below
                        }
                    },
                    expect: { e, _, c in
                        XCTAssertEqual(e.run.totalGuesses, 1, "\(c)")
                    }),
                IV.Scenario("edge-saveRecycles", allowed: .all,
                    build: { IV.engine(tops: [IV.spec(1, 9), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 2), IV.spec(59, 3), IV.spec(60, 4)],
                                       pillars: [def.id, nil, nil]) },
                    fire: { e in
                        // Find a seed that SAVES, then assert the recycle shape.
                        for seed: UInt32 in 1...2000 {
                            let t = IV.engine(tops: [IV.spec(1, 9), IV.spec(2, 6), IV.spec(3, 6)],
                                              deckOrder: [IV.spec(50, 2), IV.spec(59, 3), IV.spec(60, 4)],
                                              pillars: [def.id, nil, nil])
                            t.rng.state = seed
                            t.guess(0, .higher)
                            if t.board.isActive(0) {
                                e.rng.state = seed
                                e.guess(0, .higher)
                                return
                            }
                        }
                        XCTFail("no saving seed in 1...2000 — the 25% roll is broken")
                    },
                    expect: { e, _, c in
                        XCTAssertTrue(e.board.isActive(0), "\(c): saved")
                        XCTAssertEqual(e.board.piles[0].cards.count, 1, "\(c): one fresh top after recycle")
                    }),
                IV.Scenario("mustNotFire-correctGuess", allowed: [.guesses, .deck, .board],
                    build: { IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 9), IV.spec(59, 2)],
                                       pillars: [def.id, nil, nil]) },
                    fire: { $0.guess(0, .higher) },
                    expect: { e, _, c in
                        XCTAssertEqual(e.board.piles[0].cards.count, 2, "\(c): no roll on a survival")
                    }),
            ]

        case "lastRites":
            return [
                IV.Scenario("trigger-deathPeeks", allowed: [.guesses, .deck, .board, .deaths],
                    build: { IV.engine(tops: [IV.spec(1, 9), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 2), IV.spec(59, 3)],
                                       pillars: [def.id, nil, nil]) },
                    fire: { $0.guess(0, .higher) },
                    expect: { e, _, c in
                        XCTAssertTrue(e.run.revealNextActive, "\(c): the death paid a peek")
                    }),
                IV.Scenario("edge-survivalNoPeek", allowed: [.guesses, .deck, .board],
                    build: { IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 9), IV.spec(59, 2)],
                                       pillars: [def.id, nil, nil]) },
                    fire: { $0.guess(0, .higher) },
                    expect: { e, _, c in XCTAssertEqual(e.run.kamikazeRevealLeft, 0, "\(c)") }),
                IV.Scenario("mustNotFire-otherColumnDeath", allowed: [.guesses, .deck, .board, .deaths],
                    build: { IV.engine(tops: [IV.spec(1, 9), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 2), IV.spec(59, 3)],
                                       pillars: [nil, def.id, nil]) },
                    fire: { $0.guess(0, .higher) },
                    expect: { e, _, c in XCTAssertFalse(e.run.revealNextActive, "\(c)") }),
            ]

        case "static":
            return [
                IV.Scenario("trigger-spadeMayPeek", allowed: .all,
                    build: { IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 9, "♠"), IV.spec(59, 2)],
                                       pillars: [def.id, nil, nil]) },
                    fire: { e in
                        for seed: UInt32 in 1...200 {
                            e.rng.state = seed
                            e.guess(0, .higher)
                            return
                        }
                    },
                    expect: { e, _, c in XCTAssertEqual(e.run.totalGuesses, 1, "\(c)") }),
                IV.Scenario("edge-heartNeverPeeks", allowed: [.guesses, .deck, .board],
                    build: { IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 9, "♥"), IV.spec(59, 2)],
                                       pillars: [def.id, nil, nil]) },
                    fire: { $0.guess(0, .higher) },
                    expect: { e, _, c in XCTAssertFalse(e.run.revealNextActive, "\(c)") }),
                IV.Scenario("mustNotFire-wrongGuess", allowed: [.guesses, .deck, .board, .deaths],
                    build: { IV.engine(tops: [IV.spec(1, 9), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 2, "♠"), IV.spec(59, 3)],
                                       pillars: [def.id, nil, nil]) },
                    fire: { $0.guess(0, .higher) },
                    expect: { e, _, c in XCTAssertFalse(e.run.revealNextActive, "\(c)") }),
            ]

        case "streakSize", "streakTribute":
            let isSize = def.effect == "streakSize"
            let th = def.int("threshold", 3)
            func streakEngine() -> GameEngine {
                var deck: [CardSpec] = []
                for i in 0..<(th + 1) { deck.append(IV.spec(50 + i, 6 + i)) }   // ascending: all HIGHER correct
                deck.append(IV.spec(80, 2))
                return IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 4), IV.spec(3, 4)],
                                 deckOrder: deck, cols: [3], pillars: [def.id])
            }
            return [
                IV.Scenario("trigger-streakReached", allowed: .all,
                    build: streakEngine,
                    fire: { e in for _ in 0..<th { e.guess(0, .higher) } },
                    expect: { e, _, c in
                        if isSize {
                            XCTAssertEqual(e.board.pileSize(0), (1 + th) + 1,
                                           "\(c): streak \(th) adds +1 size to the column")
                        } else {
                            XCTAssertGreaterThan(e.board.piles[0].cards.count, 1 + th,
                                                 "\(c): the streak buried extras")
                        }
                    }),
                IV.Scenario("edge-belowThreshold", allowed: .all,
                    build: streakEngine,
                    fire: { e in for _ in 0..<(th - 1) { e.guess(0, .higher) } },
                    expect: { e, _, c in
                        if isSize {
                            XCTAssertEqual(e.board.pileSize(0), 1 + (th - 1), "\(c): no bonus below \(th)")
                        } else {
                            XCTAssertEqual(e.board.piles[0].cards.count, 1 + (th - 1), "\(c)")
                        }
                    }),
                IV.Scenario("mustNotFire-brokenStreak", allowed: .all,
                    build: {
                        var deck: [CardSpec] = [IV.spec(50, 6), IV.spec(51, 7)]
                        deck.append(IV.spec(52, 9))
                        deck.append(IV.spec(80, 2))
                        return IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 4), IV.spec(3, 4)],
                                         deckOrder: deck, cols: [1, 1, 1], pillars: [def.id, nil, nil])
                    },
                    fire: { e in
                        e.guess(0, .higher)      // streak 1 in col 0
                        e.guess(1, .higher)      // a guess in ANOTHER column resets col 0
                    },
                    expect: { e, _, c in
                        XCTAssertEqual(e.run.colStreak?[0], 0, "\(c): the other column broke the streak")
                    }),
            ]

        case "revive":
            let trigger = def.int("trigger", 10)
            return [
                IV.Scenario("trigger-offerAtSize", allowed: .all,
                    build: {
                        let e = IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), nil],
                                          deckOrder: [IV.spec(50, 9), IV.spec(59, 2)],
                                          pillars: [def.id, nil, nil])
                        for i in 0..<(trigger - 2) {
                            e.board.piles[0].cards.append(DeckManager.toCard(IV.spec(100 + i, 3), data: data))
                        }
                        return e
                    },
                    fire: { e in
                        var offered = false
                        e.on { if case .reviveOffer = $0 { offered = true } }
                        e.guess(0, .higher)
                        XCTAssertTrue(offered, "revive/trigger: the offer fired at \(trigger) cards")
                        _ = e.reviveDeadPile(col: 0, targetIndex: 2)
                    },
                    expect: { e, _, c in
                        XCTAssertTrue(e.board.isActive(2), "\(c): the dead pile came back")
                        XCTAssertEqual(e.run.reviveUsed?[0], true, "\(c): the one-shot is spent")
                    }),
                IV.Scenario("edge-noDeadPileKeepsCharge", allowed: .all,
                    build: {
                        let e = IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)],
                                          deckOrder: [IV.spec(50, 9), IV.spec(59, 2)],
                                          pillars: [def.id, nil, nil])
                        for i in 0..<(trigger - 2) {
                            e.board.piles[0].cards.append(DeckManager.toCard(IV.spec(100 + i, 3), data: data))
                        }
                        return e
                    },
                    fire: { $0.guess(0, .higher) },
                    expect: { e, _, c in
                        XCTAssertEqual(e.run.reviveUsed?[0], false, "\(c): nothing to revive, charge kept")
                    }),
                IV.Scenario("mustNotFire-belowTrigger", allowed: .all,
                    build: { IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), nil],
                                       deckOrder: [IV.spec(50, 9), IV.spec(59, 2)],
                                       pillars: [def.id, nil, nil]) },
                    fire: { e in
                        var offered = false
                        e.on { if case .reviveOffer = $0 { offered = true } }
                        e.guess(0, .higher)
                        XCTAssertFalse(offered, "revive/mustNotFire: no offer below \(trigger)")
                    },
                    expect: { e, _, c in XCTAssertEqual(e.run.reviveUsed?[0], false, "\(c)") }),
            ]

        case "heavyDiamond":
            let unit = def.int("value", 1)
            return [
                IV.Scenario("trigger-diamondsWeigh", allowed: [],
                    build: {
                        let e = IV.engine(tops: [IV.spec(1, 5, "♦"), IV.spec(2, 6), IV.spec(3, 6)],
                                          deckOrder: [IV.spec(50, 9)], pillars: [def.id, nil, nil])
                        e.board.piles[0].cards.append(DeckManager.toCard(IV.spec(90, 7, "♦"), data: data))
                        return e
                    },
                    fire: { _ in },
                    expect: { e, _, c in
                        XCTAssertEqual(e.board.pileSize(0), 2 + 2 * unit, "\(c): 2 cards + 2 ♦ x \(unit)")
                    }),
                IV.Scenario("edge-otherColumnUnweighted", allowed: [],
                    build: { IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6, "♦"), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 9)], pillars: [def.id, nil, nil]) },
                    fire: { _ in },
                    expect: { e, _, c in
                        XCTAssertEqual(e.board.pileSize(1), 1, "\(c): the pillar is column-scoped")
                    }),
                IV.Scenario("mustNotFire-noDiamonds", allowed: [],
                    build: { IV.engine(tops: [IV.spec(1, 5, "♣"), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 9)], pillars: [def.id, nil, nil]) },
                    fire: { _ in },
                    expect: { e, _, c in XCTAssertEqual(e.board.pileSize(0), 1, "\(c)") }),
            ]

        case "diamondAnchor":
            return [
                IV.Scenario("trigger-diamondTopAnchors", allowed: [],
                    build: { IV.engine(tops: [IV.spec(1, 5, "♦"), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 9)], pillars: [def.id, nil, nil]) },
                    fire: { _ in },
                    expect: { e, _, c in XCTAssertTrue(e.board.isAnchored(0), "\(c)") }),
                IV.Scenario("edge-coveringLifts", allowed: [.guesses, .deck, .board],
                    build: { IV.engine(tops: [IV.spec(1, 5, "♦"), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 9, "♣"), IV.spec(59, 2)],
                                       pillars: [def.id, nil, nil]) },
                    fire: { $0.guess(0, .higher) },
                    expect: { e, _, c in XCTAssertFalse(e.board.isAnchored(0), "\(c): a ♣ top un-anchors") }),
                IV.Scenario("mustNotFire-offSuitTop", allowed: [],
                    build: { IV.engine(tops: [IV.spec(1, 5, "♠"), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 9)], pillars: [def.id, nil, nil]) },
                    fire: { _ in },
                    expect: { e, _, c in XCTAssertFalse(e.board.isAnchored(0), "\(c)") }),
            ]

        case "ditto":
            return [
                IV.Scenario("trigger-mirrorsCenter", allowed: [],
                    build: { IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 9)],
                                       pillars: [def.id, "prime", nil]) },
                    fire: { _ in },
                    expect: { e, _, c in
                        XCTAssertEqual(e.resolvePillarDef(0)?.id, "prime",
                                       "\(c): Ditto reads as the center's pillar")
                    }),
                IV.Scenario("edge-centerEmptyIsNothing", allowed: [],
                    build: { IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 9)],
                                       pillars: [def.id, nil, nil]) },
                    fire: { _ in },
                    expect: { e, _, c in XCTAssertNil(e.resolvePillarDef(0), "\(c)") }),
                IV.Scenario("mustNotFire-dittoInCenter", allowed: [],
                    build: { IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 9)],
                                       pillars: [nil, def.id, nil]) },
                    fire: { _ in },
                    expect: { e, _, c in XCTAssertNil(e.resolvePillarDef(1), "\(c): center Ditto is nothing") }),
            ]

        case "columnPiles":
            // Fourth Seat: LAYOUT-level — its column gains a pile.
            return [
                IV.Scenario("trigger-widensItsColumn", allowed: [],
                    build: { IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 9)]) },
                    fire: { _ in },
                    expect: { _, _, c in
                        let layout = CampaignLayout.layoutForPiles(9, pillars: [def.id, nil, nil])
                        XCTAssertEqual(layout.cols[0], 4, "\(c): its column holds 4 piles")
                        XCTAssertEqual(layout.piles, 10, "\(c): the board grew by one")
                    }),
                IV.Scenario("edge-noPillarNoWiden", allowed: [],
                    build: { IV.engine(tops: [IV.spec(1, 5)], deckOrder: [IV.spec(50, 9)]) },
                    fire: { _ in },
                    expect: { _, _, c in
                        let layout = CampaignLayout.layoutForPiles(9, pillars: [nil, nil, nil])
                        XCTAssertEqual(layout.piles, 9, "\(c)")
                    }),
                IV.Scenario("mustNotFire-otherColumnsUntouched", allowed: [],
                    build: { IV.engine(tops: [IV.spec(1, 5)], deckOrder: [IV.spec(50, 9)]) },
                    fire: { _ in },
                    expect: { _, _, c in
                        let layout = CampaignLayout.layoutForPiles(9, pillars: [def.id, nil, nil])
                        XCTAssertEqual(layout.cols[1], 3, "\(c)")
                        XCTAssertEqual(layout.cols[2], 3, "\(c)")
                    }),
            ]

        // ── scoring pillars (payout at deal end) ────────────────────────────
        case "columnAllAlive", "columnNoneAlive", "allSuitTop", "heartPiles",
             "greedy", "highestHeart", "insurance", "excavator", "gambler":
            return scoringScenarios(def)

        // ── v6.76 archetype batch ─────────────────────────────────────────
        case "sameTolerance":            return sameToleranceScenarios(def)
        case "royalSafeNoTwos":          return royalSanctuaryScenarios(def)
        case "rankShield":               return rankShieldScenarios(def)
        case "suitShieldDaily":          return dailySuitScenarios(def)
        case "suitMajoritySafe":         return suitMajorityScenarios(def)
        case "absentSuitClubBury":       return absentSuitScenarios(def)
        case "clubZeroRanksBury":        return zeroRanksScenarios(def)
        case "startPileSizeEight":       return eightStartScenarios(def)
        case "diamondDupeSize":          return diamondDupeScenarios(def)
        case "eightPeek":                return eightPeekScenarios(def)
        case "pauperHeartPeek":          return pauperHeartPeekScenarios(def)
        case "stickerCurseWard":         return curseWardScenarios(def)
        case "finalPilePurge":           return finalCutScenarios(def)
        case "heartZeroRanksCoin":       return zeroRanksCoinScenarios(def)
        case "diamondZeroRanksSize":     return zeroRanksSizeScenarios(def)
        case "pauperDiamondSize":        return pauperDiamondScenarios(def)
        case "pauperSpadeTell":          return pauperSpadeScenarios(def)
        case "pauperClubBury":           return pauperClubScenarios(def)
        case "curseBuryPeek":            return curseHarvestScenarios(def)
        case "clubThin":                 return clubThinScenarios(def)
        case "sizeOneDiamonds":          return sizeOneDiamondsScenarios(def)
        // purgeFlatFive (purgeHalve) / firstFree / purgeRank run their
        // CampaignCheck.

        // ── campaign/store pillars (validated in the campaign checks) ───────
        case "freebie", "purgeStepDiscount", "rareHunter", "twoWard", "queenFinder":
            return []   // driver runs their CampaignCheck instead

        default:
            return nil
        }
    }

    /// Scoring pillar scenarios: build the END board, read computePillarPayout.
    static func scoringScenarios(_ def: ItemDef) -> [IV.Scenario] {
        let v = def.value
        func payoutLine(_ e: GameEngine) -> PayoutLine? {
            e.computePillarPayout().lines.first { $0.id == def.id || $0.label == def.label }
        }
        switch def.effect {
        case "columnAllAlive":
            return [
                IV.Scenario("trigger-columnSurvived", allowed: [],
                    build: { IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 9)],
                                       pillars: [def.id, nil, nil]) },
                    fire: { _ in },
                    expect: { e, _, c in
                        XCTAssertEqual(payoutLine(e)?.amount, v, "\(c): +\(v) at the payout")
                    }),
                IV.Scenario("edge-deadPileVoids", allowed: [],
                    build: { IV.engine(tops: [nil, IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 9)],
                                       cols: [2, 1], pillars: [def.id, nil]) },
                    fire: { _ in },
                    expect: { e, _, c in XCTAssertNil(payoutLine(e), "\(c): a death voids it") }),
                IV.Scenario("mustNotFire-noPillar", allowed: [],
                    build: { IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 9)]) },
                    fire: { _ in },
                    expect: { e, _, c in XCTAssertNil(payoutLine(e), "\(c)") }),
            ]
        case "greedy":
            // v6.65: sole-Pillar-only — the column-survival clause is gone, so
            // a dead pile no longer voids it; a second Pillar still does.
            return [
                IV.Scenario("trigger-solePillar", allowed: [],
                    build: { IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 9)],
                                       pillars: [def.id, nil, nil]) },
                    fire: { _ in },
                    expect: { e, _, c in
                        XCTAssertEqual(payoutLine(e)?.amount, v, "\(c): +\(v) at the payout")
                    }),
                IV.Scenario("trigger-deadPileStillPays", allowed: [],
                    build: { IV.engine(tops: [nil, IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 9)],
                                       cols: [2, 1], pillars: [def.id, nil]) },
                    fire: { _ in },
                    expect: { e, _, c in
                        XCTAssertEqual(payoutLine(e)?.amount, v, "\(c): a death no longer voids it")
                    }),
                IV.Scenario("mustNotFire-secondPillarVoids", allowed: [],
                    build: { IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 9)],
                                       pillars: [def.id, "prime", nil]) },
                    fire: { _ in },
                    expect: { e, _, c in XCTAssertNil(payoutLine(e), "\(c): not the sole pillar") }),
            ]
        case "columnNoneAlive":
            return [
                IV.Scenario("trigger-columnWiped", allowed: [],
                    build: { IV.engine(tops: [nil, IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 9)],
                                       pillars: [def.id, nil, nil]) },
                    fire: { _ in },
                    expect: { e, _, c in XCTAssertEqual(payoutLine(e)?.amount, v, "\(c)") }),
                IV.Scenario("edge-survivorVoids", allowed: [],
                    build: { IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 9)],
                                       pillars: [def.id, nil, nil]) },
                    fire: { _ in },
                    expect: { e, _, c in XCTAssertNil(payoutLine(e), "\(c)") }),
                IV.Scenario("mustNotFire-otherColumnWiped", allowed: [],
                    build: { IV.engine(tops: [IV.spec(1, 5), nil, IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 9)],
                                       pillars: [def.id, nil, nil]) },
                    fire: { _ in },
                    expect: { e, _, c in XCTAssertNil(payoutLine(e), "\(c)") }),
            ]
        case "allSuitTop", "heartPiles", "highestHeart", "excavator":
            let suit = def.suit ?? "♥"
            let heartsTop: [CardSpec?] = [IV.spec(1, 5, suit), IV.spec(2, 6, "♣"), IV.spec(3, 6)]
            return [
                IV.Scenario("trigger", allowed: [],
                    build: {
                        let e = IV.engine(tops: heartsTop, deckOrder: [IV.spec(50, 9)],
                                          pillars: [def.id, nil, nil])
                        if def.effect == "excavator" {
                            e.board.piles[0].cards.insert(DeckManager.toCard(IV.spec(90, 3), data: data), at: 0)
                            e.board.piles[0].cards.insert(DeckManager.toCard(IV.spec(91, 4), data: data), at: 0)
                        }
                        return e
                    },
                    fire: { _ in },
                    expect: { e, _, c in
                        guard let line = payoutLine(e) else { return XCTFail("\(c): no payout line") }
                        switch def.effect {
                        case "allSuitTop":  XCTAssertEqual(line.amount, v, "\(c)")
                        case "heartPiles":  XCTAssertEqual(line.amount, v * 1, "\(c): one ♥ top")
                        case "highestHeart": XCTAssertEqual(line.amount, 5, "\(c): the ♥ 5 pays face")
                        case "excavator":
                            let unit = def.num("value", 1) == 0 ? 1 : v
                            XCTAssertEqual(line.amount, 2 * unit, "\(c): 2 buried under the ♥ pile")
                        default: break
                        }
                    }),
                IV.Scenario("edge-royalOrEmpty", allowed: [],
                    build: { IV.engine(tops: [IV.spec(1, 12, suit), IV.spec(2, 6, "♣"), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 9)],
                                       pillars: [def.id, nil, nil]) },
                    fire: { _ in },
                    expect: { e, _, c in
                        switch def.effect {
                        case "highestHeart": XCTAssertNil(payoutLine(e), "\(c): royals pay 0")
                        case "excavator":    XCTAssertNil(payoutLine(e), "\(c): nothing buried")
                        case "allSuitTop":   XCTAssertNotNil(payoutLine(e), "\(c): a royal still tops")
                        case "heartPiles":   XCTAssertNotNil(payoutLine(e), "\(c)")
                        default: break
                        }
                    }),
                IV.Scenario("mustNotFire-noSuitTops", allowed: [],
                    build: { IV.engine(tops: [IV.spec(1, 5, "♣"), IV.spec(2, 6, "♣"), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 9)],
                                       pillars: [def.id, nil, nil]) },
                    fire: { _ in },
                    expect: { e, _, c in XCTAssertNil(payoutLine(e), "\(c)") }),
            ]
        case "insurance":
            return [
                IV.Scenario("trigger-soleSurvivorHere", allowed: [],
                    build: { IV.engine(tops: [IV.spec(1, 5), nil, nil],
                                       deckOrder: [IV.spec(50, 9)],
                                       pillars: [def.id, nil, nil]) },
                    fire: { _ in },
                    expect: { e, _, c in XCTAssertEqual(payoutLine(e)?.amount, v, "\(c)") }),
                IV.Scenario("edge-twoSurvivorsVoid", allowed: [],
                    build: { IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), nil],
                                       deckOrder: [IV.spec(50, 9)],
                                       pillars: [def.id, nil, nil]) },
                    fire: { _ in },
                    expect: { e, _, c in XCTAssertNil(payoutLine(e), "\(c)") }),
                IV.Scenario("trigger-survivorElsewhere", allowed: [],
                    build: { IV.engine(tops: [nil, IV.spec(2, 6), nil],
                                       deckOrder: [IV.spec(50, 9)],
                                       pillars: [def.id, nil, nil]) },
                    fire: { _ in },
                    expect: { e, _, c in
                        // v6.65: board-wide — the sole survivor can be anywhere.
                        XCTAssertEqual(payoutLine(e)?.amount, v, "\(c): the survivor's column no longer matters")
                    }),
            ]
        case "gambler":
            return [
                IV.Scenario("trigger-flipAlwaysReports", allowed: .all,
                    build: { IV.engine(tops: [IV.spec(1, 5, "♥"), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 9)],
                                       pillars: [def.id, nil, nil]) },
                    fire: { _ in },
                    expect: { e, _, c in
                        guard let line = payoutLine(e) else { return XCTFail("\(c): the flip must show") }
                        XCTAssertTrue(line.amount == v || line.amount == 0, "\(c): all or nothing")
                    }),
                IV.Scenario("edge-noHeartStillFlips", allowed: .all,
                    build: { IV.engine(tops: [IV.spec(1, 5, "♣"), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 9)],
                                       pillars: [def.id, nil, nil]) },
                    fire: { _ in },
                    expect: { e, _, c in
                        // v6.57: the ♥-top requirement is gone — the flip runs
                        // with ANY top, so the line shows and pays 0 or value.
                        guard let line = payoutLine(e) else { return XCTFail("\(c): the flip must show") }
                        XCTAssertTrue(line.amount == v || line.amount == 0, "\(c): all or nothing, no ♥ needed")
                    }),
                IV.Scenario("mustNotFire-noPillar", allowed: [],
                    build: { IV.engine(tops: [IV.spec(1, 5, "♥"), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 9)]) },
                    fire: { _ in },
                    expect: { e, _, c in XCTAssertNil(payoutLine(e), "\(c)") }),
            ]
        default:
            return []
        }
    }

    // MARK: - v6.76 archetype batch scenario builders

    /// SAME-TOLERANCE family (R1): a Same call that would be WRONG SURVIVES,
    /// counting as a FULL correct Same — Same Shield charged, Same-Power
    /// fired, guess counted correct. One builder per `tol` rule.
    static func sameToleranceScenarios(_ def: ItemDef) -> [IV.Scenario] {
        // (top rank/suit, tolerated drawn rank/suit, non-qualifying drawn rank/suit)
        let top: CardSpec
        let tolerated: CardSpec
        let rejected: CardSpec
        switch def.tol {
        case "near":                           // ±1 in value
            top = IV.spec(1, 5, "♠"); tolerated = IV.spec(50, 6, "♥"); rejected = IV.spec(50, 9, "♥")
        case "royalPair":                      // royal on royal
            top = IV.spec(1, 11, "♠"); tolerated = IV.spec(50, 12, "♥"); rejected = IV.spec(50, 12, "♥")
            // (rejected uses a non-royal top below)
        case "sum10":                          // ranks summing to 10
            top = IV.spec(1, 4, "♠"); tolerated = IV.spec(50, 6, "♥"); rejected = IV.spec(50, 9, "♥")
        default:                               // sameSuit (Same Suit Safe)
            top = IV.spec(1, 5, "♠"); tolerated = IV.spec(50, 9, "♠"); rejected = IV.spec(50, 9, "♥")
        }
        let filler = IV.spec(51, 3, "♦")
        let power = data.samePowerTypes.get("linkCoins")!
        let per = power.num("value", 1) == 0 ? 1 : power.value
        let tops = [top, IV.spec(2, 6, "♦"), IV.spec(3, 7, "♣")]
        let trigger = IV.Scenario("trigger-toleratedSameIsFullSame", allowed: [.guesses, .deck, .board, .coins, .charge],
            build: { IV.engine(tops: tops, deckOrder: [tolerated, filler],
                               pillars: [def.id, nil, nil], samePower: power.id) },
            fire: { $0.guess(0, .same) },
            expect: { e, f, c in
                XCTAssertEqual(e.board.top(0)?.id, tolerated.id, "\(c): the tolerated card landed")
                XCTAssertEqual(e.run.correctGuesses, f.correctGuesses + 1, "\(c): it COUNTS as correct")
                XCTAssertTrue(e.sameCharge, "\(c): it charges the Same Shield")
                XCTAssertEqual(e.run.bonusCoins, f.bonusCoins + per * 3,
                               "\(c): it fires the equipped Same-Power (Dividend × 3 alive piles)")
            })
        let rejectedTop: CardSpec = def.tol == "royalPair" ? IV.spec(1, 5, "♠") : top
        let mustNot = IV.Scenario("mustNotFire-outsideTolerance", allowed: [.guesses, .deck, .board, .deaths],
            build: { IV.engine(tops: [rejectedTop, IV.spec(2, 6, "♦"), IV.spec(3, 7, "♣")],
                               deckOrder: [rejected, filler],
                               pillars: [def.id, nil, nil], samePower: power.id) },
            fire: { $0.guess(0, .same) },
            expect: { e, f, c in
                XCTAssertFalse(e.board.isActive(0), "\(c): a Same outside the tolerance still kills")
                XCTAssertFalse(e.sameCharge, "\(c)")
                XCTAssertEqual(e.run.bonusCoins, f.bonusCoins, "\(c): no power fired")
            })
        let edge: IV.Scenario
        if def.tol == "sameSuit" {
            // Same Suit Safe shields ANY call on a same-suit landing — a
            // wrong DIRECTIONAL call survives too (and banks no charge).
            edge = IV.Scenario("edge-directionalSameSuitSurvives", allowed: [.guesses, .deck, .board],
                build: { IV.engine(tops: [IV.spec(1, 5, "♠"), IV.spec(2, 6, "♦"), IV.spec(3, 7, "♣")],
                                   deckOrder: [IV.spec(50, 3, "♠"), filler],
                                   pillars: [def.id, nil, nil]) },
                fire: { $0.guess(0, .higher) },     // 3 on 5 called higher: wrong…
                expect: { e, f, c in
                    XCTAssertEqual(e.board.top(0)?.id, 50, "\(c): …but the same-suit landing is safe")
                    XCTAssertFalse(e.sameCharge, "\(c): only a SAME call banks the charge")
                    XCTAssertEqual(e.run.correctGuesses, f.correctGuesses + 1, "\(c)")
                })
        } else {
            // No Same-Power equipped: the tolerance still charges the shield.
            edge = IV.Scenario("edge-noPowerStillCharges", allowed: [.guesses, .deck, .board, .charge],
                build: { IV.engine(tops: tops, deckOrder: [tolerated, filler],
                                   pillars: [def.id, nil, nil]) },
                fire: { $0.guess(0, .same) },
                expect: { e, f, c in
                    XCTAssertTrue(e.sameCharge, "\(c)")
                    XCTAssertEqual(e.run.bonusCoins, f.bonusCoins, "\(c): no power to fire")
                })
        }
        return [trigger, edge, mustNot]
    }

    /// ROYAL SANCTUARY: no 2s in the full deck → royals landing here are safe.
    static func royalSanctuaryScenarios(_ def: ItemDef) -> [IV.Scenario] {
        let trigger = IV.Scenario("trigger-royalSafeWithoutTwos", allowed: [.guesses, .deck, .board],
            build: { IV.engine(tops: [IV.spec(1, 5, "♠"), IV.spec(2, 6, "♥"), IV.spec(3, 6, "♣")],
                               deckOrder: [IV.spec(50, 11, "♥"), IV.spec(51, 3, "♦")],
                               pillars: [def.id, nil, nil]) },
            fire: { $0.guess(0, .lower) },          // J(11) on 5 called lower: wrong
            expect: { e, f, c in
                XCTAssertEqual(e.board.top(0)?.id, 50, "\(c): the royal landing survived")
                XCTAssertEqual(e.run.correctGuesses, f.correctGuesses + 1, "\(c)")
            })
        let edge = IV.Scenario("edge-aTwoAnywhereClosesIt", allowed: [.guesses, .deck, .board, .deaths],
            build: { IV.engine(tops: [IV.spec(1, 5, "♠"), IV.spec(2, 6, "♥"), IV.spec(3, 2, "♣")],
                               deckOrder: [IV.spec(50, 11, "♥"), IV.spec(51, 3, "♦")],
                               pillars: [def.id, nil, nil]) },
            fire: { $0.guess(0, .lower) },
            expect: { e, _, c in
                XCTAssertFalse(e.board.isActive(0), "\(c): a single 2 in the FULL deck voids the sanctuary")
            })
        let mustNot = IV.Scenario("mustNotFire-commonerLanding", allowed: [.guesses, .deck, .board, .deaths],
            build: { IV.engine(tops: [IV.spec(1, 5, "♠"), IV.spec(2, 6, "♥"), IV.spec(3, 6, "♣")],
                               deckOrder: [IV.spec(50, 9, "♥"), IV.spec(51, 3, "♦")],
                               pillars: [def.id, nil, nil]) },
            fire: { $0.guess(0, .lower) },
            expect: { e, _, c in XCTAssertFalse(e.board.isActive(0), "\(c): a 9 is no royal") })
        return [trigger, edge, mustNot]
    }

    /// RANK SHIELD (dynamic, v6.78): the FULL deck's most common rank —
    /// picked at Start Run, no shop roll — landing here is always safe.
    /// The decks below make 9 the strict leader (two copies, everything
    /// else one), so the pick is deterministic without an incumbent.
    static func rankShieldScenarios(_ def: ItemDef) -> [IV.Scenario] {
        let trigger = IV.Scenario("trigger-mostCommonRankSafe", allowed: [.guesses, .deck, .board],
            build: { IV.engine(tops: [IV.spec(1, 5, "♠"), IV.spec(2, 6, "♥"), IV.spec(3, 7, "♣")],
                               deckOrder: [IV.spec(50, 9, "♥"), IV.spec(51, 9, "♦"), IV.spec(52, 3, "♦")],
                               pillars: [def.id, nil, nil]) },
            fire: { $0.guess(0, .lower) },          // 9 on 5 called lower: wrong
            expect: { e, f, c in
                XCTAssertEqual(e.run.shopRolls[def.id]?.rank, 9, "\(c): 9 leads the full deck")
                XCTAssertEqual(e.board.top(0)?.id, 50, "\(c): the shielded rank survived")
                XCTAssertEqual(e.run.correctGuesses, f.correctGuesses + 1, "\(c)")
            })
        let edge = IV.Scenario("edge-otherColumnDies", allowed: [.guesses, .deck, .board, .deaths],
            build: { IV.engine(tops: [IV.spec(1, 5, "♠"), IV.spec(2, 6, "♥"), IV.spec(3, 7, "♣")],
                               deckOrder: [IV.spec(50, 9, "♥"), IV.spec(51, 9, "♦"), IV.spec(52, 3, "♦")],
                               pillars: [nil, def.id, nil]) },
            fire: { $0.guess(0, .lower) },
            expect: { e, _, c in XCTAssertFalse(e.board.isActive(0), "\(c): the shield is column-scoped") })
        let mustNot = IV.Scenario("mustNotFire-otherRank", allowed: [.guesses, .deck, .board, .deaths],
            build: { IV.engine(tops: [IV.spec(1, 5, "♠"), IV.spec(2, 6, "♥"), IV.spec(3, 7, "♣")],
                               deckOrder: [IV.spec(50, 8, "♥"), IV.spec(51, 9, "♦"), IV.spec(52, 9, "♣")],
                               pillars: [def.id, nil, nil]) },
            fire: { $0.guess(0, .lower) },
            expect: { e, _, c in XCTAssertFalse(e.board.isActive(0), "\(c): a non-leading rank is unshielded") })
        return [trigger, edge, mustNot]
    }

    /// DAILY SUIT: the shielded suit rolls at Start Run; the scenarios recraft
    /// the next draw to (not) match the REAL roll after the build.
    static func dailySuitScenarios(_ def: ItemDef) -> [IV.Scenario] {
        func built(match: Bool, pillar: Bool = true) -> () -> GameEngine {
            return {
                let e = IV.engine(tops: [IV.spec(1, 5, "♠"), IV.spec(2, 6, "♥"), IV.spec(3, 6, "♣")],
                                  deckOrder: [IV.spec(50, 9, "♠"), IV.spec(51, 3, "♥")],
                                  pillars: pillar ? [def.id, nil, nil] : [nil, nil, nil])
                let rolled = e.run.dailySuits?[0] ?? "♠"
                let suit = match ? rolled : (DeckManager.suits.first { $0.symbol != rolled }?.symbol ?? "♥")
                var cards = e.deck.snapshotCards()
                cards[0] = DeckManager.toCard(IV.spec(50, 9, suit), data: GameData.shared)
                e.deck.restoreSnapshot(cards: cards, drawn: e.deck.drawn())
                return e
            }
        }
        let trigger = IV.Scenario("trigger-rolledSuitSafe", allowed: [.guesses, .deck, .board],
            build: built(match: true),
            fire: { $0.guess(0, .lower) },          // 9 on 5 called lower: wrong
            expect: { e, f, c in
                XCTAssertNotNil(e.run.dailySuits?[0], "\(c): the suit rolled at Start Run")
                XCTAssertEqual(e.board.top(0)?.id, 50, "\(c): the rolled suit's landing survived")
                XCTAssertEqual(e.run.correctGuesses, f.correctGuesses + 1, "\(c)")
            })
        let edge = IV.Scenario("edge-otherSuitDies", allowed: [.guesses, .deck, .board, .deaths],
            build: built(match: false),
            fire: { $0.guess(0, .lower) },
            expect: { e, _, c in XCTAssertFalse(e.board.isActive(0), "\(c): only the rolled suit is safe") })
        let mustNot = IV.Scenario("mustNotFire-noPillar", allowed: [.guesses, .deck, .board, .deaths],
            build: built(match: true, pillar: false),
            fire: { $0.guess(0, .lower) },
            expect: { e, _, c in XCTAssertFalse(e.board.isActive(0), "\(c)") })
        return [trigger, edge, mustNot]
    }

    /// MAJORITY RULE: ≥50% of the full deck is the rolled suit → that suit's
    /// landings here are safe.
    static func suitMajorityScenarios(_ def: ItemDef) -> [IV.Scenario] {
        let rolls: [String: ShopRoll] = [def.id: ShopRoll(suit: "♥")]
        // WEB-EXACT counting (v6.78): the ratio runs over the RANKED cards
        // the full deck holds at the check — board tops + the deck still to
        // come — with no in-flight adjustment (the drawn card has left the
        // deck and not landed) and jokers/blanks outside both sides.
        let trigger = IV.Scenario("trigger-majoritySuitSafe", allowed: [.guesses, .deck, .board],
            build: { IV.engine(tops: [IV.spec(1, 5, "♥"), IV.spec(2, 6, "♥"), IV.spec(3, 6, "♠")],
                               deckOrder: [IV.spec(50, 9, "♥"), IV.spec(51, 3, "♥"), IV.spec(52, 4, "♠")],
                               pillars: [def.id, nil, nil], shopRolls: rolls) },
            fire: { $0.guess(0, .lower) },          // 9 on 5 called lower: wrong
            expect: { e, f, c in
                XCTAssertEqual(e.board.top(0)?.id, 50, "\(c): 3 of 5 ♥ at the check → safe")
                XCTAssertEqual(e.run.correctGuesses, f.correctGuesses + 1, "\(c)")
            })
        let edge = IV.Scenario("edge-exactlyHalfIsSafe", allowed: [.guesses, .deck, .board],
            build: { IV.engine(tops: [IV.spec(1, 5, "♥"), IV.spec(2, 6, "♥"), IV.spec(3, 6, "♠")],
                               deckOrder: [IV.spec(50, 9, "♥"), IV.spec(51, 3, "♥"), IV.spec(52, 4, "♠"),
                                           IV.spec(53, 7, "♣")],
                               pillars: [def.id, nil, nil], shopRolls: rolls) },
            fire: { $0.guess(0, .lower) },
            expect: { e, _, c in XCTAssertEqual(e.board.top(0)?.id, 50, "\(c): 3 of 6 ♥ at the check — ≥50% is inclusive") })
        let mustNot = IV.Scenario("mustNotFire-minority", allowed: [.guesses, .deck, .board, .deaths],
            build: { IV.engine(tops: [IV.spec(1, 5, "♠"), IV.spec(2, 6, "♠"), IV.spec(3, 6, "♣")],
                               deckOrder: [IV.spec(50, 9, "♥"), IV.spec(51, 3, "♠"), IV.spec(52, 4, "♣")],
                               pillars: [def.id, nil, nil], shopRolls: rolls) },
            fire: { $0.guess(0, .lower) },
            expect: { e, _, c in XCTAssertFalse(e.board.isActive(0), "\(c): 1 of 6 ♥ is no majority") })
        return [trigger, edge, mustNot]
    }

    /// VOID TRIBUTE: no rolled-suit card in the full deck → a ♣ landing buries
    /// buryCount under the pile.
    static func absentSuitScenarios(_ def: ItemDef) -> [IV.Scenario] {
        let bury = def.int("buryCount", 2)
        let rolls: [String: ShopRoll] = [def.id: ShopRoll(suit: "♦")]
        let trigger = IV.Scenario("trigger-absentSuitBuries", allowed: [.guesses, .deck, .board],
            build: { IV.engine(tops: [IV.spec(1, 5, "♠"), IV.spec(2, 6, "♥"), IV.spec(3, 6, "♠")],
                               deckOrder: [IV.spec(50, 7, "♣"), IV.spec(51, 3, "♥"), IV.spec(52, 9, "♠")],
                               pillars: [def.id, nil, nil], shopRolls: rolls) },
            fire: { $0.guess(0, .higher) },
            expect: { e, f, c in
                XCTAssertEqual(e.deck.remaining(), f.deckRemaining - 1 - bury,
                               "\(c): a ♣ landing buried \(bury) with no ♦ anywhere")
                XCTAssertEqual(e.board.piles[0].cards.count, f.pileCounts[0] + 1 + bury, "\(c)")
            })
        let edge = IV.Scenario("edge-suitPresentStays", allowed: [.guesses, .deck, .board],
            build: { IV.engine(tops: [IV.spec(1, 5, "♠"), IV.spec(2, 6, "♥"), IV.spec(3, 6, "♠")],
                               deckOrder: [IV.spec(50, 7, "♣"), IV.spec(51, 3, "♦"), IV.spec(52, 9, "♠")],
                               pillars: [def.id, nil, nil], shopRolls: rolls) },
            fire: { $0.guess(0, .higher) },
            expect: { e, f, c in
                XCTAssertEqual(e.deck.remaining(), f.deckRemaining - 1, "\(c): one ♦ in the deck voids it")
            })
        let mustNot = IV.Scenario("mustNotFire-nonClub", allowed: [.guesses, .deck, .board],
            build: { IV.engine(tops: [IV.spec(1, 5, "♠"), IV.spec(2, 6, "♥"), IV.spec(3, 6, "♠")],
                               deckOrder: [IV.spec(50, 7, "♥"), IV.spec(51, 3, "♥"), IV.spec(52, 9, "♠")],
                               pillars: [def.id, nil, nil], shopRolls: rolls) },
            fire: { $0.guess(0, .higher) },
            expect: { e, f, c in
                XCTAssertEqual(e.deck.remaining(), f.deckRemaining - 1, "\(c): only a ♣ landing buries")
            })
        return [trigger, edge, mustNot]
    }

    /// EMPTY RANKS: a ♣ landing buries 1 per rank with zero full-deck copies.
    static func zeroRanksScenarios(_ def: ItemDef) -> [IV.Scenario] {
        let tops = [IV.spec(1, 5, "♠"), IV.spec(2, 6, "♥"), IV.spec(3, 7, "♣")]
        // Ranks present: 5–14 → the empty ranks are 2, 3, 4.
        let fillers = [9, 10, 11, 12, 13, 14, 14, 13, 12, 11].enumerated().map {
            IV.spec(51 + $0.offset, $0.element, "♥")
        }
        let trigger = IV.Scenario("trigger-buriesPerEmptyRank", allowed: [.guesses, .deck, .board],
            build: { IV.engine(tops: tops, deckOrder: [IV.spec(50, 8, "♣")] + fillers,
                               pillars: [def.id, nil, nil]) },
            fire: { $0.guess(0, .higher) },
            expect: { e, f, c in
                let empties = (minRank...maxRank).filter { r in
                    !(tops + [IV.spec(50, 8, "♣")] + fillers).contains { $0.currentRank == r }
                }.count
                XCTAssertEqual(empties, 3, "\(c): the constructed deck has exactly 3 empty ranks")
                XCTAssertEqual(e.deck.remaining(), f.deckRemaining - 1 - empties,
                               "\(c): buried 1 per empty rank")
                XCTAssertEqual(e.board.piles[0].cards.count, f.pileCounts[0] + 1 + empties, "\(c)")
            })
        let allTops = [IV.spec(1, 2, "♠"), IV.spec(2, 3, "♥"), IV.spec(3, 4, "♣")]
        let allFill = [5, 6, 7, 8, 9, 10, 11, 12, 13, 14].enumerated().map {
            IV.spec(51 + $0.offset, $0.element, "♥")
        }
        let edge = IV.Scenario("edge-noEmptyRanks", allowed: [.guesses, .deck, .board],
            build: { IV.engine(tops: allTops, deckOrder: [IV.spec(50, 5, "♣")] + allFill,
                               pillars: [def.id, nil, nil]) },
            fire: { $0.guess(0, .higher) },
            expect: { e, f, c in
                XCTAssertEqual(e.deck.remaining(), f.deckRemaining - 1,
                               "\(c): every rank present → nothing buried")
            })
        let mustNot = IV.Scenario("mustNotFire-nonClub", allowed: [.guesses, .deck, .board],
            build: { IV.engine(tops: tops, deckOrder: [IV.spec(50, 8, "♥")] + fillers,
                               pillars: [def.id, nil, nil]) },
            fire: { $0.guess(0, .higher) },
            expect: { e, f, c in
                XCTAssertEqual(e.deck.remaining(), f.deckRemaining - 1, "\(c): only ♣ lands trigger it")
            })
        return [trigger, edge, mustNot]
    }

    /// EMPTY RANKS COINS (v6.87): the family's coin leg — the SAME derived
    /// condition as the bury leg (ranks at zero copies), its OWN effect key
    /// and observable: coins, never a bury (the deck assert pins that).
    static func zeroRanksCoinScenarios(_ def: ItemDef) -> [IV.Scenario] {
        let v = def.num("value", 2)
        let tops = [IV.spec(1, 5, "♠"), IV.spec(2, 6, "♥"), IV.spec(3, 7, "♣")]
        // Ranks present: 5–14 → the empty ranks are 2, 3, 4.
        let fillers = [9, 10, 11, 12, 13, 14, 14, 13, 12, 11].enumerated().map {
            IV.spec(51 + $0.offset, $0.element, "♥")
        }
        let trigger = IV.Scenario("trigger-coinsPerEmptyRank", allowed: [.guesses, .deck, .board, .coins],
            build: { IV.engine(tops: tops, deckOrder: [IV.spec(50, 8, "♥")] + fillers,
                               pillars: [def.id, nil, nil]) },
            fire: { $0.guess(0, .higher) },
            expect: { e, f, c in
                XCTAssertEqual(e.run.bonusCoins, f.bonusCoins + v * 3,
                               "\(c): 3 empty ranks → +\(jsNum(v)) each")
                XCTAssertEqual(e.deck.remaining(), f.deckRemaining - 1,
                               "\(c): COINS only — the bury belongs to the family's bury key")
                XCTAssertEqual(e.board.pileSize(0), f.pileCounts[0] + 1,
                               "\(c): …and no size latch either")
            })
        let allTops = [IV.spec(1, 2, "♠"), IV.spec(2, 3, "♥"), IV.spec(3, 4, "♣")]
        let allFill = [5, 6, 7, 8, 9, 10, 11, 12, 13, 14].enumerated().map {
            IV.spec(51 + $0.offset, $0.element, "♥")
        }
        let edge = IV.Scenario("edge-noEmptyRanks", allowed: [.guesses, .deck, .board],
            build: { IV.engine(tops: allTops, deckOrder: [IV.spec(50, 5, "♥")] + allFill,
                               pillars: [def.id, nil, nil]) },
            fire: { $0.guess(0, .higher) },
            expect: { e, f, c in
                XCTAssertEqual(e.run.bonusCoins, f.bonusCoins, "\(c): every rank present → no pay")
            })
        let mustNot = IV.Scenario("mustNotFire-nonHeart", allowed: [.guesses, .deck, .board],
            build: { IV.engine(tops: tops, deckOrder: [IV.spec(50, 8, "♣")] + fillers,
                               pillars: [def.id, nil, nil]) },
            fire: { $0.guess(0, .higher) },
            expect: { e, f, c in
                XCTAssertEqual(e.run.bonusCoins, f.bonusCoins, "\(c): only ♥ lands pay")
            })
        return [trigger, edge, mustNot]
    }

    /// EMPTY RANKS HEAVY (v6.87): the size leg — same condition, its own
    /// key; a latched size bonus, never coins, never a bury.
    static func zeroRanksSizeScenarios(_ def: ItemDef) -> [IV.Scenario] {
        let v = max(1, def.int("value", 1))
        let tops = [IV.spec(1, 5, "♠"), IV.spec(2, 6, "♥"), IV.spec(3, 7, "♣")]
        let fillers = [9, 10, 11, 12, 13, 14, 14, 13, 12, 11].enumerated().map {
            IV.spec(51 + $0.offset, $0.element, "♥")
        }
        let trigger = IV.Scenario("trigger-sizePerEmptyRank", allowed: [.guesses, .deck, .board],
            build: { IV.engine(tops: tops, deckOrder: [IV.spec(50, 8, "♦")] + fillers,
                               pillars: [def.id, nil, nil]) },
            fire: { $0.guess(0, .higher) },
            expect: { e, f, c in
                XCTAssertEqual(e.board.pileSize(0), f.pileCounts[0] + 1 + v * 3,
                               "\(c): 3 empty ranks → +\(v) size each, latched")
                XCTAssertEqual(e.deck.remaining(), f.deckRemaining - 1,
                               "\(c): SIZE only — nothing buried")
                XCTAssertEqual(e.board.piles[0].cards.count, f.pileCounts[0] + 1,
                               "\(c): the physical count is just the landing")
            })
        let allTops = [IV.spec(1, 2, "♠"), IV.spec(2, 3, "♥"), IV.spec(3, 4, "♣")]
        let allFill = [5, 6, 7, 8, 9, 10, 11, 12, 13, 14].enumerated().map {
            IV.spec(51 + $0.offset, $0.element, "♥")
        }
        let edge = IV.Scenario("edge-noEmptyRanks", allowed: [.guesses, .deck, .board],
            build: { IV.engine(tops: allTops, deckOrder: [IV.spec(50, 5, "♦")] + allFill,
                               pillars: [def.id, nil, nil]) },
            fire: { $0.guess(0, .higher) },
            expect: { e, f, c in
                XCTAssertEqual(e.board.pileSize(0), f.pileCounts[0] + 1, "\(c): no empties, no latch")
            })
        let mustNot = IV.Scenario("mustNotFire-nonDiamond", allowed: [.guesses, .deck, .board],
            build: { IV.engine(tops: tops, deckOrder: [IV.spec(50, 8, "♠")] + fillers,
                               pillars: [def.id, nil, nil]) },
            fire: { $0.guess(0, .higher) },
            expect: { e, f, c in
                XCTAssertEqual(e.board.pileSize(0), f.pileCounts[0] + 1, "\(c): only ♦ lands latch")
            })
        return [trigger, edge, mustNot]
    }

    /// CURSE WARD (v6.88): a conditional sticker's missed bet does NOT
    /// convert in this column — the sticker stays and simply didn't fire.
    static func curseWardScenarios(_ def: ItemDef) -> [IV.Scenario] {
        // The Tell carrier's ♠ bet misses on a ♥/♦ board — the canonical
        // conversion setup from ConditionalStickerTests, with the ward.
        let tops = [IV.spec(1, 5, "♠"), IV.spec(2, 6, "♥"), IV.spec(3, 7, "♦")]
        let deck = [IV.spec(50, 3, "♠", ["tell"]), IV.spec(51, 4, "♥")]
        let trigger = IV.Scenario("trigger-missedBetKeepsItsSticker", allowed: [.guesses, .deck, .board],
            build: { IV.engine(tops: tops, deckOrder: deck, pillars: [def.id, nil, nil]) },
            fire: { $0.guess(0, .lower) },
            expect: { e, _, c in
                let top = e.board.top(0)!
                XCTAssertTrue(top.stickers.contains { $0.type == "tell" },
                              "\(c): the sticker STAYED — no conversion in a warded column")
                XCTAssertEqual(top.stickers.count, 1, "\(c): and no curse arrived")
                XCTAssertFalse(e.run.tellPiles.contains(0), "\(c): …but it did NOT fire either")
            })
        let edge = IV.Scenario("edge-fatalConversionWardedToo", allowed: [.guesses, .deck, .board, .deaths],
            build: { IV.engine(tops: [IV.spec(1, 9, "♥"), IV.spec(2, 6, "♦"), IV.spec(3, 6, "♣")],
                               deckOrder: [IV.spec(50, 2, "♠", ["suitImmunity"]), IV.spec(51, 3)],
                               pillars: [def.id, nil, nil]) },
            fire: { $0.guess(0, .higher) },
            expect: { e, _, c in
                XCTAssertFalse(e.board.isActive(0), "\(c): the unfed guard still cannot save")
                let buried = e.board.piles[0].cards.last!
                XCTAssertTrue(buried.stickers.contains { $0.type == "suitImmunity" },
                              "\(c): the fatal-landing conversion is warded too")
            })
        let mustNot = IV.Scenario("mustNotFire-otherColumnStillConverts", allowed: [.guesses, .deck, .board],
            build: { IV.engine(tops: tops, deckOrder: deck, pillars: [nil, def.id, nil]) },
            fire: { $0.guess(0, .lower) },
            expect: { e, _, c in
                let top = e.board.top(0)!
                XCTAssertFalse(top.stickers.contains { $0.type == "tell" },
                               "\(c): the ward guards ITS column only — this one converted")
            })
        return [trigger, edge, mustNot]
    }

    /// FINAL CUT (v6.88): the column's LAST death purges the killer — the
    /// engine reports via .finalCutPurged; the flow commits the removal.
    static func finalCutScenarios(_ def: ItemDef) -> [IV.Scenario] {
        func killer() -> [CardSpec] { [IV.spec(50, 2, "♥"), IV.spec(51, 3)] }
        let trigger = IV.Scenario("trigger-lastDeathReportsThePurge", allowed: [.guesses, .deck, .board, .deaths],
            build: { IV.engine(tops: [IV.spec(1, 9, "♠"), IV.spec(2, 6), IV.spec(3, 6)],
                               deckOrder: killer(), cols: [1, 2],
                               pillars: [def.id, nil]) },
            fire: { e in
                var purged: (col: Int, cardId: Int)?
                e.on { if case .finalCutPurged(let col, let id) = $0 { purged = (col, id) } }
                e.guess(0, .higher)   // 2 on 9: the column's only pile dies
                XCTAssertEqual(purged?.col, 0, "the event names the column")
                XCTAssertEqual(purged?.cardId, 50, "…and the KILLING card")
            },
            expect: { e, _, c in XCTAssertFalse(e.board.isActive(0), "\(c)") })
        let edge = IV.Scenario("edge-columnStillAliveNoPurge", allowed: [.guesses, .deck, .board, .deaths],
            build: { IV.engine(tops: [IV.spec(1, 9, "♠"), IV.spec(2, 6), IV.spec(3, 6)],
                               deckOrder: killer(), cols: [2, 1],
                               pillars: [def.id, nil]) },
            fire: { e in
                var fired = false
                e.on { if case .finalCutPurged = $0 { fired = true } }
                e.guess(0, .higher)   // pile 1 in the same column survives
                XCTAssertFalse(fired, "a column with a survivor purges nothing")
            },
            expect: { e, _, c in XCTAssertFalse(e.board.isActive(0), "\(c)") })
        let mustNot = IV.Scenario("mustNotFire-noPillar", allowed: [.guesses, .deck, .board, .deaths],
            build: { IV.engine(tops: [IV.spec(1, 9, "♠"), IV.spec(2, 6), IV.spec(3, 6)],
                               deckOrder: killer(), cols: [1, 2]) },
            fire: { e in
                var fired = false
                e.on { if case .finalCutPurged = $0 { fired = true } }
                e.guess(0, .higher)
                XCTAssertFalse(fired, "no pillar, no purge")
            },
            expect: { e, _, c in XCTAssertFalse(e.board.isActive(0), "\(c)") })
        return [trigger, edge, mustNot]
    }

    /// CRAZY EIGHTS: 8s the most common full-deck rank (ties → lowest) → this
    /// column's piles START at pile size 8. Built WITHOUT IV.engine's
    /// post-start pile forcing, which would wipe the latched size bonus.
    static func eightStartScenarios(_ def: ItemDef) -> [IV.Scenario] {
        func build(_ specs: [CardSpec], pillar: Bool = true) -> GameEngine {
            let e = GameEngine(deckSpecs: specs, pileCount: 3,
                               runConfig: RunConfig(cols: [1, 1, 1]))
            e.start(seedOverride: 7)
            e.startRun(pillars: pillar ? [def.id, nil, nil] : [nil, nil, nil],
                       bases: [nil, nil, nil], samePower: .some(nil))
            return e
        }
        let leading = [IV.spec(1, 8, "♠"), IV.spec(2, 8, "♥"), IV.spec(3, 8, "♦"),
                       IV.spec(4, 5, "♣"), IV.spec(5, 9, "♠")]
        let trigger = IV.Scenario("trigger-columnOpensAtSize8", allowed: [],
            build: { build(leading) },
            fire: { _ in },
            expect: { e, _, c in
                XCTAssertEqual(e.board.pileSize(0), 8, "\(c): the pillar's column opens at pile SIZE 8")
                XCTAssertEqual(e.board.pileSize(1), 1, "\(c): other columns open normally")
                XCTAssertEqual(e.board.pileSize(2), 1, "\(c)")
            })
        let tied = [IV.spec(1, 8, "♠"), IV.spec(2, 8, "♥"), IV.spec(3, 5, "♣"),
                    IV.spec(4, 5, "♦"), IV.spec(5, 9, "♠")]
        let edge = IV.Scenario("edge-tieBreaksToLowestRank", allowed: [],
            build: { build(tied) },
            fire: { _ in },
            expect: { e, _, c in
                XCTAssertEqual(e.board.pileSize(0), 1,
                               "\(c): 8s tie with 5s → the LOWER rank leads → no Crazy Eights")
            })
        let mustNot = IV.Scenario("mustNotFire-eightsNotLeading", allowed: [],
            build: { build([IV.spec(1, 8, "♠"), IV.spec(2, 5, "♥"), IV.spec(3, 5, "♣"),
                            IV.spec(4, 5, "♦"), IV.spec(5, 9, "♠")]) },
            fire: { _ in },
            expect: { e, _, c in
                XCTAssertEqual(e.board.pileSize(0), 1, "\(c): 5s outnumber the 8s")
            })
        return [trigger, edge, mustNot]
    }

    /// DIAMOND ECHO: a ♦ landing → +1 pile size per duplicate of its rank in
    /// the full deck.
    static func diamondDupeScenarios(_ def: ItemDef) -> [IV.Scenario] {
        let tops = [IV.spec(1, 5, "♠"), IV.spec(2, 6, "♥"), IV.spec(3, 6, "♣")]
        let trigger = IV.Scenario("trigger-sizePerDuplicate", allowed: [.guesses, .deck, .board],
            build: { IV.engine(tops: tops,
                               deckOrder: [IV.spec(50, 7, "♦"), IV.spec(51, 7, "♥"), IV.spec(52, 7, "♠")],
                               pillars: [def.id, nil, nil]) },
            fire: { $0.guess(0, .higher) },
            expect: { e, f, c in
                XCTAssertEqual(e.board.pileSize(0), f.pileCounts[0] + 1 + 2,
                               "\(c): two other 7s in the full deck → +2 pile size")
            })
        let edge = IV.Scenario("edge-noDuplicates", allowed: [.guesses, .deck, .board],
            build: { IV.engine(tops: tops,
                               deckOrder: [IV.spec(50, 7, "♦"), IV.spec(51, 3, "♥"), IV.spec(52, 9, "♠")],
                               pillars: [def.id, nil, nil]) },
            fire: { $0.guess(0, .higher) },
            expect: { e, f, c in
                XCTAssertEqual(e.board.pileSize(0), f.pileCounts[0] + 1, "\(c): the only 7 — no echo")
            })
        let mustNot = IV.Scenario("mustNotFire-nonDiamond", allowed: [.guesses, .deck, .board],
            build: { IV.engine(tops: tops,
                               deckOrder: [IV.spec(50, 7, "♥"), IV.spec(51, 7, "♦"), IV.spec(52, 7, "♠")],
                               pillars: [def.id, nil, nil]) },
            fire: { $0.guess(0, .higher) },
            expect: { e, f, c in
                XCTAssertEqual(e.board.pileSize(0), f.pileCounts[0] + 1, "\(c): only ♦ lands echo")
            })
        return [trigger, edge, mustNot]
    }

    /// EIGHT BALL: an 8 landing here peeks the next card.
    static func eightPeekScenarios(_ def: ItemDef) -> [IV.Scenario] {
        let tops = [IV.spec(1, 5, "♠"), IV.spec(2, 6, "♥"), IV.spec(3, 6, "♣")]
        let trigger = IV.Scenario("trigger-eightPeeks", allowed: [.guesses, .deck, .board],
            build: { IV.engine(tops: tops, deckOrder: [IV.spec(50, 8, "♥"), IV.spec(51, 3, "♦")],
                               pillars: [def.id, nil, nil]) },
            fire: { $0.guess(0, .higher) },
            expect: { e, _, c in
                XCTAssertTrue(e.run.revealNextActive, "\(c): the next card is revealed")
                XCTAssertEqual(e.revealedNextCard()?.id, 51, "\(c): and it is the REAL next draw")
            })
        let edge = IV.Scenario("edge-otherColumn", allowed: [.guesses, .deck, .board],
            build: { IV.engine(tops: tops, deckOrder: [IV.spec(50, 8, "♥"), IV.spec(51, 3, "♦")],
                               pillars: [nil, def.id, nil]) },
            fire: { $0.guess(0, .higher) },
            expect: { e, _, c in XCTAssertFalse(e.run.revealNextActive, "\(c): column-scoped") })
        let mustNot = IV.Scenario("mustNotFire-nonEight", allowed: [.guesses, .deck, .board],
            build: { IV.engine(tops: tops, deckOrder: [IV.spec(50, 9, "♥"), IV.spec(51, 3, "♦")],
                               pillars: [def.id, nil, nil]) },
            fire: { $0.guess(0, .higher) },
            expect: { e, _, c in XCTAssertFalse(e.run.revealNextActive, "\(c)") })
        return [trigger, edge, mustNot]
    }

    /// PAUPER'S HEART (v6.87): while the purse is under purseBelow, a ♥
    /// landing PEEKS the next card — and pays NOTHING (the coin payout
    /// retired with the old `pauperHeart` effect key; the frame check
    /// enforces the no-coins half, `.coins` is deliberately NOT allowed).
    static func pauperHeartPeekScenarios(_ def: ItemDef) -> [IV.Scenario] {
        let ceiling = def.int("purseBelow", 10)
        let tops = [IV.spec(1, 5, "♠"), IV.spec(2, 6, "♥"), IV.spec(3, 6, "♣")]
        let trigger = IV.Scenario("trigger-brokeHeartPeeks", allowed: [.guesses, .deck, .board],
            build: { IV.engine(tops: tops, deckOrder: [IV.spec(50, 7, "♥"), IV.spec(51, 3, "♦")],
                               pillars: [def.id, nil, nil], purse: ceiling - 1) },
            fire: { $0.guess(0, .higher) },
            expect: { e, f, c in
                XCTAssertTrue(e.run.revealNextActive, "\(c): under \(ceiling) coins the ♥ peeks")
                XCTAssertEqual(e.revealedNextCard()?.id, 51, "\(c): the REAL next draw")
                XCTAssertEqual(e.run.bonusCoins, f.bonusCoins, "\(c): a peek, never coins (v6.87)")
            })
        let edge = IV.Scenario("edge-atCeilingSleeps", allowed: [.guesses, .deck, .board],
            build: { IV.engine(tops: tops, deckOrder: [IV.spec(50, 7, "♥"), IV.spec(51, 3, "♦")],
                               pillars: [def.id, nil, nil], purse: ceiling) },
            fire: { $0.guess(0, .higher) },
            expect: { e, _, c in
                XCTAssertFalse(e.run.revealNextActive,
                               "\(c): purseBelow is EXCLUSIVE — at \(ceiling) it sleeps")
            })
        let mustNot = IV.Scenario("mustNotFire-nonHeart", allowed: [.guesses, .deck, .board],
            build: { IV.engine(tops: tops, deckOrder: [IV.spec(50, 7, "♠"), IV.spec(51, 3, "♦")],
                               pillars: [def.id, nil, nil], purse: ceiling - 1) },
            fire: { $0.guess(0, .higher) },
            expect: { e, _, c in XCTAssertFalse(e.run.revealNextActive, "\(c)") })
        return [trigger, edge, mustNot]
    }

    /// PAUPER'S DIAMOND: while broke, a ♦ landing ANYWHERE counts `value`
    /// toward pile size instead of 1.
    static func pauperDiamondScenarios(_ def: ItemDef) -> [IV.Scenario] {
        let ceiling = def.int("purseBelow", 10)
        let value = max(1, def.int("value", 2))
        let tops = [IV.spec(1, 5, "♠"), IV.spec(2, 4, "♥"), IV.spec(3, 6, "♣")]
        let trigger = IV.Scenario("trigger-brokeDiamondCountsMore", allowed: [.guesses, .deck, .board],
            build: { IV.engine(tops: tops, deckOrder: [IV.spec(50, 7, "♦"), IV.spec(51, 3, "♠")],
                               pillars: [def.id, nil, nil], purse: ceiling - 1) },
            fire: { $0.guess(1, .higher) },          // the ♦ lands in ANOTHER column
            expect: { e, f, c in
                XCTAssertEqual(e.board.pileSize(1), f.pileCounts[1] + value,
                               "\(c): the ♦ counts \(value) board-wide, not 1")
            })
        let edge = IV.Scenario("edge-atCeilingCountsOne", allowed: [.guesses, .deck, .board],
            build: { IV.engine(tops: tops, deckOrder: [IV.spec(50, 7, "♦"), IV.spec(51, 3, "♠")],
                               pillars: [def.id, nil, nil], purse: ceiling) },
            fire: { $0.guess(1, .higher) },
            expect: { e, f, c in
                XCTAssertEqual(e.board.pileSize(1), f.pileCounts[1] + 1, "\(c): flush purse → plain +1")
            })
        let mustNot = IV.Scenario("mustNotFire-nonDiamond", allowed: [.guesses, .deck, .board],
            build: { IV.engine(tops: tops, deckOrder: [IV.spec(50, 7, "♠"), IV.spec(51, 3, "♦")],
                               pillars: [def.id, nil, nil], purse: ceiling - 1) },
            fire: { $0.guess(1, .higher) },
            expect: { e, f, c in
                XCTAssertEqual(e.board.pileSize(1), f.pileCounts[1] + 1, "\(c)")
            })
        return [trigger, edge, mustNot]
    }

    /// PAUPER'S SPADE: while broke, a ♠ landing arms a tell on its pile.
    static func pauperSpadeScenarios(_ def: ItemDef) -> [IV.Scenario] {
        let ceiling = def.int("purseBelow", 10)
        let tops = [IV.spec(1, 5, "♠"), IV.spec(2, 6, "♥"), IV.spec(3, 6, "♣")]
        let trigger = IV.Scenario("trigger-brokeSpadeTells", allowed: [.guesses, .deck, .board],
            build: { IV.engine(tops: tops, deckOrder: [IV.spec(50, 7, "♠"), IV.spec(51, 3, "♦")],
                               pillars: [def.id, nil, nil], purse: ceiling - 1) },
            fire: { $0.guess(0, .higher) },
            expect: { e, _, c in
                XCTAssertTrue(e.run.tellPiles.contains(0), "\(c): the tell armed on the landing pile")
                XCTAssertEqual(e.pileHint(0), .lower, "\(c): the next card (3 on 7) reads LOWER")
            })
        let edge = IV.Scenario("edge-atCeilingNoTell", allowed: [.guesses, .deck, .board],
            build: { IV.engine(tops: tops, deckOrder: [IV.spec(50, 7, "♠"), IV.spec(51, 3, "♦")],
                               pillars: [def.id, nil, nil], purse: ceiling) },
            fire: { $0.guess(0, .higher) },
            expect: { e, _, c in XCTAssertNil(e.pileHint(0), "\(c)") })
        let mustNot = IV.Scenario("mustNotFire-nonSpade", allowed: [.guesses, .deck, .board],
            build: { IV.engine(tops: tops, deckOrder: [IV.spec(50, 7, "♥"), IV.spec(51, 3, "♦")],
                               pillars: [def.id, nil, nil], purse: ceiling - 1) },
            fire: { $0.guess(0, .higher) },
            expect: { e, _, c in XCTAssertNil(e.pileHint(0), "\(c)") })
        return [trigger, edge, mustNot]
    }

    /// PAUPER'S CLUB: while broke, a ♣ landing buries digCount.
    static func pauperClubScenarios(_ def: ItemDef) -> [IV.Scenario] {
        let ceiling = def.int("purseBelow", 10)
        let dig = def.int("digCount", 1)
        let tops = [IV.spec(1, 5, "♠"), IV.spec(2, 6, "♥"), IV.spec(3, 6, "♣")]
        let trigger = IV.Scenario("trigger-brokeClubBuries", allowed: [.guesses, .deck, .board],
            build: { IV.engine(tops: tops, deckOrder: [IV.spec(50, 7, "♣"), IV.spec(51, 3, "♦"), IV.spec(52, 9, "♠")],
                               pillars: [def.id, nil, nil], purse: ceiling - 1) },
            fire: { $0.guess(0, .higher) },
            expect: { e, f, c in
                XCTAssertEqual(e.deck.remaining(), f.deckRemaining - 1 - dig, "\(c): buried \(dig)")
            })
        let edge = IV.Scenario("edge-atCeilingNoBury", allowed: [.guesses, .deck, .board],
            build: { IV.engine(tops: tops, deckOrder: [IV.spec(50, 7, "♣"), IV.spec(51, 3, "♦"), IV.spec(52, 9, "♠")],
                               pillars: [def.id, nil, nil], purse: ceiling) },
            fire: { $0.guess(0, .higher) },
            expect: { e, f, c in
                XCTAssertEqual(e.deck.remaining(), f.deckRemaining - 1, "\(c)")
            })
        let mustNot = IV.Scenario("mustNotFire-nonClub", allowed: [.guesses, .deck, .board],
            build: { IV.engine(tops: tops, deckOrder: [IV.spec(50, 7, "♥"), IV.spec(51, 3, "♦"), IV.spec(52, 9, "♠")],
                               pillars: [def.id, nil, nil], purse: ceiling - 1) },
            fire: { $0.guess(0, .higher) },
            expect: { e, f, c in
                XCTAssertEqual(e.deck.remaining(), f.deckRemaining - 1, "\(c)")
            })
        return [trigger, edge, mustNot]
    }

    /// CURSE HARVEST: a cursed card landing here buries digCount, then peeks.
    static func curseHarvestScenarios(_ def: ItemDef) -> [IV.Scenario] {
        let dig = def.int("digCount", 1)
        let tops = [IV.spec(1, 5, "♠"), IV.spec(2, 6, "♥"), IV.spec(3, 6, "♣")]
        let trigger = IV.Scenario("trigger-cursedLandingBuriesAndPeeks", allowed: [.guesses, .deck, .board],
            build: { IV.engine(tops: tops,
                               deckOrder: [IV.spec(50, 7, "♥", ["mute"]), IV.spec(51, 3, "♦"), IV.spec(52, 9, "♠")],
                               pillars: [def.id, nil, nil]) },
            fire: { $0.guess(0, .higher) },
            expect: { e, f, c in
                XCTAssertEqual(e.deck.remaining(), f.deckRemaining - 1 - dig, "\(c): buried \(dig)")
                XCTAssertTrue(e.run.revealNextActive, "\(c): …then peeked the next card")
            })
        let edge = IV.Scenario("edge-otherColumn", allowed: [.guesses, .deck, .board],
            build: { IV.engine(tops: tops,
                               deckOrder: [IV.spec(50, 7, "♥", ["mute"]), IV.spec(51, 3, "♦")],
                               pillars: [nil, def.id, nil]) },
            fire: { $0.guess(0, .higher) },
            expect: { e, f, c in
                XCTAssertEqual(e.deck.remaining(), f.deckRemaining - 1, "\(c): column-scoped")
                XCTAssertFalse(e.run.revealNextActive, "\(c)")
            })
        let mustNot = IV.Scenario("mustNotFire-cleanCard", allowed: [.guesses, .deck, .board],
            build: { IV.engine(tops: tops,
                               deckOrder: [IV.spec(50, 7, "♥"), IV.spec(51, 3, "♦"), IV.spec(52, 9, "♠")],
                               pillars: [def.id, nil, nil]) },
            fire: { $0.guess(0, .higher) },
            expect: { e, f, c in
                XCTAssertEqual(e.deck.remaining(), f.deckRemaining - 1, "\(c): no curse, no harvest")
                XCTAssertFalse(e.run.revealNextActive, "\(c)")
            })
        return [trigger, edge, mustNot]
    }

    /// CLUB THIN: a ♣ landing buries digCount per full `per`-card step of the
    /// REMAINING deck.
    static func clubThinScenarios(_ def: ItemDef) -> [IV.Scenario] {
        let per = max(1, def.int("per", 25))
        let dig = max(1, def.int("digCount", 1))
        let tops = [IV.spec(1, 5, "♠"), IV.spec(2, 6, "♥"), IV.spec(3, 6, "♣")]
        func fillers(_ n: Int) -> [CardSpec] {
            (0..<n).map { IV.spec(60 + $0, minRank + $0 % (maxRank - minRank + 1), "♠") }
        }
        let trigger = IV.Scenario("trigger-buriesPerFullStep", allowed: [.guesses, .deck, .board],
            build: { IV.engine(tops: tops, deckOrder: [IV.spec(50, 7, "♣")] + fillers(per),
                               pillars: [def.id, nil, nil]) },
            fire: { $0.guess(0, .higher) },
            expect: { e, f, c in
                // After the draw, `per` cards remain → exactly dig buried.
                XCTAssertEqual(e.deck.remaining(), f.deckRemaining - 1 - dig,
                               "\(c): \(per) remaining → \(dig) buried")
            })
        let edge = IV.Scenario("edge-belowOneStep", allowed: [.guesses, .deck, .board],
            build: { IV.engine(tops: tops, deckOrder: [IV.spec(50, 7, "♣")] + fillers(per - 1),
                               pillars: [def.id, nil, nil]) },
            fire: { $0.guess(0, .higher) },
            expect: { e, f, c in
                XCTAssertEqual(e.deck.remaining(), f.deckRemaining - 1,
                               "\(c): \(per - 1) remaining is under a step → nothing buried")
            })
        let mustNot = IV.Scenario("mustNotFire-nonClub", allowed: [.guesses, .deck, .board],
            build: { IV.engine(tops: tops, deckOrder: [IV.spec(50, 7, "♥")] + fillers(per),
                               pillars: [def.id, nil, nil]) },
            fire: { $0.guess(0, .higher) },
            expect: { e, f, c in
                XCTAssertEqual(e.deck.remaining(), f.deckRemaining - 1, "\(c)")
            })
        return [trigger, edge, mustNot]
    }

    /// DIAMOND LIFELINE: while any pile in this column is size 1, a ♦ landing
    /// ANYWHERE counts `value` toward pile size instead of 1.
    static func sizeOneDiamondsScenarios(_ def: ItemDef) -> [IV.Scenario] {
        let value = max(1, def.int("value", 2))
        let trigger = IV.Scenario("trigger-sizeOneColumnBoostsDiamonds", allowed: [.guesses, .deck, .board],
            build: { IV.engine(tops: [IV.spec(1, 5, "♠"), IV.spec(2, 6, "♥"), IV.spec(3, 4, "♣")],
                               deckOrder: [IV.spec(50, 7, "♦"), IV.spec(51, 3, "♠")],
                               cols: [2, 1], pillars: [def.id, nil]) },
            fire: { $0.guess(2, .higher) },          // the ♦ lands in the OTHER column
            expect: { e, f, c in
                XCTAssertEqual(e.board.pileSize(2), f.pileCounts[2] + value,
                               "\(c): a size-1 pile in the column → the ♦ counts \(value) board-wide")
            })
        let edge = IV.Scenario("edge-noSizeOneNoBoost", allowed: [.guesses, .deck, .board],
            build: {
                let e = IV.engine(tops: [IV.spec(1, 5, "♠"), IV.spec(2, 6, "♥"), IV.spec(3, 4, "♣")],
                                  deckOrder: [IV.spec(50, 7, "♦"), IV.spec(51, 3, "♠")],
                                  cols: [2, 1], pillars: [def.id, nil])
                // Bulk BOTH column-0 piles past size 1.
                e.board.piles[0].cards.insert(DeckManager.toCard(IV.spec(70, 3), data: data), at: 0)
                e.board.piles[1].cards.insert(DeckManager.toCard(IV.spec(71, 9), data: data), at: 0)
                return e
            },
            fire: { $0.guess(2, .higher) },
            expect: { e, f, c in
                XCTAssertEqual(e.board.pileSize(2), f.pileCounts[2] + 1,
                               "\(c): no size-1 pile here → plain +1")
            })
        let mustNot = IV.Scenario("mustNotFire-nonDiamond", allowed: [.guesses, .deck, .board],
            build: { IV.engine(tops: [IV.spec(1, 5, "♠"), IV.spec(2, 6, "♥"), IV.spec(3, 4, "♣")],
                               deckOrder: [IV.spec(50, 7, "♠"), IV.spec(51, 3, "♦")],
                               cols: [2, 1], pillars: [def.id, nil]) },
            fire: { $0.guess(2, .higher) },
            expect: { e, f, c in
                XCTAssertEqual(e.board.pileSize(2), f.pileCounts[2] + 1, "\(c)")
            })
        return [trigger, edge, mustNot]
    }
}
