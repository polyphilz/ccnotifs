#!/bin/bash
# Stash the latest tool invocation for the notification hook to read.
# Called by PreToolUse hook — must be fast and never fail loudly.
set -euo pipefail

INPUT=$(cat)

# Only stash if we're in a tmux pane (needed to key the temp file)
[ -z "${TMUX_PANE:-}" ] && exit 0

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo "")
[ -z "$TOOL_NAME" ] && exit 0

# For Bash tools, stash the command. For other tools, stash the tool name + file path if available.
TOOL_CMD=""
case "$TOOL_NAME" in
    Bash)
        TOOL_CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")
        ;;
    Edit|Write|Read)
        TOOL_CMD=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || echo "")
        ;;
    *)
        TOOL_CMD=$(echo "$INPUT" | jq -r '.tool_input | keys[0] as $k | .[$k] // empty' 2>/dev/null || echo "")
        ;;
esac

# Write to a pane-specific temp file under /tmp/ccnotifs/
# TMUX_PANE is like %42, strip the % for a clean filename
PANE_ID="${TMUX_PANE#%}"
CCNOTIFS_TMP="/tmp/ccnotifs"
mkdir -p "$CCNOTIFS_TMP"
printf '%s\t%s' "$TOOL_NAME" "$TOOL_CMD" > "${CCNOTIFS_TMP}/cmd_${PANE_ID}"
