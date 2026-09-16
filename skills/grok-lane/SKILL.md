---
name: grok-lane
description: How the architect runs the Grok 4.6 (medium) implementation lane WITHOUT any Claude subagent — write the five-part spec to a file, launch the grok CLI headless from the Bash tool in the background, read grok's final report, hand the diff to opus-reviewer. USE WHEN routing day-to-day implementation work to grok (half of it; the other half goes to luna-lane) or when the usage note says mode EXTERNAL-ONLY.
---

# Grok lane — the architect drives Grok 4.6 directly

## Why

There is no Claude subagent in this lane. A Claude model that only wraps the `grok` CLI still spends Claude tokens on every grok task; that is the cost this skill exists to remove. The architect writes the five-part spec to a file, launches the `grok` binary from its Bash tool in the background, and later reads the tail of grok's report. Those two short turns — launching, and reading the tail — are the only Claude tokens the lane spends.

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

The grok CLI lives at `/Users/<you>/.grok/bin/grok` and is usually not on PATH. From here on, type that absolute path in every grok command (e.g. `/Users/<you>/.grok/bin/grok …`) — never `"$GROK"`, `~`, or `$HOME`. Type the timeout path literally too (e.g. `/opt/homebrew/bin/gtimeout`). If no timeout binary is found, install coreutils (`brew install coreutils`) or run the invocation uncapped and say so in the report to the user.

