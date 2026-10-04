# Addon hub screen refactor — plan

Written 2026-10-04 against `b5e90a55` (file blob `a485718a`, unchanged since
`88b54092`). Follow [AGENTS.md](../../AGENTS.md). Read
`docs/refactoring/playlist-content-plan.md`, `iptv-settings-plan.md`,
`pikpak-files-plan.md` and `playback-settings-plan.md` first, including their
Progress sections. This plan reuses their technique, checker, tooling,
staging and gate procedure (callback identity, tree-recording evidence,
real-config fixtures, original-code worktree proofs, the wiring checklist,
the frozen accessor, strict-lint evidence, pinned formatter sites, Linux
goldens from the original code) and only states what differs.

Execution runs in its own git worktree on `refactor/addon-hub`, cut from
`refactor/codebase`, in parallel with other plans; Claude integrates it and
captures the Linux goldens. Commit after every step; never push. Gate commits
contain `gate`. Remote CI stays pending (GitHub Actions billing limit), so
every step runs the local CI-equivalent commands. Every manifest run passes
an **isolated `--parser-package`** initialized from
`dev/tool/verbatim_parser.pubspec.lock` in this feature's evidence namespace;
the default shared parser cache collides across worktrees (PikPak exit 253).

Revised 2026-10-04 after Codex design review round 1 (callback closures,
operation-specific profile capture, separate engine sequences, network
caches, viewport widths, sync effects, declaration counts).

## Goal

`lib/screens/addons/addon_hub_screen.dart` is 3,415 lines: the Addons tab
(index 7) while the profile flag `stremio_addon_hub_enabled` is on (default):
installed Stremio addons (toggle, rename, update, remove, details, metadata
provider, add by URL, JSON import, update/delete all), the Official and
Community marketplaces, Torrent Engines (install, delete, YAML import), the
filter bar, the page D-pad policy and 33 top-level declarations (32
private).

Split it into a new feature, `lib/features/addon_hub/`, **moving code
verbatim**. The widget tree, keys, focus nodes and debug labels, build order
and the State's lifecycle are unchanged. `AddonHubScreen` and its State
(verbatim `initState` and `dispose`, a `build` forwarder, owners, wiring, the
frozen accessor) stay in `lib/screens/addons/addon_hub_screen.dart` (the
facade), so `lib/screens/addons_screen.dart:8,52` and
`test/stremio_metadata_provider_test.dart:4,158` keep their imports.

**Why a new feature.** `sources`, `settings` and the other migrated
features are complete; their manifest checkers and `*_COMPLETE`/`TEMP(...)`
rules govern every file in their folders. `addon_hub` matches the analytics
id (`'addon_hub'`, 119) and symbol names, covers addons and engines, and
doesn't collide with `addons_screen.dart` or `stremio_addons_page.dart`.

**Architectural status:** a bounded legacy-extraction stage. Temporary
exceptions and exit milestones:
- **State-driven sections instead of Riverpod.** Exit: addon-hub notifiers.
- **A `legacy_addon_hub/` bridge** calling services, credential probes,
  `MainPageBridge`, `isTelevision`, pickers, `url_launcher` and `Clipboard`.
  Exit: addon, marketplace and engine data contracts and a platform adapter.
- **Unchanged legacy text.** Exit: the app-wide localization migration.
- **Builder side effects** (`_marketNav.ensure` creating focus nodes during
  build). Exit: row-focus ownership in the Riverpod milestone.
- **Aliased mutable service lists** (`_market` is the service cache list).
  Exit: immutable snapshots behind the marketplace contract.

## Public surface

```dart
/// A single, Stremio-themed home for addons: one list with a source + type
/// filter, a search box, an "Add addon" URL flow, and a 1-click Discover
/// marketplace — styled with the same purple Discover kit (see_all_theme +
/// StremioDropdown) as the catalog browser.
class AddonHubScreen extends StatefulWidget {
  const AddonHubScreen({super.key});

  @override
  State<AddonHubScreen> createState() => _AddonHubScreenState();
}
```

Kept exactly (42–51); the only public symbol (no parameters, `widget.` reads
or `didUpdateWidget`). Built only while tab 7 is selected (`main.dart:1545`;
a tab switch disposes it) and by the metadata test.

## What it contains (line numbers at `b5e90a55`; the step 0 manifest is authoritative)

| Lines | Area |
| --- | --- |
| 1–51 | 27 imports (13 under `lib/services/`), `_HubKind`, `_AddonSource`, the widget |
| 53–114 | State fields: 1 static (`_tabIndex = 7`), 15 `final`, 21 mutable; 3 more between methods (176, 234, 461); no `late`, getters or mixins |
| 116–230 | `initState`, `_loadDebridState`, `dispose`, `_onAddonsChanged`, `_loadInstalled`, `_loadMarket` |
| 232–501 | engines: `_onEnginesChanged`, `_loadEngines`, install, delete, YAML import, blocking progress |
| 503–567 | `_focusFirstRow`, `_toggleSearch`, `_selectKind`, `_selectSource`, `_isInstalled`, `_matchesFilters` |
| 569–1222 | actions (market install, configure, add by URL, JSON import, update all, delete all, toggle, rename, update, remove), options sheet, details, actions menu |
| 1224–2092 | `_onPageKey`, `_hasLeftNeighbour`, `build`, header, filter bar (181, the largest member), search, body, installed list, metadata picker, market list, engine list, `_iconForEngine`, `_relativeDate`, `_emptyState` |
| 2095–3415 | `_FocusCard`, `_kCardBg`, `_cardDecoration`, `_InstalledRow`, `_AddonInfo`, `_AddonTitleLine`, `_AddonMeta`, `_MarketRow`, `_MarketButton`, `_EngineRow`, `_EngineActionPill`, `_addonLogo`, `_StatusPill`, `_AddonOptionsSheet`, `_OptionTile`, `_HubActionButton`, `_HubDialog`, `_HubDialogButton`, `_capitalize`, `_RowNav`, `_capabilities`, `_CapabilityChip`, `_WarningChip`, `_centerInScrollable`: 29 declarations with the five companion States (`_FocusCardState`, `_MarketButtonState`, `_OptionTileState`, `_HubActionButtonState`, `_HubDialogButtonState`) |

No member exceeds 200 lines. No playback, route push, back handler, timer,
subscription, explicit controller besides the text field, or key literal.

## Contracts that must not change

1. **Lifecycle** (116–136, 149–172), verbatim with receiver-only
   qualification. `initState`: `super`; `screenView('addon_hub')`;
   `addAddonsChangedListener(_onAddonsChanged)`;
   `LocalEngineStorage.changes.addListener(_onEnginesChanged)`; the anonymous
   search-controller listener (never removed); `_tvFocusHandler = () =>
   _kindFocus.requestFocus()`; `registerTvContentFocusHandler(_tabIndex, …)`;
   `isTelevision().then` (mounted-guarded); unawaited `_loadDebridState()`
   then `_loadInstalled()`. Engines and marketplace do **not** load at init.
   `dispose`: the **15 cleanup statements** in order (remove addons
   listener; remove engines listener; guarded unregister; search controller;
   nodes kind, source, type, add, more, search, searchBtn, metadata,
   firstRow; `_marketNav.dispose()`; `_remoteEngines.dispose()`), then
   `super.dispose()`. `_stremio`, `_marketplace`, `_localEngines` are
   borrowed, never disposed.
