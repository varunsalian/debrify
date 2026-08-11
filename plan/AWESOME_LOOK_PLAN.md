# Making it look awesome — phase three of the theme work

*Revision 4, and the last before implementation. Round 1 found 6 P0 / 10 P1;
round 2 closed 13; round 3 closed 3 more and left 2 P0 + 5 P1 + 2 new findings.
Revision 4 answers all of them — three by redesign, two by **bounding the scope
and saying so**, which is the honest answer where a provably-correct solution
needs machinery this phase is not going to build. Corrections are marked
**[R1]** / **[R2]** / **[R3]**.*

### Where revision 4 deliberately stops short

Two findings are closed by *reducing the promise*, not by solving the general
problem. Both are recorded here so nobody has to reconstruct the reasoning:

* **The light themes are simply not re-enabled in this phase. [R3]** Every
  conditional gate proposed so far was, on inspection, a manual and incomplete
  one dressed as an automatic one. §6 now does the work — expanded audit,
  fixes, inventory — and `kDetailThemesShipped` is left exactly as it is. The
  question "are they safe yet?" gets a better answer from a later, smaller
  change than from a judgement call at 5am.
* **Look application is last-writer-wins per key, not a transaction. [R3]**
  A durable, crash-atomic, 173-setter-wide preference transaction is a real
  piece of infrastructure and is not proportionate to a cosmetic preference
  bundle. §9 states precisely what it does and does not guarantee.

The colour half of the theme system shipped (`6c9597d`…`5af540c`: 159 files,
+12,187/−3,674). Eighteen of the twenty themes reach every surface except the
player — Broadsheet and Concrete are withheld from `kDetailThemesShipped`
(`detail_theme_page.dart:38`) and that set feeds the App Theme picker too. **[R1]**

What the themes do **not** reach is everything that isn't colour. `AppTheme`
carries `core: DetailTheme` plus twelve colour subprofiles. `DetailTheme`
already carries the other half of a look — five radii, three font roles,
display weight/tracking/case/scale, `focusWidth`/`focusOffset`, a shadow list,
`grain`, `grid` — and **all of it is applied on one screen**. Everywhere else,
all twenty themes render identical geometry, typography, elevation and motion
in a different tint.

---

## 0 · Ground rules inherited from phase one and two

1. **Legacy is byte-identical.** Every new dimension needs a legacy pin whose
   value is a no-op (scale 1.0, family null, duration ×1.0).
2. **Surface and ink migrate together, both directions.**
3. **Compose a pin the same way the source composes it.**
4. **TV rules live on the theme and cannot be bypassed** — `focusWidthFor`
   (2.5 floor), `grainFor` (0 on TV), `shadowFor` (drops blur > 6).
5. **A hard TV zero wins over any token. [R1]** Where a site already collapses
   an animation to `Duration.zero` on TV (`tv_focusable_card.dart:124`,
   `catalog_browser.dart:1929`), that branch is preserved verbatim and only the
   non-TV duration may become a token. Motion tokens govern how long an
   animation that *already exists* runs — they never resurrect one the TV gate
   killed.
6. **Never build `ThemeData` in `build()`**; never store a `Future` on a
   process singleton.
7. **Hoist `AppThemeScope.of` out of** builder callbacks.
8. **Invariant colours and invariant geometry stay `const`** — black scrims,
   transparent, and circles that are circles because they are circles.
9. Everything stays **uncommitted** on `tvos_port`.

---

## 1 · Shape — a bounded scale

**1,654 `BorderRadius.circular` sites across 197 files.** Migrating them to five
named radii means 1,654 judgement calls no test can check. The detail page
already solved this once, for artwork:

```dart
BorderRadius imgRadius(double site) => BorderRadius.circular(site * radiusImg / 8);
```

**The site owns the hierarchy; the theme owns the scale.** Generalise exactly
that.

### Shrinking is free; growing is not **[R1] [R2]**

Revision 1's `max = radius <= 3 ? radius : infinity` cap was wrong — it
flattened Velvet's hero and its chips to the same 3px. Squareness is not a
threshold, it is `scale == 0`, which is exactly what five themes declare:

| Theme | `radius` | raw | **damped scale** | a 20px site | a 12px site | a 4px site |
| --- | --- | --- | --- | --- | --- | --- |
| Signal (legacy) | 10 | 1.00 | 1.00 | 20 | 12 | 4 |
| Aurora | 18 | 1.80 | **1.40** | 20 (capped) | 16 (capped) | 5.6 |
| Velvet | 3 | 0.30 | 0.30 | 6 | 3.6 | 1.2 |
| Broadsheet | 2 | 0.20 | 0.20 | 4 | 2.4 | 0.8 |
| Blueprint / Noir / Concrete / Phosphor / Vault | 0 | 0 | 0 | 0 | 0 | 0 |

