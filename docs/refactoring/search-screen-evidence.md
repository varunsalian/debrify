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


### Phase 4C season state and guide boundary (implemented and reviewed)

The production Sources screen now consumes `SourceSeasonsController` through
Riverpod. A view-specific `SourcesSession` carries the captured profile owner and
metadata identity. Selected, authoritative and derived seasons have one immutable
state owner; the screen retains focus, menu rendering and search dispatch.
Initialization explicitly requests metadata, while provider creation performs no
IO. Request generations reject replaced results, and retirement/disposal rejects
late guides before inventory dispatch. Metadata failure retains fallback behavior.

`StremioSourceSeasonsRepository` preserves origin-catalog versus fallback-IMDb
lookup and built-in metadata routing. It keeps raw metadata private and records
inventory through the existing borrowed completion service under the captured
scope. Inventory remains non-blocking. An optional commit predicate on the
existing inventory methods rejects retired interactive writes after waiting for
the preference mutation barrier; callers without the predicate retain their
existing behavior and schema. The guarded writer uses the existing barrier and
lets the preference setter own mutation revision tracking.

The affected suite has **65 passes**: real Sources focus/streaming, pure season
policies, controller timing/retirement, repository origin/fallback routing and
actual persisted inventory, completion and custom-series progress. New coverage
verifies a real inventory write queued behind a held preference snapshot cannot
write or notify after session retirement. Analyzer identities/multiplicities
remain the same **865**. The architecture check passes for **64 migrated files**;
the new controller is 88 lines and concrete adapter 75. Sources is 3,149 lines;
the parent screen is 20,142. Formatting and diff checks pass. Receipts:
`.git/refactor-evidence/phase4c/guide-final-focused.txt`,
`analyze-guide-final.txt` and `guide-analyzer-comparison.txt`.

The exact full-suite helper completed in 171,282 ms with **7,628 successes**, the
same **51 observed baseline failures** (22 failure and 29 error outcomes), and
**20 skips**. Identity comparison finds no new failures, missing tests or newly
skipped baseline cases. The historical helper still exits 1 because its allowance
covers only nine of the 51 observed failures; the allowance was not changed.
Receipts are `.git/refactor-evidence/phase4c/full-guide.jsonl`,
`full-guide.helper.txt` and `full-guide-comparison.txt`. Phase 4C remains in
progress: Sources results/search, retries, cache and pin/local-source actions
still require extraction. Later phases and native/visual/performance checks
remain outstanding.


### Phase 4C startup settings (implemented and reviewed)

`SourceSettingsController` (62 lines) owns immutable provider priority/aliases and
addon text/logo settings. `StoredSourceSettingsRepository` (60 lines) retains the
existing movie/series Quick Play selection, alias lookup, provider enumeration and
ordering, preference keys and defaults. The production Sources screen now reads
these values from a view/session-specific Riverpod subscription; the two old data
loading methods and mutable fields are removed. The screen owns subscription
cleanup and starts the search only after the existing bound-source load and both
settings branches finish. A retired startup cannot launch a search.

The controller starts no IO during construction. Priority and appearance load
concurrently, preserving sequential reads inside each branch. Priority failure
continues with default ordering; appearance failure retains its existing error
propagation. Partial completion preserves the other branch's state. Generations,
disposal and live profile ownership reject late publication. The repository uses
the captured scope and checks live ownership before subsequent service calls.
It borrows existing services and introduces no preference writes or schema change.

Before extraction the ten Sources screen tests passed. The final affected run has
**66 passing tests**, including existing Sources focus/streaming/cache selection,
source ordering, previous Sources slices and new controller, real preference and
actual screen startup cases. Both completion orders, overlapping loads, failure
behavior, immutable publication, profile/disposal/dependency retirement and the
search startup barrier are covered. The retiring-screen test uses bounded pumps:
its loading spinner intentionally continues until the handoff removes the route.
Analyzer identity comparison has **no additions and one removed legacy curly-brace
lint**, leaving **864 diagnostics**. Formatting/diff checks pass. Architecture
checks cover **69 migrated files**; Sources is 3,131 lines and its parent 20,144.
Receipts are `.git/refactor-evidence/phase4c/bound-before.txt`,
`settings-complete-focused.txt`, `analyze-settings-complete.txt` and
`settings-comparison.txt`. The latest full-suite checkpoint remains the preceding
season-guide integration (7,628 successes, same 51 failures and 20 skips); this
settings slice uses the affected suite and analyzer comparison.

Review of the next saved-source boundary found `SeriesSourceService.getSources`
also migrates legacy single-object records and custom catalog pins, including
cleanup/tombstone writes. Its extraction must cover those actual commit paths and
profile retirement, not assume the lookup is read-only. That work, Sources
results/retries/cache/pin actions, later phases and native/performance checks remain
outstanding. Phase 4C is still in progress.


### Phase 4C saved-source loading (implemented and reviewed)

`SavedSourcesController` (44 lines) owns the saved-pin/cached-episode snapshot.
`StoredSavedSourcesRepository` (81 lines) loads the existing pin list, filters its
catalog/configuration scope and checks the first direct pin against installed,
enabled streaming addons before consulting the resolved-link cache. The cache
key still uses the title, content type, season, episode and exact pin identity.
The actual screen consumes the snapshot through Riverpod and keeps selected-row
matching, focus, scrolling and diagnostics in the view. Cached-row and streaming
focus behavior remains covered by the original screen tests. Initialization does
not read data; explicit reloads reject older requests and retired sessions.
Current read failures retain the previous snapshot and propagate without retries.

The existing `SeriesSourceService` migration remains the implementation for
single-object and custom-catalog legacy pins. Its optional continuation predicate
checks interactive ownership around delayed reads and before preference writes,
including writes queued behind the preference snapshot barrier. Existing callers
without the predicate preserve their behavior. The adapter clears inherited
captured-scope zones for these interactive migrations so the preferences facade's
own live-profile checks remain effective. Existing tombstone recording retains its
original profile identity/order; cleanup checks retirement before removing pins.
The service is 463 lines, one existing persistence responsibility, and no format or
schema migration was introduced. Only touched service methods were formatted.

Before this slice, the affected legacy migration/provider and screen tests passed.
The combined affected suite now has **100 passes**. Seven new repository cases
use real preferences and a real in-memory profile registry: original single-pin
migration, custom scope/order/cleanup/tombstone identity, both migrations queued
behind an exclusive snapshot during profile switch or lifecycle clear, and a
profile switch during cleanup. The tests remove the outgoing preference key before
releasing queued writes and prove neither profile's deleted key is recreated.
Controller cases cover explicit loading, overlapping reloads, current failure,
profile/disposal/dependency retirement and late errors. Existing cached current-
episode cases exercise the real repository and original encrypted-link cache.

The initial screen run found a regression: an unmounted focus callback logged the
pin count by reading a closed Riverpod subscription. The view now captures only
that diagnostic count at disposal; it does not retain a second pin snapshot or
access disposed provider state. The same original cached-row tests pass afterward.
The first committed-profile fixture needed the real registry and a test device
cipher to reach the production migration; the corrected tests run that path.
Receipts are `.git/refactor-evidence/phase4c/bound-migrations-before.txt`,
`saved-screen.txt`, `saved-screen-fixed.txt`, `saved-migrations-final.txt` and
`saved-complete-focused.txt`.

The exact full helper completed in **173,947 ms** with **7,658 successes**, the
same **51 baseline failures** (22 failure/29 error outcomes), and **20 skips**.
Identity comparison finds no new failures, missing baseline tests or newly skipped
cases. The unchanged historical helper allowance still yields exit 1. Final
analyzer comparison has no additions and the previously removed Sources curly-brace
lint, leaving **864 diagnostics**. The architecture guard passes **74 migrated
files**, formatting and diff checks pass, and Sources is **3,105 lines** (parent
20,145). The full run started before a final `mounted` guard was added to the view's
reload wrapper; its 19 affected screen/controller cases passed afterward. That
guard prevents pin/unpin completion from reading WidgetRef after route disposal.
A brace-only formatting fix also removed a newly exposed service lint before the
final analyzer run. Receipts are `phase4c/full-saved.jsonl`,
`full-saved-comparison.txt`, `saved-disposal-final.txt`,
`analyze-saved-disposal.txt` and `saved-disposal-analyzer-comparison.txt` under
`.git/refactor-evidence/`.

