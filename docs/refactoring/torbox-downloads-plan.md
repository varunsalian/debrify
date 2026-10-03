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
temporary exceptions, each with an exit milestone in Progress, are:
- State-driven sections instead of Riverpod;
- a `legacy_torbox/` bridge folder that calls services directly;
- unchanged legacy text.

## Public surface (at `40212b6c`)

`TorboxDownloadsScreen({initialTorrentToOpen, isPushedRoute, initialSearchQuery,
selectSourceMode, onSourceSelected, ...})` keeps its exact signature and
defaults; step 0 re-derives the full parameter list. It is the only public
symbol. Callers construct it from:
- `main.dart`;
- `home_source_editor.dart`;
- `catalog_browser.dart`;
- `aggregated_search_results.dart`;
- `trakt_results_view.dart`;
- two deprecated home widgets;
- two tests: `provider_source_picker_web_download_test.dart` and
  `home_source_editor_test.dart`.

## What it contains (line numbers at `40212b6c`; the step 0 manifest is authoritative)

| Lines | Area | Notes |
| --- | --- | --- |
| 1–80 | Imports, widget, enums `_FolderViewMode`, `_TorboxDownloadsView` | |
| 81–200 | 58 State fields (some declared later) | 10 focus nodes, 6 text controllers, 2 scroll controllers |
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
2. **Select-source mode** (`selectSourceMode`, `onSourceSelected`,
   `initialSearchQuery`): the same `SeriesSource` passed back, the same
   pre-filled torrent search, the same focus.
3. **Playback handoff:** the same launcher calls and arguments (URLs,
   playlists, titles, series and episode metadata, resume identity) from
   torrents, web downloads, files and folders. No change to `VideoPlayerLauncher`
   usage.
4. **Downloads:** the same `DownloadService` and enqueue payloads (single,
   multiple, selected, ZIP), the same file naming, and the same TorBox API
   requests.
5. **Destructive actions:** every delete (single, all, selected, web download)
   keeps its confirmation dialog, wording, progress dialog and the API calls
   it makes, in order.
6. **Lists and views:** the same paging triggers (scroll thresholds), sorting,
   series arrangement (season and episode extraction, ordering), search
   matching, and empty and error states.
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

## Destination layout

`lib/features/torbox_downloads/`:
- **`application/`:** pure helpers with no services and no context, if the
  report confirms them: naming and title formatting, `_isLikelySeries`,
  `_detectSeriesPattern`, `_extractSeasonNumber`, `_extractLeadingNumber`,
  `_isValidMagnetLink`, `_formatTorboxError`, sorting and series-arrangement
  calculations.
- **`models/`:** the four private data classes, made public, if they are
  plain data.
- **`presentation/legacy_torbox/`:** the bridge (exact path in the guard),
  holding the state owners, every section that takes a `BuildContext` or
  calls services, the dialogs and sheets, and the builders.
- **`presentation/`, outside the bridge:** only widgets with no service
  imports.
- **The facade** (`lib/screens/torbox/torbox_downloads_screen.dart`) is
  registered as an exact composition root: a 400-line cap at the end,
  `TEMP(torbox)` rejection, and no feature file may import it.

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
   `check_settings_moves.py`.
   - The IPTV and settings configs stay unchanged and keep passing.
   - Add TorBox fixtures (positive and negative): lifecycle reordering, a
     builder-context swap, an own-`context`-parameter swap, wrong callback
     wiring, a duplicate owner.
4. **Characterization tests,** recorded against the original code. TorBox is
   reached through `TorboxService`'s HTTP calls, so use `http.runWithClient`
   with a `MockClient` serving fixed TorBox JSON, as earlier tests do.

   | Contract | Coverage |
   | --- | --- |
   | 1 Navigation | Widget tests: tab versus pushed route (back handler registered and unregistered, using the existing `MainPageBridge` hooks); folder back goes up a level; the `initialTorrentToOpen` flow. Source guard on the 10-second pop's condition. |
   | 2 Select-source | Widget test: `selectSourceMode` with `initialSearchQuery` pre-fills the torrent search; choosing a file calls `onSourceSelected` with the expected `SeriesSource` (extend `provider_source_picker_web_download_test.dart`). |
   | 3 Playback | Through the test accessor or a launcher spy if one can be injected without production change: the launch arguments for torrent, file, folder and web-download play. Otherwise source guards plus **pending device verification**. |
   | 4 Downloads | Source guards on enqueue payload construction and file naming; where `DownloadService` can be faked in tests today, assert the payloads. |
   | 5 Destructive | Widget tests: each delete shows its confirmation, cancelling makes no API call, confirming makes the expected DELETE requests, in order (MockClient log). |
   | 6 Lists | Widget tests: paging request on scroll; raw, A–Z and series-arranged order for a fixed folder (season and episode parsing); search filtering; empty and error states. Pixel goldens of the main views (torrents list, folder, series view, web downloads, selection mode) on macOS and Linux, Linux captured from the original code on Ubuntu (the IPTV procedure). |
   | 7 D-pad | Widget tests on the arrow-key handlers of `_firstItemFocusNode` and `_torrentSearchFocusNode`, and focus fallback after a load. |
   | 8 Lifecycle | Source guards on the verbatim lifecycle, which the checker also enforces; an unmount test with a pending fetch (no throw). |

   - Record `torbox/base2` after any test seam (with a seam-only manual size
     raise, as in the IPTV plan, if the facade grows), then `torbox/base3`
     after the tests.
   - Compare each with the previous one: `PASS`, and every new
     characterization test passes.
5. **CI list:** add every affected test as a concrete path now.
6. **Source-text inventory:**
   - `test/theme/shape_manifest_test.dart` (this file's radii);
   - `dev/tool/theme_rendered_set.py` and `measure_theme_surface.sh`, if they
     list it;
   - `dev/tool/file_size_baseline.txt`.

   Grep for more. Each entry gets the step that ports it.

### Per step and gates

As in the IPTV plan:
- **Move** verbatim, then format the new files.
- **Analyzer:** compare with
  `--relocate lib/screens/torbox/torbox_downloads_screen.dart=lib/features/torbox_downloads/`.
- **Checks:** `check_verbatim_moves.py --manifest dev/tool/torbox_manifest.tsv
  --self-test`, plus the settings and IPTV manifest runs, which must still
  pass; the architecture guard; `check_file_sizes.py --update`.
- **Tests:** the affected tests, compared with `torbox/base3`.
- **Commit.**

Gates use `suite_evidence.py run torbox/gateN` against `torbox/base3`.

## Definition of done

1. **The facade** is at most 400 lines and formatted, holding
   `TorboxDownloadsScreen` and the State with its verbatim lifecycle,
   forwarders and wiring. Every caller compiles unchanged.
2. **The guard** registers the feature, the exact bridge path, the facade as
   a composition root with its cap and `TEMP(torbox)` rejection, and no
   feature import of the facade.
3. **Checks:** all three manifest runs pass with self-tests, and every
   characterization test passes unchanged.
4. **Analyzer and tests:** no new diagnostics and no suppressions; gate 2
   passes against `torbox/base3` and gate 1.
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

(empty)

## Found, not fixed

(none yet)
