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
(unformatted; 2,847 after `dart format`): 14 import directives, no `part`
files or exports, **60 AST top-level declarations**: **47 public names**, 10
private declarations (5 States, `_SettingsSwatches`, three skeleton widgets,
`_buildSettingsPageTheme`) and 3 private top-level variables (the page-theme
memo). It is the shared
design vocabulary of every settings surface: tokens, row specs, the page theme
and route/dialog wrappers, page chrome, the Connections grid, tiles, toggles,
dropdowns, TV choice tables, the loading skeleton and the legacy-mode dialog.

Split it **move-only** into a new feature, `lib/features/settings_widgets/`,
and turn the original path into a **pure re-export facade** exporting exactly
the 47 names. Unchanged: widget trees, runtime type names, keys, `const`
placement, constructors, defaults, focus-node ownership, DPAD neighbour wiring,
the theme memo, and every lifecycle method.

**Callers stay unchanged.** Resolved import directives give **132 importing
files: 117 under `lib/` and 15 under `test/`** (14 runnable test files plus the
helper `test/theme/surface_gallery.dart`, consumed by
`test/theme/goldens_test.dart` and `contrast_audit_test.dart`;
`shape_manifest_test.dart` names the path without importing it). The `lib/`
importers are the settings pages under `lib/screens/settings/`,
`lib/screens/settings_screen.dart`, `lib/main.dart` (`show pushSettingsPage`),
`app_theme_page.dart` (`show SettingsSectionLabel`),
`collection_editor_screen.dart` and the completed features `settings`,
`playback_settings` and `iptv_settings`. Step 0 regenerates this inventory
from import directives (not grep of the file name) and records it in the deps
report. No importer uses a prefix or `hide`. Because the
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
| `kSettings*` legacy color constants kept for compatibility: `kSettingsAccent`/`kSettingsPanel2` still feed two top-level `final` focus styles (`indexer_managers_settings_page.dart:21,25,842`, `iptv_settings_dialog_button_style.dart:11`) and `legacy_pins_test` pins all of them | Those styles become functions of context (Found 1) |

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
   only `setState`. `onTap` awaits `info.onTap()`.
   **Observation, not geometry:** an ignored arrow still moves focus through
   the app's default directional shortcuts, so focused-card identity alone
   cannot prove handled vs ignored. The harness therefore (a) installs an
   ancestor `Focus(onKeyEvent:)` recorder above the summary that sees exactly
   the events the card did **not** handle, and asserts handled/ignored per
   key and event kind (KeyDown, KeyRepeat, KeyUp); (b) pins each card's
   `left/right/up/downNeighbor` identity and `isLeftColumn` by reading the
   public `ConnectionCard` widget fields from the element tree, per variant,
   independent of traversal; (c) records the reveal through a recording
   `ScrollController` whose `ScrollPosition` subclass logs `animateTo`
   (target, duration, curve) and the `SchedulerBinding` phase it ran in:
   nothing is recorded synchronously with the key event, and the call happens
   during `SchedulerPhase.postFrameCallbacks` with the tempo-scaled 200 ms
   (`tvRevealMinimal` uses `animateTo` for a non-zero duration, `jumpTo` for
   zero, and neither when no reveal is needed — the fixture places the target
   so a reveal is needed);
   (d) drives the sidebar case for callback present/absent ×
   `isLeftColumn` true/false.
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
   `tvRenderQualityLabel` (each choice; table completeness against
   `TvRenderQuality.values` and order — its `'Automatic'` fallback is
   unreachable with a valid enum value, so it is pinned by the source guard,
   class **S**), choice-table order.
