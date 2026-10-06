# Recordings hub refactor — plan

Written 2026-10-06 on `refactor/recordings`, cut from `refactor/codebase` at
`49c53e2e`. Follow [AGENTS.md](../../AGENTS.md).

Read first: [stremio-tv-plan.md](stremio-tv-plan.md) (closest analogue: a
State with a playback handoff split into an eager owners record, live
dependencies and frozen sections behind a facade that keeps the lifecycle and a
one-line `build` forwarder), [stremio-tv-tuner-plan.md](stremio-tv-tuner-plan.md)
(the opt-in `record_owners`/`record_fields` binder keys, static members kept on
a section class), [stremio-tv-catalogs-plan.md](stremio-tv-catalogs-plan.md)
(private widgets crossing files through pinned aliases, never renames) and
[debrify-tv-plan.md](debrify-tv-plan.md) (owner qualification, the occurrence
binder, live getters, `setState` tear-off, handoff ledger). This plan reuses
their technique, checker (`check_verbatim_moves.py` → `check_settings_moves.py`,
`sections` engine), callback-identity tooling, `suite_evidence.py`, real-config
fixtures, original-code proofs with assertion-failing mutation negatives, the
handoff ledger and the Linux-golden handoff. It states only what differs. A
facts inventory accompanies this plan and is copied into the dependency report
at step 0.

**Execution.** Own worktree
`/Users/varunbsalian/Documents/Projects/debrify-wt/recordings` on
`refactor/recordings`. Run `flutter pub get` first; the lockfile must not
change (Flutter 3.44.8 / Dart 3.12.2). Commit after every step; never push,
merge, rebase or switch branches; gate commits contain `gate`. Evidence only
under `$(git rev-parse --path-format=absolute --git-common-dir)/refactor-evidence/recordings/`.
Every manifest run passes an isolated `--parser-package` under the ignored
`.dart_tool/recordings_parser/` (delete `*.dill` in copies). Original proofs
use a detached worktree under `.dart_tool/recordings_original/`.
`suite_evidence.py` runs are serialized in this worktree with `--no-pub` and an
explicit `--concurrency` recorded in the env file. Four sibling refactors run
concurrently (Spotlight live timeline, Premiumize files, IPTV settings two-pane,
AllDebrid files) and `edit_profile` may merge into `refactor/codebase` meanwhile:
this branch never edits their files. Load-sensitive flakes
(`remote_pairing_recovery_integration_test`, `xtream_streaming_ingest_test`,
the catalogs manage MDB refresh, WebDAV shard, the 180 ms PIN test) are rerun in
isolation and recorded as a NOTE, never allowlisted. Every self-test and
checker added here must also pass from a fresh normal `git clone` (`.git` is a
directory) after `flutter pub get`; nothing copies `.git` as a file.

## Goal

`lib/screens/settings/recordings_page.dart` is 2,129 lines and already
formatter-clean (`dart format --set-exit-if-changed` exits 0), so **R =
`49c53e2e`** and there is no format-only commit. It is the DVR hub: one
scrollable page with three zones (Recording now, Scheduled, Library), a 1 s
wall-clock notifier for elapsed/countdown text, an Android native poll (3 s
live / 15 s scheduled), lifecycle-gated timers, a manual schedule flow
(channel → date → time → length → capacity gate → schedule), in-app playback of
a finished recording, and delete with confirmation.

It holds one public widget (`RecordingsPage`), its 928-line State
`_RecordingsPageState with WidgetsBindingObserver` (12 instance fields, two
statics, five getters, 23 methods, a 210-line `build`), six private top-level
constants and 14 private widget classes (seven with States).

Split it **move-only** into a new feature `lib/features/recordings/` behind a
facade at the original path. Unchanged: the element tree, widget runtime types,
keys, `const` placement, focus-node debug labels, dialog and snackbar text,
timer cadences, lifecycle order, service call order and arguments, and the
playback handoff.

**Why a new feature.** No `recordings` feature exists. The page belongs to the
IPTV DVR, but `lib/features/iptv/` and `lib/features/iptv_settings/` are
completed migrations whose registrations other forks may touch; a separate
feature keeps this branch's registrations disjoint and additive.

**Callers stay unchanged.** Four importers construct `const RecordingsPage()`:
`settings_page_navigation.dart`, `iptv_settings_recording_actions.dart`,
`iptv_recording_support.dart` and `lib/widgets/recording_limit_dialogs.dart`
(a deliberate import cycle with this page, which `ensureRecordingCapacity`
needs). They keep importing the facade path. No test imports the file today.

**Temporary exceptions and their exits.**

| Exception | Exit |
| --- | --- |
| Bridge sections call `LiveRecordingService`, `DesktopRecordingService`, `DesktopScheduleService`, `DevicePreferences`, `Process.run` and `VideoPlayerLauncher` directly | A recordings repository contract + Riverpod controller (and a named playback bridge) |
| `recordings_hub_schedule_row.dart` lives in the bridge because its widget field is typed `ScheduledRecording` (declared in `lib/services/live_recording_service.dart`) | `ScheduledRecording` moves to `models/` in a separately reviewed change |
| Direct `Platform.isAndroid` / `Platform.isMacOS` reads | A platform-capability adapter |
| Legacy English text (every label, dialog, snackbar) | Localization migration |
| Pinned typedef aliases for 12 private widgets | Public widget names in a later, separately reviewed rename |

## Public surface (unchanged)

`RecordingsPage` (39–44) **stays in the facade byte-identical**. Its
`createState` names the private State, so the State stays in the facade too,
with its `with WidgetsBindingObserver` header, the verbatim lifecycle
(`initState`, `dispose`, `didChangeAppLifecycleState`), the `_onRevision`
listener (its tear-off is registered and unregistered as the same object) and
a one-line `build` forwarder. The facade exports nothing.

## What it contains (lines at `49c53e2e`)

| Lines | Area |
| --- | --- |
| 1–18 | 18 imports |
| 20–28 | File header comment |
| 30–37 | `_kBg`, `_kCard`, `_kRec`, `_kGold`, `_kAccent`; doc + `_kDialogRowPadding` |
| 39–44 | `RecordingsPage` |
| 46–93 | State header, 12 fields (+ docs), static `_batteryNudgeDismissedPref`, getters `_isAndroid`, `_desktop`, `_desktopCaptures`, `_anythingLive` |
| 95–168 | `initState`, `dispose`, `didChangeAppLifecycleState`, `_onRevision`, `_showBatteryNudge`, `_dismissBatteryNudge` |
| 170–272 | `_loadAll`, `_syncTimers`, `_pollLive` (doc) |
| 274–404 | Actions banner, `_stopAndroid`, `_stopDesktop`, `_cancelSchedule`, `_play`, `_delete`, `_openFolder` |
| 406–664 | `_createManualSchedule` (doc), `_pickTime` (doc), `_askRecordingLength` (doc) |
| 666–759 | Formatting banner, `_fmtBytes`, `_fmtElapsed`, `_fmtCountdown`, `_fmtDuration`, `_clock`, `_dayLabel`, static `_stampSuffix`, `_displayFor` (doc) |
| 761–972 | Build banner, `build` |
| 975–2129 | `_HubBar`, `_SectionHeader`, `_EmptyHint`, `_LiveCard`, `_RecDot`(+State), `_ScheduleRow`(+State), `_LibraryRow`(+State), `_Thumb`, `_EmptyDvr`, `_BatteryBanner`, `_AlarmBanner`(+State), `_HubButton`(+State), `_HubIconButton`(+State), `_RowIconButton`(+State), with their banners and docs |

