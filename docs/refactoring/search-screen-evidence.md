# Search refactor implementation evidence

This log accompanies the [plan](search-screen-plan.md). A pending check is not a
pass. Remaining work follows the plan's revised delivery batches: review cohesive
workflow checkpoints, reuse valid evidence, and run broader checks at integration
gates. Earlier entries retain their original slice history. No changes are pushed
to the public repository.

## Batch D checkpoint: Home board application bindings — 2026-09-28

Base: `607fabfb`. `HomeBoardBindings` (112 lines) retains catalog/continuation,
episode artwork, tracker authentication, PikPak availability, bound-source counts,
post-playback refresh and settings-refresh application owners. The root keeps
snapshot/session construction and delegates through existing typed controllers.
Root: **10,088 → 10,015 lines**.

Review preserves provider keys, registration/read order, tracker iteration, the
continuation-only repaint subscription and the original contiguous cleanup order.
No request or state-publication owner changes. **69 tests pass** across progressive
loading/pagination and configuration, PikPak, artwork, bound-count and Trakt screen
integration. Analysis retains **836 identical diagnostic identities**; architecture
passes **561 files**; changed-code formatting/diff checks pass. Receipts:
`.git/refactor-evidence/phase5/home-board-bindings-{tests,analyze}.txt`.
No emulator used. Complete feature composition, remaining lifecycle/facade
reduction, C/D integration and final acceptance remain pending.

## Batch D checkpoint: continuation focus pools — 2026-09-28

Base: `5cf9fa74`. `HomeContinuationNodes` (92 lines) owns the ten movie/series
focus pools, labels, resize policy and phased cleanup. The five loaders and layout
refresh use its typed family API, retaining the existing accepted/merged counts.
Root accessors borrow the same lists. Root: **10,162 → 10,088 lines**.

Review preserves surviving-prefix identity, movie-before-series resizing, disposal
before tail-focus handoff, empty-row recovery ownership and the explicit local,
IPTV, Trakt, Simkl, MDBList disposal order. Favorite disposal still runs between
continuation disposal and clearing. **41 tests pass** across five continuation
screen families, layout, board viewport and a new focused-tail/merged-row case.
Final analysis retains **836 identical diagnostic identities**; architecture passes
**560 files**; changed-code formatting/diff checks pass. Receipts:
`.git/refactor-evidence/phase5/continuation-nodes-{tests,analyze-final}.txt`.
No emulator used. Remaining feature composition, lifecycle/facade reduction,
C/D integration and final acceptance are pending.

## Batch D checkpoint: continuation provider bindings — 2026-09-28

Base: `2e9288bd`. `HomeContinuationBindings` (95 lines) retains local, IPTV,
Trakt, Simkl and MDBList providers plus shared continuation layout preferences.
Stable live progress adapters are created alongside their existing controllers;
the screen delegates through aliases without copying published data. Root:
**10,225 → 10,162 lines**.

Review preserves the shared owner/view session, Trakt's Search-specific loading
seed, listen-before-read initialization order, progress-view identity and phased
cleanup (content families, favorites, then layout). **40 tests pass** across five
continuation screen families, layout-controller cases and See-All routing checks.
Analysis retains **836 identical diagnostic identities**; architecture passes
**559 files**; changed-code formatting and diff checks pass. Receipts:
`.git/refactor-evidence/phase5/continuation-bindings-{tests,analyze}.txt`.
No emulator used. Feature composition, remaining lifecycle/facade reduction and
final acceptance remain pending.

## Batch D checkpoint: Home board viewport — 2026-09-28

Base: `4304a202`. `HomeBoardViewport` (160 lines) owns the board scroll controller,
catalog-row focus pools, remembered columns, append/reconciliation and mounted-row
focus recovery. The root retains rendering/pagination decisions and aliases the
same resources. Scroll construction and scroll/node disposal remain at their
original separate lifecycle points. Root: **10,298 → 10,225 lines** after formatting
complete changed methods, without whole-file formatting.

Review preserves labels, row/content identity, incremental column remapping,
non-incremental column clearing, left-first nearest mounted cell selection,
140 ms/45%-viewport glides, the three-hop bound and post-frame mounted guard.
**62 tests pass**: 58 progressive-loading/pagination/row-focus/navigation cases
and four viewport identity/focus/retirement cases. Final analysis retains **836
identical diagnostic identities** after fixing a braces lint and using the current
cache-extent API in the new test. Architecture passes **558 files**; formatting
and diff checks pass. Receipts: `.git/refactor-evidence/phase5/board-viewport-
{tests,focused-final,analyze-final}.txt`. No emulator used. Broader feature ownership,
remaining lifecycle/facade reduction and final acceptance remain pending.

## Batch D checkpoint: Spotlight search sheet state — 2026-09-28

Base: `a0ad2eaa`. `SpotlightSearchSheet` lives beside the existing shell
presentation (file now 228 lines). It owns the open latch, focus-triggered opening,
restoration, forced-state observation, deferred field focus and close/Back reset
sequence. The root supplies its existing query reset and rebuild boundary, and
registers/removes the owner's stable callbacks at the original lifecycle points.
Root: **10,332 → 10,298 lines**. No new provider or feature file is introduced.

Review preserves Catalog-before-clear ordering, query cancellation, pre-reset
content capture, cold-start focused-field Back consumption, stale Classic-latch
fallthrough and mounted checks on deferred focus. **68 tests pass**, including
Search presentation/focus integration, Home keyword restoration and two new sheet
lifecycle cases. Final analysis retains **836 identical diagnostic identities**;
architecture passes **557 files**; changed-code formatting/diff checks pass.
Receipts: `.git/refactor-evidence/phase5/search-sheet-{tests,analyze-final}.txt`.
No emulator used. Remaining feature ownership, lifecycle/facade reduction and
final acceptance remain pending.

## Batch C checkpoint: Home See-All navigation — 2026-09-28

Base: `eea04c08`. `HomeSeeAllNavigation` (187 lines) owns catalog, tracker-list,
Trakt and generic Continue Watching grid routes. Root dispatch still keeps synthetic
collection/list rows out of catalog pagination. Existing action owners supply
playback, detail and return-refresh callbacks. Root: **10,449 → 10,332 lines**.

Review preserves route-builder-time catalog/CW/Trakt snapshots, opening-time
tracker-list snapshots, live progress maps, catalog query/cursor and addon origin,
PikPak quick-play gating, separate Simkl CW handlers, MDBList public-list origin,
expanded-card wrapping and each route's existing return refresh. **27 tests pass**:
23 local/Trakt/Simkl/MDBList continuation screen cases and four focused route tests.
Final analysis retains **836 identical diagnostic identities**; architecture passes
**557 files**; changed-code formatting/diff checks pass. The named route bridge may
import only `HomeListSection` and `HomeExtraRowIds` from the legacy list service;
the guard enforces the exact `show` list and permits no service operations.
Receipts: `.git/refactor-evidence/phase5/see-all-navigation-{screens,focused,
analyze-final}.txt`. No emulator used. Complete feature composition, remaining
lifecycle/facade reduction, C/D integration and final acceptance remain pending.

## Batch C checkpoint: page shell composition — 2026-09-28

Base: `d710827f`. `search_page_shell.dart` (175 lines) composes the route shell,
Spotlight search sheet, unified Sources bar and mode content routing. Existing
feature builders remain lazy; the root retains sheet state and focus/lifecycle
callbacks. Root: **10,558 → 10,449 lines**. This is page composition, not yet
complete Home/Search/Discover state and action ownership.

Review preserves Discover/TV Home/Spotlight/standard branch priority, transparent
TV background, SafeArea/inset geometry, sheet latch timing, close eligibility,
post-frame field focus, Sources animation and streamed-row spinner transition.
Spotlight eligibility stays lazy on routes that cannot render it. **121 affected
tests pass**: 66 Search presentation/focus cases plus 55 Home progressive-loading
and pagination cases. Four shell tests were rerun after the lazy-eligibility
refinement and pass. Final analysis retains **836 identical diagnostic identities**;
architecture passes **556 files**; changed-code formatting/diff checks pass.
Receipts: `.git/refactor-evidence/phase5/search-page-shell-{tests,home-tests,
focused,analyze-final}.txt`. No emulator used. C/D feature ownership/facade work,
integration gate and final device/performance acceptance remain pending.

## Batch D checkpoint: Home refresh queue — 2026-09-28

Base: `fe25a05c`. `HomeRefreshQueue` owns pending row/addon invalidations and
its timer. The refresh enum lives in Home's model layer, re-exported by the
existing signal service for compatibility. Production callbacks delegate to the
queue; disposal remains at the original teardown point. Root: **10,573 → 10,558
lines**.

Review preserves the 100 ms first-event deadline, insertion-order deduplication,
visible playback suppression, current-view checks, row-before-addon dispatch and
cancellation. **37 tests pass** across queue timing/disposal and six saved-content
screen families. Analysis retains **836 identical diagnostic identities**;
architecture passes **555 files**; changed-code formatting and diff checks pass.
Receipts: `.git/refactor-evidence/phase5/home-refresh-queue-tests.txt` and
`home-refresh-queue-analyze-final.txt`. No emulator used. Feature composition,
remaining lifecycle/facade reduction and final acceptance remain pending.

## Batch D checkpoint: saved-content focus pools — 2026-09-28

Base: `3c469c3d`. `HomeFavoriteNodes` (76 lines) owns the six saved-content node
pools and resize/removal policies. Custom IPTV lists retain their existing stable-
list-id owner. The root delegates synchronization and preserves disposal/clear
phases around continuation pools. Root: **10,639 → 10,573 lines**.

Review preserves labels, positional node identity, ordinary favorite trimming,
Watchlist's deferred remaining-card/content fallback, Playlist's immediate last-
card handoff and the original disposal order. **31 tests pass**: 29 saved-content
screen cases and two focused last-card removal/identity/fallback widget tests.
Analysis retains **836 identical diagnostic identities**; architecture passes
**553 files**; formatting/diff checks pass. Receipts:
`.git/refactor-evidence/phase5/favorite-nodes-{tests,focused,analyze-final}.txt`.
No emulator used. Remaining feature composition, broader lifecycle/facade reduction
and final acceptance remain pending.

## Batch D checkpoint: Home saved-content bindings — 2026-09-28

Base: `6ed9b04a`. `HomeFavoriteBindings` (76 lines) retains TV/Stremio/IPTV
favorites, IPTV lists, Watchlist and Playlist providers and exposes their existing
controllers. Each provider keeps its own fresh view identity. Registration remains
listen-before-read in the original sequence; contiguous cleanup remains in the
same order and at the same route teardown point. Root: **10,710 → 10,639 lines**.

Review confirms no provider keys, loading actions, snapshots or focus resources
were merged. **35 real-screen tests pass** across the six saved-content families.
Final analysis retains **836 identical diagnostic identities** after removing an
unused root model import; architecture passes **552 files**; formatting/diff checks
pass. Receipts: `.git/refactor-evidence/phase5/favorite-bindings-
{tests,saved-tests,analyze-final}.txt`. No emulator used.
Remaining feature composition, broader lifecycle/facade reduction and final
acceptance remain pending.

## Batch D checkpoint: Keyword viewport ownership — 2026-09-28

Base: `8b6e1627`. `KeywordViewport` (57 lines) owns the scroll controller, last
observed/pending offsets and cinema return index. Root delegates restoration,
source reset and focus selection while retaining the original listener-registration
and disposal points. Snapshot capture still reads the last observed offset after
list detachment. Root: **10,739 → 10,710 lines**.

Review preserves result-gated consume-once restoration, clamping, mounted checks,
source-reset order, index clamping, toolbar fallback and interaction freeze.
**191 tests pass**: 190 Search/TV-focus checks and a new viewport restoration/reset
test. Analysis retains **836 identical diagnostic identities**; architecture
passes **551 files**; formatting/diff checks pass. Receipts:
`.git/refactor-evidence/phase5/keyword-viewport-{tests,focused,analyze-final}.txt`.
No emulator used. Remaining feature composition, broader lifecycle/facade reduction
and final acceptance remain pending.

## Batch C checkpoint: shared Search Sources control — 2026-09-28

Base: `58dfc9a2`. Catalog and Keyword now use the same Sources control factory,
removing the duplicate Keyword widget/key handling. Each mode supplies its own
borrowed node and dialog action. The root's now-unused keyboard helper import
was removed. Root: **10,810 → 10,739 lines**.

Review confirms identical styling, pointer behavior, key-down activation and
Up/Left callbacks; unhandled keys and key-repeat behavior remain unchanged.
**190 tests pass**: Search application/presentation and TV focus handoff checks.
Final analysis retains **836 identical diagnostic identities**; architecture
passes **550 files**; formatting/diff checks pass. Receipts:
`.git/refactor-evidence/phase5/shared-sources-{tests,analyze-final}.txt`.
No emulator used. Remaining Keyword composition, other feature/navigation wiring,
lifecycle/facade reduction and final acceptance remain pending.

## Batch C checkpoint: Continue Watching family composition — 2026-09-28

Base: `0e5c0146`. The existing `home_stage_rows.dart` (176 lines) now builds the
shared movie/merged and series row pair. All five provider families use this
projection; the host supplies provider-specific lists, nodes, metadata and actions.
The root is now **10,810 lines**.

Review preserves family order, disabled/enabled gates, movie-slot identity for
merged rows, split movie metadata suppression, live See-All merge preference,
MDBList removal eligibility and IPTV synthetic-id metadata/action handling.
**104 tests pass**: 103 provider-screen/row/action/progressive/pagination cases
plus a new merged-row identity/metadata/node/disabled-state test. Analysis retains
**836 identical diagnostic identities**; architecture passes **550 files**;
formatting/diff checks pass. Receipts:
`.git/refactor-evidence/phase5/cw-family-{tests,focused,analyze-final}.txt`.
No emulator used. Remaining feature/navigation composition, lifecycle/facade
reduction and final acceptance remain pending.

## Batch D checkpoint: title suggestion presentation ownership — 2026-09-28

Base: `9a16a635`. `TitleSuggestionPresentation` (55 lines) owns the published
suggestion notifier, edit/IME deduplication and selection generation state. The
screen delegates publication/cancellation/begin/finish and disposes the notifier
at its original point after the lookup source. Profile/tab/request eligibility and
metadata navigation remain at their existing call sites.

Review preserves text versus selection-only edits, composing-state changes,
cancel-before-capture ordering and stale completions not unlocking newer opens.
**200 tests pass**: 187 Search application/presentation tests, including a new
ownership/IME test, plus 13 title-suggestion screen cases. Two previously observed
unresolved-title failures were excluded from that focused screen command using
`--name '^(?!unresolved suggestion)'`; they remain known failures, not passes.
Analysis retains **836 identical diagnostic identities**; architecture passes
**550 files**; formatting/diff checks pass. Receipts:
`.git/refactor-evidence/phase5/title-owner-{tests,screen,analyze-final}.txt`.
No emulator used. Remaining source/navigation composition, broader lifecycle/
facade reduction and final acceptance remain pending.

## Batch C/D checkpoint: query presentation cleanup — 2026-09-28

Base: `4a32f4af`. Title-suggestion formatting/actions now live beside the query
field (247 lines). Lookup cancellation, profile/request guards and navigation stay
at their original call sites. Removed the never-assigned catalog debounce field
and its four no-op cancellation calls; a repository search confirmed no assignment
or external use. Root: **10,920 → 10,900 lines**.

Review preserves item labels/year, query fallback visibility, captured selection
arguments and submit-only search timing. **186 tests pass**: all 185 Search
application/presentation tests plus a new suggestion capture/empty-state test.
Analysis retains **836 identical diagnostic identities**; architecture passes
**549 files**; formatting/diff checks pass. Receipts:
`.git/refactor-evidence/phase5/query-cleanup-{tests,focused,analyze-final}.txt`.
No emulator used. Remaining composition, suggestion lookup/navigation lifecycle,
broader facade reduction and final acceptance remain pending.

## Batch D checkpoint: Search result provider bindings — 2026-09-28

Base: `41bf6c67`. `SearchResultBindings` (106 lines) retains Lists, Catalog,
Keyword cache/results/search subscriptions and forwards their publications into
existing presentation actions. Controllers and session keys remain unchanged;
there is no copied application state. Root: **10,970 → 10,920 lines**.

Review preserves registration order, non-TV catalog append/replace logic, lazy
subscription reads, mounted guards, Keyword stream/completion/failure ordering,
cache-only badge repaints, covered-route retention and snapshot-before-cleanup.
Cleanup stays in two phases around the appearance subscription to retain the
original close sequence. **All 185 Search application/presentation tests pass**.
Analysis retains **836 identical diagnostic identities**; architecture passes
**549 files**; formatting/diff checks pass. Receipts:
`.git/refactor-evidence/phase5/search-bindings-{tests,analyze}.txt`.
No emulator used. Remaining feature composition, broader lifecycle/facade reduction
and final acceptance are pending.

## Batch C checkpoint: Lists route navigation — 2026-09-28

Base: `d1c4b3dc`. `ListsNavigation` (66 lines) owns list-grid and list-items route
construction. Search still supplies accepted open/play actions and return refresh.
Root: **11,007 → 10,970 lines**.

Review preserves copied result snapshots, the grid route's navigator for nested
items, route-build-time TV/restriction reads, MDBList action provenance, and the
original refresh-before-return-callback sequence (refresh is not newly awaited).
**11 affected tests pass**: production Lists screens, rail keyboard behavior and
MDBList Discover screens. Analysis retains **836 identical diagnostic identities**;
architecture passes **548 files**; formatting/diff checks pass. Receipts:
`.git/refactor-evidence/phase5/lists-navigation-{tests,analyze}.txt`.
No emulator used. Remaining navigation/action composition, lifecycle/facade
reduction and final acceptance remain pending.

## Batch D checkpoint: catalog continuation focus — 2026-09-28

Base: `e4bd4c60`. `HomeContinuationFocus` owns both continuation action nodes,
the borrowed return target and post-completion restoration policy. The existing
mounted-node helper moved into the same feature file with a compatibility export.
The root delegates selection/restoration and disposes nodes at the original point.
Root: **11,028 → 11,007 lines**.

Review preserves Continue-before-More priority, original-focus capture, mounted
fallbacks, current-request checks and no-steal behavior after deferred completion.
**58 affected tests pass**: mounted-focus and continuation-screen checks plus all
55 progressive/pagination screen cases. Analysis retains **836 identical diagnostic
identities**; architecture passes **547 files**; formatting/diff checks pass.
Receipts: `.git/refactor-evidence/phase5/continuation-focus-{tests,analyze}.txt`.
No emulator used. Remaining feature/navigation composition, broader lifecycle/
facade reduction and final acceptance remain pending.

## Batch C checkpoint: catalog prompt and Sources control — 2026-09-28

Base: `6590d4bf`. `catalog_search_prompt.dart` (136 lines) owns the catalog empty
prompt and Sources control rendering/key handling. The host still opens settings
and reruns the current query. Root: **11,140 → 11,028 lines**.

Review preserves theme/text/spacing, original widget stack, borrowed focus node,
key-down-only activation, Up to query, Left to sidebar and pointer activation.
**20 affected tests pass**: catalog screen, Sources dialog, shared focus controller
and TV search handoff. Analysis retains **836 identical diagnostic identities**;
architecture passes **546 files**; formatting/diff checks pass. Receipts:
`.git/refactor-evidence/phase5/catalog-prompt-{tests,analyze}.txt`.
No emulator used. Remaining navigation/action composition, lifecycle/facade
reduction and final acceptance remain pending.

## Batch C checkpoint: Lists content states — 2026-09-28

Base: `7900c24d`. The existing Lists presentation file (192 lines) now renders
loading, error, prompt, empty and result states as well as the rail. Review
preserves branch priority, theme/text/spacing and lazy result construction.
Root: **11,192 → 11,140 lines**.

**Nine affected tests pass** (production Lists screens and keyboard behavior).
Analysis retains **836 identical diagnostic identities**; architecture passes
**545 files**; formatting/diff checks pass. Receipts:
`.git/refactor-evidence/phase5/lists-content-{tests,analyze}.txt`.
The plan's C status is condensed; detailed history remains in this evidence log.
No emulator used. Navigation/action wiring, lifecycle/facade reduction and final
acceptance remain pending.

## Batch C checkpoint: Lists result rail — 2026-09-28

Base: `d60ffe68`. `lists_search_rail.dart` (124 lines) owns the lazy Lists strip,
card focus/scroll behavior and DPAD handling. The screen supplies current results,
borrowed nodes, header and actions. Root is now **11,192 lines**.

Review preserves captured card actions, current result reads, key-down/repeat
activation, TV sidebar exit, horizontal bounds, Up behavior, swallowed Down and
post-frame 150ms centered scrolling. **Ten tests pass**: production Lists screens,
focus ownership and a new keyboard boundary test. Analysis remains at **836
diagnostics**: one unchanged cacheExtent deprecation moved from the root into
the extracted rail; all other diagnostic identities match. Architecture passes
**545 files**; formatting/diff checks pass. Receipts:
`.git/refactor-evidence/phase5/lists-rail-{tests,focused,analyze-final}.txt`.
No emulator used. Remaining presentation/navigation, lifecycle/facade reduction
and final acceptance are pending.

## Batch D checkpoint: Lists result focus ownership — 2026-09-28

Base: `a79ae587`. `ListsFocus` owns result-node resizing/cleanup and deferred
return focus. The screen delegates existing reset/arrival/route-return paths.
Review preserves node identity while growing/shrinking, original clear points,
frame-time identity lookup and mounted checks before scheduling and execution.

**23 tests pass**, including production Lists screens, controller races/profile
isolation, and a new resource/return-focus test. The initial command also named a
nonexistent submit-focus test; the corrected complete group passed. Analysis
retains **836 identical diagnostic identities**; architecture passes **544 files**;
formatting/diff checks pass. Receipts:
`.git/refactor-evidence/phase5/lists-focus-{tests-final,analyze-final}.txt`.
No emulator used. Remaining presentation/navigation, screen lifecycle/facade
reduction and final acceptance remain pending.

## Batch D checkpoint: Discover shell lifecycle — 2026-09-28

Base: `82cc9955`. `DiscoverShellBridge` owns app-shell settings slots, preview
listener registration and deferred sidebar reset. It borrows the preview and
releases listeners before the route's original preview disposal point. Off-TV
preview creation remains lazy. Root: **11,323 → 11,295 lines**.

Review preserves TV gating, load-before-layout-slot registration, ownership-aware
slot clearing, listener removal and post-frame sidebar reset. The architecture
checker permits only this named UI adapter's MainPageBridge import, matching the
existing Home shell bridge; no data API exception was added.
**13 tests pass**, covering preview behavior, grid/layout/source startup and a new
teardown test for listener release and newer-route callback preservation. Its first
run lacked a scheduled frame; the corrected harness explicitly schedules the frame
needed by the original deferred reset. Analysis retains **836 identical diagnostic
identities**; architecture passes **543 files**; formatting/diff checks pass.
Receipts: `.git/refactor-evidence/phase5/discover-shell-
{tests-final,analyze-final}.txt`. No emulator used. Remaining navigation, broader
screen lifecycle/facade reduction and final acceptance remain pending.

## Batch D checkpoint: Discover provider bindings — 2026-09-28

Base: `a8881ad1`. `DiscoverBindings` (42 lines) owns the three manual Riverpod
subscriptions retaining Discover card settings, layout and source controllers.
The route supplies its existing profile/view/source session. Controllers continue
to own application state; the binding only groups registration and cleanup.

Review preserves listen-before-read order, shared view identity, initial source
and handoff, explicit remember timing, empty listeners and card/layout/source close
order at the original teardown point. **65 affected tests pass**, including
Discover application tests and real-screen grid/layout/source-startup coverage.
Analysis retains **836 identical diagnostic identities**; architecture passes
**542 files**; diff checks pass and the new file is formatted. Receipts:
`.git/refactor-evidence/phase5/discover-bindings-{tests,analyze}.txt`.
No emulator used. Remaining preview/shell lifecycle, navigation wiring, facade
reduction and final acceptance are pending. Root remains **11,323 lines**.

## Batch C/D checkpoint: Discover focus resources — 2026-09-28

Base: `81766f62`. `DiscoverFocus` owns the route's source focus node and selected-
title notifier, plus deferred source restoration. Embedded panels borrow the same
resources. Creation remains eager; disposal remains at the original contiguous
node/notifier cleanup point, separate from later preview teardown.

Review preserves focused-title notification scope, source-panel reattachment timing
and mounted-route guarding for scheduled focus. **Seven tests pass**, covering the
new focus-owner test, Discover grid/layout screens and source startup behavior.
Analysis retains **836 identical diagnostic identities**; architecture passes
**541 files**; diff checks pass and new Dart files are formatted. Receipts:
`.git/refactor-evidence/phase5/discover-focus-{tests,analyze}.txt`.
No emulator used. Provider subscription ownership, preview/shell teardown, remaining
navigation wiring, facade reduction and final acceptance are still pending.

## Batch C checkpoint: Classic row dispatch — 2026-09-28

Base: `e164d4c6`. The existing `HomeClassicRows` (115 lines) now selects the
skeleton, continuation, favorite or catalog builder from Home's ordered rail list.
Catalog search retains index ordering. The factory returns the existing widget,
so no element or resource lifetime changes. Root: **11,362 → 11,350 lines**.

Review preserves build-time stable key snapshots, lazy row-id resolution,
placeholder precedence, captured rails, footer timing and entrance animation.
**58 tests pass**: Classic row identity/animation checks plus all 55 progressive/
pagination screen tests. Analysis retains **836 identical diagnostic identities**;
architecture passes **540 files**; formatting/diff checks pass. Receipts:
`.git/refactor-evidence/phase5/classic-dispatch-{tests,analyze}.txt`.
No emulator used. Remaining navigation and route/resource boundaries, D lifecycle/
facade reduction and E final acceptance remain pending.

## Batch C checkpoint: catalog item rendering — 2026-09-28

Base: `22c6dbfe`. The existing `home_catalog_row.dart` (144 lines) now owns the
catalog/collection cell rendering and loading tile, alongside its lazy strip.
The host retains geometry inputs, row navigation and action orchestration. Root:
**11,405 → 11,362 lines**.

Review preserves lazy section reads, spinner count, per-route/cell Hero identity,
collection tile sizing/art/focus media/glow, title settings, quick-play restrictions,
focus callback order and paging triggers. The original widget stack is unchanged.
**69 affected tests pass**, covering row paging, Home catalog repository/preferences/
continuation screens, Search catalog behavior and all progressive layout cases.
Analysis retains **836 identical diagnostic identities**; architecture passes
**540 files**; formatting/diff checks pass. Receipts:
`.git/refactor-evidence/phase5/catalog-items-{tests,analyze}.txt`.
No emulator used. Remaining composition/navigation and route/resource boundaries,
D lifecycle/facade reduction and E final acceptance remain pending.

## Batch C checkpoint: Classic favorite rows — 2026-09-28

Base: `b5d11287`. `HomeClassicFavoriteRows` (221 lines) owns all six Classic
favorite row variants, their tags, artwork and shared cell/poster stack. Host
callbacks retain playback, preview lifecycle and navigation ownership. Root:
**11,590 → 11,405 lines**.

Review preserves lazy item/node/setting reads, captured Watchlist/custom-list
snapshots, fixed row counts, artwork fallbacks, badges, progress, TV/mobile styling,
directional callbacks and live-versus-VOD preview behavior. No wrapper element or
new state owner was added. **85 tests pass**: 84 existing card/favorites-screen/
progressive/pagination cases and a new widget test proving lazy item selection,
rendered-item action capture and clearing live preview on VOD focus.
Analysis retains **836 identical diagnostic identities**; architecture passes
**540 files**; formatting/diff checks pass. Receipts:
`.git/refactor-evidence/phase5/classic-favorites-{tests,focused,analyze-final}.txt`.
No emulator used. Catalog/continuation composition and route/resource boundaries,
D lifecycle/facade reduction, and E final acceptance remain pending.

## Batch C checkpoint: Home rail composition — 2026-09-28

Base: `97272d47`. `HomeRailComposition` (75 lines) owns non-empty rail projection,
Classic loading-placeholder insertion and Tonight queue/stage separation. Saved
ordering remains applied after placeholder insertion. The pure `HomeRowOrder`
policy moved unchanged into Home application, with a compatibility export for
existing settings callers; this resolves the architecture check's rejected legacy
service import without an exception. Root: **11,639 → 11,590 lines**.

Review preserves original continuation indices, borrowed rows/nodes, empty and
unready-row filtering, disabled/merged Trakt placeholders, saved ordering and
Tonight's item/node bounds. **66 distinct tests pass**: ten ordering tests,
55 real-screen progressive/pagination checks and one projection boundary test.
The 11 ordering/projection tests passed again after relocating the pure policy.
Analysis retains **836 identical diagnostic identities**; architecture passes
**539 files**; formatting/diff checks pass. Receipts:
`.git/refactor-evidence/phase5/rail-composition-
{tests,focused,order-final,analyze-final}.txt`. No emulator used.
Remaining C row/action and route/resource boundaries, D lifecycle/facade reduction
and E final acceptance are pending.

## Batch C checkpoint: shared stage favorite cards — 2026-09-28

Base: `897498f4`. `HomeStageFavoriteCards` (163 lines) owns the shared favorite
cell/poster stack and typed IPTV, watchlist, Debrify TV, Stremio TV and playlist
artwork/focus metadata. Production dispatch keeps source selection and playback
callbacks in the host. Root: **11,809 → 11,639 lines**.

Review preserves the exact widget stack, borrowed nodes, directional overrides,
white focus ring, hidden-title setting, live preview eligibility, number fallback,
playlist progress, captured playback items and focus-time metadata/subtitle reads.
Stremio cards retain poster-first art while stage focus retains background-first art.
**86 tests pass**: 84 existing card/favorites-screen/progressive/pagination cases
and two new captured-action/focus-metadata tests. Analysis retains **836 identical
diagnostic identities**; architecture passes **537 files**; formatting/diff checks
pass. Receipts: `.git/refactor-evidence/phase5/stage-favorites-
{tests,focused,analyze-final}.txt`. No emulator used.
Remaining row composition, route/resource ownership, D lifecycle/facade reduction
and E final acceptance are pending.

## Batch C checkpoint: Classic rail traversal — 2026-09-28

Base: `c3cc4e2c`. `HomeClassicNavigation` (60 lines) owns stable-row vertical
traversal, empty-row skipping, column clamping and continuation/paging fallback.
The actual screen delegates both direct and relative focus entry points. Row
snapshots and nodes are borrowed, with fresh row resolution for each focus attempt;
no provider or competing state was added. Root: **11,816 → 11,809 lines**.

Review preserves top exit, continuation priority, lazy paging reads, load-before-
defer ordering and original requested column retention in deferred moves.
**56 tests pass**: one focused traversal test and all 55 real-screen progressive/
pagination tests. Analysis retains **836 identical diagnostic identities**;
architecture checks pass **536 files**; formatting/diff checks pass. Receipts:
`.git/refactor-evidence/phase5/classic-navigation-{tests,analyze}.txt`.
No emulator used. Remaining C work includes favorite-card/row composition and
route/resource ownership; D facade/lifecycle and E acceptance are still pending.

## Batch C checkpoint: stage rail transitions — 2026-09-28

Base: `4e7c1ab6`. The existing `HomeStageNavigation` now owns rail switching,
continuation priority and deferred paging admission. The screen supplies current
readers, ordered UI activation and frame scheduling. No additional state owner or
provider was introduced. Root: **11,831 → 11,816 lines**.

Review preserves lazy reads after continuation focus, defer-before-load ordering,
per-rail columns, repeated continuation fallback, clamped edge moves and Atrium
marker updates before scheduled focus. **57 tests pass**, including all 55
real-screen progressive/pagination cases and focused navigation coverage.
Analysis retains **836 identical diagnostic identities**; architecture checks pass
for **535 files**; changed declarations are formatted and diff checks pass.
Receipts: `.git/refactor-evidence/phase5/stage-switch-{tests,analyze}.txt`.
No emulator used. Remaining C composition/navigation, D lifecycle/facade work and
E final acceptance remain pending.

## Batch C checkpoint: shared stage rail navigation — 2026-09-28

Base: `6c55161c`. `HomeStageNavigation` (98 lines) owns active rail identity,
remembered columns, mounted-node lookup, resolved rail views and one-time focus
seeding. The root delegates production resolution; Spotlight and Tonight keep
their specialized entry targets. Nodes, row data and frame scheduling are borrowed.
Root: **11,898 → 11,831 lines**.

Review preserves identity locking after first render, first-rail fallback,
lower-index tie-breaking for mounted nodes, remembered columns, Atrium's visible
window and fallback when its second row is hidden. Seeding still refuses to steal
established focus, and layout reset preserves its original ordering. Existing
render-time identity bookkeeping remains pending the D lifecycle cleanup.

**63 tests pass**: eight focused navigation/Tonight/frame-scheduler checks and all
55 real-screen progressive-loading/pagination checks across layouts. The new test
covers inserted/removed rails, hidden Atrium rows, column restoration and seeding.
Receipts: `.git/refactor-evidence/phase5/stage-navigation-
{focused,integration,analyze-final}.txt`. Analysis retains **836 identical diagnostic
identities**; architecture passes **535 files**; formatting/diff checks pass.
No emulator used. Rail transition actions, remaining composition, lifecycle and
final acceptance remain pending.

## Batch C/D checkpoint: Tonight focus ownership — 2026-09-28

Base: `bfb2900c`. `HomeTonightFocus` (100 lines) owns remembered queue identity,
index fallback, queue/rail zone, caption updates and caption-signal disposal.
The root delegates queue/rail focus and selection while supplying existing target
resolution. Nodes remain borrowed. Root: **11,970 → 11,898 lines**.

Review preserves identity-first restoration, fallback when lazy rows unmount,
failed-focus zone retention, continuation versus catalog caption hints and callback
ordering. Position reset stays separate from caption clearing to preserve the
route's ordered notifier updates; disposal stays at the original caption cleanup
point. The existing layout-time zone adjustment is still pending D cleanup.

**20 tests pass**: 16 focus/queue/rail/layout checks and four Tonight real-screen
progressive-loading/focus checks. The new focused test covers prepended rows,
unmounted fallback, caption policy, reset ordering and disposal without owning
borrowed nodes. Receipts:
`.git/refactor-evidence/phase5/tonight-focus-{tests,integration,analyze-final}.txt`.
Analysis reports **836 diagnostics**, with no added identities; two doc-comment
HTML notices disappeared with the moved queue-key documentation.
Architecture passes **534 files**; formatting/diff checks pass. No emulator used.
Remaining shared navigation, lifecycle, composition and final acceptance stay open.

## Batch C checkpoint: Mosaic grid navigation — 2026-09-28

Base: `d75ca061`. `HomeMosaicCellNavigation` (88 lines) now owns each Mosaic
cell's directional rules, prefetch and hold dispatch. Nodes, hold latch, paging
and deferred-focus coordinator remain borrowed; the actual favorite/title card
callbacks use this owner. Root: **12,020 → 11,970 lines**.

Review preserves row-edge sidebar entry, Right wrapping and catalog-only deferred
moves, two-row prefetch, Down leaving the last row, frame-captured geometry and
live node-list bounds. Held Up/Down retain the shared latch and reset behavior.
A focused widget test exercises these paths against mounted nodes.

**20 tests pass**: 16 navigation/hold/deferred-right checks (including actual
screen completion) and four Mosaic progressive-loading/focus checks. The first
focused command used an incorrect deferred-right test path; it was corrected and
the complete selected group passed. Receipts:
`.git/refactor-evidence/phase5/mosaic-navigation-{focused-final,integration,analyze}.txt`.
Analysis retains **838 identical diagnostic identities**; architecture passes
**533 files**; formatting/diff checks pass. No emulator used. Remaining shared
navigation, resource ownership, composition and final acceptance remain pending.

## Batch C checkpoint: shared stage title-card composition — 2026-09-28

Base: `c154a7fc`. `HomeStageCards` (116 lines) replaces five repeated constructors
used by Canvas, Promenade, Atrium, Mosaic and Deck/Tonight shelves. It owns shared
card presentation and callback dispatch, borrowing current section lookup and
accepted actions. Layouts retain directional navigation and extra focus effects;
no new resources/providers/data access. Root: **12,179 → 12,020 lines**.

Review preserves collection artwork/overlays, progress/episode display, restricted
quick-play, continuation Options, white focus treatment and per-layout focus side
effects. Promenade retains wide art/rest veil; Mosaic retains its own paging
policy. Atrium intentionally resolves its borrowed item at action time, while the
other layouts retain their captured item. Current section lookup remains at action
time. Two focused tests exercise that distinction, focus-effect ordering, paging
suppression and quick-play gating after input changes.

**55 real-screen progressive-loading/focus tests pass**, plus **44 action/cell/
collection tests and two new focused tests**. The broader action run also reports
two existing collection-browser errors: `Retry in tab B must remain on tab B` and
`TV tabs Down from folder chip must focus a title`. Both are recorded as errors in
`full-native-owner-c4.jsonl`; no allowlist change. Receipts in
`.git/refactor-evidence/phase5/`: `stage-cards-integration.txt`,
`stage-cards-actions.txt`, `stage-cards-focused.txt`, `stage-cards-atrium-final.txt`
and `stage-cards-analyze-final.txt`. Final Atrium integration recheck: **4 pass**.
Analysis retains **838 identical diagnostic identities**. Architecture passes **532 files**;
formatting/diff checks pass. No emulator used. Navigation/resource ownership,
remaining composition and final acceptance stay pending.

## Batch C checkpoint: Spotlight favorite shelves — 2026-09-28

