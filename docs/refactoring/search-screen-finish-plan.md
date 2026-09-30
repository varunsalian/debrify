# Search screen refactor — finish plan

Written 2026-09-30 on `refactor/search-screen` at `6dc5e10e`. **This file replaces
[search-screen-plan.md](search-screen-plan.md) for all remaining work.** The old
plan and [search-screen-evidence.md](search-screen-evidence.md) are frozen history:
do not read, update or copy them during this plan. Everything the next agent needs
is on this page plus `AGENTS.md`.

## Why this plan exists

The first three days produced 346 commits, 497 new feature files (41.5k lines),
66k lines of tests and 14k lines of plan/evidence. The screen shrank from ~29.9k
lines (five files) to one 9,964-line file. The work that was done was
tested at its gates, but the process spent most of its effort on per-helper checkpoints,
evidence receipts and repeated full-suite comparisons. This plan finishes the job
with a small number of large, **move-only** steps.

## What is already done (keep it; do not revisit)

- **Extracted and wired in production:** Home actions/resume (batch A), Sources
  acquisition/binding/playback/download (batch B), and most of the presentation
  (batch C): Search header/query/modes, Keyword page/toolbar/results/focus, Lists,
  Discover panels/focus/shell, every Home layout's composition widgets, Classic
  rows, Continue Watching composition, See-All routes. Lifecycle owners exist for
  board, continuation, saved-content and media bindings (batch D, partial).
- **Feature code:** `lib/features/{home,search,discover,sources,stremio_tv}` —
  22.4k / 5.6k / 2.0k / 10.4k / 1.0k lines.
- **Last recorded full gate:** 10,205 passing, same historical failures/errors/skips
  as the recorded baseline, no missing tests. Several later batch C/D commits
  have **no** full-suite run yet, which is why step 0 matters.

Do not re-extract, rename or "tidy" any of this. Reopen something only if a test
fails because of it.

## What remains

`lib/screens/search_screen.dart` (9,964 lines) is one `_SearchScreenState`:
~210 fields/getters, ~226 methods, 69 `setState` calls. Most of it is now glue:
getters forwarding to controllers, orchestration methods, and `_build*` methods
that pass many arguments into the already-extracted feature widgets.

| Area | Approx. lines | Key symbols (find with `grep -n`) | Destination (filled in step 10) |
| --- | --- | --- | --- |
| Top-level consts, imports, widget class | 380 | `_discCw`, `_kStageMinPosterH`, `_kPromRestVeil` |  |
| Search modes, header, query, Lists, catalog search, title suggestions | 740 | `_switchMode`, `_buildHeader`, `_buildSearchField`, `_buildBody`, `_onQueryChanged/Submitted`, `_clearQuery`, `_runCatalogSearch`, `_runListsSearch`, `_openListsResult`, `_listsNavigation`, `_openSuggestedTitle`, `_scheduleTitleSuggestions`, `_handleSearchBack`, `_focusContent` |  |
| Keyword search | 960 | all `_kw*`, `_runKeyword`, `_presentKwStreaming`, `_finishKeyword`, `_openKeyword{Sort,Filters,Providers,Sources}`, `_openBulkAdd`, `_showKwStreamMenu`, `_buildKeyword*`, `_takeKeywordSnapshot`, `_restoreKeywordState` |  |
| Continue Watching (local, Trakt, Simkl, MDBList, IPTV) | 1,560 | all `_cw*`, `_trakt*`, `_simkl*`, `_mdblist*`, `_iptvCw*`, `_load*ContinueWatching`, `_maybeAnnounce*Rows`, `_remove*CwItem`, `_openCwCardMenu`, `_pushCwSeeAll`, `_buildContinueWatchingRow`, `_buildTraktSkeletonRow` |  |
| Favorites, watchlist, playlist, IPTV lists | 1,070 | `_favRowKinds`, `_favNodesFor`, `_focusFavRowAt`, `_load{TvFavorites,StremioTvFavorites,IptvFavorites,IptvListRows,MyWatchlist,PlaylistFavorites}`, `_play{Channel,StremioTvChannel,IptvChannel,IptvListChannel,PlaylistItem}`, `_onPlaylistItemTap`, `_openMyWatchlistItem`, `_build*FavRow`, `_buildWatchlistRow`, `_buildIptvListRow` |  |
| Board loading, paging, config, focus | 1,420 | `_load`, `_loadMoreBoard`, `_loadMoreRow`, `_applySections`, `_appendSections`, `_publishHomeProgress`, `_homeRefreshQueue`, `_reloadForHomeSettings`, `_maybeAutoFocusBoard`, `_reclaimDeadFocus`, `_focusRow`, deferred-Down (`_pendingDown*`), `_continueHomeCatalogs`, `_buildBoard*`, `_buildClassic*`, `_buildRow` |  |
| Stage layouts and Spotlight | 1,800 | `_stage*`, `_canvas*`, `_atrium*`, `_mosaic*`, `_tonight*`, `_promenade*`, `_build{Canvas,Promenade,Atrium,Mosaic,Deck,Tonight,Spotlight,SearchSpotlight}Board`, `_spotlight*`, `_searchSheet`, `_home{Display,StyleEffective}` |  |
| Hero, trailer, live IPTV preview, ambient art, tint | 565 | `_hero*`, `_setHero`, `_applyHero`, `_scheduleHeroTrailer`, `_setHeroLiveIptv`, `_clearHeroLiveIptv`, `_publishAmbientArt`, `_updateHeroTint`, `_enrichHero`, `_relayChromeDim`, `_relayLightsOff` |  |
| Discover glue | 200 | `_disc*`, `_buildDiscover*`, `_selectDiscoverSource`, `_primeDiscoverRows` |  |
| Item open / detail / playback actions | 680 | `_openItem`, `_handleDetail*`, `_onCatalogPlay`, `_onCatalogBrowse`, `_openEpisodes`, `_playSelection`, `_browseSelection`, `_openSourceBinding`, `_resolveResumeInfo`, `_metaFor`, `_snack` |  |
| Lifecycle | 710 | `initState` (386), `dispose` (136), `didChangeDependencies`, `didPushNext/PopNext`, `didChangeAppLifecycleState`, `_restoreHomeSnapshot`, `_preserveHomeSnapshot`, profile/integration listeners |  |

