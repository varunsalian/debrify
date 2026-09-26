# Search refactor implementation evidence

This log accompanies the [plan](search-screen-plan.md). A pending check is not a
pass. Source moves are reviewed after each slice, with phase reviews before the
next phase. No changes are pushed to the public repository.

## Phase 0: baseline and ownership review

Starting revision: `aa3d5643` (application tree inherited from `9619c10b`).
Branch: `refactor/search-screen`, tracking the private repository. The existing
untracked `output/` directory is unrelated and is left alone.

Environment: Flutter 3.44.8, framework `058e0af2c2`, engine `0cd610717b`,
Dart 3.12.2, macOS 26.4 on arm64. Keep this SDK and the existing lockfile for
before/after comparisons. No dependency changes have been made at baseline.

- `flutter analyze --no-pub`: 865 diagnostics (83 errors, 160 warnings, 622 infos).
  All 83 errors originate in the unused `packages/media_kit_video_tvos` package;
  they already exist before refactoring. The search library has one warning and
  20 infos. Compare diagnostic identities and source symbols, not shifted lines.
- Full-suite baseline: 609 suites, 7,387 passing tests, 51 failures/errors and
  20 skipped tests, in 183 seconds. All nine historical failures still fail; 42
  additional failures were observed before application edits. The helper exits 1.
  [Observed failing identities](search-screen-initial-failures.txt) are evidence,
  not a replacement allowlist. A capture wrapper saves the helper's same-run JSON
  and exit status; `test/known_failures.txt` is unchanged. Local `outcomes.json`
  records every visible test identity for subsequent before/after comparisons.
- Raw local receipts: `.git/refactor-evidence/baseline/` contains analyzer output,
  declaration inventory, test JSON, stderr and exit codes.
- `flutter devices --machine`: macOS, an iPad on iOS 26.6, and Chrome are listed.
  Android TV/tvOS interaction and playback checks are pending. Device listing alone
  does not establish any visual, behavioral, or performance baseline.
- Additional simulator discovery found the `debrify_tv` Android emulator and
  shutdown Apple TV simulators on tvOS 26.5, plus iOS 26.4/26.5 simulators. These
  are available candidates for the pending device work; they have not been run or
  counted as passing checks. The local simulator inventory is saved beside baseline
  receipts. The current Flutter fork supports plain `flutter emulators` output.

### Production surface and resource ownership

`lib/main.dart` mounts `SearchScreen` for Home, dedicated Search, and Discover.
Keep its constructor flags and title-search/resolver test seams. The original
library also exports `sourcesScreenForTesting`, `discoverLandingLoadIsCurrent`,
and `SpotlightIptvCardPreview`; preserve their consumers when they move.

The declaration inventory was checked against the plan's responsibility map:

| Current group | Migration owner and phase |
| --- | --- |
| Keyword sort, source classification, filtering and provider reconciliation | Search policies, phase 1; state/streaming/snapshots remain phase 4B |
| Category tag, See All link, mode controls | Home/Search presentation, phase 2 |
| Catalog/Lists query state and source settings | Search application/data, phases 3–4A |
| Sources screen and source dialog controls | Sources/Search application and presentation, phase 4C/4A–B |
| Home snapshots, catalogs, CW/favorite/IPTV rows and identity records | Home application/models, phase 5 |
| Card/artwork, board/queue/canvas cells, layout metrics, scrims and identity variants | Home/Discover presentation, phase 6 |
| Discover loading predicate, selection, backdrop/veils/grid dim | Discover application/presentation, phase 6 |
| Hero/trailer/live layers, card preview, ambient chips and entrance animations | Hero presentation and bounded coordinators, phase 7 |
| Detail/source/tracker/resume actions and playback handoff | Application/data plus named presentation bridges, phase 7 |
| Route/app observers, shell bridge registrations and compatibility exports | Presentation/session lifecycle, phases 7–8 |

Resource ownership must survive extraction:

| Resource | Current owner and disposal contract |
| --- | --- |
| Title-search service, editing listener, suggestion notifier | Screen creates/borrows the injected service under its existing contract, removes listeners and disposes on unmount; cancels on profile/tab/mode changes |
| Home/keyword `ProfileSessionMemory` stores | Static borrowed stores; `take` consumes once; never instantiate per provider; snapshots are scoped to captured owner |
| Text/board/keyword scroll controllers and row/toolbar/tab focus nodes | Screen-owned; preserve post-frame disposal for shrinking keyword/source results and focus anchoring |
| Metadata/profile/addon/home-settings/integration/tracker/IPTV listeners | Register only for the same tab variants and unregister the same callbacks; shared singleton services remain borrowed |
| `MainPageBridge` focus/back/detail/layout slots | Owner-aware unregister/clear; outgoing screens must not clear a newer screen's slot |
| Home/Discover hero notifiers, timers, keyboard handlers and route subscriptions | Presentation-owned; preserve suppression, intentional layout teardown and post-frame shell resets |
| Sources query/results controller, filter/pill/row focus nodes | Sources route-owned; preserve startup priority/cache/season reads and cancellation on disposal |
| Individual card/hero/queue animations, video widgets and timers | Their existing widget owners; inspect each paired init/update/dispose before moving in phases 6–7 |

First Riverpod integration remains Lists search in phase 3: injected MDBList
access, an auto-disposed controller per profile/session and individual screen
instance, with query generations for races. Keep the current title-search service.
Do not install Riverpod before this first production integration.

