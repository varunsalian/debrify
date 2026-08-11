# Taking the theme layer app-wide — phase one

Status: **plan, not started.** Fifth draft. Two review rounds found nine P0
errors between them; the corrections that changed the *architecture* rather
than the wording are called out inline, because they are the reason this
document is worth reading.

## The containment decision — read this first

Everything else follows from it. **This inverted between drafts** — the earlier
"wrap each migrated screen" shape was wrong twice over, and the reasons are
worth keeping.

**Theme high, freeze the exclusions.** The `AppThemeScope` + its `ThemeData`
sit **above the root Navigator**. Every excluded surface is then wrapped, at its
entry point, in a `LegacyThemeBoundary` that pins today's dark theme.

Why this way round, having tried the opposite:

1. **Pushed routes do not inherit from below.** `Navigator.push` /
   `MaterialPageRoute` do **not** capture inherited themes from the launching
   context (dialogs and sheets do; ordinary routes do not). A boundary placed
   inside `MainPage` would therefore miss every Cloud provider route and every
   pushed Settings and Search child page — they would render root-legacy while
   their parent tab was themed.
2. **The shell is above the tabs.** The `Scaffold`, the shell background, the
   globally-owned `ScaffoldMessenger`, startup overlays, and any dialog launched
   from `MainPageState.context` all live above per-tab boundaries. Wrapping
   "active content + nav" leaves shell-owned snackbars and dialogs legacy.
3. **A screen still cannot wrap itself.** If a `State.build` returns
   `Theme(...)`, that State's own `context` sits above it, so its modal
   launchers capture the wrong theme. Under the inverted scheme this stops
   mattering for included screens, and for excluded ones the freeze wrapper is
   placed by the caller, not the screen.

So the exclusion list becomes an **explicit, enumerable allow-list** —
the player, IPTV/Browse, Stremio TV, Debrify TV, onboarding, launch idents,
Classic details — each wrapped once at its entry point, enforced by a test that
fails if a new excluded entry point appears unwrapped. That is a bounded set of
wrap sites, versus wrapping all 100 in-scope files.

The risk moves accordingly: under the old shape the danger was forgetting to
theme something; now it is forgetting to **freeze** something, which shows up
as an excluded screen picking up a light theme. Hence the allow-list test.

Excluded surfaces carry **~1,275 literal-colour sites across 40 files** and
actively read `Theme.of(context)` — `tv_controls.dart:185` takes
`colorScheme.primary`, as do IPTV filters and Stremio TV — which is exactly why
they must be frozen rather than left to inherit.

**Per-destination map — Foundation's FIRST gate, before boundary placement and
before baseline goldens.** Every index needs an explicit flag; a missed one
means a screen silently changes colour. Taken from the real registry in
`main.dart`:

| # | Destination | Flag |
|---|---|---|
| 0 | inert slot (deprecated old Home) | n/a |
| 1 | Playlist | **frozen (phase one)** ‡ |
| 2 | Downloads | **frozen (phase one)** ‡ |
| 3 | Debrify TV | **frozen** |
| 4 | Real-Debrid | **themed** (Cloud) |
| 5 | TorBox | **themed** (Cloud) |
| 6 | PikPak | **themed** (Cloud) |
| 7 | Addons | **themed** |
| 8 | Settings | **themed** |
| 9 | Stremio TV | **frozen** |
| 10 | WebDAV | **themed** (Cloud) |
| 11 | Premiumize | **themed** (Cloud) |
| 12 | AllDebrid | **themed** (Cloud) |
| 13 | IPTV | **frozen** |
| 14 | YouTube | **frozen** |
| 15 | Home | **themed** |
| 16 | Cloud hub | **themed** |
| 17 | Search | **themed** |
| 18 | Discover | **themed** |
| 19 | Calendar | **themed** |

‡ **Deferred, not decided — and the plan is executable either way.** Playlist
and Downloads are ordinary content screens, so *themed* is the natural reading
and an earlier draft assumed it. But they appear in no other part of this plan
— not the scope list, manifest, steps, goldens or estimate — and their direct
files alone are 3,599 lines / 110 sites before Playlist's rendered
dependencies, which are unmeasured. Quietly marking them themed would have put
an unbudgeted tree inside phase one.

So phase one **freezes them**, which needs no new budget and no new goldens. If
you want them themed, that is a measured addition: re-run
`tool/measure_theme_surface.sh` over both trees, add a step, and price it —
roughly a day for the direct files, more once Playlist's dependencies are
counted. Your call; the plan does not block on it.

