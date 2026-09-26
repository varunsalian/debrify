# Search screen incremental refactoring plan

Status: implementation started on `refactor/search-screen`; the automated baseline
and phases 1–3 are reviewed. Phases 4A catalog and 4B keyword extraction are implemented and reviewed; phase 4C source selection is in progress. Device checks remain pending.
Reviews and actual results are recorded in the
[implementation evidence](search-screen-evidence.md).

Destination: [Debrify engineering practices](../../AGENTS.md). Every completed
slice must follow those rules, particularly feature ownership, UI/logic separation,
explicit dependencies, and file-size limits. This document tracks the route there.

## Goal and scope

Turn the current SearchScreen library into cohesive Home, Search, Discover, and
source-selection components while preserving the product's existing behavior.
Aim for no known new regressions, supported by before/after evidence; tests cannot
guarantee zero regressions. Keep each change independently reviewable and reversible.

Work one responsibility at a time, from easy to complex. A slice may update several
callers, but must not rewrite the whole screen or start a general architecture
framework. Do not combine this work with redesigns, feature removal, content-provider
changes, storage migrations, dependency upgrades, or an app-wide state-management
migration. Riverpod DI/state management is an explicit part of each applicable
extraction; unrelated features retain their current state machinery.

Completion means all responsibilities from the five-file library have a coherent
owner, not just that `search_screen.dart` has become shorter. The completed source
set includes every extracted component, wherever placed, and any retained facade.
Existing external services and small call-site edits in `main.dart` remain outside
the structural size target; relocating old screen logic there is not an exemption.

## Starting point

Inspected on 2026-09-26, branch `0.10.1_alpha`, revision `9619c10b`.
Physical lines include comments and blank lines; remeasure as work progresses.

| File | Lines | Responsibilities to extract |
| --- | ---: | --- |
| `lib/screens/search_screen.dart` | 20,865 | Three tab variants, search, home loading, trackers, layouts, navigation, playback handoff, and lifecycle coordination |
| `lib/screens/search/search_sources.dart` | 3,846 | Source results/state, controls/dialogs, and Discover backdrop widgets |
| `lib/screens/search/search_card_widgets.dart` | 1,229 | Cards, artwork, row identities, See All, and mode controls |
| `lib/screens/search/search_hero_widgets.dart` | 2,289 | Hero presentation, trailer/live layers, previews, and animations |
| `lib/screens/search/search_stage_widgets.dart` | 1,706 | Row models, cells, queue controls, and alternate layout presentation |

The library totals 29,935 lines. Four files are `part` files sharing its private
namespace. The screen is mounted by `lib/main.dart` for Home, Search, and Discover;
Home-only testing is insufficient. Dedicated Search also has Catalog, Keyword,
and Lists modes. Preserve the existing constructor and tab behavior during migration.

Reuse existing components such as `TmdbTitleSearch`, `TorrentFilterMatcher`,
`loadHomeCatalogSection`, `HomeLoadProgress`, `runHomeLoadWithDeadline`,
`HomeReturnCache`, `ProfileSessionMemory`, and existing shared widgets. Their
presence is a reason to extract orchestration, not create competing implementations.
In particular, `ProfileSessionMemory` registers each instance in a process-lifetime
set and its `take()` consumes a snapshot. Keep the existing static stores behind
borrowed adapters; do not construct a new store per disposable provider or consume
a snapshot on every provider recomputation. Test late disposal after profile switch.

## Target boundaries

Create only the directories/components needed by the current extraction:

| Location | Owns |
| --- | --- |
| `lib/features/search/` | Catalog/Keyword/Lists search state, policies, and presentation |
| `lib/features/home/` | Home rows, loading/pagination, return state, and board layouts |
| `lib/features/discover/` | Discover source selection, browsing state, and presentation |
| `lib/features/sources/` | Source selection, filtering, result state, and presentation |

Use this responsibility map to prevent gaps. Expand a row into small slices while
working; record actual destination paths and removed originals in its phase log.
Assign any newly discovered responsibility before moving it; do not create a
catch-all "remaining logic" file or discard functionality to finish the checklist.

| Existing responsibility/examples | Destination owner | Phase |
| --- | --- | --- |
| `_sortKeyword`, `_recomputeKeyword`, provider-selection reconciliation | Search policies; focus effects stay in presentation | 1, 4B |
| Mode controls, cards, artwork, row identities, sizing helpers in main/part files | Owning feature presentation/models; shared UI only when reused | 2, 6 |
| `_runListsSearch`, title suggestions, query submit/clear and mode coordination | Search application/presentation | 3, 4A–B |
| `_runCatalogSearch`, `_restoreHome`, `_CatalogSourcesDialog` | Search application/data; explicit Home restore callback/contract | 4A |
| `_runKeyword`, cache checks, bulk selection, `_KeywordSourcesDialog`, `_KwPreservedState` | Search application/data and session-owned snapshot | 4B |
| `_SourcesScreenState`, season selection, addon retry, pin/unpin/local source operations | Sources application/data; Sources UI dispatches actions | 4C |
| `_load`, paging, tracker/CW/favorite/watchlist/playlist/collection loaders and revisions | Bounded Home application/data components | 5 |
| `_HomePreservedState`, return-cache listeners and invalidation | Home session-owned return state; explicit listener owner | 5, 7 |
| Discover selection/hydration, `discoverLandingLoadIsCurrent`, Search handoff | Discover application/presentation | 6 |
| Classic, Spotlight, Canvas, Promenade, Atrium, Mosaic, Deck, Tonight and Discover layouts | Respective feature presentation with shared state/actions | 6 |
| Hero resolution, artwork enrichment, trailer/live/card previews and tint/chrome effects | Hero policy/state with presentation-owned effects | 7 |
| `_openItem`, detail actions, source editing, `_reconcileSeriesResume`, `_playSelection` | Typed action preparation plus presentation routes/playback bridge | 7 |
| `MainPageBridge`, route/app observers, focus/scroll/timers and test-only exports | Explicit presentation/session owners; small compatibility surface | 7, 8 |

Within each feature, use `presentation/`, `application/`, `data/`, and `models/`
when needed. Put a shared component with its actual owner and expose a small public
contract; use shared UI/infrastructure only for demonstrated cross-feature reuse.
Do not relocate every existing service/widget or pre-create empty directories.

- Views render data and dispatch actions. Focus, animation, and route/dialog
  presentation remain in presentation code; they are not business logic.
