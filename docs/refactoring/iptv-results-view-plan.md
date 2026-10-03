# IPTV results view refactor — plan

Written 2026-10-03 on `refactor/codebase` at `d93428fb`; revised after Codex
review round 1. Follow [AGENTS.md](../../AGENTS.md). This page plus AGENTS.md
is everything the executing agent needs.

Work on the existing `refactor/codebase` branch. Commit after every step. Never
push to `origin`; push to `private` only if the goal says so. Gate commits must
contain `gate` in their message (AGENTS.md: CI's behaviour job runs on
`refactor/**` pushes only for `gate`/`[full-ci]` commits).

## Goal

`lib/widgets/iptv/iptv_results_view.dart` is 9,084 lines: the whole IPTV
browsing surface.
- **What it covers:**
  - catalog loading and maintenance, and the SQL catalog;
  - guide (EPG) context, filters and categories, favorites and lists;
  - playback, catch-up, the startup channel and recordings;
  - the player's in-player browse payload and the live preview;
  - four layouts: classic, TV two-pane, cockpit stage and Spotlight.
- **The split:** it moves into a new feature, `lib/features/iptv/`, **moving
  code verbatim**.
- **Unchanged:** the widget tree, keys, focus nodes, build order, and the
  State's `initState`/`dispose` order.
- **Stays in `iptv_results_view.dart`:** the public `IptvResultsView` widget
  and `IptvResultsViewState`. Its public members keep their signatures
  (implementations retained, or forwarders verified by the checker), and its
  lifecycle methods stay **verbatim** (see Technique 2).

**Architectural status:** this is a bounded legacy-extraction stage, like the
settings refactor. Its temporary exceptions, each recorded in Progress with an
exit milestone, are:
- State-driven sections wired by the State, instead of Riverpod (exit:
  migrate the browse state to Riverpod);
- a `legacy_iptv/` bridge whose code calls services directly (exit: move
  those calls behind IPTV data contracts, then dissolve the folder);
- unchanged legacy user-facing text (exit: the localization migration).

## Public surface to preserve (at `d93428fb`)

Step 0 re-derives this list from the code; it is authoritative over this
table. Every member keeps its exact signature on `IptvResultsViewState` or
`IptvResultsView`.

| Kind | Members | Known callers |
| --- | --- | --- |
| Static constants and getters | `tabletTwoPaneMinWidth`, `tabletTwoPaneMinHeight`, `chipRankNone`, `chipRankGuide`, `chipRankMaintenance`, `chipRankRefresh` | tests |
| Static methods | `shouldUseTouchTabletTwoPane`, `applyStoredLocalCategoryOrder`, `formatLoadBytes`, `formatLoadElapsed`, `loadBytesLabel`, `chipClaimAllowed`, `landingCategoryFor` | `test/iptv_load_status_test.dart:54,113`, `test/iptv_tablet_selector_test.dart:17`, `test/iptv_category_order_page_test.dart:358`, `test/iptv_catalog_db_test.dart:1522` |
| Instance API and interfaces | `focusFirstFilter`, `focusSearchResults`, `refreshPlaylists`, plus the `BrowseResultsFocusController` and `BrowseSearchResultsFocusController` methods | `main.dart:3276` (untyped `GlobalKey`), `browse_screen.dart:110,145` |
| Mixin | `WidgetsBindingObserver` (`didChangeAppLifecycleState`) | framework |

Live dispatch through the untyped `GlobalKey` and both interfaces must keep
working unchanged.

## What it contains (line numbers at `d93428fb`; step 0 re-derives them)

The **step 0 declaration manifest is authoritative**. These ranges are
orientation only: 23 of the State's 113 fields are declared after line 665,
for example `_searchDebounce` (1113), `_catalogPresentationJobs` (2068), the
player episode state (3407), `_previewRearmPending` (4834), the recording
state (4984) and `_pointerInStage` (7393).

| Lines | Area | Step |
| --- | --- | --- |
| 1–131 | Imports; `_TabletChannelIdentity`, `_railResExp`, enums `_CatalogChipState`/`_ChipOwner`; `IptvResultsView` | 1 (`_railResExp` and the enums with their consumers) |
| 132–665 | Most State fields; per-channel focus nodes (`_focusNodeFor`, `_rowAttached`, `_onRowDetached`); schedule pane; `_scheduleActionFor` (623) | 2 for fields; schedule actions in 5 |
| 666–1164 | `initState`/`didUpdateWidget`/`dispose` (**stay in the State, verbatim**); listener callbacks; favorites and membership (`_loadFavorites` 748, `_toggleFavorite` 806, `_openListPicker` 854, `_promptCreateList`, `_refreshVisibleListShelf`); settings loading (`_loadSettings(Inner)` 932–1093) | 3 (favorites, settings loading) |
| 1165–2431 | Catalog loading and maintenance, SQL catalog, revalidation, `_applyDbCatalogRefresh`, `_fetchCatalogFromNetwork` | 3 |
| 2432–2651 | Load status and chip (public statics here stay on the State as forwarders) | 3 |
| 2652–3410 | Guide context (`_updateEpgContext`), progressive batches, results, filters, playlist/content/category handlers, category options and hide | 4 |
| 3411–3924 | Player browse payload (`_providePlayerIptvBrowse` and friends) | 4 |
| 3925–4836 | Play, startup channel, catch-up, `_playChannelInner`, series detail, continue actions, after-playback refresh | 5 |
| 4837–5319 | `didChangeAppLifecycleState` (**stays in the State**), sidebar focus, recording support, source counts (`_recomputeSourceCounts` 4906), recordings | 5 |
| 5320–5413 | Navigation; the focus-interface methods (**stay in the State** as entry points; their bodies may forward) | 5 |
| 5414–8209 | `build` (signature stays; body moves only under the approved step-7 exception) and every layout: Spotlight, classic, TV two-pane, cockpit stage, quiet filters, focus and preview tuning, preview rail and stage, `_buildContent`, tablet selector | 6 |
| 8210–9084 | Private widgets and painters | 1 |

## Contracts that must not change

Each has the coverage given in the step 0 testability matrix below.

