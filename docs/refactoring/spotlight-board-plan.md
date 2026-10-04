# Spotlight board refactor — plan

Written 2026-10-04 on `refactor/codebase` at `b5e90a55`. The file is
unchanged since `88b54092`; the only later commit edits `checks.yml`.
Follow [AGENTS.md](../../AGENTS.md).

Read first: `docs/refactoring/playlist-content-plan.md`,
`iptv-settings-plan.md` and `merged-detail-plan.md`, and the Progress
sections of the PikPak, playback-settings, IPTV-settings and
playlist-content plans. This plan reuses their technique, checker, tooling,
staging and gate procedure, and states only what differs. That procedure
covers:
- the manifest and `check_verbatim_moves.py`;
- callback identity, with wrapper and receiver-swap negatives;
- `suite_evidence.py` tree-recording evidence;
- real-config fixtures;
- original-code worktree proofs and mutation negatives;
- the wiring checklist;
- Linux goldens captured from the original code in the calibrated local
  Docker image.

**Execution.**
- The work runs in its own git worktree on `refactor/spotlight-board`, cut
  from `refactor/codebase`, in parallel with other refactors. Progress
  records the execution base SHA at step 0, and every proof names it.
- Commit after every step; never push. Gate commits contain `gate`.
- Remote CI stays pending until Claude pushes, so every step runs the local
  CI-equivalent commands.
- Evidence goes under `refactor-evidence/spotlight_board/`.
- **Every manifest run passes an isolated `--parser-package`**, including
  self-tests and other features' manifests. The shared parser cache
  collides across worktrees (exit 253; see PikPak Progress).

## Goal

`lib/widgets/home/spotlight_board.dart` is 3,724 lines: 36 imports, 11
declarations and no `part` files. It is the Spotlight board used by Home
(hero reel plus shelves), the search board and collection folders. It
contains:
- the hero: art, warm-up, ambient tint, side flip, the ambient-trailer
  cadence and the desktop decoder lease;
- D-pad movement and progressive loading;
- the large-screen selection model;
- root, hero and shelf painting;
- the 790-line card (`_Card`/`_CardState`).

Split it into a new feature, `lib/features/spotlight_board/`, **moving code
verbatim**. The following stay unchanged: the widget tree, keys, `const`
placement, `RepaintBoundary`s, focus, build order and both States'
lifecycles.

**User decisions (2026-10-04).**
- Spotlight is in the series.
- Ambient trailers are decoration, not content playback. The following
  **move verbatim**, pinned as contracts with source guards. No new seam is
  added, and device behaviour is pending verification.
  - the hero's 2 s cadence timer;
  - host-supplied trailer mounting;
  - the three `onTrailerStop` calls;
  - the rule that the hero yields before a desktop card video;
  - card-level trailer mounting.
- The destination holding `_buildCard` (487 lines, about 531 formatted)
  gets a **documented size exception**, because a move can't divide a
  method body. Exit: a later behaviour-level card decomposition.

**Why a new feature behind a facade.**
- Seven `lib/features/home/presentation/` files import the board's types.
  `check_search_architecture.py:546–556` allows cross-feature imports only
  into `<other>/models/`.
- The facade at the original path keeps all **9 production** importers and
  all **19 test** importers unchanged. The 9 production importers are the
  seven home files, `collection_folder_screen.dart` and
  `spotlight_catalog_card_cache.dart`.
- Four more files reach the State through `GlobalKey<SpotlightBoardState>`
  without importing it.
- The name `spotlight_board` avoids a clash with the six `home_spotlight_*`
  files.
- Placing it in `lib/features/home/` is allowed but would reopen a
  completed feature with a legacy bridge.

**Temporary exceptions and their exits.**

| Exception | Exit |
| --- | --- |
| State-driven sections | Notifiers keyed by route instance |
| A `legacy_spotlight_board/` bridge importing `DiagnosticLog`, `StremioService` (card description), `MetadataPreferencesService`, `ProfileRuntime` and `DebrifyImageCache` | Data contracts |
| Direct `PlatformUtil` TV reads (contract 9) | A TV-capability adapter |
| Legacy text (`'Loading more'`, `'Open'`, `'Series'`/`'Film'`, `'★ x.x'`) | Localization migration |
| `_buildCard` size | See the size exception |

## Public surface (importable from the facade, unchanged)

**`SpotlightCard`, `SpotlightCardShape` and `SpotlightShelf` (40–245).**
- They stay byte-identical: docs, field order, constructors and the two
  pure methods.
- They depend only on `lib/models/` types plus Flutter types. Because of
  the Flutter types, they can't go in `models/`.
- They move to `presentation/spotlight_board_types.dart`. The facade
  re-exports them:
  `export '…/spotlight_board_types.dart' show SpotlightCard, SpotlightCardShape, SpotlightShelf;`
  (the IPTV-settings precedent).
- They can't stay. `SpotlightBoard` (about 163 formatted lines) plus the
  lifecycle (about 136) already fill most of a 400-line facade.

