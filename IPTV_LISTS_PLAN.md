# IPTV Custom Lists — Implementation Plan

Status: **BUILT (2026-08-01), UNCOMMITTED — awaiting device test.**
All four steps implemented. `flutter analyze` clean, `flutter test` 680 pass
(the 8 failures in series_parser_test/widget_test are pre-existing and
byte-identical before/after — verified by stashing), Kotlin compiles, debug
APK builds.

Deviations from the plan, all deliberate:
- **No shelf reload on a plain favourite toggle.** The plan implied removing
  the row; a reload disposes every row's focus node and would scramble DPAD
  focus right after the hold. The row keeps its slot with an empty heart —
  the pre-existing behaviour. The picker path DOES reload, but only when the
  channel actually left the shelf being viewed.
- **The player sheet needed no list-source branch.** It has exactly one
  source-flag branch (`isFavorites`) and otherwise drives off the browse
  callback, so `list://` sources work through the existing round-trip once
  the dispatch and catalog-key guards are in place. The planned
  `_listSourceId` state would have been dead weight; the "Saved" pill stays
  favourites-only as designed.
- **`membershipSnapshot()`** replaced the planned pair of separate
  membership/origin reads — one scan of the table instead of two per load.
- The native favourite toggle now also ships `contentType`/`duration`, which
  the plan only required of the new list write path. Without it a movie
  favourited from the native guide still came back as live.

Post-review fixes (3 findings, all confirmed and fixed):
- **Origins are keyed by (list id, url), never url alone.** The same URL can
  be saved into two lists from two different providers; a url-keyed map kept
  one arbitrary origin, so a later write from inside a shelf could be filed
  under the wrong provider and then survive (or vanish in) the wrong
  provider-deletion sweep. Each rebuilt row now also carries its own origin
  in a `list_playlist_id` attribute, which both origin resolvers prefer.
  Regression test in `iptv_lists_test.dart`.
- **The native picker shows no rows until membership loads.** The adapter was
  live against an empty membership set during the round-trip, so pressing a
  list the channel was already in read as "not in" and re-added it, and the
  late response then overwrote the displayed state.
- **Removing a channel from the list being browsed now drops its guide row**
  (locally, so scroll and focus survive; the playing channel is exempt), and
  the Dart shelf-staleness check after playback covers custom lists, not just
  Favorites.

Second review round (4 findings, all confirmed and fixed):
- **`_loadSettings` now adopts the list rows it reads.** It read them for the
  source injection but never assigned `_lists`, and returning from Settings
  does NOT go through `_loadFavorites` (a catalog reload only happens when
  the selected playlist changed) — so the first list created there left
  long-press still toggling Favorites, and a deleted one left the picker
  pointing at a row that was gone.
- **The picker reports its writes even when dismissed.** Rows apply
  immediately, but Back or a barrier tap pops with null, which read as "no
  change" and skipped the caller's refresh. Change tracking moved into a
  `_PickerOutcome` that outlives the route.
- **Closing no longer races the writes.** Mutations are queued on that same
  outcome and the wrapper awaits the queue before returning, so the caller
  can't re-read storage mid-transaction and paint the pre-toggle state back.
  The queue is ordered (rapid toggles land in press order) and absorbs
  failures so one bad write can't poison the rest. Covered by
  `test/iptv_list_picker_dialog_test.dart`.
- **`IptvChannelEntry` retains the parsed runtime.** Both native write paths
  were flattening duration to `-1`-or-null, so a VOD item added from the TV
  guide lost the runtime its progress/resume UI needs.
Reviewed 2026-08-01 against the actual code (3-agent verification sweep +
storage-layer read); line numbers below are from that pass.
Goal: users can create any number of named lists (like Favorites) and add IPTV
channels to them. Favorites becomes "the first built-in list" instead of a
special case. Phase 1 is Dart-only; native TV player parity is Phase 2.

---

## 1. Core design decisions (locked unless user objects)

1. **Unify, don't duplicate.** Favorites migrates into the new lists schema as
   a built-in, undeletable list (`id = 'favorites'`). One storage path, one
   reconcile path, one picker.
2. **Virtual-source scheme.** Each list is a virtual playlist with URL
   `list://<listId>`. Favorites keeps `favorites://` AND keeps emitting
   `isFavorites: true` in the player payload — the native ★ SAVED nav button
   does `iptvSources.firstOrNull { it.isFavorites }` (Kotlin :5782) and must
   keep finding exactly one.