- Controllers/notifiers own one coherent operation/state lifecycle, not every
  field formerly owned by `_SearchScreenState`. Resolve narrow dependencies in
  application providers/notifiers; keep constructor injection for plain services.
- Thin data adapters may call existing services while preserving storage and
  provider behavior. Do not implement new HTTP clients or persistence layers here.
- Standardize on Riverpod (`flutter_riverpod`) for DI and migrated feature state.
  Phase 3 installs version 3.4.3 with the first production controller integration.
  Verify resolution and commit the lockfile without
  unrelated dependency upgrades. The existing `provider` dependency is not the
  chosen DI system; audit it separately before removal.
- Start with manually declared providers and `Notifier`/`AsyncNotifier` as needed;
  code generation is optional, not a prerequisite. Keep local UI state and pure
  functions simple. Preserve working legacy notifier services through adapters.
- Keep the old import/constructor as a temporary facade while callers migrate.
  It may choose a tab and compose dependencies; it must not retain hidden business
  logic or become the permanent owner of all feature state.
- Never pass the old `State`, `BuildContext`, a service locator, or a giant bundle
  of mutable fields into an extracted controller to simulate independence.
- Keep composition factories separate from operation logic: factories may construct
  concrete legacy adapters; notifiers use narrow contracts. Only a named presentation
  bridge may call an existing context-dependent playback/navigation entry point.
  Put source edits, resume decisions, and progress mutations in application/data code.

Keep Riverpod declarations within each feature's application/composition code and
introduce the app's `ProviderScope` above its consuming Navigator with the first
consumer, so pushed routes and dialogs retain access. Declare providers statically;
do not create fallback containers in screens. Application notifiers
may use `Ref`; repositories and policies take ordinary dependencies and no Riverpod
types. Test notifier behavior in isolated containers without a widget tree.

Separate app, profile/session, and screen ownership. Use stable family keys for
profile/session plus Home/Search/Discover identity where needed; do not assume a
nested `ProviderScope` automatically isolates state. Choose disposal/retention
explicitly so layout changes and tab returns preserve their current contracts.
Cancel stale work and invalidate retained private state on profile handoff. Existing
completed-search/Home snapshots must not acquire an unlimited lifetime accidentally.
Verify that mounted notifiers also reject older actions within the same session.
Wrap mutable legacy `CatalogSection`/collection values in safe state snapshots or
explicit revisions so existing in-place updates cannot bypass Riverpod notifications.
Keep concurrent route instances' mutable workflow state distinct even for identical
profile/query keys; share read-only catalog data only where appropriate. Writes,
downloads, and playback remain explicit actions, never provider-build side effects.
Preserve captured profile access through legacy storage adapters; tests must inspect
stored results after a switch, not only whether stale UI updates were suppressed.

