# Taking the theme layer to the frozen surfaces — phase two

Phase one themed the app *around* seven destinations and pinned them to legacy.
This plan un-freezes six of them. Read `APP_THEME_ROLLOUT_PLAN.md` first — its
containment decision is what gets unwound here. (That document's header still
says "plan, not started"; it shipped in `6c9597d` + `ad88495`. Fix the header or
trust the code.)

## The inversion — read this first

Phase one's risk was **forgetting to freeze** something. Phase two's is the
mirror: **un-freezing something that isn't ready**. There is no partial state —
a surface is frozen or it follows the active theme, including on themes nobody
has looked at it under.

Four scheduled surfaces already read `Theme.of(context)` *while pinned to
legacy*, so lifting the boundary changes their colours before a single literal
moves: Debrify TV (32 reads), IPTV (30), Downloads (9), Stremio TV (9).

That does **not** mean one commit per surface — see *Commit shape*. It means the
classification flip is the last step, never the first.

## How the numbers below were produced

Three earlier drafts got this wrong in three different ways, so the model is
stated explicitly rather than implied:

- **Directory globs undercount.** They miss the widgets a screen renders.
- **Unbounded import walking overcounts.** Every one of these surfaces launches
  playback, so a naive walk drags the whole 40-file player tree into all of
  them. Launching a route is a *navigation* edge, not a *rendering* one.
- So: walk local imports from each surface root, **stop at route boundaries**
  (the player tree, `video_player_launcher.dart`, and Classic details), keep
  only files that paint (`Color(`, `Colors.`, `Theme.of(`, `DetailThemeScope`),
  and subtract anything phase one already owns.

`tool/theme_rendered_set.py` implements exactly that — boundaries and phase-one
subtraction are in the tool, not applied by hand afterwards. Its docstring lists
the roots. **YouTube and IPTV each need two roots**, because `main.dart` injects
their results view into `BrowseScreen` through a callback rather than an import
(`main.dart:2400`, `:2416`); one root silently loses the Browse chrome.

```
tool/theme_rendered_set.py iptv \
    lib/widgets/iptv/iptv_results_view.dart lib/screens/browse_screen.dart
```

`LIST=1` prints the file set, `RAW=1` disables the boundaries (to see the
overcount), `NO_P1=1` keeps phase-one files in.

Shared widgets are counted under every surface that renders them — the column is
what that surface must answer for. `UNION` is the de-duplicated total.

| Surface | files | lines | sites | white-lines | `Theme.of` | shared |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Downloads | 5 | 8,127 | 108 | 28 | 9 | 4 |
| YouTube | 9 | 6,452 | 86 | 35 | 1 | 5 |
| Playlist | 9 | 11,530 | 328 | 116 | 4 | 2 |
| Stremio TV | 11 | 14,998 | 458 | 164 | 9 | 3 |
| Debrify TV | 15 | 16,288 | 460 | 161 | 32 | 2 |
| IPTV | 24 | 20,208 | 545 | 170 | 30 | 5 |
| **UNION** | **58** | **65,055** | **1,809** | **599** | **85** | |

**`sites` is a ranking metric, not a work list.** It is a regex count:
`Colors.white.withValues(...)` scores twice, and a colour computed at runtime
(`HSLColor(...).toColor()`, `Color.lerp`) scores zero. Stage 0's role inventory
must be built by reading the files, not by treating 1,809 as exhaustive.

## Stage 0 — the token contract (blocks everything)

`AppTheme` has subprofiles for **Home, SeeAll, Settings, Cloud, Calendar** and
the shell (`app_theme.dart:26`). There is nothing for Playlist, Downloads, IPTV,
Stremio TV or Debrify TV.

So "replace the literals" is not mechanical, and phase one's own machinery says
why: `legacy_pins_test.dart` pins every legacy value so the compatibility
profile cannot drift. A new subprofile without pins lets a legacy colour move
silently.

Stage 0 is not "decide later". It delivers, before any surface is touched:

