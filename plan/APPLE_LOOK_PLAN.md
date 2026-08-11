# Spotlight & Showcase — the tvOS idiom as two layouts and one Look

Ship the two mocked layouts (`apple_look_mockup/`) plus the focus mechanic that
makes them feel like the reference, and bundle them as a **Look** in
Appearance → Presets.

| What | Where | Value |
|---|---|---|
| **Spotlight** | Home | new `tv_home_style` value `spotlight` |
| **Showcase** | Series/movie detail | new `detail_page_style` value `showcase` |
| **Spotlight** (Look) | Appearance → Presets | new `AppLook` |

The mock is the specification. `apple_look_mockup/index.html` is drawn at
1920×1080; **every number here is logical (÷2)** unless it says otherwise.

> **Revised twice against codex review.** Round 1 (9 P1s): LEFT edge policy,
> landing/pagination, `DetailModel` gaps, registration surface, hero source,
> trailer lifecycle, the existing Look system, theme registration, cross-card
> velocity. Round 2 (8 P1s): `ownScrim` does not remove the shell tint,
> `PremiumLooks.all` registry, `FocusExpressionBox` has no parallax arm,
> `select`'s early return, the real Spotlight integration surface, the Home
> picker, bound-source refresh, and `ParallaxTravel` having no producer.
> Round 3 (6 P1s): `shellTint` must suppress *both* shell gradients, the
> `ThemeSpec` was not constructible, parallax must not double-scale, four test
> pins not one, the trailer exclusion belongs in one function, and
> `AppLook.isActive` ignores the theme mirror.
> §7 records every change so nobody re-proposes a rejected shape.

---

## 1. Non-negotiables

1. **The mock is the spec.** Where this document and the mock disagree, the
   mock wins. Fidelity is checked band by band in Phase 5 against a 1:1
   screenshot.
2. **Additive.** Two new enum values, one new Look, one new theme id. Every
   existing home style, detail style, sidebar style and theme renders
   byte-identically.
3. **Legacy byte-identity holds.** Under `AppThemes.legacy` nothing here may
   alter a shipped pixel. The mechanic is opt-in via a `FocusExpression` value
   legacy never selects.
4. **DPAD before paint.** Every band reachable, in visual order, by explicit
   node targeting. Geometric traversal is forbidden.
5. **Sidebar opens ONLY via LEFT** — and *not from the detail page*, which is a
   pushed `MaterialPageRoute` and has no sidebar to open (§3.3).
6. **TV cost budget.** No per-frame `Opacity`, no `BackdropFilter`, no
   `saveLayer` in a focus tick, no `X.of(context)` inside an animation
   callback. Alpha baked into colours. `RepaintBoundary` around every animating
   card.
7. **Punch-hole rule, stated precisely.** No `Opacity`, filter or other
   **saveLayer-inducing ancestor** around the underlay's clear node. Siblings
   *above* the video are fine and are how the shipped code already fades hero
   metadata; a hard-edge `ClipRect` is also already an ancestor and is fine.
8. **Reduced motion collapses the mechanic to its end state**, it does not
   disable the layout.

---

## 2. What the mock specifies

### 2.1 The focus mechanic

| Part | 1920 | **logical** |
|---|---|---|
| Lift | scale 1.1 | scale 1.1 |
| Rise | `-140 × (s−1)` | `-70 × (s−1)` → 7px at full lift |
| Tilt | ±10° both axes | ±10° |
| Perspective | 1400 | **700** |
| Shift | 0.8px/deg | **0.4px/deg** |
| Shadow | `0 32 50 · black .45`, sliding **opposite** the tilt at 2.2px/deg | `0 16 25`, 1.1px/deg |
| Glare | white radial 170% of the card, parked −26% above, tracking tilt 4.2%/deg, `screen`, α .5 | same ratios |
| Brightness | `1 + 0.05 × lift` | same |

Per-shape scale (1.1 is a *poster* figure):

| Shape | scale |
|---|---|
| poster, landscape, source card | 1.10 |
| episode still | 1.055 |
| cast circle | 1.08 |
| season pill | 1.06 |

**Borderless.** No ring on anything; the lift is the signal.

**Timing is the point.** ζ ≈ 0.82: every move overshoots and settles. Use
`SpringSimulation` + `animateWith`.

**The d-pad has no pointer.** On focus gain, kick the rotation's **velocity**
away from the travel direction and let the spring carry it back through
neutral. Never ease to a tilt target.

### 2.2 Grounds

| Surface | Ground |
|---|---|
| Spotlight scrolled | **`#1B1C1C` → `#1F1D1C`**. *Measured*: `rgb(28,28,28)` at every gutter of the reference screenshots, neutral grey, ~3 levels warmer down the page. Not black. |
| Spotlight hero | full-bleed art; bottom scrim 260 tall fading **to `#1B1C1C`** — a scrim landing on a colour the page never paints leaves a seam |
| Showcase top | full-bleed backdrop, 100° left scrim `.88 → .66@26% → .18@52% → 0@68%` |
| Showcase scrolled | same backdrop as an **ambient field**: heavy blur, `saturate 1.35`, `scale 1.15`, under a **`.58`** ink veil |

The ambient field is a **bed for white text, not a picture**.

> **Do not `ImageFilter.blur(sigma: 45)`.** Decode the backdrop at
> `memCacheWidth: 32` and scale it up at `FilterQuality.low`. Same
> low-frequency field, effectively free, repaints only on source change.

### 2.3 Geometry (logical)

