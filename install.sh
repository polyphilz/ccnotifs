#!/bin/bash
# Install ccnotifs
# Downloads the hook scripts and icon from GitHub and prints the required hooks config.
#
# Run directly: curl -fsSL https://raw.githubusercontent.com/polyphilz/ccnotifs/main/install.sh | bash
# Override the ref with CCNOTIFS_REF=vX.Y.Z or CCNOTIFS_REF=main.

set -euo pipefail

GITHUB_REPO="polyphilz/ccnotifs"
HOOKS_DIR="$HOME/.claude/hooks"

normalize_ref() {
    local ref="$1"

    if [[ "$ref" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        printf 'v%s' "$ref"
    else
        printf '%s' "$ref"
    fi
}

resolve_repo_ref() {
    local latest_url=""
    local latest_ref=""

    if [ -n "${CCNOTIFS_REF:-}" ]; then
        normalize_ref "$CCNOTIFS_REF"
        return 0
    fi

    latest_url=$(curl -fsSL --connect-timeout 5 --max-time 10 -o /dev/null -w '%{url_effective}' "https://github.com/${GITHUB_REPO}/releases/latest" 2>/dev/null || echo "")
    latest_ref=$(printf '%s' "$latest_url" | sed -nE 's#.*/tag/([^/?]+).*#\1#p')

    if [ -n "$latest_ref" ]; then
        printf '%s' "$latest_ref"
    else
        printf 'main'
    fi
}

REPO_REF="$(resolve_repo_ref)"
REPO_RAW="https://raw.githubusercontent.com/${GITHUB_REPO}/${REPO_REF}"

echo "Installing ccnotifs from ${REPO_REF}..."
if [ "$REPO_REF" = "main" ] && [ -z "${CCNOTIFS_REF:-}" ]; then
    echo "  No GitHub release found yet; falling back to main."
fi

# --- Download hook files ---
mkdir -p "$HOOKS_DIR"
curl -fsSL "$REPO_RAW/notify.sh" -o "$HOOKS_DIR/notify.sh"
chmod +x "$HOOKS_DIR/notify.sh"
echo "  Downloaded notify.sh -> $HOOKS_DIR/notify.sh"

curl -fsSL "$REPO_RAW/stash_command.sh" -o "$HOOKS_DIR/stash_command.sh"
chmod +x "$HOOKS_DIR/stash_command.sh"
echo "  Downloaded stash_command.sh -> $HOOKS_DIR/stash_command.sh"

# --- Icon used by alerter (optional) ---
if curl -fsSL "$REPO_RAW/clawd-mascot-notif-icon.png" -o "$HOOKS_DIR/clawd-mascot-notif-icon.png" 2>/dev/null; then
    echo "  Downloaded clawd-mascot-notif-icon.png -> $HOOKS_DIR/clawd-mascot-notif-icon.png"
else
    echo "  Could not download clawd-mascot-notif-icon.png — notifications will use alerter's default icon."
fi

# --- Print hooks config ---
echo ""
echo "  Install dependencies with:"
echo "    brew install jq"
echo "    brew install vjeantet/tap/alerter"

cat << 'HOOKS'

Add this to your ~/.claude/settings.json:

{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/stash_command.sh"
          }
        ]
      }
    ],
    "Notification": [
      {
        "matcher": "permission_prompt",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/notify.sh needs_input"
          }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/notify.sh done"
          }
        ]
      }
    ]
  }
}

Restart your Claude Code session to activate.
HOOKS

echo ""
echo "Done!"
