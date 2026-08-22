# Reachability study — dedicated deck-shaping (v6.75 working tree, branch ios-port)

Question: with spending dedicated ENTIRELY to deck-shaping, what can a player
realistically reach on (a) single-suit concentration, (b) zero 2s, (c) four
ranks with 3+ copies — by end of stage 1 / 2 / 3?

## Method

Real web engine, headless: `tests/_harness.mjs`'s `loadGame()` drives
`CampaignState`/`RunMap`/`Economy`/`ItemData` directly (script:
`/tmp/reach/sim.mjs`, results: `/tmp/reach/results-{fresh,established}.json`).
250 seeded climbs per policy per unlock variant; seeds are paired across
policies (`setSeedOverride` → same seed = same map for every policy). Deck:
**Mamma / Regular** — the 13-heart start named in the task (Pinky/Smith/Lammy
are `altSuits` mixed starts, which only make concentration harder).

What is REAL (engine-run): map generation (genV5 full-map), all route/branch
structure, face-up pickup cards and revealed +2 packs, pickup/pack grants
(incl. Blank specials and suit-pool-exhaustion duplicates), store shelf rolls
(class-first weights, typeCap, unlock pre-filter), all prices, the Purge
ladder (5, +2 per purchase per climb), reroll ladder (5, +1 per reroll per
visit), sticker buy/apply (Change-Suit ×4 at 1 coin, rankUp at 1 coin,…),
store card slots (3c, all four suits) and card-pack swaps, mystery events
(engine-applied outcomes incl. coin caches, card windfalls, curses).

What is MODELLED (stated loudly):
- **Deals are auto-won.** No GameEngine play; a dedicated/skilled player is
  assumed to clear everything. Coin income per deal is the REAL deterministic
  payout `Economy.dealFlat(phase+1, RunMap.difficultyScore(node), isBoss)` —
  the same call the UI's payout path makes — so income is exact given
  survival. Ambushes pay their 15-coin bounty. No item-driven income (Payout
  stickers etc.) is modelled: income is if anything a slight underestimate.
  All numbers are "given you survive the climb".
- **Mystery "cast" outcomes no-op.** items.js `mystery.weights` gives ~35% of
  mystery weight to the Old Joker / Beheaded Queen / Just a Two outcomes,
  which the v6.75 web build does not implement (`applyMysteryEvent` returns
  null → the node just completes, as the real web build does). On native
  these add curses/thefts/shop modifiers; minor deck-shape impact.
- **The Large Card Pack never appears on the web.** Its gate
  (`dealsWonRegular: 15`) is a native-only stat with no web reader
  (index.html ITEM_UNLOCK_STATS comment: "never unlocked on the web"). The
  only shoppable card pack in this study is the Small Card Pack (reveal 3,
  keep 1, 2c). Native players also get the 5-keep-2 pack at 4c — shaping
  rates slightly better than reported here.
- "fresh" vs "established" (all web-readable lifetime stats maxed) variants
  differ negligibly for shaping — every deck-shaping tool (Change-Suit,
  rankUp, Wild Suit, Small Card Pack, Purge, card slot) is ungated on the
  web. Numbers below are the fresh variant unless noted.

## Structural facts that drive everything

- **The map forces growth.** The generator validates EVERY route at
  ≥ `minRouteCards` = 11 card-adds per stage (index.html GEN_CONFIG). You
  cannot route around pickups/packs entirely: ~11–15 cards per stage is the
  floor, and for Mamma every map card is the phase suit (♦ then ♣ then ♠) —
  never ♥. Starting from 13♥, a full climb force-feeds ~33–45 off-suit cards.
- Purging one stage's forced growth (~11 cards) costs 5+7+…+25 ≈ **165 coins
  — more than an entire climb's income** (see below). Purge cannot reverse
  the map's dilution; it can only trim.
- Store sticker supply of a SPECIFIC Change-Suit is ~2.1% per sticker slot
  (weight 25 of 1175 unlocked pool; sticker class = 40% of rolled slots).
  Even a dedicated shopper (~7 store visits, ~16 shelves incl. ~9 paid
  rerolls per climb) sees a given Change-to-X a median of **0–1 times per
  climb** (max ~3–6). Wild Suit and rankUp are 4× commoner (8.5%/slot;
  median 2/climb, max 7–10). Suit conversion supply is the binding
  constraint, not the 1-coin price.
- Store card slots (3c) and Small Card Packs (2c) draw ALL FOUR suits
  ungated — the only way to ADD hearts after run start.
- Income (dedicated policy, median): **~26 coins by end of stage 1, ~70
  cumulative by stage 2, ~130 by stage 3** (deals only get richer later:
  dealFlat = 2 + stage×(1+rating)).

## (a) Suit concentration — max single-suit share of the full deck

| policy | st1 med (p75, max) | ≥50% | st2 med (p75, max) | ≥50% | st3 med (p75, max) | ≥50% |
|---|---|---|---|---|---|---|
| control (grow naturally, no shopping) | .594 (.618, .649) | **100%** | .404 (.420, .471) | 0% | .297 (.309, .343) | 0% |
| dedicated ♥ (avoid growth, convert/swap/purge) | .520 (.548, .639) | 95% | .395 (.421, .579) | **2.4%** | .340 (.370, .521) | **0.8%** |
| dedicated wave (ride the current phase suit) | .613 (.643, .727) | 99.6% | .386 (.409, .488) | 0% | .317 (.344, .474) | 0% |

