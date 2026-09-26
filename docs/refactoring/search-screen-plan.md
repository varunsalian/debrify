# Search screen incremental refactoring plan

Status: implementation started on `refactor/search-screen`; the automated baseline
and phases 1–2 are reviewed. Phase 3 is next. Device verification remains pending.
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
  It is not yet installed. Add a compatible stable version with the first production
  controller integration, verify resolution, and commit the lockfile without
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

| Phase | Status | Revision, checks, and remaining work |
| --- | --- | --- |
| 0: Baseline | Automated baseline reviewed; device checks pending | `aa3d5643`: 7,387 pass / 51 fail / 20 skipped; 865 analyzer diagnostics; ownership/behavior inventory recorded in implementation evidence |
| 1: Keyword policies | Complete; reviewed | Sorting (`bd0c214e`), filtering and provider reconciliation wired; 32 new policy tests; final affected run 129 pass and the same two baseline suggestion failures; no new analyzer identities |
| 2: Leaf presentation | Complete; reviewed | Category/See All (`146466b5`) and mode controls extracted; eight new widget tests; final affected run 29 pass / same three baseline failures, analyzer unchanged; complex cards/layouts remain phases 6–7 |
| 3: Lists/suggestions | Not started | Install/wire Riverpod with first consumer; preserve title-search service |
| 4A: Catalog search | Not started | Fan-out/publication, source settings, clear/restore, See All handoff |
| 4B: Keyword search | Not started | State, streaming, engine settings, snapshots, bulk actions |
| 4C: Source selection | Not started | State, season/retry, pinning, cache and focus contracts |
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
