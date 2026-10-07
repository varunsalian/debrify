# Premiumize files screen refactor — plan

Written 2026-10-06 on `refactor/premiumize-files` (a worktree branch off
`refactor/codebase` at `49c53e2e`). Follow [AGENTS.md](../../AGENTS.md).
Read `docs/refactoring/pikpak-files-plan.md` first, including its Progress
section: this plan reuses its technique, checker (`check_verbatim_moves.py`
with a per-feature manifest/config/scaffolding/accessor), staging, evidence
and gate procedure (callback-identity checks, tree-recording evidence,
real-config fixtures, ORIGINAL-code worktree proofs, wiring checklist, Linux
goldens captured from the original code, `analyzer_allowlist.txt`), and only
states what differs. `torbox-downloads-plan.md` and
`debrid-downloads-plan.md` are the older templates PikPak itself built on.

Work only in the worktree `../debrify-wt/premiumize-files` on
`refactor/premiumize-files`. Commit after every step. Never push anywhere;
never merge (the integrator merges). Gate commits must contain `gate`.

## Goal

`lib/screens/premiumize/premiumize_files_screen.dart` is 2,276 lines: the
Premiumize cloud library. It holds:
- a **Files** view browsing the server-side folder tree by id (no paging);
- a **Transfers** view (queued/running/finished magnet transfers), with
  per-transfer delete and "Clear finished";
- folder view modes (Raw and Sort A–Z, remembered per folder for the session);
- search: a **debounced server-side cloud search at the root**, a local
  filter of loaded files inside a folder, and an `initialSearchQuery` that
  starts searching on open;
- playback (file, folder, multi-video collection);
- downloads (single file, folder through the file-selection dialog);
- playlist add (file, folder);
- add-by-link (magnet/URL → Premiumize transfer, with clipboard auto-paste);
- single delete and selection with batch delete;
- the select-source mode used by the Home source editor.

Split it into a new feature, `lib/features/premiumize_files/`, **moving code
verbatim**.
- **Unchanged:** the widget tree, keys, focus nodes, build order and the
  State's lifecycle.
- **Stays in `premiumize_files_screen.dart`:** the public
  `PremiumizeFilesScreen` widget (same constructor, parameters, field order
  and doc comments) and its State, with a verbatim `initState`, `dispose`
  (including `static const int _tabIndex = 11`, used only there), a `build`
  forwarder and section wiring. There is no `didUpdateWidget`, and none is
  added.

**Nothing is merged with PikPak, TorBox, Real-Debrid or AllDebrid.** Helpers
that match theirs (`_extractSeasonNumber`, `_extractLeadingNumber`,
`_findFirstEpisodeIndex`, `_formatPlaylistTitle`, `_composeEntryTitle`,
`_FolderViewMode`, `_autoPasteLink`) move into this feature as copies. No file
under `lib/features/premiumize_files/` may import `lib/features/pikpak_files/`,
`lib/features/torbox_downloads/`, `lib/features/debrid_downloads/` or
`lib/features/alldebrid_files/` (a sibling extraction running concurrently),
or the reverse.

**Architectural status:** a bounded legacy-extraction stage, with the same
temporary exceptions and exits as PikPak:
- **State-driven sections instead of Riverpod.** Exit: Premiumize drive state
  in Riverpod notifiers, later.
- **A `legacy_premiumize/` bridge folder that calls services directly.**
  Exit: `PremiumizeService`, `PremiumizeStorage`, `PlaylistStorage`,
  `DownloadService` and launcher calls behind Premiumize data contracts, then
  dissolve the bridge.
- **Unchanged legacy text.** Exit: the app-wide localization migration.
- **Helpers duplicated with the other cloud screens.** Exit: the future shared
  cloud-library plan (`docs/refactoring/cloud-library-shared-plan.md`, not yet
  written).
- **Mutable legacy collections.** The model classes themselves
  (`PremiumizeFolderItem`, `PremiumizeTransfer`) have final fields, but the
  State's collections (`_items`, `_transfers`, `_navigationStack`,
  `_folderViewModes`, `_selectedIds`, `_searchResults`) are mutated in place
  and shared by identity between owners and sections; no snapshots are added.
  The folder dialog keeps its raw `Map<String, dynamic>` rows. Exit: immutable
  published state behind the data contracts.

## Public surface

```dart
class PremiumizeFilesScreen extends StatefulWidget {
  final String? initialFolderId;
  final String? initialFolderName;
  final String? initialSearchQuery;
  final bool selectSourceMode;
  final Future<void> Function(SeriesSource)? onSourceSelected;
  /// When true, this screen was pushed as a route (not displayed in a tab).
  /// Back navigation pops the route instead of switching tabs.
  final bool isPushedRoute;
  const PremiumizeFilesScreen({super.key, this.initialFolderId,
    this.initialFolderName, this.initialSearchQuery,
    this.isPushedRoute = false, this.selectSourceMode = false,
    this.onSourceSelected});
}
```

Kept exactly (field order differs from parameter order; both stay), with the
class doc comment. It is the only public production symbol. Step 0 adds one **testing
accessor** in the original library (`@visibleForTesting`, as PikPak's
`pikpak_test_accessor.json` pattern), an additional public testing symbol that
stays in the final facade. Callers: `main.dart` (tab
page 1551 `const PremiumizeFilesScreen()`, deep link 1816, Cloud hub 3410),
`lib/features/home/presentation/home_source_editor.dart:382` (pushed,
`initialSearchQuery`, `selectSourceMode`, `onSourceSelected`), and
`test/features/home/presentation/home_source_editor_test.dart:192`, which
reads fields. All compile unchanged.

## What it contains (line numbers at `49c53e2e`; the step 0 manifest is authoritative)

| Lines | Area | Notes |
| --- | --- | --- |
| 1–60 | 27 imports, widget, `_FolderViewMode`, `_PremiumizeView` | No top-level functions. |
| 62–140 | State fields, `_tabIndex`, getters `_isAllSelected` (104) and `_isAtRoot` (140) | No `late`. One static const. `_searchResults` is reassigned **and** mutated. |
| 142–195 | `initState`, `dispose` | **Stay verbatim in the State.** |
| 197–317 | `_loadSettings`, `_loadFolder`, `_loadTransfers`, `_refresh`, `_switchView` | |
| 319–382 | Folder navigation, `_handleBackNavigation` | |
| 384–455 | View modes, sort, number extractors | `_applySortedView` and the extractors read no State. |
| 457–528 | Search: toggle, debounce, cloud search | Owns `_searchDebounce` writes. |
| 530–613 | `_selectBoundSource` | Select-source validation and binding. |
| 615–800 | `_playFile`, `_playFolder`, `_playPremiumizeVideos` | Three launcher sites. |
| 802–910 | Downloads | Two enqueue sites; sequential loop. |
| 912–1000 | Playlist add | Three `addPlaylistItemRaw` maps. |
| 1002–1149 | Delete (single, selected), transfer delete and clear | |
| 1151–1287 | Add-link dialog, auto-paste, `_addLink` | |
| 1289–1409 | Selection helpers, loading dialog, `_dismissDialog`, focus fallback, `_showSnackBar` | |
| 1411–1484 | `_formatUnixDate` (reads `DateTime.now`), series title helpers, `_findFirstEpisodeIndex` | |
| 1486–2276 | `_isBrowsePush`, `build` (147 lines) and 13 builders | |

No single method is over 200 lines. The largest destination is expected well
under 500 lines; **no destination size exception is planned** (any need found
later is a design change that must come back for review).

**Bounded step-0 facade growth (the only size exception).** Private State
members can only be reached by an accessor declared in the original library,
so step 0 grows the formatted facade above its 2,276-line baseline. Step 0
measures the **entire formatted facade** after adding the accessor and raises
`file_size_baseline.txt:29` to that exact value in the step-0 commit (manual
raise; `--update` cannot grow a baseline), recorded with its reason. From step
1 the baseline is lowering-only and each step lowers it to the measured facade
size. `check_file_sizes.py` drops an entry once the file is 800 lines or fewer
(`check_file_sizes.py:80`), so when the facade crosses that line its baseline
entry is removed (not re-added); after removal the standard 800-line limit
applies until step 7 activates the measured architecture facade cap.
Exit milestone: step 7.

## Contracts that must not change

