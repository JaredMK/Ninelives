# 🐱 Nine Lives

A mobile-first, single-file web card game. No frameworks, no backend, no
dependencies — open `index.html` in any modern browser.

## How to play

- A deck of **2–4 suits depending on the stage** (see Campaign). **Suits don't
  matter for guessing, only rank. Ace is high.**
- Cards are dealt face-up into a grid of piles (count/layout vary per run —
  see Campaign); the rest form the draw deck.
- **Tap a pile**, then choose **Higher**, **Same**, or **Lower** for the next
  card. The next card is revealed and compared to that pile's top:
  - **Correct** → the card is placed on the pile (new top).
  - **Wrong** → the pile dies. **A tie counts as wrong on a Higher or Lower
    guess (it kills the pile); only a correct "Same" guess survives a tie.**
- **Clear a run** by emptying the draw deck. A run ends in a win (deck empty)
  or a loss (all its piles dead). **Losing any run ends — and wipes — the
  whole campaign** (see Campaign).

## Campaign

A campaign is **3 stages of 3 runs each (9 runs)**. Each **stage** sets the
deck size by suit count; each **run** within a stage uses a fixed pile layout
(config-driven via `RUN_LAYOUTS`). The store appears **between runs**.

| Stage | Suits | Deck |
| --- | --- | --- |
| 1 | ♠ ♥ | 26 cards |
| 2 | ♠ ♥ ♦ | 39 cards |
| 3 | ♠ ♥ ♦ ♣ | 52 cards |

| Run (every stage) | Rows | Piles |
| --- | --- | --- |
| 1 | 3 · 4 · 3 | 10 |
| 2 | 3 · 3 · 3 | 9 |
| 3 | 3 · 2 · 3 | 8 |

Suits enter in a fixed order (♠ ♥ → +♦ → +♣). A suit that isn't in play yet
sits **dormant with its stickers intact** until its stage arrives. Cards are
sized so 3 fill the width; shorter rows center and a 4-card row shrinks to fit.

```
Start → S1R1 → … → S1R3 → S2R1 → … → S3R3 → Campaign Complete   (win)
   any run lost ───────────────────────────→ Campaign Over (full wipe)
```

- After a won, non-final run a **Run Cleared** intermission (stage/run progress
  + the itemized coin breakdown only) leads to the **Store**, then the next run.
- Clearing **Stage 3 Run 3** → **Campaign Complete** (campaign win).
- **Campaign lifecycle — full wipe on any loss:** losing any run ends the
  campaign immediately. **New Campaign** resets *everything* to a vanilla
  Stage 1 / Run 1 state: 26-card 2-suit deck, all stickers removed, all
  modifications gone, coins zeroed, sticker inventory cleared. Nothing carries
  across attempts; every campaign starts identical.
- **Persistence is within one in-progress campaign only.** A card's stickers
  persist run-to-run and stage-to-stage *within* an attempt, but a loss wipes
  them. (The wipe is deliberately isolated to `CampaignState.reset()` and a
  single loss call site, so it's easy to soften later — e.g. a checkpoint or
  partial carry.)
