# IPTV Startup Channel — Plan

**Goal:** when the app cold-starts, tune straight into a live IPTV channel in the
player, set-top-box style. Backing out of the player leaves the user on the IPTV
page with that channel focused, and the app behaves normally from there.

**Status:** **All 5 steps implemented (uncommitted, device test pending).**
`flutter analyze` = 0 errors; `compileDebugKotlin` = BUILD SUCCESSFUL. Nothing
verified on hardware yet — every remaining risk in §7 is a timing/lifecycle one
that only reproduces on a TV. All §11 decisions taken (see that table).
**Reviewed:** six rounds (§9 … §9f) — 34 defects found and folded in.
**Scope:** live channels only. No VOD, no series, no Continue Watching.
**Flag/default:** off by default. TV-first; phone gets the same setting but it
stays off unless deliberately enabled.

---

## 1. Background — this existed before

Commit `0377e9e` (2026-07-15) removed the whole "Launch on Startup" pipeline:
`startup_settings_page.dart` (906 lines), `auto_launch_overlay.dart` (281 lines),
~400 lines of dispatch in `main.dart`, five modes (Debrify TV, Stremio TV,
playlist item, Continue Watching, Trakt CW). **IPTV was never one of the modes.**
It was removed for lack of use, not because it misbehaved.

What survives and is reusable:

| Thing | Where | State |
|---|---|---|
| Pref keys (`startup_auto_launch_enabled`, `startup_mode`, …) | `storage_service.dart:101-114` | present, accessors deleted (see note at `:3612`) |
| `clearAllStartupSettings()` | `storage_service.dart:2497` | live, called by Reset in `settings_screen.dart:2200` |
| `hideAutoLaunchOverlay` | `main_page_bridge.dart:39` | **never assigned** — inert |
| `notifyPlayerLaunching()` | `main_page_bridge.dart:238` | live, calls `hideAutoLaunchOverlay` |
| `notifyAutoLaunchFailed()` | `main_page_bridge.dart:291` | live, inert in practice |
| Receiving-half precedent | `stremio_tv_screen.dart:277-295` | working template: `_pendingChannelId` consumed after load, `_startupAutoPlayActive`, `_notifyStartupAutoLaunchFailed` |
| Pending-value handoff pattern | `main_page_bridge.dart:312` `notifyStremioTvChannelToAutoPlay` / `getAndClear…` | live |
| Old overlay widget | `git show 0377e9e^:lib/widgets/auto_launch_overlay.dart` | recoverable; 30s `onTimeout`, **no cancel affordance** |

**Lesson to carry:** the old feature was buried in a settings page nobody
visited. Discoverability is a design requirement here, not a nicety.

---

## 2. Architecture facts this plan depends on

Verified in the current tree:

- **Startup tab is hardcoded.** `main.dart:643` — `int _selectedIndex = 15;`
  (Home / Stremio board). IPTV is index 13, built at `main.dart:2192`.
- **The IPTV page is built directly in `main.dart`**, not from the const `_pages`
  list — `_buildPage`'s `case 13:` constructs `BrowseScreen` whose `viewBuilder`
  closure constructs `IptvResultsView`. `BrowseViewArgs`
  (`browse_screen.dart:16-28`) needs **no** change: extra params can be closed
  over in `main.dart`'s builder.
- **Launch payload is fat and state-coupled.** `iptv_results_view.dart:3321`
  pushes with the channel window, categories, sources, lists, and
  `iptvBrowseProvider: _providePlayerIptvBrowse` — a **closure into the widget's
  state** that the player calls to page/zap across the catalog. A headless
  launcher would produce a channel that plays but cannot zap. **Therefore: mount
  the IPTV page and drive it. Do not build a parallel launch path.**
- **Locating a channel is cheap, no catalog load required.**
  `iptv_catalog_db.dart:1929 positionOf({url, name, group, live})`,
  `:1956 entryForChannelNumber()`, `:1972 page({offset, limit, …})`.
- **The catalog DB is already warm at startup.** `main.dart:194`
  `_prewarmIptvCatalogDb()` runs in a post-frame callback on every launch (skipped
  when the user has no IPTV playlists).
- **Live channels are not recorded anywhere.** `iptv_results_view.dart:3249`
  deliberately skips `recordIptvWatch` for live (`"62% through Sky Sports is
  meaningless"`). **There is no "last watched channel" today** — Step 1 creates it.
- **TV preview stage races real playback.** `HeroTrailerBackdrop` at
  `iptv_results_view.dart:4267` opens a live stream after a 900ms focus dwell.
  `_previewRearmPending` (`:3568`) / `_previewEpoch` (`:375`) exist precisely to
  stop a preview opening *under* a launching player (`:3351-3365`).
- **Splash hold is Home-specific.** `app_initializer.dart:140-150` holds the
  splash on `MainPageBridge.homeBoardReady` with a 10s safety valve.
  `homeBoardReady` is set **only** by `search_screen.dart:1538` and `:1550` — the
  Home board. **If the startup tab becomes 13, SearchScreen never mounts and the
  splash sits for the full 10 seconds.** Step 5 must handle this.
- **Root back is double-press-to-exit** regardless of tab (`main.dart:2419`), so
  landing on IPTV instead of Home does not break back.
- **Hold-OK on a channel row is already overloaded** —
  `iptv_results_view.dart:237`: toggles favourite, or opens the list picker once
  the user has custom lists. Do not hang "set as startup channel" there.

---

## 3. Locked design decisions

1. **Live only.** VOD and series are ineligible everywhere — picker filters on
   `isLive`, and a stored channel that resolves to non-live is treated as missing.
   No resume position is involved; live starts at the live edge.
2. **Two modes, not five.**
   - `last` — the last live channel watched. No configuration. Expected to be the
     mode almost everyone uses.
   - `pinned` — a specific channel chosen from Favourites / custom lists.
3. **Drive the mounted page.** Startup selects tab 13 and hands down a pending
   channel; `IptvResultsView` performs the launch through its existing
   `_playChannel`. Full zap / EPG / guide context comes for free.
4. **IPTV-only feature.** Do **not** resurrect the general five-mode Startup
   settings page. Reuse the surviving keys, add IPTV-specific ones.
5. **Cold start only, once per process.** Never on resume, never twice.
6. **BACK always escapes.** The overlay is cancellable — this is the difference
   between a feature and a device the user can't get out of.

---

## 4. Storage model

Reuse:
- `startup_auto_launch_enabled` (bool) — master toggle.
- `startup_mode` (string) — new value `'iptv'`.

Add:
- `startup_iptv_mode` — `'last'` | `'pinned'`.
- `startup_iptv_channel` — JSON blob for the pinned channel.
- `iptv_last_live_channel` — JSON blob, single slot. **When** it is written
  depends on §11 decision 2 (on tune, or on successful playback) — see Step 1.

Both blobs carry the same shape: `playlistId`, `url`, `name`, `channelNumber`,
`group`, `logoUrl`, `httpHeaders`.

**Resolution order (single source of truth — Step 4 and §7 must not restate it
differently):**
1. `url + name` within the stored `playlistId`.
2. `channelNumber` within the stored `playlistId` (`entryForChannelNumber`)
   **and** a normalised-exact `name` match on the resolved row. Number alone is
   **not** sufficient: virtual catalogs assign numbers per load, so a shifted
   numbering would otherwise resolve to a different channel (Defect 32 in §9f).
   `group` may corroborate; it can never substitute for the name.
3. Give up. **No unconstrained name matching** — duplicate channel names across
   providers and categories are common, and a wrong match boots the user into the
   wrong channel silently, which is the one outcome this feature must never produce.