2. **Registration identity.** `unregisterTvContentFocusHandler` removes only
   when the stored handler `==` the argument (`main_page_bridge.dart:799–806`);
   register overwrites by index (`ClassicAddonsScreen` also uses tab 7). The
   handler stays one **stored closure field** read at both sites. Removing
   the two change listeners (`List.remove`, `ValueNotifier`) needs the
   **same receiver's tear-off** of `_onAddonsChanged` and
   `_onEnginesChanged`; a wrapper closure, a recreating getter or another
   instance silently leaks the listener. `onKeyEvent: _onPageKey` stays a
   tear-off.
3. **Loads and request counters, exactly as they are.**
   `_installedLoadRevision` (176–203) guards success and error (error keeps
   the old list). The **shared** `_engineLoadRevision` (234–293) is bumped by
   both `_onEnginesChanged` and `_loadEngines`; `_loadEngines`'s entry
   `setState` (261) is unguarded; a stale load **assigns `_knownRemoteEngines
   = remote` outside `setState` and before the revision check** (270), then
   awaits `_onEnginesChanged()`, which bumps again. `_loadMarket` (205–230)
   has no counter (publishes when `_marketLoadedFor == source`);
   `_selectSource` reloads only when `_marketLoadedFor != source`;
   `force: true` only from Retry; `_selectKind` loads engines once
   (`_enginesLoadedOnce`, never reset). `_loadDebridState` and
   `isTelevision` are one-shot; `_hasDebrid` starts `true`.
4. **Ordering.**
   - **Installed:** the stored collection order is displayed **as-is**. The
     hub never sorts, reorders, drags or persists the collection; it filters
     with an order-preserving `where` (1586–1588). Adds and imports
     **append** service-side (imports in file order); remove keeps the
     others' order; toggle and alias rewrite in place. This order feeds
     metadata "Automatic" and addon fan-out downstream. Legacy fixtures show
     Zulu/Cinemeta/Alpha; committed-mode resource fixtures show the registry
     order Alpha/Cinemeta/Zulu. Installed-sort and metadata-sort mutations
     are caught by the legacy fixtures, whose order distinguishes them.
   - **Market:** the service order; nav indices in list order for
     non-installed rows only (1897–1902).
   - **Metadata picker** (1621–1740): enabled `meta` addons with a
     `baseUrl`, in installed order, then the existing `providers.sort`
     putting Cinemeta first (0 otherwise; the pinned SDK insertion-sorts
     lists of up to 33 elements, beyond which equal-element order is
     unspecified — unchanged); `' · Recommended'` labels; Automatic last; the
     selected-value rule (stored `automatic`, else a stored provider value,
     else the first Cinemeta, else `automatic`).
   - **Engines:** imported in `metadata.json` order; available = remote
     order minus imported ids.
   - Filter options (1352–1382), wide `Wrap` and narrow (<480) row order,
     capability chips (3314–3320) then the debrid chip, sheet tiles
     (2942–2971; conditions at 1043), overflow menu (1173–1180),
     import-result rows (732–737).
5. **Addon actions: effects, arguments, order.** Confirmations exist
   **only** for remove (`addonBorrowerCount(storageKey)` then
   `removeAddon(storageKey, revokeSharedProfiles: isShared)`, shared variant
   985–989), delete all (`sharedAddonCount()` then `clearAllAddons(
   revokeSharedProfiles: hasSharedAddons)`, 813–841) and delete engine.
   **None** for disable/enable (`setAddonEnabled(a.storageKey, !a.enabled)`,
   unawaited from the sheet, 860/1037), update all (`refreshAllAddons`), JSON
   import, market install (`addAddon(m.transportUrl)`, awaited
   `_loadInstalled`, post-frame refocus) or update (`refreshAddon(
   a.manifestUrl)` — **manifestUrl**). Add by URL and rename use input
   dialogs (`setAddonAlias(storageKey, alias)`, `''` = manifest name).
   `_setMetadataProvider` (1742–1757) is optimistic with a captured
   `previous` rollback. Snackbars use the messenger captured before awaits
   (except 1108, 1750); `'Exception: '` is stripped at 225, 288, 454, 596,
   679, 717.
6. **Engine actions**, three separate sequences:
   - **Install** (295–326): messenger captured; blocking dialog; `await
     downloadEngineYaml` (null throws); `await saveEngine` with **no
     `mounted` check between download and save** (299–307);
     `ConfigLoader().clearCache()`; `await EngineRegistry.instance.reload()`;
     dismiss; `await _loadEngines()`; `mounted` check; snackbar. Failure:
     dismiss, `mounted` check, red snackbar.
   - **Delete** (328–370): confirmation; `confirmed != true || !mounted`
     return; messenger; `await deleteEngine`; `clearCache()`; `await
     reload()`; `await _loadEngines()`; `mounted` check; snackbar. **No
     blocking dialog** on success or failure (the catch shows only the red
     snackbar).
   - **YAML import** (373–459): messenger and theme captured;
     `pickFiles(type: any, withData: true)`; extension; bytes or
     `xFile.readAsBytes()`; `loadYaml`; `id`/`display_name` checks; the
     replace confirmation **only when the id exists**; `mounted` check;
     blocking dialog; `await saveEngine`; `clearCache()`; `await reload()`;
     dismiss; `await _loadEngines()`; `mounted` check; snackbar. Failure:
     dismiss (a no-op when the dialog never showed), `mounted` check,
     stripped red snackbar.
   The blocking dialog (`barrierDismissible: false`) is popped through
   `Navigator.of(context, rootNavigator: true)` only while
   `_blockingProgressUp && mounted`.
7. **Network.** Manifests through `StremioService` (top-level `http.get`);
   the marketplace singleton's session cache (`api.strem.io`; paged
   `stremio-addons.net`, up to 20 pages; the `stremio-addons.com` fallback
   with `communityFromNet` gating the attribution); engines from gitlab.com.
   **The engine network client is owned:** `_remoteEngines =
   RemoteEngineManager()` is a field initializer (default `http.Client()`,
   closed and replaced by a new `http.Client()` on a 30 s timeout) closed by
   the last cleanup statement. **Only the market Retry forces** (`_loadMarket(
   _source, force: true)`, 1881). Engine refresh and Retry (`onTap:
   _loadEngines`, 1412, 1942) never clear the manager's per-instance
   5-minute metadata cache (`remote_engine_manager.dart:125`): a hit makes
   no request. A miss requests `metadata.yaml` only; the GitLab `tree`
   listing plus one request per engine file is the uncached legacy fallback
   after a metadata failure. Market fallback: `fetchCommunity` falls back to
   `_fetchCollection(stremio-addons.com, forceRefresh: force)`, which caches
   under its own URL key besides `community`. No request is added, removed
   or reordered.
