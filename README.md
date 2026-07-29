# Ninelives

A mobile-first, single-file web card game (legacy name: "Shoulda Said Same").
No frameworks, no backend, no dependencies — open `index.html` in any modern
browser. An iOS wrapper lives in `app/` (Capacitor).

Working conventions for contributors (data-files-as-source-of-truth, perf
invariants, UX rules, workflow) are in `AGENTS.md`.

## How to play

- Cards are dealt face-up into a grid of piles; the rest form the draw deck.
  **Every pile is a life.**
- **Tap a pile**, then guess **Higher**, **Same**, or **Lower** for the next
  card (or swipe: ↑ higher, ↓ lower, sideways same). Suits don't matter for
  guessing — only rank; **Ace is high**.
  - **Correct** → the card lands on the pile (new top).
  - **Wrong** → the pile dies. **A tie kills on a Higher/Lower guess; only a
    correct Same survives a tie.**
- **Win a deal** by emptying the draw deck before every pile dies.
- **Same charges**: a correct Same call banks a charge (max 1) that saves your
  next miss. A **Same-Power** artifact, once equipped, fires an extra effect
  on every correct Same.

## Campaign

A campaign is a climb up a seeded node **map** across **3 stages**, each stage
ending at a **boss** deal. Nodes: deals, stores, card pickups (+1 card), card
packs, mystery ("?") nodes. Clearing the stage-3 boss banks the campaign win
(and offers optional **endless mode** with rising difficulty). **Losing any
deal ends — and wipes — the whole campaign**: a New Campaign resets everything
to a vanilla start; nothing carries across attempts.

**Decks** (unlock chain — win a run with a deck to unlock the next):

| Deck | Quirk |
| --- | --- |
| **Pinky** | The baseline. Stages themed ♦ → ♣ → ♠. |
| **Mamma** | Plain stage 1 → 2 → 3. |
| **Mr. Smith** | Everything costs 2×; starts with stickers. |
| **Lammy** | Stickers don't stick (no sticker use); a Same-Power pre-equipped. |

Each deck offers three **difficulty tiers** — Regular / Master / Legendary
(unlocked by beating the previous tier on that deck). Tiers change the
difficulty bands and the Joker rules only; prices and all other rules are
identical. All band/joker data lives in `difficulty.js`.

## Coins, store & items

Coins are awarded on a **won deal** only:

```
coins = flat deal reward (by stage & difficulty — items.js `economy`)
      + Payout-sticker bonus + scoring-Pillar bonuses + live bonus tally
      (clamped so the total never drops below 0)

score = (alive piles) × (cards in the smallest alive pile)   ← per cleared
        deal, folded into the campaign/endless score (personal bests only)
```

Between deals, **store** nodes offer a one-screen shop: a small weighted
random shelf (stickers, pillars, bases, packs, single cards, same-powers)
plus a permanent Removal slot and a paid Refresh whose price climbs per use
within a visit. Prices are fixed; rarity tiers (common/uncommon/rare) only
bias how often an item is *offered*.

**Every item — prices, rarities, weights, descriptions and all effect numbers
— is data in `items.js`, the single source of truth.** The five item classes:

- **Stickers** — attach to one specific card and ride it for the whole
  campaign (rank shifts, suit changes, guards, coin effects, bury effects,
  peeks…). No per-card limit; some are suit-locked.
- **Pillars** — bind to the top of a board column; passive effects on every
  pile in that column, persisting across deals.
- **Bases** — bind to the bottom of a column; an active once-per-deal power
  you tap during play.
- **Same-Powers** — exactly one equipped; fires on correct Same calls.
- **Packs** — buy to reveal N random items, keep K (cards go to the pack tray
  for pre-deal swaps; stickers to inventory).

## Zen mode

A standalone higher/lower game (no campaign, coins, or items): a fresh
`suitCount × 13` standard deck dealt onto N piles. Three difficulties
(Easy/Medium/Hard) — configured in `difficulty.js`'s `zen` block.

## Persistence

All storage is `localStorage` under `ninelives.*` keys, mirrored to Capacitor
Preferences on iOS by `NativeApp` (WKWebView storage can be evicted; native
is the truth in the app). Keys: `ninelives.save.v1` (campaign checkpoint —
position, coins, deck, items, store offer; saved between deals, so a mid-deal
refresh re-deals from the seed), `ninelives.pref.*` (settings), plus lifetime
records: `ninelives.stats.v1`, `ninelives.telem.v1`, `ninelives.zenstats.v1`,
`ninelives.deckwins.v1`, `ninelives.zenunlocks.v1`. The campaign blob is
cleared on a loss and on campaign completion; lifetime records survive.

## Architecture

All logic is one inline `<script>` in `index.html`; styles in one `<style>`.
The engine is DOM-free (unit-testable in Node); the renderer never mutates
game state. Data files load before the script and are validated fail-loud on
boot.

| Module (index.html) | Responsibility |
| --- | --- |
| `NativeApp` (:75) | Capacitor bridge: storage write-through, safe areas, haptics. |
| `Telem` (:6848) | Per-item impact telemetry. |
| `ItemData` (:7263) · `DifficultyData` (:7412) · `TutorialData` (:7527) | Load + validate the three data files. |
| `DECK_RULES` (:7602) | Per-deck modifiers (suits, price multiplier, sticker rules). |
| `StickerTypes` · `PillarTypes` · `BaseTypes` · `SamePowerTypes` · `PackTypes` | Registries over the items.js groups. |
| `Economy` (:8372) | Pure win-payout math: the flat deal reward + item bonuses; the piles×smallest product rides the breakdown as the score. |
| `DeckManager` (:7810) | Card pool: build, seeded shuffle (mulberry32), draw, peek. |
| `RunMap` (:8021) | Seeded map generator; reads tier bands live from DifficultyData. |
| `DeckStats` (:9605) · `BoardState` (:9628) | Deck composition tallies; live pile board. |
| `GameEngine` (:9771) | Deal rules + effect dispatch keyed by items.js `behavior`/`effect`. |
| `CampaignState` (:11933) | Meta state: coins, inventories, deck, map traversal, store, jokers, save/restore. |
| `SaveStore` (:14205) · `Stats` (:14250) · `ZenStats` (:14336) · `DeckUnlocks` (:14392) · `ZenUnlocks` (:14469) | Persistence. |
| `Sound` (:14524) · `DeckInspector` (:14724) | WebAudio registry; read-only deck overlay. |
| `UIRenderer` (:14963) | All DOM: screens, HUD, store, map, tutorial, input, animation. |

Screens are full-screen overlays toggled with `.hidden` (menu → deck select →
map → deal → store → summary → zen); input is delegated and attached once at
boot; one rAF clock drives board motion and pauses behind overlays.

## Tests

```sh
node tests/all.mjs   # must be 100% green before any commit
```

`tests/_harness.mjs` extracts the game `<script>` and evaluates it with a
stubbed DOM, so the DOM-free engine modules are tested in Node. Each
`*.test.mjs` exports `run()`; suites register in `tests/all.mjs`. Tests pin
rules, never tunable numbers (they read `ItemData`/`DifficultyData` live).

## Debug & build

- `?debug` URL param (or triple-tap the title): force the next card, peek,
  trim the deck, jump to win/loss, telemetry table, autopilot.
- The footer shows `build vX.YZ` (from `APP_VERSION`) and logs it to the
  console.
- Deploy: pushing the live branch rebuilds the GitHub Pages site
  (`.github/workflows/pages.yml`).
