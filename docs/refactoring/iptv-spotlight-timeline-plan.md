# IPTV Spotlight live timeline refactor — plan

Written 2026-10-06 on `refactor/codebase` at `49c53e2e8`. The target file is
unchanged since that base. Follow [AGENTS.md](../../AGENTS.md).

Read first: [stremio-tv-tuner-plan.md](stremio-tv-tuner-plan.md) (closest
analogue, merged at `ecc17c59`: a public controller bound to a private State,
the widget and State kept in the facade, a typed widget view implemented by
the State through a registered header addition, owner record + cached
sections with `_deps` live getters, the opt-in occurrence binder with
`record_owners`/`record_fields`, step-aware destinations through
`validate_with_context` and `scaffold_activation_step`, the CI-listed
source-contract runner, the analyzer inventory). Then
[debrify-tv-plan.md](debrify-tv-plan.md) and
[spotlight-board-plan.md](spotlight-board-plan.md) for the shared technique.
This plan reuses their checker (`check_verbatim_moves.py` →
`check_settings_moves.py`), callback-identity tooling, `suite_evidence.py`
evidence, real-config fixtures, original-code worktree proofs with
assertion-failing mutation negatives, the per-entry wiring checklist and the
Linux-golden handoff, and states only what differs. A facts inventory
accompanies this plan and is copied into the dependency report at step 0.

**Execution.** Own git worktree `../debrify-wt/iptv-spotlight-timeline` on
branch `refactor/iptv-spotlight-timeline`, cut from `refactor/codebase` at
`49c53e2e8`, in parallel with four other refactors (Premiumize files,
AllDebrid files, IPTV settings two-pane, recordings page; none touches this
file or `lib/widgets/iptv/spotlight/`). Run `flutter pub get` first; the
lockfile must not change (Flutter 3.44.8 / Dart 3.12.2). Commit after every
step; never push or switch branches; gate commits contain `gate`. Evidence
goes only under `<git-common-dir>/refactor-evidence/iptv_spotlight_timeline/`.
Every manifest run passes an isolated `--parser-package` under the ignored
`.dart_tool/iptv_spotlight_timeline_parser/` (delete `*.dill` in copies).
Original proofs use a detached worktree under
`.dart_tool/iptv_spotlight_timeline_original/`. `suite_evidence.py` runs are
serialized in this worktree with `--no-pub` and an explicit `--concurrency`
recorded in the env file. Load-sensitive flakes (UDP remote pairing, Xtream
ingest, the catalogs MDB refresh, WebDAV shard, the 180 ms PIN test) are
rerun in isolation and recorded as a NOTE, never allowlisted. Every new
self-test and checker must also pass from a fresh normal `git clone` (where
`.git` is a directory) after `flutter pub get`; nothing copies `.git` as a
file (`gitdir: $(git rev-parse --absolute-git-dir)` if a fixture needs git).

## Goal

`lib/widgets/iptv/spotlight/spotlight_live_timeline.dart` is 2,304 lines and
**already formatter-clean** (no format commit): 13 imports, three public
typedefs, the public `SpotlightTimelineEntryKey`, `SpotlightTimelineEntry`,
`SpotlightTimelineSelection`, `IptvSpotlightTimelineController`,
`SpotlightProgrammeGeometry`, two `@visibleForTesting` top-level functions
(`spotlightProgrammeGeometry`, `spotlightRulerMarks`), the
`SpotlightLiveTimeline` widget, two private enums, two private value
classes (`_GuideSnapshot`, `_LoadToken`), the 1,773-line
`_SpotlightLiveTimelineState`, and three private widgets (`_RulerMark`,
`_GuideMessage`, `_ChannelMark`). It is the IPTV Spotlight live EPG lane: a
fixed identity column beside a pannable epoch-windowed programme track, one
`FocusNode` driving a logical cursor (identity / retry / programme lanes)
over a lazy channel list of up to ~50k rows, viewport-settled schedule loads
with stale-result rejection, a 30 s clock with a 30 min guide refresh, a
follow-now window, a Now button, hold-OK channel actions, pointer
tap-before-activate with hover dwell, wheel/drag panning and an imperative
controller for the surrounding Browse shell.

Split it into a new feature, `lib/features/iptv_spotlight_timeline/`,
**moving code verbatim**. Unchanged: the element tree, keys, `const`
placement, `RepaintBoundary`s, focus, build order, timers and the State's
lifecycle.

**Why a new feature behind a facade.** The facade at the original path keeps
both production importers (`lib/features/iptv/presentation/legacy_iptv/iptv_spotlight_content.dart:12`,
`iptv_focus_state.dart:4`) and all tests compiling unchanged. The name
`iptv_spotlight_timeline` keeps it out of `lib/features/iptv/`, whose
`p2_iptv` theme surface glob (`lib/features/iptv/presentation/*.dart`,
`legacy_iptv/*.dart`) would otherwise start measuring this code: today the
file is outside every measured surface (`p2_iptv` matches
`lib/widgets/iptv/*.dart`, one level only), and the move must keep it so.
Cross-feature imports between `iptv` and `iptv_spotlight_timeline` are
forbidden except `models/` (none planned); `iptv` keeps importing the facade.

**Temporary exceptions and their exits.**

| Exception | Exit |
| --- | --- |
| Bridge files importing `lib/services/iptv_epg_service.dart` for the `EpgProgramme` type, and `lib/services/debrify_image_cache.dart` for the channel logo cache | An EPG programme model outside the service (data layer) and an injected image-cache contract |
| Public entry/selection types and the geometry functions living in the bridge (they name `EpgProgramme`; the geometry functions must share a library with their only caller, D3) | The same EPG model extraction; geometry leaves the bridge with its caller |
| Facade-owned widget properties reached through the typed view (tuner Technique 5) | Riverpod timeline state keyed by source/session |
| Lazy `_holdOk` retained on the facade State, reached by sections through a `_deps` live getter (D4) | A TV activation controller owned by the timeline's application state |
| Legacy English text ('Live television programme guide', 'Now', 'Loading guide…', 'Guide unavailable  ·  Retry', 'Tap again to watch', 'NOW', weekday/month names, semantics hints, …) | Localization migration |

## Public surface (unchanged)

Stay **in the facade, byte-identical** (docs, field order, constructor):
`IptvSpotlightTimelineController` (98–134; it names the private State and
calls its private `_hasFocus`, `_restoreFocus`, `_focusFirstChannel`,
`_focusChannelAt`, `_focusChannel`, `_attach`/`_detach`) and
`SpotlightLiveTimeline` (211–294; `createState` names the private State).
`_SpotlightLiveTimelineState` stays in the facade with its verbatim lifecycle
and gains **five retained forwarders** for the controller:
`bool get _hasFocus => _owners.hasFocus;`,
`bool _restoreFocus() => _sections.selection.restoreFocus();`,
`bool _focusFirstChannel() => _sections.selection.focusFirstChannel();`,
`bool _focusChannelAt(int index) => _sections.selection.focusChannelAt(index);`,
`bool _focusChannel(IptvChannel channel) => _sections.selection.focusChannel(channel);`.

Move out and are **re-exported by the facade** with an exact `show` list
(names and behaviour unchanged): the three typedefs,
`SpotlightTimelineEntryKey`, `SpotlightTimelineEntry`,
`SpotlightTimelineSelection` (from `spotlight_timeline_entry.dart`), and
`SpotlightProgrammeGeometry`, `spotlightProgrammeGeometry`,
`spotlightRulerMarks` (from `spotlight_timeline_track.dart`, D3). The facade
also imports what its own declarations name. Every importer keeps compiling
with no import change; the re-export adds no analyzer diagnostic (probe:
exporting a `@visibleForTesting` member is not a use).

## What it contains

See the facts file (copied into the dependency report). Summary of the
State's responsibilities, original lines:

| Lines | Area |
| --- | --- |
| 355–402 | 4 statics, 19 instance fields, lazy `_holdOk`, `_focusNode`, `_rowHeight` (the only State-`context` read) |
| 404–501 | `didChangeDependencies`, `initState` (30 s clock, listener, post-frame autofocus/announce), `didUpdateWidget` (source/context/window/size branches), `dispose` |
| 503–547 | Follow-now window default and the 30 s clock tick with the 30 min guide refresh |
| 549–736 | Entry projection, viewport settle and visible range, visible-row loads, eviction, schedule load with stale-token rejection, retry |
| 738–1046 | Focus change, key handling, vertical/horizontal cursor moves, programme lookup, window reveal, reconcile, row reveal, activation |
| 1048–1216 | Focus handoff for the controller, taps, identity/programme selection, selection announcement, hover dwell |
| 1218–1285 | Wheel and drag panning, the Now button keys, jump to now |
| 1287–1518 | `build`, ruler, ruler geometry helpers, empty state |
| 1520–2027 | Rows: row, identity cell, programme track, programme cell, badge fit |
| 2029–2125 | Playhead, time/day formatting |
| 2128–2304 | `_RulerMark`, `_GuideMessage`, `_ChannelMark` |

## Contracts that must not change

Pinned by source guards (whole bodies, comments included, through a
per-declaration source reader `test/support/iptv_spotlight_timeline_source.dart`
that reverses manifest renames and registered substitutions) and, where
observable, by behaviour tests. Most behaviour already has coverage in
`test/widgets/iptv/spotlight/spotlight_live_timeline_test.dart` (≈ 40 cases,
which stays unchanged and must keep passing); step 0 inventories that
coverage per contract and adds characterization only for the gaps.

1. **Lifecycle (facade, verbatim with receiver-only qualification).**
   `initState`: `super` → `now = widget.now()` → window start
   (`initialWindowStart ?? defaultWindowStart(now)`) → follow-now → cursor
   time → last refresh → `controller?._attach(this)` →
   `verticalController.addListener(onViewportMoved)` → 30 s periodic clock →
   post-frame (`!mounted` return; arm load; autofocus request; announce).
   `didChangeDependencies`: `super` → arm load → reveal cursor row.
   `didUpdateWidget`: controller rebind only when `!identical`; the
   source-change (`sourceId`/`loadGeneration`/`!identical(channels)`) and
   context-change reset block in its order (cancel pointer, tapped cell, hold
   reset, guides, pending, refresh time); cursor clamp; lane reset rules; the
   two `initialWindowStart` transitions; re-arm conditions (source, context,
   `height`, `rowHeight`, `rulerHeight`, `viewportSettleDelay`); post-frame
   (mounted; announce only on source change; reconcile).
   `dispose`: viewport settle cancel → clock cancel → pointer settle cancel →
   `verticalController..removeListener(onViewportMoved)..dispose()` →
   `_holdOk.reset()` → owned node dispose → Now node dispose →
   `controller?._detach(this)` → `super.dispose()`.
   **Callback identity:** `_onViewportMoved` at add (420) and remove (494)
   keeps one receiver path and member (`_sections.loading.onViewportMoved`,
   sections cached once per State); `onFocusChange: _onFocusChange` and
   `onKeyEvent: _onKeyEvent` (build), `onKeyEvent: _onNowKeyEvent` and
   `onPressed: _jumpToNow` (ruler), and `_holdOk`'s `onTap: _activateCursor`
   become the owning section's tear-offs; `controller._attach(this)`/`_detach`
   pass the facade State.