## Invariants to preserve (carried over from the old plan)

Every move must keep these. If a test or review shows one changed, stop and fix
the move; don't record it as "Found, not fixed".

1. Home, Search, Discover and every display style keep their routes, settings,
   visible behaviour, empty/error/loading states and input paths.
2. Keyword search keeps its relevance order, sort directions, provider
   selections, direct-link handling, cache badges, cached-only mode,
   streaming freeze/adopt, bulk selection and completed-search restoration.
3. Title suggestions keep their debounce, composition handling, mode
   cancellation, exact title identity, and cancellation of stale detail opens.
4. Catalog loading keeps its raw paging cursors, hidden/watched filtering, row
   identity, deduplication, timeout/retry and deferred continuation. Android TV
   keeps progressive reveal; tvOS and non-TV keep their distinct behaviour.
   Catalog **search**: TV publishes a completed batch in stable catalog order,
   and non-TV streams completed rows. Disabled-addon settings, concurrency
   limits, partial-failure counts and the query/raw-cursor See-All handoff stay.
5. Profile and request generations still stop late results from crossing
   profiles or replacing newer work. Home/Search/Discover snapshots stay
   separate and are still invalidated on settings, integration and profile
   changes.
6. D-pad focus, hold versus press, source tabs, scrolling, dialog return,
   sidebar handoff, route coverage and returning from playback keep their
   ordering.
7. Continue Watching/tracker precedence, resume/rewatch choices, source binding,
   playback metadata, watch-progress writes and external/native handoffs stay
   compatible. No player-engine changes.
8. Hero, trailer and live previews keep their eligibility, dwell/cancellation,
   volume, foreground-playback suppression and resource cleanup, with no
   duplicate players.

## Definition of done

1. `search_screen.dart` is **at most 800 lines** (the AGENTS.md ceiling) and
   contains only: the widget class, ordered construction/disposal of the section
   coordinators, `build`, and route/app-lifecycle callbacks.
2. Every new file is **at most 500 lines** (prefer under 300) with one responsibility.
3. `flutter analyze` introduces no new diagnostics. By test identity, the full
   suite has no new failures, missing tests or new skips compared with the
   accepted step 0 run and the original baseline.
   `python3 dev/tool/check_search_architecture.py` passes.
4. The architecture guard and scoped `flutter analyze` run in CI on pull
   requests (see CI under the steps).