1. **Preview layering.** The native preview plane renders under Flutter.
   - **Permitted over the preview rect:** only the layers that are there
     today. That's the intentional stage floor and the status chip, in their
     documented order (7664, 7722).
   - **Not permitted:** no new background, decoration, opacity wrapper or
     reordering anywhere in the preview subtree.
2. **Landing-category seed rules.**
   - `_selectedCategory == null` means both "All" and "not picked yet";
     `_categoryManuallyChosen` tells them apart.
   - `_landingSeedArmed` is armed in `_loadPlaylistInner` (1252) and disarmed
     at both present sites (1553, 1655), even when the seed declines.
   - Revalidation re-presents never seed.
3. **Catalog refresh focus behaviour**, as it exists today. There are two
   paths:
   - **Unchanged digest and no numbering added** (`!numberingAdded`, 2166):
     existing facades are re-pinned, and instances and focus are retained.
     Exception: if the selected category disappeared, that branch still calls
     `_applyFilters` (2185, 2197), which replaces the filtered facade (3006).
   - **Numbering newly adopted:** the digest-unchanged branch doesn't apply.
   - **Changed digest:** it captures the old index, then tries the clamped
     same index, then any attached row, then the filter node (2258).
   - **Both paths** return early when `!mounted`. New generations clear the
     instance cache (1733).
   - It does **not** look up the surviving channel at a new position. Adding
     that would be a separate behaviour change.
4. **Playback identity.**
   - **Resident instances first:** lookup before launch-window selection
     uses the catalog's resident instances (4151), and the launch window is
     materialized from SQL (4489, 4507). A facade is never handed to the
     launcher.
   - **Unchanged copies:** catch-up builds a replay channel for the launcher
     (4376, 4401), and playback makes origin-enriched copies (3466, 4535). Both
     stay exactly as they are.
5. **Catalog safety.**
   - Empty parses are never ingested.
   - Load and refresh tickets reject stale results (1305, 1369, 2416, and
     the other `_loadTicket` checks).
   - Hidden categories are keyed by group name.
6. **D-pad behaviour.**
   - Rows play on an OK key-up whose key-down they saw (`_sawSelectDown` in
     `iptv_channel_row.dart`, which doesn't move). The row wiring here
     (callbacks, focus nodes, `_rowAttached`/`_onRowDetached`) stays exactly
     the same.
   - Guide keys are consumed.
   - The TV sidebar listener, the focus-interface entry points and
     `_consumeContentFocusRequest` keep their order.
   - The rail's expanded panel stays opaque.
7. **Startup channel:** the same trigger (after `_loadSettings` succeeds),
   resolution order, focus, failure handling and cancellation.
8. **Player browse payload:** byte-identical maps and key order across the
   browse, zap-page, channel-number and episode branches (3576, 3688, 3733).
9. **Lifecycle:** `initState`, `didUpdateWidget`, `dispose` and
   `didChangeAppLifecycleState` stay **verbatim in the State**, statement for
   statement and in order. The only allowed change is the receiver qualifier
   on a moved field (for example `_searchDebounce?.cancel()` →
   `_filters.searchDebounce?.cancel()`).
   - **The post-frame cleanup** of outgoing card focus nodes (1280) stays
     unconditional. Never add an early return there.
   - **Child-owned resources** in the private widgets (8241, 8442, 8656) keep
     their owners.
10. **Performance:**
    - no new work in `build`, no new rebuild scopes, no extra catalog
      queries;
    - read locations and lazy callbacks stay where they are (1714, 496, 6938);
    - the known slow first open must not get worse.

## Destination layout

`lib/features/iptv/` (a new feature):
- **`application/`:** pure helpers with no services and no context:
  `formatLoadBytes`, `formatLoadElapsed`, `loadBytesLabel`,
  `chipClaimAllowed`, the `chipRank*` values,
  `shouldUseTouchTabletTwoPane`, `_railResExp` and its parsing. The State
  keeps public forwarders with identical signatures, including static getters
  and constants.
- **`presentation/legacy_iptv/`:** a named bridge, with its exact path in the
  guard. It holds:
  - the state owners;
  - `landingCategoryFor`, whose original implementation reads
    `IptvCatalogDb.defaultCategory` despite its legacy "Pure decision" comment;
  - every section that takes a `BuildContext` or calls services;
  - the layout builders;
  - **the private widgets that use services:** `_IptvStageFloor` and
    `_IptvRailInfo` (`DebrifyImageCache.iptvLogos`), and
    `_IptvFocusStageInfo` (the image cache and `IptvEpgService.isEpgCapable`,
    8480, 8818, 8886, 8961). The step 0 report checks every private widget's
    imports.
- **`presentation/`, outside the bridge:** only private widgets and painters
  with no service imports, made public with an optional `super.key` (the
  settings precedent).
- **The facade** (`lib/widgets/iptv/iptv_results_view.dart`) is registered in
  `check_search_architecture.py` as an **exact composition root**, like the
  earlier facades: it isn't import-checked, but it is size-capped (400 at the
  end) and `TEMP(iptv)`-checked. Extracted code must **never import the
  facade**; a guard rule enforces this.

Each destination file is at most **500 lines**.

## Technique

The settings-screen approach (`docs/refactoring/settings-screen-plan.md`,
Technique), with these IPTV rules:

1. **Sections** are plain presentation classes the State constructs, living
   exactly as long as it does. They take narrow deps records:
   - `setState`, `mounted` and `context` as callbacks;
   - live getters for widget values (`() => widget.searchQuery`,
     `() => widget.isTelevision`, ...). Never pass the facade's concrete
     widget type into extracted code;
   - deferred calls into members that haven't moved yet.
2. **The lifecycle stays verbatim in the State** (contract 9). Fields and
   resources may move into owners, but `initState`, `didUpdateWidget`,
   `dispose` and `didChangeAppLifecycleState` keep their bodies. The only
   change is the receiver qualifier, so teardown interleaving can't change. No
   owner gets a combined `dispose()`.
3. **State owners by concern,** as the dependency report decides:
   - one owner per field, with the same initializer;
   - a field written by several sections goes through its single owner;
   - collections and notifiers keep their identity: the same instance is
     cleared, refilled and listened to, never replaced. For example,
     `_dbInstanceCache.clear()` (1258) and
     `_androidRecordingsByUrl..clear()..addAll()` (5005).