Indices 4–6 and 10–12 are the legacy per-provider entry points into what the
Cloud hub (16) now fronts — Cloud surfaces, inheriting its classification.

**Enforcement needs TWO mechanisms, not one.** An earlier draft said
`pushExcluded(...)` would be the only path to an excluded surface. That is
wrong: Stremio TV, IPTV and YouTube are **tab bodies returned directly by
`_buildPage`**, never pushed. So Foundation provides:

- a **tab-boundary factory** the shell uses when building any destination,
  which reads the table above and installs the freeze for excluded indices; and
- **`pushExcluded(...)`** for excluded surfaces that genuinely are pushed
  routes — the player above all, with **13 external `VideoPlayerScreen`
  constructions today: 12 in `magic_tv_screen.dart` and one in
  `video_player_launcher.dart`**.

**A third mechanism is needed for bootstrap surfaces.** Two declared exclusions
pass through neither of the above: **launch idents** are in-route overlays
inside the persistent `AppInitializer`, and **onboarding** (`InitialSetupFlow`)
arrives via `showDialog`. Neither is a tab body nor a pushed route, and during
the launch overlay the root route never changes — so "current tab + top route"
cannot select frozen system bars for them either. Foundation adds a
**bootstrap/excluded-overlay boundary** and a single **active-surface**
signal that all three mechanisms publish to.

A **source-guard test** fails the build on a direct construction of an excluded
screen outside any of the three paths; a hand-maintained allow-list cannot
notice the next one someone adds.

**System-bar ownership reads the active-surface signal** — current tab, top
route, *and* any bootstrap overlay — since an excluded player pushed over a
themed tab changes neither `_selectedIndex` nor the tab flag, and a launch
ident changes no route at all.

## The overlay contract — live, and free

Earlier drafts narrowed this contract to "an open overlay keeps its theme".
That was **wrong once the scope moved above the root Navigator**: dialogs and
sheets then inherit the live ancestor directly, so they restyle whether or not
we want them to, and a test asserting "unchanged" would fail. Defending the
narrow contract would have meant snapshot-wrapping *every* overlay mechanism —
work spent to make the app worse.

So the contract is the straightforward one, and the architecture pays for it:

1. **Everything restyles live**, including already-open dialogs, sheets and
   popup menus. Free, because the scope and its `ThemeData` are above the
   Navigator that hosts them.
2. **Six files use mechanisms that skip local themes** — `showGeneralDialog`,
   `RawDialogRoute` and bare `OverlayEntry`: three loading overlays,
   `search_source_dropdown.dart`, `TvTextField`'s root-navigator entry, and
   excluded `magic_tv_screen.dart`. (An earlier draft said seven and claimed
   they "inherit nothing" — wrong on both counts: the seventh is commented-out
   deprecated code, and with the scope above the Navigator they *do* inherit
   the live root theme. What they lose is any **local** theme between launcher
   and overlay.) So: included root overlays need no helper at all; **excluded**
   overlays need the frozen snapshot; **details** overlays need the live
   wrapper. Inventory and route each to the right one in Foundation.
3. **Overlays launched from an excluded surface must be frozen with it.** The
   freeze wrapper has to enclose the overlay's builder too, not just the
   screen body — see the Classic details note below, which is the hard case.
4. **`LegacyThemeBoundary` shadows BOTH `Theme` and `AppThemeScope`**, not just
   `ThemeData`. A frozen subtree that still sees live tokens is worse than one
   that sees neither.
5. **Snackbars need their own answer.** The `ScaffoldMessenger` is installed at
   the root, and Flutter presents snackbars on the root-most registered
   `Scaffold` — so a snackbar requested by frozen IPTV or Stremio TV code
   renders *outside* its boundary and picks up the app theme. Wrapping the page
   or the snack content cannot theme the `SnackBar` container. Foundation
   picks one: a destination-local `ScaffoldMessenger`, a destination-aware
   shell boundary, or a custom snack host — plus an excluded-snackbar test.
6. **Dynamic local themes need a live wrapper, distinct from the frozen one.**
   Under `legacy`, themed details installs a *local* scope below the Navigator;
   `InheritedTheme.capture` snapshots it, so an open sheet would keep the
   captured detail theme even as its route updates. Two helper flavours are
   therefore required: a **controller-aware live** wrapper for dynamic local
   themes, and a **snapshot** wrapper for frozen legacy overlays. They are not
   the same helper.

