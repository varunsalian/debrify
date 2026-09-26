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
