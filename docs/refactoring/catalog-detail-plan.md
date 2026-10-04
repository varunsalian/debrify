# Catalog detail screen refactor — plan

Written 2026-10-04 on `refactor/codebase` at `10ceef60`. Follow [AGENTS.md](../../AGENTS.md).
Revised 2026-10-04 after Codex design review round 1 (no P1s): evidence classes per
characterization case, metadata HTTP transport, per-manifest baselines, cache and
golden readiness, playback-return guard contracts, interleaved fields and listener sites.
Primary template: [merged-detail-plan.md](merged-detail-plan.md) (sibling detail
screen), including its Progress and completion review notes; also read the Progress
of [playlist-content](playlist-content-plan.md), [iptv-settings](iptv-settings-plan.md)
and [addon-hub](addon-hub-plan.md) (empty; its Found-not-fixed 21 applies). This
plan reuses their technique, checker, tooling, staging and gates, and states only
what differs.

## Execution model

- Execution runs in **its own git worktree** on branch `refactor/catalog-detail`,
  cut from `refactor/codebase`; record the **execution base SHA** in Progress at
  step 0 and name it in every proof. Run `flutter pub get` first; the lockfile
  must not change. Flutter 3.44.8 / Dart 3.12.2.
- Commit after every step; never push or switch branches. Gate commits contain
  `gate`. Remote CI is pending until Claude pushes, so local CI-equivalent checks
  run at every step.
- **Claude integrates.** Shared-file edits (architecture guard, shape test, theme
  manifest, CI lists, known failures, `checks.yml`, size baseline, light-ink,
  analyzer allowlist) stay local to this feature's entries; Claude union-merges
  them semantically (dedupe registrations, keep all nine `*_COMPLETE = True`
  flags, lowest verified size ceiling per path) and reruns every check and the
  suite on the merged committed tree. In `checks.yml` paths go **before**
  `| tee analyze.txt`, never after it.
- **Evidence** goes only to `<git-common-dir>/refactor-evidence/catalog_detail/`;
  never write to or relabel another namespace.