3. **Gesture behavior.**
   - No custom lists exist → everything behaves exactly as today
     (hold-OK / heart = toggle Favorite).
   - ≥1 custom list exists → hold-OK (TV) and NEW row long-press (phone) open
     the **list picker** (multi-select checklist: Favorites first, then
     lists, then "+ Create new list"). The phone heart button still
     quick-toggles Favorites in all cases.
   - Verified: the row has NO existing long-press/context-menu on touch
     (`iptv_channel_row.dart:413-417` — only `onTap`), so phone long-press is
     free. On TV the key budget is fully spent (OK=play, hold-OK=favorite,
     RIGHT=schedule, LEFT=sidebar; doc at `:59-68`) — re-pointing hold-OK is
     the only option, and both hint surfaces must update with it
     (`_FavHint` `:456-467`, rail hint `iptv_results_view.dart:5011`).
4. **Snapshot rows per membership**, PLUS a `content_type` column the current
   favorites table lacks. Today `_buildFavoritesResult` hardcodes
   `duration: -1` / no contentType, so every favorite reads as live
   (`isLive == true`) — which suppresses resume bars (`_loadProgress`
   :2135-2140), skips resume in the player payload (:2472-2475), and would
   filter a movie-list out of its own in-player browse (see §5 browse-type
   fix). Storing `content_type` (and `duration`) per membership fixes lists
   AND the existing VOD-favorite bug — for NEW writes; rows migrated from
   `iptv_favorites` start NULL and are backfilled by the reconcile pass
   (§3.2/§3.3), staying live-presented until then.
5. **No feature flag.** Feature is invisible until used; only always-visible
   new UI is a "+ New list" picker entry and a Lists section in settings.
6. **Series channels can't be added to lists** (as today: series rows get
   `onFavoriteToggle: null`, grid :4213-4216; native long-click on series
   sentinel already Toasts).
7. **Provider-delete sweep applies to lists too** (channels vanish from every
   list; empty lists survive).
8. **Model hardening — `isVirtual`.** Add
   `bool get isVirtual => isFavorites || isContinueWatching || isStremioAddon || isCustomList;`
   and filter on it inside `StorageService.setIptvPlaylists`. Today nothing
   structural stops a virtual playlist from round-tripping into the
   `iptv_playlists` pref (`toJson` is unguarded; `_loadSettings` only avoids
   it by call ordering). With N `list://` entries this accident is one line
   away and would duplicate sources with identical ids.
9. **Sheet "Saved" pill stays Favorites-only.** In `iptv_channel_sheet.dart`,
   `_favoritesOnly` is overloaded: source identity (:392) AND a user-toggled
   cross-cutting filter pill (:1109-1120) that suppresses the category filter.
   N lists get NO per-list pill; a list source instead sets a new
   `_listSourceId` filter state, and the Saved pill keeps meaning "in
   Favorites" regardless of source.
10. **TV source dropdown rows stay plain text.** The TV picker is
    `StremioDropdown` whose option model is `{value, label}` only and is
    shared with See-All/Discover — not widened in v1. Icons/subtitles for
    lists exist only in the classic (phone) picker sheet.

## 2. Open decisions (ask user before/while building)

- **O1 — Source order**: RESOLVED (2026-08-01) — Favorites → Continue
  Watching → custom lists (by `position`) → real playlists. Continue's
  splice anchor becomes "directly after Favorites" by id, NOT after the
  whole virtual block (§5 splice rework), so lists always sit between
  Continue and the real playlists. One-line change if the user ever wants
  lists above Continue.
- **O2 — Home rows per list**: DEFERRED, now with hard evidence — Home
  sections are a fixed enum (`HomeSection.iptvFavorites`,
  `home_focus_controller.dart:14`) and the visibility settings use a
  hard-coded `'fav:iptv'` key (`home_sections_filter_page.dart:142`). Dynamic
  rows need a data-model change + pref migration. Not in this feature.
- **O3 — Landing selection**: keep today's rule (Favorites auto-lands when
  any favorite exists, :590-591); lists never auto-land.
- **O4 — Native long-click in Phase 2**: opens native checklist picker. Yes.
- **O5 — Backup**: RESOLVED (user, 2026-08-01) — accepted for v1. Backup
  includes nothing IPTV today (verified `backup_restore_service.dart:83-119`);
  lists inherit that gap knowingly. Revisit later if requested.

