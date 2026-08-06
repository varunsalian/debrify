# TV Home Layouts — Atrium / Mosaic / Promenade / Deck / Tonight (plan)

> **STATUS 2026-08-06: ALL FIVE BUILT, uncommitted, device test pending.**
> `flutter analyze` clean (0 errors / 0 warnings); `flutter test` 861 pass / 8
> fail, and those 8 fail identically on a clean tree (pre-existing).
> Selectable from Appearance → Home Screen → Home Layout. Additive only:
> Canvas and Classic are unchanged in behaviour.
> Mocks: `tv_home_layouts_mockup/` (artifact e35fe51f).
>
> **Plan corrections found by review (the code is right, the plan text was
> not):**
> - §2.1 `setTvHomeStyle` DID have to change — the old setter coerced every
>   value that wasn't 'classic' to 'canvas', so it would have silently eaten
>   all five new ones. It now whitelists `StorageService.kTvHomeStyles`.
> - §7 "neither zone → BrandLoadingStage" is unreachable: the shared board
>   guards above the layout dispatch already return the "No catalogs yet"
>   empty state. Tonight's guard only covers the still-streaming case.
> - §5 art order is `background → metahub → poster` (`_wideArtUrl`), i.e. an
>   addon's own artwork always wins; the plan had metahub first.
> - §0.3's "no full-screen tweens" has ONE deliberate exception, inherited
>   from shipped Canvas: `_CanvasScrims` fades on an `AnimatedOpacity` for
>   theater mode. It is device-validated, runs at most twice per trailer, and
>   is a sibling ABOVE the hole — not an ancestor of it. Promenade and Deck
>   reuse it as-is rather than forking the theater cadence.

Goal: `tv_home_style` grows from 2 values to 7. Canvas stays the default and
stays pixel-identical. Classic stays pixel-identical. Every new layout is a new
build branch inside `SearchScreen`'s State, consuming the SAME orchestration
(sections, CW rows, favourites, hero pipeline, trailer engine, paging) — zero
forked data flow, exactly the precedent set by `HOME_VIEWS_PLAN.md`.

---

## 0. Non-negotiable invariants (from the shipped code + prior device pain)

These are the rules every phase is checked against. Violating one is a P1.

1. **Underlay hole = the trailer layer's laid-out rect.** `_UnderlayHole`
   measures its own RenderBox and pushes `setBounds` natively
   (trailer_engine.dart). `_HeroTrailerLayer(fullBleed: true)` therefore means
   "fill MY box", not "fill the screen" — a boxed rect is achieved by
   positioning the layer, not by a new mode. Verified at search_screen.dart
   13234-13236.
2. **Never place `Opacity`/`AnimatedOpacity`/any saveLayer ANCESTOR around the
   trailer layer.** Its `BlendMode.clear` punch-through breaks against the
   translucent surface. Sibling layers painted ABOVE the hole are fine —
   gradients, colours AND images (Canvas already paints its shelf posters over
   the full-bleed video on-device).
3. **No full-screen gradient TWEENS.** Every full-screen field snaps or is
   constant. Animated veils use colour-lerped `ColoredBox`, never an
   `AnimatedOpacity` wrapper around a subtree.
4. **Derived heights, never magic numbers.** The Canvas regression (a33982c)
   came from a hardcoded identity clearance while the shelf grew. Every layout
   computes its reserved space from the same constants the widgets read.
5. **One strip height across rail kinds.** Favourites cells carry a caption
   band; catalog cells don't. A per-rail height makes the tabs/identity jump on
   every fav↔catalog switch and overflows mid-crossfade.
6. **`AnimatedSwitcher` centres its child by default** — pin `layoutBuilder`
   whenever the swapped block is edge-anchored.
7. **A FocusNode may be mounted exactly once.** All layouts reuse the classic
   per-row node lists (`_CwRow.nodes`, `_favNodesFor`, `_rowNodes`); only ONE
   layout is ever mounted, and a rail appears in exactly one zone.
8. **Post-frame focus requests re-check** `mounted` AND that the same layout is
   still active AND resolve to a **mounted** node (`_nearestMountedNode`) —
   requesting focus on a detached node latches a stray grab.