4. **`mounted` and `context`:** the settings rule, verbatim.
   - **Guards stay put:** keep every `mounted` guard at its original position.
   - **Fetching `context`:** do it only at the original first use, or right
     after the original passing guard.
   - **Builder and dialog contexts are untouched.** The checker's
     builder-context rule enforces this.
   - **Pre-approved patterns** (record each one): a `context.mounted` check
     right after an existing `_deps.mounted()` guard and `_deps.context()`
     with no `await` between; and braces on a formatter-split `if` body.
5. **Allowed edits:**
   - qualifiers and receivers;
   - deps wiring;
   - imports;
   - dropping `_` where another file needs a symbol;
   - optional `super.key` on widgets made public;
   - removing `@visibleForTesting` from production-called implementations
     that move into another library (the facade copy keeps it);
   - the two named test seams below;
   - **Approved 2026-10-03:** the exact `root_build_forwarder` exception
     recorded in the manifest and Progress: move the original `build` body
     into plain `IptvRootLayout`, remove only its `@override`, and retain the
     State's exact annotated signature as a single forwarding expression.

   Any other edit needs approval and is recorded in the manifest.
6. **Named test seams.** These are the only production additions; each is
   recorded and exactly verified.
   - **A registered test accessor,** like settings' `settingsScreenTestAccess`,
     that exposes the private payload provider and other unreachable
     internals as real tear-offs for characterization tests.
   - **An optional clock** (`DateTime Function()`, defaulting to
     `DateTime.now`) for every Spotlight paint path that reads the time:
     - the timeline constructor parameter the view will forward
       (6534; `spotlight_live_timeline.dart:276`);
     - the timeline's direct `DateTime.now()` reads for programme styling,
       the playhead and the "Today" heading
       (`spotlight_live_timeline.dart:1863, 2034, 2108`);
     - the hero metadata (`spotlight_programme_hero.dart:173`).

     Each read becomes `now()` with the same default, so production behaviour
     is unchanged. These two files are touched only for this seam. Step 0
     lists every remaining `DateTime.now` reached by a golden; any it can't
     cover must be avoided by the fixture, with the limit recorded.
7. **Not allowed:**
   - reordering `await`s, guards, `setState` contents, timer starts or
     cancels, or listener adds and removes;
   - changing a widget, key, `FocusNode`, decoration or the build order;
   - merging look-alike helpers;
   - changing user-facing text;
   - suppressing a lint.
8. **Temporary cross-calls** (`TEMP(iptv)`) are allowed only from
   `legacy_iptv/` files, each with its planned final destination. None may
   remain at the end.

## Staged enforcement

- **From step 1:**
  - **Guard:** register `lib/features/iptv/` (with the exact `legacy_iptv/`
    bridge path and the no-facade-import rule); destination caps are checked.
  - **CI** already formats and analyzes all of `lib/features`.
  - **The size ratchet** runs `check_file_sizes.py --update` at every step
    commit to lock in the facade's shrinkage.
- **Until step 7,** the facade is held only by the shrinking ratchet, and
  isn't in CI's format scope.
- **At step 7:** format the facade, register it as the exact composition root
  with its 400-line cap, add it to CI's format and analyze scope, and turn on
  `TEMP(iptv)` rejection.

## Steps

| # | Work | Notes |
| --- | --- | --- |
| 0 | Baseline, dependency report, manifest, checker extension, test seams, characterization tests and their baseline, source-text inventory, CI test list | Nothing moves. |
| 1 | Guard registration. Private widgets and painters (service-dependent ones into `legacy_iptv/`) with `_railResExp` and the enums; pure helpers into `application/` with State forwarders | |
| 2 | State and resource owners (every field); the lifecycle stays verbatim with qualified receivers | The lifecycle tests and source guards must pass. |
| 3 | Settings loading, favorites and membership, catalog loading and maintenance, load status and chip | Contracts 2, 3 and 5. **Full-suite gate 1.** |
| 4 | Guide context, results, filters, categories; player browse payload | Contracts 2 and 8. |
| 5 | Play, startup channel, catch-up, after-playback refresh, recordings, schedule actions, source counts, navigation (the interface entry points stay in the State) | Contracts 4 and 7. |
| 6 | Layouts: Spotlight, classic, TV two-pane, cockpit stage, quiet filters, focus and preview tuning, preview rail and stage, `_buildContent`, tablet selector | Contracts 1, 6 and 10. |
| 7 | Final State, guards, CI. **Full-suite gate 2.** | See "Definition of done". |

### Step 0

1. **Baseline at `d93428fb`:**
   - `python3 dev/tool/suite_evidence.py run iptv/base`;
   - `flutter analyze > <E>/iptv/analyze-base.txt`, where `<E>` is
     `$(git rev-parse --git-common-dir)/refactor-evidence`;
   - the SDK must be Flutter 3.44.8.
2. **Dependency report** (`docs/refactoring/iptv-results-view-deps.md`). For
   every top-level declaration, State member and private-widget member, it
   records:
   - destination, step and layer;
   - reads and writes, **including in-place collection and notifier
     mutations, aliases and borrowed resources** (the parser only sees direct
     assignments, so record these by hand and verify them);
   - cross-section calls, tear-offs, deferred closures, timers and listeners;
   - each temporary cross-call's final destination;
   - the contract it touches;
   - the full public surface (above).

   Nothing may be unresolved.
3. **Checker: make `check_settings_moves.py` manifest-driven** instead of
   forking it.
   - **Per-manifest config file:** add one (for example
     `dev/tool/iptv_checker_config.json`, with the settings values moved into
     `settings_checker_config.json`) for:
     - baseline, source and feature;
     - receivers and live getters;
     - sidecar data files;
     - exact transformations and annotation exceptions;
     - forwarder rules, including a moved implementation plus its retained
       facade forwarder (today's duplicate-owner rejection at 810 must allow
       exactly this, verified);
     - lifecycle rules: verbatim with receiver-only qualification;
     - test accessors and seams.
   - **Running it:** `check_verbatim_moves.py --manifest dev/tool/iptv_manifest.tsv`
     defaults everything and enables every mode.
   - **Settings unaffected:** its run and self-tests still pass unchanged.
   - **New IPTV fixtures, positive and negative**, covering:
     - static method and getter forwarders;
     - interleaved disposal (a reordered cancel must fail);
     - live widget reads;
     - builder/dialog context substitution;
     - duplicate ownership;
     - wrong callback wiring;
     - a lifecycle statement moved out of the State.
