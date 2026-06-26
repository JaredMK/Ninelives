# 🗺️ Authoring run maps

Run maps are **plain text files you edit by hand**. You describe each phase's
structure here; the game reads the file and draws the map — you never touch
code or pixel coordinates.

- One file per map: `something.map` (plain text).
- List every file in [`manifest.json`](./manifest.json) so the game can find it.
- The game auto-positions every node from its row and left-to-right order.

## Quick start

1. Copy `diamonds-1.map` to a new file, e.g. `hearts-1.map`.
2. Edit the rows and links.
3. Add `"hearts-1.map"` to the `maps` list in `manifest.json`.
4. Reload the game. No code changes.

> **Running the game:** maps are loaded over HTTP, so serve the folder rather
> than double-clicking `index.html`:
> ```
> python3 -m http.server 8000
> ```
> then open <http://localhost:8000/>. (Opening via `file://` can't read the
> map files — the game will tell you so.)

## File format

```
PHASE: Diamonds          # required — the phase this map belongs to
ORDER: 1 of 3            # optional — "N of M"
SUIT: diamond            # required — diamond | heart | spade | club

# Comments start with '#'. Blank lines are ignored.
# Rows go bottom (START) to top (BOSS). Each row lists nodes left-to-right.
ROW 0: START
ROW 1: DEAL[piles:5]  DEAL[piles:4]
ROW 2: PACK[+3 diamond]  CARD[Q diamond]  DEAL[piles:8]
ROW 3: DEAL[piles:7]  STORE
ROW 4: BOSS[piles:6]

# Links: which node connects UP to which. Address nodes as row.index
# (0-based, left-to-right). Targets must be in the next row up.
LINKS:
  0.0 -> 1.0, 1.1
  1.0 -> 2.0, 2.1
  1.1 -> 2.1, 2.2
  2.0 -> 3.0
  2.1 -> 3.0, 3.1
  2.2 -> 3.1
  3.0 -> 4.0
  3.1 -> 4.0
```

## Node types

| Node              | Meaning                                             |
| ----------------- | --------------------------------------------------- |
| `START`           | The phase entry. ROW 0 must be exactly one `START`. |
| `DEAL[piles:N]`   | A deal; `N` piles dealt on the board.               |
| `BOSS[piles:N]`   | The phase boss. Must be the lone node in the top row. |
| `CARD[rank suit]` | Pick up one specific card, e.g. `CARD[Q diamond]`.  |
| `PACK[+N suit]`   | Pick up N cards of a suit, e.g. `PACK[+3 diamond]`. Use `any` for mixed: `PACK[+2 any]`. |
| `STORE`           | The shop.                                           |

- **rank**: `2`–`10`, `J`, `Q`, `K`, `A`
- **suit**: `diamond`, `heart`, `spade`, `club` (plus `any` for `PACK`)

> Note: `DEAL` and `BOSS` launch the higher/lower game today. `CARD`, `PACK`,
> and `STORE` are authorable and validated now, but their gameplay effects are
> placeholders — they complete instantly with a "TODO" message until those
> systems land.

## Multiple maps per phase

Maps that share the same `PHASE` **and** `ORDER` form a pool; the game picks
one at random per run. To add variety, just add more files for the same phase.

## Validation

When you reload, a malformed map fails **loudly** with the line and node at
fault — for example:

- `ROW 3 links to 4.2 but ROW 4 has only 1 node(s).`
- `ROW 4 node 0 ("BOSS"): BOSS needs piles:N ...`
- `Node 2.1 (PACK +3 diamond) is unreachable from START.`
- `Node 3.0 (DEAL piles:7) is a dead end — no path from it leads to the BOSS.`

You can also check a file from the command line without a browser:

```
node maps/check.js maps/diamonds-1.map
```