**`SpotlightBoard` stays in the facade.** Its `createState` names the
State, so moving it would back-import the facade. It keeps its 24 fields,
constructor and docs (247–268), and its statics: `groundOf`, `groundLowOf`
(420–422, an Android TV gate) and `leftThirdBusy = 0.32`. It stays
non-final and subclassable.

**`SpotlightBoardState`** keeps `with
MetadataPresentationMixin<SpotlightBoard>` and stays non-final. It keeps
exact forwarders for `heroWarmupProvider`, `currentHeroId`,
`heroAlignmentItemId`, `focusShelf`, `focusTarget` and the four mixin
overrides.

**Subclass contract.** `test/spotlight_hero_ambient_policy_test.dart:13–36`
subclasses both classes and overrides `metadataArtworkPending`. The State
calls mixin members at:
- 788: `preloadMetadata`;
- 1001 and 1352: `refreshMetadataPresentation`;
- 1057/1058/1062/1065: `metadataArtworkPending`, `usesMetadataProvider`,
  `metadataPreferences`;
- 1080: `heroPresentation`;
- 1327: `metadataArtworkPending`.

Moved code **must keep calling these through the State instance**: a live
tear-off or closure with the State as receiver, evaluated at the original
site. It never uses a cached value, `super`, or another receiver. The card
State follows the same rule for its own mixin.

Enforcement:
- the checker's receiver rule, with negatives for a captured bool, `super.`
  and a non-State receiver;
- the existing test;
- a new case where the override flips `_flip`'s pending-artwork branch,
  observed through `heroAlignmentItemId`.

## What it contains (lines at `b5e90a55`; after the format commit the manifest is authoritative)

| Lines | Area |
| --- | --- |
| 1–432 | Imports (unsorted), public types, `SpotlightBoard` |
| 434–553 | `_Tier`, `_M` (metrics) |
| 555–801 | State header, large-screen selection, metadata hooks, hero warm-up |
| 803–1091 | `_onBoardScrolled`, `_stopRolling`, desktop lease, `_restartCadence`, `_jumpTo`, `_onArtDone`, hero art |
| 1093–1229 | `initState`, `didUpdateWidget` (99), `_onHeroFocus`, `dispose` |
| 1231–1703 | Ambient, tint, flip; movement, progressive DOWN, `_onKey`, `focusTarget` |
| 1705–2738 | `build`, `_board` (215), hero paint (`_heroBackdropContent` 186), shelves |
| 2741–2931 | `_ShelfTitleLink`(+State), `_LogoOrTitle`, `_HeroOpenPill` |
| 2933–3724 | `_Card`, `_CardState` (`_buildCard` 3237–3723) |

**State and resources.**
- The board State has 32 instance fields (none `late`) and 5 static
  consts.
- `_CardState` has 20 fields, including the lazy **`late final TvHoldOk
  _hold`** (3130–3133). Its first access can be `dispose`'s
  `_hold.reset()`.
- Owned resources: `_scroll`, `_veilMetricsRevision`, and six timer sites
  (781, 991, 1026, 3076, 3100, 3505).
- Not owned: focus nodes, tickers, controllers and subscriptions.

## Contracts that must not change

Each contract is pinned by source guards and, where observable, by behaviour
tests. The guards compare whole bodies, comments included, through
`test/support/spotlight_board_source.dart`. That reader covers the facade
plus the feature files, with manifest renames reversed.

1. **Lifecycle.** These stay **verbatim in the facade's State**, with
   receiver-only qualification.
   - `initState` (1094–1104): `super` → `_heroId` →
     `addListener(_onHeroFocus)` → `_scroll.addListener(_onBoardScrolled)` →
     the **unguarded** post-frame `_probe(); _restartCadence();
     _preloadHeroes();`.
   - `didUpdateWidget(SpotlightBoard old)` (1107–1205): all 11 steps,
     including the Android TV insertion anchor (1110–1122) and the
     `identical` gates (1123–1127, 1165).
   - `didChangeDependencies` (1359–1364).
   - `dispose`: `_cancelWarmups` → `_veilMetricsRevision.dispose()` →
     `removeListener(_onHeroFocus)` → `if (_rolling)
     widget.onTrailerStop?.call()` → `_cadence?.cancel()` →
     `_scroll.dispose()` → `super.dispose()`.
   - The card State keeps its four lifecycle methods verbatim. Its
     `didUpdateWidget` (3168–3199) sends the `false` report through the
     **old** widget's callback. Its `dispose` (3202–3213) has seven steps.

   **Callback identity:**
   - `_onHeroFocus` (1097, 1134, 1135, 1224), `_onBoardScrolled` (1098)
     and `_onArtDone` (991, 1026) keep their receiver and member.
   - The per-build card tear-offs (2707–2731) and `onTrailerStart:
     widget.onTrailerStop` (2727) keep their targets.
   - A section that owns a tear-off target is created once per State,
     through a nullable cached field (never `late`, never per build).