---

## 3. Storage layer

### 3.1 Schema (debrify_tv.db — `lib/services/debrify_tv_database.dart`, version 4 today)

Bump to v5. New tables:

```sql
CREATE TABLE IF NOT EXISTS iptv_lists (
  id TEXT PRIMARY KEY,              -- uuid; 'favorites' reserved built-in
  name TEXT NOT NULL,
  position INTEGER NOT NULL,
  is_builtin INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS iptv_list_channels (
  list_id TEXT NOT NULL,
  url TEXT NOT NULL,
  name TEXT NOT NULL DEFAULT '',
  logo_url TEXT NOT NULL DEFAULT '',
  channel_group TEXT NOT NULL DEFAULT '',
  playlist_id TEXT NOT NULL DEFAULT '',
  channel_number INTEGER,
  content_type TEXT,                -- NEW vs iptv_favorites (see §1.4)
  duration INTEGER,                 -- NEW; -1/live vs VOD runtime
  http_headers_json TEXT,
  added_at INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (list_id, url),
  FOREIGN KEY (list_id) REFERENCES iptv_lists(id) ON DELETE CASCADE
);
CREATE INDEX idx_iptv_list_channels_playlist ON iptv_list_channels(playlist_id);
CREATE INDEX idx_iptv_list_channels_url ON iptv_list_channels(url);
```

### 3.2 Migration — verified structure

- **`createIptvStoreTables` (:177) is shared by `onCreate`, `onUpgrade`
  (oldVersion < 3), and tests** (in-memory DBs call it directly). Change it
  to create the NEW tables + seed the builtin favorites row, and stop
  creating `iptv_favorites`. The copy+drop lives only in the new
  `if (oldVersion < 5)` branch of `onUpgrade`.
- Keep the existing `oldVersion == 3` ALTER (adds `channel_number` to
  `iptv_favorites`, :153-157) — it must run BEFORE the v5 copy so a v3→v5
  jump copies a complete row.
- **Seed the builtin row with `INSERT OR IGNORE` — NEVER `OR REPLACE`.**
  The DB opens with `PRAGMA foreign_keys = ON` (:36) and REPLACE resolves
  conflicts by DELETE+INSERT with FK actions firing — re-seeding
  `'favorites'` via REPLACE would CASCADE-delete every favorites membership.
  The seed lives in the shared `createIptvStoreTables`, which runs on every
  open path, so this would be a wipe-on-every-launch bug, not a corner case.
  Same rule for any future re-seed/repair code touching `iptv_lists`.
- v5 branch: create tables → seed builtin (OR IGNORE) → **check
  `sqlite_master` for `iptv_favorites` before the copy/drop** — a v1/v2 DB
  never had the table (today the `oldVersion < 3` branch creates it
  mid-upgrade; once `createIptvStoreTables` stops creating it, a v1/v2→v5
  path would `SELECT` from a nonexistent table). If present:
  `INSERT INTO iptv_list_channels (list_id='favorites', …) SELECT … FROM
  iptv_favorites` → `DROP TABLE iptv_favorites`. The existence check (not an
  `oldVersion >= 3` condition) also survives a half-completed prior attempt.
- **Migrated rows keep `content_type`/`duration` NULL** — meaning
  pre-existing VOD favorites STILL present as live (no resume bar) until
  backfilled. Backfill happens in the catalog-scoped reconcile pass (§3.3),
  which already walks catalog rows on a worker: extend it to emit
  url → {contentType, duration} for stored rows whose `content_type IS
  NULL` and apply in the same txn. Until a playlist is opened once,
  old VOD favorites stay live-presented — documented limitation.
- **Legacy prefs import** (`iptv_media_store.dart:108-126`, key
  `iptv_favorite_channels_v1`): retarget `_favoriteRowFromLegacy` inserts to
  `iptv_list_channels` with `list_id='favorites'`. `_ensureMigrated`'s
  memoize-and-retry error handling is untouched.
- `onDowngrade: onDatabaseDowngradeDelete` — unchanged, aware.

### 3.3 IptvMediaStore (`lib/services/iptv_media_store.dart`)

Favorites methods become thin wrappers over list methods with
`listId: 'favorites'` (call sites keep compiling, migrate opportunistically).

