# IPTV Premium Styles — P1 "First Edition" + P3 "Master Control" as switchable looks

*(rev 2 — after Codex plan review round 1: 2 P1 + 9 P2 findings folded in)*

**Goal.** The Command Center cockpit (rail → guide → stage, `_buildTvTwoPane`
`!touchSelector` branch in `lib/widgets/iptv/iptv_results_view.dart:4967`) gains two
alternative visual styles, selected by a new `iptv_style` preference:

| value | name | language |
|---|---|---|
| `command` | Command Center | today's look — the DEFAULT, via the untouched legacy code path |
| `edition` | First Edition | editorial warm ink, serif headline, hairline ledger (mock `iptv_premium_mockup/p1_first_edition.html`) |
| `console` | Master Control | pure-black instrument, mono numerals, amber playhead (mock `iptv_premium_mockup/p3_master_control.html`) |

Mocks are the design source of truth for color/type/spacing. This is a **restyle,
not a re-layout**: same widget-tree shape, same data flow, no new focusables.

## Non-goals / untouched surfaces

- Phone classic layout, touch-tablet two-pane, in-player channel sheet, zap banner,
  recordings pages: **unchanged** (settings only gains the picker).
- No new focusables anywhere in the cockpit. The three new widgets (hero, timeline,
  status bar) contain zero Focus nodes.
- Row **extents stay exactly as shipped** (`kIptvRowTallExtent`/`kIptvEpgRowTallExtent`
  etc., `iptv_channel_row.dart:26-38`) so grid math, `_gridRowExtent` publishing
  (:113-115), startup-channel scroll targeting (:3700) and zap paging are untouched.
- VOD/series **poster rows keep their current layout** in all styles (tone-only changes).
- Empty states, loading skeletons, `IptvSchedulePane`, pickers/dialogs: unchanged in v1.

## Invariants (violating any is a review P1)

1. LEFT-only sidebar policy: rail adds no LEFT handler; LEFT bubbles to the shell.
2. Rail `swallowUp`/`swallowDown`, `_StageActions.swallowDown`, stage `onExitLeft` →
   `_returnFocusFromStage` returns to the EXACT origin row.
3. Hold-OK on rows (500 ms heart fill, `_sawSelectDown` guard) and hold-OK-to-hide on
   category options — logic untouched. The heart-fill indicator and the 34×34 pointer
   hit targets keep their sizes and positions in every style.
4. `scheduleOnRightKey` stays off in cockpit; RIGHT from rows reaches the stage.
5. Focus-node `Map.identity()` lifecycle + `onDetached` contract untouched.
6. TV perf rules: no fades/tweens on TV, no shimmer, static skeletons, stage
   `RepaintBoundary` preserved, no `Opacity`/saveLayer over the preview underlay,
   per-row EPG dwell 900 ms + 3-concurrent budget unchanged.
7. `showScheduled`/`_pageCanRecord` gating; series rows still can't favorite; SWR chip
   stays `IgnorePointer`.
8. Classic + touch-tablet builds and every non-IPTV screen render exactly as today.
   `command` renders **pixel-identical** — guaranteed structurally (see Tokens).

## DPAD geometry — honest statement (was P1 finding 2)

Inserting the hero/timeline above the grid moves rows down, which changes which rail
item a given row's LEFT geometrically pairs with, and which stage focusable RIGHT
lands on. There are no pinned pairings today either — cockpit traversal is already
purely geometric nearest-candidate — so the behavior CLASS is unchanged and no dead
zone is possible (rows always have the rail to their left, the stage to their right,
the filter line above). What we guarantee and verify instead of "unchanged geometry":

- Hero/timeline/status bar contain no Focus nodes (nothing new can be landed on).
- The guide column keeps ≥4 visible grid rows in every style (height gate below), so
  UP/DOWN inside the grid never degenerates.
- Manual DPAD pass per style on desktop + TV: from first/middle/last VISIBLE row,
  verify LEFT lands in the rail, RIGHT lands in the stage, UP from the first row lands
  on the filter line, DOWN from the last visible row scrolls; verify
  `_returnFocusFromStage` still lands on the origin row (it targets the row's own
  focus node, so the shift is irrelevant to it — verify anyway).

## Architecture

### Pref (Phase A)

`StorageService` (pattern of `getTvHomeStyle`, `storage_service.dart:646`):

