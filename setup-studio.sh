#!/bin/zsh
# setup-studio.sh — One-time setup for Mac Studio to pull from MacBook Air
# Run this once: ~/Development/studio-sync/setup-studio.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SSH_KEY="$HOME/.ssh/macbook_sync"
MACBOOK_USER="YOUR_USERNAME"

echo "============================================"
echo "  Studio Sync — Mac Studio Reverse Setup"
echo "============================================"
echo ""
echo "  This sets up SSH access so the Studio can"
echo "  pull newer files from the MacBook Air."
echo ""

# ── Step 1: Discover MacBook hostname ─────────────────────────
echo "Step 1: MacBook Discovery"
echo "─────────────────────────"
echo ""
echo "  Looking for MacBook on the network..."

# Try to find it via Bonjour
DISCOVERED_HOST=""
BONJOUR_HOSTS=$(/usr/bin/dns-sd -B _ssh._tcp local 2>/dev/null & PID=$!; sleep 3; kill $PID 2>/dev/null; wait $PID 2>/dev/null) || true

if echo "$BONJOUR_HOSTS" | grep -qi "macbook"; then
    DISCOVERED_HOST=$(echo "$BONJOUR_HOSTS" | grep -i "macbook" | awk '{print $NF}' | head -1)
    echo "  Found: $DISCOVERED_HOST"
fi

echo ""
if [ -n "$DISCOVERED_HOST" ]; then
    echo "  Detected MacBook hostname: ${DISCOVERED_HOST}.local"
    echo "  Press Enter to use this, or type a different hostname:"
else
    echo "  Could not auto-detect MacBook via Bonjour."
    echo "  Enter the MacBook's hostname (default: mac.local):"
fi

read -r USER_INPUT
if [ -n "$USER_INPUT" ]; then
    MACBOOK_HOSTNAME="$USER_INPUT"
elif [ -n "$DISCOVERED_HOST" ]; then
    MACBOOK_HOSTNAME="${DISCOVERED_HOST}.local"
else
    MACBOOK_HOSTNAME="mac.local"
    echo "  Defaulting to: mac.local"
fi

echo "  Using: $MACBOOK_HOSTNAME"

# ── Step 2: SSH Key ───────────────────────────────────────────
echo ""
echo "Step 2: SSH Key Setup"
echo "─────────────────────"

if [ -f "$SSH_KEY" ]; then
    echo "  SSH key already exists at $SSH_KEY"
else
    echo "  Generating SSH key..."
    mkdir -p "$HOME/.ssh"
    ssh-keygen -t ed25519 -f "$SSH_KEY" -N "" -C "studio-macbook-sync"
    echo "  Key generated at $SSH_KEY"
fi

# Add SSH config entry if not present
if ! grep -q "Host macbook" "$HOME/.ssh/config" 2>/dev/null; then
    mkdir -p "$HOME/.ssh"
    touch "$HOME/.ssh/config"
    cat >> "$HOME/.ssh/config" << SSHCONFIG

# MacBook Air reverse sync connection
Host macbook
    HostName $MACBOOK_HOSTNAME
    User $MACBOOK_USER
    IdentityFile ~/.ssh/macbook_sync
SSHCONFIG
    chmod 600 "$HOME/.ssh/config"
    echo "  SSH config entry added (Host: macbook)"
else
    echo "  SSH config entry already exists"
fi

# ── Step 3: Copy key to MacBook ──────────────────────────────
echo ""
echo "Step 3: Register Key with MacBook"
echo "──────────────────────────────────"
echo ""
echo "  Make sure the MacBook has Remote Login enabled:"
echo "    System Settings > General > Sharing > Remote Login > On"
echo ""
echo "  Press Enter when ready, then enter your MacBook password when prompted..."
read -r

ssh-copy-id -i "$SSH_KEY.pub" "$MACBOOK_USER@$MACBOOK_HOSTNAME"

echo ""
echo "  Testing SSH connection..."
if ssh -o ConnectTimeout=5 -o BatchMode=yes macbook "echo 'Connection successful!'" 2>/dev/null; then
    echo "  SSH connection works!"
else
    echo "  WARNING: SSH connection test failed."
    echo "  You may need to troubleshoot before reverse sync will work."
    echo "  Try: ssh macbook"
    exit 1
fi

# ── Step 4: Make scripts executable ──────────────────────────
chmod +x "$SCRIPT_DIR/pull-from-macbook.sh"

echo ""
echo "============================================"
echo "  Setup Complete!"
echo "============================================"
echo ""
echo "  You can now pull newer files from the MacBook:"
echo "    ~/Development/studio-sync/pull-from-macbook.sh"
echo ""
echo "  The MacBook's automatic sync will also push"
echo "  newer files to the Studio before pulling."
echo ""
