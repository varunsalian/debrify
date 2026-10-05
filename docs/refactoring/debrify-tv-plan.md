# Debrify TV screen refactor — plan

Written 2026-10-05 on `refactor/codebase` at `47e7d385`. The target file is
unchanged since the dead-code sweep (`22678250`, `47e7d385`).
Follow [AGENTS.md](../../AGENTS.md).

Read first: [spotlight-board-plan.md](spotlight-board-plan.md) (closest
analogue: one giant State, timers, playback-adjacent, measured facade cap, and
the gate-1 renamed-field capture bug), then the Progress sections of
[catalog-detail-plan.md](catalog-detail-plan.md),
[episodes-panel-plan.md](episodes-panel-plan.md) and
[merged-detail-plan.md](merged-detail-plan.md). This plan reuses their
technique, checker (`check_verbatim_moves.py` → `check_settings_moves.py`),
callback-identity tooling, `suite_evidence.py` evidence, real-config fixtures,
original-code worktree proofs with assertion-failing mutation negatives, the
per-entry wiring checklist and the Linux-golden handoff. It states only what
differs. A complete inventory of the file (every declaration, field,
resource, guard, handoff argument and diagnostic, with line numbers) was
produced with this plan and is copied into the dependency report at step 0.

**Execution.** The work runs in its own git worktree
`../debrify-wt/debrify-tv` on branch `refactor/debrify-tv`, cut from
`refactor/codebase`, in parallel with other refactors. Progress records the
execution base SHA at step 0, and every proof names it. Run `flutter pub get`
first; the lockfile must not change (Flutter 3.44.8 / Dart 3.12.2). Commit
after every step; never push or switch branches; gate commits contain `gate`.
Remote CI stays pending until Claude pushes, so every step runs the local
CI-equivalent commands. Evidence goes only under
`<git-common-dir>/refactor-evidence/debrify_tv/`; never write to or relabel
another namespace. **Every manifest run passes an isolated
`--parser-package`** under the ignored `.dart_tool/debrify_tv_parser/`,
including self-tests and other features' manifests (the shared parser cache
collides across worktrees: exit 253, PikPak Progress). Original-code proofs use
a detached worktree under `.dart_tool/debrify_tv_original/`. `suite_evidence.py`
runs are **serialized** (one Flutter suite at a time in this worktree, no
parallel gate load), with `--no-pub` and an explicit `--concurrency` that is
recorded in the env file, not in the paths list.

## Goal

`lib/screens/magic_tv_screen.dart` is **11,271 lines**: 80 import
directives in the 82-line import span, no `part`, and **21 top-level
declarations** — 3 consts, 7 functions (`_clampRandomStartPercent`,
`_parseRandomStartPercent`, `_formatBytes`, `_parseZipInBackground`,
`_parseZipCompute`, `_parseYamlInBackground`, `_parseYamlCompute`), 4 private
enums and 7 classes (`_SpotlightMetaPill`, `_SpotlightChoiceChip` and its
State, `_TvEngineWarmResult`, `_AllDebridPrepared`, the public
`DebrifyTVScreen` and its State). The 19 declarations outside the retained
widget/State move. The State, `_DebrifyTVScreenState` (347–11258, about 10,900 lines,
78 instance fields, 15 static consts, 1 getter, about 140 methods, 162
`setState(` tokens). It is Debrify TV: channel grid and Spotlight layouts,
keyword search across engines, channel cache warm-up, the five provider
resolve paths (Real-Debrid, TorBox, PikPak, Premiumize, AllDebrid), quick
play, playback handoff to the Flutter and Android TV players, channel
switching, the background prefetcher, import/export/share, settings dialogs,
favourites and the home/remote auto-play hooks.

Split it into a new feature, `lib/features/debrify_tv/`, **moving code
verbatim**. Unchanged: the widget tree, keys, `const` placement, focus nodes
and traversal, build order, lifecycle order, timer and delay durations, the
playback handoff arguments, ordering and callback targets, and every
user-visible string.

**Name and facade.** `debrify_tv` matches the product name, the storage
(`DebrifyTvStorage`), models (`lib/models/debrify_tv/`) and the existing
`lib/screens/debrify_tv/` layouts/dialogs (which stay where they are). The
public `DebrifyTVScreen` stays at `lib/screens/magic_tv_screen.dart`, which
becomes the facade, because `lib/main.dart:60` imports it, the theme source
guards name it (`test/theme/source_guard_test.dart:118`), and
`dev/tool/theme_rendered_set.py:30` uses it as the surface root.

**Playback-adjacent, not player work.** The file *starts* playback (11 live
`Navigator.push(videoPlayerRoute(... VideoPlayerScreen(...)))` sites plus one
in the dormant `_playNextFromQueue`, three
Android TV bridge launches, the external-player handoff) and supplies the
player's next/channel callbacks. All of it moves verbatim and is pinned by the
PLAYBACK CONTRACT below. `video_player_screen.dart`, `lib/screens/video_player/`,
`AndroidTvPlayerBridge`, `VideoPlayerLauncher` and all Android/tvOS native code
are out of scope and are not edited.

**Decisions requested before execution (design review, then the user).**

| # | Decision | Recommendation |
| --- | --- | --- |
| D1 | `_handleImportChannelsFromUrl` (2669–2775) uses `package:http` (`http.Request('GET', uri).send()`, 2722). `check_search_architecture.py` forbids `package:http/` in presentation files, bridge or not, except the single pair `PLAYER_LAUNCH_DEOVR_HTTP_IMPORT`, whose comment says "No other HTTP bridge is allowed". | Register a second exact `(file, "package:http/http.dart")` pair, `DEBRIFY_TV_URL_IMPORT_HTTP_IMPORT`, for `legacy_debrify_tv/debrify_tv_url_import.dart` only, with a comment naming the exit (a channel-download data contract). Leaving the method in the facade to dodge the rule (facades are composition roots and skip layer checks) is rejected. |
| D2 | `_watch` (4358–5229) is **872 lines** in one method with four local closures; move-only cannot split it. Its file will be about 930 lines, over the AGENTS.md 800-line ceiling. `_switchToChannel` (477) will be about 530 lines. | Two documented size exceptions (see "Size exceptions"). Exit: a later behaviour-level quick-play decomposition (it duplicates the Real-Debrid resolver closure twice) with its own goldens and review. |
| D3 | The file is already formatted (`dart format --set-exit-if-changed` → 0 changed at `47e7d385`). | No format-only commit: R is the execution base itself (Technique 1). |
| D4 | Dead members (`_parseRandomStartPercent`, `_playNextFromQueue`, the four `setShow*`/`setHide*` local setters and their locals, six write-only fields). | They move **verbatim** and keep their diagnostics (allowlisted by identity). Removal is a separate, later change. |

**Temporary exceptions and their exits.**

| Exception | Exit |
| --- | --- |
| State-driven sections over route-owned records instead of Riverpod | Debrify TV notifiers keyed by profile and route instance |
| A `legacy_debrify_tv/` bridge calling services, storage and the player directly (`DebrifyTvRepository`, `DebrifyTvCacheService`, `DebrifyTvStorage` and the four provider storages, `SettingsManager`, `EngineRegistry`, `TorrentService`, `DebridService`, `TorboxService`, `PremiumizeService`, `AllDebridService`, `PikPakTvService`, `PikPakApiService`, `CommunityChannelsService`, `MagnetYamlService`, `DebrifyTvZipImporter`, `DebrifyTvChannelArchiveService`, `AndroidTvPlayerBridge`, `VideoPlayerLauncher`, `MainPageBridge`, `AnalyticsService`, `ProfilePolicyGuard`, `ProfileAsyncAuthorization`) | Debrify TV data contracts (library, cache, provider resolve, player handoff), after which the folder dissolves |
| The `package:http` pair (D1) | A channel-download data contract |
| Two size exceptions (D2) | The quick-play and channel-switch decompositions |
| Legacy text (every snackbar, dialog and status string) | The localization migration |
| Direct `PlatformUtil.isTvOS` (2460) and `AndroidNativeDownloader.isTelevision()` (844) reads | A TV-capability adapter |

## Public surface (unchanged)

`class DebrifyTVScreen extends StatefulWidget` (340–345): `const
DebrifyTVScreen({super.key})`, no fields, `createState() =>
_DebrifyTVScreenState()`. It stays byte-identical in the facade with its
State. There is **one production importer** (`lib/main.dart:60`, constructed
at 1541 as `const DebrifyTVScreen(), // 3: Debrify TV`) and **no test
importer**. No `GlobalKey` or other code reaches the State; outside access is
only through the `MainPageBridge` registrations pinned in Contract 2. The
`DebrifyTvView` doc (`lib/screens/debrify_tv/layouts/debrify_tv_view.dart:11–19`)
names `_DebrifyTVScreenState`; the State keeps that name, so the doc stays true.

## What it contains (lines at `47e7d385`; after step 0 the manifest is authoritative)

| Lines | Area |
| --- | --- |
| 1–82 | Imports (unsorted; 21 `directives_ordering` under the strict config) |
| 84–121 | Random-start consts and helpers (`_parseRandomStartPercent` unused), 4 enums |
| 123–284 | `_SpotlightMetaPill`, `_SpotlightChoiceChip` + State (own D-pad handler) |
| 286–338 | `_formatBytes`, the two `compute` wrappers and their **top-level entrypoints** `_parseZipCompute`/`_parseYamlCompute`, `_TvEngineWarmResult` |
| 340–345 | `DebrifyTVScreen` |
| 347–494 | State statics, 78 fields, `_viewerForcesNsfw` getter |
| 496–553 | `initState`, `dispose` |
| 555–1059 | Search-bar Back ladder, progress dialog, cancel, provider defaults, `_loadSettings` (155), engine limits, `_loadChannels` |
| 1061–1526 | Library sync, favourites, auto-play, cache warm-up (`_computeChannelCacheEntry`, `_warmKeyword`), delete, provider sync, keywords |
| 1528–1818 | TorBox cache window, warm estimates, quality/size filters, `_selectTorrentsForPlayback` |
| 1820–2344 | Filter/provider chips, `_openChannelDialog` (318) |
| 2346–3583 | Import (device/URL/community/zip/yaml/txt/debrify), export, persistence, summary |
| 3585–4189 | Edit, confirm, delete, share-as-link, YAML, delete-all, `_createOrUpdateChannel` (229) |
| 4191–5904 | `_watchChannel`, **`_watch` (872)**, `_watchWithTorbox`, `_watchWithPikPak` |
| 5906–6535 | RD and AllDebrid cached flows, native-settings failure, TorBox native launch |
| 6537–7226 | Channel switching (`_switchToChannel` 477), channel metadata, RD native launch |
| 7228–7942 | TorBox and PikPak cached flows, PikPak native launch, progress dialogs, **dormant `_playNextFromQueue`** |
| 7944–9138 | `build`, Spotlight view and stage stats (250 ms debounce `Timer`), top bar, grid, cards, options menu |
| 9140–9561 | `_buildSettingsCard` (244, with the unused setters), quick play and global settings dialogs |
| 9563–10907 | TorBox/PikPak/Premiumize resolvers, Premiumize flows, `_watchWithAllDebrid`, small helpers |
| 10909–11257 | External-player handoff, prefetcher, AllDebrid link resolution |
| 11260–11271 | `_AllDebridPrepared` |

**State and resources.** Fields group into seven owners: library (6),
Spotlight stage (4), settings/provider (34), playback session (14), prefetch
(7), progress dialog (3) and focus/search (10, including the `late final
_channelSearchFocusNode` assigned in `initState`). Owned resources: two
`TextEditingController`s, one `ValueNotifier`, five `FocusNode`s, one
`MenuController` (no dispose API), one `Timer` (`_spotlightStatsDebounce`), the
prefetch loop future, and per-dialog controllers/focus nodes/notifiers
disposed by their methods. No ticker, subscription, mixin, `RouteAware`,
`didChangeDependencies` or `didUpdateWidget`.

## Contracts that must not change

Each contract is pinned by source guards and, where observable, by behaviour
tests. Guards compare whole bodies, comments included, through
`test/support/debrify_tv_source.dart`, which covers the facade plus the
feature files with registered renames and receiver substitutions reversed by
the checker's AST token normalization (the Spotlight 0b P1 reader: it validates
lexical/State context first, compares comments independently and returns the
verified original body; it never reverses names in prose, literals or
lexical locals).

1. **Lifecycle (verbatim in the facade State, receiver-only qualification).**
   - `initState` (496–521): `super` → `AnalyticsService.screenView('magic_tv')`
     → `_channelSearchFocusNode = FocusNode(debugLabel:
     'DebrifyTVChannelSearch')` → `_loadSettings()` → `_loadChannels()` (with
     its comment) → `_loadFavoriteChannels()` (all three unawaited) →
     `MainPageBridge.watchDebrifyTvChannel = _watchChannelById` →
     `registerDebrifyTvLibraryListener(_handleSyncedDebrifyTvLibraryChanged)`
     → `_tvContentFocusHandler = () { _quickPlayFocusNode.requestFocus(); }` →
     `registerTvContentFocusHandler(3, _tvContentFocusHandler!)` → the
     **unguarded** post-frame `_checkPendingAutoPlay()`.
   - `dispose` (523–553), 11 steps: debounce cancel → `watchDebrifyTvChannel
     = null` → unregister library listener → `if (_tvContentFocusHandler !=
     null)` unregister tab 3 → `_prefetchStopRequested = true` →
     `_stopPrefetch()` **unawaited** → `_progressSheetContext = null;
     _progressOpen = false` → dispose `_progress`, `_keywordsController`,
     `_channelSearchController`, then the five focus nodes in order →
     `AndroidTvPlayerBridge.clearTorboxProvider()` → `super.dispose()`.
   - `build` (7944–7957) stays a verbatim forwarder in the facade: the
     `'spotlight'` branch builds `SpotlightLayout(view:
     _buildSpotlightView(), bottomInset: …, entryFocusNode:
     _quickPlayFocusNode)`, otherwise `_buildTvGridLayout(bottomInset)`, with
     its comment.
   - Field initializers keep their evaluation point: every record is built
     **eagerly in a State field initializer**, so `SettingsManager()`, the
     controllers, focus nodes, `MenuController`, `ValueNotifier` and
     `DebrifyTvStorage.debrifyTvStyleCached` (368, "read once per mount") are
     still evaluated at State construction, in original declaration order
     within each record.
2. **External hooks and callback identity.** The library listener is
   registered and unregistered with **the same receiver and member** (the
   bridge removes it only if `==`, `main_page_bridge.dart:544–548`); the tab-3
   content handler is the same stored closure at both sites
   (`main_page_bridge.dart:799–806`); `watchDebrifyTvChannel` is the
   `_watchChannelById` tear-off of the live section and is nulled
   unconditionally in `dispose`. `_checkPendingAutoPlay` keeps its 50 ×
   100 ms wait with a `mounted` check per iteration. `focusTvSidebar` (8166,
   8480) is called at the original sites. The 13 `DebrifyTvView` callbacks
   (7970–7983) keep their targets, including the `onWatchOne` closure.
   **Auto-play paths, named:** the Home saved-channel action
   (`lib/screens/search_screen/home_saved_composition.dart:89`) calls
   `HomeHeroShellBridge.playSavedDebrifyChannel`
   (`lib/features/home/presentation/home_hero_shell_bridge.dart:155–162`),
   which calls `MainPageBridge.watchDebrifyTvChannel` when the screen is
   mounted (→ `_watchChannelById`), else stores the id with
   `MainPageBridge.notifyDebrifyTvChannelToAutoPlay` and switches to the tab,
   where the screen's post-frame `_checkPendingAutoPlay` consumes it. The
   remote-control router only **imports channel data**
   (`lib/services/remote_control/remote_command_router.dart`, e.g.
   `DebrifyTvZipImporter.parseYaml` at 4360, writing through the repository and
   cache service); it has no hook into the screen, which sees that data on its
   next `_loadChannels` (or a WebDAV `notifyDebrifyTvLibraryChanged`). Neither
   path is edited.