| Thing | Value |
|---|---|
| Page gutter | 42 |
| Poster | 130×195, gap 20, r7 · **Landscape** 260×146, gap 20, r7 |
| Episode cell | 228 wide, still 216×122, r6, gap 23 |
| Cast circle | 125, gap 26 · **Source card** 280×66, r7 |
| Row title | 13 w600 `white .84`, 10 above the strip |
| Identity | left 42; logo max 235×60, contain, **left-bottom** |
| Chip | h17 r4 pad 3.5/7.5, 9.5 w600 on `black .55` |
| Meta | 10.5 `white .86`; source disc 14; rating box r2.5 |
| Synopsis | 10.5/1.42 `white .74`, max 3 lines |
| Primary | h30 r15 pad 0/17, 10.5 w600; rest `white .22`, **focus solid white on black** |
| Secondary | 26 circle `white .18`, same flip |
| Season pill | h25 r12.5 pad 0/15, 12.5 w600; active `white .18` |
| Dots | 4 / 11×4 active, gap 4.5 |

### 2.4 Caption placement is a rule

- **Inside** the card over a gradient bed on a **poster** or **landscape**.
- **Below** the card on a **16:9 episode cell**.
- The focused episode cell gets a `white .11` r8 plate behind the **whole**
  cell — still and text together.

---

## 3. Architecture

### 3.1 Token additions

**`lib/theme/app_focus.dart`** — a **seventh** `FocusExpression` (there are six
today: ring, scale, lift, invert, flood, underline):

```dart
/// The item lifts, tilts and catches a specular highlight — the tvOS focus
/// effect. Distinct from [lift], which is a rise and a shadow: this adds
/// rotation on a perspective and a moving glare, and is spring-driven rather
/// than curve-driven so a fast traversal keeps its momentum.
parallax,
```