8. **Rendering.** Element tree, keys, `const`, private runtime type names,
   `SettingsSection` rule model / dividers between children only / blurb,
   `SettingsBackground` and `SettingsHeader` Spotlight vs other looks,
   `SettingsInfoBanner` tones, `SettingsSelectDropdown` (stale value renders an
   empty field without asserting; a `null` passed to the field's public
   nullable `onChanged` is not forwarded and returns normally; the selected
   subtitle echoes below), `SettingsSkeleton`. Goldens pin these.

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
cap; `TEMP(settings_widgets)` rejected everywhere. The settings-family ban is a
**direct implementation-import ban**: the checker examines physical directive
targets (`check_search_architecture.py:757`), so `settings`,
`playback_settings` and `iptv_settings` files that import the facade under
`lib/screens/` stay allowed, while a direct import of
`lib/features/settings_widgets/…` from them (or the reverse) is rejected; the
negative tests prove both. Tests run the real `main()`
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
   suppression, `const`, key or constructor change. (Round 1 probe at
   `8ccf2d8a`: zero errors/warnings, four pre-existing const infos.)
   **Per-symbol comparison tool.** `suite_evidence.py` records only
   (severity, file, rule, message) and relocates by file, so add
   `dev/tool/settings_widgets_diagnostics.py`: `record --rev <R>` analyzes a
   detached worktree of R (ignored `.dart_tool/`, strict options as above)
   and maps each diagnostic to its **owning top-level declaration** via the
   AST spans of the isolated parser package; `compare --rev <checkpoint>`
   does the same on the checkpoint's original-plus-destinations and fails on
   any (severity, rule, owner declaration, message) whose count exceeds the
   baseline maximum, ignoring only the recorded qualification-induced
   `directives_ordering` identities. File relocation for the whole-repo
   analyzer and test identities stays with
   `suite_evidence.py compare --relocate
   lib/screens/settings/widgets/settings_widgets.dart=lib/features/settings_widgets/`,
   run separately. Exact commands and outputs are recorded in Progress; the
   tool has fixture tests (a moved diagnostic passes, an added or
   re-owned one fails).
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
   empty `type_aliases`, `self_test_module` with real-config fixtures).
   (`--relocate` belongs to `suite_evidence.py compare`, not to this
   checker; see Per step.) Negatives: renamed private class; reworded comment; new `const` or key;
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
   **manifest-driven** and covers **all 60 AST declarations** by kind: classes
   (incl. `abstract final class`), the enum, top-level functions (incl.
   generic `pushSettingsPage<T>`/`showSettingsDialog<T>` and the arrow-bodied
   predicate), `const`/`final` variables (incl. generic `const List<…>`
   initializers) and the three uninitialized memo variables. For each
   registered declaration it reads the original or the destination the
   manifest names (if created) and fails when neither or both hold it.
   Boundaries come from a comment- and string-aware scanner (raw strings,
   interpolation, generics, `=>` bodies, `;`-terminated variables); a step 0
   tool test (`dev/tool/settings_widgets_reader_check.py`, isolated parser
   package) compares the reader's span for each of the 60 declarations with
   the analyzer's span at (b), and proves deletion and duplication rejection
   for one declaration of each kind, before the reader is frozen. Service
   `show` assertions are **staged by destination creation**: the original's
   imports (`settings_widgets.dart:6–7`) have no `show`, so the reader checks
   a `show` list only in a destination that exists. Source guards cover what behaviour tests cannot observe:
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
   swatches); `wide_connections` (ConnectionsSummary at 1280×900 with
   `mediaServers` and `mdblist`, one card focused); `phone_connections`
   (narrow ConnectionsSummary without the optional cards, on a **390×1000**
   surface — the summary alone measures ~953 px — so every card is inside
   the capture); `phone_skeleton` (`SettingsSkeleton` alone, 390×844). That
   is five scenes. Every golden asserts the rect of each promised widget
   (each named card, tile, banner, the hero swatches, the skeleton header and
   sections) overlaps the capture bounds before matching.
   **Determinism:** the default `flutter_test` font only (no font loading; the
   `JetBrainsMono` family falls back to it identically on both platforms) and
   no change to typography globals (any global the harness touches is saved
   and restored in teardown); fixed timeline per scene — build, one
   `pump()`, focus request through the public node, `pump()` then
   `pump(const Duration(milliseconds: 300))` as a deterministic **300 ms sample**
   of the snap/parallax spring (not a claim of settlement; the fake clock makes
   the sample identical on every run),
   and for the skeleton a fixed `pump(const Duration(milliseconds: 400))` of
   the `Shimmer` controller's fake clock; no `pumpAndSettle` (the shimmer
   repeats forever); dropdowns captured closed only. Scene order is
   controlled by `--dart-define=SETTINGS_WIDGETS_GOLDEN_ORDER=reverse`
   (default forward) read by the golden test, so the Linux script can capture
   in both orders and require identical hashes. Execution captures macOS
   into (b).
   **Claude captures Linux** from (b) in the calibrated `debrify-flutter:3.44.8`
   linux/amd64 Docker image (clone under `$HOME`, `flutter pub get` in the
   container, verify `HEAD` and hashes, double capture in reversed order with
   identical hashes); execution verifies hashes and provenance and commits them
   as step L; Linux is strict from L on.
