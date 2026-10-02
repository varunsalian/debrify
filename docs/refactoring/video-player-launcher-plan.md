# Video player launcher refactor — plan

Written 2026-10-02 on `refactor/codebase` at `204b1011`. Follow
[AGENTS.md](../../AGENTS.md). This page plus AGENTS.md is everything the
executing agent needs.

Work on the existing `refactor/codebase` branch; don't create a new one.
Commit after every step (more often is fine). Never push to `origin`; push to
`private` only if the goal you were given says so.

## Goal

`lib/services/video_player_launcher.dart` is 6,594 lines. Every in-app play
goes through it: Flutter player, Android TV native player, external players,
DeoVR and IPTV on Android TV. It also owns native progress and scrobbling,
metadata push to the native player, and Trakt/Simkl/MDBList progress seeding.

Split it into a new feature, `lib/features/player_launch/`, **moving code
verbatim**, and leave `lib/services/video_player_launcher.dart` as a small
facade. Callers don't change.

## What it contains (line numbers at `204b1011`)

| Lines | Area | Key symbols | Context/UI? |
| --- | --- | --- | --- |
| 1–233 | Imports, file-private session state, redirect resolver | top-level `_traktLastScrobbleAction`, `_traktLastKnownProgress/Season/Episode`, `_traktHeartbeatTimer`, the same five for Simkl, `_resolvedStreamCache`, `_redirectCache`, `_cacheResolvedStream`, `_resolveRedirectUrl`, `_clearResolvedStreams` | no |
| 234–604 | Launch arguments | `VideoPlayerLaunchArgs` (371 lines, incl. `copyWith`, and `toWidget()` which constructs `VideoPlayerScreen`) | `toWidget()` only |
| 605–928 | Public API | `VideoPlayerLauncher` class start: `debugNativeResumePositions`, `debugNativePlaybackSession`, `resumeIdForEntry`, `showAuthenticatedWebDavPlayerNotice`, `push`, `_refreshTraktEpisodeProgress`, `_seedSimklEpisodeProgress`, `_seedMdblistEpisodeProgress` | some |
| 929–1415 | Launch router | `_push` (487 lines) | yes |
| 1416–1605 | External launch commit and seeding | `_commitExternalLaunchSource`, `_seedTrackerContinueWatching`, `launchExternalIfConfigured` | some |
| 1606–2383 | External players, DeoVR, disclosure, analytics | `_launchWithExternalPlayer`, `_launchWithDeoVR`, `_confirmExternalDisclosure`, `_runWhenCoveredByExternalActivity`, `_notifyOnReturnFromExternalActivity`, `_isAndroidTv`, `_analyticsProviderLabel`, `_analyticsPlaylistProviderLabel`, statics `_externalReturnArmTimeout`, `_armedReturnObserver` | yes |
| 2384–3700 | Android TV native launch | `_launchOnAndroidTv` (**1,317 lines**) | no (native bridge) |
| 3701–3866 | IPTV on Android TV | `_launchIptvOnAndroidTv` | no |
| 3867–4415 | Metadata push and MDBList native session | `_fetchAndPushMetadataAsync` (421), `_saveSeriesPosterToPlaylist`, `_initializeNativeMdblist`, `_ensureNativeMdblistSession`, `_closeNativeMdblist`, `_nativeMdblistTarget`, `_simklSeriesSEUnresolved` | no |
| 4416–5002 | Native progress and completion | `_handleProgressUpdate` (528), `_handlePlaybackFinished` | no |
| 5003–5196 | Entry URL resolution | `_resolveEntryUrl`, enum `_PlaybackContentType` | no |
| 5197–6269 | Android TV payload model and builder | `_AndroidTvPlaybackPayload`, `_AndroidTvPlaybackItem`, `_AndroidTvSeriesSeason`, `_AndroidTvSeriesEpisode`, `_LauncherEntry`, `_AndroidTvPlaylistResolver`, `_AndroidTvPlaybackPayloadBuilder` (625) | no |
| 6270–6594 | Resume record parsing, observers | `_stateFromRecord` (270), `_PerItemState`, `_NavigationMaps`, `_AppCoverObserver`, `_AppReturnObserver` (`WidgetsBindingObserver`) | observers only |