Borrowed legacy dependencies include `TorrentFilterMatcher`, title-search, Home
paging/deadline/progress/return-cache helpers, profile runtime/preferences, existing
MDBList/Stremio/tracker/torrent services, and native playback services. In particular,
`TorrentFilterMatcher` still imports legacy quality/language helpers from UI paths;
reuse its existing classification without copying it into a second implementation.

### Behavior matrix and pending device checks

| Surface | Automated starting coverage | Required manual scenario |
| --- | --- | --- |
| Home Classic/Spotlight, non-TV | Home load/return/paging tests, Spotlight compact/layout tests | Touch/mouse search sheet, resize, return from details/playback |
| Home Classic/Spotlight/Canvas/Promenade/Atrium/Mosaic/Deck/Tonight, TV where enabled | Home focus/layout/collections/stage tests | Each reachable style with D-pad Select/Back/hold, paging, trailer dwell and style switch |
| Dedicated Search: Catalog | Suggestions, search rail metrics and focus handoff tests; fan-out gaps scheduled in 4A | Submit/clear, source toggle, empty/partial failure, See All query/cursor |
| Dedicated Search: Keyword | Streaming, matcher/filter and source/focus tests; direct policy coverage added in phase 1 | Freeze/adopt, provider untick, cached-only, sort, bulk selection and tab return |
| Dedicated Search: Lists | MDBList and search UI tests; controlled controller race cases scheduled in phase 3 | Connect/disconnect, same-query retry, open list and restore focus |
| Discover: grid/stage and configured sources | Discover startup/TMDB/layout tests | Late defaults versus user choice, Search handoff, style change during preview |
| Details/Sources/Playback/Back | Source lifecycle and resume/routing tests | Android TV, tvOS and affected touch/desktop native entry/return, profile switch during pending work |

All manual scenarios above are pending. Loading/preview timing, request counts,
rebuilds and retained resources need representative fixed-data before/after
measurements when those paths change. Pure sorting/filtering can proceed after its
automated baseline without claiming native or visual parity.

Phase-0 review: all 609 suites completed; the historical allowlist is stale but
unchanged. The two unresolved-suggestion failures expect no `MergedDetailScreen`
but observe one; the compact-hero failure expects immediate resolution but sees no
request. These are pre-extraction behavior mismatches, not sorting/filtering
failures, and must be revisited when those paths migrate. Existing matcher and
streaming tests pass. No first-policy failure prevents the bounded extraction.

## Phase 1, slice 1: keyword sorting

Destination: `lib/features/search/application/keyword_sort.dart`. The production
recompute and sort dialog now call this policy; `_sortKeyword` and `_naturalAscFor`
were removed from the screen. Sort field strings, relevance/unknown-field order,
case-insensitive display titles, directions and comparator ties remain unchanged.
No new controller, dependency, mutable state owner or persistence was introduced.

- 17 policy tests cover directions, relevance/fallback, displayed titles, ties,
  empty/singleton lists, defaults and non-mutation. Combined with streaming,
  quality-tier, dynamic-range and filter-ladder tests: **93 passing**.
- Full `flutter analyze --no-pub`: the same 865 diagnostic identities and
  multiplicities as baseline after ignoring location shifts; none added/removed.
- `python3 dev/tool/check_search_architecture.py`: one migrated source passes.
  Nine temporary positive/negative fixtures verify size, UI/framework imports,
  handwritten parts and permitted presentation keyboard imports. CI wiring remains
  phase 8. This lexical check supplements responsibility review.
- New sources/tests are Dart-formatted; `git diff --check` passes. Legacy screen
  formatting is retained outside the edited fragments to avoid unrelated churn.
- Review: the actual production call is wired, both duplicate methods are gone,
  focus syncing remains in presentation, and sort output still copies the input.
  No new or retired legacy structural exceptions. Next: filter/provider policies.

## Phase 1, slice 2 and phase review: filters/providers

Destinations: `keyword_filter.dart` and `keyword_providers.dart` beside the sorting
policy (`bd0c214e`). The screen delegates filtering and provider reconciliation;
all source-tab/count/rendering call sites use the same extracted source identity.
The old cache predicate, classification and duplicate filter/count loops are gone.

- 15 additional policy tests cover cached TB versus PM, lowercase-without-trim
  hash keys, hashless download exemptions, independent direct/torrent groups,
  empty-group semantics, source-tab intersection, existing attribute facets,
  unticked-source retention, dedupe disappearance/reappearance and immutable
  reconciliation results. Total new policy tests: **32**.
- Affected policy, streaming, classifier, suggestion and source/search-focus run:
  **129 pass**, the **same two baseline unresolved-suggestion failures**, no new
  failures, no previously passing test skipped and no missing test identities.
- Full analyzer: identical 865 diagnostic identities/multiplicities. Three
  migrated application files pass the architecture check and stay under 100 lines
  each. New files are formatted and the diff passes whitespace checks.
- Phase review: filter ordering and empty-group/cache exceptions match the old
  production algorithm. Reconciliation does not mutate its inputs; the screen
  copies the returned selections into the existing sets in place so an open
  provider dialog keeps its captured references. Focus syncing and streaming
  freeze/adopt/snapshot timing remain under their existing owner for phase 4B.
  The legacy `TorrentFilterMatcher` is reused, not rewritten. No UI/network state
  entered the policies and no new structural exceptions were introduced.
- Phase 1 exit is satisfied. The screen remains a registered legacy exception
  (20,791 lines); its remaining workflows follow phases 2–8. Manual device and
  native parity are still pending and are not inferred from these pure tests.