1. **Navigation and back handling.**
   - **Pushed route:** `pushRouteBackHandler(_handleBackNavigation)` and
     `popRouteBackHandler(_handleBackNavigation)`, matched by `==`.
   - **Tab:** `registerTabBackHandler('premiumize', …)`, the **key-only**
     `unregisterTabBackHandler('premiumize')`, and the stored TV content
     focus closure for tab **11** (`_tabIndex`), unregistered by identity.
   - **Startup order:** analytics `screenView('premiumize_files')`, then
     `_loadSettings()` (unawaited) **before** the back handlers.
   - **Back priority** (357–382): selection → search (toggle off) → folder
     stack (`_navigateUp`) → pushed route `Navigator.of(context).pop()` →
     `returnToTorrentSearchOnBack` reset and switch to
     `MainTab.legacyTorrentSearch` → `false`. Each level characterized.
   - **"Opening folder..." scaffold** while pushed, at root and on the
     initial load (1495), with its own back button popping the route.
   - **Browse push** (`_isBrowsePush`): pushed with no initial folder shows a
     root back button that calls `maybePop`.
   - **Scroll reset:** `_switchView`, `_navigateIntoFolder` and `_navigateUp`
     call `jumpTo(0)` when the controller has clients, **before** their
     `setState`.
2. **Settings load** (197–223): integration flag **and** a non-empty API key
   enable the screen; the initial folder is applied only when **both**
   `initialFolderId` and `initialFolderName` are set; a non-empty trimmed
   `initialSearchQuery` activates search and fills the controller inside the
   same `setState`; when enabled, `_loadFolder()` then
   `_performSearch(initialQuery)` (both unawaited, in that order); when
   disabled, `_initialLoad = false`. The API key is read **once**.
   With an initial folder **and** an initial query, the in-folder filter runs
   synchronously against the still-empty `_items` (the listing is in flight),
   so the results stay empty even after matching files load (preserved).
3. **Loading.** `_loadFolder` returns early on a missing key or while
   `_isLoading`; it applies the folder's current view mode to the listing,
   replaces `_items` **in place** (`clear()..addAll`), then calls
   `_focusFirstItemOrFallback()`. `_loadTransfers` has its own
   `_isLoadingTransfers` guard and replaces `_transfers` in place. Both write
   the shared `_errorMessage` and clear `_initialLoad`. `_refresh` exits
   selection mode and reloads only the active view. `_switchView` is a no-op
   for the current view, exits selection, resets scroll, clears the error,
   then loads the new view.
4. **Select-source mode.** One awaited callback site (590–601), then
   `if (!mounted) return; Navigator.of(context).pop();`.
   `SeriesSource(torrentHash: '', torrentName: item.name, debridService:
   'premiumize', debridTorrentId: item.id, cloudSourceKind: folder or file,
   boundAt: now)`.
   - Validation before it stays exactly: the "Checking folder for
     videos..." / "Checking file..." loading dialog (barrier not
     dismissible, closed once through `closeCheckingDialog` →
     `_dismissDialog`, the root-navigator pop); folder → recursive listing,
     videos only, **only the first** video's readiness (`playableUrl`
     non-empty or `resolveItemById` non-null); file → video check, then
     `resolveItemById` with a non-empty link; each rejection message; the
     catch message.
   - **Asymmetric liveness:** the folder path checks `mounted` after each
     await; the file path does **not** check `mounted` after
     `resolveItemById`, so it can invoke `onSourceSelected` after disposal,
     then checks `mounted` before popping. `widget.onSourceSelected` is read
     live at the call (not captured earlier). `item/details` failures become
     `null` inside the service (`premiumize_service.dart:534`), so the catch
     path is reached through a throwing `folder/list` (recursive listing).
   - Entry points: rows in select mode (folders and videos tap to bind;
     other files are disabled; folders have a "Browse folder" action), and
     search results, which reuse the same card.
   - Hidden in select mode: the selection toggle, Add Link and the
     Files/Transfers selector. Title "Select Premiumize Source".
5. **Playback handoff:** all **three launcher sites** (634, 699, 790), each
   preceded by `MainPageBridge.notifyPlayerLaunching()` and a `mounted`
   check, keep their `VideoPlayerLaunchArgs` exactly (`videoUrl`, `title`,
   `subtitle` (file size, or "N episodes/files • total"), `playlist` entries
   with `url`, `title`, `relativePath ?? name`, `provider: 'premiumize'`,
   `premiumizeItemId`, `sizeBytes`, and `startIndex`). `_playFile` resolves
   a missing URL by id first. The collection sort (season, episode,
   lower-cased name; or name only), the series test
   (`SeriesParser.isSeriesPlaylist`), `_findFirstEpisodeIndex` with its range
   clamp, entry titles, and `url: playableUrl ?? ''` for every entry stay.
6. **Downloads:** both **enqueue sites** (811, 887) keep `credentialKey:
   'premiumize_api_key'`, `url: item.link` (not `playableUrl`), `fileName`,
   `torrentName: folderName` on the loop site, and the inline
   `mounted ? context : null`. The folder dialog rows (`name`, `_fullPath`,
   `size` as a string, `_premiumizeIndex`), the unawaited `onDownload`, the
   sequential awaited loop with index and URL failures counted, and the
   three result messages stay.
7. **Playlists:** the three `addPlaylistItemRaw` maps (927, 962, 981) exactly,
   including key order, `FileUtils.cleanPlaylistTitle`, single versus
   collection, and video order from the recursive listing.
8. **Destructive actions.**
   - **Single delete:** a dialog (Cancel autofocus, red Delete); Delete pops,
     then calls `_executeDelete([item])` **unawaited**.
   - **Delete selected:** the item snapshot is taken **before** the dialog, in
     `_items` order; `showDialog<bool>`; on `true`, one awaited
     `_executeDelete(selected)`.
   - **`_executeDelete`:** the "Deleting N item(s)..." snackbar **before** any
     request; **sequential** per item, `deleteFolder` for folders and
     `deleteItem` for files, failures counted; then (if mounted) removes
     deleted ids from `_items` **and** `_searchResults`, clears the selection
     and leaves selection mode — even after a single delete; the two result
     messages.
   - **Transfers:** delete with its own confirm dialog, `deleteTransfer`,
     in-place removal and message; "Clear finished" calls
     `clearFinishedTransfers`, shows its message, then awaits
     `_loadTransfers()`.
9. **Search.** Toggling on clears selection and requests search focus
   post-frame; toggling off cancels the debounce and clears query, results and
   the in-flight flag. An empty query cancels the debounce and clears results.
   **At the root:** cancel, set `_isSearching`, start a **350 ms** `Timer`
   that runs `_runCloudSearch(q)`; a result is dropped if the trimmed field
   text no longer equals its query; errors clear the flag and show "Search
   failed". **In a folder:** synchronous filter of non-folder `_items` by
   lower-cased substring. The clear button and its Focus key handler
   (activate keys clear and refocus; arrow-left refocuses) stay.
   **Pending-search quirks, preserved exactly:**
   - `_performSearch('')` (typing to empty) cancels the debounce and resets
     `_isSearching`; the **clear button** paths (tap and activate key) only
     clear the controller and results — they do **not** cancel the timer or
     reset `_isSearching` (1825, 1852), and they do not call `onChanged`.
   - `_navigateIntoFolder` clears query/results and turns search off but
     leaves an armed root debounce running (321–339).
   - A stale **failure** has no query check and clears a newer search's
     `_isSearching` and shows "Search failed" (523–526).
   - Success freshness compares only the field text, so an A→B→A sequence
     accepts the first A response.
10. **Add link.** `_showAddLinkDialog` awaits `_autoPasteLink()` (clipboard
    text starting with `http://`, `https://` or `magnet:`), checks `mounted`,
    then shows the dialog (theme surface, the arrow-down `Focus` around the
    autofocus `TextField`, Cancel clearing the controller, Add enabled from
    `_isAddingLink` **as read when the dialog is built**). `_addLink`
    validates (two messages), returns on a missing key, pops the dialog with
    the **State's** `Navigator.of(context)`, sets `_isAddingLink`, shows the
    loading dialog, `createTransfer(apiKey, link, folderId:
    _currentFolderId)`, dismisses, clears, shows "Added to Premiumize",
    awaits `_refresh()`, and resets the flag in `finally` when mounted.
