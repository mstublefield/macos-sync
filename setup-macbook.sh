#!/bin/zsh
# setup-macbook.sh — One-time setup for MacBook Air to sync from Mac Studio
# Run this after cloning the repo: ~/Development/studio-sync/setup-macbook.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SSH_KEY="$HOME/.ssh/mac_studio_sync"
STUDIO_HOST="your-primary-mac.local"
STUDIO_USER="YOUR_USERNAME"
PLIST_SOURCE="$SCRIPT_DIR/studio-sync.plist"
PLIST_TARGET="$HOME/Library/LaunchAgents/com.YOUR_USERNAME.studio-sync.plist"

echo "============================================"
echo "  Mac Studio Sync — MacBook Setup"
echo "============================================"
echo ""

# ── Step 1: SSH Key ────────────────────────────────────────────
echo "Step 1: SSH Key Setup"
echo "─────────────────────"

if [ -f "$SSH_KEY" ]; then
    echo "  SSH key already exists at $SSH_KEY"
else
    echo "  Generating SSH key..."
    mkdir -p "$HOME/.ssh"
    ssh-keygen -t ed25519 -f "$SSH_KEY" -N "" -C "macbook-studio-sync"
    echo "  Key generated at $SSH_KEY"
fi

# Add SSH config entry if not present
if ! grep -q "Host mac-studio" "$HOME/.ssh/config" 2>/dev/null; then
    echo "" >> "$HOME/.ssh/config"
    cat >> "$HOME/.ssh/config" << 'SSHCONFIG'

# Mac Studio sync connection
Host mac-studio
    HostName your-primary-mac.local
    User YOUR_USERNAME
    IdentityFile ~/.ssh/mac_studio_sync
SSHCONFIG
    chmod 600 "$HOME/.ssh/config"
    echo "  SSH config entry added"
else
    echo "  SSH config entry already exists"
fi

echo ""
echo "  Now we need to register your key with the Mac Studio."
echo "  Make sure the Mac Studio has Remote Login enabled:"
echo "    System Settings > General > Sharing > Remote Login > On"
echo ""
echo "  Press Enter when Remote Login is enabled, then enter your"
echo "  Mac Studio password when prompted..."
read -r

ssh-copy-id -i "$SSH_KEY.pub" "$STUDIO_USER@$STUDIO_HOST"

echo ""
echo "  Testing SSH connection..."
if ssh -o ConnectTimeout=5 -o BatchMode=yes mac-studio "echo 'Connection successful!'" 2>/dev/null; then
    echo "  SSH connection works!"
else
    echo "  WARNING: SSH connection test failed."
    echo "  You may need to troubleshoot before syncing will work."
    echo "  Try: ssh mac-studio"
    exit 1
fi

# ── Step 2: LaunchAgent ───────────────────────────────────────
echo ""
echo "Step 2: LaunchAgent Setup"
echo "─────────────────────────"

mkdir -p "$HOME/Library/LaunchAgents"

if [ -L "$PLIST_TARGET" ] || [ -f "$PLIST_TARGET" ]; then
    echo "  Removing existing LaunchAgent..."
    launchctl bootout "gui/$(id -u)/com.YOUR_USERNAME.studio-sync" 2>/dev/null || true
    rm -f "$PLIST_TARGET"
fi

ln -s "$PLIST_SOURCE" "$PLIST_TARGET"
echo "  Symlinked LaunchAgent"

launchctl bootstrap "gui/$(id -u)" "$PLIST_TARGET"
echo "  LaunchAgent loaded — sync will now run automatically"

# ── Step 3: Make sync script executable ───────────────────────
chmod +x "$SCRIPT_DIR/sync-from-studio.sh"

# ── Step 4: Initial sync ─────────────────────────────────────
echo ""
echo "Step 3: Initial Sync"
echo "────────────────────"
echo "  Running first sync now (this may take a while for ~/Development)..."
echo ""

"$SCRIPT_DIR/sync-from-studio.sh"

echo ""
echo "============================================"
echo "  Setup Complete!"
echo "============================================"
echo ""
echo "  Your MacBook will now automatically sync from the Mac Studio"
echo "  whenever you connect to your home network."
echo ""
echo "  Manual sync:  ~/Development/studio-sync/sync-from-studio.sh"
echo "  View logs:    cat ~/Library/Logs/studio-sync.log"
echo ""