8. **Storage, profiles and sync**, all service-side: `stremio_addons_v1` or
   the resource graph, `stremio_metadata_provider_v1`, the profile `engines/`
   directory, read-only credentials; sync triggers
   (`notifyWebDavSyncLocalChange`, `'engine_definitions_changed'`) stay in
   the services. The hub captures no scope; gate remounts and tab switches
   dispose it. Capture is **operation-specific**, not a blanket rejection:
   engine install awaits the download in the hub with no `mounted` check,
   and `LocalEngineStorage._pinned()` captures the scope only when
   `saveEngine` begins, so a switch during the download saves into the
   then-active profile **if the download completes successfully after the
   switch** (disposal closes the engine client, and an aborted download
   returns null and never reaches storage, `remote_engine_manager.dart:329`;
   both outcomes recorded, preserved); delete and import
   capture when their storage call begins; `ProfilePreferences.instance()`
   captures after `SharedPreferences.getInstance()` resolves, so the
   metadata write targets the profile active at acquisition. Engine sync
   (`_notify(profileId)` with the captured id) fires only on a committed
   save or a delete that changed metadata, never on failure or cancel;
   `LocalEngineStorage.changes` is bumped only by the incoming WebDAV
   refresh (`webdav_sync_active_profile_refresh.dart:137`), not by local
   mutations. Nothing is added or removed.
9. **Clipboard and URL launching.** Configure: `launchUrl(
   externalApplication)`; on false or throw, `await Clipboard.setData` and a
   5 s snackbar. Attribution: `launchUrl`, errors swallowed. Copy URL:
   **unawaited** `Clipboard.setData`, pop, snackbar. File pickers at 379, 689.
10. **D-pad and focus.** `_onPageKey` (1232–1257): LEFT KeyDown/Repeat
    moves in-band or calls `focusTvSidebar` (handled even when null; ignored
    while searching). The filter-bar DOWN wrapper (1487–1505),
    `_focusFirstRow`, metadata arrows; `isTelevision` feeds only the
    dropdowns. **TvTextField rule:** the search and add-dialog `TvTextField`s
    are fine and nothing sets `node.onKeyEvent`; the rename dialog's raw
    `TextFormField` (873) is preserved (found, not fixed). `_MarketButton`:
    KeyDown activates, repeat consumed, Down → `nav.focus(i+1)`, Up false at
    0; four other widgets activate on KeyDown only; `_centerInScrollable`,
    `AnimatedScale` and post-install refocus (586–591) unchanged. **Row
    focus-node pool:** `_RowNav.ensure` runs in the builder, grows only
    (`'market-row-$i'`), node `i` re-attaches to nav index `i`, disposal only
    in `dispose`. `_firstRowFocus` is shared by installed and engine row 0.
11. **Filtering and identity.** `_matchesFilters` (type `contains`, trimmed
    case-insensitive search on `displayName`/`name`); `_isInstalled` by id or
    manifest URL; `warnDebrid`; `_market` aliases the service list; rows
    capture build-time `StremioAddon` snapshots (1613); the X close nests the
    listener's `setState` (1554–1557).
12. **Diagnostics.** Root analyzer: 0 issues. Original strict probe
    (destination lints, import URI qualification only): 3
    `prefer_const_constructors` infos (`_emptyState` 2079, `_AddonTitleLine`
    2330, `_EngineRow` 2756) that **stay**; import-order infos traced to
    qualification. No `const` change; `_MarketRow.navCount` keeps its name (a
    private rename would raise `unused_field`).

## Destination layout

`lib/features/addon_hub/` (each file at most 500 lines; prefix `addon_hub_`):
- **`models/`:** `_HubKind`, `_AddonSource` as `AddonHubKind`,
  `AddonHubSource`.
- **`application/`:** `_capitalize`, `_capabilities` (String/record only).
  `_relativeDate` (`DateTime.now()`) and `_iconForEngine` (`IconData`) stay
  with their sections.
- **`presentation/`, outside the bridge** (pure widgets the deps report
  confirms import no `lib/services/`): `_RowNav`; the focus card with
  `_kCardBg`, `_cardDecoration`, `_centerInScrollable`; `_HubDialog` and
  `_HubDialogButton`; `_HubActionButton`; `_OptionTile`; the addon info group
  (`_AddonInfo`, `_AddonTitleLine`, `_AddonMeta`, `_addonLogo`,
  `_StatusPill`, `_CapabilityChip`, `_WarningChip`); `_InstalledRow` and
  `_AddonOptionsSheet` if `lib/models/stremio_addon.dart` is their only data
  import. Top-level names become public (`AddonHub…`) only through manifest
  rows; private State classes keep their names and move with their widget.
- **`presentation/legacy_addon_hub/`** (exact path in the guard): `_MarketRow`
  and `_MarketButton`, `_EngineRow` and `_EngineActionPill` (service types),
  the owner records and the sections: loading (installed, market, debrid);
  engines and blocking progress; market and URL/JSON actions; addon
  management; sheets and menus; navigation with `_onPageKey`; filter bar and
  search; installed list and metadata picker; market list; engine list; body
  and empty state; composition.
- Checker files `addon_hub_manifest.tsv`, `addon_hub_checker_config.json`,
  `addon_hub_checker_test.py`; fixtures `test/support/addon_hub_*`; evidence
  `refactor-evidence/addon_hub/`; goldens `test/goldens/addon_hub/`.
- **The facade** is an exact composition root (400-line cap and
  `TEMP(addon_hub)` rejection from step 7): the widget, the State with
  `_tabIndex`, the stored `_tvFocusHandler`, verbatim lifecycle, the `build`
  forwarder, owner handles, lazy composition and the accessor. No feature
  file names `AddonHubScreen`.
- **Guard rules** (step 1, `check_search_architecture.py`): `addon_hub` in
  `FEATURES` (13); `ADDON_HUB_FACADE/BRIDGE/COMPLETE`; the bridge in
  `LEGACY_PLAYBACK_BRIDGES` (291; still no `http`, `shared_preferences`,
  `sqflite`); the facade in `COMPOSITION_ROOTS` at step 7; no `lib/services/`
  or Flutter UI imports in `application/`/`models/`; no service imports in
  `presentation/` outside the bridge; no import of the facade,
  `addons_screen.dart` or `stremio_addons_page.dart` from the feature;
  **bidirectional bans** with `sources` and `settings`; 500-line caps.

## Technique

As in the playlist-content and IPTV-settings plans, with these points:
1. **Format-only step 0a.** The original isn't `dart format` clean
   (888–891: `AppThemeScope.of(ctx).fade(...)` rewraps, removing **one**
   optional trailing comma (after `0.58`) and inserting **one** (after
   `ctx`); 2872: the nested conditional splits; 3,415 → 3,416 lines). Step 0a formats it
   alone, proven by the AST verifier (identical structure; only
   parser-identified optional commas and whitespace; same comments, radii
   and token calls). Analyzer output is compared by identity; any
   format-induced info is recorded as baseline. One recorded size raise.
2. **Comments move verbatim.** The checker compares line and doc comments
   across destinations: never reword, merge or drop one (including field
   comments and `// ── … ──` banners); only manifest `[Symbol]` link renames
   are normalized.
3. **Whole widget classes move verbatim** (class plus State), renamed only
   through manifest rows, keeping key and `const` capability. The
   `use_key_in_widget_constructors` infos the public renames expose are
   inventoried on a throwaway rename-only tree and combined with the strict
   baseline by maximum, never summed.
