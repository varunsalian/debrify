# Search screen incremental refactoring plan

Status: implementation started on `refactor/search-screen`; the automated baseline
and phases 1–3 are reviewed. Phases 4A catalog and 4B keyword extraction are
implemented and reviewed; phases 4C–8 remain in progress. The delivery batches
below govern remaining work. Device/performance acceptance remains pending.
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

Work one cohesive workflow at a time, from easy to complex. A batch may move related
methods, state, and callers together, but must not rewrite the whole screen or
start a general architecture framework. Do not combine this work with redesigns,
feature removal, content-provider
changes, storage migrations, dependency upgrades, or an app-wide state-management
migration. Riverpod DI/state management is an explicit part of each applicable
extraction; unrelated features retain their current state machinery.

Completion means all responsibilities from the five-file library have a coherent
owner, not just that `search_screen.dart` has become shorter. The completed source
set includes every extracted component, wherever placed, and any retained facade.
Existing external services and small call-site edits in `main.dart` remain outside
the structural size target; relocating old screen logic there is not an exemption.

## Remaining delivery plan — revised 2026-09-28

This section governs remaining execution and verification cadence. The numbered
phases below remain the scope/acceptance map; their historical small-slice examples
and evidence are not instructions to repeat that process. Preserve all completion
criteria. Optimize elapsed time and token use by completing cohesive workflows,
reusing verified work, and checking the risks actually affected.

Initial recovery checkpoint completed: series-resume resolver compilation errors
are fixed; cancellation remains distinct from the S1E1 fallback. The resolver's
ownership/capacity checks and affected tests pass. See the latest workflow entry
in the evidence document; the larger Home actions batch remains in progress.

| Batch | Remaining deliverable | Acceptance gate |
| --- | --- | --- |
| A — Home actions and resume | Finish series-resume cache ownership/capacity; migrate remaining Continue Watching/tracker playback and removal actions, detail/source-edit preparation, and accepted history-deletion sequencing. | Production callers use bounded action/data owners; resume precedence, launch arguments, actual profile-owned writes, sync/recovery records, and cancellation behavior are covered. No duplicate legacy implementation or unfinished resolver changes remain. |
| B — Sources integration | Finish legacy manual/automatic binding and provider-operation boundaries, including the remaining transitive persistence/native checks. Reuse the standalone Sources view and existing adapters. | Binding, copy, pin/unpin, local selection, playback and download flows preserve their contracts; stale operations cannot write into another profile. Run affected native checks and the first combined A+B full-suite gate. |
| C — Feature presentation and navigation | Finish Search focus/mode/navigation wrappers, Home layout action/navigation ownership, and Discover detail/preview boundaries. Compose actual Home/Search/Discover feature views. | All existing tabs, search modes, enabled layouts, touch/remote paths and return-focus contracts retain coverage; business operations stay outside presentation. No giant state bundle or replacement controller. |
| D — Lifecycle and entry point | Finish shared preview/player eligibility, route/app callbacks, snapshots, timers/listeners, native teardown and remaining composition wiring. Reduce the original entry point to a routing/composition facade. | Explicit resource ownership and teardown order; retirement/overlap coverage; facade at most 300 lines; completed handwritten source files at most 800 lines. Run the second combined C+D full-suite gate. |
| E — Final acceptance | Close the responsibility map and temporary exceptions; enforce architecture/size checks in CI; complete the supported-device and performance matrix. | Every completion criterion below has actual evidence, including final-revision automated checks and device/performance results. Unavailable checks stay pending; no zero-regression guarantee or unsupported completion percentage. |

A batch is a delivery unit, not permission for an unreviewable rewrite. Use a few
cohesive, independently reversible commits when needed; do not create a checkpoint
for every helper. A–D may overlap only where dependencies and file ownership are
independent. Do not re-extract completed components merely for naming symmetry.

Before each batch, identify its remaining production entry points, destination
owners and affected test groups in one short checklist. Complete one end-to-end
workflow at a time within that batch, with a compiling, focused-tested checkpoint
before starting another. In A, for example, finish resume first, then action
dispatch, then deletion/persistence. Apply analysis and architecture checks at
these workflow checkpoints too; do not leave several unrelated workflows broken
until the batch ends. This replaces per-helper checkpoints, not incremental safety.

### Verification budget and regression safeguards

- At batch start, list affected contracts and choose existing test groups. Reuse
  baseline evidence when its revision, relevant code/dependencies, SDK and settings
  still apply; establish a fresh baseline only for uncovered or invalidated areas.
- During the batch, use fast focused tests for meaningful edits. At its checkpoint,
  format changed code, run analysis, the architecture guard and all affected tests,
  then review production wiring, removed code, ownership and error paths once.
  Review fixes only where they change the prior conclusion.
- Add tests for uncovered behavior or risk: ordering, cancellation, concurrent
  actions, actual profile writes, focus and resource cleanup. Reuse fixtures and
  integration tests. Mechanical relocation with existing coverage does not need
  new per-method tests or a bespoke old/new comparison harness.
- Run the full suite after A+B, after C+D, and at final acceptance. Reuse the last
  full run if it already covers the exact final application/test revision and
  configuration. Run earlier for shared-infrastructure changes with broad impact,
  unexplained failures or gaps in targeted coverage; record the reason briefly.
  A stalled or interrupted run is incomplete evidence. Inspect the live process
  and last test, retain its logs, then isolate that test before a justified rerun;
  never run competing full suites or infer success from partial counts.
- Compare test outcomes and analyzer identities, not just totals. Never weaken
  guards, lower thresholds, change the failure allowlist, or accept a newly failing
  previously passing test. Stop dependent work to investigate a new regression.
- Native/persistence/lifecycle changes need relevant integration/device checks in
  their batch; do not postpone a known high-risk boundary to the final audit.
  Schedule the remaining device matrix together to avoid repeated setup. Reuse
  device evidence only while the exercised behavior and configuration are unchanged.
- Before further loading, layout or preview changes, capture the missing relevant
  performance/device baseline using a fixed dataset and configuration. Keep a
  separate checkout of the original baseline where needed for final before/after
  comparison. A current checkpoint can measure subsequent changes only; it cannot
  prove parity for earlier work. Record the reference revision and exercise the
  same scenario after changes; final acceptance must not discover a missing
  baseline that could have been captured earlier.

### Architecture, coordination and reporting

- Riverpod remains the DI/application-state choice. Keep local UI state local and
  pure policies as functions. Add providers, interfaces and files only for real
  dependency, lifetime or responsibility boundaries. Aim for at most 300 lines;
  accept cohesive 301–500-line components rather than splitting solely for size.
  Short components are welcome when useful; retain the 800-line ceiling and review
  requirement for 501–800-line files.
- Preserve behavior while moving code. Separate necessary bug fixes or capacity
  policy changes into explicit reviewed changes; log unrelated cleanup without
  expanding this migration. Do not redesign storage, HTTP clients or native engines.
- Limit legacy-service audits to calls reachable from migrated workflows and their
  profile/write/resource contracts. Change a legacy dependency only when needed to
  preserve or enforce those contracts, with affected regression coverage. Do not
  refactor whole external services or engine internals merely because an adapter
  calls them; record unrelated debt separately. This does not excuse an unsafe
  reachable write or moving original screen logic outside the measured source set.
- If parallel agents are explicitly authorized, give independent work separate
  file ownership and one integration owner. Shared-screen edits remain serialized;
  do not run competing full suites. Otherwise execute these batches without agents.
- Maintain one short current-status table here and append concise batch evidence
  to `search-screen-evidence.md`: revision, completed workflow, commands/results,
  risks and next deliverable. Retain existing history without rereading or copying
  thousands of evidence lines on each turn; inspect only the relevant sections.
- Report accepted deliverables and pending gates, not line-count percentages or
  test volume as overall completion. If a batch expands, state the concrete blocker
  and adjust its boundary once; do not restart an indefinite micro-extraction loop.

| Batch | Current status |
| --- | --- |
| A | In progress. Resume/cache, history removal, source editing, catalog play, tracker-menu continuation, Stremio TV picker and detail source-binding handoff have focused evidence. Remaining workflows are listed below. The picker full-suite gate completed with 9,889 passes and unchanged baseline failures/skips; see the evidence log. |
| B | Pending remaining boundaries; substantial Sources extraction already complete |
| C | Pending remaining boundaries; substantial layout/search extraction already complete |
| D | Pending remaining boundaries and facade reduction |
| E | Pending final acceptance |

### Batch A remaining action checklist

Close these pending reachable workflows before calling A complete. Completed
removal workflows are recorded in the evidence log; reuse their existing owners
and fixtures; these are workflow boundaries, not requests for one new class
or provider per entry point. Record destinations and evidence as each row closes.

| Remaining workflow / production entries | Required closing evidence |
| --- | --- |
| Detail mutations: `_handleDetailQuickAction`, `_handleDetailSimklQuickAction`, `_handleDetailMdblistQuickAction`, including rating dialogs and clear-progress | Shared reset confirmation/loader ownership is reviewed (52 affected tests), with originating profile captured before confirmation and exact loader cleanup. Rating/list/collection dialog returns and exact Home detail-route guards are now reviewed (67 affected tests pass), with originating scope retained for accepted work. Finish mutation data boundaries and the reset service's transitive write/deletion audit; preserve the reviewed refresh ordering. |
| Catalog action composition: `_onCatalogPlay`, tracker quick-play entries and `_openItem` detail callbacks | Exact detail dismissal/return ownership is reviewed through `HomeDetailRoute`; Resume-label policy and local movie reads now use the injected catalog resolver (122 affected tests pass; its cohesive 513-line policy reviewed). Catalog Play/Sources orchestration now uses the 242-line `HomeCatalogPlayAction` with loader cancellation, promised episode, exact launch arguments and detail-route retirement reviewed (53 affected tests pass). `HomeCatalogPlaybackReaders.prepareMovieRewatch`'s reachable Simkl write is now reviewed (124 affected tests pass), including credential barriers, timeout retirement and accepted-response cache ownership. Cached Trakt quick-play lookup now forwards view/profile guards through credentials, native lookup, pagination and refresh/retry (247 affected tests pass). Trakt live-feed/uncached selection and label preparation are also reviewed (273 affected tests pass), including visibility/history pagination and authentication retirement. Simkl shared episode-cache ownership and guarded paused/next-to-watch preparation are reviewed (223 affected tests pass), retaining coalescing across independently retiring consumers. Legacy/merged layout construction now uses a 154-line feature builder (69 affected tests pass). The 106-line `HomeDetailMenus` also owns opening snapshots and live menu assembly (76 affected tests pass). Detail status, recommendations and metadata now use injected captured-profile readers with route-result retirement (89 affected tests pass). Stremio recommendation/metadata cache invalidation and late publication are now guarded and reviewed (15 cache tests; completed full run plus repaired relocated rewatch assertion). Trakt detail status now forwards route/profile guards through authentication, list/watched requests and library-cache publication (153 affected tests pass). MDBList detail status and shared resolution/dropped snapshots now retain profile ownership, guard credential/transport continuation, and fence invalidated in-flight publication (167 related checks plus the 12-case focused ownership suite pass). Finish opening orchestration and addon-inventory persistence; mutation/reset contracts remain in the separate row. |

Resume/cache, hold/menu, accepted local deletion, source editor, Stremio TV picker
and detail/source-binding dispatch checkpoints already have evidence; reopen them only for a discovered defect or an
invalidated contract. Shared resource/snapshot teardown remains D, and final
platform/performance acceptance remains E. Capture relevant device/performance
baselines before the loading/layout/preview changes that would invalidate them.

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

Use this responsibility map to prevent gaps. Group related rows into cohesive batches while
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
| Original `_SourcesScreenState`, season selection, addon retry, pin/unpin/local source operations | `lib/features/sources/presentation/sources_screen.dart` (678 lines), bounded presentation helpers and Sources application/data; remaining bridge/native audits are tracked below | 4C |
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

## Original phase scope and implementation evidence

The phases below define responsibilities and retain implementation history. Use
the revised delivery batches above for remaining work and verification cadence.
Adjust a boundary if inspection reveals tighter coupling; record the reason once.

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

First slice implemented and reviewed: the four sequential Home catalog preference reads
(disabled rows, extra rows, row order and hero source) now use an injected stateless
repository. Initial loading and settings refresh both use it, preserving read
order, error propagation and the existing caller-owned retirement/commit checks.
The shared hero/extra-row value declarations move out of the storage service with
compatibility exports. `lib/screens/search_screen.dart` (20,130 lines before this
slice) temporarily retains board state, collection reads, refresh comparisons and
loading/pagination/lifecycle orchestration for the rest of phases 5–7.
`lib/services/storage_service.dart` (10,821 lines) remains an existing storage
boundary; this slice only relocates its pure Home value declarations and adds a
compatibility import/export. No unrelated storage logic or whole-file formatting
is authorized by this exception. The completed Home components still must meet the
plan's final size, ownership, profile and performance gates.

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

Catalog-preference checkpoint: `home_catalog_preferences_repository.dart` (31 lines)
performs the original sequential reads and returns a defensive, immutable
`HomeCatalogPreferences` (23 lines). The 15-line Riverpod dependency factory wires
the existing storage methods and declares its scopeable leaf dependency. The shared
hero-mode/hero-source/extra-row types now live in `lib/models/home_preferences.dart`
(eight lines), with unchanged declarations and a StorageService compatibility
export. No schema, defaults, enum order or parser behavior changed. The model is
registered in the migration guard. Collection loading/signatures, Home state,
refresh comparisons, deadlines, generation/profile checks and tracker fan-out stay
at their original locations for subsequent extraction; repository readers retain
the existing storage scope semantics and do not cache profile data.

Seven repository tests cover sequential barriers, reader errors, ordering,
immutability/fresh reads and overlapping requests. Two real SearchScreen tests use
a provider override to verify initial loading and settings refresh, plus disposal
during a pending read and listener removal. The initial new test had an untyped
empty record-list compiler error; its explicit String element type fixes it. An
unnecessary test import was narrowed. Final targeted comparison: 239 passes versus
230 before, identical 12 failure identities and one skip. Analyzer identities are
unchanged at 863; architecture checks pass for 182 migrated files. Full suite:
8,324 successes, unchanged 51 failures/20 skips, every preceding outcome preserved
and nine new successes. Evidence: `.git/refactor-evidence/phase5/catalog-preferences-*`,
`analyze-catalog-preferences-*`, `full-catalog-preferences*`. Legacy files were not
mass-formatted. This completes only the preference-read boundary; catalog loading/
paging state ownership, snapshots, tracker behavior and device/performance gates
remain open.

Catalog inventory planning now uses the 34-line pure
`application/home_catalog_plan.dart` and 19-line `models/home_catalog_plan.dart`.
The production loader supplies the same disabled/collection-claimed IDs and the
saved order only when the existing Home-order predicate is active. Required-search
catalogs stay excluded; optional-search catalogs remain browsable. Existing
HomeRowOrder policy preserves ranked/unranked behavior and source order for other
variants. There is no global row cap or new deduplication. The addon lookup retains
the first configuration per ID, including addons with no surviving board rows.
Read-only result containers retain original manifest identities for existing row
reuse; this is not a deep clone or new owner of mutable item/page state.

The old enumeration/map-building bodies and private row-ID helper are removed;
three progressive/refresh/pagination consumers use the same extracted row-ID
function. Cursor reservation, generation checks, collection-claim policy, snapshots,
requests and publication ordering remain at their existing ownership points.
Review found that the addon map also serves Discover, so its later migration must
preserve that shared behavior. The legacy screen is now 20,120 lines, with its
remaining state/presentation responsibilities still covered by the phase exception.

Six new tests cover catalog identity filtering, source/saved order, first-addon
lookup across configurations, uncapped/repeated references and read-only containers.
Targeted comparison: 245 successes, identical 12 failure identities/one skip;
analyzer identities unchanged at 863. Architecture checks pass for 184 migrated
files. Full suite: 8,330 successes, unchanged 51 failures/20 skips, every prior
outcome preserved and six new successes. Evidence:
`.git/refactor-evidence/phase5/catalog-plan-*`, `analyze-catalog-plan-*`,
`full-catalog-plan*`. Batch fetching and catalog/pagination state ownership are next;
Home/device/performance and the full migration gates remain open.

Catalog batch access now uses a 54-line plain `data/home_catalog_repository.dart`
and a 15-line Riverpod composition factory. Production addon discovery and parallel
row fetching use the injected repository; the replaced inline fetch loop is removed.
The repository reuses `loadHomeCatalogSection`, including cached-row identity,
raw cursors, filtered-window bounds and resumable empty rows. Rows still publish in
completion order and return in source order; each row reads the watched predicate
separately. Existing per-row request and publication errors remain isolated.

The screen captures the stateless dependency during initialization. Pending refresh
loops may reach another batch after disposal, so they must not read a disposed Ref.
Cursor reservation stays synchronous and guarded by the existing generation; the
caller retains profile/mounted checks. `Future.sync` preserves early error wrapping
without adding another async adoption boundary around the repository's existing
batch completion. This is an intermediate data extraction, not completed ownership
of board state: cursor/generation, committed snapshots, refresh and pagination still
need their phase-5 application boundary. The shared Discover addon lookup must keep
its existing behavior. SearchScreen remains under the documented temporary exception.

Eight repository tests cover parallel completion/order, failed/empty neighbors,
cached identity/cursors, retirement before/during requests, filtered raw windows,
per-row predicate reads and callback-error isolation. A real SearchScreen test
verifies the provider override serves discovery/fetching and that a pending result
completes safely after removing the screen and its ProviderScope. Its initial fixture
omitted a required catalog name; a later wait stalled on the widget test's fake async
queue. The corrected fixture pumps that queue until the observed request starts.
The analyzer's new test-only brace diagnostic was also fixed. Targeted result:
254 successes versus 245 before, identical 12 failure identities and one skip.
Analyzer identities remain 863; size/import checks pass for 186 migrated files.
Full suite: 8,339 successes, unchanged 51 failures/20 skips; every preceding
outcome is preserved and all nine new tests pass. SearchScreen is 20,110 lines.
Evidence: `.git/refactor-evidence/phase5/catalog-batch-*`,
`analyze-catalog-batch-*` and `full-catalog-batch*`.
The remaining Home, device/performance and full migration gates remain open.

Catalog inventory/cursor ownership now moves into the 68-line
`application/home_catalog_controller.dart`, backed by the 33-line immutable
`models/home_catalog_state.dart`. Its 25-line session key identifies the originating
profile epoch and one view, with optional immutable bootstrap data. The auto-disposed
Riverpod controller owns references, synchronous reservations and the accepted
`HomeBoardSnapshot`; it does not fetch, persist, navigate or retry. The screen's
manual subscription retains state while mounted, including covered routes, without
adding broad rebuilds. Its compatibility getters read the single controller state;
there is no duplicate mutable inventory or cursor. The shared Discover metadata map
stays in the screen and is restored from the same accepted snapshot as before.

Production initialization, refresh, progressive acceptance, vertical reservations,
timeout recovery and cached returns all use this owner. Generation/profile acceptance,
loading flags, row publication, route/focus decisions and the batch workflow remain
in the screen for the next phase-5 slices. After provider disposal, pending legacy
loops see an exhausted inventory and cannot read or mutate disposed Riverpod state.
The screen is temporarily 20,122 lines: initialization and compatibility adapters
remain until workflow extraction; this checkpoint establishes ownership rather than
claiming the screen has met its final size target.

Six controller tests cover disjoint bounded reservations, overlapping-refresh
recovery, progressive commit points, immutable containers, separate views/profile
epochs, disposal and construction-time return snapshots. The real SearchScreen
provider-override test now observes the reserved state before a pending request and
verifies no publication after disposal. Review caught five previously passing cached-
return tests regressing: restoring state during initState tried to modify a provider
while Flutter was building, and the legacy load aggregator swallowed that error.
A diagnostic run confirmed the cause. Return state now seeds provider construction,
without delaying the first frame or replaying requests. All 24 existing progressive
pagination/return tests plus six new controller tests pass after that correction.
A test fixture's initial record-to-session constructor mismatch was also corrected;
raw failing runs are retained. Analyzer identities remain unchanged at 863;
size/import checks pass for 189 migrated files. Targeted Home comparison: 260
passes versus 254 before, identical 12 failure identities and one skip. Full suite:
8,345 successes, unchanged 51 failures/20 skips, all previous outcomes preserved
and six new successes. Evidence also includes `full-catalog-state*`.
Evidence: `.git/refactor-evidence/phase5/catalog-state-*` and
`analyze-catalog-state-*`. No full-phase or device/performance completion is claimed.

Catalog batch orchestration now lives in `HomeCatalogController` (128 lines).
Its declared Riverpod dependency supplies the existing plain repository; the screen
no longer imports or stores that repository. Addon discovery, synchronous batch
reservation/fetching and the empty/excluded-batch continuation loop use the controller.
The two small view adapters only capture generation/profile/mounted acceptance and
route-continuation policy. The old loop and repository wiring are removed from the
screen, now 20,112 lines under its existing phase exception. Generations, loading
flags, full-load/tracker orchestration and accepted row publication still await their
subsequent bounded migrations.

Review preserved one `Future.sync` around reservation and the original single async
continuation loop, without adding adoption steps in the view adapters. Batch commits
still happen after acceptance and before exclusion filtering; a non-empty accepted
batch returns before checking whether a covered route may continue. Empty covered
batches retain their cursor for the later resume. Catalog row IDs use the same
addon/type/catalog identity; the repository produces catalog rows, while list and
collection identities remain with their separate view paths. The controller rejects
work after disposal, and production callbacks retain the original profile/generation
checks. Provider construction starts no requests and automatic retries remain off.

Six new workflow tests cover empty/excluded batches and commit order, pause/resume,
retirement with a replacement inventory, disposal, rejected reservation, and explicit
parent/two-child scope overrides with independent repositories/cursors. The preceding
controller tests and real SearchScreen override/disposal test also pass. Targeted
Home results: 266 passes versus 260 before, identical 12 failure identities and one
skip. Analyzer diagnostic identities remain unchanged at 863; architecture checks
pass for 189 migrated files. Full suite: 8,351 successes, unchanged 51
failures/20 skips; every preceding outcome is preserved and six new tests pass.
Evidence: `.git/refactor-evidence/phase5/catalog-workflow-*`,
`analyze-catalog-workflow-*` and `full-catalog-workflow*`.
The complete phase-5 and overall native/performance/CI gates remain open.

Catalog request ownership now moves into `HomeCatalogController` (174 lines).
The screen's generation, refresh and vertical-page fields are replaced by read-only
controller accessors. The controller starts/finishes refreshes and pages, retires a
timeout generation, and rejects stale batches internally. A stale retirement returns
no completion token, so it cannot authorize cleanup of a newer refresh. Disposal and
provider recomputation retire pending work. Profile/mounted acceptance remains an
explicit caller predicate; generation identity alone is not treated as profile safety.

`HomeCatalogState` (47 lines) publishes immutable refresh/page flags alongside its
inventory/cursor/snapshot. Fresh Home's initial refreshing flag is seeded through
`HomeCatalogSession` (27 lines); beginning that first request changes only its private
request generation and emits no provider update during initState. Cached returns and
Search/Discover variants start idle. Refresh start clears a superseded page's loading
flag; stale finalizers cannot clear flags owned by a newer operation. Existing view
setState, profile guards, progressive/deferred publication, timeout recovery and
focus decisions keep their current timing and locations. SearchScreen remains
20,114 lines under the phase exception; the full-load pipeline and independent Home
responsibilities still need extraction before this phase can be complete.

Six new ownership tests cover initial notification timing, overlapping load/page
finalizers, timeout retirement, superseded batches even with an externally true
predicate, cached recovery and provider recomputation. Earlier workflow tests now
pass the real generation token and retain their assertions. The actual SearchScreen
provider-override/disposal test and targeted Home regressions pass: 272 successes
versus 266 before, identical 12 failure identities and one skip. A missing brace pair
and unused test import from this slice were fixed; analyzer diagnostic identities
are unchanged at 863. Size/import checks pass for 189 migrated files. Full suite:
8,357 successes, unchanged 51 failures/20 skips; every preceding outcome is preserved
and six new tests pass. Evidence: `.git/refactor-evidence/phase5/catalog-ownership-*`,
`analyze-catalog-ownership-*` and `full-catalog-ownership*`. Device/performance and overall completion gates
remain open.

Home configuration access/decisions now have explicit boundaries. The 25-line
`data/home_collections_repository.dart` and 15-line Riverpod factory supply collection
reads and signatures to both loading and settings refresh. The old screen helper is
removed. Reads retain the existing failure log and empty fallback; returned containers
are read-only while legacy collection identities remain borrowed. Signature calls
forward the existing worker-isolate implementation directly, preserving its Future
and error behavior. The screen captures the stateless dependency while mounted, so
pending reads/hash calls do not resolve a disposed Ref. Store session guards and the
existing await/commit positions remain unchanged.

The 65-line pure `application/home_configuration_changes.dart` owns reload decisions.
Disabled rows, watched state, collection changes and board extras retain their reload
rules; row-order/hero-only effects still depend on the Home variant. Board reload
continues to take precedence over hero resolution, and IPTV reload stays independent.
Extra-row IDs, titles and order are compared within each family, so moving an IPTV
row across a tracker row alone remains a no-op. Saved order and hero IDs are not
normalized. Review preserved the old hide-watched comparison snapshot from before
collection hashing; other comparisons still read accepted settings after hashing
and request/session validation. The screen now only commits the accepted values and
dispatches the selected effects. It is 20,080 lines under the existing phase exception.

Three repository tests cover fresh immutable containers, failed-read recovery and
unchanged signature Future/error propagation. Six policy tests cover equality,
per-family title/order changes, tab variants, full-reload causes, effect precedence
and duplicate/order-sensitive IDs. The real SearchScreen override test now verifies
collection read/hash order before addon discovery. The new fixture's default record
list needed an explicit const, and the extracted comparison left an unused shown
import; both were corrected. Targeted Home: 281 passes versus 272 before, identical
12 failure identities and one skip. Analyzer identities remain unchanged at 863.
Full suite: 8,366 successes, unchanged 51 failures/20 skips; all previous outcomes
are preserved and nine new tests pass. Architecture checks pass for 192 migrated
files. The changed feature/test files pass formatting checks. Evidence:
`.git/refactor-evidence/phase5/collections-access-*`, `analyze-collections-access-*`,
`full-collections-access*`. Full-load orchestration, independent Home responsibilities
and overall device/performance/CI gates remain open.

Accepted Home configuration now lives in the catalog application state. The
24-line `HomeBoardConfiguration` groups the existing immutable catalog preferences,
collection container/signature and hide-watched value. Seven mutable widget fields
become read-only accessors; initial-load and settings-refresh acceptance replace one
configuration value only after their existing guards. Catalog state (53 lines) retains
that value across reservation, snapshot recovery and loading-flag changes. The
controller remains 183 lines, with one explicit configuration-acceptance action.

The in-memory Home return record carries this immutable configuration instead of
separate shallow container copies. Its legacy collection objects retain the same
borrowed identities; no persisted schema changes. The existing return-cache profile,
revision and age gates are unchanged. The session's construction data (30 lines)
seeds accepted cached configuration before the first frame, together with the board
snapshot. Cold defaults still capture hide-watched and the empty collection signature
at State construction; the new const empty preferences constructor preserves the
original random-hero default. Bootstrap data is not another mutable state owner.

Review checked the initial-load ordering and comparison timing: code after awaits
still reads the current accepted configuration through the same view accessors, and
the settings path still captures the previous hide-watched value before hashing.
This prepares the remaining load orchestration to move without freezing live inputs
at an earlier point. The screen is 20,063 lines and remains under the existing phase
exception; render/focus state and full-load orchestration are not declared migrated.

Five tests cover defensive containers, atomic publication/old snapshots, preservation
through refresh/paging/timeout recovery, construction-time return state, and separate
views/profile epochs/disposal. The real SearchScreen integration test observes the
accepted configuration from the injected collection signature. All 24 existing
pagination/cached-return tests pass. Wider targeted Home results: 286 successes
versus 281 before, identical 12 failure identities and one skip. Analyzer identities
remain 863; architecture checks pass for 193 migrated files. Full suite: 8,371
successes, unchanged 51 failures/20 skips; every preceding outcome is preserved
and five new tests pass. Changed feature/test files pass formatting checks.
Evidence: `.git/refactor-evidence/phase5/configuration-state-*`,
`analyze-configuration-state-*`, `full-configuration-state*`. Full phase and overall
device/performance/CI/size gates remain open.

The initial Home data sequence now runs in the 177-line application operation
`HomeBoardLoad`, with a 34-line plain `HomeBoardServices` contract and 25-line Riverpod
factory. It reads preferences/collections/signature in order, accepts configuration,
starts independent tracker previews, performs the bounded watched-snapshot wait,
plans catalog inventory, fetches initial/refresh batches, and assembles completed
row families. The old inline sequence, single-batch wrapper and collection-row
builder are removed from SearchScreen. Its changed `_load` method was formatted
in isolation; the whole legacy file was not formatted. SearchScreen is 19,984 lines.

The operation owns only transient tracker rows and its catalog-phase-finished flag;
accepted configuration/inventory remain in the existing controller. The view calls
`finish` in its original finally position after disposing progressive publication.
Late tracker updates remain eligible after catalog failure while their captured
request is current. Small synchronous callbacks retain shared Discover addon lookup,
hero launch, commit points and visible-row/focus handling. The deadline wrapper,
timeout recovery and presentation error handling remain in the view for subsequent
work. Provider construction starts no work; tracker/watched services retain borrowed
lifetimes and existing concurrency/retry policies.

Review preserved the async completion boundary by returning the operation Future
from the deadline callback without another await. Initial and refresh-tail batches
keep their existing acceptance-capture points. Accepted settings and saved-order
policy stay live across awaits. Review also found that tab mode must stay live:
`isHome` is a callback, rather than a boolean frozen at operation creation. Collection
claiming and final collection-row composition therefore still follow current mode.
Progressive reset/inventory snapshots commit cursor zero before any batch reserves;
nonprogressive rows remain pinned collections, retained lists, ordinary collections,
then catalogs. The 1,500ms watched wait and refresh vertical extent are unchanged.

Nine new operation tests cover read/publication order and row families, retirement
during hashing/watched waiting, exact watched timeout, live settings/tab mode,
late trackers after failure, refresh extent across empty batches, and progressive
commit points. The original focused feature/progressive/return run had 111 passes;
the final wider Home run has 295 passes versus 286 before, identical 12 failure
identities and one skip. The initial fake-clock fixture barrier was created outside
its fake zone; the timing test now uses Flutter's built-in clock and no new package.
A format-exposed brace lint was fixed. Final analyzer identities remain unchanged
at 863; architecture checks pass for 196 migrated files. Final full suite: 8,380
successes, unchanged 51 failures/20 skips; every preceding outcome is preserved
and nine new tests pass. New feature/test files pass formatting checks. The earlier full run was
started before the live-tab review correction; final verification uses the separate
`full-board-load-final` receipt. Evidence: `.git/refactor-evidence/phase5/board-load-*`,
`analyze-board-load-*`, `full-board-load*`. Remaining Home state/publication, horizontal
pagination, independent continuation/tracker responsibilities and final native,
performance, CI and size gates remain open.

Horizontal catalog data access now uses `HomeCatalogRepository.fetchRowPage`,
reached through the existing scoped Home controller. The production row-pagination
caller no longer invokes Stremio or reads watched filtering directly. The repository
captures existing IDs and the filter once, delegates to the existing filtered pager,
and checks the caller's live row/profile eligibility before every raw request.
It returns the pager Future directly, preserving the completion boundary. No new
retry, cache, provider lifetime, mutable state owner or dependency library is added.
The controller is 198 lines, repository 75, and SearchScreen 19,976.

Review retained row identity rather than board-generation cancellation: refreshing
an unchanged catalog intentionally reuses its row and its in-flight horizontal
page. The view still rejects removed rows, catalog-search detours and profile
changes after the await; it retains loading flags, error/retry handling, focus-node
growth, deferred Right completion and Android TV's silent initial spinner update.
Those mutable legacy rows and publication responsibilities remain phase-5 work;
this data boundary does not claim to finish horizontal state migration.

Four new tests cover scoped injection, raw skip/filter/dedup behavior, cancellation
between filtered windows, disabled-filter termination and propagated errors without
mutating caller inputs. Existing real-screen tests verify interrupted return paging,
profile-session rejection and seven rows inserted above a pending catalog. The
fresh Home baseline was 295 successes / 12 failures / one skip; after extraction,
299 successes with identical failure identities and skip. Analyzer identities are
identical at 863, and size/import checks pass for all 196 migrated files. Evidence:
`.git/refactor-evidence/phase5/row-page-*`, `analyze-row-page-*`, `full-row-page*`.
Full suite: 8,384 successes / unchanged 51 failures and errors / 20 skips. Every
previous checkpoint outcome is preserved and the four new tests pass. Device and
performance checks, remaining Home responsibilities and later phases remain open.

Home's accepted row inventory and horizontal paging mutations now belong to the
existing `HomeCatalogController` (258 lines). SearchScreen's mutable `_homeSections`
field is removed; its getter borrows the controller's read-only row container.
Replacement copies the container while retaining row identities. The controller
owns loading eligibility/latches, accepted raw cursor and pause/exhaustion metadata,
and item append. The view retains its live identity/profile/query acceptance check,
focus-node allocation before append, TV spinner suppression and repaint dispatch.
The controller does not introduce board-generation cancellation for retained rows.

This deliberately uses revision-bearing state for mutable legacy models:
`HomeCatalogState.rowsRevision` changes on row actions, while mutable CatalogSection
objects are never placed in published Riverpod state. Previous state objects remain
unchanged. Presentation borrows row objects and no longer writes their paging fields
or item lists. The existing manual subscription still retains the provider while
covered without triggering extra screen rebuilds; later presentation migration can
subscribe narrowly to this revision. There is one accepted row inventory, with the
visible `_sections` list remaining the Home-or-search presentation projection.

Return rows seed the provider at construction, avoiding initialization-time state
writes. The 31-line `copyHomeRowForReturn` policy replaces the old inline clone and
is used for both controller-owned rows and the hero snapshot. It detaches item lists
and resets loading latches, retaining raw cursor, pause/exhaustion, query and special
collection/tracker row types. A retired operation can release its old loading latch
without notifying a disposed provider or appending new data.

Eight new tests cover container ownership and row identity, pause/resume/exhaustion,
revision publication with focus-before-items ordering, detached return snapshots,
synthetic row dispatch, cached bootstrap/independent views, provider recomputation
and disposal. Review found that dependency recomputation must retain accepted rows
instead of replaying the bootstrap; one-time initialization and a regression test
now preserve that pre-existing view-owned behavior. The existing
feature/progressive/return screen run passed all 124 tests before these additions;
final wider Home run has 307 successes versus 299 before, identical 12 failure
identities and one skip. A newly exposed brace lint was fixed; final analyzer matches
all 863 baseline identities. Size/import checks pass for 197 migrated files and
changed feature/test files pass formatting. SearchScreen is 19,956 lines. Evidence:
`.git/refactor-evidence/phase5/row-state-*`, `analyze-row-state-*`, `full-row-state*`.
Final reviewed full suite: 8,392 successes / unchanged 51 failures and errors /
20 skips. Every prior checkpoint outcome is preserved and eight new tests pass.
The earlier full receipt predates the recomputation correction; completion evidence
for this slice is `full-row-state-reviewed`. Deferred publication, vertical merge orchestration,
continuation/tracker data, layout ownership and all remaining native/performance/CI
and final size gates remain open; this checkpoint does not complete phase 5.

Local Continue Watching's storage/progress join now lives in the injected
`HomeLocalContinuationRepository` (138 lines), returning the 29-line immutable
`HomeLocalContinuation` value. The 18-line Riverpod factory borrows existing
StorageService/Stremio operations; repositories receive plain callbacks, no Ref
or UI context. The production view reads progress-source/enabled settings through
this dependency and delegates history, optional custom-addon discovery, sequential
movie/episode progress reads and result assembly. Raw stored maps stop at this
adapter. No cache, retry, write, storage schema or package change is introduced.

The view still owns its load token, merged-row setting wait, live-state assignment,
focus-node synchronization, artwork dispatch and autofocus. Metadata results preserve
history order, missing-value defaults, finished-series progress, clamping, remaining
minutes, positive episode references and custom/native identities. The existing
season/episode label helper moved unchanged into the shared pure continuation
utility; tracker callers use it too. That 73-line shared source is now measured by
the architecture guard. Read-only result containers are safe for existing consumers:
See All derives and sorts its own list instead of mutating the supplied snapshot.
The changed local-loading method was formatted in isolation. SearchScreen is 19,884
lines; remaining row state and other Home/Discover/presentation responsibilities
retain their previously documented extraction milestones.

One intentional retirement hardening accompanies this boundary: current ownership
now combines view lifetime, local request token and the captured profile owner.
It is checked before/after settings and between history/addon/playback reads, before
the merge-setting continuation, on publication, and for late artwork acceptance.
A superseded/disposed/profile-retired load returns no partial result and does not
start the next implicit profile read. Previously this local path only checked its
view/token at the outer publication points. This does not claim that unrelated
tracker/IPTV or merge-setting internals have completed their ownership migration.

Eight repository tests cover data joins, immutable containers, native/custom
identity, retirement at each read boundary and propagated errors. Four actual-screen
tests verify injected initial loading/display, disabled short-circuiting, profile
handoff and disposal while a playback read is pending. The expanded Home plus
continuation/custom-series baseline had 322 successes / 12 failures / one skip;
after extraction it has 334 successes with identical failure identities and skip.
Analyzer matches all 863 baseline identities. Architecture checks pass for 201
migrated files; changed feature/test/shared utility formatting checks pass. Evidence:
`.git/refactor-evidence/phase5/local-continuation-*`,
`analyze-local-continuation-*`, `full-local-continuation*`. Full suite: 8,404
successes / unchanged 51 failures and errors / 20 skips. Every previous checkpoint
outcome is preserved and twelve new tests pass. Local application-state migration,
remaining Home data and deferred
publication, native/performance verification and all later phases remain open.

Local Continue Watching now has one scoped application-state owner: the 86-line
`HomeLocalContinuationController`, 43-line immutable state and 21-line profile/view
session key. The screen's enabled flag, movie/series/all lists, progress/episode/
remaining-time/identity/addon maps, selected progress source and request counter
are replaced with read-only controller projections. The data value has an empty
constructor; no competing screen copy of accepted continuation data remains.

The controller performs the existing ordered settings/data reads and merge-setting
wait, retaining partial progress-source updates and old rows on a failed refresh.
It disables automatic provider retries, starts reads only from an explicit load,
and checks request generation, mounted provider and originating profile ownership.
The view adds its own lifetime predicate. Dependency recomputation and disposal
retire pending work; distinct views and explicit child scopes own independent
state. A manual subscription keeps this view's state alive while covered and closes
with its other subscriptions. No navigation or Flutter UI dependency is introduced
in application/data code, and no extra DI or persistence system is added.

Synchronous callbacks retain the original presentation ordering: source-setting
repaint, focus-node synchronization before row publication, then artwork clearing,
optional artwork enrichment and autofocus. Disabled rows skip data/merge reads and
autofocus. The screen returns the controller Future directly without another async
wrapper. Late artwork uses the same request/profile eligibility closure, and a
presentation callback that retires the request cannot cause stale publication.
The view still owns artwork resources, shared merge-setting loading and focus.

Ten new controller/scope tests cover ordering, disabled refresh, overlapping loads,
failed refresh/no retries, disposal/recomputation/profile retirement, callback
retirement, independent views and explicit nested overrides. The real-screen test
also verifies that local-completion refresh retains the exact focused card node.
Its first expanded fixture triggered platform image caching; it now uses native
fixture identities without automatic IMDb artwork and distinguishes the focused
card label from the hero's duplicate label. All four screen scenarios pass. These
fixture failures are retained in evidence; production image behavior was not changed.
The expanded affected run has 344 successes versus 334 before, identical 12 failure
identities and one skip. An unused fixture import was removed; final analyzer
matches all 863 identities. Architecture checks pass for 204 migrated files, and
changed feature/test formatting and diff checks pass. SearchScreen is 19,837 lines.
Evidence: `.git/refactor-evidence/phase5/continuation-state-*`,
`analyze-continuation-state-*`, `full-continuation-state*`. Final full suite:
8,414 successes / unchanged 51 failures and errors / 20 skips. Every previous
checkpoint outcome is preserved and ten new tests pass. The first full run stalled
on the profile identity-save test; all five tests in that file passed separately
and in the final full run. After the final comparison passed, the redundant first
runner was explicitly stopped; its incomplete output and cancellation receipt are
retained and are not passing evidence. Final verification uses
`full-continuation-state-final`, including the strengthened focus fixture. Other
Home data, deferred publication, layout/native/performance work and remaining plan
phases are still open.

IPTV continuation loading is now independent of navigation/playback. Shared
`IptvCwEntry`/`IptvCwRows` models live in `lib/models/iptv_cw_entry.dart` (44 lines),
and the injected plain `IptvCwHistory` reader lives in
`lib/services/iptv_cw_history.dart` (99 lines). Both are registered in the migration
guard. The legacy `IptvCwRouter` (144 lines) re-exports the models and delegates its
load API; its context-dependent opening/playback bodies are unchanged. Those
presentation paths, raw descriptor use for opening/removal and profile-safe writes
remain explicit phase-7/remaining-Home work; the legacy router is not a new data
layer exception or evidence that playback migration is complete.

Home now uses a 59-line scoped IPTV continuation controller, 52-line typed snapshot
and nine-line Riverpod factory. It borrows the same profile/view session identity
as local continuation, with independent state and request generations. The screen's
IPTV row lists, lookup maps and token are removed. The controller rejects stale,
disposed and profile-retired results, preserves accepted rows on failed refresh,
and publishes only after the view synchronizes its focus nodes. The view retains
repaint/autofocus dispatch and the Search-tab gate, returning the controller Future
directly. Remaining-time calculation now belongs to the typed snapshot.

The reader preserves recency order, first episode per provider/explicit series key,
progress clamping, fallback strings and IPTV's partial/zero/negative numeric episode
labels (which intentionally differ from local IMDb labels). Routing keys and header
values are retained. Loaded row containers, top-level routing maps and header maps
are detached/read-only; legacy descriptor payloads remain for the existing playback
and removal bridge, without claiming all unknown nested payloads are deeply immutable.
The data/controller dependency graph contains no router, screen or Flutter UI import.
No new read, retry, write, storage schema or package is introduced. Outer profile
rejection does not claim that the existing storage service's internal read sequence
or playback/removal writes have completed their ownership audit.

Four history-reader tests, seven controller/scope tests and five actual-screen tests
cover ordering/deduplication, identity/defaults/headers, focus-before-publication,
overlapping and failed loads, disposal/profile/recomputation retirement, explicit
child overrides, initial tab policy and playback refresh. Home preserves its exact
focused card node across refresh; Search performs no IPTV load, while Discover
skips initial loading and loads on playback return as before. Expanded baseline:
346 successes / 12 failures / one skip; after: 362 successes with identical failure
identities and skip. One new test brace lint was fixed; final analyzer matches all
863 identities. Architecture checks pass for 209 files; changed source/test formatting
and diff checks pass. SearchScreen is 19,815 lines. Evidence:
`.git/refactor-evidence/phase5/iptv-continuation-*`,
`analyze-iptv-continuation-*`, `full-iptv-continuation*`. Full suite: 8,430
successes / unchanged 51 failures and errors / 20 skips. Every previous checkpoint
outcome is preserved and sixteen new tests pass. Remaining Home/tracker data,
deferred publication, bridge/native/performance verification and later plan phases
remain open.

#### Shared continuation layout preferences checkpoint

The initial and settings-refresh merge reads now use a 24-line injected repository,
25-line immutable layout model, 12-line scoped Riverpod factory and 66-line
controller under `features/home`. The four mutable screen flags and memoized future
are removed; the screen borrows controller state and retains all eight focus-node
reconciliation calls, their ordering and repaint ownership. It retains the same
profile/view session key as the other continuation controllers and an explicit
subscription until disposal. No preference reads occur during construction.

The four provider keys, concurrent reads, split defaults, shared initial Future,
memoized initial failure and explicit settings-refresh error propagation remain.
Refreshes do not refetch continuation history. Intentional ownership hardening:
newer requests retire slower reads (including an initial read overtaken by settings),
and profile, view, disposal and dependency-recomputation retirement reject results.
Settings reloads also supply their existing generation guard. This does not complete
the profile audit of legacy storage internals or unrelated settings refresh work.

Eight controller tests cover read sharing, typed flags, failures/retry, latest-request
acceptance, four retirement paths and explicit child/sibling isolation. The actual
Home screen test now includes a series beside movies, verifies that merging places
it on a movie-slot focus node, and preserves the original movie's exact focused node
across merge/split without another history read. The expanded fixture initially used
an invalid native series ID and did not wait for its extra asynchronous progress read;
both test issues were corrected, with the unsuccessful receipts retained.

Expanded target baseline: 362 successes / 12 failures / one skip; reviewed result:
370 successes with exactly the same failure identities and skip. Analyzer identities
match at 863; formatting/diff and architecture checks pass (213 files). SearchScreen
is 19,800 lines. Evidence is under `.git/refactor-evidence/phase5/merge-*`,
`analyze-merge-*` and `full-continuation-layout*`. Full suite: 8,438 successes,
unchanged 22 failures / 29 errors / 20 skips; all preceding checkpoint outcomes
are preserved and eight new tests pass. Remaining tracker data/state,
vertical pagination/publication, Home settings/artwork and later native/performance
and feature-retirement gates remain open.

#### Trakt continuation projection checkpoint

Trakt shelf preparation now uses `features/home/models/home_trakt_continuation.dart`
(104 lines): first-ID deduplication across movie/show feeds, progress, episode/artwork
references, remaining minutes and stable merged recency ordering. Split lists retain
feed order; equal/absent timestamps retain movies-then-shows order. Existing lookup
through metadata `progressId` is preserved, including unresolved/native-key behavior;
this extraction does not silently normalize provider identities. Result containers
are detached/read-only, while legacy metadata and playback descriptors retain their
identities. This is not a claim that their nested legacy fields are deeply immutable.

`TraktContinueWatchingItem` moves unchanged to a 34-line pure shared model registered
in the architecture guard. Its service re-exports it for existing callers; the service
implementation remains byte-identical. The production screen invokes the projection
at the original synchronous location. Review reconstructs the old loader exactly
from the new snapshot accesses: authentication, loading/failure branches, waits,
focus reconciliation, artwork dispatch, announcement and bound refresh are retained.
See-All derives a copy before sorting, so read-only lists preserve that consumer.
Trakt request/state ownership, injected data access, profile audit and context-dependent
playback/removal remain subsequent Home/phase-7 work, not completed by this policy move.

Six tests cover cross-feed duplicates, ordering/ties, progress bounds and rounding,
positive episode pairs, legacy identity lookup and read-only detached containers.
Expanded target: 399 baseline successes to 405, identical 12 failures and one skip.
Final analyzer matches all 863 identities. An initial generated-file conflict during
parallel dependency setup was bypassed with `flutter analyze --no-pub`; the subsequent
unused model import was removed. Both intermediate receipts are retained. Formatting,
diff and architecture checks pass (215 files). SearchScreen is 19,748 lines. Evidence:
`.git/refactor-evidence/phase5/trakt-projection-*`, `analyze-trakt-projection-*`,
`full-trakt-projection*`. Full suite: 8,444 successes, unchanged 22 failures / 29
errors / 20 skips; all preceding outcomes are preserved and six new tests pass.
Remaining Home responsibilities and all later phase gates
remain open.

#### Trakt continuation data-access checkpoint

The screen's Trakt continuation loader now reads the injected
`HomeTraktContinuationRepository` (37 lines), wired by a 17-line scoped Riverpod
factory. A 20-line typed read result distinguishes disconnected shelves from connected
movie/show feeds; a retired operation returns null, while a failed/null feed throws.
The existing authentication call precedes concurrent movie/show reads. There is no
new cache, retry, write or construction-time service call. Containers detach from
service lists; metadata/descriptor identities remain borrowed for the existing
projection and playback contracts.

The view retains synchronous loading/attempt bookkeeping, disconnect focus clearing,
failed-refresh retention, merge-preference wait, row publication, artwork, announcements
and bound refresh dispatch. Intentional profile hardening adds the existing captured
view owner to request eligibility before reads, after asynchronous boundaries and for
late artwork; the repository checks the supplied owner predicate before authentication,
after authentication and before accepting feeds. This does not establish profile safety
inside legacy Trakt services or complete state/lifecycle/playback migration. Accepted
rows, loading flags and resume-throttle state still await application-controller ownership.

Nine repository tests cover no-auth short circuit, concurrent feeds, detached containers,
null/throwing feed failure without retry, and retirement at each boundary. Four actual
Home screen tests exercise scoped injection, focused-card retention on failed refresh,
disconnect clearing, newer-request precedence, profile retirement and disposal. Target
baseline: 405 successes / 12 failures / one skip; after: 418 successes with identical
failure identities and skip. Analyzer matches all 863 identities; changed formatting,
diff and architecture checks pass (218 files). SearchScreen is 19,749 lines. Evidence:
`.git/refactor-evidence/phase5/trakt-access-*`, `analyze-trakt-access-*` and
`full-trakt-access*`. Full suite: 8,457 successes, unchanged 22 failures / 29 errors /
20 skips; every preceding outcome is preserved and thirteen new tests pass. Remaining
Home and later phase gates remain open.

#### Trakt continuation state/request checkpoint

A 102-line scoped Riverpod controller and 20-line immutable state now own Trakt's
accepted snapshot, loading flag, request generation and last-attempt timestamp. The
screen's mutable row/maps/token/loading/attempt fields are replaced by controller
reads; focus nodes, artwork, route/auth/playback eligibility, repaint/announcement
and bound-refresh dispatch remain in presentation. The 30-second resume gate is
unchanged and reads the controller-owned timestamp supplied by the existing view
clock. Requests retain the repository's auth/feed semantics and profile guards.
The wrapper directly returns the controller Future rather than adding an async hop.

The typed family key combines the existing profile/view session with startup loading.
Home and Discover seed loading in provider construction; Search seeds false and skips
startup reads. The first load makes no provider notification during initState. An
explicit subscription retains state while the route is covered and closes on disposal.
Dependency recomputation retires work and resets to idle rather than reseeding an
unowned loading state. Focus reconciliation precedes immutable state publication;
failed refresh retains accepted data and clears only its own loading flag. Disconnect
skips merge preferences and clears shelves without connected-only UI effects. Old
artwork eligibility expires on a newer request, disposal or profile retirement.

Review found that Trakt See-All deliberately keeps its items fixed but borrows a live
progress map. A 26-line read-only `HomeProgressView` now delegates to current controller
data, preserving that contract without copying state into a second mutable owner.
It also covers local progress when selected for the grid, correcting the corresponding
live-map gap from local state migration. Tests verify live replacement/removal and
reject writes; the actual Discover Trakt grid retains a map that sees 50% become 75%
after refresh. Other legacy tracking maps and later playback/route audits remain open.

Nine controller tests cover seeded/unseeded loading, notification timing, publication
order, attempts, failures/disconnect, stale errors, four retirement paths and explicit
child/sibling scope isolation. Actual-screen tests retain focus/failure/disconnect and
race coverage and add Search/Discover startup policy. Two live-map tests complete the
new coverage. The controller test's initial invalid assertion helper was corrected;
the live-grid fixture now returns a fresh Future for each refresh instead of reusing
a completed Future across test zones. Intermediate receipts are retained.

Expanded target: 418 baseline successes to 431, identical 12 failures and one skip.
Analyzer identities remain 863; formatting/diff and architecture checks pass (221 files).
SearchScreen is 19,713 lines. Evidence: `.git/refactor-evidence/phase5/trakt-state-*`,
`analyze-trakt-state-*`, `full-trakt-state*`. Full suite: 8,470 successes, unchanged
22 failures / 29 errors / 20 skips; every previous outcome is preserved and thirteen
new tests pass. Remaining tracker flows, artwork/settings,
vertical pagination/publication, native/performance checks and later phase gates remain
open; this does not complete Home or the overall migration.

#### Simkl continuation projection checkpoint

Simkl shelf preparation now lives in the 101-line
`features/home/models/home_simkl_continuation.dart`. Its card identity policy is shared
with the screen's rendering/opening lookups: native TMDB movie keys retain their movie
namespace, while show and resolved IMDb keys retain their existing semantics. The
projection preserves first-ID deduplication, per-feed order, stable merged recency,
null progress for up-next entries, progress bounds and positive episode labels.
Episode artwork references remain restricted to IMDb-backed titles, unlike the Trakt
policy. No generic tracker projection or provider-identity normalization is introduced.

The 45-line `SimklContinueWatchingItem` moves unchanged into a pure shared model,
registered in the architecture guard and re-exported by the service. Its model docs
refer to the service in plain text so they do not create an import dependency.
The service implementation remains byte-identical. Review reconstructs the original
screen loader after substituting snapshot fields, preserving every await, null/error
policy, focus update, repaint, artwork dispatch, announcement and bound refresh.
Result containers are detached/read-only, with legacy metadata/descriptor identities
borrowed. See-All copies its list before sorting; progress maps still retain their
existing mutable screen ownership until the next state migration.

Six new tests cover native namespaces/aliases, cross-feed duplicates, ordering/ties,
up-next progress, IMDb-only artwork and read-only containers. Nine existing Simkl
service tests also pass. Expanded Home target: 431 baseline successes to 437, identical
12 failure identities and one skip; analyzer matches all 863 identities. Formatting,
diff and architecture checks pass (223 files). SearchScreen is 19,668 lines. Evidence:
`.git/refactor-evidence/phase5/simkl-projection-*`, `analyze-simkl-projection-*`,
`full-simkl-projection*`. Full suite: 8,476 successes, unchanged 22 failures / 29
errors / 20 skips; all previous outcomes are preserved and six new tests pass.
Simkl injected data access, state/request ownership and
playback/profile audit remain next; Home and later phase gates remain open.

#### Simkl continuation state and reader checkpoint

The production screen now uses a 71-line scoped Riverpod controller for accepted
Simkl shelves and request ownership. A ten-line plain reader contract preserves the
existing service's typed nullable movie/show record, wired by an 11-line factory;
there is no additional repository, cache or retry layer. The existing projection is
the immutable provider state, with a constant empty constructor. Screen row/maps and
request token are removed. Focus/artwork, repaint, announcements, bound refresh and
context-dependent playback/removal stay in presentation pending their later phases.

Home and Discover retain their startup loads; Search skips them. Construction performs
no reads. Active null responses still await shared merge preferences then retain rows;
empty feeds clear rows and execute the existing successful-load effects. Exceptions
propagate without retry as before. Focus reconciliation precedes publication, and
older work cannot publish after overlap, disposal, dependency recomputation or view
retirement. Intentional hardening adds the captured profile owner and checks retirement
before reading merge preferences after the feed. This does not prove the internal
legacy service's profile-read sequence or writes safe. The view retains an explicit
subscription and uses the existing read-only live progress adapter so already-open
See-All grids observe new immutable snapshots.

Eight controller tests cover null/empty/throwing responses, read-layout-focus-publication
order, stale loads/artwork, four retirement paths and explicit child/sibling scopes.
Five actual-screen tests cover focused-card retention, disconnect clearing, profile
and disposal rejection, Search/Discover startup behavior and a retained Simkl grid map
observing progress from 50% to 75%. Initial fixture record typing and one brace lint
were corrected; their receipts remain. Expanded target: 446 baseline successes to
459, identical 12 failures and one skip. Architecture checks pass for 226 files;
changed formatting and diff checks pass. SearchScreen is 19,663 lines. Evidence:
`.git/refactor-evidence/phase5/simkl-state-*`, `analyze-simkl-state-*`,
`full-simkl-state*`. Final analyzer matches all 863 identities. Full suite: 8,489
successes, unchanged 22 failures / 29 errors / 20 skips; every preceding outcome is
preserved and thirteen new tests pass. Remaining tracker flows, Home settings/artwork, vertical
pagination/publication, native/performance checks and later phases remain open.

#### MDBList continuation projection checkpoint

MDBList metadata/progress/episode preparation and merged ordering now use the 88-line
`features/home/models/home_mdblist_continuation.dart`. It preserves first-ID deduplication
across feeds, selection-derived metadata/background URLs, progress clamping, positive
episode labels and the original timestamp comparator. Missing timestamps remain epoch
zero; no stable tie-break, empty-ID filtering or identity normalization is added.
Result containers are detached/read-only; the original resume/removal descriptors
remain borrowed rather than claiming deep immutability of legacy payloads.

The item/snapshot definitions move unchanged into the 28-line pure shared
`models/mdblist_continue_watching.dart`, re-exported by the legacy service. Its 294-line
pure `services/mdblist/mdblist_models.dart` dependency is also registered in the measured
set. The service implementation is byte-identical; caching, force behavior and result
classification remain there. The screen's guards and awaits before preparation,
focus/publication, forced-load timestamp, announcements and bound refresh retain their
order. Delayed revision-refresh code is unchanged. The existing ingest diagnostic
retains its payload and now follows synchronous sorting, still before focus updates.
The view continues to own mutable progress maps until the state migration, preserving
existing live consumers in this checkpoint.

Five new tests cover metadata and descriptor identity, duplicates/empty IDs, epoch
fallback ordering, progress/labels and detached read-only containers. Seven existing
MDBList service tests pass. Expanded target: 466 baseline successes to 471 with exactly
the same 12 failures and one skip. Changed formatting/diff and architecture checks
pass (229 files). SearchScreen is 19,616 lines. Evidence:
`.git/refactor-evidence/phase5/mdblist-projection-*`, `analyze-mdblist-projection-*`,
`full-mdblist-projection*`. Final analyzer matches all 863 identities. Full suite:
8,494 successes, unchanged 22 failures / 29 errors / 20 skips; all previous outcomes
are preserved and five new tests pass. MDBList injected reads, accepted state, revision ownership
and playback/profile audit remain; Home and later migration gates stay open.

#### MDBList continuation data-access checkpoint

The continuation loader now uses a 33-line injected repository with a 15-line Riverpod
factory. It waits for the existing coordinator's invalidation pass before fetching,
preserves fetch-on-false-poll behavior, forwards `force`, and returns the original
success/partial/failure result without recategorizing, retrying or adding caches.
Construction is lazy. Retirement before synchronization or after its await prevents
fetch; completed results remain available to the caller's existing merge wait and
stale-result diagnostics. The screen adds its captured profile owner to request
eligibility before reads and acceptance. This is intentional ownership hardening,
not proof that the legacy coordinator/service internals or writes are fully audited.

Review verifies the post-fetch layout, diagnostic, projection, focus/publication,
forced timestamp and UI-effect order; delayed revision refresh is byte-identical.
Six repository tests cover sequencing, false poll, force/partial identity, retirement,
exceptions without retry and caller-owned completed-response rejection. Five real
screen tests use partial empty feeds to cover dependency overrides, Home/Discover
startup, Search skip, profile/disposal during invalidation and the existing delayed
playback-revision `force: true` fetch. Populated-row focus and state migration remain
subsequent work; these empty-feed tests do not claim that broader coverage.

Expanded target: 471 baseline successes to 482, identical 12 failures and one skip.
Final analyzer matches all 863 identities after removing the now-unused coordinator
import. Formatting/diff and architecture checks pass (231 files). SearchScreen is
19,620 lines. Evidence: `.git/refactor-evidence/phase5/mdblist-access-*`,
`analyze-mdblist-access-*`, `full-mdblist-access*`. Full suite: 8,505 successes,
unchanged 22 failures / 29 errors / 20 skips; every prior outcome is preserved and
eleven new tests pass. Accepted state, revision ownership,
playback/profile audit and the remaining Home/later phase gates stay open.

#### MDBList continuation state checkpoint

A 97-line scoped Riverpod controller now owns accepted MDBList continuation rows,
progress/episode/removal lookup snapshots, request retirement and accepted forced-load
time. The screen consumes the controller through one manual subscription and keeps
focus reconciliation, repaint, announcements, route eligibility and bound refresh.
Its mutable row/maps and load token are removed. The existing live read-only progress
adapter preserves reads across snapshot replacement. Disabled-feature behavior still
hides rows and lookup entries while retaining progress/episode values and focus nodes.
No new loading state, retry, cache, or scheduling policy was added.

Review checked read → layout → projection → focus → publication → effects ordering,
partial-result acceptance, failed-result retention, stale completed-result diagnostics,
and forced timestamp changes only after accepted forced loads. The timestamp now sits
between provider publication and the view callback in the same synchronous turn;
repaint still precedes focus/announcement/bound-refresh effects. Delayed playback
revision handling and the three-second freshness gate are unchanged.

Eight controller tests cover ordering, failure/empty/disabled responses, overlapping
requests, profile/view/disposal/recomputation retirement and explicit child/sibling
isolation. Four populated actual-screen tests cover focused-node retention on failure,
empty-success removal, late profile/disposal results and Search startup exclusion.
The first populated fixture tried to initialize the native default image cache; its
failure is retained as evidence. A local PNG-backed cache fake fixes the fixture and
all four tests pass without invoking the native cache plugin.

Final verification receipts are under `.git/refactor-evidence/phase5/mdblist-state-*`,
`analyze-mdblist-state-*` and `full-mdblist-state*`. The expanded Home/tracker target rises from 482 to 494 successes with the identical
12 failures and one skip. Analyzer identities remain 863; formatting and the
232-file architecture guard pass. SearchScreen is 19,597 lines.
Full suite: 8,517 successes, unchanged 22 failures / 29 errors / 20 skips; every
prior outcome is preserved and twelve new tests pass. MDBList delayed revision
orchestration, mutation/playback profile auditing, remaining Home responsibilities
and later device/performance gates remain open.

#### MDBList delayed revision refresh checkpoint

The existing continuation controller now also owns revision generations, pending
refresh lifetime and the three-second post-playback freshness decision (148 lines
total). Its injected repository exposes the existing synchronous invalidation
operation through the small composition factory. The screen retains mode eligibility,
route visibility and the reload callback, removing its revision token, pending flag,
timestamp/freshness wrappers and delayed refresh implementation. Disposal cancels
revision ownership at the original screen teardown point and on provider disposal.

Review preserves twenty 100 ms visibility polls, the 750 ms propagation delay,
reload-without-bound-refresh and forced-fetch arguments, newest-only pending cleanup,
and the strictly-less-than-three-seconds freshness window (including backwards clock
movement). Visibility is deliberately not rechecked after propagation, matching the
legacy behavior. Profile ownership is now checked before invalidation and after each
wait; this intentionally prevents outgoing-profile work from invalidating implicitly
active service state. It does not prove downstream playback/mutation writes safe.
Errors still propagate without retries and pending ownership is released in finally.

Seventeen controller tests cover timing/order, covered-route exhaustion and return,
covering the route during propagation, overlap, profile/view/disposal/recomputation/
explicit cancellation at both waits, invalidation rejection, errors and freshness.
The actual-screen access test now observes injected invalidation, and a sixth scenario
covers Home with a real Navigator route: no fetch while covered, then exactly one
forced reload after return. Existing Search/Discover startup coverage remains; their revision eligibility
guards are unchanged. Expanded Home target: 494 to 512 successes, identical 12 failures
and one skip. All 863 analyzer diagnostic identities are unchanged. The architecture
guard passes for 232 files. SearchScreen is 19,561 lines.

Evidence: `.git/refactor-evidence/phase5/mdblist-revision-*`,
`analyze-mdblist-revision-*`, `full-mdblist-revision*`. Full suite: 8,535 successes,
unchanged 22 failures / 29 errors / 20 skips. Every prior outcome is preserved and
eighteen new tests pass. MDBList removal/playback boundaries, other continuation
mutation paths, deferred Home loading and later native/performance gates remain open.

#### MDBList continuation removal checkpoint

The existing scoped controller now resolves the accepted paused descriptor and
issues removal through its injected repository (170 / 43 lines respectively).
Missing and Up Next entries remain ineligible, descriptor/clear-target identity is
preserved, and no optimistic row deletion or retry was added. The screen retains
success feedback followed by its normal continuation reload; failures stay silent
and keep rows. Controller lifetime/profile/view checks guard dispatch and acceptance.
The screen rechecks mounted/profile after awaiting the controller so disposal or
profile changes between async continuations cannot publish feedback. A separate
lifetime generation intentionally permits ordinary loads and independent removals
while rejecting provider recomputation; no global removal lock was introduced.

Nine controller tests cover dispatch identity/eligibility, failures/exceptions,
lifetime/profile retirement and independent commands. Three added real-screen
scenarios hold the remote Select key, choose the existing removal menu action and
verify success → feedback/reload/removal, silent failure with the same focused node,
and profile change during the clear wait with no success feedback or reload.
Fixture failures (wrong menu label, clipped pointer target, missing first hold frame,
and closing-dialog duplicate title) are retained in evidence. Final fixtures drive
the actual TV hold and wait for dialog dismissal. Two HTTP-backed service tests
verify the episode clear payload/POST and cache invalidation only on success; the
initial Up Next response fixture used a list instead of the API object and was fixed.

The shared legacy service is unchanged. Its authorization capability still protects
outbound requests, but late `_scrobble` revision notifications and continuation-cache
invalidation after a profile transition remain a broader service audit item. These
UI/controller checks do not prove that boundary safe. The screen's separate resume
lookup still reads the legacy continuation service and remains in phase 7.

Expanded target: 512 to 526 successes, identical 12 failures and one skip. Analyzer
identities remain 863 and the 232-file architecture guard passes. SearchScreen is
19,566 lines. Evidence: `.git/refactor-evidence/phase5/mdblist-removal-*`,
`analyze-mdblist-removal-*`, `full-mdblist-removal*`. The initial full run preserved
all outcomes; because review added the final post-await UI guard, a fresh full run
verified the final source: 8,549 successes, unchanged 22 failures / 29 errors /
20 skips, every prior outcome preserved and fourteen new tests passing. Other continuation mutations, remaining Home
orchestration and later native/performance gates remain open.

#### MDBList late-response profile audit checkpoint

Before modification, nine new regression scenarios fail against the existing
service: start/pause/stop/clear success after a committed profile transition or
session deactivation still publishes revision counters, and a continuation clear
can report success after a synchronous revision listener retires its session.
Receipt: `.git/refactor-evidence/phase5/mdblist-profile-reproduction.txt`.

Scoped legacy retention: `lib/services/mdblist/mdblist_service.dart` is 2,209 lines
before this guard fix. It retains account, list, calendar, tracker and snapshot APIs
used throughout the app; this audit changes only scrobble session acceptance, not
those unrelated APIs or the whole file's formatting. It is an external legacy
service, not a newly extracted/adopted Home component. Phase 7 must complete the
typed playback/resume boundary and audit its integrated methods; all extracted code
still follows the final size limits. `mdblist_continue_watching_service.dart` is
376 lines before its matching completion guard and retains feed/cache ownership.
The service now captures the existing profile-session owner before authorization,
checks it before dispatch preparation and after a successful response, and rechecks
between synchronous revision notifications. Retired success becomes `denied` before
further local cache/title/revision effects. Continuation clear independently checks
its captured owner before invalidating its cache or returning success. This is an
intentional profile-isolation correction, not a claim that old cross-profile effects
were preserved. A request already sent for its authorized outgoing account is not
undone. Current-session payloads, success ordering, failure taxonomy and retries are
unchanged. The scrobble session already treats `denied` as stopping checkpointing.

Thirteen final tests cover four actions after profile switch/deactivation, preserved
incoming watched-cache contents, three synchronous listener retirement points,
independent continuation acceptance and deactivation during authorization with zero
HTTP calls. Committed-profile scenarios use a real temporary profile registry and
mock HTTP transport. A microtask-based attempt did not create the intended boundary
ordering; that failed fixture remains in receipts and was replaced with a deterministic
service fake for the continuation service's independent acceptance check. Production
timing was not changed to satisfy the fixture.

The expanded target includes all MDBList and profile authorization/outbound tests:
612 baseline successes to 625, identical 12 failures and one skip. All 863 analyzer
identities match. Changed methods are formatted without whole-service formatting;
the 232-file migration guard and diff checks pass. Service lengths are now 2,225 and
378 lines; SearchScreen remains 19,566. Evidence: `mdblist-profile-*`,
`analyze-mdblist-profile-*`, `full-mdblist-profile*` under
`.git/refactor-evidence/phase5/`. Full suite: 8,562 successes, unchanged 22 failures /
29 errors / 20 skips. Every prior outcome is preserved and thirteen new tests pass.
This closes
the audited late-scrobble/clear acceptance gap; it does not audit unrelated service
operations, playback/native teardown, profile lifecycle ordering or final device and
performance requirements.

#### Debrify TV favourites data/state checkpoint

A 44-line injected repository now reads favourite IDs, skips the channel database
when they are empty, converts/filter records in their original database order and
publishes read-only channel and keyword containers. A 56-line scoped Riverpod
controller owns accepted rows and refresh generations; construction is read-free.
The screen retains node reconciliation, repaint, autofocus eligibility and channel
navigation, removing its mutable favourites list, refresh revision and direct
repository import. The 12-line factory retains the existing storage/database APIs.
An eight-line typed favourites-session key captures profile owner and view identity.
The existing pure channel/record models (122 / 38 lines) join the measured source set.

Review preserves publication → repaint → node reconciliation → optional autofocus,
including the distinction between empty favourite IDs (no autofocus) and IDs with
no matching records (autofocus still attempted). Failures silently retain accepted
rows without retry. Request/view/profile/disposal/recomputation retirement prevents
stale publication and prevents channel reads after a retired preference read.
The underlying repository's captured database scope is retained; no writes change.

Five repository tests verify metadata/order (including equal channel numbers),
read-only detached results, empty/unmatched IDs and retirement at each read boundary.
Seven controller tests verify success/failure, callback eligibility, overlapping
loads, retirement and child/sibling isolation. Five real-screen scenarios verify
Home startup and row-refresh signals, focused-node retention on failure, empty-set
clearing without another database read, Search/Discover exclusions and profile/
disposal retirement before database access. Initial record inference errors were
fixed with explicit channel list types; their failed receipts remain available.

The populated screen test exposed an existing one-pixel favourites-caption overflow.
A separate probe used actual preference/database adapters with a fake database and
ran against both the original HEAD screen and the extraction, restoring the pending
screen in a finally block. Initial publication alone was clean; focusing the channel,
refreshing with a database failure, then clearing favourites reproduced the same
`_ArtPoster` Column overflow at 800×600 before and after (102×198 constraints).
The current screen also reproduces it at 1280×720 and with bundled fonts. Compact
single-line channel names avoid that separate caption defect; final state tests use
`One` at 1280×720, assert no exceptions, and do not suppress layout errors. This
is not proof of general layout parity. Phase 6 must fix/verify the caption case.
Receipts and the standalone probe: `tv-favorites-layout-*` and
`tv_favorites_layout_probe_test.dart` under `.git/refactor-evidence/phase5/`.

Expanded target: 625 to 642 successes, identical 12 failures and one skip. Analyzer
identities remain 863; formatting/diff and the 238-file architecture guard pass.
SearchScreen is 19,562 lines. Evidence: `tv-favorites-*`, `analyze-tv-favorites-*`,
`full-tv-favorites*` under `.git/refactor-evidence/phase5/`. Full suite: 8,579
successes, unchanged 22 failures / 29 errors / 20 skips; every prior outcome is
preserved and seventeen new tests pass. Other favourite/watchlist loaders, vertical/deferred Home orchestration,
layout extraction and native/performance gates remain open.

#### Stremio TV rotation prerequisite checkpoint

Before migrating Home's Stremio TV favourites state, the shared slot-selection
policy is separated into `lib/services/stremio_tv_rotation.dart` (104 lines).
It accepts channel ID, item descriptors and a captured clock, without the mutable
legacy channel or a service dependency. The existing Stremio TV service delegates
slot/schedule selection and daily catalog-page hashing to this policy; replaced
hash/offset/selection bodies are removed. Its source shrinks from 659 to 596 lines.
The existing pure now-playing model (54 lines) joins the measured source set.

Review preserves UTF-16 DJB2 hashing, integer mixing/truncation, salt/offset/default
semantics, local-time slot values, borrowed item identity, empty-feed short circuits
and mutable schedule results. The service captures the clock at its original point;
no storage, HTTP, rotation preference, UI, focus or playback sequencing changes.
This is a prerequisite for immutable favourites snapshots, not completion of their
repository/controller migration. The retained service still owns discovery, channel
loading and playback resolution; its placement/boundary must be addressed before
Home application/data wiring can use it without importing a screen directory.

Six tests verify 54 frozen selections/schedules captured from original service
revision `3b5930b4`, exact slot boundaries, empty/count behavior, descriptor identity,
stable hashing and the real service's offset/duration/salt forwarding. Frozen
vectors are checked in at `test/services/fixtures/stremio_rotation_baseline.json`;
they must not be regenerated from the extracted implementation. Initial wrapper
replacement and matcher mistakes were corrected; failed development receipts are
retained. Four newly exposed interpolation lints were removed without changing seeds.

Expanded Home/continuation/MDBList/profile/Stremio TV target: 692 to 698 successes,
identical 12 failures and one skip. Analyzer identities remain exactly 863; the
240-file architecture guard and changed-code formatting/diff checks pass. Receipts:
`stv-rotation-*`, `analyze-stv-rotation-*` and `full-stv-rotation*` under
`.git/refactor-evidence/phase5/`. Full suite: 8,585 successes, unchanged 22 failures / 29 errors / 20 skips;
every prior checkpoint outcome is preserved and all six new tests pass.
The Stremio favourites loader/state, other Home loaders, existing caption overflow,
and native/performance/final architecture gates remain open.

#### Stremio TV favourites data/state checkpoint

Home's Stremio favourites now use a 68-line injected repository and a 73-line
scoped Riverpod controller. The repository retains IDs → parallel movie/series
rotation preferences → channel discovery → favourite-only item loading, preserving
discovery order. A 40-line model detaches channel identity and item membership from
the legacy service's mutable cache; metadata descriptors remain borrowed and Home
reads their final display fields. The 18-line factory lazily resolves the existing
storage and Stremio TV APIs. Construction performs no reads or automatic retries.

The controller owns accepted rows, rotation settings and newest-request acceptance,
using the existing typed profile/view session. It rejects retired work before and
after each repository boundary. Empty IDs skip all later reads, clear rows and
retain prior rotation values; unmatched IDs still run loading and autofocus.
Failures retain accepted state. The controller also selects the movie/series
rotation interval through the shared pure policy. The screen keeps clock capture,
repaint → node reconciliation → optional autofocus, and unchanged ID-based playback
handoff. Its mutable favourites list, rotation fields, revision and direct service
import are removed; SearchScreen is now 19,545 lines.

The context-free shared Stremio TV service moves from `screens/stremio_tv/` to
`lib/services/stremio_tv_service.dart` with a two-line compatibility export. Its
singleton, algorithms, HTTP calls, caches and public APIs are unchanged; only
relative imports and one formatter-wrapped helper differ. The 597-line service and
143-line legacy channel model join the measured source set. Responsibility review:
the service retains discovery/filter-tree reads, bounded channel-cache loading,
rotation compatibility calls and episode/stream resolution; the independent rotation
policy is already separated. The Home boundary does not publish its mutable channel
objects. This move removes a UI-directory dependency; it does not claim the shared
transport/episode dependencies have completed phase-7 lifecycle/profile auditing.
In particular, cancellation inside the legacy discovery/loading calls and singleton
cache retention still require that audit; this checkpoint guards the outer calls
and accepted Home state, not every internal await in those services.

Seven repository tests cover parallel preference timing, favourite filtering/order,
post-load snapshots, immutable membership, empty/unmatched IDs and retirement at
all four await boundaries. Seven controller tests cover publication before effects,
retained rotations/failures, movie/series selection, racing loads, profile/view/
disposal/recomputation retirement and nested/sibling scope isolation. Five actual
screen tests cover Home startup/refresh, focus-node retention on failure, empty-ID
clearing and Search/Discover/profile/disposal exclusions. They use compact captions
and bundled fonts; the separately recorded long-caption overflow remains open.
One default-adapter test exercises actual preferences/local discovery and proves
both import paths resolve to the same singleton. Its initial unprefixed-name
expectation was corrected to the existing `Local: Mine` contract; the receipt is
retained. No production behavior was changed to satisfy that fixture.

Expanded target: 698 to 718 successes, identical 12 failures and one skip. Analyzer
identities remain exactly 863; changed-source formatting, diff and the 246-file
architecture guard pass. Evidence: `stv-favorites-*`, `analyze-stv-favorites-*` and
`full-stv-favorites*` under `.git/refactor-evidence/phase5/`.
Full suite: 8,605 successes, unchanged 22 failures / 29 errors / 20 skips;
every prior checkpoint outcome is preserved and all twenty new tests pass.
Other favourite/watchlist loaders, vertical/deferred Home orchestration, layout
work and native/performance/final retirement gates remain open.

#### IPTV favourites data/state checkpoint

A 34-line injected repository now reads and projects IPTV favourites, preserving
stored map order, null-only name fallback, empty/whitespace metadata, live-only
`duration: -1` semantics and the existing header conversion. Saved content type,
channel number and duration still do not change this favourites projection; custom
lists retain their separate richer mapping. Returned channel lists and header maps
are detached/read-only, with immutable empty attributes. The 12-line factory supplies
the existing storage read and header policy. The pure 289-line IPTV playlist/channel
model joins the measured source set without code changes.

A 55-line scoped Riverpod controller owns accepted rows and request generations.
Construction does not read; errors retain rows and there are no automatic retries.
The screen keeps the lists-revision listener, repaint → node reconciliation →
optional autofocus and existing playback/hero callbacks. Empty rows still skip
autofocus. Its mutable favourites list and direct read/projection body are removed.
SearchScreen is now 19,537 lines; the neighbouring custom-list loader is unchanged.

Explicit acceptance improvement: the old loader checked only `mounted`. This
controller additionally rejects older requests and retired profile/view/disposal/
recomputation owners. That prevents late startup data from overwriting a newer
list refresh. A real-screen overlap test exercises this case, as well as a
controller test; it is not a claim that the old loader already provided generation
isolation. The unchanged store uses `_runScoped` for first-use migration and the
list read, whose query orders by position, added time and URL. This slice changes
no writes, schema, provider requests or native playback operations.

Five repository tests cover order/metadata/header compatibility, detached containers,
empty and malformed data and retirement before/after reading. Seven controller
tests cover publication ordering, failure/empty behavior, competing requests,
profile/view/disposal/recomputation and nested/sibling isolation. Six real-screen
tests cover startup, lists-revision refresh, focused-node retention, empty clearing,
late-startup rejection and tab/profile/disposal exclusions. All eighteen pass.
The screen tests use compact captions/bundled fonts and do not suppress errors;
the previously recorded long-caption defect remains a phase-6 task.

Expanded target: 718 to 736 successes, identical 12 failures and one skip.
Analyzer identities remain exactly 863. Changed-code formatting, diff and the
250-file architecture guard pass. Full suite: 8,623 successes, unchanged 22
failures / 29 errors / 20 skips; every prior checkpoint outcome is preserved
and all eighteen new tests pass. Evidence: `iptv-favorites-*`,
`analyze-iptv-favorites-*` and `full-iptv-favorites*` under
`.git/refactor-evidence/phase5/`. IPTV custom lists, watchlist/playlist loaders,
vertical/deferred Home orchestration and later layout/playback/device/performance
work remain open.

#### IPTV custom-list data/state and focus checkpoint

Opted-in IPTV custom rows now use a 77-line injected repository, 56-line scoped
Riverpod controller, 17-line dependency factory and 16-line immutable row model.
The repository reads extras directly on each request (preserving the cold-start
race contract), excludes the built-in favourites list, walks stored list order and
reads selected lists sequentially. Empty lists are omitted. Mapping retains live/
VOD/series type, numeric duration/channel-number conversion, playlist identity,
empty-string normalization and headers; rows/channels/attribute/header containers
are read-only. This is deliberately separate from the live-only favourites mapping.
The existing shared HomeExtraRowIds grammar and captured-scope store reads remain
in use; no schemas, writes, provider fetches or native playback paths change.

The controller owns accepted snapshots and latest-request/profile/view/disposal/
recomputation acceptance, with no construction reads or automatic retries. The
no-enabled-lists/already-empty path still produces no focus/repaint/autofocus work;
unmatched enabled lists still publish an empty result. Focus reconciliation occurs
before accepted-state publication, repaint and the existing autofocus attempt.
A 47-line presentation owner retains nodes by list ID/channel position, grows and
shrinks them, disposes removed rows and clears borrowed node views on disposal.
The view retains creation/disposal timing and supplies its current ownership check.
The old mutable `_IptvListRow` and its part-file definition are removed. SearchScreen
is 19,456 lines and the retained card-widgets part is 912 lines (still a temporary
phase-6/8 responsibility, not a completed bounded file).

Explicit correction: the old loader mutated existing rows/nodes after each list
read, before later reads could fail or be superseded. The new path prepares a full
snapshot before any focus/state changes. A later-list failure now retains the
entire prior snapshot; an older overlapping request cannot partially alter it.
This is required immutable-boundary behavior, not a claim that the old incremental
mutation already provided atomic acceptance.

Nine repository tests cover stored order/filtering, metadata and header contracts,
empty versus unmatched opt-ins, retirement at every await boundary and sequential
reads with a later failure. Eight controller tests cover atomic retention, callback
ordering, no-op/empty behavior, races and scoped retirement/isolation. A focus-owner
widget test verifies retained node identity/focus across keyed reorder/rename,
grow/shrink, removed-row disposal and read-only live node views. Its first unkeyed
fixture lost focus during widget replacement; stable fixture keys isolate ownership
from layout reconciliation. That passing fixture is not full Home reorder parity.
Six real-screen tests verify Home startup/list-revision refresh, focus retention
on failure, empty clearing, late startup rejection and tab/profile/disposal
exclusions. Compact captions and bundled fonts are used; the existing caption
overflow and broader layout/device focus verification remain phase-6 work.
All twenty-four new tests pass. Newly introduced brace/import lints were corrected.

Expanded affected target: 736 to 760 successes, identical 12 failures and one
skip. Analyzer identities remain exactly 863; changed-code formatting/diff and
the 255-file architecture guard pass. Full suite: 8,647 successes, unchanged
22 failures / 29 errors / 20 skips; every prior checkpoint outcome is preserved
and all twenty-four new tests pass. Evidence: `iptv-lists-*`,
`analyze-iptv-lists-*` and `full-iptv-lists*` under `.git/refactor-evidence/phase5/`.
Watchlist/playlist loaders, vertical/deferred Home orchestration and later layout,
playback/lifecycle, device/performance and final retirement gates remain open.

#### Local watchlist read/state checkpoint

The local watchlist now uses a directly injected typed reader (10-line factory),
a 52-line scoped Riverpod controller and a 19-line grouping model. The storage API
already returns ordered `StremioMeta` items, so no forwarding repository class is
introduced. Its newest-first ordering, corrupt-row handling and persisted formats
remain unchanged. Grouping preserves input order and duplicate/descriptor identity;
only case-insensitive exact `series` goes to the series shelf, without trimming or
extra filtering. Movie/series membership is detached and read-only; the original
metadata descriptors are borrowed for existing artwork and playback consumers.

The controller owns accepted grouping and latest-request/profile/view/disposal/
recomputation acceptance. Construction remains read-free and retries are disabled.
Thrown failures retain accepted state; successful empty reads still publish and
invoke the view callback. The screen retains repaint → both-node reconciliation →
autofocus, including deferred focus recovery when a focused tail card disappears.
Its mutable movie/series lists, request revision and direct read/grouping body are
removed. SearchScreen is 19,460 lines: composition wiring temporarily adds four
lines while moving the state/data responsibility out. The final entry-point size
gate remains unchanged. Removal/unavailable-series dialogs, writes and playback
handoffs still need their phase-7 extraction/profile audit; this read checkpoint
does not establish those action contracts.

Two model tests cover case/whitespace grouping, order, duplicates, borrowed metadata,
empty refresh and immutable membership. Seven controller tests cover publication
before effects, retained failures, empty success, overlapping loads, profile/view/
disposal/recomputation and nested/sibling isolation. One default-reader test uses
actual saved preferences to verify newest-first ordering, malformed-row skipping
and movie/series grouping. Six actual-screen tests verify Home startup/row-refresh,
failure focus retention, focused-tail shrink recovery, clearing both shelves,
late startup rejection and Search/Discover/profile/disposal exclusions. These
use compact captions/bundled fonts and do not suppress layout exceptions; the
existing long-caption defect remains open. All sixteen new tests pass.

Expanded target: 760 to 776 successes, identical 12 failures and one skip.
Analyzer identities remain exactly 863. The twelve existing watchlist storage
tests pass before and after. Full suite: 8,663 successes, unchanged 22 failures /
29 errors / 20 skips; every prior checkpoint outcome is preserved and all sixteen
new tests pass. Changed-source formatting/diff and the 258-file
architecture guard pass. Evidence: `watchlist-*`, `analyze-watchlist-*` and
`full-watchlist*` under `.git/refactor-evidence/phase5/`.
Playlist loading, vertical/deferred Home orchestration and later layout, action/
playback/lifecycle, native/performance and final retirement gates remain open.

#### Playlist read/state and typed handoff checkpoint

Playlist loading now uses a 69-line injected repository, 50-line scoped Riverpod
controller, 15-line dependency factory and 89-line typed snapshot/legacy codec.
The repository retains parallel item/favourite/poster reads, descending `addedAt`
sort (null → zero, no new tie-breaker), non-empty poster overrides, then the existing
progress lookup. Poster identity and dedupe/progress identity remain distinct.
Empty item sets still perform progress lookup. Retirement before/after those awaits
prevents follow-up reads or publication for old requests, profiles and disposed views.
Construction is read-free, retries are disabled and failures retain accepted state.

Home now renders typed title/poster/collection fields and typed millisecond progress.
Progress retains numeric truncation, invalid/missing duration handling and 0–1
clamping. Entry presence remains separate from drawable progress, preserving the
Clear Progress menu option even when no fraction can be drawn. Favourite flags use
the accepted dedupe-key set. Raw saved provider fields stay behind the model's
validated legacy codec: it freezes JSON recursively and makes a detached mutable
copy only when entering the existing action menu. Unknown nested provider fields
survive, and action-side mutations cannot change accepted state. Malformed typed
fields/non-JSON values are rejected at this boundary rather than coerced; a failed
load retains the prior snapshot. Valid persisted JSON contracts are preserved.

The screen keeps focus reconciliation, repaint/autofocus and existing refresh
signals. All three playlist presentation variants consume typed data; its mutable
raw rows, favourite/progress maps, generation and progress-calculation body are
removed. The existing menu uses typed flags, then passes the full detached payload
to unchanged action handlers. SearchScreen is 19,427 lines. Legacy menu/write/player
orchestration still needs phase-7 extraction/profile auditing; this codec does not
claim those actions or their native lifecycle are complete. Recursive snapshot
copying is new ownership work, not a measured performance improvement; representative
loading/memory comparison remains part of the existing performance gate.

Three model tests cover lossless unknown-field handoff, two-way detachment, typed
validation, progress edge cases and presence/favourite/read-only semantics. Six
repository tests cover parallel start/barrier, sort/poster-before-progress order,
distinct keys, empty inputs, retirement and read/progress failures. Seven controller
tests cover coherent publication, failure/empty behavior, stale progress completion,
profile/view/disposal/recomputation and nested/sibling scopes. One default-adapter
test reads actual preferences to verify real ordering, keys, poster, progress,
favourite flags and nested handoff fields. Six real-screen tests verify startup,
refresh, focused-node retention, clearing, overlap and tab/profile/disposal behavior;
the Home case opens the real action sheet to verify Favourite icon/Clear Progress
and single-item menu choices. Initial fixture expectations used the full action
title instead of its `Favorite` pill label, then observed the closing sheet before
its transition completed; both were corrected without changing production menus.
Brace lints introduced by formatting were fixed. Failed development receipts remain.

All twenty-three new tests pass. Expanded target: 776 to 799 successes, identical
12 failures and one skip. Analyzer identities remain exactly 863. Full suite:
8,686 successes, unchanged 22 failures / 29 errors / 20 skips; every prior
checkpoint outcome is preserved and all twenty-three new tests pass. Changed-code formatting/diff and
the 262-file architecture guard pass. Evidence: `playlist-*`, `analyze-playlist-*`
and `full-playlist*` under `.git/refactor-evidence/phase5/`.
Vertical/deferred Home orchestration, remaining configuration/refresh ownership,
layouts, action/playback/lifecycle, native/performance and final retirement gates
remain open; this checkpoint does not complete Home or the overall migration.

Vertical-page acceptance checkpoint: the existing scoped `HomeCatalogController`
now owns the fetch/deduplicate/commit/merge/cache sequence through `loadNextRows`.
The production `_loadMoreBoard` uses its typed result and the redundant screen
batch wrapper is removed. Cursor snapshots still commit before row replacement,
including accepted empty batches. The merge uses the live accepted rows after the
await, retaining horizontal pages and original row identities. The original row-ID
policy remains an explicit input because tracker/collection rows have their own
IDs; addon metadata is read at acceptance time, preserving the shared lookup's
lifetime. Result membership is read-only; mutable legacy rows remain borrowed.

The view retains page eligibility/loading finalization, Android TV route pausing,
search visibility, focus allocation, deferred movement and post-frame autofill.
Cache acceptance is independent of search visibility. Generation/profile/mounted
checks run before acceptance and again when the asynchronous result reaches the
view. This adds no timer or retry. The controller is 310 lines and still owns one
catalog inventory/request/cache responsibility; it is within the 301–500 allowance.
SearchScreen is 19,400 lines and retains its existing phase 5–8 size exception.

Six new controller tests cover tail append with concurrent horizontal growth,
earlier catalog recovery, covered empty-page commits, and late profile/generation/
disposal rejection. Existing screen fixtures exercise covered-route request counts,
cached return, layout focus and pagination. The affected run passes all 42 tests
(36 before extraction); analyzer diagnostic identities remain exactly 863 and the
262-file architecture guard passes. Full-suite comparison preserves every prior
outcome: 8,692 successes, unchanged 22 failures / 29 errors / 20 skips, with all
six new tests passing. Initial development runs caught a record generic
inference error, a missing fixture title, the obsolete wrapper and a brace lint;
those were fixed, with failed receipts retained. Evidence: `page-accept-*` and
`analyze-page-accept-*` and `full-page-accept*` under
`.git/refactor-evidence/phase5/`.
Deferred publication, refresh/configuration ownership, later layouts/actions/native
checks and the original final size/performance gates remain pending.

Deferred-publication checkpoint: `HomeProgressPublication` (76 lines) owns the
view's covered-route row queue and post-frame coalescing. `_publishHomeProgress`,
route return, load reset, timeout retirement and disposal all use it; the original
pending record and scheduled flag are removed from SearchScreen. This is local
presentation state, not a second application-row owner or Riverpod workflow.
Accepted row references remain borrowed so horizontal paging identity is retained.

The queue preserves the earliest `first` flag while accepting the latest rows,
retains pending rows if the scheduled frame is still covered, clears consumed stale
scope/generation data without autofill, and carries accepted rows to the timeout's
retired generation. Clearing for a new load retains the already scheduled callback.
The view still checks mounted/route visibility, validates scope/generation, applies
rows/focus and schedules viewport measurement on the following frame. Scheduling
does not request an extra frame. Disposal releases queued references and makes
uncancellable Flutter post-frame callbacks inert before they can read view state.

Nine focused widget tests cover both first-flag values, coalescing/two-frame order,
covered retries, profile/generation rejection, clear-with-scheduled-return, timeout
retirement, replacement before a queued frame and disposal. The first fixture run
incorrectly expected a post-frame callback to request a frame; the fixture now
supplies explicit frames, as the existing route/layout flow does. Production
scheduling was not changed to satisfy that test. The affected tests pass 79/79
(70/70 before extraction). Existing real-screen progressive/pagination and deadline
fixtures pass through the new path. SearchScreen is 19,397 lines; the plan's existing
phase 5–8 exception remains. This slice separates publication ownership rather than
claiming the screen-size goal is achieved. The 263-file architecture guard and
changed-code formatting/diff checks pass. Analyzer identities remain exactly 863.
Full suite: 8,701 successes, unchanged 22 failures / 29 errors / 20 skips; every
prior outcome is preserved and all nine new tests pass.
Evidence is under `.git/refactor-evidence/phase5/` as `publication-*`,
`analyze-publication-*` and `full-publication*`. Refresh/configuration orchestration,
remaining layouts/actions/native checks and the original size/performance gates
remain open.

Display-preferences checkpoint: both startup/card-preference refresh and Home
settings reload now use the same injected `HomeDisplayPreferencesRepository`
(52 lines) and scoped `HomeDisplayPreferencesController` (52 lines). The repository
preserves focus-details, animation-enabled and animation-style reads in sequence,
then reads the four card preferences in parallel. The 31-line scalar record/session
model provides immutable values and value equality; the 17-line provider factory
wires the same storage methods. Seven mutable screen fields and both duplicated
read/apply blocks are replaced by controller getters and changed-only repainting.
Storage keys, style normalization, return-snapshot format and package versions are
unchanged. The orientation type initially remained in the storage service; the
follow-up below closes that direct dependency for these migrated components.

The controller is constructed without reads or writes. A cached Home seeds its
four saved card preferences before the first build; focus-details/animation flags
retain their original pre-read values because they were not saved in that snapshot.
The legacy pre-read focus-details value is false, while storage defaults to true;
the default-adapter test verifies that distinction rather than changing behavior.
A failed read propagates and retains accepted state. Dependency recomputation
retires work while retaining accepted display settings.

Intentional acceptance correction: the former display loaders checked only
`mounted`, so a late startup/older refresh could replace a newer settings result,
or continue sequential reads across a profile handoff. The scoped controller now
uses request generation, profile-session ownership and caller acceptance; the
repository stops between sequential reads when retired. A retired settings reload
returns before starting the later continuation/configuration work. This does not
claim that the entire settings workflow is migrated: source-text formatting,
trailer/layout/default-view preferences and later orchestration remain to audit.

Seventeen new tests cover sequential/parallel ordering, retirement at all read
boundaries, failures, newest-read ownership, profile/view/disposal/recomputation,
independent views, actual stored defaults/keys, Spotlight rendering and cached
first-frame return. Real-screen tests verify portrait/hidden-title restoration and
that a late startup cannot reverse a settings update. The first default-adapter
fixture mistakenly equated pre-read focus expansion with the stored default;
its expectation was corrected, with the failed receipt retained. The existing
Home screen/configuration/pagination baseline passes 38 tests; the expanded
focused run passes all 55. The first full run preserved every Home outcome but
observed the pre-existing remote-transfer `.part` cleanup race (test line 313).
The identical error is recorded in `phase4c/full-state-scopes.jsonl` and other
earlier receipts. Transfer service/test code is unchanged: it marks the receipt
complete before the asynchronous journal/file cleanup finishes. All 18 transfer
tests pass in isolation (`display-transfer-check.txt`); a fresh full comparison
is recorded separately, retaining the first failing receipt. That repeat preserves
every prior outcome: 8,718 successes, unchanged 22 failures / 29 errors / 20 skips,
and all seventeen new tests pass (`full-display-verified*`). The architecture
guard passes for 267 migrated files and analyzer identities remain exactly 863.
Changed-code formatting/diff checks pass. SearchScreen is 19,369 lines and retains
the existing phase 5–8 exception. Evidence: `display-*`, `analyze-display-*` and
`full-display*` in `.git/refactor-evidence/phase5/`. Remaining Home orchestration,
layouts, actions/playback/lifecycle and native/performance/final size gates remain
open.

Orientation-type boundary follow-up: the unchanged `HomeCardOrientation` enum
and its documentation now live in the existing `lib/models/home_preferences.dart`
(14 lines). The storage service already imports and exports that model, so legacy
storage imports and the new direct model imports resolve to the same enum. The
new display model/repository no longer import storage merely for the value type.
Enum order, names, preference keys, parsing and writes are unchanged. This closes
the display checkpoint's direct storage-type dependency without adding a wrapper,
new file or DI registration.

The storage service remains a 10,807-line legacy boundary under the earlier phase 5
exception: this follow-up only removes the six-line pure declaration block; no
storage logic is moved or reformatted. The shared model was already in the measured
source set. All 41 affected tests pass before and after, including actual storage
round trips and screen rendering/cached return through both import paths. Analyzer
identities remain exactly 863; changed-file formatting, diff and the 267-file
architecture guard pass. No new boilerplate tests or full-suite rerun were needed
for this declaration-only move. The latest full comparison remains the display
checkpoint's 8,718 successes / unchanged 51 failures-errors / 20 skips. Evidence:
`orientation-type-*` and `analyze-orientation-type-*` under
`.git/refactor-evidence/phase5/`. The remaining phase 5–8 scope is unchanged.

Configuration-refresh checkpoint: `HomeConfigurationRefresh` (59 lines) now owns
settings/collection reads, signature calculation, change classification and accepted
configuration publication. The production settings callback constructs this bounded
operation from the existing injected repositories and hide-watched reader; no new
DI registration or competing state owner was added. `HomeCatalogController` remains
the accepted-state owner. The view receives a typed `HomeConfigurationChanges`
record and retains board/hero/IPTV effect dispatch, search-detour reload deferral,
repaint and focus. Two obsolete configuration getters are removed from SearchScreen.

Read order and temporal comparisons are preserved: preferences, collections, the
current and previously accepted hide-watched values, then the collection signature.
After the hash await, other preferences/signature are compared against the latest
accepted configuration, as before. Unchanged input retains the exact accepted
snapshot without notifying the controller. Collection-read failures still use the
existing logged empty fallback; preference/signature errors still propagate without
publication. The operation performs no timers, network fan-out or retry itself.

Retirement improvement: the existing settings generation/collection-session/mounted
predicate now also guards entry and the boundary after preferences, so retired work
does not start subsequent collection operations. The view rechecks acceptance before
dispatching effects. This does not migrate the earlier source-text, display/trailer,
merge-focus or default-mode steps of the same callback, nor change their ownership.

Twelve new operation tests cover atomic accepted snapshots, unchanged notification
suppression, Home/non-Home effects, retirement at each operation boundary, failures,
collection fallback and overlapping configuration updates during hashing. Two actual
Home fixtures cover remove/restore of a disabled catalog, no extra catalog requests
for unchanged settings, and disposal while preferences are pending. The affected run
passes all 54 tests (40 before extraction). Full suite: 8,732 successes, unchanged
22 failures / 29 errors / 20 skips; every prior outcome is preserved and all fourteen
new tests pass. Analyzer identities remain exactly 863; formatting/diff and the
268-file architecture guard pass. Initial development receipts
include a baseline command referencing a nonexistent fixture, a corrected record-list
annotation in the new fixture, and two obsolete-getter warnings that were resolved.
SearchScreen is 19,339 lines under the existing phase 5–8 exception. Evidence:
`config-refresh-*`, `analyze-config-refresh-*` and `full-config-refresh*` under
`.git/refactor-evidence/phase5/`. The full original migration, including remaining
settings/default-view work, layouts, actions/playback/lifecycle and native/performance/
final size gates, remains open.

Default-view checkpoint: `HomeDefaultView` (49 lines) now owns the saved-default
read, keyword permission decision and per-request acceptance. Its 30-line Riverpod
composition supplies the existing storage reader and live policy callback, scopes
one operation to the mounted catalog/Home session, and closes it on disposal or
recomputation. Construction performs no read. The view reads the current operation
from its subscription, so a replaced dependency cannot leave a stale closed operation
cached in the widget. The active search mode remains view-owned; there is no second
mode state or new persistence model.

TV still selects catalog synchronously without storage or keyword-policy reads.
Off-TV reads the saved nullable string once, permits only the exact `keyword` value
when live policy allows it, and otherwise selects catalog. Non-Home retains the
post-read no-selection guard. Existing UI switching and cached-keyword suppression
remain in their original callers. Failed reads propagate without a selection.
Intentional acceptance correction: requests now reject old generations, profile
owners, retired caller requests and disposal. An already rejected action does not
cancel a valid pending read. Settings refresh passes its existing acceptance predicate;
startup keeps its mounted check plus the operation's profile ownership.

Fifteen operation tests cover exact values, synchronous TV behavior, permission
changes during reads, newest requests, owner/view/disposal retirement, rejected
requests, variants and failures. Three provider tests cover no-read construction,
profile/disposal retirement and usable replacement after recomputation. Two actual
Home tests cover the off-TV keyword/catalog transition and absence of TV reads;
a keyword-stream fixture verifies Home's completed search returns without another
default read or search. The first off-TV fixture assumed TV progressive publication;
it now completes the initial catalog batch before asserting first-row visibility,
matching the pre-existing non-TV loading contract. Production loading was unchanged.

The affected baseline passes 41 tests; the expanded run passes all 62. Full suite:
8,753 successes, unchanged 22 failures / 29 errors / 20 skips; every prior outcome
is preserved and all twenty-one new tests pass. Analyzer identities remain exactly
863;
formatting/diff and the 270-file architecture guard pass. SearchScreen is 19,341
lines under the existing phase 5–8 exception; the subscription wiring does not mean
the final size gate is achieved. Evidence: `default-view-*`,
`analyze-default-view-*` and `full-default-view*` under `.git/refactor-evidence/phase5/`.
Remaining settings/source-appearance, layouts, actions/playback/lifecycle and the
original native/performance/final size gates remain open.

Trailer-preferences checkpoint: startup and refresh now share an injected
`HomeTrailerPreferencesRepository` (26 lines), scoped controller (57 lines), a
four-line immutable preference record and a 17-line composition provider. The
three reads still start in parallel and publish only a complete enabled/effective-
volume pair. The factory maps the caller's live audio-surface choice to the existing
Home keys on TV and Detail keys off-TV. Storage remains responsible for persisted
values and volume clamping; muting changes only the effective volume to zero.

Two mutable screen fields and both direct storage-read blocks are removed. The
controller is read-free at construction, retains accepted values during failed
reads/recomputation, and shares the mounted catalog view's profile/session lifetime.
Failures still propagate. Repeated equal/disabled refreshes still invoke the accepted
callback; they cannot skip the existing stop request merely because Riverpod state
is equal. Startup still repaints, then schedules the current hero only when enabled.
Refresh still repaints, then clears the trailer when disabled. These actions, their
timers, route/suppression guards and all player resources remain in presentation;
this checkpoint does not claim phase 7 native lifecycle completion.

Intentional acceptance correction: an older enabled startup may no longer override
or schedule after a newer disabled refresh. Generation/profile/view/disposal checks
retire late results, and ownership is rechecked after state publication before UI
effects. The audio surface is an input to each load, so it is not frozen into the
session if the view's platform presentation changes.

Thirteen new tests cover the parallel barrier, mute/enable independence, failures,
no-read construction, publication/effect ordering, repeated disable callbacks,
newest-request acceptance, profile/view/disposal/recomputation, synchronous owner
retirement during notification, actual Home/Detail storage keys and clamping, and
TV/off-TV Spotlight wiring. Existing synced-volume, local-mute, trailer backdrop
and policy tests pass. The affected run passes 46 tests (33 before extraction).
The completed full suite reports 8,766 successes, the same 22 failures / 29 errors
and 20 skips as the preceding default-view checkpoint. Test-identity comparison
preserves every prior outcome and adds exactly the 13 successful tests above.
Analyzer identities remain exactly 863; changed-code formatting/diff and the 274-file
architecture guard pass. SearchScreen is 19,331 lines under the existing phase 5–8
exception. Evidence: `trailer-prefs-*`, `analyze-trailer-prefs-*` and
`full-trailer-prefs*` under `.git/refactor-evidence/phase5/`. Remaining source appearance,
layout preference/transition ownership, layouts, playback/actions/lifecycle and the
original native/performance/final size gates remain open.

Source-appearance checkpoint: keyword results now use a 51-line scoped Riverpod
controller and 12-line reader factory. The Sources repository and keyword factory
share `lib/services/source_appearance_preferences.dart` (19 lines) with the four-line
`SourceAppearance` contract under `lib/models/`. Both shared files are registered
in the measured architecture set. The plain storage reader captures the originating
profile scope, retains text-then-logo read ordering, and checks ownership before,
between and after reads. Existing Sources priority loading and its settings state
remain unchanged; the duplicated appearance read block is removed.

Keyword results no longer own two mutable appearance fields or call StorageService
for them. The retained screen only subscribes and repaints accepted refreshes.
Startup remains an explicit action in the same synchronous initState turn, now
immediately after the search session is constructed. Initial labels remain hidden
until a complete read lands; missing stored values still default to true/true and
no preferences are written. Existing settings-refresh call sites, result ordering,
focus nodes and request counts remain unchanged. Equal refreshes still repaint and
failed reads propagate while retaining accepted values. The view subscription is
closed on disposal; provider construction/recomputation performs no reads.

Intentional acceptance correction: keyword appearance now rejects older refreshes,
retired views/profiles and disposed/recomputed requests. A profile handoff clears
accepted appearance via the existing search-session activity provider. Ownership
is rechecked after publication so a synchronous handoff cannot repaint the old view.
These guards extend the protection already present in the Sources storage adapter.

The affected baseline passes 27 tests; the final focused run passes 38. Eleven new
tests cover explicit reads and defaults, complete publication before repaint,
repeated refreshes, failure retention, newest-request acceptance, profile/view/
disposal/recomputation retirement, rejected-action reads, synchronous handoff,
actual profile preference keys and no-write defaults, and real keyword row refresh
without another search. Existing Sources startup/controller/storage tests pass.
The completed full suite reports 8,777 successes, the same 22 failures / 29 errors
and 20 skips as the trailer-preferences checkpoint. Test-identity comparison
preserves every prior outcome and adds exactly these 11 successful tests.
Analyzer identities remain exactly 863 and all 278 migrated files pass size/import
checks. SearchScreen is 19,343 lines under the existing phase 5–8 exception; the
additional subscription wiring is temporary pending standalone presentation.
Evidence: `source-appearance-*`, `analyze-source-appearance-*` and
`full-source-appearance*` under `.git/refactor-evidence/phase5/`. Layout preference/
transition ownership, remaining UI/actions and native/performance/final size gates
remain open.

Layout-preference checkpoint: Home now reads its cached first-frame layout and
saved preference through the injected `HomeLayoutPreferences` boundary (10 lines).
A 37-line `HomeLayoutPreference` operation owns request retirement, and its 35-line
Riverpod composition provider shares the mounted catalog view's session identity.
The factory captures the originating profile scope for saved reads. The storage
getter still owns supported-value normalization and its existing synchronous mirror;
no schema, default, write, or normalization policy changes. Each new view reads the
current mirror, and construction performs no asynchronous read.

The screen initializes its active layout from the injected cached value before
layout/hero startup and retains ownership of the active layout. The operation does
not store a second active-layout value: after the read it compares against the live
view value and requests a transition only when different. Cold-start and Settings
bridge triggers remain at their existing call sites. The screen reads the current
operation through its retained subscription, so provider recomputation replaces the
retired operation without leaving the view with a disposed instance.

`_applyStageTransition` is byte-for-byte unchanged: clear trailer, clear live IPTV,
reset navigation, clear ambient artwork, update layout, and republish artwork/tint
on the next frame. No native resource or focus owner moved. Native lifecycle checks
remain phase 7 work; unchanged method text and widget coverage do not establish
whole-player/device parity.

Intentional acceptance correction: a late startup preference may no longer undo a
newer refresh, and retired profile/view/disposed/recomputed operations cannot apply
a layout. Rejected actions perform no read and do not cancel an already current
request. Errors still propagate without changing layout or adding retries.

The affected baseline passes 37 tests; the final focused run passes 51. Fourteen new
tests cover no-read construction, equality and live-layout comparison, latest-read
acceptance, profile/view/disposal/recomputation, rejected actions, error propagation,
current cache per view, actual profile keys/default normalization, and TV/off-TV Home
wiring from cached Classic to Spotlight with a late startup rejected. Existing
progressive pagination, layout policy, backdrop and ambient-policy tests pass.
The completed full suite reports 8,791 successes, the same 22 failures / 29 errors
and 20 skips as the source-appearance checkpoint. Test-identity comparison preserves
every prior outcome and adds exactly the 14 successful tests above.
Analyzer identities remain exactly 863; changed-code formatting/diff checks pass and
all 281 migrated files pass size/import checks. SearchScreen remains 19,354 lines
under the phase 5–8 exception; standalone presentation and final size gates remain
open. Evidence: `layout-preference-*`, `analyze-layout-preference-*` and
`full-layout-preference*` under `.git/refactor-evidence/phase5/`. Settings-refresh
coordination, remaining data/action and presentation responsibilities, return-cache
lifetime, native and performance checks still require completion.

Settings-refresh coordination checkpoint: a 51-line `HomeSettingsRefresh`
application operation now owns the sequence and request lifetime; a 21-line
Riverpod factory shares the mounted catalog session, retains the collections-scope
check, and disposes/replaces the operation with its scope. The operation borrows
explicit refresh functions and presentation callbacks. It owns no duplicate
preferences, result rows, focus nodes or player resources, and neither construction
nor recomputation starts reads.

The production view delegates appearance → display → continuation → default view →
configuration refresh to this operation. Trailer preference refresh still starts
before default-view loading and runs independently through its own controller;
the coordinator does not delay default/configuration work for it. Changed merge
settings still reconcile all eight existing continuation node lists without fetching
rows. Configuration effects retain board-before-hero precedence and the independent
IPTV reload. Those effects and focus reconciliation remain view methods; the old
screen-owned refresh generation and inline sequence are removed. Existing controller/
repository state owners, configuration comparison and accepted-state logic are reused.

Intentional retirement correction: request/profile/view ownership is established
before the first appearance await, rather than after it. A newer refresh retires
all remaining stages of the older one. Every awaited boundary, and the synchronous
continuation callback, now rechecks the operation. The same live guard reaches
appearance, display, continuation, trailer, default-view and configuration reads, so
independent trailer completion cannot apply an obsolete refresh. Rejected calls
perform no work and do not cancel a current request. Errors still propagate; no
retry loop or error suppression is added.

The affected baseline passes 38 tests; the final focused run passes 56. Eighteen new
tests cover ordering, independent trailer completion, unchanged/null configuration,
supersession at every awaited stage, first-await profile/view/disposal, synchronous
retirement during reconciliation, rejected calls, error propagation, provider
recomputation, and the real Home overlap that previously could restart configuration
reads after a newer refresh. The screen test preserves catalog visibility and request
counts. Existing display, continuation, default-view, trailer, configuration and
keyword screen tests pass. Focus reconciliation is unchanged apart from indentation.
The completed full suite reports 8,809 successes, the same 22 failures / 29 errors
and 20 skips as the layout-preference checkpoint. Test-identity comparison preserves
every prior outcome and adds exactly the 18 successful tests above.
Analyzer identities remain exactly 863; changed-code formatting/diff checks pass,
and all 283 migrated files pass size/import checks. SearchScreen remains 19,363 lines
under the existing phase 5–8 exception. Evidence: `settings-refresh-*`,
`analyze-settings-refresh-*`, and `full-settings-refresh*` under
`.git/refactor-evidence/phase5/`. Remaining integration availability/binding reads,
actions, return-cache/resource ownership, standalone presentation and the original
native/performance/final size gates remain open.

Bound-count checkpoint: displayed-title pinned-source counts now use a 27-line
plain repository, a 26-line scoped composition provider and a 48-line Riverpod
controller. The production caller still gathers the same catalog items and all
eight local/Trakt/Simkl/MDBList continuation groups, using the unchanged progress-ID
policy. The repository snapshots distinct nonempty identities in first-seen order,
reads them sequentially, omits zero counts and publishes one immutable complete map.
The screen's mutable map and direct binding-read loop are removed; existing badge,
menu and detail-count consumers read the accepted controller snapshot. All existing
load, pagination, bind/unbind, playback-return and Discover refresh triggers remain.

The adapter calls the existing SeriesSourceService with the operation's live guard
and originating profile scope. That service can migrate legacy binding records
while reading, so passing the guard through its existing migration/write barriers
is required. The adapter also checks its own captured owner even if called directly.
Active reads retain service normalization/migration behavior; active errors propagate
and retain the old complete snapshot. Empty accepted scans clear the counts. Initial
construction is read-free, and accepted counts survive dependency recomputation.

Intentional retirement correction: a newer displayed-title scan now retires the
older one; profile/view/disposal/recomputation stops later reads and prevents late
publication/repaint. Retirement errors from the guarded service are discarded only
when that operation is no longer current; active errors are not swallowed. The
controller rechecks ownership after publication before the repaint callback.

The affected baseline passes 59 tests; the final focused run passes 73. Fourteen new
tests cover sequential barriers, duplicate/unsupported/empty IDs, native identities,
immutable positive counts, retirement between reads, error handling, complete
publication, latest scan, profile/view/disposal/recomputation, synchronous owner
retirement, actual profile keys and legacy migration, rejected migration, and a real
catalog card receiving its injected bound badge. The first screen fixture used
unsupported synthetic IDs and correctly produced no reads; its IMDb replacement
required unrelated native poster-cache setup. The final supported TMDB fixture
passes without suppressing exceptions or changing production identity/artwork rules.
Both failed development receipts are retained. Analyzer identities remain exactly
863; changed-code formatting/diff checks pass and all 286 migrated files pass the
size/import guard. SearchScreen remains 19,365 lines under its phase 5–8 exception.
The completed full suite reports 8,823 successes, the same 22 failures / 29 errors
and 20 skips as the settings-refresh checkpoint. Test-identity comparison preserves
every prior outcome and adds exactly the 14 successful tests above.
Evidence: `bound-counts-*`, `analyze-bound-counts-*` and `full-bound-counts*` under
`.git/refactor-evidence/phase5/`. Integration-availability reads, remaining actions,
return-cache/resource lifetime, standalone presentation and native/performance/final
size gates remain open. Binding-service migration internals retain their existing
scope and are not claimed as a newly completed whole-service audit.

PikPak-only availability checkpoint: the shared Home/Discover/catalog quick-play
rule now uses a 42-line repository, 29-line dependency factory and 47-line scoped
Riverpod controller. The screen no longer reads the PikPak flag or four credential
values for this rule and no longer owns its mutable boolean. Existing startup,
reload and return triggers and all quick-play consumers remain wired to the same
accepted eligibility value. The rule is specifically PikPak enabled with no other
nonempty provider key; it is not a replacement general playback authorization rule.

The repository retains PikPak → Real-Debrid → TorBox → Premiumize → AllDebrid
sequential reads. It does not stop early when PikPak is disabled or an earlier key
is present. Null/empty keys remain absent and whitespace-only keys remain present.
Only a boolean crosses the data boundary; credentials are not stored in controller
state or logged. Initial eligibility remains false, unchanged reads do not repaint,
failed active reads retain the prior value and propagate, and dependency recomputation
retains accepted state without starting a read.

Intentional retirement correction: the controller owns latest-request acceptance
and profile/view/disposal/recomputation checks. The factory forwards a live request
and captured-owner guard into every existing guarded StorageService getter, including
PikPak email presence and the four key readers. Those getters retain their existing
active-profile routing and guarded credential-migration barriers; no new vault or
storage logic is added. Retired reads stop between providers and cannot repaint or
finish a blocked legacy credential migration. Ownership is checked again after
state publication before repainting.

The affected baseline passes 38 tests; the final focused run passes 58. Twenty new
tests cover all four competing keys, disabled PikPak, null/empty/whitespace semantics,
read order without early exits, blocked-read retirement, error handling, read-free
construction, changed-only repaint, latest request, profile/view/disposal/recomputation,
synchronous retirement, every actual storage key and legacy sealing, blocked migration
retirement with unchanged stored records, and real catalog quick-play callbacks for
both eligibility values. Two new test brace-style analyzer diagnostics were corrected;
final analyzer identities match the 863 baseline exactly. Changed-code formatting/diff
checks pass and 289 migrated files pass the architecture guard. SearchScreen remains
19,364 lines under its phase 5–8 exception. Evidence: `pikpak-only-*`,
`analyze-pikpak-only-*` and `full-pikpak-only*` under `.git/refactor-evidence/phase5/`.
Remaining actions, return-cache/resource ownership, standalone Home/Discover
presentation, native/performance checks and the original final size gates remain open.

Full-suite investigation: the first run added one Xtream streaming-ingest deadline
error (`Client is already closed`) while all 20 new tests passed. The unchanged
Xtream test file passes all 10 tests independently. A diagnostic copy under the
evidence directory, changing only its deadline from 50 ms to zero, reproduces the
same error against the unchanged service. `_downloadToFileOnce` starts `client.send`
before evaluating `remaining()` for `.timeout`; if file opening consumed the budget,
the latter throws before the send future receives its error handler. This is an
existing deadline race, not an availability-controller dependency. The first full
receipt, isolated run and diagnostic copy/output are retained as
`full-pikpak-only*`, `pikpak-only-xtream-*` and `xtream-deadline-probe_test.dart`.
No Xtream production/test source or failure allowance is changed by this slice.
The unchanged repeat (`full-pikpak-only-verified.jsonl`) reports 8,843 successes,
the same 22 failures / 29 errors and 20 skips as the bound-count checkpoint.
Test-identity comparison preserves every prior outcome and adds exactly the 20
successful tests above. The original Xtream deadline test passes in this repeat;
its separately reproduced timing race remains recorded rather than being hidden
by the successful comparison.

Home-return repository checkpoint: the 19-line `HomeReturnSnapshot` record now
lives with Home models, and a 37-line plain repository owns the borrowed shared
cache and process-lifetime invalidation subscriptions. Its 11-line Riverpod factory
is keyed by the captured profile owner, because taking the snapshot must precede
catalog-session bootstrap. The view retains the plain adapter for disposal and
never resolves WidgetRef while saving its outgoing snapshot. Provider disposal or
recomputation neither consumes nor invalidates the borrowed process cache.

The existing `HomeReturnCache` (41 lines) remains the consume-once, revision and
five-minute expiry implementation. Its registered `ProfileSessionMemory` backing
store is allocated once, rather than once per adapter or screen. Metadata changes
still always invalidate; watched changes still invalidate only while hide-watched
filtering is enabled. Observation begins only on Home's original initialization
path. The static callbacks retain no view, adapter, player or focus resource.
The generic cache and profile-session memory helper (121 lines) are now explicitly
registered in the measured source set. The latter gains only a read-only testing
getter for registered-store count; registration and clearing behavior are unchanged.

The screen no longer declares its private snapshot type, static cache, installed-
listener flag or listener-installation method. The existing store-eligibility test,
row/hero detachment, cached configuration bootstrap, original loadedAt, scroll and
first-frame restoration remain in presentation at the same lifecycle points. Legacy
row models retain the existing detached-container contract; this slice does not
claim newly deep-immutable metadata or move player/resource restoration.

Intentional ownership correction: a retired adapter's `take` returns before touching
the shared store. Previously a late outgoing take could discard an incoming owner's
entry through the generic mismatched-owner behavior. Late outgoing stores continue
to be rejected by the existing cache guards. Both cases are tested against an already
stored incoming snapshot.

The affected baseline passes 38 tests; the final focused run passes 46. Eight new
tests cover 100 fresh adapters with stable registered-store count, one-time
consumption, exact five-minute expiry, profile handoff with late stores/takes,
non-accumulating metadata/watched invalidation, provider disposal/recomputation, and
three real first-frame Home returns with no catalog refetch or registry growth.
Existing cache, profile-memory, progressive-return, default-view and display tests
pass. An initial missing loading-widget import in the new screen test and two
redundant imports identified by analyzer were corrected. Final analyzer identities
match the 863 baseline; changed-code formatting/diff checks pass, and all 294 measured
files pass the architecture guard. SearchScreen remains 19,351 lines under its
phase 5–8 exception. The completed full suite reports 8,851 successes, the same
22 failures / 29 errors and 20 skips as the verified PikPak-only checkpoint.
Test-identity comparison preserves every prior outcome and adds exactly the eight
successful tests above. Evidence: `home-return-*`, `analyze-home-return-*` and
`full-home-return*` under `.git/refactor-evidence/phase5/`. This proves the scoped
return-store/listener lifetime, not whole-app resource or native-player parity.
Remaining actions, standalone Home/Discover presentation, native/performance and
final size gates remain open.

Tracker-authentication checkpoint: a 51-line scoped Riverpod controller now owns
the three accepted authentication flags, keyed independently by tracker and mounted
Home/catalog view identity. A 28-line factory delegates to the original Trakt,
Simkl and MDBList authentication methods under the originating captured scope. The
nine-line model declares the tracker and reader/session contracts. Construction is
read-free; explicit startup and integration-change triggers remain unchanged.
Service errors still propagate, unchanged values do not repaint, and Trakt retains
its existing expired-token refresh policy. No dependency versions changed.

The view retains mode changes, query dispatch and TV focus. On MDBList disconnect,
Lists is cleared before authentication publication, then the mode falls back to
Catalog and the retained query/focus effects run in their original order. The
controller checks ownership again after both outgoing-state cleanup and state
publication. Each tracker has independent request ownership; an older read can no
longer undo a newer disconnect, and retired views/profiles cannot publish results.
This is an intentional race correction, covered through the real Search screen.
The three original mutable booleans and direct refresh reads are removed.

The affected baseline passes 34 tests. The expanded final run passes 64, including
17 new tests and the existing Trakt refresh/resource authorization suite. New
coverage exercises changed-only effects, before/after ordering, active failures,
overlapping reads, tracker independence, view/profile/disposal/recomputation
retirement, retirement during callbacks, real service authentication and expired
Trakt tokens without refresh credentials, rejected credential reads, and the actual
Lists disconnect race. Existing disconnect/reconnect query retention also passes.
A new unbraced-if analyzer diagnostic was corrected; final diagnostic identities
match the 863 baseline. All 297 measured files pass the architecture guard.
SearchScreen remains 19,385 lines under its phase 5–8 exception; this is state/data
ownership extraction, not completion of the standalone-view or final size gates.

The factory rejects stale calls before entering services and the controller rejects
late visible results. This does not prove cancellation of every in-flight legacy
authentication/vault operation: existing service refresh/write authorization remains
in place and its deeper boundary audit remains in phases 7–8. No whole-app native,
performance or resource-parity claim is made. Evidence: `tracker-auth-*`,
`analyze-tracker-auth-*` and `full-tracker-auth*` under
`.git/refactor-evidence/phase5/`. The completed full suite reports 8,868 successes,
the same 22 failures / 29 errors and 20 skips. Test-identity comparison against
`full-home-return.jsonl` preserves every prior outcome and adds exactly 17 successful
tests. Changed-code/stub formatting and diff checks pass. Remaining metadata/artwork
reads, actions, presentation and native/performance/final size gates remain open.

Episode-artwork checkpoint: Home's local, Trakt and Simkl continuation stills now
have one scoped 110-line Riverpod controller. It owns immutable accepted maps,
per-shelf request generations, captured episode references and metadata-settings
reload coordination. The 10-line model declares the three shelf identities and
typed episode/reader contracts. The 29-line plain repository preserves ordered
results, omission of null/empty images and the existing three-request concurrency
limit. Its 28-line factory injects the unchanged EpisodeArtworkService under the
originating captured scope and rejects already-retired owners before service entry.

The production screen now reads these snapshots and dispatches load/clear/refresh;
its three mutable artwork maps, batch resolver, metadata generation and request
registry are removed. Continuation refresh still clears before resolving. Metadata
settings still clear all retained stills synchronously and reload only current
shelves. Nonempty results retain add/replace semantics, empty results do not repaint,
and initial/recomputed providers perform no reads. Existing service memoization,
provider fallback and optional-artwork error behavior remain unchanged. The screen
keeps repaint, card image/fallback selection, focus, hero invalidation and rendering.

Ownership corrections: newer work for one shelf supersedes only that shelf; settings
refresh retires all outgoing batches; queued resolution stops once its request,
view or profile retires. Already-started service/network calls may still finish.
The existing service's internal metadata/provider/cache behavior is retained, not
claimed as newly fully cancellable or audited. Its deeper dependency review and
whole-app native/performance checks remain open.

The affected baseline passes 17 tests and the expanded run passes 33, adding 16
successful tests. Coverage includes out-of-order resolution with exactly three
workers, deterministic result order, immutable snapshots, empty/error behavior,
queued-read retirement, independent shelves, newer episodes, captured-reference
retention on settings reload, stale shelf filtering, profile/view/disposal/clear/
recomputation retirement, accepted-state retention and post-publication ownership.
The default factory rejects a retired owner before platform/service entry. A real
Spotlight Home card accepts the newer episode's image, clears/reloads it on metadata
settings changes, and rejects the old episode's late completion. Existing local,
Trakt, Simkl and service-artwork tests pass.

The initial screen fixture lacked the explicit Spotlight disk-cache platform setup;
a follow-up reached all assertions but stalled at cache cleanup after fake-frame
I/O. The final fixture uses temporary storage, seeded artwork, real asynchronous
frames and awaited cache disposal. No production cache code or exception handling
was changed to accommodate it. Failed/stalled receipts remain in evidence. Final
analyzer diagnostic identities match all 863 baseline entries, changed-code/stub
formatting and diff checks pass, and all 301 measured files pass the architecture
guard. SearchScreen remains 19,381 lines under its phase 5–8 exception. Evidence:
`episode-artwork-*`, `analyze-episode-artwork-*` and `full-episode-artwork*` under
`.git/refactor-evidence/phase5/`. The completed full suite reports 8,884 successes,
the same 22 failures / 29 errors and 20 skips. Identity comparison against
`full-tracker-auth.jsonl` preserves every prior outcome and adds exactly the 16
successful tests above. Remaining metadata/action responsibilities, standalone
presentation and native/performance/final size gates remain open.

### 6. Discover and remaining layouts

Metadata-feature policy checkpoint (shared with Catalog suggestions): a 64-line
scoped Riverpod controller owns the accepted immutable MetadataPreferences value,
readiness and request generation. Its 23-line factory delegates to the existing
MetadataPreferencesService with the captured owner/scope, and its 13-line model
declares the typed view-session, reader and policy records. These live under
`lib/features/discover/` because discovery availability is also the gate used by
Catalog title suggestions. This begins the Discover application boundary; source
selection/hydration and all layout extractions below remain unfinished.

Initialization retains the original early call position, before other Search/Home
provider setup, using an independent mounted-view identity. Settings invalidation
retains the previous policy while marking it unready, clears suggestions in the
view, and explicitly reloads. Successful reads become ready before the unchanged
suggestion scheduling and TMDB-to-Continue-Watching fallback callbacks. Ordinary
failed reads retain the existing state; failed settings reloads remain unready.
The legacy optional-load error envelope, including its presentation callback,
is preserved, and automatic retries stay disabled. Recompute/build never starts
reads or replays effects. Retired actions are rejected before dependency access;
late responses or ownership changes during publication cannot dispatch effects.
The screen's mutable policy, readiness flag and request generation are removed.

The observed affected baseline has 27 successes and two existing failures:
`unresolved suggestion submits Catalog title search (error: false/true)` in
`search_title_suggestions_test.dart`. The expanded run has 42 successes and the
same two failures. Fifteen new tests cover acceptance/readiness ordering, failed
read versus invalidated-read retention, newer disabled settings, independent views,
profile/view/disposal/recomputation/invalidation retirement, accepted-state retention,
post-publication ownership, default service decoding of changed/malformed settings,
and a retired default reader. Callback assertions are checked outside the retained
error envelope. A real Discover test selects TMDB, issues overlapping settings reads,
falls back to Continue Watching on the newer disable, and confirms that the older
enabled response cannot restore the TMDB option or embedded page. Existing language
refresh and Discover default/reopen/disable scenarios still pass.

Analyzer identities remain exactly the 863-entry baseline; formatting/diff checks
pass and all 304 measured files pass the architecture guard. SearchScreen remains
19,396 lines under its phase 5–8 exception. Evidence: `metadata-policy-*`,
`analyze-metadata-policy-*` and `full-metadata-policy*` under the existing
`.git/refactor-evidence/phase5/` directory. The completed full suite reports 8,899
successes, the same 22 failures / 29 errors and 20 skips. Test-identity comparison
against `full-episode-artwork.jsonl` preserves every prior outcome and adds exactly
the 15 successful tests above.
This does not close Discover source orchestration, presentation, native/performance,
or final size/boundary gates.

Discover-source checkpoint: the 153-line DiscoverSourceController now owns the
selected source, browsable addon inventory, explicit-selection revision, startup
request ownership and remembered-source write generation. Its 32-line model contains
the persisted source keys, typed view/session bootstrap and immutable published
inventory contract; the original landing-precedence helper moves there and its three
existing tests import that model directly. A 23-line plain repository retains the
parallel default/last preference reads and existing addon/writer boundaries, wired
by a 39-line captured-scope factory. Provider construction/recomputation starts no
loads or writes and retains already accepted state.

Fixed configured/remembered sources still paint before addon hydration. Addon
landings wait for browsable inventory and fall back to Continue Watching when
missing; a failed addon read retains the same empty-inventory fallback. Only TMDB
landing consults metadata-feature availability, and disabled TMDB still falls back
before addon hydration. Explicit selection wins over late startup preferences or
manifests. Search's MDBList handoff is consumed at the original initialization point
and seeds the provider's initial source, avoiding a provider-state mutation during
initState; its explicit remembered-source action still occurs before startup.
The full addon inventory still fills the view's shared lookup with putIfAbsent,
while only browsable addons enter the dropdown. Published list containers are
immutable; legacy addon objects retain their existing borrowed identity contract.

The screen's mutable source, revision and addon list, startup orchestration and all
three direct remembered-source writes are removed. It retains focus/preview cleanup,
metadata policy access, the shared metadata lookup and repaint callbacks. Source
selection still clears previews before changing source, starts persistence after
repaint, then schedules TV focus. Construction uses an independent mounted-view key;
Home/Search variants perform no extra source reads or writes.

Intentional retirement correction: superseded startup/selection requests and
retired profiles/views cannot commit queued remembered-source writes. The existing
`lib/services/storage_service.dart` (10,825 lines) remains a temporary external
storage boundary; this slice adds only the optional canContinue argument to
setDiscoverLastSource. Unguarded callers retain their original implementation.
Guarded calls discard foreign captured zones, capture current preferences only while
authorized, and recheck inside the existing mutation barrier immediately before
the nested setter. No preference key, validation rule, schema or unrelated storage
formatting changed. Remaining legacy storage/service internals are not claimed as
fully migrated; deeper dependency and final boundary audits remain required.

The affected baseline passes 14 tests and the final focused run passes 34. Twenty
new tests cover early fixed-source display, remembered/fixed preference
semantics, browsable/full inventory separation, immutable list containers, missing
addon and metadata-disabled fallback, selection/handoff precedence, independent
request/write retirement, profile/view/disposal/recomputation, overlapping startup,
read-free accepted-state retention, and preserved active preference-error behavior.
Actual preference writes blocked behind a snapshot are checked for selection and
profile retirement, plus active commit and existing key validation. A real Discover
screen paints Trakt while its injected inventory is pending, accepts a Simkl user
selection, then adds the delayed addon option without changing that selection or
rewriting the startup source. Existing TMDB reopen/default/disable and MDBList
handoff scenarios pass. Two newly introduced unbraced-if diagnostics were corrected;
final analyzer identities match all 863 baseline entries. Changed code/stubs pass
formatting/diff checks and all 308 measured files pass the architecture guard.
SearchScreen remains 19,347 lines under its phase 5–8 exception. Evidence:
`discover-source-*`, `analyze-discover-source-*` and `full-discover-source*` under
`.git/refactor-evidence/phase5/`. The completed full suite reports 8,919 successes,
the same 22 failures / 29 errors and 20 skips. Identity comparison against
`full-metadata-policy.jsonl` preserves every prior outcome and adds exactly the
20 successful tests above. Discover layouts,
caption overflow, preview/resource lifecycles, native/performance and final size
and boundary gates remain open.

Discover glass-stage presentation checkpoint: the remaining 407-line
`lib/screens/search/search_sources.dart` part is deleted, together with its part
directive. Its Discover-only visuals now live in three standalone presentation
widgets: backdrop (143 lines), tint veils (203), and grid dimming (77). Their bodies
compare unchanged against the prior revision after public-name and optional-key
normalization. Existing debounce, cached-image options, Android TV crossfade/snap
policy, gradients, animation durations, repaint boundaries and pointer behavior
are retained. The backdrop still owns only its dwell timer/subscription and borrows
its shown-title listenable; the other visuals borrow their signals. No player,
network service or application-state owner moved into these widgets.

The 157-line buildDiscoverGridLayout function now composes the two-pane layout
with explicit widget slots and borrowed signals. Production uses it with the same
detail rail, backdrop, trailer, tint veils and status-chip widgets. The original
rail-width formula/clamps, panel-specific MediaQuery width, layer order, theater
opacity/durations, takeover scrim and corner positioning remain. It adds no widget
boundary around the composition and owns no resources. SearchScreen retains the
TV/touch/media-server/compact selection and post-frame cleanup, Stage-style
composition, native/detail-rail bindings, and shared hero chips for subsequent
phases. Its build method still observes AppThemeScope, so theme-driven parent
rebuilds are preserved. Existing transitive detail-rail metadata/preview behavior
remains a phase-7 dependency audit, not newly claimed UI/data separation.

The affected baseline passes 24 tests. The final expanded check passes 38 and
retains the existing `no swept file grows a new bare radius` failure in
shape_manifest_test.dart, evidenced at the preceding full checkpoint. Twelve new
tests cover three panel widths and their clamps, stack ordering, theater/chip
transitions, retained text/editor state and focus through resizing, listener
cleanup, first-image versus debounced-image adoption, missing-background fallback,
pending-timer disposal, Android versus other crossfade behavior, both veil layouts
and Android/non-Android lights-up durations, and grid-dim alpha/pointer pass-through.
A real TV Discover grid shrinks to the compact panel, clears takeover/showing/theater
post-frame, restores its rail at full width and retains source selection with one
preference/addon read and no duplicate remembered-source write.

The first backdrop test assumed that removing current art also immediately removes
AnimatedSwitcher's outgoing child. The unchanged prior implementation retains the
outgoing entry's 240ms controller; coverage now checks the empty current child,
zero reverseDuration configuration and completed outgoing removal without changing
production timing. Public-widget key diagnostics and test-only protected-listener
access diagnostics were resolved; final analyzer identities equal all 863 baseline
entries. The deleted shape-manifest entry is replaced with zero-residue entries for
all four extracted files; the 490-call threshold and behavioral assertions are
unchanged. All 312 measured files pass the architecture guard. SearchScreen is
19,220 lines; three original parts remain. Evidence: `discover-layout-*` (including
body comparison and initial failing fixtures), `analyze-discover-layout-*` and
`full-discover-layout*` under `.git/refactor-evidence/phase5/`. The completed full
suite reports 8,931 successes, the same 22 failures / 29 errors and 20 skips.
Identity comparison against `full-discover-source.jsonl` preserves every prior
outcome, including the shape-manifest failure, and adds exactly 12 successful tests. Stage-style composition, caption overflow, remaining Home layouts,
native GPU/performance measurements and final size/boundary gates remain open.

Discover Stage-composition checkpoint: the 179-line buildDiscoverStageLayout
presentation function now owns the original Stage stack, shelf-metric calculation,
identity budget and theater transforms. The two private Stage-spacing constants move
with it. Production supplies the existing detail-rail builder and borrowed backdrop,
trailer, veils, indicators and listenables. The renderer adds no enclosing widget,
performs no data access and owns no player/focus/timer resource. SearchScreen retains
the native/detail-rail adapters and layout-selection/lifecycle wrapper; its old
composition body and direct shelf-scope import are removed.

The shelf still uses 30% of canvas height clamped to 140–200, 24-pixel horizontal
padding, the existing DiscoverShelfMetrics column calculation, and 22-pixel identity
clearance below a 62-pixel filter band. Identity width remains half the canvas
clamped to 320–560. Its browse budget is computed from the canvas, independently of
the theater animation. The original 900ms lights-down/250ms lights-up padding,
alignment, scale, panel slide/fade, repaint boundaries, stack order, takeover paint,
status position and pointer behavior remain. The panel stays mounted while faded.
The real detail rail still receives the 260ms settle delay; the backdrop still has
zero additional dwell and its existing platform-specific crossfade behavior.

The affected baseline passes 36 tests and the final focused run passes 40. Four new
tests cover three representative canvas sizes (including both shelf clamps), metrics
propagation, identity placement/budget, visual layer order, theater transforms and
indicator handoff, retained shelf text/editor identity/focus through theater and
resize, stable identity construction during signal-only animations, and listener
cleanup. The existing real grid-resize fixture now also exercises the actual Stage
layout, checking its detail-rail inputs, compact cleanup, restored source and one
preference/addon read with no duplicate remembered-source write. The original grid
test retains its name/path and continues to pass.

Analyzer identities match all 863 baseline entries, formatting/diff checks pass,
and all 313 measured files pass the architecture guard. The Stage composition is
added to the shape manifest with zero bare-radius residue; no assertion or threshold
is weakened. SearchScreen is now 19,070 lines under its phase 5–8 exception, with
three original parts still present. Evidence: `discover-stage-*`,
`analyze-discover-stage-*` and `full-discover-stage*` under
`.git/refactor-evidence/phase5/`. The completed full suite reports 8,935 successes,
the same 22 failures / 29 errors and 20 skips. Identity comparison against
`full-discover-layout.jsonl` preserves every prior outcome and adds exactly four
successful tests. This closes the Stage composition extraction, not native preview ownership, actual-device GPU or
performance parity, the favourites-caption overflow, Home layouts or final facade
and size/boundary gates.

#### Reviewed caption-height correction (intentional bug fix)

The phase-5 overflow was rechecked against `62f24fd8`. A `RenderParagraph`/
`TextPainter` probe measures two 18px lines (36px total), while the shared caption
budget reserved `14 × 1.25 × 2 = 35px`. The correction rounds each scaled line's
reservation upward before multiplying by the maximum line count. Every existing
favourites cell/hero/Stage/Mosaic consumer still uses the same shared budget;
poster aspect ratios, typography, title visibility, focus and refresh logic remain
unchanged. This deliberately adds 1px at normal scale (0.25px at scale 1.25),
rather than clipping text or reducing its size. Integer line heights are unchanged.

`test/features/home/home_favorite_caption_layout_test.dart` exercises the actual
SearchScreen and preference/database adapters with a fake channel database: publish
a long title, focus it, fail a refresh while retaining the caption, clear favourites,
and dispose. Twelve scenarios cover 800×600/1280×720, scales 1/1.25/2 and real bundled
Inter/Poppins faces. The test validates each asset's TrueType header and the rendered
font/scale; it does not silently rely on the invalid legacy Roboto font asset.
It asserts no framework exception at each transition and stable caption size through
failed refresh. Absolute position is intentionally not pinned: existing focus
handling scrolls the card into view. An initial position assertion was corrected;
failed diagnostic receipts are retained.

With the final regression assertions, the original screen passes 32 focused cases
and fails eight new overflow cases; after the fix all 40 pass. The four scale-2
cases already passed because their 35px line height needs no rounding. Existing
TV/IPTV/Stremio favourites, watchlist and playlist checks remain passing. Analyzer
identities remain exactly 863, and the 313-file architecture guard passes. Evidence:
`caption-*`, `analyze-caption-*` and `full-caption*` under
`.git/refactor-evidence/phase5/`. The first full-suite run
reproduced the previously recorded remote-transfer `.part` cleanup race and profile
identity-save timing failure. The unchanged transfer service publishes completion
before awaiting receipt persistence and partial-file deletion; the failing test
asserts immediate deletion. The profile test uses fixed wall-clock settling before
reading the saved name. Both test files pass independently (23 tests); the full run
ended after the profile-test cleanup timeout. Its terminal result is 8,945 successes,
23 failures / 30 errors and 20 skips; exact comparison changes only those two prior
passing tests and adds all twelve new successes. An unchanged full-suite repeat
completed with 8,947 successes, the same 22 failures / 29 errors and 20 skips.
Exact identity comparison against `full-discover-stage.jsonl` preserves every prior
outcome and adds exactly twelve successes (`full-caption-verified*` and
`caption-verified-comparison.txt`). No production code, test assertion or failure
allowance for these unrelated issues was changed. This closes the reproduced Latin-caption geometry
defect at the checked fonts/scales, not all-font,
native-renderer or whole-Home layout parity. Shared metrics and `_ArtPoster` still
need their planned presentation extraction; no new structural exception is added.

Home layout inventory rechecked against `kTvHomeStyleChoices` in
`lib/screens/settings/tv_home_style_page.dart` and `_buildBoardContent`: all eight
choices are enabled—Classic, Spotlight, Canvas, Atrium, Mosaic, Promenade, Deck and
Tonight. The six stage styles have their own board builders; Classic remains the
inline fallback and Spotlight has its own builder. Off-TV resolution deliberately
exposes only Classic/Spotlight without rewriting the stored TV preference. TV Search
uses `_buildSearchSpotlightBoard` before Home-style dispatch. Spotlight with only
favourites falls through to Classic because its shelves do not render those models.
These dispatch/fallback cases must survive the layout extraction.

#### Reviewed favourites-card presentation extraction

`lib/features/home/presentation/home_art_poster.dart` (281 lines) now owns the
artwork/fallback, badges, progress, caption and existing hover/key/focus behaviour.
All twelve real SearchScreen call sites use `HomeArtPoster`; the old `_ArtPoster`
classes were removed from the shared card part. The widget borrows its focus node
and dispatches explicit open/focus callbacks. Its image cache, decode widths,
contain-fit padding, animation helpers, theme reads and scroll-to-focus durations
are unchanged. No data access/controller/DI registration is needed for this leaf.
`home_card_style.dart` (20 lines) owns the caption metrics and the existing shared
red colour; the legacy catalog card and hero live chip now read that same colour
constant, keeping a single definition. The corrected caption-height contract from
`f013220c` remains shared by the widget and all reserving layouts.

Normalized class-body comparison against `f013220c` is identical after the public
name/style-identifier changes, optional widget key and comments/whitespace. Six
new direct widget tests exercise Enter/Space repeat and release, interrupted
activation on focus loss, borrowed-node reuse after removal, hover/tap dispatch,
optional title/live/progress rendering and 140ms TV/260ms off-TV scroll-to-focus.
The initial scroll checks needed an extra frame to start the post-frame animation;
the production callback/timing was not altered. The 40 existing real-screen
favourites/caption/watchlist/playlist checks pass before and after extraction;
the six direct checks pass after correcting that test scheduling assumption.
The original `LIVE` label retains the migration's existing localization exception.

Analyzer identities remain exactly 863. The 315-file architecture guard and diff
checks pass. The first full run caught an audit-registration mistake: placing the
new widget only in the residue-only manifest excluded its relocated shape-token
call from the aggregate count (489 instead of 490). It is now correctly registered
as a swept file with zero bare-radius residue. The manifest/location and 490-call
floor tests pass; the pre-existing bare-radius failure remains. No assertion or
threshold was weakened; the failed run is retained for review. The next full run
passes both corrected shape checks, but reproduces the previously documented
Xtream deadline race (`IOClient.send` after client closure at the unchanged
`xtream_codes_service.dart:314`). A deadline can expire while opening the output
file; `send(request)` is evaluated before the throwing `remaining()` argument,
leaving the request future without its timeout handler. The existing deadline-zero
probe documents this ordering. All ten unchanged ingest tests pass independently.
Both receipts remain available; no failure allowance or unrelated service/test was
changed. SearchScreen is 19,052 lines and the original card part is now 634 lines
(down from 912); all three remaining parts still require retirement.
Evidence: `art-poster-*`, `analyze-art-poster-*` and `full-art-poster*` under
`.git/refactor-evidence/phase5/`. The final unchanged full-suite run completed with
8,953 successes, the same 22 failures / 29 errors and 20 skips. Exact comparison of
`full-art-poster-final.jsonl` against `full-caption-verified.jsonl` preserves every
prior outcome and adds exactly six successful tests. This completes the card
extraction, not the surrounding Home layouts, native playback/preview
ownership, device/performance checks or final facade/size gates.

#### Reviewed favourites directional-navigation extraction

`lib/features/home/presentation/home_favorite_cell.dart` (97 lines) replaces
`_FavArtCell` at all twelve Classic/stage caller sites. The widget keeps the
borrowed row nodes, column index, child and directional callbacks; it owns no focus
node and remains excluded from focus traversal. Its required `onLeftEdge` callback
replaces the direct `MainPageBridge` dependency. The view passes a closure that
reads the current bridge callback when invoked, preserving route callback changes
without requiring a rebuild. Normal arrows, held-arrow overrides, neighbour focus,
first/last-column handling and key-up/non-TV bubbling are unchanged. No provider
or application controller is warranted for these view-owned focus operations.
The old wrapper class is removed from the card part.

A real-screen sidebar scenario was added and passed against the original widget
before extraction: replace the bridge callback after rendering, navigate left twice
with different callbacks, then retain focus through failed refresh and clear the
row. Six direct widget tests cover horizontal repeat traversal and both row edges,
vertical repeat fallback/overrides, horizontal override precedence, off-TV event
bubbling and passing activation/back keys to the parent. The affected baseline
(with the new sidebar test) has 29 passes; the expanded target has 35 passes.
Normalized wrapper bodies match after renaming, adding the optional key/required
callback and replacing the bridge invocation. Analyzer identities remain exactly
863; the 316-file architecture guard passes. The wrapper has zero shape residue
and no shape-token calls, so it belongs in the residue-only manifest; the existing
490-call swept-file floor is unchanged.

SearchScreen is 19,065 lines (the explicit dependency adds a line at each caller),
and the card part is now 543 lines. Evidence: `fav-navigation-*`,
`analyze-fav-navigation-*` and `full-fav-navigation*` under
`.git/refactor-evidence/phase5/`. The completed full suite reports 8,960 successes,
the same 22 failures / 29 errors and 20 skips. Exact comparison against
`full-art-poster-final.jsonl` preserves every prior outcome and adds exactly seven
successful tests. The remaining card part contains catalog-card rendering and
favourites row identifiers. Catalog
cards still use `MetadataPresentationMixin`, which reads metadata services, owns
retry/preload timers and a shared cache, and listens to policy/profile changes.
Its data/lifecycle boundary must be resolved before calling that card a completed
UI/logic separation; moving the same mixin dependency into a feature file alone
would not satisfy the destination. Native remote behaviour and the surrounding
Home layouts remain within the later device/lifecycle gates.

#### Reviewed shared metadata-cache prerequisite

Before moving the catalog card, its existing metadata dependency now delegates
resolved-result storage to `lib/core/metadata/metadata_presentation_cache.dart`
(59 lines). The process-wide `shared` instance replaces the mixin's static map;
visible card resolution and hero preloading both use it. Preparing the cache still
compares the current profile scope (including generation/epoch), revision and the
same JSON-encoded policy. Entries retain their original catalog-object keys and
presentation values, expire after 15 minutes, and remain bounded to 256 entries.
Preload reads do not consume/promote entries; visible reads remove before checking
freshness and successful results reinsert at the end. Updating an existing preload
entry refreshes its expiry without moving its insertion position. Retryable or
incomplete presentations are not stored. Callers still own relevance checks and
expiry checks at the original points; the cache does not cancel provider work or
add profile-write guarantees.

`MetadataPresentation` moved unchanged into a 13-line model file. The provider
service re-exports it for existing imports; its class body/const constructor and
legacy metadata values are unchanged. The core cache has no widget, service-call
or Riverpod dependency; profile identity is an explicit typed input. A constructor
clock permits deterministic cache checks while the shared production instance
keeps `DateTime.now`. The remaining 285-line mixin still owns resolution/retry/
preload orchestration, listeners and view publication; this prerequisite does not
claim that the catalog card's UI/logic separation is complete.

Existing metadata tests pass (47). Two new integration cases passed against the
original mixin before extraction and after it: cross-widget-type reuse survives
disposal, and hero preloading feeds a different card type while policy changes
invalidate the result. Assertions run outside the preload callback's existing
error-catching boundary; the initial fixture failure is retained. Twelve pure
cache tests cover equal-scope/policy retention, profile/generation/epoch/legacy
invalidation, revision/policy changes, object identity, consume-versus-peek reads,
partial/retry rejection, expiry records, capacity and both recency behaviours.
The expanded target passes all 61 tests. Analyzer identities remain exactly 863.
The architecture guard now includes both extracted files and treats core metadata
as data code for import checks; all 318 registered files pass. Formatting and diff
checks pass. Evidence: `metadata-cache-*`, `analyze-metadata-cache-*` and
`full-metadata-cache*` under `.git/refactor-evidence/phase5/`. The completed full
suite reports 8,974 successes, the same 22 failures / 29 errors and 20 skips. Exact
comparison against `full-fav-navigation.jsonl` preserves every prior outcome and
adds exactly fourteen successful tests. The later controller/adapter work must
borrow this same shared cache
rather than introduce a competing per-card cache or clear it on view disposal.

#### Reviewed catalog-card metadata ownership

The actual `_StremioCard` now binds to `HomeCardMetadataView` (103 lines) instead
of `MetadataPresentationMixin`. Its rendering, focus/hold animation and action
callbacks remain in the registered card part pending the next presentation move.
A normalized render-body comparison preserves all expressions after explicit
metadata-input and placeholder-argument substitutions. The adapter adds no render
object. The card part is 550 lines; the parent remains a temporary 19,067-line
composition/legacy responsibility exception under phases 6–8.

The 116-line controller owns accepted metadata, request generations and the
original bounded two-/four-second retries. Its 52-line plain repository borrows
the same process cache used by legacy heroes and preloading. The 73-line provider
factory captures profile scope, delegates existing preference/provider calls and
keeps the original diagnostic payload. The 76-line model supplies read-only
state and typed binding identity; legacy catalog objects retain their identities.
Provider build/recomputation is read-free; explicit view binding starts reads.
Same-title replacement retains approved artwork only within the same policy
and profile epoch, while recycled titles and policy changes reset it. Independent
mounted cards have independent operation state; successful cached data remains
shared. Disposal retires requests and cancels owned retries without writing other
providers. Covered routes continue accepting their in-flight response.

The outgoing-profile guard deliberately tightens ownership: an old mounted card
retires instead of resolving its old title through the newly active profile.
The incoming mounted view starts its own captured-profile binding. This is covered
at the controller/view boundary and is not proof of the complete native profile
handoff, which remains a phase-7 gate. The legacy mixin still serves hero surfaces;
its remaining orchestration must migrate before final retirement.

The observed affected baseline passed 91 tests; the wired expanded run passes
117. Twenty-six new cases cover read-free recomputation, independent siblings,
latest-action acceptance, profile/policy retirement, exceptions, cache freshness,
retry timing and cancellation, retained/recycled artwork, simultaneous policy and
item changes, covered routes, listener cleanup, captured-profile default adapters,
and a real SearchScreen card refresh with stable focus and catalog request counts.
The retry tests declare the already-locked `fake_async` 1.3.3 as a direct development
dependency; no package version changes. Analyzer identities have no additions:
863 becomes 862 by removing the existing undeclared-import warning in the IPTV
recovery test. All 323 architecture entries and formatting/diff checks pass.
Initial test compile/fixture failures and the analyzer warning are retained in the
local evidence; the widget fixture's fake-async pump deadlock was corrected without
changing production scheduling. Evidence: `card-metadata-*`,
`analyze-card-metadata-*`, and `full-card-metadata*` under
`.git/refactor-evidence/phase5/`. The completed full suite reports 9,000 successes,
the same 22 failures / 29 errors, and 20 skips. Exact comparison against
`full-metadata-cache.jsonl` preserves every prior outcome and adds precisely
twenty-six successful cases (`card-metadata-full-comparison.txt`).
Native/performance validation and the remaining layout/hero extraction stay open.

#### Reviewed catalog-card presentation and card-part retirement

`HomeCatalogCard` now lives in
`lib/features/home/presentation/home_catalog_card.dart` (558 formatted lines).
The actual `_BoardCell` caller uses it; existing Home/Search/Discover paths still
reach that same cell. The former `_StremioCard`, its private state and the card
part directive/file are removed. Two of the original four parts now remain:
hero and stage. The stage part is 1,685 lines and the parent is 19,061 lines;
these remain tracked temporary exceptions for the remaining layout/lifecycle
extractions, not completed components.

The card keeps one cohesive stateful presentation responsibility: poster layers,
focus/hover/hold animation, key/pointer dispatch and its poster hero shuttle.
The 501–800-line review found no data orchestration left in this widget: metadata
state stays behind the previously extracted view/controller. Splitting the owned
hold state across widgets would add unnecessary coupling; the existing image,
focus-rise, collection animation/glow and watched-badge widgets remain composed
children. Their transitive resource/service boundaries still require the final
phase-7/8 audit. The 558-line file satisfies the migration ceiling without a
handwritten part, mixin or parent-state reference. The constructor adds an optional
key; its prior call arguments remain unchanged. Focus nodes stay caller-owned.

The collection row and folder-tile models move unchanged from the misleading
service path to `lib/models/home_collection_rows.dart` (146 lines); the original
path is a one-line compatibility export. Keeping both models in one model library
preserves their private identity/index fast path, including duplicate-folder-ID
handling, without exposing internals or introducing a service boundary. Both
paths join the measured source set. Favourites row kind/reference move unchanged
into a 31-line feature model; all parent/stage references use the typed public
names. No order, index or equality rule changes.

Normalized source comparisons preserve the entire card body after names, the
existing focus-ring constant alias and optional key; the hero shuttle is unchanged
and the collection model body is byte-identical after import relocation. Shape
coverage follows the actual card path and retains its existing token-count floor.
Three real-screen tests now locate the public card name instead of the retired
private name; their behavior assertions remain intact. The observed baselines
pass 86 screen/interaction and 50 collection/model checks; the wired combined run
passes all 136. Six new direct tests cover Enter/Space release, 500ms hold fill and
completion on the following frame, repeat suppression, focus/disposal cancellation,
borrowed-node reuse, touch menu precedence, badges/progress, and distinct poster/
backdrop hero contexts on both push and pop. The initial hold fixture incorrectly
expected completion at exactly the animation duration; the corrected fixture pins
the original AnimationController frame boundary without changing production code.
Analyzer identities remain exactly 862. All 327 registered source files pass the
architecture check. Source-review and test receipts use `catalog-card-*`,
`analyze-catalog-card-*` and `full-catalog-card*` in
`.git/refactor-evidence/phase5/`. The completed full suite has 9,006 successes,
the same 22 failures / 29 errors and 20 skips. Exact comparison with
`full-card-metadata.jsonl` preserves every previous outcome and adds precisely
six successful cases (`catalog-card-full-comparison.txt`).
Device/performance and the remaining layout/hero lifecycle gates remain open.
The next `_BoardCell` extraction is recorded below.

#### Reviewed board-cell directional navigation

All seven original `_BoardCell` call sites now use the 196-line
`lib/features/home/presentation/home_board_cell.dart`. It composes the same
catalog card, borrows the same node/list and reports focus through the existing
callback. The wrapper remains non-focusable and excluded from traversal. The
right-arrow near-end check still runs on key-down and repeat, starting six cells
from the row end, before any horizontal override. Held vertical overrides,
ordinary-repeat fallback, left-edge dispatch, stopped right-edge traversal and
key-up/off-TV propagation retain their original ordering.

The only application boundary is now an explicit `onLeftEdge` presentation
callback. Every actual caller passes a closure reading
`MainPageBridge.focusTvSidebar` when dispatched; capturing its current value at
build time would break replacement without a rebuild. A real-screen test passed
before and after extraction with the sidebar action changed between two key
presses. The widget has no service or parent-state import, owns no node/controller,
and introduces no data state/provider. The old class is deleted from the stage
part (now 1,498 lines); the parent is 19,072 lines including the seven explicit
callbacks. Both remain temporary exceptions for remaining composition/lifecycle
work. No new oversized file or exception is introduced.

The observed existing baseline passes 61 checks; the new real-screen check also
passed before extraction. The final affected run passes 68 tests: those 61 plus
six direct navigation tests and the real-screen sidebar case. Direct cases cover
row-order repeats/edges, ordinary versus held vertical actions, prefetch threshold
and ordering with overrides, off-TV propagation without dispatch, child activation
versus parent Back, focus notifications and borrowed-node reuse. Normalized source
comparison preserves the complete original cell after class/key/callback changes.
Analyzer identities remain exactly 862; all 328 registered files pass the size/
import guard. The shape manifest includes the new view without changing its token
floor. Formatting/diff checks pass. Evidence: `board-cell-*`,
`analyze-board-cell-*` and `full-board-cell*` under
`.git/refactor-evidence/phase5/`. The initial test-file generation failed before
writing a file; that incomplete runner is not used as passing evidence. The final
verified run uses the actual six direct tests. The completed full suite reports
9,013 successes, the same 22 failures / 29 errors and 20 skips. Exact comparison
against `full-catalog-card.jsonl` preserves all prior outcomes and adds precisely
seven successes (`board-cell-full-comparison.txt`).
Remaining layout/hero presentation, native/profile handoff and performance gates
are still open.

#### Reviewed Classic lazy rows and entrance presentation

The production Classic path now uses `HomeClassicRows` (71 lines) for lazy row
construction, stable keyed relocation, footer placement, cache extent, padding
and entrance wrapping. The parent still projects its existing ordered Home rails
and chooses the existing skeleton/CW/favourites/catalog row builders; catalog
search continues using positional keys without reading Home order. The view
receives only explicit UI inputs and row/footer builders, borrows the existing
scroll controller, and snapshots the ordered ID list. No loading, navigation or
profile operation moved into this view. The parent is now 19,028 lines; remaining
Classic hero/native layers, layout dispatch and row projection remain temporary
phase-6/7 composition exceptions.

The key prefix stays `board-reveal-<generation>-`; Home IDs retain keyed row state
through insertion/reordering, while a new generation remounts entrances. Footer
rows remain outside entrance animation. The existing caller supplies a freshness
predicate reading the live board-applied timestamp; it is evaluated after each
lazy row build, retaining the 1,800ms threshold and first-six-row limit. Stagger
remains 60ms per row. Top/bottom padding stays 6 / (32 + anchor tail). The deprecated
`cacheExtent: 300` becomes `scrollCacheExtent: ScrollCacheExtent.pixels(300)`;
the installed Flutter `scroll_view.dart` directly maps the former API to this
exact value. There is no SDK/dependency upgrade or cache-policy change.

`HomeRowEntrance` (82 lines) is the unchanged one-shot animation moved from the
hero part, which is now 2,169 lines. Its 300ms ease-out fade/rise, delayed start,
reduced-motion settling, no restart on rebuild, and timer/controller disposal
remain intact. The legacy class is deleted. The normalized body comparison passes
after only class-name changes. The broader phase-7 animation/resource audit still
includes its existing curved-animation construction; this extraction does not
claim that all hero lifecycle responsibilities are finished.

The observed affected baseline has 78 successes and ten collection-responsive
failures across the two baseline runs. The wired combined run preserves all 78
successes and the exact same ten failure identities. Six new tests pass: keyed
Home relocation with retained focus/state and generation remounts; catalog keys,
footer placement and scroll geometry; lazy freshness ordering/first-six stagger;
delayed fade/rise without replay; reduced-motion cancellation; and disposal plus
initially settled-row behavior. The lazy-list fixture explicitly inspects cached
offscreen rows; its first attempt counted visible rows only. Initial compilation
required the rendering import for Flutter's new cache-extent type, then the wired
suite was rerun; failed receipts remain evidence, not passing verification.
Analyzer diagnostics fall from 862 to 861 solely by removing the old cache-extent
deprecation. All 330 measured files pass architecture checks. Formatting/diff
checks pass. Receipts: `classic-rows-*`, `analyze-classic-rows-*`, and
`full-classic-rows*` under `.git/refactor-evidence/phase5/`. The completed full
suite reports 9,019 successes, the same 22 failures / 29 errors and 20 skips.
Exact comparison with `full-board-cell.jsonl` preserves every prior outcome and
adds precisely six successful cases (`classic-rows-full-comparison.txt`).
Remaining Home layout composition, native handoff and device/profile performance
gates stay open.

#### Reviewed Home trailer transition presentation

The two Classic trailer transition builders now live together in
`lib/features/home/presentation/home_trailer_transitions.dart` (95 lines), with
explicit active flags, borrowed showing/takeover signals and child widgets.
The actual Classic composition calls both functions directly, preserving the
original widget tree without an extra wrapper element. Inactive calls return
the original child and subscribe to nothing. Both old parent methods are removed;
the retained parent is now 18,948 lines. The parent still owns trailer playback,
signals, hero/native composition and the informational takeover overlay; those
remain phase-6/7 extraction and lifecycle responsibilities.

The rows retain their original non-interactive graded veil, 900ms dim / 250ms
restore, ease-out curve and layer ordering. Board takeover retains the 240ms
follower tween, clamped opacity and 0.95 ticker cutoff. Focus and scroll remain
on the same child while hidden; child construction is retained across animation
frames. Neither helper creates a player, controller, timer or provider, and
listenable subscriptions remain owned by the existing framework builders.
Normalized comparisons preserve both complete original bodies after public names
and explicit inputs; callback/child ordering at production call sites is unchanged.

All 45 observed affected tests pass before and after. Five new tests pass for
inactive identity/no subscriptions, asymmetric fade timing and tap propagation,
retained focus/scroll/child state with hidden tickers and Select dispatch,
listenable cleanup and both out-of-range takeover clamps. The new tests initially
used deprecated `TickerMode.of`; they now use the equivalent
`TickerMode.valuesOf(...).enabled` and pass again. Analyzer identities are exactly
861 after that test-only correction. All 331 architecture entries and formatting/
diff checks pass. Evidence: `trailer-transitions-*`,
`analyze-trailer-transitions-*`, and `full-trailer-transitions*` under
`.git/refactor-evidence/phase5/`. The completed full suite reports 9,024 successes,
the same 22 failures / 29 errors and 20 skips. Exact comparison with
`full-classic-rows.jsonl` preserves all previous outcomes and adds precisely five
successes (`trailer-transitions-full-comparison.txt`). These checks establish
transition presentation behavior, not native playback or whole-layout performance;
those required gates remain open.

#### Reviewed informational trailer takeover overlay

The Classic trailer title/metadata overlay now lives in
`lib/features/home/presentation/home_takeover_info.dart` (236 lines). Its actual
call site passes the original screen context and the existing hero-item,
enrichment and takeover listenables. The overlay and two metadata-label helpers
are removed from the parent, now 18,725 lines. This is one cohesive presentation
responsibility: the existing lower-left title/metadata block and its staged
animation. It has no player/service/DI dependency, navigation or persistence.

Original metadata precedence is retained: the title and optional year come from
the catalog item; rating/runtime use enrichment only when absent; genres use
nonempty item genres before enrichment and display at most three. Title casing,
rating precision, labels, typography, theme tokens and text limits are unchanged.
The existing app-owned English kicker remains within the migration's legacy
localization exception. The original screen context is explicit, including inside
metadata helper calls, so nested builder contexts do not change theme lookup.

The existing <=0.001 hidden threshold, per-field rise/fade windows, accent scale,
46px horizontal slide, 720px text limit and lower-left insets stay intact. Text
widgets are still constructed on item/enrichment changes and reused across
per-frame takeover updates. The overlay remains IgnorePointer and owns no focus
or native resource. Empty hero state observes only the item; nested enrichment/
takeover subscriptions are released when the item clears or the view unmounts.
The complete overlay and helper bodies match after explicit inputs/function names
and whitespace/comma normalization. Its shape-token call moves into the main
shape manifest, preserving the existing aggregate floor rather than losing a
call from coverage.

All 45 observed affected tests pass before and after. Four new tests pass for
empty/cleared hero subscription lifecycle, primary/fallback metadata and genre
limits, exact title rise/fade samples with text-object retention, and settled
geometry with touch passthrough. These are logical-layout tests using deterministic
test typography; they do not establish native font/device performance parity.
Analyzer identities remain exactly 861. All 332 measured files pass size/import
checks; formatting/diff checks pass. Evidence: `takeover-info-*`,
`analyze-takeover-info*`, and `full-takeover-info*` under
`.git/refactor-evidence/phase5/`. The completed full suite reports 9,028 successes,
the same 22 failures / 29 errors and 20 skips. Exact comparison against
`full-trailer-transitions.jsonl` preserves every previous outcome and adds exactly
four successes (`takeover-info-full-comparison.txt`). Remaining Home layout
composition and hero/native lifecycle/device/performance gates stay open.

#### Reviewed Classic layout composition

The production Classic path now delegates sizing and surface ordering to
`lib/features/home/presentation/home_classic_layout.dart` (42 lines). It retains
the same LayoutBuilder and expanding Stack, with explicit builders for board,
trailer, live feed and information. The screen still supplies its current viewport
width and TV hero-budget operation; off-TV height remains 196 below 900px and
300 from 900px upward, using viewport width even when the board pane is narrower.
TV sizing still uses the board's constrained height and the original header/row
budget. Takeover signal changes do not resize the hero band.

The original board subtree, native trailer arguments, live-feed arguments and
information-overlay arguments are unchanged by normalized full-expression
comparison. Paint order remains receding board, trailer, live feed, information;
the two video surfaces keep their Positioned.fill wrappers. Inactive trailers
construct none of those three overlay surfaces and subscribe to no takeover
signal. The layout owns no native player, focus node, controller, service or
application state. The parent's retained 18,657 lines still include layout
selection, Classic hero/row projection and native compatibility surfaces, with
those responsibilities scheduled for the remaining phase-6/7 extractions.
This is composition separation, not a claim that the complete Classic/native
lifecycle boundary has been migrated.

All 65 observed existing checks pass before and after. Four new cases cover
899px/900px off-TV sizing, TV constrained-height budgeting, fixed hero geometry
during takeover, explicit layer order, retained editor text/focus and surface
state through resize, and inactive builder/subscription suppression. The native
surfaces in these tests are stateful stand-ins; actual playback/device/resource
performance remains a required separate gate. Analyzer identities remain exactly
861 after removing a now-redundant context qualifier; the initial diagnostic is
retained in the evidence. The completed full suite reports 9,032 successes, the
same 22 failures / 29 errors and 20 skips. Exact comparison against
`full-takeover-info.jsonl` preserves every previous outcome and adds exactly four
successes (`classic-layout-full-comparison.txt`). All 333 registered files pass
size/import checks;
formatting/diff checks pass. Evidence: `classic-layout-*`,
`analyze-classic-layout*`, and `full-classic-layout*` under
`.git/refactor-evidence/phase5/`.

#### Reviewed Tonight card caption and display dependencies

The real Tonight card now uses the 221-line
`lib/features/home/presentation/home_tonight_card_caption.dart`. The private
caption, card-info type and shared favourite-focus type are removed from the
stage part. `HomeTonightCardInfo` is a 20-line immutable feature model;
`HomeFavoriteFocus` is a 14-line presentation descriptor because its artwork fit
is a UI value. Existing focus notifiers retain their owner and typed values;
all Canvas/other-layout callers use the same renamed descriptor. The original
art/title/subtitle/fit defaults and action/hold/episode/progress fields are unchanged.

The shared stage logo derivation and canonical-title match now live in a 22-line
plain application policy; all original callers use it. The caption's remaining-
time formatter moves into a separate ten-line plain policy. These stateless
operations need no new provider/controller and make no service calls. The
remaining-time parser deliberately retains its original first-number/minute
contract, including rounding/clamping and its limitation on hour-formatted input;
changing runtime interpretation would be a separate behavior fix. Existing English
labels retain the plan's legacy localization exception.

The caption still observes favourite focus first; favourite content suppresses
catalog/metadata/info subscriptions, progress and hold hints. Catalog mode still
accepts enrichment only for matching raw/canonical IDs, applies the existing
metadata policy to titles/logos/runtime, and suppresses derived-logo fallback when
that policy disallows it. Image decode/fade/error fallback, text limits, row spacing,
action hints and progress rendering are preserved. Complete body comparisons
cover the caption, both descriptors, both shared metadata helpers and the time
formatter after public names/optional widget key and relocation. The shape-token
calls move into the main manifest without reducing its aggregate floor.

The observed affected baseline and wired run both pass 88 tests, including real
Tonight late-catalog/covered-route/pagination paths and other stage layouts using
the shared dependencies. Seven new tests pass: three pure policy cases with
identity/logo/time vectors and four widget cases for favourite precedence and
cleanup, unrelated-enrichment rejection, canonical policy/fallback handling, and
empty/progress states. Analyzer identities remain exactly 861 after the final check. The first full
suite has one additional failure in the unchanged remote-transfer large-binary
test: its completion observation races `.part` cleanup. The same failure exists
in earlier `full-caption.jsonl` and `full-display.jsonl` receipts; the service
sets the receipt complete before awaiting journal/partial cleanup. All eighteen
transfer tests pass in isolation (`tonight-caption-transfer-isolated.txt`). An
unchanged full-suite repeat (`full-tonight-caption-verified.jsonl`) reports 9,039
successes, the same 22 failures / 29 errors and 20 skips. Exact comparison with
`full-classic-layout.jsonl` preserves all previous outcomes and adds precisely
seven successes (`tonight-caption-full-verified-comparison.txt`); the first
receipt/comparison is retained. All 338
measured files pass size/import checks. The stage part is now 1,224 lines and the
parent 18,661; both remain temporary exceptions for the remaining layout/hero
work. Evidence: `tonight-caption-*`, `analyze-tonight-caption*`, and
`full-tonight-caption*` under `.git/refactor-evidence/phase5/`. Native/device and
performance gates remain open.

#### Reviewed Tonight Continue Watching queue row

The real Tonight queue now uses
`lib/features/home/presentation/home_tonight_queue_row.dart` (310 lines), replacing
the original private row/state in the stage part. This is one cohesive row-view
responsibility: thumbnail/title/episode/progress, focus chrome, pointer/key dispatch
and the owned hold-feedback controller. Its caller still owns focus nodes, queue
selection, hero updates, navigation, playback/menu actions and held-down escape.
The row introduces no service or Riverpod state. The 310-line size is within the
cohesive-file band; no numeric exception or private-state fragment is added.

The original 500ms hold fill/completion behavior, short-release open, repeat
suppression, focus-loss cancellation and controller disposal remain unchanged.
Up/Down/Left dispatch and swallowed Right retain their original repeat/key-up
rules, including optional held-Down override. Focus still invokes its callback
and schedules the same 140ms centered scroll. Touch handlers, thumbnail decode/
fade, bookmark, episode/progress rendering and shape tokens are unchanged.
Complete source comparison passes after class/private-state names, optional key
and the relocated artwork-policy call; the old class is removed.

Wide background derivation, background/derived-still/poster precedence and the
top-level nonempty field helper move into the existing plain stage metadata
policy (now 45 lines). Every original stage/wide-art caller uses those functions.
Their complete bodies are unchanged; the parent's separate member helper remains
untouched in this slice. The source policy still performs no data access and does
not trim strings or change fallback order. Shape coverage follows the row's new
path and keeps the existing 490-call token-count floor. The initial full run caught
a stale stage-file manifest entry after its last shape-token calls moved to the
queue row; that empty entry is removed, and both manifest-coverage checks pass.
The existing bare-radius baseline failure is unchanged. The stage part is now 898 lines;
the parent is 18,662. Both remain temporary exceptions for the remaining phase-6/7
presentation and lifecycle work.

All 45 observed existing tests pass before and after, including the real Tonight
late-catalog paths and Continue Watching hold settings. Ten new tests pass: two
wide-art/field policy cases plus eight row interaction cases covering Enter/Space,
hold completion/release, focus/disposal cancellation, directional repeats and
held-down fallback, touch actions/progress, borrowed-node reuse and the original
scroll duration/alignment. Size/import checks pass for all 339 measured files;
source and formatting/diff checks pass. All 861 analyzer diagnostic identities
match the prior checkpoint. The corrected full suite has 9,049 successes, the same
22 failures/29 errors/20 skips, with every prior test outcome preserved and all ten
new cases passing. The initial manifest failure and corrected repeat are both
retained; no failure allowance or threshold changed. Evidence: `tonight-queue-*`, `analyze-tonight-queue*`, and
`full-tonight-queue*` under `.git/refactor-evidence/phase5/`. Native/device,
remaining layout composition and performance gates remain open.

#### Reviewed shared Home stage artwork view

All six Canvas/Promenade/Atrium/Mosaic/Deck/Tonight artwork callers now use
`lib/features/home/presentation/home_stage_art.dart`. The standalone view retains
its three borrowed listenables, matching-title metadata policy, favourite override,
contain/cover geometry, decode sizes, zero image fade and 240ms expanded-child
switcher. The opaque floor and image switcher remain below the caller-owned native
video layers; this slice does not move player ownership or claim native parity.
The complete render body matches the original after naming, optional key and
failure-memo calls. The original class and memo are removed from the stage part.

`HomeStageArtFailures` is a small plain application policy for failed derived
backdrop URLs. One library-owned instance retains the original process lifetime;
this is the existing shared image-failure cache, not new application state.
Set membership and the clear-before-add rule at 512 entries are unchanged,
including duplicate insertion at capacity. No provider, storage or new cache
framework is introduced. The view owns rendering and image-error dispatch.

The observed baseline has 37 passing tests. New coverage checks canonical metadata
matching, sparse metadata and disabled fallback, favourite contain/cover/empty
art, poster fallback and memo reuse across view recreation, 240ms expanded image
transitions, opaque empty floor and borrowed subscription cleanup. Two pure memo
tests exercise all 512 retained entries, eviction and duplicate behavior. An
initial fixture read the default image manager before binding initialization;
that unnecessary read was removed. The first bounded widget fixture mounted
hundreds of images and exhausted file descriptors after its assertions passed;
the bounded policy now has pure tests, and image behavior remains covered by
widget tests. No production timing was changed to accommodate those fixtures.

All 43 affected tests pass (37 existing plus six new), all 861 analyzer diagnostic
identities match the prior checkpoint, and 341 measured files pass size/import
checks. New files pass formatting and the diff is clean. The full suite has 9,055
successes, the same 22 failures/29 errors/20 skips, every prior outcome preserved
and all six new cases passing. Evidence lives under
`.git/refactor-evidence/phase5/stage-art-*`, `analyze-stage-art*` and
`full-stage-art*`. The remaining stage part is 720 lines and still requires
retirement; the parent is 18,663 lines and remains a documented temporary
exception. Native playback, remaining layout composition, lifecycle and
performance gates remain open.

#### Reviewed shared stage shading presentation

Canvas, Promenade and Atrium now use the standalone
`lib/features/home/presentation/home_stage_scrims.dart` (160 lines), including its
three typed variants. The complete original gradients, layer order, dimensions,
900ms theater fade-out, 250ms return and ease-out curve are preserved by source
comparison after public names and optional key. The real callers keep their
existing IgnorePointer placement, theater state and native-layer ordering. The
old enum/widget are removed; no service, provider or resource owner is added.

The preceding artwork full run supplies the observed baseline, including all
31 progressive Home screen tests. Those same 31 tests and four new shading tests
pass after extraction. The new tests exercise all three variants' actual fade
values/durations, expanded viewport geometry, stable gradient children and
mid-transition variant/width changes. All 861 analyzer identities are unchanged;
342 migrated files pass size/import checks and new files pass formatting.
Evidence: `stage-scrims-*` and `analyze-stage-scrims.txt` under
`.git/refactor-evidence/phase5/`. This bounded paint-only extraction uses affected
checks; the most recent full-suite evidence remains the preceding artwork run
(9,055 successes and the same 51 failures/errors, 20 skips), not a claim that the
full suite ran again after this change. Native compositing remains a later gate.

The remaining stage part is 562 lines and still must be retired. The parent is
18,664 lines; both remain documented interim boundaries for layout/hero/resource
separation, not the destination architecture.

#### Reviewed shared stage title/metadata identity

All five Canvas/Promenade/Atrium/Mosaic/Deck identity callers now use
`lib/features/home/presentation/home_stage_identity.dart` (329 lines), including
the four existing variants and narrow-column height calculation. The shared
headline logo/text dimensions move with the view; Mosaic's band still reads those
same constants, so the layout and render sizes cannot drift. This remains one
cohesive presentation responsibility in the 301–500 line band. No state container,
service access, or new interface is introduced.

Complete source comparison passes after public names, optional key and shared
constant names. Matching/canonical title acceptance, sparse and selected-provider
field precedence, title/logo loading/error behavior, all variant geometry,
220ms identity switching, 480ms metadata fade and fixed synopsis slots are
unchanged. The caller retains favourite selection, native playback ownership,
layout selection and theater state. The old enum/helper/widget and duplicate
constant declarations are removed.

All 43 observed existing tests pass before and after, with eight additional
checks for each variant's stable late-synopsis layout, genre/title rules,
matching/provider metadata policy, blank logo loading and error fallback sizing,
trailer fade excluding the title, borrowed-listener cleanup and scaled narrow
threshold. These are host widget tests, not native-font/compositing evidence.
All 861 analyzer diagnostic identities match the prior checkpoint, and 343
measured files pass size/import checks. New source/test formatting and diff checks
pass. The full suite covering this extraction and the preceding shading change
has 9,067 successes, the same 22 failures/29 errors/20 skips, every prior outcome
preserved and all twelve added tests passing (eight identity plus four shading).
Evidence: `stage-identity-*`,
`analyze-stage-identity.txt` and `full-stage-identity*` under
`.git/refactor-evidence/phase5/`.

The remaining stage part is 251 lines (row/rail view contracts, placeholders,
favourite identity and corner painter); it still requires retirement. The parent
is 18,662 lines and remains a temporary exception for the remaining view, action
and lifecycle boundaries. No phase or native/performance gate is closed here.

#### Reviewed shared Home row/rail presentation contracts

`lib/features/home/presentation/home_stage_rows.dart` (109 lines) now owns the
continuation-kind enum, continuation row, Home rail, resolved stage rail and
Tonight queue-entry contracts. All actual construction and use sites reference
these public types. They stay in presentation because they carry borrowed focus
nodes and UI callbacks; they are not application-state models or a second state
owner. Collections and nodes retain their original live references and ownership.
The file documents that layouts must not mutate/dispose these borrowed resources.

Every field, enum value, default, const constructor and callback signature matches
the original after naming. Complete parent source comparison also passes after
only those names and the new import. Existing row ordering, progress lookups,
late updates, menu/playback dispatch and focus ownership are untouched. No
constructor-only tests are added for this mechanical contract move. All 39
observed baseline tests pass again, and the expanded actual-screen checks for
local/Trakt/Simkl/MDBList/IPTV continuation bring the passing total to 66.
All 861 analyzer identities remain unchanged; 344 migrated files pass size/import
checks. Evidence: `stage-rows-*` and `analyze-stage-rows.txt` under
`.git/refactor-evidence/phase5/`. The preceding full-suite evidence remains
`full-stage-identity` (9,067 successes, same 51 failures/errors and 20 skips).

The stage part is now 149 lines, retaining loading placeholders, the favourite
identity and the corner painter; those are still pending extraction. The parent
is 18,663 lines, with layout construction/actions/resources still to separate.
This prerequisite does not itself close the layout or native/performance gates.

#### Reviewed Trakt loading-row presentation

The real reserved Trakt row uses the standalone 63-line
`lib/features/home/presentation/home_trakt_skeleton_row.dart`, with its sized
poster helper kept private. Complete body comparison preserves the six lazy
horizontal placeholders, supplied header, static ShimmerBox, dimensions, padding,
clipping and non-scrollable physics. No polling, focus, animation or data owner
moves into the view. The initial import cleanup removed a still-used dependency
for BrandLoadingStage; compilation caught it, and the parent now explicitly
retains that symbol. The corrected run passes all 47 Trakt/row-order/progressive
screen tests and preserves all 861 analyzer identities. Size/import checks pass
for 345 files. Evidence: `stage-skeleton-*` and `analyze-stage-skeleton*` under
`.git/refactor-evidence/phase5/`. Existing full-suite baseline is unchanged;
retirement-wide verification follows the remaining two presentation extractions.
The stage part is 89 lines and remains temporary; native/compositing checks remain
open. No trivial constructor/render-copy tests were added for this body move.

#### Reviewed favourite stage identity

All five stage callers now use the 56-line
`lib/features/home/presentation/home_stage_favorite_identity.dart`. Its complete
body matches the original after the public name and optional key. Left/center
alignment, title/subtitle text, line limits, theme colors, spacing and shadows
are unchanged. Favourite selection and subscriptions stay with the composing
view; this widget receives the existing typed focus descriptor only. All 58
favourite/playlist/caption/progressive screen checks pass, and all 861 analyzer
identities are preserved. Size/import checks pass for 346 measured files.
Evidence: `stage-favorite-*` and `analyze-stage-favorite.txt` under
`.git/refactor-evidence/phase5/`. The stage part is now 40 lines, with only the
corner painter and stale historical comments left; the full retirement check
follows that final extraction. Native layout/font checks remain open.

#### Stage part retirement: corner painter and final review

Deck and Tonight now use the standalone 28-line
`lib/features/home/presentation/home_stage_corner_painter.dart`. Complete painter
body comparison preserves path difference, radius/color and repaint eligibility.
The production CustomPaint placements and layer order are unchanged. Two raster
checks exercise zero and rounded radius: the corners receive the requested ink,
while the center and straight-edge video area remain transparent. These host
raster checks do not establish native video punch-hole/compositing parity.
All 31 progressive Home tests and both new raster checks pass. All 861 analyzer
identities match the preceding checkpoint, and 347 measured files pass size/import
checks. New files pass formatting and the diff check passes.

With every remaining declaration extracted and actual callers wired, the obsolete
`lib/screens/search/search_stage_widgets.dart` and its `part` directive are
removed. Orphaned comments for previously extracted classes are removed with the
file. Three of the original four handwritten parts are now retired; only
`search_hero_widgets.dart` (2,169 lines) remains. The parent is 18,665 lines and
still has substantial layout, action and lifecycle responsibilities, so this is
not completion of the phase or destination architecture.

The first full retirement run had 9,068 successes and one extra failure in the
unchanged remote-transfer large-file test: the same line-313 leftover `.part`
race recorded at earlier caption/display checkpoints. Source review confirms the
service still advertises completion before awaited journal/deletion cleanup. All
18 isolated transfer tests pass. Both receipts are retained; no failure allowance
or production timing changed. The second unchanged run restored the transfer
outcome but hit the previously recorded Xtream deadline/client-closed race at
service line 314, matching `full-art-poster-verified`. The service starts
`client.send` before evaluating its remaining deadline after asynchronous file
open; that source and test are unchanged. All ten isolated Xtream tests pass.
The final unchanged full run has 9,069 successes, the same 22 failures/29 errors/
20 skips, every prior outcome preserved and both new painter tests passing. All
three full receipts and both isolated reruns remain in evidence; the final run
is the authoritative retirement comparison. Evidence:
`stage-retirement-*`, `analyze-stage-retirement.txt` and `full-stage-retirement*`
under `.git/refactor-evidence/phase5/`. All native/device, remaining layout,
resource ownership and performance gates remain open.

#### Reviewed Canvas geometry and theater composition

`lib/features/home/presentation/home_canvas_layout.dart` (171 lines) now owns
Canvas's geometry and layered composition: clamped card sizing, orientation and
favourite widths, shared shelf/caption/tab clearance, art/trailer/live order,
shading, identity movement/scale and shelf fade/slide/crossfade. The real Canvas
caller retains its original LayoutBuilder and null/loading resolution, focus
seeding, surface construction, view signals, tab construction and keyed lazy
shelf/card action callbacks. It passes explicit presentation slots and dimensions,
not the parent state. Native surfaces are still constructed conditionally in that
LayoutBuilder; no new widget layer or resource owner is inserted.

Source comparison covers the entire geometry block and Stack tree, all five
artwork/trailer/live/identity/tab expressions, and both complete lazy-list branches.
Only the explicit inputs/slots and constant location differ. The original 900ms
lights-down/250ms return, 200ms shelf switch, decode/request parameters, cache
extent, keys, action guards and focus callbacks are unchanged. The four Canvas
spacing constants now have one owner with their original comments and values.
The parent decreases by 142 lines to 18,523; its remaining Canvas row/action
construction is deliberately still tracked for further view separation.

All 47 observed baseline tests pass again. Four additional layout cases cover
minimum/proportional/maximum card geometry, landscape and favourite widths,
layer order, theater identity movement, caption/tab clearance, shelf editor/focus
retention, stable surface State through transitions and resize, and absent native
surfaces. These use host stand-ins for native surfaces and do not establish
playback/compositing parity. All 861 analyzer identities remain unchanged;
348 measured files pass size/import checks, and new files pass formatting.
The full suite has 9,073 successes, the same 22 failures/29 errors/20 skips,
every prior outcome preserved and all four new layout tests passing.
Evidence: `canvas-layout-*`,
`analyze-canvas-layout*` and `full-canvas-layout*` under
`.git/refactor-evidence/phase5/`. Remaining layout, native, lifecycle and
performance gates remain open.

#### Reviewed Canvas lazy shelf presentation

The two Canvas shelf branches now use the standalone 35-line
`lib/features/home/presentation/home_canvas_shelf.dart`. The shared lazy list
retains its original rail key, horizontal axis, hard clipping, 48-pixel outer
padding, seven-pixel card padding and centered sizing. Catalog/continuation cards
keep their fixed art height; favourites keep the original null/intrinsic height.
It returns the ListView directly so the owning AnimatedSwitcher still sees the
same widget type and rail identity. The screen supplies count/width/height and
the existing card builder; selection, focus, playback/menu and pagination
callbacks remain unchanged. Source comparison covers both complete card
expressions and all Canvas code preceding the shelf.

The installed Flutter SDK maps deprecated `cacheExtent` directly to
`ScrollCacheExtent.pixels`; the extracted shelf uses that equivalent API with the
same 400-pixel value. This removes two legacy deprecation diagnostics without
changing caching behavior: 859 analyzer identities remain, no added diagnostics.
All 41 observed baseline tests pass again plus four new cases for lazy creation,
fixed/intrinsic geometry, appended-row scroll/focus retention, borrowed-node reuse
and actual Canvas rail-switch crossfades. An extra closing parenthesis in the
initial new fixture was corrected before these passing checks. All 349 measured
files pass size/import checks; new files pass formatting and the diff is clean.
The parent decreases by another 49 lines to 18,474.

Evidence: `canvas-shelf-*` and `analyze-canvas-shelf*` under
`.git/refactor-evidence/phase5/`. This bounded list-presentation extraction uses
45 affected checks; the latest full-suite evidence is the preceding
`full-canvas-layout` run (9,073 successes, same 51 failures/errors and 20 skips),
not a full run after this change. Layout action construction, remaining variants,
hero/lifecycle and native/performance gates remain open.

#### Reviewed Canvas rail-tab presentation and shared metrics

`lib/features/home/presentation/home_canvas_tabs.dart` (155 lines) now owns the
read-only tab window, chevrons, active underline/style and text-scaled height.
The four original metrics retain one owner, including the chevron floor shared
with Promenade's label height. The actual Canvas caller supplies rail count,
active index and a narrow lazy title lookup; title/provenance disambiguation is
byte-identical in the parent and remains shared by the other layouts. Tabs do
not own rail navigation or add focus handling. The caller explicitly passes its
original State.context, preserving theme capture before the inner LayoutBuilder.

Full builder-body and metric comparisons pass after the explicit input/name
changes. Visible-window sizing/clamping, zero-label and single-active-label
behavior, hidden-tail count, empty-title slots, typography and shape calls are
unchanged. The shape manifest follows the moved token call with the same 490-call
floor; its two coverage checks pass and the existing bare-radius failure remains.
All 49 observed baseline tests pass again, plus seven cases covering zero/one/two/
four visible slots, first/last rails, empty labels, lazy lookup, active styling,
scaled clearance and uninterrupted owner keyboard handling. Two new fixture
style lints were corrected before final analysis. No production behavior changed.

The parent decreases by 141 lines to 18,333. All 350 measured files pass size/import
checks; changed new files pass formatting and the diff check passes. All 859
analyzer identities match the preceding checkpoint. The full suite has 9,084
successes, the same 22 failures/29 errors/20 skips, every prior outcome preserved
and all eleven added shelf/tab tests passing. Evidence:
`canvas-tabs-*`, `analyze-canvas-tabs*` and `full-canvas-tabs*` under
`.git/refactor-evidence/phase5/`. Remaining layout/action construction, hero,
native/lifecycle and performance gates remain open.

#### Reviewed Promenade composition and centered strip

`lib/features/home/presentation/home_promenade_layout.dart` (152 lines) now owns
Promenade's layer composition, bottom-column clearance, half-viewport strip
padding, lazy list and theater transitions. The real caller retains its original
LayoutBuilder, rail resolution/focus seeding, shared card-dimension policies,
conditional native construction, metadata signals and cell actions. The same
favourite/meta cell expressions are supplied through a narrow indexed builder.
No parent state or new resource owner is passed into the composition.

Complete source comparison covers the Stack/list/transition tree, column/side-pad
geometry, original rail-resolution/size-selection prefix and all seven supplied
artwork/native/identity/label/cell expressions. Constants, rail identity, clipping,
card padding, 900ms theater entry/250ms return, centered-to-corner identity move,
0.7 scale and 0.12 shelf slide remain unchanged. The installed SDK's equivalent
`ScrollCacheExtent.pixels(400)` preserves the old list cache and removes its one
legacy deprecation; no version or dependency changes occur.

All 47 observed baseline tests pass before extraction. Four new host cases pass
for narrow/wide/oversized-card side padding, lazy construction, surface order,
caption clearance, retained focus/scroll/surface State through theater and resize,
and keyed rail replacement without native surfaces. Native compositing/playback
parity still requires its device gates. The parent decreases by 125 lines to
18,208. All 351 measured files pass size/import checks; source and diff checks
pass. All 51 affected tests pass (47 existing plus four new). Analysis has 858
diagnostics, with only the old cache deprecation removed and none added. The
full suite has 9,088 successes, the same 22 failures/29 errors/20 skips, every
prior outcome preserved and all four new Promenade cases passing. Evidence:
`promenade-layout-*`, `analyze-promenade-layout*` and `full-promenade-layout*`
under `.git/refactor-evidence/phase5/`. Remaining layout/actions, hero lifecycle,
native and performance gates stay open.

#### Reviewed shared stage rail label

Promenade and Mosaic now use `home_stage_rail_label.dart` (86 lines) with
explicit title, rail index/count and alignment. The shared label height remains
scaled against Canvas's existing chevron floor. Both production callers retain
the original State context; title disambiguation, focus and navigation remain
with their current owner. The old label implementation and height helper are
removed; the Search facade is now 18,137 lines and remains a temporary exception.

Review preserved uppercase text, flexible single-line ellipsis, one-based count,
single-rail counter suppression, typography and chevron positioning. The relevant
42 existing checks and four new label checks pass, including narrow headers at
two text scales and both alignments. After correcting one interpolation-style
warning, the four direct checks pass again and analyzer diagnostic identities
exactly match the prior 858-issue baseline. All 352 migrated files pass the
architecture guard; diff checks pass. Evidence is retained under
`.git/refactor-evidence/phase5/stage-rail-label-*` and
`analyze-stage-rail-label-verified.txt`. The latest full-suite checkpoint remains
`full-promenade-layout.jsonl` (9,088 successes / 51 existing failures / 20 skips);
it predates this small presentation move. Native font/device parity remains
pending. No focus, native resource or application-state ownership moved.

#### Reviewed Atrium split-panel composition

`lib/features/home/presentation/home_atrium_layout.dart` (108 lines) now owns
Atrium's artwork/native surface stack, opaque dossier panel, seam, identity
placement and bottom rail-wall composition. The real caller retains the original
LayoutBuilder, rail resolution/focus seed, scaled row budget, one/two-row choice,
metadata subscriptions, card actions and conditional native constructors. Seven
explicit content slots replace the old inline tree; no parent state object or
new resource owner crosses the boundary. Shared spacing constants retain their
original values and keep the caller's geometry consistent with the composition.

Review compares the complete original tree, caller prefix and supplied content
expressions, allowing only parameter/constant names, formatting and removal of
the now-unused scrim import. The 43 observed baseline tests pass again, including
all eight actual TV layouts with late catalogs, covered routes and pagination.
Three new host tests cover one/two-row rectangles, artwork/trailer/live order,
panel/seam geometry, retained top-row focus and surface State across resize, and
optional-surface disposal. An initial test incorrectly assumed sibling disposal
order; it now checks both disposals exactly once without imposing that unrelated
framework detail. No production lifecycle ordering changed. All 46 affected
checks pass; native compositor/player parity remains a separate pending gate.

The parent decreases by 78 lines to 18,059. All 353 measured files pass size/import
checks. Changed-file formatting, source comparison and diff checks pass. The
unused-import warning introduced by the move was removed; final analyzer
identities exactly match the preceding 858 diagnostics. Evidence:
`atrium-layout-*` and `analyze-atrium-layout-final.txt` under
`.git/refactor-evidence/phase5/`. The full suite (`full-atrium-layout.jsonl`)
has 9,095 successes, the same 22 failures/29 errors/20 skips, every prior outcome
preserved and all seven new rail-label/Atrium tests passing. Remaining
row/layout/action ownership, hero lifecycle, native and performance work remains
open.

#### Reviewed Mosaic geometry and grid composition

`lib/features/home/presentation/home_mosaic_layout.dart` (217 lines) now owns
Mosaic's scaled header dimensions, grid sizing, live-dependent veils, fixed
identity/rail band and keyed lazy grid. Its immutable geometry value is shared
with the actual caller's cell navigation, keeping directional steps and rendered
columns consistent. The caller retains original rail resolution/focus seeding,
favourite/catalog aspect and caption selection, metadata subscriptions, hold/
pagination/actions and conditional live-surface construction. Borrowed live-channel
signals preserve both independent veil subscriptions and their original timing.
No new application state or resource owner is introduced.

Review compares the full original Stack, five content expressions, geometry,
header metrics and unchanged caller prefix. Artwork stays below the veil and
live surface; the lighter live scrim remains above it. Rail identity, caption
allowance, one-to-eight column clamp, nonnegative widths, hint text and cache
size are unchanged. The installed SDK maps the legacy 600-pixel cache directly
to `ScrollCacheExtent.pixels(600)`; adopting that equivalent API removes one
existing deprecation and does not change package versions.

All 43 baseline checks pass again, plus eight new cases covering portrait/
landscape/favourite geometry, very narrow and wide boards, scaled header clearance,
lazy cell construction, hint suppression, live shading without cell rebuilds,
retained focus/scroll/surface State through resize, keyed rail replacement and
borrowed-listener release. Source comparison, formatting and diff checks pass.
All 354 measured files pass size/import checks. Analysis has 857 diagnostics,
with only that old cache deprecation removed and no additions. The parent shrinks
by 157 lines to 17,902; it remains a temporary oversized exception. Evidence:
`mosaic-layout-*` and `analyze-mosaic-layout-final.txt` under
`.git/refactor-evidence/phase5/`. The full suite (`full-mosaic-layout.jsonl`)
has 9,103 successes, the same 22 failures/29 errors/20 skips, every prior outcome
preserved and all eight new Mosaic cases passing. Native compositing, remaining
layout/action/focus ownership and the whole-library lifecycle/performance gates
remain open.

#### Reviewed Deck card geometry and composition

`lib/features/home/presentation/home_deck_layout.dart` (197 lines) now owns
Deck's rail-first card geometry, static background, painted-corner video-card
frame, dossier placement and theater rail. The real caller retains the shared
caption-aware rail-size policy, focus/selection, peek-card subscription, metadata
signals, conditional native constructors and original lazy cell builder. The
immutable geometry value supplies the same card dimensions to the live/trailer
layers and peek placement. Identity clearance and width use those same values;
no parent state or new resource owner crosses the boundary. The shared 22-pixel
radius remains identical for the card and the caller's static peek artwork.

Review compares the full original tree, seven supplied content expressions,
rail-first geometry and original caller prefix. The native card retains art,
trailer, live, painted wedges and border order, without a new clip or save layer.
The rail retains 900ms theater entry/250ms return, 0.12 slide, lazy identity key,
cell context/padding and 400-pixel cache. The SDK-equivalent `ScrollCacheExtent`
API removes one old deprecation; no dependency or engine version changes occur.

All 41 baseline checks pass again. Six new cases pass for height-limited,
width-limited and zero-space card geometry, one/two-scale label extents, surface
rectangles and painted-corner placement, retained focus/scroll/surface State
through theater and resize, absent native content and keyed rail replacement.
The host tests do not establish native compositor parity; that gate stays open.
All 47 affected checks pass, all 355 migrated files pass size/import checks, and
source/format/diff checks pass. Analysis has 856 diagnostics, with only the old
cache warning removed and none added. The parent shrinks by 132 lines to 17,770.
Evidence is under `.git/refactor-evidence/phase5/deck-layout-*` and
`analyze-deck-layout.txt`. The full suite (`full-deck-layout.jsonl`) has 9,109
successes, the same 22 failures/29 errors/20 skips, every prior outcome preserved
and all six new Deck cases passing. Deck labels/peek presentation, remaining
layout/action ownership, hero/native lifecycle and performance work remain open.

#### Reviewed Deck static preview cards

`home_deck_peeks.dart` (70 lines) now owns the existing far-to-near artwork
preview construction. The production Deck caller still owns its focused-column
subscription and supplies the same items and card rectangle. The entire old
body matches after its public name/formatting; all other parent code matches
byte-for-byte except the import/callee name. The replaced method is removed.
Selection bounds, next-two-only policy, missing-art suppression, 480-pixel decode,
keys, transforms, 260ms transitions and pointer transparency are unchanged.

All 40 baseline checks pass again, plus three new tests covering preview order,
geometry/animation/decode settings, invalid focus and absent artwork/favourites,
focused-column updates and taps through previews. All 43 affected checks pass.
Analysis exactly matches the prior 856 diagnostics; all 356 measured files pass
size/import checks and diff/source checks pass. The parent is 17,706 lines.
Evidence: `deck-peeks-*` and `analyze-deck-peeks.txt` under
`.git/refactor-evidence/phase5/`. The latest full-suite checkpoint remains
`full-deck-layout.jsonl` (9,109 successes / 51 existing failures / 20 skips),
predating this small visual extraction. Native/device and remaining layout/action
ownership gates remain open.

#### Reviewed Deck/Tonight shared row label

`home_stage_row_label.dart` (51 lines) now owns the existing shared rail label,
with an explicit title and context. Both actual Deck/Tonight callers preserve
their original State context and title lookup. The same 12-pixel font constant
also supplies Atrium's plain row labels and scaled wall-height calculation; no
font or spacing changes occur. The old method is removed, leaving the parent
at 17,669 lines. The complete body/caller comparison passes after only explicit
inputs, constant naming and formatting.

All 41 baseline checks and three new label checks pass, covering narrow/scaled
headers in LTR/RTL, changing/empty titles and retained caller focus/directional
handling. Analyzer identities exactly match the preceding 856 diagnostics. All
357 measured files pass size/import checks; source, formatting and diff checks
pass. Evidence: `stage-row-label-*` and `analyze-stage-row-label.txt` under
`.git/refactor-evidence/phase5/`. The latest full-suite checkpoint remains
`full-deck-layout.jsonl`, predating the two small preview/label extractions;
broader comparison follows the next layout integration. Native font/device,
remaining layout/action ownership and lifecycle/performance gates remain open.

#### Reviewed Tonight geometry and zone composition

`home_tonight_layout.dart` (250 lines) now owns Tonight's card/queue geometry,
three-zone placement and native-card frame. The real caller retains its initial
queue/rail resolution, zone reconciliation, focus seeding, shared scaled rail/
header/row metrics, metadata signals and action construction. The accepted
geometry is immutable. Pure row-height arithmetic now completes before the same
caller-owned hidden-queue focus guard; that guard still runs before all content
construction. Shared padding/gap/tail constants retain their original values.

Header, optional card, queue and rail construct in their original order. Lazy
callbacks preserve the old conditions: queue-only mode cannot instantiate hidden
artwork/native/caption content, and a hidden queue does not construct its list.
The card frame keeps art/trailer/live, legibility ramp, painted corners and
caption order without a new clip. Source comparison covers the complete original
geometry, Stack/frame trees, supplied expressions and unchanged resolution prefix.
No application-state or native-lifecycle ownership moves in this slice.

All 44 baseline checks pass again, plus nine new cases for narrow/short/queue-only
geometry, the legacy minimum focusable queue row even with zero main-zone space,
exact card/queue/rail rectangles and caption/corner placement, lazy construction,
retained queue/rail focus and surface State through resize. The initial compile
check caught a missing `min` import; it was corrected and the now-unused parent
corner-painter import removed. All 53 affected checks pass. Final analyzer
identities exactly match the prior 856 diagnostics. All 358 measured files pass
size/import checks, and source/format/diff checks pass. The parent shrinks by
160 lines to 17,509 and remains a temporary oversized exception.

Evidence: `tonight-layout-*` and `analyze-tonight-layout-final.txt` under
`.git/refactor-evidence/phase5/`. The first full run hit the previously recorded
remote `.part` cleanup and Xtream expired-deadline/client-close timing races.
Their errors/frames match the earlier stage-retirement receipts; both services
and tests are unchanged since that checkpoint. The two isolated suites pass all
28 tests. Without code or failure-allowance changes, the repeated full run
(`full-tonight-layout-verified.jsonl`) has 9,124 successes, the same 22 failures/
29 errors/20 skips, every prior outcome preserved and all 15 new preview/label/
Tonight cases passing. Both full receipts and the timing review are retained.
Tonight header/list presentation, shared navigation/action ownership, hero/native
lifecycle and whole-library device/performance verification remain open. Host
state/geometry checks do not establish native compositor parity.

#### Reviewed Tonight header

`home_tonight_header.dart` (71 lines) now owns the weekday/progress header and
its scaled height. The actual caller supplies its original State theme context,
queue count and one `DateTime.now()` read per build. Height calculation keeps
the LayoutBuilder context. Existing English text, weekday ordering, count
suppression, baseline alignment and spacing remain unchanged; no clock timer,
localization migration or new state owner is introduced. The former methods and
constants are removed; source comparison covers the complete bodies/caller.

All 43 baseline checks and three new header checks pass, covering every weekday,
zero/positive count updates, stable non-ticking display and scaled height/bottom
spacing. All 46 affected checks pass. Analyzer identities match the prior 856;
all 359 measured files pass size/import checks, and formatting/source/diff checks
pass. The parent is 17,449 lines. Evidence: `tonight-header-*` and
`analyze-tonight-header.txt` under `.git/refactor-evidence/phase5/`. The latest
full-suite checkpoint remains `full-tonight-layout-verified.jsonl` (9,124 passes,
51 existing failures/errors, 20 skips), predating this small rendering move.
Native typography and remaining presentation/actions/lifecycle gates stay open.

#### Reviewed Tonight lazy queue list

`home_tonight_queue_list.dart` (46 lines) now owns the fixed-extent lazy list,
row padding and thumbnail-width calculation. The real caller supplies the same
row data, borrowed nodes and complete action/focus callbacks through an indexed
builder receiving the calculated thumbnail width. The original Column/Expanded/
ListView/Padding hierarchy, list key, zero padding, clipping and row extent stay
unchanged. Thumbnail width remains the smaller of 16:9 row height and 40% of queue
width. The old wrapper is removed; the parent is 17,423 lines. The former root
metrics comments now accompany the already-extracted Tonight geometry/queue.

All 48 baseline checks and three new list checks pass: narrow/wide thumbnail
bounds, lazy row construction, exact row spacing/taps, retained scroll/focus on
append and resize, and borrowed-node reuse after removal. An initial test-fixture
tap warning was resolved by targeting its actual GestureDetector; the expanded
51-check run passes without that warning. Complete source comparison preserves
the actual row expression and all existing callbacks. Final analyzer identities
match the preceding 856; all 360 measured files pass size/import checks, and
format/source/diff checks pass. Evidence: `tonight-queue-list-*` and
`analyze-tonight-queue-list-final.txt` under `.git/refactor-evidence/phase5/`.
The latest full checkpoint remains `full-tonight-layout-verified.jsonl`; the
header and queue wrapper use affected verification at this small rendering
checkpoint. Remaining navigation/action ownership, native/device and performance
gates stay open.

#### Reviewed stage hold-key suppression

`home_stage_hold_latch.dart` (42 lines) now owns the per-view key latch shared by
Mosaic and Tonight. It records only a successful hold jump, suppresses further
jumps for that key, releases on matching key-up or fresh key-down, and always
returns false from its observer. A failed/unmounted jump does not latch; other
keys retain their original behavior. This is local presentation state, not new
application state. The class owns no timer, focus node or keyboard registration.

The real screen now uses one owner instance at every existing call site. Global
observer add/remove stay at the original TV Home lifecycle conditions and order;
layout transitions call `reset()` at the old field-clear point. Source comparison
preserves the complete original methods under their new names and all other
parent source except the import/owner/call replacements. The old field/methods
are removed; the parent is 17,392 lines. Remaining rail rendering was deferred
within phase 6 to isolate this shared navigation responsibility first.

All 51 prior affected checks pass. A new actual Mosaic-screen test passes before
and after extraction: the first hold-repeat changes rail, subsequent repeats do
not, and release followed by a fresh press permits another change. Seven direct
checks cover successful/failed/throwing jumps, repeats and unrelated keys,
missed-key-up recovery, separate view/reset state, non-consuming keyboard dispatch
and removal using the bound method tear-off. All 59 expanded checks pass. One
new test cleanup style warning was corrected; final analyzer identities exactly
match the prior 856. All 361 measured files pass size/import checks, and source,
formatting and diff checks pass. Evidence: `stage-hold-*` and
`analyze-stage-hold-final.txt` under `.git/refactor-evidence/phase5/`.
The full suite (`full-stage-hold.jsonl`) has 9,138 successes, the same 22
failures/29 errors/20 skips, every prior outcome preserved and all 14 new
header/queue/hold cases passing. Full native/lifecycle/performance gates and the
remaining navigation/actions still require their planned work.

#### Reviewed stage deferred focus requests

`home_stage_focus_requests.dart` (35 lines) now owns the per-view generation and
post-frame request guard. Two narrow readers preserve mounted/style checks;
target selection and borrowed focus nodes remain caller-owned. Both original
generation increments (board reseed and layout reset) now invalidate this same
owner, and all original scheduling sites use it. The old field/helper are removed.
Source comparison preserves callback order, capture timing, mounted-before-style
checks and the complete target resolvers; it adds no deduplication or extra frame.
The parent is 17,379 lines and remains a temporary oversized exception.

All 58 baseline checks pass again, plus six direct cases for late target resolution,
changed layouts, same-style invalidation, unmounted access rejection, null targets,
request ordering and separate view owners. The initial direct fixture omitted
an actual scheduled frame; it now explicitly supplies the frame that production
rebuilds already provide. No production scheduling change was made to satisfy it.
All 64 expanded checks pass, including actual progressive loading/pagination,
layout preferences and the Mosaic hold flow. Analyzer identities match the prior
856; all 362 measured files pass size/import checks, and source/format/diff checks
pass. Evidence: `stage-focus-*` and `analyze-stage-focus-final.txt` under
`.git/refactor-evidence/phase5/`. The latest full checkpoint remains
`full-stage-hold.jsonl` (9,138 successes / 51 existing failures/errors / 20 skips),
predating this extraction; broader comparison follows the next integration.
Remaining deferred-move policy, rail rendering, native/lifecycle and performance
gates remain open.

#### Reviewed Tonight horizontal rail composition

`home_tonight_rail.dart` (39 lines) now owns Tonight's shared label padding,
label/rail gap, fixed-height horizontal list and trailing clearance. The actual
caller retains its navigation prefix, favourite/catalog sizing, metadata and
complete indexed cell builder. Source comparison preserves the full original
widget tree, label expression/State context and every cell/action callback;
the replaced wrapper is removed. The fixed rail identity, hard clipping and
400-pixel cache remain unchanged; the installed SDK's equivalent
`ScrollCacheExtent.pixels(400)` removes one old deprecation.

All 44 baseline checks pass again, plus three direct cases for label/list/tail
geometry, lazy construction, retained scroll and borrowed focus across append/
resize, and a fresh scroll position on rail-identity change. All 47 expanded
checks pass. Analysis has 855 diagnostics, only the old cache deprecation removed
and none added. All 363 measured files pass size/import checks, and source/format/
diff checks pass. The parent is 17,365 lines and remains a temporary exception.
Evidence: `tonight-rail-*` and `analyze-tonight-rail.txt` under
`.git/refactor-evidence/phase5/`. The full suite (`full-tonight-rail.jsonl`) has
9,147 successes, the same 22 failures/29 errors/20 skips, every prior outcome
preserved and all nine new deferred-focus/rail cases passing. Remaining row/action/
focus orchestration, hero/native lifecycle and device/performance gates stay open.

#### Reviewed shared Home layout policy

`home_layout_policy.dart` (60 lines) now owns off-TV style/shell fallback and
stage, ambient-trailer, shell-art and theater eligibility. Search imports the
pure policy directly instead of importing a Settings screen. The Settings
picker uses the same implementation and re-exports its two existing helpers
for the other Settings callers; this compatibility export can be removed when
those callers migrate their imports. It contains no duplicate implementation.
The current-surface getter retains its original TV/off-TV short-circuit order;
live preview still aliases stage eligibility, including Mosaic. Unknown stored
styles keep their original behavior; no preference writes or schema changes occur.

All 37 baseline checks pass again, plus two policy matrices covering all eight
layouts, unknown/case-mismatched styles, and loading/hero combinations. The
existing off-TV tests also exercise the Settings compatibility export. Analysis
has the same 855 diagnostic identities; all 364 measured files pass size/import
checks. Source review confirms unchanged expressions, caller evaluation order
and removal of the replaced implementations. The parent is 17,325 lines and
remains a temporary exception. Evidence: `layout-policy-*` and
`analyze-layout-policy.txt` under `.git/refactor-evidence/phase5/`. The last full
suite is `full-tonight-rail.jsonl`, predating this slice; no new full-suite or
native/performance claim is made. Action/navigation and lifecycle work remains.

#### Reviewed deferred stage Right navigation

`home_stage_deferred_right.dart` (73 lines) owns one view's pending horizontal
move, origin/age validation, consume-on-arrival and frame-time focus check. The
actual Mosaic boundary caller delegates to it; Search retains only the late
rail/node lookup. The existing stage frame scheduler still guards mounted state,
style and generation. Layout reset clears the owner at the original point;
board reseed and covered-route behavior are unchanged. Deferred Down remains
separate because it can retain a move across partial catalog arrivals.

All 27 baseline checks pass after extraction; six existing scheduler checks and
six new direct cases also pass (39 total). The new cases cover single consumption,
rail/stage/focus/expiry rejection, the inclusive three-second limit, a second
focus check inside the frame, replacement/no-focus retention, reset/isolation
and a missing target. Two real Mosaic paging cases pass against both the previous
screen and the extraction: Right reaches the next page, while moving Up before
arrival preserves the user's new focus. An initial combined command named the
scheduler test at the wrong path; the corrected run passes. Initial screen-fixture
assertions assumed a particular destination cell; the final tests observe the
actual arrow-move focus and prove parity against the old implementation.

Analysis retains exactly 855 diagnostic identities. All 365 measured files pass
size/import checks; source, formatting and diff reviews pass. The unchanged late
lookup, advance methods and single actual defer/complete/reset call sites are
verified. The parent is 17,297 lines and remains a temporary exception. Evidence:
`deferred-right-*` and `analyze-deferred-right-final.txt` under
`.git/refactor-evidence/phase5/`. The full suite (`full-deferred-right.jsonl`)
has 9,157 successes, the same 22 failures/29 errors/20 skips, every prior outcome
preserved and all ten new layout-policy/deferred-Right cases passing. Native/device,
deferred advance and broader navigation/action/lifecycle acceptance remain open.

#### Reviewed deferred stage Down navigation

`home_stage_deferred_advance.dart` (92 lines) owns a view's pending Down move,
origin/age validation, partial-arrival retention and consumption. Search retains
the single rail snapshot/readiness calculation and the original layout-specific
destination handling. All three boundary callers use the owner. Its board-reseed
invalidation preserves the old partial clearing; layout transition and route-cover
resets remain at their original sites. The accepted move borrows its origin node;
Atrium's lower-row fill, window advance, route-current guard and the Deck/Mosaic
detached-origin focus exception remain verbatim in the caller. No asynchronous
boundary, resource owner or additional state subscription is introduced.

All 27 baseline tests pass, including the real deferred-Down scenario across all
eight layouts and the existing sideways-focus/covered-route cancellation cases.
Six new direct cases cover repeated partial arrivals, stale/inactive/moved focus
while waiting or ready, inclusive age/backward-clock behavior, replacement and
missing-focus retention, resets/independent owners and readiness/validation order.
All 33 affected checks pass. Analysis retains exactly 855 diagnostic identities;
all 366 measured files pass size/import checks, and source/format/diff checks pass.
The parent is 17,259 lines and remains a temporary exception. Evidence:
`deferred-advance-*` and `analyze-deferred-advance.txt` under
`.git/refactor-evidence/phase5/`. The last full suite is `full-deferred-right.jsonl`,
predating this slice; native/device and remaining navigation/action/lifecycle
acceptance remain open.

#### Reviewed Atrium row presentation

`home_atrium_row.dart` (53 lines) owns Atrium's quiet uppercase label, reserved
gap and keyed lazy horizontal list. Search retains row selection, per-kind card
geometry, the complete indexed cell builder and all navigation/action callbacks.
The helper receives the caller's State context and Android-TV typography condition;
its root widget and original list identity remain unchanged. The existing fixed
400-pixel cache uses the installed SDK's equivalent `ScrollCacheExtent.pixels(400)`.
Source comparison preserves the complete cell builder and pre-build navigation
expressions, ignoring only formatting; the replaced wrapper is removed.

All 32 baseline checks pass, including the eight-layout deferred navigation flows.
Three new cases cover scaled Android-TV/other-platform label metrics, lazy strip
construction, retained scroll/borrowed focus through append and resize, borrowed
node reuse after unmount, and reset on rail identity change. All 35 affected tests
pass. Analysis has 854 diagnostics, with only the old cache deprecation removed;
all 367 measured files pass size/import checks. Formatting and diff checks pass.
The parent is 17,247 lines and remains a temporary exception. Evidence:
`atrium-row-*` and `analyze-atrium-row.txt` under `.git/refactor-evidence/phase5/`.
The latest full suite remains `full-deferred-right.jsonl`, predating this and the
Down-owner slice. Remaining cell/action orchestration, native lifecycle and
platform/performance acceptance stay open.

Remaining phase-6 work:

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

#### Discover source-selector presentation review

`presentation/discover_source_picker.dart` (45 lines) now builds the Source control
used by every embedded Discover panel. It returns the original `StremioDropdown`
directly, preserving the widget hierarchy, borrowed focus node, TV quiet/accent
presentation, labels, selection callback and option order. The source controller
still owns inventory/selection persistence; the caller supplies accepted feature
and authentication flags. No provider or registration layer was added for this
stateless UI composition.

The release gate still hides MDBList even when it is selected; when enabled, an
active MDBList remains representable through an authentication refresh. TMDB
visibility follows the discovery feature flag. Addons preserve controller order,
stable `a:` IDs and user display aliases without new filtering/sorting. The parent
also retains the release-gated authentication read, avoiding an eager lookup when
the feature is disabled. All embedded panel branches, source-change effects,
resume/quick-play distinctions and focus reattachment scheduling are unchanged.

All 36 baseline startup, feature, source-controller, panel-resize and dropdown
checks pass. Three new checks cover release/auth/feature combinations and alias
order, touch selection, and TV Select/Down navigation with reuse of the borrowed
node after panel replacement (39 affected successes). The TV fixture initially
assumed the popup focused its first item on open; it now follows the existing
scope-to-row navigation, without changing the dropdown. Analysis retains exactly
852 diagnostic identities; all 399 measured files pass architecture checks.
The parent is 16,963 lines. Formatting/diff checks and source comparison pass.
Evidence: `discover-source-picker-*` and `analyze-discover-source-picker.txt` under
`.git/refactor-evidence/phase5/`. Latest full evidence remains
`full-hero-shell-verified.jsonl`, predating the eight theater and three picker
cases; these bounded presentation slices used affected verification. Panel action
composition, shared layout navigation, remaining lifecycle work, final facade/CI
and device/performance acceptance remain open.

#### Discover preview presentation ownership review

`presentation/discover_preview.dart` (109 lines) now owns one view's eight shared
preview signals, theater observation/dwell and ordered reset operations. The
resolving detail rail and native trailer stage borrow those same signals; their
metadata requests, 260ms identity settling, single-decoder discipline and player
ownership remain unchanged. This is local presentation state, not a second
application store. Focus selection remains with the host, while accepted/enriched
preview identity stays in the owned feed.

The TV Discover predicate still controls playback observation at the original
initialization point. Teardown stops observation/cancels the dwell before the
same shell-slot/reset work, then disposes the eight signals in their original
order. Layout changes and media-server source transitions share the original
streams→metadata→loading→showing→theater→timer→takeover reset order. Compact
resize remains post-frame and clears only takeover/showing/theater; streams,
artwork, loading and volume remain retained. Internal showing listeners still
restore theater synchronously before later observers see the showing change.

Five seconds of uninterrupted visible playback still enters theater; activity
restores controls immediately and restarts dwell even when playback does not
change. Timer completion checks the current view and playback, stopped observation
cancels pending work, and disposal rejects retained activity callbacks. Disposal
now always cancels the owned timer, including views that never attached the TV
listener; no native resource is disposed by this presentation owner.

All 24 baseline preview/input/layout/source screen checks pass. The existing real
grid and stage resize cases were expanded before the move and pass afterward:
4,999/5,000ms boundaries, activity wake/rearm, compact reset, no source refetch and
safe unmount. Six new direct cases verify observation cadence, live retirement,
ordered layout/source versus compact resets, stop/disposal and independent view
feeds (30 affected successes). Original parent preview fields and timer methods
are removed; panel branches and controller/action calls remain unchanged.

Analysis retains exactly 852 diagnostic identities; all 400 measured sources
pass size/import checks. The parent is 16,902 lines. Formatting/diff and disposal
order review pass. Evidence: `discover-preview-*` and `analyze-discover-preview.txt`
under `.git/refactor-evidence/phase5/`. The full suite
(`full-discover-preview.jsonl`) records 9,313 successes, the same 22 failures/
29 errors/20 skips, every prior outcome unchanged and seventeen new successes
(the eight Home theater, three source-picker and six Discover preview cases).
The expanded existing grid/stage cases also retain their passing outcomes.
Discover settings/data/metadata ownership still has legacy boundaries; remaining
panel actions, shared layout navigation, native handoff, final facade/CI and
representative device/performance gates remain open.

#### Discover layout preference ownership review

Discover's layout now has one scoped Riverpod notifier (`discover_layout_controller.dart`,
56 lines), a 13-line injected preference contract, a 51-line composition factory
and a six-line profile/view session key. The screen delegates its original
explicit startup/settings reads, retains preview teardown before settings refresh,
and reads the notifier's accepted layout instead of keeping another mutable copy.
Construction does not start an asynchronous read. Equal results update the warm
mirror without repainting; changed results publish state before the existing
rebuild callback. Dependency recomputation retains accepted state without replay.

The old process-wide screen mirror is replaced by one reusable
`ProfileSessionMemory<String>` entry. Same-session tab/route re-entry still starts
warm, with `stage` as the original cold default. Profile/generation/session handoff
clears that entry; a retired owner cannot read away or repopulate incoming memory.
Default preference reads run in the originating captured profile scope, preserving
stored keys and grid/stage normalization. The bounded memory store is static as
required by its registration lifecycle and is not recreated for each view.

Request-generation, mounted, provider-lifetime and profile checks now reject
superseded/retired results before both memory publication and UI changes. Active
read failures retain their propagated error contract without retries; retired
errors are discarded. These are explicit ownership improvements: the former
screen could accept an older read or refresh its static cache after unmount.
The storage reader's optional `canContinue` guard also prevents the migrated
request from updating `StorageService.discoverLayoutCached` after its await.
Unguarded callers retain their normalized return/cache behavior; there is no
preference-format change or new write. The existing oversized
`lib/services/storage_service.dart` exception remains (10,831 lines): this slice
changes only the layout getter and its comments, with member-only formatting;
remaining unrelated storage responsibilities retain their existing extraction
milestones. The parent is 16,906 lines and remains its orchestration exception.

All 22 baseline Discover layout/settings/source checks pass. Nine controller cases
cover warm construction, equal/changed results, racing reads, mounted/profile/
handoff/dispose/recompute retirement, active versus retired errors and retained
state. Five default-adapter/storage cases prove same-session cache reuse with
independent views, actual profile-key routing/normalization, handoff clearing,
retirement during the real read and the shared-cache guard. A real Discover screen
case verifies injected first-frame grid layout, reset of preview effects before
the refresh reader is called, acceptance of the newer stage choice and rejection
of the late startup grid response (37 affected successes). Review removed four
unnecessary non-null assertions from that fixture. Analysis retains exactly 852
diagnostic identities; all 404 measured files pass architecture checks. Formatting,
diff and source review pass. Evidence: `discover-layout-*` and
`analyze-discover-layout.txt` under `.git/refactor-evidence/phase5/`.
The full suite (`full-discover-layout.jsonl`) records 9,328 successes, the same
22 failures/29 errors/20 skips, every prior outcome unchanged and fifteen new
passing cases. Discover card settings and metadata/action
boundaries, shared navigation, native handoff, final facade/CI and representative
device/performance acceptance remain open.

#### Discover card settings ownership review

The three card flags (type tags, ratings and titles) now use one immutable record
and a scoped Riverpod controller with an injected synchronous reader. The default
reader only observes the existing warmed preference cache; startup/profile
warm-up and Settings persistence retain their owners. Construction preserves the
warm first frame, explicit Discover refresh publishes changed flags once, and
equal flags do not repaint. Dependency recomputation retains the accepted state.
The parent no longer imports or reads `DiscoverPrefs` directly.

Home's five expanded poster-browser routes still read fresh flags when opened,
without depending on a Discover-only refresh notification or changing Home's
accepted snapshot. Their route builders and navigation remain unchanged. Reader
and controller guards reject retired profile/provider/view access, including
retirement during an injected synchronous read. These are explicit ownership
improvements; this slice does not claim an audit of the external preference
cache's asynchronous warm-up owner. Active reader failures still propagate
without retries, new writes, storage-format changes or asynchronous initialization.

Twelve controller/default-reader checks pass, covering warm cache reads, explicit
refresh, independent view snapshots, recomputation, errors and retirement. Both
existing real Discover grid/stage tests now also verify injected first-frame flags
and refresh while retaining resize, theater timing and source request-count checks.
A new actual Home See-all navigation test proves fresh injected settings without
a Discover notification; the source guard still checks all five route builders.
The full suite (`full-discover-card-settings.jsonl`) records 9,341 successes,
the same 22 failures/29 errors/20 skips, every prior outcome unchanged and all
thirteen new cases passing. Together with the preserved source-route guard,
all 36 affected checks pass. Evidence is recorded under
`.git/refactor-evidence/phase5/` (`discover-card-settings-*`,
`full-discover-card-settings.*`, `analyze-discover-card-settings-final.txt`).
Analysis retains exactly 852 diagnostic identities and all 407 measured files pass
architecture checks. The parent remains its orchestration exception at 16,908
lines; the three new source files are each below 300 lines. Remaining metadata/
action boundaries, shared navigation, native handoff, final facade/CI and
representative device/performance acceptance remain open.

#### Discover canvas composition review

`presentation/discover_content.dart` (178 lines) now assembles the actual Discover
canvas: the card settings scope, flat-source bypass, compact fallback, and grid/
stage identity, backdrop, trailer and veil slots. The screen passes the source
panel, immutable card settings, preview eligibility, layout choice, focused item
signal and its existing local preview owner. Home loading/ambient indicators
remain explicit presentation slots. The function introduces no widget wrapper,
mutable state copy, player owner, data read or preference access. The original
composition and six now-unused UI imports are removed from the parent, which is
16,778 lines and still retains the documented orchestration exception.

Review preserves the exact 720-pixel width and 420-pixel height thresholds,
post-frame compact reset and mounted guard, grid versus stage build contexts,
all borrowed signal identities, rail geometry, 260 ms stage identity settling,
zero-dwell/crossfading stage art and full-stage trailer parameters. Media-server
and touch bypass decisions remain at the caller; their flat panels do not acquire
a reset or player. The legacy detail rail still owns its resolution work and the
trailer surface still owns native playback: their remaining data/native boundary
work is not claimed complete by this presentation extraction.

All 128 observed affected baseline checks pass after extraction. Six new cases
cover just-below and exact canvas thresholds, both layouts, inherited card flags,
post-frame reset timing with retained loading/volume, bypass behavior, retirement
before the queued reset and borrowed-signal lifetime. The shape manifest also
registers the new composition with zero permitted literal radius residue;
its existing unrelated failure remains, with its other two checks passing.
Analysis retains exactly 852 diagnostic identities. All 408 measured source files
pass architecture checks; changed code formatting and diff review pass. Evidence:
`discover-composition-*` and `analyze-discover-composition*` under
`.git/refactor-evidence/phase5/`. Full-suite evidence remains the immediately prior
card-settings checkpoint (9,341 successes, 22 failures/29 errors/20 skips); this
bounded composition change uses the expanded affected suite. Shared layout
navigation/actions, metadata and native lifecycle boundaries, final facade/CI and
representative device/performance acceptance remain open.

#### Discover source-panel selection review

`presentation/discover_source_panel.dart` (46 lines) owns the lazy selection of
one embedded source panel. It returns the existing widget directly, with no extra
element, state owner or eager construction of inactive panels. The screen supplies
source-specific builders and a synchronous lookup into its current installed-addon
map. TMDB still falls back to Continue Watching until preferences exist; installed
addons still use the first browsable catalog in manifest order, and missing or
search-only addons retain the CW fallback without rewriting source selection.
Stable configured IDs, including IDs containing colons, remain the lookup keys.

Review compares the complete constructor arguments/callbacks for TMDB, Trakt,
Simkl, MDBList, catalog and CW with the previous revision. They are unchanged;
Jellyfin/Emby receive the identical selected source explicitly. Keys, embedded
flags, the shared source selector/focus node, progress readers, PikPak quick-play
gates, Simkl CW-aware handlers, MDBList provenance, and CW reload-after-return
remain at the same composition boundary. No source data is eagerly snapshotted,
no native work is started by the factory, and inactive builders are never called.
The old selection branches and three unused source aliases are removed. The
parent is 16,752 lines and retains its orchestration exception: moving selection
does not close the source-specific action/data and navigation boundaries.

All 102 observed affected baseline tests pass. Six new factory cases cover all
fixed sources and unknown-source fallback, TMDB readiness, lazy construction and
unwrapped widget identity, first-browsable selection, configured IDs, inventory
removal and empty/search-only addon catalogs. Analysis retains exactly 852
diagnostic identities; all 409 measured source files pass architecture checks.
Changed code formatting, diff and constructor-parity review pass. Evidence:
`discover-panel-*` and `analyze-discover-panel*` under
`.git/refactor-evidence/phase5/`. The full suite (`full-discover-panel.jsonl`)
records 9,353 successes, the same 22 failures/29 errors/20 skips, every previous
outcome unchanged and all twelve new cases passing (six canvas-composition and
six source-selection cases since the card-settings checkpoint).
Shared layout actions, source-specific data/navigation, native handoff, final
facade/CI and representative device/performance acceptance remain open.

#### Home favourites-row composition review

`presentation/home_favorite_row.dart` (73 lines) now owns the shared favourites
header and lazy horizontal strip. All six production callers (watchlist, Debrify
TV, Stremio TV, IPTV favourites, IPTV lists and playlists) still use the screen's
small delegation method; their data, tags, focus nodes, navigation and playback
callbacks are unchanged. The function returns the original Column directly and
receives television mode, measured poster width, caption-band height and a lazy
cell builder. It owns no data reads, controller, focus node or playback resource.
The old composition is removed, reducing the parent to 16,697 lines; its broader
orchestration exception remains open.

Review preserves header/tag order and spacing, one-line title overflow, 20/19-pixel
TV/touch titles, 2:3 posters, measured caption space, 14-pixel row clearance,
13-pixel strip padding, 11-pixel card spacing, hard clipping and 400-pixel cache.
The deprecated `cacheExtent: 400` spelling becomes
`scrollCacheExtent: const ScrollCacheExtent.pixels(400)`. The installed SDK's
`ScrollView.buildViewport` maps the former to that exact value, so this does not
change caching or upgrade the SDK. The explicit rendering import is included.

All 59 observed baseline checks pass, covering all six real callers and existing
caption/font/scale refresh cases. Three new cases exercise lazy construction,
touch activation, TV directional focus, retained card/scrollable state and offset
through caption/theme changes, borrowed focus-node lifetime and empty rows
(62 affected successes). The new fixture initially assumed ScrollPosition object
identity survived a theme change; Flutter legitimately replaces that object via
ScrollBehavior, so the check now asserts retained Scrollable/card identity,
scroll offset and focus. No production workaround was added for the fixture.

Analysis has 851 diagnostic identities: the single moved deprecated cache-setting
warning is removed, with no additions. All 411 measured files pass architecture
checks; changed-member formatting, diff and source review pass. Evidence:
`favorite-row-*` and `analyze-favorite-row-*` under
`.git/refactor-evidence/phase5/`. The immediately prior full-suite checkpoint
remains 9,367 successes and the same 22 failures/29 errors/20 skips; this bounded
layout extraction uses the expanded affected suite. Shared row navigation/actions,
remaining composition, final facade/CI and device/performance acceptance remain
open.

#### Catalog-row header and typography review

`presentation/home_catalog_row_header.dart` (86 lines) now owns the shared board
rail header and its Poppins title style. Existing catalog, list, continuation and
skeleton callers keep their title/tag/action inputs through a small delegate.
The extracted function returns the original Padding/Row tree directly and owns
no navigation, source lookup or focus resource. The parent drops the old header,
private font-style implementation and unused See-all/Google Fonts imports, reaching
16,648 lines while retaining its orchestration exception.

Review preserves the strict off-TV width `< 480` breakpoint, 16/24-pixel horizontal
padding, 14/22-pixel top and 10/12-pixel bottom spacing, 15/17-pixel title sizes,
one-line ellipsis, eight-pixel tag gap, 150-pixel tag cap and 9.5-pixel tag font.
TV still omits See-all; off-TV still requires an action callback and retains the
compact label. The classic-row extent uses the same extracted title style while
preserving the original screen context for theme lookup and the supplied layout
context for DefaultTextStyle, text scale and direction. Its formulas are unchanged;
only that changed member is formatted. A newly unused Google Fonts import found
by analysis is removed rather than suppressed.

All 66 passing affected baseline cases remain passing; the same twelve existing
collection errors remain unchanged by exact test-identity comparison. Five new
cases cover the 479/480 breakpoint, wide/TV layout, long title/source overflow,
optional tags/actions, single tap dispatch, retained See-all state when hiding a
tag, and the shared measurement/rendered line under scaled RTL text. Analysis
retains 851 diagnostic identities, with no additions. All 412 measured source
files pass architecture checks; formatting, diff and source review pass. Evidence:
`catalog-header-*` and `analyze-catalog-header*` under
`.git/refactor-evidence/phase5/`. The full suite (`full-catalog-header.jsonl`)
records 9,375 successes, the same 22 failures/29 errors/20 skips, every previous
outcome unchanged and all eight new cases passing (three favourites-row and five
header cases since the post-playback checkpoint). Remaining
row composition, shared navigation/actions, final facade/CI and representative
device/performance acceptance stay open.

#### Classic catalog-row layout and paging review

`presentation/home_catalog_row.dart` (47 lines) owns the classic catalog rail's
header slot, 14-pixel vertical headroom, lazy horizontal ListView and scroll-based
paging boundary. It returns the original Column/SizedBox/NotificationListener/
Builder/ListView tree without adding an element or taking data/focus ownership.
The screen retains the unchanged lazy cell/spinner builder and source-specific
card/action wiring. Child count is deliberately read inside the retained inner
Builder, at the original evaluation point, rather than snapshotting mutable
legacy page/spinner state earlier. Navigation callback factories remain lazy.

The paging threshold remains 900 logical pixels, inclusive at the boundary and
limited to horizontal notifications. Start/update/end notifications still reach
ancestor listeners and may each dispatch; the existing loader keeps deduplication
ownership. Header hiding, collection-specific card widths, shared-element tags,
card focus, quick play and deferred vertical movement are unchanged. Source review
compares the entire cell/spinner builder with the prior revision, including card
constructor arguments and callbacks. The parent is 16,604 lines and retains its
orchestration exception; remaining cell/action composition is not claimed complete.

Clipping, 13-pixel horizontal strip padding and 400-pixel cache are retained.
The deprecated cache argument uses the SDK-equivalent explicit pixel spelling,
as verified for the preceding favourites-row extraction; no SDK upgrade occurs.
All 64 observed baseline cases pass. Two new cases verify live lazy count/spinner
transitions, arbitrary caller card widths, retained focused-card/scroll state,
borrowed node lifetime, the exact paging threshold and notification propagation
(66 affected successes). Review fixes one missing-braces lint in the new fixture.
Analysis has 850 diagnostic identities: one obsolete cache-setting warning removed,
no additions. All 413 measured source files pass architecture checks; formatting
and diff review pass. Evidence: `classic-catalog-row-*` and
`analyze-classic-catalog-row-*` under `.git/refactor-evidence/phase5/`. The immediately
prior full-suite checkpoint remains 9,375 successes and the same 22 failures/
29 errors/20 skips; this bounded layout slice uses the expanded affected suite.
Shared row navigation/actions, remaining composition, final facade/CI and
representative device/performance acceptance remain open.

#### Continue Watching row composition review

`presentation/home_continuation_row.dart` (93 lines) owns the actual classic
Continue Watching row and card assembly for the existing shared row descriptor.
It borrows the descriptor's live item/node collections and per-item progress,
episode and open callbacks. The screen supplies the header, dimensions, live
artwork/display readers, bound-state lookup and navigation/menu/focus actions.
No data is copied into a new owner, no UI wrapper is added, and no node, player,
service or asynchronous lifecycle is moved. The parent delegates and removes
its original composition, reaching 16,544 lines while retaining its orchestration
exception.

Review preserves the inner Builder and lazy cell evaluation, per-item progress
and episode labels, watched-badge suppression during rewatch, absence of direct
quick-play, caller-owned long-press/hold-OK menu behavior, and current-order
vertical focus resolution. Menu callbacks retain both original CW row and column
indices; source-specific row actions and reloads remain outside the component.
The strip retains 14-pixel vertical headroom, 13-pixel outer and 11-pixel per-card
horizontal spacing, hard clipping and the original 400-pixel cache, using the
already-verified SDK-equivalent nondeprecated pixel argument. Artwork/aspect and
title-overlay readers execute at card materialization, not at parent construction.

All 58 observed affected baseline checks pass across local/Trakt/Simkl/MDBList/IPTV
screen flows, card navigation and Home pagination. Two new touch/TV cases verify
live lazy progress reads, progress-bar rendering, retained focused card through
progress/episode/display changes, vertical/edge callbacks, one short-press open,
one long-press/hold menu, no accidental quick-play/removal, and borrowed focus-node
reuse after unmount (60 affected successes). Analysis has 849 diagnostic identities:
one obsolete cache-setting warning removed, no additions. All 414 measured source
files pass architecture checks; formatting and diff/source review pass. Evidence:
`continuation-row-*` and `analyze-continuation-row*` under
`.git/refactor-evidence/phase5/`. The full suite (`full-continuation-row.jsonl`)
records 9,379 successes, the same 22 failures/29 errors/20 skips, every previous
outcome unchanged and all four new cases passing (two classic catalog-row and two
Continue Watching cases since the header checkpoint). Shared
row actions/navigation, remaining composition, final facade/CI and representative
device/performance acceptance remain open.

#### Classic row sizing and anchor measurement review

`presentation/home_classic_row_metrics.dart` (82 lines) now owns poster sizing,
shared card aspect/orientation, classic title-card dimensions, hero budgeting and
the fallback row-height measurement used during incremental scroll anchoring.
The existing 17-line `utils/home_rail_metrics.dart` helper is moved into this
feature module; its only production import and existing test import are updated,
and the old file is removed with no remaining references. The screen delegates
its actual sizing/anchor callers instead of retaining parallel formulas. It is
16,502 lines and remains the documented orchestration exception. An orphaned
paging-threshold comment from the preceding row extraction is also relocated
beside the constant it describes.

Review preserves the 900-pixel phone/desktop width breakpoint, TV Home/Search
poster height factors and clamps, landscape's 1.6x width, 2:3/16:9 aspects,
approximate 44/52-pixel header budget, 14-pixel row clearance, 24-pixel next-header
peek and 150/440 hero limits (Search stays 150). Favourites still use portrait
poster geometry. Anchor measurement retains TextPainter disposal, the focused
layout context's DefaultTextStyle/text scale/direction and the original screen
context for title styling. Title-style and card-height callbacks retain their
original evaluation order. Hidden collection headers return their spacer/card
height without font resolution or inherited text lookups.

All 46 observed baseline cases pass, including Home pagination/focus, caption
scales, display preferences, header metrics and the original poster-size tests.
Seven new cases pin phone/TV limits and orientation/hero dimensions, compare row
measurement with rendered text in both directions at 1x/2x scale, verify source-tag
visibility and updated card height, and prove the hidden-header shortcut does not
request fonts (53 affected successes). Analysis retains exactly 849 diagnostic
identities. All 415 measured files pass architecture checks; formatting, diff,
caller/import and source review pass. Evidence: `classic-row-metrics-*` and
`analyze-classic-row-metrics*` under `.git/refactor-evidence/phase5/`. The immediately
prior full-suite checkpoint remains 9,379 successes and the same 22 failures/
29 errors/20 skips; this bounded measurement slice uses the expanded affected
suite. Shared layout/navigation/actions, final facade/CI and representative
device/performance acceptance remain open.

#### Catalog continuation footer review

`presentation/home_catalog_continuation_footer.dart` (52 lines) owns the existing
SafeArea/Focus/Wrap composition for paused-row and more-catalog actions. The actual
board caller delegates to it and the inline implementation is removed; the parent
is now 16,475 lines and remains the orchestration exception. Visibility, pending
row selection, busy state, paging execution and restoration target selection stay
with their existing owners. This extraction creates no new state or resources.

Review retains action ordering/labels, empty-board autofocus priority, borrowed
focus nodes, enabled-but-busy repeat suppression and Up handling only on key down.
Repeat and release events still bubble, as do unrelated keys. The existing legacy
text localization exception applies unchanged. All 25 observed pagination/button
baseline cases and three new footer cases pass (28 successes). New tests exercise
both autofocus branches, real Select dispatch, busy retention, node reuse after
unmount and parent key propagation. Analyzer identities remain exactly 849; all
416 measured files pass architecture checks. Formatting and diff checks pass.
Evidence: `board-continuation-*` under `.git/refactor-evidence/phase5/`.
The full-suite comparison (`full-catalog-continuation-footer.*`) completes with
9,389 successes, the same 22 failures/29 errors/20 skips, and no changed or missing
prior test outcomes. Its ten added successes cover this footer and the preceding
classic-row metrics extraction. The full runner exits 1 for the unchanged baseline
failures; the suite is not claimed entirely green.

Shared paging/action orchestration, final facade/CI and representative native/
performance checks remain open; this review does not close those requirements.

#### Manual catalog continuation workflow review

`application/home_catalog_continuation_controller.dart` (90 lines) now owns the
manual continuation busy latch, rotating cursor and sequential four-row action.
The production footer and keyboard paths call this scoped Riverpod notifier;
the screen's old mutable latch/cursor and batching implementation are removed.
The parent is 16,485 lines, still an orchestration exception: subscription wiring
adds lines here, but application policy has one independent owner. The existing
catalog controller/repository remain the owners of row paging and publication.
No additional retry, data store, generic action bus or playback dependency is added.

Review retains synchronous rejection during vertical/manual/pending-row loading,
filtering of paused non-exhausted rows, cursor advance before the first await,
sequential windows of at most four rows, live row-index lookup and skipped removed
rows. More-catalog actions do not consume the row cursor. Errors propagate after
latch release. A null operation means rejection, so the screen restores focus only
for an accepted action; focus nodes, mounted target checks and post-frame restore
remain presentation-owned. As required by the scoped ownership destination, profile
handoff/disposal and provider recomputation now retire pending continuation work;
an older provider lifetime cannot clear a newer busy latch. The screen's deferred
focus callback also rejects a changed profile. This explicitly strengthens the
old generation/mounted-only boundary without changing active-profile paging.

All 28 observed pagination/footer/button baseline cases pass. Eleven new controller
cases cover batching/rotation, changing pending rows, serialization, both rejection
paths, vertical loading, empty inventory, propagated errors, view/profile/disposal
retirement, recomputation and independent views. A real Home test runs successfully
against both the pre-extraction and new screen: eight paused rows resume in two
four-row actions, the first blocked request retains footer focus, repeated Select
starts no extra work, and exhaustion removes the footer and restores board focus.
There are 40 affected successes. Evidence: `catalog-continuation-action-*` and
`catalog-continuation-screen-*` under `.git/refactor-evidence/phase5/`.
Final analysis retains exactly 849 diagnostic identities after correcting one
new test-only braces lint. All 417 migrated files pass size/import checks, and
formatting/diff review passes. The full comparison
(`full-catalog-continuation-action.*`) completes with 9,401 successes and the same
22 failures/29 errors/20 skips: no prior outcome changes or disappears, and all
twelve added controller/screen tests succeed. The runner's exit 1 reflects those
unchanged baseline failures, not an entirely green suite.

Shared navigation/playback orchestration, final facade/CI and representative native/
performance acceptance remain open.

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

#### Reviewed hero metadata selection policy

`home_hero_metadata_policy.dart` (75 lines) now owns the sparse-metadata refresh
predicate and shell-art selection/retention. Its explicit update distinguishes
keeping a publication from clearing it, including canonical title identity,
selected artwork providers, intentional missing fields and poster fallback.
Search retains TV/layout eligibility, ordered publication, async metadata fetching,
the 140ms debounce and profile/request guards. The complete async body and IMDb
gate remain unchanged. The duplicate derived-logo helper is removed; its actual
caller now uses the existing identical `homeStageLogoUrl` policy.

All 47 baseline checks pass again, with seven new cases for missing metadata,
selected-provider refresh, exact empty/null rules, legacy precedence, sparse
same-title retention, canonical identity, provider-controlled absence/fallback,
unrelated enrichment and null-item publication. All 54 affected checks pass.
One initial fixture incorrectly expected a poster-only selection to override an
existing backdrop; it was corrected to test absence in the relevant category,
with production behavior unchanged. Analysis retains exactly 854 diagnostic
identities; all 368 measured files pass size/import checks. Source, formatting
and diff reviews pass. The parent is 17,203 lines and remains a temporary
exception. Evidence: `hero-policy-*` and `analyze-hero-policy.txt` under
`.git/refactor-evidence/phase5/`. The full suite (`full-hero-policy.jsonl`) has
9,173 successes, the same 22 failures/29 errors/20 skips, every prior outcome
preserved and all 16 new deferred-Down/Atrium-row/hero-policy cases passing.
Trailer eligibility/suppression, asynchronous hero ownership, native preview
lifecycle and playback handoff remain open.

#### Reviewed asynchronous hero metadata ownership

`home_hero_metadata_loader.dart` (74 lines) owns enrichment request generations,
the 140ms debounce and cancellation. A Riverpod provider keyed by the existing
profile/view session owns its lifetime; the 38-line dependency factory injects
the original preference, Stremio and metadata-provider services through a 24-line
repository contract. No fetch occurs during provider construction. Scope is
captured per request at the original point, before preferences; stale or unavailable
preferences still return null through the existing service. Preferences resolve
before timer cancellation, and the original sparse-policy/IMDb gates remain.
The complete request sequence retains merge/presentation, relevance and optional
failure behavior, including passing relevance to the service after a late details
response. The view keeps its existing displayed notifier and ordered shell-art
publication, so there is no competing presentation state owner.

All actual enrichment callers use the loader. Folder entry cancels at the original
point; State disposal retires the loader before disposing presentation signals,
then closes its provider subscription. Provider disposal/recomputation also retires
work. The old screen timer/request fields and asynchronous implementation are gone.
All 71 baseline tests pass, plus ten direct cases covering debounce timing, late
preferences/details/presentation, skip/provider selection, cancellation, profile,
unmount, disposal and optional failures, and three DI cases for independent views,
recomputation and profile/disposal retirement. All 84 affected checks pass. Three
initial new-fixture failures used feature-enabled defaults for current-only cases;
explicit current-only preferences fix the fixtures without production changes.
New test style diagnostics were fixed; analysis retains exactly 854 diagnostics.
The first full run exposed a source guard still naming the retired timer/request
fields. It now checks the actual loader cancellation call before hero replacement,
with executable loader tests covering retirement. All 22 collection-guard/loader/DI
checks pass; the guard's trailer/live clearing and hero ownership assertions remain.
All 371 measured files pass size/import checks; source, format and diff checks pass.
The parent is 17,183 lines and remains a temporary exception. Evidence:
`hero-loader-*` and `analyze-hero-loader-guard.txt` under
`.git/refactor-evidence/phase5/`. The verified full suite
(`full-hero-loader-verified.jsonl`) has 9,186 successes, the same 22 failures/
29 errors/20 skips, every prior outcome preserved and all 13 new loader/DI cases
passing. The first full receipt is retained as `full-hero-loader.jsonl` with the
obsolete-field guard failure documented above. Trailer/live-preview ownership,
hero swap/tint, playback handoff and native/device acceptance remain open.

#### Reviewed hero trailer resolution boundary

`home_hero_trailer_resolver.dart` (55 lines) now owns trailer preference/provider
selection, original catalog/metadata fallback, first-candidate selection, YouTube
resolution and permitted IMDb backup. Riverpod injects the original services
through a 27-line repository and 36-line dependency factory, preserving ambient
height caps and VP9 preference. A 16-line typed result distinguishes unavailable
streams from retired work; stale completions must not clear newer loading state.
The screen's suppression/layout/route checks, dwell timer, loading publication,
15-second failsafe and guarded error handling remain unchanged. A final relevance
check after awaiting the resolver preserves the no-stale-publication invariant.
The screen no longer imports the metadata-provider or IMDb trailer services.

All 51 baseline tests pass, plus 13 direct/DI cases for catalog/provider selection,
identity precedence, fallback permissions, empty/unplayable candidates, optional
metadata errors, missing preferences, retirement after each async stage, resolver
errors and no work during provider construction (64 total). Two actual Home cases
verify injected resolution and rejected results after unmount and route cover.
The latter installs the actual app route observer via an optional fixture input;
an initial test omitted it and therefore did not exercise the production route
callback. The corrected two cases plus all 24 existing pagination checks pass.
Two retired service imports and one new test style diagnostic were removed;
analysis retains exactly 854 diagnostic identities. Source comparison preserves
all scheduling and final-publication code around the extracted network sequence.
All 375 measured files pass size/import checks, and formatting/diff checks pass.
The parent is 17,129 lines and remains a temporary exception. Evidence:
`hero-trailer-resolver-*` and `analyze-hero-trailer-resolver-route.txt` under
`.git/refactor-evidence/phase5/`. The full suite
(`full-hero-trailer-resolver.jsonl`) has 9,201 successes, the same 22 failures/
29 errors/20 skips, every prior outcome preserved and all 15 new resolver/DI/Home
cases passing. This is a stateless service boundary; trailer timer/suppression
and live-preview lifecycle ownership, native/device handoff and performance
acceptance remain open.

#### Reviewed hero trailer timing and cancellation ownership

`home_hero_trailer_loader.dart` (88 lines) owns the per-view dwell, request
generation, captured-scope guard, resolution handoff and 15-second loading
failsafe. The existing dependency factory (now 58 lines) supplies a Riverpod
provider keyed by the profile/view session. The caller retains suppression,
eligibility, route/layout checks and displayed signals. Source comparison keeps
the full eligibility/suppression prefix unchanged, and keeps attempted-id,
stage/route checks and loading write in the same order within the begin callback.
Spotlight retains a zero-delay event; other layouts retain the actual two-second
dwell. Failure deliberately keeps the original mount/generation-only guard,
while playable publication also requires the captured scope to remain current.

Clear and disposal use the new owner at the original cancellation points, before
signal disposal; provider disposal/recomputation retires work as well. The old
screen timer/request fields are removed. Retired failsafes were already no-ops;
the owner now cancels their timers too and retains at most one dwell/failsafe.
Synchronous cancellation during reset or publication cannot leave orphaned timers.
All 48 baseline checks pass, including real Home unmount/route-cover cases. Thirteen
new direct timing/retirement cases and three DI lifetime/isolation checks also pass
(64 total). Analysis retains exactly 854 diagnostic identities, and all 376 measured
files pass size/import checks. Source, formatting and diff checks pass. The parent
is 17,107 lines and remains a temporary exception. Evidence: `hero-trailer-loader-*`
and `analyze-hero-trailer-loader.txt` under `.git/refactor-evidence/phase5/`.
The full suite (`full-hero-trailer-loader.jsonl`) has 9,217 successes, the same
22 failures/29 errors/20 skips, every prior outcome preserved and all 16 new
loader/DI cases passing. Suppression policy, live-preview ownership, hero swap/tint,
native/player handoff and device/performance acceptance remain open.

#### Reviewed per-view hero preview intent

`home_hero_preview_policy.dart` (47 lines) now owns playback suppression,
scheduled-title baseline and attempted-title tracking as local presentation state.
All former screen fields are removed. The two suppression-lift points, focus-change
and top-exit attempt resets, and dwell-time attempt marker retain their exact call
sites. Admission lifts a new Spotlight title before the existing short-circuit
render/settings gate, then records the admitted id before later layout/favourite/
attempt gates. Playback marks suppression before reading the visible hero; a null
visible id retains the previous schedule baseline. The loader and displayed
signals remain separate owners, with no new timers, subscriptions or services.

All 28 baseline checks pass plus seven direct policy cases (35 total), covering
cold-open and A→B playback, absent visible ids, independent reset points,
settings-gate ordering and independent views. A real off-TV Spotlight scenario
passes against both the old screen and extraction: trailer launches permit another
dwell, content launch suppresses the same title, and a new title permits a preview.
The complete timer/presentation request body is unchanged apart from routing its
attempt marker. Analysis retains exactly 854 diagnostic identities; all 377
measured files pass size/import checks, and source/format/diff checks pass. The
parent is 17,083 lines and remains a temporary exception. Evidence:
`hero-preview-policy-*` and `analyze-hero-preview-policy-final.txt` under
`.git/refactor-evidence/phase5/`. The last full suite is
`full-hero-trailer-loader.jsonl`, predating this slice. Remaining surface
eligibility, live-preview and hero swap/tint ownership, native handoff and
platform/performance acceptance stay open.

#### Reviewed live-preview candidate ownership

`home_hero_live_preview.dart` (81 lines) now owns one view's request generation
and ordered candidate fallback. A 15-line injected repository delegates to the
existing Stremio IPTV service, preserving its passive-preview cache policy and
never-throw resolution contract. The 31-line Riverpod factory keys the disposable
operation by the existing profile/view session; construction starts no requests.
The view retains selected channel, visible URL, takeover signals and ordered
trailer/shell teardown. Source comparison verifies the selection prefix and
complete clear/restoration body, including separate request invalidation and
candidate clearing around synchronous notifier writes. Old request/ladder fields
are removed, and disposal retires the operation before visible signals are freed.

The captured-owner check is an intentional profile-isolation hardening: outgoing
views cannot publish candidates, start another lookup, or invalidate the incoming
profile's candidate cache. It also rejects synchronous retirement during prepare.
This does not cancel an already-running borrowed service request or establish
native player teardown parity. Current-owner behavior preserves first-candidate
selection, original index-based fallback (including duplicate URLs), cache
invalidation before clearing video, empty results and single-URL no-op fallback.

All 39 baseline checks and 17 new operation/DI cases pass (56 total), including
newer-request precedence, owner retirement, unmount, explicit/provider disposal,
recomputation and independent view owners. Analysis retains exactly 854 diagnostic
identities. All 380 measured files pass size/import checks; formatting and source
comparison pass. The parent is 17,072 lines and remains a temporary exception;
the remaining hero part is 2,169 lines. Evidence: `hero-live-*` and
`analyze-hero-live.txt` under `.git/refactor-evidence/phase5/`.
The full suite (`full-hero-live.jsonl`) records 9,242 successes, the same
22 failures/29 errors/20 skips, every prior outcome preserved and all 25 cases
added since the trailer-loader checkpoint passing (eight preview-intent cases
and 17 live-preview cases).
Live-preview presentation/native lifecycle, hero swap/tint, surface eligibility,
playback handoff and platform/performance acceptance remain open.

#### Reviewed live-preview surface and shared geometry

`presentation/home_hero_live_layer.dart` (342 lines) now owns the live-video
region, channel-art floor and LIVE/TUNING presentation as one cohesive widget.
All seven production layouts use it with their original signals/callbacks and an
explicit original channel classifier. It imports no service; borrowed channel/URL
notifiers are subscribed, rebound and detached at the original lifecycle points.
The existing backdrop still owns its native player. Same-URL rebuilds retain the
backdrop key; a new URL replaces it, with unchanged 300ms startup, addon-only
12-second first-frame timeout, volume, callback and unconditional edge-feather
behavior. The view still owns trailer/live exclusion and fallback dispatch.

The shared region geometry, brightness lift and feather helpers are now in
`presentation/home_hero_surface.dart` (76 lines), used by the remaining title/art
and trailer callers as well. Source comparison verifies unchanged executable
bodies under renaming, classifier injection and public-widget lint fixes. The
shape manifest registers the moved pill token without lowering the sweep floor.
All 47 baseline successes and the same pre-existing shape-manifest failure are
preserved; five new checks pass (52 successes total), covering signal replacement
and disposal, backdrop identity and fallback, status/callbacks, boxed/full-bleed
geometry, pointer pass-through, invalid bounds and feather progression. The first
geometry assertion used exact floating-point equality; it now uses a numerical
tolerance with unchanged production geometry. New public-widget key/parameter
lints were fixed. Analysis retains exactly 854 diagnostic identities; all 382
measured files pass size/import checks, and formatting/diff checks pass.

The parent is 17,081 lines and the remaining hero part is 1,767 lines; both remain
temporary exceptions. Evidence: `hero-live-layer-*` and
`analyze-hero-live-layer-final.txt` under `.git/refactor-evidence/phase5/`.
The latest full suite remains `full-hero-live.jsonl`, predating these five tests.
Native compositor/engine teardown and device/performance parity remain open;
widget identity checks do not establish those gates. Next separate the remaining
trailer surface and hero presentation while retaining shared geometry and player
ownership, then complete the remaining lifecycle/action boundaries.

#### Reviewed trailer surface, status presentation and stream-model boundary

`presentation/home_hero_trailer_layer.dart` (317 lines) now owns the trailer's
boxed/full-bleed surface with borrowed trailer/loading signals and the retained,
unused takeover hook. Actual Home/Discover callers use it. It preserves the
same-URL global key, per-URL player replacement, 300ms startup, separate audio,
volume and playing callback. Loading/playing indicator precedence and the original
absence of a region-level opacity wrapper are unchanged, preserving the native
underlay composition contract. Native parity still needs device evidence.

`home_hero_trailer_indicators.dart` (272 lines) owns the loading wave and ambient
pulse; `home_spotlight_search_button.dart` (42 lines) owns the button and shared
corner dimensions. Host TV layout authority still determines the corner, while
the existing platform utility determines the ambient pulse policy; these distinct
contracts were deliberately preserved. Tickers keep their original initialization,
visibility and disposal behavior. All old declarations are removed. The shape
ratchet follows both moved token calls and the remaining bare radius: the old
part is now in the existing residue-only map with allowance one, and indicators
retain allowance one. The 490-call floor is unchanged.

The first architecture check correctly rejected importing a data-service file
just for a model. `lib/models/youtube_resolved_streams.dart` (94 lines) now holds
the unchanged stream/quality/caption declarations without dependencies; it is
registered in the migration guard. The existing YouTube service imports and
re-exports it, preserving existing callers and leaving all network/cache logic
unchanged. The service is 759 lines; that does not imply its independent service
architecture has been refactored. The new surface imports the model directly.

Source comparison verifies every moved executable body, including the model,
and the otherwise-unchanged service body. The 44 baseline surface checks and two
existing stream-model compatibility checks pass again, with the same pre-existing
shape-manifest failure. Six new tests pass (52 successes total), covering notifier
replacement/disposal, key identity, fallback replacement, separate audio, inactive
takeover ownership, TV/touch placement, pointer pass-through, hidden ticker stop,
TV no-pulse behavior and search-button dispatch. Analysis retains exactly 854
diagnostic identities after removing the obsolete parent image-filter import.
All 386 measured files pass size/import checks. The parent is 17,083 lines and
the remaining hero part is 1,151 lines; both remain temporary exceptions.
Evidence: `hero-trailer-layer-*`, `hero-trailer-model-before.txt` and
`analyze-hero-trailer-layer-verified.txt` under `.git/refactor-evidence/phase5/`.
The first full run (`full-hero-surfaces.jsonl`) exposed one test finder still
using the retired private trailer class name. It now uses the public widget type
and typed volume access; all original volume/state/request assertions remain.
All 24 pagination cases pass, and final analysis
(`analyze-hero-trailer-layer-pagination.txt`) retains the same 854 identities.
The verified full run (`full-hero-surfaces-verified.jsonl`) has 9,253 successes,
the same 22 failures/29 errors/20 skips, every prior outcome preserved and all
11 new surface cases passing (five live-surface and six trailer/status cases).
Remaining hero metadata/art presentation, Spotlight card live-preview ownership,
hero swap/tint, playback actions and native/performance gates remain open.

#### Reviewed Spotlight card live-preview ownership

`presentation/spotlight_iptv_card_preview.dart` (114 lines) is now a standalone
Riverpod consumer. It keeps the displayed URL, same-value publication guard,
channel-object identity comparison, player key, headers, 300ms dwell, volume and
addon-only 12-second timeout. The old shared-part implementation is removed;
Search imports the new widget for both production shelf callers and re-exports
its existing public name for compatibility. The direct widget test now supplies
the app's ProviderScope instead of constructing a consumer without its DI owner.

`application/home_spotlight_live_preview.dart` (75 lines) owns only candidate
resolution/fallback and retirement, reusing the existing injected IPTV repository.
Its 27-line dependency factory creates an independent profile/view family key for
each mounted card, with no network work on provider construction, retries disabled,
and disposal/recomputation retirement. The widget explicitly starts resolution at
its original init/update points and retires the owner before closing its manual
subscription. This separate operation retains the card's specific contract:
series entries clear without a lookup, direct URLs publish synchronously, and
initial synchronous publication suppresses a rebuild while async acceptance always
requests one. Channel-object replacement restarts resolution even for the same URL;
volume-only updates retain the player and do not resolve again.

Captured-profile/view retirement is an intentional isolation guard, as with the
large hero: retired cards cannot publish late candidates, start another lookup or
invalidate the incoming profile's cache. Synchronous retirement while clearing
also stops lookup. It does not cancel a borrowed in-flight network request or
claim native engine shutdown before the existing widget teardown.

All 96 baseline checks and 12 new operation/DI/widget cases pass (108 total),
covering notification timing, empty results, no-work construction, separate views,
provider disposal/recomputation, profile and handoff retirement, stale channel
replacement, ordered fallback/exhaustion and actual player arguments. The first
DI fixture counted immediate null clearing as a resolved result; it now distinguishes
those events, with direct operation coverage for clearing/notification behavior.
Source comparison preserves the complete render body and URL setter except the
injected classifier access. Analysis retains exactly 854 diagnostic identities;
all 389 measured files pass size/import checks. Formatting/diff checks pass.
The parent is 17,084 lines and the remaining hero part is 1,028 lines, both still
temporary exceptions. Evidence: `spotlight-live-*` and
`analyze-spotlight-live-final.txt` under `.git/refactor-evidence/phase5/`.
The full suite (`full-spotlight-live.jsonl`) has 9,265 successes, the same
22 failures/29 errors/20 skips, every prior outcome preserved and all 12 new
operation/DI/widget cases passing.
Hero metadata/art presentation, swap/tint ownership, remaining playback/action
boundaries and native/performance acceptance remain open.

#### Reviewed shared hero metadata binding

The remaining hero spotlight now consumes the existing `HomeCardMetadataView`
and its scoped Riverpod controller/repository instead of
`MetadataPresentationMixin`. This deliberately reuses the already-migrated
non-prioritized metadata path rather than creating another controller, cache or
retry owner. The host-baseline merge and invalidation conditions are unchanged;
ordinary parent rebuilds preserve the baseline object. Same-title refresh
retention, provider revision resets, cache lookup/acceptance and bounded retries
remain with the shared owner. Captured-epoch retirement now also protects this
hero binding, including clearing an outgoing binding on a profile epoch change.
This is intentional profile isolation; it does not establish native lifecycle
parity or change the separately owned hero enrichment operation.

A small `HomeCardMetadataState.usesProvider` predicate preserves the distinction
between unknown preferences and an explicitly selected metadata provider. Hero
background, description, runtime, logo and poster fallback read that state at
build time; host rating precedence is unchanged. The complete artwork/layout,
animation controllers, motion gates, live/trailer signal subscriptions and
host-baseline invalidation bodies are unchanged under source comparison. Only
changed members were formatted. The old mixin import is removed from Search;
its unrelated users keep their existing implementation.

All 69 baseline policy/controller/view/Home tests pass again. Two new real-Home
scenarios verify injected hero plot rendering, policy refresh with retained focus,
late-result rejection after focus moves, and unchanged catalog request counts.
Analysis now has 852 diagnostics: the only removals are the old misplaced-field
and missing-getter override annotations exposed by the retired mixin. No new
identities appear. All 389 measured files pass size/import checks, and diff and
changed-member formatting checks pass. The parent is 17,085 lines and the hero
part is 1,045 lines; both remain temporary exceptions. This boundary change does
not yet claim the presentation-size gate: next extract the artwork/transition
components and move the remaining hero widget out of the shared library.
Evidence: `hero-metadata-view-*` and
`analyze-hero-metadata-view-verified.txt` under `.git/refactor-evidence/phase5/`.
The latest full suite remains `full-spotlight-live.jsonl`, predating the two new
Home scenarios. Native/device and performance gates remain open.

#### Reviewed standalone hero presentation and final part retirement

The final handwritten part, `lib/screens/search/search_hero_widgets.dart`, is
removed. Search now calls `presentation/home_hero_spotlight.dart` directly. All
four original parts/directives are retired; this does not close the remaining
large parent facade or feature/action/lifecycle audit.

The spotlight is 773 formatted lines: one mounted hero's layout and animation
coordination, with explicit display inputs and the existing scoped metadata view.
The 501–800-line responsibility review keeps its two animation controllers and
cover/motion lifecycle together; it owns no data service, repository, network
lookup or native player. Separate components now own the independent presentation
responsibilities: `home_hero_transitions.dart` (95 lines) holds fade policy with
borrowed signals; `home_hero_tint_surface.dart` (129 lines) builds the mood field
and art feathers from explicit colors/signals; `home_hero_title_art.dart` (101
lines) renders title/logo fallback. Shared trailer geometry remains single-sourced.
Source comparison confirms all executable bodies under explicit input/name/key
substitution and normal formatting, including decode sizes, controller durations,
reduced-motion/TV gates, cached title identity and all composition order.

All 46 baseline checks pass with the same pre-existing shape-manifest failure.
Six new checks pass for boxed/full-bleed fade routing and durations, signal cleanup,
cover/reduced-motion ticker stopping, tint interpolation, title slot/decode sizing,
image-first loading and failed-logo fallback across remounts. The original failure
memo is intentionally retained unchanged in this structural move: its process-wide
unbounded URL set is a scoped resource exception, to be replaced with bounded
storage in the next hero resource slice before phase-7 completion. It is not a
completed cache-policy gate. No other lifetime/eviction behavior changed here.

Nullable signal promotion and obsolete parent imports exposed by the move were
fixed. Analysis retains exactly 852 diagnostic identities. All 393 measured files
pass size/import checks; the relocated radius guard retains the original allowance
one and the shape sweep floor is unchanged. Formatting and diff checks pass.
The 17,079-line parent remains the temporary oversized orchestration exception; the new hero
widget is below the hard ceiling but not the preferred 300-line target. Evidence:
`hero-retirement-*` and `analyze-hero-retirement-verified.txt` under
`.git/refactor-evidence/phase5/`. The full run (`full-hero-retirement.jsonl`) has
9,273 successes, the same 22 failures/29 errors/20 skips, every prior outcome
preserved and all eight new cases passing (two metadata-binding Home scenarios
and six presentation cases). Remaining work includes the title failure memo,
hero swap/tint ownership, the parent action/navigation boundaries, native handoff,
CI/facade audit and representative-device performance evidence.

#### Reviewed title-art failure-memory bound

The title-art resource exception from the preceding structural move is closed.
`HomeHeroTitleArt` now owns a separate instance of the existing
`HomeStageArtFailures` policy instead of an unbounded set. The memo still spans
mounted title widgets for the process lifetime and preserves immediate text fallback
on a remembered logo failure. It now retains at most 512 URLs and clears before
remembering another failure at capacity, including the policy's existing duplicate-
at-capacity behavior. Forgotten URLs may be retried: this is an intentional bounded
resource change, committed separately from presentation extraction. It does not
share failure entries with backdrop art or change provider/cache-manager storage.

All six baseline title/stage widget checks and both existing capacity/duplicate
policy checks pass (eight total). The actual title error callback now calls
`remember`; contains checks and all presentation code are unchanged. Analysis
retains exactly 852 diagnostic identities. Size/import, formatting and diff checks
pass. Evidence: `hero-logo-cache-*` and `analyze-hero-logo-cache.txt` under
`.git/refactor-evidence/phase5/`. The latest full suite remains
`full-hero-retirement.jsonl`, predating this bounded-policy adoption. Hero swap/tint
ownership, parent action/navigation boundaries and device/performance gates remain.

#### Reviewed hero focus-rest swap ownership

`presentation/home_hero_swap.dart` (30 lines) now owns the per-view 260ms timer.
It is local presentation coordination, with no data service or competing hero
state. The parent retains immediate first-title display, title equality/jiggle
policy, folder/favourite behavior and trailer teardown ordering. All three
cancellation sites delegate at their original positions; disposal retires the
owner before hero signals are disposed. Scheduling replaces the old timer, checks
the live mounted predicate only when firing, and releases the completed/cancelled
timer reference. An already disposed owner cannot schedule more work.

All 57 baseline Home/metadata/pagination checks pass. A new real-screen test passes
before and after the move, observing the old hero through 259ms, replacement at
260ms and cancellation on an A→B→A focus jiggle. Four direct timing cases cover
latest-request precedence, cancel/rearm versus disposal, live eligibility at firing,
and reentrant scheduling followed by cancellation (62 affected successes total).
Source comparison confirms the entire parent is unchanged except the declared
owner and its delegates. Analysis retains exactly 852 diagnostic identities;
all 394 measured files pass size/import checks, and formatting/diff checks pass.
The parent is 17,080 lines and remains the temporary orchestration exception.
Evidence: `hero-swap-*` and `analyze-hero-swap.txt` under
`.git/refactor-evidence/phase5/`. The last full suite remains
`full-hero-retirement.jsonl`, predating these five cases and the separately
reviewed title-cache bound. Tint extraction, parent actions/navigation, native
handoff, final facade/CI audit and device/performance evidence remain open.

#### Hero tint request and cache ownership review

`application/home_hero_tint_loader.dart` (64 lines) now owns the per-view
120ms debounce, request generation and title-color cache. Its 28-line Riverpod
factory binds the existing profile/view session and injects the shared dominant
color resolver. Provider construction does not extract artwork. The production
screen delegates every tint request and retires the loader at the original timer
cancellation point, before disposing visible signals; provider cleanup is
idempotent. The original timer/request/cache fields and now-unused image/cache
imports are removed.

Missing posters, cached colors and cached nulls still wait the full 120ms. Cache
identity remains the title ID, the full-clear threshold still permits 301 entries,
and stale completions cannot populate the cache. The shared 64-entry URL cache,
in-flight deduplication, extraction failure-to-null behavior and image decoding
remain unchanged and borrowed. Visible hero color still publishes before shell
color; layout eligibility and live/trailer tint clearing remain with their
existing presentation owners. Captured profile/session retirement now also rejects
outgoing requests before the timer fires and after extraction; this is the scoped
ownership improvement, not a claim of unchanged stale-profile behavior.

The 45 pre-extraction checks pass. The broader affected run passes 81 checks,
including pagination and twelve new cases: seven timing/cache/retirement cases,
four Riverpod disposal/recomputation/profile/handoff cases and one actual Home
screen injection/publication-order case. The screen fixture gained an optional
catalog response and reuses its existing image fake; the initial custom-hero
fixture did not drive the Classic focused hero, and a real image cache required
native plugins, so both fixture assumptions were corrected without changing
production behavior. Source review confirms shell eligibility and publication
order are retained. Architecture checks pass for 396 measured files; the parent
is 17,055 lines and remains the documented orchestration exception. Evidence:
`hero-tint-*` and `analyze-hero-tint.txt` under `.git/refactor-evidence/phase5/`.

Analysis retains exactly 852 diagnostic identities. The unchanged repeat full suite
(`full-hero-tint-verified.jsonl`) records 9,290 successes, the same 22 failures/
29 errors/20 skips, and every previous outcome plus seventeen passing cases
(the five hero-swap tests and twelve tint tests). The first run had the previously
observed remote-transfer `.part` cleanup race at test line 313: completion is
reported before awaited journal/file cleanup. All eighteen transfer cases passed
independently and the unchanged full repeat passed that case. Both runs remain
in evidence; neither the transfer code nor failure allowances changed.
Parent actions/navigation, remaining lifecycle boundaries, native handoff, final
facade/CI audit and device/performance gates remain open.

#### TV Home hero shell registration ownership review

`presentation/home_hero_shell_bridge.dart` (91 lines) now owns the TV Home hero's
sidebar, takeover/lights-off, player-launch and hardware-key registrations plus
its borrowed route-observer subscription. The screen creates this local
presentation owner under the unchanged TV Home/capacity predicate, before the
same initial preference reload. It delegates route binding at the original
`didChangeDependencies` position and retires the bridge before disposing the
borrowed hero signals. This is presentation lifecycle ownership, not application
state, so it does not introduce another provider or a second visible-state owner.

The bridge detaches in the original order and preserves all four conditional
post-frame shell resets, including the original frame timing. An inactive shell
at disposal still schedules no reset; it does not clear later state accidentally
through an unconditional new callback. The bridge never disposes borrowed
notifiers, the observer or native players. Explicit disposal is idempotent and
retired owners cannot rebind routes. Original eligibility, trailer scheduling,
route-return, sidebar, content-launch and takeover callback bodies are unchanged.
Off-TV's separate player-launch registration is retained. Style changes remain
independent of these registrations, and low-memory TV Home still renders its
hero without claiming the heavy TV shell lifecycle.

All 60 baseline checks pass. Two real-screen regular/low-memory TV cleanup cases
pass before and after extraction. Four bridge cases cover independent listeners
and keyboard detachment, unique route cover/return observation and retirement,
and both active and inactive post-frame reset conditions (66 affected checks).
The first isolated reset fixture lacked a scheduled frame; it now explicitly
schedules one rather than changing the production callback timing. The renamed
bridge's six new checks also pass independently.

Architecture review identifies this as the explicit legacy UI integration bridge:
only its two concrete UI registry imports (`main_page_bridge.dart` and
`app_route_observer.dart`) are allowed at this named path. The checker still
rejects such service imports from ordinary views and other data/platform APIs
from this bridge. All 397 measured files pass. The parent is 17,011 lines and
remains the temporary orchestration exception. Source-comparison evidence is in
`hero-shell-review.txt`; focused logs use `hero-shell-*` under
`.git/refactor-evidence/phase5/`. Analysis retains exactly 852 diagnostic identities.
The unchanged repeat full suite (`full-hero-shell-verified.jsonl`) records 9,296
successes, the same 22 failures/29 errors/20 skips and every previous outcome plus
six passing cases. The first run reproduced the already-evidenced remote-transfer
`.part` cleanup race at test line 313; all eighteen transfer tests passed
independently and the unchanged full repeat passed that case. Both runs are
retained; no transfer code or failure allowances changed.
Native handoff, remaining surface/lifecycle policy, parent actions/navigation,
final facade/CI audit and device/performance gates remain open.

#### Home stage theater dwell ownership review

`presentation/home_stage_theater.dart` (73 lines) now owns the per-view five-second
theater timer and its local visual state. The screen reads that state directly,
keeps the existing listener/key registrations, and rebuilds the same layout on
notifications. No provider, data service or competing boolean was added. Layout
transitions reset the owner silently at the original combined reset point;
disposal cancels it before the surrounding stage signals are disposed. The old
boolean, timer, dwell constant and scheduling implementation are removed.

The dwell still rechecks mounted state, layout eligibility and visible playback
at firing. Playback stop or an ineligible layout cancels pending work and restores
an active shelf once. Key-down while theater is active wakes it and starts a new
five-second dwell; key-up/repeat and keys while inactive do not rearm it. The
handler always returns false so the input continues to its original action.
Timer references are released after firing, reset and disposal, and disposed owners
cannot start new work. Discover's separate timer/state and native player
ownership are unchanged.

All 73 baseline layout/Home/pagination checks pass. A real Canvas screen case
passes before and after extraction: no theater through 4,999ms, theater at 5,000ms,
key wake/rearm at the same cadence, the same mounted shelf element and retained
focus, then playback-stop cancellation. Seven direct timing cases cover input
kinds, each live gate, stop/cancellation, silent layout reset and disposal
(81 affected successes total). The first direct fixture needed an explicit type
for its self-referencing callback; this was corrected without production changes.
Analysis retains exactly 852 diagnostic identities. All 398 measured files pass
size/import checks, with the parent at 16,983 lines. Formatting/diff review passes;
source review confirms only the original theater owner and delegates changed.
Evidence: `stage-theater-*` and `analyze-stage-theater.txt` under
`.git/refactor-evidence/phase5/`. The latest full suite remains
`full-hero-shell-verified.jsonl` (9,296 successes and the same 51 failures/20 skips),
predating these eight new checks; this bounded presentation slice used affected
verification. Remaining lifecycle/surface rules, actions/navigation, native
handoff, final facade/CI audit and device/performance gates stay open.

#### Post-playback refresh ownership review

`application/home_post_playback_refresh_controller.dart` (87 lines) now owns
one profile/view's playback latch and ordered return refresh through Riverpod.
The screen supplies explicit existing loader callbacks and keeps route/current-page
eligibility, lifecycle notifications and native playback ownership. The old mutable
screen latch and refresh sequence are removed; both the global content-launch
listener and IPTV CW entry point mark the controller. Existing route-return and
forced-tracker callers still use the same screen entry point. The parent remains
the documented orchestration exception at 16,749 lines.

Resume-cache clearing still precedes synchronous latch consumption. Refresh order
remains watchlist, local CW, IPTV CW, the parallel Trakt/Simkl/eligible-MDBList
batch, then bound-source badges. Search consumes the latch but skips trackers.
MDBList's pending/force-fresh scrobble decision is evaluated at the original point
after local reads; tracker calls retain `refreshBound: false`, and MDBList retains
`force: true`. Existing diagnostic handling catches failures without retries.

Overlapping returns deliberately do not supersede each other: each keeps its local
refresh, while only the invocation that consumed playback owns that tracker batch.
A launch during an in-flight refresh remains latched for the next return. Provider
recomputation retains accepted latch state but retires old continuations. Explicit
profile/session/provider/view guards now prevent starting or continuing a retired
sequence; this is an ownership improvement over the former mounted-only await
guards. Individual data loaders retain their own captured-scope, stale-result and
retry ownership. This change does not claim to cancel already-started native work
or audit the remaining playback/navigation bridges.

All 41 affected observed baseline checks pass, along with thirteen new controller
cases for ordering, parallel completion, overlap, new launches, Search gating,
late scrobble eligibility, retirement, recomputation, independent views and errors.
A real Home case passes before and after extraction: trailer launches do not
refresh Trakt, content playback refreshes once, and another return does not repeat
it (55 affected successes). The new fixture's initial missing bridge-method name
was corrected, and its host-only path-provider failure was resolved with scoped
local/watchlist/IPTV/bound-count overrides so the production sequence reaches the
tracker boundary. No production plugin workaround was introduced. Review also
corrected one missing-braces lint in the new fixture.

Analysis retains exactly 852 diagnostic identities; all 410 measured source files
pass architecture checks. Formatting and diff/source review pass. Evidence:
`post-playback-*` and `analyze-post-playback*` under
`.git/refactor-evidence/phase5/`. The full suite (`full-post-playback.jsonl`)
records 9,367 successes, the same 22 failures/29 errors/20 skips, every previous
outcome unchanged and all fourteen new cases passing. Native
lifecycle, surface eligibility, route/action orchestration, final facade/CI and
representative device/performance acceptance remain open.

#### Classic hero composition review

`presentation/home_classic_hero.dart` (73 lines) now builds the classic board's
focused/enriched hero subtree. The actual board caller uses this function and its
old nested implementation is removed; the parent is 16,431 lines and remains the
orchestration exception. The existing HomeHeroSpotlight, metadata providers,
trailer/live signals and layout eligibility retain their original owners. The
small immutable configuration record carries only this hero's five display facts;
it is read inside the metadata listener build, rather than capturing potentially
stale layout/artwork settings during a parent build. No new state or DI owner is
introduced for presentation composition.

Review preserves nested listener order, no enriched subscription while focus is
null, the same element tree and hero state across metadata updates, nonempty
catalog background/description/logo precedence, nullable rating/runtime fallback,
and eager IMDb logo derivation. Height and decode budgets remain caller-selected.
The boxed region follows synchronous layout eligibility; asynchronous trailer
preferences still only gate playback. Loading UI remains in the trailer region;
showing freezes backdrop drift and live takeover hides the stale catalog identity.
The function borrows all notifiers and detaches listeners without disposing them.

Nine observed baseline hero/layout/screen cases, 24 before/after Home pagination
and remote-focus cases, and three new composition tests pass (36 successes). The new cases cover lazy empty focus, listener removal/reuse, late metadata
fallback and preserved hero state, and configuration changes seen on a metadata-only
rebuild. Analysis retains exactly 849 diagnostic identities; all 418 measured files
pass architecture checks. New Dart formatting and changed-call/diff review pass.
Evidence: `classic-hero-*` under `.git/refactor-evidence/phase5/`. The preceding full
checkpoint is 9,401 successes and the same 22 failures/29 errors/20 skips; this
bounded presentation extraction uses affected-suite comparisons. Remaining layout
dispatch, shared actions/native lifecycle, final facade/CI and representative device/
performance acceptance are not closed by this extraction.

#### Random episode selection boundary review

`data/home_random_episode_selector.dart` (96 lines) now converts raw addon episode
metadata into an `AdvancedSearchSelection`; the 13-line
`application/home_random_episode_dependencies.dart` provides its stateless Riverpod
wiring. The raw JSON normalization stays at this data boundary. The selector has no
Flutter UI, Riverpod, transport, storage or playback dependency: the factory supplies
the existing Stremio identity rules, and randomness can be deterministic in tests.
The screen's actual random-play action calls it and the original candidate/selection
implementation is removed. The parent is 16,405 lines and remains the orchestration
exception. Dialog choice, metadata-addon selection/fetch, inventory recording,
messages and the final player handoff retain their original order and owners;
these remaining action responsibilities still require extraction and lifecycle review.

Review preserves numeric coordinate normalization, exclusion of specials and invalid
or future episodes, unknown-date acceptance, candidate order and duplicate weighting,
exact video-ID preference, canonical-ID synthesis eligibility, and null/no-candidate
behavior without consuming randomness. The selected title/year/poster/content type,
continuous-shuffle flag and configured metadata-addon identity reach the same launch
model. Custom episode overrides continue to use `withStremioEpisodeIdentity`, including
its addon-scoped progress key; the new fixture was corrected to assert that existing
behavior rather than expecting the unscoped catalog ID. A missing metadata addon
still leaves the selection unscoped. Production creates a fresh random choice per
action, as before, and does not introduce shuffle history or new retries.

All 21 observed baseline dialog/launch/shuffle checks and seven new selector/DI
cases pass (28 successes). Tests cover malformed metadata, numeric normalization,
release eligibility, duplicate weighting, preserved inputs, empty inventories,
custom/canonical identity, absent metadata addon and continuous intent. Analyzer
identities remain exactly 849; all 420 migrated files pass size/import checks.
Changed Dart formatting, actual caller replacement and diff review pass. Evidence:
`random-episode-selection-*` under `.git/refactor-evidence/phase5/`.
The full comparison (`full-random-episode-selection.*`) completes with 9,411
successes and the same 22 failures/29 errors/20 skips. Every previous test outcome
is unchanged; its ten added successes cover this selector and the preceding classic
hero composition. The full runner's exit 1 is the unchanged baseline failures.

The remaining random-action asynchronous loading/persistence and presentation
handoff are explicit follow-up work; this policy extraction does not establish
native playback, profile-switch or whole-action completion. Other resume/source
selection paths, final facade/CI and device/performance acceptance remain open.

#### Random playback metadata preparation review

`data/home_random_playback_repository.dart` (102 lines) now owns random playback's
metadata-addon choice, metadata loading, nonblocking inventory recording and
selection preparation. `models/home_random_playback_preparation.dart` (22 lines)
returns ready/no-episodes/load-failed/retired data outcomes; the existing dependency
factory (59 lines) supplies concrete readers/writer, selector and captured profile
scope. The actual action delegates to this repository. The old `_metaAddonFor`
implementation and direct inventory-service import are removed. The parent is
16,369 lines and remains the orchestration exception; its remaining random-action
method contains dialog/message/launch dispatch, without raw metadata or persistence.

Review preserves the built-in/native guide exception, preferred metadata addon,
first enabled usable fallback, and origin-versus-progress content ID rule. Addon
lookup errors retain their propagation; episode-fetch errors retain their distinct
retry message. Null/empty metadata, missing progress identity, initial inventory
record timing, no delay on the inventory future, selected metadata-addon identity,
continuous mode and the original addon passed to playback are preserved. Independent
actions still prepare independently; there is no new busy/latest-action latch.
No work starts in provider initialization. The disposable factory produces a
stateless repository retained by each explicit operation; borrowed services and
selector have no operation-owned resources to dispose.

The scoped destination intentionally strengthens the previous mounted-only guard:
originating owner/view is checked before work, after addon/episode awaits and before
presentation dispatch. Readers run in captured profile scope. Inventory recording
forwards the same live guard through the existing LocalSeriesCompletionService
commit barrier, preventing a queued write after retirement. Asynchronous inventory
errors are now explicitly diagnosed without blocking playback or logging title/
credential data. This does not replace the broader native player lifecycle audit.

All 37 observed dialog/selection/shuffle/inventory baseline checks pass. Fourteen
new repository tests cover addon selection, content identity, load/lookup errors,
empty/null metadata, recording order, nonblocking error handling, retirement at
both awaits, live commit guard and independent overlapping actions. Three factory
checks include the actual preference mutation barrier (no stale persisted value or
revision), an active committed-profile write only in its captured namespace, and
retained-repository retirement before service access (54 affected successes).
Analysis retains exactly 849 diagnostic identities after removing the now-unused
legacy import; all 422 measured files pass architecture checks. Formatting, caller
replacement and diff review pass. Evidence: `random-preparation-*` under
`.git/refactor-evidence/phase5/`.
The full comparison (`full-random-preparation.*`) completes with 9,428 successes
and the same 22 failures/29 errors/20 skips. No previous outcome changes or goes
missing; all seventeen new repository/factory tests succeed. The full runner's
exit 1 reflects the unchanged baseline failures rather than an entirely green suite.

The random action's dialog/message/player bridge, other resume/source-selection
paths, final facade/CI and native/device/performance acceptance remain open.

#### Random playback presentation bridge review

`presentation/home_random_playback_action.dart` (48 lines) now owns the explicit
random-action dialog, preparation-result messages and typed launch dispatch. The
actual detail action delegates to it; the parent's dialog/result-switch code and
unused direct imports are removed. The parent is 16,359 lines and remains the
orchestration exception. It supplies lazy Riverpod preparation, its existing
message callback and `_playSelection` handoff; the bridge imports no data/platform
service and creates no state owner or event mechanism.

Review preserves both choices, title text, cancellation, original failure/empty
messages and their legacy localization exception. Preparation dependencies are not
read until the choice is accepted. The originating view/profile guard runs before
context/ref access and after each await; the bridge also checks its own context's
mounted state. Retired results cause no message or launch. Addon-lookup exceptions
retain propagation. A ready selection is passed unchanged with the original catalog
addon ID and `item.withSourceAddon(addon)`, even if metadata used a fallback addon.
Playback dispatch stays unawaited, preserving the existing action-completion timing.

All 32 observed launch/dialog/repository/adapter baseline checks and eleven new
presentation cases pass (43 successes). Widget tests drive the real dialog with
remote input and cancellation, verify exact launch arguments and one dispatch for
each mode, leave a fake player future pending to verify nonblocking handoff, retire
while choosing/preparing or unmount before completion, check each result message,
and verify preparation exception propagation. Analysis retains exactly 849 diagnostic
identities; all 423 migrated files pass architecture checks. Changed Dart formatting,
caller/payload and diff review pass. Evidence: `random-action-*` under
`.git/refactor-evidence/phase5/`.
The full comparison (`full-random-action.*`) completes with 9,439 successes and
the same 22 failures/29 errors/20 skips. Every prior outcome is unchanged and all
eleven new presentation tests succeed. Exit 1 reflects those unchanged baseline
failures; host widget checks do not establish native player/device parity.

The random action's feature boundaries are now separated. The shared legacy
`_playSelection` path and other resume/source/navigation actions, native lifecycle,
final facade/CI and representative device/performance acceptance remain open.

#### Catalog episode identity resolution review

`data/home_catalog_episode_identity.dart` (73 lines) now resolves the exact episode
identity immediately before catalog play or source browsing. Its 42-line dependency
factory wires the same Stremio singleton reader/canonical rules inside captured
profile scope. The actual catalog launch closure delegates to it and the old
`_withCatalogEpisodeIdentity` screen method is removed. The parent is 16,334 lines
and remains the orchestration exception; its larger resume/selection and native
handoff responsibilities are still open. The resolver is stateless, receives no
BuildContext/Ref, and introduces no cache, retry or competing action state.

Review preserves no-lookup movie/incomplete-coordinate paths and returns the exact
original selection for canonical aliases/episodes, including its tracker/resume
fields. Known noncanonical IDs keep their exact spelling and use the same model
copy method/configuration binding. Missing custom IDs still produce an explicitly
scoped unresolved identity with empty video ID, so playback can retry/fail rather
than silently launch a different IMDb edit. Existing custom progress scoping and
tracker-attribution clearing remain the model's responsibility. Lookup exceptions
retain propagation and overlapping actions remain independent.

The scoped destination strengthens action retirement at this boundary: the launch
closure rejects a retired view/profile/cancelled action before ref access, the
resolver checks owner/action before and after its read, and the caller rechecks
before its existing overlay dismissal and play/browse dispatch. A retired result
is null and cannot launch. Concrete reads use the originating profile scope; the
disposable factory itself owns no operation resources. Other earlier awaits in
catalog resume preparation still need their broader ownership audit.

All 25 observed custom-progress/launch/metadata-cache baseline checks and fourteen
new resolver/factory cases pass (39 successes). Tests cover missing/canonical/custom
IDs, exact payloads, absent coordinates, unchanged original selection, preserved
custom scope/attribution behavior, lookup failures, independent overlapping reads,
retirement before access and after completion, retained adapter retirement and the
production canonical lookup after factory disposal. Analysis retains
exactly 849 diagnostic identities; all 425 measured files pass architecture checks.
Changed Dart formatting and caller/payload/diff review pass. Evidence:
`catalog-episode-identity-*` under `.git/refactor-evidence/phase5/`.
The full comparison (`full-catalog-episode-identity.*`) completes with 9,453
successes and the same 22 failures/29 errors/20 skips. No prior outcome changes
or disappears; all fourteen new tests succeed. Exit 1 reflects those unchanged
baseline failures, not a claim that the entire suite is green.

Shared catalog resume/source/navigation orchestration, native player lifecycle,
final facade/CI and representative device/performance acceptance remain open.

#### Shared catalog-origin preparation review

`data/home_catalog_origin_repository.dart` (55 lines), its 23-line outcome model
and 36-line captured-scope dependency factory now share identity/addon preparation
between detail opening and catalog playback. Both production callers delegate;
their duplicate native-addon/classification/origin logic and `_progressOriginAddon`
helper are removed. The parent is 16,336 lines and remains the orchestration
exception; explicit subscriptions/action guards are not presented as size-only
progress. Detail opening retains its unavailable-history dialog, while playback
retains its unavailable-configuration message. Tracking-policy loading and later
resume/native dispatch are intentionally still separate work.

Review preserves native-ID/no-IMDb/no-configured-source fallback, classification
before history access, parsed custom-origin lookup, malformed-prefix behavior,
reattachment of custom items to the resolved configuration, and propagation of
non-StateError classification failures or origin-lookup errors. Only classification
StateError yields the existing verification message; missing origins retain the
classified item for the existing history UI. Each explicit action owns its guard;
there is no shared busy state, auto retry or eager provider work.

Originating view/profile is checked before preparation and after its awaits. The
existing Stremio service receives an optional guard in `scopeSeriesProgress` and
its mapping writer: checks follow preference/metadata awaits, wrap the mapping
commit inside the existing preference mutation barrier, and prevent stale cache
revision publication. Local episode inventory receives the same live commit guard.
Unguarded service callers preserve their prior path. The retained 3,748-line service
exception is scoped above; no transport/cache redesign or whole-service formatting
is included. Readers/writes run in the originating profile scope.

All 39 observed custom-progress/metadata-cache/native-guide baseline cases and
thirteen new repository/factory checks pass (52 successes). New checks cover native
and configured origins, custom and unavailable identities, exception boundaries,
retirement during classification/origin reads and real service persistence: a held
mapping commit retires without writing or publishing a revision; an active commit
uses only the captured profile namespace; a cancelled real metadata response writes
neither progress mapping nor local inventory. Explicit mounted checks and braces
restore the exact 849 analyzer identities. All 428 migrated files pass architecture
checks; changed-member formatting and caller/diff review pass. Evidence:
`catalog-origin-*` under `.git/refactor-evidence/phase5/`.
The full comparison (`full-catalog-origin.*`) completes with 9,466 successes and
the same 22 failures/29 errors/20 skips. Every prior outcome is unchanged and all
thirteen new tests succeed. Exit 1 reflects the unchanged baseline failures;
these host checks do not replace native/device acceptance.

Tracking-policy loading, unavailable-history removal, resume/source/navigation
actions, native lifecycle, final facade/CI and representative device/performance
acceptance remain open. This boundary does not prove all later action writes or
native playback profile-safe.

#### Tracking-policy loading review

All three catalog/resume policy loads now delegate to the injected
`data/home_tracking_policy_repository.dart` (56 lines), composed by the 51-line
captured-profile Riverpod factory. Every explicit action gets fresh sequential
scrobble/progress/credential/fallback/tick reads, then the existing content policy.
Disconnected dedicated sources still select Smart for that snapshot even if the
fallback reports no stored change. Custom/local identities still load preferences
before applying their local policy; native identity interpretation is unchanged.
There is no new cache, busy latch, automatic retry or provider-started write.

The parent is 16,360 lines; its added delegation and retirement checks establish a
boundary rather than a size-only reduction. Retired loads return null; playback
stops and resume readers return their existing neutral shape without cache writes.
Later resume continuations and dispatch still require their own ownership audit.
The retained shared `TrackingSourcePolicy.load` supports unmigrated callers.

`lib/services/storage_service.dart` remains an external legacy storage exception
(10,831 -> 10,876 lines). Changes are limited to optional guards for scrobble reads,
three tracker-presence readers and disconnected-progress fallback; unrelated
persistence stays outside this extraction. Legacy callers preserve their path.
`TrackingScrobblePreferences` (118 lines) forwards the guard for first-read seeding.
The existing `lib/services/profiles/profile_preferences.dart` is also a temporary
external storage exception (974 -> 987 lines): atomic-list, string and boolean
writes forward optional commit guards to the existing writer. Its update callback
runs before the storage barrier, so guarding only that callback was insufficient.
The guard now runs after the barrier and before mutation; cancelled writes cannot
publish mutation/native/sync notifications. Existing unguarded lock order, budget
checks and successful-write publication remain. Phase 8 audits these retained
service dependencies; neither exception permits oversized extracted feature code.

The disconnected fallback checks each scalar commit individually. It does not hold
an outer ordinary mutation across both writes: a snapshot starting between them
must be able to settle. A dedicated test starts that snapshot from the revision
notification, retires the action while the notice is queued, and verifies that the
already-committed Smart setting remains while the stale notice is not written.
Credential reads retain the captured profile and forward the guard through lazy
legacy sealing; resource-backed presence retains the existing authorization path.

All 143 affected checks pass: 112 existing cases plus 31 new reader/factory cases.
These cover each progress mode and credential status, exact read order, fresh
content policies, errors without retry, view/owner retirement at every await,
actual held seeding/fallback/credential commits, legacy credential sealing for all
three trackers, committed-profile namespace writes, retained factory freshness,
and the between-writes snapshot race. The initial seed-barrier test caught a real
pre-commit guard gap, which was fixed and rerun. Evidence is `tracking-policy-*`
and `tracking-storage-before.txt` under `.git/refactor-evidence/phase5/`.
The final analyzer comparison has 848 diagnostics (849 before): no new identities
and one removed async-context warning after the explicit mounted guard. All 430
migrated files pass size/import checks. Changed-file/member formatting and diff
checks pass. The final full comparison (`full-tracking-policy-final.*`) completed
with 9,497 successes, the same 22 failures/29 errors and 20 skips. Every prior test
outcome is unchanged; all 31 new cases succeed. Exit 1 reflects the existing failure
baseline. These host results do not replace native/device acceptance.

Tracking-policy loading does not complete later resume/source/navigation actions,
unavailable-history removal, native lifecycle, final facade/CI or representative
native/device/performance acceptance. Those gates remain open.

#### Unavailable-origin confirmation review

`presentation/home_unavailable_origin_dialog.dart` (33 lines) now owns the actual
Home unavailable-addon confirmation. It takes title, a live membership reader and
an originating view/profile guard, with no data or service dependencies. The
parent's inline dialog is removed; it is 16,356 lines and remains the orchestration
exception. Title/copy, Close/Remove ordering, membership evaluation in the dialog
builder, barrier/back dismissal, focus traversal and Navigator result are preserved.
The unchanged copy retains the legacy localization exception.

The dialog rejects an already-retired origin and a result returned after view or
profile retirement; the caller also checks ownership immediately before starting
removal. This explicitly closes the old dialog-return gap. An active confirmation
retains the original sequential Continue Watching removal, playback-state clearing,
resume-cache clearing and reload. No new provider, latch, cache, navigation route or
resource owner is introduced for this presentation-only responsibility.

All 25 observed existing tests and twelve new checks pass (37 total). The dialog
cases cover eligible/ineligible titles, lazy membership, Close/back/barrier outcomes,
remote directional selection, retired profiles, and an originating view disposed
while its modal remains on the Navigator. Two actual Home-screen cases verify
persisted Continue Watching/playback state: an active confirmation removes both;
a profile retired while the dialog is open preserves both. The active production
flow also passes against the previous screen implementation and the new one.
The test fixture supplies image caching rather than relying on unavailable host
plugins; no production image behavior changes. Analyzer identities remain exactly
848, and all 431 migrated files pass size/import checks. Formatting and caller/diff
review pass. Evidence is `unavailable-origin-*` under
`.git/refactor-evidence/phase5/`. The final full comparison
(`full-unavailable-origin.*`) completes with 9,509 successes, the same 22 failures,
29 errors and 20 skips. Every prior outcome is unchanged and all twelve new cases
succeed. Exit 1 reflects the existing baseline; native/device acceptance remains
separate.

This slice closes confirmation presentation and the pre-deletion guard only.
Accepted deletion still calls the legacy storage workflow, which persists Continue
Watching/playback state and sync/native deletion journals. Its captured-profile,
commit and retirement audit remains required before extracting that data action;
a guard before invoking storage is not proof of safety after its internal awaits.
Remaining resume/source/navigation actions, native lifecycle, final facade/CI and
representative native/device/performance acceptance remain open.

#### Tracker resume reader review

`data/home_tracker_resume_repository.dart` (105 lines) owns the three catalog movie
progress readers and shared MDBList candidate lookup. Its 45-line Riverpod factory
keys the repository by `HomeCatalogSession`, captures the originating profile scope,
and disposes the repository with its subscription. Home explicitly retains it for
the mounted view and retires it during disposal. The screen's memo, percentile
filters and direct MDBList feed-service dependency are removed; four small delegates
serve the existing label, Play and series/MDBList callers. The parent is 16,318 lines
and remains the orchestration exception. No new UI state or global container exists.

Review preserves Trakt's exact `tt` prefix check and strict 30-second memo, including
cached nulls, completion-time timestamps and independent concurrent reads whose last
completion wins. Simkl retains its IMDb/native identity rules and service-owned
cache. MDBList retains case folding without trimming, usable partial data, movies
before shows, first matching identity, paused-movie eligibility and its below-80%
cutoff; Trakt/Simkl retain below-90%. Existing numeric-comparison semantics remain.
Caller authentication/gating, series reconciliation, sequential label lookups,
parallel Play lookups and their four-second timeouts are unchanged. Timeouts still
allow an accepted background Trakt read to finish and warm the memo for this view.

The repository checks view, profile-session and disposal before reads and after
awaits; stale results cannot populate its memo. Disposal clears retained values.
This guards this reader's publication, not every transitive tracker operation:
legacy service authentication/refresh, lazy credential migration and internal feed
caches retain their existing implementations and need the recorded broader audit.
The initial move retained legacy per-view key growth to isolate structural parity;
the separate capacity review below closes that resource exception. This does not
close the representative-device performance gate. No tracker service or
storage implementation changes in this slice.

All 97 affected checks pass: 50 observed movie/storage/feed baseline tests, 24 Home
paging/lifecycle cases and 23 new repository/factory cases. New coverage includes
TTL boundary and completion clock, cached misses, exact cache keys, independent
overlaps, each tracker identity/filter/error path, partial/ordered MDBList candidates,
retirement at pending reads and rejection of late memo writes. Real Trakt transport
through the production factory verifies one view reuses its memo, another view
fetches independently, and provider/profile retirement rejects a delayed response.
The HTTP fixture supplies authoritative pagination headers, preserving production
pagination behavior. The screen retains and disposes its subscription through all
observed Home paging/lifecycle scenarios.

Analyzer identities remain exactly 848. All 433 migrated files pass size/import
checks; new files and changed screen members match Dart formatting, and caller/diff
review passes. Evidence is `tracker-resume-*` under `.git/refactor-evidence/phase5/`.
The full comparison (`full-tracker-resume.*`) completes with 9,532 successes and
the same 22 failures/29 errors/20 skips. Every previous outcome is unchanged and
all 23 new cases succeed. Exit 1 reflects the existing failure baseline; these host
checks do not close native/device or performance gates. Later resume selection, accepted
deletion journals, native/player handoff, facade/CI and representative native/device/
performance gates remain open.

#### Reviewed tracker resume memo capacity

The Trakt movie memo's key-growth exception is closed. The 114-line repository
now retains at most 512 entries per mounted view, including cached misses, and
removes the least recently used entry when a completed read exceeds the limit.
This is an intentional resource-policy change, separate from the reader extraction:
an evicted title can require a new lookup within its former 30-second window.
The cap follows the existing 512-entry small-memo scale without claiming it is a
measured device optimum. Normal below-capacity request reuse is unchanged.

A hit updates recency without changing its completion timestamp. Refreshing an
existing expired key replaces it without consuming a second slot. Errors and
retired responses cannot update recency or evict accepted entries; view/profile
ownership, independent overlaps, null caching and service/caller timeouts retain
the preceding slice's behavior. Disposal still clears the memo. No generic cache
framework, timer, new state provider or service change is added.

All 23 observed reader/factory baseline checks and five new capacity cases pass
(28 total), verifying hot/cold eviction, bounded cached misses, unchanged TTL,
refresh at capacity, and no eviction by failed/retired reads. Analyzer identities
remain exactly 848; all 433 migrated files pass architecture checks. Formatting,
diff and cache ownership review pass. Evidence is `tracker-resume-capacity-*`
under `.git/refactor-evidence/phase5/`. At this checkpoint, the full suite was
`full-tracker-resume.*` (9,532 successes / 51 existing failures-errors / 20 skips),
which predated this resource-policy change; the subsequent artwork review below
records the passing full comparison covering both changes. Representative
native/device performance, tracker internals and the remaining action/facade/CI
gates are still open.

#### Playback artwork ownership review

`presentation/home_playback_artwork.dart` (46 lines) now owns the mounted view's
single artwork object and matching key. The actual Simkl quick-play/catalog Play
capture sites, merged-detail enrichment callback, resolving overlay and playback
metadata builder delegate to that owner. The parent's two fields and four helper
methods are removed, leaving 16,270 lines; its orchestration exception remains.
This is presentation-only retained state with no I/O, subscriptions, timer or native
resource, so it stays a plain per-view owner rather than a new application provider.
There is one source of truth and no added global cache or lifecycle side effect.

Review preserves progress-ID precedence, `PlayLoaderArt.fromMeta` formatting and
art derivation, detail enrichment over same-key sparse catalog capture, clearing
for an empty different title, unconditional detail adoption (including an explicitly
empty object), and direct current-art use during resolving. Selection lookup keeps
its exact normalized key/non-empty ID fallback. In particular, matching a title
alone does not cross different non-empty IDs; title normalization changes only
case and surrounding whitespace. The old separator-containing-ID behavior is
retained and explicitly tested; changing it needs a separate identity-policy review,
not an undocumented correction mixed into structural extraction.

All 33 observed loader/model/rendering baseline cases and nine new ownership cases
pass (42 total). The same nine cases also pass against the exact old methods
extracted from the previous committed screen and wrapped only with the new public
method names; this provides direct before/after behavior evidence. Cases cover
catalog-to-loader artwork, enriched and empty-detail precedence, ID/title matching,
empty reset, replacement, view isolation and the separator edge. Analyzer identities
remain exactly 848, all 434 migrated files pass size/import checks, and formatting/
caller/diff review passes. Evidence is `playback-artwork-*` and
`legacy_playback_artwork_test.dart` under `.git/refactor-evidence/phase5/`.
The full comparison (`full-playback-artwork.*`) also covers the preceding five
cache-capacity cases: 9,546 successes, the same 22 failures/29 errors/20 skips,
every previous outcome unchanged and all fourteen new cases succeeding. Exit 1
reflects the existing baseline. These host results do not replace device acceptance. Parent action/profile continuations, deletion journals, native
handoff, final facade/CI and representative native/device/performance gates remain.

#### Catalog playback payload review

`data/home_catalog_playback_payload.dart` (80 lines) now constructs catalog movie
selections and player metadata from explicit typed inputs. Both actual movie Play/
Sources callers use the shared selection factory and the old `_movieSelection`
method is removed. `_metaFor` now supplies only the current addon fallback and
matched presentation artwork to the metadata factory. Bind, keyword-bind, Play
and Sources callers retain that wrapper. The parent is 16,220 lines and remains
the recorded orchestration exception. These are stateless model factories: no
provider, interface, I/O or lifecycle owner is added.

Review preserves resolved progress identity (including typed TMDB movie IDs) before
raw catalog fallback, so arbitrary addon/channel IDs remain usable for stream
lookup. Metadata retains the old IMDb-prefix/native/custom identity predicate and
leaves unsupported tracking IDs null. Source flags and resume percentages remain
independent and unfiltered here; their eligibility and tracking masters stay with
the existing readers/player policy. `PlaybackMeta.catalog` preserves canonical
cross-source resume, shuffle intent, episode coordinates, exact Stremio configuration/
catalog/video identity, artwork, display metadata and all three tracker attributions.
Addon precedence remains configured catalog origin, explicit caller ID, then the
screen fallback, using null semantics rather than treating empty strings as absent.
The exact catalog object/configuration and artwork references are retained.

All 44 observed launch/resume/custom-progress baseline checks and seven new payload
cases pass (51 total). The same seven cases pass against the exact old helper
methods extracted from the preceding revision, with shims supplying only ambient
addon ID and already-selected artwork. Cases cover raw/native/custom identities,
source attribution independent of percentages, configured/explicit/ambient addon
precedence including empty strings, episode identity/shuffle/artwork, canonical
resume and content-type defaults. Analyzer identities remain exactly 848, all 435
migrated files pass size/import checks, and formatting/caller/diff review passes.
Evidence is `catalog-playback-payload-*` and
`legacy_catalog_playback_payload_test.dart` under `.git/refactor-evidence/phase5/`.
The full comparison (`full-catalog-playback-payload.*`) completes with 9,553
successes, the same 22 failures/29 errors/20 skips, every prior outcome unchanged
and all seven new cases succeeding. Exit 1 reflects the existing failure baseline;
these host checks do not replace device acceptance. Later resume decisions, action/profile
continuations, accepted deletion journals, native handoff, final facade/CI and
representative native/device/performance gates remain open.

#### Catalog player handoff review

`presentation/home_catalog_playback_bridge.dart` (80 lines) now owns the catalog
player's temporary external-launch listener, legacy context-dependent launch and
immediate refresh choice. `_playSelection` uses its Riverpod dependency and supplies
only selection, lazy metadata, the captured-addon Sources callback and existing
refresh callbacks. The old inline handoff is removed; the parent is 16,200 lines
and remains the orchestration exception. Architecture checks allow only this named
bridge to import the two existing player/shell services. The bridge is stateless;
each accepted action owns its listener until launch completion, including failures.
Native teardown remains owned by the legacy player, not provider disposal.

Review preserves listener registration before metadata construction, exact episode
and metadata forwarding, the Play-button Sources callback, and finally-based
listener removal before refresh. In-app completion refreshes fully only when the
originating board route is current; external launch, a covered board or no modal
route refreshes bound badges and leaves full refresh to existing return handling.
The caller still clears its series-resume memo before launch and captures the
originating addon for both immediate metadata and delayed Sources navigation.
The boundary additionally rejects retired view/profile actions before launch and
return-time feedback. This does not cancel an already accepted native launch or
prove the deeper player/storage continuations and delayed Sources callback safe;
those remain in the action/profile and native lifecycle audit.

All 27 observed payload, post-playback-controller and real Home tracker baseline
cases and ten new handoff cases pass (37 total). Six active-action/error cases also
pass against the exact preceding inline handoff with ambient names adapted to the
same harness. Tests cover current/covered/absent routes, external notification,
lazy metadata, exact episode/metadata and Sources forwarding, metadata/launch
errors, listener cleanup and pre/post-launch profile/view retirement. Analyzer
identities remain exactly 848; all 436 migrated files pass size/import checks.
Formatting and caller/diff review pass. Evidence is `catalog-handoff-*` and
`legacy_catalog_playback_bridge*` under `.git/refactor-evidence/phase5/`.
The full comparison (`full-catalog-handoff.*`) completes with 9,563 successes,
the same 22 failures/29 errors/20 skips, every preceding outcome unchanged and
all ten new cases succeeding. Exit 1 reflects the existing failure baseline.
Device/native/performance acceptance and the remaining action, resume, deletion,
facade and CI work remain open.

#### Home Sources navigation review

`presentation/home_sources_navigation.dart` (116 lines) now owns the three Home
Sources route entry points behind a stateless Riverpod dependency. The actual
browse/Play handoff, source binding and keyword binding callers use it; the parent
no longer imports or constructs `SourcesScreen`. Sources retains its search,
pinning and playback ownership. The parent is 16,197 lines and remains the
orchestration exception: binding selection/seed preparation, episode navigation,
resume decisions and wider action workflows are still present. No service import
exception, routing library, event bus or additional state owner was introduced.

Review preserves browse metadata capture before navigation and bind metadata
construction inside the route builder. Both paths retain the live TV-mode read
inside that builder rather than capturing it at the originating button press.
Exact selection/episode and metadata objects are forwarded. Browse alone keeps
`TvHeldKeyGuard`; Play handoff alone forces a source tap to play immediately.
Regular binding and keyword binding retain bind mode, optional editable keyword
seed and no added held-key wrapper. Missing browse identity retains the exact
three-second snackbar and performs neither metadata construction nor navigation.
Browse return calls the existing playback/CW refresh; binding return refreshes
bound badges. The bridge awaits that callback, without moving its persistence or
native work into presentation or provider disposal.

The callers reject retired view/profile actions before provider access, covering
the delayed Play-to-Sources callback as well as direct presses. The bridge also
checks before navigation, deferred route building and return feedback. This does
not dismiss an already accepted route or replace Sources' own captured-session
ownership; its transitive persistence/native audit remains in phases 4C/7/8.

All fifteen observed existing Sources binding/cache/retry and catalog-player cases
and nineteen new checks pass (34 total). Six active-session cases also pass against
the exact preceding inline route code adapted to the same harness. These cover
browse, Play, bind and keyword arguments, eager/lazy metadata, TV-mode changes
between press and first frame, Back and awaited single refresh, empty identity and
held activation repeat suppression. Further cases verify pre-launch, covered-route
and pre-first-frame retirement. Four tests use the default injected bridge with
the real Sources screen and controlled search repository, verify its actual widget
arguments and one search, and pop back with one refresh. Analyzer identities remain
exactly 848; all 437 migrated files pass size/import checks. Changed-member
formatting and caller/diff review pass. Evidence is `sources-navigation-*` and
`legacy_home_sources_navigation*` under `.git/refactor-evidence/phase5/`.
The full comparison (`full-sources-navigation.*`) completes with 9,582 successes,
the same 22 failures/29 errors/20 skips, every preceding outcome unchanged and
all nineteen new cases succeeding. Exit 1 reflects the existing failure baseline.
Remaining action/profile/native lifecycle, facade, CI and representative device/
performance gates remain open.

#### Series resume reconciliation decision review

`data/home_series_resume_resolution.dart` (212 lines) now owns ranking the already-
read Trakt, Simkl, MDBList and local series positions, selecting weak fallbacks,
and resolving a completed winner to its next episode. A 25-line model file names
the immutable result and diagnostic candidate records shared with the caller.
The actual `_reconcileSeriesResume` path used by both label and Play delegates to
this operation; the replaced decision block is removed. The parent is 16,006 lines
and remains the orchestration exception. The operation has no UI, Riverpod, cache,
persistence or concrete service dependency. Its explicit guide callback uses the
caller's original play identity, built-in preference and exact catalog origin.
Existing source eligibility, concurrent reads, individual read timeouts, 45-second
cache/revision identity and publication remain in the parent pending migration.

Review preserves timestamped positions ahead of timestampless positions, newest
first, with legacy source order for absent timestamps and the same comparator for
equal timestamps. Only paused MDBList entries compete as actual positions; an
unpaused coordinate remains a weak fallback after Simkl next-to-watch. Incomplete
Trakt/MDBList coordinates cannot become candidates. The exact winning Trakt or
MDBList selection is retained, including percentages and addon identity; Simkl's
percentage remains separate. Local completion/frontier rules still use the shared
`shouldAdvanceEpisodeResume` policy. A completed winner invokes the guide once,
with the existing four-second timeout. Guide success precedes a direct successor
tracker fallback; a distant frontier cannot teleport a rewatch. Unknown finale/
guide keeps the winner. Successful advancement clears the old position's selection
and Simkl percentage but retains the base winner's scrobbling source attribution.
Guide errors propagate as before. Optional typed callbacks keep the existing
winner-before-guide and advance-after-guide diagnostics in the caller.

All 54 observed merge, rewatch, resume and playback-request baseline cases and 28
new decision cases pass (82 total). The same 28 cases pass against the exact old
decision block with only ambient guide/diagnostic calls adapted to the harness.
A further deterministic 512-combination comparison matches original and extracted
targets, original-selection object identity, percentages, guide calls and diagnostic
events, including missing/incomplete inputs and boundary values. Focused cases cover
all four source winners, zero/equal/missing timestamps, weak fallback order, local
near-complete versus finished behavior, tracker threshold, season-boundary fallback,
recency-ordered adjacent frontier choice, guide precedence/errors and exact timeout
with a late result that cannot revise the returned target. Analyzer identities
remain exactly 848; all 439 migrated files pass size/import checks. Formatting and
caller/diff review pass. Evidence is `series-resume-resolution-*`,
`legacy_home_series_resume_resolution*` and `series_resume_resolution_matrix_test.dart`
under `.git/refactor-evidence/phase5/`. The full comparison
(`full-series-resume-resolution.*`) completes with 9,610 successes, the same
22 failures/29 errors/20 skips, every preceding outcome unchanged and all 28 new
cases succeeding. Exit 1 reflects the existing failure baseline.
The parent reader/cache profile-lifetime and capacity audit, remaining action and
native lifecycle work, final facade/CI and device/performance acceptance remain open.

#### Series resume reader ownership review

`data/home_series_resume_repository.dart` (184 lines) now owns the five remaining
series-resume readers: full Trakt signal, Trakt label position, Simkl paused signal,
Simkl next-to-watch and local history. A 55-line Riverpod factory captures the
originating profile for the concrete service calls; 22 lines of immutable record
aliases name the shared signals. All five actual parent helpers now delegate and
retain only the view guard and the existing progress-ID/raw-ID Trakt card lookup.
The old reader bodies are removed; the parent is 15,877 lines and remains the
orchestration exception. Auth eligibility, caller timeouts, concurrent-read order,
reconciliation and resume-cache ownership are unchanged and remain separately
tracked. No new cache, retry loop, service interface or view subscription is added.

Review preserves cached Trakt selection before the series-only live fallback,
including cached movies and nullable label coordinates. The full signal uses the
first exact matching feed item and carries its timestamp and original selection;
the label path retains the existing `resolveSelection` API including Up Next.
Empty IDs cannot accidentally select the first unrelated Trakt item. Simkl keeps
its series-only IMDb/native identity rules, raw paused percentage/timestamp and
weaker next-to-watch signal. Local reads still try identity first and title only
for non-native/non-custom identities with incomplete coordinates. Title fallback
replaces the entire record, including its finished flag. Millisecond fields retain
precedence over bare video fields, valid duration yields a clamped percentage,
nonpositive timestamps become null, and existing read errors propagate.

The repository is stateless per captured profile and each call supplies its own
live view guard. It rejects retired owners/views before work and after every await,
including before issuing a follow-up read. Ordinary provider disposal does not
cancel an accepted call: it owns no resource, and the retained factory stays useful
only while that originating profile and view remain current. Independent views do
not cancel each other's requests. Actual local storage reads are read-only through
`ProfilePreferences` and the existing playback-map decoder; no storage-service
change or new migration is introduced. Legacy tracker credential/cache internals
remain part of the transitive audit; captured scope and outer result guards alone
do not prove all their internal operations safe during a profile switch.

All 77 observed resume/progress/reconciliation/reader baseline cases and 60 new
checks pass (137 total). Twenty-two active-session/error cases also pass against
the exact old helpers adapted only to injected reads, the supplied cached Trakt
item and diagnostic callback. Unit coverage includes matching/precedence, native
and custom title isolation, nullable coordinates, numeric conversion, identity
eligibility, all before-read and awaited-step retirement boundaries, error
propagation and independent concurrent views. Production-factory tests read real
legacy and committed-profile history (including a foreign ambient scope), retain a
disposed stateless provider's factory without stale data, and delay actual Trakt
HTTP responses across active, profile-retired and view-retired cases. Analyzer
identities remain exactly 848; all 442 migrated files pass size/import checks.
Formatting and caller/diff review pass. Evidence is `series-resume-readers-*` and
`legacy_home_series_resume_repository*` under `.git/refactor-evidence/phase5/`.
The full comparison (`full-series-resume-readers.*`) completes with 9,670 successes,
the same 22 failures/29 errors/20 skips, every preceding outcome unchanged and
all sixty new cases succeeding. Exit 1 reflects the existing failure baseline.
The parent resume-cache lifetime/capacity and remaining action/native audits, final
facade/CI and device/performance gates remain open.

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

At each completed workflow checkpoint: format changed code, run `flutter analyze`,
run the affected existing/new tests, inspect the diff and line counts, and record
results. Use focused checks during implementation. Full-suite runs follow the
revised A+B, C+D and final gates above, with earlier runs for broad shared changes
or unexplained failures; do not repeat these gates for every helper extraction.
Never broaden accepted failures to hide a regression.
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

Playback metadata now lives in `lib/models/playback_meta.dart` (101 lines), with
its shared resume-policy enum in `lib/models/playback_resume_policy.dart` (6 lines).
Legacy service imports re-export those declarations, while the Sources playback
bridge imports the model directly and restricts its service import to the action
class. The model graph contains only model/URI helpers plus Dart conversion/crypto.
The retained playback service shrank from 8,866 to 8,773 lines and the resume
resolver from 126 to 122; their implementations are unchanged. Phase 7 still owns
native handoff/lifecycle checks, and phase 8 the final integration boundary audit.
Catalog/art objects retain their existing borrowed identity; no deep-copy contract
was introduced by the model move.

IPTV search/episode-resolution results now live in the shared 25-line
`lib/models/iptv_source_result.dart`, importing only Torrent. Six Sources
application/data/model consumers use that declaration directly; the IPTV service
re-exports it for compatibility. `lib/services/iptv_source_search.dart` shrank
from 1,190 to 1,169 lines and retains cached-catalog search, refresh coordination,
episode resolution and authorization. The existing const/list API is preserved;
the repository still wraps result rows in an immutable snapshot before publication.
Phase 8 must review remaining injected/classification service dependencies.

`AddonSearchStatus` now lives in the shared 36-line
`lib/models/addon_search_status.dart`, with no imports. Five Sources application/model
files use it directly; StremioService re-exports it for compatibility. The retained
`lib/services/stremio_service.dart` shrank from 3,754 to 3,720 lines. Its addon
installation, metadata and transport responsibilities remain outside this model
move; phase 8 must still review its injected boundaries and remaining pure
selectors. Only this model joins the measured source set; this legacy exception
does not authorize unrelated service additions.

Catalog-origin preparation scope: the retained service grows from 3,703 to 3,748
lines. Its progress classification persists a catalog-to-progress mapping and can
record local episode inventory. The bounded edit adds an optional continuation
guard to this classification and mapping commit, reusing the existing preference
mutation barrier; callers without a guard retain their behavior and direct commit
ordering. Only these members are formatted. Transport/addon installation and the
existing bounded metadata cache remain legacy responsibilities for the phase-8
dependency/ownership audit. This exception is not completion of the shared-service
or playback migration.

Addon retry mode and accepted-batch orchestration now belong to the existing
search controller (183 lines). Its synchronous mode decision keeps media-server
restart dispatch synchronous and ignores already-searching servers. Its guarded
retry action merges through the existing batch owner, then calls view-owned row
presentation and cache dispatch in the original continuation/order. No retry
result model, new state owner or presentation dependency was introduced.

The search controller now owns `prepareSearch`, the synchronous cache/retry/results
reset sequence before view-owned loading/focus reset and engine dispatch. The
existing three controllers retain their state and generations; no aggregate state
was added. The search/cache providers declare the dependencies needed for explicit
nested ownership. Tests verify reset order, retained toolbar/cache configuration,
retirement of old asynchronous work and isolation from parent results.

Row-menu classification and eligibility now use the injected plain
`data/source_row_action_policy.dart` (37 lines) and immutable
`models/source_row_actions.dart` (15 lines). A 17-line application factory supplies
media-server/IPTV classification and live profile download permission. The modal
captures that policy before opening and projects on each builder invocation,
retaining live permission checks without reading a disposed WidgetRef. The view
retains all dispatch and retirement guards. The sheet re-exports the moved kind
enum for compatibility; the search library no longer imports MediaServerService.

Initial settings/saved-source readiness now belongs to the stateless application
operation `source_startup.dart` (31 lines). It concurrently loads the existing
state owners and rejects retired profiles/scopes. The view retains its post-await
mounted/profile check and search dispatch, so priority and saved bindings still
precede the first engine request. No new state owner or automatic initialization
side effect was introduced. Nine startup tests cover load ordering, failures,
retirement and explicit nested scope ownership.

Completion-only season fallback and provider reconciliation now live in
`application/source_search_completion.dart` (46 lines). Its typed result tells
the view to keep/rebuild its projection or reject retired work; it never adopts
rows or owns focus. It uses pending results as the authoritative full set when
present, retains scoped-season menus, and preserves alias reconciliation.
Results/seasons providers now declare their existing dependencies for correct
nested scoping. The view's loading/cache/focus completion tail is unchanged.

Settings now declare their existing repository/session dependencies. With pinned
Riverpod 3.4.3, nested overrides must explicitly override both the settings
controller (family or session instance) and its repository. Tests exercise an
already initialized parent, two sibling scopes, concurrent reads/publications and
child disposal. Dependency metadata prevents explicit instance overrides from
changing the parent/sibling controller ownership. A repository-only override is
still insufficient when the parent instance already exists; the reproduction is
retained in local evidence. Production currently uses one app scope and distinct
view/session keys; no additional scope or state owner was introduced. The broader
phase 4C/8 scope audit must apply and verify explicit ownership for other families;
settings tests do not establish feature-wide isolation.

The retry controller now also declares its existing session-active dependency.
Two additional tests verify explicit controller-and-repository overrides for
both family and session-instance scopes, with an initialized parent and two
siblings. Same-key retries remain independent; disposing one child rejects its
late result without clearing the parent's or sibling's pending retry. The first
experiment overriding only the controller reproduced a surviving child retry
for an instance override; it is retained in local evidence and is not a supported
scoping recipe. Final verification: all 559 Sources tests pass, analyzer remains
at 863 existing diagnostics with no added identities, and 169 migrated files pass
architecture checks. Evidence: `.git/refactor-evidence/phase4c/retry-scope-*` and
`analyze-retry-scope-*`. This bounded dependency/test change did not rerun the
full suite; the latest full-suite checkpoint remains the provider-picker run.
The other families and native phase gates still require their own audit.

Cache and season scope retirement now has four regression cases covering an
initialized parent and two sibling scopes, with family and instance controller
overrides plus repository overrides. These exposed a real ownership gap: disposing
a child could still dispatch Premiumize or record season inventory. Both repository
families now declare `dependencies: const []`, so Riverpod 3.4.3 forks their scoped
directories instead of sharing the inherited directory. Their controller operation
logic is unchanged. Tests verify child retirement, independent badge/menu state,
and continued parent/sibling work. All 33 focused tests pass; analyzer identities
remain unchanged at 863 and 169 migrated files pass architecture checks.
The full repeat records 8,218 passes, the same 51 failures and 20 skips, preserving
every prior checkpoint outcome and adding six passes including the preceding
retry-scope tests. The first full run reproduced the known remote-transfer `.part`
cleanup failure at line 313; all 18 isolated transfer tests and the unchanged full
repeat pass that case. Evidence: `.git/refactor-evidence/phase4c/state-scopes-*`,
`analyze-state-scopes-*`, `full-state-scopes*`. The initial failing focused run was
interrupted while a wrongly surviving cache request waited for its fake response;
it is retained as failure evidence, not counted as a completed verification run.
Remaining ownership checks include results, saved/binding actions, search and
pending settings work; the earlier settings test disposes after child completion.

The subsequent pending-settings audit reproduced post-disposal reads for both
family and instance overrides. The settings repository family now also declares
`dependencies: const []`. Two new tests close a child with both settings branches
pending, reject a subsequent load before any IO, and let the original completions
settle while parent/sibling loads publish independently. The existing loaded-child
scope tests remain unchanged. All 565 Sources tests pass; analyzer diagnostic
identities match the immediate baseline (863) and architecture checks pass for
169 migrated files. Evidence: `.git/refactor-evidence/phase4c/settings-retirement-*`
and `analyze-settings-retirement-*`, including the two failing reproductions before
the declaration change. This follow-up used the Sources suite rather than another
full-suite run; the 8,218-pass full checkpoint above predates these two new tests.
Results, saved/binding actions, and search ownership checks remain outstanding.

Saved-source and binding scope retirement now has four additional regression
cases covering initialized parent and sibling containers with both override modes.
Before the fix, a disposed child's preparation guard stayed active and a completed
removal dispatched another saved-source read. Declaring `dependencies: const []`
on the saved-source repository family corrects scoped ownership without changing
binding, persistence, removal or reload logic. Tests retain the binding writer
across disposal, verify no late save/reload, reject subsequent retired actions,
and complete parent/sibling saves and publications independently. Accepted removals
still finish their originating repository operation; only the retired reload is
suppressed. All 569 Sources tests pass and all 863 analyzer diagnostic identities
match the immediate baseline. Architecture checks pass for 169 migrated files.
Evidence: `.git/refactor-evidence/phase4c/binding-scopes-*` and
`analyze-binding-scopes-*`, including four failing pre-fix reproductions. This
follow-up did not repeat the full suite; its latest checkpoint remains 8,218 passes
before the settings and binding scope additions. Results and search ownership
checks, broader boundary review and native phase gates remain outstanding.

Result-buffer scope retirement is now covered for initialized parent and two
siblings with the same session key. The instance-controller-only override still
accepted rows after disposal, including after adding session metadata alone.
The verified setup explicitly overrides both the results controller and session
ownership provider. The latter now declares `dependencies: const []`; removing
that declaration from the same test causes parent reads to re-enter the child
override through the shared family directory. Production session comparison and
profile listener attachment/disposal are unchanged. Both scope modes now reject
retired callbacks and preserve independent row buffers, freeze/selection, pending
adoption and resets. The test ownership override reads the parent's current value;
it does not replace production profile handoff or introduce a new production scope.
All 571 Sources tests pass; analyzer identities remain unchanged at 863 and all
169 migrated files pass architecture checks. Full suite: 8,226 passes, the same
51 failures/20 skips, no changed prior outcomes and eight new passes since the
previous full checkpoint. Evidence: `.git/refactor-evidence/phase4c/results-scopes-*`,
`analyze-results-scopes-*`, `full-results-scopes*`. The unsuccessful experiments
are retained; metadata alone is not a supported ownership recipe. Search
integration ownership, broader boundary review and native gates remain pending.

Search integration now has two parent/two-sibling ownership tests for family and
instance overrides, explicitly wiring search/cache/retry/results controllers,
their repositories and session ownership. Child preparation leaves the parent's
selected/frozen results untouched. Disposing a searching child closes its engine
continuation guard, rejects preparation and late rows/cache callbacks, and leaves
parent/sibling busy states and authoritative final responses independent. These
pass with the existing production code. All 573 Sources tests pass; analyzer
identities remain unchanged at 863 and architecture checks pass for 169 migrated
files. Evidence: `.git/refactor-evidence/phase4c/search-scopes-*` and
`analyze-search-scopes-*`. This test-only follow-up did not repeat the full suite;
the 8,226-pass checkpoint above precedes these two cases. The recorded explicit
scope recipes now have coverage across all eight Sources state controllers;
this does not promise repository-only automatic scoping. Broader legacy boundary
review and native phase gates remain pending before phase 4C can close.

Android local movie selection and series confirmation now live in
`presentation/android_local_source_dialogs.dart` (59 lines). Their widget trees,
autofocus, dimensions, labels and return values are unchanged. The legacy caller
retains sorting, acquisition, conversion and all mounted/session guards.
`models/local_source_document.dart` (44 lines) contains the unchanged shared model;
the Android service re-exports it for existing callers, while presentation imports
the model directly without a native-service dependency. The Android service's
remaining implementation is byte-identical (178→138 lines); the local binding
service shrinks 445→407 lines. Six widget tests cover order/identity, keyboard/tap,
Cancel/Back and series counts/confirmation. All 587 affected tests pass, including
573 existing Sources tests, six new dialog cases, six native-channel contract
tests and two root layout tests. Analyzer identities are unchanged at 863 and
171 migrated files pass architecture checks. Full suite: 8,234 passes, the same
51 failures/20 skips, all prior outcomes preserved with eight new passes including
the preceding search-scope tests. Evidence: `.git/refactor-evidence/phase4c/android-dialogs-*`,
`analyze-android-dialogs-*`, `full-android-dialogs*`. Native channel tests use mocks;
device checks remain pending. Local acquisition/platform dispatch, scan-loader
ownership and remaining filesystem/UI orchestration still require boundary review.

Android folder-scan progress now belongs to
`presentation/local_folder_scan_progress.dart` (40 lines), supplied with the
existing native scan callback. It preserves the optional entry/return guards,
non-dismissible dialog, original result/error behavior and `finally` removal of
the exact owned route. The legacy wrapper returns the helper future directly;
native URI/dispatch and caller sequencing are unchanged. The service shrinks
407→382 lines. Seven cases cover Back/result identity, failure cleanup, retired
entry, a covering route, already-removed progress, removed origin and disposed
navigator. The initial origin-removal fixture left an invalid empty Navigator;
adding its landing route fixed the fixture without a production change. All
586 Sources tests pass; analyzer identities are unchanged at 863 and 172 migrated
files pass architecture checks. Evidence: `.git/refactor-evidence/phase4c/local-scan-progress-*`
and `analyze-local-scan-progress-*`. This bounded extraction did not repeat the
full suite; the 8,234-pass checkpoint predates these seven cases. Native checks
and the remaining local acquisition/filesystem/UI boundary remain pending.

Android document picking now has a stateless presentation owner in
`presentation/android_local_source_picker.dart` (148 lines). Its four injected
operations are native pick, native scan, video eligibility and episode count;
there is no native-service import or new state owner. The compatibility service
wires the existing operations and retains platform dispatch; it shrinks from
382 to 285 lines. Movie/series guards, sorting, progress/dialog sequencing, error
feedback and descriptor conversion timing are preserved. `LocalSourceUnavailable`
moves unchanged into the shared document model and remains re-exported by the
Android service. Eighteen widget tests cover cancellation, retired entry, invalid
files, opaque bindings, folder sorting, empty results, series confirmation,
retirement during pick/scan/choice and both native failure types. Two initial
finder failures came from identical fixture title/subtitle text; distinct relative
paths corrected the fixture without a production change. All 612 affected tests
pass (604 Sources, six channel-contract and two root layout tests); analyzer
identities remain unchanged at 863 and 173 files pass architecture checks.
Full repeat: 8,259 passes, the same 51 failures/20 skips, no changed prior outcomes
and 25 new passes including the preceding progress extraction. The first full run
reproduced the known transfer `.part` cleanup failure; all 18 isolated transfer
tests and the unchanged full repeat pass. Evidence:
`.git/refactor-evidence/phase4c/android-picker-*`, `analyze-android-picker-*`,
`full-android-picker*`. Desktop picker/filesystem orchestration, compatibility
composition retirement and native device checks remain pending.

Desktop file selection now uses the 38-line data adapter
`data/local_source_file_picker.dart`; series-folder stat and descriptor creation
join the existing filesystem operations in `local_source_files.dart` (193 lines).
Native picker options and extension order, result guards, cancellation, actual file
metadata, folder paths/URIs/name fallback and legacy episode-count size semantics
are preserved. Stat failures still propagate after retirement. The UI retains
episode validation/messages and platform dispatch; its compatibility service
shrinks 285→250 lines. Five metadata tests cover real fields, fallback, retirement
and errors. The full suite then passed comparison at 8,264 successes, unchanged
51 failures/20 skips, with every prior outcome preserved. Review identified missing
single-file option coverage in the folder-focused integration tests; five direct
adapter cases were added afterward, with no further production edits. Final
targeted verification passes 616 tests (614 Sources and two root layout cases),
with unchanged 863 analyzer identities and 174 files passing architecture checks.
The full checkpoint predates only those five added tests. Evidence:
`.git/refactor-evidence/phase4c/local-series-binding-*`, `desktop-file-io-*`,
`analyze-local-series-binding-*`, `analyze-desktop-file-io-*`, `full-desktop-file-io*`.
Desktop folder-resolution/UI orchestration and native device checks remain pending.

Series-folder resolution now separates filesystem lookup from presentation.
`lookupLocalSeriesFolders` returns a typed direct match or immutable candidate
list, with null for unavailable/retired lookups. The 41-line
`presentation/local_series_folder_resolution.dart` owns single-match acceptance,
help and multiple-choice presentation, and rechecks ownership after the new await
boundary. Existing direct-root priority, ordered direct children, missing-folder
behavior, labels and selection guards are preserved. Production calls use these
components and the old resolver is removed; the compatibility service shrinks
250→208 lines. Five data and eight presentation tests cover the decision paths
and retirement. Initial empty-list record inference produced four compiler
diagnostics; explicit candidate element types resolved them without changing the
behavior. All 627 Sources tests pass, analyzer identities remain unchanged at 863,
and architecture checks pass for 175 migrated files. Full suite: 8,282 passes,
unchanged 51 failures/20 skips, no changed prior outcomes and 18 new passes including
the five preceding single-file tests. Evidence:
`.git/refactor-evidence/phase4c/series-folder-lookup-*`, `analyze-series-folder-lookup-*`,
`full-series-folder-lookup*`. Local picker composition/presentation consolidation,
native checks and the remaining phase gates are still pending.

Desktop folder picker presentation now lives in the 69-line
`presentation/desktop_local_source_picker.dart`. Its movie/series functions receive
ordinary picker, scan, match/resolve and descriptor callbacks; they perform no file
IO and own no persistent state. Production wiring replaces the old UI orchestration,
shrinking the compatibility service from 208 to 174 lines. Review preserves await
and decision ordering, automatic-match and manual-choice identity, folder paths,
episode counts, original empty-folder feedback, error propagation and optional
legacy ownership semantics. The new independently callable functions also reject
retired guarded entry before IO. Twelve boundary tests cover cancellation/blank
paths, empty inventories, match/choice, resolved series paths/counts and retirement;
existing production picker integration and layout tests pass alongside them.
Verification: 641 affected tests (639 Sources plus two root layout cases), unchanged
863 analyzer identities, and 176 migrated files passing architecture checks. Full
suite: 8,294 successes, unchanged 51 failures/20 skips, every prior checkpoint
outcome preserved and exactly 12 new successes. Evidence:
`.git/refactor-evidence/phase4c/desktop-picker-*`, `analyze-desktop-picker-*`,
`full-desktop-picker*`. Native desktop success/cancellation checks remain pending;
this host verification does not extend the preceding Android TV evidence. Remaining
local picker platform/UI composition must leave the legacy service through a named
presentation boundary before phase 4C's UI separation can close.

Native checkpoint (2026-09-27): the full production Android debug APK builds
successfully with the pinned SDK. A separate blank Android TV/API 34 arm64 AVD
(`codex_sources_refactor_tv`, 1920×1080) exercised the production local picker
entry points through a temporary harness and real MainActivity/native channel.
The local service from `4ea552dc`, before the recent picker extractions, ran in
the same harness/environment for a controlled comparison. Eleven captured native
hierarchy/focus states match, including movie-mode D-pad selection, Back, native
file/folder cancellation and movie/series origin-focus restoration. Both variants
issued one file and two folder native intents and returned the same four
no-selection results. This image resolves document selection to Android TV's
`DocumentsStub`; successful document selection, scanning and persistence remain
unverified on a real document-provider target. Screenshot capture failed, so this
does not establish rendered visual parity, full Sources/player lifecycle parity
or performance. Existing AVDs/user profiles were untouched; the isolated emulator
is stopped and standard build APK outputs restored. Evidence, harnesses, hashes,
logs, XML comparison and exact limitations are in
`.git/refactor-evidence/phase4c/native/` and `native-android-debug-build.txt`.
This narrows the native gap but does not close phase 4C or the later native gates.

Local picker mode/availability presentation now uses the stateless 101-line
`presentation/local_source_picker.dart`. Its 82-line composition factory wires the
existing Android and desktop operations, centralizes OS checks and retains no
request, profile or widget state. The architecture guard permits the native import
only at that named factory. The existing `LocalBoundSourceService` is now a 45-line
compatibility forwarder: its UI, OS dispatch and native wiring bodies are removed;
its public model export and caller-owned episode-list contract remain unchanged.
The forwarding facade still carries context for legacy catalog/playback callers;
its retirement/caller migration remains part of the later boundary audit. This is
not a new data-service owner or DI framework; Sources retains its existing Riverpod
binding bridge and guarded writer.

Twelve presentation tests cover unsupported feedback, retired entry/mode choices,
Android/desktop wording, movie file/folder dispatch, input/guard identity, Escape
and direct series dispatch. Initial four fixture failures came from assertions
inside a pending tap callback; assertions now inspect captured inputs afterward.
Final affected verification passes 653 tests (651 Sources plus two root layout
cases), with 178 migrated files passing architecture checks. An analyzer run
concurrent with the Android build emitted 45 duplicate occurrences of existing
diagnostics; the unchanged settled run and final run both match all 863 baseline
identities. Raw runs remain in evidence.

Native review caught a completion-order difference that host tests did not detect:
three harness status-label bounds differed after movie cancellation, even after
settled baseline captures. Extraction had removed the existing asynchronous
file/folder dispatch wrapper. Restoring that boundary and its entry guard in
`_pickMovieSelection` restores all 11 native hierarchy/focus/geometry snapshots
against the settled baseline, with identical one-file/two-folder intent counts
and four cancellations. No native or picker UI behavior was otherwise changed.
The corrected production Android debug APK builds successfully; standard build
outputs are the full app. The isolated TV emulator is stopped. DocumentsStub,
actual selection/persistence, rendered visual/performance and whole-screen native
limitations from the preceding checkpoint still apply.

Final full-suite comparison after the completion-order correction: 8,306 successes,
unchanged 51 failures/20 skips, every prior checkpoint outcome preserved and exactly
12 new successes. Evidence: `.git/refactor-evidence/phase4c/local-picker-composition-*`,
`analyze-local-picker-composition-*`, `full-local-picker-composition*`, and
`native/composition-*` (including original differing captures and final comparison).
Phase 4C and the full migration remain open; native successful document selection,
remaining binding/preparation boundaries and later feature/lifecycle gates are not
satisfied by this checkpoint.

Successful Android document-selection checkpoint (2026-09-27, production
`acd10111`): a separate blank Pixel 6/API 34 arm64 AVD uses real DocumentsUI and
the external-storage document provider. Current and pre-extraction (`4ea552dc`
local service) harnesses were built with the same pinned SDK/native code. Five
synthetic videos exercise direct movie selection, a two-episode series folder,
and an alphabetically ordered movie-folder choice. Both variants select the same
sources and resolve episode 2 at index 1. After two force-stop/relaunch cycles
(three app processes per variant), direct movie, series and folder-movie access
still resolve correctly. Android reports three corresponding persisted read-only
URI grants in each variant.

All nine result events match, comparing every source/metadata field, file timestamp,
URI, size, ordered playlist entry and start index; only `boundAt`, the action-time
timestamp, is excluded. All 13 captured app hierarchy/focus/geometry states match,
with identical one-file/two-folder native picker intent counts. The harness saves
source JSON in its own fixture preferences, so this establishes persisted native
URI access, not full Sources repository/profile-write integration. Screenshot
capture returned an empty image; no pixel parity is claimed. Actual player rendering,
full-screen lifecycle, desktop native pickers and profile/release performance remain
pending. The TV image's DocumentsStub restriction is unchanged, but successful
selection is now verified on a real phone document-provider target.

Evidence, harnesses, fixture videos, build hashes, process logs, permission records,
XML comparison and review are in `.git/refactor-evidence/phase4c/native/phone/`.
Only the newly created test app/AVD was reset; existing AVDs/profiles were untouched.
The emulator is stopped and standard build outputs byte-match the preserved full
production APK. No application/native/dependency source changed; the prior 8,306-pass
full-suite/analyzer checkpoint remains the automated baseline. Phase 4C and later
feature/lifecycle/completion gates remain open.

Sources local-binding composition now uses Riverpod directly. The 89-line local
picker factory exposes `localSourcePickerProvider` with an explicit scopeable leaf
dependency declaration; `sourceBindingBridgeProvider` declares and consumes it.
The 96-line bridge reads availability from that injected picker and calls
`presentLocalSourceBinding` with the existing guarded writer. Sources local actions
no longer dispatch through `TorrentPlaybackService.bindLocalSource` or its global
availability getter. Other legacy catalog/playback callers retain their forwarding
entry points; direct/IPTV/debrid binding paths still use their recorded bridge.

The app-lifetime picker remains stateless; no profile/request state, extra DI system
or global container is introduced. The default bridge constructor remains compatible
with existing direct callers. The old compatibility writer's asynchronous completion
boundary is retained as an async callback, while SourceBindingController still owns
busy state, accepted writes, profile/view retirement and reloads.

Nine new tests exercise production provider wiring for movie file/folder and series
selection, descriptor/context/guard identity, parent/two-child scope isolation,
disabled availability/feedback, retirement before/during picking, missing identity
and rejected writes. All 660 Sources tests pass, including existing real-file picker
and profile-retirement integration cases. One test-only function-declaration lint
was corrected; final analyzer identities match the 863-entry baseline exactly.
All 178 migrated files pass architecture checks. Full suite: 8,315 successes,
unchanged 51 failures/20 skips, all prior outcomes preserved and nine new successes.
Evidence: `.git/refactor-evidence/phase4c/local-binding-di-*`,
`analyze-local-binding-di-*`, `full-local-binding-di*`. Native picker/file operations
and their verified completion ordering are unchanged; the earlier phone/TV evidence
covers those operations, not a new full Sources-screen native test. Remaining
binding/preparation, compatibility retirement and later phase gates stay open.

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

The shared filter matcher now has a reviewed pure dependency graph: quality
classification lives in `lib/utils/torrent_quality.dart` (32 lines), and language
mapping lives in `lib/utils/language_mapping.dart` (464 normally formatted lines,
one cohesive language-normalization/mapping responsibility). The row widget and
old player language path re-export their declarations for compatibility. The
matcher, source-quality/format-tag helpers, both extracted policies and the
language compatibility facade are measured by the migration guard; registered
shared utilities now receive data-layer import checks. The recursive matcher
graph reaches only these utilities, Torrent/filter models, dart:collection and
Flutter foundation. Provider ordering is now separated into
`lib/services/source_ordering.dart` (193 lines), depending only on Torrent and the
17-line shared SourceProviderRef model. Five Sources application consumers use it
directly. The retained SourcePriority facade (144 lines) delegates pure methods
and keeps provider/alias loading unchanged behind the settings repository. The
recursive policy graph contains no UI, platform, DI or loading-service dependency.
Registered shared services now receive the same data-layer import checks as shared
utilities. Remaining feature/legacy integration boundaries still need the phase-8
audit; these policy checks do not establish whole-feature completion. The pinned direct-stream selector is now
separated into `lib/services/pinned_direct_stream_match.dart` (34 lines, imports
only Torrent), used directly by Sources selection/result preparation. The legacy
Stremio API delegates to it for playback compatibility. Selected-source matching
also receives IPTV ownership from the existing injected binding matcher, so it
no longer imports either transport service. The
`SeriesSource` model exception is closed: it now lives in
`lib/models/series_source.dart`, registered in the migration guard, with only pure
model/hash dependencies. The service re-exports it for legacy caller compatibility. The merge-policy dependency is now separated: Sources calls the 60-line pure
`lib/services/torrent_result_merge.dart`, registered in the measured source set.
`TorrentService.mergeSearchResults` retains the legacy diagnostic and delegates
for compatibility. The retained `lib/services/torrent_service.dart` (1,053 lines)
still owns pre-existing engine configuration/network orchestration outside this
policy extraction; its injected repository boundary remains subject to phase-8
review. This change does not close other transitive service dependencies, including
the service-backed classifiers and selectors listed above.

| Phase | Status | Revision, checks, and remaining work |
| --- | --- | --- |
| 0: Baseline | Automated baseline reviewed; device checks pending | `aa3d5643`: 7,387 pass / 51 fail / 20 skipped; 865 analyzer diagnostics; ownership/behavior inventory recorded in implementation evidence |
| 1: Keyword policies | Complete; reviewed | Sorting (`bd0c214e`), filtering and provider reconciliation wired; 32 new policy tests; final affected run 129 pass and the same two baseline suggestion failures; no new analyzer identities |
| 2: Leaf presentation | Complete; reviewed | Category/See All (`146466b5`) and mode controls extracted; eight new widget tests; final affected run 29 pass / same three baseline failures, analyzer unchanged; complex cards/layouts remain phases 6–7 |
| 3: Lists/suggestions | Implemented and reviewed | Riverpod 3.4.3 and Lists controller wired; 23 new tests pass; full suite 7,450 pass / same 51 baseline failures / 20 skipped, no missing tests, analyzer unchanged; device checks pending |
| 4A: Catalog search | Implemented and reviewed | Riverpod state, streaming/TV batching, source settings and dialog wired; 35 new tests pass; affected suite retains the same three baseline failures, analyzer unchanged; device checks pending |
| 4B: Keyword search | Implemented and reviewed | Application/data state, settings/defaults, selection and snapshot ownership wired; full suite 7,600 pass / same 51 failures / 20 skips, analyzer unchanged. Focus/navigation wrappers remain in the registered legacy screen (20,138 lines) for later presentation/bridge phases; device checks pending |
| 4C: Source selection | In progress | Season policies, guide state/inventory, startup settings, saved-source loading, cache checks, initial requests, individual addon retries, toolbar projection, streamed-result preparation search state/batch orchestration, and adopted/pending result ownership and toolbar state/reconciliation and guarded unpin persistence extracted; shared binding model separated from storage; shared pin/local action gate and reload orchestration extracted; manual Sources bindings now use guarded repository persistence. Row-action sheets extracted with captured theme and guarded modal dispatch; pending-results pill extracted with borrowed focus and explicit navigation callbacks. Title/keyword headers extracted with existing render/input contracts. Active-filter summary and label helpers extracted. Season/sort/filter controls extracted with lazy menu values and view-owned focus dispatch. Provider strip extracted behind immutable display options; real narrow-screen selection/retry wiring verified. Shared source-row metadata labels extracted and Keyword callers updated without changing its distinct subtitle fallback. Provider-strip projection extracted into a pure operation with immutable results. Cinema provider summaries and server messages extracted; shared provider model separated from its widget with a compatibility export. Results pane extracted with borrowed controller and drag-only freeze dispatch. Status presentation extracted with existing visibility and theme contracts. Primary saved-source matching extracted with row identity and diagnostics preserved. Lazy row reveal extracted into a presentation helper with live view cancellation checks and borrowed nodes/controller. Manual picker calls now go through an injected presentation bridge requiring the guarded writer and live action check. Retired actions stop at outer preparation/picker boundaries; active remember-choice behavior is retained. Remember-choice writes now recheck action ownership after the preference mutation barrier and ignore foreign captured scopes. Sequential provider-availability/default loading now uses a plain data helper with injected readers and retirement checks between reads. Manual configuration credential reads now carry the action guard through profile routing and legacy sealing, including migration writes waiting on the preference barrier. Manual acquisition now forwards the action guard into the four API-key reads and checks each top-level provider response before continuing. PikPak preparation now uses an injected plain data operation with immutable video descriptors, preserving polling/listing behavior and stopping retired manual actions between waits and requests. The manual binding loader now owns its exact route, preserving newer routes when the action or launching view retires. Bind-mode completion likewise closes only its captured picker route after a successful, current save/reload. Local desktop filesystem scanning, matching and file metadata now use plain Sources data operations and immutable descriptors; the old implementations were removed and the legacy episode API remains compatible. Local movie mode, candidate choices and folder guidance are now standalone presentation functions with typed inputs; their legacy bodies were removed. Local binding now forwards the live action check through picker, filesystem and follow-up modal awaits, rejecting retired continuations while preserving unguarded callers. Copy eligibility, deferred episode resolution and clipboard sequencing now use an injected stateless operation; the view retains messages and supplies originating-profile/view ownership. Playback and direct-stream downloads now use an injected presentation bridge, retaining visible-list/index handoff, force-play intent, tap suppression and post-completion reload. Modal actions now reject retired views/profiles before dependency/context access; row-menu copy dependencies and filter-dialog opening values survive modal rebuilds independently of the original view. The shared filter header is extracted with borrowed focus/live Clear eligibility; its constrained title fixes narrow/scaled-text overflow, and the original 500-pixel modal fixture passes again. Row-node construction/replacement/disposal now has a view-owned presentation helper with a read-only live list; a reproduced multi-row shrink fallback flaw is corrected without moving the view’s selection/anchor policies. Detail/picker result-row composition is now a standalone presentation function with explicit display inputs and borrowed callbacks, preserving the existing widget tree. Compact/cinema frame composition is extracted with typed display inputs and unchanged view-owned focus callbacks; normal/picker resize roundtrips retain nodes and make no new requests. Loading/error/results-body composition is extracted with lazy optional content, borrowed resources and unchanged row actions. Toolbar grouping is extracted with unchanged control/action callbacks and pure ordered provider-warning projection. Row-to-saved-binding rules now use an injected stateless matcher; primary-selection media identity lookup also uses that adapter. Reveal generations, remembered cinema row and deferred streaming/completion anchors now have one presentation coordinator with borrowed resources and live guards. Picker diagnostic emission uses a captured injected callback and the existing logging service; no direct DiagnosticLog dependency remains in the search library. Batch preparation now has a stateless application owner for live scoped inputs; saved-source/binding dependency declarations preserve nested scope isolation. Final season fallback/provider reconciliation now uses a stateless application operation with a typed projection outcome and scoped dependencies. Play/copy/pin/unpin and row-menu presentation now use a view-owned 222-line SourceActions with live inputs and unchanged controller/bridge boundaries. Directional row/pill/filter focus now shares the existing 201-line presentation coordinator, preserving classic/TV/touch behavior. Toolbar composition and filter-dialog dispatch now use a 141-line presentation helper with the existing scoped state/controllers and live guards. An 85-line per-view trace helper now owns diagnostic snapshots at the original subscription-close points. Rendered projection, selected/cached markers and focus-transition ordering now use one 282-line presentation coordinator, with the existing Riverpod state and borrowed view resources. The production SourcesScreen is now a standalone 678-line feature view; a captured application ownership reader preserves live lifecycle checks. The test-only factory now lives under `test/features/sources/fixtures/`, with all callers migrated and no production repository wiring retained for it. Manual and automatic binding descriptor construction now delegates to an 85-line pure shared policy, retaining the existing classifiers and timestamp/mapping at the legacy boundary. Manual direct-pin guards and feedback now live in a 50-line presentation function supplied with the existing authorization/descriptor/save operations by its compatibility wrapper. Manual IPTV-pin presentation and diagnostic outcome sequencing now live in a 98-line function with injected data operations and the existing sink. Local-pin presentation now uses a 33-line function with the existing picker/writer callbacks, preserving native acquisition and guards. Debrid pin UI sequencing now uses a 65-line presentation function with an owned loader callback and typed readiness result; provider cleanup remains in the unchanged acquisition block. Shared provider-picker orchestration now uses a 37-line presentation function preserving default/single-provider fast paths, dialog options and remembered-write semantics for manual and automatic callers. Latest slice: cache/season repository scope declarations now prevent child work surviving disposal; settings, saved/binding and explicit results retirement are also verified and all 660 Sources tests pass and no new analyzer diagnostics; the results-pane slice removed one legacy deprecation. Shape-manifest location follow-up preserves its 490-call threshold. Latest full suite: 8,315 successes, same 51 failures/20 skips, all prior checkpoint outcomes preserved; the first local-retirement run had an additional profile identity-save failure that passed independently and in the unchanged repeat full run, retained in evidence alongside the transfer cleanup timing failure, which recurred on the first playback-bridge run and passed in its unchanged full repeat. Legacy binding UI/data boundaries, remaining boundary and native verification remain; standalone Sources view 678 lines; the former Sources part was removed in phase 6 after its remaining Discover visuals became standalone widgets |
| 5: Home data | In progress | Preferences, collection access/configuration policy, catalog planning/batch access, scoped inventory/cursor/loading/generation/configuration ownership and initial-load orchestration are extracted. Horizontal page fetching uses the injected catalog repository; accepted rows and paging mutations now belong to the existing controller with revision notifications and detached return snapshots. Local Continue Watching now reads a typed snapshot through an injected repository and owns accepted state/requests in a scoped Riverpod controller with request/profile retirement checks. IPTV continuation now has an injected UI-independent history reader and scoped state/controller, with legacy routing retained for phase 7. Shared continuation layout preferences now use an injected repository and scoped controller while the view retains focus reconciliation. Trakt projection and reads are separated, and a scoped controller now owns accepted rows/loading/request retirement and attempt time; live read-only progress preserves See-All behavior. Playback remains to migrate. Simkl now uses a scoped controller and injected typed reader, retaining live grid progress; playback/removal remain. MDBList projection, injected invalidation/fetch access and scoped accepted state are separated; delayed revision orchestration now belongs to the same scoped controller, and removal uses the injected repository with guarded UI feedback. Late scrobble/clear profile acceptance is now guarded and tested; remaining service operations and playback still require their audits. Debrify TV favourites reads and accepted state now use a scoped controller/repository with preserved focus behavior. Stremio TV favourites now use an injected repository, scoped accepted snapshots and controller-owned rotation selection; the shared context-free service is relocated with a compatibility export. IPTV favourites now use an injected live-only projection and scoped accepted state, with stale-request retirement and unchanged list-refresh/focus triggers. IPTV custom lists now use complete immutable snapshots and scoped state, with a view-owned focus coordinator retaining nodes by list identity; the old mutable part-file row class is removed. Local watchlist reads/grouping now use a directly injected typed reader and scoped immutable membership; movie/series focus recovery remains view-owned. Playlist reads/order/posters/progress now use an injected repository and scoped typed snapshot, with a detached legacy payload at the action boundary. Latest expanded Home/continuation/MDBList/profile/Stremio TV run: 799 successes / unchanged 12 failures / one skip; analyzer identities unchanged at 863. Vertical page fetch/commit/merge now belongs to the catalog controller; covered-route publication and frame coalescing use a view-owned coordinator. The latest publication-focused run passes 79 tests. Display preference reads and accepted state now share an injected repository and scoped controller, preserving cached first-frame values and rejecting retired reads. Configuration refresh reads, comparison and acceptance now use a bounded operation with the existing catalog state owner; the latest focused run passes 54 tests. Default-view preference reads and policy selection now use a scoped, disposable operation with no competing active-mode state; TV and cached-keyword behavior are covered. Trailer preferences now use an injected parallel reader and scoped accepted values while the view retains scheduling/stopping; the latest focused run passes 46 tests. Source appearance now shares a captured-profile reader across Sources and keyword results, with scoped keyword state; the latest focused run passes 38 tests. Layout preference reads now use an injected scoped operation while the view retains its ordered preview teardown and transition; the latest focused run passes 51 tests. Settings-refresh coordination now belongs to a scoped operation with ownership captured before its first await; the latest focused run passes 56 tests. Pinned-source badge scans now use a guarded repository and scoped immutable counts; the latest focused run passes 73 tests. PikPak-only eligibility now uses guarded injected credential reads and scoped boolean state; the latest focused run passes 58 tests. Home return snapshots now use an injected owner-bound repository borrowing one process cache and listener pair; 46 focused tests include stable registry counts across repeated real visits. Tracker authentication now uses independently scoped state and injected existing service policies; the expanded focused run passes 64 tests, including the real Lists disconnect race. Episode-artwork snapshots and metadata-refresh batches now use a scoped controller and bounded injected repository; all 33 focused tests pass, including current-image acceptance through the actual Home card. Remaining data/action and presentation responsibilities and device/performance gates remain. Detailed checkpoint evidence is recorded in phase 5 above. |
| 6: Discover/layouts | In progress | Shared discovery-feature policy/readiness now uses scoped state and the existing injected preference service. Expanded focused checks: 42 successes and the same two baseline suggestion failures; a real Discover race test preserves TMDB disable fallback. Source selection and startup hydration now use a scoped controller with injected preference/addon access and guarded remembered-source writes; all 34 focused tests pass, including actual delayed-inventory UI behavior and preference-barrier retirement. The two-pane Discover composition and its backdrop/veil/dimming widgets are extracted, removing the old Sources part; 38 focused checks pass with the same pre-existing shape-manifest failure. Stage composition is also extracted with preserved shelf/identity geometry and theater transitions; all 40 focused tests pass, including both real Discover resize paths. Caption overflow now has the separately verified line-height fix; favourites art and directional navigation are extracted. Catalog-card metadata now has scoped Riverpod ownership, an injected repository and the shared hero/cache boundary; its expanded tests pass 117 checks. The catalog card and its collection/favourites row models are now standalone, removing the card part; 136 existing checks and six new direct tests pass. All seven board cells now use a standalone navigation wrapper with explicit live sidebar dispatch; 68 focused checks pass. Classic lazy rows and one-shot entrances are extracted; 78 existing passes and ten existing failures are unchanged, and six new tests pass. Trailer dim/recede presentation now uses explicit borrowed signals; 45 existing and five new transition checks pass. The informational takeover overlay is standalone, with unchanged metadata precedence and staged animation; 45 existing and four new checks pass. Classic geometry/surface composition is now standalone; 65 existing and four new layout checks pass. Tonight card captions and their shared display dependencies are extracted; 88 existing and seven new policy/widget checks pass. The Continue Watching queue row and shared wide-art policy are extracted; 45 existing and ten new checks pass. Shared stage artwork is now standalone across all six callers, with its bounded failure memo isolated as a plain policy; 37 existing and six new checks pass. Shared stage shading and its three variants are standalone; 31 existing and four new transition checks pass. Shared stage title/metadata identity and its four variants are standalone with shared layout dimensions; 43 existing and eight new checks pass. Shared row/rail presentation contracts are standalone with borrowed resource ownership retained; all 66 affected screen checks pass. Trakt loading rows and favourite identities are standalone (47 and 58 affected checks pass); the corner painter is extracted with two raster checks, retiring the stage part. The final hero part was subsequently retired in phase 7. Canvas geometry and theater composition are standalone with preserved native/row ownership; 47 existing and four new layout checks pass. Canvas lazy shelf presentation is standalone while its card actions remain caller-owned; 41 existing and four new list/focus checks pass, removing two legacy cache deprecations. Canvas rail-tab display and shared height metrics are standalone; 49 existing and seven new checks pass with navigation still caller-owned. Promenade composition and centered strip are standalone with conditional native/cell ownership preserved; four new host layout checks pass. Shared Promenade/Mosaic rail labels are standalone; 42 existing and four new display checks pass. Atrium split-panel composition is standalone; 43 existing and three new geometry/focus/surface checks pass. Mosaic geometry and grid composition are standalone with shared navigation dimensions; 43 existing and eight new checks pass. Deck card geometry and composition are standalone with original native/peek/cell ownership; 41 existing and six new checks pass. Deck static preview cards are standalone; 40 existing and three new checks pass. Shared Deck/Tonight row labels are standalone with preserved Atrium metrics; 41 existing and three new checks pass. Tonight geometry and lazy zone/card composition are standalone; 44 existing and nine new checks pass. Tonight header/height are standalone; 43 existing and three new checks pass. Tonight lazy queue composition is standalone with caller-owned row actions; 48 existing and three new checks pass. Stage hold-key suppression has one per-view presentation owner at unchanged lifecycle/reset points; 59 affected checks pass, including the real Mosaic hold flow. Deferred stage focus requests now share a per-view generation owner; 58 existing and six new checks pass. Tonight horizontal rail composition is standalone; 44 existing and three new checks pass. Shared Home layout policy is independent of Settings UI; 37 existing and two new checks pass. Deferred Right navigation has one per-view presentation owner; 39 focused checks and two before/after Mosaic screen cases pass. Deferred Down waiting/validation has one per-view owner; all 33 affected checks pass, including all eight layout flows. Atrium row presentation is standalone; 32 existing and three new checks pass. Discover source-selector presentation is standalone with unchanged gates, ordering and borrowed focus; all 39 affected checks pass. Discover preview signals, theater dwell and ordered resets now have one local presentation owner; all 30 affected checks pass, including expanded grid/stage resize and activity timing parity. Discover layout preferences now use scoped Riverpod state and an injected captured-scope reader with guarded shared-cache publication; all 37 affected checks pass, including real-screen refresh ordering and startup-race rejection. Discover card flags now use scoped Riverpod snapshots and an injected warmed-cache reader; real Discover refresh and fresh Home expansion checks pass. Discover canvas assembly is now a standalone 178-line composition with borrowed panel/signals; 128 baseline and six new behavior checks pass. Discover source-panel selection now uses a lazy factory with unchanged constructor/action contracts; 102 baseline and six new selection checks pass. Home favourites-row composition is standalone across all six callers; 59 baseline and three new interaction checks pass, with one deprecated cache-setting diagnostic removed. Catalog-row headers and shared title metrics are standalone; all 66 passing baseline cases and five new header checks pass, with the same twelve pre-existing collection errors. Classic catalog-row layout and scroll paging are standalone with the original lazy cell builder; 64 baseline and two new interaction checks pass, removing one deprecated cache-setting diagnostic. Continue Watching row/card composition is standalone with borrowed live descriptors and caller-owned menu/navigation actions; 58 baseline and two touch/TV checks pass, removing one deprecated cache-setting diagnostic. Classic row sizing, hero budgets and anchor measurement now share one feature module; all 46 baseline and seven new measurement checks pass, retaining the original text contexts and hidden-header shortcut. Catalog continuation footer presentation is standalone with borrowed focus nodes and existing paging owners; 25 baseline and three new interaction checks pass. Manual catalog continuation now has one scoped Riverpod busy/cursor owner with sequential four-row batches; 40 affected checks pass, including before/after real Home focus and exhaustion parity. Shared layout navigation/action boundaries, remaining preview/lifecycle work, and device/performance checks remain. |
| 7: Hero/handoff/lifecycle | In progress | Hero metadata selection/retention is a pure policy and the duplicate logo derivation is retired; 47 existing and seven new checks pass. Asynchronous hero enrichment now has a per-view Riverpod-owned loader and injected services; all 84 affected checks pass. Hero trailer resolution uses an injected stateless service boundary; 64 focused checks and two real Home retirement cases pass. Trailer dwell/request/failsafe timing has one per-view Riverpod owner; all 64 affected checks pass. Preview suppression/attempt intent is a per-view presentation policy; 35 focused checks and a before/after Spotlight launch scenario pass. Live-preview candidate requests/fallback now have a per-view Riverpod owner and injected service boundary; all 56 affected checks pass. Live-preview surface/shared geometry are standalone across all seven callers; 52 affected checks pass with the same existing shape-manifest failure. Trailer surface/status presentation and the search button are standalone with a shared data-only stream model; 52 affected checks pass with the same existing shape-manifest failure. Spotlight card live-preview resolution/fallback now has independent Riverpod ownership behind the shared injected repository; all 108 affected checks pass. The hero now reuses the scoped card-metadata boundary instead of the service-backed mixin; 69 baseline and two real-Home scenarios pass, removing two obsolete override diagnostics. Hero presentation is standalone in bounded components, retiring the final part; 46 baseline checks and six new presentation cases pass with the same existing shape-manifest failure. Title failure memory now uses the existing 512-entry bound, with all eight affected checks passing. Hero focus-rest timing now has one per-view presentation owner; 62 affected checks pass, including a before/after 260ms and focus-jiggle scenario. Hero tint debounce/cache now has one per-view Riverpod owner and injected shared resolver; 81 affected checks pass, including twelve new timing, retirement and real-screen publication cases. TV Home shell registrations now have one presentation bridge with ordered detachment and conditional post-frame resets; 66 affected checks pass, including regular/low-memory screen parity. Home stage theater timing/state now have one local presentation owner; 81 affected checks pass, including before/after five-second dwell, key wake and retained shelf focus. Post-playback latch/refresh sequencing now uses a scoped Riverpod controller with preserved overlap and scrobble behavior; 55 affected checks pass, including a before/after real Home playback case. Classic hero composition is standalone with live configuration reads and borrowed signals; metadata fallback, listener lifetime and retained hero state checks pass. Random episode candidate/launch selection now uses an injected stateless raw-metadata boundary; all 28 affected policy/dialog/launch checks pass with custom progress identity preserved. Random metadata preparation now uses a captured-profile injected repository with guarded inventory commits and explicit outcomes; all 54 affected checks pass, including actual persistence-barrier and scoped-write verification. Random dialog/message/launch dispatch now uses a named presentation bridge with lazy preparation and unchanged handoff arguments; all 43 affected checks pass. Catalog episode identity now resolves through a captured-profile injected boundary before play/source dispatch; all 39 affected checks pass, preserving custom unresolved identities and retiring stale actions. Detail opening and catalog play now share captured-profile identity/addon preparation, with guarded progress-mapping and inventory writes; all 52 affected checks pass, including actual preference-barrier and metadata-retirement verification. The three catalog/resume tracking-policy loads now use injected captured-profile reads with guarded migration/fallback writes; 143 affected checks pass, including held commits and a between-writes snapshot race. Unavailable-origin confirmation is standalone with an originating view/profile return guard; all 37 affected checks pass, including real Home history persistence and prior-implementation parity. The accepted local deletion workflow now uses captured-profile writes and a lifecycle drain; host tests cover real preferences/recovery records and scoped tombstone callbacks. Device acceptance remains pending. Tracker movie-position readers and shared MDBList candidate lookup now use a per-view/profile injected repository with the original Trakt TTL and caller timeouts; 97 affected checks pass, including production transport and late-response retirement. The Trakt memo capacity exception is separately closed with a 512-entry recency bound and 28 passing reader/capacity checks. Playback artwork has one per-view presentation owner across capture, detail enrichment and loader/metadata consumers; 42 affected checks and nine direct old/new parity cases pass. Catalog movie selections and player metadata now use stateless typed factories with explicit addon/artwork inputs; 51 affected checks and seven direct old/new parity cases pass. Catalog player handoff now uses a named injected presentation bridge with per-action listener cleanup and preserved immediate/deferred refresh rules; 37 affected checks and six direct old/new parity cases pass. Home Sources browse/Play, bind and keyword route creation now share a stateless injected presentation boundary preserving metadata/TV-mode timing and refresh ownership; 34 affected checks and six direct old/new parity cases pass, including four real Sources destinations. Series-resume ranking and episode advancement now use a UI-independent operation with an explicit guide callback; 82 affected checks, 28 direct old/new cases and 512 seeded comparisons pass. The five remaining series-resume readers now use a stateless captured-profile repository with per-call retirement guards; 137 affected checks and 22 direct old/new cases pass, including actual storage namespace and delayed Trakt transport verification. Parent resume-cache ownership/capacity is implemented and reviewed in batch A; reachable transitive tracker contracts remain under audit. Native lifecycle, surface eligibility, playback handoff and native/device checks remain. |
| 8: Retirement/audit | In progress | All four handwritten parts/directives are removed. The large parent facade, remaining feature/action/lifecycle boundaries, resource exceptions, CI and native/performance destination gates remain open. |

After each delivery batch, update its status and record its revision, completed
responsibilities, actual checks/results, new/retired exceptions, and next deliverable
in the evidence document. Keep phase rows concise. If behavior changes
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