- `getIptvStyle()`/`setIptvStyle()`, key `iptv_style`, values `command|edition|console`,
  unknown coerces to `command` on BOTH read and write.
- `_IptvResultsViewState._loadSettings` reads it into `IptvStyle _iptvStyle` before
  `_settingsLoaded = true`. The existing return-from-settings path (`:4638-4644`)
  already awaits `_loadSettings` — the style re-read rides it; on change the setState
  that follows repaints the cockpit. No listener plumbing needed.
- The settings picker **awaits `setIptvStyle` before updating its selected state**
  (P2-9): no fire-and-forget write that the return-path reread could race.

### Tokens (Phase A)

New file `lib/widgets/iptv/styles/iptv_style.dart`: `enum IptvStyle` +
`IptvStyleTokens` (palette / type families / letterspacing / focus-treatment tag).

**Pixel-identity guarantee for `command` (P2-4):** every touched widget branches
FIRST on style: `command` takes the existing build method body, moved verbatim into
a `_buildLegacy…` (or kept in place with styled paths in separate methods). Styled
paths never share decoration/constraint code with the legacy path, so a null-check
can't subtly change it. Golden tests are NOT added tonight (no golden infra in repo);
the structural branch is the guarantee, plus a manual desktop A/B check with the pref
unset vs `command`.

### Fonts (Phase A) — files already staged in scratchpad

`assets/fonts/`: `Fraunces72pt-Regular.ttf`, `Fraunces72pt-Italic.ttf`,
`Fraunces9pt-Italic.ttf`, `SpaceGrotesk-Medium.ttf`, `SpaceGrotesk-Bold.ttf`,
`JetBrainsMono-Regular.ttf`, `JetBrainsMono-Bold.ttf` (~1 MB, OFL — license files
added under `assets/fonts/licenses/`). Registered in pubspec with explicit `weight`
and `style` descriptors:

- family `Fraunces72` → Regular (400), Italic (400 italic); family `Fraunces9` →
  Italic (400 italic)
- family `SpaceGrotesk` → Medium as 500, Bold as 700
- family `JetBrainsMono` → Regular 400, Bold 700

Consumed via static `fontFamily:` strings ONLY — never `GoogleFonts.*` for these
families (runtime fetch; P2-11). Assets must exist or the build fails — there is no
build-time fallback mechanism; the files are committed with the change. The subtitle
font picker's family list is hardcoded in `subtitle_font_service.dart` — new pubspec
families don't leak into it (verified).

### Settings UI (Phase A)

Gate everywhere: `PlatformUtil.isAndroidTvCached || desktop platform` — the page has
no `isTelevision` field (P2-7).

- **Narrow/single-column** (`iptv_settings_page.dart:1721+`): new `Appearance`
  section — `SettingsSectionLabel` + Card with three `RadioListTile`s (title +
  one-line description each) — inserted after **Continue watching**, before
  **Recording** (both optional sections around it already handle presence/absence).
- **Two-pane** (`iptv_settings_two_pane.dart`): new `_AppearanceDest` destination,
  rail entry after Continue watching / before Recording. All hardcoded destination
  counts and index links (`:270`, `:354`, `:369`, `:473`, `:542`, `:595`) updated to
  admit the new destination; pane = same three radio rows with the page's existing
  focusable row primitives. Selected value owned by the parent state like its
  neighbors.
- **Settings search** (`settings_screen.dart`, "Live TV & DVR" group): one leaf
  entry "IPTV appearance", gated identically to the section (house rule at `:87`),
  `onTap: _openIptvSettings` — documented plain landing (opens the page, no
  scroll-to-section; the `openAddSource`-style deep flag is optional follow-up).

### New display widgets — data flow (was P1 finding 1)

`contextVersion` does NOT signal per-channel fetch completion, and the stage owns its
fetched schedule privately. So the hero and timeline are **self-fetching consumers of
the same service caches** (exactly the `IptvRailEpgCard` pattern,
`iptv_epg_panel.dart:82,162`):

- Hero: paints instantly from `peekNowNext(url)` when fresh, else awaits
  `nowNext(url)` behind its own 450 ms focus-settle debounce (stage pattern,
  `iptv_stage_panel.dart:147-158`). Dedup is per-METHOD: `nowNext` coalesces
  with the focused row's own `_RowEpg` fetch of the same URL (cockpit rows carry
  EPG blocks, so that fetch has usually already run) via `_nowNextInFlight` +
  the LRU cache — NOT with the stage's `schedule` call, which is a different
  endpoint and in-flight map.