When integrating Riverpod 3, initially disable automatic retries for migrated
operations, preserving existing retry owners. Verify listener pausing on covered
routes, initialization timing, and asynchronous disposal guards. Use disposal hooks
for owned resources; keep ordered playback teardown in its existing coordinator.
These defaults and code-generation choices are documented at
[https://riverpod.dev/docs/3.0_migration](https://riverpod.dev/docs/3.0_migration)
and [https://riverpod.dev/docs/concepts/about_code_generation](https://riverpod.dev/docs/concepts/about_code_generation).

## Invariants to preserve

1. Home, Search, Discover, and all existing display styles retain their current
   routes, settings, visible behavior, empty/error/loading states, and input paths.
2. Keyword relevance order, sorting directions, provider selections, direct-link
   handling, cache badges, cached-only behavior, streaming freeze/adopt behavior,
   bulk selection, and completed-search restoration remain unchanged.
3. Title suggestions preserve debounce, composition handling, mode cancellation,
   exact title identity, and cancellation of stale detail opens.
4. Catalog loading preserves raw paging cursors, hidden/watched filtering, row
   identity, deduplication, timeout/retry behavior, and deferred continuation.
   Preserve Android TV progressive reveal and the distinct tvOS/non-TV behavior.
   Catalog SEARCH has a separate contract: TV publishes a completed batch in stable
   catalog order; non-TV streams completed rows. Preserve disabled-addon settings,
   concurrency limits, partial-failure counts, and query/raw-cursor See All handoff.
5. Profile/request generations prevent late results from crossing profiles or
   replacing newer work. Preserve Home/Search/Discover snapshot separation and
   invalidation on settings, integrations, and profile changes.
6. D-pad focus, hold versus press, source tabs, scrolling, dialog return, sidebar
   handoff, route coverage, and returning from playback retain their ordering.
7. Continue Watching/tracker precedence, resume/rewatch choices, source binding,
   playback metadata, watch-progress writes, and external/native handoffs remain
   compatible. Do not change player engines as part of this screen refactor.
8. Hero/trailer/live previews retain eligibility, dwell/cancellation, volume,
   foreground playback suppression, and resource cleanup without duplicate players.

If existing behavior is demonstrably wrong, record it for a separate bug fix;
do not silently change it during an extraction or weaken a test to preserve a bug.

## Sequence: verify each slice before dependent work

The phases below contain multiple small changes, not one large commit per phase.
Adjust a later boundary if inspection reveals tighter coupling; record the reason.

### 0. Establish the baseline

- Record the starting revision, SDK/platform configuration, `flutter analyze`
  diagnostics, and results for affected test groups below; run the full-suite
  helper once before structural work. Do not assume the historical baseline passes.
- `test/known_failures.txt` currently lists nine historical failures. Compare
  failures by test identity using `python3 dev/tool/test_baseline.py`; never run
  its `--record` option merely to make refactoring pass. Capture new discrepancies
  as baseline issues only with evidence from the unchanged revision.
- Retain the observed failure set from that run, including which historical entries
  now pass. Any test that passes before a slice must pass afterwards, even if the
  helper's old allowlist would accept its failure. Retire stale allowances with
  evidence separately; do not rely on the helper's exit code as the only comparison.
- Map production call sites, test exports, source-text guards, and the lifecycle
  registrations in `initState()`/`dispose()`. List resource owners before moving them.
- Check the responsibility map against all main/part-file declarations, including
  source settings, detail-menu actions, exports, and callbacks used by other tabs.
  Record borrowed external dependencies separately from code being migrated.
- Identify the first dependency group to wire with Riverpod, its profile/session
  keys, and disposal owner. Check SDK compatibility before choosing the package
  version at integration; do not build a global container or migrate unrelated
  screens as preparatory work. Record the baseline before dependency changes.
- Capture representative Home/Search/Discover appearance and interaction on TV and
  non-TV; enumerate supported layout styles. Record missing device checks as pending.
- Record a small behavior matrix: Home/Search/Discover, Catalog/Keyword/Lists,
  enabled display styles, and affected input/platform families. Give each relevant
  combination a test or manual scenario; do not claim that one Home test covers all
  tabs, layouts, or native players. Keep this evidence in the phase log below.
- Add behavior coverage only where the first extraction lacks meaningful protection.

Exit: baseline evidence is recorded below, the first slice has a bounded scope,
and unexplained failures in that slice have been investigated before extraction.

### 1. Pure keyword policies — first implementation

- Start with `_sortKeyword` and `_naturalAscFor`. Extract one small policy into
  `features/search/application/keyword_sort.dart`; pass sort field/direction as
  inputs, preserve current sort values/defaults, and replace the real screen call.
- Cover relevance order, numeric/name direction, empty input, and input-list
  non-mutation. Preserve existing tie behavior rather than adding new tie-breakers.
- Add a small migrated-source size/import check with this first feature directory.
  Cover moved code outside that directory too; exclude unrelated legacy files and
  generated/vendor sources explicitly. Start with simple path/import checks plus
  review, not a new architecture framework.
- In subsequent slices, extract cached-only/provider/source filtering and provider
  selection reconciliation. Reuse `TorrentFilterMatcher`; keep focus-node syncing
  in presentation. Preserve unchecked sources across streaming batches and the
  existing direct-link exception when cache checks cannot apply.

Exit: policy behavior is tested without a widget, production uses it, and the old
duplicate logic is removed. Do not create a controller just for sorting.

### 2. Small presentation components

- Extract a leaf such as `_CategoryTag` or `_SeeAllLink`, then similarly cohesive
  controls from the part files. Inspect actual dependencies before picking each one.
- Pass typed display values and callbacks; preserve keys, semantics, focus nodes,
  animation timing, theme behavior, and dimensions. Reuse existing equivalents.
- Widgets still making data calls are not finished extractions: separate that
  responsibility in a bounded follow-up with a recorded temporary exception.
- Keep source-selection state, hero playback layers, and complex focus ownership
  for later phases. Do not simply convert a large part file into a large public file.

Exit: extracted widgets work without access to private screen state; existing
interaction checks pass. Add new widget tests only for meaningful coverage gaps.

### 3. Lists search and title-search coordination

- Add `flutter_riverpod` and the app's `ProviderScope` in a focused integration
  slice with the first search consumer. Expose the existing MDBList adapter through
  a Riverpod `Provider`; use a `Notifier` or `AsyncNotifier` for Lists state/actions
  according to its existing loading behavior. Keep navigation/focus in presentation.
- Update existing standalone screen/test-helper hosts to provide the same Riverpod
  scope and dependency overrides; include a pushed route/dialog consumer. Do not
  mask missing production wiring with a fallback scope inside `SearchScreen`.
- Verify ordinary rebuilds retain state, disposal releases owned resources, tab
  returns follow the existing contract, and profile/session replacement rejects
  outgoing results. Use isolated test containers and overridden dependencies for
  notifier tests, and `ProviderScope` overrides for widget tests. Check that failure
  does not trigger additional requests through automatic retries.
- Cover connect/disconnect while Lists is selected: preserve mode availability,
  fallback to Catalog using the current query, stale-result cancellation, and focus.
  Ensure rebuilds or reconnects do not replay a user action or leak a second listener.
- Extract Lists query/results/loading/error state with injected MDBList access.
  Keep navigation and focus effects in the view; retain search-to-Discover handoff.
- Reuse `TmdbTitleSearch`; extract only remaining screen coordination that warrants
  it. Preserve mode/query/profile cancellation and suggested-title identity.
- Give each controller explicit ownership/disposal. Test slow-old/fast-new results,
  clearing, mode switching, failure, and disposal using controlled futures.

Exit: these searches run without `BuildContext` in application code, and the
screen no longer maintains duplicate copies of their state.

### 4. Catalog search, keyword search, then source selection

Complete 4A, 4B, and 4C independently. Shared pieces may be reused through explicit
contracts; do not merge the three workflows into a universal search controller.

- **4A — Catalog search:** extract `_runCatalogSearch`, query cancellation, disabled
  addon reads/writes, and result/error state. Preserve bounded fan-out, one row per
  searchable catalog, watched filtering, raw cursor/query handoff, stable TV batch
  publication, and non-TV streaming. Move `_CatalogSourcesDialog` data operations
  out of its widget. Keep focus transfer and `_restoreHome` dispatch in presentation;
  Home state remains owned by Home through the temporary explicit contract.
- Add missing behavior cases for rapid query replacement, partial/total failure,
  no results, disabled addons, TV versus non-TV publication, clearing back to Home
  after deferred settings reload, and See All retaining the query/cursor. Verify
  the real screen is connected to the extracted logic, not only a standalone fake.
- **4B — Keyword search:** migrate streaming, filters, cache state, snapshots, and
  `_KeywordSourcesDialog` persistence/defaults. Preserve engine-selection defaults
  and immediate setting writes, including user-configured indexer engines. Retain
  batching, freeze/pending/adopt rules, cache completion, provider selections, bulk
  actions, and snapshot behavior; reuse the policies extracted in phase 1.
- **4C — Source selection:** separate results, season filtering, individual addon
  retry, cache checks, selected-source reveal, and pin/unpin/local-source mutations.
  Extract `_SourcesScreenState` in small slices, then its controls/dialogs. Route
  mutations through a typed data contract, with selection/focus/scrolling in the view.
- Route existing torrent/provider services through narrow injected adapters;
  preserve credentials handling, request order, retries, and returned identities.
- Move test helpers such as `sourcesScreenForTesting` deliberately; temporarily
  re-export them if needed while callers migrate. Do not accidentally drop coverage.

Exit: all three workflows have independently testable state and actual wired views;
source-setting writes retain their behavior, and result completion cannot steal
focus, lose selection, or publish stale results.

### 5. Home data and continuation

- Extract catalog loading/refresh first, then vertical/horizontal pagination,
  followed by independent Continue Watching, favorites/watchlists, and collections
  responsibilities. Do not replace all Home state with one oversized controller.
- Reuse existing paging, deadline, return-cache, and progressive-loading helpers.
  Preserve profile generations, committed snapshots, and settings invalidation.
- Preserve `ProfileSessionMemory`'s borrowed static lifetime and consume-once
  snapshots. Exercise repeated mount/unmount and a profile switch followed by late
  disposal; retained store/listener counts must not grow with screen visits.
- Keep tracker precedence and source identity unchanged. Keep catalog ordering and
  focus coordination in agreement through stable row/item IDs and explicit events.
- Keep resource/state owners above layout branches when their lifetime must survive
  layout changes; transient focus/scroll resources still belong to presentation.

Exit: existing pagination, timeout, profile-switch, refresh, and cached-return
scenarios pass through the new production path without extra loads or stale rows.

### 6. Discover and remaining layouts

- Separate Discover selection/hydration from its grid/stage presentation. Preserve
  user-choice precedence over late startup defaults and Search handoff precedence.
- Extract one Home layout at a time, including current Classic/Spotlight and
  alternate layouts. Inventory actual enabled styles rather than removing rare ones.
- Reuse typed row models and narrow actions. Layout variants must share feature
  state; changing layout must not refetch data or restart playback accidentally.
- Preserve deliberate preview teardown during style changes, such as
  `_onDiscoverLayoutChanged`; avoiding incidental restarts does not mean forcing
  previews to stay alive across layouts that currently release them safely.
- Move layout-specific focus/metrics with the view and maintain an explicit owner
  for resources shared across variants. Do not solve layout extraction by passing
  the entire old screen state or a large collection of unrelated callbacks.

Exit: Home, Search, and Discover have separate feature views; all inventoried styles
remain reachable and tested for their affected layout/input behavior.

### 7. Hero, navigation/playback handoff, and remaining lifecycle

- First extract hero metadata/eligibility policy, then trailer/live-preview
  coordination, preserving timers, request generations, suppression, and cleanup.
- Separate resume/source/action preparation from route/dialog execution. Keep
  navigation in presentation and existing playback services/engines behind a
  compatibility adapter; document any legacy service that still needs UI context.
- Include detail-menu tracker actions, source add/edit/remove/local pickers, random
  episode and pack-search actions, and resume/rewatch decisions in separate slices.
  Existing engine internals remain out of scope; the new presentation bridge only
  translates/dispatches prepared actions and does not absorb business logic.
- Preserve every relevant registration/unregistration, post-frame focus disposal,
  route-cover event, playback-return refresh, and profile-switch cancellation.
- Verify actual playback entry/return and preview-to-player handoff on affected
  platform families. Flutter widget tests alone cannot establish native parity.

Exit: no leaked listeners, competing playback owners, duplicate launch, stale
resume writes, or known new focus/lifecycle regressions in the exercised scenarios.

### 8. Retire the shared library and review the destination

- Remove the four old `part` directives/files once their contents and callers have
  migrated. Retain only a small compatibility facade at the original screen path if
  still useful; otherwise update imports and delete it in a separate verified move.
- Remove obsolete fields, helpers, exports, adapters, and exceptions. Search all
  application/test references, including source guards and theme manifests.
- Audit feature dependencies, file/class sizes, state ownership, and UI/data
  boundaries. New UI must not secretly reach old services through global lookups.
- Close every row of the responsibility map with destination paths and verification
  evidence. Resolve temporary size/UI/data-boundary exceptions in the completed
  source set; do not carry those exceptions into a declaration of completion.
- Run the scoped architecture checks and wire them into CI alongside relevant
  formatting/analyzer/tests. Keep checks restricted to migrated code so unrelated
  legacy debt does not force a repository-wide cleanup. Review semantic boundaries
  that simple import checks cannot establish.
- Run final full-suite/analyzer comparisons and the applicable device smoke checks.
  Document any external legacy dependency left behind rather than claiming the
  entire app is modernized by this screen migration.

Exit: the completion criteria below are satisfied and remaining limitations are explicit.

## Existing verification map

Paths below are under `test/`; these are starting points, not proof of complete
coverage. Run affected groups per slice and broaden at controller/layout integration
milestones. Add tests for missing behavior, not every mechanical file move.

| Area | Existing tests to inspect/reuse |
| --- | --- |
| Suggestions/search UI | `tmdb_title_search_test.dart`, `search_title_suggestions_test.dart`, `search_rail_metrics_test.dart`, `tv_search_focus_handoff_test.dart` |
| Catalog search/settings | Reuse search UI tests above; establish missing query race, TV/non-TV publication, source-toggle persistence, and See All handoff coverage in phase 4A |
| Stream results/sources | `streaming_search_test.dart`, `cinema_sources_focus_test.dart`, `source_focus_lifecycle_test.dart`, `source_list_scroll_anchor_test.dart`, `source_sheet_test.dart` |
| Home loading/paging | `home_catalog_refresh_test.dart`, `home_load_deadline_test.dart`, `home_load_progress_test.dart`, `home_progressive_screen_test.dart`, `home_progressive_pagination_test.dart`, `filtered_catalog_pager_regression_test.dart` |
| Return state/focus | `home_return_cache_test.dart`, `home_continuation_focus_test.dart`, `home_row_focus_test.dart`, `catalog_continuation_button_test.dart` |
| Rows/layouts/Discover | `home_row_order_test.dart`, `home_layout_policy_test.dart`, `home_collections_responsive_test.dart`, `collections_stage_regression_test.dart`, `discover_source_startup_test.dart`, `tmdb_discover_screen_test.dart` |
| Hero/previews | `spotlight_board_test.dart`, `spotlight_board_compact_test.dart`, `spotlight_hero_ambient_policy_test.dart`, `hero_trailer_backdrop_test.dart`, `home_hero_source_test.dart` |
| Playback/profile boundaries | `rewatch_launch_routing_test.dart`, `movie_resume_source_independence_test.dart`, `profiles/profile_source_guard_test.dart`, plus profile-switch scenarios in `home_progressive_pagination_test.dart` |

Source-text guards also exist in `home_expanded_card_settings_test.dart`,
`collections_stage_regression_test.dart`, `rewatch_launch_routing_test.dart`,
`profiles/profile_source_guard_test.dart`, and `theme/shape_manifest_test.dart`.
When relocating guarded behavior, update its location or replace the guard with
equivalent executable coverage. Do not erase an assertion just because a filename changed.

For every slice: format changed Dart files, run `flutter analyze`, run the affected
existing/new tests, inspect the diff and line counts, and record results. Run the
full-suite helper at baseline, major integrations, and completion rather than after
every leaf extraction. Never broaden accepted failures to hide a regression.
Run the scoped architecture check once introduced. Compare analyzer rule/symbol/
message identities so moved line numbers are not mistaken for new issues. Preserve
test collection and assertions; explicitly map renamed/replaced tests to equivalent
behavior. The failure-baseline helper alone cannot prove coverage was retained.
Its historical allowlist also cannot prove that a previously passing test stayed
passing; compare the actual before/after outcomes for those tests.

For changes affecting presentation/lifecycle, smoke-test Home → Search modes →
Discover → Details/Sources → Playback → Back. Include slow/failing providers,
profile switches during pending work, tab returns, remote navigation, and resizing
where applicable. Exercise Android TV, tvOS, and affected touch/desktop platforms;
record devices/configurations used and checks that could not be performed. Compare
first-content time, request counts, rebuild behavior, and retained resources against
the baseline when those paths change; investigate unexplained deterioration.

## Temporary exceptions and progress

The five files in the starting inventory are registered legacy size/structure
exceptions because they jointly own the current production behavior. Their remaining
responsibilities are listed there and scheduled in phases 1–8. Do not add unrelated
responsibilities; update counts and remaining work as each extraction lands. This
exception does not automatically cover newly created oversized files.

Existing services/widgets outside this migration remain legacy dependencies. Narrow
adapters may preserve their current APIs; list any new transitional adapter's path,
reason, remaining coupling, and removal milestone when introducing it. Revisit
exceptions at each phase; retire resolved ones.

Source batch preparation now reads live search/saved state and the scoped IPTV
classifier in `application/source_batch_preparation.dart` (47 lines). This
stateless operation retains no rows and rejects retired profiles/scopes. The
existing pure preparation policy and results-state controller are unchanged;
adoption remains explicit after the view captures focus. Saved-source and binding
providers declare their dependencies so nested overrides remain isolated and
consumers resolve the correct saved-state owner. Focus remains in presentation.

Sources picker diagnostic emission now uses an app-scoped injected callback,
captured at view initialization so delayed reveal logs do not access a disposed
Ref. The existing `services/source_selection_diagnostics.dart` (170 lines) owns
the unchanged writer and is registered in the migration's measured source set.
The view retains structural field collection and disposed-state snapshots. This
removes the search library's direct DiagnosticLog dependency without changing
privacy labels, event names or console formatting.

Sources reveal generation, remembered cinema row and deferred focus anchors now
live in `presentation/source_results_focus.dart` (160 lines), one presentation
coordinator per view. It borrows nodes/scrolling and reads mounted/search/freeze/
control focus/TV state through live callbacks. Identity matching, result adoption
and application state remain outside it. It owns no disposable resource; queued
work retains the original mounted and generation checks. Streaming and completion
keep their distinct guard/scheduling rules. Its extracted implementation and
real-screen focus paths are covered by host tests; native review remains pending.

Sources row-to-saved-binding matching now lives in the plain
`data/source_binding_matcher.dart` (43 lines), supplied by the small app-scoped
`application/source_binding_match_dependencies.dart` (14 lines). Injected IPTV
ownership and media-server identity callbacks preserve on-demand lookup behavior;
no profile results/keys are cached in the adapter. Primary selection also obtains
its media-server callback through this boundary. The distinct primary-selection
policy and diagnostics remain in their existing operation; the row menu matches
the first eligible saved binding, preserving its original broader fallback rules.

Sources toolbar grouping now lives in `presentation/source_toolbar.dart`
(58 lines), with provider options, borrowed controls and explicit action callbacks.
The existing pure provider projection also supplies ordered compact-toolbar
warnings (191-line file), preserving selected-key scope and retry qualification.
Cinema does not evaluate that warning projection. The screen retains selection,
retry, season, sort, filter and focus dispatch; no competing toolbar state exists.

Sources loading/error and results-body composition now lives in
`presentation/source_results_body.dart` (61 lines). It borrows the scroll
controller and row builder, retains the keyword field above all status branches,
and lazily constructs optional title/toolbar/pending content in the results branch.
The view keeps mode/season/retry visibility decisions and classic row actions;
there is no additional state owner or copied result collection.

Sources responsive chrome now lives in `presentation/source_screen_frame.dart`
(112 lines): compact app bar and cinema frame, contextual labels/art, local-file
affordance and responsive branch selection. It takes typed display inputs and
explicit callbacks, returns the same widget tree and borrows the cinema key.
Capability/provider getters retain layout-time evaluation. Search, selection,
stream freeze and focus restoration remain owned by the screen. Real-screen
compact/cinema roundtrip tests cover normal and picker mode without re-searching.

Sources detail/picker row composition now lives in
`presentation/source_result_row.dart` (66 lines). It synchronously consumes the
row and immutable appearance settings, borrows the focus node and returns the
existing `SourceRow` directly. Display mapping is separate from screen actions
and remote navigation, which retain their original view ownership and closures.
The existing shared `widgets/source_row.dart` remains a legacy dependency; its
badge-service coupling remains subject to the final transitive boundary audit.

Sources row-node construction, resize, toolbar replacement and disposal now live
in `presentation/source_row_focus_nodes.dart` (69 lines), owned by the view.
Rows receive a read-only live list and borrow the nodes. Retain immediate search
reset versus post-frame retirement for rows still mounted, existing labels,
toolbar focus and view teardown ordering. A multi-row shrink now requests focus
once on the final survivor, avoiding the original intermediate removed-node
target; its reproduced node-level failure and correction are recorded in evidence.
Selection matching, stream adoption and
remote anchor decisions remain presentation work with the existing view while
their separate extraction/ownership review continues.

Phase 4C's modal ownership review includes row actions after view/profile
retirement and modal builders rebuilt after their originating route is removed.
Reject stale actions before reading widget Ref/context, and give the Sources
filter dialog its opening values through `presentation/source_filters_dialog.dart`.
Keep active-action messages, native arguments, modal appearance and dismissal
unchanged. This does not cancel already-started legacy playback/download work.
The shared `lib/widgets/torrent_filters_sheet.dart` now uses
`lib/ui/core/filter_sheet_header.dart` (77 lines); the title is constrained to
remaining header space, fixing the observed narrow/scaled-text overflow. Both shared paths join the measured source set because Sources and
Keyword search reuse this editor. Preserve the editor's owned focus nodes,
keyboard activation, live Clear eligibility and selection/result semantics.
The remaining 700-line editor owns local facet selection, focus and scrolling
only; that cohesive 501–800-line responsibility review is recorded in evidence.
Native/font/device layout verification remains separate from host widget checks.

Sources playback and direct-stream download dispatch now use the named
`presentation/source_playback_bridge.dart` to reach the existing context-dependent
legacy APIs. Keep row/menu eligibility, tap suppression, freezing and completion
reload timing unchanged. Preserve the rendered list/index pair, metadata, search
title and explicit force-play flag. This is an injection boundary, not a claim
that native playback/download internals are migrated: phase 7 retains their
lifecycle/device audit and phase 8 their transitive dependency audit.

The Sources copy-link action now uses a stateless, injected
`data/source_link_copier.dart`, composed by `application/source_link_dependencies.dart`.
It temporarily reuses the legacy IPTV deferred-descriptor predicate and episode
resolver/result type. Phase 4C owns verifying active/deferred copy behavior and
rejecting retired view/profile continuations; phase 8 must audit the transitive
resolver dependency. Clipboard access belongs to the small shared platform adapter
`lib/core/platform/system_clipboard.dart`, registered in the measured source set.
The view retains the existing messages; no clipboard contents or resolved links
are stored as feature state. Existing resolution/native exceptions retain their
propagation behavior, and an already-issued clipboard write cannot be undone.

The legacy `lib/services/torrent_playback_service.dart` retains manual binding
UI, provider preparation and automatic playback/binding paths. Phase 4C may add a
narrow persistence callback to its four manual binding entry points while the
original dialogs/native pickers remain there. Sources must supply its captured
repository writer. Its optional manual-operation cancellation callback is also
permitted for Sources; legacy callers retain their existing unguarded contract.
This exception covers the four manual entry points, their picker return checks,
and shared configured-provider loading. Extract that sequential loading into a
plain Sources data helper with injected readers; retain the same provider order
and default-selection rules for automatic playback callers, which do not pass a
manual action guard. This is not a service-wide cancellation rewrite. Move the manual binding UI behind the named presentation
bridge and finish its async ownership review before phase 4C closes; automatic
playback and engine internals stay in their existing phase-7 shared boundary.
The manual `_add` path may also forward its action guard through the four API-key
credential reads and check between acquisition responses. Retain request payloads,
provider ordering and legacy automatic callers; preserve cleanup of already-issued
requests. PikPak's preparation may move into a plain Sources data operation with
injected API readers/delay and typed immutable video descriptors. Preserve its
seven task attempts, five detail attempts, two-second waits, recursive depth limit,
partial-folder behavior and error-to-message mapping. Manual calls must stop between
waits/requests; automatic calls retain their unguarded behavior. Playlist rendering,
navigation closures and shared authenticated API internals stay in the legacy
service under the phase-7 exception; this extraction does not prove their ownership.
Manual binding loader cleanup may also adopt an owned route handle from the
existing `lib/widgets/debrid_loading_overlay.dart` (718 lines). Preserve its
provider styling, animation, barrier and Back behavior, and the existing callers
that ignore its return value. Only the manual binding caller changes dismissal
ownership here; other playback/UI responsibilities remain for phase 7. Verify that
completion removes its own loader when another route arrives or the launching
view/navigator disappears. This is a separate evidenced lifecycle correction.
The Sources view's bind-mode completion now captures its own route before the
action. Successful current/session-owned completion pops that route when current
or removes it when covered; retired/failed actions retain the existing no-close
contract. This separate correction is covered through the actual Sources view.
Do not treat the entire legacy playback service as newly extracted code or add
unrelated behavior to it under this exception.
The Sources manual picker boundary is now
`lib/features/sources/presentation/source_binding_bridge.dart`: a stateless,
Riverpod-injected bridge requiring the guarded writer for each pin. Its two
explicit legacy imports (IPTV ownership and playback/picker entry points) are
registered by exact file and service in the architecture guard. Views cannot
inherit that import allowance. The bridge owns no persistence or application
state. The provider preparation/authorization and picker async ownership review
still must close in phase 4C; playback/download entry points still need their
phase-7 bridge. This is not evidence that legacy internals are fully separated.

`lib/services/storage_service.dart` (10,728 lines before this slice) remains an
existing app-wide storage dependency. Phase 4C may add a guarded variant of
`setDefaultTorrentProvider` so a retired manual picker cannot write after waiting
for the preference mutation barrier. This is a bounded change to the existing
scalar preference primitive, not a migration of the entire storage service.
Keep its key/schema and unguarded callers unchanged. The Sources preparation
adapter and its ownership tests must account for this write before phase 4C
closes; unrelated storage responsibilities remain outside the Search migration.
Phase 4C may also add guarded reads to the five provider credential getters used
by availability checks (four API keys and PikPak email) and PikPak enablement.
Keep existing unguarded/remote-transfer behavior and credential formats intact;
manual guarded reads must ignore foreign captured zones and stop stale lazy
migration writes. `lib/services/secret_vault.dart` (398 lines before this slice)
is an existing encryption dependency, retained for its format and crypto behavior;
only its scalar read's optional action guard and migration-write boundary change.
No encryption algorithm, device identity, credential routing or bulk-reader rewrite
is included. Validate this boundary in phase 4C; the rest of these services stays
outside the Search migration.

The shared configuration loop now uses
`lib/features/sources/data/source_provider_configuration.dart` (35 lines).
Its inputs are plain asynchronous readers; it owns no credentials, UI or Riverpod
state. The legacy playback service supplies those readers for both manual and
silent playback, preserving its established order. Manual actions pass their live
check; silent playback retains its unguarded contract. Configuration readers now use the guarded path through preference opening,
resource routing and scalar credential migration. Manual acquisition now passes
that guard through `_add`; PikPak preparation uses
`lib/features/sources/data/pikpak_source_preparation.dart` (172 lines), with
`lib/features/sources/models/pikpak_prepared_source.dart` (24 lines). The shared
playlist builder consumes these immutable descriptors; the provider-native bound
caller decodes its existing file records at that boundary. Shared API retries and
authentication, loader route ownership and native picker internals still need
review at their recorded milestones. Availability checks alone do not establish
ownership for those internals.

`lib/services/local_bound_source_service.dart` (1,033 lines before this slice)
is an existing shared picker dependency used by Sources, catalog/detail callers
and playback's local episode resolution. Phase 4C extracts its desktop filesystem
inventory, filename/folder matching rules and immutable file descriptors into
plain Sources data/model files. Keep the public episode-scan entry point and model
export compatible, including its caller-owned result list. Preserve traversal,
ordering, partial-result/error behavior, matching scores, source metadata and
schemas. Native file/Android pickers, dialogs and navigation remain temporarily in
that service; their guarded continuation review and UI separation remain phase-4C
work. Do not redesign unrelated catalog/detail callers or native APIs under this
exception. New data code stays free of Flutter UI and Riverpod; production callers
must use it and the old implementations must be removed. This extraction is now
wired: `data/local_source_files.dart` is 139 lines, `data/local_source_file_rules.dart`
is 107 lines and `models/local_source_file.dart` is 47 lines under the Sources
feature. The legacy service is down to 750 lines, with native/modal orchestration
and async ownership still pending; being below the ceiling does not close those
boundary requirements. The movie mode sheet, file/folder choice dialogs and
series-folder guidance may now move into Sources presentation components taking
typed display inputs. Keep selection limits, order, cancellation, focus, styling
and unchanged legacy copy; platform wording is supplied by the existing caller.
Native acquisition and continuation checks remain with the recorded picker bridge.
These dialogs now live in `presentation/local_movie_pick_mode_sheet.dart` (108
lines), `local_source_choice_dialogs.dart` (179 lines) and
`local_series_folder_help.dart` (96 lines). The legacy picker is 371 lines;
Android-specific presentation, native calls and guarded continuations remain open.
The optional manual action check may be forwarded into local movie/series picking
and checked after mode/native selection, folder scanning, metadata and follow-up
modal returns. Preserve unguarded callers, native API arguments and existing
current-action errors; reject retired UI continuations before another dialog or
save. Review Android branches separately from desktop widget coverage and retain
native/device checks as pending until actually run.

The keyword filter and Sources toolbar projection reuse the existing pure calls in
`lib/utils/torrent_filter_matcher.dart` and `lib/services/source_priority.dart`.
Those legacy files retain transitive UI/service dependencies (including quality
classification in `torrent_result_row.dart`). Keep behavior during extraction,
then separate their pure classification/ordering dependencies before the phase-8
boundary audit. Passing the current direct-import guard does not close this
transitive dependency exception. Sources result preparation also reuses the pure
`StremioService.selectPinnedDirectStream` selector; separate that dependency under
the same phase-8 audit, preserving shared playback selection semantics. The
`SeriesSource` model exception is closed: it now lives in
`lib/models/series_source.dart`, registered in the migration guard, with only pure
model/hash dependencies. The service re-exports it for legacy caller compatibility. The Sources
search controller also reuses the pure `TorrentService.mergeSearchResults`
operation; separate its service imports under that audit without changing merge
or deduplication behavior.

| Phase | Status | Revision, checks, and remaining work |
| --- | --- | --- |
| 0: Baseline | Automated baseline reviewed; device checks pending | `aa3d5643`: 7,387 pass / 51 fail / 20 skipped; 865 analyzer diagnostics; ownership/behavior inventory recorded in implementation evidence |
| 1: Keyword policies | Complete; reviewed | Sorting (`bd0c214e`), filtering and provider reconciliation wired; 32 new policy tests; final affected run 129 pass and the same two baseline suggestion failures; no new analyzer identities |
| 2: Leaf presentation | Complete; reviewed | Category/See All (`146466b5`) and mode controls extracted; eight new widget tests; final affected run 29 pass / same three baseline failures, analyzer unchanged; complex cards/layouts remain phases 6–7 |
| 3: Lists/suggestions | Implemented and reviewed | Riverpod 3.4.3 and Lists controller wired; 23 new tests pass; full suite 7,450 pass / same 51 baseline failures / 20 skipped, no missing tests, analyzer unchanged; device checks pending |
| 4A: Catalog search | Implemented and reviewed | Riverpod state, streaming/TV batching, source settings and dialog wired; 35 new tests pass; affected suite retains the same three baseline failures, analyzer unchanged; device checks pending |
| 4B: Keyword search | Implemented and reviewed | Application/data state, settings/defaults, selection and snapshot ownership wired; full suite 7,600 pass / same 51 failures / 20 skips, analyzer unchanged. Focus/navigation wrappers remain in the registered legacy screen (20,138 lines) for later presentation/bridge phases; device checks pending |
| 4C: Source selection | In progress | Season policies, guide state/inventory, startup settings, saved-source loading, cache checks, initial requests, individual addon retries, toolbar projection, streamed-result preparation search state/batch orchestration, and adopted/pending result ownership and toolbar state/reconciliation and guarded unpin persistence extracted; shared binding model separated from storage; shared pin/local action gate and reload orchestration extracted; manual Sources bindings now use guarded repository persistence. Row-action sheets extracted with captured theme and guarded modal dispatch; pending-results pill extracted with borrowed focus and explicit navigation callbacks. Title/keyword headers extracted with existing render/input contracts. Active-filter summary and label helpers extracted. Season/sort/filter controls extracted with lazy menu values and view-owned focus dispatch. Provider strip extracted behind immutable display options; real narrow-screen selection/retry wiring verified. Shared source-row metadata labels extracted and Keyword callers updated without changing its distinct subtitle fallback. Provider-strip projection extracted into a pure operation with immutable results. Cinema provider summaries and server messages extracted; shared provider model separated from its widget with a compatibility export. Results pane extracted with borrowed controller and drag-only freeze dispatch. Status presentation extracted with existing visibility and theme contracts. Primary saved-source matching extracted with row identity and diagnostics preserved. Lazy row reveal extracted into a presentation helper with live view cancellation checks and borrowed nodes/controller. Manual picker calls now go through an injected presentation bridge requiring the guarded writer and live action check. Retired actions stop at outer preparation/picker boundaries; active remember-choice behavior is retained. Remember-choice writes now recheck action ownership after the preference mutation barrier and ignore foreign captured scopes. Sequential provider-availability/default loading now uses a plain data helper with injected readers and retirement checks between reads. Manual configuration credential reads now carry the action guard through profile routing and legacy sealing, including migration writes waiting on the preference barrier. Manual acquisition now forwards the action guard into the four API-key reads and checks each top-level provider response before continuing. PikPak preparation now uses an injected plain data operation with immutable video descriptors, preserving polling/listing behavior and stopping retired manual actions between waits and requests. The manual binding loader now owns its exact route, preserving newer routes when the action or launching view retires. Bind-mode completion likewise closes only its captured picker route after a successful, current save/reload. Local desktop filesystem scanning, matching and file metadata now use plain Sources data operations and immutable descriptors; the old implementations were removed and the legacy episode API remains compatible. Local movie mode, candidate choices and folder guidance are now standalone presentation functions with typed inputs; their legacy bodies were removed. Local binding now forwards the live action check through picker, filesystem and follow-up modal awaits, rejecting retired continuations while preserving unguarded callers. Copy eligibility, deferred episode resolution and clipboard sequencing now use an injected stateless operation; the view retains messages and supplies originating-profile/view ownership. Playback and direct-stream downloads now use an injected presentation bridge, retaining visible-list/index handoff, force-play intent, tap suppression and post-completion reload. Modal actions now reject retired views/profiles before dependency/context access; row-menu copy dependencies and filter-dialog opening values survive modal rebuilds independently of the original view. The shared filter header is extracted with borrowed focus/live Clear eligibility; its constrained title fixes narrow/scaled-text overflow, and the original 500-pixel modal fixture passes again. Row-node construction/replacement/disposal now has a view-owned presentation helper with a read-only live list; a reproduced multi-row shrink fallback flaw is corrected without moving the view’s selection/anchor policies. Detail/picker result-row composition is now a standalone presentation function with explicit display inputs and borrowed callbacks, preserving the existing widget tree. Compact/cinema frame composition is extracted with typed display inputs and unchanged view-owned focus callbacks; normal/picker resize roundtrips retain nodes and make no new requests. Loading/error/results-body composition is extracted with lazy optional content, borrowed resources and unchanged row actions. Toolbar grouping is extracted with unchanged control/action callbacks and pure ordered provider-warning projection. Row-to-saved-binding rules now use an injected stateless matcher; primary-selection media identity lookup also uses that adapter. Reveal generations, remembered cinema row and deferred streaming/completion anchors now have one presentation coordinator with borrowed resources and live guards. Picker diagnostic emission uses a captured injected callback and the existing logging service; no direct DiagnosticLog dependency remains in the search library. Batch preparation now has a stateless application owner for live scoped inputs; saved-source/binding dependency declarations preserve nested scope isolation. Latest slice: all 468 affected Sources/focus tests pass and no new analyzer diagnostics; the results-pane slice removed one legacy deprecation. Shape-manifest location follow-up preserves its 490-call threshold. Latest full suite: 8,093 successes, same 51 failures/20 skips, all prior checkpoint outcomes preserved; the first local-retirement run had an additional profile identity-save failure that passed independently and in the unchanged repeat full run, retained in evidence alongside the transfer cleanup timing failure, which recurred on the first playback-bridge run and passed in its unchanged full repeat. Legacy binding UI/data boundaries, remaining Sources UI and focus ownership remain; Sources part 1,543 lines |
| 5: Home data | Not started | Preserve paging, snapshots, profiles, tracker semantics |
| 6: Discover/layouts | Not started | Inventory and retain current variants |
| 7: Hero/handoff/lifecycle | Not started | Native/device checks required where affected |
| 8: Retirement/audit | Not started | Remove parts and verify destination |

After each slice, add its revision, extracted responsibility, actual checks/results,
new/retired exceptions, and next small step in the relevant row. If behavior changes
unexpectedly, pause dependent extraction and fix or revert that slice; do not stack
more restructuring on an unexplained regression. Do not revert unrelated user work.

## Completion criteria

All rows below must pass. Record the final revision and actual evidence in the
phase-8 log; planned checks and temporary exceptions are not passing results.
This migration's final 800-line ceiling is stricter than the generic exception
policy in `AGENTS.md`: oversized legacy/extraction exceptions are interim only.
Test sources, generated code, and vendors retain the exclusions in `AGENTS.md`.

| Outcome | Evidence required to call this migration complete |
| --- | --- |
| Whole-library coverage | Every responsibility-map row has destination paths and checked behavior; no old behavior silently dropped or moved outside the measured set. |
| Small entry point | `lib/screens/search_screen.dart` is removed or at most 300 formatted lines of compatibility/routing/composition, with no search, persistence, resume, or playback business logic. |
| Cohesive, bounded files | Every handwritten application file in the completed source set is at most 800 lines; aim for 300, accept cohesive files up to 500, and record responsibility review for 501–800. No temporary oversized-file exceptions remain. |
| Real feature boundaries | Production uses Home/Search/Discover/Sources components; no replacement giant controller, circular feature dependencies, handwritten `part` files, or private-state fragments. The four original part files/directives are removed. |
| UI/logic separation | Views contain presentation/interaction only; notifiers handle bounded state/actions; data access is behind injected contracts. Only named presentation bridges reach legacy context-dependent playback/navigation APIs. |
| Riverpod in production | Migrated feature state/dependencies use Riverpod, with scoped tests for disposal, profile/query races, retry behavior and retention. Repositories/policies have no Riverpod or UI context; new feature DI does not use `package:provider`. |
| Behavior preserved | Recorded scenarios cover all tab/search modes and enabled layouts, with relevant remote/touch/desktop checks. Filtering, source-setting writes, snapshots, tracking/resume and playback handoffs retain their contracts. |
| Regressions controlled | Affected tests and analyzer/full-suite comparisons have no unresolved new failures; historical failures remain evidenced separately. Native/device checks required by the changed boundary have passed. |
| Performance preserved | For changed loading/preview paths, compare fixed datasets and the same device/configuration: request counts, first-content timing, rebuilds and retained resources show no unexplained deterioration or growing leaks. |
| Maintainable result | Scoped size/import checks run in CI, replaced code is deleted, guards retain equivalent coverage, and temporary structural exceptions are closed. No unused scaffolds, duplicate state, or extra DI framework. |

An unavailable required device check leaves its phase's verification pending; it
does not prevent unrelated safe slices from progressing. Missing evidence cannot
be converted into a pass by moving a requirement to an exceptions list.

Completion applies to this migrated library. Existing external services, engine
internals, app-wide localization debt, and global storage/schema modernization
remain separately scoped work. Record such dependencies honestly; none permits
unfinished UI/logic separation or oversized extracted code in the completed set.
