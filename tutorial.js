/* ============================================================================
   NINELIVES TUTORIAL DATA — the single hand-editable source for every
   first-run tutorial bubble (TUT2, guided + gated).

   Edit this file to reword the tour: bubble copy, button labels, the anchor
   each bubble points at, and the pinned map seed live HERE. The game logic
   (in index.html) owns everything else — the sequence of bubbles, the hard
   input gates, the forced purchases and grants, and when each group fires —
   so this file can reword any bubble but never add, remove, or reorder one.

   WRITER MARKUP (inside every `text` and the grant clause):
     *asterisks*   the pink BOLD words in a bubble
     newlines      a literal line break in the string (\n) is a real line
                   break in the bubble
   The game escapes the raw text FIRST and only then applies the markup, so
   nothing written here can inject HTML.

   Shape of a step (each groups.<key> entry and each hops.<type>):
     anchor       WHICH on-screen element the bubble points at (ring + arrow)
                  — one of the game's anchor keys below. Omit it for a
                  centered, arrow-less bubble. Unknown keys fail loudly at
                  load and the tour bows out rather than soft-locking.
                    deckSelectPinky  the big Pinky character (deck select)
                    mapAvatar        Pinky's marker at the trail's foot
                    mapCardNode      a visible card/pack node (Pinky if none)
                    gateNode         THE one glowing (gated) map node
                    dealBoard        the board of piles
                    dealPile         a living pile
                    dealDeckChar     the deck character in the corner
                    sameShield       the Same-shield chip in the HUD
                    payoutLine       the summary's deal-reward + sub-rows
                    summaryBalance   the summary's "Coins held" balance row
                    storeCoins       the shop's coin balance
                    gatedTile        THE one gated shop shelf tile
                    rerollBtn        the shop's Refresh button
                    storeShelf       the whole shop shelf
                    storeExit        the GO TO MAP button
                    stickerBanner    the sticker banner atop the card picker
                    deckCount        the deck count in the map header
     text         the bubble copy (markup above; placeholders below)
     button       the advance button's label — omit for "Next"

   LIVE PLACEHOLDERS (resolved fresh every time a bubble shows, so a data
   edit elsewhere never leaves the copy stale):
     {stickerLabel}   the forced sticker's items.js label   ("Bonus Coin")
     {stickerPayout}  the forced sticker's items.js description ("+1 coin")
     {deckSize}       the live deck size at that moment
     {grant}          the grant clause below, on its own line, ONLY when that
                      step just topped the balance up — empty otherwise

   THE TOUR AT A GLANCE (all choreography in index.html):
   - Every bubble carries a small "Skip tips" link. Skip ends the WHOLE tour
     instantly: all gating removed, marked seen (ninelives.pref.tutorial2).
     The tour is otherwise marked seen only when it COMPLETES (the final
     battle deal starts) — losing the run mid-tour restarts it on the next
     fresh campaign.
   - GATES: while a step is gated, ONLY its named control accepts input — on
     the map every other legal node dims and goes inert; in the shop only the
     gated tile / Refresh / GO TO MAP is live. Guessing is never gated.
   - HOPS: the guided path on the PINNED map below is zero-hop (deal → store
     → +1 card → deal, each one tap apart), so the hops.* notes never show
     there. They exist for the dynamic fallback (stale pin): each gated stop
     that is NOT the leg's goal gets one short note by node type.
   - GRANTS: when a forced buy/Refresh is unaffordable, exactly the shortfall
     arrives via the normal credit path and that step's {grant} fills in.

   PINNED SEED: the tutorial map everyone shares. The generator itself never
   changes for the tour — this seed simply IS the first-run map, verified to
   open with the strict chain above. If a generator or difficulty.js change
   invalidates it, the game falls back to rolling seeds live (and the test
   suite fails with a "re-pin the tutorial seed" message): verify a new seed
   and update the number here.

   Malformed entries do NOT silently disappear: the game validates this file
   on load and fails loudly in the console naming the offending group/step.

   TWO EDITING RULES THAT MATTER MORE THAN THE REST:
   - Keep each text on ONE line between its double quotes; type \n for a line
     break; never type a bare double-quote inside the text. A broken quote or
     comma is a JavaScript syntax error the validator can't catch — the whole
     game stops loading until it's fixed.
   - The three shop bubbles that carry {grant} must KEEP their {grant} token:
     deleting it silently orphans the coin-grant feedback (the coins would
     tick up with no words explaining why).
   (Also: the hops "deal" note doubles for boss nodes.)
============================================================================ */
"use strict";

