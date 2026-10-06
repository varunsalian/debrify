# Settings widgets library refactor — plan

Written 2026-10-06 on `refactor/settings-widgets`, cut from `refactor/codebase`
at `0cb50df7`. Follow [AGENTS.md](../../AGENTS.md).

Read first: `detail-showcase-plan.md` (closest template: a widget library behind
a pure re-export facade, format-only original R, manifest-driven source reader,
dormant completion guards), `spotlight-board-plan.md`, `catalog-detail-plan.md`
and the Progress sections of those three. This plan reuses their technique,
checker (`check_verbatim_moves.py` with a per-feature manifest/config),
`suite_evidence.py`, gate procedure and Linux handoff, and states only what
differs.

**Execution.** Own git worktree
`/Users/varunbsalian/Documents/Projects/debrify-wt/settings-widgets` on
`refactor/settings-widgets`. Commit after every step; never push, merge or
switch branches; gate commits contain `gate`. Evidence is written **only**
under `refactor-evidence/settings_widgets/`. **Every manifest run passes an
isolated `--parser-package`** inside this worktree's ignored `.dart_tool/`
(copy, then delete any `*.dill` in the copy), including self-tests and every
other feature's manifest. Four other refactors run in sibling worktrees at the
same time (Stremio TV screen, its local-catalogs dialog and tuner, the edit
profile screen): `suite_evidence.py` runs in this worktree are serialized with
each other and with commits, a timeout under load is rerun, never recorded,
and the known load-sensitive flakes (WebDAV shard tests, the self-profile PIN
180 ms settle) are rerun in isolation with a NOTE, never allowlisted.

## Goal

`lib/screens/settings/widgets/settings_widgets.dart` is 2,835 lines
(unformatted; 2,847 after `dart format`): 15 import directives, no `part`
files or exports, **47 public top-level names**, 11 private declarations
(5 States, `_SettingsSwatches`, three skeleton widgets, `_buildSettingsPageTheme`)
and 3 private top-level variables (the page-theme memo). It is the shared
design vocabulary of every settings surface: tokens, row specs, the page theme
and route/dialog wrappers, page chrome, the Connections grid, tiles, toggles,
dropdowns, TV choice tables, the loading skeleton and the legacy-mode dialog.

Split it **move-only** into a new feature, `lib/features/settings_widgets/`,
and turn the original path into a **pure re-export facade** exporting exactly
the 47 names. Unchanged: widget trees, runtime type names, keys, `const`
placement, constructors, defaults, focus-node ownership, DPAD neighbour wiring,
the theme memo, and every lifecycle method.

**Callers stay unchanged.** 138 files import the original path: ~50 settings
pages under `lib/screens/settings/`, `lib/screens/settings_screen.dart`,
`lib/main.dart` (`show pushSettingsPage`), `app_theme_page.dart`
(`show SettingsSectionLabel`), `collection_editor_screen.dart`, the completed
features `settings` (~30 files), `playback_settings` (9) and `iptv_settings`
(12), and 16 test files. No importer uses a prefix or `hide`. Because the
facade re-exports every original public name and declares nothing, every
importer compiles and resolves to the same declarations without edits.

**Why a new feature behind a facade.**
- `lib/features/settings/` is a **completed** migration (`SETTINGS_COMPLETE`,
  its own manifest, size exceptions and facade rules keyed to
  `settings_screen.dart`). Adding a second source there would reopen its
  completed guard and couple two independently reviewed manifests; the three
  settings features would also start importing a sibling feature's
  presentation (`settings` ↔ `playback_settings`/`iptv_settings` cross-imports
  are banned today).
- `lib/ui/core/` is rejected: the library reads two legacy services
  (`MainPageBridge`, `ProfileBootstrap`) and launches URLs, and `ui/core` must
  not import services or features.
- A feature folder gains the architecture checker, CI format and the analyzer
  allowlist, none of which cover `lib/screens/settings/widgets` today.

**Not a playback seam.** No player, launcher, http, storage, preference or
database import. Platform/service touchpoints are exactly three and move
verbatim behind exact `show` imports (Contract 6).

| Temporary exception | Exit |
| --- | --- |
| `MainPageBridge` / `ProfileBootstrap` type-and-static imports via `PRESENTATION_BRIDGE_IMPORTS` `show` entries | A sidebar-focus callback and a legacy-reason value injected by the settings composition root |
| `launchSettingsUrl` calls `url_launcher` from presentation (AGENTS: widgets must not invoke native services) | A link-launcher port wired at composition |
| Legacy English text (row specs, headers, dialog) | Localization migration |
| `kSettings*` legacy color constants unused by `lib/` (pinned by `legacy_pins_test`) | Removal with the legacy-theme pins (Found 1) |

