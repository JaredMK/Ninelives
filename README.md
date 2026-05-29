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
  between runs except campaign-level stats (total correct guesses, runs
  completed).

## Architecture

Deliberately decoupled so it can grow into a full roguelike-style campaign.
The engine never touches the DOM; the renderer never mutates game state.

| Module | Responsibility |
| --- | --- |
| `DeckManager` | The card pool: build, seeded shuffle, draw, remaining count. |
| `BoardState` | The nine piles and their alive/dead status. |
| `GameEngine` | The rules + a per-run state (phase, seed, correct/total guesses). Emits events. |
| `CampaignState` | Campaign-level only: current run index, cross-run totals. Persists between runs. |
| `UIRenderer` | DOM only: renders from events, drives the phase screens, captures input. |

### Phases

Exactly one phase is shown at a time (the board is interactive only while the
overlay is hidden):

- **Start** — campaign intro.
- **Active run** — normal play.
- **Run Complete** — per-run + campaign stats, Continue.
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
