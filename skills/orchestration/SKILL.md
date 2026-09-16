---
name: orchestration
description: Routing doctrine for the architect-as-orchestrator pattern — how a session running the smartest model delegates implementation to cheaper lanes to minimize cost. USE WHEN delegating implementation work, choosing between the luna-lane/grok-lane skills, opus-heavy-implementer and opus-implementer, applying the 50/50 luna/grok split or the EXTERNAL-ONLY usage mode, sending a diff to opus-reviewer, handing a whole objective to astra-lead, routing investigation to grok-research, writing a spec for a subagent, deciding whether to consult codex-peer or advisor, managing session cost or token spend, or running any multi-task build where the session is the architect.
---

# Orchestration — the architect's routing doctrine

The session is the architect: it owns requirements, architecture, decomposition, specs, routing, and verification. It should almost never type implementation code. Every implementation task gets routed to the cheapest lane that is adequate for it — escalation is deliberate, per task, never a fixed binding.

## Cost discipline — the prime directive

The session model is the most expensive lane in the system, on both input and output tokens. The whole economic case for this pattern is keeping its token volume low: spend Fable on judgment, spend the implementation lanes on volume. Three rules follow.

**Emit judgment, not volume.** The architect's output is decomposition, specs, routing decisions, verdicts on diffs, and short reports. It does not type implementation code, test bodies, boilerplate, or config files. A code block longer than an interface signature or a few illustrative lines is a spec that hasn't been delegated yet — stop and delegate it. Fixing a lane's bug by hand is the same failure in disguise: send a corrected spec back to the lane instead.

**Keep the context lean.** Everything in the architect's context is re-read at architect prices on every turn. Delegate broad exploration, codebase searches, and log-grepping to a cheap read-only agent (Explore) or to `grok-research`, and keep only the conclusions; read files yourself only when the decision genuinely depends on the exact code. Don't paste long files, full diffs, or verbose command output into the conversation when a path reference or an excerpt will do.

**Reason once, then hand off.** Do the hard thinking — the architecture, the interface design, the debugging hypothesis — in one pass, capture it in the spec, and let the lane carry it from there. Re-deriving decisions across turns burns the premium twice.

What stays with the architect regardless of cost: decomposition, interface design, hypothesis selection when debugging, spec writing, lane routing, and judging verification evidence. Those tokens are what the premium is for — everything else is a candidate for delegation.

The simplest working solution is also the cheapest to verify — simplicity is cost discipline, not just style.

## The lanes

| Lane | Producer | Invoke | Route here when |
|---|---|---|---|
| Day-to-day (luna) | GPT-5.6 Luna (max effort) | `luna-lane` skill — the architect launches `codex exec` directly; no Claude subagent | Half of all day-to-day and cheap work: tests, lint, extraction, summaries, ordinary features. Slow (~100 steps) but cheap. Requires the codex CLI, logged in. |
| Day-to-day (grok) | Grok 4.6 (medium effort) | `grok-lane` skill — the architect launches the grok CLI directly; no Claude subagent | The other half. Preferred when wall-clock matters. Requires the grok CLI and a Bash permission rule for its path. |
| Heavy code | Claude Opus 5 (high effort) | `opus-heavy-implementer` agent | Complex algorithms, concurrency, data migrations, security-sensitive code, changes spanning many files. Outside the luna/grok tally. |
| Fallback implementer | Claude Opus 5 (medium effort) | `opus-implementer` agent | Only when luna or grok reports unavailable/rate-limited/timeout, or on explicit request. |
| Reviewer | Claude Opus 5 (medium effort) | `opus-reviewer` agent | Every luna/grok diff, before the architect accepts it. Read-only; re-runs the spec's verification. |
| Lead for a whole objective | GPT-6 Astra (high effort) | `astra-lead` skill — the architect launches `codex exec` directly | The objective is self-contained in one repo with a command that proves it done, the user asks for it, or mode is EXTERNAL-ONLY. Astra decomposes and implements it end to end. |
| Research | Grok 4.6 (medium effort) | `grok-research` skill (read-only, plan mode) | Investigating a question across a codebase, docs or the web. Falls back to the `opus-researcher` agent. |
| Peer + cross-vendor review | GPT-6 Astra (high effort) | `codex-peer` agent | NOT an implementer. A second opinion on a hard problem, a design trade-off, a diagnosis; the review of an `opus-implementer`/`opus-heavy-implementer` diff; the final review of a Fable-led deliverable. Requires the codex CLI. |
| Judgment | Fable 5.1 (high effort) | `advisor` agent | Not an implementation lane. Commitment boundaries (below) and the final review of Astra-led work. |

`sonnet-implementer` is **not routed** by this doctrine. It stays in the plugin for manual use.

## Routing policy

