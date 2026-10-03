# IPTV results view refactor — plan

Written 2026-10-03 on `refactor/codebase` at `d93428fb`. Follow
[AGENTS.md](../../AGENTS.md). This page plus AGENTS.md is everything the
executing agent needs.

Work on the existing `refactor/codebase` branch. Commit after every step. Never
push to `origin`; push to `private` only if the goal says so. Gate commits must
contain `gate` in their message (AGENTS.md: CI's behaviour job runs on
`refactor/**` pushes only for `gate`/`[full-ci]` commits).

## Goal

`lib/widgets/iptv/iptv_results_view.dart` is 9,084 lines: the whole IPTV
browsing surface. It covers catalog loading and maintenance, the database
catalog, guide (EPG) context, filters and categories, playback and catch-up,
the startup channel, recordings, the player's in-player browse payload, the
live preview, and four layouts (classic, TV two-pane, cockpit stage,
Spotlight).

Split it into a new feature, `lib/features/iptv/`, **moving code verbatim**.
- **Unchanged:** the widget tree, keys, focus nodes and build order.
- **Stays in `iptv_results_view.dart`:** the public `IptvResultsView` widget
  and `IptvResultsViewState`, with its lifecycle (`initState`,
  `didUpdateWidget`, `dispose`, `didChangeAppLifecycleState`, `build`), its
  interfaces, and the three public static helpers that tests call. Those
  helpers stay on the State as forwarders.

**Architectural status:** this is a bounded legacy-extraction stage, like the
settings refactor. Its temporary exceptions, each recorded in Progress with an
exit milestone, are:
- State-driven sections wired by the State, instead of Riverpod;
- a `legacy_iptv/` bridge folder whose code calls services directly;
- unchanged legacy user-facing text.

## What it contains (line numbers at `d93428fb`; step 0 re-derives them)

| Lines | Area | Key symbols |
| --- | --- | --- |
| 1–131 | Imports, top-level types | `_TabletChannelIdentity` (typedef), `_railResExp`, enums `_CatalogChipState`, `_ChipOwner`, `IptvResultsView` |
| 132–665 | State fields, small helpers | 113 fields: startup channel, command center, per-channel `_cardFocusNodes`, `_focusNodeFor`/`_rowAttached`/`_onRowDetached`, schedule pane. Implements `BrowseResultsFocusController` and `BrowseSearchResultsFocusController`; mixes in `WidgetsBindingObserver`. |
| 666–1164 | Lifecycle and settings | `initState` (51 lines), listener callbacks, favorites, list picker, `_loadSettings`/`_loadSettingsInner` (148), `didUpdateWidget`, `dispose` (49) |
| 1165–2431 | Catalog loading and maintenance | `_retryLoad`, `_loadPlaylist(Inner)` (181), `_presentCatalog` (179), `applyStoredLocalCategoryOrder` (public static), `_presentDbCatalog`, maintenance, migrations, numbering, `_revalidateDbCatalog(Inner)`, `_applyDbCatalogRefresh` (236), `_fetchCatalogFromNetwork` |
| 2432–2651 | Load status and catalog chip | `_buildLoadingState`, `_beginLoadStatus`/`_endLoadStatus`, `formatLoadBytes`/`formatLoadElapsed`/`loadBytesLabel` (public static), chip ownership (`_showChip`, `_hideChipIfOwned`) |
| 2652–3410 | Guide context, results, filters, categories | `_updateEpgContext` (152), progressive batches, continue/list results, `_applyFilters`, playlist/content/category change handlers, `landingCategoryFor` (public static), category options and hide |
| 3411–3924 | Player browse payload | `_playerSourcePayload`, `_playerChannelPayload`, `_fullCategoryList`, `_providePlayerIptvBrowse` (365) |
| 3925–4325 | Play and startup channel | `_playChannel`, `_maybeRunStartupLaunch`, `_resolveStartupRow`, `_scrollAndFocusStartupRow`, ... |
| 4326–4836 | Catch-up, playback, after-playback refresh | `_playCatchup`, `_playChannelInner` (174), series detail, continue actions, `_refreshAfterPlayback` |
| 4837–4935 | App lifecycle, sidebar focus, recording counts | `didChangeAppLifecycleState`, `_onTvSidebarFocusChanged`, `_initRecordingSupport` |
| 4936–5319 | Recordings | `_stageRecordNow` (124), `_scheduleProgrammeFromStage` (100), Android and desktop recording |
| 5320–5413 | Navigation and the focus interfaces | `_navigateToSettings`, `focusFirstFilter`, `focusSearchResults`, `refreshPlaylists` (public) |
| 5414–5687 | `build`, layout choice, iOS notice, chip | |
| 5688–6699 | Spotlight layout | `_buildSpotlight*`, `_showSpotlightChannelActions`, sources and category pickers |
| 6700–7372 | Classic, TV two-pane, cockpit stage, filters | `_buildTvTwoPane` (194), `_buildCockpitStage` (140), `_cockpitIdentity` (132), `_buildQuietFilters` |
| 7373–7524 | Focus and preview tuning | `_onChannelFocused`, `_retunePreview`, `_onPreviewPlaybackFailed`, `_stopPreviewPlayback`, `_clearPreview` |
| 7525–8209 | Preview rail/stage, main content, tablet selector | `_buildPreviewRail`, `_buildPreviewStage`, `_buildContent` (354), tablet selector |
| 8210–9084 | Private widgets and painters | `_SpotlightCategoryPickerDialog(State)`, `_IptvStageFloor(State)`, `_TuningWavesPainter`, `_IptvStageChip(State)`, `_TuningBarsPainter`, `_IptvFocusStageInfo`, `_IptvRailInfo`, `_IptvRailHints`, `_KeyCap` |

