# Adding a New Debrid/Cloud Provider

Step-by-step checklist for wiring a new provider into Debrify. Use **Premiumize**
(added in branch `0.5.1`) as the reference implementation — search the codebase
for `premiumize` / `Premiumize` to see each piece in context.

Convention: providers are identified by lowercase string ids
(`debrid`, `torbox`, `pikpak`, `premiumize`).

---

## 1. Account model
Parse the provider's account/user info.
- **New file:** `lib/models/<provider>_user.dart`
- Reference: `lib/models/torbox_user.dart`, `lib/models/premiumize_user.dart`
- Include helpers like `hasActivePremium`, `formattedPremiumExpiry`, `subscriptionStatus`.

## 2. API service
Network calls + validation against the provider API.
- **New file:** `lib/services/<provider>_service.dart`
- Reference: `lib/services/torbox_service.dart`, `lib/services/premiumize_service.dart`
- At minimum: `getUserInfo(apiKey)` that throws on bad key / error response.

## 3. Account service (session state)
Static holder + reactive `ValueNotifier`, validate/persist/refresh/clear.
- **New file:** `lib/services/<provider>_account_service.dart`
- Reference: `lib/services/torbox_account_service.dart`, `lib/services/premiumize_account_service.dart`
- Keep the validation-token guard and `persist` flag pattern.

## 4. Storage (SharedPreferences)
- **Edit:** `lib/services/storage_service.dart`
- Add key constants (`_<provider>ApiKey`, `_<provider>IntegrationEnabledKey`, etc.)
  near the other provider keys (~line 14-26).
- Add getters/setters: `get/save/delete<Provider>ApiKey`,
  `get/set<Provider>IntegrationEnabled` (after the Torbox helpers).

## 5. Account status widget
Card UI shown on the provider's settings page.
- **New file:** `lib/widgets/<provider>_account_status_widget.dart`
- Reference: `lib/widgets/torbox_account_status_widget.dart`, `lib/widgets/premiumize_account_status_widget.dart`

## 6. Provider settings page (API key entry)
Enable toggle + API key add/validate/logout + "how to get key" help.
- **New file:** `lib/screens/settings/<provider>_settings_page.dart`
- Reference: `lib/screens/settings/torbox_settings_page.dart`, `lib/screens/settings/premiumize_settings_page.dart`
- Skip hide-from-nav / file-selection / post-action until the provider has a
  nav tab / add-torrent flow (steps 9+).

## 7. Settings screen — Connections card
Add the tappable card in the connections grid (with TV focus wiring).
- **Edit:** `lib/screens/settings_screen.dart`
  - Import the account service + settings page.
  - Add `_<provider>Connected/Status/Caption` state fields.
  - Add `getXApiKey()` to the `_loadSummaries()` `Future.wait` + read its result index.
  - Add cached-state block + background `refreshUserInfo()` call.
  - Add `_applyXUserInfo(...)` helper.
  - Add `_ConnectionInfo` entry + `_openXSettings()` handler.
  - In `_ConnectionsSummary`: add field/constructor param, focus node
    (init + dispose), and **re-wire the grid up/down/left/right neighbors**
    for the new card count (wide 2-col + narrow 1-col).

## 8. Provider Settings page (default provider picker)
Let users pick it as the default torrent provider.
- **Edit:** `lib/screens/settings/provider_settings_page.dart`
  - Add `_<provider>Available` (gated on key + integration enabled).
  - Add to provider count, `hasAnyProvider`, and the "no longer available → reset
    to none" cleanup.
  - Add the radio `_ProviderOption` (stores id e.g. `'premiumize'`).
  - Update the no-providers message text.

---

## 9. Add / Play / Download from torrent search (DONE for Premiumize)
Wire the provider into `lib/screens/torrent_search_screen.dart`. Premiumize is
simpler than RD/Torbox: `/transfer/directdl` returns ready-to-use direct links
for every file in one call (no per-file unrestrict), so playlist entries carry
real URLs and downloads enqueue those URLs directly.
- API service methods: `checkCache` (free, gates the flow), `directDownload`
  (cached → links), `createTransfer` (not-cached → add to cloud).
  See `lib/services/premiumize_service.dart`, `lib/models/premiumize_file.dart`.
- Screen entry: `_addToPremiumize` → cache-check → directdl → post-add options
  (`_showPremiumizePostAddOptions`) → `_playPremiumizeFiles` /
  `_showPremiumizeDownloadOptions`. Mirror `_addToTorbox` / `_playTorboxTorrent`.
- Series/movie handling reuses `SeriesParser` + `_findFirstEpisodeIndex` +
  `_formatTorboxPlaylistTitle` / `_combineSeriesAndEpisodeTitle` (provider-agnostic).
