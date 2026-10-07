# cc-setup

A status line and skills for [Claude Code](https://docs.anthropic.com/en/docs/claude-code).

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

## Skills

### animate

Makes animated product videos, README GIFs and motion graphics in code. Each frame is a pure function of time, rendered in headless Chrome and encoded with ffmpeg. See [skills/animate/SKILL.md](skills/animate/SKILL.md).

### Setup

```bash
git clone https://github.com/sholub-dev/cc-setup.git
cp -R cc-setup/skills/animate ~/.claude/skills/
```
