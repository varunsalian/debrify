# Real-Debrid downloads screen refactor — plan

Written 2026-10-03 on `refactor/codebase`; design-reviewed by Codex in two rounds (no P1s); starts at `e06efe4b`. Follow [AGENTS.md](../../AGENTS.md).
Read `docs/refactoring/torbox-downloads-plan.md` (and, through it, the IPTV and
settings plans) first. This plan reuses the TorBox technique, checker, staging
and gate procedure, and only states what differs.

Work on the existing `refactor/codebase` branch. Commit after every step. Never
push to `origin`; push to `private` only if the goal says so. Gate commits must
contain `gate`.

## Goal

`lib/screens/debrid_downloads_screen.dart` is 6,445 lines: the Real-Debrid
cloud library. It holds:
- the torrents and DDL lists, with paging;
- folder browsing (raw, A–Z sorted and series-arranged views);
- playback (single file, folder, multi-file torrent, DDL);
- downloads (single, selected, folder, DDL);
- playlist and Debrify TV add;
- link copying;
- adding magnets and links;
- selection mode with bulk delete, and delete-all;
- two searches (torrent search, in-folder search);
- the select-source mode used by other screens.

Split it into a new feature, `lib/features/debrid_downloads/`, **moving code
verbatim**.
- **Unchanged:** the widget tree, keys, focus nodes, build order and the
  State's lifecycle.
- **Stays in `debrid_downloads_screen.dart`:** the public `DebridDownloadsScreen`
  widget (same constructor and parameters) and its State. The State keeps a
  verbatim `initState`, `dispose` and `build` forwarder, plus its section
  wiring. There is no `didUpdateWidget`, and none is added.

**Nothing is merged with TorBox.** Nine helpers are textually identical to
TorBox's (the six sort/series helpers, `_queryMatchesInitialTitle`,
`_buildSelectionBar`, `_FolderViewMode`). They're moved into this feature as
copies. Unifying them is a later, separate behaviour-level plan, and no file
under `lib/features/debrid_downloads/` may import from
`lib/features/torbox_downloads/` or the reverse.

**Architectural status:** a bounded legacy-extraction stage. The temporary
exceptions and their exit milestones are:
- **State-driven sections instead of Riverpod.** Exit: move the Real-Debrid
  library state (lists, navigation, selection, search) into Riverpod notifiers
  in a later change.
- **A `legacy_debrid/` bridge folder that calls services directly.** Exit:
  put `DebridService`, `RealDebridStorage`, `PlaylistStorage`,
  `DownloadService` and launcher calls behind Real-Debrid data contracts, then
  dissolve the bridge.
- **Unchanged legacy text.** Exit: the app-wide localization migration.
- **Duplicated helpers shared with TorBox.** Exit: a shared cloud-library
  plan (`docs/refactoring/cloud-library-shared-plan.md`, to be written after
  both the TorBox and Real-Debrid extractions are complete).

## Public surface

`const DebridDownloadsScreen({super.key, initialTorrentForOptions, isPushedRoute
= false, initialSearchQuery, selectSourceMode = false, onSourceSelected})`
keeps this exact signature, defaults and field doc comments; the nullable
parameters default to null. It's the only public symbol. Its five public
fields count as surface: `home_source_editor_test.dart` reads three of them.

Callers:
- `main.dart`: the tab page (1542), `MainPageBridge.openDebridOptions`
  (1741), and the Cloud hub push (3392);
- `home_source_editor.dart`;
- `catalog_browser.dart`;
- `aggregated_search_results.dart`;
- `trakt_results_view.dart`;
- two deprecated home widgets (commented-out references only);
- two tests: `provider_source_picker_web_download_test.dart` (mounts it) and
  `home_source_editor_test.dart` (inspects the constructed widget).

## What it contains (line numbers at `e5ec91b9`; the step 0 manifest is authoritative)

