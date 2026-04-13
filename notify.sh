#!/bin/bash
# Claude Code notification hook for macOS
# Sends native notifications with tmux session/window context.
#
# Usage: Called by Claude Code hooks with JSON on stdin.
#   notify.sh needs_input        — Claude needs you to approve something
#   notify.sh done               — Claude finished and is idle
#   notify.sh __alerter_worker   — internal helper for detached alerter handling

set -euo pipefail

CCNOTIFS_TMP="/tmp/ccnotifs"

capture_pane_snapshot() {
    [ -n "${TMUX_BIN:-}" ] || return 0
    [ -n "${TMUX_PANE:-}" ] || return 0
    "$TMUX_BIN" capture-pane -p -e -J -t "$TMUX_PANE" -S -120 2>/dev/null || echo ""
}

strip_ansi() {
    perl -pe 's/\e\[[0-9;?]*[ -\/]*[@-~]//g; s/\r//g'
}

extract_candidate_options() {
    # Only extract the last contiguous block of numbered options from the
    # bottom of the pane snapshot.  This avoids picking up numbered items
    # from Claude's response text above the permission prompt.
    printf '%s\n' "$1" | strip_ansi | tail -r | awk '
        /^[[:space:]]*[^0-9]*[0-9]+\.[[:space:]]+/ { found=1; print; next }
        /^[[:space:]]*$/ { if (!found) next; else exit }
        { if (found) exit }
    ' | tail -r | sed -nE 's/^[[:space:]]*[^0-9]*([0-9]+)\.[[:space:]]+(.*)$/\1\t\2/p'
}

build_action_choices() {
    local options_text="$1"
    local number=""
    local text=""
    local label=""
    local max_len=50

    while IFS=$'\t' read -r number text; do
        [ -n "$number" ] || continue
        text=$(printf '%s' "$text" | tr ',' ';' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')
        if [ ${#text} -gt $max_len ]; then
            text="${text:0:$((max_len - 3))}..."
        fi
        label="${number}: ${text}"
        printf '%s\t%s\n' "$number" "$label"
    done <<< "$options_text"
}

action_csv_from_choices() {
    local choices_text="$1"
    local csv=""
    local number=""
    local label=""

    while IFS=$'\t' read -r number label; do
        [ -n "$label" ] || continue
        if [ -n "$csv" ]; then
            csv="${csv},${label}"
        else
            csv="$label"
        fi
    done <<< "$choices_text"

    printf '%s' "$csv"
}

choice_number_from_result() {
    local result="$1"
    local choices_text="$2"
    local number=""
    local label=""

    while IFS=$'\t' read -r number label; do
        [ -n "$label" ] || continue
        if [ "$label" = "$result" ]; then
            printf '%s' "$number"
            return 0
        fi
    done <<< "$choices_text"

    return 1
}

tmux_run() {
    [ -n "${CCN_TMUX_BIN:-}" ] || return 1

    if [ -n "${CCN_TMUX_SOCKET:-}" ]; then
        "$CCN_TMUX_BIN" -S "$CCN_TMUX_SOCKET" "$@" 2>/dev/null
    else
        "$CCN_TMUX_BIN" "$@" 2>/dev/null
    fi
}

teleport() {
    if [ -n "${CCN_TERM_BUNDLE_ID:-}" ]; then
        open -b "$CCN_TERM_BUNDLE_ID"
    fi
    if [ -n "${CCN_TMUX_BIN:-}" ] && [ -n "${CCN_TMUX_PANE:-}" ] && [ -n "${CCN_SESSION:-}" ] && [ -n "${CCN_WIN_INDEX:-}" ]; then
        tmux_run switch-client -t "$CCN_SESSION"
        tmux_run select-window -t "${CCN_SESSION}:${CCN_WIN_INDEX}"
        tmux_run select-pane -t "$CCN_TMUX_PANE"
    fi
}

run_alerter_worker() {
    local alert_args=()
    local result=""
    local action_csv=""
    local selected_number=""

    [ -n "${CCN_ALERTER_BIN:-}" ] || exit 0

    alert_args=(--title "${CCN_TITLE:-}" --message "${CCN_BODY:-}")
    [ -n "${CCN_SUBTITLE:-}" ] && alert_args+=(--subtitle "$CCN_SUBTITLE")
    alert_args+=(--timeout 120 --close-label "Dismiss")
    [ -n "${CCN_ICON_FILE:-}" ] && [ -f "${CCN_ICON_FILE:-}" ] && alert_args+=(--app-icon "$CCN_ICON_FILE")
    if [ -n "${CCN_ACTION_CHOICES:-}" ]; then
        action_csv=$(action_csv_from_choices "$CCN_ACTION_CHOICES")
        [ -n "$action_csv" ] && alert_args+=(--actions "$action_csv")
    elif [ "${CCN_NOTIFY_TYPE:-}" = "needs_input" ]; then
        alert_args+=(--actions "Approve")
    else
        alert_args+=(--actions "Open")
    fi

    result=$("$CCN_ALERTER_BIN" "${alert_args[@]}" 2>/dev/null || echo "")

    if [ -n "${CCN_ACTION_CHOICES:-}" ]; then
        selected_number=$(choice_number_from_result "$result" "$CCN_ACTION_CHOICES" || echo "")
        if [ -n "$selected_number" ] && [ -n "${CCN_TMUX_BIN:-}" ] && [ -n "${CCN_TMUX_PANE:-}" ]; then
            tmux_run send-keys -t "$CCN_TMUX_PANE" -l "$selected_number"
            exit 0
        fi
    fi

    case "$result" in
        "Approve")
            if [ -n "${CCN_TMUX_BIN:-}" ] && [ -n "${CCN_TMUX_PANE:-}" ]; then
                tmux_run send-keys -t "$CCN_TMUX_PANE" Enter
            fi
            ;;
        "@CONTENTCLICKED"|""|"Open")
            teleport
            ;;
        *)
            # Dismiss, @TIMEOUT, @CLOSED, etc. — do nothing
            ;;
    esac
}