- `lists()` → `List<IptvListMeta>{id, name, position, isBuiltin, count}` —
  ONE query with a `GROUP BY list_id` count join. This also replaces the
  `hasFavorites` probe in `_loadSettings` (:561-562), which today re-reads
  the whole favorites store per settings pass — do NOT turn that into N
  store reads.
- `createList(name)` / `renameList` / `deleteList` (both reject
  `'favorites'`) / `reorderLists(orderedIds)`.
- `setChannelInList(listId, url, inList, {…meta + contentType, duration})` —
  canonical-match scan scoped `WHERE list_id = ?` (semantics of
  `setChannelFavorited` :321-368, per list). **Every write path MUST pass
  the new contentType/duration fields**: page `_toggleFavorite`
  (`iptv_results_view.dart:503`), sheet toggle
  (`iptv_channel_sheet.dart:279`), and the native bridge — whose Kotlin args
  today send NO contentType/duration (`toggleIptvFavorite` :6368-6377);
  Kotlin must add both from `IptvChannelEntry` (it has `contentType` from
  the payload) and the Dart handlers (`setIptvFavorite`,
  `setIptvChannelInList`) must forward them.
- `listChannels(listId)` ordered `added_at ASC, url ASC` (as today :382-392).
- `channelMembership()` → `Map<url, Set<listId>>`, one query.
- `removeListChannelsByPlaylistId(playlistId)` — sweeps ALL lists.
- **Reconcile generalization** (`reconcileFavoriteUrls` :221,
  `…ForCatalog` :270, worker job `computeFavoriteRenamesJob` :32): read
  DISTINCT urls across `iptv_list_channels`; apply renames per row.
  **The canonical map must become `Map<canonicalKey, Set<storedUrl>>`.**
  Today it's `Map<canonicalKey, String>` (:33-36, :228-230) with `.remove()`
  on first match — fine when urls were unique (single-table PK), but with
  per-list rows two lists can hold DIFFERENT historical URL forms of the
  same channel; they collide on one canonical key, the map literal keeps
  only the last, and the other list's row silently never gets renamed. The
  generalized scan maps each canonical key to the full set of stored forms
  and emits a rename for every stale form. Same change in both the
  in-memory scan and the worker job. NOTE (verified):
  `_applyFavoriteRenames` (:294-319) is delete+re-insert of the whole row,
  not an `UPDATE url` — the generalized version re-queries all rows with
  the stored url (may be several, one per list), rewrites each carrying its
  `list_id`, and keeps the re-check-inside-txn rule (a membership removed
  mid-scan stays gone). `ConflictAlgorithm.replace` on the (list_id,url) PK
  absorbs rename-collides-with-existing-row.
  **Backfill piggyback** (§3.2) — in BOTH variants, not just the worker:
  local-file and Stremio catalogs reconcile via the in-memory
  `reconcileFavoriteUrls(result.channels)` path and would otherwise leave
  their migrated VOD favorites live-classified forever. The in-memory scan
  backfills directly from the `IptvChannel` objects it already walks (they
  carry `contentType`/`duration`); the catalog-scoped worker job returns
  url → {contentType, duration} for stored rows with NULL `content_type`.
  Both apply in the same rename txn.
- `canonicalChannelKey` (:179) unchanged.

### 3.4 StorageService facade (`storage_service.dart`)

Existing passthroughs at :3026-3086 (incl. `reconcileIptvFavoriteUrlsForCatalog`
:3032) stay; add list-CRUD + membership passthroughs. Also: implement the
§1.8 `isVirtual` filter inside `setIptvPlaylists` (:5252).

Verified complete external call-site inventory (all must keep working via
compat wrappers): `iptv_results_view.dart` :475/:504/:562/:2234/:2471,
`android_tv_player_bridge.dart:683`, `search_screen.dart:2320`,
`iptv_channel_sheet.dart` :260/:279, `video_player_launcher.dart:2144`,
`iptv_settings_page.dart:550`.

---

## 4. Model layer

- `IptvPlaylist` (`iptv_playlist.dart`): add `isCustomList` (`list://`),
  `customListId`, and `isVirtual` (§1.8). Equality is id-only (:85-93) — two
  lists must never share an id; virtual instances fake `addedAt` with epoch 0
  as the existing singletons do.
- `IptvCatalogKey.forPlaylist` (`iptv_catalog_key.dart:39-44`): add
  `isCustomList` to the null-guard. **This is load-bearing**: without it a
  `list://` playlist would be keyed `m3u|list://<id>` and start ingesting
  rows into `iptv_catalog.db`.