11. **Lists and views.** The Files/Transfers selector shows only at the root,
    outside search and select mode. The view-mode dropdown shows only in the
    Files view inside a folder (`_navigationStack.isNotEmpty`). Raw returns a
    **copy** (`List.of`) — unlike PikPak there is no Raw aliasing — and Sort
    puts folders first (season-aware) then files (leading number), each with a
    lower-cased name fallback. `_setViewMode` is ignored at the root.
    Skeleton while loading an empty folder; empty, error, not-configured and
    transfers-empty states; "Clear finished" only when a transfer is
    finished; the transfer card's status colour/icon, running progress bar
    (indeterminate at 0) and message fallback. Dates via `_formatUnixDate`
    (relative within 7 days).
12. **D-pad and focus:** the 11 focus nodes and their debug labels; the back
    button's arrow-left `Focus` to `focusTvSidebar`; the dropdown's
    `skipTraversal` Focus with arrow-up to the back button; the search field's
    `onUpArrow`/`onDownArrow`/`onRightArrow`; `_firstItemFocusNode` only on
    index 0 when `autofocusFirst` (search results pass `false`);
    `_focusFirstItemOrFallback` (post-frame; first item, else the Add Link
    button when not loading; `_shouldFocusOnLoad` set by the TV closure and by
    folder navigation); both `FocusTraversalGroup(OrderedTraversalPolicy)`s;
    the autofocused Retry and Go to Settings buttons; `TvFocusScrollWrapper`
    on transfer cards.
13. **Lifecycle:** `initState` and `dispose` stay verbatim with receiver-only
    qualification: back unregistration (pushed vs tab, TV closure by identity),
    `_searchDebounce?.cancel()`, then **14 disposals** in order (3
    controllers, 11 focus nodes), then `super.dispose()`.
14. **Profile behaviour:** the integration flag and API key are read once
    from the active profile at startup, and every **Premiumize HTTP** call
    uses that captured key. Other owners keep their existing boundaries:
    `PlaylistStorage.addPlaylistItemRaw` delegates to `savePlaylistItemsRaw`
    (`playlist_storage.dart:165`), which captures profile preferences before
    its later awaits (`playlist_storage.dart:38`), and a profile switch after
    that makes the captured instance fail its session check
    (`profile_preferences.dart:296`) rather than redirecting the write; reads
    and saves resolve preferences separately. These stale-session guards are
    retained as they are. And `DownloadService.enqueueDownload`
    resolves authorization and credential authority during enqueue
    (`download_service.dart:2178`). The screen relies on the profile gate
    remounting it. No scoping is added or removed.

## Destination layout

`lib/features/premiumize_files/`:
- **`application/`:** pure helpers with no services, no context and no
  State: `_extractSeasonNumber`, `_extractLeadingNumber`, `_applySortedView`
  (it only calls those two), `_formatPlaylistTitle`, `_composeEntryTitle`,
  `_findFirstEpisodeIndex`. `_formatUnixDate` reads `DateTime.now()` and stays
  in a section. No parameter is added to make anything pure.
- **`models/`:** `_FolderViewMode` and `_PremiumizeView`, made public with
  manifest-listed names (`PremiumizeFolderViewMode`, `PremiumizeView`).
- **`presentation/legacy_premiumize/`:** the bridge (exact path in the guard):
  state/resource owners, every section that takes a `BuildContext` or calls
  services, dialogs and builders.
- **The facade** (`lib/screens/premiumize/premiumize_files_screen.dart`) is an
  exact composition root. A provisional 400-line cap and `TEMP(premiumize)`
  rejection turn on at step 7, then the cap is lowered to the measured size.
- **Guard rules,** added in step 1: no back-imports of the facade from
  `lib/features/premiumize_files/`; no imports between `premiumize_files` and
  `pikpak_files`, `torbox_downloads`, `debrid_downloads` or `alldebrid_files`
  (both directions); the exact bridge prefix for service/storage imports; no
  service, storage, `http` or Flutter-context use in `application/`;
  500-line destination caps from step 1.

## Technique

The same as PikPak's Technique, with these points:
1. **No `didUpdateWidget`; no `late` fields.** Every field keeps its
   initializer at its declaration, on its new owner; list/set/map identity is
   preserved (`_items`, `_transfers`, `_navigationStack`, `_folderViewModes`,
   `_selectedIds` are `final` and mutated in place; `_searchResults` is
   reassigned and also mutated by `_executeDelete`).
2. **Callback identity** (receiver path plus member; wrapping-closure and
   same-class receiver-swap negatives) for `_handleBackNavigation` (push and
   pop) and the stored tab-11 TV focus closure. The 350 ms debounce `Timer`
   callback `() => _runCloudSearch(q)` keeps its closure shape.
3. **The debounce timer** (`_searchDebounce`) is a resource: it is written by
   search and cancelled by search and by `dispose`. Its field moves to an
   owner, and `dispose`'s `_searchDebounce?.cancel()` keeps its position.
4. **`_tabIndex`** is a `static const` used only by the verbatim lifecycle; it
   stays in the State. If any section needs it, that is a design change.
5. **Contexts and liveness:** `context`, `mounted`, `widget` and `setState`
   stay live getters/callbacks evaluated at their original sites (the PikPak
   receiver rules); no context hoisting, no added or removed `mounted`
   checks.