7. **CI list.** Add to `dev/tool/ci_behavior_tests.txt` every runnable
   importing test not yet listed (six of the 14 are missing at `0cb50df7`;
   step 0 computes the exact set from the directive inventory), the helper's
   runnable consumers `test/theme/goldens_test.dart` and
   `test/theme/contrast_audit_test.dart` if missing (never the helper
   `surface_gallery.dart` itself), every new test and the golden test. Known failures only as observed in
   `base`, by identity, under a dated `# settings_widgets step 0:` comment;
   none are expected.
8. **Source-text inventory.**
   - **Shape.** The original is in `kShapeResidue`
     (`shape_manifest_test.dart:197`) with a **ceiling** of 10; the guard is
     `found > ceiling` (line 1413). Measured at `0cb50df7`: **7 bare radii**
     (orig 821, 1554, 1781, 2193, 2542, 2741, 2769) and **26 `app.shape.br`
     token calls**, which count toward the 488 floor (line 1448 counts tokens
     only over `kShapeResidue`, and line 1432 requires every `kShapeResidue`
     file to contain `app.shape.`). Allocation by destination (tokens / bare
     radii): `settings_page_theme` 15/0, `settings_page_chrome` 1/1,
     `settings_connection_card` 2/1, `settings_section` 1/1,
     `settings_look_hero` 2/0, `settings_tile` 2/1, `settings_toggle_tile` 2/0,
     `settings_info_tile` 1/0 — these eight go in **`kShapeResidue`** with
     their measured radius count as ceiling; `settings_select_dropdown` 0/1,
     `settings_skeleton` 0/2 and the other nine (0/0) go in
     **`kExtractedShapeResidue`**. Each entry is added in the commit that
     creates its file. The facade stays in `kShapeResidue` while it still
     contains a token call, its ceiling lowered at each step to its measured
     residue; in step 3, when `SettingsInfoTile` takes the last token call,
     it moves to `kExtractedShapeResidue` at 0. Every checkpoint measures and
     asserts: the token total over the slice is exactly 26 and the global
     floor count is unchanged (488 at the base, zero slack); the bare-radius
     total over the slice is exactly 7. Ceilings and measured counts are
     reported separately; the historical ceiling 10 is not an inventory.
   - **Theme:** `theme_surface_manifest.txt` `settings` surface gains an
     explicit `lib/features/settings_widgets/presentation/*.dart` pattern (no
     globstar); `lib/screens/settings/widgets/*.dart` still covers the facade.
     Measure before and after: unchanged classification.
   - **Scan scopes that would lose this code** (added in step 1, when the
     first file moves, purpose preserved): the log-redaction scan in
     `test/profiles/profile_source_guard_test.dart:344` (`print(` ban over
     `lib/screens/settings`) gains `lib/features/settings_widgets`;
     `dev/tool/light_ink_inventory.py` `PRIMARY` (line 62) gains
     `'lib/features/settings_widgets/presentation/'`, with before/after
     inventory output recorded. Step 0 greps every other test and tool that
     globs `lib/screens/settings`, `lib/screens/**` or names this file and
     records the result.
   - Verify unaffected (they scan all of `lib`): `theme/source_guard_test`,
     `stale_runtime_guard_test`; and `storage_member_map.tsv`,
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
removed; `settingsInitialsFor` capital rule removed; the screen-size label
fallback changed (the rendering fallback is unreachable, class S); the
dropdown's `if (v != null) onChanged(v);` replaced by the **compilable**
mutant `onChanged(v!);`, rejected by a `returnsNormally` assertion that
invokes the field's public nullable `onChanged` with `null` (deleting the
guard outright is a compile error and never counts as a proof); a
golden-visible radius change. Mutations that can
only be caught by a source guard (dispose order, debug label, `_motion` hook)
are classified **S** and proven against the guard separately. Any surviving
mutation gets a 0b test before extraction. Record `base3` at (b): only added,
passing identities.

### Per step and gates