if [ "${1:-}" = "__alerter_worker" ]; then
    run_alerter_worker
    exit 0
fi

NOTIFY_TYPE="${1:-done}"

# Read hook JSON from stdin (Claude Code pipes event data)
INPUT=$(cat)

# --- Claude Code session name (from /rename command) ---
# Session files in ~/.claude/sessions/ are named by the Claude process PID.
# Walk up the process tree to find which PID matches a session file.
SESSION_NAME=""
_pid=$$
while [ "$_pid" -gt 1 ] 2>/dev/null; do
    if [ -f "$HOME/.claude/sessions/${_pid}.json" ]; then
        SESSION_NAME=$(jq -r '.name // empty' "$HOME/.claude/sessions/${_pid}.json" 2>/dev/null || echo "")
        break
    fi
    _pid=$(ps -o ppid= -p "$_pid" 2>/dev/null | tr -d ' ')
    [ -z "$_pid" ] && break
done

# --- Skip notification if user is already viewing this session ---
if [ -n "${TMUX:-}" ] && [ -n "${TMUX_PANE:-}" ]; then
    SESSION_ATTACHED=$(tmux display-message -t "$TMUX_PANE" -p '#{session_attached}' 2>/dev/null || echo "0")
    PANE_ACTIVE=$(tmux display-message -t "$TMUX_PANE" -p '#{pane_active}' 2>/dev/null || echo "0")
    WINDOW_ACTIVE=$(tmux display-message -t "$TMUX_PANE" -p '#{window_active}' 2>/dev/null || echo "0")
    if [ "$SESSION_ATTACHED" != "0" ] && [ "$PANE_ACTIVE" = "1" ] && [ "$WINDOW_ACTIVE" = "1" ]; then
        FRONTMOST=$(osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true' 2>/dev/null || echo "")
        FRONTMOST_LOWER=$(echo "$FRONTMOST" | tr '[:upper:]' '[:lower:]')
        case "$FRONTMOST_LOWER" in
            terminal|iterm2|alacritty|kitty|wezterm|ghostty)
                exit 0
                ;;
        esac
    fi