## Phase 2, slice 1: leaf presentation

`CategoryTag` now belongs to `features/home/presentation/category_tag.dart` (43
lines). `SeeAllLink` is in `ui/core/see_all_link.dart` (57 lines): the existing rail
header uses it across Home and Search catalog rows, so this is demonstrated shared
UI. Its path is explicitly measured by the architecture checker. Original private
widget classes were deleted and production calls use the new widgets.

- Review compared the original widget implementations with the extracted files,
  ignoring formatting, public names and optional keys: no implementation changed.
  Theme tokens, dimensions, hover behavior, gesture callback and labels match.
- Three new widget tests cover full/compact labels, one tap dispatch, hover
  brightening/restoration and no accidental action on hover. Together with search
  metrics, search/title focus and Home row-focus/shape checks: **26 pass**, the
  **same three baseline failures** (two unresolved suggestions and shape residue).
  No new failures, skipped formerly passing tests or removed test identities.
- Full analyzer identities/multiplicities remain unchanged at 865. Five migrated
  files pass size/import checks. Shape-manifest coverage follows both moves, with
  no raised residue allowances or weakened assertions. New files are formatted.
- The existing English labels retain legacy localization debt as allowed by
  `AGENTS.md`; no alternative localization mechanism or new wording is introduced.
  No data/service call moved into these views. Next bounded slice: mode controls.

## Phase 2, slice 2 and phase review: mode controls

`features/search/presentation/search_mode_toggle.dart` (259 lines) owns the existing
selector. `features/search/models/search_mode.dart` names the same three modes in
the same order. All production references use that enum and the old private
selector/enum are removed. Keyword permission is now an explicit input from the
caller; the screen's action-time permission guard is retained. The view no longer
queries global profile policy.

- Five new widget tests cover unavailable modes, pointer selection, both D-pad
  traversal variants, field/content exits, one action per Select, borrowed focus
  node lifetime and the narrow dropdown fallback/selection. Together with the
  three See All tests, Search UI/metrics/focus and shape checks: **29 pass**, the
  **same three baseline failures**, no missing/newly skipped tests.
- Full analyzer matches all 865 baseline identities/multiplicities. Seven migrated
  files pass architecture checks; no migrated file exceeds 300 lines. Shape
  manifest follows the moved selector without changing existing allowances.
- Implementation comparison confirms only public names/keys and the explicit
  availability input differ; visual properties and keyboard dispatch are retained.
  Existing dropdown/focus utilities are reused, and the parent owns focus nodes.
- Phase 2 exit is satisfied for the selected leaves/controls. Stateful cards,
  sources controls and hero/layout widgets deliberately remain in their planned
  later phases. Remaining legacy counts: screen 20,796; cards part 926; hero part
  2,249; sources part 3,846; stage part 1,706. The original exceptions remain
  temporary; none is presented as the destination. Device checks remain pending.

## Phase 3: Lists Riverpod integration (implemented and reviewed)

Added `flutter_riverpod` 3.4.3 with manual provider declarations. Package resolution
adds only `flutter_riverpod`, `riverpod`, `listen` and `state_notifier`; every
previous lockfile entry is unchanged. The selected version was checked against
the installed SDK and the publisher documentation:
https://pub.dev/packages/flutter_riverpod
https://riverpod.dev/docs/3.0_migration

Ownership and production wiring:

- `application/lists_search_controller.dart` owns query, immutable results,
  loading/error state and action generations. The screen's former mutable fields,
  request token and error-mapping implementation are removed; remaining getters
  read the provider state, and UI code retains focus/navigation dispatch.
- `application/lists_search_dependencies.dart` composes the narrow repository
  contract and MDBList adapter. The adapter borrows existing services, checks the
  captured profile/session before invoking them and retains the originating scope
  across asynchronous credential reads. No service receives `Ref` or UI context.
- `models/search_session.dart` keys each family by captured profile/session
  and one stable screen identity. Query changes belong to that workflow's action
  generation; concurrent screens with equal queries remain independent.
- Providers disable framework retries. A screen-owned `listenManual` subscription
  preserves the existing mounted/covered-route lifetime, redraws from the single
  state owner, and closes on disposal. It does not issue requests on build,
  invalidate/re-listen, route return or ordinary widget rebuild.
- `DebrifyApp` installs `ProviderScope` above its Navigator; no fallback container
  is installed in Search. Twelve existing standalone test hosts are scoped. New
  production-screen tests verify pushed/dialog consumers inherit the same state.
- `TmdbTitleSearch` remains the existing injected, context-free debounce/query
  owner; no second title-search engine/controller is added. Field composition,
  suggestion callbacks, tab/mode cancellation and the existing resolver seam are
  retained. Context-dependent detail dispatch remains the phase-7 presentation
  bridge responsibility. The two baseline unresolved-suggestion failures remain
  visible rather than being altered to make this migration green.

Verification so far:

- **14 controller tests**: explicit actions, immutable results, both request race
  orders, stale auth, clear, profile expiry, auto-disposal, concurrent routes,
  disconnect/reconnect, disabled mode, failure/no automatic retry and partial/rate
  limit responses.
- **2 real adapter tests**: asynchronous reads retain originating profile scope;
  expired profile or lifecycle prevents subsequent credential/network dispatch.
- **7 production-screen tests**: rebuild/route/dialog retention, covered completion,
  mode return without duplicate requests, repeated visits disposing old families,
  field clear, disconnect-to-Catalog/reconnect preserving text, and outgoing-profile
  cancellation before route disposal. All **23 new tests pass**.
