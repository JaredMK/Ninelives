# Nine Lives → Neural Redesign — Visual Identity Spec (v1)

The single source of truth for the visual overhaul. Pair this with the reference mockup HTML (`neural-reference.html`). The mockup shows the *look and motion*; this doc defines the *rules and behaviors* the mockup fakes with static data.

**Scope:** presentation only. No gameplay, engine, economy, or state logic changes. Everything below is how the existing game is *rendered*, not how it works.

-----

## 0. Theme

A "living neural network." The board is a network of connected nodes (the piles) that fire and pulse like neural tissue. **Cards remain the functional crux** — the player reads them and acts on them, so legibility is paramount. **The connection network is the aesthetic soul** — it's what makes the board alive and beautiful. The two never compete: the network is rich, organic, and ever-present *behind and between* clean, highly-legible cards.

-----

## 1. Palette (muted, warm-organic neural — NOT techno-neon)

Define as CSS variables. Muted and desaturated, not hot/saturated. Avoid a "lit neon sign" look.

- **Background base:** deep muted plum/charcoal — e.g. `#1c151a` center fading to `#0e0a0d` / `#0a070a` edges, via radial gradients.
- **Background haze accents:** very low-opacity warm washes — muted rose `rgba(120,60,80,.20)`, muted violet `rgba(80,60,110,.18)`.
- **Connection (foreground links):** muted rose `#e88bb0`.
- **Signal pulses:** pale warm `#ffe0ee`.
- **Background veins:** dark muted rose `#6a4a5a` (much dimmer than links).
- **Limiting-pile accent:** warm amber `#e0973c` (replaces the old orange).
- **Card face:** light, near-white with a faint cool tint — `#faf8f7 → #ece7ea → #d4ccd2` radial.

Tune to taste; these are the reference values.

-----

## 2. Cards

- **Shape:** rounded rectangle, generously rounded corners (~24px radius), "light-core" look — a bright luminous center fading to a soft edge (radial gradient face). Soft, slightly organic, NOT a sharp flat rectangle. A subtle 1px light rim + soft outer glow in the suit color.
- **Breathing:** each card pulses *very* subtly (scale ~1.01, ~4.5s loop). Barely perceptible — life, not distraction.
- **Face is LIGHT** for maximum rank legibility. This is non-negotiable: rank readability is the game.

### Card contents (all must stay legible)

- **Rank:** large, bold, dark ink (`#1c1418`), top-left + mirrored bottom-right, plus/or centered — match current game's rank placement. Font: see §5.
- **Suit:** classic suit symbol (heart/diamond/club/spade), two-color:
  - Red suits (heart/diamond): deep muted rose `#b5566f` — NOT bright red.
  - "Black" suits (club/spade): dark ink `#2c2430` — readable dark on the light card (true black is fine too; the point is dark, since the pale version only applies on the dark background, never on cards).
  - Keep the suit symbol in BOTH the corner index and as the larger card motif, per current layout.
- **Size badge:** small dark pill/circle, suit-accent border, bottom corner — shows pile card count, as now.
- **Limiting pile(s):** the pile(s) equal to the current smallest-alive-pile size get an amber ring/glow (`#e0973c`) instead of the normal suit glow. Same logic as the existing orange limiting-pile indicator, restyled.

-----

## 3. The connection network (the signature element)

Three stacked depth layers, kept visually distinct so the meaningful layer (links) never blurs into the background:

### Layer A — background haze (furthest back)

Soft, heavily-blurred color-wash blobs (warm rose/violet), very low opacity, slow or static. Pure atmosphere.

### Layer B — background veins (behind cards)

Faint, heavily-blurred (`blur(~2.5px)`), low-opacity (~.5), dark muted curves. **Static. No signal pulses.** Pure tissue texture — the player should never confuse these with real connections. They must look clearly *behind* and *fainter* than the real links.

### Layer C — pile connections (FOREGROUND, the real network)