- **Isolation:** every manifest, format-proof and checker command passes its own
  `--parser-package` under the ignored `.dart_tool/catalog_detail_parser/` (shared
  cache collided in PikPak); original-code proofs use a detached worktree under
  `.dart_tool/catalog_detail_original/`. Serialize evidence snapshots and run gates
  without parallel Flutter load (merged's stash and Xtream-timeout lessons).

## Goal

`lib/screens/catalog_item_detail_screen.dart` is **3,500 lines** (40 imports; 26
classes: the public widget, its State, 18 private widgets, 6 private States; one
top-level const `_kNetflixRed`; no top-level functions, statics or `part`): the
non-merged detail page (hero, reveal, metadata sections, action row, tracker quick
actions, recommendations, resume/Rewatch labels, bound sources, IMDb enrichment).
Split it into **`lib/features/catalog_detail/`**, **moving code verbatim**; the
widget tree, keys, focus nodes, build order and lifecycle are unchanged.

**Name and facade.** `catalog_detail` matches the analytics id
`screenView('catalog_detail')` and `test/catalog_detail_play_hold_test.dart`; it
avoids `merged_detail`, `lib/widgets/detail/`, Home's `home_detail_*`, Search's
`catalog_search_*` and the shared route name `kCatalogDetailRouteName`
(`'catalog_item_detail'`). The public `CatalogItemDetailScreen` stays at
`lib/screens/catalog_item_detail_screen.dart` because Home
(`lib/features/home/presentation/home_detail_presentation.dart:6`) imports it and
cross-feature imports outside `<other>/models/` are banned. Do not rename the class:
`dev/tool/merged_detail_public_surface.txt` pins merged's doc, which names it.

**Playback entanglement: accepted (cleaner than merged).** No
`VideoPlayerLauncher`, engine, stream resolution, launch args, trailer, native
bridge or `PlatformUtil`. Outbound handoffs are host callbacks only; inbound
"playback ended" signals are `RouteAware.didPopNext` and
`MainPageBridge` playback-return notifications that re-read state.

**Architectural status:** a bounded legacy-extraction stage. Exceptions and exits:
- **State-driven sections instead of Riverpod.** Exit: catalog-detail presentation
  state (resume, watchlist, bound sources, metadata) in Riverpod notifiers keyed by
  profile and route instance, in a later change.
- **A `legacy_catalog_detail/` bridge** calling services and storage directly
  (`WatchlistStorage`, `SeriesSourceService`, `QuickPlayStorage`,
  `MovieCompletionService`, `MetadataDetailsService`, `ImdbParentsGuideService`,
  `DominantColorCache`, Simkl/MDBList menu helpers). Registered in
  `LEGACY_PLAYBACK_BRIDGES`. Exit: detail data contracts (metadata, watchlist,
  bound sources, completion), after which the folder dissolves.
- **Unchanged legacy text.** Exit: the app-wide localization migration.
- **Five duplicated focus/hover boilerplates.** Exit: a shared focusable primitive
  under `lib/ui/core/` once reuse is demonstrated.

## Public surface

`class CatalogItemDetailScreen extends StatefulWidget` (declared at line 49):
lines 44–148 (105 lines: the stale class doc, 21 fields with doc comments, the
`super.key` + 21-parameter constructor, `createState`) stay **byte-identical** in the facade,
pinned by `dev/tool/catalog_detail_public_surface.txt`. Field order differs from
parameter order. Required: `item`, `onPlay`, `onBrowse`. It is the only public
symbol.

- **Production callers (5), unchanged:** `buildHomeDetail`
  (`home_detail_presentation.dart:120–149`, the fullest set and the only
  `onRewatch`, `onLoaderArt` and `simklStatusLoader` caller; used when
  `merged_series_page_enabled` is off); `StremioTvScreen._pushChannelDetail`
  (`stremio_tv_screen.dart:2416–2422`, `enablePrimarySourcesHold: false`, unnamed
  `PageRouteBuilder`); `aggregated_search_results.dart:399–455`;
  `catalog_browser.dart:2042–2124` (route `kCatalogDetailRouteName`,
  `popUntil` for two Trakt leaves); `trakt_results_view.dart:671–709`.
- **Tests (5):** `catalog_detail_play_hold_test` (**not in CI**), and in CI
  `metadata_recommendation_baseline` (205), Home `home_detail_presentation` (200)
  and `home_detail_route_screen` (201), `rewatch_launch_routing` (source text, 39).
  An unrecorded HEAD run (plus shape) gave 43 pass; the recorded base is the truth.

## What it contains (line numbers at `10ceef60`; after step 0 the manifest is authoritative)

| Lines | Area | Notes |
| --- | --- | --- |
| 1–42 | 40 imports | Unordered (`dart:async` at 13; four `package:debrify/` storage imports first). |
| 44–148 | `CatalogItemDetailScreen` | Stays in the facade. |
| 150–1877 | `_CatalogItemDetailScreenState with SingleTickerProviderStateMixin, RouteAware, MetadataPresentationMixin<CatalogItemDetailScreen>` | 1,728 lines; 28 instance fields (0 static), 2 `late`, 10 getters. |
| 155–232 | Fields; `_openMetadataRecommendation` (168–171) between `_recommendations`' doc (166–167) and the field (173) | Five more fields sit between methods at four locations: `_movieCompletionGeneration` (334), `_rewatchPending`/`_rewatchBusy` (400–401), `_detailsMetadataGeneration` (543), `_artworkAccent` (661). |
| 234–271, 427–455, 638–651 | `initState`, `didChangeDependencies`, `didPopNext`, `_onPlaybackReturned`, `dispose` | **Stay verbatim in the State.** |
| 273–425 | Watchlist load/toggle, Simkl status, local movie finished, policy change, `_loadResumeInfo`, labels, `_playPrimary` (Rewatch) | `_simklStatus` (224) is write-only. |
| 457–678 | Bound state, enriched meta, loader art, `onMetadataPolicyChanged`, IMDb, parents guide, recommendations, accent | |
| 680–1025 | `build`, `_buildBody`, narrow/wide content, `_wide`/`_tight`, content columns, `_divider` | |
| 1027–1876 | Sections (`_secEyebrow` … `_secDescription`), `_scrollWideToTop`, `_buildActionRow`, `_canBrowsePrimarySources`, `_browsePrimarySources(Async)`, `_dot` | |
| 1879–3500 | 24 private classes from `_Reveal` to `_GlassIconButton`; `_kNetflixRed` (2703) | `_ActionRow` → `_PrimaryButton`, `_kNetflixRed`; `_QuickActions` → `_QuickAction`; `_SimklQuickActions` → `_SimklQuickAction`; `_Description` → `_ReadMoreToggle`. |

No member exceeds 500 lines (largest `_PrimaryButtonState.build`, 136). No style dispatch exists (no `DetailPageStorage`): merged's eleven-style contract
**does not apply**; the single Classic-like layout varies only by narrow/wide/TV.

## Contracts that must not change

1. **Public surface** as above; all 5 callers and 5 tests compile unchanged.
2. **Lifecycle.** Super chain State → `MetadataPresentationMixin` → `RouteAware` →
   `SingleTickerProviderStateMixin` → `State`; the three mixins stay on the State
   in that declared order.
   - `initState`: `super.initState()` first; the tracking-source,
     movie-finished and MDBList-watched listeners;
     `screenView('catalog_detail')`; `addPlaybackReturnListener`; `_revealCtrl`
     (1,100 ms, `vsync: this`), `value = 1.0` on TV; one post-frame callback:
     `mounted` check → `_emitLoaderArt()` → non-TV `forward()` → TV focus
     (`showQuickPlay ? _playFocus : _browseFocus`) → **nine loaders in order,
     futures discarded** (`_loadRecommendations`, `_loadEnrichedMeta`,
     `_loadArtworkAccent`, `_loadParentsGuide`, `_loadImdbEnrichment`,
     `_loadResumeInfo`, `_loadSimklStatus`, `_loadLocalMovieFinished`,
     `_loadMyWatchlistState`).
   - `didChangeDependencies` subscribes **the State itself** to
     `appRouteObserver` for a `PageRoute`. `didPopNext` and `_onPlaybackReturned`
     both run `_refreshBoundState`, `_loadResumeInfo`, `_loadLocalMovieFinished`,
     under **different guard contracts**: `didPopNext` dispatches directly (no
     `mounted` or `isCurrent` check; the observer only calls it on the subscribed,
     newly uncovered route), while only `_onPlaybackReturned` returns early unless
     `mounted` and `ModalRoute.of(context)?.isCurrent`. The playback-return listener
     receives both `MainPageBridge.notifyPlaybackReturned()` (which then also calls
     `notifyContentPlaybackStopped()`) and `notifyPlaybackDataChanged()`
     (`main_page_bridge.dart:529`, listeners only, no playback-stopped signal); the
     screen cannot tell them apart and reacts identically.
   - `dispose`, **11 steps**: three listener removals in add order;
     `appRouteObserver.unsubscribe(this)`; `removePlaybackReturnListener`;
     `_revealCtrl.dispose()` (must precede `super`, STPSM asserts); the three
     focus nodes; `_wideScroll`; `super.dispose()` last.
   - **Callback identity:** `_onMovieProgressPolicyChanged` (237/640),
     `_loadLocalMovieFinished` on two notifiers (238/641, 239/642: same member, so
     the notifier swap is the meaningful negative), `_onPlaybackReturned`
     (241/644) added and removed with the same receiver and member; `this` is the
     route-observer subscriber.
   - **The two `late`s stay on the State:** `late final _revealCtrl` (assigned in
     `initState`) and `late bool _hasBoundSource = widget.hasBoundSource` (lazy,
     first read at its original site in `_buildActionRow` or `_refreshBoundState`;
     composition never reads it). `originalMetadata` and `onMetadataPolicyChanged`
     stay State overrides (the latter may become an exact forwarder).
3. **Host callbacks, byte-identical.** Each is read live from `widget` at its
   original evaluation site and handed through as the same object:
   `widget.onPlay()` in `_playPrimary`; `restart()` = `widget.onRewatch`;
   `widget.onBrowse` passed through to `_ActionRow` (1816) and called in
   `_browsePrimarySourcesAsync`; `openEpisode()` =
   `widget.onBrowsePrimaryEpisodeSources`;
   `widget.onTraktAction?.call(TraktItemMenuAction.searchPacks)`; the tear-offs
   `widget.onTraktAction!`, `widget.onSimklAction!`, `widget.onMdblistAction!`;
   raw `widget.onRecommendationTap` to `MetadataExploreButton` (705); the loaders
   `resumeInfoLoader`, `simklStatusLoader`, `recommendationsLoader`,
   `metaEnricher`, `onLoaderArt`. Child tear-offs `_openMetadataRecommendation`,
   `_scrollWideToTop` (TV only), `_playPrimary`, `_browsePrimarySources`,
   `_toggleMyWatchlist`; closures that must stay closures (back pop, rec tap,
   description toggle, `onConfirmed`, `TvHoldOk(onTap:, onHold:)`).
4. **Resume.** `_loadResumeInfo` verbatim: the guarded `_resumePending` setState,
   `loader().timeout(const Duration(seconds: 12))`, the catch, and the `finally`
   with both mounted/unmounted branches. Labels: `_primaryLabel` (Rewatch → Play
   without `onRewatch`) and `_resolvedPrimaryLabel`'s full matrix (Play, Start
   Watching, Resume, `Resume · S{s}E{e}`, Rewatch).