- Existing Home/Search/Discover/Sources and app-smoke group: **79 pass**, the same
  three baseline failures (unresolved suggestions and the app smoke test), no
  missing or newly skipped identities. Full analyzer still has exactly the same
  865 diagnostic identities/multiplicities. Thirteen migrated sources pass the
  size/import checker; all remain below 300 lines.
- The completed full-suite rerun has **7,450 passes, the same 51 baseline failures
  and 20 skips**, with no missing or newly skipped identities. Analyzer identities
  and multiplicities are unchanged. The historical helper still exits 1 because
  its nine-name allowance predates the observed 51-name baseline; the actual
  comparison passes. No native/visual/performance parity is claimed from these
  checks. Raw receipts are under `.git/refactor-evidence/phase3/`.

Phase-3 full-suite investigation:

- The first integration run reached 7,448 passes and the same 51 ordinary baseline
  failures, but stalled in `connection_secret_editor_repair_test.dart` during its
  first IPTV credential repair. The sole remaining engine process was sampled;
  after about ten minutes it was terminated to recover the runner output. The two
  unfinished IPTV cases and teardown are recorded as three additional errors.
  This run is **not** accepted as a clean comparison.
- The unchanged credential-editor suite then passed all six scenarios in isolation
  (13.7 seconds), including both IPTV repairs. A second complete helper run is
  completed with incremental JSON capture, without repeating the stall.
  No test assertions, failure allowances or credential-editor code were changed.

Phase-3 review: production has one Lists state owner; the controller has no UI
context, services retain their existing lifetime, and scope/read generations cover
outgoing authentication as well as results. Rebuild, route, dialog, mode and
profile tests exercise the actual screen. The existing title-search owner remains
in use. The phase's structural/automated exit is met; device/visual/performance
checks remain explicitly outstanding in the migration-wide behavior matrix.

## Phase 4A: Catalog search and source settings (implemented and reviewed)

The production screen delegates catalog requests to `CatalogSearchController`;
`CatalogSourcesController` owns dialog reads and immediate settings writes.
`StremioCatalogSearchRepository` borrows the existing Stremio service and watched
filter. Catalog query/loading/failure counters and the old request token have been
removed from the screen. `SearchSession` is the existing Lists key renamed for its
now-demonstrated reuse; the two search workflows still have separate state owners.

- Catalog search preserves the ten-request limit, searchable-only catalogs,
  disabled-addon filtering, one row per catalog, failure counts, raw first-page
  cursor, query handoff, stable ordered TV batches and arrival-ordered non-TV rows.
  Empty/watched-only responses remain single-shot. Framework retries stay disabled.
- Results publish immutable row/list snapshots. `catalogSearchSection` is a small,
  one-way temporary presentation adapter to the legacy Home renderer; it copies
  item containers and cannot mutate the controller's published rows. Home retains
  its existing paging/cache ownership until phase 5. `_restoreHome` still dispatches
  deferred reloads and focus/hero effects remain in presentation.
- The real adapter guards profile/session expiry before calls and after responses.
  Settings acquire the original profile's preferences facade, then write outside
  the captured-scope zone. This preserves the existing key/JSON format while the
  facade's live-session checks reject a switch during its async mutation barrier;
  neither the incoming profile nor deleted outgoing data receives that late write.
- The Sources dialog has no service/persistence calls. It retains the original
  loading/empty/text/layout behavior, immediate toggle/bulk saves, and Done/rerun
  behavior. A profile subscription clears outgoing dialog state without initiating
  another load. Accepted saves can finish after dismissal; errors are caught and
  diagnosed without private values or automatic retries.
- Three shared dialog presentation files replace the old coupled part definitions.
  Catalog and Keyword both use them. Normalized body comparisons against phase-3
  source prove only visibility/names/optional widget keys changed; shape manifest
  follows their new paths with zero new bare-radius allowances.

Verification and review:

- Four new production-screen cases passed **before** extracting catalog search:
  TV batching/order, non-TV streaming/order, replacement query and field clear.
  After wiring, the screen suite has **eight passing cases**, adding actual Sources
  persistence/requery, failure status, outgoing-profile clearing and deferred Home
  settings reload. The last case verifies updated row membership on clear while
  preserving cached contents/request counts, rather than demanding a needless fetch.
- **14 controller tests** cover bounded fan-out, both publication styles, stale
  completion/failure, filtering, no retry, empty/partial/total failure, separate
  views, clearing, profile expiry and disposal. **Seven real adapter tests** cover
  protocol/cursor/metadata provenance, projection non-mutation, watched filtering
  without top-up, failure, stale results, exact persistence format and real profile
  write barriers. **Six dialog tests** cover Select/pointer/bulk actions, immediate
  saves, reopen/disposal, pending writes, expiry and outgoing data clearing.
- Affected tests at the last broad pass: **190 success and the same three baseline
  failures** (shape manifest and two unresolved title suggestions), no missing or
  newly skipped identities. The two subsequently added Home/watched cases pass in
  their focused suites. Full analyzer still matches all **865 diagnostic identities
  and multiplicities**. The architecture checker covers **27 files**, all below
  300 lines; `git diff --check` passes.
- A draft screen test initially tried to open Sources after results hid the prompt;
  it now exercises the actual prompt/dialog path, with an already-dispatched query
  completing underneath. Another draft expected deferred Home reload to refetch;
  inspection showed existing row-cache reuse, and it now verifies changed visible
  membership plus unchanged request count. No app behavior or existing assertion
  was changed to accommodate these fixture corrections.