Base: `d2bc9e0e`. `home_spotlight_favorites.dart` (145 lines) owns typed builders
for IPTV, watchlist, playlists, Debrify TV and Stremio TV shelves. IPTV favorites
and custom lists share rendering while retaining their distinct open callbacks.
Production dispatch remains in the root; source data/actions are borrowed.
Root: **12,260 → 12,179 lines**.

Review preserves titles, channel versus title shapes, artwork fallbacks, watched
identity, caption flags, playlist progress, live-only preview eligibility and
volume lookup at preview creation. The preview compatibility export remains in
the root. Existing profile-owned controllers and playback actions are unchanged.

**82 tests pass**: the five favorite/playlist/watchlist Home screen suites,
Spotlight IPTV preview and Spotlight board tests. Receipts:
`.git/refactor-evidence/phase5/spotlight-favorites-{tests,analyze-final}.txt`.
Analysis retains **838 identical diagnostic identities**; architecture passes
**531 files**; formatting/diff checks pass. No emulator used. Remaining stage
cell/actions, navigation, lifecycle and final acceptance remain pending.

## Batch C checkpoint: Spotlight shelf and Search composition — 2026-09-28

Base: `8057f8eb`. Home's Spotlight shelf/card projection now lives in
`home_spotlight_shelf.dart` (150 lines), and Search's shelves-only board composition
in `search_spotlight_board.dart` (98 lines). Production uses both; root falls
**12,394 → 12,260 lines**. Home's Spotlight route callbacks and favorite-card
projection remain root responsibilities; this does not close all composition.

Review preserves stable shelf ids and borrowed focus nodes, continuation progress
conversion and episode-art fallback, preference-aware Options dispatch, collection
art/shape/caption rules, and catalog card cache usage. Search captures the original
section list; paging resolves that section against the current list before loading.
Its status reservation, remote actions, watched identity and quick-play gating
remain unchanged. No new resources or data access.

**70 tests pass**: 59 Spotlight board/cache and Catalog Search screen tests plus
11 real-screen Spotlight progressive-loading/paging/focus checks. Receipts:
`.git/refactor-evidence/phase5/spotlight-composition-{tests,integration,analyze-final}.txt`.
Analysis retains **838 identical diagnostic identities**; architecture passes
**530 files**; formatting/diff checks pass. No emulator used. Remaining navigation,
composition, lifecycle and final acceptance stay pending.

## Batch C checkpoint: Classic composition and catalog status — 2026-09-28

Base: `54b76d11`. Classic's hero/status/rows/media composition now lives in
`home_classic_board.dart` (66 lines); Search owns its shared fixed-height status
strip in `catalog_search_status.dart` (36 lines). Production callers use both.
Root: **12,458 → 12,394 lines**. Ordered-row selection remains in a named root
method, evaluated at the original Builder boundary; its final ownership remains
open with the row/action composition work.

Review preserves live hero configuration reads, hero/status visibility, layer
order, dimming signals, boxed video geometry, row evaluation timing and separate
Home/Search ordering. The status strip keeps its 16-pixel reservation, colors,
text/pluralization and non-focusable behavior. No new resource owner or data call.

**26 tests pass**: 18 Classic layout/hero/rows and Catalog screen checks, plus
eight real-screen Classic progressive-loading/paging/focus checks. Receipts:
`.git/refactor-evidence/phase5/classic-board-{tests,integration,analyze-final}.txt`.
Analysis retains **838 identical diagnostic identities**; architecture passes
**528 files**; formatting/diff checks pass. No emulator used. Remaining navigation,
composition, lifecycle and final acceptance remain pending.

## Batch C checkpoint: Tonight and Canvas composition — 2026-09-28

Base: `231b8fd8`. Tonight (90 lines) and Canvas (78 lines) now compose their
boards in Home presentation. Tonight owns queue/card/rail geometry and caption
composition; Canvas owns stage/tabs/shelf composition. Root:
**12,555 → 12,458 lines**. Production uses both; old composition bodies are removed.

Review preserves rail snapshots, lazy visual settings and cell creation, media
visibility/geometry, host-context labels and focus-seeding order. Canvas card
actions remain unchanged in a named root method. Tonight's existing adjustment
when geometry hides its queue still calls back to the same focus-zone state at
the same point; removing that build-time mutation remains D, not claimed complete.
No new owned resources, providers or data calls were introduced.

**28 tests pass**: 15 Tonight layout/queue/rail/integration checks and 13 Canvas
layout/shelf/tabs/integration checks. Both use the existing
`test/home_progressive_screen_test.dart` and
`test/home_progressive_pagination_test.dart` filtered to the layout, including
late catalogs, covered routes, paging and deferred focus. Receipts:
`.git/refactor-evidence/phase5/{tonight,canvas}-board-tests.txt` and
`tonight-canvas-analyze-final.txt`. Analysis retains **838 identical diagnostic
identities**. Architecture passes **526 files**;
formatting/diff checks pass. No emulator used. Remaining composition, navigation,
lifecycle and final acceptance stay open.

## Batch C checkpoint: Atrium and Mosaic board composition — 2026-09-28

Base: `974a5e22`. Atrium (156 lines) and Mosaic (81 lines) now compose their
boards in Home presentation. Production uses both. Atrium owns its adaptive wall
budget, dossier, focused rail label and one/two-row rendering; Mosaic owns its
poster-grid geometry, identity and rail hint. Shared media remains borrowed.
Root: **12,693 → 12,555 lines**.

Review preserves captured rail/count timing, lazy visual settings, host-context
labels, scaled caption/identity constraints, Atrium's second-row eligibility and
Mosaic's live-only surface. Geometry still reaches the existing cell/navigation
callbacks; no new focus resources or data operations were introduced.

**29 tests pass**: 14 Atrium layout/row/identity checks, four Atrium real-screen
checks, and 11 Mosaic layout/real-screen checks. Integration uses
`test/home_progressive_screen_test.dart` and
`test/home_progressive_pagination_test.dart` filtered to each layout, covering late
catalogs, covered routes, pagination and deferred Down focus. Receipts in
`.git/refactor-evidence/phase5/`: `atrium-board-tests.txt`,
`atrium-board-integration.txt`, `mosaic-board-tests.txt`,
`atrium-mosaic-analyze-final.txt`. Analysis retains **838 identical diagnostic
identities**. Architecture passes **524 files**; formatting and
diff checks pass. No emulator used. Remaining layouts, resource ownership and
final acceptance stay open.

## Batch C checkpoint: Deck board composition — 2026-09-28

Base: `c8752712`. `home_deck_board.dart` (124 lines) owns Deck's rail-first
geometry, floating media card, next-title peeks, responsive identity and lazy
poster/favorite strip. Production route wiring retains focus seeding and actions;
media/settings reads and card sizing remain lazy, with the selected rail captured
as before. Review preserves item count timing, host-context labels, layer order,
full-bleed card dimensions, favorite width and focused-column preview updates.
Root: **12,769 → 12,693 lines**.

**17 Deck layout/peeks/identity tests and 4 real-screen Deck tests pass**. Commands:
`flutter test test/features/home/presentation/home_deck_layout_test.dart
 test/features/home/presentation/home_deck_peeks_test.dart
 test/features/home/presentation/home_stage_identity_test.dart`; then the two
`test/home_progressive_{screen,pagination}_test.dart` files with `--plain-name deck`.
The integration covers late catalogs, covered routes, pagination and deferred Down
focus. Receipts: `.git/refactor-evidence/phase5/deck-board-{tests,integration,analyze}.txt`.
Analysis retains **838 identical diagnostic identities**; architecture passes
**522 files**; formatting/diff checks pass. No emulator used. Remaining layout,
lifecycle and final-acceptance work is unchanged.

## Batch C checkpoint: Promenade board composition — 2026-09-28

Base: `90ece4df`. `home_promenade_board.dart` (89 lines) now composes Promenade's
geometry, media, centered identity, label and lazy cells. Production uses it;
selected-rail snapshots, focus seeding and card actions retain their existing
owners. Visual settings remain lazy reads during layout; label styling still
uses the host context. Review preserves favorite/title sizing, strip constraints,
media gates and captured rail identity. Root: **12,817 → 12,769 lines**.

**14 layout/identity/preference tests** and **4 real-screen Promenade integration
tests pass**, including late catalogs, covered routes, pagination and deferred
Down focus. Commands: `flutter test` on `home_promenade_layout_test.dart`,
`home_stage_identity_test.dart`, `home_layout_preference_screen_test.dart`; then
`test/home_progressive_screen_test.dart test/home_progressive_pagination_test.dart
--plain-name promenade`. Receipts: `.git/refactor-evidence/phase5/promenade-board-
{tests,integration,analyze-final}.txt`. Analysis retains **838 identical diagnostic
identities**, architecture passes **521 files**, formatting/diff checks pass.
No emulator used. Other layouts, lifecycle and final acceptance remain pending.

## Batch C checkpoint: shared Home media composition — 2026-09-28

Base revision: `fde5b480`. `HomeBoardMedia` (80 lines) consolidates 20 repeated
artwork/trailer/live constructors across Canvas, Promenade, Atrium, Mosaic, Deck,
Tonight, Spotlight and Classic. It is a presentation value of borrowed signals
and callbacks, with no subscriptions, players or mutable workflow state. Its
factories return the existing widgets directly, preserving element ancestry.
The route supplies current settings; layouts retain their visibility gates,
geometry and layer order. SearchScreen shrinks **12,962 → 12,817 lines**.

Review matches all six artwork bindings, seven trailer bindings and seven live
bindings to the originals, including full-bleed versus boxed rendering, Spotlight
renderability versus stage activation, volume, artwork budgets and failure/playing
callbacks. Mosaic still uses only its existing live surface; no new trailer path
was added. Player teardown and profile ownership were not changed.

**416 tests pass** (`test/features/home/presentation` and
`test/features/home/home_layout_preference_screen_test.dart`). Existing layer,
layout and screen coverage was reused for this mechanical composition change.
Analysis retains **838 identical diagnostic identities**; architecture checks pass
**520 files** and `git diff --check` passes. Receipts:
`.git/refactor-evidence/phase5/home-media-{tests,analyze-final}.txt`.
No emulator used. Layout-specific navigation/composition and lifecycle ownership
remain pending; this does not claim performance or device acceptance.

## Batch C checkpoint: Home board states and framing — 2026-09-28

Base revision: `656f6751`. Home now owns board state rendering/layout dispatch
(`home_board_content.dart`, 77 lines) and its continuation frame
(`home_board_frame.dart`, 60 lines). The shared Home/Search retry message moved
unchanged to `lib/ui/core/retry_message.dart` (48 lines), registered with the
architecture guard. The route supplies data, actions, focus nodes and lazy layout
builders; Spotlight's existing one-time reveal/focus transition stays at its
original call site pending D. SearchScreen shrinks **13,043 → 12,962 lines**.

Review preserves loading/error/empty precedence, Trakt skeleton reservation,
dedicated TV Search dispatch, Spotlight's content-dependent Classic fallback,
continuation footer visibility/actions and retry autofocus. Hidden layouts remain
unbuilt; Spotlight content projection remains lazy. Classic's existing layers and
row composition are unchanged, now in a separately named root method.

**471 affected existing tests pass** across Home presentation, catalog continuation,
layout preference and catalog repository screens, plus Search presentation.
**One new focused test passes** for dispatch precedence, lazy builders, reserved
rows and Spotlight fallback. Receipts:
`.git/refactor-evidence/phase5/home-board-view-tests.txt` and
`home-board-content-focused.txt`. Final analyzer receipt:
`home-board-view-analyze-final.txt`; the unnecessary assertion introduced by
parameter promotion was removed; **838 diagnostic identities remain unchanged**.
Architecture checks pass **519 files** and
`git diff --check` passes. No emulator used. This checkpoint does not close C/D:
layout-specific composition, resource ownership and the <=300-line facade remain.

## Batch C checkpoint: Discover panel composition — 2026-09-28

Base revision: `646b274e`. `buildDiscoverPanels` (180 lines) composes the actual
embedded media-server, metadata, tracker, addon and local-continuation panels.
The route supplies current data/actions; the feature owns the Source picker and
panel wiring. Selection remains lazy, with unchanged keys and element ancestry.
SearchScreen shrinks **13,144 → 13,043 lines**. This is a presentation checkpoint;
Home composition, Discover resource ownership and route lifecycle remain pending.

Review preserves source-specific open/play behavior (including Simkl browse vs
resume and MDBList's source flag), restricted quick-play suppression, bound/focus
callbacks, shared leading node, fallback selection and local reload-after-return.
Trakt progress projection is still evaluated only for its selected panel.
`MdblistListChoice` moved unchanged into a 59-line shared model with a compatibility
export from the original service; this avoids importing a service into the view.
The architecture guard registers the moved model without adding an exception.

**389 tests pass** across `test/features/discover`, `test/features/search`,
`test/services/mdblist/mdblist_discover_source_test.dart` and
`test/services/mdblist/mdblist_service_test.dart`. A new panel contract test covers
callback distinctions, quick-play gating, fallback/reload and lazy progress;
existing Discover screen tests cover production integration. Analysis retains
**838 identical diagnostic identities**; architecture passes **516 files**.
Formatting and `git diff --check` pass. Final receipts:
`.git/refactor-evidence/phase5/discover-panels-{tests,analyze}-final.txt`.
No emulator used; full C+D integration and device/performance acceptance remain
pending. The existing legacy panels' internal service ownership was not expanded.

## Batch C checkpoint: shared Search focus/navigation — 2026-09-28

Base revision: `c031fb5f`. `SearchFocusController` (130 lines) now owns the
query/mode focus nodes, content-entry policy, caret return, responsive selector
thresholds and delayed Sources visibility timer. Production route handlers delegate
to it with current targets; result/board nodes and text remain borrowed. No data
access or duplicate query state was introduced. SearchScreen shrinks
**13,245 → 13,144 lines**. Home/Discover composition and lifecycle remain open.

Review preserves Discover-first entry, Search's visible-result gates, Spotlight
shelf entry, Home layout target selection, empty-TV/sidebar and loading/no-op
behavior, selector labels/thresholds, 250ms blur delay and refocus cancellation.
The route retains listener registration timing and resource teardown placement;
controller disposal cancels pending hides and is idempotent.

**234 targeted tests pass** (`flutter test test/features/search
 test/tv_search_focus_handoff_test.dart`), including three new checks covering
entry/selection/caret behavior, timer/refocus/disposal and selector breakpoints.
`flutter analyze` retains the **same 838 diagnostic identities** as the preceding
checkpoint; no additions/removals. Architecture check passes **514 migrated files**;
formatting and `git diff --check` pass. Receipts:
`.git/refactor-evidence/phase5/search-navigation-{tests,analyze}.txt`.
No full-suite rerun for this presentation-only checkpoint; the next combined C+D
gate remains pending. No emulator used; device/performance acceptance stays pending.

## Batch C checkpoint: Keyword focus ownership — 2026-09-28

Base revision: `3a4c717c`. `KeywordFocusController` (167 lines) owns Keyword row,
tab, toolbar, Sources-button and arrival-pill nodes, their cleanup, tab reveal and
keyboard traversal. The root delegates node synchronization, restore/reset and
final disposal; it no longer creates/disposes those nodes in several separate
places. Route-dependent search/sidebar and above-toolbar targets remain callbacks.
The controller owns only presentation resources, with no copied query/selection
state, storage calls or Riverpod registration. SearchScreen shrinks
**13,393 → 13,245 lines**; shared query/mode and Home/Discover ownership remain open.

Review preserves node labels, fixed toolbar capacity, grow/shrink behavior, focus
reanchoring before removal, post-frame disposal, tab-scroll timing, ignored key
repeats, edge/sidebar routing and the empty-results arrival target. Final cleanup
is idempotent and retired controllers reject navigation; already queued removed-node
cleanup still completes. Ordinary query resets retain their immediate-clear path.
Keyword cleanup is grouped at the route's existing focus-disposal stage; native
teardown and other feature controllers are unchanged.

**229 existing Search/focus tests pass**, plus **two new focused tests** for shrink
and deferred disposal, keyboard boundaries, pending arrivals and retired dispatch.
The initial new-test compile failure used an unsupported physical-key constant;
correcting that fixture passed without production changes. Analyzer: **838 unchanged
identities**; **513 migrated files pass** architecture checks; formatting/diff checks
pass. Receipts: `.git/refactor-evidence/phase5/keyword-focus-tests.txt`,
`keyword-focus-focused.txt`, `keyword-focus-analyze-final-2.txt`. No emulator or
full-suite rerun. Continue with shared Search navigation and Home/Discover composition;
D resource coordination/facade and E final acceptance remain pending.

## Batch C checkpoint: Keyword page composition — 2026-09-28

Base revision: `0185bcac`. The live route now composes `KeywordSearchPage` and its
cinema/mobile frame, searching strip and arrival pill (277 cohesive lines), plus
`KeywordSourceTabs` (126 lines). Existing immutable search/results state is passed
through; inactive page states use lazy builders. No duplicate application state,
new DI framework or new resource owner was added. Original implementations and the
unused source-label wrapper are removed. SearchScreen shrinks **13,641 → 13,393**.

Review preserves loading/error/empty precedence, provider counts and order,
selection lockout, cinema key/callbacks, mobile overlay eligibility, always-mounted
tabs, focus-node mismatch fallback and the difference between touch adoption and
remote adoption-plus-row-focus. Scroll restoration, source-switch focus anchoring
and resource ownership remain explicit C/D work in the route. This is presentation
composition, not a claim that its lifecycle has migrated.

**226 Search feature tests pass** after page/tab extraction; **22 affected tests
pass** after final cinema/mobile composition, covering stream publication, cache
completion, profile retirement, controls and source dialogs. Analyzer retains
**838 identical diagnostic identities**. **512 migrated files pass** architecture
checks; changed declarations/files are formatted and diff checks pass. Receipts:
`.git/refactor-evidence/phase5/keyword-page-tests.txt`, `keyword-page-final-tests.txt`,
`keyword-page-analyze-final-2.txt`. No new tests duplicating the moved implementation,
full-suite rerun or emulator use. Continue with Search focus/navigation ownership
and Home/Discover feature composition; final acceptance remains pending.

## Batch C checkpoint: Keyword rows and shared results pane — 2026-09-28

Base revision: `7a6187ff`. `KeywordResultsList` (134 lines) renders the existing
immutable Keyword results state and source appearance, with explicit row-action
callbacks and borrowed focus/scroll resources. Row keys, copy availability,
stream/selection behavior, labels, badges and neighbor focus rules are preserved.
Selection/playback/menu dispatch and above-list focus remain with their route owner.
The parent no longer renders individual rows or duplicates their metadata formatting.
SearchScreen shrinks **13,754 → 13,641 lines**; page/cinema/navigation composition
still remains, so this does not declare the Search feature complete.

Both Keyword and Sources now use the existing `SourceResultsPane`, relocated to
`lib/ui/core/` with a compatibility export at its old path. Its implementation is
unchanged apart from the import path. This removes the duplicate Keyword lazy-list,
user-drag freeze and parked-arrival overlay layout. Padding, 1,200-pixel cache,
notification propagation and empty-result arrivals match the existing implementation;
the SDK maps the old numeric cache extent to the same pixel extent. No new controller,
state model, provider, service framework or shared mutable state was introduced.

**227 Search/shared-pane tests pass**, plus **seven Sources integration tests** for
cache/focus, binding and copy. One mistakenly named, nonexistent test path made the
first command exit unsuccessfully; all actual suites passed, and the intended
Sources files were then run successfully. Analyzer **838 identities**, no additions
and one removed legacy cache-extent deprecation. **510 migrated files pass** the
architecture check; changed formatting/diff checks pass. Receipts under
`.git/refactor-evidence/phase5/`: `keyword-results-view-tests.txt`,
`keyword-results-shared-pane-tests.txt`, `keyword-results-view-analyze-final.txt`.
No emulator or full-suite rerun. Remaining page/navigation/lifecycle and final
acceptance requirements stay open.

## Batch C checkpoint: Keyword result controls — 2026-09-28

Base revision: `3a947c41`. The production Keyword view composes `KeywordToolbar`
(225 lines) and `KeywordSelectionOverlay` (173 lines). Both receive current values,
actions and borrowed focus nodes; no storage, native calls, Riverpod state copies
or navigation-service imports live in these widgets. The root retains selection
and focus ownership, including the active-source/first-result navigation decisions.
Removed the replaced toolbar, floating entry and selection-bar implementations.
SearchScreen shrinks **14,057 → 13,754 lines**; its final facade target is still open.

Review preserves all facet counts, dynamic provider/select controls, compact mode,
All/None rules, empty Add behavior, selected counts, focus rings, mobile navigation
clearance and existing action callbacks. **223 existing Search feature tests pass**;
**three new control tests pass** for selection, keyboard activation, compact mode
and overlay dispatch. The initial new-test compile failure was a missing services
import; the corrected focused run passes. No production behavior was changed to
satisfy it. Analyzer stays at **839 identities**, no additions; **508 migrated files
pass** architecture checks. Changed code formatting/diff checks pass.

Receipts: `.git/refactor-evidence/phase5/keyword-controls-tests.txt`,
`keyword-controls-focused.txt`, `keyword-controls-analyze-final-2.txt`. Existing
passing tests were reused after the test-only import correction. No emulator or
redundant full-suite run. Next: Keyword results-body composition, retaining current
scroll/live-arrival and row focus behavior; overall C/D and final acceptance remain
pending.

## Batch C checkpoint: query editing and header presentation — 2026-09-28

Base revision: `d41d1775`. The real Search route now composes `SearchQueryField`
(218 lines) and `SearchHeader` (58 lines). Query editing, clear affordance, keyboard
shortcut actions and responsive placement move out of the root. Controllers and
focus nodes retain their existing route owner; submission, mode/content/sidebar
navigation and data work remain explicit callbacks. No provider or duplicate state
owner was added. Existing Riverpod application dependencies remain unchanged.
The original query-field implementation and private shortcut classes are removed;
SearchScreen shrinks **14,252 → 14,057 lines**, still far above its final facade target.

Review preserves caret-versus-navigation rules, TV shell/keyboard behavior, nullable
suggestions, submit-on-tvOS-end-editing, clear control, styling, widths and breakpoints.
The visibility-dependent Down target remains in the caller and is shared by both
keyboard paths. There is no intentional layout/loading/preview behavior change.
**254 affected tests pass; the two unresolved-suggestion cases remain the same
observed errors in `full-native-owner-c4.jsonl`**. No new analyzer identities: **839**.
**506 files pass** the architecture guard; formatting and diff checks pass. Receipts:
`.git/refactor-evidence/phase5/search-query-view-tests.txt` and
`search-query-view-analyze.txt`. Existing integration coverage was reused instead
of adding tests that mirror this structural move or rerunning the full suite.
No emulator was used. Device/performance acceptance remains pending under the
user's no-emulator constraint. Next: move Keyword results/toolbar/selection as a
cohesive presentation workflow; remaining query/navigation/lifecycle ownership is
still C/D work, not declared complete by this extraction.

## Batch B checkpoint: external launch admission — 2026-09-28

Base revision: `165fd015`. External-player and DeoVR preparation now check the
original launch lifetime after asynchronous settings, selection and disclosure.
The borrowed external-player service accepts optional guards through preferred
player selection, installation checks, custom settings and final process/URL
launches, including fallbacks. Unguarded callers retain their existing behavior.
Accepted episode writes use the existing original-profile write drain. Accepted
external dispatch still emits its return signal if the profile retires while its
response is pending, while stale source/tracker follow-up is rejected. Native
preparation checks retirement between metadata stages and publishes stream-cache
entries only after its final metadata lookup is accepted.

Review: player order, command arguments, disclosure, existing episode-choice and
fallback semantics retained; no platform payload changes or additional framework.
Seven new tests cover scheme discovery retirement, accepted late launch responses,
unguarded behavior, real disclosure-dialog retirement, exactly-once return and
native metadata retirement. **847 affected passes / four unchanged historical
manual-source contract failures**. Final integration after the accepted-return
review: **54 passes**. The initial return test left the existing 30-second timer
pending; it now exercises pause/resume and advances fake time, verifying one return
without changing production timeout behavior. Analyzer: **839 identities**, no
additions against 841; architecture: **504 files pass**. Receipts under
`.git/refactor-evidence/phase5/`: `external-owner-regression.txt`,
`external-owner-final-integration-fixed.txt`, `external-owner-analyze-final-3.txt`.
The last full run remains the 10,205-pass gate at `165fd015`; this follow-up uses
focused coverage and is not represented as a new full-suite pass.

Android debug build passed before the final accepted-return adjustment. A dedicated
TV emulator exercised profile opening, setup skip, Home and remote menu → Search;
no Flutter/AndroidRuntime error entries were recorded. These limited checks do not
prove playback/device parity. On the user's instruction, the emulator was stopped
and further emulator work removed from execution. Device/performance acceptance
stays pending. Continue with C presentation/navigation and D facade/lifecycle work;
do not spend further batches re-auditing closed provider operations.

## Batch B checkpoint: native preparation ownership — 2026-09-28

Base revision: `6aa15644`. All three Sources launch paths now pass their captured
profile owner and committer lifetime into player preparation. The plain
`ProfilePlaybackPreparation` runs in the origin scope and accepts local writes
inside the existing preference barrier, using the existing handoff drain. Native
launch checks retirement before platform dispatch; recovery receives the original
owner. Resolver callbacks compose player lifetime with the existing native switch
token, and the in-app source sheet rejects dismissed/superseded requests. Lazy
provider URL resolution stops subsequent work on retirement and cannot publish a
retired redirect into the shared cache. Existing platform payloads, source ordering,
provider cleanup and retained native commit leases are preserved.

Seven new cases cover real origin-scope writes, barrier retirement, accepted-write
drain, request supersession, initial native URL retirement, redirect-cache rejection
and exactly-once loader handoff without opening a retired player route. Existing
real-profile recovery scenarios now exercise the explicit owner argument. Focused
integration: **29 passes**. Affected regression run: **831 passes and four previously
observed manual-source contract failures**. Analyzer: **841 identities**, no additions
and three removed async-context infos. Architecture: **504 files pass**. Diff checks
pass. A formatter transplant initially split related hunks; compile checks caught
it, complete changed methods were restored, and the corrected verification above
supersedes those failed intermediate runs.

Receipts: `.git/refactor-evidence/phase5/native-owner-regression-fixed.txt`,
`native-owner-integration-tests.txt`, `native-owner-analyze-final-3.txt` and
`native-owner-payload-tests.txt`. The shared resolver signature/native admission
changes warranted a full integration run. `full-native-owner-c4.jsonl` completed
with **10,205 successes / 22 failures / 29 errors / 20 skips**. Exact comparison
against `full-channel-native-retry-c4.jsonl` finds **no new failures/errors, missing
tests or newly skipped tests**, with all **seven added cases passing**. Receipt:
`native-owner-full-comparison.txt`. Application and test files remained fixed
throughout the run. No failure allowlist was changed. Device discovery currently lists macOS,
Chrome and an iPad, with no running Android TV device; this is not device acceptance.
Android debug build (`flutter build apk --debug --no-pub`) passed;
receipt: `native-owner-android-build.txt`. This verifies compilation, not playback
interaction. Available emulator inventory includes `codex_sources_refactor_tv` and
`debrify_tv`, but neither was exercised in this checkpoint. Remaining B work includes
external-player/DeoVR dispatch admission, native metadata preparation review and
actual device validation. C–E remain open.

## Batch B checkpoint: channel actions and native source lifetime — 2026-09-28

Base revision: `cb597482`. Shared channel merge/create/persistence moves from the
context-dependent service and picker into `DebrifyTvChannelActions` (310 lines).
The named `DebrifyTvChannelAddBridge` (51 lines) composes it; all four production
callers use that bridge. The picker now receives callbacks and owns no database
work. Its creation guard retires when the dialog is disposed. Existing native
converters, keyword fallback, counts, provider filtering and cache read ordering
are preserved. The old service file is removed; all four migrated files join the
architecture check. Channel/cache/sync writes use existing transaction arguments
and roll back together on failure or pre-commit retirement. No borrowed database,
repository or cache implementation changes were needed.

Focused channel verification: **25 passes**, including nine new cases for merge,
rollback, transaction-wait retirement, accepted durable writes, real profile scopes,
selection/Back and closing during creation. The first fixture expected in-memory
insertion order; the real cache reads `added_at` in reverse order, and the assertion
was corrected to preserve existing storage behavior. Analyzer identities unchanged.

The native audit then found an early-close regression: Android launch returns
before its player session ends, while the committer previously closed at return.
The first full run (`full-channel-actions-c4.jsonl`) was deliberately interrupted
and is not completion evidence. The launcher now forwards an optional retain hook
from each Sources launch to the native source-persistence session. This lease
survives launch return and releases exactly once after drain, timeout or retirement.
Failed native launch releases its lease while leaving the launch owner alive for
fallback. This does not change platform payloads, native code or existing queue
ordering. Three new regression cases verify real profile commits after native
launch return, final queued switches before release, fallback, and idempotent
timeout release; **19 affected queue/ownership tests pass**.

Final analyzer: **844 unchanged identities**; architecture: **502 files pass**.
Formatting/diff checks pass. Receipts under `.git/refactor-evidence/phase5/`:
`channel-actions-focused.txt`, `native-retention-tests.txt`,
`channel-native-analyze-final.txt`. Full retry `full-channel-native-retry-c4.jsonl`: **10,198 successes / 22 failures /
29 errors / 20 skips**. Identity comparison with the last full gate finds **no new
failures/errors, missing tests or newly skipped tests**, with **62 added successes**
across the saved-cloud, download/ZIP, playlist and channel/native checkpoints.
Receipt: `channel-actions-full-comparison.txt`. The existing baseline helper was
also applied to that completed recording: it flags 42 failures beyond its stale
nine-name checked-in list. All 51 failure/error identities were already observed
in the preceding full gate; that identity comparison passes. No baseline was
rewritten. Receipt: `channel-native-baseline-helper.txt`. An attempted
`--help` invocation unexpectedly started an extra suite because the helper has no
argument parser; that redundant process was stopped and contributes no evidence. Native preparation/recovery owner propagation, source-switch request
cancellation and device checks remain B work; C–E remain open.

## Batch B checkpoint: provider-native playlist persistence — 2026-09-28

Base revision: `4ee21725`. The 115-line plain `SourcePlaylist` owns native playlist
payload policy and originating-profile execution. Both production playlist actions
use it. The UI wrapper retains feedback; `_Resolved` now extends the existing
`AcquiredSource` data model and adds only provider-tab navigation, removing duplicate
fields without changing construction defaults. Playback service: 7,059 lines.
Provider-tab callbacks also reject retired owners before navigation.

Borrowed storage methods accept optional guards around reads/enrichment and inside
the final preference mutation barrier. Existing unguarded callers, enrichment,
dedupe, tombstones and schemas remain. Singles retain playable file IDs, packs retain
folder/per-file IDs, and expiring direct links remain excluded. Thirteen added cases
cover five-provider payloads, original-scope persistence from a foreign zone,
deduplication, actual write-barrier retirement and delayed RD enrichment retirement.
The credential test initially lacked a committed active registry profile; fixing
that fixture made it exercise the authorized HTTP path and retirement as intended.

Verification: **886 affected passes / two pre-existing collection-browser failures**
(the iOS/Android non-TV Spotlight folder cases, also errors in
`full-automatic-acquisition-retry-c4.jsonl`). Sources, Home playlist consumers,
collection-source/browser and vault-migration checks ran. Analyzer: **844 unchanged
identities**; architecture: **498 files pass**. Formatting/diff checks pass.
Receipts under `.git/refactor-evidence/phase5/`: `source-playlist-tests.txt`,
`source-playlist-regression-tests.txt`, `source-playlist-analyze-final.txt`.
The previous full gate remains 10,136 passes. No full/native/device pass is claimed
here. Channel creation/cache writes (including picker-side creation), native
handoff/recovery/generation and C–E remain pending.

## Batch B checkpoint: provider download and ZIP actions — 2026-09-28

Base revision: `648ca15d`. Pack/lazy-link downloads, TorBox ZIPs, Premiumize
transfers/ZIPs and not-cached decisions now use the 257-line plain
`ProviderSourceActions`. The separate picker retains selection order, All/None,
sizes and cancellation; legacy presentation retains clipboard access and feedback.
Every production action supplies its original profile owner. Accepted downloads
remain durable; retirement stops subsequent requests/queue entries. Premiumize
polling has an optional guard; the owned loading handle dismisses only its dialog
before feedback. Provider payloads, retries, explicit-decline cleanup and legacy
best-effort queue feedback are preserved. Playback service: 7,152 lines.

Verification: **755 Sources tests pass**, followed by **13 action tests passing**
after three additional no-key/uncached-decision cases. Fifteen new cases total
cover partial pack failures, queue retirement, lazy-link retirement, ZIP payloads,
Premiumize create/lookup/generate retirement, explicit RD keep/decline and picker
selection/cancellation. Analyzer: **844 unchanged diagnostic identities**;
architecture: **497 files pass**. Formatting/diff checks pass. Receipts:
`provider-actions-regression-tests.txt`, `provider-actions-tests-final.txt`,
`provider-actions-analyze-final.txt`, `provider-actions-analyzer-comparison.txt`
under `.git/refactor-evidence/phase5/`. The previous full gate remains 10,136
passes; no new full run is claimed. Native/device verification and playlist/channel
write ownership remain pending, along with B's native handoff/recovery and C–E.

## Batch B checkpoint: saved provider-cloud preparation — 2026-09-28

Base revision: `9ec8a796`. The 393-line plain `ProviderCloudSource` operation now
owns hashless RD/TorBox/AllDebrid web-download and Premiumize/PikPak file/folder
preparation. The saved-source production path delegates to it with the original
profile owner and live action guard; its retained wrapper only maps playback data.
The legacy playback service shrinks to 7,266 lines. No native player payload or
binding format changes.

Review preserves stable-id lookup, per-play URL refresh, largest-video movie
selection, series ordering/start index, lazy file identities, non-video/ZIP
filtering, Premiumize/PikPak paths, and RD's freshly listed URL fallback when
unrestrict fails. The operation checks ownership across every asynchronous stage.
RD pagination and Premiumize/PikPak recursion forward optional guards through
subsequent requests; unguarded callers retain existing behavior and limits.
Retired operations return no result; current provider failures retain their
existing caller handling. No provider entries are created or deleted here.

All **813 affected tests pass**: Sources plus provider-native binding/picker,
collection-source and PikPak acquisition-retirement suites. The 22 added cases
cover five-provider movie/series preparation, file identities, first-response
retirement, RD pagination/fallback and real-profile endpoint/credential ownership
under a foreign scope. Fixture corrections supplied PikPak's required refresh
token and accounted for AllDebrid's existing POST unlock request. Analyzer:
**844 unchanged identities**; architecture: **495 files pass**. Formatting and
diff checks pass. Receipts in `.git/refactor-evidence/phase5/`:
`provider-cloud-operation-tests.txt`, `provider-cloud-regression-tests.txt`,
`provider-cloud-analyze-final-2.txt`. The last full gate remains the previous
checkpoint's 10,136 passes; this additive guard/extraction uses affected checks,
with the next full run at remaining Sources integration. Native/device and final
migration acceptance remain pending.

## Batch B checkpoint: automatic acquisition and source-switch resolution — 2026-09-28

Base revision: `ba0cfdc2`. Automatic selection/probes and saved torrent acquisition
now pass their originating owner and action guard into `SourceAcquisition`.
Optional owner-scoped execution retains the original endpoint/preferences even
when the caller runs in a foreign captured zone. Provider configuration/picker
calls reject retired actions. Existing provider request order, probe caps, episode
checks and cleanup rules remain; retirement alone does not delete acquisitions.

`SourcePlaylistResolver` replaces both duplicated in-player resolver bodies with
one plain operation. It preserves direct headers, provider selection, magnet
precedence and provider playlist order, including RD's existing playlist/start
ordering. The launch committer supplies its profile/action lifetime. Rejection
and wrong-episode cleanup now share plain functions that retain the original
scope; cleanup may finish after retirement without changing accounts. This does
not yet provide native switch-generation ownership: native handoff/recovery and
supersession remain the next integration boundary.

Invalid-source and cached-link removals now run through `AutomaticSourceBindings`.
Actual cache removal rechecks its guard inside the preference mutation barrier,
matching guarded saves. The real-profile tests cover foreign scopes, retirement
inside provider calls, cleanup with original credentials, delayed pin removal and
cache removal. Sources runtime/DI tests continue to use the actual production
callers; the acquisition fake accepts the new optional owner argument.

All 829 Sources/quick-play/addon/IPTV/direct-reuse tests pass. The validation
contract group retains its four observed historical failures; moved assertions
still check the provider snapshot, guarded removals and remaining-source recovery.
Analyzer: 844 unchanged identities; architecture: 494 files pass. New test fixtures
were corrected to initialize legacy runtime before capturing an owner, preserve
RD's real playlist order and supply the cache stream index. Assertions were not
relaxed to accept different application behavior.

Final review found that the new retirement condition could return before dismissing
an automatic-play overlay. Stopped the first full run intentionally, fixed that
exit and added a production widget regression: retirement during RD acquisition
removes the owned loader while preserving a newer route. Explicit acquisition now
also dismisses its own loading handle instead of popping whichever route is top.
The regression passes. The full retry completes with **10,136 passes / 22 failures / 29 errors / 20 skips**.
Exact comparison with the automatic-binding checkpoint, including its subsequently
corrected signature assertion as an observed pass, finds no new failures/errors,
missing tests or newly skipped tests and **26 added passing cases** (download plus
this checkpoint). The final analyzer still has 844 unchanged identities. The
interrupted full log is not completion evidence. The loader fix and its new test
are included in the completed full retry; the application/test revision stayed
fixed during that run.

Receipts in `.git/refactor-evidence/phase5/`:
`automatic-acquisition-focused-final.txt`, `automatic-acquisition-binding-tests-final.txt`,
`automatic-acquisition-loader-test.txt`, `automatic-acquisition-analyze-final-3.txt`,
`full-automatic-acquisition-c4.jsonl` (interrupted), and
`full-automatic-acquisition-retry-c4.jsonl`. Remaining B paths are provider-native
saved-cloud preparation, pack/zip/not-ready actions, and native handoff/recovery
ownership and device checks. C–E and final device/performance gates remain open.

## Batch B checkpoint: direct download preparation and queue handoff — 2026-09-28

Base revision: `ab7b4fa2`. `SourceDownload` now owns direct-stream authorization,
deferred IPTV preparation, redirect resolution and queue submission. The actual
Sources playback bridge resolves this operation through `sourceDownloadProvider`;
the remaining legacy entry point delegates to the same operation/presentation
adapter. The operation captures the live originating profile before awaiting,
runs in that scope even when invoked from a foreign captured zone, and stops
redirects/submission after profile or view retirement. UI messages and their
three-second snackbar lifetime remain in `downloadSource`.

The existing ten-hop HEAD policy, relative redirects, fallback URL on network
failure, request user agent, names, unsupported media-server behavior and queue
payload are preserved. `DownloadService.enqueueDownload` adds an optional guard
before initialization, after initialization and immediately before synchronous
queue publication. Publication remains the acceptance boundary: later view
retirement does not cancel the durable job. Existing unguarded callers and native
queue payloads are unchanged. This does not redesign the borrowed queue service.

Verification: seven operation tests pass, including all redirect status codes,
cycle limits, client cleanup, foreign scope, retirement while HEAD is pending,
queue rejection and the actual service's pre-initialization retirement gate. The
production Riverpod bridge test passes with injected downloads and original UI
feedback. All 69 existing playback-dispatch, media-server and device-job policy
cases pass. Initial new-test compile errors (non-const profile scopes) and widget
animation timing were corrected; focused reruns pass without changing application
assertions. Analyzer: 844 unchanged diagnostic identities. Architecture: 492 files
pass; formatting and diff checks pass. Receipts under
`.git/refactor-evidence/phase5/`: `source-download-focused-tests.txt`,
`source-download-operation-tests.txt`, `source-download-di-tests-final.txt`,
`source-download-analyze-final.txt`. The full-suite gate remains scheduled after
remaining Sources integration; the optional guard preserves unguarded behavior.

Review confirms this closes the direct-stream download preparation/queue boundary.
Automatic provider acquisition, in-player resolution and native handoff remain B;
ordered teardown remains D. Native/device/performance acceptance is still pending.
The previously corrected saved-direct-recovery signature test is an observed pass
and must remain passing in the next full comparison, despite its original full-run
failure receipt.

## Batch B checkpoint: automatic binding ownership — 2026-09-28

Base revision: `9d1ec429`. Automatic movie/series pins, switch promotion, durable
source descriptors and resolved-link caching now live in the plain
`AutomaticSourceBindings` operation. The Sources playback bridge obtains its
owner factory through Riverpod. Legacy selection, saved-source recovery and
next-episode paths retain the original owner instead of capturing a later profile.
Each launch has a `SourceBindingCommitter` queue and close signal; callbacks run
inside the originating scope and recheck retirement across provider selection,
cache encryption and actual preference writes. The existing Android TV persistence
drain precedes launcher return; external handoff still awaits its commit. This
does not replace native teardown or change player payloads.

The 407-line policy and 100-line committer replace the old UI-service policies.
Series caps, scoped addon identities, movie replacement, fallback retention,
PikPak exclusions and optional cache failure semantics are preserved. Shared
`ResolvedPlaybackLinkCache.save` accepts an optional write guard; unguarded callers
retain their existing behavior. No schema, engine or dependency upgrade is included.

Checks so far: all 64 existing binding/playback tests and seven new real-profile
ownership tests pass. New cases cover foreign captured scopes, retirement during
provider selection, queued callbacks, encryption/write barriers, delayed tombstones
and independent players. Analyzer: 844 diagnostics, no added identities (one
existing brace lint removed); architecture: 490 files pass. Receipts in
`.git/refactor-evidence/phase5/`: `automatic-bindings-existing-tests.txt`,
`automatic-bindings-owner-tests.txt`, `automatic-bindings-analyze-final.txt`.
The shared callback/cache full run (`full-automatic-bindings-c4.jsonl`) finishes
with 10,109 passes / 23 failures / 29 errors / 20 skips: seven added passing tests,
no missing tests or new skips, and one newly failing source-text assertion that
expected the old `_lazySourceCommitter` signature. Updated that assertion to verify
both the preserved preferred provider and the new originating owner. Its focused
rerun passes (`automatic-bindings-signature-test.txt`); the remaining 22 failures
and 29 errors match the preceding full run by identity. The full log remains
unaltered. Only that test assertion and method-header formatting changed afterward;
no application behavior changed and a second full suite was unnecessary. Format,
diff and architecture checks pass. No failure allowances changed.
Provider preparation, download queue ownership and native handoff checks remain
in B. C–E, device/performance acceptance and facade reduction remain pending.

## Batch B checkpoint: manual provider operation ownership — 2026-09-28

Manual preparation now captures the live originating profile/session and runs its
acquisition and rejection cleanup in that scope. It rejects retired work before
magnet resolution and after readiness. The existing live-profile credential
getters remain guarded; a foreign captured zone cannot change the endpoint,
selection preferences or credentials used by the action.

Optional action guards now reach RD add/file-upload/info/select/unrestrict steps,
AllDebrid upload/files/delayed unlock and TorBox torrent-file upload/lookup retries.
PikPak acquisition methods forward guards through authorization, credential reads,
request sending, refresh continuations and captcha retries. An accepted token
refresh retains its existing `ProfileAsyncAuthorization` owner; subsequent
acquisition requests stop after retirement. Captcha coalescing now keys by captured
profile/generation, device and account/action. A retired waiter cannot start a new
captcha request after a borrowed failure, and delayed removal only removes its
own pending entry. Ordinary callers omitting guards retain their request/retry
contract. No cancellation-based torrent deletion policy was introduced: existing
rejection cleanup remains origin-owned, and pre-existing/shared downloads are not
deleted simply because a view retires.

Focused checks: 33 provider/preparation/DI cases, 17 PikPak authentication and
concurrent-device cases, and four real-profile cases pass. The 28 added tests cover
retirement inside provider operations, delayed polling, accepted renewal with no
late acquisition retry, foreign-zone preferences, incoming credentials remaining
intact, rejection cleanup after retirement, and concurrent captcha requests for
two profiles sharing an account/device. Fixture setup corrections supplied the
actual token host and committed/activated the real profile registry; they required
no relaxation of application assertions. Receipts under
`.git/refactor-evidence/phase5/`: `provider-guards-focused-tests.txt`,
`provider-guards-pikpak-final-tests.txt`, `provider-guards-profile-final-tests.txt`.

Architecture checks pass 486 measured files. All 845 analyzer diagnostic identities
are unchanged (`provider-guards-final-analyze-2.txt`). The shared-provider full gate
(`full-provider-guards-c4.jsonl`) completed with 10,103 passes / 22 failures /
29 errors / 20 skips. Exact comparison with `full-source-acquisition-c4.jsonl`
finds no new failures/errors, missing tests or newly skipped tests, and 28 added
passing cases. Base revision: `8d37de44`. Native payloads, engines, dependency
versions and storage formats are unchanged. Automatic binding/action ownership and native/device acceptance remain
open in B; this checkpoint does not close C–E or the whole migration.

## Batch B checkpoint: shared provider acquisition and manual-pin DI — 2026-09-28

Manual binding now obtains `ManualSourcePreparation` through Riverpod's
`sourceAcquisitionProvider`/`manualSourcePreparationProvider`. The operation owns
readiness and the existing RD/AllDebrid rejection cleanup. Legacy playback shares
`SourceAcquisition`; its retained `_add` adapter translates provider folder data
into the same navigation callbacks. Acquisition no longer constructs UI callbacks
or imports screens. The 436-line main operation and 216-line PikPak operation keep
existing requests, file selection, ordering, lazy links and error semantics.
Magnet precedence and ordering have shared data implementations. `PlaylistEntry`
is now a plain shared model with a compatibility export at its former screen path.
The replaced legacy implementations are removed, not retained as parallel paths.

Focused existing coverage: 688 passes and the same four historical failures in
`manual_source_validation_contract_test.dart`, verified against the latest full
baseline by identity. New coverage: 14 real-provider HTTP fixture cases exercise
single files/packs/cache rejection for RD/TorBox/Premiumize/AllDebrid, cleanup of
owned rejected acquisitions, TorBox cached-only payload and stopping subsequent
TorBox/Premiumize operations after retirement. Three production pin DI cases cover
ready/retired/failed responses and actual writer dispatch. Existing PikPak bridge
cases cover its request sequence, polling outcomes and retirement. The DI fixture
required a configured email and completers created outside the widget fake-async
zone; initial fixture timeouts were corrected without application changes.

Analyzer comparison preserves all 845 diagnostic identities; 486 measured files
pass architecture checks. Receipts: `source-acquisition-focused.txt`,
`source-acquisition-provider-tests.txt`, `source-acquisition-di-tests.txt`, and
`source-acquisition-final-analyze.txt` under `.git/refactor-evidence/phase5/`.
The full gate was required because the shared automatic acquisition path and
playlist model ownership changed. `full-source-acquisition-c4.jsonl` completed with
10,075 passes / 22 failures / 29 errors / 20 skips. Exact identity comparison with
`full-title-actions-retry-c4.jsonl` finds no new failures/errors, missing tests or
new skips, and 17 added passing cases. Historical failures remain unchanged.

Review scope: no native payloads, provider APIs, persisted schemas or native
engines changed. Existing device evidence remains scoped to its prior scenarios;
this host checkpoint does not claim native/device acceptance. Batch B remains open
for reachable internal provider authentication/retry/preferences guards, automatic
binding writes and native handoff. In particular, high-level `canContinue` checks
do not prove that a multi-request legacy provider API stops internally on retirement.
Base revision: `a619feb2`.

## Batch A checkpoint: title-write acceptance and transitive ownership — 2026-09-28

The existing accepted-local-write registry now lives in the 28-line
`ProfileLocalWrites` helper. History removal retains its compatibility drain;
the profile lifecycle drains the same registry at the same handoff point.
Watched-title actions and successful reset snapshot writes join it. This keeps
accepted local flags, history, resume, recovery and sync-journal sequences inside
the originating profile's handoff. Writer failures still reach their caller and
do not strand the drain; no second registry or mutation lock was added.

Watched-title actions capture their scope before awaiting and distinguish
retirement from success. Their tracking-policy reads forward the existing guards
through scrobble-preference migration, credential reads and disconnected fallback
writes. Trakt, Simkl and MDBList title commands now forward action guards through
authentication/credentials and sending; retirement prevents later tracker steps.
The pre-existing shared token-refresh owner remains unchanged. Episode-only
coordinator flows are outside this title-action change.

MDBList separates sending permission from acceptance of an already-issued write.
A retired profile cannot accept its response or invalidate incoming state; a closed
view may still invalidate its owning profile's cache after an accepted success.
The common mutation path also checks ownership between synchronous revision
listeners. Reset playback reads, clears, history writes and local snapshot commits
use their existing profile guard/drain policies. The UI-facing action contract and
reviewed refresh order remain unchanged.

Focused validation: 89 existing checks, 45 ownership/policy/scrobble checks and 93
MDBList/action/reset checks pass (overlapping groups). New cases cover accepted
watched deletion/recovery, held credential/preference barriers for each tracker,
retirement between forced tracker writes, late MDBList responses and synchronous
listener retirement. Analyzer identities remain 845 and architecture checks pass
477 measured files. Receipts in `.git/refactor-evidence/phase5/`:
`title-write-existing-tests.txt`, `title-write-new-tests.txt`,
`title-write-mdblist-tests.txt`, `title-write-final-analyze-2.txt`.

A full run was required because the local lifecycle drain and shared mutation
transport changed. `full-title-actions-c4.jsonl` completed with 10,049 successes,
22 failures, 38 errors and 20 skips. Its nine extra errors came from one ten-minute
Home pagination timeout followed by eight test-framework conflicts in the same
file. The first case passed in isolation (4.5 seconds), then the entire file passed
(25 seconds) without an application change; receipts are
`title-write-pagination-isolated.jsonl` and `title-write-pagination-file.jsonl`.
Three existing policy test names were restored after expanding their matrix so
baseline identities remain directly comparable. The full retry
(`full-title-actions-retry-c4.jsonl`) completed in about six minutes with **10,058
successes / 22 failures / 29 errors / 20 skips**. Exact comparison against
`full-addon-inventory-c4.jsonl` shows no new failures/errors, missing tests or new
skips, and 37 added passing tests across the intervening checkpoints. The first
run's pagination errors did not recur; both full receipts remain available.

Batch A's listed workflows are now implemented and reviewed. Base revision:
`be638f0a`; this entry belongs to the title-write checkpoint commit. B's remaining
Sources/provider/native boundaries, C/D feature composition and lifecycle/facade,
and E's CI/device/performance acceptance remain open. Closing A does not claim the
whole original numbered phases or migration are complete.

## Batch A checkpoint: injected tracker title mutations — 2026-09-28

Home detail actions now obtain `TrackerTitleActions` through the profile-family
`homeDetailActionsProvider`. The plain shared `ProfileTrackerTitleActions` adapter
owns tracker command dispatch, branded watched/unwatched targets, Simkl drop
cleanup, custom-list reads and reset invocation. Its dependencies remain existing
services; it owns no caches, credentials or competing state. The contract is 44
lines and the implementation 211; both are measured by the architecture guard.
Shared legacy menu callers use the same adapter through a compatibility default.

The Trakt/Simkl/MDBList helpers retain their labels, confirmations, rating/list
selection, navigation callbacks and feedback. Home keeps its reviewed refresh
bridge and route guard. Provider resets preserve the original progress identity;
global reset retains its previous identity and confirmation. Every accepted command
runs in the injected owner's scope; retired dependencies reject new commands and
retired routes suppress feedback. Simkl drop now forwards existing continuation
guards so retirement between status update and cleanup prevents a later request.
No service framework, duplicate state or extra DI system was introduced.

Validation: 70 existing menu/reset/detail checks pass; the updated real-route suite
passes 22 tests, including six new injected-action/retirement cases across all three
trackers and both detail layouts. Another 33 related menu/reset/data tests pass;
the final data suite passes eight cases. Its tests verify actual forced tracker
writes with scrobbling disabled, local completion, ordered Simkl cleanup,
retirement and real origin-scoped persistence from a foreign ambient scope.
These groups overlap; their counts are not additive. Analyzer diagnostic identities
remain 845; architecture checks pass 476 measured files and diff checks pass.
Only changed legacy members were formatted. Receipts in
`.git/refactor-evidence/phase5/`: `detail-actions-existing-tests.txt`,
`detail-actions-route-tests.txt`, `detail-actions-final-related-tests.txt`,
`detail-actions-data-final-tests-2.txt`, `detail-actions-final-analyze-2.txt`.

Review: production Home wiring uses the overridden contract in executable tests,
and the shared menu helpers no longer invoke tracker mutations directly. Existing
modal-return tests retain the production transport checks. A captured scope and
result guard do not by themselves prove every transitive write safe: Batch A
still requires the watched-action sequence and remaining credential/transport,
MDBList and persistence checks. Do not reopen completed menu composition merely
for naming changes. The A+B full-suite gate and device acceptance remain pending.

## Batch A checkpoint: accepted reset deletion and tracker continuation — 2026-09-28

The reset service now includes its complete local deletion sequence in the
existing `LocalHistoryRemoval` lifecycle drain. It retains its captured profile
through playback, finished/history, recovery and sync-journal writes. Retirement
stops subsequent tracker work and global reset notifications, while the accepted
local sequence finishes. Foreign ambient profile scopes cannot begin a reset.
This is a reachable ownership fix; it introduces no new lifecycle registry.

Trakt reset reads/deletions now receive the existing continuation guard through
credentials, authentication and transport. Simkl reset propagates that guard
through authentication, history reads and playback/library removal; an awaited
history read cannot start its deletion after retirement. Accepted Simkl responses
cannot invalidate the incoming profile's caches. Existing active-account ordering,
provider-specific resets and independent failure handling remain covered.

Validation: 101 affected tests and 16 related Simkl checks pass, including seven
new cases covering actual
origin/incoming preferences, finished markers, recovery records, sync journals,
lifecycle-drain blocking, foreign scopes and active/retired Trakt/Simkl history
reads. Analyzer comparison against the addon-inventory checkpoint has no added
diagnostics; three brace diagnostics are removed (845 remain). The architecture
guard still passes 473 measured files. Receipts:
`.git/refactor-evidence/phase5/reset-local-final-tests.txt` and
`reset-local-final-analyze-2.txt`; related checks are in
`reset-local-related-tests.txt`. Only modified Simkl members were formatted.

Review: local acceptance and retirement are intentionally different policies;
a completed accepted deletion is not reported as a failed local write merely
because its initiating view retired. Existing dialog ownership/feedback guards
remain unchanged. Batch A is still open for mutation data boundaries,
watched-action sequencing and remaining MDBList/transitive persistence checks.
This checkpoint does not establish device acceptance or complete the refactor.

## Batch A checkpoint: addon inventory and hydration ownership — 2026-09-28

Addon inventory reads now capture session ownership and invalidation generation
before awaiting. Cache hits use a stable captured list while authorizing resources;
retired reads cannot borrow another profile's cache or repopulate invalidated
inventory. Hydration checks ownership between manifests and before failure-memo
publication/persistence. Its failed-URL memo now belongs to the profile session.
The existing captured authorization still owns durable collection replacement;
management/transfer errors remain actionable and retired display reads return no
inventory. Legacy preference reads receive the same publication guard.

The real-profile tests also exposed an existing recursive-save loop for a borrowed
URL-only addon: its reader cannot persist hydration into the owner's resource, so
the post-save executable reread kept hydrating and saving again. That reread now
re-authorizes once without repeating the hydration save. Ordinary owned hydration
still fetches once; borrowed hydration terminates and preserves the owner's sealed
record. This is an explicit reachable bug fix, not a schema or resource migration.

Validation: **58 targeted tests pass**, including seven new real-registry/cipher
cases for active/failing hydration, profile retirement, invalidation, failure-memo
retirement, encrypted-record preservation and borrowed-record termination/cache
reuse. Tests account for inherited profile grants and resource IDs. Existing
unreadable-sibling preservation, addon imports, metadata policy/cache, series
metadata and catalog-origin tests pass. Analyzer identities remain **848**;
**473** migrated files pass architecture checks; diff checks pass. Changed legacy
members alone were formatted. Targeted receipts:
`.git/refactor-evidence/phase5/addon-inventory-final-tests-3.txt` and
`addon-inventory-final-analyze.txt`.

Because `getAddons()` is a shared Home/Search/Sources/settings boundary, a full
concurrency-4 gate was run: **10,021 successes / 22 failures / 29 errors / 20 skips**,
with a terminal result and exit 1 for historical failures. Exact comparison against
`full-stremio-detail-c4.jsonl` retains all tests, adds 35 across intervening
checkpoints, has no new skips, and confirms the rewatch source assertion now passes.
Against the earlier picker baseline, there are no new failures/errors. Receipt:
`.git/refactor-evidence/phase5/full-addon-inventory-c4.jsonl`.

Catalog action composition is reviewed for A. Remaining A work is detail mutation
and reset data/write sequencing. Remaining feature composition, Sources integration,
lifecycle/facade/CI and native/device/performance gates remain B–E; no whole-phase
or final migration completion is claimed.

## Batch A checkpoint: detail opening orchestration — 2026-09-28

The 69-line `HomeDetailNavigation` now owns origin preparation outcomes,
unavailable-origin confirmation/removal and the exact detail-route lifecycle.
It borrows the existing injected origin repository and explicit presentation
callbacks; no new provider or state bundle is introduced. The production root
prepares its menu/layout snapshots before route push, retaining authentication
loader timing, action arguments and all existing return effects. Its remaining
detail code wires screen state and callbacks for phase C's feature composition.
The root shrinks from 14,261 to 14,248 lines; this is ownership separation rather
than a claim of substantial facade reduction.

Review also tightened the post-deletion continuation from mounted-only to the
originating profile/view guard. Accepted deletion still belongs to its existing
operation; a retired page cannot then refresh a different profile's UI. The
unverified retry message and missing-source dialog copy remain unchanged.

Validation: **67 affected tests pass** (29 existing real-route/unavailable-origin/
layout checks and 38 opening/origin/menu/routing checks). Five new navigation cases
cover pre-push preparation and one return effect, retirement during preparation,
unverified-origin feedback, and accepted deletion with active/retired refresh.
A callback assertion in the new test fixture was changed to `expectSync` after
Flutter's async test guard identified its overlap with pumping. Explicit mounted
checks satisfy context-lifetime analysis without suppressions. Final analyzer
identities match **848** baseline diagnostics; **473** migrated files pass the
architecture guard; diff checks pass. Receipts:
`.git/refactor-evidence/phase5/detail-opening-tests.txt`,
`detail-opening-focused-final-tests.txt`, and `detail-opening-final-analyze.txt`.

Opening orchestration is reviewed. Addon-inventory persistence and remaining
mutation/reset contracts are still pending in A. Screen-state composition,
resource teardown, facade/CI and native/device/performance gates remain B–E work;
this checkpoint does not complete the phase or the migration.

## Batch A checkpoint: MDBList detail read ownership — 2026-09-28

The detail-status adapter forwards its route guard through identity preparation
and title-state requests. Shared IMDb resolution and sync/dropped snapshots retain
profile-session ownership independently of any one route. Closing the initiating
page cannot cancel a sibling's shared read; each page separately rejects retired
status. Foreign captured scopes cannot borrow those caches. Profile retirement
prevents subsequent requests and cache publication, including during API-key reads.
The default key reader now forwards the existing guarded SecretVault migration
contract, so a held migration cannot commit after its owning session retires.

Review found two linked invalidation gaps: the derived dropped-ID cache could
refill from an old response, and a fresh read could still join the invalidated
snapshot's in-flight request. Bucket invalidation now detaches that request (with
identity-safe final cleanup), and the dropped projection checks epoch/bucket
generation before publication. Actual dropped-title mutations detach the derived
in-flight projection too, preserving optimistic updates to an existing cache.
The existing concurrent state/dropped reads, successful same-session coalescing,
cache lifetimes, pagination and unknown-status semantics are retained. Accepted
shared reads, including same-profile credential work, remain service-owned.