- New `IptvListMeta` model (near the store).

---

## 5. IPTV page (`lib/widgets/iptv/iptv_results_view.dart`)

Verified inventory: **27 favorites touch points** (not ~14). Beyond the
mechanical generalizations (state maps, `_loadFavorites` :474,
`_toggleFavorite` :503, dispatch :811, `_buildFavoritesResult` :2233,
payload :2423-2432, empty state :4079-4118, hints :5011, grid :4212/:4321),
the review found these additional REQUIRED changes:

- **Player payload contract (explicit spec).** `_playerSourcePayload`
  (:2423-2432) gains two keys per source: `'isList': bool` and
  `'listId': String?` alongside the existing
  `{id, name, isFavorites, isContinue, isXtream}`. These flow to BOTH
  players untouched: the launcher forwards `args.iptvSources` verbatim
  (`video_player_launcher.dart:2189`) and the Dart sheet reads the same
  maps — so no `VideoPlayerLaunchArgs` change is needed for per-source
  flags. Phase 1 consumers: sheet source-switch branch (§10). Phase 2
  consumers: Kotlin (§12).
- **Browse content-type fix (critical for non-live lists).**
  `_providePlayerIptvBrowse` filters non-Xtream sources by `requestedType`
  which defaults to `'live'` (:2654, filter :2800-2810) and only excludes
  `isContinueWatching`. Favorites/list sources must join that exclusion (or
  filter on the now-stored `content_type`) or a movie list returns empty in
  the in-player guide.
- **Virtual singletons become a collection.** `_favoritesPlaylist`
  (:232-237) and `_continuePlaylist` are `static final` singletons; lists
  are data → build the virtual-source list dynamically in `_loadSettings`
  (:567-573 prepend block).
- **Continue-shelf splice rework.** `_refreshContinueShelfPresence`
  (:3282-3300) splices Continue at `indexWhere(isFavorites) + 1` — with N
  list rows this anchor must become "after the virtual block" per O1. Its
  surgical setState-splice-without-touching-selection pattern is ALSO the
  template for "list created/deleted from the page" refresh (see next).
- **List-mutation refresh path.** `_loadSettings` re-runs only on init,
  Stremio-addon change, and settings-route pop (:466, :471, :3337). A list
  created from the page's own picker must be spliced in surgically —
  **never via `_loadSettings`**, which re-derives landing selection and
  yanks the user off their source (explicit rule at :3210-3215). Reload
  guard :617-620 also means editing the CURRENT list's contents won't
  refresh the grid by itself → after picker close, if the visible source is
  a list whose membership changed, re-run `_buildListResult` (there's a
  precedent: `_refreshAfterPlayback`'s favorites membership diff :3229-3234
  — generalize it per-list).
- **Source-vanished fallback.** The dropdown (:3609-3634) renders option[0]'s
  label when `_selectedPlaylist` isn't in the options — no membership check.
  `firstRealPlaylist` (:583-589) skips only favorites/continue, so extend it
  to skip ALL virtuals (an empty custom list is as bad a landing). Deleting
  the currently-viewed list must explicitly re-select (reuse the
  continue-shelf-emptied fallback shape at :3240-3251). Lists may NOT be set
  as default playlist (avoids dangling `iptv_default_playlist` pref).
- **Origin-id trap.** `_loadFavorites` defaults missing `playlistId` to `''`
  and `_playerOriginPlaylistId` (:2435-2446) falls back to the source id —
  i.e. a virtual id can leak out as `source_playlist_id`. Preserve the same
  semantics for lists knowingly (or fix for both while there).
- **EPG context.** `_updateEpgContext` (:1937-1946) excludes favorites from
  `isPlainM3u` → shelves get no M3U guide context; lists inherit this.
  Accept for v1 (EPG rows still work per-channel via capability sampling);
  document as known.
- **Poster rows.** `_showsPosterRows` (:262-268) is false for favorites →
  lists also render as logo rows even when movie-only. Accept for v1.
- **Ordering.** `_buildFavoritesResult` hardcodes alphabetical sort
  (:2251-2253). Keep for v1 (matches favorites); if per-list manual ordering
  is ever wanted, the store must return ordered rows and this sort becomes
  conditional (`_buildContinueResult` :2226 is the order-preserving
  precedent). Not in scope now.
