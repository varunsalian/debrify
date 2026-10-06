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
     does **not** reset the scroll offset or the file search (see Found, not
     fixed).
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
     exclusive; exactly one is built, with `_toolbarSearchFocusNode` attached,
     in each mode.
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
   | 1 Navigation | Tab versus pushed route (registered and removed on dispose, with sentinel handlers); the TV focus closure focusing the first row; each back level; `_navigateUp` focus and scroll reset; the initial query trimmed and applied once (a same-key widget update with a new query does not re-apply it). Deep link: the handler set in both modes; a pending flag opening Web Downloads and loading links once; **own disposal clears** the handler; a second screen's registration **survives** the first one's disposal; after the last screen disposes, a notification sets the pending flag and the next mount consumes it; **repeated live notifications** each reload links and reset magnet, files, selection and root search, while the scroll offset and file-search state are preserved. |
   | 2 Select-source | Pushed picker: magnet binding (callback once, awaited before the pop, every `SeriesSource` field, `boundAt` in range) and its empty-hash rejection; web binding for a video link, a non-video link not tappable; hidden actions; the select-mode title and search button. |
   | 3 Playback | A fake launcher seam is not added; the three sites are covered by the argument ledger (source guard, token-exact) plus behavioural tests up to the handoff where reachable: unlock request order for a multi-file magnet (start entry first, fallback order on failure), the "No playable video files found." and unlock-failure snacks, and the single-video shortcut. Launch itself is **pending device verification**. |
   | 4 Downloads | Source guards on the three enqueue sites and the dialog-map construction; the dialog opened from the magnet action with its file list. The selected-files loop is driven through the **real `FileSelectionDialog.onDownload` callback** (found in the widget tree) with synthetic selected maps: missing, negative and out-of-range `_adIndex` count failures **without** unlock requests; empty unlocks count failures; unlock request order follows selection order. Success and mixed-result messages only if an isolated enqueue fixture is proven against the original; otherwise **pending**. Copy link writes the unlocked URL to the clipboard. |
   | 5 Destructive | Magnet delete Cancel (no request), single, selected (list order with non-monotonic selection order), all; link delete single, all, and a partial failure count; the follow-up reload and snacks. |
   | 6 Lists | Initial load (ready-only filter), missing key, load error and Retry, lazy links load once, view switch resets, refresh in each of the three contexts, open magnet and forced refresh keeping files, the three searches, row keys, empty states. Pixel goldens (macOS and Linux) of: magnet root, Web Downloads, magnet files view, selection mode, select-source picker, error state. |
   | 7 D-pad | Search field up/down/right exits, the clear button's Enter and arrow-left, file-search up/down, the add dialogs' arrow-down, focus after load. |
   | 8 Lifecycle | Source guards on the verbatim lifecycle and the 10 disposals; unmount during a pending load: no throw. |
   | 9 Profile | The exact `Authorization: Bearer` header on every request; after a stored-credential change, a refresh in the torrents view uses the new key (since `_load` re-reads) while the links view and actions keep the cached key until `_load` runs; a remount reads the key again; two routes don't share owners. A same-key widget update with a new `onSourceSelected` callback: the next binding calls the new callback (live widget getters). |
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
6. `_focusWebDownloads` does not reset the shared scroll offset or the file
   search, unlike the view selector.
7. System Back can pop the "loading" dialog while `_loadingDialogOpen` stays
   true; the later `_dismissLoading` then pops the route underneath (the
   pushed screen itself).

## Decisions taken before design review

1. **Feature name** `alldebrid_files`, bridge `presentation/legacy_alldebrid/`.
2. **No format commit:** the original is format-clean (to verify in step 0).
3. **Goldens are included** (the builders move); Linux originals come from the
   step 0 checkpoint via Docker.
4. **No playback seam:** the launcher is not faked; the three handoffs are
   proven by the token-exact argument ledger plus behaviour up to the push.
5. **No size exceptions** are planned; any need found in step 0 is recorded
   with an exit milestone before the move.

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

