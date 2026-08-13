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
                    dealPileFirst   PILE 1 specifically (the guided 3 → Ace)
                    dealRailUp      the ▲ higher button on the left rail
                    dealDeckChar    the deck character in the corner
                    sameShield      the Same-shield chip in the HUD
                    dealHistogram   the deck-composition histogram band
                    pileCount       pile 1's card-count badge
     text         the bubble copy (markup above)
     button       the advance button's label — omit for "Next"
     advance      HOW the step dismisses (the choreography knob):
                    "next"    (default) the button
                    "tapPile" the player taps pile 1
                    "higher"  the player taps the ▲ rail button
                    "guess"   the player resolves any guess
                    "swipe"   the player swipe-guesses
                  Event-gated steps show no button; taps outside the ringed
                  anchor are swallowed while "tapPile"/"higher" wait.
     wait         hold this bubble back until N more guesses have resolved
                  since the previous bubble dismissed (free play between).
     orWrong      with `wait`: the FIRST WRONG guess also releases it.

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

    // The guided first Zen deal: a scripted opening (a 3 waits on pile 1 and
    // an Ace sits on top of the deck), then milestone tips between stretches
    // of free play.
    deal: [
      { anchor: "dealBoard",
        text: "Choose a pile and guess if the next card dealt will be *higher* or *lower* than the card shown." },
      { anchor: "dealPileFirst", advance: "tapPile",
        text: "Tap the *3*." },
      { anchor: "dealRailUp", advance: "higher",
        text: "Tap the *higher* button to guess that the next card drawn will be higher than this 3." },
      { anchor: "dealPileFirst",
        text: "You guessed correctly. *Aces count as high* in this game and *2s are low*." },
      { advance: "guess",
        text: "Pick another pile and make a *new guess*." },
      { anchor: "dealDeckChar",
        text: "Cards are drawn from *this deck*. The number on the deck is how many cards remain." },
      { text: "Try to make *more guesses*." },
      // The wait cadence is budgeted against EASY's whole deal: 26 cards − 7
      // dealt = 19 draws, and the scripted opening spends 2. These waits sum
      // to 14, so the tour lands its GO with draws to spare — at 3s across
      // the board it overran the deck and the WIN presentation fired under
      // the last bubble.
      { wait: 4, orWrong: true,
        text: "If you make a wrong guess, the *pile is killed*. Your goal is to get through the *entire deck* before all your piles are killed." },
      { wait: 2, anchor: "dealHistogram",
        text: "This graph tells you how many cards of each rank *remain in the deck*. You can *hold* on a rank and it will tell you how many remaining cards are higher or lower than it." },
      { wait: 2, anchor: "sameShield",
        text: "You can make a *Same* guess too! A correct Same guess charges this *shield*, protecting a pile from your next wrong guess." },
      { wait: 2, advance: "swipe",
        text: "You can also *swipe* on piles instead of tapping. It's faster!\nSwipe *up* to guess higher\nSwipe *down* to guess lower\nSwipe *to the side* to guess same" },
      { wait: 2, anchor: "pileCount",
        text: "This number tells you how many cards are in this pile." },
      { wait: 1, button: "Go",
        text: "Try to get through the *whole deck* before running out of piles. *Good luck!*" },
    ],

    // That first guided deal just ended: one passive line, then free play.
    zenEnd: [
      { button: "Let's play",
        text: "That's it. *Good luck!*" },
    ],

  },

  /* --------------------------------------------------------------------
     MAP HINTS — the scroll-past lines at the very bottom of the map.
     Edit freely: any mix of flavor and real tips. One line shows per
     climb, rotating with runs completed. Keep each under ~90 chars so it
     fits the map's width without wrapping.
  -------------------------------------------------------------------- */
  mapHints: [
    "Up is home.",
    "Calling Same on a Joker always lands. It banks the Same shield AND fires your Same-Power.",
    "Mama's waiting at the top.",
    "A correct Same banks a shield that saves a pile from death. It never stacks, so spend it.",
    "Nothing down here but felt.",
    "Ties kill on Higher or Lower. Call Same, or carry a Same-Safe.",
    "Anchor a tiny pile and it stops dragging your payout down.",
    "Pinky believes in you.",
    "Rerolls climb in price within a shop visit. Next store, fresh price.",
    "Bosses always deal your whole deck. Keep it lean.",
    "Hold the histogram and drag. It counts how many cards are higher, lower, or same.",
    "Fan mode spreads a pile so you can see every card in it.",
    "Hold anything (a card, a node, a shop item) and it tells you what it does.",
    "Cards can only carry up to four stickers.",
  ],
};
