/* ============================================================================
   NINELIVES DIFFICULTY DATA — the hand-editable difficulty-band table.

   Edit this file to tune how hard each TIER plays. Every deck offers three
   tiers on the deck-select screen — Regular / Master / Legendary — and the
   map generator reads the selected tier's bands LIVE from this file. Bands
   are the same index-based stage bands for all four decks (Pinky reads them
   as the ♦ → ♣ → ♠ stages; Mamma / Mr. Smith / Lammy as stage 1 → 2 → 3).
   Tiers change BANDS + the JOKER CAP — prices, subset deals and every other
   rule are identical across tiers.

   Shape:
     tiers.<id>.label       the player-facing tier name
     tiers.<id>.stageBands  [[lo,hi] ×3] — regular deals' target-difficulty
                            band per stage (stage 1, 2, 3)
     tiers.<id>.bossBands   [[lo,hi] ×3] — the stage bosses' band
     tiers.<id>.jokerCap    max Jokers HELD AT ONCE on this tier. While the
                            player is at the cap (deck + pack tray + the
                            guaranteed map Joker still waiting), Jokers stop
                            appearing anywhere — map packs and store card
                            packs; removing a Joker (e.g. via Removal)
                            reopens availability. 0 = no Jokers at all.
                            Map +1 card nodes never roll random Jokers — the
                            ONLY standalone Joker node is the guaranteed one
                            below.
     tiers.<id>.guaranteedMapJoker
                            true → exactly ONE Joker is placed as a visible
                            standalone +1 card node somewhere in stages 1-3
                            (random node per run, never inside a pack, never
                            hidden behind a "?" mystery node)
     endlessBandStep        past stage 3, BOTH edges of BOTH bands lift by
                            this much per endless stage, starting from the
                            selected tier's stage-3 bands

   ZEN MODE (the standalone higher/lower game — no campaign, no coins, no
   items) reads its three difficulties from the `zen` block:
     zen.<id>.label      the player-facing difficulty name
     zen.<id>.suitCount  how many suits the fresh standard deck keeps
                         (1-4; suits enter in the fixed order ♥ ♠ ♦ ♣, so
                         2 = ♥♠, 3 = ♥♠♦, 4 = the full deck). Cards dealt
                         = suitCount × 13 — no jokers, no stickers, ever.
     zen.<id>.piles      how many piles the deck is dealt onto

   Malformed entries do NOT silently disappear: the game validates this file
   on load and fails loudly in the console naming the tier and field.
============================================================================ */
"use strict";

const NINELIVES_DIFFICULTY = {

  // Endless lift per stage past stage 3 (applies to every tier).
  endlessBandStep: 1.25,

  tiers: {
    // The baseline — the game's original band values.
    regular: {
      label: "Regular",
      stageBands: [[1.5, 3.0], [2.0, 4.0], [3.0, 5.0]],
      bossBands:  [[2.3, 3.25], [3.75, 4.25], [4.75, 5.5]],
      jokerCap: 2,
      guaranteedMapJoker: true,
    },
    // Unlocks after beating the deck's Regular.
    master: {
      label: "Master",
      stageBands: [[1.5, 4.0], [3.5, 5.5], [5.0, 6.5]],
      bossBands:  [[3.3, 4.0], [4.75, 5.5], [6.5, 7.0]],
      jokerCap: 1,
      guaranteedMapJoker: false,
    },
    // Unlocks after beating the deck's Master. Boss bands derived by applying
    // the Regular→Master increment (+1.0 to both edges of every stage) again.
    legendary: {
      label: "Legendary",
      stageBands: [[1.5, 4.5], [4.0, 6.0], [5.5, 7.5]],
      bossBands:  [[4.3, 5.0], [5.75, 6.5], [7.5, 8.0]],
      jokerCap: 0,
      guaranteedMapJoker: false,
    },
  },

  // ZEN MODE difficulties (see the header). Each is one plain higher/lower
  // game: a fresh suitCount×13 standard deck dealt onto `piles` piles.
  zen: {
    easy:   { label: "Easy",   suitCount: 2, piles: 7 },
    medium: { label: "Medium", suitCount: 3, piles: 8 },
    hard:   { label: "Hard",   suitCount: 4, piles: 9 },
  },
};