- Timeline: same shape with `schedule(url)` — THIS one coalesces with the
  stage's schedule fetch (`_scheduleInFlight` + cache).
- **Staleness (round-2 P1):** both follow the house consumer pattern, not
  fetch-once. The hero runs a 60 s reconciliation ticker exactly like
  `_RowEpg`'s (`iptv_channel_row.dart:713-727`): re-peek; a null peek (cache
  self-invalidated at a programme boundary) → refetch; a fresh hit → repaint
  progress. The timeline arms a programme-boundary timer exactly like the
  stage's `_armBoundaryTimer` (`iptv_stage_panel.dart:127-145`) to re-derive
  cell classification (past/NOW/upcoming) when the current programme ends,
  plus the independent 30 s playhead overlay repaint. ALL these timers cancel
  when the widget is hidden (height gate, no EPG) or suspended (schedule pane
  open); the "timers only in console widgets" claim is amended — the edition
  hero owns one ticker too, same cancellation rules, none in `command`.
- Both listen to `contextVersion` ONLY for its real meaning — XMLTV context
  replacement → refetch (same as `IptvRailEpgCard`).

## Phase B — First Edition (`edition`)

Palette: ink `#0D0B09`, paper `#F3EEE3` (100/80/55/35), hairlines 9/16%, REC
`#E5484D`, live sage `#B8C79B`. Focus = 2 px paper left-edge rule + full-alpha text.

1. **`IptvCommandRail`** + `style`: `command` → legacy branch. Edition: text-only
   rows (no icons), small-caps headers, tabular counts, focused = left rule (replaces
   gold border). Handlers/counts/swallow flags untouched.
2. **`IptvChannelRow`** + `style`: `command` → legacy branch. Edition ledger skin —
   the style hook lands on **`_LogoChip`** (the actual row art widget,
   `iptv_channel_row.dart:302,1004` — NOT `IptvMonogram`, which is the rail/stage
   mark): hairline circle variant. Name default-sans w600; EPG block restyled
   (now-title paper-80, next paper-35, 1.5 px hairline progress); res string as
   hairline micro-caps chip. Trailing controls (schedule icon, favorite 34×34 target,
   TV HOLD-OK indicator, heart fill) keep size/position/behavior — recolor only.
   Focus = left rule + 3.5% tint (replaces gold border).
3. **`IptvEditionHero`** (new, display-only, no Focus nodes) between the filter line
   and the grid — **inside the Offstage guide subtree** so the schedule pane covers
   it (P2-3). Kicker (live dot · `CH 22 · NAME · 2160P`), Fraunces72 ~40 px
   programme title (channel name when no EPG), meta line, hairline progress.
   Data per "data flow" above. Visibility: a `LayoutBuilder` INSIDE the guide column
   hides it unless ≥4 grid rows stay visible (measured against the active row
   extent), and below `guideHeight < 520` it never shows. **No action buttons in the
   hero** (stage owns actions; duplicating focusables breaks geometry — documented).
4. **Stage** (`_buildCockpitStage` chrome + `IptvStagePanel` + `style`): ink panel,
   hairline-framed preview, paper Watch pill + hairline ghost actions, schedule rows
   with paper time column, REC/REPLAY/NOW micro-caps. `command` → legacy branch.
5. **Quiet filter line**: shared `SeeAllFilterBar`/`StremioDropdown` NOT forked;
   accepted v1 delta from mock.

## Phase C — Master Control (`console`)

Palette: bg `#050505`, fg `#EDEDED` (100/70/45/28), hairlines 8/15%, amber `#F2A93B`
(time/focus/playhead ONLY), REC `#FF4545`. Type: SpaceGrotesk names, JetBrainsMono
numerals/times/labels.

1. **Status bar** (`IptvConsoleStatusBar`, display-only): console+cockpit wraps the
   cockpit in `Column(children: [statusBar, Expanded(child: Row(...))])` (P2-3 —
   the Row must stay bounded). Contents, from state that actually exists (P2-6):
   source name (`_selectedPlaylist?.name`), filtered/loaded channel count
   (`_filteredChannels.length`, the same number the quiet line shows), `REC n` where
   n = `DesktopRecordingService.instance.activeCount` on desktop / the Android
   URL→task map size (channel NAMES are not retained on Android and are not shown).
   The Android map refreshes on selected events only, so the bar's 30 s tick ALSO
   invokes the parent's existing Android recording reconcile via callback — counts
   can't stay stale while focus is parked. `SCHED n` (`_scheduledCount`), status
   text = `_chipMessage` when `_chipState` is not hidden (labelled STATUS — the
   chip system speaks for guide/maintenance/refresh alike; the floating chip
   stays), clock (30 s `Timer.periodic` owned by the bar, cancelled on dispose).