The detail-showcase procedure with `--baseline <R>`. Every step runs: every
integrated manifest plus this one, with self-tests and an isolated
`--parser-package`; the per-symbol relocation comparison (zero additions);
architecture and sizes (lowering the ratchet); shape (7 radii / 26 tokens /
488 floor) and theme; CI format
and scoped analyzer with `check_analyzer_allowlist.py` (no new entry is
expected); the strict comparison by identity; LF manifests and staged diff;
the focused characterization set plus the 14 runnable importing tests,
`theme/goldens_test`, `theme/contrast_audit_test` and the
five `settings_spotlight` goldens. No golden is ever regenerated against moved
code. Gates run on committed trees with no untracked inputs against the latest
`settings_widgets/` base; gate 2 also compares with gate 1. Never `--record` a
regression.

**Linux replay.** At gate 2's commit Claude replays all five new goldens
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
   measured cap; all 132 importing files compile unchanged.
2. **Feature:** 19 destinations, each ≤ 500 lines, no size exception, no
   cross-file private, acyclic imports, no runtime type name change.
3. **Guard:** feature, facade rules and cap, exact `show` service imports, the
   `url_launcher` confinement, the playback/storage/http and settings-family
   cross-import bans, each proven through the real checker.
4. **Tests:** all manifests with self-tests pass; every characterization test
   and guard from (b) passes unchanged; macOS and Linux goldens (five new plus
   the five `settings_spotlight`) match, with the completion Linux replay's
   provenance recorded.
5. **Diagnostics:** no new diagnostics, suppressions or allowlist entries.
6. **CI:** behaviour list holds the importing and new tests; shape slice
   totals 7 bare radii and 26 token calls with 0 of each in the facade, the
   488 floor unchanged; theme surface unchanged; size baseline
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
4. **Goldens:** five new direct-harness scenes covering both looks and TV/phone
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

1. Of the 11 `kSettings*` colors only `kSettingsAccent` and `kSettingsPanel2`
   have production uses (two top-level `final` focus styles that cannot read the theme);
   the rest are read only by `theme/legacy_pins_test` (and named in
   `app_theme.dart` comments).
2. `settingsInitialsFor` is public with a single caller (`ConnectionCard`).
3. `launchSettingsUrl` ignores `launchUrl`'s `false` result and any exception.
4. `ConnectionCard`'s `MouseRegion` is not TV-gated (hover state is set but
   unused on TV).
5. `SettingsSelectDropdown` passes `initialValue` to a `FormField`. On the
   recorded Flutter 3.44.8 original, a parent value change updates both the
   closed field state value and selected subtitle; null is not forwarded and
   a stale value renders empty. Characterized, not changed.
6. Import directives in the original are unsorted (`tv_reveal` before
   `services`, `package:debrify/models` last); destinations write sorted imports,
   which is formatting of new files, not a behaviour change.

7. Eight importing files reference no facade name (listed in the deps report);
   their original imports remain unchanged.

## Round 1 review resolution (Codex design review at `8ccf2d8a`)

1. P1 shape registration → token-bearing destinations in `kShapeResidue`,
   the rest in `kExtractedShapeResidue`, facade transferred when its last
   token call moves; 26 tokens / 488 floor asserted (Step 0 item 8).
2. P1 "exactly 10" → measured 7 bare radii allocated by destination; ceilings
   and measurements reported separately.
3. P2 reader → all 60 AST declarations by kind, analyzer-span cross-check and
   per-kind deletion/duplication proofs before freezing; `show` assertions
   staged by destination creation (Step 0 item 5).
4. P2 key routing → ancestor event recorder for handled/ignored, neighbour
   fields read from the element tree, recording `ScrollPosition.animateTo`,
   sidebar 2×2 matrix (Contract 3).
5. P2 mutation recipes → rendering fallback class S with table completeness;
   compilable `onChanged(v!)` dropdown mutant with `returnsNormally`.
6. P2 goldens → five scenes (phone connections at 390×1000, skeleton alone),
   font/timeline policy, reverse-order define.
7. P2 inventory → 132 importing files (117 lib, 15 test, 14 runnable);
   missing runnable importers and the helper's consumers added to CI.
8. P2 per-symbol diagnostics → `settings_widgets_diagnostics.py`; relocation
   via `suite_evidence.py compare --relocate`.
9. P3 scan scopes → profile log-redaction scan and light-ink PRIMARY gain the
   feature path in step 1.
10. P3 → direct implementation-import ban stated and tested both ways; private
    count corrected to 10 + 3 variables; `kSettingsAccent`/`kSettingsPanel2`
    production uses recorded.

Round 2 (at `4bec3ce3`): **No P1s — executable**, no P2s; three P3 wording
notes (post-frame phase assertion, 300 ms sample, `final` styles) applied.