Phase 4C remains in progress:
search/results, retry orchestration, availability-cache checks and pin/local actions
still need extraction, followed by remaining Home/Discover/lifecycle work and native,
visual/performance checks. Saved-source focus/reveal remains view-owned.


### Phase 4C source cache checks (implemented and reviewed)

`SourceCacheController` (126 lines) owns the Sources workflow's cache generations,
provider flags, immutable badge maps and post-success hash memoization. The screen
now dispatches configuration, new-search reset and batch/completion/adopt checks;
it no longer holds provider credentials, maps or checked-hash sets. Its old
cache-check implementation is removed. `DebridSourceCacheRepository` (91 lines)
reads the same six preferences concurrently and owns the credential-bearing
session. Calls retain the original TorBox and Premiumize protocols, with no new
retry framework or dependency. Profile ownership and disposal reject stale work;
a late failure also cannot dispatch the next provider under an incoming profile.

This remains a Sources-specific controller because its observed behavior differs
from keyword cache filtering: only real hashes are eligible; hashes are trimmed
and lowercased; duplicates and overlapping in-flight dispatch remain allowed;
TorBox runs before Premiumize; short Premiumize responses mean false for missing
positions; badge maps merge across batches. Hashes become memoized only after
both enabled providers succeed. A failure retains the other provider's badges
and allows a later batch or completion sweep to retry. A new search clears badges
and memoization without reloading credentials; a pending initial configuration
still applies and causes the screen to sweep the current rows.

The immutable state carries an explicit repaint revision to preserve the original
notification timing. Provider map updates are immediately readable, but the screen
requests a repaint after both sequential attempts finish, just as the old method
did. Reset/configuration do not add independent repaints. This does not introduce a
second copy of badge state in the widget or reorder/filter rows when badges arrive.

The initial 12 affected screen/startup tests passed before extraction. The final
combined affected run has **112 passes**. New controller cases cover normalization,
synthetic/blank hashes, duplicates, sequential notification timing, short responses,
partial failures and retry eligibility, additive badges, query resets, overlapping
configuration, late configuration and profile/disposal/dependency retirement of
both success and failure. Data tests verify each enabled/preference/key requirement,
credential snapshots and RPC arguments, and rejection before retired dispatch.
A real Sources widget test proves configuration arriving after results sweeps both
rows, renders `TB | PM` for the cached result, preserves row order and retains row-
zero focus. Unrelated startup settings are injected so that test does not depend on
filesystem engine initialization. Existing cached-episode and streaming-focus tests
remain in the affected run.

Analyzer comparison has no additions and the previously removed Sources lint,
leaving **864 diagnostics**. Architecture checks cover **79 migrated files**;
formatting/diff checks pass. Sources is **3,014 lines**, its parent **20,145**.
Receipts are `.git/refactor-evidence/phase4c/cache-before.txt`,
`cache-complete-focused.txt`, `cache-screen-integration-fixed.txt`,
`analyze-cache-final.txt` and `cache-final-analyzer-comparison.txt`.
The exact full helper completed in **173,283 ms** with **7,688 successes**, the
same **51 observed baseline failures** (22 failure/29 error outcomes), and
**20 skips**. Identity comparison finds no new failures, missing baseline tests
or newly skipped cases. The historical helper allowance is unchanged and still
exits 1. Full receipts are `.git/refactor-evidence/phase4c/full-cache.jsonl`,
`full-cache.helper.txt` and `full-cache-comparison.txt`.

Phase 4C remains in progress. Results/search state, individual retries and pin/local
source actions still need extraction; focus, rendering and scrolling stay in the
view. Later Home/Discover/lifecycle phases and native/visual/performance checks
remain outstanding.


### Phase 4C initial source request boundary (implemented and reviewed)

`ServiceSourceSearchRepository` (166 lines) now owns the initial request's custom
video-ID resolution, engine/addon search and concurrent IPTV lookup. The production
screen dispatches a typed `SourceSearchRequest`, receives immutable batch/result
lists and retains presentation, source-status ordering, freeze/pending behavior,
cache dispatch and focus. Legacy service maps stay within the data adapter and its
small RPC typedef file; no new transport, timeout or retry implementation was added.
The repository borrows the existing services and starts no IO when constructed.

Routing and request fields retain their behavior: exact keyword queries use engines
only, including an empty keyword; IMDb/content-type requests preserve source order,
movie/series and episode coordinates, known seasons and originating addon/video ID.
Custom episode metadata resolves before search; an unresolved custom video suppresses
search instead of guessing an IMDb episode. IPTV is skipped for keyword, custom
identity and the existing test override. Otherwise it starts beside the main request,
publishes status before its batch, and final results await it and append IPTV rows
after the main rows. Snapshots preserve Torrent identities, including IPTV's existing
per-Torrent authorization. No extra await is introduced when IPTV is absent.

Live owner/request checks stop later RPC dispatch and callbacks after retirement.
Completion closes the request's callback gate, so timed-out provider work cannot
publish afterward. A late IPTV error is observed even if the main request has already
failed; when the main request succeeds, an IPTV failure still propagates. Current
errors remain errors and no automatic retry was introduced. The request snapshots
known seasons at dispatch; only episode selections can await video resolution, and
those do not load a season-chip inventory, so that snapshot retains the prior input.

The existing `sourcesScreenForTesting` signature remains compatible. It now composes
a nested ProviderScope overriding the repository's legacy engine callback, rather
than adding a test-only callback field to the production widget. Raw-map conversion
stays in the adapter. Production screens use the normal feature provider factory.
The helper remains in the registered legacy file until the presentation/facade move;
its adapter construction is test composition, not production widget data access.

The 13 existing screen/startup/cache tests passed before extraction. The first run
caught a cached-fallback completion timing regression caused by awaiting an empty
IPTV future. Restoring the original nullable/no-await path fixed it; every original
assertion remains unchanged. The final affected run has **181 passes**, covering
Sources state/data/widget tests and existing direct-episode, IPTV, source-priority
and streaming-search behavior. Thirteen new repository tests cover RPC flags and
order, exact custom IDs, unresolved IDs, input/output snapshots, concurrent IPTV,
status-before-batch callbacks, final concatenation, late callback rejection, request/
profile retirement and both error paths. The final analyzer has **864 diagnostics**,
with no additions and the previously removed Sources lint. Architecture checks cover
**85 migrated files**; format/diff checks pass. Only the touched screen/helper blocks
were formatted. Sources is **2,958 lines**, its parent **20,148**.

Receipts are `.git/refactor-evidence/phase4c/request-before.txt`,
`request-screen.txt`, `request-screen-fixed.txt`, `request-data-tests.txt`,
`request-complete-focused.txt`, `analyze-request-complete.txt` and
`request-final-analyzer-comparison.txt`. The first full run (`phase4c/full-request`, 173,449 ms) had 7,700 successes and
one additional failure: `self_profile_settings_page_test.dart::identity save
persists without changing access` read the old name after its fixed wait. The
unchanged profile-settings file then passed all five tests in isolation
(`request-profile-isolated.txt`). No failure allowance or profile test was changed.
The confirmation full run on the same application code completed in **173,934 ms**
with **7,701 successes**, the same **51 baseline failures** (22 failure/29 error
outcomes), and **20 skips**. The profile-name test passed. All identities from the
preceding full-cache checkpoint retain their outcomes, with no missing tests and
13 new passing identities. Comparison against the original observed baseline also
finds no new failures or newly skipped tests. The historical helper allowance is
unchanged and still exits 1. This supports treating the initial profile-save result
as a transient test outcome; the two runs and isolated result remain recorded,
rather than adding it to the baseline allowance. Final receipts are
`phase4c/full-request-confirmation.jsonl`,
`phase4c/full-request-confirmation-comparison.txt` and
`phase4c/request-confirmation-previous-checkpoint.txt` under
`.git/refactor-evidence/`.