| Lines | Area | Notes |
| --- | --- | --- |
| 1–66 | Imports (31), widget, enums `_DebridDownloadsView`, `_FolderViewMode` | No top-level helpers. |
| 68–168 | 51 of the 53 State fields, and the getters `_activeSelectedIds`, `_activeItemCount`, `_isAllSelected` | 52 instance fields plus static `_limit`. |
| 3366–3369 | **The other 2 fields**, declared mid-file: `late final _torrentSearchFocusNode` (assigned in `initState`) and `final _torrentSearchClearFocusNode = FocusNode(debugLabel: 'rd-torrent-search-clear')` (initialized at its declaration) | They move with the other owners. |
| 170–335 | `initState`, `_focusFirstItemOrFallback`, `dispose` | The lifecycle **stays verbatim in the State**. |
| 337–756 | Back navigation, scroll paging, key loading, torrent fetching and paging, torrent search, DDL fetching and paging | |
| 758–866 | Torrent and DDL row actions | `_handlePlayVideo` (758) is dormant. |
| 868–1653 | Single delete, delete-all (two twin progress dialogs, 163 lines each), selection and delete-selected | |
| 1655–1808 | Feedback and error-message helpers | |
| 1810–2406 | Folder navigation (`_navigateIntoTorrent` with the RAR dialog), folder title, sort and series view modes | |
| 2408–2652 | In-folder search | |
| 2654–3720 | `build` and the list, toolbar, search and card builders | |
| 3722–3956 | Torrent download, playlist and Debrify TV add, DDL card | |
| 3958–4254 | `_handlePlayMultiFileTorrent` (297 lines) | |
| 4256–4841 | Magnet add and link add | |
| 4843–5893 | **Dormant cluster** (~1,050 lines), including `_buildModernFileCard` (432 lines) | Reached only from the uncalled `_buildSeriesFileBrowser`. |
| 5895–6436 | Folder-node play, download and playlist actions; date and link helpers | `_copyDownloadLink` (6390) is dormant. |
| 6439–6445 | `_RDSearchResult` | Plain data. |

No single method is over 500 lines.

## Contracts that must not change

1. **Navigation and back handling.**
   - **Pushed route:** `MainPageBridge.pushRouteBackHandler(_handleBackNavigation)`
     and `popRouteBackHandler(_handleBackNavigation)`. These compare the
     tear-off with `==`, so registration and teardown must pass the same
     receiver and method.
   - **Tab:** `registerTabBackHandler('realdebrid', …)`, the **key-only**
     `unregisterTabBackHandler('realdebrid')` in `dispose`, and the TV content
     focus handler for tab **4** (a stored closure, unregistered by identity).
   - **The 10-second "failed to open" pop** for `initialTorrentForOptions`
     keeps its condition (`mounted && isPushedRoute && !selectSourceMode &&
     initialTorrentForOptions != null && _currentTorrentId == null`), message,
     colour and timing.
   - **The deep-link post-frame poll:** up to 20 × 150 ms for `_apiKey`, then
     `_navigateIntoTorrent` if mounted.
   - **Back priority** in `_handleBackNavigation` (337–386). It differs from
     TorBox's: there's **no torrent-search level**.
     1. Select-source on a pushed route pops.
     2. Selection mode exits.
     3. In-folder search closes.
     4. Inside a subfolder, go up.
     5. At a torrent root: a deep-linked open (`isPushedRoute &&
        initialTorrentForOptions != null`) pops. Otherwise
        `returnToTorrentSearchOnBack` clears the flag and switches to the
        legacy torrent-search tab. Otherwise go up to the torrents list.
     6. Otherwise return `false`.
2. **Select-source mode** (`selectSourceMode`, `onSourceSelected`,
   `initialSearchQuery`).
   - **Torrent rows** (3667), from the list and from torrent-search results:
     `SeriesSource(torrentHash, torrentName, debridService: 'rd',
     debridTorrentId, boundAt)`, then a pop.
   - **DDL rows** (3888), active only when `streamable == 1 ||
     isVideoFile(filename)`: the same with `torrentHash: ''` and
     `cloudSourceKind: SeriesSource.cloudKindWebDownload`, then a pop.
     Other DDL rows are disabled.
   - **Hidden toolbars, the `AppBar` title, the early return in
     `_toggleTorrentSearch`, the `_hiddenFromNav` title guard, and the
     pre-filled, auto-submitted torrent search** stay as they are.
