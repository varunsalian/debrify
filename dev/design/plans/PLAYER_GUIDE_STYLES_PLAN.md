# In-Player Guide Styles — both players (rev 3, post-Codex round 2)

## 0. Goal

The IPTV guide system inside the video players (zap banner / lower-third,
channel guide sheet, native dock live-restyle, native guide overlay + EPG
pane) looks dated and inconsistent: six unrelated accent systems coexist
(cyan `0x00E5FF`, purple `0x7C5CFF`, Netflix red `0xE50914`, emerald
`0x42E8B4`, gold `0xF5C451`, green `0x48D7A0`). Build **three new premium
looks + the untouched existing one**, switchable in Settings, in **both**
players:

- **Native Android TV player** (ExoPlayer, `AndroidTvTorrentPlayerActivity.kt`)
- **Dart media_kit player** (phones / tablets / desktops, `video_player_screen.dart`)

| Pref value | User-facing name | Identity |
|---|---|---|
| `classic` | Classic | today's look, verbatim code path, **default** |
| `glass` | Cinema Glass | modern streaming premium: deep translucent panels, one restrained violet accent, soft rounded geometry, app default type |
| `edition` | Midnight Edition | First Edition adapted for over-video: ink panels, warm cream type ramp, Fraunces serif titles, hairline rules, italic kickers |
| `console` | Master Control | black instrument: JetBrains Mono time machinery, SpaceGrotesk names, amber accent, squared corners, corner-bracket focus |