**On re-added Xtream accounts:** the earlier draft claimed this model survives
them. It does not, and the claim is withdrawn. Re-adding an account mints a new
`playlistId`, so step 1 fails at the *provider* lookup before any in-provider
fallback can run. Two honest options — decide in Step 2:
- **Accept it.** Re-adding an account clears the startup channel; the user
  re-picks. Simple, predictable, no silent wrong-channel risk.
- **Store a durable provider fingerprint** (e.g. normalised `serverUrl` +
  `username`) alongside `playlistId`, and allow recovery to a provider whose
  fingerprint matches, then run steps 1-2 *inside* that provider only.

Anything looser than these is a wrong-channel generator.

**Housekeeping:** add both new keys to `clearAllStartupSettings()`
(`storage_service.dart:2497`) so Reset keeps wiping cleanly. Follow the existing
accessor style at `storage_service.dart:5365-5378` (plain `SharedPreferences`
get/set, `remove` on null/empty).

---

## 5. Steps

Each step lands as **uncommitted changes for device testing** before the next
begins.

### Step 1 — Record the last live channel ✅ IMPLEMENTED (uncommitted)

**Built as: "last successfully played" + commit-on-settle (~1s).** No launch-site
write — `_playChannelInner` still skips live, untouched. What landed:
- `storage_service.dart` — `iptv_last_live_channel` key, `setIptvLastLiveChannel`
  / `getIptvLastLiveChannel` / `clearIptvLastLiveChannel`; the setter resolves the
  `serverUrl`+`username` fingerprint from the playlist id itself, so callers pass
  only a source id; added to `clearAllStartupSettings()`.
- `video_player_screen.dart` — `_noteLiveChannelPlaying()` armed from the
  `player.stream.playing` listener, 1s settle timer, re-reads the channel on fire
  (zap during the window wins), cancelled in `dispose`.
- `AndroidTvTorrentPlayerActivity.kt` — `noteLiveChannelPlaying()` from
  `onIsPlayingChanged`, posted to `iptvBrowseHandler` (so `onDestroy`'s
  `removeCallbacksAndMessages` already retires it), fire-and-forget `invokeMethod`
  with **no** `Result` — the live zap path keeps its no-round-trip guarantee.
- `android_tv_player_bridge.dart` — `noteIptvLiveChannel` handler.

Verified: `flutter analyze` full project = 0 errors; `./gradlew compileDebugKotlin`
= BUILD SUCCESSFUL. Device test pending (checklist items 1, 2, 23).

**Files:** `storage_service.dart`, `iptv_results_view.dart`,
`android/…/tv/AndroidTvTorrentPlayerActivity.kt`,
`services/android_tv_player_bridge.dart`, `screens/video_player_screen.dart`

> **Launch-site recording alone is not enough — see Defect 2 in §9.** A user who
> boots into channel A and zaps to F must next boot into **F**. Both players must
> report live channel changes, or this feature is wrong in its most common use.

> **"Last watched" currently means "last *attempted* tune" — decide which one it
> is (Defect 24 in §9d).** Every recording hook proposed here fires *before*
> playback is proven. So a dead channel overwrites the last working one, and then
> every cold start retries the dead channel: a boot-into-failure loop that the
> user can only escape through the overlay's cancel. The UI label "Last watched
> channel" implies successful playback. Options:
> - **Last tuned** — record on selection. Simple, but poisonable by one dead stream.
> - **Last successfully played** — record once playback reaches a playing state
>   (first frame / position advancing). Matches the label and cannot be poisoned.
>
> Recommendation: **last successfully played**, precisely because this feature
> re-tunes it unattended on every boot. Both players already know when playback
> starts. Recorded in §11 as a blocking decision.

- New key + accessors for `iptv_last_live_channel` (single slot, overwritten).

#### Where the write fires — conditional on §11 decision 2
**Do not implement both.** The hooks below record an *attempted tune*; under
"successfully played" they are the wrong sites entirely and would still poison the
stored channel (Defect 28 in §9e).

**If "last tuned":**
- Write it in `_playChannelInner` (`iptv_results_view.dart:3213`) in the branch
  that currently *skips* recording for live (`:3249`) — the `if (!channel.isLive)`
  gets an `else` that stores the identity blob.
- **Native TV player:** `beginIptvPlaybackAfterWatchRegistration`
  (`AndroidTvTorrentPlayerActivity.kt:7806`) currently returns early for live
  (`if (entry.isLive) { beginIptvPlayback(entry); return }`) and never calls back
  into Dart. Add a **fire-and-forget** `notifyIptvLiveChannel` invoke on that live
  branch, plus a handler beside `'recordIptvWatch'`
  (`android_tv_player_bridge.dart:652`) that stamps the slot.
  **It must not gate playback** the way the VOD path does (that path awaits the
  MethodChannel with a 2s fallback) — live zapping has to stay instant, which is
  precisely why the live branch short-circuits today.
- **Dart player:** same stamp where the live channel changes. `_currentIptvChannel`
  is a getter (`video_player_screen.dart:3829`) derived from the index, so hook
  the index-change / `_raiseIptvZapBanner` path (`:1582`), not the getter.

**If "last successfully played" (recommended):**
- **No launch-site baseline at all.** `_playChannelInner` keeps skipping live —
  the `else` branch above is not added. A channel that never plays is never stored.
- Notify from each player's **successful-playing / first-frame transition**, not
  from the tune. Locate that state in each player when building — the native
  activity's playback-ready path and the Dart player's playing-state callback —
  and confirm it fires on *zap* as well as first tune, not only once per session.
- Same fire-and-forget constraint on the native side, for the same reason.
- Consequence to accept: a channel watched briefly but never reaching a playing
  state is not remembered. That is the intended behaviour under this option.

#### Write mechanics (both options)
- Debounce the write: rapid zapping through 20 channels must not mean 20 disk
  writes. **Do not key this off the zap banner's hide timer** — it is 4500ms
  (`video_player_screen.dart:6710`) and is not armed at all while controls, the
  guide, or a sheet are visible, so killing the app shortly after a zap would
  persist the *previous* channel (Defect 8 in §9b).
- Record the **initial channel when its own success event fires** — on the same
  trigger as any later zap, independently of whether the zap banner appears. (Under
  "last tuned" this is the tune itself; under "successfully played" it is the
  playing-state transition. Phrasing it as "record the initial tune" read as
  reintroducing tune-time recording — Defect 34 in §9f.)

> **Durability and zap-path cost cannot both be guaranteed — pick one
> (Defect 21 in §9d).** Android runs no lifecycle callbacks on force-stop or
> abrupt process death, so a debounce plus an `onStop`/dispose flush is
> *best-effort by construction*. The earlier draft paired a 1s debounce with a
> test that kills the process in under a second; those contradict.
> - **(a) Guarantee it.** Commit synchronously on every *settled* channel change,
>   accepting a small write on the zap path. Then abrupt-kill durability holds,
>   bounded by the settle window.
> - **(b) Keep the debounce.** Define abrupt process death as best-effort and
>   test **graceful player exit** instead of a sub-second kill.
>
> Recommendation: **(a)** with a short settle (~1s of dwell before commit). A
> single `SharedPreferences` string write is cheap and issued off the render
> path; the guarantee is worth more than the saving. Under (a), "kill within 1s
> of a zap" legitimately has no settled channel yet — so the test asserts the
> last *settled* channel, not the last key press. Record the decision here before
> building Step 1.
- Also written by `_playCatchup`? **No** — a catchup replay is a finite VOD-style
  stream (`:3120-3200`), explicitly out of scope.