- **Save & resume (between runs).** The campaign-level state — stage/run
  position, coins, sticker inventory, the 52-card deck with its stickers +
  modifications, Pillars, and the current store offer — is saved after each
  change and restored on refresh, so a reload drops you back into your run's
  sticker phase or the store. It is cleared on a loss and on campaign
  completion (the "loss wipes everything" rule still holds). Per the
  between-runs scope, a refresh *mid-run* re-deals the current run (live board
  state isn't persisted). Storage goes through a single `SaveStore` adapter
  (browser `localStorage` today); swapping it for a server/cloud per-user save
  later is a one-module change — no gameplay code touches storage directly.

## Coins, Store & Stickers

A Balatro-style economy: **earn coins → buy stickers in the store between
runs → apply them to cards during the next run.**

**Coins** are awarded on a **win** only (first-draft formula; all coefficients
are config constants in the `Economy` module):

```
coins = (number of alive piles) × (cards in the smallest alive pile)
      + (Extra Coin stickers on alive top cards) × EXTRA_COIN_VALUE(1)
      + scoring-Pillar bonuses (Suit Bounty, Column Guardian)
      + live bonus coins (the in-run tally, may be negative; clamped so the total never drops below 0)
```

The product has no coefficient (the only tunable is `EXTRA_COIN_VALUE`). Dead
piles don't count toward the minimum, and with 0 alive piles the product is 0
(guarded, never `NaN`). The run-complete screen itemizes it: alive piles,
smallest alive pile, the `N × M` subtotal, the Extra Coin bonus, each scoring
Pillar that paid, every live-bonus line, and the total.

**Live bonus coins** are tracked *during* the run — the HUD shows a running
`+ N bonus` tally beside the payout factors (gold when positive, red when a
Tribute cost has pulled it negative), starting at 0 each run. Effects move it
the instant they fire: **Middle Reward** (+2 when a carrying card lands in the
middle column), **Lucky Coin** (+1 when a carrying card lands on a surviving
pile), the **Tribute** stickers (a coin cost), and the **All Hearts** Pillar
(+5, board-wide, every post-draw check where every alive pile shows a ♥).

**Store** (between every run): a Balatro-style limited random offering (a few
sticker slots + Pillar slots, with a reroll) drawn from the registries. Prices
are **fixed** per type (buying never raises any price). Each offer is weighted
by **rarity tier** — Common (weight 100), Uncommon (50), Rare (20) — shown as a
colored letter badge on each store tile. Tiers only bias how often a type is
*offered*; they don't change its price.

**Stickers** attach to a *specific* card by its persistent id and ride with
that card for the rest of the campaign attempt (until a loss wipes it) — they
belong to the card, not the pile position. The registry's `description` field
is the single source of truth for each one's in-store help text. Highlights
(see `StickerTypes` for the full set and exact prices):

| Sticker | Effect |
| --- | --- |
| **±1 / ±2 Rank** | Permanently shift the card's rank (clamps at Ace / 2) |
| **Random Rank** 🎰 | Set the card's rank to a random rank (2–Ace) |
| **Change Suit** (♠ / ♥ / random) | Repaint the suit (feeds Suit Bounties) |
| **Tie-Safe** 🛡️ | The card survives a tie on *any* guess |
| **Spade Guard** 🪬 | Once per run: while showing, a ♠ wrong guess is absorbed (the ♠ is reshuffled in) |
| **Extra Heart** ❤️ | Absorbs one wrong guess this run; the drawn card is reshuffled in; refreshes each run |
| **Extra Coin** 💰 | On a win, pays bonus coins equal to its pile's card count |
| **Anchor** ⚓ | Excludes its pile from the smallest-pile payout factor |
| **Middle Reward** 🎯 | +2 bonus coins when it lands in the middle column |
| **Lucky Coin** 🍀 | +1 bonus coin when it lands on a surviving pile |
| **Tribute I / II** 🪦 ⚰️ | On a surviving landing, bury 1 / 2 deck cards under the pile; costs 1 / 4 bonus coins |
| **Center Tribute** 🗿 | Tribute I, but only in the middle column |

**Pillars** are column modifiers (bought in the store, one per column slot,
bindings persist between runs) whose effect applies to every pile in their
column for the run — see `PillarTypes`. They include the four **Suit Bounties**
(+1 per correct guess off a matching-suit top), **Column Tie-Safe**, **Column
Guardian** (+5 if the whole column survives), **8 Tribute** / **Same Tribute**
(bury a deck card on a drawn 8 / a survived tie — now **uncapped**), **Double
Tribute** 🏺 (buries *two* on a survived tie), and **All Hearts** 💗 (board-wide
+5 each post-draw check where every alive pile shows a ♥).

**Applying** happens during a **pre-play window** each run: right after the
deal you may apply owned stickers to any pile's **face-up top card** (arm one
from the tray, then tap a pile). The window **closes on your first guess**
(`run.stickerWindow` flips false) — no end-of-run sticker saves. Unspent
stickers stay in inventory for the next run's window. Rank stickers take
effect immediately; behavior stickers are read by the engine on the next
guess. There is **no per-card limit** — a card may hold any number of
stickers, including duplicates (stacked Extra Coin/Heart each pay/save N,
stacked ±1 clamp at the Ace/2 boundary). The only block is at that boundary:
no +1 on an Ace, no −1 on a 2.

