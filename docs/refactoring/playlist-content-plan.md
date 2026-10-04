# Playlist content view refactor — plan

Written 2026-10-04 against `ec997117` (file blob `4fc757c7`); revised after
Codex design review round 1 (launch probe scope, typed facade getters,
progress matrix, TV taps, profile writes, parallel tooling, Linux handoff).
Follow
[AGENTS.md](../../AGENTS.md). Read `docs/refactoring/pikpak-files-plan.md`,
`debrid-downloads-plan.md` and `torbox-downloads-plan.md` first, including
their Progress sections. This plan reuses their technique, checker, tooling,
staging and gate procedure (callback-identity checks, tree-recording
evidence, real-config fixtures, original-code worktree proofs, the wiring
checklist, Linux goldens captured from the original code in the calibrated
local Docker image, `analyzer_allowlist.txt`) and only states what differs.

Execution runs in its own git worktree on a branch cut from
`refactor/codebase` (other files are being refactored in parallel); Claude
integrates it and captures the Linux goldens. Commit after every step; never
push. Gate commits contain `gate`. Remote CI stays pending until Claude
pushes, so every step runs the local CI-equivalent commands.

**Execution prerequisite (parallel worktrees).** `suite_evidence.py check`
writes a fixed `/tmp/suite_evidence_check.jsonl` (and `.stderr`)
(`dev/tool/suite_evidence.py:293`, `flutter_test_json` at 145), so parallel
worktrees overwrite each other's results; `TMPDIR` does not change it.
Before parallel execution starts, Claude either lands invocation-specific
output paths in `suite_evidence.py` on `refactor/codebase`, or such checks
are serialized through a shared lock. Execution does not start otherwise
and does not edit the tool itself.

## Goal

`lib/screens/playlist_content_view_screen.dart` is 4,140 lines: the screen
that opens a saved playlist item: content loading for six providers into
an `RDFileNode` tree; Raw and Sort (A–Z) browsing and the Series Arrange
("OTT") view; recursive search; progress badges and watched toggles; series
metadata (TVMaze, imdbId and poster saves, Fix Metadata); and playback
through seven `VideoPlayerLauncher.push` sites.

Split it into a new feature, `lib/features/playlist_content/`, **moving code
verbatim**. The widget tree, keys, focus nodes, build order and the State's
lifecycle are unchanged. The public `PlaylistContentViewScreen` and its State
(verbatim `initState` and `dispose`, a `build` forwarder, owners and wiring)
stay in `lib/screens/playlist_content_view_screen.dart` (the facade), so
`home_playlist_actions.dart:4` and `playlist_screen.dart` keep their imports.
There is no `didUpdateWidget`, and none is added.

**Nothing is merged.** `_extractSeasonNumber`, `_extractLeadingNumber`,
`_applySortedView`, `_SearchResult` and `_resolveWebDavConfig` resemble code
in `debrid_downloads`, `torbox_downloads`, `pikpak_files`,
`premiumize_files_screen.dart` and `lib/services/playlist_player_service.dart`.
They move into this feature as copies. No file under
`lib/features/playlist_content/` imports those three features (or the
reverse), and `playlist_player_service.dart` and all player/launcher code are
untouched. `FolderViewMode` stays in `lib/widgets/view_mode_dropdown.dart`.

**Architectural status:** a bounded legacy-extraction stage. Temporary
exceptions and exit milestones:
- **State-driven sections instead of Riverpod.** Exit: Riverpod notifiers.
- **A `legacy_playlist_content/` bridge calling services, storage and the
  launcher directly.** Exit: playlist-item data contracts (loading, view
  prefs, progress, metadata/poster writes, playback preparation).
- **Unchanged legacy text and `print`s.** Exit: the app-wide localization
  migration and a logging pass.
- **Duplicated helpers.** Exit: the future shared cloud-library plan
  (`docs/refactoring/cloud-library-shared-plan.md`, not yet written).
- **Raw maps and mutable models** (`widget.playlistItem`,
  `_fileProgressCache`, the live `SeriesPlaylist`) cross sections unchanged.
  Exit: typed playlist-item models behind the data contracts.

## Public surface

```dart
/// Screen for viewing contents of a playlist item
/// Supports Raw, Sort, and Series Arrange view modes
/// Handles folder navigation and progress tracking
class PlaylistContentViewScreen extends StatefulWidget {
  final Map<String, dynamic> playlistItem;
  final VoidCallback? onPlaybackStarted;
  const PlaylistContentViewScreen({super.key, required this.playlistItem,
    this.onPlaybackStarted});
}
```

Kept exactly (doc comment, field order, constructor). It is the only public
symbol. Callers: the Playlist tab (`playlist_screen.dart:238`, with
`onPlaybackStarted: () => Navigator.of(context).pop()` where `context` is the
`MaterialPageRoute` builder's) and Home (`home_playlist_actions.dart:136`, no
callback). No test constructs it today.

## What it contains (line numbers at `ec997117`; the step 0 manifest is authoritative)

| Lines | Area |
| --- | --- |
| 1–128 | 46 imports, the widget, 29 State fields (7 `final`; no `late`, statics, getters or mixins; 3 timers) |
| 130–220 | `initState`, `_initializeScreen`, `dispose`, `_checkIfAndroidTv`, `_handleBackNavigation` |
| 222–314 | saved view mode, enum converters, dormant `_loadProgressData` |
| 316–797 | `_loadContent` and six loaders, PikPak/Premiumize/WebDAV tree builders |
| 799–1124 | `_applyViewMode`, sorted and series views, `_applySortedPlaylistOrder`, folder navigation |
| 1126–1219 | `_playFile` |
| 1221–1526 | search logic and builders |
| 1528–1923 | `build` (49 lines), content and file cards, `_getProgressForFile`, `_buildOTTView` |
| 1925–2481 | initial season/episode, `_reloadProgress`, metadata saves, Fix Metadata, posters |
| 2483–3302 | season selector, episode list and scroll, episode cards (mobile, desktop), metadata row |
| 3304–3502 | `_toggleWatchedState`, `_playEpisode` |
| 3504–4131 | six per-provider play methods (seven launch sites), WebDAV config, `_cleanTorboxPath` |
| 4134–4140 | `_SearchResult` |

No member is over 200 lines (largest `_buildEpisodeCard`, 187).

## Contracts that must not change

1. **Lifecycle.** `initState` (130–139) stays verbatim with receiver-only
   qualification: `super.initState()`, `AnalyticsService.screenView
   ('playlist_content')`, unawaited `_checkIfAndroidTv()` and
   `_initializeScreen()`, then `MainPageBridge.pushRouteBackHandler
   (_handleBackNavigation)`; both async starts run before registration.
   `_initializeScreen` keeps its order: saved mode, `_loadContent`, then (if
   a root exists) `_parseSeriesPlaylist`, the **second** saved-mode read, the
   unguarded seriesArrange `setState` (160), `_applyViewMode`. `dispose`
   (173–191) keeps `popRouteBackHandler` first, then the **10 cleanup
   statements** in order (cancel `_scrollRetryTimer`,
   `_ottViewAutoSwitchTimer`, `_episodeLongPressTimer`; dispose the dropdown
   and back nodes, `_episodeListScrollController`, `_searchController`, the
   search, search-button and search-clear nodes), then `super.dispose()`.
