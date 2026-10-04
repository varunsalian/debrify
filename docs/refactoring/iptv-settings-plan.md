# IPTV settings page refactor — plan

Written 2026-10-04 on `refactor/codebase`. Follow [AGENTS.md](../../AGENTS.md).
Read `docs/refactoring/pikpak-files-plan.md`, `debrid-downloads-plan.md` and
`torbox-downloads-plan.md` first, including their Progress sections, and
`settings-screen-plan.md` for the settings conventions. This plan reuses
their technique, checker, tooling, staging and gate procedure (callback
identity checks, tree-recording evidence, real-config fixtures,
original-code worktree proofs, the wiring checklist, Linux goldens captured
from the original code in the calibrated local Docker image,
`analyzer_allowlist.txt`) and only states what differs.

Execution runs in its own git worktree on a branch cut from
`refactor/codebase` (other files are being refactored in parallel); Claude
integrates it. Commit after every step; never push. Gate commits contain
`gate`.

## Goal

`lib/screens/settings/iptv_settings_page.dart` is 4,480 lines: the IPTV
Playlists settings page. It holds:
- adding sources (M3U URL, file import, Xtream Codes), editing, removing
  (including the Admin flow for shared sources), refreshing and setting the
  default;
- channel lists (create, rename, delete, reorder through a sheet);
- hidden categories, category and channel order entry points;
- startup channel, continue-watching, channel preview, IPTV style, player
  guide style, auto-refresh interval;
- recording rows (engine toggle, scheduled recordings, max concurrent,
  battery exemption);
- a wide two-pane layout (through `IptvSettingsTwoPane`) and a narrow phone
  hub with sub-sections;
- seven private widget classes (focusable buttons, tab bar, playlist tile,
  dialogs) and the public `IptvSharedSourceDeleteDialog`.

Split it into a new feature, `lib/features/iptv_settings/`, **moving code
verbatim**. The public `IptvSettingsPage` and `IptvSharedSourceDeleteDialog`
stay importable from `lib/screens/settings/iptv_settings_page.dart` (the
facade), which keeps `lib/features/iptv/.../iptv_navigation.dart`'s import
legal.

**Why a new feature, not `lib/features/settings/` or `lib/features/iptv/`:**
both are completed migrations whose manifest checkers reject any
unregistered declaration under their folder (`check_settings_moves.py:674–705`),
and `SETTINGS_COMPLETE` rejects `TEMP(settings)`. The settings plan excluded
the pages under `lib/screens/settings/`.

**Out of scope:** `iptv_settings_two_pane.dart` (2,231 lines, its own file),
the IPTV services, storage, catalog DB and the recording services. The
facade keeps `_twoPaneKey` and its `focusRail()`/`focusAddPane()` calls.

**Architectural status:** a bounded legacy-extraction stage. Temporary
exceptions and exit milestones:
- **State-driven sections instead of Riverpod.** Exit: IPTV settings state
  in Riverpod notifiers in a later change.
- **A `legacy_iptv_settings/` bridge calling services and storage
  directly.** Exit: IPTV settings data contracts (playlists, lists,
  appearance, startup, recording) behind which the bridge dissolves.
- **Unchanged legacy text.** Exit: the app-wide localization migration.
- **Raw maps** (`_startupChannel`, `_lastLiveChannel`) stay
  `Map<String, dynamic>`. Exit: typed startup-channel models behind the data
  contracts.

## Public surface

```dart
class IptvSettingsPage extends StatefulWidget {
  const IptvSettingsPage({super.key, this.openAddSource = false});
  @visibleForTesting
  static bool showsAppearance({required bool isTelevision, required bool isDesktop})
      => isTelevision || isDesktop;
  /// (doc comment kept verbatim)
  final bool openAddSource;
}
class IptvSharedSourceDeleteDialog extends StatefulWidget {
  const IptvSharedSourceDeleteDialog({super.key, required this.playlistName,
    required this.borrowerCount});
}
```

Both stay in the facade, exactly (declaration order, doc comments, the
static). `_SharedIptvSourceDeleteDialogState` may move. Callers: the
settings connection openers (`settings_connection_navigation.dart:259,
282–285`), `lib/features/iptv/.../iptv_navigation.dart:63–66`, and three
tests.

## What it contains (line numbers at `47169f6e`; the step 0 manifest is authoritative)

