# PikPak files screen refactor — plan

Written 2026-10-04 on `refactor/codebase`; design-reviewed by Codex in two rounds (no P1s); starts at `78fa0da3`. Follow [AGENTS.md](../../AGENTS.md).
Read `docs/refactoring/debrid-downloads-plan.md` and
`docs/refactoring/torbox-downloads-plan.md` first, including their Progress
sections. This plan reuses their technique, checker, tooling, staging and gate
procedure (callback-identity checks, tree-recording evidence, real-config
fixtures, original-code worktree proofs, wiring checklist, Linux goldens
captured from the original code, `analyzer_allowlist.txt`) and only states
what differs.

Work on the existing `refactor/codebase` branch. Commit after every step. Never
push to `origin`; push to `private` only if the goal says so. Gate commits must
contain `gate`.

## Goal

`lib/screens/pikpak/pikpak_files_screen.dart` is 3,442 lines: the PikPak cloud
drive. It holds:
- the file list with token paging;
- folder browsing (raw and A–Z sorted; series-arranged and virtual folders
  are dormant);
- playback (file, folder, multi-video);
- downloads (single file, folder through the file-selection dialog);
- playlist add (file, folder);
- add offline download by link;
- single delete (trash or permanent) and selection with batch delete;
- in-folder search;
- the restricted-folder handling, including its auto-logout;
- the select-source mode used by other screens, with network validation.

Split it into a new feature, `lib/features/pikpak_files/`, **moving code
verbatim**.
- **Unchanged:** the widget tree, keys, focus nodes, build order and the
  State's lifecycle.
- **Stays in `pikpak_files_screen.dart`:** the public `PikPakFilesScreen`
  widget (same constructor, parameters, field order and doc comment) and its
  State, with a verbatim `initState`, `dispose`, a `build` forwarder and
  section wiring. There is no `didUpdateWidget`, and none is added.

**Nothing is merged with TorBox or Real-Debrid.** Several helpers match theirs
(`_extractSeasonNumber`, `_extractLeadingNumber`, `_findFirstEpisodeIndex`,
`_formatDate`, `_autoPasteLink`, `_FolderViewMode`). They move into this
feature as copies, and no file under `lib/features/pikpak_files/` may import
`lib/features/debrid_downloads/` or `lib/features/torbox_downloads/`, or the
reverse.

**Architectural status:** a bounded legacy-extraction stage. The temporary
exceptions and their exit milestones are:
- **State-driven sections instead of Riverpod.** Exit: move the PikPak drive
  state into Riverpod notifiers in a later change.
- **A `legacy_pikpak/` bridge folder that calls services directly.** Exit: put
  `PikPakApiService`, `PikpakStorage`, `PlaylistStorage`, `DownloadService` and
  launcher calls behind PikPak data contracts, then dissolve the bridge.
- **Unchanged legacy text.** Exit: the app-wide localization migration.
- **Helpers duplicated with TorBox and Real-Debrid.** Exit: a future shared
  cloud-library plan (`docs/refactoring/cloud-library-shared-plan.md`, not yet
  written; due after the cloud-library extractions).
- **Raw mutable maps across helper and model boundaries.** Files stay
  `Map<String, dynamic>` (as the API returns them) inside helpers,
  `_PikPakPlaylistItem` and `_PikPakSearchResult`; this move adds no snapshots
  or typed models (AGENTS.md wants immutable typed models at boundaries).
  Exit: typed PikPak file models behind the data contracts above.

## Public surface

```dart
class PikPakFilesScreen extends StatefulWidget {
  final String? initialFolderId;
  final String? initialFolderName;
  final bool selectSourceMode;
  final Future<void> Function(SeriesSource)? onSourceSelected;
  /// When true, this screen was pushed as a route (not displayed in a tab).
  /// Back navigation will pop the route instead of switching tabs.
  final bool isPushedRoute;
  const PikPakFilesScreen({super.key, this.initialFolderId,
    this.initialFolderName, this.isPushedRoute = false,
    this.selectSourceMode = false, this.onSourceSelected});
}
```

This is kept exactly, including the field order, which differs from the
parameter order. It's the only public symbol. Callers: `main.dart` (tab page
1544, deep link 1791, Cloud hub 3404), `home_source_editor.dart`,
`catalog_browser.dart`, `aggregated_search_results.dart`,
`trakt_results_view.dart`, and `home_source_editor_test.dart`, which reads two
fields.

## What it contains (line numbers at `9077e335`; the step 0 manifest is authoritative)

| Lines | Area | Notes |
| --- | --- | --- |
| 1–48 | Imports (22), widget, `enum _FolderViewMode` | No top-level functions. |
| 50–138 | All 43 State fields and the getters `_selectableFileCount`, `_isAllSelected` | No `late` fields, no statics. `_deleteButtonFocusNode` (124) is declared after the two getters. |
| 140–178, 356–386 | `initState`, `dispose` | **Stay verbatim in the State.** |
| 180–314 | `_selectBoundSource` (135 lines) | Select-source validation and binding. |
| 316–354 | `_onScroll`, `_resetListScroll`, `_focusFirstItemOrFallback` | |
| 388–623 | Back navigation, settings load, restricted-folder auto-logout, loading and paging | |
| 625–780 | Filtering, folder navigation (including the dormant virtual folders) | |
| 782–1131 | Play, single download, folder download, selected-files enqueue loop | |
| 1133–1425 | Refresh, single delete, selection, batch delete, `_showSnackBar` | |
| 1427–1817 | View modes, sort, number extractors, series arrange (dormant), dropdown | |
| 1819–2081 | Search; `_isBrowsePush` getter (2080) | |
| 2083–2685 | `build` (197 lines) and builders, `_formatDate` | |
| 2687–3190 | Folder play, multi-video play, playlist add, playlist title helpers | |
| 3192–3418 | Add-link dialog, auto-paste, validation, `_addLink` | |
| 3421–3442 | `_PikPakPlaylistItem`, `_PikPakSearchResult` | Plain data. |

