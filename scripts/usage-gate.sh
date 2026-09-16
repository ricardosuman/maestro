#!/usr/bin/env bash
# maestro usage gate: injects usage context into prompts and denies
# the Claude opus/sonnet lanes when the 5h window is over threshold
# (EXTERNAL-ONLY mode: luna, grok and astra carry the implementation).
set -u

MODE="${1:-}"

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

FILE="$HOME/.claude/maestro/usage.json"
T="${MAESTRO_EXTERNAL_ONLY_AT:-${FABLE_ADVISOR_EXTERNAL_ONLY_AT:-${FABLE_ADVISOR_GROK_ONLY_AT:-75}}}"

compute_state() {
  STATE="unknown"
  PCT=""
  RESET=""
  SEVEN=""

  if [ ! -f "$FILE" ]; then
    return
  fi

  FIVE_HOUR="$(jq -r '.five_hour // empty' "$FILE" 2>/dev/null)"
  if [ -z "$FIVE_HOUR" ] || [ "$FIVE_HOUR" = "null" ]; then
    return
  fi

  UPDATED_AT="$(jq -r '.updated_at // empty' "$FILE" 2>/dev/null)"
  if [ -z "$UPDATED_AT" ]; then
    return
  fi

  NOW="$(date +%s)"
  AGE=$((NOW - UPDATED_AT))
  if [ "$AGE" -gt 10800 ]; then
    return
  fi

  RAW_PCT="$(jq -r '.five_hour.used_percentage // empty' "$FILE" 2>/dev/null)"
  if [ -z "$RAW_PCT" ]; then
    return
  fi
  PCT="$(jq -r '(.five_hour.used_percentage | round)' "$FILE" 2>/dev/null)"

  RESETS_AT="$(jq -r '.five_hour.resets_at // empty' "$FILE" 2>/dev/null)"
  if [ -n "$RESETS_AT" ]; then
    if [ "$NOW" -ge "$RESETS_AT" ]; then
      STATE="unknown"
      PCT=""
      RESET=""
      SEVEN=""
      return
    fi
    RESET="$(date -r "$RESETS_AT" +%H:%M 2>/dev/null || date -d "@$RESETS_AT" +%H:%M 2>/dev/null || true)"
  fi

  RAW_SEVEN="$(jq -r '.seven_day.used_percentage // empty' "$FILE" 2>/dev/null)"
  if [ -n "$RAW_SEVEN" ]; then
    SEVEN="$(jq -r '(.seven_day.used_percentage | round)' "$FILE" 2>/dev/null)"
  fi

  STATE="known"
}

compute_state

MODE_LABEL="split"
if [ "$STATE" = "known" ] && [ -n "$PCT" ]; then
  if awk -v a="$PCT" -v b="$T" 'BEGIN{exit !(a>=b)}'; then
    MODE_LABEL="external-only"
  fi
fi

case "$MODE" in
  context)
    if [ "$STATE" = "unknown" ]; then
      MSG="maestro usage: unknown (statusline not reporting yet) · mode: split (assumed)."
    elif [ "$MODE_LABEL" = "external-only" ]; then
      MSG="maestro usage: Claude 5h ${PCT}% ≥ ${T}% · mode: EXTERNAL-ONLY — every implementation task goes to the luna, grok or astra lane (maestro:luna-lane / grok-lane / astra-lead skills, launched by the architect) and reviews go to codex-peer; opus-implementer, opus-heavy-implementer, opus-reviewer, opus-researcher and sonnet-implementer are denied by the PreToolUse gate until the 5h window drops below ${T}%. advisor, codex-peer and Explore remain available."
    else
      if [ -n "$SEVEN" ]; then
        MSG="maestro usage: Claude 5h ${PCT}% (resets ${RESET}) · 7d ${SEVEN}% · mode: split — day-to-day tasks → the luna lane (maestro:luna-lane skill) / the grok lane (maestro:grok-lane skill), 50/50, launched by the architect, every diff reviewed by maestro:opus-reviewer; heavy code → maestro:opus-heavy-implementer."
      else
        MSG="maestro usage: Claude 5h ${PCT}% (resets ${RESET}) · mode: split — day-to-day tasks → the luna lane (maestro:luna-lane skill) / the grok lane (maestro:grok-lane skill), 50/50, launched by the architect, every diff reviewed by maestro:opus-reviewer; heavy code → maestro:opus-heavy-implementer."
      fi
    fi
    jq -n --arg msg "$MSG" '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$msg}}' 2>/dev/null
    exit 0
    ;;
  gate)
    INPUT="$(cat)"
    TOOL_NAME="$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)"
    if [ "$TOOL_NAME" != "Agent" ] && [ "$TOOL_NAME" != "Task" ]; then
      exit 0
    fi
    SUBAGENT="$(echo "$INPUT" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null)"
    case "$SUBAGENT" in
      maestro:opus-implementer|maestro:opus-heavy-implementer|maestro:opus-reviewer|maestro:opus-researcher|maestro:sonnet-implementer|opus-implementer|opus-heavy-implementer|opus-reviewer|opus-researcher|sonnet-implementer)
        if [ "$STATE" = "known" ] && [ "$MODE_LABEL" = "external-only" ]; then
          REASON="maestro usage gate: Claude 5h usage ${PCT}% ≥ ${T}%. EXTERNAL-ONLY mode: route this spec to the luna, grok or astra lane; reviews go to codex-peer. The opus/sonnet lanes stay blocked until the 5h window drops below ${T}%."
          jq -n --arg reason "$REASON" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$reason}}' 2>/dev/null
        fi
        exit 0
        ;;
      *)
        exit 0
        ;;
    esac
    ;;
  *)
    exit 0
    ;;
esac