fi

# --- tmux context (session, window number, window name) ---
TMUX_INFO=""
if [ -n "${TMUX:-}" ] && [ -n "${TMUX_PANE:-}" ]; then
    SESSION=$(tmux display-message -t "$TMUX_PANE" -p '#S' 2>/dev/null || echo "")
    WIN_INDEX=$(tmux display-message -t "$TMUX_PANE" -p '#I' 2>/dev/null || echo "")
    WINDOW=$(tmux display-message -t "$TMUX_PANE" -p '#W' 2>/dev/null || echo "")
    if [ -n "$SESSION" ]; then
        TMUX_INFO="${SESSION}"
        if [ -n "$WIN_INDEX" ] && [ -n "$WINDOW" ]; then
            TMUX_INFO="${TMUX_INFO} w${WIN_INDEX} > ${WINDOW}"
        elif [ -n "$WINDOW" ]; then
            TMUX_INFO="${TMUX_INFO} > ${WINDOW}"
        fi
    fi
fi

# --- Read stashed tool info (set by PreToolUse hook) ---
TOOL_DISPLAY=""
if [ "$NOTIFY_TYPE" = "needs_input" ] && [ -n "${TMUX_PANE:-}" ]; then
    PANE_ID="${TMUX_PANE#%}"
    STASH_FILE="${CCNOTIFS_TMP}/cmd_${PANE_ID}"
    if [ -f "$STASH_FILE" ]; then
        STASH_CONTENT=$(cat "$STASH_FILE" 2>/dev/null || echo "")
        STASH_TOOL=$(echo "$STASH_CONTENT" | cut -f1)
        STASH_CMD=$(echo "$STASH_CONTENT" | cut -f2-)
        if [ -n "$STASH_TOOL" ] && [ -n "$STASH_CMD" ]; then
            # Truncate command for notification display
            MAX_CMD_LEN=60
            if [ ${#STASH_CMD} -gt $MAX_CMD_LEN ]; then
                STASH_CMD="${STASH_CMD:0:$((MAX_CMD_LEN - 3))}..."
            fi
            TOOL_DISPLAY="${STASH_TOOL}: ${STASH_CMD}"
        elif [ -n "$STASH_TOOL" ]; then
            TOOL_DISPLAY="${STASH_TOOL}"
        fi
    fi
fi

# --- Notification type ---
if [ "$NOTIFY_TYPE" = "needs_input" ]; then
    TITLE="Claude Code — Needs Input"
    if [ -n "$TOOL_DISPLAY" ]; then
        BODY="$TOOL_DISPLAY"
    else
        BODY="Claude is waiting for your input"
    fi
    SOUND="Ping"
else
    TITLE="Claude Code — Done"
    BODY="Claude has finished and is awaiting further instructions"
    SOUND="Glass"
fi

# --- Click-to-focus: detect terminal bundle ID ---
# __CFBundleIdentifier is set by macOS for GUI apps — it's already the bundle ID.
# Falls back to mapping TERM_PROGRAM for non-GUI-launched terminals.
TERM_BUNDLE_ID="${__CFBundleIdentifier:-}"
if [ -z "$TERM_BUNDLE_ID" ]; then
    TERM_PROG="${TERM_PROGRAM:-}"
    if [ "$TERM_PROG" = "tmux" ] && [ -n "${TMUX:-}" ]; then
        TERM_PROG=$(tmux show-environment TERM_PROGRAM 2>/dev/null | sed 's/^TERM_PROGRAM=//' || echo "")
    fi
    case "$TERM_PROG" in
        Apple_Terminal) TERM_BUNDLE_ID="com.apple.Terminal" ;;
        iTerm.app)     TERM_BUNDLE_ID="com.googlecode.iterm2" ;;
        ghostty)       TERM_BUNDLE_ID="com.mitchellh.ghostty" ;;
        Alacritty)     TERM_BUNDLE_ID="org.alacritty" ;;
        WezTerm)       TERM_BUNDLE_ID="com.github.wez.wezterm" ;;
        kitty)         TERM_BUNDLE_ID="net.kovidgoyal.kitty" ;;
    esac
