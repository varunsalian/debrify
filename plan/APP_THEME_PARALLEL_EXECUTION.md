# Executing the theme rollout with parallel agents, one working tree

Companion to `APP_THEME_ROLLOUT_PLAN.md`. That document says *what* to build;
this one says *who does it, when, and what stops them colliding*. Constraint set
by the user: **no branches, no worktrees** — every agent edits this tree and
leaves its work uncommitted on `tvos_port`, so it can be tested and committed
the usual way.

Everything here rests on one precondition, verified at time of writing: **the
tracked tree is clean.** Only `plan/` and `tool/` additions are untracked. That
is what makes per-track revert safe, and it is a precondition of every wave, not
just the first.

---

## What measuring the coupling changed

Before assigning anything I mapped which files import which token module. Four
findings move the plan; the last two contradict it.

**1. There are four legacy token modules, not three.** The rollout plan's
compatibility model names details (`DetailTheme`), Home (`home_theme.dart`) and
Cloud (`CloudTheme`). It misses **`lib/widgets/see_all/see_all_theme.dart`** —
`kSeeAllBg`, `kSeeAllAccent`, `kSeeAllPanel`, and friends, imported by **23
files**. The compatibility mapping table needs a `see_all` subprofile.

**2. `see_all_theme.dart` and `search_screen.dart` are one migration unit.**
The file says so itself:

> these are duplicated here on purpose: the See-All widgets are imported *by*
> `search_screen`, so importing back into it for the constants would create a
> dependency cycle. Keep these in sync with the board tokens.

`search_screen.dart:95-96` holds `kStremioAccent` / `kStremioBg` with the same
values. Migrating one without the other breaks a documented invariant, so
Home/Search/Discover and see-all **cannot be two parallel tracks**.

**3. Two token modules are imported by *frozen* surfaces.** This is the one that
matters most:

| module | importers | frozen importers |
|---|---|---|
| `home_theme.dart` | 31 | `stremio_tv/` ×3, `iptv/` ×4 |
| `see_all_theme.dart` | 23 | `browse_screen`, `youtube/` ×3, `iptv/` ×3 |
| `cloud_theme.dart` | 9 | none |
| `detail/theme/*` | 17 | none |

Foundation item 8 frames this as a *shared-widget* policy covering two widgets.
It is actually a *shared-token-module* problem across ~14 frozen importers.
Converting `HomeTheme`/`kSeeAll*` from constants to context lookups silently
themes IPTV, YouTube, Stremio TV and Browse — the exact leak the freeze wrappers
exist to prevent. **Foundation must resolve this before any sweep touches those
two files**, and the resolution is almost certainly "frozen callers keep the
constants; themed callers move to tokens", i.e. the modules split rather than
convert.

**4. Cloud and Calendar are genuinely isolated.** All 9 `cloud_theme` importers
are inside the Cloud surface. `trakt_calendar_screen.dart` imports **no** theme
module at all. These two are the clean parallel candidates, and they are the
reason this exercise is worth doing.

---

## Ownership model

One tree means correctness comes from **disjoint allow-lists**, not from git.
Every file belongs to exactly one owner.

### Central — I own these, no agent ever edits them

Not because they're hard, but because they're the files every track would
otherwise touch at once.

```
lib/main.dart
lib/widgets/detail/theme/detail_theme.dart
lib/widgets/detail/theme/detail_themes.dart
lib/widgets/home/home_theme.dart
lib/widgets/see_all/see_all_theme.dart
lib/services/storage_service.dart
lib/screens/settings/detail_theme_page.dart        (becomes the app picker)
<all new Foundation files: AppTheme, AppThemeScope, AppThemeController,
 LegacyThemeBoundary, the overlay helpers, the route factories>
```

The rule that makes this hold: **no agent may add, rename or re-value a token.**
An agent that needs one stops and reports it. I add it centrally between waves.
That converts the single worst merge hotspot into a cheap synchronisation point.

### Tracks

| Track | Surface | Files | Isolation |
|---|---|---|---|
| **A** | Cloud | 11 (incl. `cloud_theme.dart`) | clean |
| **B** | Calendar | 1 | clean |
| **C** | Settings | 41 (42 minus `detail_theme_page.dart`) | clean after Foundation |
| **D** | Home/Search/Discover + home widgets + see-all | 25 | **indivisible** |
| **E** | Addons | 2 | depends on D |
| **F** | Themed details | 12 (minus the 2 central token files) | depends on Foundation |
| **G** | Shell / nav chrome | 7 | central (`main.dart`) |