But round 2 was right that an *unbounded* scale is not hierarchy-preserving
either: an `RRect` radius is normalised to its box, so a growing theme turns a
short control into a pill.

Round 3 was right that a cap of 24 does not achieve this — a 24px radius still
pills a 40px control, and 24 was justified against the *literal distribution*
when the constraint is actually *control geometry*. **[R3]** So growth is bounded
twice, and the numbers come from the boxes:

```dart
// scale itself, at derivation time
scale = dampGrowth(core.radius / 10);          // raw > 1 → 1 + (raw-1) * 0.5

double r(double site) => scale <= 1
    ? site * scale                                  // legacy & every square
    : math.min(site * scale, math.max(site, 16));   // never below the site
```

* **Damping**: a raw scale above 1 is halved toward 1 — the same treatment and
  reasoning as `titleScale`. Aurora 1.80 → 1.40, Frost 1.60 → 1.30,
  Halo 1.40 → 1.20.
* **A cap of 16**, because the app's standard controls are 36px and taller and
  a box pills at `height / 2` = 18. A radius that never exceeds 16 cannot
  lozenge one.
* `scale <= 1` is untouched: legacy is arithmetically identical, and no
  squaring theme can collapse anything.

**The residual case, stated rather than hidden [R3]**: a control shorter than
32px whose authored radius is already above ~11 can round further under a
growing theme than it does today. That is a softening of something already
nearly circular, not the collapse of a rectangle. A provably safe rule needs
the receiving box's height, which a token cannot see — so this is a bounded,
named limitation and `shape_type_motion_test.dart` asserts the bound holds for
every theme against every radius literal the tree actually draws.

### Three named entry points **[R2]**

`brBtn` is deleted. Round 2 was right that it had no stated algorithm and three
plausible ones, each with a different legacy answer. A button with a numeric
radius is a surface; a button that is a pill asks for a pill.

```dart
class ShapeTokens {
  final double scale;      // core.radius / 10
  final double imgScale;   // core.radiusImg / 8   — matches imgRadius()
  final double pill;       // core.radiusBtn >= 999 ? 999 : core.radiusBtn
  final double focusWidth, focusOffset;
  final List<BoxShadow> shadow;
  final double grain;
  final bool grid;

  double       r     (double site);   // a bare double, per the rule above
  BorderRadius br    (double site);   // any surface — cards, chips, buttons
  BorderRadius brImg (double site);   // artwork — uses imgScale
  BorderRadius get brPill;            // the pill sentinels
}
```

**Both pill sentinels are recognised**: the tree uses `circular(999)` 85 times
and `circular(99)` 9 times **[R2]**, and the migration maps both to `brPill`.
The ratchet enforces that no bare `circular(99|999)` survives in scope, so the
two cannot drift apart again.

Sepia (`radius 4, radiusBtn 4`) squares its pills to 4px because `pill` reads
`radiusBtn`. Legacy pins `scale: 1, imgScale: 1, pill: 999`, `shadow: const []`,
`grain: 0`, `grid: false`, `focusWidth`/`focusOffset` at today's values.

### What the ratchet does and does not prove **[R2]**

Round 2 was right that counting `app.shape.` occurrences proves nothing —
comments and duplicate calls satisfy it. That half is dropped. What remains is
enforceable and still worth having:

1. **A per-file residue ratchet**, not "zero bare radii" — revision 3 claimed
   zero and the implementation cannot deliver it. **[R4]** A site converts only
   where `app` is in scope and the expression is not `const`, and the sweep
   discovered which by asking the analyzer and reverting everything it
   complained about. `test/theme/shape_manifest_test.dart` therefore records
   the residue each swept file is allowed to keep (162 across 71 files) and
   fails when one grows, plus a floor on total token calls so a wholesale
   revert cannot pass quietly. It counts both spellings —
   `BorderRadius.circular(n)` and `BorderRadius.all(Radius.circular(n))`.
   It is a tripwire, not a proof: it does not check that a site was classified
   surface-vs-artwork correctly, and like every ratchet it can be defeated by
   raising a number in the same change that regresses.