| Lines | Area |
| --- | --- |
| 1–65 | 47 imports, `enum _PhoneSection` (9 values, all reachable) |
| 67–84 | `IptvSettingsPage` |
| 86–2794 | `_IptvSettingsPageState` (`SingleTickerProviderStateMixin, WidgetsBindingObserver`): 59 fields plus 1 static (one `late`: `_tabController`); `_recheckBatteryOnResume` is declared at 2761 |
| 297–310, 349–392, 2763 | `initState`, `dispose`, `didChangeAppLifecycleState` |
| 394–657 | focus-node arrays, catalog keys, hidden/category/channel order entry points, setters |
| 659–1365 | `_loadSettings`, add URL, import file, add Xtream, remove, default, refresh |
| 1367–1817 | snackbar, channel lists and sheet, list and playlist builders, edit |
| 1819–2394 | the three add-form builders, `build` (layout switch), two-pane, single column, phone hub, style pickers |
| 2396–2793 | narrow sub-views; battery, max concurrent, scheduled recordings |
| 2796–4480 | `_TvFocusableButton`, `_TvFocusableTabBar`, `_FocusablePlaylistTile`, `_PlaylistEdit`, `IptvSharedSourceDeleteDialog`, `_EditPlaylistDialog`, `_FocusableIconButton`, `_TvFocusableBackButton`, `_PlaylistNameDialog`, `_dialogButtonFocusStyle`, `_IptvListSettingsRow`, `_FocusableSettingsTile` |

No single member is over 500 lines (the largest is
`_TvFocusableTabBarState.build`, 299).

## Contracts that must not change

1. **Lifecycle, observer and ticker.** `initState`, `dispose` and
   `didChangeAppLifecycleState` stay verbatim in the State, with
   receiver-only qualification: `addObserver(this)` first; the analytics
   call; `TabController(length: 3, vsync: this)` and
   `addListener(_onTabChanged)`; the `openAddSource` section seed; the
   unawaited `_loadSettings()`. `dispose` keeps its exact order, including
   `removeObserver(this)` between disposals, the 29 single disposals and the
   three node-array loops. The State stays the observer and the ticker
   provider. `_onTabChanged` is added and removed by the same tear-off.
   `_ensureFocusNodes` keeps disposing surplus nodes as it shrinks.
2. **Layouts.** The `LayoutBuilder` switch (two-pane when `maxWidth >= 900
   && maxHeight >= 420`) keeps writing `_twoPaneActive` during build and,
   when wide off the hub, resetting `_phoneSection` with a post-frame
   `setState`. The narrow hub, its sub-sections, and `PopScope(canPop:
   _phoneSection == hub)` returning to the hub stay as they are. Platform
   gates (`showsAppearance`, the recording section on Android or desktop,
   the battery row on Android non-TV) stay identical.
3. **Adding sources.** URL add (`fetchPlaylist(url, numberingSourceKey:,
   allowUnbound: true)`, the microsecond id, the whole-list write, the
   unawaited `refreshDue()`), file import (the picker arguments, the
   byte-read fallback, decoding, the 5 MiB warning, the name dialog, the
   millisecond id) and Xtream add (server-URL normalization, `authenticate`,
   the write, `refreshDue()`), each with its double-submit flag.
4. **Removing a source.** An ordinary source is removed **immediately, with
   no confirmation**. A shared source (borrowers present) requires an Admin
   with `manageProfiles`, shows `IptvSharedSourceDeleteDialog`, re-checks the
   initiating authorization and re-validates the Admin, then revokes
   borrowers. The exact ordered sequence stays: whole-list write,
   `archiveNumberingSource`, default cleared (outside `setState`), cache
   clears and `removeCatalogsByKeys` (Xtream or URL), synchronous
   `forgetHiddenGroups`, local-file `forgetCategoryOrders` in its try/catch,
   media-store cleanups, the `mounted` check, `setState`, focus repair, the
   snackbar; the catch-all message. It isn't transactional, and that stays.
5. **Editing a source.** The cache invalidation by credential or URL
   change, `forgetHiddenGroups` over the set difference of catalog keys, and
   the rebuilt playlist (id, `addedAt`, connection fields kept,
   `credentialsRedacted: false`).
6. **Refresh.** The sequential awaited loop over sections (Xtream live, vod,
   series; M3U live), `force: true, priority: true`, breaking on a profile
   change, per-section error handling, the `_refreshingIds` busy state.
7. **Channel lists.** Create, rename, delete (its `AlertDialog`), reorder
   through the sheet (actions `rename`, `up`, `down`, `delete`; move items
   omitted at the ends; first tile autofocus).