4. **Test seams.** Add the registered test accessor and the optional clock
   (Technique 6).
   - **Size ratchet:** the facade is exactly at its recorded limit
     (`file_size_baseline.txt:6`: 9,084), and `--update` only lowers limits.
     So the seam commit raises that one entry **by hand** by exactly the
     measured seam lines, using the documented manual mechanism
     (`check_file_sizes.py:11`). Record the scope (seam only) and its exit:
     step 1's moves bring the file well under 9,084, and `--update` locks
     that in.
   - **Second baseline** (`iptv/base2`), recorded with the seams in place.
   - **Compare it** with `iptv/base` (same SDK). `PASS` is required: no new
     failures, missing tests or new skips.
5. **Characterization tests,** per this matrix:

   | Contract | Coverage |
   | --- | --- |
   | 1 Preview layering | Layout goldens of all four layouts, preview disabled, fixed clock, real temporary SQL catalog. **Source guards** on the preview subtree's widget order and decorations. Native punch-through: **pending device verification**. |
   | 2 Landing seed | Widget tests through stored local M3U or a temporary SQL catalog: seed on first present; no seed after a manual pick; no seed on a revalidation triggered through `IptvCatalogRefreshService.instance.revision`. Source guards on the arm and disarm sites (1252, 1553, 1655). |
   | 3 Focus repair | A real temporary SQL catalog plus revision notification. Unchanged digest without numbering: instance and focus retained. Unchanged digest with the selected category gone: `_applyFilters` replaces the facade (existing behaviour). Numbering newly adopted: the changed path. Changed digest: same-index repair, attached-row fallback, focus elsewhere left alone. Source guards for branches the fixture can't reach. |
   | 4 Playback identity | Source guards on resident-instance lookup, SQL window materialization and launcher arguments (4151, 4489, 4507), plus the catch-up and origin-copy paths. Launch itself: **source plus pending device verification** (no injectable launcher). |
   | 5 Catalog safety | Reuse the service and DB tests. A view refresh with real SQL, where a stale ticket's result is dropped. Source guards on ticket checks not drivable from a test. |
   | 6 D-pad | Widget tests for row key handling and both Browse focus handoffs (extend `iptv_channel_row_key_test.dart` and `iptv_spotlight_results_view_test.dart`). Goldens don't cover key handling. |
   | 7 Startup | Resolution, focus and pre-launch cancellation through the existing hook (`iptv_spotlight_results_view_test.dart:1048`). Native launch, return and preview suppression: **source plus pending device verification**. |
   | 8 Payload | Through the test accessor: payload JSON compared with key order preserved (unsorted), for the browse, zap-page, channel-number and episode branches. |
   | 9 Lifecycle | Unmount and pending-completion widget tests (no throw after dispose). **Source guards** on the verbatim `initState`/`dispose`/`didUpdateWidget`/`didChangeAppLifecycleState` statement order (the checker also enforces it), and on the child-owned resources. |
   | 10 Performance | Source guards on read locations, lazy callbacks and rebuild boundaries (1714, 496, 6938). Device performance: **pending**. |

   - **Goldens on both hosts:**
     - **macOS:** captured locally from the original code;
     - **Linux:** captured from the original code on Ubuntu with a one-off
       workflow on a temporary branch (the settings procedure, run
       37099639922), then deleted;
     - **comparison:** exact, with the host chosen deterministically.
   - Record a **characterization baseline** (`iptv/base3`) after adding
     these tests.
   - **Compare it** with `iptv/base2`: `PASS`, and **every added
     characterization identity must pass**. A failing new test is a step 0
     bug, never a baseline outcome.
   - Later steps compare against `base3`, so the new tests are baseline
     identities, not "added".
6. **CI test list.** Add every affected test as a concrete path, nested ones
   included, to `dev/tool/ci_behavior_tests.txt` **now**, so gate 1 runs them.
   The allowlist gains nothing.
7. **Source-text inventory** (`dev/tool/iptv_source_text.txt`):
   - `test/iptv_epg_xmltv_integration_test.dart:335` (`_updateEpgContext`);
   - `test/theme/shape_manifest_test.dart:123` (7 bare radii);
   - `dev/tool/theme_rendered_set.py` and `dev/tool/measure_theme_surface.sh`,
     via `theme_surface_manifest.txt`'s `p2_iptv` entries;
   - `dev/tool/file_size_baseline.txt:6`.

   Grep for more. Each entry gets its porting step.

### Per step

- **Move:** verbatim, with the allowed edits only.
- **Format** changed files, except the facade before step 7.
- **Analyzer:** compare the whole repo with the previous step,
  `--relocate lib/widgets/iptv/iptv_results_view.dart=lib/features/iptv/`.
- **Checks:**
  - `check_verbatim_moves.py --manifest dev/tool/iptv_manifest.tsv --self-test`
    and the settings manifest run, which must still pass;
  - `check_search_architecture.py`;
  - `check_file_sizes.py --update`.
- **Tests:** the CI test list, the characterization tests and the source-text
  inventory. Record them with `suite_evidence.py run iptv/stepN <paths>` and
  compare with `iptv/base3`.
- **Commit;** gate commits say `gate`.

### Source-text and manifest ports

- **EPG guard:** point it at `_updateEpgContext`'s new file.
  - Assert the start and end markers exist before slicing.
  - Keep every assertion, rewritten to the new spelling where qualification
    changes them (for example `ticket == _loadTicket` → its qualified form),
    never loosened.
- **Shape manifest:**
  - **Radii:** keep the total at 7 across the real owners.
  - **Registration:** register every `lib/features/iptv/` file.
  - **Token floor:** owners that hold `app.shape.` calls go in
    `kShapeResidue`, which counts toward the token-call floor (321, 349,
    365). Owners without such calls go in `kExtractedShapeResidue`.