1. **A role inventory per surface.** For each of the ~1,809 sites, which
   existing role it maps to (`panel`, `panel2`, `line`, `accent`, `danger`, …)
   or which new role it needs. Reusing a superficially similar role — Cloud's
   `panel` for Playlist's card — is precisely how legacy pixels shift without a
   test noticing.
2. **The subprofiles themselves**: `PlaylistTokens`, `DownloadsTokens`,
   `IptvTokens`, `StremioTvTokens`, `DebrifyTvTokens` (or a justified decision
   to reuse an existing one), derived for all 20 themes in
   `AppTheme.fromDetail`.
3. **Legacy values + pins** — entries in `AppThemes.legacy` and matching
   assertions in `legacy_pins_test.dart`.
4. **The IPTV composition model** (see hazard 1), which has two parts.
   `IptvStyleTokens` bundles palette, semantic colours, typography and layout
   chrome into one fixed object (`iptv_style.dart:30`), so "app palette, IPTV
   layout" is not implementable until it is split along that seam. And it only
   covers two of the three styles — **Command Center, the shipped default,
   returns `null`** (`iptv_style.dart:127`) and paints from literals scattered
   through the IPTV widgets. Command needs its palette *extracted* before it can
   be composed; the other two need theirs *separated*.

Stage 0 is the largest single risk in this plan and the least visible.

## Stage 0b — widgets that straddle the boundary

Six files are rendered by more than one scheduled surface, and the first two are
rendered by **all six** — plus a long tail of themed and permanently-frozen
callers:

| File | scheduled | themed callers today | frozen callers |
| --- | ---: | --- | --- |
| `tv_text_field.dart` | 6 | Settings ×13, Cloud ×5, Search, Addons | player ×5 |
| `tv_keyboard.dart` | 6 | (via `tv_text_field`) | player |
| `shimmer.dart` | 3 | Settings, Cloud | player, Classic details |
| `browse_search_header.dart` | 2 | — | — |
| `brand_accent.dart` | 2 | — | — |
| `download_service.dart` | 2 | — | — |

A shared widget cannot be "tokenised for the frozen side", and a binary
"token-driven everywhere or literal everywhere" is not sufficient — `tv_text_field`
alone must satisfy themed Settings, six scheduled surfaces, and the permanently
frozen player *simultaneously*. `parents_guide_section.dart:17` demonstrates the
shape that works: **caller-supplied tokens**, so the widget renders under
whichever palette its host resolves.

Stage 0b's deliverable is therefore a **migration matrix**, not a yes/no: for
each shared widget, the token parameter, **and the default it takes when a
caller passes nothing**. The default must reproduce today's legacy values
exactly, so the ~20 themed callers and the frozen player keep rendering
unchanged while scheduled surfaces opt in one at a time. Without that default,
converting one widget changes the player.

## Child routes — the gap that would ship a half-frozen tab

Flipping a tab's classification does not theme the routes it pushes;
`Navigator.push` does not inherit from below, which is why phase one inverted.
Outside the player, the frozen child pushes are:

| File | pushes |
| --- | ---: |
| `magic_tv_screen.dart` | 12 (all player — stay frozen) |
| `playlist_screen.dart` | 1 |
| `downloads_screen.dart` | 1 |

Un-freezing Downloads while `downloads_screen.dart:244` still pushes a
`FrozenLegacyPageRoute` ships a themed list with a legacy child, and nothing in
`test/theme/` catches it.

**Required before the first landing:** extend `source_guard_test.dart` with the
inverse assertion — a `FrozenLegacyPageRoute` inside a *themed* surface fails
unless it is in an explicit player-only allow-list. Without it the ratchet is
not a ratchet.

## The three hazards

### 1. Four surfaces already have their own style systems

These ship today and users have chosen values in them:

| Pref | Surface | Choices |
| --- | --- | --- |
| `iptv_style` | IPTV | 3 — Command Center (default), First Edition, Master Control |
| `iptv_player_guide_style` | Both players' guide | 4 — classic / glass / edition / console |
| `tv_home_style` | TV Home | 7 |
| `detail_theme` + `detail_page_style` | Merged details | 20 themes × 10 shipped layouts |