No single method is over 500 lines.

## Contracts that must not change

1. **Navigation and back handling.**
   - **Pushed route:** `pushRouteBackHandler(_handleBackNavigation)` and
     `popRouteBackHandler(_handleBackNavigation)`, matched by `==`.
   - **Tab:** `registerTabBackHandler('pikpak', …)`, the **key-only**
     `unregisterTabBackHandler('pikpak')`, and the TV content focus handler for
     tab **6** (a stored closure, unregistered by identity).
   - **Startup order:** `_loadSettings()` is started (unawaited) **before** the
     back handlers are registered.
   - **The 10-second "failed to open folder" pop** keeps its condition
     (`mounted && isPushedRoute && initialFolderId != null && _currentFolderId
     == null`), message, colour and timing; it can't be cancelled.
   - **Back priority** in `_handleBackNavigation` (390–428), each level
     characterized in step 0. There is no select-source level. The
     `returnToTorrentSearchOnBack` reset (421) stays.
   - **The scroll listener:** `_onScroll` is added in `initState` (144) and
     removed and re-added by `_resetListScroll` (331, 333), which runs before
     the `setState` in navigation.
2. **Select-source mode.** One callback site (294–305), awaited, then
   `if (!mounted) return; Navigator.of(context).pop();`. `SeriesSource(torrentHash:
   '', torrentName: name, debridService: 'pikpak', debridTorrentId: id,
   cloudSourceKind: folder or file, boundAt)`.
   - The validation sequence before it (video/folder check, the
     "Checking PikPak source..." dialog, which disables barrier dismissal
     only (system Back can still pop it) and is closed once with
     `rootNavigator: true`, the folder phase check, recursive listing, the
     sequential readiness probe, the file phase and URL check, and each
     rejection message) stays exactly as it is.
   - Entry points: file rows when `selectable` (2539–2570), with the folder
     "Browse folder" action and the "Still downloading" label; and search
     results (2001–2010) with no completeness check.
   - Hidden in select mode: the selection toggle and Add Link. The AppBar
     title is "Select PikPak Source".
3. **Playback handoff:** all **three launcher sites** (841, 2790, 2922) keep
   their arguments (`videoUrl`, `title`, `subtitle`, `playlist` entries with
   `relativePath`, `provider: 'pikpak'`, `pikpakFileId`, `sizeBytes`,
   `startIndex`) and their guards. The multi-video sort order (season,
   episode, lower-cased name, or name only), `_findFirstEpisodeIndex`, and
   resolving only the start entry's URL stay as they are.
4. **Downloads:** both **enqueue sites** (929, 1093) keep `credentialKey:
   'pikpak_email'`, URL (`web_content_link`), file naming, meta JSON
   (`pikpakDownload`, `pikpakFileId`, `pikpakFileName`), `torrentName` on the
   loop site, and the inline `mounted ? context : null` (934, 1099).
   - The selected-files loop stays sequential and awaited, with a fresh
     `getFileDetails` per file, the progress dialog popped in `finally`, and
     its three result messages.
   - `_downloadFolder` keeps calling it unawaited from the dialog's
     `onDownload`.
5. **Destructive actions.** Every request is a **POST** with **string** ids.
   - **Single delete:** a dialog with Cancel (autofocus), "Move to Trash" and
     "Delete Permanently". Choosing pops the dialog, then calls `_deleteFile`
     unawaited, which shows its snackbar **before** one `batchTrashFiles` or
     `batchDeleteFiles` request with `[fileId]`.
   - **Delete selected:** a `showDialog<String>` returning `'trash'`,
     `'permanent'` or null (Cancel: no request). The id snapshot is taken
     **after** the dialog closes, in insertion order. **One** awaited batch
     request, with no per-item loop and no inter-item delay. Success removes
     rows, clears the selection and leaves selection mode; failure exits
     selection mode (clearing the ids) and keeps the rows.
   - **Restricted-folder auto-logout** (`_handleRestrictedFolderDeleted`,
     479): triggered at startup when `verifyRestrictedFolderExists()` returns
     false (metadata failure or not a folder; see below), and on **any**
     `_loadFiles` error at the
     restricted root. It calls `logout()`, catches a shared-connection throw
     and shows its message. Keep all of it, including the triggers.
     - `verifyRestrictedFolderExists()` returns **false** when the metadata
       request fails or the item isn't a folder, but its outer catch returns
       **true** when reading the restriction itself throws
       (`pikpak_api_service.dart:1462`). Both branches stay.
     - After a shared-connection throw, startup returns before publishing
       settings; at the restricted root, a load failure keeps its loading
       state because the handler returns without clearing it (487, 565).
6. **Lists and views.**
   - **Loading and paging:** `listFiles` with the page token, the scroll
     threshold, `_hasMore`, `_isLoadingMore`, the early return when
     `_isLoading` (518), and filtering by `_showVideosOnly` and
     `_ignoreSmallVideos`.
   - **The view-mode dropdown** offers only Raw and Sort (A-Z), and only when
     `_navigationStack.isNotEmpty` and not in a virtual folder. Series Arrange,
     the virtual folders, the recursive cache and its search branch are
     dormant and move verbatim.
   - **Collection identity:** `_files` keeps its identity. `_applyViewMode(raw,
     _files)` returns `_files` itself, so choosing Raw clears the list (see
     "Found, not fixed"); the move must keep that aliasing exactly, not
     "fix" it by copying. `_virtualFolderFiles` stays a `cast` view.
     `_searchResults` keeps being both reassigned and mutated.
   - **Search** is synchronous over the loaded files.
