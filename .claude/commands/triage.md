---
description: Sweep the Debrify Discord for bugs/feature requests, cross-check against recent commits & releases, dedupe against the tracker, and file new GitHub issues (with one approval gate)
argument-hint: [days]   e.g. /triage 1  (default 7)
allowed-tools: Bash, Read, Edit, Write
---

You are running the **Debrify Discord triage**. Goal: turn the last few days of community
chatter into a clean, deduped backlog in the private tracker — without refiling things that
are already fixed or already tracked.

Raw arguments: `$ARGUMENTS`

Parse a single optional number = **days** to look back (default **7**). Everything runs from the
repo root; the Discord tooling lives in `discord/`. Secrets are in the gitignored
`discord/.dev.vars` (bot token) and `gh` is already authenticated for issue creation.

Tracker repo: **`varunsalian/debrify-tracker`** (private). App repo: `varunsalian/debrify` (public).

There is exactly **ONE approval gate (Stage C)** — nothing is filed or closed before the user approves.

## Stage A — Gather (read-only)

1. **Sweep Discord** for the window:
   `cd discord && python3 discord_fetch.py --days <N> --json > <scratch>/sweep.json`
   (channels swept: general, help-support, bug-reports, feature-requests, alpha-builds).
   Read the file. It may be large — read it fully (page through it), don't triage from a partial view.
2. **Existing tracker issues** (dedupe targets, open AND closed):
   `gh issue list --repo varunsalian/debrify-tracker --state all --limit 200 --json number,title,state,labels`
3. **Recent code activity** (the "already fixed" signal). Use a window a bit wider than N:
   `git log --since="<N+14> days ago" --pretty=format:'%ad %s' --date=short`
   `gh release list --repo varunsalian/debrify --limit 8`
   Also consult the auto-memory `MEMORY.md` for shipped/deferred work when a report is ambiguous.

## Stage B — Triage (analysis, no writes)

Go through every human message. **Extract only actionable items** — real bug reports and feature
requests. **Skip**: appreciation, how-do-I questions that got answered, self-resolved items
("silly me, it works now"), pure sideloading/support chatter, and dev-only messages.

Classify each actionable item into exactly one bucket:

- **NEW** — not addressed by any recent commit/release and not already in the tracker → will file.
- **ALREADY SHIPPED** — a commit/release already delivered it → do NOT file; list it.
- **LIKELY FIXED (verify)** — a recent commit plausibly fixes it but it's unconfirmed → do NOT file
  by default; list it under "verify" with the probable fix. (User may opt to file these as
  `status:needs-info` "verify in <version>" tickets.)
- **DUPLICATE** — same substance as an existing tracker issue #NN (semantic match, not just title)
  or as another item in this same sweep → fold together, cite the issue/other reporter.

Merge multiple reporters of the same thing into one item (note all reporters + reaction counts —
reactions/📌 are a priority signal).

For each **NEW** item, assign labels from the taxonomy:
- type: `bug` | `feature`
- platform (only if the report names one): `platform:android` `platform:android-tv`
  `platform:windows` `platform:macos` `platform:linux` `platform:ios`
- priority: `priority:critical` (crash/data-loss/blocks core) · `priority:high` (hits many users) ·
  `priority:medium` · `priority:low`
- status: bugs → `status:needs-info` (unless dev already acknowledged → `status:triaged`);
  features → `status:triaged`

## Stage C — Approval gate (STOP)

Show the user, grouped and compact:
- **Already shipped** (won't file) — one line each with the commit/release.
- **Likely fixed / verify** — table: bug · reporter · probable fix.
- **New bugs to file** — with proposed labels; flag any `critical`/`high`.
- **New features to file** — with proposed labels.
- **Duplicates** — folded into #NN.

Then ask which sets to file (default proposal: **new bugs + new features**). The user may also ask to
file the verify set, drop/edit specific items, or adjust labels/priority — apply and re-show if so.
Do not proceed until they confirm.

## Stage D — File (only after approval)

For each approved item, create an issue in the tracker. Prefer `gh` (already authed):

```
gh issue create --repo varunsalian/debrify-tracker \
  --title "<title>" --label "<l1>" --label "<l2>" ... \
  --body "<body>"
```

**Body template** (keep the reporter + verbatim quote — it's the evidence):
```
**Reporter:** <name(s)>
**Reported:** <YYYY-MM-DD> in #<channel>

> <verbatim quote>

---
**Triage note:** <why it's real / repro hint / probable-fix commit / dupe-of>

_Filed from the /triage sweep (<N>d window)._
```

If the user asked, close any resolved/duplicate issues:
`gh issue close <NN> --repo varunsalian/debrify-tracker --comment "<reason>"`.

## Stage E — Report

Print the filed issue numbers (bugs then features), any closed issues, the highest-priority items to
look at first, and the tracker URL. End by reminding the user the window can be tuned: `/triage 1`
for a daily pass, `/triage 14` for a fortnight.

## Guardrails
- One approval gate (Stage C). Never file or close before it.
- Dedupe hard — against the full tracker (open + closed) and within the sweep. Better to fold than to
  double-file.
- Don't refile ALREADY SHIPPED / LIKELY FIXED items unless the user explicitly opts in.
- Never print secrets; the bot token stays in `discord/.dev.vars`.
- If the sweep returns nothing actionable, say so plainly and stop — don't invent tickets.