App theme and these are **not the same axis**: `iptv_style` chooses layout and
chrome, app theme chooses palette. Merged details already resolved this in phase
one. IPTV has not.

> **OPEN DECISION — blocks stage 0.4 and therefore the IPTV landing.**
> Does the app palette reach IPTV, and if so does `iptv_style` keep choosing
> layout?
>
> * **(a) Palette follows app theme, layout stays IPTV's own** — recommended.
>   The only option that doesn't discard a preference users have already set.
>   Costs the `IptvStyleTokens` split *and* extracting Command's palette.
> * **(b) App theme overrides `iptv_style` entirely** — cheapest, and silently
>   discards a shipped preference. Needs an explicit product call, not a default.
> * **(c) IPTV keeps its own styles; the app palette does not reach it** — i.e.
>   leave it frozen. Legitimate, and better than a half-answer.
>
> This is a product decision, not an engineering one. Nothing in the IPTV work
> can be scoped until it is answered.

### 2. Playback is a separate, deliberately stable domain

Not "frozen legacy" — a contract. The launcher prefers a **native activity** and
only falls back to the Dart route (`video_player_launcher.dart:930`); the Kotlin
TV layer is ~20.5k lines (`android/.../tv/*.kt`), none of it in any Dart count.
The Dart and native IPTV guides already maintain mirrored playback-specific
style tokens (`IptvGuideStyle.kt`).

A fixed, dark, high-contrast playback surface is normal over arbitrary video, and
theming only the Dart controls would create a worse split than leaving both
alone. A full Dart player theme engine was also built and reverted once as "a lot
to maintain."

**Playback — Dart player, native player, and their guide styles — has its own
stable theme and does not follow the app palette.** Revisiting that is a separate
decision with the prior revert on the table.

### 3. Classic details, onboarding, launch idents

All three stay out, and the reasons are not what an earlier draft claimed.

- **Classic details — out by decision, and note it is not frozen.** It is pushed
  with plain `MaterialPageRoute` from themed surfaces (`search_screen.dart:10036`,
  `aggregated_search_results.dart:393`, `trakt_results_view.dart:672`), and
  `AppThemeScope` sits above the root Navigator, so it **already inherits the
  live theme** with ~372 untokenised sites inside it. It looks right on dark
  themes because its literals are dark-appropriate. It would be exposed if the
  light themes ever return.
- **Onboarding — out by scope, not by dependency.** An earlier draft claimed it
  runs before a theme can be read; that is false. `AppThemeController.warm()`
  completes before `runApp` (`main.dart:186`, `:226`), and onboarding is frozen
  by an explicit `LegacyThemeBoundary` in its dialog builder
  (`initial_setup_flow.dart:53`). It is a real themable surface (4,906 lines,
  ~254 sites, 147 white-lines) that is simply not scheduled.
- **Launch idents — out because palette does not apply.** Brand artwork, 3
  white-lines across 19 files. The startup-channel `AutoLaunchOverlay`
  (`main.dart:3075`) is separately frozen and also stays.

## Order of work

| # | Surface | Notes |
| --- | --- | --- |
| 0 | **Stage 0 + 0b + child-route guard** | Blocks everything below. |
| 1 | **Downloads** | 108 sites, 5 files, 9 theme reads, one child route. The proof that the ratchet and the new child-route guard both work. |
| 2 | **YouTube** | 86 sites. Smallest remaining; shares `BrowseScreen` with IPTV (below). |
| 3 | **Playlist** | 328 sites, one child route, no competing pref. |
| 4 | **Stremio TV** | 458 sites, self-contained. |
| 5 | **Debrify TV** | 460 sites, 32 theme reads, and `magic_tv_screen.dart` is 11,162 lines on its own. Most coupled surface in the app. |
| 6 | **IPTV** | 545 sites and blocked on the open decision in hazard 1 — product, not code. |
| — | ~~Player~~ / ~~Classic details~~ / ~~Onboarding~~ / ~~Idents~~ | See hazards 2 and 3. |

