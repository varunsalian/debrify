# Episodes panel refactor — plan

Written 2026-10-04 on `refactor/codebase` at `10ceef60`. Follow
[AGENTS.md](../../AGENTS.md).

Read first: `docs/refactoring/merged-detail-plan.md` (its host-callback and
`EpisodesPanel` forwarding contracts, its contract 8 on
`WatchedActionCoordinator`, and its Progress), `spotlight-board-plan.md`
(public State, re-exports, the two-original scheme, bound-State techniques)
and `playlist-content-plan.md` (its Progress). This plan reuses their
technique, checker (`check_verbatim_moves.py` over `check_settings_moves.py`),
tooling, staging and gate procedure, and states only what differs: callback
identity with wrapper and receiver-swap negatives; `suite_evidence.py`
tree-recording evidence; real-config fixtures; original-code worktree proofs
and mutation negatives; the wiring checklist; Linux goldens captured from
the original code in the calibrated local Docker image.

**Execution.** Its own git worktree on `refactor/episodes-panel`, cut from
`refactor/codebase`, in parallel with other refactors; Progress records the
execution base SHA at step 0 and every proof names it. Commit after every
step; never push; gate commits contain `gate`. Remote CI stays pending until
Claude pushes, so every step runs the local CI-equivalent commands.
Evidence goes **only** under `refactor-evidence/episodes_panel/`; no other
shared evidence namespace is written. **Every manifest run passes an
isolated `--parser-package`** (this worktree's
`.dart_tool/episodes_panel_parser/`), including self-tests and other
features' manifests. Analyzer runs use `flutter analyze --no-pub`, serially.

## Goal

`lib/widgets/episodes_panel.dart` is 3,112 lines: 40 imports (unordered), 7
top-level declarations (`EpisodeFocusIntent`, `EpisodesPanelView`,
`EpisodesPanel`, `EpisodesPanelState`, `_CatalogSelectSourceButton`(+State),
`_SeasonStepButton`, `_CompactEpisodeRow`(+State)), no functions, typedefs or
`part`s. It is the episode drill-down engine and UI: season fetch and
grouping, landing, the four-source watch-progress merge, enrichment,
metadata re-presentation, watched fan-out, tracker menus, season options,
the Classic chrome, the compact (merged-page) layout and the
`contentBuilder` view for alternate layouts.

Split it into a new feature, `lib/features/episodes_panel/`, **moving code
verbatim**. The widget tree, keys, focus nodes and debug labels, build order
and the State's lifecycle are unchanged. Nothing is fixed.

**Playback category: accepted (host callbacks only).** The panel launches
no player, resolves no sources and holds no callback a player calls back
into (0 code hits for `VideoPlayerLauncher`, `VideoPlayerScreen`,
`TorrentPlayback*`, `SeriesSourceFetcher`, `mergeSources`; its three
`Navigator.pop(ctx, …)` close its own sheets). Outbound: `onItemSelected`,
`onQuickPlay`, `onPlayEpisode` (plus the non-playback host callbacks).
Inbound only: the host's `GlobalKey<EpisodesPanelState>` calling
`refreshWatchProgress()` (`merged_series_detail_screen.dart:371`,
`merged_detail_playback_actions.dart:114`) and the panel's listener on
`MdblistService.instance.playbackRevision` (bumped at
`mdblist_service.dart:1061` after a scrobble). Both are pinned by contracts
and source guards. **No player, launcher, service or host code is touched.**

**Why a new feature behind a facade at the original path.** AGENTS requires
migrated code under `lib/features/<feature>/`; a split inside `lib/widgets/`
has no size, architecture, format or analyzer guard. The facade stays
because 12 production files import the path (`episodes_screen.dart`,
`merged_series_detail_screen.dart`, three `legacy_merged_detail/` files, six
`lib/widgets/detail/detail_layout_*.dart` and `showcase_parts.dart`) and 10
tests do; `check_search_architecture.py` forbids `merged_detail` from
importing another feature outside `models/`, but a `lib/widgets/` import is
legal. Placing the panel in `merged_detail` is rejected (a completed feature
whose source contracts scan the whole folder; Classic `EpisodesScreen` is
not merged-detail).

**Temporary exceptions and exits.**

| Exception | Exit |
| --- | --- |
| State-driven sections instead of Riverpod | Episode-guide notifiers keyed by profile and route instance |
| `legacy_episodes_panel/` bridge importing ~20 `lib/services/` modules and `EpisodeResumeStorage` | Episode data contracts (seasons, progress, watched writes, ratings) |
| Direct `PlatformUtil.isTelevision` reads (2681, 2698) | A TV-capability adapter |
| ~35 hardcoded English strings | The app-wide localization migration |
| Display names doubling as target identities (FNF 4) | The watched-target contract with the data migration |

## Public surface (importable from the facade, unchanged)

- **`EpisodesPanel` stays in the facade, byte-identical**: 23 fields with
  doc comments (field order differs from parameter order: `addon` is the 4th
  field but 2nd parameter), the 24-parameter constructor (`super.key` +
  23), the unindented `onNextEpisodeChanged` type and `createState() =>
  EpisodesPanelState()`. The merged checker pins the host's
  `EpisodesPanel(...)` call (`merged_detail_checker_config.json:480–506`,
  `merged_detail_checker_test.py:101–102`), so no class, parameter or type
  name changes.