Validation: **167 related tests pass** across all MDBList services and Home
continuation/removal/revision integration. The final **12-case ownership suite
passes**, including one additional identity-preparation retirement test added
after that wider run. Earlier detail-reader/real-route coverage also passed (148
combined checks before the final invalidation refinement). New coverage exercises
shared reads with independently retiring routes, session changes, cache hits,
reset/bucket/mutation invalidation with late old responses, transport retirement
while awaiting credentials, and an actual held credential-migration barrier.
The delayed invalidation case reproduced the stale in-flight join before the fix.
Nullable generic inference and newly introduced brace lint were corrected. Final
analysis retains **848** diagnostic identities; **472** migrated files pass
architecture checks and diff checks pass. Only changed legacy members were
formatted. Receipts: `.git/refactor-evidence/phase5/mdblist-detail-final-related-tests.txt`,
`mdblist-detail-ownership-final.txt`, and `mdblist-detail-final-analyze-3.txt`.

Transport guards are optional for other callers; normal error classification and
request contracts retain existing service-suite coverage. No API redesign,
retry loop or native change was introduced. The previous full-suite integration
receipt remains the reference; this checkpoint uses the full affected MDBList
suite and Home integrations. Opening orchestration, addon inventory and the
remaining mutation/reset contracts are still pending, as are batches B–E and
native/device/performance acceptance.

## Batch A checkpoint: Trakt detail status ownership — 2026-09-28

The injected detail reader now forwards its continuation guard into Trakt title
status. The service captures the opening profile-session owner before authentication,
rejects foreign captured scopes, and associates library-cache entries with that
owner. Retired requests cannot borrow or populate the cache, continue through
credential migration, initiate a token refresh after a late 401, or publish title
status. The existing authenticated GET/native-ID guards are reused through the
list and series-watched readers. Existing callers without a route guard retain
normal behavior while receiving profile protection at the title-status boundary.

Review preserved the concurrent four-read structure, 45-second TTL, unknown core
list versus unknown watched semantics, mutation-generation fence and successful
same-profile refresh policy. There is no new cache, provider, retry loop or service
rewrite. The existing Trakt service remains an external legacy dependency; only
changed members were formatted.

Validation: **153 affected tests pass** (104 detail/history/menu checks plus 49
refresh/watched/Continue Watching checks). Eleven new scenarios reuse the real
two-account fixture: movies/series with active, route-retired and profile-retired
responses, late 401s, original/new token selection, cache reuse and incoming
results winning over outgoing responses. Profile tests deliberately omit singleton
reset to exercise explicit owner validation; foreign captured scopes are rejected.
A held preference-mutation snapshot also verifies no retired credential migration
or HTTP request occurs. One introduced test brace lint was fixed; final analyzer
identities remain **848**. **472** migrated files pass architecture checks and diff
checks pass. Receipts: `.git/refactor-evidence/phase5/trakt-detail-final-tests.txt`,
`trakt-detail-related-tests.txt`, and `trakt-detail-final-analyze.txt`.

The immediately preceding full-suite receipt remains the integration reference;
this narrowly forwarded guard uses focused verification rather than repeating the
full suite. MDBList status continuations, addon inventory, detail opening and
mutation/reset boundaries remain A work. Later feature/facade and CI/native/device/
performance gates are still pending.

## Batch A checkpoint: Stremio detail cache retirement — 2026-09-28

Review found that `invalidateCache()`, used by profile lifecycle cleanup, left
recommendation, enriched-metadata and non-recommendation-addon caches intact.
Late network responses could also refill cleared caches. The shared invalidation
now clears those caches and advances a generation. Both detail readers capture
profile-session ownership before awaiting, reject foreign captured scopes, and
fence network publication by generation after accepting addon inventory. That
placement preserves legitimate inventory hydration, which may itself invalidate
caches. The existing provider factory passes each detail route's continuation
check into both reads. Provider priority, metadata selection, bounded concurrency,
cache-hit reuse and ordinary failures are unchanged. This is an explicit
profile/invalidation bug fix, not a purely structural relocation.

Validation: **15 new cache tests pass**, using real service methods and controlled
HTTP responses. They cover cache hits, invalidation/session/route retirement while
requests are pending, incoming results winning over outgoing responses, lifecycle
clearing, foreign captured scope rejection and stale skip-list publication.
Final analyzer identities match all **848** baseline diagnostics; **472** measured
files pass architecture checks. Only changed legacy members were formatted.
The initial test fixture required legacy runtime initialization and valid seven-
digit IMDb recommendation IDs; those fixture failures are corrected.

The shared-service change justified a full-suite gate with concurrency 4. Its
completed outcomes are **9,985 successes / 23 failures / 29 errors / 20 skips**.
Compared with `full-sttv-picker-c4.jsonl`, all original test identities remain,
there are no new skips, and 97 tests were added across intervening checkpoints.
The sole new failure was `rewatch exits before cached tracker reconciliation,
even for S1E1`: its assertion still counted callbacks in the root after the prior
detail-composition extraction. The assertion now checks the actual feature builder
and still requires both rewatch callbacks; all resolver precedence assertions
remain. The corrected test and six detail-composition cases pass (**9 checks**).
The full run predates that test-only correction; it is not represented as an
all-green or final-revision full suite. All other failures/errors match the observed
baseline, and no allowlist changed. Receipts:
`.git/refactor-evidence/phase5/stremio-detail-cache-tests.txt`,
`stremio-detail-final-analyze.txt`, `full-stremio-detail-c4.jsonl`, and
`stremio-detail-rewatch-guard.txt`.

The retained external Stremio service is 3,801 lines; this bounded edit changes
only detail-reader continuation/cache semantics and their existing invalidation
sites. It does not relocate original screen code into that service or declare
addon inventory persistence audited. Trakt/MDBList status cache/credential paths,
opening orchestration and mutation/reset contracts remain A work; feature/facade,
CI and native/device/performance gates remain open.

## Batch A checkpoint: detail reader injection — 2026-09-28

All five `_openItem` loaders now use the 73-line `HomeDetailReaders` and a
52-line profile-family Riverpod factory. The factory captures the opening profile
scope; the plain reader receives callbacks, performs no eager reads, and rejects
requests/results for retired routes or profiles. Authentication/identity gates
stay at their original route-build point. Existing service errors, timing,
recommendation ordering and singleton cache ownership are retained. Simkl receives
the combined continuation guard through its existing service API. Two obsolete
service imports are removed from the screen. This is dependency separation, not
facade reduction: the root is 14,261 lines after explicit guard wiring.

Validation: **89 affected tests pass**, including 20 new reader cases covering
lazy dispatch, exact ID/type/value forwarding, route/profile retirement and error
propagation, plus four real Home detail-route cases across both layouts. Existing
composition, playback, tracker-menu and detail-action tests pass. The initial
nullable generic inference compile error was corrected; final analysis matches
all **848** baseline diagnostic identities. **472** migrated files pass architecture
checks; changed code is formatted and diff checks pass. Receipts:
`.git/refactor-evidence/phase5/detail-readers-final-tests.txt` and
`detail-readers-final-analyze.txt`.

Review: the stateless provider owns no resource or competing cache; service-owned
reads may finish after route closure, with results rejected at the route boundary.
The wrapper does not prove transitive cache/credential safety for the unguarded
Trakt/MDBList/Stremio APIs. Those reachable continuations remain in A's closing
audit, alongside opening orchestration and mutation/reset contracts. No native,
performance, whole-batch or final migration completion is claimed.

## Batch A checkpoint: detail menu ownership — 2026-09-28

The 106-line `HomeDetailMenus` now owns all three detail-menu builders and their
opening-time snapshots. The feature detail builder accepts this single cohesive
menu dependency instead of six separate option/builder parameters. Production
constructs it at the original opening point. Local/Trakt/MDBList membership and
theme color retain their snapshot timing; authentication, bound-source status and
Simkl paused-session eligibility remain live reads when a status rebuilds a menu.
The root shrinks from 14,334 to 14,259 lines, including removal of one obsolete import.

App actions, tracker identity gates, independent Simkl/MDBList strips, local versus
remote removal ordering/colors, status-aware toggles and legacy initial menus are
preserved. No provider, mutable application state or service action was introduced.
The architecture guard permits only the named legacy presentation factories and
status/menu declarations; negative controls reject service classes and mutation
handlers. These are UI factories, not new data/platform access from presentation.

Validation: **76 affected tests pass**, including seven new scenarios covering
identity gates (missing/custom/native/IMDb), app-action preservation, removal
ordering/theme, movie/series distinctions, fixed initial snapshots and live
status/auth/binding/pause updates. Existing layout composition, actual Home detail
routes, Play/source retirement, targeted removal and tracker-menu tests pass.
An obsolete root model import was removed after analysis flagged it; final analyzer
identities remain **848**. **470** migrated files pass architecture checks, and
diff checks pass. Receipts: `.git/refactor-evidence/phase5/detail-menus-final-tests.txt`
and `detail-menus-final-analyze.txt`.

Detail status/recommendation-reader wiring and opening orchestration remain in A,
along with mutation/reset write contracts. Later feature composition, integration,
lifecycle, CI and native/device/performance acceptance remain open.

## Batch A checkpoint: shared detail-layout composition — 2026-09-28

The two production detail routes now use `home_detail_presentation.dart`, a
154-line stateless feature builder. It owns the legacy/merged widget composition
and layout-specific action arguments; it borrows explicit callbacks and owns no
request, provider, mutable screen state or resources. The root retains origin
preparation, menus and dependency wiring, and shrinks from 14,486 to 14,334 lines.
Direct imports of the two detail screens are removed from the root.

The layout flag is captured at route opening, preserving the original choice on
later rebuilds. The merged page retains promised-episode forwarding, Trakt-first
resume, episode-source dispatch, inline ratings, initial episode/hero settings and
PikPak quick-play. Legacy composition retains its different PikPak rule, series
source-hold behavior, source-addon preservation for Watchlist, and artwork callback.
Existing route guards, loader timing, recommendation/enrichment callbacks and return
refresh sequencing remain wired through their existing owners.

Validation: **69 affected tests pass**, including six new movie/series/TV × layout
composition scenarios. They verify no eager reads, exact playback flags/promises,
source/selection/rating dispatch, metadata forwarding and lazy legacy bound-source
reads. Existing real Home tests verify Play and source actions in both layouts,
retirement, targeted dismissal, actual Sources destinations and tracker-menu
ownership. Analyzer identities remain **848**. **469** measured files pass the
architecture guard. The new builder's legacy status/menu imports are restricted
to explicit `show` types; the guard now rejects service-class and unrestricted
imports for these declarations, verified with negative controls. No service I/O
is permitted by this type-only allowance. Diff checks pass and only the changed
legacy member was formatted. Receipts:
`.git/refactor-evidence/phase5/detail-composition-final-tests.txt` and
`detail-composition-final-analyze.txt`.

This completes the duplicated layout-construction boundary, not all of `_openItem`:
menu assembly, status/recommendation-reader wiring and opening orchestration still
need their final feature owners. Mutation/reset contracts and batches B–E remain
open, including full integration and native/device/performance acceptance.

## Batch A checkpoint: Simkl shared resume reads — 2026-09-28

The existing series-resume repository now forwards its view/profile guard through
Simkl paused and next-to-watch readers, including native-library preparation and
next-to-watch credential access. The episode-session cache records the owning
profile session for both cached and in-flight values. It captures the invalidation
generation before awaiting credentials, closing a race where reset during that
wait could make an old fetch appear current. Foreign captured scopes cannot borrow
the active profile's episode cache, and a late old-profile request cannot overwrite
or clear a newer profile's request/cache.

The service retains ownership of an accepted shared episode read: one closing view
must not cancel another consumer. Each caller checks its own continuation after
awaiting the shared result. Same-profile coalescing, cache TTL, payload parsing,
resume timestamps/precedence and existing invalidation behavior are retained. An
accepted shared credential read may finish within its original live profile even
if its initiating view closes; profile retirement stops credential migration and
cache publication. No new provider or generalized cache framework was added.

Validation: **223 affected tests pass**, including ten new cases reusing the real
two-profile/account fixture. Tests cover a closing first consumer with a live
second consumer, a single network request and cache hit, foreign-scope rejection,
new-profile cache winning over an old response, generation invalidation during an
actual credential-write barrier, profile retirement preventing that migration,
and active/retired native paused and next-to-watch preparation. Existing Simkl
service, resume/catalog, continuation-screen, episode menu/native flow, playlist
identity, watched-badge/season and progress-reset checks pass. Five introduced
formatting lints were corrected; final analyzer identities remain **848** and
**468** migrated files pass architecture checks. Diff checks pass; only changed
legacy members were formatted. Receipts:
`.git/refactor-evidence/phase5/simkl-resume-final-tests.txt` and
`simkl-resume-final-analyze.txt`.

This closes the recorded Simkl resume-reader/shared episode-cache boundary.
Detail composition and mutation/reset write contracts remain in A; Sources,
lifecycle, full integration and native/device/performance gates remain pending.
The movie playback cache and unrelated service internals were not reorganized.

## Batch A checkpoint: Trakt uncached-resume preparation — 2026-09-28

Both uncached series selection and resume-label resolution now forward their
existing repository view/profile guard through the injected live-feed adapters.
The guard reaches authentication/credential migration, Up Next and paused-playback
pagination, hidden/dropped filters, watched-history pagination, and final item
selection. Retired actions cannot start the next request or turn a partially read
feed into an accepted resume target. The original concurrent read groups, conditional
visibility/history reads, pagination limits, exact identity matching, merge policy,
fallbacks and legacy no-guard call behavior are preserved.

Validation: **273 affected tests pass**, including ten new cases in the existing
real two-account fixture. Cases cover active/view/profile outcomes while initial
catalog, visibility/history and paginated reads are pending, both selection and
label callers, origin credentials despite a foreign ambient scope, and actual
credential migration held behind a preference snapshot barrier. Existing Home,
Search and Discover Trakt continuation screens, cached resume, catalog playback,
Trakt parsing/merge/calendar/history, native identity, profile refresh and reset
checks pass. A single newly introduced missing-braces lint was corrected;
final analyzer identities are the same **848**. **468** migrated files pass
architecture checks and the diff check passes. Legacy formatting was restricted
to changed members. Receipts: `.git/refactor-evidence/phase5/trakt-feed-final-tests.txt`
and `trakt-feed-final-analyze.txt`.

This closes Trakt's uncached resume preparation boundary; it does not close the
shared Simkl resume-cache/read contract, remaining detail composition, mutation/
reset writes, or later integration/native/device acceptance gates. Existing token
refresh authorization remains the owner of an already-started refresh; retirement
prevents the caller's follow-up requests and result publication.

## Batch A checkpoint: Trakt cached-resume retirement — 2026-09-28

The existing series-resume repository now passes its combined view/profile guard
through the injected Trakt item selector. The optional guard reaches native-show
lookup, next-episode resolution, every episode-progress page and authenticated
GET credential access. Retirement prevents a subsequent page, late credential
migration, a new refresh after a retired 401, retry after an already-started refresh,
and publication of a stale native-show lookup. The repository still suppresses
late selections; the guard now protects the underlying operations too.

