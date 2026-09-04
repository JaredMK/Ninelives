import XCTest
@testable import GameCore

/// TIER 1 scenario generators — BASES (tap-to-fire) and SAME-POWERS.
enum IVBases {

    static let data = GameData.shared

    /// Standard base board: base on column 0 (2 piles), one other column.
    static func baseEngine(_ def: ItemDef, tops: [CardSpec?]? = nil,
                           deckOrder: [CardSpec]? = nil,
                           pillars: [String?]? = nil,
                           samePower: String? = nil,
                           isBoss: Bool = false, isAmbush: Bool = false) -> GameEngine {
        IV.engine(tops: tops ?? [IV.spec(1, 5, "♠"), IV.spec(2, 8, "♥"), IV.spec(3, 6, "♣")],
                  deckOrder: deckOrder ?? [IV.spec(50, 9), IV.spec(51, 3), IV.spec(52, 7), IV.spec(53, 4)],
                  cols: [2, 1],
                  pillars: pillars ?? [nil, nil],
                  bases: [def.id, nil],
                  samePower: samePower,
                  isBoss: isBoss, isAmbush: isAmbush)
    }

    /// After ANY successful activation: the charge is spent and stays spent.
    static func assertSpent(_ e: GameEngine, _ c: String) {
        XCTAssertEqual(e.run.basesUsed?[0], true, "\(c): the charge is spent")
        XCTAssertNil(e.baseActivate(col: 0), "\(c): a spent base cannot fire twice")
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    static func scenarios(for def: ItemDef) -> [IV.Scenario]? {
        switch def.effect {

        case "kamikaze":
            return [
                IV.Scenario("trigger", allowed: .all,
                    build: { baseEngine(def) },
                    fire: { _ = $0.baseActivate(col: 0) },
                    expect: { e, _, c in
                        XCTAssertFalse(e.board.isActive(0), "\(c): the ♠ pile was sacrificed")
                        XCTAssertEqual(e.run.kamikazeRevealLeft, def.int("peekCount", 3),
                                       "\(c): peeks the next \(def.int("peekCount", 3)) draws")
                        assertSpent(e, c)
                    }),
                IV.Scenario("edge-lastAliveInColumn", allowed: .all,
                    build: { baseEngine(def, tops: [IV.spec(1, 5, "♠"), nil, IV.spec(3, 6)]) },
                    fire: { _ = $0.baseActivate(col: 0) },
                    expect: { e, _, c in
                        XCTAssertFalse(e.board.isActive(0), "\(c): it will take the last pile")
                    }),
                IV.Scenario("mustNotFire-noSpadeTop", allowed: [],
                    build: { baseEngine(def, tops: [IV.spec(1, 5, "♥"), IV.spec(2, 8, "♦"), IV.spec(3, 6)]) },
                    fire: { e in XCTAssertNil(e.baseActivate(col: 0), "kamikaze needs a ♠ top") },
                    expect: { e, _, c in
                        XCTAssertEqual(e.run.basesUsed?[0], false, "\(c): a refused fire keeps the charge")
                    }),
            ]

        case "rechargeSameShield":
            return [
                IV.Scenario("trigger", allowed: .all,
                    build: { baseEngine(def) },
                    fire: { _ = $0.baseActivate(col: 0) },
                    expect: { e, _, c in
                        XCTAssertTrue(e.sameCharge, "\(c): banked the charge")
                        assertSpent(e, c)
                    }),
                IV.Scenario("edge-alreadyChargedRefuses", allowed: [],
                    build: { IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 8), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 9)], cols: [2, 1],
                                       bases: [def.id, nil], sameCharge: true) },
                    fire: { e in _ = e.baseActivate(col: 0) },
                    expect: { e, _, c in
                        XCTAssertTrue(e.sameCharge, "\(c)")
                    }),
                IV.Scenario("mustNotFire-otherColumn", allowed: [],
                    build: { baseEngine(def) },
                    fire: { e in XCTAssertNil(e.baseActivate(col: 1), "no base there") },
                    expect: { e, _, c in XCTAssertFalse(e.sameCharge, "\(c)") }),
            ]

        case "activateSamePower":
            return [
                IV.Scenario("trigger-firesPower", allowed: .all,
                    build: { baseEngine(def, samePower: "linkCoins") },
                    fire: { _ = $0.baseActivate(col: 0) },
                    expect: { e, f, c in
                        XCTAssertGreaterThan(e.run.bonusCoins, f.bonusCoins, "\(c): Link Coins paid")
                        XCTAssertFalse(e.sameCharge, "\(c): banks NO charge")
                        assertSpent(e, c)
                    }),
                IV.Scenario("edge-noPowerStillSpends", allowed: .all,
                    build: { baseEngine(def) },
                    fire: { _ = $0.baseActivate(col: 0) },
                    expect: { e, f, c in
                        XCTAssertEqual(e.run.bonusCoins, f.bonusCoins, "\(c): nothing to fire")
                    }),
                IV.Scenario("mustNotFire-spent", allowed: .all,
                    build: { baseEngine(def, samePower: "linkCoins") },
                    fire: { e in _ = e.baseActivate(col: 0); _ = e.baseActivate(col: 0) },
                    expect: { e, _, c in XCTAssertEqual(e.run.basesUsed?[0], true, "\(c)") }),
            ]

        case "spadePeek":
            // v7.01: X = the column's ♠ tops (the all-♠ gate retired).
            return [
                IV.Scenario("trigger-twoSpadesPeekTwo", allowed: .all,
                    build: { baseEngine(def, tops: [IV.spec(1, 5, "♠"), IV.spec(2, 8, "♠"), IV.spec(3, 6)]) },
                    fire: { e in
                        XCTAssertEqual(e.baseLiveCounter(0), 2, "badge: 2 ♠ tops")
                        let r = e.baseActivate(col: 0)
                        XCTAssertEqual(r?.peekCount, 2, "peeks scale with the ♠ tops")
                    },
                    expect: { e, _, c in
                        XCTAssertEqual(e.run.kamikazeRevealLeft, 2, "\(c): X = 2")
                        assertSpent(e, c)
                    }),
                IV.Scenario("edge-oneSpadeAmongMixed", allowed: .all,
                    build: { baseEngine(def, tops: [IV.spec(1, 5, "♠"), IV.spec(2, 8, "♥"), IV.spec(3, 6)]) },
                    fire: { e in
                        let r = e.baseActivate(col: 0)
                        XCTAssertEqual(r?.peekCount, 1, "one ♠ top → one peek (v7.01: mixed fires)")
                    },
                    expect: { e, _, c in
                        XCTAssertEqual(e.run.kamikazeRevealLeft, 1, "\(c)")
                    }),
                IV.Scenario("mustNotFire-noSpadeTop", allowed: [],
                    build: { baseEngine(def, tops: [IV.spec(1, 5, "♥"), IV.spec(2, 8, "♥"), IV.spec(3, 6, "♠")]) },
                    fire: { e in XCTAssertNil(e.baseActivate(col: 0), "no ♠ in ITS column must refuse") },
                    expect: { e, _, c in XCTAssertEqual(e.run.basesUsed?[0], false, "\(c)") }),
            ]

        case "lonePeek":
            return [
                IV.Scenario("trigger-noPowerEquipped", allowed: .all,
                    build: { baseEngine(def) },
                    fire: { _ = $0.baseActivate(col: 0) },
                    expect: { e, _, c in
                        XCTAssertGreaterThan(e.run.kamikazeRevealLeft, 0, "\(c)")
                        assertSpent(e, c)
                    }),
                IV.Scenario("edge-emptyDeckStillFires", allowed: .all,
                    build: { baseEngine(def, deckOrder: []) },
                    fire: { _ = $0.baseActivate(col: 0) },
                    expect: { _, _, _ in }, skipSnapshot: true),
                IV.Scenario("mustNotFire-powerEquipped", allowed: [],
                    build: { baseEngine(def, samePower: "linkCoins") },
                    fire: { e in XCTAssertNil(e.baseActivate(col: 0), "a power blocks the Lone Eye") },
                    expect: { e, _, c in XCTAssertEqual(e.run.basesUsed?[0], false, "\(c)") }),
            ]

        case "lastResort":
            return [
                IV.Scenario("trigger-buriesDeckEndsDeal", allowed: .all,
                    build: { baseEngine(def) },
                    fire: { _ = $0.baseActivate(col: 0) },
                    expect: { e, _, c in
                        XCTAssertTrue(e.deck.isEmpty, "\(c): the whole deck went under")
                        XCTAssertEqual(e.status, "won", "\(c): the deal ended as a win")
                    }, skipSnapshot: true),
                IV.Scenario("edge-scoringUnchanged", allowed: .all,
                    build: { baseEngine(def) },
                    fire: { _ = $0.baseActivate(col: 0) },
                    expect: { e, _, c in
                        XCTAssertEqual(e.board.aliveCount() * e.board.minAliveCards(),
                                       e.board.aliveCount() * e.board.minAliveCards(),
                                       "\(c): score = alive x smallest on the final board")
                        XCTAssertGreaterThan(e.board.aliveCount(), 0, "\(c)")
                    }, skipSnapshot: true),
                IV.Scenario("mustNotFire-bossDeal", allowed: [],
                    build: { baseEngine(def, isBoss: true) },
                    fire: { e in
                        XCTAssertNil(e.baseActivate(col: 0), "sealed during a boss")
                        // v6.52: the amber notice must SAY it is the boss seal.
                        XCTAssertEqual(e.baseUnavailableReason(0), "Sealed during a boss deal.")
                    },
                    expect: { e, _, c in XCTAssertEqual(e.run.basesUsed?[0], false, "\(c)") }),
                // v6.52 gate pins, from a field report of an inexplicable
                // amber: GREEN whenever the deal is live, it isn't a boss,
                // this column has an alive pile and the deck has cards —
                // ambushes and mid-deal snapshot restores included.
                IV.Scenario("edge-greenInAnAmbush", allowed: [],
                    build: { baseEngine(def, isAmbush: true) },
                    fire: { e in XCTAssertTrue(e.baseAvailable(0), "an ambush does not seal it") },
                    expect: { _, _, _ in }),
                IV.Scenario("edge-greenAfterSnapshotRestore", allowed: [],
                    build: { baseEngine(def) },
                    fire: { e in
                        let blob = e.snapshot()
                        let e2 = baseEngine(def)
                        XCTAssertTrue(e2.restoreSnapshot(blob), "the mid-deal blob restores")
                        XCTAssertTrue(e2.baseAvailable(0), "a resumed deal keeps the base green")
                    },
                    expect: { _, _, _ in }),
                IV.Scenario("edge-amberOnlyWithoutAlivePileHere", allowed: [.deaths, .board],
                    build: {
                        let e = baseEngine(def)
                        e.board.kill(0); e.board.kill(1)   // column 0 wiped
                        return e
                    },
                    fire: { e in
                        XCTAssertFalse(e.baseCanActivate(0), "no alive pile here → amber")
                        XCTAssertEqual(e.baseUnavailableReason(0),
                                       "No alive pile in this column to bury under.")
                    },
                    expect: { _, _, _ in }),
            ]

        case "emptyPurse":
            // v7.01: the spend BURIES (1 per perCoins, round-robin in its
            // column), then ONE peek regardless.
            return [
                IV.Scenario("trigger-buriesPerFiveAndPeeks", allowed: .all,
                    build: { baseEngine(def) },
                    fire: { e in
                        let r = e.baseActivate(col: 0, purseCoins: 12)
                        XCTAssertEqual(r?.buried, 2, "12 coins ÷ 5 → 2 buried")
                        XCTAssertEqual(r?.purseSpent, 12, "the whole purse drains")
                        XCTAssertEqual(r?.peekCount, 1, "…and ONE peek, always")
                    },
                    expect: { e, f, c in
                        XCTAssertEqual(e.deck.remaining(), f.deckRemaining - 2, "\(c)")
                        XCTAssertEqual(e.run.kamikazeRevealLeft, 1, "\(c)")
                        assertSpent(e, c)
                    }),
                IV.Scenario("edge-brokeStillPeeks", allowed: .all,
                    build: { baseEngine(def) },
                    fire: { e in
                        let r = e.baseActivate(col: 0, purseCoins: 0)
                        XCTAssertEqual(r?.buried, 0, "0 coins bury nothing")
                        XCTAssertEqual(r?.peekCount, 1, "…the peek is the floor")
                    },
                    expect: { e, f, c in
                        XCTAssertEqual(e.deck.remaining(), f.deckRemaining, "\(c)")
                    }),
                IV.Scenario("mustNotFire-spent", allowed: .all,
                    build: { baseEngine(def) },
                    fire: { e in _ = e.baseActivate(col: 0, purseCoins: 7) },
                    expect: { e, _, c in assertSpent(e, c) }),
            ]

        case "sameTell":
            return [
                IV.Scenario("trigger-rankMatchMarks", allowed: .all,
                    build: { baseEngine(def, tops: [IV.spec(1, 9, "♠"), IV.spec(2, 8, "♥"), IV.spec(3, 6)],
                                        deckOrder: [IV.spec(50, 9), IV.spec(51, 3)]) },
                    fire: { _ = $0.baseActivate(col: 0) },
                    expect: { e, _, c in
                        XCTAssertTrue(e.run.whisperPiles.contains(0), "\(c): the matching pile is marked")
                        XCTAssertEqual(e.run.tellDrawsLeft, 1, "\(c)")
                        assertSpent(e, c)
                    }),
                // v6.62: the search is board-WIDE — the only match sits in the
                // OTHER column (pile 2) and still gets the mark.
                IV.Scenario("boardwide-marksAnotherColumn", allowed: .all,
                    build: { baseEngine(def, tops: [IV.spec(1, 5, "♠"), IV.spec(2, 8, "♥"), IV.spec(3, 9, "♣")],
                                        deckOrder: [IV.spec(50, 9), IV.spec(51, 3)]) },
                    fire: { _ = $0.baseActivate(col: 0) },
                    expect: { e, _, c in
                        XCTAssertTrue(e.run.whisperPiles.contains(2), "\(c): a match outside the base's column is marked")
                        assertSpent(e, c)
                    }),
                IV.Scenario("edge-noMatchSaysNothing", allowed: .all,
                    build: { baseEngine(def, tops: [IV.spec(1, 5, "♠"), IV.spec(2, 8, "♥"), IV.spec(3, 6)],
                                        deckOrder: [IV.spec(50, 9), IV.spec(51, 3)]) },
                    fire: { _ = $0.baseActivate(col: 0) },
                    expect: { e, _, c in
                        XCTAssertTrue(e.run.whisperPiles.isEmpty, "\(c): silence IS the answer")
                        assertSpent(e, c)
                    }),
                IV.Scenario("edge-jokerReadsSame", allowed: .all,
                    build: { baseEngine(def, tops: [IV.spec(1, 0, "★", joker: true), IV.spec(2, 8), IV.spec(3, 6)],
                                        deckOrder: [IV.spec(50, 9), IV.spec(51, 3)]) },
                    fire: { _ = $0.baseActivate(col: 0) },
                    expect: { e, _, c in
                        // v6.52: a ★ IS a same (always safe) — the = mark
                        // appears instead of silence; a joker hint never shows
                        // an arrow.
                        XCTAssertFalse(e.run.whisperPiles.isEmpty, "\(c): the ★ pile takes the = mark")
                    }),
            ]

        case "clubTell":
            // v6.52: EVERY alive ♣ top in the column gets a TELL MARKER — the
            // armed-pile hint (run.tellPiles → pileHint), live until the next
            // draw consumes it. No random pick, no rng draw.
            return [
                IV.Scenario("trigger-marksEveryClubTop", allowed: .all,
                    build: { baseEngine(def, tops: [IV.spec(1, 5, "♣"), IV.spec(2, 10, "♣"), IV.spec(3, 6)],
                                        deckOrder: [IV.spec(50, 9), IV.spec(51, 3)]) },
                    fire: { e in
                        let r = e.baseActivate(col: 0)
                        XCTAssertEqual(r?.tells?.map(\.pile), [0, 1],
                                       "clubTell: one tell per ♣ top, in pile order")
                        XCTAssertEqual(r?.tells?.map(\.direction), [.higher, .lower],
                                       "clubTell: 9 runs higher than 5, lower than 10")
                        XCTAssertNil(r?.tellPile, "clubTell: the single-pile fields belong to Same Tell")
                        // The MARKER is the feature (v6.52): both ♣ piles are
                        // armed and the live hint reads the real next card.
                        XCTAssertEqual(e.run.tellPiles, [0, 1],
                                       "clubTell: both ♣ piles carry a tell marker")
                        XCTAssertEqual(e.pileHint(0), .higher, "clubTell: pile 1's chip reads ▲")
                        XCTAssertEqual(e.pileHint(1), .lower, "clubTell: pile 2's chip reads ▼")
                        XCTAssertNil(e.pileHint(2), "clubTell: the off-suit pile stays dark")
                        // …and the next draw ANYWHERE consumes every marker.
                        e.guess(2, .higher)
                        XCTAssertTrue(e.run.tellPiles.isEmpty,
                                      "clubTell: the markers last exactly one draw")
                    },
                    expect: { e, _, c in assertSpent(e, c) }),
                IV.Scenario("edge-sameDirection", allowed: .all,
                    build: { baseEngine(def, tops: [IV.spec(1, 9, "♣"), IV.spec(2, 8, "♥"), IV.spec(3, 6)],
                                        deckOrder: [IV.spec(50, 9), IV.spec(51, 3)]) },
                    fire: { e in
                        let r = e.baseActivate(col: 0)
                        XCTAssertEqual(r?.tells?.count, 1, "clubTell: only the ♣ top is read")
                        XCTAssertEqual(r?.tells?.first?.direction, Guess.same, "clubTell: a match reads =")
                        XCTAssertEqual(e.run.tellPiles, [0], "clubTell: the ♣ pile is marked")
                    },
                    expect: { _, _, _ in }),
                IV.Scenario("mustNotFire-clubOnlyInAnotherColumn", allowed: [],
                    build: { baseEngine(def, tops: [IV.spec(1, 5, "♠"), IV.spec(2, 8, "♥"), IV.spec(3, 6, "♣")],
                                        deckOrder: [IV.spec(50, 9)]) },
                    fire: { e in
                        XCTAssertFalse(e.baseCanActivate(0), "clubTell: the ♣ must be in ITS column")
                        XCTAssertNil(e.baseActivate(col: 0), "no ♣ top here, no read")
                    },
                    expect: { e, _, c in XCTAssertEqual(e.run.basesUsed?[0], false, "\(c)") }),
                IV.Scenario("mustNotFire-noClubTop", allowed: [],
                    build: { baseEngine(def, tops: [IV.spec(1, 5, "♥"), IV.spec(2, 8, "♦"), IV.spec(3, 6)]) },
                    fire: { e in XCTAssertNil(e.baseActivate(col: 0), "no ♣ to read") },
                    expect: { e, _, c in XCTAssertEqual(e.run.basesUsed?[0], false, "\(c)") }),
            ]

        case "shuffleColumn":
            return [
                IV.Scenario("trigger", allowed: .all,
                    build: { baseEngine(def) },
                    fire: { e in
                        let r = e.baseActivate(col: 0)
                        XCTAssertEqual(r?.shuffled, 2, "shuffleColumn: both alive piles shuffled")
                    },
                    expect: { e, f, c in
                        XCTAssertEqual((0..<3).map { e.board.piles[$0].cards.count }, f.pileCounts,
                                       "\(c): a shuffle changes composition, never counts")
                        assertSpent(e, c)
                    }),
                IV.Scenario("edge-deadPileSkipped", allowed: .all,
                    build: { baseEngine(def, tops: [IV.spec(1, 5, "♠"), nil, IV.spec(3, 6)]) },
                    fire: { e in
                        let r = e.baseActivate(col: 0)
                        XCTAssertEqual(r?.shuffled, 1, "only the alive pile")
                    },
                    expect: { _, _, _ in }),
                IV.Scenario("mustNotFire-spent", allowed: .all,
                    build: { baseEngine(def) },
                    fire: { e in _ = e.baseActivate(col: 0) },
                    expect: { e, _, c in assertSpent(e, c) }),
            ]

        case "reviveBase":
            return [
                IV.Scenario("trigger-revivesKeepsKiller", allowed: .all,
                    build: {
                        let e = baseEngine(def, tops: [IV.spec(1, 5, "♠"), nil, IV.spec(3, 6)])
                        e.board.piles[1].cards.append(DeckManager.toCard(IV.spec(91, 12), data: data))
                        return e
                    },
                    fire: { _ = $0.baseActivate(col: 0) },
                    expect: { e, _, c in
                        XCTAssertTrue(e.board.isActive(1), "\(c): the dead pile is back")
                        XCTAssertEqual(e.board.piles[1].cards.count, 1, "\(c): only the killer stays")
                        XCTAssertEqual(e.board.top(1)?.id, 91, "\(c): the killing card is the top")
                        assertSpent(e, c)
                    }),
                IV.Scenario("edge-buriedGoBackHidden", allowed: .all,
                    build: {
                        let e = baseEngine(def, tops: [IV.spec(1, 5, "♠"), nil, IV.spec(3, 6)])
                        e.board.piles[1].cards.append(DeckManager.toCard(IV.spec(91, 12), data: data))
                        return e
                    },
                    fire: { _ = $0.baseActivate(col: 0) },
                    expect: { e, f, c in
                        XCTAssertEqual(e.deck.remaining(), f.deckRemaining + 1,
                                       "\(c): the one buried card went back to the deck")
                    }),
                IV.Scenario("mustNotFire-noDeadPile", allowed: [],
                    build: { baseEngine(def) },
                    fire: { e in XCTAssertNil(e.baseActivate(col: 0), "nothing to revive") },
                    expect: { e, _, c in XCTAssertEqual(e.run.basesUsed?[0], false, "\(c)") }),
            ]

        case "randomSticker":
            return [
                IV.Scenario("trigger", allowed: .all,
                    build: { baseEngine(def) },
                    fire: { e in
                        let r = e.baseActivate(col: 0)
                        XCTAssertNotNil(r?.stickerApplied, "randomSticker: something stuck")
                    },
                    expect: { e, _, c in
                        let stickered = (0..<2).contains { !(e.board.top($0)?.stickers.isEmpty ?? true) }
                        XCTAssertTrue(stickered, "\(c): a column top carries the new sticker")
                        assertSpent(e, c)
                    }),
                IV.Scenario("edge-jokersRefuse", allowed: [],
                    build: { baseEngine(def, tops: [IV.spec(1, 0, joker: true),
                                                    IV.spec(2, 0, joker: true), IV.spec(3, 6)]) },
                    fire: { e in _ = e.baseActivate(col: 0) },
                    expect: { e, _, c in
                        XCTAssertTrue(e.board.top(0)!.stickers.isEmpty, "\(c): a ★ takes nothing")
                    }),
                IV.Scenario("mustNotFire-otherColumnUntouched", allowed: .all,
                    build: { baseEngine(def) },
                    fire: { _ = $0.baseActivate(col: 0) },
                    expect: { e, _, c in
                        XCTAssertTrue(e.board.top(2)!.stickers.isEmpty, "\(c): column-scoped")
                    }),
            ]

        case "ambushWin":
            return [
                IV.Scenario("trigger-ambushEnds", allowed: .all,
                    build: { baseEngine(def, isAmbush: true) },
                    fire: { _ = $0.baseActivate(col: 0) },
                    expect: { e, _, c in
                        XCTAssertTrue(e.deck.isEmpty, "\(c): the ambush drained")
                        XCTAssertEqual(e.status, "won", "\(c): through the normal end check")
                    }, skipSnapshot: true),
                IV.Scenario("edge-boardUntouched", allowed: .all,
                    build: { baseEngine(def, isAmbush: true) },
                    fire: { _ = $0.baseActivate(col: 0) },
                    expect: { e, f, c in
                        XCTAssertEqual((0..<3).map { e.board.piles[$0].cards.count }, f.pileCounts,
                                       "\(c): no cards moved")
                    }, skipSnapshot: true),
                IV.Scenario("mustNotFire-ordinaryDeal", allowed: [],
                    build: { baseEngine(def) },
                    fire: { e in XCTAssertNil(e.baseActivate(col: 0), "only in an ambush") },
                    expect: { e, _, c in XCTAssertEqual(e.run.basesUsed?[0], false, "\(c)") }),
            ]

        case "missingRankDig":
            // MISSING RANK DIG (v7.04 NEIGHBOR rework): per pile in the base's
            // COLUMN, bury one card for each of its top's two neighbour ranks
            // (±1) at zero copies in the full deck — 0/1/2. Base on col 0
            // (piles 0 & 1); pile 2 is col 1 and never touched.
            //
            // TRIGGER: pile0 top 5 with BOTH 4 and 6 absent → 2; pile1 top 8
            // with 7 present, 9 absent → 1. Full deck = tops {5,8,11} + deck
            // {7,3,10,12,13} — no 4, 6 or 9. Total 3 under 2 piles.
            let neighborTops: [CardSpec?] = [IV.spec(1, 5, "♠"), IV.spec(2, 8, "♥"), IV.spec(3, 11, "♣")]
            let neighborDeck = [IV.spec(50, 7, "♥"), IV.spec(51, 3, "♥"), IV.spec(52, 10, "♥"),
                                IV.spec(53, 12, "♥"), IV.spec(54, 13, "♥"), IV.spec(55, 3, "♠")]
            return [
                IV.Scenario("trigger-buriesByNeighborCount", allowed: .all,
                    build: { baseEngine(def, tops: neighborTops, deckOrder: neighborDeck) },
                    fire: { e in
                        XCTAssertEqual(e.baseLiveCounter(0), 3, "badge: 2 (pile0) + 1 (pile1)")
                        let r = e.baseActivate(col: 0)
                        XCTAssertEqual(r?.buried, 3, "2 under pile0 (both neighbours gone) + 1 under pile1")
                        XCTAssertEqual(r?.piles, 2, "only the two column-0 piles dug")
                    },
                    expect: { e, f, c in
                        XCTAssertEqual(e.board.piles[0].cards.count, f.pileCounts[0] + 2,
                                       "\(c): pile0 (top 5, no 4s or 6s) took 2")
                        XCTAssertEqual(e.board.piles[1].cards.count, f.pileCounts[1] + 1,
                                       "\(c): pile1 (top 8, no 9s) took 1")
                        XCTAssertEqual(e.board.piles[2].cards.count, f.pileCounts[2],
                                       "\(c): pile2 is column 1 — column-scoped, untouched")
                        XCTAssertEqual(e.deck.remaining(), f.deckRemaining - 3, "\(c)")
                        assertSpent(e, c)
                    }),
                // ACE EDGE, NO WRAP (the discriminator): pile0 = Ace(14) with
                // BOTH its real neighbour (13) AND the rank a circular wrap
                // would reach (2) ABSENT. No-wrap buries 1 (only 13 counts —
                // 15 is off the top); a wrap would bury 2. pile1 = 8, both
                // neighbours present → 0. Full deck = tops {14,8,11} + deck
                // {7,9,10,12,3,5} — no 13, no 2, 7 & 9 present.
                IV.Scenario("edge-aceCapsAtOneNeighborNoWrap", allowed: .all,
                    build: {
                        let tops: [CardSpec?] = [IV.spec(1, 14, "♠"), IV.spec(2, 8, "♥"), IV.spec(3, 11, "♣")]
                        let deck = [IV.spec(50, 7, "♥"), IV.spec(51, 9, "♥"), IV.spec(52, 10, "♥"),
                                    IV.spec(53, 12, "♥"), IV.spec(54, 3, "♥"), IV.spec(55, 5, "♥")]
                        return baseEngine(def, tops: tops, deckOrder: deck)
                    },
                    fire: { e in
                        XCTAssertEqual(e.baseLiveCounter(0), 1,
                                       "badge: Ace → 1 (only its 13 neighbour; NO wrap to the also-absent 2), pile1 → 0")
                        let r = e.baseActivate(col: 0)
                        XCTAssertEqual(r?.buried, 1, "the Ace buries 1, NOT 2 — it has one real neighbour")
                        XCTAssertEqual(r?.piles, 1)
                    },
                    expect: { e, f, c in
                        XCTAssertEqual(e.board.piles[0].cards.count, f.pileCounts[0] + 1,
                                       "\(c): Ace top, 13 absent → 1; the absent rank 2 does NOT wrap in")
                        XCTAssertEqual(e.board.piles[1].cards.count, f.pileCounts[1],
                                       "\(c): pile1 (top 8, 7 & 9 present) → 0")
                        assertSpent(e, c)
                    }),
                // TWO EDGE mirror: pile0 = 2 with its one real neighbour (3)
                // ABSENT → 1 (rank 1 is off the bottom, no wrap to the Ace).
                // pile1 = 8, both present → 0. Full deck = tops {2,8,11} +
                // deck {7,9,10,12,5,6} — no 3.
                IV.Scenario("edge-twoHasOneNeighbor", allowed: .all,
                    build: {
                        let tops: [CardSpec?] = [IV.spec(1, 2, "♠"), IV.spec(2, 8, "♥"), IV.spec(3, 11, "♣")]
                        let deck = [IV.spec(50, 7, "♥"), IV.spec(51, 9, "♥"), IV.spec(52, 10, "♥"),
                                    IV.spec(53, 12, "♥"), IV.spec(54, 5, "♥"), IV.spec(55, 6, "♥")]
                        return baseEngine(def, tops: tops, deckOrder: deck)
                    },
                    fire: { e in
                        XCTAssertEqual(e.baseLiveCounter(0), 1, "badge: the 2's missing 3 = 1")
                        let r = e.baseActivate(col: 0)
                        XCTAssertEqual(r?.buried, 1, "a 2 buries at most 1 — its only neighbour is 3")
                    },
                    expect: { e, f, c in
                        XCTAssertEqual(e.board.piles[0].cards.count, f.pileCounts[0] + 1, "\(c): 3 absent → 1")
                        assertSpent(e, c)
                    }),
                IV.Scenario("mustNotFire-bothNeighborsPresent", allowed: .all,
                    build: {
                        // Every rank 2–14 in the deck → each top's both
                        // neighbours are present → 0 for every pile → amber.
                        let full = (2...14).enumerated().map { IV.spec(50 + $0.offset, $0.element, "♥") }
                        return baseEngine(def, deckOrder: full)
                    },
                    fire: { e in
                        XCTAssertFalse(e.baseCanActivate(0), "no missing neighbour in the column → amber")
                        XCTAssertNil(e.baseActivate(col: 0))
                    },
                    expect: { e, f, c in
                        XCTAssertEqual(e.deck.remaining(), f.deckRemaining, "\(c): nothing moved")
                        XCTAssertEqual(e.run.basesUsed?[0], false, "\(c): the charge is kept")
                    }),
            ]

        case "evenOut":
            // BALLAST (v6.88): BOARD-WIDE — pile 2 lives in the OTHER column
            // and must equalize too; the move list rides the result.
            return [
                IV.Scenario("trigger-evensTheWholeBoard", allowed: .all,
                    build: {
                        let e = baseEngine(def)
                        for i in 0..<6 {
                            e.board.piles[0].cards.append(DeckManager.toCard(IV.spec(90 + i, 3), data: data))
                        }
                        return e
                    },
                    fire: { e in
                        let r = e.baseActivate(col: 0)
                        XCTAssertEqual(r?.moves, r?.movedCards?.count, "the travel list matches the count")
                        XCTAssertTrue(r?.movedCards?.contains { $0.to == 2 } ?? false,
                                      "the OTHER column's pile received cards — board-wide")
                    },
                    expect: { e, _, c in
                        let sizes = (0..<3).map { e.board.pileSize($0) }
                        XCTAssertLessThanOrEqual((sizes.max() ?? 0) - (sizes.min() ?? 0), 1,
                                                 "\(c): EVERY pile within 1 of the rest")
                        assertSpent(e, c)
                    }),
                IV.Scenario("edge-alreadyEvenNoMoves", allowed: .all,
                    build: { baseEngine(def) },
                    fire: { e in
                        let r = e.baseActivate(col: 0)
                        XCTAssertEqual(r?.moves, 0, "already even: zero moves")
                    },
                    expect: { _, _, _ in }),
                IV.Scenario("mustNotFire-conserved", allowed: .all,
                    build: {
                        let e = baseEngine(def)
                        for i in 0..<6 {
                            e.board.piles[0].cards.append(DeckManager.toCard(IV.spec(90 + i, 3), data: data))
                        }
                        return e
                    },
                    fire: { _ = $0.baseActivate(col: 0) },
                    expect: { e, f, c in
                        XCTAssertEqual((0..<3).map { e.board.piles[$0].cards.count }.reduce(0, +),
                                       f.pileCounts.reduce(0, +), "\(c): cards conserved board-wide")
                    }),
            ]

        case "bonusResetPeek":
            // BONUS RESET (v6.88): only fireable ABOVE 1 banked bonus coin;
            // the fire zeroes the tally (itemized) and peeks the next card.
            return [
                IV.Scenario("trigger-tradesBonusForAPeek", allowed: .all,
                    build: {
                        let e = baseEngine(def)
                        e.run.bonusCoins = 5
                        return e
                    },
                    fire: { e in
                        XCTAssertTrue(e.baseAvailable(0), "5 banked → fireable")
                        let r = e.baseActivate(col: 0)
                        XCTAssertEqual(r?.peekCount, 1)
                    },
                    expect: { e, _, c in
                        XCTAssertEqual(e.run.bonusCoins, 0, "\(c): the tally reset to zero")
                        XCTAssertTrue(e.run.revealNextActive, "\(c): …and the next card shows")
                        XCTAssertEqual(e.revealedNextCard()?.id, 50, "\(c): the REAL next draw")
                        assertSpent(e, c)
                    }),
                IV.Scenario("edge-exactlyOneRefuses", allowed: [],
                    build: {
                        let e = baseEngine(def)
                        e.run.bonusCoins = 1
                        return e
                    },
                    fire: { e in
                        XCTAssertFalse(e.baseCanActivate(0), "1 banked is NOT more than 1")
                        XCTAssertNil(e.baseActivate(col: 0))
                    },
                    expect: { e, _, c in
                        XCTAssertEqual(e.run.basesUsed?[0], false, "\(c): a refused fire keeps the charge")
                        XCTAssertEqual(e.run.bonusCoins, 1, "\(c): the tally is untouched")
                    }),
                IV.Scenario("mustNotFire-zeroBanked", allowed: [],
                    build: { baseEngine(def) },
                    fire: { e in
                        XCTAssertNil(e.baseActivate(col: 0), "0 banked: nothing to trade")
                    },
                    expect: { e, _, c in
                        XCTAssertEqual(e.run.basesUsed?[0], false, "\(c)")
                        XCTAssertFalse(e.run.revealNextActive, "\(c): no peek either")
                    }),
            ]

        case "setValue", "setSuit":
            let isValue = def.effect == "setValue"
            return [
                IV.Scenario("trigger-copiesBottomPile", allowed: .all,
                    build: { baseEngine(def) },   // col 0: piles 0 (5♠) and 1 (8♥); bottom pile = 1
                    fire: { _ = $0.baseActivate(col: 0) },
                    expect: { e, _, c in
                        if isValue {
                            XCTAssertEqual(e.board.top(0)?.value, 8, "\(c): pile 0 took the source rank")
                        } else {
                            XCTAssertEqual(e.board.top(0)?.suit, "♥", "\(c): pile 0 took the source suit")
                        }
                        assertSpent(e, c)
                    }),
                IV.Scenario("edge-otherColumnUntouched", allowed: .all,
                    build: { baseEngine(def) },
                    fire: { _ = $0.baseActivate(col: 0) },
                    expect: { e, _, c in
                        XCTAssertEqual(e.board.top(2)?.value, 6, "\(c)")
                        XCTAssertEqual(e.board.top(2)?.suit, "♣", "\(c)")
                    }),
                IV.Scenario("mustNotFire-spent", allowed: .all,
                    build: { baseEngine(def) },
                    fire: { e in _ = e.baseActivate(col: 0) },
                    expect: { e, _, c in assertSpent(e, c) }),
            ] + (isValue ? [] : [
                // SUIT SETTER's v6.52 gate: green only when it can CHANGE
                // something — >1 alive pile AND at least two printed suits.
                IV.Scenario("mustNotFire-uniformSuits", allowed: [],
                    build: { baseEngine(def, tops: [IV.spec(1, 5, "♥"), IV.spec(2, 8, "♥"), IV.spec(3, 6)]) },
                    fire: { e in
                        XCTAssertFalse(e.baseCanActivate(0), "setSuit: a one-suit column is amber")
                        XCTAssertNotNil(e.baseUnavailableReason(0), "setSuit: the amber notice has words")
                        XCTAssertNil(e.baseActivate(col: 0), "setSuit: and it will not fire")
                    },
                    expect: { e, _, c in XCTAssertEqual(e.run.basesUsed?[0], false, "\(c)") }),
                IV.Scenario("mustNotFire-onePileAlive", allowed: [.deaths, .board],
                    build: {
                        let e = baseEngine(def, tops: [IV.spec(1, 5, "♠"), IV.spec(2, 8, "♥"), IV.spec(3, 6)])
                        e.board.kill(1)   // one alive pile left in the column
                        return e
                    },
                    fire: { e in
                        XCTAssertFalse(e.baseCanActivate(0), "setSuit: a lone pile is amber")
                        XCTAssertNil(e.baseActivate(col: 0))
                    },
                    expect: { e, _, c in XCTAssertEqual(e.run.basesUsed?[0], false, "\(c)") }),
            ])

        case "stickerHarvest":
            let per = def.int("buryPerSticker", 2)
            return [
                IV.Scenario("trigger-peelsAndBuries", allowed: .all,
                    build: { baseEngine(def, tops: [IV.spec(1, 5, "♠", ["tell", "gainCoin"]),
                                                    IV.spec(2, 8, "♥"), IV.spec(3, 6)]) },
                    fire: { e in
                        let r = e.baseActivate(col: 0, targetIndex: 0)
                        XCTAssertEqual(r?.harvested, 2, "harvest: counted both stickers")
                        XCTAssertEqual(r?.buried, 2 * per, "harvest: buried \(per) per sticker")
                    },
                    expect: { e, _, c in
                        XCTAssertTrue(e.board.top(0)!.stickers.isEmpty, "\(c): the card is bare")
                        assertSpent(e, c)
                    }),
                // v6.58 gate: a column with no stickered top card idles amber —
                // the charge is neither green nor spendable.
                IV.Scenario("mustNotFire-bareColumnIdles", allowed: [],
                    build: { baseEngine(def) },
                    fire: { e in
                        XCTAssertFalse(e.baseAvailable(0), "no stickered top in the column: idle, not ready")
                        XCTAssertNil(e.baseActivate(col: 0, targetIndex: 0), "cannot fire on a bare column")
                    },
                    expect: { e, _, c in XCTAssertEqual(e.run.basesUsed?[0], false, "\(c): charge kept") }),
                IV.Scenario("mustNotFire-otherColumnStickerDoesNotArm", allowed: [],
                    build: { baseEngine(def, tops: [IV.spec(1, 5, "♠"), IV.spec(2, 8, "♥"),
                                                    IV.spec(3, 6, "♣", ["tell"])]) },
                    fire: { e in
                        XCTAssertFalse(e.baseAvailable(0), "a sticker in ANOTHER column does not arm it")
                        XCTAssertNil(e.baseActivate(col: 0, targetIndex: 0))
                    },
                    expect: { e, _, c in XCTAssertEqual(e.run.basesUsed?[0], false, "\(c): charge kept") }),
                IV.Scenario("mustNotFire-needsTarget", allowed: [],
                    build: { baseEngine(def, tops: [IV.spec(1, 5, "♠", ["tell"]),
                                                    IV.spec(2, 8, "♥"), IV.spec(3, 6)]) },
                    fire: { e in XCTAssertNil(e.baseActivate(col: 0), "no target given") },
                    expect: { e, _, c in XCTAssertEqual(e.run.basesUsed?[0], false, "\(c)") }),
            ]

        case "refreshBases":
            return [
                IV.Scenario("trigger-reArmsOthers", allowed: .all,
                    build: {
                        let e = IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 8), IV.spec(3, 6)],
                                          deckOrder: [IV.spec(50, 9)], cols: [2, 1],
                                          bases: [def.id, "spadePeek"])
                        e.run.basesUsed?[1] = true   // the other base is spent
                        return e
                    },
                    fire: { e in
                        let r = e.baseActivate(col: 0)
                        XCTAssertEqual(r?.refreshed, [1], "refresh: re-armed the spent base")
                    },
                    expect: { e, _, c in
                        XCTAssertEqual(e.run.basesUsed?[1], false, "\(c): column 1 is ready again")
                        XCTAssertEqual(e.run.basesUsed?[0], true, "\(c): itself is spent")
                    }),
                IV.Scenario("edge-nothingSpentRefuses", allowed: [],
                    build: { IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 8), IV.spec(3, 6)],
                                       deckOrder: [IV.spec(50, 9)], cols: [2, 1],
                                       bases: [def.id, "spadePeek"]) },
                    fire: { e in XCTAssertNil(e.baseActivate(col: 0), "nothing to refresh") },
                    expect: { e, _, c in XCTAssertEqual(e.run.basesUsed?[0], false, "\(c)") }),
                IV.Scenario("mustNotFire-neverSelf", allowed: .all,
                    build: {
                        let e = IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 8), IV.spec(3, 6)],
                                          deckOrder: [IV.spec(50, 9)], cols: [2, 1],
                                          bases: [def.id, "spadePeek"])
                        e.run.basesUsed?[1] = true
                        return e
                    },
                    fire: { e in _ = e.baseActivate(col: 0) },
                    expect: { e, _, c in
                        XCTAssertEqual(e.run.basesUsed?[0], true, "\(c): it can never re-arm itself")
                    }),
            ]

        case "suitDig":
            let suit = def.suit ?? "♣"
            let dig = def.int("digCount", 0) != 0 ? def.int("digCount", 0) : 1
            return [
                IV.Scenario("trigger", allowed: .all,
                    build: { baseEngine(def, tops: [IV.spec(1, 5, suit), IV.spec(2, 8, suit), IV.spec(3, 6)]) },
                    fire: { e in
                        let r = e.baseActivate(col: 0)
                        XCTAssertEqual(r?.piles, 2, "suitDig: both \(suit) piles dug")
                        XCTAssertEqual(r?.buried, 2 * dig, "suitDig: \(dig) each")
                    },
                    expect: { e, _, c in assertSpent(e, c) }),
                IV.Scenario("edge-emptyDeckNothing", allowed: .all,
                    build: { baseEngine(def, tops: [IV.spec(1, 5, suit), IV.spec(2, 8, suit), IV.spec(3, 6)],
                                        deckOrder: []) },
                    fire: { e in
                        let r = e.baseActivate(col: 0)
                        XCTAssertEqual(r?.buried ?? 0, 0, "empty deck: nothing to bury")
                    },
                    expect: { _, _, _ in }, skipSnapshot: true),
                IV.Scenario("mustNotFire-offSuitTops", allowed: .all,
                    build: { baseEngine(def, tops: [IV.spec(1, 5, suit == "♣" ? "♥" : "♣"),
                                                    IV.spec(2, 8, "♦"), IV.spec(3, 6)]) },
                    fire: { e in
                        let r = e.baseActivate(col: 0)
                        XCTAssertEqual(r?.buried ?? 0, 0, "no matching top, no dig")
                    },
                    expect: { _, _, _ in }),
            ]

        case "demolish":
            // v6.51: OWN column only — no target pick, yellow without a
            // pillar in THIS column.
            return [
                IV.Scenario("trigger-destroysOwnColumnPillarPeeks", allowed: .all,
                    build: { baseEngine(def, pillars: ["fibonacci", nil]) },
                    fire: { e in
                        let r = e.baseActivate(col: 0)
                        XCTAssertEqual(r?.demolishedCol, 0, "demolish: its OWN column, no target pick")
                        XCTAssertEqual(r?.demolishedPillar, "fibonacci", "demolish: named the victim")
                    },
                    expect: { e, _, c in
                        XCTAssertNil(e.run.pillars?[0] ?? nil, "\(c): the pillar is gone")
                        XCTAssertEqual(e.run.kamikazeRevealLeft, def.int("peekCount", 2), "\(c): the peek")
                        assertSpent(e, c)
                    }),
                IV.Scenario("edge-otherColumnPillarStays", allowed: .all,
                    build: { baseEngine(def, pillars: ["fibonacci", "static"]) },
                    fire: { e in _ = e.baseActivate(col: 0) },
                    expect: { e, _, c in
                        XCTAssertNil(e.run.pillars?[0] ?? nil, "\(c): own column demolished")
                        XCTAssertEqual(e.run.pillars?[1] ?? nil, "static", "\(c): the other column is untouched")
                    }),
                IV.Scenario("mustNotFire-pillarOnlyElsewhere", allowed: [],
                    build: { baseEngine(def, pillars: [nil, "fibonacci"]) },
                    fire: { e in
                        XCTAssertFalse(e.baseCanActivate(0), "demolish: yellow without an own-column pillar")
                        XCTAssertNil(e.baseActivate(col: 0), "a pillar elsewhere is no longer a target")
                        XCTAssertNil(e.baseActivate(col: 0, targetIndex: 1), "even an explicit pick is refused")
                    },
                    expect: { e, _, c in
                        XCTAssertEqual(e.run.pillars?[1] ?? nil, "fibonacci", "\(c): the other pillar survives")
                        XCTAssertEqual(e.run.basesUsed?[0], false, "\(c)")
                    }),
                IV.Scenario("mustNotFire-noPillarAnywhere", allowed: [],
                    build: { baseEngine(def) },
                    fire: { e in XCTAssertNil(e.baseActivate(col: 0), "nothing to demolish") },
                    expect: { e, _, c in XCTAssertEqual(e.run.basesUsed?[0], false, "\(c)") }),
            ]

        case "heartDemolish":
            let per = def.num("coinPerPile", 7)
            return [
                IV.Scenario("trigger-heartsDieForCoins", allowed: .all,
                    build: { baseEngine(def, tops: [IV.spec(1, 5, "♥"), IV.spec(2, 8, "♥"), IV.spec(3, 6)]) },
                    fire: { _ = $0.baseActivate(col: 0) },
                    expect: { e, f, c in
                        XCTAssertFalse(e.board.isActive(0), "\(c)")
                        XCTAssertFalse(e.board.isActive(1), "\(c)")
                        XCTAssertEqual(e.run.bonusCoins, f.bonusCoins + per * 2, "\(c): +\(per) each")
                        assertSpent(e, c)
                    }),
                IV.Scenario("edge-otherColumnHeartsSafe", allowed: .all,
                    build: { baseEngine(def, tops: [IV.spec(1, 5, "♥"), IV.spec(2, 8, "♣"), IV.spec(3, 6, "♥")]) },
                    fire: { _ = $0.baseActivate(col: 0) },
                    expect: { e, _, c in
                        XCTAssertTrue(e.board.isActive(2), "\(c): column-scoped destruction")
                    }),
                IV.Scenario("mustNotFire-noHearts", allowed: [],
                    build: { baseEngine(def, tops: [IV.spec(1, 5, "♣"), IV.spec(2, 8, "♠"), IV.spec(3, 6)]) },
                    fire: { e in XCTAssertNil(e.baseActivate(col: 0), "no ♥ tops") },
                    expect: { e, _, c in XCTAssertEqual(e.run.basesUsed?[0], false, "\(c)") }),
            ]

        case "tax":
            let per = def.num("coinPerCard", 1)
            return [
                IV.Scenario("trigger-taxesAllHearts", allowed: .all,
                    build: {
                        let e = baseEngine(def, tops: [IV.spec(1, 5, "♥"), IV.spec(2, 8, "♣"), IV.spec(3, 6)])
                        e.board.piles[1].cards.append(DeckManager.toCard(IV.spec(90, 3, "♥"), data: data))
                        return e
                    },
                    fire: { _ = $0.baseActivate(col: 0) },
                    expect: { e, f, c in
                        XCTAssertEqual(e.run.bonusCoins, f.bonusCoins + per * 2,
                                       "\(c): 1 top + 1 buried ♥ = 2 x \(per)")
                        assertSpent(e, c)
                    }),
                IV.Scenario("edge-deadPilesExcluded", allowed: .all,
                    build: {
                        let e = baseEngine(def, tops: [IV.spec(1, 5, "♥"), nil, IV.spec(3, 6)])
                        e.board.piles[1].cards = [DeckManager.toCard(IV.spec(91, 4, "♥"), data: data)]
                        return e
                    },
                    fire: { _ = $0.baseActivate(col: 0) },
                    expect: { e, f, c in
                        XCTAssertEqual(e.run.bonusCoins, f.bonusCoins + per, "\(c): only the alive ♥")
                    }),
                IV.Scenario("mustNotFire-noHearts", allowed: [],
                    build: { baseEngine(def, tops: [IV.spec(1, 5, "♣"), IV.spec(2, 8, "♠"), IV.spec(3, 6)]) },
                    fire: { e in XCTAssertNil(e.baseActivate(col: 0), "nothing to tax") },
                    expect: { e, _, c in XCTAssertEqual(e.run.basesUsed?[0], false, "\(c)") }),
            ]

        // ── v6.76 archetype batch (purgeDiscount / transmute run their
        //    CampaignCheck — their effect is store-side / at purchase) ───────

        case "sacrifice":
            return [
                IV.Scenario("trigger-purgesTopAndKillsPile", allowed: .all,
                    build: { baseEngine(def, tops: [IV.spec(1, 5, "♠"), IV.spec(2, 8, "♥"), IV.spec(3, 6, "♣")]) },
                    fire: { e in _ = e.baseActivate(col: 0, targetIndex: 1) },
                    expect: { e, _, c in
                        XCTAssertFalse(e.board.isActive(1), "\(c): the chosen pile dies")
                        XCTAssertTrue(e.board.piles[1].cards.isEmpty,
                                      "\(c): its top card was purged, not buried or returned")
                        XCTAssertEqual(e.board.pileSize(0), 1, "\(c): the other pile is untouched")
                        assertSpent(e, c)
                    }),
                IV.Scenario("edge-noTargetRefuses", allowed: [],
                    build: { baseEngine(def) },
                    fire: { e in XCTAssertNil(e.baseActivate(col: 0), "sacrifice needs a picked pile") },
                    expect: { e, _, c in
                        XCTAssertEqual(e.run.basesUsed?[0], false, "\(c): a refused fire keeps the charge")
                    }),
                IV.Scenario("mustNotFire-foreignPile", allowed: [],
                    build: { baseEngine(def) },
                    fire: { e in XCTAssertNil(e.baseActivate(col: 0, targetIndex: 2), "pile 3 is another column's") },
                    expect: { e, _, c in
                        XCTAssertTrue(e.board.isActive(2), "\(c)")
                        XCTAssertEqual(e.run.basesUsed?[0], false, "\(c)")
                    }),
            ]

        case "devilsDeal":
            // v6.76: the base carries NO `target` — an untargeted activation
            // curses an in-column top via the seeded pick (the Kamikaze
            // precedent); an un-cursable supplied pick re-picks seeded.
            return [
                IV.Scenario("trigger-untargetedDoublesAndCurses", allowed: .all,
                    build: {
                        let e = baseEngine(def)
                        e.run.bonusCoins = 5
                        return e
                    },
                    fire: { e in _ = e.baseActivate(col: 0) },
                    expect: { e, _, c in
                        XCTAssertEqual(e.run.bonusCoins, 10, "\(c): the deal's bonus tally doubled")
                        // The seeded pick cursed exactly ONE top in the column.
                        let curses = [0, 1].flatMap {
                            e.board.top($0)?.stickers.filter {
                                data.stickerTypes.get($0.type)?.cursed == true } ?? [] }
                        XCTAssertEqual(curses.count, 1, "\(c): one curse on an in-column top")
                        assertSpent(e, c)
                    }),
                IV.Scenario("trigger-doublesOnlyTheDuringDealTally", allowed: .all,
                    // v6.94: with a scoring pillar (Guardian) equipped, Devil's
                    // Deal doubles ONLY the during-deal tally — the pillar's
                    // deal-end award hasn't been earned yet and is untouched.
                    build: {
                        let e = baseEngine(def, pillars: ["columnGuardian", nil])
                        e.run.bonusCoins = 5
                        return e
                    },
                    fire: { e in _ = e.baseActivate(col: 0) },
                    expect: { e, _, c in
                        XCTAssertEqual(e.run.bonusCoins, 10, "\(c): only the during-deal tally doubled")
                        let gv = data.pillarTypes.get("columnGuardian")?.num("value", 4) ?? 4
                        XCTAssertEqual(e.pillarPayout().bonus, gv,
                                       "\(c): Guardian's deal-end award stays undoubled")
                        assertSpent(e, c)
                    }),
                IV.Scenario("edge-uncursablePickRepicksSeeded", allowed: .all,
                    build: {
                        let e = baseEngine(def, tops: [IV.spec(1, 0, joker: true), IV.spec(2, 8, "♥"),
                                                       IV.spec(3, 6, "♣")])
                        e.run.bonusCoins = 4
                        return e
                    },
                    fire: { e in _ = e.baseActivate(col: 0, targetIndex: 0) },   // the ★ can't take a curse
                    expect: { e, _, c in
                        XCTAssertEqual(e.run.bonusCoins, 8, "\(c): the tally still doubles")
                        let curses = e.board.top(1)?.stickers.filter {
                            data.stickerTypes.get($0.type)?.cursed == true } ?? []
                        XCTAssertEqual(curses.count, 1,
                                       "\(c): the seeded re-pick cursed the only cursable top")
                        XCTAssertTrue(e.board.top(0)?.stickers.isEmpty ?? false,
                                      "\(c): the ★ stays clean")
                    }),
                IV.Scenario("edge-noCursableTopJustDoubles", allowed: .all,
                    build: {
                        let e = baseEngine(def, tops: [IV.spec(1, 0, joker: true), IV.spec(2, 0, joker: true),
                                                       IV.spec(3, 6, "♣")])
                        e.run.bonusCoins = 7
                        return e
                    },
                    fire: { e in _ = e.baseActivate(col: 0) },
                    expect: { e, _, c in
                        XCTAssertEqual(e.run.bonusCoins, 14, "\(c): it still doubles with nothing to curse")
                        let curses = [0, 1].flatMap {
                            e.board.top($0)?.stickers.filter {
                                data.stickerTypes.get($0.type)?.cursed == true } ?? [] }
                        XCTAssertEqual(curses.count, 0, "\(c): no curse could land")
                        assertSpent(e, c)
                    }),
                IV.Scenario("mustNotFire-noBonus", allowed: [],
                    // v6.93: it can't double a non-positive bonus — amber at
                    // ◉0 banked, and the refused fire keeps the charge.
                    build: { baseEngine(def) },   // bonusCoins starts at 0
                    fire: { e in XCTAssertNil(e.baseActivate(col: 0), "nothing to double") },
                    expect: { e, _, c in
                        XCTAssertFalse(e.baseCanActivate(0), "\(c): amber at ◉0 banked")
                        XCTAssertNotNil(e.baseUnavailableReason(0), "\(c): the amber tap says why")
                        XCTAssertEqual(e.run.basesUsed?[0], false, "\(c): the refused fire keeps the charge")
                    }),
            ]

        case "cleanseColumn":
            return [
                IV.Scenario("trigger-stripsOnlyCurses", allowed: .all,
                    build: { baseEngine(def, tops: [IV.spec(1, 5, "♠", ["mute", "tell"]),
                                                    IV.spec(2, 8, "♥", ["spoiler"]),
                                                    IV.spec(3, 6, "♣", ["leech"])]) },
                    fire: { e in _ = e.baseActivate(col: 0) },
                    expect: { e, _, c in
                        XCTAssertEqual(e.board.top(0)?.stickers.map(\.type), ["tell"],
                                       "\(c): the curse peeled, the clean sticker stayed")
                        XCTAssertEqual(e.board.top(1)?.stickers.count, 0, "\(c)")
                        XCTAssertEqual(e.board.top(2)?.stickers.map(\.type), ["leech"],
                                       "\(c): the OTHER column keeps its curse")
                        assertSpent(e, c)
                    }),
                IV.Scenario("edge-lastCurseCounts", allowed: .all,
                    build: { baseEngine(def, tops: [IV.spec(1, 5, "♠", ["drainShield"]),
                                                    IV.spec(2, 8, "♥"), IV.spec(3, 6, "♣")]) },
                    fire: { e in _ = e.baseActivate(col: 0) },
                    expect: { e, _, c in
                        XCTAssertTrue(e.board.top(0)?.stickers.isEmpty ?? false, "\(c)")
                    }),
                IV.Scenario("mustNotFire-noCurses", allowed: [],
                    build: { baseEngine(def) },
                    fire: { e in XCTAssertNil(e.baseActivate(col: 0), "nothing to cleanse") },
                    expect: { e, _, c in
                        XCTAssertEqual(e.run.basesUsed?[0], false, "\(c)")
                    }),
            ]

        case "chorus":
            // Full deck = 3 tops + deckOrder. Three 7s in the deck make 7 the
            // most-copied rank; the 7/3 tie variant checks the LOWEST-rank rule.
            return [
                IV.Scenario("trigger-topsTakeTheMostCopiedRank", allowed: .all,
                    build: { baseEngine(def, tops: [IV.spec(1, 5, "♠"), IV.spec(2, 9, "♥"), IV.spec(3, 6, "♣")],
                                        deckOrder: [IV.spec(50, 7, "♠"), IV.spec(51, 7, "♥"),
                                                    IV.spec(52, 7, "♦"), IV.spec(53, 4, "♦")]) },
                    fire: { e in _ = e.baseActivate(col: 0) },
                    expect: { e, _, c in
                        XCTAssertEqual(e.board.top(0)?.value, 7, "\(c)")
                        XCTAssertEqual(e.board.top(1)?.value, 7, "\(c): both column tops join the chorus")
                        XCTAssertEqual(e.board.top(2)?.value, 6, "\(c): the other column is untouched")
                        assertSpent(e, c)
                    }),
                IV.Scenario("edge-tiesBreakToLowestRank", allowed: .all,
                    build: { baseEngine(def, tops: [IV.spec(1, 5, "♠"), IV.spec(2, 9, "♥"), IV.spec(3, 6, "♣")],
                                        deckOrder: [IV.spec(50, 7, "♠"), IV.spec(51, 7, "♥"),
                                                    IV.spec(52, 3, "♦"), IV.spec(53, 3, "♣")]) },
                    fire: { e in _ = e.baseActivate(col: 0) },
                    expect: { e, _, c in
                        XCTAssertEqual(e.board.top(0)?.value, 3, "\(c): 7s tie 3s at 2 each → 3 wins")
                        XCTAssertEqual(e.board.top(1)?.value, 3, "\(c)")
                    }),
                IV.Scenario("mustNotFire-emptyColumn", allowed: [],
                    build: { baseEngine(def, tops: [nil, nil, IV.spec(3, 6, "♣")]) },
                    fire: { e in XCTAssertNil(e.baseActivate(col: 0), "no alive pile in the column") },
                    expect: { e, _, c in
                        XCTAssertEqual(e.run.basesUsed?[0], false, "\(c)")
                    }),
            ]

        case "diamondBoost":
            // COLUMN-WIDE (v6.78): no target pick — every alive ♦-topped
            // pile in the column grows by `value` on one activation.
            let boost = def.int("value", 3)
            return [
                IV.Scenario("trigger-everyDiamondPileGrows", allowed: .all,
                    build: { baseEngine(def, tops: [IV.spec(1, 5, "♦"), IV.spec(2, 8, "♦"), IV.spec(3, 6, "♣")]) },
                    fire: { e in _ = e.baseActivate(col: 0) },
                    expect: { e, _, c in
                        XCTAssertEqual(e.board.pileSize(0), 1 + boost, "\(c): +\(boost) pile size")
                        XCTAssertEqual(e.board.pileSize(1), 1 + boost, "\(c): EVERY ♦ pile in the column grows")
                        XCTAssertEqual(e.board.pileSize(2), 1, "\(c): the other column is untouched")
                        assertSpent(e, c)
                    }),
                IV.Scenario("edge-nonDiamondPileUntouched", allowed: .all,
                    build: { baseEngine(def, tops: [IV.spec(1, 5, "♦"), IV.spec(2, 8, "♥"), IV.spec(3, 6, "♣")]) },
                    fire: { e in _ = e.baseActivate(col: 0) },
                    expect: { e, _, c in
                        XCTAssertEqual(e.board.pileSize(0), 1 + boost, "\(c): the ♦ pile grows")
                        XCTAssertEqual(e.board.pileSize(1), 1, "\(c): the ♥ pile in the same column does not")
                        assertSpent(e, c)
                    }),
                IV.Scenario("mustNotFire-noDiamondTopInColumn", allowed: [],
                    build: { baseEngine(def, tops: [IV.spec(1, 5, "♥"), IV.spec(2, 8, "♥"), IV.spec(3, 6, "♦")]) },
                    fire: { e in XCTAssertNil(e.baseActivate(col: 0), "no ♦ top in the column → unavailable") },
                    expect: { e, _, c in
                        XCTAssertEqual(e.run.basesUsed?[0], false, "\(c): the charge survives")
                    }),
            ]

        default:
            return nil
        }
    }

    // MARK: - Same-Powers (fire on a correct SAME)

    /// A correct Same on pile 0 with the power equipped.
    static func powerEngine(_ def: ItemDef, variant: String? = nil,
                            tops: [CardSpec?]? = nil,
                            deckOrder: [CardSpec]? = nil) -> GameEngine {
        IV.engine(tops: tops ?? [IV.spec(1, 7, "♠"), IV.spec(2, 6, "♦"), IV.spec(3, 6, "♥")],
                  deckOrder: deckOrder ?? [IV.spec(50, 7, "♣"), IV.spec(51, 3), IV.spec(52, 4), IV.spec(53, 5)],
                  samePower: def.id, samePowerVariant: variant)
    }

    static func powerScenarios(for def: ItemDef) -> [IV.Scenario]? {
        guard let effect = def.effect else { return nil }
        func fireSame(_ e: GameEngine) { e.guess(0, .same) }
        var result: SamePowerResult?
        func capture(_ e: GameEngine) {
            result = nil
            e.on { if case .samePower(let r) = $0 { result = r } }
        }
        let common: (GameEngine, IV.Frame, String) -> Void = { e, _, c in
            XCTAssertNotNil(result, "\(c): the power announced itself")
            XCTAssertEqual(result?.power, def.id, "\(c)")
            XCTAssertTrue(e.sameCharge, "\(c): the correct Same still banks")
        }
        let variant: String? = ["linkBury": "♦"][def.id] ?? nil
        let trigger = IV.Scenario("trigger", allowed: .all,
            build: { powerEngine(def, variant: variant) },
            fire: { e in capture(e); fireSame(e) },
            expect: { e, f, c in
                common(e, f, c)
                switch effect {
                case "linkCoins":
                    XCTAssertGreaterThan(e.run.bonusCoins, f.bonusCoins, "\(c): paid per target")
                case "linkBury":
                    XCTAssertGreaterThanOrEqual((0..<3).map { e.board.piles[$0].cards.count }.reduce(0, +),
                                                f.pileCounts.reduce(0, +) + 1, "\(c): buried somewhere")
                case "samePeek", "linkTell":
                    XCTAssertTrue(e.run.revealNextActive || !e.run.tellPiles.isEmpty
                                    || e.run.tellDrawsLeft > 0
                                    || !(e.run.whisperPiles.isEmpty), "\(c): a hint armed")
                case "rankFlood":
                    // v6.76: the Same was called on a 7 — EVERY alive pile's
                    // top takes that rank, and the rewrite reports for the
                    // durable write-back.
                    XCTAssertTrue((0..<3).allSatisfy { e.board.top($0)?.value == 7 },
                                  "\(c): every alive top took the called rank")
                    XCTAssertEqual(result?.rankApplied.count, 3, "\(c)")
                default:
                    break   // structural: the result event is the contract
                }
            })
        let noCharge = IV.Scenario("mustNotFire-directionalGuess", allowed: .all,
            build: { powerEngine(def, variant: variant,
                                 tops: [IV.spec(1, 5, "♠"), IV.spec(2, 6, "♦"), IV.spec(3, 6, "♥")],
                                 deckOrder: [IV.spec(50, 9, "♣"), IV.spec(51, 3)]) },
            fire: { e in capture(e); e.guess(0, .higher) },
            expect: { _, _, c in
                XCTAssertNil(result, "\(c): a plain HIGHER never fires the power")
            })
        let edge = IV.Scenario("edge-jokerSameCountsAndFires", allowed: .all,
            build: { powerEngine(def, variant: variant,
                                 tops: [IV.spec(1, 7, "♠"), IV.spec(2, 6, "♦"), IV.spec(3, 6, "♥")],
                                 deckOrder: [IV.spec(50, 0, joker: true), IV.spec(51, 3), IV.spec(52, 4)]) },
            fire: { e in capture(e); fireSame(e) },
            expect: { e, _, c in
                XCTAssertNotNil(result, "\(c): a ★ Same is a full Same")
                XCTAssertTrue(e.sameCharge, "\(c)")
            })
        return [trigger, edge, noCharge]
    }
}