**Deliberately changed from the old plan:** the 300-line facade target is dropped
in favour of the 800-line ceiling. That is enough for maintainability, and chasing
the last 500 lines costs more risk than it saves. Device and performance
acceptance stay **pending**: no emulators, per the user. Use the manual smoke
checklist at the end instead.

## The one technique: move-only section coordinators

Every step uses the same low-risk pattern. **The widget tree does not change.**
Same widgets, same keys, same `FocusNode`s, same build order. Only the Dart
location of the code moves.

1. Create a plain presentation class in `lib/features/<feature>/presentation/`,
   for example `HomeFavoritesSection` or `KeywordSearchSection`. It owns the moved
   fields, methods and local state.
2. Its constructor takes **only what the moved code uses**: controllers and
   bindings it already reads, plus a small typed deps record of callbacks, for
   example `({void Function(VoidCallback) setState, bool Function() mounted,
   BuildContext Function() context, void Function(StremioMeta, ...) openItem,
   ...})`. Compiler
   errors after the move tell you exactly what belongs in that record.
3. Move method bodies **verbatim**. Allowed edits only:
   - `setState(fn)` → `_deps.setState(fn)`. The screen passes its own `setState`,
     so the mutation stays **inside** the callback: same dispose assertion, same
     ordering. Never rewrite it as "mutate, then rebuild".
   - `mounted` → `_deps.mounted()` wherever the guarded code does not use a
     `BuildContext`.
   - **Where `context` is used.** `State.context` throws once the State is
     disposed, so *when* you fetch it matters:
     - Synchronous entry (a build method, a user action, or right after a passing
       `mounted` check): capture `final context = _deps.context();` at that
       point. After any `await`, guard with `if (!context.mounted) return;`
       exactly where the original checked `mounted`. This is equivalent because
       the State's element never changes, and it satisfies the
       `use_build_context_synchronously` lint.
     - Delayed entry (timers, listeners, `.then`, post-frame callbacks): keep the
       original `if (!_deps.mounted()) return;` **first**, and only then fetch
       `_deps.context()`. Never fetch the context before the mounted check.
     - Build helpers that only render may take `BuildContext context` as a
       parameter from the screen's `build`.
   - `widget.<field>` (`isTelevision`, `searchMode`, `discoverMode`, ...) → a
     getter in the deps record, so values from `didUpdateWidget` are still seen
   - `ref` → the passed `WidgetRef` (rule 9)
   - calls into another area → the callback in the deps record
   - `_foo` → `foo` when the screen must call it
4. **Construction and start-up.** Construct every section at the top of
   `initState`, right after `super.initState()`, in step order. That keeps the
   old eager field initialisers (`FocusNode`s, `ValueNotifier`s, focus pools)
   created before any `initState` code runs, as today. Code that lived *in*
   `initState` (listeners, subscriptions, first loads) moves into a section
   method such as `start()`. The screen calls it at the **exact point** where
   that code used to run, so registration order stays identical.
   Several dependencies are created partway through `initState`: bindings such
   as `_searchResultBindings`, `_homeBoardBindings`, `_continuationBindings`,
   `_favoriteBindings` and `_discoverBindings`, and the profile/session owners.
   A section constructed at the top must not take them as constructor values.
   Give it a getter closure (`() => _homeBoardBindings`), or hand the dependency
   to `start()`. Never move the creation of a binding earlier to make
   construction compile.
   **Disposal:** a section gets one `dispose()` only if its old disposals were
   contiguous in `dispose`. Otherwise it exposes several named disposal methods,
   and the screen calls them at the original positions. Disposal order must stay
   identical.
5. The screen keeps thin one-line forwarders only where many call sites use a
   member. Delete them in the last step if they are no longer needed.
6. Split a section into as many files as it needs to keep each at most 500
   lines, along real seams (loading, actions, rendering, focus), not by line
   count. The file names in the steps table are a starting point. Extra
   cohesive files are allowed **within the same step and commit** without any
   re-planning.
