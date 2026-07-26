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

## Notes

- The Worker does **not** use the bot token — it replies via the interaction token. Only
  `GITHUB_TOKEN` is a Worker secret. The bot token is used by `register.mjs` / `discord_fetch.py`.
- If the bot token was ever exposed, reset it in the Developer Portal → Bot, update
  `.dev.vars`, and re-run `npm run register`.
