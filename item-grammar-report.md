# Item Grammar Classification — v6.89 active roster

Analysis only; nothing changed. Source of truth: `items.js` as of commit `432de2d`,
cross-checked against engine handlers where text was ambiguous. Table:
**`item-grammar.csv`** (119 rows: 25 stickers · 53 pillars · 30 bases · 11 powers —
111 DEAL, 8 META).

A structural note used throughout: CONDITION values split into two families —
**archetype conditions** (persistent player state: purse, deck composition,
loadout) and **availability gates** (transient board state, almost all on manual
bases: "a ♥-topped pile exists"). The counts keep them separate because a gate
is a fire-timing constraint, not a build-around.

## 2a. Condition benches (deal items)

Archetype conditions (the build-arounds):

| condition | items | action spread | verdict |
|---|---|---|---|
| board: matching top (suit) — the v6.85 conditional stickers | 7 | 7 (bury, coins, size, redistribute, save, shuffle, tell) | **healthy** |
| <10 coins (Pauper) | 4 | 4 (bury, peek, size, tell) | **healthy** |
| deck: missing ranks (Empty Ranks) | 3 | 3 (bury, coins, size) | **healthy** |
| board: matching top (rank) | 2 | 2 (peek, save) | thin (2 more held back: rechargeSameShield, activateSamePower) |
| deck: most-common rank | 2 (rankShield, eightStart) | 2 (save, size) | thin |
| loadout: missing pillar / missing base | 1 + 1 (the Scouts) | peek only | **thin & same-action** |
| deck: no 2s | 1 (royalSanctuary; +Bouncer's meta certainty) | save | thin |
| deck: majority suit | 1 (suitMajoritySafe) | save | thin |
| deck: scarcest suit | 1 (suitShield) | save | thin |
| board: pile at size 1 | 1 (sizeOneDiamonds) | size | thin |
| card: 3+ stickers on lander | 1 (denseBury) | bury | thin |
| loadout: only pillar (greedy) / center pillar (ditto) | 1 + 1 | coins / mirror | thin |
| run: bonus coins > 1 | 1 (bonusResetPeek) | peek | thin |
| survival states (all/none/one pile alive) | 3 (columnGuardian, lastLicks, insurance) | coins only | thin & same-action |

Availability gates (bases; fire-timing, not archetypes): ♠-top (kamikaze), all-♠
(spadePeek), dead pile (Phoenix, linkRevive), ♥-top (heartDemolish), ♥ cards
(tax), ♣-top (clubOracle), ♦-top (diamondBoost), cursed top (cleanseColumn),
stickered top (stickerHarvest), spent base (refreshBases), own pillar (demolish),
Same-Power present/absent (activateSame / lonePeek), non-boss (lastResort),
ambush (ambushOut) — one item each, by design.

**CONDITION = NONE: 64 of 111 deal items** (58%), spread over 17 actions.

## 2b. Trigger histogram

manual base fire 28 · card lands 17 · specific suit lands 15 · Same called 13 ·
on apply (setup) 10 · deal end 8 · specific rank lands 6 · pile died 3 ·
passive 3 · streak 2 · deal start 2 · on purchase 2 · pile-reaches-N 1 ·
cursed card lands 1.

**Unused triggers named by the grammar (zero items):** pile shuffled · bonus
coin earned · base fired · card purged · sticker peeled · pile revived.

## 2c. Action histogram

peek 15 · earn coins 14 · safety/save 11 · bury 11 · pile size 10 · change
identity (rank) 8 · change identity (suit) 7 · tell 5 · shuffle 4 · charge
shield/power 4 · revive 4 · remove sticker/curse 4 · purge 4 · redistribute 3 ·
add sticker 3 · score exclusion 2 · win deal 2 · extra pile 1 · mirror pillar 1 ·
recharge base 1.

## 2d. Tradeoffs

Real cost beyond the slot: **23 of 111** — curse a card 13 (the conditional
stickers + cover punish + Devil's Deal), kill pile 3, return-to-deck 2, destroy
pillar/base 2, peel stickers 1, lose purse 1, lose bonus 1. occupies-slot-only:
11 (every Same-Power). NONE: 77.

## 2e. Meta items (8)

store economy 5 (bulkRate, freebie, rareHunter, purgeFlatFive, purgeDiscount) ·
map & encounters 2 (Bouncer, Queen-Finder) · store+run hybrid 1 (firstFree).
Condition-gated 2 (the two certainty branches — and even their 30% base is
unconditional) · unconditional 6.

## 3. Autoplay lint

59 of 111 deal items have no condition and no real tradeoff. After the honest
exceptions —

- **setup stickers (10):** which-card placement is the decision (the placement
  log exists to measure exactly this);
- **manual bases with a gate or cost elsewhere:** timing is a real decision,
  but note the gateless, costless subset below;
- **Same-Powers (11):** the single slot + calling Sames is the decision;
- **on-purchase deck shapers (purgeRank, transmute):** the buy is the decision —

the residue is the structural autoplay core, and it is almost entirely
**passive pillars (24)**: heartBounty, columnTieSafe, envy, streakBank,
streakTribute, fourthSeat, revive, flypaper, underdog, crowdFavorite,
stickerCount, queensEye, royalCourt, lastRites, wildAces, diamondAnchor,
diamondDistribution, diamondDupeSize, stickerCurseWard, finalPilePurge,
sameTolNear, sameTolRoyal, sameTolSuit, eightPeek (+ curseHarvest, which at
least wants curses to exist). Plus five **gateless costless bases** where even
timing barely matters: shuffleColumn, randomSticker, evenOut, sameTell,
rechargeSame — and the two rank/suit setters + chorus, whose timing IS
meaningful (board state) but which cost nothing.

**Meta autoplay:** 6 of 8 meta items are unconditional pure discounts/boosters
(bulkRate, freebie, rareHunter, purgeFlatFive, purgeDiscount, firstFree) —
always worth buying if the price is right; no decision after purchase. Only the
Bouncer and Queen-Finder carry any condition, and only in their upgrade branch.

## 4. Overload lint (3 of condition+modifier+tradeoff filled)

gainCoin · heavy · diamondSnob (condition + per-suit scaling + conversion risk —
the three densest conditional stickers) · stickerHarvest · heartDemolish ·
lastResort · bonusResetPeek. Seven items; the conditional-sticker trio shares
one template so it reads as one rule learned thrice — the real illegibility
candidates are stickerHarvest and lastResort, whose three clauses are all
bespoke.

## 5. Latent combos

**Feeds that exist (action → consumer):**
- add sticker (flypaper, randomSticker, linkSticker) → denseBury's 3+-sticker
  trigger; stickerHarvest's gate and scaling.
- add curse (Devil's Deal; Payout/Anchor cover punish; every conditional
  conversion) → curseHarvest's cursed-lands trigger; cleanseColumn /
  sameCleanseAll gates; Curse Ward's whole reason to exist.
- kill pile (kamikaze, sacrifice, heartDemolish) → pile-died consumers
  (lastRites, secondWind, finalPilePurge) and the dead-pile gates (Phoenix,
  linkRevive, revive pillar); also lastLicks/insurance survival conditions.
- purge (sacrifice, linkPurge, finalPilePurge, purgeRank) → every
  deck-composition condition: missing ranks (Empty Ranks ×3), no-2s
  (royalSanctuary + Bouncer certainty), scarcest suit, most-common rank,
  majority suit. The deepest feed chain in the game.
- change identity (transmute, chorus, setSuit/setValue, rankFlood) → the same
  composition conditions from the other side (transmute literally manufactures
  suitMajoritySafe's condition), plus every suit/rank landing trigger.
- pile size (9 producers) → revive's pile-reaches-10 trigger; Payout's
  pile-size payout; the min-pile score itself.
- charge shield/power (4 producers) → the entire Same-called trigger family.
- earn coins → **anti-feed**: breaks the Pauper condition (4 items); feeds
  emptyPurse's modifier.
- Meta→deal: purgeDiscount/purgeFlatFive/bulkRate/firstFree make purges cheap →
  accelerate every composition condition above; Queen-Finder's certainty branch
  is itself a most-common-rank **consumer** on the map side.

**Actions that feed no trigger (missing hooks):** bury (11 producers, zero
consumers since Excavator retired — the largest orphaned output in the game) ·
shuffle (no pile-shuffled trigger) · revive (no pile-revived trigger) ·
peek/tell (20 producers, nothing keys on "while revealed") · redistribute ·
score exclusion. The grammar's pile shuffled / card purged / sticker peeled /
bonus-coin-earned / base-fired / pile-revived triggers all exist as hooks with
zero items.

## 6. Readings (one page)

**Vocabulary added** (all used consistently in the CSV):
- CONDITIONS: `board: matching top (suit)` and `(rank)` — the v6.85/86
  conditional stickers are a board-read gate the original grammar had no slot
  for; the base availability-gate family (`board: ♥-topped pile in column`
  etc., one per gated base); `loadout: only equipped pillar` (greedy),
  `center pillar equipped` (ditto), `own pillar equipped` (demolish),
  `other spent base` (refreshBases); `card: 3+ stickers on lander` (denseBury),
  `card: stickered/cursed top in column` (harvest/cleanse); `encounter: ambush
  deal only`; `boss: non-boss deal only`; `run: bonus coins > 1`;
  `deck: scarcest suit` (split from majority/most-common — scarcity is its own
  archetype).
- TRIGGERS: `on apply (setup)` (the 10 identity stickers act at placement, not
  in the deal); `correct-guess streak (column)`; `pile reaches N cards`;
  `cursed card lands`; `deal start`.
- ACTIONS: `change card identity (rank/suit)` (8+7 items — the single biggest
  unlisted action); `score exclusion` (anchor, diamondAnchor); `win deal`
  (lastResort, ambushOut); `extra pile`; `mirror pillar`; `recharge base`.
  Curse Ward is filed under remove sticker/curse as *prevention* (noted).
- MODIFIERS: `# alive piles` (linkCoins); `# suit cards (column)` (tax);
  `# cards in pile` (Payout); `# streak length`.

**3 biggest gaps:** (1) the loadout-absence archetype — playing *without*
pillars/bases has exactly two items, both peek, both stickers (the Scouts) —
greedy is its only cousin; (2) rank-side board reads — 2 active items against
the suit side's 7, with the other two rank conditionals still held back;
(3) suit-majority + suit-scarcity — one item each, already flagged in the
v6.87 bench report, and the purge economy feeds them harder than anything else.

**3 biggest pileups:** (1) manual-fire → peek: six bases whose entire identity
is the gate or price on the same peek (kamikaze, spadePeek, demolish,
emptyPurse, lonePeek, bonusResetPeek); (2) Same-called → one-shot board effect:
13 items on one trigger, differentiated only by the action wheel; (3)
suit-lands-in-column → small reward: heartBounty/envy/crowdFavorite/underdog/
the Pauper four/the Empty Ranks three — twelve near-isomorphic column rewards.

**Text-vs-code mismatches found while classifying:**
- donate & evenOut say "make piles **equal**" — code equalizes to *within 1*
  and only moves buried cards (a 1-card pile donates nothing).
- chorus / setValue / rankFlood say "every top card" — jokers/blanks are
  silently skipped (correct behavior, unstated).
- Guard's text omits the last-pile exemption (no other alive pile = no save,
  no conversion).
- sameTolSuit is missing its family's "a survived Same counts as a full
  correct Same" sentence though the code promotes identically to its three
  siblings.
- Flypaper/Wild Sticker/Link Sticker pools still include identity-mutating
  rank/suit stickers — consistent with their text ("random sticker") but
  inconsistent with the v6.86 rule that acquired cards are never repainted;
  in-deal grants can repaint. Flagged, not judged.