4. **Identity.** The two listener tear-offs come from one section instance
   composed lazily once (explicit nullable field and getter, the PikPak
   no-`late` decision) before `initState` registers them; `_tvFocusHandler`
   stays a stored State field. Checker callback identity (receiver path plus
   member, with wrapper, receiver-swap, wrong-member and missing-argument
   negatives) covers the **direct tear-offs** `_onPageKey` (1302),
   `_toggleSearch` (1388), `_focusFirstRow` (`onDownArrow`, 1549),
   `_loadEngines` (refresh 1412, Retry 1942) and `_setMetadataProvider`
   (1718). The **argument-capturing closures** stay closures with their
   original shape and arguments verbatim: `() => _showOptions(items[i])`
   (1613), `() => _installFromMarket(m, navIndex)` (1920), `() =>
   _configureInBrowser(m)` (1921), `(_) => _focusFirstRow()` (1548) and the
   market Retry `() => _loadMarket(_source, force: true)` (1881).
   `torbox_callback_identity.py:96` accepts only direct tear-offs and would
   reject them, so a **config-scoped extension** (opt-in key in this
   feature's config only; existing configs and their results unchanged)
   compares the closure's parameter list and argument tokens verbatim and
   resolves the **invoked member and its receiver** through the same binding
   checks. Step 0 proves the parsed original passes before any extraction.
5. **Owners keep initializers and types**, including the three
   between-method fields (a recorded placement decision); `_remoteEngines`
   is created and disposed through the same owner. Live `context`, `mounted`
   and `setState` are read at their original sites; builder side effects
   stay in their builders. No new `const`; import reordering is the only
   other edit; formatter braces or commas after receiver expansion are exact
   pinned sites.

## Steps

| # | Work | Notes |
| --- | --- | --- |
| 0a | Format-only commit of the original | Technique 1. |
| 0 | Baseline, strict-lint evidence, deps report, checker, accessor, harness, characterization and baselines, inventory, CI list, Linux script | Nothing moves. Step 0b review closes before step 3. |
| 1 | Guard registration; models; application helpers; `_RowNav` | Contracts 4, 10. |
| 2 | Pure widgets: focus card, dialogs, action button, option tile and sheet, addon info group, installed row | Contracts 10, 12. |
| 3 | Owners; lifecycle verbatim; loading; engines and blocking progress | Contracts 1–3, 6, 7. **Full-suite gate 1.** |
| 4 | Addon actions, sheets, menus, details, metadata write | Contracts 5, 8, 9. |
| 5 | Navigation, page key policy, filter bar, search, lists, market and engine rows | Contracts 4, 10, 11. Linux originals are a blocking prerequisite. |
| 6 | `build` forwarder, body and root layout | |
| 7 | Final State, composition, guards, CI, docs. **Full-suite gate 2.** | |

### Step 0

1. **Baseline:** `suite_evidence.py run addon_hub/base` and the whole-repo
   analyzer with tree provenance on the step-0a commit (Flutter 3.44.8 /
   Dart 3.12.2; `flutter pub get` once, then `--no-pub`). The original is
   also analyzed under `lib/features/analysis_options.yaml` in the ignored
   nested original worktree (import URI qualification only), plus the
   rename-only inventory.
2. **Dependency report** (`docs/refactoring/addon-hub-deps.md`): every leaf
   and field with its destination, and the per-entry **wiring checklist**
   (owner record, live `context`/`mounted`/`setState`, tear-off identity and
   source instance, the two post-frame callbacks at 524 and 586, dialog
   `ctx` versus State `context`, carried strict infos). Review each entry
   against the actual binding before pinning any scaffold.
3. **Checker:** manifest and config, LF-only, with fixtures built from the
   **real config** and negatives for: a listener added and removed through
   different receivers or wrapped; the TV handler re-created at unregister;
   for each closure, isolated negatives that change only the receiver,
   only the invoked member, only an argument, or turn it into a tear-off or
   a nested wrapper (each rejected alone); the **original-positive proof**
   (the unmodified step-0a file through the real config with every
   tear-off and closure spec, before any extraction);
   a reordered or dropped dispose statement; `_remoteEngines` disposed via
   another owner; lifecycle moved out of the State; a reworded comment; an
   added `const`; a split widget/State pair.
4. **Accessor** (the approved seam; no clock, HTTP or platform seam): a
   frozen `@visibleForTesting addonHubTestAccess(State)` in the facade with
   fresh snapshots of every mutable field (both revisions,
   `_knownRemoteEngines`, `_marketLoadedFor`, a copy of the `_RowNav` nodes),
   the live nodes and `_tvFocusHandler`, a `_market` identity probe, real
   tear-offs (both listeners, the three loads, `_focusFirstRow`,
   `_setMetadataProvider`, `_toggleAddon`) and one TV setter (`_isTv` plus
   `markNeedsBuild()` after the real check settles). The seam-only size
   raise is recorded once.
5. **Harness** (`test/support/addon_hub_fixture.dart`, reusing
   `profile_fixture.dart`): `invalidateCache()`, `http.runWithClient` whose
   factory returns a **fresh close-tracking** request-logging `MockClient`
   per call into one shared log (convenience `http.get` creates and closes
   its own client; step 0 proves the engine field's client and its timeout
   replacement both come from the zone factory). **Marketplace cache reset
   with existing APIs only:** only warm-cache cases preseed; each such case first runs `fetchOfficial(forceRefresh: true)`/
   `fetchCommunity(forceRefresh: true)` under its own client, overwriting
   the `community` key and `communityFromNet`; a case that needs the
   fallback forces it (net failure), refreshing the separate legacy-URL
   entry, and no case relies on a legacy entry left by an earlier case.
   Setup requests are logged apart from the case's. Cache-cold cases never preseed:
   each runs in a fresh isolate (its own test file) with no setup fetch, and
   both methods are called with `forceRefresh: true` only where the case
   says so. No production reset. Temp documents directory for engines; fakes for
   `FilePicker`, `UrlLauncherPlatform` (true, false, throw), clipboard and
   `MainPageBridge` sentinels; `logo: null` market fixtures. Prove one HTTP
   fixture on the original first.
6. **Characterization tests,** recorded against the original: drive **real
   entry points** (dropdowns, buttons, sheet tiles, menu, dialogs, keys);
   assert **exact request lists**; **re-read state after acting** (service
   reads and persisted preferences, not just text); **non-monotonic,
   non-alphabetical ids and names** so any sort shows; held futures for
   in-flight cases; a scheduled frame after post-frame callbacks; route
   animations drained before asserting pops; KeyDown versus KeyRepeat;
   viewport widths 375, 479/480 (filter bar, `c.maxWidth < 480`), 527/528
   (cards: list padding leaves viewport − 48 for `c.maxWidth < 480`),
   581/582 (metadata picker: margin, padding and border leave viewport − 82 for
   `constraints.maxWidth < 500`) and wide, or the `LayoutBuilder`
   constraints asserted directly; no wall-clock engine subtitles.

   | Contract | Coverage |
   | --- | --- |
   | 1 Lifecycle | Source guards on verbatim `initState` and the 15-statement dispose; no engine or market request at mount; the engine client closed after dispose. |
   | 2 Identity | Bridge sentinels (a later tab-7 handler survives dispose); listener counts before and after dispose (a notify after unmount loads nothing); checker identity negatives. |
   | 3 Loads | Installed: an older held load completing last doesn't publish. Engines: held load A, then a notify or load B; A's late remote list **overwrites `_knownRemoteEngines`** and re-bumps the revision (recorded); unmount during install/delete/import reaches the unguarded `setState` (outcome recorded). Market: same-source Retry double publish, a stale error after switching back, no request on Official→Installed→Official; engines load once. |
   | 4 Ordering | Stored order shown unchanged; add and import append; remove keeps order; market order and nav indices with installed rows interleaved; metadata picker order, labels and each selected-value rule; engine, filter, chip, sheet, menu and import-result orders. |
   | 5 Addon actions | Each action's exact service effect and argument (`storageKey` versus `manifestUrl`, `revokeSharedProfiles` true/false with a borrower), confirmation presence, cancel writing nothing, snackbar text and colour, prefix stripping; metadata rollback on a failing write. |
   | 6 Engines | Install, delete and import as separate sequences with request lists; the blocking dialog on install/import success and failure; **no blocking progress at any point during delete**, including a failing delete; replace confirmation only for an existing id. |
   | 7 Network | Exact URLs and counts; market Retry forces; engine refresh/Retry within 5 minutes is a cache hit (no request); metadata success is one `metadata.yaml` request; a metadata failure then `tree` then per-file requests in order, uncached; a timeout closes the client and later requests use a new one; fallback hides the attribution. |
   | 8 Profile | A switch through the real gate picker disposes the hub. Held engine **download** before save across a switch, characterized both ways (aborted by disposal: no write; completing late through a tracking client: written to the scope storage captures), then held `saveEngine`; held `ProfilePreferences` acquisition with the switch before and after capture; held `addAddon`; each inspects persisted data in **both** profiles and the recorded outcome is preserved; suppressed snackbars; the toggle's unhandled error; a same-profile switch. |
   | 8 Sync | A recording `webDavSyncLocalChangeSink`: engine install, import and delete notify `(profile, 'engine_definitions_changed')` exactly once, where profile is the scope **storage captures** (which can differ from the profile that initiated the action); failed or canceled saves and no-op deletes notify nothing; addon and metadata writes notify their profile and key; an incoming WebDAV refresh bumps `LocalEngineStorage.changes` and reloads the hub, distinct from ordinary listener notifications. |
   | 9 Platform | Configure true/false/throw (clipboard text, snackbar), attribution launch, Copy URL, picker arguments. |
   | 10 D-pad | LEFT in-band versus sidebar (null still handled; ignored while searching); filter DOWN; `_focusFirstRow` per source; search arrows and submit; market button keys; post-install refocus through the retained pool node (including installing the last focusable row; `_RowNav.focus` returns true even for a detached node, 3295), with the `fromNav-1` and search-button fallbacks preserved by the verbatim proof rather than required through normal UI installs; pool growth (never shrinks); TV setter → dropdown. Source guard: rename `TextFormField`, two `TvTextField`s, no `onKeyEvent =`. |
   | 11 Filters | Empty-`types` addons dropped under a type filter; alias-aware search; installed by id or URL; debrid chip; `_market` identical to the service list. |

   Pixel goldens (installed with the metadata picker, narrow and wide;
   Official market; engines; options sheet; a `_HubDialog`) on macOS and
   Linux. Record `base2` after the accessor and `base3` after the tests.
   Step 0b closes with **ORIGINAL-only mutation proofs** (sort the installed
   list, drop the Cinemeta sort, toggle by `manifestUrl`, skip the remove
   confirmation, guard the stale engine assignment, mount-guard
   `_loadEngines`, swap two dispose statements, wrap a listener, trim the
   pool), each rejected by a test, then `base4`.
7. **CI list:** every new test as a concrete path in
   `dev/tool/ci_behavior_tests.txt`, plus the existing
   `test/stremio_metadata_provider_test.dart` (passes, not listed today).
8. **Source-text inventory:**
   - **Shape** (`test/theme/shape_manifest_test.dart:134`): **7 bare radii**
     (1823, 2016, 2153, 2848, 2877, 3342, 3377; the `Radius.circular(18)` at
     1031 isn't counted) and **13 `app.shape.br` calls** (471, 646, 650,
     1169, 1524, 1658, 2691, 2826, 2926, 3025, 3124, 3170, 3254). The floor
     is **488 with zero slack** (133 `kShapeResidue` files hold exactly 488).
     **Every destination and the facade are registered:** token files in
     `kShapeResidue` (residue = bare radii), all others, zero-budget
     included, in `kExtractedShapeResidue` (the facade at 0 once token-free).
     The comma normalisation (988) gains `lib/features/addon_hub/`.
   - **Theme:** `dev/tool/theme_surface_manifest.txt:4` (`addons`) gains
     explicit per-directory patterns (`application/*.dart`, `models/*.dart`,
     `presentation/*.dart`, `presentation/legacy_addon_hub/*.dart`), never
     `**`; `light_ink_inventory.py:71` gains `'lib/features/addon_hub'`.
   - **TV text-field guard** (`test/settings_tv_input_source_guard_test.dart`):
     gains the facade before characterization and the feature directory
     **unconditionally** (no `existsSync`) from step 1.
   - `file_size_baseline.txt:23` (format and seam raises once, then down;
     removed at ≤ 800); `check_search_architecture.py`; `checks.yml` format
     (facade, `test/support/addon_hub_*`) and analyze (the facade **before**
     `| tee analyze.txt`; never append paths after the pipe);
     `analyzer_allowlist.txt` (no entries expected);
     `stale_runtime_guard_test.dart:165` (declare no `clearCache`-style
     methods in destinations); `CODEMAP.md:30` and the `_kCardBg` comment at
     `lib/theme/app_theme.dart:1924` (step 7, comment only).
   - Shared registry files are edited in small separate blocks so Claude's
     union merge stays mechanical.
9. **Linux capture script** (`dev/tool/capture_addon_hub_linux_goldens.sh`)
   resolving exact subject `test(addon_hub): step 0 original-code
   characterization checkpoint`, with the playlist handoff (reachable ref,
   `$HOME` clone, `HEAD` verified, PNGs copied into
   `test/goldens/addon_hub/linux/` and committed separately with
   provenance). Claude runs it in the calibrated `debrify-flutter:3.44.8`
   linux/amd64 image with libsqlite3; non-strict until committed before step
   5, then strict.

### Per step and gates

As in the PikPak plan, with `--relocate
lib/screens/addons/addon_hub_screen.dart=lib/features/addon_hub/`: all ten
manifests with self-tests (settings, IPTV, TorBox, Real-Debrid, PikPak,
player-launch, playback settings, IPTV settings, playlist content, this one)
on the isolated `--parser-package`; per-symbol strict analyzer comparison;
shape counts and floor; LF-only manifests; exact CI lists; architecture,
size, storage and staged diff checks; gates on **committed** trees with no
untracked inputs. Failed attempts are kept and rerun, never accepted (known
flaky: the member PIN recovery test). Never `--record`.

### Integration

Claude union-merges shared registration files with the parallel worktrees
(guard registrations, shape/theme manifests, source guards, CI lists;
`checks.yml` paths before `| tee`; ratchets only lower), re-sums the shape
floor, then runs guards, all manifests, the analyzer comparison, affected
tests, strict Linux goldens and a **full-suite comparison on the merged
committed tree**, reconciling each branch's approved additions.

## Definition of done

1. The facade (≤ 400 lines, formatted) holds the widget and the State with
   verbatim lifecycle, the stored TV handler, lazy composition, the
   forwarder and the frozen accessor; callers are unchanged.
2. The guard registers the feature, bridge, facade cap, `TEMP(addon_hub)`
   rejection and bans; TV, theme and shape registries cover the feature.
3. All manifests pass with self-tests; every characterization test and
   golden passes unchanged (macOS and strict Linux).
4. No new diagnostics or suppressions; the three strict infos relocate by
   identity; gate 2 passes against the latest base and gate 1.
5. Local CI-equivalent checks pass (remote CI pending); the CI list holds
   the new tests and the metadata test; no failure allowlist growth.
6. Progress records commits, ownership, exceptions with exit milestones,
   the seam, and pending device checks (Android TV D-pad including the
   rename dialog, live marketplace and gitlab endpoints, configure in a
   device browser).
7. Stop after gate 2 and report.

## Explicitly not in scope

- `addons_screen.dart` (`ClassicAddonsScreen`, the switcher),
  `stremio_addons_page.dart`, the Stremio, marketplace and engine services,
  `StremioDropdown`, `TvTextField`, `see_all_theme`.
- Source ranking (`QuickPlayRanking.exactOrder` belongs to Sources).
- Bug fixes and behaviour changes, including everything below.

## Progress

- Step 0a starts at `fcf13373` in this dedicated worktree. `flutter pub get`
  completed first; Flutter 3.44.8 / Dart 3.12.2; no dependency or lock changes.
  The format-only original grows 3,415 → 3,416 lines. AST declaration structure,
  tokens except exactly two parser-identified optional commas, comments, seven
  bare radii and 13 shape calls are unchanged (`addon_hub/format-proof.json`).
  The temporary oversized facade retains all responsibilities until steps 1–7;
  this documented format raise exits through the planned extraction ratchets.
  All parser/kernel caches live inside this worktree; shared evidence writes
  are confined to `refactor-evidence/addon_hub/`. No branch switch or push.

- Step 0a validation: six existing metadata tests pass; stable whole analyzer
  comparison has zero added/removed identities. Initial concurrent analyzer
  attempts are retained as inconclusive build-input evidence; both stable
  probes use identical generated inputs and `--no-pub`. The facade has zero
  root diagnostics. `git diff --check` passes.

- Step 0 original-only work is frozen before any extraction. The approved
  accessor is the sole application delta (3,416 + 58 = 3,474 lines including
  its separating blank line); exact bytes are retained for the Linux capture
  comparison. Its token sidecar covers the live tear-offs, fresh snapshots and
  TV setter. The temporary facade ratchet exits with steps 1–7.
- Baselines `base` and `base2` have identical identities: 10,984 successes,
  13 failures, 28 errors and 20 skips; seam-only comparison passes. Evidence
  records SDK, HEAD, staged/tested trees and untracked inputs. The original
  proof worktree is detached at `227712b2` **inside this worktree** under
  `.dart_tool/addon_hub/original`; only test/tool overlays and the frozen seam
  are applied there. Parser packages remain checkout-local and explicitly
  supplied, including source-contract probes.
- Conservative fixture decisions: fresh close-tracking zone clients share one
  request log; only warm cases preseed through forced existing marketplace APIs.
  Four cache-cold files run in distinct isolates without setup fetches. Asset
  futures are cleared between test zones; real filesystem/database operations
  dispatch through `runAsync`, with the timeout case deliberately using fake
  time. Teardown releases owned test gates before disposal. Draft failures and
  corrected fixture assumptions remain in evidence; no accepted baseline or
  golden is updated to admit a regression.
- Original characterization: 119 affected tests pass, including the six
  existing metadata tests, unconditional TV source guard and six macOS pixel
  scenes. Scoped test analysis has no issues. Pixel goldens are captured only
  from the unchanged original; Linux capture remains pending Claude's handoff.
  `capture_addon_hub_linux_goldens.sh` resolves the exact step-0 subject and
  checks every application file against step 0a plus the byte-exact accessor;
  the empty `.gitkeep` directory marker is explicitly excluded as non-code.
- Observed original behavior resolves plan arithmetic/service ambiguities:
  metadata constraints are viewport minus 82 (border included), so 581/582
  join the requested widths. Legacy addon order remains z9/Cinemeta/a2;
  committed graph order is the registry's stored label order (Alpha/Cinemeta/
  Zulu), with resource ids as keys. Committed addon mutations notify
  `remote_webdav_sync_registry_records_v1`; legacy preference and metadata
  writes retain their own logical keys. A same-profile picker action pops the
  pushed hub without changing the current session. All are preserved.
