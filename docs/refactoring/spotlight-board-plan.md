# Spotlight board refactor — plan

Written 2026-10-04 on `refactor/codebase` at `b5e90a55`. The file is
unchanged since `88b54092`; the only later commit edits `checks.yml`.
Revised 2026-10-04 after Codex design review round 1.
Revised 2026-10-04 after Codex design review round 2.
Follow [AGENTS.md](../../AGENTS.md).

Read first: `docs/refactoring/playlist-content-plan.md`,
`iptv-settings-plan.md` and `merged-detail-plan.md`, and the Progress
sections of the PikPak, playback-settings, IPTV-settings and
playlist-content plans. This plan reuses their technique, checker, tooling,
staging and gate procedure, and states only what differs: the manifest and
`check_verbatim_moves.py` (`check_settings_moves.py`); callback identity,
with wrapper and receiver-swap negatives; `suite_evidence.py`
tree-recording evidence; real-config fixtures; original-code worktree
proofs and mutation negatives; the wiring checklist; and Linux goldens
captured from the original code in the calibrated local Docker image.

**Execution.** The work runs in its own git worktree on
`refactor/spotlight-board`, cut from `refactor/codebase`, in parallel with
other refactors; Progress records the execution base SHA at step 0, and
every proof names it. Commit after every step; never push; gate commits
contain `gate`. Remote CI stays pending until Claude pushes, so every step
runs the local CI-equivalent commands. Evidence goes under
`refactor-evidence/spotlight_board/`. **Every manifest run passes an
isolated `--parser-package`**, including self-tests and other features'
manifests: the shared parser cache collides across worktrees (exit 253;
see PikPak Progress).

## Goal

`lib/widgets/home/spotlight_board.dart` is 3,724 lines: 36 imports, 13
declarations (11 classes and 2 enums, `SpotlightCardShape` and `_Tier`) and
no `part` files. It is the Spotlight board used by Home (hero reel plus
shelves), the search board and collection folders. It contains the hero
(art, warm-up, ambient tint, side flip, the ambient-trailer cadence and the
desktop decoder lease); D-pad movement and progressive loading; the
large-screen selection model; root, hero and shelf painting; and the
790-line card (`_Card`/`_CardState`).

Split it into a new feature, `lib/features/spotlight_board/`, **moving code
verbatim**. The following stay unchanged: the widget tree, keys, `const`
placement, `RepaintBoundary`s, focus, build order and both States'
lifecycles.

**User decisions (2026-10-04).** Spotlight is in the series. Ambient
trailers are decoration, not content playback: the hero's 2 s cadence
timer, host-supplied trailer mounting, the three `onTrailerStop` calls, the
rule that the hero yields before a desktop card video, and card-level
trailer mounting **move verbatim**, pinned as contracts with source guards;
no new seam is added, and device behaviour is pending verification. The
destination holding `_buildCard` (487 lines, about 531 formatted) gets a
**documented size exception**, because a move can't divide a method body
(exit: a later behaviour-level card decomposition).

**Why a new feature behind a facade.** Seven
`lib/features/home/presentation/` files import the board's types, and
`check_search_architecture.py:518–528` allows cross-feature imports only
into `<other>/models/`. The facade at the original path keeps all **9
production** importers (the seven home files, `collection_folder_screen.dart`
and `spotlight_catalog_card_cache.dart`) and all **19 test** importers
unchanged; four more files reach the State through
`GlobalKey<SpotlightBoardState>` without importing it. The name
`spotlight_board` avoids a clash with the six `home_spotlight_*` files.
Placing it in `lib/features/home/` is allowed but would reopen a completed
feature with a legacy bridge.

**Temporary exceptions and their exits.**

| Exception | Exit |
| --- | --- |
| State-driven sections | Notifiers keyed by route instance |
| A `legacy_spotlight_board/` bridge importing `DiagnosticLog`, `StremioService` (card description), `MetadataPreferencesService`, `ProfileRuntime` and `DebrifyImageCache` | Data contracts |
| Direct `PlatformUtil` TV reads (contract 9) | A TV-capability adapter |
| Legacy text (`'Loading more'`, `'Open'`, `'Series'`/`'Film'`, `'★ x.x'`) | Localization migration |
| `_buildCard` size | See the size exception |
| Facade-owned statics and widget properties reached through injected bindings (Technique 5) | The card decomposition or Riverpod notifiers, whichever first removes the facade dependency |

## Public surface (importable from the facade, unchanged)

**`SpotlightCard`, `SpotlightCardShape` and `SpotlightShelf` (40–245)**
stay byte-identical (docs, field order, constructors and the two pure
methods). They depend only on `lib/models/` types plus Flutter types, so
they can't go in `models/`; they can't stay, because `SpotlightBoard` with
its docs (185 formatted lines) plus the lifecycle (135) already fill 320
lines of the facade. They move to `presentation/spotlight_board_types.dart`,
and the facade re-exports them (the IPTV-settings precedent):
`export '…/spotlight_board_types.dart' show SpotlightCard, SpotlightCardShape, SpotlightShelf;`

**`SpotlightBoard` stays in the facade.** Its `createState` names the
State, so moving it would back-import the facade. It keeps its 24 fields,
constructor and docs (247–268), and its statics: `groundOf` (400),
`groundLowOf` (420–422, an Android TV gate) and `leftThirdBusy = 0.32`
(428). It stays non-final and subclassable. Moved code reaches the statics
only through injected bindings (Technique 5).

**`SpotlightBoardState`** keeps `with
MetadataPresentationMixin<SpotlightBoard>` and stays non-final. It keeps
exact forwarders for `heroWarmupProvider`, `currentHeroId`,
`heroAlignmentItemId`, `focusShelf`, `focusTarget` and the four mixin
overrides.

**Subclass contract.** `test/spotlight_hero_ambient_policy_test.dart:13–36`
subclasses both classes and overrides `metadataArtworkPending`. The State
calls mixin members at 788 (`preloadMetadata`), 1001 and 1352
(`refreshMetadataPresentation`), 1057/1058/1062/1065
(`metadataArtworkPending`, `usesMetadataProvider`, `metadataPreferences`),
1080 (`heroPresentation`) and 1327 (`metadataArtworkPending`). Moved code
**must keep calling these through the State instance**: a live tear-off or
closure with the State as receiver, evaluated at the original site, never
a cached value, `super`, or another receiver. The card State follows the
same rule for its own mixin. Enforcement: the checker's receiver rule, with
negatives for a captured bool, `super.` and a non-State receiver; the
existing test; and a new case where the override flips `_flip`'s
pending-artwork branch, observed through `heroAlignmentItemId`.

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

**State and resources.** The board State has 32 instance fields (none
`late`) and 5 static consts. `_CardState` has 20 fields, including the lazy
**`late final TvHoldOk _hold`** (3130–3133), whose first access can be
`dispose`'s `_hold.reset()`. Owned resources: `_scroll`,
`_veilMetricsRevision`, and six timer sites (781, 991, 1026, 3076, 3100,
3505); focus nodes, tickers, controllers and subscriptions are not owned.
Shelves are plain builders (`_shelfTitle` 2567, `_shelf` 2639) with no
shelf State; the only other States are `_ShelfTitleLinkState` and those the
card's children own (`ParallaxFocus` and so on).

## Contracts that must not change

Each contract is pinned by source guards and, where observable, by behaviour
tests. The guards compare whole bodies, comments included, through
`test/support/spotlight_board_source.dart`. That reader covers the facade
plus the feature files, with manifest renames and registered substitutions
(Technique 3–5) reversed.

1. **Lifecycle.** These stay **verbatim in the facade's State**, with
   receiver-only qualification:
   - `initState` (1094–1104): `super` → `_heroId` →
     `addListener(_onHeroFocus)` → `_scroll.addListener(_onBoardScrolled)` →
     the **unguarded** post-frame `_probe(); _restartCadence();
     _preloadHeroes();`;
   - `didUpdateWidget(SpotlightBoard old)` (1107–1205), all 11 steps with
     the Android TV insertion anchor (1110–1122) and the `identical` gates
     (1123–1127, 1165); `didChangeDependencies` (1359–1364);
   - `dispose`: `_cancelWarmups` → `_veilMetricsRevision.dispose()` →
     `removeListener(_onHeroFocus)` → `if (_rolling)
     widget.onTrailerStop?.call()` → `_cadence?.cancel()` →
     `_scroll.dispose()` → `super.dispose()`;
   - the card State's four lifecycle methods. Its `didUpdateWidget`
     (3168–3199) sends the `false` report through the **old** widget's
     callback; its `dispose` (3202–3213) has seven steps.

   **Callback identity:** `_onHeroFocus` (1097, 1134, 1135, 1224),
   `_onBoardScrolled` (1098) and `_onArtDone` (991, 1026) keep their
   receiver and member; the per-build card tear-offs (2707–2731) and
   `onTrailerStart: widget.onTrailerStop` (2727) keep their targets; **the
   card's `this` arguments** (`onInteraction?.call(this, …)` at 3152 and,
   inside `_buildCard`, 3690) pass the owning card State, reached in the
layout through the registered `cardState` binding (Technique 4). A
   section that owns a tear-off target is created once per State, through a
   nullable cached field (never `late`, never per build).
2. **Hero cadence: one clock, one owner.** `_restartCadence` (967–992)
   keeps its gate order and `Timer(const Duration(seconds: 2), _onArtDone)`
   (991); the comment contradicts it (Found, not fixed, 1). `_onArtDone`
   (1006–1044) keeps its 1 s hidden-route retry. `_stopRolling` (933–937)
   **always** calls `onTrailerStop` once rolling. `_scrolledAway` (865) and
   `_onHeroFocus` are unchanged; the reel never auto-advances.

   Tests use fake time with recording hosts: no `onDwell` before 2 s, then
   exactly one; none with trailers off, on dpad without hero focus, or with
   a desktop owner; the hidden-route retry; and each `onTrailerStop` path
   counted — 936 (through `_jumpTo`, `_down`, focus loss and scroll-away),
   959, and 1225 (only when rolling at unmount).
