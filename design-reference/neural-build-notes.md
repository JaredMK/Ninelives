# Neural redesign — build notes

Branch: `neural-redesign` (off the clean live game; never merged to main).
**Preview:** https://jaredmk.github.io/Ninelives/neural/  (badge → `build v0.54 · neural-5`)

Presentation only — gameplay/engine/economy/state/persistence untouched; **640
tests pass**. Each phase is a separate commit for review.

## Phases
- **P1 · palette + background + type** (`v0.50`) — muted neural `:root` palette;
  fixed `#tissue` layer (Layer A drifting haze blobs + Layer B faint static
  blurred veins) behind everything; Josefin Sans (titles) + Chakra Petch (UI +
  ranks). No starfield. Re-fit on `document.fonts.ready`.
- **P2 · cards** (`v0.51`) — light-core radial face, 22px organic corners, warm
  outer glow + light rim, subtle breathing; classic suits as crisp SVG, dark
  two-color (red `#b5566f` / ink `#2c2430`); size pill restyle; limiting pile →
  amber ring + amber count pill; dead pile → cold scar.
- **P3 · network (static)** (`v0.52`) — SVG mesh behind the cards linking
  adjacent alive piles. Adjacency = "nearest alive pile in each of 8 directions"
  (geometry-derived, handles the staggered `[3,4,3]` board). Thickness gated by
  the **weaker** pile (min size) — equal/min at start, thickens as the weaker
  endpoint grows; diagonals same rule.
- **P4 · motion** (`v0.53`) — pale signal pulses travel the live links (1 → one
  slow pulse, up to 3 faster on the strongest), capped for mobile Safari; veins
  stay static so links are the only live/foreground layer.
- **P5 · death & reconnection** (`v0.54`) — a dying pile recedes to a cold scar
  (stops breathing, links sever via a dissolve dip), and survivors re-form a
  direct bridge across it automatically (dead piles drop out of the
  "nearest-alive" graph). Cards never reflow; bridges follow the same thickness
  rule.

## How the visuals read state (never mutate)
The network/cards read only getters — `engine.getBoard()` → `isActive(i)`,
`pileSize(i)`, `aliveCount()`, `minAliveCards()`/`trueMinAliveCards()` — plus DOM
geometry. No setter is called from any render path.

## Notes / things to judge or tune
- **Adjacency** is geometric (8 sectors, nearest alive, distance cap ~2.7×
  pitch). A single dead middle pile bridges its top/bottom cleanly; two dead in
  a row may exceed the cap (no bridge) — raise the cap if you want longer
  bridges.
- **Sever animation** is a quick whole-layer opacity dip + redraw (links
  dissolve, reconnected set fades back). A per-link targeted dissolve is the
  richer version if you want it later.
- **External dep:** fonts load from Google Fonts (works on Pages; can self-host).
- **Deferred (spec §9):** sticker/Pillar icons (still the original emoji), the
  game name ("CORTEX" placeholder, kept existing HUD), and an end-of-run
  cinematic — all intentionally out of this build.
- **Readability:** rank (Chakra Petch, dark on light), suit, size pill, and the
  amber limiting ring all stay above the network (which is `pointer-events:none`
  and behind the cards). If any link/pulse density hurts legibility, dial the
  base width/opacity in `linkMarkup`.