- Reconcile skip (:957-960) + the unconditional `_loadFavorites()` at :962
  → skip lists too; the post-present reload becomes a membership-map reload.

## 6. Channel row (`iptv_channel_row.dart`)

As planned (§1.3), now verified: add `onOpenListPicker`; TV hold-OK fires it
when non-null else `onFavoriteToggle` (:148-155 status listener, :373-400 key
handling); NEW `onLongPress` on the GestureDetector (:413-417) for touch —
no conflict exists. Update `_FavHint` text and rail hint when picker mode is
active. Keep heart fill animation only for direct-toggle mode.

## 7. New widget: IptvListPickerDialog

`lib/widgets/iptv/iptv_list_picker_dialog.dart`. REVISED expectation:
`ChannelPickerDialog` is **low reuse** — it's Debrify-TV-domain
(repo/cache imports), single-select-pop control flow, different result type.
What we take from it: the Dialog + FocusNode/DPAD scaffolding, the Back-key
trap (:381-396), the inline `TvTextField` create form (:398) with
`onSubmitted` focus-hop, and the tile visuals. The multi-select instant-apply
checklist (no pop on toggle, live `setChannelInList` writes, "Done"/BACK to
close) is written fresh. Name validation: trimmed, non-empty,
case-insensitive-unique. In-app keyboard on TV; never `node.onKeyEvent` on
TvTextField nodes.

## 8. Source pickers — there are TWO (plan correction)

- **TV/desktop (primary): `StremioDropdown`** at `iptv_results_view.dart:
  3603-3629` — options are `{value, label}` only; search field is disabled
  on TV by design (`stremio_dropdown.dart:460-465`). Add list rows as plain
  labels + a `_kNewListSentinel` option modeled exactly on the existing
  `_kAddPlaylistSentinel` (:3695, handled :3620-3623). No option-model
  widening in v1 (§1.10). Known consequence: many lists = long unsearchable
  TV picker; acceptable at expected list counts.
- **Classic/phone sheet: `iptv_filters.dart`** — `_PlaylistPickerSheet`
  takes `List<IptvPlaylist>` domain objects; list tiles get their own
  icon/subtitle beside the favorites tile (:797-810), and the "+ New list"
  tile follows the existing "Add Playlist" tile pattern (:812-828; focus
  node count already parameterized :679-682). Selected-chip icon branch
  :311-317 gains a list glyph.
- Long-press a list tile (classic) / no equivalent on TV dropdown → TV list
  management lives in Settings only.

## 9. IPTV Settings (`iptv_settings_page.dart`)

- New "Lists" section AFTER the providers card, using
  `SettingsSectionLabel` + hint + empty-state Card + Card(Column) shape
  (:1110-1138 precedent). There is NO header-add-button precedent on this
  page — creation goes through a "+ Create list" row rendered as the
  section's first/last tile opening the name dialog.
- **Focus nodes: a NEW dedicated node array** for the section. Verified the
  providers list uses hand-rolled `row * 4` stride arithmetic
  (:569, :693-702, `_ensureFocusNodes` :161-172) — do not extend it.
- Row actions: Rename / Delete (confirm: "Delete '<name>'? Channels are not
  deleted."). Reorder: up/down buttons (no drag precedent on this page;
  DPAD-friendly) writing `reorderLists`.
- Provider delete: swap :550 to `removeListChannelsByPlaylistId` (watch
  history sweep at :551 unchanged).
- Settings-search: add "IPTV lists" leaf entries.

## 10. In-player Dart sheet (`iptv_channel_sheet.dart`)

Verified: the sheet has exactly ONE source-flag branch (`:392`), everything
else keys off `_contentType`/browse callbacks — so `list://` sources Just
Work via `_providePlayerIptvBrowse` once §5's dispatch + catalog-key changes
land. Changes here are only: (a) don't set `_favoritesOnly` for list sources
(§1.9 — add `_listSourceId` instead, applied in the filter at :232), (b)
hearts (:1177-1190, :1331-1337, :2041-2047) stay Favorites-only, (c) no
in-sheet list picker in Phase 1.

## 11. Home row (`search_screen.dart`)

Unchanged (O2 deferred — enum + `'fav:iptv'` key evidence in §2).
`_loadIptvFavorites` (:2318-2348) keeps reading the favorites list via the
compat facade.

