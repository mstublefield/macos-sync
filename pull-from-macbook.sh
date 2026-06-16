#!/bin/zsh -f
# pull-from-macbook.sh — Pull newer Development files from MacBook Air to this Mac Studio
# Run manually when you sit down at the Studio after working on the MacBook
# Uses --update (only copy newer files) and NO --delete (never removes Studio files)
# Uses absolute paths to avoid shell config / PATH issues

set -euo pipefail

# ── Configuration ──────────────────────────────────────────────
MACBOOK_HOST="mac-secondary"                   # SSH config alias (see ~/.ssh/config)
HOME_NETWORK_PREFIX="192.168.1"            # Only sync when on this subnet
LOG_FILE="$HOME/Library/Logs/studio-sync.log"
SCRIPT_DIR="$(cd "$(/usr/bin/dirname "$0")" && /bin/pwd)"
EXCLUDE_FILE="$SCRIPT_DIR/sync-exclude.txt"
LOCK_FILE="/tmp/studio-sync-reverse.lock"

# ── Helpers ────────────────────────────────────────────────────
log() { /bin/echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"; }

notify() {
    /usr/bin/osascript -e "display notification \"$1\" with title \"Studio Sync (Reverse)\"" 2>/dev/null || true
}

cleanup() {
    /bin/rm -f "$LOCK_FILE"
}
trap cleanup EXIT

# ── Preflight checks ──────────────────────────────────────────

# Prevent overlapping runs
if [ -f "$LOCK_FILE" ]; then
    LOCK_PID=$(/bin/cat "$LOCK_FILE" 2>/dev/null)
    if kill -0 "$LOCK_PID" 2>/dev/null; then
        log "SKIP-REV: Another reverse sync is already running (PID $LOCK_PID)"
        exit 0
    else
        log "INFO-REV: Stale lock file found, removing"
        /bin/rm -f "$LOCK_FILE"
    fi
fi
/bin/echo $$ > "$LOCK_FILE"

# Check if on home network
LOCAL_IP=$(/usr/sbin/ipconfig getifaddr en0 2>/dev/null || /usr/sbin/ipconfig getifaddr en1 2>/dev/null || /bin/echo "none")
if [[ "$LOCAL_IP" != ${HOME_NETWORK_PREFIX}* ]]; then
    log "SKIP-REV: Not on home network (IP: $LOCAL_IP)"
    exit 0
fi

# Check if MacBook is reachable via SSH
if ! /usr/bin/ssh -o ConnectTimeout=5 -o BatchMode=yes "$MACBOOK_HOST" "echo ok" &>/dev/null; then
    log "SKIP-REV: MacBook not reachable via SSH (may be asleep or off network)"
    notify "MacBook not reachable — skipping reverse sync"
    exit 0
fi

log "START-REV: Pulling newer files from MacBook ($LOCAL_IP)"

# ── Rsync options ─────────────────────────────────────────────
# Key differences from the forward sync:
#   --update    only overwrite if the source file is newer
#   NO --delete never remove files that exist on Studio but not on MacBook
RSYNC_OPTS=(
    --archive           # preserve permissions, symlinks, timestamps, etc.
    --compress          # compress during transfer
    --update            # only copy files that are newer on the source
    --partial           # keep partially transferred files (resume on next run)
    --human-readable
    --quiet             # keep logs clean; remove this for debugging
)

SYNC_ERRORS=0

sync_path() {
    local remote_path="$1"
    local local_path="$2"
    shift 2
    local extra_opts=("$@")

    # Ensure local directory exists
    /bin/mkdir -p "$local_path"

    # Escape spaces for the remote shell
    local escaped_remote="${remote_path// /\\ }"

    log "  Reverse syncing: $remote_path → $local_path"
    if /usr/bin/rsync "${RSYNC_OPTS[@]}" "${extra_opts[@]}" \
        "${MACBOOK_HOST}:${escaped_remote}" "$local_path"; then
        log "  OK-REV: $remote_path"
    else
        log "  FAIL-REV: $remote_path (exit code $?)"
        SYNC_ERRORS=$((SYNC_ERRORS + 1))
    fi
}

# ── Merge helper ──────────────────────────────────────────────
merge_history() {
    local remote_host="$1"
    local history_file="$HOME/.claude/history.jsonl"
    local tmp_remote="/tmp/studio-sync-remote-history.jsonl"
    local tmp_merged="/tmp/studio-sync-merged-history.jsonl"

    log "  REV: Merging history.jsonl from $remote_host..."

    if ! /usr/bin/rsync --compress --quiet "${remote_host}:${history_file}" "$tmp_remote" 2>/dev/null; then
        log "  SKIP-REV: Could not fetch remote history.jsonl"
        return 0
    fi

    if /usr/bin/python3 -c "
import json, sys

seen = set()
entries = []
for path in sys.argv[1:]:
    try:
        with open(path) as f:
            for line in f:
                line = line.strip()
                if line and line not in seen:
                    seen.add(line)
                    try:
                        entries.append((json.loads(line).get('timestamp', 0), line))
                    except json.JSONDecodeError:
                        entries.append((0, line))
    except FileNotFoundError:
        pass

entries.sort(key=lambda x: x[0])
for _, line in entries:
    print(line)
" "$history_file" "$tmp_remote" > "$tmp_merged" 2>/dev/null; then
        /bin/mv "$tmp_merged" "$history_file"
        log "  OK-REV: history.jsonl merged"
    else
        log "  FAIL-REV: history.jsonl merge failed"
    fi

    /bin/rm -f "$tmp_remote" "$tmp_merged"
}

# ── SQLite safe-copy helper ──────────────────────────────────
# SQLite databases consist of .db + .db-wal + .db-shm as a coherent unit.
# Rsyncing the .db alone (without WAL) produces a corrupt copy.
# Fix: use sqlite3's .backup command on the source to create a consistent snapshot.
safe_sync_sqlite() {
    local remote_host="$1"
    local db_path="$2"
    local local_dir="$3"
    local db_name="$(/usr/bin/basename "$db_path")"
    local backup_name="${db_name}.sync-backup"

    log "  REV: Creating safe SQLite backup on $remote_host: $db_path"

    if /usr/bin/ssh -o ConnectTimeout=5 -o BatchMode=yes "$remote_host" \
        "if [ -f '$db_path' ]; then /usr/bin/sqlite3 '$db_path' '.backup ${db_path}.sync-backup' 2>/dev/null && echo OK; else echo MISSING; fi" 2>/dev/null | grep -q "OK"; then

        if /usr/bin/rsync --compress --quiet \
            "${remote_host}:${db_path}.sync-backup" "${local_dir}${backup_name}" 2>/dev/null; then
            /bin/mv "${local_dir}${backup_name}" "${local_dir}${db_name}"
            log "  OK-REV: $db_name synced via safe backup"
        else
            log "  FAIL-REV: Could not rsync $backup_name"
            SYNC_ERRORS=$((SYNC_ERRORS + 1))
        fi

        /usr/bin/ssh -o BatchMode=yes "$remote_host" "/bin/rm -f '${db_path}.sync-backup'" 2>/dev/null || true
    else
        log "  SKIP-REV: $db_path not found or sqlite3 backup failed on $remote_host"
    fi
}

# ── Reverse sync ──────────────────────────────────────────────

# 0. Merge Claude Code session history from MacBook
merge_history "$MACBOOK_HOST"

# 1. Development directory
sync_path "$HOME/Development/" "$HOME/Development/" \
    --exclude-from="$EXCLUDE_FILE"

# ── Obsidian Uploads (disabled by default in public build) ─────────────
# This block helps sync content from an Obsidian vault that is too large
# for the paid Obsidian Sync service, or could be expanded to sync an
# entire vault. It's disabled here so the public build has no Obsidian
# dependency. To enable: (1) set UPLOADS_PATH to your vault's folder,
# (2) remove the two lines that bracket this block:
#     : <<'OBSIDIAN_DISABLED'   (this line, opener)
#     OBSIDIAN_DISABLED         (the matching closer below)
: <<'OBSIDIAN_DISABLED'
# 2. Obsidian Uploads (files too large for Obsidian Sync)
sync_path "$HOME/Documents/Obsidian/YOUR_VAULT/Uploads/" "$HOME/Documents/Obsidian/YOUR_VAULT/Uploads/"
OBSIDIAN_DISABLED

# 3. Claude Code skills (~/.claude/skills/)
#    Uses --update (only copy newer) and NO --delete (never remove Studio skills)
sync_path "$HOME/.claude/skills/" "$HOME/.claude/skills/"

# 3b. Claude Code session transcripts (~/.claude/projects/)
#     Lets you resume a MacBook session on the Studio. --update (only newer) and
#     NO --delete — never removes a session that exists only on the Studio.
sync_path "$HOME/.claude/projects/" "$HOME/.claude/projects/" \
    --exclude="*/sessions/"

# 4. Claude-mem MCP plugin data — REMOVED
#    Syncing claude-mem between machines kept corrupting the database and
#    breaking Claude Code on the MacBook. Each machine now keeps its own copy.

# ── Wrap up ───────────────────────────────────────────────────
if [ "$SYNC_ERRORS" -eq 0 ]; then
    log "DONE-REV: Reverse sync completed successfully"
    notify "Reverse sync complete — MacBook changes pulled in"
else
    log "DONE-REV: Reverse sync completed with $SYNC_ERRORS errors"
    notify "Reverse sync finished with $SYNC_ERRORS errors — check log"
fi