7. **Service imports: the main source of friction. Read before step 1.**
   The architecture guard rejects **any** `lib/services/…` import (and
   `http`/`shared_preferences`/`sqflite`) from a `…/presentation/` file,
   including pure types and enums. The only exception is a file listed in
   `PRESENTATION_BRIDGE_IMPORTS`. The screen itself is not checked (it sits in
   `lib/screens/`), and it imports **37** service files today. Almost every step
   will hit this, so handle each symbol by kind:
   - **Calls with side effects or I/O, and singletons.** Examples:
     - `StorageService.*` (merged-series flag, `recordIptvWatch`,
       `getIptvPlaylists`, `setMyWatchlistItem`, playlist favourite/progress/
       remove, the `localCompletionRevision` listener)
     - `MdblistService.instance.playbackRevision`,
       `HomeListRowsService.instance.resolve`, `StremioIptvService.instance.*`,
       `TvosTopShelfService.instance.publishSpotlight`,
       `MetadataTitleService.instance.resolve`
     - `_stremio`, analytics, `TorrentBulkAddService`, `VideoPlayerLauncher`,
       `PlaylistPlayerService`, `YoutubeService`

     Pick the **first** option that works:
     1. Use an existing feature repository, controller or named bridge that
        already wraps the call (for example `home_catalog_playback_bridge.dart`
        already owns `torrent_playback_service`).
     2. Add a method to the feature's existing `data/` adapter or provider.
     3. Have the screen (the composition boundary) pass the function in the deps
        record, for example
        `mergedSeriesEnabled: StorageService.getMergedSeriesPageEnabled`.
   - **App-shell statics (`MainPageBridge.*`).** Use an existing shell bridge
     (`discover_shell_bridge.dart`, `home_hero_shell_bridge.dart`) or pass a
     callback from the screen. Don't import `main_page_bridge.dart` into a new
     section.
   - **Symbols already in a feature folder.** Some `lib/services/` files are only
     compatibility re-exports. Import the feature file directly, with no
     exception needed:
     - `HomeRowOrder` → `lib/features/home/application/home_row_order.dart`
     - `HomeRowRefresh` → `lib/features/home/models/home_row_refresh.dart`

     Check any other `lib/services/` import the same way (`head` the file for
     `export '../features/…'`) before treating it as a service.
   - **Static classes that read state or do I/O belong in the first bullet, not
     here, even when the call looks pure.** Route them through an existing
     adapter or an injected callback:
     - `WatchedFilter.hides/apply/predicate` reads the `HideWatchedPrefs` cache
       and is backed by singletons.
     - `HideWatchedPrefs` reads and writes preferences.
     - `ProfilePolicyGuard.allowsSync` reads the active profile. The same class
       also has async `allows`/`require`.

     A guard `show` list restricts **names, not members**: showing a class
     exposes every static method on it. So a class like these is never
     bridge-imported. Pass a callback instead, for example
     `keywordAllowed: () => ProfilePolicyGuard.allowsSync(ProfileFeature.keywordSearch)`.
   - **Pure declarations: plain types, enums and constants only.** Examples are
     the Simkl/MDBList menu-option enums already bridged for
     `home_detail_menus.dart`. Add a `PRESENTATION_BRIDGE_IMPORTS` entry for the
     new section file as a **dict with an explicit `show` set**, plus a one-line
     comment saying there is no I/O. Every shown name must be an enum, a const,
     or a data class with no static state or I/O. Open its declaration and check
     before adding it. Never add a bare (non-`show`) entry, and never show a
     class with static methods that touch storage, singletons or the network.

   Keep the exact arguments, `await`s, ordering and profile/owner guards. List
   each routing or bridge entry under "Non-move edits" in the commit. These are
   the only non-mechanical edits allowed.
8. The screen has 17 lazy `late final x = ...` fields (for example
   `_homeRefreshQueue`, `_stageNavigation`, `_searchSheet`, `_listsNavigation`,
   `_seeAllNavigation`). Keep them **lazy** `late final` inside the section. Do
   not turn them into constructor-time initialisation: that changes when they
   are created and what state they capture.
9. Where moved code uses `ref.read`/`ref.listenManual`, pass the `WidgetRef`.
   Keep each `listenManual` subscription created at the same `initState` point.
10. `RouteAware` and `WidgetsBindingObserver` stay on the screen. Their callbacks
    call section methods in the same order as today.
11. File-private top-level consts and functions (`_discCw`, `_kStageMinPosterH`,
    `_kAtriumLabelGap`, `_atriumLabelHeight`, `_kPromRestVeil`,
    `_kBoardBatchSize`) move **with their first user**, not in the last step.