2. **Hold-OK.** `_holdOk` stays a lazy `late final` on the State: created on
   its first access at the original site (whichever of didUpdateWidget,
   focus loss, a key event, the Now button's focus change or dispose comes
   first), never at construction or composition. Its `onTap` is the cursor
   section's `activateCursor` tear-off; its `onHold` reads the live cursor
   row and `widget.onChannelActions` when it fires. Sections reach it only
   through `_deps.holdOk()` evaluated at each original site (D4). Tests: OK
   short press activates once; hold ≥ 600 ms calls `onChannelActions` once
   with the cursor entry; repeats swallowed; focus loss and source change
   reset a pending hold; no hold handling without `onChannelActions` or in
   the retry lane.
3. **Viewport-settled loads.** `_armViewportLoad` cancels the previous
   timer, bumps the generation and loads after `viewportSettleDelay` only if
   mounted and still current; only visible **live** rows load; a row with a
   ready/error snapshot for the current context version is skipped; an equal
   pending token is not re-sent; a loading snapshot is published with one
   `setState` per batch; `_visibleRange` uses the scroll offset/extent (or
   `_viewportHeight` before clients) and `_rowHeight`. Eviction keeps
   `max(8, 2 × visible)` rows each side plus the cursor row and drops their
   pending tokens. A large lazy list is never iterated (existing test).
4. **Schedule results.** Zero/negative-duration programmes dropped; sorted by
   start then stop; stored unmodifiable. `_accepts` rejects after unmount, an
   older generation, a changed context version, a non-current pending token,
   a changed source id or load generation, an out-of-range or mismatched
   ordinal, or a non-identical channel at the ordinal; a rejected result
   removes its own pending token only when it is still current. On error
   the row shows the retry state, and a programme cursor on that row falls
   back to identity with one announcement; otherwise reconcile.
   `_retry`: generation `0 → 1` only when nothing was ever armed, leaves the
   retry lane (with announcement) when the cursor sat on it.
5. **Clock.** 30 s periodic; follow-now re-anchors the window to the
   half-hour default and, when no programme is selected, the cursor time;
   after 30 min the guides/pending are cleared, a retry lane resets
   (announced) and loads re-arm; one `setState` per tick.
6. **Keys (consuming `Focus.onKeyEvent`, never a `KeyboardListener`).** Only
   with primary focus. Activate/Space with `onChannelActions` and not in the
   retry lane go to the hold handler; otherwise only KeyDown/KeyRepeat are
   handled; Home jumps to now; an activation repeat is swallowed (never
   stacks routes); arrows repeat. Vertical: Up at row 0 goes to the Now
   button when not following now, else `onExitUp` (ignored when null); Down
   at the end is handled; programme lane keeps the nearest programme by the
   cursor time, drops to identity on an empty guide or a cached error, keeps
   the lane while the target row is still loading; retry lane drops to
   identity when the target has no error. Horizontal: identity Left exits
   (`onExitLeft`, ignored when null); identity Right enters retry on error,
   else the nearest programme (window revealed), else handled; programme
   Left at the first cell returns to identity; Right at the last is handled;
   reveal uses a 12 % lead and leaves an oversized programme that already
   crosses the window clipped in place.
7. **Now button.** Shown only when not following now (else the channel
   count); its own consuming key handler: activation on KeyDown jumps to now
   (repeats/ups handled, no action); Down/Right restore the guide cell;
   Up/Left exit when callbacks exist; focus gain cancels pointer dwell,
   resets the hold and clears the tapped cell; every focus change
   `setState`s. Jump to now: follow-now on, default window, cursor time now,
   identity lane, then `_restoreFocus`.
8. **Pointer.** `selectBeforeActivate` tap-then-tap with `_lastTappedCell`
   identity per (entry key, programme start); hover dwell 375 ms that
   rejects a changed source id, load generation, context version,
   non-identical channel list, out-of-range row or recycled channel; exit
   cancels; long press selects then calls `onChannelActions`; wheel picks
   the dominant axis with the Shift + physical-mouse swap only, claims the
   signal through `pointerSignalResolver` and pans; drag start cancels the
   dwell; drag update pans by `-dx`; panning clears the tapped cell and
   leaves follow-now. `fromPointer` is true only for pointer-originated
   announcements.
9. **Controller.** One timeline at a time (assert); `restoreFocus` keeps the
   exact cell (programme revealed), requests focus, reveals the row and
   announces; `focusFirstChannel`; `focusChannelAt` bounds-checks without
   reading other rows; `focusChannel` tries the cursor row, then only the
   visible range by identity; all return false when unmounted or empty;
   `hasFocus` is the State flag.
10. **Selection announcements.** `onSelectionChanged` gets the cursor entry
    and, only in the programme lane, the programme whose start equals the
    selected start (a refreshed instance replaces the old one).
11. **Paint.** Identity width `min(widget, 45 % of width)`; row height grows
    with the text scaler exactly as `_rowHeight` computes; identity/
    programme visuals (focus fill/ink, selected tint, accent borders,
    130 ms `AnimatedScale` 1.018 and `AnimatedContainer`, NOW badge only for
    programmes ≥ 25 min, replay icon for past archived programmes, past
    dimming); ruler day heading ('Today' or weekday), local half-hour marks,
    playhead only inside the window with `timelineWidth > 0`; every
    `ValueKey` (`spotlight-live-timeline-rows`, `spotlight-jump-to-now`,
    row/identity/programme/position/loading/error/empty/window-empty keys);
    semantics labels, hints, `focused`/`selected` flags; empty and VOD
    states. Colours come from `IptvStyleTokens.spotlight` and the three
    State palette constants only.
12. **No new responsibilities.** No feature or facade file imports a player,
    `media_kit`, `player_launch`, `video_player_launcher`, `http`,
    `shared_preferences`, `sqflite`, storage or profile services, or reads
    `AppThemeScope`; schedules come only from the injected
    `scheduleLoader`. No `KeepAlive`, `Opacity`, new `Builder` or wrapper
    widget, no `const` change (59 `const ` lines), no new `GlobalKey`.

## Destination layout

All under `lib/features/iptv_spotlight_timeline/presentation/`. Each file is
at most 500 formatted lines; no size exception is planned (estimates below,
settled by the step 0 dependency report).

**Outside the bridge (service-free):**

- `spotlight_timeline_parts.dart` — `_RulerMark` →
  `SpotlightTimelineRulerMark`, `_GuideMessage` →
  `SpotlightTimelineGuideMessage`, whole and unchanged except names (≈ 140).
- `spotlight_timeline_palette.dart` — `SpotlightTimelinePalette` holding the
  three State colour constants as `static const background`,
  `identityBackground`, `timelineBackground` with their original
  initializers (≈ 10). Every reader qualifies them
  (`SpotlightTimelinePalette.background`), a registered static receiver path
  (the merged-detail `original_static_receivers` / Stremio TV static-rename
  precedent; D5).

**`legacy_iptv_spotlight_timeline/`** (the bridge; exact path in the guard):

- `spotlight_timeline_entry.dart` — the three typedefs and the three public
  entry/selection classes, verbatim (≈ 100).
- `spotlight_timeline_guide_models.dart` — `_CursorLane` →
  `SpotlightTimelineCursorLane`, `_GuideStatus` →
  `SpotlightTimelineGuideStatus`, `_GuideSnapshot` →
  `SpotlightTimelineGuideSnapshot`, `_LoadToken` →
  `SpotlightTimelineLoadToken`, verbatim except names (≈ 65).
- `spotlight_timeline_owners.dart` — `SpotlightTimelineOwners`: the 19
  instance fields renamed by dropping the underscore (`ownedFocusNode`,
  `nowFocusNode`, `verticalController`, `guides`, `pendingLoads`,
  `windowStart`, `followNow`, `lastGuideRefreshAt`, `viewportSettle`,
  `clockTick`, `pointerSettle`, `requestGeneration`, `viewportHeight`,
  `cursorRow`, `cursorLane`, `selectedProgrammeStartMs`, `cursorTimeMs`,
  `hasFocus`, `lastTappedCell`), declaration order and initializers
  verbatim (`late` kept), created **eagerly** as a facade field initializer
  (same construction timing as the State's own initializers today). Holds
  only declarations and initializers.
- `spotlight_timeline_widget_view.dart` — abstract
  `SpotlightTimelineWidgetView`, one typed getter per widget property that
  moved code reads (21, facts file).
- `spotlight_timeline_dependencies.dart` — `SpotlightTimelineDependencies`:
  `view`, `owners`, `context()`, `mounted()`, `setState` (the State's own
  tear-off), `holdOk()` (D4), `sections()`; and
  `spotlight_timeline_sections.dart` — `SpotlightTimelineSections`, which
  builds every section in its constructor in a fixed order; section
  constructors only store `_deps`.
- Sections (each `final SpotlightTimelineDependencies _deps;` plus **only the
  one-line getters it uses** among `SpotlightTimelineWidgetView get widget =>
  _deps.view;`, `_owners` and `_sections`; an unused getter would be a new
  `unused_element`):
  - `spotlight_timeline_guide_loading.dart` — `SpotlightTimelineGuideLoading`:
    `_rowHeight` (→ `rowHeight`, its two comment lines travel), `_entryAt`,
    `_onViewportMoved`, `_armViewportLoad`, `_visibleRange`,
    `_loadVisibleRows`, `_evictDistantRows`, `_loadSchedule`,
    `_removePendingIfCurrent`, `_accepts`, `_retry`, `_hasGuideError`,
    `_programmesForRow` (≈ 240).
  - `spotlight_timeline_window.dart` — `SpotlightTimelineWindow`:
    `_guideRefreshInterval` (static, read bare here only),
    `_defaultWindowStart`, `_onClockTick`, `_ensureProgrammeVisible`,
    `_handlePointerSignal`, `_panTimeline`, `_onNowKeyEvent`, `_jumpToNow`
    (≈ 170).
  - `spotlight_timeline_cursor.dart` — `SpotlightTimelineCursor`:
    `_onFocusChange`, `_onKeyEvent`, `_moveVertical`, `_moveHorizontal`,
    `_nearestProgramme`, `_distanceToProgramme`, `_selectProgrammeValue`,
    `_reconcileProgrammeCursor`, `_revealRow`, `_activateCursor`,
    `_activateIdentity` (≈ 300).
  - `spotlight_timeline_selection.dart` — `SpotlightTimelineSelectionActions`:
    `_focusNode` (→ `focusNode`, still `=> _owners.ownedFocusNode`),
    `_restoreFocus`, `_tapIdentity`, `_tapProgramme`, `_focusFirstChannel`,
    `_focusChannelAt`, `_focusChannel`, `_selectIdentity`,
    `_selectProgramme`, `_announceSelection`, `_armPointerSelection`,
    `_cancelPointerSelection` (≈ 200).
  - `spotlight_timeline_frame.dart` — `SpotlightTimelineFrame`: `build` (as
    `Widget build(BuildContext context)`, lexical `context` unchanged),
    `_buildRuler`, `_buildEmpty`, `_buildPlayhead`, `_dayHeading`,
    `_weekday` (static, bare) (≈ 345).
  - `spotlight_timeline_rows.dart` — `SpotlightTimelineRows`: `_buildRow`,
    `_buildIdentity`, plus `_ChannelMark` → `SpotlightTimelineChannelMark`
    (whole class; its service import is why it lives in the bridge) (≈ 260).
  - `spotlight_timeline_track.dart` — `SpotlightTimelineTrack`:
    `_rulerMarks`, `_timeX`, `_buildProgrammeTrack`, `_buildProgrammeCell`,
    `itemCanFitBadge`, `_formatTime` (static → `formatTime`); plus the
    top-level `SpotlightProgrammeGeometry`, `spotlightProgrammeGeometry`
    and `spotlightRulerMarks`, verbatim with their docs and annotations
    (D3) (≈ 450).

Members called only inside their own section keep their private names;
cross-class members get manifest-listed public names. Cross-section statics:
the frame's playhead reads `SpotlightTimelineTrack.formatTime(...)` (one
registered static receiver path); the three palette colours as above.