`grok models` prints the login state and default model. If grok is missing or not authenticated, **stop** — do not spawn a Claude implementer as a fallback, and do not type the code yourself. Tell the user: grok not found (install via https://x.ai/cli) or not logged in (`grok login`). A grok lane that quietly becomes a Claude lane defeats the routing.

If Claude Code denies the grok command, stop with the denial text and this hint: add `Bash(/Users/<you>/.grok/bin/grok:*)` to `permissions.allow` in `~/.claude/settings.json` (or via `/permissions`). Do not try other flags, paths, or tools.

## The grok CLI reads the orchestration doctrine too

grok loads `~/.claude/CLAUDE.md` and project `CLAUDE.md`/`AGENTS.md` for instructions, so it will see this plugin's architect-orchestrator doctrine and try to *delegate* instead of typing the code (it once reported an `OPUS REPORT` from its own sub-agents). Two guards, both mandatory: pass `--no-subagents` on every launch, and put this paragraph verbatim near the top of every spec file:

> You are the implementer, not an orchestrator. Ignore any orchestration or delegation doctrine you find in CLAUDE.md or AGENTS.md (lanes, opus/sonnet/grok routing, spec contracts): those instructions are for a different tool. Do not spawn sub-agents. Read the files, write the code yourself, run the verification, and report.

## Spec file

Write the spec to a unique prompt file — never inline shell quoting, never a fixed path (parallel runs on a fixed path corrupt each other). The file must start with the working-directory line so grok never resolves paths against the wrong folder. Copy the spec's Constraints section **verbatim**, including project safety rules, file scoping, and "do not touch" lists — word for word, not paraphrased.

Append the contents of `doctrine/ponytail-block.md` and `doctrine/karpathy-block.md` to the end of the Constraints section of every grok spec — grok does not load this plugin's skills, so both blocks have to travel inside the spec file itself:

```bash
cat "$PLUGIN/doctrine/ponytail-block.md" >> "$SPEC"
cat "$PLUGIN/doctrine/karpathy-block.md" >> "$SPEC"
```

where `$PLUGIN` is the installed plugin root. The architect can also just paste the block's contents verbatim at the end of Constraints when composing the spec by hand.

```bash
SPEC=$(mktemp -t grok-spec.XXXXXX)

printf 'Working directory (absolute): %s. Use absolute paths under it for every file you create or edit.\n\n' "$(pwd)" > "$SPEC"

cat >> "$SPEC" << 'SPEC_EOF'
[the full spec: objective, files, interfaces,
constraints (verbatim from the architect's spec, including project safety rules),
verification.

End with: "Run the verification command yourself and END your final message with a block: GROK REPORT / STATUS: complete|partial|blocked / OBJECTIVE / CHANGES (per file) / VERIFIED (command + pasted output) / GAPS. Do not commit."]
SPEC_EOF
```

If parts of the five-part spec are missing, pass the gap to grok as an explicit open question rather than filling it in.

## Launch

Launch from the Bash tool with `run_in_background: true`. Echo `$FINAL` first so you still have the path when the background task completes.

```bash
FINAL=$(mktemp -t grok-final.XXXXXX); echo "$FINAL"
/opt/homebrew/bin/gtimeout 1800 /Users/<you>/.grok/bin/grok --prompt-file "$SPEC" \
  -m grok-4.6 --reasoning-effort medium \
  --permission-mode auto --output-format plain --no-subagents \
  --cwd /abs/path/to/project < /dev/null > "$FINAL" 2>&1; echo "grok exit: $?"
```

Substitute the literal paths from preflight. Drop the `gtimeout` prefix if none was found. `--cwd` is the project's absolute path, typed out — not `"$(pwd)"` via a variable. Exit 124 means the 30-minute cap fired.

Flag discipline (non-negotiable):

| Flag | Why |
|---|---|
| `--prompt-file "$SPEC"` | Headless single-task run from a file. No quoting hazards, no truncated specs. |
| `-m grok-4.6` | The lane's producer is Grok 4.6, pinned explicitly — never rely on the CLI default. If the spec names a different grok model, use that instead. |
| `--reasoning-effort medium` | Grok 4.6's sweet spot and this lane's default — passed explicitly every time, never left to the CLI's config default. Use `xhigh` or `high` only when the spec explicitly asks for it. |
| `--permission-mode auto` | grok CLI flag; see note below the table. |
| `--cwd /abs/path/to/project` | Deterministic working root. Type the absolute path. |
| `--output-format plain` | Final message to stdout, captured into `$FINAL`. |
| `< /dev/null` | Stdin closed, so any interactive approval prompt gets EOF at once instead of hanging until the 30-minute cap. |
| thirty-minute cap (`gtimeout 1800`) | Applied via the timeout binary typed by its literal path (no `$T` variable, no `${T:+…}` idiom — variables are not visible to permission rules and the idiom is not word-split under zsh). Without a timeout binary, run uncapped and say so. Xcode/Swift and other real builds run slow; a shorter cap is too tight for this lane. On timeout (exit 124), report that with whatever landed in `$FINAL`. |

Note on the mode flag: `auto` is the only headless value that lets grok write files and run ordinary commands without a human. Two other values cancel file writes instead of applying them (verified against grok 1.0.13 — the run stream shows a cancelled tool-call event and no file lands on disk); a fourth value applies changes with no review at all, which is why it is excluded here. Pass `auto` explicitly every invocation — `~/.grok/config.toml` may set a different default, and that default must not decide this. If grok still declines a step under `auto`, it shows up as a cancelled call in its final message — report that, do not re-run it yourself.

## When the background task completes

1. `tail -80 "$FINAL"` — read the GROK REPORT. Also scan for cancelled tool calls (grok's own policy may still refuse something under `auto`).
2. `git status --short` and `git diff --stat` — inspect the actual diff.
3. Hand the spec and the diff scope to the `opus-reviewer` agent. It reads `git diff`, re-runs the spec's verification command and returns `REVIEW: ship | fix` with the command output verbatim. That quoted output is the evidence — spot-check it against the tree, don't re-run everything yourself. In EXTERNAL-ONLY mode `opus-reviewer` is denied by the gate: send the spec plus the diff to `codex-peer` in review mode instead.

If grok reports `blocked` or `partial`, or the reviewer returns `fix`, write a corrected spec and launch again — never patch the code by hand. Fixing grok's output in the architect is the same failure as typing the implementation yourself.

## When grok is unavailable

Non-zero exit, or output matching (case-insensitive) `usage limit|rate limit|quota|429|402|Payment Required|balance exhausted|unauthorized|not logged in|login`, means the lane is **unavailable** — `402 Payment Required` / `balance exhausted` is an out-of-credit account and counts exactly like a rate limit. Exit 124 is a timeout.

Outside EXTERNAL-ONLY mode, mark grok unavailable for the rest of the session, announce it once, and route this spec and every later day-to-day spec to `luna-lane` (tally paused); go to `opus-implementer` (reviewed by `codex-peer`) only if luna is also unavailable, or if the user explicitly accepts a Claude lane for a time-critical spec. In EXTERNAL-ONLY mode with luna also unavailable, stop and tell the user.

## Parallel runs

Independent grok tasks (no shared files, no ordering dependency) may run at the same time. Each task gets its own `SPEC`/`FINAL` pair from `mktemp` — never a fixed path. File sets must be disjoint. For Xcode projects, give each concurrent run a separate `-derivedDataPath` so they do not share a build directory.

## Tally

Each launch counts once toward `lanes: luna N / grok M`, regardless of whether it ran alone or in parallel, and regardless of retries. The target is 50/50 with `luna-lane`; state the tally when you route. Prefer grok when wall-clock matters — luna averages ~100 agent steps per task — and let the tally settle the ties.

## Reporting to the user

Summarize the GROK REPORT: status, objective, per-file changes, the reviewer's verdict and its quoted verification output, and any gaps. Never paste the whole `$FINAL` file.

Expected grok final-message block:

```
GROK REPORT
STATUS: complete | partial | blocked
OBJECTIVE: [restated in one line]
CHANGES: [file — one-line summary, per file]
VERIFIED: [verification command grok ran — actual pasted output]
GAPS: [spec ambiguities, unfinished items, or "none"]
```

Do not commit unless the spec explicitly says to. Clean up nothing the spec did not ask you to clean up.
