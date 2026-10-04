# Episodes panel refactor — plan

Written 2026-10-04 on `refactor/codebase` at `10ceef60`. Follow
[AGENTS.md](../../AGENTS.md).
Revised 2026-10-04 at `8a527a4e` after Codex design review round 1 (format
proof driver, models DTO allowance, watched/rating fixtures, identity
evidence, full-suite gates, goldens, declaration count and live reads).

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

`lib/widgets/episodes_panel.dart` is 3,112 lines: 40 imports (unordered), 9
top-level declarations, 1 enum and 8 classes counting both private States
(`EpisodeFocusIntent`, `EpisodesPanelView`, `EpisodesPanel`,
`EpisodesPanelState`, `_CatalogSelectSourceButton`,
`_CatalogSelectSourceButtonState`, `_SeasonStepButton`, `_CompactEpisodeRow`,
`_CompactEpisodeRowState`), no functions, typedefs or `part`s. It is the episode drill-down engine and UI: season fetch and
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
  `TraktEpisode`; an import-free DTO file), and nothing UI. That one
  service-path import is an explicit, file-scoped guard allowance (see
  Guard rules), not a layer-wide exemption. The contiguous `///` block
  44–53 (the panel's class doc that is today the enum's dartdoc, FNF 1) moves **with
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
     is added. Widget replacement therefore does not restart initialization,
     while builds read the current `showChrome`/`contentBuilder` and an
     explicit refresh or Retry reads the current loaders (FNF 9). Both
     halves are preserved: the deps getters stay live reads of the current
     `widget` (never snapshots taken at construction or init), and the
     dropdown `onKeyEvent` assignment stays inside `initState`, decided once
     by the init-time `showChrome`.
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
   `SeasonWatchedRetryState` per State. `EpisodesPanelView` exposes neither
   map (only `progressOf`/`isNext` closures), so the evidence is split:
   **checker-evidenced** (owner field declarations, initializers, every
   assignment and in-place mutation site, compared verbatim with receiver
   path) for the map instances, `_episodeMdblistRatings = result.data!`
   (584), `_episodeSeasons` and `_seasonRetries`; **executable** for what a
   test can observe without a seam: the direct loader's returned map, held
   by the test, is mutated by the panel's own optimistic tick (watched
   action, 816–820) and a test-side mutation of it shows up through
   `progressOf` after the next rebuild; a rating's effect shows in the
   reopened options sheet. No accessor is added; if step 0 review requires
   direct identity assertions, a read-only accessor is frozen as a named
   seam checkpoint before (b) with its measured facade line cost recorded.
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
  import outside the bridge (and none in `application/`), **except exactly
  one config-scoped allowance**: `lib/features/episodes_panel/models/episodes_panel_view.dart`
  may import `lib/services/trakt/trakt_episode_model.dart` (an
  `EPISODES_PANEL_MODEL_IMPORTS` map keyed by that importer and that
  target, in the style of `PRESENTATION_BRIDGE_IMPORTS`, not a layer or
  prefix rule; the generic models rules, no UI and no Riverpod, still apply),
  and every other `episodes_panel` file outside the bridge, including other
  `models/` files, keeps the ban; checker fixtures: **positive** (that model
  file with that import passes) and **negatives** (that model file importing
  a real service, e.g. `lib/services/trakt/trakt_service.dart`; a second
  `models/` file importing `trakt_episode_model.dart`; the DTO import from
  `application/`) each rejected; bans in both
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
     lines in 34 `diff -U0` hunks. **The proof is a panel-specific driver,
     `dev/tool/episodes_panel_format_proof.py`**:
     `merged_detail_format_proof.py` cannot verify this file (it hardcodes
     `lib/screens/merged_series_detail_screen.dart`, merged's comment and
     `0xFF0B0B0E` negatives, insertion-only opcodes and exactly 25 commas,
     and derives its adapter from its own filename). The new driver reuses
     the existing AST adapter `dev/tool/merged_detail_format_proof.dart.txt`
     **by explicit path** (compiled to
     `<parser-package dir>/episodes_panel_format_proof.dill`), unchanged;
     merged's driver and its invocation are not edited. (Alternative only if
     review prefers it: a parameterized shared driver, provided merged's
     existing command line and output stay byte-identical, proven by
     rerunning it.) Arguments: `--original` (revision; source path fixed to
     `lib/widgets/episodes_panel.dart`), `--formatted`, `--parser-package`,
     `--output`. It aligns the two files **through their mandatory-token streams**
     (round-2 review: the inherited `SequenceMatcher` walk mis-aligns one
     optional comma that the formatter moves across a closing parenthesis
     near `_publishSeriesCompletion`, producing a spurious `)` insert/delete
     pair). Procedure: remove AST-identified optional trailing commas from
     **each side's own** site set; the remaining mandatory scanner-token
     streams (comments and literals included) must be **exactly equal**,
     else fail. Each removed optional comma is then anchored to the index
     of the mandatory token it follows; formatted-side anchors absent on
     the original side are insertions (each at a formatted-side AST site),
     original-side anchors absent on the formatted side are removals (each
     at an original-side site, the collapsed collections). A comma whose
     anchor shifts counts as one removal plus one insertion and is listed
     as a relocation. No other difference is accepted.
     Expectations: exactly **38 inserted and 4 removed** (37/3 plus the one
     relocation, listed separately), each listed by line, AST node and
     owner. Negatives with this file's own text (each must
     occur exactly once, asserted before replacing): the dartdoc comment
     `The episode drill-down engine + UI` edited; a trailing comment
     appended; the literal `'catalog-ep-season'` edited; a non-optional
     comma; the required singleton-record comma pair; plus a synthetic
     deleted non-comma token. The output records the negative results and
     both counts; `dart format --set-exit-if-changed` idempotence. No format-induced diagnostic is predicted; the step 0
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
   `mounted` and generation guard stays in position. A getter that returned
   the init-time value would still pass first-mount tests, so the same-key
   replacement case (coverage 4) is the executable guard on the typed
   getter wiring.
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
   (`suite_evidence.py run` with **no suite paths**, whole-repo analyzer,
   tree and SDK provenance, Flutter 3.44.8 / Dart 3.12.2, `--no-pub`);
   `base-fmt` after (a), equal by identity. Since `8a527a4e`,
   `suite_evidence.py` records runner flags under `flags` and only real
   paths under `paths`, and `compare` treats a run as scoped only when it
   has real paths; Progress shows each base's and gate's env file with
   `"paths": []` and `"flags": ["--no-pub"]`. **Negative (step 0, recorded):**
   a synthetic copy of `base`'s `.jsonl` with one original suite's events
   removed, paired with a full-run env (`paths: []`), must **FAIL**
   `compare --against` `base` (missing tests), and the same copy with an
   env listing a real path must be reported as scoped; both outputs are
   kept under `refactor-evidence/episodes_panel/`.