3. **PLAYBACK CONTRACT.** Nothing in the handoff changes. Pinned per site by
   the source reader plus the callback-identity checker, and by behaviour
   tests where a host test can observe it (Step 0, contract C3).
   1. **Flutter player pushes.** The 11 live sites (and dormant P9) keep their receiver
      (`Navigator.of(context)` with the State's context), the
      `videoPlayerRoute(builder: (_) => VideoPlayerScreen(...))` wrapper and
      **every argument expression and its order**:

      | Site | Original | Options set | `requestMagicNext` | `requestNextChannel` provider set | dir / byId |
      | --- | --- | --- | --- | --- | --- |
      | P1 quick RD early | 4839 | quick | closure 4517 | `_quickProvider` ∈ RD, TorBox, PikPak, Premiumize | yes / yes |
      | P2 quick RD final | 5188 | quick | closure 4992 | `_quickProvider` ∈ RD, TorBox, PikPak | yes / yes |
      | P3 quick TorBox | 5579 | **channel** | `requestTorboxNext` | `_quickProvider` ∈ RD, TorBox, PikPak | no / no |
      | P4 quick PikPak | 5861 | quick | `requestPikPakNext` | `_quickProvider` ∈ RD, TorBox, PikPak | no / no |
      | P5 channel RD | 6163 | channel + name/number | closure 5997 | `_provider` ∈ RD, TorBox, PikPak, Premiumize | yes / yes |
      | P6 channel AllDebrid | 6415 | channel + name/number | closure 6288 | `_provider` ∈ all five | yes / yes |
      | P7 channel TorBox | 7457 | channel + name/number | `requestTorboxNext` | `_provider` ∈ RD, TorBox, PikPak, Premiumize | yes / yes |
      | P8 channel PikPak | 7628 | channel + name/number | `requestPikPakNext` | `_provider` ∈ RD, TorBox, PikPak, Premiumize | yes / yes |
      | P10 channel Premiumize | 10164 | channel + name/number | `requestPremiumizeNext` | `_provider` ∈ RD, TorBox, PikPak, Premiumize | yes / yes |
      | P11 quick Premiumize | 10459 | **channel** | `requestPremiumizeNext` | `_quickProvider` ∈ RD, TorBox, PikPak, Premiumize | no / no |
      | P12 quick AllDebrid | 10732 | quick | closure 10621 | `_quickProvider` ∈ all five | no / no |
      | P9 dormant | 7885 | quick | — | — | — |

      The inconsistencies (P2 vs P1, P3/P11 option sets) are original
      behaviour and stay (Found, not fixed).
   2. **Order around each push (exact).** For RD/AllDebrid flows:
      `_activeApiKey`/`_activeProvider` assignment → `unawaited(_startPrefetch())`
      → progress close (`_closeProgressDialog()`, or the direct
      `Navigator.of(_progressSheetContext!).pop()` at 4769/5142 in `_watch`)
      → `_handOffToExternalPlayer` (true ends the flow) →
      `_launch*OnAndroidTv` (true ends the flow) →
      `MainPageBridge.notifyPlayerLaunching()` → `await` push → `await
      _stopPrefetch()` (P1, P2, P5, P6, P12). In P12 the prefetch starts
      **after** `_closeProgressDialog()`; in P1 the dialog pops **before**
      the prefetch starts; in P2 the prefetch starts **before** the pop. Cached
      TorBox/PikPak/Premiumize flows: `if (!mounted) return;
      _closeProgressDialog();` → external → native → notify → push → status
      `setState`. Quick TorBox/PikPak/Premiumize/AllDebrid keep their
      `_watchCancelled` checks before and after the native launch and around
      the push. Every `on NativePlayerSettingsUnavailable catch (error)` (10)
      calls `_showNativeSettingsFailure(error)`; `_watch` keeps its
      `if (e is NativePlayerSettingsUnavailable) { _showNativeSettingsFailure(e);
      return; }` (4906–4908); every `finally` keeps its `_closeProgressDialog()`
      and its `if (!mounted) return;` (`control_flow_in_finally`, 5 sites).
   3. **Android TV bridge.** `_launchTorboxOnAndroidTv`,
      `_launchRealDebridOnAndroidTv` and `_launchPikPakOnAndroidTv` keep the
      `_isAndroidTv` and empty-URL gates, `notifyPlayerLaunching()` inside the
      `try` before the bridge call, every named argument (title fallback
      `'Debrify TV'`, `magnets` empty, `requestNext`, `requestChannelSwitch`/
      `requestChannelById` gated on `_channels.length > 1` or on
      `canSwitchChannels` (`_currentWatchingChannelId != null &&
      _channels.length > 1 && _provider ∈ {RD, AllDebrid}`), the option
      fields, `showChannelNameOverride ?? _showChannelName`, `channels`,
      `currentChannelId: channelId ?? _currentWatchingChannelId`,
      `currentChannelNumber`), the `onFinished` closures (TorBox/PikPak:
      `clearTorboxProvider()` then `mounted` then status; RD: `await
      _stopPrefetch()` → `clearStreamProvider()` → `_currentWatchingChannelId
      = null` → `mounted` → status), the `rethrow` of
      `NativePlayerSettingsUnavailable` (3 sites) and the fall-through
      `clear*Provider(); return false`. Premiumize keeps using
      `_launchPikPakOnAndroidTv` (10152, 10445). Recorded as-is: the native
      helpers always pass the **channel** options (`_startRandom`,
      `_randomStartPercent`, `_hideSeekbar`, `_hideOptions`, `_showVideoTitle`)
      even for quick play, whose only quick-scope input is
      `showChannelNameOverride: _quickShowChannelName`; and the native
      profile is captured **at bridge launch entry**
      (`final launchScope = ProfileRuntime.scope.value` inside
      `AndroidTvPlayerBridge.launch*Playback`), not when the watch action
      starts. Neither moves or changes.
   4. **Callbacks handed to the players are live tear-offs of one section
      instance.** `_requestNextChannel` (14 sites) and `_requestChannelById`
      (10 sites) become `_sections.channelWatch.requestNextChannel` /
      `_sections.channelWatch.requestChannelById` — both are owned by the
      `channelWatch` section (`DebrifyTvChannelWatch`,
      `debrify_tv_channel_watch.dart`), which calls
      `_sections.channelSwitch.switchToChannel`; the switch file holds
      `_switchToChannel` alone. They are evaluated at the original site (never
      cached in a field, never wrapped in a closure, never another section's
      member). The receiver is frozen in the section map (Destination layout)
      and used identically by the contract, manifest, composition and
      callback fixtures.
      The `request*Next` closures stay local closures in their moved method,
      capturing the same locals (`apiKey`, `firstTitle`, `candidateCursor`,
      `combinedList`/`candidatePool`, `log`).
   5. **External handoff.** `_handOffToExternalPlayer` (10925–10961) keeps its
      gate order: empty URL/`mounted` → `isExternalPlayerDefault()` → `mounted`
      → `_closeProgressDialog()` → `hideAutoLaunchOverlay?.call()` → `mounted`
      → `ExternalPlayerNoticeDialog.confirm(context)` (decline → `await
      _stopPrefetch(); return true`) → `mounted` →
      `launchExternalIfConfigured(context, …)` (true → `_launchedPlayer = true;
      await _stopPrefetch(); return true`). It never touches
      `_watchCancelled` (its comment explains why).
   6. **Cancellation and progress.** `_watchCancelled` is reset only at 4362
      (`_watch`) and 7798 (`_showCachedPlaybackDialog`) and set only in
      `_cancelActiveWatch` (653). `_cancelActiveWatch` keeps its order
      (flag → stop flag → `unawaited(_stopPrefetch())` → optional queue clear
      → progress clear → pop the dialog context or `_closeProgressDialog()` →
      `mounted` `setState`). `_closeProgressDialog` keeps its post-frame
      fallback with root-navigator pop. Both `showGeneralDialog` sites keep the
      `Future.microtask` deferral, the `captureAppThemes(context)` snapshot and
      who sets `_progressSheetContext` (`onReady` vs `pageBuilder`). `_watch`
      keeps `// ignore: unawaited_futures` and the `.whenComplete` reset.
      **Which flows honour cancellation (as-is):** `_watch`'s early-launch
      loop and closure #1, quick TorBox, quick PikPak, quick Premiumize, quick
      AllDebrid and cached PikPak check `_watchCancelled`. The cached RD,
      AllDebrid, TorBox and Premiumize flows and `_watch`'s final closure #2
      do **not**: after Cancel, a held resolve (for example the
      `unrestrictLink` at 6070 in cached RD) can complete, return a stream
      (6091), re-add sibling work to the just-cleared queue (6087–6089),
      restart the prefetcher (`_startPrefetch` resets
      `_prefetchStopRequested`) and reach the handoff (6130 onward) with only a
      `mounted` check. That late launch is original behaviour; it is
      characterized as-is and listed in Found, not fixed. No cancellation fix is
      made in this split.
   7. **Prefetch.** `_startPrefetch` keeps the epoch capture, the preference
      read, the post-await re-check (`mounted`, epoch, running, key) and the
      flag order; `_stopPrefetch` increments the epoch **first**, then awaits
      the task with errors swallowed, then clears inflight. The loop keeps its
      750/75/150/1000 ms delays, `_minPrepared` 6, `_lookaheadWindow` 10 and
      the `identical(_queue[idx], item)` slot guards. RD vs AllDebrid dispatch
      on `_activeProvider` is unchanged.
   8. **Channel switching.** `_switchToChannel` keeps `await _stopPrefetch()` →
      **`await Future.delayed(const Duration(seconds: 5))`** → previous-cache
      eviction → seen/filter resets → per-provider resolve → its **six**
      prefetch starts (two on success: RD 6861, AllDebrid 6947; four failure
      restarts for RD/AllDebrid: 6669, 6683, 6694, 7080) → the returned map keys
      (`channelId`, `channelName`, `channelNumber`, `firstUrl`, `firstTitle`).
      Premiumize still falls through to "Unsupported provider" (Found, not
      fixed).
   9. **Queue semantics.** `_queue` stays one `List<dynamic>` shared by every
      flow and the prefetcher, with the same `rd_restricted`, `ad_locked` and
      `torbox_file` map shapes and the same `_seenRestrictedLinks`/
      `_seenLinkWithTorrentId` keys.
   10. **No new playback seam.** No production hook is added for tests. A guard
       rejects any new import of `media_kit`, `video_player_launcher` internals,
       `player_launch` or `lib/screens/video_player/` outside the files that
       hold the moved sites, and any new `VideoPlayerScreen(` outside a
       `videoPlayerRoute(builder:` argument.
   11. **Argument ledger (frozen).** Step 0 commits
       `dev/tool/debrify_tv_handoff_ledger.json`: for each of the 12
       `VideoPlayerScreen(` constructions (11 live + dormant P9), the 11
       `_launch*OnAndroidTv(` invocations and the 3 `AndroidTvPlayerBridge.launch*`
       calls, the ordered list of `name: expression` pairs exactly as
       written, plus "every other parameter is not passed (constructor
       default)". The checker compares each moved call site with its ledger
       entry token-for-token (receiver qualification reversed), and the C3
       tests compare captured `VideoPlayerScreen` fields with the ledger's
       expected values for their fixture. Ledger at `47e7d385`:

       | Site | `videoUrl` / `title` | options (`startFromRandom`, `randomStartMaxPercent`, `hideSeekbar`, `showChannelName`, `showVideoTitle`, `hideOptions`) | `channelName` / `channelNumber` | `requestMagicNext` | `requestNextChannel` | `channelDirectory` | `requestChannelById` |
       | --- | --- | --- | --- | --- | --- | --- | --- |
       | P1 4841 | `firstUrl` / `firstTitleResolved` | `_quick*` | `null` / `null` | `requestMagicNext` | `_channels.length > 1 && (_quickProvider == RD ∨ TorBox ∨ PikPak ∨ Premiumize) ? _requestNextChannel : null` | `activeChannelDirectory` | `_channels.length > 1 ? _requestChannelById : null` |
       | P2 5190 | `firstUrl` / `firstTitle` | `_quick*` | `null` / `null` | `requestMagicNext` | same with RD ∨ TorBox ∨ PikPak | `quickChannelDirectory` | same |
       | P3 5581 | `first['url'] ?? ''` / `first['title'] ?? 'Debrify TV'` | channel | `null` / `null` | `requestTorboxNext` | `_quickProvider` RD ∨ TorBox ∨ PikPak | not passed | not passed |
       | P4 5863 | as P3 | `_quick*` | `null` / `null` | `requestPikPakNext` | `_quickProvider` RD ∨ TorBox ∨ PikPak | not passed | not passed |
       | P5 6165 | `firstUrl` / `firstTitle` | channel | `channelName` / `channelNumber` | `requestMagicNext` | `_provider` RD ∨ TorBox ∨ PikPak ∨ Premiumize | `channelDirectory` | `_channels.length > 1 ? …` |
       | P6 6417 | as P5 | channel | as P5 | `requestMagicNext` | `_provider` all five | `channelDirectory` | same |
       | P7 7459 | as P3 | channel | as P5 | `requestTorboxNext` | `_provider` RD ∨ TorBox ∨ PikPak ∨ Premiumize | `channelDirectory` | same |
       | P8 7630 | as P3 | channel | as P5 | `requestPikPakNext` | as P7 | `channelDirectory` | same |
       | P9 7887 (dormant) | `videoUrl` / `next.name` | `_quick*` | `null` / `null` | not passed | not passed | not passed | not passed |
       | P10 10166 | as P3 | channel | as P5 | `requestPremiumizeNext` | as P7 | `channelDirectory` | same |
       | P11 10461 | as P3 | channel | `null` / `null` | `requestPremiumizeNext` | `_quickProvider` RD ∨ TorBox ∨ PikPak ∨ Premiumize | not passed | not passed |
       | P12 10734 | `first['url'] ?? ''` / `firstTitle` | `_quick*` | `null` / `null` | `requestMagicNext` | `_quickProvider` all five | not passed | not passed |

       Native helper invocations (`firstStream: first` and `requestNext:` the
       flow's closure at every site): 4817 and 5168 RD with
       `showChannelNameOverride: _quickShowChannelName`, `channelId:
       activeChannelId`, `channelNumber: activeChannelNumber`,
       `channelDirectory: activeChannelDirectory` / `quickChannelDirectory`;
       5559 TorBox, 5841 PikPak, 10445 PikPak (Premiumize) with
       `showChannelNameOverride: _quickShowChannelName` and
       `channelName`/`channelId`/`channelNumber`/`channelDirectory: null`;
       10719 RD (AllDebrid) with the override and `channelId`,
       `channelNumber`, `channelDirectory: null` (no `channelName`); 6141, 6395
       RD, 7442 TorBox, 7613 and 10152 PikPak with `channelName`, `channelId`,
       `channelNumber`, `channelDirectory` and no override. Bridge calls:
       6491 and 7698 `launchTorboxPlayback` and 7164 `launchRealDebridPlayback`
       with the argument lists in Contract 3.3 (`magnets: magnets` at 6491,
       `magnets: const []` at 7698). The two bridge methods order their
       arguments differently (`magnets` vs `channelName` after `title`); each
       site keeps its own order.
4. **Settings and persistence.** `_loadSettings` keeps its read order (30
   awaits), the hard-coded `hideOptions`/`hideBackButton` false, the single
   `setState` assigning every field, the post-`setState`
   `_refreshSpotlightStatsIfFocused`, the `hideSeekbar` rewrite and the
   provider save. `_buildSettingsCard` is rendered **only** by
   `_showGlobalSettingsDialog` (9541) with `_SettingsScope.channels` and
   `includeNsfwToggle: false`, so its live controls are the provider chips,
   the start-random switch (`setStartRandom`, 9266–9271), the random-start
   slider (`setRandomStartPercent` plus `onChangeEnd`, 9272–9285), the filter
   chips and Reset; each channel-scope write goes through the original
   `DebrifyTvStorage` call. `setShowChannelName` and `setShowVideoTitle` are
   unused, `setHideOptions`/`setHideBackButton` are unused no-ops
   (9182–9228), and the card's quick-scope and NSFW branches are unreachable;
   all stay verbatim. Quick-play options are set only by the Play-now copy in
   `_showQuickPlayDialog` (9489–9503), which persists nothing. Reset writes
   exactly the keys it writes today; filter chips persist qualities and sizes
   unawaited. `_viewerForcesNsfw` stays a **live getter** evaluated at each of
   its 14 read sites (never cached).
5. **Channel library and cache.** Loading, favourites, the synced-library
   invalidation (clears `_channelCache`, `_spotlightStats`,
   `_spotlightRailHealth`, reloads), delete and delete-all (with their 100 ms +
   two `endOfFrame` waits), `_createOrUpdateChannel`'s incremental warm,
   rollback writes (`WebDavSyncMutationOrigin.rollback`) and
   `_ensureCacheEntry` caching are unchanged. Warm-up keeps the batch size,
   per-engine limits, the NSFW and minimum-torrent rules and the failure text.
6. **Import, export and share.** Type detection (extension, PK signature,
   `debrify://` content), the 120-character and 500-keyword text limits, the
   100 MB portable cap, the community 2 s summary hold, ZIP/YAML parsing
   **through `compute` with top-level entrypoints** (`_parseZipCompute`,
   `_parseYamlCompute` stay top-level functions in one library with their
   wrappers), unique-name resolution, the export profile capture
   (`ProfileAsyncAuthorization.capture(ProfileFeature.debrifyTv)` with
   `runIfCurrent` for every read and the final check), the tvOS export
   refusal, and the generated YAML text are unchanged.
7. **Spotlight stage.** `_onSpotlightChannelFocused` cancels the debounce
   **first, unconditionally**, sets the focus id, rebuilds, returns on a memo
   hit, else arms `Timer(250 ms, () => _computeSpotlightStats(channel))`.
   `_computeSpotlightStats` keeps its after-await `!mounted ||
   _spotlightFocusedId != channel.id` guard and one-pass classify.
8. **D-pad and focus.** Unchanged: the choice chip's KeyDown/KeyRepeat
   handler; the search-bar Escape/GoBack ladder on its non-focusable ancestor;
   the top buttons' Left/Right/Up/activate handling (Left at the Play button →
   `focusTvSidebar`); the menu's open/close keys and `autofocus` on Import;
   the search field's arrow callbacks and the clear button handler; dialog
   field arrow callbacks and `autofocus` targets; `TvFocusableCard` press,
   long-press and `showLongPressHint: _isAndroidTv`; the grid `KeyedSubtree`
   keys; `entryFocusNode` and the tab-3 handler.