**The facade** holds: imports; the two `export … show …` directives; the
controller and widget byte-identical; `_SpotlightLiveTimelineState` with the
header addition `implements SpotlightTimelineWidgetView`, the eager owners
field, the cached sections (nullable cache, `??=` getter; never `late`,
never per build), the lazy `_holdOk` with receiver-qualified initializer
(`onTap: _sections.cursor.activateCursor`, `onHold` reading
`_sections.loading.entryAt(_owners.cursorRow)` and
`widget.onChannelActions`), the verbatim lifecycle with receivers, the
one-line `build` forwarder (`=> _sections.frame.build(context)`), the five
controller forwarders and the 21 view getters (`@override T get p =>
widget.p;`, read live on every call).

**Cap.** Measured over every physical line: target **360**, hard maximum
**400** (imports ≈ 12, exports ≈ 14, controller 37, widget 84, State header
and composition ≈ 25, `_holdOk` 7, lifecycle 98, `build` 2, forwarders ≈ 12,
view ≈ 50, blanks). Progress records `wc -l` and an AST-range breakdown
summing to it from step 2. Above 400 is a plan failure to report, not a new
exception; the cap becomes the measured value at step 3 and
`TEMP(iptv_spotlight_timeline)` rejection enforces it.

**Guard registration** (`check_search_architecture.py`, step 1):
`iptv_spotlight_timeline` in `FEATURES` (on its own `FEATURES += (…)` line,
the catalogs/settings_widgets precedent, for clean union merges);
`IPTV_SPOTLIGHT_TIMELINE_FACADE`/`_BRIDGE`/`_COMPLETE = False` (→ `True` at
step 3) and `_FACADE_CAP`; the bridge in `LEGACY_PLAYBACK_BRIDGES` (still no
`http`, `shared_preferences`, `sqflite`); 500-line caps with an empty
`_SIZE_EXCEPTIONS`; no facade back-import; no service import outside the
bridge; the playback/storage/keep-alive bans; bans in both directions
between `iptv_spotlight_timeline` and `iptv` except `models/`; at completion
the facade in `main()` and `COMPOSITION_ROOTS` (composition root comment),
cap and `TEMP` rejection. Real-checker tests on a temporary tree copy must
reject: a missing facade, the facade at cap + 1, `TEMP(...)` in the facade or
outside the bridge, a service import outside the bridge (e.g. the parts file
importing `iptv_epg_service.dart`), a facade import from the feature, a
feature file importing `lib/features/iptv/presentation/…`, and any
destination at 501 lines; the unmodified tree passes. These live in
`dev/tool/iptv_spotlight_timeline_architecture_test.py` and run at every
step and in CI.

## Technique

As in the tuner plan (Techniques 2–8 there), with these differences:

1. **No format commit.** R is the base file itself (formatter-clean, proven
   by `dart format --output=none --set-exit-if-changed` at step 0). Step 0's
   checkpoint (b) leaves application files equal to R; Progress proves
   `git rev-parse <b>:lib` = `<base>:lib` (and `pubspec.yaml`,
   `pubspec.lock`).
2. **Strict-lint baseline and rename probe** (tuner Technique 2). Expected
   inventory: `use_key_in_widget_constructors` for the newly public
   `SpotlightTimelineRulerMark` and `SpotlightTimelineChannelMark` (no key
   parameter today; **no key is added**), any
   `library_private_types_in_public_api`, any change in
   `use_build_context_synchronously` from `context`/`mounted` becoming
   `_deps.context()`/`_deps.mounted()` (only `_rowHeight` reads the State
   context; no member awaits then uses it), and `invalid_use_of_visible_for_testing_member`
   must stay **absent** (D3 probe). Baseline and probe combine by maximum
   per identity. Any surviving warning gets an `analyzer_allowlist.txt`
   entry by destination identity in the commit that creates its file (none
   expected).
3. **Live getters, `setState` and the hold.** Sections reach the State's
   `context`, `mounted`, `setState` and `_holdOk` only through
   `_deps.context()`, `_deps.mounted()`, `_deps.setState(...)` and
   `_deps.holdOk()`, evaluated at the original site, never cached. The one
   State-context site is `_rowHeight` (396). Every builder `context`
   parameter (build 1288, LayoutBuilders 1305/1328, `itemBuilder` 1348) is
   **declared but never read**, so the file has no production lexical
   context read to substitute: the source contract pins those unused
   parameters (names and positions), the real-body proofs include
   `_rowHeight`'s one State read becoming `_deps.context()`, and any
   lexical-read fixture is a synthetic checker fixture, classified as such
   (round 1 P2-3).
   **The hold (round 1 P1-1).** No existing mechanism expresses a section
   reading a *retained State field* through a `_deps` call:
   `live_getter_aliases` requires a retained facade getter with a body
   (`check_settings_moves.py:1090`) and the binder counts the call as extra
   occurrences. The plan therefore adds one **opt-in** key, used only by this
   manifest (absent = today's behaviour, every other manifest's adapter
   output and self-tests byte-identical):
   `retained_field_live_getters: {"holdOk": "_SpotlightLiveTimelineState._holdOk"}`.
   - Checker (`normalize`): exactly the token sequence `_deps . holdOk ( )`
     normalizes to the original field token `_holdOk`; nothing else does
     (`_deps.holdOk` without the call, `(_deps.holdOk)()`, `deps.holdOk()`,
     `_owners.holdOk`, a local bound to the call). The retained field row
     stays in the facade with its initializer compared verbatim modulo the
     registered receivers.
   - Binder: an original `_holdOk` occurrence (lexical, unbound) aligns with
     the destination `_deps.holdOk()` selector+invocation as **one**
     occurrence, keeping the original role (the field read that is then
     dereferenced); occurrence counts stay equal.
   - Negatives (each must fail through the real checker and binder): a
     section caching the hold in a local or field and reusing it; a
     wrapper (`final h = _deps.holdOk; … h()`); a delayed invocation (the
     tear-off passed to a callback); a second `TvHoldOk` constructed in a
     section; `_owners.holdOk` (replacement ownership); the facade making
     `_holdOk` eager (non-`late`, or assigned in `initState`/composition);
     the composition passing `holdOk: () => TvHoldOk(...)`.
   - The composition passes exactly `holdOk: () => _holdOk` (pinned by the
     source contract), so each call reads the State's single lazy field.
4. **Owner fields and the occurrence binder** (opt-in reuse; tuner keys
   `record_owners: ["_SpotlightLiveTimelineState"]` and `record_fields`
   listing exactly the 19 instance fields, so the statics
   `_guideRefreshInterval`/`_weekday`/`_formatTime` read bare in their own
   section are not record fields). Every moved field reference is
   receiver-qualified (`_owners.cursorRow`); no section declares an instance
   field besides `_deps`. The file has no local or parameter named like a
   renamed field (facts), and the named-argument labels `windowStart:` at
   1497/1753 are labels, not references; fixtures prove both (a label stays a
   label; a bare `windowStart` read in a section fails). Real moved-body
   proofs before extraction (step 0b, through checker and reader, on a
   scratch tree built from R by the actual manifest moves of
   `_loadSchedule`, `_moveVertical`, `_buildRuler`, `_buildIdentity` and
   `_armPointerSelection`, `_rowHeight`): positives as planned; negatives — a field read
   left bare, a field replaced by a captured local, `_rowHeight`'s
   `_deps.context()` replaced by a cached context, a wrong section receiver for a cross-section
   call, `SpotlightTimelinePalette.identityBackground` swapped for
   `.timelineBackground`, the hold read cached.
5. **Typed widget view** (tuner Technique 5): header addition `implements
   SpotlightTimelineWidgetView` registered for `_SpotlightLiveTimelineState`
   only; each view getter exactly `@override T get p => widget.p;`;
   function-typed properties return the host's function object. R has no
   view, so **identity is proved in the step 0b compiling-composition probe**
   (direct assertions that each view getter returns the identical
   `widget.<p>` object for `onExitUp`, `onExitLeft`, `onChannelActions`,
   `onChannelActivate`, `onProgrammeActivate`, `onSelectionChanged`,
   `scheduleLoader`, `now`, `channels`, with wrapped-getter, cached-snapshot
   and stored-widget negatives) and pinned afterwards by the source contract's
   exact one-line getter scaffolds; ORIGINAL behaviour tests (frozen in (b))
   prove the observable side: replacing the host's callbacks, clock and
   loader on rebuild with the **same channel list** takes effect at the next
   use (round 1 P2-5). `now` is read through the view, so the moved code
never names the `@visibleForTesting` widget field outside the facade's
   library. Each section exposes `SpotlightTimelineWidgetView get widget =>
   _deps.view;`, so every moved `widget.<p>` site stays token-identical.
