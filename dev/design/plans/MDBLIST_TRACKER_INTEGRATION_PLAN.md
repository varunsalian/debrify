# MDBList Tracker Integration Plan

**Status:** implementation-ready plan, reviewed against the current call graph; feature remains disabled

**Validated:** 2026-08-22 against the official OpenAPI schema and a live, non-supporter API-key account

**Scope:** finish MDBList as a tracker, bring it to functional parity with Debrify's Trakt and Simkl integrations, and repair the list implementation before rollout

## 1. Outcome

MDBList must ship as more than a list browser. When enabled, it must support:

- account connection and API-budget visibility;
- My Lists, Liked Lists, top/curated/recommended/official lists, watchlist,
  history, collection, ratings, dropped shows, and Continue Watching;
- movie/show/episode watchlist, watched, rating, and collection actions;
- in-app and native-TV scrobbling for movies and episodes;
- cross-device movie and episode resume;
- Up Next for series;
- MDBList as a Calendar source and as an input to global watched badges;
- profile/resource isolation identical to the existing connection-resource model;
- deterministic failure behavior: a failed or partial request must never be
  rendered or imported as an authoritative empty/complete result.

Keep `kMdblistEnabled` off until the rollout gates in section 11 pass.

Official contract: <https://api.mdblist.com/docs/>

## 2. Verified API behavior

The following was exercised live with reversible test data. All temporary
watchlist, rating, collection, watched, dropped, playback, check-in, and list
state was removed after the probes.

| Flow | Live result | Implementation consequence |
|---|---|---|
| API-key authentication | Normal API key accepted on all tracker endpoints | Existing credential flow can be retained. |
| `POST /scrobble/start` | `201`, creates an active `/sync/now-playing` row | Use for an accurate active-playing state, subject to the durability decision below. |
| `POST /scrobble/pause` | `200`, creates a `/sync/playback` resume row | This is the durable Continue Watching checkpoint. |
| `POST /scrobble/stop` below 80% | Response action is `pause`; resume row remains | A normal early exit needs no separate pause call. |
| `POST /scrobble/stop` at 81% | Response action is `scrobble`; movie becomes watched | MDBList owns an inclusive `>=80%` completion rule. |
| `POST /scrobble/clear` | Removes the paused playback row | Correct removal operation for a paused Continue Watching card. |
| Pause followed by start | The paused row disappears; active row remains | Do not assume a prior pause remains as a crash-safe checkpoint after restart. |
| Active expiry | A one-minute test film was observed through its roughly ten-minute minimum lifetime; at expiry the active row vanished, with no playback row and no watched state | `start` and start-heartbeats are not crash-safe resume checkpoints. |
| Bare pause | A pause request without a preceding start created a playback row at the supplied progress | Use pause-centric checkpoints, as Debrify does for Simkl. |
| Movie playback payload | `movie`, string progress, runtime, paused/updated timestamps | Parser must accept numeric strings. |
| Episode playback payload | parent `show` plus `episode {season, number, ids}` | Retain parent IMDb ID and episode coordinates together. |
| `GET /upnext/watchlist` | Returned a never-started watchlisted show's first episode immediately | This is a Watchlist affordance, not Continue Watching. |
| `GET /upnext` | Appeared about four seconds after recording S01E01 | Treat aggregate/up-next writes as eventually consistent; refresh with bounded retry. |
| `POST /sync/state/*` | Supports TMDB or MDBList IDs, not IMDb IDs | Add an IMDb-to-TMDB resolver/cache before detail status can use this endpoint. |
| IMDb media lookup | `/imdb/movie/{id}` and `/imdb/show/{id}` return all IDs and rich metadata | Use as the resolver fallback when Debrify has only an IMDb ID. |
| Movie/show rating | Flat movie/show entries work | Use the existing Trakt-style 1–10 UI. |
| Episode rating | Nested `show -> seasons -> episodes` works | A top-level episode entry using its TMDB episode ID returned `updated: 0`; use only the proven nested form. |
| Whole-show collection | Expanded one test show into 6 seasons and 71 episodes | UI copy must say that collecting a show collects its episodes; never use this as a lightweight bookmark. |
| Watched history | Movie and nested episode writes worked; item history exposes play IDs | Supports watched/unwatched plus individual rewatch removal if later exposed. |
| Dropped show/season | Both write/read/remove flows worked | Dropping must be an explicit action; never hide it behind generic CW removal. |
| Sync journal | Returns retained latest watched/rating state, including removals, for 30 days | Use for incremental cache invalidation after the first full sync. |
| Liked lists | Like, read liked, and unlike all worked | The July “no working API” assumption is obsolete; restore real likes and remove clone-as-like behavior. |
| Static lists | Create/update/add/remove/membership/delete worked | Keep static-list management, but it is no longer the Save mechanism for public lists. |
| List pagination | Cursor and `pagination.next_cursor` worked; offset is deprecated | Replace offset walking with cursor walking. |
| Public discovery | Top/search/curated are arrays; recommended is `{sections: ...}` | Parse each endpoint explicitly rather than sharing an unchecked cast. |