9. **Rebuild boundaries.** No builder becomes a widget, no wrapper is
   inserted, no `const` changes (one `prefer_const_constructors` info at 3521
   stays). `ListenableBuilder`, `LayoutBuilder` and `Builder` scopes keep
   their lexical `context`.
10. **Profiles and stale results.** Only export captures the profile; every
    other async path keeps exactly its current `mounted`/epoch/focus-id
    guards — no guard is added or removed (Found, not fixed, lists the gaps).

## Destination layout

All destinations are under `lib/features/debrify_tv/`. Each is at most 500
formatted lines except the two documented exceptions. Line counts are
estimates (original lines + imports/headers + about 4% receiver-induced
wraps); the step 0 dependency report settles membership and the creation
commit measures each file.

**Outside the bridge (service-free):**

| File | Contents | Est. |
| --- | --- | --- |
| `models/debrify_tv_kinds.dart` | 4 enums → `DebrifyTvSettingsScope`, `DebrifyTvTopMenuAction`, `DebrifyTvChannelImportOrigin`, `DebrifyTvChannelImportType` | 15 |
| `models/debrify_tv_constants.dart` | `DebrifyTvConstants` holding the 15 State statics verbatim (`static const`, comments kept) | 30 |
| `models/debrify_tv_alldebrid_prepared.dart` | `_AllDebridPrepared` → `DebrifyTvAllDebridPrepared` (doc kept) | 16 |
| `application/debrify_tv_random_start.dart` | 3 consts, `_clampRandomStartPercent` → public, `_parseRandomStartPercent` stays private and unused | 36 |
| `application/debrify_tv_byte_format.dart` | `_formatBytes` → `formatDebrifyTvBytes` | 16 |
| `presentation/debrify_tv_meta_pill.dart` | `_SpotlightMetaPill` (private, `typedef DebrifyTvMetaPill = _SpotlightMetaPill;`) | 52 |
| `presentation/debrify_tv_choice_chip.dart` | `_SpotlightChoiceChip` + `_SpotlightChoiceChipState` (private, `typedef DebrifyTvChoiceChip = _SpotlightChoiceChip;`); the exact pure `debrifyTvChoiceChip` constructor forwarder frozen in step 0b | 125 + 13 |

The typedef export keeps the private runtime types and keyless private
constructors (the catalog/merged precedent); the rename probe inventories any
resulting `library_private_types_in_public_api` identity.
The full step-0b composition revealed a new `unused_element_parameter` warning
for `trailingIcon` when callers construct the private choice chip through a
typedef in another library. Its 13-line typed constructor forwarder returns
the original widget, passing all five arguments in their original order; it
adds no widget node, key, default, `const`, suppression or constructor change.
Only choice-chip call sites use it. The typedef remains inside its own file;
the meta pill continues to use its typedef directly. The forwarder and its
arguments are frozen in `debrify_tv_scaffolding.json`, with opt-in name
normalization in `constructor_forwarders` when step 3 creates the file.

**`presentation/legacy_debrify_tv/` (the bridge; exact path in the guard):**

| File | Contents | Est. |
| --- | --- | --- |
| `debrify_tv_bindings.dart` | `DebrifyTvDependencies`: owners, sections, live `context()`/`mounted()` getters and the State's `setState` tear-off | 45 |
| `debrify_tv_owners.dart` | `DebrifyTvOwners` composing the seven records, eager | 30 |
| `debrify_tv_library_state.dart` | `_keywordsController`, `_channels`, `_debrifyTvStyle`, `_channelCache`, `_currentWatchingChannelId`, `_favoriteChannelIds` | 25 |
| `debrify_tv_stage_state.dart` | four Spotlight stage fields | 16 |
| `debrify_tv_settings_state.dart` | 34 settings/provider fields + the live `viewerForcesNsfw` getter | 70 |
| `debrify_tv_session_state.dart` | 14 session fields (`_queue` … `_originalMaxCap`) | 35 |
| `debrify_tv_prefetch_state.dart` | 7 prefetch fields with their comments | 25 |
| `debrify_tv_progress_state.dart` | `_progress`, `_progressSheetContext`, `_progressOpen` | 14 |
| `debrify_tv_focus_state.dart` | search controller/term/flag, five focus nodes (one `late final`), menu controller, content handler | 32 |
| `debrify_tv_sections.dart` | `DebrifyTvSections`: constructs every section once, inert constructors | 110 |
| `debrify_tv_feedback.dart` | `_closeProgressDialog`, `_updateProgress`, `_cancelActiveWatch`, `_showChannelCreationDialog`, `_showCachedPlaybackDialog`, `_showSnack`, `_showNativeSettingsFailure` | 250 |
| `debrify_tv_settings_loader.dart` | `_determineDefaultProvider`, `_isProviderSelectable`, `_loadSettings`, `_syncProviderAvailability`, `_providerDisplay` | 310 |
| `debrify_tv_engine_limits.dart` | 7 engine-limit/estimate methods | 150 |
| `debrify_tv_playback_filters.dart` | quality/size filters, `_notifyQualityFallback`, `_rdLinkPassesSizeRules`, `_selectTorrentsForPlayback`, `_normalizeInfohash` | 205 |
| `debrify_tv_channel_library.dart` | load/sync/favourites/auto-play/delete/keywords/cache entry/unique name/channel number/channel metadata (14 methods) | 245 |
| `debrify_tv_channel_warmup.dart` | `_TvEngineWarmResult` (private), accumulate/sort/compute/warm/filter (6 methods) | 395 |
| `debrify_tv_channel_editor.dart` | `_addKeywordsToList`, `_openChannelDialog` | 380 |
| `debrify_tv_channel_actions.dart` | add, edit, confirmation, delete, delete-all | 230 |
| `debrify_tv_channel_save.dart` | `_createOrUpdateChannel` | 265 |
| `debrify_tv_channel_share.dart` | share-as-link, YAML generation, escape | 220 |
| `debrify_tv_channel_export.dart` | export progress, tvOS refusal, export | 230 |
| `debrify_tv_channel_import.dart` | import entry, mode, device, community, community prompt, file bytes | 295 |
| `debrify_tv_url_import.dart` | URL import (**the http pair, D1**), header extension, URL prompt, debrify-link import | 320 |
| `debrify_tv_import_formats.dart` | dispatch, safe dispatch, type detection, zip/yaml/text/debrify, strip extension, `_formatImportError` | 290 |
| `debrify_tv_import_persistence.dart` | persist imported channels, summary dialog | 275 |
| `debrify_tv_import_parsing.dart` | the two `compute` wrappers (public) and their **private top-level entrypoints** | 40 |
| `debrify_tv_quick_play.dart` | `_watch` alone (**size exception**) | ~930 |
| `debrify_tv_quick_play_torbox.dart` | `_watchWithTorbox` | 430 |
| `debrify_tv_quick_play_pikpak.dart` | `_watchWithPikPak` | 315 |
| `debrify_tv_quick_play_premiumize.dart` | `_watchWithPremiumize` | 325 |
| `debrify_tv_quick_play_alldebrid.dart` | `_watchWithAllDebrid` (doc) | 315 |
| `debrify_tv_channel_watch.dart` | `_watchChannel` (doc), `_requestNextChannel`, `_requestChannelById` | 270 |
| `debrify_tv_channel_switch.dart` | `_switchToChannel` alone (**size exception**) | ~530 |
| `debrify_tv_cached_real_debrid.dart` | `_watchWithCachedTorrents` | 335 |
| `debrify_tv_cached_all_debrid.dart` | `_watchAllDebridWithCachedTorrents` (doc) | 290 |
| `debrify_tv_cached_torbox.dart` | `_watchTorboxWithCachedTorrents` (the `unnecessary_cast`) | 315 |
| `debrify_tv_cached_pikpak.dart` | `_watchPikPakWithCachedTorrents` | 200 |
| `debrify_tv_cached_premiumize.dart` | `_watchPremiumizeWithCachedTorrents` | 265 |
| `debrify_tv_player_handoff.dart` | three `_launch*OnAndroidTv`, `_handOffToExternalPlayer` (with its section comment and doc) | 345 |
| `debrify_tv_torbox_resolver.dart` | cache window, queued file, prepare, playable entries, series title, video check, display name, `_asIntMapValue`, `_formatTorboxError` | 330 |
| `debrify_tv_cloud_resolvers.dart` | PikPak prepare; Premiumize cache window, prepare, entries, video check | 315 |
| `debrify_tv_prefetch.dart` | start/stop/loop/count/find/prefetch-one, AllDebrid resolve and prefetch | 330 |
| `debrify_tv_dormant.dart` | `_playNextFromQueue`, kept **private and unused** | 125 |
| `debrify_tv_settings_chips.dart` | `_tvFilterChips`, `_providerChoiceChips` | 210 |
| `debrify_tv_settings_card.dart` | `_buildSettingsCard` (unused setters/locals kept) | 280 |
| `debrify_tv_dialogs.dart` | quick play, global settings, channel options menu | 300 |
| `debrify_tv_spotlight_stage.dart` | `_buildSpotlightView` … `_computeSpotlightStats` (6 members) | 170 |
| `debrify_tv_top_bar.dart` | search Back ladder, toggle/clear/focus-below, top menu action, action button, menu button, top actions | 440 |
| `debrify_tv_grid_layout.dart` | `_buildTvGridLayout`, `_buildTvEmptyState` | 315 |
| `debrify_tv_grid_cards.dart` | favourites section/card, channel card, add card | 390 |

**Frozen section map.** The composition key, class and file of every
section are fixed here and used identically by the contracts, manifest,
composition and callback fixtures (`receiver_paths`/`receiver_owners` and
`callback_instances` in the config):

| Key (`_sections.<key>`) | Class | File (`legacy_debrify_tv/`) |
| --- | --- | --- |
| `feedback` | `DebrifyTvFeedback` | `debrify_tv_feedback.dart` |
| `settings` | `DebrifyTvSettingsLoader` | `debrify_tv_settings_loader.dart` |
| `engines` | `DebrifyTvEngineLimits` | `debrify_tv_engine_limits.dart` |
| `filters` | `DebrifyTvPlaybackFilters` | `debrify_tv_playback_filters.dart` |
| `library` | `DebrifyTvChannelLibrary` | `debrify_tv_channel_library.dart` |
| `warmup` | `DebrifyTvChannelWarmup` | `debrify_tv_channel_warmup.dart` |
| `editor` | `DebrifyTvChannelEditor` | `debrify_tv_channel_editor.dart` |
| `actions` | `DebrifyTvChannelActions` | `debrify_tv_channel_actions.dart` |
| `save` | `DebrifyTvChannelSave` | `debrify_tv_channel_save.dart` |
| `share` | `DebrifyTvChannelShare` | `debrify_tv_channel_share.dart` |
| `channelExport` | `DebrifyTvChannelExport` | `debrify_tv_channel_export.dart` |
| `channelImport` | `DebrifyTvChannelImport` | `debrify_tv_channel_import.dart` |
| `urlImport` | `DebrifyTvUrlImport` | `debrify_tv_url_import.dart` |
| `formats` | `DebrifyTvImportFormats` | `debrify_tv_import_formats.dart` |
| `persistence` | `DebrifyTvImportPersistence` | `debrify_tv_import_persistence.dart` |
| `quickPlay` | `DebrifyTvQuickPlay` | `debrify_tv_quick_play.dart` |
| `quickTorbox` / `quickPikPak` / `quickPremiumize` / `quickAllDebrid` | `DebrifyTvQuickPlayTorbox` / `…PikPak` / `…Premiumize` / `…AllDebrid` | `debrify_tv_quick_play_{torbox,pikpak,premiumize,alldebrid}.dart` |
| `channelWatch` | `DebrifyTvChannelWatch` (`watchChannel`, **`requestNextChannel`, `requestChannelById`**) | `debrify_tv_channel_watch.dart` |
| `channelSwitch` | `DebrifyTvChannelSwitch` (`switchToChannel` only) | `debrify_tv_channel_switch.dart` |
| `cachedRealDebrid` / `cachedAllDebrid` / `cachedTorbox` / `cachedPikPak` / `cachedPremiumize` | `DebrifyTvCached{RealDebrid,AllDebrid,Torbox,PikPak,Premiumize}` | `debrify_tv_cached_{real_debrid,all_debrid,torbox,pikpak,premiumize}.dart` |
| `handoff` | `DebrifyTvPlayerHandoff` | `debrify_tv_player_handoff.dart` |
| `torbox` | `DebrifyTvTorboxResolver` | `debrify_tv_torbox_resolver.dart` |
| `cloud` | `DebrifyTvCloudResolvers` | `debrify_tv_cloud_resolvers.dart` |
| `prefetch` | `DebrifyTvPrefetcher` | `debrify_tv_prefetch.dart` |
| `dormant` | `DebrifyTvDormant` | `debrify_tv_dormant.dart` |
| `chips` | `DebrifyTvSettingsChips` | `debrify_tv_settings_chips.dart` |
| `settingsCard` | `DebrifyTvSettingsCard` | `debrify_tv_settings_card.dart` |
| `dialogs` | `DebrifyTvDialogs` | `debrify_tv_dialogs.dart` |
| `stage` | `DebrifyTvSpotlightStage` | `debrify_tv_spotlight_stage.dart` |
| `topBar` | `DebrifyTvTopBar` | `debrify_tv_top_bar.dart` |
| `grid` | `DebrifyTvGridLayout` | `debrify_tv_grid_layout.dart` |
| `cards` | `DebrifyTvGridCards` | `debrify_tv_grid_cards.dart` |

(`import`/`export` are avoided as keys: they are Dart built-in identifiers.)
Owner records are `_owners.library`, `.stage`, `.settings`, `.session`,
`.prefetch`, `.progress`, `.focus`. A change to this map is a plan amendment.

**Cross-class privates** become manifest-listed public names
(`_watchChannel` → `watchChannel`, …). Each section exposes only what other
sections or the facade call; anything called only within its own file keeps
its private name.

**The facade** (`lib/screens/magic_tv_screen.dart`) holds sorted imports,
`DebrifyTVScreen` byte-identical, and `_DebrifyTVScreenState` with the eager
`final DebrifyTvOwners _owners = DebrifyTvOwners();`, a nullable cached
composition (`DebrifyTvSections? _composition;` and a getter that builds it
once with `DebrifyTvDependencies(owners: _owners, context: () => context,
mounted: () => mounted, setState: setState)`; never `late`, never per build),
the verbatim lifecycle and the verbatim `build` forwarder.

**Facade cap, measured over every retained physical line.**
- Estimate (formatted): imports 9 + widget 6 + State header and composition 14
  + `initState` about 32 + `dispose` about 40 + `build` about 16 + blank and
  closing lines about 15 ≈ **130–160 lines**.
- **Procedure.** At step 0b (compiling-composition probe) and at each step
  from 2 (actual), Progress records `wc -l` of the formatted facade and a
  per-span breakdown by AST range — imports, widget, State header,
  owners/composition, lifecycle, `build`, remaining blank/comment lines —
  whose sum equals the total.
