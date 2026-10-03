# TorBox downloads screen refactor — plan

Written 2026-10-03 on `refactor/codebase` at `40212b6c`. Follow
[AGENTS.md](../../AGENTS.md). Read `docs/refactoring/iptv-results-view-plan.md`
and `docs/refactoring/settings-screen-plan.md` first: this plan reuses their
technique, checker and staging, and only states what differs.

Work on the existing `refactor/codebase` branch. Commit after every step. Never
push to `origin`; push to `private` only if the goal says so. Gate commits must
contain `gate`.

## Goal

`lib/screens/torbox/torbox_downloads_screen.dart` is 7,070 lines: the TorBox
cloud library. It holds:
- the torrents and web-downloads lists, with paging;
- folder browsing (raw, A–Z sorted and series-arranged views);
- playback;
- downloads (single, multi-select, ZIP);
- playlist and Debrify TV add;
- link copying;
- adding magnets and web downloads;
- selection mode with bulk delete;
- two searches (torrent search, in-folder search);
- the select-source mode used by other screens.

Split it into a new feature, `lib/features/torbox_downloads/`, **moving code
verbatim**.
- **Unchanged:** the widget tree, keys, focus nodes, build order and the
  State's lifecycle.
- **Stays in `torbox_downloads_screen.dart`:** the public `TorboxDownloadsScreen`
  widget (same constructor and parameters) and its State. The State keeps a
  verbatim `initState`, `didUpdateWidget`, `dispose` and `build` forwarder,
  plus its section wiring.

The Real-Debrid screen (`debrid_downloads_screen.dart`) is next, with the same
template. Pulling out their shared parts is a **later, separate** behaviour-level
plan; this plan must not merge anything with Real-Debrid.

**Architectural status:** a bounded legacy-extraction stage, as before. The
temporary exceptions and their exit milestones (AGENTS.md: exceptions need an
exit milestone) are:
- **State-driven sections instead of Riverpod.** Exit: move the TorBox
  library state (lists, navigation, selection, search) into Riverpod
  notifiers in a later TorBox change.
- **A `legacy_torbox/` bridge folder that calls services directly.** Exit:
  put `TorboxService`, `TorboxTorrentControlService`, `DownloadService` and
  launcher calls behind TorBox data contracts, then dissolve the bridge.
- **Unchanged legacy text.** Exit: the app-wide localization migration.

## Public surface (at `40212b6c`)

`const TorboxDownloadsScreen({super.key, initialTorrentToOpen, isPushedRoute =
false, initialSearchQuery, selectSourceMode = false, onSourceSelected})` keeps
this exact signature and these defaults (the nullable parameters default to
null). It is the only public symbol. Callers construct it from:
- `main.dart`;
- `home_source_editor.dart`;
- `catalog_browser.dart`;
- `aggregated_search_results.dart`;
- `trakt_results_view.dart`;
- two deprecated home widgets (commented-out references only);
- two tests: `provider_source_picker_web_download_test.dart` and
  `home_source_editor_test.dart`.

## What it contains (line numbers at `40212b6c`; the step 0 manifest is authoritative)

| Lines | Area | Notes |
| --- | --- | --- |
| 1–80 | Imports, the top-level `_maybeBlur` helper (40), widget, enums `_FolderViewMode`, `_TorboxDownloadsView` | |
| 81–200 | All 57 State fields (56 instance fields plus `_limit`) | 10 focus nodes, 6 text controllers, 2 scroll controllers. Later declarations such as `_currentFiles`, `_filteredTorrentSearchResults`, `_currentItems` and `_isBrowsePush` are getters. Builders are spread through the areas below too. |
| 201–298, 1045–1081 | `initState`, `didUpdateWidget`, `dispose` | **Stay verbatim in the State** (Technique 2). |
| 299–1044 | Torrent actions | focus fallback, download all, playlist and Debrify TV add, copy links, more-options sheet (139), `_handlePlayTorrent` (205), delete confirmations |
| 1082–1325 | Back navigation, scroll paging, fetching | `_handleBackNavigation`, `_fetchTorrents`, `_fetchWebDownloads`, load more, refresh |
| 1326–2329 | Web downloads and selection | play, options dialog, ZIP, downloads, copy, playlist, delete; selection mode; bulk delete and its progress dialog; add-web-download dialog |
| 2330–3353 | TorBox file helpers and download options | naming, series detection, initial action, stream URL, file selection sheet (396), `_enqueueTorboxDownloads` (171), ZIP, download options dialog and card |
| 3354–4049 | File list views | raw, generic, movie, series (260), file card (249), empty state |
| 4050–4246 | Magnet add, settings | |
| 4247–5087 | File play, download and playlist | `_playTorboxFiles` (195), single and multiple downloads, link copying, snackbar |
| 5088–5333 | Navigation into torrent, web download and folder; navigate up | |
| 5334–5704 | Sort and series-arranged view modes; view-mode dropdown | |
| 5705–6110 | Torrent search and in-folder search | |
| 6111–7021 | `build` and every list, card, bar and toolbar builder | |
| 7022–7070 | Private data classes `_TorboxFileEntry`, `_TorboxEpisodeCandidate`, `_TorboxMoreOption`, `_TorboxSearchResult` | |