- **Theme tools,** two separate checks:
  - expand the `p2_iptv` patterns in `theme_surface_manifest.txt` so
    `measure_theme_surface.sh` measures every new file;
  - run `theme_rendered_set.py`'s import walk from the facade and Browse
    roots to confirm the new files are reached. Its line 31 is documentation,
    not a registry.
- **Never** delete an assertion to make a move pass.

## Definition of done

1. **The facade** (at most 400 lines, formatted, an exact composition root)
   holds:
   - `IptvResultsView`;
   - `IptvResultsViewState`: the verbatim lifecycle, section wiring, the
     approved single-expression `build` forwarder to plain `IptvRootLayout`,
     the interface entry points, and the whole public surface with identical
     signatures.

   `main.dart`, `browse_screen.dart` and the tests compile unchanged.
2. **Guard.**
   - `lib/features/iptv/` is a registered feature, with the exact
     `legacy_iptv/` bridge path and 500-line files.
   - Extracted code may not import the facade.
   - The facade has its 400-line cap and `TEMP(iptv)` rejection.
3. **Checks:** both manifest runs pass, with self-tests, and every
   characterization test passes unchanged against `iptv/base3`.
4. **Analyzer and tests:**
   - no new diagnostics and no lint suppressions;
   - gate 2 passes against `iptv/base3.jsonl` and `iptv/gate1.jsonl`.
5. **CI:** format and analyze cover the facade, the test list holds every
   IPTV and characterization test, the allowlist gains nothing, and CI passes
   on `private`.
6. **Progress records:**
   - the step commits and each section's ownership;
   - the seams;
   - the exceptions with their exit milestones;
   - every contract covered only by source guards, as **pending device
     verification**: preview punch-through, native launch and return, D-pad
     on Android TV, and first-open performance.
7. Stop after gate 2 and report.

## Explicitly not in scope

- Other IPTV files (`iptv_service.dart`, `iptv_catalog_db.dart`,
  `iptv_channel_row.dart`, the guide, zap and player code).
- Converting the 7 bare radii to shape tokens (a visual change).
- Adding a surviving-channel lookup to focus repair (contract 3).
- Riverpod state, performance work (the first-open hang), and bug fixes.
  Record any bug you find under "Found, not fixed".

## Progress

### Step 0 — complete; original-code checkpoint

- Starting branch/revision: clean `refactor/codebase` at `e1d99a29`.
  Original application baseline: detached checkout of `d93428fb` at
  `/tmp/debrify-iptv-baseline-d93428fb`, Flutter 3.44.8 / Dart 3.12.2.
- `python3 dev/tool/suite_evidence.py run iptv/base` completed: 10,317
  successes, 13 failures, 28 errors, 20 skips. These are observed identities;
  no allowlist was changed. Evidence lives in the git common directory,
  `refactor-evidence/iptv/`.
- [Dependency report](iptv-results-view-deps.md) and
  [declaration manifest](../../dev/tool/iptv_manifest.tsv): 383 original
  leaves, 113 State fields and 14 class headers. The named clock field adds
  one manifest leaf. Original members have assigned destinations and steps;
  the report supplements direct assignments with mutation/alias/resource
  ownership and records cross-call destinations.
- The shared checker now loads per-manifest settings/IPTV configs. The
  parser additionally handles the original record typedef. Existing settings
  fixtures and the 316-leaf settings manifest passed after generalization;
  the IPTV check passed with all 384 leaves and 25 positive/negative fixtures.
  Outputs: `settings-check-generalized.txt`,
  `iptv-check-with-seams-final.txt`. The launcher fixture run is retained.
- Registered test accessor: real production tear-offs plus borrowed
  snapshots/identities. Clock: the view forwards its default `DateTime.now`
  function to timeline paint and hero metadata; timeline refresh bookkeeping
  also reads that function, and the day-heading helper becomes an instance
  method to reach it. Exact patches are pinned in
  [iptv_checker_config.json](../../dev/tool/iptv_checker_config.json).
  No widget, decoration, focus node or lifecycle statement moved.
- Seam-only size exception: facade **9,084 → 9,149**, exactly **65 added
  physical lines**. Raised only that ratchet entry by hand. Exit: step 1
  removes the private widgets/pure helpers and ratchets below 9,084.
- First seam full-suite comparison found two timeline fixture overflows:
  the clock now paints current programmes consistently. Both fixtures retain
  every assertion and use the shipped 90-minute window; all 43 timeline
  tests passed. The corrected full run
  matches all baseline identities: 10,317 successes, the same 41 failures/errors,
  20 skips; no new failures, missing tests or newly skipped identities. PASS
  (`base2-verified-comparison.txt`). It is the canonical `iptv/base2`; the
  first failed attempt is retained as `base2-first`. No failing comparison
  is accepted.
- Whole-repo analyzer baseline initially differed because the detached
  checkout lacked local generated build pubspec inputs and nested vendor
  package configs. Those untracked inputs were copied into the baseline
  checkout; no tracked source changed. `analyze-base-normalized.txt` versus
  `analyze-base2.txt` passes with zero added diagnostics. Extra missing assets
  in the copied generated build directories account for removed baseline
  diagnostics; app/test diagnostic identities are identical.
- Source consumers are listed in
  [iptv_source_text.txt](../../dev/tool/iptv_source_text.txt). Added 59
  concrete IPTV/dependency test paths (nested tests included) to the CI test
  list; the failure allowlist gains nothing.
- Characterization: real temporary SQL view tests cover landing/manual All,
  revision-driven revalidation, identity retention, vanished categories,
  numbering adoption, same-index focus repair, external focus, stale tickets,
  query debounce replacement/disposal, and pending completion after unmount.
  Exact source guards cover all ten contracts, including preview order,
  startup/launcher identity, interleaved lifecycle and lazy read boundaries.
  The attached-row fallback cannot be isolated through this fixture's normal
  frame sequence: the replacement row at the clamped index is attached before
  the post-frame repair. Its complete same-index/attached/filter branch is
  source-guarded and independently pinned by the verbatim checker; no internal
  focus-map mutation or timing override is used to manufacture that branch.