Unsubmitted work stops. An already-submitted token refresh retains the credential
service's existing authorization/commit contract; this change prevents its retired
caller from retrying GET afterward. Existing callers that omit the optional guard
retain their request, pagination, retry and fallback behavior. Resume precedence,
paused percentages, exact next-episode coordinates and native identity remain
unchanged. No new state owner, provider, interface or transport was introduced.
Only the changed legacy service members were formatted.

Validation: **247 affected tests pass**, including fifteen new cases using the
existing real two-profile/account fixture: active/view/profile retirement during
next-episode lookup, pagination and native identity resolution; retired 401s;
active/retired refresh completion; and actual credential migration held behind a
preference snapshot barrier. Originating-account headers are verified even under
a foreign ambient scope. Existing series-resume, catalog-play, native identity,
Trakt parsing/merge/calendar/history, profile refresh and progress-reset coverage
passes. Analyzer identities remain **848**, with no added or removed diagnostics;
**468** migrated files pass architecture checks and the diff check passes.
Receipts: `.git/refactor-evidence/phase5/trakt-resume-final-tests.txt` and
`trakt-resume-final-analyze.txt`.

This closes the cached Trakt quick-play lookup's reachable credential/read chain.
Live feed/uncached resume preparation, remaining detail composition and mutation/
reset write contracts remain in A; Sources/lifecycle/device gates remain in their
recorded batches. This focused checkpoint does not replace the later full-suite
integration or final acceptance gates.

## Batch A checkpoint: detail source binding handoff — 2026-09-28

The existing `HomeSourcesNavigation` now owns the shared whole-title binding
payload, torrent/keyword dispatch, missing-identity message and editable keyword
seed. Both former root implementations use one thin composition callback. This
reuses the existing Riverpod navigation dependency; no new provider, state owner
or interface was introduced. The bridge is 172 lines and the root shrinks from
14,525 to 14,486 lines, still under its recorded temporary exception.

Detail menu source editing and the merged page's source button now propagate the
exact detail-route guard through pending repository reads, the editor, cloud/local
selection callbacks and binding-route return. A removed detail cannot open a late
source picker or publish its return effects. The episode screen retains its
intentional post-pop callback contract and existing Home/profile guard. Source
identity, custom-addon/catalog keys, metadata/TV evaluation timing, no-episode
pack binding, three-second error message and keyword seeds remain unchanged.
Transitive Sources writes/native operations remain batch B's responsibility.

Validation: **83 affected tests pass**, including ten new checks: five complete
binding payload/seed scenarios, retired/missing identity dispatch, and four actual
Home detail source-read scenarios (legacy/merged × active/closed). Existing
navigation/real Sources destinations, source editor/repository, detail-action and
tracker-menu tests pass. The first command had one incorrect repository-test path;
the corrected complete group passes. Analyzer identities remain **848** with no
additions or removals; **468** migrated files pass architecture checks and the diff
check passes. Only changed root members were formatted. Receipts:
`.git/refactor-evidence/phase5/source-binding-final-tests.txt` and
`source-binding-final-analyze.txt`. The preceding full-suite gate belongs to
`f8e6697e`; this presentation-only workflow uses the planned affected-test gate.
Remaining batch A work is tracker quick-play/detail composition and mutation/reset
write boundaries; batches B–E and device/performance acceptance remain open.

## Batch A checkpoint: Stremio TV catalog picker — 2026-09-28

The reachable Add to Stremio TV workflow now lives under `features/stremio_tv`:
a 148-line data editor, immutable option/result models, a Riverpod factory that
captures the opening profile synchronously, and the existing picker presentation.
The original screen path remains a compatibility export. Presentation no longer
reads preferences or edits raw catalog records; it retains dialog-local loading,
saving, filtering and focus state. The two identical focus-frame builders share
one borrowed-node widget. The adopted dialog is **780 lines**, reviewed as one
modal interaction/focus owner in the 501–800 band; the old file was **922 lines**.
All six new feature files are included in the architecture guard.

Creation/append retain catalog schemas, exact duplicate identity/name rules,
sorting, messages and TV navigation. The data editor captures the original profile
and checks its live view guard; guarded add/update writes check again at the actual
preference commit after any snapshot barrier. Existing unguarded storage callers
retain their behavior. Explicit corrections: rejected persistence no longer reports
successful creation; a disposed load cannot allocate late focus nodes; completion
removes only its own dialog route; a retired save suppresses feedback and permits
Cancel. Home passes the original detail-route guard through the picker and its
return message. Full-list read/modify/write semantics are otherwise unchanged.

Validation: **122 affected tests pass**, including nineteen new editor/picker
cases. Tests verify real two-profile preference writes despite a foreign ambient
scope, view/profile retirement while held behind a snapshot, actual preference-budget
refusal with tvOS policy enforced in host tests, payload/duplicate rules, create/append/error feedback, TV Select,
covered-route cleanup, retired-save dismissal and disposal during reads/writes.
Existing Home detail/dispatch, tracker menu, Stremio episode policy and preference/
budget tests pass. Analyzer identities remain **848**; **468** migrated files pass
architecture checks. Initial context guards and two new test formatting lints were
corrected before final verification. Only changed legacy members were formatted.

Receipts: `.git/refactor-evidence/phase5/sttv-picker-final-tests.txt` and
`sttv-picker-final-analyze.txt`; original widget/editor retained in
`sttv-picker-original.dart`. Full-suite verification was brought forward because
this picker and its persistence path are shared infrastructure. The first run
stalled on `identity save persists without changing access` for over seven minutes;
its live process was sampled and explicitly interrupted. It is incomplete evidence,
not a regression-free run. All five tests in that file passed separately. The
subsequent `flutter test --no-pub --concurrency 4 --reporter json` completed in
362 seconds: **9,889 successes, 22 baseline failures, 29 baseline errors and 20
skips**. Identity comparisons against both `full-local-removal.jsonl` and
`full-reset-dialog.jsonl` found no missing tests, newly skipped tests or new
failures. The repaired shape-manifest substantial-sweep check passes; eighty tests
were added since the reset-dialog run. Terminal receipt: `full-sttv-picker-c4.jsonl`;
the interrupted run and isolated profile-settings receipt remain alongside it.
Analyzer comparison was independently rechecked at 848 identical diagnostics and
the architecture/diff guards pass. No failure allowances or thresholds changed.

The active plan table now separates remaining workflows from completed removals,
and explicitly requires terminal evidence after a stalled-run investigation.
Remaining source/bind dispatch stays with its recorded Sources boundary review;
other Batch A mutations and later batches remain open.

## Batch A checkpoint: Simkl movie-rewatch write ownership — 2026-09-28

The catalog movie-rewatch reader now forwards its view/profile guard through
Simkl authentication, cached status/library reads, credential migration and the
whole-title unwatched write. The existing four-second read/write deadlines also
retire the operation's guard: `Future.timeout` alone did not prevent a delayed
credential read from submitting its POST after the caller continued. Late status
responses no longer warm the library cache for a retired request. An already
submitted POST keeps same-profile invalidation even after its view/deadline ends;
a changed profile session suppresses that response's cache/revision publication.

Optional guards preserve existing unguarded callers, endpoint/payload contracts,
matching/failure rules and timeouts. No new state owner, transport or retry policy
was added. Changes to the shared legacy Simkl service are limited to this reachable
call chain; other tracker/coordinator/reset mutations remain separately pending.

Validation: **124 affected tests pass**, including eleven new cases reusing the
real two-profile registry/credential fixture. Tests cover originating-account
headers despite a foreign ambient scope, exact removal payload, completed versus
watching status, view/profile retirement during reads and writes, server failure,
unmatched IDs, a late status response after timeout, accepted-write invalidation
after timeout, and an actual credential migration held behind a preference
snapshot barrier past the deadline. The latter retains the unsealed credential
and submits no late write. Existing Simkl, native-identity/episode, reset, tracker
menu, catalog resolver and presentation checks pass. Analyzer identities remain
**848**; **462** migrated files pass architecture checks. Only changed service
members were formatted. No allowances were changed.

Receipts: `.git/refactor-evidence/phase5/simkl-rewatch-final-tests.txt` and
`simkl-rewatch-final-analyze.txt`. Initial checks identified multiline-brace lints
and one nonexistent test-path argument; final checks correct both. This closes
`HomeCatalogPlaybackReaders.prepareMovieRewatch`'s reachable write review, not
Batch A or final native/performance acceptance.

## Batch A checkpoint: catalog Play/Sources presentation — 2026-09-28

`HomeCatalogPlayAction` now owns origin/policy preparation sequencing, resolving
loader presentation, cancellation, episode-identity resolution and final
Play/Sources/Episodes dispatch. It borrows the existing injected repositories,
resolver and artwork owner; no new provider, cache, request policy or native player
was added. Its only allowed legacy-service call renders the existing resolving
overlay. The production screen wires the existing Riverpod dependencies and UI
callbacks; the old orchestration is removed. The bridge is **242 lines**, and the
screen shrinks **14,620 → 14,516 lines**.

Review preserves policy-before-loader timing, addon activation before target
resolution, promised episode and source flags, original catalog metadata, loader
dismissal before launch and in `finally`, awaited player completion and unawaited
Sources dispatch. A separately covered ownership correction passes the exact
detail-route guard through all six detail Play/Rewatch/resolved-Sources callbacks:
closing a detail page during preparation now retires that launch. Non-detail
quick-play callers retain their profile/view guard.

Validation: **53 affected tests pass**, including eighteen direct presentation
cases and four real Home detail Play cases. Coverage includes cancellation,
retirement at preparation/target/identity boundaries, missing outcomes, errors,
view disposal, held player completion, exact target flags/launch payloads, ordinary
versus resolving-overlay flows, and both detail layouts with held origin reads.
Active detail routes launch; closed routes do not. Existing resolver, player
bridge, rewatch guards and removal-route tests pass. Analyzer identities remain
**848**; **462** migrated files pass architecture checks. Only edited legacy screen
members were formatted. Initial verification caught a logging-default/context
check and a test fixture teardown typo; all are corrected in the final receipts.

Receipts: `.git/refactor-evidence/phase5/catalog-play-final-tests.txt` and
`catalog-play-final-analyze.txt`; pre-move orchestration is retained in
`catalog-play-original.dart`. This structural move reuses unchanged loader/native
implementations; it does not certify native/performance acceptance. Remaining
tracker quick-play preparation, reachable mutation writes (including Simkl movie
rewatch), Stremio TV/source dispatch and later batches remain open.

## Batch A checkpoint: catalog Resume-label policy — 2026-09-28

The production Resume label now delegates to `HomeCatalogPlaybackResolver.label`,
using the same injected series resolver, tracker memo and scoped readers as Play.
The screen's six obsolete reconciliation/position helpers and direct movie-state
read are removed. Movie-state existence is read through the existing captured-
profile reader, including its retirement checks. The remaining screen wrapper
loads policy and supplies live view/auth/card inputs; no new provider or cache was
introduced. The entry file shrinks **14,747 → 14,620 lines**.

Review preserves MDBList-owned fast-path coordinates, reconciled series targets,
cached Trakt movie positions, local-first ordinary movies, sequential Trakt →
Simkl → MDBList checks, short-circuit behavior and live authentication reads.
Retired work retains the existing not-started label fallback. The shared resolver
is now **513 lines**: reviewed as one stateless catalog playback/label policy with
explicit data dependencies, no UI/resource ownership and no competing resume
state. Keeping the two policies together preserves their shared cache/identity
contract; this is within the reviewed 501–800-line band, not an oversized exception.

Validation: **122 affected tests pass**, including twelve new label-policy cases;
existing playback, rewatch routing, resume repositories, real Home detail layouts
and movie-source independence checks pass. The existing two-profile reader test
now verifies actual movie preference reads against a foreign ambient scope,
missing-state handling and owner retirement. Analyzer identities remain **848**;
**461** migrated files pass architecture checks; diff/format checks pass. The first
analyzer identified the newly obsolete result-model import; it was removed before
final verification. No full-suite rerun was needed for this covered policy move.

Receipts: `.git/refactor-evidence/phase5/resume-label-final-tests.txt` and
`resume-label-final-analyze.txt`; the pre-move method is preserved in
`resume-label-original.dart`. Catalog loader/launch composition, reachable mutation
writes, remaining detail/source dispatch and later batches remain open.

## Batch A checkpoint: tracker menu continuation ownership — 2026-09-28

Trakt, Simkl and MDBList menu handlers capture the originating session before any
await and run accepted operations inside that captured profile scope. Optional
view guards now cover Trakt/MDBList as well as Simkl. Rating, Trakt custom-list and
MDBList series-collection dialogs reject retired returns; late Trakt list loading
cannot open a picker or publish its empty-list message after retirement. Provider
reset confirmations inherit the same guard. Retired completions suppress menu
feedback and MDBList watched-status activation.

Both Home detail constructors and their inline rating callbacks pass their exact
`HomeDetailRoute` lifetime to the existing action bridge and menu handlers. An
active detail route remains valid beneath its own dialogs; a removed/replaced
route cannot dispatch another action or publish action-return refreshes. Existing
removal routing and tracker-specific refresh ordering are retained. No new
provider, state owner, retry policy or dependency was introduced.

Validation: **67 affected tests pass**, including sixteen new cases. Real mocked
HTTP verifies current versus retired rating submissions for all three trackers,
Trakt list selection and MDBList collection confirmation. A held accepted Simkl
operation verifies captured scope before/after profile publication and suppressed
retired feedback. Existing actual Home detail-route, dispatch, provider reset and
reset-service checks pass. The initial new fixture stalled by awaiting real async
work inside fake widget time; corrected interaction scheduling completes normally.
Final analyzer identities remain **848**; **461** migrated files pass architecture
checks. Only changed legacy functions/members were formatted.

Receipts: `.git/refactor-evidence/phase5/detail-menu-final-tests.txt` and
`detail-menu-final-analyze.txt`. Full-suite comparison remains at the preceding
integration checkpoint; these focused checks do not replace final acceptance.
This closes the menu presentation continuation review, not transitive mutation
safety: tracker/coordinator writes, reset deletion/drain behavior, remaining
catalog action composition and Stremio TV/source dispatch still need their
recorded audits and separation. Batch A and the migration remain in progress.

## Batch A checkpoint: progress-reset dialog ownership — 2026-09-28

Provider-only and all-provider resets now share `runProgressResetDialog`, a
UI-only component with injected confirmation, reset and message callbacks. It
owns the exact loading route and removes that route in `finally`, leaving a newer
page intact. Confirmation copy, safe-area/focus behavior, loader contents, result
messages and provider-specific error handling are retained. All-provider errors
still reach the caller, but no longer strand the loading dialog.

The wrappers capture their originating profile before confirmation, reject a
retired confirmation, retain that scope for an accepted operation and suppress
retired feedback. The provider wrapper also accepts an explicit live guard and
reset callback. This changes presentation ownership, not the reset service's
provider ordering, local-write policy or failure aggregation. Transitive reset
writes and profile-deletion sequencing remain in the action audit.

Validation: 52 focused tests pass, including ten new cases for cancellation,
retirement before confirmation, origin retention across accepted work, disposal,
partial/exception failures and cleanup below a newer page. Existing provider-only,
all-provider, custom-series and Home dispatch tests pass. Analyzer identities
remain 848; 461 migrated files pass architecture checks; whitespace checks pass.
Receipts: `.git/refactor-evidence/phase5/reset-dialog-targeted.txt` and
`reset-dialog-analyze.txt`. A full-suite checkpoint is brought forward because the
shared reset dialogs serve several screens and the preceding checkpoints changed
shared tracker request/cache boundaries.

That full run completed with **9,808 successes / 23 failures / 29 errors / 20
skips**. Compared by identity with `full-local-removal.jsonl`, all prior outcomes
are unchanged except `theme/shape_manifest_test.dart::the sweep is still
substantial`; 108 added tests pass. Investigation found five unchanged themed
radius calls moved into the source editor and bound-source tile, neither yet in
the manifest. Both destinations are now registered with zero bare-radius allowance;
the original 490-call floor is unchanged. The guard passes after this correction.

Final review also preserves `showDialog`'s themed barrier color in the owned
loader route; the existing dialog tests now assert a custom theme's color.
The final affected run passes **54 tests**, with only the previously observed
`no swept file grows a new bare radius` failure. Analyzer identities remain
**848**, and **461** migrated files pass architecture checks. The full run
predates these narrow inventory/theme corrections; it is not represented as a
clean final-revision full-suite gate. No failure allowances were changed.
Receipts: `full-reset-dialog.jsonl`, `reset-dialog-review-tests.txt`, and
`reset-dialog-review-analyze.txt` under `.git/refactor-evidence/phase5/`.
The reset service's transitive write/deletion audit and the other batch-A action
boundaries remain open.

## Batch A checkpoint: exact detail-route ownership — 2026-09-28

Both Home detail layouts now use the same 43-line `HomeDetailRoute` presentation
owner. It owns one named Material route and the existing return-effect sequence;
the duplicated parent completion callbacks are removed. Local and Trakt detail
removal receive that exact owner, while row-menu removal has no detail route.
A delayed result closes only its still-current original route. A covered original
stays on the stack, and a popped original cannot dismiss a newer same-name page.
Retired route callbacks cannot start these removals; accepted local writes still
finish, with retired feedback suppressed. Closing a retired profile's detail
cannot refresh incoming rows/auth or invoke its old return-tab callback.

Validation: 47 affected tests pass, including nine new cases. Five Navigator tests
cover ordinary return, covered/replaced routes, retirement and rejection before
push. Four real Home cases exercise both merged and legacy detail constructors:
hold an accepted removal, cover or replace the page, then complete the removal and
verify the newer page remains. The legacy callback is intentionally void; tests
wait on accepted-write drainage and settled navigation. Existing local/Trakt
removal, detail-dispatch and rewatch contracts pass. Analyzer identities retain all
848 prior diagnostics; 460 files pass architecture checks. Reviewed both detail
constructor payloads and preserved refresh/auth/tab-return ordering. Only edited
screen members were formatted, not the whole legacy file.

Receipts: `.git/refactor-evidence/phase5/detail-route-targeted.txt` and
`detail-route-analyze.txt`; focused owner cases are in `detail-route-tests.txt`.
The Home fixture now accepts optional initial preferences so both existing layouts
can be exercised deterministically. Other detail mutations and their dialog/data
boundaries, catalog composition, native/player lifecycle and final acceptance
remain open. This host checkpoint does not replace device acceptance.

## Batch A checkpoint: Simkl/MDBList removal and cache retirement — 2026-09-28

Home and legacy Simkl menus now share `SimklContinueWatchingRemoval` (51 lines),
a UI-independent operation with originating-profile ownership. Home injects it
through the existing continuation dependency module. Series move to On Hold and
retain success when paused-session cleanup fails; movies retain the cleanup
result. Null means retirement. Sequential writes check ownership after awaits;
optional service/credential guards preserve existing callers' defaults. The menu
keeps its original labels, colors and duration; Home supplies live ownership, and
rating/confirmation returns reject retired actions. Other detail mutations and
clear-progress dialogs still need their separate data-boundary audit.

MDBList reuses its existing controller/repository and capability-aware transport.
The controller now carries the session's captured scope through clear; its paused
eligibility, independent accepted removals, success-only invalidation and retired
feedback rules remain intact. No extra controller or cache was introduced.

Review also distinguished view retirement from profile retirement after accepted
remote writes. Simkl and Trakt invalidate the surviving original profile's caches
when a view closes, without publishing into a different profile. Simkl cleanup
invalidates after a partially completed deletion too. Normal cache invalidation
still precedes revision notifications; cancellation cleanup runs in `finally`.

Validation: 154 affected tests pass, including 21 new cases across transport,
menu and ownership tests. Distinct bound profile credentials, foreign ambient
zones, hold/read/delete retirement, partial cleanup failure, exact payloads,
untouched movie/show matches, success/failure/cancellation snackbars, retired rating
dialogs, MDBList scope continuation and same-profile cache freshness are covered.
The final ordering review is followed by 27 passing focused Simkl cases. Existing
Simkl/MDBList Home screens, native-ID regressions, Trakt scrobble/refresh and vault
checks pass. Analyzer identities remain the same 848; architecture checks now
cover 459 files, including the shared removal operation. Diff checks pass.

Receipts: `.git/refactor-evidence/phase5/tracker-removal-final.txt`,
`simkl-removal-cache-final.txt`, `simkl-removal-analyze.txt`; earlier focused runs
are `simkl-removal-targeted.txt`, `simkl-removal-dialogs.txt` and
`mdblist-removal-audit.txt`. Full-suite verification remains at the planned
integration gate. Exact detail-route ownership, other detail mutations, native
handoff and whole-batch acceptance remain open.

## Batch A checkpoint: Trakt Continue Watching removal — 2026-09-28

Home row/detail removal now uses the owner-keyed `HomeTraktHistoryRemoval`
dependency. It captures the originating profile for the entire operation and
returns cancellation separately from remote failure. The existing service still
removes playback IDs sequentially, then title history, with the original
any-success result. Optional guards now reach removal's DELETE/POST sends,
identity lookup, 401 refresh/resend and credential read/migration. Other callers
retain unguarded defaults; no transport, retry or credential subsystem is replaced.
Already sent requests and accepted credential refreshes retain their existing
completion policy; retirement prevents subsequent removal writes and UI feedback.

Validation: 115 affected tests pass, including 15 new actual-transport/factory
cases. Movie/show payloads, request order, partial failures, empty playback IDs,
foreign ambient scopes with distinct bound account credentials, retirement before
and during writes, active 401 retry and retirement during refresh are covered.
A held preference snapshot verifies retirement cannot seal a legacy credential
or send a removal after the commit barrier. Existing scrobble preference,
credential refresh/disconnect, vault, CW merge/parse, real Home and detail-dispatch
tests also pass. Initial new fixture failures exposed missing registry/account
setup; the final tests use real profile registries and bound encrypted credentials.
Analyzer identities match all 848 prior diagnostics; 458 files pass architecture
checks. Only changed members of oversized legacy services were formatted.

Receipts: `.git/refactor-evidence/phase5/trakt-removal-targeted.txt` and
`trakt-removal-analyze.txt`. Shared methods receive optional guard parameters with
unchanged default behavior; affected transport/auth tests cover those defaults.
The full suite remains at the scheduled integration gate. This closes the Trakt
remote-removal boundary, not all tracker/detail actions: Simkl/MDBList operations,
rating-dialog returns and exact detail-route ownership remain in batch A.

## Batch A checkpoint: IPTV history removal — 2026-09-28

`_removeIptvCwItem` now dispatches through `HomeIptvHistoryRemoval`, injected by
an owner-keyed Riverpod factory alongside the existing IPTV dependencies. The
screen keeps only feedback and row refresh. The operation rejects retired actions,
captures the originating profile, preserves explicit movie URL/route fallback and
playlist-specific whole-series removal, and suppresses stale success feedback.
Existing `IptvMediaStore` transactions still own history/resume deletion and sync
tombstones. `DebrifyTvDatabase.runScoped` already drains admitted operations during
scope closure, so no second deletion queue or storage implementation was added.

Validation: 58 affected tests pass, including six new production-factory tests
using real SQLite files for two profiles. They verify foreign ambient scopes do
not redirect writes, other series/playlists/profiles retain their history and
resume data, each removed item gets both sync tombstones, explicit URL takes
precedence, and retired/invalid requests write nothing. Retirement at the mutation
notification suppresses the result without undoing the accepted transaction.
Existing store, hold-menu and database-isolation tests also pass. Review retained
branch-specific metadata reads and failure propagation. Analyzer identities match
all 848 prior diagnostics; architecture checks pass for 457 migrated files.

Receipts: `.git/refactor-evidence/phase5/iptv-removal-tests.txt` and
`iptv-removal-analyze.txt`. This changes no database schema or native API and does
not require repeating the full suite before the planned integration gate. Tracker
removal and detail mutation remain open: their sequential remote writes and rating
dialog returns need originating-account/retirement review. No device acceptance
or whole-batch completion is claimed by this checkpoint.

## Batch A checkpoint: catalog playback target resolution — 2026-09-28

`HomeCatalogPlaybackResolver` (395 lines) now owns the complete catalog target
selection workflow: rewatch, tracker-owned selections, promised episode overrides,
concurrent movie positions, local history and next-episode/manual-picker fallback.
Its captured-profile readers own legacy storage/metadata calls. A small Riverpod
factory borrows the existing view session's resume resolver and tracker cache, so
the detail label and Play retain one answer. The parent retains loader, episode
picker and player/Sources dispatch; 332 net lines leave the screen (14,685 remain).
No new mutable cache, persistence format or retry policy is introduced.

Validation: 121 affected tests pass, including 16 new resolver/dependency tests.
Coverage includes rewatch without reader calls, exact selection identity, promised
coordinates, concurrent tracker reads and four-second timeout, native/custom IDs,
partial local coordinates, finished-episode advancement, cancellation, actual
profile-scoped history reads and shared versus independent view caches. The
relocated rewatch source guard retains both production callers and now accompanies
behavior coverage. The final resolver/dependency/rewatch rerun passes all 19 tests. Analyzer identities exactly match the previous 848 diagnostics;
456 migrated files pass architecture checks. Reviewed production wiring, removal
of replaced branches and borrowed cache lifetime. Formatting and diff checks pass.

Receipts: `.git/refactor-evidence/phase5/catalog-target-tests.txt`,
`catalog-target-analyze.txt` and `catalog-target-final.txt`. Full-suite validation
remains at the planned integration gate; the last full checkpoint is
`full-local-removal.*`. These host checks do not certify transitive Simkl writes,
native playback, remaining action composition or final facade acceptance. The
plan now lists the remaining A workflows explicitly and removes the old per-slice
verification instruction that conflicted with workflow checkpoints.

## Batch A checkpoint: detail tracker actions and quick-play — 2026-09-28

The three detail action handlers now share a 102-line presentation bridge for
ordered dispatch, special removal delegation, cache invalidation and the exact
provider-specific row refresh rules. It borrows existing handlers/controllers;
it adds no provider, cache or competing state owner. Every dispatch and post-action
refresh checks the originating view/profile. Handler arguments, addon activation,
inline ratings, removal paths and Search-mode exceptions remain unchanged.

Trakt Continue Watching quick-play now reuses the existing captured-profile
series-resume reader with the exact cached card and selection. Simkl's pure
selection mapping lives on its existing data model; its legacy service method
delegates for compatibility. All three tracker quick-play entries reject retired
owners before doing work. Their missing-card catalog fallbacks are retained.

Validation: 84 affected tests pass, including 14 new action/payload checks.
Every provider menu action is exercised in Home and Search modes; clear-progress
waits for its handler then starts all four refreshes together. Tests cover
retirement before/during dispatch, original failure propagation without retries,
live Search mode and native/paused/up-next Simkl payload fields. Existing menu
helper, real Home unavailable-origin, rewatch, resume-repository and Simkl transport
reproduction tests pass. Analyzer diagnostic identities remain 848; architecture
checks pass for 453 files; diff whitespace checks pass. Reviewed callback arguments,
refresh ordering, production caller wiring and deletion of replaced branches.

Receipts: `.git/refactor-evidence/phase5/detail-actions-targeted.txt` and
`detail-actions-analyze.txt`; final commands are terminal. Full-suite verification
remains at the planned integration gate. This checkpoint guards the outer detail
workflow; it does not certify transitive tracker writes, rating-dialog retirement,
Trakt remote removal, or native playback. Those remain in A/B/lifecycle scope.

## Batch A checkpoint: Home source editing — 2026-09-28

The complete detail source-edit/add workflow now lives in `HomeSourceEditor`
(444 lines), with a separate source-row presentation function (127 lines) and
`HomeSourceEditingRepository` (121 lines), wired through a scoped Riverpod factory.
The parent retains one guarded entry point; its direct SeriesSourceService,
LocalBoundSourceService, credential reads, provider-screen construction and old
editor implementation are removed. The native picker is borrowed from the existing
Sources composition. No new cache, state controller or persistence format.

The repository reuses SeriesSourceService's live-profile/mutation guards and
rejects foreign captured zones as the existing Sources adapter does. It retains
series append/dedupe, movie replacement, exact removal, complete-list order and
sequential provider availability reads. Clear-all uses the equivalent guarded
empty-list replacement instead of the unguarded remove-all API.

Explicit interaction fixes: reorder now waits for persistence before refreshing
badges; delayed reloads check that the dialog still exists; closing an emptied
editor targets its own route, preserving any newer route. Entry, picker returns,
provider handoffs and saves reject retired views/profiles. The editor remains a
cohesive presentation workflow; business writes are outside it, and its local
list is display state rather than a competing persistent-state owner.

Validation: 10 baseline source/provider tests still pass, plus 17 new checks and
nine affected Home navigation/unavailable-origin/rewatch tests: 36 passes total.
The real editor is exercised for reorder, movie/series display, delete/clear,
dismissal during reload, local selection, empty-provider fallback and retirement.
All five cloud routes retain their selection-mode/search arguments and guarded
save callbacks; these tests inspect constructed destinations without starting
cloud transports. Repository checks verify real saved ordering/deduplication and
unchanged preferences when a pending write retires at the mutation barrier.
Analyzer identities remain 848 after accounting for the existing onReorder
warning's new file; the test intentionally exercises that retained deprecated
callback. Architecture checks pass for 452 files; diff whitespace checks pass.

Receipts: `.git/refactor-evidence/phase5/source-edit-before.txt`,
`source-edit-after.txt`, `source-edit-home.txt`, and `source-edit-analyze.txt`.
All final runs are terminal. No full-suite repeat for this feature-only checkpoint;
the latest integration baseline is `full-local-removal.*`. Cloud/native internals
and the existing Sources tombstone/guard audit remain B/device acceptance work.
Next A workflow: remaining tracker playback/removal and detail action dispatch.

## Batch A checkpoint: local history removal — 2026-09-28

The local card, detail action and unavailable-origin confirmation now use one
injected `LocalHistoryRemoval` operation. The factory retains the initiating
profile scope across both existing storage calls; those calls retain their actual
WebDAV tombstone and native playback-recovery recording. No persisted format or
storage implementation changed. Retired actions cannot start; accepted deletions
finish both writes, while retired views/profiles receive no UI feedback.

The small shared operation tracks only accepted work. The existing app lifecycle
retires session memory and engine/shell registrations, then drains these removals
before publishing the next profile. This keeps a normal switch/deletion flow from
cleaning up the outgoing profile while its accepted removal still writes. The
caller retains failures; drain completion is released on success or error. No
preference mutation barrier is held across the sequence. The shared file is in
the architecture guard's measured source set; StorageService remains unchanged.

Validation: 31 affected tests pass (six new), including the actual Home unavailable
origin path, playback recovery and profile lifecycle suites. New tests inspect
both profiles' real preferences and native recovery journal after switching during
a held tombstone callback; all journal callbacks retain the origin profile and
unrelated titles survive. Tests also cover pre-start retirement, write failures,
empty IDs and a pending preference snapshot. Analyzer identities remain 848;
448 migrated files pass architecture checks. Reviewed all three production callers,
accepted-write lifetime, lifecycle ordering and preservation of storage semantics.

Receipts: `.git/refactor-evidence/phase5/local-removal-before.txt`,
`local-removal-after.txt`, and `local-removal-analyze.txt`. Full-suite integration
was brought forward because this checkpoint touches the shared profile lifecycle;
it finished with 9,701 successes, the unchanged 22 failures / 29 errors / 20 skips,
and all 31 added tests passing. Every previous test identity retains its outcome
against `full-series-resume-readers.jsonl`. Full receipts: `full-local-removal.*`;
the helper/test processes finished with the expected baseline exit 1. This is
host-level evidence, not a new device/native-recovery certification. Remaining A work includes tracker
playback/removal actions and the detail source-edit/add workflow.

## Batch A checkpoint: Continue Watching hold/menu workflow — 2026-09-28

`HomeContinueWatchingActions` now owns the complete per-view hold/menu interaction:
duplicate-gesture suppression, fresh preference read, quick-play eligibility, all
five row descriptions, modal dispatch, removal completion and return-focus handoff.
The production Home caller supplies live TV/profile/view guards and its existing
row actions. `homeCwHoldPreferenceProvider` supplies a fresh originating-scope
preference reader; there is no new preference cache or application-state owner.

Retirement guards now cover entry, preference return, modal result and removal
completion. The deferred screen focus callback also rejects a retired profile.
Existing active behavior is retained, including IPTV series opening its menu,
PikPak-only removal, preference-read failure fallback and row-specific copy.
The underlying removal/persistence operations have not yet migrated; this does
not claim safe transitive deletion writes or native recovery completion.

Validation: 15 existing affected tests pass before and after; 12 new tests exercise
the actual menu for all five sources, duplicate pending gestures, quick play,
PikPak eligibility, preference failure and retirement at asynchronous boundaries.
Combined result: 27 passes. Analyzer identities are unchanged at 848; architecture
checks pass for 446 migrated files. Diff whitespace checks pass. Review checked
production wiring, live input timing, guard release and removal/focus ordering.
Receipts: `.git/refactor-evidence/phase5/cw-action-before.txt`, `cw-action-after.txt`
and `cw-action-analyze.txt`; all processes are terminal. Full-suite comparison
remains scheduled at A+B integration. Next: remaining Home actions and the complete
local deletion/persistence workflow, including recovery/sync records.

## Batch A checkpoint: series-resume resolver — 2026-09-28

Production detail-label and Play callers now share a per-view/profile resolver
through Riverpod. It owns the 45-second answer cache and concurrent signal reads;
clear/dispose invalidate pending answers. Cancellation returns null and Play stops
instead of interpreting retirement as an unstarted S1E1 result. Availability and
cached-card reads remain after fresh policy loading. Started futures have error
handlers immediately while active failure precedence remains ordered.

Explicit capacity change: the formerly unbounded result cache now retains at most
512 answers by recency of use. Hits do not renew expiry; TTL still begins before
signal I/O. This matches the existing tracker memo capacity convention without
changing progress precedence or introducing retries.

Validation: 111 affected tests pass across resolver, provider lifetime/isolation,
signal readers, decision policy, captured-scope dependencies, real Home Trakt
continuation and rewatch routing. New checks cover cache expiry/invalidation/LRU,
late availability, cancellation at policy/read/guide boundaries, and concurrent
tracker errors. Analyzer diagnostic identities are unchanged: 848 before/after;
architecture checks pass for 444 migrated files. Reviewed real caller guards,
subscription disposal, old-cache removal and production provider dependencies.
The cohesive resolver is within the 301–500-line allowance.

Receipts: `.git/refactor-evidence/phase5/resume-workflow-targeted.txt` and
`resume-workflow-analyze.txt`; both commands finished (tests exit 0, analyzer exit 1
for unchanged legacy findings). The real Home tests emit font fixture warnings but
pass. Full-suite comparison remains scheduled at A+B integration under the revised
plan; this checkpoint does not establish full native/player or transitive-service
parity. Remaining A work: Home action dispatch and deletion/persistence workflows.

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


### Phase 4C — Cinema provider summaries

The actual cinema rail now consumes `projectCinemaSourceProviders`; media-server
message collection is also a pure operation. Both live alongside the compact
strip projection in the 177-line application file. The existing 18-line
`CinemaSourceProvider` class moved unchanged into shared models, registered in
the architecture check and re-exported by the old widget import path. A direct
comparison confirms its class body is identical. The application layer imports
the model rather than a widget; no duplicate summary DTO or new state owner was
introduced. The existing layout is otherwise unchanged (642 lines).

Review retains cinema's distinct semantics: first status label wins, all matching
rows contribute to alias-group counts, zero-count groups remain, keys are sorted
before priority ordering, empty labels become Other sources, and All sources
counts every row. Loading/failure aggregate all matching configurations. IPTV
overrides labels and supplies messages only for retryable failures; media-server
errors retain the last nonnull value. Results and message maps are immutable.
The screen no longer directly imports SourcePriority. Sources is **1,979 lines**;
parent **20,164**. The existing legacy status-type/priority transitive dependency
exception remains for the final boundary audit.

Affected baseline: **236 passes**. Final Sources/cinema group: **239 passes**.
Three new policy cases cover grouping/order/zero counts, first-label precedence,
combined flags/exact request identity, server error precedence, IPTV overrides
and immutable output. Existing production cinema and narrow-strip tests pass.
Final analyzer identities remain **864**, with no additions after removing the
now-unused priority import. Architecture checks cover **106 migrated files**.
New/migrated model and policy/test files are formatted; diff checks pass. Receipts
under `.git/refactor-evidence/phase4c/`: `cinema-projection-before.txt`,
`cinema-projection-focused.txt`, `analyze-cinema-projection.txt` (intermediate
unused import), `analyze-cinema-projection-final.txt`,
`cinema-projection-final-analyzer-comparison.txt`.

Full-suite confirmation: **7,844 successes**, the same **51 baseline failures**
(22 failure/29 error), and **20 skips**. No original-baseline identity is newly
failing, missing or skipped. Every previous row-label checkpoint outcome is
preserved, with **eight new passing tests** from compact/cinema projections.
The allowance is unchanged and the helper still exits 1 for pre-existing
failures. Receipts: `.git/refactor-evidence/phase4c/full-cinema-projection.jsonl`,
`full-cinema-projection-comparison.txt`,
`cinema-projection-previous-checkpoint.txt`.
Remaining Sources UI/focus ownership and manual binding preparation, later
phases, native/performance verification and final CI remain incomplete.


### Phase 4C — Results pane and scrolling boundary