Three more places, or the value silently removes the cursor from every themed
card in the app (round 2 P1 #3):

- the exhaustive **`drawsRing`** switch (`app_focus.dart:83` → `false`);
- both focus-expression mappings in `theme_spec.dart`, including the **focus
  scale** map at `theme_spec.dart:320`, which gives an unknown expression `1`;
- **`FocusExpressionBox`** (`lib/theme/widgets/focus_expression.dart`) gains a
  `parallax` arm that delegates to `ParallaxFocus`. This is not optional
  plumbing — `card_focus_rise.dart:66` and `source_row.dart:264` route through
  it, so without the arm the Spotlight theme leaves those sites with **no
  focus indication at all**. With it, the mechanic reaches the whole app under
  this theme, which is the intent.

  **`parallax` must resolve to `scale: 1`** in the `theme_spec.dart:320` map —
  which the existing wildcard already does, so *add no arm there* (round 3
  P1 #3). `FocusExpressionBox` applies `FocusTokens.scale` after the
  expression (`focus_expression.dart:149`), and the shape-specific
  1.10/1.055/1.08 lives inside `ParallaxFocus`. An arm returning 1.10 would
  double-scale every card.

**`lib/theme/app_motion.dart`** — `MotionCharacter.settle` already means
"slight overshoot, as though the thing has weight". Add:

```dart
/// Stiffness/damping for focus travel. Null on every character but `settle`,
/// whose whole definition is that things have mass — everything else keeps
/// the curve path.
final SpringDescription? focusSpring;
```

`settle` → `withDampingRatio(mass: 1, stiffness: 210, ratio: 0.82)`.

**`MotionTokens.copyWith` MUST carry it.** `ThemeSpec` calls
`MotionTokens.of(motion).copyWith(entrance: entrance)` (`theme_spec.dart:327`);
an unchanged `copyWith` silently drops the spring and the mechanic degrades to
a curve with no error. A test pins this.

**No new geometry tokens.** Caption placement, band order and gutters belong to
the layouts.

### 3.2 `ParallaxFocus` — `lib/theme/widgets/parallax_focus.dart`

```dart
ParallaxFocus({
  required bool focused,
  required Widget child,
  ParallaxShape shape = ParallaxShape.poster,
  BorderRadius? radius,
})
```

**Two widgets, not one** (round 2 P2 #2). `ParallaxFocus` is a *stateless*
selector: it reads the expression and either returns `child` verbatim or mounts
`_ParallaxBody`, the stateful part. Returning `child` from a `State.build` does
**not** avoid that `State`'s controller — the selector is what makes "no
controller under other themes" true rather than aspirational.

**Controller lifetime.** `_ParallaxBody` holds **one** controller for its whole
life (`SingleTickerProviderStateMixin`). An idle `AnimationController` costs
nothing — it only ticks while animating — so "unfocused cards hold no ticker"
(round 0) is replaced by *"unfocused cards hold an idle controller, which does
not tick"*.

**The controller must be `AnimationController.unbounded`.** A bounded
controller clamps at 1.0 and an underdamped `SpringSimulation` would lose
exactly the overshoot the whole mechanic is for.

**Cross-card continuity — what is actually achievable.** Card B's controller
cannot inherit card A's velocity; they are different objects. Round 0 claimed
otherwise and was wrong. Instead, a tiny shared recorder:

```dart
/// The last focus move: when, and which way. A card arriving within
/// [_rapid] of the previous one is mid-traversal, so it gets a larger initial
/// lean and a shorter settle — which is the felt property "holding RIGHT feels
/// continuous", achieved without transferring velocity between objects.
abstract final class ParallaxTravel {
  static const _rapid = Duration(milliseconds: 220);
  static void note(Offset direction);
  static (Offset dir, bool rapid) read();
}
```

`direction` is an `Offset`, not a single int: the spec tilts on **both** axes
and DOWN-arrival must lean differently from RIGHT-arrival.

**The producer is the DPAD handler** (round 2 P1 #8). A boolean `focused`
transition cannot tell you which way focus arrived, so *every* explicit
directional handler in both layouts calls `ParallaxTravel.note(dir)`
**immediately before** `requestFocus()`. A card that gains focus with no recent
note (a tap, an autofocus, a restore) reads `Offset.zero` and simply lifts
without a lean, which is correct.

- Theme read in `didChangeDependencies`; the tick touches only stored doubles.
- `disableAnimations` → jump to the end state (still lifted; reduced motion
  removes the motion, not the state).
- Glare is a `RadialGradient` in a `DecoratedBox` inside the card's
  `ClipRRect`, `BlendMode.screen`. **No `Opacity` widget** — the gradient's own
  stops carry alpha.
- Wrapped in a `RepaintBoundary`, so an animating shadow/gradient cannot
  invalidate the whole rail.

### 3.3 Showcase — `lib/widgets/detail/detail_layout_showcase.dart`

Registered exactly like the other nine: `case 'showcase':` in
`MergedSeriesDetailScreen._buildBody`, wrapped in `themed(...)`, taking
`model` + `episodesHost`.

**Registration is five places, not one** (round 1 P1 #4):

1. `StorageService.kDetailPageStyles` — else the value never stores.
2. `kDetailPageStylesShipped` — else `effectiveDetailPageStyle` resolves it
   away before `_buildBody` sees it.
3. The picker in `detail_page_style_page.dart`.
4. A `_bodySpec` entry — but **`ownScrim: true` is not enough** (round 2
   P1 #1). At `merged_series_detail_screen.dart:882` `ownScrim` *swaps* the
   Classic `.60 → .88` tint for a lighter `.10 → .24` diagonal one; it does
   not remove it. `DetailBodySpec` therefore gains `shellTint` (default
   **`true`**, so every existing layout is untouched), and `false` suppresses
   **both** shell gradients — the diagonal tint at `:877` *and* the accent
   radial at `:908` (round 3 P1 #1). Gating only the first still compounds
   Showcase's own field. The Spotlight `ThemeSpec` additionally sets
   `reactiveRoom: 0`, so the accent wash cannot return by another route.
5. The `_buildBody` case.

**Not universal**: direct-source / Xtream series are forced to Classic before
dispatch (`merged_series_detail_screen.dart:281`). Showcase never sees them,
and that is correct — they have no backdrop pipeline.

#### Bands

| # | Band | Present when |
|---|---|---|
| — | Identity: chip · logo/title · meta · synopsis · tech · **4 buttons** | always |
| — | Seasons | `view.seasons.length > 1` |
| — | Episodes | series |
| — | Cast | `model.cast.isNotEmpty` |
| — | Sources | always |
| — | More Like This | `recommendations.isNotEmpty` |
| — | Details (`detailRows` + awards) | `detailRows.isNotEmpty` |

**Deliberately unnumbered.** Bands are built into a `List<_Band>` at build time
and indexed by position; an absent band leaves no hole. This is the
`_paneNodes` lesson — numbering IS the visual order and must stay contiguous.
**Movies** simply lack Seasons and Episodes, so Sources becomes band 1 with no
special case.

#### The button row

`▶ Play/Resume` · `＋` trackers · `▶|` trailer · `⋯` more — but **"exactly
four" was wrong** (round 1 P1 #3). Every one is independently optional:
`showPrimary`, `hasTrailer`, `onAppMenu`, and the two trackers. The row is
built from whichever are available, in that fixed order, and:

- `model.focus.primaryEntry` attaches to **the first present button**, so the
  page always has a live autofocus target even when Play is hidden
  (PikPak-only) — the same rule `DetailActionRow` already follows.
- Trakt/Simkl leave the row and become **non-focusable readout marks** in the
  meta line, filled when tracked.
- `＋` opens the trackers. Since the sheets are private screen methods, the
  model gains `onTrackers` (§3.4) rather than the layout reaching into them.

#### DPAD contract

| Key | Behaviour |
|---|---|
| DOWN | next band, explicit node. Last band: no-op. |
| UP | previous band. From the identity: `model.focus.backNode`. |
| LEFT | previous column. **At column 0: `model.focus.focusEntry()`** |
| RIGHT | next column. Last column: **no-op** — Showcase has no side pane, so RIGHT is never a pane crossing. |

**LEFT does not open the sidebar** (round 1 P1 #1). The detail page is a pushed
route; the Home shell's directional action is not a dependable ancestor, and
opening a sidebar behind a covering route is wrong anyway. `contentBuilder`
replaces the panel's cells entirely (`episodes_panel.dart:1631`), so Showcase
really does own them and wires `DetailEpisodeInteraction.onLeftEdge` to
`focusEntry()` — never `null`, which would either fall into geometric traversal
or be swallowed by a `DetailEdgeTrap`.

**Only on column 0** (round 2 P2 #1). `DetailEpisodeInteraction` consumes LEFT
whenever `onLeftEdge` is non-null (`detail_episode_cells.dart:155`), so setting
it on every cell would jump to the identity from the middle of the row. Cells
1..n get `null` and move focus normally.

**Landing, honestly** (round 1 P1 #2): `EpisodesPanelView` exposes **no**
paging — seasons publish complete episode lists — so there is no load-more and
none is claimed. `revealDetailLanding` **scrolls only, never moves focus** (its
documented contract). Showcase therefore:

- scrolls `view.landing` into view on `view.generation` change,
- lands *focus* on `primaryEntry` via autofocus,
- honours `EpisodeFocusIntent.seasonControl` by focusing the Seasons band.

#### Scroll

One `ScrollController`; each band's rest offset measured from its own
`GlobalKey`. Recomputed on `generation` change and on metrics change.

### 3.4 `DetailModel` additions

Round 1 P1 #3: the model cannot describe the Sources band or a combined
tracker sheet. Four optional fields, defaulted, so every existing layout and
`catalog_item_detail_screen` compiles untouched:

```dart
/// Bound sources for the Sources band. A SharedPreferences read plus a JSON
/// decode — no network — so the band paints on open.
final List<SeriesSource> boundSources;
final void Function(SeriesSource)? onSourceMenu;
final VoidCallback? onFindSources;
final VoidCallback? onTrackers;                    // combined Trakt+Simkl
```

**There is no per-source host API** (round 2 P1 #7). The only one is the
title-level `onSelectSource(StremioMeta)`. So `onSourceMenu` and
`onFindSources` both open the **existing whole-title source manager**; the
cards are a readout plus one entry point, not a per-row action surface.
Inventing a per-`SeriesSource` bind/unbind/play contract is out of scope.

**The screen must hold the list in state and refresh it.** Merged Detail has no
local source state today — it reads the host's cached *count*
(`merged_series_detail_screen.dart:1002`), and its return-refresh
(`:423`) does not touch sources. Phase 2 adds `_boundSources` state loaded on
init and **reloaded after the source manager closes and on route return**,
or the band goes stale the moment anyone binds anything.

`onTrackers`: both configured → a chooser; one → that service's existing sheet.

### 3.5 Spotlight — `lib/screens/search_screen.dart`

`case 'spotlight': return _buildSpotlightBoard();`, `'spotlight'` in
`kTvHomeStyles`, **and an entry in the Home Layout picker**
(`tv_home_style_page.dart:19`) — a separate closed list, without which the
style cannot be chosen manually and `tvHomeStyleLabel('spotlight')` reports
"Canvas" (round 2 P1 #6).

**The real integration surface** (round 2 P1 #5). `_stageActive` needs **no**
arm — it is already `style != 'classic'`. These do:

| Site | Why |
|---|---|
| `_stageWantsAmbient` | else no ambient art |
| `_stagePublishesShellArt` | else the shell paints nothing |
| `_theaterEligible` | else the trailer never commits |
| `_stageFocusTarget` (`:5155`) | autofocus, sidebar re-entry and dead-focus recovery all route through it and default to *rail* nodes; the hero node is not one |
| `_boardHasFocus` (`:4255`) | must include the hero node, or arrival machinery thinks the board is unfocused while the hero holds focus |
| `_heroTrailerActive` (`:1128`) | style-agnostic, and reschedules from init, section loads and focus changes (`:1322`, `:4045`, `:8109`) |

**The exclusion goes in one place** (round 3 P1 #5). Scheduling reaches
`_scheduleHeroTrailer` (`:8202`) from at least six call sites — init, section
loads, focus changes (`:1322`, `:4045`, `:8109`), `_applyHero` (`:8144`), route
return (`:8431`) and sidebar return (`:8463`) — so a per-site exclusion will
miss one. Put the Spotlight guard **inside `_scheduleHeroTrailer`**, and keep
the existing transition cancellation.

**Do not make `_heroTrailerActive` style-sensitive.** It governs listener
registration and removal across an asynchronously loaded style; gating it
leaks or double-registers listeners.

#### Hero source

**Not `_stageRails[0]`** (round 1 P1 #5): `_canvasRails` is ordered Continue
Watching → Favourites (including IPTV/channels, which are not `StremioMeta`) →
catalog sections, and it re-orders as tracker data lands. A dedicated getter
instead:

```dart
/// The hero reel: the first rail that yields real catalog items, capped at 8.
/// Parked position is restored by ITEM ID, never by index, because the rail
/// list re-orders when tracker data arrives.
List<StremioMeta> get _spotlightHero
```

#### Hero behaviour

- Hero is **the first item of the scroll**; hero and shelves translate together
  over the flat ground. The scrolled page shows **no artwork**.
- LEFT/RIGHT page it, dots show position, it **parks**.
- Identity flips to the **right edge** when the backdrop's left third is busy —
  one luminance probe per item, cached by URL, threshold 0.32.
- **Text-title fallback** when logo art is missing *or* below 0.30 luminance.
  Metahub ships black wordmarks: ~1 title in 4, not an edge case.

#### The trailer state machine

```
art (4s) ──▶ trailer (20s cap) ──▶ advance ──▶ art (next item)
 ▲                                                │
 └──────────── LEFT/RIGHT: cancel, restart ───────┘
```

**Timer-capped, not completion-driven** (round 1 P1 #6): `HeroTrailerBackdrop`
opens trailers with `loop: !live` and exposes no completion, position or
duration callback. Extending its API is out of scope, so the machine advances
on its own timer and the trailer simply loops until it does.

Spotlight **isolates itself from the existing hero-swap and trailer timers**
rather than racing them — those are cancelled for the duration of the board.

- DOWN out of the hero: stop, **freeze**. UP: resume at `art` on the parked
  item.
- `IdleDim.suspend(owner)` on trailer start, **`resume(owner)` on every exit
  path**: completion, failure, DOWN, manual paging, route cover, style change,
  dispose. An unpaired suspend is a permanent idle hold.
- `disableAnimations` or `home_hero_trailer_enabled == false` → `art → advance`
  at the same cadence, no trailer.
- The identity must not gain a **saveLayer ancestor** over the punch hole; it
  fades as a **sibling above** the video, which is what the shipped hero
  already does.

**Layouts do not read `TvSidebarNav.contentInsetFor`** (round 1 P2 #3): the TV
shell already applies the inset once around all content, so reading it inside a
board would double-inset every non-pill style.

### 3.6 The Look — use the system that exists

Round 1 P1 #7: `AppLook`, `LookKeys` and `LookApplier` already implement
"a Look writes the prefs" (`lib/theme/app_looks.dart`). Round 0 invented a
second architecture; deleted. Add one `AppLook`:

| Key | Value |
|---|---|
| `app_theme` | `spotlight` |
| `tv_home_style` | `spotlight` |
| `detail_page_style` | `showcase` |
| `tv_sidebar_style` | `pill` |

`LookKeys.appTheme.write` goes through `AppThemeController.select`, which
**also writes `detail_theme`** — so this mutates five preferences, not four.
That is the controller's write-through contract and is correct; the Look must
not try to write `detail_theme` itself.

**Registering the theme id takes four places**, not two (round 2 P1 #2):

1. `StorageService.kDetailThemes` — `select` normalises anything else to Legacy.
2. `kDetailThemesShipped` — `AppLooks.validate` rejects Looks naming withheld
   themes.
3. **`PremiumLooks.all`** (`premium_looks.dart:203`) — resolution goes through
   `PremiumLooks.byId` (`app_theme_controller.dart:162`); a spec that is not in
   the registry falls back to **Signal** (`detail_themes.dart:875`) and the
   Look silently renders the wrong palette.
4. `test/theme/premium_vocabulary_test.dart` pins the five-look set in **four**
   places, not one (round 3 P1 #4): both count assertions at `:260`,
   `ids.take(5)` at `:544`, and the exhaustive `expected` / `derived` snapshot
   maps at `:626` and `:644`. Adding Spotlight to `PremiumLooks.all` without
   entries in those maps is a null-check failure, not a count mismatch.

The `ThemeSpec` must also supply the **required** `label`, `subtitle`, `scrim`
and `frame` (`theme_spec.dart:133`), which round 2 omitted — it was not
constructible as written (round 3 P1 #2):

```dart
label: 'Spotlight', subtitle: 'Full-bleed art, borderless focus, ambient detail',
scrim: ScrimStyle.gradient, frame: ArtFrame.bleed, reactiveRoom: 0,
```

**`select` must stop early-returning on the id alone** (round 2 P1 #4).
`app_theme_controller.dart:107` returns when `normalized == _id`, so this
sequence leaves the Look half-applied: apply Spotlight → change Details Theme
by hand → apply Spotlight again → the app theme matches, `select` returns, and
`detail_theme` is never repaired. Fix: early-return only when the app theme
**and** its mirror already match the target. Legacy keeps its documented
behaviour of writing no mirror.

`ThemeSpec spotlight`: ground `#1B1C1C`, sunken `#151616`, raised `#242525`,
ink `#FFFFFF`, accent `#FFFFFF`, `separation: fill`, `focusExpression:
parallax`, `motion: settle`, `entrance: fadeUp`, `idle: dimChrome`, `radius: 7`,
`accentButton: true`, `artworkAccent: false`.

**`AppLook.isActive` needs a mirror check** (round 3 P1 #6). It compares only
its four named keys (`app_looks.dart:201`) and never the controller-owned
`detail_theme`. So: apply Spotlight → change Details Theme by hand → the Look
still reports **active** while rendering a different palette. Add a
**detection-only** mirror comparison for non-legacy app themes; it changes what
`isActive` reports, never what `apply` writes.

**No Undo.** `LookApplier` snapshots generations, not values, and a correct
undo would have to restore `detail_theme` too and reason about `select`'s
early-return. Out of scope; the individual pickers remain the escape hatch,
the same contract every other Look already has.

### 3.7 Corrections to round 0's stated facts

- The coerced default is **`canvas`** for home and **`console`** for detail —
  not `classic`. Round 0 asserted otherwise and was wrong.
- `FocusExpression` gains a **seventh** value, not a fifth.

---

## 4. Phases

Each phase ends with three gates and a codex review.

1. **`flutter analyze`** from the repo root, clean of new errors/warnings.
   (`dart analyze lib/ test/` takes only one directory — round 2 P2 #3.)
2. **`python3 tool/test_baseline.py`** — runs the suite and diffs the failing
   set against `test/known_failures.txt` **by `suite::test name`**. It **fails
   closed**: a run that dies before emitting events has an empty failure set,
   which would compare clean against any baseline, so a nonzero exit with
   nothing parsed is a hard error (round 4 P1). Verified both ways — a
   deliberately broken suite exits 1 naming the file, a clean tree exits 0. A count
   gate passes when a regression replaces a repaired failure, and "7 failures
   in `series_parser_test.dart`" passes even if they are seven *different*
   ones (round 3 P2 #1). The baseline holds the nine exact names; exit 1 lists
   the delta in both directions.

3. **The phase's own tests**, listed below.

**Phase 1 — Foundation.** `FocusExpression.parallax` (+ `drawsRing` +
`theme_spec` mappings), `MotionTokens.focusSpring` (+ `copyWith`),
`ParallaxFocus`, `ParallaxTravel`, and the shared primitives: `SpotlightCard`,
`ShowcaseEpisodeCell`, `CastCircle`, `SourceCard`, `IdentityStack`,
`PillButton`/`CircleButton`, `SeasonPills`, `PageDots`.
*Tests*: `copyWith` carries the spring; non-parallax themes add no controller;
`disableAnimations` lands on the end state; rapid traversal leans harder;
legacy untouched.

**Phase 2 — Showcase.** Layout, band list, DPAD map, ambient dissolve, sticky
logo, Sources band, tracker marks, button row; `DetailModel` additions; all
five registration points.
*Tests*: every band reachable in visual order, series **and** movie; absent
bands leave no hole; LEFT at column 0 → `focusEntry` and **only** column 0;
RIGHT never crosses; `focusIntent`/`landing` honoured; **`shellTint: false`
suppresses both shell gradients** and every other layout still gets them.

**Phase 3 — Spotlight.** Board, carousel, luminance probe, text-title fallback,
trailer machine, flat ground, and the full integration surface of §3.5: three
policy switches (`_stageWantsAmbient`, `_stagePublishesShellArt`,
`_theaterEligible`), two focus integrations (`_stageFocusTarget`,
`_boardHasFocus`), the board dispatch, the picker entry, and the single
`_scheduleHeroTrailer` exclusion. "Four stage gates" (round 2) understated it.
*Tests*: hero parks by id across a rail re-order; DOWN freezes; identity flips
on a bright left third; text fallback on a dark wordmark; every trailer exit
path resumes `IdleDim`; no saveLayer ancestor over the punch hole.

**Phase 4 — The Look.** `ThemeSpec spotlight`, `kDetailThemes` +
`kDetailThemesShipped`, the `AppLook`, the Presets entry.
*Tests*: apply writes all four keys and `detail_theme` follows; `validate()`
passes; a manual change afterwards sticks; and the regression sequence in full
— apply Spotlight → change `detail_theme` by hand → `isActive` reports Custom
→ reapply Spotlight → the mirror is repaired.

**Phase 5 — Fidelity.** A cross-renderer pixel diff between Chrome and Flutter
is fake precision (round 2 P2 #4), so fidelity is checked three ways instead:

1. **A spec test.** `test/theme/spotlight_spec_test.dart` asserts the geometry
   and focus constants in the Dart source equal the §2 tables. The mock's
   numbers become executable, and drift fails a test rather than an eyeball.
2. **Flutter goldens** for both layouts at 960×540 with a fixed fixture — a
   self-consistent regression net, not a comparison against the HTML.
3. **A device pass** on the Apple TV against the mock side by side.

States covered: episode watched veil / progress / UP NEXT, loading skeletons,
empty sources, unavailable season, IMDb failure (no cast band), large text
scale, reduced motion, both layouts. Then the final codex review.

---

## 5. Risks

| Risk | Mitigation |
|---|---|
| Per-card controller cost | idle controllers do not tick; non-parallax themes build none |
| Ambient blur cost | 32px decode scaled up, not a real Gaussian |
| Band index drift | bands are a list indexed by position |
| Episodes engine | consumed via `EpisodesPanelView` unchanged; never forked |
| Trailer/carousel race | one timer; the existing hero timers are cancelled, not raced |
| Unpaired `IdleDim.suspend` | a single `_endTrailer()` funnel owns every exit |
| Text scale | no fixed-height text boxes; bands size to content |
| Legacy regression | Phase 5 diffs the existing layouts under a non-legacy theme too, since `copyWith`/`ThemeSpec` are shared |

---

## 6. Out of scope

Ranked shelves, curated editorial rows, Dolby/CC technical badges (nothing is
fetched at page open, so they cannot be honest), Look undo, and any change to
`HeroTrailerBackdrop`'s public API.

---

## 7. Round-1 review — what changed

| # | Was | Now |
|---|---|---|
| P1-1 | LEFT falls through to the sidebar | `focusEntry()`; pushed route has no sidebar |
| P1-2 | landing focus + load-more | scroll-only landing; **no** pagination exists |
| P1-3 | model already supports Sources/trackers | four optional `DetailModel` fields |
| P1-4 | register one switch case | five places incl. `ownScrim` and `…Shipped` |
| P1-5 | hero = `_stageRails[0]` | dedicated getter; four stage gates |
| P1-6 | trailer completion drives advance | timer cap; existing timers cancelled |
| P1-7 | new `LookPreset` type | the existing `AppLook`/`LookApplier` |
| P1-8 | `ThemeSpec` alone registers a theme | `kDetailThemes` + `kDetailThemesShipped`, `copyWith` |
| P1-9 | velocity carries between cards | `ParallaxTravel` rapid-traversal hint; both axes |
| P2-1 | default is `classic` | `canvas` / `console` |
| P2-2 | "no clip over the hole" | no **saveLayer ancestor**; siblings and hard clips fine |
| P2-3 | layouts read `contentInsetFor` | the shell already insets once |
| P2-4 | fifth `FocusExpression` | seventh; `drawsRing` + mappings |
| P2-5 | — | `RepaintBoundary` required |
| P2-6 | — | Phase 5 checks existing layouts under a non-legacy theme |

### Round 2

| # | Was | Now |
|---|---|---|
| P1-1 | `ownScrim: true` gives Showcase the scrim | it only *swaps* tints; new `shellTint: false` mode |
| P1-2 | two lists register a theme | four, incl. `PremiumLooks.all` and the pinned vocabulary test |
| P1-3 | new `FocusExpression` is self-contained | `FocusExpressionBox` needs a `parallax` arm or themed cards lose their cursor |
| P1-4 | `select` writes the mirror | it early-returns on the id alone; must compare the mirror too |
| P1-5 | four stage gates | `_stageActive` needs none; `_stageFocusTarget`, `_boardHasFocus` and every `_heroTrailerActive` scheduling entry do |
| P1-6 | — | the Home Layout picker is a separate closed list |
| P1-7 | model exposes per-source actions | no such host API; cards open the title-level manager, and the screen must hold + refresh the list |
| P1-8 | `ParallaxTravel` exists | it had no producer; the DPAD handlers note direction before `requestFocus` |
| P2-1 | `onLeftEdge` on every cell | column 0 only, else LEFT jumps from mid-row |
| P2-2 | one stateful widget | stateless selector + stateful body; **unbounded** controller or the overshoot clamps |
| P2-3 | `dart analyze lib/ test/` | `flutter analyze` from root; failures compared by name |
| P2-4 | 1:1 screenshot diff | spec test + Flutter goldens + device pass |

### Round 3

| # | Was | Now |
|---|---|---|
| P1-1 | `shellTint:false` hides the tint | must hide the accent radial at `:908` too; `reactiveRoom: 0` |
| P1-2 | `ThemeSpec spotlight` as listed | it lacked required `label`/`subtitle`/`scrim`/`frame` |
| P1-3 | add a parallax arm to the focus-scale map | leave the wildcard `1`; an arm double-scales |
| P1-4 | one test pins five looks | four pins: `:260` ×2, `:544`, `:626`/`:644` snapshot maps |
| P1-5 | exclude Spotlight per call site | one guard in `_scheduleHeroTrailer`; `_heroTrailerActive` stays style-blind |
| P1-6 | `isActive` is fine | it ignores `detail_theme`; add a detection-only mirror check |
| P2-1 | nine failures by filename | `tool/test_baseline.py` + `test/known_failures.txt`, by `suite::name` |
| P2-2 | "four stage gates" | the full surface: 3 switches, 2 focus integrations, dispatch, picker, trailer guard |

### Round 4

| # | Was | Now |
|---|---|---|
| P1-1 | `tool/test_baseline.py` gates the suite | it **failed open**: a compile error produced an empty failure set and reported clean. Now a nonzero exit with no parsed failures raises, and `--record` cannot erase the baseline from a dead run. |


---

## 8. Status — end of the first build session

### Landed and gated (uncommitted)

**Phase 1 — Foundation. Complete.**
`FocusExpression.parallax` (+ `drawsRing`, `FocusExpressionBox` arm),
`MotionTokens.focusSpring` + `kSettleFocusSpring` + `copyWith`,
`ParallaxFocus` / `ParallaxTravel` / `_ParallaxBody`.
**20 tests.** Codex round found 3 P1s, all fixed:
- rapid-traversal detection measured note→focus (always ~0) instead of the gap
  between moves, so the gentle lean was unreachable;
- the tilt came off a positive-only curve over the controller's *position*, so
  it pulsed one way instead of swinging through neutral — it now rides the
  spring's **velocity**, which reverses on the rebound;
- reduced motion switched on mid-flight did not stop the running spring.
A fourth defect surfaced in testing: the spring settled ~2% off its target,
leaving focused cards permanently oversized. Now snapped on completion.

**Phase 2 — Showcase. Built, gated, not yet seen on a panel.**
`detail_layout_showcase.dart` + `showcase_parts.dart`, registered in all five
places, `DetailBodySpec.shellTint` suppressing **both** shell gradients,
`DetailModel.boundSources/onTrackers/onManageSources`, `_loadBoundSources`.
**7 tests.** Codex round found 6 P1s; the five that made it non-functional are
fixed:
- it mounted its own primary node instead of `focus.primaryEntry`, which broke
  LEFT, trailer restoration and autofocus;
- the band list was built from a cached view, one frame stale;
- the focused band was tracked by INDEX, so Cast arriving asynchronously
  shifted every band below it;
- lazy horizontal rails had no scroll-into-view, so walking a rail stalled at
  the first unmounted node;
- **nothing had OK activation** — `GestureDetector.onTap` never fires for a
  remote, so every circle button, source card and poster was inert;
- `onTrackers` was always non-null, mounting a dead `+`.

**Phase 3 — Spotlight. Built, gated, not yet seen on a panel.**
`lib/widgets/home/spotlight_board.dart` — a self-contained board with its own
DPAD, so it is testable without standing up the 23k-line home screen. Wired
into `search_screen.dart`: `kTvHomeStyles`, the picker, the board dispatch,
`_stageWantsAmbient` / `_stagePublishesShellArt` / `_theaterEligible`,
`_stageFocusTarget` (the hero is a focus target the rail lists cannot
describe), `_boardHasFocus`, and the single `_scheduleHeroTrailer` guard.
Hero source is a dedicated getter over `_sections`, **not** `_stageRails[0]`.
**4 tests**: parks by item id across a reel re-order, falls back to the head
when the parked title disappears, LEFT at column 0 falls through so the
sidebar stays reachable, and a one-item reel draws no dots.

**Phase 4 — the Look. Done. The mechanic is now live.**
`PremiumLooks.spotlight` (registered in `all`, `kDetailThemes` and
`kDetailThemesShipped`), the `spotlight` `AppLook`, and two contract fixes the
review demanded:
- `AppThemeController.select` compared only the app-theme id, so applying the
  Look after a hand-changed Details Theme returned early and never repaired
  the mirror. It now compares **both**.
- `AppLook.isActive` never checked the controller-owned mirror, so a Look
  reported itself active while rendering a different palette. Detection-only
  check added; `apply` still never writes the mirror itself.
The four pinned five-look assertions in `premium_vocabulary_test.dart` are
updated to be length-derived rather than hardcoded, so the seventh look will
not repeat this.
**6 tests**, including the full regression sequence: apply → change the mirror
by hand → reads Custom → re-apply → mirror repaired.

**Appearance → Presets → Spotlight** now sets theme, both layouts and the
sidebar in one action, and `FocusExpression.parallax` has a consumer for the
first time.

**Phase 5 — partly done.**
`test/theme/spotlight_spec_test.dart` makes the mock's numbers executable: the
per-shape lifts, the spring's ζ, the measured grounds, and — in the other
direction — it **greps the mock's own source**, so retuning the HTML without
retuning the Dart fails a test. A Chrome-vs-Flutter pixel diff was rejected as
fake precision.

Also landed since the Phase-3 review:
- Showcase's `_Band.rest` is finally **read**; every reveal used `alignment: 0`
  and parked each band hard under the sticky logo with no sight of the row
  above.
- `view.loading` / `view.unavailable` / `onRetry` are consumed — a failed
  episode load was previously indistinguishable from a movie, with no way back.
- The **Details band** (`detailRows` + awards) exists, as an unfocusable footer.
- Spotlight has its **hero cadence**: `art (4s) → advance`, frozen while focus
  is off the hero, restarted by manual paging. One timer, one owner.
- Spotlight pagination: shelf load-more four cards from the end, and a batch
  request when DOWN runs out of shelves.

### Still open — and how to finish each

**1. No video in the hero.** The cadence is built, focus-gated and capped at
20s, and the board paints whatever `trailer` widget it is handed. What is
missing is the host end.

The seam is deliberate: `_scheduleHeroTrailer` is blanket-excluded for this
style so two schedulers cannot start a trailer under the wrong title. The
finish is **not** to remove that guard — it is to add a Spotlight-only entry
that bypasses the style check, called from `onDwell`, so the board stays the
single owner of the clock while the existing resolve→`HeroTrailerBackdrop`
chain does the video. Then pass that backdrop in as `trailer:` and set
`trailersEnabled: _heroTrailerEnabled && !_heroTrailerSuppressed`.
Roughly half a day, mostly in `search_screen.dart`.

**2. Continue Watching and favourites are not Spotlight shelves.** The board
takes `List<CatalogSection>`; CW and favourites are neither that shape nor
that card (they carry progress, a context menu, and non-`StremioMeta` entries
for IPTV). Guarded, not fixed: with no catalog sections at all it falls back
to classic rather than rendering a blank unfocusable board. Finishing it means
a small shelf-descriptor type the board consumes instead of `CatalogSection`.

**3. Not done:** goldens, the large-text pass, reduced motion end-to-end.

**4. Neither layout has rendered on a panel.** The only check that settles
"identical to the mock", and the one thing that cannot be done from here.

### Spotlight's own gaps

| Gap | Why it matters |
|---|---|
| **No trailer state machine** | the hero shows art and never rolls a trailer. The old scheduler is correctly excluded, but nothing replaces it — this is the `art → trailer → advance` machine from §3.5, unbuilt |
| **No auto-advance** | the carousel only pages on LEFT/RIGHT |
| Left-third probe uses the dominant colour's luminance | a proxy for "is the left third busy", not a measurement of that third |
| **Continue Watching and favourites rows are dropped** | Spotlight passes only catalog `_sections`. Mitigated, not fixed: with no catalog sections it now **falls back to classic** rather than rendering a blank unfocusable board, but CW and favourites still do not appear as shelves |
| **Neither pagination path is connected** | DOWN at the last shelf loads no further board batch, and poster focus never calls `_loadMoreRow` — only the first eight shelves and each shelf's first page are reachable |
| Dark-logo fallback is not implemented here | `_LogoOrTitle` falls back on a missing/failed URL only; it never measures logo luminance, so a black wordmark is invisible. Showcase has the same gap |

Codex reviewed Phase 3 and raised 5 P1s. Four are fixed — the hero could not
be **activated at all** (arrows paged it, OK did nothing), ambient art/tint
published **stale** when paging A→B→A because the cache short-circuited the
publish, a slow probe could overwrite a newer hero's colour, and the hero node
leaked. The two structural P1s above (CW rows, pagination) are **not** fixed
and are the first thing to pick up.

### Known gaps in Showcase (codex P2s, deliberately not yet fixed)

| Gap | Why it matters |
|---|---|
| `_Band.rest` is unused — every reveal aligns to 0 | bands sit at the very top under the sticky logo instead of their declared 110–165 offset |
| `view.loading` / `unavailable` / `onRetry` unconsumed | a failed episode load shows as bands silently vanishing, with no retry |
| The Details band (`detailRows` + awards) is not built | promised in §3.3, absent |
| Fixed band heights | overflow at ~2× text scale |
| TV backdrop decodes at 96px (`hero_trailer_backdrop.dart:795`) | pre-existing, but `shellTint: false` stops hiding it — the full-bleed top may look soft on a panel |
| Two full-screen opacity layers animate on every band change | against the TV cost budget; wants a cheaper dissolve |