7. **D-pad and focus:** the 11 focus nodes, their debug labels, the
   arrow-left Focus on the back button to `focusTvSidebar`, the dropdown's
   `autofocus: true`, focus fallback after loads, the post-frame focus
   requests, and the `FocusTraversalGroup(OrderedTraversalPolicy)`.
8. **Lifecycle:** `initState` and `dispose` stay verbatim, with receiver-only
   qualification: the analytics call, the listener add, `_loadSettings`, back
   registration, the 10-second timer, and the **14 disposals** in order, then
   `super.dispose()`.
9. **Profile behaviour:** startup settings and the cached email are read once
   from the active profile, while the API service re-reads tokens on every
   request (`pikpak_api_service.dart:713`). The screen relies on the profile
   gate remounting it. No scoping is added or removed.
10. **Add-link and playlists.**
    - **Add link:** the dialog, the clipboard auto-paste, link validation, and
      `addOfflineDownload(link, parentFolderId: _currentFolderId ??
      _restrictedFolderId)` with its exact body; the dialog pops through the
      State's `Navigator.of(context)` (3345, 3388, 3408); the unawaited
      refresh.
    - **Playlists:** the three `addPlaylistItemRaw` maps (2956, 3050, 3082),
      all `provider: 'pikpak'`, single versus collection, and the
      `listFilesRecursive` id order. Folder adds apply a **conditional
      folder-wide** 100 MiB filter (when the ignore-small-videos setting is
      on) before choosing the single or collection branch (3031); a direct
      single-file add has no size threshold (2947).

## Destination layout

`lib/features/pikpak_files/`:
- **`application/`:** pure helpers with no services and no context, if the
  report confirms them: `_extractSeasonNumber`, `_extractLeadingNumber`,
  `_findFirstEpisodeIndex`, `_isValidPikPakLink`, `_pikpakDisplayName`,
  `_formatPikPakPlaylistTitle`, `_combineSeriesAndEpisodeTitle`, and the sort
  calculation if it reads no State. Anything reading `widget`, `DateTime.now()`
  or State stays in a section; no parameter is added to make a helper pure.
- **`models/`:** `_PikPakPlaylistItem`, `_PikPakSearchResult` and
  `_FolderViewMode`, made public.
- **`presentation/legacy_pikpak/`:** the bridge (exact path in the guard):
  state owners, every section that takes a `BuildContext` or calls services,
  dialogs and builders, and the dormant code.
- **The facade** (`lib/screens/pikpak/pikpak_files_screen.dart`) is an exact
  composition root. Its 400-line cap and `TEMP(pikpak)` rejection turn on at
  step 7.
- **Guard rules,** added in step 1: no back-imports of the facade from
  `lib/features/pikpak_files/`; no imports between `pikpak_files` and
  `debrid_downloads` or `torbox_downloads`; the exact bridge prefix; no
  service imports in `application/`; 500-line destination caps from step 1.

Each destination file is at most **500 lines**.

## Technique

The same as the Real-Debrid plan's Technique, with these points:
1. **No `didUpdateWidget`; no `late` fields.** Every field keeps its
   initializer at its declaration, on its new owner.
2. **Callback identity** (receiver path plus member, checked by the checker
   with wrapping-closure and same-class receiver-swap negatives) for
   `_onScroll` (initState, `_resetListScroll` remove and re-add),
   `_handleBackNavigation` (push and pop) and the tab-6 TV focus closure.
   `_resetListScroll` moves in the same step as `_onScroll` and paging
   (step 3).
3. **`_email`'s `unused_field` warning.** Only `_loadSettings` (455) writes
   `_email`, and nothing reads it. Dart privacy is per library, so `_email`
   can stay private only if it moves into the same owner as `_loadSettings`.
   Decide this in the step 0 dependency report:
   - **Preferred:** in step 2, leave `_email` in the facade State; in step 3,
     move it as a private field into the section that receives
     `_loadSettings`, so the warning keeps firing. Then add its
     `analyzer_allowlist.txt` entry at that path, traced to the original
     warning, in the same commit.
   - **Fallback:** a public field on a state owner. The warning then
     disappears; record that under "Found, not fixed", and add no allowlist
     entry (stale entries fail).
   Never suppress it.
4. **Dormant code** moves verbatim: entry points stay private; members called
   across files get manifest-listed public names; nothing becomes reachable.
5. **The Raw aliasing bug is preserved exactly** (contract 6), and a test
   pins it.

## Steps

| # | Work | Notes |
| --- | --- | --- |
| 0 | Baseline, dependency report, manifest and checker config (`pikpak_checker_config.json`), test accessor if needed, characterization tests and their baselines, source-text inventory, CI test list, Linux capture script | Nothing moves. |
| 1 | Guard registration; enum, data classes and pure helpers | |
| 2 | State and resource owners; the lifecycle stays verbatim | |
| 3 | Back navigation, settings load and restricted-folder handling, loading and paging (with `_onScroll` and `_resetListScroll`), refresh, single and batch delete, selection, snackbar | Contracts 1, 5 and 6. **Full-suite gate 1.** |
| 4 | Filtering, folder navigation, view modes, search, select-source binding | Contracts 2, 6 and 7. |
| 5 | Play, downloads, multi-video play, playlist add, add link, dormant code | Contracts 3, 4 and 10. |
| 6 | `build` forwarder and every builder | Contract 7. |
| 7 | Final State, guards, CI. **Full-suite gate 2.** | |