2. **`IptvConsoleTimeline`** (new, display-only) under the filter line, inside the
   Offstage guide subtree: −1 h → +5 h window, hour ruler, hairline programme cells,
   NOW cell amber-tinted, **REPLAY tags only** (from `EpgProgramme.hasArchive` —
   data the schedule already carries), amber playhead. **No REC tags in v1**
   (round-2 P2): the results state holds only `_scheduledCount`, not a
   per-programme schedule snapshot, so a display-only timeline cannot truthfully
   tag scheduled programmes — recording affordances stay on the stage's TODAY
   list exactly as shipped, and per-programme REC tags are follow-up work gated
   on retaining normalized schedule records. Repaint isolation (P2-10):
   programme cells live under their own `RepaintBoundary` and rebuild on
   channel/EPG change AND on programme-boundary fires (the reclassification
   moment); only the 30 s playhead tick stays isolated to the overlay; ALL timers cancel while the strip is hidden (no EPG → zero-height,
   height gate, or schedule pane open — the widget receives `suspended:
   _scheduleChannel != null`). Same ≥4-rows/height gate as the hero.
3. **Rows** (`style` on `IptvChannelRow`): mono channel number, square hairline
   `_LogoChip` variant, SpaceGrotesk name, now/next line, ticked meter (10 fixed
   segments, plain Rows). Column budget (P2-5): res + meter + end-time render INSIDE
   the flexible middle section (a right-aligned cluster after the EPG text), so the
   existing trailing controls (schedule icon / favorite target / HOLD-OK indicator)
   keep their exact layout. Row width for the drop rules comes from the PARENT: the
   grid delegate math at `iptv_results_view.dart:5938-5960` already computes column
   count and cross extent, so the list passes the resulting tile width into
   `IptvChannelRow` (a row's own `MediaQuery` reports the window, not the tile —
   round-2 P2). Under 640 px of tile width the end-time column drops first, then
   the meter. Focus = amber corner brackets via `foregroundPainter` on the focused
   row only + 5% amber tint.
4. **Rail** (`style`): text-first rows, mono counts, amber square focus bullet,
   mono micro-caps headers.
5. **Stage** (`style`): corner-bracket monitor frame + `MONITOR · PVW` caption, mono
   clock line + amber elapsed bar, mono text commands (`WATCH` filled / `● REC`
   red-outline / `♥ FAV`), TODAY schedule in mono/grotesk, NOW in amber.

## Phase order & verification gates

- **A** pref + tokens + fonts + settings → `flutter analyze` clean; `flutter test`
  no NEW failures (record the pre-existing baseline first); macOS debug build runs;
  cockpit visually unchanged with pref unset and with `command`.
- **B** edition → same gates + desktop visual pass + DPAD checklist above.
- **C** console → same gates + desktop visual pass + DPAD checklist.
- Codex review after each phase diff; P1 findings fixed before proceeding. Final
  full-diff Codex review iterated to zero P1s.
- Everything stays **uncommitted**.

## Risks & mitigations

- `iptv_channel_row.dart` is the 50 k-catalog hot path → token lookup resolved once
  per build into locals; no per-frame allocations added; bracket painter exists only
  on the focused row.
- Timers: the edition hero owns one 60 s reconciliation ticker; console owns the
  status-bar clock (30 s), the playhead overlay tick (30 s) and the timeline's
  one-shot programme-boundary timer. Every one cancels when its widget is hidden
  (height gate, no EPG) or suspended (schedule pane open); `command` mounts none.
- Two-pane settings index arithmetic is the fiddliest edit (hardcoded indices at six
  sites) — done as its own commit-sized step inside Phase A with a manual TV-flow
  checklist (UP/DOWN through every rail entry, RIGHT into each pane, BACK out).
- Hero/timeline vertical space: height gates guarantee ≥4 grid rows; small desktop
  windows simply never show the inserts.