2. **Asymmetric radii are out of scope** — `BorderRadius.only`, `.vertical`,
   `.horizontal` keep their literals. Only `.circular` is mechanical.
   `circular(<identifier>)` (24 sites, e.g. `circular(radius)`) is also out:
   the argument is already a variable and scaling it needs the caller's intent.
3. **Pre-sweep legacy goldens over the converted families**, captured in
   **P3, before the sweep** — round 2 caught that P4 cannot depend on a gallery
   expansion scheduled after it **[R2]**, so the expansion and the capture are
   now explicit P3 deliverables and P4 only has to keep them green.
   They are evidence, **not proof**: the gallery cannot reach screens that need
   services or a database (`surface_gallery.dart:17`), so they cover the shared
   widget families and not the 1,654-site sweep in full. **[R3]** What actually
   bounds the risk is that legacy's arithmetic is the identity — a converted
   site under legacy renders its own literal or it does not compile.

### Scope

Shared families a user sees constantly: settings rows/sections; search +
results; cloud file rows + downloads; detail + episodes; TV surfaces;
calendar/addons/playlist; and the themed path of `app_theme_adapter.dart`.

Out: `screens/deprecated/**` (236 sites in one dead file), `video_player/**`
(permanently legacy), `initial_setup_flow.dart` (bootstrap boundary).

---

## 2 · Type

`AppThemeAdapter._textTheme` is `GoogleFonts.interTextTheme(_textSkeleton)`.
**It is shared by both paths** (`:145` legacy, `:343` themed), so it cannot be
changed in place — the themed path gets its own construction and the legacy
getter is left exactly as it is. **[R1]**

It is also not the only family path: `appBarTheme.titleTextStyle` builds its
own `TextStyle` (`app_theme_adapter.dart:394`) and 98 sites name a family
explicitly. The themed construction sets both the text theme *and* the
component text styles it already builds. **[R1]**

### `TypeTokens`

```dart
class TypeTokens {
  final String? displayFamily; final List<String>? displayFallback;
  final String? bodyFamily;    final List<String>? bodyFallback;
  final double titleScale;     // [R3] NOT `displayScale` — a different token
  final FontWeight? displayWeight;
  final double? displayTracking;
  final bool displayUpper;     // available to sites; NOT applied globally
}
```

Applied in `AppThemeAdapter.themed` only. Display/headline/title styles take
the display **family and scale**; body/label take the body family.

**Weight and tracking are carried but NOT applied app-wide.** They are hero
values — Cinemascope asks for 3.8 letter-spacing, Blueprint for 1.8 — and
`type_metrics_test.dart` measured Cinemascope's tracking pushing a one-line
dialog action past its box on the shipped fixtures. The app-wide contract is
therefore narrower than the details page's: *the theme owns face and scale; the
site keeps its weight, tracking and case.*

**`displayUpper` is not applied app-wide.** Six themes declare it; forcing caps
on every title in the app changes string widths unpredictably and reads as
shouting outside a hero. It stays a token sites may consult.

**It is `titleScale`, a different token from detail's `displayScale`. [R2]**
Round 2 was right that reusing one name for two transforms hides the fact that
a theme's display character now differs by surface. So the app-wide one is
named for what it is:

* `core.displayScale` — the details page's own, raw, `displaySize / 23`
  (0.78–1.35). Unchanged.
* `type.titleScale` — the app-wide one, `1 + (core.displayScale - 1) * 0.5`
  → **0.89–1.17**. Damped on purpose: 1.35 on every title in a dense TV row
  overflows, and the hero-sized statement a details page can make is not a
  statement a settings row can make.

**Acceptance criterion**: `type_metrics_test.dart` (below) must pass at
`titleScale` for every theme on the tightest real constraints. If a face and
scale combination cannot, the damping factor drops — the test is the authority,
not the 0.5.

### Font roles get real faces

`DetailFontRole.family` returns the CSS generics `'serif'`/`'monospace'`
(`detail_theme.dart:14`), pinned at `detail_theme_test.dart:159-161`. Those
resolve unpredictably off Android and are a coin-flip on the tvOS port. The
repo already bundles the faces:

| Role | Family | Fallback |
| --- | --- | --- |
| sans | `null` (Inter via textTheme) | — |
| serif | `Fraunces72` | Georgia, Times New Roman, serif |
| mono | `JetBrainsMono` | FiraMono, Menlo, monospace |

