# 🐱 Nine Lives

A mobile-first, single-file web card game. No frameworks, no backend, no
dependencies — open `index.html` in any modern browser.

## How to play

- Standard 52-card deck. **Suits don't matter, only rank. Ace is high.**
- Nine cards are dealt face-up into a 3×3 grid of piles; the rest form the
  draw deck.
- **Tap a pile**, then choose **Higher**, **Same**, or **Lower** for the next
  card. The next card is revealed and compared to that pile's top:
  - **Correct** → the card is placed on the pile (new top).
  - **Wrong** → the pile dies (ties only win on a "Same" guess).
- **Clear a run** by emptying the draw deck. A run ends in a win (deck empty)
  or a loss (all nine piles dead).

## Campaign

A play-through is a **campaign**: a fixed sequence of **3 runs**.

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

## Deck Surgery

After **winning** a run (and before the next one starts), you get a **Deck
Surgery** screen to permanently evolve ONE specific card in the campaign deck:

| Operation | Effect | Limit |
| --- | --- | --- |
| **Increase** | The chosen card goes up +1 rank | Ace (A) is the max |
| **Decrease** | The chosen card goes down −1 rank | 2 is the min |
| **Randomize** | The chosen card becomes a different random rank | — |

Each card has a **persistent identity**: a stable id and suit, the rank it
*started* as (`originalRank`), the rank it is *now* (`currentRank`), and a
`modifications` history. Surgery edits a specific card instance — other cards
of the same rank are untouched — and the change carries into every future run.

Flow: **tap an operation → tap a card → confirm** (or **Skip**). The screen
shows the actual deck as individual cards. Modified cards get a lightweight
ring and a small **+ / − / ~** marker, plus their struck-through original
rank — invalid choices for the chosen operation are greyed out and prevented.
The deck stays 52 cards, so the game keeps its uncertainty; only individual
ranks shift.

The base campaign deck and the active run deck are kept separate: each run
plays a freshly shuffled **copy** (materialized from each card's
`currentRank`), so playing never mutates the persistent deck, and surgery
never touches the live run.

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
| `CampaignState` | Campaign-level only: the persistent base deck (cards with identity + modification history), current run index, cross-run totals, and the per-card Deck Surgery operations. Persists between runs. |
| `DeckStats` | Pure: turns an order-free rank-count map into a draw-probability breakdown. |
| `DeckInspector` | Self-contained UI: the tap modal + hold quick-peek and their gesture handling. Reads stats via a callback; never touches gameplay. |
| `UIRenderer` | DOM only: renders from events, drives the phase screens, captures input. |

### Phases

Exactly one phase is shown at a time (the board is interactive only while the
overlay is hidden):

- **Start** — campaign intro.
- **Active run** — normal play.
- **Run Complete** — per-run + campaign stats, Continue.
- **Deck Surgery** — after a won run, one permanent deck edit before the next run.
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
