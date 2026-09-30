# Search screen refactor — follow-ups plan

Written 2026-09-30 on `refactor/search-screen` at `4fdb601a`, after the
[finish plan](search-screen-finish-plan.md) completed. It closes the items that
plan deliberately left open. Follow [AGENTS.md](../../AGENTS.md).

Unlike the finish plan, these steps change structure on purpose, and batches B and
C also change behaviour on purpose, so each has its own tests and a separate
commit. Behaviour that isn't named here must not change.

## Scope

| Batch | Item | Kind |
| --- | --- | --- |
| A | Two flaky tests: `remote_reliable_transfer_test` "large binary file…", `profile_setup_flow_test` "the Kid walk-through…" | test determinism |
| B | Older bugs moved unchanged: playlist and watchlist writes after a profile switch; borrowed `TmdbTitleSearch` disposed | bug fixes |
| C | P2s: detail-route liveness cancels in-flight tracker writes; nested preference-mutation deadlock against the WebDAV barrier | bug fixes |
| D | Board state written directly by 7 classes | structure |
| E | Search ↔ Home ↔ Discover import cycles; `HomeHeroShellBridge` catch-all | structure |
| F | Screen facade at most 300 lines | structure |
| G | Performance measurement: request counts, rebuilds and first-content steps, main vs branch | evidence |

## Batch A — flaky tests

Find the actual race in each test and fix it at its source: a product-side
ordering bug if there is one, otherwise the test's own waiting. Retries,
longer timeouts and skips are not allowed. Proof: run each test 30 times in a
loop under CPU load (`--concurrency` plus a parallel CPU burner) with 0
failures, where the pre-fix version fails at least once, or explain why the
race is proven absent.

## Batch B — older bugs

1. **Playlist writes** (`home_playlist_actions.dart`: favourite, clear progress,
   delete) and **watchlist removal** (`home_watchlist_actions.dart`) re-check that
   the originating profile is still current after the awaited dialog, before
   writing. Use the existing session-owner check (`profileCurrent`); don't add
   a new one.
2. **Borrowed `TmdbTitleSearch`**: the screen disposes it only when it created it
   (`widget.titleSearch == null`).

Tests: a profile switch while the dialog is open writes nothing to either
profile, and the normal path still writes. A borrowed title search survives the
screen being disposed.

## Batch C — P2s

1. **Detail-route liveness.** `detailRoute.isActive` gates only navigation
   (closing the route), snackbars and the post-action row refresh. It must not
   gate the tracker writes. Profile/owner currency (`catalogNavigationCurrent`)
   still gates writes. This matches `main`: users can back out of the detail page
   while tracker calls finish. After a completed write, the tracker rows refresh
   while the screen is mounted, as they did on `main`.
2. **Preference-mutation deadlock.** Make ordinary preference mutations
   re-entrant in `ProfilePreferences`. `_runOrdinaryMutation` marks its zone,
   and a nested ordinary mutation in that zone runs without re-waiting on the
   exclusive barrier and without double-counting active writers. It still bumps
   the mutation revision when it mutates. The exclusive barrier keeps its
   meaning: a snapshot waits for the outer writer, and therefore for everything
   nested inside it.

Tests: backing out mid-action still completes every tracker write; a
deterministic interleaving test starts the exclusive barrier between the outer
and inner registration and proves both complete (it hangs before the fix).

## Batch D — board state single owner

`HomeBoardSection` owns the board's display state: `loading`, `error`,
`pendingBoardReload`, `sections`, `homeLoadedAt`, `homeLastScroll`,
`progressiveHomeLoadPending`, `homePaginationDeferred`,
`classicAnchorTailPadding`, `boardAppliedAt` and `boardGen`. The fields become
private, with getters and named transitions (for example `markLoading`,
`markLoaded`, `markFailed`, `replaceRows`, `appendRows`, `requestReload`,
`consumeReload`). Other classes call the transitions at exactly the points where
they assign today, inside the same `setState` calls. No reordering.

## Batch E — acyclic features

Target: the feature import graph has **no cycles**. A cross-feature import may
only reach the other feature's `models/` or a small `*_contract.dart` file,
never another feature's `presentation/` implementation. Cross-feature wiring
lives at a composition boundary outside `lib/features`.

1. **Home consumes catalog search through a contract.** Home reads only
   `catalogSearching` / `catalogQuery` and triggers `runCatalogSearch`, so it
   declares `HomeCatalogSearchStatus` in its own models. The composition passes
   an adapter built from the search section.
2. **Composition layer.** Create `lib/screens/search_screen/` for files that must
   see more than one feature: the current cross-feature `*_composition.dart`
   files, the session lifecycle, and the shell registrations. It is the
   composition boundary. Register it in the architecture guard's measured set.
3. **Split `HomeHeroShellBridge`.** Keep hero relays in Home. Move Search,
   Discover and tab-shell registrations to per-feature shell registrations (or the
   composition layer when they are genuinely cross-feature).
4. **Remaining cross-feature presentation imports** go to a contract or the
   composition layer, whichever keeps the dependency narrow.
5. **Guard.** `check_search_architecture.py` fails on any cross-feature import
   of another feature's `presentation/` or `application/` code from inside
   `lib/features`, and on any cycle in the feature graph.

## Batch F — facade at most 300 lines

`search_screen.dart` keeps the widget, the `State` lifecycle callbacks and
`build`. The ordered construction and wiring now in `initState` (~520 lines)
moves into composition classes in `lib/screens/search_screen/`, one per feature
area plus one top-level composer that preserves construction order. `dispose`
delegates to the composer, which keeps the same teardown order. The four copies of
the profile-current check become one method.

## Batch G — performance measurement

Emulator and device runs stay out of scope (user constraint). Measure what is
deterministic on the host, on `main` (worktree) and on this branch, using the
same harness and fixed fixtures:

- **Network request count and order** for Home first load, one page of board
  paging, a catalog search, and a keyword search, via a counting `MockClient`.
- **Widget rebuild counts** for the screen's subtree during the same scenarios
  (`debugOnRebuildDirtyWidget`/build counters on the main shell widgets).
- **Frames to first content**: the number of `pump`s until the first row is
  visible.

Record the numbers here. Differences must be explained or fixed. On-device frame
timing stays pending and is listed in the manual checklist.

## Gates

- Every batch: format, scoped analyze (only the 2 baseline infos), the
  architecture guard, and focused tests.
- After A–D and after E–G: a full suite via `run_full.py` plus `compare.py`
  against `finish/gate2.jsonl` and the original baseline. Known flakes are fixed
  in batch A, so after A there are no allowed exceptions.
- End: `/code-review high` over this plan's commit range.

## Progress

| Batch | Commit | Result |
| --- | --- | --- |