No single method is over 500 lines. The largest are `_providePlayerIptvBrowse`
(365) and `_buildContent` (354).

## Contracts that must not change

These come from earlier IPTV work (see the IPTV notes in the repo history). Each
needs a behaviour test or an explicit source guard **before** the code it
covers moves (step 0).

1. **Preview rectangle is paint-free.** The native preview plane renders under
   Flutter, so nothing may paint over the preview rect: no new backgrounds,
   decorations or opacity wrappers. Widget order and decoration stay exactly
   the same.
2. **Landing-category seed rules.**
   - `_selectedCategory == null` means both "All" and "not picked yet";
     `_categoryManuallyChosen` tells them apart.
   - `_landingSeedArmed` is armed in `_loadPlaylistInner` and disarmed at
     **both** present sites (`_presentCatalog`, `_presentDbCatalog`), even
     when the seed declines.
   - Revalidation re-presents must never seed.
3. **Focus repair after a catalog revalidation or refresh** keeps its order:
   the surviving row, then the same index, then any built row, then the
   filters bar. It never steals focus that is elsewhere, and it returns early
   when `!mounted`.
4. **Playback identity.** Never hand `_playChannel` or the launcher a
   self-built `IptvChannel` or a catalog facade (`DbChannelList`); the player
   launch window is materialized from SQL.
5. **Catalog safety.** Empty parses are never ingested. Load and refresh
   tickets (`_loadTicket` and others) still reject stale results. Hidden
   categories are keyed by group name.