- **Day-to-day work** — simple to reasonably complex, plus all cheap work — → `luna-lane` / `grok-lane`, alternating toward **50/50**. Prefer grok when speed matters, luna for cheap volume work; the tally settles the ties.
- **Tally.** Keep a running count `lanes: luna N / grok M` and state it whenever you route. When it drifts more than one task from 50/50, send the next task to the under-used lane.
- **Heavy code** → `opus-heavy-implementer`: complex algorithms, concurrency, data migrations, security-sensitive code, many-file changes. Outside the tally; its diff goes to `codex-peer` for cross-vendor review.
- **A whole objective** → `astra-lead`, when it is self-contained in one repo with a command that proves it done, when the user asks, or in EXTERNAL-ONLY mode. Otherwise the architect stays the lead and delegates tasks.
- **Research** → `grok-research` (read-only), falling back to `opus-researcher`.
- **Fallback outside EXTERNAL-ONLY mode.** A lane returning `unavailable`, `rate-limited` or `timeout` is marked unavailable for the rest of the session — announce it once (e.g. `grok unavailable (402): its share goes to luna`) and do not relaunch it per task. Its share moves to the other external lane and the 50/50 tally is paused while one lane is down. `opus-implementer` (its diff reviewed by `codex-peer`, not `opus-reviewer`) is used only when both external lanes are unavailable, or when the user explicitly accepts a Claude lane for a time-critical spec because only the slow lane is left. Detection: non-zero exit, or output matching (case-insensitive) `usage limit|rate limit|quota|429|402|Payment Required|balance exhausted|unauthorized|not logged in|login`.
- **EXTERNAL-ONLY mode.** Every user prompt carries a usage note injected by the plugin hook (`maestro usage: … mode: …`). When it reads `mode: EXTERNAL-ONLY` (the Claude 5-hour window is at or above 75%), all implementation runs through the luna, grok and astra lanes, launched by the architect itself; no Claude implementation subagent is spawned. A PreToolUse gate denies `opus-implementer`, `opus-heavy-implementer`, `opus-reviewer`, `opus-researcher` and `sonnet-implementer` directly, so reviews go to `codex-peer` instead. `advisor`, `codex-peer` and the read-only Explore agent remain available — that's the point of the mode, to preserve Claude quota for judgment while the external lanes carry the typing. If both grok and codex are unavailable in EXTERNAL-ONLY mode, stop and tell the user; do not fall back to a Claude lane. When the note returns to `mode: split`, resume the policy above.

When the *decision itself* is uncertain — not the typing — consult `codex-peer` for an independent non-Anthropic perspective before committing.

If the codex CLI is unavailable, `codex-peer` reports a structured error — say so explicitly and never silently substitute your own opinion for the peer's.

## Review

Every luna/grok diff goes to `opus-reviewer` before the architect accepts it. It receives the spec and the diff scope, reads `git diff`, **re-runs the spec's verification command**, checks the ponytail rules, and returns `REVIEW: ship | fix` with findings as `file:line`. The reviewer's quoted verification output is the evidence — the architect spot-checks it against the tree, it does not redo the work. `fix` means a corrected spec goes back to the same lane, never a hand patch.

Diffs from `opus-implementer` and `opus-heavy-implementer` go to `codex-peer` in review mode instead: cross-vendor, so the reviewer is never the implementer's own model.

## Final review

Once, before declaring a multi-step deliverable done:

- **Fable-led** (the session decomposed and routed it) → `codex-peer` final review of the diff.
- **Astra-led** (`astra-lead`) → `advisor` final review of the diff.

Never both, never neither. The rule is simply that the final reviewer is never the same model that led the work.

## The spec contract

Implementers share none of your conversation context. Every delegation prompt carries all five parts:

1. **Objective** — what to build or change, one paragraph
2. **Files** — exact paths to create or modify
3. **Interfaces** — signatures, types, or API shapes the code must match
4. **Constraints** — project conventions, things not to touch

Every spec's Constraints section ends with the ponytail block from `doctrine/ponytail-block.md` (`${CLAUDE_PLUGIN_ROOT}/doctrine/ponytail-block.md`) and the karpathy guidelines block from `doctrine/karpathy-block.md` (`${CLAUDE_PLUGIN_ROOT}/doctrine/karpathy-block.md`), pasted verbatim — the lanes do not load skills, so both doctrines travel inside the spec.

5. **Verification** — the command(s) that prove it works

A spec you can't finish writing is a signal the decision isn't made yet — that's architect work, not a reason to hand the ambiguity to a cheaper model.

## Parallelism

Independent specs (no shared files, no ordering dependency) launch in parallel in a single message. This includes launching the luna lane and the grok lane side by side when the two tasks don't touch the same files — each spec still counts once toward the 50/50 tally regardless of how it was launched. Sequential chains and single-file surgery stay serial. For high-stakes work, pair the heavy lane's diff with a `codex-peer` review of the approach — cross-vendor scrutiny for one extra consult's cost.

## Commitment boundaries

Consult `advisor` (read-only, verdict in under 300 words) at the moments that decide whether the next hour is wasted:

- Before committing to an architecture, data migration, API shape, or refactor strategy
- Whenever the same problem has resisted two distinct attempts
- As the final review of an Astra-led objective, before accepting it (see "Final review")

Pass it the decision, the constraints, and the options considered. Act on the verdict or surface the disagreement — never silently ignore it. (If the session itself already runs on Fable, the advisor still earns its keep as a context-clean skeptic reading the actual code.)

## Visibility

Before every lane launch — an `Agent` call or a CLI command — tell the user in one sentence which lane is being used, its model and effort, and why. The user validates routing as it happens; the tally line covers the split, this line covers the reason.

## Verification

Reports are claims, not evidence. The reviewer's quoted verification output is the evidence: read the diff, send it to the reviewer the lane's rules name, and spot-check the output it quotes against the working tree — you no longer re-run everything yourself. "Should work", "tests should pass", or a review with no command output means the task is not done. A lane that reports a spec gap gets a corrected spec, not a "use your judgment".
