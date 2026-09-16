#!/usr/bin/env bash
# One-shot installer for the maestro plugin.
# Usage: ./install.sh   (or: curl the repo via git clone first — the repo is private)
set -euo pipefail

REPO="ricardosuman/maestro"
MARKETPLACE="maestro"
PLUGIN="maestro"
CLAUDE_MD="$HOME/.claude/CLAUDE.md"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$SCRIPT_DIR"

if ! command -v claude >/dev/null 2>&1; then
  echo "error: claude CLI not found. Install Claude Code first: https://claude.com/claude-code" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required for the settings merge. Install it with: brew install jq" >&2
  exit 1
fi

# The repo is private: Claude Code clones it with git, so git needs GitHub credentials.
if ! git ls-remote "https://github.com/$REPO" >/dev/null 2>&1; then
  echo "error: cannot reach https://github.com/$REPO with git." >&2
  echo "The repo is private — authenticate first, e.g.:" >&2
  echo "  gh auth login && gh auth setup-git    # or configure an SSH key" >&2
  exit 1
fi

echo "==> Adding marketplace $REPO"
claude plugin marketplace add "$REPO" || claude plugin marketplace update "$MARKETPLACE"

echo "==> Installing plugin $PLUGIN@$MARKETPLACE"
claude plugin install "$PLUGIN@$MARKETPLACE"

COMPANIONS=(
  "openai/codex-plugin-cc|openai-codex|codex"
  "DietrichGebert/ponytail|ponytail|ponytail"
  "forrestchang/andrej-karpathy-skills|karpathy-skills|andrej-karpathy-skills"
)

for companion in "${COMPANIONS[@]}"; do
  IFS='|' read -r companion_repo companion_marketplace companion_plugin <<EOF
$companion
EOF
  echo "==> Adding marketplace $companion_repo"
  if ! claude plugin marketplace add "$companion_repo"; then
    if ! claude plugin marketplace update "$companion_marketplace"; then
      echo "    warning: could not add or update $companion_marketplace; skipping $companion_plugin" >&2
      continue
    fi
  fi

  echo "==> Installing plugin $companion_plugin@$companion_marketplace"
  if ! claude plugin install "$companion_plugin@$companion_marketplace"; then
    echo "    warning: could not install $companion_plugin@$companion_marketplace; continuing" >&2
  fi
done

echo "==> Installing orchestration doctrine into $CLAUDE_MD"
mkdir -p "$(dirname "$CLAUDE_MD")"
[ -f "$CLAUDE_MD" ] || touch "$CLAUDE_MD"
DOCTRINE_RESULT="$("$REPO_DIR/scripts/refresh-doctrine.sh" "$CLAUDE_MD" "$REPO_DIR/doctrine/CLAUDE-orchestration.md")"
echo "    $DOCTRINE_RESULT"

echo "==> Installing usage statusline"
mkdir -p "$HOME/.claude/maestro"
cp "$REPO_DIR/scripts/usage-statusline.sh" "$HOME/.claude/maestro/usage-statusline.sh"
chmod +x "$HOME/.claude/maestro/usage-statusline.sh"

SETTINGS_JSON="$HOME/.claude/settings.json"
SETTINGS_BACKUP="$SETTINGS_JSON.bak-bootstrap"
SETTINGS_WAS_MISSING=0
if [ ! -f "$SETTINGS_JSON" ]; then
  mkdir -p "$(dirname "$SETTINGS_JSON")"
  printf '%s\n' '{}' > "$SETTINGS_JSON"
  SETTINGS_WAS_MISSING=1
fi
cp "$SETTINGS_JSON" "$SETTINGS_BACKUP"

STATUSLINE_PRESENT=0
if jq -e 'has("statusLine")' "$SETTINGS_JSON" >/dev/null 2>&1; then
  STATUSLINE_PRESENT=1
fi

MODEL_PRESENT=0
MODEL_VALUE=""
if jq -e 'has("model")' "$SETTINGS_JSON" >/dev/null 2>&1; then
  MODEL_PRESENT=1
  MODEL_VALUE="$(jq -r '.model | tostring' "$SETTINGS_JSON")"
fi

