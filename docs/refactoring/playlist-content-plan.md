# Playlist content view refactor — plan

Written 2026-10-04 against `ec997117` (file blob `4fc757c7`). Follow
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
5. **View modes.** `_applyViewMode` persists on **every** call (unawaited
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
   - every `PlaylistEntry(...)` construction (RD 3538/3551/3565, AllDebrid
     3641, TorBox 3714/3727/3740, PikPak 3823/3834/3846, Premiumize 3922/3972,
     WebDAV 4033) with its `provider` string and ids; only the start entry is
     resolved except Premiumize hash (all entries) and WebDAV (direct URLs);
   - start index: `_playFile` matches name and path; `_playEpisode` matches
     filename in sortedAZ, else `originalIndex` in range, else filename;
     Premiumize and WebDAV clamp, the others don't.
7. **Preparing dialog and the return from the player.** `showDialog
   (barrierDismissible: false)` (root navigator) before resolving; popped
   through the State's `Navigator.of(context)` on an empty list, after the
   launcher returns (`mounted && canPop`), and in the catch. With the
   Playlist-tab callback the dialog is popped **before** the push, so the
   post-return pop removes **the content screen** (back to the Playlist tab,
   which then refreshes); with Home (no callback) the dialog stays under the
   player and the post-return pop removes **the dialog** (the user stays on
   the content screen). A throw after the callback pops the screen.
   `_reloadProgress` follows in both paths.
8. **Watched toggles** (3304–3388): no confirmation; title from the series
   or item; season and episode default 1; imdbId from the series, then the
   item; `isEpisodeFinished` then `unmark…` or `mark…AsFinished` (local only,
   no trackers); `_reloadProgress`; the inverted snackbar text and colours;
   the error snackbar. Triggers: tap and long-press (non-TV), D-pad hold.
9. **Series metadata and Fix Metadata.** Fix Metadata (2261–2350) keeps its
   exact order: `TVMazeSearchDialog` (`barrierDismissible: false`); read the
   old mapping; if the old id differs, `TVMazeService.clearShowCache` then
   `EpisodeInfoService.clearShowCache`; `EpisodeInfoService.clearSeriesCache`;
   `TVMazeService.clearSeriesCache`; `saveTVMazeSeriesMapping(playlistItem:,
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
    last; blur cancels). The key handler isn't TV-gated; on TV only the
    InkWell `onTap`/`onLongPress` become null and the hold hint shows.
13. **Profile behaviour.** Nothing captures a profile; every read and write
    resolves the active profile at call time. The route sits above
    `ProfileGate` and is disposed by the picker's `popUntil`. No scoping is
    added or removed.
14. **Collection identity and mutable models:** Raw aliasing; `_folderPath`
    mutated in place; the WebDAV builder mutating `children`; in-place
    `SeriesPlaylist` updates; `widget.playlistItem` never refreshed.
15. **Diagnostics.** The 18 analyzer warnings (step 0 item 7) keep firing at
    their destinations; the 39 `print`s and their text stay.

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
  State's lifecycle, the `build` forwarder, owners, wiring and the accessor.
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
1. **The live widget accessor stays typed `PlaylistContentViewScreen`**
   (non-nullable). The 11 `invalid_null_aware_operator`, the
   `unnecessary_null_comparison` at 2212 and the `!` at 2214 fire only
   because `widget.playlistItem` is non-nullable; a nullable or `dynamic`
   receiver would silently drop or change them.
2. **Private dormant and warned members stay private** in the section that
   owns them: `_loadProgressData` moves privately into the dormant section,
   keeping `unused_element` with its exact message. If any warned member
   must become public, the warning's disappearance is recorded under "Found,
   not fixed" (the PikPak `_email` rule) and no allowlist entry is added.
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
| 4 | Search, progress, watched toggle, series metadata, Fix Metadata, posters, dormant code | Contracts 8, 9, 11, 13. |
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
4. **Accessor** (the approved seam; there is no TV, clock or launcher seam):
   a frozen `@visibleForTesting playlistContentTestAccess(State)` in the
   facade returning fresh snapshots (tree, view nodes, folder path, view
   mode, series playlist, progress cache, search state, the three timers,
   flags) and real tear-offs (loaders, `_applyViewMode`,
   `_applySortedPlaylistOrder`, `_playFile`, `_playEpisode`, the six play
   methods, `_toggleWatchedState`, `_showFixMetadataDialog`,
   `_saveImdbIdToPlaylist`, `_handleBackNavigation`), and one TV setter that
   assigns `_isAndroidTv` and calls `(state.context as Element)
   .markNeedsBuild()` (after `_checkIfAndroidTv` has settled to false). The
   seam-only facade size raise is recorded and exits at step 1.
5. **Harness** (`test/support/playlist_content_fixture.dart`): the PikPak
   fixture's profile setup (`SharedPreferences` mocks, `ProfileRuntime`
   reset and `initializeLegacy`, `SecretVault.debugReset`), seeded API keys
   and WebDAV servers, `http.runWithClient` with a `MockClient` per provider
   host and `api.tvmaze.com` (resolve each base URL from the services; JSON
   bodies), sqflite ffi only if the first fixture proves it necessary. Items
   carry no `poster`. Launch fixtures omit `imdbId`/`contentType` unless a
   case needs them (the launcher writes continue-watching and seeds trackers
   for catalog ids). **Launch probe:** the
   `video_player_launcher_settings_rejection_test.dart` recipe, adapted: a
   player-launch listener that passes the screen's own
   `notifyPlayerLaunching()` and throws `NativePlayerSettingsUnavailable` on
   the launcher's (second) call, so the real launcher accepts the args,
   logs its playlist trace (`debugPrint` captured: entry count, titles,
   `relativePath` of the first five), shows its snackbar and **returns
   without opening a player**. Prove one HTTP fixture and the probe on the
   original code first.
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
   | 6 Playback | Per site through the probe: the HTTP log (start entry resolved only, Premiumize hash all, AllDebrid unlock errors swallowed), the launcher's playlist trace (count, titles, relative paths incl. `_cleanTorboxPath` and the PikPak fallback), `onPlaybackStarted` once before the launcher's notify. Start index through the accessor: sorted vs raw, `originalIndex` fallback, Premiumize/WebDAV clamp. **Source guards** on the seven complete call expressions, the guard→callback→notify→push sequence, and every `PlaylistEntry` construction; remaining argument values (ids, flags, `viewMode`, WebDAV headers and fields) are **pending device verification**. |
   | 7 Return | With a `NavigatorObserver`, the screen pushed with each caller's construction reproduced verbatim (source guards pin both caller expressions): Playlist-tab form → dialog popped before the launch, content route popped after the probe returns; Home form → dialog popped after return, content screen still mounted. Plus the empty-list and catch paths. |
   | 8 Watched | Mark and unmark arguments (title fallback, defaults, imdbId preference), the persisted completion, reload, snackbar text and colour, error snackbar; via tap, long-press, D-pad hold. |
   | 9 Metadata | Fix Metadata with a fake dialog result: cache-clear calls in order (conditional pair), mapping, poster override and per-provider artwork or TorBox list write, forced imdbId, nulled fields, loading flag; cancel does nothing. Unforced imdbId save rules; detected-poster write; writes landing after unmount (recorded). |
   | 10 Timers/build | Fake time: auto-switch to A–Z at 2 s with persistence, timer object replaced per rebuild; missing-season post-frame `setState`; scroll retries and the 800 ms animation; `print` capture shows the per-card lines. |
   | 11 Search | Recursive video-only matches, paths, clear and close, hidden in seriesArrange. |
   | 12 D-pad | Clear-button keys, search-field arrows, file-card select/enter/space, episode KeyDown/hold 800 ms/repeat ignored/short press/300 ms suppression (host keys); via the TV setter: null `onTap`/`onLongPress` and the hold hint. |
   | 13 Profile | A profile switch through the gate's picker disposes the route (handler gone, timers cancelled); two routes on the same item share no owners. |
   | 14 Identity | Through the accessor: Raw aliasing, `_folderPath` identity, `_searchResults` reassign-then-clear, `_applySortedPlaylistOrder` mutating its argument. |

   Pixel goldens (raw list, search, OTT mobile and desktop, error) on macOS
   and Linux, Linux captured by Claude from the original code. Record
   `base2` after the accessor and `base3` after the tests; compare each.
   Then a step-0b review closes with ORIGINAL-only mutation negatives
   (e.g. a play dispatch with an else, persistence skipped on navigation,
   swapped dispose statements, a non-recreated auto-switch timer, the
   Playlist-tab callback removed) each rejected.
7. **Source-text inventory:**
   - **Analyzer allowlist:** the 18 warnings — `unused_element`
     (`_loadProgressData`, 274), `dead_null_aware_expression` (440, 3526),
     `unnecessary_null_comparison` (832, 2212), `invalid_null_aware_operator`
     ×11 (2114–2132, 2232, 2329), `unnecessary_non_null_assertion` (2214).
     Adding the facade to the CI analyze list in step 0 needs five entries
     at the facade path. Each moving commit relocates entries in the same
     commit; a facade entry leaves only when its last occurrence leaves.
     The checker matches sets, not counts, so the per-symbol relocation
     comparison must also show all 18 occurrences, by rule and enclosing
     member, at every step.
   - **Shape:** 0 bare radii and **11 token calls** (1308, 1357, 1493, 1740,
     2540, 2545, 2777, 2820, 2873, 3033, 3224). The floor is **488 with zero
     slack** (measured: 125 `kShapeResidue` files hold exactly 488), so
     every destination receiving a token call goes in `kShapeResidue`
     (residue 0) and every other destination in `kExtractedShapeResidue`;
     the facade leaves `kShapeResidue` when its last call leaves (step 6).
     Parallel refactors also move tokens; Claude re-sums at integration.
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
   Linux test stays non-strict through step 5.

### Per step and gates

As in the PikPak plan, with `--relocate
lib/screens/playlist_content_view_screen.dart=lib/features/playlist_content/`,
every existing manifest run (settings, IPTV results, TorBox, Real-Debrid,
PikPak, and IPTV settings once integrated) plus this one with self-tests (an
isolated parser cache when run concurrently), the allowlist and per-symbol
warning comparison, the shape floor, LF-only manifests and staged diff
checks before each commit, and gates on committed trees against the latest
playlist-content base. Never `--record` to accept a regression.

## Definition of done

1. The facade is at most 400 lines, formatted, holding the public widget
   and the State with verbatim lifecycle, forwarder, owners, wiring and the
   frozen accessor. Both callers compile unchanged.
2. The guard registers the feature, the exact bridge, the facade cap and
   `TEMP(playlist_content)` rejection, and the import bans (cloud features
   both ways, `playlist_player_service.dart`, facade back-import).
3. All manifest runs pass with self-tests; every characterization test
   passes unchanged; all seven launch-site guards are byte-identical.
4. No new diagnostics or suppressions; all 18 warnings still fire, each
   allowlisted at its destination with no stale entry; gate 2 passes against
   the latest base and gate 1.
5. Local CI-equivalent checks pass; remote CI is pending until Claude
   pushes. The test list holds the new tests; the failure allowlist gains
   nothing.
6. Progress records the commits, ownership, exceptions with exit
   milestones, the seam, and pending device verification (seven real
   launches per provider with both callers, Android TV D-pad hold and hint,
   real provider accounts, the Linux run of moved code).
7. Stop after gate 2 and report.

## Explicitly not in scope

- Merging anything with the cloud features, `premiumize_files_screen.dart`
  or `playlist_player_service.dart`.
- The player, launcher and `player_launch`; services, storage,
  `SeriesPlaylist`, `TVMazeSearchDialog`, `ViewModeDropdown`; the callers.
- Bug fixes and behaviour changes, including everything below.

## Progress

(empty)

## Found, not fixed

All pre-existing; the extraction keeps each exactly.
- **Dispatch mismatch:** `'rd'`, `'torbox_webdl'`, `'real_debrid'` and
  unknown providers load through RD but play nothing, silently (1175–1191,
  3458–3474); `'rd'` items show the whole torrent.
- **Refresh and Retry reload content only** (no reparse or reapply);
  `_currentViewNodes` can point at the old tree.
- **Start index vs skipped entries:** RD, AllDebrid, TorBox and PikPak skip
  unresolvable entries without clamping, so `entries[startIndex]` can be the
  wrong file or throw.
- **AllDebrid re-uploads the magnet** on every open and refresh; Premiumize
  hash resolves twice; PikPak lists 100 per folder with no paging,
  sequentially, throwing beyond depth 4 (fallback tree: null `relativePath`).
- **seriesArrange with no videos** spins and re-parses on every build.
- **Builder side effects:** the timer recreated per build, the nested
  `setState`, the unguarded post-frame `setState`, per-card `print`s with
  titles and progress, O(n² log n) progress lookups.
- **Unguarded `setState`s** after awaits (160, 318, 346, 222/254 in parse,
  1903); no request generations; overlapping loads and metadata fetches.
- **Writes after unmount or a profile switch:** the `.then` imdbId and poster
  saves, Fix Metadata writes and watched toggles land in the then-active
  profile; nothing captures a profile.
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
  operators behind the 18 warnings. A platform check sits in presentation.
