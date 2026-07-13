---
name: agent-pipeline
description: Multi-agent development pipeline for Shoulda Said Same — delegate nontrivial coding work to a Meta (planner/coder) subagent, an independent Reviewer loop, then parallel Implementation/Security/UX checks, so the main chat agent stays free for conversation and planning. Invoke for features, reworks, or anything touching game logic; trivial edits skip it (see the tier rule inside).
---

# agent-pipeline — the multi-agent development workflow

The main chat agent ORCHESTRATES; subagents do the heavy work. On invocation,
run step 0 (spec refinement) unless the task is obviously tier 1, classify
the tier, then run the matching flow. The main agent never writes feature
code itself in tier 2/3 — it routes specs, verdicts, and patches between
agents and reports the consolidated result.

Naming note: "Meta" is the ROLE name of the orchestrated planner/coder
subagent (a Claude subagent inside this session) — it has nothing to do with
Meta the company; no external services or API keys are involved anywhere in
this pipeline.

## Step 0 — SPEC REFINEMENT (`pipeline-spec`, before tier 2/3 work)

Spawn `pipeline-spec` with the user's RAW prompt. It investigates the code,
then returns a DRAFT SPEC + a tier recommendation + up to 4 clarifying
questions, each with a recommended default.

- **Relay the questions to the user** (AskUserQuestion or plain chat, with
  the recommended defaults marked). Subagents cannot address the user
  directly — the main agent is the relay; that is the real-mechanics
  equivalent of "an agent asks the user questions".
- Send the answers (or "use defaults" if the user says so / is clearly
  delegating) back to the SAME spec agent via SendMessage; it returns the
  FINAL SPEC + tier. That spec — self-contained, outcome-first, with
  acceptance checks — is what the Meta agent receives verbatim.
- If the spec agent returns `QUESTIONS: none`, skip the relay and proceed.
- Obvious tier-1 tasks skip step 0 entirely (a copy edit needs no
  interrogation); when in doubt, run it — a wrong build costs more than a
  spec round.

## Tier rule (classified from the FINAL SPEC; say which tier and why)

- **Tier 1 — TRIVIAL: no pipeline.** Copy edits, one-line fixes, item/value
  tweaks confined to `items.js` / `difficulty.js`, comment/doc changes,
  test-only edits. The main agent just does it (plus the normal ship ritual).
- **Tier 2 — MEDIUM: Meta + Reviewer only.** Small self-contained changes
  with real logic but narrow blast radius: a new debug tool, a single UI
  affordance, one sticker/pillar effect, a CSS/layout rework of one
  component. After Reviewer approval the MAIN agent applies the patch, runs
  the suite, and ships (no parallel check fan-out).
- **Tier 3 — FULL PIPELINE.** Features, mechanics reworks, anything touching
  the engine (`GameEngine`/`CampaignState`/`RunMap`), save format, map
  generation, the store flow, or multiple screens. Meta → Reviewer loop →
  parallel Implementation + Security + UX → consolidated report.

## The agents (defined in `.claude/agents/pipeline-*.md`)

| Role | Agent type | Works in |
|---|---|---|
| Spec refiner (step 0) | `pipeline-spec` | read-only; questions relayed via the main agent |
| Meta / orchestrated coder | `pipeline-meta` | **isolated git worktree** (`isolation: "worktree"`) |
| Reviewer | `pipeline-reviewer` | read-only, reviews the patch file |
| Implementation | `pipeline-implementer` | the REAL working tree |
| Security | `pipeline-security` | read-only, audits the patch |
| UX/UI | `pipeline-ux` | read-only, audits the patch |

## Flow (tier 3; tier 2 stops after step 2; step 0 precedes both)

0. **SPEC.** As above — `pipeline-spec` refines the raw prompt into the
   FINAL SPEC through a question round relayed by the main agent.
1. **META.** Spawn `pipeline-meta` with `isolation: "worktree"` and the FINAL
   spec. Its contract: plan, implement in its worktree, run
   `node tests/all.mjs` there, then **write the complete unified diff to the
   patch file** (path below) and return a summary (what/why/how tested).
   The live codebase is never touched in this step.
   - Patch file convention: `/tmp/agent-pipeline/<slug>.patch` (`git diff`
     from the worktree; the worktree is isolated but /tmp is shared).
