# Refactor notes

## Whole-player inventory decision rules — September 7

The current inventory covers fixed main `bde119f5b7d908341656075953ee39c8454eed3c`, file `lib/screens/video_player_screen.dart`, 11,034 physical lines, SHA256 `66f8013e16e9283c47fa8e25df53ab7c7af392e4284a12d11d84e16538217822`. All new player moves wait for the whole-file inventory and the orchestrator's consolidated decisions. Existing reviewed transition PR #244 continues separately; its expected 139-line reduction is not counted until merged.

Every region receives a disposition, including code retained in the host. Candidate assessment must identify one responsibility, actual state writers/readers, live versus snapshot inputs, lifetime and notification ordering, and existing tests that enter the real origin. Host-line reduction, destination size and added binding code are separate numbers; nested declarations are not additive line credit. Syntax references identify places to inspect, not proof of semantic ownership.

Do not create a generic interface that exposes the screen's state merely to move code. A prerequisite is a concrete ownership decision or missing origin proof, not an indefinite hold. Necessary Flutter lifecycle and rendering bindings may remain in the host. Rejected small sleep/configuration moves are not retried solely to reduce line counts. The ordered roadmap must disclose any portion of the 9,500-line target not covered by credible candidates.

Quirks discovered during lanes. **Keep them**; do not "fix" in a refactor commit.
The orchestrator (or a later dedicated bugfix) owns follow-up.