Track A owns `cloud_theme.dart` outright — all its importers are inside track A,
so the `CloudTheme.of(context)` conversion and its `const` removals stay
in-track. That is what makes Cloud the best parallel candidate despite being the
largest sweep.

Track C carves out `detail_theme_page.dart` (it becomes the unified app picker —
central) and must treat `see_all_theme` as read-only: `settings_widgets.dart`
imports it.

---

## Wave schedule

Waves are serial. Tracks inside a wave are parallel. **Each wave starts from a
clean tree and ends with you testing and committing it** — which is your normal
cadence, and also the thing that keeps per-track revert working.

### Wave 0 — Foundation (serial, ~7–9 d)

I do this alone. It is judgement, not volume: the boundary architecture, the
`ThemeData` adapter, the compatibility mapping table, the text-brightness
resolver, the golden harness. Splitting it across agents produces four
internally-sensible answers that don't compose.

**Parallel here is read-only.** Three or four agents that search and report but
never edit, run concurrently with my design work — zero collision risk by
construction:

- overlay-mechanism inventory across the six `showGeneralDialog` /
  `RawDialogRoute` / bare `OverlayEntry` files
- the 13 external `VideoPlayerScreen` construction sites, for `pushExcluded`
- frozen-importer audit of `home_theme` / `see_all_theme` (finding 3 above) —
  every call site, classified themed vs frozen
- Addons' ~10 modal entry points; the `SettingsTile` 61 `.spec` + 25 direct
  construction sites

Wave 0 also adds the `see_all` subprofile the mapping table is currently missing.

**Gate:** one themed and one frozen destination rendering side by side, one
migrated light route, golden harness green. Do not open wave 1 without it.

### Wave 1 — the vocabulary slice (serial, ~4–6 d)

**Track D alone.** Home/Search/Discover + home widgets + see-all, as one unit —
`search_screen.dart` is 22,982 lines and the `kStremio*`/`kSeeAll*` duplication
binds it to see-all. One agent or me, not several.

Then **track G** (shell), immediately after, in the same wave: a light page
inside unchanged dark navigation breaks the contract more visibly than any
single screen.

This wave is where the token vocabulary stops moving. Nothing else may start
until it does — every later track consumes the vocabulary this one establishes.

**Gate:** vocabulary frozen. Any token a later track needs is an exception I
handle centrally, not a normal event.

### Wave 2 — the parallel wave (~2–3 d wall clock, ~5–7 d of work)

Three agents, concurrently, on fully disjoint file sets:

- **A — Cloud** (11 files, ~761 sites, the `CloudTheme.of` conversion)
- **C — Settings** (41 files, ~687 sites)
- **B — Calendar** (1 file, ~122 sites)

This is the whole payoff. All three are mechanical sweeps behind a fixed
vocabulary, none shares a file with another, and the two token modules they
might have contended over (`cloud_theme` is A's alone; `see_all_theme` is
central and read-only) are resolved.

### Wave 3 — followers (~1–2 d)

- **E — Addons** (2 files) — needs D's see-all resolution, hence not wave 2
- **F — Themed details** (12 files) — the `(app_theme, detail_theme, style)`
  resolution

Two agents, disjoint, parallel.

### Wave 4 — wiring and QA (serial, 2 d + device time)

Mine. One picker, the sheet/dialog/snackbar inventory, cross-product contrast
tests, and device passes on Android phone, Android TV and Apple TV.

---

## The agent contract

Every agent gets these rules verbatim. Rule 1 is load-bearing — per-track revert
only works if it holds.

1. **Edit only files on your allow-list.** If a change is needed elsewhere, stop
   and report it. Do not edit it "just this once".
2. **Never add, rename or re-value a token.** Report the need; it will be added
   centrally.
3. **Run no builds and no analysis** — no `flutter build`, `flutter analyze`,
   `flutter pub`, `dart fix`, or `dart format`. Concurrent invocations contend
   on `.dart_tool` and each agent would see the others' half-finished edits as
   errors, producing confident and wrong bug reports. Verification is a single
   integration pass, run once, by me.
4. **Run no git commands.** No commit, stash, checkout, branch, or reset. The
   tree is shared; a stash by one agent would swallow the others' work.