No single method is over 500 lines.

## Contracts that must not change

1. **Navigation and back handling.**
   - **Pushed route:** `MainPageBridge.pushRouteBackHandler`/`popRouteBackHandler`.
   - **Tab:** `registerTabBackHandler('torbox')`/`unregisterTabBackHandler`, and
     the TV content focus handler for tab 5.
   - **Folder back:** `_handleBackNavigation` goes up a folder level before
     leaving.
   - **The 10-second "failed to open" pop** for `initialTorrentToOpen` keeps
     its condition and timing.
   - **Back priority** (1082–1123): source-picker pop, then exit selection,
     then close torrent search, then close folder search, then go up a
     folder. At a torrent root, a deep-linked open pops while ordinary
     browsing returns to the list, and `returnToTorrentSearchOnBack` hands
     back to the legacy search tab and clears its flag.
2. **Select-source mode** (`selectSourceMode`, `onSourceSelected`,
   `initialSearchQuery`): the same `SeriesSource` passed back, the same
   pre-filled torrent search, the same focus.
3. **Playback handoff:** the same launcher calls and arguments (URLs,
   playlists, titles, series and episode metadata, resume identity) from
   torrents, web downloads, files and folders, across all **seven launcher
   call sites**. No change to `VideoPlayerLauncher` usage. Inline evaluations
   such as `mounted ? context : null` stay inline, evaluated at the same
   moment.
4. **Downloads:** the same `DownloadService` and enqueue payloads (single,
   multiple, selected, ZIP) at all **seven enqueue sites** (1614, 1735, 2999, 3137, 4518, 4743, 4847), the same file
   naming, and the same TorBox API requests.
5. **Destructive actions:** every delete (single, all, selected, web download)
   keeps its confirmation dialog, wording, progress dialog and the API calls
   it makes, in order.
   - **Torrent deletion** is a **POST** through `TorboxTorrentControlService`
     (`torbox_torrent_control_service.dart:14`), with `operation: delete`,
     `all`, and an optional **string** `torrent_id`.
   - **Web-download deletion** is a **POST** with an **integer** `webdl_id`
     (`torbox_service.dart:744`).
   - **Bulk delete** (2078–2110) works through the selection in insertion
     order, sequentially, with a 150 ms wait between requests. It checks for
     cancellation before and after each request; cancelling lets an
     in-flight request finish.
     - **Completion** clears the selection.
     - **Cancellation** removes the IDs already deleted but keeps selection
       mode.
     - **Partial failure** keeps its current handling.
6. **Lists and views:** the same paging triggers (scroll thresholds), sorting,
   series arrangement (season and episode extraction, ordering), search
   matching, and empty and error states.
   - **The view-mode dropdown** offers only Raw and A–Z (5688). Series
     Arrange is unreachable through it, and the series selection sheet
     `_showTorboxFileSelectionSheet` (2503) has no callers. Both move
     verbatim as dormant code; neither is made reachable here.
   - **`_resetListScroll`** keeps its detach-listener, jump, reattach
     sequence (5254).
   - **Embedded mutations:** builders that mutate state (for example 6647)
     keep doing so at the same point.
   - **Download override:** `_currentTorrent`'s temporary override and
     restoration around downloads (343) stays exactly as it is.