- Dispatch points wired: default-provider tap, service-selection dialog,
  per-result-card button (`buildPremiumizeButton`), Quick Play next-retry,
  post-torrent-action helpers, `_enabledServicesCount`, in-player source
  switching (`_resolveSourceViaPremiumize`), not-cached "add anyway".
- Loading overlay: `DebridLoadingOverlay.showPremiumize`.

## 10. Cache check during search (DONE for Premiumize)
Show a provider "cached" badge on search results (mirrors Torbox).
- **API:** Premiumize `/cache/check` accepts a repeated `items[]` array of
  infohashes/magnets, is free (no fair-use), and returns a parallel `response[]`
  of booleans. `PremiumizeService.checkCache(apiKey, items)` is **POST**, with a
  manually-built urlencoded body (package:http's Map body can't do repeated
  keys), **chunked** (100/req) with capped concurrency, results reassembled by
  index. Send **infohashes** (short), not full magnets.
- **Setting:** `get/setPremiumizeCacheCheckEnabled` (key
  `premiumize_check_cache_before_search`, default off) + a SwitchListTile on the
  settings page.
- **Search wiring (torrent_search_screen.dart):** state
  `_premiumizeCacheCheckEnabled` + `_premiumizeCacheStatus` (keyed by lowercased
  infohash), saved/restored in preserved state, cleared per search, loaded in
  init + the search `Future.wait`; a cache-check block after the Torbox one,
  request-id stale-guarded.
- **Badge:** `TorrentResultRow.cacheLabels` (List<String>) renders confirmed
  providers joined by ` | ` (e.g. `TB | PM`); `_cacheLabelsForResult` builds it.
  Badge-only — does NOT gate the provider button (cache verified on tap).

## 11. Quick Play (detail-screen "Play" button) (DONE for Premiumize)
The catalog/detail Play button runs Quick Play: search → auto-pick a cached
source → play. Two things were needed for a new provider:
- **`hasDebridProvider`** (torrent_search_screen.dart, in the quick-play
  handler ~line 5918) must include the provider, else `useTorrents` is false and
  Quick Play falls back to direct-stream — i.e. a provider-only setup would
  never use it. Add the provider's availability check there.
- **Cache pre-filter:** mirror the Torbox block — when the provider is the one
  Quick Play will use (`_defaultTorrentProvider == '<id>'`, or it's the sole
  fallback), batch `checkCache` the candidate hashes and narrow
  `torrentsForQuickPlay` to cached-only (reusing `_<provider>CacheStatus` if the
  search already populated it). Guard with `cachedOnly.isNotEmpty` so it
  degrades to the sequential retry when nothing is cached.
- Dispatch itself already works via the `forcePlay` branches wired in step 9
  (`_handleTorrentCardActivated`, `_tryNextQuickPlayTorrent`).

## 12. Bound sources / "Edit Source" (DONE for Premiumize)
Bind a torrent to a movie/series once, then replay instantly ("Edit Source").
Premiumize is stateless by magnet, so we store only the infohash in
`SeriesSource.torrentHash` (debridTorrentId empty) and re-resolve via directdl
on replay — no persistent transfer id needed.
- **Movie auto-save:** in `_addToPremiumize` (cached path), `setSources` a
  `SeriesSource(debridService:'premiumize', torrentHash:infohash)` for movies.
- **Select-source mode:** add the provider to the `_handleSelectSourceTorrentPicked`
  chain + `_addToPremiumizeAndBindSource` (cache-check → bind via `_saveSource`
  → exit mode). Movies overwrite (`setSources`), series append (`addSource`).
- **Replay:** add a `case 'premiumize'` to the `_tryPlayFromBoundSource` switch +
  `_tryPlayFromBoundSourcePremiumize` (rebuild magnet from `torrentHash` →
  directdl → find episode via `_findEpisodeInFilenames` / largest for movie →
  playlist of direct links → `_launchBoundSourcePlayer`). Removes the bound
  source if it no longer resolves.
- **Edit Source UI label:** add a `case 'premiumize'` (color + 'Premiumize') to
  the `serviceLabel` switch in `catalog_browser.dart`,
  `trakt/trakt_results_view.dart`, and `aggregated_search_results.dart`.

## 13. Bulk add (DONE for Premiumize)
Multi-select torrents → add all to the provider at once.
- Add a chooser tile + enabled-gate in `_showBulkAddDialog` and a dispatch
  branch (`result == 'premiumize' → _bulkAddToPremiumize()`).
- `_bulkAddToPremiumize` mirrors `_bulkAddToRealDebrid` (progress dialog with
  live Added/Not-cached/Failed counts, 300ms between adds, cancel, exit selection
  mode in `finally`). It **batch cache-checks all selected infohashes first**
  (free) and only `createTransfer`s the cached ones — uncached are skipped (not
  queued as cloud downloads), matching RD/Torbox semantics.