- The natural max suit is the STAGE-1 phase suit ♦ for any growing route
  (mode ♦ in 249/250 control runs at st1): the map itself hands you a
  ~60% single-suit deck at end of stage 1 — for free, no dedication.
- Past stage 1 the forced multi-suit growth wins. Even total dedication
  (median spend by st3: ~105 of ~135 earned coins; 4 purges, 5 swap-ins,
  ~16 shelves shopped) holds only ~34% (fixed-♥) / ~32% (wave) at st3.
  The two ≥50% st3 runs in 250 spent 107–110 coins (nearly the whole
  climb's income) and landed exactly 50.0–52.1%.

**Verdict: 50%+ printed-suit share is a STAGE-1 condition.** Free at end of
stage 1; ~2% of fully-dedicated climbs at stage 2; effectively unreachable
(~1 in 250, all-in) at stage 3. A 40% threshold sits at the dedicated
player's stage-2 median (and is the control's stage-2 median too); 30–35%
is the stage-3 reality.

## (b) Zero 2s

The starting 13-heart deck has exactly one 2 (2♥); further 2s enter via
pickups/packs (~1/13 of suited grants) — but map pickups are FACE-UP, so a
dedicated player routes around visible 2s and fixes the rest.

- **100% of dedicated climbs reach zero-2s; 93% (233/250) get there during
  STAGE 1**, the rest during stage 2.
- Cost to first zero: median **3 coins**, p75 5, p90 8, max 24 (one rankUp
  at 1c turning 2→3, one swap-in over the 2 at 3c, one Blank/mystery
  removal, or one Purge at 5c — whichever the shop offers first).
- It is upkeep, not one-and-done: stage-end zero rates are 72% / 82% / 80%
  (fresh 2s drip in between store visits; always fixable at the next shop
  for a couple of coins). A natural unshaped 66-card deck holds ~5 2s.

**Verdict: trivially reachable — stage 1, ~3–8 coins, against a stage-1
income of ~26. Any item gated on "no 2s in deck" is an EARLY-game item whose
condition costs almost nothing; price the item's power, not the gate.**

## (c) Four ranks with 3+ copies

| policy | st1: ≥4 ranks at 3+ | med ranks at 3+ | st2 | st3 |
|---|---|---|---|---|
| control | 94% | 5 | 100% (med 11) | 100% (med 13) |
| dedicated rank-buying | 94% | 6 | 100% (med 12) | 100% (med 13) |
| dedicated ♥ purging (worst case) | 63% | 4 | 100% (med 8) | 100% (med 11) |

No dedication needed: once a suit's 13 uniques are claimed, further grants
mint duplicates, so 3+ piles form on their own. For reference, the stiffer
"4 ranks with **4+** copies" bar: 5% at st1, 99% at st2, 100% at st3.

**Verdict: not a gate.** Four ranks at 3+ is free by end of stage 1 for any
growing deck and universal by stage 2 even for a purge-happy suit deck. As
an archetype prerequisite it prices as ~free; if the design wants a real
deck-building commitment, use 4 ranks × 4+ (a stage-2 gate) or a
5-copies/X-ranks shape.

## Price-tuning implications for the archetype items

1. **50%-suit pillar: do not gate at 50% printed suit for mid/late play.**
   At 50% the condition is free in stage 1 and ~unreachable afterwards — an
   item gated on it either reads as stage-1-only or as dead. Options:
   threshold ≈40% (the stage-2 dedicated band) for a mid-game item;
   ≈30–35% for a late-game one; or let Wild Suit cards count (supply ~2/
   climb at 1c — a real but bounded lever, currently 4× more available than
   any specific Change-Suit). If it must stay 50%+, price it EARLY and
   expect it to fall off after stage 1.
2. **No-2s items: price as early-game.** The gate costs ~3–8 coins and is
   met by stage 1–2 at 100% under minimal dedication. It should never carry
   a premium for "build-around difficulty" — it carries none.
3. **4-ranks×3+ pile-size items: the condition is free** (94% by stage 1
   with zero dedication). Any price/positioning should assume the gate is
   always on from stage 2. For an actual commitment test, gate on 4+ copies
   (stage-2 onset) or higher counts.
4. **Purge (5, +2/climb) is the only deck-SHRINKING tool and it cannot
   outrun forced growth** (~165 coins to purge one stage's worth). If
   future archetypes want small-deck or high-concentration play to be
   viable past stage 1, the lever is cheaper/free removals (Blanks, mystery
   Purges) or a lower `minRouteCards` — not prices on the buying side.
5. Change-Suit stickers at 1 coin are price-correct but **starved at
   weight 25** (0–1 sightings/climb of the one you want). If suit-shaping
   archetypes ship, their enabler is the shelf weight, not the coin cost.

## Caveats

- Deals auto-won (see Method): all results are conditioned on surviving;
  income excludes item bonuses (mild underestimate) and ambush bounties are
  counted (+15). Real players also lose climbs sometimes — these are
  reachability ceilings given competent play, not average outcomes.
- Web-engine reality (v6.75): mystery cast outcomes no-op; Large Card Pack
  never in pool (native-only gate). Both noted in Method; both slightly
  conservative for shaping rates on native.
- Pinky/Smith/Lammy (mixed 4/3/3/3 starts) make suit concentration strictly
  harder than the Mamma numbers above.
- Policies are heuristics, not optimal play: the ≥50% rates are lower
  bounds on "achievable", but the gap to optimal is small — the binding
  constraints (forced 11+ adds/stage, shelf supply) are structural.