3. **Host trailer mounting (no Opacity over the hole).** `if
   (widget.trailer != null) Positioned.fill(child: widget.trailer!)` stays
   at 2041 (compact) and 2268 (wide), with its comments, and is never gated
   on `_rolling`. `_heroBackdropContent` keeps its child order: image,
   trailer, identity scrim, ground fade, veil. **No `Opacity`,
   `ShaderMask`, `ColorFiltered`, `BackdropFilter` or saveLayer ancestor is
   added or removed.** The existing `_heroBackdrop` wrapping (2165–2190) is
   preserved exactly: with animations off, neither; on dpad, an `Opacity`
   snapped to exactly 1.0 or 0.0 (2185) and no `ShaderMask` (2173); on wide
   touch, the `ShaderMask` (`dstIn`, 0/0.7/1 stops) inside the
   scroll-driven `Opacity`.

   Tests: an ancestor-chain assertion from a sentinel trailer, in dpad and
   touch modes, with animations on and off, comparing the **full ordered
   list of compositing ancestor types** with the ORIGINAL's per mode (so
   the touch `ShaderMask`/`Opacity` and the TV 0/1 snap are pinned, not
   forbidden); TV asserts the opacity is exactly 1.0 at row −1 and 0.0
   below; the trailer stays mounted while not rolling.
4. **The hero yields before a desktop card video.**
   `_onDesktopPreviewActivityChanged` (943–964) returns on dpad and acts
   only on empty ↔ non-empty transitions. On non-empty it cancels and nulls
   the cadence, sets `setState(_rolling = false)` if rolling, and **always**
   calls `onTrailerStop`; on empty it calls `_restartCadence`. The card's
   `_reportDesktopPreviewActivity` (3156–3165) and `_previewActive`
   (3143–3147) are unchanged, as is the owner gate in `_restartCadence`
   (980). Tests: hovering from A to B never restarts the hero; the hero's
   stop precedes a card preview or trailer mount; leaving every card
   re-arms the hero.
5. **Card trailer.** `_armCardTrailer` (3067–3085) keeps the 2 s dwell, its
   guard order, and `onTrailerStart` before `_trailerAttempted` and
   `setState(_trailerRequested)`. The mount (3494–3514) keeps its condition
   (`_trailerRequested && _activeCard && !_moving && _canExpand &&
   widget.trailerEnabled`), `ValueKey(c.metadata!.id)`,
   `SpotlightCardTrailer` and the 2 s text-hide timer. Also unchanged:
   `CollectionFocusArt` (3482–3488); `previewBuilder` (3489–3493); growth
   1.38/1.18; the tween durations (3224–3232). Tests use fake time and find
   the trailer by type without reaching its resolve. Engine start is
   pending device verification.
6. **Card-size decoding (no keep-alive; eviction-thrash fix).** `decodeW`
   (3256–3259) keeps its formula and comment (no `growth` term; the 1.18
   factor, off on Android TV; DPR × 1.1; `.clamp(100, 1000)`) and serves
   both the primary (3446) and fallback (3472) images. Also unchanged:
   `_heroDecodeWidth` (742–745); the 900/1400 poster fallbacks; the 520
   logo; the warm-up cache-key match
   (`spotlight_hero_ambient_policy_test.dart:130–136`). A guard rejects
   `KeepAlive`, `AutomaticKeepAliveClientMixin` and `IndexedStack` in the
   feature and facade. Tests check decode width per shape, focus, DPR and
   TV flag.
7. **Parallax cursor rules (eef825c).** Off parallax, the card uses the
   `FocusExpressionBox` fallback (3573–3579), not unconditionally.
   `ParallaxFocus` (3395–3401) and `CollectionFocusGlow` share one `active`
   expression. The passthrough `Stack` stays mounted in both states
   (3589–3603). **Hover is gated on `!widget.dpad`, not on
   `PlatformUtil`**: `hoverable`/`MouseRegion` (2728, 3667–3673),
   `_ShelfTitleLink` (2571), the wide hero's `GestureDetector` (2137) and
   the tappable dots (2415). `ParallaxTravel.note` runs before each
   `requestFocus` (1340) and on paging (1353). New test: no `MouseRegion`
   on dpad.
8. **Responsive tiers and `wideTouchScale` (c2256ad).** The tier is `dpad ?
   wide : <600 compact : <1100 mid : wide`; `k => (dpad || compact) ? 1.0 :
   wideTouchScale(w)` (482). Also unchanged: the `k`-scaled insets and type
   (2394–2396, 2446, 2455, 2467); the hero fractions 0.64/1.0; the 88/540
   overlap; the rich-card condition (1724–1728).
9. **TV performance gating.** `PlatformUtil.isAndroidTvCached` stays
   exactly at 420, 1110, 3232, 3257, 3457–3462 and 3705, and `isTvOS` at
   3325 (420 stays in the facade's `groundLowOf`; moved code reaches it only
   through the injected binding). The dpad choices are unchanged: `lowPower`
   backgrounds (1898–1900); the snapped veil and opacity; no `ShaderMask`;
   the hero fades (747–755). Tests set `debugSetAndroidTvCached(true)` per
   site and reset it in teardown; no existing `spotlight_*` test covers
   these sites.
10. **Rebuild and repaint boundaries (perf-sensitive).**
    - The `RepaintBoundary`s at 1909 and 2362 stay. The vertical
      `ListView.builder` keeps `cacheExtent: 600`, `itemCount + 2`,
      `findChildIndexCallback` and the `KeyedSubtree` keys. The veil stays
      driven by an `AnimatedBuilder` over `_scroll`/`_veilMetricsRevision`.
      `ParallaxRichScope` and every inventoried key stay.
    - `_walk` (horizontal) has no `setState` (1600–1605). `_down` and `_up`
      **do** call the board's `setState` (1462, 1473, 1488, 1498); that is
      observed behaviour and stays.
    - **No builder becomes a widget, no wrapper is inserted, and no `const`
      changes** (88 `const ` lines; 0 `prefer_const_constructors`).

    Tests: **horizontal movement** (LEFT/RIGHT) between already-mounted
    cards, after async setup settles (post-frame probe, warm-up and
    description timers drained by bounded pumps), is observed two ways.
    - **Board State:** `debugOnRebuildDirtyWidget` counts rebuilds of the
      board's `StatefulElement` only (filtered to the `SpotlightBoard`
      element, not all descendants); the count is zero.
    - **Shelves:** a shelf `Column` is rebuilt by its parent, not marked
      dirty, so the hook can't see it. Before and after the move, the test
      records, for each already-mounted shelf, the root widget instance
      `_shelf` returns (found by its `KeyedSubtree` key) and its `Element`;
      both must be `identical` before and after. Card and `Focus` rebuilds
      under a shelf are intended and are not counted.
    - **Identities:** the `Element`s and `State`s of the `ScrollableState`s
      (vertical list and row), the card `State`s and the `ParallaxFocus`
      `State`s stay `identical`.
    - **Positive control:** the same observer, run on a scene that forces a
      shelf reconstruction (a board `setState` through a vertical step, or
      a sections update), must report a changed shelf root widget, proving
      it can detect one.

    For **vertical movement** (DOWN/UP) and a sections update, the board
    rebuild counts observed on the ORIGINAL are recorded and must match,
    and the same State identities survive. The existing widget-count tests
    stay.
11. **D-pad and focus.** `_onKey` (1614–1668) handles KeyDown and KeyRepeat
    only; re-syncs `_row` from live focus; returns `ignored` for Left at
    column 0 or on the first slide, so the sidebar receives it; and opens
    the hero on Select only at `_row < 0`. Also unchanged: `_down`/`_up`;
    progressive DOWN (`_loadingMoreShelves`; the 3 s `DateTime.now()`
    window); `_focusRow`'s nearest-attached fallback and ±300 retry;
    `_walk`'s load-more threshold; the `focusTarget()` priority;
    `focusShelf` via `_shelfExtent`, which must match the shelf layout; the
    card `Focus` handlers, `TvHoldOk` (600 ms) and `ensureVisible`. New
    tests: the Android TV insertion anchor; a held `onLoadMoreShelves`
    future, with real wall time for the 3 s window.
12. **Large-screen selection.** Unchanged, and covered by the 21 existing
    cases: the 60% cursor; 65%/24 px visibility; 4 px ties; desktop
    pointer ownership; the width freeze; short-row padding.
13. **Ambient, tint and stale results.** `_probe` keeps its generation and
    `mounted` guards; `_emitAmbient` its dedupe; `_flip` its per-id memo
    and pending-artwork rule. The card description checks its captured
    scope after each await (3096–3114) and at paint (3267). Tests: a late
    tint after a hero change is dropped (a held provider if the original
    allows it, otherwise source-guard-only); a held `fetchMetaDetails`
    (`MockClient`) answered after a profile switch or unmount publishes
    nothing.
14. **Collection identity.** Unchanged: the `identical` gates (1123–1125,
    1165, 3181, 66, 82); the in-place `_col` and `_visibleCards`; node
    identity in `contains` (1377, 1433).
15. **No playback seam.** No feature or facade file imports `media_kit`,
    `hero_trailer_backdrop`, a trailer engine, `video_player_launcher` or
    `player_launch`; a guard enforces it. The only mounts stay
    `SpotlightCardTrailer` and `CollectionFocusArt`.

## Destination layout

All destinations are under `lib/features/spotlight_board/presentation/`.
Each is at most 500 formatted lines, except the size exception. The step 0
dependency report settles exact membership from the actual imports.

**Outside the bridge:** `spotlight_board_types.dart` (re-exported);
`spotlight_board_metrics.dart` (`_Tier`, `_M` → `SpotlightBoardTier`,
`SpotlightBoardMetrics`); `spotlight_shelf_title_link.dart`; any other
service-free whole widget class.

**`legacy_spotlight_board/`** (the bridge; exact path in the guard) holds
the board owners (the 32 fields, in route-owned records);
`spotlight_board_bindings.dart` (the typed widget-property view and the
injected statics; Technique 5); sections for selection, hero art and
warm-up, cadence and lease, ambient and flip, and movement and focus; paint
files for the root (`build` body and `_board`), the compact hero, the wide
hero and backdrop, the hero foreground, identity and dots (with
`_LogoOrTitle` and `_HeroOpenPill`), and the shelves; the card
(`_Card`/`_CardState` → `SpotlightBoardCard`/`SpotlightBoardCardState`)
with its verbatim lifecycle, the `late final _hold`, its owners and its
trailer and description sections; and
**`spotlight_board_card_layout.dart`** (`_buildCard` alone, in
`SpotlightBoardCardLayout`, bound to its card State; Technique 4).