Extracted the 71-line `SourceResultsPane`, wired into the actual Sources body.
It owns the lazy-list/empty-state layout, existing scroll-anchor wrapper and
pending-arrival overlay. The view supplies row/empty builders, the borrowed
ScrollController, layout flags and a user-scroll callback; row actions, focus
nodes, pending-result state and controller disposal retain their original owners.
The replaced inline Stack/list wrapper is removed. Sources is **1,939 lines**;
parent **20,165**.

Review preserves Positioned.fill, empty versus filtered-empty messages, pending
overlay placement, 24/8-pixel TV/touch vertical padding, 10/0-pixel redesign
horizontal padding and the 1,200-pixel cache budget. Notifications continue to
bubble; only ScrollStartNotification with nonnull drag details freezes arrivals.
The deprecated cacheExtent argument moved with its existing diagnostic; it was
replaced with `scrollCacheExtent: ScrollCacheExtent.pixels(1200)`, the exact
conversion used by the installed Flutter 3.44.8 ScrollView implementation. CI
is already pinned to that version and other app widgets use this API; no SDK/
dependency upgrade is involved. The rendering import required by that API is
explicit. Classic/redesigned row builders and navigation callbacks are retained.

Affected Sources/cinema/row-focus/scroll-anchor baseline: **258 passes**. Final
group: **259 passes**. One new boundary test verifies lazy construction, retained
overlay with empty results, programmatic scrolling versus a real drag, parent
notification delivery, and reuse of the view-owned controller after detachment.
Final analyzer has **863 diagnostics**, no additions and one further removed
legacy deprecation versus the previous checkpoint. Architecture checks pass for
**107 migrated files**; new files and the touched body are formatted and diff
checks pass. Receipts under `.git/refactor-evidence/phase4c/`:
`results-pane-before.txt`, `results-pane-focused.txt`,
`results-pane-focused-final.txt` (intermediate rendering import),
`results-pane-complete.txt`, `analyze-results-pane-complete.txt`,
`results-pane-complete-analyzer-comparison.txt`.

Latest full suite remains `full-cinema-projection.jsonl` (7,844 successes,
unchanged 51 failures/20 skips); this leaf uses affected checks. Native focus/
performance parity is not inferred from widget tests. Remaining Sources focus/
lifecycle, binding preparation, later phases and final native/performance/CI
gates remain open.


### Phase 4C — Sources status presentation

Extracted `SourceSearchProgress` and `SourceStatusMessage` into the 56-line
`source_status_widgets.dart`. The actual body now uses these widgets and the
original helper methods are removed. The view retains loading/error/empty-state
decisions and the existing error versus filtered-empty text. The progress strip
still appears only while searching outside cinema layout. Its inherited app
theme dependency remains in the widget; centered messages receive the same
explicit onSurfaceVariant color from the view. Sources is **1,905 lines**;
parent **20,166**.

Review compared the original rendering: progress dimensions/stroke, padding,
spacing, label/font/fade, and centered-message padding/alignment/color remain
unchanged. No state, resource, dependency or application text was introduced.
This mechanical leaf move reuses existing behavior coverage rather than adding
implementation-mirroring tests.

Affected Sources/cinema baseline and post-extraction runs both pass **240 tests**.
Analyzer identities remain **863** with no additions. Architecture checks pass
for **108 migrated files**; the new file and touched body are formatted and diff
checks pass. Receipts under `.git/refactor-evidence/phase4c/`:
`status-widgets-before.txt`, `status-widgets-focused.txt`,
`analyze-status-widgets.txt`, `status-widgets-analyzer-comparison.txt`.
The last full-suite checkpoint remains `full-cinema-projection.jsonl`
(7,844 successes, same 51 failures/20 skips), before the results-pane and status
leaves. Sources focus/lifecycle, binding preparation, later phases and final
native/performance/CI verification remain open.


### Phase 4C — Primary saved-source selection matching

Extracted the 89-line `source_selection_match.dart`, wired through the existing
`_updateSelectedDirect` entry point. Matching now returns the original Torrent
instance plus immutable diagnostic fields; the view assigns the selected row
and retains logging, focus, scrolling and lifecycle effects. Media-server
binding-key lookup is an explicit callback supplied by the existing view boundary,
called lazily only for the primary media-server pin. The replaced matching
branches are removed. Sources is **1,845 lines**; parent **20,167**.

Review preserves primary-pin precedence, first media/IPTV match, complete IPTV
identity, exact addon configuration, candidate index ordering on a copied list,
existing profile/binge selection behavior, and every diagnostic reason/count.
The media branch still omits a match log. No network, persistence or focus side
effect moved into the matcher. The existing Stremio selector and IPTV ownership
helper remain legacy dependencies under the final transitive-boundary audit;
this does not claim their whole service graph is pure or complete the binding
preparation migration.

Affected Sources/cinema/provider-native baseline: **246 passes**. Final group:
**252 passes**. Six new cases exercise primary-only selection, explicit lazy
media lookup, IPTV ownership/catalog matching, exact addon identity, stable
input order and returned row identity, diagnostic reasons and strict binge-group
misses. Initial addon fixtures omitted the model-required addon ID; the fixture
was corrected without changing production behavior. Existing Sources selected
source/focus/cached fallback cases remain passing. Analyzer identities stay at
**863**, with no additions; architecture checks pass for **109 migrated files**.
New files are formatted and diff checks pass. Receipts under
`.git/refactor-evidence/phase4c/`: `selected-source-before.txt`,
`selected-source-focused.txt` (invalid initial fixture),
`selected-source-focused-final.txt`, `analyze-selected-source.txt`,
`selected-source-analyzer-comparison.txt`.

The first full run had one newly observed failure:
`remote_reliable_transfer_test.dart::large binary file arrives intact with bounded
progress blocks`. Transfer content/progress assertions passed, but a `.part` file
remained during the immediate directory assertion. This is not added to the
baseline allowance. The unchanged transfer service sets receipt phase `complete`
before awaiting receipt journal IO and deleting the temporary file; sender
completion can therefore race the assertion. All **18 isolated transfer tests
pass** without changes. A confirming full run is required; the first failed run
and identity comparison remain in evidence. Receipts:
`.git/refactor-evidence/phase4c/full-selected-source.jsonl`,
`full-selected-source-comparison.txt`, `selected-source-previous-checkpoint.txt`,
`selected-source-transfer-isolated.txt`.

The unchanged confirmation run has **7,851 successes**, the same **51 baseline
failures** (22 failure/29 error), and **20 skips**. The transfer cleanup test
passes. No original-baseline identity is newly failing, missing or skipped;
every previous cinema-projection checkpoint outcome is preserved, with **seven
new passing tests** from results-pane and selection matching. The first timing-
dependent failure remains documented; neither its test nor service was changed.
Receipts: `.git/refactor-evidence/phase4c/full-selected-source-confirmation.jsonl`,
`full-selected-source-confirmation-comparison.txt`,
`selected-source-confirmation-previous-checkpoint.txt`.
The historical helper still exits 1 for its unchanged pre-existing failures.
Sources focus/reveal/lifecycle ownership and binding preparation, later phases
and native/performance/CI verification remain unfinished.


### Phase 4C — selected-row reveal presentation

Extracted `revealSourceRow` into
`lib/features/sources/presentation/source_row_reveal.dart` (52 lines), with the
production Sources view delegating its viewport walking and 0.3 alignment. The
view still owns the scroll controller, focus nodes, query/result generations,
focus eligibility and cancellation diagnostics. The helper checks the live
cancellation callback after each frame before accessing nodes, requests focus
through the view callback, and retains the original boundary/unattached exits.
No new state owner, dependency or generic scheduling framework was introduced.
Reviewed against the deleted loop: guard ordering, preserve-focus behavior,
viewport step/clamping and event timing remain the same. Sources is now 1,822
lines; parent 20,168. Other focus/lifecycle and binding boundaries remain pending.

Affected baseline: **265 passes**; final: **269 passes**. Four new widget tests
cover cancellation before node access, forward/backward lazy mounting with the
same focus node, and an unattached controller. Initial test failures were fixture
issues: assertions in an asynchronous callback conflicted with Flutter's pump
guard, and variable-extent list layout probed row zero before the initial scroll
position. Assertions now inspect recorded callback values after pumping; the
bidirectional walking fixture uses explicit item extents. This does not change
the production algorithm's existing treatment of detached node contexts or claim
new coverage for every variable-height backwards-scroll history. Existing cinema
focus, lifecycle and scroll-anchor cases pass. No production behavior was changed
to accommodate the tests.

Architecture check passes for **110 migrated files**. New files are formatted;
diff checks pass. Analyzer retains **863 diagnostics**, with no added identities.
Receipts under `.git/refactor-evidence/phase4c/`: `row-reveal-before.txt`,
`row-reveal-focused.txt` (initial fixture failures), `row-reveal-isolated.txt`,
`row-reveal-focused-final.txt`, `analyze-row-reveal-final.txt`, and
`row-reveal-analyzer-comparison.txt`. The last full-suite checkpoint remains the
selected-source confirmation above; this bounded presentation slice reran the
affected group. Phase 4C and the whole migration remain in progress.


### Phase 4C — manual binding presentation bridge

The Sources view now invokes its manual pin and local picker through
`sourceBindingBridgeProvider`. Its stateless `SourceBindingBridge` (72 lines)
retains IPTV-before-direct-before-torrent dispatch, all metadata arguments and
the existing platform availability check. Every entry point requires the calling
controller's guarded `SourceBindingWriter`; the bridge has no fallback writer,
state, retained context or IO of its own. The existing controller still owns
busy state and successful reload; the view retains external-link rejection and
bind-mode navigation. Sources is 1,808 lines; parent 20,169. The legacy service's
dialogs, authorization and provider preparation remain behind this explicit
compatibility boundary. Their asynchronous profile ownership review is still
required before phase 4C closes. Playback/download calls remain later work.

The architecture guard permits exactly this bridge's two named service imports;
an executable check using substituted import text confirms both imports are
rejected in another presentation file and unrelated storage remains rejected in
the bridge. This scoped allowance is documented in the plan. All **111 migrated
files** pass size/import checks; new/changed Dart methods are formatted and diff
checks pass. Analyzer retains **863 diagnostics**, with no new identities.

Affected baseline: **302 passes / four failures**; final: **303 passes / the same
four failures** in `manual_source_validation_contract_test.dart`: recovery probe
selection, remaining-pin recovery, preferred-provider recovery, and exact-route
startup recovery guards. These failures precede the change. The existing real
Sources direct pin/unpin integration passes through the production bridge. The
new local-picker override test proves no action occurs on build, the screen
passes title/year/movie identity, and the bridge result saves through the real
profile-owned repository exactly once. Controller/profile-race tests also remain
passing. The test substitutes the picker; it does not claim native dialog parity.
Receipts under `.git/refactor-evidence/phase4c/`: `binding-bridge-before.txt`,
`binding-bridge-isolated.txt`, `binding-bridge-focused.txt`,
`analyze-binding-bridge.txt`, `binding-bridge-analyzer-comparison.txt`.


Async review identified a specific remaining preparation boundary: the legacy
`_pickProvider` awaits configuration/dialog selection and then writes a remembered
choice through `StorageService.setDefaultTorrentProvider`, which resolves profile
preferences at that later call. Torrent pinning subsequently awaits magnet
resolution before `_add` reads provider credentials. The guarded binding writer
covers the final saved source, not those earlier preference/credential operations.
These paths need originating-session tests and explicit capture/retirement guards
before the manual binding review can close. Local picker scan/dialog completion
also needs its view/session review. This slice leaves those legacy internals
unchanged and does not claim that introducing a bridge resolves their ownership.


Full integration comparison: **7,856 successes**, the same **51 baseline failures**
(22 failure/29 error), and **20 skips**. No original-baseline test is newly failing,
missing or skipped. Every selected-source confirmation checkpoint outcome is
unchanged; all **five new identities** pass (four row-reveal tests and the local
bridge test). Receipts: `.git/refactor-evidence/phase4c/full-binding-bridge.jsonl`,
`full-binding-bridge-comparison.txt`, `binding-bridge-previous-checkpoint.txt`,
and `binding-bridge-failure-comparison.txt`. The historical baseline helper still
exits 1 because of the unchanged pre-existing failures. Native dialog/profile
preparation, remaining Sources ownership, phases 5–8 and final performance/CI
verification remain open.


### Phase 4C — binding action liveness at preparation boundaries

This is a targeted stale-action behavior correction, separate from the preceding
structural bridge extraction. `SourceBindingController` now supplies both the
existing guarded writer and a live preparation check. The check closes when the
operation completes/errors, the controller generation changes, the view closes,
or the originating profile session retires. The bridge requires and forwards it
to all four manual entry points. Their optional callback preserves compatibility
for other legacy callers; no automatic playback path receives the new callback.
Sources is 1,810 lines; controller 72, bridge 78, legacy playback service 8,891.
The service remains the previously registered interim exception.

The manual entry points reject retired starts and outer async completions,
suppress stale messages, and check before torrent acquisition after magnet
resolution. Provider selection checks again after configuration reads and after
the dialog returns, before remembering a choice. Loader cleanup retains its
captured navigator and ordering. Direct/IPTV authorization and local picker return
checks retain explicit `context.mounted` checks alongside action liveness; an
initial helper-only check was rejected by analyzer and corrected without ignores.
IPTV distinguishes a retired session from an unmounted view in its completion
log. Save/reload ordering and existing controller retry/duplicate rules are intact.

Affected baseline: **288 passes**; final reviewed group: **296 passes**. Five new
controller cases cover preparation and retained-writer retirement on view/profile/
disposal/completion/error. Three bridge widget cases verify stale direct
authorization cannot save/show success, a stale provider dialog cannot remember
its choice, and an active dialog still remembers its choice even if pinning fails.
The provider fixture uses dummy local credentials, a source without a magnet to
avoid network acquisition, and a bounded alternation of real async IO and Flutter
frames until the actual picker appears. Initial attempts used only fake frames or
blocked on a real-zone observer while frame work was pending; those fixture runs
failed or were deliberately stopped for correction. Completion and preference
reads stay in the real async zone, followed by a frame for snack presentation.
No production behavior was loosened to accommodate those fixtures.

Receipts in `.git/refactor-evidence/phase4c/`: `binding-liveness-before.txt`,
`binding-liveness-isolated.txt`, `binding-liveness-bridge*.txt` (fixture iterations),
`binding-liveness-focused-reviewed.txt`, `analyze-binding-liveness-reviewed.txt`.
The earlier interrupted focused run is retained as `binding-liveness-focused.txt`.

This does not yet prove complete ownership of provider preparation. Configuration
and credential reads inside `_configuredProviders`/`_add` still resolve legacy
state across their own awaits. A queued remember-choice write also requires
review at its actual preference commit edge. Local picker internal scans/dialogs
still have their own lifecycle checks to review. Those are explicit remaining
phase-4C requirements; the outer action callback is not a replacement for them.
Native dialogs/devices and the later migration/performance/CI gates remain pending.


Final review: all 111 migrated files pass the size/import guard; changed legacy
methods and the five feature/test files match Dart formatting; diff checks pass.
Analyzer retains **863 diagnostics**, with no added identities. Full suite:
**7,864 successes**, the same **51 baseline failures** (22 failure/29 error), and
**20 skips**. No original-baseline test is newly failing, missing or skipped.
All previous binding-bridge checkpoint outcomes are unchanged; all eight new
regression cases pass. Receipts:
`.git/refactor-evidence/phase4c/full-binding-liveness.jsonl`,
`full-binding-liveness-comparison.txt`, `binding-liveness-previous-checkpoint.txt`,
and `binding-liveness-analyzer-comparison.txt`. The historical helper's nonzero
exit remains attributable to its unchanged baseline failures. Phase 4C and the
whole migration remain incomplete for the responsibilities listed above.


### Phase 4C — queued provider-choice persistence

Closed the specific queued preference-write gap identified in the prior binding
review. The manual picker forwards its live action check into
`StorageService.setDefaultTorrentProvider`. Its optional guarded path opens
preferences outside inherited captured-profile zones, checks again after opening,
then enters the existing preference mutation barrier and rechecks immediately
before calling the nested setter. There is no await between that final check and
the setter. The preferences facade retains its own scope validation, write budget
and change notifications. The outer barrier does not double-count a mutation.
A retired action completes without writing; genuine errors still propagate.
The existing unguarded path and scalar key/schema are unchanged.

No new DI framework or synchronization abstraction was added. This is a bounded
change to a pre-existing legacy primitive, recorded before implementation in the
plan's exception list. StorageService is now 10,745 lines; playback service 8,894.
They retain unrelated app-wide responsibilities. Sources entry/view size remains
unchanged. Provider acquisition and native-picker internals still require their
separate phase-4C ownership review; this closes only the remembered-choice write.

Regression evidence first ran the old setter body with the new optional argument:
**two passes / five failures**. Failures reproduced retired writes, a foreign
captured-scope write, and view/profile/lifecycle retirement while queued. With the
guard, all **eight storage tests pass**, including current/unguarded behavior,
queued live completion and propagation/recovery after a forbidden nested preference
mutation. One additional real bridge/dialog test holds the actual mutation
barrier after the picker appears, returns a remembered choice, then retires the
action before releasing the barrier; it verifies no preference is persisted.
The existing positive picker path remains passing. Combined boundary group:
**12 passes**. Dummy credentials are mock preferences, with no provider acquisition.

Affected suite baseline: **394 passes / two failures**; final: **403 passes / the
same two failures** (`profile_restore_coordinator_test.dart` explicit appearance
restore and `webdav_sync_hot_merge_test.dart` appearance portability). Analyzer
retains **863 diagnostics**, with no added identities. The size/import guard passes
for **111 migrated files**; changed methods/test files match Dart formatting and
diff checks pass. Receipts under `.git/refactor-evidence/phase4c/`:
`provider-choice-write-before.txt`, `provider-choice-write-red.txt`,
`provider-choice-write-green.txt`, `provider-choice-write-integration.txt`,
`provider-choice-write-focused.txt`, `provider-choice-write-failure-comparison.txt`,
`analyze-provider-choice-write.txt`, `provider-choice-write-analyzer-comparison.txt`.
The retired-action test title was clarified after the red run to state only the
observable no-write assertion; its assertion and failure coverage were retained.


Full integration review: **7,873 successes**, unchanged **51 baseline failures**
(22 failure/29 error), and **20 skips**. No original-baseline identity is newly
failing, missing or skipped. Every previous binding-liveness checkpoint outcome
is preserved, with **nine new passing identities**. Receipts:
`.git/refactor-evidence/phase4c/full-provider-choice-write.jsonl`,
`full-provider-choice-write-comparison.txt`,
`provider-choice-write-previous-checkpoint.txt`. The historical helper still exits
1 for the unchanged baseline failures. Provider acquisition, local picker internals,
remaining Sources ownership and all later/native/performance/CI gates remain open.


### Phase 4C — sequential provider configuration loading

Extracted the shared configured-provider/default loop into
`lib/features/sources/data/source_provider_configuration.dart` (35 lines).
The production playback service supplies plain availability/default readers;
manual picker actions also pass their live cancellation check. Silent provider
selection uses the same helper without that optional check. Provider precedence
remains Real-Debrid, TorBox, Premiumize, AllDebrid, PikPak; reads stay sequential,
the saved default is read only when providers are configured, and unconfigured/
case-mismatched/default-`none` values remain unset. Published lists are immutable;
the two original callers only inspect/iterate the list. A null result represents
retirement, separately from a valid empty configuration. Current read errors
propagate without retry; errors from an already-retired read are discarded.
This is extraction plus the explicit cancellation correction, not an optimization
or a change to normal provider precedence. No new interface hierarchy or state
owner was needed. The service remains 8,894 lines; Sources view sizes are unchanged.

Ten data tests exercise ordering/sequential execution, immutable results, defaults,
empty configuration, retirement before/between reads or during the default read,
and current versus retired read errors. A real binding bridge test retires during
the first provider read and verifies the next provider's mock plaintext credential
has not undergone its observable read-time migration; no picker, save or message
is produced. The existing active/retired/queued dialog tests remain passing.
The combined boundary group has **15 passes**.

Affected baseline: **320 passes / four failures**; final: **331 passes / the same
four failures** in the pre-existing manual-source validation contracts. Failure
identities are unchanged. Analyzer retains **863 diagnostics**, with no added
identities. Size/import checks pass for **112 migrated files**, and changed methods
and new/changed test files match Dart formatting; diff checks pass. Receipts under
`.git/refactor-evidence/phase4c/`: `provider-config-before.txt`,
`provider-config-isolated.txt`, `provider-config-integration.txt`,
`provider-config-focused.txt`, `provider-config-failure-comparison.txt`,
`analyze-provider-config.txt`, `provider-config-analyzer-comparison.txt`.

The helper stops subsequent reads after retirement; it does not retroactively
cancel an already-started reader or establish ownership within its credential
lookup/migration. Those internals, torrent acquisition, local picker scans/dialogs,
remaining Sources ownership and the later/native/performance/CI gates remain open.


Full review: **7,884 successes**, unchanged **51 baseline failures** (22 failure /
29 error), and **20 skips**. No original-baseline identity is newly failing,
missing or skipped. Every previous provider-choice checkpoint outcome remains
unchanged, and all **eleven new cases** pass. Receipts:
`.git/refactor-evidence/phase4c/full-provider-config.jsonl`,
`full-provider-config-comparison.txt`, `provider-config-previous-checkpoint.txt`.
The historical helper's nonzero exit is still its unchanged baseline failures.
Phase 4C and the whole migration remain open for the responsibilities above.


### Phase 4C — guarded configuration credential reads

The manual availability path now forwards its action check into the four provider
API-key readers and PikPak enablement/email. These optional guarded branches use a
single private storage helper outside foreign captured-profile zones. They check
before opening preferences, after each async lookup, and around remote-transfer
routing. Existing unguarded calls retain their original paths. The guarded scalar
SecretVault read checks retirement around resource routing and decryption/sealing;
its lazy migration waits on the existing mutation barrier and rechecks both action
ownership and the stored value immediately before writing. A retired read returns
null. Current reads retain their value/format and real errors are not hidden.
No encryption algorithm, credential schema, remote permission, retry policy or
provider order changed. The review found committed resource reads already capture
`ProfileAuthorizationContext` before registry awaits and validate when resolving
secrets; existing in-flight revocation/decryption cases were rerun.

The Sources configuration adapter is the production caller for these guards.
`_add`, other playback operations and the PikPak acquisition session do not yet pass
them and remain under the explicit acquisition review. Existing legacy dependencies
now measure StorageService 10,821 lines, playback service 8,909, SecretVault 415.
These are the bounded callback changes recorded in the plan, not wholesale service
migrations. Sources view and feature/controller sizes are unchanged.

Before changes, Sources/crypto/choice-write tests had **288 passes**, and the
credential/resource authorization group had **27 passes**. Final combined group:
**328 passes**. Thirteen new cases cover the five guarded getters, PikPak enablement,
pending migration on view/profile/lifecycle retirement, replacement while waiting,
normal migration completion, a committed-profile read from a foreign captured zone,
and preservation of use-only remote-transfer denial. The real bridge test was also
strengthened to check that retirement avoids migrating the first credential,
besides avoiding the next read. Deliberately bypassing reader-guard forwarding
makes that test fail because the first dummy credential is rewritten; restoring
forwarding passes the full affected group. This controlled experiment was restored
before further validation. All fixture credentials are local dummy values.

Receipts under `.git/refactor-evidence/phase4c/`: `provider-credential-before.txt`,
`provider-credential-auth-before.txt`, `provider-credential-isolated.txt`,
`provider-credential-wiring-red.txt`, `provider-credential-focused-final.txt`,
`analyze-provider-credential-reviewed.txt`. Initial analyzer runs caught one
multiline-if formatting lint in a new test; it was fixed with braces, not ignored.
The size/import guard passes for **112 migrated files**. Changed methods and test
files are formatted, and diff checks pass. Provider acquisition, local picker
internals, remaining Sources ownership and later/native/performance/CI gates remain
open; the credential review here is specific to manual configuration loading.


Final analyzer review retains **863 diagnostics**, with no added identities.
Full suite: **7,897 successes**, unchanged **51 baseline failures** (22 failure /
29 error), and **20 skips**. No original-baseline test is newly failing, missing
or skipped; every previous provider-configuration checkpoint outcome is unchanged.
All **thirteen new cases** pass, as does the strengthened existing bridge case.
Receipts: `.git/refactor-evidence/phase4c/full-provider-credential.jsonl`,
`full-provider-credential-comparison.txt`,
`provider-credential-previous-checkpoint.txt`,
`provider-credential-analyzer-comparison.txt`. The historical helper still exits 1
for its unchanged pre-existing failures. Phase 4C remains open for acquisition,
local picker internals and remaining Sources responsibilities; later migration,
native/device, performance and CI gates also remain incomplete.

### Phase 4C — API-key acquisition continuation checks

The manual torrent binding entry point now forwards its action check into `_add`.
That existing provider pipeline checks at entry, passes the guard into all four
API-key readers, and checks after each top-level await before a later request or
resolved result can proceed. Real-Debrid, TorBox, Premiumize and AllDebrid continue
to use the captured key for their backend calls. Premiumize's existing awaited
cache condition is now a local boolean so retirement is checked before deciding
whether to continue. Request payloads, playlist ordering, provider metadata and
current-action results are unchanged. Automatic callers omit the callback and
retain their previous behavior. No cancellation framework or additional state
owner was added. Playback service is 8,953 lines under its recorded exception;
Sources view/feature-controller sizes are unchanged.

The cancellation error is contained by the manual binding handler's existing
failure path; it dismisses the captured loader and rejects the retired action
before displaying a message or saving. Provider not-cached exceptions still pass
to their original captured-key cleanup handlers; checks only run after successful
awaits and do not intercept that cleanup. Already-started backend operations are
not rolled back by this change. Their internal work retains the supplied key.
PikPak receives the entry check only: its separate session, polling and recursive
listing/playlist path still needs review. Loader-route/native picker ownership
and device verification also remain pending; retaining the old navigator cleanup
is not proof for every profile/navigation scenario.

Four real bridge tests use a scoped mock HTTP client with no external requests.
Before implementation, **two passed / two failed**: retirement after TorBox create
or details still issued the next request. Afterward **all four pass**, covering
retirement after create/details/link, full active request order, cached-only magnet
payload presence, binding metadata/save counts and loader removal. This directly
verifies the production pipeline, not only an isolated cancellation helper.
The tests preserve the already-issued request and stop later pipeline steps.

Affected baseline: **346 passes / four failures**; final: **350 passes / the same
four failures** in existing manual-source validation contracts. Analyzer retains
**863 diagnostics**, with no new identities. Size/import checks pass for all
**112 migrated files**; changed methods/test files are formatted and diff checks
pass. Receipts under `.git/refactor-evidence/phase4c/`: `acquisition-before.txt`,
`acquisition-red.txt`, `acquisition-green.txt`, `acquisition-focused.txt`,
`acquisition-failure-comparison.txt`, `analyze-acquisition.txt`,
`acquisition-analyzer-comparison.txt`. The remaining provider/native, Sources and
later migration/performance/CI gates stay open.

Full-suite review: **7,901 successes / the same 51 failures / 20 skips**. Every
previous checkpoint test retains its outcome, and all four new bridge cases pass.
The original-baseline comparison also finds no new failures, missing tests or new
skips. Receipts: `.git/refactor-evidence/phase4c/full-acquisition.jsonl`,
`full-acquisition-comparison.txt` and `acquisition-previous-checkpoint.txt` in the
same directory. The historical baseline helper remains nonzero for the existing
failures; its allowance was not changed. This completes this bounded continuation
check, not phase 4C or the remaining native and migration gates.


### Phase 4C — PikPak preparation data boundary

Moved PikPak add/task polling, file-readiness polling and recursive video listing
from the legacy playback service to `pikpak_source_preparation.dart` (172 lines).
The plain operation receives API functions, an optional wait function and the live
action check. It has no Flutter, Riverpod or authentication-service dependency.
The production `_addPikPak` caller supplies the existing API instance; automatic
callers omit cancellation as before. `PikPakPreparedSource` and `PikPakSourceVideo`
(24 lines) publish final scalar fields and an unmodifiable video list; raw provider
maps remain in the decoding boundary. The shared playlist builder consumes these
descriptors and preserves single/multiple-file names, sizes, IDs and series order.
Its provider-native bound caller now decodes its existing records at that boundary.
The obsolete polling and recursive methods were removed, reducing the playback
service from **8,953 to 8,868 lines** under its existing temporary exception.

Preserved seven task attempts, five file-detail attempts, two-second waits, the
90-percent task shortcut, fallback after task-read errors, detail retries, hard
failure propagation, depth-five cutoff, partial recursive results, video MIME
filtering and case-insensitive path ordering. No pagination policy changed: the
existing folder-list API invocation remains the same. Failed/still-processing
results map to the original private exceptions and messages. The injected wait
exists for deterministic timing checks, not a new runtime scheduler.

Manual retirement is checked before/after waits and requests, after recursive
returns, on swallowed-reader-error paths and at playlist preparation/return.
Cancellation is explicitly rethrown through the existing tolerant listing/polling
paths. Already-issued API requests and shared authentication/token-refresh retries
are not cancelled or rolled back; the caller stops subsequent preparation steps.
The native route/loader ownership and shared service internals remain separate
open work. No device or performance parity is inferred from these tests.

Verification: **23 data tests** cover readiness, timing, bounded retries, hard and
transient failures, folder order/depth/partial results, immutable snapshots,
retirement at each operation boundary and the unguarded automatic contract.
**Nine real bridge tests** use scoped mock HTTP responses with fixture credentials
and no external requests. They cover retirement after add/task/details/folder/link,
active single-video and season-pack saves, first-episode link selection, original
request payload, loader removal and the two original failure messages. Against the
previous pipeline these yield **five passes / four failures**; after integration
all nine pass. The four failures demonstrate extra requests after retirement.

Affected baseline: **281 passes / four failures**; final: **313 passes / the same
four manual-source contract failures**. Analysis remains **863 diagnostics** with
no new identities. Size/import checks pass for **114 migrated files**. New files
and touched legacy methods are formatted, and diff checks pass. Receipts under
`.git/refactor-evidence/phase4c/`: `pikpak-before.txt`,
`pikpak-preparation-tests.txt`, `pikpak-bridge-red.txt`, `pikpak-focused.txt`,
`pikpak-failure-comparison.txt`, `analyze-pikpak.txt` and
`pikpak-analyzer-comparison.txt`. Phase 4C and all subsequent outstanding migration,
CI, native/device and performance gates remain open.

Full-suite review: **7,933 successes / the same 51 failures / 20 skips**. All
previous checkpoint outcomes are unchanged; all **32 newly added cases** pass.
The original-baseline comparison finds no new failures, missing tests or new
skips. Receipts: `.git/refactor-evidence/phase4c/full-pikpak.jsonl`,
`full-pikpak-comparison.txt` and `pikpak-previous-checkpoint.txt` in that directory.
The historical helper still returns nonzero for unchanged existing failures, and
its allowance was not modified. This verifies this extraction's automated gates;
the migration and native/performance/CI completion audit remains open.


### Phase 4C — manual binding loader route ownership

A reproduced lifecycle defect: manual binding captured the root navigator but
later called `pop()` on whatever route was current. A new route arriving during
acquisition could be closed instead of the loader, and removing the original
loader before completion could cause the same mistake. The four production
bridge/navigation tests produce **one pass / three failures** before the fix.
The failures cover a route above the loader, an already-removed loader and removal
of the launching page. Navigator disposal was already harmless in that fixture.

The shared `DebridLoadingOverlay.show` and provider helpers now return a small
`DebridLoadingHandle` owning the exact navigator/route. Route construction uses
the same `RawDialogRoute` and defaults as the installed SDK's `showGeneralDialog`;
provider styles, content, 300ms transition, barrier and Back behavior are retained.
The handle dismisses once, pops normally when current (preserving the exit fade),
removes only its own route when covered and does nothing after prior removal or
navigator disposal. The manual binding caller holds and dismisses this handle
before checking the source view/session again. Existing callers may ignore the
return value; automatic playback dismissal paths and the separate PikPak progress
overlay are unchanged. The shared widget is **739 lines**; playback service is
**8,864 lines** under its recorded exception. No new state/DI system was introduced.

Afterward all **four bridge/navigation tests pass**, with no stale saves or new
route pops. **Four overlay tests** cover visible/suppressed route and Back behavior,
barrier/timing, normal animated/idempotent dismissal and root ownership from a
nested navigator. Active acquisition success/error tests from previous slices
remain in the affected suite. This is a separate demonstrated lifecycle correction,
not a claim that every legacy loader or local picker has been migrated.

Affected baseline: **333 passes / four failures**; final: **341 passes / the same
four existing manual-source contract failures**. Analyzer retains **863 diagnostic
identities/counts**, with no additions; two new test brace diagnostics were fixed.
The migrated-source architecture check still passes **114 files**; this existing
shared widget is covered by its scoped ownership review, not claimed as a fully
migrated feature widget. Changed methods/tests are formatted and diff checks pass.
Receipts under `.git/refactor-evidence/phase4c/`: `loader-before.txt`,
`loader-red.txt`, `loader-green.txt`, `loader-overlay-tests.txt`,
`loader-focused.txt`, `loader-failure-comparison.txt`, `analyze-loader.txt` and
`loader-analyzer-comparison.txt`. Local-picker continuation ownership, remaining
Sources presentation and later phase/native/performance/CI gates remain open.

Follow-up review also identifies the Sources view's bind-mode completion pop
(`_bindSource` in `lib/screens/search/search_sources.dart`) as a separate route
ownership boundary: it currently checks mounted/session ownership but uses the
current navigator route. This loader fix does not close that view-level review.
`lib/services/local_bound_source_service.dart` remains 1,033 lines with modal,
native picker, folder scanning and file-metadata continuations; record its bounded
exception before editing it in the subsequent picker slice.

Full-suite review: **7,941 successes / the same 51 failures / 20 skips**. Every
previous checkpoint outcome is unchanged, and all **eight new loader cases** pass.
The original-baseline comparison finds no added failures, missing tests or new
skips. Receipts: `.git/refactor-evidence/phase4c/full-loader.jsonl`,
`full-loader-comparison.txt` and `loader-previous-checkpoint.txt` in that directory.
The historical helper remains nonzero for existing failures; no allowances were
changed. Phase 4C remains in progress, with the view-level completion pop, local
picker continuations and remaining Sources responsibilities still open.


### Phase 4C — bind-mode Sources completion route

The Sources view's delayed binding completion had the analogous route defect:
a successful save/reload called `Navigator.pop()` on a newer route above the
picker. The new real-screen navigation tests reproduce this: **five pass / one
fails** on the prior implementation. The failing covered-route case keeps the
Sources picker open and closes the newer route instead.

`_bindSource` now captures the picker route and its owning navigator before the
action. After the existing successful-result, bind-mode, mounted and profile/session
checks, it pops that route normally if current or removes only that route if
covered. A missing/inactive route or disposed navigator causes no navigation.
No action state, persistence ordering, reload behavior or profile guard moved to
the view. The test host's optional `bindMode` flag defaults to false, preserving
existing tests while exercising the real production picker behavior. This keeps
route ownership in presentation without adding a routing abstraction or DI layer.
The retained Sources part is **1,826 lines**, including this test-host extension;
its remaining UI/focus responsibilities still require extraction.

Six real-screen tests cover normal picker completion, a newer route above it,
already-removed picker, profile-session retirement, rejected save and ordinary
non-binding Sources mode. They also assert save/reload counts and unchanged
incoming-route identity. A controlled bridge and repository exercise the actual
Riverpod action gate and screen completion path; no API/native picker is replaced
in production. All **six pass** after the fix. Affected baseline **301 passes**;
afterward **307 passes**, with no failures. Analyzer retains **863 diagnostics**
with no new identities; migrated architecture checks pass **114 files**. New tests
and the changed method are formatted; diff checks pass.

Receipts under `.git/refactor-evidence/phase4c/`: `bind-route-before.txt`,
`bind-route-red.txt`, `bind-route-focused.txt`, `analyze-bind-route.txt` and
`bind-route-analyzer-comparison.txt`. This closes the reproduced view completion
route defect, not the local-picker continuation or complete Sources migration.
Native/device, performance and later CI/architecture gates remain outstanding.

Full-suite review: **7,947 successes / the same 51 failures / 20 skips**. Every
previous checkpoint outcome is preserved, and all **six new navigation cases**
pass. The original-baseline comparison finds no new failures, missing tests or
new skips. Receipts: `.git/refactor-evidence/phase4c/full-bind-route.jsonl`,
`full-bind-route-comparison.txt` and `bind-route-previous-checkpoint.txt` in the
same directory. The helper remains nonzero for unchanged historical failures;
its allowances were not changed. Phase 4C and subsequent migration/native gates
remain active.


### Phase 4C — local file inventory and matching data boundary

Extracted filesystem inventory/source metadata into `local_source_files.dart`
(**139 lines**), pure movie/folder matching and path rules into
`local_source_file_rules.dart` (**107 lines**), and final file/folder/episode
metadata descriptors into `local_source_file.dart` (**47 lines**). These files
contain no UI, navigation, Riverpod or mutable application state. The existing
picker supplies paths and consumes the results directly; its native/modal flow
and Android service are unchanged. No new interface, scheduler or DI container
was needed for stateless filesystem operations. The legacy picker now imports
the shared source model directly instead of its persistence service.

The old implementations and model declarations were removed, reducing
`lib/services/local_bound_source_service.dart` from **1,033 to 750 lines**. The
public `scanSeriesFolder` facade delegates to the new operation and returns a
caller-owned list as before; `LocalSeriesEpisodeFile` remains available through
a compatibility export. New feature inventories are unmodifiable snapshots.
Movie/folder chooser candidates retain their original object identity and order;
matching still sorts copies instead of mutating input lists.