No size exception is needed: every destination is ≤ 500 lines.

## Public surface (unchanged, importable from the facade)

The 47 names, in original order:

- Tokens (12): `kSettingsBg`, `kSettingsAccent`, `kSettingsAccent2`,
  `kSettingsPanel`, `kSettingsPanel2`, `kSettingsGreen`, `kSettingsRed`,
  `kSettingsAmber`, `kSettingsLine`, `kSettingsDim`, `kSettingsDim2` (the last
  three are non-`const` `final`s) and `kSettingsMaxWidth`.
- `WebDavSyncPendingBadge`, `settingsInitialsFor`, `SettingsRowContent`,
  `SettingsRows`, `launchSettingsUrl`, `settingsPageTheme`,
  `pushSettingsPage`, `showSettingsDialog`, `SettingsPageScaffold`,
  `SettingsPageHeader`, `SettingsBannerTone`, `SettingsInfoBanner`,
  `SettingsBackground`, `SettingsHeader`, `SettingsSectionLabel`,
  `ConnectionInfo`, `settingsConnectionNeedsAttention`,
  `settingsConnectionIsReady`, `ConnectionsSummary`, `ConnectionCard`,
  `SettingsSection`, `SettingsLookHero`, `SettingsTile`, `SettingsToggleTile`,
  `TvUiScaleChoice`, `kTvUiScaleChoices`, `tvUiScaleLabel`,
  `TvRenderQualityChoice`, `kTvRenderQualityChoices`, `tvRenderQualityLabel`,
  `SettingsSelectOption`, `SettingsSelectDropdown`, `SettingsInfoTile`,
  `SettingsSkeleton`, `showLegacyModeInfoDialog`.

The step 0 inventory confirms the count with the analyzer (every public
top-level declaration of R) and fails if it is not 47. The facade holds only
`export '…' show …` directives naming exactly these names, plus comments: no
imports, declarations or aliases. A test pins the exported namespace to exactly
the 47 names (the `detail_showcase_surface_test` pattern, with a declaration
regex that also matches top-level functions, `final`/`const` variables, enums
and `abstract final class`).

## What it contains (original lines at `0cb50df7`; after the format commit the manifest is authoritative)

| Orig | Area |
| --- | --- |
| 1–15 | imports |
| 17–39 | token doc + 12 tokens |
| 41–72 | `WebDavSyncPendingBadge`, `settingsInitialsFor` |
| 74–454 | `SettingsRowContent`, `SettingsRows` (~60 specs), `launchSettingsUrl` |
| 456–744 | `settingsPageTheme`, the three memo variables, `_buildSettingsPageTheme`, `pushSettingsPage`, `showSettingsDialog` |
| 746–905 | `SettingsPageScaffold`, `SettingsPageHeader`, `SettingsBannerTone`, `SettingsInfoBanner` |
| 907–1074 | `SettingsBackground`, `SettingsHeader`, `SettingsSectionLabel` |
| 1076–1108 | `ConnectionInfo`, `settingsConnectionNeedsAttention`, `settingsConnectionIsReady` |
| 1110–1430 | `ConnectionsSummary` + State (12 owned focus nodes, DPAD graph) |
| 1432–1718 | `ConnectionCard` + State (key routing, sidebar hand-off, reveal) |
| 1720–1800 | `SettingsSection` |
| 1802–1984 | `SettingsLookHero` + State, `_SettingsSwatches` |
| 1986–2250 | `SettingsTile` + State |
| 2252–2420 | `SettingsToggleTile` + State |
| 2422–2492 | TV screen-size and rendering choice tables and labels |
| 2494–2613 | `SettingsSelectOption`, `SettingsSelectDropdown` |
| 2615–2678 | `SettingsInfoTile` |
| 2680–2777 | `SettingsSkeleton`, `_SkeletonHeader`, `_SkeletonSection`, `_SkeletonTile` |
| 2779–2835 | `showLegacyModeInfoDialog` |

**Resources.** Owned focus nodes: the 12 in `_ConnectionsSummaryState` (11
`late final` created in `initState`, `_mediaServersFocusNode` field-initialized;
`dispose` releases all 12 in a fixed order, then `super.dispose()`);
`_ConnectionCardState._wrapNode`; and the lazily created `_ownNode` of
`_SettingsLookHeroState`, `_SettingsTileState` and `_SettingsToggleTileState`
(created only when the widget's `focusNode` is null; a supplied node is
borrowed and never disposed). No timer, controller, ticker, subscription or
`GlobalKey`. One post-frame callback (`ConnectionCard._focusAndScroll`). One
process-wide mutable memo (`_settingsThemeBase`/`_settingsThemeApp`/
`_settingsThemeCache`).

## Contracts that must not change

