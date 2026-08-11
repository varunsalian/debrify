# Home Rows: Trakt/Simkl lists + IPTV custom lists on Home

## Goal

Let users pick extra rows for the Home board from what Discover already offers,
via the existing **Settings → Home Page → Home Rows** two-pane manager:

1. **Trakt list rows** — Watchlist, History, Collection, Ratings,
   Recommendations, Trending, Popular, Anticipated, plus the user's **custom
   lists** and **liked lists**.
2. **Simkl list rows** — Plan to Watch, Watching, On Hold, Completed, Dropped,
   Ratings, Trending, Top Rated, New & Upcoming.
3. **IPTV custom list rows** — one Home row per `list://` custom list (the
   built-in Favorites list is already the `fav:iptv` row).

**Defaults = today.** Every new row is **opt-in (default OFF)**; nothing about
the current board changes until the user turns a row on. Addon-catalog
hide/unhide already exists and is untouched. **No reordering** (out of scope).

Non-goals: reorder, per-row genre filters, MDBList rows (alpha-hidden), Trakt/
Simkl calendars, per-channel IPTV hiding.

## Where things stand today (verified against code)

- Home = `SearchScreen` (`lib/screens/search_screen.dart`, ~22.4k lines). One
  file serves phone classic + 7 TV layouts (classic/canvas/atrium/mosaic/
  promenade/deck/tonight).
- Row families:
  - `_CwRow` continue-watching rows — hardcoded list at `_cwRows` (:823), with
    a duplicated allocation-free `_cwVisible` gate (:953).
  - Favourites rows — `enum _FavKind {iptv, debrify, stremio, playlist}`;
    visible list `_favRowKinds` (:2308); per-kind helpers `_favNodesFor`
    (:2319), `_canvasFavItemCount` (:4843), `_canvasFavTitle` (:4856),
    `_buildFavRow` (:14618); ~50 `favKind` touchpoints across the 6 stage
    layouts (grep `favKind`).
  - Addon catalog rows — `CatalogSection` list `_sections`, fed from
    `_boardRefs` in `_load()` (:1745), batched by `_fetchBoardBatch` (:1810),
    appended by `_appendSections` (:1898), paged per-row by `_loadMoreRow`
    (:1916), reseeded by `_applySections` (:3594). Stage layouts index it via
    `_CanvasRail.sectionIndex` and the `sec:<i>` positional rail keys.
- Hidden rows: `home_disabled_sections_v1` (OFF-ids set,
  `StorageService.get/setHomeDisabledSections`, storage_service.dart:6573).
  Managed by `HomeSectionsFilterPage`
  (`lib/screens/settings/home_sections_filter_page.dart`), opened from
  `home_page_settings_page.dart:_openHomeRowsManager` (:180), which fires
  `MainPageBridge.notifyHomeSettingsChanged()` → `_reloadForHomeSettings`
  (:1718) diffs the disabled set and re-runs `_load()`.
- List loaders already exist and return `List<StremioMeta>`:
  - `TraktListSource.loadList(TraktListChoice)` +
    `loadUserLists()` (`lib/services/trakt/trakt_list_source.dart`).
  - `SimklListSource.loadList(SimklSeeAllList)`
    (`lib/services/simkl/simkl_list_source.dart`).
- Opening a plain (non-CW) tracker-list title already has a proven path:
  `_openSimklItem` / `_playSimklItem` (:2944/:2950) route through
  `_addonForContinue(item.sourceAddon?.id)` (:2915). Note its fallback is
  `_homeSections.first.addon` — a trap once virtual sections lead the list
  (must skip them).
- See All: `TraktSeeAllScreen` / `SimklSeeAllScreen` always open on Continue
  Watching / auto-pick — **no `initialList` param yet**.
- IPTV lists: SQLite `iptv_lists` / `iptv_list_channels`
  (`lib/services/iptv_media_store.dart`), facade
  `StorageService.getIptvLists()` / `getIptvListChannels(listId)`
  (storage_service.dart:3426/:3478). Home's IPTV favourites row builds
  `IptvChannel`s from stored meta (`_loadIptvFavorites` :2565) and plays via
  `_playIptvChannel`; DPAD focus retunes the hero to the live stream
  (`_setHeroLiveIptv`).