- **`EpisodesPanelState` stays in the facade and public** (IPTV results-view
  pattern: the widget's `createState` names it and the host's GlobalKey
  types it). It keeps its doc comment, `extends State<EpisodesPanel>`
  header (no mixin, no `implements`), the verbatim `initState`/`dispose`,
  `refreshWatchProgress()` with its doc and signature, `consumeFocusIntent()`
  (zero callers, kept), a `build` forwarder and composition. No
  `didUpdateWidget`, `didChangeDependencies` or `deactivate` is added.
- **`EpisodeFocusIntent` and `EpisodesPanelView` move to
  `models/episodes_panel_view.dart` and are re-exported** (spotlight-board
  precedent): `export
  'package:debrify/features/episodes_panel/models/episodes_panel_view.dart'
  show EpisodeFocusIntent, EpisodesPanelView;`. The models layer may import
  `package:flutter/foundation.dart` (`VoidCallback`) and
  `lib/services/trakt/trakt_episode_model.dart` (`TraktSeason`,
  `TraktEpisode`), and nothing UI. The contiguous `///` block 44–53 (the
  panel's class doc that is today the enum's dartdoc, FNF 1) moves **with
  the enum**, unchanged; the manifest records it as the enum's fragment.
- Callers and all 10 importing tests compile unchanged; Progress proves it
  with a compile-only check at steps 1 and 7.

## What it contains (lines at `10ceef60`; after the format commit the manifest is authoritative)

| Lines | Area |
| --- | --- |
| 1–42 | 40 imports (20 `lib/services/**`) |
| 44–141 | Panel doc + `EpisodeFocusIntent`; `EpisodesPanelView` (19 final fields) |
| 143–276 | `EpisodesPanel` |
| 278–418 | State doc, 27 leading fields (4 service singletons, load state, auth flags, 5 FocusNode/controller resources), getters, `initState`, `dispose` |
| 420–672 | `_loadEpisodeWatchProgress` (181 formatted), `_logEpisodeProgress`, `_mergedUpNext`, `_publishNextEpisode`, `_publishSeriesCompletion` |
| 674–740 | MDBList revision refresh, `refreshWatchProgress`, `_isDirectSource`, `_resolve{Trakt,Simkl,Mdblist}Auth` |
| 742–940 | `_watchedSyncTargets`, static `_joinNames`, `_setEpisodeWatchedEverywhere`, Trakt and MDBList menu actions |
| 942–1375 | `_fallbackToDirectSearch`, `_fetchSeasons`, `_groupVideosIntoSeasons`, static `_downsizeMetahubThumb`, `_enterEpisodeMode` (≈285 formatted), `_directLandingTarget` |
| 1377–1623 | Ratings/thumbnail enrichment, `_scrollFocusEpisode`; **mid-class fields** 1563–1564, `_episodePolicyChanged`, metadata landing/load |
| 1625–1754 | `_onSeasonChanged`, `_onEpisodeTap`, `_onEpisodeQuickPlay` |
| 1756–2219 | Classic rendering, `build`, `_buildView`, `consumeFocusIntent` |
| 2221–2605 | Compact section (**mid-class fields** 2226–2227), `_showSeasonOptions`, `_stepSeason`, compact header/content, `_showEpisodeOptions` (≈197 formatted) |
| 2607–3112 | `_CatalogSelectSourceButton`(+State), `_SeasonStepButton`, `_CompactEpisodeRow`(+State; `build` ≈299) |

No member exceeds 500 formatted lines; **no size exception is needed**.
State: 31 instance fields (0 `late`, 0 static), 2 static methods, 6 getters.

## Contracts that must not change

1. **Public surface** as above, byte-identical, with the re-export.
2. **Host handoffs (outbound).** `_onEpisodeTap` (1656–1704): `onPlayEpisode`
   short-circuits; otherwise the `AdvancedSearchSelection` (Stremio episode
   identity added only for a non-canonical video id, 1689–1701), then
   `onBeforeTerminalDispatch?.call()` **before** `onItemSelected!`.
   `_onEpisodeQuickPlay` (1706–1754): `onBeforeTerminalDispatch`, then
   `onQuickPlay` else `onItemSelected`. `_fallbackToDirectSearch` (945–957):
   `onBeforeTerminalDispatch`, then the series selection. Also `onSelectSource`
   (awaited, 1866), `onBack`, `onFocusLeftEdge`, `boundSourceCount`,
   `seasonsLoader`, `watchProgressLoader`, `onNextEpisodeChanged(…, mutation:)`
   and `onSeriesCompletedChanged`: each invoked synchronously at its original
   site through a live read of the widget property, never cached. Selection
   fields are the append-only pipeline's input (merged contract 5), so they
   move verbatim.
3. **Inbound couplings.** `refreshWatchProgress()` stays a public method of
   `EpisodesPanelState` with signature `Future<void> refreshWatchProgress()
   async`; its two internal callers (`_refreshAfterMdblistMutation` and the
   season mark at 2300) reach **that State method** through a bound
   tear-off, never a section copy. The `playbackRevision` listener keeps the
   route-current wait (20 × 100 ms), the 750 ms wait, token supersession and
   one `await refreshWatchProgress()`.
