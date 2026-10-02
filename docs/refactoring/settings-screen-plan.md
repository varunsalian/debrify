# Settings screen refactor — plan

Drafted 2026-10-02 and reviewed by Codex in four rounds (verdict: "No P1s —
executable"). The line numbers were written against `3bf55ea4` and re-checked
at `6d6676cc`, where the launcher refactor ended: `settings_screen.dart` and
the other cited files are unchanged, apart from `theme_rendered_set.py`,
whose glob moved one line, to 73–75. Execute from `6d6676cc` or later. The
guard, size baseline, CI and `check_verbatim_moves.py` now include the
launcher refactor's additions; extend them, don't replace them. Follow
[AGENTS.md](../../AGENTS.md).

Work on the existing `refactor/codebase` branch. Commit after every step.
Never push to `origin`; push to `private` only if the goal you were given
says so.

## Goal

`lib/screens/settings_screen.dart` is 8,757 lines: the Settings hub. The 73
individual settings pages already live in `lib/screens/settings/`. Split the
hub into `lib/features/settings/`, **moving code verbatim**. The widget tree,
keys, focus nodes and build order don't change. `settings_screen.dart` keeps
the public `SettingsScreen` widget and the State's lifecycle, wiring in the
extracted sections.

**Architectural status:** this is a bounded legacy-extraction stage, not the
finished architecture.
- **Temporary exceptions to AGENTS.md,** recorded in Progress:
  - **Riverpod:** state stays State-driven and constructor-wired (AGENTS.md
    wants Riverpod for migrated feature state);
  - **bridge folder:** `legacy_settings/` calls services directly.
- **Exit milestone,** after this plan:
  - move the summaries into a Riverpod `Notifier`;
  - put service calls behind settings data contracts, then dissolve the
    bridge folder.

## What it contains (line numbers at `3bf55ea4`; step 0 re-derives them)

| Lines | Area | Key symbols |
| --- | --- | --- |
| 1–173 | Imports | |
| 174–179 | **Public pure helper** | `shouldApplyPendingCredentialOverride`. `test/profiles/settings_pending_credential_override_test.dart:2` imports the screen to reach it. |
| 180–189 | Widget | `SettingsScreen`, including `summaryReadOverrides` |
| 190–333 | State fields | 76 fields plus `_mediaServerCount` (1224), 77 in all. These are summary scalars **and resources**: `_firstCardFocusNode` (198), `_tvContentFocusHandler` (249), `_updateDownloadSub`/`_updateDownloadTaskId` (297–298). There are also computed getters (`_isAndroid`, `_isTelevision`, `_iptvAppearanceSearchable`, ...). |
| 334–370 | Lifecycle | `initState` order: analytics, `_loadSummaries`, `_loadSupportConfig`, `_loadDownloadLocation`, recording probe, TV focus handler (tab 8). `dispose` order: unregister the handler, dispose the focus node, cancel `_updateDownloadSub`. |
| 371–1008 | Summary loading | `_loadSummaries` (380–397: captures the starting scope and guards error/finally publication), `_loadSummariesForCurrentProfile` (421–1008, **588 lines**). It reads `widget.summaryReadOverrides` at call time (425–426); its initial publication guard is at 671; background account refreshes check `mounted` (970–1004). |
| 1010–1121 | Helpers | pending-credential, support and account-caption helpers |
| 1123–1160 | `build` | |
| 1161–1310 | Connection getters | combine summary values with navigation callbacks |
| 1312–1573 | Layouts and search entry | `_buildTvLayout`, `_buildLayout`, `_openSettingsSearch` |
| 1574–2944 | `_buildSearchIndex` (**1,371 lines**) | helpers `conn` and `nav`; the list returned at 1611–2936; Appearance block 1924–2573 (**650 lines**) |
| 2945–4969 | `_leafSearchEntries` (**2,025 lines**) | preamble locals (`pageIcons`, `pageOpeners` at 2975, `leaf`, `optionLabels`, `externalPlayerLabels`, label consts, `advancedAppearanceOptions`); the list returned at 3261–4967 |
| 4970–5456 | Navigation and profile actions | `_open*Settings`, `_editActiveProfile`, `_ensureProfileFeature` |
| 5457–6309 | Backup, restore, diagnostics | `_createBackup`, `_restoreBackup`, `_promptAndDecryptBackup`, `_exportDiagnosticLogs` (diagnostic visibility writes at 5725–5727), `_backupSummaryLines`, `_formatRestoreReport` |
| 6310–6730 | Downloads and maintenance | download location and folder, clear data, `_resetAppData` |
| 6731–7426 | Updates and the rest of the State | `_checkForAppUpdates` (6731), `_toggleAutoUpdateChecks` (6936), `_toggleIncludeAlphaUpdates` (6945), `_showReleaseDetails`, `_startAndroidUpdateDownload`, `_reloadAppearanceSummaries`, `_showSnack` (7408: checks `mounted` before using `context`). The State ends at **7426**. |
| 7428–7594 | **Top-level constant** | `_kAdaptiveSettingsCategories`, used by the layout (7823) |
| 7596–8693 | `_SettingsLayout` | `const` constructor (7694). Declaration, fields and constructor run 7596–7774; helpers include `_buildSpotlight` (7799) and `_buildSpotlightCategory` (7873); the classic `build` is at 8277–8688 (412 lines); playback keys at 8037 and 8470. |
| 8694–8757 | `_SettingsSearchBar`, `_SettingsSearchBarState` | own `FocusNode` |

## Facts that shape the plan

- **Shared state is written in several places.**
  - Update settings are written by the loader (939–940) **and** the update
    actions (6939–6954).
  - Diagnostic visibility is written by the loader (964), profile navigation
    (5245–5247) **and** diagnostic export (5725–5727).

  So the shared owner must exist **before** any action section moves.
- **Resources are not summaries.** The focus node, focus handler and update
  subscription each keep an explicit owner, and teardown keeps its order:
  unregister the handler, dispose the focus node, cancel the subscription.
- **`mounted` before `context`.** Helpers like `_showSnack` (7408) check
  `mounted` before touching `context`, and they run after `await`s. Moved code
  must never fetch `context` ahead of the original guard.
- **The permission guard is a contract.** `test/update_service_test.dart:154–160`
  requires each update action's **first statement** to be
  `if (!await _ensureProfileFeature(ProfileFeature.appUpdates)) return;`.
- **TV input is a contract.** `test/settings_tv_input_source_guard_test.dart`
  forbids raw `TextField(` and requires `TvTextField(`.
- **Search order is a contract.** `lib/screens/settings/settings_search.dart:196–205`
  groups results by first appearance, so the index's order decides category
  order. Existing grouping tests
  (`test/settings_search_grouping_test.dart:34–40`, `:54–60`) use synthetic
  entries, not these builders.
- **Profile lifetime:** coordinators live exactly as long as the State. The
  profile gate remounts the subtree on a switch
  (`lib/screens/profiles/profile_gate.dart:589–592`), and the background
  refreshes rely on that.

## Destination layout

`lib/features/settings/`:
- **`application/`**: pure helpers with no services and no context:
  `shouldApplyPendingCredentialOverride` (`settings_screen.dart` re-exports
  it, so the test's import keeps working; extracted code imports it from
  here, never from the screen); `_formatRestoreReport` and
  `_backupSummaryLines` if the report confirms they're pure.
- **`presentation/legacy_settings/`**: a named bridge for sections that take
  a `BuildContext` and call legacy services: the summaries owner, the summary
  loader, connection getters, navigation and profile actions,
  backup/restore/diagnostics, downloads/maintenance, updates, and the search
  index builders.
- **`presentation/`**, outside the bridge, for UI without service imports:
  the layout, the search bar, and `_kAdaptiveSettingsCategories` (with the
  layout).

The step 0 report decides files. Each file is at most **500 lines**, except
the named files under "Size" below.

## Technique: move-only section coordinators

1. **Sections are plain presentation classes** that own their moved methods
   and any state only they use. They're constructed by the State and live
   exactly as long as it does.
2. **The summaries owner is created first (step 2)** and holds every summary
   scalar the hub reads or writes, with the same initializers. Sections and
   the State read and write through it (`_x` → `_summaries.x`). Resources
   stay explicit:
   - `_firstCardFocusNode` and `_tvContentFocusHandler` stay in the State;
   - `_updateDownloadSub` and `_updateDownloadTaskId` move to the update
     section, which exposes `void dispose()`. The State calls it at exactly
     the original position, so dispose keeps unregister → focus dispose →
     cancel.
3. **Deps records** are typed and narrow. Values read at call time stay live:
   - `summaryReadOverrides: () => widget.summaryReadOverrides` (a getter,
     never a captured value);
   - `setState: setState`;
   - `mounted: () => mounted`;
   - `context: () => context`;
   - deferred callbacks where a section calls a method that's still in the
     State.
4. **`mounted`/`context` rule** (from the search-screen refactor):
   - `setState(fn)` → `_deps.setState(fn)`, so the mutation stays inside the
     callback;
   - `mounted` → `_deps.mounted()`, at the original position;
   - fetch `context` (`final context = _deps.context();`) only at the
     original first use of `context`, or right after the original passing
     `mounted` check. Never before a guard that preceded it in the original;
   - after `await`s, check `context.mounted` exactly where the original
     checked `mounted`;
   - dialog, sheet and builder contexts (`builder: (ctx) ...`) are their own
     parameters, unchanged;
   - delayed entries (timers, listeners, `.then`, post-frame callbacks) keep
     the original guard order;
   - an update action's first statement stays the permission guard.
5. **Allowed edits:** the ones above, field and method qualifiers, imports,
   dropping `_` where another file needs a symbol, and the named structural
   edits below.
6. **Not allowed:**
   - reordering `await`s, guards or `setState` contents;
   - changing a widget, key, `FocusNode`, constructor default, `const`
     capability or the build order;
   - merging look-alike helpers;
   - changing user-facing text. Moved text keeps a documented
     legacy-localization exception (AGENTS.md), recorded in Progress with
     the localization milestone.
7. **`_SettingsLayout` structural edits** (no widget is added or removed):
   - **Helpers to top-level functions:** the State's private build helpers
     become top-level functions in sibling files, taking the layout as their
     first argument.
   - **Calls and fields:** helper calls become function calls. Private
     getters and fields read through the layout get public names inside the
     feature.
   - **Constant:** `_kAdaptiveSettingsCategories` moves with the layout.
   - **Tear-offs:** a method passed as a tear-off (for example at 7837)
     **stays a method on the class**, so the tear-off is identical. Don't
     replace it with a closure.
   - **Classic `build` body:** `build` (8277–8688) becomes a one-line
     dispatcher, `return buildClassicSettingsLayout(this, context);`, and the
     body moves verbatim (apart from receiver qualifiers) into that
     top-level function.
   - **`_buildSpotlightCategory` (7869–8275, 407 lines)** gets the same
     treatment. Its body moves into the top-level
     `buildSpotlightCategory(layout, ...)` (in `settings_spotlight_category.dart`),
     and the method stays as a one-line forwarder with the same signature,
     so calls and any tear-offs are identical. With both large bodies moved
     out, the layout class (declaration, fields, constructor, small helpers,
     forwarders) must be under 500 lines. The report measures it; if it
     isn't, move the next-largest helper body the same way.
   - **One service read:** the category renderer reads
     `ProfileBootstrap.legacyReasonSummary` (8123–8125), a service the layout
     may not import outside the bridge.
     - Add one required named constructor parameter,
       `String Function() legacyReasonSummary`: non-nullable, matching the
       getter (`profile_bootstrap.dart:67`, `static String get` with a
       fallback), so the renderer's `.split('\n').first` compiles unchanged.
       The State (bridge side) passes
       `() => ProfileBootstrap.legacyReasonSummary`.
     - The renderer calls `layout.legacyReasonSummary()` at the original
       position, so the value is still read live, at the same moment.
     - The constructor stays `const`, and other parameters and defaults are
       unchanged. Every construction site is in this file. The manifest
       records it.
   - **Unchanged:** the `const` constructor, defaults, keys (8037, 8470) and
     focus ownership.
8. **List partition** (only for `_buildSearchIndex` and `_leafSearchEntries`):
   - **Builder, fresh on every call.** The method creates a new builder
     object each time it runs:
     - the preamble locals become the builder's `final` fields, initialised
       in its constructor in the original order (so `pageOpeners` is still
       built once per call, before the list);
     - local functions (`conn`, `nav`, `leaf`, `optionLabels`,
       `externalPlayerLabels`) become methods;
     - local `const`s become `static const`;
     - nothing is retained between calls.
   - **Partition units** are complete top-level elements of the returned
     list literal. A collection `if`/`for` element (1612, 3946, 3984, 4745,
     4791) is never split. Closures, including ones capturing loop
     variables (3990) and toggles reading live State (2758, 2876, 2885), are
     unchanged.
   - **Slices** are cut at existing section comments and are at most about
     300 lines. The Appearance block (1924–2573) is cut at its inner comments
     into several slices. The manifest records every cut line.
   - **Joining:** the method returns `[...b.slice1(), ...b.slice2(), ...]` in
     the original order.
   - **Partition check:**
     - the joined slices' elements equal the original elements token for
       token, in order;
     - the preamble declarations equal the builder's fields and methods;
     - the join order matches the manifest.
9. **Temporary cross-calls** (`TEMP(settings)`) are allowed only from
   `legacy_settings/` files, and none may remain at the end.

## Size

- **Default:** every new file is at most **500 lines**.
- **Named exceptions** (AGENTS.md: 501–800 is acceptable with one clear
  responsibility):

  | File | Holds | Cap |
  | --- | --- | --- |
  | `legacy_settings/settings_summary_loader.dart` | `_loadSummariesForCurrentProfile` (588 lines), one responsibility | measured size, ≤ 800 |
  | `presentation/settings_classic_layout.dart` | `buildClassicSettingsLayout` (the 412-line classic build) | measured size, ≤ 800 |

  `settings_spotlight_category.dart` (the 407-line body, plus imports) should
  fit in 500. If its measured size doesn't, it becomes a third named
  exception, capped at that size.

  Nothing else is over 500.
- **The facade** (`settings_screen.dart`) is at most **400 lines at the
  end**.
- **Staged enforcement.** The screen stays large until step 6, so the final
  rules switch on at the end:
  - **From step 1:** the guard registers `lib/features/settings/` and checks
    every **destination** file against its cap (500, or its named
    exception) at every step. CI's format and analyze steps cover
    `lib/features/settings/`.
  - **Steps 1–5:** `settings_screen.dart` is **not** registered with the
    facade cap. It is only held by the repo size ratchet, which must shrink
    at each step (`check_file_sizes.py --update`). It is also not in CI's
    format scope (it has pre-existing unformatted regions); CI's analyze step
    may include it from step 1.
  - **Step 6:** format `settings_screen.dart` whole, register it with the
    400-line facade cap, add it to CI's format scope, and turn on the
    guard's `TEMP(settings)` rejection. `TEMP(settings)` markers are allowed
    in intermediate steps only in `legacy_settings/`.

## Steps

| # | Work | Notes |
| --- | --- | --- |
| 0 | Baseline, dependency report, checks, source-text inventory, production-index order test | Nothing moves. Run after the launcher refactor ends. |
| 1 | Guard and CI registration, staged (see Size). Pure UI: search bar, layout (helpers, the classic `build` body, the `_buildSpotlightCategory` body, `_kAdaptiveSettingsCategories`, the `legacyReasonSummary` parameter). `shouldApplyPendingCredentialOverride` to `application/`, with a re-export. | |
| 2 | **Summaries owner** (every summary scalar) and connection getters | Resources keep their owners. |
| 3 | Action sections: updates (takes the update subscription), backup/restore/diagnostics, maintenance/downloads, profile actions, navigation openers | The permission guard stays first. |
| 4 | Summary loader (`_loadSummaries`, `_loadSummariesForCurrentProfile`, `_loadSupportConfig`, `_loadDownloadLocation`, `_reloadAppearanceSummaries`, helpers 1010–1121) | The profile-scope guards move verbatim. **Full-suite gate 1.** |
| 5 | Search index and leaf entries, by list partition | The order test must pass. |
| 6 | Final State, guards, CI, **full-suite gate 2** | See "Definition of done". |

### Step 0

1. **Baseline,** at `6d6676cc` or later:
   `python3 dev/tool/suite_evidence.py run settings/base`, and
   `flutter analyze > <E>/settings/analyze-base.txt`. `<E>` is
   `$(git rev-parse --git-common-dir)/refactor-evidence`. The SDK must be
   Flutter 3.44.8.
2. **Dependency report** (`docs/refactoring/settings-screen-deps.md`):
   - every top-level declaration and every member of the State,
     `_SettingsLayout`, `_SettingsSearchBar` and `_SettingsSearchBarState`;
   - each one's destination, step and layer;
   - which fields each section reads and writes;
   - every cross-section call, every tear-off, every deferred callback.

   Nothing may be unresolved.
3. **Checks:**
   - `dev/tool/check_verbatim_moves.py` (from the launcher refactor), with
     `dev/tool/settings_manifest.tsv` recording each member's allowed edit
     kinds;
   - its **partition mode** (above);
   - a **context-guard check**: for each moved method, the position of the
     first `context` use relative to `mounted` guards is unchanged;
   - self-tests: a reordered slice, a dropped element, a duplicated element,
     a split collection-`if`, and `context` fetched before a guard must
     each fail.
4. **Production-index order test** (`test/settings_search_index_order_test.dart`):
   - It asserts the ordered `(category, title)` list from the **real**
     `_buildSearchIndex` and `_leafSearchEntries`. Record it at baseline; it
     must pass unchanged at every step.
   - **Host-aware:** some entries depend on the platform, for example
     Download Location (2777–2796), gated by 6280–6284, which shows on Linux
     but not macOS. CI runs on Ubuntu, local runs are on macOS. So keep one
     reviewed expected list per host platform the tests run on (macOS,
     Linux), each in exact order. A platform-gated entry must be covered in
     at least one of them. Never weaken it to an unordered or subset
     comparison.
   - Reach the builders through the existing search UI if possible.
     Otherwise add one minimal `@visibleForTesting` accessor; it's
     test-only, and the manifest records it.
   - Also add a **disposal regression test**: an update or snack helper
     that completes after the screen is disposed must not throw.
5. **Source-text inventory** (`dev/tool/settings_source_text.txt`):
   - `test/update_service_test.dart:148–160`;
   - `test/settings_tv_input_source_guard_test.dart`;
   - `test/settings_sync_and_migrate_source_guard_test.dart`;
   - the diagnostic-visibility guard in
     `test/profiles/profile_source_guard_test.dart:414`;
   - `test/theme/shape_manifest_test.dart:97`;
   - `dev/tool/theme_surface_manifest.txt:6`, read by
     `dev/tool/theme_rendered_set.py` and `dev/tool/measure_theme_surface.sh`.

   Grep for more. Each entry gets the step that ports it.

### Per step

- **Move:** verbatim, with the allowed edits only.
- **Format** every changed project-owned Dart file (AGENTS.md), with one
  exception: `settings_screen.dart` has pre-existing unformatted regions, so
  format it only in step 6, once they have moved out. Don't format
  unrelated files.
- **Analyzer:** compare the whole repo with the previous step,
  `--relocate lib/screens/settings_screen.dart=lib/features/settings/`.
- **Checks:** `check_verbatim_moves.py` (partition mode in step 5), the
  architecture guard and the size ratchet.
- **Tests:** the settings tests, the source-text inventory, the order and
  disposal tests, and `test/profiles/isolation_suite`. Record them with
  `suite_evidence.py run settings/stepN <paths>` and compare with
  `settings/base`.
- **Then** self-check with `git diff --color-moved`, and commit.

### Source-text tests

- **Permission guard:** point the regex at the update section's file. It
  still requires the guard as each action's first statement. If the call
  becomes `_profile.ensureProfileFeature(...)` or similar, match that exact
  spelling; never loosen it to "contains".
- **TV text field:** scan the remaining `settings_screen.dart` and every file
  under `lib/features/settings/`. No raw `TextField(` anywhere, and
  `TvTextField(` still present.
- **Shape manifest** (`test/theme/shape_manifest_test.dart`): keep both kinds
  of coverage.
  - **Bare radii:** the screen's four (6333, 8722, 8725, 8733) go to their
    new owners in `kExtractedShapeResidue`: the download-sheet owner with 1,
    the search bar with 3.
  - **Token call:** the release-details owner, which takes the only
    `app.shape.br` call (6840), goes in `kShapeResidue` with residue 0.
    `kShapeResidue` files must contain `app.shape.` (241–247), and the
    token-call floor (261–270) must still be met.
  - **The screen itself** moves to the right map once its token call has
    left.
- **Theme surface:** `theme_rendered_set.py` (73–75) uses non-recursive
  `glob` and `measure_theme_surface.sh` (11–16) expands with `ls`. List exact
  per-directory patterns both accept, such as
  `lib/features/settings/presentation/*.dart`,
  `lib/features/settings/presentation/legacy_settings/*.dart` and the
  search-index directory. Verify every new file is included.
- **Sync/Migrate and diagnostic-visibility guards:** point them at the new
  owners. Replace substring boundaries that no longer hold, keep every
  assertion, and make negative guards scan every possible destination.
- Never delete an assertion to make a move pass.

## Definition of done

1. **The screen file.** `settings_screen.dart` (at most 400 lines, formatted)
   holds `SettingsScreen`, the re-export of
   `shouldApplyPendingCredentialOverride`, the State's section wiring,
   `initState`, `dispose`, `build` and the layout choice.
2. **Guard.**
   - `lib/features/settings/` is in `FEATURES`.
   - The exact `presentation/legacy_settings/` path is a bridge; service
     exemptions are confined to it, and the application layer keeps its UI
     prohibitions.
   - The Settings rule applies the 500 default, the two named exceptions and
     the 400-line facade, and rejects `TEMP(settings)`.
3. **Checks:** `check_verbatim_moves.py` passes, including the partition and
   context-guard modes and their self-tests. The order and disposal tests
   pass.
4. **Analyzer and tests:** no added diagnostics. Gate 2 passes against
   `settings/base.jsonl` and `settings/gate1.jsonl`.
5. **CI.**
   - Format and analyze cover `lib/features/settings` **and**
     `lib/screens/settings_screen.dart`.
   - `dev/tool/ci_behavior_tests.txt` gains concrete paths, not globs (the
     manifest isn't glob-expanded): every `test/settings_*` file found with
     `ls`, the order and disposal tests, the source-text inventory,
     `test/profiles/settings_pending_credential_override_test.dart` and
     `test/settings_search_grouping_test.dart`.
   - The allowlist is seeded from failures that still fail at gate 2.
   - CI passes on `private`.
6. **Progress records:**
   - the step commits, and every section with what it owns;
   - the partition evidence;
   - the two size exceptions;
   - the Riverpod and bridge exceptions, with their exit milestones;
   - the legacy-localization exception.
7. Stop after gate 2 and report.

## Explicitly not in scope

- The 73 pages in `lib/screens/settings/`.
- The Riverpod migration of the summaries (the exit milestone above).
- Changing settings text, ordering, search grouping, focus or navigation.
- Bug fixes. Record any you find under "Found, not fixed".

## Progress

### Step 0 — extraction prerequisites

- Starting revision: `17db33f2` on `refactor/codebase`; Flutter 3.44.8
  (`058e0af2c2`, Dart 3.12.2). No original declaration moved or changed.
- `settings-screen-deps.md` resolves all seven top-level declarations, 316
  declaration leaves and 277 callbacks. `settings_manifest.tsv` records the
  destinations, steps, layers and permitted edit kinds. Resources and live
  getters are distinguished from summary scalars.
- `check_verbatim_moves.py` now dispatches to Settings-specific partition and
  context-guard checks. It preserves the launcher mode and self-tests. The
  Settings self-tests reject reordered/dropped/duplicated elements, split
  collection-if/for elements, preamble changes, reordered joins, and context
  acquisition above guards or outside a delayed callback. Builder contexts
  remain independent. Preamble declarations, constructor initializer order,
  whole AST elements and exact fresh-builder dispatch are checked.
- `settings_partitions.json` records every complete-element cut. The user
  approved the cut at original line 4166 inside the otherwise 376-line Player
  Settings block; all other cuts use existing section comments. This is the
  only extra partition boundary beyond the plan's original technique.
- The single `settingsScreenTestAccess` accessor exposes real builder and
  snack-helper tear-offs. macOS expected lists contain 212 index / 150 leaf
  pairs; the reviewed Linux lists contain 213 / 150, adding Download Location
  at the original position. Linux execution remains pending Ubuntu CI.
- Scope/size exception for step 0: `settings_screen.dart` retains all original
  responsibilities until steps 1–6. The authorized test accessor adds 15
  lines (8757 → 8772); its ratchet is raised by exactly those lines in this
  commit. Step 1 begins shrinking the ratchet; step 6 exits at ≤400 lines.
- Observed full baseline: `suite_evidence.py run settings/base`: 10,304
  success, 14 failure, 29 error, 20 skipped. Evidence lives under the git
  common directory's `refactor-evidence/settings/`, including SDK/HEAD metadata.
  Whole-repo analyzer baseline: 832 diagnostics. Analyzer used `--no-pub`
  after concurrent pub regeneration hit an ephemeral iOS package-directory
  deletion race; no dependency/SDK change was made.
- Focused `settings/step0`: 85 success, 2 failure, 1 error. Comparison against
  `settings/base.jsonl` passes: no new failures, missing tests or new skips;
  two added passing identities are the production-order and disposal tests.
  The three still-failing identities are shape residue, direct SharedPreferences
  source guard, and device-reset diagnostic cleanup source guard; each fails
  in the observed full baseline too. The order test runs both real builders
  twice; disposal verifies the snack works while mounted and safely completes
  after the State has been retired.
- Analyzer comparison `analyze-step0.txt` vs `analyze-base.txt`, with the
  settings relocation rule: no added or removed diagnostics. Move checks in
  both modes with all self-tests, the architecture guard, the size ratchet,
  changed-test formatting and diff checks pass. `settings_source_text.txt`
  records every executable source consumer and its porting step.
- Temporary architecture exceptions for this bounded extraction: sections
  retain State-driven, constructor-wired state instead of Riverpod; only the
  named `presentation/legacy_settings/` bridge may retain legacy service
  calls. Exit after this plan: introduce the summary Notifier, add settings
  data contracts, and dissolve the bridge. Moved app text keeps the legacy
  localization exception until that later settings localization migration.
- Gate 1 and gate 2 pushes/Ubuntu CI are pending; nothing has been pushed for
  this prerequisite step.


### Step 1 — UI extraction

- Prerequisite commit: `3fe409a1` (step 0); all required artifacts and tests
  were committed before moving declarations.
- `settings_pending_credentials.dart` owns the original pure helper; the
  public screen re-exports it. The seven presentation files own category
  definitions, search-bar focus, the small layout class, connection grid,
  spotlight summary, spotlight category body and classic layout body.
  Production still constructs the layout from the State and reads the
  legacy-reason getter live at the original renderer position.
- The two dispatch methods preserve signatures and method tear-offs. The
  layout constructor remains const; defaults, widget keys and focus owners
  are unchanged. `SettingsLayout` currently measures 219 lines. Classic
  layout currently measures 420; spotlight category 433. Every destination
  remains within 500. The screen shrinks from 8772 to 7438 lines; the ratchet
  records that shrinkage.
- Architecture guard now registers Settings, confines service exemptions to
  the exact legacy bridge path and measures destination caps. The facade
  cap/TEMP rejection switch stays off until step 6. CI already formats all
  features and now analyzes the legacy screen as well.
- Source ports preserve all assertions: TV-safe text-field checks scan the
  whole source set; Sync/Migrate labels, classic title and category switches
  read their new owners; negative backup checks scan all feature files.
  Search-bar bare radii move as 3 to the extracted map; the screen keeps 1
  and its sole token call until step 3.
- Both theme manifest consumers include all seven presentation files using
  exact per-directory patterns. The move checker now verifies the named
  first-parameter, live-getter and forwarder edits. AST-specific argument /
  parameter trailing commas may follow dart format; record commas retain
  their semantics and a mutation self-test verifies this distinction.
- A first focused run exposed an incorrect source-test owner for the classic
  Sync/Migrate title. The assertion was redirected to its actual owner;
  both Sync/Migrate tests then passed. The final focused run has 85 success,
  2 failure, 1 error and passes comparisons against both the observed full
  baseline and step 0, including the production-order and disposal identities.
  The architecture guard, ratchet, move/partition/context checks with self-tests,
  formatting and diff checks pass. Whole-repo analyzer comparison identifies
  exactly two added prefer_const_constructors infos in the moved classic body;
  changing its widget const calls is forbidden by this move-only plan.
  The user rejected lint suppressions and authorized two exact named exceptions:
  `production_api_annotation` removes only `@visibleForTesting` from the
  production `shouldApplyPendingCredentialOverride` API; its now-unused
  annotation import and the draft screen-wide ignore are removed.
  `classic_update_indicator_const` adds `const` only to the flagged update
  trailing `SizedBox` (20 × 20, stroke width 2.5). Its nested
  `CircularProgressIndicator` inherits the const context, resolving both
  flagged infos without adding an unnecessary nested const. The manifest
  records both edits and the checker compares the complete declarations
  against exactly those baseline transformations. Beyond the named exceptions,
  no other annotation, widget const call, signature, default or diagnostic
  suppression is allowed.
  Both draft public-constructor ignores are removed. The intermediate analyzer run
  (`analyze-step1-exceptions.txt`) has no removed diagnostics and exactly two
  added `use_key_in_widget_constructors` infos, one each on `SettingsLayout`
  and `SettingsSearchBar`. The user approved `public_widget_key`: add optional
  `super.key` to exactly those two const constructors, matching the reviewed
  `constructor-key-proposal.diff`. No caller passes a key, so existing calls,
  defaults and behavior remain unchanged. The manifest records each constructor
  and the checker requires the exact added parameter with all other tokens
  unchanged. For the rest of this run, the same exception is authorized only
  when a private-to-public widget move exposes `use_key_in_widget_constructors`;
  record every such constructor. Any other new diagnostic requires approval.
  The exception-focused run (`settings/step1-exceptions`) passes all 12 tests,
  including the pure helper, production index/order, disposal and TV spotlight
  behavior. Comparisons against the observed full baseline and prior focused
  step 1 run pass with no missing tests, new failures or skips. Move checks
  and all self-tests, architecture/size checks, formatting and diff checks pass.
- Final step 1 verification at `dd7dc356` plus the reviewed worktree:
  `analyze-step1-final.txt` matches all 832 baseline diagnostic identities after
  the Settings-only relocation rule: no added or removed diagnostics. The
  constructor-focused run (`settings/step1-key`) passes all 10 tests and its
  comparison against the observed full baseline passes. Earlier 12-test
  exception evidence and the full focused batch remain applicable. Formatting,
  move/partition/context checks with all self-tests, architecture/size checks
  and `git diff --check` pass. No lint suppressions remain in the Settings
  source set. The single new key parameter preserves each const constructor
  and every existing default; checker self-tests reject missing/required keys,
  changed defaults and lost const capability.
- Continuation audit retained the user's intervening `dd7dc356` IPTV-test cleanup
  commit. The SDK still matches the recorded evidence. A diagnostic full-suite
  run (`settings/step1-full`) completed because that commit changed shared
  refresh infrastructure after the original baseline; it is not a named gate.
  Result: 10,306 success, 14 failure, 29 error, 20 skipped. Comparison against
  `settings/base.jsonl` passes by identity: no new failures, missing tests or
  new skips; the only two added identities are the passing order/disposal
  contracts. Both those tests also pass in this full-suite run.
- Move-check coverage now also rejects unregistered destination helpers,
  classes/functions and duplicate fields. Context-guard evidence compares the
  canonical prefix of the original first-use statement as well as mounted /
  await order, so acquisition above a synchronous early return or a service
  call is rejected too. Await boundaries use the operand's end: arguments
  such as `await show(context)` are evaluated before suspension, and the
  legal first-statement acquisition remains accepted. Added positive/negative
  self-tests pass; the launcher verifier and its self-tests still pass with
  the extended parser. Application code remains unchanged by these verification
  improvements. The earlier `lint-exceptions-proposal.diff` is rejected and
  superseded by the user's two named exceptions above. The checker rejects
  added lint suppressions, retained/extra API annotations, API body changes,
  missing/misplaced indicator consts and any other indicator edits. No approval
  is inferred for any other new diagnostic.

### Step 2 — summaries and connection views

- Step 1 commit: `dd2aa11a`. Baseline SDK/configuration and diagnostic/test
  identities remain applicable; no dependency or engine change.
- `SettingsSummaries` owns all 73 original summary fields (88 lines), preserving
  initializers and their relative order. One instance belongs to each Settings
  State; every existing load, action, search and layout read/write uses it.
  Focus node/handler and update resources retain their previous owners.
- `SettingsConnections` owns the 13 connection getters and two failure-caption
  helpers (198 lines). It reads current summaries and borrows the original
  typed action tear-offs through a narrow record. No connection snapshot is
  retained. Production layout and search callers use these getters.
- The five new constructor/dependency/wiring leaves are registered exactly in
  `settings_scaffolding.json`; the move check rejects missing/changed scaffolds
  and unregistered additions. Necessary braces around qualified single-value
  string interpolation preserve the original value; mutation self-tests reject
  another field/expression. Original comments move with their responsibilities.
- `settings/step2`: all 24 affected tests pass, including summary authorization,
  profile remounts, pending credentials, real index ordering, TV rendering and
  disposal. Comparisons against both the original full baseline and observed
  step 1 run pass. Two new connection-boundary tests pass, verifying live
  status/failure/availability precedence, immutable prior views and unchanged
  action tear-offs. No Riverpod setup is added to this bounded legacy stage.
- `analyze-step2.txt` matches the original 832 diagnostic identities with the
  Settings relocation rule; no added or removed diagnostics. Move/partition/
  context checks and all self-tests, formatting, architecture guard, size
  ratchet and diff checks pass. State shrinks 7438 → 7218 lines. Gates 1/2
  and private CI remain pending.

### Step 3 — action sections (verified)

- Step 2 commit: `447ef585`. Actions now use the single summaries owner.
  Twelve State-owned presentation sections separate updates, release details,
  backup, restore, diagnostics, downloads, maintenance and related navigation/
  profile actions. Pure backup/report formatting lives in application code.
  Every destination is below 500 lines; State shrinks 7218 → 4832 lines.
- Section dependencies are narrow typed records. Deferred cross-section calls
  avoid construction cycles; connection views retain moved navigation tear-offs.
  The State still owns focus; `focusFirstCard` drops only its underscore for
  the borrowed callback. Updates owns the subscription/task ID, with the exact
  cancel statement registered in its disposer. State teardown retains handler
  unregistration → focus disposal → update cancellation.
- Context acquisition stays at the original first-use statement, with the
  original preceding guards/services intact. A dominating acquisition is reused
  inside nested blocks; otherwise acquisition remains local to that branch.
  Builder/dialog contexts are unchanged. The single expression-only context
  use stays inline after its original passing guard. The move/context checks
  validate all 316 declarations; new scaffolds are registered exactly.
- Permission, tvOS visibility and theme source assertions point at their new
  owners. Update permission guards remain the first statements. Theme residue
  moves as 1 to download location and 0 to release details; the facade is in
  the extracted map at 0, and the token floor remains 488.
- `settings/step3`: 87 success, 2 failure, 1 error. Comparisons against both
  the observed full baseline and step 1 pass with no new failures, missing
  tests or skips. The same three pre-existing focused failures/errors remain.
  Formatting, architecture/size checks and move/partition/context self-tests
  pass. Two additional update-permission boundary tests pass: denied actions
  cannot even read mounted/state or write preferences; a permission result
  arriving after State retirement cannot publish or persist a setting. The
  new test files analyze cleanly.
- The user approved `context-confirmation-proposal.diff` as written. The named
  exception class `context_confirmation` adds exactly 37 local checks immediately
  after the injected context acquisition, after an existing State-mounted guard
  with no intervening await. One boolean method returns `false`, as in the
  approved patch and its existing denied branch. `formatter_if_braces` wraps
  exactly the three flagged if bodies without changing condition or body.
  These patterns are pre-approved for the remaining steps and must be recorded
  per site; any other new diagnostic still requires approval. No lint ignore
  was added.
- Each affected manifest row names the exception class and points to
  `dev/tool/settings_context_exceptions.json`. The checker validates the exact
  acquisition ordinal, immediately following condition/return, full preceding
  token sequence and absence of an intervening await. It removes only those
  validated additions for the original verbatim/context comparison. Registered
  brace bodies and their preceding conditions are exact. New self-tests reject
  missing/changed/moved confirmations, changed State guards, intervening awaits,
  extra guards and changed/moved/extra brace pairs.
- Final analyzer (`analyze-step3-context.txt`): all 832 diagnostic identities
  match both step 2 and the original baseline under the Settings-only relocation
  rule; no additions or removals. The four original context infos remain.
  `settings/step3-confirmed` reruns the complete affected batch, including the
  two permission tests: 89 success, 2 failure, 1 error. Comparisons against the
  observed baseline and step 1 pass, with no missing tests or new skips. Move/
  partition/context self-tests, architecture, size, formatting and diff checks
  pass. State is 4832 lines; every extracted destination remains below 500.
- Gates 1/2 and private pushes/CI remain pending. Continue with the summary
  loader and gate 1; the full original objective remains unchanged.


### Step 4 — summary loading (gate 1 complete)

- Step 3 commit: `2f859a55`. The summaries loader, refresh orchestration and
  account-caption helpers now have separate State-owned bridge classes. All
  production callbacks use the new owners; no duplicate implementation remains.
  The facade shrinks 4832 → 4044 lines and retains indexes, platform gates,
  layout composition, focus and lifecycle until steps 5/6.
- `settings_summary_loader.dart` measures 658 lines, including imports and its
  narrow typed dependency record; the named size exception is capped at 658
  (below 800). Refresh orchestration measures 146 lines and account captions 81.
  The loader's original cached/local reads, initial scope check, captured scopes,
  error/finally guards, background refresh timing and mounted checks stay exact.
- `summaryReadOverrides` is read through `() => widget.summaryReadOverrides`
  at the original call-time position. The three download-location getters use
  narrow typed callbacks at their original read positions, registered as the
  plan's `live_getter_callback` edit on that method only. Constructors do no
  work; deferred callbacks avoid loader/refresh construction cycles.
- Five new boundary tests pass: a retained loader reads replacement overrides
  on reload; error/finally publication works in the current session and is
  rejected after disposal, lock or a same-profile epoch change. Existing
  production summary/profile-remount tests remain part of gate 1.
- The analyzer (`analyze-step4-final.txt`) retains all 832 diagnostic identities
  from step 3, with no additions or removals. Imports were pruned at their new
  owners. Formatter-inserted trailing list/set/map commas are identified by AST
  node kind; positional record commas remain significant. Self-tests cover
  unchanged literal values and strict record/callback edits.
- Gate 1 (`settings/gate1.jsonl`), Flutter 3.44.8: 10315 success, 14 failure,
  29 error, 20 skipped. Identity comparisons against both the original full
  baseline and the observed step 1 full run pass: no new failures, missing tests
  or new skips; all nine subsequently added boundary tests pass. The unchanged
  historical `test_baseline.py` comparison was replayed against both completed
  saved runner outputs, without rerunning tests or rewriting its allowlist. It
  reports the same 34 failures/errors outside its historical nine-entry list in
  both runs; the observed identity comparisons establish parity.
- Move/partition/context self-tests pass all 316 declarations; the launcher
  verifier/self-tests also pass all 154. Formatting (30 files), architecture
  (796 migrated files), size, storage-key/reference and diff checks pass.
  Analyzer comparison against the original baseline also passes with no removed
  diagnostics. Step 4 commit: `2c565186`, pushed only to `private`.
  Ubuntu CI run `37012013439` completed successfully at the exact commit
  `2c565186a1455f64cbcd714b3908166badb14f8b`: formatting/analyzer/architecture,
  size/storage and behavior jobs all pass.
  https://github.com/varunsalian/debrify-refactor/actions/runs/37012013439
  Steps 5/6 and gate 2 remain required.


### Step 5 — production search index (verified)

- Gate 1's exact-commit private CI is green. The seven platform getters and
  search navigation now have State-owned bridge classes; computed gates still
  read the shared summaries/service values when called. Search navigation
  acquires context at its original first awaited push and preserves the refresh
  after returning. The record borrows the live production index callback.
- The shell move checker passes all 316 declarations. The order/grouping/focus/
  disposal run (`settings/step5-shell`) passes all nine tests and compares cleanly
  against gate 1. One newly unused facade import was removed; no lint suppressions
  or additional diagnostic exceptions were introduced.
- Both production lists are now wired to `SettingsSearchIndex`, which creates
  fresh index/leaf builders and joins 11 slices for each list in manifest order.
  `pageOpeners` is initialized once in each fresh leaf constructor; local helpers
  become methods and local constants become static constants. Slices qualify
  those constants through their builder. All 25 new index files are below 500
  lines, with slice files below about 300. The approved original-line-4166 cut
  stays at the complete collection-if boundary.
- Index context reads stay inline at the original MediaQuery expression
  positions, so acquisition is not hoisted above preceding entry evaluation.
  The Subtitle Priority callback retains permission → State mounted guard →
  context acquisition. Its one new redundant context confirmation follows the
  standing approval and is recorded in the manifest and
  `dev/tool/settings_partition_context_exceptions.json`; `deps` is the public
  builder's typed borrowed record. No await intervenes. Live getter callbacks
  are enumerated in `settings_partition_live_getters.json` and the two manifest
  rows. Nothing else is suppressed or changed to remove a diagnostic.
- `analyze-step5-index-clean.txt` matches all 832 step 4 diagnostic identities,
  with no additions/removals. Imports were pruned at their new owners. The
  production-index order/disposal run passes both tests unchanged, exercising
  both real builders twice. The checker passes all 316 declarations and its
  self-tests, comparing complete reconstructed preambles/lists and callback
  scopes to the original. It independently checks constructor initializer order,
  matching borrowed callback bindings, fresh construction, exact physical context
  confirmations and complete collection elements. New negative cases reject
  rewired callbacks, cached builders and misplaced context/guards across slices.
- The affected batch initially found the planned Sync and Migrate source assertion
  still reading the facade. It now reads slice 09, keeping its exact registration
  assertion and all negative guards. Both theme consumers include all 51 Settings
  presentation files through their exact directory patterns. Formatting and the
  architecture guard pass; State shrinks 4044 → 684 lines and leaves the >800
  repository ratchet. Every destination is within its named cap; the largest
  index file is the 367-line leaf builder, and the largest slice is 262 lines.
- Final affected batch (`settings/step5-final`): 94 success, 2 failure, 1 error.
  Identity comparisons against the original baseline and gate 1 both pass: no
  new failures, missing tests or new skips. The three remaining identities are
  the same observed shape/profile-source failures. Move/partition/context checks
  and all self-tests, formatting (57 files), architecture (823 migrated files),
  size (1892 tracked app files), theme expansion and diff review pass.
  Step 6, its final facade cap/formatting, CI expansion and gate 2 remain required.

## Found, not fixed

(none yet)