6. **Original analyzer state:** one info (`deprecated_member_use`, the
   dropdown's `value`, 1696). It moves with its builder; record the identity
   relocation. Destination lint configuration may add const/ordering infos on
   moved code; handle them exactly as PikPak did (observed original-under-
   destination-lints evidence; no rewrite, no suppression, allowlist only for
   relocated original warnings).

## Steps

| # | Work | Notes |
| --- | --- | --- |
| 0 | Baseline, dependency report, manifest/config/scaffolding/accessor, characterization tests and baselines, source-text inventory, CI test list, Linux capture script | Nothing moves. |
| 0b | Claude's independent step-0 review: close every gap (mutation proofs on ORIGINAL) | Before step 1. |
| L | Original-code Linux goldens (Claude captures in Docker), committed separately | Before step 6. |
| 1 | Guard registration; enums and pure helpers | |
| 2 | State and resource owners; the lifecycle stays verbatim | |
| 3 | Settings load, loading (files and transfers), refresh, view switching, back navigation, selection, delete (single, selected, transfers), loading dialog, `_dismissDialog`, focus fallback, snackbar | Contracts 1–3, 8, 12. **Full-suite gate 1.** |
| 4 | Folder navigation, view modes, search (with the debounce), select-source binding | Contracts 4, 9, 11. |
| 5 | Play (three sites), downloads (two sites), playlist add, add link and auto-paste, `_formatUnixDate` | Contracts 5–7, 10. |
| 6 | `build` forwarder and every builder (strict Linux goldens from here) | Contracts 11, 12. |
| 7 | Final State, guards, CI. **Full-suite gate 2.** | |

### Step 0

1. **Baseline:** `suite_evidence.py run premiumize/base` and the whole-repo
   analyzer, with tree provenance. Flutter must be 3.44.8.
2. **Dependency report** (`docs/refactoring/premiumize-files-deps.md`), with
   the per-entry wiring checklist (as PikPak).
3. **Checker:** `dev/tool/premiumize_manifest.tsv`,
   `premiumize_checker_config.json` (+ scaffolding/accessor/context-exception
   files as PikPak needed them), real-config fixtures, the callback-identity
   negatives, and a `premiumize_checker_test.py` self-test. Reuse existing
   opt-in checker keys; any new key must be opt-in and leave every existing
   feature's checks byte-identical.
4. **Harness:** `SharedPreferences.setMockInitialValues` seeding
   `premiumize_api_key` and `premiumize_integration_enabled` (the flag
   defaults to `true`, `premiumize_storage.dart:54`), then the legacy
   `ProfileRuntime` initialization/reset and the `SecretVault` device-identity
   override (`secret_vault.dart:410`; it does not seed values). For
   committed-profile tests, seed a bound `provider.premiumize` resource:
   committed credential reads do not fall back to the scalar key
   (`profile_credential_facade.dart:216`). Then
   `http.runWithClient` with a `MockClient` for `www.premiumize.me/api`
   (folder/list, folder/search, item/details, item/delete, folder/delete,
   transfer/list, transfer/delete, transfer/clearfinished, transfer/create).
   Prove one passing HTTP fixture against the ORIGINAL first. A held-response
   helper for in-flight cases. Responses are decoded by `decodeJsonAsync`
   (`lib/utils/json_isolate.dart`); bodies under 32 KiB decode inline, so
   fixtures stay below that. **Timing:** do not inherit PikPak's
   unconditional 600 ms mount pump (`pikpak_files_fixture.dart:179`); the
   debounce timer must be created and advanced in fake time, and any real
   async waits are isolated from timer assertions.
5. **Characterization tests,** recorded against the ORIGINAL. Apply the
   TorBox/Real-Debrid/PikPak lessons up front: drive actions through real
   entry points; re-read state after acting; non-monotonic ids where order
   matters; assert values, not names; exact request lists (method, path,
   query/body); sentinel handlers for route versus tab registration.

   | Contract | Coverage |
   | --- | --- |
   | 1 Navigation | Tab versus pushed route registration and removal on dispose (sentinel handlers, key-only tab unregister, TV closure by identity); each back level including `returnToTorrentSearchOnBack`; the Opening-folder scaffold and its back; browse-push back (`maybePop`). **Scroll reset ordering:** a genuinely scrolled outgoing list (offset > 0, extent asserted) and a scroll-controller listener that records the offset change together with the navigation fields observed at that moment, proving `jumpTo(0)` runs before the navigation `setState` for `_switchView`, `_navigateIntoFolder` and `_navigateUp`. Startup order (source guard). |
   | 2 Settings | Disabled flag; missing/empty key; enabled; initial folder needs both id and name; `initialSearchQuery` (trimmed, field text, search active, root cloud search request fired after the debounce, folder listing also requested). **Initial folder + initial query:** listing held, query matches files in the listing; after it completes the search results are still empty (filter ran against the empty list). |
   | 3 Loading | First load and in-place `_items` identity; loading guard (second load while held makes no request); error state with message and Retry; transfers load, guard, empty and error; refresh reloads only the active view and exits selection; `_switchView` same-view no-op. |
   | 4 Select-source | On a pushed route: folder binding (recursive listing, first-video readiness by `playableUrl` and by `resolveItemById`; **an unready first video followed by a ready second video is rejected, with exactly one `item/details` request for the first**), file binding; held-request unmount on both paths (folder: no callback; file: callback still invoked, no pop); the widget callback replaced while a request is held (the new callback is the one called); the catch through a throwing `folder/list`; callback awaited before the pop; `SeriesSource` fields; the checking dialog closed exactly once (root navigator) and distinguished from the screen pop; each rejection (no videos, first not ready, not a video, not ready to stream, thrown error); disabled non-video file rows; "Browse folder"; binding from search results; hidden toggle/Add Link/selector; title. **Back hazard:** with the request held, system Back pops the checking dialog while `checkingDialogOpen` stays true, so the later `_dismissDialog` root pop can pop the screen: characterize and keep. |
   | 5 Playback | Source guards on all three launcher sites and their arguments (and `notifyPlayerLaunching` order), plus pending device verification. **Notification-count coverage only:** `MainPageBridge.addPlayerLaunchListener` observes `notifyPlayerLaunching()` (it runs inside the notification, before and separate from the launcher call, `main_page_bridge.dart:472`); the probe must never throw. Actual launcher counts and arguments stay source-guard-only unless an ORIGINAL-proven observer exists. `_playFile` resolve-by-id request when the URL is missing; "No playable URL" paths (no launch). **Collection arguments** (entry order, titles, start index for a series folder with episode order ≠ name order and cross-season, and a non-series folder): only if an observer of the pushed arguments is first proven against the ORIGINAL without any production change; PikPak's failing-resolution trick does not apply (the collection launches even with an empty start URL). Otherwise they are **source-guard-only and pending**. No copied preparation helper, no early return. |
   | 6 Downloads | Source guards on both enqueue sites. Folder dialog rows (exact maps) and the sequential loop's index/URL failure counting through the accessor. Enqueue success/mixed messages only if an isolated enqueue fixture is first proven against the ORIGINAL; otherwise **pending**, with the source guards kept. |
   | 7 Playlists | Source guards on the three maps; accessor tests on persisted entries: single file (non-video rejected), folder with one video (single), folder with several (collection, recursive order), "Already in playlist". |
   | 8 Destructive | Single delete Cancel (no request) and Delete (snackbar before the request; `item/delete` vs `folder/delete`; selection mode exited); delete selected Cancel, confirm with non-monotonic ids (snapshot in `_items` order, sequential requests in that order), partial failure (rows kept for failures, message), removal from search results; transfer delete Cancel/confirm/failure; clear finished then reload. |
   | 9 Search | Toggle on/off (focus request, selection cleared, debounce cancelled); root: debounce at 349 ms vs 350 ms (fake time), one request per settled query, stale success dropped when the text changed, error message; folder: synchronous local filter (files only); empty query. **Quirks (held responses + fake time):** clear button (tap and activate key) leaves the timer armed and `_isSearching` set (the request still fires); entering a folder leaves the root debounce armed; a stale failure clears a newer search's in-flight flag and shows its message; A→B→A accepts the first A response. Arrow-left on the clear button. |
   | 10 Add link | **Nested navigators** (the screen inside a nested Navigator) distinguish the State-context pop in `_addLink`, the dialog's lexical Cancel pop and the root `_dismissDialog`. Clipboard auto-paste (platform-channel mock: accepted and ignored prefixes); validation messages; exact `transfer/create` POST (query `apikey`; form body `src`, plus `folder_id` only inside a folder); success (dialog pops via State navigator, loading dialog dismissed, message, refresh request) and failure; Cancel clears. |
   | 11 Lists | Files/Transfers selector visibility; dropdown visibility; Raw copy vs Sort order (folders season-aware first, files by leading number, name fallback) and per-folder memory; root ignores `_setViewMode`; skeleton, empty (root vs folder), not-configured, error, transfers-empty; Clear-finished visibility; transfer card status variants; `_formatUnixDate` with fixed old dates (> 7 days, so output is date-only and clock-independent). Pixel goldens of the reachable views (root files with selector, folder with dropdown, selection mode, transfers with all three statuses, select-source, search results, not-configured) on macOS and Linux, Linux from the ORIGINAL (capture script, run by Claude). |
   | 12 D-pad | Back button arrow-left (sidebar sentinel); dropdown arrow-up to back; search field arrows and clear-button keys; first-item focus after a navigation load and the Add Link fallback on an empty folder; TV closure path; autofocused Retry / Go to Settings. |
   | 13 Lifecycle | Source guards on the verbatim lifecycle and the full dispose sequence; unmount with a pending load and with a pending debounce timer: no throw and no request after dispose. |
   | 14 Profile | A profile-gate remount gives a fresh State with new owners; two independent routes don't share owners; requests made before/after a profile switch carry the A/B keys actually read at each mount; a playlist add under a **stable** profile persists to that profile. Any switch-during-write timing is characterized against the ORIGINAL first and asserted only as observed (or left pending). |

   - Record `premiumize/base2` after any seam, then `premiumize/base3` after
     the tests; compare each with the previous one (`PASS`, only added
     identities, all passing).
   - **Mutation proofs:** a test-to-contract mapping file in evidence
     (`premiumize/mutation-map.json`) records, per behavioural test identity:
     the contract, the precise mutation applied to the ORIGINAL, the assertion
     expected to fail, original/mutated/restored source hashes, the failing
     run's JSON/env, and a passing control replay after restoring. Required
     targeted mutations include timing (debounce 350 → 349/351, removed
     cancel), callback waiting (unawaited `onSourceSelected`), ownership
     (collection identity: copy instead of in-place), request ordering
     (reversed delete loop), and context binding (State vs lexical navigator
     in add link/delete dialogs). Compilation errors or harness/infrastructure
     failures never count. Mutations are restored and never committed.
     Source-guard-only coverage is labelled as such. Callback-identity
     negatives (wrapper closure, same-class receiver swap, and a different
     search-owner instance for the `Timer` closure via the existing opt-in
     closure binding in `torbox_callback_identity.py`) run through the
     identity checker directly in the self-test, as PikPak's self-test does.
6. **CI list:** add every new test as a concrete path in
   `dev/tool/ci_behavior_tests.txt`.
7. **Source-text inventory:** the `cloud` glob in
   `theme_surface_manifest.txt:5` (add the new feature directories; the
   AllDebrid fork edits the same line — keep the edit minimal and keyed to
   `premiumize_files`); the shape manifest (the facade has **six bare radii
   and six shape-token calls** today, residue 6; every destination
   registered, token-bearing files in `kShapeResidue`, the others in
   `kExtractedShapeResidue`, and the final zero-token facade moves to
   `kExtractedShapeResidue`);
   `file_size_baseline.txt:29`; `check_search_architecture.py` (new
   Premiumize constants and rules; architecture scanning covers registered
   features only (`check_search_architecture.py:1030`), so an unregistered
   `lib/features/alldebrid_files/` is never scanned. Add a Premiumize-keyed
   scan of `lib/features/alldebrid_files/**` import directives, restricted to
   the cross-import prohibition with `premiumize_files`, and prove both
   directions through the real `main()` with negative probes while AllDebrid
   is absent from `FEATURES` (and still correct once it registers); `checks.yml` (format and analyze the
   facade and the new `test/support/premiumize_*` helpers, paths inside the
   command, never after `| tee`); `analyzer_allowlist.txt` (only relocated
   original **warnings**; the original's single diagnostic is an info
   (`deprecated_member_use`) and stays out of the allowlist, which ignores
   infos, `check_analyzer_allowlist.py:48`); the generic profile, theme and storage
   readers (verify). Update `dev/design/ADDING_A_PROVIDER.md` only if it
   names a moved private member.
8. **Linux capture script** (`dev/tool/capture_premiumize_linux_goldens.sh`),
   resolving the step-0 checkpoint by exact subject; Claude runs it in the
   local `debrify-flutter:3.44.8` Docker image. The Linux golden test becomes
   strict at step 6.
9. **Fresh-clone proof:** every new self-test/checker passes from a fresh
   normal `git clone` (where `.git` is a directory) after `flutter pub get`.
   Never copy `.git` as a file.

### Checker activation and intermediate wiring

- At step 0 the config has **empty** production scaffolds, plain sections and
  root/forwarder rules (copying PikPak's final config would fail the
  immediate plain-section and scaffold-fingerprint checks). Each step adds
  its scaffolds only after Claude/Codex review the wiring against the
  dependency checklist, then pins them.
- Step 3 code calls step-4 members (settings → `_performSearch`, loading →
  `_getCurrentViewMode`/`_applyViewMode`, back → `_toggleSearch` and
  `_navigateUp`). Step 3 wires these through **temporary callbacks to the
  retained facade methods**, recorded as deferred scaffolds; step 4 replaces
  them with the real section owners and deletes the deferred record. No
  `late` field; no work starts during composition.
- Live widget getters: `isPushedRoute`, `initialFolderId`,
  `initialFolderName`, `initialSearchQuery`, `selectSourceMode`,
  `onSourceSelected`.
- Root/forwarder rules activate at step 6 (the build forwarder), the facade
  cap and `TEMP(premiumize)` rejection at step 7.

### Per step and gates

As in PikPak: after each step, all manifest runs (every
`dev/tool/*_manifest.tsv`) with self-tests on isolated `--parser-package`
copies, architecture, sizes, storage references/keys, exact CI format and
analyze-plus-allowlist, staged diff checks, and the focused Premiumize
characterization run compared with the latest base. Gate 1 (after step 3) and
gate 2 (after step 7) are full-suite runs from committed source, compared by
identity with the latest Premiumize base (and gate 2 with gate 1).

## Decisions taken before design review

1. **Separate feature, no sharing** with the other cloud screens (above).
2. **No destination size exceptions;** the bounded step-0 facade exception
   ends at step 7. The 147-line `build` and every builder fit 500-line files.
3. **No format commit of the original:** the file is already `dart format`
   clean (verify in step 0; if not, a format-only commit before step 0 with
   its own full-suite identity check).
4. **`_tabIndex` stays in the State** (lifecycle-only).
5. **Goldens are needed** (the screen has no existing tests; layout and
   transfer-card paint are otherwise unpinned), macOS and Linux.
6. **Dead or odd code moves verbatim:** `_isAddingLink`'s build-time-only
   effect, the "Go to Settings" snackbar, and the `_runCloudSearch` early
   return that leaves `_isSearching` set.
7. **Device-only items go to the end-of-series checklist**, never a merge gate.

## Definition of done

1. **The facade** is at most its measured cap (≤ 400) and formatted, holding
   `PremiumizeFilesScreen` and the State with its verbatim lifecycle,
   forwarders and wiring. Every caller compiles unchanged.
2. **The guard** registers the feature, the exact bridge path, the facade as a
   composition root with its cap and `TEMP(premiumize)` rejection, no import
   of the facade from the feature, and no imports between `premiumize_files`
   and the other cloud features.
3. **Checks:** all manifest runs pass with self-tests (including from a fresh
   clone), and every characterization test passes unchanged.
4. **Analyzer and tests:** no new diagnostics and no suppressions; the CI
   analyzer allowlist check passes; gate 2 passes against the latest
   Premiumize base and gate 1.
5. **CI:** local CI-equivalent checks pass; remote CI is pending (Actions
   billing). The test list holds the new tests; no failure allowlist grows.
6. **Progress records:** commits, ownership, seams, evidence paths, and the
   end-of-series device checklist.
7. Stop after gate 2 and report.

## End-of-series device checklist

- Android TV D-pad: back arrow-left to the sidebar, dropdown arrow-up, search
  field arrows and clear button, first-row focus after folder navigation and
  after the TV content-focus request (tab 11), Files/Transfers selector.
- All three native/Flutter playback handoffs (file, single-video folder,
  collection) with a real Premiumize account.
- Real account flows: cloud search, add magnet/link (fair-use points), delete
  file/folder, transfers delete and clear finished, folder download through
  the file-selection dialog (native enqueue success/mixed messages).
- Select-source binding from the Home source editor, including system Back
  during "Checking…".

## Explicitly not in scope

- Merging or sharing anything with the other cloud screens.
- `PremiumizeService`, `PremiumizeStorage`, `DownloadService`, the player and
  launcher, `CloudFileRow` and other cloud widgets, the Premiumize settings
  page.
- Bug fixes and behaviour changes, including everything below.

## Found, not fixed

All pre-existing; the extraction keeps each exactly.
- **Stale or lost folder loads.** `_loadFolder` returns early while loading,
  so navigating during a load never fetches the new folder, and the old
  listing is written into the new folder's view.
- **`_dismissDialog` pops whatever is on top of the root navigator** when it
  can pop. If system Back already closed a loading dialog (select-source
  "Checking…", folder scans, add link), the later pop can close the screen or
  another route. The catch blocks of `_playFolder`, `_downloadFolder` and
  `_addFolderToPlaylist` dismiss again after an earlier dismiss when the
  error is thrown later (double pop).
- **`_addLink` closes the dialog with the State's `Navigator.of(context)`**,
  which can differ from the dialog's (root) navigator inside a tab.
- **`_isAddingLink`** only affects the Add button when the dialog is built.
- **A single delete exits selection mode** and clears any selection.
- **Delete selected** snapshots items before the confirmation; a reload
  during the dialog can delete rows no longer shown.
- **In-folder search** filters the items loaded when typing; it is not
  re-run after a reload.
- **`_runCloudSearch` with no key** returns leaving `_isSearching` true.
- **Key-only tab unregistration** (`'premiumize'`), as in the other cloud
  screens.
- **The not-configured "Go to Settings" button** only shows a snackbar.
- **The shared `_errorMessage`**: when **both** `_items` and `_transfers`
  are empty, an error from either view shows the full-screen error page.
- **Pending searches are not owned:** the clear button leaves the debounce
  armed and `_isSearching` set; entering a folder leaves the root debounce
  armed; a stale failure clears a newer search's loading flag and shows its
  error; A→B→A accepts the first A response.
- **Initial folder + initial query** yields empty results (filter runs before
  the listing).
- **File binding after disposal:** the file path can call
  `onSourceSelected` after the screen is disposed.

## Round 1 review resolution

All eleven findings are addressed above: (1) bounded step-0 facade growth with
a measured manual baseline raise and step-7 exit, and the testing accessor
named as a public testing symbol; (2) pending-search quirks in contract 9, the
matrix and Found-not-fixed, distinguishing `_performSearch('')` from the clear
button; (3) the real seeding mechanism; (4) checker activation, deferred
step-3 callbacks and live getters including `initialSearchQuery`; (5) the
mutation map with targeted mutation classes and direct identity-checker
negatives including the `Timer` closure; (6) the three named boundary
fixtures; (7) asymmetric binding liveness, live callback replacement, nested
navigators and the `folder/list` catch path; (8) collection launch arguments
source-guard-only unless an ORIGINAL-proven observer exists; (9) the narrowed
profile claim and A/B assertions; (10) reverse AllDebrid probes, six radii/six
token calls, the info kept out of the allowlist, and fake-time timing rules;
(11) the two wording fixes.

## Round 2–3 review resolution

Round 2 (three P2s, two P3s) and round 3 (two P3 wording fixes) are folded
into the sections above; round 3 ended "No P1s — executable" with no P2s.

## Progress

### Step 0 — original-code characterization checkpoint

No extraction has begun. The first 2,276 source lines remain byte-identical to
`49c53e2e`; the only production addition is the frozen testing accessor. Its
100 formatted lines make the temporary facade 2,376 lines. The exact manual
size-baseline raise has the step-7 exit; it is lowering-only from step 1.
Services, storage, player/launcher, MainPageBridge, cloud widgets, models,
AllDebrid and other worktrees are unchanged. No branch switch or push occurred.

The 113-leaf manifest and dependency report assign every original declaration
and include per-entry reads/writes/calls and wiring checks. Step-0 production
scaffolds/plain sections/root rules remain empty. The accessor is a fresh map
of live members and original tear-offs; it adds no setters or service seam.
The existing opt-in `callback_closure_binding` key pins the Timer's closure,
including its receiver. Direct identity negatives cover wrappers and a second
instance of the same class. No shared checker/adapter implementation changed.
The original facade remains registered for its six shape-token calls and six
bare radii; destination registration and architecture activation occur with
the first production destination in step 1 (no nonexistent shape entries).
The floor remains 488 with zero slack.

All evidence is confined to `<git-common-dir>/refactor-evidence/premiumize/`.
SDK: Flutter 3.44.8 (`058e0af2c2`), Dart 3.12.2. `flutter pub get` was the first
command. `base` is the observed original whole-suite baseline; `base2` records
the accessor; `base3` records the completed characterization tests. Full-suite
paths are empty, runner flags recorded separately, and full runs serialized.
No failure allowlist, assertion, or baseline recorder was weakened.

Checks and original-code proof:

- `original-final-frozen-control`: **139 passing identities** (94 behaviour,
  seven pixel comparisons, 38 frozen source guards). The first HTTP fixture
  passed before the rest of the harness was built. Draft failures/probes are
  retained as development evidence and do not count as characterization proof.
- `mutation-map.json`: **101/101 behaviour/pixel identities**, **45 accepted
  named-assertion mutations**, each with original/mutated/restored source hashes
  and a passing replay after restoration. One first-guard-only attempt did not
  fail and is explicitly excluded. An additional original test proves that
  unmounting before first-video readiness prevents an `item/details` request;
  its first-guard mutation fails that exact request assertion. Required 349/351,
  cancellation, callback waiting, collection-copy ownership, delete ordering,
  and lexical/State navigator mutations all fail named assertions, not compile
  or infrastructure failures. Expected golden-negative PNG outputs are archived
  in evidence; their tree-change note is separate from source-input integrity.
- Full suites: `base` 12,032 success / 13 failure / 28 error / 20 skipped;
  `base2` 12,030 / 13 / 30 / 20; `base3` 12,170 / 13 / 29 / 20.
  Raw comparators report **FAIL** only for contention flakes: `base2` keyword
  focus/MDB snackbar (both isolated retries pass), and `base3` Xtream50k
  responsiveness (isolated retry passes on the identical tested tree).
  No raw outcome is overwritten or allowlisted. Reconciled identity audits are
  **PASS**: no unexplained failures, missing/newly skipped identities; all 139
  additions pass. `base3` also restores the two transient `base2` failures.
  The observed original passing identities remain authoritative; neither old allowlists nor `base2` failures conceal a later failure.
- Whole analyzer comparison: **PASS, zero added diagnostics**. Exact CI format,
  scoped analyzer and existing analyzer-allowlist commands: **PASS**. Size,
  architecture, storage-key and storage-reference checks: **PASS**. The original
  source's dropdown deprecation stays an info, outside the allowlist.
- Premiumize's 113-leaf real-config manifest/self-test: **PASS**. All **20 other
  manifests** and their self-tests: **PASS**, each on its own explicit local
  parser package. Their source inputs and all six shared checker/adapter
  implementations are byte-identical to `49c53e2e`; twice-parsed adapter output
  bytes match for every manifest (`existing-manifest-proof.json`). No shared
  implementation or new parallel checker mechanism was introduced. All 293
  pre-existing tooling/configuration/fixture files (except the three approved
  shared inventory edits) are byte-identical (`shared-configuration-proof.json`).
- Fresh normal-clone proof: **PASS** (`fresh-clone-proof.json`), with `.git`
  verified as a directory, `flutter pub get`, standalone Premiumize self-test,
  generic manifest/self-tests, capture-script syntax and all 38 source-reader
  contracts. The generic checker requires its explicit parser package to be
  bootstrapped first. The external clone harness initially omitted that setup;
  its infrastructure failure is retained separately, then the correct setup
  and replay pass without shared-tool or application edits. The checkpoint's
  final documentation-only amendment preserves every checked code/data byte
  (`checkpoint.json`); no application recheck is invalidated.

Seven macOS PNGs were initially captured against this unchanged original with
`PREMIUMIZE_CAPTURE_ORIGINAL_MACOS=true`; their hashes are frozen in evidence.
The committed Linux script resolves the checkpoint's exact subject, verifies
the original prefix and absent production feature, records revision/SDK/input
and PNG hashes, captures seven original Linux PNGs and runs a strict replay.
Claude captures/reviews these in Docker at stop point 1; Linux originals are
pending and strict Linux mode still activates only at step 6.

Conservative decisions / material limitations:

- Tests advance the 350 ms debounce in fake time; mount has no unconditional
  delay. Real waits are isolated from timer assertions. Both 349/351 mutations
  target explicit request-boundary assertions.
- Collection identity is tested across reload, deletion, independent routes
  and real profile-gate remounts. A/B HTTP keys come from committed bound
  `provider.premiumize` resources; playlist writes are verified under a stable
  profile. Switch-during-write timing remains pending (storage guards unchanged).
- Native player observation attempts fail because `Mpv.framework` is absent.
  No throwing notification probe or copied preparation helper was adopted.
  All three launcher sites/arguments/order remain frozen source-guard-only;
  no-URL rejection tests assert zero notifications. Positive launcher payloads
  and native notification counts remain device-only pending.
- Both download enqueue sites remain frozen source guards. Original dialog
  row maps and invalid-index/missing-URL failure counting are exercised;
  native successful/mixed enqueue and its messages remain pending.
- D-pad tests cover reachable key/focus paths; a one-result search's Down key
  retains the search field under the original geometric traversal policy.
  Physical TV repeat/hold and player-return focus remain pending.
- The original analyzer has the dropdown `value` deprecation info. An unchanged
  copy under destination lint rules adds five import-order infos. No suppression
  or allowlist entry was introduced.

Found-not-fixed remains unchanged: clear-button pending timer/flag; folder-entry
pending root timer; stale failure clearing a newer loading flag; A→B→A accepting
the first A; initial folder+query filtering the still-empty list; stale folder
listing winning a newer guarded navigation; binding file/folder disposal
asymmetry; the checking-dialog Back hazard; root Raw ignoring view-mode writes
and Raw copying the current sort instead of restoring server order; nested Add
State pop versus root loading dismissal. Device/platform work is pending; no
behaviour repair is bundled.

Shared edits to union at integration: Premiumize-only globs on the `cloud` line,
format/analyzer paths inside both CI commands, nine concrete CI behaviour-test
paths, and the exact temporary Premiumize facade size-baseline value. Other
manifest/config/fixture/source bytes and adapter outputs remain unchanged.

Step 0 stopped at checkpoint `f1cfa6f2` for Claude's independent review.
The resumed step 0b is recorded below; no extraction has begun.


### Step 0b — independent review closure on ORIGINAL

Checkpoint: `2cf7b76ca267f95cabe55f7fceb9a40181373f86`.

The production screen and all existing characterization assertions remain
unchanged at `f1cfa6f2`. Three new test files add 19 behavioural identities,
registered as concrete CI paths. Conservative decisions preserve the observed
clear-key prompt, root server order, empty navigation-stack dropdown rule,
focus while loading, and null destructive-dialog results.

Ten review survivors now have named-assertion mutation proofs on the ORIGINAL:
root view mode and root reentry; deep-link versus navigated dropdown visibility;
parent-row focus after navigating up; no Add Link focus during an empty held
load, then fallback after completion; Enter activation clearing populated
search results and returning field focus; selected/transfer delete dismissed
by Back and barrier; chapter sorting; the seven-day relative-date threshold;
and reachable zero-item selection showing Select All. Every mutation has an
original pass, source hashes, named failure and a restored passing control in
`step0b/targeted-proofs.json` and `mutation-map.json`. Two extra mutations prove
all seven numeric folder patterns and search-hidden selection visibility.

Bare `Chapter 10` also matches the final letters-plus-number fallback. The
additional `Story Chapter 10`/`Story Chapter 2` pair isolates the dedicated
unanchored chapter pattern. Relative-date tests use the existing clock with
30-second, 30-minute and 12-hour margins, observed synchronously; repeated
original controls pass. No production clock seam was added. The small wall
clock risk allowed by the review is retained explicitly.

Replaying the 28 mutations killed in Claude's original audit found **none
killed only by pixel goldens** (`step0b/audit28-pixel-review.json`). All have
non-pixel expectations; missing transfer reload and incomplete initial-folder
settings fail existing completion-predicate assertions, recorded distinctly
from request/value expectations. The original control passes. Its first
metadata attempt failed before running tests because `git stash create`
transiently returned exit 1; that infrastructure attempt is preserved, excluded
from test verdicts, and retried successfully on the same source.

Collection playback arguments (`play-sort-season`, contract 5) and native
successful/mixed download messages (`dl-mixed-msg`, contract 6) remain pending
and source-guard-only. Their frozen full-body guards remain unchanged. All
12 survivor mutations and these two explicit guards will be replayed after
the checkpoint, without counting source guards as behavioural coverage.

Integrator decision: Premiumize does not opt into `occurrence_field_bindings`.
If later wiring needs that existing opt-in, set `mandatory_qualification`
explicitly to true and justify it here; the future unconditional default from
edit_profile must not affect this branch's assumptions. Do not rebase.

`original-final-control` passes **158 identities**: 113 behaviour, seven pixel
comparisons and 38 unchanged frozen source guards. The comparison preserves
all 139 old identities and adds exactly 19 passing identities. The mutation
map covers **120/120 behaviour/pixel identities** with **57 accepted unique
named-assertion mutations** (45 original plus 12 review proofs).

Original full-suite `premiumize/base4` records 12,189 successes / 13 failures /
29 errors / 20 skips, on stable tested tree
`b01d4d78cd04ced49a900f048c2b1d431a0fe331`. Paths are `[]`; flags are
`--no-pub --concurrency=2`. The raw comparison with `base3` is retained as
**FAIL** for one new MDB missing-snackbar assertion; base3's Xtream failure
recovers. The exact MDB test passes in isolation on the identical tested tree
and SDK (`step0b/base4-mdb-isolation`), with a NOTE in
`step0b/base4-retry-note.json`. The reconciled identity audit is **PASS**:
exactly 19 additions, all passing; no missing/newly skipped identities; every
original observed pass, including base3's isolated Xtream control, remains
passing. Reconciled counts are 12,190 / 13 / 28 / 20. Raw runs and comparators
are never rewritten, and no assertion or allowlist changes.

Whole analyzer comparison: **PASS, zero added diagnostics**. Premiumize's
113-leaf manifest and standalone self-test, exact CI format/scoped analyzer /
analyzer allowlist, new-test analyzer, architecture, sizes and both storage
checks: **PASS** (`step0b/checks.json`). All **293** pre-existing tool/config /
fixture blobs remain byte-identical to `49c53e2e`, excluding the approved
shared inventory edits (`step0b/shared-configuration-proof.json`). All **20 other manifests and their self-tests pass**, each on its own
explicit local parser package. Every self-test output and adapter fingerprint
is **byte-identical to step 0** (`step0b/existing-manifest-proof.json`). The normal-clone proof and all twelve survivor replays follow the
checkpoint commit.

The full suite and analyzer tested the frozen code/test/config inputs before
this documentation-only result update. The unchanged production source remains
SHA-256 `93be5f5e4bfe1b5c9dd411adcad616e030b9fe4e478c484ffd2e7b6e96a64476`.
Linux originals are reserved for the separate step-L provenance/PNG commit.
Steps L and 1–7 remain unstarted. Found-not-fixed and device-only items are
unchanged. The integration union adds these three CI behaviour-test paths to
the nine from step 0; no shared checker implementation edit is introduced.


Step-0b post-checkpoint audit: all twelve Claude survivor mutations replayed
against every Premiumize test except `premiumize_source_contract_test.dart`:
**ten named behavioural kills**, **two permitted native-pending survivors**,
and **120/120 restored control passes after every mutation**. Both pending
mutations then fail their named full-body source guards, with passing original
restored controls (`step0b/postcheckpoint-replay-audit.json`). The mutation map
labels these two explicitly SOURCE-GUARD-ONLY; native behaviour remains pending.
One control's first Git metadata attempt did not start tests; its valid mutation
output is preserved and the control replay passes. The ignored evidence parser
was corrected to read unit-test assertion text from `error` events as well as
widget-test `print` events; no shared implementation or assertion changed.

Fresh normal clone: **PASS** (`step0b/fresh-clone-proof.json`) at the exact
step-0b checkpoint, `.git` is a directory, `flutter pub get`, standalone and
generic manifest/self-tests on separate explicit parser packages, capture
script syntax, all 38 source guards and all 19 new review identities. Original
code/data remain byte-identical to the checkpoint and the base4 tested inputs;
only this result documentation is added afterward.

### Step L — original Linux golden artifacts

Seven Linux PNGs and their checked-in `provenance.json` are committed separately.
Claude captured the ORIGINAL checkpoint `f1cfa6f2` twice in local
`debrify-flutter:3.44.8`, linux/amd64, Flutter 3.44.8 / Dart 3.12.2. Both captures
and strict replays pass 7/7; every PNG hash matches between independent captures.
Every recorded source/test/harness input hash still matches this unchanged
original screen. Capture/strict logs and provenance remain under the Premiumize
evidence directory; no originals are regenerated or updated. The strict Linux
CI switch still activates at step 6. Remote CI is pending; this is local Docker
evidence. With the PNGs and passing `linux-original-strict.txt` verified, stop
point 2's prerequisite is satisfied and step 1 may proceed. No extraction has
begun in this artifact commit.


### Step 1 — enums, pure helpers and feature guards

The two enums and six pure methods now live in the four manifest-owned model
and application files. Their declarations, expressions and comments pass the
113-leaf verbatim checker; the accessor uses the six registered unbound
tear-offs. The public widget and lifecycle are unchanged. The facade shrinks
from 2,376 to 2,276 formatted lines; its size baseline only decreases.

Premiumize is registered from its first destination, with an unconditional
500-line feature cap, exact legacy bridge, facade composition root and
application restrictions. The facade cap remains staged for step 7. Real-main
negative probes reject the facade import, services/HTTP/BuildContext in
application, late fields, oversized destinations, and all four cloud peers in
both directions. AllDebrid's peer-only import scan works before registration
and after registration; an absent sibling's unrelated code is outside that
scan. The probes modify owned copies inside `.dart_tool`, never the real
AllDebrid screen or feature. CI invokes the new architecture self-test.

Evidence: `premiumize/step1/`. All 158 frozen Premiumize identities and three
shape checks pass; the changed source-reader resolver additionally passes all
38 body contracts. The shape manifest registers all four destinations and
retains the facade's six bare radii/six token calls, floor 488, zero slack.
Architecture/self-test, sizes, storage keys/references, exact CI format/scoped
analyzer/allowlist and whole-analyzer comparison pass, with zero added
diagnostics. Two source-reader string-style infos in a draft were corrected;
the draft logs remain evidence. Every other manifest/self-test passes: all 20
output hashes and adapter hashes match the original proof byte-for-byte, with
source inputs unchanged from `49c53e2e`. Every parser invocation uses an
explicit package inside this worktree's `.dart_tool`.

Conservative decisions: retain all original behavior and text; no service,
storage, model, cloud-widget, player/launcher or bridge implementation changes.
Premiumize does not opt into occurrence-field bindings and relies on no default
for mandatory qualification. A disposable normal clone under `.dart_tool`
validated the upcoming owner/section wiring with all 158 tests plus shape
checks. It identified only existing opt-in formatter accommodations for owner
qualification; production remains at step 1 until this checkpoint.


### Step 2 — route-owned state and resources

All 36 mapped fields now live on the seven route-owned state holders. Original
initializers, final collection identities and the lifecycle disposal order are
preserved. The State retains tab index 11 and seven final owner handles; its
facade decreases from 2,276 to 2,248 formatted lines. No work starts from an
owner constructor. Live reads and writes, including the frozen accessor, use
the registered receiver paths.

Evidence: `premiumize/step2/`. The 113-leaf manifest and feature self-tests,
architecture/self-test, sizes, storage keys/references, exact CI format/scoped
analyzer/allowlist and whole-analyzer comparison pass with zero added
diagnostics. All 158 original Premiumize identities plus three shape checks
pass. All seven new destinations are registered, with the facade's six bare
radii and six token calls retained, floor 488 and zero slack. Every other
manifest/self-test passes with output and adapter bytes identical to the
original proof (20 manifests; explicit isolated parser packages).

Conservative formatter decisions: reuse the existing opt-in navigation-record
trailing-comma rule, activated on the retained original method, and pin the
single formatter-required skeleton-return brace pair. These change no
expression, statement, comment or branch condition. The feature does not opt
into occurrence-field bindings; no qualification default is assumed. Resource
creation, timer cancellation, callback identity and borrowed implementations
remain exactly as characterized.


### Step 3 — catalog, selection, feedback and focus sections

Seven plain sections now own the step-3 methods. The five deferred callbacks (performSearch, getCurrentViewMode, applyViewMode, toggleSearch and navigateUp) are pinned in PremiumizeScope and the State composition getter, and recorded in step3/deferred-scaffolds.json with their step-4 exit. Composition only constructs sections; it starts no work. State lifecycle tear-offs and the stored TV closure retain their receiver identity. Context, mounted and all six widget inputs remain live callbacks/getters at the original use sites.

Evidence: `premiumize/step3/`. All 113 verbatim leaves and feature self-tests, architecture/self-test, sizes, storage keys/references, exact CI format/scoped analyzer/allowlist and whole-analyzer comparison pass with zero added diagnostics. All 158 frozen Premiumize identities and three shape checks pass. Every other manifest/self-test passes (20), with output and adapter bytes identical to the original proof and explicit isolated parser packages. The facade is 1917 formatted lines. Every destination and the facade are registered in the shape manifest (floor 488, zero slack).

Conservative decisions: typed narrow dependency records contain only the original field reads and calls; composition callbacks preserve parameter defaults. Only registered receiver/rename substitutions, live callbacks, imports and exactly pinned formatter brace pairs/trailing commas are admitted. Comments in moved leaves remain verbatim. No occurrence-field-binding opt-in or checker default is assumed. Found-not-fixed remains unchanged.


### Full-suite gate 1

Full-suite evidence `premiumize/gate1.jsonl` and `.env.json` records committed source `38d3e87bdfe65befdcb63732198bd84443e0025f`, tested tree `37e949cac4856d847ebf2bf95b071cbeb9429295`, paths `[]`, and runner flags separately. Same SDK as the latest original Premiumize base4. Identity comparison against base4 passes after documented same-tree isolated replays, if any. Raw counts: {'success': 12190, 'failure': 13, 'error': 28, 'skipped': 20}. Reconciled counts: {'success': 12190, 'failure': 13, 'error': 28, 'skipped': 20}. No missing identities, new failures, new skips or previously passing regressions. Original passing observations, including the isolated base3 Xtream and base4 MDB controls, remain mandatory.

Canonical `premiumize/gate1/identity-audit.json` retains both raw comparisons and any NOTE/replay records; raw logs, assertions and failure allowlists are unchanged. The gate commit changes only this Progress record. Device-only checks, remote CI and integration remain pending.


### Step 4 — navigation, search and source binding

The four real navigation/search/source-binding owners replace all five deferred callbacks. The temporary scope entries are removed, and data wiring now dispatches to the corresponding section owners. The 350 ms Timer closure, cancellation order, live onSourceSelected callback, disposal asymmetry, request ordering and all characterized stale-search behavior are preserved.

Evidence: `premiumize/step4/`. All 113 verbatim leaves and feature self-tests, architecture/self-test, sizes, storage keys/references, exact CI format/scoped analyzer/allowlist and whole-analyzer comparison pass with zero added diagnostics. All 158 frozen Premiumize identities and three shape checks pass. Every other manifest/self-test passes (20), with output and adapter bytes identical to the original proof and explicit isolated parser packages. The facade is 1684 formatted lines. Every destination and the facade are registered in the shape manifest (floor 488, zero slack).

Conservative decisions: typed narrow dependency records contain only the original field reads and calls; composition callbacks preserve parameter defaults. Only registered receiver/rename substitutions, live callbacks, imports and exactly pinned formatter brace pairs/trailing commas are admitted. Comments in moved leaves remain verbatim. No occurrence-field-binding opt-in or checker default is assumed. Found-not-fixed remains unchanged.


### Step 5 — playback, downloads, playlists, links and date formatting

The seven action/date owners preserve all three playback bodies, two download bodies, playlist persistence calls and link/clipboard dialogs. No player, launcher, downloader or storage implementation changes. Collection launch arguments and native enqueue success/mixed messages remain source-guard-only, with device checks pending. Date formatting uses its original DateTime.now call; no test clock seam is added. The source-reader now matches the checker-existing optional argument/parameter format commas and retains original matched statement text when removing pinned braces. Frozen source assertions and payload JSON remain byte-identical to 0b. Draft prefix/spacing failures and overlapping recorders are retained and excluded; the corrected full focused control runs serially and passes all 161 identities on a stable tree (source-reader-fix.json).

Evidence: `premiumize/step5/`. All 113 verbatim leaves and feature self-tests, architecture/self-test, sizes, storage keys/references, exact CI format/scoped analyzer/allowlist and whole-analyzer comparison pass with zero added diagnostics. All 158 frozen Premiumize identities and three shape checks pass. Every other manifest/self-test passes (20), with output and adapter bytes identical to the original proof and explicit isolated parser packages. The facade is 1095 formatted lines. Every destination and the facade are registered in the shape manifest (floor 488, zero slack).

Conservative decisions: typed narrow dependency records contain only the original field reads and calls; composition callbacks preserve parameter defaults. Only registered receiver/rename substitutions, live callbacks, imports and exactly pinned formatter brace pairs/trailing commas are admitted. Comments in moved leaves remain verbatim. No occurrence-field-binding opt-in or checker default is assumed. Found-not-fixed remains unchanged.


### Step 6 — verbatim rendering and build forwarder

The six plain rendering sections contain every original builder. State.build is the exact registered forwarder; only the moved plain root loses its override annotation through the existing opt-in token rule. The six bare radii and six theme-token calls move with their builders. CI enables PREMIUMIZE_REQUIRE_ORIGINAL_LINUX from this step. Original Mac goldens remain unchanged; strict Linux evidence is recorded after committing this source, against the seven original PNGs, without regeneration.

Evidence: `premiumize/step6/`. All 113 verbatim leaves and feature self-tests, architecture/self-test, sizes, storage keys/references, exact CI format/scoped analyzer/allowlist and whole-analyzer comparison pass with zero added diagnostics. All 158 frozen Premiumize identities and three shape checks pass. Every other manifest/self-test passes (20), with output and adapter bytes identical to the original proof and explicit isolated parser packages. The facade is 251 formatted lines. Every destination and the facade are registered in the shape manifest (floor 488, zero slack).

Conservative decisions: typed narrow dependency records contain only the original field reads and calls; composition callbacks preserve parameter defaults. Only registered receiver/rename substitutions, live callbacks, imports and exactly pinned formatter brace pairs/trailing commas are admitted. Comments in moved leaves remain verbatim. No occurrence-field-binding opt-in or checker default is assumed. Found-not-fixed remains unchanged.