9. **Sidebar opens ONLY via LEFT** at a zone's left edge
   (`MainPageBridge.focusTvSidebar`). No other key may reach it.
10. **Fav cells are `Center`-wrapped** in a fixed-height slot so the focus
    scale isn't clipped.
11. **Style switch tears down live players BEFORE relayout**
    (`_onTvHomeStyleChanged`) so the engine widget is never re-parented
    mid-play.

---

## 1. Verified facts this plan is built on

| Fact | Where |
|---|---|
| `_HeroTrailerLayer(fullBleed:true)` fills its own box; skips boxed feathers | 13234 |
| `_HeroLiveLayer` same shape, painted above the trailer layer | 13398 |
| `_CanvasArtLayer` is geometry-agnostic (fills its box, opaque floor) | 14508 |
| `_BoardCell` handles L/R internally via `column`+`rowNodes`; `onUp`/`onDown` are callbacks; LEFT at col 0 → sidebar | 14360 |
| `_FavArtCell` — same contract | 15344 |
| `_StremioCardState` / `_ArtPosterState` call `Scrollable.ensureVisible` on focus (140ms TV glide) | 15105 / 15587 |
| `CardFocusRise` hardcodes `AspectRatio(2/3)` — needs an optional override for 16:9 stills | card_focus_rise.dart |
| `_canvasRails` = CW rows → favourites rails → catalog sections | 4361 |
| Rail identity keys `cw:<title>:<tag>` / `fav:<kind>` / `sec:<i>` | 4305 |
| `_canvasCols` remembers a column per rail key | 4091 |
| `_canvasActive` has exactly **7** call sites | 3768, 4060, 4269, 4287, 4441, 4472, 10740 |
| `_metahubLogoUrl` derives logo art from an IMDb id synchronously | 14447 |
| `_metahubBackgroundUrl` **does not exist** (deleted with SHELF) — must be re-added for 16:9 stills | — |
| `_scheduleHeroTrailer` already refuses to start under a fav/live stage | 5017 |
| Settings plumbing reads `kTvHomeStyleChoices` + `tvHomeStyleLabel` — adding entries flows to the picker, the Appearance row subtitle and settings search automatically | tv_home_style_page.dart + 3 call sites |

---

## 2. Shared plumbing (Phase 0)

### 2.1 Pref
`StorageService.getTvHomeStyle()` currently returns `classic` for the literal
string and `canvas` for everything else. Replace with a whitelist:

```dart
const _kTvHomeStyles = {'classic','canvas','atrium','mosaic','promenade','deck','tonight'};
// unknown / unset / removed ('shelf') → 'canvas'
```

`setTvHomeStyle` unchanged. **Coercion must stay total** — a value written by a
newer build and read by an older one must not crash.

### 2.2 State getters (replacing the `_canvasActive` monoculture)

```dart
String get _homeStyleEffective => _homeBoardMode ? _tvHomeStyle : 'classic';
bool get _stageActive   => _homeStyleEffective != 'classic';   // any of the 6
bool get _canvasActive  => _homeStyleEffective == 'canvas';    // canvas only
bool get _stageWantsAmbient => switch (_homeStyleEffective) {
  'canvas' || 'promenade' || 'deck' || 'atrium' || 'tonight' => true,
  _ => false,                                                  // mosaic: no video
};
bool get _theaterEligible => switch (_homeStyleEffective) {
  'canvas' || 'promenade' || 'deck' => true, _ => false,
};
```

**Audit of the 7 `_canvasActive` sites** (each must be re-pointed deliberately):

| Site | Now | Becomes | Why |
|---|---|---|---|
| 3768 `_topBoardFocusNode` | canvas | `_stageActive` | every stage layout routes focus through `_stageFocusTarget()` |
| 4269 `_onCanvasTrailerShowingChanged` guard | canvas | `_theaterEligible` | theater only where the video owns the frame |
| 4287 theater timer fire guard | canvas | `_theaterEligible` | same |
| 4441 `_canvasSwitchRail` post-frame | canvas | `_stageActive` | shared by all |
| 4472 focus seed post-frame | canvas | `_stageActive` | shared by all |
| 10740 board branch | canvas | `switch (_homeStyleEffective)` | dispatch |
| 4060 definition | — | keep + add the new getters | |

