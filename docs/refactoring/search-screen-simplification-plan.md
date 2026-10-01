# Search screen refactor — simplification pass

Written 2026-10-01 on `refactor/search-screen` at `8edbdb9e`. The refactor and
its follow-ups optimised for zero regressions by moving code verbatim, which
left it more fragmented and callback-heavy than a clean design. This pass
simplifies structure **without changing behaviour**. Follow
[AGENTS.md](../../AGENTS.md).

Measured starting point (599 files, 57,467 lines under `lib/features` and
`lib/screens/search_screen`): 181 files under 40 lines, 67 provider-only
`*_dependencies.dart` files, 90 deps records (14 with more than 12 fields),
12 classes taking more than 8 collaborators, 1,235 `Function()` occurrences,
279 one-line forwarding getters, and 5 files over 500 lines.

## Batches

| # | Change | Rule |
| --- | --- | --- |
| 1 | **Consolidate provider files.** Merge provider-only `*_dependencies.dart` files into one `<area>_providers.dart` per cohesive area (Search, Sources, Discover; Home by sub-area: board, continuation, saved content, hero, detail/playback). | No giant registration file; each result stays under 300 lines where practical. Provider declarations, names and dependencies are unchanged. |
| 2 | **Remove dead and needless indirection.** Delete forwarding getters and members nothing uses; inline `() => x` closures and pass-throughs where the value is already built and never changes. | Keep closures that defer construction order or read live state. |
| 3 | **Split the five files over 500 lines** along their real seams. | Moves only. |
| 4 | **Narrow wide dependencies.** For deps records with more than 12 fields and classes with more than 8 collaborators, group related callbacks into small role contracts or pass the owning collaborator, so each class states what it needs by role. | Contracts live with the consumer; no behaviour change; no grab-bag "context" objects. |

Every batch: format, scoped analyze (2 baseline infos), architecture guard,
focused tests compared with `finish/followups-gate.jsonl`. At the end: a full
suite via `run_full.py` plus `compare.py`, then review iterations until clean,
then push to `private`.

## Progress

| Batch | Commit | Result |
| --- | --- | --- |