### Step 0

1. **Baseline:** `suite_evidence.py run pikpak/base` and the whole-repo
   analyzer, with tree provenance. Flutter must be 3.44.8.
2. **Dependency report** (`docs/refactoring/pikpak-files-deps.md`), with the
   per-entry wiring checklist.
3. **Checker:** `dev/tool/pikpak_manifest.tsv` and
   `pikpak_checker_config.json`, as in the Real-Debrid plan, with fixtures
   based on the real config and the callback-identity negatives.
4. **Harness:** reuse the Real-Debrid harness pattern (`ProfileRuntime`
   initialized and reset, the `SecretVault` override, `http.runWithClient` with
   a `MockClient` for `api-drive.mypikpak.com`). Seed valid access and refresh
   tokens and answer with 2xx so the service's refresh and re-login never run,
   except in the cases that test them on purpose. **Successful responses must
   be JSON-map bodies:** the Real-Debrid fixture's empty 204 would fail
   PikPak's decoding (`pikpak_api_service.dart:856`). Prove one passing HTTP
   fixture first.
5. **Characterization tests,** recorded against the original code. Apply the
   TorBox and Real-Debrid lessons up front: drive actions through their real
   entry points; re-read state after acting; non-monotonic ids where order
   matters; assert values, not names; assert exact request lists; sentinel
   handlers for route versus tab registration.

   | Contract | Coverage |
   | --- | --- |
   | 1 Navigation | Widget tests: tab versus pushed route (registered and removed on dispose, sentinel handlers); each back level; folder back; the deep-link open (`initialFolderId`) and the 10-second pop's condition (source guard plus a fake-time test: mount outside `runAsync`, assert just before and at the deadline, and drain the uncancellable timer in teardown); `_loadSettings` starting before registration (source guard). Reset during scroll: no paging request, one listener. |
   | 2 Select-source | **Checking-dialog Back hazard:** with the details request held, system Back pops the dialog while `checkingDialogOpen` stays true, so the later root-navigator pop can pop the underlying screen; characterize it and keep it. Widget tests on a pushed route: a folder and a file binding (callback count, awaited before the pop, `SeriesSource` fields; the checking dialog closed exactly once by its root-navigator pop, distinguished from the later screen pop). **Disabled rows** (not selectable) through the UI; the **invalid-input rejections** (empty id, not a video or folder) through the test accessor, since a disabled row can't be tapped. Through fixtures: folder not complete, no videos, no ready streams, file not ready, and the error message. A **readiness-probe** fixture with an incomplete child, a throwing child, an unstreamable child and then a playable child: sequential requests in order, stopping after the first success. Search-result binding; the hidden selection toggle and Add Link. |
   | 3 Playback | Source guards on all three launcher sites and their arguments, plus **pending device verification**. Through the accessor where feasible: the multi-video entry order and start index for a series and a non-series folder. |
   | 4 Downloads | Source guards on both enqueue sites. Through HTTP alone: the selected-files loop's details-GET order, missing-URL failures counted as failures, and null ids skipping the GET (1069). Enqueue itself initializes connectivity and the native downloader (`download_service.dart:2176`, 1484), so **success and mixed result messages** are asserted only if an isolated enqueue fixture is first proven against the original code; otherwise they're recorded as **pending**, with the source guards kept. |
   | 5 Destructive | Widget tests with a MockClient log: single delete Cancel (no request), Move to Trash, Delete Permanently (exact POST path and `{'ids': [...]}` body), the snackbar before the request; delete selected Cancel, trash and permanent with non-monotonic insertion order, success and failure outcomes (rows, selection, mode). Restricted-folder auto-logout: at startup on a non-folder and on a metadata error (logout). The outer-catch branch (reading the restriction throws, so the service returns true) can't be reached through the screen, because `_loadSettings` reads the restriction first, outside a catch (435); characterize it with a **service-level** test of `verifyRestrictedFolderExists()` instead. on a load error at the restricted root (credentials cleared, message). **Shared-connection throw:** a committed registry, a deterministic cipher, an owner-bound `provider.pikpak` resource and a borrower grant, as in `test/profiles/profile_credential_disconnect_test.dart` (36, 273). Assert that credentials, grants and the restriction survive, and the two screen outcomes (startup returns before publishing settings; the restricted-root load keeps its loading state). |
   | 6 Lists | Widget tests: first page, paging on scroll with the page token, `_hasMore` end, filtering by both settings, Raw and Sort order, **Raw emptying the list** (pinning the aliasing; through the accessor, the Raw result is the identical `_files` object and `_files` keeps its identity through mutations; clearing the virtual list empties the backing `virtual_files` list, 765), dropdown visibility rules, synchronous search over loaded files, empty, error and not-enabled states. Series arrangement through the accessor, with a source guard on the dormant branches. Pixel goldens of the reachable views (root list, folder with dropdown, selection mode, select-source, not-enabled) on macOS and Linux, Linux from the original code (the capture script, run by Claude). Dates are fixed UTC values more than seven days old. |
   | 7 D-pad | The back button's arrow-left handler; focus on the first item after a load and its fallback; the dropdown's autofocus. |
   | 8 Lifecycle | Source guards on the verbatim lifecycle and the full 14-disposal sequence; an unmount test with a pending load on normal startup (no restricted folder): no throw. |
   | 9 Profile | A profile-gate remount gives a fresh State with new owners; two independent routes don't share owners. |
   | 10 Add-link/playlists | HTTP fixtures for add link (the exact POST body with `parent_id` from the current or restricted folder; success and failure; the refresh); the clipboard auto-paste with a platform-channel mock. Playlists: source guards on the three submitted maps; accessor tests on the persisted entries with fixed responses: one folder holding a 99 MiB and an exactly 100 MiB video gives a **single** entry with ignore-small-videos on and a **collection** (id order kept) with it off; a direct add of a small file is still accepted with the setting on. |

   - Record `pikpak/base2` after any seam, then `pikpak/base3` after the
     tests; compare each with the previous one (`PASS`, only added
     identities, all passing).