4. **Lifecycle.**
   - `initState` (381–402): `super.initState()`; the **same tear-off
     `_episodePolicyChanged` on two static notifiers**
     (`MetadataPreferencesService.revision`, then `ProfileRuntime.scope`);
     the dropdown `onKeyEvent` assignment only when `widget.showChrome`
     (fixed at init, FNF 9); the three `_resolve*Auth()` calls with discarded
     futures (no `unawaited` added); the `playbackRevision` add; the
     fire-and-forget `_enterEpisodeMode(widget.show, …)`.
   - `dispose` (405–418), 10 steps in order: remove revision listener;
     remove scope listener; `_mdblistRefreshToken++`; remove
     `playbackRevision`; dispose scroll controller; back, season, retry
     nodes; the episode-node loop; `super.dispose()` (not the reverse of the
     add order; kept).
   - **Callback identity:** each add/remove pair uses the same notifier
     expression, the same receiver path and the same member; the policy
     section is constructed once per State, so its two tear-offs compare
     equal at add and remove.
   - **No `didUpdateWidget`** (and none of the other hooks) exists, and none
     is added.
   - Resources keep their creation time (State construction), instances and
     debug labels: `'catalog-ep-back'`, **`'catalog-ep-season'`** (found by
     `merged_detail_focus_test.dart:62`), `'catalog-ep-retry'`,
     `'catalog-ep-$i'` (recreated in `_enterEpisodeMode` and
     `_onSeasonChanged`, with the original dispose-before/after-`setState`
     placement, FNF 13) and `'catalog-select-source-btn'`.