2. **Back handling.** `popRouteBackHandler` removes only when
   `_pushedRouteStack.last == handler` (`main_page_bridge.dart:347–351`), so
   the push and pop tear off `_handleBackNavigation` from the **same
   receiver** (checker rule plus negatives). Priority: active search →
   `_toggleSearch()`, true; non-empty `_folderPath` → `_navigateUp()`, true;
   else false (falls through to the tab handler). The AppBar back calls
   `_navigateUp`, which pops the route at root with no `canPop` (1115).
3. **Provider dispatch.** Load (324–340): the provider (default
   `'realdebrid'`) is **lower-cased**; torbox → pikpak → webdav → premiumize
   → alldebrid → **else Real-Debrid**, so `'rd'`, `'torbox_webdl'`,
   `'real_debrid'` and unknown values load through RD. Play (1175–1191,
   3458–3474): lower-cased and matched **exactly** against six names with
   **no else**: those providers open but don't play (dialog shown, popped,
   progress reloaded, nothing launched).
4. **Loading per provider** keeps its exact requests: RD torrent info;
   AllDebrid `addMagnetAndResolveFiles` (**re-uploads the magnet on every
   open and refresh**); TorBox `getTorrentById` (`as int?`, its internal
   retry); PikPak sequential recursive `listFiles(limit: 100)` with the
   depth-over-4 throw and the cached flat fallback; Premiumize
   `resolveFilesByHash` or the cloud tree with no network; WebDAV with no
   network. `_loadContent`'s unguarded `setState`s (318, 346) stay.
5. **View modes.** When a root exists (it returns immediately otherwise,
   801), `_applyViewMode` persists on **every** call (unawaited
   `savePlaylistItemViewMode`, 852), including folder navigation and the
   auto-switch; seriesArrange closes search; a missing folder resets to root;
   Raw assigns `currentFolder.children` itself (840, aliasing);
   `_applySortedPlaylistOrder` reorders its argument in place only in
   sortedAZ, with the TorBox second-segment path.
6. **Playback handoff, all seven sites** (RD 3595, AllDebrid 3667, TorBox
   3769, PikPak 3874, Premiumize cloud 3940, Premiumize hash 4001, WebDAV
   4084). Each keeps `if (!mounted) return;` → `widget.onPlaybackStarted
   ?.call()` → `MainPageBridge.notifyPlayerLaunching()` → `await
   VideoPlayerLauncher.push(context, …)`, and its exact arguments:
   - common: `videoUrl` (`initialVideoUrl` = `entries[startIndex].url` at
     3583/3657/3757/3862/3990; inline `cloudEntries[startIndex].url` and
     `entries[startIndex].url` at the cloud and WebDAV sites), `title`
     (`_seriesPlaylist?.seriesTitle ?? item['title'] ?? 'Series'`),
     `subtitle: '${n} episodes'`, `playlist`, `startIndex`,
     `disableAutoResume: true`, `viewMode: _convertToPlaylistViewMode(...)`,
     `contentImdbId` and `contentType` from the in-memory item,
     `suppressTraktAutoSync: true`;
   - extras: RD `rdTorrentId`; TorBox `torboxTorrentId.toString()`; PikPak
     `pikpakCollectionId: item['pikpakFileId']`; WebDAV `httpHeaders:
     WebDavService.authHeaders(config)`, `disableExternalPlayer:
     _hasWebDavCredentials(config)`, `webDavServerId`, `webDavBaseUrl`,
     `webDavPath` with their item-or-config fallbacks;
   - never passed: `onPlayerHandoff`, `sourceOwner`, `canContinue`,
     `retainSourceSession`;
   - all 14 `PlaylistEntry(...)` constructions: the parse-only one in
     `_parseSeriesPlaylist` (2164, `url: ''`) and the 13 provider-playback
     ones (RD 3539/3551/3565, AllDebrid 3641, TorBox 3714/3727/3740, PikPak
     3823/3834/3846, Premiumize 3922/3972, WebDAV 4033) with their `provider`
     strings and ids; only the start entry is resolved except Premiumize hash
     (all entries) and WebDAV (direct URLs);
   - start index: `_playFile` matches name and path; `_playEpisode` matches
     filename in sortedAZ, else `originalIndex` in range, else filename.
     RD, AllDebrid, TorBox and PikPak don't clamp. Premiumize cloud clamps
     against **`videoFiles` before filtering** (3908; null-`path` nodes are
     then skipped, so `cloudEntries[startIndex]` can be the wrong entry or
     throw); Premiumize hash (3988) and WebDAV (4046) clamp against the
     **built entries**.
7. **Preparing dialog and the return from the player.** `showDialog
   (barrierDismissible: false)` (root navigator) before resolving; popped
   through the State's `Navigator.of(context)` on an empty list, after the
   launcher returns (`mounted && canPop`), and in the catch. With the
   Playlist-tab callback the dialog is popped **before** the push, so the
   post-return pop removes **the content screen** (back to the Playlist tab,
   which then refreshes); with Home (no callback) the dialog stays under the
   player and the post-return pop removes **the dialog** (the user stays on
   the content screen). A throw after the callback pops the screen.
   `_reloadProgress` follows in both paths. "After the launcher returns"
   differs by launch kind: the in-app player returns when its route pops
   (`launch_router.dart`, the awaited `Navigator.push`), while a native
   Android TV, external or DeoVR launch returns **immediately** after
   handing off, so the same post-return pop and reload run while the
   external player is still playing.
8. **Watched toggles** (3304–3388): no confirmation; title from the series
   or item; season and episode default 1; imdbId from the series, then the
   item; `isEpisodeFinished` then `unmark…` or `mark…AsFinished` (local only,
   no trackers); `_reloadProgress`; the inverted snackbar text and colours;
   the error snackbar. Triggers: the episode card's watched button
   (`GestureDetector.onTap`, mobile 2981 and desktop 3148, **not TV-gated**:
   it toggles on TV too); the outer card `InkWell.onLongPress` (null on TV);
   the D-pad hold. The outer `InkWell.onTap` **plays** the episode (null on
   TV, 2786).
9. **Series metadata and Fix Metadata.** Fix Metadata (2261–2350) keeps its
   exact order: `TVMazeSearchDialog` (`barrierDismissible: false`); read the
   old mapping; if the old id differs, `TVMazeService.clearShowCache` then
   `EpisodeInfoService.clearShowCache`; `EpisodeInfoService.clearSeriesCache`
   (which itself calls `TVMazeService.clearSeriesCache`,
   `episode_info_service.dart:180`); `TVMazeService.clearSeriesCache` again
   (so **two** TVMaze series clears per fix); `saveTVMazeSeriesMapping(playlistItem:,
   tvmazeShowId:, showName:)`; `_updatePlaylistPoster` (override plus the
   per-provider artwork or TorBox raw-list write; no WebDAV, `'rd'` or
   `'torbox_webdl'` branch); the snackbar; null `tvmazeShowId`,
   `tvmazeShowName`, `showPosterUrl` on the live model; `fetchEpisodeInfo`
   then `.then` `_saveImdbIdToPlaylist(force: true)` and the detected-poster
   save. The unforced imdbId save skips existing or non-`tt` ids. The
   `.then` writes run after unmount, unguarded.