- **Origin playlist id — the source differs per option** (Defect 33 in §9f).
  `_originPlaylistIdFor` (`iptv_results_view.dart:527`) is private to
  `IptvResultsView` and is **not reachable** from a player's playing-state
  callback. Never use `_selectedPlaylist.id`: a channel played from Favourites or
  a custom list must remember its *real* provider.
  - **Launch-site / "last tuned":** `_originPlaylistIdFor(channel)`.
  - **Dart player:** `channel.attributes['source_playlist_id']`, with the same
    fallback chain the catchup path already uses
    (`video_player_screen.dart:3675-3678` — attributes → guide-context
    `sourceId` → `widget.iptvSourceId`).
  - **Native player:** `IptvChannelEntry.sourceId`. Note it can be null per entry
    and is backfilled from the launch-level `iptvSourceId`
    (`AndroidTvTorrentPlayerActivity.kt:5254`), so read it *after* that
    assignment, not from the raw payload.
- Stremio-addon channels: store the `stremio-addon://` key, not the resolved CDN
  URL (resolved URLs expire). Launch re-resolves through the existing ladder.

**Acceptance (conditional on §11 decision 3 — Defect 31 in §9e):**
- Under **(a) synchronous-on-settle**: play a live channel, let it settle, kill
  the app, confirm the blob is on disk with the right playlist id.
- Under **(b) debounce**: exit the player gracefully, then confirm the blob.
  Abrupt-kill persistence is explicitly best-effort and must not be asserted.

Either way: the right playlist id, live channels only, and nothing else changes
behaviour.

### Step 2 — Settings UI
**Files:** `screens/settings/iptv_settings_page.dart`, `settings_screen.dart`

- New section on the IPTV settings page (`build` at `:1195`; reuse
  `_FocusableSettingsTile` at `:2920` and the `SwitchListTile` idiom at `:1338`):
  - **"Start on a channel"** master switch.
  - **Mode** row: *Last watched channel* / *A specific channel*.
  - **Channel** row (enabled only in `pinned` mode) → picker dialog.
- Picker sources its rows from Favourites + custom lists via
  `StorageService.getIptvLists()` / membership snapshot, filtered to `isLive`.
  Bounded sets — no picker over a 50k-row catalog. If the user has no
  favourites/lists, the row explains that and points at hold-OK to star a channel.
- **Identity and dedup must be provider + channel, never URL alone**
  (Defect 25 in §9d). The picker aggregates across lists, and the same URL can
  exist under two different providers — which is exactly why the page already
  keys origins by `(listId, url)` (`_favoritePlaylistIds`,
  `iptv_results_view.dart:245-249`, with the comment explaining that one URL
  saved from two providers must keep **both** origins). A URL-keyed picker would
  save the wrong `playlistId` and boot the channel under another account's
  credentials. Carry the origin through selection.
- Register in settings search: an entry alongside the existing IPTV rows in
  `settings_screen.dart` (`SettingsSearchEntry` list from `:709`, IPTV lists entry
  at `:753`) so it is reachable from search, per the leaf-index pattern.
- TV DPAD: follow the house focus idioms already used on this page.

**Acceptance:** toggle + pick a channel, reopen settings, state persists. Still
nothing auto-launches.

### Step 3 — Startup dispatch
**Files:** `main.dart`

- **The prefs must be warmed in `main()` before `runApp`, not read in
  `initState` — see Defect 3 in §10.** `_selectedIndex = 15` (`main.dart:643`) is
  a synchronous field initializer; an async `SharedPreferences` read resolves
  *after* first build, so Home (15) would mount and start its cold-start IO before
  the switch. Follow the house pattern documented at `main.dart:668`:
  `bool _isAndroidTv = PlatformUtil.isAndroidTvCached`, warmed in `main()`
  alongside `_capImageCache()`'s `getTvKeyboardEnabled()` warm. Expose a
  synchronous cached flag + pending-channel blob the field initializer can read.
- Bail silently when disabled, or when the stored blob is missing or malformed.
  **That is the limit of what this step can know** (Defect 27 in §9d): it runs
  before any provider catalog is loaded, so it cannot tell whether the channel
  still exists. Actual channel resolution — and its failure path — belongs to Step 4.
- **Do not validate provider existence here** (Defect 29 in §9e). The earlier
  draft also bailed on "provider no longer installed", but a prefs-time check
  sees only `getIptvPlaylists()` — the *stored* list. Virtual providers are
  appended later, inside `_loadSettings` (`iptv_results_view.dart:700-706`, via
  `StremioIptvService.getVirtualPlaylists()`), so a **Stremio-addon startup
  channel would be rejected as "uninstalled" on every boot.** Defer
  provider-existence validation to Step 4, once `_playlists` includes virtual
  entries. (Warming the virtual list before `runApp` is the alternative, but it
  puts addon IO on the pre-first-frame path — not worth it.)
- **Deep-link / share suppression is an intent-resolution gate, not a flag.**
  `getInitialLink()` and the initial-share read resolve *asynchronously after
  `MainPage` mounts*, so a synchronous startup-tab decision wins the race and can
  auto-launch before the link is even known. A "pending" flag added later is
  useless if it is populated too late. **Resolve initial link + initial share in
  `main()` before `runApp`**, alongside the pref warm, and let the synchronous
  decision read the settled answer. If that proves too slow to await, the
  fallback is an explicit gate: the startup attempt does not begin until
  intent resolution completes, and the splash holds meanwhile. Pick one in
  Step 3 — do not defer it again.
- **The preflight must hand the intent on, not just observe it.**
  `DeepLinkService.initialize()` already reads both `getInitialLink()`
  (`deep_link_service.dart:36`) and `getInitialSharing()` (`:56`). A preflight
  that reads them independently gives two readers of a once-only source: the
  link is either handled twice or consumed and dropped. **Cache the preflight
  results and hand them to the existing service exactly once**, with
  `initialize()` consuming the cached values instead of re-reading. Sharing
  intents in particular must be treated as consume-once.
- When a target exists: `_selectedIndex` initializes to `13` instead of `15`, and
  the pending channel lives in a static, consumed-once latch mirroring
  `main_page_bridge.dart:312`'s `notifyStremioTvChannelToAutoPlay` /
  `getAndClear…` pair.
- Tab 13 is unconditionally present in `_computeVisibleNavIndices`
  (`main.dart:2052-2058`), so `_onItemTapped`'s visibility early-return
  (`:1799-1802`) can never swallow the dispatch. No guard needed.
- Pass it into the `IptvResultsView` built in `_buildPage`'s `case 13:`
  (`main.dart:2192`) — closed over in the `viewBuilder`, so `BrowseViewArgs`
  is untouched.
- **Two distinct guards — a static bool covers only one of them.** A process
  static is reset by process death, so it guards *widget/activity recreation
  while the Dart process survives* (config change, activity restart) and nothing
  more. Process-death restore is, from Dart's point of view, a cold start.
  - In-process recreation → static bool, set on first dispatch, never reset.
  - Process-death restore / return-via-recents → needs a **persisted** marker if
    it should be suppressed at all. Define the clearing semantics explicitly:
    a monotonic "last auto-launch at" timestamp with a cooldown (e.g. suppress a
    second auto-launch within N minutes of the last one) is simpler to reason
    about than a session id, and degrades safely if a write is lost.
  - **Open decision:** whether a genuine relaunch-after-kill *should* re-tune. A
    user returning via recents after the OS killed the app arguably wants their
    channel back. Decide before building; do not leave the test suite asserting
    a behaviour the guard cannot deliver.

**Acceptance:** with the setting on, the app opens on the IPTV tab. Channel
resolution and row focus are **Step 4's** acceptance, not this step's — verify
only that the tab lands and the pending channel survives to consumption.

### Step 4 — Consumption and launch in `IptvResultsView`
**Files:** `widgets/iptv/iptv_results_view.dart`