5. **Watched writes** go through `WatchedActionCoordinator.setEpisodeWatched`
   (`watched_action_coordinator.dart:174–262`) with `imdbId: progressId ??
   id`, `seriesTitle`, `season`, `episode`, `watched` and no `forceTargets`.
   The coordinator **always** writes local completion
   (`EpisodeCompletionStorage.markEpisodeAsFinished` on watch,
   `unmarkEpisodeAsFinished` on unwatch) and invalidates the local snapshot;
   custom ids stop there. Trakt, Simkl and MDBList (IMDb or native ids) are
   written only when the content policy selects the source **and** a fresh
   `isAuthenticated()` passes; a successful Simkl watch also deletes
   episode playback. The panel computes targets from **initState-cached**
   auth (`_watchedSyncTargets`, always appending `'this device'`), then
   `mounted`, `MdblistContinueWatchingService.invalidate()`, `done = targets −
   failed`, the `rendersHere` gate, the in-place optimistic tick, `_mergedUpNext`,
   `_publishNextEpisode(next, mutation: true)` only when `next != null`,
   `_publishSeriesCompletion()`, then the snackbar. **The misleading comments
   are preserved verbatim** (the checker compares comments): 742–746 and
   771–777 ("on watch only when it is the sole store", "every connected
   tracker"), the "(Unwatch always changes at least local storage.)" note
   (~800), 420–426 ("two sources … all three") and 703 ("local + Trakt").
   Coordinator and services are untouched.
6. **Reads and loads.** The progress merge rules (Trakt/Simkl `> 5` floor and
   no downgrade of 100; MDBList `>= 100 || > existing` with no floor; ratings
   assigned outside `setState`), the twice-loaded `TrackingSourcePolicy`,
   landing tiers and pair validation, the direct-source `>= 95 → next` rule,
   `scopeSeriesProgress` and `recordEpisodeInventory` calls, `MetadataEpisodeService.present(widget.show, …)`
   (not `_selectedShow`, FNF 14), every generation/token (`_episodeModeGeneration`,
   `_viewGeneration`, `_episodeMetadataGeneration` with its
   `ProfileRuntime.scope` capture, `_mdblistRefreshToken`) at its original
   site; the missing guards (FNF 5, 6, 11) are neither added nor removed.
7. **In-place mutation and identity.** `_episodeWatchProgress` and
   `_episodeMdblistRatings` are mutated in place; the direct loader's map is
   stored by reference; `TraktEpisode.rating`/`thumbnailUrl` are mutated;
   `_episodeSeasons` starts growable `[]`; `_seasonRetries` is one
   `SeasonWatchedRetryState` per State.
8. **Season options.** Hold-OK/long-press via `SeasonActionRegion`
   (`TvHoldOk`), short OK opens the season list; fresh auth per tracker;
   custom ids disable all trackers, **native ids disable Trakt and MDBList**
   (FNF 16); `SeasonWatchedService.mark` to one provider, then
   `refreshWatchProgress()` (future discarded); `_seasonActionBusy`
   reentrancy guard.
9. **D-pad and focus.** Classic back button (Up swallowed, Right/Down
   targets, Activate/Escape/goBack → `onBack`, whole-panel `setState` on focus,
   FNF 21); dropdown keys (only with chrome); select-source button keys;
   TV autofocus on Retry; compact rows (OK/Space play, Right options, Left
   `onLeft` or ignored, `KeyDownEvent` only, `ensureVisible` 220 ms on TV);
   `_stepSeason`'s post-frame refocus; the three `TvHeldKeyGuard` sheets and
   their TV autofocus; landing via `_scrollFocusEpisode` (16 attempts).
10. **Rendering.** Classic (chrome), compact, slim (dormant, FNF 8) and custom
    branches; `RepaintBoundary` and `CachedNetworkImage(cacheManager:
    DebrifyImageCache.manager, memCacheWidth: 300)` on compact rows; `HomeTheme`
    durations; no new `const`.

## Destination layout

All under `lib/features/episodes_panel/`; each destination at most 500
formatted lines. The step 0 dependency report settles exact membership from
actual imports (any file naming `TraktSeason`/`TraktEpisode` imports
`lib/services/` and therefore belongs in `models/` or the bridge).

- **`models/episodes_panel_view.dart`:** the doc block, `EpisodeFocusIntent`,
  `EpisodesPanelView` (re-exported).
- **`application/`:** `_joinNames` and `_downsizeMetahubThumb` (pure,
  service-free statics), each with its comment, as public manifest-listed names.
- **`presentation/` (outside the bridge):** `_SeasonStepButton` and
  `_CatalogSelectSourceButton`(+State) if their imports are service-free
  (`DetailThemeScope`, `PlatformUtil`, `tv_keys` are allowed).
- **`presentation/legacy_episodes_panel/`** (the bridge; exact path in the
  guard): the deps record (typed live getters per `EpisodesPanel` property,
  plus `context`/`mounted`/`setState` callbacks and the State's
  `refreshWatchProgress` tear-off: merged/IPTV technique; the facade's
  widget type never crosses); the owners (the leading fields, same
  initializers, collection identity); sections: progress load and publish;
  tracker auth and MDBList refresh; watched fan-out and tracker menus;
  season fetch and grouping; episode mode and landing; enrichment and
  scroll focus; metadata re-presentation (**with the mid-class fields
  1563–1564 declared immediately before `_episodePolicyChanged`**);
  navigation handoffs (`_onSeasonChanged`, `_onEpisodeTap`,
  `_onEpisodeQuickPlay`, together in one file); Classic chrome and content;
  root `build` body and `_buildView`; compact header/content; season options
  (**mid-class fields 2226–2227 immediately before `_showSeasonOptions`**);
  the episode options sheet; `_CompactEpisodeRow`(+State)
  (`DebrifyImageCache`).
- **Private widget classes stay private** (runtime type names unchanged; no
  `Key? key`, no `const`); cross-file construction uses exact public typedef
  aliases (merged precedent), or constant constructor tear-off exports where
  a step 0 lint probe shows the typedef surfaces unused optional parameters.
  Either way, no `use_key_in_widget_constructors` or
  `library_private_types_in_public_api` identity is introduced.
- **The facade** keeps imports (sorted), the re-export, `EpisodesPanel`, and
  the State (doc, header, composition in the State's constructor body as
  assigned `late final`s, resources created there in field order, lifecycle,
  `refreshWatchProgress`, `consumeFocusIntent`, `build` forwarder). Estimate:
  imports ~35, re-export 3, widget ~136, State ~170, blanks ~20 ≈ 360.
  **Target 400, cap = measured value at most 450**; Progress records `wc -l`
  and a per-span breakdown summing to it from step 3. No accessor is
  planned (`contentBuilder` exposes `EpisodesPanelView`); if step 0 proves
  one necessary it is frozen, counted and its seam-only size raise recorded.
- **Guard rules** (step 1, `check_search_architecture.py`): `"episodes_panel"`
  in `FEATURES`; `EPISODES_PANEL_FACADE = "lib/widgets/episodes_panel.dart"`,
  `EPISODES_PANEL_BRIDGE =
  "lib/features/episodes_panel/presentation/legacy_episodes_panel/"`,
  `EPISODES_PANEL_COMPLETE = False`; the bridge in `LEGACY_PLAYBACK_BRIDGES`
  (still no `http`, `shared_preferences`, `sqflite`); no file under
  `lib/features/episodes_panel/` imports the facade; no service/storage
  import outside the bridge (and none in `application/`); bans in both
  directions between `episodes_panel` and `merged_detail`, `catalog_detail`
  and `detail_showcase` except `<other>/models/` (written by name so they
  apply whenever those features land); a ban on any `lib/features/episodes_panel/`
  file mentioning `VideoPlayerLauncher`, `VideoPlayerScreen`,
  `SeriesSourceFetcher`, `mergeSources` or `TorrentPlayback`; 500-line
  destination caps. Step 7: `EPISODES_PANEL_COMPLETE = True`, the facade in
  `main()`'s paths and `COMPOSITION_ROOTS` (commented as the feature's
  composition root), its cap and `TEMP(episodes_panel)` rejection; tests
  run the real checker on a temporary tree copy and must reject a missing
  facade, cap + 1, `TEMP(episodes_panel)` in the facade or outside the
  bridge, a facade back-import, and a cross-import with each banned feature.

## Technique

As in the merged-detail and spotlight plans, plus:

1. **Two step 0 originals.**
   - **(a) Format-only commit** (`style(episodes-panel): format the original
     episodes panel`): `dart format` on this file only, **3,112 → 3,232**
     lines in 34 `diff -U0` hunks. The proof (reusing
     `merged_detail_format_proof.py` with explicit `--original`,
     `--formatted`, `--parser-package`, `--output`) compares whole-file
     scanner tokens after removing only AST-identified optional trailing
     commas: exactly **37 inserted and 3 removed** (collapsed collections),
     each listed by AST node and owner; every comment and literal identical;
     negatives (an edited comment or literal, a non-optional comma, a
     required singleton-record comma) fail; `--set-exit-if-changed`
     idempotence. No format-induced diagnostic is predicted; the step 0
     analyzer comparison must show the formatted run equal to the original
     by rule, symbol and message (the curly info moves from 2306 to
     formatted ≈2419 inside `_showSeasonOptions`). Any new info stops the
     work for a user decision (merged precedent); none is accepted silently.
     **Raise `file_size_baseline.txt:24` by hand** 3112 → 3232 (seam-only;
     lowered from step 1, removed below 800). Record
     `episodes_panel/base-fmt`. (a) is the verbatim-comparison ORIGINAL and
     the approved application reference R (`--baseline`, relocation,
     hash rule).
   - **(b) Characterization checkpoint** (`test(episodes-panel): step 0
     original-code characterization checkpoint`): application files
     unchanged from R; adds tests, harness, source reader, fixtures,
     checker config and macOS goldens. Progress proves `git rev-parse
     <b>:lib` = `<R>:lib` (and `pubspec.yaml`, `pubspec.lock`). If a seam
     proves necessary it becomes a named seam checkpoint between (a) and
     (b), and R is that commit everywhere.
2. **Strict-lint baseline.** Analyze (a) under
   `lib/features/analysis_options.yaml` in a detached copy inside the ignored
   `.dart_tool/`, qualifying relative imports only. Expected: **19 infos =
   18 `directives_ordering` + 1 `curly_braces_in_flow_control_structures`
   (`_showSeasonOptions`), 0 `prefer_const_constructors`, 0 warnings** (default
   config: that 1 info only; no `analyzer_allowlist.txt` entry). A
   throwaway rename-only probe applies exactly the manifest's public renames
   and alias/tear-off exports and inventories any resulting identities;
   comparison combines baseline and probe by maximum, never sum. End state:
   the 18 ordering infos disappear through sorted imports (documented); the
   curly info traces to its original symbol; zero additions.
3. **Live reads, nothing hoisted.** Sections reach `widget.<p>` through the
   deps getters, `context`/`mounted`/`setState` through registered live
   callbacks (`live_widget_getters`), evaluated at the original sites.
   `ModalRoute.of(context)` in async code stays where it is (FNF 21). Every
   `mounted` and generation guard stays in position.
4. **Verbatim comments.** The checker compares comments: no rewording,
   including the misleading ones in contract 5; each comment fragment's
   owner is in the manifest, and the mid-class field fragments keep their
   adjacency.
5. **Callback identity** (receiver path plus member; wrapper and same-class
   receiver-swap negatives) for: both `_episodePolicyChanged` sites and
   their removals; the `playbackRevision` pair; the dropdown `onKeyEvent`
   assignment; the `refreshWatchProgress` tear-off handed to sections; every
   tear-off handed to `EpisodesPanelView`, `EpisodeTile`, the sheets and the
   private widgets.
6. **Merged checker stays green.** After every step run the merged
   manifest with `--self-test` and `merged_detail_source_contract_test`
   (its recursive scan of `lib/features/merged_detail/` must see no
   episodes-panel file); the host's `EpisodesPanel(...)` call is never edited.

## Steps

| # | Work | Contracts |
| --- | --- | --- |
| 0 | Baseline; (a) and `base-fmt`; lint probes; deps report; manifest and config; harness, characterization, goldens; checkpoint (b); CI list; source-text inventory; Linux script; step 0b review | Nothing moves |
| 1 | Guard registration; `models/` (re-exported); `application/` helpers; shape and theme registration begin | 1 |
| 2 | `_SeasonStepButton`, `_CatalogSelectSourceButton`, `_CompactEpisodeRow` (whole classes with States) | 9, 10 |
| 3 | Deps record, owners, composition; lifecycle verbatim | 3, 4, 7 |
| 4 | Progress load/publish, tracker auth, MDBList refresh, watched fan-out and menus, metadata re-presentation, season fetch, episode mode, enrichment. **Full-suite gate 1.** | 3, 5, 6, 7 |
| 5 | Navigation handoffs, season options, episode options sheet | 2, 5, 8 |
| 6 | `build` forwarder, `_buildView`, Classic, compact. Committed Linux originals are a prerequisite. | 9, 10 |
| 7 | Completion guards, facade cap, CI scopes. **Full-suite gate 2.** | All |

### Step 0

1. **Baselines.** `episodes_panel/base` on the untouched branch head
   (`suite_evidence.py run`, whole-repo analyzer, tree and SDK provenance,
   Flutter 3.44.8 / Dart 3.12.2, `--no-pub`); `base-fmt` after (a), equal by
   identity.
2. **Dependency report** (`docs/refactoring/episodes-panel-deps.md`): every
   leaf (31 fields, 6 getters, methods, 7 declarations, comment fragments)
   with destination; reads of `widget` (by property), `context`, `mounted`,
   `setState`, `this`; tear-offs; resource owners; the wiring checklist,
   reviewed before any scaffold is pinned.