10. **Timers and build-time side effects**, verbatim: `_buildOTTView` starts
    `_parseSeriesPlaylist()` when null; for a non-series it **cancels and
    recreates** the 2 s `_ottViewAutoSwitchTimer` on every build, whose
    callback runs `_applyViewMode` **inside** `setState` (nested); a
    post-frame unguarded `setState` for a missing season (1902–1906);
    `_buildEpisodeList` writes `_targetEpisodeIndex`/`_isScrollScheduled`
    and schedules `_scrollToEpisode` (retries at 100/200/300 ms via
    `_scrollRetryTimer`, 800 ms `easeInOut`, 116/124 px estimates); the five
    per-card `print`s; per-card full sorts in `_getProgressForFile`.
11. **Search:** recursive, video-only, case-insensitive, `' / '` paths;
    `_searchResults` reassigned and `.clear()`ed; hidden in seriesArrange.
12. **D-pad and focus:** the five node debug labels; dropdown default
    `autofocus: true`; the search field's `TvTextField` arrows (never
    `node.onKeyEvent`); the clear button's KeyDown handler; file cards'
    select/enter/space; episode cards (KeyDown starts the 800 ms timer,
    KeyRepeat ignored, KeyUp plays when no long press and > 300 ms since the
    last; blur cancels). The key handler and the watched-button taps aren't
    TV-gated; on TV only the outer card InkWell `onTap` (play) and
    `onLongPress` (toggle) become null and the hold hint shows.
13. **Profile behaviour.** The screen captures no scope. Storage does,
    partly: `ProfilePreferences.instance()` (`profile_preferences.dart:271`)
    captures the committed scope at acquisition and rejects later reads and
    writes through that instance once the profile changes; an operation that
    *starts* after the handoff acquires the new profile. The playlist
    read-modify-writes (detected poster 2365–2372, TorBox raw list
    2424–2431) read through one instance and `savePlaylistItemsRaw`
    reacquires preferences to save, so a switch between read and save can
    write the old profile's list into the new one; the save also records
    deletion tombstones for **previous keys absent from the replacement list**
    (`playlist_storage.dart:43`), so saving stale profile-A data into
    profile B tombstones B's displaced entries (fixtures use disjoint
    profile lists to show it). The route sits above `ProfileGate` and is
    disposed by the picker's `popUntil`. These outcomes are characterized
    and preserved; no scoping or protection is added or removed.
14. **Collection identity and mutable models:** Raw aliasing; `_folderPath`
    mutated in place; the WebDAV builder mutating `children`; in-place
    `SeriesPlaylist` updates; `widget.playlistItem` never refreshed.
15. **Diagnostics.** All 17 analyzer warnings (step 0 item 7) keep firing
    at their destinations, verified by rule and enclosing member; none may
    disappear. The 39 `print`s and their text stay.
16. **Progress lookup and initial selection.** `_getProgressForFile`
    (1802–1839): a parsed `S_E` key returns only when non-null; otherwise,
    with a root, the sequential `0_{index+1}` key (index in the
    sortedAZ-reordered video list) is returned **immediately even when
    null** (1831); the filename key is tried only when the file isn't found
    or there is no root. Completion: `progress >= 0.9` or under 120,000 ms
    left (1423, 1646, 2686), plus the manual marker `positionMs == 0 &&
    durationMs == 1` on episode cards. `_determineInitialSeason` /
    `_determineInitialEpisodeIndex` pick the latest `updatedAt`: an `int` is
    taken as ms; a numeric string below 10^10 is seconds (×1000), else ms;
    other strings parse as ISO; ties keep the first seen. The initial season
    (2203) and the scheduled scroll follow from that.

## Destination layout

`lib/features/playlist_content/` (each file at most 500 lines):
- **`application/`:** pure helpers, if the report confirms them:
  `_buildPikPakFileTree`, `_buildPremiumizeCloudFileTree`,
  `_buildPremiumizeFileTree`, `_buildWebDavFileTree`, `_relativeWebDavPath`,
  `_fileNameFromPath`, `_asStringDynamicMap`, `_asInt` (tree builders);
  `_applySortedView`, `_extractSeasonNumber`, `_extractLeadingNumber` (sort
  policy); `_formatAirDate`, `_cleanTorboxPath`, `_hasWebDavCredentials`.
  Not here: the enum converters (they name `FolderViewMode` from
  `lib/widgets/`) and anything naming `PlaylistEntry` (re-exported through
  `lib/screens/video_player/`); no import URI changes to make them fit.
- **`models/`:** `_SearchResult` as `PlaylistContentSearchResult`.
- **`presentation/legacy_playlist_content/`** (exact path in the guard):
  owners; loading (six loaders, PikPak recursion); view modes, navigation,
  back and converters; search; progress and watched toggle; series metadata
  and Fix Metadata; play entries (`_playFile`, `_playEpisode`); debrid
  launches (RD, AllDebrid, TorBox); cloud launches (PikPak, Premiumize,
  WebDAV, `_resolveWebDavConfig`); file list; OTT view, season selector and
  episode list; episode card; mobile and desktop episode layouts; the
  dormant `_loadProgressData`; composition; root layout.
- File names use the `playlist_content_` prefix; checker files are
  `playlist_content_manifest.tsv` and `playlist_content_checker_config.json`.
- **The facade** is an exact composition root (400-line cap and
  `TEMP(playlist_content)` rejection from step 7); it keeps the widget, the
  State's lifecycle, the `build` forwarder, owners, wiring (including the
  typed `playlistItem`/`onPlaybackStarted` getters) and the accessor; no
  file under `lib/features/playlist_content/` names
  `PlaylistContentViewScreen`.
- **Guard rules** (step 1, `check_search_architecture.py`):
  `playlist_content` in `FEATURES`; `PLAYLIST_CONTENT_FACADE/BRIDGE/
  COMPLETE`; the bridge in `LEGACY_PLAYBACK_BRIDGES` (still no `http`,
  `shared_preferences`, `sqflite`); no service or UI imports in
  `application/`; no back-import of the facade; **bidirectional bans**
  between `playlist_content` and `debrid_downloads`, `torbox_downloads`,
  `pikpak_files`; no import of `lib/services/playlist_player_service.dart`
  from the feature; 500-line destination caps.

## Technique

As in the PikPak plan, with these points:
1. **The concrete widget type stays in the facade; sections get live typed
   getters.** No section names `PlaylistContentViewScreen` (that would
   back-import the facade). The facade wiring injects `Map<String, dynamic>
   Function() playlistItem` (`() => widget.playlistItem`, non-nullable,
   returning the same map object, never a copy) and `VoidCallback?
   Function() onPlaybackStarted` (`() => widget.onPlaybackStarted`), read
   at each use. The 11 `invalid_null_aware_operator`, the
   `unnecessary_null_comparison` at 2212 and the `!` at 2214 fire only
   because the item is non-nullable; a nullable or `dynamic` getter would
   silently drop or change them. The checker config registers the
   normalization `widget.playlistItem` ↔ `playlistItem()` and
   `widget.onPlaybackStarted` ↔ `onPlaybackStarted()` (with negatives for a
   nullable return type, a copied map and a cached value), and every step
   verifies all 17 occurrences by rule and enclosing member.
2. **Private dormant and warned members stay private** in the section that
   owns them: `_loadProgressData` moves privately into the dormant section,
   keeping `unused_element` with its exact message. No warned member becomes
   public and no warning may disappear (the PikPak `_email` escape does not
   apply here); a placement that would drop one is redesigned.
