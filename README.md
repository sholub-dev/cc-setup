# cc-setup

A status bar and native macOS notifications for [Claude Code](https://docs.anthropic.com/en/docs/claude-code).

---

## Statusline

![statusline](assets/statusline.png)

**Line 1** — model, project path, git branch, uncommitted changes

**Line 2** — Claude subscription usage limits (5-hour and 7-day windows) with reset countdowns, context window usage, session cost

### Prerequisites

- macOS
- `jq` on `$PATH`

### Setup

```bash
curl -fsSL https://raw.githubusercontent.com/sholub-dev/cc-setup/master/install.sh | bash
```

#### Developer install

```bash
git clone https://github.com/sholub-dev/cc-setup.git
cd cc-setup
./install.sh
```

### Troubleshooting

**Line 2 doesn't appear**
- Rate limit data is provided by Claude Code itself — ensure you're on a version that includes `rate_limits` in statusline JSON input

### Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/sholub-dev/cc-setup/master/uninstall.sh | bash
```

---

## Notifications

Native macOS notifications when Claude Code needs your attention — visible on any screen, not just the terminal.

| Task complete / question | Permission prompt |
|---|---|
| ![complete](assets/notification-complete.png) | ![permission](assets/notification-permission.png) |

Shows the project name so you know which session needs you.

**Events covered:**

| Event | Notification |
|---|---|
| Task complete / question | `Claude Code ✅` |
| Permission prompt (Bash, file edit, etc.) | `Claude Code 🔄` |
| MCP server input request | `Claude Code 💬` |

**Smart lifecycle:**

- New notifications replace old ones for the same project (no stacking)
- Notifications auto-dismiss when you interact — approve a permission, send a message, or use any tool
- Duplicate notifications are debounced (5-second window for consecutive Stop events)

### Prerequisites

- macOS
- Swift compiler (`swiftc`) — included with Xcode Command Line Tools
- `jq` on `$PATH`

### Setup

```bash
curl -fsSL https://raw.githubusercontent.com/sholub-dev/cc-setup/master/install-notifications.sh | bash
```

On first run, macOS will ask you to allow notifications for **ClaudeNotify** — click Allow. Restart Claude Code to activate the hooks.

#### Developer install

```bash
git clone https://github.com/sholub-dev/cc-setup.git
cd cc-setup
./install-notifications.sh
```

### Configuration

Edit `~/.claude/scripts/notify.sh` to customize:

- **Disable sound** — remove `--sound` from the last line
- **Change debounce** — adjust the `5` (seconds) in the debounce check

### Roadmap

- Interactive notification actions (e.g. text-to-speech playback button)

### Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/sholub-dev/cc-setup/master/uninstall-notifications.sh | bash
```

---

## Skills

### animate

Makes animated product videos, README GIFs and motion graphics in code. Each frame is a pure function of time, rendered in headless Chrome and encoded with ffmpeg. See [skills/animate/SKILL.md](skills/animate/SKILL.md).

### Setup

```bash
git clone https://github.com/sholub-dev/cc-setup.git
cp -R cc-setup/skills/animate ~/.claude/skills/
```