5. **Rewatch.** `_playPrimary`: `_rewatchBusy` re-entrancy guard;
   `if (restart == null || _item.type == 'series' || _primaryLabel != 'Rewatch')`
   before `await resetProgressForRewatch(context, …, onConfirmed: …)`;
   `++_movieCompletionGeneration` after success; the four-field reset including
   `_simklStatus = null`; `restart()` unawaited; `finally`.
6. **Metadata and profile.** `_detailsMetadataGeneration`,
   `_movieCompletionGeneration` and the mixin generations with their
   `ProfileRuntime.scope` and `MetadataPreferencesService.revision` captures
   (`valid()`) stay exactly as they are; missing guards are neither added nor
   removed. `onMetadataPolicyChanged` keeps its reset set (`_imdbExtra`,
   `_recommendations = []`) and reload order. `_recommendationOriginals` stays
   `Map.identity()`; `_recommendations` keeps `null` versus `[]`; the eight-item
   `enrich` pre-warm stays before `valid()`.
7. **Trackers and watchlist.** Optimistic watchlist toggle, haptic, both snackbars
   and rollback; the saved item's `sourceAddon` fallback; the presented `_item`
   key. Tracker writes stay host callbacks; quick-action rows dispatch exactly
   the host's options. Bound sources keyed by `widget.item` (`_boundKey`). IMDb
   enrichment through `MetadataDetailsService.enrich(_item, loadExisting:
   ImdbEnrichmentService.fetch)`; Simkl status via the host loader only.
8. **Primary sources.** `_canBrowsePrimarySources`, the movie → `onBrowse` branch,
   `QuickPlayStorage.getQuickPlayRules(isMovie: false)`, the packs gate, the sheet,
   and the switch, verbatim.
9. **D-pad and focus.** Labels `detail-play`, `detail-browse`, `detail-watchlist`;
   TV autofocus; UP → `_scrollWideToTop` (280 ms) on TV; `TvHoldOk` on Play with
   hold → primary sources when enabled; Read-more toggle; quick-action and rec-card
   focus/hover handlers.
10. **Layouts.** `_wide` (TV, or ≥ 900 wide landscape), `_tight` (height < 620),
    narrow versus wide columns, section order, `_Reveal` stagger starts and `dy`,
    `_Backdrop(animate: !widget.isTelevision)` with the 22 s Ken Burns, the
    `ArtworkAccentScope` accent with `_kNetflixRed` fallback, the FAB.

## Destination layout

`lib/features/catalog_detail/` (the dependency report decides exact files; each
≤ 500 lines):
- **`presentation/`, outside the bridge:** whole private widget classes with no
  service or storage import, each with its State: `_Reveal`, `_Backdrop`,
  `_CertBadge`, `_GenreChip`, `_MetacriticBadge`, `_RecCard`, `_Description`,
  `_ReadMoreToggle`, `_ActionRow` with `_kNetflixRed` and `_PrimaryButton`,
  `_QuickActions`/`_QuickAction`, `_GlassCard`, `_GlassIconButton`.
- **`presentation/legacy_catalog_detail/`** (the bridge, exact path in the guard):
  widget classes importing `lib/services/` (`_CastAvatar` for `CastMember`,
  `_MdblistQuickActions`, `_SimklQuickActions`/`_SimklQuickAction`); the
  state/resource owners and actions (primary action: resume, completion, labels,
  Rewatch, Simkl status; watchlist; bound sources and primary-sources browse;
  metadata: enrichment, loader art, IMDb, parents guide, recommendations, accent);
  the renderer (body, columns, sections, action row). No `application/` or
  `data/` folder is created (nothing is pure enough to justify one).
- **`_simklStatus` rule:** the field and **both** writers (`_loadSimklStatus`,
  `_playPrimary`) stay private in **one** library, keeping the `unused_field`
  warning's identity (rule, field name, message). It is recorded in
  `analyzer_allowlist.txt` at its **destination path** in the **same commit** that
  moves it, with a dated provenance comment (PikPak `_email` precedent):
  `warning | unused_field | <destination> | The value of the field '_simklStatus'
  isn't used. Try removing the field, or using it`. No removal, no suppression.
- **The facade** keeps the public widget, the State with its three mixins, the
  verbatim lifecycle, the two `late`s, overrides, forwarders and inert
  composition. Cap **360 lines** with `TEMP(catalog_detail)` rejection, both
  enforced at completion.
- **No merging with merged detail.** No import between `catalog_detail` and
  `merged_detail` in either direction (the generic rule allows `<other>/models/`;
  neither feature may use even that). Same-named classes (`_RecCard`,
  `_PrimaryButton`, `_CastAvatar`/`_CastTile`, `_Reveal`/`_StaggerReveal`,
  `_QuickActions`/`_QuickActionsMenu`) stay independent; overlap is noted only.
- **Guard rules** (step 1) in `check_search_architecture.py`: add
  `"catalog_detail"` to `FEATURES` (line 13); `CATALOG_DETAIL_FACADE`,
  `CATALOG_DETAIL_BRIDGE`, `CATALOG_DETAIL_COMPLETE = False`; add the bridge to
  `LEGACY_PLAYBACK_BRIDGES` (lines 294–310, after `MERGED_DETAIL_BRIDGE`); no
  `lib/features/` file other than Home's existing caller imports the facade (the
  catalog feature never does); no catalog↔merged import; no service or storage
  import outside the bridge; 500-line destination cap from step 1; facade cap and
  completion `main()` scan at completion. Guards are **unconditional**: no
  file-exists skips, no flags that disable a rule before completion other than the
  staged facade cap.

## Technique