fi
TMUX_BIN=$(command -v tmux 2>/dev/null || echo "")
CANDIDATE_OPTIONS=""
ACTION_CHOICES=""

if [ "$NOTIFY_TYPE" = "needs_input" ]; then
    PANE_SNAPSHOT=$(capture_pane_snapshot)
    if [ -n "$PANE_SNAPSHOT" ]; then
        CANDIDATE_OPTIONS=$(extract_candidate_options "$PANE_SNAPSHOT")
        if [ -n "$CANDIDATE_OPTIONS" ]; then
            ACTION_CHOICES=$(build_action_choices "$CANDIDATE_OPTIONS")
        fi
    fi
fi

# --- Project name from cwd ---
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || echo "")
PROJECT=""
if [ -n "$CWD" ]; then
    PROJECT=$(basename "$CWD")
fi

# --- Subtitle ---
SUBTITLE=""
if [ -n "$TMUX_INFO" ] && [ -n "$PROJECT" ]; then
    SUBTITLE="${TMUX_INFO} · ${PROJECT}"
elif [ -n "$TMUX_INFO" ]; then
    SUBTITLE="${TMUX_INFO}"
elif [ -n "$PROJECT" ]; then
    SUBTITLE="${PROJECT}"
fi

# Append session name to subtitle
if [ -n "$SESSION_NAME" ]; then
    if [ -n "$SUBTITLE" ]; then
        SUBTITLE="${SUBTITLE} · ${SESSION_NAME}"
    else
        SUBTITLE="${SESSION_NAME}"
    fi
fi

# --- Send notification ---
# For both notification types: alerter > osascript
ALERTER_BIN=$(command -v alerter 2>/dev/null || echo "")
ICON_FILE="$HOME/.claude/hooks/clawd-mascot-notif-icon.png"

if [ -n "$ALERTER_BIN" ]; then
    env \
        CCN_ALERTER_BIN="$ALERTER_BIN" \
        CCN_NOTIFY_TYPE="$NOTIFY_TYPE" \
        CCN_TITLE="$TITLE" \
        CCN_BODY="$BODY" \
        CCN_SUBTITLE="$SUBTITLE" \
        CCN_ACTION_CHOICES="$ACTION_CHOICES" \
        CCN_ICON_FILE="$ICON_FILE" \
        CCN_TMUX_PANE="${TMUX_PANE:-}" \
        CCN_TMUX_SOCKET="${TMUX:+${TMUX%%,*}}" \
        CCN_TERM_BUNDLE_ID="${TERM_BUNDLE_ID:-}" \
        CCN_TMUX_BIN="${TMUX_BIN:-}" \
        CCN_SESSION="${SESSION:-}" \
        CCN_WIN_INDEX="${WIN_INDEX:-}" \
        nohup "$0" __alerter_worker >/dev/null 2>&1 < /dev/null &
else
    # Fallback: osascript (shows Script Editor icon)
    TITLE_ESC="${TITLE//\"/\\\"}"
    BODY_ESC="${BODY//\"/\\\"}"
    if [ -n "$SUBTITLE" ]; then
        SUBTITLE_ESC="${SUBTITLE//\"/\\\"}"
        osascript -e "display notification \"${BODY_ESC}\" with title \"${TITLE_ESC}\" subtitle \"${SUBTITLE_ESC}\" sound name \"${SOUND}\""
    else
        osascript -e "display notification \"${BODY_ESC}\" with title \"${TITLE_ESC}\" sound name \"${SOUND}\""
    fi
fi

# Play sound via afplay (routes through system audio, capturable by BlackHole etc.)
SOUND_FILE="/System/Library/Sounds/${SOUND}.aiff"
if [ -f "$SOUND_FILE" ]; then
    nohup afplay "$SOUND_FILE" >/dev/null 2>&1 < /dev/null &
fi