- The target is 300 lines (AGENTS.md preferred band). If the measured
  complete facade exceeds it, the cap becomes that measured value, **at most
  450** (the user's maximum for this plan). Above 450 is a plan failure to
  report, not a new exception. The enforced cap is the measured value, not the
  maximum; no line may be added to use headroom. `TEMP(debrify_tv)` rejection
  enforces it from step 8.
- No accessor or forwarder is planned (the State has no public members and no
  test reaches it). If step 0b proves one necessary, it is frozen and counted.

**Guard rules** (step 1, `check_search_architecture.py`): `debrify_tv` in
`FEATURES`; `DEBRIFY_TV_FACADE`, `DEBRIFY_TV_BRIDGE`, `DEBRIFY_TV_COMPLETE =
False`; the bridge in `LEGACY_PLAYBACK_BRIDGES` (still no `shared_preferences`
or `sqflite`); `DEBRIFY_TV_URL_IMPORT_HTTP_IMPORT` (D1) honoured beside the
DeoVR pair in the presentation import rule; no facade back-import (`own ==
"debrify_tv" and target == DEBRIFY_TV_FACADE`); service imports only inside
the exact bridge (the Spotlight rule); `application/` and `models/` import no
`lib/services/` (the pure-helper rules); the playback-import ban (Contract
3.10) for every feature file except the registered handoff/flow files;
500-line caps with `DEBRIFY_TV_SIZE_EXCEPTIONS`, and the global 800-line
ceiling (`check_search_architecture.py:601`) generalised to read
`max(800, PLAYER_LAUNCH_SIZE_EXCEPTIONS…, DEBRIFY_TV_SIZE_EXCEPTIONS…)` for
the one `_watch` file.

**Facade registration** (step 8, with `DEBRIFY_TV_COMPLETE = True`): `if
DEBRIFY_TV_COMPLETE: paths.add(ROOT / DEBRIFY_TV_FACADE)` in `main()`; the
facade in `COMPOSITION_ROOTS` with a comment (it imports concrete bridge files
to wire them, so it skips layer import checks but keeps its cap and `TEMP`
rejection); `DEBRIFY_TV_FACADE_CAP = <measured>` and the
`TEMP(debrify_tv)` rejection as for `SPOTLIGHT_BOARD_FACADE`. Tests run **the
real checker** against a temporary copy of the tree and must reject: the
facade missing; the facade at cap + 1; `TEMP(debrify_tv)` in the facade and
in a feature file; **each of the two size-exception files**
(`debrify_tv_quick_play.dart`, `debrify_tv_channel_switch.dart`) at its
measured cap + 1; an **unrelated** registered file (another Debrify TV
destination, and separately a file of another feature) grown above 800 lines,
proving the generalised ceiling does not spread the exemption; the
`package:http` import in any Debrify TV file other than
`debrify_tv_url_import.dart` (the D1 pair is an import permission, not a size
exception); a non-bridge file importing `lib/services/`. The unmodified tree
passes.

## Size exceptions

`DEBRIFY_TV_SIZE_EXCEPTIONS = {
  "lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_quick_play.dart": <measured>,
  "lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_channel_switch.dart": <measured>,
}`

Values are measured in each file's creation commit (estimates: about 930 and
530). Each file holds its one method alone plus imports, the section header
and its dependency getters. The `_watch` file also gets a hand-added line in
`dev/tool/file_size_baseline.txt` in its creation commit (the shrink-only
`check_file_sizes.py --update` cannot add files), with the reason in the
commit message. Comments state the reason (a move cannot split one method
body) and the exit (a later behaviour-level decomposition of quick play —
the twin Real-Debrid `requestMagicNext` closures — and of channel switching's
per-provider arms, each with its own goldens and review). No other exception
is authorized; the checker rejects growth of either file.

## Technique

As in the Spotlight and catalog plans, plus:

1. **Two originals without a format commit.** The file is already formatted
   (0 changes, D3), so R is the **execution base SHA**; Progress records the
   idempotence proof (`dart format --output=none --set-exit-if-changed` on R)
   in `format-idempotence.json` and needs no token proof. If the base has moved
   and the formatter changes the file, fall back to the precedent: a
   format-only commit (a) `style(debrify-tv): format the original Debrify TV
   screen` with the token/comma proof, which then becomes R.
   - **(b) Characterization checkpoint** (`test(debrify-tv): step 0
     original-code characterization checkpoint`): application files
     unchanged from R; adds the frozen characterization tests, harness,
     source reader, fixtures, checker config and macOS goldens, and switches
     the two existing source-text tests to the reader (Step 0.8). It is the
     ORIGINAL for behaviour: detached-worktree proofs, mutation negatives and
     the Linux capture all run (b)'s own tests against (b)'s application
     code. Progress proves `git rev-parse <b>:lib` = `<R>:lib` (and
     `pubspec.yaml`, `pubspec.lock`). No seam checkpoint is planned; if step 0
     proves one unavoidable, stop and ask.
   - R is used everywhere: the manifest `--baseline`, the relocation
     comparison, the hash rule, the Linux script and every replay.
2. **Strict-lint baseline** (probe at `47e7d385`, scratch copy, same SDK):
   **72** diagnostics under the features config = the root **50** (17
   warnings, 33 infos, re-counted by identity from the measured output) + **21 `directives_ordering`** + **1
   `prefer_const_constructors`** (3521). Root warnings: `unused_element` ×6
   (`_parseRandomStartPercent`, `_playNextFromQueue`, `setShowChannelName`,
   `setShowVideoTitle`, `setHideOptions`, `setHideBackButton`),
   `unused_field` ×6 (`_status`, `_hideBackButton`, `_quickHideBackButton`,
   `_lastQueueSize`, `_lastSearchAt`, `_originalMaxCap`),
   `unused_local_variable` ×4, `unnecessary_cast` ×1. Infos:
   `sort_child_properties_last` ×8, `no_leading_underscores_for_local_identifiers`
   ×6, `prefer_interpolation_to_compose_strings` ×1,
   `use_build_context_synchronously` ×13, `control_flow_in_finally` ×5.
   Step 0 re-measures these at R in a detached worktree inside `.dart_tool/`
   (qualifying relative imports only) and records them by identity (rule,
   enclosing member, message). A throwaway **rename/receiver probe** applies
   the manifest's renames and receiver substitutions to a compiling copy and
   inventories, by identity: the six `unused_field` warnings that disappear
   (fields become public record members — a recorded removal, not a fix);
   every change in `use_build_context_synchronously` caused by
   `context`/`mounted` becoming `_deps.context()`/`_deps.mounted()` (the lint
   may stop recognising a `mounted` guard); any `library_private_types_in_public_api`
   from the typedefs. Baseline and probe combine by **maximum** per identity,
   never by sum. No `const`, key, constructor or suppression change is made.
   **CI analyzes `lib/features` from the first file**, so every surviving
   warning gets its `analyzer_allowlist.txt` entry (by destination path) in
   the commit that creates its file: `_parseRandomStartPercent`
   (`application/debrify_tv_random_start.dart`), `_playNextFromQueue`
   (`debrify_tv_dormant.dart`), the four setters and four locals
   (`debrify_tv_settings_card.dart`), `unnecessary_cast`
   (`debrify_tv_cached_torbox.dart`), under a dated comment naming R.
3. **Live getters and setState.** Sections reach `context`, `mounted` and the
   State's `setState` only through `_deps.context()`, `_deps.mounted()` and
   `_deps.setState(...)` (registered `live_getter_callbacks`, the injected
   tear-off), evaluated at the original site; nothing is hoisted or cached.
   `DebrifyTVScreen` has no fields, so no widget view and no class-header
   addition are needed. **Lexical scopes stay lexical**: every builder
   `context` parameter (2063, 3241, 8191, 8301, 8358, 8527, 8618, 8653, 8758,
   8759, 8965, 9403, 9532) and every **shadowed setter** — the
   `StatefulBuilder` parameter named `setState` in `_promptImportUrl` (3241;
   uses at 3292, 3313) and the `setState` parameter of `_addKeywordsToList`
   (2004; use at 2010), plus `setModalState`/`setDialogState`. The checker
   normalises `_deps.setState` to `setState`, which would hide a swap, so a
   new opt-in config key `lexical_state_setters` (declaration → scopes)
   checks, **before normalization**, that those tokens remain the bare
   lexical identifier. Negatives: each shadowed use replaced by
   `_deps.setState`; a State `setState` site replaced by a lexical setter; a
   builder `context` replaced by `_deps.context()` (existing context guard).
4. **Field ownership and the field-binding guard.** All 78 instance fields
   move at step 2 into the seven records, renamed by dropping the leading
   underscore (`_startRandom` → `startRandom`). **Every moved field reference
   is receiver-qualified** (`_owners.settings.startRandom`); no section,
   resolver or paint class declares an instance field, and no record method
   reads a sibling field unqualified. This removes the Spotlight failure mode
   — an unqualified renamed field captured by a same-named parameter or local
   (`_moving` → `moving` in `setWideSelection`). This file has many such
   names (dependency report lists them): `_loadSettings` declares locals
   `startRandom`, `randomStartPercent`, `hideOptions`, `showChannelName`,
   `showVideoTitle`, `tvFilters`, `tvEngineStates`, the three `*MaxByEngine`
   maps, `channelBatchSize`, `keywordThreshold`, `minTorrentsPerKeyword`,
   `quickPlayMaxKeywords` and the five `*Available` flags, and assigns each to
   its same-named field (847–895); `_syncProviderAvailability` does the same
   for the five flags; `_buildSettingsCard` declares `startRandom`,
   `randomStartPercent`, `showChannelName`, `showVideoTitle`, `hideOptions`,
   `hideBackButton` beside closures that write the fields;
   `_persistImportedZipChannels` takes `channels` and writes `_channels`.
   **Guard: occurrence-level binding with mandatory qualification (new,
   opt-in).** The reused Spotlight comparison
   (`spotlight_board_field_bindings.py`) is not enough: it compares
   *counters* keyed by field identity and read/write role, so a balanced
   relocation (one field read turned into a local read while a local read
   elsewhere becomes the field read) keeps the counts, and it accepts a bare
   field inside its destination class (lines 44–46). Add a config-scoped key,
   `occurrence_field_bindings` (Debrify TV config only; every other
   manifest's behaviour and self-tests unchanged), implemented beside the
   Spotlight helper and run **before** declaration normalization and before
   the source reader:
   - **Binder (syntax-based, explicit).** The AST adapter
     (`dev/tool/verbatim_ast.dart.txt`) is syntax-only: it uses `parseString`
     (494) and exposes name sets per scope (`References`, 19–25, 164–165), not
     resolved declaration identities. Resolved analysis is not adopted (it
     would need the whole app's package resolution inside the isolated parser
     package). Instead the adapter gains an opt-in **declaration/scope binder**
     (emitted only when the config asks for `occurrence_field_bindings`; output
     for every other manifest is unchanged). For each manifest leaf it emits
     the ordered list of `SimpleIdentifier` occurrences outside comments and
     string text (identifiers inside `${…}` interpolations are included) with:
     the token index; the scope path (member → each enclosing
     `FunctionExpression`, local `FunctionDeclaration`, block, `for`, `catch`
     and pattern scope); a **kind** — `lexical` for a bare reference (an
     identifier that is not the selected member of a qualified expression) or
     `selector` for the member selected by a `PrefixedIdentifier`,
     `PropertyAccess`, `MethodInvocation` target or cascade, with its full
     **qualifier chain** (for example `_owners.settings` for
     `_owners.settings.startRandom`, `cacheEntry` for `cacheEntry.status`,
     `parsed` for `parsed.channels`); for `lexical` occurrences only, the
     **binding** — `decl:<scope path>#<name>#<ordinal>` for a parameter, local
     variable, local function, loop/catch/pattern variable, or `unbound` when
     no lexical declaration in any enclosing scope declares the name; for
     `selector` occurrences no lexical lookup is done (a selector never binds
     a local); and the role (read, write, read-write, invocation, tear-off).
     Named-argument labels are excluded. **Scoping follows Dart:** the binder
     first collects every declaration of each lexical scope (block, function
     body, `for`/`catch`/pattern scope, including local functions), and only
     then binds references, so a local declared anywhere in a block shadows
     outer names for the **whole** block. A reference that precedes its
     scope's same-named declaration is recorded as `early:<decl>` (the
     analyzer's `referenced_before_declaration`); it is never resolved to an
     outer local or a field, and any `early:` occurrence in a destination is
     rejected (original code has none; step 0 records that).
   - **Alignment.** Destination occurrences are aligned with original ones
     after removing **only registered receiver scaffolding**, and the
     kind/binding classification is computed on the raw ASTs **before** that
     removal, so stripping a qualifier never turns a selector into a lexical
     reference or the reverse. Registered scaffolding is the qualifier
     chains listed in `receiver_paths`/`receiver_owners`
     (`_owners.<record>.`, `_sections.<key>.`) and the live-getter forms
     `_deps.context()`, `_deps.mounted()`, `_deps.setState`, plus the
     registered renames. Any other inserted, removed or reordered identifier
     fails alignment. This runs on the raw destination AST **before** the
     destructive token normalization in `check_settings_moves.py`.
   - **Binding rules per aligned pair.**
     - An original `lexical` + `unbound` occurrence whose name is a State
       field (from the original class member set) must align with a
       destination `selector` whose qualifier chain is exactly its registered
       record path and whose name is the registered new name
       (`_owners.settings.startRandom`), same role and same scope path.
     - An original `lexical` + `decl:` occurrence must align with a
       destination `lexical` occurrence bound to the **same** declaration
       (scope path, name, ordinal): an original local stays a bare reference
       to that local. Replacing it with a qualified field
       (`_owners.settings.startRandom` where the original read the local
       `startRandom`) is rejected.
     - An original `selector` must align with a destination `selector` with
       the same name and the same qualifier chain after registered renames of
       the chain's leading identifier (so `cacheEntry.status`,
       `parsed.channels`, `channel.name` stay untouched even though `status`
       and `channels` are also record member names).
     - A destination `lexical` + `unbound` occurrence whose name is a record
       member is a **bare field reference** and is rejected in every Debrify
       TV file (sections and records; records hold only declarations and
       initializers, and their one getter, `viewerForcesNsfw`, reads no
       field). A `lexical` occurrence bound to a legitimate local or parameter
       of the same name is allowed, and `selector` occurrences are never bare
       references.
   - **Binder fixtures** (adapter self-tests plus real-config checker cases):
     positives — a qualified field beside a same-named local
     (`_owners.settings.startRandom = startRandom` in `_loadSettings`'s
     `setState`), unchanged `cacheEntry.status` (4244) and `parsed.channels`
     (3006, 3010, 3042), a local function declared after its first use in a
     closure body; negatives — a local replaced by a qualified field, a field
     selector replaced by a bare local, an `early:` reference (a moved body
     where a later `final startRandom` in the same block hides the earlier
     use), a later **local function** declaration hiding an outer name, and a
     selector whose qualifier chain changed (`cacheEntry.status` →
     `_owners.session.status`).
   - **Wiring.** `check_settings_moves.py` calls the binder check (opt-in key)
     before normalization; the Debrify TV reader calls the same check before
     returning ORIGINAL text, so a source-text test can never pass over a
     re-bound field.
   - **Negatives** (real config, each must fail, through both the checker
     and the reader): ordinary capture
     (`_owners.settings.startRandom = startRandom` turned into a bare
     `startRandom` that binds the local in `_loadSettings`); balanced
     field/local relocation (swap one field read and one same-named local read
     in `_buildSettingsCard`, counts unchanged); a bare owner-field reference
     inside a record and inside a section; `_owners.library.channels` replaced
     by the `channels` parameter in `_persistImportedZipChannels`. Positives
     cover every record and every hazard method above. The existing
     `spotlight_state_field_bindings` check also stays on for
     `_DebrifyTVScreenState` and `_SpotlightChoiceChipState`.
   These are **checker-level** negatives over moved source; they are not
   original-code behavioural mutations (several cannot even compile on R:
   `startRandom` is a `final` local at 755 and 9150, and the ZIP parameter's
   elements are `DebrifyTvZipImportedChannel`, not `DebrifyTvChannel`). The
   behavioural proxies that *can* run on R are listed in Step 0.5. The guard
   runs at every step from 2.
5. **Receivers and composition.** Sections follow the Spotlight shape:
   `final DebrifyTvDependencies _deps;` with `DebrifyTvOwners get _owners`
   and `DebrifyTvSections get _sections` getters. Cross-section calls are
   `_sections.<section>.<member>` (registered `receiver_paths` and
   `receiver_owners`); the facade reaches sections through its cached
   composition. `DebrifyTvSections` builds every section in its constructor in
   a fixed order; section constructors only store `_deps` and read no owner,
   context or service.
6. **Callback identity** (`torbox_callback_identity.py` /
   `catalog_detail_callback_identity.py` mechanism, receiver path + member,
   with wrapper and same-class receiver-swap negatives) for: the library
   listener register/unregister pair; `watchDebrifyTvChannel` assignment; the
   stored tab-3 handler at register and unregister; `_requestNextChannel` (14
   sites) and `_requestChannelById` (10 sites), both on `_sections.channelWatch`; the 13 `DebrifyTvView`
   callbacks; each `request*Next` argument at its push and native launch; the
   three `onFinished` closures' bodies; `_cancelActiveWatch` inside both
   dialogs' cancel callbacks; the Spotlight debounce `Timer` callback; the
   card, menu and grid `onPressed`/`onSelected` targets. Negatives at each:
   a wrapper closure, a receiver swap to another section, a member swap
   (`requestNextChannel` ↔ `requestChannelById`), and a cached tear-off field.
7. **Verbatim comments.** The checker compares comments; never reword, move
   or drop one, including `// ignore: unawaited_futures` (4447), the section
   banners (`// ===================== Prefetcher =====================`) and the
   trailing comments on fields and consts. A section banner travels with the
   first member below it.