8. **Settings writes.** Every setter keeps its storage call and key, its
   `_runProfileAction` wrapping (or lack of one: the recording engine
   toggle, battery, max concurrent and scheduled recordings aren't
   wrapped), `LookApplier.noteExternalWrite('iptv_style')` before the style
   write, the auto-refresh double `refreshDue()`, and
   `recording_max_concurrent` staying device-wide.
9. **Catalog DB.** The page never calls `runExclusive`; the move adds or
   removes no wrapping. `hiddenGroupCounts` stays synchronous inside
   `setState(_reloadHiddenCounts)`; `forgetHiddenGroups` stays synchronous
   and unawaited; `archiveNumberingSource` stays outside the gate.
10. **Profile behaviour.** `_runProfileAction` bodies run inside the captured
    profile zone, so everything created inside a body (post-frame callbacks,
    unawaited `refreshDue()`) inherits it. **Moved code keeps every such
    creation lexically inside the same closure.** The scope comparisons in
    `_loadSettings`, `_pickAutoRefresh` and refresh stay. The page relies on
    the profile gate remounting it.
11. **D-pad and focus.** The explicit arrow wiring through
    `TvTextField(onUpArrow:, onDownArrow:)` (never `node.onKeyEvent` on a
    `TvTextField`), the `NumericFocusOrder` values, `ExcludeFocus` on
    inactive tabs, the tab-bar keys, the playlist tile's LEFT/RIGHT chains,
    the back button (Select, back keys, escape, DOWN), TV entry focus, the
    section re-seed (Android TV only), focus repair after remove and
    delete-list, the shared-delete dialog swallowing activate key repeats,
    and the TV autofocus choice in the edit and name dialogs. All debug
    labels stay.
12. **Collection identity.** `_refreshingIds` is mutated in place and passed
    to the two-pane by reference; `_playlists`, `_lists` and `_hiddenCounts`
    are replaced, never mutated; `_customLists` and `_categoryOrderSources`
    return fresh lists. None of this changes.

## Destination layout

`lib/features/iptv_settings/`:
- **`application/`:** `_normalizeXtreamServerUrl` (it uses only `Uri`).
  Nothing else qualifies; `_catalogKeysFor` and
  `_catalogOwnerReferencesFor` import services, so they go to the bridge.
- **`models/`:** `_PhoneSection` and `_PlaylistEdit`, made public.
- **`presentation/`, outside the bridge:** the pure widget classes with no
  service imports (`_TvFocusableButton`, `_TvFocusableTabBar`,
  `_FocusablePlaylistTile`, `_FocusableIconButton`,
  `_TvFocusableBackButton`, `_IptvListSettingsRow`, `_FocusableSettingsTile`,
  the dialogs and `_dialogButtonFocusStyle`), if the dependency report
  confirms each has no service import. `_dialogButtonFocusStyle` is shared
  by three dialogs: co-locate them or give it one public name.
- **`presentation/legacy_iptv_settings/`:** the bridge (exact path in the
  guard): state owners and every section that takes a `BuildContext` or
  calls services, storage, the catalog DB or platform services.
- Avoid the basenames `iptv_settings_loading.dart` and
  `iptv_settings_state.dart`, which `lib/features/iptv/` already uses.
  Checker files are named `iptv_settings_manifest.tsv` and
  `iptv_settings_checker_config.json`.
- **The facade** stays an exact composition root with a 400-line cap and
  `TEMP(iptv_settings)` rejection from step 7. It keeps the two public
  classes; the State keeps its mixins, lifecycle and wiring.
- **Guard rules** (step 1): no back-imports of the facade from
  `lib/features/iptv_settings/`; no imports between `iptv_settings` and the
  `settings` or `iptv` features (except their `models/`); the exact bridge
  prefix; no service imports in `application/` or outside the bridge; 500-line
  caps.

## Technique

As in the PikPak plan, with these points:
1. **Whole widget classes move verbatim** (class plus State), renamed public
   only through manifest rows. Their own lifecycles (`initState`,
   `didUpdateWidget`, `dispose`) stay verbatim inside them; the checker
   compares each class against its original.
2. **The State's mixins stay.** Sections never become the observer or the
   ticker provider.
3. **Zone-sensitive closures.** A `_runProfileAction` body moves as one
   unit; nothing inside it is split into a separate method that would run
   outside the zone.
4. **Callback identity** (receiver path plus member, with the usual
   negatives) for `_onTabChanged`, the observer registration, and every
   tear-off handed to `IptvSettingsTwoPane` and child widgets.