2. **REVIEWER LOOP.** Spawn `pipeline-reviewer` with the spec + patch path.
   It returns either `APPROVED` (with a short rationale) or `REVISE:` with
   concrete numbered findings. On `REVISE`, use **SendMessage to the SAME
   Meta agent** (it keeps its worktree + context) with the findings; Meta
   updates the patch; re-review with a fresh SendMessage to the SAME
   Reviewer. Cap the loop at 3 rounds — if still unapproved, surface the
   disagreement to the user instead of grinding.
3. **PARALLEL CHECKS** (single message, three Agent calls at once):
   - `pipeline-implementer`: apply the approved patch to the real tree
     (`git apply`), run the FULL suite, boot the game headlessly (Playwright
     at `/opt/node22/lib/node_modules/playwright/index.js`, viewport
     390×844) and exercise the feature; report pass/fail with evidence.
   - `pipeline-security`: audit the patch only (checklist in its agent def).
   - `pipeline-ux`: audit the patch against the UX conventions (its def).
   Security/UX read the patch file, so they can run while the implementer
   mutates the tree — no conflict.
4. **CONSOLIDATE.** All three pass → the main agent runs the standard ship
   ritual (APP_VERSION bump, commit, push, deploy-verify) and reports each
   agent's summary (built / review findings / security notes / UX notes).
   ANY failure → SendMessage the findings back to the SAME Meta agent, and
   re-run from step 2 (a changed patch must be re-reviewed).

## Project invariants (every agent def repeats its own slice; this is the master list)

- `items.js` / `difficulty.js` are the ONLY home for item/difficulty
  tunables; both validate fail-loud on load. Never hardcode a tunable in
  index.html; tests read registry values live, never pin them.
- Tests: `node tests/all.mjs` must be 100% green; new logic gets tests in
  the existing registry-driven style (`tests/_harness.mjs` extracts the
  DOM-free engine modules from index.html).
- Perf rules: no per-frame layout reads (no `getBoundingClientRect` in
  rAF/scroll loops — see the svh probe + `--shell-h` measured-once
  patterns); one animation clock (reuse `queueAnim`/`flyCard`/`cardBreathe`
  conventions, never add free-running per-element timers); no accumulating
  state across deals (listeners are delegated; per-run objects rebuilt).
- UX conventions: phone-first (390px); one-screen store; hold-for-help
  everywhere (`attachCardHoldHelp` / peek-info); ALL confirmations/choices
  ride the bottom prompt bar (`showActionBar` — never a screen-blocking
  modal); card motion uses the shared `flyCard` travel; sounds via the
  WebAudio `Sound.*` registry; safe-areas via the `body.native-app` block.
- Storage/safety: saves are `ninelives.*` localStorage keys through the
  existing SaveStore/write-through paths; all user-adjacent strings pass
  `escHtml`; no `eval`/`new Function` on data; never bypass the items.js /
  difficulty.js validators; nothing may corrupt a serialized run
  (serialize/restore round-trip is a hard invariant).

## Deviations from the requested design (real subagent mechanics)

- **The spec agent cannot question the user directly** — subagents have no
  user channel. The main agent relays its questions (with recommended
  defaults) and returns the answers via SendMessage to the same agent. Same
  outcome, one hop longer.
- **"Scratch state"** is a real git worktree via the Agent tool's
  `isolation: "worktree"`. Worktrees are per-agent and vanish after the run,
  so the patch is handed over via the shared `/tmp/agent-pipeline/*.patch`
  file, not via git refs.
- **The revision loop** uses `SendMessage` to continue the SAME Meta/Reviewer
  agents (context and worktree intact) rather than agents messaging each
  other directly — subagents cannot talk peer-to-peer; the main agent is the
  bus. This is the closest real equivalent and is capped at 3 rounds.
- **"Implementation agent applies to the real codebase"** is real, but the
  final commit/push/deploy stays with the MAIN agent (subagents should not
  push), matching the repo's ship ritual.
- Skills do not auto-apply: the user invokes `/agent-pipeline <spec>`, or the
  main agent invokes the Skill tool when a request clearly matches tier 2/3.
