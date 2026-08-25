#!/bin/bash
# Debrify nightly triage — run by launchd at 1am. Runs the autonomous triage headless
# on the LOCAL machine (which has the secrets in .dev.vars + gh auth), so it can fetch
# Discord, dedupe/size, and file tickets with full AI triage. See com.debrify.nightly-triage.plist.
#
# NOTE: the copy that actually runs lives at
#   ~/Library/Application Support/debrify-triage/nightly_triage.sh
# (macOS TCC blocks launchd from exec'ing scripts under ~/Documents). If you edit this
# file in the repo, re-copy it there (see dev/tool/discord/README.md).
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

# Do NOT let Claude Code self-update mid-run: a background npm-global update swaps its
# files under the running headless process and kills it with EPERM (root cause of the
# first failed run, 2026-07-26). Keep it pinned during the unattended run; update manually.
export DISABLE_AUTOUPDATER=1

# Optional: a long-lived headless token (from `claude setup-token`) avoids depending on the
# macOS Keychain for auth refresh. Drop it at the path below (chmod 600) to use it.
TOKEN_FILE="$HOME/Library/Application Support/debrify-triage/.claude_oauth_token"
[ -f "$TOKEN_FILE" ] && export CLAUDE_CODE_OAUTH_TOKEN="$(tr -d '[:space:]' < "$TOKEN_FILE")"

REPO="/Users/varunbsalian/Documents/Projects/debrify"
cd "$REPO" || { echo "nightly-triage: repo not found: $REPO" >&2; exit 1; }

mkdir -p dev/tool/discord/nightly_logs
LOG="dev/tool/discord/nightly_logs/$(date +%Y-%m-%d_%H%M).log"

{
  echo "======== Debrify nightly triage :: $(date) ========"
  # Hard 15-min cap (perl alarm — macOS has no `timeout`). Prevents a hung run.
  perl -e 'alarm shift @ARGV; exec @ARGV' 900 \
    claude -p "Read and follow .claude/commands/triage-nightly.md exactly. This is the unattended 1am run — never ask questions or wait for approval; be fast and decisive; auto-file only genuinely-new, deduped tickets, auto-size them, then print the summary." \
      --permission-mode bypassPermissions \
      --model claude-sonnet-5
  RC=$?
  if [ $RC -eq 142 ] || [ $RC -eq 124 ]; then
    echo "!! nightly-triage: TIMED OUT after 15m (rc=$RC) — killed."
  elif [ $RC -ne 0 ]; then
    echo "!! nightly-triage: claude exited non-zero (rc=$RC)."
  fi
  echo "======== done (rc=$RC) :: $(date) ========"
} >> "$LOG" 2>&1

# Keep only the last 30 daily logs.
ls -1t "$REPO/dev/tool/discord/nightly_logs"/*.log 2>/dev/null | tail -n +31 | xargs -r rm -f
