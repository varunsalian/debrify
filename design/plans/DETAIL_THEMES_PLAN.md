# Detail page themes — twenty looks over one layout system

The four alternate layouts differ in **where things are**. They do not differ in
**what things feel like** — same gold, same pills, same rings — so they read as
one product with the furniture moved. This adds the missing layer: a theme,
chosen in **Appearance → Details Theme**, that restyles whichever layout is
active.

Mock: `detail_themes_mockup/`, artifact
https://claude.ai/code/artifact/60c2f44f-0af7-415c-ad6b-066b459ef3d3

> **Revised after codex rounds 1 and 2** (9 P1s). Round 1 killed the original
> premise; round 2 found that the shell estimate was *still* wrong, that a
> shared widget outside `lib/widgets/detail` is rendered by two layouts, that
> the scope arrived after its consumers, and that goldens are unworkable here.
> Review stopped after round 2 — the findings had become concrete and local.
>
> **Round 1's headline:** Draft 1
> claimed this cost "one wrap plus one line" in the shell. It does not: the
> tint, the ambient still, the per-title accent wash, the back button and the
> trailer chip all live outside `_buildBody`, and an opaque body ground would
> hide the artwork that Marquee and Stage exist to show. The shell **is**
> themed, through one derived object, and §0 is now about coordinating that
> edit rather than pretending to avoid it.

---

## 0. Working constraint — a parallel session owns two files

Another session is editing `lib/screens/merged_series_detail_screen.dart` and
`lib/screens/settings_screen.dart`.

| File | Change | Conflict risk |
|---|---|---|
| `merged_series_detail_screen.dart` | Scope insert; tint/ink/wash read a derived `DetailShellStyle`; `_accent` gains a theme policy; **and the private `_RoundIconButton` (back) and `_TrailerPlayingChip` gain optional style parameters** — their fill, forced `CircleBorder`, border, icon colour and halo are hardcoded inside them, so a square theme cannot use them as-is. Realistically **60–90 lines across `build`, `_bodySpec` and two private widgets** — not the 25 draft 2 claimed. | **Real and larger than hoped.** Land as its own step; re-check the file immediately before starting. |
| `lib/widgets/parents_guide_section.dart` | Optional theme parameter. Rendered by Dossier and Stage; its white text, white surfaces, fixed radii and `HomeTheme.focusGold` are unreadable under Broadsheet and Concrete. `maybeOf` fallback keeps Classic and every other caller exactly as they are. | Low — additive parameter. |
| `settings_screen.dart` | The additive row pattern the layout picker already used. | Low, mechanical. |
| `settings/settings_tv_layout.dart` | One field + one row. | Low. |
| `main.dart` | One guarded `getDetailTheme()` warm beside `getDetailPageStyle()`. | Low. |
| `lib/widgets/detail/*`, new files | Everything else. | None. |

---

## 1. What ships

Twenty themes, all from the mock. `signal` is the default and reproduces
today's look exactly, so nothing changes until a user opts in.

**Concept set** — Signal Gold, Noir, Broadsheet, Phosphor, Aurora, Concrete,
Velvet, Blueprint, Broadcast, Sepia.
**Premium/OTT set** — Obsidian, Halo, Prestige, Deep Field, Graphite, Vault,
Spectrum, Verdant, Frost, Cinemascope.

Grounds: **Broadsheet and Concrete are light**; Frost is a *dark* blue-grey with
translucent surfaces (draft 1 wrongly called it light); the rest are dark.

---

## 2. Non-negotiables

1. **Classic is not themed** — it keeps its own private widgets. The picker says
   so.
2. **`signal` must reproduce today's look exactly**, verified by the harness,
   the literal guard and the token-resolution tests in §5 — not asserted, and
   not by goldens, which this repo cannot support (§5).
3. **No focus-graph change.** Callbacks, edge traps and key handlers are not
   touched — but see §2a: this is *not* the same as "no layout change".
4. **TV cost budget.** No per-frame `saveLayer`: grain and blur shadows both
   degrade on TV (§3.6).
5. **A theme can never hide the cursor** — TV focus floor (§3.6).
6. **A theme never recolours a third party's mark** — IMDb, Trakt and Simkl keep
   their brand colours.

### 2a. This is not "paint only"

Display sizes run 18px→31px, families change, tracking changes, button weights
and borders change. That moves text wrapping, scroll extents and therefore
**focus-node rectangles**, which is what directional traversal is computed from.
The focus *graph* is unchanged; the *geometry* is not. Every theme needs an
overflow + traversal check (§5).

---

## 3. Architecture

### 3.1 Colour roles

Five, not three. Draft 1 collapsed roles that the mock keeps apart.

| Role | Means | Sites |
|---|---|---|
| `accent` | identity / brand | eyebrows, section flourishes |
| `state` | computed progress | watched tick, progress fill + %, bound-source pill |
| `callout` + `calloutText` | an attention flag, not a measurement | UP NEXT (foreground is its own token), CONTINUE WATCHING |
| `award` | immutable metadata highlight | awards pill |
| `rating` | data, not state | the episode ★ |
| `focus` | the DPAD cursor | rings, tab underline, sheet radio, pane border |

