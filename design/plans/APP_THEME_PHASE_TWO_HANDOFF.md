# Phase two — where it stands

All **uncommitted**. 48 files, +3,584/−1,196. `dart analyze lib/` clean,
`test/theme/` **141/141**.

## The one-line summary

The conversion is **done for all six surfaces**; **none of it is switched on**.
Every surface still sits behind its `LegacyThemeBoundary` and renders legacy.
The flip is deliberately not done — see *Before you flip*.

## What landed

| Stage | State |
| --- | --- |
| **Stage 0** — token contract | ✅ 6 subprofiles (`Downloads`, `Youtube`, `Playlist`, `StremioTv`, `DebrifyTv`, `Iptv`), derived for all 20 themes, legacy values pinned |
| **Stage 0b** — cross-boundary widgets | ✅ 9 optional params across `tv_text_field`, `tv_keyboard`, `shimmer`, `browse_search_header`; **0 callers edited** |
| **Guards** | ✅ `kThemingPrepared` + 3 new tests |
| **Surfaces** | ✅ all six converted, ~38 files registered as prepared |

The Stage 0b contract is the important one: every parameter defaults to the
literal it replaces, so themed Settings/Cloud and the permanently-frozen player
all render byte-identically while scheduled surfaces opt in one at a time.

## Suggested commit split

1. `app_theme.dart` + `legacy_pins_test.dart` — the token contract
2. `source_guard_test.dart` — the guards (independently useful)
3. `search_screen.dart` + `pipeline_loading_overlay.dart` — two containment bug
   fixes, both worth landing on their own
4. the four Stage 0b widgets
5. one commit per surface

## Bugs found and fixed on the way

**`PlaylistContentViewScreen` rendered two palettes.** Frozen from the Playlist
tab, themed from Search (`search_screen.dart:3184` pushed it bare). Fixed, and
there is now a guard for the class of it.

**`download_service.dart` is rendered by six themed Cloud screens.** It paints
the battery sheet with the *caller's* context. Tokenising it during Downloads —
step 1, "plausibly one commit end to end" — would have changed six already-themed
screens. The plan's own tool contradicted the plan's table; table corrected, file
left alone.

**`pipeline_loading_overlay.dart` themed Search immediately.** Rendered by both
themed Search (via `torrent_playback_service`) and frozen Stremio TV, it had been
converted to read `AppThemeScope` directly — changing Search *today*, before
Stremio's flip. Now pinned to its legacy palette and reads no ambient theme.
Note while fixing it I first wrote two **wrong** defaults from memory
(`0xFF120A24`/`0xFF7B5CFF`) instead of the real `0xFF201636`/`0xFF8B6BFF` — the
exact byte-identity violation being guarded against. Checked and corrected.

**Fifteen `kThemingPrepared` entries were decorative.** Their paths were absent
from the guard's frozen-prefix list, so the allow-list looked like it was holding
files back while the guard could not see them at all. Prefix list widened, and
there is now a test asserting no entry can sit outside it.

## Before you flip — known-open, from the Codex review

Ranked. None of these affect rendering today; all of them bite at flip time.

1. **Ink on a fill is not contrast-checked in two places.**
   `tv_focusable_button.dart:90` gives every button `app.core.tx` regardless of
   its `backgroundColor` — white on white for Noir, amber on amber for Phosphor,
   1:1. Playlist badges repeat it (`playlist_content_view_screen.dart:1720`,
   white on derived success ≈1.92:1). Both need a legacy-pinned `onFill` token
   using `_inkOnWorstOf`, not `core.tx`.
2. **IPTV's Edition/Console palettes are being overridden.** Those styles own
   fixed dark grounds and foreground ramps, but `IptvRailEpgCard` now uses app
   ink unconditionally, even when `widget.tokens != null`
   (`iptv_epg_panel.dart:203`, `:247`). That contradicts the agreed decision —
   palette follows the theme, **layout and its own ramps stay IPTV's**. Also
   `iptv_results_view.dart:6680` uses `core.tx` where it should use `onGlass`.
3. **Two intended integrations are dead.** `downloads.shimmerBase/Highlight`
   have no call site (`downloads_screen.dart:693` passes neither), and
   `BrowseSearchHeader` never forwards `accent`/keyboard params to its internal
   `TvTextField` (`browse_search_header.dart:100`), so YouTube's
   `keyboardPanel`/`onFocus` tokens do nothing.
4. **The ratchet is still uncoupled from `AppSurfaces`.** `stillFrozen` in
   `source_guard_test.dart` is a hand-maintained list, so flipping a tab to
   themed can leave the guard green. It should read the classification.
5. **I lost review findings 1–2.** The Codex run was piped through `tail -60`
   and its first two findings were truncated. Re-run before flipping:
   `codex exec --sandbox read-only` over the working-tree diff.

## Judgement calls to sanity-check

**18 deliberate reuse rejections.** Roles whose legacy value equals an existing
role but whose meaning differs — e.g. `youtube.focus` is value-identical to
`seeAll.accent` and deliberately separate, because a DPAD cursor and a surface
accent answer different questions. This is the class of error no test can catch:
every selectable theme is dark, so value equality holds under legacy regardless.
If anything here is wrong, it is in that list.

**`dart format` was not run.** The tall-style formatter rewrites these files
wholesale (1,219 lines on an *untouched* `downloads_screen.dart`), which would
bury the conversions. Their already-converted neighbours are in the same state.
A repo-wide reformat should be its own commit.

**One agent declined an invited change**, correctly. `BrowseSearchHeader`'s docs
invite passing the theme accent as `focusedBorderColor`; doing so would swap
today's white-at-0.15 ring for violet — visible under legacy. It left it null
and noted the swap belongs in the commit that lifts the boundary.
