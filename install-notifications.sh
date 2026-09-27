#!/bin/bash
# Installs Claude Code notifications: builds a native macOS notification app
# and configures Claude Code hooks to trigger it.
#
# Two install modes:
#   LOCAL  — run from a cloned repo:  ./install-notifications.sh
#   REMOTE — via curl one-liner:      curl -fsSL <url>/install-notifications.sh | bash

set -euo pipefail

# ── Constants ─────────────────────────────────────────────────────────────────
if [ -n "${SUDO_USER:-}" ]; then
    HOME="$(dscl . -read /Users/"$SUDO_USER" NFSHomeDirectory 2>/dev/null | awk '{print $2}')"
    HOME="${HOME:-/Users/$SUDO_USER}"
fi
GITHUB_RAW="https://raw.githubusercontent.com/sholub-dev/cc-setup/master"
INSTALL_DIR="$HOME/.claude/extensions/cc-notifications"
APP_DIR="$HOME/Applications/ClaudeNotify.app"

# ── Detect install mode ──────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo "")"

if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/ClaudeNotify.swift" ]; then
    MODE="local"
    REPO_DIR="$SCRIPT_DIR"
    echo "Detected local repo at $REPO_DIR"
else
    MODE="remote"
    echo "Remote install — downloading files to $INSTALL_DIR"
fi

# ── Pre-flight checks ────────────────────────────────────────────────────────
ERRORS=0

if ! command -v swiftc &>/dev/null; then
    echo "✗ swiftc not found"
    echo "  Install Xcode Command Line Tools: xcode-select --install"
    ERRORS=$((ERRORS + 1))
else
    echo "✓ swiftc found"
fi

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
    for f in ClaudeNotify.swift notify.sh dismiss.sh assets/AppIcon.icns; do
        target="$INSTALL_DIR/$(basename "$f")"
        if curl -fsSL "$GITHUB_RAW/$f" > "$target"; then
            echo "  ✓ $(basename "$f")"
        else
            echo "  ✗ Failed to download $f"
            exit 1
        fi
    done
elif [ "$MODE" = "local" ]; then
    cp "$REPO_DIR/ClaudeNotify.swift" "$INSTALL_DIR/"
    cp "$REPO_DIR/notify.sh" "$INSTALL_DIR/"
    cp "$REPO_DIR/dismiss.sh" "$INSTALL_DIR/"
    cp "$REPO_DIR/assets/AppIcon.icns" "$INSTALL_DIR/"
    echo "✓ Copied files to $INSTALL_DIR"
fi

chmod +x "$INSTALL_DIR/notify.sh" "$INSTALL_DIR/dismiss.sh"

# ── Build app bundle ────────────────────────────────────────────────────────
echo ""
echo "Building ClaudeNotify.app..."

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

# Write Info.plist
cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.claude-code.notify</string>
    <key>CFBundleName</key>
    <string>ClaudeNotify</string>
    <key>CFBundleExecutable</key>
    <string>ClaudeNotify</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSUserNotificationAlertStyle</key>
    <string>alert</string>
</dict>
</plist>
PLIST

# Copy icon
cp "$INSTALL_DIR/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"

# Compile
if swiftc "$INSTALL_DIR/ClaudeNotify.swift" -o "$APP_DIR/Contents/MacOS/ClaudeNotify" 2>&1; then
    echo "✓ Compiled ClaudeNotify"
else
    echo "✗ Compilation failed"
    exit 1
fi

# Sign
if codesign --force --sign - "$APP_DIR" 2>&1; then
    echo "✓ Signed app bundle"
else
    echo "✗ Code signing failed"
    exit 1
fi

# Register with Launch Services
if /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister "$APP_DIR" 2>&1; then
    echo "✓ Registered with Launch Services"
else
    echo "⚠ Launch Services registration failed (icon may not appear)"
fi

# ── Symlink scripts ────────────────────────────────────────────────────────
mkdir -p "$HOME/.claude/scripts"
ln -sf "$INSTALL_DIR/notify.sh" "$HOME/.claude/scripts/notify.sh"
ln -sf "$INSTALL_DIR/dismiss.sh" "$HOME/.claude/scripts/dismiss.sh"
echo "✓ Symlinked notify.sh → ~/.claude/scripts/notify.sh"
echo "✓ Symlinked dismiss.sh → ~/.claude/scripts/dismiss.sh"

