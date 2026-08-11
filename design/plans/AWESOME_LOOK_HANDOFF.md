# Phase three — where it stands

All **uncommitted** on `tvos_port`. `dart analyze lib/` **0 errors**. Full
suite **2205 pass / 9 fail** — the same nine pre-existing `series_parser`
failures the tree had before any of this (baseline 2103/9; the extra 102 passes
are the new tests). `flutter build apk --release --target-platform android-arm64`
green at **53.8 MB**, unchanged.

## The one-line summary

The theme system now reaches everything that isn't colour — shape, type,
motion, texture — and the app has one **Look** picker instead of fourteen
independent style dropdowns. **Nothing changes for anyone on Debrify Classic.**

## What shipped, by phase

| # | Phase | Outcome |
| --- | --- | --- |
| P1 | Cosmetic debt | 3 real fixes + a guard; 3 of the handoff's 6 items were already fixed and are recorded as such |
| P2 | Token foundation | `ShapeTokens` / `TypeTokens` / `MotionTokens` on `AppTheme`, all no-ops under legacy |
| P3 | Type, motion, texture | Per-theme faces in the themed adapter; `AppTexture` app-wide; gallery grown 4 → 15 families |
| P4 | Shape sweep | 500 sites across 71 files onto the shape tokens; **legacy golden unchanged** |
| P5 | Artwork accent | `ArtworkAccentScope` + a dominant-colour cache; the Play button takes the poster's colour |
| P6 | Light themes | Gallery + audit + inventory tool + 30 fixes. **Still withheld — deliberately** |
| P7 | Ident palette | Opt-in `launch_ident_palette`; the ident's room takes the theme, the mark keeps its art |
| P8 | Looks | Six curated bundles, detection-not-storage, one pick at the top of Appearance |
| P9 | Review | 6 Codex rounds; every P0 closed |

## What a user will actually notice

**On Debrify Classic: nothing.** That is the point, and it is enforced rather
than hoped — `shape_type_motion_test.dart` pins every new token to an
arithmetic identity, and the legacy surface-gallery golden came through the
entire 500-site shape sweep unchanged.

**On any other theme**, the themes finally differ in more than hue:

* **Shape** — Blueprint, Noir, Concrete, Phosphor and Vault are genuinely
  square everywhere, not just on the details page. Aurora, Frost and Halo are
  softer. Sepia squares its pills but keeps soft cards.
* **Type** — six themes now wear a real face app-wide (Fraunces for Broadsheet,
  Velvet, Sepia and Vault; JetBrains Mono for Phosphor and Blueprint), and
  titles scale to the theme's own hierarchy.
* **Texture** — Sepia and Cinemascope grain the whole app; Blueprint rules it.
  Off on TV, off on the player, off during the splash.
* **Motion** — a tempo per theme, and **reduced motion is honoured for the
  first time** on the sites that adopted the tokens.
* **Looks** — Appearance opens with one pick that sets the theme, the details
  page, the ident and the TV layouts so they agree with each other.

## Three things to know before you test

1. **The light themes are still withheld, on purpose.** `kDetailThemesShipped`
   is untouched. Every conditional gate I could design for re-listing them
   turned out to be a manual judgement wearing an automatic one's clothes, so
   the phase built the tooling instead: the inventory now says exactly how much
   is left (**791 sites, 241 of them on the screens a user meets first**), and
   re-listing is a small, evidence-backed change later.

2. **Four files in `assets/fonts` are not fonts.** `SourceSerifPro-Regular.ttf`,
   `Merriweather-Regular.ttf`, `Roboto-Regular.ttf` and `Roboto-Bold.ttf` are
   HTML error pages saved with a `.ttf` extension — they begin `<!DOCTYPE
   html>`. Anything naming them silently falls back to the platform default,
   and **the subtitle font picker offers all three to users today**. That is a
   pre-existing shipped bug, outside theming, and fixing it means adding
   megabytes of variable font — a size decision that is yours, not mine. The
   theme layer routes around it (Fraunces is real, bundled and licensed).

3. **Reduced motion now applies under legacy too.** This is the single
   deliberate exception to byte-identity: a user who has switched "Remove
   animations" on gets it whichever theme they are using. Gating accessibility
   on a cosmetic preference seemed the worse trade. Both halves are pinned by
   tests.

## Where to look first on a device

* **Settings → Appearance → Looks** — pick *Console*, then *Cinema*. This is
  the headline.
* **A details page under Sepia** — grain, and the app-wide texture claiming the
  page from `DetailAtmosphere`.
* **Any list under Blueprint or Noir** — square corners everywhere, which is
  the shape sweep.
* **Settings under Broadsheet** *(not reachable from the picker — set
  `detail_theme` by hand if you want to see it)* — this is where the remaining
  ink literals live.
* **A launch ident with "Match the app theme" on**, under Aurora.

## The reviews

Six Codex rounds: three on the plan (which killed the first design of the
artwork accent, the shape cap and the Looks write path outright), one per
implementation phase, and two on the finished tree. Every P0 is closed. The
last pass caught two things worth naming because they are the kind that ship:

* **My own ink sweep put page ink on pinned semantic fills** in
  `debrid_downloads_screen` — white glyphs on a `const` green became
  theme ink, which on a paper theme is near-black on green. Reverted with the
  reason recorded at each site: the surface never migrated, so its ink must
  not either.
* **The ident palette was leaking into Classic.** `LaunchIdent.palette`
  exposes `sweepColors` as its accent, and the splash was passing that to the
  painter unconditionally — so the default Horizon would have ignited in the
  loading sweep's blue instead of its own. The painter now gets `null` unless
  the user opts in, and a test pins why the two colours are not
  interchangeable.

## Known-unfinished, all recorded

* 241 primary-surface ink literals remain (inside `const` widget trees).
* 162 `BorderRadius.circular` literals remain in swept files, same reason;
  `shape_manifest_test.dart` ratchets them so they cannot grow.
* Asymmetric radii (`BorderRadius.only/vertical/horizontal`) were deliberately
  out of the mechanical pass.
* No device QA of any of it — the suite, the contrast audit, the real-font
  metrics test and the goldens are the whole net.
* `dart format` was not run; it would rewrite these files wholesale and bury
  every conversion. If you want it, it should be its own commit.
* `ShapeTokens.shadow` and `focusOffset` are carried but not consumed
  app-wide — promoting elevation is a design pass (does a theme's shadow
  replace or compose with what a site draws?), and an outward focus offset
  needs each site to make room for it. Both are documented as such in
  `app_shape.dart` rather than left looking wired.
* Several detail-layout files still gate TV behaviour on the Android-only
  probe (`detail_identity.dart`, `detail_layout_stage.dart`,
  `detail_layout_console.dart`, `detail_episode_cells.dart`). That predates
  this phase; the two files this phase touched now use `isTelevision`, and the
  rest is a tidy-up for the tvOS port to own.

## Suggested commit split

1. `lib/theme/app_{shape,type,motion}.dart` + `AppTheme` wiring + their tests
2. the four P1 debt fixes + the source-guard coupling
3. `app_theme_adapter` typography + `DetailFontRole` + `type_metrics_test`
4. `app_texture.dart` + `DetailAtmosphere` deferral + its test
5. the shape sweep + `shape_manifest_test`
6. `artwork_accent.dart` + its consumers
7. `IdentPalette` + the pref + the picker
8. `app_looks.dart` + `LooksPage` + the Appearance/TV-pane wiring
9. the ink sweep + `tool/light_ink_inventory.py`