Pinned by behaviour tests and/or source guards. Guards read whole bodies,
comments included, through `test/support/settings_widgets_source.dart`, a
**manifest-driven** reader frozen at (b) (Step 0 item 5).

1. **Public surface** as above; each name declared in exactly one destination
   and re-exported once; importers unchanged.
2. **Connections DPAD graph.** For both `wide` (`maxWidth > 520`) and narrow
   layouts, and each combination of `mediaServers` and `mdblist` present or
   absent, every card's `left/right/up/downNeighbor` and `isLeftColumn` is
   exactly the original (including the un-parenthesised
   `mediaServers != null ? … : wide ? … : …` tracking `upNeighbor`). The
   twelve nodes keep their debug labels, creation points and dispose order;
   `firstCardFocusNode` is borrowed (never disposed). Tests drive real arrow
   keys through every edge of every variant and record the focused card.
3. **ConnectionCard key routing.** Only `KeyDownEvent` is handled (repeat and
   up events are ignored); an arrow with a neighbour requests focus on it and
   schedules one post-frame `tvRevealMinimal(target.context!, duration:
   _motion.scaled(200 ms))` guarded by `target.context != null`; left with no
   neighbour in the left column calls `MainPageBridge.focusTvSidebar!()` only
   when it is non-null, else is ignored; every other case returns `ignored`.
   `_motion` is resolved in `didChangeDependencies`. `_focused` is read live
   from `_wrapNode.hasFocus` (descendant-inclusive); `onFocusChange` and hover
   only `setState`. `onTap` awaits `info.onTap()`. Tests: sidebar callback
   called once / not at all; repeat ignored; reveal scrolls a vertical
   ancestor after one frame; a theme with a scaled tempo changes the reveal
   duration observed through the scroll animation.
4. **Tiles.** `SettingsTile`, `SettingsToggleTile`, `SettingsLookHero`: own
   node only when none is supplied, disposed with the State; supplied nodes
   stay usable after unmount. `SettingsTile(enabled: false)`:
   `canRequestFocus: false` (DPAD traversal skips it), `onTap: null`,
   `Opacity 0.45`, no hover light. Live `_focused` (the stale-focus contract of
   `settings_single_focus_test`). Toggle: the row InkWell is the only focus
   stop (`Switch` under `ExcludeFocus`), tap/OK calls `onChanged(!value)`.
   `.spec` factories copy icon/title/subtitle with the documented subtitle
   override. `SettingsLookHero` shows swatches only at `maxWidth >= 390`.
   Under the Spotlight look with parallax focus expression, a lit row paints
   the inverse plate (goldens).
5. **Page theme and routes.** `settingsPageTheme` returns the **identical**
   cached `ThemeData` while both `Theme.of(context)` and
   `AppThemeScope.of(context)` are identical, and rebuilds when either changes;
   `pushSettingsPage` wraps the **route builder** in
   `Theme(data: settingsPageTheme(ctx))`, so a dialog opened from the pushed
   page inherits the settings palette; `showSettingsDialog` applies the theme
   to the dialog and forwards `barrierDismissible`. The memo stays one
   process-wide library-private state in one file.
6. **Service/platform touchpoints**, verbatim: `launchSettingsUrl` →
   `launchUrl(Uri.parse(url))` (test through a fake `UrlLauncherPlatform`);
   `showLegacyModeInfoDialog` reads `ProfileBootstrap.legacyReasonSummary` and
   autofocuses OK, which pops; the sidebar hand-off above. A guard bans any
   other `lib/services/`, `package:http`, `shared_preferences`, `sqflite`,
   storage, player or launcher import in the feature and facade.
7. **Pure helpers** (table tests): `settingsInitialsFor` (two words, `&`
   separator, internal capitals, single short word, empty → `?`),
   `settingsConnectionNeedsAttention` (each keyword, case-insensitive,
   disconnected → false), `settingsConnectionIsReady`, `tvUiScaleLabel` and
   `tvRenderQualityLabel` (each choice and the fallback), choice-table order.
8. **Rendering.** Element tree, keys, `const`, private runtime type names,
   `SettingsSection` rule model / dividers between children only / blurb,
   `SettingsBackground` and `SettingsHeader` Spotlight vs other looks,
   `SettingsInfoBanner` tones, `SettingsSelectDropdown` (stale value renders an
   empty field without asserting; `null` selections are not forwarded; the
   selected subtitle echoes below), `SettingsSkeleton`. Goldens pin these.

## Destination layout

All under `lib/features/settings_widgets/presentation/`, flat (no
`application/`, `data/` or bridge folder: there is no state, I/O or playback to
separate). Sizes are estimates after formatting, with imports; each file is
measured in its creation commit and must be ≤ 500 (checker-enforced). Within a
file, declarations keep their original relative order.