Same four styles, same names, same pref on every platform. Pref key:
`iptv_player_guide_style` (independent of the IPTV page's `iptv_style`).

## 1. Scope

**In scope (Dart player):**
- `IptvZapBanner` (both homes: floating overlay + dock `infoPanel` flush variant) — `lib/screens/video_player/widgets/iptv_zap_banner.dart`
- `IptvChannelSheet` (header, now-playing card, search field chrome, filter bar, channel tiles, badges, empty states, keyboard hints, schedule-pane header) — `lib/screens/video_player/widgets/iptv_channel_sheet.dart`
- `EpgScheduleList` gets an **optional nullable `IptvStyleTokens? tokens`**
  (null = literal legacy branch), propagated into `_ScheduleRow`,
  `_EpgRecordChip`, `_EpgTag`, `_EpgProgressBar`, day headers, loading and
  empty states — an accent alone can't cover `fgDim`/`focusTint`/`hairline`/
  `rec`/typography. The IPTV page call sites (iptv_epg_panel.dart:732, 811)
  keep passing null; only the player sheet call
  (iptv_channel_sheet.dart:1224) passes player tokens.
- Pref read in `video_player_screen.dart` (async at init, like `_loadPlayerDefaults`)

**In scope (native player):**
- Zap banner (`ensureIptvZapBanner` + paint fns — fully code-built, token-drive it)
- Dock live restyle (`setupIptvControls` / `arrangeLiveIptvControlDock` — the existing `iptv_premium_*` swap becomes token-driven for styled modes)
- IPTV guide overlay: left panel, nav rail, mode bar, filter bar, channel rows (`IptvChannelAdapter` + `item_iptv_channel.xml`), EPG pane (`IptvEpgAdapter` + `item_iptv_epg_program.xml`), floating now-playing card
- Category picker dialog AND add-to-list picker (`showIptvListPicker` ~7210 +
  `IptvListPickerAdapter` ~7350) — both code-built → same token pass. The
  long-press flow is fully styled, matching the manual checklist.
- Pref read at launch via `FlutterSharedPreferences` (`flutter.iptv_player_guide_style`), same route as `loadPlayerDefaults`

**Out of scope (explicitly deferred, keep legacy in all styles):**
- Debrify-TV `ChannelGuide` (green overlay — different feature, not IPTV)
- `StremioTvGuideSheet` (both players) — separate mode; restyle later if asked
- Dart `Controls` dock itself (seekbar, buttons — Netflix look stays; only its `infoPanel` content restyles). Native dock DOES restyle because its live restyle already exists.
- Native stock `AlertDialog`s (source picker, jump dialog) — legacy in v1
- Any behavioral change: zap ladder, paging, EPG fetching, focus/DPAD wiring, recording, favorites — untouched

## 2. Pref + enum

- `StorageService.getIptvPlayerGuideStyle()/setIptvPlayerGuideStyle()`,
  key `iptv_player_guide_style`, whitelist `{classic, glass, edition, console}`,
  coerce unknown → `classic` on read AND write (mirror `getIptvStyle`).
- New file `lib/screens/video_player/widgets/player_guide_style.dart`:

```dart
enum PlayerGuideStyle {
  classic, glass, edition, console;
  static PlayerGuideStyle fromPref(String raw) => ...; // unknown → classic
  String get prefValue => name;
  bool get isStyled => this != PlayerGuideStyle.classic;
}
```

- **Token type is reused**: `IptvStyleTokens` from
  `lib/widgets/iptv/styles/iptv_style.dart` (13 colors + 4 font families —
  exactly what we need; the page file itself is NOT touched). Three player
  presets live in the new file as statics on `PlayerGuideTokens`:

```dart
abstract final class PlayerGuideTokens {
  static const IptvStyleTokens glass = IptvStyleTokens(
    bg: Color(0xFF0A0C12),
    panel: Color(0xF20E1118),        // translucent over video
    fg: Color(0xFFF2F5FA),
    fgMid: Color(0xCCF2F5FA), fgDim: Color(0x8CF2F5FA), fgFaint: Color(0x54F2F5FA),
    hairline: Color(0x16FFFFFF), hairline2: Color(0x2BFFFFFF),
    accent: Color(0xFF8F7BFF),       // restrained violet — the ONLY color
    rec: Color(0xFFFF4545), live: Color(0xFF34D399),
    selectedTint: Color(0x148F7BFF), focusTint: Color(0x0F8F7BFF),
    // all font families default '' = app font — glass is the "clean" one
  );
  static const IptvStyleTokens edition = IptvStyleTokens(
    // = IptvStyleTokens.edition values with panel made translucent for
    // over-video use: panel 0xF2141110, bg 0xF00D0B09; everything else
    // (cream ramp, hairlines, rec 0xFFE5484D, live 0xFFB8C79B,
    // Fraunces72/Fraunces9 families) copied verbatim from the page preset.
  );
  static const IptvStyleTokens console = IptvStyleTokens(
    // = IptvStyleTokens.console values with panel translucent:
    // panel 0xF50A0A0A, bg 0xF2050505; amber 0xFFF2A93B accent,
    // live 0xFF34D399, rec 0xFFFF4545, SpaceGrotesk/JetBrainsMono.
  );
  static IptvStyleTokens? of(PlayerGuideStyle s) => ...; // null for classic
}
```

- Rationale for translucent panels: these surfaces float over live video;
  fully opaque slabs (page presets) would read as a hard app-switch. Alpha is
  pre-multiplied into the color (house rule: no `Opacity` widgets over video).

## 3. House rules (same contract that shipped `iptv_style`)

1. **`classic` is the verbatim legacy path.** Widgets/functions branch on
   style FIRST; only styled branches read tokens. Classic must be provably
   pixel-identical — no shared expression may change under classic.
2. **Paint-only restyle.** List geometry is untouched in every style:
   Dart sheet `itemExtent` stays 78/72; native rows stay 68dp;
   native EPG rows stay 86dp. No new focusables, no focus-order changes,
   no DPAD/key-handling changes, zero behavior changes.
3. **Each style uses ONLY its token colors** inside styled branches — this is
   what kills the six-accent chaos. No `GoogleFonts.*`, plain `fontFamily`
   strings (fonts already bundled: Fraunces72pt-{Regular,Italic}.ttf,
   Fraunces9pt-Italic.ttf, SpaceGrotesk-{Medium,Bold}.ttf,
   JetBrainsMono-{Regular,Bold}.ttf).
4. **TV perf rules**: no new `BackdropFilter` (the sheet's existing `_frost`
   already skips TV); no shimmer in styled branches; no per-frame work beyond
   the existing 1s zap ticker; pre-multiplied colors instead of `Opacity`.
5. **Native styled drawables are code-built** (`GradientDrawable` /
   `StateListDrawable` from tokens) so `res/drawable/iptv_*` XMLs stay
   untouched for classic. Styled mode never mutates a shared XML drawable
   instance (always `mutate()` or build fresh). **Adapters build drawables /
   apply invariant typefaces ONCE in `onCreateViewHolder`** — bind only sets
   entry-dependent colors/text/visibility/`isSelected`; no per-bind
   allocation during scroll.
6. **Layout XML edits are allowed for ID-adds ONLY** (several style targets
   are anonymous today: nav rail container, D tile, kickers
   view_iptv_channel_guide.xml:164/386, footer hint rows :300/:506, live-dot
   + label item_iptv_channel.xml:119). Legacy dimensions, colors, drawables,
   focusability and child order are byte-for-byte preserved; new IDs get
   ViewHolder/field references — never `getChildAt()` positional access.
7. **Native classic paths are verbatim at function level.** Every restyled
   painter/builder branches FIRST: `if (guideTokens == null) { existing body,
   unchanged } else { styled body }`. No routing of legacy constants through
   token-aware fallback helpers. The 1s EPG repaint (~9520) resets
   colors/typefaces — the styled repaint branch must therefore re-apply
   styled colors itself, never inherit from the classic reset.
8. Native typefaces load once per activity from Flutter assets. Exact map:
   Fraunces72 regular/italic = `Fraunces72pt-Regular.ttf` /
   `Fraunces72pt-Italic.ttf`; Fraunces9 italic = `Fraunces9pt-Italic.ttf`;
   SpaceGrotesk w500/w700 = `SpaceGrotesk-Medium.ttf` / `SpaceGrotesk-Bold.ttf`;
   JetBrainsMono w400/w700 = `JetBrainsMono-Regular.ttf` /
   `JetBrainsMono-Bold.ttf`, all under
   `flutter_assets/assets/fonts/`. Cache = `MutableMap<String, Typeface?>`
   checked with `containsKey` so a load FAILURE is memoized too (null →
   default typeface, no retry per repaint).
9. Style is read ONCE at player launch (both players). Changing the setting
   applies to the next playback session — no live re-theming.
10. Compound-drawable icons on native buttons carry fixed XML `drawableTint`s
    (e.g. view_iptv_channel_guide.xml:63/199/247/266) — styled modes must set
    `compoundDrawableTintList` state-lists alongside `setTextColor`, and the
    styled pass runs AFTER the legacy `premiumButtonIds` loop in
    `setupIptvControls` so nothing overwrites it.

## 4. Design specs

### 4.1 Dart `IptvZapBanner` (floating + flush)

Shared: same `IgnorePointer`, same scale math, same progress semantics, same
"Loading guide…"/"No guide data" states.

New input: **`isRecording`** (default false), passed from
`_buildIptvInfoPanel` with the same combined expression `Controls` already
receives (`_isRecording || _engineTaskId != null || _desktopCaptureForCurrent() != null`
— hoist whatever exact expression sits at the Controls call site ~VPS:9227
into a getter both use). REC treatment: a small `● REC` tag in token `rec`
rendered BESIDE the LIVE tag (never replacing it) in styled modes only;
classic ignores the new param entirely (verbatim paint).

- **classic** — untouched (cyan accent, current scrim, current type).
- **glass** — floating home becomes an **island lower-third**: inset
  card (left 28·bottom 24 at scale 1, max width ~760) with panel fill,
  hairline border, radius 22; logo tile radius follows; channel number in
  `fg` (not accent), name w800; LIVE dot in `live`; progress = 3dp rounded
  pill in `accent`; scrim gradient much lighter (video stays visible).
  Flush home: same content style, no card (transparent, panel provided by
  dock), full-width progress pill.
- **edition** — full-width ink band, hairline top rule; kicker line
  `CH 012 · LIVE · GROUP` in Fraunces9 italic caps `fgDim`; programme title
  in Fraunces72 (bigger than channel name — editorial hierarchy flips:
  the *programme* is the headline, channel name is the byline); cream
  hairline progress (2dp, `fg` on `hairline`); times in small mono-spaced
  figures (`fgDim`, tabular, default family).
- **console** — full-width black strip with 2dp amber left rule; channel
  number `JetBrainsMono` bold `padLeft(3,'0')` in `accent`; name
  SpaceGrotesk; times JetBrainsMono; progress = amber tick meter (reuse the
  page's tick-meter idea: thin track + amber elapsed) with end-time
  after it; `● LIVE` in `live`; REC state (when recording) in `rec`.

### 4.2 Dart `IptvChannelSheet`

All styles keep: layout modes (compact/mid/wide), pane logic, search
semantics, favorites, record flow, list `itemExtent`, focus zones, key
handling, scrim tap-close, slide animation.

- **classic** — untouched.
- **glass** — surface = `panel` (not `_surfaceDark`), border `hairline`;
  header icon tile: accent-tinted rounded square, title stays w700;
  now-playing card: `selectedTint` fill + `accent` hairline; search focus
  glow → `accent`; filter buttons/chips: hairline outlines, selected =
  `selectedTint` + accent text (kills the purple); tiles: focused =
  `focusTint` fill + 1.5 `accent` border (no white gradient), NOW badge =
  accent pill (no pulse animation change — keep the controller, tint only),
  LIVE dot = `live`; sub-line EPG text `fgDim`; keyboard-hint chips hairline.
- **edition** — panel ink; header: kicker `GUIDE` Fraunces9 italic over
  "Live Television" in Fraunces72; hairline dividers instead of tile
  cards (tiles paint only a bottom hairline inside the same extent);
  circle logo chips (the page's edition grammar); focused tile =
  `selectedTint` + left 2dp cream rule; NOW tag = small-caps cream text,
  no pill; times/counts in `fgDim`.
- **console** — panel black; header: `CHANNEL GUIDE` SpaceGrotesk +
  mono count readout; tiles: mono `padLeft(3)` numbers, bracket focus via
  `IptvFocusBracketsPainter(accent)` as `foregroundPainter` on the focused
  tile only, amber reserved for focus/time, LIVE = `live` square tag,
  NOW = amber square tag; search field squared (radius 4); filter
  buttons squared mono uppercase.
- Schedule pane: pass full `tokens` into `EpgScheduleList` in styled modes
  (NOW row highlight, progress tint, day headers `fgDim`, REPLAY/record chips
  `rec`, row focus `focusTint`, empty/loading states). Null = literal legacy
  branch; the page's two call sites stay null.
- Color-mapping table for states the tokens don't name directly (applies to
  BOTH players; channel-logo image content is exempt from the token rule):
  - Favorite star/heart active: glass = `accent`, edition = `fg` (cream),
    console = `accent` (amber). Inactive: `fgFaint`.
  - Letter-avatar fallback tiles: styled modes drop the per-name HSL random
    color → `selectedTint` fill + `fg` letter (calm, uniform premium).
  - LIVE dot/tag: `live`. NOW badge: glass = accent pill, edition =
    small-caps cream text, console = amber square tag. REC anything: `rec`.

### 4.3 Native zap banner (`ensureIptvZapBanner` + paint fns)

Fully code-built → introduce a native **style discriminator + tokens pair**,
both resolved once at launch from the pref:

```kotlin
enum class GuideStyle { CLASSIC, GLASS, EDITION, CONSOLE }
data class GuideTokens(/* Kotlin mirror of the Dart preset hexes */)
// guideStyle: GuideStyle, guideTokens: GuideTokens? (null iff CLASSIC)
```

Colors/fonts alone can't select between three structurally different
builds — styled builders, adapters, and `applyIptvZapBannerMode` branch on
an explicit `when (guideStyle)`; `guideTokens == null` remains the classic
fast-path guard.

**Branching strategy (house rule 7): separate classic and styled painters.**
`ensureIptvZapBanner()` and every paint fn open with
`if (guideTokens == null)` → the EXISTING body unchanged; the styled branch
builds/paints its own tree with its own colors, typefaces, drawables. No
shared color helpers with fallbacks. Because `ensureIptvZapBanner` caches
one tree forever and `applyIptvZapBannerMode` today only shifts margins/hint
visibility, the styled build stores a **`ZapViews` holder** (scrim, card,
body row, logo tile, number, name, LIVE tag, REC tag, programme labels,
progress rule, hint rail) and the styled `applyIptvZapBannerMode(docked)`
explicitly switches backgrounds / insets / scrim visibility / progress
placement on every home change. The styled 1s repaint re-applies styled
colors (the classic repaint resets colors — styled must never fall into it).

**Native REC plumbing:** one predicate
`isRecordingCurrentIptvChannel()` = engine task active for the current
channel || `iptvRecordingController.isActive` (the same truth the Record
button paint uses, ~6173-6189). The styled banner applies REC tag
visibility/color on initial `showIptvZapBanner` AND inside the styled 1s
repaint (ticker runs whenever the banner is visible, so recording-state
changes propagate within a second). Classic: tag never exists.

- **classic** — null tokens: existing builder + painters run unchanged.
- **glass** — island card: body row gains a rounded-22 panel bg
  (code-built GradientDrawable, hairline stroke), lighter scrim; number in
  fg, violet progress; keycap hints re-tinted fg-dim on hairline.
- **edition** — band + top hairline; programme title becomes the largest
  line (Fraunces72 typeface), channel name drops to byline size; cream
  progress; kicker caps line in Fraunces9 italic.
- **console** — amber left rule (4dp view), mono number/time typefaces
  (JetBrainsMono), SpaceGrotesk name, amber progress, `live` green LIVE.

Typeface plumbing: `guideTypeface(name)` cache in the activity;
`TextView.typeface` set only in styled branches.

### 4.4 Native dock live restyle

`setupIptvControls()` currently swaps dock bg → `iptv_premium_panel_bg` and
buttons → `iptv_premium_button_bg`/`iptv_premium_button_text` — but that
runs once at setup, and `restoreCinemaIptvControlStyle()` (VOD) overwrites
every drawable/text color while the return to live only reorders children
(`arrangeLiveIptvControlDock`). **Fix shape: extract
`applyLiveIptvControlStyle()`** containing the current live swap (classic
body verbatim) plus the styled branch, and call it from
`updateIptvControlPresentation()` whenever presentation enters live, after
arranging the dock. Classic keeps today's call graph exactly (the extra
re-style call happens only when `guideTokens != null`, preserving classic
pixel/behavior parity).

**Icon tints + VOD return (styled only):** dock buttons carry compound
drawables tinted by cinema XML selectors (styles.xml:101-154);
`restoreCinemaIptvControlStyle()` restores only backgrounds/text colors.
So: (a) dock `compoundDrawableTintList` styling happens in
`applyLiveIptvControlStyle()`; (b) before first styling, capture each
button's original `compoundDrawableTintList` (post-inflation values); (c) a
styled-only restoration tail after `restoreCinemaIptvControlStyle()`
re-applies the captured cinema tint lists on live→VOD. Classic never runs
any of this — its restore function body stays untouched.

**Tint-pass separation (fact fix):** `premiumButtonIds` tinting lives in
`setupIptvOverlay()` (~6641), NOT `setupIptvControls()` — overlay styled
tints run after that loop in `setupIptvOverlay()`; dock styled tints run in
`applyLiveIptvControlStyle()`.

- **classic** — existing swap untouched, existing call sites only.
- **styled** — same swap points, but backgrounds are code-built from tokens:
  dock = panel fill + hairline stroke (+ radius 22 glass / 8 edition /
  4 console), button state-list = focused `fg` fill + `bg` text (inverse
  chip — the existing cream-on-focus grammar, re-tinted per style), idle
  transparent + `fgDim` text; play button accent-tinted for glass/console,
  cream for edition. Text colors via `ColorStateList` built in code.
  `restoreCinemaIptvControlStyle()` untouched (VOD always returns to
  cinema look in every style).

### 4.5 Native guide overlay + EPG pane

Layout XMLs get **ID-adds only** (house rule 6) so every style target is
reachable; classic values stay byte-identical. In styled modes, a single
`applyGuideStyle()` pass (called once from `setupIptvOverlay`, AFTER any
legacy tinting loops so nothing overwrites it) re-tints in code:

- Panel bgs (`iptv_guide_panel`, `iptv_epg_panel`, now-playing card):
  code-built drawables from `panel`/`hairline`, radius per style.
- Nav rail: bg `bg`; nav item state-list re-built (focused = `fg` fill +
  inverse text — replaces cream/gold XML selector; selected = `selectedTint`).
  Logo "D" tile re-tinted `fg`/`bg`.
- Mode bar: kicker color → `accent` (glass) / `fgDim` italic-serif
  (edition) / `accent` mono (console); title/count → `fg`/`fgDim`;
  source + category buttons re-tinted state-lists.
- Search field: code-built bg (radius 12 glass / 8 edition / 4 console,
  focused stroke `accent`), text/hint `fg`/`fgFaint`.
- Rows (`IptvChannelAdapter`): adapter gets `tokens` + typefaces.
  **`onCreateViewHolder`** applies the invariant work once per holder:
  row bg state-list (focused = `focusTint` + accent stroke 1.5 for
  glass/edition; console = 1.5dp amber stroke, squared corners — Android has
  no cheap bracket painter here), typefaces, static label colors,
  compound-drawable tints. **`onBindViewHolder`** only sets entry-dependent
  text/colors/visibility (`isCurrent` recolor via token accent,
  letter-avatar tint, badges). Focus scale animation kept in all styles.
- EPG rows (`IptvEpgAdapter`): same holder/bind split; NOW/REPLAY chip +
  progress tint + typefaces from tokens; `itemView.isSelected = airing` set
  explicitly; day tabs/date/empty text re-tinted.
- Footer key hints + loading spinners re-tinted `fgFaint`/`accent`.
- Category picker AND add-to-list picker: dialog panels + status text + rows
  re-tinted from tokens (both are code-built dialogs; same treatment).

Everything lands in a dedicated section of the activity (or a small
`IptvGuideStyler` helper class in `tv/`) so the diff is reviewable and the
classic path is a single `if (guideTokens == null) return`.

### 4.6 Settings (Phase E)

- IPTV settings, new narrow section **"Player guide"** directly after
  "Appearance" (4 RadioListTiles: Classic / Cinema Glass / Midnight
  Edition / Master Control, subtitle strings describing each in a few words).
- **No platform gate** — every platform has a player (phones use the Dart
  player; TV uses native). Unlike page Appearance (TV/desktop-only).
- Two-pane: `_PlayerGuideDest` after `_AppearanceDest`. **Exact index
  contract** (Appearance is optional — TV/desktop gate; Player guide is
  ALWAYS present):
  - `base = playlists.length + 4`
  - `_appearanceIndex = base` (only meaningful when `showAppearance`)
  - `_playerGuideIndex = base + (showAppearance ? 1 : 0)`
  - `_recordingIndex = _playerGuideIndex + 1`
  - rail count grows by exactly 1 vs today in every configuration.
  New cases required in EVERY exhaustive site: `_railCount`, `_destForRail`,
  `_selectedRailIndex`, onUp/onDown DPAD links (Continue ↔ Appearance ↔
  Player guide ↔ Recording chain, skipping Appearance when hidden),
  `_buildPane` + its `ValueKey` switch ('player_guide').
- Settings search: entry "IPTV player guide" → IPTV settings, ungated.
- Persist-before-setState (`_setIptvStyle` pattern).

## 5. Wiring

- **Dart**: `_playerGuideStyle` field on `_VideoPlayerScreenState`, default
  `classic`, loaded in `_loadPlayerDefaults` — which `_initializePlayer()`
  AWAITS (VPS:1778) before playback setup, so any IPTV surface that can
  actually appear (first tune, zap, guide) already has the real value; the
  only classic-default window is the initial empty player frame where no
  guide surface exists. No extra setState needed beyond the existing flow.
  Threaded as a plain constructor param into `IptvZapBanner` and
  `IptvChannelSheet` (+ tokens derived once, not per-build).
- **Native**: `loadPlayerDefaults()` gains
  `prefs.getString("flutter.iptv_player_guide_style", "classic")`;
  resolved to `GuideTokens?` before `initIptvMode` uses it. No payload
  change, no bridge change.

## 6. Phases + review gates

- **Phase A** — Dart infra: pref (StorageService), `player_guide_style.dart`
  (enum + presets), VPS pref read + threading, `IptvZapBanner` all styles.
  → Codex review, fix P1s.
- **Phase B** — Dart `IptvChannelSheet` all styles + `EpgScheduleList`
  nullable full `IptvStyleTokens? tokens` param propagated through all
  schedule subcomponents (null = literal legacy branches). → Codex review,
  fix P1s.
- **Phase C** — Native infra (GuideTokens, typeface cache, pref read) +
  zap banner + dock live restyle. → Codex review, fix P1s.
- **Phase D** — Native guide overlay + EPG pane + category picker
  (`applyGuideStyle` + adapter token branches). → Codex review, fix P1s.
- **Phase E** — Settings (narrow + two-pane + search). → Codex review, fix P1s.
- **Final** — whole-diff Codex review until zero P1; verification (§7).

## 7. Verification

- `flutter analyze` — baseline is 98 pre-existing issues; no new ones.
- `flutter test` — baseline 845 passing / 8 pre-existing failures; no new failures.
- macOS debug build (Dart compile check).
- `./gradlew assembleDebug` with Android Studio JBR (JDK 21) — Kotlin/XML
  compile check (house rule: default JDK 25 crashes Kotlin-DSL).
- Manual checklist for the user (morning): per style × per player —
  zap banner floating + docked, guide open/scroll/search/schedule pane,
  dock buttons focus, category picker, favorites long-press, record chip,
  classic pixel-parity spot check.
- Everything stays **uncommitted**.

## 8. Deferred (recorded, not built)

- StremioTvGuideSheet + Debrify-TV ChannelGuide restyles.
- Native source-picker / jump-dialog restyle (stock AlertDialogs).
- Live re-theming on pref change mid-session.
- Any structural redesign of the guide (new panes, new data) — this effort
  is skin-only by design.