**Public API (production and tests):** `push` (66 uses), `readMovieResumeState`,
`debugNativePlaybackSession`, `debugNativeResumePositions`, `resumeIdForEntry`,
`shouldExplainExternalPlayerFallback`, `externalPlaybackUrlFor`,
`showAuthenticatedWebDavPlayerNotice`, `normalizeScrobbleFlags`,
`androidExternalVideoIntent`, `shouldEnableMdblistTracking`,
`launchExternalIfConfigured`, `isExternalPlayerDefault`, and the
`VideoPlayerLaunchArgs` class (with `toWidget()`, used by 7 call sites).
About 45 files import the launcher.

Line numbers are approximate. Re-derive them; the dependency report (step 0)
decides.

## Shared state and cross-area dependencies (checked at `204b1011`)

- **File-private scrobble session state** is shared by the Android TV launch
  (2384–3700), the progress handlers (4416–5002) and the public API section:
  the ten Trakt/Simkl top-level variables, including **two heartbeat
  `Timer`s**. Today these are file-private globals. They move into **one
  owner class**, `data/native_scrobble_session.dart`, as static members with
  the same initializers. The only edit is the qualifier at use sites. Don't
  scatter them as public top-level variables across files.
- **The redirect and stream caches** (`_resolvedStreamCache`,
  `_redirectCache`) and their three functions are used by entry-URL
  resolution, the payload builder, progress handling and the public API.
  They move together into `data/stream_redirect_resolver.dart`, each cache
  with one owner.
- **`_PlaybackContentType`** is used by six areas, so it moves first, to
  `models/`.
- **Payload classes** (`_AndroidTvPlaybackPayload` and friends,
  `_LauncherEntry`) are used by the Android TV launch, metadata push and
  progress handling. They move together to `models/`, or to `data/` where they
  carry behaviour such as the playlist resolver and the builder.
- **`_stateFromRecord`, `_PerItemState` and `_NavigationMaps`** are used by
  the payload builder.
- **The observers** (`_AppCoverObserver`, `_AppReturnObserver`) are used by
  the external-player code and import Flutter widgets, so they go in the
  bridge folder.
- **The progress-seeding helpers** in the public API section
  (`_refreshTraktEpisodeProgress` and the Simkl and MDBList ones) are used by
  `_push`.
- **`_launchOnAndroidTv`** calls `_launchIptvOnAndroidTv`,
  `_fetchAndPushMetadataAsync`, `_initializeNativeMdblist`,
  `_closeNativeMdblist`, `_handleProgressUpdate`, `_handlePlaybackFinished`,
  `_resolveEntryUrl`, the payload builder and the playlist resolver. So all of
  those move before it, or with it.

## Destination layout

`lib/features/player_launch/`:
- **`models/`**: `VideoPlayerLaunchArgs` (without `toWidget`, see below),
  `PlaybackContentType`, the payload data classes, `PerItemState`,
  `NavigationMaps`, `LauncherEntry`. Only pure data, under the guard's model
  rules.
- **`data/`**: everything with no `BuildContext` and no widget or UI import:
  - session state (`native_scrobble_session.dart`);
  - the redirect resolver and caches;
  - resume-record parsing (`_stateFromRecord`);
  - entry-URL resolution;
  - the payload builder and playlist resolver;
  - metadata push and the MDBList native session;
  - progress and completion handling;
  - IPTV on Android TV;
  - the Android TV native launch.

  These call native-bridge services (`AndroidTvPlayerBridge` and others in
  `lib/services/`), which the data layer may do.
- **`presentation/legacy_launch/`**: a named, temporary bridge for code that
  takes a `BuildContext` or shows UI and still calls legacy services
  directly: `_push`, external players, DeoVR, disclosure dialogs, observers,
  analytics labels, the external launch commit and seeding, the WebDAV
  notice, and the `toWidget` extension.

Suggested files (keep each under 500 lines, prefer 300; the dependency report
decides): `native_scrobble_session.dart`, `stream_redirect_resolver.dart`,
`resume_record_parser.dart`, `entry_url_resolver.dart`,
`android_tv_payload_builder.dart`, `android_tv_playlist_resolver.dart`,
`native_metadata_push.dart`, `native_mdblist_session.dart`,
`native_progress_handler.dart`, `iptv_android_tv_launch.dart`,
`android_tv_native_launch.dart`, `launch_router.dart`,
`external_player_launch.dart`, `deovr_launch.dart`,
`external_disclosure.dart`, `external_return_observers.dart`,
`external_launch_commit.dart`, `video_player_launch_widget.dart`.