> **Do not hand `_playChannel` a self-materialized row — see Defect 5 in §10.**
> `DbChannelList.contains` and `indexOfInstance` are **identity**-based
> (`db_channel_list.dart:169-176`). A row built from `snapshot.page(...)` is a
> foreign instance, so `_playChannelInner`'s `_filteredChannels.contains(channel)`
> is false, it falls through to `_allChannels`, `indexOfInstance` returns null,
> and `?? 0` centres the window on **index 0** — the app silently boots into the
> first channel of the catalog. The window must come from the live facade, not
> from a parallel query.

- New optional `startupChannel` param, consumed once (guard flag alongside
  `_launchingChannel` at `:3099`).

#### 4a. Cancellation ownership (cross-widget)
- A monotonic `_startupAttempt` int inside `IptvResultsView`, captured at the
  start and re-checked *after every await and immediately before* `_playChannel`.
- **The overlay lives in `MainPage`; the token lives in the results view.** They
  need a wire: register a `MainPageBridge.cancelIptvStartup` callback in
  `initState`, clear it in `dispose`, and have the overlay's BACK / 30s timeout
  invoke it. Without this the plan says "BACK bumps the token" with nothing
  connecting the two (Defect 12 in §9c).
- **A transient callback alone has an early-registration race** (Defect 22 in
  §9d): the overlay can be up before `IptvResultsView.initState` registers, so an
  immediate BACK would invoke a null callback while the pending latch stays
  consumable — and the launch proceeds moments later. Cancellation must therefore
  **also set a central cancelled epoch** on the bridge. The callback is the fast
  path; the epoch is the truth.
- **The epoch must be stamped on the payload, not read bare** (Defect 30 in §9e).
  A bare integer tells a late-mounting view that *something* was cancelled, not
  whether **its** pending launch was. Dispatch stamps the pending payload with
  the current epoch; **consumption is allowed only if `payload.epoch ==
  currentEpoch`**; cancellation increments the epoch. This also stops a stale
  cancellation from killing an unrelated later attempt — which matters as soon as
  a second attempt is possible (e.g. the process-death path in §11 decision 4).
- **Distinguish the startup's own programmatic playlist switch from a user
  switch.** The rule "a playlist change invalidates the attempt" would otherwise
  make step 4c cancel itself. Set a `_startupProgrammaticSwitch` flag around the
  switch and skip invalidation while it is set.
- Clearing the pending latch in `main.dart` is **not** cancellation — by then the
  latch is consumed and the async chain owns the attempt.

#### 4b. Two catalog kinds — both must be handled
**The draft assumed a DB catalog throughout. It is wrong for roughly half the
sources** (Defect 13 in §9c). `_dbSnapshot` / `DbChannelList` / the catalog
accessors exist only for ingested provider catalogs. Favorites, Continue watching,
custom lists, local-file playlists and **Stremio-addon shelves** are plain
materialized `List<IptvChannel>` (`_loadPlaylistInner`, `:982-1000`), and the
Stremio path is **progressive** — the list grows batch by batch as the walk
proceeds, so the target may not exist yet when the first batch renders.

#### 4c. Sequence (order matters — Defect 14 in §9c)
Resolution must happen **against the target provider's own catalog**, so the
provider switch comes first. The draft resolved before switching, when
`_dbSnapshot` still belonged to the landing playlist.

1. **Locate the stored playlist** in `_playlists` (by `playlistId`, or the
   fingerprint decided in §4). Fail cleanly if absent.
2. **Switch to it** if it is not the landing selection, via the programmatic path
   (`:2510-2525`), with `_startupProgrammaticSwitch` set. This resets
   `_selectedCategory`, which is why category adoption happens later.
3. **Await that load's ticket** (`_loadTicket` / `_inFlightLoadTicket`).
   Re-check the token.
4. **Branch on catalog kind:**
   - **DB-backed** (`_dbSnapshot != null`): resolve a catalog entry —
     `entryForUrl({url, name})` (a small new accessor beside
     `entryForChannelNumber`, `iptv_catalog_db.dart:1956`, returning
     `({position, channel})`) → `entryForChannelNumber` fallback → give up.
   - **Materialized** (plain list): scan `_allChannels` for url+name →
     channelNumber fallback. **For Stremio (progressive)**, the target may not
     have arrived yet: observe successive batches until it appears, the walk
     completes, or the token/timeout ends the attempt. Do not assume the first
     batch is the whole list.
5. **Validate the resolved entry is live.** If not, abort (§3: live only).
6. **Adopt the entry's own group** as `_selectedCategory` and await the filter
   rebuild. Re-check the token.
7. **Obtain the resident instance:**
   - **DB-backed:** convert catalog position → filtered index, then
     `_filteredChannels[index]` (see 4d for the exact filter contract).
     `DbChannelList.operator[]` (`db_channel_list.dart:102-144`) faults the page
     and registers the instance in `_indexOfInstance` — which is what
     `_playChannelInner` requires.
   - **Materialized:** the object in `_allChannels` *is* the instance the
     filtered list holds, so `indexOf` works and `contains` succeeds naturally.
8. **Verify before launching — against the resolved entry, not the stored blob**
   (Defect 16 in §9c). Verifying the resident row's url/name against the *stale*
   blob would reject every successful channel-number fallback, which exists
   precisely because the URL changed. Verify identity against what resolution
   returned (position for DB, object identity for materialized). **A
   channel-number fallback additionally requires the stored name to match the
   resolved name** (normalised exact — case/whitespace folded, not fuzzy);
   `group` may corroborate further but is **never sufficient on its own**
   (Defect 32 in §9f). Hundreds of channels share "Sports" or "News", so a
   group-only check would happily accept the wrong channel whenever virtual
   numbering shifts — which is precisely the condition that triggers the fallback.
9. **Scroll and focus the row** (see 4e). Re-check the token.
10. `_playChannel(row)` — the normal path, so window, guide, zap, sources, lists
    and browse provider are all correct. **No parallel `page()` window is built
    at any point.**
11. **Cancellation must reach inside the launch path — see Defect 20 in §9d.
    This is the release-critical one.** Checking the token *before*
    `_playChannel` is not enough: `_playChannelInner` then awaits Stremio
    `resolveCandidates` (`:3225`) and `recordIptvWatch` (`:3256`) before
    `VideoPlayerLauncher.push` (`:3321`). BACK during either await still ends in
    a player. Pass an optional `shouldCancel` predicate / attempt token into
    `_playChannelInner` and check it **after its final await, immediately before
    `push`**. Optional, so the single launch path is preserved and normal taps
    are unaffected.

#### 4d. The filtered-index contract (DB path)
**`DbChannelList` filters on `group` + `search` only — there is no `live`
parameter** (`db_channel_list.dart:26-34`; its `_length` is
`snapshot.count(group:, search:)`). The earlier revision said to convert with
`count(group:, live:, beforePosition:)`. On a mixed live+VOD M3U category that
counts a *different set* than the facade indexes, and returns the wrong row
(Defect 15 in §9c).

- **The count must mirror the facade exactly:**
  `count(group: <facade.group>, search: <facade.search>, beforePosition: position)`
  — **no `live`**.
- Live-ness is enforced by *validating the resolved entry* (step 5), not by
  filtering.
- Alternative, if a live filter is genuinely wanted in the UI: add `live` to
  `DbChannelList` and thread it everywhere. Larger change; only if something else
  needs it.

