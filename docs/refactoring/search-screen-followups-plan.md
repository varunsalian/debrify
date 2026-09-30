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

1. **Detail-route liveness.** `detailRoute.isActive` gates only *starting* an
   action from the page and closing the route (`closeIfCurrent`). It must not
   gate the tracker writes, the row refresh or the result feedback; those use
   profile/owner currency (`catalogNavigationCurrent`). This matches `main`:
   users can back out of the detail page while tracker calls finish, and the
   rows refresh and feedback shows on the board afterwards.
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
| A | `7fec21b2` | Remote transfer: the sender sees `complete` before the receiver deletes `.part`; the test now settles the receiver (`close()`) before checking. Reproduced 3/20 under CPU load before, 0/30 after. Kid walk-through: a fixed 10-window pump budget raced the real SQLite create chain; the test now pumps until the row exists (same fix for "divergence"). Not reproducible locally even with 12 parallel copies, so this fix follows from reading the code; the gate 1 stack matched this race. |
| B | `45c7bd47` | Playlist favourite/clear/delete and watchlist removal check `profileCurrent` after their prompt. The profile-switch tests fail without the guard; same-profile paths still write. A borrowed `TmdbTitleSearch` is no longer disposed by the screen. |
| C1 | `99fbbaf0` | `HomeDetailActionBridge.canStart` (live page) admits actions; tracker writes, row refresh and feedback use `catalogNavigationCurrent`. The detail route screen test now asserts the write survives back-out and reports on the board (6 test ids renamed "…retires feedback" → "…survives back-out"). |
| C2 | `da583a92` | Ordinary preference mutations are re-entrant inside an open zone frame; frames close when the outer writer ends. The deterministic interleaving test timed out before the fix and passes after; tests for nested-revision and inherited-zone behaviour were added. |
| D | `5abeac90` | 12 board display fields private with named transitions called at the same points inside the same `setState`s; external writes no longer compile. |
| E | `1b2cbd4d` | Features acyclic: cross-feature imports only to `models/`; 25+ wiring files in `lib/screens/search_screen/`; contracts `HomeCatalogSearchStatus`, `HomeScreenControls`, `HomeLocalSourcePicker`; shared widgets in `lib/ui/core`; `HomeHeroShellBridge` split. Guard enforces both rules (verified it fails on a planted violation). |
| F | `46ae8213` | `search_screen.dart` 800 → **131** lines; `SearchScreenComposer` (291) plus search (119), home (276) and session (123) factories; one `profileCurrent()`; guard enforces the 300-line facade. |
| Gate | `finish/followups-gate.jsonl` | 10,279 pass / 22 fail / 29 err / 20 skip: the same failure set as gate 2 and the original baseline, with no new failures or skips. The only missing identities are the intentional renames (6 detail-route ids from C1, plus the Canvas guard from step 0). Both former flakes passed. Whole-repo analyzer identical to `analyze-gate0.txt`. |
| G | (this commit) | Probe `dev/perf/search_screen_perf_probe_test.dart`, 3 runs each on `main` (`9619c10b`, the only change being no `ProviderScope`, since `main` has no Riverpod) and the branch. Results below. |

### Performance measurement (batch G)

Host-side, fixed fixtures (1 addon, 12 catalogs × 10 titles), classic layout,
TV and phone. Requests: counting mock client. Rebuilds: Flutter's
`debugOnRebuildDirtyWidget`. First content: 100 ms pumps until the first card
is present.

| Scenario | Requests main / branch | Rebuilds main / branch | First content (pumps) |
| --- | --- | --- | --- |
| Home first load, TV | 14 / 14 | 2,521 / 2,572 | 1 / 1 |
| Home paging, TV | 19–20 / 19 | 13,990 / 14,275 | — |
| Catalog search, TV | 12 / 12 | 1,595 / 1,599 | 1 / 1 |
| Home first load, phone | 9 / 9 | 3,022 / 3,074 | 1 / 1 |
| Home paging, phone | 3–4 / 3–4 | 5,474 / 5,579 | — |
| Catalog search, phone | 12 / 12 | 2,833 / 2,880 | 1 / 1 |

- **Requests:** same count, same order. The first request of each load is
  a random catalog picked for the automatic hero source on both revisions
  (for example `row8`, `row11`, `row2`); the board then requests `row0`–`row7` in
  the same order. Paging counts vary by one run to run on both revisions
  (real-IO timing).
- **Rebuilds:** +1–2%, explained by a per-type histogram (TV first load, +51).
  The refactor split `_StremioCard` into `HomeCatalogCard` plus a separate
  `HomeCardMetadataView` element: 80 whole-card rebuilds became 41 card plus 82
  metadata-view rebuilds, so metadata arrival now rebuilds only the small
  metadata view (+43 elements, less work per rebuild). `ProviderScope`
  contributes +7; renamed widgets (`_BoardCell` → `HomeBoardCell`, the hero
  layers, the entrance reveal) cancel out exactly. No unexplained growth.
- **Not measured here:** keyword search (needs real torrent engines) and
  on-device frame timing. Both stay in the manual device checklist.

## Final review (`/code-review high` over `c60f6229^..5f620df6`)

Fixed:
- **Post-await prompts after back-out:** `handleTraktMenuAction` gained
  `canPrompt`; the list picker (which appears after lists load) now also needs
  the detail page to be live. Writes and feedback still follow view/profile
  currency. Test: `trakt_list_picker_prompt_test.dart`.
- **Nested preference write outliving its writer:** nested ordinary mutations
  now register as active (they skip only the barrier wait), so an unawaited
  nested write holds a snapshot off until it finishes. The test fails on the
  previous version.
- **Guard gap:** files in `lib/screens/search_screen/` are checked as
  presentation, except the composition root (composer and three factories),
  which may import `lib/services/` directly. The rule covers `lib/services/`
  and platform packages, as it does for feature presentation; presentation
  reading its own feature's data adapters through providers stays an existing
  allowed pattern. A feature importing the facade is flagged, missing roots
  fail the guard, and tab-shell registration's `main_page_bridge` import is
  pinned with `show MainPageBridge`.
- **`titleSearch` ownership** is recorded when it is resolved.
- **Catalog search status strip** is back in Home (its only users).
- **Screen-controls adapter** takes its sections directly.
- **Probe wording:** its numbers are compared across runs, not claimed
  deterministic.

Accepted, with rationale:
- **Composer fields shared by the three factories:** the composer is the
  screen's composition root. Its groups reference each other lazily in
  cycles (search needs board, board needs search), which `late` fields on one
  root express. Only composition code in this folder can reach them.
- **`homeSourcesNavigationProvider` in the composition folder:** it binds Home
  to the Sources screen, so it belongs to neither feature; Home receives it
  through its dependencies.
- **Rejected saved-content writes are silent:** consistent with every other
  owner/profile guard in these features; a rejection only happens while the
  screen's profile session is being replaced.

Second review (`cbbc4e94`):
- The picker test now goes through `handleTraktMenuAction` with `canPrompt`,
  and the detail route screen test proves the detail-page wiring. Both fail
  when their piece is removed.
- `canPrompt` doc corrected: it also stops the picker's list fetch, which
  exists only to show that prompt.
- Accepted: Simkl and MDBList take no `canPrompt` today because they have no
  prompt that appears after an await. If one is added, it should follow the
  Trakt pattern.