2. **Hero cadence: one clock, one owner.**
   - `_restartCadence` (967–992) keeps its gate order and `Timer(const
     Duration(seconds: 2), _onArtDone)` (991). The comment contradicts it
     (Found, not fixed, 1).
   - `_onArtDone` (1006–1044) keeps its 1 s hidden-route retry.
   - `_stopRolling` (933–937) **always** calls `onTrailerStop` once rolling.
   - `_scrolledAway` (865) and `_onHeroFocus` are unchanged. The reel never
     auto-advances.

   Tests use fake time with recording hosts:
   - no `onDwell` before 2 s, then exactly one;
   - none with trailers off, on dpad without hero focus, or with a desktop
     owner;
   - the hidden-route retry;
   - each `onTrailerStop` path counted:
     - 936, through `_jumpTo`, `_down`, focus loss and scroll-away;
     - 959;
     - 1225, only when rolling at unmount.
3. **Host trailer mounting (no Opacity over the hole).**
   - `if (widget.trailer != null) Positioned.fill(child: widget.trailer!)`
     stays at 2041 (compact) and 2268 (wide), with its comments, and is
     never gated on `_rolling`.
   - `_heroBackdropContent` keeps its child order: image, trailer, identity
     scrim, ground fade, veil.
   - **No `Opacity`, `ShaderMask`, `ColorFiltered`, `BackdropFilter` or
     saveLayer ancestor is added.**
   - On dpad, the `_heroBackdrop` opacity stays exactly 1.0 or 0.0 (2185),
     and there is no `ShaderMask` (2173).

   Tests:
   - an ancestor-chain assertion from a sentinel trailer, in dpad and touch
     modes, with animations on and off;
   - the trailer stays mounted while not rolling.
4. **The hero yields before a desktop card video.**
   - `_onDesktopPreviewActivityChanged` (943–964) returns on dpad and acts
     only on empty ↔ non-empty transitions.
     - On non-empty it cancels and nulls the cadence, sets
       `setState(_rolling = false)` if rolling, and **always** calls
       `onTrailerStop`.
     - On empty it calls `_restartCadence`.
   - The card's `_reportDesktopPreviewActivity` (3156–3165) and
     `_previewActive` (3143–3147) are unchanged, as is the owner gate in
     `_restartCadence` (980).

   Tests:
   - hovering from A to B never restarts the hero;
   - the hero's stop precedes a card preview or trailer mount;
   - leaving every card re-arms the hero.
5. **Card trailer.**
   - `_armCardTrailer` (3067–3085) keeps the 2 s dwell, its guard order, and
     `onTrailerStart` before `_trailerAttempted` and
     `setState(_trailerRequested)`.
   - The mount (3494–3514) keeps its condition (`_trailerRequested &&
     _activeCard && !_moving && _canExpand && widget.trailerEnabled`),
     `ValueKey(c.metadata!.id)`, `SpotlightCardTrailer` and the 2 s
     text-hide timer.
   - Also unchanged:
     - `CollectionFocusArt` (3482–3488);
     - `previewBuilder` (3489–3493);
     - growth 1.38/1.18;
     - the tween durations (3224–3232).
   - Tests use fake time and find the trailer by type without reaching its
     resolve. Engine start is pending device verification.
6. **Card-size decoding (no keep-alive; eviction-thrash fix).**
   - `decodeW` (3256–3259) keeps its formula and comment:
     - no `growth` term;
     - the 1.18 factor, off on Android TV;
     - DPR × 1.1;
     - `.clamp(100, 1000)`.
   - It is used for both the primary (3446) and fallback (3472) images.
   - Also unchanged:
     - `_heroDecodeWidth` (742–745);
     - the 900/1400 poster fallbacks;
     - the 520 logo;
     - the warm-up cache-key match
       (`spotlight_hero_ambient_policy_test.dart:130–136`).
   - A guard rejects `KeepAlive`, `AutomaticKeepAliveClientMixin` and
     `IndexedStack` in the feature and facade.
   - Tests check decode width per shape, focus, DPR and TV flag.
7. **Parallax cursor rules (eef825c).**
   - Off parallax, the card uses the `FocusExpressionBox` fallback
     (3573–3579), not unconditionally.
   - `ParallaxFocus` (3395–3401) and `CollectionFocusGlow` share one
     `active` expression.
   - The passthrough `Stack` stays mounted in both states (3589–3603).
   - **Hover is gated on `!widget.dpad`, not on `PlatformUtil`.** This
     covers:
     - `hoverable`/`MouseRegion` (2728, 3667–3673);
     - `_ShelfTitleLink` (2571);
     - the wide hero's `GestureDetector` (2137);
     - the tappable dots (2415).
   - `ParallaxTravel.note` runs before each `requestFocus` (1340) and on
     paging (1353).
   - New test: no `MouseRegion` on dpad.