**Fraunces, not Source Serif — because Source Serif is not a font.** Four files
in `assets/fonts` are HTML error pages saved with a `.ttf` extension:
`SourceSerifPro-Regular.ttf`, `Merriweather-Regular.ttf`, `Roboto-Regular.ttf`
and `Roboto-Bold.ttf` (all begin `<!DOCTYPE html>`). Anything naming them
silently falls back — which the **subtitle font picker already offers to
users**, so this is a shipped bug with a blast radius outside theming. Fixing
it means adding megabytes of variable font, a size decision rather than a
theming one, so it is reported and left. Fraunces is real, licensed and already
bundled for the IPTV Edition style.

`sans` stays null, so **Signal does not move** and its pins hold. The two
generic-string assertions are updated with this rationale — a deliberate
change, flagged for review.

Blast radius of a non-Inter *body*: **two themes**, Broadsheet (serif) and
Phosphor (mono) — not four. **[R1]** Display face changes on six: Broadsheet,
Velvet, Sepia, Vault (serif), Phosphor, Blueprint (mono).

### The overflow guard has to use real fonts **[R1]**

`golden_harness.dart:13` sets `debugUseTestTypography = true`, so goldens
cannot detect Source Serif or JetBrains Mono widths, and widget tests do not
make every overflow a failure by default.

New `test/theme/type_metrics_test.dart`: loads the real bundled TTFs via
`FontLoader`, lays out the tightest real strings in the tightest real
constraints (TV row titles, settings subtitles, chip labels, episode captions)
under every theme, and **asserts on the overflow explicitly** — both by
capturing `FlutterError.onError` for `RenderFlex`/text-overflow exceptions and
by measuring `TextPainter.didExceedMaxLines` against the constraint. A face
that does not fit fails the build rather than a user's TV.

---

## 3 · Motion

682 `Duration(milliseconds:` sites; `easeOutCubic` used 132 times **[R1]**;
no token, and no single place to turn motion down on a weak box.

### `MotionTokens`, resolved through context **[R1]**

Revision 1's `operator *` had no `BuildContext` and therefore could not honour
reduced-motion. And the claim that this is the first use of that flag was false
— `stremio_tv_tuner.dart:1111` already honours it.

```dart
class MotionTokens {
  final Duration fast, base, slow;    // 120 / 220 / 360 at scale 1
  final Curve standard, emphasized;
  final double scale;
}

/// The only public way to get a duration. Resolves reduced-motion and the
/// TV policy at the call site, where the context exists.
class AppMotion {
  static AppMotion of(BuildContext context);   // reads scope + MediaQuery
  Duration get fast; Duration get base; Duration get slow;
  Duration scaled(Duration d);
  Curve get standard; Curve get emphasized;
}
```

* `MediaQuery.disableAnimations` collapses every duration **this API vends** to
  `Duration.zero`. Not "every duration in the app": route-controller duration
  is unreachable from a `PageTransitionsBuilder`, and unconverted literals are
  unaffected. **[R2]**
* Legacy: `120/220/360`, `easeOutCubic`, `easeOutBack`, scale 1.0 — chosen to
  equal the durations already most common, so adopting a token is usually a
  no-op.
* Per theme, `scale` is deliberately narrow: 1.15 for editorial themes
  (`grain > 0 || displayUpper`), 0.85 for technical ones (hard `focusWidth`,
  no `shadow`), else 1.0. A theme that takes 2× as long to open a sheet reads
  as lag, not character.

### Where a site is allowed to call it **[R2]**

Round 2 was right that an inherited lookup is invalid in `initState` and stale
after a theme or accessibility change, and that calling it inside an
`AnimatedBuilder`/transition callback breaks rule 0.7. Three rules, and the
adoption list is chosen to fit them:

1. **`State` that owns an `AnimationController`** resolves in
   `didChangeDependencies` — construct the controller in `initState` with the
   legacy default, then assign `controller.duration` from `AppMotion.of` in
   `didChangeDependencies`. That is the one lifecycle hook that may both depend
   on inherited widgets and re-run when they change.
   **What that does and does not do [R3]**: Flutter reads `duration` when a run
   *starts*, so this affects the NEXT run, not one already in flight. Revision 3
   claimed both "retargets a live controller" and "does not disturb a run in
   progress", which cannot both be true. The honest contract is: a theme or
   reduced-motion change applies from the next animation onward, and an
   animation already playing finishes at its old tempo. Nothing in this app
   runs long enough for that to be visible, and forcing a stop/restart would
   make a theme switch visibly glitch every live animation on screen.
2. **Stateless sites** (`AnimatedContainer`, `AnimatedOpacity`,
   `AnimatedSwitcher`) read it in `build`, hoisted above any builder callback
   exactly like `AppThemeScope.of`.