12. **Seam check:** if a deps record needs more than about 12 callbacks, or a
    section would need the screen State itself, the seam is wrong. Split
    differently rather than pass a grab-bag. AGENTS.md forbids exposing the
    whole screen state or tightly coupled fragments.

Not allowed during a move:

- behaviour changes, bug fixes or logic rewrites
- renames outside the moved code
- new providers or Riverpod restructuring
- widget-tree or key changes
- changing timer or debounce values

If you find a bug, add it to **Found, not fixed** below and keep moving.

This is a presentation-layer move, so `BuildContext` in these sections is allowed
by AGENTS.md. Most business logic is already in the application and data layers
from batches A–D. Service access that remains is handled by rule 7, not moved
verbatim.

**Non-goals.** Do **not** add any of these:
- a base `Section` class, mixin or shared deps type
- a generic event bus or registry
- new interfaces "for testability"
- new Riverpod providers (except where rule 7 option 2 extends an existing
  feature provider)
- any renaming or restyling of extracted components

Eight similar plain classes are the intended result. Consolidating them is not
part of this plan.

**Temporary exception (AGENTS.md size rule):** `lib/screens/search_screen.dart`
stays over 800 lines until step 10. Its responsibilities and exit milestone are
the area table above and step 10.

## Steps (in this order: least coupled first)

Each step is **one commit** (two at most). Line counts are approximate. The
"after" column is the expected screen size.

