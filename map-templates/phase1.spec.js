/* ============================================================================
   PHASE MAP SPEC — the fillable authoring format
   ----------------------------------------------------------------------------
   This is the EXACT data structure the game reads (RunMap.parseMapSpec). Fill it
   in node-by-node and edge-by-edge; what you write is what renders — every field
   below controls a real node or edge, with zero interpretation. When you hand
   this back, it gets dropped straight into PHASE_DEFS[0] in index.html.

   A spec has three parts:
     1) suit   — the phase suit (Phase 1 = "♦"). Cards drafted here are this suit.
     2) nodes  — the NODE LIST. Each node has a unique string id, a type, params,
                 and a layout position (tier + x).
     3) edges  — the EDGE LIST. Directed, bottom→top: [fromId, toId]. This is
                 where forks and recombines are defined, unambiguously.

   ── NODE TYPES & PARAMS ────────────────────────────────────────────────────
     { id, type, tier, x, ...params }

     type "start"            run start (NOT drawn on the map). EXACTLY ONE.
                             Its out-edges define the openings (the first row).
     type "deal",  piles: N  a deal across N piles (the only thing that matters).
     type "boss",  piles: N  the phase boss. EXACTLY ONE, at the top. Beating it
                             completes the phase. (No out-edges.)
     type "store"            a shop chokepoint. No params.
     type "card"             adds exactly +1 card (shown face-up = its exact card).
                             Optional:  card: "K♦"     → force that exact card
                                        card: "random" → any draft (default if
                                                          you omit `card`)
     type "pack",  add: N    adds +N cards (N >= 2), shown as a sealed pack.

   ── LAYOUT ─────────────────────────────────────────────────────────────────
     tier : vertical row. Smaller = lower. The bottom (start) is the smallest
            tier; the boss is the largest. Nodes that fork off the same parent
            share the next tier up; a recombine target sits one tier above its
            branches. (Tiers are normalized on load, so 0,1,2,… is simplest, but
            only the ORDER matters — gaps are fine.)
     x    : 0..1 horizontal slot WITHIN the tier. 0 = far left, 1 = far right,
            0.5 = center. Use distinct x values for forked siblings so the
            branches line up visually (e.g. 0.25 / 0.5 / 0.75 for a 3-way fork).

   ── EDGES ──────────────────────────────────────────────────────────────────
     Each edge is [fromId, toId], pointing UPWARD (toward the boss).
       fork      : one `from`  → many `to`   (["d1","a"], ["d1","b"])
       recombine : many `from` → one  `to`   (["a","m"],  ["b","m"])
     The `start` node's out-edges are the opening moves. The boss has no out-edge.

   Every id you reference in `edges` must exist in `nodes`. One start, one boss,
   and the boss must be reachable from the start (no orphans).
============================================================================ */


/* ── WORKED EXAMPLE ──────────────────────────────────────────────────────────
   A small map showing a FORK and a RECOMBINE:

       start → Deal(5) → ┌─ card +1 (forced K♦) ─┐
                         └─ pack +3 ─────────────┴→ card +1 → Store → Boss(6)

   Read it bottom-to-top. "d1" forks to "left" and "right" (a card and a pack);
   they recombine into "mid"; then a store, then the boss. */
export const EXAMPLE_SPEC = {
  suit: "♦",
  nodes: [
    { id: "start", type: "start",                 tier: 0, x: 0.50 },
    { id: "d1",    type: "deal",  piles: 5,        tier: 1, x: 0.50 },
    { id: "left",  type: "card",  card: "K♦",      tier: 2, x: 0.30 },  // forced exact card
    { id: "right", type: "pack",  add: 3,          tier: 2, x: 0.70 },  // a +3 pack
    { id: "mid",   type: "card",                   tier: 3, x: 0.50 },  // +1, random ♦
    { id: "shop",  type: "store",                  tier: 4, x: 0.50 },
    { id: "boss",  type: "boss",  piles: 6,        tier: 5, x: 0.50 },
  ],
  edges: [
    ["start", "d1"],
    ["d1", "left"], ["d1", "right"],   // FORK: the deal splits into two routes
    ["left", "mid"], ["right", "mid"], // RECOMBINE: both routes merge at "mid"
    ["mid", "shop"],
    ["shop", "boss"],
  ],
};


/* ── BLANK PHASE 1 TEMPLATE — fill this in ───────────────────────────────────
   Add one line per node and one line per edge. Keep `start` and `boss` (exactly
   one of each). Everything else is yours: copy the node lines you need, give each
   a unique id, set type + params + tier + x, then wire them in `edges`.

   Tips:
     • Work bottom-to-top: assign tiers in increasing order from start to boss.
     • For a fork, give the parent several edges; for a recombine, point several
       parents at one child.
     • +1 → type "card";  +2 or more → type "pack" with add: N.
     • Only `piles` matters on deals/boss; only `add` matters on packs. */
export const PHASE1_SPEC = {
  suit: "♦",
  nodes: [
    { id: "start", type: "start",            tier: 0,  x: 0.50 },
    // … add your nodes here, e.g.:
    // { id: "d1",  type: "deal",  piles: 5,  tier: 1,  x: 0.50 },
    // { id: "c1",  type: "card",             tier: 2,  x: 0.35 },
    // { id: "p1",  type: "pack",  add: 3,    tier: 2,  x: 0.65 },
    // { id: "s1",  type: "store",            tier: 5,  x: 0.50 },
    { id: "boss",  type: "boss",  piles: 6,   tier: 12, x: 0.50 },
  ],
  edges: [
    // ["start", "d1"],
    // ["d1", "c1"], ["d1", "p1"],
    // … wire every connection here …
    // ["s1", "boss"],
  ],
};