6. **Callback identity, split by shape** (tuner Technique 7). Direct
   tear-offs and single-call arrow closures: `addListener`/`removeListener`
   of `onViewportMoved`; `onFocusChange`/`onKeyEvent` (build); the Now
   button's `onKeyEvent`/`onPressed`; the hold's `onTap`; `onPointerSignal`
   (×2), `onHorizontalDragStart`/`Update`, the identity/programme/track
   `onTap`, `onEnter`/`onExit`, `onLongPress` closures. Block closures (the
   30 s clock, the viewport settle, the pointer dwell, the
   `pointerSignalResolver` registration, post-frame callbacks, the hold's
   `onHold`, the Now button `onFocusChange`) are covered by whole-body
   comparison, the binder and the context guard with in-body receiver-swap
   negatives (e.g. the dwell's `_owners.pointerSettle` replaced by
   `_owners.viewportSettle`).
7. **Verbatim comments.** The checker compares comments; never reword, move
   or drop one (including `_rowHeight`'s two-line comment, `_evictDistantRows`'s
   `[_accepts]` reference — renamed only through the manifest mapping — and
   every doc comment on the moved public types and functions).
8. **Shape and theme.** The file is in neither `kShapeResidue` nor
   `kExtractedShapeResidue` (6 bare radii, no shape token); the move keeps
   every destination unregistered and the floor/ratchet tests unchanged
   (verify; D6). Theme: no measured surface covers the file or the new
   feature directory; `measure_theme_surface.sh` output is recorded before
   and after and must be identical. `light_ink_inventory.py`: total 774
   sites / 240 primary unchanged.
9. **Re-exports.** The facade's `export … show` lists are exact (six names
   from the entry file, three from the track file) and pinned by the source
   contract; negatives: an extra or missing name, an unrestricted export,
   an export of a section class.

## Steps

| # | Work | Contracts |
| --- | --- | --- |
| 0 | Baseline `base`; lint/rename probes; dependency report; manifest, config, callback sites; harness, characterization tests, source reader, macOS goldens (two reversed-order captures); checkpoint (b); CI list; source-text inventory; Linux capture script | Nothing moves |
| 0b | Independent review (Claude); original-only mutation proofs; compiling-composition probe with the real checker and facade measurement; `base2` at (b) | Nothing moves |
| L | **Before step 1:** Linux originals hash-verified (Claude, Docker), committed separately, Linux golden test made strict | Goldens |
| 1 | Guard registration and architecture test (CI-registered runner); CI format/analyze inputs for the facade and support files plus the analyzer info inventory; parts file; entry file and the facade re-export; guide models (renamed public; the State keeps using them by their new names through type renames). These are whole classes and public types that never read State members. **Full-suite gate 1** | 11, 12, Technique 9 |
| 2 | The whole State body in one step: owners, view (header addition), dependencies, sections aggregator, all seven sections (track with the geometry declarations), composition, `_holdOk` with receivers, verbatim lifecycle with receivers, `build` forwarder, controller forwarders; the palette file is created here with its readers (no unused scaffold in step 1) | 1–12 |
| 3 | Completion: `COMPLETE = True`, facade cap and `TEMP`, `COMPOSITION_ROOTS`, real-checker negatives, final CI verification (format/analyze inputs and the inventory were registered at step 1), final evidence. **Full-suite gate 2** | All |

The geometry declarations stay in the facade through step 1 (their only
callers are State members) and move with the track section in step 2, so
no step ever calls a `@visibleForTesting` function across libraries.

**Why the State moves in one step.** Its members call each other across
every planned section (`build` → loading, cursor, selection, window, rows,
track; cursor ↔ selection ↔ loading ↔ window; lifecycle → loading, window,
selection, cursor). Moving them over several steps would need temporary
facade forwarders and a per-step borrowing map; moving all 58 members, the
19 fields and the 4 statics in one reviewed step avoids both (tuner round 1
P1-2). The step is still verbatim: every leaf is a manifest row, and the
frozen member map (dependency report) assigns each to exactly one
destination. Step 0b's compiling-composition probe builds this exact shape
(all destinations, real bodies, full facade) on a scratch tree, runs the
real checker and the strict analyzer over it, measures the facade, and is
then discarded.

### Step 0

1. **Baselines.** `iptv_spotlight_timeline/base` on the untouched worktree
   head: `suite_evidence.py run` (paths `[]`) plus the whole-repo analyzer
   with tree and SDK provenance.
2. **Dependency report** (`docs/refactoring/iptv-spotlight-timeline-deps.md`):
   for every leaf the destination; reads of `widget` (by property),
   `context` (State or lexical), `mounted`, `setState`, `_holdOk`, owner
   fields, statics, `this`; tear-offs; timer owner; the cross-class call
   graph that decides public names; and a wiring-checklist entry per leaf.
3. **Checker.** `dev/tool/iptv_spotlight_timeline_manifest.tsv` (LF only),
   `iptv_spotlight_timeline_checker_config.json`, real-config fixtures and
   `iptv_spotlight_timeline_checker_test.py` with a `__main__` that parses
   `--parser-package`, runs every fixture and exits non-zero on failure.
   Reuse the tuner's opt-in mechanisms (`validate_with_context`,
   `scaffold_activation_step`, `class_header_additions`, `record_owners`/
   `record_fields`, `occurrence_type_renames` if the binder needs the class
   renames, `byte_identical_declarations` for the controller and widget,
   `lexical_state_setters` if any) through
   `dev/tool/iptv_spotlight_timeline_contracts.py`; add a shared-checker key
   only if none fits, opt-in and keyed by this feature, with every other
   manifest's self-test byte-identical. Rows: **retained** (controller,
   widget, State lifecycle, `_holdOk`), **moved** (every other leaf,
   including the original `State.build`, which moves at step 2 to
   `SpotlightTimelineFrame.build`), **registered forwarders** (the five
   controller forwarders and the exact `build` forwarder (the moved
   `build` row lists `retained_forwarder` in `allowed_edits`)
   `@override Widget build(BuildContext context) => _sections.frame.build(context);`).
   Because the moved `build` loses its `@override` on the plain frame class
   (keeping it would be a new warning), the config registers the existing
   `retained_override_bodies` mechanism (`check_settings_moves.py:438`) for
   the forwarder and `forwarded_annotation_occurrences`
   (`occurrence_field_bindings.py:80`, Stremio TV precedent) so the binder
   drops exactly the original leading `@override` occurrence; the complete
   schedule is proven at S = 0–3 (round 1 P1-2).
   Fixtures at S = 0…3 (steps 0, 1, 2, 3) run the complete checker and reader in one process:
   deleting an activated destination fails; restoring a moved leaf to the
   facade fails; a missing or altered forwarder fails; a retained row moved
   out fails; an absent future file passes. Negatives (each must fail):
   `onViewportMoved` receiver swapped or wrapped at add or remove; a
   reordered or dropped dispose step; the 30 s / 30 min / 375 ms durations
   changed; a `mounted` check dropped from `_accepts` or the dwell; a
   section built per build; the hold created eagerly; a reworded comment;
   a new or removed `const`; the Technique 3–5 and 9 negatives.
4. **Harness** (`test/support/iptv_spotlight_timeline_fixture.dart`): reuse
   the existing test file's channel/programme helpers where possible (copy,
   don't import a test file); a scripted `scheduleLoader` with per-channel
   completers (resolve, fail, hang) recording calls; a large lazy list
   proxy that throws on unexpected index reads; fixed `now` clock and
   `initialWindowStart`; recording host callbacks; `IptvStyleTokens.spotlight`
   only (no app theme needed); pinned `tester.view` size and DPR;
   `debugDefaultTargetPlatformOverride` explicit where pointer kinds matter,
   reset in teardown; `MediaQuery` text-scaler variants; bounded pumps and
   fake time (no `pumpAndSettle` across the 30 s periodic clock). Channel
   logos are null (fallback icon) except one case asserting the
   `CachedNetworkImage` widget fields (`cacheManager`
   `DebrifyImageCache.iptvLogos`, `memCacheHeight` 96, `BoxFit.contain`)
   with a recording image cache that never calls a loader and a tripwire on
   `path_provider`/`sqflite` channels (tuner Step 0.4).
5. **Characterization tests** under
   `test/features/iptv_spotlight_timeline/presentation/legacy_iptv_spotlight_timeline/`,
   written against R and frozen in (b), one group per contract **gap** (the
   step 0 coverage table maps each contract clause to an existing test name
   or a new one); each passes in a detached worktree of (b) before
   extraction. At minimum the gaps: lifecycle orders (timers cancelled and
   listener removed at dispose, controller rebind, `initialWindowStart`
   transitions, size-change re-arm, no re-arm on unrelated changes); the
   30 s tick / 30 min refresh / follow-now anchor; eviction buffer and
   cursor-row retention; the `_accepts` rejection cases that are reachable
   on their own (unmounted completion, a newer generation after a viewport
   move, a superseded pending token, a recycled channel at the same ordinal
   in an in-place list mutation) plus the existing stale-result tests;
   `_retry` generation rule; hold laziness and hold/tap/repeat matrix; the
   Now-button key matrix; `focusChannel` visible-range limit; announcement
   payloads (`programme`, `fromPointer`); playhead visibility; day heading;
   NOW badge threshold; replay icon; semantics labels/hints/flags; VOD and
   empty states; identity-width clamp; text-scaled row height.
6. **Goldens.** Deterministic dedicated scenes captured from (b) (DPR 1.0,
   `en-US`, fixed clock, fixed window, null logos, bounded pumps): TV wide
   1280×360 with identity focus, loaded guides, NOW badge and playhead;
   programme cell focused with a past archived (replay) cell and a
   retry-focused error row; panned window with the Now button and a loading
   row, an empty-guide row, a window-empty row and a VOD row; dense mode at
   text scale 1.3; the empty channel list. Two captures in reversed scene
   order must be byte-identical. Execution captures macOS in (b); Claude
   captures Linux (step L). The existing `iptv_results/spotlight.png` golden
   (macOS and Linux) must keep passing unchanged at every step.
7. **CI list and tooling in CI.** Add the new tests and goldens to
   `ci_behavior_tests.txt`. A Dart test
   `iptv_spotlight_timeline_source_contracts_test.dart` (listed in
   `ci_behavior_tests.txt`) runs `python3 dev/tool/iptv_spotlight_timeline_checker_test.py`
   and, from step 1, `iptv_spotlight_timeline_architecture_test.py`, each
   with an isolated parser package under `.dart_tool/`, and asserts exit 0
   (positive control: a deliberately broken fixture fails the Dart test).
   Add to `ci_behavior_known_failures.txt` only failures `base` actually
   observes for newly listed tests, by identity (none expected).
   **Diagnostic inventory in CI (round 1 P2-4).** `check_analyzer_allowlist.py`
   ignores infos and the tuner's inventory checker is hard-coded to its own
   source and feature, so this plan adds
   `dev/tool/iptv_spotlight_timeline_analyzer_inventory.json` (every info
   identity — rule, enclosing member, message — allowed in the facade and the
   feature, with maxima from the step 0 baseline + probe, by maximum per
   identity) and `dev/tool/check_iptv_spotlight_timeline_analyzer.py`
   (strict rule/symbol/message maxima, zero additions; reuses the tuner
   checker's parsing by import only if that leaves the tuner script
   byte-identical, otherwise a standalone copy). It runs in `checks.yml`
   **after** the general allowlist on the same `analyze.txt`, with its own
   isolated parser package. **The facade and
   `test/support/iptv_spotlight_timeline_*` join the CI format and analyze
   inputs at step 1** (before `| tee`), together with the inventory
   registration, so the facade is analyzed from the first checkpoint the
   inventory covers it (round 2 P2; the facade's `recursive_getters` info
   is recorded by identity). Proofs at every step from step 1: a
   fresh-clone positive, and added-info negatives in **both** the facade
   and a destination (one extra `prefer_const_constructors` each) that
   fail.
