# Stremio TV screen refactor — plan

Written 2026-10-06 on `refactor/codebase` at `0cb50df7` (the Debrify TV merge).
Follow [AGENTS.md](../../AGENTS.md).

Read first: [debrify-tv-plan.md](debrify-tv-plan.md) (closest analogue: one
giant playback-adjacent State, provider resolvers, player handoff ledger,
occurrence-level field-binding guard, per-declaration source reader, the
reversed double golden capture, and its Progress section), then the
Technique/Progress sections of [spotlight-board-plan.md](spotlight-board-plan.md)
(format-only reference commit, live widget getters, typedef-exported private
widgets) and [addon-hub-plan.md](addon-hub-plan.md) (`build` forwarder into a
layout section). This plan reuses their technique, checker
(`check_verbatim_moves.py` → `check_settings_moves.py`, engine `sections`),
callback-identity tooling, `suite_evidence.py` evidence, real-config fixtures,
original-code worktree proofs with assertion-failing mutation negatives, the
per-entry wiring checklist and the Linux-golden handoff. It states only what
differs. A facts inventory produced with this plan (every declaration, field,
resource, hook, handoff argument, cancellation occurrence and source-text
reader, with line numbers) is copied into the dependency report at step 0.

**Execution.** The work runs in its own git worktree
`../debrify-wt/stremio-tv` on branch `refactor/stremio-tv`, cut from
`refactor/codebase` at `0cb50df7`, in parallel with four other refactors
(two of them touch sibling files in the same directory, see "Sibling
coordination"). Progress records the execution base SHA at step 0, and every
proof names it. Run `flutter pub get` first; the lockfile must not change
(Flutter 3.44.8 / Dart 3.12.2). Commit after every step; never push, merge or
switch branches; gate commits contain `gate`. Remote CI stays pending, so
every step runs the local CI-equivalent commands. Evidence goes only under
`<git-common-dir>/refactor-evidence/stremio_tv/`; never write to or relabel
another namespace. **Every manifest run passes an isolated
`--parser-package`** under the ignored `.dart_tool/stremio_tv_parser/`
(delete any `*.dill` in a copied parser package; recompilation is
timestamp-based), including self-tests and other features' manifests.
Original-code proofs use a detached worktree under
`.dart_tool/stremio_tv_original/`. `suite_evidence.py` runs are
**serialized** in this worktree (one Flutter suite at a time) with `--no-pub`
and an explicit `--concurrency` recorded in the env file, not in the paths
list. Five refactors run concurrently on this machine: load-sensitive flakes
(the WebDAV shard tests, the self-profile PIN 180 ms settle) are rerun in
isolation and recorded as a NOTE, never allowlisted.

## Goal

`lib/screens/stremio_tv/stremio_tv_screen.dart` is **3,957 lines** (not
formatter-clean: `dart format --set-exit-if-changed` changes it): 50 import
directives (1–51, unsorted, mixed package/relative), no `part`, and **11
top-level declarations** — the public `StremioTvScreen` (58–69, one field
`isTelevision` with a doc comment) and its State `_StremioTvScreenState`
(71–3382), the manual source picker (`_ManualSourcePickerSheet` + State,
3386–3655, under the banner comment at 3384), `_SourcePickerTab` + State
(3658–3737), `_SourcePickerItem` + State (3740–3905), and three data classes
(`_ChannelPlaybackResult` 3908–3940, `_ResolvedSourceChoice` 3942–3947,
`_StremioTvPlaybackCursor` 3949–3957). The State holds **40 instance fields**
(one, `_pushingChannelDetail`, declared mid-class at 2368), one getter
(`_filteredChannels`), one static method (`_extractQuality`), about 60
methods and **23 `setState(` tokens**. It is Stremio TV: channel discovery
and lazy item loading, the header (search, options menu with import submenu,
debrid provider menu), the tuner wall, channel detail/guide/favourite/local
catalog actions, the play pipeline (stream search, episode filter, TorBox and
Premiumize cache filters, five debrid resolvers with the
`StremioTvDebridFallback` ladder, a manual source picker), and the player
handoff with its in-player guide, channel-switch and next-slot providers.

Split it into the existing feature `lib/features/stremio_tv/`, **moving code
verbatim**. Unchanged: the widget tree, keys, `const` placement, focus nodes
and traversal, build order, lifecycle order, delays and timeouts, the
playback handoff arguments, ordering and callback targets, the provider
result maps, and every user-visible string.

**Name and facade.** `stremio_tv` is already a registered feature
(`check_search_architecture.py:13`) holding the catalog picker
(`application/`, `data/`, `models/`, `presentation/`). The public
`StremioTvScreen` stays at `lib/screens/stremio_tv/stremio_tv_screen.dart`,
which becomes the facade, because `lib/main.dart:61` imports it (constructed
at 1549 and 3264), `test/theme/source_guard_test.dart:130` names it as a
frozen tab root, and `dev/tool/theme_rendered_set.py:29` uses it as the
surface root. The new code goes to a new bridge
`lib/features/stremio_tv/presentation/legacy_stremio_tv/` plus one models
file, one application file and two plain presentation files (Destination
layout). The existing catalog-picker files are not touched, and no rule
added here applies to them.

**Playback-adjacent, not player work.** The file *starts* playback (two
`VideoPlayerLauncher.push(context, VideoPlayerLaunchArgs(...))` sites) and
supplies the player's source resolver and Stremio TV guide/switch/next
providers. All of it moves verbatim and is pinned by the PLAYBACK CONTRACT
below. `video_player_screen.dart`, `lib/screens/video_player/`,
`VideoPlayerLauncher`, `lib/features/player_launch/`, `MainPageBridge`,
`StremioTvService`, `StremioTvDebridFallback`, the debrid services, the
tuner/local-catalog/guide/filter widgets and all Android/tvOS native code
are out of scope and are not edited.

**Decisions taken before design review (Claude, 2026-10-06).**

| # | Decision | Rationale |
| --- | --- | --- |
| D1 | **Format-only reference commit.** The file is not formatter-clean, so step 0 commits (a) `style(stremio-tv): format the original Stremio TV screen` (this file plus the hand-raised `file_size_baseline.txt:15` entry: formatting makes the file 3,958 lines) with the token/optional-comma proof; (a) is R. | Spotlight precedent; the verbatim checker compares formatted ASTs. |
| D2 | **`build` is 565 lines in one method**; move-only cannot split it. It moves alone into `legacy_stremio_tv/stremio_tv_layout.dart` with a documented size exception equal to its measured lines (scratch measurement: 682 qualified method lines, about 700 with imports and scaffolding; under the 800 ceiling). The facade keeps an exact forwarder `Widget build(BuildContext context) => _sections.layout.build(context);` (addon-hub precedent). | Exit: a later paint decomposition of the header bar and channel area with its own goldens and review. |
| D3 | **`_playChannel` is 422 lines.** It moves alone into `stremio_tv_play_channel.dart` (estimate about 470 formatted with imports and header). If the measured file exceeds 500, it gets the same kind of documented exception equal to its measured lines; no other exception is authorized. | Exit: the players goal (a play-pipeline decomposition with its own characterization). |
| D4 | Private widget classes keep private runtime types, exported by typedef from their own file (Debrify TV/catalog precedent); an exact typed constructor forwarder is added only if step 0b's compiling probe shows a new `unused_element_parameter` (frozen in the scaffolding sidecar). The three data classes become public renamed models (`_AllDebridPrepared` precedent). | Keeps widget runtime types; data classes must be named across libraries. |
| D5 | Pre-existing defects move unchanged (Found, not fixed). No behaviour fix, guard or dead-code removal in this split. | Move-only. |
| D6 | No device gate. Device-only items go to the end-of-series device checklist (Definition of done). | User decision for the whole series. |

**Temporary exceptions and their exits.**

| Exception | Exit |
| --- | --- |
| State-driven sections over route-owned records instead of Riverpod | Stremio TV notifiers keyed by profile and route instance |
| A `legacy_stremio_tv/` bridge calling services, storage and the launcher directly (`StremioTvService`, `StremioTvStorage`, `RealDebridStorage`, `TorboxStorage`, `PikpakStorage`, `PremiumizeStorage`, `AllDebridStorage`, `TorrentService`, `DebridService`, `TorboxService`, `TorboxTorrentControlService`, `PikPakTvService`, `PikPakApiService`, `PremiumizeService`, `AllDebridService`, `StreamUrlValidator`, `MdblistService`, `AnalyticsService`, `MainPageBridge`, `VideoPlayerLauncher`, `PlayLoaderStyleController`) | Stremio TV data contracts (channel library, stream search, debrid resolve, player handoff), after which the folder dissolves |
| Size exceptions D2 (and D3 if measured over 500) | The paint decomposition / the players goal |
| Legacy text (every snackbar, hint and menu label) | The localization migration |

## Public surface (unchanged)

`class StremioTvScreen extends StatefulWidget` (58–69) with its doc comment,
`final bool isTelevision` (with its four-line doc), `const
StremioTvScreen({super.key, this.isTelevision = false})` and `createState()
=> _StremioTvScreenState()`. It stays byte-identical in the facade with its
State. One production importer (`lib/main.dart:61`); no test importer. No
`GlobalKey` reaches the State; outside access is only through the
`MainPageBridge` registrations in Contract 2. The compatibility export
`lib/screens/stremio_tv/stremio_tv_service.dart` is untouched.

## What it contains (unformatted lines at `0cb50df7`; after step 0 the manifest at R is authoritative)

| Lines | Area |
| --- | --- |
| 1–51 | Imports |
| 53–69 | `StremioTvScreen` |
| 71–143 | State fields (39 of 40) and `_rotationFor` (93–95, between fields) |
| 145–211 | `initState`, `dispose` |
| 213–345 | `_loadSettings`, `_loadAvailableProviders`, `_discoverAndLoad`, startup notifiers, `_refresh`, `_sortedChannels` |
| 347–414 | `_submenuItem`, `_topMenuItem` (menu item paint with D-pad) |
| 416–530 | Filter page, local catalogs, six imports, settings page, provider select and labels |
| 532–602 | Lazy loading (`_ensureChannelLoaded`, `_ensureChannelItemsLoaded`) |
| 604–845 | Playback helpers: `_extractQuality`, `_tryDirectStreams`, `_tryTorrentsViaDebrid`, `_filterTorrentsForEpisode`, `_sortStreamsByQuality`, `_isValidStreamUrl`, `_tvProviderInfo` |
| 847–1268 | **`_playChannel` (422)** |
| 1270–1566 | `_resolveChannelPlayback`, `_showManualSourcePicker`, `_computeStartProgress`, cursor helpers, `_guideDataFor`, `_playbackResultToMap` |
| 1568–1751 | Source resolver factory; in-player guide metadata and the three provider factories |
| 1753–2345 | `_resolveTorrentUrl` (fallback ladder), TorBox cache hashes, RD, AllDebrid, TorBox, PikPak (+ trash), Premiumize resolvers |
| 2347–2581 | `_playChannelById`, channel detail (with the mid-class field), guide, favourites, local catalog copy/edit |
| 2583–2690 | Search getter, focus helpers, row-node reorder, search Back ladder |
| 2692–3260 | **`build` (565)** |
| 3262–3382 | `_headerButton`, `_buildLoadingSkeleton` |
| 3384–3905 | Manual source picker sheet, tab and item widgets |
| 3907–3957 | Three data classes |

**State and resources.** Fields group into four owners: library (7),
settings (12), playback (7) and focus (14). Owned resources: one
`TextEditingController` (with a never-removed listener), one
`ValueNotifier<int>`, five fixed `FocusNode`s plus the dynamic
`_rowFocusNodes` list, two `MenuController`s (no dispose API), one
`StremioTvTunerController` (never disposed). The picker widgets own their
own focus nodes. No timer, ticker, subscription, mixin, `RouteAware`,
`didChangeDependencies` or `didUpdateWidget`.

## Contracts that must not change

Each contract is pinned by source guards and, where observable, by behaviour
tests. Guards compare whole bodies, comments included, through
`test/support/stremio_tv_source.dart` (Contract 9 / Step 0.8).

1. **Lifecycle (verbatim in the facade State, receiver-only qualification).**
   - `initState` (145–186), in order: `super` →
     `AnalyticsService.screenView('stremio_tv')` →
     `_loadSettings().then((_) => _discoverAndLoad())` (unawaited) →
     `MdblistService.instance.isAuthenticated().then(…)` with its `mounted`
     and inequality check → `_searchController.addListener(…)` (lowercase,
     trim, inequality, `setState`) → `_tvContentFocusHandler = () {
     _searchBtnFocusNode.requestFocus(); }` →
     `MainPageBridge.registerTvContentFocusHandler(9, _tvContentFocusHandler!)`
     → `MainPageBridge.watchStremioTvChannel = (channelId) async { if
     (mounted) { _playChannelById(channelId); } }` →
     `getAndClearStremioTvChannelToAutoPlay()` into `_pendingChannelId` →
     the trailing "no periodic refresh" comment. Every comment stays.
   - `dispose` (189–211), in order: `_contentRevision.dispose()` → the four
     header focus nodes in declaration order → `_searchController.dispose()`
     → `_searchFocusNode.dispose()` → every row node → `if
     (MainPageBridge.watchStremioTvChannel != null) { … = null; }` →
     `if (_tvContentFocusHandler != null)` unregister tab 9 with the stored
     handler → `super.dispose()`.
   - `build` becomes the exact forwarder (D2). The moved body keeps its
     `context` **parameter** (the State's build context), so every lexical
     use stays a parameter use.
   - Field initializers keep their evaluation point: the four records are
     built **eagerly in one State field initializer**, so
     `StremioTvService.instance`, the tuner controller, the `ValueNotifier`,
     the focus nodes, menu controllers and text controller are still created
     at State construction, in original declaration order within each
     record.
2. **External hooks and callback identity.** The tab-9 content handler is
   the same stored closure at register and unregister
   (`main_page_bridge.dart:799–806` removes only on `==`).
   `watchStremioTvChannel` is the original closure (a `mounted` check, then
   `_sections.actions.playChannelById(channelId)`), assigned in `initState`
   and nulled under the original non-identity check in `dispose`. The pending
   id is consumed once in `initState` and played after the first discovery
   (`_discoverAndLoad`: `_startupAutoPlayActive = true` →
   `_ensureChannelLoaded(id)` → `_playChannelById(id)`). **Auto-play paths,
   named:** `HomeHeroShellBridge` (`lib/features/home/presentation/home_hero_shell_bridge.dart:165–169`)
   calls `watchStremioTvChannel` when set, else
   `notifyStremioTvChannelToAutoPlay` then switches tab. Neither caller is
   edited. `MainPageBridge.focusTvSidebar?.call()` stays at its three sites
   (search field Left, search button Left, tuner `onFocusSidebar`).
3. **PLAYBACK CONTRACT.**
   1. **Player pushes (ledger, frozen).** Step 0 commits
      `dev/tool/stremio_tv_handoff_ledger.json` with both
      `VideoPlayerLauncher.push` sites — **P1** (manual picker, 1180) and
      **P2** (auto, 1232) — each: the receiver (`VideoPlayerLauncher.push`
      with the State context read live at the site, i.e.
      `_deps.context()`), no named push options, and the ordered list of the
      **19** `VideoPlayerLaunchArgs` `name: expression` pairs exactly as
      written, plus "every other parameter is not passed (constructor
      default)":

      | Arg | P1 | P2 |
      | --- | --- | --- |
      | `videoUrl` | `result.url` | `firstPlayableUrl` |
      | `title` | `_currentPlayTitle ?? item.name` | same |
      | `startAtPercent` | `_currentSlotProgress` | same |
      | `contentImdbId` / `contentTitle` / `contentType` | `item.effectiveImdbId` / `item.name` / `item.type` | same |
      | `contentSeason` / `contentEpisode` | `season` / `episode` | same |
      | `stremioSources` | `playableSources` | same |
      | `stremioCurrentSourceIndex` | `result.sourceIndex` | `firstPlayableIndex` |
      | `resolveStremioSource` | `_createSourceResolver(item, season: season, episode: episode)` | same |
      | `stremioTvChannels` | `_buildGuideChannelMetadata()` | same |
      | `stremioTvCurrentChannelId` | `channel.id` | same |
      | `stremioTvRotationMinutes` / `stremioTvSeriesRotationMinutes` / `stremioTvMixSalt` | `_rotationMinutes` / `_seriesRotationMinutes` / `_mixSalt` | same |
      | `stremioTvGuideDataProvider` / `stremioTvChannelSwitchProvider` / `stremioTvNextProvider` | `_createGuideDataProvider()` / `_createChannelSwitchProvider()` / `_createNextProvider()` | same |

      The checker compares each moved site with its ledger entry
      token-for-token (registered receiver qualification reversed); the
      provider factories are **called at the push site** (a fresh closure per
      launch, never cached in a field).
   2. **Order around each push (exact).** P2: `if (!mounted ||
      _playGeneration != myGeneration) { overlay.dismiss(); return; }` →
      `overlay.setStage(PlayLoadStage.starting)` → `overlay.dismiss()` →
      `_notifyStartupPlayerLaunching()` → `_rememberPlaybackCursor(channel.id,
      baseSlotStartMs: nowPlaying.slotStart.millisecondsSinceEpoch,
      slotOffset: 0)` → `await` push. P1: `overlay.dismiss()` →
      `_notifyStartupAutoLaunchFailed('No auto-play stream resolved')` →
      `if (mounted && _playGeneration == myGeneration)` → `await
      _showManualSourcePicker(…)` → `if (result != null && mounted)` (no
      generation re-check, Found-not-fixed 4) → notify launching → remember
      cursor → `await` push → `return`. The `catch (e)` arm keeps
      `overlay.dismiss()` → notify failed with `'Error searching streams: $e'`
      → `mounted` → snackbar.
   3. **Loader overlay.** `PipelineLoadingOverlay.show(context, …)` keeps
      every argument (poster/title, provider info from `_tvProviderInfo()`,
      the theme tokens, the Play Loader style ternary,
      `PlayLoaderArt.fromMeta(item)`, inks) and the `onCancel` closure (bump
      `_playGeneration`, then notify failed `'Playback canceled'`). Its 19
      `overlay.` calls keep their order and stages (`searching` with
      `sourceCount`, `cacheCheck` with and without `cachedCount`,
      `preparing`, `starting`) and every `dismiss()` before each return.
   4. **Stream search.** Both `TorrentService.searchByImdbWithStremio(` calls
      keep their arguments: `_playChannel` passes `includeMediaServers:
      false`, `isMovie`, `season`, `episode`, `contentType`, `stremioTimeout:
      7 s`, `engineTimeout: 10 s`; `_resolveChannelPlayback` passes the same
      **without** `engineTimeout` (Found-not-fixed 6). The source filters (no
      external streams, direct ≥ 5 MB, no 480p torrents), the episode filter,
      the TorBox and Premiumize cache filters (with `mounted` checks only),
      torrents-first ordering and the 20-attempt caps are unchanged.
   5. **Cancellation (`_playGeneration`, 15 occurrences, enumerated).**
      Declaration (89); `_tryDirectStreams` 638, 640; `_tryTorrentsViaDebrid`
      675 (memoized TorBox `isCancelled`), 680, 688 (resolver `isCancelled`);
      `_playChannel` 848 (`final myGeneration = ++_playGeneration;`), 853,
      924 (`_playGeneration++` in `onCancel`), 942, 981, 1165 (`==`), 1216;
      `_resolveChannelPlayback` 1424 (`final gen = _playGeneration;`); and
      the comment at 923. Every occurrence stays at its site with
      `!mounted ||` / `mounted &&` exactly as written. `isCancelled` (18
      occurrences in `_resolveTorrentUrl`, `_loadTorboxCachedHashes`,
      `_resolveViaTorbox`, `_resolveViaPikPak`) is unchanged. Which awaits
      honour cancellation is characterized as-is (Step 0, C3 cancel).
   6. **Provider results handed to the player.** `_playbackResultToMap` keys
      and their conditional entries; `_guideDataFor` (7 keys);
      `_buildGuideChannelMetadata` (5 base keys, `nowPlaying` 7, `nextUp` 5);
      the guide data provider's per-id map (with `loadChannelItems` for
      unloaded channels); the channel-switch provider (`_resolveChannelPlayback(ch)`
      → remember cursor → map); the next provider (`_nextSlotOffsetFor` →
      resolve with `slotOffset` → remember cursor → map, else the debug log,
      remember the failed slot against the current base and return null);
      `_createSourceResolver` snapshots `_debridProvider` **at creation**
      into its local `debridProvider`. `_ChannelPlaybackResult` keeps its 14
      fields and constructor order under its new public name.
   7. **Debrid resolve.** `_resolveTorrentUrl` keeps its
      `StremioTvDebridFallback.resolve<String>` call with `selected`,
      `isCancelled`, the `canAttempt` and `attempt` switches (provider
      order, RD blocked-torrent rule, auto-only TorBox cache check through the
      memoized loader or a one-torrent load, Premiumize/AllDebrid enable
      checks, key reads). Each resolver keeps its magnet format, episode
      selection, largest-file rule, cleanup (RD delete on mismatch, AllDebrid
      delete on not-ready and on mismatch, TorBox `finally` delete with 10 s
      timeout unless kept, PikPak `finally` trash with 10 s timeout unless
      kept), the TorBox **3 s** settle and every `debugPrint`.
   8. **Manual source picker.** `showModalBottomSheet<…>(context:
      State context, isScrollControlled: true, backgroundColor:
      Colors.transparent, builder: (ctx) => picker sheet)` with
      `validateDirectUrl:` the `_isValidStreamUrl` tear-off of one live
      section instance and `resolver:` the factory result. The sheet, tab
      and item classes move whole (their own `context`/`setState`/`mounted`/
      `widget` are untouched): post-frame first-item focus, tab filtering,
      resolve/validate/pop of `_ResolvedSourceChoice`, D-pad handlers
      (activate, Up to tabs from the first item, Esc/Back pops).
   9. **No new playback seam.** No production hook is added for tests. A
      guard rejects any new import of `video_player_launcher`,
      `player_launch`, `media_kit` or `lib/screens/video_player/` in a
      Stremio TV file other than the registered handoff files
      (`stremio_tv_play_channel.dart`, `stremio_tv_player_guide.dart`), and
      any new `VideoPlayerLauncher.push(` or `VideoPlayerScreen(` in this
      feature beyond the two ledger sites.
