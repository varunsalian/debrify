# Player Dialogs Redesign — Spotlight Grammar

The dart (media_kit) player — normal player, Debrify TV, IPTV, and the ONLY
player on Apple TV — accumulated ~15 interactive surfaces across three design
generations: old Material bottom sheets/AlertDialogs, mid-generation custom
overlays, and newer themed panels. This plan converges them on one grammar.
Android TV is out of scope (native player).

## The grammar (from the approved mock, scratchpad `player_dialogs_spotlight_mock.html`)

Spotlight tokens, taken from `showcase_parts.dart`:
- Black glass: `#101012` @ 0.72 + BackdropFilter blur 26 (near-opaque fill on
  Android TV boxes, where the dart player can still run as a fallback).
- White ink at graded alphas; 0.75px hairline borders (white @ 0.14).
- **The focused thing is a solid white pill with black text**, scale ~1.03,
  soft shadow. Crimson `#E23D4C` is a status color only (recording/live).
- Section captions: 11px, letter-spaced, uppercase, white @ 0.42.

Feel: slide-in 320ms easeOutCubic + fade; value panes crossfade with a small
slide; focus moves animate 140–160ms; video dims (gradient scrim) but never
disappears; scrim tap closes.

## Phase 1 — panel kit + unified menu  ✅ BUILT (this delivery, uncommitted)

`lib/screens/video_player/widgets/player_menu_panel.dart` + wiring in
`video_player_screen.dart`, behind `kUnifiedPlayerMenuEnabled` (const, same
style as the native player's `USE_UNIFIED_MENU`; old surfaces intact when off).

One right-side panel, two panes: section rail (Audio / Subtitles / Subtitle
style / Sync / Speed / Aspect / Sleep timer / Shuffle, each captioned with its
current value) + value column. Absorbs: TracksSheet (all three tabs, incl.
per-addon subtitle slots with live status/retry/identify), SleepTimerSheet,
shuffle AlertDialog, and the blind speed/aspect button cycles.

Architecture decisions (keep these invariants):
- **Panel is pure UI + slot-fetch orchestration.** Every player mutation goes
  through host appliers in `video_player_screen.dart` (`_menuSelectAudio`,
  `_menuSubtitlesOff`, `_menuSelectEmbeddedSubtitle`, `_menuSelectAddonSubtitle`,
  `_menuApplyTrackChange` = the old sheet's onTrackChanged closure verbatim).
- **House overlay pattern** (like SourceSheet/IPTV guide): in-tree
  `Positioned.fill`, own KeyboardListener claiming focus post-frame,
  `handleHostBack()` for tvOS Menu (PopScope → `_closeTopPlayerOverlay`),
  `TvOverlayBack.mark()` on key-driven close so the press doesn't also pop
  the player. Root key handler ignores all keys while the menu is open.
- DPAD: rail UP/DOWN; RIGHT/OK enters pane; pane LEFT/BACK returns to rail;
  stepper rows (Style pane) take LEFT/RIGHT as adjust, BACK to exit. Per-pane
  focus memory. Focus visuals only once the DPAD is in play (always on TV).
- Pane-crossfade keeps BOTH panes in the tree → scroll-target GlobalKeys are
  scoped `(section, index)`, never index alone.
- Speed section hidden on live; Shuffle hidden without a playlist; rail index
  clamped in didUpdateWidget (sections can shrink live).
- Entry points: tracks button → menu@subtitles (identity context awaited,
  exactly like the old sheet); speed/aspect/sleep/shuffle buttons → menu@that
  section with cache-only identity (`_openPlayerMenuQuick`) — if IMDb was
  never fetched the Subtitles pane still offers "Fix the title".
- Keyboard shortcuts (A = aspect cycle) and long-press 2× are untouched.
- `_resetSubtitleState` closes the menu on content switch (stale identity).

## Phase 2 — sync surfaces  ✅ BUILT
- `sync_stepper_overlay.dart`: bottom glass stepper pill replaces the
  Material-slider overlay. LEFT/RIGHT ±0.1s, held repeats accelerate ×5,
  OK resets, BACK bubbles to the host (which owns `_showSyncOverlay`).
  Video fully visible.
- `subtitle_line_picker_overlay.dart`: full-screen sheet → right-side glass
  panel (menu grammar), logic untouched; the manual Material Slider became
  stepper buttons; playing cue marked by a white bar, not a color.

## Phase 3 — confirm-card component  ✅ BUILT (scoped)
`spotlight_dialog.dart`: `showSpotlightDialog` + `SpotlightDialogCard` +
`SpotlightPillButton` (Focus-based white-pill, recommended action = solid on
touch / autofocus on TV). Converted: record-programme confirm (IPTV guide),
season/episode entry (player). DELIBERATELY NOT converted:
- `recording_limit_dialogs.dart` — just migrated to the app token layer with
  byte-identical legacy guarantees; repainting it here would undo that.
- TVMaze fix-metadata (`series_browser.dart`) — shared with phone screens
  outside the player; belongs to the app-theme work, not this one.
- Shuffle dialog — already absorbed by the Phase 1 menu.

## Phase 4 — big panels converge  ✅ BUILT (scoped)
- SourceSheet: accent consts red → white ink, white-pill content flipped to
  black, square panel edge + 0.75px hairline, chips hairline-outlined
  monochrome, `_frost` now blurs everywhere except Android TV boxes.
- StremioTvGuideSheet: cyan consts → white ink, same white-pill fix.
- Identify-title search sheet: bottom sheet → right-side glass panel
  (showGeneralDialog, slide+fade), logic untouched.
- IPTV guide menus: stock `PopupMenuButton` → `_GuideSelectDialog` in the
  guide's own picker chrome (token-aware, reuses `_CategoryPickerRow`).
- PlaylistSheet: Spotlight material, bottom-sheet geometry KEPT — an
  episodes grid genuinely wants full width; only small pickers panel-ize.
- DockOverflowSheet: KEPT as-is — it is themed by the dock-palette system
  (a deliberate mechanism, like guide styles); with the menu on, most of its
  entries route into the menu anyway.

## Phase 5 — feel + verification  ✅ code parts BUILT, device pass pending
- Hold-to-accelerate: in the sync stepper (repeat ×5); menu steppers accept
  key repeats natively.
- Theming decision: the new surfaces hardcode Spotlight tokens for now;
  per-look theming (AppThemeScope / PlayerGuideStyle) is future work, noted
  as the price of shipping one tuned look first.
- tvOS release build + install: compile-verified; the FEEL pass on the
  actual Apple TV remote is the user's — that is the true Phase 5 exit.