8. **Source-text inventory.** `file_size_baseline.txt:26` (lowered from
   step 1, removed at step 2 once the facade is under 500); shape (Technique 8); theme and light-ink
   (Technique 8); verify unaffected: `test/theme/source_guard_test.dart`
   (`lib/widgets/iptv/` frozen-prefix list is a kThemingPrepared
   containment check, no path change needed), `profile_source_guard_test`,
   `stale_runtime_guard_test`, `settings_tv_input_source_guard_test`,
   `iptv_results_source_guard_test`, `storage_member_map.tsv`.
   `checks.yml` (step 1, Step 0.7): the facade and
   `test/support/iptv_spotlight_timeline_*` into the format and analyze
   lists **before `| tee`**, never after; the architecture test and the
   inventory checker as their own steps.
9. **Linux capture script**
   `dev/tool/capture_iptv_spotlight_timeline_linux_goldens.sh`, resolving
   (b) by exact subject and failing unless its application hash matches R
   (the tuner script is the template).

### Step 0b (before any extraction)

Claude reviews step 0 independently. On (b), each ORIGINAL-only mutation must
make a **named assertion fail** (behavioural where observable, otherwise
recorded as source-guard-only with the reason): viewport settle 375 → 0 ms
honoured by the default only; generation check removed from the settle
timer; non-live rows loaded; ready snapshot reloaded for the same context;
eviction buffer 8 → 2 and cursor-row retention dropped; sort by stop first;
zero-duration programmes kept; each `_accepts` clause removed (one mutant
per clause); `_removePendingIfCurrent` removing a newer token; error on the
selected programme row not falling back; `_retry` generation always bumped;
clock 30 s → 1 s; refresh 30 min → 0; follow-now cursor time advanced while
a programme is selected; activation repeat not swallowed; arrow repeat
dropped; Home not jumping; Up at row 0 ignoring the Now button; programme
lane not dropping on cached error; ensure-visible lead 12 % → 0 and the
oversized-clip rule removed; Now button shown while following now; Now
Down not restoring; hold created without `onChannelActions`; hold active in
the retry lane; tap activating on the first tap with `selectBeforeActivate`;
dwell 375 → 0 and each dwell guard removed; wheel Shift swap applied to
trackpads; drag pan sign flipped; `focusChannel` scanning beyond the visible
range; announcement `fromPointer` always false; programme announced outside
the programme lane; identity width clamp 45 % → 50 %; row-height scaler
term dropped; NOW badge threshold 25 → 20 min; playhead shown outside the
window; dispose not removing the listener; `didUpdateWidget` not re-arming
on `rowHeight`; controller not rebound. **Source-guard-only mutants (rounds
1 P3-6 and 2 P1), named in the mutation ledger with the masking reason;
each is pinned by the whole-body source guard instead of a behavioural
assertion:**
- `_armViewportLoad`'s `generation == _requestGeneration` check (the
  previous timer is always cancelled before re-arming);
- `_accepts`' context-version, source-id and load-generation clauses (every
  widget update that changes them also re-arms, so the generation clause
  rejects first), its generation and pending-token clauses under a
  source/context change (pending tokens are cleared too), and its
  negative-index and ordinal-mismatch clauses (`_loadVisibleRows` and
  `_retry` never construct such a token);
- the pointer dwell's source-id, load-generation, context-version and
  channel-list identity guards (any widget update changing them first
  cancels the dwell in `didUpdateWidget`), its `mounted` guard (`dispose`
  cancels the timer) and its negative-row guard (entries are built from
  valid ordinals);
- the explicit `removeListener` in `dispose` (masked by the controller's own
  disposal).
Every listed mutant **not in this ledger** must fail a named behavioural
assertion; the ledger is final at step 0b and any further masked mutant
found then is added with its reason before (b)'s review closes (the
stale-result, cancellation and recycled-row behaviour tests stay). It also runs the
compiling-composition probe (the full step-2 shape with real bodies, under
the strict config, through the real checker CLI with header and re-export
negatives) and records the facade measurement. `base2` at (b) must pass
with only added, passing identities.

### Per step and gates

The tuner procedure applies with `--baseline <R>` and
`--relocate lib/widgets/iptv/spotlight/spotlight_live_timeline.dart=lib/features/iptv_spotlight_timeline/`.
Every step runs: per-entry wiring review before pinning; **all integrated
manifests plus this one** with self-tests and isolated parser packages; the
occurrence-binder, context, callback-identity checks; the per-symbol
relocation comparison (zero additions beyond the probe inventory); the
architecture test; sizes; storage references; shape and theme (unchanged);
CI format and scoped analyze with the allowlist; LF manifests; staged diff;
the existing timeline, results-view and results-golden tests; all
characterization tests; strict macOS and Linux goldens. Gates run serially
on committed trees against the latest base; gate 2 also compares against
gate 1. A first gate failure is investigated as a possible extraction
regression with original/current causal proofs before any flaky
acceptance. Never `--record` or `--update` to accept a regression.

### Integration (Claude)