3. **Checker.** `dev/tool/episodes_panel_manifest.tsv` (LF only; check the
   staged diff), `episodes_panel_checker_config.json`,
   `episodes_panel_checker_test.py` with real-config fixtures, plus
   `dev/tool/episodes_panel_public_surface.txt` (the verbatim `EpisodesPanel`
   text from (a)). Negatives: each listener tear-off wrapped or
   receiver-swapped (the two policy sites, the revision pair); the two
   policy adds sharing **different** owner instances; each removal deleted
   individually; the first two and last two disposal steps swapped; a
   `didUpdateWidget` added; a debug label changed; `refreshWatchProgress`
   called on a section instead of the State; `onBeforeTerminalDispatch`
   moved after dispatch; `onQuickPlay`/`onItemSelected` swapped; a cached
   widget property; a mid-class field separated from its method; a reworded
   comment; a new `const`; a changed public-surface byte.
4. **Harness** (`test/support/episodes_panel_fixture.dart`):
   `SharedPreferences.setMockInitialValues`; `SecretVault.debugReset(deviceIdOverride:)`;
   root `flutter_test_config.dart` `ProfileRuntime` init and reset;
   `SimklService.instance.resetProfileScope`; tracker tokens via
   `TraktStorage`/`SimklStorage`/MDBList storage;
   `TrackingSourceStorage.setTrackingScrobbleTargets`; `http.runWithClient`
   + a recording `MockClient` (method, host, path, query, exact JSON body;
   TVMaze → 404); `MaterialApp` + `AppThemeScope(AppThemes.legacy)` +
   `Scaffold`; `PlatformUtil.debugSetAndroidTvCached` reset in teardown;
   **unique addon ids per case** (`StremioService._seriesMetaCache` is
   process-wide, 15 min TTL, no reset); recording host callbacks. Fake time
   mounted outside `runAsync`, IO inside; bounded pumps, no `pumpAndSettle`;
   schedule a frame after post-frame callbacks. Prove one fixture on (a)
   first. `test/support/merged_detail_fixture.dart` covers the compact host.
5. **Characterization tests** under
   `test/features/episodes_panel/presentation/legacy_episodes_panel/`,
   written against (a), frozen in (b), each first passing in a detached
   worktree of (b). Every new guard gets an ORIGINAL-only mutation negative.

   | Contract | Coverage |
   | --- | --- |
   | 1 Surface | Source guard on the verbatim widget, view, enum, State header and both public methods; the re-export resolves both types. |
   | 2 Handoffs | Recording callbacks with exact order and selection fields: tap and quick-play with and without `onPlayEpisode`/`onQuickPlay`; a non-canonical video id; fallback search from the unavailable panel; `onSelectSource` awaited; `onNextEpisodeChanged(mutation:)` and `onSeriesCompletedChanged` emissions. Existing: `episode_simkl_menu`, `merged_detail_playback`. |
   | 3 Inbound | `refreshWatchProgress` through a `GlobalKey<EpisodesPanelState>` re-reads progress; the MDBList revision waits while a route covers the panel, then 750 ms, one refresh; a newer bump supersedes (fake time); after unmount, no publication. Source guard on the State method's signature. |
   | 4 Lifecycle | Policy and scope notifications before unmount re-present once, after unmount publish nothing (behaviour only, since the callback bumps its generation before `mounted`); detachment is checker-evidenced (contract 4 negatives). Source guards on `initState`, the 10-step `dispose` and the absence of `didUpdateWidget`; all five debug labels; existing `merged_detail_focus` (`'catalog-ep-season'`). |
   | 5 Watched | Exact requests per case (host + path + body): Trakt `POST https://api.trakt.tv/sync/history` / `/sync/history/remove`; Simkl `POST https://api.simkl.com/sync/history` / `/sync/history/remove`, plus on a successful watch `GET /sync/playback/episodes` and, with a paused fixture, `DELETE /sync/playback/{id}`; MDBList `POST https://api.mdblist.com/sync/watched` / `/sync/watched/remove`. Cases: all selected and signed in (watch and unwatch); none selected (local only, both directions, zero tracker writes); selected but signed out after mount (cached-vs-fresh mismatch: no request, snackbar still names it, FNF 3); Simkl failure ("— failed on Simkl", local stands, tick per `rendersHere`); a policy whose rendered source wasn't written (no tick); native id (MDBList written); custom id (local only). Local completion asserted in storage for watch **and** unwatch. **Profiles:** A with tokens, B without: B's action writes only B's local store and sends no request; A's store and B's are disjoint; a same-session scope republish re-presents metadata but does not re-resolve auth. Existing: `merged_detail_episode_watched`, `custom_series_progress`. |
   | 6 Loads | Landing tiers 1–4 and pair validation; direct-source landing (>= 95 → next); progress policy matrix (smart/local/trakt/simkl/mdblist) with the floors; MDBList ratings; unavailable panel (Retry, Search for sources, absent for direct source); StateError snackbar; a stale retry rejected by generation; `_groupVideosIntoSeasons`, `_downsizeMetahubThumb`; metadata re-present with a mid-present scope change rejected (existing `metadata_episode_focus`). |
   | 7 Identity | In-place progress/rating maps keep their instance across a watched action; the direct loader's map is the same object. |
   | 8 Season options | Hold-OK vs short-OK; custom and native provider disabling; retry state; mark → refresh; busy reentrancy. |
   | 9 D-pad | **New Classic `EpisodesScreen` widget test** (no test drives it today): back-button keys, dropdown keys, select-source button keys, Retry autofocus on TV, `EpisodeTile` list, Trakt `onMenuAction` rate gate and `onTrackerOptions` gate, terminal dispatch popping to the host before `onItemSelected`. Compact row keys including a null `onLeft`; `_stepSeason` refocus; sheet autofocus. |
   | 10 Rendering | Goldens below; existing `detail_layouts_dpad`, `detail_showcase`, `detail_showcase_compact`, `detail_theme_layout` (view-only). |

