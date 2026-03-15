#!/bin/bash
# Install ccnotifs
# Downloads the hook scripts and icon from GitHub and prints the required hooks config.
#
# Run directly: curl -fsSL https://raw.githubusercontent.com/polyphilz/ccnotifs/main/install.sh | bash

set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/polyphilz/ccnotifs/main"
HOOKS_DIR="$HOME/.claude/hooks"

echo "Installing ccnotifs..."

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