3. **Callback identity** (receiver path plus member, wrapper and same-class
   receiver-swap negatives) for `_handleBackNavigation` (push and pop), and
   tear-off form for `_navigateUp`, `_toggleSearch`, `_loadContent` (Refresh,
   Retry), `_applyViewMode` (`onModeChanged`), `_performSearch`
   (`onChanged`), `_showFixMetadataDialog`.
4. **Timers stay with their owners.** The three `Timer?` fields live on one
   owner each; the callbacks that create them move with their builders and
   keep reading the live `mounted`; `dispose` cancels them through the same
   owner.
5. **Build-side effects move verbatim** inside their builders; nothing is
   hoisted into `initState`, a listener or `didChangeDependencies`. No new
   `const`; import reordering is the only allowed edit beyond receivers.

## Steps

| # | Work | Notes |
| --- | --- | --- |
| 0 | Baseline, deps report, manifest and checker config, accessor, characterization tests and baselines, source-text inventory, CI list, Linux capture script | Nothing moves. |
| 1 | Guard registration; search-result model; pure application helpers | |
| 2 | State and resource owners (29 fields); lifecycle verbatim | Contract 1. |
| 3 | Loading and dispatch, view modes, navigation, back handler, saved mode, `_initializeScreen` | Contracts 2–5, 14. **Full-suite gate 1.** |
| 4 | Search, progress, watched toggle, series metadata, Fix Metadata, posters, dormant code | Contracts 8, 9, 11, 13, 16. |
| 5 | `_playFile`, `_playEpisode`, all seven launch sites | Contracts 3, 6, 7. |
| 6 | `build` forwarder, file list, OTT view, episode list and cards | Contracts 10, 12. Linux originals are a blocking prerequisite. |
| 7 | Final State, composition, guards, CI. **Full-suite gate 2.** | |

### Step 0

1. **Baseline:** `suite_evidence.py run playlist_content/base` and the
   whole-repo analyzer with tree provenance; Flutter 3.44.8. The original
   file is also analyzed under `lib/features/analysis_options.yaml` in the
   detached original worktree (relative-import qualification only) so
   destination-only infos (12 `directives_ordering`, 0
   `prefer_const_constructors`) are traced.
2. **Dependency report** (`docs/refactoring/playlist-content-deps.md`):
   every leaf and field with its destination, plus the per-entry wiring
   checklist (owner, live getters for `widget`/`context`/`mounted`, tear-off
   identity, timer owner, which warned member it carries). Review each entry
   against the actual binding before pinning any scaffold.
3. **Checker:** manifest and config as in the PikPak plan, fixtures built
   from the real config, with negatives for: `_handleBackNavigation` pushed
   and popped from different receivers or wrapped in a closure; a moved or
   reordered dispose statement; a timer cancelled through a different owner;
   a dropped `onPlaybackStarted` or `notifyPlayerLaunching` before a push;
   lifecycle moved out of the State.
4. **Accessor** (the approved seam; no clock or launcher seam, and the only
   TV seam is the setter below): a frozen `@visibleForTesting
   playlistContentTestAccess(State)` in the facade returning fresh snapshots
   (tree, view nodes, folder path, view mode, series playlist, progress
   cache, search state, the three timers, `_targetEpisodeIndex`,
   `_isScrollScheduled`, flags), the live `_episodeListScrollController`,
   and real tear-offs (loaders, `_applyViewMode`,
   `_applySortedPlaylistOrder`, `_playFile`, `_playEpisode`, the six play
   methods, `_toggleWatchedState`, `_showFixMetadataDialog`,
   `_saveImdbIdToPlaylist`, `_handleBackNavigation`, `_getProgressForFile`,
   `_determineInitialSeason`, `_determineInitialEpisodeIndex`,
   `_reloadProgress`, `_scrollToEpisode` for unattached-controller retry
   tests), and one TV setter that assigns `_isAndroidTv` and calls
   `(state.context as Element).markNeedsBuild()`, used only after the async
   `_checkIfAndroidTv` has settled (false on the host). The list is complete
   before freezing; the seam-only facade size raise is recorded and exits
   at step 1.