Phase 4C remains in progress. The view still owns search/result state, provisional
batch accumulation and presentation coordination; initial request IO is now outside
it. Individual retry orchestration and pin/local-source actions remain too. Later
Home/Discover/lifecycle phases and native/visual/performance checks are outstanding.


### Phase 4C individual addon retries (implemented and reviewed)

`SourceRetryController` (65 lines) now owns the immutable set of in-flight addon
configuration keys and its search generation. Explicit retries suppress duplicate
taps for one configuration while permitting independent addons. New searches clear
retry state; an old same-key completion cannot clear a newer retry. Errors clear
the current busy state without automatic retry and leave the existing chip as the
error indicator. Provider construction/recomputation does not dispatch requests.
The view retains the media-server full-search branch, source-status presentation,
stream merging, cache dispatch and frozen-result/focus behavior.

`ServiceSourceSearchRepository` now exposes a typed retry operation as well as the
initial search (240 lines total). It preserves configuration-specific request keys,
content-type fallback, movie/series coordinates, the existing one-minute manual
retry timeout, source order and exact custom video IDs. Missing custom IDs remain
unavailable rather than being guessed. Profile/request checks after metadata
resolution prevent a retired retry from starting the next RPC. Completed rows are
immutable snapshots. Existing services retain transport and timeout ownership.

The retry provider declares its scoped repository dependency so the existing test
composition and production provider resolution agree. `sourcesScreenForTesting`
keeps its existing required arguments and gains an optional retry RPC override;
production widgets have no test callback field. The screen no longer owns a mutable
retry set or directly invokes retry metadata/stream APIs.

The 23 existing screen/initial-request tests passed before extraction. The final
affected suite has **201 passes**, including the existing Sources, direct-episode,
IPTV, streaming and source-priority tests. Nine new controller cases cover concurrent
configuration keys, duplicate taps, failure, generation replacement and profile/
disposal/dependency retirement of results and errors. Ten new data cases cover exact
RPC arguments, custom IDs/resolution, stale resolution and stale failures. The real
Sources widget test selects the failed provider using Select, repeats Select while
busy, verifies one RPC, preserves actual rail focus, updates the status and holds
recovered rows behind the pending-results button until adoption. Its first remote
version used a mismatched generic ValueKey type; the corrected locator identifies
the actual Focus node by debug label and retains all behavior assertions.

Analyzer identity comparison has no additions and the previously removed Sources
lint, remaining at **864 diagnostics**. Architecture checks cover **86 migrated
files**; formatting and diff checks pass. Only changed screen blocks were formatted.
Sources is **2,931 lines**, and the parent is **20,150**. Receipts:
`.git/refactor-evidence/phase4c/retry-before.txt`, `retry-controller.txt`,
`retry-new-tests.txt`, `retry-screen-remote.txt`, `retry-final-focused.txt`,
`analyze-retry-complete.txt` and `retry-final-analyzer-comparison.txt`.
The exact full helper completed in **172,369 ms** with **7,721 successes**, the
same **51 baseline failures** (22 failure/29 error outcomes), and **20 skips**.
No original baseline test is newly failing, missing or newly skipped. Every test
from the previous request-confirmation checkpoint retains its outcome, with 20
new passing identities. The historical helper allowance is unchanged and still
exits 1. Full receipts are `.git/refactor-evidence/phase4c/full-retry.jsonl`,
`full-retry-comparison.txt` and `retry-previous-checkpoint.txt`.

Phase 4C remains in progress: search/result state, provisional result accumulation,
filter/sort projection and pin/local-source actions remain. Rendering, scrolling
and focus stay view-owned. Later Home/Discover/lifecycle phases and native/visual/
performance checks remain outstanding.


### Phase 4C — Sources toolbar result projection

Moved the production `_applyToolbar` algorithm into the 63-line
`application/source_result_projection.dart`. The widget passes explicit filter,
provider configuration and sort values; it retains focus, buffering and render
ownership. The result is an immutable list preserving the original Torrent
identities. Reviewed all Sources list uses: neither `_visible` nor `_torrents`
mutates its published list in place. Source filtering and quality facets still
precede priority/deduplication, series still ignore only the size facet, and
explicit field sorts run last. The old screen implementation and now-unused
parent filter-matcher import are removed.

Before extraction, the existing cinema focus, priority and season tests passed
**32 tests**. After extraction, all Sources feature tests plus those three suites
passed **160 tests**, including nine new projection cases. New coverage verifies
alias filtering before cross-provider deduplication, eligible duplicate selection,
series facet behavior, priority-selected identity before sorting, both directions
for all four explicit sorts, stable provider order and immutable snapshots.
Existing screen tests retain their focus and pending-results assertions.

Analyzer comparison reports **864 diagnostics**, no additions, and only the same
previously removed Sources curly-braces lint against the original baseline.
Architecture checks pass for **87 migrated files**. New files are formatted;
diff review/check passes. Sources is **2,892 lines**; parent stays **20,150**.
Receipts: `.git/refactor-evidence/phase4c/projection-before.txt`,
`projection-focused.txt`, `analyze-projection.txt` and
`projection-analyzer-comparison.txt`. The full suite was not rerun for this bounded
pure-policy extraction; the latest full run remains the retry checkpoint above.

Review identified the shared matcher's transitive UI imports and priority helper's
legacy service dependencies. Their pure calls remain shared to avoid classifier
changes during extraction; the plan explicitly requires separating these before
the final boundary audit. Phase 4C remains open for search/result state, streamed
result preparation, pin/local actions and presentation extraction. Later phases,
native behavior and performance checks are also still pending.


### Phase 4C — Streamed Sources result preparation

Moved the production batch-preparation algorithm into the 80-line
`application/source_result_preparation.dart`. The widget still rejects stale
search tokens before invoking it and owns pending-result buffering, focus and
rendering. The policy returns an immutable list with original Torrent identities
and a flag for the existing cached-row diagnostic. Cached fallback insertion still
happens before buffering, only on search completion, using only the first saved
source and the existing exact configuration/binge-group/profile selector.
Episode-scoped queries still retain all returned rows; series-pack eligibility,
IPTV binding exceptions and same-addon direct-first order remain unchanged.

The baseline cinema-focus and season-policy suites passed **24 tests**. All Sources
feature, cinema-focus, priority and season-filter tests passed **166 tests** after
extraction. Six new preparation cases cover row identity/order/nonmutation,
completion-only cache fallback, exact configuration and binge-group behavior,
first-pin eligibility and whole-series IPTV binding. Existing screen tests verify
pending fallback counts and focus behavior. Analyzer review caught an unnecessary
non-null assertion made redundant by the new local parameter; removed it without
changing behavior and reran analysis.

Shared legacy pure selection and model dependencies are recorded in the plan's
transitive-boundary exception; the direct-import guard alone does not resolve it.
Sources is **2,847 lines**, parent **20,151**. Formatting and diff checks pass;
architecture checks cover **88 migrated files**. Receipts:
`.git/refactor-evidence/phase4c/preparation-before.txt`, `preparation-focused.txt`,
`analyze-preparation.txt` (intermediate diagnostic) and
`analyze-preparation-final.txt`.


Final analyzer comparison has no additions: **864 diagnostics**, preserving the
prior checkpoint. The exact full-suite helper completed in **172,948 ms** with
**7,736 successes**, the same **51 observed baseline failures** (22 failure/29
error) and **20 skips**. No baseline test is newly failing, missing or skipped;
every identity from the retry checkpoint retains its outcome, with **15 new
passing identities** from toolbar projection and preparation. The historical
allowance file is unchanged and the helper still exits 1 for those pre-existing
failures. Full receipts: `.git/refactor-evidence/phase4c/full-preparation.jsonl`,
`full-preparation-comparison.txt`, `preparation-previous-checkpoint.txt` and
`preparation-analyzer-comparison.txt`.

Phase 4C remains in progress for search/result state, pin/local actions and Sources
presentation. Later Home/Discover/lifecycle work, native checks, performance
comparisons and the final architecture/CI audit are not yet complete.


### Phase 4C — Sources search state and batch orchestration