- Extended row key coverage preserves quick-select, focus-loss disarming,
  repeat/hold favorite dispatch and no release playback. Spotlight checks both
  Browse interfaces and untyped GlobalKey dispatch. The startup hook verifies
  exact identity, corroborated number fallback and first-available focus,
  cancelling before native launch. Native launch/return, preview punch-through,
  Android TV D-pad and first-open performance remain pending device checks.
- Payload JSON fixtures compare unsorted encoded maps through the real accessor
  for browse, zap-page, end paging, channel-number/miss and both episode paths.
  A local HTTP panel warms the real Xtream episode cache. Only its variable
  loopback address is substituted; key/array order and every other value stay
  exact. Payload capture output: `payload-capture-third.txt` (7 passing tests).
- Original-code goldens: four macOS captures passed locally, then strict
  comparisons passed in the characterization run. Linux capture and strict
  comparison passed on Ubuntu at temporary revision `f7729406`, based on
  `d93428fb` plus only the approved clock seam and golden harness. Evidence:
  https://github.com/varunsalian/debrify-refactor/actions/runs/37106832940.
  The remote temporary branch was deleted. PNG hashes and provenance are in
  `test/goldens/iptv_results/provenance.json`; goldens select the host explicitly.
- Dependency review corrected `landingCategoryFor`'s destination to the exact
  legacy bridge: it reads `IptvCatalogDb.defaultCategory`. No implementation
  change or data contract is introduced; the public static forwarder stays.
  The declaration manifest/report govern this source-derived classification.
- `iptv/base3` completed: 10,351 successes, the same 13 failures/28 errors
  and 20 skips. Comparison against `base2` is PASS: no new failures, missing
  tests or new skips; **all 34 added identities pass**
  (`base3-comparison.txt`, `base3-added-identities.txt`). These are now the
  required baseline identities for every extraction/gate.
- Final whole-repo analyzer compared with `base2`: 832 diagnostics, identical
  identities, PASS (`analyzer-step0-comparison.txt`). Both manifest self-test
  runs pass (`iptv-check-step0-final.txt`, `settings-check-step0-review.txt`),
  architecture and file-size checks pass, changed Dart files are formatted,
  and the diff check passes. Shared checker review retains the settings
  partition/context checks; exact forwarder, lifecycle and accessor checks
  apply to the IPTV config. CI formats the new support helpers and includes
  all four characterization test files. The allowlist remains unchanged.
- This checkpoint commits the dependency report, manifest, checker/configs,
  frozen seams and original-code characterization before any extraction.

## Found, not fixed

- Timeline programme badges can overflow when a current programme is
  partially visible in a four-hour window (`spotlight_live_timeline.dart`:
  programme Row / duration-based `itemCanFitBadge`). The old injected-clock
  tests never painted their future-dated programmes as current; the complete
  clock seam exposes the existing layout issue. No production layout fix is
  included. Navigation fixtures use the shipped 90-minute window and keep
  every assertion.

### Step 1 — complete

- Step-0 checkpoint: `a28cd8fe`; no extraction preceded it.
- The bars painter references the chip State's private `_amber` constant.
  Both are co-located in `iptv_stage_chip.dart` so that the existing State and
  constant keep their privacy and ownership; the manifest/report now identify
  that cohesive destination. No initializer or paint expression changes.
- Moved 79 manifest leaves into 14 files; the bars painter and chip share
  their cohesive file. The facade ratchets **9,149 → 8,256** and the largest
  new file is 189 lines. Public constants/getters/methods remain exact checked
  forwarders; the State lifecycle and widget trees remain in place.
- Registered IPTV's exact bridge and 500-line feature caps, the pure-helper
  service-import rejection and no-facade-import rule. Shape registrations cover
  every new file and preserve all seven radii and the token floor. Expanded
  `p2_iptv` globs; the theme measurement and import walk pass, and an explicit
  reachability check confirms all 14 new files from facade/Browse roots.
- Fixed parser formatting metadata for the comma before a named/optional
  parameter-list closing delimiter. Two fixtures accept only formatting/key
  addition and reject a changed parameter. The accessor token sidecar was
  regenerated from committed `a28cd8fe`, not the changed source: only its two
  now-recognized formatting commas disappear; its contract is unchanged.
- Checks: `step1-verbatim-verified.txt` (384 leaves, 27 IPTV fixtures plus
  settings/launcher fixtures), `step1-settings-verbatim.txt` (316 leaves),
  architecture/size/format/diff checks pass. Whole analyzer: 832 diagnostics,
  zero added after relocation (`step1-analyzer-verified-comparison.txt`).
  `suite_evidence.py run iptv/step1 @dev/tool/ci_behavior_tests.txt`: 2,786
  successes, the same two known failures, zero missing/new skips, PASS against
  `base3` (`step1-test-comparison.txt`). No golden or payload fixture changed.

### Step 2 — complete

- Step-1 checkpoint: `282dd6b7`. The 111 remaining original State fields now
  have nine owners by concern; the two public threshold constants already
  belong to the step-1 layout policy. Initializers, static/final semantics
  and collection/notifier identity remain exact. No owner receives a combined
  disposal method: lifecycle statements stay interleaved in the State.
- The facade ratchets **8,256 → 8,085**; nine new owners are 29–105 lines.
  Their borrowed services/collections retain original initialization and
  construction/disposal ownership. Nine exact composition fields are pinned
  in the scaffolding sidecar. Every lifecycle body remains receiver-qualified
  in the facade with its original statement order.
- The State and category-dialog fields both originally used `_scrollController`.
  The checker now resolves ambiguous renames within the original declaration
  owner. Added positive/negative fixtures prove that the dialog's independent
  field reference cannot be silently renamed. All 29 IPTV fixtures and the
  settings/launcher fixtures pass, with 384 IPTV leaves and 316 settings leaves
  (`step2-verbatim-verified.txt`, `step2-settings-verified.txt`).
- Ported the EPG source guard's ticket spelling when fields moved, ahead of
  its method relocation in step 4. All original assertions remain, and both
  slice markers must exist. Its focused 12 tests pass (`step2-epg-port.txt`).
  Other source guards, all seven radii and all 23 feature registrations remain.