## 3. Current Debrify gaps

The existing MDBList code implements account settings and list browsing only.
It has no methods or wiring for scrobble, playback sessions, Up Next, watched
history, ratings, watchlist, collection, dropped state, item state, last
activities, or journal sync.

There are also four list-side corrections required:

1. `fetchListItems` uses deprecated offset pagination.
2. A later-page failure returns `complete: false`, but the source adapter drops
   that flag, so browsing/import can silently accept a truncated list.
3. Public-list Save clones a static list because Liked Lists was assumed dead;
   the live API now supports real like/unlike and the account already returns
   liked lists.
4. The HTTP client is hardwired and there are no MDBList contract tests.

### 3.1 Code-audit surface map

The implementation must treat this table as a required inventory, not as a
suggestion. It records the concrete integration seams found in the current
codebase.

| Concern | Existing code seam | Required MDBList work |
|---|---|---|
| Credentials/profile isolation | `storage_service.dart`, `profile_credential_facade.dart`, `profile_app_lifecycle_participant.dart` | Keep the existing connection resource; add scoped non-secret preferences/caches and reset them with the MDBList service/calendar/CW services. |
| Settings and connection discovery | `mdblist_settings_page.dart`, `settings_screen.dart`, Settings search | Add sync toggle, quota/error state, correct DPAD reseeding, searchable terms, and integration-change notification. |
| Onboarding | `tracker_auth_controller.dart`, `trackers_step.dart` currently model only Trakt/Simkl device-code flows | Add a separate MDBList API-key card/controller. Do not force an API-key flow into the device-code controller. |
| App shell/Calendar availability | `main.dart` gates Calendar on Trakt/Simkl; `trakt_calendar_screen.dart` has a two-provider selector | Include MDBList auth in the shell gate and add an MDBList calendar source backed by `/calendar/events`, with generation/caching semantics matching the other providers. |
| Global watched badges | `watched_status_service.dart` merges local + Trakt + Simkl | Fold in MDBList completed movie/show snapshots without allowing a failed fetch to clear the previous set. |
| Details and episode UI | `search_screen.dart`, `catalog_browser.dart`, `aggregated_search_results.dart`, `catalog_item_detail_screen.dart`, `merged_series_detail_screen.dart`, `episodes_panel.dart`, `detail_model.dart`, `detail_identity.dart`, all alternate detail layouts | Thread MDBList auth/status/actions/rating through every entry path and layout. Add episode progress, watched, and rating overlays. Direct-source/no-IMDb mode must stay tracker-free. |
| Playback launch contract | `AdvancedSearchSelection`, `TorrentPlaybackService`, `VideoPlayerLaunchArgs`, and the launcher's two full manual argument rebuilds | Add MDBList source/progress/scrobble fields everywhere. Introduce a tested `VideoPlayerLaunchArgs.copyWith` before adding the field so a future rebuild cannot silently drop a provider. Keep `scopedToSeason` and all selection factories covered by copy tests. |
| In-app playback | `video_player_screen.dart` has separate Trakt and Simkl state/timers at every play, pause, seek, switch, completion, exit, and dispose hook | Add one MDBList-specific, reusable, fake-clock-tested state machine and feed it from the same lifecycle hooks. Do not route Trakt or Simkl through it or alter their existing state/timers. Add MDBList to local-completion suppression only while MDBList owns the playback. |
| Native Android TV | Kotlin emits progress; `_handleProgressUpdate` and `_handlePlaybackFinished` in `video_player_launcher.dart` perform tracker writes in Dart | Keep MDBList networking in Dart. Extend `_AndroidTvPlaybackPayload`, effective resume, per-episode progress maps, static timer/state reset, episode switching, teardown, and local-completion suppression. No MDBList secret belongs in the Kotlin payload. |
| External playback | `_seedTrackerContinueWatching` | Add the proven bare-pause MDBList 1% seed and include MDBList when deciding whether local CW is owned by a tracker. |
| Home/CW | `search_screen.dart` owns provider arrays/maps/nodes, `_CwKind` switches, row menus, focus queue, refresh fan-out, See All, startup autoplay | Add both MDBList rows and every switch/map/refresh/focus path; preserve rows on unknown failure. Add `mdblist:movies`/`mdblist:shows` to Home disable/order settings. |
| Home list rows | `home_list_rows.dart`, `home_sections_filter_page.dart`, Home row assembly | Define stable MDBList built-in/user/liked list row IDs, parsing, unavailable-row preservation, and canonical order so MDBList lists can be pinned to Home like the other trackers. |
| Discover/list import | MDBList See All/search/save widgets and Stremio TV local-catalog import/refresh | Add real Liked category, typed built-ins, cursor paging and partial-result blocking. Preserve imported catalogs while the flag is off but prevent all network refresh reachability. |
| Backup/profile transfer | profile package/restore, sanitized sharing policy, remote config export, Transfer Everything, `ConfigCommand` and remote router | Full encrypted profile backup already carries scoped non-secret preferences and the connection resource; add explicit tests. Keep the sync toggle out of credential-free sanitized exports, matching existing tracker settings. Add MDBList to device-to-device transfer protocol and every receive/rollback/summary path. Never put the API key in diagnostics. |
| Analytics/diagnostics | playback event currently reports only `trakt_scrobble`; integration and list events already exist | Report provider enablement symmetrically without media IDs or credentials; audit debug/error text so query-string API keys and full URIs cannot escape. |
| Flag | `kMdblistEnabled` gates Settings, Search/Discover, and import, but old imported-catalog refresh can bypass UI gates | Centralize the feature check at MDBList outbound service boundaries (except explicit connection/migration tests) and add a reachability test, not only widget-visibility tests. |

