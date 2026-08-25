# C3 Command Center — Build Plan (approved mock: design/mockups/iptv_redesign_mockup/c3)

Scope: IPTV page TV/desktop two-pane becomes rail → list → stage-right cockpit.
Phone/classic layout untouched. Player untouched. Additive + surgical: the
paged grid, SWR cache, focus machinery, and every handler stay as shipped.

## Deltas

1. **Rail (new `iptv_command_rail.dart`)** — left, 200px: LIBRARY (Favorites,
   Continue, Scheduled→ScheduledRecordingsPage), SOURCES (playlists, counts
   via IptvSourceStatsLoader.read — sync, cheap), LISTS (custom lists w/
   channelCount), footer "Manage sources". Selecting = existing
   `_onPlaylistChanged`. Plain focusable items ⇒ geometric DPAD: LEFT from
   grid col-0 lands on rail, LEFT from rail bubbles to the shell's global
   action = app sidebar (LEFT-only policy preserved, zero interception code).
2. **Stage moves right** (TV + desktop non-touch; touch-tablet layout
   unchanged): preview 16:9 + identity/now-next (existing pieces) + actions
   row (Watch · Record · ♥ · Guide) + "Today on <channel>" compact schedule
   with inline REC/REPLAY/NOW — new `iptv_stage_panel.dart`.
   RIGHT from right-edge rows reaches stage actions geometrically
   (`scheduleOnRightKey:false` in this mode; the full schedule pane stays
   reachable via the stage's Guide action → `_openSchedulePane`).
3. **Top bar** — keep the shipped quiet dropdowns (sources/type/category) as
   dropdowns per user instruction; search unchanged (browse header).
4. **Recording actions on the page**: Record-now = engine start (Android) /
   DesktopRecordingService (desktop, path via new public
   `DesktopScheduleService.buildRecordingPath`); programme REC = same
   schedule flow as the channel sheet (platform-branched, gated by
   `isSchedulableUrl`). Catchup rows → existing `_playCatchup`.

## Perf rules (TV must never hitch)
- Stage schedule fetch: 450ms focus-settle debounce, only when
  `IptvEpgService.isEpgCapable`, served by the existing 30-min schedule cache
  + in-flight dedupe; stale-ticket guarded.
- Rail: static column, counts computed once per playlist load (no per-build
  DB reads); Scheduled count loaded with settings + after page return.
- No new animations/opacity layers on TV; RepaintBoundary around the stage
  panel; snap state changes.

## Non-goals (this step)
Recordings library page; phone cockpit sheet; removing the sources dropdown
(kept alongside the rail so no focus-repair wire breaks); live REC badge on
stage (needs registry polling — later).