Added `SourceSearchController` (128 lines) and immutable `SourceSearchState`
(19 lines), wired into the actual Sources view through a manual Riverpod
subscription. The controller owns searching/error state, addon/IPTV outcomes,
ordered status filtering, accumulated engine batches and retry-result merging.
Production no longer stores competing copies of those fields or invokes the
search repository directly. Accepted row callbacks hand results to the existing
presentation path; cache callbacks retain batch timing. The controller starts no
work during construction, disables automatic retries and retires work on request
generation, dependency replacement, profile retirement and disposal.

The view retains its mounted/token cancellation callback through the repository,
including the auto-disposal grace period. It owns focus nodes, loading visibility,
prepared/rendered/frozen rows and cache/season presentation actions. A disposed
boolean is captured solely for already-scheduled focus diagnostics, avoiding a
read from a closed subscription. No new retained credential or row snapshot is
introduced for logging. Settings are immutable and loaded before search begins,
so passing priority/aliases at invocation preserves their completion-time values.

Review preserved the existing retry contract: retries merge accumulated batches,
not final-only rows from the authoritative response. Final search completion
still replaces provisional raw rows before preparation/buffering. Empty batches
are ignored; empty successful retries clear failure state. Current errors keep
IPTV outcomes and stop searching. Late batches after completion cannot publish.

Baseline Sources feature/cinema suites passed **144 tests**. The same integration
suite passed after wiring. Final affected Sources/cinema/priority/season run
passed **177 tests**, including **11 new controller cases** for explicit startup,
provisional/final behavior, status priority, rapid searches, current/stale errors,
retry identity and accumulation, caller cancellation, profile retirement,
disposal and dependency replacement. The initial dependency test returned the
same repository instance after invalidation, so it did not cause a dependency
change; the fixture now replaces the repository and retains the stale-callback
assertions. No existing test assertions or failure allowance were changed.

Analyzer identity comparison adds no diagnostics (**864**, same prior checkpoint).
Architecture passes for **90 migrated files**. New files are formatted; changed
screen blocks and diffs are reviewed. Sources is **2,778 lines**, parent **20,153**.
Receipts: `.git/refactor-evidence/phase4c/search-state-before.txt`,
`search-state-integration.txt`, `search-state-controller.txt` (fixture failure),
`search-state-controller-final.txt`, `search-state-focused-final.txt`,
`analyze-search-state-final.txt`, and `search-state-analyzer-comparison.txt`.

The plan retains a concrete phase-8 exception for pure merge/priority operations
still housed in legacy service files. Direct-import checks do not establish
transitive purity. Rendered/frozen result state, pin/local actions, Sources UI,
later phases and native/performance verification remain unfinished.


The exact full helper completed in **172,731 ms** with **7,747 successes**, the
same **51 observed baseline failures** (22 failure/29 error) and **20 skips**.
No baseline identities are newly failing, missing or skipped. Every identity
from the preparation checkpoint retains its outcome, with **11 new passing
controller cases**. The historical allowance remains unchanged and the helper
still exits 1 for pre-existing failures. Full receipts:
`.git/refactor-evidence/phase4c/full-search-state.jsonl`,
`full-search-state-comparison.txt`, and `search-state-previous-checkpoint.txt`.


### Phase 4C — Adopted/pending Sources result ownership

Added the 60-line `SourceResultsController` and 31-line immutable
`SourceResultsState`. The actual Sources view now reads adopted rows, pending rows,
freeze state and the pending-row count from the session/view-owned Riverpod state.
The replaced mutable fields and row-key/count implementation are removed. The
controller has explicit begin, freeze, buffer and display actions and starts no
IO. It rejects actions for retired owners and after disposal; scope invalidation
clears its rows. Distinct views for the same title have independent state.

Review preserved full-set replacement rather than pending-batch accumulation,
empty pending replacements, case-insensitive real-hash keys and exact name/URL
fallback keys. Repeated new identities still count once per pending row, as before.
Adoption clears pending rows but remains frozen. New search clears both sets and
resumes streaming. Lists are immutable snapshots with original Torrent identities.
The screen captures old row focus before display/adoption, and retains toolbar
projection, focus-node synchronization, loading visibility and cache/season actions.
On scope retirement, its remaining projected list is cleared with focus nodes
retired through the existing post-frame path. Post-disposal diagnostics capture
only counts/index/boolean values before subscriptions close, not retained raw rows.

Baseline Sources feature/cinema tests passed **155 tests**, and that integration
suite passed after wiring. Final affected Sources/cinema/priority/season run
passed **186 tests**, including nine controller cases for buffering/adoption,
reset, immutable identity-preserving snapshots, smaller replacements, hashless
keys/duplicate counts, repeated freeze/empty pending, view isolation, profile
retirement and disposal. Existing cinema tests retain their focus and pending-row
assertions. Final analysis remains at **864 diagnostics**, with no additions;
architecture checks pass for **92 migrated files**. New files and changed screen
methods are formatted, with no whole-file formatting. Diff checks pass.

Sources is **2,782 lines**, parent **20,155**: subscription/disposal wiring replaces
private state ownership rather than just reducing line count. Toolbar projection
state and the remaining Sources actions/UI are still part of Phase 4C. Later
phases and native/performance checks remain unfinished.
Receipts: `.git/refactor-evidence/phase4c/result-state-before.txt`,
`result-state-integration.txt`, `result-state-controller.txt`,
`result-state-focused-final.txt`, `analyze-result-state.txt`, and
`result-state-analyzer-comparison.txt`.


The exact full-suite helper completed in **172,759 ms** with **7,756 successes**,
the same **51 observed baseline failures** (22 failure/29 error) and **20 skips**.
No original baseline test is newly failing, missing or skipped. All search-state
checkpoint identities retain their outcomes, with **nine new passing tests**.
The historical allowance file remains unchanged; the helper still exits 1 for
pre-existing failures. Full receipts:
`.git/refactor-evidence/phase4c/full-result-state.jsonl`,
`full-result-state-comparison.txt`, and `result-state-previous-checkpoint.txt`.
Phase 4C and later migration/device/performance gates remain open.


### Phase 4C — Sources toolbar state and provider reconciliation

Extended the existing `SourceResultsController` (now 131 lines) with toolbar
selection actions and projection through the already-tested Sources policy.
The 33-line immutable `SourceToolbarState` belongs to `SourceResultsState`
(now 34 lines), avoiding a separate controller for four related settings. The
production view no longer owns mutable provider/filter/sort fields. All existing
cinema rail, source pill, sort direction, filter dialog and clear-filter actions
use this state. A disposed provider-filter boolean preserves diagnostic access
without reading a closed subscription.

New searches preserve toolbar choices while clearing adopted/pending/frozen rows.
Freeze, buffering and adoption retain the same toolbar snapshot. Provider
reconciliation still runs only at completion, against the full authoritative
set including pending rows, using the same aliases; a quality filter hiding a
provider does not clear its selection. The screen retains the exact explicit
adoption/focus/scroll actions after toolbar changes and derives its rendered list
through the controller's pure projection call. No persistence or request behavior
was added.

Baseline and post-wiring Sources feature/cinema suites passed **164 tests**.
Final affected Sources/cinema/priority/season run passed **191 tests**, including
five new toolbar cases covering reset preservation, pending-row lifetime,
alias-aware final reconciliation, current-state projection/filter clearing and
retired-profile rejection. Existing focus and pending-row assertions are unchanged.
Analysis caught a missing-braces lint in the extracted reconciliation condition;
adding braces preserved its control flow. Final analysis returns to **864
diagnostics**, with no additions against baseline. Architecture checks pass for
**93 migrated files**, formatting and diff checks pass. Sources is **2,771 lines**;
parent stays **20,155**.

Receipts: `.git/refactor-evidence/phase4c/toolbar-state-before.txt`,
`toolbar-state-integration.txt`, `toolbar-state-focused-final.txt`,
`analyze-toolbar-state.txt` (intermediate lint), `analyze-toolbar-state-final.txt`,
and `toolbar-state-final-analyzer-comparison.txt`.
Pin/local actions, Sources UI/focus extraction, later phases, native/performance
checks and final transitive-boundary/CI verification remain open.