The old `HomeFocusController` tracker enum is used by deprecated Home code; do
not expand it unless a live reference is reintroduced. The current Home path is
the `_CwRow`/focus-queue implementation in `search_screen.dart`.

## 4. Product semantics

### 4.1 Continue Watching

Build MDBList Continue Watching from:

- `/sync/playback`: paused movies and episodes with resumable progress;
- `/upnext`: in-progress shows with the next unwatched episode.

Paused entries win over Up Next for the same show. `/upnext/watchlist` must not
be merged into Continue Watching because it includes titles the user has never
started. It belongs in the Watchlist view.

For removal:

- paused entry: call `/scrobble/clear`;
- pure Up Next entry: do not show generic “Remove from Continue Watching” in
  phase one. Offer a separately named “Drop show” action only where the user
  can understand its stronger meaning.

### 4.2 Resume precedence

Do not collapse episode selection and seek-position reconciliation into one
rule; the current code treats them differently.

- Movie, or the already-selected episode: seek to the furthest valid local,
  Trakt, Simkl, or MDBList position for that same media identity.
- Series target episode: preserve the existing Trakt -> Simkl -> local behavior
  for existing users, inserting MDBList after Simkl and before local unless the
  card was opened from MDBList, in which case its paused/up-next episode owns
  the selection. A later provider-neutral redesign may use comparable activity
  timestamps, but must not silently change Trakt/Simkl precedence in this work.
- A provider-computed Up Next is weaker than a real paused session and local
  last-played history. It is only a fallback when no resumable episode exists.
- Compare percentages only when they refer to the same movie or S/E identity;
  never compare `65% of S01E02` with `20% of S01E05`.

Ignore MDBList progress outside `0 < progress < 80` because 80 or more is
server-complete. The in-app player currently accepts broader remote values and
the detail screen filters movie resume differently, so normalize this once at
the MDBList model boundary and test that the button label, selected episode,
and actual seek always agree.