Each card has a **persistent identity**: a stable id and suit, the rank it
*started* as (`originalRank`), the rank it is *now* (`currentRank`), a
`modifications` history, and its `stickers`. Edits target a specific card
instance — other cards of the same rank are untouched — and carry into every
later run of the same campaign. The base deck (all 52 identities) and the
active run deck are kept separate: each run plays a freshly shuffled **copy**
of the current stage's active suits (26/39/52 cards), materialized from each
card's `currentRank` with behavior stickers projected onto run-local fields,
so playing never mutates the persistent deck. Draw order is never revealed —
Extra Heart's shuffle-back reinserts at a random position, so uncertainty is
preserved.

## Deck inspection

During an active run you can check what's **left to draw** — without learning
the order — by interacting with the **Deck** pill in the HUD:

- **Tap** → a bottom-sheet modal with the full breakdown: each rank's remaining
  count, its **draw probability**, and the total cards left.
- **Press & hold** → a lightweight quick-peek overlay (compact rank counts +
  total) that vanishes the instant you release.

Percentages are computed from the **current run deck only**. It's strictly
informational: it never reveals draw order or upcoming cards, never lets you
manipulate the deck, and never pauses or alters gameplay (counts are read from
the live deck, sorted by rank, so order can't leak).

## Architecture

Deliberately decoupled so it can grow into a full roguelike-style campaign.
The engine never touches the DOM; the renderer never mutates game state.

| Module | Responsibility |
| --- | --- |
| `DeckManager` | The card pool: build, seeded shuffle, draw, remaining count. |
| `BoardState` | The piles (count varies per run) and their alive/dead status. |
| `GameEngine` | The rules + a per-run state (phase, seed, correct/total guesses). Emits events. |
| `CampaignState` | Campaign-level only: the persistent 52-card base deck (identity + modifications + stickers), current **stage** + run, stage→suit-count run-deck construction, cross-run totals, coins, sticker inventory + application, and the full-wipe `reset()`. Persists within one campaign attempt; wiped on loss. |
| `Economy` | Pure: the win-only coin payout formula (config coefficients, no DOM, no state). |
| `StickerTypes` | Data-driven sticker registry (id, label, kind, price, behavior) so sticker behavior isn't hardcoded inline. |
| `DeckStats` | Pure: turns an order-free rank-count map into a draw-probability breakdown. |
| `DeckInspector` | Self-contained UI: the tap modal + hold quick-peek and their gesture handling. Reads stats via a callback; never touches gameplay. |
| `UIRenderer` | DOM only: renders from events, drives the phase screens, captures input. |

### Phases

Exactly one phase is shown at a time (the board is interactive only while the
overlay is hidden):

- **Start** — campaign intro.
- **Active run** — normal play. The top bar shows the two payout factors as
  `alive piles × smallest alive pile` (e.g. `9 × 1`), labelled and with the
  smallest-pile number in orange to tie it to the highlighted pile(s); the
  product itself is not shown. A persistent `Stage X · Run Y · 🪙 coins` pill
  sits in the header, and the sticker tray is active only during the pre-play
  window. The deck counter lives below the piles on the right (tap to inspect,
  hold for a quick peek). Each pile shows a card-count badge; the limiting
  pile(s) — those whose count equals the current smallest alive pile — are
  orange (all of them if several tie), updating live as counts change. Both
  factors read `board.aliveCount()` / `board.minAliveCards()`, the same source
  the Economy module uses for the payout product.
- **Run Cleared** — stage/run indicator + itemized coin breakdown, Continue
  (won, non-final run). **Hold** anywhere on this screen to peek the final board.
- **Store** — between runs: spend coins on stickers, then Start Run.
- **Campaign Complete** — cleared all 3 stages; final totals, New Campaign.
- **Campaign Over** — after any loss; full wipe, New Campaign.

### Seeded shuffle

Each run generates a 32-bit seed fed to a deterministic PRNG (mulberry32), so
a given seed always produces the same deal. No seed UI is exposed yet.

### Extension points (wired, not yet implemented)

- `applyRunScaling(runIndex)` — called at the start of every run; the future
  home for per-run difficulty scaling. Currently a no-op.
- `HOOKS.onRunComplete / modifyDeck / openShop` — reserved for a future
  reward / deck-modification / shop system.

### Build badge

The footer shows `build vX.Y.Z` (from the `APP_VERSION` constant) and logs it
to the console, so you can confirm at a glance which version is loaded.

### Debug

Add `?debug` to the URL (or triple-tap the title) to open a debug panel:
force the next card, peek upcoming cards, trim the deck, or jump to a
win/loss.