4. **Settings and persistence.** `_loadSettings` keeps its read order (13
   awaits including the five-provider probe), the conditional
   `setStremioTvDebridProvider('auto')` reset, and **no `setState`** (callers
   rebuild: `_openStremioTvSettings`, `_refresh`, discovery). Provider menu
   writes through `setStremioTvDebridProvider`; favourites through
   `setStremioTvChannelFavorited`; filter page and local-catalog dialogs own
   their writes.
5. **Channel library.** Discovery, refresh (single-flight on `_refreshing`,
   cache invalidation via `lastFetched = null`, loading-id clear, row-node
   rebuild), favourite sort, lazy item loading (dedupe on
   `_loadingChannelIds`, error → `lastFetched = now`, empty-channel removal
   with focus rescue and `_focusedIndex` sync inside `setState`, otherwise
   `_contentRevision.value++` only), the 120 ms × ≤ 8000 ms detail poll and
   the detail re-entrancy flag are unchanged.
6. **D-pad and focus.** Unchanged: the search Back ladder on its
   non-focusable ancestor; the three header buttons' Left/Right/Up/Down/
   activate handling (Down → `_focusDialFromHeader`, which routes through
   `_tunerController.focusRealIndex` before falling back); menu open/close
   keys; `_submenuItem` Left/Right → submenu node and Esc/Back → close +
   menu node; `_topMenuItem` close keys with `closeOnArrowUp`; `autofocus` on
   Shuffle, Manage and the provider Auto item; the search field's arrow
   callbacks; post-frame focus after favourite toggle and local-catalog
   edit; the tuner's `onFocusHeader`/`onFocusedIndexChanged` (bookkeeping
   without `setState`).
7. **Rebuild boundaries.** No builder becomes a widget, no wrapper is
   inserted, no `const` changes. The `ValueListenableBuilder` on
   `_contentRevision` still computes `_filteredChannels` inside its builder;
   `ListenableBuilder`, `MenuAnchor.builder` and `Builder` scopes keep their
   lexical `context`.
8. **Profiles and stale results.** No profile capture exists today; every
   async path keeps exactly its current `mounted`/generation guards — no
   guard is added or removed (Found, not fixed, lists the gaps).
9. **Source-text readers.** `test/media_server_service_test.dart:1268–1279`
   reads this file and requires exactly two `searchByImdbWithStremio(…);`
   calls, each containing `includeMediaServers: false`. In (b) only the
   `File(...).readAsStringSync()` is replaced by
   `stremioTvCurrentSource()` (Step 0.8); the regex and both expectations
   stay byte-identical, and the guard keeps biting on current code.

## Destination layout

All destinations are under `lib/features/stremio_tv/`. Each is at most 500
formatted lines except D2 (and D3 if measured over 500). Estimates are
formatted original lines + imports/header + about 4% receiver wraps; the
step 0 dependency report settles membership and each creation commit
measures.

**Outside the bridge (service-free):**