- Before running, picking Premiumize shows `_showPremiumizeFairUseDialog` (D-pad
  friendly, responsive) warning that Premiumize uses fair-use points (~1000 max,
  ~30/day, ~1pt/GB) so the user adds carefully. See "API limits" note below.

> **Premiumize API limits to know:** `cache/check` is free; `transfer/create`
> and `directdl` spend fair-use points (~1pt/GB, ~1000 cap, +30/day). No
> documented request-rate limit (we still pace bulk add 300ms + cap cache-check
> concurrency). Eager directdl resolves ALL files of a torrent on play — a known
> point-cost/expiry trade-off; lazy per-file resolution is a future optimization.

## 14. Post-torrent action (DONE for Premiumize)
What happens after adding a torrent (none / let-me-choose / play / download /
add-to-channel), settable per provider — same as RD/Torbox.
- Storage: `get/savePremiumizePostTorrentAction` (default 'choose').
- Settings page: a "Post-Torrent Action" RadioListTile card (Premiumize excludes
  'open' — no nav tab; 'playlist' IS supported, see step 19).
- Helpers: `_get/_savePostTorrentActionForProvider` already route 'premiumize';
  `_postTorrentActionOptionsForProvider` returns the Premiumize subset
  (`none`, `choose`, `play`, `download`, `playlist`, `channel`) so the home
  **quick-controls** dialog shows the right options. `_addToPremiumize`'s
  `_showPremiumizePostAddOptions` reads the pref and dispatches all of them
  (the `playlist` action → `_addPremiumizeToPlaylist`, see step 19).

## 15. Backup/restore (DONE for Premiumize)
Include the provider's API key in the file backup and restore it on import.
- **Edit:** `lib/services/backup_restore_service.dart`
  - `buildBackup()`: read `StorageService.get<Provider>ApiKey()`, add
    `'<provider>ApiKey': key` to the JSON map (guarded by non-empty).
  - `summarize()`: populate `has<Provider>` from the map key.
  - `applyBackup()`: add a `if (selection.<provider>)` block that reads the
    key, saves it, and calls `set<Provider>IntegrationEnabled(true)`.
  - `BackupSummary`: add `has<Provider>` field + constructor param + include in
    `isEmpty` getter.
  - `BackupSelection`: add `<provider>` field, set to `true` in `.all()`,
    add to constructor + `copyWith`.
  - `RestoreReport`: add `<provider>` field + count in `totalSuccess`.
- **Edit:** `lib/screens/settings_screen.dart`
  - `_backupSummaryLines()`: add `if (s.has<Provider>) lines.add('<Provider>')`.
  - `_formatRestoreReport()`: add `if (r.<provider>) parts.add('<Provider>')`.
  - Restore dialog text: add provider name to the credentials-overwrite warning.
  - Post-restore: `if (report.<provider>) <Provider>AccountService.clearUserInfo()`
    so the connection card refreshes after restore.

## 16. Remote Control — Transfer Everything + Send Setup to TV (DONE for Premiumize)
Let the remote sender push credentials to a TV via UDP, just like RD/Torbox.
- **Edit:** `lib/services/remote_control/remote_constants.dart`
  - Add `static const String <provider> = '<provider>';` to `ConfigCommand`.
- **Edit:** `lib/services/remote_control/remote_command_router.dart` (TV receiver)
  - Import the provider's account service.
  - Add `case ConfigCommand.<provider>: await _handle<Provider>Config(data);` to
    the `_handleConfigCommand` switch.
  - Add `_handle<Provider>Config(String apiKey)` handler: validate via
    `<Provider>AccountService.validateAndGetUserInfo(apiKey)`, then save key +
    enable integration. Validation happens here (unlike file restore) because the
    key crossed a network.
