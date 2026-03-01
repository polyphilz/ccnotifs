<div align="center">

<img src="assets/clawd-shimmer.gif" width="200" alt="Clawd">
<h1>ccnotifs</h1>

Native macOS notifications for <a href="https://docs.anthropic.com/en/docs/claude-code" target="_blank">Claude Code</a>.
Know when Claude finishes or needs your input. Click notifications to bring into focus the tmux pane that spawned the notification.

<a href="https://www.apple.com/macos/" target="_blank"><img src="https://img.shields.io/badge/macOS-000000?style=flat&logo=apple&logoColor=white" alt="macOS"></a>
<a href="notify.sh"><img src="https://img.shields.io/badge/Shell_Script-4EAA25?style=flat&logo=gnu-bash&logoColor=white" alt="Shell Script"></a>
<a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License: MIT"></a>

<br>

![demo](assets/demo.gif)

</div>

## Features

- **Two notification types** — "Done" when Claude finishes, "Needs Input" when Claude needs approval
- **Teleport** — Click a notification to teleport back to the right terminal, tmux session, window, and pane
- **tmux context** — Shows session name, window number, and window name
- **Project name** — Displays the current project directory
- **Suppression** — Skips notifications when you're already viewing the Claude Code session
- **Custom icon** — Use your own app icon instead of the default Script Editor icon
- **Sound** — Plays a sound per notification type

```
Claude Code — Done
myproject w3 > feature-branch · my-app
Claude has finished and is awaiting further instructions
```

## Quick Start

```bash
brew install jq                    # required
brew install terminal-notifier     # recommended — enables teleport and custom icon

curl -fsSL https://raw.githubusercontent.com/polyphilz/ccnotifs/main/install.sh | bash
```

The install script:
1. Downloads `notify.sh` into `~/.claude/hooks/`
2. If `terminal-notifier` is installed, downloads `icon.png` and builds a `ccnotifs.app` with a custom icon
3. Prints the hooks config to add to your `settings.json`

## How it works

Claude Code's <a href="https://docs.anthropic.com/en/docs/claude-code/hooks" target="_blank">hooks system</a> runs shell commands on lifecycle events:

| Hook | Event | Notification |
|------|-------|-------------|
| `Stop` | Claude finishes responding | "Claude Code — Done" |
| `Notification` | Claude needs approval (permission prompt) | "Claude Code — Needs Input" |

The script reads JSON from stdin (provided by Claude Code), extracts the working directory, and queries tmux for session/window context. If you're already looking at the session in a supported terminal (Ghostty, iTerm2, Alacritty, kitty, WezTerm, Terminal), the notification is suppressed.

### Notification priority

The script tries these in order:

1. **`ccnotifs.app`** — custom icon + teleport, requires `terminal-notifier` + `icon.png` setup
2. **`terminal-notifier`** — teleport, no setup beyond `brew install`
3. **`osascript`** — zero dependencies, but no teleport support

### Teleport

When `terminal-notifier` is installed, clicking a notification brings you back to where Claude Code is running. It activates your terminal, switches to the correct tmux session, selects the right window, and focuses the exact pane.

Supported terminals: Terminal.app, iTerm2, Ghostty, Alacritty, kitty, WezTerm.

<details>
<summary><strong>Manual setup</strong></summary>

If you prefer not to use `install.sh`:

**1. Download the script:**

```bash
mkdir -p ~/.claude/hooks
curl -fsSL https://raw.githubusercontent.com/polyphilz/ccnotifs/main/notify.sh -o ~/.claude/hooks/notify.sh
chmod +x ~/.claude/hooks/notify.sh
```

**2. Add hooks to `~/.claude/settings.json`:**

```json
{
  "hooks": {
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
```

**3. Activate the hooks.**

Open the `/hooks` menu in Claude Code to review and accept the new hooks, or restart your session.

</details>

<details>
<summary><strong>Troubleshooting</strong></summary>

**Notifications don't appear when screen recording or mirroring:**
macOS suppresses banners during screen sharing as a privacy feature. Fix: System Settings > Notifications > "Allow notifications when mirroring or sharing the display" > Allow Notifications.

**Notifications show in Notification Center but not as banners:**
Check System Settings > Notifications > find "ccnotifs" (or "terminal-notifier") > set alert style to "Banners" or "Alerts".

**tmux info not showing:**
Make sure Claude Code is running inside a tmux session. The `$TMUX` and `$TMUX_PANE` environment variables must be set.

**Square brackets in subtitle cause it to disappear:**
Known `terminal-notifier` bug. The script avoids brackets by default.

</details>

## License

MIT