Additionally `_scheduleHeroTrailer` gains `if (!_stageWantsAmbient && _stageActive) return;`
and `_canvasFavFocused` only calls `_setHeroLiveIptv` when `_stageWantsAmbient`.

### 2.3 Rails per layout

```dart
List<_CanvasRail> get _stageRails => _homeStyleEffective == 'tonight'
    ? _canvasRails.where((r) => r.cw == null).toList()   // CW lives in the queue
    : _canvasRails;
```

`_stageFocusTarget()` = today's `_canvasFocusTarget()` but over `_stageRails`,
plus the Tonight queue branch (§7). `_canvasSwitchRail` → `_stageSwitchRail`,
same body over `_stageRails`.

### 2.4 Shared widget changes (additive, defaulted)

- `CardFocusRise` gains `double aspectRatio = 2/3`.
- `_CanvasIdentity` gains `variant` (`stage` default | `narrow` | `centered`):
  - `narrow` — logo capped to the column width, meta wraps onto two lines
    (facts line + genres line), synopsis 4 lines in a fixed slot.
  - `centered` — cross-axis centre, no synopsis, centred meta row.
- `_CanvasScrims` gains `centerPocket` (Promenade) and `seam` (Atrium:
  left-edge feather at the split instead of the full left column scrim).
- `_BoardCell` and `_FavArtCell` gain `VoidCallback? onLeft` / `onRight`
  overrides. **Null keeps today's behaviour byte-for-byte.** Needed because a
  grid's leftmost cell is not `column == 0`, so the sidebar would otherwise be
  unreachable from rows 2+.
- New `_metahubBackgroundUrl(item)` mirroring `_metahubLogoUrl`
  (`background/medium/<tt>/img`), used by Promenade + Tonight stills with a
  fallback chain `background ?? metahub ?? poster`.

### 2.5 Settings
`kTvHomeStyleChoices` grows to 7, ordered: Canvas, Classic, Atrium, Mosaic,
Promenade, Deck, Tonight — each with a one-line subtitle. No other settings
file changes (all three call sites read the list/label helper).

---

## 3. ATRIUM

**Shape.** Vertical split at `w * 0.38`.
- Left: flat `kStremioBg` column, never focusable, holding the `narrow`
  identity (eyebrow = active rail name, logo, meta, synopsis, OK/▸ hints),
  vertically centred. Fav-focus override renders title+subtitle as Canvas does.
- Right: `_CanvasArtLayer` + trailer + live layers filling the right rect;
  scrims = seam feather (left edge of the art) + bottom ramp.
- Bottom-right: a **two-rail wall** — active rail on top, next rail below.
  `cardH = (h * 0.205).clamp(100, 170)`, `cardW = cardH * 2/3`; one height for
  both rows and for fav vs catalog rails (invariant 5).

**Reserved height** = `2 * (railLabelH + cardH + captionBand) + gaps + tail`,
computed once and used both for the wall's own box and to keep the art's bottom
ramp aligned. Never hardcoded.

**Nav.** Window = `[active, active+1]`.
| From | Key | Result |
|---|---|---|
| row A (rail i) | UP | active := i-1 (clamped), focus row A |
| row A | DOWN | focus row B at its remembered column |
| row B (rail i+1) | UP | focus row A |
| row B | DOWN | active := i+1, focus row B (now rail i+2); at the end → `_loadMoreBoard()` |
| either, col 0 | LEFT | sidebar |

When `rails.length == 1` only row A renders and DOWN pages/no-ops.

**Theater:** no. **Ambient trailer:** yes, in the right rect.

---

## 4. MOSAIC

**Shape.** No hero. Full-bleed `_CanvasArtLayer` of the focused title under a
**constant** `Color(0xDE0D0B1A)` veil plus one constant violet bloom radial
(no tween — invariant 3). Top band: `narrow`-ish identity (logo `md` + one meta
line) left, `_canvasTabs` right. Grid fills the rest.