**YouTube and IPTV share `BrowseScreen`** (`main.dart:2400`, `:2416`). They do
*not* have to land together: `AppSurfaces.wrapTab` already applies the boundary
per tab, so a tokenised `BrowseScreen` inherits live tokens under YouTube and
legacy tokens under IPTV's boundary. What must change first is
`source_guard_test.dart:80`, which currently treats `browse_screen.dart` as
frozen wholesale.

## Commit shape

Phase one advised against mixed ~500-site diffs
(`APP_THEME_ROLLOUT_PLAN.md:417`) and that stands. Per surface:

1. **Preparatory commits, root still frozen** — token definitions, legacy pins,
   leaf-widget conversions. Reviewable in pieces.
2. **One small final commit** — remove the boundary, remove the child-route
   freezes, flip `AppSurfaces.tabs`, update the guards and the picker copy.

This needs one relaxation first: `source_guard_test.dart:75` forbids app-theme
reads across whole frozen *directories*, which also blocks leaf-by-leaf
preparation. It must move to root-level, or gain a per-file allow-list, in stage
0. Note its current coverage is partial — it omits the Debrify leaf directories,
Playlist's content screen and the IPTV screen files — so "relax the guard" also
means "make it cover what it claims to".

Only Downloads is plausibly one commit end to end.

## The ratchet

A surface is not done until all of these move:

- **`AppSurfaces.tabs`** — the classification. `kindForTab` fails safe to frozen
  for unmapped indices; keep that.
- **`tab_classification_test.dart`** pins the frozen set as
  `[0, 1, 2, 3, 9, 13, 14]`. Six indices come off across phase two. **Index 0
  never does** — it is the inert deprecated-Home slot. The end state is `[0]`,
  not empty.
- **`source_guard_test.dart`** — relax the landed surface; **keep every
  `VideoPlayerScreen` entry**, since playback stays out. Add the child-route
  assertion.
- **`legacy_pins_test.dart`** — pins for each new subprofile (stage 0).
- **`app_theme_page.dart:117`** — the picker's copy hardcodes the exclusion list
  in user-facing text. Every landing edits this string. **It is already wrong
  today**: it claims "movie/series pages" are themed while Classic details is
  not covered by that promise.
- **Visual acceptance — decide per surface, up front.** `goldens_test.dart`
  covers four theme IDs, and `surface_gallery.dart:17` states that
  service/database/platform-dependent screens are out of reach — which is
  Downloads, IPTV, Stremio TV and Debrify TV. "Add it to the gallery" is not
  executable for those. For each surface choose one and write it down: a leaf
  golden over a representative widget, or a documented no-golden with a manual
  device pass.
- **`contrast_audit_test.dart`** — extend, knowing its limits: it keys sites by
  label *and current ink*, so a site whose ink correctly changes gets a new key,
  and missing baseline keys are skipped (`contrast_audit_test.dart:68`). It loops
  themes only — not brightness presets, layouts, or IPTV styles. It proves the
  tokens are sound, **not** that the surface is done.

## What this does not fix

Phase one's themed surfaces still carry ~340 hardcoded whites (Settings 118,
merged details 59, Cloud 55, Home/Search/Discover 46, Addons 27, Calendar 17,
rest 13), and Classic details adds ~122 more while already being live. They are
invisible on all 18 selectable themes and are the sole reason `broadsheet` and
`concrete` are withheld (`detail_theme_page.dart`).

Phase two neither needs nor touches them — but note the coupling: **re-enabling
the light themes needs phase one's whites, Classic details, *and* every surface
phase two lands to be clean.** The scheduled surfaces add 602 white-lines to that
debt.

Either way there is a live consequence today: hardcoded whites ignore Text
Brightness, so Soft and Dim are already partially inert. Worth a device look
before deciding it doesn't matter.
