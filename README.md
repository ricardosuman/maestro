# maestro

Maestro started as an adaptation of [DannyMac180/fable-advisor](https://github.com/DannyMac180/fable-advisor) (MIT) and has since been rewritten around its own doctrine.

## What it is

Maestro turns a Claude Code session into an architect-orchestrator: the session decomposes the problem, writes specs, routes the actual typing to other models, and judges the verification evidence — it almost never writes the code itself. Implementation goes to cheaper or external lanes (GPT-5.6 Luna and Grok 4.6 by default, Claude Opus or Sonnet as fallback), each launched from a spec with its own reviewer checking the diff before the architect accepts it. The point is cost: keep the expensive model (Fable 5.1) for judgment — decomposition, interface design, routing, and reading reviews — and spend cheaper or external tokens on volume.

## Lanes band

The optional `maestro-lanes` mod polls `/tmp/maestro-lanes/` and shows each Luna, Grok, Astra, or research run above the prompt with its task suffix, state, elapsed time, and latest output line. Load it with `claude --plugin-dir mods/lanes`, or install `maestro-lanes` from this marketplace. Function hooks are early access.
Function hooks load only with `CLAUDE_CODE_ENABLE_FUNCTION_HOOKS=1` in the environment (e.g. `CLAUDE_CODE_ENABLE_FUNCTION_HOOKS=1 claude --plugin-dir mods/lanes`).

## Who this is for

This is tuned to my own setup and subscriptions: a Claude subscription used from Claude Code (the session runs Fable 5.1; Opus/Sonnet lanes), an OpenAI subscription used through the Codex CLI (GPT-5.6 Luna and GPT-6 Astra lanes), and an xAI Grok subscription used through the Grok Build CLI (Grok 4.6 lanes). If you don't have one of these, the corresponding lanes report `unavailable` and the doctrine falls back as documented below. Nothing here is a benchmark or a recommendation; it is the routing that keeps my weekly Claude limit alive.

## How work is routed

| Lane | Runs | Claude subagent? | Used when |
|---|---|---|---|
| `maestro:luna-lane` skill | GPT-5.6 Luna, effort `max`, via `codex exec` | No — architect launches `codex` directly from Bash | Half of day-to-day/cheap work; slow (~100 steps) but cheap |
| `maestro:grok-lane` skill | Grok 4.6, effort `medium`, via the Grok CLI | No — architect launches `grok` directly from Bash | The other half of day-to-day work; preferred when wall-clock matters |
| `maestro:astra-lead` skill | GPT-6 Astra, effort `high`, via `codex exec` | No — architect launches `codex` directly from Bash | A whole self-contained objective with a command that proves it done, on request, or in EXTERNAL-ONLY mode; followed by mandatory `advisor` final review |
| `maestro:grok-research` skill | Grok 4.6, effort `medium`, plan mode (read-only) | No | Investigating a question across code/docs/web; falls back to `opus-researcher` |
| `maestro:opus-heavy-implementer` agent | Claude Opus 5, effort `high` | Yes | Complex algorithms, concurrency, migrations, security-sensitive code, many-file changes. Outside the tally; diff reviewed by `codex-peer` |
| `maestro:opus-implementer` agent | Claude Opus 5, effort `medium` | Yes | Fallback when luna/grok is unavailable, or on explicit request; diff reviewed by `codex-peer` |
| `maestro:opus-reviewer` agent | Claude Opus 5, effort `medium` | Yes | Reviews every luna/grok diff: reads `git diff`, re-runs the spec's verification, returns ship/fix |
| `maestro:opus-researcher` agent | Claude Opus 5, effort `medium` | Yes | Research fallback when `grok-research` is unavailable; read-only |
| `maestro:codex-peer` agent | GPT-6 Astra, high reasoning, via `codex exec` (wrapper model: haiku) | Yes (thin forwarder) | Cross-vendor discussion/second opinion; reviews `opus-implementer`/`opus-heavy-implementer` diffs and Fable-led final deliverables |
| `maestro:advisor` agent | Fable 5.1, effort `high` | Yes | Commitment-boundary decisions; mandatory final review of Astra-led work |
| `maestro:sonnet-implementer` agent | Claude Sonnet 5, effort `medium` | Yes | Not routed by the doctrine — kept for manual use only |

Day-to-day implementation (simple to reasonably complex, plus all cheap work) splits **50/50 between the luna and grok lanes**; the architect keeps a running `lanes: luna N / grok M` tally and corrects toward 50/50 as it drifts, preferring grok when wall-clock matters and luna for cheap volume work. Heavy code goes to `opus-heavy-implementer`, outside that tally. Every luna/grok diff goes to `opus-reviewer` before it's accepted — it re-runs the spec's verification command and returns ship/fix; diffs from the opus lanes go to `codex-peer` instead, so the reviewer is never the implementer's own vendor. Once the Claude 5-hour usage window hits 75%, mode flips to **EXTERNAL-ONLY**: all implementation runs through luna, grok and astra, and a PreToolUse gate denies the opus/sonnet lanes outright. When a lane reports unavailable, rate-limited or timed out, its share moves to the other external lane (the 50/50 tally pauses); `opus-implementer` is used only when both external lanes are down, or the user explicitly accepts a Claude lane for a time-critical spec. The architect itself keeps only decomposition, interface design, spec writing, routing, and judging verification evidence — never the typing.

## The usage gate

A statusline script (`scripts/usage-statusline.sh`) reads Claude Code's rate-limit data on every prompt and records the 5-hour and 7-day usage percentages to `~/.claude/maestro/usage.json`. A hook (`scripts/usage-gate.sh`, wired in `hooks/hooks.json`) reads that file on every `UserPromptSubmit` and injects a `maestro usage: … mode: …` note into the prompt, and on every `PreToolUse` for an `Agent`/`Task` call it denies `opus-implementer`, `opus-heavy-implementer`, `opus-reviewer`, `opus-researcher` and `sonnet-implementer` once the 5-hour window is at or above the threshold. The threshold is set by the env var `MAESTRO_EXTERNAL_ONLY_AT` (default 75; the older `FABLE_ADVISOR_EXTERNAL_ONLY_AT` and `FABLE_ADVISOR_GROK_ONLY_AT` are still accepted as fallbacks). `advisor`, `codex-peer` and the read-only Explore agent are never gated — they stay available in EXTERNAL-ONLY mode because the point of the mode is preserving Claude quota for judgment, not shutting the session down.

## The spec contract and the simplicity block

Every implementation prompt carries the same five parts, because lanes share none of the architect's conversation context: **objective, files, interfaces, constraints, verification**. The Constraints section always ends with the ponytail simplicity block (`doctrine/ponytail-block.md`) pasted in verbatim, plus the karpathy guidelines block (`doctrine/karpathy-block.md`) — the external lanes don't load this plugin's skills, so both doctrines have to travel inside the spec file itself. The opus agents carry the same ladder directly in their own instructions and apply it even if a spec forgets to paste it.

## Install

```sh
git clone https://github.com/ricardosuman/maestro.git
cd maestro && ./install.sh
```

`install.sh` checks that the `claude` and `jq` CLIs are present and that it can reach the (private) repo over git, then: adds this repo as a plugin marketplace and installs the `maestro` plugin; adds and installs the companion plugins (`openai-codex`, `ponytail`, `karpathy-skills`); writes the orchestration doctrine block (`doctrine/CLAUDE-orchestration.md`) and the always-on-skills block into `~/.claude/CLAUDE.md`; copies `scripts/usage-statusline.sh` into `~/.claude/maestro/`; merges `~/.claude/settings.json` (per-model effort levels, a `statusLine` entry pointing at the usage script, and a `permissions.allow` rule for the grok binary); and, when run interactively, offers to register the Obsidian MCP server.

The grok lanes call the grok binary by its literal absolute path, so add the permission rule `install.sh` prints — `Bash(/Users/<you>/.grok/bin/grok:*)` — to `permissions.allow` in `~/.claude/settings.json` if it isn't merged automatically. The luna/astra/codex-peer lanes need the [Codex CLI](https://github.com/openai/codex) installed and logged in (`npm i -g @openai/codex`, then `codex login`); the grok/grok-research lanes need the [Grok CLI](https://x.ai/cli) installed and logged in (`grok login`). Without one of these, the corresponding lanes report unavailable and the doctrine's fallback rules apply.

**Restart Claude Code (or start a new session)** after installing or updating — hooks, skills and agents only load on a fresh session.

## Updating

Bump the version in `.claude-plugin/plugin.json`, push, then on each machine:

```sh
claude plugin marketplace update maestro && claude plugin update maestro@maestro
```

Restart Claude Code afterward.

## Files

```
.claude-plugin/marketplace.json   plugin marketplace entry
.claude-plugin/plugin.json        plugin manifest (name, version, description)
agents/advisor.md                 Fable 5.1 commitment-boundary advisor
agents/codex-peer.md              cross-vendor discussion peer + reviewer (GPT-6 Astra via Codex CLI)
agents/opus-heavy-implementer.md  Claude Opus 5 high — heavy/correctness-critical implementation
agents/opus-implementer.md        Claude Opus 5 medium — fallback implementation
agents/opus-researcher.md         Claude Opus 5 medium — research fallback
agents/opus-reviewer.md           Claude Opus 5 medium — reviews every luna/grok diff
agents/sonnet-implementer.md      Claude Sonnet 5 medium — manual-use simple implementer
doctrine/CLAUDE-always-on-skills.md   loads ponytail + karpathy skills every session
doctrine/CLAUDE-orchestration.md      the routing doctrine merged into ~/.claude/CLAUDE.md
doctrine/karpathy-block.md            karpathy guidelines block pasted into every spec
doctrine/ponytail-block.md            simplicity ladder block pasted into every spec
hooks/hooks.json                  wires usage-gate.sh to UserPromptSubmit and PreToolUse
install.sh                        one-shot installer
scripts/refresh-doctrine.sh       replaces a doctrine block inside a CLAUDE.md file
scripts/usage-gate.sh             injects the usage note; denies opus/sonnet in EXTERNAL-ONLY mode
scripts/usage-statusline.sh       records usage.json and prints the statusline
skills/astra-lead/SKILL.md        how to hand a whole objective to GPT-6 Astra
skills/grok-lane/SKILL.md         how to drive the Grok 4.6 day-to-day lane
skills/grok-research/SKILL.md     how to drive Grok 4.6 read-only research
skills/luna-lane/SKILL.md         how to drive the GPT-5.6 Luna day-to-day lane
skills/orchestration/SKILL.md     the full routing doctrine
```

## License

MIT (see LICENSE).