**State resources.** Owned: `_now` (`ValueNotifier<DateTime>` created at State
construction, disposed), `_firstLibraryFocus` (`FocusNode` created at State
construction with debug label `recordings_first_library_row`, disposed,
injected into the first library row which must not dispose it), `_ticker`
(1 s periodic), `_poll` (3 s / 15 s periodic, Android only), the binding
observer and two revision listeners. Widget States own: `_RecDotState`'s
`AnimationController` (non-TV only) and a lazily created own `FocusNode` in
each focusable row/button/banner State (disposed; `_LibraryRowState` prefers
the injected node and never disposes it).

## Contracts that must not change

Pinned by behaviour tests on ORIGINAL code (step 0) where reachable, and by
source guards through a per-declaration manifest-driven reader
(`test/support/recordings_source.dart`) otherwise. Each step 0 inventory row is
**B** (behavioural; needs an assertion-failing ORIGINAL mutation proof) or
**S** (source guard only, with the reason).

**Reachability.** `_isAndroid` is `!kIsWeb && Platform.isAndroid` from
`dart:io`, which a test cannot override; on the macOS and Linux test hosts every
Android-only branch (native live query and poll, Android stop, exact-alarm
banner, battery nudge, Android schedule/delete/library, `disableExternalPlayer:
true`, `ensureEngineReady`) is unreachable and is **S** by construction,
verified by the whole-body verbatim checker and listed on the device checklist.
`_desktop` (`DesktopScheduleService.instance.isSupported`) is true on both test
hosts, so the desktop paths are **B**.

1. **Lifecycle (facade, verbatim with receiver-only qualification).**
   `initState`: `super` → `addObserver(this)` →
   `schedulesRevision.addListener(_onRevision)` → (desktop)
   `revision.addListener(_onRevision)` → `unawaited(loadAll)` →
   `unawaited(DevicePreferences.instance().then(…))` reading the dismissal pref
   with a `mounted` check and `setState` only when non-zero. `dispose`:
   `removeObserver` → remove both listeners (desktop guard) → ticker cancel →
   poll cancel → `now` dispose → `firstLibraryFocus` dispose →
   `super.dispose()`. `didChangeAppLifecycleState`: `resumed` → visible + reload;
   `paused`/`hidden` → invisible, cancel and null both timers; other states
   ignored. `_onRevision`: `if (mounted) unawaited(loadAll())`. Tests: listener
   counts on both notifiers before/after dispose; a bump of either reloads (a
   seeded schedule appears); a bump after dispose does nothing; disposal leaves
   no pending timers.
2. **Load.** One `Future.wait` of five futures in fixed order; desktop: live =
   empty, schedules = `DesktopScheduleService.instance.list()` mapped with
   `toScheduledRecording()`, library = `DesktopRecordingService.listLibrary()`,
   exact alarms and battery exempt = `true`; `mounted` check after the wait;
   live filtered by `isRecording`; schedules sorted by `startMs` ascending;
   library sorted by `displayFor(…).recordedAt` descending; one `setState`
   writing all six fields and `loading = false`; then `syncTimers`. Tests:
   spinner until the first load; ordering of schedules and library; a dispose
   before the wait completes does not throw.
3. **Timers.** The 1 s ticker runs only while something is live or scheduled
   and the app is visible; `??`-style single instance (never two); stops when
   neither holds; each tick writes `now.value = DateTime.now()` and rebuilds
   only the scoped `ValueListenableBuilder`s (row/card element identity and
   build counts unchanged across a tick). Lifecycle `paused`/`hidden` cancels
   both timers; a revision bump while hidden reloads but never re-arms
   (`syncTimers` returns early); `resumed` re-arms through the reload. Android
   poll cadence (3 s live / 15 s scheduled / off), the light poll and its
   membership comparison escalating to a full reload are **S**.
