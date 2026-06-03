# Constellation redesign — overnight build notes

Branch: `constellation-redesign` (never merged to main; live game untouched).
**Preview (open on phone):** https://jaredmk.github.io/Ninelives/preview/
Live game (unchanged): https://jaredmk.github.io/Ninelives/

The build badge at the bottom of the screen shows which phase is live
(`v0.55 · cinematic` once Pages finishes the last deploy). Hard-refresh if you
opened it earlier — fonts/CSS cache for a few minutes.

Each phase is a separate commit so you can review them independently:
`icons → nodes → network → suits → cinematic` (plus the earlier `atmosphere`).

> Note: there is no `frontend-design` skill installed in this environment, so I
> applied those design principles directly rather than invoking a skill.

All **640 engine tests pass**; gameplay/logic/state and the DOM-free engine are
unchanged throughout — everything here is presentation.

---

## Design system (commit: "custom celestial SVG icon family")
- New `Icons` module: one designed hand — 24×24 grid, `currentColor` strokes at
  a shared weight, minimal celestial line-art. Covers **every** glyph: the four
  suit archetypes, all 26 stickers, 16 Pillars, packs, and the HUD/store/chrome
  marks + the big overlay marks.
- Replaced emoji rendering **everywhere a player sees it** (badges, mini-cards,
  deck pill, store tiles + buy buttons, Pillar indicators + column chips,
  inventory/tray, pack reveal/info, help + peek popups, coin breakdown, overlay
  icons). The registry `icon:` fields still hold the old emoji strings but are
  **no longer rendered** (left in place so nothing keyed off them breaks).

## Phase 1 — Atmosphere (committed earlier as `v0.50`)
Deep night-sky `#sky` layer behind everything (`z-index:-1`, `pointer-events:none`):
gradient void + screen-blended nebula, three parallax star fields with offset
twinkle, SVG film grain, vignette. Celestial palette mapped onto the existing
CSS variables. Type: **Cormorant Garamond** (display) + **Jost** (UI) via Google
Fonts. Card/deck-strip/breakdown rank glyphs pinned to the original font stack so
board info is byte-identical. Re-fits the board on `document.fonts.ready` (FOUT
no-scroll guard).

## Phase 2 — Nodes float in space (`v0.52`)
Each pile drifts on a slow, low-amplitude, transform-only float (per-node phase/
duration/amplitude set in JS so the field never breathes in lockstep) with a
faint breathing aura. Cards became crafted objects (soft cool-white gradient,
starlight rim, inner highlight/shade) — rank/suit/size/badges fully legible
(ink + font unchanged). Death = collapse (drains of light, cools, dims; aura
fades; a collapsed-star mark replaces the old red X). Card back shows a
constellation crest.

## Phase 3 — Constellation network (`v0.53`)
SVG layer behind the cards links vertically-adjacent **alive** piles per column.
Strength = the **weaker** pile's card count: 1 → faint starlight, 5+ → layered
halo+glow strokes carrying travelling sparks. Only consecutive alive piles
connect, so a dead middle pile's neighbours **re-link directly**; on a death the
layer dips and redraws (links dissolve, survivors re-form). Redraws on every
deal/guess/guard/heart and on resize. `pointer-events:none`, below the cards.

## Phase 4 — Suits → celestial archetypes (`v0.54`)
`♠ → Star · ♥ → Sun · ♦ → Moon · ♣ → Planet`, drawn as custom SVG on card
corners + the centre emblem and on mini-cards, peek/info titles, store tiles,
Pillar indicators, sticker badges, and the coin breakdown. Suit-change/guard/
bounty/all-suit **text labels + descriptions** were relabelled to celestial
terms. **No suit logic changed** — the engine still keys off `♠/♥/♦/♣`; suits
stay red/black via the face colour.

## Phase 5 — End-of-run cinematic (`v0.55`)
Run end → quiet beat → dead nodes dissolve to stardust → card faces dissolve,
leaving only the survivors' glowing celestial symbols floating → the network
collapses to a **uniform layer count = the smallest surviving pile** (the
limiting node made visible) → survivors glow and the score appears. A **win**
ignites the whole board (warm emblem glow, gold pathways, swirling stardust).
CSS/SVG-only; honors `prefers-reduced-motion` (skips to the score).

---

## Places I was unsure / flags for you

- **Phase 4 — suit references I judged but you should sanity-check:**
  - **Deck composition strip / graph is RANK-based, not suit-based** — it shows
    rank counts (2..A), so there were no suit symbols to re-skin there. Nothing
    changed in the strip; flag me if you expected suit symbols on it.
  - **"Extra Heart" is a LIFE, not the Hearts suit.** I deliberately kept it as a
    heart glyph/label (the game is "Nine Lives"); only the Hearts *suit* became
    the Sun. If you'd rather the life pip also be celestial, say so.
  - **Suit→archetype mapping** (♠Star/♥Sun/♦Moon/♣Planet) is my call for
    consistency; easy to re-map if you prefer a different pairing.
  - Relabelling Pillars/stickers changed the **engine logbook** text (e.g. "Spade
    Bounty" → "Star Bounty"); I updated the one test that asserted it. Logic is
    unchanged.

- **Readability calls (paramount per your brief):**
  - Rank numerals, the suit emblem, pile-size badges, the limiting-pile (orange)
    indicator and the deck strip all stay on their original fonts/sizes/colours.
    The atmosphere/network sit strictly **behind** opaque cards and never overlap
    card faces.
  - The card centre emblem (suit) is drawn fairly bold for legibility; if it
    competes with the rank at the smallest pile sizes, I can lower its opacity.
  - The constellation lines are only visible in the gaps **between** cards (they
    pass behind the card faces) — by design, so they can't obscure information.

- **Couldn't do perfectly / deferred / watch-items:**
  - **External dependency:** the display/UI fonts load from **Google Fonts**.
    Works on Pages; if you want the app fully self-contained again I can
    self-host/embed them.
  - **Debug overlay** (hidden dev tool, `?debug`) still has a couple of emoji on
    its coin buttons — intentionally low-priority; not part of the played game.
  - **Death "dissolve" in Phase 3** is a quick layer dip + redraw rather than a
    per-link particle shatter (the per-card stardust in Phase 5 is the richer
    version). Could be elevated later.
  - **Cinematic vs score panel:** the score overlay's backdrop currently covers
    the board, so the glowing constellation shows during the ~1s cinematic beat
    and then the panel arrives. I kept the backdrop opaque for score legibility
    rather than overlaying text on the glowing board — tell me if you'd prefer
    the constellation to remain visible *behind* the score.
  - **Pre-existing flaky test:** `expansion` uses unseeded `e.start()` and can
    intermittently fail a recycle/deck-count assertion (random deal). It passes
    on re-run; unrelated to this work (engine untouched). Worth seeding later.
  - I did **not** keep iterating/polishing past a first draft of each phase, per
    your instruction — these are review-ready drafts, not final art.

## Suggested things to judge in the morning
1. Does the overall frame read as **art** (atmosphere + type + icons + suits)?
2. Is **every** card's rank/suit/size/badge + the orange limiting-pile indicator
   + the deck strip still instantly readable? (If anything got harder, name it.)
3. Phase-by-phase taste: float amplitude, network density/brightness, the suit
   archetypes, and the end cinematic pacing — each is easy to dial.