5. **No opportunistic refactoring, no formatting-only churn.** Every hunk must
   be attributable to the theme migration, so the wave's diff stays reviewable
   per track.
6. **Preserve `const` where the value is genuinely invariant** — pure-black
   scrims, `transparent`, structural widgets. Tokenising an invariant colour
   costs a `const` and buys nothing. (This softens the rollout plan's "no
   `Color(0x…)` literal left" exit criterion, which as written fights this.)
7. **Report a per-file change summary** on finish: file, what changed, tokens
   consumed, anything you wanted to touch and didn't.
8. **Self-review with codex before finishing — scoped to your own files.**
   Codex reviews the uncommitted diff, and with several agents in one tree a
   bare invocation would review the OTHER tracks' half-written changes and
   report confident findings about code that isn't yours. Pass your explicit
   allow-list in the prompt ("review ONLY these files"), run
   `codex exec --sandbox read-only "…" < /dev/null` (the stdin redirect is
   mandatory — without it codex hangs), fix its P0/P1 findings inside your
   allow-list, and include the verdict in your report. Findings about files
   outside your list are reported upward, never acted on. Codex runs as a
   separate process, so this costs no orchestrator context.

---

## Integration protocol

Because it is one uncommitted pile, attribution comes from the allow-lists
rather than from git metadata.

**After each wave, I run once:**
1. `flutter analyze` — a single invocation, no contention.
2. A build (`flutter build apk --release --target-platform android-arm64` is the
   fastest useful one).
3. Golden suite for every surface the wave touched, under `legacy`.
4. Diff review, per track, using the allow-list as the file filter.
5. An allow-list breach check — any modified file outside every track's list is
   a rule-1 violation and gets inspected before anything else.

**Then it's yours**: test on the box, commit. Wave N+1 does not start until wave
N is committed and the tree is clean again.

## Recovery

One track going bad is the scenario worth designing for, and it's cheap here:

```
git checkout -- <that track's allow-list>
```

This restores exactly that track's files to the wave's starting point, leaving
the other tracks untouched — **but only because the tree was clean when the wave
opened.** If a wave starts dirty, this command also destroys whatever else was
uncommitted in those files. That is the entire reason for the
clean-tree precondition, and it is not negotiable.

Then rerun that one agent. The other two tracks' work is unaffected and still
uncommitted, ready for you to test.

**Cap: three agents per wave.** Not a technical limit — a review limit. Beyond
three, the wave's combined diff stops being something you can meaningfully test
in one sitting, which defeats the point of landing it uncommitted.

---

## What this actually buys

| Wave | Serial | This plan |
|---|---|---|
| 0 Foundation | 7–9 d | 6–8 d (read-only inventory agents) |
| 1 Home/Search/Discover + shell | 5–6 d | 4–6 d (indivisible) |
| 2 Cloud + Settings + Calendar | 5–7 d | **2–3 d** (3 agents) |
| 3 Addons + details | 2–3 d | 1–2 d (2 agents) |
| 4 Wiring + QA | 2 d + device | 2 d + device |
| **Total** | **20–26 d** | **15–21 d** |

The gain is concentrated in wave 2 and nowhere else, which is the honest shape:
Foundation is judgement, wave 1 is one indivisible file, and QA is device time.
Roughly a fifth off the total — worth having, not transformative.

Two things would erase it. **Vocabulary churn** — if wave 1 doesn't actually
freeze the token set, every wave-2 agent stalls on central additions and the
parallelism evaporates. And **an allow-list breach**, which turns a clean
per-track revert into manual diff surgery. Both are process failures, not
technical ones, which is why the contract above is short and absolute rather
than nuanced.

---

## Open decisions before wave 0

1. **Playlist (index 1) and Downloads (index 2)** — still frozen-by-default in
   the rollout plan, pending your call. Themed means re-measuring both trees and
   adding roughly a day, more once Playlist's dependencies are counted.
2. **`home_theme` / `see_all_theme` split-vs-convert** — finding 3. My reading
   is split (frozen callers keep constants, themed callers move to tokens), but
   it is a Foundation deliverable and worth confirming, since it decides whether
   IPTV/YouTube/Stremio TV need any edits at all in phase one.
3. **The two light themes on TV** — `broadsheet` and `concrete` at TV brightness
   in a dark room. Possibly phone-first in the picker; a comfort call, not a
   technical one.