- **Edit:** `lib/widgets/remote/remote_config_export.dart` (Send Setup to TV)
  - Add `_ConfigItem? _<provider>` and `String? _<provider>ApiKey` state fields.
  - In `_loadConfigs()`: read key + enabled flag, build `_ConfigItem`.
  - Add to `_hasAnyConfigured` and `_hasAnySelected` guards.
  - In `_sendToTv()`: add a send block for the provider key.
  - In the build UI: add provider tile inside the "DEBRID PROVIDERS" section
    (update the section's `isConfigured` guard too).
  - Add `case ConfigCommand.<provider>` in `_getIcon()` and `_getIconColor()`.
- **Edit:** `lib/widgets/remote/remote_transfer_all.dart` (Transfer Everything)
  - Add `String? _<provider>ApiKey` state field.
  - In `_loadBundle()`: read key + enabled flag, add a `_TransferItem` when
    configured (icon + brand color).
  - Add `case ConfigCommand.<provider>` in `_sendConfigItem()` switch.

## 17. Debrify TV / Magic TV (DONE for Premiumize)
Wire the provider into `lib/screens/magic_tv_screen.dart` so it can stream via
both the channel-based auto-play flow and the Quick Play keyword flow.

### Provider constant + availability state
```dart
static const String _providerPremiumize = 'premiumize';
bool _premiumizeAvailable = false;
```

### `_determineDefaultProvider` (5th param)
Add `bool premiumizeAvailable` after `pikpakAvailable`. Insert Premiumize in
preferred-provider check and in the fallback order (after Torbox, before PikPak
is a reasonable placement).

### `_isProviderSelectable`
```dart
if (provider == _providerPremiumize) return _premiumizeAvailable;
```

### `_loadSettings` + `_syncProviderAvailability`
Load `getPremiumizeIntegrationEnabled()` + `getPremiumizeApiKey()`, compute
`premiumizeAvailable = enabled && key.isNotEmpty`, pass as 5th arg to
`_determineDefaultProvider`, and set `_premiumizeAvailable` in `setState`.

### `_providerDisplay`
```dart
if (provider == _providerPremiumize) return 'Premiumize';
```

### Provider chip in `_providerChoiceChips`
Mirror the Torbox/PikPak `ChoiceChip` block, guarded by `_premiumizeAvailable`.
Use `Icons.workspace_premium_rounded` and `Color(0xFFFB923C)` (orange) as the
brand color.

### `providerReady` switch
```dart
_providerPremiumize => _premiumizeAvailable,
```

### `_watchChannel` dispatch
```dart
else if (_provider == _providerPremiumize)
  await _watchPremiumizeWithCachedTorrents(cachedTorrents, ...);
```

### Quick-play dispatch
```dart
if (_quickProvider == _providerPremiumize) {
  await _watchWithPremiumize(keywords, _log);
  return;
}
```

### `requestNextChannel` conditions (all occurrences)
Add `|| _quickProvider == _providerPremiumize` and
`|| _provider == _providerPremiumize` to both guard expressions.

### No-provider snack message
Add `!_premiumizeAvailable` to the multi-`&&` guard.

### Reset dialog
Pass `_premiumizeAvailable` as the 5th arg to `_determineDefaultProvider`.

---

### New model classes
- **`lib/models/debrify_tv/prepared_torrents.dart`**: Add
  `PremiumizePreparedTorrent` (same shape as `TorboxPreparedTorrent` —
  `streamUrl`, `title`, `hasMore`).
- **`lib/models/debrify_tv/cache_results.dart`**: Add `PremiumizePlayableEntry`
  (`file: PremiumizeFile`, `title`, `info: SeriesInfo`).

---

### New methods in `magic_tv_screen.dart`

#### `_fetchPremiumizeCacheWindow`
```dart
Future<TorboxCacheWindowResult> _fetchPremiumizeCacheWindow({
  required List<Torrent> candidates,
  required int startIndex,
  required String apiKey,
})
```
- Slices `candidates[startIndex..]` into chunks of 100, up to 2 calls.
- Calls `PremiumizeService.checkCache(apiKey, chunk.map(t => t.magnetLink))`.
- Returns positional `List<bool>` — iterate by index: `if (i < cached.length && cached[i]) hits.add(chunk[i])`.
- Returns `TorboxCacheWindowResult(cachedTorrents: hits, nextCursor: ..., exhausted: ...)`.

#### `_preparePremiumizeTorrent`
```dart
Future<PremiumizePreparedTorrent?> _preparePremiumizeTorrent({
  required Torrent candidate,
  required String apiKey,
  required List<String> Function() log,
})
```
- Calls `PremiumizeService.directDownload(apiKey, magnet)` → `List<PremiumizeFile>`.
- Feeds files to `_buildPremiumizePlayableEntries` for filtering/sorting.
- Tracks seen files via `_seenLinkWithTorrentId` using `'$infohash|${file.path}'` key.
- Returns first unseen entry's URL (`file.streamLink ?? file.link`).
- `hasMore = entries.length > 1`.

#### `_buildPremiumizePlayableEntries`
```dart
List<PremiumizePlayableEntry> _buildPremiumizePlayableEntries(
  List<PremiumizeFile> files,
  String fallbackTitle,
)
```
- Filters: `_premiumizeFileLooksLikeVideo(file)` + min size (reuse Torbox threshold).
- Parses series info via `SeriesParser`, sorts episodes, random-shuffles movies.

#### `_premiumizeFileLooksLikeVideo`
```dart
bool _premiumizeFileLooksLikeVideo(PremiumizeFile file) =>
    FileUtils.isVideoFile(file.fileName);
```
`PremiumizeFile.fileName` is a computed getter derived from `file.path`.

#### `_watchPremiumizeWithCachedTorrents`
Full channel-based flow mirroring `_watchTorboxWithCachedTorrents`:
1. `_fetchPremiumizeCacheWindow` — get cached batch.
2. For each hit: `_preparePremiumizeTorrent`.
3. Launch via `_launchPikPakOnAndroidTv(streamUrl, title)` — Premiumize returns
   plain HTTPS URLs, same as PikPak, so the same launcher works.
4. On `MagicNext`: advance cursor, fetch next window when exhausted.

#### `_watchWithPremiumize`
Quick Play keyword flow mirroring `_watchWithTorbox`:
1. DB lookup + network search for candidates.
2. `_fetchPremiumizeCacheWindow` to narrow to cached.
3. `_preparePremiumizeTorrent` → `_launchPikPakOnAndroidTv`.
4. `MagicNext` retry loop.

---

### Key differences vs Torbox
| | Torbox | Premiumize |
|---|---|---|
| Cache check | `checkCachedTorrents` → `Set<String>` of hashes | `checkCache` → `List<bool>` positional |
| Prepare | createTorrent → poll → requestFileDownloadLink (3 steps) | `directDownload` (1 step) |
| Launch | `_launchTorboxOnAndroidTv` | `_launchPikPakOnAndroidTv` (HTTPS URLs) |
| Seen-key | `torrentId|fileId` | `infohash|file.path` |

## 18. Stremio TV debrid provider (DONE for Premiumize)

Wire the provider into `lib/screens/stremio_tv/stremio_tv_screen.dart` so it appears
in the provider picker and is used for cache filtering and stream resolution.

**Imports** — add `premiumize_service.dart` and `premiumize_file.dart`.

**`_loadAvailableProviders`** — check both `getPremiumizeIntegrationEnabled()` AND
`getPremiumizeApiKey()`. Only add the entry when both pass (Premiumize has a two-flag
guard; other providers only check the key or a single enabled flag).

**`_providerShortLabel` / `_providerFullLabel`** — add `'premiumize'` cases (`'PM'` /
`'Premiumize'`). The menu UI is data-driven off `_availableProviders` so no other UI
changes are needed.

**Cache pre-filter (two locations)** — one inside `_playChannel`, one inside the
prefetch/next-channel helper. For Premiumize, `checkCache` returns `List<bool>`
(positional, not a `Set<String>`), so build `cachedSet` via an index loop:
```dart
final cachedResults = await PremiumizeService.checkCache(pmKey, torrentHashes);
final cachedSet = <String>{};
for (int i = 0; i < torrentHashes.length; i++) {
  if (i < cachedResults.length && cachedResults[i]) cachedSet.add(torrentHashes[i]);
}
```
Then filter `playableSources` to keep direct streams + only cached torrents.

**`_playTorrentViaDebrid`** — add `'premiumize'` branch (explicit) and auto-fallback
(last in chain, after RD → Torbox → PikPak). Update the no-provider snackbar to
mention Premiumize.

**`_playViaPremiumize`** — single `directDownload` call returns ready URLs; no polling.
Pick largest file for movies, `candidates.first` for others. Prefer `streamLink ?? link`.
Pattern matches `_playViaPikPak` (HTTPS URLs, no create/poll steps).

**`_resolveTorrentUrl`** — same `'premiumize'` branch + auto-fallback pattern as above.

**`_resolveViaPremiumize`** — like `_playViaPremiumize` but returns URL only (no
`VideoPlayerLauncher`). Adds episode matching via `StremioEpisodeSelector.findEpisodeFileIndex`
on `f.path`; falls back to largest file on miss. This is better than the Torbox equivalent.

### Key differences vs Torbox
| | Torbox | Premiumize |
|---|---|---|
| Cache check response | `Set<String>` of hashes | `List<bool>` positional — use index loop |
| Stream resolution | createTorrent → 3 s delay → getTorrentById → requestFileDownloadLink | `directDownload` (1 step, returns ready URLs) |
| URL type | HTTPS download link | `streamLink` (HLS) preferred, `link` fallback |
| Episode selection in `_resolve*` | `findLargestFileIndex` + `findEpisodeFileIndex` | same, but on `f.path` |

## 19. Add to playlist (DONE for Premiumize)
Save a torrent to a user playlist (single video or whole collection), then replay
it later from the playlist UI on **all three playback surfaces**: the in-app Dart
player, the native Android TV player, and the external player. Premiumize stores
only the infohash + per-file path and **re-resolves direct links via `directdl`**
at play time (links expire / spend points eagerly), so nothing stale is persisted.

### Data model — what gets saved
- **Single:** `{provider:'premiumize', kind:'single', title, torrent_hash:<infohash>,
  premiumizePath:<file path>, sizeBytes}`.
- **Collection:** `{provider:'premiumize', kind:'collection', title,
  torrent_hash:<infohash>, count}`.
- **Lazy-resolution fields** on `PlaylistEntry`
  (`lib/screens/video_player/models/playlist_entry.dart`): add
  `premiumizeHash` (infohash) + `premiumizePath` (matched on re-resolve). These
  must be carried through **every** entry-reconstruction path or playback silently
  loses the ability to refresh expired links.

### Re-resolution helper
- **`lib/services/premiumize_service.dart`** — `resolveFilesByHash(apiKey, infohash)`
  builds `magnet:?xt=urn:btih:$infohash` → `directDownload` → `List<PremiumizeFile>`.
  Match the saved file by **exact `file.path` string equality** (single play has a
  `firstWhere(... orElse: first)` fallback; collections fill all URLs eagerly from
  the one call).

### Save from torrent search (`torrent_search_screen.dart`)
- `_postTorrentActionOptionsForProvider` includes `'playlist'` (step 14).
- `_showPremiumizePostAddOptions`: add a `case 'playlist':` auto-action **and** an
  "Add to playlist" `_DebridActionTile` (`Icons.playlist_add_rounded`,
  `0xFF818CF8`) → `_addPremiumizeToPlaylist(files, torrentName, infohash:...)`.
- `_addPremiumizeToPlaylist`: single (filter via `_premiumizeFileLooksLikeVideo` →
  store `premiumizePath`) vs collection (store `count`); both attach
  imdb/contentType/poster from `_activeAdvancedSelection`.

### Storage (`storage_service.dart`)
- `computePlaylistDedupeKey` already keys Premiumize off `torrent_hash`
  (`premiumize|hash:<hash>`) — **no change needed**.
- `updatePlaylistItemImdbId` / `updatePlaylistItemPoster`: add a `premiumizeHash`
  param; match on `provider == 'premiumize'` AND case-insensitive `torrent_hash`.
- `addPlaylistItemRaw` stores Premiumize items cleanly (no RD hash-fetch — there's
  no `rdTorrentId`).

### Playback dispatch — wire ALL THREE surfaces
1. **In-app Dart player** — `lib/screens/video_player_screen.dart`
   `_resolvePlaylistEntryUrl`: add a Premiumize branch (before the
   `restrictedLink` branch) → `resolveFilesByHash` → match `f.path == path` →
   return `match.link`.
2. **Native Android TV / external player** — `lib/services/video_player_launcher.dart`
   - `_resolveEntryUrl`: same Premiumize branch (guard
     `hash != null && hash.isNotEmpty && path != null && path.isNotEmpty`).
   - `_prepareEntries` reconstruction: carry
     `premiumizeHash: entry.premiumizeHash, premiumizePath: entry.premiumizePath`
     (⚠️ easy to miss — drops re-resolution on TV/external).
3. **Playlist launch service** — `lib/services/playlist_player_service.dart`
   - `play()`: route `if (provider == 'premiumize') { await _playPremiumizeItem(...); return; }`.
   - `_playPremiumizeItem`: single (match `premiumizePath`, fallback
     `videoFiles.first`) + collection (series-aware sort, eager-fill all URLs from
     one `resolveFilesByHash`, set `premiumizeHash`/`premiumizePath` on every
     entry). Reuses `_findFirstEpisodeIndex`, `_formatPikPakPlaylistTitle`,
     `_composePikPakEntryTitle`. Add `_PremiumizePlaylistCandidate` helper.

### Playlist content browsing (`playlist_content_view_screen.dart`)
- `_loadContent`: add `else if (provider == 'premiumize') _loadPremiumizeContent()`.
- `_loadPremiumizeContent` + `_buildPremiumizeFileTree`: flat `RDFileNode` tree —
  `name=fileName`, `path=file.path`, **`relativePath` = path with the first
  (torrent) folder stripped**, `bytes=size`.
- `_playFile` / `_playEpisode`: add `else if (provider == 'premiumize')
  _playPremiumizePlaylist(...)` → re-resolve, build a `linkByPath` map, build
  entries with `url` + `premiumizeHash` + `premiumizePath`.
- `_saveImdbIdToPlaylist` / `_updatePlaylistPoster`: pass `premiumizeHash` (the
  saved `torrent_hash`) to the storage updaters.

### Sorting — no Premiumize-specific branch
`_applySortedPlaylistOrder` groups folders off `node.relativePath ?? node.path`.
Because `_buildPremiumizeFileTree` **pre-strips** the torrent folder into
`relativePath`, the default branch is correct. Do **NOT** copy Torbox's runtime
first-folder-skip (Torbox needs it only because it doesn't pre-strip).

### Resume keys — RD-tier (filename-hash), by design
Premiumize has **no** resume-key branch in `video_player_screen._resumeIdForEntry`,
`video_player_launcher.resumeIdForEntry`, or
`movie_collection_browser._resumeIdForEntry` — it falls to the shared
`nameWithoutExt.hashCode` filename-hash, **identical to Real-Debrid**. Only Torbox
(and PikPak in some paths) use ID-based keys because their file IDs are a stable
identity Premiumize lacks. Adding ID-based keys here would *diverge* from RD and
risk inconsistency with the search-playback path — leave it as filename-hash.

### Series enrichment (`lib/widgets/series_browser.dart`)
imdb update + `_updatePlaylistPoster`: add the `isPremiumize` flag + `premiumizeHash`
and pass them to the storage updaters (mirror the PikPak/RD calls).

### Provider badges (UI)
- `home_playlist_section.dart` / `home_favorites_section.dart` `_providerInfo`:
  `case 'premiumize': return ('PM', Color(0xFFFB923C), 'Premiumize');`.
- `playlist_grid_card.dart` / `playlist_landscape_card.dart` badge fn:
  `case 'premiumize': return 'PM';`.

### Key differences vs Real-Debrid
| | Real-Debrid | Premiumize |
|---|---|---|
| Saved link | restrictedLink (lazy unrestrict) | infohash + path (lazy `directdl`) |
| Re-resolve | `unrestrictLink` per file | `resolveFilesByHash` (1 call, all files) |
| Match key | restrictedLink string | `file.path` exact equality |
| Resume key | filename-hash | filename-hash (same) |
| Dedupe key | `torrent_hash` | `torrent_hash` (same) |

## 20. Navigation tab — cloud library browser (DONE for Premiumize)
A full-screen tab to browse the provider's cloud and act on items, mirroring the
Torbox/PikPak pages. Premiumize's cloud is a **server-side folder hierarchy**
(like PikPak/WebDAV), so the browser navigates folders by id rather than building
a virtual tree. The closest template is
`lib/screens/pikpak/pikpak_files_screen.dart`.

### Cloud API (`lib/services/premiumize_service.dart`)
Added: `listFolder(apiKey, {folderId})` (GET `/folder/list`, omit `id` for root),
`listFolderRecursive` (depth-guarded, stamps `relativePath`), `resolveItemById`
(GET `/item/details` → fresh `PremiumizeFile` for playlist re-resolution),
`deleteFolder`/`deleteItem` (POST `/folder/delete` · `/item/delete`),
`listTransfers` (GET `/transfer/list`), `deleteTransfer` (POST `/transfer/delete`),
`clearFinishedTransfers` (POST `/transfer/clearfinished`),
`generateFolderZip`/`generateItemZip`; and `createTransfer` gained an optional
`folderId` (so "Add link" lands in the current folder).

### Models
- **`lib/models/premiumize_folder_item.dart`** — `PremiumizeFolderItem`
  (id, name, type folder/file, size, `link`, `streamLink`, mimeType, createdAt,
  `relativePath`; `isVideo`, `playableUrl` link-first) + `PremiumizeFolderListing`.
  Note: `/folder/list` already returns `link`/`stream_link` for files, so play
  and download need **no** extra resolve call.
- **`lib/models/premiumize_transfer.dart`** — `PremiumizeTransfer`
  (id, name, status, progress 0–1, message, folderId/fileId; `isFinished`,
  `isError`, `isRunning`, `progressPercent`).

### Screen (`lib/screens/premiumize/premiumize_files_screen.dart`)
Two views (a root toggle): **My Files** (folder browser) + **Transfers**
(queued/running/finished, with per-transfer delete + "Clear finished").
Per-item actions match PikPak: Open (folder), Play (file/folder, series-aware),
Download (file direct / folder via `FileSelectionDialog`), Add to Playlist
(file/folder), Delete; plus multi-select bulk delete, in-folder Search, Raw /
Sort(A-Z) view modes, "Add to Premiumize" (magnet/link), pull-to-refresh, and
full TV/D-pad focus (`TvFocusScrollWrapper`, `registerTvContentFocusHandler(11)`).

### Add-to-Playlist needs cloud item ids (no infohash!)
Cloud items have no torrent hash, so they're saved/resolved by **cloud item id**
(`premiumizeItemId`), mirroring PikPak's `pikpakFileId` — a path **parallel** to
the search-added hash+path path, not a replacement.
- `PlaylistEntry.premiumizeItemId` added; carried through `_prepareEntries`.
- Both player resolvers (`video_player_screen._resolvePlaylistEntryUrl`,
  `video_player_launcher._resolveEntryUrl`) gained an item-id branch **before**
  the hash branch (`resolveItemById` → fresh link).
- `playlist_player_service`: `_playPremiumizeItem` routes to a new
  `_playPremiumizeCloudItem` when there's no hash but cloud ids exist
  (single via `premiumizeFile`, collection via `premiumizeFiles`/`premiumizeItemIds`).
- `playlist_content_view_screen`: `_loadPremiumizeContent` builds the tree from
  stored file metadata (item id in `RDFileNode.path`); `_playPremiumizePlaylist`
  has a cloud branch resolving the start item via `resolveItemById`.
- `storage_service.computePlaylistDedupeKey`: `premiumize:item:<id>` /
  `premiumize:items:<joined>` cases; `updatePlaylistItemImdbId`/`Poster` gained a
  `premiumizeItemId` match (content-view + series_browser pass it).
- Saved shapes — single: `{provider, kind:'single', premiumizeItemId,
  premiumizeFile:{id,name,size}}`; collection: `{provider, kind:'collection',
  premiumizeItemId:<folderId>, premiumizeFiles:[{id,name,size}],
  premiumizeItemIds:[…], count}`.

### Hide-from-nav + main wiring
- Storage: `premiumize_hidden_from_nav` key + `get/set/clearPremiumizeHiddenFromNav`.
- Settings page: a "Hide from Navigation" `SwitchListTile` (confirm-to-hide,
  logout-to-unhide); `_deleteKey` clears the flag.
- `main.dart`: `_pages`/`_titles`/`_icons` index **11**
  (`Icons.workspace_premium_rounded`); `_premiumizeEnabled` +
  `_premiumizeHiddenFromNav` state; loaded in `_loadIntegrationState`; threaded
  through `_applyIntegrationState` + `_computeVisibleNavIndices` (both TV and
  non-TV branches, and the no-provider early-return); `_navSectionForIndex`
  case 11 → 'Library'; `_onItemTapped` tab-key `case 11 → 'premiumize'` (⚠️
  required or the global/TV back button is dead on the tab); switchTab
  hidden-vs-missing snackbar branch for index 11.

### Key differences vs PikPak
| | PikPak | Premiumize |
|---|---|---|
| Play/download URL | `getFileDetails` per file (links expire fast) | `link`/`stream_link` already in `folder/list` (no extra call) |
| Playlist re-resolve | `pikpakFileId` → `getFileDetails` | `premiumizeItemId` → `item/details` |
| Pagination | page tokens | none (`folder/list` returns all) |
| Second view | — | **Transfers** (`/transfer/list`) |

---

## 21. Onboarding setup flow (DONE for Premiumize)

Add the provider as a selectable chip on the welcome screen of
`lib/widgets/initial_setup_flow.dart`.

- **Enum:** add `premiumize` to `_IntegrationType`.
- **Meta:** add an `_IntegrationMeta` entry in `_integrationMeta` with
  `title`, `url` (API-key page), `linkLabel`, `steps`, `inputLabel`, `hint`,
  `gradient` (brand colours), `icon`.
- **Controller:** `_premiumizeController = TextEditingController()` — dispose
  it in `dispose()`.
- **Focus node:** `_premiumizeChipFocusNode` — add to `_addFocusListeners()`
  list and dispose in `dispose()`.
- **Welcome chip:** extend the focus-node and traversal-order ternary chains
  in `_buildWelcomeStep`. Bump the Skip/Continue button traversal orders if
  needed (with 4 chips: Skip=5, Continue=6).
- **`_buildIntegrationStep` controller lookup:** add a `premiumize` branch
  before the PikPak fallback; Premiumize is API-key (not email/password), so
  it must resolve to `_premiumizeController` and take the non-PikPak path.
- **`_startIntegrationFlow`:** add `premiumize` to the `ordered` list.
- **`_submitCurrent`:** route `premiumize` to
  `PremiumizeAccountService.validateAndGetUserInfo(value)` (key is saved
  automatically; `getPremiumizeIntegrationEnabled` defaults to `true` so no
  separate enable call is required). Add `premiumize` to the `nonav:` prefix
  block → `StorageService.setPremiumizeHiddenFromNav(true)`. Update analytics
  ternary to emit `'premiumize'`.
- **`_requestFocusForCurrentStep`:** Premiumize falls through to the shared
  `_textFieldFocusNode` (same as RD/Torbox).
- **D-pad:** fully compatible — Premiumize reuses `_TvFriendlyTextField` with
  `_textFieldFocusNode`, which already handles arrow-key escape and hardware
  back.

---

### Quick verify
```
flutter analyze lib/screens/settings_screen.dart \
  lib/screens/settings/<provider>_settings_page.dart \
  lib/services/<provider>_service.dart \
  lib/services/<provider>_account_service.dart \
  lib/services/storage_service.dart \
  lib/models/<provider>_user.dart \
  lib/widgets/<provider>_account_status_widget.dart
```
