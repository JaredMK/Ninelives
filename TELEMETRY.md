# Telemetry Schema — v7.00

The remote-analytics contract for the TestFlight beta. **Extend this file
first** when adding events — the vocabulary lives here, the code follows.

## Architecture

- **One instrumentation source, two sinks.** The engine's `recT` stream (its
  long-dormant `GameEngine.telemetry` hook, wired in `DealController`) keeps
  feeding the local debug log exactly as before; `TelemetryCore` (GameCore) is
  the remote sink — queue, envelope, batching, opt-out. The app-side bridge
  (`UI/Telemetry.swift`, behind the `TELEMETRY` compilation condition in
  `project.yml`) injects the TelemetryDeck transport and owns sessions,
  lifecycle flushes, milestones, and the settings switch.
- **Batching**: signals queue locally; a batch flushes at 20 queued events,
  on app background, on session start, and at run end. The TelemetryDeck SDK
  adds its own retry queue underneath and drops silently on failure. Sharing
  OFF drops at the door — nothing queues, nothing lingers.
- **Opt-out**: Settings → "SHARE ANONYMOUS GAMEPLAY DATA". Stored at
  UserDefaults `ninelives.pref.telemetryShare` ("1"/"0"); unset means the
  channel default — **ON for TestFlight and DEBUG, OFF for App Store**.
  `RESET PROGRESS` clears prefs, so the switch returns to the channel default.
- **Build flag**: remove `TELEMETRY` from `SWIFT_ACTIVE_COMPILATION_CONDITIONS`
  (app target, `project.yml`) and the whole layer compiles out — no SDK init,
  no transport, and the core's sharing check stays permanently false.

## The envelope (every signal)

| field | value |
|---|---|
| `run_id` | UUID per climb/endless leg; `"none"` in menus and Zen |
| `game_mode` | `climb` / `zen` / `endless` (absent in menus) |
| `deck`, `tier`, `seed` | the run's identity (deck also set for Zen) |
| `deal_number` | v7.00: stamped on every IN-DEAL signal (armed by `deal_start`, cleared at deal/run end) — `item_fired` joins `deal_start`'s loadout on (`run_id`, `deal_number`) with no per-event plumbing. An event carrying its own `deal_number` (e.g. `deal_end`) keeps it |
| `build` | `BuildStamp.version` (e.g. `v6.92`), added at transport |
| user id, app version, platform, `isTestFlight`… | TelemetryDeck's default payload (anonymous, salted-hashed id) |

## Events

### Session & modes
| event | params | fires |
|---|---|---|
| `session_start` | — | app launch + each foreground return |
| `session_end` | `seconds` | app background (paired with the last start) |
| `mode_start` | `picked_mode`, `zen_diff`? | every Zen game / climb start / endless entry |
| `zen_end` | `outcome`: win·loss, `zen_diff`, `seconds` | v7.00: every finished Zen game (a mid-game quit emits nothing — navigational) |
| `tutorial` | `phase`: started·step·completed·abandoned, `step`? | the deal tour's lifecycle |