6. **CI list:** add every new test as a concrete path.
7. **Source-text inventory:** the `cloud` registry glob in
   `theme_surface_manifest.txt:5`; the shape manifest (**9 bare radii**, no
   trailing-comma radius, **5 token calls**; every destination registered,
   token files in `kShapeResidue`, the others in `kExtractedShapeResidue`, the
   final facade leaving `kShapeResidue`); `file_size_baseline.txt:23`;
   `check_search_architecture.py` (new PikPak constants and rules);
   `checks.yml` (format and analyze the facade, and add every new
   `test/support/pikpak_*` helper to the explicit format list); `analyzer_allowlist.txt`
   (`_email`); `light_ink_inventory.py` (optional); the generic profile,
   theme and storage readers (verify).
8. **Linux capture script** (`dev/tool/capture_pikpak_linux_goldens.sh`), as for
   Real-Debrid; Claude runs the capture against the resolved step-0 checkpoint.
   The Linux golden test becomes strict at step 6.

### Per step and gates

As in the Real-Debrid plan, with `--relocate
lib/screens/pikpak/pikpak_files_screen.dart=lib/features/pikpak_files/` for the
analyzer comparison, all five manifest runs (settings, IPTV, TorBox,
Real-Debrid, PikPak) with self-tests, and gates against the latest PikPak base.

## Definition of done

1. **The facade** is at most 400 lines and formatted, holding
   `PikPakFilesScreen` and the State with its verbatim lifecycle, forwarders
   and wiring. Every caller compiles unchanged.
2. **The guard** registers the feature, the exact bridge path, the facade as a
   composition root with its cap and `TEMP(pikpak)` rejection, no import of the
   facade from `lib/features/pikpak_files/`, and no imports between
   `pikpak_files` and the TorBox or Real-Debrid features.
3. **Checks:** all five manifest runs pass with self-tests, and every
   characterization test passes unchanged.
4. **Analyzer and tests:** no new diagnostics and no suppressions; the CI
   analyzer allowlist check passes; gate 2 passes against the latest PikPak
   base and gate 1.
5. **CI:** local CI-equivalent checks pass (the exact `checks.yml` format,
   analyze-plus-allowlist, architecture and size commands); remote CI on
   `private` is recorded as pending until Claude pushes. The test list holds
   the new tests; the test-failure allowlist gains nothing.
6. **Progress records:** the commits, ownership, exceptions with exit
   milestones, seams, and what is pending device verification (D-pad on
   Android TV, playback handoff, real PikPak account flows).
7. Stop after gate 2 and report.

## Explicitly not in scope

- Merging or sharing anything with TorBox or Real-Debrid.
- `PikPakApiService`, `PikpakStorage`, `DownloadService`, the player and
  launcher, `pikpak_folder_picker_dialog.dart`, the PikPak settings page.
- Bug fixes and behaviour changes, including the items below.

## Progress

### Step 0 — complete; original-code characterization

- Execution begins at `c2e02c0d`, clean `refactor/codebase`, Flutter 3.44.8 / Dart 3.12.2. No push. Original whole suite `pikpak/base`: 10,489 successes / 13 failures / 28 errors / 20 skips. Seam-only `base2` matches by identity (PASS, no additions/missing/skips). Stable tested trees and SDK recorded in env files.
- One frozen accessor adds fresh snapshots and real action tear-offs; no clock/service seam or public constructor edit. Manual seam-only facade size raise 3,442 → 3,550, ending with shrink-only scheduled extractions. Preferred private `_email` ownership is retained through step 2, moving with settings at step 3.
- 83 original-code characterization identities pass, including full 14-disposal sequence, all three launch sites, both enqueue bodies, three playlist maps, Raw aliasing/cast view, held paging/probe/download boundaries, exact request sequences, sentinel route/tab/TV handlers, callback waiting and checking-dialog Back hazard, profile gate and shared-owner logout outcomes. All 83 pass unchanged in detached original worktree `/private/tmp/debrify-pikpak-original-c2e02c0d`, plus 13 caller tests (96 total, original-verified JSON/env and byte-identical original source proof). No extraction preceded characterization.
- Test-fixture decision: explicitly schedule a frame after the legacy post-frame focus callback because adding a post-frame callback alone does not request a frame. Hold HTTP responses and drain route transition animations before checking dialog removal. Search requires actual folder navigation before its field is rendered. Every final characterization assertion is frozen only after proving original behavior.
- Five macOS goldens were captured on original code with January UTC dates; strict rerun passes. Claude runs the original-code Linux capture; the Linux test remains non-strict through step 5. The capture script resolves this checkpoint by exact subject `test(pikpak): step 0 original-code characterization checkpoint`.
- Enqueue success/mixed messages remain pending: no isolated successful native-downloader/connectivity fixture is proven. Complete original download bodies guard the sequential awaited loop and three result branches. Native launch handoffs, Android TV D-pad and real-account flows remain pending device checks.
- The dependency report tracks all 128 original leaves and a per-entry wiring checklist; scaffold pinning follows manual binding review, and production root/forwarder rules activate at step 6. Existing checker configs are unchanged. All temporary legacy extraction exceptions and exit milestones remain as specified above.

