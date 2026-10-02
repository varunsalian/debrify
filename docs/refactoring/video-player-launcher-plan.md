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
| 4416–5002 | Native progress and completion | `_handleProgressUpdate` (**527 lines**, 4416–4942), `_handlePlaybackFinished` | no |
| 5003–5196 | Entry URL resolution | `_resolveEntryUrl`, enum `_PlaybackContentType` | no |
| 5197–5644 | Android TV payload classes | `_AndroidTvPlaybackPayload` (includes mutable MDBList session objects and factories, 5232), `_AndroidTvPlaybackItem`, `_AndroidTvSeriesSeason`, `_AndroidTvSeriesEpisode`, `_LauncherEntry`, `_AndroidTvPlaylistResolver` | no |
| 5645–6538 | Payload builder | `_AndroidTvPlaybackPayloadBuilder`: **one 894-line class**, including the 10-line static `_stateFromRecord` (6270) | no |
| 6539–6594 | Small types and observers | `_PerItemState`, `_NavigationMaps`, `_AppCoverObserver`, `_AppReturnObserver` (`WidgetsBindingObserver`) | observers only |

**Public API (production and tests):** `push` (66 uses), `readMovieResumeState`,
`debugNativePlaybackSession`, `debugNativeResumePositions`, `resumeIdForEntry`,
`shouldExplainExternalPlayerFallback`, `externalPlaybackUrlFor`,
`showAuthenticatedWebDavPlayerNotice`, `normalizeScrobbleFlags`,
`androidExternalVideoIntent`, `shouldEnableMdblistTracking`,
`launchExternalIfConfigured`, `isExternalPlayerDefault`, and the
`VideoPlayerLaunchArgs` class (with `toWidget()`, used by 8 call sites).
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
- **`_PerItemState` and `_NavigationMaps`** are used by the payload builder.
  `_stateFromRecord` is a static method inside the builder and moves with it.
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
  `PlaybackContentType`, `PerItemState`, `NavigationMaps`, and the payload
  data classes that are plain data. Only immutable data, under the guard's
  model rules (AGENTS.md: models are immutable at boundaries).
  - **Documented exception:** `VideoPlayerLaunchArgs` is an immutable
    parameter bundle, but it carries borrowed callbacks and one borrowed
    mutable handle, `seriesSourceFetcher` (328). That fetcher keeps session
    flags (`series_source_fetcher.dart:238`) and mutates them while fetching
    (278), and `copyWith` passes the same object on (513).
  - The args never own or mutate it; they hand it to the player. Record this
    borrowed-handle exception in Progress. It goes away when the fetcher's
    session state moves behind a contract, out of scope here.
  - The payload's **mutable MDBList session objects and factories** (5232)
    stay in `data/`, with the payload type that holds them. Metadata push
    mutates their identity (4011), and teardown clears the factory before
    awaiting close (4408), so reference identity must be kept. The step 0
    report decides each class's layer.
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
re-exports it, so the 8 `args.toWidget()` call sites compile unchanged. Before
doing it, confirm that nothing subclasses or implements
`VideoPlayerLaunchArgs` and that `toWidget` isn't torn off; extension dispatch
is static. Record the result in Progress.

**Size exceptions.** Some declarations are too large to fit the caps when
moved whole, and splitting them is out of scope:

| Destination | Holds | Approx. size | Measured cap |
| --- | --- | --- | --- |
| `data/android_tv_native_launch.dart` | `_launchOnAndroidTv` (1,317-line method) | ~1,380 | 1,302 |
| `data/android_tv_payload_builder.dart` | `_AndroidTvPlaybackPayloadBuilder` (894-line class) | ~940 | 924 |
| `data/native_progress_handler.dart` | `_handleProgressUpdate` (527 lines) and `_handlePlaybackFinished` | ~650 | 584 |
| `presentation/legacy_launch/launch_router.dart` | Whole `_push`, public `push`, platform check | ~550 | 592 |

