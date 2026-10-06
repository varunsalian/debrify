# Stremio TV tuner refactor — plan

Written 2026-10-06 on `refactor/codebase` at `0cb50df7`. The target file is
unchanged since that base. Follow [AGENTS.md](../../AGENTS.md).

Read first: [spotlight-board-plan.md](spotlight-board-plan.md) (closest
analogue: a pure-UI widget with a facade-owned widget class, a typed widget
view implemented by the State through a registered header addition, a card
State and a bound owner class, measured facade cap), then
[debrify-tv-plan.md](debrify-tv-plan.md) (owner records with mandatory
qualification, the opt-in occurrence binder, live getters and `setState`
tear-off, mandatory completed scaffolds). This plan reuses their technique,
checker (`check_verbatim_moves.py` → `check_settings_moves.py`),
callback-identity tooling, `suite_evidence.py` evidence, real-config fixtures,
original-code worktree proofs with assertion-failing mutation negatives, the
per-entry wiring checklist and the Linux-golden handoff. It states only what
differs. A facts inventory accompanies this plan and is copied into the
dependency report at step 0.

**Execution.** Own git worktree `../debrify-wt/stremio-tv-tuner` on branch
`refactor/stremio-tv-tuner`, cut from `refactor/codebase` at `0cb50df7`, in
parallel with four other refactors (two of them siblings in
`lib/screens/stremio_tv/`: the screen → feature `stremio_tv`, and the local
catalogs dialog → feature `stremio_tv_catalogs`). **This branch never edits
`stremio_tv_screen.dart`, `stremio_tv_local_catalogs_dialog.dart` or any
other file of those features.** Run `flutter pub get` first; the lockfile must
not change (Flutter 3.44.8 / Dart 3.12.2). Commit after every step; never push
or switch branches; gate commits contain `gate`. Evidence goes only under
`<git-common-dir>/refactor-evidence/stremio_tv_tuner/`. Every manifest run
passes an isolated `--parser-package` under the ignored
`.dart_tool/stremio_tv_tuner_parser/` (delete `*.dill` in copies). Original
proofs use a detached worktree under `.dart_tool/stremio_tv_tuner_original/`.
`suite_evidence.py` runs are serialized in this worktree, with `--no-pub` and
an explicit `--concurrency` recorded in the env file. Five refactors run
concurrently: load-sensitive flakes (WebDAV shard, the 180 ms PIN test) are
rerun in isolation and recorded as a NOTE, never allowlisted.

## Goal

`lib/screens/stremio_tv/widgets/stremio_tv_tuner.dart` is 2,476 lines (2,556
after `dart format`): 18 imports and 11 declarations — the public
`StremioTvTunerController` and `StremioTvTuner`, the 958-line (formatted)
`_StremioTvTunerState`, the Stage (`_Stage`/`_StageState`, 717 formatted
lines), `_StageDescription`, `_LivePip`, `_Marquee`, the dial card
(`_DialCard`/`_DialCardState`, 485) and `_DialHintChip`. It is the Stremio TV
channel surface: a full-bleed Stage over a horizontal D-pad dial on TV,
desktop and tablets, and a vertical channel pager on phones, with a live
broadcast tick, a focus-settle debounce, neighbour backdrop warm-up, reliable
focus jumps for the screen's header handoff, and two bottom sheets.

Split it into a new feature, `lib/features/stremio_tv_tuner/`, **moving code
verbatim**. Unchanged: the element tree, keys, `const` placement,
`RepaintBoundary`s, focus, build order, timers and all three States'
lifecycles.

**Why a new feature behind a facade.** The facade at the original path keeps
the only production importer (`stremio_tv_screen.dart:47`, which the sibling
refactor also keeps) compiling unchanged, with no import change in a file this
branch must not touch. The feature name `stremio_tv_tuner` keeps it out of the
existing `lib/features/stremio_tv/` (catalog picker), which the screen sibling
extends; cross-feature imports are forbidden outside `models/` either way.

**Temporary exceptions and their exits.**

