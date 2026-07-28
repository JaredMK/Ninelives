---
name: agent-pipeline
description: Development workflow for Shoulda Said Same — three tiers. TRIVIAL and STANDARD work is done directly by the main agent (no subagents); only MAJOR work (multi-system reworks, save/serialization, map-generation validation) uses two agents (implementer + one reviewer). Invoke to classify a task and follow the matching flow.
---

# agent-pipeline — the development workflow

Single-file browser game; most changes are small and the test suite is fast.
Default to doing the work directly. Subagents are reserved for MAJOR work
only. On invocation: classify the tier (say which and why), then follow that
tier's flow. When in doubt between two tiers, pick the lower one — the
conventions checklist and full test suite are the real safety net, not
agent count.

## Tier rule

- **TRIVIAL — no agents, no pipeline.** Copy/text edits, value tweaks in
  `items.js` / `difficulty.js`, one-line fixes, small CSS, comment/doc or
  test-only changes. Do it directly, run the test suite, commit (normal
  ship ritual: APP_VERSION bump if player-visible, push, deploy-verify).
- **STANDARD — direct implementation + one self-review pass. No subagents.**
  Most features, bug fixes, and UI work: new UI affordances, sticker/pillar
  effects, store/screen changes, layout reworks, perf fixes. Implement it
  yourself, then do ONE explicit self-review pass against the conventions
  checklist below (data files as source of truth, perf invariants, UX
  conventions, storage/safety) — read your own diff as a reviewer would and
  fix what you find. Run the FULL test suite, commit, ship.
- **MAJOR — at most TWO agents: implementer + one reviewer.** Only for:
  multi-system reworks (several screens/systems changing together), anything
  touching the save/priority chain or run-state serialization
  (serialize/restore, SaveStore, the persist/coalesce paths), and map
  generation validation. Flow:
  1. Spawn `pipeline-meta` with `isolation: "worktree"` and a self-contained
     spec (outcome, requirements, acceptance checks — write it yourself; no
     separate spec agent). It implements, tests in its worktree, and writes
     the diff to `/tmp/agent-pipeline/<slug>.patch`.
  2. Spawn `pipeline-reviewer` with the spec + patch path for a SINGLE
     combined pass: correctness AND the full conventions checklist below
     (including the security and UX items — there are no separate
     security/UX/implementation agents; their checks are folded into this
     one review). On `REVISE`, SendMessage the SAME meta agent, then
     re-review; cap at 2 rounds, then surface the disagreement to the user.
  3. On approval the MAIN agent applies the patch, runs the full suite,
     commits, and ships. Subagents never commit or push.

Ask the user clarifying questions (with recommended defaults) directly in
chat before starting when the request is genuinely ambiguous — for any tier.
No dedicated spec-refinement agent.

## Conventions checklist (the STANDARD self-review pass and the MAJOR review both use this)

- **Data files**: `items.js` / `difficulty.js` are the ONLY home for
  item/difficulty tunables; both validate fail-loud on load. Never hardcode
  a tunable in index.html; tests read registry values live, never pin them.
- **Tests**: `node tests/all.mjs` must be 100% green (run per-suite if the
  full runner is flaky under host load); new logic gets tests in the
  existing registry-driven style (`tests/_harness.mjs` extracts the DOM-free
  engine modules from index.html).
- **Perf**: no per-frame layout reads (no `getBoundingClientRect` in
  rAF/scroll loops — see the svh probe + `--shell-h` measured-once
  patterns); one animation clock (reuse `queueAnim`/`flyCard`/`cardBreathe`,
  never add free-running per-element timers); no accumulating state across
  deals or store visits (listeners delegated; per-run objects rebuilt;
  nothing unbounded grows per action).
- **UX**: phone-first (390px); one-screen store; hold-for-help everywhere
  (`attachCardHoldHelp` / peek-info); ALL confirmations/choices ride the
  bottom prompt bar (`showActionBar` — never a screen-blocking modal); card
  motion uses the shared `flyCard` travel; sounds via the WebAudio `Sound.*`
  registry; safe-areas via the `body.native-app` block.
- **Storage/safety**: saves are `ninelives.*` localStorage keys through the
  existing SaveStore/write-through paths; serialize/restore round-trip is a
  hard invariant (nothing may corrupt a saved run); all user-adjacent
  strings pass `escHtml`; no `eval`/`new Function` on data; never bypass the
  items.js / difficulty.js validators.

## Agent defs

`.claude/agents/pipeline-meta.md` (implementer, worktree) and
`.claude/agents/pipeline-reviewer.md` (single combined review) are the only
two agents this flow uses. The other pipeline-* defs (spec, implementer,
security, ux) are retired from this workflow — do not spawn them.