## Design

### Row identity + storage

New id grammar (leaf ids; never collide with existing `cw:`/`trakt:`/`simkl:`/
`iptv:`/`fav:`/`addonId:type:catalogId` ids):

| Row | Id |
|---|---|
| Trakt built-in list | `traktlist:<apiValue>` e.g. `traktlist:watchlist` |
| Trakt custom list | `traktlist:custom:<traktListId>` |
| Trakt liked list | `traktlist:liked:<traktListId>` |
| Simkl list | `simkllist:<enumName>` e.g. `simkllist:planToWatch` |
| IPTV custom list | `iptvlist:<listId>` |

These rows are **default-OFF**, so the OFF-ids store can't express them. New
SharedPreferences key **`home_extra_rows_v1`**: JSON array of
`{"id": "...", "title": "..."}` — the opted-in rows. `title` is the display
name captured at opt-in time for dynamic rows (custom/liked lists, IPTV lists)
so the row header renders instantly and survives an API hiccup; built-ins
ignore the stored title (label from the enum). Order in the pref is
irrelevant — render order is canonical (Trakt built-ins in enum order, then
Trakt custom, then liked, then Simkl in enum order; IPTV list rows in
`iptv_lists.position` order).

`StorageService`: `HomeExtraRow` record (`({String id, String title})`),
`getHomeExtraRows()` / `setHomeExtraRows(...)` (remove key when empty),
mirroring the disabled-sections pair. Corrupt JSON → `[]` (matches
`getHomeDisabledSections`).

### Resolver service — `lib/services/home_list_rows.dart` (new)

`HomeListRowsService` (stateless singleton, mirroring `TraktListSource`):

- `Future<List<HomeListSection>> resolve(List<HomeExtraRow> enabled,
  {Duration? deadline})` — returns board-ready sections directly (each
  carries `rowId` + `traktChoice`/`simklList` for See-All routing; no
  intermediate data type needed). With a deadline, returns the rows whose
  fetches completed by then (canonical order), dropping only stragglers —
  see the board section for why.
- Returns `const []` immediately when no `traktlist:`/`simkllist:` ids are
  enabled — **zero added work in the default config**.