| File | Contents | ≈ |
| --- | --- | --- |
| `settings_tokens.dart` | token doc comment + 12 tokens | 30 |
| `settings_pending_badge.dart` | `WebDavSyncPendingBadge` | 25 |
| `settings_rows.dart` | `SettingsRowContent`, `SettingsRows` | 380 |
| `settings_links.dart` | `launchSettingsUrl` (the only `url_launcher` import) | 10 |
| `settings_page_theme.dart` | `settingsPageTheme`, memo variables, `_buildSettingsPageTheme`, `pushSettingsPage`, `showSettingsDialog` | 295 |
| `settings_page_chrome.dart` | `SettingsPageScaffold`, `SettingsPageHeader`, `SettingsBannerTone`, `SettingsInfoBanner` | 165 |
| `settings_root_chrome.dart` | `SettingsBackground`, `SettingsHeader`, `SettingsSectionLabel` | 175 |
| `settings_connection_info.dart` | `ConnectionInfo`, the two predicates | 40 |
| `settings_connections_summary.dart` | `ConnectionsSummary` + State | 345 |
| `settings_connection_card.dart` | `settingsInitialsFor`, `ConnectionCard` + State | 310 |
| `settings_section.dart` | `SettingsSection` | 85 |
| `settings_look_hero.dart` | `SettingsLookHero` + State, `_SettingsSwatches` | 190 |
| `settings_tile.dart` | `SettingsTile` + State | 270 |
| `settings_toggle_tile.dart` | `SettingsToggleTile` + State | 175 |
| `settings_tv_choices.dart` | screen-size and rendering choice tables and labels | 80 |
| `settings_select_dropdown.dart` | `SettingsSelectOption`, `SettingsSelectDropdown` | 125 |
| `settings_info_tile.dart` | `SettingsInfoTile` | 70 |
| `settings_skeleton.dart` | `SettingsSkeleton` and its three private widgets | 105 |
| `settings_legacy_mode_dialog.dart` | `showLegacyModeInfoDialog` | 65 |

`settingsInitialsFor` moves to the card file, its only caller (still exported
by the facade). `ConnectionInfo` and the predicates get their own file so the
summary → card → info import graph is acyclic. The import graph inside the
feature is a DAG (step 0 deps report draws it; the source guard rejects a
cycle).

**No aliases.** After the split no private declaration is referenced from
another file: the memo variables and `_buildSettingsPageTheme` stay with
`settingsPageTheme`, `_SettingsSwatches` with `SettingsLookHero`, the skeleton
privates with `SettingsSkeleton`, every State with its widget. Comments that
name another file's private (`_SettingsTileState._focused` in the card,
look-hero and toggle docs) stay verbatim. The manifest therefore registers
`unchanged` leaves only; `type_aliases` is empty and the step 0 probe proves
there is no cross-file private reference (the analyzer reports none in the
split probe).

**Imports.** Each destination writes sorted `package:debrify/…` imports of
only what it uses (plus `package:flutter/…`, `package:url_launcher/…` in the
links file). Service imports are exact `show` lists registered per file in
`PRESENTATION_BRIDGE_IMPORTS`: `settings_connection_card.dart` →
`services/main_page_bridge.dart show MainPageBridge`;
`settings_legacy_mode_dialog.dart` →
`services/profiles/profile_bootstrap.dart show ProfileBootstrap`. Any
`unused_import`/`unnecessary_import` is a new diagnostic and fails.

**Guard rules** (step 1, `check_search_architecture.py`, additive and keyed by
this feature): `settings_widgets` in `FEATURES`;
`SETTINGS_WIDGETS_FACADE = "lib/screens/settings/widgets/settings_widgets.dart"`,
`SETTINGS_WIDGETS_COMPLETE = False`; the feature never imports its facade or
any `lib/screens/` file; no `lib/services/` import except the two registered
`show` entries (exact names); no `url_launcher` import except in
`settings_links.dart`; playback/storage/http bans (Contract 6); no import
either way between `settings_widgets` and `settings`, `playback_settings`,
`iptv_settings` (they keep importing the facade) except `<other>/models/`;
500-line cap on every feature file, no exceptions.

At step 4 (`SETTINGS_WIDGETS_COMPLETE = True`): `main()` adds the facade;
`COMPOSITION_ROOTS` entry with comment; pure-export rule (only `export`
directives and comments, exactly the 47 names, every target under
`package:debrify/features/settings_widgets/presentation/`); the measured facade
cap; `TEMP(settings_widgets)` rejected everywhere. Tests run the real `main()`
on a temporary tree copy and must reject: missing facade; a facade declaration
or import; facade over cap; a missing or extra exported name; a feature
back-import of the facade; a `settings` feature import; an unshown or
over-shown service import; a `url_launcher` import outside the links file; a
`TEMP` marker. The unmodified tree passes.

