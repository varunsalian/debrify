# AllDebrid files screen refactor — plan

Written 2026-10-06 on `refactor/alldebrid-files`, branched from
`refactor/codebase` at `49c53e2e`. Follow [AGENTS.md](../../AGENTS.md).
Read [pikpak-files-plan.md](pikpak-files-plan.md) first, including its
Progress section, and through it the Real-Debrid and TorBox plans. This plan
reuses their technique, checker (`check_verbatim_moves.py` with the
`sections` engine of `check_settings_moves.py`), callback-identity checks,
tree-recording evidence, real-config fixtures, original-code worktree proofs,
wiring checklist, Linux goldens captured from the original code, and
`analyzer_allowlist.txt`. It only states what differs.

Commit after every step. Never push. Gate commits must contain `gate`.
This is batch 3 of a parallel series; a sibling branch is refactoring
`premiumize_files_screen.dart` (feature `premiumize_files`) at the same time.

## Goal

`lib/screens/alldebrid/alldebrid_files_screen.dart` is 1,996 lines: the
AllDebrid cloud library. It holds:
- two root views behind segmented tabs: the magnet library ("Torrent
  Downloads") and the saved-links library ("Web Downloads"), the links
  loaded lazily on first switch;
- a two-level browser: magnet list, then the selected magnet's files;
- playback (one file, a whole magnet as a series-aware playlist, one saved
  link);
- downloads (one file, a magnet through the file-selection dialog, one link)
  and copy-link;
- add magnet, add link (clipboard auto-paste), add magnet to playlist;
- delete (one magnet, selected magnets, all magnets, one link, all links);
- root search and in-magnet file search;
- the select-source mode used by the Home source editor (magnet and
  web-download bindings);
- the "shared web link → open on Web Downloads" deep-link handler.

Split it into a new feature, `lib/features/alldebrid_files/`, **moving code
verbatim**.
- **Unchanged:** the widget tree, keys, focus nodes, build order and the
  State's lifecycle.
- **Stays in `alldebrid_files_screen.dart`:** the public
  `AllDebridFilesScreen` widget (same constructor, parameters, field order and
  doc comment) and its State with a verbatim `initState` and `dispose`
  (receiver-only qualification), a `build` forwarder and section wiring.
  There is no `didUpdateWidget`, and none is added.

**Nothing is shared with TorBox, Real-Debrid, PikPak or Premiumize.**
`_findFirstEpisodeIndex` and the search-bar helpers resemble theirs; they move
into this feature as copies. No file under `lib/features/alldebrid_files/`
may import `lib/features/{debrid_downloads,torbox_downloads,pikpak_files,premiumize_files}/`,
or the reverse.

**Architectural status:** a bounded legacy-extraction stage, with the same
temporary exceptions and exit milestones as PikPak:
- **State-driven sections instead of Riverpod.** Exit: AllDebrid library
  state in Riverpod notifiers in a later change.
- **A `legacy_alldebrid/` bridge folder that calls services directly**
  (`AllDebridService`, `AllDebridStorage`, `PlaylistStorage`,
  `DownloadService`, `VideoPlayerLauncher`, `MainPageBridge`, `Clipboard`).
  Exit: AllDebrid data contracts, then dissolve the bridge.
- **Unchanged legacy text.** Exit: the app-wide localization migration.
- **Helpers duplicated with other cloud screens.** Exit: the future shared
  cloud-library plan named in the PikPak plan.

## Public surface

```dart
class AllDebridFilesScreen extends StatefulWidget {
  final bool isPushedRoute;
  final String? initialSearchQuery;
  final bool selectSourceMode;
  final Future<void> Function(SeriesSource)? onSourceSelected;
  const AllDebridFilesScreen({super.key, this.isPushedRoute = false,
    this.initialSearchQuery, this.selectSourceMode = false,
    this.onSourceSelected});
}
```

Kept exactly, with its doc comment. It is the only public symbol. Callers:
`main.dart` (tab page 1552, deep link 1837, Cloud hub 3416),
`lib/features/home/presentation/home_source_editor.dart:392`,
`test/provider_source_picker_web_download_test.dart:75`, and
`test/features/home/presentation/home_source_editor_test.dart:196`. Both
tests are part of the affected verification at every step.

## What it contains (line numbers at `49c53e2e`; the step 0 manifest is authoritative)

| Lines | Area | Notes |
| --- | --- | --- |
| 1–32 | 27 imports, `enum _AdView` | No top-level functions. |
| 56–106, 1149 | All State fields, the `_isAtRoot` getter (79) | `_loadingDialogOpen` is declared mid-class at 1149. No `late` fields. One static const (`_tabIndex = 12`). |
| 108–193 | `initState`, `_focusWebDownloads` (151), `dispose` | **`initState` and `dispose` stay verbatim in the State.** |
| 195–363 | `_focusFirstItem`, `_load`, `_loadLinks`, `_refresh`, `_openMagnet`, `_navigateUp`, `_handleBackNavigation` | |
| 365–565 | Playback: `_looksLikeVideo`, `_unlockStart`, `_playFile`, `_playMagnet`, `_playVideos`, `_findFirstEpisodeIndex` | `_findFirstEpisodeIndex` is pure. |
| 567–675 | Downloads: `_downloadFile`, `_downloadMagnet`, `_downloadSelectedFiles` | |
| 677–731 | `_showAddMagnetDialog` | |
| 733–939 | Web downloads: `_playLink`, `_downloadLink`, `_copyLink`, `_showAddLinkDialog`, `_deleteLinks`, `_confirmDeleteAllLinks` | |
| 941–1052 | `_addMagnetToPlaylist`, `_deleteMagnets`, `_confirmDeleteAll` | |
| 1054–1145 | Selection (`_isAllSelected` getter 1081), `_toggleSearch`, the three `_visible*` getters | |
| 1147–1194 | `_loadingDialogOpen`, `_showLoading`, `_dismissLoading`, `_snack` | |
| 1196–1641 | `build` (47 lines), `_isBrowsePush` (1248), toolbar (162 lines), view selector, selection bar, search decoration, `_moveFocusTo`, both search bars | |
| 1643–1995 | Body, magnets view and card (with the magnet binding), links view and card (with the web binding), files view and card | |

No method is over 200 lines; no size exception is expected.

## Contracts that must not change

1. **Navigation and back handling.**
   - **Pushed route:** `pushRouteBackHandler(_handleBackNavigation)` and
     `popRouteBackHandler(_handleBackNavigation)`, matched by `==` (the same
     tear-off on the same stable owner).
   - **Tab:** `registerTabBackHandler('alldebrid', …)`, the **key-only**
     `unregisterTabBackHandler('alldebrid')`, and the stored TV content focus
     closure for tab **12**, unregistered by identity.
   - **Deep-link handler:** `MainPageBridge.focusAllDebridWebDownloads =
     _focusWebDownloads` in both modes, and `dispose` clears it **only if** it
     still `==` this State's tear-off. A second mounted screen keeps its own
     registration when the first one disposes, and the **last** screen's
     disposal clears its own registration, so a later notification sets the
     pending flag for the next mount. `getAndClearAllDebridFocusWebDownloads()`
     is consumed once in `initState`, before `_load()`.
   - **Startup order:** analytics, initial query (trimmed; initialization
     only — later widget updates don't re-apply it), back registration,
     deep-link handler, pending flag, then `_load()` **unawaited** (its first
     `setState` runs synchronously inside `initState`), then `_loadLinks()`
     unawaited only when the pending flag selected Web Downloads. The two
     loads are not serialized.
   - **Live deep-link notification** (`_focusWebDownloads`, 151): every call
     switches to Web Downloads, clears the open magnet, files, selection and
     root search, and **always** reloads links, even if already loaded. It
     makes **no explicit scroll-controller jump** and does not reset the file
     search. Because `_loadLinks` swaps the list for a skeleton while
     loading, the controller detaches and the reloaded list starts at offset
     0 (characterized with a held response).
   - **Back priority** in `_handleBackNavigation` (341–363): selection mode,
     file search, root search, open magnet, else `false`. Each level
     characterized.
   - `_navigateUp` sets `_shouldFocusOnLoad`, jumps the shared scroll
     controller to 0 when attached, resets the file view, then calls
     `_focusFirstItem`.
2. **Select-source mode.**
   - **Magnet binding** (1722–1741): an empty-hash rejection snack; otherwise
     `SeriesSource(torrentHash: m.hash, torrentName: m.name,
     debridService: 'alldebrid', debridTorrentId: m.id, boundAt)`, awaited,
     then `if (!mounted) return; Navigator.of(context).pop();`.
   - **Web binding** (1881–1896): video links only (non-video rows have no
     tap); `SeriesSource(torrentHash: '', torrentName: l.fileName,
     debridService: 'alldebrid', debridTorrentId:
     SeriesSource.opaqueCloudReference(l.link), cloudSourceKind:
     SeriesSource.cloudKindWebDownload, boundAt)`, awaited, then the same pop.
   - Hidden in select mode: the selection toggle, delete-all and add; the
     toolbar shows "Select AllDebrid Source" and the alternate search-button
     branch (1357–1378). The two search-button branches are mutually
     exclusive: exactly one is built, with `_toolbarSearchFocusNode`
     attached, when the active view's backing list (`_links` or `_magnets`)
     is non-empty, and none otherwise; a search filtering to zero matches
     keeps the button.
3. **Playback handoff.** All **three launcher sites** (390 file, 531 magnet,
   747 link), each preceded by `MainPageBridge.notifyPlayerLaunching()`, keep
   every `VideoPlayerLaunchArgs` and `PlaylistEntry` argument, in order:
   `videoUrl`, `title`, `subtitle` (size or the "N episodes/files • size"
   string), `playlist`, `startIndex`, `viewMode` (`sorted` or `series`);
   entries with `url` (start entry only for multi-file, `''` otherwise),
   `title`, `relativePath` (first path segment stripped for multi-file),
   `provider: 'alldebrid'`, `allDebridLink` (the locked link), `sizeBytes`
   (null when 0). Also unchanged: the series sort (season, episode,
   lower-cased name) versus name-only sort, `_findFirstEpisodeIndex`, the
   start-index clamp, the sequential fallback-unlock loop that moves the start
   index, the single-video shortcut to `_playFile`, and every `mounted` check
   and snack in between. A full argument ledger for the three sites is part
   of step 0 and is re-verified token-by-token at every step that moves them.
4. **Downloads and clipboard.** The **three enqueue sites** (581, 655, 781)
   keep `credentialKey: 'alldebrid_api_key'`, `url`, `fileName`,
   `torrentName` (655 only) and the inline `context: mounted ? context :
   null`. `_downloadMagnet` builds the dialog maps (`name`, `_fullPath`,
   `size` as a string, `_adIndex`) and passes `onDownload` as an unawaited
   closure; `_downloadSelectedFiles` stays sequential and awaited with its
   three result messages; a missing, negative or out-of-range `_adIndex`
   counts a failure **without** an unlock request. `_copyLink`'s `Clipboard.setData` and the add-link
   `Clipboard.getData` auto-paste (http/https prefix only) stay as they are.
5. **Destructive actions.**
   - **Magnets:** the confirmation dialog (title override, singular/plural
     texts, red Delete), then one `deleteMagnet` POST per magnet in order,
     awaited, no per-item catch in the screen (the service swallows errors),
     then `_dismissLoading`, `_exitSelectionMode`, an awaited `_load`, and the
     success snack. Delete-selected snapshots `_magnets` filtered by the
     selected ids in **list order**, not selection order. Delete-all passes
     `List.of(_magnets)` unawaited.
   - **Links:** the confirmation dialog, one `user/links/delete` POST per link
     in order with a per-link catch counting failures, `_dismissLoading`, an
     awaited `_loadLinks`, then the success or "Failed to delete N link(s)"
     snack. Delete-all links passes `List.of(_links)` unawaited.
6. **Lists and views.**
   - `_load` re-reads the API key from storage **on every call** and filters
     to `isReady` magnets, pruning stale selected ids;
     errors and the missing-key message keep their texts and the Retry button.
   - `_loadLinks` prefers the cached `_apiKey` (reading storage only when it
     is null) and sets `_linksLoadedOnce` on every outcome. Switching to Web Downloads loads only when never loaded;
     switching views exits selection, resets the shared scroll controller and
     clears the root search.
   - `_openMagnet` with `force` keeps the current files during refresh; the
     not-ready and failed snacks stay (unreachable from the list today, since
     `_load` keeps only ready magnets).
   - Search filters: magnets by name, links by file name or host, files by
     file name; all case-insensitive on the trimmed query.
   - Row keys: `ValueKey(magnet.id)`, `ValueKey(link.link)`,
     `ValueKey('${magnetId}:${path}:$index')`; the first row of each list gets
     `_firstItemFocusNode`.
   - The loading dialog is guarded by one shared `_loadingDialogOpen` flag
     (initializer `false`, declared at 1149): a second `_showLoading` while
     open is suppressed; `_dismissLoading` clears the flag **before** the
     mounted-guarded `rootNavigator: true` pop. `barrierDismissible: false`
     blocks only the barrier: system Back can pop the dialog while the flag
     stays true, so the later `_dismissLoading` pops the route underneath
     (a pushed screen). This hazard is kept and characterized.
   - Select All toggles only the **visible** (search-filtered) magnets;
     hidden selections are preserved, and `_isAllSelected` reads the visible
     set.
7. **D-pad and focus:** the 7 focus nodes (only `_firstItemFocusNode` has a debug label); the
   search field's up/down/right exits through `_moveFocusTo`; the clear
   button's activate and arrow-left handling; the file search's up/down
   exits; the add dialogs' arrow-down `nextFocus`; the post-frame focus
   requests in `_toggleSearch`, the AppBar file-search toggle and
   `_focusFirstItem`; and the shared `_toolbarSearchFocusNode` on whichever
   toolbar search button is built.
8. **Lifecycle:** `initState` and `dispose` stay verbatim with receiver-only
   qualification, including the **10 disposals** in order, then
   `super.dispose()`.
9. **Profile behaviour:** `_load` reads the active profile's API key on
   every call and caches it in `_apiKey`; `_loadLinks` and every action use
   the cached key. The screen relies on the profile gate remounting it. No
   scoping is added or removed. Tests assert the actual `Authorization:
   Bearer` header per request, after a credential change and after a
   remount.
10. **Playlists.** The two `addPlaylistItemRaw` maps (972 single with
    `allDebridLink` and `sizeBytes`; 981 collection with `count`), both
    `provider: 'alldebrid'`, `title: FileUtils.cleanPlaylistTitle(name)`,
    `torrent_hash`; the empty-hash rejection; the "Added to playlist" /
    "Already in playlist" snack.

11. **Add magnet and add link.**
    - **Add magnet:** Cancel or empty input does nothing; otherwise the
      loading dialog, one `magnet/upload` POST with `magnets[]` = the trimmed
      input, dismiss, "Magnet added", then an awaited `_load`; on failure,
      dismiss and "Failed to add magnet: …".
    - **Add link:** clipboard auto-paste (http/https only); Cancel or empty
      does nothing; a non-http(s) input shows the "Enter a valid URL…" snack
      with no request; otherwise `link/unlock` then `user/links/save` with the
      **original input link** (not the unlocked URL), dismiss, "Link added",
      then an awaited `_loadLinks`; an unlock or save failure dismisses and
      shows "Failed to add link: …" without the reload.

## Destination layout

`lib/features/alldebrid_files/`:
- **`models/`:** `_AdView`, made public under a manifest-registered name
  (values unchanged).
- **`application/`:** `_findFirstEpisodeIndex` as a pure function, if the
  dependency report confirms it reads no State. Nothing else is forced pure.
- **`presentation/legacy_alldebrid/`:** the bridge (exact path in the guard):
  state owners (library, navigation, search, selection, focus/resources,
  loading dialog), a deps record with live `context`/`mounted`/`setState`
  closures and live widget getters, and sections grouped by responsibility
  (library loading and navigation; playback; downloads and copy; add, delete
  and playlist actions; selection, search and feedback; root layout and
  toolbar; search bars; list views). The exact file split is fixed in the
  step 0 section map and frozen there.
- **The facade** (`lib/screens/alldebrid/alldebrid_files_screen.dart`) is an
  exact composition root. Its cap is measured at the final step (expected
  well under 300 lines) and its `TEMP(alldebrid)` rejection turns on then.
- **Guard rules,** added in step 1 to `check_search_architecture.py` as
  new feature-keyed rules (the existing PikPak rules do not cover all of
  them: they allow cross-feature `models/` imports, have no enqueue-placement
  check, and scan only registered features):
  - no back-imports of the facade from `lib/features/alldebrid_files/`;
  - **bidirectional** no-imports, **including `models/`**, between
    `alldebrid_files` and each of `debrid_downloads`, `torbox_downloads`,
    `pikpak_files` and `premiumize_files`; `premiumize_files` is scanned
    whenever its directory exists, even before (or without) its own
    registration, following the existing peer-scan pattern;
  - the exact bridge prefix; `lib/services/`, `package:flutter/services.dart`,
    `package:http` and launcher imports only inside the bridge; no service
    imports in `application/` or `models/`;
  - `VideoPlayerLauncher.push` / `VideoPlayerScreen(` and
    `DownloadService.instance.enqueueDownload` only in their registered
    section files (exact file sets in the config);
  - 500-line destination caps from step 1.
  Each rule ships with a real negative probe (a temporary file or edit in a
  scratch copy that the guard must reject).

Each destination file is at most **500 lines**.

## Technique

The same as the PikPak plan's Technique, with these points:
1. **No `didUpdateWidget`, no `late` fields, no timers or subscriptions.**
   Every field keeps its initializer at its declaration on its new owner.
2. **Callback identity** (receiver path plus member, with wrapping-closure and
   same-class receiver-swap negatives) for `_handleBackNavigation` (push and
   pop), `_focusWebDownloads` (the assignment in `initState` **and** the `==`
   comparison operand in `dispose`) and the tab-12 TV focus closure.
   `torbox_callback_identity.py` supports assignment sites but has no
   comparison-site selector, so step 0 adds an **opt-in**
   `comparison_property` site kind (the raw right-hand operand of
   `<property> ==`), keyed by this feature's config, with independent
   wrapper and receiver-swap negatives at the assignment and at the
   comparison, and a positive proving no scaffold error masks either rule.
   Every other feature's config behaves byte-identically.
3. **Owner construction** follows PikPak's compilable pattern
   (`pikpak_files_screen.dart:49`): plain `final` state-owner fields on the
   State (no constructor arguments), and one nullable section cache behind a
   getter (`_sectionCache ??= createAllDebridSections(deps, owners)`) that
   builds the whole graph at once, wires it completely before returning it,
   and whose constructors only retain their dependencies (no work, no
   listeners). The graph is created on first use and is then stable for the
   State's lifetime, so every tear-off (`_sections.<owner>.<member>`) is
   equal across `initState` and `dispose`. `_load()` stays an unawaited call
   in the same `initState` position. Each step's callback owner is recorded
   in the section map (the State until the step that moves the method, the
   section afterwards).
4. **Field bindings.** Fields that move to owners are checked with the
   occurrence binder (`occurrence_field_bindings.py`), reusing the existing
   opt-in keys (`record_owners`/`record_fields` or `record_paths`); no new
   binder mechanism. Shared-tool edits, if any, are opt-in keys keyed by this
   feature, and every other feature's config behaves byte-identically.
5. **Dormant branches** (the not-ready/failed magnet badges and snacks) move
   verbatim; nothing becomes reachable.
6. **Formatting.** The original file is already `dart format`-clean at the
   base; no format-only commit is needed (verify in step 0).

## Steps

| # | Work | Notes |
| --- | --- | --- |
| 0 | Baseline, dependency report (`docs/refactoring/alldebrid-files-deps.md`), section map, manifest and checker config, test accessor if needed, characterization tests and baselines, playback argument ledger, source-text inventory, CI test list, Linux capture script | Nothing moves. Stop for review. |
| L | Linux goldens captured by Claude from the step 0 checkpoint in the local Docker image; committed separately | Claude runs it. |
| 1 | Guard registration; enum and pure helper | |
| 2 | State and resource owners, deps record; lifecycle stays verbatim | |
| 3 | Library loading, navigation, back handling, refresh, search and selection state actions, loading dialog and snack | Contracts 1, 6, 7. **Full-suite gate 1.** |
| 4 | Playback, downloads, copy, add magnet/link, delete, playlist | Contracts 3, 4, 5, 10. |
| 5 | `build` forwarder and every builder, including both select-source bindings | Contracts 2, 7. |
| 6 | Final State, guards, CI, docs. **Full-suite gate 2.** | |

### Step 0

1. **Baseline:** `suite_evidence.py run alldebrid_files/base` and the
   whole-repo analyzer, with tree provenance. Flutter 3.44.8.
2. **Dependency report** with the per-entry wiring checklist and the frozen
   section map (every original declaration → destination file and owner).
3. **Checker:** `dev/tool/alldebrid_files_manifest.tsv` and
   `alldebrid_files_checker_config.json`, real-config fixtures, the
   callback-identity negatives (including the new opt-in comparison site:
   wrapper and receiver-swap negatives at the assignment and at the `==`
   operand, independently), and the field-binding negatives (a bare
   reference to a moved field, a receiver swap, a qualified field replacing a
   local). The config pins the binder's `receiver_members`, record paths (or
   `record_owners`/`record_fields`), mandatory qualification, the live
   `context`/`mounted`/`setState` callbacks and the live widget getters
   (`isPushedRoute`, `selectSourceMode`, `onSourceSelected`;
   `initialSearchQuery` is read only in `initState`).
4. **Harness:** the Real-Debrid pattern (`ProfileRuntime.initializeLegacy`,
   `SecretVault.debugReset`, the seeded `alldebrid_api_key`,
   `http.runWithClient` with a `MockClient` for `api.alldebrid.com`, a
   platform-channel mock for the clipboard). Successful responses use the
   `{"status":"success","data":{…}}` envelope. Prove one passing fixture first.
5. **Characterization tests,** recorded against the original code, driven
   through real entry points (taps, keys, `MainPageBridge` handlers), with
   exact request lists (method, URL, form body) and non-monotonic ids where
   order matters.

   | Contract | Coverage |
   | --- | --- |
   | 1 Navigation | Tab versus pushed route (registered and removed on dispose, with sentinel handlers); the TV focus closure focusing the first row; each back level; `_navigateUp` focus and scroll reset; the initial query trimmed and applied once (a same-key widget update with a new query does not re-apply it). Deep link: the handler set in both modes; a pending flag opening Web Downloads and loading links once; **own disposal clears** the handler; a second screen's registration **survives** the first one's disposal; after the last screen disposes, a notification sets the pending flag and the next mount consumes it; **repeated live notifications** each reload links and reset magnet, files, selection and root search, while the file-search state is preserved; with the links response held, a scrolled list shows the skeleton and the reloaded list starts at offset 0 (no explicit jump). |
   | 2 Select-source | Pushed picker: magnet binding (callback once, awaited before the pop, every `SeriesSource` field, `boundAt` in range) and its empty-hash rejection; web binding for a video link, a non-video link not tappable; hidden actions; the select-mode title and search button. |
   | 3 Playback | A fake launcher seam is not added; the three sites are covered by the argument ledger (source guard, token-exact) plus behavioural tests up to the handoff where reachable: unlock request order for a multi-file magnet (start entry first, fallback order on failure), the "No playable video files found." and unlock-failure snacks, and the single-video shortcut. Launch itself is **pending device verification**. |
   | 4 Downloads | Source guards on the three enqueue sites and the dialog-map construction; the dialog opened from the magnet action with its file list. The selected-files loop is driven through the **real `FileSelectionDialog.onDownload` callback** (found in the widget tree) with synthetic selected maps: missing, negative and out-of-range `_adIndex` count failures **without** unlock requests; empty unlocks count failures; unlock request order follows selection order. Success and mixed-result messages only if an isolated enqueue fixture is proven against the original; otherwise **pending**. Copy link writes the unlocked URL to the clipboard. |
   | 5 Destructive | Magnet delete Cancel (no request), single, selected (list order with non-monotonic selection order), all; link delete single, all, and a partial failure count; the follow-up reload and snacks. |
   | 6 Lists | Initial load (ready-only filter), missing key, load error and Retry, lazy links load once, view switch resets, refresh through the toolbar in the two reachable root contexts (torrents root reloads magnets; Web Downloads reloads links), open magnet; the **dormant** forced-files refresh branch (no toolbar or `RefreshIndicator` in the files view) through the frozen test accessor's retained `_refresh` tear-off, labelled dormant coverage (keeps the current files while loading, uses the cached key) — no UI control is added, the three searches, row keys, empty states. Pixel goldens (macOS and Linux) of: magnet root, Web Downloads, magnet files view, selection mode, select-source picker, error state. |
   | 7 D-pad | Search field up/down/right exits, the clear button's Enter and arrow-left, file-search up/down, the add dialogs' arrow-down, focus after load. |
   | 8 Lifecycle | Source guards on the verbatim lifecycle and the 10 disposals; unmount during a pending load: no throw. |
   | 9 Profile | The exact `Authorization: Bearer` header on every request; after a stored-credential change, a refresh at the torrents **root** uses the new key (since `_load` re-reads) while the links view, the dormant files refresh and every action keep the cached key until `_load` runs; a remount reads the key again; two routes don't share owners. A same-key widget update with a new `onSourceSelected` callback: the next binding calls the new callback (live widget getters). |
   | 10 Playlists | Single and collection maps persisted with exact fields; empty-hash rejection; the "Already in playlist" path. |
   | 11 Add | Add magnet: Cancel, empty, success (exact `magnet/upload` form body; the fixture returns a valid `data.magnets` entry), failure; snack before the reload; the reload request. Add link: auto-paste for http/https only (and none for other clipboard text), Cancel, empty, invalid URL (no request), success with an unlock response **different** from the input (proving `user/links/save` sends the original link), unlock failure and save failure (no reload); request order unlock → save → `user/links`. |
   | Loading dialog | Duplicate `_showLoading` suppressed; with an unlock held, **system Back** pops the dialog while the flag stays true; releasing the unlock makes `_dismissLoading` pop the route underneath (on a pushed route: the screen itself; distinguish the user's modal pop from the later root-navigator pop). Kept as found-not-fixed. |
   | Selection | Filtered Select All/Deselect All affect only visible magnets and keep hidden selections; `_isAllSelected` on the visible set; stale ids pruned after reload; delete-selected order is list order. |

   Every test is proven by an assertion-failing mutation of the original code
   (behavioural proxies separated from source-guard-only mutants). Record
   `alldebrid_files/base2` after any seam and `base3` after the tests.
6. **CI list:** every new test as a concrete path in
   `dev/tool/ci_behavior_tests.txt`.
7. **Source-text inventory:** `theme_surface_manifest.txt` (`cloud` line: add
   the new feature globs), the shape manifest (the measured one bare radius
   and five token calls are preserved across destinations; every destination
   registered — token-call files in `kShapeResidue`, the others in
   `kExtractedShapeResidue`; the final facade **leaves `kShapeResidue`** and
   enters `kExtractedShapeResidue` at 0, since a zero budget in
   `kShapeResidue` without a token call fails),
   `file_size_baseline.txt:38`, `check_search_architecture.py`,
   `checks.yml` (format/analyze the facade and new `test/support/alldebrid_files_*`
   helpers, paths inside the commands, never after `| tee`),
   `light_ink_inventory.py` (optional), and the generic profile, theme and
   storage readers (verify).
8. **Linux capture script** (`dev/tool/capture_alldebrid_files_linux_goldens.sh`),
   double capture in reversed order; Claude runs it. The Linux golden test
   becomes strict (missing PNGs fail) in the same commit that adds the
   verified originals at step L, before any code moves.

### Per step and gates

As in the PikPak plan: verbatim checker with an isolated `--parser-package`,
**all** manifest self-tests, the analyzer comparison with `--relocate
lib/screens/alldebrid/alldebrid_files_screen.dart=lib/features/alldebrid_files/`,
and gates against the latest AllDebrid base. Every new self-test and checker
must also pass from a fresh normal `git clone` (`.git` a directory) after
`flutter pub get`.

## Definition of done

1. The facade holds `AllDebridFilesScreen` and its State with the verbatim
   lifecycle, forwarders and wiring, under its measured cap; every caller
   compiles unchanged.
2. The guard registers the feature, the bridge, the facade as a composition
   root with its cap and `TEMP(alldebrid)` rejection, and the import rules
   above.
3. All manifest runs pass with self-tests; every characterization test passes
   unchanged.
4. No new diagnostics or suppressions; the analyzer allowlist check passes;
   gate 2 passes against the latest base and gate 1.
5. Local CI-equivalent checks pass; remote CI is recorded as pending.
6. Progress records: commits, ownership, exceptions, seams, Found-not-fixed,
   and the end-of-series device checklist.
7. Stop after gate 2 and the reviews; do not merge or push.

## Explicitly not in scope

- Sharing anything with other cloud screens.
- `AllDebridService`, `AllDebridStorage`, `DownloadService`, the player and
  launcher, `MainPageBridge`, the AllDebrid settings page, `main.dart`.
- Bug fixes and behaviour changes, including everything below.

## Found, not fixed (recorded; behaviour kept)

1. `_load` keeps only ready magnets, so the list's "Failed" and
   "Downloading N%" badges and `_openMagnet`'s not-ready snacks are
   unreachable.
2. `AllDebridService.deleteMagnet` swallows errors, so `_deleteMagnets`
   always reports success, even when every request failed.
3. The add-magnet and add-link dialogs never dispose their
   `TextEditingController`s.
4. `_confirmDeleteAll` and `_confirmDeleteAllLinks` start unawaited futures
   with no error handling.
5. `_loadLinks` reuses the cached `_apiKey`; a credential change while the
   screen stays mounted is not picked up (the profile gate remount covers
   profile switches).
6. `_focusWebDownloads` makes no explicit scroll jump (the reload's
   skeleton resets the offset as a side effect) and does not reset the file
   search, unlike the view selector.
7. System Back can pop the "loading" dialog while `_loadingDialogOpen` stays
   true; the later `_dismissLoading` then pops the route underneath (the
   pushed screen itself).
8. `_refresh`'s open-magnet branch is unreachable from the UI: the files view
   has no toolbar or pull-to-refresh.

9. `_navigateUp`'s explicit guarded `jumpTo(0)` is dormant while the files view is rendered: its list has no shared scroll controller, so `hasClients` is false. The root's observed offset 0 after Back comes from reattachment, not an executed jump. The original statement remains protected by the verbatim source guard; no accessor or UI control is added to activate it.

## Decisions

Items 1–5 were taken before design review; item 6 records Step 0b integration.

1. **Feature name** `alldebrid_files`, bridge `presentation/legacy_alldebrid/`.
2. **No format commit:** the original is format-clean (to verify in step 0).
3. **Goldens are included** (the builders move); Linux originals come from the
   step 0 checkpoint via Docker.
4. **No playback seam:** the launcher is not faked; the three handoffs are
   proven by the token-exact argument ledger plus behaviour up to the push.
5. **No size exceptions** are planned; any need found in step 0 is recorded
   with an exit milestone before the move.

6. **Step 0b integrator pin:** `occurrence_field_bindings.mandatory_qualification` is explicitly `true` in the AllDebrid config (already pinned at Step 0, retained and now asserted by the real-config self-test). The integrator's unconditional default is not relied on. `state_classes` / `field_classes`, `registered_occurrence_substitutions` and `require_live_state_callbacks` are not present on this branch and are not reimplemented here; any later need for those opt-ins must stop for integration.

## End-of-series device checklist

- Android TV: D-pad through the toolbar, view tabs, search field exits, clear
  button, first-row focus after load and after Back from a magnet, the add
  dialogs' arrow-down; tab-12 sidebar handoff.
- Playback handoff: single file, multi-file series magnet (start episode,
  lazy unlock of the rest), saved link.
- Downloads to device (file, selected magnet files, link) and copy link.
- Shared web link deep link opening Web Downloads (tab and Cloud hub).
- Home source editor picker binding (magnet and web download).
- tvOS and phone layouts (compact toolbar under 480 px).

## Round 1 review resolution

Codex round 1 (`ad-design`, gpt-6.1-sol xhigh): one P1, seven P2s, one P3.
1. **P1, deep-link comparison identity:** an opt-in `comparison_property`
   site kind for `torbox_callback_identity.py` is a step 0 deliverable, with
   independent negatives at assignment and comparison (Technique 2, Step 0.3);
   own-disposal clearing, replacement survival and post-dispose pending-flag
   delivery are characterized (table row 1).
2. **P2, owner construction:** PikPak's lazy, stable section cache is
   specified with constructors that only retain dependencies; `_load()`
   timing is unchanged (Technique 3).
3. **P2, add submissions:** contract 11 and table row 11.
4. **P2, invalid indices:** driven through the real `onDownload` callback
   (table row 4; contract 4).
5. **P2, credentials and live notification:** contracts 1, 6 and 9 corrected
   (`_load` re-reads every call; startup loads unawaited); headers, credential
   change and repeated notifications are characterized (rows 1 and 9).
6. **P2, loading dialog:** contract 6, the Loading dialog row, Found-not-fixed
   7.
7. **P2, filtered selection and live widget values:** contract 6, the
   Selection row, rows 1 and 9, and the pinned binder/live-getter config in
   Step 0.3.
8. **P2, guards and registrations:** the explicit guard rules with negatives;
   the shape-manifest facade transition; strict Linux goldens from step L.
9. **P3:** `home_source_editor_test.dart:196` added to the caller inventory;
   the mutually exclusive search-button branches described (contract 2).

## Round 2 review resolution

Codex round 2: one P1, one P2, one P3; round-1 items confirmed resolved.
1. **P1, scroll preservation:** the live-notification contract now states
   "no explicit jump" and the characterized held-response reset to offset 0
   (contract 1, row 1, Found-not-fixed 6).
2. **P2, refresh reachability and credential scope:** two reachable root
   refresh cases; the forced-files branch is dormant coverage through the
   frozen accessor's retained `_refresh`; the credential-change expectation
   is scoped to the torrents root (rows 6 and 9, Found-not-fixed 8).
3. **P3:** the search-button condition includes the non-empty backing list
   (contract 2).

## Round 3 review resolution

Codex round 3: all round-2 findings resolved, no P1 or P2 — "No P1s —
executable". Its one P3 (Found-not-fixed numbering) is fixed.



## Progress

### Step 0 — in progress; baseline and permitted seam

- Execution starts at clean `52996ce3` on `refactor/alldebrid-files`, base `49c53e2e`; original screen byte-identical to the base, Flutter 3.44.8 / Dart 3.12.2. Original format check: one file, zero changes. No extraction, push or device run.
- Untouched full suite `alldebrid_files/base`: 12,031 success / 13 failure / 29 error / 20 skipped; stable tested tree and SDK are recorded in `base.env.json`. Whole analyzer `base-analyze.txt`: 3,230 records, including unresolved vendor media-kit tests; this observed environment baseline is retained without dependency or suppression edits. Tree provenance is in its env file.
- Only a frozen `@visibleForTesting` accessor is added: fresh unmodifiable state snapshots, resource reads and the retained `_refresh` tear-off for the dormant forced-files branch. No action/service/player seam, setter, constructor change or original method move. Temporary facade ratchet 1,996 → 2,040 lines; original responsibilities remain until Steps 1–5 and final facade cap in Step 6.
- The first real HTTP fixture passed in an isolated original-code normal clone before writing the characterization matrix. It verifies the success envelope, ready-only filtering, exact magnet/status POST/header and lazy links. JSON/env/stable tested tree are retained as `original-fixture-first.*`; the clone contains only the original screen plus this permitted seam and test overlay.
- Existing manifest self-tests are being recorded before the opt-in shared-tool extension. All later-step production architecture/theme/shape registrations remain deferred to their scheduled steps. Base2, characterization/mutation proofs, final checks and fresh-clone verification are still pending; this is a seam checkpoint, not completion.

### Step 0 — original-code characterization checkpoint

- Nothing is extracted. All 98 original AST leaves and both class containers have frozen destinations in [alldebrid-files-deps.md](alldebrid-files-deps.md); the per-entry wiring checklist remains unchecked until the scheduled move. Three launch sites retain token-exact ordered launch/entry arguments and full owning bodies in `alldebrid_files_playback_ledger.json`. Callback owners stay on the State through Step 2, then the stable navigation section from Step 3.
- Checker configuration pins record owners/fields and receiver paths, mandatory field qualification, live context/mounted/setState and widget getters. The real-config positive has no scaffold masking. Independent raw callback checks reject wrappers and same-class foreign receivers at each assignment/comparison site; real moved `_load` fixtures reject bare/foreign fields, a field replacing a local, cached mounted and a foreign State setter. Only the additive opt-in `comparison_property` selector changes shared tooling. Existing manifest and fresh-clone verification are recorded below when complete.
- Ten test files contain 107 identities: 94 behavioral cases, including six macOS pixel cases, and 13 source-only cases. Every Step 0 table row (contracts 1–11, Loading dialog, Selection) is covered through real widgets, keys or MainPageBridge handlers. Requests compare complete ordered method/URL/form/header tuples; ids and selected order are deliberately non-monotonic. The dormant files refresh alone calls the frozen retained refresh accessor. Native playback handoffs and successful/mixed enqueue messages remain pending as permitted by rows 3/4.
- The fixture uses `ProfileRuntime.initializeLegacy`, SecretVault reset/device override, real storage credentials, HTTP success/error envelopes and platform clipboard mocking. Fixture-private Inter uses the existing valid font asset for deterministic popup metrics; bundled Roboto assets resolve to HTML, and remain untouched. The first original-code HTTP fixture preceded the matrix.

| Test file (all under `test/features/alldebrid_files/presentation/legacy_alldebrid/`) | Identities | Coverage |
| --- | ---: | --- |
| `alldebrid_add_playlist_test.dart` | 14 | Add magnet/link, clipboard paste, original-link save, playlist maps/dedup |
| `alldebrid_binding_test.dart` | 6 | Picker bindings, live callback, title and search visibility |
| `alldebrid_delete_selection_test.dart` | 11 | Destructive dialogs/order/errors, filtered selection/pruning |
| `alldebrid_fixture_test.dart` | 1 | Initial real HTTP fixture, ready-only filter |
| `alldebrid_focus_test.dart` | 5 | Hardware search exits, clear activation/left, add arrow-down, load focus |
| `alldebrid_navigation_test.dart` | 13 | Route/tab/TV handlers, back levels, query lifecycle, deep links, scroll, unmount |
| `alldebrid_playback_download_test.dart` | 13 | Unlock order/fallback/failures, dialog maps/indices, copy, duplicate/modal Back hazard |
| `alldebrid_profile_test.dart` | 14 | Credential changes, cached action headers, remount resources |
| `alldebrid_source_contract_test.dart` | 13 | Lifecycle, three launch ledgers, three enqueue sites, dormant branches and feedback |
| `alldebrid_views_test.dart` | 17 | Loads/retry/lazy views/refresh/search/keys/empty/error; six macOS goldens |

Mutation proof summary: **83 variants: 70 behavioral and 13 source-only; 107 unique test identities killed (94 + 13); zero final survivors and zero compiler/infrastructure kills.** The frozen case file maps each variant to exact test identities and original-method edits; `mutation-table.json` and per-case `.patch`, `.jsonl`, `.stderr`, `.result.json` under `.git/refactor-evidence/alldebrid_files/` contain actual assertion failures and source hashes. Every edit was applied to the original 49c53e2e implementation plus permitted seam in a normal scratch clone, restored in `finally`, and never committed. Behavioral and source-only runs are separate.

| Variant | Kind | Named test assertions killed | Result |
| --- | --- | ---: | --- |
| `ready-filter` | behavioral | 1 | PASS: assertion failure |
| `back-root-sentinel` | behavioral | 2 | PASS: assertion failure |
| `focus-first-row` | behavioral | 2 | PASS: assertion failure |
| `back-priority` | behavioral | 1 | PASS: assertion failure |
| `navigate-reset` | behavioral | 1 | PASS: assertion failure |
| `initial-query-trim` | behavioral | 1 | PASS: assertion failure |
| `pending-consumption` | behavioral | 2 | PASS: assertion failure |
| `own-handler-clear` | behavioral | 1 | PASS: assertion failure |
| `replacement-handler-survives` | behavioral | 1 | PASS: assertion failure |
| `live-search-reset` | behavioral | 1 | PASS: assertion failure |
| `reload-skeleton-detach` | behavioral | 1 | PASS: assertion failure |
| `unmount-publication` | behavioral | 1 | PASS: assertion failure |
| `picker-map-fields` | behavioral | 2 | PASS: assertion failure |
| `picker-empty-hash` | behavioral | 1 | PASS: assertion failure |
| `picker-toolbar-title` | behavioral | 1 | PASS: assertion failure |
| `picker-empty-search` | behavioral | 1 | PASS: assertion failure |
| `picker-live-dispatch` | behavioral | 1 | PASS: assertion failure |
| `search-up-target` | behavioral | 1 | PASS: assertion failure |
| `file-search-up-target` | behavioral | 1 | PASS: assertion failure |
| `add-dialog-down` | behavioral | 2 | PASS: assertion failure |
| `multi-unlock-start-order` | behavioral | 2 | PASS: assertion failure |
| `no-videos-snack` | behavioral | 1 | PASS: assertion failure |
| `single-shortcut-snack` | behavioral | 1 | PASS: assertion failure |
| `unlock-failure-file_play` | behavioral | 1 | PASS: assertion failure |
| `unlock-failure-file_download` | behavioral | 1 | PASS: assertion failure |
| `unlock-failure-link_play` | behavioral | 1 | PASS: assertion failure |
| `unlock-failure-link_download` | behavioral | 1 | PASS: assertion failure |
| `dialog-maps` | behavioral | 1 | PASS: assertion failure |
| `invalid-selection-result` | behavioral | 1 | PASS: assertion failure |
| `clipboard-value` | behavioral | 1 | PASS: assertion failure |
| `duplicate-modal` | behavioral | 1 | PASS: assertion failure |
| `system-back-dismiss` | behavioral | 1 | PASS: assertion failure |
| `missing-key-text` | behavioral | 1 | PASS: assertion failure |
| `load-error-text` | behavioral | 2 | PASS: assertion failure |
| `view-selection-reset` | behavioral | 1 | PASS: assertion failure |
| `root-refresh-header-false` | behavioral | 1 | PASS: assertion failure |
| `root-refresh-header-true` | behavioral | 1 | PASS: assertion failure |
| `row-key` | behavioral | 1 | PASS: assertion failure |
| `dormant-force-retention` | behavioral | 1 | PASS: assertion failure |
| `search-case` | behavioral | 1 | PASS: assertion failure |
| `empty-state-text` | behavioral | 1 | PASS: assertion failure |
| `open-file-error` | behavioral | 1 | PASS: assertion failure |
| `golden-padding` | behavioral | 6 | PASS: assertion failure |
| `magnet-cancel` | behavioral | 1 | PASS: assertion failure |
| `magnet-delete-order` | behavioral | 4 | PASS: assertion failure |
| `link-delete-results` | behavioral | 4 | PASS: assertion failure |
| `visible-only-selection` | behavioral | 1 | PASS: assertion failure |
| `prune-stale-selection` | behavioral | 1 | PASS: assertion failure |
| `add-magnet-cancel-empty` | behavioral | 2 | PASS: assertion failure |
| `add-magnet-header` | behavioral | 2 | PASS: assertion failure |
| `clipboard-prefix` | behavioral | 1 | PASS: assertion failure |
| `add-link-cancel-empty` | behavioral | 2 | PASS: assertion failure |
| `add-link-validation` | behavioral | 1 | PASS: assertion failure |
| `add-link-header` | behavioral | 3 | PASS: assertion failure |
| `playlist-map` | behavioral | 2 | PASS: assertion failure |
| `playlist-hash-reject` | behavioral | 1 | PASS: assertion failure |
| `root-key-reread` | behavioral | 1 | PASS: assertion failure |
| `remount-new-key` | behavioral | 1 | PASS: assertion failure |
| `cached-action-play_file` | behavioral | 1 | PASS: assertion failure |
| `cached-action-play_magnet` | behavioral | 1 | PASS: assertion failure |
| `cached-action-download_file` | behavioral | 1 | PASS: assertion failure |
| `cached-action-download_magnet` | behavioral | 1 | PASS: assertion failure |
| `cached-action-play_link` | behavioral | 1 | PASS: assertion failure |
| `cached-action-download_link` | behavioral | 1 | PASS: assertion failure |
| `cached-action-copy_link` | behavioral | 1 | PASS: assertion failure |
| `cached-action-add_magnet` | behavioral | 1 | PASS: assertion failure |
| `cached-action-add_link` | behavioral | 1 | PASS: assertion failure |
| `cached-action-delete_magnet` | behavioral | 1 | PASS: assertion failure |
| `cached-action-delete_link` | behavioral | 1 | PASS: assertion failure |
| `cached-action-playlist` | behavioral | 1 | PASS: assertion failure |
| `source-only-01` (verbatim State startup and ten ordered disposals) | source-only | 1 | PASS: assertion failure |
| `source-only-02` (token-exact file launcher arguments and mounted handoff) | source-only | 1 | PASS: assertion failure |
| `source-only-03` (token-exact series playlist sorting fallback clamp and launcher arguments) | source-only | 1 | PASS: assertion failure |
| `source-only-04` (token-exact saved-link launcher arguments and notify order) | source-only | 1 | PASS: assertion failure |
| `source-only-05` (file enqueue credentials context size and failure contracts) | source-only | 1 | PASS: assertion failure |
| `source-only-06` (saved-link enqueue credentials context and failure contracts) | source-only | 1 | PASS: assertion failure |
| `source-only-07` (selected-files sequential enqueue and three result branches) | source-only | 1 | PASS: assertion failure |
| `source-only-08` (download dialog maps retain full paths sizes indices and unawaited callback) | source-only | 1 | PASS: assertion failure |
| `source-only-09` (playlist persistence single and collection maps retain all arguments) | source-only | 1 | PASS: assertion failure |
| `source-only-10` (shared loading flag guard clear-before-pop and non-dismissible barrier) | source-only | 1 | PASS: assertion failure |
| `source-only-11` (dormant non-ready snacks and badges remain unreachable and verbatim) | source-only | 1 | PASS: assertion failure |
| `source-only-12` (navigate-up attached-scroll reset and focus protocol remain verbatim) | source-only | 1 | PASS: assertion failure |
| `source-only-13` (clipboard auto-paste and original input link-save contract remain verbatim) | source-only | 1 | PASS: assertion failure |

- Initial survivors led to stronger assertions, never relaxed ones: catch-side mounted protection as well as success-side protection; add-dialog focus landing on a button; selection reset on every view transition; mixed-case name/host queries; Cancel/empty with no snackbar; both playlist-map branches. A runner classifier initially mistook the literal `Failed to load` in expected source text for compilation failure; it now requires an actual runner-error prefix, and the affected proofs were rerun. First attempts and rechecks remain in `mutations/` and `mutations-final/`; final navigate and source-reader follow-ups remain separate.
- Source-text inventory is frozen in the dependency report: one bare radius and five shape token calls; theme/shape/import/placement registrations wait for the scheduled extraction steps. Four generic storage checks, file-size ratchet and architecture checks pass. Existing profile/theme/shape source guards were run: the profile direct-SharedPreferences inventory failure is the same observed baseline identity; all 107 added identities and both production caller suites pass in the original-code scoped comparison (157 success / 1 baseline failure; comparison PASS). No suppression, allowlist, dependency or other-feature source change.
- CI lists all ten concrete new test paths. `checks.yml` adds the facade and support globs inside both format/analyze commands before any `| tee`. The Linux capture script is committed, shell-syntax checked, **not run**: local `debrify-flutter:3.44.8`, linux/amd64, normal clone under container HOME, container pub get, double capture in reversed order and strict replay. Claude owns Step L, including verified Linux PNGs and strict default. No Docker/device/emulator run or push.

Final full-suite, whole-analyzer, shared-tool and fresh-clone evidence follows in the verification checkpoint.

- Current original-code matrix: 107/107 passing, stable tested tree (`original-characterization-current.*`); its identity set exactly equals the named mutation kills (`characterization-mutation-coverage.json`). Whole analyzer: 1,718 records, zero added identities versus the 3,230-record untouched baseline, stable tree (`step0-analyze-final.*`, comparison PASS). Two independent macOS capture processes, second in reversed order, each passed 6/6 and preserved all six already-characterized PNG hashes (`mac-original-double-capture.json`).

### Step 0 — verification and reader qualification checkpoint

- Seam-only `base2` full rerun (concurrency 2, frozen normal clone at `a0d2b7a33`): 12,032 success / 13 failure / 28 error / 20 skipped; comparison against untouched base PASS, zero additions/omissions/new skips. Xtream 50k now passes and is retained as an observed passing identity. The first complete characterization `base3` at `50efffabb` (concurrency 1): 12,139 success / 13 failure / 28 error / 20 skipped; comparison against base2 PASS, exactly 107 added identities, all passing. Full raw/environment records are preserved separately before the reader fix below. No merged/overlaid test outcomes.
- Load NOTE: the first contended base2 added four UDP and three WebDAV shard errors; a concurrency-1 full rerun added only the three WebDAV timeouts. Original logs/comparisons remain. WebDAV rerun in the same seam clone passed 105/105, scoped comparison PASS; the next full concurrency-2 base2 comparison passes. An aborted base3 concurrency-4 attempt with four UDP errors and its failed isolated rerun also remain preserved; the completed concurrency-1 base3 has no UDP regression. The observed host load reached approximately 181, and WebDAV errors explicitly report 30-second timeouts. The Xtream M3U case after a grouped 50k timeout passed alone. No allowlist, timeout, test assertion or dependency was relaxed.
- All 20 existing manifest self-tests pass with isolated parser copies and copied kernels deleted. Every before/after adapter output is byte-identical; four available complete self-test stdout baseline pairs are also identical. Removing only the new 25-line opt-in comparison branch reconstructs the previous shared-tool file byte-for-byte, and all existing JSON configs opt out. `existing-manifests-after.json`, `existing-manifests-verdict.json`, `opt-in-isolation.json` and `step0-preservation-proof.json` record the proof.
- Fresh normal clone of `50efffabb`, `.git` directory, after flutter pub get: checker plus real-config fixtures PASS; 107/107 Dart identities PASS with stable tree; the mutation driver demonstrates a real original-code assertion kill; Linux script syntax only PASS, not run; clean clone. `fresh-clone-result.json` and input hashes record this checkpoint.
- Reader audit found that a facade-only early return would bypass qualification normalization between field and method moves. It is removed using the existing normalization rules. All 13 original source guards still pass; all 13 source-only original mutants still fail named assertions. A real original `_showLoading` body with registered owner/live callback qualifications now normalizes in the retained facade, while foreign receiver/cached mounted variants remain rejected. The previous reader fails the new positive. These real-config probes join the existing checker self-test (no new characterization identities); no production move or widened callback/field allowance. A final full base3, analyzer and fresh-clone check follow for this correction.

- Reader correction verification before its checkpoint: extended real-config checker PASS (`reader-fixed-checker.txt`); original-code matrix 107/107 PASS with stable tested tree (`reader-fixed-original-characterization.*`); whole analyzer 1,709 records, zero added diagnostic identities against the untouched baseline, stable tested tree (`reader-fixed-analyze.*`, comparison PASS). The final suite/fresh-clone runs use the committed correction.

### Step 0 — complete; stop before Step L / Step 1

- Checkpoints: `a0d2b7a33` freezes the permitted seam; `50efffabb` freezes original-code characterization, manifests, ledger, dependency/wiring report, mutations, macOS PNGs, CI paths and the unrun Linux script; `225cdc521` adds the retained-facade qualification proof. This final checkpoint records verification only. Every original production byte at `49c53e2e` remains unchanged; the only application addition is the frozen 44-line accessor. No extraction/destination production file, dependency upgrade, Premiumize edit, push, device or emulator run.
- Final full `base3` at `225cdc521`, Flutter 3.44.8 / Dart 3.12.2, `--no-pub --concurrency=2`: **12,139 success / 13 failure / 28 error / 20 skipped**, stable tested tree `deb7cdfd29b423e19721c73604b072a8b71a5eae`, full-suite paths empty. `suite_evidence.py compare` against final seam-only `base2`: **PASS**, exactly 107 added identities, all passing; zero new failures, missing identities or new skips. Comparison against `base3-before-reader-fix` also PASS, zero added/missing identities or regressions. Final base2 versus untouched base remains PASS (zero additions). Existing baseline failures/errors remain visible; no `--record`, allowlist or merged outcome acceptance. Evidence: `base2-compare.txt`, `base3-compare.txt`, `base3-reader-fix-compare.txt`, raw JSONL and environment sidecars.
- All 107 characterization identities are proven against original production code: 94 behavioral (six macOS pixel cases included) / 13 source-guard-only. The final table has **83 variants: 70 behavioral / 13 source-guard**, yielding **94 / 13 named assertion kills**, **zero survivors and zero invalid proofs**. Source-guard variants ran separately; every scratch source was restored and no mutant was committed. The late reader correction reran all 13 source-only mutants (`mutations-reader-fixed/`) and the final table selects those results. `characterization-mutation-coverage.json` proves exact identity equality; `mutation-table.json` and per-variant patch/raw/error/assertion results retain the evidence. The separate reader self-test also rejects foreign receiver and cached mounted variants; the old reader fails its new real-facade positive.
- Whole-repository analyzer after the final reader change: **1,709 diagnostic records, zero added identities** versus untouched base's 3,230; stable tree and identical SDK. Historical/vendor findings remain visible. `reader-fixed-analyze.*`, `reader-fixed-analyzer-compare.txt` and `step0-final-result.json` record the comparison. Earlier local storage/size/architecture checks and existing profile/theme/shape/caller verification stand; no affected implementation changed afterward. All 20 existing manifest self-tests pass, with byte-identical before/after adapter output and isolated parser copies; the shared file is byte-identical outside its 25-line opt-in branch.
- Final **fresh normal clone** of this branch at `225cdc521` (`/tmp/debrify-ad-step0-reader-fixed-fresh`, `.git` directory), after `flutter pub get`: extended checker and every new real-config fixture PASS using an isolated `--parser-package` copy with copied `*.dill` deleted; **107/107 tests PASS**, stable tree; mutation driver proves a named assertion kill of original code; Linux script **syntax only** PASS; clone clean. `fresh-reader-result.json`, `fresh-reader-checker.txt`, `fresh-reader-characterization.*` and `fresh-reader-mutations/` retain the records. The implementation inputs match the tested clone; this last commit changes documentation only.
- Load-sensitive reruns and failed/incomplete attempts remain preserved with NOTE, including the failed isolated UDP rerun (`base3-udp-isolated.*`); both final full suites pass their comparisons, including the now-observed-passing Xtream 50k identity. The final base3 required no isolated rescue or accepted regression.
- Six macOS originals are committed and matched across two independent captures in reversed order. **Linux Step L remains Claude-owned:** `capture_alldebrid_files_linux_goldens.sh` was not run. Its verified original PNGs and strict default must be committed before extraction. Per Step 0 rows 3/4, the three native player handoffs and successful/mixed enqueue messages remain pending: launcher fakes are prohibited and no isolated successful native enqueue fixture was established. Exact source guards cover those arguments/branches; behavioral coverage reaches unlock/failure and the real selection-dialog callback. Physical focus/device verification and remote CI remain pending under the no-device/no-push scope. No other Step 0 deliverable is outstanding.

### Step 0b — independent review closure (original code; no extraction)

- Claude's independent sample at `50efffabb`: 40 one-line original mutations, behavioral suites plus provider picker and no source-contract suite; 29 caught / 11 survived. Six survivors identify behavioral gaps closed below. Five are accepted source-only boundaries: `fallback-idx` (fallback `startIndex = i`), `relpath` (`firstSlash > 0`), `multi-size` (positive-size ternary), `playfile-mode` (`PlaylistViewMode.sorted`) follow the no-launcher-seam / token-exact playback ledger decision; `navup-jump` is dormant (`hasClients == false` in the rendered files view). Its source guard remains retained. Root reattachment reaching offset 0 is not proof that the jump executed.
- New `alldebrid_review_closure_test.dart` has six real-entry behavior tests: live deep-link reset reads the retained controller and reopens the field; TV content focus requested inside a magnet leaves Back focused and defers first-row focus; snackbar visible at 2,999 ms and gone after 3,001 ms plus the exit animation; AppBar files-search opens and focuses the field without `enterText`; clear-button Left consumes the hardware event and returns to the field even when host directional traversal is disabled; search Down on an empty initial library unfocuses the field with the first-row node never attached. Exact ordered requests remain asserted. No production method or frozen accessor changed.
- The mutation fixture edits are copied from Claude's actual review script, not substitute mutations; all eleven full mutant sources are asserted byte-identical to that script's replacements. Six behavioral variants run separately from five accepted source-only probes in an original-code scratch clone. Per-variant patches, JSONL, stderr and named assertion evidence live under `step0b-mutations-behavioral/` and `step0b-mutations-source/`; `step0b-review-mutations.json` records the independent input script hash. Initial fixture-only setup errors remain as `step0b-original-first.*` / `step0b-original-six.*`; the corrected original six-case run passes 6/6 (`step0b-original-six-final.*`).

| Review mutant | Boundary | New characterization / retained guard | Result |
| --- | --- | --- | --- |
| `fwd-searchctl` | behavioral | retained root-search controller cleared by live handler | PASS: named assertion failure |
| `focus-atroot` | behavioral | TV content focus while a magnet is open | PASS: named assertion failure |
| `snack-dur` | behavioral | three-second visibility deadline | PASS: named assertion failure |
| `filesearch-focus` | behavioral | AppBar post-frame field focus without text entry | PASS: named assertion failure |
| `clear-left` | behavioral | real Left consumed before framework traversal | PASS: named assertion failure |
| `movefocus-ctx` | behavioral | unattached target releases field | PASS: named assertion failure |
| `navup-jump` | dormant source-only | retained navigate-up body | PASS: named assertion failure |
| `fallback-idx` | launch source-only | retained series playlist body / ledger | PASS: named assertion failure |
| `relpath` | launch source-only | retained series playlist body / ledger | PASS: named assertion failure |
| `multi-size` | launch source-only | retained series playlist body / ledger | PASS: named assertion failure |
| `playfile-mode` | launch source-only | retained single-file body / ledger | PASS: named assertion failure |

- CI gains the concrete new review-closure test path. The explicit qualification pin is retained and asserted by the changed self-test; no shared occurrence-binder change or forthcoming edit-profile opt-in key is introduced. Full `base3b`, comparison to final `base3`, focused analyzer and fresh normal-clone changed-self-test results follow. Linux capture remains unrun and Claude-owned; Step 1 is not started.

- Mutation/checker verification checkpoint: **6/6 exact behavioral mutants killed + 5/5 accepted source-only probes killed; zero survivors / invalid proofs**. Every recorded mutant SHA equals Claude’s full replacement SHA. Scratch original source restored to frozen seam SHA `e35a1af1…`. Extended real-config checker PASS (`step0b-checker.txt`), including the explicit qualification pin; focused analyzer has no issues (`step0b-focused-analyze.txt`). The sole new test file is format-clean. `step0b-mutation-table.json` records final results; the original Step 0 mutation table is preserved. Full-suite and fresh-clone evidence follows after this implementation checkpoint.

### Step 0b — complete; stop before Step L / Step 1

- Final full `suite_evidence.py run alldebrid_files/base3b --no-pub --concurrency=2`, Flutter 3.44.8 / Dart 3.12.2: **12,145 success / 13 baseline failure / 28 baseline error / 20 baseline skipped**. `suite_evidence.py compare --against base3.jsonl base3b.jsonl`: **PASS**, exactly **six added identities, all passing**, zero new failures, missing identities or new skips. Stable full tested tree `65642fa8998befa313f73a6110eae66c353d2510` at implementation checkpoint `0eae99e8a`; no scoped paths or tracked edits during the run. `base3b.*` and `base3b-compare.txt` preserve raw outcomes/provenance. No load-sensitive regression needed rescue, no allowlist/`--record` acceptance and no result overlay.
- A fresh normal `git clone` of the branch's implementation checkpoint, `.git` directory, after `flutter pub get`, passes the changed real-config checker/self-test with a private parser copy and copied `*.dill` deleted. **113/113 AllDebrid identities pass**, stable tested tree; clone clean. The unchanged mutation driver also demonstrates an original-code assertion kill from that clone. Evidence: `step0b-fresh-result.json`, `step0b-fresh-checker.txt`, `step0b-fresh-characterization.*`, `step0b-fresh-mutations/`. Every production/test/helper/checker/config/CI input byte-matches the final implementation; only this completion documentation is added afterward.
- Closure totals: **six new behavioral tests in one new file**, CI path registered; original characterization now **113 tests in eleven files** (100 behavioral including six macOS pixels / 13 source-only). **Six exact behavioral mutants + five exact accepted source-only probes fail named assertions, zero survivors / invalid proofs.** Existing guards were retained; all final characterization identities equal the union of original and Step 0b named mutation kills. `step0b-mutation-table.json` and `step0b-final-result.json` record the complete result. The independent 40-case script is preserved as `step0b-independent-review-mutants.py`; this closure reran its eleven surviving edits exactly, not the whole independent sample.
- The qualification config was already explicitly pinned `true` and remains byte-identical; its changed self-test now requires that pin. No forthcoming `edit_profile` occurrence opt-in was implemented, no shared tool change, and no production/accessor change. The original-with-seam facade SHA remains `e35a1af1e91b8b997f03106da3a617827749ce740723e2e2ace5629d5fb5b7a0`. Focused analyzer: no issues; both changed Dart files format-clean; diff checks pass. Linux capture is **not run**, Claude owns Step L; no extraction, push, device/emulator run or Premiumize edit.