- Final original `pikpak/base3`: 10,572 successes / 13 failures / 28 errors / 20 skips; PASS against base2, exactly 83 added passing identities, no new failures/missing/newly skipped tests. This was the latest PikPak base through Step 5; Step 0b below supersedes it for subsequent comparisons. Env records stable staged tested tree `0eb4bb63436268ee27720a5d91505f49cf4c2517`, with no untracked paths or changes during the run.
- Whole analyzer: 839 diagnostics, zero additions/removals versus original. CI-equivalent format (1,423 files) and scoped analyze/strict warning allowlist (five original warnings) PASS. Original code was also analyzed under unchanged destination lint configuration in the detached worktree, with only relative-import URI qualification: 19 original diagnostics, including five directive-order infos; no const/runtime rewrite or suppression. This observed strict evidence is retained for any destination-only diagnostic relocation.
- Architecture, strict sizes, storage reference/self-tests and all 314 storage constants PASS. All five manifest/self-test runs PASS; PikPak accounts for 128 leaves and rejects all wrapping/receiver callback negatives. No historical failure list changed. Evidence lives under the common git directory in `refactor-evidence/pikpak/`; source/checker/test additions are all staged in tree evidence. Remote CI remains pending; no push.

### Step 0a — metadata correction

- Step 0 is `2b93c520`. The staged diff check exposed CRLF from the TSV writer after the earlier unstaged check passed. Corrected the manifest to LF and proved parsed rows identical before/after; no application or characterization change. The original Linux capture continues resolving `2b93c520` by its exact subject, and latest test base remains `pikpak/base3`. All subsequent staged diff checks must pass before committing.

### Step 1 — complete

- Step 0a is `e5a1b6b6`. Moved eight pure helpers, FolderViewMode and both plain data classes; production callers and frozen accessor use the actual destinations. Facade 3,550 → 3,342; largest destination 96 lines. No production scaffold is needed or pinned yet.
- Registered PikPak, exact legacy_pikpak bridge, application service ban, facade back-import ban and bidirectional cross-cloud bans, with 500-line destination caps. The facade 400-line cap/TEMP rejection stays staged until step 7. Theme and complete shape inventory preserve exactly nine bare radii / five token calls.
- All five manifest/self-test runs PASS; PikPak validates all 128 leaves and callback wrapper/same-class-receiver negatives. Initial concurrent runs encountered a shared cached parser-kernel rebuild (exit 253); reran all five successfully with the existing --parser-package option and an isolated evidence-directory cache. Checker/source rules were unchanged.
- `pikpak/step1`: 111 success / one observed pre-existing profile source-guard failure, PASS versus base3 (zero added/missing/newly skipped identities or new failures); all 83 characterization tests and five strict macOS originals unchanged. Stable staged tested tree d311f67b1088347ea04e49520f153d900a1473ab recorded. Whole analyzer 839, zero additions/removals. Architecture, sizes, storage references/self-tests/314 keys, format and staged diff checks PASS.

### Step 2 — complete

- Step 1 is `35f1bccb`. Seven state/resource owners keep every original field initializer at its declaration, original list/set/map identity, focus debug labels and controller construction. `_email` remains private in the facade. Manually reviewed each owner and all facade/accessor receivers before pinning the seven owner-handle scaffolds. Full lifecycle and 14-disposal sequence remain unchanged.
- Facade 3,342 → 3,318; largest owner 37 lines. Receiver expansion requires one named-record trailing comma in navigation and braces around the paging early return. Both are exact, manifest-listed formatting exceptions; the source reader reverses only the registered brace site with its entire prefix and body matched. Frozen characterization assertions and PNGs are unchanged.
- `pikpak/step2`: 111 successes / one observed pre-existing profile source-guard failure; PASS versus latest base3, no added/missing/newly skipped identities or new failures. Stable staged tested tree 9ec23679db9b3390acffd64d6259e178a9db2620. Whole analyzer 839 diagnostics, zero additions/removals. All five manifest/self-tests, architecture, strict sizes, storage references/self-tests/314 keys, formatting and staged diff checks PASS.

### Step 3 — complete; gate 1 PASS

- Step 2 is `d181b61d`. Moved back/focus actions, private `_email` with settings, restricted-folder logout, file loading/paging with both scroll methods, refresh, single/batch deletion, selection and feedback. All production callers use the new sections; facade 3,318 → 2,854, largest destination 262 lines.
- Manually reviewed every dependency entry against the data composition before pinning 33 scaffold declarations. Each section receives only its used owners/callbacks. Cross-section callbacks resolve the one section holder; five remaining navigation/view callbacks are deferred to the real facade until step 4. Context/widget/mounted getters are live and evaluated at original sites; no context hoisting or guard change.
- Conservative no-late decision: original fields retain declaration initializers, the State lazily caches one section composition through an explicit nullable field/getter, and composition assigns section slots once before returning them. Constructors only retain dependency records, so callbacks cannot run during wiring. No `late` fields or lifecycle initialization statement is added. Scroll/back tear-offs and the stored TV closure retain their exact owning instances.
- `_email` remains private and write-only; relocated exactly its original unused_field identity in the analyzer allowlist. Whole analyzer still 839 diagnostics, zero additions/removals by identity/relocation. CI format (1,445 files, zero changes), scoped analyzer and strict five-warning allowlist PASS.
- `pikpak/step3`: 111 successes / one observed pre-existing profile source-guard failure; PASS against base3, zero added/missing/newly skipped identities/new failures; all 83 frozen characterizations and five macOS originals unchanged. Stable staged tested tree 6f65996c5e78a4ce4eba66222f2b9370e3f01f15. All five manifest/self-tests, architecture, sizes, storage references/self-tests/314 keys, format and staged diff checks PASS. Gate 1 must run from the committed Step 3 source before dependent moves.