## Technique

As in the detail-showcase plan, plus:

1. **Two step 0 originals.**
   - **(a) Format-only commit** (`style(settings-widgets): format the original
     settings widgets`) is R: the manifest `--baseline`, relocation comparison
     and hash rule. `dart format` makes 5 hunks, 2,835 → 2,847 lines,
     idempotent. Tokens differ only by **exactly 2 AST-identified optional
     trailing commas** (`FocusNode(debugLabel: 'settings-media-servers',)` in
     `_ConnectionsSummaryState`, and the `mediaServers` `ConnectionCard(…)`
     call). Add `dev/tool/settings_widgets_format_proof.py`, a wrapper over the
     existing AST adapter used by `detail_showcase_format_proof.py` (do not
     modify the other features' proof scripts). Inputs: `--original`,
     `--formatted`, isolated `--parser-package`, per-run kernel path,
     `--output`. It lists each comma by node and owner, **expects exactly 2**,
     and asserts each mutation changes its input before requiring that
     edited-comment, trailing-comment, edited-literal (`'settings-media-servers'`)
     and non-optional-comma negatives reject. 0 format-induced diagnostics are
     expected; any observed are recorded by identity, never fixed. The commit
     raises `dev/tool/file_size_baseline.txt` 2835 → 2847 by hand and updates
     nothing else; later steps only lower it and step 3 removes it.
   - **(b) Characterization checkpoint** (`test(settings-widgets): step 0
     original-code characterization checkpoint`): application files unchanged
     from R (Progress proves `git rev-parse <b>:lib` = `<R>:lib`, likewise
     `pubspec.yaml`/`pubspec.lock`); adds frozen tests, harness, source reader,
     checker manifest/config, format proof and macOS goldens. No application
     seam is expected; if one proves necessary, the spotlight seam-checkpoint
     rule applies and R moves to it everywhere.
2. **Strict-lint baseline by identity.** Analyze R under
   `lib/features/analysis_options.yaml` in a detached worktree in ignored
   `.dart_tool/`, qualifying import URIs only; record every diagnostic by
   (rule, symbol, message), separating qualification-induced
   `directives_ordering` infos. A throwaway **split probe** applies exactly the
   manifest's split and imports and must report no new rule identity (no
   `library_private_types_in_public_api`, no unused/unnecessary import, no
   undefined name). Combine baseline and probe by maximum, never sum. No
   suppression, `const`, key or constructor change.
3. **Whole declarations move verbatim** with docs and States. The verbatim
   checker compares comments: **never reword one**, including the `[SettingsRows]`,
   `[SettingsPageScaffold]`, `[SettingsBackground]`, `[SettingsTile]`,
   `[SettingsSelectDropdown]`, `[SettingsRootHeader]` and
   `_SettingsTileState._focused` references that now cross files. Nothing is
   hoisted, reordered, wrapped, keyed or `Builder`-ed.
4. **Intermediate original.** Until step 3 the original keeps the unmoved code,
   imports the feature files it needs and `export … show`s each moved public
   name, so importers compile at every checkpoint. It never declares a
   forwarder. Its now-unused imports are removed in the same step that moves
   their last user (no `unused_import` at any checkpoint).

## Steps

| # | Work | Contracts |
| --- | --- | --- |
| 0 | Baseline; (a) and `base-fmt`; deps report, manifest, config; lint/split probes; harness, characterization, macOS goldens, (b); CI list; inventory; Linux script; step 0b review | Nothing moves |
| L | Linux originals in a separate commit (Claude captures; execution verifies and commits). **Blocking before step 1.** | — |
| 1 | Guard registration; tokens, badge, rows, links, page theme, page chrome, root chrome; shape/theme registration begins | 1, 5, 6, 8 |
| 2 | Connection info, summary, card; section; look hero; tile; toggle tile. **Full-suite gate 1.** | 2, 3, 4, 7, 8 |
| 3 | TV choices, select dropdown, info tile, skeleton, legacy dialog; the original becomes the pure facade; size baseline entry removed | 6, 7, 8 |
| 4 | `SETTINGS_WIDGETS_COMPLETE`, facade rules/cap, `checks.yml`, CI lists. **Full-suite gate 2.** | All |

### Step 0

1. **Baselines.** `settings_widgets/base` (`suite_evidence.py run`, full suite,
   `paths` empty, flags recorded, plus whole-repo analyzer) on the untouched
   head with tree/SDK provenance (Flutter 3.44.8 / Dart 3.12.2);
   `settings_widgets/base-fmt` after (a), equal by identity.