const NINELIVES_TUTORIAL = {

  // The pinned first-run map seed (strict chain: opening deal → adjacent
  // store → adjacent +1 card → adjacent deal). See PINNED SEED above.
  // Re-pinned to 18 after the Regular-tier difficulty bands changed (the old
  // seed 32 no longer opens the strict guided chain under the new bands).
  seed: 18,

  // Appended (via {grant}) to a forced step's bubble when it topped the
  // balance up, paired with a coin tick + a pulse on both counters.
  grant: "A few coins *on the house* to cover it.",

  // One short note per node type for a gated stop that is NOT the current
  // leg's goal (dynamic-fallback maps only — never on the pinned map).
  hops: {
    deal:   { anchor: "gateNode", button: "Got it",
              text: "A *deal* blocks the path — survive it and press on." },
    store:  { anchor: "gateNode", button: "Got it",
              text: "Another *shop* on the way — pass through." },
    pack:   { anchor: "gateNode", button: "Got it",
              text: "A *card pack* on the way — take it." },
    pickup: { anchor: "gateNode", button: "Got it",
              text: "A free *card* on the way — take it." },
  },

  groups: {

    // Deck select (the first Play) — meet Pinky.
    pinky: [
      { anchor: "deckSelectPinky", button: "Let's go",
        text: "This is *Pinky* — he's lost, a long way from mama.\nHelp him climb home." },
    ],

    // Map, first visit: the goal, the loop, then the gated first deal.
    map1: [
      { anchor: "mapAvatar",
        text: "Pinky starts down here and must climb up." },
      { anchor: "mapCardNode",
        text: "*Card nodes* grow Pinky's deck as he climbs — and a bigger deck means *longer, harder deals*.\nDrafting well and shopping for upgrades is how you keep up." },
      { anchor: "gateNode", button: "Got it",
        text: "Tap the *glowing node* to set off to your first deal." },
    ],

    // First deal, as the board appears (guessing is never gated).
    deal: [
      { anchor: "dealBoard",
        text: "*Goal: survive.* Every pile is a life." },
      { anchor: "dealPile",
        text: "Pick a pile, then *swipe*:\n↑ higher\n↓ lower\nsideways for same.\nOr tap the pile and use the buttons on the left" },
      { anchor: "dealDeckChar",
        text: "Every guess draws from *Pinky's deck*.\nCorrect guess → the pile grows\nWrong guess → the pile dies\nBeat the *whole deck* before every pile is gone." },
      { anchor: "sameShield",
        text: "*Same* guesses are hard. A correct Same call charges this *shield*, which saves your next miss." },
      { button: "Go",
        text: "Your turn — make a guess!" },
    ],

    // First deal summary: the payout formula, then where coins live.
    coins: [
      { anchor: "payoutLine",
        text: "Coins = *surviving piles × smallest pile*\nSpend coins on upgrades." },
      { anchor: "summaryBalance", button: "Got it",
        text: "Your *coins* bank into this balance — the same counter rides the top bar on every screen." },
    ],

    // Map, after the first payout: the gated walk to the shop.
    toStore: [
      { anchor: "gateNode", button: "Got it",
        text: "Shops along the trail sell *upgrades* — let's visit one.\nFollow the *glowing node*." },
    ],

    // Guided shop: the balance, then the forced sticker buy.
    shopC: [
      { anchor: "storeCoins",
        text: "Welcome to the shop. Your *coins* to spend sit here — the same balance as the top bar.{grant}" },
      { anchor: "gatedTile", button: "Got it",
        text: "*Stickers* attach to *one card* and ride it for the whole run.\nThis *{stickerLabel}* pays *{stickerPayout}* — tap it to buy." },
    ],

    // Guided shop: the taught Refresh.
    shopD: [
      { anchor: "rerollBtn", button: "Got it",
        text: "*Refresh* re-rolls the whole shelf for coins — the price climbs each use within a visit.\nTap *Refresh*.{grant}" },
    ],

    // Guided shop: the forced Guardian buy + column placement.
    shopE: [
      { anchor: "gatedTile", button: "Got it",
        text: "*Pillars* bind to the top of a column and work passively every deal.\nThe *Guardian* pays out when every pile in its column survives — tap it and pick a column.{grant}" },
    ],

    // Guided shop: bases + Same-Powers (words only), then the exit.
    shopF: [
      { anchor: "storeShelf",
        text: "Two more kinds live on this shelf.\n*Bases* sit at a column's foot — a once-per-deal power you tap during play." },
      { anchor: "storeShelf",
        text: "*Same-Powers* equip to the Same button — exactly one at a time, firing on every correct *Same* call." },
      { anchor: "storeExit", button: "Got it",
        text: "All stocked up — tap *GO TO MAP* to head back out." },
    ],

    // The buy-time card picker during the forced sticker buy.
    stickerPicker: [
      { anchor: "stickerBanner", button: "Got it",
        text: "This sticker is *♥ only* — other suits grey out.\nTap a *heart*, then confirm." },
    ],

    // Map, back from the shop: the gated walk to the +1 card.
    toPickup: [
      { anchor: "gateNode", button: "Got it",
        text: "Travel on to *draft new cards* — every card node grows Pinky's deck, and a bigger deck means harder deals… but more power to win with.\nGrab the *+1 card* ahead." },
    ],

    // Map, the drafted card just flew in: the grown deck, then the battle
    // whose start completes the tour.
    grew: [
      { anchor: "deckCount",
        text: "The deck just *grew* — Pinky now carries *{deckSize} cards*.\nMore cards = longer deals, but more to win with." },
      { anchor: "gateNode", button: "Go",
        text: "Time to *battle* — tap the deal. Good luck!" },
    ],

  },
};
