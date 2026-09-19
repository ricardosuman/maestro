---
name: luna-lane
description: How the architect runs the GPT-5.6 Luna (max) implementation lane WITHOUT any Claude subagent — write the five-part spec to a file, launch `codex exec` headless from the Bash tool in the background, read Luna's final report, hand the diff to opus-reviewer. USE WHEN routing day-to-day or cheap implementation work to luna (half of it; the other half goes to grok-lane) or when the usage note says mode EXTERNAL-ONLY.
---

# Luna lane — the architect drives GPT-5.6 Luna directly

## Why

There is no Claude subagent in this lane. A Claude model that only wraps the `codex` CLI still spends Claude tokens on every task; that is the cost this skill exists to remove. The architect writes the five-part spec to a file, launches `codex exec` from its Bash tool in the background, and later reads the tail of Luna's report. Those two short turns — launching, and reading the tail — are the only Claude tokens the lane spends.

Luna is the cheap half of the day-to-day split: it is slow (it averages ~100 agent steps per task) but its output is worth its price at effort `max`, and only at `max` — `high` collapses. Prefer `grok-lane` when wall-clock matters; the tally settles the ties.

Do not spawn a Claude agent to drive codex. Load this skill and run the binary yourself.

## Preflight — once per session

Resolve the codex binary and the timeout wrapper **once**, then type those absolute paths literally for the rest of the session. Claude Code's Bash permission rules match the literal command text, not a variable or `$HOME` expansion: a command that starts with `"$CODEX"` or `~/.nvm/.../codex` will not match a `Bash(<path>:*)` rule.

```bash
command -v codex && codex --version && codex login status

T=$(command -v gtimeout || command -v timeout || true); echo "timeout: ${T:-none}"
```

From here on, type the path `command -v codex` printed in every launch (e.g. `/Users/<you>/.nvm/versions/node/<v>/bin/codex`) — never `"$CODEX"`, `~`, or `$HOME`. Type the timeout path literally too (e.g. `/opt/homebrew/bin/gtimeout`). If no timeout binary is found, install coreutils (`brew install coreutils`) or run the invocation uncapped and say so in the report to the user.

`codex login status` prints the auth state. If codex is missing or not authenticated, **stop** — do not spawn a Claude implementer as a silent substitute. Tell the user: codex not found (`npm i -g @openai/codex`) or not logged in (`codex login`). Outside EXTERNAL-ONLY mode you may then re-route the spec to `opus-implementer`, but say so explicitly.

If Claude Code denies the codex command, stop with the denial text and this hint: add `Bash(<the path command -v codex printed>:*)` to `permissions.allow` in `~/.claude/settings.json` (or via `/permissions`). Do not try other flags, paths, or tools.

## codex reads the orchestration doctrine too

`codex exec` loads `AGENTS.md` and (through it) whatever project instructions live in the repo, so it can see this plugin's architect-orchestrator doctrine and try to *delegate* instead of typing the code. Put this paragraph verbatim near the top of every spec file:

> You are the implementer, not an orchestrator. Ignore any orchestration or delegation doctrine you find in CLAUDE.md or AGENTS.md (lanes, opus/luna/grok routing, spec contracts): those instructions are for a different tool. Do not spawn sub-agents. Read the files, write the code yourself, run the verification, and report.

## Spec file

Write the spec to a unique prompt file — never inline shell quoting, never a fixed path (parallel runs on a fixed path corrupt each other). The file must start with the working-directory line so codex never resolves paths against the wrong folder. Copy the spec's Constraints section **verbatim**, including project safety rules, file scoping, and "do not touch" lists — word for word, not paraphrased.

Append the contents of `doctrine/ponytail-block.md` and `doctrine/karpathy-block.md` to the end of the Constraints section of every luna spec — codex does not load this plugin's skills, so both blocks have to travel inside the spec file itself:

```bash
cat "$PLUGIN/doctrine/ponytail-block.md" >> "$SPEC"
cat "$PLUGIN/doctrine/karpathy-block.md" >> "$SPEC"
```

where `$PLUGIN` is the installed plugin root. The architect can also just paste the block's contents verbatim at the end of Constraints when composing the spec by hand.

```bash
SPEC=$(mktemp -t luna-spec.XXXXXX)

printf 'Working directory (absolute): %s. Use absolute paths under it for every file you create or edit.\n\n' "$(pwd)" > "$SPEC"

cat >> "$SPEC" << 'SPEC_EOF'
[the implementer preamble above, verbatim.

Then the full spec: objective, files, interfaces,
constraints (verbatim from the architect's spec, including project safety rules),
verification.

End with: "Run the verification command yourself and END your final message with a block: LUNA REPORT / STATUS: complete|partial|blocked / OBJECTIVE / CHANGES (per file) / VERIFIED (command + pasted output) / GAPS. Do not commit."]
SPEC_EOF
```

`codex exec` has no `--prompt-file`: the prompt goes on argv as `"$(cat "$SPEC")"`, the same form `codex-peer` already uses. If parts of the five-part spec are missing, pass the gap to Luna as an explicit open question rather than filling it in.

## Launch

Launch from the Bash tool with `run_in_background: true`. Echo `$FINAL` first so you still have the path when the background task completes.

