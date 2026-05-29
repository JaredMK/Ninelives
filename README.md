# 🐱 Nine Lives

A mobile-first, single-file web card game. No frameworks, no backend, no
dependencies — open `index.html` in any modern browser.

## How to play

- Standard 52-card deck. **Suits don't matter, only rank. Ace is high.**
- Cards are dealt face-up into a grid of piles (count/layout vary per run —
  see Campaign); the rest form the draw deck.
- **Tap a pile**, then choose **Higher**, **Same**, or **Lower** for the next
  card. The next card is revealed and compared to that pile's top:
  - **Correct** → the card is placed on the pile (new top).
  - **Wrong** → the pile dies. **A tie counts as wrong on a Higher or Lower
    guess (it kills the pile); only a correct "Same" guess survives a tie.**
- **Clear a run** by emptying the draw deck. A run ends in a win (deck empty)
  or a loss (all nine piles dead).

## Campaign

A play-through is a **campaign**: a fixed sequence of **3 runs**. Each run
defines its own pile count and row layout (config-driven via `RUN_LAYOUTS`):

| Run | Rows | Piles |
| --- | --- | --- |
| 1 | 3 · 4 · 3 | 10 |
| 2 | 3 · 3 · 3 | 9 |
| 3 | 3 · 2 · 3 | 8 |

Cards are sized so 3 fill the width (a normal 3-card row, like Run 2, is
edge-to-edge); shorter rows center and a 4-card row shrinks just enough to fit.
The draw deck is always the full 52 cards — only the number dealt to piles
changes with the layout.

```
Start → Run 1 → Run Complete → Run 2 → Run Complete → Run 3 → Campaign Complete
```

- After every run a **Run Complete** screen shows the run result, correct
  guesses, and piles remaining, plus campaign totals. A single **Continue**
  button starts the next run with a full reset.
- After the third run the **Campaign Complete** screen shows the final totals
  and a **New Campaign** button.
- Each run fully resets the deck, piles, UI, and engine — nothing leaks
  between runs except campaign-level state (the persistent deck, total
  correct guesses, runs completed).

## Coins, Store & Stickers

A Balatro-style economy: **earn coins → buy stickers in the store between
rounds → apply them to cards during the next round.**

**Coins** are awarded on a **win** only (first-draft formula; all coefficients
are config constants in the `Economy` module):

```
coins = WIN_BONUS(5)
      + (fewest cards among alive piles) × PER_MIN_ALIVE_PILE(5)
      + (number of alive piles)         × PER_ALIVE_PILE(2)
```

**Store** (between every round): spend coins on stickers, which go into your
campaign inventory. **Stickers** attach to a *specific* card by its persistent
id and ride with that card for the rest of the campaign — they belong to the
card, not the pile position. Starter types:

| Sticker | Effect | Blocked when |
| --- | --- | --- |
| **+1 Rank** | Permanently raises that card's rank by 1 | card is an Ace |
| **−1 Rank** | Permanently lowers that card's rank by 1 | card is a 2 |
| **Extra Heart** | The card survives one wrong guess this run — the wrongly-drawn card is shuffled back into the deck and the heart "breaks". Refreshes each run. | — |
| **Tie-Safe** | The card survives a tie on *any* guess (not just Same) | already has Tie-Safe |

**Applying** happens *in-round*: owned stickers appear in a tray; tap one to
arm it, then tap a pile to apply it to that pile's **face-up top card**. Rank
stickers take effect immediately; behavior stickers (Extra Heart / Tie-Safe)
are read by the engine on the next guess. A card holds at most
`STICKER_SLOTS_PER_CARD` (3) stickers; rank stickers stack toward the Ace/2
caps and are blocked at the cap so none are wasted.

Each card has a **persistent identity**: a stable id and suit, the rank it
*started* as (`originalRank`), the rank it is *now* (`currentRank`), a
`modifications` history, and its `stickers`. Edits target a specific card
instance — other cards of the same rank are untouched — and carry into every
future run. The base campaign deck and the active run deck are kept separate:
each run plays a freshly shuffled **copy** (materialized from each card's
`currentRank`, with behavior stickers projected onto run-local fields), so
playing never mutates the persistent deck. The deck stays 52 cards and draw
order is never revealed — Extra Heart's shuffle-back reinserts at a random
position, so uncertainty is preserved.

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
| `BoardState` | The nine piles and their alive/dead status. |
| `GameEngine` | The rules + a per-run state (phase, seed, correct/total guesses). Emits events. |
| `CampaignState` | Campaign-level only: the persistent base deck (cards with identity + modification history + stickers), current run index, cross-run totals, coins, and the sticker inventory + application. Persists between runs. |
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
- **Run Complete** — per-run + campaign stats, coins earned, Continue.
- **Store** — between rounds: spend coins on stickers, then Start Round.
- **Campaign Complete** — final totals, New Campaign.

### Seeded shuffle

Each run generates a 32-bit seed fed to a deterministic PRNG (mulberry32), so
a given seed always produces the same deal. No seed UI is exposed yet.

### Extension points (wired, not yet implemented)

- `applyRunScaling(runIndex)` — called at the start of every run; the future
  home for per-run difficulty scaling. Currently a no-op.
- `HOOKS.onRoundComplete / modifyDeck / openShop` — reserved for a future
  reward / deck-modification / shop system.

### Build badge

The footer shows `build vX.Y.Z` (from the `APP_VERSION` constant) and logs it
to the console, so you can confirm at a glance which version is loaded.

### Debug

Add `?debug` to the URL (or triple-tap the title) to open a debug panel:
force the next card, peek upcoming cards, trim the deck, or jump to a
win/loss.