The exact full-suite helper completed in **175,996 ms** with **7,761 successes**,
the same **51 observed baseline failures** (22 failure/29 error) and **20 skips**.
No original baseline identity is newly failing, missing or skipped. Every result-
state checkpoint identity retains its outcome, with **five new passing tests**.
The historical allowance remains unchanged and the helper still exits 1 for
pre-existing failures. Full receipts:
`.git/refactor-evidence/phase4c/full-toolbar-state.jsonl`,
`full-toolbar-state-comparison.txt`, and `toolbar-state-previous-checkpoint.txt`.
Phase 4C and later migration/device/performance gates remain unfinished.


### Phase 4C — Saved-source removal boundary

Wired production `_unpin` through `SavedSourcesController.remove` and
`StoredSavedSourcesRepository.remove`. The view no longer invokes the persistence
service directly. The existing controller/repository remain cohesive at **61/99
lines**. The adapter calls the existing binding-specific removal with the captured
owner's `canContinue` predicate, outside captured profile zones, preserving the
preferences facade's live-profile checks and existing guarded-write barrier.
Current errors propagate; retired operations return false and do not reload.
The underlying service, storage schema, binding-key matching and tombstone
implementation are unchanged.

An explicit removal remains repository-owned if the view closes; the controller
checks liveness, repository identity and owner before reloading. Independent
removals do not invalidate each other's writes through the read-generation guard.
The existing reload generation still handles competing reads. Pin/local binding
calls require a separate presentation bridge because they involve dialogs and
platform picking; they remain outstanding rather than being hidden in a data
adapter taking BuildContext.

The existing saved-source repository/controller and cinema focus baseline passed
**26 tests**. After extraction all Sources feature/cinema tests passed **175
tests**. Six new cases exercise remove-before-reload ordering, completion after
view disposal, stale/current error handling, exact binding removal/last-key
cleanup/origin tombstone recording, and actual queued writes during profile
switching or lifecycle retirement. Queued tests delete outgoing data while the
write barrier is held and verify it is not recreated and incoming profile data
is untouched. No failure allowance or existing assertion was changed.

A missing-braces lint introduced in the new controller guard was corrected; final
analysis remains **864 diagnostics** with no new identities. All five changed
feature/test files pass formatting, architecture checks pass for **93 migrated
files**, and diff checks pass. Sources remains **2,771 lines**, parent **20,155**.
Receipts: `.git/refactor-evidence/phase4c/unpin-before.txt`, `unpin-focused.txt`,
`analyze-unpin.txt` (intermediate lint), `analyze-unpin-final.txt`, and
`unpin-final-analyzer-comparison.txt`.
The full suite was not repeated for this bounded adapter/action change; its latest
checkpoint remains the toolbar-state run above. Phase 4C pin/local binding and UI,
later phases, native/performance checks and the final architecture audit remain
unfinished.


### Phase 4C — Shared binding value model

Tracing pin/local-source calls confirmed that their value contract still lived
inside the preferences service. Extracted `SeriesSource` into the shared
`lib/models/series_source.dart` (198 lines), preserving its complete class body.
The old service imports/re-exports the same type for existing callers and is now
268 lines. Migrated Sources state, controller, repository contract and preparation
policy import the model directly. The stored repository imports the model plus
only `SeriesSourceService` from the service library. This closes the recorded
model-to-storage dependency exception without migrating unrelated consumers or
introducing a second binding representation.

Reviewed all transitive model imports: dart:convert, crypto, the pure
`MediaServerSource` value model and pure catalog-scope hash helper. No preferences,
HTTP, platform, UI or Riverpod dependency remains in this value-model graph.
Registered the extracted shared model in `EXTRACTED_ELSEWHERE` so its size/import
requirements cannot disappear outside the feature directory. Architecture checks
now cover **94 migrated files**. Legacy exports preserve source compatibility and
all callers use the same Dart class identity.

Existing provider-native binding, addon-direct binding and Sources feature tests
passed **186 tests** both before and after extraction. No new behavior or storage
format was introduced; a separate mechanical comparison proves the entire
formatted class body is identical to the pre-extraction HEAD, covering key
construction, hashing, JSON fields/defaults and matching methods in addition to
the existing executable coverage. No assertions or failure allowance changed.
Analysis remains **864 diagnostics** with no new identities. Changed Dart files
are formatted and diff checks pass. Sources and parent remain **2,771/20,155 lines**.
Receipts: `.git/refactor-evidence/phase4c/binding-model-before.txt`,
`binding-model-focused.txt`, `binding-model-body-comparison.txt`,
`analyze-binding-model.txt`, and `binding-model-analyzer-comparison.txt`.

Pin/local UI workflows and their remaining data/platform boundaries are still
outstanding. The other transitive-helper exceptions, later migration phases,
native/performance validation and final CI audit remain open.


The exact full-suite helper completed in **174,141 ms** with **7,767 successes**,
the same **51 observed baseline failures** (22 failure/29 error) and **20 skips**.
No baseline identity is newly failing, missing or skipped. All toolbar-state
checkpoint outcomes are preserved; the six new passing identities are the unpin
cases from the preceding slice. The historical allowance is unchanged and the
helper still exits 1 for pre-existing failures. Full receipts:
`.git/refactor-evidence/phase4c/full-binding-model.jsonl`,
`full-binding-model-comparison.txt`, and `binding-model-previous-checkpoint.txt`.
Phase 4C and later migration/device/performance gates remain incomplete.


### Phase 4C — Shared pin/local binding action orchestration

Added the 53-line `SourceBindingController` and wired both production pin and local
binding paths into it. A single Riverpod busy flag replaces `_pinning`, prevents
concurrent operation callbacks, and stays busy through the saved-source reload.
Construction is inert and automatic retries are disabled. The controller watches
the borrowed saved-sources notifier to keep reload alive, and guards its own
completion using profile/view lifetime and generation. Cancelled operations do
not reload; operation/reload errors propagate while the live action releases its
gate. A retired completion cannot clear a replacement action's busy flag.

Dialogs/pickers, transport dispatch, external-link messaging and final route pop
remain in presentation. The actual legacy binding functions and their arguments
are unchanged. This does NOT establish that all writes or RPCs inside those
functions are profile-safe: their internal async persistence/native boundaries
and the final presentation bridge still need review before phase completion.
The new controller guards dispatch/reload/completion, not unseen work inside the
callback. No BuildContext or navigator is imported into application code.

Baseline Sources/cinema suites passed **175 tests**. Broader existing Sources,
cinema, addon-direct and IPTV integration tests passed **222 tests** after wiring.
Final affected run passed **232 tests**, including nine new controller cases for
busy/reload ordering, duplicate rejection, cancellation, current errors, view/
profile/disposal retirement and replacement-action ownership. A new actual
Sources menu test pins a direct row, verifies its refresh descriptor omits the
temporary URL, verifies reload changes the menu to Unpin, and removes the binding
through that menu. Its first fixture used a dynamic empty addon-status list,
violating the legacy callback's typed list contract; an attempted startup wait
was not the fix. Tracing identified the cast error. Omitting that optional field
uses the existing empty default and preserves all persistence/menu assertions.
All temporary tracing was removed. No existing tests or failure allowance changed.

Final analysis remains **864 diagnostics**, with no new identities. Architecture
passes for **95 migrated files**; new files and touched screen methods are
formatted, and diff checks pass. Sources is **2,766 lines**, parent **20,156**.
Receipts: `.git/refactor-evidence/phase4c/binding-action-before.txt`,
`binding-action-integration.txt`, `binding-action-controller.txt`,
`binding-action-screen-trace3.txt` (fixture diagnosis),
`binding-action-screen-typed.txt` (passing menu test),
`binding-action-focused-final.txt`, `analyze-binding-action-final.txt`, and
`binding-action-analyzer-comparison.txt`.
Remaining Phase 4C binding UI/data separation and native checks, Sources UI/focus
extraction, later phases and the final architecture/performance/CI audit remain
unfinished.


