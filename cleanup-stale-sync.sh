#!/bin/zsh -f
# cleanup-stale-sync.sh — Remove previously-synced junk that's now excluded
# Run once on the MacBook after updating the sync script
# Uses absolute paths to avoid any PATH/shell config issues

/bin/echo "Cleaning up stale synced data..."
/bin/echo ""

FREED=0

remove_if_exists() {
    local path="$1"
    if [ -e "$path" ]; then
        local size=$(/usr/bin/du -sh "$path" 2>/dev/null | /usr/bin/cut -f1)
        /bin/rm -rf "$path"
        /bin/echo "  Removed: $path ($size)"
        FREED=$((FREED + 1))
    fi
}

# ── Claude Desktop runtime junk ───────────────────────────────
/bin/echo "Claude Desktop (~/Library/Application Support/Claude/):"

remove_if_exists "$HOME/Library/Application Support/Claude/vm_bundles"
remove_if_exists "$HOME/Library/Application Support/Claude/Cache"
remove_if_exists "$HOME/Library/Application Support/Claude/Code Cache"
remove_if_exists "$HOME/Library/Application Support/Claude/claude-code-vm"
remove_if_exists "$HOME/Library/Application Support/Claude/claude-code"
remove_if_exists "$HOME/Library/Application Support/Claude/local-agent-mode-sessions"
remove_if_exists "$HOME/Library/Application Support/Claude/GPUCache"
remove_if_exists "$HOME/Library/Application Support/Claude/DawnWebGPUCache"
remove_if_exists "$HOME/Library/Application Support/Claude/DawnGraphiteCache"
remove_if_exists "$HOME/Library/Application Support/Claude/blob_storage"
remove_if_exists "$HOME/Library/Application Support/Claude/Session Storage"
remove_if_exists "$HOME/Library/Application Support/Claude/Local Storage"
remove_if_exists "$HOME/Library/Application Support/Claude/IndexedDB"
remove_if_exists "$HOME/Library/Application Support/Claude/Crashpad"
remove_if_exists "$HOME/Library/Application Support/Claude/sentry"
remove_if_exists "$HOME/Library/Application Support/Claude/shared_proto_db"
remove_if_exists "$HOME/Library/Application Support/Claude/SharedStorage"
remove_if_exists "$HOME/Library/Application Support/Claude/SharedStorage-wal"
remove_if_exists "$HOME/Library/Application Support/Claude/WebStorage"
remove_if_exists "$HOME/Library/Application Support/Claude/Shared Dictionary"
remove_if_exists "$HOME/Library/Application Support/Claude/fcache"
remove_if_exists "$HOME/Library/Application Support/Claude/ant-did"
remove_if_exists "$HOME/Library/Application Support/Claude/Conversions"
remove_if_exists "$HOME/Library/Application Support/Claude/Conversions-journal"
remove_if_exists "$HOME/Library/Application Support/Claude/Cookies"
remove_if_exists "$HOME/Library/Application Support/Claude/Cookies-journal"
remove_if_exists "$HOME/Library/Application Support/Claude/DIPS"
remove_if_exists "$HOME/Library/Application Support/Claude/DIPS-wal"
remove_if_exists "$HOME/Library/Application Support/Claude/Trust Tokens"
remove_if_exists "$HOME/Library/Application Support/Claude/Trust Tokens-journal"
remove_if_exists "$HOME/Library/Application Support/Claude/Network Persistent State"
remove_if_exists "$HOME/Library/Application Support/Claude/Preferences"
remove_if_exists "$HOME/Library/Application Support/Claude/TransportSecurity"
remove_if_exists "$HOME/Library/Application Support/Claude/VideoDecodeStats"

# ── Claude Code caches ────────────────────────────────────────
/bin/echo ""
/bin/echo "Claude Code (~/.claude/):"

remove_if_exists "$HOME/.claude/debug"
remove_if_exists "$HOME/.claude/telemetry"
remove_if_exists "$HOME/.claude/paste-cache"
remove_if_exists "$HOME/.claude/shell-snapshots"
remove_if_exists "$HOME/.claude/file-history"
remove_if_exists "$HOME/.claude/session-env"
remove_if_exists "$HOME/.claude/cache"
remove_if_exists "$HOME/.claude/statsig-cache"
remove_if_exists "$HOME/.claude/statsig"

# Remove session transcript directories inside each project
/bin/echo ""
/bin/echo "Claude Code session transcripts (~/.claude/projects/*/sessions/):"
/usr/bin/find "$HOME/.claude/projects" -type d -name "sessions" 2>/dev/null | while read -r dir; do
    remove_if_exists "$dir"
done

# ── Summary ───────────────────────────────────────────────────
/bin/echo ""
if [ "$FREED" -gt 0 ]; then
    /bin/echo "Done — removed $FREED items. Claude Desktop and Claude Code will"
    /bin/echo "regenerate what they need locally."
else
    /bin/echo "Nothing to clean up — already clean."
fi