**System bars need their own owner.** An `AnnotatedRegion` inside a destination
boundary sits within `SafeArea` and does not cover the bar coordinates, so the
top-level region keeps winning. Ownership is therefore **shell/route level**:
one full-screen region whose style is selected from the active destination's
**route metadata** — explicitly *not* `_selectedIndex`, which does not change
when an excluded route is pushed over a themed tab — independent of where
content boundaries sit. Status
and navigation bar, on tab switch and on pushed routes.

## Scope

**In:** Calendar, Addons, Cloud (incl. WebDAV), Home/Search/Discover and the
home/see-all widgets they render, Settings, and the app shell / navigation
chrome.

Also **in, and previously missed from the manifest: themed (non-Classic)
details** — it already consumes the token layer, but it still needs its cached
`late final _theme` fixed, its own `ThemeBoundary`, its manual modal scopes
converted to the shared helper, and a defined resolution of
`(app_theme, detail_theme, detail style)`. That is a step, not a sentence.

**Out, deliberately, for a later phase:** video player, IPTV/Browse, Stremio
TV, Debrify TV, onboarding, launch idents, native splash — and **Classic**
details (see below).

## What already exists

`DetailTheme`: **56** instance fields, **20** themes (pinned by `detail_theme_test.dart`'s
registry test), delivered by `DetailThemeScope` — a plain `InheritedWidget`,
*not* an `InheritedTheme`. `of` asserts in debug and falls back to Signal in
release; `maybeOf` falls back silently. `fade(color, factor)` exists because
`withValues(alpha:)` replaces rather than composes alpha.

Two themes are light: `broadsheet` (ground `#F3EFE7`, `computeLuminance()`
≈ 0.86) and `concrete` (`#C9C7C1`, ≈ 0.57). Use `Color.computeLuminance()` and
a stated threshold when deriving brightness — not an ad-hoc formula.

`DetailThemes.signal` is today's details page exactly, pinned by
`detail_theme_test.dart`, but only **selected** values — not all 56 fields and
not pixel identity. That is what the golden harness is for.

## Surface manifest

Reproducible via `tool/measure_theme_surface.sh` (checked in, not `/tmp`).
`sites` = `Color(0x` + `Colors.*` + `withValues`. Treat these as **relative
sizing, not a migration-site count**: the regex double-counts
`Colors.white.withValues(...)` and misses `withOpacity`, `Theme.of(...)
.colorScheme.*` and existing token references. Good enough to rank surfaces;
not good enough to price one. The exact per-step file list is produced by
re-running the script over that step's rendered widget tree.

| Surface | files | lines | sites |
|---|---|---|---|
| Calendar | 1 | 1,767 | 122 |
| Addons | 2 | 3,207 | 145 |
| Cloud (incl. WebDAV) | 11 | 22,863 | 761 |
| Settings | 42 | 40,040 | 687 |
| Home/Search/Discover | 1 | 22,982 | 517 |
| — home widgets | 5 | 832 | 43 |
| — see-all widgets | 19 | 7,720 | 162 |
| Shell (incl. `main.dart`, `animated_background`) | 7 | 6,544 | 365 |
| Themed details (incl. `merged_series_detail_screen.dart`) | 12 | 12,762 | 627 |
| **phase-one total** | **100** | **118,717** | **3,429** |
| *(excluded surfaces, for contrast)* | 40 | 33,433 | 1,275 |

Run `tool/measure_theme_surface.sh` with no arguments — the file sets live in
`tool/theme_surface_manifest.txt`, so the table reproduces without undocumented
arguments. **`main.dart` itself is in the shell surface** (3,326 lines, 71
sites): it owns the root theme, the shell Scaffolds, scrims, system bars,
dialogs and snackbar literals. Earlier drafts listed only the four nav widgets.

The manifest must **follow rendered dependencies, not directory names** — the
first two drafts missed WebDAV, the shell chrome, `home_theme.dart` and the
see-all tiles. Before estimating any step, re-run the script over that step's
actual widget tree.

## Compatibility model

The app has at least three looks today, none of them a single accent: details
(Signal, plus `useArtworkAccent`), Home (`home_theme.dart`: `accent #818CF8`,
`chromeAccent #7B5CFF`, `focusGold`, `cardBg`, `highlight`, `danger`), and
Cloud (`CloudTheme`, with category *and* status colours). So compatibility is a
**profile with role mappings**, not one lifted palette.

**One preference, `app_theme`, defaulting to the sentinel `legacy`.**

