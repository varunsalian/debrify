# Debrify Discord bot

Structured bug/feature intake for the Debrify community, plus a read-only CLI to sweep
the free-text channels. Bug reports and feature requests become GitHub issues in the
private **[debrify-tracker](https://github.com/varunsalian/debrify-tracker)** repo.

## Pieces

| File | What it is |
|------|------------|
| `src/worker.js` | Cloudflare Worker — Discord interactions endpoint. `/bug` & `/feature` → forms → GitHub issue + channel embed. |
| `register.mjs` | One-time (re-run on change) registration of the slash commands to the guild. |
| `discord_fetch.py` | Read-only CLI to pull recent posts from `general`, `help-support`, `bug-reports`, `feature-requests`. |
| `config.json` | Non-secret IDs (app, guild, channels, tracker repo). |
| `.dev.vars` | **Secrets, gitignored.** `DISCORD_TOKEN`, `DISCORD_PUBLIC_KEY`, `GITHUB_TOKEN`. |

## How the forms work

`/bug` takes a **platform** dropdown, `/feature` takes a **category** dropdown. Picking
one opens a modal (the "form") that forces the reporter to fill the fields. On submit the
Worker files a labelled issue in the tracker and posts a summary embed back in the channel.
See the tracker README for the exact fields.

## Setup / redeploy

```bash
cd discord

# 1. Register (or update) the slash commands — needs DISCORD_TOKEN in .dev.vars
npm run register

# 2. Push the GitHub PAT secret (once), then deploy the Worker
wrangler secret put GITHUB_TOKEN
npm run deploy

# 3. In the Discord Developer Portal → General Information →
#    "Interactions Endpoint URL" = the deployed Worker URL. Save (Discord sends a PING).
```

## Sweep the free-text channels

```bash
python3 discord_fetch.py                 # all channels, human-readable
python3 discord_fetch.py bug-reports     # one channel
python3 discord_fetch.py --json          # for triage tooling
```

## Nightly automation (1am, local)

Runs the whole triage unattended once a day via macOS `launchd` — locally, because the cloud can't
hold the secrets. It fetches the last ~30h, dedupes against the tracker, auto-files genuinely-new
tickets, and auto-sizes them (no approval gate — see `.claude/commands/triage-nightly.md`).

**Install / reinstall:**
```bash
# 1. Launcher must live OUTSIDE ~/Documents (macOS TCC blocks launchd from exec'ing scripts there)
mkdir -p "$HOME/Library/Application Support/debrify-triage"
cp discord/nightly_triage.sh "$HOME/Library/Application Support/debrify-triage/nightly_triage.sh"
chmod +x "$HOME/Library/Application Support/debrify-triage/nightly_triage.sh"

# 2. Install + load the launchd job (1am local, Hour=1)
cp discord/com.debrify.nightly-triage.plist "$HOME/Library/LaunchAgents/"
launchctl bootout   gui/$(id -u)/com.debrify.nightly-triage 2>/dev/null
launchctl bootstrap gui/$(id -u) "$HOME/Library/LaunchAgents/com.debrify.nightly-triage.plist"
launchctl enable    gui/$(id -u)/com.debrify.nightly-triage

# Run it now (test):   launchctl kickstart gui/$(id -u)/com.debrify.nightly-triage
# Logs:                discord/nightly_logs/  (gitignored, keeps last 30)
```

**Requires:** Mac powered on + logged in at ~1am (screen may be locked). Asleep → runs at next wake.
`claude` auth is read from the macOS Keychain; launchd's `HOME`+`USER` env is enough for it.
**If you edit `nightly_triage.sh`, re-copy it to App Support** (step 1) — that copy is what actually runs.

## Notes

- The Worker does **not** use the bot token — it replies via the interaction token. Only
  `GITHUB_TOKEN` is a Worker secret. The bot token is used by `register.mjs` / `discord_fetch.py`.
- If the bot token was ever exposed, reset it in the Developer Portal → Bot, update
  `.dev.vars`, and re-run `npm run register`.