| File | Contents | Est. |
| --- | --- | --- |
| `models/stremio_tv_playback_records.dart` | `_ChannelPlaybackResult` → `StremioTvChannelPlaybackResult` (doc kept), `_ResolvedSourceChoice` → `StremioTvResolvedSourceChoice`, `_StremioTvPlaybackCursor` → `StremioTvPlaybackCursor` | 60 |
| `application/stremio_tv_stream_quality.dart` | `StremioTvStreamQuality` holding `static String? extractQuality(String name)` verbatim with its doc (was the State static `_extractQuality`) | 25 |
| `presentation/stremio_tv_manual_source_picker.dart` | banner comment, `_ManualSourcePickerSheet` + State (private; `typedef StremioTvManualSourcePickerSheet = _ManualSourcePickerSheet;`) | 290 |
| `presentation/stremio_tv_source_picker_controls.dart` | `_SourcePickerTab` + State, `_SourcePickerItem` + State (private; typedefs `StremioTvSourcePickerTab`, `StremioTvSourcePickerItem`; forwarders only per D4) | 260 |

**`presentation/legacy_stremio_tv/` (the bridge; exact path in the guard):**

| File | Contents | Est. |
| --- | --- | --- |
| `stremio_tv_bindings.dart` | `StremioTvDependencies`: owners, sections, live `context()`/`mounted()`/`isTelevision()` getters and the State's `setState` tear-off | 40 |
| `stremio_tv_owners.dart` | `StremioTvOwners` composing the four records, eager | 20 |
| `stremio_tv_library_state.dart` | `service`, `channels`, `loading`, `refreshing`, `contentRevision` (doc), `mixSalt` (comment), `loadingChannelIds` (comment) | 30 |
| `stremio_tv_settings_state.dart` | `rotationMinutes` … `hideNowPlaying` (11) + `mdblistConnected` (comment) | 30 |
| `stremio_tv_playback_state.dart` | `currentSlotProgress`, `playGeneration`, `currentPlayTitle` (comment), `playbackCursors`, `pendingChannelId`, `startupAutoPlayActive` (comment), `pushingChannelDetail` | 25 |
| `stremio_tv_focus_state.dart` | `rowFocusNodes`, `focusedIndex`, `tunerController` (doc), header focus nodes and menu controllers (comment), search controller/node/query/flag (comment), `tvContentFocusHandler` (comment) | 45 |
| `stremio_tv_sections.dart` | `StremioTvSections`: constructs every section once, inert constructors | 60 |
| `stremio_tv_settings_loader.dart` | `_loadSettings`, `_loadAvailableProviders`, `_openStremioTvSettings`, `_setDebridProvider`, `_providerShortLabel`, `_providerFullLabel` | 150 |
| `stremio_tv_channel_library.dart` | `_rotationFor` (doc), `_discoverAndLoad`, both startup notifiers, `_refresh`, `_sortedChannels`, the Lazy Loading banner, `_ensureChannelLoaded`, `_ensureChannelItemsLoaded` | 210 |
| `stremio_tv_menu_actions.dart` | `_openChannelFilter`, `_openLocalCatalogs`, six `_importFrom*` | 90 |
| `stremio_tv_chrome.dart` | `_submenuItem` (doc), `_topMenuItem`, `_headerButton`, `_buildLoadingSkeleton` | 215 |
| `stremio_tv_stream_selection.dart` | the Playback banner, `_tryDirectStreams` (doc), `_tryTorrentsViaDebrid`, `_filterTorrentsForEpisode` (doc), `_sortStreamsByQuality`, `_isValidStreamUrl` (doc), `_tvProviderInfo` (doc) | 255 |
| `stremio_tv_play_channel.dart` | `_playChannel` alone (D3) | ~470 |
| `stremio_tv_channel_resolve.dart` | `_resolveChannelPlayback` (doc), `_showManualSourcePicker` (doc), `_computeStartProgress` (doc) | 265 |
| `stremio_tv_player_guide.dart` | `_rememberPlaybackCursor`, `_nextSlotOffsetFor`, `_guideDataFor`, `_playbackResultToMap`, the Source Resolution banner + `_createSourceResolver`, the In-Player Guide banner + `_buildGuideChannelMetadata`, `_createGuideDataProvider`, `_createChannelSwitchProvider`, `_createNextProvider` | 285 |
| `stremio_tv_debrid_resolvers.dart` | `_resolveTorrentUrl` (doc), `_loadTorboxCachedHashes`, `_resolveViaRealDebrid`, `_resolveViaAllDebrid` (doc) | 310 |
| `stremio_tv_cloud_resolvers.dart` | `_resolveViaTorbox`, `_resolveViaPikPak`, `_trashRejectedPikPakItem`, `_resolveViaPremiumize` | 320 |
| `stremio_tv_channel_actions.dart` | `_playChannelById`, the Channel Detail banner, `_openChannelDetail` (doc), `_pushChannelDetail`, the Channel Guide banner + `_showGuide`, the Favorites banner + `_toggleFavorite`, `_copyLocalCatalogJson`, `_editLocalCatalog` | 250 |
| `stremio_tv_navigation.dart` | the Search banner, `_filteredChannels` getter, `_currentFocusedChannelId`, `_focusDialFromHeader` (doc), `_reorderRowFocusNodes`, `_handleSearchBarBack` (doc) | 125 |
| `stremio_tv_layout.dart` | the Build banner and `build` alone (D2, size exception) | ~700 |

**Banner placement.** Banners and other free comments are manifest leaves.
Each banner moves to the file of the section whose members it heads, placed
immediately above that section's first moved member from the original run;
the mid-class Channel Detail banner (2364–2366) therefore moves to
`stremio_tv_channel_actions.dart` above `openChannelDetail` (its field
`_pushingChannelDetail` moves to the playback record without the banner).
The dependency report lists every comment leaf and its destination.

**Frozen section map.** Used identically by the contracts, manifest,
composition and callback fixtures (`receiver_paths`/`receiver_owners`,
`callback_instances`). A change is a plan amendment.

| Key (`_sections.<key>`) | Class | File (`legacy_stremio_tv/`) |
| --- | --- | --- |
| `settings` | `StremioTvSettingsLoader` | `stremio_tv_settings_loader.dart` |
| `library` | `StremioTvChannelLibrary` | `stremio_tv_channel_library.dart` |
| `menuActions` | `StremioTvMenuActions` | `stremio_tv_menu_actions.dart` |
| `chrome` | `StremioTvChrome` | `stremio_tv_chrome.dart` |
| `streams` | `StremioTvStreamSelection` | `stremio_tv_stream_selection.dart` |
| `play` | `StremioTvPlayChannel` | `stremio_tv_play_channel.dart` |
| `resolve` | `StremioTvChannelResolve` | `stremio_tv_channel_resolve.dart` |
| `guide` | `StremioTvPlayerGuide` | `stremio_tv_player_guide.dart` |
| `debrid` | `StremioTvDebridResolvers` | `stremio_tv_debrid_resolvers.dart` |
| `cloud` | `StremioTvCloudResolvers` | `stremio_tv_cloud_resolvers.dart` |
| `actions` | `StremioTvChannelActions` | `stremio_tv_channel_actions.dart` |
| `navigation` | `StremioTvNavigation` | `stremio_tv_navigation.dart` |
| `layout` | `StremioTvLayout` | `stremio_tv_layout.dart` |

Owner records are `_owners.library` (`StremioTvLibraryState`), `.settings`
(`StremioTvSettingsState`), `.playback` (`StremioTvPlaybackState`), `.focus`
(`StremioTvFocusState`).

**Cross-class privates** become manifest-listed public names
(`_playChannel` → `playChannel`, …). Each section exposes only what other
sections or the facade call; anything called only within its own file keeps
its private name. `_extractQuality(x)` becomes
`StremioTvStreamQuality.extractQuality(x)` (registered static rename).

**The facade** (`lib/screens/stremio_tv/stremio_tv_screen.dart`) holds
sorted imports, `StremioTvScreen` byte-identical, and `_StremioTvScreenState`
with the eager `final StremioTvOwners _owners = StremioTvOwners();`, a
nullable cached composition (`StremioTvSections? _composition;` and a getter
that builds it once with `StremioTvDependencies(owners: _owners, context: ()
=> context, mounted: () => mounted, setState: setState, isTelevision: () =>
widget.isTelevision)`; never `late`, never per build), the verbatim
lifecycle and the exact `build` forwarder. `widget.isTelevision` reads in
moved code become `_deps.isTelevision()` (registered `live_widget_getters`,
the Spotlight precedent: the factory must read the current widget).

**Facade cap, measured over every retained physical line.** Estimate:
imports 8 + widget with docs 17 + State header and composition 14 +
`initState` about 45 + `dispose` about 26 + `build` forwarder 2 + blanks and
closing about 10 ≈ **120–140 lines**. At step 0b (compiling probe) and each
step from 2, Progress records `wc -l` and a per-span breakdown (imports,
widget, State header, owners/composition, lifecycle, forwarder, remaining
blank/comment lines) whose sum equals the total. Target 300; the enforced
cap is the measured complete value (`STREMIO_TV_FACADE_CAP`), at most 300;
no line may be added to use headroom.

