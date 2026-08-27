# Tracking Sources — Scrobble set / Progress source / Home ticks

Driven by Discord (2026-08-27): Ramsy ("choose which one we want to use"),
king c0llier (gym case: Trakt/Simkl evict a show from Continue Watching at
80% while his Debrify watched-at setting says 90%+; wants Debrify-local CW
while still scrobbling to trackers; posted Nuvio's "Tracking" menu as the
reference shape).

Three controls in one new **Tracking** settings section. Each owns exactly one
question so no two knobs can disagree:

| # | Control | Kind | Question it owns |
|---|---------|------|------------------|
| 1 | **Scrobble** | multi-select (Local locked ON) | What do we SEND — which trackers receive playback + explicit watch/unwatch |
| 2 | **Progress source** | single-select: Smart / This device / Trakt / Simkl / MDBList | What we TRUST — resume position, Continue Watching membership + advance, every progress bar incl. Home |
| 3 | **Home tick marks** | multi-select: Local / Trakt / Simkl / MDBList | What DECORATES Home — the watched checkmarks on Home poster cards only |

Scope decisions already made with Varun (do not relitigate):
- Option 3 is **Home cards only**. Episode guides / detail panels keep today's
  always-merged ticks — guides are where you *manage* state, Home is where you
  *glance*. Settings copy must own the possible mismatch.
- Option 2 governs Home CW row composition too. Today local CW is empty for
  scrobbling users **by design** — the SINGLE-OWNER RULE at
  `video_player_launcher.dart:1005-1020`: `saveContinueWatchingItem` runs only
  when NO tracker scrobbles the title ("so it lives in exactly one row
  instead of duplicating"), and the tracker-ownership removal at `:998`.
  "This device" mode must bypass both: write local CW regardless of
  scrobbling (no duplication risk — the tracker rows are hidden in that
  mode) and skip the OWNERSHIP removal at `:998` only.
  **Do NOT touch `local_series_completion_service.dart:341`** (review): that
  removal is CAUGHT-UP eviction — fires when every released episode is
  locally finished, and re-adds the series when new episodes air. It is
  completion housekeeping, wanted in every mode; bypassing it would strand
  finished series in local CW forever.
- **Local completion tracking: THREE-WAY rule, not a blanket policy switch**
  (round-4 review corrected round 3's unconditional wording):
  `VideoPlayerScreen._usesLocalCompletionTracking` and the launcher's
  `localCompletionTracking` (`video_player_launcher.dart:4852`) are both
  `!traktScrobble && !simklScrobble && !mdblistScrobble && …` today.
  New rule on BOTH player paths:
  **This device → forced ON** (independent of option 1 — king c0llier's
  scrobble-while-local setup needs it); **Smart and dedicated-tracker modes →
  today's scrobble-derived behavior UNCHANGED** (Smart is every profile's
  default; forcing it either way would change behavior for the whole
  installed base or break local-only users).
- Scrobbling (option 1) is independent of reading (option 2): progress=Trakt
  with scrobble-to-Trakt OFF is VALID (Stremio-refugee reads Trakt that other
  apps write). No warning dialog; one caption line at most.
- **Rewatch detector follows the SAME masked inputs** (self-review round 5 —
  the earlier "moot, guides unchanged" note became stale when round 4 masked
  guide partials): `hasActiveTraktEpisodeRewatch` consults tracker PARTIAL
  sessions to un-tick locally finished episodes. In a dedicated mode a
  non-selected tracker's session must not un-tick anything — feed the
  detector the same policy-masked percents the guide bars get, and the rule
  stays one rule. Smart mode: unchanged.

## Semantics that replace existing invariants

**Explicit watch/unwatch fan-out rule (NEW, replaces the conditional local
write):** user-initiated mark watched/unwatched writes to LOCAL always + every
tracker ticked in option 1. This retires the "never write local completion
when a tracker is connected" invariant (episodes_panel.dart ~:668 comment and
[[project_episode_unwatch_union_fix]]) — under the new model a ticks=Local
user NEEDS the local write even while authed. Unwatch already fans out
everywhere (d187504e); watch becomes symmetric with it.

