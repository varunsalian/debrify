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
| 1 | `9f98a9f6` | 67 provider-only files → 10 area files (Home split six ways, each under 300 lines); declaration counts verified per area. `keyword_providers.dart` is the torrent-provider policy, not DI, and stays. Guard: 667 → 610 measured files. |
| 2 | `40f3353a` | 9 dead forwarding getters removed. No other unreferenced public members. The `() => x` closures are forward references into the composition's late-field graph or reads of live state, not needless; the remaining getters are used and keep callers out of section internals. The earlier "1,235 `Function()`" count is mostly these legitimate callbacks. |
| 3 | `0a99b198` | Stremio TV picker 780 → 617, hero spotlight 776 → 675, catalog card 558 → 487 (builders, so the widget tree is unchanged). Reviewed and kept: Sources screen 678 (a subscription coordinator; rendering already extracted) and the playback resolver 513 (`label` and `resolve` share all five collaborators). Follow-up: `resolve()` is one 350-line method; splitting it changes control flow and needs its own change. |
| 4 | `4b6532db` | `HomeClassicGeometry` extracted from `HomeClassicSection` (sizing only depends on display prefs). `HomeCatalogItemActions` replaces the open, quick-play, See-All, source-tag, bound and PikPak-only callbacks, which were wired identically in five places (Classic, stage cells and cards, Tonight, Spotlight rows, Spotlight results). Classic deps 14 → 9, stage cells 4, Spotlight rows 4. The earlier ">12-field" count included named parameters inside function types; by top-level fields, 10 records exceed 12, mostly composition-layer wiring. |
| Gate | `finish/simplify-gate.jsonl` | 10,286 pass / 22 fail / 29 err / 20 skip: the same failure set as the follow-ups gate, with no missing tests or new skips (7 added). |

## Review iterations

**Iteration 1** (`9f98a9f6^..4b6532db`): no correctness bugs; provider
declarations verified identical. Fixed:
- one `HomeCatalogItemActionsAdapter` and one `HomeClassicGeometry`, built
  once in the board presentation composition. Consumers take the values
  directly (stages, workflow, rendering) or read `board().geometry` instead of
  reaching through `HomeClassicSection`.
- extracted builders became small widgets (`HomeHeroIdentity`,
  `HomeCardHoldLayer`, `HomeCardPlaceholder`, `StremioTvCatalogCreateView`,
  `StremioTvCatalogActionTile`). The catalog card's mixed "parts" file was split into
  card layers and `home_poster_flight.dart` (a Hero shuttle callback, so it
  stays a function).
- shape-manifest entries for the new files.
- `keyword_providers.dart` → `keyword_provider_selection.dart` (the torrent
  provider policy, not DI), and 29 `*_dependencies_test.dart` →
  `*_providers_test.dart` to match the merged provider files (test ids
  renamed accordingly).

Declined, with rationale:
- `classicCatalogRowExtent` measures the title with the screen context and
  the card with the passed one. This moved verbatim; making it consistent
  could change row extents, so it is a separate fix (below).
- `StremioTvCatalogCreateView` takes the dialog's focus nodes and key
  handlers explicitly: they are its focus protocol. Hiding them would move
  that protocol, not remove it.
- `search-screen-plan.md` is frozen history and still names files that no
  longer exist; its header points to the current plans.

**Iteration 1 fixes:** `1d16efc2`. Checks: scoped analyze unchanged, 2,738
affected tests with no new failures, guard and format clean.

**Iteration 2** (reviewed `1d16efc2`, fixed in `1cc97a28`): no bugs. Removed
now-dead dependency fields (rendering `navigation`/`badges`, stages
`badges`) and the unused `rendering.classic`. The picker's
`ValueKey('create')` is back on the `AnimatedSwitcher` child (no runtime
change; the two children already differed in type). One import was moved
below the package import; the files' relative imports were never sorted, and
this pass does not sort them. Checks: scoped analyze unchanged, 1,613
affected Home/Stremio TV/screen tests with no new failures, guard and format
clean. The mixed-context row extent stays a recorded pre-existing issue.

**Iteration 3** (reviewed `1cc97a28`, fixed in `b66866b2`): no bugs.
`createHomeRendering` returns `HomeBoardRendering` directly (no one-field
record, no `rendering.rendering`), with plain finals instead of needless
`late` fields. `HomeClassicSection`'s geometry and row/footer/status builders
are private now that nothing outside reaches it, and its doc no longer
claims row geometry. Checks: scoped analyze unchanged, 1,594 Home and
screen tests with no new failures, guard and format clean.

**Iteration 4** (reviewed `b66866b2`, fixed in `f5e97cfd`): no bugs. `stages` and `rendering` are plain finals (only `workflow` is
read before it is assigned), and a stale doc reference was corrected.
Declined: the per-build layouts map and Classic's positional wiring predate
this pass (behaviour-neutral polish for a later change); the constant footer
and import grouping are cosmetic, and this pass does not sort imports.
Four rounds found no correctness issues and shrinking findings, so review
stopped here.

## Final gate

`finish/simplify-final.jsonl` at `f5e97cfd`: 10,286 pass / 22 fail / 29 err /
20 skip, the same failure set as `simplify-gate.jsonl`, no new failures or
skips. The 98 "missing" identities are exactly the renamed provider test
files (`*_dependencies_test.dart` → `*_providers_test.dart`,
`keyword_providers_test.dart` → `keyword_provider_selection_test.dart`); each
one is present under its new path with an identical outcome. Scoped analyze
unchanged, guard passes (617 files), formatting clean.

## Found, not fixed

- `HomeClassicGeometry.classicCatalogRowExtent` mixes the screen context
  (title style) with the caller's context (card height). Behaviour is
  unchanged from before the refactor.
- `HomeCatalogPlaybackResolver.resolve()` is a single ~350-line method.