6. **D-pad behaviour.**
   - Rows play on an OK key-up whose key-down they saw (`_sawSelectDown` in
     `iptv_channel_row.dart`, which doesn't move). This file's row wiring
     (callbacks, focus nodes, `_rowAttached`/`_onRowDetached`) stays exactly as
     it is.
   - Guide key handling consumes events.
   - The TV sidebar focus listener, `focusFirstFilter`/`focusSearchResults`,
     and content-focus requests (`_consumeContentFocusRequest`) keep their
     order.
   - The rail's expanded panel stays fully opaque.
7. **Startup channel launch:** the same trigger point (after `_loadSettings`
   succeeds), resolution order, failure handling and cancellation.
8. **Player browse payload** (`_providePlayerIptvBrowse` and the
   `_player*Payload` helpers): byte-identical maps, keys and ordering. It feeds
   the native and Flutter players.
9. **Lifecycle order.**
   - **`initState`:** observer and sidebar listener (TV only), Stremio,
     channel-order and catalog-refresh listeners, `_loadSettings().then(...)`,
     `_loadFavorites`, recording support, the iOS notice, then the
     recording-schedule listeners.
   - **`dispose`:** seven listener removals (two of them TV-only), cancelling
     eight timers, then disposing the scroll controller, seven focus nodes or
     scopes, five preview `ValueNotifier`s and the card focus nodes, then
     `super.dispose()`.
   - **Exact order:** both keep their exact order. A moved resource's owner
     exposes `dispose()`, which the State calls at the original position.
10. **Performance.** No new work in `build`, no new rebuild scopes, no extra
    catalog queries. The known slow first open must not get worse.

## Destination layout

`lib/features/iptv/` (a new feature):
- **`application/`:** pure helpers with no services and no context, if the
  report confirms them (for example `formatLoadBytes`, `formatLoadElapsed`,
  `loadBytesLabel`, `landingCategoryFor`, the `_railResExp` parsing).
- **`presentation/legacy_iptv/`:** a named bridge for sections that take a
  `BuildContext` or call services: the state owners, catalog loading and
  maintenance, guide context, filters and categories, the player payload,
  playback and startup, recordings, navigation, and the layout builders.
- **`presentation/`, outside the bridge:** the private widget classes and
  painters (8210–9084), as public widgets where they now need to be, with an
  optional `super.key` per the settings precedent. Also any layout piece with
  no service imports.

Each file is at most **500 lines**. The facade file is at most **400 lines**,
enforced only at the final step (see "Staged enforcement").

## Technique

The same approach as `docs/refactoring/settings-screen-plan.md`; read its
Technique section. In short:

1. **Sections are plain presentation classes** constructed by the State and
   living exactly as long as it does. Constructors take narrow deps records:
   `setState`, `mounted`, `context`, `widget` getters as live callbacks, and
   deferred calls into methods that haven't moved yet.
2. **State owners by concern.** The 113 fields move into a few owners (for
   example browse/catalog state, preview, startup, recording, chip/status,
   Spotlight), as the dependency report decides.
   - **One owner per field,** with the same initializer.
   - **Fields written by several sections** go through their single owner.
   - **Resources** (the scroll controller, focus nodes and scopes, preview
     `ValueNotifier`s, timers, `_cardFocusNodes`) have an explicit owner. Each
     owner's `dispose()` runs at the original position in the State's
     `dispose`.
3. **`mounted` and `context`:** the settings rule, verbatim.
   - **Guards stay put:** keep every `mounted` guard at its original position.
   - **Fetching `context`:** do it only at the original first use, or right
     after the original passing guard.
   - **Builder and dialog contexts are untouched.** The checker's
     builder-context rule enforces this.
   - **Pre-approved patterns** (record each one): a `context.mounted` check
     right after an existing `_deps.mounted()` guard and `_deps.context()`,
     with no `await` between; and braces on a formatter-split `if` body.
4. **Allowed edits:**
   - qualifiers and receivers;
   - deps wiring;
   - imports;
   - dropping `_` where another file needs a symbol;
   - optional `super.key` on widgets made public;
   - removing `@visibleForTesting` from production-called implementations
     that move into another library;
   - any other edit only with approval, recorded in the manifest.
5. **Not allowed:**
   - reordering `await`s, guards, `setState` contents, timer starts or
     cancels, or listener adds and removes;
   - changing a widget, key, `FocusNode`, decoration or the build order;
   - merging look-alike helpers;
   - changing user-facing text;
   - suppressing a lint.
6. **Temporary cross-calls** (`TEMP(iptv)`) are allowed only from
   `legacy_iptv/` files, and none may remain at the end.

## Staged enforcement

As in the settings refactor:
- **From step 1:** the guard registers `lib/features/iptv/` (data, application
  and presentation rules, with the `legacy_iptv/` bridge exact path) and
  checks every **destination** file's cap.
- **CI** format and analyze cover `lib/features/iptv/` from step 1.
- **Until the last step,** `iptv_results_view.dart` is held only by the
  shrinking size ratchet.
- **At the last step:** format the facade, cap it at 400 lines, add it to CI's
  format scope, and turn on `TEMP(iptv)` rejection.

## Steps

| # | Work | Notes |
| --- | --- | --- |
| 0 | Baseline, dependency report, manifest, checker extension, characterization tests, source-text inventory | Nothing moves. |
| 1 | Guard and CI registration. Private widgets and painters (8210–9084), then pure helpers into `application/` | No State coupling. |
| 2 | State owners (every field) and resource owners with `dispose()` | The lifecycle order tests must pass. |
| 3 | Catalog loading and maintenance, load status and chip | Contracts 2, 3 and 5. **Full-suite gate 1.** |
| 4 | Guide context, results, filters and categories; player browse payload | Contracts 2 and 8. |
| 5 | Play, startup channel, catch-up, after-playback refresh, recordings, navigation | Contracts 4 and 7. |
| 6 | Layouts: Spotlight, classic, TV two-pane, cockpit stage, preview rail and stage, `_buildContent`, tablet selector; then focus and preview tuning | Contracts 1 and 6. |
| 7 | Final State, guards, CI. **Full-suite gate 2.** | See "Definition of done". |

### Step 0

1. **Baseline at `d93428fb`:**
   - `python3 dev/tool/suite_evidence.py run iptv/base`;
   - `flutter analyze > <E>/iptv/analyze-base.txt`, where `<E>` is
     `$(git rev-parse --git-common-dir)/refactor-evidence`;
   - the SDK must be Flutter 3.44.8.
2. **Dependency report** (`docs/refactoring/iptv-results-view-deps.md`):
   - every top-level declaration, every State member and every private widget
     member, with its destination, step and layer;
   - which fields each section reads and writes;
   - every cross-section call, tear-off, timer and listener;
   - which contract each member touches.

   Nothing may be unresolved.
3. **Manifest and checker.**
   - Add `dev/tool/iptv_manifest.tsv`.
   - Make the settings coordinator checks in `check_settings_moves.py`
     **manifest-driven**, so the IPTV manifest uses the same allowed-edit kinds
     and the context, builder-context and scaffolding checks. Extend that
     checker, don't fork it.
   - `check_verbatim_moves.py --manifest dev/tool/iptv_manifest.tsv` must
     default its baseline, source and feature, and enable every check mode, as
     the settings manifest does.
   - The self-tests still pass, plus one IPTV fixture.
4. **Characterization tests,** recorded at baseline and run unchanged at every
   step:
   - **Layout goldens:** pixel goldens for each layout (classic, TV two-pane,
     cockpit stage, Spotlight) with a fake catalog. Strict, per host (macOS
     and Linux), with the Linux goldens characterised from the original code
     on Ubuntu as the settings run did. These guard contracts 1 and 6, and the
     build order.
   - **Landing seed:** the seed is applied on first present, never on
     revalidation, and never after a manual pick (contract 2).
   - **Focus repair:** after a revalidation, the survivor, same-index, any-row
     and filters order (contract 3), with a fake catalog.
   - **Player payload:** the browse payload map for a fixed catalog, compared
     with a golden JSON (contract 8).
   - **Lifecycle:** listeners are registered and removed, and timers
     cancelled, in the original order (contract 9). Use fakes or spies where
     the services allow; where they don't, a source guard on the State's
     `dispose`/`initState` text is acceptable and must be recorded as such.
   - **Disposal:** a pending timer or async completion after dispose must not
     throw.

   Where a contract can't be driven from a test without production changes,
   record it as a source guard plus pending device verification. Don't skip
   it silently.
5. **Source-text inventory** (`dev/tool/iptv_source_text.txt`):
   - `test/iptv_epg_xmltv_integration_test.dart:335` slices `_updateEpgContext`
     to `final isPlainM3u`;
   - `test/theme/shape_manifest_test.dart:123` gives this file 7 bare radii;
   - `dev/tool/theme_rendered_set.py:31` lists it in the IPTV surface;
   - `dev/tool/theme_surface_manifest.txt`.

   Grep for more. Each entry gets the step that ports it.

### Per step

- **Move:** verbatim, with the allowed edits only.
- **Format** changed files, except the facade before step 7.
- **Analyzer:** compare the whole repo with the previous step,
  `--relocate lib/widgets/iptv/iptv_results_view.dart=lib/features/iptv/`.
- **Checks:** `check_verbatim_moves.py --manifest dev/tool/iptv_manifest.tsv`
  (with `--self-test`), `check_search_architecture.py` and
  `check_file_sizes.py`.
- **Tests:** the IPTV tests (`ls test | grep -i iptv`), the characterization
  tests and the source-text inventory. Record them with
  `suite_evidence.py run iptv/stepN <paths>` and compare with `iptv/base`.
- **Commit;** gate commits say `gate`.

### Source-text and manifest ports

- **EPG guard:** point it at `_updateEpgContext`'s new file. Keep each
  assertion: the favorites/custom-list branch, `setListEpgContext`, the
  channels source and the `_loadTicket` check.
- **Shape manifest:** split the 7 bare radii across their new owners so the
  total stays 7. Register **every** `lib/features/iptv/` file, zeros included
  (the settings follow-up precedent). Keep the token-call floor.
- **Theme surface:** list exact per-directory patterns that both
  `theme_rendered_set.py` and `measure_theme_surface.sh` accept, and verify
  every new file is included.
- Never delete an assertion to make a move pass.

## Definition of done

1. **The facade.** `iptv_results_view.dart` (at most 400 lines, formatted)
   holds `IptvResultsView`, `IptvResultsViewState` (lifecycle, interfaces,
   section wiring, `build`), and forwarders for `landingCategoryFor`,
   `applyStoredLocalCategoryOrder` and `loadBytesLabel`. `main.dart` and the
   tests compile unchanged.
2. **Guard.** `lib/features/iptv/` is a registered feature, with the
   `legacy_iptv/` bridge exact path, 500-line files, the 400-line facade at
   the end, and `TEMP(iptv)` rejection.
3. **Checks:** the manifest checker passes with self-tests, and every
   characterization test passes unchanged.
4. **Analyzer and tests:**
   - no new diagnostics and no lint suppressions;
   - gate 2 passes against `iptv/base.jsonl` and `iptv/gate1.jsonl`.
5. **CI:**
   - format and analyze cover `lib/features/iptv` and the facade;
   - `dev/tool/ci_behavior_tests.txt` gains the IPTV tests and the
     characterization tests, as concrete paths;
   - the known-failure list gains nothing new;
   - CI passes on `private`.
6. **Progress records:**
   - the step commits and each section's ownership;
   - the bridge, Riverpod and localization exceptions with exit milestones;
   - any contract verified only by a source guard, as **pending device
     verification**: the preview plane, D-pad, native preview and startup
     launch on Android TV.
7. Stop after gate 2 and report.

## Explicitly not in scope

- Other IPTV files (`iptv_service.dart`, `iptv_catalog_db.dart`, the guide,
  zap and player code, other `lib/widgets/iptv/*` widgets).
- Converting the 7 bare radii to shape tokens (a visual change).
- Riverpod state, performance work (the first-open hang), and bug fixes.
  Record any bug you find under "Found, not fixed".

## Progress

(empty)

## Found, not fixed

(none yet)