#### 4e. Scroll/focus to a lazy row (new procedure — Defect 17 in §9c)
There is **no existing scroll-to-index path to reuse.** The grid's only
auto-scroll is per-row: `Scrollable.ensureVisible` fired post-frame from a
**built** row's focus callback (`iptv_channel_row.dart:352-366`). A distant lazy
row is neither built nor has a focus node, so nothing to focus and nothing to
ensure-visible.
- **The metrics are not reachable from the startup routine** (Defect 23 in §9d).
  Column count and `rowExtent` are locals inside `LayoutBuilder`
  (`iptv_results_view.dart:4498-4529`). The build must **publish current grid
  metrics to state** for the routine to read; otherwise the offset cannot be
  computed at all.
- Wait for `_scrollController.hasClients` **and** valid scroll dimensions before
  jumping — at startup the grid may not have laid out yet.
- Then request focus post-frame once the row has mounted (retrying a frame or
  two — the row must build first). The existing per-row `ensureVisible`
  fine-tunes alignment when focus lands.
- **The touch-tablet path needs a different handoff entirely.** It renders
  `IptvCenteredSelector` (`:4646`), which owns its **own** `ScrollController`
  (`iptv_centered_selector.dart:49`) — the page's `_scrollController` (`:92`)
  does not drive it. Use that widget's existing `initialIndex` / `selectionToken`
  inputs to hand it the target index instead of scrolling imperatively.
- **Suppress the preview stage for the whole startup window.** A new
  suppression flag read where the stage decides to mount (`:4257-4267`), cleared
  when the launch resolves, fails, **or is cancelled**. `_previewRearmPending`
  alone is not enough — it parks a *re-arm*, it does not stop the initial 900ms
  dwell from opening a stream under the launching player.
- **Failure paths** (channel gone, provider deleted, Stremio ladder empty,
  catalog empty, row verification failed): call
  `MainPageBridge.notifyAutoLaunchFailed(reason)`, leave the user on the IPTV
  page with a snackbar. Never retry, never fall back to a different channel —
  booting into the wrong channel is worse than not booting into one.

**Acceptance:** cold start tunes into the *correct* channel (including when it
sits inside a category); BACK from the player lands on the IPTV page with that
row focused and navigation intact; BACK *during* the launch aborts it and no
player ever appears; no preview stream audible under the player.

### Step 5 — Overlay and splash hand-off
**Files:** `widgets/auto_launch_overlay.dart` (restored), `main.dart`,
`widgets/app_initializer.dart`, `services/main_page_bridge.dart`

- Restore the overlay from `0377e9e^` and **add a cancel affordance** the
  original lacked: "Press BACK to cancel", wired ahead of the root `PopScope`
  (`main.dart:2419`).
- **Cancel must bump Step 4's cancellation token, not just clear the latch.**
  The latch is consumed early; the async resolve/load chain owns the attempt from
  then on. BACK and the 30s timeout both invalidate the token, hide the overlay,
  and clear preview suppression. Without this, loading finishes after the user
  backed out and the player opens anyway (Defect 4 in §10).
- Re-assign `MainPageBridge.hideAutoLaunchOverlay` in `MainPage` init/dispose so
  the existing `notifyPlayerLaunching` (`:238`) tears the overlay down when the
  player actually starts — this is already called by every playback path, so it
  works with no changes to `VideoPlayerLauncher`.
- Keep the overlay's 30s timeout as the terminal safety valve → treat as failure.
- **Splash:** `app_initializer.dart:140-150` waits on `homeBoardReady`, which the
  Home board alone sets (`search_screen.dart:1538`, `:1550`). Once Step 3 lands
  the **synchronous** dispatch, SearchScreen never mounts, the signal never fires,
  and the splash burns the full 10s valve. Fix by having the startup-IPTV path
  publish the same latch once the overlay is up — one signal, no new branch in
  `AppInitializer`.
  *(Note: this stall is a consequence of doing Step 3 correctly. Under the
  rejected async-dispatch approach Home would mount and fire the signal anyway —
  which is why the two steps must not be evaluated independently.)*

**Acceptance:** splash → overlay → player, no flash of the IPTV page, no 10s
stall. BACK during the overlay cancels cleanly.

---

## 6. Invariants

- **Never auto-launch twice in a process.** Latch in `main.dart`, never reset.
- **Never auto-launch on resume.** Cold start only.
- **BACK always escapes**, at every stage of the sequence.
- **Never substitute a different channel** on failure. Fail visibly.
- **Never build a second launch path.** Everything goes through
  `_playChannel` / `VideoPlayerLauncher.push` so zap, EPG, sources and lists
  stay correct.
- **Never let the preview stage arm during a startup launch.**
- **Live only.** Any stored channel resolving to non-live is treated as missing.

---

## 7. Risks

| Risk | Mitigation |
|---|---|
| Boot loop with no escape — user can't reach Settings | In-process latch + BACK cancels via `cancelIptvStartup` + 30s timeout; process-death case per the Step 3 decision |
| Player opens *after* the user cancelled | Attempt-scoped token re-checked after every await and before `_playChannel` (§4a) — not the pending latch |
| Cold catalog: first-ever load is a full M3U download + parse (known first-open ANR territory) | Overlay stays up with the channel name and a cancel hint; failure after 30s is visible, not a frozen splash |
| Progressive Stremio catalog: target not in the first batch | Observe batches until it appears, the walk ends, or the token/timeout fires (§4b) |
| Splash stalls 10s because `homeBoardReady` never fires | Step 5 — publish the latch from the startup-IPTV path |
| Preview stream opens under the launching player | Explicit suppression flag, not just `_previewRearmPending` |
| Wrong row launched from a mismatched filter set | Count mirrors the facade's `group`+`search` exactly, no `live` (§4d) |
| Stored URL stale after re-adding an Xtream account | **Not recoverable under the current model** — a new account mints a new `playlistId`. Per §4: either the startup channel clears cleanly, or a `serverUrl`+`username` fingerprint is stored. Decide in Step 2 |
| Channel lives in a non-default playlist → extra load latency | Store `playlistId`; switch **before** resolving (§4c); overlay covers the wait |
| Deep-link / magnet launch hijacked by auto-launch | Intent resolution gate before the startup decision, with the intent handed to `DeepLinkService` exactly once (Step 3) |
| Phone users surprised by a player on open | Default off |

---

## 8. Out of scope

- VOD / series / Continue Watching startup modes.
- Restoring the general five-mode Startup settings page.
- Catchup / timeshift replay on startup.
- Resume position (live has none).
- Any change to `VideoPlayerLauncher` itself, or to how either player *plays*.

**Correction:** an earlier draft listed "any change to either player" as out of
scope while Step 1 modifies both. Step 1 **does** touch both players — a
fire-and-forget live-channel notify in the native activity and the equivalent in
the Dart player. That is in scope and unavoidable: without it "last watched
channel" is wrong (Defect 2 in §10). What stays out of scope is playback
behaviour, the launch API, and anything on the VOD path.

---

## 9. Review record (2026-08-01)

Plan reviewed against the tree after first draft. Four defects found and folded
back into the steps above; kept here so the reasoning isn't lost.

### Defect 1 — position vs offset are different index spaces *(Step 4, correctness)*
The draft said "`positionOf(...)` → materialize with `page(offset, limit)`".
`positionOf` (`iptv_catalog_db.dart:1929`) and `entryForChannelNumber` (`:1956`)
return the `position` **column**; `pageEntries` (`:2004`) issues
`ORDER BY position LIMIT ? OFFSET ?` — an index into the **filtered** set. These
coincide only when no filter applies and positions are dense. With a category
selected, or a live-only filter, the startup channel would land at the wrong
window offset — a silently wrong channel, not a crash. The existing zap path
already does it right (`iptv_results_view.dart:2946-2956`, via
`count(beforePosition:)`); the plan now mandates that conversion.