| # | Step | New owner(s) | Screen after |
| --- | --- | --- | --- |
| 0 | Baseline (see **Step 0** below). | — | 9,964 |
| 1 | Discover glue | `features/discover/presentation/discover_section.dart` | ~9,760 |
| 2 | Keyword search | `features/search/presentation/keyword_search_section.dart` (plus `keyword_search_actions.dart` if over 500) | ~8,800 |
| 3 | Search modes, header, query, Lists, catalog search, title suggestions | `features/search/presentation/search_mode_section.dart` | ~8,060 |
| 4 | Item open / detail / playback actions | `features/home/presentation/home_item_actions.dart` | ~7,380 |
| 5 | Favorites, watchlist, playlist, IPTV lists | `home_saved_content_section.dart` (load/actions) + `home_saved_content_rows.dart` (row builders) | ~6,310 |
| — | **Full-suite gate 1.** `run_full.py finish/gate1`, then `compare.py` against both the original baseline and `--against finish/gate0b.jsonl` (the accepted baseline, see Progress), by test identity and outcome, including missing tests and new skips. | | |
| 6 | Continue Watching | `home_continuation_section.dart` (load/announce/remove) + `home_continuation_rows.dart` (rows, card menu, See-All) | ~4,750 |
| 7 | Hero / trailer / live preview | `home_hero_section.dart` | ~4,190 |
| 7b | **Safety net before the riskiest move.** Existing layout coverage is thinner than it looks. `home_progressive_{screen,pagination}_test.dart` loop over every style, but they check build and pagination, not directional navigation. The stage deferred-Right, hold and theater screen tests cover shared stage navigation. Add one parameterised widget test: reuse the fakes and harness from `home_progressive_screen_test.dart`, pump `SearchScreen` (TV) for each of the 8 styles with a fixed fake catalog, press Down/Right/Left/Up/Select, and assert focus lands on the same card key as today and no exception is thrown. Commit it on its own **before** step 8. It must pass unchanged after step 8. This is the only new test in the plan. | `test/features/home/home_layout_dpad_smoke_test.dart` | — |
| 8 | Stage layouts and Spotlight | `home_stage_section.dart` (navigation, deferred advance, focus) + `home_stage_boards.dart` (Canvas/Promenade/Atrium/Mosaic/Deck/Tonight builders) + `home_spotlight_section.dart` | ~2,390 |
| 9 | Board loading, paging, config, focus | `home_board_section.dart` (load/paging/config) + `home_board_focus.dart` (auto-focus, reclaim, deferred Down) + `home_classic_board.dart` (classic builders) | ~970 |
| 10 | Lifecycle and facade. `initState`/`dispose` become ordered construction and disposal of the sections. Delete dead forwarders and unused imports (the screen has ~290 import lines today). Also remove any adapter, export or compatibility re-export that these moves left unused, searching `lib/`, `test/`, source guards and the shape manifest first. Finally, fill the **Destination** column of the area table under "What remains" with the actual files, so every original responsibility has a named owner. If the file is still over 800 lines, move Home return-snapshot preserve/restore and profile/integration listeners into `home_return_section.dart`. Add CI (below). | `search_screen.dart` | ≤ 800 |
| — | **Full-suite gate 2** (final): `run_full.py finish/gate2`, compared against the original baseline and `--against finish/gate1.jsonl`. Also compare whole-repo `flutter analyze` identities with `compare.py --against .git/refactor-evidence/finish/analyze-gate0.txt <new analyze file>`: no added diagnostics. Then stop. The user has Claude run one `/code-review high` over `<step 0 commit>..HEAD` (the executing agent doesn't self-certify). | | |

### Step 0 — baseline (before any code moves)

**User, once:** type `/codex:setup --disable-review-gate`, so a Stop-hook review
doesn't run on every turn.

`dev/tool/test_baseline.py` is **not** enough on its own:
`test/known_failures.txt` has only 9 entries while the recorded runs contain 22
failures and 29 errors, and it doesn't detect missing tests. Use the identity
tooling in `.git/refactor-evidence/` instead.

1. Extend `.git/refactor-evidence/compare.py` with an `--against <file>` option:
   - `.jsonl`: reuse `outcomes()` against the given run.
   - analyzer `.txt`: reuse `diagnostics()` against the given file, instead of
     the hardcoded `baseline/analyze.txt`.

   Also fix its missing-test check. It currently only looks at suites present
   in the new run (`k.split('::')[0] in suites`), so a deleted or unloaded test
   file goes unnoticed. For full-suite comparisons, check **every** baseline test
   identity.
2. From the repo root (both scripts resolve paths from the current directory),
   run `python3 .git/refactor-evidence/run_full.py finish/gate0`. It writes
   `finish/gate0.jsonl` and never passes `--record`. Its exit code comes from the
   legacy `test_baseline.py` known-failures check, which is stale, so a nonzero
   exit is **not** the verdict. The gate is `compare.py`'s result.
3. Compare that run with the original baseline (`baseline/outcomes.json`), and
   with `--against .git/refactor-evidence/phase5/full-native-owner-c4.jsonl`,
   the last verified run (10,205 passes / 22 failures / 29 errors / 20 skips at
   `165fd015`). The 56 commits since then have not had a full run.
4. New failures, missing tests, or newly skipped previously passing tests
   require investigation. Resolve them, or stop and report to the user,
   **before step 1**. Added passing tests and fixed failures are welcome
   differences. Once clean, `gate0.jsonl` is the accepted baseline.
5. Save whole-repo `flutter analyze` output to
   `.git/refactor-evidence/finish/analyze-gate0.txt`. The scoped analyze
   baseline is already known: **2 infos** (`deprecated_member_use` in
   `home_source_editor.dart` and `lists_search_rail.dart`).

### CI (added in step 10)

`.github/workflows/build.yml` only runs on releases and manual
dispatch, so add a small `.github/workflows/checks.yml` for `pull_request` and
pushes. It runs `python3 dev/tool/check_search_architecture.py` and
`flutter analyze --no-fatal-infos lib/features lib/screens/search_screen.dart`.
Don't gate on whole-repo analyze yet, because of pre-existing issues outside this
migration. Adding the full test suite to CI is optional and a separate decision
(it takes about 6 minutes, with known historical failures).

### If a step is harder than expected

If a step turns out to be much more tightly coupled than expected, split it once
into two commits and continue. Do not stop to re-plan.

## Per-step procedure (keep it short)

1. `grep -n` the symbols for the area and read **only** those regions of the
   screen plus the signatures of the feature files they call.
2. Create the section file, move the code verbatim, and wire the construction and
   disposal points (rules above).
3. `dart format` the changed files, then run
   `flutter analyze lib/screens/search_screen.dart lib/features`. It takes about
   3 seconds and must still report exactly the 2 baseline infos.
4. Run the focused tests in **one** deduplicated `flutter test <files>` call:
   - the screen-level tests (`grep -rl "SearchScreen(" test`, 25 files) that
     exercise the moved area. Select them by grepping the test files for the
     area's widgets or behaviour, and include every one whose relevance is
     unclear.
   - the 5 source-text tests that read `search_screen.dart`:
     `test/home_expanded_card_settings_test.dart`,
     `test/collections_stage_regression_test.dart`,
     `test/features/home/home_mdblist_continuation_screen_test.dart`,
     `test/profiles/profile_source_guard_test.dart`,
     `test/theme/shape_manifest_test.dart`
   - the tests of any feature files the step edited (rule 7 adapters)

   Run a **whole feature folder** only when that feature's last step is done:
   `test/features/discover/` after step 1, `test/features/search/` after step 3
   and again after step 8 (which moves the search Spotlight sheet/board),
   `test/features/home/` (plus all 25 screen tests) after step 9. The three
   full-suite runs (step 0, gate 1, gate 2) stay as they are.
5. If a source-text test fails only because code moved, point it at the new file
   and keep **every** assertion. Never delete or loosen one.
   `shape_manifest_test.dart` is a ratchet over **listed files only**. The
   screen has 1 bare `BorderRadius.circular` and 1 `app.shape.br` call today.
   If rendering code moves into a new file, register that file:
   - in `kShapeResidue` with its bare-radius count if it contains `app.shape.`
   - in `kExtractedShapeResidue` if it does not

   Otherwise its radii go unguarded, and the ≥490 token-call floor can drop. If
   the screen ends up with no `app.shape.` call, move its entry to
   `kExtractedShapeResidue`. Counts may go down but never up.
6. Check the move is pure with `git diff --color-moved=zebra` (without
   `--stat`, which hides the colouring) and skim the non-moved lines. The only
   non-moved lines should be the allowed edits from the rules above.
7. Run `python3 dev/tool/check_search_architecture.py`. It scans `lib/features/`
   automatically and enforces the 800-line ceiling and import rules. Register a
   file in `EXTRACTED_ELSEWHERE` only if it lives outside `lib/features/`. Never
   add a `PRESENTATION_BRIDGE_IMPORTS` entry except under rule 7's
   declaration-only `show` route. The
   500-line section target is checked with `wc -l`.
8. Commit locally on `refactor/search-screen` using the evidence format below,
   and add one row to the progress table. Nothing else is written. **Never
   push** without the user's explicit OK.

**Evidence format:** the commit body gets three lines.

```
Moved: <area> → <files> (screen N → M lines)
Checks: analyze no new diagnostics; focused tests X passed; guard pass
Non-move edits: <list, or "none beyond setState/widget/context adaptation">
```

No receipts directory per step, no analyzer identity diff per step, and no
evidence-log appends. The step 0 baseline files are the only kept artifacts,
plus the two gate comparisons.

## Rules that keep this fast

- One agent, serial. All steps touch the same file, so no parallel agents.
- Do not read the old plan or evidence files, and do not reread this file's
  history. Read only the region being moved.
- The full suite takes about 6 minutes. Run it only at step 0, gate 1 and gate 2
  (always through `run_full.py` plus `compare.py`), or when a focused run fails
  for an unclear reason. Never run two at once. A stalled or partial run is not
  evidence: find the stuck test and rerun.
- A failing test is investigated immediately. If it predates this plan (it is in
  the step 0 baseline), move on.
- No new tests for moved code apart from the step 7b smoke test. The existing
  screen-level tests are the safety net: they pump `SearchScreen` in Home,
  Search (3 files) and Discover (3 files) modes and cover pagination for every
  layout. Apart from the 5 source-text tests, tests check only the state's identity
  (`tester.state(...)`, `same(...)`), never private members, so moving private
  code cannot break them.

## Carried over from the old plan: explicitly not done here

The old plan's completion criteria asked for more than this plan delivers. None
of this is dropped silently:

- **300-line facade:** replaced by the 800-line ceiling, by decision (see
  Definition of done). If you want 300, it's a separate follow-up.
- **Device, native and playback acceptance** (old phase 7: "verify actual playback
  entry/return and preview-to-player handoff on affected platform families"):
  **pending**. It's covered by the manual smoke checklist below, not by this
  plan's automated checks.
- **Performance comparison** (request counts, first-content timing, rebuilds,
  retained resources): **pending**. This plan changes no loading, layout or
  preview logic, so no new performance risk is expected, but nothing has been
  measured.
- **Legacy service boundary audits** noted in the old plan as "phase 8 must
  review": `lib/services/stremio_service.dart` (injected boundaries and pure
  selectors), `lib/services/iptv_source_search.dart` (injected/classification
  dependencies), the Sources copy-link path's transitive dependency on the legacy
  IPTV deferred-descriptor predicate and episode resolver
  (`features/sources/data/source_link_copier.dart`), and native playback/download
  internals' transitive dependencies. They're outside the screen and out of scope
  here. Track them as follow-ups.

## Progress

| Step | Commit | Screen lines | Notes |
| --- | --- | --- | --- |
| 0 | `5b632a61` docs, `c1aa91b9` guard fix | 9,964 | Accepted baseline `finish/gate0b.jsonl`: 10,262 pass / 22 fail / 29 err / 20 skip, same failure set as `165fd015`, no new skips. Only expected missing identity: `collections_stage_regression_test.dart::Widget _buildCanvasBoard uses collection artwork, shape and focus preview`, replaced by `_canvasCell` + Canvas-geometry guards in `c1aa91b9`. First run (`gate0`) found 8 stale source guards (fixed) + 1 flake (see Found, not fixed). Analyzer: `finish/analyze-gate0.txt`, 836 issues. Its only 2 "added" identities vs the original baseline are pre-existing deprecations relocated from `search_screen.dart`/`search_sources.dart`. |
| 1 | `99a2b30e` | 9,826 | Source/layout/focus/preview → `discover_section.dart`; priming/inventory → `discover_loading.dart`. Panel cross-feature wiring is a construction callback; binding/handoff lifecycle stays ordered for step 10. Scoped analyze: same 2 infos; 311 focused passes plus corrected source assertion (5 baseline failures/errors); Discover recheck 106 pass, final panel wiring 7 pass; guard passes. |
| 2 | `28b800d5` | 8,957 | Streaming/focus, dialogs/actions, selection, row/frame rendering, pure projections and completed-search return moved into Search presentation owners (all ≤384 lines). Same 2 analyzer infos; 215 focused passes and 5 step-0 failures/errors, no missing identities/new skips; final affected recheck 25 pass plus 2 baseline failures/errors; guard passes. |
| 3 | `7d8495f0` | 8,597 | Search mode/query/header/focus, Catalog search, Lists and title suggestion orchestration moved into Search presentation owners. Same 2 analyzer infos; whole Search feature + screen/source guards: 427 pass, 5 step-0 failures/errors, no missing identities/new skips; guard passes. |
| 4 | `:/refactor: move Home item and playback actions` | 8,079 | Item opening, detail menus, source editing and catalog playback/navigation moved into five Home presentation owners (48–228 lines). Tracking-policy label handoff uses the existing repository; Simkl/MDBList service calls remain composition callbacks with enum-only imports. Scoped analyze: same 2 infos; focused screen/source/adapter tests: 268 pass, 5 step-0 failures/errors, no missing identities/new skips; guard passes. |

## Found, not fixed

(Bugs or cleanups noticed during moves. Each needs a separate change after the
refactor merges.)

- `test/remote_reliable_transfer_test.dart::large binary file arrives intact with
  bounded progress blocks` is flaky under full-suite load: a temp `.part` file
  is still present when the test checks. It passes 3/3 in isolation, and no
  remote code changed after `165fd015`. Not related to this refactor; treat
  that single identity as flaky in gate comparisons.
- `test/theme/shape_manifest_test.dart::no swept file grows a new bare radius`
  is a historical failure (failing in the original baseline). Its failure
  message prints `${entry.key}` literally, so it never names the files.

## Manual smoke checklist (user, after gate 2, on real devices)

Phone and Android TV, with a profile that has Trakt/Simkl/MDBList connected
where possible:

1. Home opens, rows load, scroll to the bottom to trigger paging, then open a
   title and press Back: scroll position and focus are restored.
2. Switch each TV Home layout (Classic, Spotlight, Canvas, Promenade, Atrium,
   Mosaic, Deck, Tonight). DPAD through rails, hold Down, and check the hero
   trailer starts and stops.
3. Continue Watching: play, return, and check progress updates. Remove an item
   from the card menu.
4. Favorites: play a Debrify TV channel, a Stremio TV channel and an IPTV
   favourite. Open a playlist item and a watchlist item.
5. Search tab (TV): Catalog query, then Keyword query with sort, filter and
   providers, then Lists. Press Back from each.
6. Discover: switch sources and open a title.
7. Switch profiles while Home is loading. The other profile's rows must never
   appear.
8. If available, spot-check items 1, 2 and 5 on a desktop build (keyboard and
   mouse) and on Apple TV. tvOS and non-TV keep distinct loading behaviour
   (invariant 4).