2. **Dependency report** (`docs/refactoring/settings-widgets-deps.md`): per leaf
   (declaration, private top-level item, comment fragment) its destination,
   each cross-file **public** reference, each service type and `show` entry,
   State reads of `widget`/`context`/`mounted`, the feature import DAG, and a
   wiring checklist; per importer (lib and test) the names it uses (proving
   all 47 remain reachable through the facade).
3. **Checker.** `dev/tool/settings_widgets_manifest.tsv` (LF only) and
   `settings_widgets_checker_config.json` (sections engine, `unchanged` only,
   empty `type_aliases`, `self_test_module` with real-config fixtures);
   `--relocate lib/screens/settings/widgets/settings_widgets.dart=lib/features/settings_widgets/`.
   Negatives: renamed private class; reworded comment; new `const` or key;
   reordered `dispose` in `_ConnectionsSummaryState`; a swapped neighbour
   argument; `canRequestFocus: widget.enabled` dropped; `ExcludeFocus` removed;
   the memo keyed on `base` only; a declaration duplicated in two
   destinations; a destination missing a manifest leaf. Shared checker
   modules are edited only through opt-in config keys (none expected); every
   other manifest's self-tests stay passing unchanged.
4. **Harness** (`test/support/settings_widgets_fixture.dart`):
   `AppThemeScope` with a named legacy look and the Spotlight look (parallax
   focus expression), pinned `tester.view` size, DPR 1.0, `en-US`, text scale
   1.0; host-owned focus nodes disposed in teardown; recording callbacks;
   `MainPageBridge.focusTvSidebar` and platform flags saved/restored in
   teardown; `ParallaxTravel.resetForTest()` in setUp/teardown where a
   `ParallaxFocus` row is focused; a fake `UrlLauncherPlatform` restored in
   teardown; bounded pumps (no `pumpAndSettle` where a post-frame reveal or
   route animation is timed); braces in tests. Prove it on R first.
5. **Characterization tests** under
   `test/features/settings_widgets/presentation/`, frozen in (b), importing
   **only the facade path** so they are unchanged at every checkpoint, each
   passing in a detached worktree of (b) before any move:
   `settings_connections_dpad_test` (2, 3), `settings_tiles_focus_test` (4),
   `settings_page_theme_test` (5), `settings_touchpoints_test` (6),
   `settings_helpers_test` (7), `settings_widgets_render_test` (8),
   `settings_widgets_surface_test` (facade namespace = 47 names) and
   `settings_widgets_source_contract_test`. The frozen reader is
   **manifest-driven**: for each registered declaration it reads the original
   or the destination the manifest names (if created) and fails when neither
   or both hold it. Source guards cover what behaviour tests cannot observe:
   the 12-node dispose order and debug labels, `_motion` resolved in
   `didChangeDependencies`, borrowed nodes never disposed, the memo variables
   private to one file, the service `show` lists. Final-topology requirements
   (every destination exists, the original is a pure 47-name facade) are
   **dormant until** `SETTINGS_WIDGETS_COMPLETE = True` (absent counts as
   false). The step 0b review proves the guards pass on (b), fail on a
   declaration deleted from the original, and that the final-topology checks
   fire on a temporary copy of (b) with the flag set.
6. **Goldens.** The five `settings_spotlight_*` goldens (macOS and `linux/`)
   stay untouched and must keep passing. New deterministic scenes from (b),
   `settings_widgets_goldens_test.dart` →
   `test/goldens/settings_widgets/{macos,linux}/`, using a **direct widget
   harness** (no settings screen, no services): `tv_legacy_gallery`
   (1920×1080, legacy look: page header, info banners in all four tones,
   section with tile/toggle/info tile/disabled tile, select dropdown with
   subtitle, one tile focused); `tv_spotlight_gallery` (same content,
   Spotlight look, a focused tile painting the inverse plate, look hero with
   swatches); `wide_connections` (ConnectionsSummary at 1280 wide with
   `mediaServers` and `mdblist`, one card focused); `phone_connections_skeleton`
   (390×844 narrow ConnectionsSummary without the optional cards, then
   `SettingsSkeleton`). Every golden asserts each promised widget's rect
   overlaps the capture bounds before matching. Fixed pump durations, no
   `pumpAndSettle` across focus animations. Execution captures macOS into (b).
   **Claude captures Linux** from (b) in the calibrated `debrify-flutter:3.44.8`
   linux/amd64 Docker image (clone under `$HOME`, `flutter pub get` in the
   container, verify `HEAD` and hashes, double capture in reversed order with
   identical hashes); execution verifies hashes and provenance and commits them
   as step L; Linux is strict from L on.
7. **CI list.** Add to `dev/tool/ci_behavior_tests.txt` the direct-importer
   tests not yet listed (step 0 checks each of the 16 importing tests),
   every new test and the golden test. Known failures only as observed in
   `base`, by identity, under a dated `# settings_widgets step 0:` comment;
   none are expected.
