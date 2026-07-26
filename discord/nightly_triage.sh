#!/bin/bash
# Debrify nightly triage — run by launchd at 1am. Runs the autonomous triage headless
# on the LOCAL machine (which has the secrets in .dev.vars + gh auth), so it can fetch
# Discord, dedupe/size, and file tickets with full AI triage. See com.debrify.nightly-triage.plist.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
REPO="/Users/varunbsalian/Documents/Projects/debrify"
cd "$REPO" || { echo "repo not found: $REPO"; exit 1; }

mkdir -p discord/nightly_logs
LOG="discord/nightly_logs/$(date +%Y-%m-%d_%H%M).log"

{
  echo "======== Debrify nightly triage :: $(date) ========"
  claude -p "Read and follow .claude/commands/triage-nightly.md exactly. This is the unattended 1am run — never ask questions or wait for approval; auto-file only genuinely-new, deduped tickets, auto-size them, then print the summary." \
    --permission-mode bypassPermissions \
    --model claude-sonnet-5
  echo "======== done :: $(date) ========"
} >> "$LOG" 2>&1

# Keep only the last 30 daily logs.
ls -1t "$REPO/discord/nightly_logs"/*.log 2>/dev/null | tail -n +31 | xargs -r rm -f