### Gate 1 — complete

- Step 3 source is `31ee19ac`. Full suite ran from that clean committed source, HEAD/index/tested/end tree recorded in gate1.env.json: tested tree `8c5874c542dd9cbf4f223af2f38b5f10e9f0149c`, no worktree snapshot, no untracked inputs, no changes during run; Flutter 3.44.8 / Dart 3.12.2.
- Gate 1: 10,572 successes / 13 failures / 28 errors / 20 skips. PASS against latest PikPak base3 by identity, zero added/missing/newly skipped identities and no new failures. Historical helper reused completed runner JSON, with no second runner or recording: its same 32 failure/error identities absent from the historical list are byte-identical to base3. No failure list changed.
- JSON/env/comparison/historical fingerprints are recorded in gate1-final-proof.json. Gate evidence is committed separately before Step 4. No push.

### Step 4 — complete

- Gate 1 evidence is `43025625`. Moved filtering/folder/virtual navigation, all view modes, synchronous search and awaited select-source binding. Facade 2,854 → 2,264, largest destination 267 lines. Raw identity and emptying, recursive cast aliasing, stale-list behavior, readiness-probe request order and checking-dialog Back/pops remain exactly characterized.
- Reviewed every navigation-composition entry before pinning 45 current scaffold declarations. All five deferred callbacks now resolve their real section owners; removed the obsolete deferred record, State closures and factory parameters. Source binding uses the live callback getter; no widget snapshot or context hoist. Original DateTime.now stays in the dormant series method.
- Recorded one exact formatter-brace site in getCurrentViewMode after receiver expansion. Corrected only source-reader normalization order (live widget getters before member renames) and whitespace around qualified receivers; frozen assertions are unchanged. Replayed all five source-contract identities against the unchanged original c2e02c0d worktree with the revised reader: PASS, stable tree/env recorded as original-source-reader-step4.
- `pikpak/step4`: 111 successes / one observed pre-existing profile source-guard failure, PASS versus latest base3, zero added/missing/newly skipped identities/new failures; all 83 characterizations and five macOS PNGs unchanged. Stable staged tested tree f1ce75ff1135d9b60c9e87b53b9db68e0865d9bc. Whole analyzer 839, zero additions/removals. All five manifest/self-tests, architecture, sizes, storage references/self-tests/314 keys, exact CI format (1,450 files), analyzer/strict five-warning allowlist and staged diff checks PASS.

### Step 5 — complete; stopped before Step 6

- Step 4 is `2c5f393a`. Moved file/folder/multi-video playback, file/folder/selected downloads, playlist actions and Add Link into six sections plus their composition. All production entries and the frozen accessor use the real owners. Facade 2,264 → 1,214; largest destination 276 lines. Three launcher sites, both enqueue sites, full sequential download body and three playlist maps remain verbatim; no native/service upgrade or behavior fix.
- Manually reviewed every actions-composition dependency against the checklist before pinning 64 current scaffold declarations. Feedback callbacks preserve defaults, playback/download contexts remain live at original sites, link actions reach the one link/navigation owner and original refresh action, and shared catalog settings reach the originating State. No deferred scaffold remains and no work starts during composition.
- `pikpak/step5`: 111 successes / one observed pre-existing profile source-guard failure; PASS versus latest base3, zero added/missing/newly skipped identities/new failures. All 83 frozen characterizations and five macOS originals remain unchanged. Stable staged tested tree d1f1ed8974412deea53c97974fcae2d5ac8eb99a. Whole analyzer 839 diagnostics, zero additions/removals; all five manifest/self-tests, architecture, strict sizes, storage references/self-tests/314 keys, exact CI format (1,457 files, zero changes), scoped analyzer/strict five-warning allowlist and staged diff checks PASS. Evidence fingerprints are in step5-final-proof.json.
- **Blocking prerequisite before Step 6:** zero Linux PNGs under test/goldens/pikpak_files/linux and all five linux-original-{capture,strict,sha256,revision,run-url}.txt files absent in the common evidence directory, rechecked at the checkpoint. No Linux asset was swept into a step commit. The Linux test remains non-strict, as authorized only through Step 5. Stop here: Linux original/provenance verification and its separate artifacts commit, strictness switch, Steps 6–7 and full-suite gate 2 remain pending. At this Step 5 checkpoint, Gate 1 passed against base3; Step 0b below establishes the newer base4.
- Android TV focus/repeat, all three physical launcher handoffs, real PikPak account workflows, isolated native enqueue success/mixed messages and remote CI remain pending. Existing found-not-fixed behavior below is preserved. No push.

### Step 0b — independent review closed; stop before Step 6