3. **Playback handoff:** all **six launcher sites** (4 live: 820, 4233, 5920,
   6023; 2 dormant: 774, 4868) keep their arguments (`videoUrl`, `title`,
   `subtitle`, `playlist`, `startIndex`, `viewMode`) and their `mounted`
   guards, or the absence of one.
   - **Multi-file series play** keeps prefetching the first-episode index
     while launching with `startIndex: 0`.
4. **Downloads:** all **four enqueue sites** (3 live: 848, 6102, 6265;
   1 dormant: 4964) keep their payloads, `credentialKey:
   'real_debrid_api_key'`, file naming and meta JSON.
   - **The two inline `mounted ? context : null`** (6108, 6272) stay inline.
   - **`_downloadSelectedRealDebridFiles`** keeps its sequential awaited loop
     and its two callers' different `linkIndex` meanings.
5. **Destructive actions.** Every request is an HTTP **DELETE** with a
   **string** id in the path (`debrid_service.dart:540`, `:561`); no body.
   - **Single delete** (torrent and DDL): confirmation (Cancel makes no
     request), a loading dialog, the request, then removal and a message.
   - **Delete all** (torrents and DDL, twin flows): it fetches every item
     **unfiltered** with `limit: 1000`, checking cancellation before each
     page. Cancelling during the fetch refetches and returns. It then deletes
     sequentially in fetched order, checks cancellation before each request
     (an in-flight request finishes), and waits 150 ms **only after a
     successful** delete. Selection isn't touched. Keep all of this exactly,
     including that delete-all also removes torrents the list hides.
   - **Delete selected:** a snapshot of the active selection in insertion
     order and sequential requests. After each request, success or failure,
     there's a 150 ms wait, **unless** cancellation is seen at the
     post-request check (1610), which breaks out before the wait.
     - **Completion** (including partial failure) removes deleted rows,
       clears both selection sets and leaves selection mode.
     - **Cancellation** removes deleted rows and their ids from the active
       set only, and stays in selection mode, with no message.
6. **Lists and views:** the same paging triggers (pixels ≥ max − 200), page
   size 50, the torrent-search fetch (`limit: 2000`, at most 3 pages), sorting,
   search matching, and empty and error states.
   - **The view-mode dropdown** offers only Raw and Sort (A-Z) (2769–2775).
     Series Arrange is unreachable; its branches and helpers move verbatim as
     dormant code.
   - **`_resetListScroll`** keeps its remove-listener, jump, add-listener
     sequence, torrent controller first.
   - **Mutations outside `setState`** (`_shouldFocusOnLoad`,
     `_torrentViewModes.putIfAbsent`, `_folderPath.removeLast()`/`.clear()`,
     controller clears after an await) keep their placement.
7. **D-pad and focus:** the 10 focus nodes and their handlers (the arrow-key
   handler on `_torrentSearchFocusNode`), `TvSearchFocusHandoff`, focus
   fallback after loads, the post-frame focus requests, and toolbar and
   selection-bar traversal.
8. **Lifecycle:** `initState` and `dispose` stay verbatim, with
   receiver-only qualification: the analytics call, the two `late final`
   focus-node creations, the select-source pre-fill and the unawaited
   `_hiddenFromNav` load, `_loadApiKeyAndData`, the two listener adds, back
   registration, the 10-second timer, the post-frame poll, and the **16
   disposals** in order.
9. **Profile behaviour:** the screen reads `RealDebridStorage.getApiKey()`
   once and relies on the profile gate remounting it. Keep exactly that.