**Dedicated mode with a disconnected tracker:** fall back to Smart VISIBLY
(one-time notice), never leave the mode pointing at nothing — that's the
"nothing shows ☹" screenshot.

**IPTV CW rows are exempt from option 2** — they're player-history keyed
(IptvCwRouter routeKeys, not IMDb), no tracker ever populates them. Always
shown per their own rules.

## Code anchors (verified 2026-08-27)

### Storage / policy (Phase 0)
- New profile-scoped prefs in `storage_service.dart`:
  `tracking_scrobble_targets` (set), `watch_progress_source` (enum string,
  default `smart`), `home_tick_sources` (set, default all).
- One policy helper (new `lib/services/tracking_source_policy.dart`):
  `scrobbles('trakt')`, `progressFrom('simkl')`, `homeTicksFrom('local')` —
  pure, unit-testable, mirrors ResumeWriteGuard's shape.
- Backup/restore + remote profile transfer both carry the three prefs — but
  they are SEPARATE mechanisms with separate gotchas; see the detailed
  bullets under Option 1 (absent-key rule, wire payload + router map). Do
  not assume "in backups" implies "on the wire".

### Option 1 — Scrobble (write side)
- Per-tracker toggles today are **"Sync Catalog Items"** rows on
  `trakt_settings_page.dart:380`, `simkl_settings_page.dart:370`,
  `mdblist_settings_page.dart:450`, keys `get/setXxxSyncCatalogItems`
  (`storage_service.dart:5917-6018`).
- **DECIDED (Varun, 2026-08-27): Option B.** The old keys mean "scrobble
  catalog/addon content too", not "scrobble at all" (tracker-native items
  always scrobbled regardless). New per-tracker master keys, seeded from the
  old SyncCatalogItems values — the closest reading of existing intent, since
  the bulk of Debrify playback IS catalog/addon content. Accepted behavior
  change: unticked = tracker-native items stop scrobbling too (what the
  checkbox says). Old rows removed.
