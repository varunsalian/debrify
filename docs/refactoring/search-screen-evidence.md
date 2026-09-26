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
