# TV Home Views — Classic / Shelf / Canvas (plan)

> **STATUS 2026-08-03 (later): SHELF REMOVED after device test (user call);
> the pref is now Classic/Canvas only and stored 'shelf' coerces to classic.
> CANVAS device-validated and being iterated (synopsis, scrim pocket,
> left-anchored identity, white ring, tab dedupe).**
>
> **Earlier: BUILT, uncommitted, agent-review verdict SHIP.**
> All phases implemented + 1 review round each + final agent review (6
> findings → #1 #2 #3 #6 fixed, #5 fixed as a side effect of rail identity
> keys, #4 partially accepted). Residual accepted minors: vanished-rail
> fallback jumps to rail 0; `sec:` rail keys reset meaning across a full
> board reload; canvas remembered column decays to the built strip on
> revisit. Device test pending.

Goal: TV-only `tv_home_style` pref with three home layouts. Classic stays the
default and pixel-identical. All new code is additive and unreachable unless
the pref is flipped. Everything lands uncommitted.

## Architecture decision (deviation from "controller extraction")

The earlier sketch called for extracting home orchestration into a controller.
After mapping the code: all three views can consume SearchScreen's EXISTING
state fields and pipeline (`_sections`, `_CwRow.nodes`, `_setHero`,
`_applyHero`, `_loadMoreBoard`, `_heroTrailer*` listenables) directly if they
are built as alternate build paths inside the same State. Zero orchestration
is forked; only presentation differs. A standalone controller refactor of a
17k-line live file, done autonomously without device testing, is the riskiest
possible first step for zero user-visible gain — so views live in
search_screen.dart (+ small standalone widgets in lib/widgets/home/) and the
extraction happens opportunistically later if a 4th consumer appears.

## Key enabling facts (verified in code)

- Underlay hole = wherever the engine widget is laid out: `_UnderlayHole`
  measures its own RenderBox each frame and pushes `setBounds` to native
  (trailer_engine.dart:448-466). Full-bleed trailer = lay `_HeroTrailerLayer`'s
  region out full-canvas. No native work.
- `_heroTrailerTakeover` is permanently 0 (never assigned) — the takeover
  overlay machinery is inert; we do NOT revive it. CANVAS gets full-bleed
  ambient directly via region geometry instead.
- Hole invariants: never put an ancestor Opacity/saveLayer around the engine
  widget; overlays painted ABOVE the hole are fine when they are plain
  gradient/color draws (the feathers already do this, on-device proven).
  Animated veils over the hole use color-lerp ColoredBox (TweenAnimationBuilder),
  never AnimatedOpacity wrappers.
- Pref pattern to copy: `phone_nav_style` (StorageService get/set with value
  coercion, cached field + MainPageBridge VoidCallback for live change).
- Picker page pattern to copy: `tv_screen_size_page.dart` (radio-row
  SettingsTiles, DPAD-safe, entry-focus marker).
- Catalog row FocusNodes are parallel to `_sections` (`_rowNodes`), CW/fav
  rows carry their own nodes — reusing rows keeps the DPAD grid intact.
- `_derivedHeroLogo` derives metahub logo URLs from IMDb ids synchronously;
  same trick derives `background/medium` stills for Shelf CW cards.

## Phase 1 — pref + plumbing

1. StorageService: `tv_home_style` key, `getTvHomeStyle()` coercing to
   `classic|shelf|canvas` (default classic), `setTvHomeStyle`.
2. New `lib/screens/settings/tv_home_style_page.dart` — radio picker page
   (Classic / Shelf / Canvas with one-line descriptions), persists on select,
   fires `MainPageBridge.tvHomeStyleChanged?.call()`.
3. Register: settings_screen.dart TV Mode section (`if (_isAndroidTv)` nav row
   like tvScreenSize) + settings_tv_layout.dart TV Mode case + settings-search
   entry (TV-gated).
4. MainPageBridge: `static VoidCallback? tvHomeStyleChanged;`
5. SearchScreen: `String _tvHomeStyle = 'classic'` loaded in initState;
   register bridge callback (home board instance only, cleared on dispose) →
   reload pref, `_clearHeroTrailer()` + `_clearHeroLiveIptv()` (player teardown
   before layout swap), setState.
6. Branch point in `_buildBoard()` gated
   `widget.isTelevision && !widget.searchMode && !widget.discoverMode`:
   canvas → `_buildCanvasBoard()` (Phase 3; until then falls back to classic),
   shelf → classic structure with row-variant flag (Phase 2).
   Search tab & phone always classic.

## Phase 2 — SHELF (Classic hero kept; rows are the redesign)

Deliberate scope cut vs mock: the boxed hero/trailer stage stays EXACTLY as
Classic (full-width hero + boxed trailer region would fight; not worth the
trailer-machinery risk). The rows change:

1. `_CardFocusRise` gains `aspectRatio` (default 2/3) and `ringColor`
   (default = current behavior). Shelf/Canvas pass white ring.
2. CW row (shelf): 16:9 cards — width `(boardH*0.40).clamp(200,300)`,
   backdrop still `item.background ?? derived metahub background ?? poster`,
   logo overlay `item.logo ?? derived` (error → title text), episode label,
   WHITE hairline progress. Same `row.nodes`, same `_BoardCell` wiring,
   same callbacks — only the cell visual + row height differ.
3. Top-10 row: section 0 renders numeral-style (outlined giant numeral behind
   a poster, first 10 items only, header "Top 10 · <title>"). Same
   `_rowNodes[0]` (list may be longer than 10 → clamp nodes usage to
   rendered count via the existing nearest-mounted logic; grid stays parallel
   because the SECTION index is unchanged). onNearEnd paging disabled for this
   row (fixed 10).
4. Catalog rows (shelf): `_railPosterW` → `(boardH*0.21).clamp(110,165)`.
   Hero budget auto-adapts (it derives from `_railPosterW`).
5. Fav rows + skeleton rows unchanged.

## Phase 3 — CANVAS

New `_buildCanvasBoard()` replacing hero+ListView entirely (loading/error
states shared with classic):

1. Rails model (built per build, cheap): `[('Continue Watching', cwItems)]`
   (if enabled+nonempty) + one rail per `_sections[i]`. Fav rows and lists
   rail are OUT of canvas v1 (documented); IPTV live layer not mounted →
   `_setHeroLiveIptv` never fires.
2. Stage: full-canvas Stack —
   a. art layer: `ValueListenableBuilder` on `_heroItem`/`_heroEnriched` →
      CachedNetworkImage full-bleed (bg ?? poster), AnimatedSwitcher ~220ms
      keyed by URL (TvAmbientArtStage pattern), NO Ken Burns full-bleed
      (3× the region area = real per-frame cost on the box; static + trailer
      motion instead).
   b. `_HeroTrailerLayer` with new `fullBleed: true` — region = full canvas
      (bypasses `_heroTrailerRegionRect`); boxed feathers off in this mode.
      Ambient chip kept.
   c. scrims: ONE set of left+bottom gradient DecoratedBoxes painted ABOVE
      the trailer layer (siblings after it in the stage Stack) so they read
      identically over idle art AND over live video (widgets above the hole
      punch render over video — the feathers prove this pattern on-device).
      Plain draws, hole-safe; no state-dependent scrim swap, no pop at
      trailer start.
   d. identity: logo (`item.logo ?? _derivedHeroLogo`, text fallback) + meta
      line bottom-left above the shelf; plain draws over the hole area.
   e. rail tabs: text row (active white + underline, inactive 40%) — display
      only, not focusable.
   f. shelf: one horizontal row of `_StremioCard`-style cards
      (`(boardH*0.30).clamp(150,220)` tall posters), own FocusNode list
      rebuilt per rail; LEFT at col 0 → `MainPageBridge.focusTvSidebar`;
      LEFT/RIGHT browse (existing ensureVisible glide); UP/DOWN → switch rail
      (crossfade shelf, keep per-rail remembered column); OK/hold-OK → same
      open/menu callbacks as classic rows.
3. Hero feed: shelf card focus → `_setHero(item)` (existing 260ms settle +
   enrich + tint + trailer schedule all reused).
4. Paging: rail switch near end of sections + `_boardHasMore` →
   `_loadMoreBoard()`; within-rail near-end → `_loadMoreRow(sectionIndex)`.
5. Dim-on-ambient: when trailer showing, dim tabs/meta via color-lerp veil
   (no opacity layers over the hole).

## Per-phase inline review + `flutter analyze` after each phase.
## Phase 4 — final thorough review: 1 agent over the full uncommitted diff
   (extraction fidelity irrelevant here; focus: Classic regression risk, hole
   invariants, focus traversal dead-ends, teardown on style switch, paging),
   fix confirmed findings, re-analyze.

## Non-goals / explicitly deferred
- ORBIT view (rejected). Full-width Shelf hero. Ken Burns on canvas.
- Fav/lists rails + IPTV live preview in canvas. Phone/desktop styles.
- Persisting canvas rail index across sessions.

## Plan self-review notes (2 passes, issues found → fixed above)
- R1: takeover revival dropped (machinery inert; full-bleed via geometry is
  strictly simpler) — plan updated. Style-change teardown added (players
  cleared BEFORE setState relayout). Search-tab gating pinned to
  `!searchMode && !discoverMode`.
- R2: Top-10 grid safety (nodes list longer than rendered cells) resolved via
  render-count clamp note; shelf CW row keeps `row.nodes` count == item count
  (cards 1:1). Canvas scaffold keeps `glassHome` transparency + ambient-art
  publishing (sidebar glass still works). Canvas skips Hero flight tags
  (null heroTag) to avoid duplicate-tag asserts across rail swaps.
- R3: canvas scrim z-order fixed — scrims must paint ABOVE the trailer layer
  (one shared set for art+video states), not below where the hole punch would
  clear them. Bridge callback registration gated to the HOME board instance
  only (`isTelevision && !searchMode && !discoverMode`) and cleared on dispose
  only if still ours — SearchScreen has multiple live instances (search tab).