| Exception | Exit |
| --- | --- |
| State-driven sections in `legacy_stremio_tv_tuner/` importing `StremioTvService` (the `service` property's type and its two calls) | A Stremio TV now-playing contract (screen data layer) |
| Facade-owned widget properties reached through the typed view (Spotlight Technique 5) | Riverpod tuner state keyed by route instance |
| Direct `defaultTargetPlatform` read in `touchDial` | A TV/input-capability adapter |
| Legacy English text (tile labels, 'Tuning in…', 'LIVE', 'UP NEXT', 'OPTIONS', 'RIGHT-CLICK', 'Read more', …) | Localization migration |
| The dial-card file size, only if measured over 500 (D2) | A behaviour-level dial-card decomposition with its own goldens |

## Public surface (unchanged)

`StremioTvTunerController` (19–45) and `StremioTvTuner` (47–152) **stay in
the facade byte-identical** (docs, field order, constructor). The controller
calls the State's private `_focusRealIndex` and binds the private State type,
and `StremioTvTuner.createState` names the private State, so neither can move
without a back-import. `_StremioTvTunerState` stays in the facade with its
verbatim lifecycle; it keeps a one-line retained forwarder
`_focusRealIndex(realIndex)` for the controller. No export is added; nothing
else in the file is public today except `_DialCardState.channelNumberLabel`
(a getter on a private class).

## What it contains (original lines at `0cb50df7`; after the format commit the manifest is authoritative)

| Lines | Area |
| --- | --- |
| 1–45 | Imports, controller |
| 47–152 | `StremioTvTuner` |
| 154–328 | State fields (8), `_touchDial`, lifecycle, `_onDialScroll`, `_snapDial`, `_syncTick`, `_rebuildIndex` |
| 330–462 | Ident/now-playing helpers, index/node lookup, `_setActive` (180 ms settle), neighbour warm-up, `_channelById`, `_surf` |
| 464–549 | Dial statics, leading pad, `_focusRealIndex`, `_scrollDialToIndex`, `_focusWhenAttached` |
| 551–839 | Quick-actions sheet, channel-list sheet (5 s sheet tick), list row, thumbnail fallback |
| 841–1055 | `build`, `_buildWide` (Stage + dial), `_buildNarrow` (pager) |
| 1057–1762 | `_Stage`, `_StageState` (lifecycle, Ken Burns, cascade, `build`, ten content builders) |
| 1764–1956 | `_StageDescription`, `_LivePip`, `_Marquee` |
| 1958–2476 | `_DialCard`, `_DialCardState`, `_DialHintChip` |

**State and resources.** Tuner State: 8 instance fields (`_tick`, `_activeId`,
`_centredId`, `_pendingId`, `_settle`, `_indexById`, `_pageController`,
`_dialScroll`), 2 static consts. Owned: two `ValueNotifier`s, the page and
scroll controllers, the 15 s tick, the 180 ms settle, the sheet-local 5 s tick
(cancelled by `whenComplete`), post-frame callbacks. Stage State: `late final`
`_ken` (22 s) and `_textFx` (260 ms, starts at 1.0), `_motionOk`. Dial card
State: `_focused`, `_hovered`, `_centred`, the `centredId` listener. Focus nodes
are host-owned (`rowFocusNodes`).

## Contracts that must not change

Pinned by source guards (whole bodies, comments included, through a
per-declaration source reader `test/support/stremio_tv_tuner_source.dart`
that reverses manifest renames and registered substitutions) and, where
observable, by behaviour tests.

1. **Lifecycle (facade, verbatim with receiver-only qualification).**
   `initState`: `super` → `controller?._bind(this)` → `_rebuildIndex` →
   `_activeId = first or null` → `_centredId = _activeId` →
   `_dialScroll.addListener(_onDialScroll)` → `_syncTick`.
   `didUpdateWidget`: controller rebind only when `!identical`; **always**
   `_rebuildIndex` (host mutates lists in place); `_syncTick`; the reset of
   active/pending/centred plus `_settle?.cancel()` when the active id is gone;
   the touch post-frame `if (mounted) _onDialScroll()`. `dispose`: unbind →
   tick cancel → settle cancel → `_activeId` dispose → `_centredId` dispose →
   page controller dispose → `removeListener(_onDialScroll)` → scroll dispose →
   `super.dispose()`. The Stage and dial-card States move whole with their
   lifecycles unchanged (Stage: `didChangeDependencies` → `_syncKen`;
   dial card: listener add/swap/remove and the setState-free re-derive).
   **Callback identity:** `_onDialScroll` at add (212) and remove (325) keeps
   one receiver path and member (`_sections.dial.onDialScroll`, sections
   cached once per State); `_onCentredChanged` (2042/2054/2055/2065) and
   `onKeyEvent: _onKey` (2110) are unchanged inside the moved card State;
   `onUp: widget.onFocusHeader` (1003) passes the host's function object
   through the view getter; `onOpenList: _openChannelList` (1048) becomes the
   sheets section's tear-off; every `onFocused`/`onSelect`/`onLongPress`/
   `onLeft`/`onRight` closure keeps its target (`_setActive`, `onPlay`,
   `_openActions`, `_surf(channel, i, ∓1)`); the controller's `_bind(this)`
   passes the facade State.
2. **Live broadcast tick.** 15 s periodic only while `autoRefresh`; `??=`
   (never two); cancel and null when turned off through `didUpdateWidget`; each
   tick checks `mounted`, skips while `ModalRoute.of(context)` is not current,
   then `setState(() {})`. Tests: fake time; no rebuild before 15 s; one per
   tick; none under a pushed route, one on the first tick after pop; toggling
   off stops ticks.
3. **Focus settle and Stage scoping.** `_setActive` dedupes on `_pendingId`,
   reports `onFocusedIndexChanged(realIndex)` **immediately**, then after
   180 ms (mounted, pending, already-active and still-present guards) writes
   `_activeId`, calls `setState` only when `!autoRefresh`, and warms ±1
   neighbour backdrops. **Only the Stage's `ValueListenableBuilder` rebuilds
   on a settle** when `autoRefresh` is on; dial cards are not rebuilt (no
   tuner `setState`), and the dial card `State`s and `Element`s stay
   `identical`. Tests count `_DialCard` State builds and the tuner element's
   rebuilds across a surf settle with `autoRefresh` on (zero) and off (one),
   with a positive control.
4. **Neighbour warm-up decode match.** `precacheImage(ResizeImage.resizeIfNeeded(width, null, CachedNetworkImageProvider(bg)), context, onError: …)`
   for idx ± 1 only; width = hidden ? (TV 96 : 480) : (TV
   `HomeTheme.heroBackdropCacheWidthTv` : `HomeTheme.heroBackdropCacheWidth`),
   equal to the Stage's `memCacheWidth` for the same mode. Test: a recording
   `ImageCache`/provider spy observes the requested keys per mode and that each
   matches the Stage's decode width.
5. **Index and lookup.** First-wins on duplicate ids; `_realIndex` validates
   the cached index against the live list and rebuilds once on a miss;
   `_nodeFor` bounds; `_channelById` falls back to `channels.first`.
6. **D-pad surfing.** `_DialCard._onKey`: Left/Right on KeyDown and
   KeyRepeat; Up, Down/contextMenu (→ quick actions) and activate (→ play) on
   KeyDown only; everything else ignored. `_surf` validates `buildIndex`,
   drops a press whose channel vanished, hands Left at index 0 to
   `onFocusSidebar`, ignores Right at the end, else focuses the neighbour's
   host node. Focus change: `setState(_focused)`, `onFocused`, then
   `Scrollable.ensureVisible(context, alignment: 0.5, duration: zero)` with the
   card's lexical build `context`.
7. **Reliable focus jumps (controller).** `focusRealIndex` returns false with
   no State, out-of-range indices or a channel not in the dial; with no dial
   clients (narrow) it requests focus directly and returns true; a mounted
   card is focused immediately; an off-screen card is scrolled into view by
   `jumpTo(leadingPad + i·154 + 77 − viewport/2)` clamped, then focused on a
   later frame (≤ 3 retries), bailing if the node left `rowFocusNodes`.
   Tests use 200 channels so the target is recycled off-screen.
8. **Dial geometry and pointer input.** Item extent 154 (138 + 16), leading
   pad 32 (TV/desktop) or centring pad `(viewport − 154)/2` (touch); vertical
   wheel only (dx ignored) → `jumpTo` clamped; drag devices touch, mouse,
   trackpad, stylus; touch: centre id follows scroll immediately, Stage via
   the settle, snap on `ScrollEndNotification` at depth 0 (220 ms
   easeOutCubic), no snap loop.
9. **Layout selection.** Wide when `isTelevision || maxWidth >= 900`;
   narrow = vertical `PageView` whose `onPageChanged` ensures current and next
   loaded, then `_setActive`. Touch wide: the Stage is wrapped in a
   `GestureDetector` (tap → play, long-press → actions); TV and desktop return
   the bare Stage.
10. **Platform modes (input axis, not form factor).** `touchDial =
    !isTelevision && defaultTargetPlatform ∈ {iOS, android}`. **flutter_test
    defaults to android**, so every non-TV test pins
    `debugDefaultTargetPlatformOverride` explicitly (macOS for desktop,
    android for touch) and resets it in teardown. Dial card: `touchSelect` tap
    plays without requesting focus; hover ignored when `touchSelect`;
    `MouseRegion` `onEnter`/`onExit` mounted guards; hint chips OPTIONS (TV,
    focused) / RIGHT-CLICK (non-TV, hovered), never on touch.
11. **TV performance gating.** Stage: Ken Burns never on TV, only with art and
    motion, stopped in blur mode; TV backdrop `memCacheWidth` 96 (hidden) or
    `heroBackdropCacheWidthTv`, zero fades; TV darken is a 12 % black overlay
    `Stack`, non-TV a `ColorFiltered(darken)`; blur (`ImageFiltered` σ 32) only
    non-TV hidden; `RepaintBoundary(ClipRect(AnimatedBuilder))` only when not
    blurred. Dial card: no blurred `boxShadow` on TV; posters 280 / TV-hidden
    16 / non-TV hidden `ImageFiltered` σ 18 at 200; `RepaintBoundary` around
    `MouseRegion`; `AnimatedScale` 140 ms easeOutCubic 1.10. Tests inspect the
    widget properties per mode (no network: `CachedNetworkImage` is found by
    type and its fields compared).
12. **Sheets.** Quick actions: `HapticFeedback.mediumImpact` (recorded via the
    platform channel mock), theme captured from the tuner's context, tiles and
    their conditions (Details/Guide hidden when `hideNowPlaying`; Edit/Copy
    only for local channels with a callback), each tile pops its sheet before
    calling the host. Channel list (narrow): 0.78/0.45/0.96 sheet, 5 s sheet
    tick created once and **cancelled on close** (`whenComplete`; test:
    no pending timers after close), row tap pops, `jumpToPage`, `_setActive`.
    Description sheet: theme from the calling context.
13. **Stage motion.** `_textFx` starts settled (1.0); forwards from 0 on an
    item or channel change only when motion is allowed; reduced motion holds
    the backdrop and snaps the text (`_textFx.value = 1.0`); cascade intervals
    unchanged.
14. **No new responsibilities.** No feature or facade file imports `media_kit`,
    a player, `player_launch`, `video_player_launcher`, `http`,
    `shared_preferences`, `sqflite` or any storage/profile service; playback
    is only the host's `onPlay`/`onOpenDetail`. No `KeepAlive`, no new
    `Builder` or wrapper widget, no `const` change (88 `const ` lines).

## Destination layout

All under `lib/features/stremio_tv_tuner/presentation/`. Each file is at most
500 formatted lines (D2 aside). The step 0 dependency report settles exact
membership from the actual references.

**Outside the bridge (service-free whole classes):**

- `stremio_tv_tuner_stage.dart` — the banner, `_Stage` →
  `StremioTvTunerStage`, `_StageState` → `StremioTvTunerStageState` with its
  fields, lifecycle, `_syncKen`, `build` and `_cascade` → **`cascade`** (public:
  called from the content owner). `build` reaches the content builders through
  one cached owner (`StremioTvTunerStageContent? _contentCache` with a getter
  `_content => _contentCache ??= StremioTvTunerStageContent(this)`; nullable
  cached, never `late`, never per build): `_buildContent` →
  `_content.buildContent`, `_glassPill` → `_content.glassPill`. ≈ 360 lines.
- `stremio_tv_tuner_stage_content.dart` — `StremioTvTunerStageContent`, a plain
  class (not a widget; no element-tree change) **bound to its Stage State** via
  `final StremioTvTunerStageState stageState;` (the Spotlight `cardState`
  shape). It holds `_buildContent` (public `buildContent`), `_glassPill`
  (`glassPill`) and the private `_channelTag`, `_metaRow`, `_metaStyle`,
  `_dot`, `_liveBar`, `_upNext`, `_tuningState`, `_hiddenState`, unchanged
  names, plus exactly two **live forwarding getters**
  `BuildContext get context => stageState.context;` and
  `StremioTvTunerStage get widget => stageState.widget;` (Technique 6). The
  moved bodies are therefore token-identical except `_cascade(` →
  `stageState.cascade(` (a registered receiver path) and private class names →
  manifest names. No `setState`, `mounted` or `this` occurs in these bodies
  (step 0 verifies). ≈ 400 lines.
- `stremio_tv_tuner_parts.dart` — `_StageDescription` →
  `StremioTvTunerStageDescription`, `_LivePip` → `StremioTvTunerLivePip`,
  `_Marquee` → `StremioTvTunerMarquee` (with its banner), `_DialHintChip` →
  `StremioTvTunerDialHintChip`. ≈ 250 lines.
- `stremio_tv_tuner_dial_card.dart` — the dial banner, `_DialCard` →
  `StremioTvTunerDialCard`, `_DialCardState` → `StremioTvTunerDialCardState`,
  whole and unchanged except the hint-chip name. Measured ≈ 500 (D2).

**`legacy_stremio_tv_tuner/`** (the bridge; it imports
`lib/services/stremio_tv_service.dart` directly, the compat re-export under
`lib/screens/` being off-limits to features):

- `stremio_tv_tuner_owners.dart` — `StremioTvTunerOwners`, the 8 fields with
  their docs, renamed by dropping the underscore (`tick`, `activeId`,
  `centredId`, `pendingId`, `settle`, `indexById`, `pageController`,
  `dialScroll`), initializers verbatim, created **eagerly** as a facade field
  initializer (same construction timing as today).
- `stremio_tv_tuner_widget_view.dart` — abstract `StremioTvTunerWidgetView`
  with one typed getter per `StremioTvTuner` property that moved code reads
  (21: every field except `controller`, which only the lifecycle reads).
- `stremio_tv_tuner_dependencies.dart` — `StremioTvTunerDependencies`: `view`,
  `owners`, `context()`, `mounted()`, `setState` (the State's own tear-off),
  `sections()`; and `stremio_tv_tuner_sections.dart` —
  `StremioTvTunerSections`, which builds every section in its constructor in a
  fixed order; section constructors only store `_deps`.
- Sections (each `final StremioTvTunerDependencies _deps;` plus **only the
  one-line getters it uses** among `StremioTvTunerWidgetView get widget =>
  _deps.view;`, `_owners` and `_sections` — an unused getter would be a new
  `unused_element` warning; the dependency report lists each section's set
  and the source contract pins exactly that set; Technique 5 explains the
  `widget` name):
  - `stremio_tv_tuner_channels.dart` — `StremioTvTunerChannels`: `_syncTick`,
    `_rebuildIndex`, `_identFor`, `_nowPlaying`, `_nextPlaying`,
    `_displayProgress`, `_realIndex`, `_nodeFor`, `_setActive`,
    `_precacheNeighborBackdrops`, `_channelById`, `_surf` (≈ 200).
  - `stremio_tv_tuner_dial.dart` — `StremioTvTunerDial`: `_touchDial`
    (`touchDial`), `_onDialScroll`, `_snapDial`, the two statics (kept
    `static const` on this class; names public only if read elsewhere),
    `_dialLeadingPadFor`, `_focusRealIndex`, `_scrollDialToIndex`,
    `_focusWhenAttached` (≈ 190).
  - `stremio_tv_tuner_sheets.dart` — `StremioTvTunerSheets`: `_openActions`,
    `_openChannelList`, `_channelListRow`, `_listThumbFallback` (≈ 350).
  - `stremio_tv_tuner_layout.dart` — `StremioTvTunerLayout`: `_buildWide`,
    `_buildNarrow` with their banners (≈ 230).

Members called only inside their own section class keep their private names
(no rename); cross-class members get manifest-listed public names.

**The facade** holds the imports, the controller and widget byte-identical,
and `_StremioTvTunerState` with the header addition
`implements StremioTvTunerWidgetView`, the eager owners field, the cached
sections, the verbatim lifecycle and `build`, the controller forwarder and the
21 view getters (`@override T get p => widget.p;`, read live on every call).

**Cap.** Measured over every physical line: target **350**, hard maximum
**400** (estimate: imports 18, controller 28, widget 107, State header and
composition ~15, lifecycle ~62, `build` 14, forwarder 2, view ~65, blanks).
Progress records `wc -l` and an AST-range breakdown summing to it from step 3.
Above 400 is a plan failure to report, not a new exception; the cap becomes
the measured value at step 4 and `TEMP(stremio_tv_tuner)` rejection enforces
it.

**Guard registration** (`check_search_architecture.py`, step 1):
`stremio_tv_tuner` in `FEATURES`; `STREMIO_TV_TUNER_FACADE`/`_BRIDGE`/
`_COMPLETE = False` (→ `True` at step 4) and `_FACADE_CAP`; the bridge in
`LEGACY_PLAYBACK_BRIDGES` (still no `http`, `shared_preferences`, `sqflite`);
500-line caps with `STREMIO_TV_TUNER_SIZE_EXCEPTIONS` (empty unless D2); no
facade back-import; no service import outside the bridge; the playback/
keep-alive bans; bans in both directions between `stremio_tv_tuner` and
`stremio_tv`/`stremio_tv_catalogs` except `models/`; at completion the facade
in `main()` and `COMPOSITION_ROOTS` (composition root comment), cap and `TEMP`
rejection. Real-checker tests (temporary tree copy) must reject: a missing
facade, the facade at cap + 1, `TEMP(stremio_tv_tuner)` in the facade or
outside the bridge, a service import outside the bridge, a facade import from
the feature, and (if D2 applies) the dial card at exception + 1; the unmodified
tree passes. These live in `dev/tool/stremio_tv_tuner_architecture_test.py`
and are run at every step (not only in CI).

## Technique

As in the Spotlight and Debrify TV plans, plus:

1. **Format commit (a), then checkpoint (b).** The file is not
   formatter-clean, so (a) `style(stremio-tv-tuner): format the original
   tuner` formats **this file only**, proves token equality with the original
   except whitespace and AST-identified optional formatter commas (listed by
   node; negatives: an edited comment or literal, or a non-optional comma,
   must fail) plus idempotence, and raises `file_size_baseline.txt:27` by hand
   to the measured value (≈ 2,556), lowered from step 1. Any
   formatter-induced `curly_braces_in_flow_control_structures` or other info
   is recorded by identity in `stremio_tv_tuner/base-fmt` (the Spotlight
   precedent), not fixed. (a) is R. (b) `test(stremio-tv-tuner): step 0
   original-code characterization checkpoint` leaves application files equal
   to R and adds the frozen tests, harness, source reader, fixtures, checker
   config and macOS goldens; Progress proves `git rev-parse <b>:lib` =
   `<R>:lib` (and `pubspec.yaml`, `pubspec.lock`). No seam checkpoint is
   planned; if one proves unavoidable, stop and report.
2. **Strict-lint baseline and rename probe.** Analyze R under
   `lib/features/analysis_options.yaml` in a detached worktree inside
   `.dart_tool/` (qualifying relative imports only) and record diagnostics by
   identity (rule, enclosing member, message). A throwaway rename/receiver
   probe applies the manifest's renames and receiver substitutions to a
   compiling copy and inventories by identity: `use_key_in_widget_constructors`
   for the newly public widgets without `key` (`StremioTvTunerStage`,
   `StremioTvTunerStageDescription`, `StremioTvTunerLivePip`,
   `StremioTvTunerMarquee`, `StremioTvTunerDialHintChip`), any
   `library_private_types_in_public_api`, and any change in
   `use_build_context_synchronously` from `context`/`mounted` becoming
   `_deps.context()`/`_deps.mounted()` (`_openActions` awaits a sheet).
   Baseline and probe combine by maximum per identity, never by sum. **No key
   parameter, constructor, `const` or suppression change is made.** CI analyzes
   `lib/features` from the first file, so any surviving **warning** gets an
   `analyzer_allowlist.txt` entry by destination identity in the commit that
   creates its file (step 0 expects none: the file has no unused members).
3. **Live getters and `setState`.** Sections reach the tuner State's
   `context`, `mounted` and `setState` only through `_deps.context()`,
   `_deps.mounted()` and `_deps.setState(...)` (registered
   `live_getter_callbacks`, the State's own tear-off), evaluated at the original
   site, never cached. State-context sites (facts: 264, 335, 425, 557/560,
   646/648, 704, 822, 859, **950** — `ScrollConfiguration.of(context)` sits in
   `_buildWide` outside every builder) become `_deps.context()`; **lexical
   scopes stay lexical**: the builders' `context`/`ctx` parameters (846, 877,
   970, 977, 1032, the sheet builders) and the sheet-local `setSheet`. The
   existing context guard and the Debrify TV `lexical_state_setters` key (for
   `setSheet`) apply; negatives replace a lexical `ctx`/`context` with
   `_deps.context()` and the reverse, and `setSheet` with `_deps.setState`.
4. **Owner fields and the occurrence binder (opt-in reuse, no new
   substitution kinds).** Every moved field reference is receiver-qualified
   (`_owners.activeId`); no section declares an instance field besides
   `_deps`; the owners record holds only declarations and initializers. The
   hazard this file actually has: `_buildWide`'s `ValueListenableBuilder`
   builder declares a **parameter named `activeId`** (877), the same name as
   the renamed `_activeId` field, and its body reads the parameter
   (`_channelById(activeId)`). The design deliberately uses **only the
   substitutions the existing binder already supports** (round 1 P1-1):
   registered receiver paths with their member lists (`_owners`,
   `_sections.<key>`, and `stageState` for the content owner's `cascade`) and
   the three `_deps` live getters. The two other receivers a straightforward
   design would need (`widget.<p>` → `_view.<p>`, State `context` →
   `stageState.context`) are avoided by the token-preserving getters of
   Techniques 5 and 6, so the original and destination occurrences stay
   `lexical`/`unbound` with the same names. The binder needs **three opt-in
   extensions** (round 2), each defaulting to today's behaviour so the
   Debrify TV manifest and every other manifest's adapter output and
   self-tests stay byte-identical:
   - `record_owners` (list) replaces the two hard-coded
     `_DebrifyTVScreenState` comparisons (`occurrence_field_bindings.py:52`,
     `:83`); Debrify TV sets `["_DebrifyTVScreenState"]`.
   - `record_fields` (optional explicit list per owner) restricts mandatory
     record qualification to named members. The tuner lists exactly the eight
     instance fields, so the two `static const`s `_dialItemExtent` and
     `_dialLeadingPad` (469, 472), which move to `StremioTvTunerDial` and are
     read bare there (seven reads), are not treated as record fields. Without
     the key, all variable declarations count (today's behaviour).
   - `_canonical_name` honours the manifest config's `type_renames` when the
     opt-in `occurrence_type_renames: true` is set, because `_StageState` is
     split into member rows and has no whole-class row to carry its rename
     (the scratch probe rejected `_Stage.createState` without it).
   Fixtures for each: the static reads bare in the dial section pass; a
   static moved into the owners record and read bare fails; `createState() =>
   StremioTvTunerStageState()` passes while a wrong State type fails; Debrify
   TV's config without the new keys reproduces today's results exactly.
   The binder runs for this manifest with record owner `_StremioTvTunerState`. **Real moved-body
   proofs before extraction** (step 0b, through both the checker and the
   reader, on a scratch tree built from R by the actual manifest moves of
   `_buildWide`, `_setActive`, `_syncTick`, `_channelListRow` and
   `_buildContent`): positives — those bodies as planned; the VLB parameter
   `activeId` stays a bare `decl:` reference while `_owners.activeId` is the
   field; negatives — the parameter read replaced by `_owners.activeId.value`,
   a field read replaced by a bare `activeId` inside that builder, a bare
   owner field in a section, `_deps.context()` in place of a lexical
   `context`/`ctx` and the reverse, `widget.ident` in the content owner
   replaced by a captured `ident` local, and `stageState.cascade` replaced by
   a cached tear-off.
5. **Typed widget view (Spotlight Technique 5), read through a `widget`
   getter.** The facade State's header gains exactly `implements
   StremioTvTunerWidgetView`; the manifest registers that one header addition
   for `_StremioTvTunerState` only (negatives: a changed superclass, an extra
   interface or mixin, the addition on another class,
   `final`/`base`/`sealed`). Each view getter is exactly `@override T get p =>
   widget.p;` (live on every call); function-typed properties return the
   host's function object, so `onUp: widget.onFocusHeader` still passes the
   same object (an identity test compares it with the host's closure). Each
   section exposes the view as `StremioTvTunerWidgetView get widget =>
   _deps.view;`, so **every moved `widget.<p>` site stays token-identical**
   and still resolves to a member of the enclosing class (`unbound` in both
   ASTs). A tuner-specific source contract pins each section's `widget`,
   `_owners` and `_sections` getters and each view getter to their exact
   one-line bodies. Negatives: a cached property snapshot, a stored copy of
   `widget`, a getter returning another object, a wrapper closure, any facade
   import.
6. **The Stage content owner is bound to its Stage State (Spotlight Technique
   4, without `this` or `setState`).** One `StremioTvTunerStageContent` per
   Stage State (nullable cached field). Its two live forwarding getters
   (`context => stageState.context`, `widget => stageState.widget`) keep the
   original bare State `context` sites (1400, 1464, 1489, 1558, 1591, 1603,
   1610, 1672, 1715, 1740) and every `widget.<p>` site token-identical; both
   are evaluated on every call, never cached. The only lexical `context` in the
   moved content would be `_cascade`'s `AnimatedBuilder` builder parameter, and
   `_cascade` stays in the State (renamed `cascade`, reached as
   `stageState.cascade`). The source contract pins the two getters' exact
   bodies and the single `stageState` field. Negatives: a getter returning a
   cached context/widget, a different receiver (a tuner section, a new State),
   a wrapper closure, and `stageState` used outside the content owner. A
   behaviour test asserts the content reads the Stage's own element: it wraps
   the Stage alone in a different look than its surroundings (the surface
   theme boundary) and compares rendered colours.
7. **Callback identity, split by shape.** The `torbox_callback_identity.py`
   mechanism (receiver path + member, wrapper and same-class receiver-swap
   negatives) covers the **direct tear-offs and single-call arrow closures**:
   `addListener`/`removeListener(_onDialScroll)`, `onOpenList:
   _openChannelList`, `onUp: widget.onFocusHeader`, `onKeyEvent: _onKey`,
   `_onCentredChanged` add/swap/remove, and the dial card's `onFocused`,
   `onSelect`, `onLongPress`, `onLeft`, `onRight` closures and the Stage's
   `onTap`/`onLongPress`/`onOpenDetail` closures. **Block closures** (the 15 s
   tick, the 180 ms settle, the 5 s sheet tick, the `Listener.onPointerSignal`
   wheel handler, the `NotificationListener` snap, the post-frame callbacks,
   the sheet tile `onTap`s) are covered as part of their enclosing moved
   bodies by the whole-body verbatim comparison, the occurrence binder and the
   context guard, with receiver-swap negatives inside each (for example the
   settle's `_deps.setState` replaced by a section-local call, or the wheel
   handler's `_owners.dialScroll` replaced by `_owners.pageController`).
8. **Verbatim comments.** The checker compares comments; never reword, move or
   drop one, including the section banners (`// --- Channel ident ---…`,
   `// =====…`) which travel with the first member below them, and the
   stale `_tick` doc ("every second"; Found, not fixed).
9. **Shape.** The file is in `kShapeResidue` at 0 bare radii with **20
   `app.shape.br*` tokens** (sheets 6, Stage content 7, description 2, dial
   card 4, hint chip 1), and the 488-token floor counts only `kShapeResidue`
   files. From step 1, register every destination that receives a token in
   **`kShapeResidue` at 0**, every other destination (and the facade once its
   last token leaves) in `kExtractedShapeResidue` at 0. At every checkpoint the
   slice holds 20 tokens and 0 bare radii, and the floor test passes.
10. **Theme.** `p2_stremio_tv` (`lib/screens/stremio_tv/*.dart`) does not
    cover `widgets/` today, so the measured surface is unchanged by the move;
    record the before/after `measure_theme_surface.sh` output to prove it. Do
    not widen the surface in this branch (that would change another feature's
    baseline under a sibling's feet). `theme_rendered_set.py` keeps its root
    (the import walk reaches the feature). `light_ink_inventory.py`: no change
    (verify).

## Steps

| # | Work | Contracts |
| --- | --- | --- |
| 0 | Baseline `base`; format commit (a) and `base-fmt`; lint/rename probes; dependency report; manifest, config, callback sites; harness, characterization tests, source reader, macOS goldens (two reversed-order captures); checkpoint (b); CI list; source-text inventory; Linux capture script | Nothing moves |
| 0b | Independent review (Claude); original-only mutation proofs; compiling-composition probe with the real checker and facade measurement; `base2` at (b) | Nothing moves |
| L | **Prerequisite before step 1 (before anything moves):** Linux originals hash-verified, committed separately, Linux golden test made strict | Goldens |
| 1 | Guard registration and architecture test (with its CI-registered source-contract runner); parts file (description, pip, marquee, hint chip); dial card file; shape/CI registrations begin | 6, 10, 11 |
| 2 | Stage and its bound content owner. **Full-suite gate 1** | 11, 13, Technique 6 |
| 3 | The whole tuner State in one step: owners, view (header addition), dependencies, all four sections (channels, dial, sheets, layout), composition, verbatim lifecycle and `build` with receivers, controller forwarder. Nothing is left half-moved, so no temporary forwarder exists | 1–10, 12 |
| 4 | Completion: `STREMIO_TV_TUNER_COMPLETE = True`, facade cap and `TEMP`, `COMPOSITION_ROOTS`, real-checker negatives, CI format/analyze paths, final evidence. **Full-suite gate 2** | All |

**Why step 3 moves the whole State at once (round 1 P1-2).** The State's
methods call each other across every planned section (`_buildWide` →
`_nodeFor`, `_identFor`, `_nowPlaying`, `_setActive`, `_surf`,
`_openActions`, `_snapDial`; `_channelListRow` → `_identFor`, `_nowPlaying`,
`_setActive`; lifecycle → `_rebuildIndex`, `_syncTick`, `_onDialScroll`,
`_touchDial`). Moving them over several steps would need temporary facade
forwarders and a per-step borrowing map; moving all 30 members, the 8 fields
and the 2 statics in one reviewed step avoids both. The step is still
verbatim: every leaf is a manifest row, and the frozen member map (dependency
report) assigns each to exactly one destination. The add and remove of
`_onDialScroll` are rewritten together, both to `_sections.dial.onDialScroll`.
Step 0b's compiling-composition probe builds **this exact step-3 shape**
(all destinations, real bodies, full facade) on a scratch tree, runs the real
checker and the strict analyzer over it, measures the facade, and is then
discarded.

### Step 0

1. **Baselines.** `stremio_tv_tuner/base` on the untouched worktree head:
   `suite_evidence.py run` plus the whole-repo analyzer with tree and SDK
   provenance. After (a), `stremio_tv_tuner/base-fmt` (equal to `base` by
   rule, symbol and message except recorded formatter infos).
2. **Dependency report** (`docs/refactoring/stremio-tv-tuner-deps.md`): for
   every leaf the destination; reads of `widget` (by property), `context`
   (State or lexical), `mounted`, `setState`, owner fields, statics, `this`;
   tear-offs; timer owner; and a wiring-checklist entry. It confirms the
   Technique 6 claim (no `setState`/`mounted`/`this` in the content builders)
   and the cross-class call graph that decides public names.
3. **Checker.** `dev/tool/stremio_tv_tuner_manifest.tsv` (LF only) and
   `stremio_tv_tuner_checker_config.json`, real-config fixtures and
   `stremio_tv_tuner_checker_test.py`. **Step-aware mandatory destinations
   (round 1 P2-3).** The shared checker has one global scaffold threshold and
   a destination-or-facade fallback (`check_settings_moves.py:1142`, `:1269`),
   so the tuner adds its own validator through the existing opt-in
   `source_validator_module` key (`dev/tool/stremio_tv_tuner_contracts.py`)
   plus the additive context hook below. Given the config's `completed_step`
   S, every destination file and scaffold registered for steps ≤ S must
   exist, and future files may be absent. **Scaffold activation:** the shared
   scaffold check (`check_settings_moves.py:1149`) validates declarations of
   every registered scaffold whose file exists, and the facade exists from
   step 0, so registering completed facade scaffolds early would fail the
   original (25 errors in the round-3 probe). The shared checker therefore
   gains an **opt-in** `scaffold_activation_step` filter (per scaffold; absent
   = always active, today's behaviour): scaffolds whose step > S are dropped
   before scaffold validation and ownership registration. The complete
   schedule is frozen in the scaffolding sidecar; only its active subset is
   checked at each checkpoint. The S = 0…4 fixtures run the **complete
   checker and the source reader**, not the validator alone. Rows fall into three kinds, read from the
   manifest: **retained** rows (destination = facade: the controller, the
   widget, the State's lifecycle and `build`) must be in the facade at every
   step; **moved** rows with step ≤ S must exist only at their destination;
   **registered forwarders** (exactly one: the State's `_focusRealIndex`,
   with its exact one-line body `=> _sections.dial.focusRealIndex(realIndex)`)
   must exist in the facade alongside their moved implementation from their
   step. The hook today passes only `sources`
   (`check_settings_moves.py:1058`); the shared checker gains an **additive**
   call: when the module also defines `validate_with_context(sources, config,
   rows)`, that is called with the live parsed config (including
   `completed_step`) and manifest rows; modules without it are unaffected. The
   validator caches nothing between calls. Fixtures run at S = 0…4 **within
   one process**, changing the config in memory, and prove: deleting an
   activated destination fails; restoring a moved leaf to the facade (double
   definition or fallback) fails; a missing or altered forwarder fails; a
   retained row moved out fails; an absent future file passes.
   Negatives (each must fail): `_onDialScroll` receiver
   swapped or wrapped at add or remove; a reordered or dropped dispose step in
   any of the three States; the 180 ms or 15 s duration changed; the
   `!autoRefresh` settle `setState` dropped; `ModalRoute` check dropped; a
   section built per build; the Stage content owner built per build or made
   `late`; a reworded comment; a new or removed `const`; the Technique 3–6
   negatives.
4. **Harness** (`test/support/stremio_tv_tuner_fixture.dart`): a fake
   `StremioTvService` (`implements` with `noSuchMethod`; scripted
   `getNowPlaying`/`getNextPlaying` per channel id, recording `rotationMinutes`
   and `salt`); channels built from real `StremioAddon`/`StremioAddonCatalog`
   values, including a duplicate id placed **earlier** in `allChannels` than a
   displayed copy (dial ids stay unique), a local channel and a favourite;
   now-playing slots fixed in the past (`progressText` 'Ended', `progress`
   1.0) for ordinary items, future slots only for next-playing/progress
   cases, and **`getNowPlaying` returning null** with the channel in or out of
   `loadingChannelIds` for the 'Tuning in…'/'No broadcast' states; host-owned focus nodes
   disposed in teardown; recording host callbacks; `AppThemeScope` with a
   named look; pinned `tester.view` size and DPR; explicit
   `debugDefaultTargetPlatformOverride` per test, reset in teardown; a
   `MediaQuery(disableAnimations)` variant; `HapticFeedback` recorded through
   `SystemChannels.platform` mock. **No `pumpAndSettle`** (Ken Burns repeats
   with art; the tuning spinner never settles); bounded pumps; fake time for
   the 15 s tick, 180 ms settle and 5 s sheet tick.
   **Artwork (round 1 P2-4).** Image resolution starts during build and
   `precacheImage` resolves eagerly, so "not painting" is not enough. Each
   artwork test file installs a test binding whose `createImageCache()`
   returns a **recording `ImageCache`**: `putIfAbsent` records the opaque key
   and returns a never-completing
   `ImageStreamCompleter` **without calling the loader**, so neither the cache
   manager, `path_provider`, `sqflite` nor HTTP is reached. The harness also
   fails the test on any `MethodChannel` call to `plugins.flutter.io/path_provider`
   or `com.tekartik.sqflite`, clears the recording cache and releases listeners
   in teardown. `ResizeImageKey` keeps its fields private, so assertions
   compare recorded keys **by equality** with keys obtained from the expected
   providers (`ResizeImage.resizeIfNeeded(width, null,
   CachedNetworkImageProvider(url))`, `obtainKey` with the test's
   `ImageConfiguration`, which never calls a loader), plus the
   `CachedNetworkImage` widget fields for `memCacheWidth` and fades. Goldens stay
   artwork-free (D5).
   **Observation schedules (round 1 P2-6).** Build counters are reset after
   the focus change has been processed (the card's own `setState` at 2112),
   so the settle assertion counts only settle-caused rebuilds. Retry coverage
   forces delayed attachment: the target card is kept out of the built range
   for the first post-frame callback (a scroll physics/viewport that needs
   more than one frame), so `_focusWhenAttached` must retry. The
   `didUpdateWidget` index proof uses the earlier duplicate: an in-place host
   mutation that keeps the old cached index valid for the wrong copy, so only
   a skipped `_rebuildIndex` (not `_realIndex`'s self-repair) changes the
   reported index. Sheet cleanup is proved by a named assertion (no active
   `Timer` after close, with tuner auto-refresh off so the 15 s tick does not
   mask it), not by teardown failure alone.
5. **Characterization tests** under
   `test/features/stremio_tv_tuner/presentation/legacy_stremio_tv_tuner/`,
   written against R and frozen in (b), one group per contract; each passes in
   a detached worktree of (b) before extraction. Device-only behaviour
   (Android TV remote repeat/hold, real image decode cost, tvOS focus engine)
   is listed for the end-of-series checklist.
6. **Goldens** (none exist). Deterministic scenes captured from (b): TV wide
   1920×1080 (`isTelevision`, focus on dial card 2, OPTIONS hint); desktop
   wide 1440×900 (macOS platform, no focus); touch tablet 1280×800 (android,
   not TV; centred gold ring on card 0); phone narrow 390×844 (pager with the
   Channels/Details pills); TV hidden-now-playing; phone quick-actions sheet;
   phone channel-list sheet. DPR 1.0, pinned look, `en-US`, text scale 1.0,
   fixed `displayProgress` 0.4, no artwork, bounded pumps. Two captures in
   reversed scene order must be byte-identical. Execution captures macOS in
   (b); Claude captures Linux (step L).
7. **CI list and known failures.** Add the new tests and the golden test to
   `ci_behavior_tests.txt`. **Tooling in CI (round 1 P2-8):** a Dart test
   `stremio_tv_tuner_source_contracts_test.dart` (listed in
   `ci_behavior_tests.txt`, which runs in the behaviour job that already has
   `fetch-depth: 0`) runs `python3 dev/tool/stremio_tv_tuner_checker_test.py`
   (which must have a `__main__` entry that parses `--parser-package` and
   runs every fixture, exiting non-zero on any failure; a positive control
   proves a deliberately broken fixture makes the Dart test fail)
   and, from step 1, `stremio_tv_tuner_architecture_test.py`, each with an
   isolated parser package under `.dart_tool/`, and asserts exit 0. It lands
   in (b) (checker) and step 1 (architecture), before anything moves. Add to `ci_behavior_known_failures.txt` only
   failures `base` actually observes for newly listed tests, by identity,
   under a dated comment (none expected: no existing test covers the tuner).
8. **Source-text inventory.** Shape (Technique 9), theme (Technique 10),
   `file_size_baseline.txt`, and **verify unaffected**:
   `test/theme/source_guard_test.dart` (no frozen prefix covers the feature;
   `StremioTvScreen` root rule untouched), `profile_source_guard_test`,
   `stale_runtime_guard_test`, `storage_member_map.tsv`, and the two doc
   comments in `lib/theme/app_art.dart:51` and `app_motion.dart:254` (they
   name the facade path, which survives; unchanged). `checks.yml` (step 4):
   the facade and `test/support/stremio_tv_tuner_*` into the format and
   analyze lists **before `| tee`**, never after.
9. **Linux capture script** `dev/tool/capture_stremio_tv_tuner_linux_goldens.sh`,
   resolving (b) and R by exact subject and failing unless their application
   hashes match (the Debrify TV script is the template).

### Step 0b (before any extraction)

Claude reviews step 0 independently. On (b), each ORIGINAL-only mutation must
make a **named assertion fail** (behavioural where observable, otherwise
recorded as source-guard-only with the reason): settle 180 → 0 ms; no
immediate `onFocusedIndexChanged`; tick 15 s → 1 s; `ModalRoute` check
removed; settle `setState` made unconditional (dial cards rebuild with
auto-refresh on) and removed (no rebuild with it off); warm-up width 96 → 480
on TV hidden and ±1 → ±2; `_rebuildIndex` last-wins; `didUpdateWidget`
skipping `_rebuildIndex` for identical lists (in-place mutation); Left at index
0 not calling `onFocusSidebar`; vanished-channel press not dropped;
`_focusWhenAttached` retries 3 → 0 and the `rowFocusNodes.contains` guard
removed; narrow `focusRealIndex` returning false; item extent 154 → 138; wheel
also handling dx; Left/Right on KeyDown only (repeat dropped); Down not opening
actions; Details tile shown while hidden; channel-list `whenComplete` removed
(pending timer); wide threshold 900 → 1000 and TV not forcing wide; pager not
preloading next; Ken Burns on TV; `_textFx` not forwarding on change; TV
`ColorFiltered` instead of the overlay; dial `boxShadow` on TV; hover lighting
under `touchSelect`; touch tap requesting focus; the `ValueListenableBuilder`
replaced by a tuner `setState`; the controller not rebound on a controller
change. It also runs the compiling-composition probe (the full step-3 shape
plus the step-2 Stage split with real bodies, under the strict config, through the
real checker CLI with header negatives) and records the facade measurement.
`base2` at (b) must pass with only added, passing identities.

### Per step and gates

The Spotlight procedure applies with `--baseline <R>` and
`--relocate lib/screens/stremio_tv/widgets/stremio_tv_tuner.dart=lib/features/stremio_tv_tuner/`.
Every step runs: per-entry wiring review before pinning; **all integrated
manifests plus this one** with self-tests and isolated parser packages; the
occurrence-binder, context, lexical-setter and callback-identity checks; the
per-symbol relocation comparison (zero additions beyond the probe inventory);
the architecture test; sizes (lowering the facade ratchet; breakdown from step
3); storage references; shape (20 tokens, 0 bare radii, floor ≥ 488) and
theme (unchanged); CI format and scoped analyze with the allowlist; LF
manifests; staged diff; all characterization tests; strict macOS and Linux
goldens. Gates run serially on committed trees against the latest base; gate 2
also compares against gate 1. A first gate failure is investigated as a
possible extraction regression with original/current causal proofs before any
flaky acceptance. Never `--record` or `--update` to accept a regression.

### Integration (Claude)

Claude merges the branch after the sibling refactors in whatever order they
finish, integrating these shared files **semantically, by union**:
`check_search_architecture.py` (feature, bridge, caps, `main()` facade path,
`COMPOSITION_ROOTS`, bans), `check_settings_moves.py` and the shared
source-reader helper, `occurrence_field_bindings.py` (the generalised owner
key; Debrify TV's behaviour byte-identical), the callback-identity helper,
`shape_manifest_test.dart`, `ci_behavior_tests.txt`,
`ci_behavior_known_failures.txt`, `analyzer_allowlist.txt`, `checks.yml`
(paths before `| tee`), `file_size_baseline.txt`. Then, on the merged
committed tree: every manifest with self-tests, architecture, size, shape and
theme, CI format and analyze, and a full-suite comparison.

## Definition of done

1. **Facade** formatted, within its measured cap (target 350, maximum 400),
   breakdown recorded; it holds the controller and `StremioTvTuner`
   byte-identical and the State with the header addition, eager owners,
   cached sections, verbatim lifecycle and `build`, the forwarder and the view.
   `stremio_tv_screen.dart` compiles unchanged.
2. **Guard**: feature, exact bridge, caps (and the D2 exception only if
   measured), facade in `main()` and `COMPOSITION_ROOTS`, cap and `TEMP`, the
   import/playback/keep-alive and sibling-feature bans, each proven through the
   real checker. Every other destination is at most 500 lines.
3. **Tests**: all manifests pass with self-tests; every characterization test
   and source guard from (b) passes unchanged; macOS and Linux goldens match
   the originals.
4. **Diagnostics**: no new warning or suppression; every info maps to an
   original or probe-inventoried identity; removed identities listed.
5. **CI**: local CI-equivalent checks pass; behaviour list holds the new tests;
   shape slice 20 tokens, floor met, facade 0; theme unchanged.
6. **Progress** records R, (b) and each step's commit, ownership, exceptions
   with exits, cap arithmetic, and the end-of-series device checklist.
7. **Gate 2** passes against the latest base and gate 1. Then stop and report.

## End-of-series device checklist (no device gate before merge)

- Android TV: D-pad surfing with key repeat/hold across 200+ channels; Left at
  the first card → sidebar; Up → header; Down/menu → quick actions; the
  header's down-arrow handoff landing on a recycled card (controller jump).
- Android TV: Stage swap smoothness on surf settle (no Ken Burns, snapped
  fades) and neighbour warm-up hitting the cache; hidden-now-playing mode.
- tvOS focus engine on the dial; desktop wheel/drag/hover preview and
  right-click; tablet centre-snap dial; phone pager and both sheets.
- Remote CI once Actions is available.

## Explicitly not in scope

`stremio_tv_screen.dart` and every other `lib/screens/stremio_tv/` file;
`lib/features/stremio_tv/`; `StremioTvService`, models, `HomeTheme`,
`AppThemeScope`; Riverpod, data contracts, localization, a TV-capability
adapter; behaviour fixes (below) and the dial-card decomposition.

## Found, not fixed

1. `_tick`'s doc says the tick "re-evaluates now-playing every second"; the
   timer is 15 s.
2. `_StageDescription` creates a `TextPainter` per layout and never disposes
   it.
3. `_LivePip` ignores its `color` field (constant red).
4. `_Marquee` does not scroll (a plain ellipsized `Text`).
5. Side effects in build paths: `ensureLoaded` in `_channelListRow`,
   `_buildWide` and `_buildNarrow` builders; the channel-list sheet tick is
   created inside a `StatefulBuilder` builder.

## Decisions taken before design review (Claude, 2026-10-06)

- **D1. Format commit.** The file is not formatter-clean (≈ 80 lines grow),
  so a format-only commit (a) is R, with the Spotlight token/comma proof.
- **D2. Dial-card size.** The dial card class plus State formats to ≈ 485
  lines; with imports and its banner the file lands at ≈ 500. If the measured
  file exceeds 500, it gets a documented size exception equal to the measured
  value (at most 520), exit: a behaviour-level dial-card decomposition with
  its own goldens. Splitting the widget from its State, or binding its
  306-line `build` to an owner for a handful of lines, adds coupling without
  a responsibility boundary. Above 520 it is split instead (State `build` to
  a bound layout owner, the Spotlight card precedent), decided before step 1.
- **D3. Stage split.** The 717-line Stage is split along its one real seam:
  lifecycle/backdrop `build` (State) versus the text content builders (a bound
  owner), keeping `_cascade` and both animation controllers in the State.
- **D4. No theme-surface widening.** The tuner is outside today's measured
  `p2_stremio_tv` glob; the move keeps it outside (Technique 10).
- **D5. Goldens without artwork.** Network images never load in tests;
  decode/fade/blur choices are pinned by widget-property tests instead.

## Round 1 review resolution

1. **P1 — binder support.** No new substitution kind: sections and the Stage
   content owner expose token-preserving live getters (`widget`, `context`),
   so only existing receiver-path and `_deps` scaffolding is used; the two
   hard-coded record-owner comparisons become `record_owners` config
   (Debrify TV byte-identical). Step 0b proves real moved bodies (positives
   and capture negatives) through checker and reader before extraction
   (Techniques 4–6).
2. **P1 — intermediate composition.** The tuner State moves in one step
   (step 3), so no temporary forwarder or borrowing map exists; the step-0b
   probe compiles and checks that exact shape (Steps).
3. **P2 — step-aware destinations.** A tuner validator through the existing
   `source_validator_module` key, with S = 0…4 fixtures (Step 0.3).
4. **P2 — artwork loading.** Recording `ImageCache` that never calls loaders,
   plugin-channel tripwires, teardown release (Step 0.4).
5. **P2 — loading/empty states.** Null now-playing with `loadingChannelIds`
   toggled; future slots only for next/progress (Step 0.4).
6. **P2 — observation schedules.** Counter reset after focus, forced delayed
   attachment, earlier-duplicate index proof, named timer assertion
   (Step 0.4).
7. **P2 — block closures.** Direct identity for tear-offs/arrow closures;
   block closures covered by whole-body, binder and context guards with
   in-body receiver-swap negatives (Technique 7).
8. **P2 — CI registration.** A CI-listed Dart source-contract test runs the
   checker and architecture fixtures before anything moves (Step 0.7).

## Round 2 review resolution

1. **P1 — split Stage State rename.** Opt-in `occurrence_type_renames` makes
   binder canonicalization honour `type_renames`; correct/wrong State-type
   fixtures (Technique 4).
2. **P1 — dial statics.** Opt-in `record_fields` limits mandatory record
   qualification to the eight instance fields; statics stay bare on the dial
   section (Technique 4).
3. **P1 — validator vs facade retention.** Retained, moved and registered
   forwarder rows are distinguished; an additive `validate_with_context`
   hook passes live config and rows; in-process fixtures for S = 0…4
   (Step 0.3).
4. **P2 — unused section getters.** Each section declares and pins only the
   getters it uses (Destination layout).
5. **P2 — resize keys.** Recorded keys compared by equality with keys
   obtained from expected providers (Step 0.4).
6. **P3 — checker entry point.** `__main__` with parser arguments and a
   broken-fixture positive control (Step 0.7).

## Round 3 review resolution

1. **P2 — scaffold activation.** Opt-in per-scaffold
   `scaffold_activation_step` filter before scaffold validation and ownership
   registration; full schedule frozen, active subset checked; S = 0…4
   fixtures run the complete checker and reader (Step 0.3).
2. **P3 — wording.** The validator introduction now describes the three row
   kinds and the additive hooks (Step 0.3). The probe inventory records the
   `recursive_getters` and public-State parameter-name infos observed in the
   round-3 prototype (Technique 2).

Round 3 verdict: **No P1s — executable.** Execution may start.

## Progress

### Step 0 — ORIGINAL characterization checkpoint (2026-10-06)

Format (a): `2d3ef03404b62a6a61116d9e7636c43dba7349c2` is R. Checkpoint (b) is the exact subject `test(stremio-tv-tuner): step 0 original-code characterization checkpoint`; its hash and `lib`/pubspec object equality are recorded in `refactor-evidence/stremio_tv_tuner/step0-checkpoint.json` after commit. Nothing is extracted. The only application edit is (a)'s target-file formatting, plus the measured 2,556-line baseline adjustment. Neither sibling file, service, model, theme nor player/native implementation is changed.

- `flutter pub get` ran first in this worktree; Flutter 3.44.8 / Dart 3.12.2; lockfile unchanged.
- Untouched `base` and R's `base-fmt`: full-suite `suite_evidence.py run` with paths `[]`, flags `--no-pub --concurrency=4`, serialized runs and stable tested trees. Both have 11,654 successes, 13 failures, 28 runner errors and 20 skips. Every identity/outcome is identical; `base-fmt-vs-base.txt` reports no additions, losses, regressions or new skips. No historical failure was accepted through an obsolete allowlist; no allowlist changed. No PIN/WebDAV contention flake occurred in these runs.
- Whole-repo analyzer: base and base-fmt each 1,689 identical diagnostic identities/counts. No formatter infos changed. Additional scratch-project diagnostics were diagnosed as overlapping analysis of nested probe projects; those roots were removed before the final root comparison. Final root run is exactly the same 1,689 identities/multiplicities as base-fmt; `step0-analyzer-comparison.txt` is the verdict.
- Formatter proof: unchanged declaration tokens/comments except AST-identified optional commas, identical import prefix, idempotent formatting; edited comment, literal and non-optional comma negatives fail. Per-node comma evidence is `format-token-proof.json`.
- Strict R copy under feature analysis options, qualifying only relative imports (including the existing service compatibility URI): three import-order infos, no errors/warnings. The compiling rename/receiver probe has nine infos, no errors/warnings. `stremio_tv_tuner_analyzer_inventory.json` freezes maxima per rule/original symbol/message (never sum), including five public-widget key infos, two public-State parameter infos, recursive sections getter and the qualified wheel callback's formatter-related flow-control info. No constructor, key, const, suppression or behavior fix was made. Initial import-only probe failures and final sources/imports/analyzer logs remain in evidence. The formatted dial-card probe is 499 physical lines including imports/banner, so D2 is inactive and no size exception is added. Facade composition measurement remains step 0b.
- LF manifest: 67 leaves, complete scheduled 53 scaffolds, 21 live widget-view getters and 15 callback-identity contracts and 28 checked ORIGINAL callback-expression sites (including the nine listed block closures). Complete checker and source reader run the real config at S=0…4 in one process; activated destinations, retained rows, absent future files and controller forwarder are checked. Negatives cover listener wrapping/swapping at both sites, all three States' dispose reorder/drop, durations/gates, context/setter capture, lexical activeId, cached getters/owners, class headers, comment/const changes and opt-in static/type binding. The CI-listed Dart fixture assertion passes, with independent positive controls before binder/callback negatives. The broken-fixture compile flag makes that exact named Dart assertion fail (expected exit 0, actual 1); evidence is broken-checker-dart-positive-control.txt. Final source-contract replay passes 69 tests after adding the complete checked callback sidecar and every listed block-receiver negative.
- Shared tools: opt-in record_owners/record_fields/occurrence_type_renames and validate_with_context/scaffold_activation_step only. All 16 pre-existing manifests pass their self-tests with byte-identical stdout+stderr before/after; raw normalized adapter JSON is byte-identical in both modes (32 outputs). Evidence: parity-before.json, parity-after.json and every paired log. Existing configs are untouched; no parser cache is shared. Fresh parser packages are initialized before CLI invocation. The later architecture feature block is not introduced at step 0.
- Frozen characterization: 34 behavior/artwork cases + seven strict macOS goldens + 69 source/tooling contracts = 110 successful tests on the unchanged R application. The original full 110-test run and the final affected 69-test run are recorded separately, with exact paths/flags; no focused run is represented as a full-suite gate. The frozen (b) detached replay is recorded in step0-original-characterization.jsonl after commit, before any extraction. CI lists all six new Dart files. Recording ImageCache holds keys without invoking loaders; plugin tripwires, actual ResizeImage-key equality, named sheet-timer cleanup and host focus-node ownership are tested. Counters reset after focus; controller retry forces one unattached callback; the in-place duplicate test keeps every old cache index valid so self-repair cannot mask a skipped didUpdateWidget rebuild. The removed-node test attaches the card before removing the live host node ahead of deferred focus.
- Seven artwork-free macOS ORIGINAL scenes captured twice in reversed order; all PNG hashes are identical and strict comparison passes. Dimensions, focus hints, locale, text scale, DPR, progress, look and platform are pinned. Bundled fonts/icons are loaded; inherited system faces retain the framework's deterministic test-font rendering as in the series fixtures. Device typography/image decode is not claimed. Linux originals are pending Claude's Docker capture from (b), using the committed `capture_stremio_tv_tuner_linux_goldens.sh`; it resolves exact subjects and rejects mismatched lib/pubspec objects and SDK/architecture. No moved-code golden is generated or accepted.
- Source-text inventory: original tuner has 20 app.shape.br occurrences, residue 0; global floor 488 with zero slack passes unchanged. Existing shape/theme manifests, storage member map, app_art/app_motion facade comments and sibling source objects are unchanged. Source/shape/stale/profile guard run: 30 successes, one existing profile-source failure (`direct SharedPreferences opens stay inside reviewed adapters/stores`), every observed outcome equals base-fmt. Storage keys/references self-tests, architecture, file-size ratchet, LF, formatting and diff checks pass. No assertions or checks were weakened. CI tooling uses the same active tuner config for independent binder/callback positive controls and negatives. Direct live manifest check passes all 67 leaves. All nine characterized/changed Dart files are formatter-clean; Python/shell syntax and diff checks pass.

Conservative decisions: keep original focus-forwarder documentation/signature above its exact one-line dispatch while the moved method retains the original documentation too; the shared forwarder checker pins that prefix. No new substitution kind or compatibility-URI rewrite is introduced. Tuner-only `validate_with_context` additionally rejects bare State context/mounted/setState in activated sections; lexical sheet/builder parameters and Stage content live getters remain valid. Feature guards always scan every present feature file without a completed-step guard. Default record-owner semantics remain unchanged for existing manifests; their configs are not edited. The architecture feature block and checks.yml format/analyze path additions remain their planned later steps (paths go inside the command before tee).

Found, not fixed: stale every-second tick documentation (actual 15 s), undisposed description TextPainter, LivePip's constant red ignoring its color, non-scrolling Marquee, ensureLoaded and sheet tick creation in builders. These retain whole-body/comment contracts.

STOP POINT 1: after the committed (b) is verified with its Linux capture script and step-0 evidence. Step 0b (independent review, ORIGINAL-only named-assertion mutation proofs, real-checker compiling-composition/facade measurement, base2), step L, steps 1–4 and both full-suite extraction gates have not begun. Device remote repeat/hold, real decode cost, tvOS focus, remote CI and integration remain pending. Resume only after Claude's independent review/findings.


### Step 0b review follow-through (2026-10-06)

- Claude's independent review resumed execution after checkpoint (b) `6c7a35f8d97744036552019d92c2d31c68341205`. Production library and pubspec objects still equal (b) and R; nothing has moved. The review additions preserve every existing assertion: D-pad centering of a mid-list TV card; desktop and touch Ken Burns scale above 1.05 after 22 seconds, then decreasing; direct focused-card decoration checks (TV shadow null, non-TV one bloom); a named depth-zero source assertion. The depth guard is source-guard-only: the dial cards contain no nested scrollable, while the Stage and modal sheets lie outside its notification subtree. Genuine dial notifications therefore have depth zero; fabricating a nested notification would not characterize an original production path.
- Original-only proof: the owned detached (b) checkout, with these review test additions, passed all 114 characterization identities on a stable tested tree (`step0b-original-characterization`). All 38 mutations in `dev/tool/stremio_tv_tuner_original_mutations.json` failed their expected named assertions: 37 behavioural cases and one classified depth source guard, covering 27 distinct original test identities. `original-mutations.json` records exact errors/expectations, original revision, tested trees and pixel hashes. Compile/load errors and timeouts are rejected by the runner. The immediate-index proxy delays the report until the existing settle callback, so it proves timing with a named assertion rather than failing on an empty list. Every original byte was restored and the disposable original checkout was removed. The preliminary positive run (113 tests) is retained as preliminary evidence only because tests were being completed during that run; the accepted 114-test run is stable.
- Compiling-composition probe: the full step-3 composition plus step-2 Stage split, with actual moved bodies and trimmed imports, passed the real checker CLI with all self-tests. Real CLI negatives reject an omitted interface, an extra interface, and a wrong State type. Strict analyzer: 9 infos, zero warning/error, zero additions beyond the original/probe symbol inventory. Probe facade: 297 physical lines = controller 26 + widget 106 + State 155 + imports/gaps 10; full State member ranges and all 13 source hashes are recorded in `composition-probe-verification.json`. The 499-line dial card needs no D2 exception. The disposable compiling tree was removed. Test/support analyzer reports no issues.
- Linux provenance pre-verification: all seven untracked originals match `linux-original-sha256-first.txt`; first/reverse lists are identical; checkpoint/reference library and pubspec objects match (b)/R; Flutter 3.44.8, Dart 3.12.2, linux/amd64; strict original capture passed 7. This is recorded separately in the evidence directory and will be committed with the originals at step L.
- Conservative decisions: retain original constructors, parameter names, comment bytes, motion/focus/timer behavior and all Found-not-fixed items. No assertions, failure lists or analyzer allowlists are relaxed. All parser packages and scratch/kernel caches remain below this worktree's `.dart_tool`; evidence stays under `refactor-evidence/stremio_tv_tuner/`. `base2` now runs at (b), with only review characterization/tool additions and the original production objects, before the step-0b commit.
- Baseline follow-through: the first complete `base2` attempt had 11,768 successes, the same 13 failures / 28 errors / 20 skips as `base-fmt`, and 114 added passing characterization identities. Before accepting the final baseline, the original broad descendant-shadow assertion was retained alongside the stricter direct decoration assertion (the direct assertion runs first). No original assertion is removed. The full baseline is repeated against these final test inputs; the first run is retained as `base2-preliminary`. Mutation rejections remain tied to the unchanged first assertions and original source; this addition cannot mask any recorded rejection.
- Accepted final `base2`: {'success': 11768, 'failure': 13, 'error': 28, 'skipped': 20}; all baseline identities/outcomes are unchanged and exactly 114 added identities pass (110 checkpoint tests plus 4 review additions). Full suite paths `[]`, flags `--no-pub --concurrency=4`, stable tested tree `3573c423c8250dd044e325e290cc7588e547adbe`, same Flutter/Dart SDK. `base2-vs-base-fmt` and `base2-vs-preliminary` pass; final whole analyzer has identical diagnostic identities/counts to `base-fmt`. This is the latest tuner baseline for both gates. Step 0b is complete; no extraction has begun.

### Step L — strict Linux originals

- Step 0b commit: `9d3547676e3d00e31945a17e1930b3a7ff160f00`. The seven Linux PNGs are unchanged from Claude's independent capture at (b); first/reverse hashes and checkpoint/R library/pubspec objects were verified before extraction. `test/goldens/stremio_tv_tuner/linux-original-verification.json` freezes the seven hashes, SDK/image/platform provenance and hashes of the original capture evidence. The Linux skip and capture/require booleans are removed from the current golden test: missing or mismatched Linux pixels now fail by default. The original capture script continues to resolve and clone frozen (b), so its original-only calibration contract stays unchanged.
- Strict goldens: macOS 7/7 and calibrated linux/amd64 Docker 7/7 pass without updating images. All seven Linux hashes remain unchanged after verification. No production source has moved; the library and pubspec objects still equal (b)/R. Step L is complete, and step 1 may begin. Device checks, remote CI and integration remain pending.

### Step 1 — parts and dial card

- Step L commit: `b54827d8f91418864ce46ef4261d26da70ae09f4`. Production callers now use `stremio_tv_tuner_parts.dart` (242 lines) and `stremio_tv_tuner_dial_card.dart` (499 lines). Whole widgets/State and comments move verbatim, with only registered public names and imports. Controller and public tuner widget stay byte-identical. No D2 size exception is needed. The remaining 1,828-line facade owns tuner State and Stage until steps 3 and 2 respectively; its existing size ratchet is lowered to 1,828, with those explicit exit milestones. An unused `ValueListenable` import show-name was removed after it moved exclusively with the card; no application body was changed to fix a lint.
- Additive architecture registration: unconditional feature scan, exact service bridge, 500-line extraction caps, keep-alive/playback bans, facade back-import ban, and both directions of the TV/catalog implementation boundary (models remain allowed). The catalog peer is scanned even before its sibling branch registers that feature. Real checker copy fixtures reject every listed violation before completion and completion-only facade/TEMP negatives, including a missing facade. All 16 other manifests pass their self-tests with byte-identical stdout/stderr to the frozen pre-change outputs; their AST adapter JSON modes match, and 32 raw adapter stdout strings match frozen R directly. Shared binder/checker opt-ins remain unchanged from (b).
- All 17 manifests and self-tests pass with explicit isolated parser packages. Source-reader, occurrence/field/context/lexical-setter/callback identity checks pass. Strict symbol inventory: 5 infos, no new warning/error; whole analyzer outside this slice is identical to `base-fmt`, and the 5 new-name infos were inventoried by the compiling probe. CI analyzer allowlist, format, architecture, size, storage keys/references and tuner-LF/unchanged-other-manifest/diff checks pass. All 114 characterization tests and shape tests pass against `base2`; strict macOS 7/7 and Linux 7/7 originals pass without image updates.
- Evidence correction: a mistaken `suite_evidence.py run --help` started an unintended suite; its owned process tree was stopped, all three stray evidence files removed, and the overlapped characterization was discarded and rerun serially. Only the accepted serial run is used (step1-serialization-note.json). Conservative scope decision: existing TorBox CRLF is retained byte-for-byte; tuner TSV is LF, and all other manifest bytes are unchanged. Shape updater was corrected to remove formatter-wrapped entries idempotently after the whole analyzer rejected a duplicate dial-card entry; repeated generation/formatting is byte-identical and the affected checks were rerun. Shape: all three current files are registered at residue zero; the slice remains exactly 20 tokens, with the global 488 floor and zero slack. Measured theme surface remains 3 files / 5,463 lines / 79 sites; light-ink site expressions and primary surface are unchanged. The rendered-set root is unchanged and follows the production feature imports. Found-not-fixed code, profile/source guards and all protected source objects remain unchanged. Step 1 is complete; no temporary forwarding methods were introduced.

### Step 2 — Stage and bound content; gate 1 input

- Stage widget/State, both owned animation controllers, lifecycle, cascade and build move together. The content owner is a plain class, bound to that State with live `context` and `widget` getters and one nullable lazy cache; it adds no element, retains every original callback/const/comment, and reads no service. Bodies match the compiling step-0b probe exactly. The remaining facade retains tuner State until step 3, and its size ratchet is lowered to the measured value. The next full-suite run is gate 1 on this committed tree, compared against latest `base2`; step 3 waits for that verdict.

- Previous checkpoint: `f677124847877fa0d63649ea1d4afae3626584b4`. All 17 manifests/self-tests pass with isolated packages; all other manifests' stdout/stderr and both AST modes are byte-identical to pre-change, with 32 raw adapter byte comparisons also passing. Occurrence, field, context, lexical-setter and callback guards pass. Architecture real-checker negatives, size, storage keys/references, formatter, CI analyzer allowlist, per-symbol inventory, whole-analyzer external identities, tuner LF and unchanged other manifest bytes, and staged diff pass. All 114 ORIGINAL characterization identities and shape tests pass against `base2`, including strict macOS 7/7; calibrated Linux 7/7 passes without image updates. The 20-token shape slice registers every file and the facade at zero residue, global floor 488 with zero slack. Theme and normalized light-ink expressions remain unchanged. Protected production/native/model/theme objects and original test assertions are byte-identical (evidence `step2-protected-objects.json`). No found-not-fixed code was repaired.
- Measured physical lines: `{"lib/features/stremio_tv_tuner/presentation/stremio_tv_tuner_dial_card.dart": 499, "lib/features/stremio_tv_tuner/presentation/stremio_tv_tuner_parts.dart": 242, "lib/features/stremio_tv_tuner/presentation/stremio_tv_tuner_stage.dart": 357, "lib/features/stremio_tv_tuner/presentation/stremio_tv_tuner_stage_content.dart": 389, "lib/screens/stremio_tv/widgets/stremio_tv_tuner.dart": 1107}`. No D2 or other extracted size exception. Per-entry production wiring/ownership is recorded in `step2-wiring-review.json`; symbol correspondence and removed original diagnostic identities are recorded in `step2-analyzer-identities.txt`.

### Full-suite gate 1 — accepted evidence

- Committed input `4f225c2d0a5e6cbc48e0a00782bb16cdd0496eb2`, tested tree `8814cff24980e7829a513f94f5381f3f62b16964`; SDK `{"dartSdkVersion": "3.12.2", "frameworkRevision": "058e0af2c2b57e369d905a03ac9748b0ebf543c6", "frameworkVersion": "3.44.8"}`. Serialized full-suite paths `[]`, flags `--no-pub --concurrency=4`; tree and HEAD were stable. Outcomes `{'success': 11768, 'failure': 13, 'error': 28, 'skipped': 20}` match latest `base2` by every identity and outcome, with no new failures, missing tests or new skips. Evidence `gate1.jsonl`, `.env.json`, `.stderr`, `gate1-against-base2.txt`. Gate 1 passes; step 3 may proceed.

### Step 3 — whole tuner State composition

- All eight eagerly initialized fields move into one owners object; the original lifecycle keeps construction/listener/disposal order. Four sections are constructed in fixed order through one nullable cache. Dependencies carry live context/mounted callbacks, the direct State setter tear-off, owner/view references and a live sections getter. All 21 typed widget-view getters forward to the current widget. The controller and public widget remain byte-identical. The controller-only `_focusRealIndex` forwarder retains the original signature/docs and a single forwarding statement; no temporary methods remain. Section constructors only store dependencies, and each declares exactly the getters it uses. Every body/scaffold matches the compiling step-0b probe.
- Facade measurement: 297 physical lines; declaration breakdown `{"StremioTvTuner": 106, "StremioTvTunerController": 26, "_StremioTvTunerState": 155, "imports_and_gaps": 10}`, summing exactly to that count. The detailed State-member AST ranges/counts are in `step3-facade-measurement.json`. The oversized-facade baseline entry is removed. This is within the 350 target and 400 hard limit; all 12 destinations are at most 500 lines.

- Previous checkpoint: `358ea14dea544e788d35ffb2b31d211c761dd38c`. All 17 manifests/self-tests pass with isolated packages; all other manifests' stdout/stderr and both AST modes are byte-identical to pre-change, with 32 raw adapter byte comparisons also passing. Occurrence, field, context, lexical-setter and callback guards pass. Architecture real-checker negatives, size, storage keys/references, formatter, CI analyzer allowlist, per-symbol inventory, whole-analyzer external identities, tuner LF and unchanged other manifest bytes, and staged diff pass. All 114 ORIGINAL characterization identities and shape tests pass against `base2`, including strict macOS 7/7; calibrated Linux 7/7 passes without image updates. The 20-token shape slice registers every file and the facade at zero residue, global floor 488 with zero slack. Theme and normalized light-ink expressions remain unchanged. Protected production/native/model/theme objects and original test assertions are byte-identical (evidence `step3-protected-objects.json`). No found-not-fixed code was repaired.
- Measured physical lines: `{"lib/features/stremio_tv_tuner/presentation/legacy_stremio_tv_tuner/stremio_tv_tuner_channels.dart": 198, "lib/features/stremio_tv_tuner/presentation/legacy_stremio_tv_tuner/stremio_tv_tuner_dependencies.dart": 21, "lib/features/stremio_tv_tuner/presentation/legacy_stremio_tv_tuner/stremio_tv_tuner_dial.dart": 155, "lib/features/stremio_tv_tuner/presentation/legacy_stremio_tv_tuner/stremio_tv_tuner_layout.dart": 228, "lib/features/stremio_tv_tuner/presentation/legacy_stremio_tv_tuner/stremio_tv_tuner_owners.dart": 41, "lib/features/stremio_tv_tuner/presentation/legacy_stremio_tv_tuner/stremio_tv_tuner_sections.dart": 18, "lib/features/stremio_tv_tuner/presentation/legacy_stremio_tv_tuner/stremio_tv_tuner_sheets.dart": 346, "lib/features/stremio_tv_tuner/presentation/legacy_stremio_tv_tuner/stremio_tv_tuner_widget_view.dart": 28, "lib/features/stremio_tv_tuner/presentation/stremio_tv_tuner_dial_card.dart": 499, "lib/features/stremio_tv_tuner/presentation/stremio_tv_tuner_parts.dart": 242, "lib/features/stremio_tv_tuner/presentation/stremio_tv_tuner_stage.dart": 357, "lib/features/stremio_tv_tuner/presentation/stremio_tv_tuner_stage_content.dart": 389, "lib/screens/stremio_tv/widgets/stremio_tv_tuner.dart": 297}`. No D2 or other extracted size exception. Per-entry production wiring/ownership is recorded in `step3-wiring-review.json`; symbol correspondence and removed original diagnostic identities are recorded in `step3-analyzer-identities.txt`.

### Step 4 — completion guards and gate 2 input

- Completion is enabled, the facade is registered in `main()` and `COMPOSITION_ROOTS`, and its composition comment explains the live bridge wiring. Its cap is the measured 299 lines, enforced with completion TEMP rejection. Feature guards remain unconditional. The real checker rejects missing facade, cap + 1, feature/bridge limits, TEMP markers, forbidden services/back-imports, playback/keep-alive, and both directions of sibling implementation imports; models remain allowed. CI format includes the facade and `test/support/stremio_tv_tuner_*.dart`; scoped analyze includes the facade inside the command before `| tee`. No analyzer/failure allowlist was changed.
- Final facade: 299 physical lines = `{"StremioTvTuner": 106, "StremioTvTunerController": 26, "_StremioTvTunerState": 155, "imports_and_gaps": 12}`. Detailed State counts are in `step4-facade-measurement.json`. Extracted size exceptions are empty, including D2 (dial card 499). Both gates use latest `base2`; gate 2 additionally compares against gate 1. The next run is gate 2 on this committed completed tree.
- Integration must union the additive owner/field/type binding options, context-validation/scaffold-activation hooks, tuner architecture registration/guards, shape entries, CI test paths and workflow paths, and facade size-ratchet removal. Device-only remote repeat/hold, real decode cost, tvOS focus, remote CI and merged integration checks remain pending. All five found-not-fixed items remain exactly as characterized.

- Previous checkpoint: `66ea3e848119d25122f559f2f4cbb175061e15a3`. All 17 manifests/self-tests pass with isolated packages; all other manifests' stdout/stderr and both AST modes are byte-identical to pre-change, with 32 raw adapter byte comparisons also passing. Occurrence, field, context, lexical-setter and callback guards pass. Architecture real-checker negatives, size, storage keys/references, formatter, CI analyzer allowlist, per-symbol inventory, whole-analyzer external identities, tuner LF and unchanged other manifest bytes, and staged diff pass. All 114 ORIGINAL characterization identities and shape tests pass against `base2`, including strict macOS 7/7; calibrated Linux 7/7 passes without image updates. The 20-token shape slice registers every file and the facade at zero residue, global floor 488 with zero slack. Theme and normalized light-ink expressions remain unchanged. Protected production/native/model/theme objects and original test assertions are byte-identical (evidence `step4-protected-objects.json`). No found-not-fixed code was repaired.
- Measured physical lines: `{"lib/features/stremio_tv_tuner/presentation/legacy_stremio_tv_tuner/stremio_tv_tuner_channels.dart": 198, "lib/features/stremio_tv_tuner/presentation/legacy_stremio_tv_tuner/stremio_tv_tuner_dependencies.dart": 21, "lib/features/stremio_tv_tuner/presentation/legacy_stremio_tv_tuner/stremio_tv_tuner_dial.dart": 155, "lib/features/stremio_tv_tuner/presentation/legacy_stremio_tv_tuner/stremio_tv_tuner_layout.dart": 228, "lib/features/stremio_tv_tuner/presentation/legacy_stremio_tv_tuner/stremio_tv_tuner_owners.dart": 41, "lib/features/stremio_tv_tuner/presentation/legacy_stremio_tv_tuner/stremio_tv_tuner_sections.dart": 18, "lib/features/stremio_tv_tuner/presentation/legacy_stremio_tv_tuner/stremio_tv_tuner_sheets.dart": 346, "lib/features/stremio_tv_tuner/presentation/legacy_stremio_tv_tuner/stremio_tv_tuner_widget_view.dart": 28, "lib/features/stremio_tv_tuner/presentation/stremio_tv_tuner_dial_card.dart": 499, "lib/features/stremio_tv_tuner/presentation/stremio_tv_tuner_parts.dart": 242, "lib/features/stremio_tv_tuner/presentation/stremio_tv_tuner_stage.dart": 357, "lib/features/stremio_tv_tuner/presentation/stremio_tv_tuner_stage_content.dart": 389, "lib/screens/stremio_tv/widgets/stremio_tv_tuner.dart": 299}`. No D2 or other extracted size exception. Per-entry production wiring/ownership is recorded in `step4-wiring-review.json`; symbol correspondence and removed original diagnostic identities are recorded in `step4-analyzer-identities.txt`.

### Full-suite gate 2 — accepted evidence

- Committed input `074551d6047085d094e95d0a1322c11013870463`, tested tree `2ef5480ae717ae667d1fa493598e8737c0f68b7f`; SDK `{"dartSdkVersion": "3.12.2", "frameworkRevision": "058e0af2c2b57e369d905a03ac9748b0ebf543c6", "frameworkVersion": "3.44.8"}`. Serialized full-suite paths `[]`, flags `--no-pub --concurrency=4`; tree and HEAD were stable. Outcomes `{'success': 11768, 'failure': 13, 'error': 28, 'skipped': 20}` match latest `base2` by every identity and outcome, with no new failures, missing tests or new skips. Evidence `gate2.jsonl`, `.env.json`, `.stderr`, `gate2-against-base2.txt` and `gate2-against-gate1.txt`. Gate 2 passes; all planned extraction work is complete. Device-only checks, remote CI and merged integration remain pending.