**One required non-verbatim edit.** `VideoPlayerLaunchArgs.toWidget()`
constructs `VideoPlayerScreen` (from `lib/screens/`), so the class can't
live in `models/` as is. Move the method body verbatim into
`extension VideoPlayerLaunchArgsWidget on VideoPlayerLaunchArgs { VideoPlayerScreen toWidget() {...} }`
in `presentation/legacy_launch/video_player_launch_widget.dart`. The facade
re-exports it, so the 7 `args.toWidget()` call sites compile unchanged. Before
doing it, confirm that nothing subclasses or implements
`VideoPlayerLaunchArgs` and that `toWidget` isn't torn off; extension dispatch
is static. Record the result in Progress.

**Size exception.** `_launchOnAndroidTv` is one 1,317-line method. Move it
whole into `data/android_tv_native_launch.dart`, which will be about 1,400
lines. That breaks the 800-line ceiling, so it is a documented temporary
exception. Its exit milestone is splitting the method in a later control-flow
change, and Progress records it. Every other file follows the normal caps.

## Invariants (every step)

1. **Native bridge payloads are byte-identical.** The Android TV payload
   (fields, ordering, headers, subtitle and audio settings, playlist and
   series structure, resume positions), `MethodChannel` names and arguments,
   intents and external-player arguments don't change. AGENTS.md: "Preserve
   native bridge payloads, headers, subtitle/audio settings, fallback
   policies, session identity, progress handling, and teardown ordering."
2. **One owner per piece of state.** Each scrobble field, heartbeat timer,
   cache, armed observer and timeout constant has exactly one declaration,
   with the same initializer. Timers are started, cancelled and replaced at
   the same points.
3. **Same progress and tracker behaviour:** the same throttling, heartbeat
   cadence, scrobble transitions, completion thresholds, resume writes,
   tracker seeding order and MDBList session open/close points.
4. **Same routing:** the Flutter, native, external, DeoVR and IPTV decisions,
   PiP route (`videoPlayerRoute(...)` / `FrozenLegacyPageRoute`), disclosure
   prompts and return-from-external behaviour, in the same order.
5. **Logs are unchanged**, including the `[RedirectResolver]` prefixes.
6. No Riverpod, providers or new DI. Plain classes and functions.

## Technique: move-only

- **Move declarations verbatim** into top-level functions or small `final`
  classes with static members. Allowed edits:
  - qualifiers at call sites;
  - imports;
  - dropping a leading `_` when another file now uses the symbol (for
    example `_PlaybackContentType` → `PlaybackContentType`);
  - turning the file-private session globals and caches into static members
    of their single owner class, with the same names minus `_` and the same
    initializers;
  - the `toWidget` extension above.
- **Not allowed:**
  - reordering `await`s, guards, timer starts or cancels, bridge calls or map
    insertions in payloads;
  - merging look-alike helpers;
  - splitting `_launchOnAndroidTv`, `_push`, `_handleProgressUpdate`,
    `_fetchAndPushMetadataAsync` or the payload builder.
- **Temporary cross-calls.** Moved code that still needs an unmoved private
  member calls it through `VideoPlayerLauncher.<name>`, with the `_` dropped
  and `// TEMP(vpl): moves in step N` on the member. Only
  `presentation/legacy_launch/` files may make such calls; `data/` and
  `models/` code never does. Step 5 removes every marker.
- Dependencies run `presentation → data → models`. `data/` and `models/` keep
  the guard's rules (no widget imports and no `BuildContext`; Flutter only via
  `package:flutter/foundation.dart` in `models`/`application`/`data`). If a
  "no UI" member turns out to need a widget import, it belongs in the bridge
  folder.

## Steps