## Progress

### Step 0 — originals and characterization preparation

- Execution starts at plan HEAD `397485b416c7060e9da5a33e488435f6a3fb6bf3`
  (base `0cb50df7`) in the dedicated `refactor/settings-widgets` worktree.
  `flutter pub get` ran here first; pubspec and lockfile remain unchanged.
  All evidence is in the git common directory's
  `refactor-evidence/settings_widgets/`; parser/kernel caches and detached
  proof/probe copies are in this worktree's ignored `.dart_tool/settings_widgets/`.
- (a), R: `0eadeb8c516b55445a367f1885136a7cf4be2312`, exact subject
  `style(settings-widgets): format the original settings widgets`.
  Only the original source and its size-baseline entry changed (2835 → 2847).
  `settings_widgets_format_proof.py --original 397485b4 --formatted
  lib/screens/settings/widgets/settings_widgets.dart --parser-package
  .dart_tool/settings_widgets/parser/.dart_tool/package_config.json --kernel
  .dart_tool/settings_widgets/parser/.dart_tool/settings_widgets_format_proof_final.dill
  --output <evidence>/format-proof.json` passed: exactly two AST-identified
  optional commas, both owned by `_ConnectionsSummaryState`; whole-file
  tokens/comments/literals equal otherwise; edited comment, trailing comment,
  literal and required singleton-record comma negatives all rejected.
  `dart format --output=none --set-exit-if-changed` is idempotent on R.
- Full suites `suite_evidence.py run settings_widgets/base --no-pub` on
  untouched HEAD and `run settings_widgets/base-fmt --no-pub` on R:
  each **11654 success / 13 failure / 28 error / 20 skipped**. Both env files
  record Flutter 3.44.8 / Dart 3.12.2, paths `[]`, flags `["--no-pub"]`,
  HEAD = index = tested = end tree, no untracked input, no changed tree.
  `compare --against <evidence>/base.jsonl <evidence>/base-fmt.jsonl` PASS:
  zero added/missing/changed identities, new failures, new skips or fixes.
- Whole-repo analyzer initially duplicated diagnostics while generated test
  assets were being created (3201 reports). Retained raw evidence; a clean
  detached replay of untouched HEAD with the same generated asset inputs is
  `base-analyzer-stable.txt`: **1689 reports / 578 identities**, identical by
  severity/file/rule/message/count to `base-fmt-analyzer.txt`; zero additions
  or removals (`format-analyzer-comparison.txt`). The preliminary replay's
  twelve missing-asset warnings are environmental and not accepted as code
  diagnostics. No format-induced diagnostic, suppression or allowlist entry.
- Deps report and reproducible analyzer-backed inventory: **60 declarations,
  47 public names, 132 importers (117 lib / 15 test / 14 runnable)**. URI
  directives are resolved; public-reference DAG is acyclic; no cross-file
  private reference, alias or application seam is needed. Every declaration,
  private item, State read and comment fragment has an owner and wiring row.
  Eight original importers use no facade name; their imports remain unchanged.
- Real sections config/manifest: 60 unchanged leaves, empty type_aliases;
  original/current and complete-split positives plus nine textual negatives
  and duplicate/missing-leaf negatives. Every manifest run/self-test uses its
  own copied parser package with all copied `*.dill` removed. The integrated
  manifest results are recorded under `checkers/` and summarized below after
  completion; no other feature's proof script or shared checker is edited.
- Strict record/split: `settings_widgets_diagnostics.py record --rev
  0eadeb8c5 --split --parser-package <isolated-package> --output
  <evidence>/strict/baseline.json`. Zero errors/warnings. The split has the
  **four original const infos** (SettingsSkeleton, _SkeletonHeader and two
  _SkeletonTile sites), no private-public-API/import/undefined-name issue.
  Five original ordering infos and two qualification-induced ordering counts
  are retained separately; baseline maximum is 11 counts, never a sum.
  Fixture command `settings_widgets_diagnostics.py fixtures` proves moved
  identities pass, added/re-owned/new-rule identities fail, and maximum
  counts never sum. Sorted probe exports avoid artificial ordering growth.