Review retained recursive video scans without following links, descending size
order, sample filtering, largest-duplicate episode selection, season/episode order,
direct-child series-folder matching, score/name ordering and filename/year rules.
The movie substring rule and path normalization quirks were intentionally preserved.
Source hashes, URIs, local kinds, size/modification metadata and bound timestamps
are unchanged. Stream/stat error branches still retain their prior behavior,
including partial unsorted results on interrupted enumeration; no retry or scan
limits were added. Native permission/error scenarios still need device validation.

Before extraction, **three filesystem behavior tests passed** through the original
public episode API. They verify nested ordering/duplicates, relative names/metadata,
empty/missing folders, mutable legacy results and exclusion of file/directory
symlinks. They still pass after extraction. **Fourteen matching/path tests** and
**five data-operation tests** cover matching scores, year preference, input identity,
path separators, immutable inventories, direct-child ordering and saved metadata.
**Two real picker tests** substitute only the native directory-selection plugin,
use real temporary files and verify movie year selection and series-child-folder
resolution. They pass both against the original service restored temporarily for
comparison and against the extracted implementation. The Windows symlink fixture
is explicitly skipped where creating links requires host privileges; all current
host cases ran.

Affected baseline: **315 passes**; final: **339 passes**, with no failures.
Analyzer retains **863 diagnostics**, with no added identities. Architecture checks
pass **117 migrated files**; new files and changed legacy methods are formatted,
and diff checks pass. Receipts under `.git/refactor-evidence/phase4c/`:
`local-files-before.txt`, `local-inventory-baseline.txt`, `local-files-data-tests.txt`,
`local-files-picker-baseline.txt`, `local-files-picker-tests.txt`,
`local-files-focused.txt`, `analyze-local-files.txt` and
`local-files-analyzer-comparison.txt`. The remaining local picker continuation
checks, presentation separation and later Sources/native/performance/CI gates
remain open; a smaller service alone is not completion.

Extraction review also compared all **11 moved function bodies** against the
unchanged service, normalizing only symbol names, formatting and the documented
immutable result wrapping. All match. Receipt:
`.git/refactor-evidence/phase4c/local-files-extraction-review.txt`. This confirms
that the existing matching formulas and partial/error branches moved intact;
it supplements the behavior tests rather than replacing them.

Full-suite review: **7,971 successes / the same 51 failures / 20 skips**. All
previous checkpoint outcomes are unchanged and all **24 new cases** pass. The
original-baseline comparison reports no new failures, missing tests or new skips.
Receipts: `.git/refactor-evidence/phase4c/full-local-files.jsonl`,
`full-local-files-comparison.txt` and `local-files-previous-checkpoint.txt` in that
directory. The historical helper's nonzero result is unchanged; no failure
allowances were modified. Phase 4C remains open for local-picker continuation/UI
ownership and the remaining Sources work, followed by the original later phases.


### Phase 4C — local picker presentation components

Moved the local movie mode sheet to `local_movie_pick_mode_sheet.dart` (**108
lines**), file/series-folder candidate dialogs and their size label to
`local_source_choice_dialogs.dart` (**179 lines**), and series-folder guidance to
`local_series_folder_help.dart` (**96 lines**). They accept typed display inputs,
render the original widgets and return the original selection/cancellation values.
They import no services, storage, native APIs or Riverpod. The movie sheet receives
its Android wording flag from the existing platform decision in the caller.
No application state or new abstraction was introduced for these modal functions.

The actual picker calls these functions; its replaced builders, private widgets,
mode enum and size formatter were removed. The legacy coordinator shrank from
**750 to 371 lines**. Its remaining responsibilities include native/Android picking,
Android-specific dialogs, filesystem action orchestration and snackbars; its live
action continuation review remains open. This is not a claim that all picker UI
or native behavior is migrated merely because the file is now smaller.

Preserved original context forwarding, modal options, focus/autofocus, shapes,
colors, padding, labels, movie file/folder outcomes, 40-folder and 80-file display
limits, ordering and selected candidate identity. Existing unlocalized copy and
fixed legacy styling remain under the unchanged-UI migration exception. Both
candidate lists still copy the limited input for presentation without mutating the
source inventory. Cancellation and Back retain their prior results.

**Nine component tests pass**, covering directional movie selection and Android/
desktop wording, file/Back results, candidate limits and identity, size labels,
empty-list cancellation and guidance examples/dismissal. **Three new real picker
integration cases** exercise unmatched movie choice, multiple series-folder choice
and no-match guidance using temporary files with only the native directory plugin
substituted. Together with the two earlier picker tests, all **five pass** against
both the unchanged service restored temporarily for comparison and the extracted
implementation. Existing narrow/landscape large-text picker checks also pass.
Review compared all **seven moved UI/helper bodies** with the original after
formatting, renamed symbols and the explicit platform argument: all match.

Affected baseline **339 passes**; final **351 passes**, no failures. Analyzer
retains **863 diagnostics**, with no new identities. Size/import checks pass
**120 migrated files**; new files/changed legacy methods are formatted and diff
checks pass. Receipts under `.git/refactor-evidence/phase4c/`:
`local-dialogs-before.txt`, `local-dialogs-tests.txt`,
`local-dialogs-integration-baseline.txt`, `local-dialogs-integration.txt`,
`local-dialogs-focused.txt`, `local-dialogs-extraction-review.txt`,
`analyze-local-dialogs.txt` and `local-dialogs-analyzer-comparison.txt`.
Native/device and later migration/performance/CI gates remain open.

Full-suite review: **7,983 successes / the same 51 failures / 20 skips**. Every
previous checkpoint outcome is unchanged; all **12 new cases** pass. The original
baseline comparison finds no new failures, missing tests or new skips. Receipts:
`.git/refactor-evidence/phase4c/full-local-dialogs.jsonl`,
`full-local-dialogs-comparison.txt` and `local-dialogs-previous-checkpoint.txt` in
the same directory. The historical helper remains nonzero for the unchanged
existing failures; its allowances were not modified. Phase 4C remains in progress
for picker continuation/native ownership and the remaining Sources work.

### Phase 4C — local binding action retirement

The existing manual binding action check now passes through local movie/series
selection, native picker returns, directory scans, file metadata reads and
follow-up dialog returns. Retired actions return without another dialog, scan,
source publication or save. Android's existing caught-error snackbars also check
ownership; its progress route retains the existing exact-route cleanup in
`finally`. Already-issued native calls and filesystem reads are allowed to settle.

This is an intentional lifecycle correction, separate from the preceding
presentation extraction. Callers omitting the optional callback retain their
previous behavior, API arguments, ordering and error handling. No DI framework,
retry, new state owner or persisted format was added. The file operations remain
plain data functions; the compatibility coordinator remains temporarily in the
legacy service at **445 lines**, with Android UI/native orchestration still to
migrate. The data file is **166 lines**.

Six bridge tests exercise actual local binding with a substituted native directory
picker and real temporary files. They cover retirement during the mode sheet,
movie/series directory selection and profile reset, plus current movie/series
saves. Against the previous implementation, the two active cases pass and all
four retirement cases fail; with the continuation checks, all six pass. The
directory cases explicitly wait for the native picker to start before retiring,
so modal closing animation cannot turn them into entry-guard tests.

Thirteen data tests cover current, already-retired and pending scan results for
video inventories, episode inventories and matching folders. Controlled file
existence/stat futures verify that retirement prevents the next metadata read or
source publication while an active action preserves the source. These supplement
existing ordering, immutable output and metadata tests.

The Sources test directory passes **362 tests**. Analyzer retains **863
diagnostics**, with no new identities against the original baseline. The scoped
architecture check passes **120 migrated files**; formatting and diff checks pass.
Receipts under `.git/refactor-evidence/phase4c/`:
`local-retirement-reviewed-red.txt`, `local-current-green.txt`,
`local-retirement-affected.txt`, `analyze-local-retirement.txt` and
`local-retirement-analyzer-comparison.txt`.

Review traced each introduced asynchronous continuation and preserved the
unguarded branches. Desktop bridge tests do not execute Dart's Android platform
branch; Android native/UI behavior still needs device verification. Existing
desktop layout and Android service tests remain part of the full-suite gate.
The broader Sources presentation, native ownership, and all later phases remain
open.

Full-suite investigation: the first run had **8,001 successes / 52 failures /
20 skips**, including a new observation of
`self_profile_settings_page_test.dart::identity save persists without changing access`
reading the old name after its fixed-duration wait. The unchanged profile test
file then passed all **five cases** independently. Review found the edited
local-binding methods are outside this profile identity-save path and introduce
no shared initialization/storage change. Timing sensitivity is a plausible
explanation, not an established root cause; the first receipt is retained.

The unchanged repeat full run finished with **8,002 successes / the original
51 failures / 20 skips**. Every prior checkpoint outcome is preserved, including
the profile save test; all **19 new tests** pass. Both original-baseline and
previous-checkpoint identity comparisons pass, with no missing tests or new skips.
No test, timeout or failure allowance was changed to obtain this result.
Receipts: `full-local-retirement.jsonl`,
`local-retirement-profile-investigation.txt`,
`full-local-retirement-verified.jsonl`,
`full-local-retirement-verified-comparison.txt` and
`local-retirement-verified-previous-checkpoint.txt` in the same evidence directory.
The historical helper still exits nonzero for the original failures. Phase 4C
and the full migration remain in progress.

### Phase 4C — source copy-link operation

Moved copy eligibility, deferred IPTV episode resolution and clipboard sequencing
into the stateless `data/source_link_copier.dart` (**65 lines**). It takes ordinary
function dependencies, publishes a typed outcome and retains no links, requests
or profile state. The **14-line** Riverpod composition file supplies the existing
IPTV predicate/resolver and the **5-line** shared system clipboard adapter. This
needs no notifier, repository hierarchy or additional state owner. The platform
adapter is included in the measured migration source set.

The production Sources screen now dispatches the operation and renders the
original progress/outcome messages. Its replaced episode-target predicate,
resolution and native clipboard body were removed; the Sources part is now
**1,812 lines**, still an explicit interim exception with other responsibilities
remaining. Row/menu visibility, target validation (including its case-insensitive
episode identifier), link selection through `Torrent.copyLink`, missing versus
unavailable outcomes and the platform method payload are preserved. No automatic
retry, deduplication or new exception swallowing was added. Existing unlocalized
messages retain their scoped legacy-copy exception.

Separately from the structural move, copy actions now use the originating Sources
profile/session as well as view lifetime. A retired entry does no work; retirement
during deferred resolution prevents the clipboard call, and retirement during an
already-issued clipboard write suppresses success feedback. The native write
itself cannot be rolled back. The legacy IPTV resolver's internal authorization
and network behavior were not changed; its transitive boundary still requires
the phase-8 audit.

Baseline: **365 Sources tests pass**, including three new real-screen cases for
direct/magnet copying and a linkless menu action. Those use the actual clipboard
method channel adapter, substituted only at the platform channel. A fourth
real-screen case captures a row callback, clears the profile session and invokes
it: the original screen fails by writing its old link; the three active cases
still pass. The guarded implementation passes all four.

**Fifteen operation tests** cover eligibility, direct/magnet links, missing target
and link, the three resolution statuses, ordered/awaited clipboard writing,
retirement before and during work, and unchanged resolution/clipboard exception
propagation without retries. **Five injected real-screen tests** cover deferred
success, profile retirement, route/view disposal, missing episode and unavailable
episode, checking clipboard writes and existing visible messages. The provider is
only immutable app-scoped wiring; all action ownership is supplied per invocation.

All **386 Sources tests pass**. Analyzer retains **863 diagnostics**, with no new
identities. Architecture checks pass **123 migrated files**; new files and touched
legacy methods are formatted, with no whole-file legacy formatting. Diff checks
pass. Receipts under `.git/refactor-evidence/phase4c/`:
`copy-link-before.txt`, `copy-link-retirement-red.txt`,
`copy-link-focused.txt`, `copy-link-ownership.txt`,
`copy-link-affected.txt`, `analyze-copy-link.txt` and
`copy-link-analyzer-comparison.txt`.
Native/device checks and the remaining Sources/later migration phases remain open.

Full-suite review: **8,026 successes / the same 51 failures / 20 skips**.
Every preceding checkpoint outcome is preserved, and all **24 new tests** pass.
Original-baseline and prior-checkpoint identity comparisons find no new failures,
missing tests or new skips. The final analyzer run (including the last added
retirement test) retains **863 diagnostics** and no new identities. Receipts:
`full-copy-link.jsonl`, `full-copy-link-comparison.txt`,
`copy-link-previous-checkpoint.txt`, `analyze-copy-link-final.txt` and
`copy-link-final-analyzer-comparison.txt` in the same evidence directory.
The baseline helper's nonzero exit remains due to the original failures; its
allowances are unchanged. Phase 4C remains open for the remaining presentation,
focus and legacy action boundaries, with the original later phases still required.

### Phase 4C — playback and download presentation bridge

Sources row activation and direct-stream downloads now call the injected
`presentation/source_playback_bridge.dart` (**39 lines**). It is an immutable,
stateless adapter for the existing context-dependent legacy APIs, with no
persistence, native resource ownership or parallel application state. Its precise
legacy import is registered alongside the binding bridge; no general service
imports were allowed for presentation files.

The screen retains interaction ownership: freeze before activation, suppress
dialog-generated duplicate taps, compute stream/download policy eligibility and
reload saved bindings after playback completion only while mounted. The bridge
forwards the same context, selected torrent, force-play flag, metadata, rendered
source list, selected index and search title, without copying/reordering the list
or introducing an asynchronous boundary. The download menu captures its bridge
when opened, so download capability checks and dispatch do not need a live Ref
during later modal rebuilds. Other modal callbacks, including torrent copy
eligibility, still need the separate view-retirement review.

Review compared both `_playNow` and `_showRowMenu` with the preceding checkpoint:
after substituting bridge calls/captured dependency and normalizing formatting,
their bodies match. Native activation, download resolution and their existing
error/lifecycle behavior are untouched; this is not native parity evidence or
completion of their phase-7 review. The Sources part remains an interim exception
at **1,816 lines**; the test-only entry point gained an optional force-play flag
so tests can exercise the production widget's existing intent parameter.

**Seven real-screen wiring tests pass**: ordinary row activation, explicit
force-play, menu activation, provider-filtered list/index handoff, completion after
view disposal, eligible download dispatch and unsupported download visibility.
They verify selected torrent/metadata identity, visible playlist order, exact
index and query title, duplicate-tap suppression, and saved-binding reload only
after successful completion. The filtered fixture uses the narrow provider strip
and its actual `engine:beta` key; the other cases use the wide cinema layout.
Tests substitute only the presentation bridge and existing repository boundaries;
actual player startup, transfers and native teardown remain separate device gates.

Affected baseline **386 passes**; after integration **393 passes**, no failures.
After the modal dependency-capture review, the focused **seven cases** pass again.
Final analyzer retains **863 diagnostics**, with no new identities. Architecture
checks pass **124 migrated files**; touched legacy methods/new files are formatted
and diff checks pass. Receipts under `.git/refactor-evidence/phase4c/`:
`playback-bridge-before.txt`, `playback-bridge-affected.txt`,
`playback-bridge-final-focused.txt`, `playback-bridge-extraction-review.txt`,
`analyze-playback-bridge-final.txt` and
`playback-bridge-final-analyzer-comparison.txt`.
Remaining Sources presentation/focus work and all later phases remain open.

The first full run reported **8,032 successes / 52 failures / 20 skips**.
All seven new wiring tests passed, but the previously documented
`remote_reliable_transfer_test.dart::large binary file arrives intact with bounded progress blocks`
cleanup race recurred: its content/progress checks passed and its immediate
directory assertion still saw the temporary `.part` file. Reinspection confirms
the unchanged receiver publishes receipt phase `complete` before awaiting
journal IO and temporary-file deletion. The Sources bridge changes neither this
service nor the transfer test. All **18 transfer tests** pass in isolation.
The first run and comparison remain recorded in `full-playback-bridge.jsonl`,
`full-playback-bridge-comparison.txt`, and
`playback-bridge-transfer-investigation.txt`; no failure allowance was changed.

The unchanged repeat full run has **8,033 successes / the original 51 failures /
20 skips**. The transfer cleanup test passes; all preceding checkpoint outcomes
are preserved and all **seven new tests** pass. Both original-baseline and prior
checkpoint comparisons report no new failures, missing tests or new skips.
Receipts: `full-playback-bridge-verified.jsonl`,
`full-playback-bridge-verified-comparison.txt` and
`playback-bridge-verified-previous-checkpoint.txt` in the same directory.
The historical helper still exits nonzero for the original failures. Phase 4C,
the modal ownership/focus review, and the later native/performance/CI gates remain
open.

### Phase 4C — modal action ownership and filter input capture

The modal review reproduced nine failures against the previous checkpoint:
Play/Download could dispatch after a profile reset, Play/Copy/Download could read
an unmounted view, stale row/filter callbacks could open UI after disposal, and
row/filter builders could read a disposed Ref or closed provider subscription.
These are intentional lifecycle fixes, not claimed behavior-neutral movement.

The Sources view now checks one existing view/session ownership predicate before
reading Ref/context or dispatching its explicit actions. Pin/unpin and local
binding entry points use the same check while retaining their repository-level
guards. The row sheet captures its stateless copy dependency when opened, so
eligibility can still be evaluated on rebuild without reading the old view.
Its active commands, labels, eligibility rules, theme capture and dismissal
behavior remain unchanged; retired callbacks dismiss the sheet without dispatch.

Moved the filter modal wrapper into
`presentation/source_filters_dialog.dart` (**22 lines**), accepting its immutable
opening filter state and series/movie display flag. Rebuilds no longer read the
opening view's subscription. The caller rejects stale completion before reading
or updating current filter state. The existing `TorrentFiltersSheet`, transparent
Dialog, copy and modal defaults are retained; the replaced builder was removed.
The legacy Sources part remains **1,820 lines** with other presentation/focus
responsibilities still pending. No generic event system, new state owner or
additional DI framework was introduced.

**Nineteen real-screen cases pass**. Twelve exercise Play/Copy/Pin/Download with
active, disposed and retired-profile owners; two rebuild row/filter modals after
removing their originating route; three cover applying, cancelling and ignoring a
retired filter result; two invoke captured open callbacks after disposal. Tests
use real Navigator routes and a theme change to rebuild modals, with side effects
recorded at the existing injected boundaries. The original implementation passes
ten and fails nine of these exact final cases. ClearAll in the profile fixture
retires action ownership without pretending to replace the Navigator/profile
route or clear the currently rendered widgets.

The initial 500-pixel-wide fixture also exposed an existing filter-header overflow
under the widget-test font. The ownership fixture uses 560 pixels to isolate its
lifecycle assertions; the layout observation is retained as an explicit pending
layout verification item. No layout test was weakened or converted into an
allowlisted failure. Active filter chips are tapped and their selected state is
asserted before applying/cancelling.

Affected existing baseline: **22 passes** across playback/copy/binding navigation.
After the fix, **all 412 Sources tests pass**. Analyzer retains **863 diagnostics**
with no new identities. Architecture checks pass **125 migrated files**; changed
legacy methods/new files are formatted and diff checks pass. Receipts under
`.git/refactor-evidence/phase4c/`: `modal-owner-before.txt`,
`modal-owner-red.txt` (initial narrow fixture), `modal-owner-reviewed-red.txt`,
`modal-owner-final-red.txt`, `modal-owner-affected.txt`,
`analyze-modal-owner.txt` and `modal-owner-analyzer-comparison.txt`.

This does not cancel native playback/download work that started while its owner
was current; that deeper lifecycle audit remains phase 7. Sources focus and
presentation work, native/device checks, the new layout follow-up and all later
migration gates remain open.

Full-suite review: **8,052 successes / the same 51 failures / 20 skips**.
Every preceding checkpoint outcome is preserved, and all **19 new cases** pass.
Original-baseline and previous-checkpoint comparisons find no new failures,
missing tests or new skips. Receipts: `full-modal-owner.jsonl`,
`full-modal-owner-comparison.txt` and `modal-owner-previous-checkpoint.txt` in
the same evidence directory. The historical helper's nonzero result remains due
to the original failures; no allowances were changed. Phase 4C remains in progress.

### Phase 4C — shared filter header and narrow layout

Extracted the filter editor's header to `lib/ui/core/filter_sheet_header.dart`
(**77 lines**), used by the existing shared editor reached from Sources and
Keyword search. The editor still owns both FocusNodes, selection sets, Clear
mutation and dialog result/navigation. The header borrows the nodes and callbacks;
its Clear predicate is read at build and interaction time, preserving the former
live eligibility check. No Riverpod state or service/data access was added.

The intentional layout correction gives the title the remaining row width,
bounded to two lines with ellipsis. Its original text, font and weight remain.
Clear/Close retain their original order, widgets, focus nodes, Select/Space
handling, callback eligibility, colors and semantics. Review compared both
control subtrees against the previous implementation after input substitutions;
both match. The extracted legacy header body was removed.

The shared editor shrank from **746 to 700 physical lines** (a formatted temporary
copy is **673 lines**, also below the ceiling). Its remaining responsibility is
one local facet-selection editor: constructing/disposal of chip focus nodes,
local selection updates and Clear/Apply, keyboard scrolling, facet rendering and
static option labels. It contains no network, persistence or feature application
orchestration. This is the required 501–800-line cohesion review, not an exception
to the final ceiling. The untouched legacy portions were not mass-formatted.
Both editor and header are registered in the measured source set, and registered
`lib/widgets/` files now receive the same presentation import checks as shared UI.

**Eight real-dialog tests pass**. Six cover 390/500-pixel portrait widths,
landscape and TV-sized windows, with normal, 1.6x and 2x text as specified by the
cases. They assert no layout exception, visible control bounds and successful
Clear/Apply. Two cover Select and Space activation of Clear, disabled Clear and
Close/cancel. Against the unchanged editor, four narrow/scaled cases fail with
header overflow while the other four pass; all eight pass after the change.

The earlier modal ownership fixture is restored from 560 to its original **500
pixels**. All **19 cases pass** at that width, closing the specific host-layout
finding without bypassing it. Combined affected Sources/Search tests: **630
passes**. Analyzer retains **863 diagnostics**, no new identities. Architecture
checks pass **127 measured files**; new code/delegation formatting and diff checks
pass. Native/device/font verification remains part of the later platform gates;
these are host widget layout results.

Receipts under `.git/refactor-evidence/phase4c/`: `filter-header-red.txt`,
`filter-header-green.txt`, `filter-header-affected.txt`,
`filter-header-original-width.txt`, `filter-header-extraction-review.txt`,
`analyze-filter-header.txt` and `filter-header-analyzer-comparison.txt`.
Sources focus/presentation and all later migration work remain open.

Full-suite review: **8,060 successes / the same 51 failures / 20 skips**.
Every previous checkpoint outcome is preserved and all **eight new cases** pass.
Original-baseline and preceding-checkpoint comparisons find no new failures,
missing tests or new skips. Receipts: `full-filter-header.jsonl`,
`full-filter-header-comparison.txt` and `filter-header-previous-checkpoint.txt`
in the same evidence directory. The baseline helper still exits nonzero for the
original failures; its allowances were not changed. Phase 4C and the full
migration remain in progress.

### Phase 4C — row focus-node ownership

Moved row FocusNode construction, resize, toolbar replacement, search reset and
disposal into `presentation/source_row_focus_nodes.dart` (**69 lines**), owned by
one Sources view. Rows borrow nodes through a read-only live list. No application
state, filtering, selected-source matching, scroll controller or toolbar/pill
focus ownership moved into this helper. The production view calls it in each
former allocation/retirement path, and the replaced node-mutation bodies were
removed. The Sources part shrank from **1,820 to 1,790 lines**.

Search reset still disposes its previous nodes immediately when entering loading.
Streaming retains surviving node identities and `src_N` labels. Toolbar changes
create replacement nodes without moving focus to the list; retired nodes are
disposed after the rebuild frame, while ordinary view teardown disposes current
nodes. Pending retirement callbacks retain only their own retired nodes and finish
cleanup even when the view is removed. Disposal prevents subsequent helper calls
from resurrecting resources. The view still owns all row identity restoration,
selected-source reveal, freeze and remote-anchor decisions.

The initial moved resize algorithm matched the original `_syncStreamNodes`
after inlining helper calls and replacing the count expression. A real Focus
widget host exposed a pre-existing flaw at this resource boundary: when several
focused-tail rows were removed, an intermediate focus request could target a node
removed later in the same loop. Six lifecycle cases passed and this multi-row
case failed. The deliberate correction records whether a removed node held focus
and requests the final surviving node once, retaining reverse retirement order
and post-frame disposal. The higher-level view policies remain unchanged; this
is not a claim that a new native-device symptom was reproduced.

**Seven lifecycle tests pass**, covering growth without stealing toolbar focus,
retained identities/live read-only access, single/multiple/all-row shrink,
post-frame retirement while widgets are still mounted, toolbar replacement,
immediate search reset and disposal with queued cleanup. They verify disposal on
the real FocusNodes and exercise actual Focus widget rebuild/detach behavior.
Existing production-screen streaming/selected-source/cinema/held-key tests also
pass, covering the integrated callers rather than only the new helper.

Affected baseline **435 passes**; after integration **442 passes**, no failures.
Analyzer retains **863 diagnostics**, with no new identities. Architecture checks
pass **128 migrated files**. New code is formatted and diff checks pass; no
whole-file legacy formatting was performed. Receipts under
`.git/refactor-evidence/phase4c/`: `row-focus-before.txt`,
`row-focus-initial.txt`, `row-focus-initial-implementation.dart`,
`row-focus-extraction-review.txt`, `row-focus-affected.txt`,
`analyze-row-focus.txt` and `row-focus-analyzer-comparison.txt`.

Remaining Sources presentation/focus decisions and all later migration phases,
native/device checks, performance comparisons and CI completion gates remain open.

Full-suite review: **8,067 successes / the same 51 failures / 20 skips**.
Every previous checkpoint outcome is preserved and all **seven new lifecycle
cases** pass. Original-baseline and preceding-checkpoint comparisons find no new
failures, missing tests or new skips. Receipts: `full-row-focus.jsonl`,
`full-row-focus-comparison.txt` and `full-row-focus-previous-checkpoint.txt` in
the same evidence directory. The baseline helper still exits nonzero for the
original failures; its allowances were not changed. Final diff/architecture
review passes. Phase 4C and the full migration remain in progress.

### Phase 4C — detail/picker result-row composition

Extracted the detail/picker row display mapping into
`presentation/source_result_row.dart` (**66 lines**). It takes the row, immutable
appearance settings, layout/selection flags, cache label, borrowed FocusNode and
explicit action/navigation callbacks. It returns the existing `SourceRow`
directly, preserving widget-tree depth, row state and existing interaction owners.
Format versus compact rows, title/add-on metadata, quality/coverage/cache/stream
badges, current-source state, cached-episode notice and TV play affordance retain
their original expressions. Unchanged legacy copy remains under the plan's scoped
localization exception.

The real Sources caller uses the function; its old display mapping and now-unused
appearance getters were removed. Action eligibility, bind/play dispatch, copy,
long press and directional focus closures stay byte-for-byte unchanged in the
view. No controller, provider, resource owner or data access was added. The
original mutable Torrent is read synchronously, without retaining a competing
presentation snapshot. The Sources part shrank **1,790 → 1,770 lines**.

The existing affected suite passes **442 cases both before and after**. It covers
production search/stream updates, retry/cache results, selected-source focus,
copy/pin/playback wiring, modal ownership, held keys and node lifecycle. A source
comparison additionally verifies every moved display expression after explicit
argument renames and unchanged action closures; it supplements behavioral tests.
No tests or failure allowances were altered. Architecture checks pass **129
migrated files**. Shared `SourceRow` still contains legacy badge-service coupling;
its transitive boundary review remains pending with the overall migration.

Receipts under `.git/refactor-evidence/phase4c/`: `row-view-before.txt`,
`row-view-after.txt`, `row-view-original.txt`, `row-view-extraction-review.txt`
and `analyze-row-view.txt`. Sources composition/focus, later phases, native/device
and performance validation, and final CI gates remain open.

Full-suite review: **8,067 successes / the same 51 failures / 20 skips**.
Every test outcome is identical to the preceding row-focus checkpoint; original
baseline comparison also finds no new failures, missing tests or newly skipped
cases. Analyzer remains at **863 diagnostics**, with no added identities.
Receipts: `full-row-view.jsonl`, `full-row-view-comparison.txt`,
`full-row-view-previous-checkpoint.txt` and `row-view-analyzer-comparison.txt`.
The baseline helper remains nonzero for original failures; no allowances changed.
Formatting, diff and architecture checks pass. Phase 4C remains in progress.

### Phase 4C — responsive Sources frame

Extracted compact app-bar and cinema frame presentation into
`presentation/source_screen_frame.dart` (**112 lines**). The function consumes
immutable selection/art and scalar display inputs with explicit callbacks, and
returns the same LayoutBuilder/Scaffold/SafeArea/CinemaSourcesLayout tree. It
borrows the existing cinema key and does not introduce a resource/state owner.
The existing threshold policy, titles/subtitles, keyword art suppression,
poster/year fallback, back navigation and local-file affordance are preserved.
Local capability checks and cinema provider projection stay lazy inside the
selected layout branch. The original view keeps search/subscriptions, body
composition, provider selection, streaming freeze and focus restoration callbacks.
The former frame implementation is removed; Sources part **1,770 → 1,704 lines**.

Before extraction, **442 existing affected tests passed**, and two added real-screen
resize scenarios passed on the original implementation. Both normal and bind mode
resize compact → cinema → compact, retaining the row FocusNode and title, correct
play affordance and contextual cinema title/count, exactly one search request,
and a working copy action after returning. The fixture adds an observable request
counter and optional bind mode; existing modal test behavior remains unchanged.
After extraction **444 affected tests pass**. Existing cinema/held-key, playback,
binding, selected-source and modal cases exercise the integrated callbacks.

Review confirms identical frame widget expressions/tree after explicit argument
substitution and unchanged focus callback bodies apart from formatting. No new
analyzer diagnostic identities (**863 existing diagnostics**); architecture checks
pass **130 migrated files**. New/touched test code and the changed legacy build
method are formatted without mass-formatting the legacy part. No failure
allowances changed. These host resize tests do not replace native/device checks.

Receipts under `.git/refactor-evidence/phase4c/`: `layout-before.txt`,
`layout-resize-before.txt`, `layout-after.txt`, `layout-original.txt`,
`layout-extraction-review.txt`, `analyze-layout.txt` and
`layout-analyzer-comparison.txt`. Remaining Sources body/focus coordination,
later phases, native/performance validation and final CI gates remain pending.

Full-suite review: **8,069 successes / the same 51 failures / 20 skips**.
Every previous checkpoint outcome is preserved and both new resize cases pass.
Original-baseline and preceding-checkpoint comparisons find no new failures,
missing tests or new skips. Receipts: `full-layout.jsonl`,
`full-layout-comparison.txt` and `full-layout-previous-checkpoint.txt` in the same
evidence directory. The baseline helper remains nonzero for original failures;
its allowances were not changed. Final diff/format/architecture checks pass.
Phase 4C and the overall migration remain in progress.

### Phase 4C — Sources results-body composition

Extracted loading/error/results composition into
`presentation/source_results_body.dart` (**61 lines**). It returns the original
Column/Expanded hierarchy with the existing status/progress widgets and
SourceResultsPane. Keyword input remains visible above every status branch;
loading takes precedence over error. Title, toolbar and pending-result content
are lazy callbacks, constructed only in the results branch. The empty-pane
builder still reads current result availability when invoked, retaining the
no-sources versus filtered-empty distinction.

The view supplies visibility decisions, borrowed scroll controller, row builder,
drag-freeze callback and optional content; it still owns mode/season/retry rules,
search state, subscriptions, focus and row actions. Empty season searches retain
their toolbar; IPTV and retry recovery controls retain their existing visibility.
Cinema still suppresses the extra search-progress strip. No collection/state
copy, resource owner or provider was introduced. The original body composition
and obsolete parent imports were removed. Sources part **1,704 → 1,687 lines**.

The existing affected suite passes **444 cases before and after**; no tests or
allowances were changed. Row-builder/action callback comparison confirms the
classic path remains unchanged apart from formatting. Review also checked branch
precedence, optional-content construction, empty-message timing and unchanged
SourceResultsPane list/overlay/drag behavior. Analyzer remains **863 diagnostics**
with no new identities; **131 migrated files** pass architecture checks. New code
and the changed legacy method are formatted without whole-file formatting.

Receipts under `.git/refactor-evidence/phase4c/`: `body-before.txt`,
`body-after.txt`, `body-original.txt`, `body-extraction-review.txt`,
`analyze-body.txt` and `body-analyzer-comparison.txt`. Remaining Sources view/focus
coordination, later phases and native/performance/CI completion gates stay open.

Full-suite review: **8,069 successes / the same 51 failures / 20 skips**.
Every test outcome is identical to the preceding frame checkpoint; the original
baseline comparison likewise finds no added failures, missing tests or new skips.
Receipts: `full-body.jsonl`, `full-body-comparison.txt` and
`full-body-previous-checkpoint.txt` in the same evidence directory. The baseline
helper remains nonzero for original failures, with no allowance changes. Final
format, diff and architecture checks pass; Phase 4C remains in progress.

### Phase 4C — Sources toolbar composition

Extracted toolbar grouping into `presentation/source_toolbar.dart` (**58 lines**):
provider strip, warnings, supplied season/sort/filter controls and active-filter
summary. It returns the original Column hierarchy and applies the same theme
colors, warning padding/text style and visibility rules. The production view
supplies provider options, selection/retry callbacks, borrowed controls and Clear
handling; it retains every state mutation, search dispatch and focus action.
The former grouping implementation, message getter and obsolete imports were
removed. Sources part **1,687 → 1,661 lines**.

Ordered warning projection now joins the existing pure provider projection
(**191 lines**). It preserves media-server map insertion order/latest duplicate
value, server-before-IPTV order, exact selected-key filtering and retryable IPTV
qualification/text. It returns an immutable string list without data access or
state retention. The callback is evaluated only when provider messages are shown,
so cinema still skips these compact-toolbar warnings. Existing legacy service
model imports in the projection retain their recorded transitive-audit obligation.

Affected baseline **444 passes**; after extraction **445 passes**. The added case
covers mixed server/addon/IPTV status, duplicate server errors, selected server,
selected failed/ready IPTV, unknown selection and immutable output. Existing
real-screen provider/retry/filter/focus and modal tests all pass. Review confirms
unchanged SourceToolbarControls construction and provider-select/retry/Clear
callback bodies apart from formatting, plus original render order and styles.
Analyzer retains **863 diagnostics**, no new identities; architecture checks pass
**132 migrated files**. Formatting and diff checks pass, with no whole-file legacy
formatting or failure-allowance changes.

Receipts under `.git/refactor-evidence/phase4c/`: `toolbar-before.txt`,
`toolbar-after.txt`, `toolbar-original.txt`, `toolbar-extraction-review.txt`,
`analyze-toolbar.txt` and `toolbar-analyzer-comparison.txt`. Remaining Sources
view/focus work, later phases and native/performance/CI gates remain open.

Full-suite review: **8,070 successes / the same 51 failures / 20 skips**.
Every prior checkpoint outcome is preserved and the new warning-projection case
passes. Original-baseline and preceding-checkpoint comparisons find no new
failures, missing tests or new skips. Receipts: `full-toolbar.jsonl`,
`full-toolbar-comparison.txt` and `full-toolbar-previous-checkpoint.txt` in the
same evidence directory. The baseline helper remains nonzero for original
failures, with no allowance changes. Final diff/format/architecture review passes.
Phase 4C and the overall migration remain in progress.

### Phase 4C — saved-binding matching boundary

Moved `_bindingFor` iteration/branch rules into plain
`data/source_binding_matcher.dart` (**43 lines**) with injected media-server key
and IPTV ownership callbacks. `application/source_binding_match_dependencies.dart`
(**14 lines**) provides the stateless adapter through Riverpod at app scope.
Identity is resolved on each call without retaining rows, pins, profile data or
keys. The production row menu delegates to the matcher; primary-source selection
also receives its existing media-server callback through this adapter. Primary
selection policy/diagnostics remain distinct, as before. The old matching body is
removed; Sources part **1,661 → 1,636 lines**.

The matcher preserves saved order/first match, conditional per-pin media lookup,
IPTV ownership and complete catalog identity, direct add-on configuration and
binge-group/profile compatibility, and exact nonempty torrent-hash fallback.
Returned objects retain their original identities. It does not read storage or
receive Ref/BuildContext. Review compares the moved algorithm with the original
after explicit dependency substitution, formatting and braces around one return.
The legacy media-server implementation behind the adapter remains in the final
transitive audit; this step does not claim it has been migrated.

**Seven new plain tests** cover no lookups for empty pins, saved-order identity,
stream/hash eligibility, add-on group/profile fallback and configuration isolation,
IPTV catalog identity/ownership, lazy media lookup stopping at the first match,
and changing identity resolution across calls. The initial add-on test fixture
omitted its required addonId, so six new cases passed and that fixture failed;
adding the missing fixture field made all seven pass without changing behavior.
That failed receipt is retained, not classified as an app regression.

Affected baseline **445 passes**, after integration **452 passes**. Existing
real-screen binding, modal, primary-selection/focus and playback tests still pass.
Analyzer retains **863 diagnostics**, with no added identities. Architecture
checks pass **134 migrated files**; formatting/diff checks pass and no failure
allowances changed. Receipts under `.git/refactor-evidence/phase4c/`:
`binding-match-before.txt`, `binding-match-invalid-fixture.txt`,
`binding-match-after.txt`, `binding-match-original.txt`,
`binding-match-extraction-review.txt`, `analyze-binding-match.txt` and
`binding-match-analyzer-comparison.txt`. Remaining Sources focus/service boundaries
and later phases/native/performance/CI gates remain open.