| # | Work | Notes |
| --- | --- | --- |
| 0 | Baseline, dependency report, verbatim checker, source-text inventory | Nothing moves. |
| 1 | Create the feature, register it in the guard and CI. Move `models/` (`PlaybackContentType`, `VideoPlayerLaunchArgs` and the `toWidget` extension, payload data classes, `PerItemState`, `NavigationMaps`, `LauncherEntry`) and the shared `data/` cores (`native_scrobble_session.dart`, `stream_redirect_resolver.dart`). | Ports the theme source guard (see Source-text tests). |
| 2 | `data/`: resume-record parsing, entry-URL resolution, payload builder and playlist resolver, MDBList native session, metadata push, progress and completion handling | All context-free. |
| 3 | `data/`: IPTV on Android TV, then `_launchOnAndroidTv` (size exception) | **Full-suite gate 1** after this step. |
| 4 | `presentation/legacy_launch/`: observers, external players, DeoVR, disclosure, analytics labels, external launch commit and seeding, progress-seeding helpers, WebDAV notice, `_push` | One commit per cohesive group is fine. |
| 5 | Facade, guards, CI, **full-suite gate 2** | See "Definition of done". |

### Step 0 — baseline, report, checker, inventory

1. **Baseline at `204b1011`.** The storage follow-up changed Dart after the
   last full run, so record a new one:
   `python3 dev/tool/suite_evidence.py run vpl/base`. `<E>` is
   `$(git rev-parse --git-common-dir)/refactor-evidence`. Then record the
   analyzer: `flutter analyze > <E>/vpl/analyze-base.txt`. The SDK must be
   Flutter 3.44.8; if it isn't, stop and ask.
2. **Dependency report**, committed as `docs/refactoring/video-player-launcher-deps.md`:
   - every top-level and class member of the file (variables, functions,
     classes, enums, static fields and methods), with its destination file and
     step;
   - every private symbol used across destination files, and how it is
     shared;
   - every member's layer, justified by the imports it actually needs.

   Nothing may be unresolved before step 1.
3. **Generic verbatim checker: `dev/tool/check_verbatim_moves.py`**, reusable
   for later refactors (the player screen is next).
   - **Inputs:** an original file at a git revision, a set of destination
     files, and a small rename table (TSV, for example
     `dev/tool/vpl_renames.tsv`).
   - **What it does:** for every declaration in the original (top-level
     members, classes, and class members including static fields and their
     initializers), it finds exactly one destination declaration. It compares
     their complete text: modifiers, types, parameters **and their
     defaults**, annotations and bodies. Normalisation is only whitespace
     outside string literals, qualifiers, and the renames listed in the
     table.
   - **What it reports:** missing, duplicated and changed declarations. The
     `toWidget` extension and the session-state owner are listed as expected
     differences, each with its own exact check.
   - **Self-tests:** negative fixtures must fail for a changed parameter
     default, a changed string literal, a reordered statement, a dropped
     `await`, and a duplicated declaration.
   - Commit it with its fixtures. It reads the original with
     `git show 204b1011:...`, so it runs locally, not in CI.
4. **Source-text inventory: `dev/tool/vpl_source_text.txt`.** List every test
   or tool that reads the launcher's source or asserts on its text. Known:
   - `test/manual_source_validation_contract_test.dart:39`
   - `test/android_tv_mdblist_progress_source_test.dart:15`
   - `test/native_player_settings_wiring_test.dart:12`
   - `test/media_server_watch_player_wiring_test.dart:18`
   - `test/media_server_player_resume_test.dart`
   - `test/theme/source_guard_test.dart:51,75,184`
   - `dev/tool/theme_rendered_set.py:58`

   Grep for more, including string literals that name `VideoPlayerLauncher`
   members. Each entry says which step ports it and how.

### Per step

1. Move the step's members verbatim. Fix call sites until `flutter analyze`
   on touched files reports nothing new. Port this step's source-text
   entries.
2. Run `dart format` on new files only. Don't reformat
   `video_player_launcher.dart` before step 5, because it has unformatted
   regions; by step 5 they have moved.
3. Record the whole-repo analyzer after formatting and compare it with the
   previous step:
   `suite_evidence.py compare --against <previous>.txt --relocate lib/services/video_player_launcher.dart=lib/features/player_launch/ <this>.txt`.
4. Run `check_verbatim_moves.py`, `check_search_architecture.py` and
   `check_file_sizes.py`. Run `check_file_sizes.py --update` when the old
   file shrinks.