**Grid.** `crossAxisCount` derived from available width and a target cell width
(~`h * 0.28 * 2/3`), min 5 / max 8; `GridView.builder` with
`SliverGridDelegateWithFixedCrossAxisCount`. Cells are the SAME `_BoardCell` /
`_canvasFavCell` widgets — cards self-scroll via their existing
`ensureVisible`.

**Nav** (needs the new `onLeft`/`onRight` overrides):
| Key | Result |
|---|---|
| LEFT | `col % perRow == 0` → sidebar; else focus `col-1` |
| RIGHT | `col+1 < len` → focus `col+1`; fire `onNearEnd` within 2 rows of the end |
| UP | `col-perRow >= 0` → focus that; else `_stageSwitchRail(-1)` |
| DOWN | `col+perRow < len` → focus that (+`onNearEnd`); else `_stageSwitchRail(1)` |

**Ambient trailer: deliberately OFF** (`_stageWantsAmbient` false) — Mosaic has
no stage, the art is a 13%-visible wash, and this is what makes it the cheapest
layout on weak GPUs. IPTV favourite focus therefore shows the channel's art in
the wash, not a live feed. *(Flagged for review: is this an acceptable
deliberate omission or a feature gap?)*

---

## 5. PROMENADE

**Shape.** Canvas geometry (full-bleed art/trailer/live), symmetric
composition: `centered` identity in the lower third, a centred rail eyebrow
`‹  RAIL NAME  ·  3/12  ›`, and a **centre-locked strip**.

**Strip.** Height `stripH = (h * 0.20).clamp(96, 150)`; catalog/CW cells are
16:9 (`w = stripH * 16/9`) using `_metahubBackgroundUrl ?? background ??
poster`; fav rails keep poster-shaped cells at the same height (a rail is
homogeneous, so the strip never mixes shapes).

**Centre lock.** Horizontal `ListView` with leading/trailing padding of
`(viewportW - cellW) / 2` so items 0 and N-1 can also reach dead centre;
existing `ensureVisible(alignment: 0.5)` does the travel. Unfocused cells rest
at `scale .86 / opacity .55` (transform+opacity only).

**New widget** `_StillCell` — 16:9 art + progress bar + episode badge + focus
ring via `CardFocusRise(aspectRatio: 16/9, ringColor: white)`; same
`onUp/onDown/onLeft/onRight/onOpen/onLongPress/onNearEnd` contract as
`_BoardCell` so paging, CW hold-OK menu and quick-play all survive.

**Nav.** Canvas grammar unchanged (L/R along, U/D switch rail).
**Theater:** yes.

---

## 6. DECK

**Shape.** Constant radial ground. Hero **card**: `cardW = w * 0.52`,
`cardH = cardW * 9/16`, at `left = w * 0.39`, `top = h * 0.12`. Trailer/live/art
layers fill that rect. Two peek cards behind it (static art, `translateX` +
`scale .94/.87`, opacity `.52/.30`). Identity (`narrow`) at the left. One
compact rail + rail label at the bottom.

**Rounded corners over video.** A `CustomPainter` above the layers fills
`rect − RRect(24)` with `kStremioBg` (`Path.combine(difference)`). Plain paint
above the hole — allowed (invariant 2). No clip, no saveLayer.

**Deal motion.** The peek stack is an `AnimatedPositioned`/`AnimatedScale`
group keyed off the focused column parity — transform+opacity only, 260ms.
The hero card itself never animates its RECT (moving the hole every keypress
would thrash `setBounds`); only the peeks move.

**Nav.** Canvas grammar. **Theater:** yes.

---

## 7. TONIGHT

**Zones,** ordered top→bottom for UP/DOWN traversal:
`[queue rows…]` then `[the active non-CW rail]`.

- **Queue** = every CW row flattened to `(rail, col)` pairs, windowed to 4
  visible rows, using `cw.nodes[col]` (mounted exactly once — CW rails are
  excluded from `_stageRails`, §2.3). Row = 16:9 thumb + title + `S· E·
  subtitle` + progress bar. Vertical `ListView`; rows self-scroll.