7. **D-pad and focus:** the 10 focus nodes and their key handlers (for
   example the arrow-up/down handling on `_firstItemFocusNode` and
   `_torrentSearchFocusNode`), focus fallback after loads and deletes, and the
   toolbar and selection-bar traversal.
8. **Lifecycle:** `initState`, `didUpdateWidget` and `dispose` stay verbatim,
   with receiver-only qualification. That keeps the order of listener adds,
   back-handler registration and the 18 disposals.
9. **Profile behaviour:** the screen reads `TorboxStorage.getTorboxApiKey()`
   and relies on the profile gate remounting it. Keep exactly that; add no
   scoping and remove none.
10. **Add, playlist and Debrify TV actions.**
    - **Playlists:** the same entries are persisted, distinguishing
      `torbox` from `torbox_webdl` and single from collection, with
      file-ID order kept (405, 1827, 4588).
    - **TV add:** passes the converted torrent and the current search query
      (449).
    - **Web-download creation:** reads its three controllers and refreshes
      web downloads.
    - **Magnet creation:** passes its three flags and calls the
      view-dependent `_refresh` (2289, 4185).

## Destination layout

`lib/features/torbox_downloads/`:
- **`application/`:** pure helpers with no services and no context, if the
  report confirms them: naming and title formatting, `_isLikelySeries`,
  `_detectSeriesPattern`, `_extractSeasonNumber`, `_extractLeadingNumber`,
  `_isValidMagnetLink`, `_formatTorboxError`, sorting and series-arrangement
  calculations.
- **`models/`:** `_TorboxFileEntry`, `_TorboxEpisodeCandidate` and
  `_TorboxSearchResult`, made public, if the report confirms they are plain
  data. `_TorboxMoreOption` carries `IconData` and an action callback (7048),
  so it goes to presentation.
- **`presentation/legacy_torbox/`:** the bridge (exact path in the guard),
  holding the state owners, every section that takes a `BuildContext` or
  calls services, the dialogs and sheets, and the builders.
- **`presentation/`, outside the bridge:** only widgets with no service
  imports.
- **The facade** (`lib/screens/torbox/torbox_downloads_screen.dart`) is
  registered as an exact composition root. It gets a 400-line cap and
  `TEMP(torbox)` rejection, both turned on at step 7 (staged as in the IPTV
  plan).
- **Guard rules,** added in step 1:
  - **No back-imports:** no file under `lib/features/torbox_downloads/` may
    import the facade, the same rule as for IPTV. Callers elsewhere, such as
    `lib/features/home/presentation/home_source_editor.dart:9`, keep importing
    it.
  - **Bridge path:** the `presentation/legacy_torbox/` prefix is exact.
  - **Pure helpers:** `application/` files may not import services (the IPTV
    rule at `check_search_architecture.py:380`, extended to TorBox).
  - **Size caps:** 500 lines for destination files from step 1, 400 for the
    facade from step 7.

Each destination file is at most **500 lines**.

## Technique

The same as the IPTV plan's Technique, with these points:
1. **Sections** are plain classes the State constructs, with narrow deps
   records:
   - `setState`, `mounted` and `context` as callbacks;
   - widget values as live getters (`() => widget.selectSourceMode`, ...);
   - deferred calls into members that haven't moved yet.

   Never pass the facade's concrete widget type into extracted code.
2. **The lifecycle stays verbatim** (contract 8): the same statements in the
   same order; only receivers on moved fields are qualified. No owner gets a
   combined `dispose()`.
3. **One owner per field,** with the same initializer. Controllers and focus
   nodes keep their identity: they're created once and listened to the same
   way.
4. **`mounted`/`context`, builder contexts, the pre-approved patterns, the
   allowed edits, the not-allowed list and the temporary cross-calls** are as
   in the IPTV plan.
   - The checker's builder-context and own-`context`-parameter rules apply.
   - The facade's `build` may become a one-line forwarder to a plain
     (non-widget) section, exactly as approved for IPTV (`IptvRootLayout`).
     The checker must verify it's the single forwarding expression and that
     the section isn't a widget.

## Steps