2. **Dependency report** (`docs/refactoring/episodes-panel-deps.md`): every
   leaf (31 fields, 6 getters, methods, 9 top-level declarations (1 enum +
   8 classes, both private States counted), comment fragments)
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
   **all three trackers reset in setup and again in teardown**
   (`TraktService`, `SimklService` and `MdblistService`
   `.instance.resetProfileScope()`, exactly as
   `merged_detail_fixture.dart:370–386` does, teardown in `finally`);
   tracker tokens via `TraktStorage`/`SimklStorage`/MDBList storage;
   `TrackingSourceStorage.setTrackingScrobbleTargets`; `http.runWithClient`
   + a recording `MockClient` (method, host, path, query, exact JSON body);
   `MaterialApp` + `AppThemeScope(AppThemes.legacy)` +
   `Scaffold`; `PlatformUtil.debugSetAndroidTvCached` reset in teardown;
   **unique addon ids per case** (`StremioService._seriesMetaCache` is
   process-wide, 15 min TTL, no reset); **TVMaze reset:** the existing public
   `TVMazeService.clearCache()` (clears `_cache`, `_seriesIdCache`, the
   availability timestamp and the persistent `TVMazeCacheService` cache) runs
   in every case's setup and teardown, inside the mocked environment after
   profile/preferences initialization, so no availability or lookup state
   carries between cases; unique IMDb/native identities per case are kept
   as well. For any other IMDb/native-id resolution cache the step 0 deps
   report finds, the report lists the reset used or the uniqueness rule
   (services are not touched to add one). **TVMaze routing:**
   `GET /shows/1` → 200 (the availability probe; a blanket 404 would set the
   static `_isAvailable = false` for 5 minutes and skip the lookup), then
   `GET /lookup/shows?imdb=<unique id>` → 404. TVMaze expectations are
   **per case/scene**: a case that performs thumbnail enrichment asserts the
   probe and lookup requests in the log, so a cached or "unavailable"
   short-circuit fails instead of passing silently; a case in which no
   thumbnail prefetch was launched **and** subsequent enrichment was skipped
   (e.g. the specified unavailable fixture: failing addon meta, prefetch
   disabled, failing Trakt fallback) asserts **zero** TVMaze requests. An
   empty-season case whose Trakt stub addon starts prefetch before the
   seasons await (1168) is not covered by that rule and pins its own log.
   Recording host callbacks. Fake time
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
   | 4 Lifecycle | Policy and scope notifications before unmount re-present once, after unmount publish nothing (behaviour only, since the callback bumps its generation before `mounted`); detachment is checker-evidenced (contract 4 negatives). Source guards on `initState`, the 10-step `dispose` and the absence of `didUpdateWidget`; all five debug labels; existing `merged_detail_focus` (`'catalog-ep-season'`). **Same-key replacement** (FNF 9): mount with `showChrome: false`, then pump replacements under the same `GlobalKey<EpisodesPanelState>`: (i) `showChrome: true`, a different `show` and a new `watchProgressLoader`; (ii) additionally a recording `contentBuilder`. Assert the same State instance throughout; no re-initialization (no new season/meta request for the new `show`, no auth re-resolve); after (i) the Classic filters bar renders (current `showChrome`) but the season dropdown has **no** custom `onKeyEvent` (Up is not trapped, decided at init); `refreshWatchProgress()` calls the **new** loader and not the old one; after (ii) the recording builder receives the view (current `contentBuilder`). |
   | 5 Watched | Exact requests per case (method + host + path + query + **complete JSON body**, every key compared, never a subset): Trakt `POST https://api.trakt.tv/sync/history` / `/sync/history/remove`; Simkl `POST https://api.simkl.com/sync/history` / `/sync/history/remove`, plus on a successful watch `GET /sync/playback/episodes` and, with a paused fixture, `DELETE /sync/playback/{id}`; MDBList `POST https://api.mdblist.com/sync/watched` / `/sync/watched/remove`. Time-valued fields are validated, not ignored: MDBList's `watched_at` (`DateTime.now().toUtc().toIso8601String()`, `mdblist_service.dart:1161`, `timestampField: 'watched_at'` at 1298) must parse as UTC (`Z`) and lie within `[before, after]` captured around the action; the body is then compared exactly with that one value substituted. **Simkl playback GET:** the cache is account-wide with a 30 s real-clock TTL (`simkl_service.dart:87–104`) and the mount's progress load may warm it, so each case asserting the GET first establishes a cold cache (preferred: the log shows no `/sync/playback/episodes` before the action under the case's policy; otherwise `SimklService.instance.resetProfileScope()` after mount, recording that the case's auth outcome is unchanged) and asserts exactly one GET after the action. Cases: all selected and signed in (watch and unwatch); none selected (local only, both directions, zero tracker writes); selected but signed out after mount (cached-vs-fresh mismatch: no request, snackbar still names it, FNF 3); Simkl failure ("— failed on Simkl", local stands, tick per `rendersHere`); a policy whose rendered source wasn't written (no tick); native id (MDBList written; a unique native id per case, since native-id resolution may be cached); custom id (local only). Local completion asserted in storage for watch **and** unwatch. **Profiles:** A with tokens, B without: B's action writes only B's local store and sends no request; A's store and B's are disjoint; a same-session scope republish re-presents metadata but does not re-resolve auth. Existing: `merged_detail_episode_watched`, `custom_series_progress`. |
   | 5b MDBList rating | Original-code characterization of `_onEpisodeMdblistMenuAction` (888–940) through the options sheet (2540–2558): **rate cancelled** (dialog dismissed → `rating == null`, 906–907: no request, no snackbar, reopened sheet still offers "Rate on MDBList"); **rate succeeds** (`POST https://api.mdblist.com/sync/ratings`, complete body with `rating` and UTC `rated_at` validated in the action window as above; snackbar "Rated N/10 on MDBList", success colour; reopened sheet offers "Remove MDBList rating (N/10)", 917); **rate fails** (non-2xx: "Failed: Rated N/10 on MDBList", failure colour, reopened sheet still offers "Rate on MDBList"); **remove succeeds** (`POST /sync/ratings/remove`, complete body; "Removed rating from MDBList"; reopened sheet offers "Rate on MDBList", 928) and **remove fails** ("Failed: Removed rating from MDBList"; reopened sheet still offers removal). Unique identities per case. |
   | 6 Loads | Landing tiers 1–4 and pair validation; direct-source landing (>= 95 → next); progress policy matrix (smart/local/trakt/simkl/mdblist) with the floors; MDBList ratings; unavailable panel (Retry, Search for sources, absent for direct source); StateError snackbar; a stale retry rejected by generation; `_groupVideosIntoSeasons`, `_downsizeMetahubThumb`; metadata re-present with a mid-present scope change rejected (existing `metadata_episode_focus`). |
   | 7 Identity | Executable: with a direct `watchProgressLoader` returning a test-held map, a watched action's optimistic tick appears **in that map** (stored by reference, mutated in place), and a test-side mutation of it is visible through `progressOf` after the next rebuild; ratings are observed only through 5b's reopened sheet. Checker-evidenced (not a test claim): the map instances, `result.data!` adoption, `_episodeSeasons` growable `[]`, one `_seasonRetries` per State, `rating`/`thumbnailUrl` mutation sites. |
   | 8 Season options | Hold-OK vs short-OK; custom and native provider disabling; retry state; mark → refresh; busy reentrancy. |
   | 9 D-pad | **New Classic `EpisodesScreen` widget test** (no test drives it today): back-button keys, dropdown keys, select-source button keys, Retry autofocus on TV, `EpisodeTile` list, Trakt `onMenuAction` rate gate and `onTrackerOptions` gate, terminal dispatch popping to the host before `onItemSelected`. Compact row keys including a null `onLeft`; `_stepSeason` refocus; sheet autofocus. |
   | 10 Rendering | Goldens below; existing `detail_layouts_dpad`, `detail_showcase`, `detail_showcase_compact`, `detail_theme_layout` (view-only). |

