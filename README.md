# 🐾 Nine Lives

A mobile-first, single-file web card game. No frameworks, no backend, no
dependencies — just open `index.html` in Safari (or any modern browser).

## How to play

- The deck is a standard 52-card deck. **Suits don't matter, only rank.**
- **Ace is high.**
- Nine cards are dealt face-up into a 3×3 grid of piles. The rest form the
  face-down draw deck.
- **Tap a pile**, then choose **Higher** or **Lower** for the next card.
- The top card of the draw deck is revealed and compared to that pile's top:
  - **Correct** → the drawn card is placed on the pile (new top).
  - **Wrong** → the pile dies and flips face-down (it stays in its slot but
    can't be used). A **tie counts as wrong** (it's neither higher nor lower).
- **Win** by surviving until the draw deck is empty.
- **Lose** if all nine piles are dead.

## Architecture

The code is deliberately split into decoupled modules so it can grow into a
full roguelike-style run. The engine never touches the DOM; the renderer never
mutates game state.

| Module | Responsibility |
| --- | --- |
| `DeckManager` | The card pool: build, shuffle (Fisher–Yates), draw, remaining count. |
| `BoardState` | The nine piles and their alive/dead status. |
| `GameEngine` | The rules: turn flow, higher/lower resolution, win/lose. |
| `UIRenderer` | DOM only: renders from a state snapshot, captures input. |
| `Hooks` | Placeholder extension points (not yet implemented). |

### Future-feature hooks

These are stubbed in the `Hooks` object so they can be wired in later without
touching the core flow:

- `onRoundComplete` — **reward phase** after a round is cleared.
- `modifyDeck` — **deck modification system** (alter cards pre-shuffle).
- `onRunEnd` — **shop system** between runs.

### Input model

Mobile-first: tap a pile to reveal its Higher/Lower buttons, tap to commit.
The renderer marks a clear hook (`_buildPile`) where a swipe-up/swipe-down
gesture can be added later by calling `onGuess(id, direction)`.