- **Guard:** `check_search_architecture.py` rejects every file under
  `lib/features` over 800 lines, and new files over 500 per plan.
  - In **step 1**, before any move needs it, add a named exception table to
    the guard (`PLAYER_LAUNCH_SIZE_EXCEPTIONS = {path: cap}`), with a reason
    comment each.
  - Exactly these four paths get exceptions. Each cap is its measured
    formatted size, set in the commit that creates the file. Every other
    feature file keeps the 500 target and the 800 ceiling.
- **Size ratchet:** `check_file_sizes.py --update` only lowers counts, so the
  commit creating each of the two over-800 files adds its baseline line by
  hand. That is the documented way to record an exception.
- Progress records all four, each with its exit milestone: split the method
  or class in a later control-flow change.

## What host tests can't prove

The native bridge returns immediately on non-Android hosts
(`lib/services/android_tv_player_bridge.dart:1866`). The debug harness
(`debugNativePlaybackSession`, 635) returns the builder's initial map, but
production adds fields afterwards (3442) and runs the finish, disposal and
next-episode ordering (3566).
- **Covered by host tests:** the builder's payload and resume positions,
  through the existing debug harness tests.
- **Add if possible without changing production code:** fake-clock tests
  (`fake_async`) of the Trakt and Simkl heartbeat timers' start and
  cancellation, through the existing handlers.
- **Pending:** the rest of the launch and finish sequence on a real Android TV
  device. Record it as pending in Progress. Don't claim parity for it.

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
  classes with static members. Allowed edits (each recorded in the ownership
  manifest, below):
  - qualifiers at call sites;
  - imports;
  - dropping a leading `_` when another file now uses the symbol (for
    example `_PlaybackContentType` → `PlaybackContentType`);
  - turning the file-private session globals and caches into static members
    of their single owner class, with the same names minus `_` and the same
    initializers;
  - the `toWidget` extension above;
  - **exactly three warning fixes.** These analyzer warnings would fail CI
    once the code is under `lib/features`, because CI's analyze is fatal on
    warnings:
    - `unnecessary_null_comparison` at 4849:25 and 5599:62;
    - `invalid_null_aware_operator` at 5599:87.

    Fix each in the smallest way the analyzer's message proposes. The
    analyzer proves these conditions always hold, so behaviour is unchanged.
    Record each one in the manifest as an expected difference. Don't fix,
    or suppress, any other diagnostic;
  - **the enum rename's log text.** Renaming `_PlaybackContentType` to
    `PlaybackContentType` changes its `toString()`, which logs interpolate
    (for example 3883).
    - The step 0 report must list every `toString()` or interpolation use of
      the enum. If any reaches a payload, persistence, a comparison or a
      native call, stop and ask.
    - If they are all logs, record the label change as an accepted, logged
      exception to Invariant 5.
    - Checked at `204b1011`: the native payload uses `contentType.name`
      (5311), which the rename doesn't change. Only logs use the full text
      (3883, 3891, 5889). The step 0 report re-confirms this.
- **User-approved amendment (2026-10-02):** remove `@visibleForTesting`
  only from the moved implementations of `debugNativeResumePositions`,
  `debugNativePlaybackSession`, `externalPlaybackUrlFor`,
  `shouldEnableMdblistTracking`, `normalizeScrobbleFlags` and
  `showAuthenticatedWebDavPlayerNotice`. Retain the original annotations on
  their facade forwarders. Cross-library calls otherwise introduce
  `invalid_use_of_visible_for_testing_member`. The manifest/checker verify
  each exact removal and retained facade annotation; no suppression or other
  annotation change is permitted.