8. **Shape.** The file is in **`kShapeResidue`** (the swept map) at 7, but
   has **0** bare radii by the test's regex and **16 `app.shape.br` tokens**;
   the 488-token floor is **exactly met today (zero margin)**. From step 1:
   lower the facade entry to 0; register every destination that receives a
   token in **`kShapeResidue`** with residue 0 (meta pill 1, choice chip 1,
   share 1, top bar 4, grid layout 4, grid cards 4, settings card 1 = 16) and
   every other destination in `kExtractedShapeResidue` with 0 (never in
   `kShapeResidue`, whose swept test needs a token). Move the facade from
   `kShapeResidue` to `kExtractedShapeResidue` in the commit that removes its
   last token (step 7). At every checkpoint the slice holds 16 tokens and 0
   bare radii, and the floor test passes.
9. **Theme.** `theme_surface_manifest.txt:24` (`p2_debrify_tv`, 19 files,
   18,002 lines, **228 sites**) gains explicit per-directory patterns
   `lib/features/debrify_tv/application/*.dart`,
   `lib/features/debrify_tv/models/*.dart`,
   `lib/features/debrify_tv/presentation/*.dart`,
   `lib/features/debrify_tv/presentation/legacy_debrify_tv/*.dart` (no `**`).
   Sites must stay 228 at every step. `theme_rendered_set.py` keeps its root
   (the import walk reaches the feature). `light_ink_inventory.py`:
   Debrify TV is not `PRIMARY`; no change (verify).

## Steps

| # | Work | Contracts |
| --- | --- | --- |
| 0 | Baseline `base`; format idempotence (no format commit); strict and rename probes; dependency report; manifest, config and handoff ledger; harness, characterization tests, per-declaration source reader, source-test switch, `fetch-depth: 0` for the behaviour job with the shallow-clone proof, macOS goldens (two reversed-order captures); checkpoint (b); CI list; source-text inventory; Linux capture script | Nothing moves |
| 0b | Independent review; original-only mutation proofs; compiling-composition probe with the real checker and facade measurement; `base2` at (b) | Nothing moves |
| L | **Prerequisite before step 2:** supplied Linux originals hash-verified, committed separately, Linux golden test made strict | Goldens |
| 1 | Guard registration (feature, bridge, D1 pair, size-exception placeholders, bans); models; application helpers; import parsing (compute entrypoints); shape/theme registrations begin | Surface, 6 (compute) |
| 2 | Owners: 78 fields → 7 records, eager; bindings; composition with its first consumer (the lifecycle); lifecycle and `build` verbatim with receivers; field-binding guard live for all fields; temporary facade ratchet raise recorded | 1, 2, 4 (field binding) |
| 3 | Choice chip and meta pill; feedback/progress; settings loader; engine limits; playback filters; channel library; Spotlight stage | 2, 3.6, 4, 7, 8 |
| 4 | Channel management: warm-up, editor, actions, save, share, export, device/community import, URL import (D1), formats, persistence | 5, 6 |
| 5 | Provider resolvers (TorBox; PikPak + Premiumize); prefetch; player handoff (native + external); dormant | 3.3, 3.5, 3.7 |
| 6 | Playback flows: `_watch` (exception file), four quick-play providers, channel watch, channel switch (exception file), five cached flows. **Full-suite gate 1** | 3 (all), 4, 10 |
| 7 | Paint: settings chips and card, dialogs, top bar, grid layout, grid cards; the facade keeps only lifecycle, `build` and composition; facade leaves `kShapeResidue` | 8, 9 |
| 8 | Composition final; facade registration, cap and `TEMP`; real-checker negatives; CI format/analyze paths; final evidence. **Full-suite gate 2** | All |

### Step 0

1. **Baselines.** `debrify_tv/base` on the untouched worktree head:
   `suite_evidence.py run debrify_tv/base --no-pub --concurrency=<n>` plus the
   whole-repo analyzer (`flutter analyze --no-pub`), with tree and SDK
   provenance. Record `format-idempotence.json` for R (Technique 1).
2. **Dependency report** (`docs/refactoring/debrify-tv-deps.md`). For every
   leaf (78 fields, 15 statics, the getter, every method, the 21 top-level
   declarations — 19 outside the retained widget and State —
   declarations, comment fragments and banners) it records the destination;
   reads of `context` (State or lexical), `mounted`, `setState` (State or
   shadowed); every field read/write with its record and new name and every
   same-named parameter or local in the destination method (Technique 4);
   tear-offs and closures handed outside the State; timer/delay owners; and a
   per-entry wiring-checklist entry, reviewed before any scaffold is pinned.
   It copies the inventory tables produced with this plan (handoff sites,
   delays, resources, hooks, diagnostics).
3. **Checker.** `dev/tool/debrify_tv_manifest.tsv` (LF only; check the staged
   diff), `debrify_tv_checker_config.json` (`baseline` R, `source`
   `lib/screens/magic_tv_screen.dart`, `feature` `lib/features/debrify_tv`,
   `engine` `sections`, `context_guard` true, receivers `_deps`, `_owners`,
   `_sections`, `live_getter_callbacks` `context`/`mounted`,
   `lexical_state_setters`, `spotlight_state_field_bindings`,
   `occurrence_field_bindings` (Technique 4; consumed by the checker and the
   reader), `scaffolds` (the three registered scaffold files, below),
   `callback_identities`, `lifecycle` for `initState`/`dispose`/`build`,
   `type_renames`, sidecars), `debrify_tv_checker_test.py` with
   **real-config** fixtures and `self_test_module`. Negatives (each must
   fail): a reordered or dropped `dispose` step; `_stopPrefetch()` awaited in
   `dispose`; a dropped `notifyPlayerLaunching` at any of the 15 sites; a
   reordered `_startPrefetch`/`_closeProgressDialog` pair in P1, P2 and P12;
   a changed provider set in any `requestNextChannel` condition; a channel
   option swapped for its quick twin (and back) at P3 and P11; a removed
   `_watchCancelled` check; the 5 s cooldown changed; the 250 ms debounce
   changed; the debounce cancel moved after the memo return; the export
   `runIfCurrent` wrapper dropped; a compute entrypoint turned into a closure
   or instance method; a cached `viewerForcesNsfw` value; a section built per
   build or per access; a reworded comment; a new `const`; plus the
   callback-identity, lexical-setter, context and field-binding negatives
   (Technique 3, 4, 6).
4. **Harness** (`test/support/debrify_tv_fixture.dart`, after the debrid and
   catalog fixtures): mocked `SharedPreferences`; `ProfileRuntime` init and
   reset, with an adult and a child profile; `SecretVault.debugReset(
   deviceIdOverride: 'debrify-tv-characterization')` and provider keys set
   through the storages; `sqflite_common_ffi` in-memory Debrify TV database
   seeded through `DebrifyTvRepository`/`DebrifyTvCacheService` (the
   `profile_debrify_tv_database_isolation_test.dart` setup);
   `PlatformUtil.debugSetTvOS`/`debugSetAndroidTvCached` reset in teardown
   (on the host `AndroidNativeDownloader.isTelevision()` returns false unless
   `PlatformUtil.isTvOS`, `android_native_downloader.dart:400–401`, so the TV
   cases set the tvOS override and accept its other tvOS effects, such as the
   export refusal); a method-channel mock for
   `com.debrify.app/android_tv_player` (the bridge returns false before
   invoking it on a non-Android host); `http.runWithClient` with a
   recording `MockClient` for `DebridService`, `TorboxService`,
   `PremiumizeService`, `AllDebridService`, the URL import and community
   downloads (step 0 confirms each uses package-level `http` calls; any that
   build their own `IOClient` get the catalog `HttpOverrides` transport
   pattern in a Debrify-TV-owned support file); a fake `FilePicker.platform`;
   a Clipboard mock; `MainPageBridge` probes (`hideAutoLaunchOverlay`,
   `focusTvSidebar`, the content-focus request) reset in teardown;
   **a fixture search engine installed through production storage**: the
   fixture writes one engine YAML (keyword search, `tv_mode` enabled, one
   page, fixed result mapping) with `LocalEngineStorage.instance.saveEngine(…)`
   (the `addon_hub_engines_test.dart` precedent, 238/275/407), then awaits
   `EngineRegistry.instance.reload()`; `ConfigLoader.loadEngineConfigs`
   reads it from `getAllEngineFilePaths()`. Its HTTP goes through
   `engine_executor.dart`'s package-level `http.get`/`http.post` (577 onward),
   so the same recording `MockClient` under `http.runWithClient` serves
   deterministic search results. No registry seam is added; quick-play search
   is therefore **observable** (O), not source-only;
   `DebrifyTvStorage` style mirror set before mount for Spotlight cases;
   pinned `tester.view` size and DPR; `AppThemeScope` with a pinned look.
   **The player-route interceptor:** a `NavigatorObserver` records each
   pushed `MaterialPageRoute`, extracts the `VideoPlayerScreen` by invoking
   the route's original builder (unwrapping `LegacyThemeBoundary` →
   `Builder`) with a live element as context, and removes the route **before
   the next frame**, so the player never mounts and the flow's `await push`
   resumes as if the player exited. Prove the interceptor on R first (one
   fixture), as the Spotlight plan requires. **No `pumpAndSettle`**: the
   250 ms debounce, 100 ms polls, 2 s summary hold and 5 s cooldown use fake
   time; IO runs inside `runAsync`. January UTC dates; braces in tests.