### Defect 2 — "last watched channel" would ignore zapping *(Step 1, product)*
**The serious one.** The draft recorded the channel at *launch* only. But the
native TV player's `beginIptvPlaybackAfterWatchRegistration`
(`AndroidTvTorrentPlayerActivity.kt:7806`) short-circuits live
(`if (entry.isLive) { beginIptvPlayback(entry); return }`) and never invokes the
`recordIptvWatch` bridge for live channels — deliberately, so live zapping stays
instant. Net effect: boot into A, zap to F, close the app → next boot returns to
**A**. That is wrong in the single most common usage of the feature, and it would
have survived every test in the draft's checklist. Step 1 now covers both players,
with the explicit constraint that the native notify stays fire-and-forget.

### Defect 3 — async prefs cannot drive a synchronous field initializer *(Step 3)*
`_selectedIndex = 15` (`main.dart:643`) is a field initializer evaluated at
construction. A `SharedPreferences` read in `initState` resolves after first
build, so Home would mount, begin its cold-start IO, and only then get swapped
for IPTV — a flash plus wasted work, and it competes with the
`_prewarmIptvCatalogDb` scheduling this feature depends on. The codebase already
solved this shape once and documented it at `main.dart:668` (`_isAndroidTv =
PlatformUtil.isAndroidTvCached`, warmed before `runApp`). Step 3 now follows it.

### Defect 4 — a Step 5 claim was true only conditionally
The draft asserted flatly that `homeBoardReady` never fires with tab 13 as the
startup tab. That holds only under the *synchronous* dispatch of Defect 3's fix;
under the async version Home mounts and the signal fires normally. Stated
unconditionally it would have sent someone chasing a stall that, at that moment,
didn't exist. Now scoped explicitly.

### Verified sound (no change needed)
- `notifyPlayerLaunching` **is** called by `VideoPlayerLauncher`
  (`:884`, `:995`, `:1714`, `:2229`), so re-assigning `hideAutoLaunchOverlay` is
  genuinely sufficient to tear the overlay down. Step 5's claim holds.
- Tab 13 is unconditional in `_computeVisibleNavIndices` (`main.dart:2052-2058`),
  so `_onItemTapped`'s visibility early-return cannot swallow the dispatch.
- `_originPlaylistIdFor` exists (`iptv_results_view.dart:527`) and is the right
  source for the origin id, as the draft assumed.
- The preview-suppression analysis holds: `_previewRearmPending` parks a re-arm
  and does not prevent the initial 900ms dwell.

### Known-weak, deliberately left open (round 1)
- **Cold-catalog worst case** is mitigated by UI (overlay + cancel + 30s timeout)
  rather than made fast. Acceptable, but it means a first-run user with a large
  M3U and no disk cache gets a slow boot the first time and a fast one after.

---

## 9b. Second review round (2026-08-01, external)

Eight further findings, all accepted. Two invalidated the draft's core handoff.

### Defect 4 — cancellation was never actually wired *(High, Steps 3-5)*
The draft consumed the pending channel *before* the async playlist/catalog work,
then defined BACK/timeout as "clears the pending latch". Once consumed the latch
is inert, so the chain would complete and open the player **after** the user
backed out. Fixed with an attempt-scoped cancellation token re-checked after
every await and immediately before `_playChannel`; BACK, timeout, user playlist
switch and dispose all invalidate it and clear preview suppression.

### Defect 5 — self-materialized rows would boot the wrong channel *(High, Step 4)*
Worse than the reviewer stated. The draft said "materialize a window with
`page()`, then call `_playChannel(channel)`". `_playChannelInner` builds its own
window and looks the row up by **identity**: `DbChannelList.contains` and
`indexOfInstance` are backed by `HashMap.identity` (`db_channel_list.dart:77,
169-176`). A foreign instance fails `contains` → falls through to `_allChannels`
→ `indexOfInstance` returns null → `?? 0`. The app would silently launch **the
first channel in the catalog**. Fixed by deleting the parallel `page()` entirely
and reading the row from the live facade (`_filteredChannels[index]`), whose
`operator[]` faults and registers the resident instance. Plus an explicit
url/name verification before launch.

### Defect 6 — the filter set was never defined *(High, Step 4)*
Position→offset conversion was corrected in round 1, but nothing said *which*
group filter applied. If the landing category excludes the target, no amount of
correct counting inside it can materialize the row. Now: resolve the row and its
group together (needs a small `entryForUrl` accessor, since `positionOf` returns
only a position), adopt that group as the active category, and use that one
filter set for count, facade, `_selectedCategory` and player context alike.

### Defect 7 — deep-link suppression was an unresolved blocker, not a detail
`getInitialLink()` and the initial share resolve asynchronously after `MainPage`
mounts, so a synchronous startup decision wins the race regardless of any flag
added later. Now a decision forced in Step 3: resolve intents before `runApp`, or
gate the startup attempt behind intent resolution. No third option.

### Defect 8 — banner hide timer is the wrong debounce *(Medium, Step 1)*
4500ms (`video_player_screen.dart:6710`), and not armed while controls/guide/
sheets are up. Killing the app shortly after a zap would persist the previous
channel — failing this feature's primary acceptance test. Now a ~1s independent
debounce plus a flush on stop/dispose.

### Defect 9 — process statics don't survive process death *(Medium, Step 3)*
The draft claimed one static guarded "process-death restore". Statics reset with
the process. Split into in-process recreation (static) and process-death restore
(persisted cooldown marker, if suppressed at all) — with the product question of
whether a relaunch-after-kill *should* re-tune raised rather than assumed.

### Defect 10 — stale-account recovery was self-contradictory *(Medium, §4/Step 4)*
§4 said url → number → name; Step 4 said url → number → give up. Worse, the
re-added-account scenario fails at the *provider* lookup before any fallback
runs, so the claim was empty. Resolution order is now stated once in §4, the
re-added-account claim is withdrawn, and unconstrained name matching is banned
outright.

### Defect 11 — scope and acceptance contradictions *(Low)*
"No changes to either player" vs Step 1 modifying both — scope corrected, since
Step 1's player changes are load-bearing. Step 3's acceptance claimed a focused
channel before Step 4 implements resolution — moved to Step 4. Duplicate list
numbering in Step 4 fixed.

---

---

## 9c. Third review round (2026-08-01, external)

Eight findings, all accepted. One invalidated Step 4 for roughly half of all
sources. **After this round the plan is still not implementation-ready — see
§11.**

### Defect 12 — cancellation had no cross-widget wire *(High, §4a)*
The overlay lives in `MainPage`; `_startupAttempt` is private to
`IptvResultsView`. "BACK bumps the token" connected nothing. Now a registered
`MainPageBridge.cancelIptvStartup` callback, installed/disposed by the results
view. Also: the "playlist change invalidates the attempt" rule would have made
the startup's *own* programmatic switch cancel itself — now flagged around.

### Defect 13 — Step 4 only worked for DB-backed catalogs *(High, §4b)*
The biggest miss so far. `_dbSnapshot`, the catalog accessors and `DbChannelList`
exist only for ingested provider catalogs. Favorites, Continue watching, custom
lists, local-file playlists and **Stremio-addon shelves** are plain materialized
lists (`:982-1000`), and Stremio is **progressive** — the list grows batch by
batch, so the target may be absent when the first batch renders. Test 17
(Stremio startup channel) could not have passed. Step 4 now branches explicitly,
with batch observation for the progressive case.

### Defect 14 — resolution was ordered before loading the target provider *(High, §4c)*
The draft resolved the row, then switched playlists. At resolution time
`_dbSnapshot` still belonged to the *landing* playlist, so the lookup ran against
the wrong catalog. Order corrected: locate playlist → switch → await ticket →
resolve → validate live → adopt category → obtain resident row.