- Review closes on unchanged moved application `47169f6e`. Every edited/new widget case was authored and passed first in detached ORIGINAL checkpoint worktree `/private/tmp/debrify-pikpak-original-2b93c520-step0b` at `2b93c520`: all 88 PikPak characterization identities pass, including five additions. ORIGINAL screen is byte-identical to that checkpoint; all main-worktree application/dependency files remain unchanged from `47169f6e`. Only the three explicitly reviewed test fingerprints change; other frozen assertions and all five macOS PNGs are unchanged.
- **P2:** the reset fixture has ten rows and a next token, asserts `0 < maxScrollExtent < 200`, uses correctPixels(max), resets and checks offset zero plus exactly one complete request tuple. Retained the existing remove-once/re-add and both paging-token assertions. Removing both detach/reattach calls only in the ORIGINAL worktree makes this test fail with Expected 1 / Actual 2 requests. The failing JSON/env output is step0b-negative-reset-without-detach; the mutation was restored and never committed.
- **P3 tests:** episode order now differs from alphabetical order (A.S01E03/B.S01E02/C.S01E01); an added cross-season fixture also differs (A.S02E01/B.S01E02/C.S01E01). Only expected start a2 lacks a URL, other entries retain valid URLs, and exact requests/start helper values are asserted. Added restricted/deep-link Back with an empty stack (returns to restriction with no route pop), pushed empty-root false, tab initial-id timeout negative and unmount immediately before the 10-second deadline. Existing assertions remain and additional checks strengthen them.
- Eight deliberately broken ORIGINAL-only variants are rejected: no reset detach, reversed file-name sort, wrong series classification (both episode/season fixtures), removed restricted empty-stack branch, consumed pushed empty root, removed mounted timer guard, scheduling the timer for a tab, and last-two resource disposal swap. Each has complete JSON/env evidence; step0b-mutation-proof.json records variant hashes and the restored ORIGINAL hash. All mutations were restored before baseline recording.
- **P3 tooling/docs:** accurately named first-two disposal fixture and added last-two fixture, both rejected using real config on ORIGINAL and moved code. Capture script now uses checkpoint-owned tests/fixture with no current-code copy; exact-subject resolution remains `2b93c520`, shell syntax passes and both checkpoint resources exist. Fixed all six blank application owners to their top-level function/file. Step 0 and Progress now explicitly agree that Claude runs Linux capture. Claude reports private Actions blocked by billing and will calibrate local linux/amd64 Docker with Flutter 3.44.8 against existing GitHub Debrid Linux originals before capture; no Linux capture/strictness/builders are changed here.
- **New baseline:** `pikpak/base4` runs the full suite on ORIGINAL `2b93c520` with the reviewed tests: 10,577 success / unchanged 13 failure / 28 error / 20 skips. PASS versus base3; exactly five added passing identities, every previous outcome identical, no missing/newly skipped/newly failing tests. Stable staged tested tree 8f41a7d6af12a98f41fbabdd79f5fce58e08ee12, no untracked inputs or changes during run. Historical helper uses the recorded original root when replaying JSON; its same 32 unlisted pre-existing failure/error identities match base3 exactly. No historical allowlist change.
- **Moved replay after base4:** `step0b-moved-focused` at HEAD `47169f6e`, stable staged tested tree 6bce58cec3f5f4d4e4325e6c8b9f6178993b7b7d: all 88 PikPak characterizations PASS and identical to ORIGINAL; broader affected run 116 successes / the same one pre-existing `profile_source_guard_test.dart::direct SharedPreferences opens stay inside reviewed adapters/stores` failure. PASS against base4 with no added/missing/skipped/new failures. Corrected Steps 1–5's documentation label for that existing failure; recorded identities/counts are unchanged.
- Whole analyzer still 839 diagnostics, zero added/removed versus Step 5. All five manifest/self-tests and callback negatives, exact CI format (1,457 files, zero changed), analyzer/strict five-warning allowlist, architecture, sizes, storage/self-tests/314 keys, capture-shell syntax and staged diff checks PASS. JSON/env/hash proof files are in the common evidence directory; step0b-final-proof.json fingerprints the original, mutation, base4 and moved runs.
- Latest PikPak base is now base4. Existing gate1 remains historical evidence against base3 and is not relabeled as a base4 run; audit it against the new baseline when resuming the remaining gate work. Step 0b stops here as requested, with Step 6, strict Linux originals and Step 7/gate 2 pending. No push.

## Found, not fixed

All pre-existing; the extraction keeps each exactly.
- **Choosing Raw empties the list.** `_applyViewMode(raw, _files)` returns
  `_files` itself, so `_setViewMode` clears it and adds nothing back
  (1503–1511, 1553). "Folder is Empty" shows until a refresh.
- **Stale folder results.** `_loadFiles` returns early while loading, so
  navigating during a load writes the old folder's listing into the new
  folder; in-flight load-more pages have no folder guard either.
- **Restricted-folder auto-logout on transient errors,** and no `mounted`
  check between the startup check (442) and the logout or `setState` (446,
  451). The logout clears whichever profile is active when it lands.
- **Double `rootNavigator` pops** in the catch blocks of `_downloadFile`,
  `_downloadFolder`, `_playFolder` and `_addFolderToPlaylist`.
- **`_addLink`** closes dialogs with the State's `Navigator.of(context)`.
- **Key-only tab unregistration** (`'pikpak'`), as in TorBox and Real-Debrid.
- **A single-video folder with no URL** does nothing, silently (2787).
- **"Files refreshed"** shows even when the refresh was skipped.
- **Select-source checking dialog:** system Back can pop it while
  `checkingDialogOpen` stays true (194), so the later root-navigator pop
  (215) can pop the screen underneath.
- **The not-enabled "Go to Settings" button** only shows a snackbar (a TODO).
- **A deep link** can show "Opening folder..." until the 10-second pop while
  `_currentFolderId` stays null. The restricted-folder fallback can assign it
  even without an initial name (460), and a logout doesn't clear an
  already-assigned folder id (500).
- **Dormant code:** Series Arrange, the virtual folders, the recursive cache
  and its search branch, `_showFallbackToSorted` (ignores its `reason`), the
  empty `_showVideosOnly` branch, `_isAddingLink`'s effect,
  `_PikPakPlaylistItem.originalIndex`, and the write-only `_email`.