- Whole analyzer is 832 diagnostics with zero added after relocation, PASS
  (`step2-analyzer-comparison.txt`). `iptv/step2-verified` reruns the complete
  CI list after the source guard correction: 2,786 successes, the same two
  failures, no missing/new skips, PASS against `base3`
  (`step2-test-comparison.txt`). Architecture, size, formatting, import
  reachability/theme measurement and diff checks pass. No fixture changed.

### Step 3 — complete; full-suite gate 1 passes

- Step-2 checkpoint: `63ee65c3`. Moved 43 methods into eleven legacy bridge
  owners: settings loading, favorites, category order, catalog loading,
  presentation, facades, maintenance, refresh, network fetching, load status
  and the status chip. Production callers and the registered test accessor
  use them; no replaced implementation remains in the State.
- The facade ratchets **8,085 → 6,528**. The largest new file is 400 lines.
  Typed dependency records borrow the existing concern owners and use live
  State/widget callbacks. Deferred cross-section closures preserve lazy
  construction without a type-inference cycle. Listener add/remove sites
  retain the same section method tear-offs. No resource or disposal statement
  leaves its original lifecycle position.
- Seven formatter-split `if` bodies receive only braces, at exact pinned
  sites in `iptv_context_exceptions.json` and their manifest rows. These are
  the plan's pre-approved formatter pattern; every original statement remains.
  No context confirmation or lint suppression was added. Temporary callbacks
  name their final destinations and exit in steps 4, 5 or 6.
- The shared parser exposes return/parameter metadata for typed wiring;
  comparison tokens are unchanged. Both manifest/self-test runs pass:
  384 IPTV leaves and 29 IPTV fixtures plus existing settings/launcher
  fixtures, and 316 settings leaves (`step3-verbatim-second.txt`,
  `step3-settings.txt`).
- Whole analyzer: the same 832 diagnostic identities, zero added/removed,
  PASS against the verified step-2 run
  (`step3-analyzer-verified-comparison.txt`). The complete CI list has 2,786
  successes and the same two failures, no missing/new skips, PASS against
  `base3` (`step3-test-comparison.txt`). Strict goldens and payload fixtures
  remain unchanged. Architecture, size, formatting, diff and theme checks
  pass; all 34 IPTV feature files are reached from facade/Browse imports.
- Full-suite `iptv/gate1` matches `base3`: 10,351 successes, the same
  13 failures/28 errors and 20 skips. No new failures, missing tests or newly
  skipped identities; PASS (`gate1-comparison.txt`). Native preview, launch/
  return, Android TV D-pad and first-open performance remain pending device
  verification. This gate is committed before the next extraction step;
  its push goes only to `private` and its CI must pass before step 4.
- Gate checkpoint: `03543cf4`, pushed only to `private`. All CI jobs pass,
  including the Linux behavior suite and original-code golden comparisons:
  https://github.com/varunsalian/debrify-refactor/actions/runs/37111405964.

### Step 4 — complete

- Gate-1 checkpoint: `03543cf4`. Moved 24 methods into six owners: guide
  context, filters, categories, virtual results, player payload construction
  and player browsing. Calls to already-moved sections use typed deferred
  callbacks; borrowed getters stay live. The categories section's wiring
  receiver is `_categoryActions`, avoiding the original `_categories` field
  name. The original field still has its single catalog-state owner.
- The facade ratchets **6,528 → 5,369**; the largest new file is 404 lines.
  Resolved step-4 `TEMP(iptv)` comments are removed from the earlier owners;
  remaining callbacks retain their step-5/6 destinations. Their scaffolds
  change only by those comment removals and the registered receiver wiring.
- The EPG source test now reads `iptv_guide_context.dart`, validates both
  markers and retains all four assertions. The shape manifest registers all
  40 feature files, preserves seven radii and its token floor. Theme
  measurement and the facade/Browse import walk pass.
- Added one exact formatter-braces site for the newly split progress guard.
  The shared parser recognizes an optional trailing comma in multi-field
  positional record literals; four fixtures accept formatting and reject a
  changed field or a semantic singleton-record comma. Named dependency
  records stay pinned. Both manifest/self-test runs pass: 384 IPTV leaves,
  33 IPTV fixtures plus settings/launcher fixtures, and 316 settings leaves
  (`step4-verbatim-verified.txt`, `step4-settings.txt`).
- Whole analyzer: the same 832 identities, zero added/removed, PASS
  (`step4-analyzer-comparison.txt`). The verified CI-list run has 2,786
  successes, the same two failures, no missing/new skips and PASS against
  `base3` (`step4-test-verified-comparison.txt`). Strict payload bytes/key
  order and goldens are unchanged. Architecture, size, format and diff checks
  pass. No new allowlist entry or lint suppression was added.

### Step 5 — complete

- Step-4 checkpoint: `5d5e0d15`. Moved 47 methods into fourteen owners:
  playback, playback actions/refresh, startup resolution/launch, catch-up,
  preview handoff, schedule actions, recording support, record-now, Android
  and desktop recording, source counts and navigation. The public interface
  entry points remain in the State, with their original signatures/bodies and
  qualified member calls. Native launcher code and bridge payloads are untouched.
- The facade ratchets **5,369 → 4,120**; the largest new file is 291 lines.
  The source-counts section uses `_sourceStatistics` for wiring, avoiding
  duplicate naming with the original `_sourceCounts` field, still owned only
  by recording state. Resolved step-5 temporary callbacks are removed; layout/
  preview callbacks retain their step-6 exit. Two exact formatter-braces sites
  preserve their original guards/statements. Lifecycle order stays verbatim.
- Both manifest/self-test runs pass: 384 IPTV leaves and 33 IPTV fixtures
  plus settings/launcher fixtures, and 316 settings leaves
  (`step5-verbatim-verified.txt`, `step5-settings.txt`). Whole analyzer retains
  all 832 identities, zero added/removed, PASS (`step5-analyzer-comparison.txt`).
- The verified CI list matches `base3`: 2,786 successes, the same two
  failures, no missing/new skips, PASS (`step5-test-comparison.txt`). This
  includes startup resolution/focus/pre-launch cancellation, both Browse
  interfaces and untyped GlobalKey dispatch, payloads, source guards and
  strict goldens. Native launch/return and preview punch-through still need
  device verification; no device parity is claimed.