- **Migrate the old keys' readers BY ROLE, not wholesale** (review 2026-08-27):
  - Write-side → new masters: `video_player_launcher.dart:765/862/965`
    (auto-enable branches), `search_screen.dart:13039` (Simkl launch gating),
    `remote_command_router.dart`, the three settings pages being retired.
  - **Read-side → REPLACE the gate, don't preserve the retired key**
    (round-4 review sharpened round 2's classification):
    `episode_tracker_snapshot_service.dart` (`:559` seedMdblistPlayback,
    `:671` refreshMdblistHistory) currently gates on the old key. Once its
    settings row is deleted, that key becomes FROZEN INVISIBLE STATE — a
    user who ever turned it off can never turn it back on, and those fetches
    return empty forever even in progress=MDBList mode (same trap class as
    the auto_bind mirror lesson in
    [[project_play_button_source_mode]]). New gate: authentication + the
    applicable READ policy (option 2). The retired key is consulted once at
    seeding time and never read again.
  - `backup_restore_service.dart`: add the new keys to future payloads; on
    restore accept old backups (see Defaults & migration for the absent-key
    rule).
  - **Remote profile transfer is a SEPARATE path** (round-4 review, matches
    [[project_remote_profile_graph]]): `RemoteConfigExport` /
    `RemoteTransferAll` hand-encode their payload categories and
    `RemoteCommandRouter._applyProfileRemotePayload` replays a fixed category
    map — keys in backups do NOT ride the wire automatically. Add the three
    prefs to the outbound payload AND the router's application map, or a
    transferred profile silently resets to Smart/all/seeded defaults.
- **Normalize the scrobble flags at ONE choke point** (review finding — the
  per-branch gating below is insufficient alone): playback launched FROM a
  tracker row arrives with `args.traktScrobble/simklScrobble/mdblistScrobble`
  already true (e.g. `video_player_launcher.dart:833`), so the auto-enable
  branches at `:760+` are SKIPPED — and the flags flow untouched into the
  native TV payload (`:1059 'trakt_scrobble'`) and
  `_seedTrackerContinueWatching`. Add a single normalization on the shared
  launcher path, BEFORE payload construction and external seeding:
  `flag = flag && policy.scrobbles(x)` for all three. The per-site gates
  below then become defense in depth, not the mechanism.
- Gate the write paths: `video_player_screen.dart:1766`
  (`_traktScrobbleEnabled = isAuthenticated()` → `&& policy.scrobbles(...)`,
  same for simkl/mdblist enables), launcher auto-enable branches
  (`video_player_launcher.dart:765/862/965`).
- **Explicit-action fan-out inventory (COMPLETE list — review finding; the
  panel alone is not enough):** `episodes_panel.dart` `_watchedSyncTargets` +
  local-write branch `:666-680`; `handleTraktMenuAction`
  (`trakt_menu_helpers.dart` — Home/detail card menus);
  `TraktResultsView._onMenuAction` / `._onEpisodeMenuAction`
  (`trakt_results_view.dart`); `handleMdblistMenuAction`
  (`mdblist_menu_helpers.dart`); `handleSimklMenuAction` `moveToCompleted`
  (`simkl_menu_helpers.dart` — search/detail/catalog-browser surfaces).
  Each currently writes only its own provider; under the new rule every one
  writes local + the option-1 set. At five-plus scattered sites the
  coordinator is no longer optional — **route all explicit watched actions
  through one watched-action coordinator** so the next surface added can't
  miss the rule. `playlist_content_view_screen.dart:3319-3328` (cloud
  playlist ticks) stays LOCAL-ONLY as today — audit whether tracker identity
  even exists there before extending fan-out; if not, document the exemption.

### Option 2 — Progress source (read side)
- **Resume:** `_reconcileSeriesResume` (single-writer since a592692d) — null
  non-selected candidates before winner logic, **AND the fallbacks** (review
  finding): the Simkl `next_to_watch` input and the MDBList selection used
  when the ranked list is empty can each still pick a tracker episode in
  This-device mode. Null non-selected fallback signals and tracker frontiers
  together with the candidates — the filter lives at the reconciler's INPUT
  gathering, not on the ranked list.
- **Reconcile cache must key on the policy** (review finding): the reconciler
  returns cached answers for ~45s (`reconcile-cache-hit ageMs=… rev=…` in
  logs) and its revision key carries tracker revisions/auth but no
  preference. Include the progress-source value in `_seriesResumeRev` (or
  clear the cache on pref change), or a mode switch keeps the previous
  provider's pill and launch target until expiry.
- **Movie + source fast paths are NOT downstream of the reconciler** (review
  finding, corroborated by [[project_play_button_source_mode]]'s own note that
  the MDBList fast path bypasses it): `_resolveResumeInfo` checks tracker
  movie percentages directly and has an MDBList-source fast path;
  `_onCatalogPlay` separately fetches all tracker movie percentages and
  bypasses the reconciler for MDBList-sourced series and Trakt-sourced
  movies. Without gating these `search_screen.dart` paths, This-device mode
  still shows "Resume" from Simkl and launches at the remote percentage.
  Gate them with the same policy.
- **Merged-detail ENGINE target is a third resume input** (review): when the
  policy-filtered reconciler returns no started candidate,
  `MergedDetailScreen._loadResumeInfo` adopts `_pendingEngineTarget` from the
  ALWAYS-MERGED episode panel, and `promisedTarget` then overrides the
  reconciler at Play ([[project_play_button_source_mode]] invariants). So
  This-device mode with only remote progress would still show and launch the
  tracker's episode via the engine path. Mask the engine-target ARBITRATION
  by the policy (an engine target derived from non-selected sources doesn't
  qualify as "started") while leaving the panel's ticks merged — the same
  label/press coherence rule 494af113 established still holds afterward.
- Player-side launch percents: launcher rows `'traktProgressPercent'`
  (`video_player_launcher.dart:2379, 2678, 3400, 5003`) and
  `_currentEpisodeTraktPercent/_Simkl/_Mdblist` in
  `video_player_screen.dart` — filter at the supplier, so the native TV
  payload follows for free (NO Kotlin change). **Include the late-metadata
  path**: `updateEpisodeMetadata` updates carry `trackerProgressPercent`
  (builders near `video_player_launcher.dart:3428/3462`) and the activity
  merges them into items — the same supplier-side filter applies there, or
  the native guide regrows foreign bars a few seconds after launch.
- **Home CW rows:** `search_screen.dart:744-830` — the row blocks are already
  per-source (`_cw*` local since it reads `continue_watching_v1`, `_trakt*`,
  `_simkl*`, `_mdblist*`, `_iptvCw*`). Mode = gate which blocks LOAD (loaders
  around `:2690` follow `_cwEnabled`-style enables; See-All grids ride their
  block). "This device" additionally bypasses the single-owner rule (see
  scope decisions above) so the local store actually populates.
- **Interplay with the EXISTING display-layer knobs (fourth knob — do not
  skip):** the Home Sections filter (`home_sections_filter_page.dart:223-250`)
  already has per-row toggles for `cw:*`, `trakt:*`, `simkl:*`, `mdblist:*`
  CW rows — this is what king c0llier actually used — plus the master
  Continue Watching switch on the Home Screen page
  (`getHomeContinueWatchingEnabled`, read at `search_screen.dart:2689`).
  Layering rule: **option 2 decides which sources are ELIGIBLE; the sections
  filter and CW master switch remain display-layer choices among eligible
  rows.** In a dedicated mode, ineligible sources' CW rows are force-hidden
  regardless of filter state, and the filter page should grey them out with a
  one-line note pointing at Tracking ("hidden by your Progress source
  setting") — otherwise the filter page shows toggles that do nothing, which
  is its own Discord thread.
  **The CW master switch is currently a WRITE gate, not display-only**
  (review — verified): `saveContinueWatchingItem` returns without persisting
  when `getHomeContinueWatchingEnabled` is false
  (`storage_service.dart:2446`). **DECIDED (Varun, round 4): the gate moves
  to RENDER side in ALL modes** — the switch becomes pure display, history
  always records, re-enabling the row brings titles back. (The alternative —
  keeping it a write gate renamed "Track Continue Watching" — was considered
  and rejected; per-title removal remains available for anyone who wants an
  item gone.)
- **Detail pill/card:** the series MAINLINE is downstream of the reconciler;
  the movie/fast paths above are the exceptions — after gating those, nothing
  extra here.
- **Episode guides: completed ticks stay merged; PARTIAL progress follows
  option 2** (DECIDED, Varun, round 4 — refines the original ticks-only
  scope decision): in a dedicated mode,
  `EpisodesPanel._loadEpisodeWatchProgress` masks non-selected sources'
  partial percentages and tracker frontiers before they enter
  `_episodeWatchProgress` — those drive the in-guide progress bars and
  `_mergedUpNext`, and an unmasked 40% Simkl bar on an episode this device
  never played would promise a resume the Play button refuses to honor.
  Fully-watched entries (ticks) from every source keep merging exactly as
  today.

### Option 3 — Home ticks
- `watched_status_service.dart:42-55` — `isWatched` is already a union of
  per-source sets (`_localMovies/_traktSeries/...`). Add a Home-scoped lookup
  that masks sets by the pref (e.g. `isWatchedForHome`), notify on pref
  change. **Home call sites only**: `spotlight_board.dart:2616-2621` (card
  badge) — leave `movie_watched_badge.dart` consumers on detail/search pages
  (`catalog_item_detail_screen.dart`, `merged_series_detail_screen.dart`,
  `search_card_widgets.dart`, `catalog_item_tile.dart`) on the unfiltered
  lookup unless the card renders on the Home board.

### Settings UI (Phase 4)
- New "Tracking" group: either a section on `settings_screen.dart` or a hub
  page (Nuvio-style, matches [[project_tracker_options_redesign]] step 1).
  Three rows; options constrained to authed trackers; Local locked in 1 and
  always available in 2/3.
- Remove the three Sync Catalog rows; settings-search keywords ("scrobble",
  "sync catalog", "watch progress", "continue watching source") must land on
  the new section (`project_settings_search` machinery).
- TV: multi-select rows use the two-pane manager grammar
  ([[project_tv_filter_two_pane]]); single-select uses the house dropdown.

## Copy (drafted, adjust tone)
- Scrobble: "Which services record what you watch. Debrify always keeps its
  own progress."
- Progress source · Smart: "Combines this device with your connected
  trackers — the most recent activity wins." (NOT "furthest wins" — review
  finding: the series reconciler is deliberately RECENCY-based; "furthest"
  is the player's position-level rule, a different layer. Copy must not
  promise what the reconciler doesn't do.) · This device: "Resume and Continue
  Watching use only this device and your watched-at % setting. Tracker rows
  are hidden on Home; history is still sent to ticked services. Progress
  won't follow you to other devices." · Trakt/Simkl/MDBList: "<X> owns your
  progress. Shows leave Continue Watching by <X>'s rules."
- Home ticks: "Which histories draw the ✓ on Home cards. Episode lists always
  show every service's ✓." (NOT "combined history" — since round 4, episode
  lists combine TICKS from everything but show partial bars only from the
  selected progress source; the copy must not promise merged bars.)

## Defaults & migration
- scrobble = seeded from the three SyncCatalogItems values (per Option B
  decision), progress = Smart, ticks = ALL. Zero behavior change until
  touched.
- **Absent-key rule for restores (review finding — verified):**
  `backup_restore_service.dart` serializes `sync_catalog_items` ONLY for
  MDBList (`:207`); Trakt and Simkl restores hardcode catalog scrobbling ON
  (`:578`, `:600`). Seeding a master from an absent old key must therefore
  default to **true** for Trakt/Simkl (matching what those restores actually
  produced), while MDBList seeds from its restored value. New keys join
  future backup payloads; restores of old backups take this fallback path.
- No storage migration of watch data (all read-side); prefs only.

## Order of work (3–4 sessions — grew from the original 2–3 as reviews added
the fast paths, engine mask, cache key, guide-partial masking, mandatory
coordinator, and the remote-transfer wire work)
1. Phase 0 policy + tests (half session).
2. Option 2 core: reconciler inputs/fallbacks/cache + player suppliers incl.
   late-metadata + Home CW gating + single-owner bypass (~1 session).