5. **Harness** (`test/support/playlist_content_fixture.dart`): the PikPak
   fixture's profile setup (`SharedPreferences` mocks, `ProfileRuntime`
   reset and `initializeLegacy`, `SecretVault.debugReset`), seeded API keys
   and WebDAV servers, `http.runWithClient` with a `MockClient` per provider
   host and `api.tvmaze.com` (resolve each base URL from the services; JSON
   bodies), sqflite ffi only if the first fixture proves it necessary.
   **Metadata isolation:** before recording requests, prepare the
   process-wide TVMaze caches and availability and the `EpisodeInfoService`
   state through their existing APIs, and cancel or drain their timers in
   teardown, so one case can't suppress another's requests. Items
   carry no `poster`. Launch fixtures omit `imdbId`/`contentType` unless a
   case needs them (the launcher writes continue-watching and seeds trackers
   for catalog ids). **Launch probe (rejection path only):** the
   `video_player_launcher_settings_rejection_test.dart` recipe, adapted: a
   player-launch listener that passes the screen's own
   `notifyPlayerLaunching()` and throws `NativePlayerSettingsUnavailable` on
   the launcher's (second) call at `launch_router.dart:466`. That throw
   skips the playlist trace (468–478) and every launch branch; the catch
   (94–103) emits `notifyContentPlaybackStopped`, shows the settings-error
   snackbar and returns normally. The probe therefore proves only the
   rejection path: the screen's HTTP requests, `onPlaybackStarted` once
   before the launcher's notify, the playback-stopped signal and snackbar,
   and the screen's post-return dialog/route pops and reload **on
   rejection**. It proves no playlist contents and no successful-launch
   cleanup. **Successful launch:** step 0 may prove, on the original code,
   a fixture where the real launcher pushes the in-app player route and a
   `NavigatorObserver` pops it as soon as it is pushed (the trace captured
   via `debugPrint`, the pushed route's args read before the pop); if that
   fixture is not proven on the original code, the playlist trace, launch
   arguments and successful caller cleanup stay **pending device
   verification**. Native TV, external and DeoVR completion (return
   immediately) are pending device verification either way. Prove one HTTP
   fixture and the probe on the original code first.
6. **Characterization tests,** recorded against the original code, with
   the earlier lessons up front: drive real entry points; re-read state
   after acting; non-monotonic ids and file orders that differ from
   alphabetical; exact request lists; held responses for in-flight cases;
   fake-time tests mounted outside `runAsync` with IO inside it; an explicit
   scheduled frame after post-frame callbacks; route animations drained
   before asserting pops; January UTC dates; braces in test code (no
   test-style analyzer additions); every focused-run path verified to exist.

   | Contract | Coverage |
   | --- | --- |
   | 1 Lifecycle | Source guards on verbatim `initState`, `_initializeScreen` and the full dispose sequence; async starts before registration; unmount during a held load (record the unguarded `setState` outcome); timers cancelled on dispose (fake time: no callback after unmount). |
   | 2 Back | Sentinel route handlers below and above: push/pop identity (the sentinel stays intact after dispose); search close → folder up → false and fall-through to the tab sentinel; AppBar back in a folder and at root (route popped). |
   | 3 Dispatch | Load: each canonical provider and `'RD'`-cased variants; `'rd'`, `'torbox_webdl'`, `'real_debrid'`, unknown → the RD request. Play: those four open, show and pop the dialog, reload progress, launch nothing (probe listener never called). |
   | 4 Loading | Exact request lists: RD info; AllDebrid upload then files, **again on Refresh**; TorBox retry; PikPak recursion order, `limit=100`, depth-over-4 error, cached fallback; Premiumize hash and cloud (no request); WebDAV single, list and path fallback, empty error. Refresh and Retry call `_loadContent` alone (no reparse or reapply). |
   | 5 View modes | Saved mode read twice; auto seriesArrange only with nothing saved; persistence on every apply including navigation; Raw result identical to `children`; sorted order; missing folder resets; seriesArrange closes search. |
   | 6 Playback | Per site through the probe (rejection path): the HTTP log (start entry resolved only, Premiumize hash all, AllDebrid unlock errors swallowed), `onPlaybackStarted` once before the launcher's notify, the playback-stopped signal and settings snackbar. Start index through the accessor: sorted vs raw, `originalIndex` fallback, the Premiumize cloud clamp against pre-filter `videoFiles` (with a null-`path` node before the start) vs the hash and WebDAV clamps against built entries. Playlist contents (count, titles, relative paths incl. `_cleanTorboxPath` and the PikPak fallback) only through the successful-launch fixture if proven, else **pending device verification**. **Source guards** on the seven complete call expressions, the guard→callback→notify→push sequence, and all 14 `PlaylistEntry` constructions; remaining argument values (ids, flags, `viewMode`, WebDAV headers and fields) are **pending device verification**. |
   | 7 Return | With a `NavigatorObserver`, the screen pushed with each caller's construction reproduced verbatim (source guards pin both caller expressions). **Rejection path (probe):** Playlist-tab form → dialog popped before the launch, content route popped after the launcher returns; Home form → dialog popped after return, content screen still mounted. **In-app success:** the same two observations only through the proven observer-controlled fixture, else pending device verification. Native/external completion (immediate return): pending device verification. Plus the empty-list and catch paths. |
   | 8 Watched | Mark and unmark arguments (defaults and imdbId preference; title fallback to the item is source-guard-only), the persisted completion, reload, snackbar text and colour, error snackbar; via the watched button (mobile and desktop widths, **TV false and TV true**: toggles both ways), the outer long-press (non-TV), D-pad hold; the outer card tap plays (non-TV) and is inert on TV. |
   | 9 Metadata | Fix Metadata with a fake dialog result: the cache-clear calls' order and counts (conditional pair; two TVMaze series clears, one transitive through `EpisodeInfoService.clearSeriesCache`) are pinned by **source guards**, since an HTTP mock can't spy on static calls; their effect is verified behaviourally through the resulting cache misses and requests; mapping, poster override and per-provider artwork or TorBox list write, forced imdbId, nulled fields, loading flag; cancel does nothing. Unforced imdbId save rules; detected-poster write; writes landing after unmount (recorded). |
   | 10 Timers/build | Fake time: auto-switch to A–Z at 2 s with persistence, timer object replaced per rebuild; missing-season post-frame `setState`; scroll retries and the 800 ms animation; `print` capture shows the per-card lines. |
   | 11 Search | Recursive video-only matches, paths, clear and close, hidden in seriesArrange. |
   | 12 D-pad | Clear-button keys, search-field arrows, file-card select/enter/space, episode KeyDown/hold 800 ms/repeat ignored/short press/300 ms suppression (host keys); via the TV setter (after the TV check settles): null outer `onTap`/`onLongPress`, the watched button still live, and the hold hint. |
   | 13 Profile | A profile switch through the gate's picker disposes the route (handler gone, timers cancelled); two routes on the same item share no owners. Separately, with held futures and asserting persisted data **and tombstones** in both profiles (including writes the captured instance rejects): (a) a late operation (`.then` imdbId/poster save, watched toggle) that starts after the handoff; the Fix Metadata mapping-write variant is source-guard-only; (b) a switch between `getPlaylistItemsRaw` and `savePlaylistItemsRaw` in the poster and TorBox list writes; (c) a switch after a `ProfilePreferences` instance was acquired. Outcomes are recorded and preserved; no protection is added. |
   | 14 Identity | Through the accessor: Raw aliasing, `_folderPath` identity, `_searchResults` reassign-then-clear, `_applySortedPlaylistOrder` mutating its argument. |
   | 16 Progress | Through the real tear-offs: `S_E` key hit; sequential key returned even when null (filename key then not consulted) vs filename fallback when the file is absent or there is no root; sortedAZ index; completion at 0.89/0.90 progress and 120,000/119,999 ms remaining, the manual `0/1` marker (independent predicate source-guard-only because remaining time also accepts it); `updatedAt` as int ms, numeric seconds string, ms string, ISO string, unparsable, and ties; initial season and episode index; the scheduled scroll and its 100/200/300 ms retries through `_scrollToEpisode` with an unattached controller, then the 800 ms animation once attached. |

   Pixel goldens (raw list, search, OTT mobile and desktop, error) on macOS
   and Linux, Linux captured by Claude from the original code. Record
   `base2` after the accessor and `base3` after the tests; compare each.
   Then a step-0b review closes with ORIGINAL-only mutation negatives
   (e.g. a play dispatch with an else, persistence skipped on navigation,
   swapped dispose statements, a non-recreated auto-switch timer, the
   Playlist-tab callback removed) each rejected.
7. **Source-text inventory:**
   - **Analyzer allowlist:** the 17 warnings — `unused_element`
     (`_loadProgressData`, 274), `dead_null_aware_expression` (440, 3526),
     `unnecessary_null_comparison` (832, 2212), `invalid_null_aware_operator`
     ×11 (2114–2132, 2232, 2329), `unnecessary_non_null_assertion` (2214).
     Adding the facade to the CI analyze list in step 0 needs five entries
     at the facade path. Each moving commit relocates entries in the same
     commit; a facade entry leaves only when its last occurrence leaves.
     The checker matches sets, not counts, so the per-symbol relocation
     comparison must also show all 17 occurrences, by rule and enclosing
     member, at every step.
   - **Shape:** 0 bare radii and **11 token calls** (1308, 1357, 1493, 1740,
     2540, 2545, 2777, 2820, 2873, 3033, 3224). The floor is **488 with zero
     slack** (measured: 125 `kShapeResidue` files hold exactly 488), so
     every destination receiving a token call goes in `kShapeResidue`
     (residue 0) and every other destination in `kExtractedShapeResidue`;
     the facade leaves `kShapeResidue` when its last call leaves (step 6).
     Parallel refactors also move tokens; a re-sum alone is not enough at
     integration (see "Per step and gates").
   - **Theme:** `theme_surface_manifest.txt:21` (`p2_playlist`) gains
     explicit per-directory patterns (`ls $@` without `globstar` treats `**`
     as one level); `source_guard_test.dart:188` keeps its frozen prefix
     (harmless).
   - **Not extended:** the `print(` redaction scan
     (`profile_source_guard_test.dart:326`) covers `lib/services`,
     `lib/widgets/remote`, `lib/screens/settings` only; no code moves there.
   - `file_size_baseline.txt:16` (ratchet down; remove at ≤ 800),
     `check_search_architecture.py`, `checks.yml` format and analyze lists
     (facade, `test/support/playlist_content_*`), `ci_behavior_tests.txt`,
     `light_ink_inventory.py` (verify), docs naming the path
     (`CODEMAP.md:47`, `ADDING_A_PROVIDER.md`) updated at step 7.
   - Shared registry files are edited in small separate blocks so Claude's
     merge with parallel plans stays mechanical.
8. **CI list:** every new test as a concrete path.
9. **Linux capture script** (`dev/tool/capture_playlist_content_linux_goldens.sh`)
   resolving the step-0 checkpoint by its exact subject
   (`test(playlist-content): step 0 original-code characterization
   checkpoint`), run by Claude in the calibrated local Docker image; the
   Linux test stays non-strict through step 5. **Handoff:** like the PikPak
   script, it searches the *invoking* `HEAD`'s ancestry and copies PNGs into
   the *invoking* repo root, and a linked worktree's absolute `gitdir` is
   not reachable inside Docker. So execution reports the exact checkpoint
   hash and leaves it on a reachable ref (the execution branch); Claude
   clones that branch into a `$HOME` path (mounted by colima), checks out
   the checkpoint hash there, verifies `HEAD` equals it, runs the script
   inside the container from that clone, and copies the produced PNGs
   (with the evidence files) explicitly into the feature worktree's
   `test/goldens/playlist_content/linux/`, where execution reviews and
   commits them.

### Per step and gates

As in the PikPak plan, with `--relocate
lib/screens/playlist_content_view_screen.dart=lib/features/playlist_content/`,
every existing manifest run (settings, IPTV results, TorBox, Real-Debrid,
PikPak, and IPTV settings once integrated) plus this one with self-tests (an
isolated parser cache when run concurrently), the allowlist and per-symbol
warning comparison, the shape floor, LF-only manifests and staged diff
checks before each commit, and gates on committed trees against the latest
playlist-content base. Never `--record` to accept a regression.

**Integration.** After Claude merges with parallel plans, the checks run on
the **merged committed tree**, not per branch: the architecture guard (all
registered features), the analyzer allowlist (no stale or missing entry,
per-symbol comparison), every manifest run with self-tests, the CI format,
analyze and behaviour-test lists, `file_size_baseline.txt` ratchet and the
shape floor (`kShapeResidue`/`kExtractedShapeResidue` membership and the
total), plus the affected tests, and a **full-suite run on the merged
committed tree** (AGENTS.md: cross-feature integration gate), reconciling test
identities against the observed branch baselines and approved additions.

## Definition of done

1. The facade is at most 400 lines, formatted, holding the public widget
   and the State with verbatim lifecycle, forwarder, owners, wiring and the
   frozen accessor. Both callers compile unchanged.
2. The guard registers the feature, the exact bridge, the facade cap and
   `TEMP(playlist_content)` rejection, and the import bans (cloud features
   both ways, `playlist_player_service.dart`, facade back-import).
3. All manifest runs pass with self-tests; every characterization test
   passes unchanged; all seven launch-site guards are byte-identical.
4. No new diagnostics or suppressions; all 17 warnings still fire, each
   allowlisted at its destination with no stale entry; gate 2 passes against
   the latest base and gate 1.
5. Local CI-equivalent checks pass; remote CI is pending until Claude
   pushes. The test list holds the new tests; the failure allowlist gains
   nothing.
6. Progress records the commits, ownership, exceptions with exit
   milestones, the seam, and pending device verification (seven real
   launches per provider with both callers, including the playlist trace
   and successful-return cleanup unless the observer fixture proved them,
   and native TV/external completion; Android TV D-pad hold and hint;
   real provider accounts; the Linux run of moved code).
7. Stop after gate 2 and report.

## Explicitly not in scope

- Merging anything with the cloud features, `premiumize_files_screen.dart`
  or `playlist_player_service.dart`.
- The player, launcher and `player_launch`; services, storage,
  `SeriesPlaylist`, `TVMazeSearchDialog`, `ViewModeDropdown`; the callers.
- Bug fixes and behaviour changes, including everything below.

## Progress

- Execution is confined to the dedicated `refactor/playlist-content` worktree
  at `67b32702`; no branch switch or push. `flutter pub get` completed first
  with Flutter 3.44.8 / Dart 3.12.2 and no dependency changes. The
  invocation-specific suite checker prerequisite is present at `4f3ee3b3`.
- Step 0: the original 4,140-line implementation is byte-identical, followed
  by the frozen 99-line accessor (4,239-line temporary seam-only ratchet;
  exits step 1). The 107-leaf manifest, dependency/wiring checklist,
  real-config checker fixtures, named-argument callback checks and negative
  wrappers/receiver swaps are installed. No implementation has moved.
- Observed baselines: `playlist_content/base` and accessor-only `base2`
  both have 10,577 successes, 13 failures, 28 errors and 20 skips; identity
  comparison passes with no missing/new failures or changed skips. Whole
  analyzer evidence is `base-analyze.txt` with tree/SDK provenance; the
  first pub-enabled attempt hit concurrent Flutter iOS package housekeeping,
  so the authoritative comparison uses `flutter analyze --no-pub`.
  Existing vendor test-package errors are retained, not accepted as new.
- Original characterization: `playlist_content/characterization-original`
  passes all 151 identities before extraction. Every test uses the unchanged
  original plus frozen accessor; the original-code proof runs here, not in a
  second worktree, to obey the user's worktree confinement. After the
  checkpoint, a clean-tree original replay will pin the checkpoint and
  complete fixture/tests. `base3` is the full original-plus-tests baseline: 10,728 successes,
  the same 13 failures / 28 errors / 20 skips; comparison to base/base2
  passes, with exactly the 151 approved characterization additions.
- The strict-lint original proof is inside this worktree's ignored
  `.dart_tool/playlist_content_original_strict/`, with relative imports
  qualified only. It records 12 `directives_ordering` infos and zero
  `prefer_const_constructors`. Original warnings are pinned by rule,
  member and message in `playlist_content_original_warnings.json`.
  **Plan arithmetic correction:** the listed warning groups total 17, and
  both original analyzer runs observe exactly 17 (1 unused + 2 dead-null +
  2 null comparisons + 11 invalid-null-aware + 1 non-null assertion).
  Preserve every observed occurrence; do not invent an eighteenth warning.
- Metadata fixtures isolate TVMaze and EpisodeInfo caches, drain owned
  timers, and use deterministic bundled fonts/artwork. Fake-time fixtures
  advance frames while real IO runs through `runAsync`. The D-pad's 300 ms
  check uses `DateTime.now`, so its fixture also advances real wall time.
  Raw mode is mounted before completed-metadata mobile goldens to avoid
  masking the original missing-thumbnail overflow. Original macOS captures
  and strict comparisons cover raw, search, OTT mobile/desktop and error.
- Profile evidence uses real file-backed tombstones reopened after writes,
  disjoint A/B lists, and held decode continuations through Dart's existing
  Zone boundary (no production hook). It preserves A-read/B-save data
  replacement and displaced B tombstones for both detected-poster and
  TorBox writes, stale captured-instance rejection, late metadata after
  unmount/handoff, watched actions, and the real gate picker disposing the
  route/timer/back handler. Ordinary IMDb progress remains title-keyed in
  the current storage; the title/identity mismatch test uses a custom-series
  identity, which is the current exact-key branch.
- The launch probe proves rejection only at all seven sites and both caller
  forms. No successful launcher fixture is claimed. Successful in-app
  cleanup/playlist arguments, native TV, external/DeoVR completion, real
  provider accounts and Android TV physical remote behavior remain device
  checks. Remote CI and merged-tree integration remain pending.
- Step 0 checks: all six configured manifests pass with self-tests using
  the isolated playlist-content parser (107 / settings 316 / IPTV 384 /
  TorBox 195 / Real-Debrid 173 / PikPak 128 leaves). Whole analyzer matches the original exactly;
  scoped allowlist, per-member warnings, clean test analyzer, format,
  architecture, size ratchet, storage keys/references, shape/source guards,
  the new playlist-content manifest is LF-only and staged diff checks pass.
  The pre-existing TorBox manifest uses CRLF; it remains untouched. Evidence is under
  `playlist_content/`; no known-failure list changed.
- Linux handoff script resolves the exact step-0 subject and uses only its
  checkpoint-owned tests. Linux absence is permitted through step 5 only;
  verified PNG hashes/provenance and a separate golden commit are required
  before any builder moves in step 6.

- Step 0b review closure (before any extraction): navigation persistence now
  overwrites storage with `raw` before both sorted navigation directions.
  Installed probes make the cloud-clamp and non-TV long-press assertions
  observable. The cloud clamp reaches callback + screen notify before its
  `RangeError`, without reaching launcher notify; this original behavior stays.
  The late-metadata profile case checks show id/name and exact request count.
  The formerly duplicate int/String timestamp tests have distinct typed names;
  the other timestamp identities remain unchanged. New cases tap the outer
  episode card and dispatch all six uppercase canonical provider names.
- Coverage limits recorded by the review: manual `0/1` is **source-guard-only**
  as an independent predicate (the remaining-time rule also accepts it).
  Completion boundaries exercise only the episode-card copy (original 2686);
  the search badge (1423) and file card (1646) copies rely on the verbatim checker.
  Same-show-id Fix Metadata cache non-clearing, the 116 px mobile scroll estimate,
  watched title fallback to the item, and profile scenario (a)'s Fix Metadata
  mapping write starting after handoff are **source-guard-only**; no behavioral
  characterization of those four branches is claimed. Their original method
  bodies/calls remain guarded. The direct ProfilePreferences stale-instance
  test is infrastructure coverage; screen scenario (c) is the interactions
  test's stale acquisition case, not that direct preferences test.
- TV overrides await the real async check before platform changes; false-to-false
  setters in timer replacement and completion rendering are explicitly rebuild
  triggers. The golden scenes/helpers/shared fixture are unchanged. ProfileFixture
  moved unchanged from the PikPak test into `test/support/profile_fixture.dart`;
  both its consumers are included in the original replay.
- The main checker now invokes live binding validation for dependency records,
  including nullable, uncached `onPlaybackStarted`; original service calls still
  receive the map. Exact dependency-record callback aliases get a rule-level
  positive and same-instance negative. Shared interpolation resolver commit
  `def4e304` was cherry-picked as `456a442c` with the required Codex trailer.
- The user's review explicitly authorizes a separate detached proof worktree at
  `6e23a3c5`, inside this worktree's ignored `.dart_tool/playlist_content_original_proof`.
  It supersedes the earlier same-worktree proof choice for the review cases.

- Step 0b evidence: `step0b-original-proof-final` and `step0b-current` each
  pass 163 identities (159 playlist + four affected PikPak profile cases).
  The final awaited-long-press change is replayed separately on both inputs.
  Six original-only behavioral mutants are rejected without invoking the checker;
  both skipped navigation saves fail with `raw` instead of `sortedAZ`.
  Long press additionally proves a toggle-plus-launch mutant fails its probe.
  `base4` is the full original-code review baseline. Its comparison uses the
  audited `base3-renamed.json`: the old duplicate's last String outcome is
  renamed to the typed String identity, and int gains one distinct identity;
  seven new play/tap cases are the other additions. The original base3 evidence
  is immutable, all outcomes remain unchanged by normalization, and no failure
  allowlist is updated. Exact mapping is checked in as
  `playlist_content_step0b_identity_renames.json`.

- Step 0b full result: `base4` versus audited `base3-renamed.json` **PASS**:
  10,736 successes, unchanged 13 failures / 28 errors / 20 skips, eight added
  identities and no missing/new failures or changed skips. Raw comparison's
  sole missing spelling is exactly the documented duplicate rename; its nine
  new spellings comprise that rename plus eight additions. All six manifests
  and self-tests pass (107/316/384/195/173/128); whole analyzer has no added or
  removed diagnostics, CI allowlist/format and all 17 warning occurrences pass.
  Original checkpoint and current affected tests pass; no production move yet.

- Step 1: the 14 pure helpers and search-result DTO use their planned
  application/model destinations. Actual per-entry callers are reviewed in
  the wiring checklist; the production caller and frozen accessor use those
  functions. Feature/import/500-line destination guards and explicit theme
  globs are registered. The facade ratchet is 3,935 lines; State resources,
  loading/actions/layout and composition remain until their named steps.
  Evidence `playlist_content/step1-*` passes against latest `base4`: 172 focused/source/shape identities, all six manifest self-tests, exact analyzer comparison, CI format/allowlist, all 17 warning occurrences, architecture/size and storage checks. No new strict-lint infos; original diagnostics are retained.

- Step 2: 29 original fields now live in eight fresh route-owned state/resource
  records. All production reads/writes and the accessor use the same objects;
  original types/defaults and resource expressions remain unchanged. State
  retains complete lifecycle bodies and cleanup order. Each field binding is
  reviewed in the checklist before pinning the eight owner declarations.
  The facade ratchet is 3,896 lines. Evidence `step2-*` versus `base4` passes: 172 focused/source/shape identities; all six manifest self-tests; CI format/allowlist, all 17 warnings, architecture/size and storage checks. Analyzer has no additions and only the documented private-field info removal. The final source reader again passes 26 original-checkpoint guards after its two string-composition lint fixes; no application/checker inputs changed in that final fix.

- Step 2 conservative representation decisions: field documentation links
  name the actual declaring record class. The newly wrapped AllDebrid link-index
  `if` receives braces only around its unchanged `continue;`, with its complete
  raw prefix pinned at the manifest entry. Body fixtures/assertions remain
  frozen. Optional formatter commas are adapted by exact UTF-16 positions and
  full-prefix SHA-256 hashes after the AST verifier proves token parity;
  string-literal comma changes are rejected. The updated source reader passes
  all 26 guards on original 6e23a3c5, as well as current source. The lone removed
  `prefer_final_fields` info is the former private `_folderPath`: its public
  owner field keeps the original mutable type/default, so that private-field
  recommendation no longer applies. All 17 warnings remain required.
  Initial failed source/lint evidence is preserved under `step2-attempt1-*`.


- Step 3: six dependency-record sections now own initialization, navigation,
  saved/view modes, debrid loading, cloud loading and playlist ordering.
  All per-entry production bindings were reviewed before scaffold pinning;
  lifecycle registration/removal keeps the same Navigation instance, and
  item/context/mounted getters remain live. The facade is 3,316 lines.
  Evidence `step3-*` passes against `base4`: 172 focused/source/shape tests,
  all six manifests with self-tests, analyzer comparison with no additions,
  CI format/allowlist, all 17 warnings, architecture/size and storage checks.
  The initializer-removal checker fixture now locates its moved receiver
  through the manifest and still rejects the mutation; its initial lookup
  failure is retained as `step3-attempt1-*`. Only that affected self-test was
  repeated; the other five manifests and unchanged application checks retain
  their recorded passing inputs. Gate 1 follows on the committed tree.

- Gate 1: committed step 3 `730c0a41`, tree
  `adafe86d7c9e33c0580664fc54feec8ce637d584`; `gate1` versus latest `base4`
  **PASS**: 10,736 successes, unchanged 13 failures / 28 errors / 20 skips,
  no added/missing identities or changed outcomes. No tracked changes during
  the run; the five pending Linux PNG paths were recorded as untracked and
  deliberately excluded from the gate commit.
- Linux original handoff: all five supplied PNG hashes match
  `linux-original-sha256.txt`; revision resolves to the exact step-0 subject
  at `6e23a3c5`. Capture and strict original-code logs each pass five scenes.
  Provenance: calibrated `debrify-flutter:3.44.8` linux/amd64 Ubuntu 24.04
  image under Colima, supplied local run dated 2026-10-04T03:04:05Z;
  `linux-original-verified.json` records hashes and provenance. They are
  committed separately. Missing Linux files now fail instead of returning
  successfully; existing assertions and scene construction are retained.
  Step 0b did not change golden scenes, seedSeries or shared fixtures, so
  recapture of the original is unnecessary. A moved-code Linux comparison
  will use this same locally available calibrated image after step 6.

- Step 4: search, progress, watched actions, series/Fix Metadata, poster
  writes and private dormant progress move into six reviewed records.
  Provider/profile ownership, writes after handoff, mounted checks and
  original unsafe continuations are preserved. Facade: 2,569 lines.
  `step4-*` versus `base4` passes: 172 focused/source/shape identities, all
  six manifest self-tests, analyzer comparison with no additions, CI
  format/allowlist, all 17 warnings, architecture/size/storage checks.
  The source reader accepts only whitespace around registered live getters
  after Dart formatting splits a receiver; its 26 source guards pass on
  original `6e23a3c5` as well as moved code. Frozen method bodies and all
  assertions remain unchanged. An initial original-reader invocation with
  a misspelled test path is retained as `step4-attempt1-original-*`; the
  corrected run proves all 26 original guards.

- Step 5: both play entries and all seven launch sites now use three
  reviewed playback records. Live optional playback callback and item
  getters, dialog builder contexts, exact launch arguments, sorting,
  provider dispatch, headers and unsafe start-index policies remain intact.
  The two formatter-induced empty-list canPop lints receive braces only
  around their original pop statements; exact conditions, complete raw
  prefixes and body tokens are pinned alongside the AllDebrid continue
  site. No context acquisition or asynchronous operation is moved.
  Facade: 1,780 lines. `step5-*` versus `base4` passes: 172 affected identities,
  all six manifest self-tests, no added analyzer diagnostics, CI format/
  allowlist, all 17 warnings, architecture/size/storage checks. A clean
  committed focused replay follows before the builder move, so its tree
  evidence includes all three new playback files.

- Step 6: nine reviewed layout records now render the root, search, file
  list, OTT/season selector, episode list/card and both responsive layouts.
  State has the exact build forwarder; registered callback tear-offs retain
  their original targets, lexical builder contexts stay lexical, and all
  three timer protocols stay in their original builders/owners. A generator
  collision with the external `Icons.build` constant was caught during
  binding review and corrected before verification; the original icon stays
  unchanged. The null-series selector's original return receives only exact
  pinned braces for its formatter-induced lint. Four such sites are now
  registered, with unchanged original statements and guards.
  `step6-*` passes against `base4`: 172 identities including five macOS
  goldens, all six manifest self-tests, no added diagnostics, CI format/
  allowlist, all 17 warnings, architecture/size/storage checks. New files
  were staged before these runs, so their stable tested trees include every
  builder. Facade: 499 lines, retaining composition only until step 7.
  Step 5's clean committed replay at `21d1d5ff`, tree
  `df5875d68c18022c68ba543f22600ec164063290`, also passes its 172 tests,
  complete 107-leaf comparison and local focused checks with no untracked
  inputs or changes during the run. Strict moved-code Linux follows on
  the committed step-6 archive in the calibrated image.


## Found, not fixed

All pre-existing; the extraction keeps each exactly.
- **Mobile missing-thumbnail placeholder:** the original 500-pixel layout
  can overflow vertically by 5 pixels under the real app theme. Preserved;
  completed-metadata goldens use deterministic thumbnails.
- **Live IMDb during Fix Metadata:** a supplied in-memory IMDb identity can
  retain precedence over the new mapping; no identity policy is changed.
- **Dispatch mismatch:** `'rd'`, `'torbox_webdl'`, `'real_debrid'` and
  unknown providers load through RD but play nothing, silently (1175–1191,
  3458–3474); `'rd'` items show the whole torrent.
- **Refresh and Retry reload content only** (no reparse or reapply);
  `_currentViewNodes` can point at the old tree.
- **Start index vs skipped entries:** RD, AllDebrid, TorBox and PikPak skip
  unresolvable entries without clamping, so `entries[startIndex]` can be the
  wrong file or throw; Premiumize cloud clamps against pre-filter
  `videoFiles` and then skips null-`path` nodes, with the same effect.
- **AllDebrid re-uploads the magnet** on every open and refresh; Premiumize
  hash resolves twice; PikPak lists 100 per folder with no paging,
  sequentially, throwing beyond depth 4 (fallback tree: null `relativePath`).
- **seriesArrange with no videos** spins and re-parses on every build, once
  the view has nodes (empty view nodes show "No files found" first, 1608).
- **Builder side effects:** the timer recreated per build, the nested
  `setState`, the unguarded post-frame `setState`, per-card `print`s with
  titles and progress, O(n² log n) progress lookups.
- **Unguarded `setState`s** after awaits (160, 318, 346, 2222/2254 in parse,
  1903); no request generations; overlapping loads and metadata fetches.
- **Writes after unmount or a profile switch:** the screen captures no
  scope, so a `.then` imdbId or poster save, Fix Metadata write or watched
  toggle that *starts* after the handoff writes the then-active profile.
  A `ProfilePreferences` instance acquired before the switch rejects its
  later access, but the playlist read-modify-writes reacquire preferences
  to save, so a switch between read and save can write the old profile's
  list into the new profile, tombstoning the new profile's displaced
  entries.
- **Sequential progress lookup** returns a null `0_n` hit without trying the
  filename key; Fix Metadata clears the TVMaze series cache twice; the
  watched button stays tappable on TV while the card's tap and long-press
  don't.
- **View mode persisted on every navigation;** the saved mode read twice.
- **`contentImdbId`** comes from the unrefreshed in-memory item.
- **Progress keys disagree** (title key for reads, `seriesProgressKey(title,
  imdbId)` for toggles); the IMDb-based read is dormant.
- **Posters:** TorBox compares raw ids with `==` (its loader casts
  `as int?`); no artwork update for WebDAV, `'rd'` or `'torbox_webdl'`.
- **Raw aliasing** and the WebDAV builder mutating `children` lists.
- **`print` of raw exceptions** (345, 1202, 3485) may include tokenised URLs.
- **Badges disagree** (search `toInt()%`, file card `round()%`).
- **Back and focus:** root AppBar back pops without `canPop`; no TV
  arrow-left to the sidebar; no focus restore after playback or dialogs;
  no re-entrancy guard on play (double activate can launch twice).
- **Error after the callback:** with the Playlist-tab caller, a throw after
  the dialog was popped pops the content screen instead.
- **Dormant and redundant code:** `_loadProgressData`;
  `_applySeriesArrangeView`'s nodes are never shown; the null-aware
  operators behind the 17 warnings. A platform check sits in presentation.