6. **Goldens** (none exist). Deterministic scenes from (b): Classic
   `EpisodesScreen` phone 390×844; Classic TV 1920×1080 with focus on the
   first episode; compact panel at 900 wide; the unavailable panel; the
   episode options sheet on TV. All: addon meta served by `MockClient`, no
   network art (null thumbnails or 404), TVMaze 404, DPR 1.0,
   `AppThemes.legacy`, `en-US`, text scale 1.0, named initial focus, bounded
   pumps past the first-frame unavailable state (FNF 10). macOS captured in
   (b) by execution; **Linux captured by Claude** in the calibrated
   `debrify-flutter:3.44.8` linux/amd64 image, committed separately; the
   Linux test is non-strict through step 5 and strict from step 6.
7. **CI list.** Add `test/episode_simkl_menu_test.dart`,
   `test/metadata_episode_focus_test.dart`,
   `test/detail_showcase_compact_test.dart` (observed passing at HEAD) and
   every new test and golden test to `ci_behavior_tests.txt`. Add to
   `ci_behavior_known_failures.txt` only failures `base` actually observes in
   newly listed files, by identity, under `# 2026-10-04 episodes_panel step
   0: pre-existing, newly exposed by CI coverage; observed in
   episodes_panel/base` (none expected).
8. **Source-text inventory.**
   - **Shape:** 7 bare radii (1764, 1944, 1966, 2689, 2885, 2898, 2953;
     7 after formatting), 0 `app.shape.` calls; not listed today. From step
     1 register **the facade and every destination**, zero-count files
     included, in `kExtractedShapeResidue` (never `kShapeResidue`, whose
     "swept" test needs a token call), ratcheted so the slice totals 7 at
     every checkpoint and the facade ends at 0. The 488-over-133 floor is
     unaffected.
   - **Theme:** `theme_surface_manifest.txt:22` (`p2_classic_details`)
     gains explicit per-directory patterns (`…/episodes_panel/models/*.dart`,
     `…/application/*.dart`, `…/presentation/*.dart`,
     `…/presentation/legacy_episodes_panel/*.dart`); `**` is not expanded.
     Measure before and after (238 sites). `theme_rendered_set.py:62` keeps
     the facade as a route boundary; prove the rendered set unchanged.
     `light_ink_inventory.py` is not extended (the panel isn't listed).
   - **Guards are unconditional:** the source reader
     (`test/support/episodes_panel_source.dart`: facade plus feature files,
     manifest renames reversed, whitespace and one optional comma tolerated
     only) reads every registered location and fails on a missing file; it
     never skips. Verify unaffected: `profile_source_guard_test`,
     `stale_runtime_guard_test`, `theme/source_guard_test`,
     `storage_member_map.tsv`, the merged checker and source contracts.
   - **`checks.yml` (step 7):** add the facade to the format (45) and
     analyze (52) lists and `test/support/episodes_panel_*` to the format
     list, **inserting before `| tee analyze.txt`, never after it**.
9. **Linux capture script** (`dev/tool/capture_episodes_panel_linux_goldens.sh`,
   `set -euo pipefail`): resolves (b) and R by **exact subject** without an
   early-exiting reader on a pipe (no `git log … | awk '… { print; exit }'`,
   which SIGPIPEs `git log` under `pipefail`; capture the full output into a
   variable, then match), fails unless `<b>:lib`, `pubspec.yaml` and
   `pubspec.lock` hash-equal R's, uses only (b)'s tests, and writes hashes
   and revision evidence.

**Step 0b review** (before extraction). ORIGINAL-only mutations on (b) must
each be rejected: `onBeforeTerminalDispatch` after dispatch; `onQuickPlay`
ignored; a missing local unwatch write path (coordinator call dropped); the
optimistic tick unconditional; the MDBList 750 ms wait removed; the route
wait removed; a removed `playbackRevision` removal; a changed season debug
label; native ids allowed in season options; Right on a compact row
playing. Record `base3` after tests at (b); each comparison passes with
only added, passing identities.

### Per step and gates

The merged procedure, with `--baseline <R>` and `--relocate
lib/widgets/episodes_panel.dart=lib/features/episodes_panel/`. Every step:
every integrated manifest plus this one with self-tests and the isolated
parser; per-symbol relocation comparison (zero additions); architecture,
sizes (lowering the facade ratchet; breakdown from step 3), storage
references; shape (7) and theme (238); CI format and scoped analyze; LF
manifests; staged diff; compile-only check of the 22 importers. Evidence
snapshots (`git stash create`) are serialized. Gates run on committed trees
with no untracked inputs against the latest `episodes_panel/` base; gate 2
also against gate 1. Known flaky identities (Xtream 50k timeout under CPU
load; PIN-recovery fixed wait) are rerun with no other Flutter work before
attribution. Never `--record` a regression.

### Integration (Claude)

Claude merges the branch and integrates shared files **semantically, by
union**: `check_search_architecture.py`, `check_settings_moves.py` and the
shared source reader (only opt-in config keys), `shape_manifest_test.dart`,
`theme_surface_manifest.txt`, `ci_behavior_tests.txt`,
`ci_behavior_known_failures.txt`, `checks.yml`, `file_size_baseline.txt`.
Union and dedupe registrations, CI paths, failure identities, theme
patterns and shape entries; keep every `*_COMPLETE`; take the lowest
verified size ceiling; keep every `checks.yml` path before `| tee`. Then on
the merged committed tree rerun every manifest with self-tests,
architecture, size, shape, theme, CI format/analyze and a full-suite
comparison against each branch's bases.

## Definition of done

1. Facade formatted, within its measured cap (≤ 450), breakdown recorded;
   `EpisodesPanel` byte-identical; the State with verbatim lifecycle,
   `refreshWatchProgress`, `consumeFocusIntent`, forwarders and
   composition; re-export in place; all 22 importers compile unchanged.
2. Guard: feature, exact bridge, facade in `main()` and
   `COMPOSITION_ROOTS`, cap, `TEMP(episodes_panel)`, facade back-import,
   playback-symbol and cross-feature bans, each proven through the real
   checker; every destination ≤ 500.
3. All manifests (including merged) pass with self-tests; every
   characterization test and guard from (b) passes unchanged; macOS and
   Linux goldens match the originals.
4. No new diagnostics or suppressions; 0 warnings; strict infos trace to
   the original (curly) with the 18 ordering infos gone.
5. Local CI-equivalent checks pass; the CI list holds the three
   newly listed and all new tests; the shape slice totals 7 with 0 in the
   facade; the theme surface is unchanged; the size baseline entry is gone.
6. Progress records commits ((a), R, (b), each step), ownership, the cap
   arithmetic, exceptions with exits, and **pending device verification**:
   Android TV D-pad and hold-OK on season options, Classic chrome on TV,
   real tracker accounts for watched writes and season marks, the
   post-playback MDBList refresh, remote CI.
7. Gate 2 passes; stop and report.

## Explicitly not in scope

`WatchedActionCoordinator`, `SeasonWatchedService`, tracker services,
`StremioService`, storage; `EpisodeTile`, `SeasonActionRegion`,
`lib/widgets/detail/*`, `EpisodesScreen`, the merged host and its checker
config; the player, launcher and source pipeline; Riverpod, data contracts,
localization, a TV-capability adapter; bug fixes and behaviour changes,
including everything below.

## Progress

(empty)

## Found, not fixed

All pre-existing; the extraction keeps each exactly.

1. The panel's class doc (44–53) is the enum's dartdoc; `EpisodesPanel` has none.
2. Stale comments: 742–746 and 771–777 (conditional local write; merged FNF
   20), 420–426 ("two sources … all three"), 703 ("local + Trakt").
3. `_watchedSyncTargets` uses initState-cached auth; the coordinator uses fresh
   auth, so the snackbar and `rendersHere` can disagree with the writes.
4. Display names double as failure identities (localization hazard);
   `'this device'` can never be reported failed; a throwing local write
   escapes a `VoidCallback` tap with no snackbar.
5. An in-flight progress load can overwrite the optimistic tick.
6. Overlapping `refreshWatchProgress` calls are last-writer-wins.
7. `consumeFocusIntent()` has zero callers; `_focusIntent` is never reset.
8. `_buildSlimSeasonRow` is dormant; the Classic chrome path had no widget test.
9. No `didUpdateWidget`: changes to `show`, `addon`, loaders or `showChrome`
   are ignored; the dropdown key handler is fixed at init.
10. The first frame renders the "Couldn't load episodes" panel (Retry
    autofocuses on TV) until the first load `setState`.
11. `_enterEpisodeMode` is `void async`; progress and `_resolve*Auth` futures
    are discarded without `unawaited`/catch; the policy loads twice per entry.
12. Published state mutated in place (`rating`, `thumbnailUrl`, progress and
    rating maps); ratings assigned outside `setState`; the direct loader's
    map stored by reference.
13. Episode FocusNodes are disposed before the rebuild that detaches them.
14. `_loadSelectedEpisodeMetadata` presents `widget.show`, not `_selectedShow`.
15. Silent swallows at 1622 and 2305.
16. Season options disable Trakt and MDBList for native ids; the episode
    paths accept them.
17. The MDBList progress overlay has no 5 % floor, unlike Trakt and Simkl.
18. One `DiagnosticLog` event plus one `debugPrint` per episode per refresh.
19. `scopeSeriesProgress` and `recordEpisodeInventory` run without
    `canContinue`/`canCommit`; `setEpisodeWatched` captures no profile owner
    (mitigated by the `ProfileGate` rekey).
20. Direct `PlatformUtil.isTelevision` reads ignore `widget.isTelevision`.
21. The back button's focus change rebuilds the whole panel; `ModalRoute.of`
    is read from async code.
22. ~35 hardcoded English strings; compact rows have no `Semantics`.
23. Two field pairs are declared mid-class (1563–1564, 2226–2227).
24. `_resolve*Auth` calls `setState` with no visible change for custom ids.