- **User-approved amendment (2026-10-02):** only
  `presentation/legacy_launch/deovr_launch.dart` may retain its existing
  `package:http/http.dart` import. `_launchWithDeoVR` combines upload and UI;
  splitting it would violate this move-only batch. The guard names that exact
  path/URI pair; every other bridge keeps the HTTP prohibition. Exit milestone:
  move the JSON upload behind a data contract in a later control-flow change.
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
| 1 | Create the feature, register it in the guard (with the size-exception table) and CI. Move `models/` (`PlaybackContentType`, `VideoPlayerLaunchArgs` and the `toWidget` extension, payload data classes, `PerItemState`, `NavigationMaps`, `LauncherEntry`) and the shared `data/` cores (`native_scrobble_session.dart`, `stream_redirect_resolver.dart`). | Ports the theme source guard (see Source-text tests). |
| 2 | `data/`: first the resume helpers `readMovieResumeState` (724) and `resumeIdForEntry` (681), with facade forwarders; then resume-record parsing, entry-URL resolution, payload builder and playlist resolver, MDBList native session, metadata push, progress and completion handling | All context-free. The builder calls both resume helpers (6252, 6533), the native launch's source-playlist resolver calls `readMovieResumeState` (2702), and `readMovieResumeState` calls `resumeIdForEntry` (735). So they need a data owner before anything uses them; `data/` code may not call back through the launcher. |
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
   - **Ownership manifest** (`dev/tool/vpl_manifest.tsv`): one row per
     **leaf declaration** of the original: top-level variables, functions,
     enums and classes that move whole, and every member of a class that is
     split, `VideoPlayerLauncher` in particular. Columns: original name,
     destination file, destination class (or top level), new name, and an
     `expected_difference` note for the listed exceptions.
   - **Comparison:** each leaf is compared with its single destination
     declaration as complete text: modifiers, types, parameters **and their
     defaults**, annotations, initializers and body. Normalisation is only
     whitespace outside string literals, qualifiers, and the manifest's
     renames.
   - **Split classes:** a class being split, `VideoPlayerLauncher` above all,
     is never compared as a whole. Its members are leaves. The facade's
     forwarders are checked separately: each forwards to the manifest's
     owner with the same parameters, defaults and argument order.
   - **Intermediate steps:** unmoved declarations are compared in place in
     the shrinking original file, so every step covers every leaf.
   - **Expected differences:** each has its own exact check: the `toWidget`
     extension, the session-state owner (fields and initializers), the three
     warning fixes, and the enum rename.
   - **No vacuous passes:** it fails on an empty or incomplete parse (leaf
     count below the manifest's), and on a destination declaration the
     manifest doesn't know.
   - **Self-tests:** negative fixtures must fail for a changed parameter
     default, a changed string literal, a reordered statement, a dropped
     `await`, a duplicated declaration, a missing declaration, and empty
     input. A positive fixture must pass for a correctly split class.
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
    the launcher in its `allowed` set with the extension file.
    - The guard skips allowed files entirely, so also assert that the
      extension file contains **exactly one** `VideoPlayerScreen(`
      construction.
    - Mutation-check both cases: zero constructions fail, and a second
      construction fails.
  - "video_player_launcher pushes via FrozenLegacyPageRoute": in step 4,
    point it at the file containing the push (`launch_router.dart`). It still
    requires `videoPlayerRoute(` and still forbids `MaterialPageRoute`, in
    every file under `presentation/legacy_launch/`.
  - The line-184 entry keeps its meaning.
- **`dev/tool/theme_rendered_set.py`**: point it at the files that now hold
  the moved rendering-relevant code.
- **Stale guards.** `test/android_tv_mdblist_progress_source_test.dart:21`
  searches for a resolver signature that no longer exists (the real code is
  at 2524), so it fails before checking anything. Repair its markers to the
  real code at its new location, so it exercises its assertions.
  - Any repaired test that now passes is removed from
    `ci_behavior_known_failures.txt` in the same commit; `check` fails on a
    listed test that passes.
  - Every ported source guard must reach its assertions; a guard that fails
    on a missing marker hasn't been ported.
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
     `lib/services/`, never `shared_preferences` or `sqflite`; HTTP remains forbidden except for the user-approved exact DeoVR path/URI pair. That
     means generalising `LEGACY_PLAYBACK_BRIDGE` to a tuple of bridge folders.
   - Every file is under 500 lines, except the four files in the
     size-exception table (`android_tv_native_launch.dart`,
     `android_tv_payload_builder.dart`, `native_progress_handler.dart`,
     `launch_router.dart`). Each is capped at its measured moved size in the
     guard's exception table. No other file gets an exception.
3. **Checks.** `check_verbatim_moves.py` passes for every original
   declaration, with its self-tests. No `TEMP(vpl)` markers remain.
4. **Analyzer and tests.** The whole-repo analyzer chain adds no
   diagnostics. It removes exactly the three fixed warnings, and the moved
   code has no warnings, so CI's analyze step passes. Gate 2 passes against `vpl/base.jsonl` and `vpl/gate1.jsonl`.
5. **CI.**
   - The format and analyze scopes cover `lib/features/player_launch` and the
     facade.
   - `dev/tool/ci_behavior_tests.txt` gains the source-text inventory tests,
     plus the tests that exercise the launcher's behaviour through
     `debugNativePlaybackSession`/`debugNativeResumePositions` and `push`
     (list them in step 0).
   - Seed `ci_behavior_known_failures.txt` from the failures that **still
     fail at gate 2**, by exact identity, not from every `vpl/base` failure.
     A stale guard repaired during the port must not be listed:
     `suite_evidence.py check` fails on a listed test that passes.
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
| 0 | `cfe1e2cd` | 6,594 | Baseline, dependency report, manifest/checker/self-tests committed before any move. |
| 1 | `fb19821d` | 5,783 | Models/extension and single session/cache owners wired; comparisons PASS. |
| 2 | `5468465e` | 3,358 | Context-free resume, payload, metadata and progress owners wired; comparisons PASS. |
| 3 | `03420c5e` | 1,855 | Native/IPTV launch owners wired; full-suite gate 1 PASS. |
| 4 | `6c813b3b` | 238 | Presentation bridge owners wired; all 134 affected tests pass. |
| 5 | (gate 2 commit) | 186 | Forwarding-only facade, final guards/CI; gate 2 PASS against base and gate 1. |

### Step 5 / gate 2 evidence

- The formatted facade is **186 lines**, exports args and the widget extension,
  forwards all **13** original public methods, and holds no state. Its imports
  use the direct playlist/resume contracts. Production caller expressions remain
  unchanged. The architecture guard registers it with a **300-line cap** and
  rejects `TEMP(vpl)` throughout the feature and facade; none remain.
- **31** feature Dart files; only the four named size exceptions exceed 500.
  All caps equal moved sizes: native launch **1302**, builder **924**, progress
  **584**, router **592**. No other exception is introduced. Original session
  fields/caches retain their single owners and initializers documented above.
- `check_verbatim_moves.py --self-test`: all **154 leaves** and all forwarders
  pass; **23** self-tests pass/reject as expected. Forwarder checking preserves
  signatures/defaults and the actual owner/argument order; only a new call body's
  optional trailing comma is ignored. Original moved declarations still compare
  every punctuation token. Architecture and repo-wide size guards pass.
- Whole-repo `analyze-step5.txt` vs step 4 and the original baseline: **PASS**,
  no added diagnostics. Exactly the three planned warnings are removed, plus
  one formatting-only flow-control info. All remaining moved diagnostics are
  pre-existing infos. The final CI format scope (1,112 files) and scoped analyzer
  both pass locally, including the facade; no diagnostic is suppressed.
- `vpl/step5` vs base: **PASS**, all **134 affected tests succeed**.
- `vpl/gate2` vs **both** `vpl/base` and `vpl/gate1`: **PASS**,
  **10,304 success / 14 failure / 29 error / 20 skipped**. No new failures,
  missing tests or new skips. The six repaired guards and four heartbeat tests
  pass. Existing full-suite failures/errors are retained as evidence, not
  accepted by recording a new baseline.
- CI's failure list is seeded from exact gate 2 failures within its test scope:
  only the existing WebDAV appearance identity remains. No failure was added.
  The behavior scope is retained (gate 1 private job 8m05s). The gate 2 private
  CI run and final commit are reported at review handoff after pushing this commit.
- Real Android TV enrichment/finish/disposal/next-episode sequence checks remain
  **pending**. This host-only extraction evidence does not establish device parity.

### Step 4 evidence

- All remaining presentation declarations move to the named legacy bridge.
  `LaunchRouter` owns both public `push` and the whole private `_push`, plus
  the platform check, avoiding a circular import. Its measured **592-line**
  cap is the fourth and final size exception; exit is a later control-flow split.
- `ExternalActivityLifecycle` owns the original arm timeout and single
  armed-return observer, unchanged initializers and cover/return ordering.
  The observer classes move whole. Service calls still belong to this named
  temporary bridge; exit is to put them behind data contracts and dissolve it.
- The approved exact DeoVR HTTP path/URI exception is enforced; mutations
  reject HTTP in another bridge, other HTTP imports, preferences and SQLite.
  The method remains verbatim. Its upload moves behind a data contract later.
- `analyze-step4.txt` vs step 3: PASS, no added/removed diagnostics.
  `vpl/step4` vs base: PASS, all **134 affected tests succeed**.
  Source guards follow the seeding/router owners; the route guard scans every
  bridge Dart file for `MaterialPageRoute`, retaining the freeze assertion.
- Verbatim checker: all **154 leaves** and facade forwarders pass; **22**
  self-tests include static-state/header mutations and recursive/wrong-receiver
  forwarding rejection. Qualifier normalization never hides a changed receiver
  or the facade's actual dispatch owner. Architecture and size ratchet pass.
- The external-player method has formatter off/on comments outside its
  declaration: the formatter otherwise adds a comma to the original two-argument
  call even in preservation mode. Its full declaration retains original tokens;
  this changes no diagnostic rule. All other new bridge code is formatted.

### Step 3 / gate 1 evidence

- `check_verbatim_moves.py`: 154 leaves/all forwarders pass. Architecture and
  repo-wide size ratchet pass. Native launch is capped at its measured
  **1302 lines**, including imports; its over-800 baseline was added by
  hand. Exit: split the whole method during a later control-flow change.
- `analyze-step3.txt` vs step 2: PASS; no added diagnostics. Normal formatting
  removed one flow-control info without changing any declaration token.
- `vpl/step3` vs base: PASS, all **134 affected tests succeed**. The four
  stale MDBList guards and two manual-source guards now reach all assertions
  and pass: signature/connected-progress getter markers follow actual code;
  manual-source resolution preserves the cancellation argument; route
  checking follows the existing mounted/retirement `current()` guard and
  exact captured route. No production logic changes. Passing identities were
  removed from CI's historical failure list in this commit.
- `vpl/gate1` vs `vpl/base`: **PASS**, 10,304 success / 14 failure /
  29 error / 20 skipped; zero new failures, missing tests or new skips;
  six repaired source guards and four added heartbeat tests pass.
- Local CI behavior command: PASS, 2,060 success and the one known WebDAV
  appearance failure. Private CI passed at `e5856f4b`:
  https://github.com/varunsalian/debrify-refactor/actions/runs/36978433063
  (behavior job **8m05s**, below the 12-minute split threshold). The first
  run had a transient error in the IPTV auto-pin test; the same application
  passed its local targeted run and remote rerun. Diagnostic-only follow-up
  `e5856f4b` exposes unexpected errors/stacks and saves runner artifacts;
  verdicts and failure identities are unchanged.
- Android TV device sequence checks remain pending; host evidence is limited
  to the contracts documented above.

### Step 2 evidence

- `check_verbatim_moves.py --self-test`: 154 leaves/all facade forwarders
  pass, including exact user-approved annotation removal and its fixtures.
- `analyze-step2.txt` vs step 1: PASS, no added diagnostic; removed exactly
  the two null-comparison warnings and one null-aware warning specified in
  the plan. Imports alone remove unused/newly redundant wiring.
- `vpl/step2` vs base: PASS, 128 success / 6 existing failures, no missing
  tests or new skips; four added heartbeat lifecycle tests pass. These use
  fake clocks through the existing progress/finish handlers, cover both
  Trakt/Simkl starts and two-minute cadence, pause/completion cancellation
  and finish cleanup, with no production hook or logic change.
- The facade forwards both resume helpers directly to `MovieResumeState`.
  Data owners never call through the facade. `_stateFromRecord` remains
  inside the whole builder, as the declaration-splitting prohibition requires.
- Size exceptions: `data/android_tv_payload_builder.dart` **924** lines
  and `data/native_progress_handler.dart` **584** lines, exact caps in
  the architecture guard. The builder's over-800 size is registered by hand
  in the ratchet. Exit milestone for each: split the whole declaration in a
  later control-flow change. The builder has an external formatter off/on
  block because formatting an originally unformatted conditional adds a
  comma even with preservation mode; its original complete declaration and
  blank lines are retained. `dart format` still verifies the file.
- Source-text payload/builder references follow their new owners; remaining
  resolver/metadata/Flutter source guards are repaired at their inventory
  port steps, preserving their assertions.

### Step 1 evidence

- `check_verbatim_moves.py`: 154 leaves pass; architecture and file-size guards pass.
- `analyze-step1.txt` vs `analyze-base.txt`: no added/removed diagnostics.
- `vpl/step1` vs `vpl/base`: PASS, 124 success / 6 existing failures, no missing tests or new skips.
- Theme construction guard now scans the extension and requires exactly one construction; zero/two mutations are rejected by that assertion. The route-boundary tool registers the legacy bridge.
- Static state owner `NativeScrobbleSession`: all ten original Trakt/Simkl fields and heartbeat timers, unchanged initializers. `StreamRedirectResolver`: both caches and all three cache/redirect functions, unchanged initializers.
- Feature-scoped formatter uses `trailing_commas: preserve` and 100-column width to keep original punctuation after qualifying/indenting code. The checker caught and rejected the default formatter's comma edits.
- `SourcePlayerArgs` re-exports the facade extension for its indirect consumers; no existing call expression changes. MDBList source inventory starts scanning the original plus feature for moved payload fields.

### Step 0 evidence

- Application source/lockfile at HEAD `3bf55ea4` are identical to `204b1011`.
  Flutter 3.44.8 / Dart 3.12.2, framework `058e0af2c2`.
- `python3 dev/tool/suite_evidence.py run vpl/base`: 10,294 success,
  20 failure, 29 error, 20 skipped; complete JSON evidence under the git
  common directory's `refactor-evidence/vpl/`. Exit 1 is baseline evidence,
  not a passing full suite. Subsequent gates must pass the identity comparison.
- `flutter analyze > <E>/vpl/analyze-base.txt`: 836 existing diagnostics;
  launcher has three warnings and five infos. The only allowed warning
  removals are the three specified above.
- [Dependency report](video-player-launcher-deps.md): all 154 leaves and
  283 declarations including members of whole classes, destinations, imports,
  private cross-file edges, state owners and layer decisions; nothing unresolved.
- `check_verbatim_moves.py --self-test`: all 154 in-place leaves pass;
  correct split passes; changed default/literal/order/await, duplicate/missing/
  empty declarations and changed facade defaults/argument order are rejected.
  Token completeness is checked, including declarations with doc comments.
  The isolated parser uses pinned analyzer 14.3.0 and a checked-in tool lockfile;
  it changes no application dependency. Source fixtures use `.dart.txt` to
  keep tool-only packages and intentionally broken fixtures out of app analysis.
- `VideoPlayerLaunchArgs` has no subclass/implementation and no `toWidget`
  tear-off; all eight references are calls (seven test calls plus the router). Its borrowed fetcher exception
  remains until that service's session state moves behind a contract.
- Enum full-text uses are exactly the three log interpolations at original
  3883, 3891 and 5889; native/persisted projection uses `.name`. Accepted log
  label exception: `_PlaybackContentType` becomes `PlaybackContentType`.
- Android TV launch enrichment, finish/disposal and next-episode ordering
  remain **pending on a real Android TV device**. Host tests cover builder
  payload/resume behavior only.
- Temporary oversized original: `lib/services/video_player_launcher.dart`
  retains unmoved routing/native/tracker/external responsibilities through
  steps 1–4; extraction milestones are those steps, then the 300-line facade
  at step 5. Four whole-declaration exceptions will be measured on creation;
  their exit milestone is a later control-flow split.
- Bridge exit milestone: move legacy service calls behind data contracts and
  dissolve `presentation/legacy_launch/` in a later migration.

## Found, not fixed

(none yet)