- The strict original probe observes four infos (three original const sites
  plus import qualification ordering); the rename-only probe observes 21
  (17 public-constructor key infos plus those four). The frozen inventory uses
  per-symbol maxima, never sums. No production const or suppressions are added.
  The dependency report covers all 127 leaves with planned destinations and
  source bindings; destination wiring is reviewed and pinned when introduced.

- Step 0 validation closes on original code: `base3` has 11,096 successes,
  13 failures, 28 errors and 20 skips. Comparison against `base2` passes:
  exactly 112 new accepted characterization identities, no new failures,
  missing tests or new skips; the recorded tree is stable with no untracked
  inputs. Detached-original `original-characterization` passes all 119
  affected tests on its stable staged overlay. All ten real-config manifest
  self-tests pass on the isolated parser, including the opt-in closure
  extension and its individual identity/argument negatives. Existing configs
  remain unchanged. Format, size, architecture, storage, shape/floor, runtime
  source guards, CI analyzer and analyzer allowlist pass. Whole analysis has
  zero added identities against `base-analyze`; removed duplicate/generated
  diagnostics are retained as evidence (1,664 → 1,651). No allowlist changes.
- Mutation evidence is recorded against the restored detached original for
  all nine required mutations (`original-mutation-proofs.json`), each with
  its rejected test identity and tested tree. The initial harness wrongly
  expected `suite_evidence run` itself to return the Flutter failure code;
  corrected proof checks recorded outcomes, as the tool's verdict is always
  the comparison. No mutation is accepted and no application move occurred.
  Failed command attempts (including a wrong runtime-guard path) remain in
  this feature's evidence; corrected commands pass. Step 0b will record the
  original-only proof closure and the latest `base4` before gate 1.

