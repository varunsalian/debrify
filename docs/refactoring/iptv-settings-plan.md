# IPTV settings page refactor — plan

Written 2026-10-04 on `refactor/codebase`. Follow [AGENTS.md](../../AGENTS.md).
Revised 2026-10-04 after Codex design review round 1 (twelve findings).
Read `docs/refactoring/pikpak-files-plan.md`, `debrid-downloads-plan.md` and
`torbox-downloads-plan.md` first, including their Progress sections, and
`settings-screen-plan.md` for the settings conventions. This plan reuses
their technique, checker, tooling, staging and gate procedure (callback
identity checks, tree-recording evidence, real-config fixtures,
original-code worktree proofs, the wiring checklist, Linux goldens captured
from the original code in the calibrated local Docker image,
`analyzer_allowlist.txt`, the original-code strict-lint evidence) and only
states what differs.

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
- nine private widget classes (`_TvFocusableButton`, `_TvFocusableTabBar`,
  `_FocusablePlaylistTile`, `_EditPlaylistDialog`, `_FocusableIconButton`,
  `_TvFocusableBackButton`, `_PlaylistNameDialog`, `_IptvListSettingsRow`,
  `_FocusableSettingsTile`), the `_PlaylistEdit` value class and the public
  `IptvSharedSourceDeleteDialog`.

Split it into a new feature, `lib/features/iptv_settings/`, **moving code
verbatim**. `IptvSettingsPage` stays declared in
`lib/screens/settings/iptv_settings_page.dart` (the facade);
`IptvSharedSourceDeleteDialog` moves with its State and the facade
re-exports it. Both stay importable from the facade, which keeps
`lib/features/iptv/.../iptv_navigation.dart`'s import legal.

**Why a new feature, not `lib/features/settings/` or `lib/features/iptv/`:**
both are completed migrations whose manifest checkers reject any
unregistered declaration under their folder (`check_settings_moves.py:674–705`),
and `SETTINGS_COMPLETE` rejects `TEMP(settings)`. The settings plan excluded
the pages under `lib/screens/settings/`.

**Out of scope:** `iptv_settings_two_pane.dart` (2,231 lines, its own file),
the IPTV services, storage, catalog DB and the recording services (the
Step 0b review explicitly authorizes an assertion-only refresh entry-count
probe; the operational service body remains unchanged). The
facade State keeps its single `_twoPaneKey` (`GlobalKey<IptvSettingsTwoPaneState>`);
moved bodies borrow that exact key (contract 2).

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
- **Build-time field writes** (`_twoPaneActive` and the `_phoneSection` hub
  reset inside the `LayoutBuilder`, contract 2) are a side effect in
  `build()`, which AGENTS.md disallows. Kept verbatim as a scoped exception.
  Exit: layout state derived in the Riverpod controller milestone above.

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

`IptvSettingsPage` stays in the facade, exactly (declaration, doc comments,
the static). `IptvSharedSourceDeleteDialog` and
`_SharedIptvSourceDeleteDialogState` move **together** to one presentation
file, both declarations verbatim (the State stays private: it `extends
State<IptvSharedSourceDeleteDialog>`, page 3569, so the two can't be split
across the facade without a back-import). The facade re-exports it with
`export '...' show IptvSharedSourceDeleteDialog;`; the moved removal body
(which constructs it, page 1159) imports the dialog file, never the facade.
Callers: the settings connection openers
(`settings_connection_navigation.dart:259, 282–285`),
`lib/features/iptv/.../iptv_navigation.dart:63–66`, and three tests, all
unchanged.

The facade State also keeps the static `_isDesktopPlatform` and the
`_appearanceVisible` getter (page 249–254), because the getter reads
`IptvSettingsPage.showsAppearance`; moving it would import the facade back.
Moved builders that read it (page 2191, 2339) receive a live `bool
Function()` getter evaluated where the original read it, never a captured
value.

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
| 2796–4480 | `_TvFocusableButton`, `_TvFocusableTabBar`, `_FocusablePlaylistTile`, `_PlaylistEdit`, `IptvSharedSourceDeleteDialog` (3554) and its State, `_EditPlaylistDialog`, `_FocusableIconButton`, `_TvFocusableBackButton`, `_PlaylistNameDialog`, `_dialogButtonFocusStyle` (4348), `_IptvListSettingsRow`, `_FocusableSettingsTile` |

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
   provider (`this` in `addObserver`/`removeObserver` and `vsync: this` is
   the facade State, pinned by checks). `_onTabChanged` is added and removed
   by the same tear-off. `_ensureFocusNodes` keeps disposing surplus nodes
   as it shrinks.