3. **Never inside a transition or `AnimatedBuilder` callback.** The TV page
   transition keeps its `const Interval(0.0, 0.4, curve: Curves.easeOut)`
   literal; curves that belong to a route are baked into the memoized
   `ThemeData` by the controller, never read ambiently per frame.

### Route transitions are out of scope **[R1]**

`TvAwarePageTransitionsBuilder` receives an animation the route already
created (`app_theme_adapter.dart:29`); a `PageTransitionsBuilder` **cannot**
change route duration. Revision 1 implied it could. Route *duration* stays as
it is; only curves/intervals inside the existing builder are token-shaped.

### Adoption scope

Sheet and dialog reveals, focus rise/glide on TV cards **subject to rule 0.5**,
Home hero cross-fades, sidebar open/close. Everything else keeps its literal,
which equals the token default.

---

## 4 · Texture, app-wide

Facts corrected **[R1]**: `DetailAtmosphere` (`detail_style.dart:484`) uses no
`BlendMode.overlay` and no cached tile — `_GrainPainter` paints up to ~3,000
rectangles per repaint (`:526`). And **grid is not gated off on TV** today;
only grain is (`:491`).

The promotion therefore must do three things the detail page does not:

1. **Batch the grain — no image cache. [R2]** Round 2 was right that a
   `ui.Image` cache keyed on logical size is wrong across DPR, unbounded across
   resizes, leaks native memory without disposal, and cannot be rasterised
   synchronously from `paint()` anyway. The fix is the idiom the launch idents
   already use: precompute the speck positions **once** into a reused
   `Float32List` and emit them with a single `canvas.drawRawPoints`, instead of
   thousands of `drawRect` calls. Synchronous, allocation-free per frame, no
   image to key or dispose, and the buffer is rebuilt only when `(size, grain)`
   changes — the same `_size`-guard pattern `_HorizonPainter` uses. This also
   fixes the detail page, which shares the painter.

   **The contract, spelled out [R3]**: `PointMode.points` with an explicit
   `strokeWidth` and `StrokeCap.square`, so a point is the same 1px mark the
   current `drawRect` draws rather than a round dot of paint-dependent size.
   The buffer key is `(size, grain, devicePixelRatio)` — DPR matters because a
   hairline point is sized in physical pixels, so the same logical buffer at a
   different DPR changes both speck density and speck size. Invalidation reads
   DPR from the enclosing `MediaQuery`, not from the canvas.
2. **Gate grid on TV as well.** A full-screen 32px rule is cheap to *paint*
   but not free to composite over a scrolling shelf on a 2 GB box; it follows
   the same `isAndroidTvCached` policy grain already follows.
3. **Respect containment. [R1]** A single insertion above the Navigator
   (`main.dart:489`) would texture the permanently-legacy player and the
   frozen launch ident (`app_initializer.dart:414`). `AppTexture` therefore
   **listens to `AppSurfaceState.instance` and paints nothing while
   `active == SurfaceKind.frozen`** — the same signal system-bar ownership
   already reads, and the reason that signal exists.

Off for legacy and for every theme that declares neither. Grain: two themes
(Sepia 0.09, Cinemascope 0.05) **[R1]**. Grid: Blueprint alone.

---

## 5 · Artwork accent — a scoped value, not a derived theme

Revision 1 proposed `AppTheme.withArtworkAccent(Color)`. Review killed it, and
correctly: `fromDetail` derives a dozen subprofiles from `core.accent`
(`app_theme.dart:139`) while `DetailTheme` deliberately exposes only
`withText` (`:301`) — so replacing the accent leaves `focus`, `state`,
`callout`, `btnFill` and the washes on the old colour while the subprofiles
move. A half-recoloured theme is worse than an unrecoloured one.

**The redesign: artwork accent is a value in scope, consumed explicitly.**
Exactly what `merged_series_detail_screen.dart:989` already does
(`_theme.useArtworkAccent ? _accent : _theme.accent`), promoted to a shared
mechanism instead of copied.

```dart
/// InheritedTHEME, not InheritedWidget. [R2] `InheritedTheme.capture` silently
/// SKIPS plain inherited widgets, so a dialog or sheet launched from a themed
/// page would lose the accent — the exact bug `DetailThemeScope` and
/// `AppThemeScope` both extend `InheritedTheme` to avoid.
class ArtworkAccentScope extends InheritedTheme {
  final Color? accent;                       // null ⇒ use the theme's own
  @override Widget wrap(BuildContext c, Widget child) =>
      ArtworkAccentScope(accent: accent, child: child);
  @override bool updateShouldNotify(ArtworkAccentScope old) =>
      old.accent != accent;                  // Color has value equality
  static Color? of(BuildContext context);
}
```

