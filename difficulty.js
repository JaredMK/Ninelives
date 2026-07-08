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
     tiers.<id>.jokerCap    max Jokers a run may gain on this tier. Once the
                            cap is reached (owned + still-waiting on the map),
                            Jokers stop appearing anywhere — map cards, map
                            packs, store card packs. 0 = no Jokers at all.
                            Tiers with a cap ≥ 1 GUARANTEE one Joker appears
                            as a standalone map card somewhere in the run.
     endlessBandStep        past stage 3, BOTH edges of BOTH bands lift by
                            this much per endless stage, starting from the
                            selected tier's stage-3 bands

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
      stageBands: [[1.5, 3.0], [2.5, 4.5], [4.0, 5.5]],
      bossBands:  [[2.3, 3.0], [3.75, 4.5], [5.5, 6.0]],
      jokerCap: 2,
    },
    // Unlocks after beating the deck's Regular.
    master: {
      label: "Master",
      stageBands: [[1.5, 4.0], [3.5, 5.5], [5.0, 6.5]],
      bossBands:  [[3.3, 4.0], [4.75, 5.5], [6.5, 7.0]],
      jokerCap: 1,
    },
    // Unlocks after beating the deck's Master. Boss bands derived by applying
    // the Regular→Master increment (+1.0 to both edges of every stage) again.
    legendary: {
      label: "Legendary",
      stageBands: [[1.5, 4.5], [4.0, 6.0], [5.5, 7.5]],
      bossBands:  [[4.3, 5.0], [5.75, 6.5], [7.5, 8.0]],
      jokerCap: 0,
    },
  },
};