10. **Add, playlist, Debrify TV and copy actions.**
    - **Magnet add:** default selection (`getFileSelection()`) and advanced
      selection (`'smart'`, `'largest'`, `'video'`, `'all'`), including the
      cleanup DELETE after `TorrentNotCachedException` (4442, 4602).
    - **Link add:** `unrestrictLink` (4800), which creates a DDL entry.
    - **Playlists:** the four live `addPlaylistItemRaw` payloads (3817, 3841,
      6311, 6343). The two torrent actions omit `provider` (so storage
      defaults it to `realdebrid`) while the two node actions submit `rd`.
      These spellings, and `PlaylistStorage`'s enrichment (`addedAt`,
      credential re-reads, torrent-info fetches), stay unchanged.
    - **RAR torrents** (`_navigateIntoTorrent`, 1844–1990): the RAR dialog's
      Cancel and "Copy Download Link" (unrestrict, then copy, 1917), versus a
      normal folder open, which makes a second info GET through
      `getTorrentFolderTree` (`debrid_service.dart:1029`).
    - **TV add:** `addTorrentsToChannel(context, torrents:
      [fromRealDebridTorrent(t)], searchKeyword: _torrentSearchQuery)`.
    - **Clipboard:** the copy and auto-paste sites, including the unawaited
      magnet auto-paste and the awaited link auto-paste.

## Destination layout

`lib/features/debrid_downloads/`:
- **`application/`:** pure helpers with no services and no context, if the
  report confirms them: `_extractSeasonNumber`, `_extractLeadingNumber`,
  `_applySortedView`, `_applySeriesArrangedView`, `_detectSeriesPattern`,
  `_collectVideoFilesRecursively`, `_isValidMagnetLink`, `_isValidLink`,
  `_getUserFriendlyErrorMessage`, `_getLinkUnrestrictErrorMessage`. Anything
  that reads `widget`, `DateTime.now()` or State stays in a section; no
  parameter is added to make a helper pure.
- **`models/`:** `_RDSearchResult` and the two enums, made public.
- **Dormant code** moves to the bridge. Its **entry points**
  (`_handlePlayVideo`, `_buildSeriesFileBrowser`, `_copyDownloadLink`) stay
  private, so they keep their `unused_element` warnings. Internal dormant
  members that are called **across files** (for example `_buildModernFileCard`,
  called from `_buildEpisodesList`) get public names on their section class,
  through the manifest's rename mechanism, exactly like live members. Every
  such rename is listed in the manifest. Production stays unable to reach
  any of it. Changed diagnostic identities are recorded; nothing is
  suppressed, and no `part` files are used.
- **`presentation/legacy_debrid/`:** the bridge (exact path in the guard),
  holding the state owners, every section that takes a `BuildContext` or
  calls services, the dialogs and the builders.
- **`presentation/`, outside the bridge:** only widgets with no service
  imports.
- **The facade** (`lib/screens/debrid_downloads_screen.dart`) is registered as
  an exact composition root. Its 400-line cap and `TEMP(debrid)` rejection are
  turned on at step 7.
- **Guard rules,** added in step 1:
  - **No back-imports:** no file under `lib/features/debrid_downloads/` may
    import the facade. Callers elsewhere keep importing it.
  - **No cross-feature imports** between `debrid_downloads` and
    `torbox_downloads`.
  - **Bridge path:** the `presentation/legacy_debrid/` prefix is exact.
  - **Pure helpers:** `application/` files may not import services.
  - **Size caps:** 500 lines for destination files from step 1, 400 for the
    facade from step 7.

Each destination file is at most **500 lines**. `_buildModernFileCard` (432
lines) gets a file of its own.

## Technique

The same as the TorBox plan's Technique. The differences:
1. **No `didUpdateWidget`.** The lifecycle check covers `initState` and
   `dispose` only.
2. **Focus-node initialization stays where it is.** `_firstItemFocusNode`
   and `_torrentSearchFocusNode` are `late final` and assigned in `initState`
   (177 onward); those assignments stay in `initState`, verbatim.
   `_torrentSearchClearFocusNode` and the other nodes keep their
   initializers at the declaration, unchanged, on their new owner.