- Receipts: `.git/refactor-evidence/phase4a/`. Device/visual/performance checks remain
  pending and are not inferred from widgets. Legacy sizes: screen **20,689** lines;
  Sources part **3,347**; other remaining parts unchanged. Phase 4B/C and 5–8 remain.

## Phase 4B: Keyword source settings slice (phase still in progress)

`KeywordSourcesDialog` now consumes its own Riverpod controller and immutable
`KeywordSource` choices. The real screen opens it with the captured `SearchSession`
and retains its existing post-dialog search/first-paint toolbar focus handling.
The shared dialog controls from 4A keep the original appearance and keyboard paths.
`EngineKeywordSourcesRepository` receives the existing combined engine loader and
borrowed `SettingsManager`; it preserves registry order, per-engine defaults,
explicit saved overrides, key normalization and one immediate write per bulk item.
Like catalog settings, preference writes retain live profile checks at the async
mutation barrier. Profile handoff clears the dialog without replaying a load.

Slice review and checks:

- Four adapter tests cover all three default cases (missing/false/true), saved
  overrides, settings-key compatibility, late enumeration and actual preference
  barriers. The combined-loader case imports a real temporary registry YAML file
  and a disabled Prowlarr configuration, proving both appear in order and the
  user-configured indexer's saved override takes precedence. An initial fixture
  used the internal model's JSON shape instead of the flat imported-YAML format;
  correcting the fixture exercised the real registry parser successfully.
- Five dialog tests cover defaults, Select/tap, immediate bulk writes, reopen and
  disposal, saves failing after dismissal, stale loads on profile replacement,
  empty state and no automatic retry. All nine new tests pass.
- Related integration/source/engine tests: **49 pass, the same two baseline title
  suggestion failures**, no missing or newly skipped identities. Analyzer remains
  at the same 865 identities/multiplicities. Architecture checks cover **33 files**,
  all below 300 lines; diff checks pass. Receipts are under
  `.git/refactor-evidence/phase4b/`.
- This completes only the source-settings slice. Keyword streaming/freeze/adopt,
  per-batch cache checks/final cache-only mode, default filters, borrowed snapshots,
  and bulk-selection ownership are still in the screen and remain required work.
  Source part is now 3,257 lines and the main screen 20,686 lines. No new permanent
  size exception or device/performance parity claim is introduced.

### Phase 4B cache slice (implemented and reviewed)

`KeywordCacheController` owns the immutable badge map, checked hashes, outstanding
batch checks, successful-TorBox flag and cached-only decision. Credentials and
provider calls live in a search-owned session behind `KeywordCacheRepository`;
`DebridKeywordCacheRepository` borrows the original storage and provider services.
The screen's mutable cache/config fields and cache-check implementations are gone.

The boundary preserves lowercasing without trimming, duplicate dispatch, TB-before-PM
request order, partial badges, memoization only after all enabled checks succeed,
retry eligibility for failed hashes, the completion sweep and other-provider gating.
Repeated-key badge replacement retains the original `addAll` behavior. The existing
provider services still own network retries/timeouts; Riverpod retries are disabled.
Private generations and the workflow token reject stale configuration and results.
The screen's subscription repaints badges; only an accepted cached-only change
reconciles visible rows/focus. Profile handoff now also clears outgoing keyword
rows and invalidates their workflow token before a late completion can publish.

Review found a real restoration regression before this slice was committed: the
first version called a notifier restore action inside `initState`, which Riverpod
correctly rejects during widget construction. A new actual-screen remount test
exposed it despite the earlier full-suite pass. The fix consumes the existing
borrowed snapshot once before constructing the immutable `SearchSession`, seeds
its cache provider on initial build, and restores other presentation fields at
their original point before default-view loading. It does not defer the first
render or requery. Dependency/profile rebuilds do not reapply that initial seed.
The existing static `ProfileSessionMemory` remains the snapshot owner; no new store
or listener is allocated per provider. Full snapshot extraction remains later 4B.

Focused evidence: **15 controller tests**, **14 real-adapter tests**, and **four
production-screen tests** now pass. They cover completion ordering, retry/memoization,
empty success versus failure, disabled/other providers, request replacement,
configuration races, clear/profile/disposal, immutable seeding, real credential
settings/delegation, focus-preserving filtering, profile handoff and a fresh-screen
restore without additional engine/credential/cache calls. The adapter's draft
record-of-list equality assertion was corrected to compare keys and hash lists
separately; the actual captured values were already correct.

The full suite before adding the remount case matched the observed baseline
(7,526 passing identities, 51 existing failures, 20 skipped). After the restoration
fix and added case, the repeated full suite has **7,527 passing identities, the
same 51 baseline failures, and 20 skipped**, with no missing or newly skipped
identities. Analyzer still matches all **865 diagnostic identities/multiplicities**.
The historical helper's exit 1 remains attributable to its outdated nine-failure
allowance; comparison with the actual observed baseline passes. The architecture
check covers **38 migrated files**, all below 300 lines. Formatting and diff checks
pass. Raw receipts remain in `.git/refactor-evidence/phase4b/`.

The cache slice's automated review is complete; phase 4B as a whole remains in
progress. The main screen is 20,571 lines. Remaining keyword work includes the
workflow/action generation and initial-action profile guard, streaming/freeze/adopt,
filtered/sorted results and selections, default-filter reads, and full snapshot
ownership. Focus/scroll and legacy navigation effects will remain in presentation.
Device/visual/performance checks are still pending, not inferred from these tests.

