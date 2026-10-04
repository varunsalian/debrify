# Merged detail screen refactor — plan

Written 2026-10-04 on `refactor/codebase` at `a92c08b8`. Follow [AGENTS.md](../../AGENTS.md).
Revised 2026-10-04 after Codex design review round 1.
Read `docs/refactoring/pikpak-files-plan.md`, `debrid-downloads-plan.md` and
`torbox-downloads-plan.md` first, including their Progress sections, and
`iptv-settings-plan.md` for the parallel-worktree conventions. This plan reuses
their technique, checker, tooling, staging and gate procedure (callback-identity
checks with wrapper and receiver-swap negatives, tree-recording evidence,
real-config fixtures, original-code worktree proofs and mutation negatives, the
wiring checklist, Linux goldens captured from the original code in the
calibrated local Docker image, `analyzer_allowlist.txt`) and only states what
differs.

Execution runs in its own git worktree on a branch cut from `refactor/codebase`
(other refactors run in parallel); Claude integrates it and captures the Linux
originals. Commit after every step; never push. Remote CI is pending until
Claude pushes, so local CI-equivalent checks are required at every step. Gate
commits contain `gate`.

## Goal

`lib/screens/merged_series_detail_screen.dart` is 5,532 lines (73 imports, 34
classes, no top-level functions, no `part` files): the merged detail page for
**series and movies**: the shell (ambient still, trailer backdrop and
foreground, back, `PopScope`); the 11-style dispatch over one `DetailModel`;
the Classic body (movie column, two-pane, stacked); the primary action, its
launch guard and the resume arbitration with the hosted `EpisodesPanel`;
tracker pills, sheets and menus; My Watchlist, bound sources, IMDb enrichment,
parents guide, recommendations, accent; and 22 private widget classes.

Split it into a new feature, `lib/features/merged_detail/`, **moving code
verbatim**. The widget tree, keys, focus nodes, build order and the State's
lifecycle are unchanged.

**Why a new feature named `merged_detail`, and why the facade stays.** The
screen renders movies too; `merged_detail` matches the existing play-guard test
and mockup names and avoids `lib/widgets/detail/` and Home's `home_detail_*`. The public
`MergedDetailScreen` stays at `lib/screens/merged_series_detail_screen.dart`
because `lib/features/home/presentation/home_detail_presentation.dart:7` imports
it, and `check_search_architecture.py` forbids cross-feature imports outside
`<other>/models/`; a `lib/screens/` import is legal. Xtream
(`lib/screens/iptv/xtream_series_detail.dart:11`) and 9 test files also import
the facade path.

**Architectural status:** a bounded legacy-extraction stage. Temporary
exceptions and exit milestones:
- **State-driven sections instead of Riverpod.** Exit: merged-detail
  presentation state (resume pill, tracker statuses, trailer, watchlist) in
  Riverpod notifiers keyed by profile and route instance, in a later change.
- **A `legacy_merged_detail/` bridge calling services, storage and the
  launcher directly** (about 30 `lib/services/` modules,
  `VideoPlayerLauncher.push`, `WatchlistStorage`, `SeriesSourceService`,
  `QuickPlayStorage`, `AmbientTrailerStorage`). Exit: detail data contracts
  (metadata/trailer, watchlist, bound sources, completion) and a named
  trailer-playback presentation bridge, after which the folder dissolves.
- **Direct `PlatformUtil.isTelevision` reads** (2064, 3567, 3836). Exit: a
  TV-capability adapter. **Unchanged legacy text.** Exit: the app-wide
  localization migration.
- **Seven duplicated `_focused` boilerplates.** Exit: a shared focusable
  primitive under `lib/ui/core/` once reuse is demonstrated.

## Public surface

```dart
class MergedDetailScreen extends StatefulWidget {
  final StremioMeta item; final StremioAddon addon; final bool isTelevision;
  /* ... 36 more fields with doc comments, ending in watchProgressLoader */
  const MergedDetailScreen({super.key, required this.item, required this.addon,
    required this.onResume, this.initialSeason, this.initialEpisode,
    /* ... 33 more, ending */ this.seasonsLoader, this.onPlayEpisode,
    this.watchProgressLoader});
}
```

The 40-parameter constructor (`super.key` plus 39), the 39 fields with their
types and doc comments (88–196), the **field order, which differs from the
parameter order**, the stale class doc (77–86) and `createState` stay
byte-identical in the facade (the step 0 manifest holds the verbatim text). It
is the only public symbol. `onResume` and `onBrowsePrimaryEpisodeSources` keep
the `({bool started, int season, int episode})?` promise signature.

- **Production callers (2), unchanged:** `buildHomeDetail`
  (`home_detail_presentation.dart:66–117`, flag-gated) and
  `xtream_series_detail.dart:278–302` (ungated, `onResume: (_) =>
  resumeAndPlay()` ignoring the promise on purpose).
- **Tests that construct it (5):** `merged_detail_play_guard`,
  `metadata_native_detail_explore`, `metadata_recommendation_baseline`,
  `metadata_source_management_baseline`, `simkl_status_toggle_sheet`.
- **Tests that read public fields (4):**
  `test/features/home/presentation/home_detail_presentation_test.dart`,
  `home_detail_route_screen_test.dart`,
  `test/features/home/home_layout_dpad_smoke_test.dart`,
  and `test/search_title_suggestions_test.dart` (not the same-named file under
  `test/features/search/`).

## What it contains (line numbers at `a92c08b8`, unchanged since `72dcf3bf`; after the step 0 format commit the manifest is authoritative)

| Lines | Area | Notes |
| --- | --- | --- |
| 1–75 | 73 imports | Unordered (`dart:async` at 16). |
| 77–243 | `MergedDetailScreen` | Stays in the facade. |
| 245–3460 | `_MergedDetailScreenState with RouteAware, MetadataPresentationMixin` | 57 fields: 53 instance (2 of them `late final`) plus 4 static const; 30 instance getters, 3 static methods. |
| 247–521 | Fields, palette statics, `_openMetadataRecommendation` (263–266) between fields, `late final _style` (365), getter `_theme` (386), `late final _focusCoordinator` (417), `originalMetadata`, `_item`, menu getters | |
| 523–543, 720–772, 1114–1129 | `initState`, `didChangeDependencies`, `didPopNext`, `_onPlaybackReturned`, `_refreshAfterPlayback`, `dispose` | **Stay verbatim in the State.** |
| 545–718 | `_guardPlay`, `_primaryEpisodePromise`, `_playPrimary`, `_rewatchTitle` (620), `_browsePrimarySources` (643), quick/direct play, `_loadShowcaseOpeningData` | |
| 774–1112 | Watchlist, tracker status loads, local movie finished, `_loadResumeInfo` (101 lines), engine target, labels, accent | |
| 1131–1500 | Enriched meta, trailer pipeline, the launcher site (1407), explore, `onMetadataPolicyChanged`, IMDb enrichment, parents guide, recommendations | |
| 1502–1971 | Layout getters, `build` (241), the interleaved doc comment (1769–1791) around `_boundSources`/`_loadBoundSources`, `_buildDetailModel` (147), `_bodySpec`, `_themedBody` | |
| 1975–3459 | `_buildBody` switch, Classic/two-pane/stacked bodies, pane key handlers, info pane, hero, meta bar, action row, descriptions, menus, episodes panel, side rail | |
| 3462–5532 | 22 private widget classes, from `_StaggerReveal` to `_AmbientStill` | `_PrimaryButton` and `_SourcePill` reach `_MergedDetailScreenState._gold`; `_QuickActionsMenu` and `_TraktSheet` reach `._descriptionFor`; `_SimklSheet` reaches `._descriptionForSimkl`. |

No member exceeds 500 lines (largest: `build` 241, `_TraktSheetState.build`
~200, `_sideRailSections` 173).

## Contracts that must not change

1. **Public surface** as above; both production callers and all 9 importing
   tests compile unchanged.