- Step 0 checkpoint: `8c5981a4` (exact Linux-capture subject). The capture
  script's macOS preflight proves every application file is the format-only
  original plus the frozen seam, then deliberately rejects non-Linux capture.
- Step 0b original-only proof closure: the detached original is restored;
  all 119 affected tests passed before mutations. Each required mutation is
  rejected individually by its named test on a stable recorded tree: installed
  sort, missing Cinemeta sort, committed toggle by manifest URL, removed
  confirmation, guarded stale engine assignment, mount-guarded engine load,
  reordered cleanup, wrapped listener and trimmed row-node pool. Mutation
  diagnostics were reviewed; none is a compile/loading failure. Evidence and
  original macOS SHA-256 hashes remain in `refactor-evidence/addon_hub/`.
  No review findings have arrived at this checkpoint. `base4` is recorded on
  this committed original-plus-tests tree as the latest comparison base.

- Step 0 checkpoint: `8c5981a4` (exact Linux-capture subject). The script's
  macOS preflight proves every application blob is the format-only original
  plus the frozen seam, then deliberately rejects non-Linux capture. Blob
  identities verify all unchanged files in one tree listing.
- Step 0b closes the restored-original mutation proofs: all 119 affected tests
  pass before mutations; all nine mutations are rejected individually by named
  tests on stable recorded trees. The rejected diagnostics were reviewed;
  none is a compile/loading failure. No review findings have arrived here.
  `base4` is recorded on this committed original-plus-tests tree as the latest
  comparison base. An early baseline attempt begun before this documentation
  commit is retained as incomplete; it is not used as evidence.