**Cross-class privates** become manifest-listed public names:
`_freezeScrollWidth` (585); `_setWideSelection` (590, 592, 672); `_f`
(610, 613, 683); `_h` (610, 682); each card private that `_buildCard`
reads.

**The facade** holds the imports, the re-export, `SpotlightBoard`, and the
State with its mixin, verbatim lifecycle, forwarders, overrides, `build`
forwarder, the bindings implementation and composition.

**Its cap is measured over every retained physical line.**
- Fixed parts (formatted original): `SpotlightBoard` with its 22-line docs
  = 185 lines (formatted 255–439); the four lifecycle methods with their
  `@override`s = 135 (initState 12, didUpdateWidget 106, dispose 10,
  didChangeDependencies 7). Subtotal 320, **before** imports, the
  re-export, the State header, owner and section fields, forwarders,
  overrides, the bindings implementation, composition, blank lines and
  comments.
- **Procedure.** At step 0 (estimate) and at each step from 3 (actual),
  Progress records `wc -l` of the formatted facade and a per-span
  breakdown by AST range — imports/re-export, widget plus docs, State
  header, lifecycle, forwarders/overrides, bindings, composition, and the
  remaining blank/comment lines — whose sum must equal the `wc -l` total.
- The target is 400 lines. If the measured total exceeds it, the cap
  becomes that measured value, **at most 460** (amended after step 0b: the
  complete composition probe measured 451 physical lines with the public
  State warm-up override preserved through its tear-off; the original
  450 maximum was the merged-detail precedent, and 451–460 stays inside the
  AGENTS.md 301–500 band for one responsibility — composition). Above 460
  is a plan failure to report, not a new exception. The cap is the
  measured value, not 460: no line may be added to use the headroom.
  `TEMP(spotlight_board)` rejection enforces the cap from step 7.
- No accessor is planned: the public seams, host callbacks and bindings
  suffice. If step 0 proves one necessary, it is frozen and counted, and
  its seam-only raise is recorded.

**Guard rules** (step 1, `check_search_architecture.py`): `spotlight_board`
in `FEATURES`; `SPOTLIGHT_BOARD_FACADE`/`_BRIDGE`/`_COMPLETE = False`; the
bridge in `LEGACY_PLAYBACK_BRIDGES` (still no `http`, `shared_preferences`
or `sqflite`); no facade back-import (`own == "spotlight_board" and target
== SPOTLIGHT_BOARD_FACADE`); bans in both directions between
`spotlight_board` and `home` (except `models/`); the playback-import and
keep-alive bans; 500-line caps and `SPOTLIGHT_BOARD_SIZE_EXCEPTIONS`.

**Facade registration** (step 7, with `SPOTLIGHT_BOARD_COMPLETE = True`).
`main()` (563–590) scans only `FEATURES` directories plus explicitly added
external paths, so the facade is checked only once registered. Add `if
SPOTLIGHT_BOARD_COMPLETE: paths.add(ROOT / SPOTLIGHT_BOARD_FACADE)` beside
the other `*_COMPLETE` facades; add the facade to `COMPOSITION_ROOTS` (103)
with a comment that it is the feature's composition root (it imports
concrete bridge files to wire them, so it is exempt from layer import
checks but keeps its size cap and `TEMP` rejection); and add its cap and
`TEMP(spotlight_board)` rejection as for `PLAYLIST_CONTENT_FACADE`
(414–419).

Tests run **the real checker** (`main()` against a temporary copy of the
tree, the playlist precedent) and must reject: the facade file missing
(`Registered extracted source is missing` / `Composition root is
missing`); the facade at cap + 1 lines; `TEMP(spotlight_board)` in the
facade; and `TEMP(spotlight_board)` outside the bridge. The unmodified
tree passes.

## Size exception

`SPOTLIGHT_BOARD_SIZE_EXCEPTIONS = {"lib/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_card_layout.dart": <measured>}`

The value is measured in the file's creation commit: about 531 lines plus
imports, the owner class header and its bound fields, under the 800
ceiling. Its comment states the reason (a move can't split the method) and
the exit: a **later behaviour-level card decomposition** into art, caption
and expanded-description widgets, which alters the element tree and so
needs its own goldens and review. No other exception is authorized. The
file holds `_buildCard` alone, and the checker rejects growth. The card
class (about 867 formatted lines) is split regardless: State plus sections
in one file, layout in another.

## Technique

As in the playlist and merged-detail plans, plus:

1. **Two step 0 originals.**
   - **(a) Format-only commit** (`style(spotlight): format the original
     spotlight board`) is the **verbatim-comparison ORIGINAL** and the
     default approved application reference R (below): the manifest's
     `--baseline`, the relocation comparison, and the application-file
     hash reference.
     The formatter changes 850 lines, making the file 3,896 (+172). The
     commit formats this file only and proves token equality with the
     original except whitespace and AST-identified optional formatter
     commas, listed by node (negatives: an edited comment or literal, or a
     non-optional comma, must fail), plus idempotence. **It also raises
     `file_size_baseline.txt:19` by hand** from 3,724 to the measured value;
     that is lowered from step 1. Formatting adds **6
     `curly_braces_in_flow_control_structures` infos** (wrapped `if`s at
     original 66, 687, 700, 717, 1065 and 1112), recorded by identity (rule,
     enclosing member, message) in `spotlight_board/base-fmt` (the
     merged-detail precedent), not fixed. If a destination's nesting wraps a
     different `if`, the per-symbol comparison reports it, and it is handled
     only as a registered formatter-brace site: braces around the unchanged
     statement, raw prefix pinned (the playlist precedent).
   - **(b) Characterization checkpoint** (`test(spotlight-board): step 0
     original-code characterization checkpoint`): a later step 0 commit
     whose **application files are unchanged from R** and which adds the
     frozen characterization tests, harness, source reader, fixtures,
     checker config and macOS goldens. It is the ORIGINAL for behaviour:
     the detached-worktree proofs, original replays, step 0b mutation
     negatives and the Linux capture all run **(b)'s own tests** against
     **(b)'s application code**. Progress records both hashes and proves
     `git rev-parse <b>:lib` equals `<R>:lib` (and likewise `pubspec.yaml`
     and `pubspec.lock`).
   - **One approved application reference (R).** By default R is (a).
     If step 0 proves a seam is needed (fixed artwork or another
     original-code hook), execution commits it as an explicitly named
     **seam checkpoint** (`test(spotlight-board): step 0 seam checkpoint`)
     between (a) and (b); R is then that commit, Progress records its
     `git diff <a> <R> -- lib pubspec.yaml pubspec.lock` and Claude
     reviews it. Whichever R is chosen, it is used **everywhere**: the
     manifest's `--baseline`, the relocation comparison, the hash rule
     (`<b>:lib` = `<R>:lib`, plus `pubspec.yaml` and `pubspec.lock`), the
     Linux capture script and every original replay. Progress names R once
     at step 0; no step mixes (a) and a seam commit.
2. **Strict-lint baseline.** Analyze (a) under
   `lib/features/analysis_options.yaml`, in a detached worktree inside the
   ignored `.dart_tool/`, qualifying relative imports only. Expected: 15
   `directives_ordering`; 10 curly (4 original, 6 format-induced); 2
   `deprecated_member_use`; 1 `avoid_renaming_method_parameters`; 0
   `prefer_const_constructors`. A throwaway **rename-only probe** applies
   exactly the manifest's public renames (card and State, title link and
   State, logo, open pill, metrics, tier and card members) and inventories
   by identity the resulting `use_key_in_widget_constructors` and any
   `library_private_types_in_public_api` infos. The comparison combines
   baseline and probe by maximum observed count, never by sum. Add no `Key?
   key` parameters and make no constructor or `const` change. New files
   write imports sorted; the removed `directives_ordering` infos are
   documented. There are 0 warnings, so no allowlist entry is expected.
3. **Live getters.** Sections reach `context`, `mounted` and `setState`
   through registered live getters (`live_widget_getters`), `widget`
   through the typed property view (Technique 5), and mixin members through
   the State; nothing is hoisted. Build-time writes stay in their builders:
   `_lastMetrics`, `_heroBandH`, `_selectionViewport`, `_scrollRowId`,
   `_largeCardInteractions`, `_paintedGrowth` and the `_flip` memo. **The
   verbatim checker compares comments: never reword one.** **One owner per
   timer**; the cancel-without-null sites (1214, 1463, 1226) are preserved.