6. **Goldens** (none exist). Deterministic scenes from (b), each with
   both dimensions, an exact focus target and a capture-readiness predicate
   recorded in the test and in Progress:

   | Scene | Size (logical, DPR 1.0) | Focus target at capture | Ready when |
   | --- | --- | --- | --- |
   | Classic `EpisodesScreen`, phone | 390×844 | none: asserted that no `catalog-ep-*` / `catalog-select-source-btn` node has primary focus | first episode title found; request log equals the scene's expected set |
   | Classic, TV | 1920×1080 | `'catalog-ep-0'` (landing = first episode, no progress) | as above, plus `primaryFocus.debugLabel == 'catalog-ep-0'` |
   | Compact panel (merged host width) | 900×1200 | none (non-TV), asserted as for phone | season header and first compact row found; request log as expected |
   | Unavailable panel, TV | 1920×1080 | `'catalog-ep-retry'` (TV autofocus) | "Couldn't load episodes" found **after** the failed load (the fixture's addon meta returns an error and the log shows it), not the first-frame placeholder (FNF 10) |
   | Episode options sheet, TV | 1920×1080 | the sheet's "Play" tile (`autofocus: widget.isTelevision`, 2501); asserted as `primaryFocus`'s widget containing the "Play" text | sheet route present and its autofocus settled; request log as expected |

   All: addon meta served by `MockClient`; **no network art at all**:
   episode `thumbnail` and show `poster`/`background` null in the meta, so
   neither the thumbnail nor the `showImageUrl` poster fallback (2820,
   `show.poster` at 2105/2186/2418) yields a URL; the readiness check
   asserts no `CachedNetworkImage` in the tree has a non-null `imageUrl` and
   no image host appears in the log. TVMaze as in the harness (`clearCache()` in setup and
   teardown; `/shows/1` 200, `/lookup/shows?imdb=<unique id per scene>` 404).
   Per-scene TVMaze expectation: the classic phone/TV, compact and options
   scenes assert the probe and lookup in the log; the **unavailable** scene
   asserts **zero** TVMaze requests (its empty-season branch returns before
   thumbnail enrichment). Its fixture fails the addon meta **and** makes the
   public Trakt fallback explicitly return an error/empty result (mocked
   route asserted in the log), so the unavailable state is reached
   deterministically. `AppThemes.legacy`, `en-US`,
   text scale 1.0, a fixed bounded pump count per scene (recorded). **Repeatability
   before extraction:** each scene is captured twice from (b) in separate
   `flutter test` processes and in reversed scene order; the two captures
   must be byte-identical (macOS by execution in (b); Linux in the image),
   and Progress records the hashes. macOS captured in (b) by execution;
   **Linux captured by Claude** in the calibrated
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
label; a successful MDBList rating not recorded (917 dropped, so the
reopened sheet still offers "Rate on MDBList"); native ids allowed in season options; Right on a compact row
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
also against gate 1. **Gate runs are full runs**: `suite_evidence.py run
<name> --no-pub` with no suite paths (a gate whose env records any path is
invalid and is rerun, never compared as scoped), and the comparison must
show every suite of the base present. Known flaky identities (Xtream 50k timeout under CPU
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
architecture, size, shape, theme, CI format/analyze and a **full-suite**
run on the merged tree (no suite paths; env `paths: []`), compared against
each branch's bases.

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

### Step 0 — formatted ORIGINAL checkpoint

- Execution base: `81fff4bede4f244f95a96582db8e635cfa9e6e3b`, clean
  dedicated `refactor/episodes-panel` worktree. `flutter pub get` ran here
  first; the lockfile is unchanged. Flutter 3.44.8 / Dart 3.12.2.
  No branch switch, push, or changes in any other checkout. Evidence writes
  use only `refactor-evidence/episodes_panel/`. Parser/package/kernel caches
  remain in this worktree's ignored `.dart_tool/episodes_panel_parser/`.
- Untouched full suite `episodes_panel/base`: 11,093 successes, 13 failures,
  28 errors, 20 skips, on committed execution base, tree
  `143a6d533bba6ec2ee3e9687c97c3bf462d468c8`. Its env records `paths: []`,
  `flags: ["--no-pub"]`, no untracked inputs, and no tree changes. The three
  newly requested CI paths all pass; no failure entry is added.
- `missing-full.comparison.txt` rejects removal of the original
  `episode_simkl_menu_test` suite: four missing identities, FAIL. The same
  synthetic outcomes paired with a real-path scoped env pass only the
  remaining suites (`missing-scoped.comparison.txt`). No baseline is updated.
- The format proof uses the unchanged shared Dart adapter by explicit path,
  aligns mandatory token streams, and records exactly 38 inserted / 4
  removed optional commas, including the completion-publishing relocation.
  Tokens, comments and literals are equal; all six negatives are rejected.
  `format-proof.json` records each comma's AST site and original owner.
  Format idempotence passes. The observed zero-context diff has 35 hunks
  (the plan predicted 34); the mandatory-token/comma proof is authoritative.
  Whole-repo formatted analysis has zero added/removed diagnostics
  (`format-analyzer-comparison.txt`: PASS). The facade grows 3,112 to 3,232 physical lines;
  its baseline ceiling is raised by hand only for this format checkpoint.
- Whole-repo original analyzer is `base-analyze.txt`, with matching tree/SDK
  evidence. Strict detached-copy analysis qualifies relative imports only:
  original and formatted each have exactly 19 infos (18 directive ordering,
  one existing curly-braces info in `EpisodesPanelState._showSeasonOptions`),
  zero warnings/errors, zero prefer-const findings. The curly info shifts
  2306 → 2419 without changing its rule, symbol or message. No suppression
  or allowlist entry is added.
- This is the format-only application reference R; nothing has moved and no
  seam is introduced. Remaining Step 0 characterization, dependency inventory,
  checker fixtures, original proofs and golden capture precede extraction.


### Step 0 — characterization checkpoint (b)

- R is `92339749` (`style(episodes-panel): format the original episodes panel`).
  Application files remain identical to R: `lib`, `pubspec.yaml` and
  `pubspec.lock` are unchanged. No seam is needed. The exact-subject Linux
  script verifies all three Git object hashes before constructing its owned
  original checkout; it consumes the complete Git log under `pipefail`.
- `original-characterization-final`: all 76 new cases pass on ORIGINAL code,
  including complete watched/rating requests and UTC action-window timestamps,
  in-place progress-map observation, profile-local watch/unwatch isolation,
  all landing tiers and dedicated progress policies, original lifecycle and
  surfaces, same-key replacements, MDBList route/timer supersession, stale
  retries and metadata, Classic route/key dispatch, compact keys, season
  short/held OK, provider disabling, busy/retry state and five golden scenes.
  Existing callers are untouched. `step0-importers` compiles all 22 original
  importing libraries and the public State/view/enum types.
- Five macOS originals have exact size, focus and readiness assertions in
  `episodes_panel_goldens_test.dart`; `original-mac-reverse` captures them in
  a separate process in reversed order. All five PNGs are byte-identical
  (`mac-original-{first,reverse}-sha256.json`). The options scene uses the
  compact panel's actual options gesture; its sheet autofocus is Play. The
  unavailable scene pins two failed addon requests, the failed public Trakt
  fallback (`extended=episodes,full`), and zero TVMaze requests. Other scenes
  pin one addon request plus the availability probe and IMDb lookup. No image
  URL or network artwork is present. The fixture uses 20 × 50 ms bounded
  settling frames; options adds 400 ms. Linux remains non-strict only while
  originals are absent and the completed step is below 6; presence, capture
  or require-original flags make it strict without rewriting frozen tests.
- Conservative fixture decisions: MDBList's cached client resolves the current
  fixture through the live HTTP zone; all three singleton scopes reset in
  setup/teardown, TVMaze resets inside that zone, and addon/native IDs are
  unique. Simkl's complete fixed query is asserted, and Trakt playback
  fixtures include authoritative pagination headers. Local landing fixtures
  seed the persisted format through profile preferences, preserving the
  storage ownership guard. Same-session scope republishing retains the
  valid generation/epoch and tests metadata and cached auth separately.
- The 93-leaf manifest/dependency inventory owns every original declaration,
  resource, live read and comment fragment. Wiring remains pending at each
  owning step; scaffolds are empty until reviewed. Private typedef exports
  are selected by the rename/alias strict probe: exactly the original 19
  infos (18 ordering, one curly), zero warnings/errors and no new diagnostic
  identity; baseline/probe combine by maximum. Shadowed field reads in the
  throwaway probe alone are qualified so the rename cannot bind a local.
  `step0-analyzer-comparison.txt`: zero added/removed diagnostics, PASS.
- The real-config checker passes and rejects each listener removal, wrappers,
  same-class receiver swaps, distinct policy owners, disposal order, added
  hook, debug label, State refresh replacement, terminal order, quick/item
  swap, comment/const/public-byte changes and separated mid-class fields.
  Its opt-in live factory has a positive and all 23 cached-getter negatives,
  plus a missing-factory negative. Shared additions are config-scoped; each
  other manifest is checked with its own original/config (merged: `21320ff9`).
  Overlapping fixture checks use a second worktree-owned parser/kernel.
- Architecture, sizes, storage-reference fixtures, LF manifests, Dart format,
  shell syntax and staged diff checks pass. CI coverage adds the three
  requested existing suites and all nine new suites; no known-failure entry
  is added. This checkpoint freezes tests and application identity; detached
  checkpoint proofs, ORIGINAL-only mutation evidence and `base3` follow
  before any extraction. Linux originals are captured externally from this
  exact checkpoint and committed separately when delivered.


### Step 0b — strengthen original-only mutation coverage

- During ORIGINAL-only proofing, the cancel-rating mutation survived because
  the assertion ran before pending HTTP continuations drained. The cancellation
  case now uses the existing bounded fixture settling before checking zero
  requests, zero snackbar and the reopened sheet. Season busy reentrancy also
  asserts exactly one `BottomSheet`, including offstage routes, so a hidden
  duplicate cannot pass a visible-text count. No assertion is removed or weakened.
- `step0b-strengthened-original`: all 17 rating/TV cases pass against R's
  unchanged application. `lib`, `pubspec.yaml`, `pubspec.lock` still equal R.
  This supplemental original checkpoint retains (b)'s exact-subject Linux
  capture reference and five unchanged golden scenes. Detached checkpoint
  proofs and a fresh full-suite base follow before extraction.
- Supplemental checkpoint: `1f575f79`; `step0b-original-detached` passes all
  76 identities on its clean committed tree. All 57 valid ORIGINAL mutations
  are rejected, covering every one of the 76 identities
  (`original-mutation-proofs.json`, zero uncovered). Each mutant env records
  the exact tested Git tree; compiler/load failures are never accepted as
  proof. The 11 requested review mutations are included. An unrelated
  first-episode mutation cannot affect tracker landing at S2E1, so that case
  instead rejects disabling the tracker landing tier; both checks are kept.
- Both separate original macOS capture processes, first and reverse order,
  match all five committed PNG hashes (`step0b-mac-{first,reverse}-sha256.json`).
  Capture evidence uses the existing tree/SDK helpers and refreshes Git's
  cached file stats after rewriting identical PNG bytes; unsuccessful end
  snapshots are retained as incomplete attempts and are not proof.
- Fresh full `base4` on `1f575f79`, tree
  `e78dc3f0ac8553fc375c16e54a170c4751ce2b7f`: 11,169 successes, 13 failures, 28 errors, 20 skips.
  Comparison with `base3` and `base-fmt` passes: no new failures, missing
  identities or newly skipped cases; 76 added successes versus `base-fmt`.
  `base4.env.json` has `paths: []`, `flags: ["--no-pub"]`, no untracked
  inputs, unchanged tree. Both future gates use this latest original base.
  Linux originals are still pending external delivery before builder moves.

### Linux ORIGINAL delivery

- Five Linux PNGs delivered from exact checkpoint `989718fa`, with application
  hashes equal to R `92339749`. The calibrated Docker capture, reversed capture
  and strict run each pass all five scenes. First/second SHA-256 lists are equal;
  every delivered PNG matches `linux-original-sha256.txt` and its prescribed
  dimensions. `linux-original-local-verification.json` records the complete
  hashes and supplied local Docker provenance (2026-10-04T15:47:42Z).
- Originals are committed separately from extraction. Presence enables the
  frozen Linux comparison immediately; `completed_step >= 6` requires every
  original even if a PNG is missing. No golden or application code is updated.
  Their asynchronous arrival invalidated `step1-behavior`'s untracked-input
  snapshot; that attempt is retained and will be replayed after staging.

### Step 1 — models and policies

- Moved the enum's original doc block and the complete view class, re-exported
  from the unchanged facade path. Both pure static helpers move with their
  comments; every caller qualifies only the helper's owner. The widget class
  remains byte-identical; no production host or service changes.
- Architecture registration is unconditional: exact DTO allowance, bridge,
  both-direction named detail-feature bans, playback symbols, destination cap
  and staged TEMP rejection. Real tree-copy fixtures pass positives and reject
  service/UI/DI imports, missing facade, caps, facade back-imports, temporary
  calls, source/player symbols and each cross-import in both directions.
  Completion-only facade checks are exercised in the copy before step 7.
- Shape registration includes the facade and both destinations (zero included);
  slice remains 7. Four explicit theme directory patterns preserve 238 sites
  and the `EpisodesScreen` rendered boundary (171 lines, one site, no white
  lines or Theme.of). No recursive glob is introduced.
- Strict evidence traces one original curly info and zero additions/warnings;
  all 18 import-ordering infos disappear through sorted imports. Whole-repo
  final relocation comparison adds/removes zero diagnostics. The first whole
  analysis duplicated the detached original's package context; the completed
  proof checkout was removed and the clean replay is authoritative.
- Temporary facade exception: `lib/widgets/episodes_panel.dart`, 3,142 lines.
  Leading state/resources exit at step 3; engine/actions at steps 4–5;
  rendering at step 6. The facade ratchet is lowered by hand. Destinations
  are 102 lines (model) and 15 lines (policies), each below 500.
  Wiring inventory is reviewed for every step-1 entry before completion.
- `step1-behavior-final` versus `base4`: PASS, 180 successes and the same
  pre-existing profile raw-preferences source-guard failure, zero missing
  identities/new skips; compile-only importer check adds one success. Its env
  has no untracked inputs or tree changes. CI format checks 1,707 files with
  zero changes; scoped analyze retains the same 12 allowed warnings and no
  stale/new warning. Architecture, sizes, storage references and LF/diff pass.
  All 93 own leaves/self-tests and every other manifest/self-test pass with
  its own config/original (merged: `21320ff9`) and isolated parser/kernel.

### Step 2 — private widgets

- Step 1: `3b20807c`; verified Linux originals: `908edb00` (separate commit).
  Five complete original widget/State declarations move into three files.
  Names, constructors, defaults, keys, focus labels, callback forms and every
  body/comment stay exact. All original call sites use their public typedefs.
- Conservative lint decision: the step-0 single-library alias probe did not
  exercise cross-library optional-parameter accounting. The actual split
  exposes five `unused_element_parameter` warnings. The original-only split
  probe copies all five declaration bodies byte-for-byte from R, imports the
  aliases into the original rename-only engine, and proves the plan's fallback:
  two constant constructor tear-off exports expose the SourceButton and
  CompactRow constructors without invoking them. The season stepper needs no
  extra export. `original-cross-library-export-proof.json` proves body identity;
  `rename-alias-cross-library-strict-verified.txt` has one original curly info,
  zero warnings/errors/new identities. Failed probes are retained, not accepted.
- The five exact alias/export scaffolds are reviewed then pinned; changed
  constructor-target negatives are added to the real configuration fixtures.
  Redundant imports are removed rather than suppressed. Widget bodies receive
  no new const invocation or optional key. The per-entry checklist is reviewed.
- Temporary facade: 2,637 lines, remaining state/engine/actions/rendering with
  the same step 3–6 exits. All six actual source locations (facade included)
  are registered in the source reader and shape manifest; slice remains 7.
  Theme directory registration and the facade route boundary remain unchanged.
- Own 93-leaf checker and all manifest self-tests PASS, each with its own
  original/config and a distinct worktree-owned parser/kernel for overlapping
  processes. Merged remains at `21320ff9`. Scoped behavior versus `base4`
  PASS: 180 successes, the same one pre-existing profile source-guard failure,
  no missing/newly skipped cases; all 22 importers compile. Whole analyzer
  relocation has zero additions/removals; strict trace has the one original
  curly info and zero additions/warnings. CI format: 1,710 files, zero changes;
  CI allowlist: same 12 warnings, no stale/new entry. Architecture/tree-copy
  negatives, file sizes, storage references, LF and staged diff pass.
  Destinations: SourceButton 138, season stepper 46, compact row 345 lines.
  Theme remains 238; panel rendered metric remains 165 sites, 50 white lines,
  four Theme.of calls; EpisodesScreen remains the same route boundary.

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
9. No `didUpdateWidget`: replacing the widget (same State) does not
   restart initialization (no `_enterEpisodeMode` re-entry, no auth
   re-resolve, no listener change), so a new `show`, `addon` or initial
   season/episode is not loaded by itself. But reads stay live: every
   `build` reads the current `showChrome` (2162) and `contentBuilder` (2147,
   and `_custom`, 327), and an explicit `refreshWatchProgress()` or Retry
   reads the current `watchProgressLoader`/`seasonsLoader` (437, 714, 966;
   Retry also the current `initialSeason`/`initialEpisode`, 2201–2205). Only the dropdown `onKeyEvent` handler is fixed at init (389–391).
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