- Built-ins fetch via the existing sources in parallel (`Future.wait`), each
  wrapped so one failure can't sink the batch. Failed or empty lists are
  dropped (row simply doesn't appear — same as empty catalogs).
- Custom/liked ids: one `TraktListSource.loadUserLists()` call (only when such
  ids are enabled) to re-resolve the raw list maps by id, then fetch each
  matched list's items. Vanished (deleted/unliked) lists drop silently.
- Auth: unauthenticated private lists fail inside the loaders and drop —
  same UX as the existing `trakt:movies` CW leaf when unauthenticated.
- Loader functions are constructor-injectable (defaulting to the real
  singletons) so unit tests don't need network.

IPTV rows are *not* in this service (different item type, different render
path) — see Phase 3.

### Home board: Trakt/Simkl rows = virtual sections

A new `HomeListSection extends CatalogSection` (lives in
`home_list_rows.dart`): carries `rowId` + `traktChoice`/`simklList`,
constructed with a shared **placeholder addon** (same shape as
`_addonForContinue`'s fallback: empty `manifestUrl`/`baseUrl`, ids
`debrify.home.trakt` / `debrify.home.simkl`), a synthetic catalog, and
`exhausted: true` (no paging, `_loadMoreRow` early-returns on it; the
horizontal spinner never shows).

Why sections and not a new row family: `_sections` already flows through the
classic ListView, all 6 stage layouts, `_rowNodes` focus bookkeeping, hero
seeding, search-detour restore (`_applySections(_homeSections)`), and the
entrance animation — a new family would need all of that re-threaded by hand.

Integration points in `search_screen.dart`:

1. `_load()` (:1745): read extras alongside the disabled set; run
   `HomeListRowsService.resolve(...)` **in parallel** with
   `_fetchBoardBatchUntilNonEmpty()` (`Future.wait`), with a **5s timeout**
   on the list-rows future. Then
   `_homeSections = [...listSections, ...firstBatch]` — list rows sit after
   the favourites rows and before every addon row. `_boardCursor` batching
   appends after them untouched.
   **Explicit tradeoff:** when tracker rows are enabled, first paint / splash
   release (`MainPageBridge.homeBoardReady`) waits for
   `max(firstBatch, min(listRows, 5s))` — an accepted, opt-in cost, chosen
   over late-prepending rows (which would need an `_applySections` reseed
   that nukes focus/rail identity mid-arrival). Zero cost when no extras are
   enabled.
   **The 5s deadline is per-row-collecting, not all-or-nothing:** the
   resolver starts every fetch, then at `min(allDone, 5s)` returns the rows
   whose fetches HAVE completed (canonical order preserved) and drops only
   the stragglers — one slow list must not discard every already-loaded row
   (individual provider calls allow 15s internally, so an aggregate
   `.timeout()` would realistically fire). Straggler requests aren't
   cancelled (Dart timeouts don't cancel); their results are dropped.
   **Concurrency cap:** the resolver runs at most 3 list fetches per provider
   at a time (each Trakt built-in fans out 2 HTTP calls, Simkl lists up to 3
   — an uncapped "everything enabled" config would fire ~30 concurrent
   requests and invite throttling).
2. **Board load generation token.** `_load()` re-entry already races
   (`_reloadForHomeSettings` today; this plan adds an integrations trigger),
   and stale loads mutate shared `_boardRefs`/`_boardCursor`/`_homeSections`.
   Add `int _boardLoadGen`; `_load()` captures `++_boardLoadGen` and threads
   it through `_fetchBoardBatchUntilNonEmpty` → `_fetchBoardBatch` (bail
   before advancing the cursor when stale) and checks it after every await
   before touching shared state (`_homeSections`, `_applySections`,
   `homeBoardReady`, `_loading`). `_loadMoreBoard` captures the current gen
   the same way. This fixes the pre-existing race class rather than adding
   to it.
3. `_addonForContinue` (:2915): fallback must skip `HomeListSection`s when
   picking "any homepage addon".
4. Item open / quick-play: **source-aware dispatchers**, not just an addon
   swap — Trakt items must keep Trakt semantics (`isTraktSource: true`,
   resume via Trakt), exactly as Discover's `TraktSeeAllScreen` wiring does:
   `void _sectionOpenItem(CatalogSection s, StremioMeta item)` /
   `_sectionQuickPlay(...)`:
   - `HomeListSection` (trakt) → `_openTraktItem` / `_playTraktItem`
     (the same handlers `_openTraktSeeAll` passes for every Trakt list).
   - `HomeListSection` (simkl) → `_openSimklItem` / `_playSimklItem`
     (:2944/:2950 — Discover's plain Simkl-list routing).
   - real sections → today's `_openItem(item, section.addon)` /
     `_onCatalogPlay(item, section.addon)`.
   Used at the ~10 `section.addon` open/quick-play call sites (classic
   `_buildRow` :14470/:14479 + the 5 stage-layout sites at
   :5161/:5183/:5591/:5605/:6064/:6087/:6431/:6449/:6840/:6858).
5. See All: `_openCatalogSeeAll` (:14098) branches on `HomeListSection` →
   push `TraktSeeAllScreen(initialList: choice, ...)` /
   `SimklSeeAllScreen(initialList: list, ...)` with the same
   `.then((_) => _refreshAfterPlayback(trackers: true))` as `_openTraktSeeAll`
   (:14253). CW items/progress passed as today so the user can still switch
   lists inside the screen — and the **Simkl push must wire the separate CW
   handlers** (`cwOnOpen: _openSimklCwItem`, `cwOnQuickPlay:
   _playSimklCwItem`, mirroring Discover's wiring at :13314): without them a
   switch to Continue Watching inside the screen would open/play without
   resume semantics (`SimklSeeAllScreen` falls back to the plain handlers).
6. `_sectionTypeLabel`: return the source name ('Trakt' / 'Simkl') for
   virtual sections so the rail header tag reads "Watchlist · Trakt".
7. Reload triggers:
   - `_reloadForHomeSettings` (:1718): ALSO diff the enabled-extras list
     (ids + titles) before deciding "unchanged".
   - `_onIntegrationsChanged` (:1447): Trakt/Simkl connect/disconnect →
     reload only when any tracker list rows are enabled (cheap check) **and
     only on the Home board variant** (`!widget.searchMode &&
     !widget.discoverMode` — the listener is registered by every
     `SearchScreen` variant, and Search/Discover intentionally never run the
     board pipeline; an unconditional `_load()` would stomp their active
     `_sections`). Safe under the generation token.
   - **Search-detour guard for triggered reloads.** `_load()` visibly resets
     `_loading`/`_sections` — running it while a Home catalog search is
     showing its results (`_catalogQuery.isNotEmpty || _catalogSearching`)
     would stomp the search view (`_loadMoreBoard` :1877 already models the
     required discipline: cache may grow, the visible view may not change
     mid-search). Both triggered reload paths (`_reloadForHomeSettings` —
     where this stomp is a latent pre-existing bug our extras-diff would
     make likelier — and the new integrations trigger) route through a
     `_requestBoardReload()` helper: if a search detour is active, latch
     `_pendingBoardReload` instead of loading; `_restoreHome` consumes the
     latch and runs `_load()` then. The initial `initState` load is
     unaffected.
   - Deliberately NOT refreshed per-playback (`_refreshAfterPlayback`) —
     list membership isn't playback state; next board reload picks changes
     up. (Documented behavior.)
8. Hero/trailer/focus: nothing special — virtual sections are ordinary
   sections (StremioMeta items), `sec:<i>` positional keys behave as today.

### See-All screens: `initialList`

- `TraktSeeAllScreen`: new optional `TraktListChoice? initialList`. In
  `initState`, when set and not CW: select it and fetch via the existing
  `_fetchList` (:462). For a custom/liked choice: set `_group` AND **seed the
  matching `_customLists`/`_likedLists` array with the choice synchronously**
  (both dropdowns derive their options from those arrays, which
  `_loadUserLists()` fills async — an unseeded choice renders a blank
  dropdown until/unless that fetch lands). When the async refresh arrives,
  merge by list id, preserving the seeded choice if the refresh fails or no
  longer contains it.
- `SimklSeeAllScreen`: new optional `SimklSeeAllList? initialList`. When set:
  overrides the CW/Trending auto-pick and sets `_autoList = false` so a
  late-arriving CW list can't hijack it; fetch as the existing non-CW path
  does.
- Both default null → behavior byte-for-byte identical to today.

### IPTV custom list rows (favourites-row family)

- Generalize the favourites row descriptor: `_favRowKinds` returns
  `List<_FavRowRef>` where `_FavRowRef = {kind: _FavKind, listIndex: int}`
  (`listIndex == -1` for the four singleton rows; `>= 0` indexes
  `_iptvListRows` for `kind == iptv` list rows). All kind-keyed helpers take
  the ref: `_favNodesFor`, `_canvasFavItemCount`, `_canvasFavTitle`,
  `_buildFavRow`, `_canvasFavFocused`, and `_CanvasRail.favKind` →
  `_CanvasRail.fav` (~50 mechanical touchpoints; grep `favKind`).
  `_canvasRailKeyOf` emits `fav:iptvlist:<listId>` for list rows (stays
  content-addressed).
- State: `List<_IptvListRow> _iptvListRows` where
  `_IptvListRow = {listId, title, channels List<IptvChannel>, nodes}`.
  Loader `_loadIptvListRows()`: for each enabled `iptvlist:` extra →
  `StorageService.getIptvListChannels(id)` → `IptvChannel`s reconstructing
  **all stored presentation fields** — `contentType`, `duration`,
  `channelNumber`, `group`, `httpHeaders` (the store keeps them all; do NOT
  copy `_loadIptvFavorites`' lossy `duration: -1` mapping — lists can contain
  VOD, not just live). **Kept in list order** (added_at — the user's
  curation, unlike the name-sorted favourites row). Rows render only when
  non-empty (same as every fav row). A deleted list's row drops (channels
  cascade-delete); titles come fresh from `getIptvLists()` at load.
- **Content-aware play + preview**, keyed off the reconstructed
  `contentType`/URL scheme, mirroring how the IPTV page routes the same
  entries (verify exact routing there at implementation):
  - live → `_playIptvChannel` + hero live retune (`_setHeroLiveIptv`),
    exactly like the favourites row;
  - VOD → the IPTV page's VOD launch path (resume-capable), **no** live hero
    preview (focus clears the live feed like non-IPTV fav rows do);
  - `xtream-series://` sentinel (if the picker can store one) → series
    routing à la `IptvCwRouter.open`.
  Row tag is `List` (not `Live` — the row can be mixed).
- **FocusNode ownership:** `_loadIptvListRows()` reconciles by `listId` —
  surviving rows keep their node lists (synced to the new channel count like
  `_syncIptvFavNodes`), removed rows' nodes are disposed (after moving focus
  to a surviving rail if one of them held it), and `State.dispose()` disposes
  every remaining row-owned node.
- **Invalidation:** IPTV list mutations happen outside Home (IPTV page
  dialogs, IPTV settings, transfer/import, URL reconciliation) and today
  nothing tells Home. Signal **at the mutation boundary, on the store
  itself**: `IptvMediaStore.listsRevision` (`ValueNotifier<int>`), bumped by
  every method that writes `iptv_lists`/`iptv_list_channels` —
  `createList`/`renameList`/`deleteList`/`reorderLists`,
  `setChannelInList`, `removeListChannelsByPlaylistId` (provider deletion),
  `reconcileFavoriteUrls[ForCatalog]` (only when rows actually changed), and
  the transfer-apply paths (which already funnel through the store). Home
  listens and re-runs `_loadIptvListRows()`. A facade-level notifier was
  rejected — provider deletion and reconciliation bypass the five obvious
  facades and would leave Home holding removed/dead URLs. This also covers
  renames — the earlier claim that title changes "need no reload" was wrong
  for a Home that stays alive across tab switches.
- **Stale-load guard:** `_loadIptvListRows()` is token-guarded
  (`_iptvListRowsLoadToken`, same pattern as `_cwLoadToken` /
  `_iptvCwLoadToken`): the picker queues several immediate mutations, each
  bumping the revision — an older multi-list read must not commit after a
  newer one (it would restore stale channels and reconcile/dispose against
  newer FocusNodes). Only the newest load applies state.
- Kickoff in `initState`'s `_settleAutoFocusAfter([...])` (:1390) +
  re-run from `_reloadForHomeSettings`.
- Render: `_buildIptvListRow(ref, ...)` through `_buildFavRowShell` (classic)
  and a new `listIndex` branch in `_canvasFavCell` (:4442 — the single shared
  fav-cell builder all six stage layouts use), title = list name. Rows appear
  after the `fav:iptv` row in `_favRowKinds` order.
- Tonight layout: untouched — only CW rails move to its queue.

### Settings manager expansion

`HomeSectionsFilterPage`:

- `_Item` gains `defaultOn` (true = existing disabled-set semantics; false =
  opt-in, persisted to `home_extra_rows_v1`) and `storedTitle`.
- `_persist()` splits: OFF default-on ids → `setHomeDisabledSections`; ON
  opt-in ids (+titles) → `setHomeExtraRows`. Both writes happen on save.
- **Never destroy selections the model can't see.** `loadUserLists()` returns
  `[]` on disconnect/error — if the manager rebuilt `home_extra_rows_v1`
  purely from rendered leaves, opening it during a Trakt outage and toggling
  anything would silently delete every enabled custom/liked row. Rule:
  enabled extras that didn't resolve into a leaf are **materialized as
  "unavailable" leaves** from their stored titles (dimmed, still toggleable
  OFF) — so they're representable, survive a save verbatim unless the user
  deliberately turns them off, and come back when Trakt reconnects. Same rule
  covers an IPTV-lists read failure.
- Groups:
  - **Trakt** group grows list leaves (8 built-ins, badge `LIST`), then
    fetched custom lists (badge `CUSTOM`) and liked lists (badge `LIKED`).
    Built-ins always shown (matches today's `trakt:movies` leaves shown even
    unauthenticated — the row is simply absent on Home until sign-in).
  - **Simkl** group grows its 9 list leaves (badge `LIST`).
  - New **IPTV Lists** group (only when custom lists exist), one leaf per
    list (badge `LIST`). Favorites stays where it is (`fav:iptv`).
- New widget inputs: `extraRows` (current enabled set), `traktUserLists`
  (pre-fetched choices, may be empty), `iptvLists` (pre-fetched metas).
- `home_page_settings_page._openHomeRowsManager` (:180): gather inputs before
  push — `getHomeExtraRows()`, `getIptvLists()`, and (only when Trakt is
  authenticated) `TraktListSource.loadUserLists()` with a ~5s timeout; failure
  → built-ins only. Brief inline busy state on the tile while gathering.

### Explicitly unchanged

`_cwRows`/`_cwVisible`, skeleton reservation, Tonight queue, `sec:` positional
keys, addon-row batching, search detour, Discover, settings search index,
`home_disabled_sections_v1` semantics for existing ids.

## Phases (each ends with a Codex review; fixes applied before the next)

**Phase 1 — data layer.** `HomeExtraRow` + storage pair;
`home_list_rows.dart` (resolver with per-provider concurrency cap +
`HomeListSection`); `initialList` on both See-All screens (incl. custom/liked
seeding); unit tests (`test/home_extra_rows_test.dart`): storage round-trip +
corrupt JSON, id grammar parse, resolver ordering / partial-failure /
empty-input short-circuit / concurrency cap (injected loaders).

**Phase 2 — board wiring.** Board load generation token; `_load()` parallel
fetch + 5s timeout; ordering; `_addonForContinue` skip; source-aware
`_sectionOpenItem`/`_sectionQuickPlay` at the ~10 call sites;
`_openCatalogSeeAll` branch; `_sectionTypeLabel`; reload triggers
(settings-diff incl. extras, integrations). Verify classic + stage layouts
against unchanged section plumbing.

**Phase 3 — IPTV list rows.** `_FavRowRef` generalization (mechanical sweep of
the ~50 `favKind` touchpoints incl. `_canvasFavCell`); `_iptvListRows` state +
content-aware loader/play + node reconciliation + load token + row builder;
rail keys; `IptvMediaStore.listsRevision` bumps at the mutation boundary +
Home listener.

**Phase 4 — settings.** `HomeSectionsFilterPage` dual-store model + new
groups + unavailable-leaf preservation rule; `_openHomeRowsManager` data
gathering; `_reloadForHomeSettings` extras diff (if not landed in Phase 2).

**Final.** Full Codex review over the feature diff, `flutter analyze` clean,
`flutter test` (8 pre-existing failures in the repo are known/unrelated),
everything left uncommitted for device testing.

## Risks / watchpoints

1. **`_addonForContinue` fallback** returning the placeholder addon once
   virtual sections lead `_homeSections` — must skip `HomeListSection`
   (test-worthy).
2. **First-paint latency** when tracker rows are enabled — explicit accepted
   tradeoff (see board item 1): bounded by the 5s timeout + per-provider
   concurrency cap; zero-cost when disabled.
3. **favKind sweep breadth** — mechanical, and helper signature changes make
   the compiler find every site; the real risk is DPAD wiring
   (`_favRowOnUp/_favRowOnDown` are already favIndex-based, so extra rows
   slot in; verify on the stage layouts + Tonight's rail zone).
4. **Duplicate rows**: a user can enable `traktlist:watchlist` while an addon
   also has a watchlist catalog — fine, they're distinct rows (same as two
   addons with Trending today).
5. **`_load()` re-entry** — fixed properly by the generation token (board
   item 2), which also covers the new integrations trigger.
6. **Manager data loss on tracker outage** — covered by the
   unavailable-leaf rule (settings section); test the
   "outage → toggle unrelated leaf → save → extras preserved" path.
7. **VOD-in-list semantics** — content-aware routing keyed off stored
   `contentType`; live hero preview only for live entries.
