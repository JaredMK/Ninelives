# The GOLDEN BASELINE

These JSON files are the committed regression record of what **GameCore
itself** produces — captured by `Tests/GoldenRecorder.swift` running the real
engine, and replayed on every `make test` by `SeedFixtureTests`,
`EngineTraceTests` and `CampaignFixtureTests`. **The iOS engine is the source
of truth.** (Before v6.79 these were captured from the web engine in
`../index.html`; that engine is frozen and never consulted again.)

| File | Covers |
| --- | --- |
| `seed-fixtures.json` | mulberry32 streams, SeedCode encode/decode/rejects, standard + zen shuffles, `Economy.dealFlat`/`breakdown` tables, difficulty bands/scores/subset-piles, a 96-map + 72-stage generator seed corpus, the data-registry echo |
| `engine-traces.json` | 137 scripted deals replayed step-for-step: every draw, guess result, pile size, coin tally, sticker/pillar/base/same-power fire, prompt drain, save-priority resolution, final payout |
| `campaign-fixtures.json` | fresh-start state for every deck × tier × seed (run seed, deck ids, start cards, loadouts, joker budget), store-roll and store-card seed corpora, mystery run-seed derivation, pack reveals, the save blob's EXACT key set + restore round-trips, the pile→column layout table |

## Regenerating

Only after an **intentional** engine change, in the same commit that makes it:

```sh
cd ios
make golden    # re-records Fixtures/*.json from GameCore
make test      # must be green against the new baseline
```

Review the `Fixtures/` diff before committing — every changed value is a
behavior change you are declaring deliberate. A normal test run can never
overwrite these files (the recorder skips without the `.golden-record` flag
`make golden` creates).

## Growing the corpus

- `engine-traces.json`: add an inputs-only scenario object (name, seed,
  piles, steps, cols/pillars/bases/samePower/stickers…) and run `make golden`
  — the recorder fills in the trace.
- `seed-fixtures.json`: add an inputs-only entry to any section the same way.
- `campaign-fixtures.json`: extend the seed/deck/tier matrices in
  `GoldenRecorder.recordCampaignFixtures`.

New gameplay behavior should get a hand-written Swift XCTest FIRST (rules,
boundaries, invariants); the golden layer is the regression net underneath,
not a substitute for a real test.