**Guard rules** (step 1, `check_search_architecture.py`, additive, keyed by
this feature): `STREMIO_TV_FACADE`, `STREMIO_TV_BRIDGE`,
`STREMIO_TV_COMPLETE = False`, `STREMIO_TV_PREEXISTING` (the exact seven
catalog-picker files present at base `0cb50df7`: `application/stremio_tv_providers.dart`,
`data/stremio_tv_catalog_editor.dart`, `models/stremio_tv_catalog_option.dart`,
`models/stremio_tv_catalog_picker_result.dart`,
`presentation/stremio_tv_catalog_picker_dialog.dart`,
`presentation/stremio_tv_catalog_picker_views.dart`,
`presentation/stremio_tv_focus_frame.dart`) — **every other** file under
`lib/features/stremio_tv/` (this split's files and any future file) is held
to the 500-line cap (or its registered exception) and the service rule,
while the seven pre-existing files keep exactly their current treatment; the bridge in `LEGACY_PLAYBACK_BRIDGES` (still no
`shared_preferences`/`sqflite`); no facade back-import from any
`lib/features/stremio_tv/` file; `lib/services/` imports only inside the
exact bridge; the models/application files import no `lib/services/` and no
UI (existing layer rules); the playback-import ban (Contract 3.9); 500-line
caps with `STREMIO_TV_SIZE_EXCEPTIONS`, and the global 800 ceiling read for
the layout file stays satisfied without generalisation (estimate about
700). At step 7 (`STREMIO_TV_COMPLETE = True`): the facade added to `paths`
in `main()`, the facade in `COMPOSITION_ROOTS` with a comment, its measured
cap and the `TEMP(stremio_tv)` rejection. Tests run **the real checker**
against a temporary copy of the tree and must reject: the facade missing;
the facade at cap + 1; `TEMP(stremio_tv)` in the facade and in a feature
file; each size-exception file at its measured cap + 1; an unrelated new
Stremio TV destination at 501 lines, and separately an unregistered new file
under `lib/features/stremio_tv/presentation/` at 501 lines; a non-bridge new file importing
`lib/services/`; a `video_player_launcher` import in
`stremio_tv_channel_actions.dart`. The unmodified tree passes, and the
existing catalog-picker files (including the 618-line picker dialog) pass
unchanged.

## Size exceptions

`STREMIO_TV_SIZE_EXCEPTIONS = { STREMIO_TV_BRIDGE + "stremio_tv_layout.dart":
<measured> }` (+ `stremio_tv_play_channel.dart: <measured>` only if D3
triggers). Values are measured in each file's creation commit. Each file
holds its one method alone plus imports, the section header and dependency
getters. Comments state the reason (a move cannot split one method body) and
the exit (D2/D3). `dev/tool/file_size_baseline.txt` gains no new entry
(both files are under 800); line 15 is lowered as the facade shrinks and
removed below 800. The checker rejects growth.

## Technique

As in the Debrify TV and Spotlight plans, plus:

1. **Two originals with a format commit (D1).**
   - **(a) Format-only commit** `style(stremio-tv): format the original
     Stremio TV screen`: this file plus the hand-raised `file_size_baseline.txt:15`
     entry (3,958 lines after formatting), nothing else; token equality with the original
     except whitespace and AST-identified optional formatter commas (listed
     by node; negatives: an edited comment or literal, a non-optional comma,
     must fail); idempotence; `file_size_baseline.txt:15` raised by hand to
     the measured value if it grows. New infos caused by formatting (e.g.
     `curly_braces_in_flow_control_structures` on wrapped `if`s) are
     recorded by identity in `stremio_tv/base-fmt`, not fixed. (a) is R
     unless step 0 proves a seam is needed (then stop and ask).
   - **(b) Characterization checkpoint** `test(stremio-tv): step 0
     original-code characterization checkpoint`: application files
     unchanged from R; adds the frozen tests, harness, reader, fixtures,
     checker config, ledger and macOS goldens, and switches the
     media-server source test to the reader (Step 0.8). It is the ORIGINAL
     for behaviour. Progress proves `git rev-parse <b>:lib` = `<R>:lib` (and
     `pubspec.yaml`, `pubspec.lock`).
2. **Strict-lint baseline and rename probe.** Re-measure R under the
   features analysis config in a detached worktree inside `.dart_tool/`
   (qualifying relative imports only), recorded by identity (rule, enclosing
   member, message). A throwaway rename/receiver probe applies the
   manifest's renames, receivers and typedefs to a compiling copy and
   inventories, by identity, every diagnostic that appears or disappears
   (`use_build_context_synchronously` changes from `_deps.context()` /
   `_deps.mounted()`, `library_private_types_in_public_api` from typedefs,
   `unused_element_parameter` on the moved private widgets — which triggers
   D4's forwarders). Baseline and probe combine by maximum per identity.
   Every surviving warning gets an `analyzer_allowlist.txt` entry (by
   destination path) in the commit that creates its file.
3. **Live getters and setState.** Sections reach `context`, `mounted`,
   `widget.isTelevision` and the State's `setState` only through
   `_deps.context()`, `_deps.mounted()`, `_deps.isTelevision()` and
   `_deps.setState(...)`, evaluated at the original site; nothing is hoisted
   or cached. **Lexical scopes stay lexical:** `build`'s `context`
   parameter and every builder `context` (`ListenableBuilder` ×2,
   `MenuAnchor.builder` ×2, `Builder`, `ValueListenableBuilder`,
   `showModalBottomSheet`'s `ctx`, the skeleton `itemBuilder`), and
   everything inside the three picker classes (their own State members).
   There is no shadowed `setState` in the State (`lexical_state_setters`
   empty; verify). Negatives: a builder `context` replaced by
   `_deps.context()`; a `_deps.context()` replaced by the `build` parameter
   in a non-build section; a picker `setState` qualified.
4. **Field ownership and the occurrence-level binding guard.** All 40
   fields move at step 2 into the four records, renamed by dropping the
   leading underscore, and **every moved field reference is
   receiver-qualified** (`_owners.library.channels`). Reuse the Debrify TV
   opt-in `occurrence_field_bindings` key and binder with **two narrowly
   scoped, opt-in extensions** (authorized here; Debrify TV's config,
   adapter output and self-tests must stay byte-identical): **(i)** the
   State owner and record-path qualification come from the config (`owners:
   ["_StremioTvScreenState"]`, `record_paths` from `receiver_paths`) instead
   of the hard-coded `_DebrifyTVScreenState`
   (`occurrence_field_bindings.py:15`, `:52`), with Debrify TV's values as
   the default; `mandatory_qualification: true` is **implemented** (a
   destination `lexical`+`unbound` record-member name is rejected in every
   new Stremio TV file) rather than merely stated; **(ii)** alignment
   accepts each registered `live_widget_getters` substitution
   (`widget.isTelevision` ↔ `_deps.isTelevision()`) beside the three State
   callbacks, as registered receiver scaffolding only. Positives: all three
   `widget.isTelevision` sites (`_openChannelFilter`, `_pushChannelDetail`,
   `build`'s tuner argument). Negatives (through checker **and** reader): a
   cached widget value (`final tv = _deps.isTelevision();` hoisted), the
   getter on a wrong receiver (`_owners.focus`), a bare record field, and the
   Debrify TV fixtures unchanged. Enable `spotlight_state_field_bindings` for
   `_StremioTvScreenState`. Hazards (dependency report lists them all):
   locals named `channels` in `_discoverAndLoad` and `_refresh` and the
   `_sortedChannels(channels)` parameter beside the `channels` field;
   `debridProvider` as a local in `_loadSettings` and
   `_createSourceResolver` and as a parameter of `_resolveTorrentUrl`;
   `channel`/`item` locals (not fields). Positives: each hazard method
   unchanged; `channel.isFavorite`, `ch.lastFetched`, `result.url`
   selectors untouched. Negatives (real config, through checker and
   reader): `_owners.library.channels = _sortedChannels(channels)` turned
   into a bare `channels = …` binding the local; the `_sortedChannels`
   parameter replaced by `_owners.library.channels`; the
   `_createSourceResolver` snapshot replaced by a live
   `_owners.settings.debridProvider` read inside the closure (it must stay
   the creation-time local); a bare record-member reference in a section.
   The behavioural proxies that can run on R are in Step 0.5.
5. **Receivers and composition.** Sections follow the Debrify TV shape:
   `final StremioTvDependencies _deps;` with `_owners`/`_sections` getters;
   cross-section calls are `_sections.<key>.<member>`; `StremioTvSections`
   builds every section in a fixed order; constructors only store `_deps`.
   Statics: `_extractQuality` → `StremioTvStreamQuality.extractQuality`
   (registered rename).
6. **Callback identity** (the Debrify TV mechanism, receiver path + member,
   with wrapper, receiver-swap, member-swap and cached-field negatives) for:
   the tab-9 handler (register = unregister object); the
   `watchStremioTvChannel` closure body; the search-controller listener
   body; the tuner's seven tear-offs (`rotationFor` →
   `_sections.library.rotationFor`, `onOpenDetail` →
   `_sections.actions.openChannelDetail`, `onPlay` →
   `_sections.play.playChannel`, `onToggleFavorite`, `onShowGuide`,
   `onEditLocal`, `onExportLocal` → `_sections.actions.*`) and five closures
   (`ensureLoaded`, `displayProgress`, `onFocusSidebar`, `onFocusHeader`,
   `onFocusedIndexChanged`); the search field `onKeyEvent:
   _handleSearchBarBack` tear-off (→ `_sections.navigation`); the menu
   `onPressed: _openStremioTvSettings` and the seven submenu `onPressed`
   tear-offs (→ `_sections.settings` / `_sections.menuActions`); the
   picker's `validateDirectUrl: _isValidStreamUrl` (→ `_sections.streams`);
   the overlay `onCancel` closure body; the detail screen's `onPlay`/
   `onBrowse` closures; each provider factory **call** at both pushes (a
   factory call, not a cached closure).
7. **Verbatim comments.** Never reword, move or drop a comment, including
   the misplaced `_tryDirectStreams` doc (Found-not-fixed 7), the banners
   (`// ====…`, `// ─── … ───`), trailing field comments and the
   `// Hidden for the alpha (kMdblistEnabled)` note.
8. **Shape.** The file is in `kShapeResidue` at 0 with **13 `app.shape.br`
   tokens** (build 3, `_headerButton` 1, skeleton 5, picker sheet 1, tab 1,
   item 2). Step 0 re-counts and verifies the 488-token floor (zero slack)
   and whether the `const BorderRadius.vertical(top: Radius.circular(20))`
   (3540) counts as a bare radius under the test regex. From the first
   step that moves a token: every destination that receives a token goes in
   `kShapeResidue` with its residue (layout, chrome, picker sheet, picker
   controls); every other destination in `kExtractedShapeResidue` at 0; the
   facade moves to `kExtractedShapeResidue` in the commit that removes its
   last token. At every checkpoint the slice holds 13 tokens with the same
   bare-radius count and the floor test passes.
9. **Theme.** `theme_surface_manifest.txt:23` (`p2_stremio_tv =
   lib/screens/stremio_tv/*.dart`) gains explicit patterns for this split
   only: `lib/features/stremio_tv/presentation/legacy_stremio_tv/*.dart`,
   `lib/features/stremio_tv/presentation/stremio_tv_manual_source_picker.dart`,
   `lib/features/stremio_tv/presentation/stremio_tv_source_picker_controls.dart`,
   `lib/features/stremio_tv/application/stremio_tv_stream_quality.dart`,
   `lib/features/stremio_tv/models/stremio_tv_playback_records.dart` (never
   `presentation/*.dart`, which would pull in the catalog picker). Step 0
   measures the surface's site count; it must stay equal at every step.
   `theme_rendered_set.py` keeps its root. `light_ink_inventory.py`:
   verify no change.

## Steps

| # | Work | Contracts |
| --- | --- | --- |
| 0 | Baseline `base`; (a) format-only commit R with proofs; strict and rename probes; dependency report; manifest, config, ledger, contracts module; harness, characterization tests, reader, media-server source-test switch, macOS goldens (two reversed-order captures); checkpoint (b); CI list; Linux capture script | Nothing moves |
| 0b | Independent review; original-only behavioural mutation proofs; guard mutants on simulated moved source; compiling-composition probe with the real checker and facade measurement; `base2` at (b) | Nothing moves |
| L | **Prerequisite before step 2:** supplied Linux originals hash-verified, committed separately, Linux golden test strict | Goldens |
| 1 | Guard registration (bridge, file set, size-exception placeholders, bans); models; application static; picker sheet and controls (typedefs, forwarders per D4); shape/theme registrations begin | Surface, 3.8 |
| 2 | Owners: 40 fields → 4 records, eager; bindings (incl. `isTelevision`); composition with its first consumer (the lifecycle); lifecycle verbatim with receivers; field-binding guard live; temporary facade ratchet raise recorded | 1, 2, 4 |
| 3 | Settings loader, channel library, menu actions, navigation, chrome | 2, 4, 5, 6 |
| 4 | Stream selection, debrid and cloud resolvers, channel resolve, player guide | 3.4–3.8 |
| 5 | `_playChannel` (D3), channel actions. **Full-suite gate 1** | 3 (all), 5, 8 |
| 6 | Layout (`build`, D2) with the forwarder; the facade keeps only lifecycle, forwarder and composition; facade leaves `kShapeResidue` | 6, 7 |
| 7 | Composition final; `STREMIO_TV_COMPLETE`, facade registration, cap and `TEMP`; real-checker negatives; CI format/analyze paths; final evidence. **Full-suite gate 2** | All |

### Step 0

1. **Baselines.** `stremio_tv/base` on the untouched worktree head:
   `suite_evidence.py run stremio_tv/base --no-pub --concurrency=<n>` plus
   the whole-repo analyzer, with tree and SDK provenance. Then commit (a)
   (Technique 1) and record `base-fmt` (analyzer only; the suite need not
   rerun for a formatter-only change unless an identity changes).
2. **Dependency report** (`docs/refactoring/stremio-tv-deps.md`). For every
   leaf (40 fields, the getter, the static, every method, the nine top-level
   declarations outside the retained widget/State, comment fragments and
   banners) it records the destination; reads of `context` (State or
   lexical), `mounted`, `setState`, `widget.isTelevision`; every field
   read/write with its record and new name and every same-named parameter or
   local in the destination method (Technique 4); tear-offs and closures
   handed outside the State; delay/timeout owners; and a per-entry
   wiring-checklist entry, reviewed before any scaffold is pinned. It copies
   the facts inventory tables (handoff args, cancellation occurrences,
   hooks, readers, Found-not-fixed).
3. **Checker.** `dev/tool/stremio_tv_manifest.tsv` (LF only),
   `stremio_tv_checker_config.json` (`baseline` R, `source`
   `lib/screens/stremio_tv/stremio_tv_screen.dart`, `feature`
   `lib/features/stremio_tv`, `engine` `sections`, `context_guard` true,
   receivers `_deps`, `_owners`, `_sections`, `live_getter_callbacks`
   `context`/`mounted`, `live_widget_getters` `isTelevision`,
   `spotlight_state_field_bindings`, `occurrence_field_bindings`,
   `scaffolds` (bindings, owners, sections), `callback_identities`,
   `lifecycle` for `initState`/`dispose`, an exact `build` forwarder pin,
   `type_renames` for the three data classes, `type_aliases` for the three
   widgets, `stremio_tv_contracts` (new opt-in module
   `dev/tool/stremio_tv_contracts.py`, the `debrify_tv_contracts`
   pattern), sidecars (scaffolding, handoff ledger, callback sites)),
   `stremio_tv_checker_test.py` with **real-config** fixtures and
   `self_test_module`. **Every shared-tool change is opt-in and keyed by
   this feature; every other manifest's adapter output and self-tests are
   byte-identical before and after.** Negatives (each must fail): a
   reordered or dropped `dispose` step; the tab-9 handler unregistered with
   a new closure; `watchStremioTvChannel` not nulled; a dropped or
   reordered `overlay.dismiss()`/`_notifyStartupPlayerLaunching()`/
   `_rememberPlaybackCursor` before P1 or P2; any ledger argument changed,
   dropped, reordered or added at P1 or P2; a provider factory result cached
   in a field; `includeMediaServers: false` dropped or `engineTimeout`
   added/removed at either search; a removed `_playGeneration` check; the
   `onCancel` bump moved after the notify; the TorBox 3 s settle or a 10 s
   cleanup timeout changed; the 120 ms poll or 8000 ms cap changed; the
   `_createSourceResolver` snapshot made live; `_loadSettings` gaining a
   `setState`; a section built per build or per access; a reworded
   comment; a new `const`; plus the callback-identity, live-getter,
   context and field-binding negatives (Technique 3, 4, 6).
4. **Harness** (`test/support/stremio_tv_fixture.dart`, after the Debrify TV
   and catalog fixtures): mocked `SharedPreferences`; `ProfileRuntime` init
   and reset; `SecretVault.debugReset(deviceIdOverride:
   'stremio-tv-characterization')` and provider keys/enables set through the
   provider storages; **channels without network**: local catalogs seeded
   through `StremioCatalogStorage` (production storage; `discoverChannels`
   reads `getStremioTvLocalCatalogs`, local channels skip `loadChannelItems`)
   with explicit item lists, plus — where a lazy-load case needs it — one
   addon catalog channel served by a recording `MockClient` under
   `http.runWithClient` (step 0 confirms `StremioService` uses package-level
   `http`; otherwise the catalog `HttpOverrides` transport pattern in a
   Stremio-TV-owned support file); stream search through the same
   `MockClient` (a fixture Stremio addon's `stream/` endpoint and, if
   needed, a fixture engine installed with
   `LocalEngineStorage.instance.saveEngine` + `EngineRegistry.instance.reload()`,
   the Debrify TV precedent), so P1/P2 are **observable**; RD, TorBox,
   Premiumize and AllDebrid through the `MockClient` (PikPak is (O) only if
   `PikPakTvService`/`PikPakApiService` resolve through package `http` under
   the fixture, else (S) with the reason recorded); `StreamUrlValidator`
   HEAD through the `MockClient`; a Clipboard mock; `MainPageBridge` probes
   (`hideAutoLaunchOverlay`, `focusTvSidebar`, content-focus request,
   `watchStremioTvChannel`, the auto-play stash) reset in teardown;
   `StremioTvStorage` settings seeded **before** mount (`autoRefresh: false`
   in every case that does not test it, so the tuner's 15 s tick never runs;
   cases that need it advance fake time explicitly); pinned `tester.view`
   size and DPR; `AppThemeScope` with a pinned look. **The player-route
   interceptor:** a `NavigatorObserver` records each pushed route, extracts
   the `VideoPlayerScreen` from `videoPlayerRoute`'s builder (unwrapping
   `LegacyThemeBoundary` → `Builder`) with a live element as context, and
   removes the route before the next frame, so the player never mounts and
   `await VideoPlayerLauncher.push` resumes. Reuse
   `test/support/debrify_tv_handoff.dart`'s typed field accessor for
   `VideoPlayerScreen` (import, don't copy). `stremioTvRotationMinutes`,
   `stremioTvSeriesRotationMinutes` and `stremioTvMixSalt` are consumed only
   by the native payload builder, not by `VideoPlayerScreen`, and the
   native bridge returns before its method-channel call on non-Android hosts
   (`android_tv_player_bridge.dart:1866`; TV overrides do not change
   `Platform.isAndroid`). They are therefore **(S)**: pinned by the ledger and
   contracts module only. Rotation and mix-salt behaviour stays (O) through
   the guide/next provider results. Prove the interceptor on R first (one fixture).
   **No `pumpAndSettle`**: delays (3 s settle, 120 ms poll, 200 ms
   `AnimatedSize`) use fake time; IO runs inside `runAsync`. **Time:** the
   rotation reads `DateTime.now()` (not faked by `fake_async`), so
   behavioural cases use one-item channels (deterministic now-playing) and
   never assert time-derived text or progress; golden scenes follow Step
   0.6. January UTC dates; braces in tests.
5. **Characterization tests**, under
   `test/features/stremio_tv/presentation/legacy_stremio_tv/`, written
   against R and **frozen in (b)**; each passes in a detached worktree of
   (b) before any extraction. Every case names its evidence class: **(R)**
   rendered, **(O)** observable reads/writes (MockClient requests in order,
   prefs, clipboard, bridge probes, captured player arguments), **(S)**
   source/checker evidence. Negatives ("does not push", "no request after
   cancel") use **held** responses released after the trigger.

   | Contract | Coverage |
   | --- | --- |
   | C1 Lifecycle | After mount: screen view logged (O if observable, else S), `watchStremioTvChannel` set, the content-focus request focuses the search button (R/O), the search listener filters channels (R); after unmount: `watchStremioTvChannel` null and the tab-9 handler removed (O through the bridge's request path), focus/controller disposal (S); `initState`/`dispose` bodies and the forwarder (S). |
   | C2 Hooks | `HomeHeroShellBridge` path with the screen unmounted stores the id; mounting plays that channel after discovery (O: overlay shown, search request issued); unknown id while startup auto-play is active → `notifyAutoLaunchFailed('Startup channel not found')` (O via `hideAutoLaunchOverlay` probe); while mounted the call goes through `watchStremioTvChannel` (O). |
   | C3 Playback handoff P2 (RD) | One-item movie channel + RD `MockClient`: tune in from the tuner → loader shown (R) → search request (O) → add/info/unrestrict requests in order (O) → loader dismissed **before** the push (O: observer order) → captured `VideoPlayerScreen` fields equal the P2 ledger entry field by field, with unlisted parameters at their defaults (O) → invoking the captured `resolveStremioSource` resolves through the **creation-time** provider even after the provider menu changes it (O) → invoking the captured `stremioTvNextProvider(channelId)` advances one slot and returns the map with every key (O) → `stremioTvChannelSwitchProvider` for a second channel returns its map (O) → `stremioTvGuideDataProvider([ids])` returns now/next for loaded channels **and loads an initially unloaded addon channel through its catalog request** (O). |
   | C3 Next and cursor | (a) Next whose resolve fails: returns null, logs, and records the failed slot; a second explicit Next asks for the **following** slot (O: slot boundaries in the returned/requested data, since one-item titles are identical). (b) Cursor reset by P2: advance through captured Next (offset 2 recorded), retune the **same** channel through P2 within the same base slot, then Next returns slot 1 again, not slot 3 (O: returned slot boundaries). |
   | C3 startup flag | Startup auto-play (pending id) → P2 launch; afterwards `watchStremioTvChannel('unknown-id')` plays the first channel via `orElse` (O), proving `_notifyStartupPlayerLaunching` cleared the startup flag (with the flag left set it would report 'Startup channel not found' instead). |
   | C3 P1 (manual picker) | Every auto candidate fails (RD returns no links, direct HEAD invalid) → picker sheet shown with All/Direct/Torrent counts (R) → selecting a source resolves and validates, pops the choice → push with `result.url`/`result.sourceIndex` (O, ledger P1) and `notifyAutoLaunchFailed` already fired once (O). A failed pick marks the item failed and stays open (R). |
   | C3 provider paths | TorBox (cache filter then create/info/link and `finally` delete of a rejected torrent), Premiumize (cache filter then direct download), AllDebrid (not-ready → delete magnet → next; ready → unlock), auto mode ladder order with the RD blocked-torrent skip (O: request order). Series: random-episode resolve and the episode filter dropping a confidently different single episode (O). |
   | C3 cancel | Cancel on the loader while the RD `unrestrictLink` is held: after release, **no push** (O) and `'Playback canceled'` reported (O). Cancel while the TorBox cache check is held (no generation check there, as-is): the cache request completes, then the next generation-checked step stops (O: request sequence; no push). A second `playChannel` while the first is held: the first stops at its next generation check (O). |
   | C4 Settings | Provider menu lists only available providers with Auto label "Auto (<first>)" (R); selecting persists and rebuilds (O/R); a stored provider that is no longer available is reset to auto on load (O: prefs); `_openStremioTvSettings` reloads settings (O). |
   | C5 Library | Discovery renders favourites first (R); favourite toggle persists, re-sorts and keeps focus on the toggled channel (R/O); refresh is single-flight (O: one discovery while refreshing); an addon channel that loads zero items is removed with focus rescued to its neighbour (R); a channel whose items land bumps only the tuner (S + R). |
   | C6 Menu and dialogs | Options menu items in order with Shuffle label `Mix n` advancing (R); Import submenu items, MDBList entry only when connected (R); filter page push returns `true` → refresh (O); local-catalog copy writes the JSON to the clipboard and snackbars (O/R); edit refocuses the edited channel (R). |
   | C7 Detail and guide | Detail opens `CatalogItemDetailScreen` with `isTelevision` and `enablePrimarySourcesHold: false` (O: route content); re-entrancy flag blocks a double open (O); still-loading channel waits on the 120 ms poll (O, fake time); guide sheet tap plays (O). |
   | C8 D-pad | Search button Left → sidebar probe, Right → menu, Down → tuner focus via the controller (R/O); search Escape ladder (clear, then close and refocus) (R); menu open by Select and closed by Escape with focus restored (R); submenu Left/Right returns to the Import item (R); provider menu Escape (R); picker: first item autofocus, Up → tabs, Escape pops (R). |
   | C9 Field binding (behavioural proxies) | After load: rotation observable through guide/next slot boundaries (O; the three native-only push args are S); **mix salt** on a dedicated **two-item** channel (the fixture first asserts the two salts select different items at the compared offsets), observed on three separate paths, each before and after Shuffle (`_mixSalt` 0 → 1) within the same base slot: **(i)** fresh launch metadata — the `stremioTvChannels` inline `nowPlaying` of a **new** P2 push after Shuffle (captured providers do not regenerate it); **(ii)** the guide data provider called before and after Shuffle; **(iii)** Next/channel-switch results compared **at the same cursor offset** — the cursor is reset (channel-switch, or a P2 retune of the same channel) before each compared Next call, the compared results' slot boundaries are asserted equal, then their item identities asserted different (O; successive Next calls alone advance the offset and can coincide, `A,B,A,B` vs `B,A,B,A`); preferred quality, torrents-first and max-start reach request order and `startAtPercent` (O); `hideNowPlaying` and `autoRefresh` reach the tuner (R/O). |

   **Mutation proofs** come in two kinds, recorded separately.
   - **Behavioural (ORIGINAL) proxies** (`original-mutations.json`):
     named, *compilable* mutations of R's application code, applied in the
     detached original and each rejected by an **assertion** (never a
     compile error, harness crash or reader rejection), with original/mutated
     hashes and logs; every new behavioural identity is covered by at least
     one. Required at minimum: P2 `stremioCurrentSourceIndex` replaced by
     `0`; P1 `videoUrl` replaced by the first source's URL; `title` without
     the `_currentPlayTitle ??`; `_createSourceResolver` reading
     `_debridProvider` live inside the closure; `_rememberPlaybackCursor`
     before P2 removed (rejected by the C3 cursor-reset case (b): Next then
     continues from the stale offset);
     `overlay.dismiss()` before P2 removed; `_notifyStartupPlayerLaunching()`
     removed (rejected by the C3 startup-flag case, not by a launching probe,
     since `LaunchRouter` itself calls `notifyPlayerLaunching`); **every** generation check removed together in the paths the
     cancel case exercises (each replaced by its not-cancelled value; a
     single removal masked by the remaining checks is a guard mutation, S);
     the `onCancel` bump removed; `includeMediaServers: false` flipped (the
     media-server test's regex and a request-observable proxy); the episode
     filter's `confidentMismatch` negated; the 480p torrent filter dropped;
     the TorBox `finally` delete skipped; three separate salt-to-zero
     mutants, each rejected by its own C9 path: the `_mixSalt` reads in
     `_buildGuideChannelMetadata` (path i), in `_createGuideDataProvider`
     (path ii), and in `_resolveChannelPlayback`'s `getSchedule` (path iii); favourite sort order inverted;
     `_loadSettings` dropping the `_maxStartPercent` read; the stale-provider
     reset skipped; the detail re-entrancy flag never set; the focus rescue
     targeting `idx + 1` first; `watchStremioTvChannel` not nulled in
     `dispose`; the tab-9 handler not registered.
   - **Checker/guard mutations (S)** over simulated moved source, for what no
     host test can observe: the tab-9 unregister with a new closure (the
     bridge keeps the old one silently); the `_searchController` listener
     body changes that render identically; the three native-only
     rotation/mix-salt push arguments (Step 0.4); single redundant generation checks;
     native-only arguments; `_loadSettings` field writes moved into
     `setState`. Each is rejected by the manifest checker, contracts module,
     binding guard or callback-identity checker, and classified **S**.
6. **Goldens** (macOS captured by execution in (b), Linux by Claude; strict
   from capture). **No scene renders the tuner**: its hidden-now-playing
   branch still paints `_liveBar()` with `np.progressText`
   (`stremio_tv_tuner.dart:1412`, `:1657`), derived from real-time slot
   bounds with no injection path, so loaded-wall pixels cannot be made
   deterministic without a seam. Tuner wiring is covered by the (R/O)
   behaviour cases; the tuner's own pixels belong to its sibling refactor.
   Scenes: **(1)** loading skeleton, TV 1920×1080 (discovery held); **(2)**
   header over the empty state (no channels), TV 1920×1080, providers RD and
   TorBox (provider chip visible), focus on the search button; **(3)** the
   same with the search field open and a typed term, phone 390×844; **(4)**
   empty state, desktop 1280×800, no providers; **(5)** options menu open
   with the Import submenu expanded (MDBList connected), over the empty
   state, TV; **(6)** the manual source picker sheet with one direct and two
   torrent sources, one marked failed, TV — captured as a **cropped region golden**:
   locate the sheet element by runtime type name `_ManualSourcePickerSheet`
   (its build returns a plain `Container`, so it owns no boundary), ascend to
   the nearest `RenderRepaintBoundary` (the modal route's layer, which
   excludes the tuner — asserted by checking the boundary's subtree has no
   `StremioTvTuner`), render that boundary's layer to an image and **crop
   it to the sheet's render box bounds transformed into the boundary's
   coordinates** before comparing (a test-side helper in
   `test/support/stremio_tv_goldens.dart`; no production wrapper). The
   crop helper has its own test (a known sub-rectangle of a synthetic
   boundary). Before each capture the test asserts its readiness markers
   (header rendered, intended focus owner, menu/sheet fully shown, no
   `StremioTvTuner` in the captured subtree). No network images. Fonts
   include JetBrainsMono; DPR 1.0; pinned theme; `en-US`; text scale 1.0;
   bounded fixed pumps. macOS originals are captured **twice in independent
   processes, the second in reversed scene order**, byte-identical before
   (b) is committed; the Linux script does the same; later replays are
   strict.
7. **CI list and pre-existing failures.** Add every new test and the golden
   test to `ci_behavior_tests.txt`. Add **only failures `base` actually
   observes** in newly listed files, by identity, in the same commit, under a
   dated `stremio_tv step 0` comment. A test passing in `base` must keep
   passing.
8. **Source-text inventory.**
   - **Reader** (`test/support/stremio_tv_source.dart` +
     `dev/tool/stremio_tv_source_reader.py`), the Debrify TV reader rules:
     ownership per declaration by **AST declaration presence** (destination
     declares it → owned there; else the retained facade declaration);
     duplicate and missing ownership rejected; scaffold files registered with
     pinned declarations; tests for ORIGINAL, partial, completed (simulated),
     scaffold-only, mixed file and each rejection. **Source selection
     (opt-in, shared by the CLI and the reader):** a config key
     `excluded_feature_files` lists the seven `STREMIO_TV_PREEXISTING`
     catalog-picker files, which are removed **before parsing** (the adapter
     cannot parse their multi-variable fields, `.variables.single`) and
     before ownership; every other file under `lib/features/stremio_tv/`
     must own a manifest declaration or be a registered scaffold, and any
     unexpected new file is rejected. Configs without the key behave
     byte-identically. **Validated forwarder:** `_StremioTvScreenState.build`
     is registered as an exact forwarder (`forwarders` with its pinned token
     text `@override Widget build(BuildContext context) =>
     _sections.layout.build(context);`); the reader treats the facade
     declaration as the validated forwarder and `StremioTvLayout.build` as the
     implementation owner (no duplicate-ownership error), `plain_sections`
     registers `StremioTvLayout`, and the addon-hub token rule removes only
     the moved method's `@override` while the facade keeps its annotation.
     Fixtures: the original `build` body still in the facade with no
     forwarder (steps 0–5 shape), forwarder plus moved body (step 6 shape), a forwarder with any
     extra token, a moved body still annotated, and the body in both places
     each rejected. **Annotation occurrence exception:** the occurrence guard
     runs before normalization and counts the `override` identifier of the
     removed `@override` (scratch probe: 545 vs 544 occurrences), so the
     binder gains a third opt-in, declaration-specific exception
     (`forwarded_annotation_occurrences: {"_StremioTvScreenState.build":
     ["override"]}`): exactly one leading `@override` annotation occurrence
     of that declaration may be absent in the destination, and only while
     the registered validated forwarder is present in the facade. Positives
     (checker and reader): retained build with annotation (steps 0–5), moved
     build without it plus the exact forwarder (step 6). Negatives: moved
     build without annotation but no forwarder; an extra annotation removed
     elsewhere in the body; the exception used for another declaration;
     forwarder text changed. Manifests without the key behave
     byte-identically. Completion enforcement uses this plan's final step
     **7**.
     `stremioTvOriginalSource()` returns raw ORIGINAL (R) text only after the
     checker proves every current declaration equals its original under the
     registered substitutions. **`stremioTvCurrentSource()`** returns the
     concatenated current text of the facade plus every file that owns a
     manifest declaration (deterministic manifest order).
   - `test/media_server_service_test.dart:1268–1270`: replace **only**
     `File('lib/screens/stremio_tv/stremio_tv_screen.dart').readAsStringSync()`
     with `stremioTvCurrentSource()`; the regex and the two expectations stay
     byte-identical. Negatives (simulated moves): a moved
     `searchByImdbWithStremio` call with `includeMediaServers: true`, a third
     call added in a feature file, or a call dropped each make the test fail.
   - `test/theme/source_guard_test.dart`: `StremioTvScreen` stays defined in
     the facade (line 130 unchanged). The `VideoPlayerScreen` allow-list is
     unaffected (this screen constructs none; the Contract 3.9 guard covers
     the feature). No assertion is deleted or weakened.
   - **CI history:** the `sources-behavior` job already has `fetch-depth: 0`
     (`checks.yml:69`, Debrify TV); verify, and prove the reader passes in a
     `--depth 1` clone only after `git fetch --unshallow`.
   - Shape and theme: Technique 8–9. `file_size_baseline.txt:15` follows
     Technique 1 and is lowered as the facade shrinks (removed below 800);
     the step-2 intermediate growth from receiver qualification is a
     recorded, hand-raised ratchet.
   - **Verify unaffected:** `test/profiles/profile_source_guard_test.dart`
     (its known failure stays known), `stale_runtime_guard_test.dart`,
     `test/theme/legacy_pins_test.dart`, storage checks.
   - `checks.yml` (step 7): add the facade and the new files to the format
     and analyze lists and `test/support/stremio_tv_*` to the format list.
     **Insert paths before `| tee`, never after it.**
9. **Linux capture script** (`dev/tool/capture_stremio_tv_linux_goldens.sh`):
   identical rules to the Debrify TV script (resolve (b) by exact subject
   and R by SHA or exact subject, require equal `lib`/`pubspec.yaml`/
   `pubspec.lock` objects, two independent passes — scene order and reversed
   — with their own logs and SHA-256 lists that must be identical, a
   detached worktree of (b) using only (b)'s tests, strict verification,
   evidence under `refactor-evidence/stremio_tv/`; no `head`/`awk exit` in
   `pipefail` pipelines).
10. **Step 0 checks:** all 16 integrated manifests (vpl, settings, iptv,
    torbox, debrid, pikpak, playback_settings, iptv_settings,
    playlist_content, merged_detail, addon_hub, detail_showcase,
    spotlight_board, episodes_panel, catalog_detail, debrify_tv) with
    self-tests, each with its own config and baseline and an isolated
    parser package, plus this one against R; architecture, sizes, storage,
    shape, theme, light-ink, CI format, scoped analyzer with allowlist,
    staged diff. Commit the checkpoint with the exact subject.

**Step 0b review** (before any extraction): the Debrify TV procedure —
behavioural proxies against ORIGINAL (entire characterization files, named
assertion per mutation) recorded in `step0b-behavioural-proxies.json`; guard
mutants against simulated moved layouts (one per section kind: lifecycle,
the play flow with the overlay closure, a resolver with `finally` cleanup, a
provider factory, a paint builder with lexical contexts, a record with
hazard fields, the picker with typedefs) recorded in
`step0b-guard-mutants.json`; the compiling-composition probe (facade,
owners, bindings, composition, one stub section of each kind, the typedef'd
picker classes) under the strict config with no new warnings, through the
real manifest checker CLI with an isolated parser package and `--self-test`,
with the facade measured per span. Record `base2` at (b). Claude reviews the
step 0 commit **immediately** (in parallel with 0b), the probe before step 1.

### Step L — Linux originals

As Debrify TV: Claude runs the script in the calibrated
`debrify-flutter:3.44.8` linux/amd64 image (Colima, clone under `$HOME`,
`flutter pub get` inside the container) from a clone at (b), verifies `HEAD`
and hashes, hands over PNGs and evidence; execution verifies and commits them
separately with `linux-original-verification.json`. From then on the Linux
golden test is strict. No golden is ever generated or updated against moved
code.

### Per step and gates

The Debrify TV procedure with `--baseline <R>` and `--relocate
lib/screens/stremio_tv/stremio_tv_screen.dart=lib/features/stremio_tv/`
(these apply only to the Stremio TV checks). Every step runs: per-entry
wiring review before pinning; all 16 manifests plus this one with
self-tests and isolated parser packages; the field-binding and
callback-identity checks; the contracts module; the per-symbol relocation
comparison (zero additions beyond the probe inventory); architecture, sizes,
storage references; shape (13 tokens, floor ≥ 488) and theme (sites equal);
CI format and scoped analyze with allowlist; LF manifests; staged diff; all
characterization tests against the latest `stremio_tv/` base; strict macOS
and Linux goldens. Gates run serially on committed trees against the latest
base; gate 2 also compares against gate 1. A gate failure is investigated as
a possible extraction regression with original/current causal proofs before
any flaky acceptance; never `--record`/`--update` to accept a regression.

### Sibling coordination

Two sibling refactors run concurrently on `stremio_tv_tuner.dart` (feature
`stremio_tv_tuner`) and `stremio_tv_local_catalogs_dialog.dart` (feature
`stremio_tv_catalogs`). This branch never edits those files; the moved code
keeps importing `StremioTvTuner`/`StremioTvTunerController`,
`StremioTvLocalCatalogsDialog`, `StremioTvLocalCatalogEditorDialog` and
`LocalCatalogExporter` **from their original paths** (their facades keep
those public names), so either merge order compiles. This screen's goldens do
not render the tuner, but the behaviour cases drive it and the local-catalog
dialogs: the siblings are move-only, so every characterization test and
golden must still pass after integration (a failure is a sibling regression
to report, never a test or golden update). Shared registration files they may also edit:
`check_search_architecture.py`, `theme_surface_manifest.txt` (the
`p2_stremio_tv` line), `shape_manifest_test.dart` (the
`lib/screens/stremio_tv/…` entries), `file_size_baseline.txt`,
`ci_behavior_tests.txt`, `analyzer_allowlist.txt`, `checks.yml` and the
shared checker tools. Keep every edit additive and keyed by this feature.

### Integration (Claude)

Claude merges the branch and integrates shared files **semantically, by
union** (the Debrify TV list plus `stremio_tv_contracts.py` and the reader
helpers): registrations, exceptions, CI paths (before `| tee`), known
failures, theme patterns (one `p2_stremio_tv` line holding every sibling's
patterns), shape entries; keep every `*_COMPLETE = True`; take the lowest
verified size ceiling; review checker extensions as shared-tool changes
(opt-in only; every other manifest's self-tests unchanged). Then, on the
merged committed tree, rerun every manifest with self-tests, architecture,
size, shape and theme, CI format and analyze, the goldens, and a full-suite
comparison reconciling identities against each branch's bases.

## Definition of done

1. **Facade.** Formatted, within its measured cap (target and maximum 300,
   every physical line counted), breakdown recorded. It holds
   `StremioTvScreen` byte-identical and `_StremioTvScreenState` with the
   eager owners, the cached composition, the verbatim lifecycle and the
   exact `build` forwarder. `lib/main.dart` compiles unchanged.
2. **Guard.** Bridge, file set, size exception(s), facade in `main()` and
   `COMPOSITION_ROOTS`, cap, `TEMP(stremio_tv)` and the import/playback
   bans, each proven through the real checker. Every other new destination
   is at most 500 lines; the existing catalog-picker files are unaffected.
3. **Tests.** All manifests pass with self-tests. Every characterization test
   and source guard from (b) passes unchanged; the media-server source test
   keeps both original expectations. macOS and Linux goldens match the
   originals.
4. **Diagnostics.** No new warning or suppression; surviving original
   warnings allowlisted by destination identity; every info maps to an
   original or probe-inventoried identity; removed identities listed.
5. **CI.** Local CI-equivalent checks pass; behaviour list holds the new
   tests; known failures gain only observed identities; shape slice 13
   tokens with the floor met and the facade at 0; theme sites unchanged.
6. **Progress** records R, (b) and each step's commit, ownership, exceptions
   with exits, cap arithmetic, and the **End-of-series device checklist**
   below. Remote CI stays pending.
7. **Gate 2** passes against the latest base and gate 1. Then stop and
   report.

## End-of-series device checklist (not a merge gate)

- Android TV: tune a channel for each provider (RD, TorBox, PikPak,
  Premiumize, AllDebrid, Auto) through the native player; in-player guide,
  channel switch and Next (slot advance) on the native player.
- Flutter player (phone/desktop): the same handoff, plus the manual source
  picker after an all-fail.
- Remote D-pad: header (search, menu, Import submenu, provider menu),
  search Back ladder, sidebar exit, tuner ↔ header focus after long surfing,
  favourite toggle focus restore.
- Home → Stremio TV saved-channel auto-play (mounted and unmounted).
- Loader Cancel during each stage.

## Explicitly not in scope

`video_player_screen.dart`, `lib/screens/video_player/`,
`VideoPlayerLauncher`, `lib/features/player_launch/`, `MainPageBridge`,
`StremioTvService`, `StremioTvDebridFallback`, `PipelineLoadingOverlay`, the
tuner/local-catalog/guide/filter/settings widgets, the existing
`lib/features/stremio_tv/` catalog-picker files, every Android/Kotlin/Java
and tvOS file; `lib/main.dart`; Riverpod, data contracts, localization;
behaviour fixes, guards and dead-code removal (D5); the `build` and
`_playChannel` decompositions.

## Found, not fixed

All pre-existing; the extraction keeps each exactly.

1. `_discoverAndLoad` (from `_loadSettings().then`) calls `setState` without
   a `mounted` check, and both it and `_refresh` dispose and recreate row
   focus nodes after their awaits without a `mounted` check (double dispose
   if the screen unmounts mid-discovery).
2. `dispose` nulls `MainPageBridge.watchStremioTvChannel` whenever it is
   non-null; its comment says "only if we're the active handler", but the
   check is not identity-based.
3. The tuner controller and both `MenuController`s are never disposed (the
   latter have no API).
4. P1 (manual picker) does not re-check `_playGeneration` after the picker
   returns: a play superseded while the sheet was open can still push.
5. The TorBox/Premiumize cache-check awaits in `_playChannel` check only
   `mounted`, so a cancelled play still completes those requests.
6. `_resolveChannelPlayback` omits the 10 s `engineTimeout` that
   `_playChannel` passes.
7. `_tryDirectStreams`'s doc comment describes stream sorting (misplaced).
8. `_loadSettings` writes state without `setState`; the rebuild comes from
   its callers.
9. No profile capture: favourite writes, provider saves and local-catalog
   edits are `mounted`-only across awaits.
10. Strings are unlocalized; icon-only header buttons have no `Semantics`
    labels.

## Round 1 review resolution

Codex design review round 1 (`~/.codex-runs/stv-design/last.txt`, at
`cd6443dd`); each point re-checked against source before revising.

1. **P1 manifest scope** — `excluded_feature_files` (opt-in, CLI and reader)
   drops the seven pre-existing catalog-picker files before parsing; the
   architecture rule caps **every** other `lib/features/stremio_tv/` file
   (`STREMIO_TV_PREEXISTING` replaces the exact new-file set), with a
   501-line unregistered-file negative.
2. **P1 binder reuse** — two authorized opt-in extensions (config-driven
   owner/record paths with `mandatory_qualification` implemented;
   live-widget-getter alignment), with positives for all three
   `isTelevision` sites and cached/wrong-receiver/bare-field negatives through
   checker and reader; Debrify TV byte-identical.
3. **P1 reader vs forwarder** — registered validated forwarder,
   `plain_sections`, the addon-hub `@override` token rule, step-5/step-6
   fixtures and rejections; completion at step 7.
4. **P1 golden determinism** — no scene renders the tuner (its `_liveBar`
   prints real-time `progressText`); loaded scenes sit over the empty state,
   and the picker is a region golden of its own repaint boundary with a
   no-tuner assertion.
5. **P1 surviving mutations** — new C3 cursor-reset case (Next, retune the
   same channel through P2 in the same base slot, Next returns slot 1) and
   a startup-flag case (`orElse` play vs 'Startup channel not found')
   reject the two mutations.
6. **P2 native-only args** — the three rotation/mix arguments are (S);
   rotation behaviour stays (O) through provider results.
7. **P2 factory branches** — failed Next followed by another Next, and
   guide loading of an unloaded addon channel, added to C3.
8. **P3** — format commit raises the size baseline (3,958); layout estimate
   about 700 (682 measured qualified); nine top-level declarations; step 7
   completion.

## Round 2 review resolution

1. **P1 `@override` occurrence** — third opt-in binder exception
   `forwarded_annotation_occurrences` tied to the validated forwarder, with
   retained/moved positives and four negatives through checker and reader.
2. **P2 mix salt** — dedicated two-item channel for C9 with a precondition
   that the two salts select different items; the salt-to-zero mutation is
   rejected there.
3. **P2 picker golden** — cropped region golden from the modal route's
   repaint boundary to the sheet's bounds via a tested test-side helper.
4. **P3** — stale tuner-golden and "this file only" wording updated.

## Round 3 review resolution

Round 3: "No P1s — executable". Both P2s resolved: C9 observes salt on
three paths (fresh launch metadata, guide provider, Next/switch at a reset
cursor offset with equal slot boundaries) with three separate salt-to-zero
mutants.

## Progress

### Step 0 — original-code characterization (2026-10-06)

Execution is limited to step 0 on `refactor/stremio-tv`. No extraction,
production seam, sibling-widget/player/launcher/service edit, device run,
push, merge or branch switch. Step 0b and all construction/extraction work
remain for Claude's review. Found-not-fixed entries above remain unchanged.

Evidence root **E** is the absolute Git-common-dir path
`/Users/varunbsalian/Documents/Projects/debrify/.git/refactor-evidence/stremio_tv/`.
All run logs, JSON provenance, mutation results and repeatability proofs
below are under E, outside the committed tree.

- **Execution base:** `e1ea293faebf44f3842b61a2a7d9e322fa113762`.
  Flutter 3.44.8 (`058e0af2c2`), Dart 3.12.2, macOS; dependency resolution
  leaves `pubspec.lock` unchanged. `python3 dev/tool/suite_evidence.py run
  stremio_tv/base --no-pub --concurrency=4` observes **11,654 passes,
  13 failures, 28 errors, 20 skips, 1,138 suites**. `base.jsonl`,
  `base.env.json`, `base-summary.json` record every identity and SDK/tree
  provenance; the tested tree was stable. Historical failure identities
  agree with the observed run. No load-sensitive flake was allowlisted;
  no failure baseline was recorded or updated.
- **Format-only commit (a), R:**
  `c7a3d156d260e08421043a5430c6242124ba8e1b`, subject
  `style(stremio-tv): format the original Stremio TV screen`.
  Exactly the facade and its hand-raised size ratchet change (3,957 →
  **3,958** physical lines). `format-token-proof.json` and
  `format-proof.py` prove comments/literals/required commas unchanged,
  enumerate nine removed and five inserted AST-owned optional formatter
  commas, reject edited comments/literals/required singleton-record commas,
  and prove formatter idempotence.
- **Analyzer base-fmt:** raw `base-analyze.txt` has 1,689 diagnostics;
  `base-fmt-analyze.txt` has 1,698. The raw comparison fails on **nine
  duplicate occurrences of existing diagnostics outside this screen**:
  generated build/pubspec paths (2), patched-package removed lints (2),
  dock-metrics alpha infos (5). Fresh detached base/R worktrees with matching
  pub-get/generated state have **1,687 each**, exactly equal diagnostic
  identity counters (`base-control-analyze.txt`,
  `base-fmt-control-analyze.txt`, `base-fmt-control-compare.txt`,
  `base-fmt-diagnostics.json`). The facade's diagnostic identities are
  unchanged. This artifact difference is documented, not accepted with an
  allowance or source fix; no second whole-suite formatter run is needed.
- **Strict/rename probes:** detached R under the feature analysis config,
  imports qualified only. Original and typed receiver/rename/typedef probe
  each have **13 directive-ordering infos, zero warnings/errors**, no
  appeared/disappeared identities; maximum per identity is 13.
  The probe compiles in its one-test check. A separate original private
  picker/public-typedef probe has two infos and zero warnings/errors.
  `strict-inventory.json`, `strict-original.txt`,
  `strict-rename-probe.txt`, `strict-probe-compile.txt`,
  `strict-picker-probe-final.txt`, the three hashed probe sources and
  `strict-probe.py` preserve the evidence. These typed copies are not a
  split-construction proof: full composition and D4 activation remain 0b.
- **Inventory and pins:** `stremio-tv-deps.md` reviews **119 declaration
  leaves** (retained widget, 40 State fields, 69 State methods/getter/static,
  nine other top-level declarations), original scopes/read-write roles,
  same-name locals, destinations, callback lifetimes, delays/timeouts and
  the copied facts inventory. The LF-only manifest/config pin those leaves;
  the ledger pins all **19 ordered arguments at each P1/P2** and defaults
  of unlisted host parameters. The callback sidecar pins **259 outgoing
  callback expressions**; 35 free comment leaves retain assigned owners and
  total occurrences. The three native-only rotation/mix-salt push arguments
  remain S; guide/Next/metadata supply their separate O behavior coverage.
  Scaffolding is conditional and pinned; eager owners and once-per-State
  sections/live callbacks are future composition pins, not production code.
- **Authorized tooling opt-ins:** pre-parse `excluded_feature_files`
  (exactly the seven existing catalog-picker files); binder State owners and
  record paths; implemented `mandatory_qualification`; `live_widget_getters`
  alignment; declaration-specific `forwarded_annotation_occurrences`; exact
  explicitly pinned build-forwarder tokens and reader ownership validation;
  feature contracts/callbacks. Other configurations retain their defaults.
  The forwarder negative discovered that ordinary formatter-token comparison
  permits an optional comma: the explicit-text opt-in now compares every raw
  token, and rejects that comma too. A picker own-State negative also exposed
  screen-callback normalization there: the feature-only contracts now reject
  dependency receivers in the six picker widget/State declarations. The other
  16 configs have no explicit forwarder-text pin, and do not run these feature
  contracts. The adapter itself is unchanged.
- **Checker/reader verification:** ORIGINAL, excluded pre-existing
  multi-variable fields, scaffold-only, partial records/methods, mixed
  ownership, step-6 exact forwarder and simulated completed-step-7 positives;
  negatives pin every P1/P2 argument/value/drop/adjacent ordering/addition,
  lifecycle/callback order, timeouts/generations, snapshots, bare/misbound
  fields, live getters, lexical context, caching/composition, annotation
  exception limits, ownership, comments and premature completion.
  Moved media-server true/extra/dropped calls also fail the unchanged
  source-test predicates independently of reader rejection. The original
  has unused nested builder-context formals; fixtures preserve those exact
  bindings and exercise real lexical build-context reads, while shared
  context fixtures cover used builder reads. Syntax layouts here are not
  claimed to compile; the compiling composition is reserved for 0b.
  `step0-final-manifest-stremio_tv.txt` enumerates the real-config results.
- **Compatibility:** all **16 existing manifests plus Stremio TV** pass
  their real CLI/self-tests against their own config/baseline with explicit,
  isolated `--parser-package` copies and all `*.dill` deleted before each run.
  `step0-before-manifests.json`, `step0-after-manifests.json`,
  `step0-final-manifest-stremio_tv.json` and
  `manifest-compatibility.json` preserve commands and byte-for-byte equality
  of every other manifest's self-test output. `adapter-before.json`,
  `adapter-after.json`, `adapter-compatibility.json` prove all 16 raw adapter
  inputs and outputs byte-identical too. Reproduction scripts are stored in E.
- **Harness and characterization:** ten new test files, **48 cases**:
  **37 R/O behavioral cases, four S source cases, one crop-helper case,
  six goldens**, covering C1–C9 including all Round 1–3 additions.
  Test-owned profiles/preferences/storage, recording MockClient transports,
  held responses, Clipboard/bridge probes, fonts/theme/DPR/locale and bounded
  pumps reach original production callers. The route observer unwraps the
  theme boundary with a live context, captures the player fields with the
  existing typed accessor, removes the route before the player mounts, and
  lets the launch await finish. No application seam or `pumpAndSettle`.
  The committed-profile real media-server request proxy is in its own test
  file/VM to avoid legacy profile-service cache contamination between cases;
  initial combined-fixture readiness failures were corrected in test setup,
  with application behavior unchanged. PikPak is observable via MockClient.
- **Original behavioral mutations:** `original-mutations.json` and
  `original-mutations-coverage.json` record **43/43 assertion rejections**,
  covering **all 37 behavioral identities**, with commands, original/mutated
  hashes, assertion names and individual JSON logs. Mutations run only in
  detached R, whose source is restored afterward. Required P1/P2, provider
  snapshot, cursor reset, startup flag, overlay, combined generation/cancel,
  real media request, episode/480p filters, TorBox cleanup, three independent
  salt paths, favorites, max-start, stale provider, detail/focus and hook/tab
  mutations are all proved. Test hashes match the frozen checkpoint files.
  This is step-0 original-code evidence; **no step0b proxy/guard review or
  composition probe has begun**.
- **macOS goldens:** all six tuner-free scenes captured in independent
  processes, second order reversed: **all PNG bytes identical**.
  `macos-original-first/`, both SHA-256 lists,
  `macos-original-repeatability.json`,
  `macos-original-capture-reverse.txt`, and
  `mac-goldens-strict-readiness.txt` preserve capture and strict-replay proof.
  The picker capture uses the nearest modal repaint boundary, asserts no
  tuner in its subtree, transforms and crops to the sheet's own bounds; its
  independent known-subrectangle test passes. No tuner pixel seam is added.
- **Final Step 0 replay:** `suite_evidence.py run
  stremio_tv/step0-characterization` with the new directory, media-server,
  profile-source/stale-runtime and theme pins/shape/source tests,
  `--no-pub --concurrency=1`: **163 pass, one baseline-known profile source
  failure**, including all 48 new cases passing. Comparison against observed
  `base` passes: no new failure, missing identity or new skip; tree stable
  (`step0-characterization.{jsonl,env.json}` and
  `step0-characterization-compare.txt`). Suite-evidence runs were serialized.
  The frozen checkpoint is also replayed in its detached worktree:
  `checkpoint-replay.{jsonl,env.json}`, `checkpoint-replay-compare.txt`.
  `checkpoint-proof.json` pins the actual checkpoint SHA, frozen tree and
  **equal `lib`, `pubspec.yaml`, `pubspec.lock` objects with R**.
  The shallow-clone reader proof fails for missing R at depth 1, then passes
  after `git fetch --unshallow` (`shallow-reader-proof.json` and logs).
- **Other Step 0 checks:** architecture **1,448 files**; sizes **2,454
  files/154 existing ratchets** (five unrelated baseline files were already
  smaller, no `--update`); storage keys **300 pairs/14 retired**,
  reference self-tests, member map **1,081 rows**, bodies **1,036/44 retired**
  with exact reset ordering. Shape remains **488 globally/13 in the facade,
  zero bare radii**; residue/theme manifests unchanged. Theme audit remains
  30 sites; light-ink three non-primary sites, zero primary. Exact CI format
  command: **1,964 files, zero changes**; scoped CI analyzer/allowlist:
  **25 pre-existing warnings, nothing new**; new tests/support analyze with
  no issues. Final syntax, local documentation-link, staged diff and scope
  checks pass. `step0-*.txt`, `step0-shape-theme-proof.json`,
  `step0-inputs.json` and `step0-final-review.json` preserve results.
- **CI/capture delivery:** all ten new files are listed in
  `ci_behavior_tests.txt`; failure/analyzer allowlists unchanged.
  Format/analyze add the original facade and test support; analyze paths
  precede `| tee`; existing behavior checkout has `fetch-depth: 0`.
  `capture_stremio_tv_linux_goldens.sh` passes shell syntax validation and
  requires calibrated Linux/SDK, the exact checkpoint subject and R,
  equal application/dependency objects, detached checkpoint tests, independent
  first/reversed captures, byte equality and strict verification.
  **Linux execution/capture remains pending with Claude**, as planned.
- **Checkpoint (b):** exact subject
  `test(stremio-tv): step 0 original-code characterization checkpoint`;
  resolved SHA and equality/replay proof are in `checkpoint-proof.json`.
  Committed files are tests, support, six macOS PNGs, inventory/checker/reader,
  opt-in tooling, Linux script, CI wiring and this progress/dependency report.
  Application source and dependencies equal R. Stop here for Claude's
  Step 0 review; step 0b and steps 1–7 remain unstarted.


### Step 0b — ORIGINAL review closure (2026-10-06)

Parent **(b) = `587ea94dfeb1eed38b39061e7a5dc00748deab55`**; R remains
`c7a3d156d260e08421043a5430c6242124ba8e1b`. The exact review checkpoint
subject is `test(stremio-tv): step 0b review closure checkpoint`. Its resolved
SHA and application/dependency object equality are recorded in
`step0b-checkpoint-provenance.json`. All evidence stays under the common Git
directory's `refactor-evidence/stremio_tv/`; application code has not moved.

Claude's independent run found 17 surviving mutations among 29 compilable
mutations. Step 0's targeted mutation runs are historical evidence, not
sufficient Step 0b whole-file evidence. Fifteen new ORIGINAL cases cover
series P1 title/non-null start, a second valid direct candidate, TorBox and
Premiumize cache stages plus RD's absent stage, series Next/switch map fields,
the captured direct resolver, RD largest selected video, AllDebrid episode
mismatch deletion, rejected PikPak prepared-root trash, favorite focus restoration, empty-library editor fallback,
genre-only filtering, Escape refocus and stored disabled filters. The complete
characterization set has **63 cases: 52 behavioral, four source guards, one
crop test and six unchanged strict macOS golden scenes**. Whole-file ORIGINAL
runs and named assertions are the acceptance criteria for every behavioral
mutation; compile/fixture failures are rejected as proof.

The focus cases hold the original asynchronous preference boundary and move
focus to a competing node before the post-frame callback. The genre case uses
the existing public mutable `allChannels` list and a valid public channel model
with genre independent of its display name (production factories normally
repeat the genre in the name). It asserts the matching channel remains visible
before accessing the tuner. The initial genre mutant's fixture lookup failure
is rejected as proof. No production seam or sibling widget edit is introduced.

**`autoLabel` is proposed S, pending Claude's agreement:** R's only call to
`_providerFullLabel` is the provider-menu build inside
`_availableProviders.isNotEmpty`; therefore its empty-provider `return 'Auto'`
branch has no UI-observable boundary. Its exact mutation remains guarded in
the simulated moved layout and reader. No seam is added to expose it.

The owned detached composition probe maps **all 119 manifest leaves** into
the facade/owners/sections/models/private widgets; it compiles the unchanged
`main.dart` entrypoint. Strict analysis has **zero warnings/errors and seven
infos**, inventoried by original member/rule/message in
`step0b-analyzer-inventory.json`. Mandatory receiver qualification wraps seven
one-line statements; their braces are not changed. D4 is activated by the
probe's seven new private optional-parameter warnings: exactly two typed
constructor forwarding functions are frozen in the feature-only scaffolding
sidecar. Private widget constructors and runtime types remain unchanged.
Two unused scaffold getters (`Chrome._sections`, `CloudResolvers._owners`)
are omitted from the pins and simulated layouts; no original leaf changes.

The formatted probe facade is **119 lines**: imports 7, widget 16, State
header/close 2, owners/composition 10, lifecycle 72, build 2, remaining
blanks/comments 10 (sum 119). The only probe file above 500 is layout at
**713** lines; play is below 500. Actual production creation caps remain
inactive until extraction. Sources, AST spans, hashes and the real checker CLI
command are in `step0b-compiling-sources/` and `step0b-composition-proof.json`.
Nineteen simulated mutants are rejected by both checker and reader: all seven
required section kinds, `autoLabel`, three composition mutations, two D4
forwarder mutations and the three native-only values at both P1/P2 (`step0b-guard-mutants.json`).

The Linux ORIGINAL capture script now selects this Step 0b checkpoint by its
exact subject, verifies application objects against R and retains the same
six original-only scenes. Two new characterization files are added to CI's
behavior list; no golden, allowlist or shared checker implementation changes.
The checkpoint records the completed test/probe work. Post-commit acceptance
covers Claude's unchanged 29 line mutations, whole-file replay of the original
43 proxies plus the RD cache control, real CLI/self-tests, all-manifest
compatibility and serialized full-suite `base2`; the accepted outcomes follow
below. **Stop before
Step 1** for Claude's probe review, S agreement and Linux-original handoff.


The first post-commit replay at `b3b7cd357` rejected 27/29 through named
assertions, but `pikTrashSkip` passed (despite its earlier reviewed kill).
That run is preserved under `step0b-initial-checkpoint-*` and
`step0b-initial-claude-*`. The added fifteenth case prepares a mismatched
PikPak episode and observes the exact root `files:batchTrash` payload and its
ordering before retry. It passes on ORIGINAL. The unpublished checkpoint is
amended to include it; all 29 line mutations are replayed again at the
resolved final checkpoint before accepting the result. The Linux script's
exact subject still resolves one checkpoint in the final branch history.


**Final post-commit acceptance (2026-10-06).** Review checkpoint **
`e1d4fe1f2b0462826de0a591ef7371a84200d85d`** supersedes the unpublished
`b3b7cd357` checkpoint. Both application and dependency objects still equal R;
`step0b-checkpoint-provenance.json` records the final tree and all test hashes.
The Progress completion is a separate documentation commit so the recorded
checkpoint and full-suite tree remain unchanged.

- **ORIGINAL characterization:** all **63/63** pass at the committed final
  checkpoint, including six strict unchanged macOS goldens. The two new files
  contain **15** cases and analyze with zero diagnostics. Evidence:
  `step0b-characterization.jsonl`, its stable-tree/SDK `.env.json`,
  `step0b-characterization-run.txt`, `step0b-new-cases-analyze-final.txt`.
- **Behavioral proxies:** Claude's exact script is copied and hash-pinned;
  only runner options change to explicit concurrency 4 and JSON reporting,
  with an outer `finally` restoration. Its dictionary, line edits and whole
  behavioral-file glob (goldens included, source guards/crop excluded) are
  unchanged. All **28 observable review mutations** fail their named
  behavioral assertions; `autoLabel` completes successfully and remains the
  **one S proposal pending Claude's required agreement**, with checker and
  reader rejection. The original **43** frozen mutations retain their exact
  mutation hashes, now run whole files with concurrency 1 and no name filter;
  all reject on their named assertions. The additional RD cache control also
  rejects. **73 merged definitions = 72 behavioral rejections + one guarded
  S proposal** in `original-mutations.json` and
  `step0b-behavioural-proxies.json`; `original-mutations-coverage.json` proves
  named assertion-failing coverage for all **52** behavioral cases. Compile
  errors, fixture failures and unrelated assertion failures never count.
  All mutators restore R, and the full replay follows the final commit.
  Original review inputs/raw logs, rejected initial replay, exact commands,
  test names, expectations, failure messages and raw runs are preserved.
- **Guards and probe:** all **19** simulated mutations reject through both
  checker and reader; their unmutated full layout passes. They cover all seven
  section kinds, the S proposal, three composition mutations, two D4 typed
  forwarders and both launch sites for the three native-only arguments.
  The real compiling-probe CLI at R with an isolated parser package and
  `--self-test` passes **8 positives, 185 checker negatives and 185 reader
  negatives**. Unchanged `main.dart` plus the full composition compiles.
  Facade **119**, play **495**, layout **713**; no other destination exceeds
  500. Strict warnings/errors remain zero, with seven inventoried infos.
  `step0b-guard-mutants.json`, `step0b-composition-proof.json`,
  `step0b-compiling-sources/` and `step0b-analyzer-inventory.json` contain the
  exact evidence. No production Dart file or dependency changes.
- **Compatibility and CI:** all **16 existing manifests plus Stremio TV**
  pass real CLI/self-tests with isolated parser packages and copied `*.dill`
  files deleted. All 16 existing stdout files are byte-identical to Step 0
  (`step0b-manifests.json`, `step0b-manifest-compatibility.json`). Shared
  checker/adapter and CI configuration inputs equal (b) byte-for-byte;
  `step0b-unchanged-inputs.json` validates reuse of the Step 0 raw adapter and
  unchanged CI analyzer/allowlist evidence. The exact expanded CI format
  command passes **1,966 files, zero changes**. Architecture, file sizes,
  storage keys/references, Stremio TV manifest/changed-file LF and diff checks,
  and Linux script syntax pass;
  `step0b-ci-paths.json` verifies the Stremio TV analyze path before `| tee`.
  No allowlist changes. Linux goldens remain with Claude, as planned.
- **Full-suite `base2`:** serialized after all owned AST jobs and mutation
  runs finish, at the final committed checkpoint, with `--no-pub
  --concurrency=4`, matching the observed base SDK/configuration. **11,717
  success, 13 failure, 28 error, 20 skipped, 1,150 suites**. Identity comparison
  against `base.jsonl` is **PASS: zero new failures, zero missing tests, zero
  newly skipped tests and exactly 63 passing additions**. Existing failing
  identities remain unchanged. Raw runner exit 1 reflects those observed
  baseline failures; the comparison is the acceptance verdict. No
  load-sensitive flake occurs and no isolated rerun/allowlisting is needed.
  Evidence: `base2.jsonl`, `base2.env.json`, `base2-run.txt`,
  `base2-compare.txt`, `step0b-base2-proof.json`.

**Stop at Step 0b.** Step 1 and production extraction remain unstarted.
Claude reviews the probe and the `autoLabel` S proposal, agrees the latter
before treating that classification as final, and hands over Linux originals
before extraction. Remote CI and device-only/native playback checks remain
pending. Material adjustments are the additional PikPak cleanup coverage,
D4's authorized constructor forwarders, omission of two unused scaffold
getters, and the documented public-model genre input; none changes production
behavior or introduces a production seam.