8. **Responsive tiers and `wideTouchScale` (c2256ad).**
   - The tier is `dpad ? wide : <600 compact : <1100 mid : wide`.
   - `k => (dpad || compact) ? 1.0 : wideTouchScale(w)` (482).
   - Also unchanged:
     - the `k`-scaled insets and type (2394–2396, 2446, 2455, 2467);
     - the hero fractions 0.64/1.0;
     - the 88/540 overlap;
     - the rich-card condition (1724–1728).
9. **TV performance gating.**
   - `PlatformUtil.isAndroidTvCached` stays exactly at 420, 1110, 3232,
     3257, 3457–3462 and 3705, and `isTvOS` at 3325.
   - The dpad choices are unchanged:
     - `lowPower` backgrounds (1898–1900);
     - the snapped veil and opacity;
     - no `ShaderMask`;
     - the hero fades (747–755).
   - Tests set `debugSetAndroidTvCached(true)` per site and reset it in
     teardown. No existing `spotlight_*` test covers these sites.
10. **Rebuild and repaint boundaries (perf-sensitive).**
    - The `RepaintBoundary`s at 1909 and 2362 stay.
    - The vertical `ListView.builder` keeps `cacheExtent: 600`,
      `itemCount + 2`, `findChildIndexCallback` and the `KeyedSubtree`
      keys.
    - `_walk` has no `setState`.
    - The veil stays driven by an `AnimatedBuilder` over
      `_scroll`/`_veilMetricsRevision`.
    - `ParallaxRichScope` and every inventoried key stay.
    - **No builder becomes a widget, no wrapper is inserted, and no `const`
      changes** (88 `const ` lines; 0 `prefer_const_constructors`).

    Tests:
    - shelf and card `State` objects survive a focus move and a sections
      update;
    - a focus step rebuilds no board subtree;
    - the existing widget-count tests.
11. **D-pad and focus.**
    - `_onKey` (1614–1668):
      - handles KeyDown and KeyRepeat only;
      - re-syncs `_row` from live focus;
      - Left at column 0 or on the first slide returns `ignored`, so the
        sidebar receives it;
      - Select opens the hero only at `_row < 0`.
    - Also unchanged:
      - `_down`/`_up`;
      - progressive DOWN (`_loadingMoreShelves`; the 3 s `DateTime.now()`
        window);
      - `_focusRow`'s nearest-attached fallback and ±300 retry;
      - `_walk`'s load-more threshold;
      - the `focusTarget()` priority;
      - `focusShelf` via `_shelfExtent`, which must match the shelf layout;
      - the card `Focus` handlers, `TvHoldOk` (600 ms) and `ensureVisible`.
    - New tests: the Android TV insertion anchor; a held
      `onLoadMoreShelves` future, with real wall time for the 3 s window.
12. **Large-screen selection.** These are unchanged, and the 21 existing
    cases cover them:
    - the 60% cursor;
    - 65%/24 px visibility;
    - 4 px ties;
    - desktop pointer ownership;
    - the width freeze;
    - short-row padding.
13. **Ambient, tint and stale results.**
    - `_probe` keeps its generation and `mounted` guards.
    - `_emitAmbient` keeps its dedupe.
    - `_flip` keeps its per-id memo and pending-artwork rule.
    - The card description checks its captured scope after each await
      (3096–3114) and at paint (3267).

    Tests:
    - A late tint after a hero change is dropped. This uses a held provider
      if the original allows it, otherwise it is source-guard-only.
    - A held `fetchMetaDetails` (`MockClient`) answered after a profile
      switch or unmount publishes nothing.
14. **Collection identity.** These are unchanged:
    - the `identical` gates (1123–1125, 1165, 3181, 66, 82);
    - the in-place `_col` and `_visibleCards`;
    - node identity in `contains` (1377, 1433).
15. **No playback seam.** No feature or facade file imports `media_kit`,
    `hero_trailer_backdrop`, a trailer engine, `video_player_launcher` or
    `player_launch`; a guard enforces it. The only mounts stay
    `SpotlightCardTrailer` and `CollectionFocusArt`.

## Destination layout

All destinations are under `lib/features/spotlight_board/presentation/`.
Each is at most 500 formatted lines, except the size exception. The step 0
dependency report settles exact membership from the actual imports.

**Outside the bridge:**
- `spotlight_board_types.dart` (re-exported);
- `spotlight_board_metrics.dart` (`_Tier`, `_M` → `SpotlightBoardTier`,
  `SpotlightBoardMetrics`);
- `spotlight_shelf_title_link.dart`;
- any other service-free whole widget class.

**`legacy_spotlight_board/`** (the bridge; exact path in the guard):
- board owners: the 32 fields, in route-owned records;
- sections for:
  - selection;
  - hero art and warm-up;
  - cadence and lease;
  - ambient and flip;
  - movement and focus;
- paint files for:
  - the root (`build` body and `_board`);
  - the compact hero;
  - the wide hero and backdrop;
  - the hero foreground, identity and dots, with `_LogoOrTitle` and
    `_HeroOpenPill`;
  - the shelves;
