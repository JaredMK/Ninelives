# Tests

Unit tests for the DOM-free engine modules in `index.html`
(`DeckManager`, `BoardState`, `GameEngine`, `CampaignState`, `DeckStats`).

```sh
node tests/all.mjs
```

`_harness.mjs` extracts the `<script>` from `index.html` and evaluates it with
a minimal stubbed `document`, then returns the module objects — so the engine
can be tested without a browser. Each `*.test.mjs` exports `run()` returning
`{ pass, fail, fails }`; register new suites in `all.mjs`.