- Linux originals received separately: all six supplied SHA-256 values match
  the PNGs; capture revision is `8c5981a4`, strict original run is 6/6 PASS.
  Provenance: calibrated `debrify-flutter:3.44.8` linux/amd64 Ubuntu 24.04,
  official Flutter 3.44.8 archive and libsqlite3-dev under Colima; calibration
  passed all 14 GitHub-captured TorBox/Debrid originals. Remote Actions remains
  unavailable (spending limit). Evidence: `linux-original-*` and
  `linux-provenance-verified.json` in this feature namespace. Assets are
  committed separately; only the Linux strict-default flag changes, with
  the six scenarios and macOS originals unchanged. Local Linux execution
  after extraction remains pending a reachable calibrated runner.

- Independent step-0 review closure (new step 0b, before extraction): all four
  P2 gaps and the requested P3 items are closed. Failed Automatic selection
  starts with the non-null z9 provider and restores that exact UI snapshot;
  the underlying preference store retains z9. Committed-mode Update seeds
  the actual resource graph, distinguishes the resource storage key from the
  manifest URL, requests exactly `GET https://z9.addon.test/manifest.json`,
  preserves resource identity/order and records the registry sync key.
  Null-sidebar LEFT asserts handled for Down and Repeat, plus a parent key
  probe proving the hub consumes it before ancestor traversal can do so.
  YAML import fails the real storage write after its non-dismissible blocking
  dialog shows (held external mutation barrier, then corrupt inventory);
  dismissal, stripped red snackbar, no engine file and no sync are checked.
- Review original proof: `review-original-final` runs all 121 affected tests
  on the detached `227712b2` application plus the frozen accessor/test overlay;
  all pass on a stable tree. `review-original-mutation-proofs.json` records
  four behavioral rejections, each running its entire relevant file:
  metadata-reset-null (16 cases), update-storage-key (16), left-null-ignored
  (31), import-failure-dialog-retained (19). No loading/compilation failure
  counts as a proof. Initial LEFT mutation survived the return assertion
  because ancestor traversal also handles LEFT; its preserved evidence drove
  the parent probe. Draft fixture/command failures remain evidence only.
- P3 closure: remove only the explicitly reviewed tautology; document why
  overlapping marketplace/engine requests require the frozen live tear-offs;
  send actual TV passthrough arrow events and submit via the real platform
  text-input search action; refocus the input before each action. Pin the
  actual post-install primary focus to the retained `market-row-0` node.
  The six golden scenarios and PNGs are unchanged. Step 0 item 6 now records
  the actual 581/582 picker threshold; contract 4 distinguishes committed
  registry order from the legacy order that catches both sort mutations.
- No application move or configuration/accessor change in this review batch.
  Scoped test analysis is clean; earlier checker, original strict-lint and
  source evidence remains applicable to the identical application/tool inputs.
  The previous full-suite run is preserved as `base4-pre-review`; the new
  committed review checkpoint will supply `addon_hub/base4`, compared against
  `base3` before any extraction. Expected change: only the two added test
  identities; gate comparisons must use this latest base.

- Review base is `da6bc0b4`: `base4` versus `base3` PASS, exactly two added
  successful identities, no fixes, failures, missing identities or new skips.
  Stable committed tree `344c80461bb2b74ed153d395ab370a75e68a84b3`, no untracked
  inputs: 11,098 successes / 13 failures / 28 errors / 20 skips. Whole analyzer
  also compares with zero added or removed identities. This is the required
  latest original addon-hub base for both gates; the original strict maximum
  remains 21 per-symbol infos, merged into `original-max-analyze.txt`.
- Step 1 moves only the two kind/source enums, label/capability functions and
  row-nav class. Every destination and the facade is registered for shape;
  total bare radii remain 7 and the global floor remains 488 with zero slack.
  Feature scanning is unconditional, theme patterns name each directory,
  and the guard enforces the exact bridge, bidirectional sources/settings
  bans and 500-line destinations. The per-entry pure bindings are reviewed.
  Facade: 3,418 physical lines; remaining responsibilities exit at steps 2–6.
  No parser/kernel cache uses a shared worktree namespace.

- Parser execution decision: the unchanged pinned AST adapter is also
  compiled as an ignored worktree-local AOT executable; its full production
  AST equals the existing kernel output (`parser-aot-equivalence.json`). An
  ignored local runtime dispatches only this exact parser-kernel path to it;
  every checker still receives the isolated package and runs all positives
  and negatives. The slow interrupted read-only attempt is retained; its
  complete successor is the acceptance evidence. No shared cache or tracked
  tool behavior changes.

- Step 1 verification: all ten manifests and their self-tests PASS on the
  isolated parser (aggregate `step1-checks.json`); 129 affected behavior,
  shape/floor and stale-runtime cases PASS, comparison to `base4` PASS.
  Strict per-symbol analysis has zero destination additions; whole diagnostic
  relocation and exact CI analyzer allowlist PASS (12 existing warnings).
  Architecture, size, storage, formatting and staged diff checks PASS.

- Step 2 moves only the whole pure widgets and each companion private State
  to presentation files, using manifest public names at the production caller.
  Constructors, defaults, focus nodes, layout and callback arguments remain
  verbatim; every moved comment is preserved. Imports are cleaned only for
  unused directives/order, with no const/key fixes. Per-entry bindings and
  strict original identities are reviewed. Facade: 2566 lines; all workflow,
  service state, legacy rows and builders remain for their scheduled steps.
  Every new destination remains in the shape manifest; the 7/488 budgets
  and zero slack are unchanged.

- Step 2 verification: all ten manifest/self-tests PASS; 129 affected tests
  PASS on the corrected shape registry and compare to `base4` PASS. Original
  strict diagnostics relocate with zero additions; exact CI analyzer allowlist,
  architecture, size, storage and format/diff checks PASS. macOS pixels and
  calibrated Docker strict Linux pixels both pass (6/6 Linux, unchanged PNGs).
  Shape placement follows token presence, not a nonzero radius budget; the
  first guard failure caught the wrong bucket, retained as evidence, and the
  fix preserves both assertions, the seven original bare radii and floor 488.
  Evidence snapshot startups are serialized after a concurrent index-lock
  collision; failed startups produced no accepted test evidence.

- Step 3 moves the 38 non-static/non-handler fields into four typed owners,
  plus installed/market/debrid loads, engine loads and engine actions into
  three plain sections. Nontrivial construction order remains installed
  service, marketplace singleton, navigation resources, then owned engine
  manager; the between-method revisions and blocking flag are placed with
  their owners. All initialization/disposal statements stay on the State in
  original order with receiver qualification only. Borrowed services stay
  borrowed; the one remote manager stays owned and closes last.
- Step 3 binding review pins 25 structural leaves, exact owner/section paths,
  plain class headers and 11 dependency bindings. `context`/`mounted` remain
  live functions and `setState` is the actual State tear-off. Both change
  listeners use one lazily composed section instance before registration.
  The short typed `_l` getter returns that existing engine-loading section;
  it avoids changing unmoved kind-guard syntax and exits in step 5. Navigation
  and engine handles `h`/`_e` likewise keep unmoved guards formatter-clean;
  they preserve the same typed owner instances. No wrapper listener appears.
