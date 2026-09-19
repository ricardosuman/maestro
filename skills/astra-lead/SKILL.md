---
name: astra-lead
description: How the architect hands a WHOLE objective to GPT-6 Astra (high) as the lead — write an objective brief to a file, launch `codex exec` headless from the Bash tool in the background, read Astra's report, then send the diff to advisor for the mandatory final review. USE WHEN an objective is self-contained in one repo with a command that proves it done, when the user asks for it, or when the usage note says mode EXTERNAL-ONLY.
---

# Astra lead — a whole objective delegated to GPT-6 Astra

## Why

The other skills delegate a *task*; this one delegates the *objective*. Astra decomposes it, implements it end to end, and verifies it, so the architect spends Claude tokens on exactly two short turns — launching, and reading the tail — plus one final review. There is no Claude subagent in this lane.

Use it when the objective is self-contained in one repo and there is a command that proves it done, when the user asks for it, or when the usage note says `mode: EXTERNAL-ONLY`. When the objective needs judgment the brief cannot fix in advance — an architecture still being decided, or work spanning repos — keep the lead and delegate tasks instead.

Do not spawn a Claude agent to drive codex. Load this skill and run the binary yourself.

## Preflight — once per session

Resolve the codex binary and the timeout wrapper **once**, then type those absolute paths literally for the rest of the session. Claude Code's Bash permission rules match the literal command text, not a variable or `$HOME` expansion: a command that starts with `"$CODEX"` or `~/.nvm/.../codex` will not match a `Bash(<path>:*)` rule.

```bash
command -v codex && codex --version && codex login status

T=$(command -v gtimeout || command -v timeout || true); echo "timeout: ${T:-none}"
```

From here on, type the path `command -v codex` printed in every launch — never `"$CODEX"`, `~`, or `$HOME`. Type the timeout path literally too (e.g. `/opt/homebrew/bin/gtimeout`). If codex is missing or not authenticated, **stop** and tell the user (`npm i -g @openai/codex`, then `codex login`); do not quietly become a Claude lane. If Claude Code denies the command, stop with the denial text and the hint to add `Bash(<the path command -v codex printed>:*)` to `permissions.allow`.

## The objective brief

Astra gets a **brief**, not a five-part spec — it is the lead, so the decomposition is its job, not yours. The brief has four parts:

1. **Goal** — what must be true when this is done, in plain prose.
2. **Repo** — the absolute path, and the working-directory line so nothing resolves against the wrong folder.
3. **Constraints** — project conventions, files and areas not to touch, plus the ponytail and karpathy blocks appended verbatim (codex does not load this plugin's skills, so both blocks travel inside the brief).
4. **Definition of done** — the verification command(s) that prove it, written out exactly.

```bash
BRIEF=$(mktemp -t astra-brief.XXXXXX)

printf 'Working directory (absolute): %s. Use absolute paths under it for every file you create or edit.\n\n' "$(pwd)" > "$BRIEF"

cat >> "$BRIEF" << 'BRIEF_EOF'
You are the lead for this objective: decompose it, implement it end to end,
verify it with the commands below, and finish with an ASTRA REPORT
(STATUS / TASKS DONE / VERIFIED with output / GAPS).

GOAL: [what must be true when this is done]
REPO: [absolute path]
CONSTRAINTS: [project conventions, what not to touch — verbatim]
DEFINITION OF DONE: [the verification command(s), written out]

Do not commit.
BRIEF_EOF

cat "$PLUGIN/doctrine/ponytail-block.md" >> "$BRIEF"
cat "$PLUGIN/doctrine/karpathy-block.md" >> "$BRIEF"
```

where `$PLUGIN` is the installed plugin root. `codex exec` has no `--prompt-file`: the brief goes on argv as `"$(cat "$BRIEF")"`.

## Launch

Launch from the Bash tool with `run_in_background: true`. Echo `$FINAL` first so you still have the path when the background task completes.

```bash
mkdir -p /tmp/maestro-lanes; FINAL=$(mktemp /tmp/maestro-lanes/astra.XXXXXX); echo "$FINAL"
/opt/homebrew/bin/gtimeout 3600 /Users/<you>/.nvm/versions/node/<v>/bin/codex exec \
  --model gpt-6-astra -c model_reasoning_effort=high \
  --sandbox workspace-write -c approval_policy=never --skip-git-repo-check \
  -C /abs/path/to/project "$(cat "$BRIEF")" \
  < /dev/null > "$FINAL" 2>&1; ec=$?; echo "maestro-exit: $ec" >> "$FINAL"; echo "codex exit: $ec"
```

## Dispatching through lane-runner

Dispatching `maestro:lane-runner` with `lane: astra`, the spec file, and the project instead of the Bash launch makes the run appear in Claude Code's native agent list with a transcript.
It costs a little Claude quota while Haiku waits, and the spec file is written exactly the same way.
The Bash launch above remains the default; use lane-runner when native agent visibility matters.

Substitute the literal paths from preflight. Drop the `gtimeout` prefix if none was found. `-C` is the project's absolute path, typed out. Exit 124 means the one-hour cap fired.

Flag discipline (non-negotiable):

| Flag | Why |
|---|---|
| `"$(cat "$BRIEF")"` | The whole brief on argv from a unique file. No inline quoting hazards. `codex exec` has no `--prompt-file`. |
| `--model gpt-6-astra` | The lead's producer, pinned explicitly — never rely on the CLI default. |
| `-c model_reasoning_effort=high` | Explicit every time; the config default on this machine is `low`. |
| `--sandbox workspace-write` | The lead writes code in the project; it must not touch the rest of the disk. |
| `-c approval_policy=never` | Headless: no approval prompt can block the run. Verified on codex-cli 0.153.4 — `codex exec` has **no** `--full-auto` flag, so the config override is the supported way. |
| `--skip-git-repo-check` | Without it codex refuses to start outside a trusted/git directory ("Not inside a trusted directory and --skip-git-repo-check was not specified"). |
| `-C /abs/path/to/project` | Deterministic working root. Type the absolute path. |
| `< /dev/null` | Stdin closed. With stdin open, codex prints "Reading additional input from stdin…" and waits instead of running the argv prompt. |
| one-hour cap (`gtimeout 3600`) | A whole objective needs the longer cap. Applied via the timeout binary typed by its literal path (no `$T` variable, no `${T:+…}` idiom). Without a timeout binary, run uncapped and say so. On timeout (exit 124), report that with whatever landed in `$FINAL`. |

## When the background task completes

1. `tail -120 "$FINAL"` — read the ASTRA REPORT.
2. `git status --short` and `git diff --stat` — inspect the actual scope.
3. **Mandatory final review:** hand the objective and `git diff` to the `advisor` agent in final-review mode. It returns `VERDICT: ship | fix`. Never send Astra-led work to `codex-peer` — same vendor as the implementer is not a second opinion.

Nothing is accepted before that review. `fix` means a corrected brief goes back to this lane — never a hand patch in the architect.

## When Astra is unavailable

Non-zero exit, or output matching (case-insensitive) `usage limit|rate limit|quota|429|402|Payment Required|balance exhausted|unauthorized|not logged in|login`, means the lane is **unavailable** — `402 Payment Required` / `balance exhausted` is an out-of-credit account and counts exactly like a rate limit. Exit 124 is a timeout.

A `"status": 400` in the output is *not* unavailability: it means a bad model name or a bad `model_reasoning_effort` value (codex rejects them rather than silently downgrading). Fix the command; that is a spec or config bug.

Outside EXTERNAL-ONLY mode the architect takes the lead back and routes the objective as ordinary tasks (`luna-lane` / `grok-lane`), saying so explicitly. In EXTERNAL-ONLY mode, stop and tell the user.

## Tally

An Astra-led objective is outside the `lanes: luna N / grok M` tally — it is a lead, not a day-to-day implementation lane.

## Reporting to the user

Summarize the ASTRA REPORT: status, the tasks Astra decomposed the objective into, the per-file scope, the verification with its output, the gaps, and the `advisor` verdict. Never paste the whole `$FINAL` file.

Expected Astra final-message block:

```
ASTRA REPORT
STATUS: complete | partial | blocked
TASKS DONE: [what it decomposed the objective into, one line each]
VERIFIED: [the definition-of-done command(s) — actual pasted output]
GAPS: [ambiguities, unfinished items, or "none"]
```

Do not commit unless the brief explicitly says to.