As in the merged plan, with these points:
1. **Formatted original.** `dart format` gives **3,561 lines** (18 hunks, **15
   optional trailing commas**; no radius gains one). Merged's format proof hardcodes
   its path and 25 commas, so add `dev/tool/catalog_detail_format_proof.py` (same
   arguments; merged's stays untouched). The format-only commit is the
   **ORIGINAL** for the catalog checks only: the catalog checker's `--baseline`
   and the catalog analyzer baseline. Every other integrated manifest keeps its own
   config and original baseline (for example merged_detail stays at `21320ff9`,
   `dev/tool/merged_detail_checker_config.json:13`).
2. **Format-induced info: accepted** (merged precedent, user decision). Exactly
   one: `info | curly_braces_in_flow_control_structures |
   _CatalogItemDetailScreenState._openMetadataRecommendation | Statements in an if
   should be enclosed in a block. Try wrapping the statement in a block`, recorded by
   identity in `format-induced-diagnostics.json`. **No braces, no suppression**, no
   allowlist entry (infos are ignored); it traces by rule/symbol/message.
3. **Strict-lint baseline** from the formatted original under the features config:
   15 `directives_ordering` (gone once new files have sorted imports), **4
   `prefer_const_constructors`** (`_secMeta` `Icon(` and `Color(0xFFFACC15)`,
   `_secGenres` shimmer `Wrap(`, `_MetacriticBadge.build` `TextStyle(`) that
   **stay** — no `const` changes — plus the curly info and the `unused_field`
   warning. Every addition fails; relocations correspond by rule/symbol/message.
4. **Whole widget classes move verbatim** with their lifecycles (`_BackdropState`'s
   `_ken`, `_PrimaryButtonState`'s `late final TvHoldOk _hold` and `reset()`).
   Keep private Widget/State declarations, keyless private constructors, defaults
   and runtime types; expose exact pinned typedef/constructor exports at
   cross-file boundaries (merged step 2: typedef calls otherwise report optional
   parameters unused; measure per symbol, e.g. `_Reveal.dy`, `_Backdrop.animate`,
   `_Description`, `_QuickAction.expand`).
5. **The State keeps RouteAware, the ticker and the mixin.** Owners never subscribe
   to the route observer, never become the mixin host and never create the ticker.
   Owners read `widget`, `context`, `mounted`, `_item` and `presentedMetadata`
   through live getters at the original sites; no hoisting. Composition constructs
   inert owners once per State and reads no widget, context, lazy field or service.
6. **Verbatim comments.** The checker compares comments; never reword, move or drop
   one. The `_recommendations` doc (166–167), `_openMetadataRecommendation` and the
   field keep their exact text and order in one owner; the five between-method
   fields (four locations, 400–401 holding two) stay beside their neighbours; comment-only references (`[_QuickAction]`
   2478, `_QuickAction's` 2518, `[_QuickActions]` 2981) stay verbatim.
7. **Callback identity** (receiver path plus member, wrapper and same-class
   receiver-swap negatives) for the **six screen listener operation sites** (adds
   237–239, removals 640–642: the tracking-source registration/removal of
   `_onMovieProgressPolicyChanged` at 237/640 plus the **four completion-listener
   sites** 238/239/641/642), the playback-return pair (241/644), `this` for the
   route observer, and every tear-off and host callback in contract 3. The
   mixin's own listeners (`metadata_presentation_mixin.dart:105–106, 281–282`)
   are not moved and not counted here.
8. **Shape:** 29 bare radii, 0 `app.shape.` tokens; the original is not listed.
   From step 1 register **the facade and every destination** in
   `kExtractedShapeResidue` (never `kShapeResidue`, whose swept test needs a token),
   zero-budget files included, each with its exact count, ratcheted every step so
   the slice reconciles to **29**. The 488-token floor sums `kShapeResidue` only and
   is unaffected.

## Steps

| # | Work | Notes |
| --- | --- | --- |
| 0 | Base; format-only commit with the rewatch fix; dependency report, manifest, checker config, characterization, macOS goldens, source-text inventory, CI list, Linux capture script; named checkpoint | Nothing moves; **no production seam**. |
| 0L | Linux originals (Claude), separate commit | Blocking before step 2. |
| 1 | Guard, shape, theme, light-ink registrations; leaf widgets `_Reveal`, `_CertBadge`, `_GenreChip`, `_MetacriticBadge`, `_GlassCard`, `_GlassIconButton` | Contracts 9–10. |
| 2 | Remaining widget classes: `_Backdrop`, `_RecCard`, `_Description`/`_ReadMoreToggle`, `_ActionRow` + `_kNetflixRed` + `_PrimaryButton`, `_QuickActions`/`_QuickAction`; bridge classes `_CastAvatar`, `_MdblistQuickActions`, `_SimklQuickActions`/`_SimklQuickAction` | Contracts 3, 9, 10. |
| 3 | Resource/state owners (focus nodes, `_wideScroll`, fields); primary action (resume, completion, labels, Rewatch, `_simklStatus` with both writers + allowlist entry); watchlist; bound sources and primary-sources browse | Contracts 2–5, 7, 8. **Full-suite gate 1.** |
| 4 | Metadata: enriched meta, loader art, `onMetadataPolicyChanged` body, IMDb, parents guide, recommendations (with the interleaved method), accent | Contracts 6, 7; the curly info moves here. |
| 5 | `build` forwarder, body, narrow/wide content and columns, sections, `_buildActionRow`, `_scrollWideToTop`, `_dot` | Contracts 9, 10. |
| 6 | Final State and composition, completion guards, facade cap, CI scopes. **Full-suite gate 2.** | |

### Step 0

1. **Baseline `catalog_detail/base`** on the untouched worktree HEAD:
   `suite_evidence.py run catalog_detail/base` and the whole-repo analyzer
   (`flutter analyze --no-pub`), with tree provenance.
2. **Format-only commit** (`style(catalog): format the original catalog detail
   screen`):
   - `dart format` on the screen only. Proof: whole-file scanner tokens, every
     comment and literal identical after removing only AST-identified optional
     trailing commas (exactly 15, each listed by AST node and owner; a required
     singleton-record comma kept); negatives that add a non-optional comma or edit
     a comment or literal fail; `dart format --set-exit-if-changed` idempotent.
     Record `catalog_detail/format-proof.json`.
   - **The formatter breaks `rewatch_launch_routing_test`** (verified): the four
     catalog `contains('$notifier.addListener(_loadLocalMovieFinished)')` /
     `removeListener` checks go from 1 to 0 matches (sites 238, 239, 641, 642 wrap
     and gain a trailing comma). In the same commit, replace **only those four**
     with declaration-scoped matching in a new `test/support/catalog_detail_source.dart`
     (`catalogCompletionListenerSite`, scoped to `class
     _CatalogItemDetailScreenState`, finding `initState` for adds and `dispose` for
     removals, matching the exact notifier, operation and callback with any
     whitespace and one optional trailing comma before `)`). Do not modify merged's
     helper in `test/support/merged_detail_source.dart` or the merged branch. All
     other catalog expectations survive formatting and stay as they are. Prove on
     the unformatted and formatted file: positives pass; for **each of the four
     sites**, deletion, a wrapper (`() => _loadLocalMovieFinished()`), a notifier
     swap, a callback swap (`_onMovieProgressPolicyChanged`) and a site relocated
     out of its declaration (starting on its own line) fail. Fixture as
     `dev/tool/catalog_detail_format_guard_test.dart.txt`.
   - Raise `file_size_baseline.txt:20` by hand 3,500 → 3,561 (no seam raise follows).
   - Record `base-fmt` (full suite) and the analyzer: equal to `base` by
     rule/symbol/message except the one accepted curly info.
3. **Dependency report** (`docs/refactoring/catalog-detail-deps.md`): every leaf
   (28 fields, 10 getters, methods, 24 private classes, the const, comment
   fragments) with destination, reads of `widget`/`context`/`mounted`/`setState`/
   mixin members, and the per-entry wiring checklist (receiver, live getter or
   tear-off, original evaluation site), reviewed before any scaffold is pinned.
4. **Checker:** `dev/tool/catalog_detail_manifest.tsv` (LF only; check the staged
   diff), `catalog_detail_checker_config.json`, `catalog_detail_checker_test.py`
   with **real-config** fixtures. Negatives, per site: at **each of the six screen
   listener operation sites** a wrapped tear-off, a notifier (receiver) swap and a
   callback swap (`_onMovieProgressPolicyChanged` ↔ `_loadLocalMovieFinished`; at
   the four completion sites the notifier swap is the meaningful one since they
   share a member); the same at the playback-return pair and for every contract-3
   tear-off; each add deleted individually (three listeners, playback return) and
   each removal deleted individually (three listeners including the tracking-source
   removal at 640, playback return, `unsubscribe`);
   a route subscriber that isn't the State; a lost or reordered mixin; a `late`
   turned eager or moved; lifecycle reordered (first two and last two disposals
   swapped; `_revealCtrl.dispose()` after `super`); a post-frame loader reordered;
   `_simklStatus` and one writer split; a host callback wrapped or read from
   `_item`; `_boundKey` switched to `_item`; a dropped or reworded comment.
5. **Harness** (`test/support/catalog_detail_fixture.dart`, after merged's): mock
   preferences, `ProfileRuntime` legacy init/reset, `SecretVault` and tracker scope
   resets; `http.runWithClient` + `MockClient` for the `package:http` top-level
   calls (IMDb enrichment `imdb_enrichment_service.dart:277`, parents guide
   `imdb_parents_guide_service.dart:64`). **Metadata HTTP:** `TmdbMetadataRepository`
   builds `TmdbHttpClient` (an `IOClient`) directly
   (`tmdb_metadata_repository.dart:33`), so `runWithClient` cannot intercept it, and
   the unconfigured `TmdbMetadataRepository.instance` (empty
   `TMDB_READ_ACCESS_TOKEN`) rejects requests before any transport. Add a
   catalog-owned `test/support/catalog_detail_http_transport.dart`, equivalent to
   merged's `test/support/merged_detail_http_transport.dart` (not imported or
   edited), installed with `HttpOverrides.runZoned(createHttpClient:)` to route
   `dart:io` requests into the fixture's recording `MockClient`. Construct the
   adapter, and any client it caches (its inner `http.Client()`), **inside** the
   `runWithClient` fixture zone so it resolves to the recording client. Cases that
   need TMDB success (credits, TMDB recommendations) run in a **configured child
   test**, as merged's `merged_detail_trailer_test.dart` does
   (`flutter test --dart-define=TMDB_READ_ACCESS_TOKEN=<fixture>` on a
   `dev/tool/catalog_detail_*_fixture.dart.txt` child); in-process cases assert the
   unconfigured path (no TMDB request reaches the transport);
   `MaterialApp(navigatorObservers: [appRouteObserver], builder: AppThemeScope(theme:
   AppThemes.legacy, …))`; `MainPageBridge.notifyPlaybackReturned`; recording fakes
   for every host callback and loader; deterministic artwork (null URLs or a bundled
   image via test `HttpOverrides`; no real network). TV paths use `isTelevision:
   true`; phone/wide use bounded pumps (Ken Burns and `Shimmer` repeat: **no
   `pumpAndSettle`**). Schedule a frame after the post-frame loaders; teardown pumps
   ≥ 13 s for the resume timeout.
   **Cache isolation:** `ImdbEnrichmentService` and `ImdbParentsGuideService` keep
   process-wide static `_cache` maps keyed by IMDb id (no reset hook), and
   `TmdbMetadataRepository.instance` keeps its own response cache. Each case uses a
   distinct IMDb id / TMDB identity (fixture-allocated, never reused across cases in
   one process) or runs in an isolated child process; no production reset seam is
   added. Cases state whether they expect a **cached** answer (no request, immediate
   republication) or an **uncached** one (a recorded request, optionally held).
6. **Characterization through real entry points**, recorded against the ORIGINAL,
   under `test/features/catalog_detail/presentation/legacy_catalog_detail/`. **No
   production accessor:** observe rendered widgets, labels, focus, recording
   callbacks, stores and `MockClient` requests (the checkpoint's `lib/` must equal
   the ORIGINAL; if a seam proves unavoidable, stop and ask). Re-read state after
   acting; exact call lists; sentinel callbacks.

   **Evidence classes.** Without a seam the harness proves less than "every path
   reloads once", so each case names which of three classes it relies on:
   **(R) rendered** behaviour (labels, sections, accent, focus); **(O) observable
   reads** (recording host loaders and `MockClient` requests, which do have counts;
   storage and cached-service reads do not); **(S) checker/source-guard** evidence
   for what neither shows (private counters such as `++_movieCompletionGeneration`,
   early returns that read nothing, transient resets hidden by republication).
   Behavioural negatives ("does not publish", "stale rejected") use **uncached,
   held** responses released after the triggering change; a negative built on a
   cached or immediately-completing read proves nothing and is not accepted.

   | Contract | Coverage |
   | --- | --- |
   | 1 Surface | Existing Home field-read tests; byte guard on lines 44–148 against the surface file. |
   | 2 Lifecycle | **Screen notifiers:** tracking-source revision on a movie whose stored completion was changed first → finished state and label flip (R; `_onMovieProgressPolicyChanged`'s `false` reset then reload); movie-finished and MDBList revisions likewise (R). `_loadLocalMovieFinished` returns without reading for series or a missing IMDb id, and `MovieCompletionService.load` exposes no count, so "reloads once" and the generation bump are (S); series/no-id cases assert only that nothing rendered changes (R). **Mixin notifiers** (`MetadataPreferencesService.revision`, `ProfileRuntime.scope`): with an **uncached, held** IMDb response, IMDb-derived rows disappear while held and return on release (R + O: one new request); recommendations reload through the recording loader (O, exact count); with a cached IMDb answer the transient `_imdbExtra = null` is republished at once, so that reset is (S). **Playback-return listener**, via `notifyPlaybackReturned` and separately via `notifyPlaybackDataChanged`: when current → one `resumeInfoLoader` call (O) and bound state re-read (R); with a route on top → zero loader calls (O); the data-changed case also asserts that an `addContentPlaybackStopListener` probe, armed by `notifyPlayerLaunching()`, is **not** called (only `notifyPlaybackReturned` signals stop). **`didPopNext`** via a pushed and popped route → one loader call (O); its lack of a `mounted`/`isCurrent` gate is (S). **After unmount:** firing each notifier and both bridge signals → zero recording-loader calls (O, "no read"); a held response released after unmount publishes nothing and throws nothing (R, "no publication"); completion-listener detachment is (S). Post-frame order through recording loaders (resume, Simkl, recommendations, enricher, loader art) (O), the rest pinned by an `initState` source guard (S); source guards on `initState`, `didChangeDependencies`, the 11-step `dispose`, both `late` declarations and the mixin clause. Detachment is checker-evidenced unless an existing probe proves it. |
   | 3, 8 Host callbacks, primary sources | Play → `onPlay` once; Rewatch → `onRewatch` and never `onPlay`; movie Sources/hold → `onBrowse`; series hold with packs off → episode sources; packs on → sheet → `searchPacks` or episode; Stremio TV shape (`enablePrimarySourcesHold: false`) does not hold-browse; quick-action rows dispatch the host's exact enum to each host callback; FAB receives the raw `onRecommendationTap`; rail taps map presented → original by identity; `onLoaderArt` emission points. |
   | 4 Resume | Spinner while pending, each label in the matrix, failed loader, 12 s timeout (fake time, mounted outside `runAsync`), refresh after pop, playback return and playback data changed (R+O). |
   | 5 Rewatch | Confirm and cancel with call order (reset before `onRewatch`); busy re-entrancy; `Rewatch` → `Play` without `onRewatch`; the post-confirm failed reset leaves "Rewatch" (Found 2, characterized as-is). |
   | 6 Metadata/profile | Profile scope and policy change reload IMDb extra and recommendations only (O: one new uncached IMDb request, one recording-loader call; zero parents-guide requests for a fresh id); the `_imdbExtra`/`_recommendations = []` reset is (R) only with held uncached responses, else (S); a stale recommendation batch and a stale IMDb answer, each **held and uncached** and released after a policy change, are not published (R); enricher skipped when rich (O). |
   | 7 Watchlist/sources | Toggle on/off with persisted row, rollback and error snackbar on a throwing store (R + store re-read); bound state refreshed on pop, playback return and playback data changed, keyed by `widget.item` (R; store reads uncounted). |
   | 9 D-pad | TV autofocus Play versus Sources (`showQuickPlay: false`); UP scroll-to-top; hold-OK on Play; Read-more toggle by Select; quick-action focus traversal. Existing `catalog_detail_play_hold_test`. |
   | 10 Layouts | Narrow phone, wide desktop (≥ 900 landscape) and TV movie/series; tight height; reveal completes (opacity 1) before capture. |

   **Goldens** (macOS captured by the executor, strict from capture): TV movie
   wide, phone movie narrow, desktop series wide, TV series with resume label.
   Deterministic: pinned surface size, DPR 1.0, `AppThemes.legacy`, `en-US`, text
   scale 1.0, a named initial focus (or none) per golden, fixed metadata and
   artwork, bounded fixed-duration pumps covering the reveal (and a fixed Ken
   Burns phase), all loaders completed so no shimmer, **no wall-clock text**.
   **Readiness:** `_Backdrop` uses `Image.network` with a 650 ms `AnimatedOpacity`
   fade on non-TV (`wasSync` false). Establish the image decode first (inside
   `tester.runAsync`, which does not advance the fake clock, then one frame), so the
   fade starts at a known frame; then advance one **fixed** fake-clock capture
   timeline whose total covers the reveal and the full 650 ms fade. The timeline is
   identical in every run and every golden of a layout, so the 22 s Ken Burns
   controller (started in `_BackdropState.initState`) is captured at the same phase;
   decode waiting never adds fake-clock time. IMDb/parents-guide caches follow the
   cache-isolation rule (each golden its own ids, or uncached responses completed
   before the timeline starts).
   - **Mutation proofs:** every new case first passes in the detached ORIGINAL;
     `original-mutations.json` records named mutations of original code, each
     rejected by an assertion (not a compile error), covering every new identity.
     Record `base2` after the tests; versus `base-fmt` only passing additions.
7. **CI list:** add `test/catalog_detail_play_hold_test.dart` and every new test
   (concrete paths) to `ci_behavior_tests.txt`. If the recorded base shows
   pre-existing failures in newly listed files, add **only those observed
   identities** to `ci_behavior_known_failures.txt` under
   `# 2026-10-04 catalog_detail step 0: pre-existing, newly exposed by CI coverage;
   observed in catalog_detail/base` in the same commit. A test passing in the base
   must keep passing.
8. **Source-text inventory:**
   - `rewatch_launch_routing_test` (CI 39): listener sites stay in the facade's
     lifecycle; `generation == _movieCompletionGeneration` moves with
     `_loadLocalMovieFinished`; `_playPrimary`'s tail-to-EOF checks (`if (restart ==
     null` before `await resetProgressForRewatch`, `restart();`, no `(widget.onRewatch
     ?? widget.onPlay)()`) and `widget.onRewatch == null && _resolvedPrimaryLabel ==
     'Rewatch'` move with the primary action. When they move, the catalog path reads
     `catalogDetailSource()` (facade plus feature files in original manifest order,
     renames reversed, literal-safe), so tail-to-EOF semantics are preserved; add an
     assertion that both rewatch markers lie in `_playPrimary`'s declaration in one
     file. A missing declaration fails, never skips. No assertion is deleted or
     weakened.
   - **Theme:** `theme_surface_manifest.txt:22` (`p2_classic_details`, 3 files,
     6,783 lines, 238 sites) gains explicit per-directory patterns
     (`lib/features/catalog_detail/presentation/*.dart`,
     `…/presentation/legacy_catalog_detail/*.dart`); no recursive `**`. Sites must
     stay 238.
   - `light_ink_inventory.py:67` (`PRIMARY`) and `theme_rendered_set.py:60`
     (`ROUTE_BOUNDARIES`, manual tool): add the feature directories.
   - `file_size_baseline.txt:20`: lowered as the facade shrinks; removed below 800.
   - `.github/workflows/checks.yml`: at step 6 add the facade to the format (45)
     and analyze (52, before `| tee`) lists and every `test/support/catalog_detail_*`
     helper to the format list.
   - Verify unaffected: profile/stale-runtime/theme source guards, storage checks.
9. **Linux capture script** `dev/tool/capture_catalog_detail_linux_goldens.sh`
   (`set -euo pipefail`; checks `uname` Linux and Flutter 3.44.8). **Two-original
   scheme:** it resolves the format-only ORIGINAL by its exact subject and the
   checkpoint by `test(catalog): step 0 original-code characterization
   checkpoint`, then fails unless `git rev-parse <checkpoint>:lib`,
   `:pubspec.yaml` and `:pubspec.lock` equal the ORIGINAL's object hashes. It never
   uses `awk '… { print; exit }'` (or `head`) in a pipeline under `pipefail`: the
   early exit SIGPIPEs the producer and fails the script; use `git log -1
   --format=%H --grep=…` or capture output to a variable first. It captures once in
   a detached worktree of the checkpoint, verifies strictly, copies PNGs, and writes
   `linux-original-{capture,strict,sha256,revision}.txt` under
   `refactor-evidence/catalog_detail/`.
10. **Step 0 checks:** every integrated manifest (vpl, settings, iptv, torbox,
    debrid, pikpak, playback_settings, iptv_settings, playlist_content,
    merged_detail) with self-tests, each with **its own config and original
    baseline** (unchanged; merged_detail at `21320ff9`), plus this one against the
    catalog format commit; architecture, sizes, storage,
    shape, theme, light-ink, CI format, scoped analyzer with allowlist, strict
    comparison, staged diff. Commit the checkpoint with the exact subject above.

### Step 0L — Linux originals

Claude runs the script in the calibrated local Docker image
(`debrify-flutter:3.44.8`, linux/amd64 Ubuntu 24.04, `libsqlite3-dev`, under
Colima; calibrated against the 14 TorBox/Debrid GitHub goldens) and commits the
PNGs separately with `linux-original-verification.json` (hashes, revision,
provenance). From then on the Linux golden test is **strict**: no missing-file
early return, no opt-out define. No golden is ever generated or updated against
moved code. This is a blocking prerequisite for step 2.

### Per step and gates

As in the merged plan; the catalog checks (catalog manifest, format proof,
catalog analyzer comparison) use `--baseline <catalog format commit>` and
`--relocate lib/screens/catalog_item_detail_screen.dart=lib/features/catalog_detail/`.
These apply **only** to the catalog checks: every other integrated manifest runs
with its own config and original baseline, never the catalog SHA or relocation.
Each step: per-entry wiring review before pinning; all manifests with self-tests
(isolated parser); architecture, sizes, storage, shape (reconciles to 29), theme
(238 sites), light-ink, CI format, scoped analyzer with allowlist, per-symbol
strict comparison (zero additions), staged diff; all focused and characterization
tests against the latest `catalog_detail/` base; macOS and Linux strict goldens.
Gates run serially from committed source against the latest base; gate 2 also
against gate 1. Never use `--record` or `--update` to accept a regression.

## Definition of done

1. Facade ≤ 360 lines, formatted, public widget byte-identical, State with the
   three mixins, verbatim lifecycle, both `late`s, overrides, forwarders and
   composition; all callers and tests compile unchanged.
2. The guard registers the feature, the exact bridge (in
   `LEGACY_PLAYBACK_BRIDGES`), facade cap, `TEMP(catalog_detail)` rejection,
   facade back-import, catalog↔merged and service/storage import bans;
   `CATALOG_DETAIL_COMPLETE = True` with every other completed flag preserved.
3. All manifests pass with self-tests; every characterization test passes
   unchanged; the rewatch guard reads the new locations with every expectation.
4. No new diagnostics or suppressions: the 4 const infos, the accepted curly info
   and the allowlisted `_simklStatus` warning remain, traced by identity.
5. CI lists hold the new tests and the play-hold test; known failures gain only
   observed identities. Shape reconciles to 29; theme measures 238 sites.
6. Progress records commits, owners, exceptions with exits, and pending device
   verification (Android TV D-pad and hold-OK, host playback handoffs from all five
   callers, real tracker accounts). Stop after gate 2 and report.

## Explicitly not in scope

- The five callers, Home's flag and routing, `lib/widgets/detail/*`,
  `resetProgressForRewatch`, `MetadataPresentationMixin`, `MetadataExploreButton`,
  trackers, services and storage; merged detail and any shared widget extraction.
- Riverpod, data contracts, localization, deduplicating focus boilerplate, adding
  stale-result guards, image decode sizing.
- Bug fixes and behaviour changes, including every item below.

## Progress

- Execution base: `881ed25073c9cac0f80c5ae650118a9bcdcb4d41`, branch
  `refactor/catalog-detail`, dedicated worktree only. Flutter 3.44.8 / Dart
  3.12.2; first command `flutter pub get`, lockfile unchanged; no push or
  branch switch. Evidence namespace `catalog_detail/`; parser and kernels
  isolated under this worktree's `.dart_tool/catalog_detail_parser/`.
- Untouched full baseline `catalog_detail/base`: 11,093 successes / 13
  failures / 28 errors / 20 skips, stable committed tree
  `b11d47e4c6824a9ed47202bf8f4dcac98509dba5`. Existing catalog hold cases all
  pass; no new CI failure entries are authorized. Whole analyzer: 1,666
  original diagnostics. The historical failure list is not the baseline.
- Temporary oversized original: `lib/screens/catalog_item_detail_screen.dart`
  retains all rendering, lifecycle, state, actions and private widgets until
  the prescribed steps 1–5 extract them. Its format-only ceiling is 3,561;
  step 6 enforces the final 360-line facade cap. This records retention,
  remaining responsibilities and the extraction milestone before editing.
- Format-only preparation preserves every application token, comment and
  literal except the 15 AST-identified optional formatter commas. Only the
  four formatter-broken catalog completion-listener assertions use the new
  declaration-scoped helper; their notifier, operation and callback identity
  remain exact. Every other catalog and merged assertion is retained.
- Format proof PASS: 15 optional commas, token/comment/literal equality and
  four scanner negatives; format idempotent. Listener guard fixture: 48/48
  positives/negatives pass on unformatted and formatted originals; all three
  unchanged rewatch guards pass. Root formatted analyzer: 1,667 diagnostics,
  exactly the one accepted curly info added. Exact-import strict probe uses a
  temporary local analysis config, restored after each run; 20 unformatted
  versus 21 formatted diagnostics. Rejected package-import and symlink probes
  remain evidence only and are never accepted as baselines.
- Conservative decision: the single format-induced curly-braces info is
  accepted by the exact user-approved rule/symbol/message identity; no braces,
  suppression or info allowlist entry. `_simklStatus` remains untouched until
  its private destination and both writers move together in step 3.


- Step 0 original-code characterization: 73/73 pass in the owned detached
  format-only original, recorded as `catalog_detail/original-characterization-final`
  on tested tree `e5dded15496ebe241db83a9d3bc2ce23803a3083` (SDK unchanged,
  no untracked inputs, no tree change during the run). `original-checkpoint-proof.json`
  verifies the whole `lib/`, `pubspec.yaml` and lockfile objects equal the
  formatted original and all 16 test/helper/pixel inputs still match that run.
  There is no production seam. Tests observe rendered widgets, exact host
  callbacks, stored rows, request counts and direct configured-TMDB transport.
- Original negatives: `catalog_detail/original-mutations.json` records 39
  assertion-rejected mutations covering all 73 new identities, zero uncovered.
  Each negative records its tested tree, restores original production bytes and
  preserves all five fixture/master image hashes. The interrupted autofocus run
  was archived as incomplete, the original restored, and that negative rerun;
  neither incomplete runs nor compile-error drafts count as accepted proof.
- Four macOS masters captured against original code and replayed strictly:
  TV movie wide, phone movie narrow, desktop series wide, TV series resume.
  Readiness waits for backdrop decode at zero fake-clock time, then uses one
  fixed 1.2 s reveal/fade timeline, named TV focus, no shimmer and a null accent.
  Conservative fixture decision: explicit empty poster skips the original
  cached accent decode; fixed bitmap artwork still exercises the backdrop.
  Sparse enrichment's loader-art emissions are separately observed. Failed
  cache/accent-readiness drafts are retained only as rejected evidence.
- The LF manifest covers all 135 original leaves; the dependency report reviews
  intended receivers, live host reads, resource owners and every entry's actual
  wiring checkpoint before any scaffold is pinned. Actual moving-step wiring
  remains pending. Catalog-only identity checks pin all eight listener receivers,
  17 callback handoffs, nine raw host assignments and recommendation mapping;
  real-config negatives independently exercise the resolver before whole-leaf
  comparison. Other manifests retain their own configs and original baselines,
  including merged detail at `21320ff9`.
- `catalog_detail/base2` full suite: 11,166 successes / 13 failures / 28 errors /
  20 skips. Comparison with `base-fmt` passes with exactly 73 passing additions,
  no changed original identity, missing test or newly skipped test. Runner flags
  are recorded separately (`--no-pub`); its full-suite paths list is empty.
  Tested tree `176bae456cf23a5671a88e318c640674c3f516f7` is stable.
  This is the latest catalog base for both later gates. Gate 1 and gate 2 have
  not run yet. Every new concrete test and the three already-passing original
  hold cases are on the CI list; the known-failure list is unchanged.
- Step 0 inventories: original shape has 29 bare-radius sites and no tokens;
  theme remains 238 sites (formatting alone raises its measured line total to
  6,844); light-ink remains 919 total / 249 primary sites. Architecture, size,
  storage map/bodies/keys/references and the CI format command plus the catalog
  facade and every helper pass. Current original facade breakdown: 43 import /
  blank lines, 106 public-widget / separator lines, 1,789 State lines and 1,623
  private-widget / section-comment lines = 3,561. The final cap is still pending.
  All source guards remain enforced; feature,
  facade, shape and explicit-directory theme registrations land with step 1.
- Step 0 analyzer closure: root comparison against `base-fmt-analyze.txt`
  has zero added or removed diagnostics (1,667 total). CI-scoped analyzer plus
  `check_analyzer_allowlist.py` passes all 12 exact pre-existing warning entries;
  the seven new tests and four support helpers have no diagnostics. The exact-
  import strict facade probe remains 21 original identities, zero additions;
  its temporary analysis config is removed. Catalog `_simklStatus` warning is
  deliberately outside CI scope until step 3 moves it with both writers and
  adds its full-message destination allowlist entry in that same commit.
- Step 0 checker closure: all 11 integrated manifests and their self-tests pass,
  recorded in `catalog_detail/step0-manifests.json` with separate logs. Every
  invocation uses the isolated parser; each existing manifest keeps its own
  original/config (merged detail `21320ff9`), and only catalog uses the format
  baseline. Catalog passes all 135 leaves plus independent callback, receiver,
  live-read, lifecycle, lazy, mixin, co-location and comment negatives. The
  final staged diff is LF-clean and contains no application change beyond the
  already-committed formatting; all original assertions are retained.
- Linux handoff script uses the exact named checkpoint and format-only original,
  verifies their application objects match, captures in an owned detached
  worktree and replays strict originals before copying four PNGs. `bash -n`
  passes; it has no early-exit producer pipeline. Linux originals are not yet
  present, so step 0L and all moves remain pending. Until original pixels arrive,
  the Linux-only missing-master skip exists solely for this checkpoint; step 0L
  removes it and the opt-out define in a separate provenance/asset commit.


## Found, not fixed

All pre-existing; the extraction keeps each exactly.
1. `_simklStatus` (224) is write-only (`unused_field`); its doc and the
   `simklStatusLoader` doc (98–103) describe a Rewatch relabel nothing reads.
2. `_rewatchPending` is set by `onConfirmed` and cleared only on success: when
   `resetProgressForRewatch` returns false after confirming
   (`rewatch_progress_dialog.dart:63, 72`), the label **stays "Rewatch"**.
3. `_Reveal.build` creates an undisposed `CurvedAnimation` every build; each adds a
   status listener to `_revealCtrl`, so **listeners pile up** until disposal.
4. `_Description` creates a `TextPainter` per layout and never disposes it.
5. Enriched meta, parents guide, accent, Simkl status, watchlist and bound-state
   loads have no generation or profile guard (`mounted` only).
6. `_loadResumeInfo` has no request generation; overlapping calls share
   `_resumePending`, so an older answer can publish last.
7. `onMetadataPolicyChanged` clears `_recommendations`/`_imdbExtra` without their
   loaded flags (no shimmer on reload) and reloads nothing else.
8. The recommendation pre-warm discards futures (errors unhandled), before `valid()`.
9. `_refreshBoundState` has no try/catch, is unawaited, and keys on `widget.item`
   while most sections use presented `_item`.
10. `_toggleMyWatchlist` has no re-entrancy guard, stores presented (possibly
    translated) metadata, and isn't re-read after playback return or policy change.
11. `++_movieCompletionGeneration` runs before the series early return (harmless).
12. Async tear-offs used as `VoidCallback` listeners drop errors.
13. `openMetadataTitle` runs without `isCurrent`; the FAB gets raw
    `onRecommendationTap`, not the identity-mapping `_openMetadataRecommendation`.
14. `_secEyebrow` and `_ActionRow.isSeries` read `widget.item.type`; others `_item`.
15. `_Backdrop` uses `Image.network` with no cache or decode size; the
    `CachedNetworkImage`s in `_CastAvatar`/`_RecCard` have no `memCacheWidth`.
16. Five duplicated focus/hover boilerplates; the two quick-action rows duplicate
    each other deliberately.
17. All user-facing strings are hardcoded English.
18. Interleaved `_recommendations` doc; five fields declared between methods at
    four locations (334, 400–401, 543, 661).
19. The class doc (44–48) is stale.
20. `_artworkAccent` is never recomputed after enrichment changes the poster.
21. Only Home supplies `onRewatch`; elsewhere Rewatch shows as Play (by design).
22. Analytics reports `'catalog_detail'` for movies and series alike.