Full-suite review: **8,077 successes / the same 51 failures / 20 skips**.
Every previous checkpoint outcome is preserved and all seven new matcher cases
pass. Original-baseline and preceding-checkpoint comparisons find no new failures,
missing tests or new skips. Receipts: `full-binding-match.jsonl`,
`full-binding-match-comparison.txt` and `full-binding-match-previous-checkpoint.txt`
in the same evidence directory. The baseline helper remains nonzero for original
failures, with no allowance changes. Final diff/format/architecture review passes.
Phase 4C and the overall migration remain in progress.

### Phase 4C — Sources focus coordination ownership

Moved selected-row reveal coordination, generation invalidation, cinema remembered
row and post-frame focus anchors into `presentation/source_results_focus.dart`
(**160 lines**), one lazy view-owned coordinator. It borrows the existing scroll
controller and row/filter/pill nodes. Mounted, search token, freeze, selected-row
visibility, rail focus, empty-result recovery and TV mode remain live reads. The
coordinator owns only reveal generation and remembered-row index; it creates no
nodes, timers, subscriptions or application state. The original node/controller
owners retain disposal order. Deferred work keeps the original mounted guards.

The view still matches selected identity, adopts/reconciles results, resolves a
previously focused torrent's new index, and owns search state. Generation
invalidation remains at the same batch/freeze call sites; provider changes reset
the remembered row at the same point. The existing lazy viewport walker remains
unchanged. Streaming anchors still respect freeze/selected/control/rail state;
completion retains its distinct existing guards and empty-season/retry filter
recovery. Restoring a user-focused row still uses its resolved index after a frame.
Original bodies/fields were removed; Sources part **1,636 → 1,551 lines**.

Review compares reveal continuation checks, cancellation-reason precedence,
mounted-row dispatch and focus-request diagnostics after explicit live-dependency
substitution. TV mode is deliberately a live getter, including after await.
Manual review verifies deferred scheduling, the distinct streaming/completion
conditions and original identity restoration. Application/profile behavior was
not broadened by adding a new focus-state provider.

Affected baseline **452 passes**. Eleven new widget-host tests cover query,
generation, freeze and view-retirement cancellation between frames; filter/pill/
rail focus acquired while awaiting; preservation and restoration of a selected
cinema row; live TV mode at reveal completion; selected/user focus protection;
retired queued callbacks; and empty recovery eligibility. The first test draft
needed an explicit type for its self-referencing fixture initializer. The empty
recovery fixture then exposed unscheduled test frames: addPostFrameCallback does
not itself schedule one. The production caller already schedules through setState;
the fixture was corrected to explicitly drive frames without changing production
timing. Debug receipts are retained. All **11 new tests pass**.

After integration **463 affected tests pass**, including the existing actual-screen
selected-row reveal, held keys, provider switching, streaming freeze and completion
focus cases. Analyzer retains **863 diagnostics**, no new identities; architecture
checks pass **135 migrated files**. Formatting/diff checks pass and no failure
allowances changed. Receipts under `.git/refactor-evidence/phase4c/`:
`focus-coordination-before.txt`, `focus-coordination-after.txt`,
`focus-coordination-new.txt`, `focus-coordination-original.dart`,
`focus-coordination-extraction-review.txt`, `focus-empty-debug.txt`,
`focus-empty-debug2.txt`, `analyze-focus-coordination.txt` and
`focus-coordination-analyzer-comparison.txt`. Phase 4C service/view completion,
later phases, native/device performance comparisons and CI gates remain open.

Full-suite review: **8,088 successes / the same 51 failures / 20 skips**.
Every prior checkpoint outcome is preserved and all eleven new focus cases pass.
Original-baseline and preceding-checkpoint comparisons find no new failures,
missing tests or new skips. Receipts: `full-focus-coordination.jsonl`,
`full-focus-coordination-comparison.txt` and
`full-focus-coordination-previous-checkpoint.txt` in the same evidence directory.
The baseline helper remains nonzero for original failures, with no allowance
changes. Final diff/format/architecture review passes. Phase 4C remains in progress.

### Phase 4C — picker diagnostics boundary