### Run lifecycle
| event | params | fires |
|---|---|---|
| `run_start` | (envelope) | climb start; endless entry starts its own run |
| `run_end` | `outcome`: win·loss·abandon, `stage_reached`, `score`, `deals_played`, `seconds`, **v7.00:** `pillars`/`bases` (csv by column, `-` = empty), `same_power`, and the full composition summary (`deck_size`, `suits`, `ranks`, `sticker_count`, `curse_count` — `deck_snapshot`'s exact format) | loss screen · Pinky's home (win) · a new climb over a live one (abandon — quitting to menu is navigational, the climb resumes) |
| `deal_start` | v7.00: `stage`, `cards` (dealt), `piles` (starting), `rating` (1–3 stage-relative difficulty), `pillars`/`bases` (csv by column), `same_power` — the deal's SHAPE + the equipped loadout. One per deal number (redeal/resume re-boots dedupe). Replaces v6.92's bare `loadout` | every campaign deal boot |
| `deal_end` | `won`, `deal_number`, `stage`, `node_id`?, `node_type`?, `piles_alive`, `deck_size`, **v7.00:** `cards`, `piles`, `rating` (the shape it started with — "players die on 4-pile 15-card deals") | every campaign deal's fold |
| `milestone_first_store` / `_first_mystery` / `_first_death` | — | once per install |
| `milestone_time_to_first_climb` | `seconds` since install | first climb ever |

### Store
| event | params | fires |
|---|---|---|
| `store_visit` | `shelf` (`kind:id:price\|…`), `purse`, `purge_price`, `reroll_cost` | each shelf roll (`openStore`) |
| `item_offered` | `kind`, `item_id`, `price` | v7.00: one per rolled shelf slot — openStore AND every restock (the Purge slot excluded). The countable "times offered" denominator |
| `item_bought` | `item_id`, `purse` (after) | every purchase (the one funnel, `recordBuy`) |
| `item_skipped` | `item_id`, `kind` | per slot still on the shelf at exit |
| `purge_used` | `price` | each Purge buy |
| `restock_used` | `kind`: paid·free, `cost` | each reroll |
| `redeal_used` | `kind`: paid·free, `cost` | each in-deal reshuffle |
| `store_exit` | `purse` | leaving the store |

### Bases
| event | params | fires |
|---|---|---|
| `base_equipped` | `base_id`, `column` | placement |
| `base_fired` | `base_id` (details ride the paired `item_fired`) | activation |
| `base_expired_uncharged` | `base_id`, `column` | deal end, per charged-but-unfired base — the "they don't know bases exist" signal |

### Build / archetype
| event | params | fires |
|---|---|---|
| `deck_snapshot` | `stage`, `deck_size`, `suits` (`♠N\|…`), `ranks` (`2:N\|…14:N`), `sticker_count`, `curse_count` | run start + each stage rollover |
| `sticker_placement` | the placement log's own record (debug builds; `PLACE\|` NDJSON — not remoted, by design: it carries the full eligible set) | — |
| `conditional_outcome` | `sticker_id`, `outcome`: fired·converted | derived per conditional-sticker recT entry |
| `item_fired` | `item_class`, `item_id`, `fx_*` (the recT impact dict) | every recT entry — pillars, bases, stickers, powers, missed rolls |
| `mystery_choice` | `character`: queen·two, `event` (outcome key = the branch) | each mystery resolution |

**Never logged:** per-guess higher/lower calls, settings changes (beyond the
sharing switch's own effect of going silent), device identifiers, free text.

## The questions the schema answers (v7.00 completeness pass)

- **Deck/tier per run** — the envelope on `run_start` (and everything after).
- **Win rate, overall / per deck / per tier** — `run_end.outcome` split by the
  envelope. Use `run_start` as the denominator: a device wiped mid-climb never
  emits its `run_end`, so start-vs-end also measures that leak.
- **Where runs end** — `run_end.stage_reached` + `deals_played`, and the fatal
  deal's own `deal_end` (`won=0`) now carries `cards`/`piles`/`rating`.
- **Score distribution per deck/tier** — `run_end.score` × envelope.
- **Per item** — offered: `item_offered`; bought: `item_bought`; skipped:
  `item_skipped`; deals equipped: count `deal_start`s whose csv contains the
  id; fired: `item_fired` (joins on `run_id` + `deal_number`); conditional
  fired-vs-converted: `conditional_outcome`.
- **Run timeline from run_id** — every in-run signal carries the envelope;
  order by TelemetryDeck's `receivedAt` + `deal_number`.
- **Zen** — played: `mode_start` (`picked_mode=zen`, `zen_diff`);
  won/lost + duration: `zen_end`.

## Dashboard setup (TelemetryDeck)

App ID `8FC986B9-0F2C-44AA-8ED2-F95676B952FE` is wired in `UI/Telemetry.swift`.
The **TestFlight Beta** dashboard is BUILT and live (org `com.jarheadlabs` →
shoulda said same → Dashboards); its versioned spec lives at
[`telemetry-dashboard.json`](telemetry-dashboard.json) — re-import any time via
Dashboards → Import Dashboard. Nine insights, all validated against test-mode
signals in the SDK's own wire format:

1. Mode adoption — `mode_start` by `picked_mode` (Top N donut)
2. Mode adoption — `mode_start` by `deck` (Top N donut)
3. Session funnel — `session_start → mode_start → run_start → deal_end →
   run_end` (Funnel; the last step's condition is wrapped in a one-element
   `or` — semantically identical)
4. Run outcomes — `run_end` by `outcome` (Top N donut)
5. Stage reached — `run_end` by `stage_reached` (Top N bar chart)
6. Conditional stickers — `conditional_outcome` by `sticker_id` + `outcome`
   (Advanced TQL `groupBy`, two dimensions — the conversion-rate table)
7. Base discovery — `base_fired` vs `base_expired_uncharged` (Advanced TQL
   `groupBy` on `type` with an `in` filter)
8. Restocks & redeals — by `kind` paid/free (Advanced TQL `groupBy` on
   `type` + `kind`, `in` filter over `restock_used`/`redeal_used`)
9. Tutorial funnel — `phase=started → phase=step → phase=completed` (Funnel;
   `phase` only rides `tutorial` signals, so no type clause needed)

Retention and session length need no insight: they're built into the app's
**Customers** tab (Acquisition / Activation / Retention — hourly/daily/weekly/
monthly returning users) fed by the SDK's default payload (SwiftSDK ≥ 2.8.0;
we ship 2.14.2). Toggle the **Test Mode** chip to switch between beta test
signals and production data. Note: TelemetryDeck's free tier queues data
processing — signals can take a while to appear ("Queued for Data
Processing" banner); paid plans process in real time.

## App Store Connect privacy questionnaire

Declare: **Data is collected** → **Product Interaction** (gameplay events) —
**used for Analytics**, **not linked to the user's identity**, **not used for
tracking**. Nothing else: no identifiers, no location, no diagnostics
category needed (we send no crash data), no tracking (answer "No" to the ATT
question). `App/PrivacyInfo.xcprivacy` matches this exactly, and the SDK
bundles its own manifest for its salted user identifier.
