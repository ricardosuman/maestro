#!/usr/bin/env bash
# maestro statusline: records Claude rate-limit usage and prints a summary line.
set -u

if ! command -v jq >/dev/null 2>&1; then
  echo "maestro: jq missing"
  exit 0
fi

DIR="$HOME/.claude/maestro"
mkdir -p "$DIR"
T="${MAESTRO_EXTERNAL_ONLY_AT:-${FABLE_ADVISOR_EXTERNAL_ONLY_AT:-${FABLE_ADVISOR_GROK_ONLY_AT:-75}}}"

INPUT="$(cat)"

MODEL="$(echo "$INPUT" | jq -r '.model.display_name // "Claude"')"

FIVE_HOUR_PCT="$(echo "$INPUT" | jq -r '.rate_limits.five_hour.used_percentage // empty')"
FIVE_HOUR_RESETS="$(echo "$INPUT" | jq -r '.rate_limits.five_hour.resets_at // empty')"
SEVEN_DAY_PCT="$(echo "$INPUT" | jq -r '.rate_limits.seven_day.used_percentage // empty')"
SEVEN_DAY_RESETS="$(echo "$INPUT" | jq -r '.rate_limits.seven_day.resets_at // empty')"
CTX_PCT="$(echo "$INPUT" | jq -r '.context_window.used_percentage // empty')"

if [ -n "$FIVE_HOUR_PCT" ] || [ -n "$SEVEN_DAY_PCT" ]; then
  NOW="$(date +%s)"
  TMP="$DIR/usage.json.tmp.$$"
  echo "$INPUT" | jq \
    --arg now "$NOW" \
    '{
      five_hour: (if .rate_limits.five_hour.used_percentage != null then {used_percentage: .rate_limits.five_hour.used_percentage, resets_at: .rate_limits.five_hour.resets_at} else null end),
      seven_day: (if .rate_limits.seven_day.used_percentage != null then {used_percentage: .rate_limits.seven_day.used_percentage, resets_at: .rate_limits.seven_day.resets_at} else null end),
      updated_at: ($now | tonumber | floor)
    }' > "$TMP" 2>/dev/null
  mv "$TMP" "$DIR/usage.json"
fi

if [ -z "$FIVE_HOUR_PCT" ] && [ -z "$SEVEN_DAY_PCT" ]; then
  echo "$MODEL · usage n/a · lanes: split"
  exit 0
fi

FIVE_ROUNDED=""
if [ -n "$FIVE_HOUR_PCT" ]; then
  FIVE_ROUNDED="$(echo "$FIVE_HOUR_PCT" | jq 'round')"
fi

RESET_STR=""
if [ -n "$FIVE_HOUR_RESETS" ]; then
  RESET_STR="$(date -r "$FIVE_HOUR_RESETS" +%H:%M 2>/dev/null || date -d "@$FIVE_HOUR_RESETS" +%H:%M 2>/dev/null || true)"
fi

SEVEN_ROUNDED=""
if [ -n "$SEVEN_DAY_PCT" ]; then
  SEVEN_ROUNDED="$(echo "$SEVEN_DAY_PCT" | jq 'round')"
fi

CTX_ROUNDED=""
if [ -n "$CTX_PCT" ]; then
  CTX_ROUNDED="$(echo "$CTX_PCT" | jq 'round')"
fi

LANES="split"
if [ -n "$FIVE_ROUNDED" ]; then
  if awk -v a="$FIVE_ROUNDED" -v b="$T" 'BEGIN{exit !(a>=b)}'; then
    LANES="external-only"
  fi
fi

LINE="$MODEL"

if [ -n "$FIVE_ROUNDED" ]; then
  if [ -n "$RESET_STR" ]; then
    LINE="$LINE · 5h ${FIVE_ROUNDED}% (↺${RESET_STR})"
  else
    LINE="$LINE · 5h ${FIVE_ROUNDED}%"
  fi
fi

if [ -n "$SEVEN_ROUNDED" ]; then
  LINE="$LINE · 7d ${SEVEN_ROUNDED}%"
fi

if [ -n "$CTX_ROUNDED" ]; then
  LINE="$LINE · ctx ${CTX_ROUNDED}%"
fi

LINE="$LINE · lanes: $LANES"

echo "$LINE"
exit 0
