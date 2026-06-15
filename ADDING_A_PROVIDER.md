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
  'open' — no nav tab — and 'playlist' — not supported yet).
- Helpers: `_get/_savePostTorrentActionForProvider` already route 'premiumize';
  `_postTorrentActionOptionsForProvider` returns the Premiumize subset so the
  home **quick-controls** dialog shows the right options. `_addToPremiumize`'s
  `_showPremiumizePostAddOptions` reads the pref and dispatches all 5 actions.

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

## Not done yet (future steps)
- [ ] **Navigation tab** (browse Premiumize cloud library) + hide-from-nav.

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