### Defect 15 — the filtered-index conversion still didn't match the facade *(High, §4d)*
Round 1 fixed position-vs-offset; this round found the *filter set* still wrong.
`DbChannelList` takes `group` + `search` only — **no `live`**
(`db_channel_list.dart:26-34`). Counting live-only rows and indexing a facade
holding live+VOD returns the wrong channel on any mixed M3U category. The count
now mirrors the facade exactly, and live-ness is validated on the resolved entry
instead of filtered.

### Defect 16 — row verification contradicted the number fallback *(High, §4c step 8)*
Verifying the resident row against the *stored* url/name would reject every
successful `channelNumber` fallback — which exists precisely because the URL
changed. Verification now targets the resolved catalog entry, with corroborating
name/group required for number-based matches (numbers are reassigned per load on
virtual catalogs).

### Defect 17 — no scroll-to-index path exists to reuse *(Medium, §4e)*
The draft said "reuse the page's existing focus/scroll-to-index path". There
isn't one: the only auto-scroll is `Scrollable.ensureVisible` fired post-frame
from a **built** row's focus callback (`iptv_channel_row.dart:352-366`). A
distant lazy row is not built and has no focus node. Now specified as a new
indexed-scroll procedure (column count + row extent → jump → post-frame focus).

### Defect 18 — intent preflight would double-read a once-only source *(Medium, Step 3)*
`DeepLinkService.initialize()` already reads `getInitialLink()` (`:36`) and
`getInitialSharing()` (`:56`). A preflight reading them independently means the
link is handled twice or consumed and dropped. The preflight must cache and hand
off exactly once.

### Defect 19 — stale statements survived the rewrite *(Low)*
The risk table still said "suppress when a pending deep link exists" and
described stale-account recovery as a three-tier resolve, both contradicting the
revised §4 and Step 3. Table rewritten.

---

---

## 9d. Fourth review round (2026-08-01, external)

Eight findings, all accepted. One is release-critical.

### Defect 20 — cancellation stopped at the door of the launch path *(release-critical)*
§4c checked the token immediately before `_playChannel`, but `_playChannelInner`
then awaits Stremio `resolveCandidates` (`:3225`) and `recordIptvWatch` (`:3256`)
before `VideoPlayerLauncher.push` (`:3321`). BACK during either await still ends
in a player — so the plan's headline promise ("BACK always escapes") did not hold.
Fixed by threading an optional `shouldCancel`/attempt token into
`_playChannelInner`, checked after its final await. **Without this the feature
must not ship.**

### Defect 21 — durability and debounce were mutually exclusive *(High)*
A 1s debounce with an `onStop`/dispose flush is best-effort by construction —
Android runs no callbacks on force-stop or abrupt death — yet test 2 killed the
process in under a second. Now an explicit choice with a recommendation, and the
test reworded to assert the last *settled* channel.

### Defect 22 — cancellation bridge had an early-registration race *(Medium)*
The overlay can exist before `IptvResultsView.initState` registers the callback,
so an immediate BACK would hit a null callback while the latch stayed consumable.
Added a central cancelled epoch that a later-mounting view reads before consuming.

### Defect 23 — the scroll procedure had no layout handoff *(Medium)*
Column count and `rowExtent` are locals inside `LayoutBuilder` (`:4498-4529`),
unreachable from the startup routine — the offset simply could not be computed.
Build must publish grid metrics to state, and the routine must wait for
`hasClients` + valid dimensions. Separately, the touch-tablet path uses
`IptvCenteredSelector`'s own controller (`iptv_centered_selector.dart:49`), so it
needs an index handoff via `initialIndex`/`selectionToken`, not a scroll.

### Defect 24 — "last watched" meant "last attempted tune" *(Medium, product)*
Recording fires before playback is proven, so one dead stream overwrites the last
working channel and every subsequent boot retries it — a boot-into-failure loop,
made worse by the fact that this feature runs unattended. Now a blocking decision
with "last successfully played" recommended.

### Defect 25 — picker identity by URL would save the wrong provider *(Medium)*
The picker aggregates Favourites and custom lists, where one URL can exist under
two providers. The page already keys origins by `(listId, url)`
(`iptv_results_view.dart:245-249`) for exactly this reason. URL-only selection
would store the wrong `playlistId` and boot under another account's credentials.

### Defect 26 — the open-decisions conclusion contradicted itself *(Low)*
It claimed Steps 1 and 2 were unblocked while decision 1 changes the storage blob
and picker. Corrected: decisions 1-3 all land inside Steps 1-2, so nothing starts
until they are answered.

### Defect 27 — Step 3 claimed knowledge it cannot have *(Low)*
"Bail when no channel resolves" runs before any provider catalog is loaded. Step 3
can only reject a missing/malformed blob or an absent provider; resolution and its
failure path belong to Step 4.

---

## 9e. Fifth review round (2026-08-01, external)

Four findings, all accepted. All were internal contradictions the plan had
introduced while fixing earlier rounds — worth noting as a pattern: each round of
fixes has itself needed review.

### Defect 28 — Step 1 mandated the very hooks its recommendation rejects *(High)*
§11 decision 2 recommends "last successfully played", but Step 1's bullets still
required a pre-play write in `_playChannelInner`, a native notify before
`beginIptvPlayback`, and a Dart notify on index change. All three record an
*attempted* tune, so implementing them would poison the stored channel on a dead
stream — exactly the failure the recommendation exists to prevent. Step 1 is now
split into two mutually exclusive hook sets, with an explicit "do not implement
both".

### Defect 29 — provider-existence check would reject every Stremio channel *(Medium)*
Step 3 bailed when the stored provider was "no longer installed", but at
prefs-warm time only `getIptvPlaylists()` (stored playlists) is visible. Stremio
IPTV playlists are **virtual**, appended later inside `_loadSettings`
(`iptv_results_view.dart:700-706` via `getVirtualPlaylists()`). A Stremio-addon
startup channel would therefore be rejected on every boot. Validation deferred to
Step 4.

### Defect 30 — the cancelled epoch had no attempt identity *(Medium)*
"A late-mounting view reads the epoch" — but a bare integer cannot say whether
*this* pending launch was the cancelled one. Now the epoch is stamped on the
pending payload at dispatch, consumption requires `payload.epoch ==
currentEpoch`, and cancellation increments. Also prevents a stale cancellation
from killing an unrelated later attempt.

### Defect 31 — Step 1 acceptance asserted an undecided guarantee *(Low)*
It still required killing the app and finding the blob persisted, which is not
guaranteed under the best-effort debounce option. Made conditional in the same
way as test 2.

---

## 9f. Sixth review round (2026-08-01, external)

Three findings, all accepted.

### Defect 32 — number-fallback corroboration was too loose *(High)*
Round 4 required "corroborating name **or** group" for a channel-number match.
Group is far too broad — hundreds of channels share "Sports" or "News" — so on a
virtual catalog whose numbering shifted (the exact condition that triggers the
fallback) a wrong channel in the same group would verify clean. Now: normalised
exact **name** match required, group only as extra corroboration. Also propagated
to §4's canonical resolution order, which still implied number lookup alone
sufficed — the two had drifted apart.

### Defect 33 — origin resolution is unreachable under the recommended option *(Medium)*
Step 1 said to store the origin via `_originPlaylistIdFor(channel)`, but that is
private to `IptvResultsView` and unavailable from a player's playing-state
callback — i.e. from exactly where the recommended "successfully played" option
records. Per-option sources now specified: `_originPlaylistIdFor` at the launch
site, `channel.attributes['source_playlist_id']` (with the catchup path's
existing fallback chain) in the Dart player, and `IptvChannelEntry.sourceId` in
the native one — read after the launch-level backfill at
`AndroidTvTorrentPlayerActivity.kt:5254`, since it can be null per entry.