The exact full helper completed in **176,033 ms** with **7,777 successes**, the
same **51 observed baseline failures** (22 failure/29 error) and **20 skips**.
No baseline test is newly failing, missing or skipped. Every binding-model
checkpoint identity retains its outcome, with **10 new passing tests**. The
historical allowance is unchanged and the helper still exits 1 for pre-existing
failures. Full receipts:
`.git/refactor-evidence/phase4c/full-binding-action.jsonl`,
`full-binding-action-comparison.txt`, and `binding-action-previous-checkpoint.txt`.
Phase 4C and later migration/device/performance gates remain unfinished.


### Phase 4C — Profile-owned binding persistence

Sources now passes a generation/view-checked writer into the four existing manual
binding entry points (torrent, addon/media-server direct, IPTV and local). The
69-line `SourceBindingController` supplies the writer through its operation
contract and closes it as soon as the operation returns, including failure.
A retained callback cannot save after completion or retirement. It delegates
accepted writes to the 125-line `StoredSavedSourcesRepository`, which owns the
captured Sources session and preserves movie replacement versus series
append/stable-binding deduplication. Saved-source reload remains once per successful
live action; the final view pop also rechecks originating owner after its await.

The repository runs outside foreign captured zones and passes owner checks into
`SeriesSourceService.addSource/setSources`. Both methods now accept optional
`canContinue` callbacks, propagate them into reads/migrations, recheck after awaited
work (including replacement tombstones), and use the existing guarded write
barrier. Thus a queued write cannot recreate deleted outgoing-profile data or
target an incoming profile. An accepted persistence operation remains owned by
its originating repository; view closure alone does not retarget it. Current
storage errors propagate, while retired operations return false.

Legacy manual bind callers may omit the writer and retain the prior persistence
policy through `_persistManualBinding`. The existing dialogs, descriptor creation,
loader cleanup and native picker calls remain in `TorrentPlaybackService` under
the explicitly recorded transitional exception. This does not complete their
provider/RPC/native ownership review or the presentation bridge extraction.
The service is **8,868 lines** (was 8,828); only its four manual binding methods
and a small compatibility writer changed. `SeriesSourceService` is **280 lines**.
No schema or default auto-play binding policy was changed.

Baseline and initial integration passed **238 tests**. Final affected Sources,
cinema, addon-direct, IPTV and provider-native binding run passed **250 tests**.
Twelve new cases cover movie/series save policy, four real queued-write/profile
retirement combinations, retirement during movie tombstone recording, foreign
captured-zone handling, accepted writer lifetime and three pre-write retirement
cases. The existing real Sources pin/unpin menu test additionally spies on the
injected repository and verifies exactly one repository save while retaining its
secret-free descriptor and menu/persistence assertions. That strengthened screen
test also passed independently. No existing assertions or failure allowances were
weakened.

Review fixed four missing-braces diagnostics in touched legacy blocks (including
one exposed by normal formatting). Final analysis returns to **864 diagnostics**
with no new identities. Architecture checks pass for **95 migrated files**;
changed feature/test files and touched legacy methods are formatted, and diff
checks pass. Sources is **2,775 lines**, parent **20,156**. Receipts:
`.git/refactor-evidence/phase4c/binding-save-before.txt`,
`binding-save-integration.txt`, `binding-save-new-tests.txt`,
`binding-save-focused-final.txt`, `binding-save-wired-screen.txt`,
`analyze-binding-save.txt` (intermediate lints), `analyze-binding-save-final.txt`
and `binding-save-analyzer-comparison.txt`.
Phase 4C UI/native/provider preparation boundaries, Sources UI/focus extraction,
later phases and final native/performance/CI audits remain unfinished.


The exact full-suite helper completed in **176,285 ms** with **7,789 successes**,
the same **51 observed baseline failures** (22 failure/29 error) and **20 skips**.
No original baseline identity is newly failing, missing or skipped. Every binding-
action checkpoint outcome is preserved, with **12 new passing tests**. The
historical allowance is unchanged and the helper still exits 1 for pre-existing
failures. Full receipts:
`.git/refactor-evidence/phase4c/full-binding-save.jsonl`,
`full-binding-save-comparison.txt`, `binding-save-previous-checkpoint.txt`,
`analyze-binding-save-complete.txt` and
`binding-save-complete-analyzer-comparison.txt`.
Phase 4C and later migration/device/performance gates remain incomplete.


### Phase 4C — Sources row-action sheet

Extracted the torrent/direct/external action sheets into the 116-line
`SourceRowActionsSheet`, wired through the actual Sources row-menu entry point.
The widget receives a captured theme, row kind, binding state and eligible action
callbacks. It owns only rendering and the existing input-guard → modal-pop →
action ordering. Eligibility and playback/persistence dispatch stay at the caller
until their remaining boundaries migrate. The replaced stream-specific sheet
method is removed; Sources is now **2,652 lines**, parent **20,157**.

Review compared all five row kinds (torrent, addon, IPTV, media server, external),
bound/unbound labels, icon colors, subtitle styles, optional copy/download actions
and sheet geometry against the original. Stream copy remains visible even when
its handler must report a missing link. Download eligibility is still evaluated
inside the modal builder. Media-server/IPTV ownership checks only inspect the
source prefix; evaluating them for a bound row has no side effects. Unchanged
legacy text retains the migration's localization exception.

The existing real Sources binding/menu and cinema-focus baseline passed **11
tests**, and passed again after wiring. Eleven new widget cases cover row
variants, unpin wording and keyboard activation for play/pin/copy/download,
including the active input guard and modal dismissal before callback dispatch.
The complete affected Sources/cinema/addon-direct/IPTV/provider-native group
passes **261 tests**. Analyzer identities remain at **864**, with no additions
against the initial baseline; the previously removed Sources braces lint stays
removed. Architecture checks pass for **96 migrated files**. Formatting and diff
checks pass. Receipts under `.git/refactor-evidence/phase4c/`:
`row-actions-before.txt`, `row-actions-integration.txt`, `row-actions-widget.txt`,
`row-actions-focused-final.txt`, `analyze-row-actions.txt` and
`row-actions-analyzer-comparison.txt`.

This completes the automated row-action-sheet slice only. Remaining Sources UI,
focus ownership, binding presentation/native/provider preparation, later phases,
and native/performance/CI gates are still open.

Full-suite verification completed in **174,385 ms**: **7,800 successes**, the same
**51 observed baseline failures** (22 failure/29 error), and **20 skips**. No
initial-baseline test is newly failing, missing or skipped. Every previous
binding-persistence checkpoint outcome is preserved, with **11 new passing
identities**. The unchanged historical helper still exits 1 for pre-existing
failures. Receipts: `.git/refactor-evidence/phase4c/full-row-actions.jsonl`,
`full-row-actions-comparison.txt` and `row-actions-previous-checkpoint.txt`.


### Phase 4C — Pending Sources pill presentation

Extracted `SourcePendingResultsPill` (110 lines) and wired the existing Sources
overlay to it. The widget receives the pending count, a borrowed focus node,
adoption and row-navigation callbacks, and a toolbar-navigation callback that
reports whether the key was handled. The view still owns adjacent row/filter
nodes and their disposal; Riverpod remains the owner of pending results. The
original inline rendering/key handler is removed. Sources is **2,578 lines**;
parent **20,158**.

Review preserved the Focus/ListenableBuilder/GestureDetector hierarchy, theme
colors, geometry, pluralization and shadow. Select/Enter/numpad Enter/gamepad A
adopt before requesting the current first row; Down only requests that row. Up
checks toolbar attachment at event time and bubbles in Classic where no funnel
is attached. Only KeyDownEvent triggers these actions, as before. Touch adopts
without forcing row focus. Neither the widget nor its provider owns a second
copy of result state or any focus-node lifetime. Unchanged text retains the
documented localization exception.

Baseline Sources, cinema-focus, row-focus lifecycle and scroll-anchor group:
**227 passes**. The same group plus nine new widget cases: **236 passes**. The
new cases exercise all four remote activation keys, touch versus key focus,
Down, attached/absent toolbar Up, repeat/release handling and reuse of the same
borrowed node after unmount. Existing real-screen frozen arrivals/cached fallback
and retry/adoption tests continue to pass. No tests or assertions were removed.
Analyzer comparison has **no added identities** (864 diagnostics); architecture
checks pass for **97 migrated files**. New files and the replaced caller are
formatted; diff checks pass. Receipts under `.git/refactor-evidence/phase4c/`:
`pending-pill-before.txt`, `pending-pill-widget.txt`, `pending-pill-focused.txt`,
`analyze-pending-pill.txt`, `pending-pill-analyzer-comparison.txt`.