2. **Layouts.** The `LayoutBuilder` switch (two-pane when `maxWidth >= 900
   && maxHeight >= 420`) keeps writing `_twoPaneActive` during build. When
   wide off the hub (page 2122–2126) two separate things happen and both
   stay: `_phoneSection = hub` is assigned **synchronously** during build,
   and a **deferred** post-frame `if (mounted) setState(() {})` rebuilds the
   `PopScope` and title that were built earlier (the scoped exception
   above). The narrow hub, its sub-sections, and `PopScope(canPop:
   _phoneSection == hub)` returning to the hub stay as they are. Platform
   gates (`showsAppearance`, the recording section on Android or desktop,
   the battery row on Android non-TV) stay identical. One
   `GlobalKey<IptvSettingsTwoPaneState>` per facade State; moved bodies
   borrow it and resolve `currentState` only inside the original callbacks
   (`focusRail()`/`focusAddPane()` at their original call time), never while
   composing. The key and `_tabController` keep their identity across a
   resize and with `openAddSource`.
3. **Adding sources.** URL add (`fetchPlaylist(url, numberingSourceKey:,
   allowUnbound: true)`, the microsecond id, the whole-list write, the
   unawaited `refreshDue()`) and Xtream add (server-URL normalization,
   `authenticate`, the write, `refreshDue()`) each keep their double-submit
   flag. File import (page 859–) has **no** busy flag ("Browse Files" stays
   enabled, 1928) and gains none: the picker arguments (`FileType.any`,
   single, `withData: true`), cancel, extension rejection, supplied bytes
   first and the real-path `xFile` fallback, `M3uParser.decodeBytes`, the
   5 MiB warning tested against the **decoded `content.length`** (897), not
   bytes, the name dialog, the millisecond id.
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
   After the dialog, `if (confirmed != true || !mounted) return;` (1164)
   returns silently when the gate has remounted the page; the "Nothing was
   removed" snackbar only appears when the still-mounted State's scope was
   replaced.
5. **Editing a source.** The cache invalidation by credential or URL
   change, `forgetHiddenGroups` over the set difference of catalog keys, and
   the rebuilt playlist (id, `addedAt`, connection fields kept,
   `credentialsRedacted: false`).