`callout`, `award` and `rating` exist because codex was right that folding them
into `state` is a *choice*, not a fact. Signal sets all of `state`, `callout`
and `award` to the same gold, so **Signal is unchanged**; other themes may split
them.

Fixed, never themed: the IMDb badge, `kTraktRed`, `kSimklCyan`.

### 3.2 The per-title accent problem

`_accent` is extracted from the poster and drives the shell wash, the Dossier
and Console eyebrows and the Play glow. A fixed-palette theme (Noir's white,
Phosphor's amber) is contaminated by it; removing it breaks Signal.

```dart
final bool useArtworkAccent;   // Signal: true. Fixed-palette themes: false.
```

The screen passes `theme.useArtworkAccent ? _accent : theme.accent` into
`DetailModel.accent`. Shell wash opacity becomes `theme.washOpacity` (Signal
0.16, fixed-palette themes 0).

### 3.2a Signal's complete mapping — pinned

Ambiguity here is how "Signal is unchanged" quietly stops being true. Every
role's Signal value, from today's code:

| Token | Signal value |
|---|---|
| `useArtworkAccent` | **true** (the poster-extracted `_accent`) |
| `washOpacity` | 0.16 |
| `state` · `callout` · `award` | `0xFFF5B942` — all three the same gold today |
| `calloutText` | `0xFF2A1E02` (the UP NEXT foreground) |
| `rating` | `0xFFF5C518` — IMDb yellow, *not* the state gold |
| `focus` | `0xFFFBBF24`, width **2.5**, **in-bounds** foreground border |
| `ground` · `pane` | `0xFF0B0B0E` · `0xFF0E0B14` |

The focus placement matters: the mock uses an outward `outline-offset`; today's
app draws an in-bounds foreground border. Signal keeps **in-bounds**.

### 3.3 The token object

`lib/widgets/detail/theme/detail_theme.dart` — beyond the roles above:

```
grounds     ground pane railBg panel hair
washes      paneWash railWash idWash        (Gradient?, null = flat)
text        tx tx2 tx3
shape       radius radiusSm radiusBtn radiusImg radiusCast
type        displayFont bodyFont dataFont           ← dataFont was missing:
                                                     the mock's --f-data drives
                                                     eyebrows, meta, episode
                                                     data, slabs, severity
            displayWeight displayUpper
            displayTracking displaySize
            slabSize slabTracking slabWeight            ← slabSize was missing
controls    btnFill btnText btnWeight btnGradient
            btnBorder btnBorderWidth                    ← Vault/Blueprint/Scope
            ghostFill ghostBorder ghostText
focus       focusWidth focusOffset                      ← Broadcast wants 0
surface     shadow  dividerGradient  grain  grid
ground kind lightGround  washOpacity  useArtworkAccent
```

**Font weights snap to the nine legal `FontWeight` values.** The mock's CSS 750
and 780 become `w700`/`w800`; noted so nobody "fixes" the discrepancy later.

**Spectrum**: the mock promises a duotone gradient but supplies a flat state
colour. Decided here — Spectrum's *progress bar* uses `stateGradient`; ticks and
text use flat `state`. `stateGradient` is nullable and null everywhere else.

### 3.4 Scope

```dart
class DetailThemeScope extends InheritedWidget {
  final DetailTheme theme;
  @override bool updateShouldNotify(DetailThemeScope old) => old.theme != theme;

  /// Asserts in debug when absent — a missing scope is a migration bug, and a
  /// silent Signal fallback would make it look correct.
  static DetailTheme of(BuildContext c) { … assert … }
  static DetailTheme maybeOf(BuildContext c) => … ?? DetailThemes.signal;
}
```

`DetailTheme` needs `==`/`hashCode` for `updateShouldNotify` to mean anything.

**Sheets do not inherit it.** Audited:

| Sheet | Owner | v1 |
|---|---|---|
| season picker | this work (`detail_identity.dart:790`) | **themed** — takes the theme as a parameter |
| App actions / Trakt / Simkl | the shell, shared with Classic | **not themed** — deliberate |
| episode options | `EpisodesPanel`, shared with Classic | **not themed** — deliberate |

Theming the last four means restyling code Classic also renders. Out of scope,
documented, revisit after this lands. `maybeOf` exists for exactly these.

### 3.5 The real size of the refactor

It is **not** the 107 `DetailPalette` references. Every presentational literal in
the seven files has to be routed through a token — `Colors.white`, the
`0xFFF6F5F0` primary fill, `Color(0xFF1A1622)` image placeholders, hardcoded
radii, and the title `TextStyle`s. Without that pass, Broadsheet and Concrete
render **white text on a light ground**.

Method: `DefaultTextStyle` + `IconTheme` at the layout root give a themed
baseline, then every explicit literal is replaced. The audit is the step, not a
side effect of it.

### 3.6 Rules a theme cannot break

```dart
double focusWidthFor(bool tv) => tv ? math.max(focusWidth, 2.5) : focusWidth;
double grainFor(bool tv)      => tv ? 0 : grain;

/// Aurora 40px, Deep Field 30px and Frost 44px blur shadows repaint on every
/// focus move. On TV they collapse to a hard offset or nothing.
List<BoxShadow> shadowFor(bool tv) => tv
    ? [for (final s in shadow) if (s.blurRadius <= 6) s]
    : shadow;
```

Static gradient and grid layers get a `RepaintBoundary` so a focus repaint does
not re-rasterise them.

### 3.7 The pref

Mirrors `detail_page_style` exactly (`storage_service.dart:680`): whitelist,
sync-cached, coerced both directions, plus `effectiveDetailTheme` narrowed
against a shipped set — **and warmed in `main.dart` beside
`getDetailPageStyle()`**, or a non-Signal choice does not survive a cold start.

---

## 4. Steps

| # | Step | Verify |
|---|---|---|
| 1 | `DetailTheme` + five roles + `==` + scope + twenty definitions | every id ↔ definition; **Signal equals §3.2a exactly** |
| 2 | Pref + `effectiveDetailTheme` + `main.dart` warm + picker | coercion both ways; cold-start with a stored non-Signal value |
| 3 | **Scope insert FIRST**, then the literal audit + refactor of `detail_style` / `detail_identity` / `detail_episode_cells` / the four layouts / the season picker — **atomically**, because an asserting `of()` fails the moment a consumer exists without a provider | harness (§5) under Signal |
| 4 | `parents_guide_section.dart` optional theme param (`maybeOf`, so Classic is untouched) | Classic renders identically |
| 5 | Shell: `DetailShellStyle`, `_RoundIconButton` + `_TrailerPlayingChip` params, accent policy, light ground | harness under Signal; trailer promote/dismiss still works |
| 6 | Settings wiring (phone + TV + search) | analyze; row present on both |
| 7 | Per-theme overflow + traversal pass at 960×540 and phone portrait | no overflow; back reachable under every theme |
| 8 | Full sweep + final codex review | analyze 0 errors; tests ≥ 877/8 baseline |

Steps 3 and 4 of draft 2 are merged: the scope must exist before the first
consumer, or debug asserts fire.

---

## 5. Verification — goldens are out

**This repo has zero golden tests** across 877, so there is no harness, no
comparator convention and no baseline discipline. Worse, a full-route golden
cannot even be constructed: a fake `seasonsLoader` forces the screen back to
Classic, and without one the live episode engine runs. Standing that up is new,
flaky scope to prove a claim that can be proved more cheaply.

What replaces it:

1. **A component harness.** `EpisodesPanelView` is a plain value object this
   work already owns, so each layout can be rendered against a *synthetic* one —
   no engine, no network. Fixed surface size, DPR 1, fixed text scale,
   animations settled, `errorWidget` placeholders for images (the test
   `HttpClient` fails every request deterministically, which is a feature here).
2. **A source-literal guard test.** Reads the themed files and fails on any raw
   colour literal outside the definitions file. This directly targets the
   biggest P1 — a literal that never got routed — and keeps targeting it for
   whoever adds a widget next year. A golden would only catch it if the missed
   literal happened to land in a golden'd region.
3. **Token-resolution tests.** Pump each layout under Signal and assert the
   focus ring, progress fill, tick, awards pill and rating resolve to the exact
   values in §3.2a.
4. **The TV rules are pure functions** taking `isTv` as a parameter, so they are
   unit-testable directly — which matters because `PlatformUtil.isAndroidTvCached`
   has no test seam.
5. **Overflow + traversal per theme** (step 7): §2a means type changes move
   focus rectangles. Dossier's fixed card, Console's top strip and every wrapped
   action row are where to look.
6. **A device pass.** Screenshots have found more real defects in this work than
   any test has; that is not an argument against tests, but it is the honest
   ranking of what catches what.

---

## 6. Known traps

1. `gold` means four things today — split into state / callout / award / rating.
2. The per-title artwork accent fights fixed-palette themes (§3.2).
3. Modal sheets do not inherit the scope; four are deliberately unthemed.
4. Hardcoded literals outside `DetailPalette` are the bulk of the work (§3.5).
5. `BlendMode` and blur are per-frame saveLayers — grain and big shadows off on TV.
6. A theme must not be able to hide the cursor.
7. Light themes need the shell's ground, not just the body's.
8. `FontWeight` has nine legal values; the mock's 750/780 snap to 700/800.
9. `InheritedWidget` without `updateShouldNotify` never rebuilds dependents.
11. The scope must exist before any consumer calls the asserting `of()`.
12. `ParentsGuideSection` lives outside `lib/widgets/detail` but is rendered by
    two layouts — theme it by parameter so Classic keeps today's look.
13. The shell's back button and trailer chip are private widgets with hardcoded
    circular shape and fills; a square theme cannot reuse them unchanged.
10. Signal is the regression test — if Signal moves, the refactor is wrong.

---

## 7. Decisions taken here (not asked)

- **All twenty ship** — they are data; the plumbing is the work.
- **Classic is not themed**, stated plainly in the picker.
- **The four shared sheets are not themed in v1** — they are Classic's too.
- **No per-theme layout defaults.** Two orthogonal settings.