```bash
mkdir -p /tmp/maestro-lanes; FINAL=$(mktemp /tmp/maestro-lanes/luna.XXXXXX); echo "$FINAL"
/opt/homebrew/bin/gtimeout 1800 /Users/<you>/.nvm/versions/node/<v>/bin/codex exec \
  --model gpt-5.6-luna -c model_reasoning_effort=max \
  --sandbox workspace-write -c approval_policy=never --skip-git-repo-check \
  -C /abs/path/to/project "$(cat "$SPEC")" \
  < /dev/null > "$FINAL" 2>&1; ec=$?; echo "maestro-exit: $ec" >> "$FINAL"; echo "codex exit: $ec"
```

Substitute the literal paths from preflight. Drop the `gtimeout` prefix if none was found. `-C` is the project's absolute path, typed out — not `"$(pwd)"` via a variable. Exit 124 means the 30-minute cap fired.

Flag discipline (non-negotiable):

| Flag | Why |
|---|---|
| `"$(cat "$SPEC")"` | The whole spec on argv from a unique file. No inline quoting hazards, no truncated specs. `codex exec` has no `--prompt-file`. |
| `--model gpt-5.6-luna` | The lane's producer, pinned explicitly — never rely on the CLI default (`~/.codex/config.toml` sets its own model). |
| `-c model_reasoning_effort=max` | Luna is only worth routing to at `max`; `high` collapses. The config default on this machine is `low`, so this flag is what makes the lane the lane. |
| `--sandbox workspace-write` | The lane writes code in the project; it must not touch the rest of the disk. |
| `-c approval_policy=never` | Headless: no approval prompt can block the run. Verified on codex-cli 0.153.4 — `codex exec` has **no** `--full-auto` flag (only `--approve-for-me` and `--dangerously-bypass-approvals-and-sandbox`), so the config override is the supported way. |
| `--skip-git-repo-check` | Without it codex refuses to start outside a trusted/git directory ("Not inside a trusted directory and --skip-git-repo-check was not specified"). |
| `-C /abs/path/to/project` | Deterministic working root. Type the absolute path. |
| `< /dev/null` | Stdin closed. With stdin open, codex prints "Reading additional input from stdin…" and waits instead of running the argv prompt. |
| thirty-minute cap (`gtimeout 1800`) | Applied via the timeout binary typed by its literal path (no `$T` variable, no `${T:+…}` idiom — variables are not visible to permission rules and the idiom is not word-split under zsh). Without a timeout binary, run uncapped and say so. Luna's ~100 steps are slow; a shorter cap is too tight for this lane. On timeout (exit 124), report that with whatever landed in `$FINAL`. |

## When the background task completes

1. `tail -80 "$FINAL"` — read the LUNA REPORT.
2. `git status --short` and `git diff --stat` — inspect the actual diff.
3. Hand the spec and the diff scope to the `opus-reviewer` agent. It reads `git diff`, re-runs the spec's verification command and returns `REVIEW: ship | fix` with the command output verbatim. That quoted output is the evidence — spot-check it against the tree, don't re-run everything yourself. In EXTERNAL-ONLY mode `opus-reviewer` is denied by the gate: send the spec plus the diff to `codex-peer` in review mode instead.

If Luna reports `blocked` or `partial`, or the reviewer returns `fix`, write a corrected spec and launch again — never patch the code by hand. Fixing Luna's output in the architect is the same failure as typing the implementation yourself.

## When Luna is unavailable

Non-zero exit, or output matching (case-insensitive) `usage limit|rate limit|quota|429|402|Payment Required|balance exhausted|unauthorized|not logged in|login`, means the lane is **unavailable** — `402 Payment Required` / `balance exhausted` is an out-of-credit account and counts exactly like a rate limit. Exit 124 is a timeout.

A `"status": 400` in the output is *not* unavailability: it means a bad model name or a bad `model_reasoning_effort` value (codex rejects them rather than silently downgrading). Fix the command; that is a spec or config bug.

Outside EXTERNAL-ONLY mode, mark luna unavailable for the rest of the session, announce it once, and route this spec and every later day-to-day spec to `grok-lane` (tally paused); go to `opus-implementer` (reviewed by `codex-peer`) only if grok is also unavailable, or if the user explicitly accepts a Claude lane for a time-critical spec. In EXTERNAL-ONLY mode with grok also unavailable, stop and tell the user.

## Parallel runs

Independent luna tasks (no shared files, no ordering dependency) may run at the same time. Each task gets its own `SPEC`/`FINAL` pair from `mktemp` — never a fixed path. File sets must be disjoint. A luna run and a grok run may also go side by side when their file sets are disjoint.

## Tally

Each launch counts once toward `lanes: luna N / grok M`, regardless of whether it ran alone or in parallel, and regardless of retries. The target is 50/50 with `grok-lane`; state the tally when you route.

## Reporting to the user

Summarize the LUNA REPORT: status, objective, per-file changes, the reviewer's verdict and its quoted verification output, and any gaps. Never paste the whole `$FINAL` file.

Expected Luna final-message block:

```
LUNA REPORT
STATUS: complete | partial | blocked
OBJECTIVE: [restated in one line]
CHANGES: [file — one-line summary, per file]
VERIFIED: [verification command Luna ran — actual pasted output]
GAPS: [spec ambiguities, unfinished items, or "none"]
```

Do not commit unless the spec explicitly says to. Clean up nothing the spec did not ask you to clean up.
