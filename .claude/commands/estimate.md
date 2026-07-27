---
description: Code-grounded effort estimation for tracker tickets — investigate the Debrify repo for each open issue, then apply an effort:* label and a "where the work lives" note
argument-hint: [issue numbers]   e.g. /estimate 5 14 21   (default: all open issues with no effort label)
allowed-tools: Bash, Read, Grep, Glob, Agent, Edit, Write
---

You are sizing Debrify tracker tickets by **actually reading the code**, not guessing. Each ticket
gets an `effort:*` label and a short, grounded note on where the work lives.

Raw arguments: `$ARGUMENTS`

- If numbers are given, estimate exactly those tracker issues.
- Otherwise, estimate **every open issue that has no `effort:*` label yet** (idempotent — safe to
  re-run; already-sized tickets are skipped).

Tracker repo: **`varunsalian/debrify-tracker`**. App repo: the current working dir (`varunsalian/debrify`, a Flutter app — code under `lib/{screens,services,widgets,models,utils}`).

## Effort scale (labels already exist)

- `effort:xs` — < 1 hour (one-line / config / label tweak)
- `effort:s` — a few hours (localized change, one file/flow)
- `effort:m` — 1–2 days (spans a few files, some new logic/UI)
- `effort:l` — multi-day (new screen/subsystem-ish, cross-cutting)
- `effort:xl` — major or uncertain scope (new subsystem, new runtime, big unknowns)

## Stage A — Collect the tickets

`gh issue list --repo varunsalian/debrify-tracker --state open --limit 200 --json number,title,body,labels`
Filter to the target set (given numbers, or those lacking any `effort:` label). If none, say so and stop.

## Stage B — Retrieval (cheap Haiku agents gather; they do NOT size)

This is the token-heavy part (reading a ~400-file Flutter codebase), so it runs on cheap, fast agents.
The final effort verdict is **not** theirs — it's decided in Stage C by you (the main model) from their
summaries. Keeping judgment out of Haiku's hands is deliberate: sizing + the "already fixed" catch is
where accuracy matters.

**First read `CODEMAP.md`** (repo root) — the area→owning-files index. Use it to route each ticket to
its likely files so agents skip the expensive discovery grep-around. Group the tickets **by shared file**
where possible (e.g. all `search_screen.dart` tickets in one agent) so a huge file is read once, not
per-ticket. Respect the 🔴 "grep, don't read whole" flags in the map.

For each cluster, **dispatch an `Explore` agent with `model: "haiku"` and `effort: "low"`**, running
clusters in parallel. Hand each agent the **candidate file paths from CODEMAP.md** for its tickets.
Each agent's job is **retrieval only** — confirm/locate code and report facts, not a size. Prompt them
to return, PER TICKET (terse — paths + one-liners, not essays):

> - **Files/functions** actually involved (real paths — verify they exist, don't guess).
> - **What the change touches**: one line — which layers (model / service / UI / native), and whether
>   the machinery already exists or would be built from scratch.
> - **Isolated or cross-cutting**: ~1 file/flow vs. many files / a new subsystem.
> - **Already-fixed / duplicate check** (do this explicitly): run `git log --oneline -S"<key symbol>"`
>   and `git log --since="30 days ago" --oneline` + grep for the feature; if a recent commit already
>   implements/fixes it, report the commit hash + subject. This is the highest-value signal — flag it.
> - Do NOT edit anything. Do NOT assign an effort label — just report what you found.

## Stage C — Size the tickets (main model — the judgment step)

Using each Haiku agent's factual summary (not vibes, not re-reading every file), assign the `effort:*`
size yourself. Anchor on:
- **How many files/layers** it touches (1 file = S; a few = M; many/new subsystem = L/XL).
- **Does the machinery already exist?** (a new filter option next to existing ones = S/M; a whole new
  provider runtime / plugin host = XL.)
- **Already fixed?** If an agent found a commit that resolves it → size `XS` and note "already done,
  verify/close."
- **Unknowns** (external API behavior, device-specific TV bugs) push size up and warrant `status:needs-info`.

If an agent's summary is too thin to size confidently (missing files, vague), spot-check that one ticket
yourself with Grep/Read before deciding — don't guess low.

## Stage D — Apply (write)

For each ticket, add the label and a grounded comment:

```
gh issue edit <NN> --repo varunsalian/debrify-tracker --add-label "effort:<size>"
gh issue comment <NN> --repo varunsalian/debrify-tracker --body \
  "**Effort: <SIZE>** — <where the work lives: files/functions> · <one-line rationale>. _(code-grounded estimate)_"
```

Keep the note concrete: name real paths you found (e.g. `lib/services/prowlarr_service.dart`), say
whether it's isolated or cross-cutting, and flag any big unknown.

## Stage E — Report

Print a table: issue · title · priority · effort. Then surface the **quick wins** (high/medium priority
+ `effort:xs`/`s`) and the **big rocks** (`effort:l`/`xl`) so the user can plan. Note that
`priority` (how much it matters) and `effort` (how much work) are independent — the sweet spot is
high-priority + low-effort.

## Guardrails
- **Read-only on the app repo** — investigation never edits Debrify code. Writes go only to the tracker
  (labels + comments).
- Ground every estimate in files you actually located; if you genuinely can't find the code, size it
  `effort:xl` and say why (unknown scope) rather than guessing low.
- Idempotent: never double-label; skip tickets that already have an `effort:*` label unless explicitly named.
- **Model tiering:** retrieval agents run on Haiku/low-effort (cheap, they only gather facts); the
  effort verdict is always the main model's call. Never let a Haiku agent's self-assigned size stand
  unreviewed — that's where mis-sizing and missed already-fixed cases creep in.