3. **Tear-off identity.** `_handleBackNavigation` is registered and
   unregistered by `==`. Whatever object owns it after the move, the
   registration and the teardown must use the same receiver.
   - **Checker work:** `lifecycle_tokens` (`check_settings_moves.py:780`)
     only validates owner classes, so two receivers of the same class
     normalize identically. Add a check of the **actual receiver paths** in
     the registration and teardown expressions, and a negative fixture that
     swaps between two instances of the same class.
   - **Behaviour:** a widget test (contract 1) checks that a pushed route's
     back handler is removed on dispose.
   - **Scroll listeners too.** `_onTorrentScroll` and `_onDownloadScroll` are
     added in `initState` (209) and removed and re-added by
     `_resetListScroll` (1818). All of those bindings move together in step
     3 (`_resetListScroll` moves with them, not with folder navigation in
     step 4), and the checker validates the resolved callback identity for
     both controllers, with negative fixtures for a receiver swap and for a
     wrapper closure. A widget test resets the list during a scroll and
     asserts that no paging request is made and that only one listener
     remains attached.
4. **Dormant code** is handled as described in Destination layout.
5. **The trailing-comma radius** at 5152–5154 (`BorderRadius.circular(\n 4,\n
   )`) must keep its trailing comma, so formatting can't collapse it into a
   24th counted bare radius. The shape count is checked after every
   formatting run.

## Steps

| # | Work | Notes |
| --- | --- | --- |
| 0 | Baseline, dependency report, manifest and checker config (`debrid_checker_config.json`), test accessor if needed, characterization tests and their baselines, source-text inventory, CI test list | Nothing moves. |
| 1 | Guard registration; enums, `_RDSearchResult` and pure helpers | |
| 2 | State and resource owners; the lifecycle stays verbatim | |
| 3 | Back navigation, key loading, fetching and paging (with `_resetListScroll`), row actions, all deletes, selection, feedback helpers | Contracts 1, 5 and 6. **Full-suite gate 1.** |
| 4 | Folder navigation, view modes, in-folder search, torrent search | Contracts 2, 6 and 7. |
| 5 | Torrent download, playlist and TV add, multi-file play, magnet and link add, folder-node actions, dormant cluster | Contracts 3, 4 and 10. |
| 6 | `build` forwarder and every builder | Contract 7. |
| 7 | Final State, guards, CI. **Full-suite gate 2.** | |

### Step 0

1. **Baseline:** `suite_evidence.py run debrid/base` and the whole-repo
   analyzer, at the step 0 starting commit. Flutter must be 3.44.8.
2. **Dependency report** (`docs/refactoring/debrid-downloads-deps.md`), as in
   the TorBox plan.
3. **Checker:** `dev/tool/debrid_manifest.tsv` and `debrid_checker_config.json`,
   as in the TorBox plan: wiring reviewed by hand against the dependency
   report before scaffolds are pinned; production scaffold and plain-section
   entries activated as their declarations exist (the root section and
   forwarder at step 6); the existing configs unchanged and still passing;
   positive and negative fixtures, including a `popRouteBackHandler` receiver
   swap.