### 4.3 Scrobbling

MDBList accepts IMDb IDs for movie/show scrobbles. A series request must include
both season and episode; refuse half-resolved or unresolved series coordinates.

Use `>=80`, not `>80`, when choosing stop versus checkpoint. The server's rule
is inclusive.

Do not blindly copy Trakt's heartbeat or Simkl's pause-only behavior:

- start gives correct Now Playing but removes the paused resume row;
- pause creates the durable resume row;
- a subsequent start removes that row again.

Use a pause-centric strategy, as Debrify does for Simkl:

- issue a bare pause checkpoint when playback starts;
- refresh it periodically while playing;
- issue pause on a real user pause and stop on exit/completion;
- do not call start after a checkpoint.

Use a two-minute checkpoint initially, matching the existing player cadence,
but count all tracker calls against the account's reported daily allowance.
Coalesce duplicate ticks, apply `429` backoff, and stop checkpointing for the
session if the remaining budget reaches a conservative floor. Multiple devices
must not be able to turn a heartbeat into an unbounded retry loop.

This deliberately gives up MDBList's Now Playing state in exchange for durable
cross-device resume. The live expiry test proves that an active session simply
vanishes at expiry, while the bare-pause test proves no preceding start is
needed. Do not emit pause+start as a “checkpoint”; start deletes the durable row.

### 4.4 Multiple trackers

MDBList remains an independent tracker, like Trakt and Simkl. If users enable
more than one, Debrify will scrobble to all enabled trackers and render separate
provider rows. Local Continue Watching must be suppressed when any enabled
tracker owns the playback so the local row is not a fourth duplicate.

The current field `suppressTraktAutoSync` is already context-scoped and also
suppresses Simkl. Add a tracker-neutral replacement while retaining a backwards-
compatible alias and identical effective semantics for all current callers; do
not make a flag-off launch behave differently merely because the field name is
being repaired. Cover playlists, Stremio TV, trailers, IPTV/live channels, and
direct-source content with one suppression test table.

### 4.5 Trakt and Simkl non-regression contract

MDBList is additive. This project may touch shared launch arguments, Home/detail
plumbing, suppression naming, and provider fan-out, but it must not change the
observable Trakt or Simkl implementation. In particular, keep their existing:

- endpoint selection, request payloads, progress thresholds, timers, retry and
  error behavior;
- play/pause/seek/stop/episode-switch/external-player call sequences;
- Continue Watching membership, removal, ordering, and cache semantics;
- series episode-selection precedence and same-item resume calculations;
- profile/resource capability checks, logout/reset behavior, and sync-toggle
  defaults;
- local-history suppression behavior for every pre-MDBList launch context.

Do not “correct” an existing Trakt or Simkl threshold or consolidate either
provider into the MDBList state machine in this work, even if their policy is
different from MDBList's inclusive 80% rule. Shared refactors must land as
behavior-preserving changes with characterization tests before MDBList is added.
When the feature flag is off, or MDBList is disconnected/disabled, service-call
traces, selected episode, effective resume position, cached rows, and rendered
provider state must match the pre-change baseline.

When MDBList is enabled alongside existing trackers, its calls and rows are an
additional branch. The only intended cross-provider effects are the documented
same-item resume merge, MDBList's insertion after Simkl in series precedence,
and suppression of a duplicate local row when MDBList itself owns playback.
Those effects must disappear completely when MDBList is disabled.

### 4.6 Explicitly out of scope

The current official schema also exposes check-ins, discussions/comments,
following activity, people favorites, notification-device registration,
watch-provider links, external/shared lists, and account deletion. They are not
needed for Trakt/Simkl parity in Debrify and must not be pulled into this tracker
release:

- `/checkin` is a manual presence session, not durable playback; the verified
  pause-centric scrobble policy is the playback integration.
- discussion/social/follow/person-favorite APIs have no equivalent Debrify UI;
  adding them would be a new product feature, not tracker completion.
- APNS/notification preferences belong to MDBList's own notification system;
  Debrify must not register devices without a separate privacy/product design.
- account deletion is intentionally never exposed through an embedded API-key
  integration.