See `dev/design/REFACTOR_PLAN.md` §2 rule 1.
Phase 2 extractions also follow `dev/design/REFACTOR_PLAN_PHASE2.md` (binding as of #72).

## Phase 2 correction

- **Old G1 steps 1–5 / remaining G3 / G5 follow-ups are not the template.** Wrappers,
  `extension on _SearchScreenState` parts, and pins against the copy do not count.
  New units must compile without the god file's private members (gate g).
- **`refactor/g3-player-prefs` is parked.** Pin+move already exist on that branch
  under the old G3 contract. PlayerPrefs is **S2-3** (with `iptv_prefs`) after
  S2-0…S2-2. Do not merge the parked branch.
- **Gate (h) evidence.** A pin must exercise lib code on the origin path: a widget
  test driving the State, or a test calling the origin function. `File(...).readAsStringSync()`
  greps and test-local re-implementations of the moved body do **not** count.
- **Leaves shortfalls are not "Decisions needed: None".** Record the miss here
  with the slice that clears it, or reject the PR. See the Leaves shortfalls table.

### Gate 2 · layering regression (blocking)

`tool/check_layering.dart`: **77** at #72 → **99** pre-#95 → **106** after
#95/#98 → **90** after **#100** (V1-fix). Ceiling is **90**.
`--strict` remains Q1. Remaining service offender in the six-file class:
`channel_import_export.dart` (M1-2, 7). #96 path-moved both CW units to
`lib/screens/search/` so the count stays 90.

| File | Lane | After #100 |
|---|---|---|
| `subtitle_track_controller.dart` | V1-3 | moved to `lib/screens/video_player/` |
| `iptv_zap_controller.dart` | V1-5 | moved to `lib/screens/video_player/` |
| `resume_controller.dart` | V1-1 | moved to `lib/screens/video_player/` |
| `keyword_search_controller.dart` | G1'-3 | moved to `lib/screens/search/` |
| `catalog_play_resolver.dart` / `iptv_recording_controller.dart` | G1'-1 / V1-4 | stayed (`foundation` only) |
| `channel_import_export.dart` | M1-2 | still in services (7); out of V1-fix |

`ProfileScope.fileIn` now POSIX-normalizes the relative path so Windows
`..\escape` is rejected the same way Linux already rejected `../escape`.
Keep: Linux behaviour; the old Windows miss was a hole, not a product quirk.

### #90 · parent-path pin still unpaid

`#90` pin is text-grep + test-local re-implementations and was edited after the
move. **#98** is a post-move widget pin of `KeywordSearchScreen` — it cannot pass
on the parent of the G1'-3 move, so it does **not** clear gate (h). Follow-up:
a widget test that is green on that parent commit, then rebase the pin so the
move commit does not touch it.

### #86 · Leaves shortfall + façade forwarders (Decisions)

**#86** (S2-3) Leaves **1 067 vs 1 600** (shortfall **533**). Clearing slice:
**S2-7** façade collapse. Forwarders left in `StorageService` are **>10 lines**
and needed a Decisions entry on the PR before merge (PHASE2 §2.2). Recorded
here after the fact: S2-7 deletes them; Q2 may `@Deprecated` the names until
then. Same class of debt on S2-1 (869) and S2-2 (325) — also S2-7.

## Quirks kept, not fixed

### H1 · Home row registry

- **Rail de-dup.** `_canonicalCanvasRails` now keys rails by row id (`railsById`)
  instead of appending. Duplicate live ids collapse to one rail. Pre-H1 the list
  could theoretically carry two `_CanvasRail`s with the same `_sectionRowId`.
  Keep: a duplicated id is a data bug, not a feature.
- **Wider stray leaves.** `HomeRowRegistry.buildManagerModel` materializes
  enabled extra rows that no family resolved (outage / vanished list) as
  `unavailable` leaves, so a save cannot silently drop them. Pre-H1 only some
  prefixes got this treatment. Keep: it is strictly more conservative.
- **Addon-group merge by name.** Families that share `groupName` (Trakt CW +
  Trakt lists, Simkl CW + Simkl lists, MDBList CW + MDBList lists) merge into
  one manager group. Pre-H1 the manager had separate rails per builder. Keep:
  the manager was always grouped by provider label; the registry made that
  rule uniform.

### T1 · transfer category registry

- **Tracking-prefs apply/send order.** Apply/send now follows
  `TransferCategoryRegistry` iteration, not the old hand-written switch order.
  Payload keys and `ConfigCommand` strings are unchanged. Keep: order is not a
  compatibility surface.
- **Tile icon / colour.** Remote tiles take `TransferCategory.icon` / `.color`.
  A few categories do not match the pre-T1 `_iconFor` / `_colorFor` switch
  pixel-for-pixel. Keep: visual, not wire.
- **Label case.** Registry `label` / `summarizeLabel` is the display string
  (e.g. `PikPak`). Pre-T1 onboarding `_configLabel` had mixed case. Keep:
  not a persisted string.
- **JSON key order.** `jsonEncode` of registry-built maps may emit keys in a
  different order than the old literal maps. Keys themselves are frozen. Keep.
- **`BackupSelection.all()` is non-const.** It now derives from the registry
  (`Set<TransferCategory>`). Call sites that needed a const value still use
  the named constructor. Keep: required for fake-category tests.
- **Double-apply fix.** Profile restore used to apply default-on categories
  twice (named constructor defaults plus an explicit set). T1 made coordinator
  sets explicit so default-on categories are not applied twice. Keep: this was
  a latent bug; do not restore double-apply.

### P2a · Magic TV strings

- **`MagicTvDispatch` is a screen façade**, not a new cloud capability. It
  lives in `magic_tv_screen.dart` and routes string switches through
  `CloudProviderRegistry` / `is` checks. Follow-up should not move it into
  `lib/services/cloud/` from a P2 lane (cloud is P1-owned).
- **Next-channel allowlists are a moved table.** The Real-Debrid / TorBox / …
  allowlists that decide which providers may auto-advance were lifted into
  the dispatch table, not redesigned. Keep the membership identical.

### T2 · tracker commons

- **Local progress is not dedicated.** `WatchProgressSource.local` has
  `isDedicatedProgress: false`, so `TrackingSourcePolicy.load` still returns
  null for local (same as the old `_ => null` arm). Keep: local never had a
  dedicated tracker credential.
- **MDBList adapter ignores `inferredType`.** The new
  `TrackerItemTransformer` method on MDBList does not use `inferredType`.
  Keep: origin transformer behaviour; do not "fix" in a follow-up that is
  not a dedicated bugfix.
- **Out-of-lane callers not chased.** `search_screen.dart` still wires CW
  rows by family singleton; calendar / tracking settings / player scrobble
  still switch. G1 / G5 own those files.

### G5 · scrobble coordinator

- **Simkl is pause-centric.** No POST to `/scrobble/start`. `'start'` and
  `'pause'` both call `scrobblePause`. Heartbeat force-sends pause and leaves
  the local marker `'start'`. Keep: origin Simkl machine.
- **Incomplete series season/episode skips Simkl only.** Trakt still sends
  (latent gap). Keep: pinned in `test/scrobble_video_player_machines_pin_test.dart`.
- **`_traktSeasonEpisode` stays on the player** (skip-segments / resume /
  guide). No TrackerRegistry scrobble factory this phase. Native TV / launcher
  paths still call Trakt/Simkl/MDBList directly.

### G3 · storage split

- **`clearAllHomePageSettings` does not remove Trakt default keys**
  (`home_default_trakt_list_type` / `home_default_trakt_content_type`).
  Keep: origin clearer, pinned in `test/storage_home_prefs_snapshot_test.dart`.
- **Empty `home_tick_sources` writes an empty list**, it does not remove the
  key. Absent key still means all four `TrackingSource`s. Keep: origin setter,
  pinned in `test/storage_home_prefs_snapshot_test.dart`.
- **`'shelf'` (and any unknown `tv_home_style`) coerces to `'canvas'`** on
  both read and write. Keep: origin `kTvHomeStyles` table.
- **Hero `custom` with no ids reads `random`.** `auto` is stored; unknown
  modes and corrupt JSON also fall back to `random`. Keep: origin getter.
- **`trackingSourceRevision++` stays on the StorageService façade** of
  `setHomeTickSources` (HomePrefs cannot import StorageService). Callers
  still bump the notifier.
- **Callers still import `StorageService`.** HomePrefs is a forwarding façade
  only. Remaining Home keys are in HomePrefs (#70). Next: PlayerPrefs.
  `@Deprecated` on forwards waits for Q2.

### G4 · cloud file screens

- **Selection bar stays on both hosts.** Extracting `_buildSelectionBar` into
  the shared screen dropped two `app.shape.br` sites from `kShapeResidue` and
  failed `test/theme/shape_manifest_test.dart` (out of lane). Keep the bar on
  `RealDebridCloudFilesHost` / `TorboxCloudFilesHost` until that test lists
  the new file (and possibly lowers the 490 floor).
  *Resolved by G4-5*: `CloudSelectionBar`, `CloudTorrentSearchBar` and
  `CloudSearchBar` are now listed in `kShapeResidue` and the floor is 484.
  De-duplicating twelve identical sites down to six is what moved it; the
  floor is a revert tripwire, not a site budget.
- **TorBox's in-folder file search can never return a hit.** `_performSearch`
  reads `_navigationStack.first.node`, but the first entry is always the
  state pushed on the way *into* the torrent — `node: null` — so the search
  short-circuits to an empty list at every depth. Real-Debrid reads
  `_currentFolderTree` and works. Preserved as-is and pinned by
  `test/cloud_files_shared_chrome_origin_pin_test.dart`
  (`resultsReachable: false`); fixing it is a behaviour change, not a
  refactor. Consequence: TorBox's copy of `_buildSearchResultCard` was
  unreachable, so `CloudSearchResultCard` is pinned through Real-Debrid only.
- **`_showDeleteSelectedProgressDialog` was not converged** (G4-5). The two
  copies differ in the id type (`int` vs `String`), the delete service calls,
  the list/selection fields they mutate, the snackbar helpers, and the dialog
  title ("Web Downloads" vs "Downloads"). No single provider-label parameter
  makes the bodies verbatim; a shared version needs a generic id plus four
  callbacks, which is a rewrite. Same for `_buildTorrentSearchResults`
  (TorBox computes its result list *after* the empty-query check, RD before,
  and RD's empty copy omits the query) and `_buildViewSelectorBar` (TorBox
  suspends the torrent search and clears selection inline; RD calls
  `_exitSelectionMode`).
- **`_toggleSearch` stays on both hosts** (G4-5) even though the 13 lines are
  byte-identical. It is pure host-`State` mutation over four private fields;
  the only home that does not put a Flutter-dependent mutator in `services/`
  leaves a stub of nearly the same size in each host, i.e. a forwarder.
- **Premiumize / AllDebrid / PikPak routed** onto `CloudFilesScreen` (G4
  step 2). Selection bars stay on those hosts (PM/AD still use
  `BorderRadius.circular(12)`; PikPak already uses `app.shape.br(12)`).
  Public types and sidebar ids stay frozen. PikPak has no
  `initialSearchQuery` (bind drops the query). PM/AD/PikPak bind stays
  async (`Future<void> Function`); `CloudFilesSource.onSourceSelected`
  remains the RD/TorBox sync type.

### G1'-4 · tracker + local continue-watching

- **Generation tokens drop stale loads.** `_cwLoadToken` / `_traktCwToken` /
  `_simklCwToken` / `_mdblistCwToken` / `_iptvCwLoadToken` increment at the
  start of each loader; a newer run never has its nodes/state replaced.
  Keep: origin per-source loaders.
- **`_traktCwLoading = true` is a plain assignment** (initState-safe, not
  `setState`). Transient Trakt error leaves existing rows and only clears
  the loading flag. Resume refresh coalesces to 30s.
- **Simkl `result == null` is a transient fetch failure** — leave rows in
  place. Disconnect returns empty lists and falls through.
- **MDBList `!result.isUsable` discards.** Forced load stamps
  `_mdblistCwForcedLoadAt`; `_mdblistCwForceFresh` is a 3s window.
  Revision refresh waits for a current route (20×100ms) then 750ms.
- **`syncCwNodes` preserves the surviving prefix.** Only a shrinking tail
  is disposed; focus in that tail hands off to the last survivor
  (`search_cw_` debug labels).
- **Merged providers ship the combined list through the MOVIES slot**
  (same row id / node list); Series row is suppressed.
- **`_cwVisible` is allocation-free field checks**, not `_cwRows`. Keep
  in lock-step with the row gates.
- **Progress: Smart keeps the row's own numbers; dedicated source remaps.**
  IPTV is exempt (routeKey, not imdbId).
- **Card menu:** IPTV series play label is "Open series"; PikPak-only
  hides Play except IPTV. Hold-to-quick-play skips IPTV series.
  Host cells pass `showWatchedBadge: false`.
- **Host keeps** Home board chrome, favourites, hero, Discover CW landing,
  `_addonForContinue`, `_openItem` / `_onCatalogPlay` / `_playSelection`,
  and thin loader wrappers. Leftover wrappers listed as G1'-9 debt.
- **§2.2 `_cw*` getters + load wrappers → G1'-9.** `_cwMovies` /
  `_cwSeries` / `_cwAll` / `_cwIds` / node lists / `_cwMergeTrakt` /
  `_iptvCwByKey` / Trakt / Simkl / MDBList maps / `_cwRows` /
  `_cwVisible` / `_traktReserving`, plus `_loadContinueWatching` and
  the tracker load/open thunks. More than ~10 lines; Decisions on #96.
- **Double rebuild.** `_cw.addListener(_onContinueWatchingChanged)` →
  host `setState`, and the controller already notifies the extracted
  row. Same pattern as #90 `_onKeywordChanged`. Keep until **G1'-9**.
  Do not fix in this PR.
- **Source-scan pins follow the types.** `search_public_types_pin_test` and
  the G1'-2 Mode/CwKind check read `continue_watching_controller.dart`.
  `home_expanded_card_settings_test` counts host builders plus the two
  row `wrap(` see-all routes (still five; wrap is
  `_withHomeExpandedCardSettings`).

### G1'-3 · keyword search

- **Streamed batches merge through `TorrentService.mergeSearchResults`.** A late
  batch after `!kwSearching` is dropped (timed-out engine futures must not
  mutate the authoritative set). Keep: origin `_runKeyword` stream.
- **Freeze on first real interaction.** Pending count is a **set difference**,
  not a length delta. Adopt is identity-preserving; a vanished source tab
  clears. Empty `Torrent.source` buckets as `'unknown'`.
- **Provider ticks are additive** (`d:src` / `t:src`). Vanished sources prune
  from both the ticks and the seen set.
- **Cached-only:** no-real-hash + `torrentUrl` stays; cache key is
  `infohash.toLowerCase()` with no trim; settle only after the completion
  sweep when `kwTbRan && !kwOtherProviderActive`.
- **Relevance keeps engine order.** Name A→Z natural asc, case-insensitive.
- **Selectable rows exclude direct/external.** Dismissing bulk-add stays in
  selection mode.
- **Snapshot only a completed keyword search** (query + results, not
  mid-stream). Pending is folded into the snapshot in dispose. Home TV skips
  restore (`searchScreenRestoresKeyword`).
- **`_handleKwTabKey`:** activate/space; up → search field; down → toolbar;
  left edge → `MainPageBridge.focusTvSidebar`. Distinct no-engine-ran vs
  all-engines-errored copy.
- **`friendlyKeywordError` `replaceAll('Exception: ', '')`** also strips the
  suffix of `"SocketException: "`. Network bucket survives via
  `"Failed host lookup"`.
- **Host keeps** `_switchMode` (policy + query handoff), `_modeKeywordNode`,
  `_openKeywordBind`, and the catalog Sources bar. Leftover wrappers listed
  as G1'-9 debt.
- **Double rebuild.** `KeywordSearchController._emit` calls `notifyListeners`.
  The host (`_SearchScreenState`) listens with `_onKeywordChanged` → `setState`,
  and `KeywordSearchScreen` also listens → `setState`. Same notify rebuilds the
  shell and the extracted screen. Keep until **G1'-9** drops the host listener
  (the screen already owns the paint). Do not "fix" in a later extract. **#98**
  is a post-move widget pin and does **not** clear parent-path (h) for #90.

### G1'-2 · source edit/add dialogs

- **Movie chrome is `item.type == 'movie'` only.** Any other type (series,
  tv, …) gets series chrome: reorder, "Add Source", "Series Sources (N)",
  Remove All when count > 1. Keep: origin predicate.
- **Empty `initial` or null IMDb returns** from the edit dialog without
  opening the add picker.
- **Reorder `setSources` is not awaited.** Same as origin
  `ReorderableListView.onReorder`. Keep `onReorder` + `newIndex--`
  (not `onReorderItem`); an `// ignore: deprecated_member_use` hides
  the relocated INFO so `analyze_baseline.json` is not grown.
- **Local pick uses `item.type == 'series'`** for folder vs file (not the
  movie-chrome predicate). A `tv` title would take the movie-file picker
  and then `setSources` replace. Keep: two different type checks.

### G1 · step 5 TV stages

- **Empty Spotlight still `break`s to classic.** If every spotlight shelf
  has empty `items`, the host switch falls through instead of rendering the
  Spotlight board. Keep: origin `switch`, pinned in
  `test/tv_home_stage_layouts_pin_test.dart`.
- **`_buildDiscoverStage` stays on the host.** Discover chrome, not a TV
  Home layout. Classic `LayoutBuilder` hero/rows also stay.
- **Library-private `part`s.** Stage widgets are `part of search_screen.dart`
  so they can read host fields. Analyzer diagnostics report the part path;
  C0 baseline identity is `path|code|message`, so moved `cacheExtent` infos
  were retargeted in `tool/analyze_baseline.json` (no new kinds).

### G1 · step 4 Search/Discover screens

- **`searchMode` wins if both flags are true.** Tab index, variant key, and
  analytics name all use `searchMode ? … : (discoverMode ? … : home)`.
  Keep: origin `?:` order, pinned in `test/search_discover_shells_test.dart`.
- **God file stayed in place.** `SearchScreenHost` is still the 18k State;
  this step only split public types and shell contracts. TV stages landed
  in step 5 (#71).

### G1 · step 3 TitleOpener

- **Merged path includes movies.** When `_mergedSeriesPage` is on, both
  `series` and `movie` go to `MergedDetailScreen`. The origin comment said
  movies fall through to `CatalogItemDetailScreen`; the code did not.
  Keep: pinned in `test/title_opener_test.dart`.
- **Merged `showQuickPlay` is always `true`**, including PikPak-only.
  Legacy `CatalogItemDetailScreen` still uses `showQuickPlay: !_pikpakOnly`.
  Keep: two different literals, not a unification.
- **Simkl CW membership is `progress != null`; MDBList is `paused == true`.**
  Local CW is `_cwIds.contains`; Trakt CW is `_traktByImdb.containsKey`.
  Keep: origin predicates.

### G1 · step 2 CatalogSearchController

- **`_restoreHome` does not zero failures.** `CatalogSearchController.cancel`
  clears query/searching and bumps the generation token, but leaves
  `failures` at the last search's count. Keep: origin `_restoreHome`
  behaviour, pinned in `test/catalog_search_controller_test.dart`.

### G2 · settings_screen split

- **Restore-report omitted keys.** `homeCollectionsFailed` and
  `streamBadgeSourcesFailed` feed `hasAnyFailure` but are omitted from the
  snackbar failed-list. Keep: origin formatter quirk, pinned in
  `test/backup_restore_page_test.dart`.
- **`extraPlayerKeywords` stays bound** at `settings_screen.dart` (S1-fix).
  Do not drop the argument when extracting further settings pages.
- **Linux default label is `App folder (default)`.** SAF and Windows share
  `Downloads/Debrify (default)`. Keep: origin
  `DownloadService._appDownloadsSubdir` fallback on Linux.
- **macOS is excluded** from custom download location (sandbox grants
  read-only user-selected access; writable folder needs security-scoped
  bookmarks). Keep: origin comment, not a missing-platform bug.
- **Host keeps a `DownloadLocationController` field** plus three binding
  reads (`supported` / `subtitle` / `openSettings`). Not a method
  forwarder; delete only if a later settings-shell lane owns the field.

### P2e · playback-service strings

- **`PlaybackServiceDispatch` is a service façade**, not a new cloud
  capability. Same pattern as P2a `MagicTvDispatch`. Do not move it into
  `lib/services/cloud/` from a later lane (cloud is P1-owned).
- **`PlaybackCacheFirst.reorder` still string-switches** in
  `lib/services/cloud/` (`torbox` / `premiumize`). Out of P2e (forbidden).
  Keep until a cloud-owned follow-up.

## Regressions (follow-up PRs; do not leave on `main`)

These were **not** declared in the lane PRs. They change user-visible or wire
behaviour and must be restored, not kept as quirks.

| Lane | Regression | Follow-up |
|---|---|---|
| H1 | Canonical board rails regroup section ids by family `canonicalIndex`, so pinned collections no longer lead the board (they sat first in `_sections`: pinned collections, tracker lists, unpinned collections, catalogs). | **merged** `refactor/h1-pinned-collections-lead` (#57) |
| T1 | `_readPikpakWire` returned null when `pikpakPassword` was empty. Both old senders (Send Setup to TV + Transfer Everything) encoded `{email}` (password omitted when empty). | **merged** `refactor/t1-pikpak-empty-password` (#58) |
| S1 | `settings_screen.dart` never passed `extraPlayerKeywords`, so VLC / mpv / Infuse / … names dropped out of Settings search. | **merged** `refactor/s1-extra-player-keywords` (#59) |

### S2-1 · Stremio / social / Debrify TV prefs

- **`debrify_tv_show_watermark` is the show-channel-name key.** The Dart
  symbol is `getDebrifyTvShowChannelName`. Keep: persisted name is frozen.
- **Debrify TV filter getters have no try/catch.** Corrupt JSON throws
  `FormatException`. Stremio catalogs / favorites catch and return empty.
  Keep: origin.
- **`clearAllDebrifyTvSettings` leaves provider, channels, favorites, and
  the external-player notice.** Only display/filter keys and the `engine_tv_`
  / `debrify_tv_use_` / channel-size / quick-play prefixes plus the two
  keyword literals. Keep: origin clearer.
- **YouTube setter writes any int;** only the getter coerces `<= 0` to 1080.
- **Empty Lemmy instance reads as `https://lemmy.world`.** Setter still
  stores the empty string.
- **Adult-content helper is copied** onto `SocialPrefs` and `DebrifyTvPrefs`
  (same body as `StorageService.profileAllowsAdultContent`) so the stores do
  not import the god file. Call sites use `_profileAllowsAdultContent()`.
- **Callers still import `StorageService`.** `@Deprecated` waits for Q2.
- **`debrify_tv_style` / `debrify_tv_player_style` extracted in S2-4.**

### S2-2 · Provider credential prefs

- **CloudSecretPrefs hunks skipped.** Origin ~516–529 / ~549–565 / PM+AD
  API-key helpers / PikPak email+password were already CloudSecretPrefs
  forwards. Not re-extracted. Secret key strings stay `real_debrid_api_key`,
  `torbox_api_key`, `premiumize_api_key`, `alldebrid_api_key`, `pikpak_email`,
  `pikpak_password`.
- **`clearAllIntegrationStates` does not touch PikPak.** It clears RD/TB/PM/AD
  integration+hidden and WebDAV enabled+hidden only. PikPak enabled/hidden
  survive. Keep: origin clearer.
- **`setPikPakRestrictedFolder(null)` leaves subfolder caches.** Only
  `clearPikPakRestrictedFolder` also wipes torrents/tv folder ids.
- **RD endpoint default** is `https://api.real-debrid.com/rest/1.0`. Delete
  restores that default by removing the key.
- **Integration enabled defaults true** (RD/TB/PM/AD). PikPak and WebDAV
  enabled default false.
- **Post-torrent actions default `choose`.** File selection defaults `smart`.
- **WebDAV legacy single-server keys promote** into `webdav_servers_v1` on
  first `getWebDavServers` and write through SecretVault.
- **`clearAllFilterSettings` still clears `default_torrent_provider_v1`**
  via the store's `clearDefaultTorrentProvider` (same key, same remove).
- **Callers still import `StorageService`.** `@Deprecated` waits for Q2.
- **PlayerPrefs / IptvPrefs** extracted in S2-3. Tracking stays S2-5.

### S2-3 · Player and IPTV prefs

- **Style keys extracted in S2-4.** `player_dock_style` / `palette` / `size`,
  `play_loader_style`, `tv_player_controls_style`, `debrify_tv_player_style`,
  `iptv_style`, `iptv_channel_preview_enabled`, `iptv_player_guide_style`
  now live on `AppStylePrefs`.
- **Completion thresholds stayed.** `movie_completion_threshold`,
  `episode_completion_threshold`, purge/migrate hooks, and
  `_getPlaybackStateMap` stay for S2-6 / S2-7.
- **iOS external player defaults to `vlc`**, not `system_default`.
- **`clearExternalPlayerSettings` drops Android/generic keys only.**
  iOS / Linux / Windows preferred-player keys survive.
- **Empty path/name/command remove the key.** Empty subtitle/audio language
  codes persist (`''`); only `null` clears those two.
- **Unknown skip-segment provider reads and writes `auto`.**
- **`uiSoundsCached` is published before the prefs write.**
- **Android renderer first read migrates null/`direct_surface` to
  `direct_mediacodec` once** (`android_video_renderer_gpu_migration_v1`).
- **IPTV decoder / startup-mode coerce unknown values; network tuning does
  not.**
- **Virtual playlists are dropped on set.** Favorites / continue / list /
  stremio-addon URLs never reach `iptv_playlists`.
- **Last-live and pinned startup blobs are SecretVault-sealed** (Xtream URL
  embeds the password). Empty last-live URL is a no-op; malformed JSON
  reads as null.
- **`setStartupIptvEnabled(false)` removes `startup_mode`.** The comment
  says "leave the mode behind"; the body clears it. Shared keys
  `startup_auto_launch_enabled` / `startup_mode` stay owned by
  StorageService.
- **`warmStartupIptv` last-with-no-channel sets the `firstAvailable`
  sentinel; pinned-with-no-channel leaves the cache null.**
- **`recordIptvWatch` / `getIptvContinueWatching` no-op when tracking is
  off** without deleting stored history.
- **Callers still import `StorageService`.** `@Deprecated` waits for Q2.

### M1-1 · Channel cache warmer

- **No generation / warm-token.** `computeChannelCacheEntry` has no
  generation counter. Empty `keywordsToWarm` resets `anySuccess` to
  `accumulator.isNotEmpty`; a failed warm returns
  `torrents: const <CachedTorrent>[]` (drops leftover accumulator) and
  `'No torrents found for these keywords yet.'`. First `failureMessage`
  wins (`??=`). Keep.
- **Empty cache is a miss.** `ensureCacheEntry` is memory-first and does
  **not** write a storage miss back into the map (returns null). Keep.
- **Inclusion-only keyword filter.** `filterCachedTorrentsForKeywords`
  keeps a torrent if it has any allowed keyword. `merge(keywords: matching)`
  unions onto the existing list and does **not** strip the others. Keep.
- **Accumulate override is strict `>`.** Equal seeders keep the old torrent
  body; keywords/sources still union. Empty infohash is a no-op. Keep.
- **Quality filter at READ.** Empty match falls back to the unfiltered pool
  and notifies (snack stays on the host). Playback select filters first;
  `<= 1000` shuffles the whole pool; empty per-keyword pick takes the first
  1000 **unshuffled**. Keep.
- **Quick-play torrent filter is strict** unless `allowFallback` is true
  (partial rebuilds must not start an off-filter source). Keep.
- **TorBox window.** Empty API key returns no hits and keeps the start
  cursor; live walk is chunk 90 / max 2 calls / stop on first hit. Keep.
- **Edit-prune.** A torrent that carries **any** removed keyword is dropped
  entirely (even if it also has kept ones). Prune-to-empty marks `failed`
  and keeps the baseline error (`clearErrorMessage` only when torrents
  remain). Create/update **dialogs** stay on the host (M1-5). Keep.
- **RD size-filter session** lives on the warmer (`rdSizeRejections` /
  `sizeFilterRelaxed`); the relax snack stays injected. Trailer floor
  (`minVideoSizeBytes`) is passed in. Keep.
- **P1b unlock pin path identity.**
  `test/cloud_magic_tv_unlock_pin_test.dart` now scans host +
  `channel_cache_warmer.dart` for `unrestrict['download']` /
  `unrestrict['filesize']` so the filesize read is not a new allowlist
  miss. Same relocate pattern as G1 `cacheExtent` / M1-0 WatchSession.

### M1-2 · Channel import/export

- **Device-picker cancel leaves busy.** After the mode dialog sets
  `_isBusy`, a cancelled `FilePicker` returns without clearing it.
  URL / community cancel paths do clear busy. Keep.
- **Text import cap is 500; persist cap is 1000.** A `.txt` file rejects
  more than 500 keywords; zip/yaml persist uses `maxChannelKeywords`
  (1000). Keep both.
- **Unknown text is not sniffed as yaml/txt.** `_determineImportType`
  only content-sniffs `debrify://` after extension + PK signature.
- **YAML `sources` are quoted as-is**, not passed through
  `_escapeYamlString` (only `name` is escaped). Keep.
- **Create/update dialogs and watch flows stayed** (M1-5 / M1-3).
  `_showDebrifyTvConfirmation` stays on the host so single-channel
  delete can share it; delete-all calls `confirmDeleteAll`.
- **Shape / analyze path identity.** Three `SORT_CHILD_PROPERTIES_LAST`
  infos moved to `import_export_dialogs.dart`. The three
  `USE_BUILD_CONTEXT_SYNCHRONOUSLY` rows stay on the host — those
  origin hits were not the import sites; the new file uses a local
  `BuildContext` + `context.mounted` so it does not add diagnostics.
  `import_export_dialogs.dart` added to the shape manifest (residue 0;
  two `app.shape.br` sites).
- **`cloud_magic_tv_unlock_pin_test` still scans host + warmer.**
  Import/export does not touch `unrestrict` / `filesize`.
- **§2.2 host block (~50 lines) recorded after merge.**
  `ChannelImportExportHost` / `ProgressSink` on the State:
  `importExportMounted` / `importExportContext`, `isAndroidTv`,
  `isBusy` / `status`, `channels` / `channelCache`, `applyImportState`,
  `reloadImportedChannels`, `confirmDeleteAll`, `showSnack` → **M1-3**.
  `showImportProgress` / `createImportedTextChannel` → **M1-5**.
  Do not start M1-3 until a real origin-path pin exists for M1-0/M1-1.

### S2-4 · App style prefs

- **Discover layout + source keys moved** so Leaves hit 800. They are
  layout/chrome caches (`discover_layout`, `discover_default_source`,
  `discover_last_source`), not a later Discover store. Say so if a later
  slice wants them back.
- **Launch animation, text brightness, sidebar configuration, TV UI scale,
  and TV hero artwork** moved with the style-cache family for the same
  Leaves reason. TV render quality / `getTvLowResRenderActive` stayed
  (device-level, `DevicePreferences`).
- **`migrateDefaultsGeneration` stays on StorageService** (S2-7). It now
  writes through `AppStylePrefs.appThemeKey` / `detailThemeKey` /
  `detailPageStyleKey` / `tvSidebarStyleKey` / `desktopSidebarStyleKey` /
  `debrifyTvStyleKey` (same pairing, same literals).
- **Unknown → origin fallbacks.** Dock `classic`, play-loader `marquee`,
  TV controls `marquee`, Debrify TV player `cinema`, app theme `legacy`,
  detail theme `signal`, detail page `console`, Debrify TV style `grid`,
  IPTV look `command`, IPTV guide `classic` (tvOS unset → `spotlight`),
  phone nav `classic`, launch ident `ident`, TV sidebar `ghost`, desktop
  sidebar `rail`. Keep.
- **Cache publish order is not uniform.** `debrifyTvStyleCached` /
  `iptvStyleCached` / sidebar / discover publish *before*
  `ProfilePreferences.instance()`. `themeOverridesCached` and
  `launchIdentPaletteCached` publish *after* instance(), before the write.
  Detail page / theme / app theme / launch animation publish *after* the
  write. Keep.
- **`two_tier` dock style is still accepted** (legacy synonym of `auto`).
- **TV UI scale setter writes any int;** only the getter coerces to 90.
- **Empty `theme_overrides` removes the key.**
- **Callers still import `StorageService`.** `@Deprecated` waits for Q2.
- **`stale_runtime_guard_test` names, not callees.** A façade
  `static String get fooCached` still counts even when the body is a
  store getter. `resetProfileCaches()` must **name** each mirror in its
  own body — calling `AppStylePrefs.resetCaches()` is not enough. S2-5
  and later must list every extracted `*Cached` on the façade.

### S2-5 · Tracking prefs

- **`trackingSourceRevision` lives on TrackingPrefs.** StorageService keeps a
  forwarding getter so existing `StorageService.trackingSourceRevision.value`
  reads and writes hit the same notifier.
- **`home_tick_sources` stays on HomePrefs.** TrackingPrefs.get/set wrap it
  only so `setHomeTickSources` can bump the revision. Ownership did not move.
- **Legacy catalog switches stay bool keys.** `trakt_sync_catalog_items` /
  `simkl_sync_catalog_items` / `mdblist_sync_catalog_items` default false.
  Absent legacy key still seeds that tracker ON when adopting masters.
- **Unknown `watch_progress_source` reads `smart`.** Dedicated disconnect
  fallback only owns trakt/simkl/mdblist — never smart or local.
- **Empty MDBList username removes the key.** Empty Trakt username persists
  `''`. `clearMdblistAuth` also drops clones + checkpoint.
- **MDBList tokens are not CloudSecretPrefs.** Same SecretVault +
  ProfileCredentialFacade dance as origin. `_credentialConfigured` moved
  with the three tracker helpers.
- **Episode progress / `_getPlaybackStateMap` stayed** for S2-6.
- **Callers still import `StorageService`.** `@Deprecated` waits for Q2.

### V1-3 · subtitle track controller

- **Stored `auto` is no-choice.** A persisted subtitle id of `auto` (audio-only
  persist) falls through to the default-language path so addon auto-select is
  not blocked by mpv's file-default track.
- **Stored `no` is always honored.** It never counts as a default-language
  conflict, including when the global default is `off`.
- **Conflicting bare mpv ordinals lose.** A stored embedded id whose language
  does not match the current default (or when default is `off`) takes the
  default-language path. Ids are file-local ordinals.
- **Addon auto-select defaults to English** when no subtitle-language
  preference is set (`defaultLang ?? 'en'`).
- **Temp-file cleanup stays on host dispose.** Controller owns the delete
  loop; `_VideoPlayerScreenState.dispose` still calls it.
- **Identify sheet was not re-extracted.** Controller calls
  `showIdentifyTitleSearchSheet` / `requestSeasonEpisodeForIdentity`. Host
  keeps `_currentPlaybackTitleForIdentity` and
  `_currentSeasonEpisodeForIdentity`.

### V1-4 · IPTV recording

- **Engine first on Android.** When the engine flag is on and the stream has
  a recordable URL, `LiveRecordingService.start` runs before the tee. Tee
  fallback is only `engine_unsupported` / `fgs_not_allowed` / `missing_plugin`
  on a non-committed profile.
- **Desktop never falls through to the tee.** `DesktopRecordingService.instance.isSupported`
  + `extension: 'ts'`. HLS / no record URL shows the desktop-HLS snack and
  returns; mpv muxers are absent on media_kit's stock libs.
- **Committed profile + no engine URL aborts.** "This stream cannot be
  recorded safely" — no tee fallback.
- **Dispose does not await stop.** `finalizeOnDispose` bumps the start-gen,
  clears tee state, and chains MediaStore publish after `stream-record` is
  cleared. Desktop captures are left running (hub / service owned).
- **Resource lookup prefers a fresh playlist read.** Launch-payload revision
  is fallback only (`source_playlist_id` → `series_playlist_id` →
  `widget.iptvSourceId`).
- **Zap / catch-up / overlay Stack stayed on the host.** Call sites still
  invoke `_stopRecording`; the body moved.

### V1-5 · IPTV zap ring + catch-up

- **`onSwitch(channel)` looks up by url+name.** The host
  `_switchToIptvChannel` stays the media owner (ticket, recording stop,
  Stremio ladder). The controller's same-named helper only forwards the
  channel at that index.
- **Unpaged zap wraps and arms paging.** A launch window with no page
  context modulo-wraps, then `_ensureIptvZapPagingArmed` re-anchors so a
  lost bootstrap does not leave the ring circling the launch list.
- **Prefetch edge is 12; page size is 1500.** Adjacent-category cache
  answers only its origin and direction; pending inputs cap at 24 and
  collapse to ±1.
- **Catch-up is a single VOD item.** Programme title, `contentType: 'vod'`,
  paging reset, then switch index 0. Source id is
  `source_playlist_id` → guide context → launch source.
- **Banner raise is skipped** when the channel sheet, source sheet, guide,
  or dock is up. Hide timer is 4500ms. Ticker runs while floating or while
  the dock owns live identity.
- **Stream-error burst is 6s.** Auth-looking 401/403/404 skip recovery.
  `_lastIptvErrorShown` lives on the controller; switch still clears it
  via `clearErrorBurst`.
- **Decoder / resume / identify / subtitle / recording were not
  re-extracted.** Overlay Stack stays for V1-10.

## Leaves shortfalls (merged Phase 2)

A PR under its Leaves target is a reject unless the shortfall is named here
with the slice that clears it. "Decisions needed: None" is not that record.

| PR | Lane | Target | Actual | Shortfall | Clears |
|---|---|---:|---:|---:|---|
| #77 | S2-1 | 1 400 | 531 | 869 | S2-7 (later slices took named hunks; leftover is facade) |
| #82 | S2-2 | 900 | 575 | 325 | S2-7 |
| #83 | V1-2 | 700 | 527 | 173 | absorbed by V1-3 (subtitle-fetch tail; already merged) |
| #86 | S2-3 | 1 600 | 1 067 | **533** | **S2-7** (style went to S2-4; completion/progress is S2-6; the 533-line hole is facade collapse) |
| #87 | M1-1 | 850 | 856 board / 581 first body | 0 after resubmit | create/update UI stays M1-5 |

Met: G1'-1 1069/850, G1'-2 486/450, G1'-3 2379/2100, V1-1 666/650, V1-3 943/900, V1-4 704/550, V1-5 1008/1000, M1-2 1539/1500, S2-4 806/800, S2-5 373/350, G2 3107→2899 vs 3000, Leaves-0 prereqs.

## Gate (h) pin audit (merged Phase 2)

Evidence: widget test driving State, or a test calling the origin/lib function.
Text greps and test-local clones fail the gate even when the pin commit predates the move.

| PR | Lane | Pin file | Verdict |
|---|---|---|---|
| #73 | S2-0 | registry / byKey tests | **pass** (lib StorageService / ownership) |
| #74 | G1'-0 | `search_public_types_pin_test.dart` | text-only (rename; acceptable for Leaves 0) |
| #75 | V1-0 | `video_player_launch_fields_pin_test.dart` | **pass** (constructs `VideoPlayerScreen`) |
| #76 | P1b | `cloud_magic_tv_unlock_test.dart` | **pass** (calls cloud lib) |
| #77 #82 #86 #92 #93 | S2-1..5 | `storage_*_snapshot_test.dart` / s2x roundtrip | **pass** (write/read through `StorageService`) |
| #78 | G1'-1 | `catalog_play_resolver_pin_test.dart` | **fail** text + test-local clones |
| #79 | V1-1 | `player_resume_pin_test.dart` | **fail** text + clones (`resume_controller_test` is post-move) |
| #81 | M1-0 | `magic_tv_watch_session_fields_pin_test.dart` | **fail** text-only |
| #83 | V1-2 | `identify_title_sheet_pin_test.dart` | **fail** text; widget tests import the new file |
| #84 | G1'-2 | `source_binding_dialogs_pin_test.dart` | **fail** text + clones; `source_binding_dialogs_test` is post-move |
| #85 | G2 | `download_location_pin_test.dart` | **fail** text-only (lane already met 3000; no next slice) |
| #87 | M1-1 | `magic_tv_channel_cache_warmer_pin_test.dart` | **fail** text + clones |
| #88 | V1-3 | `subtitle_track_controller_pin_test.dart` | **fail** text + clones |
| #90 | G1'-3 | `keyword_search_pin_test.dart` | **fail** text + clones. **#98** pumps `KeywordSearchScreen` post-move — does **not** clear parent-path (h) |
| #91 | V1-4 | `iptv_recording_controller_pin_test.dart` | **fail** text + clones |
| #94 | V1-5 | `iptv_zap_controller_pin_test.dart` | **fail** text + clones |
| #95 | M1-2 | `magic_tv_channel_import_export_pin_test.dart` | **fail** text + clones (merged; §2.2 host block recorded after) |
| #100 | V1-fix | `673af47d` lib-call pins | **pass** for the four moved files (predates `10f10a61`) |

Follow-ups before the next slice of that lane merges:
- G1': parent-path (h) for #90 still unpaid. Do not merge #96 until CW leaves `lib/services/`.
- V1: real lib pin for V1-1..5 before V1-6 assigns.
- M1: real lib pin for M1-0/M1-1 before M1-3. #95 is **merged**; Decisions recorded (`ChannelImportExportHost` / `ProgressSink` → M1-3 / M1-5).

## Process

Gate check **(c)** is tightened (plan §6): the pinning test must be committed
and shown green **before** the move commit, and the PR must include an
origin-diff of each moved body with every difference listed and justified.

P2b / P2c / P2d had pin-before-move commits but **no origin-diff table**. They
stay on `main` (no revert without a behaviour audit); they are not the
template for later lanes. Reject any new review PR that omits the table.

## Out of plan

- **PR #56** (Qwen helper) edits `.cursor/**` (Q3) and is held until Phase 3.
- **PRs #36–#43** (stacked TorBox / web download port) are superseded by **G4**
  (cloud file screens). Close rather than rebase through the refactor.

## Gate 3 decisions — 2026-09-05

- Gate 3 evidence is user-reported at 843d631b: Windows/Flutter 3.47.2, 471 analyzer diagnostics (0 errors), 5143 passed/37 failed. #108 independently verified 21 targeted tests and merged; full corrective gate still due. Both native builds reported pass; SHIELD smoke not evidenced.
- #100/#102 V1 controller directory changes are accepted as honest screen-layer placement, not dependency separation. V1-1 Leaves 666, V1-2 527, V1-3 943, V1-4 704, V1-5 1008 are host reductions; relocated widget-building units do not become pure logic merely by moving directories. Phase 3 must not count directory relocation again as extraction.
- Restore #72 layering ceiling 77; do not ratchet it upward. M1-fix removes the seven channel_import_export service-to-UI dependencies; M1-3 waits.
- #96 original total +1118 = production +575, tests +494, docs +49; host Leaves 1738 measures only the host and does not measure repository shrinkage. Integration adds a disposal guard, so candidate host Leaves 1737. Candidate build pin reports one host build and one row build; row has no second listener. Preserve required host notification. Disposal race coverage still needs a mutation-sensitive real lib test. Keyword #90 double-update finding is separate.
- #109 held outside plan; adoption requires C0 decision. All worker assignment/merges go through orchestrator.
- Canonical Flutter is existing CI 3.44.8 for both dev and CI; no silent analyzer rebaseline to diagnostics from3.47.2. SDK alignment and comparison assigned C0.
- S2 requires synthetic fixture produced by real pre-refactor export and restored through current lib APIs, comparing keys/types/values and profile isolation once per storage lane. Current snapshot tests are not proof of complete profile restore compatibility.
- Forwarders expire with named G1'-9/S2-7 cleanup and Q2 caller migration, before Phase 3 completion. No indefinite wrappers.
- TV performance gate: SHIELD Home focus/playback smoke once per phase, with rebuild-count tests; phone smoke is not SHIELD evidence. Hardware run remains user-dependent.
- Permanent-fork versus upstream-integration strategy remains a product decision. No recurring merge automation scheduled without that decision; no upstream merge mixed into extraction lanes.
- Backup decoder recovered from8d8e5ebd is separately authorized feature work: opt-in strict admission only, no existing caller switches. Draft review first; full sync semantics remain undecided.

User decisions (2026-09-05): aim to contribute the refactor upstream; do not treat this as a permanent fork or schedule its conditional recurring merge lane. SHIELD hardware unavailable: record hardware performance gate blocked, no phone substitution. Independent corrective work continues.

Superseding user correction: decoder112 is parked scope creep for this refactor; only S2 fixture tests continue. Upstream workflow currently pins3.44.8 (blob2a48503bcf470fef4affcc606182c90444855511); SDK alignment follows that evidence. No automatic golden regeneration. Strategy precedes new extraction assignment. Disposal96 has one remaining verification attempt maximum, then explicit unresolved debt if needed. Event-driven worker reporting with hourly fallback.

## Storage residual audit (2026-09-05, main b3f518ff)
Storage4365 exceeds2800target by1565:783explicit shortfalls(433S2-6+350S2-7),782otherresidual. Read-only audit distinguishes1315forwarder methodlines,1755logicmethodlines,137constantlines,662blank,404comments,92otherdeclarations. Proposed progress/metadata/watchlist/quick-filter/repair followons forecast1010–1165 total;400–555would still require authorized Q2caller/facade retirement or targetdecision. These are estimates, not achieved reduction. No new extractions authorized before automatedmini-gate. Do not count historical relocation or same remaininglines twice.


V1-6 decoder feasibility paused: actualnative syntheticvideo failed beforepositiveparams evenwith approved2IO-only testingseams; no greenpin/extraction/PR,450Leaves notclaimed. Failedscaffold remains uncommitted only isolated debrify-v1-6-decoder-diagnostics. No furtherhooks permitted. PositiveAndroidfallback also unproven. Newnativetest cannot silentlyship because currentnativejob singlecase; explicitCIregistration required iffuturefeasibilitysucceeds.


G1'-7 readiness: actualDiscover uses20hostcollaborators, not plannedboardRefs seam.56discoverMode tokens/39widgetaccesses currentinventory; privateexecutionbranches targetzero, frozenpubliccompatibilitydispatch exempt. Must approve explicitdata/action lifetime ownership, no hiddenhost/callbackbag. No broadsharedwidget/router edits approved; actualoriginstartup/focuspins next after123merge. M1-5scope core+cohesivehelpers/sharedchip approved; noimport/watchhooks padding, livewrites/resetorder preserved; productwaitnextautomatedgate.


## Evidence correction: M1-4 Android-TV host coverage
MagicTV_loadSettings uses AndroidNativeDownloader.isTelevision, which returnsfalse ondesktop beforechannel; PlatformUtil debugTVoverride does not set host_isAndroidTv. PR122 tests named androidHost=true do NOT exercise hosttrue launcherbranch or Androidbridge-level rejection. Valid coverage remains realdesktop channel switching/capturedkey/nextwrap and hostearlyrejection/Flutterroutecontinuation. Hosttrue/nativepositive/onFinished all unproven. This supersedes earlier stronger coverage wording; no productbug identified. M15mustnotclaim TVfocus from thisoverride; desktopfocus/disposal only. Worker authorized precise merged122PRbody correction.


G17a PR125 current-caller contract accepted after independent76current/8origin tests: soleproduction commit callback synchronous once; loader partition moves before mounted/commit with extraasyncboundary. Disposedpath mayallocate discardedlists; arbitrary delayed/multiapplycallbackequivalence and exactmicrotasktiming NOTproven. No currentcallerfailure found. HostrefreshIO order unchanged; sharedprefshold cannotkill removedwatchlistawait. Zero750Leavescredit. M15a editor/chip only approved; rejectedlarge20fieldsettingscallbackbag, remainingsettings requiresactualownershipdesign.


M15a analyzer provenance repair authorized: historical0a0ca9e6 mislabeled originaleditor baseline2096:17 as importdialog137:13. Minimumtwo-rowrepair maps originaleditor to neweditor166:17/span8351 and originalimport3198:15 to actualimport141:13/span1229. Samecode/type/severity/message,454count andSORT_CHILDmultiset8 unchanged; no arbitraryhostrow reassignment. Otherhistoricalmislabels recorded asdebt, notexpandedcleanup.


## Shape guard debt identified during PR129 review
Independent review of 4ab8e1c confirms only moved-renderer inventory repair, floor490 unchanged. Existing aggregate bare-radius test is allowlisted for tv_sidebar_nav.dart; an additional offender can therefore be masked under the same test identity. Raw mutation failure does not prove fail-closed CI. C0 assigned read-only minimum per-file guard/allowance migration proposal before any new edits. No allowance expanded, no product radius change authorized.


PR131 resolved aggregate shape-guard masking via per-file identities and separate sidebar debt cap, with independent actual-parser mutations. PR134 retains32/24line lifecycle adapters and legal owner/legacy library cycle untilrealG17/Q2;93host reduction is not independent Discover closure. No native or escaping-listener runtime proof claimed.


User requested per-god-file forwarder counts in every gate row; ledger inventory assigned, historical unmeasured entries must stay unmeasured rather than fabricate counts. Gate4 reported native unset-env failure is developer usability debt; skipping that ordinary run must not relax mandatory native CI evidence.


PR139 Windows exact-pair exit79 diagnosed read-only as native flutter_tester.exe access violation0xc0000005, corroboratedApplicationError1000/WER1001 for both origin/current failures. Selector/noTestsRan message is secondary after process crash. Faulting component remains unknown; no dump available, no attribution to skip change/libmpv/driver established. Linux exact-head native pair passed; unset/invalid/strict-runner semantics independently verified. Preserve failed evidence; no blind retries or Windows-green claim.


### Discover refresh ordering: retained coupling
Post140 read-only review found no existing public seam that independently observes Discover private watchlist-node synchronization or separates watchlist and CW awaits: both start through the memoized preference future, and Discover cannot arm Home deferred-down state. Preserve the full FavRows adapter/lifetime; replacing it with a bare loader is not authorized by current pins. No additional136-equivalent test counts as closing this gap. A bounded real Home-consumer focus pin is assigned separately and will not be described as Discover or independent-await proof.


### Onboarding restore compatibility quirk (preserve, not fix)
Actual pre-S2 6d26 export excludes initial_setup_complete_v1 while authenticated profile setupComplete is true. Current restore can import canonical true into a destination retaining compatibility false; the next public isInitialSetupComplete reconciles that false into canonical readiness and removes the compatibility key. Subsequent re-export is false. Locke's exclusion fixture pins this observed outcome; no claim that readiness stays unchanged or that preferences are authoritative in general. Do not fix within the ownership extraction. Evidence branch refactor/s2-profile-onboarding-state fixture checkpoint; final commit pending.


## Atrium origin hold — September 6
Two finite origin runs at 1920x1080 and 1920x1440 reached navigation assertions but each ended red on a 2.1px RenderFlex overflow. No green pin or extraction credit. A two-label typography/height mismatch is a source-based numerical hypothesis, not verified RenderObject attribution. Raw logs and uncommitted origin test remain in debrify-g1-8-atrium-stage; no suppression, product fix or further runtime attempt authorized. M1 cached consolidation may meet its leaf-size target while live WatchFlowBindings/UI coupling remains open; distinct provider algorithms are intentional, not a demand for another abstraction.

## PR182 native reliability note
Exactdf41 CI attempt1 passed originbc46 but current process hung600s with no assertion/error terminal. One authorized failed-job retry passed both sides using identical test/runtime hashes. Cause unknown; original and retry artifacts retained in C0 history-watchlist review .dart_tool/q2-review. No timeout/code/baseline change; accepted with note, not first-pass-green or proven infrastructure failure.

## M1-7 finite retention disposition after186
Accepted remaining Windowed bindings as live owner-injected work, not dead aliases: quick/cached prepare callbacks retain captured credentials/log/candidates but resolve current host prepare state at invocation; two populateQueue bindings keep the queue owner. Historical24 physical lines now18, not additional deletion credit. Two requestNext aliases preserve the same run callable; inlining does not remove an ownership edge. Four TorBox/Premiumize entry methods compose live admission/continuation. Seven channel delegates retain live channel/native routing; editor/settings/import-export callbacks retain UI lifetime, policy and persistence boundaries. These are explicitly retained obligations, not a requirement for zero callbacks. Earlier Q2 dead aliases were removed;186 replaces three operation callbacks with two typed captured-operation dependencies. No new native/device proof. Original M1-7 size627/common-flow/capability work is implemented; whole outcome awaits integrated acceptance of186. No expansion to autonomous providers or unifying distinct algorithms.

M1-7 closure: gate e78d100e passed including186; finite retention disposition above plus leaf627/common-flow/captured-operation evidence satisfy agreed outcome4. Closed, without expanding scope or claiming native/SHIELD execution.

Renderer experiment HOLD: isolated new case on193-based separate draft timed out waiting disposal entry, with later cleanup/null assertion and replacement progress. No native or positive fallback proof; merged193 unaffected. Preserve raw renderer-isolated.jsonl/proof and three uncommitted experiment files. No further runtime/investigation authorized; V1-7 cohesive speed/aspect read-only design explicitly authorized separately.

## September 6 — storage retention decisions after gate896a168d

The parent accepts five named coordinator retentions: migrateDefaultsGeneration(21 declaration lines), clearAllStartupSettings(14), clearAllFilterSettings(5), clearAllTorrentEngineSettings(12), resetProfileCaches(22). Preserve captured preferences, phase order/final marker, startup IPTV tail and synchronous first keyboard reset slot. Their 74 lines are not dead forwarding APIs or completion credit; all failure/interleaving cases are not proven.

Battery's two methods/eight lines retain a profile-scoped raw String/default unknown until meaningful download-lifecycle work. Fixed-parallel's two methods/six lines retain getter1/setter-no-op/no persisted key. No device-global conversion or concurrency feature is authorized.

Six native/render methods42 lines plus debug reset3 remain explicitly deferred ownership work, not completed or waived. Nine native-sensitive forwarding APIs and caller/native-proof requirements remain. Strict facade-only outcome3 stays OPEN. Indexer portable-resource export and adult held-inside-getProfile gaps remain disclosed.

Search Atrium FINAL HOLD and merged stage ledger762/1400 (638 short) remain open. Mosaic129-line cell policy is retained because generic shelf substitution changes focus notification and prefetch behavior. Player scrub ownership is retained because moving five helpers leaves eleven invalidation/input transitions behind; no callback-only wrapper or renewed native experiments is authorized.
### September 6 — gate 9ae and merge #210
Original native gate attempt exited79 with an incomplete test, without an assertion stack. One isolated original-only retry passed after concurrent verification ended; current native test passed first attempt. Root cause remains unknown; retain both evidence directories. Gate passed with this note, not a first-pair pass. #210 removes32 forwarders and69 host lines (66 net production lines), preserving domain behavior; #211/#212 remain unmerged. Physical counts corrected for prior added imports; these are not whole-project deletion claims.

### Storage limited milestone accepted at bc017
Independent contract mapping and full bc017 gate support acceptance of extracted/key-compatible Storage plus completed eligible Q2 routing only. Strict outcome3 remains OPEN: six native/render policy methods42lines plus debug3 are deferred, distinct from nine already-owned native-sensitive forwarding APIs. Five coordinators74lines and battery/fixed14lines remain previously accepted retentions; no new zero-alias requirement. Finite6d26 pre-S2 fixtures are not a complete pre-Phase0 user backup; Indexer portable export, adult held lookup, Android-positive and lifetime evidence remain unproved. The gate passed with recorded known failures; no device wait or broader closure inferred. Same C0 AST204/133/161/23/0 remains authoritative. No further tiny-batch survey is assigned.

### Player terminal tracker feasibility — stopped, no green pin
Four bounded attempts retained in debrify-v1-9-progress-terminal-origin/.dart_tool/tracker-terminal/DEBT-HANDOFF.md. Corrected authenticated fixture reached actual selected-episode21s seek, but final test failed on a preexisting initial-resume800ms delayed verification Future remaining on the fake clock. Selected resume does not enable landing verification; original delayed task checks disposal/epoch before effects after waking. No post-dispose seek or product regression proved. Overall four failures remain failures; no fifth run, timer clearing, pump extension, or lifetime production fix authorized. Full tracker pin/ownership remains open. Upstream candidate remains locally prepared only by explicit user decision.

### Current hero/player evidence after #220
Hero first invocation failed before loading: missing own package_graph. Genuine offline enforce-lockfile dependency setup preserved manifest/lock; seven verified generated checkout-only changes restored. Replacement timed out at180s: first case MissingPlugin temp/support-directory errors, second unfinished, zero visible passes. Default cache initialization preceded path-provider fixture setup; second stall cause unproved. Setup/cleanup-only correction is authorized for review, no product move/green pin.
Player separately reviewed cancellation correction adds98 production lines, four host hooks. First combined run24PASS/2ERROR: original15 passed, lifecycle9/11 passed. Two fired-before-continuation cases report guarded-function conflicts from assertions inside timer callbacks; independent attribution pending. Preserve raw failures and extra async-continuation behavior delta; no timing-identity claim, no fifth tracker attempt. No new device proof.

### Player #221 merged and hero verification checkpoint
Independent review confirmed both lifecycle callback errors were Flutter guarded-expect placement, not demonstrated cancellation failures. Only callback expect changed to expectSync with identical matcher; author corrected26PASS and independent26PASS. Full431/scoped61/layer56 unchanged against exact origin. #221 merged d7cdffb7; extra continuation and prompt cancellation are declared behavior corrections, production+98/host+4 and zero extraction credit. Full actual-main gate pending.
Hero origin finally2PASS after reviewed fixture-only cache setup, exact background whitelist and explicit zero-time frame request; prior failures retained. Product author136PASS/one exact preexisting sidebar failure; three actual radius inventory mutations failed intended assertions and restored three guards passed. Total radius allowance162 unchanged. Independent production run remains pending behind full gate; hero not merged.


## #225 merged: shared rail labels (d282889d)

Origin tests preserve the existing held ninth-row focus behavior: keyed Promenade/Mosaic replacement can leave the enclosing route scope focused. Explicit ninth-row focus recovery is a separate test action, not an automatic-focus fix. Theme dependency moves from the host to the inner stage; finite theme/scaler evidence is recorded, not exclusive host-detachment proof. Origin eight cases passed before the move; production and independent suites each passed132 with one existing sidebar shape exception. Search removes80 physical lines (64 label,4 height,1 font,1 binding,10 documentation/separators), while whole production grows9. Stage credit is988/1400, leaving412. Full-row focus/action ownership remains excluded from the next Atrium text preparation.


## #226 merged52e8da5b: Atrium text ownership

Origin e8c759 five tests green before product b58fc1; independent129PASS and one exact known sidebar failure. Wall theme dependency moves into the inner stage; borrowed notifier references are stable, values remain lazy. Same Text measurement, conditional second-row read, dossier builder context and row/native bodies are preserved. Host -59, owner +80, whole production +21; callables7 to6 but leaf inputs10 to14. Stage shortfall353 after merge. Full gate remains31e360, production counter2; #227 would trigger next gate. Home takeover proposal has zero seven-stage credit.


## User direction: Phase 2 player finish and Gate 5

Gate 5 user report at d2cbea19 Windows Flutter3.47.2:6187pass/33exactallowlisted,0unexpected/0unused; analyzer0errors449issues,layer56/77,WindowsbuildPASS/launched. Not an independent rerun; no Android/new-device result inferred. Search/Magic/Storage/Settings accepted at target and frozen. Prior353 Search target remainder is superseded by user scope decision, not silently completed. Player11539->9500 is the Phase2 stopping rule,2039lines remaining. Renderer coordinator and whole scrub-session ownership decisions are written at board top; tracker fake-clock harness cleanup authorized, actual green pin still required. All four workers redirected to disjoint player preparation/pins, parent serializes sharedhost production integration. PR228 and227 parked for Phase3; IPTV admission and Indexer static-stop evidence retained, no further retries. Final full gate/upstream54/55/56 mapping/closing report follow player threshold; upstream publication remains local-only. One board commit per mergedPR; this note staged only with next such update.


## Explicit exception: finish227 and228

User requested both after the player-only direction. #227 merged1e4128ae with reviewed5f3 head and allCIpassing. #228 authorized pending currentunion/CI and full227 gate. This exception does not reopen broader Search/Q work. Player count refreshed from actual merged source; no extraction credit for metadata wiring.


## Exceptions227/228 complete

Full1e4128 actual-main gate passed with exact known failures and both native builds; #228 merged408cd894 after exactfreshCI and union acceptance. Search5879, player11538:2038remaining to9500. Takeover -223host/+29wholeproduction earns zero player/stage credit. Freeze resumes; onlyplayerPhase2 work. Gate evidence in debrify-c0-post-225-226-227-gate/.dart_tool/main-gate/REPORT.md. Counter1 aftergate.


## Media candidate b220 rejected — September 7

Green origin pin982e24dd (four public-host mocked-terminal cases) retained. Unapplied two-transaction design b220 preserved as rejected evidence: host-341, owner575, whole production+234;36 inbound and23 outward interface members, including10 single-field compatibility bridges. Source body/notification refinements and57-writer/24-group accounting accepted, but coupling cost failed simplicity review. No production change applied. Next work is loader/identity boundary and additional origin admission, not callback regrouping or an automatic broader move.


## G4-3 reviewer follow-ups — September 7

PR232 Decisions2/3 are excluded from the sorting deduplication. Dead series-arrange methods/arms are proposed for a separately evidenced Phase3 deletion, retaining the enum compatibility value; reachability still requires verification. Diverged PikPak/Premiumize/playlist sort variants remain unchanged and require per-host pins and explicit difference accounting before any G4-4 convergence. #227 is already merged. Neither follow-up is currently assigned or credited to the player target.


## G4-3 landing provenance

PR232 merged ab4e8323 after user authorized landing. Pin-before-move ancestry28db8762→e89c54a9 and independent old-origin2PASS/current66PASS are verified. Historical pre-move execution and mutation excerpts remain author-reported, not independently timestamp-proven. Case-fold/non-Season regex/unnumbered-folder comparisons are source-preserved rather than adversarially pinned. Exact final merge tree a56df4d6 preserves all four accepted payload blobs and all outside main paths. No additional runtime was repeated.


## Reviewer wave preserved quirks and clearing lanes — September 7

These are author-reported preserved behaviors pending independent source/pin review, not new fixes:

- R1: malformed live-transfer chunk failure before `failedBuffer` assignment leaves the buffer until stall deadline; failure notices surface after batch idle gap. Keep unchanged.
- R2: request outcome cache keeps first answer, including early rejection, for five minutes; process-wide authorization timestamp makes refusal-test ordering significant. Keep unchanged; no reset seam silently added.
- D1: `DetailCastTile` can overflow the92px rail by2px on wrapped names; single-word fixture does not pin overflow. `DetailAmbientStill` is dead in shipped layouts but reachable via model hook. Scroll anchor toTop runs on descendant focus with active gate. Preserve and label finite coverage.
- D2: MDBList sheet uses default Material chrome unlike themed Trakt/Simkl. Null Simkl/MDBList status still resolves via finally; null Trakt result retains earlier status. Listed mechanical rewrite needs per-body lifecycle/notification verification, not automatic acceptance.
- T3: smallest ranking sinks unknown sizes; directValidationBudgetForRules ignores argument and returns5; pack curation strict while ordinary curation falls back.18 test-facing forwards (~44lines) explicitly expire in queued T3-F owning service plus quick_play_rules_test/filter_ladder_test/torrent_playback_service_strings_test and origin pin. No lib callers claimed; verify before deletion.
- I1/I2:111-line target shortfall is accepted with clearing slice I3 Phase3. Retained dead classes are described as208lines in I1; these are different accounting measures. I2 unreachable railTV/non-touch branches and focus-stage callback plumbing join I3 after reachability verification; no revived layout. Live stage getters preserve startup suppression/rearm semantics.
- R3 afterR2 clears busy and legacy-consent dialog layering together; not part of R1/R2. T3 CODEMAP hunk accepted within lane scope.


D2 correction to intake quirk report: independent actual-origin comparison found MDBList sheet DID provide backgroundColor/showDragHandle/isScrollControlled; fc8 omission is a regression, not a preserved quirk. Prior entry is author-reported and superseded by this finding. Restore exact origin arguments and correct PR before merge.


## Complete player inventory and orchestrator decisions — September 7

**Inventory complete at fixed bde119f5: all 11,034 physical lines accounted for exactly once, zero gaps or overlaps.** Dart parsing reports zero errors. The 2,126 structural records include nested locals/callbacks and duplicate field/group representations; they are not additive line savings. There are 10 classes; the main State occupies 10,335 lines and its build method 1,191. References are syntax plus human source review, not a claim of complete alias analysis.

**Current merged result:** PR #244 landed as f65486a3, tree b9fcd2ec68347ac8f81882337de2d0b3f125ef41. Player 10,895; remaining to 9,500 is 1,395. Its 139-line reduction is counted once and never added to inventory forecasts. Whole production +8; origin and post-move two-case pins and independent two-case review passed, supporting guard suite12 passed, fresh CI test/goldens/native all passed. Analyzer430/449 with zero new issues after exactly three old warning-path substitutions; layering53/77 with no added/removed IDs. Scoped61 inherited issues still returns1, not a zero-issue claim. No new device smoke.

### Final decisions and execution order

1. **First: navigation/shuffle policy, pin before move.** Select the five synchronous algorithms at3338,3402,3536,3563,3585 for a bounded contract and actual-screen origin pins. Own only the shuffle bag/enable policy; retain active playlist/index/cache/URL and playback commands in the host. Proposed contract: six operations and one flag, up to five existing typed inputs per operation, same borrowed Random, no callback into State. Preserve the actual40% main-file threshold despite its stale70% comment, unknown sizes, next/previous asymmetry, empty-list early returns, lazy series reads and random draw ordering. Existing navigation test copies do NOT qualify. Estimated host reduction145–160, new owner220–245, whole growth60–100; these are forecasts, not accepted Leaves or permission to move now.
2. **Before larger flow moves: resolve playback identity and adoption ownership.** Treat the lazy SeriesPlaylist cache, active list/index/URL, source overrides, identity token, metadata completion and resets as one explicit writer map. Keep initialization, openMedia and route lifecycle in the host while designing named adoption/reset operations. No State proxy, per-field mirror, eager snapshot or repeat of the rejected59/72-member Media design. The prerequisite output is an origin-read/write and command contract with counted capabilities and exact notification slots; only then choose separate move slices. This work remains Phase2 preparation, not silently deferred to meet a number.
3. **Episode display projection follows that read contract.** Title/subtitle/enhanced metadata at3114–3335 is a cohesive218-body-line opportunity, but the lazy series getter and guide/source precedence must keep their read timing. Prefer explicit existing data inputs; if a value object is necessary, its full field surface and separate prerequisite must be reviewed. No forecast of218 net lines: host bindings and destination cost are not measured.
4. **PikPak retry/metadata monitoring is the next substantial state-machine candidate.** Two bodies total428 lines. Own retry token/counter/status/message together; preserve every invalidation site, wall-clock polling, old-token UI clearing, six-attempt schedule and live player/header reads. Before production work require real-host positive/error/cancel pins and a reviewed contract (currently roughly10 expanded dependencies). Provisional host reduction368–398/new owner450–510/whole growth52–142 is unmeasured and may fail the interface review. Do not normalize behavior or begin the deferred cross-service fallback feature.
5. **Converge subtitle application on the existing owner only after cache/token identity is assigned.** The six application bodies at10404–10529 have real policy differences: menu and legacy tails, late failure reporting and guarded persistence must remain distinct. Component tests are insufficient. Do not create another command-only menu controller or claim the rejected design became acceptable merely by regrouping callbacks.
6. **Rendering comes after observable state ownership.** Keep the native texture/keys, framework context, lifecycle, focus root and necessary live adapters. Review HUD, controls and overlay composition separately after their state owners exist. A57-input Stack move or a State interface hidden inside a model is rejected. The goal is fewer shared dependencies, not an identical build method in another file.

**Explicit keep/backlog decisions:** no standalone sleep scheduling extraction (under69 gross lines for four callbacks), tiny native-video configuration consolidation, random tile-only move, small formatting utility sweep or forced removal of necessary framework adapters. Native audio/output/session lifetime changes need separate platform evidence and remain Phase3 backlog. Touch gesture ownership and banner-only ownership are secondary opportunities, not additional active lanes; they require real-host pins and measured interface benefit. Existing PiP, recorder, zap, resume, tracker and diagnostics delegation does not mean their host orchestration has disappeared.

**Budget/target accounting:** navigation's forecast alone leaves1,235–1,250 lines. If the retry candidate also survives review, the two disjoint forecasts total513–558 and leave837–882. That remainder is NOT covered by an accepted design today. Do not sum gross spans, include overlapping projection/identity/overlay work twice, or promise completion from these estimates. The target stays9,500; this inventory exposes the architecture work needed to reach it honestly. No reliable hour/token estimate is available from source size.

### Decision coverage by region

The region ledger below is exhaustive at the fixed source. KEEP means retain current ownership; PREDECESSOR names work required before a move, not an authorization; CANDIDATE requires contract/pin admission. Worker suggestions are subordinate to the decisions above: sleep/banner/touch micro-extractions are not selected, guide acquisition remains host-owned, and all244 sites are already completed. The detailed source/async/test evidence is retained in the four linked local inventories.

#### Source band 1–2750

- **L1–115: Imports and compatibility exports — KEEP host.** 0 new inputs/outputs; retain exact directives until an actual body owner removes its last use. No configuration relocation lane. Chosen net0.
- **L116–132: Validation exception and screen documentation — KEEP host.** Exception has0 constructor inputs and one instance output. Retain with validation command authority; net0.
- **L133–302: Public VideoPlayerScreen launch API — KEEP host.** All existing formal parameter counts and return types in AST ledger. No new API:0 new inputs/outputs,0 glue/new owner/net. Public API cannot be retired by packing fields into a bag.
- **L303–386: State root, native instance and media identity storage — NEEDS predecessor.** Rejected whole-media state bridge must not be recreated. A predecessor must assign ALL writers before moving cells. Existing adapter/config surfaces enumerated individually. No proposed interface/count/net earned; chosen no move net0.
- **L387–442: Playlist item payload and lazy SeriesPlaylist cache — NEEDS predecessor.** Payload could take4 scalar inputs plus playlist eligibility and return nullable map, but33lines is not cohesive cache ownership. Cache move needs list/identity owner; no new holder/forwarder. Gross55, net unmeasured/not proposed.
- **L443–483: TV focus, timeline eligibility, scrub binding and banner adapters — NEEDS predecessor.** V1-10 rejected composition/menu protocols remain rejected. Need coherent rendering/focus authority rather than callbacks perleaf. No new contract; net0 retained. Scrub binding is ALREADY delegated, no new credit.
- **L484–514: Gesture, playlist progression and guide state — NEEDS predecessor.** Separate pure traversal policy may consume list/index/mode, but active identity writes stay host. No field relocation before full writer map; interface/net unmeasured. No duplicate Cicero candidate.
- **L515–618: IPTV live recovery integration — NEEDS predecessor.** KEEP existing recovery owner. A coherent retune command requires media/recording authority predecessor, not3 more callbacks. No proposed new inputs/output/glue/net;0 move now.
- **L619–721: Dock preferences, geometry generations and measured layout — NEEDS predecessor.** 9 signature components, one string output; moving that formatter alone is trivial. Larger rendering-owner proposal57inputs was rejected; need state+UI owner with complete writers. No new contract/net estimate beyond no move0.
- **L722–758: Lifecycle subscription, subtitle diagnostics and recording forwarders — ALREADY delegated.** 4 existing recording facades:2 getters, toggle0args, stop1optionalarg; retain until peer contract changes. No facade-deletion credit or inferred future-join correction. Host lifecycle needs broader predecessor.
- **L759–828: Source overrides, captured menu identity and effective-value adapters — NEEDS predecessor.** No shared-state bridge or eager snapshot just to remove getters. Require complete workflow owner; exact existinggetter I/O in declaration ledger; no proposed new surface/net.
- **L829–855: Skip-provider settings and fetch-session integration — ALREADY delegated.** Existing owner bindings retained. No2nd fetch/session owner. Any host flag move requires media authority predecessor;0 new extraction credit.
- **L856–897: Subtitle cache, native autosync resources and pill state — NEEDS predecessor.** Do not split owner/cachecell or move only pill to inflate reduction. Need full presentation+subtitle lifetime decision. No new interface/net quantified; currentnet0.
- **L898–954: Validation/readiness, resume and peer-owner bindings, playback clocks — ALREADY delegated.** Keep3 existing framework adapters; no forced removal. Whole-media rejected bridge remains rejected. Transition940 ALREADY MERGED244, not freshcredit. No new contract/net.
- **L955–977: Subscription handles, decoder ownership and buffering notifier — NEEDS predecessor.** Event-binding ownership needs explicit authority/retirement contract (Cicero map); no generic callbackbag or duplicate decoder service. No netestimate for unadmittedboundary.
- **L978–991: Gesture starting values and delegated presentation/transport — ALREADY delegated.** No configuration-field relocation. Preserve currentowners and direct readtiming; 0 new inputs/outputs/credit.
- **L992–1016: Sleep countdown and stop-latch declarations — KEEP host.** Scheduling-only69gross beforeglue for4callbacks/7publicmembers rejected. Preserve SLEEP-SCHEDULING-CANDIDATE-DEBT.md; no furthermicroiterations or netcredit.
- **L1017–1032: Launch orientation latch and synchronous portrait preference — KEEP host.** One existinggetter/fact plusstate. Not a worthwhile standaloneowner; net0.
- **L1033–1055: Rainbow transition state declarations — ALREADY MERGED244.** Alreadyreviewed host-139/new147/net+8 acrosswholefile, not bandrepeatedcredit. Two constructorcallbacks/9commands/5outputs. Merged f65486a3; no new candidate.
- **L1056–1090: Dynamic title, tracker adapter and start-offset arithmetic — ALREADY delegated.** Offsetutility possible3inputs(duration,maxpercent,Random) and2inputs(duration,percent), eachnullableDuration output; only25gross so no standalone move recommended. Tracker alreadydelegated, net0 newcredit.
- **L1091–1291: State initialization and lifetime wiring — KEEP host.** Constructorobjects hide capabilities unless counted; percall inputs/outputs andcallbackrecords in AST. Keepcompositionroot; moving201lines assetupclass merely relocatesconfiguration. Net0 chosen.
- **L1292–1357: Skip settings, completion thresholds and tracking policy — NEEDS predecessor.** No prefs configuration relocation. Need completion command/cell authority covering crossband mark/check methods. Inputs/outputs unmeasured pendingthatdesign; no netclaim.
- **L1358–1457: Skip request identity and display synchronization — NEEDS predecessor.** Could isolated purefacts function consume at leastsettings/readiness/transition/duration/identity/episodeprovider facts, but requires captureorder specification; no rejectedMediaStateproxy. No newcontract/netcount until predecessor.
- **L1458–1473: Skip button command — KEEP host.** 13gross wouldneed numerous effectcallbacks; retainone concretecommand, net0.
- **L1474–1537: Persistable position, episode identity and tracker forwarding — NEEDS predecessor.** Moving accessor bundle could hide sharedmutable authority. Keep2forwarders; need identityowner predecessor. No newnetcredit; offset/helperpurity mustnot be assumedfromgetter syntax.
- **L1538–1610: External audio and Android effects session lifetime — Phase3.** Cohesiveaudio resourceowner conceivable but requires genuine platform/sessionorigin andorderedrecreation proof. Nativehold meansno move now; I/O/netunmeasured, notconfigurationcredit.
- **L1611–1695: Video output lease — KEEP host.** Resourceboundary may move only with fullconstruction/disposalauthority. Isolatedleasewrapper addsnothing;0 newcontract/net.
- **L1696–1725: Native player instance construction — KEEP host.** Existingrendererdecision explicitly retainedconstructionhost. Oneformal renderer input butmanyoutput resourcewrites; do not call oneinputpurefactory. No newowner/net.
- **L1726–1875: Autosync integration and transient pill state machine — NEEDS predecessor.** Meaningfulsessionowner wouldneed borrowednative plusposition/playing/offset reads, offsetcommand,noticeUI andpathlifetime; >=6capabilities beforeUIbindings. Net unmeasured; don't propose tiny80linepillowner orsplitcache without predecessor.
- **L1876–1972: Serialized live passthrough and audio setup — Phase3.** Do not count configurationrelocation. Nativecommand/lifetimeowner requires meaningfuloldhostplatformadmission andcachedstatewriterdecision; potential~74methodlines butnet/I/Ounmeasured, no move now.
- **L1973–2039: tvOS remedy binding and ready presentation — NEEDS predecessor.** Keepnativebinding; presentation-once algorithm couldjoinfutureUIowner onlywithfocusedlifecyclepins. No newstatebridge orpureconfigurationmove; netunmeasured.
- **L2040–2427: Initial playback transaction — NEEDS predecessor.** Do not transplant388lines behindwholeMediaState bridge. Need existingloader/sharedidentityauthority map andpubliclaunchproduceradmission first; actual inputcapturecount large/unmeasured, outputs mutatehost. No materialnetclaim withoutbodymap.
- **L2428–2629: Player event subscriptions and renderer cancellation bridge — NEEDS predecessor.** _notifyRendererStateChanged isexistingnecessaryframeworkboundary; no facadedelcredit. Need completeeventauthoritycontract, notcallbacksoneperlistener. Interface/netunmeasured; ALREADY MERGED244handledseparately.
- **L2630–2693: Decoder parameter and native observer integration — KEEP host.** No worthwhilepuredecoderboundary: only2dimensionfallbacklinespure. Moving62grossrequiresauthority/callbacks, soKEEP; no newowner/input/output/net.
- **L2694–2750: Media generation and serialized network tuning (crossing to2776) — NEEDS predecessor.** Potentialcohesivequeue+defaultslifetimeowner onlyafterinstance-reset/nativeproducer contract: current51methodlines+3fields beforeglue,4formalinnerinputs(platform,tuning,live,generation), requireslivegenerationguardcapability andstate/resetops. Owner/glue/net unmeasured; notconfigurationrelocation ornewlane. Crossingownedhere, adjacentband starts _openMedia2778.

#### Source band 2751–5500

- **L2778–2871: Media-open choke point — KEEP host.** Retain the choke point; moving it needs authority over live player replacement, resume and native options. A callback exposing the whole open algorithm simply exports the host. Network queue belongs to adjacent band1, not additional band2 credit.
- **L2873–2902: Release diagnostic bridge — KEEP host.** Single input String / void output already narrow. A standalone sink would move30 lines with another import/dispatch dependency and no state reduction; retain.
- **L2904–2924: Widget update lifecycle — KEEP host.** Lifecycle override remains at host; extracting a field synchronization callback would retain the same authority.
- **L2927–2959: Readiness polling adapters — KEEP host.** Each zero-arg Future<void> helper already small. Moving introduces a live-duration callback or shared state; do not unify the budgets.
- **L2937–2948: Subtitle failure toast — KEEP host.** One String input/void output; context UI effect should remain at host rather than a presentation callback bag.
- **L2962–2993: Last-played episode lookup — NEEDS predecessor.** Potential colocated progress lookup adapter:1 SeriesPlaylist argument -> Future<Map?>, zero callbacks and no host capture. Must preserve after-await live object read; standalone32-line relocation has small value.
- **L2995–3086: Completion routing/auto-advance — KEEP host.** Cross-domain orchestration remains host; sleep is separately owned/delegated and must not be absorbed. No candidate input bag or line credit.
- **L3088–3105: Transition start — ALREADY delegated / MERGED #244 after fixed base.** Already merged #244; no new opportunity credit. Its precise site substitutions are recorded separately in transition-sites.json.
- **L3108–3335: Episode title/subtitle/OTT projection — NEEDS predecessor.** Possible display projection after exact live-read input model is justified. Existing roots include playlist, index, catalog title/season/episode, channel lists/index, guide state, dynamic and widget fields; no bounded smaller interface measured. Avoid replacing219 lines with a bag.
- **L3338–3646: Synchronous traversal and shuffle choice — MOVE candidate.** Candidate6 operations(next,previous,mainGroup,pick,setContinuousAndClear,clearBag)+1 read-only flag; synchronous typed inputs list/index/series/viewMode plus borrowed same Random, no callbacks/host reentry. Exact lazy getter timing must stay in caller adapters. This is a candidate only, no move/pin authorization.
- **L3432–3534: Shuffle menu/intents — KEEP host.** Keep UI and load orchestration; conditional later replace bag/flag mutation with B11 named calls at same slots. No menu workflow repetition from rejected design.
- **L3649–3674: Navigation availability — KEEP host.** Retain two narrow bool queries until complete traversal/guide authority is decided; do not merge into pure B11 if it drags service/launch policy.
- **L3676–3679: Buffering reset — KEEP host.** Four-line adapter; moving alone yields no useful ownership benefit. Merged transition does not automatically own buffering.
- **L3682–3848: Next episode orchestration — PREDECESSOR: identity/adoption contract.** Rejected59-member Media and72-member loader extension remain rejected. Do not move this whole body as a callback into an owner; requires independently closed acquisition+load authority first.
- **L3853–3923: Series next pop handoff — KEEP host.** Could only move with route-lifetime handoff owner, requiring context command/latch and live identity; not a pure next-index helper. Keep host pending proof.
- **L3926–3942: Channel directory initialization — KEEP host.** 17 lines combining parsing and initial identity mutation; extracting parser alone would leave original owner and add output adoption glue.
- **L3945–4107: Subtitle style load/change/native offset — KEEP host.** Do not fold into renderer composition or menu owner: persistence/offset/manual-auto semantics have different lifetimes. Existing coordinator predecessor needed for material contraction.
- **L3964–4014: Dock geometry/preference adapters — KEEP host.** Cannot move as one pure metric without separating real panel-existence computation from building. Pure calculator would need resolved visibility/style/extent/inset but change host reads unless pinned; no new proposal here.
- **L4016–4071: Startup preference acquisition — KEEP host.** Initialization prerequisite for renderer/audio sessions; splitting into frozen facts or earlier constructor reads would alter live/config order. Already peer-owned policies are retained, not moved again.
- **L4113–4177: Subtitle sync overlay/focus — KEEP host.** Leaf widgets already separate. Moving acquisition callbacks exports existing host policy; keep until coherent sync workflow owner with explicit evidence, not a generic menu bag.
- **L4180–4197: Channel guide visibility — KEEP host.** 15 lines of route UI coordination; do not move just for count.
- **L4204–4290: IPTV source-sheet adapter state — NEEDS predecessor.** Potential source adapter should be folded into actual IPTV session authority, not independent mirroredindex object. Hash is existing Dart URLhash convention, not guaranteed stable crossprocess. Preserve one-line delegates explicitly; no retirement claimed.
- **L4305–4352: Settled last-live-channel persistence — NEEDS predecessor.** A real debounce owner is plausible with notifyPlaying/close and live channel/playing/sourceId reads+persist sink (~4capabilities). But needs lifecycle origin before candidate; net small, not already-approved74retention closure.
- **L4360–4462: IPTV series eligibility/audio preference — NEEDS predecessor.** Eligibility functions remain cheap host queries; meaningful audio-memory owner would require 5+live dependencies and borrowed track commands. Need capture/apply race origin; no wholesale session grant.
- **L4469–4494: IPTV watch registration adapter — KEEP host.** 1channel input+live launch sourceId ->Future<void>; could join a future IPTV boundary, but moving26lines standalone adds adapter without reducing authority.
- **L4497–4697: IPTV channel switch transaction — NEEDS predecessor.** Merged244 (after fixed bde) removes only transition portion. Another whole-switch closure/broad host proxy rejected; need real tune authority contract across recording/zap/currentmedia before extraction.
- **L4703–4756: Live candidate validation — NEEDS predecessor.** Possible terminal probe module only with exact opener, player-stream and recording sequencing admission. Do not unify with before-open VOD arming; no input contraction measured.
- **L4771–5067: VOD direct/probe validators — NEEDS predecessor.** Potential coherent readiness-probe boundary AFTER explicit event/cancellation contract. Needs live renderer reads; no frozen mode facts, no forced common validator. Surface estimate withheld until exact authority design; cannot claim296gross as net.
- **L5073–5328: Startup ranked failover/adoption — PREDECESSOR: identity/adoption contract.** Same shared authority problem as rejected59/72protocol; this body is actual identitywriter, cannot leave behind while claiming closedowner. Need genuine acquisition+adoption dependency reduction; no repeat naiveMedia design.
- **L5330–5352: Binding commit and diagnostic formatter — KEEP host.** Two unrelated narrow adapters; splitting22lines would not be a cohesive owner. Preserve async Future and nullablecallback semantics.
- **L5354–5365: Startup gate UI publications — KEEP host.** Two named publication commands are host boundary; no standalone state bag, no genericsetters.
- **L5369–5424: Source sheet acquisition/dispatch — PREDECESSOR: identity/adoption contract.** RejectedMedia evidence retained: shared identity and hostloader backedge mustnotbe replaced by genericsetters/Stateproxy. Keep until authority redesign; no new pins authorized.
- **L5431–5480: Manual live-source switch — NEEDS predecessor.** Cannot reuse VOD source-switch policy. Needs B27/B28 authority agreement; merged244 (after fixed bde) substitutions not new credit.
- **L5482–5739: Playlist source transaction crossing band — PREDECESSOR: identity/adoption contract.** b22059-member/net+234 and59->72loader extension explicitly REJECTED. Moving258lines while retaining loader/validator and identitywriters needs reverse bridges. Keep host pending the Phase2 identity/adoption contract; the rejected design remains deferred. Do not repeat that design or count crossing lines twice.

#### Source band 5501–8250

- **L5501–5739: Inbound playlist-source transaction — NEEDS predecessor.** Do not repeat rejected Media b220: 59 surfaces, host-341/owner575/net+234; loader expansion59→72 also rejected. No new interface/net estimate; parent boundary decision needed.
- **L5741–5910: Direct source transaction — NEEDS predecessor.** Retain host until cohesive identity/transaction boundary avoids reentry. Existing method2 parameters; actual host dependencies counted in JSON, NOT a proposed two-input API. Rejected b220 accounting applies; new glue/owner/net unmeasured.
- **L5914–5988: Stremio guide capability/projection helpers — KEEP host.** Existing parser1 input/nullable-list output and projection3 inputs are not a substantive independent ownership boundary. Moving parsing alone is tiny relocation; moving guide state requires shared overlay ownership. New owner/glue/net unmeasured, no credit.
- **L5990–6149: Stremio channel and next-slot transactions — PREDECESSOR: identity/adoption contract.** A coherent channel session might own metadata and outstanding duration subscription, but cancelling it now would change behavior. Current13-argument switch +1-option next method already substantial. Must inventory caller facts and pin before choosing owner; inputs/outputs/glue/net for move unmeasured.
- **L6152–6420: Debrify TV direct/next channel transactions — NEEDS predecessor.** Potential shared channel ownership needs channel state + commit boundaries, not extract duplicate map parsing only. Preserve differing id/next behavior. Proposed interface and net unmeasured; broad Media/renderer proxy excluded.
- **L6423–6455: Previous episode command — KEEP host.** 33 gross lines, no autonomous state. A forwarding/controller split would add command dependencies without owning algorithm; keep caller until episode navigation predecessor. New owner0 while kept; no reduction credit.
- **L6458–6560: Local completion policy and writes — NEEDS predecessor.** Candidate only after reset/identity ownership predecessor:3 existing bodies98 gross excluding separators; existing0arg methods hide live reads. Must own3 latches +2 thresholds with live identity/position inputs and two persistence effects. Exact ports/glue/owner/net unmeasured; do not count it as accepted move.
- **L6568–6585: Failure transition adapter — KEEP host.** Keep precise host adapter slot after merged delegation; do not extract skip readiness with transition. Existing18 lines; owner148/host-139/net+9 are WHOLE #244 candidate prior accounting, not band subtotal or new proposal.
- **L6587–6788: Playlist load orchestration and unlock forwarding — NEEDS predecessor.** Resolver ALREADY delegated algorithm, retain bounds/shortcut adapter. Loader inclusion was explicitly rejected59→72 interfaces (+16/-4) and must not be resurrected as broad owner. Body186+15=201 measured; no accepted newowner/glue/net estimate.
- **L6796–7225: PikPak metadata monitoring and retry ownership — MOVE candidate.** Source-feasible option only, NOT move authorization: own4 fields, expose play/cancel +3 UI outputs (5 members); borrow live mounted,duration,isPlaying,player-state duration/playing,headers plus open/notify/failure/next effects (10 expanded dependencies, not one bag). Existingmonitor3/play5 arguments. Measured bodies428 gross; provisional host glue/token sites30–60, owner450–510 => host Leaves368–398 and total growth52–142, UNMEASURED forecast not credit. Parent may reject cost; actual interface sketch/origin admission required.
- **L7228–7437: Metadata preload, subtitle retry and durable enrichment — NEEDS predecessor.** Do not return to rejected loader/identity bridge59→72. Requires cohesive identity owner and lifetime origin admission; existing helper inputs0/2/0/1/1 hide widget and services. Body total measured in manifest; ports/newowner/glue/net UNMEASURED. Preserve API compatibility of already-moved metadata loader.
- **L7440–7498: PiP platform adapters — ALREADY delegated.** Keep small adapters: existing service is boundary; new owner would need lease identity +5 live values +3 host UI/actions. No substantive reduction, newowner0 while retained. Six methods not six independent algorithms.
- **L7505–7581: Foreground intent, live rejoin and display lock — KEEP host.** Route/platform facts belong host, cannot mirror startup/PiP state into broad lifecycle controller.3 methods65 gross; proposed ports/net unmeasured and prior broad-state bridging rejected. Keep until a justified cohesive lifecycle decision.
- **L7583–7709: Route teardown plus autosave handle — KEEP host.** Keep orchestration at host; owners retain their own cleanup implementation. No dispose-all helper/callback bag.127 physical span through field incl separators; measured declarations available. No extraction budget/new owner; lifetime hazards forbid cosmetic reduction.
- **L7727–7847: Television transport widget assembly — KEEP host.** 121 gross widget-assembly lines; moving it alone is not ownership. Prior menu57-input and complete-menu27ctor/net+236 REJECTED; do not revive a25/30member factory. Host glue/newowner/net unmeasured, no credit.
- **L7856–8055: Overlay BACK, guide dispatch and TV input — KEEP host.** Preserve existing owners; a coordinator with overlay boolean mirrors/State proxy is rejected design. Exact declaration totals/refs recorded. New input/output/glue/net unmeasured; no standalone tiny boundary.
- **L8057–8193: Touch double-tap and pan gesture session — BACKLOG / not selected.** Potential cohesive touch-session only after actual public gesture admission. Own6 recognition fields +ripple and2 notifier lifetimes; borrow geometry,duration,position,volume,controlsVisible,mounted plus seek/volume/brightness/scrobble/notify. Proposed11 expanded inputs/effects +3 UI outputs +4 event commands; NOT accepted interface.134 body lines; speculative host glue25–45/owner155–190 => Leaves89–109, total growth46–101 UNMEASURED, may fail simplicity. Do not apply.
- **L8195–8225: Formatting, explicit play and manual-selection timer — KEEP host.** format ALREADY delegated one-line adapter. Other commands remain host composition until genuine ownership transfer.1+15+12 gross; new owner0 while kept; no host reduction claim.
- **L8231–8267: Sleep label and menu entry crossing out — KEEP host.** Retain prior rejection: scheduling<69gross/4callbacks; fullpolicy cleanup weak.3 declarations34 body lines incl full20line crossing sheet; no new owner/net credit. Cross-band8251–8267 context in Locke only.

#### Source band 8251–11034

- **L8251–8268: Sleep sheet tail; START8248 belongs band3 — KEEP host.** No independent move or credit; parent reconciles the crossing. 0 new inputs/outputs.
- **L8269–8335: Sleep selection/countdown/cancel/fire/toast — KEEP host.** KEEP per parent explicit scheduling-only STOP: <69 gross / four callbacks does not establish a substantive new owner. Prior alternative estimate withdrawn. Current section67 lines includes comments/blanks; no timer-only move. Zero proposed new ports/owner/glue/net. Preserve lifecycle/save-before-pause exactly.
- **L8336–8403: Presentation commands and native orientation/gesture geometry — KEEP host.** KEEP event wiring. No new helper-owner just to forward existing presentation methods; new inputs/outputs0, host/net0. Orientation is native boundary, not proven by desktop speed pins.
- **L8404–8439: Native subtitle configuration and video texture composition — KEEP host.** KEEP texture/renderer composition until native owner boundary explicitly granted. 0 new ports/net0; no duplication of text/bitmap placement.
- **L8440–8447: PR244 ALREADY MERGED transition overlay facade; fixed-source coordinates — ALREADY delegated.** ALREADY MERGED #244 f65486a3. Fixed-source full-file11034 unchanged in this inventory; actual postmerge10895 =11034−139. Band adjustment must not simply deduct139 because moved declarations span other bands.
- **L8448–8491: Stremio loading overlay passive composition — NEEDS predecessor.** Group with overlay composition after Media owner, not another helper-only PR. Unmeasured 40–55 owner lines, 3–8 host wiring, 30–38 host reduction, whole growth likely. Proposed2 data inputs/1widget output.
- **L8492–8587: Debrify identity/banner/timer/clock with existing IPTV delegation — BACKLOG / not selected.** Candidate coherent Debrify banner session, but requires clock visibility and disposal/overlay entry sites across bands; 3commands raise/arm/hide + visibility output, roughly5 live inputs identity/overlay/controls/transition/duration and2 effects commit/clock. Unmeasured owner90–120,hostglue15–25,bandreduction45–65. Existing IPTV delegation must stay one owner.
- **L8588–8654: Media episode availability, synthetic guide caches and pack policy — NEEDS predecessor.** NEEDS Media ownership decision. Lower-level services delegated, actual host orchestration NOT extracted/completed. Availability, three local fields, synthetic cache and pack coverage remain host-owned. No duplicate owner or credit. Candidate state/input/output/cost unmeasured pending complete Media boundary.
- **L8655–8823: Media existing/episode/pack candidate ladder — NEEDS predecessor.** NEEDS Media ownership decision. _fetchAndPlayEpisode111 lines and _tryEpisodeCandidate49 lines still own actual ordered admission/guard/commit orchestration here, not in fetcher/resolver. Lower-level service calls are not ownership closure. Provisional cohesive owner160–210, hostglue10–25, hostreduction130–150 UNMEASURED and not a release; full cross-band switch dependency must settle first. Two current callable inputs total7 (2+5), async outputs Future<void> and Future<bool>; real boundary also needs state/commit capabilities, not a seven-input snapshot.
- **L8824–8882: Adjacent episode and public playlist sheet assembly — NEEDS predecessor.** NEEDS Media identity/playlist owner first; public PlaylistSheet presentation may remain host assembly. Proposed data1model+selection callbacks2, but metadata async completion/lifetime must not be flattened into precomputed snapshots. Cost unmeasured, hostglue10–20 vs owner50–75, reduction25–40 conditional.
- **L8883–8899: build root lifecycle/context/Focus wiring — KEEP host.** KEEP host. 1BuildContext input→1Widget output;0new/net0.
- **L8900–9230: Public keyboard dispatch/overlay priority/native fullscreen — NEEDS predecessor.** NEEDS whole input/transport ownership consolidation; do not extract a key-switch accepting dozens of callbacks. Frozen live native/window/focus receiver sites retained until coherent session interface. Current callback2args→KeyEventResult; candidate port count/cost UNMEASURED, no removal forecast or padding.
- **L9231–9333: Static stack texture/startup/transition composition — KEEP host.** KEEP native texture. Passive startup view may be grouped later with startup owner, not moved with ownership disguised as layout. Candidate0here;net0.
- **L9334–9548: Seek/volume/aspect/speed/subtitle/reconnect/buffering HUD composition — NEEDS predecessor.** NEEDS overlay composition as one cohesive presentation owner after notifiers; potential 7display inputs +1startup input and retained one-model memo, Widget output. Unmeasured owner200–240,glue20–40,hostreduction170–195. Phase2V1-10 says overlay stack last. Do not add render seams.
- **L9549–9578: Gesture layer event wiring and live hit testing — KEEP host.** KEEP host input wiring. 0newports/net0; individual callback bodies are in declaration appendix.
- **L9579–9819: Controls and TV controls, measurements and transport callbacks — NEEDS predecessor.** NEEDS final transport composition after Media/track/sleep owners. CurrentControls API is large; moving construction alone into callback bag is not eligible ownership. Exact borrowed symbol count generated; candidate interface UNMEASURED. Keep host until bounded program/session replaces policy; no numericcredit.
- **L9820–9867: Skip public button layout around existing skip owner — ALREADY delegated.** ALREADY delegated fetch/UI. KEEP finite layout until overlay composition; no newskip service/nativebehavior. No incremental owner credit.
- **L9868–9954: Debrify/IPTV fade-unmount and PikPak dock-aware overlays — NEEDS predecessor.** NEEDS banner+Media predecessors then shared presentationassembly. Not genericOpacityhelper. Unmeasured owner90–110/glue15–25/reduction55–70; 5data+2endcallbacks plus live dock predicate, widget output provisional.
- **L9955–10054: Guide/source/menu/sync overlay stack and live source assembly — NEEDS predecessor.** NEEDS V1-10 last-stage composition after Media/session closures. Moving all with 20+callbacks is rejected shape, not netclosure. Exact dependency list generated; 0approvednewports/no measurednet.
- **L10055–10085: Mouse visibility builder and any-overlay getter — KEEP host.** KEEP host shell, not separateowner. Getter0→bool; builder3→widget;0net.
- **L10086–10137: Live title and season/episode precedence — NEEDS predecessor.** NEEDS Media ownership decision; sharing one identity service only if exactdifferent menus/cache identity semantics retained. 2queries/0explicitargs→String+nullableSelection; unmeasuredowner45–65/glue4–8/reduction35–42. Not standalone tinyPR.
- **L10138–10316: Metadata-enriched tracks sheet and guarded subtitle-cache writeback — NEEDS predecessor.** NEEDS coordinated Subtitle+Media contract. Keep enrichment and sheet opening separate until identity capture agreed; no broadhostSession proxy. Provisional1context input, sheet multiple callbacks exactsource; owner160–200/glue15–30/reduction130–155 UNMEASURED, noauthorization.
- **L10317–10403: Menu identity snapshot/quick cached path/focus and visibility order — NEEDS predecessor.** NEEDS Menu session owning snapshots+open/close invalidation with realvisibility/focus lifecycle. 7explicitAt inputs,1quicksection,6/7snapshot outputs depending grouping; no 31closure bag. Unmeasured owner90–120/glue12–25/reduction55–70.
- **L10404–10529: Menu/legacy track apply, download token checks and persistence tails — MOVE candidate.** MOVE candidate only as cohesive existing SubtitleTrackController operation boundary with hostmenu UIeffects retained. 6methods; exact AST parameter sum is authoritative; proposed public operations audio/off/embedded/addon/legacy5, commonpersist internal. Unmeasured owner125–155/glue15–25/bandreduction85–110; do not expand tokenauthority or silentlyaddguards.
- **L10530–10612: Menu parameter assembly and captured cache key — NEEDS predecessor.** NEEDS Menu+sleep+track predecessors before passive viewcomposer. Proposeddata snapshot+5operationcapabilities not frozen spec; exact currentborrowedsymbol countprovided. UNMEASUREDowner90–115/glue15–30/reduction50–65. Avoid widgetskeleton relocation claim.
- **L10613–10639: Episode index fallback and legacy filename hash; host closing brace — NEEDS predecessor.** NEEDS identity/playlist owner; 2methods1inputeach→Episode?/String. Onecoherent batch only; standaloneutilitymove notuseful. UNMEASUREDowner20–28/glue4–6/netgrowthlikely.
- **L10640–10654: Tracker live host adapter — ALREADY delegated.** ALREADY delegated tracker. KEEP adapter for currentcontract; movingtofile needingprivateState createscycle. 1ctorinput,8getters+1methodoutputs;0new/net0.
- **L10655–10717: Renderer live host/native/UI adapter — KEEP host.** KEEP host native adapter. Mechanicalfile relocation cannot removeprivateState coupling. Current method/getter/input counts inledger;new0/net0. #244 only transitiongetterreceiver adjustment.
- **L10718–10780: Resume live host and tracker/presentation adapter — KEEP host.** KEEP compatibility adapter untilMedia identity boundary;0new/net0. Bulkgetter removal not ownership. #244 changesisTransitioningreadonly.
- **L10781–10895: Subtitle live host/cache/identity/native adapter — NEEDS predecessor.** NEEDS futureSubtitle+Media sharedstatedecision. Do not move _s proxy intoanotherlibrary. KEEP activeboundary until realstate owner canreplaceit;new0/net0 now.
- **L10896–10948: IPTV live list lookup/UI adapter — KEEP host.** KEEP host coordinator. 1borrowedhost ctor; getters/setters/actions countedexact;0new/net0. Source mapping toMedia switch requiresparentcoordination.
- **L10949–10973: IPTV recording/player/native/capacity adapter — KEEP host.** KEEP native/authority adapter,0new/net0. Device capacity grant and engineaccess unchanged.
- **L10974–11034: Passive shuffle choice tile; not a new standalone extraction — Phase3.** Phase3/KEEP untilcoherent shufflepresentation batch. 4ctorinputs incl1callback→1Widget; aloneowner≈61,host61off/new≈61 whole≈0UNMEASURED, no substantiveownershipcredit.

### Exhaustive declaration index

<details>
<summary>Every import/export, class, constructor, field and member at the fixed origin</summary>

These ranges overlap by containment (class/member); they are an index, not additive size accounting. Locals and anonymous callbacks belong to their enclosing body and are enumerated in the linked AST artifact.

- L1–1: import `../services/series_playlist_metadata_loader.dart`.
- L2–2: import `video_player/services/renderer_startup_environment.dart`.
- L3–3: import `video_player/services/renderer_coordinator.dart`.
- L4–4: import `package:debrify/services/storage/quick_play_policy_prefs.dart`.
- L5–5: import `../services/playback/decoder_diagnostics.dart`.
- L6–6: import `video_player/services/player_terminal_backend.dart`.
- L7–7: import `package:debrify/services/storage/iptv_prefs.dart`.
- L8–8: import `package:debrify/services/storage/playback_progress_store.dart`.
- L9–9: import `dart:async`.
- L10–10: import `dart:io`.
- L11–11: import `dart:math`.
- L13–13: import `package:flutter/foundation.dart`.
- L14–14: import `package:flutter/material.dart`.
- L15–15: import `package:window_manager/window_manager.dart`.
- L16–16: import `package:flutter/services.dart`.
- L17–17: import `package:screen_brightness/screen_brightness.dart`.
- L20–20: import `package:wakelock_plus/wakelock_plus.dart`.
- L21–21: import `../services/storage_service.dart`.
- L22–22: import `../services/local_playback_resume_resolver.dart`.
- L23–23: import `../services/startup_stream_policy.dart`.
- L24–24: import `../services/resume_write_guard.dart`.
- L25–25: import `../services/skip_segment_service.dart`.
- L26–26: import `../services/playback/skip_segment_session.dart`.
- L27–27: import `../services/analytics_service.dart`.
- L28–28: import `../services/pip_service.dart`.
- L29–29: import `../services/audio_effect_session_service.dart`.
- L30–30: import `../services/tvos_decode_remedy.dart`.
- L31–31: import `../services/android_native_downloader.dart`.
- L32–32: import `../widgets/recording_limit_dialogs.dart`.
- L33–33: import `../services/profiles/profile_lock_controller.dart`.
- L34–34: import `../services/tracking_source_policy.dart`.
- L35–35: import `../services/cloud/cloud_provider_registry.dart`.
- L36–36: import `../utils/platform_util.dart`.
- L37–37: import `../utils/player_audio_config.dart`.
- L38–38: import `../utils/time_formatters.dart`.
- L39–39: import `../utils/series_parser.dart`.
- L40–40: import `../utils/movie_parser.dart`.
- L41–41: import `../services/movie_metadata_service.dart`.
- L42–42: import `../models/iptv_playlist.dart`.
- L43–43: import `../services/stremio_iptv_service.dart`.
- L44–44: import `../models/playlist_view_mode.dart`.
- L45–45: import `../models/series_playlist.dart`.
- L46–46: import `../services/next_episode_service.dart`.
- L48–48: import `../widgets/player/identify_title_sheet.dart`.
- L49–49: import `../widgets/video_output_lease.dart`.
- L50–50: import `package:media_kit/media_kit.dart`.
- L51–51: import `package:media_kit_video/media_kit_video.dart`.
- L54–54: import `video_player/models/playlist_entry.dart`.
- L55–55: import `video_player/player_launch_config.dart`.
- L56–56: import `video_player/resume_controller.dart`.
- L57–57: import `video_player/player_tracker_lifecycle.dart`.
- L58–58: import `video_player/subtitle_track_controller.dart`.
- L59–59: import `../services/playback/iptv_recording_controller.dart`.
- L60–60: import `video_player/iptv_zap_controller.dart`.
- L61–61: import `video_player/services/subtitle_track_utils.dart`.
- L62–62: import `video_player/models/gesture_state.dart`.
- L63–63: import `video_player/models/hud_state.dart`.
- L64–64: import `video_player/painters/double_tap_ripple_painter.dart`.
- L65–65: import `video_player/utils/gesture_helpers.dart`.
- L66–66: import `video_player/utils/language_mapping.dart`.
- L67–67: import `video_player/utils/aspect_mode_utils.dart`.
- L68–68: import `video_player/player_presentation_controls.dart`.
- L69–69: import `video_player/player_transport_visibility.dart`.
- L70–70: import `video_player/player_scrub_session.dart`.
- L71–71: import `video_player/constants/timing_constants.dart`.
- L72–72: import `video_player/widgets/auto_sync_pill.dart`.
- L73–73: import `video_player/widgets/seek_hud.dart`.
- L74–74: import `video_player/widgets/vertical_hud.dart`.
- L75–75: import `video_player/widgets/aspect_ratio_hud.dart`.
- L76–76: import `video_player/widgets/controls.dart`.
- L77–77: import `video_player/widgets/dock_style.dart`.
- L78–78: import `video_player/widgets/tv_controls.dart`.
- L79–79: import `video_player/widgets/aspect_ratio_video.dart`.
- L80–80: import `video_player/widgets/transition_overlay.dart`.
- L81–81: import `video_player/widgets/pikpak_retry_overlay.dart`.
- L82–82: import `video_player/widgets/buffering_indicator.dart`.
- L83–83: import `video_player/widgets/tracks_sheet.dart`.
- L84–84: import `video_player/widgets/player_menu_panel.dart`.
- L85–85: import `video_player/widgets/playlist_sheet.dart`.
- L86–86: import `video_player/widgets/channel_guide.dart`.
- L87–87: import `video_player/widgets/iptv_channel_sheet.dart`.
- L88–88: import `video_player/widgets/player_guide_style.dart`.
- L89–89: import `../widgets/iptv/styles/iptv_style.dart`.
- L90–90: import `video_player/widgets/source_sheet.dart`.
- L91–91: import `video_player/widgets/stremio_tv_guide_sheet.dart`.
- L92–92: import `video_player/models/channel_entry.dart`.
- L93–93: import `video_player/services/network_tuning.dart`.
- L94–94: import `video_player/services/subtitle_settings_service.dart`.
- L95–95: import `video_player/services/media_kit_subtitle_auto_sync.dart`.
- L96–96: import `video_player/services/playback_ui_clock.dart`.
- L97–97: import `video_player/services/skip_segment_ui_controller.dart`.
- L98–98: import `video_player/services/android_renderer_startup_fallback.dart`.
- L99–99: import `video_player/services/iptv_tune_diagnostics.dart`.
- L100–100: import `video_player/services/iptv_live_recovery.dart`.
- L101–101: import `video_player/widgets/subtitle_line_picker_overlay.dart`.
- L102–102: import `video_player/widgets/skip_segment_button.dart`.
- L103–103: import `video_player/widgets/sleep_timer_sheet.dart`.
- L104–104: import `video_player/widgets/sync_stepper_overlay.dart`.
- L105–105: import `video_player/widgets/debrify_tv_banner.dart`.
- L106–106: import `../models/stremio_subtitle.dart`.
- L107–107: import `../models/torrent.dart`.
- L108–108: import `../models/android_video_renderer_mode.dart`.
- L109–109: import `../services/series_source_fetcher.dart`.
- L110–110: import `../services/scrobble/scrobble.dart`.
- L111–111: import `../utils/tv_keys.dart`.
- L114–114: export `video_player/models/playlist_entry.dart`.
- L115–115: export `video_player/models/channel_entry.dart`.
- L117–119: class `_ManualSourceValidationFailure`.
- L118–118: constructor `_ManualSourceValidationFailure._ManualSourceValidationFailure`.
- L133–301: class `VideoPlayerScreen`.
- L134–134: field `VideoPlayerScreen.videoUrl`.
- L138–138: field `VideoPlayerScreen.audioUrl`.
- L139–139: field `VideoPlayerScreen.title`.
- L140–140: field `VideoPlayerScreen.subtitle`.
- L141–141: field `VideoPlayerScreen.playlist`.
- L142–142: field `VideoPlayerScreen.startIndex`.
- L143–143: field `VideoPlayerScreen.rdTorrentId`.
- L144–144: field `VideoPlayerScreen.torboxTorrentId`.
- L145–145: field `VideoPlayerScreen.pikpakCollectionId`.
- L147–147: field `VideoPlayerScreen.requestMagicNext`.
- L149–149: field `VideoPlayerScreen.requestNextChannel`.
- L152–152: field `VideoPlayerScreen.requestChannelById`.
- L154–154: field `VideoPlayerScreen.channelDirectory`.
- L156–156: field `VideoPlayerScreen.startFromRandom`.
- L157–157: field `VideoPlayerScreen.randomStartMaxPercent`.
- L159–159: field `VideoPlayerScreen.startAtPercent`.
- L161–161: field `VideoPlayerScreen.hideSeekbar`.
- L163–163: field `VideoPlayerScreen.showChannelName`.
- L164–164: field `VideoPlayerScreen.channelName`.
- L165–165: field `VideoPlayerScreen.channelNumber`.
- L167–167: field `VideoPlayerScreen.showVideoTitle`.
- L169–169: field `VideoPlayerScreen.hideOptions`.
- L171–171: field `VideoPlayerScreen.hideBackButton`.
- L173–173: field `VideoPlayerScreen.httpHeaders`.
- L175–175: field `VideoPlayerScreen.disableAutoResume`.
- L177–177: field `VideoPlayerScreen.viewMode`.
- L179–179: field `VideoPlayerScreen.contentImdbId`.
- L180–180: field `VideoPlayerScreen.contentType`.
- L181–181: field `VideoPlayerScreen.contentSeason`.
- L182–182: field `VideoPlayerScreen.contentEpisode`.
- L183–183: field `VideoPlayerScreen.contentTitle`.
- L184–184: field `VideoPlayerScreen.resumePolicy`.
- L186–186: field `VideoPlayerScreen.iptvChannels`.
- L187–187: field `VideoPlayerScreen.iptvStartIndex`.
- L188–188: field `VideoPlayerScreen.iptvCategories`.
- L189–189: field `VideoPlayerScreen.iptvSourceId`.
- L190–190: field `VideoPlayerScreen.iptvSourceName`.
- L191–191: field `VideoPlayerScreen.iptvSelectedCategory`.
- L192–192: field `VideoPlayerScreen.iptvContentType`.
- L193–193: field `VideoPlayerScreen.iptvSources`.
- L195–195: field `VideoPlayerScreen.iptvBrowseProvider`.
- L197–197: field `VideoPlayerScreen.stremioSources`.
- L198–198: field `VideoPlayerScreen.stremioCurrentSourceIndex`.
- L199–199: field `VideoPlayerScreen.resolveStremioSource`.
- L201–201: field `VideoPlayerScreen.resolveSourceToPlaylist`.
- L202–202: field `VideoPlayerScreen.startupFailoverEnabled`.
- L203–203: field `VideoPlayerScreen.startupResolverProvider`.
- L204–204: field `VideoPlayerScreen.onStremioSourceCommitted`.
- L205–205: field `VideoPlayerScreen.onStartupSourcesExhausted`.
- L208–208: field `VideoPlayerScreen.seriesSourceFetcher`.
- L210–210: field `VideoPlayerScreen.stremioTvChannels`.
- L211–211: field `VideoPlayerScreen.stremioTvCurrentChannelId`.
- L213–213: field `VideoPlayerScreen.stremioTvGuideDataProvider`.
- L215–215: field `VideoPlayerScreen.stremioTvChannelSwitchProvider`.
- L216–216: field `VideoPlayerScreen.stremioTvNextProvider`.
- L218–218: field `VideoPlayerScreen.traktScrobble`.
- L220–220: field `VideoPlayerScreen.traktProgressPercent`.
- L223–223: field `VideoPlayerScreen.simklScrobble`.
- L224–224: field `VideoPlayerScreen.simklProgressPercent`.
- L225–225: field `VideoPlayerScreen.mdblistScrobble`.
- L226–226: field `VideoPlayerScreen.mdblistProgressPercent`.
- L231–231: field `VideoPlayerScreen.initialSubtitles`.
- L233–297: constructor `VideoPlayerScreen.VideoPlayerScreen`.
- L300–300: method `VideoPlayerScreen.createState`.
- L303–10637: class `_VideoPlayerScreenState`.
- L305–305: getter `_VideoPlayerScreenState.config`.
- L307–309: field `_VideoPlayerScreenState._tvReleaseLogChannel`.
- L310–312: field `_VideoPlayerScreenState._androidPlayerDiagnosticChannel`.
- L314–314: field `_VideoPlayerScreenState._player`.
- L318–318: field `_VideoPlayerScreenState._playerCreated`.
- L323–323: field `_VideoPlayerScreenState._audioEffectSessionId`.
- L324–324: field `_VideoPlayerScreenState._videoController`.
- L325–326: field `_VideoPlayerScreenState._renderer`.
- L331–331: field `_VideoPlayerScreenState._tvosDecodeRemedy`.
- L336–336: field `_VideoPlayerScreenState._tvosForceSoftwareDecode`.
- L340–340: field `_VideoPlayerScreenState._audioPassthroughEnabled`.
- L341–341: field `_VideoPlayerScreenState._systemAudioEffectsEnabled`.
- L342–342: field `_VideoPlayerScreenState._appleMultichannelEnabled`.
- L343–343: field `_VideoPlayerScreenState._tvosRouteOutputChannels`.
- L344–344: field `_VideoPlayerScreenState._tvosForceStereoAudio`.
- L345–345: field `_VideoPlayerScreenState._tvosLegacyAudioOutput`.
- L346–346: field `_VideoPlayerScreenState._playerInstanceGeneration`.
- L347–347: field `_VideoPlayerScreenState._playerPresentationInitialized`.
- L354–354: field `_VideoPlayerScreenState._activeOpenedMedia`.
- L355–355: field `_VideoPlayerScreenState._activeMediaShouldPlay`.
- L356–356: field `_VideoPlayerScreenState._activeMediaUserPaused`.
- L357–357: field `_VideoPlayerScreenState._random`.
- L358–358: field `_VideoPlayerScreenState._cachedSeriesPlaylist`.
- L359–359: field `_VideoPlayerScreenState._activePlaylist`.
- L360–360: field `_VideoPlayerScreenState._seriesImdbKnownAtLaunch`.
- L361–361: field `_VideoPlayerScreenState._episodeMetadataReady`.
- L362–362: field `_VideoPlayerScreenState._playerInitializationFuture`.
- L363–363: field `_VideoPlayerScreenState._playlistIdentityToken`.
- L364–364: field `_VideoPlayerScreenState._controlsVisible`.
- L366–366: field `_VideoPlayerScreenState._currentStreamUrl`.
- L369–369: field `_VideoPlayerScreenState._singleFileImdbId`.
- L370–370: field `_VideoPlayerScreenState._singleFileImdbFetched`.
- L373–373: field `_VideoPlayerScreenState._manualContentImdbId`.
- L374–374: field `_VideoPlayerScreenState._manualContentType`.
- L375–375: field `_VideoPlayerScreenState._manualContentSeason`.
- L376–376: field `_VideoPlayerScreenState._manualContentEpisode`.
- L377–377: field `_VideoPlayerScreenState._manualSubtitleDisplayLabel`.
- L380–380: field `_VideoPlayerScreenState._isPikPakRetrying`.
- L381–381: field `_VideoPlayerScreenState._pikPakRetryCount`.
- L382–382: field `_VideoPlayerScreenState._pikPakRetryMessage`.
- L383–384: field `_VideoPlayerScreenState._pikPakRetryId`.
- L387–419: method `_VideoPlayerScreenState._constructPlaylistItemData`.
- L421–442: getter `_VideoPlayerScreenState._seriesPlaylist`.
- L449–449: field `_VideoPlayerScreenState._tvBarScope`.
- L450–450: field `_VideoPlayerScreenState._tvPlayPauseFocus`.
- L451–451: field `_VideoPlayerScreenState._tvProgressFocus`.
- L456–456: field `_VideoPlayerScreenState._tvRootFocus`.
- L461–464: getter `_VideoPlayerScreenState._tvNoTimeline`.
- L466–466: field `_VideoPlayerScreenState._scrub`.
- L471–471: field `_VideoPlayerScreenState._isSeekingWithSlider`.
- L472–472: field `_VideoPlayerScreenState._lastSliderSeekPos`.
- L476–476: field `_VideoPlayerScreenState._showDebrifyBanner`.
- L477–477: field `_VideoPlayerScreenState._debrifyBannerFloatingMounted`.
- L478–478: field `_VideoPlayerScreenState._debrifyBannerTimer`.
- L480–480: getter `_VideoPlayerScreenState._showIptvZapBanner`.
- L481–481: getter `_VideoPlayerScreenState._iptvZapFloatingMounted`.
- L482–483: setter `_VideoPlayerScreenState._iptvZapFloatingMounted`.
- L485–485: field `_VideoPlayerScreenState._ripple`.
- L486–486: field `_VideoPlayerScreenState._panIgnore`.
- L487–487: field `_VideoPlayerScreenState._currentIndex`.
- L488–488: field `_VideoPlayerScreenState._lastTapLocal`.
- L489–490: field `_VideoPlayerScreenState._isManualEpisodeSelection`.
- L491–491: field `_VideoPlayerScreenState._isAutoAdvancing`.
- L492–493: field `_VideoPlayerScreenState._allowResumeForManualSelection`.
- L494–494: field `_VideoPlayerScreenState._manualSelectionResetTimer`.
- L495–495: field `_VideoPlayerScreenState._continuousShuffleEnabled`.
- L496–496: field `_VideoPlayerScreenState._shuffleBag`.
- L499–499: field `_VideoPlayerScreenState._currentChannelName`.
- L500–500: field `_VideoPlayerScreenState._currentChannelNumber`.
- L501–501: field `_VideoPlayerScreenState._currentChannelId`.
- L504–504: field `_VideoPlayerScreenState._showChannelGuide`.
- L505–505: field `_VideoPlayerScreenState._showSyncOverlay`.
- L506–506: field `_VideoPlayerScreenState._channelEntries`.
- L509–509: field `_VideoPlayerScreenState._showIptvChannelSheet`.
- L510–510: field `_VideoPlayerScreenState._currentIptvIndex`.
- L515–515: field `_VideoPlayerScreenState._iptvDiag`.
- L524–524: field `_VideoPlayerScreenState._iptvReconnectText`.
- L528–528: field `_VideoPlayerScreenState._backgroundedAt`.
- L530–552: field `_VideoPlayerScreenState._iptvLiveRecovery`.
- L557–569: method `_VideoPlayerScreenState._iptvRecoveryEligible`.
- L576–612: method `_VideoPlayerScreenState._performIptvLiveRetune`.
- L614–614: getter `_VideoPlayerScreenState._iptvGuideContextOverride`.
- L616–616: getter `_VideoPlayerScreenState._effectiveIptvChannels`.
- L618–618: getter `_VideoPlayerScreenState._iptvZapBannerOwnsIdentity`.
- L622–622: field `_VideoPlayerScreenState._playerGuideStyle`.
- L625–625: field `_VideoPlayerScreenState._dockStyle`.
- L626–626: field `_VideoPlayerScreenState._dockPalette`.
- L627–627: field `_VideoPlayerScreenState._dockSize`.
- L635–635: field `_VideoPlayerScreenState._dockExtent`.
- L640–640: field `_VideoPlayerScreenState._infoPanelHeight`.
- L643–643: field `_VideoPlayerScreenState._dockVolume`.
- L645–651: getter `_VideoPlayerScreenState._infoPanelSignature`.
- L653–653: field `_VideoPlayerScreenState._lastInfoPanelSignature`.
- L659–659: field `_VideoPlayerScreenState._infoPanelGeneration`.
- L664–664: field `_VideoPlayerScreenState._dockGeometryGeneration`.
- L669–679: method `_VideoPlayerScreenState._dockGeometrySignature`.
- L681–681: field `_VideoPlayerScreenState._lastDockGeometrySignature`.
- L684–687: method `_VideoPlayerScreenState.didChangeDependencies`.
- L691–705: method `_VideoPlayerScreenState._refreshDockGeometry`.
- L709–717: getter `_VideoPlayerScreenState._reservedInfoPanelHeight`.
- L720–720: field `_VideoPlayerScreenState._playerGuideTokens`.
- L737–737: field `_VideoPlayerScreenState._lifecycle`.
- L744–744: field `_VideoPlayerScreenState._pausedByLifecycle`.
- L746–746: field `_VideoPlayerScreenState._subtitleDiagnosticLogSub`.
- L747–747: field `_VideoPlayerScreenState._subtitleDiagnosticGeneration`.
- L748–748: field `_VideoPlayerScreenState._activeSubtitleApplyAttempt`.
- L749–751: field `_VideoPlayerScreenState._subtitleSelectionCorrection`.
- L753–753: getter `_VideoPlayerScreenState._canRecord`.
- L754–754: getter `_VideoPlayerScreenState._recordingActiveNow`.
- L755–755: method `_VideoPlayerScreenState._toggleRecording`.
- L756–757: method `_VideoPlayerScreenState._stopRecording`.
- L761–761: field `_VideoPlayerScreenState._showSourceSheet`.
- L762–762: field `_VideoPlayerScreenState._currentSourceIndex`.
- L763–763: field `_VideoPlayerScreenState._pendingSourcePlaylist`.
- L765–765: field `_VideoPlayerScreenState._stremioSourcesOverride`.
- L766–766: field `_VideoPlayerScreenState._resolveStremioSourceOverride`.
- L769–769: field `_VideoPlayerScreenState._augmentedSources`.
- L774–774: field `_VideoPlayerScreenState._playerMenuInitialSection`.
- L775–776: field `_VideoPlayerScreenState._playerMenuKey`.
- L777–777: field `_VideoPlayerScreenState._menuImdbId`.
- L778–778: field `_VideoPlayerScreenState._menuContentType`.
- L779–779: field `_VideoPlayerScreenState._menuSeason`.
- L780–780: field `_VideoPlayerScreenState._menuEpisode`.
- L781–781: field `_VideoPlayerScreenState._menuCachedSlots`.
- L782–782: field `_VideoPlayerScreenState._menuCacheKey`.
- L785–785: field `_VideoPlayerScreenState._showStremioTvGuide`.
- L786–786: field `_VideoPlayerScreenState._currentStremioTvChannelId`.
- L787–787: field `_VideoPlayerScreenState._stremioTvChannelsOverride`.
- L788–788: field `_VideoPlayerScreenState._showStremioTvNextLoading`.
- L789–789: field `_VideoPlayerScreenState._currentStremioTvContentImdbId`.
- L790–790: field `_VideoPlayerScreenState._currentStremioTvContentType`.
- L791–791: field `_VideoPlayerScreenState._currentStremioTvContentSeason`.
- L792–792: field `_VideoPlayerScreenState._currentStremioTvContentEpisode`.
- L793–793: field `_VideoPlayerScreenState._currentStremioTvContentTitle`.
- L797–798: getter `_VideoPlayerScreenState._effectiveSources`.
- L801–802: getter `_VideoPlayerScreenState._effectiveResolver`.
- L804–805: getter `_VideoPlayerScreenState._effectiveStremioTvChannels`.
- L807–808: getter `_VideoPlayerScreenState._effectiveContentImdbId`.
- L809–810: getter `_VideoPlayerScreenState._effectiveContentType`.
- L811–812: getter `_VideoPlayerScreenState._effectiveContentSeason`.
- L813–814: getter `_VideoPlayerScreenState._effectiveContentEpisode`.
- L815–816: getter `_VideoPlayerScreenState._effectiveContentTitle`.
- L821–828: getter `_VideoPlayerScreenState._currentSeriesImdbId`.
- L833–833: field `_VideoPlayerScreenState._skipSegmentSettingsLoaded`.
- L834–834: field `_VideoPlayerScreenState._skipSegmentsEnabled`.
- L835–835: field `_VideoPlayerScreenState._skipSegmentProviderId`.
- L836–841: field `_VideoPlayerScreenState._skipSegmentSession`.
- L842–842: field `_VideoPlayerScreenState._skipSegments`.
- L843–843: field `_VideoPlayerScreenState._loadedSkipSegmentsKey`.
- L854–854: field `_VideoPlayerScreenState._skipSegmentsMediaReady`.
- L857–857: field `_VideoPlayerScreenState._subtitleSettings`.
- L860–860: field `_VideoPlayerScreenState._cachedStremioSubtitles`.
- L863–863: field `_VideoPlayerScreenState._cachedAddonSlots`.
- L868–868: field `_VideoPlayerScreenState._injectedSubtitleSlots`.
- L869–869: field `_VideoPlayerScreenState._cachedSubtitleKey`.
- L871–871: field `_VideoPlayerScreenState._selectedStremioSubtitleId`.
- L872–873: field `_VideoPlayerScreenState._embeddedSubtitleApplied`.
- L874–875: field `_VideoPlayerScreenState._userManuallySelectedSubtitle`.
- L876–876: field `_VideoPlayerScreenState._trackPreferencesReadyForAddonSubtitles`.
- L877–878: field `_VideoPlayerScreenState._addonSubtitleFetchToken`.
- L882–882: field `_VideoPlayerScreenState._tempSubtitleFiles`.
- L883–883: field `_VideoPlayerScreenState._activeExternalSubtitlePath`.
- L884–884: field `_VideoPlayerScreenState._subtitleAutoSyncEnabled`.
- L885–885: field `_VideoPlayerScreenState._subtitleAutoSync`.
- L888–889: field `_VideoPlayerScreenState._autoSyncPill`.
- L891–891: field `_VideoPlayerScreenState._autoSyncWindowActive`.
- L892–892: field `_VideoPlayerScreenState._autoSyncPillHold`.
- L893–893: field `_VideoPlayerScreenState._autoSyncPillPhaseTimer`.
- L895–895: field `_VideoPlayerScreenState._autoSyncPillLastShown`.
- L898–898: field `_VideoPlayerScreenState._isReady`.
- L899–899: field `_VideoPlayerScreenState._startupGateActive`.
- L904–904: field `_VideoPlayerScreenState._startupGateOverlayHidden`.
- L908–908: field `_VideoPlayerScreenState._manualSourceGateActive`.
- L909–910: getter `_VideoPlayerScreenState._validationGateActive`.
- L911–911: field `_VideoPlayerScreenState._startupGateMessage`.
- L914–914: field `_VideoPlayerScreenState._resumeWriteGuard`.
- L915–915: field `_VideoPlayerScreenState._resume`.
- L916–917: field `_VideoPlayerScreenState._subs`.
- L918–919: field `_VideoPlayerScreenState._recording`.
- L920–921: field `_VideoPlayerScreenState._zap`.
- L922–922: method `_VideoPlayerScreenState._runSubtitleSetState`.
- L923–923: method `_VideoPlayerScreenState._runRecordingSetState`.
- L924–924: method `_VideoPlayerScreenState._runZapSetState`.
- L929–929: field `_VideoPlayerScreenState._resumeVerifyEpoch`.
- L930–930: field `_VideoPlayerScreenState._isPlaying`.
- L933–933: field `_VideoPlayerScreenState._isPipActive`.
- L934–934: field `_VideoPlayerScreenState._position`.
- L935–935: field `_VideoPlayerScreenState._duration`.
- L936–937: field `_VideoPlayerScreenState._playbackUiClock`.
- L938–939: field `_VideoPlayerScreenState._activeSkipSegmentUi`.
- L940–940: field `_VideoPlayerScreenState._isTransitioning`.
- L947–947: field `_VideoPlayerScreenState._seriesNextDispatched`.
- L948–948: field `_VideoPlayerScreenState._currentEpisodeMarkedAsFinished`.
- L949–949: field `_VideoPlayerScreenState._currentMovieMarkedAsFinished`.
- L950–950: field `_VideoPlayerScreenState._currentMovieRewatchStarted`.
- L951–952: field `_VideoPlayerScreenState._movieCompletionThreshold`.
- L953–954: field `_VideoPlayerScreenState._episodeCompletionThreshold`.
- L956–956: field `_VideoPlayerScreenState._posSub`.
- L957–957: field `_VideoPlayerScreenState._durSub`.
- L958–958: field `_VideoPlayerScreenState._playSub`.
- L959–959: field `_VideoPlayerScreenState._paramsSub`.
- L960–960: field `_VideoPlayerScreenState._trackSub`.
- L961–961: field `_VideoPlayerScreenState._completedSub`.
- L962–962: field `_VideoPlayerScreenState._bufferingSub`.
- L963–963: field `_VideoPlayerScreenState._iptvErrorSub`.
- L964–964: field `_VideoPlayerScreenState._rendererStartupErrorSub`.
- L970–970: field `_VideoPlayerScreenState._decoderProbeGeneration`.
- L971–971: field `_VideoPlayerScreenState._decoderDiagnostics`.
- L974–974: field `_VideoPlayerScreenState._showBufferingIndicator`.
- L975–975: field `_VideoPlayerScreenState._bufferingDebounceTimer`.
- L978–978: field `_VideoPlayerScreenState._mode`.
- L979–979: field `_VideoPlayerScreenState._gestureStartPosition`.
- L980–980: field `_VideoPlayerScreenState._gestureStartVideoPosition`.
- L981–981: field `_VideoPlayerScreenState._gestureStartVolume`.
- L982–982: field `_VideoPlayerScreenState._gestureStartBrightness`.
- L985–987: field `_VideoPlayerScreenState._seekHud`.
- L988–989: field `_VideoPlayerScreenState._verticalHud`.
- L990–990: field `_VideoPlayerScreenState._presentation`.
- L991–991: field `_VideoPlayerScreenState._transportVisibility`.
- L999–999: field `_VideoPlayerScreenState._sleepTimerMode`.
- L1004–1004: field `_VideoPlayerScreenState._sleepTimerDeadline`.
- L1008–1008: field `_VideoPlayerScreenState._sleepTimerArmedMinutes`.
- L1009–1009: field `_VideoPlayerScreenState._sleepTimer`.
- L1015–1015: field `_VideoPlayerScreenState._sleepStopLatched`.
- L1020–1020: field `_VideoPlayerScreenState._landscapeLocked`.
- L1030–1031: getter `_VideoPlayerScreenState._startsInPortrait`.
- L1034–1034: field `_VideoPlayerScreenState._rainbowController`.
- L1035–1035: field `_VideoPlayerScreenState._rainbowOpacity`.
- L1036–1036: field `_VideoPlayerScreenState._rainbowActive`.
- L1037–1037: field `_VideoPlayerScreenState._transitionRunning`.
- L1038–1038: field `_VideoPlayerScreenState._transitionStopTimer`.
- L1039–1039: field `_VideoPlayerScreenState._transitionPhaseTimer`.
- L1040–1040: field `_VideoPlayerScreenState._transitionPhase`.
- L1041–1041: field `_VideoPlayerScreenState._transitionPhase2Started`.
- L1044–1044: field `_VideoPlayerScreenState._tvStaticMessage`.
- L1045–1045: field `_VideoPlayerScreenState._tvStaticSubtext`.
- L1046–1055: field `_VideoPlayerScreenState._tvStaticMessages`.
- L1058–1058: field `_VideoPlayerScreenState._dynamicTitle`.
- L1060–1061: field `_VideoPlayerScreenState._tracker`.
- L1062–1062: getter `_VideoPlayerScreenState._scrobble`.
- L1064–1079: method `_VideoPlayerScreenState._randomStartOffset`.
- L1081–1089: method `_VideoPlayerScreenState._percentStartOffset`.
- L1092–1291: method `_VideoPlayerScreenState.initState`.
- L1293–1311: method `_VideoPlayerScreenState._loadSkipSegmentSettings`.
- L1313–1324: method `_VideoPlayerScreenState._loadLocalCompletionThresholds`.
- L1326–1332: getter `_VideoPlayerScreenState._usesLocalCompletionTracking`.
- L1334–1334: field `_VideoPlayerScreenState._forceLocalCompletionTracking`.
- L1336–1344: method `_VideoPlayerScreenState._loadTrackingPolicy`.
- L1346–1350: getter `_VideoPlayerScreenState._currentLocalMovieImdbId`.
- L1352–1356: method `_VideoPlayerScreenState._resetLocalCompletionState`.
- L1358–1421: method `_VideoPlayerScreenState._currentSkipSegmentRequest`.
- L1423–1425: method `_VideoPlayerScreenState._syncSkipSegmentsForCurrentContent`.
- L1427–1433: method `_VideoPlayerScreenState._publishSkipSegments`.
- L1441–1447: method `_VideoPlayerScreenState._resetSkipSegmentState`.
- L1449–1453: getter `_VideoPlayerScreenState._activeSkipSegment`.
- L1455–1457: method `_VideoPlayerScreenState._syncActiveSkipSegmentUi`.
- L1459–1471: method `_VideoPlayerScreenState._skipActiveSegment`.
- L1479–1495: getter `_VideoPlayerScreenState._persistablePosition`.
- L1499–1521: method `_VideoPlayerScreenState._traktSeasonEpisode`.
- L1527–1530: method `_VideoPlayerScreenState._scrobbleSeek`.
- L1532–1534: method `_VideoPlayerScreenState._resumeTrackingAfterValidationGate`.
- L1541–1547: method `_VideoPlayerScreenState._setExternalAudioTrack`.
- L1571–1600: method `_VideoPlayerScreenState._attachAudioEffectSession`.
- L1605–1610: method `_VideoPlayerScreenState._releaseAudioEffectSession`.
- L1619–1619: field `_VideoPlayerScreenState._outputLease`.
- L1641–1643: field `_VideoPlayerScreenState._outputLeaseTimeout`.
- L1645–1685: method `_VideoPlayerScreenState._claimVideoOutput`.
- L1687–1690: method `_VideoPlayerScreenState._releaseVideoOutput`.
- L1696–1696: field `_VideoPlayerScreenState._screenDisposed`.
- L1698–1725: method `_VideoPlayerScreenState._createPlayerInstance`.
- L1727–1758: method `_VideoPlayerScreenState._installSubtitleAutoSyncForPlayer`.
- L1760–1765: method `_VideoPlayerScreenState._disposeSubtitleAutoSync`.
- L1767–1783: method `_VideoPlayerScreenState._applyAutoSubtitleSyncOffset`.
- L1785–1820: method `_VideoPlayerScreenState._showSubtitleAutoSyncNotice`.
- L1822–1836: method `_VideoPlayerScreenState._openAutoSyncPillWindow`.
- L1838–1848: method `_VideoPlayerScreenState._showAutoSyncPillResult`.
- L1850–1857: method `_VideoPlayerScreenState._hideAutoSyncPill`.
- L1859–1874: method `_VideoPlayerScreenState._setActiveExternalSubtitlePath`.
- L1881–1881: field `_VideoPlayerScreenState._passthroughFlipChain`.
- L1891–1897: method `_VideoPlayerScreenState._setAudioPassthroughLive`.
- L1899–1929: method `_VideoPlayerScreenState._applyPassthroughFlip`.
- L1936–1971: method `_VideoPlayerScreenState._configurePlayerAudio`.
- L1978–1999: method `_VideoPlayerScreenState._installTvosDecodeRemedy`.
- L2001–2038: method `_VideoPlayerScreenState._onPlayerInstanceReady`.
- L2040–2427: method `_VideoPlayerScreenState._initializePlayer`.
- L2429–2602: method `_VideoPlayerScreenState._bindPlayerInstanceSubscriptions`.
- L2604–2604: method `_VideoPlayerScreenState._notifyRendererStateChanged`.
- L2605–2629: method `_VideoPlayerScreenState._takeRendererSubscriptions`.
- L2631–2650: method `_VideoPlayerScreenState._handleDecoderProbeParams`.
- L2652–2693: method `_VideoPlayerScreenState._installDecoderObservers`.
- L2695–2702: method `_VideoPlayerScreenState._beginMediaGeneration`.
- L2708–2708: field `_VideoPlayerScreenState._networkTuning`.
- L2716–2716: field `_VideoPlayerScreenState._networkTuningDefaults`.
- L2723–2723: field `_VideoPlayerScreenState._networkTuningChain`.
- L2725–2739: method `_VideoPlayerScreenState._applyNetworkTuning`.
- L2741–2776: method `_VideoPlayerScreenState._applyNetworkTuningInner`.
- L2778–2871: method `_VideoPlayerScreenState._openMedia`.
- L2873–2902: method `_VideoPlayerScreenState._releasePlayerDiagnostic`.
- L2905–2924: method `_VideoPlayerScreenState.didUpdateWidget`.
- L2927–2935: method `_VideoPlayerScreenState._waitForVideoReady`.
- L2937–2948: method `_VideoPlayerScreenState._showSubtitleFailureMessage`.
- L2951–2959: method `_VideoPlayerScreenState._waitForDuration`.
- L2962–2993: method `_VideoPlayerScreenState._getLastPlayedEpisode`.
- L2995–3086: method `_VideoPlayerScreenState._onPlaybackEnded`.
- L3088–3105: method `_VideoPlayerScreenState._startTransitionOverlay`.
- L3108–3108: method `_VideoPlayerScreenState._getCurrentEpisodeTitle`.
- L3114–3214: method `_VideoPlayerScreenState._getCurrentEpisodeTitleInfo`.
- L3217–3296: method `_VideoPlayerScreenState._getCurrentEpisodeSubtitle`.
- L3299–3335: method `_VideoPlayerScreenState._getEnhancedMetadata`.
- L3338–3399: method `_VideoPlayerScreenState._findNextEpisodeIndex`.
- L3402–3430: method `_VideoPlayerScreenState._getMainGroupIndices`.
- L3432–3495: method `_VideoPlayerScreenState._showRandomPlaybackMenu`.
- L3497–3516: method `_VideoPlayerScreenState._toggleContinuousShuffle`.
- L3518–3534: method `_VideoPlayerScreenState._playRandomOnce`.
- L3536–3561: method `_VideoPlayerScreenState._shuffleEligibleIndices`.
- L3563–3582: method `_VideoPlayerScreenState._pickShuffleIndex`.
- L3585–3646: method `_VideoPlayerScreenState._findPreviousEpisodeIndex`.
- L3649–3660: method `_VideoPlayerScreenState._hasNextEpisode`.
- L3663–3674: method `_VideoPlayerScreenState._hasPreviousEpisode`.
- L3676–3679: method `_VideoPlayerScreenState._clearBufferingIndicator`.
- L3682–3848: method `_VideoPlayerScreenState._goToNextEpisode`.
- L3853–3923: method `_VideoPlayerScreenState._handleSeriesNextEpisode`.
- L3926–3942: method `_VideoPlayerScreenState._parseChannelDirectory`.
- L3945–3955: method `_VideoPlayerScreenState._loadSubtitleSettings`.
- L3964–3965: method `_VideoPlayerScreenState._dockBand`.
- L3972–3993: method `_VideoPlayerScreenState._skipButtonBottom`.
- L3995–4014: method `_VideoPlayerScreenState._loadDockPrefs`.
- L4016–4071: method `_VideoPlayerScreenState._loadPlayerDefaults`.
- L4074–4088: method `_VideoPlayerScreenState._onSubtitleStyleChanged`.
- L4090–4095: method `_VideoPlayerScreenState._applySubtitleSyncOffset`.
- L4101–4107: method `_VideoPlayerScreenState._resetSubtitleSyncOffset`.
- L4113–4116: method `_VideoPlayerScreenState._tvReleaseFocusForOverlay`.
- L4118–4124: method `_VideoPlayerScreenState._showSyncOverlayPanel`.
- L4126–4128: method `_VideoPlayerScreenState._hideSyncOverlay`.
- L4130–4153: method `_VideoPlayerScreenState._buildSyncOverlay`.
- L4155–4177: method `_VideoPlayerScreenState._buildSliderSyncOverlay`.
- L4180–4190: method `_VideoPlayerScreenState._showChannelGuideOverlay`.
- L4193–4197: method `_VideoPlayerScreenState._hideChannelGuideOverlay`.
- L4204–4204: field `_VideoPlayerScreenState._iptvSwitchTicket`.
- L4209–4209: field `_VideoPlayerScreenState._iptvChannelKey`.
- L4218–4218: field `_VideoPlayerScreenState._iptvErrorsMuted`.
- L4220–4220: method `_VideoPlayerScreenState._onIptvStreamError`.
- L4226–4269: method `_VideoPlayerScreenState._setIptvSources`.
- L4274–4288: method `_VideoPlayerScreenState._initIptvStremioSources`.
- L4290–4290: getter `_VideoPlayerScreenState._currentIptvChannel`.
- L4305–4305: field `_VideoPlayerScreenState._lastLiveChannelTimer`.
- L4306–4306: field `_VideoPlayerScreenState._lastLiveChannelArmedUrl`.
- L4313–4313: field `_VideoPlayerScreenState._lastLiveChannelSettle`.
- L4315–4352: method `_VideoPlayerScreenState._noteLiveChannelPlaying`.
- L4360–4362: getter `_VideoPlayerScreenState._hasIptvNext`.
- L4364–4365: getter `_VideoPlayerScreenState._hasIptvPrevious`.
- L4372–4376: getter `_VideoPlayerScreenState._isIptvSeriesContext`.
- L4381–4381: field `_VideoPlayerScreenState._preferredIptvAudioLanguage`.
- L4386–4393: method `_VideoPlayerScreenState._iptvSeriesAudioKey`.
- L4398–4416: method `_VideoPlayerScreenState._captureIptvAudioLanguage`.
- L4425–4462: method `_VideoPlayerScreenState._applyIptvAudioPreference`.
- L4469–4494: method `_VideoPlayerScreenState._recordIptvWatchForChannel`.
- L4497–4697: method `_VideoPlayerScreenState._switchToIptvChannel`.
- L4703–4756: method `_VideoPlayerScreenState._tryOpenLiveStream`.
- L4771–4893: method `_VideoPlayerScreenState._openStartupDebridDirect`.
- L4895–5067: method `_VideoPlayerScreenState._tryOpenStartupVod`.
- L5073–5328: method `_VideoPlayerScreenState._openInitialVodWithFailover`.
- L5330–5341: method `_VideoPlayerScreenState._commitValidatedStremioSource`.
- L5343–5352: method `_VideoPlayerScreenState._startupSourceFields`.
- L5354–5359: method `_VideoPlayerScreenState._setStartupGateActive`.
- L5361–5365: method `_VideoPlayerScreenState._setStartupGateMessage`.
- L5369–5377: method `_VideoPlayerScreenState._showSourceSheetOverlay`.
- L5379–5383: method `_VideoPlayerScreenState._hideSourceSheet`.
- L5385–5396: method `_VideoPlayerScreenState._buildSourceSheetResolver`.
- L5398–5424: method `_VideoPlayerScreenState._handleSourceSelected`.
- L5431–5480: method `_VideoPlayerScreenState._switchToIptvSource`.
- L5482–5739: method `_VideoPlayerScreenState._switchToSourcePlaylist`.
- L5741–5910: method `_VideoPlayerScreenState._switchToStremioSource`.
- L5914–5920: method `_VideoPlayerScreenState._findInitialStremioTvChannelId`.
- L5922–5925: getter `_VideoPlayerScreenState._hasStremioTvGuide`.
- L5927–5929: getter `_VideoPlayerScreenState._hasStremioTvNext`.
- L5931–5932: getter `_VideoPlayerScreenState._hasAnyNext`.
- L5934–5940: method `_VideoPlayerScreenState._showStremioTvGuideOverlay`.
- L5942–5946: method `_VideoPlayerScreenState._hideStremioTvGuide`.
- L5948–5953: method `_VideoPlayerScreenState._setStremioTvNextLoading`.
- L5955–5977: method `_VideoPlayerScreenState._applyStremioTvGuidePlaybackData`.
- L5979–5988: method `_VideoPlayerScreenState._parseStremioTvSources`.
- L5990–6080: method `_VideoPlayerScreenState._switchToStremioTvChannel`.
- L6082–6149: method `_VideoPlayerScreenState._goToNextStremioTvSlot`.
- L6152–6278: method `_VideoPlayerScreenState._goToChannelById`.
- L6281–6420: method `_VideoPlayerScreenState._goToNextChannel`.
- L6423–6455: method `_VideoPlayerScreenState._goToPreviousEpisode`.
- L6458–6502: method `_VideoPlayerScreenState._markCurrentEpisodeAsFinished`.
- L6504–6522: method `_VideoPlayerScreenState._markCurrentMovieAsFinished`.
- L6527–6560: method `_VideoPlayerScreenState._checkAndApplyLocalCompletion`.
- L6568–6585: method `_VideoPlayerScreenState._clearTransitionOnFailure`.
- L6587–6772: method `_VideoPlayerScreenState._loadPlaylistIndex`.
- L6774–6788: method `_VideoPlayerScreenState._resolvePlaylistEntryUrl`.
- L6796–6897: method `_VideoPlayerScreenState._waitForVideoMetadata`.
- L6900–7225: method `_VideoPlayerScreenState._playPikPakVideoWithRetry`.
- L7228–7283: method `_VideoPlayerScreenState._preloadEpisodeInfo`.
- L7285–7307: method `_VideoPlayerScreenState._retryAddonSubtitleFetchAfterSeriesMetadata`.
- L7310–7364: method `_VideoPlayerScreenState._fetchSingleFileMovieMetadata`.
- L7366–7377: method `_VideoPlayerScreenState._saveImdbIdToPlaylist`.
- L7380–7437: method `_VideoPlayerScreenState._saveSeriesPosterToPlaylist`.
- L7440–7446: method `_VideoPlayerScreenState._enterPip`.
- L7451–7456: method `_VideoPlayerScreenState._armPipAutoEnter`.
- L7461–7473: method `_VideoPlayerScreenState._pushPipState`.
- L7477–7485: method `_VideoPlayerScreenState._onPipModeChanged`.
- L7488–7498: method `_VideoPlayerScreenState._onPipAction`.
- L7505–7528: method `_VideoPlayerScreenState._pauseForBackground`.
- L7533–7562: method `_VideoPlayerScreenState._resumeFromBackground`.
- L7571–7581: method `_VideoPlayerScreenState._syncWakelock`.
- L7584–7707: method `_VideoPlayerScreenState.dispose`.
- L7709–7709: field `_VideoPlayerScreenState._autosaveTimer`.
- L7727–7847: method `_VideoPlayerScreenState._buildTvControls`.
- L7856–7857: field `_VideoPlayerScreenState._iptvSheetKey`.
- L7864–7864: getter `_VideoPlayerScreenState._overlayJustClosed`.
- L7866–7872: getter `_VideoPlayerScreenState._anyPlayerOverlayOpen`.
- L7876–7906: method `_VideoPlayerScreenState._closeTopPlayerOverlay`.
- L7911–7925: method `_VideoPlayerScreenState._openTvGuide`.
- L7928–8025: method `_VideoPlayerScreenState._handleTvKey`.
- L8028–8055: method `_VideoPlayerScreenState._onControlsVisibilityChanged`.
- L8057–8091: method `_VideoPlayerScreenState._handleDoubleTap`.
- L8093–8120: method `_VideoPlayerScreenState._onPanStart`.
- L8122–8177: method `_VideoPlayerScreenState._onPanUpdate`.
- L8179–8193: method `_VideoPlayerScreenState._onPanEnd`.
- L8195–8195: method `_VideoPlayerScreenState._format`.
- L8197–8211: method `_VideoPlayerScreenState._togglePlay`.
- L8214–8225: method `_VideoPlayerScreenState._setManualSelectionMode`.
- L8231–8239: getter `_VideoPlayerScreenState._sleepTimerMinutesLeft`.
- L8242–8246: getter `_VideoPlayerScreenState._sleepTimerButtonLabel`.
- L8248–8267: method `_VideoPlayerScreenState._showSleepTimerSheet`.
- L8269–8281: method `_VideoPlayerScreenState._applySleepTimerSelection`.
- L8283–8293: method `_VideoPlayerScreenState._startSleepCountdown`.
- L8295–8309: method `_VideoPlayerScreenState._cancelSleepTimer`.
- L8314–8322: method `_VideoPlayerScreenState._fireSleepTimer`.
- L8324–8333: method `_VideoPlayerScreenState._showSleepTimerToast`.
- L8338–8344: method `_VideoPlayerScreenState._onSpeedButton`.
- L8346–8352: method `_VideoPlayerScreenState._onAspectButton`.
- L8356–8381: method `_VideoPlayerScreenState._onLongPressStart`.
- L8384–8400: method `_VideoPlayerScreenState._toggleOrientation`.
- L8402–8402: method `_VideoPlayerScreenState._currentFit`.
- L8414–8424: method `_VideoPlayerScreenState._buildSubtitleViewConfig`.
- L8427–8437: method `_VideoPlayerScreenState._buildCustomAspectRatioVideo`.
- L8440–8446: method `_VideoPlayerScreenState._buildTransitionOverlay`.
- L8448–8490: method `_VideoPlayerScreenState._buildStremioTvNextLoadingOverlay`.
- L8496–8497: getter `_VideoPlayerScreenState._debrifyTvOwnsIdentity`.
- L8499–8518: method `_VideoPlayerScreenState._buildDebrifyTvInfoPanel`.
- L8524–8529: method `_VideoPlayerScreenState._syncPlaybackClockVisibility`.
- L8534–8544: method `_VideoPlayerScreenState._raiseDebrifyBanner`.
- L8546–8566: method `_VideoPlayerScreenState._armDebrifyBannerTimer`.
- L8568–8578: method `_VideoPlayerScreenState._hideDebrifyBanner`.
- L8580–8581: method `_VideoPlayerScreenState._buildIptvInfoPanel`.
- L8584–8585: method `_VideoPlayerScreenState._getCustomAspectRatio`.
- L8593–8600: getter `_VideoPlayerScreenState._canFetchEpisodes`.
- L8602–8602: field `_VideoPlayerScreenState._episodeFetchInProgress`.
- L8606–8606: field `_VideoPlayerScreenState._syntheticGuidePlaylist`.
- L8607–8607: field `_VideoPlayerScreenState._syntheticGuideEntries`.
- L8609–8609: method `_VideoPlayerScreenState._pad2`.
- L8611–8635: method `_VideoPlayerScreenState._buildSyntheticGuide`.
- L8637–8653: method `_VideoPlayerScreenState._packCoversSeason`.
- L8659–8769: method `_VideoPlayerScreenState._fetchAndPlayEpisode`.
- L8774–8822: method `_VideoPlayerScreenState._tryEpisodeCandidate`.
- L8826–8844: method `_VideoPlayerScreenState._adjacentEpisode`.
- L8846–8881: method `_VideoPlayerScreenState._showPlaylistSheet`.
- L8884–10074: method `_VideoPlayerScreenState.build`.
- L10078–10084: getter `_VideoPlayerScreenState._isAnyOverlayOpen`.
- L10089–10105: method `_VideoPlayerScreenState._currentPlaybackTitleForIdentity`.
- L10108–10135: method `_VideoPlayerScreenState._currentSeasonEpisodeForIdentity`.
- L10138–10313: method `_VideoPlayerScreenState._showTracksSheet`.
- L10319–10342: method `_VideoPlayerScreenState._openPlayerMenuAt`.
- L10348–10401: method `_VideoPlayerScreenState._openPlayerMenuQuick`.
- L10406–10413: method `_VideoPlayerScreenState._menuApplyTrackChange`.
- L10415–10422: method `_VideoPlayerScreenState._menuSelectAudio`.
- L10424–10433: method `_VideoPlayerScreenState._menuSubtitlesOff`.
- L10435–10453: method `_VideoPlayerScreenState._menuSelectEmbeddedSubtitle`.
- L10457–10495: method `_VideoPlayerScreenState._menuSelectAddonSubtitle`.
- L10497–10528: method `_VideoPlayerScreenState._applyStremioSubtitleFromTracksSheet`.
- L10530–10610: method `_VideoPlayerScreenState._buildPlayerMenuPanel`.
- L10613–10626: method `_VideoPlayerScreenState._findSeriesEpisodeForCurrentIndex`.
- L10630–10636: method `_VideoPlayerScreenState._generateFilenameHash`.
- L10640–10653: class `_PlayerTrackerSession`.
- L10641–10641: constructor `_PlayerTrackerSession._PlayerTrackerSession`.
- L10642–10642: field `_PlayerTrackerSession._s`.
- L10643–10643: getter `_PlayerTrackerSession.currentSeriesImdbId`.
- L10644–10644: getter `_PlayerTrackerSession.seriesPlaylist`.
- L10645–10645: getter `_PlayerTrackerSession.activePlaylist`.
- L10646–10646: getter `_PlayerTrackerSession.currentIndex`.
- L10647–10647: getter `_PlayerTrackerSession.effectiveContentType`.
- L10648–10648: getter `_PlayerTrackerSession.effectiveContentSeason`.
- L10649–10649: getter `_PlayerTrackerSession.effectiveContentEpisode`.
- L10650–10650: getter `_PlayerTrackerSession.isPlaying`.
- L10651–10652: method `_PlayerTrackerSession.trackerSeasonEpisode`.
- L10655–10716: class `_RendererSession`.
- L10656–10656: constructor `_RendererSession._RendererSession`.
- L10657–10657: field `_RendererSession._s`.
- L10658–10658: getter `_RendererSession.mounted`.
- L10659–10659: getter `_RendererSession.playerInstanceGeneration`.
- L10660–10660: getter `_RendererSession.mediaGeneration`.
- L10661–10661: getter `_RendererSession.player`.
- L10662–10662: getter `_RendererSession.activeOpenedMedia`.
- L10663–10663: getter `_RendererSession.position`.
- L10664–10664: getter `_RendererSession.activeMediaShouldPlay`.
- L10665–10665: getter `_RendererSession.activeMediaUserPaused`.
- L10666–10666: getter `_RendererSession.sleepStopLatched`.
- L10667–10667: getter `_RendererSession.isLive`.
- L10668–10668: getter `_RendererSession.externalAudio`.
- L10669–10669: getter `_RendererSession.pausedByLifecycle`.
- L10670–10670: getter `_RendererSession.isTeeRecording`.
- L10671–10671: getter `_RendererSession.errorsMuted`.
- L10672–10672: getter `_RendererSession.isTransitioning`.
- L10673–10673: getter `_RendererSession.fallbackPlatformIsAndroid`.
- L10674–10674: getter `_RendererSession.probePlatformIsAndroid`.
- L10675–10675: getter `_RendererSession.isAndroidTv`.
- L10676–10676: method `_RendererSession.takeSubscriptions`.
- L10677–10677: method `_RendererSession.heldResumeTarget`.
- L10678–10678: method `_RendererSession.disposeSubtitleAutoSync`.
- L10679–10679: method `_RendererSession.clearExternalSubtitlePath`.
- L10680–10680: method `_RendererSession.releaseAudioEffectSession`.
- L10681–10681: method `_RendererSession.retainPlayerOwnership`.
- L10682–10682: method `_RendererSession.claimVideoOutput`.
- L10683–10683: method `_RendererSession.createPlayerInstance`.
- L10684–10684: method `_RendererSession.configurePlayerAudio`.
- L10685–10685: method `_RendererSession.installSubtitleAutoSync`.
- L10686–10686: method `_RendererSession.attachAudioEffectSession`.
- L10687–10687: method `_RendererSession.notifyStateChanged`.
- L10688–10688: method `_RendererSession.openMedia`.
- L10689–10689: method `_RendererSession.waitForVideoReady`.
- L10690–10690: method `_RendererSession.setExternalAudioTrack`.
- L10691–10691: method `_RendererSession.seekForResume`.
- L10692–10692: method `_RendererSession.restoreTrackPreferences`.
- L10693–10693: method `_RendererSession.diagnostic`.
- L10694–10701: method `_RendererSession.invalidatePlayerForFallback`.
- L10702–10705: method `_RendererSession.resetPlaybackPosition`.
- L10706–10715: method `_RendererSession.showAutomaticNotice`.
- L10718–10779: class `_ResumeSession`.
- L10719–10719: constructor `_ResumeSession._ResumeSession`.
- L10720–10720: field `_ResumeSession._s`.
- L10721–10721: getter `_ResumeSession.writeGuard`.
- L10722–10722: getter `_ResumeSession.resumeVerifyEpoch`.
- L10723–10723: getter `_ResumeSession.activePlaylist`.
- L10724–10724: getter `_ResumeSession.currentIndex`.
- L10725–10725: getter `_ResumeSession.effectiveIptvChannels`.
- L10726–10726: getter `_ResumeSession.currentIptvIndex`.
- L10727–10727: getter `_ResumeSession.videoUrl`.
- L10728–10728: getter `_ResumeSession.title`.
- L10729–10729: getter `_ResumeSession.resumePolicy`.
- L10730–10730: getter `_ResumeSession.traktProgressPercent`.
- L10731–10731: getter `_ResumeSession.simklProgressPercent`.
- L10732–10732: getter `_ResumeSession.mdblistProgressPercent`.
- L10733–10733: getter `_ResumeSession.contentImdbId`.
- L10734–10734: getter `_ResumeSession.isAutoAdvancing`.
- L10735–10735: setter `_ResumeSession.isAutoAdvancing`.
- L10736–10736: getter `_ResumeSession.isManualEpisodeSelection`.
- L10737–10737: getter `_ResumeSession.allowResumeForManualSelection`.
- L10738–10738: getter `_ResumeSession.launchTraktPercentSpent`.
- L10739–10739: setter `_ResumeSession.launchTraktPercentSpent`.
- L10740–10740: getter `_ResumeSession.launchSimklPercentSpent`.
- L10741–10741: setter `_ResumeSession.launchSimklPercentSpent`.
- L10742–10742: getter `_ResumeSession.launchMdblistPercentSpent`.
- L10743–10743: setter `_ResumeSession.launchMdblistPercentSpent`.
- L10744–10744: getter `_ResumeSession.position`.
- L10745–10745: getter `_ResumeSession.duration`.
- L10746–10746: getter `_ResumeSession.playerPosition`.
- L10747–10747: method `_ResumeSession.seek`.
- L10748–10748: method `_ResumeSession.setRate`.
- L10749–10749: getter `_ResumeSession.playbackSpeed`.
- L10750–10750: setter `_ResumeSession.playbackSpeed`.
- L10751–10751: getter `_ResumeSession.aspectMode`.
- L10752–10752: setter `_ResumeSession.aspectMode`.
- L10753–10753: method `_ResumeSession.applyAspectVideoZoom`.
- L10754–10754: method `_ResumeSession.waitForDuration`.
- L10755–10756: method `_ResumeSession.currentEpisodeTraktPercent`.
- L10757–10758: method `_ResumeSession.currentEpisodeSimklPercent`.
- L10759–10760: method `_ResumeSession.currentEpisodeMdblistPercent`.
- L10761–10761: getter `_ResumeSession.currentLocalMovieImdbId`.
- L10762–10762: getter `_ResumeSession.seriesPlaylist`.
- L10763–10763: getter `_ResumeSession.effectiveContentImdbId`.
- L10764–10764: getter `_ResumeSession.effectiveContentType`.
- L10765–10765: getter `_ResumeSession.effectiveContentSeason`.
- L10766–10766: getter `_ResumeSession.effectiveContentEpisode`.
- L10767–10767: getter `_ResumeSession.effectiveContentTitle`.
- L10768–10768: getter `_ResumeSession.currentStremioTvContentTitle`.
- L10769–10769: getter `_ResumeSession.currentStreamUrl`.
- L10770–10770: getter `_ResumeSession.validationGateActive`.
- L10771–10771: getter `_ResumeSession.isReady`.
- L10772–10772: getter `_ResumeSession.isTransitioning`.
- L10773–10773: getter `_ResumeSession.currentMovieMarkedAsFinished`.
- L10774–10774: getter `_ResumeSession.speedBeforeHold`.
- L10775–10775: getter `_ResumeSession.isMounted`.
- L10776–10776: getter `_ResumeSession.screenDisposed`.
- L10777–10778: method `_ResumeSession.generateFilenameHash`.
- L10781–10893: class `_SubtitleTrackSession`.
- L10782–10782: constructor `_SubtitleTrackSession._SubtitleTrackSession`.
- L10783–10783: field `_SubtitleTrackSession._s`.
- L10784–10784: getter `_SubtitleTrackSession.player`.
- L10785–10785: getter `_SubtitleTrackSession.isMounted`.
- L10786–10786: getter `_SubtitleTrackSession.hostContext`.
- L10787–10787: getter `_SubtitleTrackSession.videoTitle`.
- L10788–10788: getter `_SubtitleTrackSession.seriesPlaylist`.
- L10789–10789: getter `_SubtitleTrackSession.effectiveContentImdbId`.
- L10790–10790: getter `_SubtitleTrackSession.effectiveContentType`.
- L10791–10791: getter `_SubtitleTrackSession.effectiveContentSeason`.
- L10792–10792: getter `_SubtitleTrackSession.effectiveContentEpisode`.
- L10793–10793: getter `_SubtitleTrackSession.singleFileImdbId`.
- L10794–10795: getter `_SubtitleTrackSession.currentStremioTvContentSeason`.
- L10796–10797: getter `_SubtitleTrackSession.currentStremioTvContentEpisode`.
- L10798–10798: getter `_SubtitleTrackSession.launchContentSeason`.
- L10799–10799: getter `_SubtitleTrackSession.launchContentEpisode`.
- L10800–10801: getter `_SubtitleTrackSession.androidVideoRendererMode`.
- L10802–10802: getter `_SubtitleTrackSession.isIptvSeriesContext`.
- L10803–10803: getter `_SubtitleTrackSession.iptvSwitchTicket`.
- L10804–10804: getter `_SubtitleTrackSession.addonSubtitleFetchToken`.
- L10805–10806: setter `_SubtitleTrackSession.addonSubtitleFetchToken`.
- L10807–10808: getter `_SubtitleTrackSession.subtitleDiagnosticGeneration`.
- L10809–10810: setter `_SubtitleTrackSession.subtitleDiagnosticGeneration`.
- L10811–10812: getter `_SubtitleTrackSession.activeSubtitleApplyAttempt`.
- L10813–10814: setter `_SubtitleTrackSession.activeSubtitleApplyAttempt`.
- L10815–10816: getter `_SubtitleTrackSession.subtitleSelectionCorrection`.
- L10817–10818: getter `_SubtitleTrackSession.cachedStremioSubtitles`.
- L10819–10820: setter `_SubtitleTrackSession.cachedStremioSubtitles`.
- L10821–10821: getter `_SubtitleTrackSession.cachedAddonSlots`.
- L10822–10823: setter `_SubtitleTrackSession.cachedAddonSlots`.
- L10824–10824: getter `_SubtitleTrackSession.cachedSubtitleKey`.
- L10825–10825: setter `_SubtitleTrackSession.cachedSubtitleKey`.
- L10826–10827: getter `_SubtitleTrackSession.selectedStremioSubtitleId`.
- L10828–10829: setter `_SubtitleTrackSession.selectedStremioSubtitleId`.
- L10830–10830: getter `_SubtitleTrackSession.embeddedSubtitleApplied`.
- L10831–10832: setter `_SubtitleTrackSession.embeddedSubtitleApplied`.
- L10833–10834: getter `_SubtitleTrackSession.userManuallySelectedSubtitle`.
- L10835–10836: setter `_SubtitleTrackSession.userManuallySelectedSubtitle`.
- L10837–10838: getter `_SubtitleTrackSession.trackPreferencesReadyForAddonSubtitles`.
- L10839–10840: setter `_SubtitleTrackSession.trackPreferencesReadyForAddonSubtitles`.
- L10841–10841: getter `_SubtitleTrackSession.tempSubtitleFiles`.
- L10842–10843: getter `_SubtitleTrackSession.activeExternalSubtitlePath`.
- L10844–10844: getter `_SubtitleTrackSession.manualContentImdbId`.
- L10845–10846: setter `_SubtitleTrackSession.manualContentImdbId`.
- L10847–10847: getter `_SubtitleTrackSession.manualContentType`.
- L10848–10849: setter `_SubtitleTrackSession.manualContentType`.
- L10850–10850: getter `_SubtitleTrackSession.manualContentSeason`.
- L10851–10852: setter `_SubtitleTrackSession.manualContentSeason`.
- L10853–10853: getter `_SubtitleTrackSession.manualContentEpisode`.
- L10854–10855: setter `_SubtitleTrackSession.manualContentEpisode`.
- L10856–10857: getter `_SubtitleTrackSession.manualSubtitleDisplayLabel`.
- L10858–10859: setter `_SubtitleTrackSession.manualSubtitleDisplayLabel`.
- L10860–10861: method `_SubtitleTrackSession.runSetState`.
- L10862–10863: method `_SubtitleTrackSession.showSubtitleFailureMessage`.
- L10864–10869: method `_SubtitleTrackSession.showSnackBar`.
- L10870–10871: method `_SubtitleTrackSession.setActiveExternalSubtitlePath`.
- L10872–10872: method `_SubtitleTrackSession.resetSubtitleSyncOffset`.
- L10873–10877: method `_SubtitleTrackSession.hidePlayerMenuOnContentChange`.
- L10878–10882: method `_SubtitleTrackSession.reconcileMenuSubtitleSelection`.
- L10883–10884: method `_SubtitleTrackSession.applyIptvAudioPreference`.
- L10885–10888: method `_SubtitleTrackSession.findSeriesEpisodeForCurrentIndex`.
- L10889–10890: method `_SubtitleTrackSession.currentPlaybackTitleForIdentity`.
- L10891–10892: method `_SubtitleTrackSession.currentSeasonEpisodeForIdentity`.
- L10896–10947: class `_IptvZapSession`.
- L10897–10897: constructor `_IptvZapSession._IptvZapSession`.
- L10898–10898: field `_IptvZapSession._s`.
- L10899–10899: getter `_IptvZapSession.isMounted`.
- L10900–10900: getter `_IptvZapSession.hostContext`.
- L10901–10901: getter `_IptvZapSession.launchChannels`.
- L10902–10902: getter `_IptvZapSession.currentIptvIndex`.
- L10903–10903: setter `_IptvZapSession.currentIptvIndex`.
- L10904–10904: getter `_IptvZapSession.iptvSwitchTicket`.
- L10905–10905: getter `_IptvZapSession.iptvSourceId`.
- L10906–10906: getter `_IptvZapSession.iptvSourceName`.
- L10907–10907: getter `_IptvZapSession.iptvCategories`.
- L10908–10908: getter `_IptvZapSession.iptvSelectedCategory`.
- L10909–10909: getter `_IptvZapSession.iptvContentType`.
- L10911–10912: getter `_IptvZapSession.iptvBrowseProvider`.
- L10913–10913: getter `_IptvZapSession.controlsVisible`.
- L10914–10914: getter `_IptvZapSession.showIptvChannelSheet`.
- L10915–10915: getter `_IptvZapSession.showSourceSheet`.
- L10916–10916: getter `_IptvZapSession.showChannelGuide`.
- L10917–10917: getter `_IptvZapSession.playerGuideStyle`.
- L10918–10918: getter `_IptvZapSession.playerGuideTokens`.
- L10919–10919: getter `_IptvZapSession.recordingActiveNow`.
- L10920–10921: method `_IptvZapSession.runSetState`.
- L10923–10932: method `_IptvZapSession.onSwitch`.
- L10934–10939: method `_IptvZapSession.openIptvChannelSheet`.
- L10941–10943: method `_IptvZapSession.closeIptvChannelSheet`.
- L10944–10944: getter `_IptvZapSession.iptvErrorsMuted`.
- L10945–10945: method `_IptvZapSession.noteTuneError`.
- L10946–10946: method `_IptvZapSession.tryLiveRecoveryOnError`.
- L10949–10972: class `_IptvRecordingSession`.
- L10950–10950: constructor `_IptvRecordingSession._IptvRecordingSession`.
- L10951–10951: field `_IptvRecordingSession._s`.
- L10952–10952: getter `_IptvRecordingSession.player`.
- L10953–10953: getter `_IptvRecordingSession.playerCreated`.
- L10954–10954: getter `_IptvRecordingSession.isMounted`.
- L10955–10955: getter `_IptvRecordingSession.currentIptvChannel`.
- L10956–10957: getter `_IptvRecordingSession.iptvZapBannerOwnsIdentity`.
- L10958–10958: getter `_IptvRecordingSession.currentStreamUrl`.
- L10959–10959: getter `_IptvRecordingSession.iptvSourceId`.
- L10960–10961: getter `_IptvRecordingSession.iptvSources`.
- L10962–10963: method `_IptvRecordingSession.runSetState`.
- L10964–10969: method `_IptvRecordingSession.showSnackBar`.
- L10970–10971: method `_IptvRecordingSession.ensureCapacity`.
- L10974–11034: class `_RandomChoiceTile`.
- L10975–10975: field `_RandomChoiceTile.icon`.
- L10976–10976: field `_RandomChoiceTile.title`.
- L10977–10977: field `_RandomChoiceTile.subtitle`.
- L10978–10978: field `_RandomChoiceTile.onTap`.
- L10980–10985: constructor `_RandomChoiceTile._RandomChoiceTile`.
- L10988–11033: method `_RandomChoiceTile.build`.

</details>

### Detailed evidence artifacts

- [Band1 detailed inventory](C:/Users/hunth/debrify/debrify-renderer-coordinator-prep/.dart_tool/renderer-coordinator-prep/closing-player-gap/whole-host-band1/INVENTORY.md); SHA256 `c69d40e412708961fbb269a5e4e238a706165e8a96e59dbfe9e028a5f44b16b9`.
- [Band2 detailed inventory](C:/Users/hunth/debrify/c0-d2-delta-ecca/.dart_tool/c0-review/band-2751-5500/INVENTORY.md); SHA256 `25fd542c55987f178603b57c153a235de45c62844a8679a9d4e39843b817427d`.
- [Band3 detailed inventory](C:/Users/hunth/debrify/confucius-t3-current-2c48/.dart_tool/band-5501-8250/INVENTORY.md); SHA256 `0456038934e4baaaf9127c24ab5d913b7d9150063b34d5b72e1b96b42d5533d9`.
- [Band4 detailed inventory](C:/Users/hunth/debrify/locke-transition-a100/.dart_tool/player-band-8251/INVENTORY.md); SHA256 `6f31ebc628b21dd920317e9ade8c19d8d9246264ed324e01c0d8e91bc6012747`.
- [Whole-file AST and contextual reference index](C:/Users/hunth/debrify/locke-transition-a100/.dart_tool/player-band-8251/wholefile-ast.json); SHA256 `a8dbff1a6c18270966b68fb036a9b9d444768eac3125c5c3278cbd1318201fe6`. Static syntax evidence, not fresh behavior-test execution.
# L1 reviewer intake — September 7 decision addendum

Preserved quirks reported with origin pin d7d357c9 (not yet fetchable from origin during this review): IMDb-bearing multi-entry series without tracker credentials clears the cached cross-device percentage in that payload; getLastPlayedEpisode resolves equal updatedAt values by map iteration order, affecting series startIndex. Keep both; author reports actual-path pins and mutation coverage, parent verification pending.

L1's17-line debugAndroidTvLaunch production seam was outside the prior pin-only scope. A nullable terminal bridge substitution is acceptable in principle, but exact null-path equivalence, result/error propagation and test reset require source review before move admission. This is not blanket authorization for production changes in pins.

Builder inclusion and three narrowly repointed source-marker assertions are accepted scope. New launcher/builder circular imports are rejected: moving launch args alone leaves static backedges and its toWidget screen dependency. An acyclic ownership proposal is required; no reduction is earned and no args relocation is yet authorized. Report corrected physical ranges, moved cache lines outside the tail, total new code and wrapper debt separately.
# R3 dialog presentation decisions — September 7

Author-reported origin a0f6683d: busy dialog is protected by BOTH barrierDismissible=false and PopScope.canPop=false. Pin both separately; dropping one may escape a naive dismissal test. Preserve self-close on success and finally-close on failed restore. Single-profile confirmation deliberately reads "Import 1 profiles?". Legacy consent expiry remains silent while explicit Deny raises "Incoming settings were blocked". Preserve Deny-first autofocus and no answer on expiry.

Reverse-direction presenter registration accepted with narrowly owned main import/registration, idempotent/store-only binding and no silently missing dialog path. Pairing fallback expansion requires its own genuine origin coverage before relocation. Measured target removes only router's pairing-widget edge (2→1); remaining material edge is Phase3 R3-M debt covering snackbar/profile confirmations/focus only after separate ownership/pins. Frozen profile cluster stays untouched now. No claim of total UI decoupling or independently reproduced a0f6683d results yet.
# R3 pairing origin evidence addendum

Origin e61a9a56 adds actual router pairing-fallback cases; author/reviewer reports four caught mutations. A fifth mutation that also requests UI in the busy path is masked by existing process-wide _pairingDialogOpen protection, so it is explicitly not a caught mutation. Preserve that shared latch, navigator-key late lookup, panel-presenter counting and no-navigator return. Registration line/import already granted; no further user approval required for the scoped presenter move. Preserve source-only versus independently executed evidence distinctions until final review.