6. **Refresh.** The sequential awaited loop over sections (Xtream live, vod,
   series; M3U live), `force: true, priority: true`, breaking on a profile
   change, per-section error handling, the `_refreshingIds` busy state. The
   service's queue, dedupe, retry-after and 100 ms yield
   (`iptv_catalog_refresh_service.dart:158–332`) are its own and untouched.
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
10. **Profile behaviour.** `_runProfileAction` bodies run under
    `authorization.runIfCurrent(body)`, which rejects a stale scope before
    and at the start of the body and runs it through `withCapturedScope`
    (`runZoned`, `profile_runtime.dart:76–79`). Execution inside the body,
    its awaited continuations and any async work **started** in it (the
    unawaited `refreshDue()`) keep the captured scope; post-frame callbacks
    do **not** (`addPostFrameCallback` doesn't bind the registering zone).
    **Moved code keeps every call lexically inside the same closure, and
    keeps existing post-frame scheduling exactly as it is, adding no zone
    binding.** The scope comparisons in `_loadSettings`, `_pickAutoRefresh`
    and refresh stay. The page relies on the profile gate remounting it.
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
- **`presentation/`, outside the bridge:** pure widgets are allowed here
  (the guard restricts imports only): `_TvFocusableButton`,
  `_TvFocusableTabBar`, `_FocusablePlaylistTile`, `_FocusableIconButton`,
  `_TvFocusableBackButton`, `_FocusableSettingsTile`, `_PlaylistNameDialog`,
  and `IptvSharedSourceDeleteDialog` with its State, if the dependency
  report confirms each has no service import. The top-level final
  `_dialogButtonFocusStyle` (4348, used by the shared-delete, edit and name
  dialogs) moves verbatim to its own small presentation file under one
  public name, imported by all three; co-locating the three dialogs would
  be about 550 lines, over the cap.
- **`presentation/legacy_iptv_settings/`:** the bridge (exact path in the
  guard): state owners and every section that takes a `BuildContext` or
  calls services, storage, the catalog DB or platform services. This
  includes `_EditPlaylistDialog` (it calls `IptvService`, 3743) and
  `_IptvListSettingsRow` (it takes service-owned `IptvListMeta`, 4360).
- Avoid the basenames `iptv_settings_loading.dart` and
  `iptv_settings_state.dart`, which `lib/features/iptv/` already uses.
  Checker files are named `iptv_settings_manifest.tsv` and
  `iptv_settings_checker_config.json`.
- **The facade** stays an exact composition root with a 400-line cap and
  `TEMP(iptv_settings)` rejection from step 7. It declares
  `IptvSettingsPage`, re-exports `IptvSharedSourceDeleteDialog`; the State
  keeps its mixins, lifecycle, `_twoPaneKey`, `_isDesktopPlatform`,
  `_appearanceVisible` and wiring.
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
   compares each class against its original as a declaration comparison.
   Only the facade State's lifecycle is listed in the facade-only lifecycle
   config.
2. **The State's mixins stay.** Sections never become the observer or the
   ticker provider; lifecycle and header checks pin `addObserver(this)`,
   `removeObserver(this)` and `vsync: this` to the facade State.
3. **Zone-sensitive closures.** A `_runProfileAction` body moves as one
   unit; nothing inside it is split into a separate method that would run
   outside the zone, and no post-frame callback gains or loses zone binding.
4. **Callback identity** (receiver path plus member, with the usual
   negatives) for `_onTabChanged`, the observer registration, and every
   tear-off handed to `IptvSettingsTwoPane` and child widgets. Most of these
   are named arguments; `torbox_callback_identity.py:75` resolves positional
   arguments only, so step 0 adds named-argument support with negatives on
   real constructor calls (wrong member, wrong receiver, wrapping closure,
   missing argument).
5. **Constructors and analyzer evidence.** Constructor bodies, `const`
   capability and keys stay as they are: no new `const`, no added `Key?
   key` parameters. Import reordering is an allowed edit. CI's ignoring of
   infos is not the comparison: `suite_evidence.py:84` parses every
   severity and relocation only matches existing identities, while the
   destination `lib/features/analysis_options.yaml` adds
   `prefer_const_constructors` and making the nine private widget classes
   public exposes `use_key_in_widget_constructors`. Follow the Debrid and
   PikPak strict-lint procedure: step 0 analyzes the original code under the
   unchanged destination lint configuration in the original-code worktree
   (import URI qualification only) and records that original strict
   baseline, plus an observed inventory of the `use_key_in_widget_constructors`
   identities produced by exactly the manifest's permitted public renames
   (run on a throwaway rename-only tree). The relocation comparison
   combines these by maximum observed count (never summing), and a
   per-symbol check maps every destination diagnostic to the same original
   or inventoried symbol, rule and message. Zero additions; no broad info
   ignore, suppression or allowlist growth beyond those exact identities.

## Steps

| # | Work | Notes |
| --- | --- | --- |
| 0 | Baseline, strict-lint evidence, dependency report, manifest and checker config, named-argument callback resolver, accessor if needed, characterization tests and baselines, source-text inventory, CI list, Linux capture script | Nothing moves. |
| 1 | Guard registration; enum, `_PlaylistEdit`, `_normalizeXtreamServerUrl` | |
| 2 | The pure widget classes, the shared-delete dialog (with facade re-export), the name dialog and the shared button style | Contract 11. |
| 3 | State and resource owners; lifecycle verbatim; load, add, remove, edit (with `_EditPlaylistDialog`), refresh, default | Contracts 1, 3–6, 9, 10. **Full-suite gate 1.** |
| 4 | Lists (with `_IptvListSettingsRow`), hidden/category/channel order entry points, settings setters, recording rows | Contracts 7, 8. |
| 5 | Form builders, layouts, phone hub, sub-views | Contracts 2, 11. **Blocked until** the Linux originals are captured from the step 0 checkpoint, verified and strictly rerun. |
| 6 | `build` forwarder | |
| 7 | Final State, guards, CI. **Full-suite gate 2.** | |

### Step 0

1. **Baseline** with tree provenance; Flutter 3.44.8. Plus the original
   strict-lint baseline and rename inventory (technique 5).
2. **Dependency report** (`docs/refactoring/iptv-settings-deps.md`) with the
   per-entry wiring checklist, including which closures are
   zone-sensitive and which post-frame callbacks exist.
3. **Checker:** manifest and config as in the PikPak plan, with fixtures
   based on the real config and negatives for callback identity
   (positional and named), a moved observer or `vsync`, a lost mixin, a
   closure split out of a profile-action body, and a split dialog/State
   pair. The facade-only lifecycle config lists only the main State.
4. **Harness:** the `connection_secret_editor_repair_test.dart` recipe
   (sqflite ffi; `SharedPreferences` mocks; `ProfileRuntime`,
   `DeviceKeyProvider` resets; `AppStorage.debugOverride`;
   `IptvCatalogDb.debugDirectoryOverride`, **a separate directory per
   profile/test** for catalog isolation cases, never one shared override.
   The override is global and an open connection stays on its old directory
   (`iptv_catalog_db.dart:722–727`), so each handoff awaits `closeScope()`,
   replaces the override, and reopens before incoming-profile work; tests
   assert distinct database paths and inspect both files. (Alternatively,
   use the normal profile storage paths under `AppStorage.debugOverride` and
   exercise the production handoff.)
   **Refresh isolation:** seed refresh interval `0` for the profiles in
   manual-loop tests (explicit discovery then returns immediately while
   `force: true` refreshes stay enabled, as in
   `test/iptv_catalog_refresh_service_test.dart:410`); dispose timers and
   drain outstanding work before closing databases.
   **Parser isolation:** pass `--parser-package <isolated package_config.json>`
   (`check_verbatim_moves.py:347`) to every manifest run, from a package
   initialized with the pinned lockfile (as in PikPak Progress);
   `ProfileRegistry` with a committed profile; `MemoryDeviceSecretCipher`;
   IO inside `tester.runAsync`; closing the media DB in teardown). Add
   `MockClient` for fetch and authenticate (feasible: the downloads run on
   the calling isolate), a fake `FilePicker`, the TV platform switches, and
   a borrower grant plus Admin for the shared-delete flow
   (`profile_credential_disconnect_test.dart` pattern). The
   `IptvCatalogRefreshService` singleton is settled and reset before each
   fixture, and pending actions are drained before DBs close. Prove one
   passing fixture first.
5. **Characterization tests,** recorded against the original code, with the
   TorBox, Real-Debrid and PikPak lessons applied up front.

   | Contract | Coverage |
   | --- | --- |
   | 1 Lifecycle | Source guards on the verbatim lifecycle and the full disposal sequence (including `removeObserver` placement, observer `this` and `vsync: this`); a resume test for the battery re-check; unmount during `_loadSettings`. |
   | 2 Layouts | Widget tests at narrow (< 900 px) and wide (≥ 900×420) sizes: which layout mounts, `_twoPaneActive`, the hub reset when widening off the hub (the synchronous `_phoneSection` value and, separately, the post-frame rebuild of `PopScope`/title), the phone hub sections and `PopScope` back to the hub, `openAddSource` in both layouts. Identity of `_twoPaneKey` and `_tabController` across resize and `openAddSource`; `focusRail()`/`focusAddPane()` resolved at callback time. |
   | 3 Add | URL and Xtream add through the real forms: exact requests (`MockClient`), the persisted list, ids, the `refreshDue()` call where observable, the double-submit flags, validation and error messages. File import (no guard): picker arguments, cancel, extension rejection, supplied bytes, real-path fallback, decoding (UTF-8 and latin1), the warning threshold on decoded length (a fixture whose byte and decoded lengths straddle 5 MiB differently), a repeated tap opening a second picker. |
   | 4 Remove | An ordinary source (no dialog; exact ordered effects: list, default, catalog keys removed, hidden groups forgotten, media-store cleanups, snackbar); a local-file source; the shared-source flow: a non-Admin **owner** of a resource with a borrower grant is refused; dialog cancel removes nothing; confirm revokes borrowers; a mid-sequence failure leaving earlier steps applied. Profile scenarios below. |
   | 5 Edit | Credential and URL changes: the catalog keys removed, hidden groups forgotten for the set difference, the rebuilt playlist's fields. |
   | 6 Refresh | Manual-loop cases run with automatic discovery disabled; discovery is tested separately. Full-call source guards pin `force: true, priority: true`; behaviour pins request order for Xtream and M3U, per-section failure, termination on a stale scope, and that the busy set passed to the two-pane is the same `_refreshingIds` object throughout. |
   | 7 Lists | Create, rename, delete (cancel and confirm), the sheet's actions and the omitted moves at the ends. |
   | 8 Settings | Each setter's persisted key and value, the style write's `noteExternalWrite` order, the auto-refresh interval and its `refreshDue()` invocation sites (two for a nonzero interval: the service's own and the page's; one for Off, which skips the service's; network effects tested separately, since dedupe means two invocations need not mean two downloads), max concurrent staying device-wide. Recording on the desktop host: the actual desktop recording rows, scheduled-recording counts, the device-wide limit, and the absence of the Android engine and battery controls. Platform predicates are never bypassed; the accessor may test the resume-flag clearing and the non-Android `false` from `LiveRecordingService` (`_invokeBool`, `live_recording_service.dart:885`; `Platform.isAndroid` at page 685). Android engine and battery behaviour is pending device verification. |
   | 9 Catalog DB | Source guards: no `runExclusive` in the page; `forgetHiddenGroups` unawaited; `hiddenGroupCounts` inside `setState`. |
   | 10 Profile | Four distinct, observable scenarios, each asserting the actual stored writes and grants for **both** profiles: (a) a real gate remount gives fresh owners, and an in-flight removal returns at its `mounted` check (1164) with no snackbar; (b) the mounted State's scope is replaced during the shared confirmation: "Nothing was removed", nothing written; (c) a stale scope rejected before the body starts (`runIfCurrent` pre-check): no write; (d) a body held mid-operation across a switch, per held operation and boundary: captured-scope preference setters completing for the originating profile; `setIptvPlaylistsAndReload` persisting and then throwing at its live-scope check (`iptv_playlist_storage.dart:168–177`); and each caller's own error handling. `runIfCurrent` checks only before entering the body, so there's no blanket mid-action `StateError`. Captured scope is tested at those boundaries, not by post-frame inheritance. |
   | 11 D-pad | The form arrow chains, tab-bar keys, playlist tile chains, back button keys, TV entry focus in both layouts, focus repair after remove, the shared-delete dialog's key-repeat swallow (existing test kept), the dialogs' TV autofocus. |
   | 12 Identity | Through the accessor: `_refreshingIds` is the same object the two-pane receives, before and after a refresh. |

   Pixel goldens of the narrow hub, a narrow sub-section, the wide two-pane
   and the edit dialog, on macOS and Linux, with deterministic state:
   playlists with **uncached** catalogs (the two-pane shows relative
   "Refreshed …" text, `iptv_settings_two_pane.dart:907`), fixed viewports
   (narrow 400×800, wide 1,200×800), the settings theme, explicit platform
   overrides (non-TV desktop) and a defined focus (none, or the named
   entry node). Recorded on original code at the checkpoint named by exact
   subject `test(iptv_settings): step 0 original-code characterization
   checkpoint`; Linux captured by Claude in the local Docker image from that
   checkpoint. Evidence lives in `refactor-evidence/iptv_settings/` and
   goldens in `test/goldens/iptv_settings/`; the checker uses an isolated
   parser cache directory, not one shared with the parallel worktrees.
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
     (`test/settings_tv_input_source_guard_test.dart:7–12`) doesn't scan this
     page today; it gains the facade **before** characterization is
     recorded, then each destination as it is created. The `print(`
     redaction scan (`test/profiles/profile_source_guard_test.dart:336`)
     gains the new feature folder.
   - `file_size_baseline.txt:13`, `check_search_architecture.py` (new
     constants and rules), `checks.yml` (format and analyze the facade,
     `test/support/iptv_settings_*`), `analyzer_allowlist.txt` (only the
     exact identities from technique 5, if any), `light_ink_inventory.py`
     (optional).
8. **Linux capture script** (`dev/tool/capture_iptv_settings_linux_goldens.sh`),
   resolving the checkpoint by its exact subject.

### Per step and gates

As in the PikPak plan, with `--relocate
lib/screens/settings/iptv_settings_page.dart=lib/features/iptv_settings/`,
every existing manifest run plus this one with self-tests, the analyzer
comparison against the original strict baseline (technique 5), and gates
against the latest IPTV-settings base. The Linux golden test stays
non-strict until the verified originals are committed (before step 5), then
becomes strict.

### Integration

Claude merges the shared registration files by **union** with the other
worktrees' changes: architecture-check registrations, shape and theme
manifests, source guards, CI paths and analyzer inventories; size ratchets
only ever lower. Claude then verifies the merged committed tree (manifests,
guards, analyzer, focused tests) and runs and records a **full-suite
comparison on it** (AGENTS.md: full suite at cross-feature integration
gates), keeping test and diagnostic identities and accounting explicitly for
each parallel branch's additions, before claiming parity.

## Definition of done

1. The facade is at most 400 lines, formatted, declaring `IptvSettingsPage`,
   re-exporting `IptvSharedSourceDeleteDialog`, and holding the State with
   its mixins, verbatim lifecycle, `_twoPaneKey`, `_isDesktopPlatform`,
   `_appearanceVisible`, forwarders and wiring. Every caller compiles
   unchanged.
2. The guard registers the feature, the bridge, the facade's cap and
   `TEMP(iptv_settings)` rejection, the import bans, and the extended TV
   text-field (facade plus every destination) and redaction guards.
3. All manifest runs pass with self-tests (including the named-argument
   callback negatives); every characterization test passes unchanged.
4. Zero analyzer additions against the original strict baseline and
   rename inventory, by whole-analyzer relocation and per-symbol
   comparison; no suppressions; the analyzer allowlist check passes; gate 2
   passes against the latest base and gate 1.
5. Local CI-equivalent checks pass; remote CI is pending until Claude
   pushes. The test list holds the new tests; the failure allowlist gains
   nothing. Linux originals are verified with provenance and the Linux
   golden test is strict.
6. Progress records the commits, ownership, exceptions with exit
   milestones (including the build-side-effect exception), seams, and
   pending device verification (Android TV D-pad, recording engine and
   battery on Android, real IPTV providers).
7. Stop after gate 2 and report.

## Explicitly not in scope

- `iptv_settings_two_pane.dart` and every other `lib/screens/settings/` page.
- IPTV services, storage, the catalog DB, recording services.
- Merging the private widget clones with any shared widgets.
- Bug fixes and behaviour changes, including the items below.

## Progress

- Step 0 complete (commit recorded by its exact checkpoint subject) on `refactor/iptv-settings`, baseline `4f3ee3b3`.
  `flutter pub get` ran here first; Flutter 3.44.8 / Dart 3.12.2, no dependency
  or lockfile changes. Original facade: 4,480 lines; seam-only facade: 4,585.
- Original full suite `iptv_settings/base`: 10,577 successes, 13 failures,
  28 errors, 20 skipped. Seam-only `base2` has exactly the same identities
  and outcomes; comparison PASS. The historical failure file was not used
  to accept failures that passed in these observed runs.
- Original-code proofs use a disposable detached `4f3ee3b3` worktree nested
  under this authorized worktree's ignored `.dart_tool/iptv_settings_original`.
  No pre-existing worktree or main-checkout source was accessed or modified.
  Evidence is in the authorized common `refactor-evidence/iptv_settings/`
  namespace. The parser is separately pinned there with the checked-in lock;
  every manifest command explicitly supplies its isolated `--parser-package`.
- The frozen accessor returns actual fields and method tear-offs; no service,
  clock, constructor, or platform predicate seam. The seam-only 105-line size
  increase is recorded once; later size ratchets only lower. The TV text-field
  guard includes the original facade before characterization.
- Original strict probe: 15 infos (9 directive-order, 2 const, 4 deprecated
  Radio arguments). Manifest public-renames-only probe: 24 infos, adding
  exactly nine widget-key constructor identities. Neither probe edits const
  capability, constructor keys, bodies, or lint configuration. Import URI
  qualification only; corrected preliminary URI probes are retained as
  preliminary evidence, not accepted baselines. The checked-in symbol
  inventory combines counts by maximum, never sum; the per-symbol checker
  rejects any other identity or scaffold diagnostic.
- Dependency report and all 168 manifest leaves have explicit destinations
  and a per-entry wiring checklist. Callback checks have additive named-
  argument resolution; real-config fixtures mutate every identity site's
  member, receiver, closure wrapper and missing argument, plus disposal,
  observer, ticker/mixins, profile-body boundaries and paired dialog ownership.
- Characterization uses real profile paths, independent catalog files, actual
  registry resources/grants, persisted preference adapters and sealed saves.
  IO runs outside the fake clock; automatic refresh interval 0 isolates manual
  loops. Actions/timers drain and dialogs close before owned databases do.
  Profile cases cover gate remount, mounted confirmation replacement, pre-body
  rejection and held preference/playlist/removal saves with each caller's
  observed handling. No blanket mid-body authorization guard was invented.
- Decisions: keep the original narrow source-form overflow; golden sub-section
  is Startup at the required 400×800 viewport. Interactive narrow form tests
  use 800×1,000 without changing app layout thresholds. Back keys lacking a
  Flutter test Android raw-key mapping exercise the real focused key handler;
  Enter, Select and Escape use dispatched key events. Dialog TV autofocus
  targets Save/Import when initially valid, matching the original buttons.
- Latest baseline is `iptv_settings/base3`: 10,686 successes, the same 13
  failures / 28 errors / 20 skips; PASS versus base2 with exactly 109 added
  successful identities and no regressions/missing/new skips. Original proof
  `original-characterization`: 131 successes / the same observed direct-SharedPreferences
  source-guard failure; PASS against base3. Its tested staged tree is
  `af981a48385d3819f9b032e93feb4f609630ac72`, with no untracked inputs or tree
  change; all 14 new test/body/helper/PNG inputs are byte-identical here.
- All seven manifest/self-test runs PASS (Settings 316, IPTV 384, TorBox 195,
  Debrid 173, PikPak 128, player-launch 154, IPTV-settings 168 leaves).
  Whole analyzer: 1,635 diagnostics, zero additions/removals; new tests/helpers
  have zero diagnostics. Exact CI format (1,473 files), scoped analyzer and
  strict five-warning allowlist PASS. Architecture, strict sizes, storage
  references/self-tests/314 keys, shell syntax and staged diff checks PASS.
  No assertion, known-failure file, warning allowlist or lint suppression was
  weakened. Four original macOS PNGs were captured then strictly replayed;
  the evidence namespace records their immutable input hashes.
- Linux capture script resolves the exact checkpoint subject and uses only
  that checkpoint's tests and fixture. Linux originals remain pending and
  non-strict until verified, separately committed and strictly replayed before
  any step-5 builder moves. Android engine/battery, physical Android TV and
  provider accounts remain device-only pending checks. Remote CI and merged-
  tree integration are pending Claude; no push or branch switch.

- Step 1 complete: enum and edit value object are public models; the pure
  normalizer is a top-level application function. Production calls and the
  frozen accessor point directly to it. Exact bridge/import/500-line rules
  are registered with real positive and negative architecture checks; facade
  completion cap remains staged for Step 7. Theme, TV and shape readers cover
  the three destinations. Facade ratchet: 4,524 lines.
  `step1`: 131 successes / the unchanged observed source-guard failure, PASS
  versus latest base3, zero added/missing/newly skipped identities or new
  failures. Staged tested tree `491a7f551d71b7c10ffc944ab10be6b5b523b783`, no untracked
  inputs or change during run. All seven manifest/self-tests, exact CI format
  and analysis/five-warning allowlist, architecture/negative fixtures, sizes,
  storage references/self-tests/314 keys, capture-shell syntax and diff PASS.
  Whole analyzer remains 1,635, zero added/removed; per-symbol strict evidence
  PASS. All 109 characterization assertions and four PNGs remain unchanged.

- Step 2 complete: seven pure private widgets become manifest-named public
  widgets; their private State classes, constructor keys/const capability,
  lifecycle, focus and handlers stay verbatim. The shared-delete dialog and
  State moved together; the facade re-exports its unchanged public name. The
  shared button style has one presentation owner. Sixteen whole declarations
  moved to nine files (14–371 lines); the facade ratchet is 3,284 lines.
  Pure widgets import no services. Import-only cleanup removed unused and
  redundant directives; the two unlinked prose class references stay verbatim
  to satisfy the existing comment-preservation check. All five shape-token
  calls now live in registered presentation files, with both bare radii
  transferred and the token-free facade moved to the extracted residue map;
  the 488 floor and all assertions remain unchanged.
  `step2-final`: 131 successes / the unchanged source-guard failure, PASS
  versus base3; all 109 characterizations/four strict macOS PNGs unchanged.
  Stable staged tested tree `ab887dbecd3d028a0f76acc25e9cb2228333ac9c`; no untracked
  inputs or change during run. All seven manifests/self-tests and corrected
  real-config positives/callback negatives PASS. Exact CI format, scoped
  analyzer/five-warning allowlist, architecture/negatives, sizes, storage and
  diff PASS. Whole analyzer 1,642: seven observed constructor-key infos from
  the original rename-only probe; zero additions against the 1,655-diagnostic
  maximum-combined strict-original inventory, and per-symbol check PASS (11
  current page/destination identities). Preliminary registration failures are
  retained as failed evidence, followed by corrected runs; nothing was
  accepted with a record/update regression command.

- Step 0b independent review closure (before any Step 3 moves): the shared
  interpolation fix `def4e304` is cherry-picked as `c0f5fb87`, retaining Claude's
  trailer and adding the required Codex trailer. The named-argument resolver
  also recognizes typed constructors, necessary for the two original
  `RadioListTile<String>` sites. Hub `SettingsTile` count is 12; Channel order
  is occurrence 3, Auto-refresh occurrence 1. Both startup radio callbacks are
  pinned. Real-config checks exercise interpolated arguments, wrong members,
  wrong receivers, closures and missing arguments, with the resolver itself
  tested independently of token/scaffold failures.
- P2 removal coverage now reads durable numbering aliases/namespaces and
  preserved assignments, and actual per-source category-channel orders.
  Six later failure boundaries use the real preference adapter or SQLite
  triggers (default, catalog deletion, tolerated local category-order cleanup,
  media category orders, favorites/list membership and history); each pins
  prior persisted effects, retained UI state and the original message.
  The previous damaged-catalog failure case and assertions remain.
- Contract 9 pins `if (!mounted) return; setState(_reloadHiddenCounts)` after
  the hidden-categories route returns. Widget tests open/pop that actual route,
  change its switch and check counts/badges, reject a stale Category order
  opening with its exact message, and push/pop the actual Channel order page.
  Scenario (c) now invokes the real style setter before publishing the incoming
  scope, proving no physical preference writes for either profile, unchanged
  cached values, stored connections and grants, and the original StateError.
- P3 closes body-space 900×420 wide / 900×419 narrow (the viewport adds the
  scaffold's 56-pixel AppBar); rail DOWN/TV entry asserts `iptv-2p-rail-0`.
  Surplus node disposal, last-row/empty playlist and list focus repair, sheet
  Rename/Delete persistence and exact interleaved Xtream requests are covered.
  The runExclusive guard scans the whole facade and every destination.
  TV text-field scanning includes the feature conditionally so the original
  checkpoint remains runnable. An assertion-only, visible-for-testing service
  entry counter proves refreshDue invocations: two nonzero / one Off, including
  the early-return invocation. No service ordering, awaits or release behavior
  changes; the same probe is installed on the original proof tree.
- Golden decision: keep the checkpoint-owned fixture and PNGs byte-identical.
  The original SettingsPageScaffold already wraps the page in settingsPageTheme
  (`settings_widgets.dart`); import/edit dialogs explicitly wrap that theme too.
  ThemeData.dark() remains the host's ambient fallback, preserving the actual
  original caller. The golden loop changes only missing, non-strict Linux
  reporting to markTestSkipped; rendering/capture inputs stay unchanged, so
  the Linux capture at `8a6e1cf9` remains applicable. No golden update is used.
- Original proof is a new detached worktree at exactly `8a6e1cf9`, nested under
  this dedicated worktree. The facade matches that commit byte-for-byte; every
  changed/new characterization passes there (124 total, 15 added identities).
  Eleven deliberate application mutations are rejected by these tests; the
  interpolation-opener regression is separately rejected by its isolated
  resolver fixture. Mutation JSON, per-run tree env files and immutable input
  hashes are in `iptv_settings/`. All seven manifests/self-tests, architecture,
  size/storage, exact CI format/analyzer and strict allowlist pass. Final whole
  analyzer: 1,642, zero added/removed against Step 2; per-symbol strict check:
  11 original destination diagnostics, zero additions. Draft failed evidence
  is retained; corrections pin original behavior and remove only new test lint.

- Latest full baseline is `iptv_settings/base4`: 10,701 successes, the same
  13 failures / 28 errors / 20 skips; PASS versus base3 with exactly 15
  added successes, zero new failures/missing/new skips/fixes. Original
  checkpoint HEAD `8a6e1cf9`, stable staged tested tree
  `fbe271ddfb3a5f3b15a1b039f98b0d4a19ae8b55`, no untracked inputs. The original facade
  is byte-identical to the checkpoint; frozen original body JSON, all four
  macOS PNGs and the golden fixture are unchanged. `step0b-final` on moved
  code: 146 successes / the same observed direct-SharedPreferences source
  guard failure; PASS versus base4, zero additions or missing/newly skipped
  identities. Stable staged tree `d2d2bb843f701da344d6292366877cf2d1e3f972`;
  all characterization/helper/PNG inputs match the original proof byte-for-byte.
  Both planned extraction gates will compare against base4.

- Step 3 implementation: six per-State resource/state owners and ten narrow workflow sections now own load/add/import/Xtream/remove/edit/refresh/default, profile authorization, focus repair and feedback. The edit dialog and private State moved together. Actual callbacks are stable section tear-offs; State getters stay live. Lifecycle observer/ticker identity and disposal order remain verbatim. The facade is 2,003 lines; bridge files are 15–327 lines. Wiring rows for this checkpoint are reviewed.
- Step 3 conservative decisions: recording/layout receivers r/l keep the lifecycle guards within the original formatter width. One source-edit cancellation return requires formatter braces after receiver qualification; its exact original condition, prior tokens and return are registered, with no new guard or await. Borrowed-resource alias normalization is opt-in and validates the unchanged facade field; a real wrong-key fixture fails. The frozen source-body reader uses that exact alias and formatter site; assertions/body JSON are unchanged.
- Linux originals have arrived from 8a6e1cf9: four SHA-256 values match the supplied evidence, capture and original strict replay each pass four goldens in the calibrated linux/amd64 Flutter 3.44.8 container. These pending Linux-only PNG inputs stay separate from Step 3 and are not read by the macOS gate; their immutable hashes are recorded alongside gate provenance. They will be committed separately and made strict before Step 5.

- Step 3 validation corrections: exact CI format found an unformatted file-import continuation; formatting changes whitespace only. Architecture found the declared bridge absent from the shared legacy-bridge tuple. It now uses the same exact service-import exception as the other reviewed bridges; pure views, sibling paths, HTTP and facade/implementation cross-imports remain forbidden, with stronger real positive/negative checks. Interrupted preliminary gate logs are retained and never accepted; the complete gate is restarted only on this corrected stable tree.

- Step 3 complete; full-suite gate 1 PASS against latest base4: exactly 10,701 successes / 13 failures / 28 errors / 20 skips, no added/missing/fixed/newly skipped/new failures. Stable staged tested tree 2bdef2b5138918d95f6374de1690c6b12588826c; the only untracked inputs are the four separately hashed, unused-on-macOS Linux PNGs. The unchanged historical helper replays completed JSON: 41 failures/errors, the same 32 absent from its historical list; no failure list changes. All seven manifest/self-tests, exact CI format and analyzer/strict five-warning allowlist, architecture/stronger negatives, sizes/storage/diff pass. Whole analyzer 1,644, zero additions versus original strict maximum; per-symbol check 13 original identities. CI behavior check passes: 3,158 successes / two known failures. The source-body reader passes all four unchanged guards on 8a6e1cf9 and current code. Gate/env/audit and final-checks evidence are under iptv_settings/.

## Found, not fixed

All pre-existing; the extraction keeps each exactly.
- A failed default-preference remove retains the physical stored value while
  SharedPreferences clears its cached value; the facade default field remains.
- Removing an ordinary playlist has no confirmation and no in-flight guard;
  the removal sequence isn't transactional, and its catch-all reports
  failure after partial changes.
- File import has no double-submit guard ("Browse Files" stays enabled
  while a pick or parse is in flight), and its 5 MiB warning measures
  decoded characters, not bytes.
- A stale scope rejected by `runIfCurrent`'s pre-body check raises an
  unhandled `StateError` for callers that drop the `_runProfileAction`
  future; later continuations aren't re-checked, and
  `setIptvPlaylistsAndReload` can throw after it has persisted.
- Post-frame callbacks scheduled inside a profile-action body run outside
  the captured scope.
- Some profile-action bodies use `context` or `setState` before a fresh
  `mounted` check.
- A shared-source removal interrupted by a gate remount ends silently (no
  snackbar).
- TV focus repair after remove and delete-list ignores `_twoPaneActive`; the
  TV re-seed gates differ (`isAndroidTvCached` versus `isTelevision`).
- `_TvFocusableTabBarState` and `_FocusablePlaylistTileState` cache focus
  flags; the tab bar has no `didUpdateWidget`.
- Whole-list writes from a start-of-action snapshot can lose concurrent
  updates; `_reloadLists` has no ordering guard.
- `_loadSettings` has no error handling, so a storage throw can leave the
  spinner.
- With a nonzero interval, auto-refresh invokes `refreshDue()` twice (the
  service and the page).
- `build()` writes `_twoPaneActive` and `_phoneSection` (a scoped exception,
  above).
- Dialogs opened from the IPTV page's plain `MaterialPageRoute` that don't
  wrap `settingsPageTheme` themselves use the ambient theme.
- The 400-pixel narrow source form has pre-existing tab-row overflow; it is
  retained. URL/Xtream stale post-persistence throws can retain busy flags.
- Stale comments (133; `lib/theme/app_looks.dart:22`).
