#!/usr/bin/env bash
# Replace the maestro orchestration doctrine block inside a CLAUDE.md file.
set -euo pipefail

CLAUDE_MD="${1:-}"
DOCTRINE_MD="${2:-}"

if [ -z "$CLAUDE_MD" ] || [ -z "$DOCTRINE_MD" ]; then
  echo "usage: refresh-doctrine.sh <claude_md_path> <doctrine_md_path>" >&2
  exit 1
fi

if [ ! -f "$CLAUDE_MD" ]; then
  echo "error: claude_md not found: $CLAUDE_MD" >&2
  exit 1
fi

if [ ! -f "$DOCTRINE_MD" ]; then
  echo "error: doctrine_md not found: $DOCTRINE_MD" >&2
  exit 1
fi

MARKER="$(head -n 1 "$DOCTRINE_MD")"

# Pre-rename marker: strip a stale fable-advisor-plugin block left by an
# older install before inserting the current (maestro-plugin) block, so an
# upgrade never leaves two orchestration blocks.
OLD_MARKER="# Orchestration doctrine (fable-advisor plugin) — always active"
OLD_REMOVED=0

if [ "$OLD_MARKER" != "$MARKER" ] && grep -qF "$OLD_MARKER" "$CLAUDE_MD"; then
  TMP="$(mktemp)"
  awk -v marker="$OLD_MARKER" '
    BEGIN { in_block = 0 }
    {
      if ($0 == marker) { in_block = 1; next }
      if (in_block) {
        if ($0 ~ /^# /) { in_block = 0; print "" } else { next }
      }
      print
    }
  ' "$CLAUDE_MD" > "$TMP"
  mv "$TMP" "$CLAUDE_MD"
  OLD_REMOVED=1
fi

TMP="$(mktemp)"

if ! grep -qF "$MARKER" "$CLAUDE_MD"; then
  cat "$CLAUDE_MD" > "$TMP"
  echo "" >> "$TMP"
  cat "$DOCTRINE_MD" >> "$TMP"
  mv "$TMP" "$CLAUDE_MD"
  if [ "$OLD_REMOVED" -eq 1 ]; then
    echo "doctrine: replaced (old block removed)"
  else
    echo "doctrine: appended"
  fi
else
  awk -v marker="$MARKER" -v doctrine="$DOCTRINE_MD" '
    BEGIN { in_block = 0; printed = 0 }
    {
      if ($0 == marker) {
        in_block = 1
        while ((getline line < doctrine) > 0) {
          print line
        }
        close(doctrine)
        printed = 1
        next
      }
      if (in_block) {
        if ($0 ~ /^# /) {
          in_block = 0
          print ""
        } else {
          next
        }
      }
      print
    }
  ' "$CLAUDE_MD" > "$TMP"
  mv "$TMP" "$CLAUDE_MD"
  if [ "$OLD_REMOVED" -eq 1 ]; then
    echo "doctrine: replaced (old block removed)"
  else
    echo "doctrine: replaced"
  fi
fi