### Phase 4B request orchestration (implemented and reviewed)

The production keyword action now delegates to
`lib/features/search/application/keyword_search_controller.dart` (118 lines).
It owns the query, loading/searching/error state, request generation, provisional
batch accumulation and authoritative engine completion. The screen's mutable
request fields, `_kwBatches`, service dispatch and error mapping are removed.
`keyword_search_state.dart` publishes immutable result containers;
`keyword_search_result.dart` gives the service completion a typed boundary.
`keyword_search_dependencies.dart` wires the narrow repository and disables retries.
`engine_keyword_search_repository.dart` borrows `TorrentService.searchAllEngines`
and its existing deterministic merge, limits, authorization and retry/timeout
behavior. Raw maps stay inside this adapter. Calls retain the originating scope,
and an outgoing owner is rejected before dispatch and before publishing a batch.

The request controller retains the cache notifier through its provider dependency.
An explicit search still resolves cache settings before starting engines, presents
each accepted batch before asking for its badges, and rejects empty, superseded or
post-completion batches. Completion publishes the authoritative list exactly once.
The screen subscription invokes the existing presentation/focus wrapper and cache
completion sweep in that order. A clear invalidates the request and cache work.
Closing the Home search sheet uses this same clear; its redundant second token
increment is gone, with one monotonic generation still rejecting every old callback.
Initial outgoing-view actions are rejected before resetting presentation controls.

Query restoration uses immutable per-view bootstrap data in `SearchSession`, just
as the preceding cache slice does. It does not call a notifier action from widget
construction. Dependency rebuilds do not restore the bootstrap again. The borrowed
static full snapshot store, variant matching, default-view suppression and scroll
restoration retain their existing ownership and timing.

The legacy screen still owns the frozen displayed projection (`_kwAll`, pending
arrivals, filters/sort/provider choices and bulk selection), focus and scrolling.
This is a registered temporary phase-4B boundary, not the final architecture:
move the projection's application state next, leaving only focus/layout/navigation
in presentation. The latest engine publication has one owner in Riverpod; the
frozen projection intentionally may display an earlier accepted result until adopt.
Full snapshot and default-filter data extraction also remain in phase 4B.

Focused review evidence includes **23 controller tests**, **nine adapter tests**,
and **four new actual-screen streaming tests**. They cover cache-before-engine
ordering; incremental merge and final replacement; late timed-out callbacks;
query/configuration replacement; clear, disposal and profile handoff; dependency
replacement without bootstrap replay; independent views in one profile; disabled,
failed and partially successful engines; immutable lists and exact query/source
handoff; captured scope and rejected outgoing dispatch; and the unchanged error
messages. The screen cases cover first streamed paint, frozen live source counts,
identity-preserving adoption, final invalid-source clearing, old-query rejection
and profile clearing. The four prior actual-screen cache/focus/remount tests also
pass through the real engine adapter. The pre-extraction affected run had all
11 existing streaming-policy/cache-screen tests passing.

Draft test corrections did not change production behavior: source ids use the
legacy lowercased `Torrent.source`; the existing loading animation's uncancellable
3s/7s message futures must be drained after widget disposal; invalidating a provider
that returns the identical dependency does not constitute dependency replacement;
and the existing `replaceAll('Exception: ', '')` also strips that substring from
some exception type names. Tests now explicitly retain that latter legacy behavior
rather than silently fixing it during extraction. These failed draft receipts and
corrected runs are retained in `.git/refactor-evidence/phase4b/stream-*.txt`.

Analyzer comparison after implementation and tests has no added or removed
identities/multiplicities (the same 865). The architecture guard covers 44 migrated
application files, all below 300 lines. The main screen is now 20,479 lines.
The full suite completed in 174,270 ms: **7,563 passing identities, the same
51 baseline failures (22 failures plus 29 errors), and 20 skipped**, with no new
failures, missing identities or newly skipped previously passing tests. The
historical helper still exits 1 because its nine-failure allowance is stale; the
actual observed-baseline identity comparison passes. Receipts are
`.git/refactor-evidence/phase4b/full-stream.jsonl`, `full-stream-comparison.txt`,
`analyze-stream-final.txt` and `stream-analyzer-final-comparison.txt`. Formatting
and diff checks pass. This request slice's automated review is complete; phase 4B
and the overall migration remain in progress. Device/visual/performance checks
remain pending.

### Phase 4B displayed results (implemented and reviewed)

`KeywordResultsController` (232 lines) now owns the displayed/pending raw results,
freeze/adopt decisions, filtered/sorted results, provider reconciliation and choices,
source-tab selection and bulk-selection state. `KeywordResultsState` publishes
immutable containers and reuses unchanged lists on freeze/selection updates. The
existing filtering, sorting and provider policies are reused. `KeywordProviders`
is now a model, re-exported by its former policy file for existing callers.
The screen's mutable projection fields and `_computeKwProviders` are removed;
its small action wrappers keep row/tab focus, scroll and legacy dialog/navigation
handoff. Cache badge notifications do not cause recomputation: the accepted cache
completion still explicitly recomputes the displayed projection.

The result controller is separate from the engine-request controller because the
user can deliberately keep viewing older rows while authoritative results arrive.
Each state has one owner. An explicit new search resets per-search choices while
retaining the hidden prior rows and filter/sort preferences until the first paint.
An explicit adopt updates provider choices and clears a vanished tab; completion
validates the tab against the full pending set but filters the displayed set.
Bulk selection keeps exact infohash identity, excludes direct/external rows from
All, and retains the prior None/Cancel behavior. Outgoing-session actions are
rejected by the injected search repository's owner check.

