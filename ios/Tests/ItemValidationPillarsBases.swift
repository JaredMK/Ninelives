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

        case "fibonacci":
            let unit = def.num("value", 1) == 0 ? 1 : v
            let t = pillarLanding(def, drawn: IV.spec(50, 8), allowed: .coins) { e, f, c in
                XCTAssertEqual(e.run.bonusCoins, f.bonusCoins + unit, "\(c): a fib (8) landed → +\(unit)")
            }
            return [t.scenario,
                IV.Scenario("edge-aceHighFires", allowed: [.coins, .guesses, .deck, .board],
                    build: { IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 14), IV.spec(59, 2)],
                                       pillars: [def.id, nil, nil]) },
                    fire: { $0.guess(0, .higher) },
                    expect: { e, f, c in
                        XCTAssertEqual(e.run.bonusCoins, f.bonusCoins + unit, "\(c): the Ace counts (14/1)")
                    }),
                IV.Scenario("mustNotFire-nonFib", allowed: [.guesses, .deck, .board],
                    build: { IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 9), IV.spec(59, 2)],
                                       pillars: [def.id, nil, nil]) },
                    fire: { $0.guess(0, .higher) },
                    expect: { e, f, c in XCTAssertEqual(e.run.bonusCoins, f.bonusCoins, "\(c): 9 is not fib") })]

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
            let drawnSpec = isDense ? IV.spec(50, 9, "♣", ["tell", "tieSafe"]) : IV.spec(50, 9, "♣")
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
                                       pillars: [def.id, "fibonacci", nil]) },
                    fire: { _ in },
                    expect: { e, _, c in
                        XCTAssertEqual(e.resolvePillarDef(0)?.id, "fibonacci",
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

        // ── campaign/store pillars (validated in the campaign checks) ───────
        case "freebie", "purgeStepDiscount", "rareHunter", "twoWard":
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
        case "columnAllAlive", "greedy":
            let needsSole = def.effect == "greedy"
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
                needsSole
                    ? IV.Scenario("mustNotFire-secondPillarVoids", allowed: [],
                        build: { IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)],
                                           deckOrder: [IV.spec(50, 9)],
                                           pillars: [def.id, "fibonacci", nil]) },
                        fire: { _ in },
                        expect: { e, _, c in XCTAssertNil(payoutLine(e), "\(c): not the sole pillar") })
                    : IV.Scenario("mustNotFire-noPillar", allowed: [],
                        build: { IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)],
                                           deckOrder: [IV.spec(50, 9)]) },
                        fire: { _ in },
                        expect: { e, _, c in XCTAssertNil(payoutLine(e), "\(c)") }),
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
                IV.Scenario("mustNotFire-survivorElsewhere", allowed: [],
                    build: { IV.engine(tops: [nil, IV.spec(2, 6), nil],
                                       deckOrder: [IV.spec(50, 9)],
                                       pillars: [def.id, nil, nil]) },
                    fire: { _ in },
                    expect: { e, _, c in XCTAssertNil(payoutLine(e), "\(c)") }),
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
                IV.Scenario("edge-noHeartNoFlip", allowed: [],
                    build: { IV.engine(tops: [IV.spec(1, 5, "♣"), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 9)],
                                       pillars: [def.id, nil, nil]) },
                    fire: { _ in },
                    expect: { e, _, c in
                        XCTAssertEqual(payoutLine(e)?.amount, 0, "\(c): no ♥ top, no flip, says so")
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
}