`/calendar/events`, `/user` usage, rich media lookup, and `/upnext/*` are in
scope where they support existing Debrify surfaces. `/user/stats`, public
catalog/search, and streaming-chart endpoints are optional enhancements, not
rollout blockers and must not be fetched in the background without a UI
consumer.

## 5. Phase 0 — repair the existing list integration

### Work

- Inject an `http.Client` into `MdblistService` while retaining the singleton
  default.
- Introduce a typed result that distinguishes success, empty, partial, denied,
  rate-limited, and transient failure.
- Walk `pagination.next_cursor`; retain `X-Has-More`/offset only as a defensive
  compatibility fallback.
- Propagate `complete`/partial status through `MdblistListSource`.
- Block Stremio TV import and refresh on partial data.
- Add `fetchLikedLists`, `likeList`, and `unlikeList`.
- Replace the search-only clone Save button with real like/unlike for public
  lists. Keep explicit “Clone to My Lists” as a separately named action.
- Do not auto-delete old clones or auto-like their source lists. Preserve the
  existing clone as a normal My List, clear only the obsolete source->clone UI
  marker after a one-time migration, and explain the change in release notes.
- For explicit Clone, chunk large add-item writes, stop on the first
  failed chunk, and either roll back the new list or surface it as incomplete;
  never send the current possible 25k-item accumulation as one request.
- Restore Liked Lists to Discover and Stremio TV import.
- Add curated/recommended/official sections only after their distinct payloads
  have typed parsers.
- Remove stale comments claiming likes, filters, or list search are unavailable.

### Tests

- cursor pagination across mixed movie/show pages;
- partial second-page failure is visible and never cached/imported;
- liked-list idempotency and unlike;
- create response as object and legacy array defensively;
- static-list rollback after add failure;
- top/search/curated array versus recommended-object parsing;
- flag-off reachability, including refresh of previously imported MDBList
  catalogs.

### Exit

No list operation can silently truncate data, and public Save no longer creates
a stale snapshot unless the user explicitly chooses Clone.

## 6. Phase 1 — tracker-capable service layer

### Files

- extend `lib/services/mdblist/mdblist_service.dart`;
- add `lib/services/mdblist/mdblist_models.dart`;
- add `lib/services/mdblist/mdblist_id_resolver.dart`;
- extend `lib/services/mdblist/mdblist_item_transformer.dart`;
- add focused tests under `test/services/mdblist/`.

### Service methods

Implement typed, profile-authorized methods for:

- scrobble start, pause, stop, and clear;
- playback and now-playing sessions;
- Up Next, upcoming, and watchlist Up Next;
- title/episode state batch lookup;
- watchlist add/remove/read;
- watched add/remove/read and item play history;
- ratings add/remove/read for movie, show, and nested episode;
- collection add/remove/read;
- dropped show and dropped season add/remove/read;
- last activities and sync journal.

All network boundaries must carry the captured profile/resource capability
through response publication, matching the remediated MDBList list operations.
For writes, construct and send the outbound request inside
`runIfCurrentAsOutbound`; checking only after the response is too late. A
playback session must capture its connection capability once at launch and use
that same capability for every timer callback/final stop, so a profile switch
cannot redirect an old movie's heartbeat into the newly active account.

### Identity

- Add optional TMDB/MDBList IDs to the MDBList-specific models; do not require a
  global `StremioMeta` migration in this phase.
- Resolve an IMDb-only title through `/imdb/{movie|show}/{imdb}/` and cache the
  ID tuple per resource/profile.
- Batch `/sync/state` calls in groups of at most 100 TMDB IDs.
- Scrobble and most writes should continue using IMDb directly; resolve TMDB
  only where the endpoint requires it.

### Error and quota rules

- `null`/failure is unknown, never “not in watchlist” or empty history.
- Parse progress from number or numeric string.
- Recognize `401/403`, `404`, `409`, `429`, 5xx, error bodies returned with 200,
  timeout, and malformed JSON separately.
- Read API usage from `/user`; avoid polling patterns that can exhaust the free
  daily allowance.
- Never log the `apikey` query parameter or a complete request URI.
- Centralize URI creation, timeouts, response decoding, retry/backoff, and
  redaction in one transport helper. Do not let each endpoint recreate auth
  query handling.