| # | Work | Notes |
| --- | --- | --- |
| 0 | Baseline, dependency report, manifest and checker config (`torbox_checker_config.json`), test accessor if needed, characterization tests and their baselines, source-text inventory, CI test list | Nothing moves. |
| 1 | Guard registration; data classes, enums and pure helpers | |
| 2 | State and resource owners; the lifecycle stays verbatim | |
| 3 | Fetching, paging, back navigation, torrent actions, web downloads and selection | Contracts 1, 5 and 6. **Full-suite gate 1.** |
| 4 | File helpers, download options, file play, download and playlist, magnet add | Contracts 3 and 4. |
| 5 | Navigation into folders, view modes, both searches | Contracts 2, 6 and 7. |
| 6 | `build` forwarder and every builder (lists, cards, bars, toolbar) | Contract 7. |
| 7 | Final State, guards, CI. **Full-suite gate 2.** | |

### Step 0

1. **Baseline** at `40212b6c`: `suite_evidence.py run torbox/base` and the
   whole-repo analyzer. Flutter must be 3.44.8.
2. **Dependency report** (`docs/refactoring/torbox-downloads-deps.md`), as in
   the IPTV plan. It covers every declaration's destination, step and layer;
   reads and writes, including in-place collection mutation; cross-section
   calls, tear-offs, deferred closures and listeners; each temporary
   cross-call's final destination; and the contract each one touches.
3. **Checker:** add `dev/tool/torbox_manifest.tsv` and
   `torbox_checker_config.json`, using the manifest-driven
   `check_settings_moves.py`. `check_verbatim_moves.py:355` already picks up a
   third config. The config needs TorBox's own lifecycle and receiver
   ownership rules, live getters, scaffolding, accessor, plain root section,
   forwarder rules and exact annotation removals.
   - **Wiring review first:** before scaffolds are pinned, check every
     wiring entry by hand against the dependency report. The checker only
     compares wiring with the recorded scaffolds, so wiring that's wrong when
     recorded would be accepted. Give particular attention to same-signature
     fetch callbacks and the listener and back-handler tear-offs.
   - The IPTV and settings configs stay unchanged and keep passing.
   - **Activation:** production scaffold and plain-section entries become
     active as their declarations come into existence. The shared checker
     validates `plain_sections` unconditionally (`check_settings_moves.py:821`)
     and rejects an absent registered root (710), so the root section entry
     and the forwarding specification are activated in step 6, not step 0.
     Step 0 tests those rules only through fixtures.
   - Add TorBox fixtures (positive and negative): lifecycle reordering, a
     builder-context swap, an own-`context`-parameter swap, wrong callback
     wiring, a duplicate owner.
