import XCTest
@testable import GameCore

/// TIER 1 scenario generators — STICKERS. One generator per behavior kind,
/// parameterized by the item's OWN knobs (the numbers its help text quotes).
enum IVStickers {

    static let data = GameData.shared

    /// A landing scenario family: `sticker` rides the DRAWN card (or the pile
    /// top when `onTop`), a correct HIGHER guess fires the landing. Returns
    /// trigger + last-card-in-deck edge + must-not-fire (no sticker).
    static func landingFamily(_ def: ItemDef, onTop: Bool = false,
                              topRank: Int = 5, drawnRank: Int = 9,
                              topSuit: String = "♠", drawnSuit: String = "♠",
                              boardTops: [CardSpec?]? = nil,
                              allowed: IV.Allowed,
                              expect: @escaping (GameEngine, IV.Frame, String) -> Void,
                              expectNoFire: @escaping (GameEngine, IV.Frame, String) -> Void,
                              expectEdge: ((GameEngine, IV.Frame, String) -> Void)? = nil)
        -> [IV.Scenario] {
        let sid = def.id
        func tops(_ withSticker: Bool) -> [CardSpec?] {
            var t = boardTops ?? [IV.spec(1, topRank, topSuit), IV.spec(2, 6), IV.spec(3, 6)]
            if onTop, withSticker, let first = t[0] {
                t[0] = IV.spec(first.id, first.currentRank, first.suit, [sid])
            }
            return t
        }
        func drawn(_ withSticker: Bool) -> CardSpec {
            IV.spec(50, drawnRank, drawnSuit, (!onTop && withSticker) ? [sid] : [])
        }
        let fire: (GameEngine) -> Void = { $0.guess(0, .higher) }
        return [
            IV.Scenario("trigger", allowed: allowed.union([.guesses, .deck, .board]),
                        build: { IV.engine(tops: tops(true), deckOrder: [drawn(true), IV.spec(51, 2)]) },
                        fire: fire, expect: expect),
            IV.Scenario("edge-lastCard", allowed: allowed.union([.guesses, .deck, .board]),
                        build: { IV.engine(tops: tops(true), deckOrder: [drawn(true)]) },
                        fire: fire, expect: expectEdge ?? expect, skipSnapshot: true),
            IV.Scenario("mustNotFire", allowed: [.guesses, .deck, .board],
                        build: { IV.engine(tops: tops(false), deckOrder: [drawn(false), IV.spec(51, 2)]) },
                        fire: fire, expect: expectNoFire),
        ]
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    static func scenarios(for def: ItemDef) -> [IV.Scenario]? {
        let v = def.value
        switch def.behavior {

        case "gainCoin":
            return landingFamily(def, allowed: .coins,
                expect: { e, f, c in
                    XCTAssertEqual(e.run.bonusCoins, f.bonusCoins + v, "\(c): +\(v) coins on landing")
                },
                expectNoFire: { e, f, c in
                    XCTAssertEqual(e.run.bonusCoins, f.bonusCoins, "\(c): no sticker, no coins")
                })

        case "extraCoin", "deathBounty", "compound":
            // extraCoin: end-of-deal coin units (board read); deathBounty:
            // pays on pile DEATH; compound: pays per lifetime correct.
            if def.behavior == "extraCoin" {
                return [
                    IV.Scenario("trigger", allowed: [],
                        build: { IV.engine(tops: [IV.spec(1, 5, "♠", ["extraCoin"]), IV.spec(2, 6), IV.spec(3, 6)],
                                           deckOrder: [IV.spec(50, 9)]) },
                        fire: { _ in },
                        expect: { e, _, c in
                            XCTAssertEqual(e.board.extraCoinUnits(), Int(max(1, v)),
                                           "\(c): the board counts its coin units")
                        }),
                    IV.Scenario("edge-deadPileDoesNotCount", allowed: [],
                        build: { IV.engine(tops: [nil, IV.spec(2, 6), IV.spec(3, 6)],
                                           deckOrder: [IV.spec(50, 9, "♠", ["extraCoin"])]) },
                        fire: { _ in },
                        expect: { e, _, c in
                            XCTAssertEqual(e.board.extraCoinUnits(), 0, "\(c): dead piles pay nothing")
                        }),
                    IV.Scenario("mustNotFire", allowed: [],
                        build: { IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)],
                                           deckOrder: [IV.spec(50, 9)]) },
                        fire: { _ in },
                        expect: { e, _, c in XCTAssertEqual(e.board.extraCoinUnits(), 0, "\(c)") }),
                ]
            }
            if def.behavior == "deathBounty" {
                return [
                    IV.Scenario("trigger-onDeath", allowed: [.coins, .guesses, .deck, .board, .deaths],
                        build: { IV.engine(tops: [IV.spec(1, 9), IV.spec(2, 6), IV.spec(3, 6)],
                                           deckOrder: [IV.spec(50, 2, "♠", ["deathBounty"]), IV.spec(51, 3)]) },
                        fire: { $0.guess(0, .higher) },   // 2 < 9: wrong → pile dies
                        expect: { e, f, c in
                            XCTAssertFalse(e.board.isActive(0), "\(c): the pile died")
                            XCTAssertEqual(e.run.bonusCoins, f.bonusCoins + v,
                                           "\(c): the killing card pays its bounty")
                        }),
                    IV.Scenario("edge-safeLandingPaysNothing", allowed: [.guesses, .deck, .board],
                        build: { IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)],
                                           deckOrder: [IV.spec(50, 9, "♠", ["deathBounty"]), IV.spec(51, 3)]) },
                        fire: { $0.guess(0, .higher) },
                        expect: { e, f, c in
                            XCTAssertEqual(e.run.bonusCoins, f.bonusCoins, "\(c): no death, no bounty")
                        }),
                    IV.Scenario("mustNotFire", allowed: [.guesses, .deck, .board, .deaths],
                        build: { IV.engine(tops: [IV.spec(1, 9), IV.spec(2, 6), IV.spec(3, 6)],
                                           deckOrder: [IV.spec(50, 2), IV.spec(51, 3)]) },
                        fire: { $0.guess(0, .higher) },
                        expect: { e, f, c in
                            XCTAssertEqual(e.run.bonusCoins, f.bonusCoins, "\(c): plain death pays nothing")
                        }),
                ]
            }
            // compound
            let step = def.num("step", 1)
            return [
                IV.Scenario("trigger-secondCorrectPays", allowed: [.coins, .guesses, .deck, .board],
                    build: {
                        let e = IV.engine(tops: [IV.spec(1, 5, "♠", ["compound"]), IV.spec(2, 6), IV.spec(3, 6)],
                                          deckOrder: [IV.spec(50, 9), IV.spec(51, 2)])
                        e.board.top(0)!.compoundHits = 1   // one lifetime correct already
                        return e
                    },
                    fire: { $0.guess(0, .higher) },
                    expect: { e, f, c in
                        XCTAssertEqual(e.run.bonusCoins, f.bonusCoins + step,
                                       "\(c): hit #2 pays (hits-1) x step")
                        XCTAssertEqual(e.run.compoundUpdates[1], 2, "\(c): the counter persists")
                    }),
                IV.Scenario("edge-firstHitPaysZero", allowed: [.guesses, .deck, .board],
                    build: { IV.engine(tops: [IV.spec(1, 5, "♠", ["compound"]), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 9), IV.spec(51, 2)]) },
                    fire: { $0.guess(0, .higher) },
                    expect: { e, f, c in
                        XCTAssertEqual(e.run.bonusCoins, f.bonusCoins, "\(c): the first use pays +0")
                    }),
                IV.Scenario("mustNotFire-wrongGuess", allowed: [.guesses, .deck, .board, .deaths],
                    build: { IV.engine(tops: [IV.spec(1, 5, "♠", ["compound"]), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 2), IV.spec(51, 3)]) },
                    fire: { $0.guess(0, .higher) },
                    expect: { e, f, c in
                        XCTAssertEqual(e.run.bonusCoins, f.bonusCoins, "\(c): a wrong guess grows nothing")
                    }),
            ]

        case "collector":
            let unit = def.num("value", 1) == 0 ? 1 : v
            return landingFamily(def, boardTops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)],
                allowed: .coins,
                expect: { e, f, c in
                    // Collector alone: 0 other stickers → +0. Assert the exact contract.
                    XCTAssertEqual(e.run.bonusCoins, f.bonusCoins, "\(c): alone it pays 0")
                    _ = unit
                },
                expectNoFire: { e, f, c in XCTAssertEqual(e.run.bonusCoins, f.bonusCoins, "\(c)") })
                + [IV.Scenario("trigger-withCompanions", allowed: [.coins, .guesses, .deck, .board],
                    build: { IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 9, "♠", ["collector", "tieSafe", "tell"]),
                                                   IV.spec(51, 2)]) },
                    fire: { $0.guess(0, .higher) },
                    expect: { e, f, c in
                        XCTAssertEqual(e.run.bonusCoins, f.bonusCoins + unit * 2,
                                       "\(c): +\(unit) per OTHER sticker on the card (2)")
                    })]

        case "tributeCoin":   // Leech
            return landingFamily(def, allowed: .coins,
                expect: { e, f, c in
                    XCTAssertEqual(e.run.bonusCoins, f.bonusCoins - v, "\(c): -\(v) coins on landing")
                },
                expectNoFire: { e, f, c in XCTAssertEqual(e.run.bonusCoins, f.bonusCoins, "\(c)") })

        case "deepPockets":
            let per = def.num("per", 10)
            return [
                IV.Scenario("trigger-20cards", allowed: [.coins, .guesses, .deck, .board],
                    build: {
                        var deck: [CardSpec] = [IV.spec(50, 9, "♠", ["deepPockets"])]
                        for i in 0..<20 { deck.append(IV.spec(60 + i, 2 + (i % 8))) }
                        return IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)], deckOrder: deck)
                    },
                    fire: { $0.guess(0, .higher) },
                    expect: { e, f, c in
                        XCTAssertEqual(e.run.bonusCoins, f.bonusCoins + (20.0 / per).rounded(.down),
                                       "\(c): +1 per \(Int(per)) cards left (20 left after the draw)")
                    }),
                IV.Scenario("edge-thinDeckPaysZero", allowed: [.guesses, .deck, .board],
                    build: { IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 9, "♠", ["deepPockets"]), IV.spec(51, 2)]) },
                    fire: { $0.guess(0, .higher) },
                    expect: { e, f, c in
                        XCTAssertEqual(e.run.bonusCoins, f.bonusCoins, "\(c): 1 card left < \(Int(per)) pays 0")
                    }),
                IV.Scenario("mustNotFire", allowed: [.guesses, .deck, .board],
                    build: {
                        var deck: [CardSpec] = [IV.spec(50, 9)]
                        for i in 0..<20 { deck.append(IV.spec(60 + i, 2 + (i % 8))) }
                        return IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)], deckOrder: deck)
                    },
                    fire: { $0.guess(0, .higher) },
                    expect: { e, f, c in XCTAssertEqual(e.run.bonusCoins, f.bonusCoins, "\(c)") }),
            ]

        case "looseChange":
            let maxV = Double(def.int("max", 3))
            return landingFamily(def, allowed: .coins,
                expect: { e, f, c in
                    let d = e.run.bonusCoins - f.bonusCoins
                    XCTAssertTrue(d >= 0 && d <= maxV, "\(c): pays 0-\(Int(maxV)), paid \(d)")
                },
                expectNoFire: { e, f, c in XCTAssertEqual(e.run.bonusCoins, f.bonusCoins, "\(c)") })

        case "heartChoir":
            return landingFamily(def,
                boardTops: [IV.spec(1, 5), IV.spec(2, 6, "♥"), IV.spec(3, 6, "♥")],
                allowed: .coins,
                expect: { e, f, c in
                    XCTAssertEqual(e.run.bonusCoins, f.bonusCoins + v * 2,
                                   "\(c): +\(v) per OTHER alive ♥ top (2)")
                },
                expectNoFire: { e, f, c in XCTAssertEqual(e.run.bonusCoins, f.bonusCoins, "\(c)") })
                + [IV.Scenario("edge-noHeartsPaysZero", allowed: [.guesses, .deck, .board],
                    build: { IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6, "♣"), IV.spec(3, 6, "♠")],
                                       deckOrder: [IV.spec(50, 9, "♠", ["heartChoir"]), IV.spec(51, 2)]) },
                    fire: { $0.guess(0, .higher) },
                    expect: { e, f, c in XCTAssertEqual(e.run.bonusCoins, f.bonusCoins, "\(c)") })]

        case "heartSnob", "suitSnob", "clubSnob", "diamondSnob":
            // The snob rides the PILE TOP; a matching-suit landing fires it.
            let suit = ["heartSnob": "♥", "suitSnob": "♠", "clubSnob": "♣", "diamondSnob": "♦"][def.behavior!]!
            let base: [CardSpec?] = [IV.spec(1, 5, suit), IV.spec(2, 6, "♦"), IV.spec(3, 6)]
            return landingFamily(def, onTop: true, topSuit: suit, drawnSuit: suit,
                boardTops: base,
                allowed: [.coins, .deck],
                expect: { e, f, c in
                    switch def.behavior {
                    case "heartSnob":
                        XCTAssertEqual(e.run.bonusCoins, f.bonusCoins + def.num("value", 4),
                                       "\(c): +\(def.num("value", 4)) when a ♥ lands on it")
                    case "suitSnob":
                        XCTAssertTrue(e.run.revealNextActive, "\(c): peeks the next card")
                    case "clubSnob":
                        // Trigger deck has spares; the last-card edge has none —
                        // assert the bury only when the deck could feed it.
                        let dug = e.deck.isEmpty && f.deckRemaining <= 1 ? 0 : def.int("digCount", 1)
                        XCTAssertEqual(e.board.piles[0].cards.count, f.pileCounts[0] + 1 + dug,
                                       "\(c): buried \(dug) under the landing")
                    case "diamondSnob":
                        XCTAssertEqual(e.run.bonusCoins, f.bonusCoins, "\(c): shuffle moves no coins")
                    default: break
                    }
                },
                expectNoFire: { e, f, c in
                    XCTAssertEqual(e.run.bonusCoins, f.bonusCoins, "\(c)")
                    XCTAssertFalse(e.run.revealNextActive, "\(c)")
                })
                + [IV.Scenario("mustNotFire-offSuitLanding", allowed: [.guesses, .deck, .board],
                    build: { IV.engine(tops: [IV.spec(1, 5, suit, [def.id]), IV.spec(2, 6, "♦"), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 9, suit == "♥" ? "♠" : "♥"), IV.spec(51, 2)]) },
                    fire: { $0.guess(0, .higher) },
                    expect: { e, f, c in
                        XCTAssertEqual(e.run.bonusCoins, f.bonusCoins, "\(c): off-suit landing, no fire")
                        XCTAssertFalse(e.run.revealNextActive, "\(c)")
                    })]

        case "clubRoots":
            let dig = def.int("digCount", 1)
            return [
                IV.Scenario("trigger", allowed: [.board, .deck, .guesses],
                    build: { IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6, "♣"), IV.spec(3, 6, "♣")],
                                       deckOrder: [IV.spec(50, 9, "♠", ["clubRoots"]), IV.spec(51, 2),
                                                   IV.spec(52, 3), IV.spec(53, 4), IV.spec(54, 7)]) },
                    fire: { $0.guess(0, .higher) },
                    expect: { e, f, c in
                        XCTAssertEqual(e.board.piles[1].cards.count, f.pileCounts[1] + dig,
                                       "\(c): buried \(dig) under the OTHER ♣ pile 2")
                        XCTAssertEqual(e.board.piles[2].cards.count, f.pileCounts[2] + dig,
                                       "\(c): buried \(dig) under the OTHER ♣ pile 3")
                    }),
                IV.Scenario("edge-emptyDeckBuriesNothing", allowed: [.board, .deck, .guesses],
                    build: { IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6, "♣"), IV.spec(3, 6, "♣")],
                                       deckOrder: [IV.spec(50, 9, "♠", ["clubRoots"])]) },
                    fire: { $0.guess(0, .higher) },
                    expect: { e, f, c in
                        XCTAssertEqual(e.board.piles[1].cards.count, f.pileCounts[1], "\(c)")
                    }, skipSnapshot: true),
                IV.Scenario("mustNotFire", allowed: [.board, .deck, .guesses],
                    build: { IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6, "♣"), IV.spec(3, 6, "♣")],
                                       deckOrder: [IV.spec(50, 9), IV.spec(51, 2)]) },
                    fire: { $0.guess(0, .higher) },
                    expect: { e, f, c in
                        XCTAssertEqual(e.board.piles[1].cards.count, f.pileCounts[1], "\(c)")
                    }),
            ]

        case "diamondRipple":
            return [
                IV.Scenario("trigger-shufflesOtherDiamonds", allowed: [.guesses, .deck, .board],
                    build: { IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6, "♦"), IV.spec(3, 6, "♦")],
                                       deckOrder: [IV.spec(50, 9, "♠", ["diamondRipple"]), IV.spec(51, 2)]) },
                    fire: { $0.guess(0, .higher) },
                    expect: { e, f, c in
                        XCTAssertEqual((0..<3).map { e.board.piles[$0].cards.count }, [2, 1, 1],
                                       "\(c): a shuffle moves nothing between piles")
                        XCTAssertNil(e.run.pendingRipple, "\(c): auto mode resolves inline")
                    }),
                IV.Scenario("edge-consentModeParks", allowed: [.guesses, .deck, .board],
                    build: {
                        let e = IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6, "♦"), IV.spec(3, 6, "♦")],
                                          deckOrder: [IV.spec(50, 9, "♠", ["diamondRipple"]), IV.spec(51, 2)])
                        e.run.rippleNeedsConsent = true
                        return e
                    },
                    fire: { $0.guess(0, .higher) },
                    expect: { e, _, c in
                        XCTAssertEqual(e.run.pendingRipple?.piles.sorted(), [1, 2],
                                       "\(c): consent mode parks the shuffle for the prompt")
                        e.answerRipple(false)
                        XCTAssertNil(e.run.pendingRipple, "\(c): a decline discards it")
                    }),
                IV.Scenario("mustNotFire-noDiamondTops", allowed: [.guesses, .deck, .board],
                    build: { IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6, "♣"), IV.spec(3, 6, "♠")],
                                       deckOrder: [IV.spec(50, 9, "♠", ["diamondRipple"]), IV.spec(51, 2)]) },
                    fire: { $0.guess(0, .higher) },
                    expect: { e, _, c in XCTAssertNil(e.run.pendingRipple, "\(c)") }),
            ]

        case "spadeWhispers":
            return landingFamily(def,
                boardTops: [IV.spec(1, 5), IV.spec(2, 6, "♠"), IV.spec(3, 6, "♠")],
                allowed: [.deck],
                expect: { e, _, c in
                    XCTAssertEqual(e.run.tellDrawsLeft, 2, "\(c): +1 hint per other ♠ top (2)")
                    XCTAssertTrue(e.run.whisperPiles.contains(0), "\(c): its own pile whispers")
                },
                expectNoFire: { e, _, c in
                    XCTAssertEqual(e.run.tellDrawsLeft, 0, "\(c)")
                })

        case "quickBury":
            return landingFamily(def, allowed: [.board, .deck],
                expect: { e, f, c in
                    XCTAssertEqual(e.board.piles[0].cards.count, f.pileCounts[0] + 2,
                                   "\(c): the landing + 1 buried beneath")
                    // Web parity: Quick Bury PERSISTS — it never peels itself.
                    XCTAssertTrue(e.board.top(0)!.stickers.contains { $0.type == "quickBury" }
                                    || e.board.piles[0].cards.contains { c2 in c2.stickers.contains { $0.type == "quickBury" } },
                                  "\(c): the sticker stays on the card")
                },
                expectNoFire: { e, f, c in
                    XCTAssertEqual(e.board.piles[0].cards.count, f.pileCounts[0] + 1, "\(c): just the landing")
                },
                expectEdge: { e, f, c in
                    XCTAssertEqual(e.board.piles[0].cards.count, f.pileCounts[0] + 1,
                                   "\(c): an empty deck buries nothing, the landing is fine")
                })

        case "snowball":
            let step = def.int("step", 1)
            return [
                IV.Scenario("trigger-growsThenBuries", allowed: [.board, .deck, .guesses],
                    build: {
                        let e = IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)],
                                          deckOrder: [IV.spec(50, 9, "♠", ["snowball"]), IV.spec(51, 2), IV.spec(52, 3)])
                        e.deck.snapshotCards().first { $0.id == 50 }!.snowball = 2
                        return e
                    },
                    fire: { $0.guess(0, .higher) },
                    expect: { e, f, c in
                        XCTAssertEqual(e.board.piles[0].cards.count, f.pileCounts[0] + 1 + 2,
                                       "\(c): buried its X (2) under the landing")
                        XCTAssertEqual(e.run.snowballUpdates[50], 2 + step, "\(c): X grew by \(step)")
                    }),
                IV.Scenario("edge-firstLandingBuriesZero", allowed: [.board, .deck, .guesses],
                    build: { IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 9, "♠", ["snowball"]), IV.spec(51, 2)]) },
                    fire: { $0.guess(0, .higher) },
                    expect: { e, f, c in
                        XCTAssertEqual(e.board.piles[0].cards.count, f.pileCounts[0] + 1,
                                       "\(c): X=0 buries nothing")
                        XCTAssertEqual(e.run.snowballUpdates[50], step, "\(c): X grew to \(step)")
                    }),
                IV.Scenario("mustNotFire-wrongPlacementResets", allowed: [.board, .deck, .guesses, .deaths],
                    build: {
                        let e = IV.engine(tops: [IV.spec(1, 9), IV.spec(2, 6), IV.spec(3, 6)],
                                          deckOrder: [IV.spec(50, 2, "♠", ["snowball"]), IV.spec(51, 3)])
                        e.deck.snapshotCards().first { $0.id == 50 }!.snowball = 3
                        return e
                    },
                    fire: { $0.guess(0, .higher) },   // wrong → reset
                    expect: { e, _, c in
                        XCTAssertEqual(e.run.snowballUpdates[50], 0, "\(c): a wrong placement resets X")
                    }),
            ]

        case "twinSpark":
            return landingFamily(def, drawnRank: 6,
                boardTops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 3)],
                allowed: [.deck],
                expect: { e, _, c in
                    XCTAssertTrue(e.run.revealNextActive, "\(c): a rank twin on pile 2 → peek")
                },
                expectNoFire: { e, _, c in XCTAssertFalse(e.run.revealNextActive, "\(c)") })
                + [IV.Scenario("mustNotFire-noTwin", allowed: [.guesses, .deck, .board],
                    build: { IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 11), IV.spec(3, 3)],
                                       deckOrder: [IV.spec(50, 6, "♠", ["twinSpark"]), IV.spec(51, 2)]) },
                    fire: { $0.guess(0, .higher) },
                    expect: { e, _, c in XCTAssertFalse(e.run.revealNextActive, "\(c)") })]

        case "revealNext":
            return landingFamily(def, allowed: [.deck],
                expect: { e, _, c in XCTAssertTrue(e.run.revealNextActive, "\(c): Scout peeks") },
                expectNoFire: { e, _, c in XCTAssertFalse(e.run.revealNextActive, "\(c)") })

        case "tell":
            return landingFamily(def, allowed: [.deck],
                expect: { e, _, c in XCTAssertTrue(e.run.tellPiles.contains(0), "\(c): the pile is told") },
                expectNoFire: { e, _, c in XCTAssertTrue(e.run.tellPiles.isEmpty, "\(c)") })

        case "pillarScout", "baseScout":
            let isPillar = def.behavior == "pillarScout"
            return landingFamily(def, allowed: [.deck],
                expect: { e, _, c in
                    XCTAssertTrue(e.run.revealNextActive, "\(c): empty slot → peek")
                },
                expectNoFire: { e, _, c in XCTAssertFalse(e.run.revealNextActive, "\(c)") })
                + [IV.Scenario("mustNotFire-slotFilled", allowed: [.guesses, .deck, .board, .coins],
                    build: { IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 9, "♠", [def.id]), IV.spec(51, 2)],
                                       pillars: isPillar ? ["fibonacci", nil, nil] : nil,
                                       bases: isPillar ? nil : ["spadePeek", nil, nil]) },
                    fire: { $0.guess(0, .higher) },
                    expect: { e, _, c in
                        XCTAssertFalse(e.run.revealNextActive, "\(c): a filled slot blocks the scout")
                    })]

        case "rechargeSameShield":
            return landingFamily(def, allowed: [.charge],
                expect: { e, _, c in XCTAssertTrue(e.sameCharge, "\(c): banks the charge") },
                expectNoFire: { e, _, c in XCTAssertFalse(e.sameCharge, "\(c)") })

        case "activateSamePower":
            return [
                IV.Scenario("trigger-firesEquippedPower", allowed: [.coins, .guesses, .deck, .board, .charge],
                    build: { IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 9, "♠", ["activateSamePower"]), IV.spec(51, 2)],
                                       samePower: "linkCoins") },
                    fire: { $0.guess(0, .higher) },
                    expect: { e, f, c in
                        XCTAssertGreaterThan(e.run.bonusCoins, f.bonusCoins,
                                             "\(c): Link Coins fired on the landing")
                    }),
                IV.Scenario("edge-noPowerEquippedIsQuietNoOp", allowed: [.guesses, .deck, .board],
                    build: { IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 9, "♠", ["activateSamePower"]), IV.spec(51, 2)]) },
                    fire: { $0.guess(0, .higher) },
                    expect: { e, f, c in XCTAssertEqual(e.run.bonusCoins, f.bonusCoins, "\(c)") }),
                IV.Scenario("mustNotFire", allowed: [.guesses, .deck, .board],
                    build: { IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 9), IV.spec(51, 2)],
                                       samePower: "linkCoins") },
                    fire: { $0.guess(0, .higher) },
                    expect: { e, f, c in XCTAssertEqual(e.run.bonusCoins, f.bonusCoins, "\(c)") }),
            ]

        case "tieSafe":
            return [
                IV.Scenario("trigger-tieOnDirectionalIsSafe", allowed: [.guesses, .deck, .board],
                    build: { IV.engine(tops: [IV.spec(1, 7, "♠", ["tieSafe"]), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 7, "♥"), IV.spec(51, 2)]) },
                    fire: { e in
                        var saved = false
                        e.on { if case .tieSafeSaved = $0 { saved = true } }
                        e.guess(0, .higher)
                        XCTAssertTrue(saved, "tieSafe: the save ANNOUNCES itself (v6.50 audit fix)")
                    },
                    expect: { e, _, c in
                        XCTAssertTrue(e.board.isActive(0), "\(c): the tie was safe")
                        XCTAssertEqual(e.run.correctGuesses, 1, "\(c): counts correct")
                    }),
                IV.Scenario("edge-jokerInvolvedStillSafe", allowed: [.guesses, .deck, .board],
                    build: { IV.engine(tops: [IV.spec(1, 7, "♠", ["tieSafe"]), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 0, joker: true), IV.spec(51, 2)]) },
                    fire: { $0.guess(0, .lower) },
                    expect: { e, _, c in XCTAssertTrue(e.board.isActive(0), "\(c)") }),
                IV.Scenario("mustNotFire-plainTieKills", allowed: [.guesses, .deck, .board, .deaths],
                    build: { IV.engine(tops: [IV.spec(1, 7), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 7, "♥"), IV.spec(51, 2)]) },
                    fire: { $0.guess(0, .higher) },
                    expect: { e, _, c in XCTAssertFalse(e.board.isActive(0), "\(c): no sticker, the tie kills") }),
            ]

        case "suitImmunity":
            let suit = def.suit ?? "♠"
            return [
                IV.Scenario("trigger-guardAbsorbsWrongGuess", allowed: [.guesses, .board, .deck],
                    build: { IV.engine(tops: [IV.spec(1, 9, suit, [def.id]), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 2, suit), IV.spec(51, 3)]) },
                    fire: { $0.guess(0, .higher) },   // wrong, but the guarded suit is involved
                    expect: { e, f, c in
                        XCTAssertTrue(e.board.isActive(0), "\(c): the guard absorbed it")
                        XCTAssertEqual(e.deck.remaining(), f.deckRemaining - 1 + 1,
                                       "\(c): the drawn card went back to the deck")
                    }),
                IV.Scenario("edge-bidirectional", allowed: [.guesses, .board, .deck],
                    build: { IV.engine(tops: [IV.spec(1, 9, suit), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 2, "♠" == suit ? "♥" : "♠", [def.id]), IV.spec(51, 3)]) },
                    fire: { $0.guess(0, .higher) },
                    expect: { e, _, c in
                        XCTAssertTrue(e.board.isActive(0),
                                      "\(c): the DRAWN card's guard saves when the PILE TOP is its suit")
                    }),
                IV.Scenario("mustNotFire-unguardedSuit", allowed: [.guesses, .board, .deck, .deaths],
                    build: {
                        let other = suit == "♠" ? "♥" : "♠"
                        return IV.engine(tops: [IV.spec(1, 9, other, [def.id]), IV.spec(2, 6), IV.spec(3, 6)],
                                         deckOrder: [IV.spec(50, 2, other), IV.spec(51, 3)])
                    },
                    fire: { $0.guess(0, .higher) },
                    expect: { e, _, c in
                        XCTAssertFalse(e.board.isActive(0), "\(c): the guard is suit-locked (v6.x fix)")
                    }),
            ]

        case "wildSuit":
            return [
                IV.Scenario("trigger-countsAsEverySuit", allowed: [],
                    build: { IV.engine(tops: [IV.spec(1, 5, "♣", ["wildSuit"]), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 9)]) },
                    fire: { _ in },
                    expect: { e, _, c in
                        XCTAssertTrue(CardRules.matchesSuit(e.board.top(0), "♥"), "\(c): ♥ yes")
                        XCTAssertTrue(CardRules.matchesSuit(e.board.top(0), "♠"), "\(c): ♠ yes")
                    }),
                IV.Scenario("edge-feedsSuitPillar", allowed: [.coins, .guesses, .deck, .board],
                    build: { IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 9, "♣", ["wildSuit"]), IV.spec(51, 2)],
                                       pillars: ["heartBounty", nil, nil]) },
                    fire: { $0.guess(0, .higher) },
                    expect: { e, f, c in
                        XCTAssertGreaterThan(e.run.bonusCoins, f.bonusCoins,
                                             "\(c): a wild ♣ pays the ♥ bounty")
                    }),
                IV.Scenario("mustNotFire", allowed: [],
                    build: { IV.engine(tops: [IV.spec(1, 5, "♣"), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 9)]) },
                    fire: { _ in },
                    expect: { e, _, c in
                        XCTAssertFalse(CardRules.matchesSuit(e.board.top(0), "♥"), "\(c)")
                    }),
            ]

        case "anchor":
            return [
                IV.Scenario("trigger-anchoredPileLeavesTheMin", allowed: [],
                    build: {
                        let e = IV.engine(tops: [IV.spec(1, 5, "♠", ["anchor"]), IV.spec(2, 6), IV.spec(3, 6)],
                                          deckOrder: [IV.spec(50, 9)])
                        e.board.piles[1].cards.append(DeckManager.toCard(IV.spec(90, 7), data: data))
                        e.board.piles[2].cards.append(DeckManager.toCard(IV.spec(91, 7), data: data))
                        return e
                    },
                    fire: { _ in },
                    expect: { e, _, c in
                        XCTAssertTrue(e.board.isAnchored(0), "\(c): the pile is anchored")
                        XCTAssertEqual(e.board.minAliveCards(), 2,
                                       "\(c): the size-1 anchored pile is excluded from the min")
                    }),
                IV.Scenario("edge-allAnchoredFallsBack", allowed: [],
                    build: { IV.engine(tops: [IV.spec(1, 5, "♠", ["anchor"]), IV.spec(2, 6, "♠", ["anchor"]),
                                              IV.spec(3, 6, "♠", ["anchor"])],
                                       deckOrder: [IV.spec(50, 9)]) },
                    fire: { _ in },
                    expect: { e, _, c in
                        XCTAssertEqual(e.board.minAliveCards(), 1, "\(c): every pile anchored → true min")
                    }),
                IV.Scenario("mustNotFire", allowed: [],
                    build: { IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 9)]) },
                    fire: { _ in },
                    expect: { e, _, c in XCTAssertFalse(e.board.isAnchored(0), "\(c)") }),
            ]

        case "heavy":
            let w = def.int("value", 1)
            return [
                IV.Scenario("trigger-countsExtra", allowed: [],
                    build: { IV.engine(tops: [IV.spec(1, 5, "♠", [def.id]), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 9)]) },
                    fire: { _ in },
                    expect: { e, _, c in
                        XCTAssertEqual(e.board.pileSize(0), 1 + w, "\(c): counts 1+\(w)")
                    }),
                IV.Scenario("edge-feedsTheMin", allowed: [],
                    build: {
                        let e = IV.engine(tops: [IV.spec(1, 5, "♠", [def.id]), IV.spec(2, 6), IV.spec(3, 6)],
                                          deckOrder: [IV.spec(50, 9)])
                        e.board.piles[1].cards.append(DeckManager.toCard(IV.spec(90, 7), data: data))
                        e.board.piles[2].cards.append(DeckManager.toCard(IV.spec(91, 7), data: data))
                        return e
                    },
                    fire: { _ in },
                    expect: { e, _, c in
                        XCTAssertEqual(e.board.minAliveCards(), min(1 + w, 2), "\(c): the min sees the weight")
                    }),
                IV.Scenario("mustNotFire", allowed: [],
                    build: { IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 9)]) },
                    fire: { _ in },
                    expect: { e, _, c in XCTAssertEqual(e.board.pileSize(0), 1, "\(c)") }),
            ]

        case "shuffle":
            return landingFamily(def, allowed: [.deck],
                expect: { e, _, c in
                    XCTAssertEqual(e.run.pendingActions.first?.kind, "shuffle",
                                   "\(c): the OPTIONAL shuffle is offered")
                },
                expectNoFire: { e, _, c in
                    XCTAssertTrue(e.run.pendingActions.isEmpty, "\(c)")
                })
                + [IV.Scenario("mustNotFire-singleCardPile", allowed: [.guesses, .deck, .board, .deaths],
                    build: { IV.engine(tops: [IV.spec(1, 9), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 2, "♠", ["shuffle"]), IV.spec(51, 3)]) },
                    fire: { $0.guess(0, .lower) },   // correct: lands, pile = 2 cards → offers
                    expect: { e, _, c in
                        XCTAssertEqual(e.run.pendingActions.count, 1, "\(c)")
                    })]

        case "donate":
            return [
                IV.Scenario("trigger-movesToSmallest", allowed: [.board, .deck, .guesses],
                    build: {
                        let e = IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)],
                                          deckOrder: [IV.spec(50, 9, "♠", ["donate"]), IV.spec(51, 2)])
                        e.board.piles[0].cards.append(DeckManager.toCard(IV.spec(90, 7), data: data))
                        e.board.piles[0].cards.append(DeckManager.toCard(IV.spec(91, 8), data: data))
                        return e
                    },
                    fire: { $0.guess(0, .higher) },   // 9 on the size-3 pile → donates down
                    expect: { e, f, c in
                        XCTAssertLessThan(e.board.piles[0].cards.count, f.pileCounts[0] + 1,
                                          "\(c): a bottom card left the landing pile")
                        XCTAssertTrue(e.board.piles[1].cards.count > f.pileCounts[1]
                                        || e.board.piles[2].cards.count > f.pileCounts[2],
                                      "\(c): a smaller pile received it")
                    }),
                IV.Scenario("edge-alreadySmallestStaysPut", allowed: [.board, .deck, .guesses],
                    build: {
                        let e = IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)],
                                          deckOrder: [IV.spec(50, 9, "♠", ["donate"]), IV.spec(51, 2)])
                        e.board.piles[1].cards.append(DeckManager.toCard(IV.spec(90, 7), data: data))
                        e.board.piles[2].cards.append(DeckManager.toCard(IV.spec(91, 7), data: data))
                        return e
                    },
                    fire: { $0.guess(0, .higher) },
                    expect: { e, f, c in
                        XCTAssertEqual(e.board.piles[1].cards.count, f.pileCounts[1], "\(c): no donation up")
                        XCTAssertEqual(e.board.piles[2].cards.count, f.pileCounts[2], "\(c)")
                    }),
                IV.Scenario("mustNotFire", allowed: [.board, .deck, .guesses],
                    build: { IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 9), IV.spec(51, 2)]) },
                    fire: { $0.guess(0, .higher) },
                    expect: { e, f, c in
                        XCTAssertEqual(e.board.piles[1].cards.count, f.pileCounts[1], "\(c)")
                    }),
            ]

        case "tribute":
            let count = def.int("tributeCount", 0) != 0 ? def.int("tributeCount", 0) : 1
            let cost = def.num("coinCost", 0)
            return [
                IV.Scenario("trigger", allowed: [.deck, .board, .coins, .guesses],
                    build: { IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 9, "♠", [def.id]), IV.spec(51, 2),
                                                   IV.spec(52, 3), IV.spec(53, 4)]) },
                    fire: { $0.guess(0, .higher) },
                    expect: { e, f, c in
                        XCTAssertEqual(e.board.piles[0].cards.count, f.pileCounts[0] + 1 + count,
                                       "\(c): buried \(count) automatically")
                        XCTAssertEqual(e.run.bonusCoins, f.bonusCoins - cost,
                                       "\(c): charged its \(cost) coin toll")
                    }),
                IV.Scenario("edge-emptyDeckStillTolls", allowed: [.deck, .board, .coins, .guesses],
                    build: { IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 9, "♠", [def.id])]) },
                    fire: { $0.guess(0, .higher) },
                    expect: { e, f, c in
                        XCTAssertEqual(e.run.bonusCoins, f.bonusCoins - cost,
                                       "\(c): the toll charges; the empty deck buries nothing")
                    }, skipSnapshot: true),
                IV.Scenario("mustNotFire", allowed: [.deck, .board, .guesses],
                    build: { IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 9), IV.spec(51, 2)]) },
                    fire: { $0.guess(0, .higher) },
                    expect: { e, f, c in
                        XCTAssertEqual(e.run.bonusCoins, f.bonusCoins, "\(c)")
                    }),
            ]

        // Curse stickers are exhaustively covered in CurseTests — map them to
        // a representative trigger + must-not-fire here so the completeness
        // contract sees them (their deep suites already ran).
        case "trapdoor", "shrink", "mute", "spoiler", "drainShield", "flatline",
             "magnet", "jammer", "peeler", "drainBase", "malfunction", "saboteur":
            return curseSummary(def)

        default:
            return nil
        }
    }

    /// Compact curse mapping (the full behavior suites live in CurseTests).
    static func curseSummary(_ def: ItemDef) -> [IV.Scenario] {
        [
            IV.Scenario("trigger-representative", allowed: .all,
                build: { IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)],
                                   deckOrder: [IV.spec(50, 9, "♠", [def.id]), IV.spec(51, 2)],
                                   pillars: ["fibonacci", nil, nil], bases: ["spadePeek", nil, nil],
                                   sameCharge: true) },
                fire: { $0.guess(0, .higher) },
                expect: { e, _, c in
                    XCTAssertEqual(e.board.top(0)?.id ?? -1, 50, "\(c): the cursed card landed")
                }),
            IV.Scenario("edge-lastCard", allowed: .all,
                build: { IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)],
                                   deckOrder: [IV.spec(50, 9, "♠", [def.id])]) },
                fire: { $0.guess(0, .higher) },
                expect: { _, _, _ in }, skipSnapshot: true),
            IV.Scenario("mustNotFire-clean", allowed: [.guesses, .deck, .board, .coins],
                build: { IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)],
                                   deckOrder: [IV.spec(50, 9), IV.spec(51, 2)],
                                   sameCharge: true) },
                fire: { $0.guess(0, .higher) },
                expect: { e, _, c in
                    XCTAssertTrue(e.sameCharge, "\(c): a clean landing drains nothing")
                    XCTAssertEqual(e.run.basesUsed?[0], false, "\(c)")
                }),
        ]
    }
}