- `legacy` → chrome renders the compatibility profile; details resolves to the
  existing `detail_theme` preference. Pixel-identical to today.
- Any real theme → every in-scope surface uses it.
- **Write-through on selection:** choosing a real app theme also mirrors the
  matching id into `detail_theme`. Without that, a downgrade to an older build
  silently reverts details to a stale selection, since old builds ignore
  `app_theme`.

**The mapping table is a Foundation deliverable, not an implementation
detail.** A single global `rowHeader`/`cardFill`/`tileFocus` cannot preserve
Home's, Cloud's, Settings' and Calendar's different current values at once, so
`legacy` resolves through **named subprofiles per surface family** (`home`,
`cloud`, `settings`, `calendar`, `addons`, `shell`), each pinning every role to the
literal it replaces. Without that table written down first, the first shared
token silently homogenises legacy rendering and the pixel-identity claim dies.

**Preference failure semantics.** Unknown or removed `app_theme` id → fall back
to `legacy`, never to a random theme. The two writes (`app_theme` and the
mirrored `detail_theme`) are not atomic: write `detail_theme` first, then
`app_theme`, so a crash between them leaves a consistent older-build view.
Selecting `legacy` after a real theme returns details to the **mirrored**
app-theme id, not whatever the user had chosen in the old Details Theme picker
— write-through overwrote it. Accept that and say so in the UI, and **redirect
the existing Details Theme picker to the single app picker** rather than
leaving two controls whose relationship the user has to infer.

**Classic details needs a mechanism, not a label.** Its style is resolved at
runtime *inside* the detail screen, and its modal launchers use the State's
context — which sits above any boundary the screen's own `build` could install.
"Wrap at the caller" does not describe a workable entry point here. Foundation
must specify one: either the detail route is pushed through a factory that
already knows the resolved style, or the screen installs the freeze in a
`Builder` beneath its State and routes every modal launch through a context
taken from below it. Decide before step 5.

**Classic details is excluded and stays excluded.** `_themedBody` is
`_style != 'classic'`, and direct-source series force Classic — so "every
surface, details included" was false in the previous draft. Classic is by
definition the unthemed look; migrating it is a separate decision.

## Foundation (must land before any sweep)

1. **`AppThemeScope extends InheritedTheme`** with `wrap()` implemented, so
   dialogs and sheets launched from a migrated route capture the theme.
   `InheritedTheme.capture()` cannot capture a plain `InheritedWidget` — the
   current `DetailThemeScope` would silently fail here.
2. **`AppThemeController extends ChangeNotifier`**, warmed at startup. The
   details screen's `late final _theme` capture is fixed as part of this, or an
   open route never restyles. Tests: an already-open route **and** an
   already-open overlay both restyle — free, since the scope is above the
   Navigator they inherit from.
3. **`AppTheme → ThemeData` + `SystemUiOverlayStyle` adapter**, applied at the
   above-Navigator scope for themed destinations and by each
   `LegacyThemeBoundary` for frozen ones. Specifics that must be decided here,
   not during a sweep:
   - Brightness = `ground.computeLuminance() > 0.5` → light. State the
     threshold; `broadsheet` ≈ 0.86 and `concrete` ≈ 0.57 both land light.
   - **Build from a RAW `ThemeData`, never from the root one** — the root has
     already been through `_applyTextBrightness`, and re-applying the resolver
     on top would double-apply the preset.
   - Enumerate the full `ColorScheme` + component-theme mapping (dialog, popup,
     switch, slider, selection, scrollbar, divider, disabled, error).
   - **System bars: one full-screen owner at shell/route level**, whose style
     is selected from the ACTIVE destination (themed or frozen). Explicitly not
     an `AnnotatedRegion` inside a content boundary — that sits within
     `SafeArea` and never covers the bar coordinates, so the top-level region
     would keep winning. Replaces the one-time imperative call at startup;
     covers status and navigation bar, tab switches and pushed routes.
4. **Text-brightness composition.** `TextBrightnessController`'s `soft`/`dim`
   are fixed light greys written into `onSurface` after `ThemeData` is built —
   on Broadsheet they are nearly invisible, and token text (`AppTheme.tx`)
   bypasses that Material-only transform entirely. Foundation needs **one
   resolver over `(theme, brightness preset)`** with defined light-theme
   behaviour, and contrast tests across the **cross-product**, not one per
   theme.
