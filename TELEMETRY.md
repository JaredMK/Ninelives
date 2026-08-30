# Telemetry Schema — v6.92

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
| `build` | `BuildStamp.version` (e.g. `v6.92`), added at transport |
| user id, app version, platform, `isTestFlight`… | TelemetryDeck's default payload (anonymous, salted-hashed id) |

## Events

### Session & modes
| event | params | fires |
|---|---|---|
| `session_start` | — | app launch + each foreground return |
| `session_end` | `seconds` | app background (paired with the last start) |
| `mode_start` | `picked_mode`, `zen_diff`? | every Zen game / climb start / endless entry |
| `tutorial` | `phase`: started·step·completed·abandoned, `step`? | the deal tour's lifecycle |

### Run lifecycle
| event | params | fires |
|---|---|---|
| `run_start` | (envelope) | climb start; endless entry starts its own run |
| `run_end` | `outcome`: win·loss·abandon, `stage_reached`, `score`, `deals_played`, `seconds` | loss screen · Pinky's home (win) · a new climb over a live one (abandon — quitting to menu is navigational, the climb resumes) |
| `deal_end` | `won`, `deal_number`, `stage`, `node_id`?, `node_type`?, `piles_alive`, `deck_size` | every campaign deal's fold |
| `milestone_first_store` / `_first_mystery` / `_first_death` | — | once per install |
| `milestone_time_to_first_climb` | `seconds` since install | first climb ever |

### Store
| event | params | fires |
|---|---|---|
| `store_visit` | `shelf` (`kind:id:price\|…`), `purse`, `purge_price`, `reroll_cost` | each shelf roll (`openStore`) |
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
| `loadout` | `pillars`, `bases`, `same_power` (csv ids) | each campaign deal start |
| `sticker_placement` | the placement log's own record (debug builds; `PLACE\|` NDJSON — not remoted, by design: it carries the full eligible set) | — |
| `conditional_outcome` | `sticker_id`, `outcome`: fired·converted | derived per conditional-sticker recT entry |
| `item_fired` | `item_class`, `item_id`, `fx_*` (the recT impact dict) | every recT entry — pillars, bases, stickers, powers, missed rolls |
| `mystery_choice` | `character`: queen·two, `event` (outcome key = the branch) | each mystery resolution |

**Never logged:** per-guess higher/lower calls, settings changes (beyond the
sharing switch's own effect of going silent), device identifiers, free text.

## Dashboard setup (TelemetryDeck)

App ID `8FC986B9-0F2C-44AA-8ED2-F95676B952FE` is wired in `UI/Telemetry.swift`.
Suggested insights: `mode_start` grouped by `picked_mode` and `deck` (what do
testers actually play) · funnel `session_start → mode_start → run_start →
deal_end → run_end` · `run_end.outcome` split + `stage_reached` histogram ·
`conditional_outcome.outcome` grouped by `sticker_id` (the conversion rates) ·
`base_expired_uncharged` count vs `base_fired` (base discovery) ·
`restock_used`/`redeal_used` existence (do they find them) · `tutorial.phase`
funnel · retention comes free from `session_start`.

## App Store Connect privacy questionnaire

Declare: **Data is collected** → **Product Interaction** (gameplay events) —
**used for Analytics**, **not linked to the user's identity**, **not used for
tracking**. Nothing else: no identifiers, no location, no diagnostics
category needed (we send no crash data), no tracking (answer "No" to the ATT
question). `App/PrivacyInfo.xcprivacy` matches this exactly, and the SDK
bundles its own manifest for its salted user identifier.
