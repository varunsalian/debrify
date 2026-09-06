# Refactor notes

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