`keywordResultsSnapshot` is a pure application function that folds pending raw
rows and provider choices without changing the live state. It intentionally
retains the legacy snapshot's previously displayed filtered rows. The first
integration draft called a controller getter during widget disposal and the eight
existing screen tests caught Riverpod's unsafe `WidgetRef` read. The correction
uses the retained subscription's state and the pure function; no provider is
resolved or mutated during disposal. Restoration seeds the result provider from
immutable `SearchSession` bootstrap data before the first widget build, with no IO
or recomputation. The static full snapshot store is still borrowed; moving its
storage/consume boundary and default-filter reads remains phase 4B work.

`KeywordProvidersDialog` (118 lines) replaces the legacy local-repaint dialog with
a Consumer widget that owns its subscription for the dialog lifetime. Checkbox
and All/None actions dispatch to current immutable state rather than mutate a
captured Set. This also makes profile invalidation clear an open dialog's outgoing
choices; a retained outgoing checkbox callback cannot restore them. The screen's
focus callback is mounted-guarded. `keywordSourceLabel` preserves the same display
name lookup and fallback for the dialog and source rail. Layout, wording and
control styling are retained.

Focused checks pass: **12 new controller tests**, **two new actual-screen tests**,
and the **eight existing streaming/cache/focus/remount screen cases** (22 total).
They cover stable freeze/adopt, provider unticks and reappearance, independent
Direct/Torrent groups, invalid source tabs, filter/sort interaction, explicit cache
recomputation, eligible bulk selection, begin/clear, retired actions, immutable
bootstrap and pure snapshot folding. The new screen cases exercise the actual
provider dialog, Name sort, bulk All/None/Cancel and an open-dialog profile handoff
including a retained callback. The dialog test uses bounded frame advances while
the searching indicator animates, and scrolls the toolbar to reach Select rather
than suppressing missed-hit warnings. Draft fixture enum names were corrected to
`StreamType.directUrl`/`externalUrl`; no production enum changed.

The architecture guard covers **50 migrated files**, all below 300 lines, and the
main screen is **20,281 lines**. Formatting and diff checks pass. Raw receipts are
`.git/refactor-evidence/phase4b/results-*.txt`.

The intermediate full suite (before extracting the dialog subscription and adding
its profile-handoff test) matched the observed baseline with 7,576 passing
identities. The repeated final suite completed in 172,038 ms: **7,577 passing
identities, the same 51 baseline failures (22 failures and 29 errors), and 20
skipped**, with no new failures, missing identities or newly skipped previously
passing tests. Final analyzer identities/multiplicities remain the same **865**.
The historical helper still exits 1 because its nine-failure allowance is stale;
the actual observed-baseline comparison passes. Final receipts are
`.git/refactor-evidence/phase4b/full-results-dialog.jsonl`,
`full-results-dialog-comparison.txt` and `analyze-results-dialog.txt`.

This slice's automated review is complete. Phase 4B still needs the default-filter
read boundary and full snapshot storage/consume ownership; legacy presentation
and navigation/playback bridges remain scheduled in their later phases. Native,
visual and performance checks remain pending. The full migration is not complete.

### Phase 4B defaults and snapshot boundary (implemented and reviewed)

`StoredKeywordDefaultsRepository` reads the existing five JSON preferences under
the originating profile scope, in the same order, retaining exact enum-name
matching, input order and unknown-value handling. `KeywordResultsController` now
owns explicit default loading, nonempty-user-choice precedence, nonfatal failure
and generation checks for replacement/disposal. Late defaults can still filter
an already completed fast search; clearing a query does not cancel this startup
preference. Empty choices retain the legacy eligibility for saved defaults. No
read starts from provider construction/recomputation, and restored keyword views
still skip the startup action. The screen only synchronizes focus nodes after an
accepted result; its preference reads and enum parsing loops are gone.

`KeywordSnapshot` replaces `_KwPreservedState`. The screen retains a plain
`KeywordSnapshotRepository` resolved before constructing its SearchSession, so
neither snapshot consumption nor disposal requires a provider-state mutation.
`MemoryKeywordSnapshotRepository` borrows one static `ProfileSessionMemory` store,
keyed by its captured owner with explicit tab-variant matching. Wrong-variant
reads retain the entry, matching reads consume it once, and a denied matching
snapshot is still consumed. An outgoing adapter cannot read or overwrite a newer
incoming snapshot. Lifecycle clear invalidates retained values and old adapters.

Snapshot preparation still folds pending authoritative raw rows while retaining
the legacy displayed filtered rows. The model retains query, filters, sort,
provider choices, source tab, badges/cached-only state and scroll offset; it drops
transient freeze, pending, bulk selection and provider-seen state exactly as the
old snapshot did. It reuses unchanged immutable result lists. Restoration seeds
the three existing keyword providers without starting a search, reading settings,
recomputing filters or allocating another process-lifetime store.

Focused checks pass: **nine defaults-controller tests**, **five real preference
adapter tests**, **seven snapshot-repository tests**, and **12 actual keyword
screen cases** (33 total). New screen cases cover late defaults filtering fast
rows followed by remount without another settings read/search, and a frozen final
snapshot restoring its legacy displayed rows while keeping all authoritative raw
rows available for the next deliberate sort. Repository tests cover all five
preference keys, malformed data, captured profile reads through a handoff,
consume-once/variant/policy rules, 100 adapters borrowing the same store, lifecycle
clear, late outgoing writes/reads and immutable snapshot choices. Existing query,
cache, focus, source-dialog/profile and restoration screen cases remain passing.

