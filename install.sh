#!/bin/bash
# Installs Claude Code statusline: copies the script and configures Claude Code settings.
#
# Two install modes:
#   LOCAL  — run from a cloned repo:  ./install.sh
#   REMOTE — via curl one-liner:      curl -fsSL <url>/install.sh | bash

set -euo pipefail

# ── Constants ─────────────────────────────────────────────────────────────────
if [ -n "${SUDO_USER:-}" ]; then
    HOME="$(eval echo "~$SUDO_USER")"
fi
GITHUB_RAW="https://raw.githubusercontent.com/sholub-dev/cc-setup/master"
INSTALL_DIR="$HOME/.claude/extensions/cc-setup"

# ── Detect install mode ──────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo "")"

if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/statusline.sh" ]; then
    MODE="local"
    REPO_DIR="$SCRIPT_DIR"
    echo "Detected local repo at $REPO_DIR"
else
    MODE="remote"
    echo "Remote install — downloading files to $INSTALL_DIR"
fi

# ── Pre-flight checks ────────────────────────────────────────────────────────
ERRORS=0

if ! command -v jq &>/dev/null; then
    if command -v brew &>/dev/null; then
        echo "⚠ jq not found — installing via Homebrew..."
        brew install jq
        echo "✓ jq installed"
    else
        echo "✗ jq not found and Homebrew not available"
        echo "  Install: brew install jq  (or visit https://jqlang.github.io/jq/)"
        ERRORS=$((ERRORS + 1))
    fi
else
    echo "✓ jq found"
fi

if [ "$ERRORS" -gt 0 ]; then
    echo ""
    echo "Fix the above issues and re-run the installer."
    exit 1
fi

# ── Install ──────────────────────────────────────────────────────────────────
echo ""

mkdir -p "$INSTALL_DIR"

if [ "$MODE" = "remote" ]; then
    echo "Downloading files..."
    if curl -fsSL "$GITHUB_RAW/statusline.sh" > "$INSTALL_DIR/statusline.sh"; then
        echo "  ✓ statusline.sh"
    else
        echo "  ✗ Failed to download statusline.sh"
        exit 1
    fi
elif [ "$MODE" = "local" ]; then
    cp "$REPO_DIR/statusline.sh" "$INSTALL_DIR/"
    echo "✓ Copied statusline.sh to $INSTALL_DIR"
fi

chmod +x "$INSTALL_DIR/statusline.sh"
echo "✓ Made statusline.sh executable"

# Symlink statusline.sh into ~/.claude/
ln -sf "$INSTALL_DIR/statusline.sh" "$HOME/.claude/statusline.sh"
echo "✓ Symlinked statusline.sh → ~/.claude/statusline.sh"

# Configure Claude Code settings
SETTINGS="$HOME/.claude/settings.json"
if [ -f "$SETTINGS" ]; then
    TMP=$(mktemp)
    jq '.statusLine = {"type":"command","command":"~/.claude/statusline.sh","padding":0}' "$SETTINGS" > "$TMP" && mv "$TMP" "$SETTINGS"
    echo "✓ Updated Claude Code settings"
else
    mkdir -p "$HOME/.claude"
    cat > "$SETTINGS" <<'SETTINGS_JSON'
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh",
    "padding": 0
  }
}
SETTINGS_JSON
    echo "✓ Created Claude Code settings"
fi

# ── Post-install verification ────────────────────────────────────────────────
echo ""
echo "Verification:"
PASS=0
FAIL=0

# statusline.sh is executable
if [ -x "$INSTALL_DIR/statusline.sh" ]; then
    echo "  ✓ statusline.sh is executable"
    PASS=$((PASS + 1))
else
    echo "  ✗ statusline.sh is not executable"
    FAIL=$((FAIL + 1))
fi

# settings.json contains statusLine
if jq -e '.statusLine' "$SETTINGS" >/dev/null 2>&1; then
    echo "  ✓ settings.json contains statusLine config"
    PASS=$((PASS + 1))
else
    echo "  ✗ settings.json missing statusLine config"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "$PASS passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
    echo "Some checks failed — review the output above."
    exit 1
fi

echo ""
echo "Done! Open a Claude Code session — you should see the statusline."
