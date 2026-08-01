# Surface sweep — styleguide §9 inventory vs native app

## Chunk 1 — Deal board + guess rail (19)
| Surface | Status |
|---|---|
| Slim HUD line (suit track, Same charge, Same-Power chip, score, coins) | ✅ HUDBar |
| Stage·Run floating badge | ◐ folded into the HUD stage label + per-screen headers |
| Deal-status row (Reward + live Score) | ✅ RewardLine |
| Left rail: histogram + deck stack + character | ✅ DeckPanel (top band, the web's active thumb layout) |
| Board: pile grid + pillar/base plaques | ✅ |
| Play controls row (guess buttons) | ✅ FAN/▲/＝/▼ rail |
| Bottom histogram band | ✅ as the top deck band (same info, thumb layout) |
| Placement sheet (in-deal Cards/Stickers/Pillars/Bases/Same tabs) | ✗ — items place at buy time instead (store flows); no mid-deal placement window |
| Card/item info popup (hold-help) | ✅ |
| Swipe-guess floating label | ✅ |
| Peek info + peek band | ✅ (help takes over the deck band) |
| Deck quick peek | ◐ hold = help text; tap = full deck inspect modal |
| Deck inspection modal | ✅ DeckInspectViewController |
| Pile fan-out viewer | ✅ |
| 'Shoulda said same' nudge | ✅ |
| Subset-deal reveal | ✅ |
| Traveling-card FX | ✅ |
| Coin/save float chips | ✅ |
| Tutorial bubbles | ✅ (bottom-anchored panel; no per-anchor arrows) |

## Chunk 2 — Map (10)
| Surface | Status |
|---|---|
| Progression map overlay | ✅ |
| Map avatar + travel/collect FX | ✅ |
| Map spotlight layers | ✅ |
| Map key legend | ✅ |
| Map → Store back button | ✅ (shows while standing on a store node) |
| Fossil detail popup | ✗ — fossils not recorded (display-only flourish) |
| Mystery '?' event reveal | ✅ |
| Map overscroll Easter egg | ✅ |
| Map-granted pickers | ✅ |
| Debug node addresses + mystery peek | ◐ long-press jump-to-node; no address tags |

## Chunk 3 — Store (9)
| Surface | Status |
|---|---|
| Store overlay (shelf/loadout/footer) | ✅ |
| Store item-type legend | ✅ |
| Store detail popup (buy/sell focus) | ✅ with compare + Replace question |
| Pack reveal | ✅ |
| Pack item info help slot | ✅ |
| Sticker-apply / card picker (5 modes) | ✅ |
| Item place picker | ✅ (in-detail column chooser) |
| Post-deal placement screen | ◐ pack-keep walk + GO-TO-MAP lock cover the flows; no dedicated 'Spoils' screen |
| Store reroll confirm | ✅ |

## Chunk 4 — Menus etc (17)
| Surface | Status |
|---|---|
| Main menu | ✅ |
| Deck select + seed entry | ✅ |
| Zen select | ✅ |
| Collection screen | ✅ |
| Collection item detail | ✅ (prompt-bar detail) |
| Lifetime stats sheet | ✅ |
| How to Play manual | ✅ (single-page rules; no mock boards) |
| In-game pause menu | ✅ |
| Start/end overlay | ✅ |
| Start screen (campaign intro) | ◐ deck select IS the start gate |
| Deal-cleared payout (coin tally) | ✅ line-by-line + rising pings + score plaque |
| Game-over screen | ✅ (no bouncing fossil field) |
| Victory 'Pinky is home' | ✅ |
| Zen end screen | ✅ |
| Deck-unlock celebration | ✅ |
| Item-unlock pop queue | ✅ (with 4+ summary collapse) |
| Reset-progress double confirm | ✅ |

## Chunks 5/6 — Cross-cutting (11)
| Surface | Status |
|---|---|
| Boot splash | ◐ system launch screen (felt) — no jar art |
| Neural tissue background | ✗ by design — static felt + map dot field (perf-positive) |
| Shared bottom prompt bar | ✅ PromptBar everywhere |
| Static-volatility toast | ✅ as summary lines (⚡ held / blew up) |
| Global nav corner buttons | ✅ |
| Footer build line | ✅ (menu) |
| Debug panel | ◐ launch-args harness instead |
| Autopilot controls | ✅ (launch-arg autopilots incl. full-campaign) |
| Telemetry sheet | ✗ — playtest tool, skipped |
| Shared icon sprite + coin | ✅ pixel-matrix icons |
| Viewport probe | n/a |

Legend: ✅ ported · ◐ design-equivalent/partial · ✗ not ported (noted)
Totals: 66 surfaces — 52 ✅ · 8 ◐ · 5 ✗ (fossils, in-deal placement sheet,
tissue atmosphere, telemetry sheet, jar boot splash) · 1 n/a