- Coalesce identical in-flight reads and tag every cache/in-flight future with
  both profile scope and connection-resource authorization revision.

## 7. Phase 2 — detail, episode, and Discover actions

### Models and helpers

Add:

- `MdblistTitleStatus`;
- `MdblistMenuOption` / `MdblistItemMenuAction`;
- `mdblist_menu_helpers.dart` parallel to the provider-specific Trakt and Simkl
  helpers.

Do not merge provider semantics into `TraktTitleStatus`. MDBList has collection,
watchlist, watched/completed, rating, dropped, and episode state that do not map
cleanly to either existing tracker.

### Surfaces

Wire MDBList status/actions into:

- catalog and merged movie/show details, their shared `DetailModel` identity
  controls, tracker sheets, and every alternate detail layout;
- episode tiles and `EpisodesPanel`, including auth resolution and the combined
  local/Trakt/Simkl/MDBList progress merge;
- Search/Home cards, `CatalogBrowser`, aggregated search, provider See All
  grids, and recommendation drill-downs;
- MDBList's own Discover lists.

Actions:

- add/remove Watchlist;
- mark watched/unwatched;
- rate/remove rating, including nested episode payloads;
- add/remove Collection with explicit whole-show expansion copy;
- drop/restore show or season as an explicitly named advanced action.

After a successful mutation, invalidate only affected state/list caches, bump
the shared finished revision where watched state affects card badges, and do a
bounded delayed refresh for eventually consistent show aggregates.

Add MDBList to `WatchedStatusService` so poster ticks are correct across the
whole app. A title-state fetch that fails remains unknown and must retain the
last good provider set; logout/disconnect or profile-scope reset is the only
immediate authoritative clear.

Add `MdblistCalendarService` over `/calendar/events`, map it into the existing
calendar entry display model (or rename that model provider-neutrally), include
MDBList in `main.dart`'s Calendar-tab auth gate, and extend the Calendar source
selector/cache generation. Calendar movie/person events that the existing
episode-only screen cannot render must be filtered explicitly in this phase;
request `favorite_cast=false` and never misparse movie/person events as
episodes. Supporting those event types is a separate Calendar product change.

## 8. Phase 3 — playback scrobbling

### Settings and launch contract

- Add `mdblist_sync_catalog_items`, default off for existing/migrated keys and
  set on after a successful new connection, matching both current Trakt and
  Simkl Settings/onboarding behavior. Preserve the preference on disconnect so
  reconnecting restores the user's choice, also matching those trackers.
- Add `mdblistScrobble` and `mdblistProgressPercent` to
  `VideoPlayerLaunchArgs`, `VideoPlayerScreen`, `_AndroidTvPlaybackPayload`,
  `AdvancedSearchSelection`, `TorrentPlaybackService`, all copy/rebuild sites,
  native effective-resume payload, per-episode progress snapshots, and the
  external-player seed path. Kotlin continues to receive only the already
  merged resume percent; it never receives credentials or performs MDB writes.
- Add `VideoPlayerLaunchArgs.copyWith` and a source-level constructor/copy test
  before touching the launcher's two full manual rebuilds.
- Add the MDBList toggle/status to `MdblistSettingsPage` and Settings search.
- Add a tracker-neutral replacement for `suppressTraktAutoSync`, retain the old
  constructor/getter as a compatibility alias, and prove identical behavior for
  current callers before updating local-CW/local-completion ownership checks to
  include MDBList.

### In-app player

Add provider-isolated MDBList state beside the existing Trakt and Simkl state:

- auth initialization;
- capture of one playback-owned profile/resource capability;
- movie/episode identity validation;
- play, pause, buffering, app inactive/paused/detached, seek-threshold,
  heartbeat, source switch, episode switch/auto-advance, completion, route exit,
  error, and disposal handling;
- no scrobble for trailers, live channels, unresolved series, or suppressed
  catalog contexts.

### Native Android-TV player

Feed the same state machine from the native activity's Dart event handler in
`video_player_launcher.dart`:

- payload field propagation;
- episode-switch stop for the previous episode;
- buffering treated as playing;
- exactly-once completion/exit stop;
- timer cancellation on route/player teardown;
- reset of all static MDBList session fields before and after each native
  launch, including failed launches.

### External players

