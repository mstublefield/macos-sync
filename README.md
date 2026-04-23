# macOS Sync

Bidirectional rsync between two Macs over SSH — a "work from anywhere" setup that keeps your Claude Code/Desktop environment, Development projects, and shell config coherent across a **primary Mac** (desktop) and a **secondary Mac** (laptop).

The secondary pulls from the primary automatically on login, on network change, and hourly. A safety-net reverse-push (secondary → primary) runs first each time so `--delete` never wipes work you did on the laptop. A separate primary-side script pulls newer files from the secondary on demand.

## What gets synced

- **`~/.claude/`** — skills, plugins, MCP configs, settings, memory, project CLAUDE.md files. Excludes conversation transcripts, debug logs, telemetry, and caches (~4 GB saved per sync).
- **`~/.claude/history.jsonl`** — merged (not overwritten) by timestamp with dedup, so slash-command history from both machines survives.
- **`~/.agents/`** — shared skill sources.
- **`~/Library/Application Support/Claude/`** — Claude Desktop config JSON files only. Electron runtime caches, VMs, and session databases are skipped (~9 GB saved).
- **`~/.docker/mcp/`** — Docker MCP server configs (Atlassian, Playwright, etc.). `mcp-toolkit.db` is skipped.
- **`~/Development/`** — all projects. See `sync-exclude.txt` for what's skipped (`node_modules/`, `.next/`, `.turbo/`, `dist/`, etc.).
- **`~/.zshrc`**, **`~/.gitconfig`** — shell config, git identity.
- **`~/Library/LaunchAgents/com.*.env.plist`** — GUI app environment variables.
- **Optional: `~/Documents/Obsidian/<vault>/Uploads/`** — large files outside the paid Obsidian Sync service, via a Studio-initiated SSH push that bypasses macOS TCC restrictions on writes to `~/Documents/`. Disabled by default; see "Optional: Obsidian Uploads" below.

## Prerequisites

On **both** Macs: enable Remote Login (System Settings → General → Sharing → Remote Login).

## Setup on the secondary Mac (forward sync — automatic)

```bash
git clone <this-repo> ~/Development/macos-sync
cd ~/Development/macos-sync

# Edit the top of sync-from-studio.sh to set:
#   STUDIO_HOST           — your SSH alias for the primary Mac
#   STUDIO_USER           — your macOS username on the primary Mac
#   HOME_NETWORK_PREFIX   — subnet the sync is allowed to run on
# Then:
./setup-macbook.sh
```

`setup-macbook.sh` generates an SSH key, appends an entry to `~/.ssh/config`, registers the key with the primary, installs the LaunchAgent, and runs an initial sync.

## Setup on the primary Mac (reverse pull — optional, manual)

If you want to pull newer secondary-Mac files to the primary manually when you sit back down:

```bash
cd ~/Development/macos-sync

# Edit the top of pull-from-macbook.sh to set MACBOOK_HOST and HOME_NETWORK_PREFIX.
./setup-studio.sh
```

`setup-studio.sh` discovers the secondary via Bonjour (or prompts), sets up a reverse SSH key, and registers it.

Trigger a reverse pull with:

```bash
~/Development/macos-sync/pull-from-macbook.sh
```

## How it works

### Forward sync (secondary pulls from primary — automatic)

Runs on login, on network change (watched via `/Library/Preferences/SystemConfiguration`), and hourly as a fallback. Throttled to at most once per 5 minutes so DHCP renews and WiFi roams don't spam it.

Each run:

1. **Preflight.** Lock file prevents overlap; skip unless on the configured home network; skip silently if the primary is unreachable.
2. **Reverse push (safety net).** Any newer secondary-Mac files under `~/Development/` and `~/.claude/skills/` get pushed to the primary with `--update` (no `--delete`), so the main pull can't clobber laptop-only work.
3. **History merge.** `~/.claude/history.jsonl` is fetched from the primary, deduplicated, sorted by timestamp, and written back as the union of both machines' entries.
4. **Main pull.** All the paths listed above, with `--archive --compress --delete --partial --itemize-changes`.
5. **Notify.** macOS notification on changes or errors; silent on clean no-op runs. Full log at `~/Library/Logs/studio-sync.log`.

### Reverse pull (primary pulls from secondary — manual)

Uses `--update` and no `--delete` — only copies files that are newer on the secondary, never removes files from the primary. Runs the same `history.jsonl` merge logic. Safe to run anytime; skips if the secondary isn't reachable.

### Optional: Obsidian Uploads

A block in `sync-from-studio.sh` (and a counterpart in `pull-from-macbook.sh`) can sync a folder from an Obsidian vault that's too large for the paid Obsidian Sync service — or you can adapt it to sync an entire vault. It's **disabled by default** in the public build, wrapped in a `: <<'OBSIDIAN_DISABLED' ... OBSIDIAN_DISABLED` heredoc.

macOS TCC blocks LaunchAgent-spawned processes from writing to `~/Documents/`, even with Full Disk Access granted to a wrapper `.app`. The workaround in the code: the secondary SSHes into the primary and tells the primary to `rsync` *to* the secondary. Files arrive via `sshd`, which writes with the user's full permissions and bypasses TCC entirely.

To enable:

1. Set `UPLOADS_PATH` in `sync-from-studio.sh` to your vault's folder (relative to `$HOME`).
2. Remove the `: <<'OBSIDIAN_DISABLED'` and matching `OBSIDIAN_DISABLED` lines that bracket each block.

### Safe SQLite snapshots

A helper (`safe_sync_sqlite`) exists to snapshot SQLite DBs via `sqlite3 .backup` before rsync, since `.db + .db-wal + .db-shm` must be copied atomically. Currently unused — `claude-mem` sync was removed after WAL/shm mismatches kept corrupting the DB and breaking Claude Code on the secondary Mac. Each machine now keeps its own `~/.claude-mem/` copy.

## Manual forward sync

```bash
~/Development/macos-sync/sync-from-studio.sh
```

## Cleanup

Upgrading from an earlier version of this script? You may have accumulated Claude Desktop caches and Claude Code session transcripts that are now excluded from sync but still sitting on disk (multi-GB). Run once:

```bash
~/Development/macos-sync/cleanup-stale-sync.sh
```

## Modifying excludes

`sync-exclude.txt` controls what's skipped under `~/Development/`. Add projects, build caches, or anything else you don't want on the secondary.

## Logs

- Forward sync log: `~/Library/Logs/studio-sync.log` (prefix: `START`, `REVERSE`, `OK`, `FAIL`, `DONE`)
- Reverse pull log: same file, prefix `*-REV`

## Configuration summary

All user-specific values live at the top of each script — edit once, then commit if you're tracking your own fork:

| Variable | File | Example |
|---|---|---|
| `STUDIO_HOST` | `sync-from-studio.sh` | SSH alias for the primary Mac |
| `STUDIO_USER` | `sync-from-studio.sh`, `setup-macbook.sh` | macOS username on the primary Mac |
| `MACBOOK_HOST` | `pull-from-macbook.sh` | SSH alias for the secondary Mac |
| `HOME_NETWORK_PREFIX` | both sync scripts | e.g. `192.168.1` |
| `UPLOADS_PATH` | `sync-from-studio.sh` | path to your Obsidian Uploads folder, relative to `$HOME` (only if you enable the optional Obsidian block) |
| `Label`, plist paths | `com.*.studio-sync.plist` | reverse-DNS label; edit `StandardOutPath`/`StandardErrorPath` to your username |

## License

BSL 1.1 — see [LICENSE](LICENSE). Converts to Apache 2.0 on 2030-04-23.