The profile source-text guard moved its store/take/store checks to the real
adapter and retains the old raw-static prohibition, adds the new raw-static
prohibition and asserts captured-owner/stale-write guards. Its migrated test
passes; running that whole guard file still reports the same two unrelated
observed-baseline failures (direct SharedPreferences inventory and diagnostic
reset source lookup). No assertion or known-failure allowance was removed.

#### Phase 4B automated exit audit

| Required responsibility | Production owner and verification |
| --- | --- |
| Engine streaming, request replacement and failures | `KeywordSearchController` + `EngineKeywordSearchRepository`; request/adapter tests and real screen streaming cases |
| Frozen arrivals, filters/sort/source choices and bulk selection | `KeywordResultsController` with phase-1 policies; controller tests plus actual provider/sort/All/None/Cancel controls |
| Cache configuration, batches, retries and completion filtering | `KeywordCacheController` + `DebridKeywordCacheRepository`; cache/controller/adapter/focus/remount tests |
| Source settings, defaults and immediate writes, including indexer engines | `KeywordSourcesController` + `EngineKeywordSourcesRepository` and dialog; combined registry/indexer and real preference mutation tests |
| Saved filter defaults and user-choice precedence | `StoredKeywordDefaultsRepository` + explicit results-controller action; data, race and real screen restoration tests |
| Full keyword snapshot ownership and restoration | `MemoryKeywordSnapshotRepository`, `KeywordSnapshot`, pure fold and immutable bootstrap; variant/profile/lifecycle/repeated-adapter and real remount cases |
| Legacy focus/scroll and navigation/playback effects | Existing presentation wrappers retain ordering and arguments; executable focus/selection coverage above; bridge extraction remains phase 7 |

The implementation audit covers phase 4B's application/data migration, not the
entire Search/Home/Discover library or device parity. The main screen is 20,138
lines; the largest keyword controller is 260 lines. All 57 migrated files pass
the architecture guard, and formatting/diff checks pass.

The final full suite completed in 170,355 ms: **7,600 passing identities, the same
51 observed-baseline failures (22 failures and 29 errors), and 20 skipped**. There
are no new failures, missing identities or newly skipped previously passing tests.
Analyzer identities/multiplicities remain the same **865**. The historical helper
still exits 1 because its nine-failure allowance is stale; the actual observed
baseline comparison passes. Final receipts are
`.git/refactor-evidence/phase4b/full-defaults-snapshot.jsonl`,
`full-defaults-snapshot-comparison.txt` and
`analyze-defaults-snapshot-complete.txt`.

Phase 4B's application/data implementation and automated review are complete.
Phase 4C, later Home/Discover/layout/lifecycle phases, CI wiring and native/visual/
performance checks remain outstanding; the full migration is not complete.

### Phase 4C season policy slice (implemented and reviewed)

`lib/features/sources/application/source_seasons.dart` (104 lines) now owns source
season-pack eligibility, coverage-derived fallback season numbers and menu
precedence. The actual Sources screen calls these policies; its old filtering
and derivation implementations are removed. IPTV ownership is passed as the
existing predicate, keeping service access outside the pure policy. Movie and
episode selections, bind-mode IPTV exceptions, provider order, complete/ranged/
single-season packs, unknown coverage and legacy episode-name substring matching
retain their behavior. Range expansion still permits at most 50 steps (51 season
numbers), excludes nonpositive numbers and ignores malformed/wider ranges.
Metadata seasons take precedence over fallback results; the selected season stays
reachable when absent from either list. Metadata fetching, selected-season state
and the rule to derive fallback seasons only at unscoped completion remain in the
registered legacy screen until the next state/data extraction.

The old `season_filter_test.dart` simulated a copy of the filtering algorithm.
It now exercises the real production policy with its existing assertions intact.
Fourteen new policy cases cover direct/episode/movie eligibility, the injected
IPTV exception, order, coverage edge cases, matching quirks, range bounds and menu
fallback without input mutation. One new actual Sources-screen case verifies a
season-scoped search drops other-season packs and direct episode links, retains
the correct pack/complete series in returned order, and starts focus on row zero.
Existing selected/cached direct-source and streaming-focus tests remain passing.

Before extraction, all 15 affected tests passed. The final affected run has
**30 passing tests and no failures**. Analyzer identities/multiplicities are
unchanged at **865**. A normalized-body comparison also proves the filtering body
matches the original apart from whitespace/comments and the injected binding/
IPTV ownership names. Formatting and diff checks pass; the architecture guard
covers **58 migrated files**. The Sources part is now **3,167 lines**, and the
main screen is **20,139 lines**. Receipts are in
`.git/refactor-evidence/phase4c/season-before.txt`, `season-final-focused.txt`,
`season-equivalence.txt`, `analyze-season.txt` and
`season-analyzer-comparison.txt`.

This is the first reviewed slice of phase 4C, not its completion. Source state,
season-guide metadata/inventory side effects, individual retries, selected-source
reveal, pin/local mutations and cache orchestration remain. The last full-suite
checkpoint is still the preceding phase-4B run; this pure policy slice used the
affected suite plus analyzer comparison. Native/visual/performance checks and all
later migration phases remain pending.