## 12. Phase 2 — Native Android TV player parity

Corrections from review, then the work:

- The badge is a **star** (`item_iptv_channel.xml:106-116`, "★"), not a
  heart; the nav button is "★ SAVED" (`view_iptv_channel_guide.xml:89-101`).
- "Zap hidden in Favorites" was WRONG: `:8285` hides only the jump-by-number
  hint; `:6983` blocks the channel-jump dialog. Channel up/down zapping
  WORKS in favorites and will work in lists. Extend only the jump-by-number
  block to list sources.
- **Sources are parsed ONCE at launch** (`parseIptvSources` called only at
  :5234). Dart re-sends `sources` in every browse response but Kotlin never
  re-parses. Consequence: lists created/deleted while the native player is
  open don't appear until relaunch. ACCEPT + document for Phase 2 v1 (or
  small fix: re-parse sources from browse responses — optional stretch).
- **Source picker whitelists nothing** (`showIptvSourcePicker` :6022-6033
  lists all non-continue sources) → `list://` sources appear with zero
  Kotlin UI changes, PROVIDED: non-empty id, `isContinue=false`, and a
  `source.isList -> "live"` arm added next to :6012 (a lingering "vod"
  content-type state otherwise passes through and mis-browses a live list).
- **New-field edit sites are FOUR**, not two: JSONArray parse :5369, List
  parse :5425, and the `iptvChannelEntry(...)` factory :5448 (param) +
  :5474 (assignment). (`:13214 isFavorite` is StremioTvGuideChannel — a
  different feature; ignore.)
- **Checklist dialog precedent: NONE exists** (no multi-choice/CheckBox in
  the activity). Clone `showIptvCategoryPicker` (:6034-6194) +
  `IptvCategoryAdapter` (:6195-6259): themed AlertDialog + RecyclerView of
  focusable rows with `isSelected` styling — all DPAD plumbing already
  solved there. Convert to multi-select with a `MutableSet` + Done button.
  No create-new natively.
- **Membership data: do NOT ship per-channel `listIds` in the launch
  payload.** The channel payload is capped at 1500 entries with a
  documented UI-freeze history (`_kMaxPlayerChannels`,
  `iptv_results_view.dart:2405-2411`). Instead ship a small top-level
  `lists: [{id, name}]` array once, and fetch a channel's membership
  on-demand when the picker opens via a new bridge method
  (`getIptvChannelListMembership(url)` — static handler, like
  `setIptvFavorite`).
- **Full contract edit list for Phase 2** (explicit, so nothing is missed):
  1. Dart: per-source `isList`/`listId` already emitted by
     `_playerSourcePayload` (Phase 1, §5) — flows through unchanged.
  2. Dart: NEW top-level `'lists': [{id, name}]` launch-payload key — this
     one does NOT exist today, so: new `iptvLists` field on
     `VideoPlayerLaunchArgs` (+ ctor threading), populated by
     `iptv_results_view.dart` at launch, emitted by the launcher next to
     `'sources'` (:2189).
  3. Kotlin: `IptvSourceEntry` (:13135-13141) gains
     `isList: Boolean, listId: String?`; `parseIptvSources` (:5335-5346)
     reads them.
  4. Kotlin: parse the top-level `lists` array in `initIptvMode` (:5223).
  5. Kotlin: `selectIptvSource` coercion arm `source.isList -> "live"`
     (next to :6012).
  6. Kotlin channel entries: only if a per-channel field is ever added —
     remember the FOUR edit sites (:5369, :5425, :5448, :5474). The chosen
     design adds none.
  7. Bridge: `setIptvChannelInList` + `getIptvChannelListMembership`
     handlers (static) beside `setIptvFavorite`
     (`android_tv_player_bridge.dart:668-692`); Kotlin toggle args gain
     `contentType`/`duration` (§3.3 write-path rule).
- **Writes**: new `setIptvChannelInList {listId, url, inList, meta…}` case
  beside `setIptvFavorite` (`android_tv_player_bridge.dart:668-692`).
  Verified this handler is STATIC (works with the IPTV page unmounted,
  unlike the browse provider) — keep the new one static too. Kotlin call is
  fire-and-forget with an optimistic Toast (no Result callback) — same
  pattern, accepted.
- Local-state caveat (existing behavior, inherited): Kotlin mutates
  `entry.isFavorite` optimistically and only resyncs on the next browse
  round-trip; removing a channel from the list being viewed leaves the row
  until next browse. Accept.
