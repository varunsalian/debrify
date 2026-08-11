# "Appearance" settings section (rev 2, post-Codex round 1)

## 0. Goal

Every look/layout pref is buried in a different home today: TV home style
inside the Home Screen page, Discover layout / sidebar style / screen size
as TV rows inside "Home & Display", IPTV page appearance and the new Player
guide two levels deep in IPTV settings, phone nav style behind a dialog.
Create ONE top-level **Appearance** section — phone, TV rail, and settings
search — where each look pref is one tap from the settings root.

## 1. Shape

A new top-level section/category "Appearance", inserted directly after
"Home & Display" on all THREE sync surfaces (the code comments document the
three-way sync contract):

1. **Phone/desktop** (`_SettingsLayout`, settings_screen.dart ~3794):
   `_SettingsLayout` is ONLY built when `_isAndroidTv` is false, so it
   carries NO TV rows (the existing `if (isAndroidTv)` block there is dead
   code — the three moved rows are deleted from it along with their
   now-unused props `tvUiScalePercent`/`onOpenTvScreenSize`/
   `tvSidebarStyleLabel`/`onOpenTvSidebarStyle`/`discoverLayoutLabel`/
   `onOpenDiscoverLayout`; the keyboard toggle row/props stay as-is).
   New `SettingsSection(title: 'Appearance')` (after Home & Display):
   - IPTV appearance → NEW `IptvStylePage` — `if (showIptvAppearance)`,
     a prop fed from `_iptvAppearanceSearchable` so the row, its search
     entry, and the IPTV settings section share ONE desktop/TV predicate
   - Player guide → NEW `PlayerGuideStylePage` — unconditional
   - Navigation style → existing dialog — unconditional here (the layout
     is already non-TV)
   All rows carry the live pref label as subtitle (the `SettingsRows`
   dynamic-subtitle pattern). Navigation style gets a REAL live caption:
   new `_phoneNavStyle` state loaded in `_loadSummaries`, and
   `_openNavigationSettings` is reworked so the dialog RETURNS the chosen
   value (`showDialog<String>`), the handler AWAITS `setPhoneNavStyle`,
   updates `_phoneNavStyle`, then fires `MainPageBridge.navPrefsChanged` —
   fixing the existing pop-then-unawaited-write race as a side benefit.
2. **TV rail** (`settings_tv_layout.dart`): new `_Category('Appearance',
   subtitle 'Home, sidebar, IPTV & player looks', icon
   Icons.palette_rounded)` at index 3; `_buildPaneChildren` cases 3–9
   renumber to 4–10 (audited: no other category-index dependency exists —
   `_selected` is session-local, rail nodes generate from
   `_kCategories.length`, callers pass no indices). The Appearance case
   uses CONTIGUOUS `_paneNodes[0..5]` (home style, discover, sidebar,
   screen size, IPTV appearance, player guide) — exactly fits
   `_kMaxCategoryRows = 6` (comment updated at the constant). **Case 2
   (Home & Display) compacts its nodes**: Home Screen → `_paneNodes[0]`,
   Debrify Keyboard → `_paneNodes[1]` — the DPAD walker only advances to
   the immediately adjacent live node, so a gap would strand DOWN.
3. **Search** (`_buildSearchIndex`): results group by category
   FIRST-APPEARANCE order, so the seven Appearance registrations (screen
   size, sidebar style, discover layout, TV home style, IPTV appearance,
   player guide, navigation style) are PHYSICALLY RELOCATED into one
   contiguous block immediately after the Home & Display registrations and
   before Playback — not merely re-labeled. IPTV pair retargets to the new
   picker pages. Gates unchanged per entry. **Old-category vocabulary is
   preserved in keywords** (category strings are part of the match
   haystack, and matching splits ONLY on whitespace, so the '&' token
   matters): the TV/nav entries gain the full former string
   'home & display' (plus 'display'); the IPTV pair gains
   'live tv & dvr' (plus 'live tv', 'dvr').

## 2. Moves (no duplicated top-level rows)

