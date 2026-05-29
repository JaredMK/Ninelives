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

## Coins, Store & Stickers

A Balatro-style economy: **earn coins → buy stickers in the store between
runs → apply them to cards during the next run.**

**Coins** are awarded on a **win** only (first-draft formula; all coefficients
are config constants in the `Economy` module):

```
coins = WIN_BONUS(5)
      + (number of alive piles)                    × PER_ALIVE_PILE(2)
      + (alive top cards with the Extra Coin sticker) × EXTRA_COIN_VALUE(1)
```

**Store** (between every run): spend coins on stickers, which go into your
campaign inventory. Each type has its own **base price that climbs +1 every
time you buy that type** (tracked per type in `CampaignState`, reset on wipe).
**Stickers** attach to a *specific* card by its persistent id and ride with
that card for the rest of the campaign attempt (until a loss wipes it) — they
belong to the card, not the pile position. Types:

| Sticker | Base | Effect | Blocked when |
| --- | --- | --- | --- |
| **+1 Rank** | 2 | Permanently raises that card's rank by 1 | card is an Ace |
| **−1 Rank** | 2 | Permanently lowers that card's rank by 1 | card is a 2 |
| **Tie-Safe** 🛡️ | 3 | The card survives a tie on *any* guess (not just Same) | already has Tie-Safe |
| **Extra Heart** ❤️ | 8 | Survives one wrong guess this run — the wrongly-drawn card is shuffled back into the deck and the heart "breaks"; refreshes each run | — |
| **Extra Coin** 💰 | 1 | At end of run, +1 coin if this card is alive on top of a pile | already has Extra Coin |

**Applying** happens *in-run*: owned stickers appear in a tray; tap one to
arm it, then tap a pile to apply it to that pile's **face-up top card**. Rank
stickers take effect immediately; behavior stickers (Extra Heart / Tie-Safe)
are read by the engine on the next guess. A card holds at most
`STICKER_SLOTS_PER_CARD` (3) stickers; rank stickers stack toward the Ace/2
caps and are blocked at the cap so none are wasted.

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
- **Active run** — normal play.
- **Run Cleared** — stage/run indicator + itemized coin breakdown, Continue (won, non-final run).
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