4. **Characterization tests,** recorded against the original code. TorBox is
   reached through `TorboxService`'s HTTP calls, so use `http.runWithClient`
   with a `MockClient` serving fixed TorBox JSON, as earlier tests do.

   | Contract | Coverage |
   | --- | --- |
   | 1 Navigation | Widget tests: tab versus pushed route (back handler registered and unregistered, using the existing `MainPageBridge` hooks); folder back goes up a level; the `initialTorrentToOpen` flow. Source guards on the 10-second pop's condition and on the exact registration order. **Back priority:** one case per level of the order above (picker, selection, torrent search, folder search, folder up); deep-linked root pop versus browse-root return; the `returnToTorrentSearchOnBack` handoff and the flag cleared afterwards. |
   | 2 Select-source | Widget tests on a pushed route (extend `provider_source_picker_web_download_test.dart`) for the two selection paths: **torrent rows** (6474) and **web-download rows** (6392). File rows play (6618). Assert the callback count, the route pop, identity and hash, the web download's `cloudSourceKind`, and that a web row with no playable files is disabled. Treat `boundAt` as a bounded timestamp; no clock seam. Also assert that `initialSearchQuery` pre-fills the torrent search. |
   | 3 Playback | `VideoPlayerLauncher` is static and can't be spied without a production change, so: **source guards on all seven launcher call sites** and their arguments, plus **pending device verification**. Where a test accessor can expose argument-building code as real tear-offs, assert it too. |
   | 4 Downloads | `DownloadService` is a fixed singleton, so: **source guards on all seven enqueue sites**, payload construction and file naming. Assert payloads only where the existing test infrastructure can observe them. |
   | 5 Destructive | Widget tests with a MockClient log. **Confirmation:** cancelling the dialog makes no request; confirming makes the exact POST control requests above (operation, `all`, string `torrent_id`; integer `webdl_id`). **Bulk delete, for torrents and web downloads:** full success; partial failure; cancellation while a request is in flight. Assert insertion-order processing, no request after cancellation, remaining rows and selection, and that the dialog closes. |
   | 6 Lists | Widget tests: paging request on scroll; Raw and A–Z order for a fixed folder; search filtering; empty and error states. **Series arrangement** and season/episode parsing are tested through the registered test accessor (the UI can't reach them), with a source guard on the dormant dropdown and sheet branches. Pixel goldens of the reachable views (torrents list, folder, web downloads, selection mode) on macOS and Linux, Linux captured from the original code on Ubuntu (the IPTV procedure), with HTTP fixtures and fixed animation capture points. |
   | 7 D-pad | Widget tests on the arrow-key handlers of `_firstItemFocusNode` and `_torrentSearchFocusNode`, and focus fallback after a load. |
   | 8 Lifecycle | Source guards on the verbatim lifecycle, which the checker also enforces. An unmount test with a pending fetch on **normal startup** (no pre-filled query): no throw. The pre-filled-query startup can call `setState` after dispose (see "Found, not fixed"), so it isn't asserted, and the extraction keeps its existing guards exactly. |
   | 9 Profile | Widget tests: a profile-gate remount gives a fresh State whose owners are new, so the incoming credentials and lists replace the outgoing ones; two independent routes don't share owners. No new profile semantics. |
   | 10 Add/playlist/TV | **Add:** HTTP fixtures for web-download and magnet creation (success, failure, cancel), asserting the requests and which refresh runs. **Playlists:** real-action accessor tests observing persistence through `playlist_storage.dart:20` (provider kind, single versus collection, file-ID order). **TV handoff:** source guards on the arguments. UI flows not exercised are recorded as **pending**. |

   - Record `torbox/base2` after any test seam (with a seam-only manual size
     raise, as in the IPTV plan, if the facade grows), then `torbox/base3`
     after the tests.
   - Compare each with the previous one: `PASS`, and every new
     characterization test passes.
5. **CI list:** add every affected test as a concrete path now.
6. **Source-text inventory:**
   - **Theme registry:** the `cloud` entry in
     `dev/tool/theme_surface_manifest.txt:5`, read by `measure_theme_surface.sh`
     and `theme_rendered_set.py`. Expand its patterns to cover the
     destinations.
   - **Shape manifest:** `test/theme/shape_manifest_test.dart` records **14
     bare radii** for this file, and the file has **23 shape-token calls**.
     Keep all 14 radii, and register the token-bearing owners in
     `kShapeResidue` so the token floor (488, `shape_manifest_test.dart:448`) still counts them.
   - **Generic readers:** the theme source guards, the profile source
     guards, the storage-reference checks and the size ratchet
     (`dev/tool/file_size_baseline.txt`). These scan the repo, so they need
     verification, not path rewrites.

   Grep for more. Each entry gets the step that ports it.

### Per step and gates

As in the IPTV plan:
- **Move** verbatim, then format the new files.
- **Analyzer:** compare with
  `--relocate lib/screens/torbox/torbox_downloads_screen.dart=lib/features/torbox_downloads/`.
- **Checks:** `check_verbatim_moves.py --manifest dev/tool/torbox_manifest.tsv
  --self-test`, plus the settings and IPTV manifest runs, which must still
  pass; the architecture guard; `check_file_sizes.py --update`.
- **Tests:** the affected tests, compared with `torbox/base4`.
- **Commit.**

Gates use `suite_evidence.py run torbox/gateN` against `torbox/base4`.

## Definition of done

1. **The facade** is at most 400 lines and formatted, holding
   `TorboxDownloadsScreen` and the State with its verbatim lifecycle,
   forwarders and wiring. Every caller compiles unchanged.
2. **The guard** registers the feature, the exact bridge path, the facade as
   a composition root with its cap and `TEMP(torbox)` rejection, and no
   import of the facade from any file under `lib/features/torbox_downloads/`
   (other callers, such as `home_source_editor.dart`, keep importing it).
3. **Checks:** all three manifest runs pass with self-tests, and every
   characterization test passes unchanged.
4. **Analyzer and tests:** no new diagnostics and no suppressions; gate 2
   passes against `torbox/base4` and gate 1.
5. **CI:** it passes on `private`; the test list holds the new tests; the
   allowlist gains nothing.
6. **Progress records:** the commits, the ownership, the exceptions with exit
   milestones, any seams, and what is pending device verification (D-pad on
   Android TV, playback handoff, real TorBox account flows).
7. Stop after gate 2 and report.

## Explicitly not in scope

- `debrid_downloads_screen.dart` and any merging with it.
- `TorboxService`, `DownloadService`, the player and launcher.
- Bug fixes and behaviour changes. Record any bug you find under "Found, not
  fixed".

## Progress

### Step 0 — complete

- Execution starts at requested `191ab849` on `refactor/codebase`; the original screen is unchanged from the plan's `40212b6c`. Flutter 3.44.8 / Dart 3.12.2.
- `torbox/base` and seam-only `torbox/base2`: 10,351 successes, 13 failures, 28 errors, 20 skips. Identity comparison PASS (`base2-comparison.txt`). Evidence lives in `.git/refactor-evidence/torbox/` and streams runner output throughout long commands.
- Registered original-code accessor exposes actual action tear-offs, collection/resource identities and snapshots on each invocation. No clock, service or widget-signature change. Seam-only facade ratchet raise: 7,070 → 7177 lines, by hand; exit in step 1. No extraction preceded characterization.
- 51 new characterization tests plus the three existing source-picker tests pass on original code (`characterization-original-verified.jsonl`, strict identity comparison PASS against `base3`). Four macOS goldens captured only from original code, then compared strictly. Linux originals **pending** user-run Ubuntu capture; no workflow or remote push. Linux golden tests explicitly report pending when originals are absent.
- Decision: preserve the observed folder-search null-root behavior and test it; accessor fixture additionally populates the existing borrowed navigation stack to characterize actual matching. No production fix. Lifecycle has 18 resource disposals plus `super.dispose()` (19 dispose invocations).
- Pending device verification: all seven native playback handoffs, Android TV D-pad, real TorBox account download/delete/add/TV flows. TV UI handoff is source-guarded; unexercised device/UI paths remain pending.
- `torbox/base3`: 10,402 successes, the same 13 failures / 28 errors / 20 skips, 51 added test identities; PASS against `base2`. Every new test passes. Final original-code source tests include complete playback/download argument-building bodies as well as all 14 call expressions.
- Final analyzer: 830 diagnostics, zero added; accessor removes two unused-method warnings. All three manifest/self-test runs, architecture, size, storage reference/key, format and diff checks pass. IPTV/settings configs remain unchanged.
- No push or remote CI is authorized; local CI-equivalent checks replace the plan's private-push requirement. Remote CI remains pending.

### Step 0b — complete

- Interrupted step-1 work preserved in stash `2f515213a5d78b466be8c89eee8bfae5e8cdfa4a`; no extraction is included in step 0b. Revised tests first execute in detached original-code worktree `/private/tmp/debrify-torbox-original-c4f5375a` at `c4f5375a`, with the screen and frozen accessor unchanged.
- Step change: `_resetListScroll` moves with **both** scroll listeners and paging in step 3, not step 5. Resolved callback checks run before receiver normalization and compare receiver path plus member, rejecting closure wrappers and same-class instance swaps for scroll, route back and TV tab-5 focus. Tab-back teardown remains the original key-only unregister; its registration shares the route-back tear-off.
- TorBox fixtures now use the real production configuration and declarations; fixture overrides contain paths only. The deps report contains a review checklist for every wiring entry; review actual bindings before each scaffold pin.
- Base3 predates the final edits to the two playback/download source guards. Base4 records their complete bodies and all step-0b changes against original code; later affected tests and full gates use base4. Final reports also compare gates transitively with base3.
- Linux originals are a **blocking prerequisite before step 6**. `minttest` exists but has no Flutter SDK in PATH or under `/home`, `/opt`, `/usr/local`; no SDK installed. On an Ubuntu checkout containing this commit and existing Flutter 3.44.8, run `bash dev/tool/capture_torbox_linux_goldens.sh`. It creates a detached c4f5375a worktree, copies reviewed tests only, captures four originals, compares them strictly, copies PNGs back, and writes revision/hash/capture/strict evidence under the common git evidence directory. Commit those four PNGs and retain the evidence; never update against moved code. No push is authorized. Stop before step 6 with `BLOCKED: Linux goldens` if the files/evidence remain absent.
- Conservative test choice: stage the outgoing scroll position at bottom with `correctPixels` to isolate reset-generated notifications from a legitimate page scroll. Assert no offset=50 during reset, then exactly one offset=50 and offset=100 request on separate real scrolls. The identity checker verifies the single init add plus balanced reset remove/add for each controller; behavior verifies the retained attached listener and page counts.
- Removing the frozen test accessor later will re-surface the original unused-element warnings for dormant `_handleAddWebDownloadToPlaylist` and `_findFirstEpisodeIndex`. Match those by rule/symbol/message; removal is outside this move-only plan and the accessor is retained here.

- Original-code final `torbox/base4`: 10,411 successes, unchanged 13 failures / 28 errors / 20 skips. PASS against base3: exactly nine added identities, no failures, missing tests or newly skipped tests (`base4-comparison.txt`). All 63 affected identities pass, including four strict macOS goldens. Original code/accessor is byte-unchanged; hashes recorded in `step0b-original-sha256.txt`.
- Revised coverage verifies route/tab isolation and sentinel teardown, both-view bulk confirmation/cancel/confirm and 149+1 ms waits, magnet refresh from Web Downloads, fresh route snapshots, non-monotonic playlist IDs, magnet flag values, every resource disposal in order, empty-folder/pre-load focus, widget-update initial opens and the complete temporary torrent override body.
- Analyzer: 830 identities, zero added/removed (`step0b-analyzer-comparison.txt`). TorBox real-config/identity fixtures, settings/IPTV manifest self-tests, architecture, size, storage reference/key, format and diff checks pass. Evidence streams to the common evidence dir; no known-failure list or golden updated to accept a regression.

### Step 1 — complete

- Step 0b committed as `6267a505` (step 0: `c4f5375a`). Restored interrupted step-1 work from the preserved stash; resolved its checker-module conflict by retaining the real-config fixtures and equivalent accessor-wrapper/wrong-member negative checks added in step 0b.
- Registered exact TorBox feature/bridge boundaries and 500-line destination caps. Moved three pure helper concerns, plain models, enums, the blur helper and presentation option model; all production callers use their moved declarations. Facade 7,177 → 6,795 lines, with all remaining workflows and resources temporarily retained until their scheduled extraction steps.
- 195 original leaves plus every real-config/callback-identity/accessor fixture pass (`step1-verbatim-base4.txt`); settings/IPTV manifest self-tests pass unchanged. Shape inventory retains 14 bare radii / 23 token calls; theme registry includes feature destinations. No scaffolds are pinned at this step.
- Whole analyzer: 829 identities, zero added; one former private-option unused-parameter warning disappears when its class becomes public (`step1-analyzer-comparison-base4.txt`). All 79 affected tests pass against base4 (`step1-test-comparison-base4.txt`), including all 63 characterization/source-picker tests unchanged and four strict macOS goldens.
- Architecture, lowering-only size ratchet, format and diff checks pass. Linux originals remain pending and block step 6. No push.

## Found, not fixed

- **Startup `setState` after dispose.** With a pre-filled
  `initialSearchQuery`, `_loadApiKeyAndTorrents` awaits both initial fetches
  and then calls `_submitTorrentSearch` with no further `mounted` check
  (1175). That can call `setState` after the screen is disposed (5762).
  Pre-existing; the extraction keeps it exactly. Fix it in a separate change.
- **Dormant code.** `_showTorboxFileSelectionSheet` (2503) has no callers,
  and the dropdown can't select Series Arrange (5688). Pre-existing; moved
  verbatim.

- **Folder search null root.** Ordinary navigation pushes a root record whose node is null. `_performSearch` reads that first record and returns no results. Original behavior preserved; test fixture also covers matching with a populated original stack.