This leaf extraction uses the immediately preceding full-suite checkpoint
(7,800 successes, unchanged 51 failures/20 skips); the full suite was not rerun
for this slice. This is automated evidence only, not native input/visual parity.
Phase 4C binding presentation/provider/native preparation, remaining UI/focus,
later phases, device/performance checks and final CI remain open.


### Phase 4C — Pending-pill shape-manifest follow-up

The next slice's broader baseline exposed a missed source-text guard in the
pending-pill extraction: `the sweep is still substantial` counted 489 calls in
its registered files because the moved `app.shape.brPill` was outside that list.
This test passed in the original baseline and preceding full-suite checkpoint,
so it was a regression in test-location coverage, not an accepted baseline
failure. The previous 236-test affected group did not include this guard.

Added the extracted `source_pending_results_pill.dart` to `kShapeResidue` with
zero bare radii. The guard again counts **490 calls**, its existing threshold
is unchanged, and the extracted component is now covered by the per-file bare
radius ratchet. An audit found no other unregistered feature files containing
`app.shape` calls. The original-baseline `no swept file grows a new bare radius`
failure remains; the other two manifest checks pass. Receipts:
`.git/refactor-evidence/phase4c/headers-before.txt` and
`pending-pill-shape-repair.txt`. No application code or failure allowance changed.

The confirming full suite has **7,809 successes**, the same **51 baseline
failures** (22 failure/29 error), and **20 skips**. All previous row-action
checkpoint outcomes are preserved; all nine pending-pill tests pass. No initial
baseline identity is newly failing, missing or skipped. Receipts:
`.git/refactor-evidence/phase4c/full-pending-pill.jsonl`,
`full-pending-pill-comparison.txt`, `pending-pill-previous-checkpoint.txt`.


### Phase 4C — Title and keyword Sources headers

Extracted `SourceTitleHeader` (92 lines) and `SourceKeywordField` (44 lines),
replacing the two original methods with actual widgets in `_sourcesBody`. Title
visibility still requires redesign, non-keyword and non-cinema mode after loading
and errors resolve. Keyword input remains above the loading/results area. The
view supplies display strings/poster, its existing text controller, color scheme
and submission callback; query state/lifecycle is not duplicated in the widgets.
Sources is **2,481 lines**; parent **20,160**.

Review mechanically compared the complete title render subtree against the prior
method after parameter substitution: it is unchanged. The 128-pixel strip,
640-pixel image decode cap, low filter quality, gapless playback, empty/error
artwork behavior, gradient constants and title/subtitle overflow/styles remain.
Keyword input still uses the existing TV-aware field, exact text dispatch,
Search IME action and suffix button; two new executable cases verify both submit
paths retain whitespace/case and leave the borrowed controller usable on unmount.

The keyword field's unchanged bare radius moves with its guard: one permitted
site transfers from the Sources manifest entry (3 → 2) to an extracted-residue
entry (1). It has no shape-token sites to count as already swept, so only the
bare-radius ratchet includes that entry. The existing swept-file assertions and
490-call floor remain unchanged. No new radius allowance or app text was added.

The confirming full-suite checkpoint immediately before this extraction passed
7,809 tests with the same 51 baseline failures/20 skips. After extraction, the
Sources/cinema/shape/TV-input affected group has **239 passes** and only the
original-baseline `no swept file grows a new bare radius` failure. Both other
shape checks pass; all Sources and TV-input cases pass. Final analyzer comparison
remains **864 diagnostics with no additions**; architecture checks pass for
**99 migrated files**. New files and the touched caller are normally formatted;
diff checks pass. Receipts under `.git/refactor-evidence/phase4c/`:
`headers-focused.txt`, `headers-widget.txt`, `headers-focused-final.txt`,
`analyze-headers.txt`, `headers-analyzer-comparison.txt`,
`analyze-headers-final.txt`, `headers-final-analyzer-comparison.txt`.

The full suite was not rerun after this leaf extraction. Native/visual checks,
remaining Sources UI/focus and binding boundaries, later phases and final
performance/CI gates remain incomplete.


### Phase 4C — Active-filter summary presentation

Extracted `SourceActiveFilters` (106 lines), including its five private label
formatters. The actual toolbar passes immutable `TorrentFilterState`, its existing
accent/dim colors and a Clear callback. The callback still sets empty filters on
`SourceResultsController` then calls `_rebuildVisible`; all focus and result
projection stay with their existing owners. The replaced method/label helpers
are removed from Sources, now **2,401 lines**; parent **20,161**.

Review preserves group order (quality, rip source, language, size, range), set
insertion order within each group, exact legacy labels, wrap/padding dimensions,
colors and the existing InkWell. Visibility still depends on nonempty filters.
The moved `app.shape.brPill` site is registered with zero bare-radius allowance,
keeping the existing 490-call shape guard intact. No new application text,
service dependency or second copy of filter state was introduced.

Baseline affected Sources/cinema/shape tests: **221 passes**, one original
baseline shape-radius failure. Post-extraction: **223 passes**, that same failure.
Two new widget cases cover pointer and keyboard Clear, single dispatch, retained
input state and observable label ordering. Both other shape guards pass. Final
analyzer identities remain **864**, with no additions. Architecture checks pass
for **100 migrated files**; new files are formatted and diff checks pass. The
inserted toolbar call follows normal formatting; existing unrelated formatting
in the surrounding legacy toolbar is retained. Receipts under
`.git/refactor-evidence/phase4c/`: `filter-summary-before.txt`,
`filter-summary-focused.txt`, `analyze-filter-summary.txt`,
`filter-summary-analyzer-comparison.txt`.

The most recent full-suite checkpoint remains `full-pending-pill.jsonl`
(7,809 successes, same 51 failures/20 skips), preceding the header and this
filter-summary leaf extraction. No full-suite/native parity claim is made for
these leaves. Remaining Sources toolbar/results/focus and manual binding
boundaries, later phases and native/performance/CI checks remain open.


### Phase 4C — Season, sort and filter toolbar controls

Extracted `SourceToolbarControls` (217 lines) from the real Sources toolbar. It
receives displayed season/sort/filter values, the borrowed filter FocusNode and
narrow action/navigation callbacks. Season options remain a callback evaluated
when the popup opens, rather than a potentially stale build-time snapshot. The
view still checks accepted season changes before searching; sort and direction
callbacks update the existing results controller then rebuild visible rows.
Filter Down still checks pending-count first and otherwise focuses the current
first row at event time. Provider projection/pills/retries remain in the view for
a separate extraction. Sources is **2,242 lines**; parent **20,162**.

Review preserves popup options/colors/initial values, season zero → null mapping,
sort-direction visibility, spacing, chip rendering and theme tokens. The unused
foreground parameter of the original chip helper was removed; the child still
receives its original colors. The filter's outer Focus remains the sole focus
target (`InkWell.canRequestFocus: false`), reacts only to KeyDownEvent, and keeps
the existing view-owned focus listener and disposal. The moved three shape-token
sites are registered with zero bare radii; the manifest still counts 490 calls.

The affected Sources/cinema/shape baseline and post-wire group both have
**223 passes** and the one original-baseline bare-radius failure. Seven new
widget cases pass for lazy season options/all-season mapping, sorting and
direction, four activation keys and filter Down, including ignored repeats/
release and reusing the borrowed node after unmount. Architecture checks pass
for **101 migrated files**. New files are formatted; diff checks pass. Receipts:
`.git/refactor-evidence/phase4c/toolbar-controls-before.txt`,
`toolbar-controls-focused.txt`, `toolbar-controls-widget.txt`,
`analyze-toolbar-controls.txt`.

A simultaneous final analyzer dependency preparation exited before analysis
while deleting an iOS ephemeral `.packages` directory. The existing full-suite
process remains the verification owner; it was not restarted. Analysis is
repeated with `--no-pub` against the already resolved, unchanged dependencies.
This is an environment preparation failure, not a parsed diagnostic result.

