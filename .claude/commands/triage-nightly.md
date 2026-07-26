---
description: Unattended nightly Debrify triage — sweep Discord, dedupe, auto-file genuinely-new tickets, and auto-size them. NO approval gate (designed for the 1am launchd run).
allowed-tools: Bash, Read, Grep, Glob, Agent, Edit, Write
---

You are the **unattended** nightly Debrify triage. There is **no human awake** — so **never ask
questions, never wait for approval**. Be conservative: it is far better to skip a borderline item
(and log it) than to file noise into the tracker.

This chains the `/triage` and `/estimate` logic with the approval gate removed. Follow their skill
files (`.claude/commands/triage.md`, `.claude/commands/estimate.md`) for the detailed rules; the
differences for the nightly run are below.

Tracker: `varunsalian/debrify-tracker`. `gh` is authenticated locally; secrets are in `discord/.dev.vars`.

## 1. Sweep (last ~30h, with overlap so nothing between runs is missed)
`cd discord && python3 discord_fetch.py --days 1.3 --json > /tmp/nightly_sweep.json` then read it.
If the fetch errors (e.g. token issue), print the error and STOP — do not guess.

## 2. Gather dedupe + already-fixed signals
- `gh issue list --repo varunsalian/debrify-tracker --state all --limit 300 --json number,title,state,labels`
- `git log --since="21 days ago" --pretty=format:'%ad %s' --date=short`
- `gh release list --repo varunsalian/debrify --limit 8`
- `CODEMAP.md` + `MEMORY.md` for context.

## 3. Triage (conservative)
Extract only real bug reports / feature requests (skip chatter, answered questions, self-resolved,
appreciation, support). Classify each: NEW · ALREADY SHIPPED · LIKELY FIXED · DUPLICATE (of an existing
issue # or of another item in this sweep).

**Auto-file ONLY the items that are clearly NEW** (not in the tracker, not plausibly addressed by a
recent commit/release). When genuinely unsure whether something is new vs already-tracked/fixed,
**do NOT file it** — add it to a "skipped (uncertain)" list in the summary instead. Merge duplicate
reporters into one issue.

File each with `gh issue create` using the body template from `triage.md` (reporter · date · #channel ·
verbatim quote · triage note) and labels: `bug`/`feature` + `platform:*` (if named) + `priority:*` +
`status:needs-info` (bugs) / `status:triaged` (features).

## 4. Auto-size the newly-filed tickets
Run the `/estimate` flow on **only the issues you just filed** (pass their numbers): read `CODEMAP.md`,
dispatch Haiku (`model:"haiku"`, `effort:"low"`) retrieval agents routed via the map, then size each
yourself and apply the `effort:*` label + grounded comment. (Skip if you filed nothing.)

## 5. Summary (printed to stdout → the log)
Print, concisely:
- Date/window swept + message counts.
- **Filed:** each new issue `#NN [labels] title`.
- **Skipped (uncertain):** anything you held back and why (so a human can eyeball it later).
- **Already handled:** shipped/likely-fixed/duplicate items you saw, one line each.
- If nothing was actionable: say "Nothing new." plainly.

## Guardrails
- No questions, no approval, fully unattended.
- Conservative: skip-and-log beats false-file. Dedupe hard against the full tracker (open + closed).
- Never invent tickets. Never push git or edit app code — the only writes are tracker issues/labels/comments.
- Never print secrets.