Seed a 1% paused MDBList row before handing off, as Debrify already does for
tracker-owned Continue Watching. This is an honest “playback launched” marker,
not real external-player progress. Document that external progress cannot be
known unless that external player independently integrates MDBList.

### Tests

Use a fake client and fake clock for transition tables, not widget-timer sleeps:

- movie and episode play/pause/stop;
- exactly 80%;
- seek above 80 and seek back below;
- auto-advance stops old episode before starting/checkpointing new episode;
- hard-kill checkpoint policy selected by the expiry gate;
- no one-coordinate series payload;
- concurrent Trakt + Simkl + MDBList enabled;
- characterization call traces for Trakt-only, Simkl-only, and Trakt+Simkl
  before and after every shared launch/player refactor;
- profile switch/resource revoke during every awaited request;
- app background/foreground, route pop, player error, source switch, failed
  native launch, and sync-toggle change during playback;
- constructor/copy propagation and local-CW/local-completion suppression across
  every tracker combination.

## 9. Phase 4 — MDBList Continue Watching and resume

### Files

- add `lib/services/mdblist/mdblist_continue_watching_service.dart`;
- extend `AdvancedSearchSelection` with MDBList progress/source fields;
- extend Search/Home state, loading, card maps, focus nodes, refresh paths, and
  startup autoplay handoff;
- add a provider-specific MDBList See All Continue Watching choice;
- add `mdblist:movies` and `mdblist:shows` to Home section filtering, global row
  ordering, accessibility announcements, hold-OK menus, keyboard/DPAD switch
  statements, and canonical-order tests.
- extend native per-episode tracker progress storage/merge so playlist bars and
  switched-episode resume include MDBList rather than only the launch item;
  add a profile-scoped `episode_mdblist_progress` replaceable snapshot beside
  the existing Trakt/Simkl stores and seed it before series playback.

### Merge algorithm

1. Fetch `/sync/playback` and every `/upnext` page concurrently where possible;
   `/upnext` uses `limit`/`offset` plus `has_more` even though list-item APIs use
   cursor pagination.
2. Parse movies and episodes from playback.
3. Group episode sessions by parent-show IMDb ID, keeping the newest paused
   session.
4. Convert `/upnext` rows to zero-progress series selections.
5. Let paused rows replace Up Next rows for the same show.
6. Sort paused rows by `paused_at`; place Up Next using `last_watched_at`.
7. Preserve the previous UI rows on transient failure; clear only when an
   authenticated request authoritatively returns empty or the account logs out.

Removal calls `/scrobble/clear` only for paused rows. After clear, refresh the
specific provider row and resume maps.

Account for the observed several-second delay before `/upnext` reflects a new
episode completion: update the immediate card locally, then retry the server
aggregate with capped backoff rather than hammering the endpoint.

### Cross-cutting release integration

- Add a separate MDBList API-key card/controller to onboarding. API-key
  paste/reveal behavior must match the existing secure Settings field and TV
  keyboard flow; successful connection enables catalog sync just as the other
  tracker onboarding flows do.
- Include the connection resource, username, sync preference, journal cursor,
  and caches in profile reset/rotation/restore tests. Credentials travel only
  in encrypted connection-resource backup/transfer sections; sanitized profile
  exports must never contain them.
- Extend device-to-device Remote Config and Transfer Everything end to end:
  command constant, sender inventory/card, encrypted payload, receiver routing,
  validation, transactional rollback, summary, tests, and integration refresh.
  Failed validation must roll back without changing the prior MDBList resource.
- Update `MainPageBridge` refresh fan-out and auth refresh after detail/player
  returns, logout, profile switch, and external-player return.
- Add MDBList to Calendar-tab shell gating and to Settings/Home discoverability
  only while the feature flag is enabled.
- Update playback analytics to report Trakt, Simkl, and MDBList symmetrically as
  booleans or a fixed provider set. Never attach IMDb/TMDB/MDBList IDs, list
  names, account names, progress, or API usage to analytics/crash breadcrumbs.
- Add accessibility labels, focus restoration, keyboard traversal, DPAD tests,
  and theme shape-manifest entries for every new card/sheet/control.
- Add a one-time cleanup for obsolete `mdblist_saved_clones` markers without
  deleting the actual remote lists the user created.