* A consumer opts in **per site**, where it already paints an *identity*
  colour. Meaning colours (state, callout, error, success) never take it.
* `useArtworkAccent` still gates it: a fixed-palette theme (Noir's white,
  Phosphor's amber) is never contaminated.
* **Ground-aware normalisation. [R1]** `extractDominantColor` normalises "into
  an accent range that reads well on a **dark** UI"
  (`dominant_color.dart:66`). On Broadsheet/Concrete paper that can land
  low-contrast. A new `normaliseAccentFor(Color raw, AppTheme theme)` bisects
  the extracted hue toward a target luminance against the theme's *own*
  ground, reusing the `_atLuminance` machinery already in `app_theme.dart:539`
  — and every consumer still routes ink through `inkOn` / `focusOn`.
* **A `DominantColorCache`** (LRU, keyed by URL, 64 entries) so extraction is
  free on revisit; the two existing callers adopt it.
* `catalog_item_detail_screen` gains the same poster path merged_series has.
* Extraction stays off where the Home hero already publishes `tvHeroTint` on
  its own rest cadence — two publishers would fight.

---

## 6 · Light themes — a two-part gate

Broadsheet and Concrete are withheld (`d3d78fb`) because *"screens still
carrying hardcoded light text literals never go through the token layer"*. The
commit is explicit that **green tests are not the signal for re-enabling**.

Scale: **1,152 `Colors.white` sites** outside the player and deprecated
screens; 752 as `color:`. Many are correctly white (over artwork, on glass, on
a filled accent). Blind conversion is exactly the mistake rule 0.2 names.

Review's P0 stands: a green *covered* gallery is not a release criterion,
because `surface_gallery.dart:17` excludes screens needing services/DB and
`contrast_audit_test.dart:137` understands only simple painted backgrounds, not
images or gradients. **[R1]** So the gate has two parts and both must pass:

1. **Rendered audit** — expand `surface_gallery.dart` with the widget families
   that carry the most white literals and are constructible from plain props
   (poster/playlist cards, IPTV channel rows, YouTube video cards, episode
   tiles, cloud file rows, empty states, filter chips, badges, see-all cells,
   calendar cells); run `contrast_audit_test` under Broadsheet and Concrete;
   fix every failure, surface and ink together.
2. **A triage inventory — explicitly NOT a release gate. [R2]** Round 2 was
   right that a lexical scan cannot be a completeness check: ink also arrives
   through locals, `copyWith`, `IconTheme`, `DefaultTextStyle`, widget
   defaults, aliases and helpers, while a literal in a `color:` argument is
   often a legitimate fill. An allow-list built on that would become an
   unreviewable suppression file, and a clean run would mean nothing.

   So the scan is demoted to what it can honestly be: `tool/light_ink_inventory.py`,
   a **ranked worklist**, not a test. It reports candidate ink literals per
   file with surrounding context so they can be judged by a human (me) and
   fixed by hand. It never votes on whether the themes ship, and nothing in
   `test/` depends on it.

**`kDetailThemesShipped` is not touched in this phase. [R3]** Round 3 was right
that revision 3 called the inventory "not a release gate" and then made
re-listing conditional on it being empty — a manual, incomplete gate wearing an
automatic one's clothes, with "visually sane goldens" as its final criterion.

So there is no conditional. The withheld set stays exactly as `d3d78fb` left
it, and this phase's deliverables for the light themes are the three things
that are unambiguously progress:

* the **expanded gallery**, which makes far more of the app auditable under any
  theme, light or dark;
* every **audit failure fixed**, surface and ink together;
* the **inventory**, which turns "1,152 white literals somewhere" into a ranked,
  reviewed worklist.

A later change re-lists them once that worklist is short enough to argue about.
That change will be small, and it will be able to point at evidence — which is
strictly better than a judgement call made at the end of a long night.

### What actually landed **[R4]**

* The gallery grew from four widget families to fifteen, and its goldens are
  captured for legacy, Noir, Broadsheet and Concrete.
* `contrast_audit_test` is green under both light themes for everything the
  gallery can reach.
* `tool/light_ink_inventory.py` ships: **791 candidate ink sites in 102 files,
  241 of them on the primary surfaces** a user meets first. That last number is
  the one to watch — it is what gates re-listing.
* A mechanical pass moved **30 primary-surface sites** onto `core.tx` at their
  exact shipped alphas (`0xB3 / 0xFF` and friends, composed the way the source
  composes them), so legacy renders identically and a paper theme finally gets
  dark ink. The rest are inside `const` widget trees, where converting means
  un-consting an outer constructor — mechanical, but a per-site judgement about
  allocation that is not worth making 241 times unattended.

---

## 7 · Launch idents follow the theme

Seventeen idents, each with `baseColor`, `backdrop`, `sweepColors` and a
painter carrying ~10 colour literals. Repainting every mark per theme is
neither cheap nor right — the ident *is* an art direction.

**The room takes the theme's colour; the mark keeps its own art.**

```dart
class IdentPalette { final Color base, accent, ink; final Decoration backdrop;
                     final List<Color> sweep; }
```

* **The backdrop is themed, not just the base. [R2]** Round 2 was right that
  every ident's `backdrop` must be fully opaque (`launch_ident.dart:56`), so
  swapping only `baseColor` changes nothing a viewer sees. Themed mode keeps
  each ident's backdrop *geometry* — its gradient type, centre, radius and
  stop positions — and substitutes its *colours*, so Horizon stays a radial
  nebula around the collapse point and simply becomes the theme's nebula. Each
  ident supplies that mapping itself via a `themedBackdrop(IdentPalette)`
  override, defaulting to a flat `palette.base` for the ones whose backdrop is
  already a plain colour.
* `LaunchIdent.palette` defaults to the ident's own literals; `createPainter`
  gains an optional `palette`, and each painter reads `palette.accent` /
  `palette.ink` where it reads its signature literal today. Structural blacks,
  whites-as-light and alpha veils stay literal.
* **The palette is passed explicitly, never looked up. [R1]** Idents render
  under the bootstrap freeze (`app_initializer.dart:414`), so an ambient
  `AppThemeScope.of` would return *legacy* and the feature would silently do
  nothing. The splash reads `AppThemeController.instance.theme` — a singleton,
  already warmed in `main()` before `runApp` — and passes the derived palette
  down as a parameter.
* New pref `launch_ident_palette` ∈ {`ident`, `theme`}, default `ident`, so
  nothing changes for anyone who does not opt in.
* **Contrast guard**: a themed base is adopted only if it keeps ≥ 3:1 against
  the ident's mark; otherwise the ident keeps its own base. Three seconds of
  first impression — an unreadable ident is worse than an off-palette one.

---

## 8 · Cosmetic debt still open

Re-verified against the tree. Three of the handoff's six are **already fixed**
and are not scheduled: `tv_focusable_button.dart:101` applies `inkOn`;
`browse_search_header.dart:139` forwards all four keyboard params and
`browse_screen.dart:143-149` passes them; the playlist badge is legacy-pinned
with `inkOn` for themed fills (`playlist_content_view_screen.dart:1743`). **[R1]**

| # | Site | Fix |
| --- | --- | --- |
| a | `iptv_epg_panel.dart:203,247` | App ink overrides Edition/Console's own `fg/fgMid/fgDim/fgFaint` ramp even when `widget.tokens != null` — use the tokens' ramp when present |
| b | `iptv_results_view.dart:6704` | `core.tx` for a border on black glass — use `onGlass` |
| c | `downloads_screen.dart:693,695` | `Shimmer(…)` passes neither `base` nor `highlight`; `downloads.shimmerBase/Highlight` have no call site |
| d | `source_guard_test.dart:175` | `stillFrozen` is a hand-maintained path list. It cannot literally "read `AppSurfaces.tabs`" (that maps indices, not paths), so instead: assert the list contains only playback paths **and** that `AppSurfaces.tabs` has no frozen entry other than the inert index 0 — a flip then cannot leave the guard green |

---

## 9 · Looks — one pick instead of fourteen

Fourteen independent pickers across Appearance and Home & Display. A **Look**
is one pick that writes a curated bundle; every individual picker stays.

### The write path is a coordinator, not a token **[R1]**

Review's P0 is correct: `_persistSeq` is private to `AppThemeController.select`
and guards only its own two-key write. `setTvHomeStyle`
(`storage_service.dart:752`), `setIptvStyle` (`:932`) and `setLaunchAnimation`
(`:1047`) each obtain `SharedPreferences` and write independently, and pages
like `tv_home_style_page.dart:121` fire their own live-apply callbacks.

### The generation counter lives on the KEY, not on the applier **[R2]**

Round 2 was right that an applier-local token is useless: manual pickers never
increment it, so a manual write landing between two of the applier's awaits is
invisible and gets overwritten by a later one. And "publish synchronously" was
not achievable through setters that assign their mirror *after* persistence —
`setLaunchAnimation` (`storage_service.dart:1047`) is exactly that shape.

The counter therefore moves into `StorageService`, where every writer already
passes:

```dart
// StorageService
static final Map<String, int> _writeGen = {};
static int  generationOf(String key) => _writeGen[key] ?? 0;
static void _bumpGen(String key) => _writeGen[key] = generationOf(key) + 1;
```

* **No existing setter is modified. [R3]** Round 3 was right on both counts:
  there are ~173 `setX` methods, many with no synchronous mirror to publish at
  all, and at least one caller deliberately persists *before* reflecting
  (`iptv_settings_page.dart:464`, because the page it returns to re-reads the
  pref). A blanket mirror-first conversion would rewrite an established
  contract across the whole service to serve a cosmetic feature.
* Instead a **narrow adapter layer** describes only the ~12 keys a Look can
  name: for each, `read`, `write` (delegating to the existing setter), and
  `notify` (the live callback that picker already fires). The generation
  counter lives in that layer, not in `StorageService`.
* `LookApplier` snapshots each key's generation, applies in a fixed order, and
  **skips a key whose generation moved** mid-apply — a human beats a preset.
* The theme pair still routes through `AppThemeController.select`, untouched,
  so the `detail_theme`-before-`app_theme` write-through survives; the applier
  does not own that pair, it delegates to the thing that does.
* **A Look may never name a theme that is not in `kDetailThemesShipped`. [R3]**
  Round 3 found the real hole: `AppThemeController.select` accepts any stored
  detail-theme id, so a bundle naming `broadsheet` would expose exactly the
  theme §6 withholds. The applier rejects unshipped ids and a test asserts
  every bundle's theme is shipped — so the withheld set cannot be reached
  through the side door.

**What this does NOT guarantee, stated plainly [R3]:** it is not a transaction.
A crash mid-apply leaves a partial Look (the next apply fixes it, and the
picker will read *Custom* until then). A manual change made in the same
handful of milliseconds as an apply resolves last-writer-wins per key, not
atomically. Both are acceptable for a cosmetic bundle and neither is worth the
durable-transaction machinery that fixing them properly would require.

Only keys the bundle names are written. Six Looks ship, each a defensible art
direction; the one built on Broadsheet is listed **only if §6 lands**.

**Detection, not storage**: "which Look am I on" is computed by comparing
current values to each bundle, so a Look never goes stale against a manual
change; a non-matching set reads *Custom*.

---

## 10 · Phase order **[R1: artwork accent moved before the light gate]**

Each phase ends with `dart analyze lib/`, the theme suite, and a Codex review.

| # | Phase | Gate |
| --- | --- | --- |
| **P1** | Cosmetic debt (§8) | Four isolated fixes; clears known-broken state first |
| **P2** | Token foundation (§1–3 token classes) + legacy pins + derivation tests | Legacy no-op; all 20 themes derive |
| **P3** | Type + motion wiring (§2, §3) + texture (§4) **+ the gallery expansion and the pre-sweep legacy golden capture** **[R3]** | Real-font metrics test green; texture respects `AppSurfaceState`; goldens captured for every family P4 will touch |
| **P4** | Shape sweep (§1) | Manifest ratchet green; P3's legacy goldens still match |
| **P5** | Artwork accent (§5) | Runs **before** the light work so P6 audits the colours it introduces |
| **P6** | Light themes (§6) | Gallery audit green; inventory produced; `kDetailThemesShipped` untouched |
| **P7** | Ident palette (§7) | Opt-in pref; default byte-identical; palette passed explicitly |
| **P8** | Looks (§9) | Adapter-layer ordering; every bundle round-trips; **no bundle names an unshipped theme** |
| **P9** | Full-tree review, full suite, `dart analyze`, arm64 release build | No P0/P1 open; report written |

## 11 · What this plan does not do

* **The player stays legacy** — excluded at its entry points; a Dart player
  theme engine was built and reverted once already.
* **No asymmetric-radius migration** (`BorderRadius.only/vertical/horizontal`)
  — recorded in §1, deliberately out of the mechanical pass.
* **No repo-wide `dart format`** — it rewrites these files wholesale and would
  bury every conversion.
* **No device QA.** The suite, the contrast audit, the new metrics test and the
  goldens are the net; a device pass is still the user's step, and §6 is the
  item most exposed to it.
* **No new layouts.** Every item is the existing structure, better dressed.