- the card (`_Card`/`_CardState` → `SpotlightBoardCard` /
  `SpotlightBoardCardState`), with its verbatim lifecycle, the `late final
  _hold`, its owners and its trailer and description sections;
- **`spotlight_board_card_layout.dart`** (`_buildCard` alone).

**Cross-class privates** become manifest-listed public names:
- `_freezeScrollWidth` (585);
- `_setWideSelection` (590, 592, 672);
- `_f` (610, 613, 683);
- `_h` (610, 682);
- each card private that `_buildCard` reads.

**The facade** holds the imports, the re-export, `SpotlightBoard`, and the
State with its mixin, verbatim lifecycle, forwarders, overrides, `build`
forwarder and composition.

**Its cap is measured.**
- Step 0 measures the formatted parts that must stay: `SpotlightBoard`
  (about 163 lines), the lifecycle (about 136), and the overrides,
  forwarders and imports.
- The target is 400 lines. If the measured parts plus minimal composition
  exceed it, the cap becomes the measured value, at most 450 (the
  merged-detail precedent).
- Progress records the arithmetic. `TEMP(spotlight_board)` rejection
  enforces the cap from step 7.
- No accessor is planned: the public seams and host callbacks suffice. If
  step 0 proves one necessary, it is frozen and counted, and its seam-only
  raise is recorded.

**Guard rules** (step 1, `check_search_architecture.py`):
- `spotlight_board` in `FEATURES`;
- `SPOTLIGHT_BOARD_FACADE`/`_BRIDGE`/`_COMPLETE = False`;
- the bridge in `LEGACY_PLAYBACK_BRIDGES` (still no `http`,
  `shared_preferences` or `sqflite`);
- no facade back-import;
- bans in both directions between `spotlight_board` and `home` (except
  `models/`);
- the playback-import and keep-alive bans;
- 500-line caps;
- `SPOTLIGHT_BOARD_SIZE_EXCEPTIONS`.

## Size exception

`SPOTLIGHT_BOARD_SIZE_EXCEPTIONS = {"lib/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_card_layout.dart": <measured>}`

- The value is measured in the file's creation commit: about 531 lines plus
  imports and the section header, under the 800 ceiling.