## 10. Phase 5 — efficient account sync

Start with full snapshots. Add incremental sync only after correctness is
covered:

1. persist the server timestamp from `/sync/last_activities` per connection
   resource;
2. compare bucket timestamps before refetching watchlist/watched/ratings/
   collection/dropped/playback;
3. use `/sync/journal?since=` for exact watched/rating changes and removals;
4. replay every cursor page;
5. if the journal reports `requires_full_sync` or the cursor is older than the
   30-day retention window, discard the checkpoint and run a full snapshot;
6. scope every checkpoint and cache to the MDBList connection resource, not a
   process-global account.

The journal only supplies watched/rating deltas. Watchlist, collection, dropped,
playback, lists, and Calendar must still be invalidated from their own activity
bucket/timestamps or fetched with bounded TTLs; never infer journal silence as
“nothing changed” for those domains.

This phase is required before enabling aggressive Home/detail refreshes on the
1,000-request/day free tier.

## 11. Rollout gates

The flag may turn on only after all of these pass:

- [x] Replace offset list pagination and propagate partial status.
- [x] Restore real Liked Lists and remove clone-as-like UI semantics.
- [x] Dedicated fake-server tests cover the implemented endpoint families and
      transport error classes.
- [x] Live create/mutate/remove smoke test leaves the account exactly as found.
- [x] Active-expiry and bare-pause behavior verified live; pause-centric
      checkpoint policy selected and recorded above.
- [ ] In-app movie and episode scrobble verified on phone/tablet/desktop/tvOS.
- [ ] Native Android-TV movie, pause/resume, auto-advance, completion, and exit
      verified on a device.
- [ ] External-player 1% seed verified and accurately described in Settings.
- [ ] Continue Watching refresh verified across two devices/accounts.
- [ ] Movie/episode resume label, selected episode, and actual seek agree when
      local, Trakt, Simkl, and MDBList contain conflicting positions.
- [ ] Exactly-80%, low-progress stop, clear, rewatch, and dropped-show behavior
      verified live.
- [ ] Calendar source, watched badges, episode progress/ratings, Home row
      filtering/order, and every detail layout pass widget/DPAD tests.
- [ ] Multi-profile switch, revoke, resource rotation, logout, backup/restore,
      remote transfer, and app reset tests pass with no cross-profile request,
      cache publication, or timer callback.
- [ ] Playback-owned capability test proves a profile switch cannot redirect an
      old session's heartbeat/final stop into the new account.
- [x] API-key values are absent from logs, diagnostics, analytics, crash reports,
      and test artifacts.
- [ ] Free-tier budget test covers request coalescing, `429` backoff, retry caps,
      and heartbeat shutdown at the safety floor.
- [ ] Flag-off test proves no Settings, Discover, Search, import, refresh,
      background sync, or scrobble path can reach MDBList.
- [ ] Trakt-only, Simkl-only, and Trakt+Simkl characterization suites prove
      identical endpoint payloads, call order, thresholds, timer cadence,
      Continue Watching rows/removal, resume selection, caches, and local
      suppression with MDBList off or disconnected.
- [ ] A source-level audit proves neither existing provider is routed through
      the MDBList state machine and no Trakt/Simkl endpoint or model contract was
      edited as part of the tracker implementation.

## 12. Recommended commit sequence

1. `MDBList: inject client + typed API results`
2. `MDBList: cursor paging + partial-list correctness`
3. `MDBList: restore liked lists and real like/unlike`
4. `Playback: tracker-neutral launch copy and suppression contract`
5. `MDBList: tracker models, ID resolution, state and sync APIs`
6. `MDBList: details, episodes, watched badges and calendar`
7. `MDBList: in-app scrobble state machine`
8. `MDBList: native-TV and external-player tracking`
9. `MDBList: Continue Watching, Home rows and cross-device resume`
10. `MDBList: profile backup, transfer, reset and analytics integration`
11. `MDBList: activity/journal incremental sync`
12. `MDBList: rollout gates, live matrix and flag enablement`

Each commit must keep `kMdblistEnabled` false and leave existing Trakt/Simkl
behavior unchanged until the final rollout commit. If a shared refactor cannot
be proven behavior-preserving with the characterization suite, it does not land
as part of this implementation.
