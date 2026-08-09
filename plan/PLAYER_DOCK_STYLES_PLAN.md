# Player Dock Style, Palette & Density — Dart player (rev 12 — AS BUILT)

> **Re-based on `b525f2dc`** ("Improve player battery efficiency and renderer
> fallback"), working tree clean, in sync with `origin/tvos_port`. All line
> numbers below are against that commit. The re-base changed one thing that
> matters: **`Controls` no longer takes `duration`/`position` — it takes
> `clock` (`ValueListenable<PlaybackUiClockValue>`) and its seek row rebuilds
> inside a `ValueListenableBuilder` (`controls.dart:11,80,309-320`).**

## 0. Status — shipped, and where the build diverged

Built and pushed as `43142f25` (the dock) and `3b4ea443` (selectable
arrangements + the wide rebuild), on top of `b525f2dc`. `flutter analyze lib
test` is clean; 24 dock tests pass; the suite is at 2250 with 9 pre-existing
`series_parser` failures untouched by this work.

Rev 1–11 were reviewed against the plan. Implementation then contradicted the
plan in ten places, every one deliberate. **Where this section and the sections
below disagree, this section is what the code does.**

| Plan said | Code does | Why |
|---|---|---|
| One styled dock (`two_tier`), arrangement chosen by viewport | **Five styles**: Classic · Adaptive · Compact · Two-Tier · Cinema. A forced arrangement degrades to the viewport's pick, then to Classic | Three of the four mock concepts were the same widget at different widths — correct for layout, wrong for the user, who got no say on a wide window |
| Pref values `classic`, `two_tier` | `classic`, `auto`, `compact`, `tiers`, `cinema`; **`two_tier` still accepted on read** and resolves to `auto` | Installs that chose the styled dock must keep it |
| `dockExtent` seeds to the full viewport height to over-protect | **Seeds to 0**, so `_dockBand` yields each consumer's legacy constant | Over-protecting the whole screen killed every gesture until first measurement, and stranded the fallback case where no reporter is ever mounted |
| All six consumers read one notifier, classic included | **Classic keeps its literals**; the notifier is styled-only, with a branch at each of the six sites | One scalar cannot simultaneously be `160/28`, `72` and `80`. The uniform path did not exist |
| `aurum` is the only palette with dark primary ink | **`aurum` and `ice`** | `ice`'s hot end `0xFF7BF1FF` is light enough to need it. Caught by the Phase A test, not by review |
| PiP lives in the tools row | **Top bar**, as legacy does | The tools row disappears under `hideOptions`, which lost PiP entirely |
| `DockMetrics.compute` checks a vertical budget | Checks **vertical and horizontal** | Nothing verified transport + More fit side by side; `large` on a 320lp viewport overflowed by 14px |
| `wide` reuses the two-tier tree | Its own zoned row: transport · **volume** · `pos / dur` \| title + subtitle \| icon-only tools · **fullscreen** | The shipped version was the design's skeleton with half its content missing |
| Scrub fill runs `deep → hot` | A custom `GradientSliderTrackShape` | Material's `SliderThemeData` takes a flat `Color`; the plan asserted something the framework cannot do |
| Aspect labels from a four-value switch | `AspectModeUtils.aspectModeToString` | The real `AspectMode` has ten values |

Two additions with no plan entry at all: a **volume** control (new `_dockVolume`
state mirrored to `_player.setVolume`, starting at 1.0 rather than reading the
player's real level) and a **fullscreen** button gated to Windows/Linux, where
`windowManager` actually drives it. The mock showed fullscreen everywhere; the
mock was wrong.

## 1. Goal & scope

`PLAYER_GUIDE_STYLES_PLAN.md` §1 deferred the Dart `Controls` dock because the
native dock already had a live-restyle mechanism and the Dart dock had none.
This builds that mechanism.

**In scope:** `controls.dart` (top bar, seek row, control row, `infoPanel`
mounting); three prefs; one Appearance row + picker page; the pref read in
`VideoPlayerScreen`; the dock↔host geometry contract.

**Out of scope:** `TvControls` and the native Android TV player; app-theme
integration (`kStillFrozenPaths` at `source_guard_test.dart:35-38` already
covers `lib/screens/video_player/`); the IPTV zap banner / channel sheet /
track and source sheets (owned by `player_guide_style`); backup and remote
export (appearance prefs are not in the payload — `backup_restore_service.dart:20`).

### 1.1 Defects being fixed

1. **Hit targets fail everywhere.** `NetflixControlButton` ≈ **28px** tall
   (16px icon + 6px padding) vs Apple 44pt / Material 48dp. All 15 call sites
   pass `isCompact: true`; there is no non-compact path.
2. **No viewport response.** `controls.dart` never reads `MediaQuery` size.
3. **`0xFFE50914` in four places** — fill `netflix_control_button.dart:36`
   (at `.withOpacity(0.9)`), border `:41` (opaque), `activeTrackColor`
   `controls.dart:333`, `thumbColor` `:340`.
4. **No hierarchy, invisible overflow.** 15 chips in a bare
   `SingleChildScrollView`; Play/Pause drifts as conditional controls appear.

### 1.2 Prefs

| Pref | Key | Values | Default |
|---|---|---|---|
| Style | `player_dock_style` | `classic`, `auto`, `compact`, `tiers`, `cinema` (+ legacy `two_tier` → `auto`) | `classic` |
| Palette | `player_dock_palette` | `ultraviolet`, `crimson`, `aurum`, `ice` | `ultraviolet` |
| Size | `player_dock_size` | `auto`, `small`, `medium`, `large` | `auto` |

Palette and size are **inert under `classic`**; their rows render disabled
with the hint "Applies to control styles other than Classic", and stored
values are preserved so switching to Two-Tier restores prior choices.

## 2. Contract

**Preserved, asserted by test (§7.4):**
- Every existing `Controls` callback stays reachable and fires with identical
  arguments. **No callback added or removed by this plan.** The baseline is
  `Controls` as of `b525f2dc` — note that commit itself removed `duration` and
  `position` and added `clock`, so parity is measured against the *new*
  signature, not the one rev 1–9 were written against.
- Seek, scrobbling, PiP, auto-hide, gestures, zap ladder, playlist nav:
  untouched.
- `classic` is a verbatim legacy subtree the styled path cannot enter. It
  **does not participate in the footprint contract** — every host consumer
  keeps its literal constant on that branch (§5.4).

**Changed under `two_tier` only — the complete list:**
1. New `DockOverflowSheet` — a new modal route with new focusable rows.
2. Tooltips + hover states on pointer devices.
3. Control grouping and order (§3.2). No control dropped.
4. Dock height becomes variable (§5).
5. **Guide/Channels disambiguated** — control #7's label changes from
   "Guide" to "Channels". Callback unchanged.
6. **Rotate is hidden off-phone.** Today it is unconditional and meaningless
   on desktop. This is the one place a control becomes *unreachable* on some
   platforms, so §2's parity claim is scoped: "reachable under `two_tier` on
   every platform where the action is meaningful". Classic keeps it
   unconditional.

**Also changed, discovered during implementation:**
7. `wide` carries a **volume** control and a **fullscreen** button
   (Windows/Linux only). Neither existed in `Controls` before; both are new
   parameters with classic-safe defaults.
8. The top bar drops its title in `wide` — but only when the centre zone will
   actually render it, since `hideOptions` removes the controls row and would
   otherwise lose the identity from both places at once.

**Not in v1:** ±10s buttons — they need a callback `Controls` does not have
(only `onSeekBarChanged(double)`), and double-tap already seeks. See §9.

## 3. Design

### 3.1 One style, three arrangements

**Adaptive** selects its arrangement from **width and height** at build time;
the other three styles force one. A forced arrangement is a preference, not a
promise — `cinema` on a short window cannot seat two rows, so it degrades to
the viewport's own pick, and only if that fails too does the dock render
`classic`. The pref never changes; rotating or resizing re-picks.

| Arrangement | Selected when | Shape |
|---|---|---|
| `narrow` | width < 600lp **or height < 480lp** | **one row**: transport · 3 contextual tools · **More**, scrubber above |
| `regular` | width 600–1079lp and height ≥ 480lp | **two tiers**: centred transport above scrubber, tools tier wraps below |
| `wide` | width ≥ 1080lp and height ≥ 480lp | edge-to-edge scrubber; zones — transport+time / title / icon-only tools + tooltips |

**The height gate is the fix for rev 3's blocker #1.** Two tiers cost two
target-heights; a 360lp-tall viewport cannot afford that at any density. Rev 3
assumed `599×360` was a two-tier case and then tried to cap it — the cap was
arithmetically impossible. `narrow` is a *single* row, so that viewport was
never a two-tier case to begin with.

### 3.2 Control mapping

All 15 controls from the horizontal `SingleChildScrollView` row at
`controls.dart:386-530`, existing guards transcribed unchanged. Count
re-verified after the re-base: still 15 `isCompact: true` call sites, and
still four `0xFFE50914` literals (`controls.dart:336,345`;
`netflix_control_button.dart:36,41`).

| # | Control | Guard | Group |
|---|---|---|---|
| 1 | Previous | `hasPrevious` | transport |
| 2 | Play/Pause | always | transport (primary) |
| 3 | Next | `hasNext` | transport |
| 4 | Audio & Subs | always | tools |
| 5 | Episodes | `hasPlaylist` | tools |
| 6 | Guide | `hasGuide && onShowGuide != null` | tools |
| 7 | **Channels** | `hasIptvChannels && onShowIptvChannels != null` | tools |
| 8 | Sources | `hasStremioSources && onShowStremioSources != null` | tools |
| 9 | Record | `hasRecord && onRecord != null` | tools |
| 10 | Next Channel | `hasNextChannel && onNextChannel != null` | tools |
| 11 | Speed | `!hideSpeed` | tools |
| 12 | Sleep | always | tools |
| 13 | Aspect | always | tools |
| 14 | Random | `!hideRandom` | tools |
| 15 | Rotate | **`showRotate`** (new param, see below) | tools |

Top bar: Back `!hideBackButton` (`:236`); PiP
`showPipButton && onPip != null` (`:277`). `infoPanel` at `:297`, **outside**
the `if (!hideOptions)` guard at `:299`; seek row inside `if (!hideSeekbar)`
at `:309`. All preserved.

**`showRotate` is a new `Controls` param**, defaulting `true` so classic is
unchanged. `VideoPlayerScreen` passes `PlatformUtil.isPhone`. `Controls` must
**not** read `PlatformUtil` itself — that is what makes §7.4 testable on a
desktop test host, which was rev 2's contradiction.

**Active states:** exactly two — `isRecording` (#9) and
`sleepTimerLabel != null` (#12).

### 3.3 Contextual selection — availability priority, not mode

Rev 2 assumed an `isLive` input. **`Controls` has none**, and the guards are
independent: live IPTV can have Channels without Guide; playlist VOD usually
has Episodes without Sources; single-file VOD has neither. Mode-based mapping
collapsed to two buttons in all three cases.

Replacement — a fixed priority order, take the first **3 available**:

```
Record(9) → Guide(6) → Channels(7) → NextChannel(10) → Episodes(5)
          → Sources(8) → Subs(4) → Aspect(13) → Sleep(12)
```

**Next Channel sits fourth**, immediately after Channels. Rev 3 omitted it
entirely: a session whose only special guard is `hasNextChannel` would have
promoted Subs/Aspect/Sleep and buried its one session-specific action in the
sheet — the exact inversion this order exists to prevent.

Record and Guide lead because they are the most session-specific and least
reachable elsewhere. Subs sits mid-list rather than first: it is *always*
available, so leading with it would waste a slot that a rarer control needs.
**Subs, Aspect and Sleep are unconditional**, so the tail guarantees three are
always found — the "collapses to two" failure is impossible by construction.

The overflow sheet lists **every** available control including the promoted
three, so it is never a subset the user must reason about.

### 3.4 Fitting — collapse ladder and vertical budget

**Horizontal**, applied in order until the row fits:

1. Labels on contextual chips → **icon-only** (tooltip + `Semantics` retained).
   More keeps its label.
2. `gap` → `gap × 0.75`.
3. Contextual three → two.
4. Last resort: tools row scrolls horizontally **with an edge fade** (today's
   silent clipping is defect #4 — a fade is the minimum acceptable form).

**Vertical.** The flat 45% cap is gone — it was an invented constant that
could contradict a pinned density. Replaced by a budget that accounts for
*everything else in the column*, since the top bar shares the same
`spaceBetween` column as the dock (`controls.dart:225-289`):

```
reserved = safeAreaTop + safeAreaBottom + topBarH + infoPanelH
         + 56 + gaps(1.55)      // worst-case k, not current k
budget   = viewportH − reserved
rows     = (arrangement == regular || wide) ? 2 : 1
                 // `wide` lays out ONE zoned row, so rows=2 deliberately
                 // over-reserves by one row. Intentional: wide viewports have
                 // height to spare, and a single conservative rule is worth
                 // more than a third branch. Revisit only if a real wide
                 // viewport is ever rejected.
fitK     = budget / (rows × 44)              // UNCLAMPED
k        = min(requestedK, fitK, 1.55)
```

- **`gaps` is evaluated at `k = 1.55`, not at the current `k`.** It scales
  with density, so using the live `k` makes the equation circular.
  `scrubberH` does **not** scale — it is a fixed 56lp bound, so it needs no
  worst-case evaluation. Taking the worst case makes the test conservative and solvable in
  one pass.
- **A pinned size is an upper bound that degrades.** `large` asks 1.50 and
  gets it wherever there is room; on a cramped viewport it scales down rather
  than overflowing. Rev 3 treated the pin as absolute, which is what made its
  worst case unsatisfiable.
- **`fitK` is computed unclamped**, so the `fitK < 1.0` case is real: one 44lp
  row does not fit, and `two_tier` **falls back to `classic`**. Rev 4 clamped
  to ≥ 1 and then asked whether it was < 1, which could never be true.
- `infoPanel` is measured, never collapsed — it carries live channel identity.
- **The overhead terms are constants, not approximations.** Rev 5 wrote
  `≈30`/`≈25` without defining them, which is not an executable contract:

  | Term | Bound at k = 1.55, text scale 1.3 | Composition |
  |---|---|---|
  | `scrubberH` | **56lp**, fixed — never scaled | rev 6 said 34, which is not a bound — an unconstrained Material `Slider` still claims ~48lp alone — it survives the
re-base, now inside the `ValueListenableBuilder` at `controls.dart:309-375`. The styled dock builds its own scrub row and **must explicitly constrain it**; 56 bounds that row plus time labels at scale 1.3. It is a **fixed worst-case constant**, not a function of the live `textScale` — `textScale` is an input to `DockLayoutInput` for the *label-fit* checks in §3.4's collapse ladder, not for this bound |
  | `gaps` | **38lp** (`narrow`) / **50lp** (`regular`, `wide`) | rev 6's 26/38 was arithmetically wrong: dock padding alone is `2 × 8 × 1.55 = 24.8`, plus one `8 × 1.55 = 12.4` inter-row gap = 37.2 → 38. Two tiers add a second gap → 50 |
  | `topBarH` | **72lp** | a `static const`, not an input. The current top row is the *max* of its 48lp `IconButton` and the title/subtitle column, not their sum (`controls.dart:234-289`), so 72 over-reserves |

  All three are upper bounds, so the budget can only under-estimate available
  room, never over-estimate it.

Worked worst case — `599×360`, `large`, full-EPG `infoPanel`, zero insets.
`narrow` (height < 480) so `rows = 1`:

```
reserved = 0 + 0 + 72 + 100 + 56 + 38 = 266
budget   = 360 − 266 = 94
fitK     = 94 / 44 = 2.14
k        = min(1.50, 2.14, 1.55) = 1.50    → a 66lp row inside 94lp
```

Fits. Rev 6's version used the superseded `56/30/25` figures and is replaced.

**There is no fixed minimum viewport — the boundary is computed.**

Rev 6 declared `320×320`, which round 6 showed is not generally supportable:
with a full-EPG panel and 60lp of insets, `72 + 100 + 56 + 38 + 60 = 326`
exceeds 320 outright. A fixed number cannot express a boundary that depends on
insets, panel content and text scale.

The rule instead: **`two_tier` renders iff `fitK >= 1`**, evaluated per build
from the real inputs. Otherwise `DockMetrics.compute` returns null and the
dock renders `classic`. §7.5 asserts *"either styled fits, or it cleanly falls
back"* — never "no overflow at size X", which rev 6 could not have satisfied.

**The sub-boundary overflow is pre-existing and configuration-dependent.** At
240lp with a full-EPG panel `classic` cannot fit either — ~100lp panel + 32
padding + 48 slider + 16 gap + ~28 controls + 48 top bar exceeds it
(`controls.dart:225-305`, `:320-385`). But rev 6's blanket "below ~320 the
player already overflows" was too broad: near 300lp with zero insets and a
bare panel it may fit. Stated correctly: *in some configurations — notably
full EPG and/or large safe-area insets — the current player already overflows
below roughly 320lp of height.* Deferral stays defensible because sub-boundary
styled layouts fall back to the byte-preserved classic path, so this feature
never makes those configurations worse. Recorded in §9.

### 3.5 Palette — 14 tokens

`hot`, `deep`, `specular`, `glow`, `tick`, `activeFill`, `activeEdge`,
`onPrimary`, `chipFill`, `chipEdge`, `ink`, `inkDim`, `inactiveTrack`,
`scrim`.

| Palette | hot → deep | onPrimary |
|---|---|---|
| `ultraviolet` | `0xFFFF3DA6` → `0xFF6D2BFF` | white |
| `crimson` | `0xFFFF3A52` → `0xFFB00418` | white |
| `aurum` | `0xFFFFE7A3` → `0xFFC1861A` | `0xFF2A1B00` |
| `ice` | `0xFF7BF1FF` → `0xFF0A5CFF` | `0xFF00203D` |

**`aurum` and `ice` both carry dark ink on the primary** — a real branch;
hardcoding white ships an invisible glyph. `ink`/`inkDim`/`scrim` are
near-identical across palettes by design: the dock stays dark over video.

**Record red `0xFFF43F5E` is not a palette token — and does not exist today.**
`controls.dart:458` only swaps icon and label. Introducing it is a **new**
treatment, scoped here deliberately, identical in all four palettes.

**Primary paint — two layers.** A single `BoxDecoration` cannot composite a
linear gradient with a radial hotspot. Outer `Container` carries
`LinearGradient(hot→deep)` + `boxShadow: [tight, wide]` from `glow`; an inner
`DecoratedBox` carries `RadialGradient` at 28%/12% for the hotspot; `specular`
is a 1px top `Border`. Scrub fill runs `deep → hot` so the leading edge is
brightest. No `Opacity`, no `BackdropFilter` (the dock repaints per position
tick).

### 3.6 Density

```
base    = { icon 20, label 12, target 44, padX 10, padY 8, gap 8, radius 10 }
widthK  = lerp(1.00 → 1.55) over width  600 → 2200 lp, clamped
heightK = lerp(1.00 → 1.35) over height 360 → 1200 lp, clamped
k       = (size == auto) ? min(widthK, heightK) : size.requestedK
          // then bounded by §3.4's fitK
target  = max(44, 44 × k)        // floor; no override may breach it
```

`auto` is responsive. `small`/`medium`/`large` **request** k of
`1.00 / 1.25 / 1.50` — a request the vertical budget in §3.4 may reduce, never
raise. They are upper bounds, not absolutes; rev 4 said they "ignore the
viewport", which contradicted §3.4's own degradation rule. What distinguishes
them from `auto` is that they do not grow with viewport width, which is the
point: `medium` on a 4K desktop stays at 1.25 where `auto` would reach 1.55.

**Text scale.** `main.dart:540-552` clamps the platform scaler to 1.3 and
Android's curve is **non-linear** (`:545`). Feed `label` as an unscaled base
`fontSize`; never pre-multiply. Because scaled labels change *which chips
fit*, this is a widget-level assertion, not a metrics unit test (§7.5).

## 4. New files

`lib/screens/video_player/widgets/dock_style.dart` — `PlayerDockStyle`,
`PlayerDockPalette`, `PlayerDockSize`, `DockArrangement`, `DockPalette` (14
tokens), `DockPalettes.of`, and:

```dart
@immutable class DockMetrics {
  final double k, icon, label, target, padX, padY, gap, radius,
               trackHeight, knob;
  /// Pure — unit-testable with no widget tree. Takes everything §3.4's
  /// budget needs; rev 4's `(Size, PlayerDockSize)` signature could not
  /// produce the resolved k because it knew nothing of the arrangement,
  /// the insets or the info panel.
  /// Null when the viewport cannot seat a 44lp row (fitK < 1) — the caller
  /// then renders `classic`. An explicit result, not a k < 1 sentinel.
  static DockMetrics? compute(DockLayoutInput input);
  static DockMetrics? of(BuildContext, PlayerDockSize,
      {required double infoPanelH});   // topBarH is the §3.4 constant, not a param
}

@immutable class DockLayoutInput {
  final Size viewport;
  final EdgeInsets safeArea;
  final DockArrangement arrangement;
  final double infoPanelH;      // measured (two-pass, see §5.3)
  final double textScale;       // label-fit checks + panel signature only;
                                // does NOT feed scrubberH, which is fixed
  final PlayerDockSize size;
  /// §3.4's fixed bounds. Constants, not fields — rev 6 left `topBarH` an
  /// arbitrary input while claiming it was not a parameter. Tests assert
  /// against them (§7.7); they are not injectable, since a `static const`
  /// cannot be overridden.
  static const double topBarH = 72;
  static const double kInfoPanelBound = 200;
}
```

`dock_widgets.dart` — `DockChip`, `DockTransportButton`, `DockOverflowSheet`,
`DockExtentReporter`, and **`GradientSliderTrackShape`**: Material's
`SliderThemeData` accepts a flat `Color`, so painting the `deep → hot` fill
with its bloom needs a custom track shape, which also derives its bounds and
gradient direction from `textDirection` (taking left-to-thumb showed a full
bar at position 0 under RTL).

`styled_dock.dart` — the `two_tier` widget itself, with the three arrangements
and the availability-priority selector.
Built fresh: `TracksSheet` is a monolithic static `show` (`tracks_sheet.dart:44`,
modal at `:136`) with no reusable chrome widget.

## 5. Dock↔host geometry contract

### 5.1 The problem

**Six** host behaviours assume a fixed dock height:

| Consumer | Constant | Where |
|---|---|---|
| Skip-segment button | `160` when visible && (TV \|\| !hideOptions), else `28` | `video_player_screen.dart` skip `AnimatedPositioned` |
| Single-tap toggle | `72` | `gesture_helpers.dart:6` (`isInBottomArea`, used by `shouldToggleForTap:22`) |
| Double-tap seek | `const bottomBar = 72.0` | `video_player_screen.dart:9165` |
| Pan start | `const bottomBar = 72.0` | `video_player_screen.dart:9199` |
| **Long-press speed** | `const bottomBar = 72.0` | `video_player_screen.dart:9532` |
| **PikPak retry overlay** | `Positioned(bottom: 80)` | `pikpak_retry_overlay.dart:18-20`, mounted in the player stack |

Rev 2 named two of these; rev 3 named five and mislabelled one; rev 4 added the sixth. Updating
`isInBottomArea` alone leaves double-tap seeking, panning and long-press speed
live behind a tall dock.

### 5.2 Measurement boundary and coordinate space

**Boundary:** the `Column` at `controls.dart:294-534` — the unit that starts
with `if (infoPanel != null) infoPanel!` (`:297`) and ends after the control
row. Rev 3 cited `:302-532`, which begins *inside* the options container and
so excluded the info panel entirely — the one part of the dock most likely to
make it tall.

**Coordinate space:** one published value, `dockExtent`, defined as
*the distance from the **screen** bottom to the top of that Column*, measured
in the full-screen host's coordinate space. That is deliberately the space the
gesture handlers already work in: the screen's outer `SafeArea` is
`bottom: false` (`video_player_screen.dart:9723-9727`), so gesture `dy` values
run to the physical bottom. Defining the value this way means any bottom inset
below the Column is already inside it, and the four gesture sites need no
adjustment beyond swapping their constant.

**The skip button is the exception** — it wraps itself in its own bottom
`SafeArea`. It must use `dockExtent − MediaQuery.paddingOf(context).bottom`,
or it double-counts the inset. This is stated on the notifier's doc comment,
because it is exactly the kind of thing that is guessed wrong.

### 5.3 Publication

`ValueNotifier<double> dockExtent`, owned by `_VideoPlayerScreenState`,
**live only while a styled dock is mounted**.

- **Seeded to the full viewport height**, and re-seeded on every
  geometry-affecting mutation, not only viewport changes. Rev 5 reseeded on
  viewport change alone, which left the dock able to *grow* at constant
  viewport size. The complete invalidation list: viewport change (rotation,
  resize, split-screen); **safe-area/padding change independent of viewport
  size**; **`TextScaler` change** (it feeds label-fit and the panel signature); `infoPanel`
  mounting, unmounting or gaining now/next rows; `hideOptions` or
  `hideSeekbar` toggling; arrangement change; density change; **dock-style
  change or styled-dock mount/unmount**. **Every entry on this list — the
  whole list, not the three named in rev 7 — increments the generation
  counter** — rev 6's parenthetical
  named only style/arrangement/viewport, which allowed stale callbacks after
  an info-panel, density or flag change. Any of these reseeds to full height before the next layout, so the
  band is never briefly shorter than the dock. Rev 4 seeded
  `max(160, h × 0.5)` and called it an upper bound; it is not, since the dock
  has no half-height cap any more, and the under-protection recurred on every
  resize rather than only on the first frame. Full height is the only value
  that is *provably* an over-estimate. Cost: at most one frame in which a
  gesture near the bottom is ignored.
- Published from a post-layout callback, **never during layout**.
- **Ownership.** `Controls` is stateless (`controls.dart:7`) and stays that
  way; `_VideoPlayerScreenState` owns both the `dockExtent` notifier and the
  cached `infoPanelH`. That is the correct owner because it already *builds*
  the panel (`_buildIptvInfoPanel`), so it knows when the panel's geometry
  changes without introspecting an opaque widget.
- **`infoPanelGeometryGeneration`** — an `int` on the host, a signature, not just a
  structure counter. It changes on: mount/unmount; guide-style change; **any change to the
  structural row mask** — `{ now, times, next, group, channelNumber,
  recording }`. Rev 9 tracked only now/next, but Glass adds a metadata row on
  `times != null || (group != null && group.isNotEmpty)`
  (`iptv_zap_banner.dart:463`), so switching between two guideless channels
  where only one has a `group` grows the panel with no reseed. The mask is
  presence-of-row, not content — text changing within a row cannot alter
  height, since every row is bounded to one line; **viewport width** (the panel scales via `s(width)`
  and switches layout at 640lp — `iptv_zap_banner.dart:70,96`); and
  **`TextScaler`**. Rev 8 tracked only structure and style, so the cached
  height could under-reserve on the first frame after a resize or a font-size
  change. The one-second clock rebuild
  (`video_player_screen.dart:9090`) is deliberately excluded.
  The measurement callback **captures the panel generation and re-checks it
  before writing the cache**, so a late callback cannot overwrite a newer
  measurement. On a generation change the cache resets to
  **`panel == null ? 0 : kInfoPanelBound`** — rev 8 reset to the bound on
  *unmount* too, which would have reserved 200lp for a panel that is not
  there and could reject a styled layout outright, with no subsequent panel
  measurement to correct it. The one-second rebuild that must **not** touch it is
  **`_iptvZapTicker`** (`video_player_screen.dart:561`, cancelled/restarted
  around `:9090`), which repaints the panel's programme progress every second.
  Rev 9 named the playback-clock `ValueListenableBuilder` instead, which is a
  different timer and not the one that would have thrashed the cache. Neither
  touches it, so a ticking programme timer cannot reset the cache to 200 every second
  — which is what rev 7's unspecified protocol would have done.
- **`infoPanelH` acquisition is a two-pass contract.** `DockMetrics.compute`
  needs a measured panel height, but measuring it requires a layout.

  **Pass 1** lays out with `kInfoPanelBound = 200lp`. Rev 7 used 120, derived
  from the ~100lp *classic* panel at width 599 — but the panel renders in any
  `PlayerGuideStyle` (`video_player_screen.dart:9678`), and Edition at width
  ≥ 960 with text scale 1.3 already reaches ~132lp
  (`iptv_zap_banner.dart:569`). 120 could therefore *under*-reserve, which is
  the one thing pass 1 must never do. 200 is chosen to clear the measured
  maximum with margin, and **`dock_info_panel_bound_test.dart` (§7.7) measures
  the real maximum across all four guide styles × text scales 1.0/1.3 ×
  widths 320/599/**639/640**/**959/960**/1440, using the **maximum structural
  fixture** (now + times + next + group + channel number + recording active),
  and asserts it stays under the constant** — so the
  bound is verified, not asserted.

  **Pass 2** publishes the measured height. If it differs from the cached
  value by ≥ 1lp, one re-layout follows. This terminates: the measured panel
  height does not depend on the dock's `k`, so pass 2 cannot feed back into
  pass 1.

  *Note this is a different threshold from the `dockExtent` epsilon in the
  bullet above.* `dockExtent` publishes **every** increase exactly (including
  +0.9lp) because under-protection is a bug; `infoPanelH` follows the **same asymmetric
  rule**: every *increase* updates the cache exactly, and only *decreases*
  under 1lp are suppressed. Rev 8 suppressed sub-1lp changes in both
  directions, which would leave the vertical budget under-reserved by up to
  0.9lp — the same class of bug the `dockExtent` rule exists to prevent.
- **Asymmetric epsilon.** An *increase* publishes immediately and exactly — a
  suppressed `+0.9lp` would leave the protected band shorter than the dock,
  which is precisely the overlap §7.6 forbids. Only *decreases* below 1.0lp
  are suppressed, since over-protecting is harmless.
- **Mounted + generation guard.** The generation counter increments whenever
  the reporting subtree is replaced or invalidated (every entry on the invalidation
  list above, without exception) and is checked immediately before publishing. A
  queued post-frame callback can otherwise outlive its subtree and write a
  stale extent, or touch a disposed notifier.
- The skip button's `AnimatedPositioned` already animates 150ms, so a
  one-frame stale value resolves as a short slide, not a jump.
- **Settled-layout contract.** Even with conservative reseeding, a positioned
  consumer is correct only once layout settles — the skip button animates for
  150ms after any change. §7.6 therefore asserts *no overlap at settled
  layout*, and explicitly tolerates the animation window. Rev 5's unqualified
  "never overlaps" was not achievable with `AnimatedPositioned` in the tree,
  and pretending otherwise would have produced a flaky test.

**Visibility condition.** `controlsVisible && (infoPanel != null ||
!hideOptions)` — **not** the old `!hideOptions` test. `infoPanel` mounts
outside the `hideOptions` guard (`controls.dart:294-300`), so with
`hideOptions: true` a live info panel can be on screen while the old condition
left the skip button at 28lp.

### 5.4 Classic keeps its literals

Rev 4 tried to have all six consumers read one notifier, classic included.
That is impossible: a single scalar cannot simultaneously be `160/28`
(skip), `72` (four gesture bands) and `80` (PikPak). It also required
`Controls` to publish the legacy skip ternary, which it cannot — it receives
neither `controlsVisible` nor `isTelevision`, and is built only on the non-TV
branch.

The contract is therefore a branch, accepted deliberately:

```
final protectedExtent = dockStyle.isStyled ? dockExtent.value : <legacy const>;
```

per consumer, with each deriving its own offset from the shared extent. The
two **positioned** consumers must also honour the §5.3 visibility condition —
`Controls` stays mounted under `AnimatedOpacity` when hidden
(`video_player_screen.dart:10257`), so `dockExtent` remains non-zero and rev 5's
unconditional formulas would have left the skip button floating above an
invisible dock:

```dart
final bottomDockVisible =
    controlsVisible && (infoPanel != null || !hideOptions);
```

The four gesture bands need no such guard — they are already only consulted
while controls are visible.


| Consumer | classic | styled |
|---|---|---|
| Skip button | `controlsVisible && (isTelevision \|\| !hideOptions) ? 160 : 28` — unchanged, including its child `SafeArea` | `bottomDockVisible ? dockExtent + 8 − MediaQuery.paddingOf(context).bottom : 28` (its own `SafeArea` re-adds the inset; subtracting avoids double-counting) |
| Single-tap toggle | `72` | `dockExtent` |
| Double-tap seek | `72` | `dockExtent` |
| Pan start | `72` | `dockExtent` |
| Long-press speed | `72` | `dockExtent` |
| PikPak retry | `80` | `bottomDockVisible ? max(80, dockExtent + 12) : 80` |

Six `if (styled)` branches is more code than rev 4's "one uniform path", and
that is the correct trade: the uniform path did not exist. Classic is
untouched by construction, which is also what makes §7.6 provable rather than
merely golden-tested.

## 6. Wiring

1. **`storage_service.dart`** — three keys beside `_iptvPlayerGuideStyleKey`
   (`:950`); whitelist; unknown → default **on read and write**.
2. **`settings/player_dock_page.dart`** — three sections, modelled on
   `player_guide_style_page.dart`: `Choice` lists, `_firstCardMarker` TV focus
   marker, `AnalyticsService.screenView('player_dock_settings')` in
   `initState` (the precedent emits a screen view at `:73` and **no** event on
   selection). Exports `playerDockStyleLabel`.
3. **`settings_widgets.dart`** — `SettingsRows.playerDock`
   (`Icons.tune_rounded`, "Player Controls", dynamic subtitle).
4. **`settings_screen.dart`:**
   - three futures appended to `_loadSummaries`' `Future.wait` (`:246`). The
     list currently holds **32** entries (`0..31`, highest read `results[31]`),
     so the new ones are **`results[32]`, `[33]`, `[34]`**.
   - three state fields + assignments.
   - `_openPlayerDockPage()` re-reading all three, mirroring
     `_openPlayerGuideStylePage` (`:3832`).
   - **visible row** beside `playerGuideStyle` (`:4275`), gated
     `if (!PlatformUtil.isTelevision)`. Note the gate is **defence-in-depth,
     not the load-bearing fix**: `AndroidNativeDownloader.isTelevision()`
     returns true on tvOS by design (`android_native_downloader.dart:267-275`),
     that value is `results[9]`, and `_isAndroidTv` therefore selects
     `_buildTvLayout` (`:617`) on Apple TV too. Leaving
     `settings_tv_layout.dart` untouched is what actually keeps the row off
     both televisions. Rev 3 had this reasoning backwards.
   - **search entry** in the contiguous Appearance block (~`:1236`), same gate.
   - label/action properties through `_SettingsLayout`.
5. **`settings_tv_layout.dart`** — no change. (`_kMaxCategoryRows = 14` at
   `:243` with rows consuming 0–13 is why adding one is not free.)
6. **`video_player_screen.dart`:**
   - read all three in `_loadPlayerDefaults` (`:3405`), which already runs at
     launch (`:1871`);
   - hold `_dockStyle` / `_dockPalette` / `_dockSize` as parsed enums;
   - pass them plus `showRotate: PlatformUtil.isPhone` and `dockExtent` at the
     `Controls` construction point (the non-TV branch of the
     `PlatformUtil.isTelevision` ternary at `:9804`).

## 7. Verification — what exists, what does not

**Written and passing (24 tests):**

- `test/dock_metrics_test.dart` — the 44lp floor across 9 viewports × 4 sizes ×
  2 inset sets × 3 panel heights; arrangement boundaries either side of both
  gates; the worked `599×360` case; null-instead-of-overflow at `320×240`;
  labels never pre-multiplied; every style's `forcedArrangement`; the legacy
  `two_tier` value resolving to Adaptive; all four palettes, including that
  **two** carry dark primary ink.
- `test/dock_layout_test.dart` — renders the densest possible dock at every
  approved viewport × inset × text scale × size and asserts no overflow; the
  same with a full-EPG panel; each arrangement's distinguishing shape; PiP
  surviving `hideOptions`.

This pair earned its keep immediately: it found three overflows the arithmetic
had approved (no width check at all, the scrubber's time labels against the
`Slider`'s minimum track, and `DockChip`'s own label in constrained rows).

**Not written — the outstanding debt:**

1. **Storage coercion.** The enum parsing is tested; `StorageService`'s
   whitelist and its coerce-on-read-and-write are not.
2. **Classic goldens.** Nothing pins today's dock. The legacy subtree is
   unreachable from `classic` by construction, but nothing would catch an
   accidental edit to it.
3. **Callback parity.** No test proves every control fires the same callback
   with the same arguments as before. Needs capability fixtures (one per
   conditional callback plus an all-enabled case), realistic fixtures for the
   §3.3 selector, and explicit seek start/change/end coverage.
4. **Six-consumer footprint.** No test proves the skip button and PikPak
   overlay clear a taller dock at settled layout, nor that `classic` keeps its
   exact `160/28` ternary and four `72`s.
5. **Info-panel bound.** `kInfoPanelBound = 200` is a reading of
   `iptv_zap_banner.dart`, not a measurement. Needs the render across all four
   guide styles × text scale 1.0/1.3 × widths 320/599/639/640/959/960/1440
   with the maximum structural fixture.

**Not covered by any test, by nature:** whether the dock *looks* right. The
layout tests prove it does not overflow; they cannot tell you the volume
control sits well or the bar reaches the edges. The single defect that most
embarrassed this plan — `wide` shipping as the design's skeleton with half its
content missing — was found by putting a screenshot beside the mock, after
eleven rounds of review had passed the code. Render and look before calling a
visual change done.

## 8. Phases — all shipped

| # | Phase | State |
|---|---|---|
| A | `dock_style.dart` tokens + metrics | done, §7.1 green |
| B | Prefs, picker page, settings wiring | done; Classic still the default |
| C | Footprint contract | done, with the classic-keeps-literals contract of §5.4 |
| D | `regular` | done |
| E | `narrow` + overflow sheet, `wide` | done; `wide` rebuilt in `3b4ea443` |

Codex reviewed the plan nine times and the build twice. The build reviews found
two criticals the plan reviews could not have: a reporter measuring the whole
screen instead of the dock, and a fallback that left the host in styled
geometry with no reporter to correct it.

## 9. Deferred

**The pre-existing, configuration-dependent low-viewport overflow** — in some
configurations, notably a full-EPG info panel and/or large safe-area insets,
the current player already overflows below roughly 320lp of height,
independent of this feature (§3.4). Not a blanket claim: near 300lp with zero
insets and a bare panel it may well fit. Recorded here so it is not mistaken for a regression · ±10s
buttons (needs a new callback; double-tap already seeks) · `rail`
arrangement (conflicts with `infoPanel`, zap banner, skip button) · hover
scrub-preview thumbnails (no frame-extraction path) · retiring
`NetflixControlButton` once classic is no longer default · native TV /
`TvControls` parity · a `platinum` monochrome palette.

## 10. Re-base — completed against `b525f2dc`

Rev 1–9 were reviewed against a tree carrying 666 uncommitted insertions. That
work is now committed and pushed; this section records what the re-base
actually changed.

| Item | Outcome |
|---|---|
| `Controls` parameter list | **Changed.** `duration`/`position` removed, `clock` added (`controls.dart:11,80`). §2's parity baseline and §7.4's fixtures updated |
| Seek row structure | **Changed.** Now a `ValueListenableBuilder` (`:309-320`); the Material `Slider` survives inside it, so `scrubberH = 56` still bounds it — re-confirm by measurement in §7.7 |
| Control inventory | **Unchanged** — still 15 `isCompact: true` |
| `0xFFE50914` | **Unchanged at four** — `controls.dart:336,345`, `netflix_control_button.dart:36,41` (positions moved) |
| `results[32..34]` | **Still correct.** The commit's `settings_screen.dart` change adds only a search-index leaf; the new `android_video_renderer_mode` pref has its own getter and does not join `_loadSummaries` (highest existing index is still `results[31]`) |
| Guard line numbers | Refreshed: `:236` back, `:277` PiP, `:297` infoPanel, `:299` hideOptions, `:309` hideSeekbar |
| §7.3 classic goldens | Safe to capture now — the tree is settled |

The architecture was unaffected. Only the parity baseline and line references
moved.

**Second pass, `3b4ea443`.** `StyledDock` gained `volume`,
`onVolumeChanged`, `showFullscreen`, `onFullscreen`; `_scrubber` gained a
`bleed` variant mounted *outside* the dock's horizontal padding (negative
padding asserts in Flutter, so the edge-to-edge bar cannot be produced by
cancelling the padding — it has to sit outside it); and `PlayerDockStyle`
went from two values to five. §7's outstanding tests are written against this
surface, not the rev-11 one.
