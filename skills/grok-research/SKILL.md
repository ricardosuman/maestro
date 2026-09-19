---
name: grok-research
description: How the architect runs read-only research on Grok 4.6 (medium) WITHOUT any Claude subagent — write the question to a file, launch the grok CLI headless in plan mode from the Bash tool in the background, read the RESEARCH REPORT. USE WHEN investigating a question across a codebase, docs or the web before deciding; falls back to the opus-researcher agent when grok is unavailable.
---

# Grok research — the architect asks Grok 4.6 to investigate

## Why

Investigation is volume work: greps, file reads, doc pages. Paying architect prices for it is the waste this skill removes. The architect writes the question to a file, launches `grok` in **plan mode** (read-only by construction — it cannot edit files or run mutating commands) from its Bash tool in the background, and later reads the report.

Do not spawn a Claude agent to drive grok. Load this skill and run the binary yourself.

## Preflight — once per session

Resolve the grok binary and the timeout wrapper **once**, then type those absolute paths literally for the rest of the session. Claude Code's Bash permission rules match the literal command text, not a variable or `$HOME` expansion. The user has a rule `Bash(/Users/<you>/.grok/bin/grok:*)`; a command that starts with `"$GROK"` or `~/.grok/bin/grok` will not match it.

```bash
GROK=$(command -v grok 2>/dev/null || true)
[ -z "$GROK" ] && [ -x "$HOME/.grok/bin/grok" ] && GROK="$HOME/.grok/bin/grok"

echo "$GROK"
"$GROK" --version && "$GROK" models 2>&1 | head -3

T=$(command -v gtimeout || command -v timeout || true); echo "timeout: ${T:-none}"
```

The grok CLI lives at `/Users/<you>/.grok/bin/grok` and is usually not on PATH. From here on, type that absolute path in every grok command — never `"$GROK"`, `~`, or `$HOME`. Type the timeout path literally too (e.g. `/opt/homebrew/bin/gtimeout`). If grok is missing or not authenticated, fall back to the `opus-researcher` agent and say so.

If Claude Code denies the grok command, stop with the denial text and this hint: add `Bash(/Users/<you>/.grok/bin/grok:*)` to `permissions.allow` in `~/.claude/settings.json` (or via `/permissions`).

## The question file

```bash
Q=$(mktemp -t grok-research.XXXXXX)

cat > "$Q" << 'Q_EOF'
[the question, stated precisely: what you need to know, why it matters,
where to look (paths, docs, vendor URLs), and what would settle it.

You are researching, not implementing. Do not write or edit files.

End your final message with a block: RESEARCH REPORT / QUESTION /
FINDINGS (each with its source) / SOURCES (path:line or URL, one per line) /
OPEN QUESTIONS.]
Q_EOF
```

Never a fixed path — parallel research runs on a fixed path corrupt each other.

## Launch

Launch from the Bash tool with `run_in_background: true`. Echo `$FINAL` first so you still have the path when the background task completes.

```bash
mkdir -p /tmp/maestro-lanes; FINAL=$(mktemp /tmp/maestro-lanes/research.XXXXXX); echo "$FINAL"
/opt/homebrew/bin/gtimeout 900 /Users/<you>/.grok/bin/grok --prompt-file "$Q" \
  -m grok-4.6 --reasoning-effort medium \
  --permission-mode plan --output-format plain --no-subagents \
  --cwd /abs/path/to/project < /dev/null > "$FINAL" 2>&1; ec=$?; echo "maestro-exit: $ec" >> "$FINAL"; echo "grok exit: $ec"
```

Substitute the literal paths from preflight. Drop the `gtimeout` prefix if none was found. Exit 124 means the fifteen-minute cap fired.

Flag discipline (non-negotiable):

| Flag | Why |
|---|---|
| `--prompt-file "$Q"` | Headless single-task run from a file. No quoting hazards, no truncated questions. |
| `-m grok-4.6` | The producer, pinned explicitly — never rely on the CLI default. |
| `--reasoning-effort medium` | Grok 4.6's sweet spot, and plenty for investigation. Passed explicitly every time; `~/.grok/config.toml` may set a different default and that default must not decide this. |
| `--permission-mode plan` | Read-only by construction: grok investigates and plans, it cannot edit files. This is what makes the lane safe to run unattended. |
| `--no-subagents` | grok loads `~/.claude/CLAUDE.md` and project `CLAUDE.md`/`AGENTS.md`, sees this plugin's delegation doctrine, and would otherwise try to spawn its own lanes. |
| `--cwd /abs/path/to/project` | Deterministic working root. Type the absolute path. |
| `--output-format plain` | Final message to stdout, captured into `$FINAL`. |
| `< /dev/null` | Stdin closed, so any interactive prompt gets EOF at once instead of hanging until the cap. |
| fifteen-minute cap (`gtimeout 900`) | Applied via the timeout binary typed by its literal path (no `$T` variable, no `${T:+…}` idiom). Research that runs longer than this is a question that needed splitting. On timeout (exit 124), report that with whatever landed in `$FINAL`. |

## When the background task completes

`tail -120 "$FINAL"` and read the RESEARCH REPORT. Keep the conclusions and the sources in your context; do not paste the whole file. Findings with no source are open questions, not answers.

## When grok is unavailable

Non-zero exit, or output matching (case-insensitive) `usage limit|rate limit|quota|429|402|Payment Required|balance exhausted|unauthorized|not logged in|login`, means the lane is **unavailable** — `402 Payment Required` / `balance exhausted` is an out-of-credit account and counts exactly like a rate limit. Exit 124 is a timeout.

Either way, re-route the same question to the `opus-researcher` agent and say so explicitly.

## Tally

Research does not count toward the `lanes: luna N / grok M` implementation tally.