- Its comment states the reason (a move can't split the method). It also
  states the exit: a **later behaviour-level card decomposition** into
  art, caption and expanded-description widgets. That change alters the
  element tree, so it needs its own goldens and review. No other exception
  is authorized.
- The file holds `_buildCard` alone, and the checker rejects growth.
- The card class (about 867 formatted lines) is split regardless: State
  plus sections in one file, layout in another.

## Technique

As in the playlist and merged-detail plans, plus:

1. **Format-only step 0 commit** (`style(spotlight): format the original
   spotlight board`).
   - The file isn't format-clean: the formatter changes 850 lines, making it
     3,896 (+172).
   - The commit formats this file only and proves token equality with the
     original except whitespace and any AST-identified optional formatter
     commas, listed by node. Negatives (an edited comment or literal, or a
     non-optional comma) must fail. It also proves idempotence.
   - **The same commit raises `file_size_baseline.txt:19` by hand**, from
     3,724 to the measured value; it is lowered from step 1.
   - Formatting adds **6 `curly_braces_in_flow_control_structures` infos**
     (wrapped `if`s at original 66, 687, 700, 717, 1065 and 1112). They are
     recorded by identity (rule, enclosing member, message) in
     `spotlight_board/base-fmt`, per the merged-detail precedent, and are
     not fixed.
   - If a destination's nesting wraps a different `if`, the per-symbol
     comparison reports it. It is then handled only as a registered
     formatter-brace site: braces around the unchanged statement, raw
     prefix pinned (the playlist precedent).
   - The format commit is the **ORIGINAL** for all later proofs, the
     detached worktree and the Linux capture.
2. **Strict-lint baseline.**
   - Analyze the formatted original under
     `lib/features/analysis_options.yaml`, in a detached worktree inside the
     ignored `.dart_tool/`, qualifying relative imports only.
   - Expected:
     - 15 `directives_ordering`;
     - 10 curly (4 original, 6 format-induced);
     - 2 `deprecated_member_use`;
     - 1 `avoid_renaming_method_parameters`;
     - 0 `prefer_const_constructors`.
   - A throwaway **rename-only probe** applies exactly the manifest's public
     renames: card and State, title link and State, logo, open pill,
     metrics, tier and card members. It inventories by identity the
     resulting `use_key_in_widget_constructors` infos and any
     `library_private_types_in_public_api` infos.
   - The comparison combines baseline and probe by maximum observed count,
     never by sum.
   - Add no `Key? key` parameters and make no constructor or `const`
     change.
   - New files write imports sorted. The removed `directives_ordering`
     infos are documented.
   - There are 0 warnings, so no allowlist entry is expected.
3. **Live getters.**
   - Sections reach `widget`, `context`, `mounted` and `setState` through
     registered live getters, and mixin members through the State. Nothing
     is hoisted.
   - Build-time writes stay in their builders: `_lastMetrics`,
     `_heroBandH`, `_selectionViewport`, `_scrollRowId`,
     `_largeCardInteractions`, `_paintedGrowth` and the `_flip` memo.
   - **The verbatim checker compares comments: never reword one.**
4. **One owner per timer.** The cancel-without-null sites (1214, 1463,
   1226) are preserved.

## Steps

| # | Work | Contracts |
| --- | --- | --- |
| 0 | Baseline; format commit and `base-fmt`; lint probes; deps report, manifest, config; characterization tests and goldens; CI list; inventory; Linux script; step 0b review | Nothing moves |
| 1 | Guard registration; public types (re-exported); metrics; shape and theme registration begin | Surface |
| 2 | Title link, logo, open pill; card and card State (owners, trailer and description sections, layout section with its exception) | 5–7, 15 |
| 3 | Board owners (32 fields); lifecycle verbatim | 1, 14 |
| 4 | Hero art and warm-up, cadence and lease, `_onHeroFocus`, ambient, tint, flip, metadata hook bodies. **Full-suite gate 1.** | 2, 4, 6, 13 |
| 5 | Selection, scroll, movement, progressive DOWN, `focusShelf`/`focusTarget` bodies | 11, 12 |
| 6 | `build` forwarder, `_board`, hero paint, shelves. Committed Linux originals are a prerequisite. | 3, 7–10 |
| 7 | Composition, facade cap and `TEMP`, guards, CI. **Full-suite gate 2.** | All |

### Step 0

1. **Baselines.**
   - `spotlight_board/base`, on the untouched branch head:
     `suite_evidence.py run` plus the whole-repo analyzer, with tree and SDK
     provenance (Flutter 3.44.8 / Dart 3.12.2, `--no-pub`).
   - After the format commit, `spotlight_board/base-fmt`. It must equal
     `base` by rule, symbol and message, except for the 6 recorded infos.
2. **Dependency report** (`docs/refactoring/spotlight-board-deps.md`). For
   every leaf (fields, getters, methods, the 6 classes, comment fragments)
   it records:
   - the destination;
   - reads of `widget`, `context`, `mounted`, `setState` and mixin members;
   - tear-offs;
   - the timer owner;
   - a wiring-checklist entry, reviewed before any scaffold is pinned.
3. **Checker.** `dev/tool/spotlight_board_manifest.tsv` (LF only; check the
   staged diff) and `spotlight_board_checker_config.json`, with real-config
   fixtures. Negatives:
   - `_onHeroFocus` receiver-swapped or wrapped;
   - a reordered or dropped dispose step in either State;
   - a dropped `onTrailerStop` at each of the three sites;
   - a rebound `onTrailerStart`;
   - a trailer gated on `_rolling`;
   - an inserted `Opacity`;
   - a changed 2 s duration;
   - a mixin call through a captured value or `super`;
   - an eager `_hold`;
   - a section built per build;
   - a reworded comment;
   - a new `const`.
4. **Harness** (`test/support/spotlight_board_fixture.dart`).
   - Setup:
     - mocked `SharedPreferences`;
     - root `ProfileRuntime` init and reset;
     - `AppThemeScope` with a named look (Spotlight parallax and one
       other);
     - pinned `tester.view` size and DPR;
     - host-owned focus nodes.
   - Recording callbacks: `onDwell`, `onTrailerStop`, `onAmbient`,
     `onLoadMoreRow`, `onLoadMoreShelves` and `onExitTop`.
   - Platform and time: `debugSetAndroidTvCached`/`debugSetTvOS`, reset in
     teardown; `MockClient`; `ParallaxTravel.clock`.
   - **No `pumpAndSettle`.** It fires the 2 s cadence, the 2 s dwell and the
     300 ms description timer.
   - Schedule a frame after post-frame callbacks.
   - Fake time runs outside `runAsync`, with IO inside it. The 3 s window
     uses real wall time.
   - Use braces in tests and January UTC dates.
   - Prove one fixture on the original first.
5. **Characterization tests**, under
   `test/features/spotlight_board/presentation/legacy_spotlight_board/`.
   - They are recorded against the ORIGINAL, and each passes first in the
     detached original worktree.
   - Coverage follows the contracts.
   - Real engine start, tvOS's single `VideoOutput` and MediaKit queuing
     are **source-guarded and pending device verification**.
6. **Goldens.** None exist today. Capture deterministic scenes from the
   ORIGINAL: execution captures macOS, Claude captures Linux.
   - **Scenes:**
     - wide desktop at 1440×900;
     - TV dpad at 1920×1080, focus on row 0 column 1, card expanded;
     - compact phone at 390×844;
     - mid tier at 900 wide;
     - collection `shelvesOnly` with `paintBackground: false`;
     - one non-parallax look.
   - **All scenes:**
     - trailers off (`trailersEnabled: false`; `onDwell` and `trailer`
       null);
     - `animationsEnabled: false`;
     - DPR 1.0, pinned theme, `en-US`, text scale 1.0;
     - a named initial focus or none;
     - bounded pumps.
   - **Fixed artwork.** Step 0 tries to prove a seam-free path that serves
     bundled PNG fixtures to `DebrifyImageCache.manager` on the original
     (for example `HttpOverrides`). Otherwise, the scenes use deterministic
     placeholders (null `image`, `coverEmoji`, the ground hero), and
     Progress records that choice.
7. **CI list and pre-existing failures.**
   - Add all 19 importers, the new tests and the golden test to
     `ci_behavior_tests.txt`; none is listed today.
   - The HEAD run gave 265 passes and 5 errors. All five are on the
     historical list (`search-screen-initial-failures.txt:7, 8, 31, 32,
     41`), and none is in `ci_behavior_known_failures.txt`:
     - the compact cadence test (Found, not fixed, 1);
     - two `search_title_suggestions` "unresolved suggestion submits
       Catalog title search" cases;
     - two `collection_native_browser` "Spotlight Home folder opens all rows
       directly" cases.
   - Add **only the failures `base` actually observes**, by identity, in the
     same commit as the list change, under a dated comment:
     `# 2026-10-04 spotlight_board step 0: pre-existing, newly exposed by CI
     coverage; observed in spotlight_board/base`. They are not fixed.
   - `theme/shape_manifest_test` passes now, despite an old list, and must
     keep passing.
8. **Source-text inventory.**
   - **Shape:** 3 bare radii and 0 token calls: `circular(999)` at 1930
     (`_board`), `circular(2)` at 2502 (`_dots`) and `circular(21)` at 2911
     (`_HeroOpenPill`).
     - From step 1, register **the facade and every destination**,
       including zero-count files, in `kExtractedShapeResidue`, never in
       `kShapeResidue`.
     - Ratchet so the slice totals 3 at each checkpoint and the facade ends
       at 0.
     - The 488 token floor is unaffected.
   - **Theme:** `theme_surface_manifest.txt:8` (`home_widgets`) gains
     explicit per-directory patterns: `…/spotlight_board/presentation/*.dart`
     and `…/legacy_spotlight_board/*.dart`. `ls $@` without `globstar`
     treats `**` as one level. Measure before and after.
   - **`light_ink_inventory.py:72`:** add both directories.
   - **Guards are unconditional.** They read the feature folder whether or
     not it exists, and a missing file fails.
   - **Verify unaffected:** `profile_source_guard_test`,
     `stale_runtime_guard_test`, `theme/source_guard_test` and
     `storage_member_map.tsv`.
   - **`checks.yml` (step 7):** add the facade to the format (44) and
     analyze (52) lists, and `test/support/spotlight_board_*` to the format
     list. **Insert paths before `| tee analyze.txt`, never after it.**
   - Historical design docs that name the path stay as they are.
9. **Linux capture script**
   (`dev/tool/capture_spotlight_board_linux_goldens.sh`).
   - It resolves the checkpoint by exact subject and uses only that
     checkpoint's tests.
   - Execution reports the hash on a reachable ref.
   - Claude clones the branch into a colima-mounted `$HOME` path, verifies
     the hash, and runs the script in the calibrated
     `debrify-flutter:3.44.8` linux/amd64 image.
   - Claude copies the PNGs and evidence into
     `test/goldens/spotlight_board/linux/`. Execution verifies the hashes
     and provenance, then commits them separately.
   - The Linux test is non-strict through step 5 and strict from step 6.

**Step 0b review** (before any extraction). Each of these ORIGINAL-only
mutation negatives must be rejected:
- a 0 s cadence;
- `_stopRolling` without `onTrailerStop`;
- a trailer gated on `_rolling`;
- a lease without the dpad return;
- `decodeW` with `growth`;
- an unconditional `FocusExpressionBox`;
- `hoverable` on dpad;
- a `setState` in `_walk`;
- an unsnapped TV veil;
- a mixin call that bypasses the override.

Record `base2` (after any seam) and `base3` (after tests). Each comparison
must pass with only added, passing identities.

### Per step and gates

The playlist procedure applies, with `--baseline <format commit>` and
`--relocate lib/widgets/home/spotlight_board.dart=lib/features/spotlight_board/`.

Every step runs:
- every integrated manifest plus this one, with self-tests and an isolated
  `--parser-package`;
- the per-symbol relocation comparison (zero additions);
- architecture, sizes (lowering the facade ratchet) and storage
  references;
- shape (totalling 3) and theme;
- CI format and scoped analyze;
- LF manifests;
- staged diff checks.

Gates:
- They run on committed trees with no untracked inputs, against the latest
  `spotlight_board/` base. Gate 2 also compares against gate 1.
- An unrelated flaky failure is accepted on rerun only after original and
  current replays with the input closure hashed (the playlist gate 2
  precedent).
- Never `--record` a regression.

### Integration (Claude)

Claude merges the branch and integrates these shared files **semantically,
by union**:
- `check_search_architecture.py`
- `shape_manifest_test.dart`
- `theme_surface_manifest.txt`
- `ci_behavior_tests.txt`
- `ci_behavior_known_failures.txt`
- `checks.yml`
- `file_size_baseline.txt`
- `light_ink_inventory.py`

Merge rules:
- union and dedupe the registrations, exceptions, CI paths, known-failure
  identities, theme patterns and shape entries;
- keep every `*_COMPLETE`;
- take the lowest verified size ceiling;
- keep every `checks.yml` path before `| tee`.

Then, on the merged committed tree, Claude reruns:
- every manifest with self-tests;
- architecture, size, shape and theme;
- CI format and analyze;
- a **full-suite comparison**, reconciling identities against each branch's
  bases and approved additions.

Remote CI stays pending until a push is approved.

## Definition of done

1. **Facade.** It is formatted and within its measured cap (400, or the
   recorded value up to 450). It holds `SpotlightBoard`, the re-export, and
   the State with its mixin, verbatim lifecycle, forwarders and
   composition. All 9 production and 19 test importers compile unchanged.
2. **Guard.** It registers:
   - the feature;
   - the exact bridge;
   - the size exception;
   - the facade cap with `TEMP(spotlight_board)`;
   - the import, playback and keep-alive bans.

   Every other destination is at most 500 lines.
3. **Tests.** All manifests pass with self-tests. Every characterization
   test and source guard passes unchanged. The macOS and Linux goldens
   match the originals.
4. **Diagnostics.** No new diagnostics or suppressions. Every destination
   info maps to an original or inventoried identity.
5. **CI.** Local CI-equivalent checks pass. The behaviour list holds the 19
   importers and the new tests. The known-failure list gains only the dated
   identities observed in `base`. The shape slice totals 3, with 0 in the
   facade. The theme surface is unchanged.
6. **Progress.** It records the commits, ownership, exceptions with exits,
   the cap arithmetic and any seam. It lists as **pending device
   verification**:
   - hero trailer start and stop on Android TV, tvOS and desktop;
   - the desktop single-decoder handoff;
   - card trailers;
   - Android TV D-pad, hold-OK and the insertion anchor;
   - the unchanged entry-lag burst (no keep-alive);
   - remote CI.
7. **Gate 2** passes against the latest base and gate 1. Then stop and
   report.

## Explicitly not in scope

- `SpotlightCardTrailer`, `HeroTrailerBackdrop`, `CollectionFocusArt`, the
  host's trailer resolution, the player and the launcher.
- The home feature and all callers; `MetadataPresentationMixin`; services.
- Riverpod, data contracts, localization, a TV-capability adapter and the
  card decomposition.
- Bug fixes and behaviour changes, including everything below.

## Progress

(empty)

## Found, not fixed

All are pre-existing; the extraction keeps each exactly.

1. **Cadence comment vs code.** Lines 895–912 and 989–990 promise to
   "resolve immediately … no user-visible dwell", but 991 arms a 2 s timer.
   The historical failure in `spotlight_board_compact_test` ("asks for a
   trailer immediately", line 506) pins the comment's intent.
2. `_restartCadence` clears `_rolling` without `setState` or
   `onTrailerStop` (976). This is bookkeeping by design.
3. **`_cadence` cancelled but not nulled** in `_onHeroFocus` (1214) and
   `_down` (1463), against the null-is-armed invariant (970–973). As a
   result, `didUpdateWidget`'s reconcile (1151) can skip a restart. The same
   happens in `dispose` (1226), harmlessly.
4. **Two engine-request paths.** The hero's `onDwell` and the card's
   `SpotlightCardTrailer` are ordered only by the card's `onTrailerStart`
   (3081) and, off dpad, by the owner set. On TV only 3081 orders them.
5. **Host callbacks run during build:**
   - `onAmbient`, via `didUpdateWidget` → `_probe`;
   - a board `setState` plus `onTrailerStop`, from a card's
     `didUpdateWidget`;
   - `_stopRolling`, from a metrics notification.
6. The init post-frame callback (1099–1103) has no `mounted` check.
7. `_warmNext` has no generation check, and `_tints` and `_leftThird` are
   unbounded. The futures at 1002, 1100, 1204 and 1354 lack `unawaited`.
8. The logo always decodes at 520, regardless of `k`.
9. Strings are unlocalized, and the hero, dots and open pill have no
   `Semantics` labels.
10. Deprecated `cacheExtent` (1782) and `TickerMode.of` (3078).
11. `_shelfExtent` re-measures every heading with `TextPainter` on each
    `focusShelf` and each insertion anchor (O(rows)).
12. Timer callbacks read `context` (`ModalRoute.of` at 1021 and 3078,
    `TickerMode.of` at 3078), which registers dependencies outside build.