The meaningful layer. Crisp, brighter, sits on top, and is the **only** layer that carries traveling signal pulses.

**Which links exist (full visual mesh):**

- Every card connects to all of its grid neighbors — N/S/E/W **and diagonals** (up to 8 neighbors).
- This is **VISUAL ONLY.** Game adjacency/logic is unchanged. The mesh is for the look; it does not change which piles interact in gameplay.

**Connection thickness rule (important — encodes the core mechanic):**

- A connection's thickness/brightness is gated by the **smaller** of the two piles it connects: `thickness = f(min(pileA.size, pileB.size))`.
- At run start every pile is size 1 → **every connection is the same minimum thickness.**
- A link only thickens as the *weaker* of its two endpoints grows. If A=4 but neighbor B=1, the link stays thin (gated by B). Only when B grows does that link thicken.
- This applies to **all** links including diagonals (same rule).
- Visual effect: thin links reveal the board's weak links / bottlenecks at a glance — reinforcing the "limiting pile" tension that drives scoring.

**Signal pulses:**

- Small bright dots travel along each *live* connection (Layer C only). More/faster pulses on stronger (thicker) links. This motion is the primary cue that distinguishes real connections from background veins.

-----

## 4. Death & reconnection (makes the network feel alive)

When a pile dies:

1. The dead pile **dims/recedes** (a cold, dark, "scar" state) and its connections **sever with an animation** (dissolve/fade).
1. **Cards stay in place** — the board does NOT reflow positions. The dead pile leaves a visible dimmed scar where it was.
1. **New connections form between the now-adjacent survivors**, bridging across the dead pile. Adjacency is recomputed treating the dead pile as removed from the grid — e.g. if a column's middle pile dies, the top and bottom piles form a new direct connection across the gap.
1. The new bridging connection follows the **same thickness rule** — gated by the smaller of the two newly-connected piles.

(Keep this behavior driven by the real alive/dead pile state the engine already tracks. The visual reacts to state; it doesn't change state.)

-----

## 5. Typography

- **Title / display:** an organic, soft font — **Josefin Sans** (reference choice; tall, elegant, soft). NOT a techno/geometric/space font (no Oxanium/Orbitron). Open to a similarly soft organic alternative.
- **Ranks / gameplay text:** **Chakra Petch** (clean, legible, slightly technical) — or any clean face that keeps ranks instantly readable. Ranks must never sacrifice legibility for style.
- Load via Google Fonts. No Inter/Roboto/Arial/system defaults.

-----

## 6. Background

- Warm organic *tissue*, NOT space. Deep muted-plum radial base + faint warm haze blobs + faint blurred veins (Layer A/B above).
- **No starfield, no scattered star-points** — those read as the old astronomy theme and must be removed.

-----

## 7. Motion summary (restrained, organic, performant)

- Cards: subtle breathing pulse.
- Connections: traveling signal pulses (live links only).
- Background: slow drift on haze, static veins.
- All CSS/SVG-driven where possible for mobile Safari performance. Restrained — atmosphere, not a screensaver.

-----

## 8. Hard constraints (unchanged from the live game)

- Presentation only — gameplay, engine, economy, state, and persistence logic untouched.
- Fits one screen, NO scrolling. Run 1 (10 piles, 4-tall middle column) is the tight layout constraint.
- Cards remain the primary, fully-legible play surface. Rank, suit, size, sticker badges, limiting-pile indicator all instantly readable.
- Mobile-first, locked viewport (no accidental scroll/zoom, as already implemented).

-----

## 9. Open / deferred (not part of this build)

- **Name:** the game may be renamed for the neural theme (placeholder in mockups was "CORTEX"). Decide separately; not required for this visual build.
- **End-of-run cinematic** (network dissolves, surviving nodes glow, etc.) — a future phase, not in this build.
- **Sticker/Pillar icon restyle** to match the neural language — future polish, not this build.
