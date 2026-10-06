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
| 1 | Guard registration and architecture test (CI-registered runner); parts file; entry file and the facade re-export; guide models (renamed public; the State keeps using them by their new names through type renames). These are whole classes and public types that never read State members. **Full-suite gate 1** | 11, 12, Technique 9 |
| 2 | The whole State body in one step: owners, view (header addition), dependencies, sections aggregator, all seven sections (track with the geometry declarations), composition, `_holdOk` with receivers, verbatim lifecycle with receivers, `build` forwarder, controller forwarders; the palette file is created here with its readers (no unused scaffold in step 1) | 1–12 |
| 3 | Completion: `COMPLETE = True`, facade cap and `TEMP`, `COMPOSITION_ROOTS`, real-checker negatives, CI format/analyze paths, final evidence. **Full-suite gate 2** | All |

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
   controller forwarders and the exact `build` forwarder
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
   cursor-row retention; `_accepts` rejection matrix (each clause alone);
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
   isolated parser package. Proofs: a fresh-clone positive and an
   added-info negative (one extra `prefer_const_constructors` in a
   destination fails), both run at every step from step 1.
8. **Source-text inventory.** `file_size_baseline.txt:26` (lowered from
   step 1, removed at step 2 once the facade is under 500); shape (Technique 8); theme and light-ink
   (Technique 8); verify unaffected: `test/theme/source_guard_test.dart`
   (`lib/widgets/iptv/` frozen-prefix list is a kThemingPrepared
   containment check, no path change needed), `profile_source_guard_test`,
   `stale_runtime_guard_test`, `settings_tv_input_source_guard_test`,
   `iptv_results_source_guard_test`, `storage_member_map.tsv`.
   `checks.yml` (step 3): the facade and
   `test/support/iptv_spotlight_timeline_*` into the format and analyze
   lists **before `| tee`**, never after; the architecture test as its own
   step.
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
on `rowHeight`; controller not rebound. **Source-guard-only mutants (round
1 P3-6), named in the mutation ledger with their reason:** the `_accepts`
generation and pending-token clauses under a source/context change (that
change also clears `_pendingLoads` and re-arms, so the result is rejected
by the pending-token clause either way — the stale-result behaviour test is
kept, but it does not isolate each redundant clause); the negative-index
and ordinal-mismatch clauses (`_loadVisibleRows` never constructs such a
token); the explicit `removeListener` in `dispose` (masked by the
controller's own disposal). Every other listed mutant must fail a named
behavioural assertion. It also runs the
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

(Step 0 adds any further quirks it observes; none are fixed.)

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
   (step 2 → `SpotlightTimelineFrame.build`) with an exact registered facade
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

## Progress

(none yet)