4. **Characterization tests,** recorded against the original code, with
   `http.runWithClient` and a `MockClient` serving fixed Real-Debrid JSON.
   - **Harness prerequisite.** The existing picker test only seeds
     `SharedPreferences`, which isn't enough: startup awaits
     `ProfilePreferences.instance()`, which needs an initialized
     `ProfileRuntime` (`profile_preferences.dart:271`), and plaintext
     credentials trigger vault migration. The step 0 harness must
     initialize and reset the legacy runtime for ordinary fixtures,
     configure and reset the deterministic vault override, and use
     committed-profile fixtures for the profile tests. Build it first and
     prove it with one passing HTTP fixture before writing the matrix.

   | Contract | Coverage |
   | --- | --- |
   | 1 Navigation | Widget tests: tab versus pushed route (back handler registered and removed on dispose); one case per Real-Debrid back level as enumerated in contract 1, including that Back does **not** close the torrent search, the deep-linked root pop, the `returnToTorrentSearchOnBack` handoff with the flag cleared, the browse-root return, and `false` at the top; folder back goes up a level; RAR fixtures for Cancel and Copy Download Link (request order, clipboard text, no download enqueued) and the normal folder open's two info GETs; the `initialTorrentForOptions` deep link (the post-frame poll then folder open). Source guards on the 10-second pop's condition and on the exact registration and teardown expressions. |
   | 2 Select-source | Widget tests on a pushed route (extend `provider_source_picker_web_download_test.dart`): a torrent row from the list and from search results, and a DDL row. Assert the callback count, the pop, hash, id, `debridService`, the DDL row's `cloudSourceKind`, and that a non-playable DDL row is disabled. `boundAt` is a bounded timestamp. Also the pre-filled, auto-submitted torrent search, and the hidden toolbars. |
   | 3 Playback | Source guards on all six launcher sites and their arguments, plus **pending device verification**. Where a test accessor can expose argument-building code, assert it. |
   | 4 Downloads | Source guards on all four enqueue sites, their payloads and file naming. |
   | 5 Destructive | Widget tests with a MockClient log. **Single delete**, torrent and DDL: cancel makes no request; confirm makes one DELETE to the exact path. **Delete all**, torrent and DDL: an unfiltered paged fetch then sequential DELETEs in fetched order; cancellation during the fetch; cancellation with a request in flight (it finishes; no request after); a partial failure and its message. **Delete selected**: insertion order; full success, partial failure, and cancellation with a request in flight; the resulting rows, selection sets and selection mode. "No request after cancellation" means **no further DELETE**; the existing refresh GETs (for example delete-all's refetch, 1133) are asserted explicitly. Fake-time assertions on the 150 ms waits: delete-all waits after success only; delete-selected waits after success or failure unless cancellation is seen at the post-request check. |
   | 6 Lists | Widget tests: a paging request on scroll; the torrent-search fetch limits; Raw and A–Z order for a fixed folder; in-folder and torrent search filtering; empty and error states. **Series arrangement** and season/episode parsing through the test accessor, with a source guard on the dormant dropdown branches. Pixel goldens of the reachable views (torrent list, DDL list, folder, selection mode, select-source) on macOS and Linux; Linux captured from the original code on Ubuntu (the IPTV procedure). Torrent cards render relative dates from `DateTime.now()` (`_formatDate`, 6371), so fixtures use fixed UTC `added` values more than seven days old (the absolute-date branch); record that and the capture provenance. |
   | 7 D-pad | Widget tests: the `_torrentSearchFocusNode` arrow handler; focus on the first item after a load; the fallback to the search button. |
   | 8 Lifecycle | Source guards on the verbatim lifecycle, which the checker also enforces. An unmount test with a pending fetch on **normal startup** (no pre-filled query): no throw. |
   | 9 Profile | Widget tests: a profile-gate remount gives a fresh State with new owners; two independent routes don't share owners. |
   | 10 Add/playlist/TV/copy | HTTP fixtures for magnet add (default and advanced selection; the `TorrentNotCachedException` cleanup DELETE) and link add, asserting requests in order. **Playlists:** source guards pin the four submitted maps exactly; separately, real-action accessor tests assert the persisted entries, with fixed enrichment responses and bounded `addedAt`. Source guards on the TV handoff and the clipboard sites. Unexercised UI flows are recorded as **pending**. |

   - Record `debrid/base2` after any test seam (with a seam-only manual size
     raise if the facade grows), then `debrid/base3` after the tests. Compare
     each with the previous one: `PASS`, and every new characterization test
     passes.
5. **CI list:** add every affected test as a concrete path now, including
   `provider_source_picker_web_download_test.dart` and
   `home_source_editor_test.dart`, which aren't listed today.
6. **Source-text inventory:**
   - **Theme registry:** the `cloud` entry in
     `dev/tool/theme_surface_manifest.txt:5` names this file by exact path.
     Add the destinations.
   - **Shape manifest:** `kShapeResidue` allows **23 bare radii** for this
     file, and it has exactly 23, plus **23 `app.shape.br` calls**. Keep the
     trailing-comma radius uncounted (Technique 5). Distribute the 23-radius
     budget exactly across the destination owners:
     - **Files with tokens** go in `kShapeResidue`, so the sweep floor (488,
       `shape_manifest_test.dart:448`) still counts their tokens. Every file
       there must contain `app.shape.` (433).
     - **Files with radii but no tokens** go in `kExtractedShapeResidue`
       (151). That includes the modern-card file (9 counted radii, 0 tokens)
       and the final facade (0 tokens, residue 0), which has to leave
       `kShapeResidue`. `kExtractedShapeResidue` doesn't count towards the
       token floor.
     - **Every other destination file**, including models, deps records
       and owners with no radii or tokens, is registered in
       `kExtractedShapeResidue` with a zero budget, as in the IPTV plan. The
       guard only scans registered paths (409), so nothing may go
       unregistered.
   - **Size ratchet:** `dev/tool/file_size_baseline.txt:9`.
   - **`dev/tool/light_ink_inventory.py:64`:** a report tool; add the feature
     path to `PRIMARY`.
   - **Generic readers:** the theme and profile source guards, the
     stale-runtime guard and `check_storage_references.py`. Verify; no path
     rewrites.

   Grep for more. Each entry gets the step that ports it.

### Per step and gates

As in the TorBox plan, with `--relocate
lib/screens/debrid_downloads_screen.dart=lib/features/debrid_downloads/` for
the analyzer comparison, all four manifest runs (settings, IPTV, TorBox,
Real-Debrid) with self-tests, and gates against `debrid/base3`.

## Definition of done

1. **The facade** is at most 400 lines and formatted, holding
   `DebridDownloadsScreen` and the State with its verbatim lifecycle,
   forwarders and wiring. Every caller compiles unchanged.
2. **The guard** registers the feature, the exact bridge path, the facade as
   a composition root with its cap and `TEMP(debrid)` rejection, no import of
   the facade from any file under `lib/features/debrid_downloads/`, and no
   imports between `debrid_downloads` and `torbox_downloads`.
3. **Checks:** all four manifest runs pass with self-tests, and every
   characterization test passes unchanged.
4. **Analyzer and tests:** no new diagnostics and no suppressions (relocated
   ones correspond by rule, symbol and message); gate 2 passes against
   `debrid/base3` and gate 1.
5. **CI:** it passes on `private`; the test list holds the new tests; the
   allowlist gains nothing.
6. **Progress records:** the commits, the ownership, the exceptions with exit
   milestones, any seams, and what is pending device verification (D-pad on
   Android TV, playback handoff, real Real-Debrid account flows).
7. Stop after gate 2 and report.

## Explicitly not in scope

- Merging or sharing anything with TorBox.
- `DebridService`, `RealDebridStorage`, `DownloadService`, the player and
  launcher.
- Bug fixes and behaviour changes, including the items below.

## Progress

### Step 0 — complete; original-code checkpoint

- Starting revision ecea0f96; Flutter 3.44.8 / Dart 3.12.2. Untouched base: 10,411 success / 13 failure / 28 error / 20 skipped; analyzer 825 identities. Corrected accessor-only base2a matches base exactly. Preliminary base2 exposed a redundant foundation import; removed it before adopting base2a. No new failure accepted.
- Added the frozen actual-tear-off accessor only; no original method moves. Manual seam-only facade ratchet 6,445 → 6,590 (+145); exit at step 1. Inventory has all 173 leaves and all 53 fields, including both mid-file focus declarations. The deps report has a per-entry binding checklist before scaffolds are pinned.
- Harness first passed against original screen/accessor in detached ecea0f96 worktree. Tests exercise real HTTP/service paths, real delete confirmations, non-monotonic string IDs, fresh post-action state, exact 149+1 ms waits, all 16 disposals plus super, and sentinel route/tab registrations. Committed profile coverage uses the real ProfileGate without a GlobalKey, matching production remount semantics.
- Five macOS originals captured in the original worktree then compared exactly. January 2026 UTC fixture dates use the original absolute-date branch. Linux remains pending during steps 0–5; step 6 activates mandatory missing-original failure. The capture script resolves the unique step-0 commit by its exact subject because a commit cannot embed its own hash, then checks out that commit detached; no moved-code capture, SDK installation or push.
- The first full test baseline base3 has the 75 passing added identities; the analyzer exposed 37 new test-style brace diagnostics. Added braces only in test code, retaining every assertion, and re-proved all 97 affected identities in the original worktree. Final base4 is the gate baseline; no extraction has begun. Manifest CRLF normalized to LF and descriptive rd_search_result filename chosen before moves.
- Real-config fixtures cover wrong context, lifecycle order/move, callback rewiring, duplicate owners, root/forwarder/accessor rules, and callback receiver-path/member equality with same-class receiver-swap and wrapper negatives. Existing settings/IPTV/TorBox configs remain unchanged.
- Conservative decisions: retain every dormant entry and original guard, mutation, payload, delay and known defect; copy duplicate helpers only inside this feature; no Riverpod/data/localization redesign. Pending physical Android TV focus, six launcher handoffs and real-account download/add/playlist/TV checks. All original found-not-fixed items remain out of scope.


- Final base4: 10,486 success / 13 failure / 28 error / 20 skipped; PASS versus base2a (75 added successes) and base3 (no added identities). Analyzer 825, zero additions versus original. All 97 core affected identities pass in the original ecea0f96 worktree; all 125 expanded focused identities match base4 (124 success, one pre-existing theme source-guard failure). Original worktree/test fingerprints and tested trees are retained in suite_evidence env files; no input changed during these runs.
- All four manifest/self-test runs pass, including original-code real-config negative fixtures. Architecture, strict sizes, storage reference fixtures and all 314 storage constants pass. Five original macOS hashes recorded; Linux capture script syntax passes. A preliminary expanded run named a nonexistent runtime-guard path; corrected to test/profiles/isolation_suite/stale_runtime_guard_test.dart and reran successfully against the observed baseline. No assertion removed/weakened and no allowlist/golden regression acceptance.
- Concurrent user-owned CI-only commit 00bcf391 landed between base2 and base2a. Preserved unchanged; no application/test change. Base2a/base3/base4 record that HEAD and stable tested trees. Historical helper reports the same 32 failure/error identities missing from the nine-entry historical list, before extraction; observed-baseline identity comparisons establish parity.

## Found, not fixed

All pre-existing; the extraction keeps each exactly.
- **Startup auto-submit after dispose.** `_loadApiKeyAndData` calls
  `_submitTorrentSearch()` (431) after its awaits with no `mounted` check,
  which can reach `ScaffoldMessenger.of(context)` (574) and `setState` (587,
  591, 614).
- **RAR branch `setState`.** `_navigateIntoTorrent` calls `setState` at 1860
  after an await, before its `mounted` check at 1865.
- **`context` after `await`.** Many `_showSuccess`/`_showError` calls, the
  launcher pushes at 5920 and 6023, and `showDialog` at 4629.
- **Pops that may close the wrong route.** The catch blocks in `_playFile`,
  `_playFolder`, `_handlePlayMultiFileTorrent`, the delete-all outer catch, and
  the `rootNavigator` pops in the download flows.
- **Retry with no API key** throws a null-check error (3283, 3569).
- **Key-only tab unregistration** can remove a newer instance's handler
  (`main_page_bridge.dart:325–330`). TorBox has the same.
- **Delete all** removes torrents the list doesn't show (undownloaded ones).
- **Multi-file series play** launches at index 0 with an empty URL when the
  first episode isn't the first entry.
- **Dormant code** (~1,120 lines): `_handlePlayVideo`,
  `_buildSeriesFileBrowser`, `_copyDownloadLink`, and everything reached only
  from them; the unreachable Series Arrange mode.