5. **Role tokens** the chrome needs: `rowHeader`, `cardFill`, `cardFocus`,
   `heroScrim`, `tileFill`, `tileFocus`. Plus, for Cloud, **separate** roles —
   `statusSuccess`/`statusWarning`/`statusError`, `destructive`, and
   `categoryVideo`/`categoryFolder`/`categorySeason` — each with
   container/foreground pairs. Lumping them into one `status*` set would
   misclassify folders, because `CloudTheme.amber` is *both* the folder
   category and a warning badge. Name for role, never for screen.
6. **Overlay-mechanism inventory and conversion** — the **six** active files
   using `showGeneralDialog`, `RawDialogRoute` or bare `OverlayEntry` (three
   loading overlays, `search_source_dropdown.dart`, `tv_text_field.dart`, and
   excluded `magic_tv_screen.dart`), plus the existing manual modal scopes.
   Routed to **two distinct helpers**, not one: a controller-aware **live**
   wrapper for dynamic local themes, and a **snapshot** wrapper for frozen
   legacy overlays. Included root overlays need neither — they inherit the live
   root theme already.
7. **Tab-boundary factory + `pushExcluded(...)` + bootstrap-overlay boundary +
   source guard**, and the active-surface-driven system-bar ownership — all as specified in the per-destination map
   above. Both mechanisms are required; neither alone covers both tab bodies
   and pushed routes.
8. **Shared-widget boundary policy.** `SeeAllFilterBar` and `StremioDropdown`
   are rendered by excluded IPTV *and* included Search/Addons. Making them read
   the app theme silently themes excluded surfaces. Decide per widget: explicit
   token parameters, a frozen legacy scope at the excluded caller, or promote
   the caller into scope. Enforce with a test that excluded routes render
   legacy regardless of `app_theme`.

## Steps

Hardest surface first, so the vocabulary meets artwork overlays, TV focus,
Material controls and a light theme before 41 settings files commit to it.

0. **Foundation** — everything above, **including the scope above the Navigator
   and the freeze wrappers on every excluded entry point**, plus the golden
   harness. Containment cannot be deferred to step 2: step 1 verifies Home
   under a light theme, which is meaningless if the shell around it is still
   root-legacy. The re-estimate gate therefore needs one migrated light route,
   which means Foundation ends with a thin vertical proof — not with step 1.
1. **Home/Search/Discover + home & see-all widgets** (~722 sites) — one
   complete vertical slice: three modes, phone **and** TV, verified under
   `legacy`, one dark theme, one light theme.
2. **Shell / nav chrome token conversion** (~291 sites) — the *placement* is
   Foundation's; this step converts the chrome's own literals — immediately after, because a light
   page inside unchanged dark navigation breaks the contract more visibly than
   any single screen.
3. **Cloud** (~761 sites). `CloudTheme` is `abstract final` static consts used
   inside `const` expressions (`const BorderSide(color: CloudTheme.accent)`); a
   static cannot read an inherited theme, so it becomes `CloudTheme.of(context)`
   returning a build-local token object, and the affected `const`s are removed.
   Budget those call-site edits explicitly.
4. **Settings** (~687 sites) — theme `SettingsTile` (61 `.spec` calls **plus 25 direct constructions**) and
   `SettingsSection` (40) first, then **re-measure** before touching
   41 files. Focus rings and the TV two-pane rail get their own reviewed pass.
5. **Themed details** — the `(app_theme, detail_theme, style)` resolution and
   the token work. Its cached-theme fix, its boundary and the Classic freeze
   mechanism belong to **Foundation**, not here: the containment gate and the
   excluded-surface test are not truthful until Classic is actually contained.
6. **Calendar, then Addons** (~267 sites) — cheap follow-ons. Addons has ~10
   modal/menu entry points; inventory them.
7. **Wiring, sheet inventory, QA** — one picker; inventory every dialog,
   popup, snackbar and bottom sheet reachable from touched pages.

**Exit criterion per slice is *not* "no new token needed".** That was unsafe:
Home cannot exercise Cloud's category/status semantics or Calendar's. The
vocabulary is allowed to grow in later slices, with back-propagation to
already-migrated surfaces — budget for it rather than forcing unrelated
meanings into existing roles.

## Regression risk

1. **Alpha and layering — largest risk.** ~700 `withValues(...)` calls encode
   scrims over artwork; a wrong one makes text unreadable over a bright poster,
   which no diff shows and no unit test catches. The rule is **preserve the
   composite `legacy` renders** — *not* "never change an alpha", which an
   earlier draft got wrong: tokens already carry alpha (Signal's `panel` is
   `0x12FFFFFF`), so keeping a site's numeric alpha while swapping an opaque
   colour for a translucent token silently changes the result. Classify tokens
   overlay-vs-surface; use `fade()` for proportional dimming.