Final analysis completed with **864 diagnostics and no added identities**. The
confirming full suite has **7,820 successes**, the same **51 baseline failures**
(22 failure/29 error), and **20 skips**. No initial-baseline identity is newly
failing, missing or skipped. Every previous pending-pill checkpoint outcome is
preserved; all **11 added tests** from headers, active-filter summary and toolbar
controls pass. The historical helper allowance is unchanged and still exits 1
for pre-existing failures. Final receipts:
`.git/refactor-evidence/phase4c/analyze-toolbar-controls-complete.txt`,
`toolbar-controls-complete-analyzer-comparison.txt`,
`full-toolbar-controls.jsonl`, `full-toolbar-controls-comparison.txt`,
`toolbar-controls-previous-checkpoint.txt`.
Phase 4C provider rail, remaining Sources UI/focus and manual binding preparation
boundaries, later phases, native/performance checks and final CI remain open.


### Phase 4C — Provider-strip presentation

Extracted the 128-line `SourceProviderStrip` with a 16-line immutable
`SourceProviderOption` boundary. The production toolbar prepares its ordered
options and sends separate selection/retry callbacks; the widget snapshots the
list and only renders/dispatches. Source aliases, provider ordering, label
precedence, actionable-status selection, request-key lookup and failure messages
remain upstream for the next projection slice. The original local pill builder
and strip rendering are removed. Sources is **2,159 lines**; parent **20,164**.

Review preserves strip visibility and All eligibility at the call site; existing
ValueKeys, horizontal scroll geometry, pill padding, selected ink/fill, failed
colors, retry text constraints and spinner/refresh behavior remain. Busy retries
remain clickable as before, with duplicate prevention still owned by the retry
controller. Retry callbacks resolve the same captured status by source key,
retaining the exact configuration request key at the service boundary. Media
server/IPTV messages and selection filtering are unchanged.

The shape guard initially exposed that Sources now contains no shape-token calls
after this move. The old file is retained under the existing no-token residue
map with its actual **zero** bare radii (tightened from allowance 2). The strip's
two moved token calls are registered with zero bare radii. Both token guards pass
and the total remains **490**; thresholds and failure allowances are unchanged.

Affected baseline: **230 passes**, the one original-baseline bare-radius failure.
Final affected Sources/cinema/shape group: **233 passes**, the same failure. Two
new widget cases exercise ordered All/provider/retry choices through touch and
keyboard, including a busy failed retry. A new real-screen test at 500×800
exercises the non-cinema production strip: select one provider, restore All,
then retry using the exact addon configuration. The existing cinema retry test
also passes. Analyzer identities remain **864**, with no additions; architecture
checks pass for **103 migrated files**. New/changed test files and new widgets/
model are formatted; diff checks pass. Receipts under
`.git/refactor-evidence/phase4c/`: `provider-strip-before.txt`,
`provider-strip-focused.txt` (intermediate manifest mismatch),
`provider-strip-focused-final.txt`, `provider-strip-wired-screen.txt`,
`provider-strip-complete.txt`, `analyze-provider-strip-final.txt`,
`provider-strip-final-analyzer-comparison.txt`.

The previous full-suite checkpoint remains `full-toolbar-controls.jsonl`
(7,820 successes, same 51 failures/20 skips); this leaf uses affected checks.
Remaining provider projection, Sources UI/focus, manual binding preparation,
later phases and native/performance/CI gates are still open.


### Phase 4C — Shared source-row metadata labels

Extracted the 74-line `lib/ui/core/source_metadata_labels.dart` with pure
subtitle, date, size, quality and coverage display functions. The real Sources
row now uses these functions and the original methods are removed. Review and
compilation exposed Keyword's calls into three private Sources methods; all
four Keyword call sites now use the shared size/date/quality functions directly.
The initial intermediate compilation failure was fixed before final verification.
Keyword's separate subtitle assembly deliberately retains its trimmed, nonempty
addon-name fallback, while Sources retains its existing null-only fallback.
Sources is **2,087 lines**; parent **20,165**.

The shared file is registered in the migrated-source architecture checker. Its
transitive dependencies are the plain Torrent model and existing pure format-tag/
source-quality helpers, with no UI context, Riverpod, data or platform services.
Date formatting accepts an optional time for deterministic tests; production
still samples `DateTime.now()` only for positive timestamps at the original
formatting point. No persisted format or application text changed.

Baseline affected Sources/cinema/row-focus group: **236 passes**. Final group
plus the shared-label tests: **249 passes**. Thirteen new cases exercise upload
age boundaries (including future timestamps), byte formatting and metadata order,
empty/addon source precedence, direct/external omission of peer/date metadata,
pixel quality precedence over loose UHD tokens, and pack/episode fallbacks.
Final analyzer identities remain **864**, with no additions; architecture checks
pass for **104 migrated files**. New files are normally formatted and diff checks
pass. Receipts under `.git/refactor-evidence/phase4c/`:
`row-labels-before.txt`, `row-labels-focused.txt` (intermediate missing Keyword
call sites), `row-labels-focused-final.txt`, `analyze-row-labels-final.txt`,
`row-labels-analyzer-comparison.txt`.

The full-suite confirmation has **7,836 successes**, the same **51 baseline
failures** (22 failure/29 error) and **20 skips**. No original-baseline identity
is newly failing, missing or skipped. Every prior toolbar-controls checkpoint
outcome is preserved, with **16 new passing identities** from the provider-strip
and metadata-label slices. The historical allowance remains unchanged; the
helper still exits 1 for pre-existing failures. Receipts:
`.git/refactor-evidence/phase4c/full-row-labels.jsonl`,
`full-row-labels-comparison.txt`, `row-labels-previous-checkpoint.txt`.
Phase 4C provider projection, remaining Sources UI/focus and manual binding
preparation, later phases and native/performance/CI gates remain incomplete.


### Phase 4C — Provider-strip projection

Extracted `source_provider_projection.dart` (112 lines), wired into the actual
Sources toolbar. The pure operation accepts current rows/statuses/IPTV metadata,
priority/aliases and retry request keys, returning immutable options/retry map
plus visibility/All eligibility. It owns no search state, performs no IO and
uses no UI context or Riverpod. Selection/retry dispatch remains with the view
and existing controllers. The original projection, label helper and actionable
status predicate are removed; both toolbar and cinema retry checks use the
shared predicate. Sources is **2,026 lines**; parent **20,165**.

Review preserves alphabetical source traversal before priority ordering, alias
collisions, status label precedence (including empty labels), IPTV's final label
override, retry suppression when a source already has rows, last matching retry
status identity, exact request-key busy state, and retry-only/single-IPTV-failure
visibility. The label fallback retains its case-sensitive prefix handling and
first matching IPTV entry. The projected list/map are unmodifiable.

Existing `SourcePriority` pure calls and legacy `AddonSearchStatus`/
`IptvSourceResult` types remain external dependencies, as in the migrated search
state. Their transitive legacy service/UI graph is not claimed pure; separation
remains part of the phase-8 boundary audit. No new service API or business side
effect was introduced in this extraction.

Affected baseline: **231 passes**. Final Sources/cinema group: **236 passes**.
Five new policy cases cover grouping/precedence, retry eligibility/configuration,
immutable results, single-provider visibility and IPTV override/failure behavior.
Existing narrow production strip and cinema retry tests pass. Intermediate
compilation exposed one remaining cinema reference to the old predicate; that
call site was updated before final verification. Final analyzer has **864
diagnostics with no new identities**. Architecture checks pass for **105
migrated files**; new files are formatted and diff checks pass. Receipts under
`.git/refactor-evidence/phase4c/`: `provider-projection-before.txt`,
`provider-projection-focused.txt` (intermediate predicate reference),
`provider-projection-focused-final.txt`, `analyze-provider-projection-final.txt`,
`provider-projection-analyzer-comparison.txt`.

The latest full-suite checkpoint remains `full-row-labels.jsonl` (7,836 successes,
same 51 failures/20 skips); this slice uses affected checks. Cinema provider
projection, remaining Sources UI/focus, manual binding preparation and later
phases/native/performance/CI gates remain unfinished.
