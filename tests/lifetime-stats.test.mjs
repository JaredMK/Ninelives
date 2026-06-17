// Lifetime-stats plumbing: the engine/state hooks that feed the lifetime stats
// screen. Stats itself is a localStorage shim (untestable in Node), so we test
// the DOM-free sources it reads:
//   - DeckManager: deck.drawn() counts cards pulled from the deck.
//   - GameEngine: run.cardsDrawn = cards drawn during ACTIVE play (the initial
//     deal is excluded), the source of the lifetime "Cards drawn" tally.
//   - CampaignState: the playedCounted guard (a run counts as played on the
//     first guess) round-trips through serialize/restore and clears on reset.
import { loadGame, makeRunner } from "./_harness.mjs";

export function run() {
  const { GameEngine, DeckManager, CampaignState } = loadGame();
  const r = makeRunner("lifetime-stats.test.mjs");

  // --- deck.drawn() counts every pull, never un-counts a returnCard ------
  {
    const deck = DeckManager.create(DeckManager.buildStandardDeck());
    r.eq(deck.drawn(), 0, "a fresh deck has drawn 0 cards");
    const a = deck.draw(), b = deck.draw(), c = deck.draw();
    r.eq(deck.drawn(), 3, "three top draws count as 3");
    deck.drawFromBottom();
    r.eq(deck.drawn(), 4, "a bottom draw also counts");
    deck.returnCard(a);                       // back into the deck
    r.eq(deck.drawn(), 4, "returning a card does NOT un-count the draw");
    deck.draw();
    r.eq(deck.drawn(), 5, "re-drawing the returned card counts again");
  }

  // --- run.cardsDrawn excludes the deal, counts play draws ---------------
  {
    const e = GameEngine.create(DeckManager.buildStandardDeck(), 9);
    e.start();
    e.startRun();                             // snapshots the deal's draws
    r.eq(e.getRun().dealDraws, e.getBoard().size, "deal draws = one card per pile");

    // Three guaranteed-correct guesses (draw == top, guess "same" survives a
    // tie): each draws exactly one card from the deck.
    for (let k = 0; k < 3; k++) {
      e.debug.setNextCard(e.getBoard().top(0).value);
      e.guess(0, "same");
    }
    r.eq(e.getRun().cardsDrawn, 3, "cardsDrawn = play draws only (deal excluded)");
  }

  // --- playedCounted guard: persists, round-trips, resets ---------------
  {
    const a = CampaignState.create();
    r.ok(!a.isPlayedCounted(), "a fresh campaign has not been counted as played");
    a.markPlayed();
    r.ok(a.isPlayedCounted(), "markPlayed() flips the guard");

    const wire = JSON.parse(JSON.stringify(a.serialize()));
    const b = CampaignState.create();
    b.restore(wire);
    r.ok(b.isPlayedCounted(), "the played guard survives serialize/restore");

    // A pre-guard save (no playedCounted field) restores as not-counted.
    const old = JSON.parse(JSON.stringify(a.serialize()));
    delete old.playedCounted;
    const c = CampaignState.create();
    c.restore(old);
    r.ok(!c.isPlayedCounted(), "a pre-guard save defaults to not-counted");

    a.reset();
    r.ok(!a.isPlayedCounted(), "reset() clears the played guard");
  }

  return r.summary();
}