5. **No new `const`** to satisfy `prefer_const_constructors`; those infos
   stay (CI ignores infos). Import reordering is an allowed edit.

## Steps

| # | Work | Notes |
| --- | --- | --- |
| 0 | Baseline, dependency report, manifest and checker config, accessor if needed, characterization tests and baselines, source-text inventory, CI list, Linux capture script | Nothing moves. |
| 1 | Guard registration; enum, `_PlaylistEdit`, `_normalizeXtreamServerUrl` | |
| 2 | The pure widget classes and dialogs | Contract 11. |
| 3 | State and resource owners; lifecycle verbatim; load, add, remove, edit, refresh, default | Contracts 1, 3–6, 9, 10. **Full-suite gate 1.** |
| 4 | Lists, hidden/category/channel order entry points, settings setters, recording rows | Contracts 7, 8. |
| 5 | Form builders, layouts, phone hub, sub-views | Contracts 2, 11. |
| 6 | `build` forwarder | |
| 7 | Final State, guards, CI. **Full-suite gate 2.** | |

### Step 0

1. **Baseline** with tree provenance; Flutter 3.44.8.
2. **Dependency report** (`docs/refactoring/iptv-settings-deps.md`) with the
   per-entry wiring checklist, including which closures are
   zone-sensitive.
3. **Checker:** manifest and config as in the PikPak plan, with fixtures
   based on the real config and negatives for callback identity, a moved
   observer, a lost mixin, and a closure split out of a profile-action body.
4. **Harness:** the `connection_secret_editor_repair_test.dart` recipe
   (sqflite ffi; `SharedPreferences` mocks; `ProfileRuntime`,
   `DeviceKeyProvider` resets; `AppStorage.debugOverride`;
   `IptvCatalogDb.debugDirectoryOverride`; `ProfileRegistry` with a
   committed profile; `MemoryDeviceSecretCipher`; IO inside
   `tester.runAsync`; closing the media DB in teardown). Add `MockClient`
   for fetch and authenticate, a fake `FilePicker`, the TV platform
   switches, and a borrower grant plus Admin for the shared-delete flow
   (`profile_credential_disconnect_test.dart` pattern). Prove one passing
   fixture first.
5. **Characterization tests,** recorded against the original code, with the
   TorBox, Real-Debrid and PikPak lessons applied up front.

   | Contract | Coverage |
   | --- | --- |
   | 1 Lifecycle | Source guards on the verbatim lifecycle and the full disposal sequence (including `removeObserver` placement); a resume test for the battery re-check; unmount during `_loadSettings`. |
   | 2 Layouts | Widget tests at narrow (< 900 px) and wide (≥ 900×420) sizes: which layout mounts, `_twoPaneActive`, the hub reset when widening off the hub, the phone hub sections and `PopScope` back to the hub, `openAddSource` in both layouts. |
   | 3 Add | URL, file and Xtream add through the real forms: exact requests (`MockClient`), the persisted list, ids, the `refreshDue()` call where observable, double-submit flags, validation and error messages, the 5 MiB warning. |
   | 4 Remove | An ordinary source (no dialog; exact ordered effects: list, default, catalog keys removed, hidden groups forgotten, media-store cleanups, snackbar); a local-file source; the shared-source flow (non-Admin refused; dialog cancel removes nothing; confirm revokes borrowers; profile change between dialog and action: "Nothing was removed"); a mid-sequence failure leaving earlier steps applied. |
   | 5 Edit | Credential and URL changes: the catalog keys removed, hidden groups forgotten for the set difference, the rebuilt playlist's fields. |
   | 6 Refresh | Section order for Xtream and M3U, `force` and `priority`, break on profile change, per-section failure, the busy state. |
   | 7 Lists | Create, rename, delete (cancel and confirm), the sheet's actions and the omitted moves at the ends. |
   | 8 Settings | Each setter's persisted key and value, the style write's `noteExternalWrite` order, the auto-refresh interval and its double `refreshDue()`, max concurrent staying device-wide. |
   | 9 Catalog DB | Source guards: no `runExclusive` in the page; `forgetHiddenGroups` unawaited; `hiddenGroupCounts` inside `setState`. |
   | 10 Profile | A profile-gate remount gives fresh owners; a profile change mid-action (the `StateError` path is characterized, not fixed). |
   | 11 D-pad | The form arrow chains, tab-bar keys, playlist tile chains, back button keys, TV entry focus in both layouts, focus repair after remove, the shared-delete dialog's key-repeat swallow (existing test kept), the dialogs' TV autofocus. |
   | 12 Identity | Through the accessor: `_refreshingIds` is the same object the two-pane receives, before and after a refresh. |

   Pixel goldens of the narrow hub, a narrow sub-section, the wide two-pane
   and the edit dialog, on macOS and Linux (Linux captured by Claude in the
   local Docker image). Record each base and compare.