- Frozen reader: `settings_widgets_reader_check.py --parser-package
  <isolated-package> --output <evidence>/reader-check-final.json` PASS:
  **all 60 spans exactly equal analyzer spans**, deletion and duplication
  rejected for class/enum/function/variable, and lexical stress fixtures
  cover nested comments, raw/triple/interpolated strings, generics, arrow
  bodies and an uninitialized memo. Service shows are staged by destination;
  completion topology is dormant while the completion flag is absent.
- Harness and frozen tests proved on R: **48 behavioral tests** (seven files,
  including five pixel scenes), separately **6 source/surface guards (S)**.
  Host resources, sidebar/launcher/legacy reason/platform flags and parallax
  travel are restored. Bounded fake-clock pumps; no new scene loads a font or
  changes typography globals. The existing 19 related files pass **201 tests**,
  including all 14 direct importing runners, both helper consumers, the five
  existing settings Spotlight goldens and shape/theme/stale-runtime guards.
- macOS originals (captured only against R), strict forward and reverse:
  `tv_legacy_gallery` 1920×1080, `tv_spotlight_gallery` 1920×1080,
  `wide_connections` 1280×900, `phone_connections` 390×1000,
  `phone_skeleton` 390×844. All promised widgets overlap capture bounds;
  all five PNGs match strictly in reverse order. Default flutter_test font,
  DPR 1, en-US, text scale 1, 300 ms focus sample / 400 ms shimmer sample.
  Capture hashes and 16 frozen test/helper/PNG inputs are recorded in
  `frozen-input-sha256.json`. Existing Spotlight PNGs remain untouched.
- CI inventory adds the six missing runnable importers, two helper consumers
  and all nine new tests (17 paths); never the helper itself. None of these
  related identities failed in the observed base, so no known-failure entry.
  Actual checks.yml format/analyze commands and allowlist PASS (25 existing
  warnings); no workflow or analyzer-allowlist change is made in Step 0.
  Whole-repo analyzer with the new tests still equals R: 1689 reports.
- Source inventories: slice exactly **26 token calls / 7 bare radii**, ceiling
  10 measured separately; global **488**, zero slack. Per-destination totals
  are in `source-inventory.json`. Theme settings surface is **219 files /
  657 sites**, identical before/after the explicit presentation glob. Light
  ink is **774 sites / 198 files**, PRIMARY **240 / 67**, unchanged. The scan
  inventory identifies shape, theme, light-ink PRIMARY and profile log scans;
  the last two gain the destination scope only at step 1. All-lib theme and
  stale-runtime scans, storage member map and facade-based legacy pins remain
  applicable. No shape entry is changed before a destination is created.
- Linux handoff `dev/tool/capture_settings_widgets_linux_goldens.sh` passes
  `bash -n`; exact unique-subject lookup consumes all git-log output, checks
  (b)'s lib/pubspec/lock equality to R, requires calibrated Linux/amd64 Flutter
  3.44.8, and double-captures independent originals in opposite scene orders,
  requires byte/hash equality and strict replay, and records provenance.
  **It is not run in Step 0. No Linux PNG, step L or extraction is started.**
- Conservative decisions: keep the original library intact after R; no
  behavior fix, import cleanup, font load, API/dependency/seam change, lint
  suppression or weakened assertion. The hero threshold fixture uses inner
  width (outer width includes 40 px padding/border). The generic move adapter
  cannot inventory callers with multi-variable fields, so the small opt-in
  inventory adapter reads their import directives/identifiers; no shared
  checker is changed. Any 0b proof must fail an assertion, never compilation.
  The 0b runner prepares 30 B + 8 S mutations, including both layouts for all
  four optional-card variants and each of the three borrowed-node widgets.
  Committed (b), detached original proof, base3 and the complete mutation
  table follow below before the Step 0 stop.

- Before finalizing (b), original-code review adds the Console rule-surface
  branch (transparent fill, unchanged border/divider/blurb) and makes the
  service/import guard inspect the facade as well as created destinations (including player/launcher paths).
  These pass on R; their targeted fill, HTTP-import and player-import mutants join the table.
  The harness explicitly declares en-US as supported as well as selected;
  strict macOS PNG hashes remain identical. Linux scenes skip only while the
  original PNG is absent before L, then run strictly without changing this
  frozen test; the capture script explicitly requires strict Linux replay.
  The mutation runner distinguishes compiler source-location errors from an
  asserted runtime `_TypeError` in the nullable-callback/sidebar cases.
  Preliminary checkpoint/suite/proof records are retained separately; final
  committed original proofs and base3 use the amended, frozen checkpoint.