5. **Characterization tests**, under
   `test/features/debrify_tv/presentation/legacy_debrify_tv/`, written
   against R and **frozen in (b)**; each passes in a detached worktree of (b)
   before any extraction. Every case names its evidence class: **(R)**
   rendered, **(O)** observable reads/writes (MockClient requests in order,
   DB rows, prefs, clipboard, bridge probes, captured player arguments),
   **(S)** source/checker evidence. Negatives ("does not publish", "no push
   after cancel") use **held** responses released after the trigger.

   | Contract | Coverage |
   | --- | --- |
   | C1 Lifecycle | After mount: `watchDebrifyTvChannel` set, content-focus request focuses Quick Play (R/O); after unmount: `watchDebrifyTvChannel` null (O), a running prefetch issues no further request (O), focus/controller disposal and `clearTorboxProvider` (S); `initState`/`dispose`/`build` bodies (S). |
   | C2 Hooks | `HomeHeroShellBridge.playSavedDebrifyChannel(id)` with the screen unmounted stores the id; mounting starts that channel after the post-frame wait (O); the same call while mounted goes through `watchDebrifyTvChannel` and starts it (O); unknown id does nothing (O); `notifyDebrifyTvLibraryChanged()` after a DB change shows the new channel and clears stage stats (R). Listener **detachment after unmount is unobservable** (the retained callback returns on `!mounted`, 1061–1062), so register/unregister identity is (S) with checker mutations (unregister call dropped; a different tear-off receiver). |
   | C3 Playback handoff (RD channel, P5) | Seeded channel + RD `MockClient`: Tune in → `CachedLoadingDialog` shown (R) → add/info/unrestrict requests in order (O) → dialog closed **before** the push (O: observer order) → captured `VideoPlayerScreen` fields equal the P5 ledger entry (Contract 3.11) field by field, with unlisted parameters at their constructor defaults, including `requestNextChannel` present only with >1 channel and an allowed provider (O) → invoking the captured `requestMagicNext` resolves the next queue item (O) → after the interceptor removes the route, `_stopPrefetch` ran (no further prefetch request) and the busy state cleared (R/O). |
   | C3 other flows | TorBox (P7), Premiumize (P10), AllDebrid (P6) channel flows and quick-play TorBox/Premiumize/AllDebrid (P3, P11, P12) with their MockClient sequences and captured arguments compared field by field with the ledger (Contract 3.11), including the channel-vs-quick option sets (O). **Separate quick-play RD fixtures:** P1 — the fixture engine returns a playable result, so the early launch fires from closure #1 (O: push before the search loop ends, `firstTitleResolved`, `activeChannelDirectory`, the Premiumize-inclusive `requestNextChannel` set); P2 — a quality filter no result matches, so every per-batch queue is empty, the end-of-search fallback (4886–4895) fills the queue and closure #2 launches (O: fallback snackbar, then push with `firstTitle`, `quickChannelDirectory` and the Premiumize-exclusive set). PikPak flows (P4, P8) are (O) if `PikPakTvService`/`PikPakApiService` resolve through package `http` under the fixture (step 0 proves it), else (S) with the reason recorded. |
   | C3 native TV | With the tvOS override (so `_isAndroidTv` is true): `AndroidTvPlayerBridge` returns false on the non-Android host, so the flow clears the provider and falls back to the Flutter push, and `hideAutoLaunchOverlay` fires once from the native attempt and once before the push (O); bridge arguments and `onFinished` bodies (S). Without the override `_isAndroidTv` is false and the native arm is skipped (O). |
   | C3 external | External player as default: notice declined → no push, prefetch stopped, flow ends (O); accepted with a failing launch → in-app push follows (O). |
   | C3 cancel (honoured) | In the paths that check `_watchCancelled` — quick TorBox, quick Premiumize, quick AllDebrid, `_watch` early launch (closure #1) and cached PikPak where served — Cancel while the resolve is held pops the dialog and clears the queue and busy state; after release there is **no push** (R/O). |
   | C3 cancel (late launch, as-is) | Cached RD: Cancel while `unrestrictLink` (6070) is held pops the dialog and clears the queue; after release the closure returns the stream (6091), may re-add the torrent to the cleared queue, restarts the prefetcher and **pushes the player** (O: captured push after cancel). This characterizes the original late-launch behaviour (Found, not fixed); the same holds for the other cached flows without a `_watchCancelled` check, which are (S). |
   | C3 switching | Invoke the captured `requestNextChannel()` with 2 channels under fake time: no result before 5 s, then the map with the five keys for the next channel and `isCurrent` moved in the directory of the next launch (O); Premiumize returns null (O). |
   | C4 Settings | The global settings dialog renders the seeded provider, start-random switch and (when on) slider value (R). The **two live option controls**: toggling start-random writes `saveDebrifyTvStartRandom` and moving the slider writes `saveDebrifyTvRandomStartPercent` (O: prefs re-read). Quick-scope values change **without persistence**: Play now in the quick-play dialog copies the channel options and the NSFW choice into the quick set, and afterwards no `DebrifyTvStorage` key changed (O) while the captured P4/P12 player fields carry the copied values (O). Settings the dialog does not render (`hideSeekbar`, `showChannelName`, `showVideoTitle`, `hideOptions`) are observed only through captured player fields after seeding prefs (O); the unused/no-op setters and the unreachable quick/NSFW branches of the card are (S). Reset writes exactly the original keys (O); provider chips disabled when unavailable and default resolution by availability (R); filter chips persist and invalidate stage stats (O); a child profile forces NSFW on, and the switch is inert, in the channel editor and quick-play dialog (R). |
   | C5 Library | Grid renders seeded channels with favourites first (R); favourite toggle persists (O); delete and delete-all with confirmation, including cancel (R/O). |
   | C6 Import/export/share | Device import of `.zip`, `.yaml`, `.txt`, `.debrify` and an extension-less PK file through the fake picker → DB rows and summary text (O/R); text limits (120 chars, 500 keywords) and empty file messages (R); URL import with MockClient 200 (progress text, persisted) and 404 (error) (O/R); community import of two channels with one failure (O/R); share: copied link decodes to the exact YAML (O); export on tvOS shows the refusal (R); export selection reaches the save step with the captured profile (O where the save platform can be mocked, else S). |
   | C7 Editor | Validation messages; comma and Enter keyword entry; the 1000 cap message (R); edit with removed keywords prunes the cached pool without network (O); NSFW change forces a full rebuild path (O or S). |
   | C8 Spotlight | Style `spotlight` mounts `SpotlightLayout` with Quick Play as entry node (R); a rail focus computes stats only after 250 ms (fake time) (R); gliding B→A with A memoised cancels B's pending timer (R). |
   | C9 D-pad | Top bar Left → sidebar probe, Right/Up traversal, activate (R/O); search Escape ladder (clear, then close and refocus) (R); menu open by Select and closed by Escape with focus restored (R); channel card long-press opens the options menu (R); choice chip KeyRepeat moves focus (R). |
   | C10 Field binding (behavioural proxies) | Behaviour that a lost field write would change: after `_loadSettings`, the rendered settings (provider, start-random, slider percent) and, through captured player fields, the unrendered ones (`hideSeekbar`, `showChannelName`, `showVideoTitle`; `hideOptions` is hard-coded false) carry the stored non-default values (R/O); `_syncProviderAvailability` toggles chip availability when a key is added (R); the two live setters (`setStartRandom`, `setRandomStartPercent`) change their own field's rendered and persisted value (R/O). The dead and no-op setters are (S). The ZIP **append before reload** (3431–3436) is not observable: `_loadChannels()` immediately republishes the persisted rows and no existing boundary holds that read, so the append is (S), pinned by the occurrence-level binding guard and a source guard on the exact `setState` body. |

   **Mutation proofs** come in two kinds, recorded separately.
   - **Behavioural (ORIGINAL) proxies** (`original-mutations.json`): named,
     *compilable* mutations of R's application code, applied in the detached
     original and each rejected by an **assertion** (never a compile error),
     with original/mutated hashes and logs; every new behavioural identity is
     covered by at least one. Required: an option-set swap at P5 (channel →
     quick) and at P3 (channel → quick), each run on a fixture that makes the
     two sets **differ** through existing live controls, because
     `_loadSettings` initialises both sets equally and Play now copies channel
     → quick (9490–9500):
     - **P5:** after mount, toggle start-random in the global settings dialog
       (channel scope, `setStartRandom`) so `_startRandom != _quickStartRandom`,
       then tune a channel; the named assertion "P5 passes the channel
       `startFromRandom`" fails under the swap.
     - **P3:** in the Spotlight style, start quick play (Play now copies
       channel → quick), hold the TorBox cache-check response, then invoke the
       still-live `DebrifyTvView.onSettings` callback read from the mounted
       `SpotlightLayout` (the existing `_showGlobalSettingsDialog`, no seam),
       toggle start-random and close the dialog, then release; the named
       assertion "P3 passes the channel `startFromRandom`" fails under the
       swap. Step 0 proves this boundary on ORIGINAL; if the stacked dialog
       cannot be driven, the P3 channel→quick expression swap is reclassified
       **S** (checker/ledger negative) and the behavioural coverage for P3 is
       a wrong-value mutation instead (`startFromRandom: !_startRandom` at
       5584), which the same named assertion rejects on the ordinary fixture; `requestNextChannel` always null at
     P5; the P5 prefetch start moved after the push; `_closeProgressDialog()`
     removed before the P5 push; **every** `_watchCancelled` check in quick
     TorBox removed together — all **17** occurrences in `_watchWithTorbox`
     (5231–5622): 5437 `if`, 5440 `while (!…)`, 5448 `&& !…`, 5467 `if`, 5476
     `if`, 5480 `&& !…`, 5487 `if`, 5501 `if`, 5505 `&& !…`, 5508 `&& !…`,
     5515 `if`, 5522 `&& !…`, 5531 `if`, 5536 `&& !…`, 5568 `if`, 5575
     `if (!…)`, 5605 `&& !…`, each replaced by its not-cancelled value
     (`false`, `true`, or the conjunct dropped), so the held prepare's result
     reaches the push (any single or partial removal is masked by the
     remaining checks, so those are guard mutations, S);
     the 5 s cooldown set to
     0; the debounce cancel moved after the memo return; a dropped field
     assignment in `_loadSettings`'s `setState` (e.g. `_startRandom =
     startRandom;` removed) and a settings-card setter writing the wrong scope
     (the proxies for capture, which cannot be written as `startRandom =
     startRandom` because the locals are `final`, 755 and 9150); NSFW not
     forced for a child profile; Reset writing an extra key; the 120-character
     limit off by one; `watchDebrifyTvChannel` not nulled in `dispose`.
   - **Checker/guard mutations (S)** over moved source, for what no host test
     can observe: the library listener's unregister call dropped or given a
     different receiver (unobservable: the callback returns on `!mounted`);
     the tab-3 handler unregistered with a new closure; the post-native
     `if (_watchCancelled) return;` (10727) removed (masked by the guarded push
     and status update that follow); the ZIP append replaced by assignment
     (masked by the reload); `_persistImportedZipChannels` capturing the
     `channels` parameter and the `_loadSettings` capture (both non-compiling
     on R, so checker-only); native bridge argument changes. Each is rejected
     by the manifest checker, the occurrence-level binding guard or the
     callback-identity checker, and is classified **S** in the case table.
6. **Goldens** (macOS captured by execution in (b), Linux by Claude; strict
   from capture). Scenes: **(1)** grid, TV 1920×1080, `isTelevision` true,
   six channels with two favourites, focus on Quick Play; **(2)** grid,
   phone 390×844, search bar open with a term matching three channels;
   **(3)** empty state, desktop 1280×800; **(4)** Spotlight style, TV
   1920×1080, rail focus on the second channel after the 250 ms debounce with
   a **ready one-torrent cache per channel stored with `fetchedAt: 0`** (the
   stage sample is a `shuffle`, so a larger pool is not deterministic; and the
   stage's freshness text calls `DateTime.now()`
   (`lib/screens/debrify_tv/layouts/spotlight_stage.dart:480`), while
   `_computeSpotlightStats` maps `fetchedAt <= 0` to `null` (8080–8082), which
   renders the fixed "never"); the test asserts the stats are populated and
   "never" is visible before capturing; **(5)** global settings dialog (channel
   scope), TV; **(6)** channel editor (edit, three keyword chips, child
   profile with NSFW forced), phone. Scenes (1), (4) and (5) set the tvOS
   override so `_isAndroidTv` (long-press hint, slider mode, autofocus) takes
   its TV value. All scenes: no network images (the
   screen draws none), the golden helpers' fonts including JetBrainsMono, DPR
   1.0, pinned theme, `en-US`, text scale 1.0, a named initial focus or none,
   bounded fixed pumps, no wall-clock text. **Readiness and order
   independence:** each scene asserts its readiness markers (channels
   rendered, intended focus owner, dialog fully shown, stats present) before
   capture; the macOS originals are captured **twice in independent
   processes, the second in reversed scene order**, and both sets must be
   byte-identical (the Episodes Progress precedent) before (b) is committed;
   the Linux capture script does the same in the container.
7. **CI list and pre-existing failures.** Add every new test and the golden
   test to `ci_behavior_tests.txt` (the facade has no test importers; the two
   source-text tests are already listed at 48 and 50). Add **only failures
   `base` actually observes** in newly listed files, by identity, in the same
   commit, under `# 2026-10-05 debrify_tv step 0: pre-existing, newly exposed
   by CI coverage; observed in debrify_tv/base`. A test passing in `base` must
   keep passing.
8. **Source-text inventory.**
   - **Reader** (`test/support/debrify_tv_source.dart` +
     `dev/tool/debrify_tv_source_reader.py`). Ownership is resolved **per
     declaration** from the manifest by **AST declaration presence**, not
     file existence: for each row the reader parses the destination file (if
     any) and the facade; the declaration is owned by the destination when
     its destination class/member is declared there, else by its retained
     original declaration in the facade. A row declared in **both** places is
     duplicate ownership and rejected; a row declared in **neither** is missing
     and rejected. Several rows retained in one facade declaration (fields of
     one statement, or members still in the facade) dedupe to one location.
     Files under `lib/features/debrify_tv/` must each own at least one
     manifest declaration **or** be one of the explicitly registered scaffold
     files (`scaffolds` in the config: `debrify_tv_bindings.dart`,
     `debrify_tv_owners.dart`, `debrify_tv_sections.dart`, each with its
     pinned scaffold declarations, as `check_settings_moves.py`
     `destination_ownership` does, 800–815); any other file is rejected. Once
     `DEBRIFY_TV_COMPLETE` is true, every final destination must own its
     declarations. Tests cover: ORIGINAL (everything in the facade); a partial
     layout; the completed layout (simulated); a **scaffold-only destination**
     (scaffold files present while every declaration is still in the facade,
     the step-2 shape); a **mixed file** (a destination owning some moved
     declarations while sibling rows of the same file are still retained in
     the facade); and each rejection (duplicate, missing, unregistered extra
     file, scaffold declaring a manifest leaf).
     `debrifyTvOriginalSource()` returns the **raw ORIGINAL text** (from the
     baseline, whitespace and comments preserved), but only after the
     checker's AST token comparison proves every current declaration equals
     its original under the registered substitutions **and** a
     **physical-source guard** proves that indentation-sensitive blocks are
     physically unchanged in their current location: the
     `if (e is NativePlayerSettingsUnavailable) {` / `_showNativeSettingsFailure(e)`
     / `return;` block of `_watch` (4906–4908) is compared line by line
     with its original leading whitespace reproduced exactly (the body moves
     at the same nesting depth, so its indentation is unchanged; the
     receiver-qualified call is compared through the registered rename). The
     Spotlight reader's whitespace-stripped return (`spotlight_board_source_reader.py:106`)
     is **not** reused for this.
   - `test/native_player_settings_wiring_test.dart:17` reads the file by
     path; its counts (3 `rethrow`, 10 `on NativePlayerSettingsUnavailable
     catch (error)`) and the exact 8-space-indented
     `_showNativeSettingsFailure(e)` string would break when `_watch` moves.
     In (b), replace **only** the `File(...).readAsStringSync()` with
     `debrifyTvOriginalSource()`; every expectation stays byte-identical.
     Reader negatives (run against simulated moves) prove the expectations
     still bite: a moved `_watch` with one `rethrow` deleted, one catch
     deleted, the failure block re-indented by two spaces, or the call renamed
     to another member each make the reader fail (or, for a change the reader
     would accept, the existing expectation fail); none passes.
   - `test/theme/source_guard_test.dart`: in the `allowed` set (48–52),
     replace **only** the `'lib/screens/magic_tv_screen.dart'` entry:
     ```dart
     final allowed = {
       'lib/screens/video_player_screen.dart', // itself
       'lib/features/player_launch/presentation/legacy_launch/video_player_launch_widget.dart', // the shared factory
       ...debrifyTvSourceFiles(),
     };
     ```
     where `debrifyTvSourceFiles()` is the set of files that currently own a
     Debrify TV declaration under the reader's ownership rule (only the facade
     at (b)). The player screen and the shared factory stay allowed, and the
     factory's existing single-construction assertion is unchanged. One new
     assertion applies **only to `debrifyTvSourceFiles()`**: every
     `VideoPlayerScreen(` there is the `builder:` result of a
     `videoPlayerRoute(` call. The `MaterialPageRoute` test (80–90) reads the
     current text of the same Debrify TV files. Lines 118, 185 and 228 keep naming the facade (it
     still defines `DebrifyTVScreen`). No assertion is deleted or weakened.
   - **CI history for reader-based tests.** The reader loads ORIGINAL with
     `git show <R>:lib/screens/magic_tv_screen.dart`, like the Spotlight
     reader (`spotlight_board_source_reader.py:116`), but the
     `sources-behavior` job's `actions/checkout@v4` (`checks.yml:67`) uses
     the default `fetch-depth: 1`, so R is absent in CI. In the (b) commit,
     set `fetch-depth: 0` on that checkout (R is an arbitrary older commit on
     the refactor history, so no smaller fixed depth is reliably sufficient).
     This also supplies the history the already-listed Spotlight reader test
     (`spotlight_board_source_contracts_test.dart`, CI list 270) needs. Prove
     it locally: in a fresh `git clone --depth 1 file://…` of the (b) commit
     the reader test fails with a missing-object error; after `git fetch
     --unshallow` (the equivalent of `fetch-depth: 0`) it passes. Record both
     logs. (A committed ORIGINAL snapshot with a provenance hash was
     considered and rejected: it duplicates 11,271 lines and adds a second
     source of truth.)
   - Shape and theme: Technique 8–9. `file_size_baseline.txt:5` is lowered as
     the facade shrinks (removed below 800) and gains the `_watch` file by
     hand (Size exceptions); the step-2 intermediate growth from receiver
     qualification is a recorded, hand-raised ratchet (the Spotlight step-3
     precedent).
   - **Verify unaffected:** `test/profiles/profile_source_guard_test.dart`
     (its known "direct SharedPreferences opens" failure stays known),
     `test/profiles/isolation_suite/stale_runtime_guard_test.dart`,
     `test/theme/legacy_pins_test.dart`, storage checks
     (`check_storage_keys.py`, `check_storage_references.py --self-test`).
   - `checks.yml` (step 8): add the facade to the format (45) and analyze (52)
     lists and `test/support/debrify_tv_*` to the format list. **Insert paths
     before `| tee analyze.txt`, never after it.** Design docs that name the
     path stay as they are.
9. **Linux capture script** (`dev/tool/capture_debrify_tv_linux_goldens.sh`,
   `set -euo pipefail`, checks Linux and Flutter 3.44.8): resolves checkpoint
   (b) by its exact subject and R by SHA or exact subject, requires equal
   `lib`, `pubspec.yaml` and `pubspec.lock` objects, captures **twice** — a
   first pass in scene order and an independent reverse pass in reversed
   scene order, each in its own process with its own log
   (`linux-original-capture-first.txt`, `linux-original-capture-reverse.txt`)
   and SHA-256 list (`linux-original-sha256-first.txt`,
   `linux-original-sha256-reverse.txt`), failing unless the lists are
   identical — in a
   detached worktree of (b) using only (b)'s tests, verifies strictly, copies
   PNGs and writes the first/reverse capture logs and hash lists above plus
   `linux-original-{strict,revision}.txt` under
   `refactor-evidence/debrify_tv/`. Never `awk '{…; exit}'` or `head` in a
   pipeline under `pipefail` (SIGPIPE); use `git log -1 --format=%H
   --grep=…` or capture to a variable.
10. **Step 0 checks:** all 15 integrated manifests (vpl, settings, iptv,
    torbox, debrid, pikpak, playback_settings, iptv_settings,
    playlist_content, merged_detail, addon_hub, detail_showcase,
    spotlight_board, episodes_panel, catalog_detail) with self-tests, each
    with **its own config and original baseline** and an isolated parser
    package, plus this one against R; architecture, sizes, storage, shape,
    theme, light-ink, CI format, scoped analyzer with allowlist, strict
    comparison, staged diff. Commit the checkpoint with the exact subject.

**Step 0b review** (before any extraction). Two separate proof runs on (b):
- **Behavioural proxies against ORIGINAL.** Each mutation in
  `original-mutations.json` is applied to R's application code in the detached
  original worktree; the **entire** characterization files run (no name
  filtering), and the run must fail on the **named behavioural assertion**
  the mutation targets (recorded per mutation: test name, expectation and
  failure message). A compile error, a harness crash, or a reader/source-guard
  rejection does not count as evidence for a behavioural proxy.
- **Guard mutants against simulated moved source.** Each S mutation is
  applied to a simulated moved layout (one per section kind: lifecycle, a
  flow with a closure, a dialog with a shadowed setter, a paint builder with
  lexical contexts, a record with hazard fields), and must be rejected by the
  named guard (manifest checker, occurrence binding guard, callback-identity
  checker or reader); the unmutated simulated layouts pass. Results are
  recorded separately (`step0b-behavioural-proxies.json`,
  `step0b-guard-mutants.json`). A **compiling-composition probe** on a
throwaway branch of (b) builds the facade, owners, bindings, composition and
one stub section of each kind, compiles under the strict config with no new
warnings, runs the **real manifest checker** through its CLI wrapper
(`python3 dev/tool/check_verbatim_moves.py --manifest
dev/tool/debrify_tv_manifest.tsv` with the Debrify TV config, baseline R, an
isolated `--parser-package` and `--self-test`), and measures the facade per
span. Record `base2` at (b) (only passing additions versus `base`). Claude
reviews the probe before step 1.

### Step L — Linux originals

Claude runs the script in the calibrated `debrify-flutter:3.44.8`
linux/amd64 image (Colima) from a clone at (b), verifies `HEAD` and the
hashes, and hands over the PNGs and evidence. Execution verifies hashes and
provenance and commits them separately with
`linux-original-verification.json`. From then on the Linux golden test is
strict (no missing-file skip, no opt-out define). No golden is ever generated
or updated against moved code.

### Per step and gates

The Spotlight procedure applies with `--baseline <R>` and
`--relocate lib/screens/magic_tv_screen.dart=lib/features/debrify_tv/`; these
apply only to the Debrify TV checks. Every step runs: per-entry wiring review
before pinning; all 15 manifests plus this one with self-tests and isolated
parser packages; the field-binding, lexical-setter and callback-identity
checks; the per-symbol relocation comparison (zero additions beyond the
probe inventory); architecture, sizes (lowering the facade ratchet, and from
step 2 the facade breakdown), storage references; shape (16 tokens, 0 bare
radii, floor ≥ 488) and theme (228 sites); CI format and scoped analyze with
allowlist; LF manifests; staged diff; all characterization tests against the
latest `debrify_tv/` base; strict macOS and Linux goldens.

Gates run serially on committed trees with no untracked inputs, against the
latest base; gate 2 also compares against gate 1. A first gate failure is
investigated as a possible extraction regression with original/current
causal proofs (the Spotlight 4b precedent) before any flaky acceptance; an
unrelated flake is accepted on rerun only after original and current replays
with the input closure hashed. Never `--record` or `--update` to accept a
regression.

### Integration (Claude)

Claude merges the branch and integrates these shared files **semantically,
by union**: `check_search_architecture.py` (feature, bridge, D1 pair, size
exceptions, generalised 800 ceiling, facade path in `main()`,
`COMPOSITION_ROOTS`, cap, `TEMP`), `check_settings_moves.py` and the shared
source-reader helper (the opt-in `lexical_state_setters` key), the
callback-identity helper, `shape_manifest_test.dart`,
`theme_surface_manifest.txt`, `ci_behavior_tests.txt`,
`ci_behavior_known_failures.txt`, `analyzer_allowlist.txt`, `checks.yml`
(including the behaviour job's `fetch-depth: 0`), the new opt-in
`occurrence_field_bindings` helper and its **adapter change** in
`dev/tool/verbatim_ast.dart.txt` (the declaration/scope binder output, emitted
only on request; every other manifest's adapter output and self-tests must be
byte-identical before and after), the reader's `scaffolds`/ownership rules,
`file_size_baseline.txt`, `test/theme/source_guard_test.dart` and
`test/native_player_settings_wiring_test.dart`. Merge rules: union and dedupe
registrations, exceptions, CI paths, known failures, theme patterns and shape
entries; keep every `*_COMPLETE = True`; take the lowest verified size
ceiling; keep `checks.yml` paths before `| tee`; review the checker extension
as a shared-tool change (opt-in only; every other manifest's self-tests
unchanged). Then, on the merged committed tree, rerun every manifest with
self-tests, architecture, size, shape and theme, CI format and analyze, and a
full-suite comparison reconciling identities against each branch's bases.
Remote CI stays pending until a push is approved.

## Definition of done

1. **Facade.** Formatted, within its measured cap (target 300, hard maximum
   450, every physical line counted), breakdown recorded. It holds
   `DebrifyTVScreen` byte-identical and `_DebrifyTVScreenState` with the
   eager owners, the cached composition, the verbatim lifecycle and the
   verbatim `build` forwarder. `lib/main.dart` compiles unchanged.
2. **Guard.** The feature, exact bridge, D1 pair, both size exceptions, the
   generalised ceiling, the facade in `main()` and `COMPOSITION_ROOTS`, its
   cap and `TEMP(debrify_tv)`, and the import/playback bans, each proven
   through the real checker. Every other destination is at most 500 lines.
3. **Tests.** All manifests pass with self-tests. Every characterization test
   and source guard from (b) passes unchanged; the two pre-existing source-text
   tests keep every original expectation. macOS and Linux goldens match the
   originals.
4. **Diagnostics.** No new warning or suppression; the surviving original
   warnings are allowlisted by destination identity; every info maps to an
   original or probe-inventoried identity; removed identities are listed.
5. **CI.** Local CI-equivalent checks pass; behaviour list holds the new
   tests; known failures gain only observed identities; shape slice 16 tokens
   with the floor met and the facade at 0; theme 228 sites.
6. **Progress** records R, (b) and each step's commit, ownership, exceptions
   with exits, cap arithmetic, and lists as **pending device verification**:
   Android TV native launch for RD/TorBox/PikPak/Premiumize/AllDebrid with
   channel switching and `onFinished` teardown; the external-player notice;
   D-pad on a real remote (hold/repeat, sidebar exit, menu); remote/home
   auto-play; and remote CI.
7. **Gate 2** passes against the latest base and gate 1. Then stop and report.

## Explicitly not in scope

`video_player_screen.dart`, `lib/screens/video_player/`, `AndroidTvPlayerBridge`,
`VideoPlayerLauncher`, `MainPageBridge`, every Android/Kotlin/Java and tvOS
file; `lib/screens/debrify_tv/` layouts, dialogs and widgets; models and
services; `lib/main.dart`; Riverpod, data contracts, localization, a
TV-capability adapter; behaviour fixes and dead-code removal (the unused
members stay verbatim, D4); the quick-play and channel-switch
decompositions; adding stale-result or profile guards; everything below.

## Progress

### Step 0 — ORIGINAL characterization checkpoint (b), 2026-10-05

Execution base **R = `991029f64a6e4ce27b68626ac4537bf9f38f483c`** on
`refactor/debrify-tv`, exclusively in the dedicated Debrify TV worktree.
`flutter pub get` ran here first; Flutter **3.44.8**, Dart **3.12.2**, lockfile
unchanged. All three Round review resolutions and the four series precedents
were read. Format idempotence is **11,271 lines, zero changes**; no format-only
checkpoint or production seam was needed. The checkpoint is resolved by its
exact subject, `test(debrify-tv): step 0 original-code characterization checkpoint`;
its SHA and object-equality proof are recorded in `step0-checkpoint-provenance.json`.
`lib`, `pubspec.yaml`, and `pubspec.lock` equal R's objects respectively:
`c9e3c1c3dbdce72dc3205fe04ae1444d0e920e49`,
`5f983ff8c68a01aef5c7a1ec393e677e7693591f`,
`e0ff9cca69c00ae69bb4dfe111c18a89547cec98`. No application, player, bridge,
launcher, Android, iOS, or legacy TV source was changed.

Evidence lives only in the common Git directory's
`refactor-evidence/debrify_tv/`. `base.env.json` records a committed, clean R
input tree, paths `[]`, flags `--no-pub --concurrency=4`, and SDK identity.
The serialized full original suite completed: **11,562 success, 13 failure,
28 error, 20 skipped**. Exact identities are in `step0-test-identities.json`;
this observed baseline, rather than a historical allowlist, governs later
comparisons. An incomplete run during capacity contention was preserved as
`base-incomplete-capacity*` and explicitly rejected; only the completed rerun
is accepted. Whole-repository ORIGINAL analysis recorded **1,686 diagnostics**
in `base-analyze.txt`. Both planned full-suite extraction gates remain pending.

The [dependency report](debrify-tv-deps.md) reviews **265 leaves**: 21 top-level
declarations (19 outside widget/State), 244 main-State members (78 fields,
15 statics, one getter, 150 methods including lifecycle/build), and the two
choice-chip-State members. Every leaf records its destination, raw occurrence
roles/scopes, field reads/writes, lexical hazards, callbacks, comments and
wiring checklist; resources, hooks, delays and diagnostic ownership are also
inventoried. The frozen map contains seven owner records and 39 sections;
both channel callbacks remain on `channelWatch`, with only switching on
`channelSwitch`. Three optional scaffold templates and two optional private
widget typedefs were pinned after that review; none is installed in the app.
All moved comment text, including banners and lint comments, is preserved.

The optional two-pass AST binder collects block declarations before resolving
references, distinguishes selectors from lexical names, and rejects early
references and lost field qualification before normalization. Default adapter
outputs for all **15 existing configurations are byte-identical**
(`adapter-default-output-proof.json`). The reader proves each declaration's
single current owner and returns raw R source; completion rejects any retained
leaf. ORIGINAL, partial, mixed, scaffold-only, and simulated-complete positives
and missing/duplicate/extra ownership negatives are covered. Both checker and
reader reject ordinary and balanced capture, ZIP parameter capture, changed
selectors, lexical State-setter replacement, and bare references in all seven
records and a section. Physical native-failure indentation, typed catches,
rethrows, and callback targets remain guarded. Receiver-path indexing was
proved equivalent over all raw ORIGINAL and simulated nodes; fixture-only
memoization reuses exact normalizer/canonical-name input/output in one process
and never caches AST scopes, binding or checker decisions. Parser packages/kernels are owned under
this worktree's `.dart_tool/debrify_tv_parser/`; each CLI run passes an explicit
isolated package, and copied packages have stale `.dill` files removed.

**Characterization:** eight new files, **68 passing R/O identities**, with
fixture search engines installed through production local-engine storage and
served by a recording MockClient. All 11 live Flutter handoffs, including
PikPak P4/P8 and the separate RD P1 early/P2 fallback flows, are observable;
the player-route interceptor removes routes before mounting the player.
Constructor fields/defaults, directory maps, close-before-push ordering,
held cancellation, running-prefetch disposal, five-second switching,
external decline/failure, hooks, settings/prefs, availability, child policy,
filters, favourites/deletion, imports/export/share, editor/pruning/full warm-up,
250 ms memo cancellation, and D-pad/KeyRepeat/focus are exercised. P5's live
channel setting and P3's stacked settings while the TorBox cache check is held
make channel and quick options differ, preserving the requested **O** option
swap proofs. No `pumpAndSettle`, production registry seam, or mutation acceptance
flag was used. **60 frozen ORIGINAL proxy definitions cover all 68 identities**
in `debrify_tv_original_mutations.json`; compilation and named assertion-failure
proofs are deliberately deferred to step 0b. Checker/reader mutations are S
proofs and are not counted as those behavioral proofs.

**Goldens:** six macOS ORIGINAL PNGs were captured in independent first/reverse
processes, with identical SHA-256 lists and a passing strict comparison
(`macos-original-*`). Fonts include JetBrainsMono, DPR/locale/text scale/theme
and focus are pinned, Spotlight uses one cached torrent and `fetchedAt: 0`,
and readiness is asserted before every image. Visual inspection retained the
original test rendering: unspecified font families use Flutter's test fallback
while explicit font families are loaded. Original SwitchRow decoration
diagnostics are recorded with their specific identity; the phone add-card's
exact **37-pixel** overflow is asserted in both search layouts. These host
rendering findings are preserved, not suppressed broadly or fixed. The Linux
capture script is committed, shell-syntax checked, and restricted to calibrated
Linux x86_64 / Flutter 3.44.8 / Dart 3.12.2 with application-object equality.
It uses checkpoint-owned tests in an owned detached checkout, separate
first/reverse processes and hash lists, strict verification, and copies six
PNGs plus evidence. Missing Linux files are tolerated only before their ORIGINAL
capture/step L; capture/require defines or step 1 make comparison strict.

**Checks:** all 15 integrated manifests with their own baselines/configurations
and isolated self-tests passed; the TV manifest and its real-config self-tests
cover lifecycle order, all 15 launch notifications, provider conditions,
P1/P2/P12 prefetch/close order, channel/quick swaps, cancellation, cooldown,
debounce/memo order, export authorization, compute entrypoints, live NSFW,
scaffold construction, comments, const, context, fields, and callback identity.
Architecture, size ratchets, storage keys/references, shape, theme, light-ink,
CI format and scoped analyzer/allowlist checks pass. Shape is **16 tokens,
zero bare radii, global floor 488 with zero slack**; theme remains **19 files,
18,002 lines, 228 sites**. Existing source/theme/profile guards: **83 success**,
with the one `direct SharedPreferences opens` failure also observed in `base`.
CI format: **1,886 files, zero changes**; scoped analyzer: **270 pre-existing
issues**, allowlist **14 warnings, nothing new**. New test/support analysis is
clean. The TV feature scan is unconditional before completion; exact D1 HTTP
permission and both size growth negatives are proven with the real architecture
checker. Actual exception caps remain zero until each file's creation commit
measures it; synthetic fixture caps are not production permissions.

**Strict diagnostics:** detached ORIGINAL root **50** (17 warnings/33 infos),
strict features **72**, compiling rename/receiver-only probe **53**, with
**zero added identities**. Six `unused_field` and thirteen
`use_build_context_synchronously` occurrences disappear; these are diagnostic
removals caused by relocation/receiver representation, not fixes. Private
widget typedefs add zero private-type diagnostics. Inventories combine by
maximum per identity, never sum (`strict-comparison.json`); destination warning
allowlist entries are added only when those production files are created.

**Checkpoint provenance:** the complete staged checkpoint tree was made into a
candidate commit object and replayed detached with its own frozen tests against
its unchanged application objects, before publishing that identical object on
the current branch. `original-b-characterization*` records all eight whole files
and strict macOS images. A fresh depth-1 clone of that checkpoint fails the
reader with the missing R object; after `git fetch --unshallow`, the same reader
and existing native/theme source checks pass (`step0-shallow-*`). The behavior
job's checkout now has `fetch-depth: 0`. Test, tool and application input hashes
and exact commit/tree provenance are recorded alongside those logs; no branch
switch or push was performed.

**Decisions and pending:** retain all 19 Found-not-fixed behaviors, especially
cached RD's player launch after Cancel, Premiumize's null switch result, and
P3/P11 channel-option binding. Use the existing tvOS host override to exercise
TV controls and the original false native bridge result; native payloads and
completion callbacks remain S/device evidence. Hold provider responses until
the original progress dialog is ready when asserting close-before-push, using
the existing UI boundary. Keep guards/source-reader changes narrow and retain
all existing assertions and known-failure lists. The original facade remains
**11,271 lines**; facade composition breakdown and measured extraction size
exceptions belong to the step-0b compiling probe and creation steps. **STOP
POINT 1:** step 0b, base2, step L, all production moves (steps 1–8), both gates,
Debrify TV device playback checks, remote CI and integration are pending
Claude's Linux capture and independent step-0 review. No step-0b mutation,
composition probe, or new baseline has begun.

### Step 0b — independent review closure on ORIGINAL, 2026-10-05

Parent characterization checkpoint **(b) =
`58e9d5d9602c700d4361b25908b1830a2ba19baf`**; application execution base R,
SDK, dependencies and lockfile stay unchanged. The review-closure checkpoint
has the exact subject `test(debrify-tv): step 0b review closure checkpoint`;
its SHA, tree/input hashes and ORIGINAL application object equality are in
`step0b-checkpoint-provenance.json`. All evidence remains confined to
`refactor-evidence/debrify_tv/`. Production code has not moved.

The independent review's **29 exact mutations** are now frozen alongside the
original proxy set in `debrify_tv_original_mutations.json`. There are **96
behavioral proxies and six S proxies**. Every behavioral proxy has a completed
ORIGINAL run failing its named assertion, with command, original mutation
hash, test name, expectation and failure message in
`step0b-behavioural-proxies.json`. All runs execute whole characterization
files, without name filtering. Compile failures and surviving assertions were
rejected as proof; corrected proxy definitions were replayed. All **24 new
tests** have recorded assertion-failing mutations (`step0b-review-closure.json`).
Existing assertions remain; the complete nine files now contain **92 passing
tests**, including six strict macOS golden scenes.

Review coverage invokes both captured by-id callbacks and compares the full
returned map, uses three channels for next-channel selection, and separates
the five configurable channel/quick option values at all 11 live push sites.
The sixth field, `hideOptions`, is hardcoded false in the original constructors
and remains an exact S ledger assertion; P9 is dormant S. P3/P11's original
Flutter channel-option behavior is preserved. Final-link cancellation holds
TorBox requestdl and AllDebrid unlock. Queued ORIGINAL Cancel callbacks cover
the late TorBox push guards and pending prefetch start invalidation; the
cached-RD late launch remains observable while its retained queue is emptied.
Active P12 prefetch makes the post-push stop observable. Ordered dialog close,
prefetch start, external handoff, push and stop are asserted at the reachable
boundaries. Other additions cover a second provider in P1 gating, an exact
five-second cooldown plus one frame, library cache invalidation, tab-handler
removal, unmount prefetch stop, Back focus before the clear control disappears,
and the first colliding import suffix `(2)`.

Four reviewer mutations remain S with recorded guard rejections: library
listener removal (the original mounted guard masks notifications after
unmount), Spotlight debounce cancellation (the focused-id recheck masks it),
the prefetch epoch recheck, and native helper arguments. The original memo-hit
cancel proxy and explicit key-repeat branch proxy also remain S where original
fallback behavior masks removal; separate observable debounce-delay and
handled-repeat proxies fail their behavioral assertions. All six S cases are
rejected by both the real checker and source reader. Five additional guard
mutants cover lifecycle, flow closure, dialog shadowed setter, paint lexical
context and hazard record (`step0b-guard-mutants.json`); constructor argument,
callback identity and cached composition changes are rejected separately in
`step0b-composition-scaffold-mutants.json`.

The owned detached compiling probe builds **all 265 moves**, seven owners,
bindings and all 39 sections, exceeding the five-kind stub requirement. Its
real CLI uses an isolated parser package and `--self-test` at R. The facade
uses eager owners and the specified nullable cache/getter, without `late`
fields; an in-flight probe that used `late` was corrected before acceptance.
The formatted facade is **107 lines**: imports 8, widget 6, State header/close
2, owners/composition 10, lifecycle 63, build 14, remaining blanks/comments 4
(sum 107). AST spans, source hashes and the compiling source copy are in
`step0b-composition-proof.json` and `step0b-compiling-sources/`. Creation-step
caps are measured at **946** for quick play and **524** for channel switch;
all other probe destinations are at most 500. The production exception caps
remain zero until those files are created. Frozen composition scaffolds are
inactive until their full declarations exist, with exact activation rules
recorded in the sidecar. The 37 ordinary comments outside leaf AST spans are
frozen verbatim with their destinations in `debrify_tv_comment_moves.json`.

The full composition has **53 strict diagnostics: 11 inherited warnings and
42 infos**, with zero new warnings. Compared by original member/rule/message,
six private unused-field warnings, 21 import-ordering infos and 13 context
infos disappear; receiver qualification plus normal formatting produces 21
brace infos when existing one-line statements wrap. They are inventoried,
without adding braces or suppressions, in `debrify_tv_analyzer_inventory.json`;
ORIGINAL and probe combine by maximum per identity. The temporary typedef-only
`trailingIcon` warning is rejected and eliminated by the exact constructor
forwarder described above. Root `flutter analyze` retains all **1,686** observed
diagnostic identities. The binder now ignores only AST-identified optional
formatter commas within selector qualifiers; actual argument separators and
record commas remain significant. Raw qualifier positives/negatives cover this.
The default adapter output is byte-identical for all 15 other manifests
(`step0b-adapter-default-output-proof.json`); every manifest runs its existing
self-tests with its own isolated worktree-local parser/kernel package.

Recorded checks also cover unconditional architecture scans, sizes, storage
references/self-tests, shape/source/native guards, the **488** shape floor with
zero slack, **19 TV theme files / 228 sites**, read-only CI format, CI scoped
analysis/allowlist and diff checks. Root and probe characterization runs are
92/92. The new full-suite **`base2`** runs serialized on the exact committed
ORIGINAL review-closure tree, paths `[]`, flags `--no-pub --concurrency=4`;
`base2.env.json`, `base2-comparison.txt` and `base2-provenance.json` record
SDK/input closure and identity reconciliation against `base`. Only passing
additions are accepted; no baseline recording/update option is used.
The first baseline attempt overlapped heavy AST self-tests and hit four new
UDP pairing bounded-wait failures. It was stopped and rejected as evidence,
preserved under `base2-rejected-contention*`. Whole-file causal replays on both
ORIGINAL and the checkpoint passed **5/5**, with identical application/test
objects and hashed inputs (`step0b-udp-causal-replays.json`). The accepted
full-suite retry runs after the checker jobs finish, using the same concurrency
and SDK; no timeout or failed identity is added to an allowlist.

**Decisions and stop:** retain every Found-not-fixed behavior and all historical
failure assertions. Claude's six Linux PNGs captured at (b), plus their evidence,
remain preserved and uncommitted. Step 0b adds observer/debug capture to the
shared golden fixture, so Linux must be recaptured from this new ORIGINAL
checkpoint before step L. The capture script resolves that exact checkpoint,
deletes all six first-pass PNGs before reverse capture, requires exactly six
new reverse-pass files, compares their hashes, then runs strict replay. No
step L, production extraction, full-suite gate, push or branch switch has
begun. Pending: Linux recapture and Claude's composition review, step L,
steps 1–8 and both gates, device-only TV playback, remote CI and integration.

### Step L — verified ORIGINAL Linux goldens, 2026-10-05

The supplied recapture is from **`58e3e599c5d5f29b0437b111cca1af9827cc3de1`**,
whose `lib`, `pubspec.yaml` and lock objects equal R. All six PNGs exactly
match both identical first/reverse SHA-256 lists. Capture, reverse capture and
strict replay logs each pass 6/6 in the calibrated `debrify-flutter:3.44.8`
linux/amd64 image. `linux-original-verification.json` records objects, hashes,
SDK, Dockerfile and provenance; the superseded capture remains preserved.

Committed the six ORIGINAL Linux PNGs separately. The golden test now always
asserts its platform's PNG: no missing-file skip, config gate or opt-out define.
Independent strict replay of these assertions passes **macOS 6/6 and Linux
6/6**, using the available calibrated Docker image and an owned input copy
under this worktree's `.dart_tool/debrify_tv_linux/`. Evidence is
`stepL-{macos,linux}-strict.txt`. No PNG is generated or updated here, and
production application/dependency objects remain unchanged. Step 0b's Linux
recapture prerequisite is resolved; proceed with steps 1–8 and both gates.
Device-only playback, remote CI and integration remain pending.

### Step 1 — extract pure models, helpers and compute entrypoints, 2026-10-05

Previous checkpoint: `42f329819b826eb3c3bc25b17042d2bfd70edf42`. Guard registrations from step 0b remain unconditional. All six first destinations are registered for shape, including zero-token files; the facade budget is zero. Theme patterns are explicit in all four feature directories. The unused parser and its inherited warning remain. A TV-only fixture parser cache proves batched/per-unit AST output identical in both modes, defensively copies results, reparses every changed input and reruns every guard; production checks and other manifests are unchanged. The first Linux retry lacked the disposable container's package cache; reject that harness failure and preserve it as step1-linux-rejected-cache.txt. The calibrated image now uses a worktree-local package cache and enforces the unchanged lockfile.

All 16 manifests pass their existing self-tests with explicit isolated parser
packages and stale copied kernels deleted; TV checks cover all 265 declarations,
occurrence/lexical bindings, comments, ownership and 236 callback negatives.
Architecture, sizes, storage, shape/source guards, theme (**228 sites**), CI
format and scoped analyzer/allowlist pass. Strict symbol inventory observes
**52 diagnostics, zero additions** against R/probe maxima.
The **92** whole-file characterization identities match latest **base2**;
strict macOS and calibrated Linux goldens pass **6/6 each**. All **490 original
comments**, **16 shape tokens**, zero bare radii and the **488 global floor
with zero slack** remain. LF and diff checks pass. Evidence is
`step1-*` under `refactor-evidence/debrify_tv/`, including wiring review,
measurement/source hashes, diagnostic identities, manifests and comparisons.

Formatted facade: **11206** lines. AST breakdown: retained original top levels 173, widget 6, state header and close 2, retained original bodies 10664, lifecycle 57, build 14, imports 86, remaining blank comment lines 204
(sum 11206). Every actual destination and
the facade are shape-registered. All Found-not-fixed behaviors remain; no
protected player/launcher/bridge/native code, dependency upgrade, push or
branch switch. Device-only playback, remote CI and integration remain pending.

## Found, not fixed

All pre-existing; the extraction keeps each exactly.

1. **Inconsistent `requestNextChannel` gating.** P1 allows Premiumize, P2
   (same quick-play RD flow) does not; quick TorBox/PikPak omit
   Premiumize/AllDebrid; P6 and P12 allow all five.
2. **Premiumize channel switching always fails.** `_switchToChannel` has no
   Premiumize branch (returns null at "Unsupported provider"), yet P10 and
   P11 offer `requestNextChannel`.
3. `_launchRealDebridOnAndroidTv` gates channel switching on the **channel**
   provider `_provider`, also for quick play.
4. Quick-play TorBox (P3) and Premiumize (P11) Flutter pushes use the channel
   playback options instead of the `_quick*` set.
5. Premiumize native playback reuses `_launchPikPakOnAndroidTv`.
6. `_watch` holds two near-duplicate `requestMagicNext` closures; the second
   ignores `_watchCancelled`.
7. `_deleteChannel` calls `setState` after an `await` with no `mounted` check.
8. The init post-frame `_checkPendingAutoPlay` has no `mounted` check before
   its first read.
9. `dispose` nulls `MainPageBridge.watchDebrifyTvChannel` unconditionally,
   even if another instance registered later.
10. Only export captures the profile; favourites, provider saves, channel
    create/edit/delete and imports are `mounted`-only across awaits.
11. `_launchRealDebridOnAndroidTv` logs the first 50 characters of the
    resolved stream URL.
12. Six fields are written but never read (`_status`, `_hideBackButton`,
    `_quickHideBackButton`, `_lastQueueSize`, `_lastSearchAt`,
    `_originalMaxCap`); `_parseRandomStartPercent`, `_playNextFromQueue` and
    four settings-card setters are dead.
13. Five `return` statements inside `finally` blocks.
14. `MenuController` is never disposed (no API).
15. Strings are unlocalized; several icon-only controls lack `Semantics`
    labels beyond their tooltips.
16. **Late launch after Cancel in cached flows.** Cached RD, AllDebrid,
    TorBox and Premiumize never check `_watchCancelled`: a resolve held
    across Cancel (e.g. `unrestrictLink` at 6070) can return a stream (6091),
    re-add sibling work to the cleared queue (6087–6089), restart the
    prefetcher (which resets `_prefetchStopRequested`) and push the player
    (6130 onward) with only a `mounted` check. `_watch`'s final closure #2
    behaves the same.
17. Several `_watchCancelled` checks in the quick-play flows are redundant
    (e.g. 10727 is followed by the guarded push), so removing one alone
    changes nothing observable.
18. The ZIP import appends channels with `setState` and immediately
    republishes them through `_loadChannels()` (3431–3436); the append is
    invisible.
19. Native quick play passes the channel playback options (only the
    channel-name flag comes from quick play), and the native profile is
    captured at bridge launch, not when the watch starts.

## Decisions taken before design review (Claude, 2026-10-05)

1. URL import keeps its existing `package:http` use; it is recorded as one
   additional named, file-scoped exception in `check_search_architecture.py`
   (behaviour moves verbatim; no new HTTP access is introduced).
2. The two oversize destinations (`_watch`, an 872-line single method, and
   `_switchToChannel`) carry documented size exceptions equal to their measured
   line counts, following the Spotlight card-layout precedent; a move-only
   refactor cannot split a method body. Exit milestone: the players goal.
3. No format-only commit: the file is already formatter-clean, so the branch
   base is reference R.
4. Pre-existing unused members move verbatim with their analyzer warnings
   allowlisted at their destinations; deleting them is a separate decision.

## Round 1 review resolution

Codex design review round 1 (`~/.codex-runs/tv-design/last.txt`, reviewed at
`b8de4ff2`); each point was re-checked against the source before revising.

1. **P1 cached cancellation.** Confirmed: cached RD's closure has no
   `_watchCancelled` check (6070/6087–6091/6130). Contract 3.6 now lists which
   flows honour cancellation; C3 is split into "honoured" (quick TorBox,
   Premiumize, AllDebrid, `_watch` closure #1, cached PikPak) and "late
   launch, as-is" (cached RD observed, the others S); Found, not fixed 16. No
   production change.
2. **P1 unprovable mutations.** Confirmed (`final` locals at 755/9150;
   `DebrifyTvZipImportedChannel` vs `DebrifyTvChannel` at 3335; `!mounted`
   return at 1061; redundant check at 10727; reload at 3436). Step 0.5 now
   separates compilable ORIGINAL behavioural proxies from checker/guard
   mutations (S); C2 and C10 reclassify detachment and the ZIP append as S;
   Technique 4 states the capture negatives are checker-level.
3. **P1 reader at (b).** Ownership is resolved per declaration (facade until
   the destination exists), with missing/duplicate/unlisted rejections and a
   completion rule; tested on ORIGINAL, partial and completed layouts.
4. **P1 CI history.** Confirmed `checks.yml:67` uses checkout v4 defaults and
   the Spotlight reader uses `git show` (116). Step 0.8 sets `fetch-depth: 0`
   on the behaviour job in (b), with a fresh shallow-clone failure/unshallow
   pass proof; it also covers the existing Spotlight reader test. Integration
   lists the change.
5. **P2 binding guard.** Confirmed counter semantics and bare-owner
   acceptance (`spotlight_board_field_bindings.py:36–51`). Technique 4 adds
   the opt-in `occurrence_field_bindings` guard (occurrence/scope pairing and
   mandatory qualification) with ordinary-capture, balanced-relocation and
   bare-owner negatives; other configs unchanged.
6. **P2 callback ownership.** Both channel callbacks are owned by
   `_sections.channelWatch` (`DebrifyTvChannelWatch`,
   `debrify_tv_channel_watch.dart`); `channel_switch` holds
   `switchToChannel` only. A frozen section map (key/class/file) is in the
   Destination layout and used everywhere.
7. **P2 playback characterization.** The fixture engine is installed through
   `LocalEngineStorage.saveEngine` + `EngineRegistry.instance.reload()` and
   served by the `MockClient` (`engine_executor.dart:577`); P1 and P2 have
   separate observable fixtures; Contract 3.11 freezes the complete named-
   argument ledger for all 12 constructors (11 live + P9), the 11 native
   helper invocations and the 3 bridge calls; Contract 3.3 records channel
   options in native quick play and bridge-entry profile capture.
8. **P2 reader whitespace.** Confirmed the Spotlight reader returns
   whitespace-stripped text (106). `debrifyTvOriginalSource()` returns raw
   ORIGINAL text after the token proof and a physical-source guard for the
   native-failure block; reader negatives prove the expectations still bite.
9. **P2 goldens and size negatives.** Confirmed `DateTime.now()` at
   `spotlight_stage.dart:480` and the `fetchedAt <= 0 → null → "never"` path
   (8080–8082). Scene 4 uses `fetchedAt: 0`, scenes assert readiness, and
   originals are captured twice in reversed order with identical bytes.
   Real-checker negatives now cover both size-exception files at cap + 1 and
   unrelated files above 800; the D1 pair is treated as an import permission.
10. **P3 inventory.** Corrected: 7 top-level functions and 21 top-level
    declarations (19 outside the retained widget/State); 80 import
    directives in the 82-line span; settings owner 34 and focus/search 10
    (sum 78); 13 `DebrifyTvView` callbacks; 11 live pushes plus dormant P9;
    six `_switchToChannel` prefetch starts (four failure restarts, two
    success); root diagnostics 17 warnings / 33 infos; the playback Step-0
    reference is C3; the auto-play path
    (`home_saved_composition.dart:89` → `HomeHeroShellBridge.playSavedDebrifyChannel`
    → `MainPageBridge` → the screen) and the remote router's data-only channel
    import are named in Contract 2. The facts file was corrected to match.

## Round 2 review resolution

Codex design review round 2 (reviewed at `ec928209`); each point re-checked
against the source.

1. **P1 C10/settings.** Confirmed `_buildSettingsCard` is rendered only from
   `_showGlobalSettingsDialog` (9541) with channel scope and no NSFW toggle;
   only `setStartRandom` and `setRandomStartPercent` are wired (9266–9285);
   the other four setters are unused (two are no-ops). Contract 4, C4 and C10
   now name the two live controls, assert their persisted writes, assert that
   quick-scope values change without persistence (Play-now copy, captured
   P4/P12 fields), observe unrendered settings through captured player fields,
   and classify the dead/no-op setters and unreachable branches as S.
2. **P1 theme allow-list.** Confirmed `source_guard_test.dart:48–52`. Only the
   Debrify TV entry is replaced (`...debrifyTvSourceFiles()`); the player
   screen and shared factory stay, the factory's assertion is unchanged, and
   the new `videoPlayerRoute(builder:)` assertion applies only to Debrify TV
   files.
3. **P2 occurrence guard.** Confirmed the adapter is syntax-only (`parseString`
   494, name sets 164–165). Technique 4 now specifies an explicit syntax-based
   declaration/scope binder in the adapter, alignment after removing only
   registered receiver scaffolding, binding checks before destructive
   normalization, bare-field rejection with same-named locals allowed, and
   wiring into both checker and reader; the key is in the Step 0 config
   inventory and the adapter change is listed under Integration.
4. **P2 reader ownership.** Ownership is by AST declaration presence with
   duplicate/missing rejection and deduped retained locations; the three
   scaffold files are registered explicitly (the `destination_ownership`
   precedent, `check_settings_moves.py:800–815`) and other extras rejected;
   positives added for a scaffold-only destination and a mixed file.
5. **P2 mutations.** All 17 `_watchCancelled` occurrences in `_watchWithTorbox`
   (5437 … 5605) are listed for the behavioural proxy. Step 0b now runs
   behavioural proxies against ORIGINAL (each must fail its named behavioural
   assertion; reader/guard rejection does not count) and guard mutants
   against simulated moved source, recorded separately.
6. **P3.** The dependency-report inventory says 21 top-level declarations (19
   outside the retained widget and State); the Linux script captures first and
   reverse passes with separate logs and SHA-256 lists and fails unless they
   match.

## Round 3 review resolution

Codex design review round 3 (reviewed at `177d240c`): "No P1s — executable".
The three P2s, re-checked against the source:

1. **Qualified selectors vs bare references.** Technique 4's binder now
   classifies each occurrence as `lexical` (bound to a declaration or
   `unbound`) or `selector` (with its qualifier chain), computes this on the
   raw ASTs before any receiver scaffolding is stripped, keeps an original
   local a bare reference to the same declaration, and leaves selectors such as
   `cacheEntry.status` (4244) and `parsed.channels` (3006, 3010, 3042)
   untouched. Fixtures: qualified field beside a same-named local, those
   selectors unchanged (positives); local replaced by a qualified field,
   selector chain changed (negatives).
2. **Declaration order.** The binder collects each lexical scope's
   declarations before binding, so a local shadows outer names for its whole
   block; references before their declaration are recorded as `early:` and
   rejected, never resolved to a field. Fixtures cover later local and local
   function declarations hiding outer names.
3. **Option-swap proofs.** P5 diverges the sets through the live start-random
   switch before tuning; P3 diverges them after the Play-now copy (9490–9500)
   by invoking the mounted Spotlight layout's `onSettings` while the TorBox
   cache check is held. If step 0 cannot drive that boundary, the P3 swap
   becomes S and a wrong-value mutation (`!_startRandom` at 5584) provides the
   behavioural coverage. Each proxy must fail its named assertion.