3. Option 2 edges: movie/source fast paths, engine-target mask, guide
   partial masking + rewatch-detector inputs (~half–1; heaviest manual
   testing — CW/resume is the area just hardened by
   [[project_resume_write_guard]], re-run its device matrix after).
4. Option 1: flag normalization choke point + write gating + watched-action
   coordinator + page cleanup + remote-transfer wire (~1).
5. Option 3 WatchedStatusService mask (~small) + Settings UI/copy (~half).

## Test notes
- Unit: policy class; reconciler candidate AND fallback filtering (extend the
  rig noted in [[project_profiles_redesign]] gotchas if reused); cache-key
  includes policy; WatchedStatusService mask; launcher flag normalization
  (tracker-row launch with scrobble unticked → payload flags false).
- Manual matrix: king c0llier scenario END TO END (progress=This device,
  scrobble Trakt ON: watch past 80% but below local threshold → stays in CW
  here + marked watched on trakt.tv; then watch PAST the local threshold →
  local completion records and the show leaves local CW — pins the
  localCompletionTracking-follows-progress-policy fix); caught-up series
  still evicts from local CW in This-device mode; series with ONLY tracker
  progress in This-device mode shows fresh S1E1, not the engine's tracker
  episode (pins the engine-target mask); play with CW row hidden, re-enable
  the row, title appears (pins the write-gate move); Stremio-refugee
  (progress=Trakt,
  scrobble Trakt OFF — snapshot fetches must still run); launch FROM a Trakt
  row with Trakt unticked (native TV payload must carry trakt_scrobble=false);
  mark-watched from a Home card menu in ticks=Local mode (tick must render);
  mode switch updates the detail pill within one screen visit (cache);
  restore an old backup then check seeded masters (Trakt/Simkl ON);
  legacy user with old MDBList sync-catalog OFF → progress=MDBList still
  fetches playback/history (pins the frozen-key replacement); Smart-mode
  non-scrobbling play with CW row hidden → re-enable shows the title (render-
  side gate, all modes); remote profile transfer carries all three prefs;
  dedicated mode: guide shows NO foreign partial bars but keeps foreign ✓
  ticks, up-next follows the selected source; Smart-mode scrobbling user:
  local completion still NOT recorded (three-way rule preserves legacy);
  disconnect-while-dedicated fallback; TV DPAD on all three controls.