- ★ SAVED button + `firstOrNull { it.isFavorites }` (:5782) keeps working
  because Favorites keeps its flag (§1.2).

## 13. Edge cases & invariants checklist

- [ ] Toggling in the picker while viewing that list → row removal without
      focus loss (focus-preserving reconcile pattern).
- [ ] Canonical-duplicate insert per list (Xtream credential drift) — one
      membership row per (list, canonical channel).
- [ ] Reconcile never resurrects a membership removed mid-scan (re-check in
      apply txn, per (list_id, url); rename rewrites EVERY list's row).
- [ ] Provider delete: memberships swept from all lists; empty lists render
      empty state.
- [ ] Deleting the currently-viewed list: explicit re-select fallback; lists
      cannot be default playlist; dropdown never left rendering a phantom
      option[0] label.
- [ ] Virtual playlists can never persist into `iptv_playlists` pref
      (`isVirtual` filter in `setIptvPlaylists`).
- [ ] `list://` never reaches `IptvCatalogKey`/catalog DB ingestion.
- [ ] `stremio-tv://` synthetic URLs pass canonicalization untouched; list
      membership works for Stremio addon channels.
- [ ] Series rows: both gestures inert (as today).
- [ ] Duplicate URLs within a playlist: same membership state on both rows —
      acceptable, documented.
- [ ] Movie/VOD channels in a list: browse-type fix (§5) verified in the
      in-player guide; resume bars appear (content_type stored).
- [ ] Legacy prefs import lands in new schema; v3→v5 upgrade path copies
      `channel_number`.
- [ ] 'favorites' list: cannot rename/delete/reorder-below-0; always emits
      `isFavorites: true` to the player payload.
- [ ] Sheet: switching to a list source does not light the "Saved" pill;
      switching away clears the list filter.

## 14. Tests

- `test/iptv_media_store_test.dart`: list CRUD, membership map, per-list
  canonical dedup, cross-list provider sweep, builtin protections, reorder,
  content_type round-trip.
- `test/iptv_favorites_reconcile_test.dart` → multi-list reconcile:
  (a) same URL in 2 lists renames both rows; (b) **DIFFERENT historical URL
  forms of the same channel in 2 different lists — both get renamed to the
  current form** (this is the case the Set-valued canonical map exists for;
  a same-URL-only test would pass with the old buggy map); (c) mid-scan
  removal not resurrected; (d) NULL-content_type backfill applied — tested
  through BOTH variants: the in-memory `reconcileFavoriteUrls(channels)`
  path (a VOD channel with a runtime backfills a NULL row) AND the
  catalog-scoped worker job.
- Migration tests: **v1→v5 and v2→v5** (no `iptv_favorites` table ever
  existed — copy step must no-op via the sqlite_master guard), v3→v5
  (ALTER + copy, `channel_number` preserved), v4→v5 (rows under
  'favorites', old table dropped, ordering preserved). Re-running the seed
  (`createIptvStoreTables` on an existing DB) must NOT touch memberships
  (guards the OR IGNORE rule). Fresh-create path — existing tests that call
  `createIptvStoreTables` directly must be updated to the new schema.

## 15. Delivery order (uncommitted-step workflow — one step, user tests, commit, next)

- **Step 1 — Storage + models + tests.** §3, §4, §14. No UI change;
  favorites runs through compat wrappers. Verifiable via `flutter test`.
- **Step 2 — Page + picker + row + source pickers.** §5, §6, §7, §8.
  Create lists, add channels, browse a list; phone + TV.
- **Step 3 — Settings + sheet + polish.** §9, §10, empty states, §13 sweep.
- **Step 4 (Phase 2) — Native player.** §12. Needs TV device test.

Estimate: Steps 1–3 ≈ 2 days (review added the browse-type fix, splice
rework, and two-picker reality); Step 4 ≈ 1–1.5 days incl. device testing.

## 16. Explicitly deferred

- Home rows per custom list (O2 — enum/pref-key migration).
- Per-list manual channel ordering (store is ready; UI sort stays A–Z).
- List picker inside the in-player sheet.
- Native create-new-list; native live source refresh (launch-frozen sources).
- Backup inclusion (O5), sharing/export, cross-device sync.
- Poster rows + EPG context for list shelves (inherit favorites behavior).
- Smart lists / auto-rules.