### Defect 34 — "record the initial tune" contradicted the semantics *(Low)*
Under "successfully played" that phrasing reads as reintroducing tune-time
recording. Reworded to "record the initial channel when its success event fires",
which is correct under both options.

---

## 10. Device test checklist (Android TV)

Ordered by what they guard. Items marked **(D*n*)** exist because a specific
defect would otherwise ship silently.

1. **(D2)** Boot into A, zap to F, exit, cold start → tunes into **F**. Run on the
   native TV player *and* the Dart player — different code paths.
2. **(D8/D21)** Zap to F, let it **settle**, then kill the app → next boot is F.
   Wording depends on decision 3 in §11: under synchronous-on-settle, assert the
   last *settled* channel and kill right after the settle window; under debounce,
   test a **graceful player exit** instead — an abrupt force-stop is explicitly
   best-effort and must not be asserted.
3. **(D5)** Startup channel that is **not** near the top of the catalog → tunes
   into it, not channel #1. The identity bug's signature is "always plays the
   first channel", so a target at index 0 would mask it — pick one deep in the list.
4. **(D6)** Startup channel inside a category, with a *different* category active
   at launch → tunes into the right channel and the page shows its category.
5. **(D4)** BACK during the overlay while a large catalog is still loading → the
   attempt aborts and **no player appears afterwards**. Watch for ~30s; the
   failure mode is a player that opens late, after the user has moved on.
6. **(D4)** Same, but let the 30s timeout fire instead of pressing BACK.
7. Cold start, mode `last` → tunes in. Mode `pinned` → tunes into the pinned channel.
8. BACK from the player → IPTV page, **that row focused**, DPAD normal.
9. Backgrounding and resuming → does **not** re-launch.
10. **(D9)** Activity recreation with the process alive (rotate / TV config change)
    → does not re-launch.
11. **(D9)** Force-stop, then relaunch → behaves per the decision recorded in
    Step 3. Do not assert a behaviour the guard cannot deliver.
12. Pinned channel's provider deleted → snackbar, no launch, no crash.
13. **(D10)** Re-add an Xtream account → behaves per the §4 decision (either the
    startup channel clears cleanly, or fingerprint recovery finds it). Never a
    different channel.
14. Cold catalog (clear IPTV DB) → overlay holds, then tunes in or fails visibly.
15. **(D7)** Open via deep link / magnet with the setting on → no auto-launch, and
    the link is handled normally. Test a cold process, not a warm one.
16. Setting off → startup identical to today (Home board, splash timing unchanged).
17. **(D13)** Startup channel on a **Stremio-addon** shelf, where the target is
    *not* in the first batch → the attempt waits for later batches, then tunes in
    (or fails visibly). This is the case the DB-only design could not do at all.
18. **(D13)** Startup channel from **Favourites / a custom list / a local-file
    playlist** → tunes in. These are materialized lists, not DB catalogs.
19. **(D15)** Startup channel in a **mixed live+VOD category** on an M3U → tunes
    into the right row. The live-filter mismatch's signature is an off-by-N row
    within the right category.
20. **(D16)** Change a channel's URL in the provider but keep its number →
    number fallback resolves it, and verification does **not** reject it.
21. **(D12)** BACK during the launch, then immediately switch playlists by hand →
    no stray player, no cancelled-then-resurrected attempt.
22. **(D20)** BACK during the launch **while a Stremio channel is resolving
    candidates** → no player ever appears. This is the exact window the
    pre-`_playChannel` token check missed; watch for 30s.
23. **(D24)** Make the last-watched channel a **dead** stream, then cold start →
    behaves per decision 2 in §11, and in no case does the app enter a
    boot-retry-fail loop the user cannot escape.
24. **(D25)** Same URL saved to two lists from two different providers → the
    picker stores the provider the user actually chose, and boot uses its credentials.
25. **(D23)** Startup channel far down the list on a **touch tablet**
    (`IptvCenteredSelector` path) → the row is selected and centred on return.
26. **(D29)** Startup channel belonging to a **Stremio-addon** provider → boots
    normally. The rejected draft would have failed this on every launch, since
    virtual providers do not exist at prefs-warm time.
27. **(D32)** On a virtual/renumbered catalog, shift channel numbers so the
    stored number now points at a *different* channel in the same group → the
    fallback **rejects** it rather than tuning the neighbour.
28. Phone build with the setting on → same behaviour, no layout breakage.

---

## 10b. Amendment — first-run bootstrap (2026-08-01)

**Behaviour change, decided after implementation.** With mode `last` and nothing
ever recorded (the first boot after switching the feature on), the app used to do
nothing at all: `warmStartupIptv` found no channel, no payload was set, and it
booted to Home silently. Correct per the "never substitute a different channel"
invariant, but it reads as broken at the exact moment a user first tests the
feature — the same first-impression failure that killed the original
Launch-on-Startup.

The invariant still holds where it was aimed: a *stored* channel that fails to
resolve must never be swapped for another, because the user has a specific
expectation. With nothing stored there is no expectation to violate, so a
bootstrap pick is legitimate.

- `warmStartupIptv` sets a `firstAvailable` sentinel payload (never persisted)
  when mode is `last` and nothing is remembered.
- `_resolveFirstAvailableRow` takes the first **live** row of whatever the page
  landed on — which is Favourites when the user has any, else their default
  provider — walking at most 300 rows so a VOD-heavy catalog can't stall it.
- Rows come off `_filteredChannels`, so they are resident instances already; no
  category is adopted, since the landing view is the intended one.
- It self-corrects: playing that channel for the settle window records it, so
  every later boot uses a genuine last-watched value.
- **Mode `pinned` deliberately does NOT fall back.** "A specific channel" with
  none chosen is an explicit blank the settings row already labels; auto-picking
  something else would contradict what the user asked for.
- Settings now states the truth instead of the intent: the `last` row reads
  "Nothing watched yet — starts on the first channel, then remembers what you
  watch" when empty, and names the remembered channel when set.

---

## 11. Open decisions — blocking implementation

The plan is **not** implementation-ready until these are answered. Each changes
code, not just wording.

| # | Decision | Blocks | Recommendation |
|---|---|---|---|
| 1 | ~~**Re-added Xtream account**~~ | — | **TAKEN: fingerprint recovery.** Blob stores `serverUrl`+`username`; `_startupPlaylistFor` falls back to a fingerprint match when the playlist id is gone. |
| 2 | ~~**"Last watched" semantics**~~ | — | **ANSWERED: last successfully played.** Implemented — hooks sit at each player's playing-state transition, no launch-site write. |
| 3 | ~~**Durability vs zap-path cost**~~ | — | **ANSWERED: commit on settle (~1s).** Implemented in both players. Test 2 asserts the last *settled* channel. |
| 4 | ~~**Process-death relaunch**~~ | — | **TAKEN: re-tune.** A cold start is a cold start; the user gets their channel back, and BACK cancels. No persisted marker — revisit if it feels wrong on device. |
| 5 | ~~**Intent preflight shape**~~ | — | **TAKEN: preflight + handoff.** `DeepLinkService.preflightLaunchIntent()` runs before `runApp`; `initialize()` consumes the cached values so the once-only share is neither dropped nor doubled. |
| 6 | ~~**Live filtering in `DbChannelList`**~~ | — | **TAKEN: validate on the resolved entry.** The facade keeps `group`+`search` only, and the index count mirrors it exactly. |

All six are taken and built. Decision 4 (re-tune after process death) is the one
most worth revisiting after device testing — it is a product judgement, not a
technical constraint, and it is a one-line change if it feels wrong.