- The three TV rows (sidebar / discover / screen size) MOVE out of
  "Home & Display" on both phone layout and the TV pane — a pref reachable
  from two sibling top-level sections would be confusing. "Home & Display"
  keeps: Home Screen page row, Debrify Keyboard toggle. Its TV rail
  subtitle updates ("Home, Discover, sidebar & screen size" → "Home screen
  rows & keyboard" or similar).
- Feature-LOCAL copies stay (that's contextual, not sibling duplication):
  the Home Screen page keeps its "TV home layout" row; IPTV settings keeps
  its Appearance + Player guide sections (narrow + two-pane) untouched.

## 3. New files (radio-picker idiom, copied from tv_home_style_page.dart)

- `lib/screens/settings/iptv_style_page.dart` — `IptvStylePage`: 3 options
  (Command Center / First Edition / Master Control), pref via
  `StorageService.getIptvStyle/setIptvStyle` (persist on tap; a newly
  opened IPTV page route loads the stored value in its initState — no
  bridge call needed). Explainer notes phones keep the classic list.
- `lib/screens/settings/player_guide_style_page.dart` —
  `PlayerGuideStylePage`: 4 options (Classic / Cinema Glass / Midnight
  Edition / Master Control), pref via
  `getIptvPlayerGuideStyle/setIptvPlayerGuideStyle`. Explainer notes it
  applies to the NEXT playback session and covers this device + Android TV.
- Both: single column of `SettingsTile` radio rows inside
  `SettingsSection`, `_firstCardMarker` + post-frame focus grab on TV
  (`primary is! FocusScopeNode` guard), `SettingsPageScaffold` +
  `SettingsPageHeader`, no hand-wired DPAD (default traversal).
- Label helpers `iptvStyleLabel()` / `playerGuideStyleLabel()` live beside
  their choice lists IN the new pages (the tv_home_style_page.dart
  precedent — they are NOT added to settings_widgets.dart).

## 4. Wiring details

- `SettingsRows` (settings_widgets.dart): two new specs `iptvAppearance`
  and `playerGuideStyle` (dynamic subtitle `''` + call-site override).
- `_SettingsScreenState`: new fields `_iptvStyle`/`_playerGuideStyle`/
  `_phoneNavStyle` loaded in `_loadSummaries()` alongside the other caption
  prefs; new handlers `_openIptvStylePage` / `_openPlayerGuideStylePage`
  (pushSettingsPage + re-read pref on return, same shape as
  `_openTvScreenSize`). Existing `_openTvHomeStyle` (currently search-only)
  now also backs the visible Appearance row.
- **Stale-caption guard (P1 fix)**: the feature-local copies can change
  these prefs behind the root screen's back. A small
  `_reloadAppearanceSummaries()` (re-reads ONLY tv_home_style, iptv_style,
  iptv_player_guide_style — the three prefs with feature-local editors —
  then setState) is awaited at the end of `_openHomePageSettings`,
  `_openIptvSettings` AND `_openIptvAddSource` (the search deep-landing
  opener also reaches the two-pane's Appearance/Player guide panes), in
  addition to the new picker handlers' own re-reads. No network work —
  never the full `_loadSummaries()`.
- `_SettingsLayout` gains the needed props (labels + callbacks), threaded
  exactly like the existing tvSidebarStyle/discoverLayout/tvScreenSize
  props it already carries (which move sections but keep their prop names).
- `SettingsTvLayout` gains props for the six pane rows (three move from
  case 2, three new: home style, IPTV appearance, player guide) + the
  renumbered switch: inserting category index 3 shifts Playback→Danger Zone
  cases +1 — EVERY case literal in `_buildPaneChildren` (and any other
  index-sensitive site in the file — audit `_selected` uses) updates.
- Desktop gate: reuse the page-level desktop detection already used for
  `_iptvAppearanceSearchable` (settings_screen.dart:103-105) so the row and
  the search entry share one truth.

## 5. Invariants

- Pref semantics untouched: same keys, same coercions, persist-on-tap.
  No new prefs.
- IPTV settings page/two-pane and Home Screen page are NOT modified.
- TV DPAD: new pane rows use the pooled `_paneNodes` + `_isPaneRowLive`
  pattern verbatim; rail entry count grows by one; no focus-order changes
  beyond the intended insertion. Picker pages rely on default traversal
  (proven idiom).
- Search entries keep their platform gates; only category + landing change.
- The three-way-sync comments in settings_screen.dart /
  settings_tv_layout.dart are updated to name the new section.

## 6. Verification

- flutter analyze: 0 errors / 98 pre-existing warnings.
- flutter test: 845 passing / 8 pre-existing failures.
- macOS debug build (desktop shows Appearance with IPTV appearance +
  player guide + navigation style rows).
- Manual checklist (user): phone — Appearance section shows Player guide +
  Navigation style; TV — rail has Appearance with six rows, DPAD in/out,
  Home & Display no longer lists the three moved rows; search "sidebar",
  "glass", "screen size" land on pickers directly.
- Everything stays UNCOMMITTED for user test.

## 7. Out of scope

- Scroll-to-highlight (obsolete for these entries — they now land on
  dedicated pickers; the system-wide gap stays on the deferred list).
- Subtitle appearance, ambient trailer toggles, keyboard toggle (input),
  `stremio_addon_hub_enabled` (no UI row exists) — candidates for a later
  pass, listed for the record.
- tv_nav_style — does not exist in the tree.