Moved picker event emission into the existing
`services/source_selection_diagnostics.dart` (**170 lines**, now registered in the
migration's measured source set). Its structural-source-tracing responsibility
already owns related playback/IPTV diagnostics; no duplicate logger or storage
abstraction was introduced. The writer preserves DiagnosticLabel wrapping,
`source_selection`/`picker_` event names, field order and console formatting.
An **11-line** Riverpod composition file supplies the stateless callback.

The view captures that callback in initState, before any asynchronous reveal can
start. Delayed diagnostics therefore do not resolve Ref after disposal. Field
collection remains byte-for-byte unchanged, including disposed subscription
snapshots and detail precedence; the view still owns that presentation context.
The old writer and the search library's now-unused direct DiagnosticLog import
were removed. Sources part **1,551 → 1,543 lines**. No profile/private state is
retained in the app-scoped callback, and no log schema or redaction policy changed.

Existing affected Sources/focus/diagnostics tests pass **465 cases before and
after**. Source comparison independently verifies the moved writer after
whitespace normalization and unchanged field collection. Analyzer retains **863
diagnostics**, with no new identities. Architecture checks pass **137 migrated
files**, including the reused service. Formatting/diff checks pass. This small
logging-boundary extraction uses the affected suite; the most recent full suite
remains the preceding focus-coordination checkpoint (**8,088 successes / 51
existing failures / 20 skips**), not a full-suite claim for this commit.

Receipts under `.git/refactor-evidence/phase4c/`: `picker-diagnostics-before.txt`,
`picker-diagnostics-after.txt`, `picker-diagnostics-original.txt`,
`picker-diagnostics-extraction-review.txt`, `analyze-picker-diagnostics.txt` and
`picker-diagnostics-analyzer-comparison.txt`. No test/failure allowances changed.
Remaining Sources and later-phase work, native/performance and final CI gates
remain open.

### Phase 4C — scoped batch preparation ownership

Introduced `application/source_batch_preparation.dart` (**47 lines**) as a
stateless application operation. It reads the current search state, saved-pin
snapshot and injected IPTV classifier at batch arrival, then invokes the unchanged
pure preparation policy. It rejects a retired profile or disposed provider scope
before reading dependencies. The view supplies the effective selection/bind intent,
retains query-generation checks, logs preparation outcomes and explicitly buffers
or adopts after capturing focus. No result collection, query state or retention
policy moved into a second state owner. The results-state controller is unchanged.
The old view-level input assembly/import is removed; Sources part remains **1,543 lines** after formatting; this step separates input ownership rather than reducing its size.

Scoped DI review matters here: a controller-family version reused a parent
instance in the new nested-classifier test. The final stateless preparation
provider resolves at the relevant dependency scope; that test remains and passes.
A nested saved-state test exposed missing dependency metadata that allowed its
child override to affect the parent. SavedSourcesProvider now declares its
repository/session dependencies; SourceBindingProvider declares its saved-state,
repository/session dependencies as its consumer. The latter declaration was
required by existing binding tests after saved state became explicitly scoped.
The stateless binding-matcher provider also explicitly supports scoping. No SDK,
repository, persistence, retry or provider state implementation was changed.

Five new isolated-container tests cover live search completion and cached fallback,
no implicit display/buffering, immutable rows and retained identity, current saved
snapshots, nested classifier and saved-state overrides with unchanged parent
behavior, and profile/scope retirement. Existing real-screen tests exercise the
actual scoped composition, including binding navigation, provider retry,
selected-source focus, filtering and modal retirement.

A clean committed-HEAD baseline passes **463 cases** (`preparation-owner-clean-before.txt`).
An earlier attempted baseline overlapped the edit and produced a mixed-source
compile failure; it is not used as evidence. The clean run restored the pending
implementation afterward. After final integration **468 affected tests pass**.
The missing binding dependency produced a failed affected receipt, retained as
`preparation-owner-missing-binding-dependency.txt`; it was corrected without
weakening assertions. The initial full run was deliberately stopped on that known
regression before further code edits. Its incomplete JSON is not a comparison
baseline; the final full run is `full-preparation-owner-verified`.

Receipts under `.git/refactor-evidence/phase4c/` also include
`preparation-owner-new.txt`, `preparation-owner-scope-debug.txt`,
`preparation-owner-after.txt`, `full-preparation-owner-interrupted.txt` and
`analyze-preparation-owner.txt`. Phase 4C orchestration/view completion, later
phases and native/performance/CI completion gates remain open.

Final verification: **468 affected passes**; analyzer remains **863 diagnostics**,
with no added identities; **138 migrated files** pass architecture checks.
The completed full suite has **8,093 successes / the same 51 failures / 20 skips**.
Every previous full-checkpoint outcome is preserved and all five new tests pass.
Original-baseline and preceding-checkpoint comparisons find no new failures,
missing tests or new skips. Receipts: `full-preparation-owner-verified.jsonl`,
`full-preparation-owner-comparison.txt`,
`full-preparation-owner-previous-checkpoint.txt`,
`preparation-owner-analyzer-comparison.txt` and
`preparation-owner-extraction-review.txt`. The baseline helper remains nonzero
for original failures; no allowances changed. Changed code is formatted, including
a whitespace-only formatting pass of the modified legacy method; diff checks pass.
Phase 4C and the full migration remain in progress.

### Phase 4C — completion-only application bookkeeping

Moved final season-fallback snapshotting and provider-filter reconciliation into
`application/source_search_completion.dart` (**46 lines**). The stateless operation
reads the existing results state and updates the existing seasons/results
controllers; it owns no duplicate rows/state, starts no metadata load and dispatches
no UI effects. It returns a typed keep/rebuild/retired outcome. The real view uses
that outcome for visible projection/node synchronization, then executes its
unchanged loading transition, cache sweep and focus-anchor tail.

The full set remains pending rows when present, otherwise displayed rows.
Only unscoped eligible season searches update the fallback menu; scoped results
cannot collapse it. Provider reconciliation uses that same authoritative set and
current aliases. Pending state is re-read only after a changed provider filter,
matching the original short circuit; pending rows are never adopted here. The
operation rejects retired profiles/provider scopes before reads; the view retains
its mounted and query-token guard. Results/seasons providers declare their existing
dependencies so nested overrides have the correct owner. Their state/action
implementations are unchanged. Sources part **1,543 → 1,538 lines**.

Baseline **468 affected passes**; after integration **476 passes**. Eight new
isolated-container tests cover parked/full-set reconciliation without adoption,
menu retention for season-scoped and ineligible searches, projection rebuilding
only when needed, preserved sort state, alias-resolved provider selection,
nested results overrides without parent mutation, and separate profile/scope
retirement. Existing real-screen completion/focus/season and binding cases pass.
The metadata repository fake throws if completion attempts IO, so these tests
also verify completion does not start a guide request.

Review confirms the view loading/cache/focus tail is byte-for-byte unchanged,
with final bookkeeping order and effective-selection inputs preserved. New code
and the changed legacy method are formatted without whole-file formatting.
Analyzer retains **863 diagnostics**, no new identities; **139 migrated files**
pass architecture checks. Diff checks pass; no failure allowances changed.
Receipts under `.git/refactor-evidence/phase4c/`: `completion-owner-before.txt`,
`completion-owner-new.txt`, `completion-owner-after.txt`,
`completion-owner-original.txt`, `completion-owner-extraction-review.txt`,
`analyze-completion-owner.txt` and `completion-owner-analyzer-comparison.txt`.
Phase 4C and later migration/native/performance/CI gates remain in progress.

Full-suite review: **8,101 successes / the same 51 failures / 20 skips**.
Every prior checkpoint outcome is preserved and all eight new completion cases
pass. Original-baseline and preceding-checkpoint comparisons find no new failures,
missing tests or new skips. Receipts: `full-completion-owner.jsonl`,
`full-completion-owner-comparison.txt` and
`full-completion-owner-previous-checkpoint.txt` in the same evidence directory.
The baseline helper remains nonzero for original failures; no allowances changed.
Final diff/format/architecture checks pass. Phase 4C remains in progress.

### Phase 4C — settings scope audit (unresolved)

After checkpoint `a108abbb`, the nine existing settings-controller tests pass.
A new local reproduction initializes and listens to the parent controller, then
creates a child container overriding the settings repository family. Reading the
same session's settings controller in the child returns the identical parent
controller, violating the intended independent repository/state ownership.

Declaring the controller's repository/session dependencies does not fix the test.
Also declaring `dependencies: const []` on the repository family still does not
fix it. The attempted application changes and failing checked-in test were reverted;
the complete reproduction and patch remain in local evidence. This is an open
scope limitation, not a successful fix. Existing explicit controller-override
coverage must not be generalized to automatic transitive family scoping.

Inspection of the installed Riverpod 3.4.3 source provides a likely explanation:
`ClassFamily.call` creates instances with null dependency metadata, and
`ProviderDirectory.from` retains parent pointers unless marked as transitive.
This is an inference from the implementation; the identical-controller assertion
is the direct behavioral evidence. Do not upgrade or patch Riverpod incidentally.
The next scope review must test an explicit ownership strategy with an already
initialized parent and sibling scopes before claiming feature-wide DI isolation.

Receipts under `.git/refactor-evidence/phase4c/`: `settings-scope-before.txt`
(9 passes), `settings-scope-reproduction.txt` (9 passes, new isolation case fails),
`settings-scope-after.txt` (461 Sources passes, only the new isolation case fails),
`settings-scope-fixed.txt` (the additional repository metadata still fails),
`settings-scope-reproduction.dart`, `settings-scope-attempt.patch`, and
`settings-scope-analyzer-comparison.txt` (no added analyzer identities).
Application/test sources are restored to the verified checkpoint. No full-suite
rerun is needed for this documentation-only outcome; its last full result remains
8,101 successes / 51 existing failures / 20 skips. Phase 4C and later gates remain
open.

### Phase 4C — explicit settings scope ownership

The follow-up establishes a supported settings scope contract without changing
Riverpod or adding a scope framework: override the controller along with the
repository in a nested scope. The production settings provider now declares its
existing repository/session dependencies. Its state and loading implementation
remain unchanged. A provider-adjacent comment records why repository-only
transitive scoping is insufficient on the pinned version.

Two new behavior tests exercise both whole-family and session-instance controller
overrides. They start with an initialized/listened parent, create two siblings,
verify controller identities through each container, concurrently load three
repositories, publish different settings, and dispose one child before finishing
parent/sibling loads. Both tests fail before the metadata change (a parent lookup
returns a different controller), and both pass afterward. These are explicit-scope
tests, not a claim that the earlier repository-only reproduction is fixed. That
limitation remains documented, with its original evidence preserved.

Baseline: nine settings tests pass. After integration: eleven settings tests and
all 463 tests under `test/features/sources` pass. Analyzer remains at 863 diagnostics
with no new identities; 139 migrated files pass architecture checks. The production
app retains its existing single root ProviderScope and distinct view/session keys.
No package, UI, query, timing or persistence behavior was changed. The broader
family-scope audit and remaining phase 4C/5–8/native/performance/CI work stay open.

Receipts in `.git/refactor-evidence/phase4c/`:
`settings-explicit-scope-before.txt`, `settings-explicit-scope-reproduction.txt`,
`settings-explicit-scope-after.txt`, `settings-explicit-scope-sources.txt`,
`analyze-settings-explicit-scope.txt` and
`settings-explicit-scope-analyzer-comparison.txt`.

Full-suite verification: **8,103 successes / the same 51 failures / 20 skips**.
Every outcome from the prior completed checkpoint is preserved, and both new
explicit-scope tests pass. Original-baseline comparison also reports no new
failures, missing tests or new skips. Receipts: `full-settings-explicit-scope.jsonl`,
`full-settings-explicit-scope-comparison.txt`,
`full-settings-explicit-scope-previous-checkpoint.txt` and
`settings-explicit-scope-review.txt`. The baseline helper's nonzero exit remains
attributable to existing failures; no allowances were changed. Changed code is
formatted and diff/architecture checks pass. This resolves explicit settings
scope ownership, not automatic repository-only scoping or the broader migration.

### Phase 4C — application-owned startup readiness

Moved the initial settings/saved-source readiness barrier from the view into
`application/source_startup.dart` (31 lines). The stateless Riverpod operation
loads the two existing controllers concurrently in the original dispatch order,
then returns readiness only for an active originating profile/scope. It creates
no state, search, navigation or persistence effect on provider construction.
Production `_initializeSources` awaits it and still owns `_runSearch` dispatch.
The old inline load orchestration was removed; Sources part **1,538 → 1,532 lines**.

Review retains the view's mounted and profile checks after its await: checking
only inside the operation would leave an asynchronous gap before search dispatch.
The settings and saved-source controller implementations and their error policies
are unchanged. Settings priority is still ready before the first batch, avoiding
the old interaction-path streaming freeze. `_reloadBound` remains for subsequent
pin/playback actions; only initial readiness moved. Season loading and cache
initialization retain their existing independent timing.

Baseline: **463 Sources tests pass**. After extraction: **472 pass**, including
nine new tests covering either completion order, appearance/saved-read failure
propagation, profile/scope retirement before and during startup, and explicit
nested controller/repository overrides without loading or changing parent state.
The scoped test uses the verified explicit-ownership strategy from the previous
checkpoint; it does not assume repository-only transitive family scoping.

Receipts under `.git/refactor-evidence/phase4c/`: `startup-owner-before.txt`,
`startup-owner-after.txt` (471 passes before the scoped case),
`startup-owner-verified.txt` (472 passes), `analyze-startup-owner.txt` and
`startup-owner-analyzer-comparison.txt`. Architecture checks cover **140 migrated
files**. Phase 4C and subsequent phases/native/performance/CI gates remain open.

Final verification: **8,112 full-suite successes / the same 51 failures / 20 skips**.
Every prior checkpoint outcome is preserved and all nine new startup tests pass.
Original-baseline comparison finds no new failures, missing tests or new skips.
The final analyzer retains **863 diagnostics**, with no added identities. Receipts:
`full-startup-owner.jsonl`, `full-startup-owner-comparison.txt`,
`full-startup-owner-previous-checkpoint.txt`, `analyze-startup-owner-final.txt`,
`startup-owner-final-analyzer-comparison.txt` and `startup-owner-review.txt`.
Changed files/methods are formatted; architecture and diff checks pass. No failure
allowances changed. Phase 4C remains in progress; this is startup readiness only,
not completion of the remaining view/search orchestration or later phases.

### Phase 4C — injected row-action eligibility

Extracted row-menu classification, pin/copy visibility and download permission
into the plain `data/source_row_action_policy.dart` (37 lines). Its immutable
result/kind live in `models/source_row_actions.dart` (15 lines); the existing
sheet exports the enum for caller compatibility. A 17-line application factory
injects the existing media-server/IPTV classifiers and live synchronous profile
permission. Copy/download capability functions remain captured from the existing
injected copier and presentation bridge, so the policy imports no UI/Riverpod and
performs no playback or persistence work.

The real row menu captures the policy before opening, then projects inside its
builder as before. Review preserves classifier precedence (torrent, external,
media server, IPTV, addon), short-circuit callback order, live permission reads,
external pin exclusion, and all existing action/mounted/profile guards. No
WidgetRef access was introduced into the delayed builder. The immutable torrent
stream type can be read there without changing the opening classification.
The three direct service calls were removed from the Sources view; the parent
search library's now-unused MediaServerService import was removed. Existing
IPTV/profile imports remain for other library responsibilities. Sources part
**1,532 → 1,526 lines**; no widget/action implementation was duplicated.

Baseline: **472 Sources tests pass**. After integration: **480 pass**, including
eight new plain policy tests covering all source kinds, classifier precedence,
copy eligibility, live permission changes, denied/unsupported downloads and
skipped capability calls. Existing real-screen modal/retirement and sheet tests
pass unchanged. Initial analyzer found the now-unused legacy media-server import;
it was removed before final verification. Architecture checks cover **143 migrated
files**. No dependency upgrade or failure allowance change was made.

Receipts under `.git/refactor-evidence/phase4c/`: `row-action-policy-before.txt`,
`row-action-policy-after.txt`, `row-action-policy-format.dart`,
`analyze-row-action-policy.txt` and `row-action-policy-analyzer-comparison.txt`
(the retained initial unused-import finding). Phase 4C and remaining migration,
native/performance and CI completion gates remain open.

Final verification: **8,120 successes / the same 51 failures / 20 skips**.
Every previous checkpoint outcome is preserved; all eight new policy tests pass.
Original-baseline comparison finds no new failures, missing tests or new skips.
Analyzer retains **863 diagnostics** with no added identities after removing the
unused import. Receipts: `full-row-action-policy.jsonl`,
`full-row-action-policy-comparison.txt`,
`full-row-action-policy-previous-checkpoint.txt`,
`analyze-row-action-policy-final.txt` and
`row-action-policy-final-analyzer-comparison.txt`. Changed code and the modified
legacy method are formatted; diff and architecture checks pass. The helper remains
nonzero for existing failures; no allowance changes. Phase 4C and later gates
remain in progress.

### Phase 4C — coordinated search preparation

Moved the cache/retry/results reset sequence into the existing application search
controller's explicit `prepareSearch` action. The controller is now **147 lines**;
no additional state owner, orchestration class or UI callback was added. The
actual view invokes this action, then resets loading/focus resources and dispatches
search exactly where it did before. Retired search owners reject preparation
before looking up dependent providers. Sources part **1,526 → 1,524 lines**.

Cache and search providers declare their existing/new dependencies for explicit
nested ownership. Cache/retry/results state and reset algorithms are unchanged;
search batches, request generation, callbacks and completion remain unchanged.
Review confirms no dependency cycle: retry/cache/results do not depend on the
search controller. The view still owns the query token used for focus/adoption.
The synchronous split is intentional: query-owned work resets before view focus
resources, and request dispatch follows those view changes.

Baseline: **480 Sources tests pass**. After integration: **484 pass**. Four new
cases use real state owners and controlled repositories to verify ordered
cache/retry/results publication, cleared displayed/pending/frozen state while
retaining toolbar selection and cache configuration, retirement of outstanding
cache/retry work, preservation of a newer same-key retry, rechecking previously
cached hashes, profile/disposal rejection before dependency access, and explicit
child preparation without changing parent results. Existing production-screen
streaming/focus/retry behavior tests pass.

Analyzer retains **863 diagnostics** with no added identities. All **143 migrated
files** pass architecture checks. Receipts under `.git/refactor-evidence/phase4c/`:
`search-reset-owner-before.txt`, `search-reset-owner-after.txt`,
`analyze-search-reset-owner.txt` and
`search-reset-owner-analyzer-comparison.txt`. Phase 4C and the broader migration,
native/performance and CI completion gates remain open.

Full-suite review: **8,124 successes / the same 51 failures / 20 skips**.
Every previous checkpoint outcome is preserved and all four preparation tests
pass. Original-baseline comparison finds no new failures, missing tests or new
skips. Receipts: `full-search-reset-owner.jsonl`,
`full-search-reset-owner-comparison.txt`,
`full-search-reset-owner-previous-checkpoint.txt` and
`search-reset-owner-review.txt`. The baseline helper remains nonzero for existing
failures; no allowances changed. Changed code/method formatting, architecture and
diff checks pass. Phase 4C and the remaining migration gates are still open.

### Phase 4C — application-owned addon retry orchestration

The existing search controller now owns synchronous `SourceRetryMode` selection
and the accepted-addon retry workflow. Media-server chips restart the full search
only while idle; retired/searching owners produce an ignored mode. Ordinary
addon retries use the existing retry controller and are merged by the existing
search batch owner only after repository/profile/generation and caller checks.
The controller remains **183 lines** with no new state or presentation import.

The real view handles the typed mode and supplies row/cache callbacks. This
preserves synchronous media-server restart dispatch and the accepted retry's
status → rows → cache sequence within one continuation, without an extra await
between row presentation and cache dispatch. The callback implementation still
owns view-token/mounted rejection and the same frozen/pending preparation path.
An empty successful batch updates the addon status but dispatches no rows/cache;
final-only search rows still do not become accumulated engine batches. The old
inline merge/retry logic and unused retry-controller getter were removed. Sources
part **1,524 → 1,528 lines**: the explicit mode switch makes the view slightly
longer while removing its service-selection and merge orchestration decisions.

Baseline: **484 Sources tests pass**. Final affected run: **494 pass**, including
ten new cases for media-server idle/searching behavior, empty/nonempty completion,
callback order, pre-dispatch caller retirement, pending view/query/profile/scope
retirement, duplicate requests and failure. The query replacement case deliberately
omits `prepareSearch` to independently prove that search generation rejects stale
retry merging; existing preparation tests cover retry-generation reset separately.
The original retry controller and existing acceptance/merge algorithm are unchanged.

The first affected run had only one new-test failure: its scheduled microtask
marker had not run when the test asserted the full event list. The test now waits
for the marker, then asserts rows/cache preceded it. Production code was unchanged
for that correction. Receipts preserve both runs: `retry-owner-before.txt`,
`retry-owner-after.txt`, `retry-owner-verified.txt`, `retry-owner-generation.txt`,
`retry-owner-format.dart`, `analyze-retry-owner.txt` and
`retry-owner-analyzer-comparison.txt` under `.git/refactor-evidence/phase4c/`.
Analyzer retains **863 diagnostics**, no added identities; **143 migrated files**
pass architecture checks. Phase 4C and later/native/performance/CI gates stay open.

Full-suite review: **8,134 successes / the same 51 failures / 20 skips**.
Every prior checkpoint outcome is preserved, and all ten new retry cases pass.
Original-baseline comparison finds no new failures, missing tests or new skips.
Receipts: `full-retry-owner.jsonl`, `full-retry-owner-comparison.txt`,
`full-retry-owner-previous-checkpoint.txt` and `retry-owner-review.txt`.
The baseline helper remains nonzero for existing failures; no allowance changes.
Changed code/method formatting, diff and architecture checks pass. Phase 4C and
later/native/performance/CI gates remain in progress.

### Phase 4C — shared pure result-merge policy

Extracted the merge policy into `lib/services/torrent_result_merge.dart` (**60
lines**, imports only the Torrent model). The Sources application controller now
calls the pure function directly. The existing TorrentService API delegates and
retains its original diagnostic for deduplicated/default mode, with no diagnostic
for preserve-source-order mode. All original callers remain compatible; the
service's old private merge/tie-break implementations were removed.

This is a shared policy, used by Sources and the legacy service's keyword/IMDb
search paths. Its existing services location avoids a dependency from shared
infrastructure into a feature. It is registered in the architecture/size guard.
The retained legacy torrent service shrinks **1,093 → 1,053 lines** and still
owns its pre-existing engine/network orchestration; that adapter boundary remains
part of the final review. Other Stremio/source-priority transitive dependencies
are not claimed resolved by this direct import change.

Review mechanically matches the original algorithm/comments after unindenting,
removing `static`, renaming the entry point and retaining the diagnostic in the
wrapper. Everything before the original merge section is unchanged apart from
one import. Exact-hash deduplication, highest-seeder/name/source precedence,
first-winner behavior for exact ties, provider-order concatenation, original
Torrent identities and mutable new result lists are preserved. No normalization,
sorting optimization or package upgrade was introduced.

Baseline: **501 affected Sources/streaming-merge tests pass**. After integration:
**508 pass**, including seven new direct-policy cases for empty input in both
modes, duplicate/identity retention in Sources order, representative precedence,
exact ties, raw empty/case-sensitive hash keys and immutable input preservation.
The existing corpus-based arrival-order, associative and incremental merge cases
still exercise the compatibility API. The first run's one new-test failure came
from an untyped empty inner fixture list passed to `List.unmodifiable`; typing
the outer fixture fixed it without changing production code.

Analyzer remains **863 diagnostics**, no added identities; **144 migrated files**
pass architecture checks. Receipts under `.git/refactor-evidence/phase4c/`:
`merge-policy-before.txt`, `merge-policy-after.txt` (fixture failure retained),
`merge-policy-verified.txt`, `merge-policy-review.txt`, `analyze-merge-policy.txt`
and `merge-policy-analyzer-comparison.txt`. Phase 4C and later/native/performance/CI
completion gates remain open.

Full-suite review: **8,141 successes / the same 51 failures / 20 skips**.
Every previous checkpoint outcome is preserved, and all seven new merge-policy
cases pass. Original-baseline comparison finds no new failures, missing tests or
new skips. Receipts: `full-merge-policy.jsonl`,
`full-merge-policy-comparison.txt`, `full-merge-policy-previous-checkpoint.txt`
and `merge-policy-wrapper-format.dart`. Changed files and the legacy wrapper are
normally formatted; architecture/diff checks pass. No failure allowances changed;
the baseline helper remains nonzero for existing failures. Phase 4C and later
migration/native/performance/CI gates remain open.

### Phase 4C — shared addon-status model boundary

Moved `AddonSearchStatus` and its documentation byte-for-byte into
`lib/models/addon_search_status.dart` (**36 lines**, no imports), registered in
the measured architecture/size set. Search/retry controllers, provider projection,
and search state/result models now import it directly. StremioService imports
and re-exports that same declaration, preserving all existing import paths and
type identity. No duplicate class, model conversion or API change was introduced.

The retained Stremio service shrinks **3,754 → 3,720 lines**. Every declaration
from `StremioAddonImportResult` onward is byte-for-byte unchanged. Its pre-existing
installation/metadata/transport responsibilities remain behind legacy boundaries;
this move does not claim their migration or resolve other pure-selector/IPTV
transitive dependencies. The oversized retained-service scope is recorded in the
plan for the final boundary review.

Baseline and after: **494 Sources tests pass**. Existing retry completion,
request-key, projection and real-screen cases cover the model's behavior and
exercise the compatibility export. No new trivial model/structure tests were
added for a byte-preserving relocation. Analyzer retains **863 diagnostics**,
no added identities; **145 migrated files** pass architecture checks. Formatting
and diff checks pass without mass-formatting the legacy service.

Receipts under `.git/refactor-evidence/phase4c/`: `addon-status-before.txt`,
`addon-status-after.txt`, `analyze-addon-status.txt`,
`addon-status-analyzer-comparison.txt` and `addon-status-review.txt`.
Phase 4C and later/native/performance/CI completion gates remain open.

Full-suite review: **8,141 successes / the same 51 failures / 20 skips**, with
exactly the same test identities and outcomes as the preceding checkpoint.
Original-baseline comparison finds no new failures, missing tests or new skips.
Receipts: `full-addon-status.jsonl`, `full-addon-status-comparison.txt` and
`full-addon-status-previous-checkpoint.txt`. The baseline helper remains nonzero
for existing failures; no allowances changed. Final format/diff/architecture
checks pass. Phase 4C and the remaining migration gates stay open.

### Phase 4C — shared IPTV result model boundary

Moved `IptvSourceResult`, `IptvEpisodeResolutionStatus` and
`IptvEpisodeResolution` byte-for-byte into `lib/models/iptv_source_result.dart`
(**25 lines**, imports only Torrent). Sources link copying, search repository/API
contracts, provider projection and search state/result models now import the
model directly. IptvSourceSearch imports and re-exports the same declarations,
preserving existing imports and type identity without introducing DTO conversion.

The retained IPTV service shrinks **1,190 → 1,169 lines**; its entire search,
refresh, resolution and authorization implementation is unchanged. Constructors
and the legacy result-list contract are preserved, including const callers. The
production Sources repository still publishes `List.unmodifiable(result.torrents)`
through its existing snapshot function; that repository was not edited. This is
model/service separation, not a claim that the legacy result constructor itself
creates an immutable row list or that other service-backed classifiers are migrated.

Baseline and after: **494 Sources tests pass**. Existing resolution/copy,
repository snapshot, retry/projection and real-screen tests cover these contracts
and service compatibility exports. No trivial field/structure tests were added
for unchanged declarations. Analyzer retains **863 diagnostics**, no added
identities; **146 migrated files** pass architecture checks. The legacy service
was not mass-formatted. Receipts under `.git/refactor-evidence/phase4c/`:
`iptv-result-model-before.txt`, `iptv-result-model-after.txt`,
`analyze-iptv-result-model.txt`, `iptv-result-model-analyzer-comparison.txt`
and `iptv-result-model-review.txt`. Phase 4C and later/native/performance/CI gates
remain in progress.

Full-suite review: **8,141 successes / the same 51 failures / 20 skips**.
All test identities and outcomes exactly match the preceding checkpoint.
Original-baseline comparison finds no new failures, missing tests or new skips.
Receipts: `full-iptv-result-model.jsonl`,
`full-iptv-result-model-comparison.txt` and
`full-iptv-result-model-previous-checkpoint.txt`. The helper remains nonzero for
existing failures; no allowances changed. Final formatting/diff/architecture
checks pass. Phase 4C and later migration/native/performance/CI gates remain open.

### Phase 4C — shared pinned-stream matching policy

Extracted the pinned direct-stream selector into
`lib/services/pinned_direct_stream_match.dart` (**34 lines**, imports only Torrent),
registered in the measured architecture/size set. Sources selection and cached
fallback preparation call it directly. The original static StremioService API
remains a compatibility delegate, so browser selection and playback resolution
continue to share one implementation. The service shrinks **3,720 → 3,703 lines**.

Review matches the original selector signature/body after unindenting, removing
`static` and renaming the entry point. An explicit missing binge group is still
a miss; an existing group prefers the matching profile then its first candidate.
Without a group, profile identity is required and response index only breaks
profile ties. Original Torrent identity, caller ordering and miss behavior remain.
All service content outside the selector is unchanged apart from the import.

Selected-source matching also receives `isIptvSource` from the existing injected
binding matcher, alongside its media-server identity lookup. The view captures
that same adapter and supplies both functions. This removes both transport-service
imports from the selected-source policy without a new factory, state owner or
adapter. Candidate filtering/sorting, diagnostics and selection precedence remain
unchanged. The new test supplies an ownership rule that differs from the legacy
prefix, verifying the dependency is used and iteration stops at its first match.
Sources part **1,528 → 1,530 lines** due to explicit dependency wiring.

Baseline: **519 affected Sources/direct-stream tests pass**. After: **520 pass**.
Existing direct reuse, binding, source selection and fallback preparation tests
exercise both the compatibility API and direct policy callers. Analyzer retains
**863 diagnostics**, no added identities; **147 migrated files** pass architecture
checks. Changed code and the legacy view method are normally formatted without
whole-file formatting. Remaining source-priority/filter transitive dependencies
and later/native/performance/CI completion gates remain open.

Receipts under `.git/refactor-evidence/phase4c/`:
`pinned-stream-policy-before.txt`, `pinned-stream-policy-after.txt`,
`analyze-pinned-stream-policy.txt`, `pinned-stream-policy-analyzer-comparison.txt`,
`pinned-stream-policy-format.dart` and `pinned-stream-policy-review.txt`.

Full-suite review: **8,142 successes / the same 51 failures / 20 skips**.
Every prior checkpoint outcome is preserved, and the new injected-classifier case
passes. Original-baseline comparison finds no new failures, missing tests or new
skips. Receipts: `full-pinned-stream-policy.jsonl`,
`full-pinned-stream-policy-comparison.txt` and
`full-pinned-stream-policy-previous-checkpoint.txt`. The baseline helper remains
nonzero for existing failures; no allowance changes. Final format/diff/architecture
checks pass. Phase 4C and the remaining migration gates stay open.

### Phase 4C — filtering policies no longer depend on UI paths

Moved `TorrentQualityExtension` and `qualityTierForName` from the result-row
widget into `lib/utils/torrent_quality.dart` (**32 lines**). The widget re-exports
those declarations for compatibility, while TorrentFilterMatcher, FilterLadder
and Debrify TV filters now import the utility directly. The widget implementation
is unchanged and its file shrinks **639 → 611 lines**. The quality policy is
byte-for-byte identical to the original declarations.

Moved the player-path LanguageMapper to `lib/utils/language_mapping.dart`, with
a one-line export at the old path. Normal formatting expands the original 334
lines to **464 lines**; review confirms the result equals the normally formatted
original. This is one cohesive language alias/normalization/mapping responsibility,
within the accepted 301–500 range. TorrentFilterMatcher now imports the shared
path directly. No parsing rules, tables, fallback behavior or APIs changed.

The extracted policies, compatibility facade and adopted matcher/source-quality/
format-tag helpers join the measured source set. Shared registered utilities now
receive data-layer import checks, so direct UI and state-framework imports fail
the architecture guard. A recursive review of the actual matcher dependency graph
finds only seven project model/utility files plus dart:collection and Flutter
foundation; no UI or service dependency remains in that graph. This closes the
filter-classification exception, not SourcePriority's separate service coupling.

Baseline and after: **559 affected Sources/quality/language/filter-ladder tests
pass**. Existing quality tests continue exercising the widget export while real
filter callers use the shared utility; language tests similarly cover the old
path. No new tests were added for unchanged policy relocations. Analyzer retains
**863 diagnostics**, no added identities; **153 migrated files** pass architecture
checks. Row/player rendering was not modified. Native/visual completion gates
remain pending alongside the rest of phase 4C and later phases.

Receipts under `.git/refactor-evidence/phase4c/`:
`filter-policy-boundaries-before.txt`, `filter-policy-boundaries-after.txt`,
`analyze-filter-policy-boundaries.txt`,
`filter-policy-boundaries-analyzer-comparison.txt`,
`filter-policy-language-original.dart` and `filter-policy-boundaries-review.txt`.

Full-suite review: **8,142 successes / the same 51 failures / 20 skips**, with
exactly the same test identities/outcomes as the preceding checkpoint.
Original-baseline comparison finds no new failures, missing tests or new skips.
Receipts: `full-filter-policy-boundaries.jsonl`,
`full-filter-policy-boundaries-comparison.txt` and
`full-filter-policy-boundaries-previous-checkpoint.txt`. The helper remains
nonzero for existing failures; no allowance changes. Final format/diff/architecture
checks pass. Phase 4C and remaining migration/native/performance/CI gates stay open.

### Phase 4C — pure provider ordering separated from loading

Moved the eight pure SourcePriority operations into
`lib/services/source_ordering.dart` (**193 lines**), and SourceProviderRef into
`lib/models/source_provider_ref.dart` (**17 lines**). Five Sources application
consumers now call SourceOrdering directly. The original SourcePriority API
(**301 → 144 lines**) delegates those methods and re-exports the descriptor,
retaining its provider/alias loading methods for existing settings/repository
callers. No new DI object, storage abstraction or duplicate ordering logic was added.

Review compares all eight methods against the normally formatted original after
renaming the utility class and adding braces around the same provider-prefix
return. The descriptor and provider/alias loading bodies are byte-for-byte
unchanged. Stable provider order, legacy aliases, direct-link prioritization,
case-insensitive dedupe, original identities and unchanged-list fast paths are
preserved. The repository's load/retirement/priority snapshot sequence is untouched.
The new pure graph contains only SourceOrdering, Torrent and SourceProviderRef.

Both files join the measured source set. Registered shared service files now
receive data-layer import checks, alongside shared utilities; this strengthens
the guard without allowing new UI/framework dependencies. The facade remains a
legacy data-loading boundary, not an application-policy dependency. Descriptor
constructor/legacy-key set semantics are preserved for compatibility; no collection
contract was changed incidentally.

Baseline and affected run: **563 Sources/priority/Quick Play tests pass**. Existing
SourcePriority tests exercise the compatibility facade while real Sources tests
exercise the new policy path. No duplicate test suite was added for moved methods.
The first analyzer run found a missing-braces info exposed by formatting the
extracted multi-line return condition; adding braces preserves the condition and
returns and resolves it. Final analyzer: **863 diagnostics**, no added identities.
**155 migrated files** pass architecture checks. New/extracted code and the now
small facade are formatted. Phase 4C and later/native/performance/CI gates remain
in progress.

Receipts under `.git/refactor-evidence/phase4c/`: `source-ordering-before.txt`,
`source-ordering-after.txt`, `analyze-source-ordering.txt` and
`source-ordering-analyzer-comparison.txt` (initial lint retained),
`analyze-source-ordering-final.txt`, `source-ordering-final-analyzer-comparison.txt`,
`source-ordering-original.dart` and `source-ordering-review.txt`.

Initial full-suite run: **8,141 successes / 52 failures / 20 skips**. The only
changed prior outcome is the previously observed remote-transfer large-binary
`.part` cleanup race (line 313). The transfer test and implementation are unchanged;
inspection again finds completion published before awaited receipt journaling and
file deletion. All 18 transfer tests pass in isolation. This is consistent with
the earlier recorded intermittent failure; it is not accepted into any allowance.
The full suite was repeated unchanged. Initial evidence is retained in
`full-source-ordering.jsonl`, `full-source-ordering-comparison.txt`,
`full-source-ordering-initial-previous-checkpoint.txt` and
`source-ordering-transfer-isolated.txt`.

Final unchanged repeat: **8,142 successes / the same 51 failures / 20 skips**.
All test identities/outcomes match the previous checkpoint; original-baseline
comparison finds no new failures, missing tests or new skips. The transfer case
passes in this full run. Receipts: `full-source-ordering-verified.jsonl`,
`full-source-ordering-verified-comparison.txt` and
`full-source-ordering-verified-previous-checkpoint.txt`. Both full runs remain
recorded. Final formatting/diff/architecture checks pass; no allowances changed.
Phase 4C and remaining migration/native/performance/CI gates are still open.

### Phase 4C — playback metadata boundary for the remaining view extraction

Moved PlaybackMeta to `lib/models/playback_meta.dart` (**101 lines**) and
PlaybackResumePolicy to `lib/models/playback_resume_policy.dart` (**6 lines**).
The original services import/re-export the same declarations for compatibility.
The Sources playback bridge now imports metadata directly and limits its service
import to TorrentPlaybackService. Both model files are in the measured source set;
no parallel metadata representation, conversion or new playback effect was added.

Review proves PlaybackMeta equals the normally formatted original and the enum
matches byte-for-byte. All implementation code in the playback service and local
resume resolver is unchanged. The retained files shrink **8,866 → 8,773** and
**126 → 122 lines**, respectively. Constructor defaults, canonical/source-specific
resume selection, progress identity and tracker flags remain unchanged. Catalog
and artwork objects keep their existing borrowed identities; this is not a new
deep-immutability contract. The recursive metadata graph reaches only model/URI
helpers, dart:convert and crypto, without project UI/service dependencies.

Baseline and affected run: **515 Sources/resume/direct-stream tests pass**.
Existing bridge wiring, direct stream reuse and resume precedence cases cover the
compatibility path. No trivial duplicate model tests were added. The first
analyzer run identified two now-unused service imports and a redundant bridge
import; removing the former and restricting the bridge service import resolved
all three. Final analyzer: **863 diagnostics**, no added identities.
**157 migrated files** pass architecture checks. New models and the bridge are
formatted; neither large legacy service was mass-formatted. Native handoff and
lifecycle verification remain phase-7 gates; this move does not claim them done.

Receipts under `.git/refactor-evidence/phase4c/`: `playback-meta-model-before.txt`,
`playback-meta-model-after.txt`, `analyze-playback-meta-model.txt`,
`playback-meta-model-analyzer-comparison.txt` (initial import findings retained),
`analyze-playback-meta-model-final.txt`,
`playback-meta-model-final-analyzer-comparison.txt`,
`playback-meta-model-original.dart` and `playback-meta-model-review.txt`.
Phase 4C and later/native/performance/CI completion gates remain in progress.

Full-suite review: **8,142 successes / the same 51 failures / 20 skips**.
All test identities/outcomes match the preceding completed checkpoint.
Original-baseline comparison finds no new failures, missing tests or new skips.
Receipts: `full-playback-meta-model.jsonl`,
`full-playback-meta-model-comparison.txt` and
`full-playback-meta-model-previous-checkpoint.txt`. The baseline helper remains
nonzero for existing failures; no allowance changes. Final formatting/diff/
architecture checks pass. Phase 4C and later/native/performance/CI gates stay open.


### Phase 4C — Sources action presentation

Extracted play/copy/pin/unpin and row-menu presentation into the view-owned
`SourceActions` (222 formatted lines). The production view dispatches to it;
original methods are removed. Existing application controllers still own binding,
persistence and link resolution; named presentation bridges own legacy playback
and picker calls. The helper borrows the view context/ref/session and explicit
live inputs, owns no focus/search state, and starts no effects on construction.

Review retained tap suppression, freeze-before-play, rendered-list/index identity,
post-play reload, copy continuation guards/messages, external-link pin rejection,
and menu capability projection inside the modal builder. Widget details are read
live, including after binding awaits. The captured originating picker route alone
is popped/removed after success; mounted/profile checks and navigator ownership
remain in place. Existing real-screen tests exercise these paths and origin
retirement; no duplicate implementation-shaped tests were added.

Baseline: **495 Sources tests pass**. Initial extraction checks caught a mechanical
`navigator.mounted` rename and five unused parent imports. Those are fixed; the
initial failing receipts remain recorded. Final affected run: **495 pass**;
analyzer **863 diagnostics**, no new identities; **158 migrated files** pass
size/import checks. Full-suite comparison is recorded below.
Receipts under `.git/refactor-evidence/phase4c/`: `action-presentation-before.txt`,
`action-presentation-after.txt`, `analyze-action-presentation.txt`,
`action-presentation-fixed.txt`, `analyze-action-presentation-fixed.txt`,
`action-presentation-analyzer-comparison.txt` and the formatting review stubs.

Phase 4C remains open: the Sources view still needs further cohesive extraction
before its standalone feature move. Discover backdrop components in the same
legacy part remain phase-6 scope. Native, performance, CI and full-library
retirement gates are not satisfied by this action extraction.

Full suite: **8,142 successes / the same 51 failures / 20 skips**. Every test
identity/outcome matches the previous checkpoint; no added failures, missing
tests or new skips against the original baseline. Receipts:
`full-action-presentation.jsonl`, `full-action-presentation-comparison.txt` and
`full-action-presentation-previous-checkpoint.txt`. No failure allowance changed.
The Sources part shrinks **1,530 → 1,382 lines**. Only changed methods were checked
through a formatter stub; the final row-callback wrap is whitespace-only. The
unrelated existing provider getter formatting was left untouched.


### Phase 4C — row and toolbar focus navigation

Moved directional row/pill/filter decisions into the existing SourceResultsFocus
coordinator (**201 lines**). The view continues to own every node and scroll
controller; there is no additional state owner or resource lifecycle. Production
classic and redesigned row callbacks, the pending-results pill and toolbar funnel
now dispatch to that coordinator. Live pending-result and TV-mode getters retain
callback-time behavior. Row movement still freezes streaming first, the pending
pill still precedes the funnel, classic rows do not acquire redesigned funnel
behavior, and an unattached funnel still allows the pill's Up key to bubble.

Baseline: **495 Sources tests pass**. Final affected suite: **499 pass**, including
four new widget cases for first-row classic/TV/touch behavior, row boundaries,
pending priority, live pending changes and empty targets. Existing real-screen
focus/resize/retirement tests also pass. Analyzer **863 diagnostics**, no added
identities; **158 migrated files** pass size/import checks. The Sources part
shrinks **1,382 → 1,343 lines**. Diff review confirms the callbacks are delegated
without changing widget structure, action ordering, node ownership or disposal.

Receipts under `.git/refactor-evidence/phase4c/`: `row-navigation-before.txt`,
`row-navigation-after.txt`, `analyze-row-navigation.txt` and
`row-navigation-analyzer-comparison.txt`. Full-suite results follow below.
Phase 4C, standalone view retirement, broader migration and required native/
performance/CI gates remain open.

Full suite: **8,146 successes / the same 51 failures / 20 skips**. Every prior
checkpoint outcome is preserved, with exactly the four new passing focus cases.
Original-baseline comparison finds no new failures, missing tests or new skips.
Receipts: `full-row-navigation.jsonl`, `full-row-navigation-comparison.txt` and
`full-row-navigation-previous-checkpoint.txt`. Changed legacy view methods pass a
formatter stub check (`row-navigation-format.dart`); no whole-file formatting or
failure-allowance changes. Phase 4C and later gates remain in progress.


### Phase 4C — toolbar presentation and filter interaction

Extracted toolbar composition, provider/sort/season dispatch and filter-dialog
presentation into SourceToolbarPresentation. The view's production body calls its
builder; replaced methods and toolbar-only getters are removed. This presentation
helper reads the existing scoped Riverpod controllers; it creates no subscriptions,
application state or resources. The view retains search/retry execution, projection
rebuilding, focus nodes, lifetime and subscription ownership. Its constructor is
side-effect free, and widget eligibility/series/active guards remain live callbacks.

Review retains provider projection order, lazy warning construction, captured
retry targets, current season inventory, select-before-search/rebuild ordering and
filter-dialog opening values. After the dialog, active/profile checks precede
provider access, and returned filters are compared with current filters before
applying/rebuilding. Existing modal retirement/retheme and actual screen tests
exercise these effects. No new DI registrations or persistence paths were added.

Baseline and affected run: **499 Sources tests pass**. The initial analyzer found
five unused parent imports and a multiline early-return brace diagnostic; all were
fixed. Final analyzer: **863 diagnostics**, no added identities. **159 migrated
files** pass size/import checks. Changed view methods were checked through a
formatter stub; its only difference was the stub's trailing blank line. Existing
large source files were not mass-formatted.

Receipts under `.git/refactor-evidence/phase4c/`:
`toolbar-presentation-before.txt`, `toolbar-presentation-after.txt`,
`analyze-toolbar-presentation.txt`, `analyze-toolbar-presentation-final.txt`,
`toolbar-presentation-analyzer-comparison.txt` and
`toolbar-presentation-format{,-before}.dart`. Full-suite results follow below.
Phase 4C and the remaining full-library/native/performance/CI gates stay open.

Full suite: **8,146 successes / the same 51 failures / 20 skips**. Every prior
checkpoint identity/outcome is preserved; original-baseline comparison finds no
new failures, missing tests or new skips. Receipts:
`full-toolbar-presentation.jsonl`, `full-toolbar-presentation-comparison.txt` and
`full-toolbar-presentation-previous-checkpoint.txt`. No allowances changed.
The helper is **141 formatted lines**; the Sources part shrinks **1,343 → 1,268**.
The derived-season fallback comment moves with the menu responsibility. Remaining
view extraction, Discover components and later/native gates are still pending.


### Phase 4C — picker diagnostic retirement snapshots

Moved diagnostic map construction and the six post-disposal fallback fields into
SourcePickerTrace (**85 lines**). The view captures its existing sink during
initState and passes ordinary callbacks, not Ref or subscriptions. Construction
reads no state. The view still owns subscription/resource disposal and captures
results, search and bound-count snapshots immediately before each original close
point. The original picker ID timing, map keys, selected/visible index semantics,
focus fields and detail override order remain unchanged. Result fields are read
from one current immutable state snapshot per event.

Two added tests verify that readers throwing after their individual close points
are never accessed by a delayed unmounted log, that each close point preserves its
own latest values, and that active logs reflect current row identity/state while
retaining detail overrides. Existing real-screen disposal/reveal cases also pass.
Baseline **499 Sources tests**; affected suite **501 pass**. Analyzer **863
diagnostics**, no added identities; **160 migrated files** pass size/import checks.
Changed view methods pass a formatter stub without whole-file formatting. The
Sources part shrinks **1,268 → 1,249 lines**; this is a diagnostics ownership move,
not completion of the remaining view/library retirement.

Receipts under `.git/refactor-evidence/phase4c/`: `picker-trace-before.txt`,
`picker-trace-after.txt`, `analyze-picker-trace.txt`,
`picker-trace-analyzer-comparison.txt` and `picker-trace-format.dart`.
Full-suite results follow below. Phase 4C and later/native/performance/CI gates
remain open.

Full suite: **8,148 successes / the same 51 failures / 20 skips**. All prior
checkpoint outcomes are preserved, with exactly the two added trace tests passing.
Original-baseline comparison finds no new failures, missing tests or new skips.
Receipts: `full-picker-trace.jsonl`, `full-picker-trace-comparison.txt` and
`full-picker-trace-previous-checkpoint.txt`. No allowances changed. Final diff,
formatting and architecture checks pass; remaining migration gates are open.


### Phase 4C — rendered result and focus-transition coordination

Extracted SourceResultsPresentation (**282 lines**) as the one per-view owner of
the rendered row projection, selected-source marker and cached-episode marker.
Existing Riverpod controllers remain the authoritative owners of results, pending
batches, filters and saved data. The presentation component coordinates their
updates with borrowed row nodes/focus operations; it creates no provider,
subscription, focus node, scroll controller or asynchronous initialization.
The view retains loading/rebuild effects and all resource/subscription disposal.

Production streaming, completion, pending adoption, toolbar rebuilding, selected
source matching and profile/query clearing now use this component. The replaced
methods and three duplicate view fields are removed; view getters borrow the
same rendered list/identities for row rendering and playback. Live callbacks
preserve effective selection, bind mode, season eligibility, TV mode, mount state
and search generation. The two small view focus callbacks remain tear-offs so
constructing the borrowed focus coordinator does not recursively construct this
presentation object.

Review retains the exact transition sequence: capture user-focused torrent before
adoption; display through the existing controller; update selected/cached markers;
project and resize nodes; emit diagnostics; end loading; restore the user's row or
apply the existing selected-source/TV anchor. Toolbar rebuilding still freezes,
adopts pending rows and checks cache before projection, replaces nodes post-frame
and keeps toolbar focus. Completion and profile/query retirement preserve their
existing guards and node-reset order. No application policy or retry owner moved
into this component.

Baseline **501 Sources tests pass**; the initial affected run also passes all 501.
The final expanded run passes **527 Sources/cinema-focus/badge-focus/focus-lifecycle
tests**. The first analyzer identified the removed pending getter and three stale
imports; those are cleaned up. Final analyzer: **863 diagnostics**, no added
identities. **161 migrated files** pass size/import checks. Changed legacy methods
pass a formatting stub; no whole-file formatting. The Sources part shrinks
**1,249 → 1,064 lines**, including the still-pending Discover components.

Receipts under `.git/refactor-evidence/phase4c/`:
`results-presentation-before.txt`, `results-presentation-after.txt`,
`results-presentation-focus.txt`, `analyze-results-presentation.txt`,
`analyze-results-presentation-final.txt`,
`results-presentation-analyzer-comparison.txt` and
`results-presentation-format.dart`. Full-suite results follow below. The next
structural milestone is the standalone Sources feature view; no claim is made
that phase 4C, native/performance checks or the full library migration is complete.

Full suite: **8,148 successes / the same 51 failures / 20 skips**. Every previous
checkpoint identity/outcome is preserved. Original-baseline comparison finds no
new failures, missing tests or new skips. Receipts:
`full-results-presentation.jsonl`, `full-results-presentation-comparison.txt` and
`full-results-presentation-previous-checkpoint.txt`. Final formatting, diff and
architecture checks pass; no failure allowances changed. Phase 4C and later
migration/native/performance/CI gates remain open.


### Phase 4C — standalone Sources feature view

Moved the actual SourcesScreen widget/state to
`lib/features/sources/presentation/sources_screen.dart` (**678 normally formatted
lines**), with explicit imports and no shared-library part dependency. All three
production launch sites and the existing testing factory instantiate the public
widget. Its optional key is the only constructor addition. The legacy Sources
part shrinks **1,064 → 436 lines** and now retains only the testing factory and
Discover visuals; those remain phase-6/8 responsibilities, not removed behavior.

Responsibility review for the 501–800 range: the view owns composition, local
loading/query state, subscriptions and resource lifetime. Existing bounded
application controllers own search/retry/results/settings/binding state and data
operations; presentation coordinators own actions, toolbar dispatch, rendered
projection/focus transitions and diagnostics. No persistence/network/native API
is imported directly. Remaining transitive integration audits and native gates
are still required; being under the file ceiling does not close phase 4C.

The direct profile-service read now goes through the 19-line application
SourceSessionOwnership dependency, captured during initState. It evaluates the
current owner at each capture/check rather than caching a boolean; the original
owner-capture timing and mount/profile guards are preserved. A new test verifies
lifecycle-only clears without scope/runtime changes and continued use of the
captured reader after its container is disposed. This avoids treating the scope
notifier as the sole source of lifecycle invalidation.

Source comparison proves the entire view equals the normally formatted original
after the explicit class/key/ownership substitutions. The remaining Discover tail
is byte-for-byte unchanged; the test factory only changes the widget class name.
The parent diff removes now-unused imports and renames exactly the three launch
sites, without route/argument changes. Baseline/initial affected run: **527 tests
pass**. Final affected Sources/focus run: **528 pass**. Initial analyzer findings
were stale parent imports, one redundant view import and the newly public key
lint; all are addressed. Final analyzer **863 diagnostics**, no added identities;
**163 migrated files** pass size/import checks. No guard exceptions were added.

Receipts under `.git/refactor-evidence/phase4c/`: `standalone-view-before.txt`,
`standalone-view-after.txt`, `standalone-view-final.txt`,
`analyze-standalone-view.txt`, `analyze-standalone-view-final.txt`,
`standalone-view-analyzer-comparison.txt`, `standalone-view-expected.dart` and
`standalone-view-review.txt`. Full-suite results follow below. Phase 4C and the
remaining migration/native/performance/CI completion gates remain open.

Full suite: **8,149 successes / the same 51 failures / 20 skips**. Every prior
checkpoint outcome is preserved, with exactly the new ownership case passing.
Original-baseline comparison finds no new failures, missing tests or new skips.
Receipts: `full-standalone-view.jsonl`, `full-standalone-view-comparison.txt` and
`full-standalone-view-previous-checkpoint.txt`. Final formatting/diff/architecture
checks pass; no failure allowances changed. The standalone move is verified by
host tests; native, performance, CI and remaining boundary gates stay open.


### Phase 4C — move the Sources testing factory deliberately

Moved sourcesScreenForTesting into the 36-line test fixture
`test/features/sources/fixtures/sources_screen_factory.dart`; all ten importing
caller/fixture files now reference it there. Its actual SourcesScreen,
ProviderScope repository override, owner, defaults and retry/search forwarding
are unchanged. The search argument uses the existing structurally identical
LegacySourceSearchOverride typedef instead of importing the legacy service alias.
All repository callers migrated together, so no production re-export is needed.

The Search library no longer imports Sources search repository implementation,
API aliases or dependency wiring for test-only construction. The old Sources
part now contains only Discover visuals (**436 → 407 lines**); its remaining tail
is byte-for-byte unchanged. Source comparisons also prove that the factory body
is unchanged apart from the callback typedef and all ten caller files change
imports only. No assertions, fixtures' behavior or test coverage were removed.

Baseline and affected run: **512 Sources/cinema-focus tests pass**. The analyzer
identified three unused Sources imports, then the remaining torrent-service alias
import after that cleanup; after removing all four,
**863 diagnostics** remain with no added identities. **163 migrated files** pass
architecture checks. The helper is normally formatted; existing test files were
not mass-formatted. The plan's test-factory relocation item is satisfied; remaining
phase-4C ownership/boundary and native gates still require their own evidence.

Receipts under `.git/refactor-evidence/phase4c/`: `testing-factory-before.txt`,
`testing-factory-after.txt`, `testing-factory-callers.txt`,
`testing-factory-review.txt`, `analyze-testing-factory.txt`,
`analyze-testing-factory-final.txt` and
`testing-factory-analyzer-comparison.txt`. Full-suite results follow below.

Full suite: **8,149 successes / the same 51 failures / 20 skips**. Every previous
checkpoint identity/outcome is preserved; original-baseline comparison finds no
new failures, missing tests or new skips. Receipts:
`full-testing-factory.jsonl`, `full-testing-factory-comparison.txt` and
`full-testing-factory-previous-checkpoint.txt`. The subsequent unused-import-only
cleanup passes the final analyzer comparison in `analyze-testing-factory-clean.txt`
and `testing-factory-clean-analyzer-comparison.txt`; earlier diagnostic receipts
remain recorded. Final diff/format/architecture checks pass, with no allowance
changes. Remaining phase-4C and broader migration/native/performance gates stay open.


### Phase 4C — shared durable binding descriptor policy

Extracted the shared descriptor builder into
`lib/services/durable_source_binding.dart` (**85 lines**), importing only Torrent
and SeriesSource models. Manual direct/IPTV pins and automatic validation/source
switches already share this policy; all continue through the original legacy
wrapper, which supplies the original classifiers, media-server binding resolver,
provider mapping and entry-time timestamp. This is a prerequisite for moving the
remaining manual binding UI, not a claim that that UI boundary is complete.

Review retains media-server-before-IPTV-before-addon precedence, including a null
media binding stopping fallback. Provenance rejection, stream-index default,
catalog scope, raw infohash, provider mapping and time fields are unchanged.
Transient playback URLs/headers never enter constructed addon/IPTV descriptors.
The wrapper and all existing caller arguments remain compatible. All legacy
implementation outside the descriptor method/import is byte-for-byte unchanged;
the playback service shrinks **8,773 → 8,715 lines**, under its existing bounded
phase-4C/7 exception. The new pure policy is registered in the measured source set.

Baseline **549 Sources/addon/IPTV tests pass**; affected run **557 pass**, with
eight new plain-policy cases covering precedence, null/empty provenance,
credential exclusion, index defaults and raw torrent/provider/catalog identity.
Existing manual-pin and automatic-switch cases exercise production delegation.
Analyzer **863 diagnostics**, no added identities; **164 migrated files** pass
size/import checks. New files and the changed legacy method are normally formatted;
no whole-service formatting, DI registration or competing state owner was added.

Receipts under `.git/refactor-evidence/phase4c/`: `durable-binding-before.txt`,
`durable-binding-after.txt`, `analyze-durable-binding.txt`,
`durable-binding-analyzer-comparison.txt`, `durable-binding-original.dart`,
`durable-binding-wrapper-format.dart` and `durable-binding-review.txt`.
Full-suite results follow below. Manual binding UI ownership and remaining
migration/native/performance/CI gates stay open.

Full suite: **8,157 successes / the same 51 failures / 20 skips**. All prior
checkpoint identities/outcomes are preserved, with exactly eight new passing
policy cases. Original-baseline comparison finds no new failures, missing tests
or new skips. Receipts: `full-durable-binding.jsonl`,
`full-durable-binding-comparison.txt` and
`full-durable-binding-previous-checkpoint.txt`. Final formatting/diff/architecture
checks pass; no allowances changed. Phase 4C and later gates remain open.


### Phase 4C — direct-source binding presentation

Moved direct-pin view guards, feedback and interaction sequencing into
`presentation/direct_source_binding.dart` (**50 lines**). It receives ordinary
authorize/describe/save callbacks, imports only Flutter and typed models, and
creates no state owner or DI registration. The public legacy service method is a
compatibility wrapper returning this function's Future directly; it supplies the
same authorization, durable descriptor and guarded-or-legacy persistence calls.
The existing injected Sources bridge and other callers therefore use the new
production function without API changes.

Review preserves the initial optional-guard contract, authorization before IMDb
validation, post-authorization retirement checks, accepted descriptor types,
false/error save behavior, three-second feedback and successful-save return value
when a view retires during saving. The application binding controller still
rejects retired completion. Catalog arguments, movie/series persistence behavior
and saved descriptor identity are forwarded unchanged. All implementation outside
the replaced method/import is byte-for-byte unchanged; the retained playback
service shrinks **8,715 → 8,696 lines**. Other manual UI/preparation boundaries
remain open; this function does not close the whole binding migration.

Baseline **517 Sources/addon tests pass**. Final affected run **523 pass**, with
six added widget cases for retired entry, active/retired authorization failure,
retirement during rejected/successful save and legacy missing-identity ordering.
Two initial fixture cases lacked mandatory addon provenance; after correcting
that, callback-local assertions exposed Flutter guarded-test conflicts. Capturing
the saved value and asserting after the pump fixes the harness. Initial failed
receipts are retained; existing behavior tests stayed passing. Analyzer initially
has **863 diagnostics**, no added identities; final comparison follows below.
**165 migrated files** pass size/import checks. Both extracted code and the legacy
wrapper pass normal formatting checks without mass-formatting the service.

Receipts under `.git/refactor-evidence/phase4c/`: `direct-binding-ui-before.txt`,
`direct-binding-ui-after.txt`, `direct-binding-ui-fixed.txt`,
`direct-binding-ui-verified.txt`, `analyze-direct-binding-ui.txt`,
`direct-binding-ui-analyzer-comparison.txt`, `direct-binding-ui-original.dart`,
`direct-binding-ui-wrapper-format.dart` and `direct-binding-ui-review.txt`.
Full-suite results follow below. Phase 4C and remaining native/performance/CI and
full-library gates remain open.

Full suite: **8,163 successes / the same 51 failures / 20 skips**. Every prior
checkpoint identity/outcome is preserved, with exactly the six added UI cases
passing. Original-baseline comparison finds no new failures, missing tests or new
skips. Receipts: `full-direct-binding-ui.jsonl`,
`full-direct-binding-ui-comparison.txt` and
`full-direct-binding-ui-previous-checkpoint.txt`. Final analyzer remains **863**
with no added identities (`analyze-direct-binding-ui-final.txt` and
`direct-binding-ui-final-analyzer-comparison.txt`). Final diff/format/architecture
checks pass; no allowances changed. Remaining migration gates stay open.


### Phase 4C — IPTV binding presentation

Moved IPTV pin interaction, feedback and outcome emission into the 98-line
`presentation/iptv_source_binding.dart`. Its caller supplies authorization,
descriptor creation, persistence and the existing typed diagnostic sink. The
legacy public method returns the new presentation Future directly, preserving
all Sources bridge and other callers without another async continuation or state
owner. No transport, storage service or Riverpod dependency enters this function.

Review retains the initial optional action guard; started event and missing-IMDb
check before authorization; authorization error identity/feedback; distinct
view-closed versus session-retired diagnostics after authorization; provenance
rejection; save rejection, error logging/rethrow and saved outcome; and movie/
series success messages with the original three-second duration. A successful
save that finishes after retirement still returns true/logs saved without showing
feedback; the application controller retains its separate completion guard.
All legacy implementation outside the method/import remains byte-for-byte intact.

Baseline **540 Sources/IPTV tests pass**; affected run **552 pass**. Twelve new
widget cases cover each completion outcome and movie/series feedback, including
retirement during authorization/save and unchanged storage exception identity.
Existing real-pin/picker tests continue to exercise the production wrapper.
Analyzer **863 diagnostics**, no added identities; **166 migrated files** pass
size/import checks. New files are normally formatted; the changed legacy wrapper
received only the formatter's two-line whitespace-only wrapping adjustment.

Receipts under `.git/refactor-evidence/phase4c/`: `iptv-binding-ui-before.txt`,
`iptv-binding-ui-after.txt`, `analyze-iptv-binding-ui.txt`,
`iptv-binding-ui-analyzer-comparison.txt`, `iptv-binding-ui-original.dart`,
`iptv-binding-ui-wrapper-{before,format}.dart` and `iptv-binding-ui-review.txt`.
Full-suite results follow below. Local/debrid manual binding presentation and the
remaining migration/native/performance/CI gates stay open.

Full suite: **8,175 successes / the same 51 failures / 20 skips**. Every prior
checkpoint outcome is preserved, with exactly the twelve new IPTV UI cases
passing. Original-baseline comparison finds no new failures, missing tests or new
skips. Receipts: `full-iptv-binding-ui.jsonl`,
`full-iptv-binding-ui-comparison.txt` and
`full-iptv-binding-ui-previous-checkpoint.txt`. Final formatting/diff/architecture
checks pass; no allowances changed. The retained playback service is now
**8,624 lines** (from 8,696). Remaining migration gates stay open.


### Phase 4C — local-source binding presentation

Moved local pin view guards, missing-identity feedback, picker completion/save
sequencing and success feedback into `presentation/local_source_binding.dart`
(**33 lines**). It receives only picker/save callbacks and the existing optional
action guard. Native acquisition and filesystem ownership remain unchanged.
The public compatibility wrapper returns the presentation Future directly and
retains movie-versus-series selection, context/title/year/guard forwarding and
guarded-or-legacy persistence. Existing Sources bridge callers use this function.

Review retains empty-identity rejection before picking, null/cancelled results,
post-picker mounted/session checks, original descriptor identity, rejected saves,
uncaught picker/storage errors, and three-second success feedback. Saves finishing
after retirement keep their original true result without feedback; the application
controller still guards completion. All legacy code outside the method/import is
byte-for-byte unchanged. The playback service shrinks **8,624 → 8,614 lines**.
This extraction does not substitute widget tests for required native picker checks.

Baseline **520 Sources tests pass**; affected run **530 pass**, with ten new cases
for retired entry, missing identity, cancelled/retired/closed picker results,
accepted/rejected saves, retirement during save, and picker/storage error identity.
Existing real-picker integration and retirement cases also pass. Analyzer **863
diagnostics**, no added identities; **167 migrated files** pass size/import checks.
New files and the changed legacy wrapper are normally formatted without formatting
the entire service. No additional DI registration or state owner was introduced.

Receipts under `.git/refactor-evidence/phase4c/`: `local-binding-ui-before.txt`,
`local-binding-ui-after.txt`, `analyze-local-binding-ui.txt`,
`local-binding-ui-analyzer-comparison.txt`, `local-binding-ui-original.dart`,
`local-binding-ui-wrapper-format.dart` and `local-binding-ui-review.txt`.
Full-suite results follow below. Debrid/manual preparation boundaries and remaining
migration/native/performance/CI gates are still open.

Full suite: **8,185 successes / the same 51 failures / 20 skips**. Every previous
checkpoint outcome is preserved, with exactly the ten added local-binding cases
passing. Original-baseline comparison finds no new failures, missing tests or new
skips. Receipts: `full-local-binding-ui.jsonl`,
`full-local-binding-ui-comparison.txt` and
`full-local-binding-ui-previous-checkpoint.txt`. Final formatting/diff/architecture
checks pass; no allowances changed. Remaining migration gates stay open.


### Phase 4C — debrid pin presentation and readiness boundary

Moved manual torrent/debrid pin presentation to
`presentation/torrent_source_binding.dart` (**65 lines**). The caller supplies
provider selection, the exact loader dismissal callback, readiness acquisition,
descriptor construction, persistence and provider labeling. The presentation
function owns the interaction order and releases its loader in finally before
checking view/session retirement or showing feedback/writing. Unexpected injected
preparation errors also release the loader before propagating; production provider
errors retain their existing backend handling.

The compatibility wrapper retains all public arguments and returns the presentation
Future directly. Acquisition now lives in the context-free private readiness
method returning a typed `(ready, failureMessage)` record. Its entire prior body —
magnet resolution, guarded add, Real-Debrid/AllDebrid cleanup, PikPak processing/
failure messages and fallback catches — is byte-for-byte unchanged. The extracted
readiness call introduces an awaited boundary, after which the UI rechecks ownership
following loader dismissal. Existing actual route-ownership cases and the new
retirement tests pass. Descriptor construction remains after successful current
preparation, preserving raw hash/name, stored provider mapping, timestamp and addon
catalog fields. Save-result and late-success feedback semantics are unchanged.

Baseline **530 Sources tests pass**; affected run **545 pass**, with fifteen new
cases covering early exits, provider cancellation/configuration absence, view/
session retirement during picking and acquisition, loader-before-save ordering,
retirement caused by dismissal, unexpected preparation failure, specific/fallback
feedback, save rejection and late successful save. The first analyzer found one
multiline guard needing braces; that formatting issue is corrected. **168 migrated
files** pass architecture checks. The legacy service shrinks **8,614 → 8,607 lines**;
all code outside the binding block/import remains byte-for-byte unchanged.

Receipts under `.git/refactor-evidence/phase4c/`: `torrent-binding-ui-before.txt`,
`torrent-binding-ui-after.txt`, `analyze-torrent-binding-ui.txt`,
`analyze-torrent-binding-ui-final.txt`, `torrent-binding-ui-original.dart`,
`torrent-binding-ui-wrapper-format.dart` and `torrent-binding-ui-review.txt`.
Full-suite/final analyzer results follow below. Shared provider-picker/native and
preparation internals still need their recorded boundary review; this extraction
does not close phase 4C or the remaining migration/native/performance/CI gates.

Full suite: **8,200 successes / the same 51 failures / 20 skips**. Every prior
checkpoint identity/outcome is preserved, with exactly fifteen new passing
interaction cases. Original-baseline comparison finds no new failures, missing
tests or new skips. Receipts: `full-torrent-binding-ui.jsonl`,
`full-torrent-binding-ui-comparison.txt` and
`full-torrent-binding-ui-previous-checkpoint.txt`. Final analyzer remains **863**
with no added identities (`torrent-binding-ui-analyzer-comparison.txt`). Final
diff/format/architecture checks pass; no allowances changed. Remaining migration
gates stay open.


### Phase 4C — shared provider-picker presentation

Moved provider-selection orchestration into the 37-line
`presentation/source_provider_picker.dart`. The legacy wrapper supplies existing
configuration loading, provider display options, remembered-default persistence
and the cancellation sentinel; both manual binding and existing playback callers
use it. No new configuration/state owner or retry loop was introduced. The dialog
widget itself, provider option order/styles and storage operations are unchanged.

Review retains null configuration versus empty provider semantics, default and
single-provider fast paths, guarded and unguarded caller differences, view/session
checks around dialog display, dismissal behavior, awaited remembered writes and
the returned provider. In particular, legacy unguarded defaults may return after
their view closes, and a remembered write returns its selection after awaiting;
caller/storage ownership checks remain responsible for rejecting retired work.
No new blanket guard silently changes those existing contracts.

Baseline **545 Sources tests pass**; affected run **557 pass**, with twelve new
cases covering fast paths, configuration retirement, guarded/unguarded closed
views, real-dialog order/selection/remember/dismissal, rejected retired choices
and awaiting persistence. Existing real binding/provider/credential ownership
tests continue to pass. Analyzer **863 diagnostics**, no added identities;
**169 migrated files** pass size/import checks. The extracted function and wrapper
are normally formatted. All legacy implementation outside the method/import is
byte-for-byte unchanged; playback service **8,607 → 8,591 lines**.

Receipts under `.git/refactor-evidence/phase4c/`: `provider-picker-ui-before.txt`,
`provider-picker-ui-after.txt`, `analyze-provider-picker-ui.txt`,
`provider-picker-ui-analyzer-comparison.txt`, `provider-picker-ui-original.dart`,
`provider-picker-ui-wrapper-format.dart` and `provider-picker-ui-review.txt`.
Full-suite results follow below. Remaining native/integration ownership audits and
full-library/performance/CI gates are still open.

Full suite: **8,212 successes / the same 51 failures / 20 skips**. Every previous
checkpoint identity/outcome is preserved, with exactly twelve new passing picker
cases. Original-baseline comparison finds no new failures, missing tests or new
skips. Receipts: `full-provider-picker-ui.jsonl`,
`full-provider-picker-ui-comparison.txt` and
`full-provider-picker-ui-previous-checkpoint.txt`. Final diff/format/architecture
checks pass; no allowances changed. Remaining migration gates stay open.
