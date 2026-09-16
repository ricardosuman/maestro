# maestro

Maestro started as an adaptation of [DannyMac180/fable-advisor](https://github.com/DannyMac180/fable-advisor) (MIT) and has since been rewritten around its own doctrine.

The current doctrine:

- **`luna-lane` skill** — day-to-day implementation lane (GPT-5.6 Luna at effort `max`, via `codex exec`). The architect launches `codex` itself from Bash; no Claude subagent is involved
- **`grok-lane` skill** — the other day-to-day lane (Grok 4.6 at effort `medium`, via the Grok CLI), launched the same way
- **`astra-lead` skill** — a whole objective delegated to GPT-6 Astra (high) as the lead: it decomposes, implements and verifies end to end
- **`grok-research` skill** — read-only investigation (Grok 4.6 medium, plan mode); falls back to `opus-researcher`
- **`opus-heavy-implementer`** — heavy implementation lane (Claude Opus 5, high) for complex algorithms, concurrency, migrations, many-file changes
- **`opus-implementer`** — fallback implementation lane (Claude Opus 5, medium) when luna or grok is rate-limited/unavailable
- **`opus-reviewer`** — read-only reviewer (Claude Opus 5, medium) for every luna/grok diff; re-runs the spec's verification
- **`opus-researcher`** — research fallback (Claude Opus 5, medium), read-only
- **`codex-peer`** — cross-vendor *discussion* peer and reviewer (GPT-6 Astra via the Codex CLI); analyzes and gives verdicts, never implements
- **`advisor`** — commitment-boundary advisor (Fable 5.1, high) and final reviewer of Astra-led work; advises only
- **`sonnet-implementer`** — kept for manual use; **not routed** by the doctrine
- **`orchestration` skill** — the architect-as-orchestrator routing doctrine and five-part spec contract

Every lane passes its model *and* its effort explicitly — CLI config defaults never decide a lane's effort.

### Routing: 50/50 luna/grok, opus review, EXTERNAL-ONLY mode

Day-to-day implementation (simple to reasonably complex, plus all cheap work) is split **50/50 between `luna-lane` (Luna at `max`) and `grok-lane` (Grok 4.6 at `medium`)**; the architect keeps a running `lanes: luna N / grok M` tally and corrects toward 50/50 when it drifts. Prefer grok when wall-clock matters (Luna averages ~100 agent steps), luna for cheap volume work. Heavy code goes to `opus-heavy-implementer`, outside the tally.

Every luna/grok diff goes to **`opus-reviewer`** before the architect accepts it: it reads the diff, re-runs the spec's verification command and returns `ship`/`fix` with `file:line` findings. Diffs from the opus lanes go to `codex-peer` instead — the reviewer is never the implementer's own vendor. Final review of a multi-step deliverable: Fable-led → `codex-peer`, Astra-led → `advisor`; never both, never neither.

When a lane reports unavailable / rate-limited / timed out (non-zero exit, or `429`, `402 Payment Required`, an exhausted balance, a quota or login error), it is marked unavailable for the rest of the session and announced once; its share moves to the other external lane and the 50/50 tally is paused while one lane is down. `opus-implementer`, reviewed by `codex-peer`, is used only when both external lanes are unavailable, or when the user explicitly accepts a Claude lane for a time-critical spec because only the slow lane is left; research falls back to `opus-researcher`.

A statusline script and hooks track how much of the current Claude 5-hour usage window has been consumed and inject a usage note (`maestro usage: … mode: …`) into every prompt. Once that window reaches **75%** (override with the env var `MAESTRO_EXTERNAL_ONLY_AT`; the older `FABLE_ADVISOR_EXTERNAL_ONLY_AT` and `FABLE_ADVISOR_GROK_ONLY_AT` still work as fallbacks), the note flips to `mode: EXTERNAL-ONLY` — the mode previously called `GROK-ONLY`: every implementation task runs through the luna, grok and astra lanes, launched by the architect itself; no Claude implementation subagent is spawned, and a PreToolUse gate denies `opus-implementer`, `opus-heavy-implementer`, `opus-reviewer`, `opus-researcher` and `sonnet-implementer` outright, so reviews go to `codex-peer`. `advisor`, `codex-peer`, and the read-only Explore agent stay available throughout, since the point of the mode is preserving Claude quota for judgment, not shutting the session down. If both grok and codex are unavailable in EXTERNAL-ONLY mode, the architect stops and tells the user instead of silently falling back to a Claude lane.

Requires the [Codex CLI](https://github.com/openai/codex) installed and logged in (`codex login`) for `luna-lane`, `astra-lead` and `codex-peer`, and the [Grok CLI](https://x.ai/cli) installed and logged in (`grok login`) for `grok-lane` and `grok-research`.

The grok lanes call the grok binary by its literal absolute path (never a `$GROK` variable, `~`, or `$HOME`), because Claude Code's Bash permission rules match the literal command text. Add the permission rule printed by `install.sh` (`Bash(<home>/.grok/bin/grok:*)`) to `permissions.allow` in `~/.claude/settings.json` once (or via `/permissions`); the codex lanes need the same treatment for the path `command -v codex` prints.

GPT-5.6 Sol at high/xhigh is a strong third day-to-day option if Codex quota isn't the constraint — it shares that quota with Luna, which is why it isn't wired in.

## Install (any machine — macOS or Linux/Omarchy)

Prereqs: [Claude Code](https://claude.com/claude-code) and git access to this private repo (easiest: `gh auth login && gh auth setup-git`).

```sh
git clone https://github.com/ricardosuman/maestro.git
cd maestro && ./install.sh
```

Running `./install.sh` adds this repo as a plugin marketplace, installs this plugin and the companion plugins (codex, ponytail, karpathy), and merges the required settings keys into `~/.claude/settings.json`. It installs both managed `CLAUDE.md` sections and can register the Obsidian MCP when run interactively.

**Restart the Claude Code session after running `install.sh`** — hooks, skills and agents (including the `luna-lane`/`grok-lane`/`astra-lead`/`grok-research` skills and the EXTERNAL-ONLY usage gate) only load on a fresh session. The doctrine assumes the session runs Fable 5.1 at effort high; switch with `/model` if it doesn't.

Manual alternative, inside Claude Code:

```
/plugin marketplace add ricardosuman/maestro
/plugin install maestro@maestro
```

…then copy `doctrine/CLAUDE-orchestration.md` into `~/.claude/CLAUDE.md` yourself.

The `luna-lane` and `astra-lead` skills and the `codex-peer` agent need the OpenAI Codex CLI installed and authenticated (`codex login`); without it, day-to-day work runs on grok alone.

### Simplicity doctrine

Every spec's Constraints section ends with the ponytail simplicity block (`doctrine/ponytail-block.md`) and the karpathy guidelines block (`doctrine/karpathy-block.md`) pasted verbatim, so both travel into every lane that doesn't load this plugin's skills. The opus implementer agents carry the same ladder directly and apply it even when a spec forgets to paste it; `opus-reviewer` checks the diff against it.

## Updating

Push changes here, then on each machine: `/plugin marketplace update maestro` (or reinstall).