2. **Goldens, not colour asserts.** Asserting a few decoration values cannot
   prove pixel identity for gradients, blends and typography. Golden tests per
   surface under `legacy`, covering bright artwork, focus, disabled controls
   and an open dialog.
3. **Coverage is thin.** No test renders `SearchScreen` at all. Build the
   golden harness in Foundation, before any sweep.
4. **Leakage into excluded surfaces** — mitigated structurally by the freeze
   wrappers on excluded entry points, enforced by the allow-list test.
5. **Blast radius** — one file serves three destinations. Sweep by token in
   separate reviewable commits, never one mixed 500-site diff.

## Naming

`DetailTheme` stops being honest once Settings reads it, but renaming now
churns exactly the files another session is editing. Introduce an `AppTheme`
façade in Foundation that delegates; do the mechanical rename and the move out
of `lib/widgets/detail/` only once both the details work and this contract are
stable, with a shim for old import paths.

## Prerequisite — now satisfied

The details-theme work has **landed** (`bf1ea86`, `e421b15`, `9c1cd07`), so the
token layer this plan builds on is committed and stable. Re-verified against
the committed tree: 57 token fields, 20 themes (registry test), `broadsheet`
and `concrete` still the two light ones, and `DetailThemeScope` still a plain
`InheritedWidget` — so Foundation's `InheritedTheme` upgrade is still required.

Note the tree carries further in-flight work from that session (new premium
detail layouts). It does not touch the token layer, but re-run
`tool/measure_theme_surface.sh` before pricing any step — the detail widget
surface has already grown to 12 files / 627 sites.

## Exit criteria

- `legacy` renders every touched surface identically to today — proven by
  goldens, per surface.
- Every theme, including both light ones, yields legible Material controls,
  dialogs and system bars across every text-brightness preset — proven by
  cross-product contrast tests.
- Changing the theme restyles an already-open route and an already-open
  overlay; the six local-theme-skipping mechanisms render with the right theme
  (live for details, frozen for excluded) — all asserted.
- Excluded routes render legacy regardless of `app_theme` — proven by test.
- Analyzer clean; no new failures against the 9 pre-existing.
- Golden coverage for **every navigation layout** — classic bottom nav,
  floating nav, desktop/tablet sidebar, TV sidebar — not just one.
- Smoke-tested on `legacy`, one dark and one light theme, across **Android
  phone, Android TV and Apple TV** — the two TV shells are separate code paths,
  so Apple TV alone validates neither.

## Estimate

| Step | Cost |
|---|---|
| 0 Foundation (tab classification gate, route factories + source guard, above-Navigator scope, freeze wrappers incl. Classic, live + snapshot overlay helpers, snackbar host, system-bar owner, adapter, text-brightness resolver, compatibility mapping table, golden harness) | 7–9 d |
| 1 Home/Search/Discover slice (~722 sites) | 3–4 d |
| 2 Shell / nav chrome token conversion (~365 sites, incl. `main.dart`) | 2 d |
| 3 Cloud (~761 sites, incl. `const` removal, category/status split) | 2–3 d |
| 4 Settings (~687 sites, 42 files) | 2–3 d |
| 5 Themed details (~627 sites) | 1–2 d |
| 6 Calendar + Addons (~267 sites) | 1 d |
| 7 Wiring, inventory, QA | 2 d + device time |
| **Total** | **20–26 days + device QA** |

**Provisional — do not commit to it.** Successive drafts read 5.5–6, 11–15,
13–18, 17–23 and now 20–26 days. The growth has been entirely the manifest
catching up with what is actually rendered (WebDAV, the shell including
`main.dart`, see-all tiles, themed details) and Foundation absorbing work each
earlier draft assumed away — containment, route enforcement, two overlay helper
flavours, the snackbar host, the text-brightness cross-product, the
compatibility mapping table.

**Foundation is the gate.** It must produce: the complete tab classification,
the route factory + guard, a working boundary with a themed and a frozen
destination side by side, one migrated light route, and the golden harness.
Only then is a total worth trusting. If Foundation runs long, narrow phase one
rather than push through — dropping Settings or Cloud to a later phase is a
much cheaper correction than discovering the model is wrong at 60% coverage.