8. **Source-text inventory.**
   - **Shape:** `shape_manifest_test.dart` lists the original at 10. Step 0
     records each bare radius by declaration (expected among
     `SettingsPageHeader`, `ConnectionCard`, `SettingsSection`, `SettingsTile`
     tag chip, `SettingsSelectDropdown`, `_SkeletonSection`, `_SkeletonTile`).
     Register each destination in `kExtractedShapeResidue` (never
     `kShapeResidue`) **in the commit that creates it**, zero-count files
     included; every checkpoint asserts the slice total of exactly 10 (facade
     ends at 0). The 488 token floor is unaffected (zero slack).
   - **Theme:** `theme_surface_manifest.txt` `settings` surface gains an
     explicit `lib/features/settings_widgets/presentation/*.dart` pattern (no
     globstar); `lib/screens/settings/widgets/*.dart` still covers the facade.
     Measure before and after: unchanged classification.
   - **Light ink / primary lists, profile and stale-runtime guards:** step 0
     greps every test and tool that globs `lib/screens/settings`,
     `lib/screens/**` or names this file, and records for each whether moved
     code leaves its scope; any guard that would silently lose coverage gets
     the feature path added (purpose preserved), never removed.
   - Verify unaffected: `theme/source_guard_test`, `profile_source_guard_test`,
     `stale_runtime_guard_test`, `storage_member_map.tsv`,
     `theme/legacy_pins_test` (still imports the facade). Historical design
     docs naming the path stay as they are.
9. **Linux capture script** (`dev/tool/capture_settings_widgets_linux_goldens.sh`,
   modelled on the detail-showcase script): `set -euo pipefail`; resolves (b)
   and R by **exact subject** over all of `git log --format='%H %s'` (awk
   prints every match, no early exit) and requires exactly one; requires (b)'s
   `lib`/`pubspec.yaml`/`pubspec.lock` hash-equal to R's; uses only (b)'s
   tests; checks Flutter 3.44.8 on Linux; captures twice in reversed order,
   requires identical hashes, verifies strictly, writes hash and revision
   evidence.

**Step 0b review** (on (b), before any move). Each ORIGINAL-only mutation must
be rejected by a real **assertion failure** (not a compile error), run one at a
time on a scratch copy of (b) and recorded with the failing test name:
a swapped wide/narrow neighbour (one per variant: plain, `mediaServers`,
`mdblist`, both); the tracking `upNeighbor` parenthesised differently; sidebar
hand-off removed / called when null; `KeyRepeatEvent` handled; reveal not
scheduled; `canRequestFocus: true` on a disabled tile; `onTap` kept on a
disabled tile; `ExcludeFocus` removed; toggle `onChanged(widget.value)`; own
node used even when one is supplied; look-hero swatch threshold 390 → 380;
memo keyed on `base` only; `pushSettingsPage` theming the page instead of the
route builder; `barrierDismissible` dropped; a needs-attention keyword
removed; `settingsInitialsFor` capital rule removed; a label fallback changed;
dropdown forwarding `null`; a golden-visible radius change. Mutations that can
only be caught by a source guard (dispose order, debug label, `_motion` hook)
are classified **S** and proven against the guard separately. Any surviving
mutation gets a 0b test before extraction. Record `base3` at (b): only added,
passing identities.

### Per step and gates

The detail-showcase procedure with `--baseline <R>`. Every step runs: every
integrated manifest plus this one, with self-tests and an isolated
`--parser-package`; the per-symbol relocation comparison (zero additions);
architecture and sizes (lowering the ratchet); shape (10) and theme; CI format
and scoped analyzer with `check_analyzer_allowlist.py` (no new entry is
expected); the strict comparison by identity; LF manifests and staged diff;
the focused characterization set plus the 16 existing importing tests and the
five `settings_spotlight` goldens. No golden is ever regenerated against moved
code. Gates run on committed trees with no untracked inputs against the latest
`settings_widgets/` base; gate 2 also compares with gate 1. Never `--record` a
regression.

**Linux replay.** At gate 2's commit Claude replays all four new goldens
**and** the five `settings_spotlight` goldens in the calibrated Docker image,
strict, no regeneration, recording provenance (SHA, tree hashes, image ID,
Flutter version) and unchanged PNG hashes.

**Step 4** also adds the facade and `test/support/settings_widgets_*.dart` to
the `checks.yml` format list and the facade to the analyze list — **paths
before `| tee analyze.txt`, never after** — and records the facade's `wc -l`
breakdown (export directives + comments = total), the chosen cap, and final
per-file sizes.

### Integration (Claude)