- **Big card** (display-only, not focusable) mirrors the focused item: art
  layer + trailer/live in the card rect, bottom gradient, logo `sm`, episode,
  time-left, progress, `OK Resume` hint.
- **Bottom rail** = the active `_stageRails` entry, horizontal, Canvas cells.

**Nav.**
| From | Key | Result |
|---|---|---|
| queue row i | UP | i>0 → row i-1; else nothing (top of board) |
| queue row i | DOWN | i+1 < queue.length → row i+1; else first cell of the bottom rail |
| queue row | LEFT | sidebar |
| queue row | RIGHT | no-op |
| rail cell | UP | previous rail if any; else last queue row; else nothing |
| rail cell | DOWN | next rail; at the end → `_loadMoreBoard()` |

**Degenerate cases (must be handled, not crash):**
- No CW rails → queue omitted, big card + rail only, rail UP = previous rail.
- No non-CW rails → rail strip omitted, queue only, queue DOWN = no-op.
- Neither → `BrandLoadingStage` (shared guard).

**Zone tracking.** `_tonightZone` (`queue` | `rail`) + `_tonightQueueCol`;
`_stageFocusTarget()` returns the queue node when the zone is `queue`. Both
reset on layout switch / board reseed.

**Header.** `Tonight` + weekday word + "N in progress". **No clock** — a
ticking `Timer` on the home board is not worth a minute-accurate label.

**Theater:** no. **Ambient trailer:** yes, in the card rect.

---

## 8. Phasing (each phase: implement → `flutter analyze` → codex review → fix)

| Phase | Contents |
|---|---|
| 0 | Pref whitelist, state getters, `_canvasActive` audit, `_stageRails`, shared widget params, `_metahubBackgroundUrl`, 7 settings choices. Canvas/Classic must be byte-identical in behaviour. |
| 1 | **Promenade** — closest to Canvas; validates the shared refactor first. |
| 2 | **Atrium** — first boxed-art layout; validates rect-scoped trailer + two-rail window. |
| 3 | **Mosaic** — first grid; validates `onLeft/onRight` overrides + grid paging. |
| 4 | **Deck** — card rect + corner painter + deal motion. |
| 5 | **Tonight** — zones, queue, degenerate cases. |
| 6 | Full codex review, `flutter analyze`, `flutter test`, doc + memory update. |

## 9. Test matrix (per layout, to be walked by review)

Cold start with rails still streaming · CW rails prepending late (must not swap
the shown rail) · fav rail focus (art + title override) · IPTV fav live preview
· switching layout mid-trailer · sidebar reachable via LEFT from every zone's
left edge · paging at the end of a rail and at the last rail · empty board ·
board reseed (See-All return / Home Rows / integrations) · text scale ·
Screen Size settings (narrow board) · hold-OK CW menu · quick-play on catalog
cells.

## 10. Open questions for review

1. Mosaic's deliberate no-trailer/no-live decision — acceptable, or must every
   layout carry the full stage feature set?
2. Atrium's two-rail window: should UP from row A at rail 0 fall through to the
   sidebar, or stay put?
3. Deck's peek cards: static art of the next two ITEMS in the rail, or the next
   two RAILS' first items? (Plan says items.)
4. Tonight with a single CW row of 1 item — queue of one row; is that worth
   rendering, or should the queue require ≥2?


---

## 11. What actually shipped (2026-08-06, uncommitted)

Three review rounds (one on the plan, two on the code). Everything below is in
the working tree; `flutter analyze` is clean and the test suite matches a clean
checkout exactly.

### Shared plumbing
`StorageService.kTvHomeStyles` (7-value whitelist, total coercion both ways) ·
`_stageActive` / `_stageWantsAmbient` / `_stageWantsLivePreview` /
`_theaterEligible` / `_stagePublishesShellArt` · `_stageRails` (Tonight lifts CW
rows out) · `_resolveStageRail` → `_StageRailView` · `_stageFocusTarget`
(Atrium's lower row and Tonight's zone aware) · `_stageSwitchRail` ·
`_stagePostFrameFocus` (style + `_stageGeneration` guarded) ·
`_resetStageNavigation` / `_applyStageTransition` (ONE transition path: the
picker AND the cold-start pref load) · `_maybeCompleteStageAdvance` /
`_maybeCompleteStageRight` (a DPAD press waiting on a page completes when it
lands) · `_stagePosterW` / `_stageFavW` / `_stageRailBoxH` (one box height, two
fills, floor derived from the SCALED caption band).