4. **The card layout owner is bound to its card State.** `_buildCard`'s
   focus handler calls `widget.onInteraction?.call(this, v)` (3690), whose
   parameter is typed `_CardState`; moved into another class, `this` would
   be the layout owner and break the contract.
   - **The binding is `cardState`, never `card`.** `_buildCard` already
     declares a local widget `final card = widget.captionBelow ? … : …`
     (3608, used as `child: card` at 3665); a field named `card` would be
     shadowed there, so `onInteraction?.call(card, v)` would pass that
     widget and `card.<member>` would resolve against it. The local `card`
     widget stays exactly as it is.
   - `SpotlightBoardCardState` creates one `SpotlightBoardCardLayout` per
     State (nullable cached field, Contract 1), passing **itself** as the
     final field `cardState`, plus its live getters and its `setState`
     tear-off. At the original site the only change is `this` →
     `cardState`; every other card member except `setState` is reached as
     `cardState.<member>` (receiver-only qualification, manifest renames
     for privates); `cardState.hold` keeps `_hold`'s lazy first access.
   - **`setState` is never State-qualified.** `State.setState` is
     `@protected`, so `cardState.setState` would raise
     `invalid_use_of_protected_member`. The card State passes its own
     `setState` tear-off through the registered callback binding
     (`live_widget_getters`, as Technique 3), and the four sites (3502,
     3507, 3511, 3687) call the bound `setState` unchanged. Negatives: a
     `cardState.setState` qualification; a tear-off of another State's
     `setState` (the board's); a wrapper closure.
   - The checker gains a **registered bound-`this` substitution** for this
     one method (`this` → `cardState`, the field bound to the owning
     `SpotlightBoardCardState`), and the source reader reverses **exactly
     that registered binding**: only `cardState` tokens that resolve to the
     layout's field, never any other identifier and never the local `card`.
     Negatives: `this` left unreplaced; a different State receiver (the
     board State, `widget`, a new or captured State, `_deps.state`); a
     wrapper closure in place of `cardState`; the substitution applied
     outside `_buildCard`; and a **receiver-shadowing negative**: a moved
     site whose receiver resolves to the local `card` widget (for example
     `onInteraction?.call(card, v)` or a field named `card`) must be
     rejected.
   - **The lexical `BuildContext` stays.** `_buildCard(BuildContext
     context, double growth)` keeps its parameter, and the
     `TweenAnimationBuilder` builder still passes its own `context`
     (`builder: (context, growth, _) => …build(context, growth)`). Body
     uses (`AppThemeScope.of` at 3239, `findRenderObject` at 3697,
     `Scrollable.ensureVisible` at 3698) stay the parameter, never the
     State's `context` getter.
   - **The context guard learns bound-State receivers.** The
     shadowed-context rule (`check_settings_moves.py:442–444`,
     `builder_context_signature`) counts only `_deps.context`/`deps.context`
     over a `context` parameter, and `normalize` would map
     `cardState.context` onto a plain lexical `context`, hiding a swap. A
     config-scoped key (`bound_state_receivers`, here `cardState` for
     `_buildCard` only) makes the guard recognise `<receiver>.context` **before**
     normalization and count it as `state-context-over-parameter` (the
     prohibited substitution), while `<receiver>.mounted` counts as the
     original State-mounted guard (`_buildCard` legitimately reads State
     `mounted` at 3500 and 3506, recorded as `state-mounted: 2`). A positive
     fixture preserves both mounted checks. Negatives replace the lexical
     `context` with `cardState.context` in `AppThemeScope.of(context)`,
     `context.findRenderObject()` and `Scrollable.ensureVisible(context, …)`;
     each must fail. Manifests without the key behave as today.
   - **The element tree is unchanged.** The owner is a plain class, not a
     widget; no `Builder` or wrapper is introduced. Goldens and the
     identity tests (Contract 10) pin it, and a behaviour test asserts the
     `onInteraction` argument is `identical` to the card's own State
     (`tester.state`) for both focus and hover.
5. **Facade-owned dependencies.** Moved code reads `widget.<property>`
   (typed `SpotlightBoard`), `SpotlightBoard.groundOf` (1759, 1989, 2215),
   `SpotlightBoard.groundLowOf` (1883) and `SpotlightBoard.leftThirdBusy`
   (1332). Importing the facade is forbidden, so:
   - `spotlight_board_bindings.dart` declares an abstract
     `SpotlightBoardWidgetView` with one **typed getter per
     `SpotlightBoard` property** that moved code reads (listed by the
     dependency report; types come from the bridge, `models/` or Flutter),
     plus `Color Function(AppTheme) groundOf`, `Color Function(AppTheme)
     groundLowOf` and `double leftThirdBusy`.
   - The facade State implements it, so its class header gains exactly
     `implements SpotlightBoardWidgetView`. The checker compares retained
     widget headers exactly (`check_settings_moves.py:1026`, `Widget class
     header changed`), so the manifest registers **that one header
     addition** for `SpotlightBoardState` only: `extends
     State<SpotlightBoard> with MetadataPresentationMixin<SpotlightBoard>`
     (555) stays token-identical and only the trailing `implements` clause
     is allowed. Negatives: a changed superclass, a dropped or added mixin,
     another or an extra interface, the addition on any other class, and
     `final`/`base`/`sealed` modifiers must each fail.
   - Each getter **reads `widget.<p>`
     live** on every call; the statics are bound as the
     `SpotlightBoard.groundOf`/`SpotlightBoard.groundLowOf` tear-offs and
     `SpotlightBoard.leftThirdBusy`, so `groundLowOf` still evaluates
     `PlatformUtil.isAndroidTvCached` on each call at the original site.
     At the original sites the only change is the receiver (`widget.<p>` →
     `view.<p>`, `SpotlightBoard.<static>` → `view.<static>`).
   - Negatives: a cached `Color`, `bool` or property snapshot; `groundOf`
     and `groundLowOf` swapped; an inlined `0.32`; a wrapper closure; a
     property getter that reads a stored copy of `widget`; any facade
     import.
   - **Compiling composition before extraction.** Step 0b proves, on a
     throwaway branch of (b), that the facade State can implement the view
     (with the registered header addition) and pass it to one stub
     section, and that a stub `SpotlightBoardCardLayout` bound through
     `cardState` and the injected `setState` tear-off compiles, under the
     strict config with no new diagnostics (in particular no
     `invalid_use_of_protected_member`). The probe also runs **the real
     manifest checker** through its CLI wrapper
     (`python3 dev/tool/check_verbatim_moves.py --manifest
     dev/tool/spotlight_board_manifest.tsv` with the Spotlight config, baseline
     R, source, feature, an isolated `--parser-package` and `--self-test`;
     `check_settings_moves.py` has no CLI entry point) over the probe tree, which must accept
     the header addition and reject each header negative. The evidence is
     kept and the branch discarded. Step 3 reruns the real checker on the
     real header. The view lands at step 3 with its first production
     consumer (no unused scaffold).
   - **Shared checker extensions.** The bound-`this` and bound-State
     context guard (4), and the view/static receiver substitutions and
     registered header addition (5), extend `check_settings_moves.py`
     (`receiver_paths`, `live_widget_getters`, `bound_state_receivers`, a
     per-class header-addition key) and the shared source-reader
     helper as opt-in config keys; every integrated manifest's self-tests
     must pass unchanged, and Claude reviews the diff at integration.

## Steps

| # | Work | Contracts |
| --- | --- | --- |
| 0 | Baseline; format commit (a) and `base-fmt`; lint probes; deps report, manifest, config; characterization tests, macOS goldens and checkpoint (b); CI list; inventory; Linux script; step 0b review | Nothing moves |
| 1 | Guard registration; public types (re-exported); metrics; shape and theme registration begin | Surface |
| 2 | **Prerequisite: the supplied Linux originals are hash-verified, committed separately and the Linux golden test made strict before this step.** Title link, logo, open pill; card and card State (owners, trailer and description sections, bound layout owner with its exception) | 1 (`this`), 5–7, 15 |
| 3 | Board owners (32 fields); widget view and injected statics; lifecycle verbatim | 1, 14 |
| 4 | Hero art and warm-up, cadence and lease, `_onHeroFocus`, ambient, tint, flip, metadata hook bodies. **Full-suite gate 1.** | 2, 4, 6, 13 |
| 5 | Selection, scroll, movement, progressive DOWN, `focusShelf`/`focusTarget` bodies | 11, 12 |
| 6 | `build` forwarder, `_board`, hero paint, shelves (Linux originals already committed and strict since before step 2). | 3, 7–10 |
| 7 | Composition, facade registration, cap and `TEMP`, guards, CI. **Full-suite gate 2.** | All |

### Step 0

1. **Baselines.** `spotlight_board/base`, on the untouched branch head:
   `suite_evidence.py run` plus the whole-repo analyzer, with tree and SDK
   provenance (Flutter 3.44.8 / Dart 3.12.2, `--no-pub`). After (a),
   `spotlight_board/base-fmt`, which must equal `base` by rule, symbol and
   message, except for the 6 recorded infos.
2. **Dependency report** (`docs/refactoring/spotlight-board-deps.md`). For
   every leaf (fields, getters, methods, the 13 declarations, comment
   fragments) it records the destination; reads of `widget` (by property),
   `context` (State or lexical), `mounted`, `setState`, mixin members,
   `this` and `SpotlightBoard` statics; tear-offs; the timer owner; and a
   wiring-checklist entry, reviewed before any scaffold is pinned.
3. **Checker.** `dev/tool/spotlight_board_manifest.tsv` (LF only; check the
   staged diff) and `spotlight_board_checker_config.json`, with real-config
   fixtures. Negatives: `_onHeroFocus` receiver-swapped or wrapped; a
   reordered or dropped dispose step in either State; a dropped
   `onTrailerStop` at each of the three sites; a rebound `onTrailerStart`;
   a trailer gated on `_rolling`; an inserted `Opacity`; a changed 2 s
   duration; a mixin call through a captured value or `super`; an eager
   `_hold`; a section built per build; a reworded comment; a new `const`;
   plus the bound-`this`, receiver-shadowing, `setState` and bound-State
   context negatives (Technique 4) and the view/static and header-addition
   negatives (Technique 5).
4. **Harness** (`test/support/spotlight_board_fixture.dart`): mocked
   `SharedPreferences`; root `ProfileRuntime` init and reset;
   `AppThemeScope` with a named look (Spotlight parallax and one other);
   pinned `tester.view` size and DPR; host-owned focus nodes; recording
   `onDwell`, `onTrailerStop`, `onAmbient`, `onLoadMoreRow`,
   `onLoadMoreShelves` and `onExitTop`; `debugSetAndroidTvCached`/
   `debugSetTvOS` reset in teardown; `MockClient`; `ParallaxTravel.clock`.
   **No `pumpAndSettle`**: it fires the 2 s cadence, the 2 s dwell and the
   300 ms description timer. Schedule a frame after post-frame callbacks.
   Fake time runs outside `runAsync`, with IO inside it; the 3 s window
   uses real wall time. Use braces in tests and January UTC dates. Prove
   one fixture on (a) first.
5. **Characterization tests**, under
   `test/features/spotlight_board/presentation/legacy_spotlight_board/`,
   written against (a)'s application code and **frozen in checkpoint
   (b)**; each passes in a detached worktree of (b) before any extraction.
   Coverage follows the contracts. Real engine start, tvOS's single
   `VideoOutput` and MediaKit queuing are **source-guarded and pending
   device verification**.
6. **Goldens.** None exist today. Capture deterministic scenes from (b):
   execution captures macOS (committed in (b)), Claude captures Linux.
   **Scenes:** wide desktop at 1440×900; TV dpad at 1920×1080, focus on
   row 0 column 1, card expanded; compact phone at 390×844; mid tier at 900
   wide; collection `shelvesOnly` with `paintBackground: false`; one
   non-parallax look. **All scenes:** trailers off (`trailersEnabled:
   false`; `onDwell` and `trailer` null); `animationsEnabled: false`; DPR
   1.0, pinned theme, `en-US`, text scale 1.0; a named initial focus or
   none; bounded pumps.
   - **Fixed artwork.** Step 0 tries to prove a seam-free path that serves
     bundled PNG fixtures to `DebrifyImageCache.manager` on the original
     (for example `HttpOverrides`). Otherwise, the scenes use deterministic
     placeholders (null `image`, `coverEmoji`, the ground hero), and
     Progress records that choice.
7. **CI list and pre-existing failures.** Add all 19 importers, the new
   tests and the golden test to `ci_behavior_tests.txt`; none is listed
   today.
   The HEAD run gave 265 passes and 5 errors, all on the historical list
   (`search-screen-initial-failures.txt:7, 8, 31, 32, 41`) and none in
   `ci_behavior_known_failures.txt`: the compact cadence test (Found, not
   fixed, 1); two `search_title_suggestions` "unresolved suggestion submits
   Catalog title search" cases; two `collection_native_browser` "Spotlight
   Home folder opens all rows directly" cases. Add **only the failures
   `base` actually observes**, by identity, in the same commit as the list
   change, under a dated comment: `# 2026-10-04 spotlight_board step 0:
   pre-existing, newly exposed by CI coverage; observed in
   spotlight_board/base`. They are not fixed. `theme/shape_manifest_test`
   passes now, despite an old list, and must keep passing.
8. **Source-text inventory.**
   - **Shape:** 3 bare radii and 0 token calls: `circular(999)` at 1930
     (`_board`), `circular(2)` at 2502 (`_dots`) and `circular(21)` at 2911
     (`_HeroOpenPill`). From step 1, register **the facade and every
     destination**, including zero-count files, in
     `kExtractedShapeResidue`, never in `kShapeResidue`. Ratchet so the
     slice totals 3 at each checkpoint and the facade ends at 0. The 488
     token floor is unaffected.
   - **Theme:** `theme_surface_manifest.txt:8` (`home_widgets`) gains
     explicit per-directory patterns: `…/spotlight_board/presentation/*.dart`
     and `…/legacy_spotlight_board/*.dart` (`ls $@` without `globstar`
     treats `**` as one level). Measure before and after.
     `light_ink_inventory.py:72` adds both directories.
   - **Guards are unconditional**: they read the feature folder whether or
     not it exists, and a missing file fails. **Verify unaffected:**
     `profile_source_guard_test`, `stale_runtime_guard_test`,
     `theme/source_guard_test` and `storage_member_map.tsv`.
   - **`checks.yml` (step 7):** add the facade to the format (44) and
     analyze (52) lists, and `test/support/spotlight_board_*` to the format
     list. **Insert paths before `| tee analyze.txt`, never after it.**
     Historical design docs that name the path stay as they are.
9. **Linux capture script**
   (`dev/tool/capture_spotlight_board_linux_goldens.sh`). It resolves
   checkpoint (b) by its **exact subject**, uses only (b)'s tests, and
   fails unless (b)'s application files hash-equal R's (`git rev-parse
   <b>:lib` = `<R>:lib`, plus `pubspec.yaml` and `pubspec.lock`), resolving
   R by its exact subject too ((a)'s, or the seam checkpoint's when
   Progress names one). Execution reports both hashes on a
   reachable ref. Claude clones the branch into a colima-mounted `$HOME`
   path, checks out (b), verifies `HEAD` and the hashes, runs the script in
   the calibrated `debrify-flutter:3.44.8` linux/amd64 image (the playlist
   handoff), and copies the PNGs and evidence into
   `test/goldens/spotlight_board/linux/`; execution verifies hashes and
   provenance, then commits them separately. The Linux test is non-strict
   through step 5 and strict from step 6.

**Step 0b review** (before any extraction). On (b), each of these
ORIGINAL-only mutation negatives must be rejected: a 0 s cadence;
`_stopRolling` without `onTrailerStop`; a trailer gated on `_rolling`; a
lease without the dpad return; `decodeW` with `growth`; an unconditional
`FocusExpressionBox`; `hoverable` on dpad; a `setState` in `_walk`; an
unsnapped TV veil; a touch backdrop without its `ShaderMask`; a mixin call
that bypasses the override; `onInteraction` given a different State. It
also records the compiling-composition probe with its real-checker run
(Technique 5). Record `base2` (at R, only when R is a seam checkpoint) and
`base3` (after tests, at (b)); each comparison must pass with only added,
passing identities.

### Per step and gates

The playlist procedure applies, with `--baseline <R>` (Technique 1) and
`--relocate lib/widgets/home/spotlight_board.dart=lib/features/spotlight_board/`.
Original-side behaviour replays use (b). Every step runs: every integrated manifest plus this one, with self-tests
and an isolated `--parser-package`; the per-symbol relocation comparison
(zero additions); architecture, sizes (lowering the facade ratchet, and
recording the facade breakdown from step 3) and storage references; shape
(totalling 3) and theme; CI format and scoped analyze; LF manifests; staged
diff checks.

Gates run on committed trees with no untracked inputs, against the latest
`spotlight_board/` base; gate 2 also compares against gate 1. An unrelated
flaky failure is accepted on rerun only after original and current replays
with the input closure hashed (the playlist gate 2 precedent). Never
`--record` a regression.

### Integration (Claude)

Claude merges the branch and integrates these shared files **semantically,
by union**: `check_search_architecture.py`, `check_settings_moves.py` and
the shared source-reader helper, `shape_manifest_test.dart`,
`theme_surface_manifest.txt`, `ci_behavior_tests.txt`,
`ci_behavior_known_failures.txt`, `checks.yml`, `file_size_baseline.txt`
and `light_ink_inventory.py`.

Merge rules: union and dedupe the registrations, exceptions, CI paths,
known-failure identities, theme patterns, shape entries, the `main()`
facade path and the `COMPOSITION_ROOTS` entry; keep every `*_COMPLETE`;
take the lowest verified size ceiling; keep every `checks.yml` path before
`| tee`; **review the checker extensions** (bound-`this`, bound-State
context guard, view/static receivers, header addition) as a shared-tool change: opt-in only, with every other
manifest's self-tests unchanged.

Then, on the merged committed tree, Claude reruns every manifest with
self-tests; architecture, size, shape and theme; CI format and analyze;
and a **full-suite comparison**, reconciling identities against each
branch's bases and approved additions. Remote CI stays pending until a
push is approved.

## Definition of done

1. **Facade.** Formatted and within its measured cap (400, or the recorded
   measured value — 451 or lower — within the amended 460 design maximum,
   counting every physical line), with the breakdown
   recorded. It holds `SpotlightBoard`, the re-export, and the State with
   its mixin, verbatim lifecycle, forwarders, bindings and composition. All
   9 production and 19 test importers compile unchanged.
2. **Guard.** It registers the feature; the exact bridge; the size
   exception; the facade in `main()` and `COMPOSITION_ROOTS`, its cap and
   `TEMP(spotlight_board)`, each proven through the real checker; and the
   import, playback and keep-alive bans. Every other destination is at most
   500 lines.
3. **Tests.** All manifests pass with self-tests. Every characterization
   test and source guard from (b) passes unchanged. The macOS and Linux
   goldens match the originals.
4. **Diagnostics.** No new diagnostics or suppressions; every destination
   info maps to an original or inventoried identity.
5. **CI.** Local CI-equivalent checks pass. The behaviour list holds the 19
   importers and the new tests; the known-failure list gains only the dated
   identities observed in `base`. The shape slice totals 3, with 0 in the
   facade; the theme surface is unchanged.
6. **Progress.** It records the commits ((a), R if different, (b) and each step),
   ownership, exceptions with exits, the cap arithmetic and any seam, and
   lists as **pending device verification**: hero trailer start and stop on
   Android TV, tvOS and desktop; the desktop single-decoder handoff; card
   trailers; Android TV D-pad, hold-OK and the insertion anchor; the
   unchanged entry-lag burst (no keep-alive); remote CI.
7. **Gate 2** passes against the latest base and gate 1. Then stop and
   report.

## Explicitly not in scope

`SpotlightCardTrailer`, `HeroTrailerBackdrop`, `CollectionFocusArt`, the
host's trailer resolution, the player and the launcher; the home feature
and all callers; `MetadataPresentationMixin`; services; Riverpod, data
contracts, localization, a TV-capability adapter and the card
decomposition; bug fixes and behaviour changes, including everything below.

## Progress

### Step 0 — original baseline and characterization preparation

- Execution is confined to this dedicated `refactor/spotlight-board` worktree,
  starting at `c5978c5fbc491ed7ef0f4ab84ceb025cd62c94e9`. No push or branch
  switch; no other existing checkout/worktree is opened. `flutter pub get`
  completed first, with no dependency or lockfile change. Flutter 3.44.8 /
  Dart 3.12.2 matches the plan. Parser/kernel caches are isolated under this
  worktree's ignored `.dart_tool/spotlight_board/`; every manifest invocation
  passes `--parser-package`. Evidence writes use only `spotlight_board/`.
- Approved application reference **R is the format-only commit `a65ad81a`**,
  subject `style(spotlight): format the original spotlight board`. No seam
  checkpoint is needed. Formatted facade: **3,896 physical lines**; the size
  ratchet was raised by hand from 3,724. Its original responsibilities remain
  temporarily until steps 1–7, with the planned extraction milestones above.
  `format-token-proof.json` proves identical tokens/comments except whitespace
  and AST-owned optional formatter commas, inventoried by declaration. Edited
  comment, literal and non-optional comma negatives reject; formatting is
  idempotent. The commit contains only the facade and its size ratchet.
- Untouched `base` and committed-format `base-fmt` each record **10,984
  successes / 13 failures / 28 errors / 20 skips**. Identity comparison PASS:
  no new failures, missing/newly skipped tests or changed outcomes. Whole
  analyzer differs by exactly the six format-induced curly-brace infos in the
  plan; all other diagnostic identities/counts are unchanged. SDK, HEAD,
  tested/end trees and input paths are in their env files. These observed
  outcomes remain authoritative over historical allowlists.
- Strict original probe qualifies import URIs only and uses the unchanged
  destination lint configuration. It observes 15 import-order, ten curly and
  two deprecation infos; the root additionally observes the inherited
  `avoid_renaming_method_parameters` info. The rename-only probe adds exactly
  four constructor-key infos, no private-type API infos, no warnings/errors
  and no const recommendation. `spotlight_board_analyzer_inventory.json`
  combines original/probe counts by **maximum**, never sum, and retains the
  root parameter-name identity. No constructor, key, const or suppression
  changes are made. Sorted destination imports will remove the 15 ordering
  infos. Initial unsuccessful rename probes are retained as evidence.
- Conservative rename decision: `_previewActive` becomes `cardPreviewActive`,
  because `_buildCard` already has a local `previewActive`. The local remains
  unchanged. The final rename probe compiles without errors. The separate
  local widget `card` remains unchanged; the layout binding is `cardState`.
- The dependency report and LF manifest inventory **157 original leaves**,
  their dependencies/destinations and per-entry production wiring checklist.
  Scaffolds are not pinned before their wiring review. The checker extensions
  are opt-in: bound-this, bound-State lexical-context guard, view/static
  receivers, registered header addition and split-State type rename.
  Real-config fixtures reject lifecycle/stop/timing/trailer/receiver/comment/
  const mutations; callback identity negatives also run independently of
  verbatim/scaffold checks. The bound layout positive retains both mounted
  reads; all three lexical-context substitutions fail. Header negatives
  cover superclass, mixins, interfaces, modifiers and another class.
- Original fixture owns host focus nodes and recording callbacks, initializes
  and resets ProfileRuntime, SharedPreferences, platform flags and travel
  clock, pins theme/locale/size/DPR, and uses MockClient for held metadata.
  Bounded pumps explicitly schedule the frame after post-frame setup; fake
  time stays outside `runAsync`, and the progressive-DOWN window uses real
  wall time. No `pumpAndSettle` or production trailer seam was added.
- Characterizations cover cadence/gates/retry and each stop path; full ordered
  trailer ancestors and TV snap; preview stop before mount; card dwell,
  growth/text-hide timing; exact decode widths by shape/focus/DPR/TV;
  original live subclass overrides; ignored dpad preview leases; row-snapped TV
  ground veil independent of scroll glide; horizontal zero board rebuilds plus shelf,
  card, scrollable and parallax-body identities; vertical and sections-update
  positive counts; Android TV insertion anchor; held progressive DOWN; and
  held description responses after profile change/unmount. Interaction owner
  identity is observed through the selected card's own mounted State and
  visual, for focus and hover, while the full body guard pins its argument.
- Characterization preparation exposed two fixture details: ParallaxFocus has
  its own MouseRegion (exit/hover); the card's outer enter/exit region is the
  dpad-gated surface tested here. `_ParallaxBody` owns the spring State;
  ParallaxFocus itself is StatelessWidget. The three-second window belongs to
  a pending independent shelf arrival after a false load result, not the
  directly appended-true continuation. Tests exercise these original scopes.
- Artwork decision: the original HttpOverrides/bundled-PNG cache probe fails
  on the host's missing path-provider implementation; its failure log is
  retained. No cache/HTTP seam is added. All six golden scenes use deterministic
  null-artwork placeholders and the ground hero. MacOS originals are captured
  and strict rerun PASS. Linux capture resolves the exact characterization
  checkpoint subject and R subject and requires equal lib/pubspec/lock blobs;
  it captures only the checkpoint's own tests in an isolated archive inside
  the clone. Supplied Linux PNGs will be verified and committed separately.
- CI coverage adds the 19 unchanged facade importers and all new tests.
  Exactly the five newly covered failure identities observed in `base` are
  added under the prescribed dated comment; no other failure is accepted.
  Shape inventory remains three bare radii (999, 2, 21); all destination and
  facade registrations begin at step 1. Theme inventory is unchanged.
  Shape/theme/stale guards pass; the profile source guard's failure is already
  observed in `base`. The initial stale-guard path typo is retained; the
  corrected actual suite passes all five cases.
- Facade estimate is measured in ignored formatted probes: 419 fixed lines
  before forwarders/owners/composition, 473 with conventional separated
  forwarding getters, 447 with adjacent related forwarding getters. This is
  an estimate, not final cap evidence. The real step-3 measured breakdown must
  fit the plan's hard 450 maximum; the composition probe must settle it.
- Checkpoint freeze, original-copy replay, original mutation proofs,
  compiling-composition probe and final base3 evidence follow before any move.
  Device trailer start/stop, decoder handoff, native card trailers, D-pad
  hold/repeat and entry-lag burst remain pending, as do remote CI and merged
  integration. Found-not-fixed items above remain unchanged.

### Step 0b — independent review corrections; facade cap blocks extraction

- The characterization checkpoint (b) is
  `54b4afa559b1341f6aece38c47072e0b2c8164e0`; the approved application
  reference R remains format-only
  `a65ad81aebbbcbe29730fc2de1d78b037a84539c`. No production code has moved.
  Both revisions have lib tree `9c828d5bd303068f3bb2768fdce45c28f78fef80`,
  pubspec blob `5f983ff8c68a01aef5c7a1ec393e677e7693591f`, and lock blob
  `e0ff9cca69c00ae69bb4dfe111c18a89547cec98`. The review corrections change
  tests and tooling only; the same application hashes remain required.
- **Reviewed reader correction (P1).** The Dart reader now calls the Python
  checker's AST token normalization with an explicitly isolated parser
  package. It validates physical lexical/State context before normalization,
  compares original comment tokens independently, then returns the verified
  original body. It never reverses names in raw prose, literals or locals.
  Correct simulated shelf, DOWN, warm-up, hero-open and card-layout moves
  pass; executable/receiver and ordinary-comment mutations fail. Card bindings
  cover widget, mounted and all inherited members actually read by layout,
  including metadataArtworkPending. The warm-up and open sites also retain
  the State's overridable heroWarmupProvider and originalMetadata dispatch.
  Registered formatter exception sidecars use the same validator as the
  checker; no general punctuation or context exception is introduced.
- **Behavior corrections (P2/P3).** Desktop lease ordering first requires
  exactly one stop. A-to-B hover transfer retains the original extra stop on
  acquisition and never produces a hero dwell while B owns the preview;
  leaving B re-arms the original two-second clock. Android TV behavior now
  covers groundLowOf, card tween, both image fade durations, ensureVisible
  snap and ParallaxTravel.note, each with the non-TV control where applicable.
  The held-description case has a successful publication control; its profile
  and unmount guards remain. The self-comparing State assertion is removed;
  the decode test name now describes its measured growth behavior. Existing
  meaningful assertions, golden tests and golden PNGs are unchanged.
- **Checker negatives (P2).** Whole-checker fixtures reject the board State's
  setter tear-off, setter wrapper, per-access section recreation and a
  section constructed on every build, cached widget-property snapshots and
  static wrappers. Real-config mutations also reject inserted Opacity and a
  dropped dispose step in either State, alongside the existing negatives.
- **Original proofs.** The contained ignored original copy is still on (b)
  with application files equal R. Its final reviewed characterization run
  passes all **146** cases: 49 behavior cases, 91 source/reader cases and six
  strict macOS goldens. Start/end tree and SDK provenance and hashes of the
  reviewed inputs are in `step0b-original-final.{env.json,jsonl}` and
  `step0b-original-final-inputs.json`. All **20** application mutants compile
  and fail the **entire contracts test file**, without name filtering;
  `step0b-review-full-mutation-proofs.json` records commands, original and
  mutated hashes, input hashes and individual logs. This supersedes the
  earlier filtered mutation evidence. The reader's simulated positives and
  negatives run through the entire source-contract file.
- **Complete composition probe (P2-4): BLOCKED: facade cap.** A separate
  ignored copy contains every actual planned owner, section, card and layout,
  the retained lifecycle, typed live view and the real composition factory.
  It compiles under the feature's strict configuration with **17 infos, zero
  warnings/errors and zero added rule/symbol/message identities**. Sixteen
  receiver-induced formatter wraps are individually pinned in that copy;
  all ten original curly sites remain. Related getter declarations retain
  the previously measured adjacent layout. The complete facade is **451
  physical formatted lines**, exceeding the hard 450 maximum:

  | AST span | Lines |
  | --- | ---: |
  | Imports and re-export | 13 |
  | Widget and its docs | 185 |
  | State header | 3 |
  | Lifecycle | 142 |
  | Forwarders and mixin overrides | 26 |
  | Live widget/static bindings | 54 |
  | Owners and cached composition | 11 |
  | Remaining blank/comment/closing lines | 17 |
  | **Total** | **451** |

  The nominal 450-line variant bypassed the public State warm-up override.
  Preserving that call through the owning State's tear-off adds one factory
  binding line. Exposing that method in the implemented view instead also
  requires an added override annotation. Neither permits accepting the
  incomplete variant. No alternative layout, new size exception, deleted
  comment or compressed formatting is adopted. Actual application facade
  remains the original **3,896** lines. Sources, hashes, AST line sets, strict
  inventory and the full probe scripts are retained under the own evidence
  namespace (`step0b-real-composition-*`). The full probe's real checker also
  rejects a newly formatted named-record comma in loadShelvesAndFinishDown
  and its changed context prefix; this is recorded as an unresolved tooling
  finding, not accepted or hidden by weakening the guard. The earlier original
  compiling binding/header probe and its real-checker negatives still pass.
- **Contract 13 choice.** Late ambient tint remains source-guard-only: the
  original dominant-color/cache path does not provide a deterministic held
  provider without an added production seam. Generation and mounted guards,
  ambient dedupe, per-ID flip memo and pending-artwork branch are pinned
  verbatim; held descriptions have behavioral controls. No ambient seam is
  added; device behavior remains pending.
- **Capture script and supplied Linux originals.** Exact-subject lookup now
  consumes the entire git-log stream under pipefail; SDK first-line selection
  also drains its input. Dependency setup uses --enforce-lockfile. Syntax,
  original hash resolution and a long-stream pipefail control pass. The six
  supplied Linux PNG hashes and provenance verify against (b), R and the
  calibrated local linux/amd64 capture/strict logs. The user's as-run script
  is retained in evidence. Golden tests were not changed in 0b; no recapture
  is required for these review changes. PNGs remain separately untracked;
  their dedicated commit and strict Linux enforcement are pending before
  any builder move, per the user's stronger prerequisite.
- **Xtream flaky-acceptance evidence.** The two stable default-concurrency
  b-suite attempts reproduce only the unrelated 50k ingest responsiveness
  timeout. Isolated current and original replays pass all ten cases; a
  contended original replay reproduces the same timeout. The 75-file project
  import closure, pubspec/lock and analyzer options hash-equal R/b
  (`base3-xtream-input-audit.json`). A controlled R full-suite run with four
  workers has exactly the original baseline identities and outcomes:
  10,984 success, 13 failure, 28 error, 20 skipped. No Xtream failure is added
  to any allowlist and no timeout/assertion is changed. Proper base3 will run
  after this review commit with --no-pub and four workers, with the complete
  start/end tree provenance; its result is recorded separately before stopping.
- Local review checks: whole-repo analyzer comparison against base-fmt has
  zero additions/removals; CI format and scoped analyzer pass (12 existing
  allowlisted warnings). Architecture, size, storage declarations and
  storage-reference self-tests pass. Every integrated manifest is rerun with
  self-tests and the isolated parser package; final results follow in the
  evidence checkpoint. Steps 1–7 and both full-suite gates remain pending
  because extraction is blocked by the measured facade cap. The thirteen
  original found-not-fixed behaviors below remain unchanged; device checks,
  remote CI and merged integration remain pending.

### Step 0b — frozen base3 and stop checkpoint

- Review correction commit: `97d79c07b260ec039ea1aa4dcdcd4eb9476621f0`
  (`test(spotlight-board): step 0b close characterization review and measure
  facade cap`). Format-only R and characterization checkpoint (b) remain
  reachable and unchanged. This subsequent evidence checkpoint changes only
  this Progress document; application, tests, dependencies and tooling remain
  the inputs tested at 97d79c07.
- Final command: `python3 dev/tool/suite_evidence.py run
  spotlight_board/base3 --no-pub --concurrency=4`. The committed start and end
  HEAD are 97d79c07; index/tested/end tree all equal
  `8457e625239a4d79292465a2c607dd1381391738`, with no worktree snapshot and
  `tree_changed_during_run: false`. `base3.env.json` records complete end
  provenance, SDK and unchanged SHA256s of the six untracked, Linux-only
  supplied PNGs. No application or test input changed during the run.
- **Comparison PASS** against controlled R `base-fmt-c4`: 11,130 success,
  13 failure, 28 error, 20 skipped; **146 added passing identities, zero new
  failures, zero missing tests and zero newly skipped tests**. That controlled
  R baseline also compares equal to the original default-concurrency baseline.
  Fresh isolated original and review-commit Xtream replays both pass 10/10;
  their JSONL/env/commands are `step0b-review-xtream-{original,current}.*`.
  The prior failing attempts and hashed input-closure evidence remain retained.
  No known-failure entry or assertion is changed to accept the flaky timeout.
- All **ten** integrated manifests and their self-tests PASS with the isolated
  parser package. The latest Spotlight log includes the actual per-build
  section mutation as well as per-access recreation, both setter negatives,
  both view negatives, dispose/Opacity mutations and the reader positives and
  negatives. Final results and tool hashes are in
  `step0b-review-final-manifest-results.json`. CI format, scoped analyzer
  allowlist, whole-analyzer identity comparison, architecture, sizes and
  storage checks PASS as recorded above. All six macOS goldens remain strict;
  neither golden tests nor PNGs were changed by the review correction.
- **Stop:** P2-4 is blocked at the measured 451-line complete facade; no
  application extraction, step 1–7 commit or full-suite gate commit is made.
  `base3` is the latest Spotlight baseline, not either planned gate. Both
  gates remain pending against that base. The probe's named-record formatter
  comma remains an explicit unresolved checker finding; no checker assertion
  is weakened. The dependency inventory also needs the LogoOrTitle destination
  under the documented bridge before moving it: its original DebrifyImageCache
  access means it is not service-free. The probe follows the currently frozen
  manifest for measurement; no production file uses that destination yet.
  The supplied Linux originals remain hash-verified and separately untracked;
  their dedicated commit/strict enforcement waits before any builder move.
  Device-only trailer/decoder/TV checks, remote CI and merged integration stay
  pending. No branch switch or push occurred.


### Step 0c — reviewed amendment tooling and complete composition

- Resumed from the reviewed amendments `3f812727` and `0c8e795c`. The
  complete compiling composition remains **451 physical facade lines**:
  imports/export 13; widget/docs 185; State header 3; lifecycle 142;
  forwarders/overrides 26; bindings 54; composition 11; remaining 17.
  The enforced final cap is 451, within the 460 design maximum. No layout,
  comment deletion or compression was introduced.
- `spotlight_named_record_formatter_commas` identifies only the named record
  in `SpotlightBoardState._loadShelvesAndFinishDown`: ordinal 0 of exactly
  one record, with every original field/value/separator pinned. AST evidence
  supplies its trailing-comma offset **before** formatter/context-prefix,
  declaration and reader comparisons. The general named-record comma rule
  remains unchanged. `step0c-named-record-inventory.json` records its exact
  physical destination and offset. Full-composition positives with and
  without that optional comma pass; changed values, another record/comma,
  an additional token sequence and hoisted context fail the checker/reader.
- The reader now also uses the existing owned-context ordering check before
  exposing original text. Its simulated moves deliberately use the original
  unformatted bodies; the real formatted bodies retain their pinned wraps.
  Binding/header/mutation fixtures locate actual moved owners and preserve
  all prior assertions, including valid `super` bypass negatives.
- `_LogoOrTitle` is registered inside the exact legacy bridge, with its
  `DebrifyImageCache.manager` dependency and lexical `build` context recorded
  in the dependency checklist. The complete probe uses that destination.
- Evidence under `spotlight_board/`: `step0c-real-composition-*` records the
  compiling probe, all self-tests, **17 infos / zero warnings/errors** and
  zero per-symbol additions; `step0c-probe-final-characterization.jsonl`
  records **146 PASS** (49 behavior, 91 source/reader, six strict macOS
  goldens). `step0c-original-source-frozen.*` records **91 PASS** against
  original checkpoint (b), with identical current reader/config/AST inputs
  and complete stable end-tree provenance. The 20 original-code behavioral
  mutation proofs from 0b remain applicable; no Dart case changed.
- All ten integrated manifests and their self-tests pass with explicit
  isolated parser packages (`step0c-final-manifest-*`). The strict diagnostic
  mapper is now durable as `check_spotlight_board_analyzer.py`, requiring an
  explicit parser package. LF, Python compilation and diff checks pass.
- Conservative baseline decision: no tracked `lib`, Dart test, pubspec or
  lockfile changed (`step0c-inputs.json`); retain the frozen **base3** from
  `97d79c07`, tested tree `8457e625239a4d79292465a2c607dd1381391738`.
  The six supplied Linux PNGs remain untracked and untouched for their own
  provenance/strictness commit before step 2. Device and remote CI checks
  remain pending.

### Step 1 — public types, numerical metrics and guards

- Step 0c is `b46b514e`. Extracted the three public types with the facade
  re-export and the numerical metrics/tier with their exact constructors,
  constants and expressions. Reviewed every step-1 dependency/caller entry.
  Identifier-token edits preserve all moved comments and string literals.
- Registered the feature and exact bridge unconditionally, 500-line limits,
  the single future card-layout exception, both Home/Spotlight import
  directions, facade back-import, playback and keep-alive bans. The real
  checker passes and its missing-directory/size/import/ownership negatives
  reject. Facade completion enforcement remains scheduled for step 7.
- Registered the facade and both new files in the extracted shape slice
  (3 + 0 + 0); added explicit patterns for both presentation directories and
  the light-ink registry. The theme surface remains **118 sites**. Sorted
  facade imports remove its original directive-order infos.
- Formatted facade: **3,569 lines**, lowered ratchet. All ten manifest suites
  and self-tests, architecture (1,213 files), size, storage, shape/theme,
  CI format and analyzer allowlist checks pass. Strict analysis has **13
  inventoried infos, no warnings/errors and zero per-symbol additions**.
  `step1-focused*` compares with base3: **176 PASS / one unchanged profile
  source-guard failure**, no new failures, missing identities or skips.
  New sources are staged for the frozen final focused replay, so its tree
  includes every extracted application input. No characterization assertion
  or original golden scene changes.
- The supplied Linux originals remain separate; their provenance/strictness
  commit is next, before the first builder move.

### Linux originals — separate prerequisite before step 2

- Step 1 is `9d6e90ba`. Verified all six supplied PNG hashes against
  `linux-original-sha256.txt`, and verified original checkpoint (b)
  `54b4afa559b1341f6aece38c47072e0b2c8164e0` has the same `lib`, pubspec and
  lock blobs as approved R. Supplied capture/strict/revision/run evidence is
  retained unchanged under `spotlight_board/`.
- Removed the Linux missing-file skip and opt-in flags. Linux now always
  asserts the original file exists and compares every scene. Scene setup,
  expectations, fixture, fonts, sizes and PNG bytes are unchanged; no
  recapture or update acceptance occurred.
- The calibrated `debrify-flutter:3.44.8` linux/amd64 image
  `sha256:cc4fea9c2aaefc3b4841105c51564d01059c9576afde4f9a21ffaf02982a263a`
  passes all **six strict Linux** comparisons on step-1 code before any
  builder move. `linux-originals-landing-{inputs.json,strict.txt}` records
  inputs, original provenance and results. The copy, package and build caches
  are inside this worktree or the disposable container. Six strict macOS
  comparisons also pass (`linux-originals-macos.*`). This dedicated commit
  contains only the six originals, strictness enforcement and this record.
- Latest full-suite base remains original-characterized base3; the six test
  identities and all macOS behavior are unchanged. Linux enforcement is now
  stronger. Builder moves may proceed.

### Step 2 — card and small rendering widgets

- Linux prerequisite is `487efa2e`. Moved the title link, open pill, logo,
  card and card State to their registered destinations. The logo remains
  inside the bridge with its original image-cache dependency. The card's
  bound layout owner preserves `cardState`, its own injected setter and
  physical context sites. No timing, decode, boundary, const or comment
  changes. Card State is 368 lines; `_buildCard`'s single documented
  layout-file exception is 585 lines. Facade ratchet: **2,505**.
- All ten manifests with self-tests, architecture negatives, sizes,
  storage references, shape (total 3), theme, CI format/analyze and analyzer
  allowlist pass. Strict symbol comparison: 17 inventoried infos, zero
  additions, errors or warnings. Six strict Linux goldens match the original
  bytes. Focused evidence `step2-focused.*` records 176 passing identities
  and the unchanged profile source-guard failure; comparison with original
  base3 passes. End-of-run full tree provenance is recorded before this
  Progress edit. Per-entry wiring checklist reviewed before scaffold pinning.

### Step 3 — board owners and live view

- Previous checkpoint: `aa29343a`.
- Moved all 32 board fields into the five route-owned records and
  wired 27 live widget/static getters. Lifecycle bodies retain original
  order and virtual metadata/mixin dispatch. Per-entry dependencies and
  wiring were reviewed before production scaffold pinning. For unmoved
  methods the manifest registers the actual facade declaration, retaining
  original private names; the immutable planned-destinations ledger retains
  their final destinations. This keeps context/formatter/source-reader checks
  active on the real intermediate code without relaxing comparisons.
- Conservative temporary size decision: the live bindings and pinned
  receiver-induced wraps add 25 lines at this boundary (2,505 to 2,530).
  Raised only this intermediate facade ratchet by hand; original bodies
  still retained exit in steps 4–6. No compression, deleted comments,
  accessor or alternative layout. Complete measured cap remains 451.
- Formatted facade: **2530**. Physical AST breakdown: imports export 35, widget docs 185, state header 3, lifecycle 142, forwarders overrides 0, bindings 54, composition 1, retained original bodies 2031, remaining 79 (sum 2530); detailed spans in `step3-cap.json`.
- All ten manifests with isolated-parser self-tests, architecture/size and storage checks, real architecture negatives, shape (3), theme, CI format/analyze and exact analyzer allowlist pass. Strict per-symbol comparison has zero additions, warnings or errors. Focused outcomes {'success': 176, 'failure': 1}; comparison against original base3 passes. `step3-focused.*` includes full end-of-run tree provenance before this Progress edit.

### Step 4 — hero lifecycle sections; gate 1

- Previous checkpoint: `e1d22c65`.
- Moved hero art/warm-up, cadence/lease, hero focus, ambient/tint/flip
  and metadata hooks. Plain sections are constructed once and cached in
  the State; live context/mounted getters and the exact State setter and
  virtual warm-up-provider tear-offs are injected. All trailer mount,
  timing and stop bodies remain verbatim, source-guarded and contract-pinned;
  ambient trailers remain decoration with device behavior pending.
- Per-entry wiring reviewed before pinning. Facade ratchet resumes lowering.
  Full-suite gate 1 runs next on this committed tree against original base3;
  its completed evidence is recorded with step 5.
- Formatted facade: **2168**. Physical AST breakdown: imports export 31, widget docs 185, state header 3, lifecycle 142, forwarders overrides 18, bindings 54, composition 11, retained original bodies 1667, remaining 57 (sum 2168); detailed spans in `step4-cap.json`.
- All ten manifests with isolated-parser self-tests, architecture/size and storage checks, real architecture negatives, shape (3), theme, CI format/analyze and exact analyzer allowlist pass. Strict per-symbol comparison has zero additions, warnings or errors. Focused outcomes {'success': 176, 'failure': 1}; comparison against original base3 passes. `step4-focused.*` includes full end-of-run tree provenance before this Progress edit.

### Step 4b — close the gate-1 field-capture regression

- Step 4 is `8e385c17`. The first full gate (`gate1.*`, retained) rejected
  `spotlight_large_screen_test::overlapping horizontal rows stay moving until
  both end`: 11,129 PASS / 13 failure / 29 error / 20 skipped, one new error.
  Investigation found the step-2 `_moving` → `moving` rename captured the
  existing `moving` parameter in both the comparison and assignment inside
  `setWideSelection`. This was a real extraction regression, not accepted
  as flaky or added to any allowlist.
- Conservative correction: the exposed field is `cardMoving`; the original
  parameter, field behavior, method body structure, callbacks, comments and
  timing are unchanged. Updated the manifest, immutable destination ledger,
  card references, dependency entry and exact physical context prefixes.
  Facade stays 2,168; card layout stays 585; complete cap stays 451.
- Added opt-in Spotlight State-field binding comparison before declaration
  normalization and before source-reader comparison. It uses AST lexical
  parameters/block locals, exact registered receivers and read/write roles;
  comment references are excluded. It covers all 32 board fields and card
  fields. General token/comma rules and every other feature's behavior are
  unchanged. Guard-alone positives and parameter/local-capture negatives
  prevent token normalization from hiding another capture.
- Full relevant file on ORIGINAL b/R: 21 PASS. Separate original read,
  write and local-capture mutations produce respectively 19/2, 20/1 and 20/1
  PASS/error; each is rejected by the binding guard too. Original source is
  restored and hash-verified. Corrected current full file: 21 PASS with no
  missing identities or skips. `step4b-original-full-mutation-proofs.json`
  and `step4b-causal-proof.json` retain inputs/results; full end-of-run tree
  provenance is captured before restoration and Progress edits.
- All ten manifests with self-tests, focused characterization comparison,
  architecture negatives, sizes/storage, shape/theme, CI format/analyze and
  allowlist PASS again (`step4b-*`). Strict analysis: 17 inventoried infos,
  zero additions, errors or warnings. No test assertions or goldens changed;
  original base3 remains authoritative. A fresh committed gate-1 run uses
  `gate1-final.*`, preserving the rejected first attempt.

### Amendment after step 0b (design-reviewed before resuming)

1. **Facade cap.** The hard maximum becomes 460 (see the size section); the
   enforced cap is the measured complete facade (451 from the probe, or the
   actual step-7 value if it is lower). No compression, deleted comment or
   alternative layout is introduced to reach any number.
2. **Named-record formatter comma.** The probe's new trailing comma in the
   named-record literal inside `loadShelvesAndFinishDown` (and its changed
   context prefix) is a formatter consequence of the receiver rename, the
   same class as the sixteen pinned receiver-induced wraps. It is added to
   the AST-owned optional-formatter-comma inventory by declaration and
   position, with a negative proving any other added comma or token in that
   declaration still fails. The checker's general rule is not relaxed.
   **Wiring (review P2):** an inventory row alone changes nothing —
   `verbatim_ast.dart.txt` deliberately excludes named-record literal commas
   and comparisons consume only `formatCommas`. Add a **config-scoped**
   validator (Spotlight config key only) that identifies exactly this
   optional trailing comma in the named-record literal of
   `loadShelvesAndFinishDown` and supplies its offset before the
   declaration, context-prefix and source-reader comparisons. Required
   fixtures on the full composition: positive (the real output passes);
   negatives for an unregistered named-record comma elsewhere, changed
   record values, and a hoisted context — each must fail.
3. **`_LogoOrTitle` placement.** Its original reads
   `DebrifyImageCache.manager` (original 2970), so it is not service-free.
   Its destination becomes
   `presentation/legacy_spotlight_board/spotlight_board_logo_or_title.dart`
   (inside the bridge): update `spotlight_board_manifest.tsv` (row 120),
   `spotlight-board-deps.md` (127), imports, guard/shape/theme registrations
   and the probe accordingly, record the cache dependency, and correct its
   context inventory to the lexical `build` parameter.
4. **Linux originals** become a prerequisite **before step 2** (the first
   builder move), not step 6: verify hashes, commit separately, make the
   Linux test strict, then step 2.

## Found, not fixed

All are pre-existing; the extraction keeps each exactly.

1. **Cadence comment vs code.** Lines 895–912 and 989–990 promise to
   "resolve immediately … no user-visible dwell", but 991 arms a 2 s timer.
   The historical failure in `spotlight_board_compact_test` ("asks for a
   trailer immediately", line 506) pins the comment's intent.
2. `_restartCadence` clears `_rolling` without `setState` or
   `onTrailerStop` (976), as bookkeeping by design.
3. **`_cadence` cancelled but not nulled** in `_onHeroFocus` (1214) and
   `_down` (1463), against the null-is-armed invariant (970–973). As a
   result, `didUpdateWidget`'s reconcile (1151) can skip a restart. The same
   happens in `dispose` (1226), harmlessly.
4. **Two engine-request paths.** The hero's `onDwell` and the card's
   `SpotlightCardTrailer` are ordered only by the card's `onTrailerStart`
   (3081) and, off dpad, by the owner set. On TV only 3081 orders them.
5. **Host callbacks run during build:** `onAmbient`, via
   `didUpdateWidget` → `_probe`; a board `setState` plus `onTrailerStop`,
   from a card's `didUpdateWidget`; `_stopRolling`, from a metrics
   notification.
6. The init post-frame callback (1099–1103) has no `mounted` check.
7. `_warmNext` has no generation check, and `_tints` and `_leftThird` are
   unbounded. The futures at 1002, 1100, 1204 and 1354 lack `unawaited`.
8. The logo always decodes at 520, regardless of `k`.
9. Strings are unlocalized; the hero, dots and open pill lack `Semantics`.
10. Deprecated `cacheExtent` (1782) and `TickerMode.of` (3078).
11. `_shelfExtent` re-measures every heading with `TextPainter` on each
    `focusShelf` and each insertion anchor (O(rows)).
12. Timer callbacks read `context` (`ModalRoute.of` at 1021 and 3078,
    `TickerMode.of` at 3078), which registers dependencies outside build.
13. Vertical D-pad steps (`_down`/`_up`) rebuild the whole board through
    `setState`, unlike the horizontal `_walk`.