Merged by Claude into `refactor/codebase` after the parallel Stremio TV and
edit-profile branches, integrating shared files **semantically, by union**:
`check_search_architecture.py` (`FEATURES`, `PRESENTATION_BRIDGE_IMPORTS`,
`COMPOSITION_ROOTS`, `main()` facade paths, every `*_COMPLETE`),
`shape_manifest_test.dart`, `theme_surface_manifest.txt`,
`ci_behavior_tests.txt`, `ci_behavior_known_failures.txt`,
`analyzer_allowlist.txt`, `checks.yml` (paths before `| tee`),
`file_size_baseline.txt`. Then, on the merged committed tree: every manifest
with self-tests (isolated parser packages); architecture, size, shape, theme;
CI format, analyze and allowlist; a full-suite comparison; the Linux golden
replay.

## Definition of done

1. **Facade:** pure re-export of exactly the 47 names, formatted, within its
   measured cap; all 138 importers compile unchanged.
2. **Feature:** 19 destinations, each ≤ 500 lines, no size exception, no
   cross-file private, acyclic imports, no runtime type name change.
3. **Guard:** feature, facade rules and cap, exact `show` service imports, the
   `url_launcher` confinement, the playback/storage/http and settings-family
   cross-import bans, each proven through the real checker.
4. **Tests:** all manifests with self-tests pass; every characterization test
   and guard from (b) passes unchanged; macOS and Linux goldens (four new plus
   the five `settings_spotlight`) match, with the completion Linux replay's
   provenance recorded.
5. **Diagnostics:** no new diagnostics, suppressions or allowlist entries.
6. **CI:** behaviour list holds the importing and new tests; shape slice
   totals 10 with 0 in the facade; theme surface unchanged; size baseline
   entry removed.
7. **Progress** records commits ((a) = R, (b), L, each step), and the
   end-of-series device checklist below as pending.
8. **Gate 2** passes against the latest base and gate 1. Then stop and report.

## Explicitly not in scope

Every settings page and layout that imports the library,
`dynamic_settings_builder.dart`, `AppThemeScope`/`AppTheme`, `ParallaxFocus`,
`tv_reveal`, `MainPageBridge`, `ProfileBootstrap`, Riverpod, localization, a
link-launcher or sidebar-focus port, and every bug fix or behaviour change
below.

## Decisions taken before design review

1. **Location:** new feature `lib/features/settings_widgets/presentation/`
   behind a pure re-export facade at the original path (not
   `lib/features/settings/`, not `lib/ui/core/`; reasons under Goal).
2. **No aliases:** the split leaves no cross-file private; nothing is renamed.
3. **Format-only original R** (5 hunks, 2 optional commas) so destinations are
   formatted without a second format pass; proof script per feature.
4. **Goldens:** four new direct-harness scenes covering both looks and TV/phone
   sizes, captured on macOS by execution and on Linux by Claude; the existing
   `settings_spotlight` goldens are the integration check through real pages.
5. **Service/platform touchpoints stay verbatim** behind exact `show` imports
   and one link file; their ports are a later milestone (exceptions table).
6. **Dead or single-use public names stay public and move verbatim**
   (`kSettings*`, `settingsInitialsFor`); removal is out of scope.
7. **Importers are not edited**, including the two `show` importers and the
   three completed features.

## End-of-series device checklist (no device gate before merge)

- Android TV: D-pad through every Connections card in both column layouts,
  with and without media servers and MDBList; Left from the left column opens
  the TV sidebar; the reveal scroll keeps the focused card visible.
- Android TV: settings rows/toggles are one D-pad stop each; a disabled row is
  skipped; returning from a sub-page shows one cursor (stale-focus contract).
- Apple TV: the same rows with the Siri remote; hover is irrelevant there.
- Desktop/phone: hover lights rows; the look hero shows swatches when wide;
  dropdown menus open, take D-pad focus and close with Back.
- The legacy-mode dialog opens from the Profiles row and OK closes it; the
  community links open the browser.

## Found, not fixed

1. `kSettings*` (11 colors) are unused in `lib/` outside comments in
   `app_theme.dart`; only `theme/legacy_pins_test` reads them.
2. `settingsInitialsFor` is public with a single caller (`ConnectionCard`).
3. `launchSettingsUrl` ignores `launchUrl`'s `false` result and any exception.
4. `ConnectionCard`'s `MouseRegion` is not TV-gated (hover state is set but
   unused on TV).
5. `SettingsSelectDropdown` passes `initialValue` to a `FormField`; whether a
   parent's later `value` change updates the closed field is characterized as
   observed at step 0 and recorded here, not changed.
6. Import directives in the original are unsorted (`tv_reveal` before
   `services`, `package:debrify/models` last); destinations write sorted imports,
   which is formatting of new files, not a behaviour change.

## Progress

(Execution appends here.)