- Orphan group banners and inline comments are carried byte for byte with
  their original responsibility; draft checker failures exposed omissions
  before any acceptance evidence. Three formatter-required brace sites are
  pinned only in moved methods, with complete raw prefixes and bodies;
  lifecycle has no formatting exception. No infos are added to the frozen
  original strict inventory. Facade: 2190 lines; action/menu/list/layout
  responsibilities remain for steps 4–6.

- Step 3 source-guard attempt retained: the first navigation handle `n`
  collided with the original local focus-node name in `_RowNav`; the unchanged
  whole-widget assertion caught normalization ambiguity. The unique short `h`
  handle avoids that collision and preserves unextracted one-line guard syntax.
  `_n` was also evaluated, but needed a brace exception outside the moved set;
  that draft is rejected. No source assertion or strict inventory is weakened.

- Step 3 verification: `step3-final-checks.json` records all ten manifest
  self-tests and architecture/size/storage/format/diff PASS. All 129 cases
  in `step3-affected-final` pass and compare to the latest `base4` with zero
  additions/missing/skips; macOS pixels pass. Strict Linux originals pass
  6/6 (`step3-linux`), unchanged image hashes. `step3-final-analyze-recorded`
  and its env record no added original strict identities or whole-repo
  diagnostics; exact CI allowlist retains only its 12 existing warnings.
  Gate 1 now runs on the committed step-3 tree, with no untracked inputs.

- Gate 1: committed `9f84dd5f`, tested tree
  `c66dae0a97b14237bb95c74945812989bfb5a8fb`, no untracked inputs or tree
  change. `gate1` versus original `base4` (`da6bc0b4`) PASS: 11,098 success,
  13 failure, 28 error, 20 skipped; no added/missing/newly skipped identities,
  no new failures or fixes. The unchanged historical `test_baseline.py` parser
  is replayed over those recorded events and the original base4 events:
  both return 1 with exactly the same 41 failures (32 absent from the stale
  nine-entry historical list). Its list is never updated; the observed
  identity comparison is the gate. Replay evidence and stable-tree envs stay
  in `addon_hub/`; no second full-suite run is needed to reparse those events.
- Step 4 moves install/URL/JSON actions, addon management, sheets/details/menu
  actions and the metadata write into their scheduled sections. All 32
  actual composition bindings and per-entry dependencies are reviewed;
  live State getters, captured messengers/themes, dialog `ctx`, post-frame
  install refocus and the previous metadata value stay at their original
  sites. The committed-mode Update still passes `manifestUrl`; toggle/rename/
  remove still pass `storageKey`. Facade: 1511 lines. No new formatting site
  beyond the three already required in moved loading methods.

- Step 4 verification: all ten manifests/self-tests and guards PASS
  (`step4-checks.json`); strict original-symbol and whole diagnostic comparisons
  report zero additions, exact CI analyzer allowlist PASS. All 129 affected
  cases and their comparison to base4 PASS; macOS and strict Linux originals
  pass unchanged (Linux 6/6). No characterization assertion or failure list
  changes. Commit follows this verified batch.

- Step 5 Linux prerequisite is reverified at `2b91f04f`: all six received
  SHA-256 hashes match both the worktree PNGs and their separately committed
  `95955bfc` bytes (`step5-linux-prerequisite.json`). Tests remain strict;
  no golden scenario or pixel is changed.
- Step 5 moves navigation/key policy, filters, filter bar/search, installed/
  market/engine lists and whole market/engine rows with their private States.
  The 71 actual dependency bindings are reviewed before final scaffold pinning;
  UI/listener callbacks remain genuine source tear-offs or the original
  argument-capturing closures. All six exact brace sites are in moved methods;
  lifecycle remains receiver-only. The earlier `_l` alias is removed. A typed
  `_el` getter to the same engine-list instance keeps the retained body's
  one-line guard unchanged and exits in step 6. The sole retained empty-state
  builder is bound directly from the State, marked TEMP with exit step 6.
  Facade: 271 lines; its oversized-file baseline is removed now at ≤800.

- Step 5 strict analyzer caught a redundant facade `flutter/services.dart`
  import after key handlers moved. That failed attempt is retained. Import
  cleanup removes it without changing a declaration; the strict inventory
  remains frozen. All ten self-tests passed the initial step-5 tree; the final
  import-only recheck reruns this manifest/self-tests and all shared guards,
  reusing the other nine complete results whose inputs are unchanged.

- Step 5 verification: all ten manifest/self-tests PASS (nine unchanged
  results reused, this feature rerun, `step5-final-checks.json`); all guards,
  format/diff and exact CI analyzer allowlist PASS. Strict original symbols
  and whole diagnostic relocation have zero additions. All 129 affected
  identities match base4 and pass; macOS and strict original Linux pixels
  pass (Linux 6/6), unchanged hashes and no golden-test changes.

## Found, not fixed

All pre-existing; the extraction keeps each exactly.
1. `_loadEngines`'s entry `setState` is unguarded (261), reached after
   awaits in install, delete and import (311/357/446).
2. `_showActionsMenu` uses `context` after `await showMenu` (1183–1193).
3. Market loads have no generation: same-source double publish, an older
   error over a newer success, no reload after an error (544).
4. The shared engine revision's stale path assigns `_knownRemoteEngines`
   unguarded and re-bumps the revision (270–273).
5. The metadata write is optimistic with no generation (1742–1757);
   `List.sort` order for equal providers is unspecified above 33 (the
   pinned SDK insertion-sorts up to 33).
6. `_toggleAddon` is unawaited, unhandled and unconfirmed (860, 1037).
7. `_updateAddon` uses `a.manifestUrl`, not `storageKey`; no try (937–960).
8. `_addByUrl`'s `TextEditingController` is never disposed (633).
9. The rename dialog's raw `TextFormField` (873) is a TV DPAD risk
   (flutter#177360) that the guard's `\bTextField\(` misses.
10. The type filter drops addons with empty `types` (561).
11. `_hasDebrid` starts `true`, is probed once and never refreshed.
12. Every addons-changed notify shows the full spinner, unmounting a focused
    row after toggle, rename or remove; focus returns only after installs.
13. A market install reloads twice (584 plus the listener).
14. Sheet actions use build-time `StremioAddon` snapshots (1613).
15. The blocking dialog can stay up if the hub unmounts mid-operation (497).
16. `_marketNav.ensure` creates focus nodes in build (1902), never trimmed.
17. The touch-only X close nests the listener's `setState` (1554–1557).
18. Copy URL's `Clipboard.setData` is unawaited (1106).
19. A platform check (130), debrid storage imports and service singletons
    sit in the widget; no localization.
20. Dormant: `_MarketRow.navCount`; installed rows pass a null logo;
    `setStremioAddonHubEnabled` has no caller and its doc says
    "per-device" though the flag is profile-scoped.
21. CI: `checks.yml` once listed two facades after `| tee analyze.txt`
    (not analyzed); fixed upstream at `b5e90a55`, kept as a rule.
22. `'addons'` and `'addon_hub'` screen views both fire on every mount.

23. A rejected metadata write leaves the SharedPreferences cache optimistic
    even though the underlying store retains its prior value; the hub restores
    its captured UI value. The extraction preserves this original behavior.