SETTINGS_TMP="$(mktemp "$HOME/.claude/settings.json.tmp.XXXXXX")"
jq --arg grok_rule "Bash($HOME/.grok/bin/grok:*)" '
  .modelSettings = (
    {
      "claude-fable-5": {"effortLevel": "high"},
      "claude-fable-5-1": {"effortLevel": "high"},
      "claude-opus-5": {"effortLevel": "medium"},
      "claude-sonnet-5": {"effortLevel": "medium"}
    }
    + (if (.modelSettings | type) == "object" then .modelSettings else {} end)
  )
  | if has("model") then . else .model = "claude-fable-5-1" end
  | .permissions = (if (.permissions | type) == "object" then .permissions else {} end)
  | .permissions.allow = (
      (if (.permissions.allow | type) == "array" then .permissions.allow else [] end)
      | if index($grok_rule) == null then . + [$grok_rule] else . end
    )
  | if has("statusLine") then . else .statusLine = {
      type: "command",
      command: "bash ~/.claude/maestro/usage-statusline.sh"
    } end
' "$SETTINGS_JSON" > "$SETTINGS_TMP"
mv "$SETTINGS_TMP" "$SETTINGS_JSON"

if [ "$STATUSLINE_PRESENT" -eq 1 ]; then
  echo "    statusLine already configured in $SETTINGS_JSON — point it at ~/.claude/maestro/usage-statusline.sh to enable the usage gate"
elif [ "$SETTINGS_WAS_MISSING" -eq 1 ]; then
  echo "    created $SETTINGS_JSON with statusLine pointed at usage-statusline.sh"
else
  echo "    statusLine configured in $SETTINGS_JSON"
fi

if [ "$MODEL_PRESENT" -eq 1 ]; then
  echo "    model configured as $MODEL_VALUE; doctrine assumes Fable 5.1 (use /model to switch)"
fi

echo "==> Installing always-on skills doctrine into $CLAUDE_MD"
ALWAYS_ON_RESULT="$("$REPO_DIR/scripts/refresh-doctrine.sh" "$CLAUDE_MD" "$REPO_DIR/doctrine/CLAUDE-always-on-skills.md")"
echo "    $ALWAYS_ON_RESULT"

OBSIDIAN_NOTE="registration skipped (non-interactive)"
if [ -t 0 ]; then
  MCP_SERVERS="$(claude mcp list 2>/dev/null || true)"
  if printf '%s\n' "$MCP_SERVERS" | grep -Eq '(^|[[:space:]])obsidian([[:space:]:]|$)'; then
    OBSIDIAN_NOTE="already registered"
  else
    read -r -p "Register the Obsidian MCP server? [y/N] " REGISTER_OBSIDIAN
    case "$REGISTER_OBSIDIAN" in
      y|Y|yes|Yes|YES)
        read -rs -p "Obsidian API key: " OBSIDIAN_API_KEY
        printf '\n'
        if claude mcp add --scope user --transport http obsidian https://127.0.0.1:27124/mcp --header "Authorization: Bearer $OBSIDIAN_API_KEY"; then
          echo "    Obsidian MCP registered."
          echo "    Note: enable Obsidian's \"Local REST API with MCP\" plugin in Obsidian."
          echo "    Note: trust its self-signed certificate by adding NODE_EXTRA_CA_CERTS (path to the exported cert) to the env block of $SETTINGS_JSON."
          echo "      openssl s_client -showcerts -connect 127.0.0.1:27124 </dev/null 2>/dev/null | openssl x509 -outform PEM > ~/.claude/obsidian-rest-api.crt"
          OBSIDIAN_NOTE="registered"
        else
          echo "    warning: could not register the Obsidian MCP; continuing" >&2
          OBSIDIAN_NOTE="registration failed"
        fi
        unset OBSIDIAN_API_KEY
        ;;
      *)
        OBSIDIAN_NOTE="registration skipped (declined)"
        ;;
    esac
  fi
fi

echo ""
echo "Done. Restart Claude Code (or start a new session) to pick up the plugin, hooks and agents."
echo "Note: the companion plugins (codex, ponytail, karpathy) were installed; restart Claude Code to load them."
echo "Note: the luna-lane and astra-lead skills and the codex-peer agent need the OpenAI Codex CLI installed and authenticated (npm i -g @openai/codex, then: codex login)."
echo "Note: the grok-lane and grok-research skills need the Grok CLI installed and authenticated: https://x.ai/cli (then run: grok login)."
echo "Note: the grok lanes call the grok binary by its literal absolute path, so they need a Bash permission rule for that path. Add this to permissions.allow in $HOME/.claude/settings.json (or via /permissions):"
echo "  Bash($HOME/.grok/bin/grok:*)"
echo "Note: the doctrine assumes the session runs Fable 5.1 at effort high. If it isn't, switch with /model."
echo "Note: Obsidian MCP $OBSIDIAN_NOTE."