# ── Configure Claude Code hooks ─────────────────────────────────────────────
SETTINGS="$HOME/.claude/settings.json"

HOOKS_FRAGMENT='{
  "Stop": [
    {
      "matcher": "",
      "hooks": [
        {
          "type": "command",
          "command": "~/.claude/scripts/notify.sh"
        }
      ]
    }
  ],
  "PermissionRequest": [
    {
      "matcher": "",
      "hooks": [
        {
          "type": "command",
          "command": "~/.claude/scripts/notify.sh"
        }
      ]
    }
  ],
  "Elicitation": [
    {
      "matcher": "",
      "hooks": [
        {
          "type": "command",
          "command": "~/.claude/scripts/notify.sh"
        }
      ]
    }
  ],
  "UserPromptSubmit": [
    {
      "matcher": "",
      "hooks": [
        {
          "type": "command",
          "command": "~/.claude/scripts/dismiss.sh"
        }
      ]
    }
  ],
  "PostToolUse": [
    {
      "matcher": "",
      "hooks": [
        {
          "type": "command",
          "command": "~/.claude/scripts/dismiss.sh"
        }
      ]
    }
  ],
  "PreCompact": [
    {
      "matcher": "",
      "hooks": [
        {
          "type": "command",
          "command": "~/.claude/scripts/dismiss.sh"
        }
      ]
    }
  ],
  "PostCompact": [
    {
      "matcher": "",
      "hooks": [
        {
          "type": "command",
          "command": "~/.claude/scripts/notify.sh"
        }
      ]
    }
  ]
}'

if [ -f "$SETTINGS" ]; then
    TMP=$(mktemp)
    echo "$HOOKS_FRAGMENT" | jq -s --arg notify "~/.claude/scripts/notify.sh" --arg dismiss "~/.claude/scripts/dismiss.sh" '
        def dedup($key; $cmd; $new): ((.hooks[$key] // []) | map(select(.hooks | all(.command != $cmd)))) + $new[$key];
        .[0] as $new | input |
        .hooks = (.hooks // {}) |
        .hooks.Stop = dedup("Stop"; $notify; $new) |
        .hooks.PermissionRequest = dedup("PermissionRequest"; $notify; $new) |
        .hooks.Elicitation = dedup("Elicitation"; $notify; $new) |
        .hooks.UserPromptSubmit = dedup("UserPromptSubmit"; $dismiss; $new) |
        .hooks.PostToolUse = dedup("PostToolUse"; $dismiss; $new) |
        .hooks.PreCompact = dedup("PreCompact"; $dismiss; $new) |
        .hooks.PostCompact = dedup("PostCompact"; $notify; $new)
    ' - "$SETTINGS" > "$TMP" && mv "$TMP" "$SETTINGS"
    echo "✓ Updated Claude Code hooks in settings.json"
else
    mkdir -p "$HOME/.claude"
    echo "$HOOKS_FRAGMENT" | jq '{hooks: .}' > "$SETTINGS"
    echo "✓ Created Claude Code settings with hooks"
fi

# ── Request notification permission ─────────────────────────────────────────
echo ""
echo "Requesting notification permission..."
"$APP_DIR/Contents/MacOS/ClaudeNotify" "Claude Code" "Notifications enabled" --sound 2>/dev/null || true

# ── Post-install verification ────────────────────────────────────────────────
echo ""
echo "Verification:"
PASS=0
FAIL=0

if [ -x "$APP_DIR/Contents/MacOS/ClaudeNotify" ]; then
    echo "  ✓ ClaudeNotify.app built"
    PASS=$((PASS + 1))
else
    echo "  ✗ ClaudeNotify.app not found"
    FAIL=$((FAIL + 1))
fi

if [ -x "$INSTALL_DIR/notify.sh" ]; then
    echo "  ✓ notify.sh is executable"
    PASS=$((PASS + 1))
else
    echo "  ✗ notify.sh is not executable"
    FAIL=$((FAIL + 1))
fi

if jq -e '.hooks.Stop' "$SETTINGS" >/dev/null 2>&1; then
    echo "  ✓ settings.json contains hooks"
    PASS=$((PASS + 1))
else
    echo "  ✗ settings.json missing hooks"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "$PASS passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
    echo "Some checks failed — review the output above."
    exit 1
fi

echo ""
echo "Done! If prompted, allow notifications for ClaudeNotify in System Settings."
echo "Restart Claude Code to activate the hooks."