- Architecture, size, format and diff checks pass. Shape registration covers
  all 54 feature files and seven radii; theme measurement and facade/Browse
  import reachability pass. No allowlist or golden/payload fixture changed.

### Step 6 — complete

- Step-5 checkpoint: `864b1247`. Moved 64 methods into fifteen owners:
  loaded/classic/TV two-pane layouts, cockpit stage, content, quiet filters,
  Spotlight layout/hero/content/actions/focus, row projection, tablet selection,
  preview layout and preview tuning. Widget trees, keys, focus nodes, paint
  order, lazy callbacks and live widget reads remain verbatim.
- The facade ratchets **4,120 → 1,714** before final composition cleanup.
  No `TEMP(iptv)` remains in the feature. Six exact formatter-braces sites
  preserve existing guards and statement order. Every section meets 500 lines;
  composition wiring is the remaining step-7 responsibility, alongside final
  facade formatting, guard registration and CI scope.
- Shape registration covers all 69 feature files plus the facade and preserves
  seven radii and the unchanged token floor. Owners with `app.shape.` calls
  stay in `kShapeResidue`; the facade now has none and moves to
  `kExtractedShapeResidue`. Theme measurement and all-file import reachability
  from facade/Browse pass.
- Both manifest/self-test runs pass: 384 IPTV leaves and 33 IPTV fixtures
  plus settings/launcher fixtures, and 316 settings leaves
  (`step6-verbatim-verified.txt`, `step6-settings.txt`). Whole analyzer retains
  the same 832 identities, zero added/removed, PASS
  (`step6-analyzer-comparison.txt`).
- The verified CI list matches `base3`: 2,786 successes, the same two
  failures, no missing/new skips and PASS (`step6-test-comparison.txt`). All
  four strict layout goldens, row repeat/hold behavior, Browse handoffs,
  startup focus, payload fixtures and preview/lifecycle source guards pass.
  Architecture, size, format and diff checks pass. Native preview layering,
  native launch/return, Android TV D-pad and first-open performance remain
  pending device verification.

### Step 7 — local gate 2 complete

- Step-6 checkpoint: `2172b70b`. The 45 existing section constructors now live
  in seven concern-specific composition factories, borrowing the same nine state
  owners and live State/widget callbacks. Deferred cross-group getters preserve
  lazy access. `IptvCompositionOwners` constructs the original nine owners eagerly
  and in their original order; teardown remains in the State's verbatim lifecycle.
  Ordinary field/section comments move beside their owners. No original business
  implementation is copied into the factories.
- **Approved named exception, `root_build_forwarder` (2026-10-03):** the original
  `IptvResultsViewState.build` body moves verbatim into
  `presentation/legacy_iptv/iptv_root_layout.dart::IptvRootLayout.build`, except
  for dependency/receiver wiring and removal of the moved `@override`. The State
  keeps its exact annotated signature and one forwarding expression. The root
  section is a plain class with narrow callbacks and borrowed settings state;
  it is not a widget and does not introduce a new element/rebuild scope. Widget
  trees, local builder contexts, conditional reads, callbacks and evaluation
  order remain intact. The prescribed retained members exceeded 400 lines before
  imports/wiring (435 at the initial measurement); this approved exception
  resolves that conflict while preserving the 400-line cap.
- The formatted facade is **393 lines**. All 80 feature files meet 500 lines;
  the largest is 439. The ten composition/binding/owner files range from 36 to
  326 lines, and the root layout is 113. The completed guard is enabled, registers
  the facade as an exact composition root, and rejects `TEMP(iptv)` throughout
  the completed source set. CI format and analyzer scope include the facade.
- The shared checker pins the root class header to `class IptvRootLayout {`,
  excluding inheritance, interfaces, mixins and widget aliases. It compares the
  complete moved declaration with the original, removing only the named
  `@override` tokens and normalizing registered dependencies/receivers. It requires
  the retained State member, its exact annotated signature and the single
  expression `_sections.standardLayouts.rootLayout.build(context)`. Twelve
  new positive/negative fixtures cover the plain section, body/annotation
  mutations, widget inheritance, interfaces/mixins, missing forwarding member,
  statement/wrapped dispatch, wrong context and lost facade annotation.
- The prepared proposal passed isolated compilation and all 30 characterization
  identities against `base3`, with strict original golden/payload fixtures and no
  added/missing/skipped identities. This proposal evidence is retained separately
  from final production checks (`root-build-proposal-verbatim.txt`,
  `root-build-proposal-analyze.txt`, `root-build-proposal-test-comparison.txt`).
- Final production checks pass: 384 IPTV leaves and all 50 IPTV fixtures, plus
  existing settings/launcher fixtures (`step7-verbatim.txt`); 316 settings leaves
  and self-tests (`step7-settings.txt`). The full analyzer retains the same 832
  identities, zero added/removed (`step7-analyzer-comparison.txt`), and the exact
  CI analyzer command exits successfully (`step7-ci-analyze.txt`). All 1,263
  files in CI's format scope are already formatted (`step7-format.txt`). The
  101-test focused run has zero failures and exactly matches `base3`
  (`step7-focused-comparison.txt`). No lint suppression is added.
- Gate 2 exactly matches **both** observed full-suite baselines: **10,351
  successes, 13 failures, 28 errors and 20 skips**, with no new failures, missing
  tests, added identities, fixed identities or new skips
  (`gate2-base3-comparison.txt`, `gate2-gate1-comparison.txt`). These existing
  failures/errors remain; a nonzero Flutter runner exit is not a clean-suite
  claim. SDK/configuration match the recorded baselines.
- Architecture, file-size, import reachability, separate theme measurement,
  shape registration and diff checks pass. All 80 feature files are reached
  from facade/Browse roots. The seven bare radii and token-call floor are
  unchanged; original golden/payload fixtures, CI test list and failure allowlist
  gain nothing. Native preview layering, native launch/return, Android TV D-pad
  and first-open performance remain **pending device verification**.
- This step's checkpoint commit is `refactor(iptv): gate 2 complete facade and
  composition extraction`. Its private-only push and CI confirmation follow the
  local gate; the final review report records the resulting commit/run URL, with
  local CI evidence in `gate2-ci-status.json` and `gate2-ci.log`. No `origin` push
  is authorized. Stop after this gate and its passing private CI.