6. **CI list:** the new tests as concrete paths, plus
   `test/profiles/connection_secret_editor_repair_test.dart`, which mounts
   the full page and isn't listed today.
7. **Source-text inventory:**
   - **Shape manifest:** 2 bare radii (2882, 3411), the
     `BorderRadius.vertical(top: Radius.circular(18))` at 1494 the regex
     doesn't count, and 5 token calls. The token floor (488) has **zero
     slack**, so every destination holding a token call must be registered
     in `kShapeResidue`; the others go to `kExtractedShapeResidue`.
   - **Theme registry:** `theme_surface_manifest.txt:6` with explicit
     per-directory patterns (the tools don't expand `**` recursively).
   - **Guards to extend, keeping their purpose:** the TV text-field guard
     (`test/settings_tv_input_source_guard_test.dart:8–12`) and the `print(`
     redaction scan (`test/profiles/profile_source_guard_test.dart:336`) gain
     the new feature folder.
   - `file_size_baseline.txt:13`, `check_search_architecture.py` (new
     constants and rules), `checks.yml` (format and analyze the facade,
     `test/support/iptv_settings_*`), `analyzer_allowlist.txt` (none needed
     unless a split exposes a warning), `light_ink_inventory.py` (optional).
8. **Linux capture script** (`dev/tool/capture_iptv_settings_linux_goldens.sh`).

### Per step and gates

As in the PikPak plan, with `--relocate
lib/screens/settings/iptv_settings_page.dart=lib/features/iptv_settings/`,
every existing manifest run plus this one with self-tests, and gates against
the latest IPTV-settings base.

## Definition of done

1. The facade is at most 400 lines, formatted, holding the two public
   classes and the State with its mixins, verbatim lifecycle, forwarders and
   wiring. Every caller compiles unchanged.
2. The guard registers the feature, the bridge, the facade's cap and
   `TEMP(iptv_settings)` rejection, the import bans, and the extended TV
   text-field and redaction guards.
3. All manifest runs pass with self-tests; every characterization test
   passes unchanged.
4. No new diagnostics or suppressions; the analyzer allowlist check passes;
   gate 2 passes against the latest base and gate 1.
5. Local CI-equivalent checks pass; remote CI is pending until Claude
   pushes. The test list holds the new tests; the failure allowlist gains
   nothing.
6. Progress records the commits, ownership, exceptions with exit
   milestones, seams, and pending device verification (Android TV D-pad,
   recording on Android, real IPTV providers).
7. Stop after gate 2 and report.

## Explicitly not in scope

- `iptv_settings_two_pane.dart` and every other `lib/screens/settings/` page.
- IPTV services, storage, the catalog DB, recording services.
- Merging the private widget clones with any shared widgets.
- Bug fixes and behaviour changes, including the items below.

## Progress

(empty)

## Found, not fixed

All pre-existing; the extraction keeps each exactly.
- Removing an ordinary playlist has no confirmation and no in-flight guard;
  the removal sequence isn't transactional, and its catch-all reports
  failure after partial changes.
- A profile change mid-action raises an unhandled `StateError` for callers
  that drop the `_runProfileAction` future.
- Some profile-action bodies use `context` or `setState` before a fresh
  `mounted` check.
- TV focus repair after remove and delete-list ignores `_twoPaneActive`; the
  TV re-seed gates differ (`isAndroidTvCached` versus `isTelevision`).
- `_TvFocusableTabBarState` and `_FocusablePlaylistTileState` cache focus
  flags; the tab bar has no `didUpdateWidget`.
- Whole-list writes from a start-of-action snapshot can lose concurrent
  updates; `_reloadLists` has no ordering guard.
- `_loadSettings` has no error handling, so a storage throw can leave the
  spinner.
- Auto-refresh triggers `refreshDue()` twice.
- Dialogs opened from the IPTV page's plain `MaterialPageRoute` that don't
  wrap `settingsPageTheme` themselves use the ambient theme.
- Stale comments (133; `lib/theme/app_looks.dart:22`).