5. Run the affected tests: every test importing the launcher, and every
   source-text inventory entry. Record them with
   `suite_evidence.py run vpl/stepN <paths>` and
   `compare --against <E>/vpl/base.jsonl`.
6. Self-check:
   `git diff --color-moved=dimmed-zebra --color-moved-ws=allow-indentation-change HEAD`.
7. Commit: `refactor: move <area> out of VideoPlayerLauncher`.

**Full-suite gates.** `suite_evidence.py run vpl/gate1` (later `vpl/gate2`),
then `compare --against <E>/vpl/base.jsonl`. `PASS` is required: no new
failures, no missing tests, no new skips.

### Source-text tests

- **`test/theme/source_guard_test.dart`**, ported in step 1 with the
  extension:
  - "VideoPlayerScreen is constructed only where the freeze exists": replace
    the launcher in its `allowed` set with the extension file. Exactly one
    shared factory remains.
  - "video_player_launcher pushes via FrozenLegacyPageRoute": in step 4,
    point it at the file containing the push (`launch_router.dart`). It still
    requires `videoPlayerRoute(` and still forbids `MaterialPageRoute`, in
    every file under `presentation/legacy_launch/`.
  - The line-184 entry keeps its meaning.
- **`dev/tool/theme_rendered_set.py`**: point it at the files that now hold
  the moved rendering-relevant code.
- **The other inventory entries** are ported in the step that moves the code
  they read. Positive and negative guards keep their meaning. A negative
  guard must scan every file that could now contain the forbidden text (the
  whole feature folder where unsure), not just one destination. Test names
  don't change.
- Never delete an assertion to make a move pass.

## Definition of done

1. **The facade.** `lib/services/video_player_launcher.dart` is **at most 300
   lines**: `VideoPlayerLauncher`'s public members forwarding to their owners,
   plus exports of `VideoPlayerLaunchArgs` and the `toWidget` extension. It
   has no state. Callers are unchanged. Register it in
   `check_search_architecture.py` with a 300-line cap, like the playback
   facade.
2. **Feature registration.**
   - `lib/features/player_launch/` is in the guard's `FEATURES`.
   - `presentation/legacy_launch/` is a named bridge folder: it may import
     `lib/services/`, never `http`, `shared_preferences` or `sqflite`. That
     means generalising `LEGACY_PLAYBACK_BRIDGE` to a tuple of bridge folders.
   - Every file is under 500 lines, except the documented
     `android_tv_native_launch.dart` exception, capped at its moved size.
3. **Checks.** `check_verbatim_moves.py` passes for every original
   declaration, with its self-tests. No `TEMP(vpl)` markers remain.
4. **Analyzer and tests.** The whole-repo analyzer chain adds no
   diagnostics. Gate 2 passes against `vpl/base.jsonl` and `vpl/gate1.jsonl`.
5. **CI.**
   - The format and analyze scopes cover `lib/features/player_launch` and the
     facade.
   - `dev/tool/ci_behavior_tests.txt` gains the source-text inventory tests,
     plus the tests that exercise the launcher's behaviour through
     `debugNativePlaybackSession`/`debugNativeResumePositions` and `push`
     (list them in step 0).
   - Any of their failures at `vpl/base` go in
     `ci_behavior_known_failures.txt` by exact identity.
   - Measure the job; split it rather than drop tests if it would pass about
     12 minutes.
   - CI passes on `private`.
6. **Progress records:** the step commits, the `toWidget` check, the size
   exception and its exit milestone, each moved piece of state with its owner,
   and the bridge folder's exit milestone (move service calls behind data
   contracts and dissolve the folder).
7. Stop after gate 2 and report. The user has Claude review
   `<step 0 commit>..HEAD`.

## Explicitly not in scope

- Splitting `_launchOnAndroidTv`, `_push`, `_handleProgressUpdate` or the
  payload builder into smaller methods.
- Any change to native payloads, channels, intents, the player screen or
  Kotlin/Swift code.
- Repointing the ~45 callers away from the facade.
- Bug fixes. Record any you find under "Found, not fixed", with file, symbol
  and a one-line repro.

## Progress

| Step | Commit | Launcher lines | Result |
| --- | --- | --- | --- |
| 0 | | 6,594 | |

## Found, not fixed

(none yet)