Claude merges the branch in whatever order the batch finishes, integrating
shared files **semantically, by union**: `check_search_architecture.py`,
`check_settings_moves.py`, `occurrence_field_bindings.py` (every other
feature's behaviour byte-identical), `ci_behavior_tests.txt`,
`ci_behavior_known_failures.txt`, `analyzer_allowlist.txt`, `checks.yml`
(paths before `| tee`), `file_size_baseline.txt`. Then, on the merged
committed tree: every manifest with self-tests, architecture, size, shape
and theme, CI format and analyze, and a full-suite comparison.

## Definition of done

1. **Facade** formatted, within its measured cap (target 360, maximum 400),
   breakdown recorded; it holds the re-exports, the controller and
   `SpotlightLiveTimeline` byte-identical and the State with the header
   addition, eager owners, cached sections, lazy hold, verbatim lifecycle,
   forwarders and view. Both production importers and every test compile
   unchanged.
2. **Guard**: feature, exact bridge, caps (no size exception), facade in
   `main()` and `COMPOSITION_ROOTS`, cap and `TEMP`, the import/playback/
   keep-alive and `iptv` cross-feature bans, each proven through the real
   checker. Every destination is at most 500 lines.
3. **Tests**: all manifests pass with self-tests; every characterization
   test and source guard from (b) passes unchanged; the existing timeline
   and IPTV results tests and goldens pass unchanged; macOS and Linux
   goldens match the originals.
4. **Diagnostics**: no new warning or suppression; every info maps to an
   original or probe-inventoried identity; removed identities listed.
5. **CI**: local CI-equivalent checks pass; behaviour list holds the new
   tests; shape and theme unchanged; light-ink totals unchanged.
6. **Progress** records R, (b) and each step's commit, ownership, exceptions
   with exits, cap arithmetic, and the end-of-series device checklist.
7. **Gate 2** passes against the latest base and gate 1. Every new
   self-test and checker passes from a fresh clone. Then stop and report.

## End-of-series device checklist (no device gate before merge)

- Android TV: DPAD traversal with key repeat over a large lazy channel list
  (thousands of rows), programme-lane LEFT/RIGHT across the window edge,
  Up to the Now button and back, hold-OK (600 ms) channel actions, a single
  activation per OK press, exits to the source rail and the search shell.
- Android TV / tvOS: focus handoff from the Browse shell through the
  controller (`restoreFocus`, `focusChannel`) after search and after
  returning from playback.
- Real EPG providers (XMLTV and Xtream): viewport-settled loads while
  scrolling fast, a guide-context switch, the 30 min refresh with the guide
  left open, retry after a provider error.
- Desktop: mouse wheel, Shift + wheel, trackpad horizontal pan, drag pan,
  hover dwell preview, tap-then-tap; phone/tablet touch tap-preview-tap-play
  and long press.
- Accessibility text scaling on TV and phone.
- Remote CI once Actions is available.

## Explicitly not in scope

`lib/features/iptv/` and every other IPTV file; `IptvEpgService`,
`DebrifyImageCache`, models, `IptvStyleTokens`, `tv_keys.dart`; players and
native code; Riverpod, data contracts, localization; behaviour fixes (below).

## Found, not fixed

1. The 30 s clock calls `setState` every tick while mounted, even when the
   timeline is offstage or nothing changed.
2. `itemCanFitBadge` is a public-named member on a private State (naming
   only).
3. The guide refresh is checked only on clock ticks, so it can run up to
   30 s after the 30 min interval.

4. The cache constructor requests filesystem/cache-repository directories
   before an image loader runs. The artwork fixture blocks those
   construction-only futures; no production cache behavior is changed.
5. Two retries accepted before the next frame can create equal
   same-generation tokens. The first completion may win and remove the
   equal pending token; the later completion is rejected. The ORIGINAL
   loading test pins this behavior.

6. The bundled `Roboto-Regular.ttf`/`Roboto-Bold.ttf` contain HTML rather
   than TrueType data; `FontLoader` silently falls back to the test font.
   The golden fixture uses the existing valid Inter asset under a unique
   test family and checks its header. The application assets stay unchanged.

All six items remain unchanged.

## Decisions taken before design review (Claude, 2026-10-06)

- **D1. No format commit.** The file is formatter-clean at the base.
- **D2. Facade keeps controller, widget and State.** The controller binds
  the private State and calls its private members; the widget's
  `createState` names it. Five one-line controller forwarders keep the
  controller byte-identical (tuner `_focusRealIndex` precedent).
- **D3. Geometry co-located with its only caller.**
  `spotlightProgrammeGeometry` and `spotlightRulerMarks` are
  `@visibleForTesting`; a probe (scratch package, 2026-10-06) confirmed that
  a cross-library call from `lib` reports
  `invalid_use_of_visible_for_testing_member` (a warning) while an `export`
  does not. Both functions and `SpotlightProgrammeGeometry` therefore move
  into the track section's library, whose `_rulerMarks` and
  `_buildProgrammeTrack` are their only callers; the frame calls
  `_sections.track.rulerMarks()`/`timeX(...)`; the facade re-exports the
  three names so the existing unit tests keep importing them from the
  original path. No annotation is removed or added.
- **D4. `_holdOk` stays on the State.** Its initializer closes over State
  members and its laziness is observable in principle (first access may be
  in `dispose`); moving it into the owners record would need the owners to
  see sections or would change its creation time. Sections reach it through
  a `_deps.holdOk()` live getter evaluated at each original site
  (Technique 3).
- **D5. Shared statics.** The three palette colours are read by three
  sections, so they move to `SpotlightTimelinePalette` and every read is
  qualified; `_formatTime` moves to the track (three of four readers) and
  the playhead qualifies it; `_guideRefreshInterval` and `_weekday` stay
  bare in their only section.
- **D6. No shape or theme registration.** The source is unregistered in the
  shape manifests and outside every theme surface; registering destinations
  would create new ratchets not required by the move. The before/after
  measurements prove nothing changed.
- **D7. Seven sections by responsibility.** Loading, window, cursor,
  selection, frame, rows, track — chosen so every file stays under 500
  lines (the rows/track split is forced by their 505 combined lines) and
  each has one reason to change.
- **D8. Entry types in the bridge.** `SpotlightTimelineSelection` and
  `SpotlightProgrammeActivate` name `EpgProgramme`, which is declared in a
  service file, so the entry file imports a service and lives in the
  bridge; exit with the EPG model extraction.


## Round 1 review resolution

1. **P1 — retained hold through `_deps`.** A new opt-in key
   `retained_field_live_getters` in the checker and binder recognises exactly
   `_deps.holdOk()` as the original `_holdOk` read (one occurrence, original
   role); caching, wrapping, delayed invocation, a second hold, replacement
   ownership and eager creation are negatives (Technique 3).
2. **P1 — `build` ownership.** The original `State.build` is a moved row
   (step 2 → `SpotlightTimelineFrame.build`, its row's `allowed_edits`
   including `retained_forwarder`) with an exact registered facade
   forwarder; `retained_override_bodies` and
   `forwarded_annotation_occurrences` handle the dropped `@override`; S = 0–3
   proven (Step 0.3).
3. **P2 — lexical context.** The builder `context` parameters are unused;
   they are pinned, `_rowHeight` joins the real-body proofs, and no
   production lexical-read substitution is claimed (Technique 3).
4. **P2 — info inventory in CI.** A timeline inventory and checker run after
   the general allowlist, with fresh-clone positive and added-info negative
   (Step 0.7).
5. **P2 — view identity.** Proved in the step 0b composition probe with
   wrapped/cached negatives and pinned by exact getter scaffolds; ORIGINAL
   tests cover live callback/clock/loader replacement (Technique 5).
6. **P3 — guard-only mutants** named with reasons (Step 0b).
7. **P3 — month list** quirk removed (it is a `const` list).

## Round 2 review resolution

1. **P1 — unobservable mutants.** The masked mutants (settle generation,
   `_accepts` context/source/load-generation/negative/ordinal clauses, the
   dwell's update-cancelled guards, mounted and negative-row guards,
   `removeListener`) are named source-guard-only with reasons; the
   behavioural matrix is restricted to reachable cases; "every other"
   now means every mutant not in that ledger (Step 0.5, Step 0b).
2. **P2 — facade analysis in CI.** The facade and support files join the CI
   format/analyze inputs at step 1 with the inventory; added-info negatives
   in the facade and a destination (Step 0.7).
3. The `build` row lists `retained_forwarder` in `allowed_edits`.

## Round 3 review resolution

No P1 or P2. P3 (step-table wording) fixed: CI format/analyze inputs and the
inventory are step 1; step 3 is final CI verification.

Round 3 verdict: **No P1s — executable.** Execution may start.

## Progress

### Step 0 — original characterization checkpoint (b)

Execution stays on `refactor/iptv-spotlight-timeline` in the dedicated
worktree. Read all three review-resolution sections. No format commit and
no application move: R is `49c53e2e8081eb7e951c39bafedf90d678a92f55`;
untouched execution HEAD is `cea18cef4e9c615330ab72acaee4a5202367a436`.
`flutter pub get` ran first, without dependency/lockfile changes. SDK:
Flutter 3.44.8, framework `058e0af2c2b57e369d905a03ac9748b0ebf543c6`,
Dart 3.12.2. Evidence is confined to the git-common-directory namespace
`refactor-evidence/iptv_spotlight_timeline/`.

- Full untouched `base`: `python3 dev/tool/suite_evidence.py run
  iptv_spotlight_timeline/base --no-pub --concurrency=2`; paths `[]`, flags
  recorded separately. 12,093 outcomes: 12,032 success, 13 failure,
  28 error, 20 skipped; 1,175 suites. `base.env.json` records unchanged
  start/end HEAD/tree and no untracked inputs. Exact failed identities are
  in `base-summary.json`; none is added to an allowlist. No runner timeout
  occurred. The timeout messages belong to passing deadline/engine/resume
  characterization scenarios; the named load-sensitive suites passed.
- Whole `flutter analyze` baseline: 1,730 diagnostics, with tree/SDK
  provenance in `base-analyze.env.json`; no facade diagnostic under the
  original root options. Strict ORIGINAL/rename probes: zero warnings or
  errors; maxima are one imports-order info and the two newly public,
  unchanged keyless-widget constructor infos. The inventory records
  rule/original-symbol/message maxima; no suppression/key/const change.
- Complete AST-derived dependency/wiring report:
  [iptv-spotlight-timeline-deps.md](iptv-spotlight-timeline-deps.md), 103
  leaves, 19 owner fields, 21 live view properties, 22 callback sites and
  seven independent callback identities. The separately mentioned facts
  file was absent, so the source/AST and observed original test names are
  the evidence. Builder contexts remain named and unused; only `_rowHeight`
  reads State context. Leading ordinary comments are pinned too.
- Original-code behavior/paint/artwork and six strict macOS scenes plus
  existing timeline/results/unchanged IPTV results goldens: 112 tests PASS
  (`step0-original-characterization.txt`). All nine new Dart files are
  formatter-clean; scoped analysis is clean (`step0-tests-analyze-final.txt`).
  The final harness re-run passes all 48 new behavior/golden tests
  (`step0-final-harness-characterization.txt`). First/reversed captures
  have identical six PNG SHA-256 values; strict replay passed. Dedicated
  goldens use valid bundled Inter under a unique test family, check its
  TrueType header and hide the fixture debug banner. Original app font
  assets stay unchanged (found-not-fixed 6). No image-loader/storage work ran
  in the artwork fixture. Construction-only directory futures are blocked
  deliberately.
- Real manifest/checker/reader fixtures and existing-manifest compatibility
  proofs PASS. The timeline CLI `--self-test` passes all 103 leaves and the
  complete real S = 0–3 checker/reader schedules, independent hold/label
  occurrence negatives and seven callback-identity negatives
  (`step0-manifest-self-test.txt`). All 20 other manifests’ complete
  `--self-test` runs pass both before and after the shared changes: 40 test
  runs, byte-identical stdout and occurrence AST digests. Forty separate
  raw adapter comparisons (normal and occurrence mode for all 20) are
  byte-identical, and the adapter source is unchanged
  (`all-manifests-compatibility.json`, `all-manifests-adapter-raw.json`).
  The before helpers are frozen exact HEAD bytes. All manifest invocations
  pass an explicit `--parser-package`; parser packages/kernels are isolated
  below this worktree’s `.dart_tool`, with stale copied kernels deleted.
  `retained_field_live_getters` is the sole new opt-in key, in
  `check_settings_moves.py` and `occurrence_field_bindings.py`; every
  absent-key manifest retains its output. These two additive blocks and
  the seven `ci_behavior_tests.txt` paths require union during integration.
- Fresh normal clone (`.git` directory), after its own `flutter pub get`:
  106 source-contract tests PASS, including the complete checker driver,
  reader and every original body/comment (`fresh-clone-source-contracts.txt`);
  six strict goldens PASS (`fresh-clone-macos-goldens.txt`) and the analyzer
  inventory checker passes. The clone received the owned checkpoint files;
  its `.git` was never copied. Replay from committed (b) remains before
  extraction. The Dart driver’s deliberately
  broken fixture fails its named exit-code assertion
  (`checker-driver-positive-control.txt`), proving CI executes the checker.
  Its 45-minute tooling timeout accommodates the loaded host; application
  fake-time boundaries are unchanged.
- Source-text inventory: unchanged guard/storage/size hashes; original
  facade 2,304 physical lines = 2,272 AST top-level declaration lines + 32
  imports/gaps/trailing lines. State 1,773, controller 37, widget 84. Shape
  remains unregistered (six bare radii). Theme-surface outputs compare
  byte-for-byte and light-ink remains 774 / 240 primary. Existing profile
  source-guard failure is preserved. Size/architecture checks pass without
  changing their registrations; final facade measurement belongs to 0b/2.
- Seven new test paths join `ci_behavior_tests.txt`, including the real
  checker driver; `ci_behavior_known_failures.txt` is unchanged. The CI
  format/analyzer inputs, inventory execution and architecture registration
  remain step 1 as resolved in round 3. The Linux ORIGINAL capture script
  is committed here, resolves (b) by its exact subject, rejects lib/pubspec
  object drift and requires two reversed-order equal captures plus strict
  verification. Linux originals/strictness remain L.

Discarded draft fixture/infra runs are labeled `discarded-*` and are not
accepted evidence. An accidental initial `suite_evidence.py run --help`
invocation was stopped and its exact artifacts moved into this feature’s
namespace; it did not change application input. Characterization assertion
expectations were established against ORIGINAL code before any move, and
original tests/assertions remain untouched. Found-not-fixed items 1–6 are
preserved.

Stop after committing (b), before 0b. Independent review, original-only
mutation ledger, compiling-composition probe, `base2`, Linux originals,
steps 1–3 and both full-suite gates remain pending. Device checks, remote CI
and cross-worktree integration remain pending; nothing is pushed.

### Integrator note: binder qualification

Step 0b pins `occurrence_field_bindings.mandatory_qualification: true`
explicitly in this feature's config. This base defaults to false;
`refactor/codebase` at `9f3755b9b` defaults to true. The explicit value makes
the feature's behavior identical across the integrator's merge. Real
S=2/S=3 fixtures leave `pendingLoads.remove` bare in the moved loading
section and require `Bare owner field reference` from both the complete
checker/reader and the independent binder. Results are recorded with the
completed 0b evidence below.

No rebase or binder-default change is made here. The integrator must union
this feature's named opt-in `retained_field_live_getters` blocks with
edit_profile's `state_classes` / `field_classes`,
`registered_occurrence_substitutions` and `require_live_state_callbacks`
blocks. Those newer keys are not used on this branch's base.

### Step 0b review and composition decisions

Claude's independent ORIGINAL sample was read in full: 50 exact one-line
mutations, 40 behavioral kills and ten survivors. Seven reachable gaps
now have named behavioral assertions against checkpoint (b), including a
failed completion after disposal (a successful completion's thrown
`setState` error is swallowed by the original loader's catch/pending-token
guard). The Now/Down proof checks both restored focus and exactly one
programme announcement; fallback focus traversal alone would mask that
mutant. The lazy-list focus proof asserts `returnsNormally` before checking
the false result, so an offscreen read fails a named matcher. Existing tests
and assertions are retained unchanged.

The complete ledger contains 70 exact edits: 53 behavioral proofs and 17
named source-only scenarios, with masking reasons in the dependency report
and JSON ledger. Two source/context scenarios additionally have independent
behavioral proofs for their generation/pending-token clauses. The redundant
outside-lane announcement guard is justified by the enumerated null-start
invariant; eviction's token cleanup is masked by the prior generation bump.
All original guards remain pinned. The mutation driver runs only behavioral
tests for behavioral cases and only the named whole-body assertion for a
source-only case; compilation errors never count as kills. Resume requires
identical fixture and mutation hashes and a completed positive run.

The full step-2 scratch composition validates the intended public controller
delegates and static `SpotlightTimelineTrack.formatTime` receiver. The
manifest/config now use public `focusFirstChannel`, `focusChannelAt` and
`focusChannel` destination names. The fixture generator selects the static
track receiver for `_formatTime`. These correct the proposed wiring before
any application move; method bodies and behavior are unchanged.

Measured composition: facade 332 physical lines = controller 37 + widget 84 +
State 182 + imports/exports/gaps/trailing 29. All 15 destinations are at
most 500 lines: entry 88, track 444, guide models 64, palette 10, owners 49,
window 162, selection 205, guide loading 241, cursor 297, frame 336, rows
260, parts 134, widget view 28, dependencies 24 and sections 27. Strict
analysis has ten infos and zero warnings/errors. The original/rename
inventory grows to 11 exact maxima to include seven original-symbol
`curly_braces_in_flow_control_structures` infos caused by receiver formatting
and the planned cached `_sections` getter's `recursive_getters` info. No
braces, suppressions or getter behavior are changed to hide these infos.
The probe checks nine identical host objects before/after host replacement,
compiling wrapped/cached negatives, and real CLI header/re-export/stored-view
negatives, including a genuinely unrestricted export.

Accepted ORIGINAL evidence: `step0b-original-positive.jsonl` has 207
passing selected assertions; `step0b-original-mutations.json` records all
70 named failures and fixture/mutation hashes. The first 50 edits match
Claude's exact text, verified in `step0b-claude-exact-mutations.json`. One
owned run was interrupted while improving suite selection; its incomplete
case was rerun and never accepted as a proof. The driver now selects the
named test's suite from the positive run instead of compiling unrelated
filtered suites. Inputs remained frozen across the resumed ledger.

The complete real manifest self-test passes, including mandatory
qualification at S=2 and S=3 through checker/reader and independent binder
(`step0b-checker-frozen.txt`). A fresh normal clone, after its own pub get,
passes all 106 source-contract/checker tests and the final 11 review tests.
The full composition probe and inventory also pass there, with identical
source hashes/measurements; the mutation driver passes its positive run and
mounted/error-fallback negatives there. Fresh-clone evidence is prefixed
`fresh-clone-step0b-*` or `step0b-fresh-clone-*`. The probes are discarded.

Changed tests are formatter-clean and analyzer-clean. Size, architecture
and storage checks pass. Shared helper bytes remain identical to (b), so
the 40 existing-manifest self-tests and 40 raw adapter comparisons recorded
above remain valid. Whole analysis adds no identity: 1,709 emissions versus
1,730 in `base-analyze.txt`. The difference is exactly 21 identical
diagnostic lines emitted twice in the baseline and once now; their tracked
sources remain byte-identical and every unique identity is still present.
The duplicate count evidence and removed emission list are recorded in
`step0b-whole-analyze.env.json` and
`step0b-whole-analyze-removed-identities.json`. Found-not-fixed 1–6,
production library, pubspec objects and app assets are unchanged.

`base2` runs at detached checkpoint (b) with final owned test/tool additions
staged: paths `[]`, flags `--no-pub --concurrency=2`, tested tree
`ba2335e6064bb0c3c09870909824d18ba049e48e`. Its input hashes are in
`base2-input-files.json`; no mutation or application edit runs in that
checkout during the suite. Accepted comparison and the 0b commit follow.

Accepted `base2` (`base2-vs-base.txt`, `base2-summary.json`): 12,197 success,
13 failure, 28 error and 20 skipped outcomes across 1,183 suites. All
12,093 old identities and outcomes are identical; exactly 165 added
identities pass (48 checkpoint behavior/golden tests, 106 source-contract
tests and 11 review tests). No new failure, missing identity, new skip or
allowlist change. Start/end HEAD and tested tree remain stable; SDK matches
`base`. This is the latest baseline for both extraction gates. No
load-sensitive failure or runner timeout required acceptance or an exception.

Fresh complete rerun of all 20 other manifests' self-tests passes with
explicit isolated parser packages. Every stdout and occurrence-adapter
digest is byte-identical to the step-0 pre-opt-in proof
(`step0b-all-manifests-compatibility.json`). This feature's complete
self-tests and original-body reader also pass within `base2`. Exact CI
format scope plus the facade/support files passes (`step0b-ci-format.txt`).
Step 0b is complete; no production code moved. Linux originals are present
but deliberately unstaged here; their hash verification, strict tests and
separate commit are step L. Device checks, remote CI and integration remain
pending. No push or branch switch.

### Step L — strict Linux originals

Step 0b commit: `9a373b8dd96a9694d1ee601c689b61159a21e877`. Six supplied
Linux PNGs match both `linux-original-sha256-first.txt` and the reversed
capture list exactly. Checkpoint (b), R and current library/pubspec objects
match. `linux-original-verification.json` freezes PNG hashes, capture
evidence hashes, Flutter/Dart and calibrated linux/amd64 image provenance.
No original capture was performed here.

The current golden test removes the capture/require booleans and Linux
missing-file skip; missing or mismatched Linux originals now fail by
default. The capture script still resolves frozen (b), whose original test
supports its capture flags. Strict macOS 6/6 and Linux 6/6 pass without
image updates (`stepL-macos-strict.txt`, `stepL-linux-strict.txt`). Linux
verification uses a fresh normal clone under this worktree's `.dart_tool`,
its own pub get and `debrify-flutter:3.44.8`; pubspec objects stay unchanged.
All six supplied hashes remain unchanged afterward. Step L is complete;
production remains ORIGINAL and step 1 may begin.

### Step 1 — whole types and widget parts; gate 1 input

Step L commit: `de5672d13`. Twelve whole declarations move from R: the six
unchanged entry/selection/loader/activation types (88 lines), four public
guide types (64 lines) and two whole widget parts (134 lines). The State
uses their registered public names through actual imports; the facade
exports exactly the original six entry names. Geometry and all State
workflow/resource ownership remain in the 2,057-line facade until step 2.
Its existing size ratchet is lowered to 2,057; no destination exception.
`step1-wiring-review.json` records every entry, caller and ownership exit.

Architecture registration is additive, on its own `FEATURES +=` line:
exact bridge, 500-line limits, empty exceptions, unconditional feature
scan, service/back-import/storage/playback/keep-alive/TEMP guards and both
directions of the IPTV implementation boundary (models allowed). Real
copy negatives and positives pass, including completion-only facade cap,
missing facade and TEMP probes. The new runner passes from a fresh normal
clone after its own pub get and is CI-registered. CI format/analyze paths
include the facade and support files inside their commands, before `| tee`;
the per-symbol inventory runs in CI too.

Current feature CLI self-test passes all 103 leaves, reader, occurrence,
context, callback and mandatory-qualification fixtures. The 228 selected
behavior/paint/golden/source-body identities match `base2` exactly; the
unchanged subprocess driver is covered by the separately passing real CLI
and will run in full gate 1. Wrong test paths and an empty regex draft are
discarded, never accepted. Strict macOS timeline/results goldens pass in
the selected tests; calibrated Linux timeline 6/6 and unchanged IPTV
results 4/4 pass with no updates (`step1-linux-strict.txt`).

Analysis has two exact inventoried infos and zero new warning/error;
outside-slice diagnostics/locations match the latest ORIGINAL run. The
loaded analyzer emitted repeated identical lines; only byte-identical
severity/message/file:line:column/rule emissions are canonicalized for
comparison, with raw logs retained (`step1-analyzer-identities.json`).
The two infos are the public RulerMark constructor and original
reconcileProgrammeCursor's formatter-expanded conditional. No braces,
key, suppression or behavior changes. CI format/allowlist/inventory,
architecture, size, storage and shape checks pass. Theme output is
byte-identical; light-ink remains 774 / 240 primary. Protected source
guards/storage hashes and every unrelated production file are unchanged.
Found-not-fixed 1–6 remain preserved.

The full gate runs on this committed input against latest `base2`; the
fresh rerun of all 20 other manifests is also finishing with isolated
packages. Their verdicts are required before step 2. No source mutation or
dependent move will overlap the gate.

### Step 1 guard continuation — IPTV auxiliary clock seam

The first all-manifest rerun exposed a missed source-text consumer:
`iptv_checker_config.json` pins the entire timeline as an auxiliary clock
seam. Its unchanged original-file assertion rejects the declared move
(`all-manifests-step1-worker0/iptv.txt`); the same manifest passed against
ORIGINAL in step 0b. This is a checker relocation issue, not an accepted
failure. The incomplete first gate attempt was stopped and is discarded
(`gate1-aborted-clock-seam.json`). Gate 1 is restarted on a committed tree
containing the preserved guard.

Conservative decision: register `source_reader_module` only on that
auxiliary seam. `check_seams` defaults to its existing direct-file path;
the opt-in timeline reader first validates every live leaf, retained
forwarder, scaffold, callback and field binding against R, then returns
that validated ORIGINAL source. The existing whole-file clock-seam
fingerprint comparison (including directives and comments) still compares
it with IPTV's exact patched historical baseline. No seam patch, assertion
or production body is removed or weakened. A reader validation failure
retains the named auxiliary-seam error. This additive hook and the one
IPTV config registration must be unioned by the integrator in addition to
the previously planned shared edits.

The new timeline-owned clock-seam fixture runs from the CI-listed real
checker runner. At S=0/1/2/3 it proves the original fingerprint passes and
a clock mutation in `_dayHeading` fails the auxiliary assertion (the
method moves at S=2). A different returned baseline and an unregistered
reader path also fail. The real IPTV CLI passes in the normal scratch
clone with the opt-in hook. Final fixture, fresh-clone, all-manifest and
restarted-gate verdicts are recorded below when complete; step 2 remains
blocked until the required checks pass.

### Gate 1 accepted

Step-1 input `4c35f749e` and guard continuation
`e5c6e7d32fd23721408fb92fdf01d9d815fe9851` are accepted. The 13 clock-seam
fixtures pass here and from the normal clone; its real IPTV CLI positive
and physical `_dayHeading` mutation prove the preserved auxiliary assertion
(`step1-fresh-clone-clock-seam-proof.json`). All 20 other complete manifest
self-tests pass with isolated packages; stdout and occurrence AST digests
remain byte-identical to ORIGINAL (`step1-reviewed-all-manifests-compatibility.json`).

Serialized full `gate1-serial` on clean committed `e5c6e7d32` passes against
latest `base2`: exactly 12,197 success, 13 failure, 28 error, 20 skipped,
1,183 suites, no added/missing identity or changed outcome. Paths `[]`,
flags `--no-pub --concurrency=2`, identical SDK and stable start/end tree
are recorded in `gate1-summary.json` / `gate1-serial.env.json`; comparison
is `gate1-serial-vs-base2.txt`.

NOTE: the second, discarded attempt overlapped three manifest workers and
hit the unchanged Xtream 50k ingest 30-second timeout, followed by its
cleanup assertion. Test and service blobs match ORIGINAL, where it passes.
The exact named test passes alone after those workers finish
(`gate1-xtream-NOTE.json`), then the entire gate passes serialized. Neither
incomplete attempt is accepted; no timeout, assertion, baseline or allowlist
is changed. Step 2 may now begin.

### Step 2 — complete State section move

All 103 entries are reviewed in `step2-wiring-review.json`; actual imports,
receivers and original callers are wired. Owners retain the 19 fields;
seven cached sections borrow the live view/context/mounted/setState and
lazy hold getter. The facade retains original lifecycle order, hold owner,
controller/widget declarations and the five controller/build forwarders.
Only registered receiver/name/identifier-link substitutions are used.
All 16 production files are byte-identical to the accepted step-0b full
composition probe, including its live-view identity proof.

Facade: 332 physical lines = controller 37 + widget 84 + State 182 +
imports/exports/gaps/trailing 29. Destinations: entry 88, track 444, guide
models 64, palette 10, owners 49, window 162, selection 205, guide loading
241, cursor 297, frame 336, rows 260, parts 134, view 28, dependencies 24,
sections 27. All are below 500; only this facade's size-baseline entry is
removed. Bridge/view/hold/localization exceptions keep the exits already
named above. Every other original production file, pubspec/lockfile and
existing timeline/results test is byte-identical to R.

Complete timeline CLI self-tests pass all 103 leaves and every S=0–3
reader, binder, context, callback, comment, scaffold and export fixture
(`step2-own-manifest.txt`). Mandatory qualification rejects bare owner reads
at S=2 and S=3 independently and through checker/reader. All 20 other full
self-tests pass; stdout and occurrence output remain byte-identical to
pre-opt-in evidence (`step2-all-manifests-compatibility.json`); adapter
source remains unchanged. Explicit isolated parser packages are used.

CI format, scoped analyzer allowlist/inventory, architecture with real
negatives, sizes, storage keys/references, shape tests, LF and diff checks
pass. Ten infos are within the 11 exact probe maxima; outside-slice
diagnostic identities/locations match latest ORIGINAL after identical-line
deduplication with raw logs retained (`step2-analyzer-identities.json`).
No warning/error, suppression, key or braces change. Theme output is
byte-identical and light-ink remains 774 / 240.

All 228 focused identities/outcomes match `base2`; strict macOS timeline
and results goldens pass. Linux timeline 6/6 and unchanged results 4/4 pass
(`step2-linux-strict.txt`), without image updates. All committed golden
bytes retain their original hashes. No load-sensitive failure occurs.
Found-not-fixed 1–6 remain unchanged. Step 2 is complete; completion guards,
fresh final clone, gate 2, device checks, remote CI and integration remain.

### Step 3 — completion guard input

Step 2 commit: `fcc624aa5975aaf5896078a5a2659a562b3de443`.
Completion sets the timeline flag true, pins its measured facade cap to
332, and adds the facade to COMPOSITION_ROOTS with its ownership comment.
The existing completion branch includes it in main and forbids TEMP in
both facade and bridge. Application/test/golden bytes are unchanged from
step 2. Full local verification, a fresh normal clone and full gate 2
against latest `base2` and accepted `gate1-serial` remain before acceptance.

### Step 3 — local verification and gate 2 input accepted

Completion guards pass through the real checker: measured 332-line facade
cap, facade inclusion/missing-file guard, TEMP bans and both directions of
the IPTV boundary. All 103 live leaves, retained forwarders, scaffold,
context, occurrence qualification and callback checks pass
(`step3-own-manifest.txt`). All 20 other complete self-tests pass with
isolated packages; stdout and occurrence digests are byte-identical to
pre-opt-in evidence (`step3-all-manifests-compatibility.json`). Forty fresh
raw normal/occurrence comparisons are also byte-identical; adapter source
remains unchanged (`step3-all-manifests-adapter-raw.json`).

Fresh normal clone (`.git` directory), after its own pub get: complete
real-config self-test, architecture positives/negatives, source contracts,
11 review tests and per-symbol inventory pass. It clones step 2 and stages
only the three owned step-3 config/guard/Progress overlays; executable
hashes match the final input. The real IPTV CLI positive passes; a physical
`widget.now()` → `DateTime.now()` mutation in the moved frame's `_dayHeading`
fails the named auxiliary seam assertion and is restored. No `.git` file
or parser kernel is copied (`step3-fresh-clone-proof.json`). Original
mutation-driver and composition-probe fresh-clone proofs recorded in 0b
remain applicable: those tools are unchanged and all production bytes
match the accepted probe.

Final CI format, analyzer allowlist, strict 10-info inventory, architecture,
size, storage references/keys, shape, LF and staged-diff checks pass.
Outside-slice analyzer identities/locations match latest ORIGINAL; only
identical repeated diagnostic lines are deduplicated, with raw logs retained.
Theme output is byte-identical; light-ink remains 774 / 240. All 228 focused
identities/outcomes match `base2`. Strict macOS scenes and Linux timeline
6/6 plus results 4/4 pass without image updates. Production/golden hashes
and facade/destination arithmetic remain exactly as recorded in step 2
(`step3-unchanged-production.json`). No load-sensitive failure occurs in
these final checks. Found-not-fixed 1–6 are preserved.

Gate 2 runs next on the clean committed input, with paths `[]`, flags
`--no-pub --concurrency=2`, against latest `base2` and accepted
`gate1-serial`. All heavy checker/clone runs finish before the full suite;
no mutation or dependent edit overlaps its tested tree.

### Gate 2 accepted and completion handoff

Step 3 input: `a551d80b040c982170e105b2cdcfc98b4d255b12`, tested tree
`c2a4069efce9a6f877221342dc9b187fd77ecf9a`. Accepted full `gate2-serial`
passes against both latest `base2` (tree
`ba2335e6064bb0c3c09870909824d18ba049e48e`) and accepted `gate1-serial`
(input `e5c6e7d32fd23721408fb92fdf01d9d815fe9851`). Exactly 12,258
identities/outcomes match each: 12,197 success, 13 failure, 28 error and
20 skipped across 1,183 suites. No added/missing identity, changed outcome,
new skip or new failure. Comparison logs are `gate2-serial-vs-base2.txt`
and `gate2-serial-vs-gate1-serial.txt`; `gate2-summary.json` records the
stable clean start/end HEAD/tree, paths `[]`, flags separately, and the
same Flutter 3.44.8 / Dart 3.12.2 SDK as both baselines. The ordinary
Flutter exit 1 is the same 41 baseline failures/errors; both comparison
verdicts PASS.

NOTE / conservative scheduling decision: the first gate-2 attempt used
`--concurrency=2` and hit the named Xtream 50k ingest 30-second timeout,
then its cleanup assertion. It is incomplete and discarded
(`gate2-aborted-contention.json`). The test and all six imported project
libraries are byte-identical to ORIGINAL. The exact named test passes
alone on this same committed input (`gate2-xtream-NOTE.json`). The complete
retry uses `--no-pub --concurrency=1`, serializing test suites to reduce
contention; it passes that test and every other baseline identity. This
changes runner scheduling only: no timeout, assertion, baseline or allowlist
is modified. Accepted gate 1 uses concurrency 2; both full gates have
paths `[]`. All incomplete attempts remain explicitly unaccepted.

Final facade/destination measurements and production hashes are unchanged
from step 2. Every step commit ends with the required Codex co-author
footer. `final-audit.json` records the series, clean branch, protected
files, unchanged allowlists, golden hashes and acceptance input. This
closing commit changes Progress only; no executable input changes after
the accepted gate. Steps 0, 0b, L and 1–3 and both full-suite gates are
complete. No branch switch, push, rebase, sibling edit or main-checkout edit.

Integrator union list:
- `check_settings_moves.py` and `occurrence_field_bindings.py`: named opt-in
  `retained_field_live_getters` normalization, alignment, retained-declaration
  ownership and exact live-factory checks; keep all absent-key defaults.
- `check_settings_moves.py.check_seams`: additive `source_reader_module`
  hook, retaining full ORIGINAL fingerprint comparison;
  `iptv_checker_config.json` registers it on this one auxiliary timeline
  seam. Include the owned reader and clock-seam fixtures.
- `check_search_architecture.py`: this feature's own FEATURES += line, exact
  bridge, 500-line destinations/empty exceptions, COMPLETE flag, measured
  332-line facade cap, COMPOSITION_ROOTS/main/TEMP, import/service/data/
  playback/keep-alive and bidirectional IPTV boundary checks.
- `ci_behavior_tests.txt`: union all eight timeline test paths, including
  source-contract/checker driver and review tests; `checks.yml`: preserve
  format/analyze paths inside commands before tee, architecture runner and
  isolated analyzer inventory calls.
- `file_size_baseline.txt`: remove only this completed facade's old entry.
  Neither analyzer_allowlist nor ci_behavior_known_failures changes here.

The binder qualification note above remains mandatory: this feature
explicitly sets `mandatory_qualification: true`. Do not replace upstream's
new default or discard edit_profile's other named opt-in blocks when
unioning the retained getter key. On the integrated committed tree rerun
every manifest, architecture/size/storage/shape/theme, CI format/analyze
and full-suite comparison, as described in Integration.

Found-not-fixed 1–6 remain: periodic offstage setState, the public
`itemCanFitBadge` name, up-to-30-second refresh delay, cache-constructor
directory requests, equal same-generation retry-token first-completion
behavior, and malformed bundled Roboto assets. Existing bridge/view/hold/
localization exceptions retain their documented future exits. Pending:
the end-of-series Android TV/tvOS/provider/desktop/touch/accessibility
device checks above, remote CI when available, and cross-worktree
semantic integration. No device gate is claimed. Nothing is pushed.
