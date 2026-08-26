# Principle-1 Audit (v6.84) — every item vs the "shift the puzzle" test

**The test** (Slay the Spire designers): a synergy where you just "get a bonus
for having both" is not enough. At least one half must work alone, and the
other half must SHIFT THE PUZZLE — change how the player plays — not merely
add a bigger number. No tradeoff + no change to play = an autoplay decision.

**Sticker-specific test:** is WHICH CARD you place it on a real decision? A
sticker whose placement never matters fails even if the effect is fine.

**What "changes how you play" means in this game:** it changes which pile you
guess on, which call you make (esp. when you dare a Same), what you bury or
purge, how you shape the deck between deals, or it makes you accept a risk
you'd otherwise refuse. Coins are the weakest currency to judge by: a flat
coin drip changes nothing at the moment of play.

Analysis is on the item set as of v6.83 (post-archetype batch, post-gating).
Cursed stickers are excluded — they are inflicted, never chosen or placed, so
"autoplay decision" doesn't apply; they're environment, and good at it.

---

## STICKERS

| Item | Verdict | Rationale |
|---|---|---|
| +1 Rank / −1 Rank | **CONDITIONAL** | Placement is a real rank decision ONLY when a rank-caring item is equipped (Rank Shield, Prime, Crazy Eights, Rank Roots, Same-family) or you're building duplicates for Sames; alone, shifting a 7 to an 8 changes nothing you can act on. Enabler frequency: moderate (rank-carers are common post-v6.76). |
| +2 / −2 Rank | **CONDITIONAL** | Same as ±1 with a stronger push toward the Ace/2 poles — poles are genuinely playable (extreme tops are easy calls), so this is the better half of the family. Same enablers. |
| Random Rank | **FAILS** | You give up the one thing rank stickers offer (choosing the rank); placement is any card you dislike, outcome is a coin flip you can't play around before it lands. |
| Change to ♠/♥/♦/♣ | **PASSES** | The deck-shaping workhorse: which card you convert decides your suit balance (guards, Majority Rule, Void Tribute, stage suits, mono-suit plans). Placement = the decision. |
| Random Suit | **FAILS** | The shaping tool with the shaping removed. No plan survives a random suit; placement is "whichever card I care least about." |
| Wild Suit | **PASSES** | Counts as every suit — placement decides which card becomes the universal key (guard triggers, suit pillars, Majority Rule numerator). Real choice, no downside, but the choice itself is rich. |
| Same-Safe (tieSafe) | **PASSES** | Placement wants a rank with many living duplicates, and it CHANGES CALLS (you dare Sames/anything onto it). The model sticker. |
| Guards (♠♥♦♣ Immunity) | **PASSES** | Suit is pinned, but rank placement matters: the guard is most valuable on the ranks that make the worst tops (mids), and it changes calls — you deliberately route risky guesses through the guarded pile. |
| Payout (extraCoin) | **CONDITIONAL** | Pays only if the carrier tops an alive pile at deal end → you want it on a card you can KEEP on top (extreme ranks), and you play to protect that pile. Weak but real. Enabler: none needed, but the incentive is small. |
| Bonus Coin (gainCoin) | **FAILS** | +2 coins when it lands. Fires identically wherever it rides among hearts; no call changes; the archetypal autoplay drip. |
| Last Coin (deathBounty) | **PASSES (barely)** | Pays on a KILL — a perverse incentive is still an incentive: you can sacrifice its pile on purpose. Placement barely matters, but use does. |
| Anchor | **PASSES** | Excludes its pile from the smallest-pile score → you deliberately STARVE that pile. Changes which pile you feed all deal. |
| Heavy / Massive | **CONDITIONAL** | +size is score, and score is optional prestige. Placement (a card that'll sit in a big pile) is marginal. Enabler: caring about score at all; on a score push it passes. |
| Collector | **PASSES** | Wants a card you'll stack more stickers on → creates the "mule card" plan and interacts with the 4-cap. Placement is the whole game. |
| Compound | **PASSES** | Grows per correct, RESETS on a wrong guess — a streak tradeoff that punishes your risky calls everywhere. Changes how bold you play while it's live. |
| Scout (revealNext) | **PASSES** | A peek when it lands; ♠-pinned, placement thin — but peeks change the next call by definition. Passes on effect; placement is admittedly interchangeable. |
| Shuffle | **PASSES** | An OFFERED choice at landing (take the shuffle or keep the order) — a real decision every fire. |
| Donate | **PASSES** | Moves buried cards to the smallest pile — score-shaping you time deliberately. |
| Quick Bury | **CONDITIONAL** | Great effect (burying is survival), but any ♣ is the same home — placement interchangeable. Passes the puzzle test as an effect, fails the sticker-placement test. Enabler for placement: none exists. |
| Twin Spark | **PASSES** | Peek if ANOTHER pile's top matches its rank → placement wants a duplicated rank AND you keep matching tops alive. Rank + board play. |
| Loose Change | **FAILS** | Random 0–3 coins on landing. No placement logic, no call changes. |
| Snowball Bury | **PASSES** | Streak-grown bury with reset-on-wrong — Compound's tradeoff plus a bury payoff. |
| Deep Pockets | **CONDITIONAL** | Coins per cards LEFT in deck — an honest anti-synergy with the bury school (real tension!), but on its own it's a drip. Enabler: a bury build to be in tension WITH; otherwise autoplay. |
| Pillar Scout / Base Scout | **PASSES** | Peek only in an item-free column — the placement AND the loadout constraint interact (you keep a column deliberately bare: a real cost). |
| Spade Snob | **PASSES** | Bidirectional ♠-touch peek: you route ♠ landings into it on purpose. |
| Heart Snob | **FAILS** | Same trigger as Spade Snob but the payoff is +2 coins — the trigger asks nothing of you because the reward changes nothing. |
| Diamond Snob | **PASSES** | Board-wide shuffle on ♦ touch — a big, sometimes UNWANTED effect; you place and route around it carefully. |
| Club Snob | **PASSES** | Bury on ♣ touch — routing decision like Spade Snob, survival payoff. |
| Heart Choir | **FAILS** | Coins per ♥ top when it lands. You can't meaningfully arrange ♥ tops for a one-shot landing; drip. |
| Diamond Ripple | **PASSES** | Shuffles every ♦-topped pile when it lands — you WANT or FEAR this depending on board state; timing/placement matters. |
| Rank Roots (clubRoots) | **PASSES** | Buries under every rank-matching top — placement wants a heavily duplicated rank; pairs with rank shaping. The v6.78 redesign made this one pass. |
| Spade Whispers | **PASSES** | Hints scale with other ♠ tops → you maintain ♠ tops, changing keeps/calls. |
| Tell | **PASSES** | A permanent tell on its pile — you guess THROUGH that pile constantly; placement = which card returns to top most. |
| Recharge Shield | **PASSES** | Refills the Same shield on landing — you spend the shield more freely knowing a refill is buried in the deck. Changes risk appetite. |
| Tap Power | **CONDITIONAL** | Fires your Same-Power on landing — entirely as good as the equipped power. Enabler: a power worth firing off-Same (Rank Flood, Burrow: yes; Dividend: it's a coin drip again). |

## PILLARS

| Item | Verdict | Rationale |
|---|---|---|
| Heart Bonus | **FAILS** | +1 coin per ♥ landing in the column. You don't route ♥s for 1 coin; pure drip. |
| Column Tie-Safe | **PASSES** | Ties safe in-column → you call INTO ties there; changes calls every deal. |
| Last Licks | **PASSES (perverse)** | Pays if the column is WIPED — you can deliberately feed a column to death. A real (if grim) plan. |
| Guardian | **PASSES** | Pays if ALL survive → you protect that column's calls. The pay-side twin of Last Licks; the pair is a genuine choice. |
| Clean Bury (clubTribute) | **CONDITIONAL** | Bury per sticker-FREE ♣ landing — tension with the sticker economy (real), but the no-sticker condition mostly just happens. Enabler: a ♣-dense deck. |
| All Hearts | **CONDITIONAL** | Pays if every surviving top is ♥ — demands genuine board-shaping, but the payout is 4 coins. Enabler: ♥-shaping tools; the ask exceeds the reward. |
| Envy | **FAILS** | Coins per ♥ top at deal end; you won't reshape tops for 2/pile. Drip with a condition. |
| Streak Size | **PASSES** | In-column streak bonus resetting on any other-column guess — warps WHERE you guess for whole deals. One of the strongest puzzle-shifters. |
| Streak Bury | **PASSES** | Same warp, bury payoff. |
| Fourth Seat | **PASSES** | An extra pile changes board geometry and where you can afford deaths. |
| Second Wind | **PASSES** | Death-save at the price of RETURNING buried cards to the deck — an honest tradeoff (undoes bury progress). |
| Greedy | **PASSES (tradeoff)** | Pays only if it's your ONLY pillar — a real loadout sacrifice. The tradeoff IS the design. |
| Highest Heart | **CONDITIONAL** | Pays the highest numbered ♥ top — you'd keep a 10♥ on top, which is at least a keep-decision. Enabler: ♥ tops worth protecting; marginal. |
| Dense Bury | **CONDITIONAL** | ♣ with 2+ stickers landing → bury. Wants sticker-stacked clubs: a build ask (Collector-style mules). Enabler: sticker density; uncommon but reachable. |
| Revive | **PASSES** | A 10-card pile arms a revive — you GROW a pile on purpose to bank a resurrection. |
| Bulk Rate / Freebie / Rare Hunter | **FAILS (as play)** | Store-economy passives: real value, zero effect on any in-deal decision, and no tradeoff beyond the slot. They're shop math, not play. (The column slot cost is real but invisible at buy time.) |
| Bouncer (twoWard) | **FAILS** | 30% to cancel a bane you never chose to meet. Insurance you buy and forget. |
| Flypaper | **PASSES (barely)** | Random sticker per landing, 5% — you can't steer it, but permanent random stickers change future placement puzzles. Borderline. |
| Underdog / Crowd Favorite | **CONDITIONAL** | Pay/bury on the locked scarcest/most-common rank — the lock makes the deck's rank curve visible and pushes purge/transmute decisions. Enabler: rank-shaping tools; present mid-game. |
| Insurance | **FAILS** | +8 if exactly one pile lives. You never PLAY toward one-alive; it pays you for almost losing. |
| Ditto | **PASSES** | Mirrors the center pillar — a loadout-geometry puzzle (what deserves doubling, what sits center). |
| Massive Diamond (heavyDiamond) | **CONDITIONAL** | ♦ counts +2 size in-column — score currency; passes only on a score push with ♦ shaping. |
| Prime | **FAILS** | +1 coin on prime ranks. Rank-keyed drip; nobody changes a call for it. |
| Queen's Eye | **PASSES** | Peek on royal ♠ landings — you route royals there, and it pairs with royal-keeps. |
| Shuffler (royalCourt) | **PASSES** | ♦ landing shuffles the column — sometimes harmful; you time ♦ landings. |
| Excavator | **CONDITIONAL** | Coins per buried card under the largest ♥-topped pile — asks for a ♥ top on your bury pile; a real but fiddly ask. Enabler: bury build + ♥ shaping. |
| Gambler | **FAILS** | A coin flip at deal end. Zero decisions, by design a pure lottery ticket. |
| Last Rites | **PASSES (perverse)** | Peek per in-column death — makes deaths there partially GOOD; changes where you accept losses. |
| Static | **CONDITIONAL** | 50% peek on ♠ landings — Queen's Eye with a coin flip. Enabler: ♠ density; the RNG halves the routing incentive. |
| Wild Aces | **PASSES** | Aces high OR low in-column — changes the math of every call there; you route aces. |
| Diamond Anchor | **CONDITIONAL** | Anchor's column version — score currency again. |
| Diamond Distribution | **PASSES** | ♦ landing equalizes the column — powerful, sometimes unwanted; routing and timing matter. |
| Empty Ranks (zeroRanksBury) | **PASSES** | Bury per ZERO-copy rank on ♣ landings — the purge school's payoff; you purge ranks to feed it. Real build. |
| Crazy Eights (eightStart) | **PASSES** | Piles start at size 8 if 8s lead the deck — demands deliberate 8-shaping (Old Joker's Eights, transmute); huge, conditional, earned. |
| Royal Sanctuary | **PASSES** | Royals safe if the deck holds no 2s — purge every 2: a real, checkable project with a real payoff. |
| Void Tribute | **PASSES** | Zero of the rolled suit → ♣ landings bury 2 — a mono-suit-elimination project. |
| Majority Rule | **PASSES** | ≥50% of deck in the rolled suit → that suit safe here — the mono-suit project's crown. |
| Diamond Echo | **CONDITIONAL** | ♦ landing +size per rank duplicate — score payoff for rank-duplication builds. Enabler: rank flood tools + caring about score. |
| Close Call / Royal Pair / Perfect Ten | **PASSES** | Tolerated Sames = you CALL Same in spots that are otherwise wrong — the family directly rewrites the call decision. |
| Same Suit Safe | **PASSES** | Suit-match safety changes every call in the column; rare-tier gates its strength. |
| Rank Shield | **PASSES** | Protects the deck's most-common rank — visible, dynamic, and you can FEED it (add copies of the protected rank). |
| Scarce Suit | **PASSES** | Shields your fewest suit, recomputed per deal — purges/transmutes MOVE the shield; deck-shaping steers it. |
| Flat Purge / On the House | **FAILS (as play)** | Store-economy passives like Bulk Rate — real money, no play. |
| Eight Ball | **CONDITIONAL** | Peek when an 8 lands — a rank-routing incentive with a small ask. Enabler: 8-density (pairs beautifully with the Eights bargain / Crazy Eights). |
| Pauper's ♥/♦/♠/♣ | **PASSES (tradeoff)** | Live only under 10 coins — the whole family trades the shop economy for in-deal power. A real standing tradeoff you manage every purchase. |
| Curse Harvest | **PASSES** | Makes cursed landings GOOD (bury+peek) — flips curse-avoidance into curse-routing; changes how you take Old Joker bargains. |
| Club Thin | **CONDITIONAL** | ♣ bury scaled by deck remaining — bury school member, strongest early in deals. Enabler: ♣ density. |
| Rank Purge | **PASSES** | On-purchase purge of a shown rank — a deck-shaping decision made AT the shelf, exactly once. |
| Diamond Lifeline | **CONDITIONAL** | ♦ +size while a size-1 pile exists in-column — rescue mechanics for score; niche. |

## BASES

| Item | Verdict | Rationale |
|---|---|---|
| Kamikaze | **PASSES** | Kill your own ♠ pile for 2 peeks — sacrifice with timing. |
| Spade Peeker | **PASSES** | Peek gated on an ALL-♠ column — you shape tops to arm it. |
| Upheaval | **PASSES** | Column shuffle on demand — pure timing tool. |
| Phoenix | **PASSES (tradeoff)** | Revive returns buried cards to the deck — undoes bury progress; when to fire is real. |
| Wild Sticker | **PASSES (barely)** | Random sticker on a random in-column top — timing only (whose tops are up); the randomness eats most of the decision. |
| Ballast | **PASSES** | Equalize the column — score/survival timing. |
| Rank Setter | **PASSES** | Set tops to the bottom pile's rank — board-wide Same setup; you arrange the bottom pile first. |
| Suit Setter | **PASSES** | Suit version — guards/suit-pillar setup. |
| Sticker Harvest | **PASSES (tradeoff)** | Bury 2/sticker but PEEL them — spends your sticker investment for burial; a genuine exchange. |
| Reactor | **PASSES** | Recharge the other bases — loadout-geometry (worthless alone, multiplies neighbors: the classic enabler half). |
| Club Dig | **CONDITIONAL** | Bury per ♣ top in-column — bury school, wants ♣ tops arranged. |
| Demolish | **PASSES (tradeoff)** | DESTROY your own pillar for 3 peeks — the crispest tradeoff in the game. |
| Heart Demolish | **PASSES (tradeoff)** | Kill your ♥ piles for coins — selling board position for money. |
| Heart Tax | **FAILS** | Coins per ♥ in the column, tap when fullest. The "when" is trivially "late"; no play changes. |
| Recharge Cell | **PASSES** | Shield refill on demand — you spend Sames more freely; timing real. |
| Power Surge | **CONDITIONAL** | Fires the equipped power — as good as the power (Rank Flood: a board-rewrite button; Dividend: a coin button). |
| Last Resort | **PASSES (tradeoff)** | Insta-win a non-boss deal, destroys itself and neighbors — dramatic, costed, timed. |
| Empty Purse | **PASSES (tradeoff)** | ALL your coins for peeks — the Pauper school's panic button; a real price every time. |
| Same Tell | **PASSES** | Board-wide same-rank mark for the next draw — changes the very next call. |
| Lone Eye | **PASSES (tradeoff)** | Peek only with NO Same-Power equipped — a standing loadout sacrifice. |
| Club Oracle | **PASSES** | Tells on ♣ tops — you arrange ♣ tops first. |
| Escape Hatch | **PASSES (tradeoff)** | Dead weight except in an ambush — carrying it is the cost, cashing it is the plan. |
| Purge Coupon | **FAILS (as play)** | Store discount on a plaque — tap it, forget it. |
| Transmute | **PASSES** | 13-cards-at-a-stroke suit rewrite AT PURCHASE — the biggest single deck-shaping decision on the shelf. |
| Sacrifice | **PASSES (tradeoff)** | Purge the top card by killing its pile — thinning at a board price, targeted. |
| Devil's Deal | **PASSES (tradeoff)** | Double bonus coins, take a curse — the textbook pass. |
| Cleanse | **PASSES** | Curse removal with column targeting — pairs against Devil's Deal/Old Joker bargains. |
| Chorus | **PASSES** | Set column tops to your most-common rank — the rank build's activator. |
| Diamond Boost | **CONDITIONAL** | +3 size to ♦ piles — score currency; timing trivial. |

## SAME-POWERS

| Item | Verdict | Rationale |
|---|---|---|
| Burrow (linkBury) | **PASSES** | Bury under suit-topped piles — WHEN you call Same starts depending on the board's suit tops. |
| Rekindle | **PASSES** | Revive on Same — you bank Sames for after deaths; changes call timing. |
| Dividend (linkCoins) | **FAILS** | Coins per alive pile on Same. You were calling Same anyway; the payoff changes nothing about when. |
| Link Shuffler | **PASSES** | Board shuffle on Same, with consent — a timed disruption tool. |
| Same Peeker | **PASSES (barely)** | Peek on Same — always-good, but peeks do change the next call. The blandest pass. |
| Second Sight | **PASSES** | One draw of total vision — you SAVE the Same for the moment vision matters most. |
| Sticker Spray | **PASSES** | Permanent random stickers on the called column — you choose the column by choosing the pile. |
| Long Odds (linkPurge) | **CONDITIONAL** | 25% purge from the remaining deck — thin-deck school, but RNG-gated and invisible. |
| Same Heavy | **CONDITIONAL** | +size everywhere, +3 on the hub — score currency; hub choice is real on a score push. |
| Rank Flood | **PASSES** | Rewrites every top to the called rank — WHICH Same you call becomes the biggest decision in the deal. The archetype anchor working as intended. |

---

## Summary counts

- **PASSES:** 66 (including 14 that pass specifically via a tradeoff)
- **CONDITIONAL:** 20
- **FAILS (autoplay):** 17

## The FAILS list (candidate cut-or-complicate set)

**Pure coin drips:** Bonus Coin, Loose Change, Heart Snob, Heart Choir,
Heart Bonus, Envy, Prime, Gambler, Insurance, Dividend, Heart Tax.
**Choice-removers:** Random Rank, Random Suit.
**Shop passives (no play):** Bulk Rate, Freebie, Rare Hunter, Flat Purge,
On the House, Purge Coupon, Bouncer.
*(The shop passives are a deliberate class — if "shop value" is a build lane
you want, they're fine as a lane; they just never touch a deal.)*

## Conditionals and their enablers (frequency-honest)

| Item | Enabler | How often present |
|---|---|---|
| ±1/±2 Rank | any rank-carer (Rank Shield, Rank Roots, Crazy Eights, tolerance family, Same plans) | COMMON post-v6.76 — these now pass in most real runs |
| Payout | none needed; incentive small | always, weakly |
| Heavy/Massive, Diamond Echo, Same Heavy, Diamond Anchor, Massive Diamond, Diamond Boost, Diamond Lifeline | caring about SCORE | score is prestige-only; on a leaderboard push, common; otherwise absent |
| Quick Bury | none exists for PLACEMENT (effect is fine) | never — the placement is always interchangeable |
| Deep Pockets | a bury build to tension against | moderate |
| Clean Bury / Club Thin / Club Dig | ♣ density | moderate (one Transmute away) |
| All Hearts / Excavator / Highest Heart | ♥ shaping + keeps | uncommon — ask exceeds reward |
| Dense Bury | sticker-stacked ♣ mules | uncommon |
| Underdog / Crowd Favorite | rank shaping tools | moderate |
| Static / Eight Ball | ♠ / 8 density | moderate; Eight Ball spikes with the Eights bargain |
| Tap Power / Power Surge | a power worth firing (Rank Flood, Burrow) | player-controlled — fine |
| Long Odds | thin-deck payoffs | moderate |

## Five clearest fails — a tradeoff that would fix each, and the cut call

1. **Bonus Coin (gainCoin)** — *Fix:* "+4 coins when this card lands
   WRONG-SIDE-SAVED or on a pile of 5+" — i.e. pay only when the landing was
   earned under pressure, so you route it. *Cut?* **Cut.** Small Sticker
   Packs already deliver coin-adjacent filler; the slot is better empty.
2. **Loose Change** — *Fix:* "+0–6, roll shown BEFORE the deal starts" so you
   can play its pile knowing the stake. *Cut?* **Cut** — Random-payoff coin
   stickers are two-axis noise; Bonus Coin covers the niche if kept.
3. **Heart Choir** — *Fix:* "+2 per ♥ top, but every counted ♥ top gets
   SHUFFLED into its pile" — pays you to disturb your own board: a real
   trade. *Cut?* Keep-with-fix is better than cut; the ♥ lane is thin on
   interesting members.
4. **Gambler** — *Fix:* let the player CALL the flip (heads = +6, tails =
   −3) at deal start — a stake, not a lottery. *Cut?* **Cut** unless the
   game wants an explicit gambling identity; one pure lottery item teaches
   players that pillars can be thoughtless.
5. **Insurance** — *Fix:* "+8 coins if exactly one pile survives AND it holds
   8+ cards" — now it's a deliberate all-eggs-one-basket plan, pairing with
   Anchor/feeding. *Cut?* Keep-with-fix — the one-pile endgame is a real
   state players already navigate; paying it to be CHOSEN is interesting.
6. *(bonus)* **Random Suit** — *Fix:* "choose the card; the suit rolls among
   the two suits you hold LEAST" — randomness with a shaping floor. *Cut?*
   **Cut** — Change-to-X exists at the same price; this is strictly the
   worse decision.