2. **Flag and routing.** `merged_series_page_enabled` is per-profile, defaults
   on, and has no production setter. Home's async read (`home_rows_navigation.dart:63,
   230–235`; awaited only for the pending deep link at 207) and the choice at
   open time (`home_item_actions.dart:94`) stay outside the move. Xtream ignores
   the flag. `_style` is forced to `'classic'` when `seasonsLoader != null`.
   The move touches no gate.
3. **Lifecycle** (super chain State → `MetadataPresentationMixin` → `RouteAware`
   → `State`).
   - `initState` (524–543): `super.initState()` first (the mixin adds its
     `MetadataPreferencesService.revision` and `ProfileRuntime.scope`
     listeners, then unawaited `_resolveMetadata()`); the tracking-source,
     movie-finished and MDBList-watched listeners; `screenView('series_detail')`;
     `addPlaybackReturnListener`; one post-frame callback (`mounted` check,
     then nine loaders in order, futures discarded).
   - `didChangeDependencies` (721–725) subscribes **the State itself** to
     `appRouteObserver` for a `PageRoute`; `didPopNext` and the RouteAware mixin
     stay on that State.
   - `dispose` (1115–1129), **13 steps**: the three listener removals in add
     order; `appRouteObserver.unsubscribe(this)`;
     `removePlaybackReturnListener`; three scroll controllers; four focus nodes
     and scopes; `super.dispose()` last (the mixin cancels its timers, bumps its
     generation and removes its two listeners).
   - **Callback identity:** the four listener callbacks
     (`_onMovieProgressPolicyChanged`, `_loadLocalMovieFinished` on two
     notifiers, `_onPlaybackReturned`) are added and removed with the same
     receiver and member; `this` is the route-observer subscriber.
   - **The two `late final`s** (`_style` 365, `_focusCoordinator` 417) stay on
     the State, initializers at their declarations, initialized lazily at
     their first build-path read; composition never reads them. Both mixins
     stay; `originalMetadata` and `onMetadataPolicyChanged` stay State
     overrides (the latter may become an exact forwarder).
4. **Playback handoffs.**
   - The single direct launcher call, `_playSelectedTrailer`'s
     `VideoPlayerLauncher.push(context, VideoPlayerLaunchArgs(videoUrl:,
     audioUrl:, fallbackUrl:, title: '${_item.name} — Trailer', viewMode:
     PlaylistViewMode.sorted), isTrailer: true)` (1407–1418) with its comment,
     the choice dialog (1328–1340), the in-place promote (1347–1350) and the
     always-re-resolve rule, verbatim.
   - Every host-callback handoff verbatim: `_guardPlay` (545–565, the one
     launch gate); `_playPrimary` (Rewatch branch, else
     `widget.onResume(promised)`); the promise rule (570–597);
     `_browsePrimarySourcesAsync` (unguarded; packs sheet,
     `onTraktAction(searchPacks)`, `openEpisode`); quick and direct play;
     `onItemSelected` after `_popToHost()` (`popUntil` by
     `kCatalogDetailRouteName`); the `DetailModel` and action-row callbacks.
     No player, launcher or `EpisodesPanel` code changes.
5. **Append-only sources (indirect).** The contract lives in
   `SeriesSourceFetcher.mergeSources` (`series_source_fetcher.dart:288–301`) and
   the player code (`android_tv_native_launch.dart`, `source_sheet.dart`,
   `video_player_screen.dart`); this file has no fetcher or source list. The
   move must forward the host callbacks and the `_buildEpisodesPanel`
   arguments (3050–3105: their order, `widget.item` not `_item`,
   `showQuickPlay: true`, `showChrome: false`, `compact: true`, the
   `onFocusLeftEdge` condition, `onBack`, the pass-throughs and both change
   callbacks) byte-identically, and must not import or construct a fetcher.
6. **Resume arbitration.** `_loadResumeInfo`, `_onNextEpisodeChanged`,
   `_applyEngineTarget` and the labels (880–1091) verbatim: the 12 s timeout,
   the stash and settle (`_pendingEngineTarget`, `_resumeLoaderInFlight`), the
   `_hasMergedEpisodeTarget` latch, mutation write-through, started-loader
   discard, and all 11 `[SeriesResume]` logs.
7. **Metadata, trailer and profile.** `_trailerGeneration`,
   `_detailsMetadataGeneration`, `_movieCompletionGeneration` and the mixin
   generations, with their `ProfileRuntime.scope` and
   `MetadataPreferencesService.revision` captures, stay **exactly where they
   are**; the missing guards (see Found, not fixed) are neither added nor
   removed. `onMetadataPolicyChanged` (1436–1448) keeps its reset set and order;
   it doesn't reset parents guide, `_enriched`, resume, trackers, watchlist,
   bound sources or accent. The 25 s safety net stays uncancelled.
8. **Trackers and destructive actions.**
   - Rewatch (`_rewatchTitle`, 620–641): `if (restart == null) return;`
     before `await resetProgressForRewatch`, no `widget.onResume`, the
     `onConfirmed` `setState`, `refreshWatchProgress`, then on success
     `++_movieCompletionGeneration`, the S1E1 reset and `await restart()`.
   - Sheets: Trakt/Simkl removals pop first, then act; `_run` publishes via
     `onChanged` before its own `mounted` check; Simkl's active-status row
     calls `removeFromList`; MDBList awaits its reload, then pops; the four
     clear-progress actions call `_refreshAfterPlayback()`; rating strips fall
     back to `onAction(rate)`.
   - **Episode watched fan-out** (`EpisodesPanel._setEpisodeWatchedEverywhere`,
     `episodes_panel.dart:778`, with `_watchedSyncTargets` at 747 naming the
     targets for the row subtitle and snackbar): the action delegates to
     `WatchedActionCoordinator.setEpisodeWatched`
     (`watched_action_coordinator.dart:174`), which **always** writes local
     completion, marking on watch (183) and unmarking on unwatch (190), then
     invalidates the local snapshot (197); custom series IDs stop there (199).
     Remote writes go to Trakt, Simkl and MDBList (IMDb or native IDs only)
     only when the content's tracking policy selects that source
     (`scrobbleTargets`, or `forceTargets`) **and** the service reports
     `isAuthenticated()`, not on mere connection; Simkl watch also deletes
     episode playback. Each failed target is reported; the panel moves the
     tick only when a succeeded target is one the guide renders, shows
     "Marked as … — failed on …", and the OR-union re-merges on the next
     load. The panel's own comments ("on watch only when it is the sole
     store") don't describe this (Found, not fixed, 20). Coordinator and panel stay
     untouched; the panel receives identical arguments (contract 5).
9. **Watchlist and bound sources.** The optimistic toggle with haptic,
   snackbar and rollback; `_myWatchlistItem` using the presented `_item`;
   `_loadBoundSources` keyed by `_item.imdbId` and reloaded from three paths;
   writes and counts through `widget.item` only.
10. **D-pad and focus.** The 4 owned nodes and their debug labels
    (`merged-left-entry`, `merged-info-pane`, `merged-episodes-pane`,
    `merged-back`); the two-pane scopes and key handlers (with `KeyRepeatEvent`);
    the action-row ordering and RIGHT crossing only when `!_isMovie && _wide`;
    the rail edge traps and caps (12 cast, 10 recommendations); `_ScrollAnchor`
    alignments; the autofocus rules; `TvHoldOk` on `_PrimaryButton`;
    `ExcludeFocus` during trailer foreground and the post-frame re-anchor; the
    three `PlatformUtil.isTelevision` sites; `_StaggerReveal` keys.
11. **Layouts and themes.** `_style` resolved once; `_theme` stays a getter;
    `AppThemeScope.of(context)` in `build`; the `_buildBody` switch, the
    `DetailThemeScope/DetailAtmosphere/DetailHoldHint` wrapping and
    `_bodySpec`; `_wide = isTelevision || width >= 900`; the `DetailModel`
    constructor call (1793–1937) with every field verbatim.
12. **Collection identity.** `_recommendationOriginals` stays
    `Map.identity()` with positional batch mapping; `_recommendations` keeps
    `null` (never loaded) versus growable `[]`; `_boundSources = const []`;
    `_trailerCandidates` growable; the GlobalKeys `_backdropKey` and
    `_episodesPanelKey` keep one instance per State.

## Destination layout

`lib/features/merged_detail/`:
- **`application/`:** `_simklStatusLabel` (a pure `String` mapping) only; the
  descriptions use `TraktItemMenuAction` from `lib/widgets/trakt/`.
- **`presentation/`, outside the bridge:** the palette
  (`merged_detail_palette.dart`: `_bg`, `_gold`, `_imdb`, `_glass2`, `_hair`
  as manifest-listed public names), the Trakt action descriptions
  (`merged_detail_action_descriptions.dart`: `_descriptionFor` only, whose
  `TraktItemMenuAction` comes from `lib/widgets/trakt/trakt_menu_helpers.dart`),
  and whole private widget classes with no service or storage import, each
  moved with its State.
- **`presentation/legacy_merged_detail/`:** the bridge (exact path in the
  guard): `_descriptionForSimkl` in its own bridge file
  (`merged_detail_simkl_descriptions.dart`), because its
  `SimklItemMenuAction` is declared in
  `lib/services/simkl/simkl_menu_helpers.dart:18` and the service-import ban
  (`check_search_architecture.py:448`) exempts only files under a
  `LEGACY_PLAYBACK_BRIDGES` prefix, not files that merely sit beside one;
  state owners, every section that takes a `BuildContext`, reads
  `widget`, or calls services, storage or the launcher; widget classes that
  import services (likely `_TraktSheet`, `_SimklSheet`, `_RecCard`,
  `_AmbientStill`; the report decides).
- **The facade** keeps the public widget, the State with both mixins, its
  verbatim lifecycle, the two `late final`s, overrides, forwarders and
  composition. Its cap is **450 lines** (the verbatim public widget alone is
  167) with `TEMP(merged_detail)` rejection, both active at step 7.
- **Guard rules** (step 1) in `check_search_architecture.py`: add
  `"merged_detail"` to `FEATURES`; `MERGED_DETAIL_FACADE`,
  `MERGED_DETAIL_BRIDGE`, `MERGED_DETAIL_COMPLETE = False`; add the bridge to
  `LEGACY_PLAYBACK_BRIDGES`; no back-import of the facade from
  `lib/features/merged_detail/`; no import of `lib/features/home/` (except
  `models/`); no service, storage or launcher import outside the bridge;
  500-line destination caps from step 1.

## Technique

As in the PikPak and IPTV-settings plans, with these points:
1. **Formatted original.** CI formats `lib/features`, but the file isn't
   `dart format` clean (29 `diff -U0` hunks; 5,532 → 5,630 lines; the
   formatter also **inserts 25 optional trailing commas**, so raw token
   streams differ while comments are identical). Step 0 commits a
   **format-only** version of the original, proven equal except for
   AST-identified optional formatter commas, and records it as its own
   baseline. Every later checker
   run uses that commit as `--baseline`, so moves compare against the
   formatted original and no formatting exceptions are needed for the
   original's own drift.
2. **Whole widget classes move verbatim** with their own lifecycles
   (`_StaggerRevealState` timer/controller, `_PrimaryButtonState` `TvHoldOk`
   `late final` set in `initState`, the sheets' `late` status initializers).
3. **The State keeps RouteAware and the mixin.** Sections never subscribe to
   the route observer and never become the mixin host. Sections read
   `widget`, `context`, `mounted`, `_item`, `presentedMetadata` and the two
   `late final`s through live getters evaluated at the original sites; no
   hoisting.
4. **`_rewatchTitle` and `_browsePrimarySources` move together**, adjacent and
   in that order, in one destination file (see source-text consumers).
5. **The interleaved doc comment (1769–1791)** and the mid-field method
   (263–266) keep their exact text and relative order in their new owner; the
   manifest records each comment fragment's owner.
6. **Callback identity** (receiver path plus member, wrapper and same-class
   receiver-swap negatives) for the four listener sites, the playback-return
   pair, `this` for the route observer, and every tear-off handed to
   `EpisodesPanel`, `DetailModel` and the widget classes.
7. **No new `const`** for the 11 `prefer_const_constructors` infos the
   features config reports (original lines 2332–4709); they stay. Imports in
   new files are written sorted. The `onPopInvoked` info moves with `build`.

## Steps

| # | Work | Notes |
| --- | --- | --- |
| 0 | Baseline; format-only commit and its baseline; dependency report, manifest, checker config, accessor if needed, characterization tests and baselines, source-text inventory, CI list, Linux capture script | Nothing moves. |
| 1 | Guard registration; palette, Trakt action descriptions, `_descriptionForSimkl` (into the bridge), `_simklStatusLabel` | Shape and theme registrations begin. |
| 2 | Presentational widget classes without service imports (`_StaggerReveal`, `_FocusHalo`, `_RailEdgeTrap`, `_CastTile`, `_PrimaryButton`, `_TrailerPlayingChip`, `_GhostButton`, `_SourcePill`, `_ScrollAnchor`, `_TrackerPill`, `_RoundIconButton`, sheet rows and strips) | Contract 10. |
| 3 | `_QuickActionsMenu`, `_TraktSheet`, `_SimklSheet`, `_SimklStatusRow` and remaining classes; State and resource owners (fields, scroll controllers, focus nodes, GlobalKeys); lifecycle verbatim | Contracts 3, 8, 10, 12. |
| 4 | Playback actions (`_guardPlay` to `_playDirectEpisode`, rewatch with browse), resume arbitration, the callees of `_refreshAfterPlayback` (which itself stays verbatim in the State; step 4 wires and verifies its moved callees), tracker status loads, local movie finished, watchlist | Contracts 4, 6, 8, 9. **Full-suite gate 1.** |
| 5 | Metadata and trailer pipeline (enriched meta, trailer, launcher site, explore, `onMetadataPolicyChanged` body, IMDb, parents guide, recommendations, accent), bound sources, the four menus | Contracts 4, 7, 9, 12. |
| 6 | `build` forwarder, `_buildDetailModel`, bodies, panes, key handlers, hero, meta bar, action row, episodes panel, side rail | Contracts 5, 10, 11. Linux originals are a blocking prerequisite. |
| 7 | Final State and composition, guards, facade cap, CI. **Full-suite gate 2.** | |

### Step 0

1. **Baseline `merged/base`** on the untouched HEAD of the worktree branch:
   `suite_evidence.py run merged/base` and the whole-repo analyzer, with tree
   provenance; Flutter 3.44.8 / Dart 3.12.2.
2. **Format-only commit** (`style(merged): format the original merged detail
   screen`):
   - `dart format` on the facade only. Prove equality **except
     AST-identified optional formatter commas**: the checker's scanner-token
     comparison over the whole file, after removing only commas the AST marks
     as optional trailing commas in argument, parameter and collection lists
     (as the checker's AST `tokens()` adapter does: it removes optional
     trailing commas, including in multi-field positional records, but keeps
     the required comma of a singleton positional record), must match exactly; every comment, every literal
     and every other token is identical, and only whitespace outside literals
     otherwise differs. The proof lists all 25 removed commas by AST node and
     fails on a negative that adds a non-optional comma or edits a comment or
     literal; plus `dart format --set-exit-if-changed` idempotence. Record it
     under `refactor-evidence/merged/format-proof.json`.
   - **The formatter breaks `rewatch_launch_routing_test`** (verified): the four
     `…Revision.addListener(_loadLocalMovieFinished)` /
     `removeListener(...)` sites wrap onto three lines **and gain a trailing
     comma**, so collapsing whitespace alone still fails all four. In the same
     commit, replace only the merged-screen `contains` checks with
     **declaration-scoped matching**: find the site inside the `initState`
     (adds) or `dispose` (removals) declaration, and match the exact notifier
     expression, operation (`addListener`/`removeListener`) and callback
     (`_loadLocalMovieFinished`), accepting any whitespace and one optional
     trailing comma before `)`. The `catalog_item_detail_screen` checks stay as
     they are; no expectation is weakened or removed. Prove it passes on both
     the original and the formatted file, and fails, for **each of the four
     sites**, on a deletion, a wrapper (`() => _loadLocalMovieFinished()`) and a
     receiver swap (the other notifier, or `_onMovieProgressPolicyChanged`),
     and on a site moved out of its declaration.
   - Raise `file_size_baseline.txt:9` by hand, 5,532 → 5,630 (a seam-only
     raise; it must shrink from step 1 and leave the over-limit list at step 7).
   - Record `merged/base-fmt` (full suite) and the analyzer: identities equal
     to `merged/base` by rule, symbol and message (line shifts only). This
     commit is the **ORIGINAL** for all later proofs, detached worktrees and
     the Linux capture.
3. **Dependency report** (`docs/refactoring/merged-detail-deps.md`): every
   leaf (fields, getters, methods, the 22 widget classes and their States, comment fragments) with its
   destination, the reads of `widget`/`context`/`mounted`/`setState`/
   mixin members, and the per-entry wiring checklist (receiver, live-getter or
   tear-off, original evaluation site) reviewed before any scaffold is pinned.
   It decides which widget classes import services, and lists the
   cross-class private references (`_gold` at 3798, 4086; `_descriptionFor` at
   4503, 5085, 5095, 5105, 5139, 5152; `_descriptionForSimkl` at 5381, 5389).
4. **Checker:** `dev/tool/merged_detail_manifest.tsv` (LF only; check the
   staged diff) and `merged_detail_checker_config.json`, with
   `merged_detail_checker_test.py` fixtures built on the **real config**.
   Negatives: a wrapped or receiver-swapped listener tear-off (each of the four
   sites and the playback-return pair); each removal deleted individually (the
   three listener removals, `removePlaybackReturnListener`, `unsubscribe`); a route-observer subscriber that isn't
   the State; a lost mixin; a `late final` turned eager or moved; the lifecycle
   reordered (first two and last two disposals swapped); `_rewatchTitle`
   separated from `_browsePrimarySources`; one `EpisodesPanel` argument
   reordered or switched from `widget.item` to `_item`; a changed launcher
   argument; a dropped comment fragment.
5. **Harness** (`test/support/merged_detail_fixture.dart`):
   `SharedPreferences.setMockInitialValues`; the root
   `flutter_test_config.dart` `ProfileRuntime` legacy init and reset;
   `DetailPageStorage.setDetailPageStyle(...)` before pump (`_style` reads the
   cache synchronously); `MaterialApp(navigatorObservers: [appRouteObserver],
   builder: AppThemeScope(...))`; `MainPageBridge.notifyPlaybackReturned`;
   `http.runWithClient` with a `MockClient` for IMDb, metadata and provider
   calls on the main isolate (not YouTube streams: see contract 4's trailer
   row); trailer autoplay off through `AmbientTrailerStorage` (or
   `disableAnimations`) so no test reaches `YoutubeService.resolveStreams`; fake host loaders and callbacks that record arguments and call
   order; `PlatformUtil.debugSetAndroidTvCached(true)` (reset in teardown) for
   TV paths. Prove one passing fixture first. Schedule a frame explicitly after
   the post-frame loaders (a post-frame callback alone requests no frame).
6. **Characterization tests**, recorded against the ORIGINAL (format commit),
   under `test/features/merged_detail/presentation/legacy_merged_detail/`.
   Apply the earlier lessons up front: real entry points, re-read state after
   acting, assert values and exact call lists, sentinel callbacks, mutation
   negatives in the original worktree for every new guard.

   | Contract | Coverage |
   | --- | --- |
   | 1 Surface | Existing `home_detail_presentation_test` and `home_detail_route_screen_test` field reads; a source guard on the verbatim constructor, field order and doc comments. |
   | 2 Flag | Existing `home_detail_route_screen_test` (flag on/off by `initialPreferences`); `xtream_series_detail_test` only parses saved Xtream identities, so it is credited for nothing here. New: an **Xtream handoff guard**, a source guard on the whole `MergedDetailScreen(...)` construction in `openXtreamSeries` (`xtream_series_detail.dart:281–302`: `kCatalogDetailRouteName` route, `showQuickPlay: true`, `onResume: (_) => resumeAndPlay()`, `resumeInfoLoader`, `seasonsLoader`, `onPlayEpisode`, `watchProgressLoader`), plus a widget test constructing the screen with Xtream's argument shape that proves `seasonsLoader` forces the Classic body under a non-classic style, the panel uses the injected loaders, and an episode tap reaches `onPlayEpisode` with the episode while `onResume` receives the promise argument is ignored (the returned Future is still awaited through `_guardPlay`). The source guard also covers the enclosing `MaterialPageRoute` and its route settings (line 280), which sit outside the constructor. |
   | 3 Lifecycle | **Reload behaviour:** each of the five notifiers (three screen, two mixin) and the playback-return list fired before unmount reloads exactly once, and fired after unmount produces no reload; this is behaviour only, not detachment evidence, because callbacks such as `_onMovieProgressPolicyChanged` return early when unmounted, and `_loadLocalMovieFinished` increments its generation and awaits `MovieCompletionService.load` before checking `mounted` at publication (860–868): it still **reads** after unmount but doesn't **publish**. Tests distinguish "no read" from "no publication". **Detachment evidence:** the checker's exact add/remove identity (same notifier expression, operation pair and member tear-off, in add order) for the three screen listeners, the playback-return pair and the route observer, with lifecycle mutation negatives that delete **each removal individually** (and each `unsubscribe`) and must fail; executable detachment is claimed only for a site with registration instrumentation (an existing listener-count or registry probe, no new production seam) whose removal-deletion mutation is shown to fail the test, and otherwise recorded as checker-evidenced; `didPopNext` refresh through a pushed and popped route on `appRouteObserver`; `_onPlaybackReturned` refreshes only when the route is current (negative: a route pushed on top); the `_refreshAfterPlayback` call order through recording loaders; the nine post-frame loaders' order; source guards on `initState`, `didChangeDependencies`, the 13-step `dispose` and both `late final` declarations. |
   | 4 Playback | Each host callback invoked with exact arguments: `onResume` with and without a promise (series with a started merged target versus movie), Rewatch routing to `onRewatch` and not `onResume`, `_guardPlay` single launch on double press (existing play-guard test plus a held future), `onBrowsePrimaryEpisodeSources` with the packs sheet both ways and with `preferSeriesPacks` off, `onTraktAction(searchPacks)`, movie `onBrowse`, quick play without a pop, `onPlayEpisode` (Xtream), `onItemSelected` after `popUntil` across two stacked merged routes. Trailer, **no new production seams**: `YoutubeService.resolveStreams` runs `_resolveStreamsBlocking` in `Isolate.run` (`youtube_service.dart:377`), outside the test zone's `MockClient`, and promotion needs `HeroTrailerBackdrop.canPromote` (`_engine != null && _videoVisible`, set only after a rendered first frame), while the merged screen doesn't pass the backdrop's `engineFactory` seam. Executable: the choice dialog listing two `MockClient`-served candidates and its cancel (nothing resolved, no snackbar). **Source-guarded and pending device verification:** the in-place promote, the stream resolve with its IMDb fallback, the "Couldn't load trailer" snackbar and the launcher call, through a source guard on the whole `_playTrailer` and `_playSelectedTrailer` bodies (the launcher has no capture hook). |
   | 5 Append-only | Through a recording `EpisodesPanel` probe: `show` is `widget.item` even when presentation differs, the forwarded callbacks are the host's own objects (`boundSourceCount`, `onSelectSource`, `seasonsLoader`, `watchProgressLoader`), `onFocusLeftEdge` null versus non-null; a source guard on the complete `_buildEpisodesPanel` body; a source guard that no `lib/features/merged_detail/` file mentions `SeriesSourceFetcher` or `mergeSources`. |
   | 6 Resume | Stash and settle, mutation write-through, latch, failed loader, started-loader discard, the 12 s timeout (fake time, mounted outside `runAsync`). |
   | 7 Metadata/profile | Profile scope change: trailer, recommendations and IMDb extra reset and reload; parents guide, resume, trackers, watchlist and bound sources not reloaded; a stale recommendation batch and a stale trailer-candidate result (served by `MockClient` on the main isolate) rejected by generation, the stream-resolve stale return being source-guarded (contract 4); recommendation tap maps a presented object to its original by identity. |
   | 8 Trackers/destructive | Existing `simkl_status_toggle_sheet_test`, `rewatch_progress_dialog_test`, `series_rewatch_test`, `tracker_menu_ownership_test`; new: rewatch confirm and cancel with the call order (reset before `onRewatch`, never `onResume`); Trakt and Simkl pop-then-act; Simkl `removeFromList`; MDBList reload then pop; each `clearWatchProgress` refresh; rate fallback to `onAction(rate)`; pill labels (Checking…, Not tracked, Status unavailable, Rated). Episode watched: existing `custom_series_progress_test` (custom ID, local write only even with forced targets) is the only direct coordinator coverage, and `episode_simkl_menu_test` only renders the "Mark as Unwatched" row without acting on it; add a hosted-panel test through the merged screen with `MockClient`: Simkl selected and authenticated, Trakt authenticated but not selected, MDBList selected but signed out; watch and unwatch each write local completion; the Simkl requests are exactly: on a successful watch, the history add plus `deletePlaybackForEpisode`'s `GET /sync/playback/episodes` and, with a matching paused-session fixture, `DELETE /sync/playback/{id}`; on unwatch, `POST /sync/history/remove`. No Trakt or MDBList **writes** (their required reads are allowed); a Simkl failure shows the failed-on snackbar while the local write stands; reopening re-merges the union. Contract 5 pins the arguments. |
   | 9 Watchlist/sources | Toggle on and off with the persisted row, rollback and error snackbar on a throwing store; bound sources reloaded at opening, on playback return and after `onManageSources`. |
   | 10 D-pad | Two-pane RIGHT/LEFT crossing and UP to back, DOWN dead stop, key repeat; action-row RIGHT crossing (series wide only) and LEFT stop; rail traps; movie autofocus on TV; trailer foreground exclusion and re-anchor are **source-guarded and pending device verification** (foreground needs promotion, which needs a rendered engine the screen gives no seam for): guards on `_exitTrailerForeground` and the exclusion wiring; existing `home_layout_dpad_smoke_test` and held-OK test. |
   | 11 Layouts | Classic movie column, two-pane (≥ 900 and TV) and stacked; each of the 11 production style branches (`classic`, `marquee`, `dossier`, `stage`, `console`, `vista`, `monolith`, `mosaic`, `halo`, `premiere`, `showcase`; switch at 1985–2070) mounts its own body type, inside `themed(...)` (`DetailThemeScope`/`DetailAtmosphere`/`DetailHoldHint`) for the ten alternates and unwrapped for Classic, with `_bodySpec`, plus an unknown stored style narrowed by `effectiveDetailPageStyle` to the default body: new original-code characterization (`metadata_source_management_baseline_test.dart:14` loops `classic` and `showcase` only, for source-action metadata, and is credited for those two); existing `detail_page_layouts`, `detail_layouts_dpad`, `detail_showcase`, `detail_theme`, `detail_theme_layout` and `hero_trailer_backdrop` tests. Pixel goldens of Classic two-pane, stacked phone, movie column, Console and Showcase on macOS and Linux (Linux by Claude in the calibrated Docker image from the ORIGINAL), with fixed metadata and no network art; trailer resolution disabled (no candidates served, autoplay off); pinned surface size, DPR 1.0, `AppThemes.legacy`, `en-US` locale and text scale 1.0, and a named initial focus (or none) per golden; **bounded pumping**: pump the post-frame loaders and their fake futures to completion, then a fixed number of fixed-duration pumps covering the opening-readiness gate and every `_StaggerReveal` delay and animation (no `pumpAndSettle`, which repeating animations defeat), asserting that the reveal controllers have completed before capture (autoplay off means the 25 s safety net is never armed). |
   | 12 Identity | Through the accessor: `_recommendationOriginals` is an identity map; `_recommendations` null before load and growable after a reset; GlobalKeys and focus nodes keep their instances across rebuilds. |

   - Reuse the 21 existing related files unchanged (except the rewatch
     declaration-scoped matching): `merged_detail_play_guard`, the three `metadata_*`
     baselines, `simkl_status_toggle_sheet`, `rewatch_launch_routing`,
     `rewatch_progress_dialog`, `series_rewatch`, `tracker_menu_ownership`, Home (`home_layout_dpad_smoke`, `home_detail_presentation`,
     `home_detail_route_screen`), `search_title_suggestions`,
     `xtream_series_detail`, the five `detail_*` and `hero_trailer_backdrop`
     tests and `theme/shape_manifest`. An unrecorded HEAD run gave 1,306 pass / 3 fail
     (the `detail_episode_cells` raw-colour scan and two
     `search_title_suggestions` cases, all in PikPak `base4`'s failure
     identities, but not in `ci_behavior_known_failures.txt`; see item 7);
     `merged/base` and `merged/base-fmt` are the recorded truth.
   - Record `merged/base2` after any seam (accessor), then `merged/base3` after
     the tests; compare each with the previous one (`PASS`, only added
     identities, all passing). Every new case first passes in the detached
     ORIGINAL worktree.
7. **CI list:** add every new test and the existing merged tests above that
   aren't listed (only `rewatch_launch_routing_test`, line 39, and
   `theme/shape_manifest_test`, line 68, are today) to
   `ci_behavior_tests.txt` as concrete paths.
   - **Newly exposed pre-existing failures.** Listing these tests exposes
     deterministic failures CI never ran, absent from
     `ci_behavior_known_failures.txt`: at least
     `test/detail_theme_test.dart::no raw colour literals survive in the themed
     files detail_episode_cells.dart` (the raw-colour scan of
     `lib/widgets/detail/detail_episode_cells.dart:327, 335, 341`), and the two
     `search_title_suggestions` cases if still observed. After `merged/base`
     is recorded, inventory **only** the failures that run actually observed in
     the newly listed files, and add those exact identities to
     `ci_behavior_known_failures.txt` in the same commit as the list change,
     under a dated comment (`# 2026-10-04 merged_detail step 0: pre-existing,
     newly exposed by CI coverage; observed in merged/base`). No assertion
     changes, no unrelated app-code fix, and nothing not observed in
     `merged/base`; every baseline comparison still rejects regressions, and a
     newly listed test passing in `merged/base` must keep passing.
8. **Source-text inventory:**
   - `test/rewatch_launch_routing_test.dart` (in CI) reads the facade for: the
     listener strings (stay in the facade's lifecycle), `generation ==
     _movieCompletionGeneration` (moves with `_loadLocalMovieFinished`), the
     substring from `Future<void> _rewatchTitle()` to `void
     _browsePrimarySources()` (`if (restart == null) return;` before `await
     resetProgressForRewatch`, no `widget.onResume`), and `widget.onRewatch ==
     null && _resolvedPrimaryLabel == 'Rewatch'` (moves with `_primaryLabel`).
     When each moves, the test's path follows it through
     `test/support/merged_detail_source.dart` (as `pikpak_files_source.dart`:
     facade plus feature files, manifest renames reversed, keeping step 0's
     declaration-scoped matching that tolerates whitespace and one optional
     trailing comma only), and additionally asserts the two rewatch markers are in the
     **same file** and adjacent. Every expectation keeps its purpose; contract
     8's executable rewatch test backs it. Never delete an assertion.
   - **Shape manifest:** 26 bare radii, 0 token calls; the original isn't
     listed. From step 1, register **the facade's remaining residue and every
     destination** in `kExtractedShapeResidue` (not `kShapeResidue`, whose
     "swept" test needs a token call), zero-budget files included, each with
     its exact measured count, and ratchet every entry to its new exact count
     at each step, so the complete slice (facade plus destinations) reconciles
     to 26 at every checkpoint. Step 1 moves radius-free helpers, so its new
     files register 0 and the facade keeps 26.
   - **Theme registry:** `theme_surface_manifest.txt:11` (`details_themed`)
     gains explicit per-directory patterns
     (`lib/features/merged_detail/application/*.dart`,
     `…/presentation/*.dart`, `…/presentation/legacy_merged_detail/*.dart`);
     the tools don't expand `**` recursively. Measure before and after.
   - `light_ink_inventory.py:68` (`PRIMARY`): add the feature directories.
   - `file_size_baseline.txt:9`: the step 0 raise, lowered as the facade
     shrinks, removed once under 800.
   - `check_search_architecture.py`: the constants and rules above.
   - `.github/workflows/checks.yml`: at step 7 add the facade to the `dart
     format` and `flutter analyze` lists (lines 45, 52), and every
     `test/support/merged_detail_*` helper to the format list.
   - `analyzer_allowlist.txt`: no entry expected (0 warnings today); add one
     only if a split exposes an original warning, traced to it.
   - Verify unaffected: `test/profiles/profile_source_guard_test.dart`,
     `isolation_suite/stale_runtime_guard_test.dart`,
     `test/theme/source_guard_test.dart`, `storage_member_map.tsv`.
9. **Linux capture script** (`dev/tool/capture_merged_detail_linux_goldens.sh`),
   resolving the characterization checkpoint by exact subject and using its own
   tests; Claude runs it in the calibrated local Docker image. The Linux golden
   test is non-strict through step 5 and strict from step 6.

### Per step and gates

As in the PikPak plan, with `--baseline <format commit>` and `--relocate
lib/screens/merged_series_detail_screen.dart=lib/features/merged_detail/`. Map
the 38 original strict infos per symbol (26 `directives_ordering`, 11
`prefer_const_constructors`, 1 `deprecated_member_use`). Run every integrated
manifest plus this one with self-tests (isolated parser cache when
concurrent), architecture, sizes, storage references, shape, theme, CI format,
scoped analyze with the allowlist, and staged diff checks. Gates run from
committed source against the latest `merged/` base; gate 2 also against
gate 1. Record the **execution base SHA** (the `refactor/codebase` commit the
worktree branch is cut from) in Progress at step 0; every proof names it.
Edits to files shared with parallel refactors (`check_search_architecture.py`,
`shape_manifest_test.dart`, `theme_surface_manifest.txt`,
`ci_behavior_tests.txt`, `ci_behavior_known_failures.txt`, `checks.yml`,
`file_size_baseline.txt`, `light_ink_inventory.py`) are kept local to this
feature's entries where possible, but they are not all append-only (the size
baseline is raised and lowered, the shape budgets ratchet, the guard gains
rules), so **Claude integrates them semantically**, not by textual merge:
union and dedupe registrations (features, bridges, CI paths, known-failure
identities, theme patterns, shape entries); preserve every `*_COMPLETE` and
other completed flag already set by any branch; merge size ceilings per path
by taking the lowest verified ceiling; then rerun, on Claude's merged and
committed tree, every integrated manifest with self-tests, the architecture,
size, shape and theme checks, CI format and analyzer with the allowlist, and
the behaviour suite compared against the latest recorded base.

## Definition of done

1. The facade is at most 450 lines, formatted, with `MergedDetailScreen`
   byte-identical and the State (mixins, verbatim lifecycle, `late final`s,
   overrides, forwarders, composition); callers and tests compile unchanged.
2. The guard registers the feature, the exact bridge (also a legacy playback
   bridge), the facade cap, `TEMP(merged_detail)` rejection and import bans.
3. All manifest runs pass with self-tests; every characterization test passes
   unchanged; the rewatch source guard reads the new locations with every
   expectation intact.
4. No new diagnostics or suppressions; the analyzer allowlist check passes;
   gate 2 passes against the latest base and gate 1.
5. Local CI-equivalent checks pass; remote CI is pending until Claude pushes.
   The test list holds the new tests; the failure allowlist gains only the
   dated, inventoried pre-existing identities observed in `merged/base` and
   newly exposed by CI coverage (step 0 item 7), nothing else.
   The facade's and destinations' registered shape budgets reconcile to 26;
   the theme surface measures the same.
6. Progress records the commits, ownership, exceptions with exit milestones,
   seams, and pending device verification (Android TV D-pad and hold-OK, the
   trailer launch, host playback handoffs from Home and Xtream, real tracker
   accounts).
7. Stop after gate 2 and report.

## Explicitly not in scope

- `EpisodesPanel`, `lib/widgets/detail/*`, `DetailModel`, the player,
  launcher and source pipelines; the flag, its storage and every Home/Xtream
  caller; `resetProgressForRewatch`, `SeriesProgressResetService`, trackers.
- Riverpod, data contracts, localization, deduplicating `_focused`, replacing
  `onPopInvoked`, adding stale-result guards.
- Bug fixes and behaviour changes, including the items below.

## Progress

**Completed:** Steps 0–7, independent-review Step 0b, separate Linux-original
checkpoint, and both full-suite gates. Latest baseline is `merged_detail/base4`;
final source Gate 2 is `a3057a82`. Earlier blocker/pending notes below are
historical checkpoints. Remaining work is device verification, remote CI and
Claude’s semantic integration on the merged committed tree.

### Step 0 — blocked at formatted-original analyzer parity

- Execution base is `def4e30423c9d8344eeb340c665afc2ee866c11f`, clean
  `refactor/merged-detail` in the dedicated merged-detail worktree. Ran
  `flutter pub get` here first; the lockfile is unchanged. Flutter 3.44.8 /
  Dart 3.12.2. No branch switch, push, or changes to another checkout.
  All evidence uses the requested `refactor-evidence/merged_detail/`
  namespace. The tool-only analyzer 14.3.0 parser and kernels are isolated
  under this worktree's `.dart_tool/merged_detail_parser/`.
- Untouched full suite `merged_detail/base` identifies committed HEAD
  `def4e304` and tree `d3c663da804069a0bc24ba39f3d2faa4fca6b6f2`:
  10,577 successes / 13 failures / 28 errors / 20 skips. No overlay,
  untracked input, or tree change during the run. Its whole-repo analyzer
  is recorded, including existing dependency-package test errors.
- Format-only checkpoint is `21320ff9264fb7b1072b7682665058982a763dec`
  (`style(merged): format the original merged detail screen`). Production
  changes are only formatter whitespace and the 25 optional commas. The
  existing rewatch test retains all expectations; only the merged listener
  sites use declaration-scoped matching, with exact notifier, operation and
  callback, arbitrary whitespace and one optional trailing comma. Catalog
  checks are unchanged. The planned size ceiling is 5,630, up from 5,532;
  no source responsibility has moved.
- `format-proof.json`: whole-file scanner tokens, comments and literals
  match after removing only AST-identified optional formatter commas.
  Every added comma is listed by AST node and owner; exactly 25. Comment,
  literal and required singleton-record comma negatives are rejected.
  `dart format --output=none --set-exit-if-changed` is idempotent for the
  screen and changed test. The reproducible proof tool is
  `dev/tool/merged_detail_format_proof.py`, requiring `--original`,
  `--formatted`, `--parser-package` and `--output`; its kernel stays beside
  the explicitly supplied parser configuration.
- All three existing rewatch identities pass on both unformatted and
  formatted production source. `format-rewatch-site-negatives-final`
  records 51 successes: the three existing cases plus original/formatted
  positives and negatives at each of the four sites. Each site rejects
  deletion, closure wrapping, notifier swap, callback swap, and movement
  outside its lifecycle declaration. The reproducing fixture is
  `dev/tool/merged_detail_format_guard_test.dart.txt`; copy it to
  `.dart_tool/merged_detail_step0/rewatch_guard_test.dart` and save the exact
  `git show def4e304:lib/screens/merged_series_detail_screen.dart` text as
  `.dart_tool/merged_detail_step0/unformatted-original.txt` before running.
- `merged_detail/base-fmt` ran on clean committed `21320ff9`. Exactly the
  same 10,577 / 13 / 28 / 20 outcomes as `base`, with every identity and
  outcome equal, no additions/missing/new skips, and stable committed trees.
  `base-fmt-comparison.txt` is PASS. These are Step 0 baselines, not gates.
- **Required analyzer parity is FAIL.** The formatter changes four existing
  one-line guarded statements into multiline statements, exposing
  `curly_braces_in_flow_control_structures` infos in
  `_openMetadataRecommendation`, `_showQuickActionsMenu`,
  `_showSimklQuickActionsMenu`, and `_showMdblistQuickActionsMenu`. This
  contradicts Step 0 item 2's required equal analyzer identities and the
  predicted 38 strict infos: original strict analysis has 38, formatted
  strict analysis has 42. No warning or error is new in this screen.
  The exact source still passes the token/comment/literal proof.
- Initial whole analyzer runs overlapped Flutter test-asset rebuilding and
  reported changing multiplicities. They remain historical evidence.
  Serial `flutter analyze --no-pub` replay, with the exact unformatted
  facade temporarily restored and then restored to the committed formatted
  bytes in `finally`, confirms 1,635 original / 1,639 formatted diagnostics:
  **exactly those four added infos and zero removals**. Each run records its
  actual tested tree; the original replay accurately records its source
  overlay. `format-analyzer-parity.json` records FAIL and the four owners.
  An intervening transient `git stash create` failure interrupted the first
  serial script after the original run; the formatted source was restored,
  and the formatted serial run was completed separately with stable tree
  evidence. No evidence was relabeled as a passing parity check.
- Conservative decision: preserve the format-only checkpoint and stop
  before dependent extraction. Adding braces would widen the format-only
  proof beyond the authorized comma/whitespace edits; suppressing or
  allowlisting the four infos would evade the required parity check. No
  such change, diagnostic acceptance, assertion weakening, `--record`, or
  `--update` was made. File-size and staged diff checks pass.
- **Pending:** completion of Step 0 (dependency report, move manifest,
  real-config checker fixtures, accessor and original-code worktree
  characterization, CI registrations, and Linux capture script/checkpoint),
  Steps 1–7, both full-suite gates, and Linux originals/strict verification.
  The facade remains 5,630 formatted physical lines. All 20 Found, not fixed
  items below remain untouched. Device-only checks, remote CI and Claude's
  eventual semantic integration remain pending; no migration parity is
  claimed.


### Step 0 — resumed; user-authorized analyzer baseline decision

- The user explicitly accepts the four format-induced infos; the previous
  stop remains historical evidence and is resolved. Do not add braces or
  suppress these infos. Every subsequent analyzer comparison uses formatted
  ORIGINAL `21320ff9264fb7b1072b7682665058982a763dec`, not the unformatted
  execution base. Strict baseline is the formatted original under destination
  lints (42 infos), combined by per-identity maximum with the unformatted
  original only for identities present there. All other additions still fail.
  Relocations must correspond by rule, original symbol and message.
- Exact accepted identities, all severity `info`, all classified
  **format-induced**, all in
  `lib/screens/merged_series_detail_screen.dart`, all with rule
  `curly_braces_in_flow_control_structures` and message
  `Statements in an if should be enclosed in a block. Try wrapping the statement in a block`:
  `_MergedDetailScreenState._openMetadataRecommendation`,
  `_MergedDetailScreenState._showQuickActionsMenu`,
  `_MergedDetailScreenState._showSimklQuickActionsMenu`, and
  `_MergedDetailScreenState._showMdblistQuickActionsMenu`.
  `merged_detail/format-induced-diagnostics.json` records each complete
  rule/file/symbol/message identity and the authorization. No warning
  allowlist entry is added; the CI warning checker already ignores infos.


### Step 0 — characterization checkpoint preparation

- Nothing has moved. The only production seam is the frozen, test-only
  `mergedDetailTestAccess` accessor (29 lines); the facade is 5,659 lines.
  Its original methods, fields, comments and public widget remain unchanged.
- The dependency report and 235-leaf LF manifest inventory every original
  responsibility and its live reads, receivers, evaluation sites and tear-offs.
  The real-config checker covers 52 callback contracts at 56 sites, including
  named arguments and interpolation. Each site independently rejects closure
  wrapping and a same-class receiver swap. Individual listener removals,
  route subscription, lifecycle order, lazy declarations, mixins, adjacent
  rewatch/browse, panel arguments, launcher flag and comment negatives pass.
- 106 characterization identities in 11 files first passed on formatted
  ORIGINAL `21320ff9`, with only the frozen accessor, fixtures and tests
  overlaid in the owned detached original-proof directory. Evidence is
  `original-characterization-final4` (104 successes) and
  `original-metadata-retention2` (22 successes; two additions, 20 overlaps).
  `original-mutations.json` records 40 rejected production mutations covering
  all 106 original-positive identities, with per-run trees, SDK, execution
  base, source hashes and JSON outcomes. Production original files were
  restored after each mutation. No regression was accepted with record/update.
- Real-entry fixtures exercise all 11 styles, forced Classic and Xtream's
  whole route/handoff, resume arbitration, lifecycle reads/publication,
  callback order, watchlist persistence/rollback, source reloads, tracker
  sheets, episode watched fan-out, retained metadata, D-pad and object identity.
  Equal-but-distinct metadata keys distinguish `Map.identity()` from a normal
  map. Configured trailer candidates/cancel and stale returns run in an
  isolated real-TMDB-config child process with a mocked main-isolate transport.
  Device-only promotion, stream isolation and trailer playback remain pending.
- Five macOS pixel originals were initially captured on original code and
  subsequently checked strictly, with bounded pumping and completed reveal
  controllers. Linux capture uses the checkpoint-owned tests and resolves
  the exact commit subject `test(merged): step 0 original-code characterization checkpoint`.
  The script checks Flutter 3.44.8 on Linux, captures once, then verifies
  strictly and writes hashes/revision evidence. Linux remains non-strict
  through Step 5 and is a blocking prerequisite before Step 6.
- `base2` preserved a 30-second Xtream large-dataset timeout while original
  proof work competed for CPU. The identical source rerun `base2-repeat`,
  without that load, has 10,577 successes / 13 failures / 28 errors / 20 skips
  and exactly matches `base-fmt`; the failed run remains evidence. Whole
  analyzer fixture declarations were corrected before freeze; no additional
  fixture infos are accepted. The strict identity comparison records the
  42-info formatted-original baseline, with a new-info negative rejected.
- CI lists all 21 existing related paths plus 11 new paths. Only the three
  newly exposed failure identities actually observed in `base` are added
  under the dated Step 0 comment. Source-text consumers, shape (26 bare
  radii, zero token calls), theme patterns, light-ink inventory, size ceiling,
  architecture and final CI lists are inventoried for their prescribed steps.
- Conservative move decisions: preserve private widget/State declarations
  and expose exact public type aliases at cross-file boundaries. This avoids
  adding constructor keys, changing runtime type names or introducing new
  key-constructor diagnostics; lint and alias mutation probes are recorded.
  `_CastTile` imports an image-cache service, so its whole class moves into
  the bridge at Step 3. The mid-field recommendation method shares the
  metadata-state owner; the interleaved bound-source field/method and model
  factory share one owner, preserving original comment order and adjacency.
  These ownership decisions are pinned in the manifest and dependency report.


- **Step 0 local verification PASS:** all seven integrated manifests
  (`vpl`, `settings`, `iptv`, `torbox`, `debrid`, `pikpak`, `merged_detail`)
  with self-tests; architecture, sizes, storage keys/references (self-tests),
  theme/light-ink inventory, full CI format scope plus facade/all new helpers,
  and staged diff checks. Evidence is `step0-*-verbatim`, `step0-architecture`,
  `step0-sizes`, `step0-storage-*`, `step0-theme`, `step0-light-ink`,
  `step0-format`, and `step0-diff`. Shape and the unaffected profile/stale
  runtime/theme source guards are also exercised by the full suite.
- `base3` is PASS against `base2-repeat`: **10,683 successes / 13 failures /
  28 errors / 20 skips**, exactly 106 added identities, all successful,
  no missing tests, new failures, fixes or new skips. The staged source tree
  was stable throughout; its env records the actual tested tree and SDK.
  The checkpoint's subsequent changes are Progress documentation only.
  This is the latest merged-detail base for Gate 1.
- Whole analyzer `step0-analyze` has exactly the formatted original's 1,639
  identities/multiplicities, with no additions or removals. Scoped analysis
  and `step0-allowlist` pass with the existing warning entries only; no
  merged-detail warning is added. `step0-strict-comparison.json` traces all
  42 strict infos to their original symbols, with zero additions. A new
  fixture-only curly info was corrected before freeze, retaining every
  assertion; `original-metadata-frozen` re-proves its four cases on original
  production code. The four accepted production infos remain unmodified.

### Step 0b — independent review closure

- Step 1 was uncommitted. Its helper moves and registrations are saved under
  this worktree's ignored `.dart_tool/merged_detail_step1_pending/`; the facade
  and tracked registrations were restored to `4b65c7cf` before this revision.
  Nothing moves in Step 0b. The only production-seam change removes the unused
  `loadTrailer` and `loadBoundSources` entries (27 lines, facade 5,657).
- P2-1: non-Xtream action fixtures explicitly default to Console and obtain
  the mounted `DetailConsole.model`. Classic's model accessor is read-only
  observation; primary/watchlist actions tap rendered labels. All alternate
  style checks read their actual mounted model. After engine emissions, tests
  paint the scheduled frame before re-reading the view's model.
- P2-2/3: hosted episode writes pin the Simkl host and complete IMDb/S1E1
  bodies; playback reads and paused-session deletion pin their host. The panel
  probe waits for visibly enriched metadata, proves original and presented
  objects differ, and compares its loaders with the exact screen fields using
  `same()`. Its Classic primary action is a real tap.
- P2-4: configured trailer children run `flutter test --dart-define=...`
  directly. Child source and reporter output live in a unique system temp
  directory and are removed in `finally`; the parent asserts only child
  outcomes. No nested suite-evidence run, SDK-version assertion, or shared
  evidence mutation remains in the test.
- P2-5 conservative original-behavior decision: successful IMDb enrichment is
  cached for the process lifetime by `ImdbEnrichmentService._cache`, with no
  reset seam. The retained-title cases now start from non-null extra, assert
  null synchronously on policy/profile notification, and await republication
  of the same cached object with exactly zero additional non-ParentsGuide
  GraphQL requests. Separate policy/profile cases start with an unsuccessful,
  uncached fetch, then require exactly one additional request, its IMDb body,
  and the rendered model's new rating. Requiring an extra network request for
  the cached title would contradict original behavior; no cache is changed.
- P3: actual keyboard dispatch covers the info pane, episodes pane, action row
  and rail trap, preserving the direct branch/result checks. A two-season
  fixture renders the real season dropdown. Tracking-source detachment is
  checker-only because its callback checks `mounted` before reading; its test
  title now claims only mounted reload and no publication after unmount. Movie
  and MDBList removal-deletion mutations must fail generation observations.
- Watchlist retention uses a recording store: its actual saved IMDb row,
  original storage key/value and exact write list survive policy/profile
  refresh; rendered watchlist/resume labels remain. SharedPreferences caches
  reads, so this is persistence/retention evidence, not a claim of instrumented
  per-read detachment. Tracker refresh uses `MainPageBridge` notification.
  The direct accessor rewatch call is documented as a defensive early-return
  probe: the no-restart branch cannot be selected by the Play UI.
- Source contracts preserve literal whitespace and distinguish interpolation
  boundaries; code formatting and optional commas remain tolerated. The
  relocated listener negative now starts the misplaced site on its own line.
  Four of nine post-frame loaders have recording host callbacks in the order
  test (`resume`, `trakt`, `simkl`, `mdblist`); the remaining five and the entire
  invocation order are pinned by the original `initState` source guard.
- The five Linux originals copied by Claude stay untracked and outside Step
  0b. Their hash/provenance verification and separate commit remain required
  before Step 6; the exact Step 0 characterization checkpoint stays `4b65c7cf`.

- Original proofs: `original-step0b-final` passes all 109 cases on the owned
  detached `21320ff9` worktree. After switching the getter to the review's
  exact `WidgetTester.widget<DetailConsole>(...).model`, its 40 affected cases
  pass again in `original-step0b-rendered-model`. `original-step0b-frozen`
  passes 43 metadata/source cases and all 48 listener-format positives and
  negatives, including the newly multiline relocation sites.
- `step0b-original-mutations.json`: all 49 guard mutations rejected, 109/109
  characterization identities exercised, zero uncovered. This is 48 original
  production mutations plus one regression mutation of the test canonicalizer.
  `step0b-named-mutation-assertions.json` verifies actual assertion failures for
  all nine appended review-specific mutations; no compilation/loading failure
  is accepted. The mounted-model primary swap is re-proved on the final getter.
  `step0b-original-production-proof.json` proves the facade's original bytes
  unchanged, with only the two removed accessor entries differing from Step 0.
- `merged_detail/base4` is the latest base: 10,686 successes, 13 failures,
  28 errors, 20 skips. Comparison with base3 passes with exactly three added
  passing identities, no new failure, missing identity, newly skipped test or
  fixed failure. The user-requested tracking-source title rename has one exact
  correspondence in `step0b-identity-correspondence.json`; the derived
  `base3-step0b-identities.json` retains every original outcome and its source
  hash/SDK/tree provenance. No failure allowance or assertion is changed.
- All seven integrated manifests with self-tests pass, as do architecture,
  sizes, storage keys/references, theme, light-ink, CI format and staged diff.
  Stable runs are reused after cleanup limited to test scaffolds; the one
  IPTV run whose tree changed during execution is rerun on the final tree.
  Whole analyzer `step0b-analyze` has exactly the formatted original's 1,639
  diagnostic identities/multiplicities, zero additions/removals. Scoped
  allowlist passes; strict comparison retains the maximum original baseline
  of 42, including all four format-induced identities, with zero additions.
  New test-support lint findings were fixed and the affected original-code
  proofs rerun; accepted production infos remain untouched.
- The full-suite tested tree is frozen; the subsequent checkpoint edit is
  this Progress report only. Proof summary: `step0b-proof-summary.json`.

### Linux originals — separate artifact checkpoint

- Claude captured the five original PNGs from `4b65c7cf` in local Docker
  `debrify-flutter:3.44.8`, linux/amd64 Ubuntu 24.04 with the official Flutter
  3.44.8 SDK and `libsqlite3-dev`, under Colima on macOS, at
  `2026-10-04T07:24:28Z`. The image was calibrated against 14 GitHub-captured
  TorBox/Debrid goldens; all 14 strict comparisons passed. GitHub Actions was
  unavailable because of its spending limit; this is local Linux evidence.
- `linux-original-{capture,strict,sha256,revision,run-url}.txt` record the
  capture and strict five-test pass. `linux-original-verification.json`
  verifies all five copied file hashes, exact revision and evidence hashes.
  No PNG is generated or updated against moved code.
- Conservative instruction precedence: the user's instruction to make Linux
  strict when the originals arrive is applied now, earlier than the plan's
  Step 6 default. The missing-file early return and opt-out are removed;
  Linux runs require the committed originals. This changes test enforcement
  only. The capture script continues resolving its checkpoint-owned tests by
  their exact Step 0 commit subject.

### Step 1 — static helpers and registrations

- Eight original static leaves move to the four manifest-selected owners:
  palette (13 lines), Trakt descriptions (58), Simkl descriptions in the
  legacy bridge (38), and pure Simkl labels in application (18). The eight
  wiring entries were checked: signatures, literals, argument order and
  evaluations remain at their original sites. All facade imports now resolve
  to the same libraries through sorted package URIs. Facade: 5,571 lines.
- Register the feature, bridge and 500-line destination cap; final 450-line
  facade enforcement remains staged for Step 7. Theme uses three explicit
  directory patterns; light-ink includes them. Shape registers the facade's
  26 radii plus all four zero-budget destinations, still totaling 26.
- The shared normalizer gains only the three inventoried original qualified
  static names (`_gold`, `_descriptionFor`, `_descriptionForSimkl`) for this
  config's exact original State receiver. Its three wrong-static-owner
  negatives reject mismatches. No generic original-State prefix is erased.
- `step1-characterization`: all 109 cases pass against the latest base4;
  no new failure, missing or skipped identity. Shape's three checks pass.
  All seven integrated manifests with self-tests, architecture, sizes,
  storage keys/references, theme, light-ink, full CI format and diff pass.
  All 235 leaves and present forwarders match the formatted original.
- Whole analyzer comparison has no additions/removals; scoped allowlist
  passes. Strict evidence traces 16 infos (the original 11 const, deprecated
  use and four format-induced identities), with zero additions to the
  maximum original baseline of 42; sorting removes 26 import-order infos.
  The first combined strict input duplicated the facade's five default infos
  by appending its normal-scope log to its strict copy. This rejected input
  is retained as `step1-strict-duplicate-input.json`; the valid combined log
  contains the strict facade and only the feature lines from scoped analysis.
  No diagnostic rule or comparison allowance changes.


### Step 2 — service-free widget classes

- Move 21 whole declarations into 15 files, keeping each private Widget/State,
  constructor, default, lifecycle and runtime type. Exact public typedefs expose
  constructors. Facade is 4,406 lines; shape remains 26 across the complete slice.
- Conservative choice: constructor tear-off exports keep original keyless private
  constructors intact. Dart's cross-library typedef calls otherwise report their
  optional parameters unused. These constant exports perform no invocation or
  initialization; their exact targets are pinned, with changed-target negatives.
  No keys, braces, const invocations or lint suppressions are added to original
  declarations. The header check selects concrete classes, and separately checks
  every typedef; a typedef is not a second widget declaration.
- All 115 focused cases pass (109 characterization plus shape and rewatch guards),
  compared to base4 with no failed, missing or newly skipped identity. All seven
  manifests with self-tests and local architecture, size, storage, theme, format
  and diff checks pass. Three integrated checks span an independent merged-only
  self-test edit; their unchanged-input reuse is recorded in
  `step2-check-reuse.json`. The merged checker includes the new negative cases.
- Allowlist passes with zero merged warnings. Strict comparison is PASS: 16 original
  infos, zero additions. Whole analyzer uses the maximum of the original whole
  analysis and original destination-lint analysis, with relocation; every slice
  diagnostic also passes the stricter rule/symbol/message comparison. Four const
  infos surface after moving widgets into destination lints and correspond to
  original members. No candidate identity participates in either baseline.


### Step 3 — remaining widgets and resource owners

- Eleven whole Widget/State declarations move into seven files. All 22 widget
  classes now retain their private runtime types and exact constructors through
  pinned typedef/constructor exports. Six cohesive resource/state owners retain
  original initializers, collection identity and GlobalKey/focus/scroll instances.
  Facade is 3,310 lines. Every destination is under 500; shape still totals 26.
- Composition constructs resources once before initState, captures no widget,
  context or lazy reads, then binds its dependency object. The original two lazy
  declarations remain in the State; the new assigned late-final parts field is
  assigned in the constructor, not initialized lazily. Short typed owner getters
  keep reads at the original sites and avoid new format-induced diagnostics.
  The original static action set has an exact constant projection, with no copy.
  `seriesDone` is the extracted name for `_seriesCompleted`, keeping its original
  one-line guard within the formatter width. No braces or allowances are added.
- The accessor follows actual owners; its original typed receiver is normalized
  only for manifest-owned members. All added construction/projection leaves are
  pinned after the per-entry wiring review. Lifecycle, mixins, subscription target,
  disposal order, lazy initializers, defaults and bodies pass all 235 leaf checks.
- Source readers now select a declaration, not mere destination-file existence;
  the rewatch test follows the complete slice with every assertion retained.
  All 40 affected cases pass first on the formatted original, whose production
  bytes remain identical (`original-step3-source-proof.json`), then on this tree.
  The literal-safe mapper skips irrelevant renames without altering mappings.
- `step3-final-characterization`: 115 PASS against base4. All seven integrated
  manifests/self-tests and architecture, size, storage, theme, format/diff pass on
  a stable tested tree. Whole/scoped/strict analyzer and allowlist comparisons
  pass, with 16 traced original infos and zero additions. The first reader run's
  two source-reader failures are preserved; neither assertion is weakened.
- Evidence snapshot creation is serialized at the beginning/end of the checker
  batch. Parallel per-command git stash-create snapshots collided at the worktree
  index; that failed launcher is preserved, and every check was rerun successfully.


### Step 4 — actions and gate 1 checkpoint

- Move playback/rewatch/browse, resume arbitration, tracking/completion and
  watchlist into four cohesive owners (187/230/174/56 lines before final qualifier
  formatting). The State retains `_refreshAfterPlayback` and wires its callees in
  the original order. Facade: 2,792 lines; complete-slice shape remains 26.
- Listener pairs share the same tracking-action instance; playback-return and route
  ownership remain the State. All host callbacks are read live and handed through
  directly. Resume timeout, latch/stash/settle, item writes, eleven logs, launch
  guard, destructive order, watchlist writes/rollback and mounted checks are exact.
- Compiler-confirmed unnecessary receiver qualifiers were removed only at those
  sites, retaining local bindings. The literal-safe source reader reverses implicit
  owner member names while preserving named labels and external qualified reads.
  Its 40 affected original-code cases pass before the moved-code run.
- All 115 focused checks pass against base4. All seven manifests/self-tests,
  architecture, sizes, storage, shape, theme, CI format and diff pass on a stable
  tree; every original leaf and callback identity remains checked. Whole/scoped
  analysis, allowlist and per-symbol strict comparison pass with zero additions.
- Gate 1 will run from this committed source against the latest merged_detail/base4,
  with other Flutter tests and parser self-tests stopped to avoid the characterized
  concurrency-sensitive Xtream 50k timeout. Gate evidence follows separately.


### Gate 1 — full suite PASS

- Source revision `26f90beaaa48275b100352b64f964ec1905d40a7`, tested tree `c04f601a1683e4af83bb638fa25ff1422389a933`; Flutter
  3.44.8 / Dart 3.12.2. `merged_detail/gate1` has 10,686 successes, 13 failures,
  28 load/test errors and 20 skips, exactly matching latest `merged_detail/base4`.
- `gate1-comparison` is PASS: no new failure/error, missing test or newly skipped
  identity. The tested tree did not change during the run. Gate evidence is recorded
  in this separate documentation commit; its difference from the tested source is
  documentation only. No baseline or assertion is updated to accept a regression.


### Step 5 — metadata, trailer, sources and menus

- Move metadata loading/policy, metadata exploration, trailer pipeline and the
  four menus to their manifest owners; recommendation opening occupies its original
  position before the recommendation fields in the metadata-state owner. Bound
  sources/loading share the model factory and retain their interleaved doc fragments.
  Facade: 2,136 lines. New owners are 34–293 lines; shape stays 26.
- The State retains its mixin override as an exact policy forwarder. The existing
  `layout_body` structural mode is enabled for its moved body only; its annotation
  remains required on the facade. Source guards reconstruct that actual annotation
  plus the actual destination body, preserving the complete original assertion.
- All generations, captured profile/revision checks, reset/load order, cache
  retention, uncancelled safety timer, trailer selection/promotion/launcher arguments,
  pop/act sequencing, source read/write identity and mounted checks remain exact.
  No service/player/panel implementation or persisted format changes.
- All 115 focused cases pass against base4; the 40 affected reader cases also pass
  on original code. All seven integrated manifests/self-tests, architecture, sizes,
  storage, shape, theme, CI format and diff pass on a stable tree. Whole/scoped/strict
  analyzer and allowlist pass with zero additions. The four accepted formatting
  infos now trace by original rule/symbol/message to metadata-state and menu owners.
- Linux originals are already verified and committed in their separate checkpoint.
  Step 6 may proceed; the current Linux rendering will also be checked locally in
  the calibrated image, without generating or updating any golden.


### Step 6 — renderer and model factory

- Move the complete build/model/body/pane/key-handler/hero/action/episode/rail
  leaves to their reviewed manifest owners. The facade is 434 formatted lines;
  all 49 feature Dart files are below 500. Public widget bytes, the two lazy fields,
  mixins, original lifecycle order and direct action tear-offs remain exact.
  Composition captures live getters and constructs inert owners once per route;
  it reads no widget, context, lazy field or service during construction.
- Per-entry wiring was reviewed before pinning: root/body rendering uses live
  presentation, panel source identity remains the host's original item, every
  host callback remains the same object, and focus/resource reads retain their
  original sites. The model factory keeps bound-source loading and its comment
  fragments in the original order. Shape budgets reconcile to exactly 26.
- The callback resolver now distinguishes named labels from member reads, while
  retaining ternary/map reads and interpolation. Real-config wrapper/receiver
  negatives and all seven integrated manifests/self-tests pass. Architecture,
  sizes, storage, theme, light-ink, format and diff pass. Whole/scoped/strict
  analyzer and warning allowlist pass, with no diagnostic additions.
- The complete source-body assertions caught reader bugs around a ternary colon,
  a spread call and comment-separated named labels. The reader now carries code
  context across comments and preserves literal text. Every assertion stays;
  all 40 affected source cases pass on unchanged original production code, and
  all 115 focused cases pass on the moved code (`step6-characterization-context`).
  The 21 related files also compare PASS to base4 (1,306 success, one failure,
  two errors; the same three observed original identities).
- Linux strict rendering passes all 18 view cases in the calibrated amd64 image
  (`step6-linux-strict`, stable archived tree). All five committed original PNG
  hashes remain unchanged. That run preceded only the source-reader correction;
  application, view-test, fixture and golden inputs are identical. The separate
  original-golden commit remains separate. No golden was generated or updated.


### Step 7 — completion guards and Gate 2 checkpoint

- Enable `MERGED_DETAIL_COMPLETE`: the facade cap is 450 lines and every
  `TEMP(merged_detail)` marker is rejected. Retain the exact legacy bridge,
  feature-to-facade/service/other-feature import bans, and every prior completed
  feature flag. Sixteen positive/negative probes verify these actual rules.
- CI format/analyzer scopes now include the facade; the format scope lists all
  four `test/support/merged_detail_*.dart` helpers explicitly. Behavior paths and
  the five exact known-failure identities retain the approved Step 0 inventory.
  No analyzer allowance or unrelated failure entry changes.
- Acceptance proof: 235 manifest entries; byte-identical public surface; 434-line
  facade; 49 feature Dart files, maximum 346 lines; unchanged Home/Xtream callers,
  profile/stale-runtime/theme source guards and storage map; all 11 characterization
  files byte-identical to the separate original-Linux checkpoint.
- All seven integrated manifest/self-test runs, architecture, size, storage,
  theme, light-ink, CI formatting and diff pass on the stable Step 7 source tree.
  Whole/scoped/strict analyzer comparisons and allowlist pass. Sixteen original
  infos remain: 11 const suggestions, one deprecated member, four accepted
  format-induced curly suggestions, traced by original rule/symbol/message.
  Only the 26 original import-order infos disappear through sorted imports.
- Shape stays 26; the registered theme surface stays 750 sites. Linux input
  parity proves all 2,080 application/dependency/config/view/fixture/golden inputs
  match the strict tested archive. No missing-golden bypass remains.
- Production State contains only retained lifecycle/mixins/lazy fields, live
  metadata overrides, exact forwarders, inert composition and the frozen accessor.
  Legacy-stage exceptions retain their named exit migrations (Riverpod route/profile
  state, data contracts/playback bridge, TV capabilities, localization, shared focus).
- The local CI behavior list and full-suite Gate 2 run next from this committed
  source, serially. Gate 2 must compare with latest `merged_detail/base4` and Gate 1;
  the following evidence commit changes documentation only. Device, remote-CI and
  Claude's semantic integration checks remain pending.


### Gate 2 — full suite PASS; execution complete

- Full-suite run from clean committed `a3057a829173471bd9afbd9de56c35a88dd62a33`,
  tree `5d9a6d80a36b137da7b82dbacacbf3fe4fbda3a5`, Flutter 3.44.8 / Dart 3.12.2:
  **10,686 successes, 13 failures, 28 errors, 20 skips**. The tree and untracked
  inputs stayed unchanged. Raw Flutter exit 1 represents the same original
  failure/error identities; both recorded comparison verdicts are PASS.
- `gate2-comparison-vs-base4` and `gate2-comparison-vs-gate1` each report no new
  failure, missing identity, added identity, newly skipped test or fixed failure.
  Gate 1 likewise matched latest base4 from committed `26f90bea`.
- Local CI checker also passes from committed `a3057a82`: 4,437 successes,
  three failures and two errors, exactly the five approved original identities.
  `step7-ci-comparison` passes against base4 with no added/missing/skipped/fixed
  identities. No failure allowance, test assertion or golden was weakened.
- Completion index: shared authorized `refactor-evidence/merged_detail/` only,
  `completion-summary.json`. It joins execution base, formatted original, latest
  base, gate source trees/SDKs and all final checker/analyzer/CI verdicts. Parser
  package/kernel artifacts remain inside this worktree’s ignored `.dart_tool`.
- Step commits: format `21320ff9`, historical blocker `fc2f72df`, original
  checkpoint `4b65c7cf`, review closure `e3a312c2`, separate Linux `2d2ce60c`,
  step 1 `fc5b23b7`, step 2 `7c778ac7`, step 3 `864c0979`, step 4/Gate 1
  `26f90bea` (evidence `70fa4ec1`), step 5 `0f92cfe2`, step 6 `66735b61`,
  step 7/Gate 2 `a3057a82`. This final evidence commit changes this plan only.
- Final facade: **434 lines**; 49 feature Dart files, maximum 346 lines;
  235 verified manifest entries; 109 unchanged characterization cases,
  49 rejected original mutations; 115 focused cases; 18 strict Linux view cases
  with all five original PNG hashes unchanged. All seven integrated manifests
  with self-tests, architecture, size, storage, shape, theme, format, analyzer
  comparison and warning allowlist pass. Sixteen original strict infos remain,
  including all four accepted format-induced identities; zero new diagnostics.
- All 22 found-not-fixed items remain preserved. Pending physical checks:
  Android TV D-pad/hold-OK, trailer promotion/foreground/launcher and isolated
  stream resolution, host playback handoffs from Home/Xtream, real tracker accounts.
  Remote CI is pending until Claude pushes (local calibrated Linux evidence is
  complete); semantic shared-file integration and all integrated checks/full-suite
  comparison on that committed tree remain Claude’s work. No branch switch or
  push was made. Stop here as instructed.


## Found, not fixed

All pre-existing; the extraction keeps each exactly.
1. Stale class doc (77–86): experimental, Search-only, series-only, `StorageService`.
2. Deprecated `onPopInvoked` (1543).
3. `_loadParentsGuide` (1467) has no generation or scope guard and isn't
   reloaded on a policy or profile change.
4. `_loadEnrichedMeta` (1131) has no generation guard (`mounted` only).
5. `_loadBoundSources` (1783) has no try/catch yet is unawaited from
   `_refreshAfterPlayback` (772); it has no `canContinue` or profile guard and
   keys by presented `_item.imdbId` while binding writes use `widget.item`.
6. `_loadResumeInfo` has no request generation; overlapping calls share
   `_resumeLoaderInFlight`, so an older answer can settle after a newer one.
7. Tracker status, watchlist and accent loads are last-writer-wins on overlap.
8. `_playSelectedTrailer`: `ImdbTrailerService.resolveTrailer` (1391–1393) is
   outside any try, so a throw can strand `_trailerLoading = true`; the stale
   return also leaves it true until `onMetadataPolicyChanged`.
9. Async tear-offs used as `VoidCallback`s (`_loadLocalMovieFinished`
   listeners, `_playTrailer` taps) drop errors.
10. The 25 s `Future.delayed` safety net isn't cancelled on dispose (guarded).
11. `++_movieCompletionGeneration` runs before the `!_isMovie` return (harmless).
12. Analytics reports `'series_detail'` for movies.
13. Three direct `PlatformUtil.isTelevision` checks in presentation.
14. All user-facing strings are hardcoded English.
15. `_myWatchlistItem` stores presented (possibly translated) metadata.
16. `showQuickPlay: false` branches are dormant (both callers pass `true`).
17. Seven duplicated `_focused` boilerplates and duplicated focus literals.
18. The `_buildDetailModel` doc comment is interleaved around `_boundSources`
    and `_loadBoundSources` (1769–1791).
19. `merged_detail_play_guard_test` relies silently on the default `'console'`
    style, so a default-style change changes which body it covers.
20. Outside this file, out of scope: `EpisodesPanel`'s `_watchedSyncTargets`
    and `_setEpisodeWatchedEverywhere` comments describe a conditional local
    write on watch that `WatchedActionCoordinator.setEpisodeWatched` doesn't
    make (it always writes local completion).

21. A failed SharedPreferences watchlist write updates the in-memory plugin
    cache before the backend rejects it. The original UI rolls back, while
    that cache can retain a ghost row; rollback tests verify the actual store
    backend and UI. Storage behavior remains untouched.
22. `_CastTile` can overflow its 92-pixel rail by two pixels for a two-line
    cast name (56-pixel image, 6-pixel gap, two text lines). Original fixtures
    use short cast names; the 12-member cap is still asserted. No layout fix.