4. **Formatting and display (B, through rendered text).** `fmtBytes` (GB 2 dp,
   MB/KB 0 dp, B; thresholds at 1024ⁿ), `fmtElapsed` (`h:mm:ss` from one hour,
   else `mm:ss`), `fmtCountdown` (≤ 60 s `starting…`, < 60 min, < 24 h with and
   without minutes, days + hours), `fmtDuration` (s / min / h / h m), `clock`
   (`MaterialLocalizations.formatTimeOfDay` from the State's context),
   `dayLabel` (Today / Tomorrow / Yesterday / `Wkd d/m`), and `displayFor`:
   extension stripped (only when the dot is past index 0), stamp suffix
   `_YYYYMMDD_HHMMSS` with optional `_n` parsed into local time, underscores to
   spaces, empty title → `Recording`, `recordedAt` stamp else mtime, duration
   from the store else `mtime − stamp` only when strictly between 1 s and 12 h.
   Library files in a temporary recordings directory drive these through the
   rendered subtitle (`channel · day clock · size · duration`, the channel shown
   only when non-empty and different from the title) and monogram name.
5. **Layout.** Loading spinner (accent colour); empty state when not loading
   and nothing is live, scheduled or in the library (`Your DVR is empty`,
   `Schedule a recording` autofocused on TV); otherwise the list in this order:
   alarm banner (Android, S), battery banner (Android, S), RECORDING NOW
   (`N LIVE`, desktop captures first then Android, Stop autofocused on TV for
   the first card), SCHEDULED (`N UPCOMING` or the empty hint), LIBRARY
   (`N · size` or the empty hint; desktop folder button with DOWN to the first
   row), footer text (desktop vs other). TV autofocus: first live Stop, else
   first schedule row, else first library row. `onScheduleDown` is non-null only
   when not desktop, no alarm banner, nothing live or scheduled and the library
   is non-empty (S on test hosts: desktop is always true; the DOWN redirect
   itself is B through the folder button). Countdown chip: `due` once started,
   colours by state.
6. **Actions.**
   - Stop (desktop): `await capture.stop()`; `Recording saved (<size>)` or
     `Recording stopped — nothing was captured`; reload. Stop (Android): S.
   - Cancel schedule: confirm dialog (`Cancel recording?`; content
     `title — channel` or channel alone; `Keep` / autofocused `Cancel
     recording`); on confirm and still mounted, desktop
     `DesktopScheduleService.instance.cancel(id)` (Android `cancelSchedule`, S);
     no explicit reload (the revision listener reloads). Keep leaves the
     schedule; dismissal does nothing.
   - Delete: confirm (`Delete recording?`, `<title> (<size>) will be removed
     from this device.`, autofocused `Keep`, red `Delete`); desktop
     `DesktopRecordingService.deleteRecordingFile(uri)`; `Couldn't delete the
     recording` when it returns false (for example an active capture's file);
     reload in both outcomes; Keep deletes nothing.
   - Open folder: S (`Process.run` cannot be faked; running it on a macOS host
     opens Finder). The fallback snackbar text is pinned by source guard.
7. **Manual schedule (desktop B; Android S).** Channel picker titled `Record
   which channel?`; cancel stops; a non-schedulable URL shows the exact snackbar
   and stops; `engineRecordableUrl` null stops silently; date picker
   (`initialDate`/`firstDate` now, `lastDate` now + 7 days, `Recording date`);
   time picker (`Start time`, initial now + 2 min; the TV spinner when
   `PlatformUtil.isAndroidTvCached`, Material otherwise); a start not after now
   becomes now; length dialog (`Record for how long?`, five presets, first
   preset autofocused only on TV, `Pick end time…` → `End time` picker with
   initial start + 1 h; an end at or before the start rolls the calendar day;
   over 6 h asks `That's a long recording` with the exact text and an autofocused
   `Cancel`); `ensureRecordingCapacity(…, offerManage: false)` with the
   candidate URL and window; `DesktopScheduleService.instance.add(url,
   channelName, programmeTitle: '', startMs, endMs, headers,
   connectionResourceId, resourceAuthorizationRevision)`; result messages
   (`Recording starts in a few seconds` / `Recording scheduled` / `duplicate` /
   `overlap` / `bad_time` / default) and the `exact_alarms_required` snackbar
   with its Settings action (S on desktop if unreachable); reload. Every
   `mounted` check after each await is kept (S where no test can unmount at that
   point).
8. **Playback handoff (one site; round 1 P1-3).** `VideoPlayerLauncher.push(context,
   VideoPlayerLaunchArgs(videoUrl: entry.uri, title: display.title,
   showVideoTitle: true, disableExternalPlayer: isAndroid))` with the State's
   context, the original argument set and order, nothing else supplied. A
   ledger `dev/tool/recordings_handoff_ledger.json` lists the site, its four
   supplied arguments and every `VideoPlayerLaunchArgs` default, each classified
   **observable** (transferred to `VideoPlayerScreen` by
   `video_player_launch_widget.dart`'s `toWidget`, e.g. `videoUrl`, `title`,
   `showVideoTitle`) or **launcher-only** (e.g. `disableExternalPlayer`).
   - Observable fields are compared behaviourally: on desktop with the default
     in-app player, an engine-free observer (the `StremioTvObserver` pattern in
     `test/support/stremio_tv_fixture.dart`: unwrap the boundary/`Builder`,
     remove the route in a microtask before its first frame) captures the pushed
     `VideoPlayerScreen` and compares each observable supplied field and every
     observable default with the ledger.
   - `disableExternalPlayer: false` on desktop is proven behaviourally by a
     macOS external-default case: with the external player selected, the push
     reaches the mocked URL-launcher transport (the
     `test/macos_infuse_launch_test.dart` pattern) instead of an in-app route.
     The Android `true` value is S.
   - The complete push envelope (receiver, argument names, order, values, no
     extra arguments) is pinned structurally by the source validator.
9. **Widgets.**
   - Focusable rows, buttons and banners: Select/Enter/Space (KeyDown only)
     activate; taps activate; `onFocusChange` repaints; focused visuals (gold
     border, alpha changes) — goldens plus property checks.
   - `_HubButton`/`_HubIconButton` with `onDown`: DOWN KeyDown calls it and is
     handled; DOWN repeat/up while redirecting is swallowed; without `onDown`
     DOWN is ignored (geometric traversal).
   - Focus-state derivation is live (`_focusNode.hasFocus`), never cached: after
     a pushed route pops, a row that lost focus repaints unfocused.
   - `_LibraryRowState` uses the injected node when given and disposes only its
     own lazily created node (test: the State's injected `firstLibraryFocus`
     is still usable after rows rebuild/dispose).
   - `_RecDot`: TV → static dot, no ticker; non-TV → `FadeTransition` driven by
     a 900 ms repeat-reverse controller between 0.35 and 1.0, disposed with the
     State.
10. **Device and profile ownership.**
    - The page captures no profile. The battery-dismissal value is read and
      written through `DevicePreferences` (device-wide) under
      `recording_battery_nudge_dismissed_at`; a profile switch does not change
      it (test: seed the device pref, switch the active profile, the State's
      read is unchanged).
    - Desktop schedules and captures shown are exactly what the services return
      for the active profile at load time: with schedules owned by two profiles
      seeded, only the active profile's appear; after a profile switch and a
      `schedulesRevision` bump the other profile's appear. No page-side filtering
      or caching exists to preserve beyond that.
    - Deletion only calls the platform delete service with the entry's URI; the
      desktop library comes from the recordings folder.
11. **No new responsibilities.** No feature or facade file adds `http`,
    `shared_preferences`, `sqflite`, `media_kit`, a player screen, a
    `KeepAlive`, a new `Builder` or wrapper widget, or a `const` change.
    `VideoPlayerLauncher` is imported only by the facade (if at all) and the
    registered handoff file.

## Destination layout

All under `lib/features/recordings/presentation/`. Each file is at most 500
formatted lines; estimates are original lines plus imports/header plus about
5 % receiver wraps. The step 0 dependency report settles exact membership.

**Outside the bridge (service-free widgets):**

| File | Contents | Est. |
| --- | --- | --- |
| `recordings_hub_tokens.dart` | `_kRec`, `_kGold`, `_kAccent` renamed `kRecordingsHubRec`, `kRecordingsHubGold`, `kRecordingsHubAccent` (registered manifest renames) | 15 |
| `recordings_hub_buttons.dart` | Buttons banner, `_HubButton`+State, `_HubIconButton`+State, `_RowIconButton`+State + aliases | 300 |
| `recordings_hub_chrome.dart` | Top bar banner, `_HubBar`, Sections banner, `_SectionHeader`, `_EmptyHint` + aliases | 150 |
| `recordings_hub_live_card.dart` | Recording-now banner, `_kCard`, `_LiveCard`, `_RecDot`+State + alias | 160 |
| `recordings_hub_library_row.dart` | Library-row banner, `_LibraryRow`+State, `_Thumb` + alias | 195 |
| `recordings_hub_empty_states.dart` | Empty-state banner, `_EmptyDvr`, `_BatteryBanner` (doc), `_AlarmBanner`+State + aliases | 260 |

**`legacy_recordings/`** (the bridge; exact path in the guard):

| File | Contents | Est. |
| --- | --- | --- |
| `recordings_hub_owners.dart` | `RecordingsHubOwners`: the 12 instance fields with docs, renamed by dropping the underscore, initializers verbatim | 55 |
| `recordings_hub_dependencies.dart` | `RecordingsHubDependencies`: `owners`, `context()`, `mounted()`, `setState` (the State's own tear-off), `sections()` | 35 |
| `recordings_hub_sections.dart` | `RecordingsHubSections`: builds every section once in a fixed order; constructors only store `_deps` | 35 |
| `recordings_hub_data.dart` | `RecordingsHubData`: static `batteryNudgeDismissedPref`; getters `isAndroid`, `desktop`, `desktopCaptures`, `_anythingLive`, `showBatteryNudge`; `dismissBatteryNudge`, `loadAll`, `_syncTimers`, `_pollLive` (doc) | 175 |
| `recordings_hub_actions.dart` | Actions banner, `stopAndroid`, `stopDesktop`, `cancelSchedule`, `play` (the handoff), `delete`, `openFolder` | 160 |
| `recordings_hub_scheduling.dart` | `_kDialogRowPadding` (doc), `createManualSchedule` (doc), `_pickTime` (doc), `_askRecordingLength` (doc) | 290 |
| `recordings_hub_format.dart` | Formatting banner, `fmtBytes`, `fmtElapsed`, `fmtCountdown`, `fmtDuration`, `clock`, `dayLabel`, static `_stampSuffix`, `displayFor` (doc) | 115 |
| `recordings_hub_layout.dart` | Build banner, `_kBg`, `build` | 240 |
| `recordings_hub_schedule_row.dart` | Scheduled-row banner, `_ScheduleRow`+State + alias | 180 |

**Frozen section map** (used identically by the contracts, manifest,
composition and callback fixtures; a change is a plan amendment):

| Key (`_sections.<key>`) | Class | File (`legacy_recordings/`) |
| --- | --- | --- |
| `data` | `RecordingsHubData` | `recordings_hub_data.dart` |
| `actions` | `RecordingsHubActions` | `recordings_hub_actions.dart` |
| `scheduling` | `RecordingsHubScheduling` | `recordings_hub_scheduling.dart` |
| `format` | `RecordingsHubFormat` | `recordings_hub_format.dart` |
| `layout` | `RecordingsHubLayout` | `recordings_hub_layout.dart` |

**Cross-class privates** become manifest-listed public names (`_loadAll` →
`loadAll`, `_fmtBytes` → `fmtBytes`, `_isAndroid` → `isAndroid`, …). Members
called only inside their own section keep their private names (`_syncTimers`,
`_pollLive`, `_anythingLive`, `_pickTime`, `_askRecordingLength`,
`_stampSuffix`). `_batteryNudgeDismissedPref` becomes the public static
`RecordingsHubData.batteryNudgeDismissedPref`: read bare inside
`RecordingsHubData` and as `RecordingsHubData.batteryNudgeDismissedPref` in the
facade `initState` (a registered static-receiver substitution; the Stremio TV
`_extractQuality` → `StremioTvStreamQuality.extractQuality` precedent).

**Private top-level constants.** `_kBg` (only `build`), `_kCard` (only
`_LiveCard`) and `_kDialogRowPadding` (only `_askRecordingLength`) move whole
with their sole user and keep their names. `_kRec`, `_kGold` and `_kAccent` are
used in several destinations, so they move to the tokens file **renamed** to
`kRecordingsHubRec`, `kRecordingsHubGold`, `kRecordingsHubAccent` (manifest
rows with `new_name`; round 1 P1-1: a value alias is not canonicalized by the
occurrence binder, while a manifest rename already is). Every use site is the
new name. A constant has no runtime type name, so the widget-alias rationale
does not apply; the values are identical canonical consts.

**Private widgets cross files through pinned aliases, never renames** (the
catalogs/detail-showcase precedent, keeping runtime type names and avoiding
new `use_key_in_widget_constructors` infos). Each owner file adds `typedef
RecordingsHub<Name> = _<Name>;` immediately after the class, for: `_HubBar`,
`_SectionHeader`, `_EmptyHint`, `_LiveCard`, `_ScheduleRow`, `_LibraryRow`,
`_EmptyDvr`, `_BatteryBanner`, `_AlarmBanner`, `_HubButton`, `_HubIconButton`,
`_RowIconButton` (12). `_RecDot` and `_Thumb` are used only within their own
file and get no alias. Owner-file uses keep the private name; every other use
(including `const _EmptyHint(` → `const RecordingsHubEmptyHint(`) is the alias.
Registered through `type_aliases`, the opt-in `file_aliases` (owner-local
spelling) and `additional_owners`, each in the step that creates its owner
file. Final alias names are fixed by the step 0 alias probe (no reflow).

**The facade** (`lib/screens/settings/recordings_page.dart`) holds sorted
imports, the file header comment, `RecordingsPage` byte-identical and
`_RecordingsPageState` with the eager `final RecordingsHubOwners _owners =
RecordingsHubOwners();` (same construction timing as today's field
initializers), a nullable cached composition (`RecordingsHubSections?
_composition;` and a getter building it once with
`RecordingsHubDependencies(owners: _owners, context: () => context, mounted:
() => mounted, setState: setState)`; never `late`, never per build), the
verbatim lifecycle and `_onRevision`, and exactly `@override Widget
build(BuildContext context) => _sections.layout.build(context);` (the layout
section's `build` keeps its lexical `context` parameter, so `Navigator.of(context)`
and the `Builder` parameter stay lexical).

**Cap.** Measured over every physical line: estimate imports 10, header comment
9, widget 7, State header and composition 14, `initState` 17, `dispose` 13,
`didChangeAppLifecycleState` 18, `_onRevision` 4, forwarder 3, blanks about 10
≈ **105**. Target 150; the enforced cap is the measured complete value
(`RECORDINGS_FACADE_CAP`), at most 150. Progress records `wc -l` and a per-span
breakdown summing to it from step 2.

**Guard registration** (`check_search_architecture.py`, step 1, additive and
keyed by this feature): `FEATURES += ("recordings",)` on its own line;
`RECORDINGS_FACADE`, `RECORDINGS_BRIDGE`, `RECORDINGS_COMPLETE = False`
(→ `True` at step 4), `RECORDINGS_FACADE_CAP`, `RECORDINGS_HANDOFF_FILES =
{RECORDINGS_BRIDGE + "recordings_hub_actions.dart"}`; the bridge in
`LEGACY_PLAYBACK_BRIDGES` with its exit comment (still no `http`,
`shared_preferences`, `sqflite`); 500-line caps with an empty
`RECORDINGS_SIZE_EXCEPTIONS`; no facade back-import from any feature file;
`lib/services/` imports only inside the exact bridge; `video_player_launcher`,
`player_launch`, `media_kit` and `lib/screens/video_player/` imports only in the
handoff file; no `lib/screens/` import from the feature; at completion the
facade in `main()` and in `COMPOSITION_ROOTS` (comment: composition root
holding the lifecycle), its measured cap and `TEMP(recordings)` rejection.
Real-checker tests (`dev/tool/recordings_architecture_test.py`, temporary tree
copy, run at every step and in CI) must reject: the facade missing; the facade
at cap + 1; `TEMP(recordings)` in the facade and outside the bridge; a 501-line
destination; a service import in a non-bridge file; a `video_player_launcher`
import in `recordings_hub_layout.dart`; a facade import from a feature file. The
unmodified tree passes.

## Technique

As in the Stremio TV, tuner and Debrify TV plans, plus:

1. **One original (R = `49c53e2e`), characterization checkpoint (b).** No
   format commit. (b) `test(recordings): step 0 original-code characterization
   checkpoint` leaves application files equal to R and adds the frozen tests,
   harness, source reader, fixtures, checker config, ledger and macOS goldens;
   Progress proves `git rev-parse <b>:lib` = `<R>:lib` (and `pubspec.yaml`,
   `pubspec.lock`). No production seam is added; if one proves unavoidable,
   stop and report.
2. **Strict-lint baseline and rename/alias probe.** Analyze R under
   `lib/features/analysis_options.yaml` in a detached worktree inside
   `.dart_tool/` (qualifying relative imports only), recorded by identity
   (rule, enclosing member, message). A throwaway probe applies the manifest's
   renames, receivers, aliases and imports to a compiling copy and inventories by
   identity every diagnostic that appears or disappears
   (`use_build_context_synchronously` changes from `_deps.context()` /
   `_deps.mounted()`, `library_private_types_in_public_api`, `unused_element`,
   `unused_import`, `directives_ordering`). Baseline and probe combine by
   maximum per identity. **No key parameter, constructor, `const` or
   suppression change is made.** Any surviving warning gets an
   `analyzer_allowlist.txt` entry by destination identity in the commit that
   creates its file.
3. **Live getters and `setState`.** Sections reach the State's `context`,
   `mounted` and `setState` only through `_deps.context()`, `_deps.mounted()`
   and `_deps.setState(...)` (registered `live_getter_callbacks`, the State's
   own tear-off), evaluated at the original site, never cached or hoisted.
   State-context sites (facts: 279, 291, 305, 338, 354, 380, 401, 412, 421,
   427, 442, 473, 506, 533, 547, 553, 566, 636, 703) become `_deps.context()`.
   **Lexical scopes stay lexical:** `build`'s parameter (764, 777), the
   `Builder` parameter (921) and every `dialogContext` (306, 355, 567, 637,
   642). No shadowed `setState` exists (`lexical_state_setters` empty; verify).
   Negatives: a builder `context` replaced by `_deps.context()`; a
   `_deps.context()` replaced by a captured local; `_deps.mounted()` hoisted
   above an await.
4. **Owner fields and the occurrence binder (reuse, no new mechanism).** All
   12 instance fields move at step 2 into `RecordingsHubOwners`, renamed by
   dropping the underscore (`live`, `schedules`, `library`, `loading`,
   `exactAlarms`, `now`, `ticker`, `poll`, `appVisible`, `batteryExempt`,
   `batteryNudgeDismissedAtMs`, `firstLibraryFocus`); **every moved field
   reference is receiver-qualified** (`_owners.live`), in the facade and in
   every section. The config uses the tuner's opt-in keys: `record_owners:
   ["_RecordingsPageState"]` and `record_fields` naming exactly those 12, so
   the two statics (`_batteryNudgeDismissedPref`, `_stampSuffix`) are not
   record fields. Hazards (the dependency report lists them all): locals
   `live`, `schedules`, `library` in `_loadAll` and `_pollLive` beside the
   renamed fields (`_owners.live = live`); locals `now` in
   `_dismissBatteryNudge`, `_createManualSchedule` and `_dayLabel` beside the
   renamed `now` field; the named-argument labels `now:` at 834/849/879 are
   labels, not references. Positives: each hazard method as planned.
   Negatives (real config, through checker and reader): `_owners.live = live`
   turned into a bare `live = live`; the local `now` in `_dismissBatteryNudge`
   replaced by `_owners.now`; a bare record field in any section; a field read
   through the wrong receiver.
5. **Receivers and composition.** Sections hold `final RecordingsHubDependencies
   _deps;` plus only the one-line getters they use (`_owners`, `_sections`); an
   unused getter would be a new warning, and the source contract pins each
   section's exact getter set. Cross-section calls are
   `_sections.<key>.<member>`. The facade's lifecycle reads `_desktop` as
   `_sections.data.desktop` and `_loadAll` as `_sections.data.loadAll` (the
   getter reads `DesktopScheduleService.instance.isSupported` live on every call,
   as today). Constructing the composition in `initState` (its first consumer)
   creates no resource.
6. **Callback identity, split by shape (round 1 P1-2).**
   - **Direct tear-offs** use the `torbox_callback_identity.py` mechanism
     (receiver path + member; wrapper, receiver-swap, member-swap and
     cached-field negatives): `addObserver`/`removeObserver(this)`; both
     `addListener`/`removeListener(_onRevision)` pairs (the facade State's own
     tear-off, unchanged); `onDismiss: _dismissBatteryNudge` →
     `_sections.data.dismissBatteryNudge`; `fmtBytes: _fmtBytes` (×2),
     `fmtElapsed: _fmtElapsed` (×2), `fmtCountdown: _fmtCountdown` →
     `_sections.format.*`; and inside the moved widgets `onTap:
     widget.onCancel/onPlay/onTap/onPressed`, `onPressed: onBack/onSchedule/
     onDismiss/widget.onDelete`, `onTap: onFix`.
   - **Wrapped and conditional closures** are outside that helper's direct-call
     shape (it resolves `unawaited`, not the inner call). They are pinned by a
     recordings-specific validator registered through the existing
     `source_validator_module` hook (the tuner precedent), which parses each
     site, checks the exact envelope (`() => unawaited(<receiver>.<member>(<args>))`,
     the `onScheduleDown` conditional with its five-term guard and
     `() => _owners.firstLibraryFocus.requestFocus()`, the folder button's
     `onDown` conditional, `() => Navigator.of(context).maybePop()` with the
     lexical build `context`, the dialogs' `() =>
     Navigator.of(dialogContext).pop(<literal>)`, `bytesOf: () => capture.bytes`
     and `bytesOf: () => rec.bytes`), and validates the inner receiver path and
     member **before** normalization, plus the occurrence binder on every
     identifier inside. Sites (facts): `onBack` 777, `onSchedule` 778/798,
     `onScheduleDown` 782–789, `onOpenAlarmSettings` 800, `onTap` 809, `onFix`
     817, `onStop` 839/857, `bytesOf` 835/850, `onCancel` 889, `onPressed` 903,
     `onDown` 904–906, `onPlay` 946, `onDelete` 947, the dialog pops 315/320/364/
     368/583/592/651/655, the snackbar action 513. Negatives per envelope: a
     different member (`stopAndroid` for `stopDesktop`), a different section
     receiver, the wrapper dropped (`() => _sections.actions.play(entry)`
     returning a Future to a `VoidCallback` is a compile error, so the negative
     is `unawaited` replaced by a cached tear-off), a conditional term removed
     or reordered, `context` replaced by `_deps.context()`, `capture.bytes`
     replaced by a captured local.
   - **Block closures** (the two `Timer.periodic` bodies, the
     `DevicePreferences.then` bodies, the `Builder` body, the `onKeyEvent`
     handlers) are covered by the whole-body comparison, the binder and the
     context guard, with receiver-swap negatives inside each.
7. **Verbatim comments.** The checker compares comments; never reword, move or
   drop one, including the banners (`// ── Actions ──…`, `// ── Formatting ──…`,
   `// ── Build ──…`, the widget banners), which travel with the first member
   below them, and the docs that cite `settings/widgets/settings_widgets.dart`
   (Found, not fixed: the path is now a facade). The file header comment stays in
   the facade.
8. **Shape.** The file is unswept: it is in neither `kShapeResidue` nor
   `kExtractedShapeResidue`; the verified inventory is **12 bare radii and zero
   `app.shape.` calls**. Accepted decision: destinations are not registered in
   the shape manifest (an extracted-residue entry would be allowed, but this
   branch keeps the shared manifest untouched to stay merge-disjoint).
   Instead a named guard, `test/features/recordings/recordings_shape_inventory_test.dart`
   (in the CI behaviour list), counts the radius regex used by
   `shape_manifest_test.dart` over the facade plus every recordings feature
   file and requires exactly 12 and zero `app.shape.` calls; it passes on R
   (the facade alone) and at every checkpoint, and the 488-token floor test
   passes unchanged.
9. **Theme and audits (round 1 P2-10).** `theme_surface_manifest.txt:6`
   (`settings = … lib/screens/settings/*.dart …`) covers this file today. At
   step 1 append exactly `lib/features/recordings/presentation/*.dart
   lib/features/recordings/presentation/legacy_recordings/*.dart` to that line
   (additive tokens; `edit_profile` and others also append there). Step 0
   measures the surface's site count with `measure_theme_surface.sh`; it must
   stay equal at every step. `light_ink_inventory.py`: extend `PRIMARY` with the
   recordings feature paths at step 1 so every moved site keeps its primary
   classification (before/after inventory output identical by site).
   `text_white_sweep.py`: keep the original's classification (today it is
   excluded as `settings`) by adding the recordings feature to the same
   exclusion at step 1 (before/after output identical). `theme_rendered_set.py`
   keeps its root (verify the import walk reaches the feature).
10. **Imports in new files.** Sorted `package:debrify/…` URIs, only what each
    file uses (relative imports in the original become package imports); no
    `unused_import`/`unnecessary_import`. `lib/widgets/recording_limit_dialogs.dart`
    is imported by the scheduling section (the cycle with the facade is
    pre-existing and unchanged in kind).
11. **Build forwarder and reader ownership (round 1 P1-4).** The facade's
    `build` is a registered retained forwarder: `forwarders` holds its exact
    text (`@override Widget build(BuildContext context) =>
    _sections.layout.build(context);`), the manifest row for
    `_RecordingsPageState.build` carries `retained_forwarder,layout_body`
    edits, and `forwarded_annotation_occurrences:
    {"_RecordingsPageState.build": ["override"]}` lets the moved body drop only
    the leading `@override` (the Stremio TV precedent; no new mechanism). The
    reader (Technique 13) validates the exact forwarder before excluding it from
    implementation ownership, so the moved body is the single implementation.
    `completion_step` is **4**. Positives/negatives through checker and reader:
    build retained in the facade (before step 3); exact forwarder plus moved
    body; both a full facade `build` and the moved body (duplicate
    implementation); an altered forwarder (extra statement, different receiver,
    cached section); a missing forwarder; the moved body still carrying
    `@override`.
12. **Composition, frozen per step (round 1 P2-5).** `RecordingsHubDependencies`
    takes `owners`, `context`, `mounted`, `setState` and `sections`; the facade
    supplies `sections: () => _sections`. Step 2's composition constructs
    exactly `data` and `format`; step 3's adds `actions`, `scheduling` and
    `layout` in the frozen order (`data`, `actions`, `scheduling`, `format`,
    `layout`). Both shapes are registered as scaffolds for their step
    (constructor and dependency tokens, plain section headers, eager owners
    construction, required files, each section's exact getter set) using the
    existing `scaffolds`/`required_scaffolds_step`/`scaffold_file_steps` and
    `plain_sections` keys. Mutations (checker and validator): sections rebuilt
    per `build`, a cached `context`/`mounted` value, `setState` wrapped in a
    closure, a section wired to the wrong class, a section constructor that
    creates a resource or reads `_deps`, owners created lazily.
13. **Source reader and proof media (round 1 P2-9).** The reader is a Python
    AST reader `dev/tool/recordings_source_reader.py` (on the shared
    `verbatim_ast` parser, `parser_lock`, isolated parser package) with a thin
    Dart wrapper `test/support/recordings_source.dart`. It reads verified raw
    ORIGINAL text (`git show <R>:…` with a hash check), the current physical
    sources, and enumerates owner files deterministically from the manifest;
    fixtures cover ORIGINAL, partial (after steps 1 and 2), mixed (a declaration
    in both places), scaffold-only and completed trees. Mutation media:
    behavioural (B) mutants run whole behavioural test files without name
    filtering, with test and harness hashes frozen, and each B mutant must fail
    a named behavioural assertion; S mutants run the source-contract test and
    are reported apart; simulated-move checker/reader rejections are a third
    report naming the guard that rejected and covering every section kind. A
    reader exception is never counted as B evidence.

## Steps

| # | Work | Contracts |
| --- | --- | --- |
| 0 | Base evidence; dependency report; manifest, config, ledger, callback sites; strict and alias/rename probes; harness, characterization tests, source reader, macOS goldens (two reversed-order captures); checkpoint (b); CI list; source-text inventory; Linux capture script | Nothing moves |
| 0b | Claude's independent review; gap closure on ORIGINAL; compiling-composition probe of the step-3 shape with the real checker and facade measurement | Nothing moves |
| L | **Prerequisite before step 1:** Linux originals hash-verified, committed separately; Linux golden test made strict | Goldens |
| 1 | Guard registration and architecture test; theme registration; tokens, buttons, chrome, live card, library row, empty states (outside the bridge) and the schedule row (bridge), with aliases; the facade `build` uses the aliases | 5, 9 |
| 2 | Owners record (eager), dependencies, sections with the `data` and `format` sections; the facade lifecycle verbatim with receivers; every remaining facade method qualifies field reads. **Full-suite gate 1** | 1–4, 10 |
| 3 | `actions`, `scheduling` and `layout` sections; the facade keeps only lifecycle, `_onRevision`, composition and the `build` forwarder | 5–8 |
| 4 | Completion: `RECORDINGS_COMPLETE = True`, facade cap and `TEMP`, `COMPOSITION_ROOTS`, real-checker negatives, CI format/analyze paths, `file_size_baseline.txt:36` removed, final evidence. **Full-suite gate 2** | All |

**No temporary forwarders.** `data` and `format` call nothing in `actions`,
`scheduling` or `layout`, so step 2 moves them while the remaining facade
methods call `_sections.data.*`/`_sections.format.*` directly. Step 3 moves the
three remaining sections together because `build` calls `actions` and
`scheduling`. Step 0b's compiling-composition probe builds the step-3 shape on a
scratch tree, runs the real checker and measures the facade.

### Step 0

1. **Base.** `recordings/base`: full suite via `suite_evidence.py run` on
   untouched R (paths `[]`, flags recorded separately) plus the whole-repo
   analyzer, with tree/SDK provenance.
2. **Dependency report** `docs/refactoring/recordings-deps.md` from the facts
   file: per leaf (declaration, banner, doc) its destination; every renamed,
   aliased or receiver-qualified occurrence; State `context`/`mounted`/
   `setState` sites; field hazards; callback sites; service/native/playback
   touchpoints; owned resources and disposal order.
3. **Checker.** `dev/tool/recordings_manifest.tsv` (LF) and
   `recordings_checker_config.json` (`engine: sections`), self-test module
   `recordings_checker_test.py` with real-config fixtures, `--relocate
   lib/screens/settings/recordings_page.dart=lib/features/recordings/`.
   Negatives through the real config: renamed private widget; alias used in its
   owner file; alias target changed; reworded comment; reordered `dispose`;
   changed debug label; changed timer duration; a field read left bare; a
   receiver swapped between sections; a registration ahead of its owner file.
   Any shared-tool change is opt-in and keyed by this feature; every integrated
   manifest's self-tests stay byte-identical in output.
4. **Harness** `test/support/recordings_fixture.dart`:
   - Pinned view 1280×800 (desktop) and 1920×1080 at DPR 1 for TV mode, the
     existing `PlatformUtil` TV debug overrides set and restored per test,
     `debugDefaultTargetPlatformOverride` pinned (macOS) and reset.
   - `SharedPreferences.setMockInitialValues` for desktop schedules
     (`desktop_recording_schedules_v1`) built through the real
     `DesktopSchedule.toJson`, and the `DevicePreferences` value.
   - A fake `PathProviderPlatform` pointing downloads at a per-test temporary
     directory so `recordingsDir()`/`listLibrary()` read real files (sizes and
     mtimes set explicitly); deleted in teardown.
   - `ProfileRuntime`: every test initializes the legacy runtime (captures'
     `start` and `captures` read `ProfileRuntime.isProfileCommitted`, which
     throws uninitialized); the ownership tests use the committed two-profile
     fixture (`test/support/profile_fixture.dart`).
   - A recording `NavigatorObserver`; dialogs driven by tapping and by keys.
   - Desktop captures are **B** (round 1 P2-7): the public
     `DesktopRecordingService.instance.start(...)` against a local `HttpServer`
     (inside `runAsync`) writing into the fake downloads directory produces a
     real capture; the fixture owns every capture it starts and **awaits their
     `stop()`** before resetting profiles or deleting directories (scheduler
     `shutdown()` does not stop captures). Required B coverage: nonzero and zero
     Stop outcomes, live-card focus and tick text, the delete refusal of an
     active capture's file. Only a concrete probe showing a genuine blocker may
     turn a row S.
   - Revision listeners are proven by presence and effect, not by private
     listener counts: a bump of each notifier causes exactly one counted reload
     (observed through the path-provider/shared-preferences boundary call
     counts) while mounted and none after dispose.
   - Time: tests do not advance `DateTime.now()` by pumping. Elapsed/countdown
     boundaries are driven through the public `ValueListenableBuilder<DateTime>`
     `valueListenable` found in the tree (setting its value) and observed in the
     rendered text.
   - `DesktopScheduleService.instance.shutdown()` in teardown; bounded pumps
     (the `_RecDot` animation repeats, so no `pumpAndSettle` while it is on
     screen); no pending timers at the end.
5. **Characterization tests** under `test/features/recordings/presentation/`
   (mirroring destinations): `recordings_lifecycle_test`,
   `recordings_load_and_timers_test`, `recordings_layout_test`,
   `recordings_actions_test`, `recordings_manual_schedule_test`,
   `recordings_handoff_test`, `recordings_widgets_focus_test`,
   `recordings_profile_ownership_test`, `recordings_goldens_test` and
   `recordings_source_contract_test` (S guards for the Android-only branches,
   the poll cadences and membership comparison, `Process.run` arguments and the
   folder fallback text, the `exact_alarms_required` snackbar, every `mounted`
   check, dispose orders, the `_RecDot` controller parameters, the debug label,
   the handoff site). Source reads go through the frozen manifest-driven reader
   that picks each declaration from the original or its created destination and
   fails when neither or both hold it. Final-topology checks are dormant until
   `RECORDINGS_COMPLETE`. All pass on (b).
   **Explicit S rows (round 1 P2-6), each with its reason:** supplied desktop
   channel metadata and store-duration precedence (`listLibrary` always yields
   `channelName: null`, `durationMs: null`); the page's private dismissal value
   and the battery banner (Android-only); `engineRecordableUrl == null` after
   `isSchedulableUrl == true` (dormant: `isSchedulableUrl` already requires a
   non-null recordable URL). A separate service-level test pins
   `DevicePreferences` round-tripping `recording_battery_nudge_dismissed_at`
   across a profile switch; it is not evidence for the page's private state.
   **Goldens (round 1 P2-8)** follow the reference protocol: the app theme and
   look used by the settings goldens, the bundled test fonts loaded once,
   `en_US` locale, text scale 1.0, DPR 1, pinned sizes, disabled animations
   where the framework allows and TV mode where `_RecDot` is static; time-free
   content only — library files with fixed old dates (`2024-03-0x` stamps) whose
   labels do not depend on today, schedules already started so the chip renders
   `due` with the scheduler unarmed (`shutdown()`), no live card in a golden
   unless the notifier value is set explicitly; readiness asserted before each
   capture (expected rows present, intended focus owner). Scenes: empty state
   (TV), populated desktop list, TV focus on a library row. Reversed-order
   captures run in **independent processes** and must be byte-identical;
   later comparisons are strict.
6. **Mutation proofs (ORIGINAL).** `dev/tool/recordings_original_mutations.py`
   applies each mutation to a scratch copy of (b) and requires a **named
   assertion failure** (not a compile error, not a timeout); B and S mutants
   run and are reported separately. At minimum (B): schedule sort reversed;
   library sort ascending; `fmtBytes` GB threshold `>` and MB precision 1;
   `fmtElapsed` hour form dropped; `fmtCountdown` 60 s boundary `<`; days branch
   hours dropped; `fmtDuration` minute threshold; `dayLabel` Tomorrow/Yesterday
   swapped; stamp regex optional `_n` removed; duration window 12 h → 24 h and
   1 s `>=`; extension stripped at dot index 0; empty title fallback text;
   ticker armed with nothing scheduled; ticker not cancelled when the last
   schedule goes; `syncTimers` visibility guard removed (a revision bump while
   hidden must not re-arm); `paused` not cancelling; `resumed` not reloading;
   revision listener not removed in `dispose`; first-library-focus disposed by
   the row; stop-desktop snackbar texts swapped; cancel dialog autofocus on
   Keep; delete dialog autofocus on Delete; delete not reloading on failure;
   handoff `showVideoTitle: false` and a swapped `title`; start-in-past not
   clamped to now; date picker last date + 6 days; length presets reordered;
   end-time roll by 24 h instead of the calendar day (a DST-independent proof
   or S with reason); 6 h confirm threshold `>=`; `offerManage: true`;
   `programmeTitle` non-empty; result message for `overlap` changed; TV
   autofocus moved to the second schedule row; `onDown` repeat not swallowed;
   activate on KeyUp; `_RecDot` animating on TV; focus derived from a cached
   field. Results recorded with counts; **every B mutant must fail**.
7. **CI list and workflow (round 1 P2-10).** Every new Dart test (including
   `recordings_shape_inventory_test.dart`) goes into
   `dev/tool/ci_behavior_tests.txt`. `.github/workflows/checks.yml`: step 1
   adds `- run: python3 dev/tool/recordings_architecture_test.py` after
   `check_search_architecture.py` in the architecture job (it uses only the
   working tree; no history or parser package needed); step 4 appends
   `lib/screens/settings/recordings_page.dart test/support/recordings_*.dart`
   to the `dart format` command and `lib/screens/settings/recordings_page.dart`
   to the `flutter analyze` command, both **inside** the command, never after
   `| tee` (`lib/features` already covers the feature). Manifest self-tests and
   the reader self-test are not CI steps (the series' convention); they run at
   every step and gate locally. No known failures expected.
8. **Inventory.** Bare-radius count (Technique 8), theme surface count
   (Technique 9), the source-text guards list and the strict-lint baseline.
9. **Linux capture script** for the Docker image `debrify-flutter:3.44.8`
   (clone under `$HOME`, `flutter pub get` inside the container, double
   reversed capture), run by Claude after (b).
10. **Commit (b)** with the proofs in Progress.

### Step 0b

Claude reviews (b) before any move: re-runs a sample of mutants, checks each B
classification is behavioural and each S reason is real (especially the
Android/desktop split, the capture rows and `Process.run`), hunts for unpinned
branches (timer arming/disarming, dialog results, profile ownership, the
handoff defaults) and lists gaps. Codex closes them on ORIGINAL code in a 0b
commit and builds the compiling-composition probe. Record `base2` only if tests
were added (added identities only, all passing).

### Per step and gates

Every step: this manifest plus every integrated manifest's self-tests (isolated
parser packages); the architecture test; sizes (lowering
`file_size_baseline.txt:36` as the facade shrinks, removed at step 4); shape
(bare-radius aggregate and floor) and theme surface count; CI format and scoped
analyzer with `check_analyzer_allowlist.py`; strict comparison by identity; the
focused characterization set and goldens. Gates are full-suite on committed
trees vs `recordings/base`; gate 2 also vs gate 1. Never `--record` a
regression.

### Integration (Claude)

Claude reviews the full range (verbatim checker, callback identity, field
bindings, lifecycle/disposal order, focus, the handoff ledger, profile
ownership) and runs an independent read-only Codex review (`rec-rev`); fixes go
through `rec-exec`. Before reporting, every new self-test and checker is run
from a fresh normal clone after `flutter pub get`. The integrator merges.

## Definition of done

- The facade is the composition root at its measured cap; every other file is
  ≤ 500 lines; no size exception.
- Production callers unchanged; the original responsibilities are each traced
  to a destination in the dependency report.
- All step 0/0b tests pass unchanged at every checkpoint; both gates show no new
  failure, nothing missing, nothing newly skipped.
- Checkers, self-tests, architecture test, format, analyzer allowlist, shape and
  theme counts clean; CI lists updated with paths inside commands (never after
  `| tee`).

## End-of-series device checklist (no device gate before merge)

- Android phone: Recording now cards from the native engine, bytes/elapsed
  updating, Stop and its snackbar, the 3 s/15 s poll picking up a finished
  capture, the exact-alarms banner and its settings link, the battery nudge and
  its dismissal surviving a restart, manual schedule through
  `ensureEngineReady`, delete of a MediaStore recording.
- Android TV: D-pad through the hub (autofocus order, the Schedule button's
  DOWN redirect when only the library is below, the folder button absent),
  the time spinner, playing a recording in-app (`content://`, external player
  disabled), timers pausing while the native player covers Flutter.
- Desktop (macOS/Windows/Linux): Show in folder, a live capture card and Stop,
  play with the external-player default.
- tvOS/iOS: the page as reached today (no recording support on iOS).

## Explicitly not in scope

Any service, native, player or launcher change; `ScheduledRecording` or other
model moves; Riverpod; localization; fixing any Found-not-fixed item; renaming
the private widgets; registering the file in the shape sweep.

## Found, not fixed

1. `_loadAll` has no request generation: a slower earlier load (revision bump,
   resume and poll can overlap) can overwrite a newer result.
2. If any of the five load futures throws, `_loadAll` throws inside an
   `unawaited` call: `loading` stays true (spinner forever) and the error is
   unhandled.
3. `_cancelSchedule` awaits `DesktopScheduleService.cancel`, which throws
   `StateError` for another profile's schedule without `manageProfiles`; the
   error escapes through `unawaited` from `onCancel`.
4. `_openFolder` awaits `recordingsDir()` outside its `try`.
5. `_dayLabel` adds/subtracts 24 h from local midnight, so on a DST transition
   day "Tomorrow"/"Yesterday" can be missed.
6. The library sort calls `_displayFor` (a regex parse) inside the comparator,
   O(n log n) parses per load.
7. The focus-state docs point at `settings/widgets/settings_widgets.dart`,
   which is now a re-export facade.

(The step 0 inventory may add items; each is recorded, never fixed.)

## Decisions taken before design review (Claude, 2026-10-06)

1. **New feature `recordings`**, not `iptv`/`iptv_settings` (completed
   migrations other forks may touch).
2. **R = base**: the file is formatter-clean; no format commit.
3. **Typedef aliases, never renames, for private widgets**; the three shared
   colour constants are renamed (round 1 P1-1); single-user constants move
   whole with their user.
4. **State split with an eager owners record, live dependencies and five frozen
   sections**; the facade keeps the lifecycle, `_onRevision` and a one-line
   `build` forwarder. No size exception expected.
5. **Android-only branches are S by construction** (dart:io `Platform`), backed
   by the whole-body verbatim checker and the device checklist; no production
   seam is added to reach them.
6. **Not registered in the shape sweep**; theme surface extended additively.
7. **Goldens**: macOS and Linux for three scenes (Step L before step 1).

## Round 1 review resolution (Codex `rec-design`, at `d29a5e14`)

| Finding | Resolution |
| --- | --- |
| P1-1 value aliases not canonicalized by the occurrence binder | The three shared colour constants are **renamed** through manifest rows (already canonicalized); widget typedef aliases stay (`type_aliases` is canonicalized). No value alias remains; no new mechanism. Fixtures exercise all three renamed tokens in State members and in whole widget declarations through checker and reader. |
| P1-2 identity helper cannot see wrapped/conditional closures | Technique 6 split by shape: direct tear-offs keep the identity helper; wrapped, conditional and chained closures (all sites listed, both `bytesOf` closures included) are pinned by a recordings validator via `source_validator_module` that checks the envelope and inner receiver before normalization, plus the binder. |
| P1-3 pushed widget does not carry every launch argument | Contract 8: ledger classifies observable vs launcher-only fields; observable fields compared on the engine-free observed `VideoPlayerScreen`; desktop `disableExternalPlayer: false` proven by a macOS external-default case through the mocked URL-launcher transport; full envelope pinned by the validator. |
| P1-4 reader ownership vs the permanent forwarder | Technique 11: registered `forwarders` text, `retained_forwarder,layout_body` edits, `forwarded_annotation_occurrences`, reader validates the forwarder first; `completion_step` 4; listed positives/negatives. |
| P2-5 composition wiring | Technique 12: `sections: () => _sections`; step-2 and step-3 scaffold shapes frozen and registered; listed mutations. |
| P2-6 overpromised B rows | Explicit S rows with reasons (desktop metadata/duration, dismissal value, dormant null URL); separate `DevicePreferences` test; time boundaries driven through the public notifier. |
| P2-7 capture coverage | Captures are B via public `start` + local `HttpServer`; legacy runtime initialized in every test; fixture awaits capture `stop()`; listener presence via counted reloads. |
| P2-8 golden determinism | Full protocol in step 0.5: theme, fonts, locale, text scale, time-free content (old dates, `due` chips, scheduler unarmed), readiness assertions, independent-process reversed captures, strict later comparisons. |
| P2-9 reader and mutation media | Technique 13: Python AST reader + Dart wrapper, verified ORIGINAL, deterministic owner enumeration, five fixture topologies; three separate proof reports; reader exceptions never count as B. |
| P2-10 CI and audits | Step 0.7: exact `checks.yml` commands and activation steps; Technique 9: `light_ink_inventory.PRIMARY` extended, `text_white_sweep` exclusion preserved; Technique 8: named shape inventory test. |
| P3-11 counts | 14 private widgets (seven with States); 12 bare radii, zero shape calls; shape rationale corrected. |

## Progress

(Filled in by execution.)
