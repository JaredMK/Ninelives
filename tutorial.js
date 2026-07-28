/* ============================================================================
   NINELIVES TUTORIAL DATA — the single hand-editable source for every
   first-run tutorial bubble (Zen-first flow).

   New players learn the CORE MECHANICS ONLY, inside their first Zen deal:
   survive the piles, swipe to guess, the deck draws, ties kill unless you
   call Same, Ace is high, and the histogram. No campaign concepts here (no
   map, shops, stickers, decks) — those are met in the run itself. When the
   last bubble is dismissed the tour stamps ninelives.pref.tutorial2 and the
   player simply keeps playing Zen; the campaign unlocks on the menu after
   this tutorial plus a first Zen session (see index.html, maybeUnlockCampaign).

   Edit this file to reword the tour: bubble copy, button labels, and the
   anchor each bubble points at live HERE. The game logic (in index.html)
   owns everything else — when each group fires and what a step rings — so
   this file can reword any bubble but never add, remove, or reorder one.

   WRITER MARKUP (inside every `text`):
     *asterisks*   the pink BOLD words in a bubble
     newlines      a literal line break in the string (\n) is a real line
                   break in the bubble
   The game escapes the raw text FIRST and only then applies the markup, so
   nothing written here can inject HTML. Placeholders ({likeThis}) are NOT
   supported in this flow — the validator rejects them loudly.

   Shape of a step (each groups.<key> entry):
     anchor       WHICH on-screen element the bubble points at (ring + arrow)
                  — one of the game's anchor keys below. Omit it for a
                  centered, arrow-less bubble. Unknown keys fail loudly at
                  load and the tour bows out rather than soft-locking.
                    dealBoard       the board of piles
                    dealPile        a living pile
                    dealDeckChar    the deck character in the corner
                    sameShield      the Same-shield chip in the HUD
                    dealHistogram   the deck-composition histogram band
     text         the bubble copy (markup above)
     button       the advance button's label — omit for "Next"

   THE TOUR AT A GLANCE (all choreography in index.html):
   - groups.deal fires on the guided first Zen deal, as its board appears.
     Guessing is never gated — the player may simply play through the tips;
     the first resolved guess steps any lingering bubble aside (unstamped,
     so the tour offers itself again next deal).
   - Every bubble carries a small "Skip tips" link. Skip ends the tour
     instantly and stamps it seen (ninelives.pref.tutorial2), same as
     completing it.
   - groups.zenEnd fires ONCE, when that first guided deal ends — one
     passive line naming what just unlocked. No prompt to leave; free Zen
     play continues for as long as the player likes.

   Malformed entries do NOT silently disappear: the game validates this file
   on load and fails loudly in the console naming the offending group/step.

   THE EDITING RULE THAT MATTERS MORE THAN THE REST:
   - Keep each text on ONE line between its double quotes; type \n for a line
     break; never type a bare double-quote inside the text. A broken quote or
     comma is a JavaScript syntax error the validator can't catch — the whole
     game stops loading until it's fixed.
============================================================================ */
"use strict";

const NINELIVES_TUTORIAL = {

  groups: {

    // The guided first Zen deal, as the board appears (guessing never gated).
    deal: [
      { anchor: "dealBoard",
        text: "*Goal: survive.* Every pile is a life." },
      { anchor: "dealPile",
        text: "Pick a pile, then *swipe* to guess the next card against that pile's *top card*:\n↑ higher\n↓ lower\nsideways = *same*\nOr tap the pile and use the buttons on the left." },
      { anchor: "dealDeckChar",
        text: "Every guess draws the next card from *the deck*.\nRight → the pile grows\nWrong → the pile dies\nBeat the *whole deck* before every pile is gone." },
      { anchor: "sameShield",
        text: "Call *Same* when you expect an equal card — a *tie kills* a Higher or Lower guess, so 'close' never counts. A correct Same charges this *shield*, saving your next miss." },
      { anchor: "dealPile",
        text: "Cards run *2 up to Ace* — Ace is *high*: never guess Higher against it.\nAnd a 2 is as low as it gets: never guess Lower against that." },
      { anchor: "dealHistogram",
        text: "This strip is *the histogram* — it counts what's left in the deck at every rank.\nRead it before a guess: tall bars are the cards you're most likely to draw." },
      { button: "Go",
        text: "Your turn — make a guess!" },
    ],

    // That first guided deal just ended: one passive line, then free play.
    zenEnd: [
      { button: "Let's play",
        text: "That's the whole game — stay as long as you like.\nThe *climb home* waits on the menu whenever you head back." },
    ],

  },
};