### Widget changes (all additive, all defaulted)
`CardFocusRise.aspectRatio` + `.restVeil` · `_StremioCard.aspectRatio` +
`.artUrl` + `.restVeil` · `_BoardCell` / `_FavArtCell` `.onLeft` / `.onRight`
overrides · `_canvasFavCell` nav overrides · `_CanvasScrims.variant`
(canvas/centered/seam) · `_CanvasIdentity.variant`
(stage/narrow/centered/headline) + `.maxWidth` · `_StageFavIdentity` (extracted,
now shared with Canvas) · `_CornerWedges` painter (rounded corners over the
punch hole without a clip) · `_TonightQueueRow` · `_TonightCardCaption` ·
`_metahubBackgroundUrl` / `_wideArtUrl`.

### Deliberate design decisions (not omissions)
- **Mosaic plays no catalog trailer.** It has no stage — the art is a 13%-visible
  wash behind a grid — so a trailer would be invisible AND the most expensive
  thing on screen. The IPTV live preview IS kept (the veil lifts for it), because
  that is the only way to see what a channel is playing.
- **Tonight's OK opens the detail page**, like every Continue Watching card in
  the app; HOLD resumes. The card's hint says so rather than promising a resume
  the key doesn't perform.
- **Canvas keeps its `AnimatedOpacity` theater fade.** It is a sibling above the
  hole (never an ancestor), device-validated, and Promenade/Deck reuse it rather
  than forking the cadence.
- **Rail identity survives a layout switch** only for content-addressed keys;
  `sec:<i>` keys and their columns are dropped on a board reseed because the
  index means a different catalog afterwards.

### Still to do
Device test on the Mi Box — nothing here has run on hardware. Walk the matrix in
§9 for each of the five, and watch in particular: Atrium's two-row window at the
board's real height, Mosaic's grid paging at a rail boundary, Deck's corner
wedges over live video, Tonight's queue with two CW sources, and switching
layouts mid-trailer.


## 12. Review rounds

| Round | Scope | Outcome |
|---|---|---|
| 1 | The plan, checked against the code | 8 P1 / 7 P2. Biggest: `setTvHomeStyle` would have eaten all five new values; cold-start pref load is a layout TRANSITION and must tear down players; `sec:` rail keys go stale on reseed; post-frame focus needs a generation guard. |
| 2 | The implementation | 6 P1 / 5 P2. Geometry: every layout had a clamp that re-spent reserved height, and fixed boxes that a scaled caption overflows. Behaviour: Mosaic's DOWN trapped focus in a long catalog; Deck's peeks never re-derived; Mosaic silently lost the IPTV live preview. |
| 3 | The implementation again | 1 P1 / 7 P2 / 2 P3. The P1: a deferred page-load completion checked only the rail key, so a late batch could yank focus after the user had moved along that same rail. Now every deferred move is anchored to the FocusNode that pressed the key and re-checked inside the frame. |
| 4 | Verification of round 3's fixes | 1 P1 / 3 P2 / 1 P3, all fixed. The P1: Atrium's deferred completion delegated to `_atriumAdvance`, whose own post-frame never re-checked the captured origin. Also: a queue-only Tonight could still end up unfocusable; the headline identity fallback dropped its genres into an ellipsising facts row; a style transition cleared the shell but never republished it for the layout being entered. |

Every P1 and P2 raised across the four rounds is fixed. What is NOT verified is
behaviour on real hardware — see §11.

Self-found between rounds: Atrium's UP from the top row landed back on the row
it came from (the window's marker had to be re-anchored); Tonight dropped its
queue instead of shrinking the card on a narrow board; the caption band was
being reserved on catalog cells that don't have one, costing ~45px per row.
