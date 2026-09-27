# Search screen incremental refactoring plan

Status: implementation started on `refactor/search-screen`; the automated baseline
and phases 1–3 are reviewed. Phases 4A catalog and 4B keyword extraction are implemented and reviewed; phase 4C source selection, phase 5 Home extraction and phase 6 layout extraction are in progress. Remaining device/performance checks are pending.
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
| 6: Discover/layouts | In progress | Shared discovery-feature policy/readiness now uses scoped state and the existing injected preference service. Expanded focused checks: 42 successes and the same two baseline suggestion failures; a real Discover race test preserves TMDB disable fallback. Source selection and startup hydration now use a scoped controller with injected preference/addon access and guarded remembered-source writes; all 34 focused tests pass, including actual delayed-inventory UI behavior and preference-barrier retirement. The two-pane Discover composition and its backdrop/veil/dimming widgets are extracted, removing the old Sources part; 38 focused checks pass with the same pre-existing shape-manifest failure. Stage composition is also extracted with preserved shelf/identity geometry and theater transitions; all 40 focused tests pass, including both real Discover resize paths. Caption overflow now has the separately verified line-height fix; favourites art and directional navigation are extracted. Catalog-card metadata now has scoped Riverpod ownership, an injected repository and the shared hero/cache boundary; its expanded tests pass 117 checks. The catalog card and its collection/favourites row models are now standalone, removing the card part; 136 existing checks and six new direct tests pass. All seven board cells now use a standalone navigation wrapper with explicit live sidebar dispatch; 68 focused checks pass. Classic lazy rows and one-shot entrances are extracted; 78 existing passes and ten existing failures are unchanged, and six new tests pass. Trailer dim/recede presentation now uses explicit borrowed signals; 45 existing and five new transition checks pass. The informational takeover overlay is standalone, with unchanged metadata precedence and staged animation; 45 existing and four new checks pass. Classic geometry/surface composition is now standalone; 65 existing and four new layout checks pass. Home layout variants, the remaining hero presentation and preview/lifecycle boundaries, and device/performance checks remain. |
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
