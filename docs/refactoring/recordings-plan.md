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
statics, five getters, 25 methods, a 210-line `build`), six private top-level
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
| 1–18 | 16 imports |
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
   ignored. `_onRevision`: `if (mounted) unawaited(loadAll())`. Tests: a bump of
   either notifier causes exactly one counted reload while mounted (a seeded
   schedule appears) and none after dispose; protected `ChangeNotifier.hasListeners` observations
   additionally require each notifier's baseline before mount, true while
   mounted and restoration after dispose. Tests use explicit protected-API
   ignore comments as authorized by the Step 0b review; disposal leaves no
   pending timers.
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
4. **Formatting and display (B through rendered text, except the explicit S
   rows in step 0.5: supplied channel metadata and store-duration precedence).** `fmtBytes` (GB 2 dp,
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
     The Android `true` value is S. **Cleanup (round 2 P2-3):** a successful
     external launch arms a return observer and a 30 s timer
     (`launch_router.dart:509`, `external_activity_lifecycle.dart:74`); the case
     disposes the page, delivers the cover/resume lifecycle pair, drains the
     30 s fake timer and restores the lifecycle/bridge state before teardown,
     with no pending timers.
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
      `recording_battery_nudge_dismissed_at`. The page's use of the value is S
      (Android-only banner); a separate service-level test pins that the
      `DevicePreferences` value survives a profile switch.
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
() => mounted, setState: setState, sections: () => _sections)`; never `late`, never per build), the
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
   record fields. `mandatory_qualification: true` is explicit, independent of
   the shared default. The opt-in `mandatory_qualification_classes` scopes the
   shared bare-name scan to the owners and all five sections: the preserved
   `_LiveCard.now` is a separate widget field, and otherwise falsely matches
   the renamed State field. Occurrence alignment and the recordings validator
   still require every workflow reference, including the facade, to qualify.
   A real-config negative reading `now.value` bare in the data section must
   emit `Bare owner field reference` and be rejected by checker and reader. Hazards (the dependency report lists them all): locals
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
     lexical build `context`, each dialog pop with its exact argument
     (`pop(false)`/`pop(true)` at 315/320/364/368/592/651/655, and `pop(d)` at
     583 where `d` must stay the lexical loop-pattern variable of the preset
     `for`), `bytesOf: () => capture.bytes`
     and `bytesOf: () => rec.bytes`), and validates the inner receiver path and
     member **before** normalization, plus the occurrence binder on every
     identifier inside. Sites (facts): `onBack` 777, `onSchedule` 778/798,
     `onScheduleDown` 782–789, `onOpenAlarmSettings` 800, `onTap` 809, `onFix`
     817, `onStop` 839/857, `bytesOf` 835/850, `onCancel` 889, `onPressed` 903,
     `onDown` 904–906, `onPlay` 946, `onDelete` 947, the dialog pops 315/320/364/
     368/583/592/651/655, the snackbar action 513. Negatives per envelope: a
     different member (`stopAndroid` for `stopDesktop`), a different section
     receiver, the wrapper dropped (`() => _sections.actions.play(entry)`
     compiles as a `VoidCallback`, so it is a required checker/reader
     negative), `unawaited` replaced by a cached tear-off, `pop(d)` bound to
     anything but the loop variable, a conditional term removed
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
    `layout`). Because `scaffold_activation_step` only activates entries (an
    earlier constructor version would stay active and reject the step-3
    constructor), the two composition versions are **frozen step-specific
    specifications selected by the recordings validator**
    (`source_validator_module`, the tuner's `stremio_tv_tuner_contracts.py`
    precedent, which also enforces `scaffold_file_steps`): it reads
    `completed_step` and applies exactly the step-2 or step-3 specification
    (constructor and dependency tokens, plain section headers, eager owners
    construction, required files, each section's exact getter set). Both stages
    are tested with the final tooling: the step-2 tree passes under the step-2
    specification and fails under step 3, and the reverse. Mutations (checker and validator): sections rebuilt
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
   - `ProfileRuntime`: every test initializes the legacy runtime
     (`DesktopRecordingService.start` reads `ProfileRuntime.isProfileCommitted`,
     which throws uninitialized; `captures` already guards that case); the ownership tests use the committed two-profile
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
   - Revision listeners are proven by protected `hasListeners` before mount,
     while mounted and after disposal, plus their effect: a bump of each notifier causes exactly one counted reload
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

## Round 2 review resolution (Codex `rec-design`, at `e38b5122`; "No P1s — executable")

| Finding | Resolution |
| --- | --- |
| P2-1 scaffold version selection | Technique 12: the recordings validator selects the frozen step-2 or step-3 composition specification from `completed_step` (tuner contracts precedent); both stages tested both ways. Facade constructor example now passes `sections: () => _sections`. |
| P2-2 callback envelopes | Technique 6: each pop's exact argument pinned, including `pop(d)` bound to the lexical loop variable; the wrapper-dropped arrow is a compile-valid required negative. |
| P2-3 external launcher cleanup | Contract 8: dispose, cover/resume pair, drain the 30 s timer, restore lifecycle/bridge state, no pending timers. |
| P3-4 superseded wording | Contracts 1, 4 and 10 aligned with counted reloads and the explicit S rows; harness note narrowed (`start` needs the runtime; `captures` guards it). |

## Progress

### Step 0 — ORIGINAL characterization checkpoint (2026-10-07)

Checkpoint (b) has the exact subject `test(recordings): step 0 original-code characterization checkpoint`. Its resolved commit and application-object checks are recorded after commit in `refactor-evidence/recordings/step0-checkpoint.json`. `b:lib` and `R:lib` both resolve to `7d84002d0eac9b5acc023d922759dd335d321e94`; `pubspec.yaml` is `5f983ff8c68a01aef5c7a1ec393e677e7693591f`, and `pubspec.lock` is `e0ff9cca69c00ae69bb4dfe111c18a89547cec98`, unchanged from R. No application, service, player, native, other feature, theme or production seam changes. The existing 2,129-line facade / 928-line State retain their original responsibilities for characterization; their extraction milestones remain steps 1–3.

- Setup: read the complete plan including both resolution tables, AGENTS, all four reference plans and their Progress/tooling/tests. Verified and preserved the supplied facts in `recordings-deps.md`; corrected 18 imports to 16 and 23 non-getter methods to 25 (30 method declarations including 5 getters). `flutter pub get` first; Flutter 3.44.8 / Dart 3.12.2, framework `058e0af2c2b57e369d905a03ac9748b0ebf543c6`; lockfile unchanged. All evidence lives in the git common directory's `refactor-evidence/recordings/`.
- Base: `python3 dev/tool/suite_evidence.py run recordings/base --no-pub --concurrency=4`, on untouched detached R `49c53e2e8081eb7e951c39bafedf90d678a92f55`. Paths `[]`, flags separate, no untracked inputs, stable tested tree `6ac99ca96c0ff5b22f2fd30c9410b4c527f8de78`: **12,028 success, 13 failure, 32 error, 20 skipped; exit 1**. `base-summary.json` preserves every identity. The 19 failing files reran at concurrency 1; the WebDAV interrupted-apply case recovered there, then failed in its separate whole-file rerun. Separate Xtream/WebDAV reruns still have the known 30 s load timeouts (9/1 and 102/3 success/error); these are **NOTEs**, not accepted failures. No allowlist or `--record` changed. The three existing shape-floor tests passed in this observed baseline and their source/dependencies remain unchanged.
- Whole analyzer: original **1,709 diagnostics**, compared by severity/path/rule/message using `suite_evidence.py compare --relocate lib/screens/settings/recordings_page.dart=lib/features/recordings/`. `step0-ready-wait-analyze.txt` (after the final test fix) matches every original identity/count: **added [] / removed [], PASS**. An intermediate run emitted nine extra notifications (duplicate generated-asset warnings, duplicate legacy alpha diagnostics, and two unchanged vendor removed-lint warnings). The clean-R recheck and direct R legacy-file probe document these; the repeated full command returned the original 1,709 identities without deduplication or suppression. Recordings tests/support scoped analyzer: **zero issues**. Formatting and Python compilation pass; documentation/diff and shell syntax checks pass.
- Inventory: 72 LF manifest leaves, ten free banners, 261 planned rename/alias/receiver occurrences and 46 State UI-boundary sites in the dependency report. Frozen real-config fixtures cover ORIGINAL, stages 1–4 and scaffold-only ownership. The validator pins 72 callback/push envelopes before normalization, exact step-2/3 composition, owner getters, eager owners, live context/mounted and State setState tear-off. Source reader reuses the shared AST/ownership checker through the thin Dart wrapper. Ledger: **77 parameters, 61 observable / 16 launcher-only**, verified against original constructor and `toWidget`; nullable compatibility parameter effective default documented.
- Strict baseline/probe: R under feature lints has **2 infos**; the throwaway compiling rename/alias/receiver/import copy has **9 warnings + 1 info, zero errors**. By original enclosing-member identity the maximum is **12**: nine private-constructor optional-parameter warnings, the frozen lazy-composition `recursive_getters` info and two original import-order infos. No key, constructor, const, suppression or persisted-format fixes. No unused imports, private-type API or BuildContext additions survive the probe. The future file-creation commits own any named allowlist entries; none added here. The real-checker composition/facade-measurement gate remains Step 0b.
- Characterization: **34/34 pass** on the owned R worktree with the final frozen tests/harness, and **34/34 pass in the fresh normal clone**. Covers lifecycle/reload counts, load/disposal, ordering, timer scope and cancellation, formatting boundaries, lazy row readiness, real desktop HTTP captures (188/0 bytes), active-file refusal/reload, dialog focus/remote keys, scheduling and actual preference writes, typed engine-free playback defaults/external transport, and committed profile ownership/device-wide preferences. No private State calls or listener counts. A later clone run had 33 successes / one delete-reload assertion error: its real file deletion had completed before the UI reload was rendered. The unchanged whole actions file passed 5/5 in isolation. Accepted cancel/delete now poll the public empty state for a bounded interval before the original named assertion; the full 34-test clone and ORIGINAL runs pass, and all B/S/probe reports were regenerated with these final frozen bytes. This is recorded in `normal-clone-final-characterization-load-NOTE.txt`, without allowlisting or recording a regression. Eleven new test files, including shape inventory, are additive CI behaviour-list entries; workflow/architecture/theme activation stays at the later planned steps.
- Three separate reports: `step0-original-B-mutations.json` **39/39 named behavioural assertion rejections, no survivors**; `step0-original-S-mutations.json` **43/43 source-contract assertion rejections, no survivors**; `step0-checker-reader-mutations.json` **6 positives, 115 checker + 115 reader rejections**, naming rejecting guards. B mutants run whole behavioural files without name filtering; compile/load/timeouts and reader exceptions never count as B. Test/harness/ledger/PNG hashes freeze every run, and original bytes restore in `finally`. Initial discovery found weak absent-row/readiness assertions; those were strengthened and the entire B set rerun. The separate inert-listener probe survives, as documented below. Occasional concurrent-worktree `git stash create` provenance contention is retried only as infrastructure, with notes; mutant verdicts are never retried or softened.
- **Historical Step 0 deviation (superseded by Step 0b):** revision-listener removal was classified S, despite its minimum-B listing in item 6. The concrete mutation removing both unregister calls passes the whole lifecycle file: `_onRevision`'s mounted guard makes retained callbacks inert after disposal, so permitted reload-boundary observations cannot distinguish removal. `step0-original-probe-mutations.json` records this surviving reachability probe; it is not a B rejection. Registration/effect remain B; exact teardown remains S. The permitted calendar-vs-24-hour rollover is S because the pinned host time window has no DST distinction. All S reasons, including the 22 separate mounted occurrences, Android-only paths, null desktop metadata/duration, dormant URL, folder processes, teardown/controller/debug metadata, are in the dependency inventory and mutation cases.
- Goldens: **three macOS scenes**, independent forward and reverse processes, byte-identical hashes in `mac-original-provenance.json`; strict comparisons pass in both characterization runs. Original settings theme/look, bundled fonts, en_US, scale/DPR 1, pinned dimensions, fixed old stamps/due chips and focus readiness. Linux capture script syntax-checked for calibrated `debrify-flutter:3.44.8`, normal clone under HOME, pub get and lock/object checks, two reversed captures and strict comparison. **Docker/Linux capture intentionally not run**; Claude owns Step L after this checkpoint.
- Integrated manifest matrix: all 20 pre-existing manifests pass on R and current (40 exits 0), with byte-identical stdout for every pair in `integrated-final-self-tests.json`. Shared checker/parser/manifest implementations stay byte-identical to R; only additive recordings tools and feature-keyed CI entries are new. Execution memoization caches AST/normalizer data, never validation decisions. The final normalizer key includes tokens, config, declaration and all manifest rename pairs; a different/in-place edited mapping probe passes. All 20 additional corrected-key audit runs exit 0 and reproduce both paired outputs byte for byte (`integrated-audit-self-tests.json`, `integrated-audit-output-compare.json`): 60 successful runs total. Each run uses its own parser-package copy under `.dart_tool`, with copied dills deleted.
- Normal clone: final characterization candidate `a43cbfe30f69160d8dba6dfd0646d2ccfad4c8f6`, `.git` verified as a directory, `flutter pub get` and unchanged lockfile. The normal clone first validated all four new-tool commands on `0d232a74195d0e1130a724f3f427a86857baf62d`; every checker/fixture blob is unchanged in the final candidate. All four commands pass: reader JSON, real-config manifest self-test, reader self-test, and standalone checker fixtures; the clone reproduces six positive stages and 115 checker plus 115 reader rejections. Root/clone manifest self-test output is byte-identical, and the clone's 34 characterization tests pass. Executable/test/fixture blob equality to (b), commands, counts and output hashes are recorded in `normal-clone-final-provenance.json`, `normal-clone-ready-wait-provenance.json`, `normal-clone-final-final-checks.json`, `normal-clone-ready-wait-characterization-command.json` and the final checkpoint attestation; documentation-only Progress updates do not change those inputs.

**STOP after Step 0.** Step 0b independent review/gap closure/composition measurement, Linux capture/Step L, production extraction/registrations and both integration gates have not begun. No Docker, emulator, device, flutter run, push, merge, rebase or branch switch.

### Step 0b — independent review closure on ORIGINAL (2026-10-07)

The checkpoint has the exact subject `test(recordings): step 0b review closure on ORIGINAL`; its resolved commit and application-object attestation are recorded after commit in `refactor-evidence/recordings/step0b-checkpoint.json`. Application code remains R. The Step 0 listener-removal S classification is withdrawn: the review correctly identified protected `ChangeNotifier.hasListeners` as an observable registration boundary. The two unregister calls now have separate B proofs; the old inert-callback probe is historical evidence only.

- Characterization: **13 added identities**, all passing, in `recordings_review_closure_test.dart`; **47/47 ORIGINAL** pass with final inputs. `recordings/base2` is scoped to the 13 added identities, `--no-pub --concurrency=1`; `base2-summary.json` proves disjointness from the original 34-test set and no failures. Existing three macOS golden scenes remain strict and unchanged. Android TV time-picker selection is reachable through the existing cached-TV override even on desktop; native Android live entries remain unreachable through the original `dart:io` load branch.
- Coverage extends beyond the fourteen review cases: the date picker pins initial/first today and last today + 7 days, both start/end help labels and initial times; cancel pins both title/channel and channel-alone content; two real captures pin first-desktop-only Stop autofocus; four live/scheduled combinations pin the library and schedule rules. Three additional B mutants remove the library live/schedules guards or move desktop Stop autofocus to the second capture. The separate S mutant removes the Android fallback's `desktopCaptures.isEmpty` guard, with its host-reachability reason.
- Qualification is explicit `mandatory_qualification: true`. One additive, opt-in shared binder key, `mandatory_qualification_classes`, is necessary because the preserved `_LiveCard.now` otherwise falsely matches the renamed State field. It names the owners and all five frozen sections; existing manifests have no behavior change. The real-config bare `now.value` section negative requires the shared `Bare owner field reference` guard and checker/reader rejection; facade and all State references remain covered by occurrence alignment and the recordings validator. No state/field-class, registered substitution or new production seam was added.
- The compiling probe exposed four formatter-added trailing-comma envelope differences. The validator now uses the shared AST's `formatCommas` markings, preserving semantic positional-record commas and every receiver/member/argument. Sixteen frozen stage/site expressions changed only optional commas (`step0b-envelope-formatting.json`); a real `dart format` stage-3 positive prevents recurrence. This is a tooling closure required by the actual compiling probe, not a body change.
- Full step-3 scratch composition: `.dart_tool/recordings_composition`, detached from (b), **16 physical sources**, all 72 real bodies, 12 aliases, three token renames, eager owners, live dependencies, five ordered sections and exact facade forwarder. Real manifest checker, recordings validator and Python reader pass on physical formatted sources (`step0b-probe-final-checks.json`). No scratch production files are committed. Destination sizes are 8–291 lines, all below 500.
- Facade: **`wc -l = 101`**; measured cap for later registration is **101** (under target 150). Breakdown: imports 9 + blanks 9 + header comment 9 + public widget 6 + State header/closing brace 3 + composition 11 + initState 18 + dispose 13 + lifecycle 18 + onRevision 3 + build 2 = **101**. `step0b-composition-probe.json` records spans, all source hashes/sizes and diagnostic identities.
- Probe analyzer: **zero errors, nine warnings + one info**. By severity/rule/enclosing-member/message, delta from Step 0's rename/alias probe is **added 0 / removed 0**. Versus strict ORIGINAL: added 10 (nine frozen private-constructor optional-parameter warnings and the lazy-composition `recursive_getters` info), removed 2 original directive-order infos. Imports are sorted and minimal; no unused import, private-type API or BuildContext diagnostic was introduced. No constructor, const, suppression or allowlist change.

The following fourteen ORIGINAL mutants fail their named assertions in `recordings_review_closure_test.dart`; the complete B report also re-audits every existing B case using whole behavioural files, with source-contract and shape-source files explicitly forbidden by the runner:

| Mutant | Named behavioural test | Killing assertion |
| --- | --- | --- |
| danger-fill-alpha | live Stop fill follows focus and live card keeps its decoration | unfocused live Stop fill is 0.16 |
| end-time-initial-2h | desktop manual pickers pin dates times and no preset autofocus | end picker starts one hour after chosen start |
| empty-hint-text | scheduled empty hint retains exact text | scheduled empty hint keeps original punctuation and wording |
| pick-time-tv-branch | Android TV cached flag selects remote spinner for both times | Android TV start uses remote time spinner |
| ticker-schedules-only | live capture without schedules arms ticker and clamps elapsed | live capture alone arms one-second ticker |
| delete-content-text | delete dialog content names title size and this device | delete content names title size and this device |
| date-help | desktop manual pickers pin dates times and no preset autofocus | date picker help text is Recording date |
| length-autofocus-any | desktop manual pickers pin dates times and no preset autofocus | first length preset has no non-TV autofocus |
| inactive-cancels | inactive lifecycle leaves the visible ticker running | inactive is ignored and ticker keeps running |
| schedule-autofocus-ignore-live | TV autofocus precedence live=true scheduled=true | first schedule autofocus requires no live capture |
| cancel-dialog-content-dash | cancel dialog content uses title dash channel or channel alone | cancel content uses title em dash channel |
| live-elapsed-neg | live capture without schedules arms ticker and clamps elapsed | negative live elapsed is clamped to zero |
| schedules-listener-removal | revision listeners exist only for the mounted page | disposed schedules listener returns to baseline |
| desktop-listener-removal | revision listeners exist only for the mounted page | disposed desktop listener returns to baseline |

Final verification:

- Three separate reports: `original-B-mutations.json` **56/56**, `original-S-mutations.json` **43/43**, `checker-reader-mutations.json` **7 positives / 116 checker + 116 reader rejections**. **No surviving mutants.** `step0b-B-assertion-audit.json` matches each B case's assertion reason to its own failed behavioural test ID; every runner command uses whole behavioural files, with no source-contract or shape-source evidence. All test/helper/fixture/PNG hashes match final root bytes. The old combined-listener survival report is archived as `step0-original-probe-mutations.json`; the active pointer explicitly marks it superseded by the two B cases.
- All **20 existing manifests pass**, isolated parser-package copies under `.dart_tool` with copied dills deleted. Their stdout hashes match the recorded R outputs directly (`step0b-integrated-direct-R-compare.json`), not only counts. The shared binder's only change is the four-line additive opt-in class scope; no other shared implementation, manifest or feature files changed.
- Fresh normal clone (`.git` directory), `flutter pub get`, unchanged lockfile: all four commands pass (reader JSON, real-config manifest self-test, reader self-test, standalone checker fixtures), with byte-identical root/clone stdout and checker reports. Final candidate `e5f08e5ba3569b4ea5a24ccdb3c296a128b47f15` changes only documentation and the new test's clock bracket from the initial clone candidate; all tool/config/source inputs are identical. **47/47 final clone tests pass**. `step0b-input-attestation.json` proves all ten changed executable/test/fixture inputs equal across root, ORIGINAL and the normal clone.
- Compiling probe runtime: **34 original tests + 13 final review tests pass**, including the three strict macOS scenes, on the full physical composition. Source checker/validator/reader, measurement and diagnostic hashes are in `step0b-composition-probe.json` / `step0b-probe-final-checks.json`; no probe sources are staged or committed.
- Whole analyzer final: **1,709 original identities/counts, added [] / removed [], PASS** (`step0b-whole-analyzer-final-compare.txt`). Scoped recordings tests/support analyzer has **zero issues**; architecture check passes **1,515 migrated files**. Formatting, Python compilation and diff checks pass. Flutter **3.44.8 / Dart 3.12.2**, framework `058e0af2c2b57e369d905a03ac9748b0ebf543c6`, remains unchanged.
- **NOTEs:** initial whole-analyzer runs repeated unchanged generated/vendor and test diagnostics, including identical file/line notifications. One run temporarily isolated and then restored the ignored generated build folder; the settled final full command returned the exact R multiset, without deduplication, suppressions or allowlisting. The proof series was fully restarted after final protected-API comment placement/formatting and after bracketing the start clock before channel choice (preventing a minute-boundary race); intermediate reports are not the final proof. No behavioural regression was recorded or allowlisted.
- Base remains the observed untouched-R full suite: **12,028 success / 13 failure / 32 error / 20 skipped, exit 1**; the known isolation notes from Step 0 remain applicable. `base2` adds only **13 passing identities**. Three macOS PNGs are unchanged; Linux capture / strictness remains Claude's **Step L**, and Docker was not run.

**STOP after Step 0b.** This checkpoint closes the review on ORIGINAL and the compiling probe only. Linux capture, Step L, feature registration/extraction and both production integration gates remain pending. No application files, production seams, services, players, native code or other features were edited; no push, merge, rebase or branch switch.

### Step 0b — second independent review closure on ORIGINAL (2026-10-07)

The checkpoint has the exact subject `test(recordings): step 0b second review closure on ORIGINAL`; its resolved commit and object attestation are recorded after commit in `refactor-evidence/recordings/second-review-checkpoint.json`. `lib`, `pubspec.yaml` and `pubspec.lock` remain exactly R. This batch adds only tests, harness helpers, feature-owned inventory/checker tooling, additive CI behaviour-list entries and documentation. No extraction, production seam or unrelated feature changes.

- **Exhaustive AST inventory:** [recordings-text-inventory.md](recordings-text-inventory.md) and `dev/tool/recordings_text_inventory.json` enumerate all **134 string expressions**: **104 visible = 93 B / 11 S**, plus **30 individually classified internal** expressions. The visitor handles adjacent strings, nested interpolation alternatives, const constructors and implicit constructor invocations. Every visible item identifies its covering behavioural test/assertion or its explicit S reason. Class counts are recorded in the linked inventory and `second-review-root-text-inventory-checker.json`.
- **Text properties:** all **42 AST Text sites = 34 B / 8 S** are accounted for. Rendered assertions compare `maxLines`, overflow, alignment, size, weight, colour/alpha, letter spacing, height and font features, including null/default values. Titles, elapsed/countdown text, labels/chips, both hints, footer, empty state, buttons, dialogs and reachable snackbars have property checks. Verbatim tests cover all seven weekday names and d/m in both row kinds, relative dates, complete byte/duration/time templates, both schedule title/channel alternatives, live chips, tooltips, every manual preset, complete long-dialog interpolation alternatives, and result messages. Golden test-font blocks are not claimed as text/style proof.
- **Focus visuals:** seven B cases cover filled/danger HubButton, HubIconButton, RowIconButton, ScheduleRow, LibraryRow and Thumb highlight. Both states pin backgrounds, borders/widths/radii, icon and text colours; schedule recording-circle/countdown and Thumb gradient/play decorations are included. Two S variants remain: plain HubButton has **no original caller** (all three AST sites explicitly select filled/danger), and AlarmBanner requires native Android. The inventory checker rejects a new plain caller until that S becomes B. Alarm/battery text/style, native snackbars/settings, non-desktop footer and the Process.run fallback have explicit host/process reasons. The accepted RecDot controller S is unchanged.
- **Reachability extension:** the original desktop minimum-remaining guard is reachable by selecting an immediate start and next-minute end. A picker result whose source has disappeared reaches the original generic authorization-error message. Both are now B, through public route results and real services, without a production seam. The manual driver forwards optional channel/resource metadata; no service or player code changed.
- **Characterization:** **21 added identities** in `recordings_text_inventory_test.dart` (12) and `recordings_visual_properties_test.dart` (9); **68/68 ORIGINAL** pass with final frozen inputs. `recordings/base2 --no-pub --concurrency=1` runs only the 21 additions, all passing and disjoint from the previous 47 identities (`base2-summary.json`). First-review base2 artifacts are preserved as `first-review-base2*`. Existing action/manual tests add Text-property/verbatim checks without changing identities. Two new files are additive CI behaviour-list entries. Three strict macOS PNGs are unchanged; Docker/Linux capture remains pending with Claude.

The four independently reported survivors now fail named behavioural assertions with source-contract and shape-source evidence excluded:

| Mutant | Killing test | Named assertion |
| --- | --- | --- |
| daylabel-weekday-order | each nonrelative weekday and day month appears in both row kinds | nonrelative schedule weekday d/m verbatim: Sat 2/3 |
| library-row-maxlines | populated widgets every Text site has explicit properties | LibraryRow title Text properties |
| live-chip-text | populated DVR verbatim headers chips footer and live text | populated DVR verbatim text: 1 LIVE |
| rowicon-focus-color | row icon both focus states pin decoration icon and text | RowIconButton focused and unfocused icon colour |

- **Mutation proofs:** 33 added B cases cover all four survivors and every newly covered reachable string/property/focus class. Final reports `original-B-mutations.json` **89/89**, `original-S-mutations.json` **43/43**, and `checker-reader-mutations.json` **7 positives / 116 checker + 116 reader rejections**, with the feature inventory checker's **2 positives / 9 rejections** reported separately inside the third report. **No survivors.** The runner explicitly forbids source-contract/shape tests for B and now binds assertion reasons to each expected test ID. `second-review-B-assertion-audit.json` independently verifies every killing assertion belongs to its behavioural file/test. Whole files run at explicit concurrency 1; source/reader/compile/timeout failures do not count as B. Tests/helpers/fixtures/PNGs are frozen and original source restores in `finally`.
- **Normal clone and compatibility:** fresh normal clone (`.git` directory), `flutter pub get`, unchanged lockfile; final frozen candidate `f9c76204dd24020d58c84ba0b0cdb7154a95bd1e`. All five commands pass: reader JSON, real-config manifest self-test, reader self-test, new text-inventory self-test, standalone checker fixtures. Root/clone stdout and checker reports are byte-identical; **68/68 clone tests pass**. `second-review-input-attestation.json` proves final non-documentation inputs equal root, ORIGINAL and candidate/clone. The orchestration retained its initial candidate label; the final candidate/tree is explicitly corrected and attested in the characterization environment record. All **20 other manifests pass** with stdout byte-identical directly to recorded R (`second-review-integrated-direct-R-compare.json`); isolated parser copies under `.dart_tool`, copied `*.dill` deleted. No shared tool, other manifest or other feature file changed in this second batch.
- **Verification:** whole analyzer identities match R (**1,709; added [] / removed [], PASS**). Scoped recordings tests/support: zero issues. Architecture: **1,515 migrated files pass**. Formatting, Python compilation and diff checks pass. SDK stays Flutter 3.44.8 / Dart 3.12.2. Untouched-R full-suite base remains **12,028 success / 13 failure / 32 error / 20 skipped, exit 1**; no full-suite rerun, allowlist or `--record` in this test-only closure.
- **NOTEs:** preliminary proof inputs were refreshed after finding two reachable backend messages, removing one unnecessary test-helper import, and replacing exact-text readiness waits with public dialog/snackbar presence so mutations reach named assertions. Earlier snackbar is explicitly dismissed before the next action. All 33 new cases passed discovery before the entire 89 B / 43 S inventory was regenerated from zero with final bytes; intermediate reports are not final evidence. `second-review-input-refresh-NOTE.txt` records this. The only reachability exception to requested focus coverage is the plain HubButton's nonexistent ORIGINAL caller; adding a seam to manufacture it would violate the original-code boundary, so it is explicit S with an AST call-site guard.

**STOP after this second-review commit.** Step L, Linux capture, Step 1 and production extraction remain pending. No lib/service/player/native edits, Docker, emulator, device, flutter run, push, merge, rebase or branch switch.


### Step 0b — final preset-duration closure on ORIGINAL (2026-10-07)

Subject: `test(recordings): step 0b preset durations on ORIGINAL`; resolved commit/object proof is in `preset-review-checkpoint.json` under the common-directory recordings evidence. Application, service, player and native files remain R; `lib = 7d84002d0eac9b5acc023d922759dd335d321e94`, with both pubspec objects unchanged.

- Five new behavioural identities in the 40-line `recordings_preset_durations_test.dart` select every preset through the original manual flow and compare the real desktop schedule's `endMs - startMs` with 5 min / 30 min / 1 h / 2 h / 3 h. Each has its own `length preset <label> schedules its exact duration` identity and `preset schedules exact desktop duration: <label>` assertion. `preset-label` (2 h → 3 h), `preset-five-minutes`, `preset-thirty-minutes`, `preset-one-hour` and `preset-three-hours` each fail that assertion in the whole behavioural file, without source-contract evidence. One additive CI entry.
- Final ORIGINAL characterization **73/73**, with the three unchanged strict macOS scenes. `recordings/base2 --no-pub --concurrency=1` contains only the **five added passing identities**, disjoint from the previous 68; prior base2 artifacts are preserved as `second-review-final-base2*`. `base2-summary.json` records the union. Untouched-R full-suite base remains **12,028 success / 13 failure / 32 error / 20 skipped, exit 1**.
- Three regenerated reports: **94/94 B**, **43/43 S**, **7 positives / 116 checker + 116 reader rejections**, with inventory **2 positives / 9 rejections** separately reported in the third report. No survivors. Every B is independently matched to its own named behavioural assertion in `preset-review-B-assertion-audit.json`; fixtures/tests/harness/PNGs are frozen and ORIGINAL bytes restore in `finally`. No name filtering, compile/timeout/reader evidence counted as B, regression recording or allowlisting.
- Fresh normal clone candidate `5dee104c192fa7252d224bca65feadb2ca6923f7`, `.git` directory, `flutter pub get`, unchanged lockfile: all five tooling commands pass and **73/73 clone characterizations pass**. All five stdout hashes and checker reports equal the prior root results byte for byte; the unchanged tooling inputs justify reusing those root checks. Final candidate/input equivalence is in `preset-review-input-attestation.json`.
- All **20 other manifests** pass with stdout byte-identical directly to R (`preset-review-integrated-direct-R-compare.json`), using isolated parser copies with copied dills deleted. No shared tooling change in this closure. Whole analyzer **1,709, added [] / removed [], PASS**; scoped analyzer has zero issues. Format/diff checks pass. SDK remains Flutter 3.44.8 / Dart 3.12.2. No load flakes observed in this closure.

The next authorized checkpoint is Step L, followed by Steps 1–2 and gate 1. Step 3 remains outside this authorization.


### Step L — verified Linux ORIGINAL goldens (2026-10-07)

Previous checkpoint `2dfcab7e60573335e7ce2d53eb4b3106095ff760`. Subject: `test(recordings): step L verified Linux ORIGINAL goldens`; resolved commit/object attestation is in `stepL-checkpoint.json`.

- Before any change, both the complete golden test and scene fixture were byte-identical to (b) `0eab0f5c`; `stepL-input-verification.json` records their hashes. All three supplied PNGs match `linux-original-sha256-first.txt` exactly and its independent reversed hash list is byte-identical. Committed `test/goldens/recordings/linux/{empty_tv,library_focus_tv,populated_desktop}.png`: `ef808bd11d06fb207c303dae5d77741f2842be4432b333bf247fdd3ab7008a5f`, `aadf74fab4027a59e1d9b1272385a994479b2b1e9e0e335708c6180659a411d3`, `ef0cc354a7445213a35dc2f85110ddbfe82991ee7a49abbc5df490c77ceef22f`.
- Claude's `linux-original-*` evidence proves a normal clone of (b), application/pubspec objects equal R, calibrated `debrify-flutter:3.44.8` / Dart 3.12.2, two independent reversed captures and **3/3 strict Linux replay**. Docker was not run here. The current test removes the Linux skip and both capture/require overrides: missing or mismatched Linux pixels now fail by default. Its original capture script still clones frozen (b), retaining calibration.
- Current strict macOS replay **3/3**, unchanged PNG bytes; scoped analyzer zero issues, formatter/diff clean. No application or tooling inputs changed, so the immediately preceding manifest/self-test/normal-clone evidence remains valid. `lib`, `pubspec.yaml`, `pubspec.lock` remain R. This prerequisite is complete; Step 1 may begin. Post-extraction Linux execution remains for Claude under the no-Docker constraint.


### Step 1 — widget/token extraction and registrations (2026-10-07)

Parent `22e3084ff2f53a5d426ce8f5cbf218d0beb997cf`; checkpoint subject `refactor(recordings): step 1 widget and token extraction`. Resolved objects and source sizes are recorded after commit in `step1-checkpoint.json` under the common-directory recordings evidence.

- Seven destinations preserve whole private declarations, comments, constructors and const/key behaviour: tokens **8**, buttons **291**, chrome **148**, live card **156**, library row **189**, empty states **259**, bridge schedule row **176** lines. Twelve immediate public typedef aliases expose the unchanged private widgets; only the three registered shared colour names change. The facade is **977 lines**; its public Widget is byte-identical to R. `step1-inventory.json` gives the AST span breakdown. Lifecycle, data/format/workflows and fields remain in State until Step 2.
- Feature-keyed architecture registration enforces 500-line destinations, the exact temporary bridge, service/screen/playback/persistence boundaries, missing facade and keep-alive rules. Completion remains false; the previously measured **101-line** completion cap and TEMP rules have positive/negative probes. The 120-line `recordings_architecture_test.py` invokes the real main and is wired immediately after the architecture command in `checks.yml`. The size baseline is lowered to 977 and retained until Step 4. Theme/light-ink registrations and white-sweep exclusion match the settings source classification. Explicit `mandatory_qualification: true` remains unchanged.
- Actual physical Step 1 passes checker, validator and reader. All five root tooling commands pass: real reader JSON, manifest self-test, reader self-test, inventory self-test and standalone fixtures. Reports: **7 positives / 116 checker + 116 reader rejections**, inventory **2 positives / 9 rejections**. All **20 other manifests** pass with stdout byte-identical directly to R, with isolated parser copies and copied dills deleted (`step1-integrated-direct-R-compare.json`).
- **73/73** characterization identities pass unchanged, including strict macOS goldens and all preset checks; **13/13** shape/theme guard tests pass. Bare-radius aggregate/floor remain **12/488**, shape calls zero; owned theme sites **95**, full settings surface **657**, light ink **27**, all primary, and white-sweep excluded. The production rendered-set walk reaches all seven created files. Both macOS and committed Linux PNG bytes remain unchanged. Post-extraction Linux execution remains Claude's task under the no-Docker constraint.
- Fresh normal clone, `.git` directory, `flutter pub get`, unchanged lockfile: final candidate `9e964e9c76f0c46c7125e5fa0c4bdb3141cbbd78`, all five tool outputs/reports byte-identical to root, real architecture probes pass, **73/73** characterizations pass. The ink-tool correction was refreshed into the candidate before characterization; final input/tree attestation corrects the orchestration's initial candidate label (`step1-input-attestation.json`).
- CI format/scoped analysis with the analyzer helper, local facade/support analysis, architecture/real negatives, size, storage-key checks and diff checks pass. Whole analyzer **1,718 vs 1,709**: nine private-constructor alias warnings already measured by the ORIGINAL alias/composition probe, with **no added/removed outside-feature identities** and no strict identities beyond that probe. The feature-only analyzer entries record those exact extraction warnings; no behavioural regression is allowlisted. Services, players, native code, pubspecs and all other feature application files are unchanged (`step1-protected-sources.json`).
- **Tooling adjustment / NOTE:** formatting the two longer registered colour names wrapped the original ScheduleRow/LibraryRow border ternaries, which the line-oriented ink scanner initially missed. A recordings-only white-else continuation rule restores the same 27 expressions after registered-name canonicalization. Real scanner probes reject non-recordings paths, fill roles, already-counted white branches and non-white continuations. No application body or another feature's classification changes. `step1-ink-formatting-NOTE.txt` records the discovery; the final predicate and inputs were refreshed before final checks. No runtime load flake was observed.

Step 2 and gate 1 are the next authorized work; Step 3 remains outside this checkpoint.


### Step 2 — eager owners, data/format and live dependencies (2026-10-07)

Parent `65cf79a56`; checkpoint subject `refactor(recordings): step 2 owners data and format`. Resolved objects are in `step2-checkpoint.json`; gate 1 runs only after this checkpoint is committed.

- Five bridge destinations: owners **49**, dependencies **18**, sections **11**, data **160**, format **102** lines. All twelve owner slots initialize eagerly in original order with unchanged initializers/docs. Dependencies are the five frozen required references (`owners`, live `context`, live `mounted`, the State `setState` tear-off, live `sections`). The section constructor creates only `data`, then `format`; no future sections, forwarders, service/model/player edits or production seams. The seven Step 1 widget files and all characterization sources are byte-identical.
- Facade **740 lines** = imports 23 + blanks 22 + banners/header 9 + retained constants/docs 3 + public Widget 6 + State boundary 5 + composition 11 + lifecycle 52 + actions/scheduling workflow 385 + retained build 224. The public Widget remains byte-identical to R. Lifecycle/listener/disposal order is preserved with owner/data receivers; every remaining workflow field access is qualified. `file_size_baseline.txt` is lowered to 740 and deliberately retained until Step 4. Explicit `mandatory_qualification: true` remains set.
- Physical-tree checker/reader/validator pass, with `completed_step: 2` and only the two plain sections registered. `step2-real-composition-selection.json` proves the same sources are accepted by the step-2 specification and rejected by the step-3 specification with **Frozen step-3 composition changed**. Frozen source envelopes, field bindings, aliases, comments, handoff ledger and renamed-token checks all remain active.
- All five root tooling commands pass; fixtures remain **7 positives / 116 checker + 116 reader rejections**, inventory **2 positives / 9 rejections**. All **20 other manifests** pass with stdout byte-identical directly to R (`step2-integrated-direct-R-compare.json`), using fresh isolated parser-package copies with copied dills deleted.
- **73/73** unchanged characterization identities pass, including all preset windows, listeners, timers, focus/property checks and three strict macOS scenes. **13/13** shape/theme source guards pass. Bare-radius aggregate/floor **12/488**, shape calls zero, owned theme **95**, full settings surface **657**, light ink **27** (all primary), white-sweep exclusion unchanged. The actual rendered-set walk still reaches all seven moved rendering files, with **181** sites including unchanged shared widgets. Committed macOS/Linux PNG hashes remain unchanged; Linux execution after moves remains Claude's task.
- Fresh normal clone candidate `99ac461135cfebf7e074d043f906f91070ba4a25`, `.git` directory, `flutter pub get`, unchanged lockfile: actual current checker/reader and the real architecture positives/negatives pass, plus **73/73** characterizations. All five self-test tool/fixture blobs are unchanged from the immediately preceding fresh-clone Step 1 proof (which exercises every staged topology); that proof is reused, while root runs all five again on this checkpoint. `step2-input-attestation.json` binds final non-documentation inputs to this candidate.
- CI/local format and scoped analysis, analyzer helper, strict member identities, architecture/real negatives, sizes, storage-key/reference checks and diff checks pass. The ten feature diagnostics are exactly the nine private-alias constructor warnings and one recursive live-sections getter info already measured in the Step 0b composition probe; strict additions are empty. Final whole analyzer **1,719 vs 1,709**, with the exact outside-feature diagnostic multiset unchanged (**added [] / removed []**), after all owned AST jobs stopped. No duplicate notifications remain in final evidence. Services, players, native code, dependencies and other feature application files are unchanged (`step2-protected-sources.json`).
- **NOTEs:** `step2-orchestration-NOTE.txt` retains the mistyped existing shape-test path, the passing partial four-test selection and the prematurely started inventory read; final evidence uses the correct 13 shared guards and measurement after its analyzer dependency completed. The first whole-analyzer outputs contain repeated identical notifications; the ignored generated build directory was briefly isolated and restored in `finally`, exposing the two baseline generated warnings as removals in that isolated view. Neither raw artifact is hidden or used to add an exception. `step2-analyzer-NOTE.txt` and the exact-location multiplicity report preserve this environment evidence. No runtime load flake or behaviour change was observed.

Gate 1 runs next on the committed, stable tree, after all owned AST/clone jobs stop, compared by identity against `recordings/base`, the added-only `base2`, and the full 73-case ORIGINAL characterization. Step 3 has not started.

### Full-suite gate 1 — committed-tree evidence and stop (2026-10-07)

| Checkpoint | Commit | Facade lines | Created application files |
| --- | --- | ---: | --- |
| 0b preset windows on ORIGINAL | `2dfcab7e6` | 2,129 (= R) | None |
| L verified strict Linux originals | `22e3084ff` | 2,129 (= R) | None |
| 1 widgets/tokens and registrations | `65cf79a56` | 977 | 7, largest 291 |
| 2 eager owners, data/format and live composition | `d028465ab` | 740 | 5, largest 160 |

Gate 1 uses committed **`d028465ab047cc38d4fb021162733f6f15d26776`**, tree **`7278ce4c15d6da418c1fc39194dae149445f9a14`**, with all owned AST/self-test/clone jobs stopped beforehand. Whole suite paths **[]**, flags **`--no-pub --concurrency=4`**; HEAD and tested tree are stable, with no untracked inputs. SDK matches R: Flutter **3.44.8**, Dart **3.12.2**, framework `058e0af2c2b57e369d905a03ac9748b0ebf543c6`.

- **PASS by identity:** **12,105 success / 13 failure / 28 error / 20 skipped**, **12,166 identities / 1,190 suites**, raw runner **exit 1** for the known outcomes. Against untouched R's **12,028 / 13 / 32 / 20**, there are **73 added passing identities**, **no new failure**, **no missing identity** and **no new skip**. Four formerly errored tests now pass: the Xtream 50k ingest case and the three WebDAV shard/interrupted-apply cases. Their services and tests are unchanged; this records observed recovery, not a code fix or a proved cause.
- `gate1-against-base.txt` and `gate1-against-base2-union.txt` both **PASS**. `base-with-base2.json` is explicitly an observed identity union, not another suite run: R's complete baseline plus the **73/73 ORIGINAL** characterizations; the latest added-only **five-case base2** is audited as a passing subset. Union comparison has **zero additions**. All **73/73 recording outcomes** in gate 1 equal ORIGINAL; the complete event projection and official comparison are `gate1-recordings-projection*` / `gate1-against-original-recordings.txt`. Final identity/provenance audit is `gate1-summary.json`.
- **No load flake / timeout observed**, no isolated rerun or full retry needed. Known-risk whole-file results are remote pairing **5/5**, Xtream **10/10**, catalogs manage/MDB **22/22**, WebDAV engine/shards **105/105**, PIN screen **6/6**. `gate1-timeout-audit.json` and `gate1-flake-NOTE.txt` preserve this. No test, assertion, wait, baseline or behavioural failure allowlist changed; no `--record`, `--update-goldens` or golden recapture.
- Per-step evidence is reused at this documentation-only gate checkpoint because every executable input remains the Step 2 committed input: all **20 other manifest outputs** byte-identical to R; recordings **7 positives / 116 checker + 116 reader rejections**, inventory **2 / 9**; **73/73 root and normal-clone** characterizations, **13/13** shared shape/theme guards; architecture/real negatives, format, scoped analyzer/helper, strict member comparison, sizes, storage and diff checks pass. Final whole analyzer is **1,719 vs 1,709**: the exact R outside-feature multiset plus the ten already-probed feature diagnostics, with no new strict identity. Source inputs are attested to the normal clone after pub get; no dependency/native/player/service/other feature application changes.
- Three strict macOS goldens pass and all six PNG bytes remain the Step L bytes (`gate1-golden-attestation.json`). Linux originals were independently double-captured/replayed by Claude and hash-verified in Step L; post-move Linux execution remains Claude's task under the no-Docker constraint.
- **Verification-command NOTE:** an extra comparison initially applied the 73-case scoped baseline to the entire full-suite output, which necessarily called unrelated known failures new. This invalid-domain output is retained as `gate1-against-original-recordings-full-scope-invalid.txt`; an explicit event-domain projection, independently checked against all 73 actual gate outcomes, passes the unchanged helper. `gate1-comparison-NOTE.txt` records the correction. A summary script initially expected an exit field absent from the helper environment schema; raw exit 1 is instead attributed to the observed run stdout and runner's done event. A final source audit initially compared the CI workflow to Step L, preceding its required Step 1 registration; the correct Step 1 comparison is byte-identical. Neither correction changes execution or acceptance criteria.

The evidence checkpoint's subject contains **gate**: `test(recordings): gate 1 committed-tree evidence`; its resolved commit and unchanged lib/pubspec attestation are in `gate1-checkpoint.json`. The only implementation adjustment is the Step 1 recordings-only ink continuation rule needed for normal formatting of the registered colour names; it has real positive/negative probes and preserves the original 27 expressions.

**STOP after gate 1.** `completed_step` is **2**, explicit `mandatory_qualification` is **true**, `RECORDINGS_COMPLETE` remains false, the size-baseline facade entry remains 740, and the frozen composition contains only **data/format**. There are no `actions`, `scheduling` or `layout` destination files, no build forwarder, no completion registration or Step 3 work. No Docker, emulator/device, flutter run, push, merge, rebase or branch switch.

### Step 3 — actions, scheduling, layout and retained build forwarder (2026-10-07)

Gate 1 was accepted by Claude before this work. Checkpoint subject: `refactor(recordings): step 3 actions scheduling and layout`; resolved objects and measurements are recorded in `step3-checkpoint.json` under the common-directory recordings evidence.

- Three new bridge files: actions **150**, scheduling **281**, layout **260** lines. The frozen composition now constructs **data, actions, scheduling, format, layout**, once, in that order. All prior destinations except the section map are byte-identical to Step 2. Services, players, native code, other features and both pubspec objects are unchanged. The handoff remains confined to its registered actions file; no production seam or behaviour fix.
- The facade is **101 physical lines**: imports **9**, blanks **9**, original header **9**, public Widget **6**, State boundary **3**, eager owners/lazy live composition **11**, lifecycle plus `_onRevision` **52**, exact annotated build forwarder **2**. The public Widget is byte-identical to R. Lifecycle/teardown and comments remain verbatim after the registered receivers; the reader validates the registered forwarder before excluding it from implementation ownership. `forwarded_annotation_occurrences` permits only the moved build body's leading override to drop. The size-baseline entry is lowered to 101 until Step 4.
- `completed_step: 3` selects the exact Step 3 composition specification. The actual tree passes and the same sources under Step 2 are rejected by **Frozen step-2 composition changed** (`step3-real-composition-selection.json`). Explicit `mandatory_qualification: true`, owner qualification, aliases, getter sets and all callback/push envelopes remain active.
- All five root tooling commands pass: current reader, manifest self-test, reader self-test, text inventory self-test and standalone fixtures. Reports remain **7 positives / 116 checker + 116 reader rejections**, inventory **2 positives / 9 rejections**. All **20 other manifests** pass with stdout byte-identical directly to R (`step3-integrated-direct-R-compare.json`); separate parser-package copies under `.dart_tool`, copied dills deleted. Fresh normal-clone execution of all completed tooling is scheduled after gate 2, as requested; no new self-test implementation was added at Step 3.
- **73/73** unchanged characterizations and **13/13** shape/theme guards pass. Three strict macOS scenes pass; all six PNGs and all characterization inputs equal Step L. Aggregate/floor **12/488**, shape calls zero; owned theme **95**, settings surface **657**, light ink **27** (all primary), white-sweep excluded. The actual import walk reaches eight moved paint files plus five shared widgets, **181 sites**. Linux replay after moves remains Claude's separate task; no Docker execution here.
- Architecture **1,530 migrated files**, real probes **6 positives / 18 rejections**, sizes, CI/local format, scoped analyzer/allowlist, strict member identities, storage checks and diff checks pass. Final whole analyzer after owned AST jobs stopped: **1,719 vs R 1,709**, exact outside-feature multiset unchanged (**added [] / removed []**), only the nine alias warnings and recursive getter info predicted by the 0b probe. Strict additions are empty. The preliminary analyzer output is retained separately.
- No load flake observed. `step3-command-NOTE.txt` records two corrected read-only command arguments (comparison pathname and rendered-set label); neither changed inputs or acceptance. ORIGINAL mutation evidence is unchanged: **94 B / 43 S**, all rejected with no survivors, source-contract excluded from B.

Step 3 is complete. Step 4 completion registration and gate 2 are next; no completion flag was activated in this checkpoint.

### Step 4 — completion registration and local checks (2026-10-07)

Parent `8989e95ee`; checkpoint subject `refactor(recordings): step 4 completion`. Resolved objects are recorded in `step4-checkpoint.json`. Gate 2 runs only after this checkpoint is committed.

- `RECORDINGS_COMPLETE = True`, measured `RECORDINGS_FACADE_CAP = 101`, empty size exceptions, facade in `COMPOSITION_ROOTS` with its lifecycle comment, and the existing conditional facade registration in `main()` now active. `TEMP(recordings)` is rejected in the facade and every feature destination, including the former temporary bridge. The facade's size-baseline entry is removed; all other entries remain unchanged. Explicit `mandatory_qualification: true` remains set.
- The real architecture test now checks completion/config consistency, the actual facade's measured cap and composition registration, and uses the actual completed facade for cap + 1, missing and TEMP negatives. **7 positives / 18 real-main rejections** pass. Architecture covers **1,531 migrated files**. CI format includes the facade and `test/support/recordings_*.dart`; CI analyze includes the facade **before `| tee analyze.txt`**. Both exact commands pass, as do the analyzer helper, local format/scoped analysis, sizes, storage checks and diff checks.
- Application/native files are byte-identical to Step 3; services, players, other features and both pubspecs remain unchanged from R. Only five tooling/configuration files change. The completed config selects the frozen Step 3 composition; actual sources pass and the Step 2 specification rejects them by name (`step4-real-composition-selection.json`).
- Final facade `wc -l`: **101**, equal to the enforced cap. AST physical spans sum to 101: imports **9** + blanks **9** + header **9** + public Widget **6** + State boundary **3** + owners/composition **11** + lifecycle/`_onRevision` **52** + annotated build forwarder **2**. Public Widget bytes equal R; no implementation remains behind a temporary forwarder.

Final application destinations, including all imports, comments and blanks:

| File (`recordings_hub_*.dart`) | Physical lines |
| --- | ---: |
| presentation/tokens | 8 |
| presentation/buttons | 291 |
| presentation/chrome | 148 |
| presentation/live_card | 156 |
| presentation/library_row | 189 |
| presentation/empty_states | 259 |
| legacy_recordings/schedule_row | 176 |
| legacy_recordings/owners | 49 |
| legacy_recordings/dependencies | 18 |
| legacy_recordings/sections | 20 |
| legacy_recordings/data | 160 |
| legacy_recordings/format | 102 |
| legacy_recordings/actions | 150 |
| legacy_recordings/scheduling | 281 |
| legacy_recordings/layout | 260 |

- All five root tooling commands pass, **7 positives / 116 checker + 116 reader rejections**, inventory **2 positives / 9 rejections**. All **20 other manifests** pass with stdout byte-identical directly to R, isolated parser copies and copied dills deleted (`step4-integrated-direct-R-compare.json`). Final fresh normal-clone execution of every new tool and the 20-manifest matrix follows gate 2, as explicitly requested.
- **73/73** unchanged characterizations (including strict macOS goldens) and **13/13** shape/theme guards pass, with identical ORIGINAL identities. All six PNG bytes and all characterization inputs remain Step L. Aggregate/floor **12/488**, zero shape calls; theme owned/settings surface **95/657**, primary light ink **27**, white-sweep excluded; rendered walk **13 files / 181 sites**. Post-move Linux replay remains Claude's separate task; no Docker run here.
- Final whole analyzer after owned AST jobs stopped: **1,719 vs R 1,709**, outside-feature **added [] / removed []**. The ten feature identities remain precisely the nine alias-constructor warnings and recursive getter info predicted by the 0b probe; no new strict identity. Preliminary analyzer output is retained separately. ORIGINAL mutation reports remain **94 B / 43 S**, no survivors; no source-contract evidence counted as B. No load flake or implementation deviation in Steps 3–4, and no regression recording or behavioural allowlist change.

Completion implementation is committed before the full-suite gate. Gate 2 and the final normal-clone proof remain pending in this checkpoint.

### Gate 2 — committed completion and final normal-clone proof (2026-10-07)

Implementation checkpoints: Step 3 **`8989e95ee`**, Step 4 **`598ac492e0e1bd23668caa0dda0c98f5bd452120`**. Gate 2 and the fresh normal clone use the latter committed input, tree **`90536a004eb2b0e061da542137b5d66a44e1154d`**. Evidence remains exclusively in the git-common-directory `refactor-evidence/recordings/`. The final documentation-only checkpoint's subject is `test(recordings): gate 2 completion evidence`; its resolved objects and unchanged application inputs are recorded after commit in `gate2-checkpoint.json`.

- **PASS by identity:** final full-suite `gate2-retry1`, paths **[]**, **`--no-pub --concurrency=4`**, SDK Flutter **3.44.8** / Dart **3.12.2**, framework `058e0af2c2b57e369d905a03ac9748b0ebf543c6`: **12,105 success / 13 failure / 28 error / 20 skipped**, **12,166 identities / 1,190 suites**, raw runner **exit 1** for the known outcomes. Every outcome equals gate 1 by identity. `gate2-against-base.txt`, `gate2-against-base2-union.txt` and `gate2-against-gate1.txt` all **PASS**: no new failure, missing identity or new skip; **73 added passing identities** against R, zero additions against the observed base/base2 union or gate 1. All **73 ORIGINAL** recording outcomes, including the latest **five added-only base2** preset identities, remain passing. The four recovered R errors recorded at gate 1 remain passing. Provenance and outcome audits are in `gate2-summary.json`.
- **Load-flake NOTE:** the initial committed-tree run was **12,102 success / 13 failure / 31 error / 20 skipped**. The Xtream 50k ingest case timed out at 30 seconds, and two MDB import-dialog cases failed their widget lookups (duplicate Series and mine/liked/top categories). Those initial regressions and failed comparison outputs are retained. Their recursive local source/test dependency closures are byte-identical to R (**72 Xtream / 175 MDB files**); no recordings dependency enters either closure. Sequential, whole-file isolated reruns with **`--no-pub --concurrency=1`** pass **10/10 Xtream** and **35/35 MDB**, with outcomes equal to the corresponding gate 1 identities. A second complete suite on the same unchanged committed input then matches gate 1 exactly; no result overlay, assertion/wait change, regression recording or behavioural allowlisting. Details: `gate2-flake-NOTE.txt`, `gate2-isolated-results.json`, source attestations and both complete event streams. Final known-risk files pass remote pairing **5/5**, Xtream **10/10**, catalogs manage/MDB **22/22**, WebDAV **105/105**, PIN **6/6**, plus MDB import dialogs **35/35**.
- **Final fresh normal clone:** `.git` is a directory, default cloned branch already resolves to Step 4, **no checkout/branch switch**, `flutter pub get` passes and the lockfile remains unchanged. All **five** recordings tooling commands pass, with stdout and reports byte-identical to the completed root results. The actual checker CLI, architecture main and **7 positives / 18 real-main architecture rejections**, file sizes, exact CI format/analyze commands, analyzer helper and local format/analyze checks pass (**nine quality commands**). All **73/73** clone characterizations pass, including the three strict macOS goldens. All **20 other manifests** pass in this clone with stdout byte-identical directly to R; every command uses its own parser-package copy under `.dart_tool`, with copied `*.dill` files deleted. `completed-final-normal-clone-input-attestation.json` binds every changed executable input to the root commit and clone; the integrated direct-R comparison and individual logs are retained.
- The final facade is **101 lines**, enforced cap **101**. Physical spans remain imports **9** + blanks **9** + header **9** + public Widget **6** + State boundary **3** + owners/composition **11** + lifecycle/`_onRevision` **52** + annotated build forwarder **2**. The **15 destinations** have the measured sizes in the preceding table, maximum **291**; no size exceptions. `completed_step: 4`, `completion_step: 4`, explicit `mandatory_qualification: true`, the frozen Step 3 composition, handoff registration, `RECORDINGS_COMPLETE = True`, facade composition/main registration and TEMP rejection remain enforced; the facade size-baseline entry is absent. Whole analyzer remains **1,719 vs R 1,709**, exact outside-feature multiset unchanged, only the nine alias warnings and recursive getter info predicted by the ORIGINAL probe; no new strict identity.
- ORIGINAL mutation evidence remains **94/94 B**, **43/43 S**, **7 positives / 116 checker + 116 reader rejections** and separate inventory **2 positives / 9 rejections**; **no survivors**. B evidence excludes the source contract and reader/checker failures. Final per-step characterization, shape/theme, source/architecture, format/analyzer and storage checks are reused without invalidated executable inputs. All six macOS/Linux PNG bytes remain Step L; strict macOS replay passes. Claude's moved-tree Linux replay remains separate under the no-Docker instruction; no Linux execution is claimed here.
- `gate2-protected-source-attestation.json` proves Step 4 application files equal Step 3, only the planned recordings destinations/facade differ from R, and services, players, native code, other feature application files and both pubspec objects remain unchanged. No new implementation deviation in Steps 3–4. `gate2-command-NOTE.txt` records a corrected read-only golden audit argument (repository-relative git object path); no input or acceptance criterion changed.

**STOP after gate 2 evidence is committed.** Steps 3–4 and completion checks are finished; no further extraction, Docker, emulator/device, flutter run, push, merge, rebase or branch switch.
