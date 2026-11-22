# Ledger tracker integration

"Ledger" is a **placeholder code name** for Debrify's own watch tracker, the
service at https://debrify.garib.dev/ (API https://debrify-api.garib.dev,
contract in the `debrify-sync` repo at `openapi/debrify.openapi.yaml`). Its
development build calls itself "Debrify Sync"; neither name is final.

## Renaming before release

The user-facing name comes from one constant, `kLedgerDisplayName` in
`lib/features/ledger/models/ledger_brand.dart`. Change it there; every
settings page, card, row title and message follows.

Code identifiers (`Ledger*`, `ledger_*.dart`) may be renamed freely. These
values are **persisted** and need a compatibility migration if they change
after any build ships:

| Persisted value | Where |
| --- | --- |
| `TrackingSource.ledger`, `WatchProgressSource.ledger` (stored by `.name`) | tracking preferences (`tracking_scrobble_targets`, `watch_progress_source`, `home_tick_sources`), backups, WebDAV sync |
| `ledger_access_token`, `ledger_refresh_token`, `ledger_username`, `ledger_token_expiry` | `lib/services/storage/ledger_storage.dart` |
| `episode_ledger_progress_v1` | `TrackerEpisodeProgressStorage` |
| Home row id `ledger:continue` | saved Home order / hidden rows (`HomeLedgerRowIds`) |
| analytics property `ledger_scrobble` | `LaunchAnalytics.trackPlaybackStarted` |

## Feature flag

Ledger ships hidden: `kLedgerEnabled` (`ledger_brand.dart`) is false in
builds. While it is off there is no Settings card, Tracking page option,
Home layout entry or sign-in, Home row orders are not seeded with
`ledger:continue`, and `LedgerStorage` reports no session (a session stored
by a dev build is ignored), so nothing calls the service and users see the
app as it was before Ledger. Stored, defaulted and transferred tracking
preferences leave Ledger out (a `ledger` value from a dev build reads as
unknown), analytics and diagnostics carry no Ledger fields, a series reset
writes no Ledger snapshot, and launch, episode lists and watched-state
refreshes skip their Ledger steps without an extra await. Turn it on once the name is final. Tests turn
it on with `debugLedgerEnabled = true` (reset to null in tearDown); the
flag-off behaviour has its own tests.

## What is integrated

Ledger follows Trakt's model (START and PAUSE save a resume point; a STOP at or
past the user's watched percent records a play), so it mirrors the Trakt paths
with its own state.

- **Account:** device sign-in (RFC 8628) committed only into the profile
  that started it, rotating refresh tokens with single-flight refresh per
  profile, 401 renew-and-retry once, a refused refresh token signs the
  profile out locally, sign-out revokes the session. Settings → Trackers
  card, Ledger settings page, "Import history" from Trakt/Simkl accounts
  linked on the website.
- **Profiles: the session is per profile and per device.** Ledger revokes a
  whole session when an already-exchanged refresh token is presented again,
  so a copied token pair would sign every copy out. Unlike Trakt/Simkl it is
  therefore NOT a connection resource: it is never shared between profiles,
  synced (WebDAV), imported, exported or backed up. The tokens live in the
  profile's preferences sealed with the device key, their keys are
  non-portable, and a profile switch abandons pending sign-ins. Each device
  (and each profile) signs in once.
- **Tracking policy:** Scrobble target, Progress source and Watched-ticks
  source on the Tracking page. Native (`simkl:`) and custom identities fall
  back to local like Trakt/MDBList.
- **Playback:** in-app player (`VpLedgerScrobbler`), Android TV native player
  (`NativeLedgerSession`, payload percents), external players (resume-point
  seed that never overwrites a real position). Both state machines finalise
  at the account's watched percent (`/v1/me/tracking-settings`, default 80),
  not a hard-coded 80. Resume (launches that scrobble to Ledger, or any
  launch while Ledger is the connected Progress source; decided
  synchronously so other launches keep their exact timing; a movie's live
  read is capped at 3 s so a slow server never holds startup): launch percent,
  movie resume read live, per-episode snapshot (`episode_ledger_progress_v1`,
  read per show, only while connected, cleared on sign-out).
- **Watched state:** poster ticks (watched movies; series with every aired
  regular episode played = watched shows with a regular episode played,
  absent from Up Next, and neither hidden from progress nor dropped), episode
  guide ticks/bars, mark title/episode/season watched/unwatched.
- **Home:** one "Ledger Continue Watching" row from Up Next (resumes + next
  episodes in server order), See All, removal (a movie: delete its resume
  point; a show: delete it and hide the show from Up Next, or it would come
  straight back as its next episode), hide/reorder in Home layout. Users
  without Ledger get no extra rebuild: an empty row that stays empty
  publishes nothing.

## Not yet integrated (follow-ups)

Each was deliberately left out of the first pass to keep the change
reviewable and regression-free:

1. Detail-page Ledger pill/sheet (watchlist, rating, lists) and Discover
   source. `LedgerService` already exposes `setWatchlisted`, `rate`,
   `titleStatus`; the API client covers lists.
2. Home watchlist/list rows and See-All for Ledger lists.
3. Calendar / Airing soon source (`LedgerApi.calendar` exists).
4. Detail-page Play/Resume resolver (`home_series_resume_resolution.dart`,
   `home_catalog_playback_resolver.dart`): its integer source priorities
   (0 Trakt … 3 local) need renumbering to add a tracker. Until then a detail
   page's Play picks the episode from local/Trakt/Simkl/MDBList; the player
   still resumes from Ledger's position, and the Ledger row resumes exactly.
5. Onboarding tracker step and settings search entries. (Remote transfer,
   sync and backups intentionally never carry Ledger sessions; see Profiles.)
8. Home's Ledger row refreshes on return from playback like the other
   tracker rows; the final STOP is sent without waiting, so the row can
   briefly show the pre-stop state until the next refresh.
9. Turning the feature flag on (see Feature flag) once the name is final.
6. Localization: settings and player strings follow the surrounding
   English-only code; there is no localization infrastructure yet.
7. Completed-series ticks are skipped (not guessed) when Up Next returns a
   full page (100 entries), because the list could be truncated.

10. Rotating refresh tokens: if a refresh response is lost (timeout, app
    killed) the next refresh presents an already-used token and the server
    revokes the session; the app then shows Ledger as disconnected and the
    user signs in again. Deleting a profile forgets its session locally but
    does not revoke it server-side (it expires on its own).

## Compatibility notes
- The Progress source choice syncs between devices but Ledger sessions do
  not, so a device without a Ledger session reads a synced "Ledger" choice as
  Smart in memory and never rewrites it (signing out also leaves it alone).
  Home's Continue Watching cards use the same effective value
  (`TrackingSourceStorage.getEffectiveWatchProgressSource`). On such a
  device the Tracking page shows Smart; picking Smart there saves it and
  moves the synced devices off Ledger, and no "fell back" notice is shown.
- Movie resume reads Ledger under one rule on both players (in-app and
  Android TV): when the launch scrobbles to Ledger or Ledger is the connected
  Progress source, via `LedgerService.movieResumePercent` (capped at 3 s). An
  in-app Ledger resume that finishes after the item changed is dropped.
- The resume rewatch detector (`hasActiveTraktEpisodeRewatch`) stays
  Trakt-only on purpose: it migrates legacy builds that stored Trakt history
  as local completion, which never happened for Ledger.
- Every Ledger request is pinned to the profile that started it, so a
  refresh or 401 retry that lands after a profile switch still uses that
  profile's tokens.

- Ledger adds no connection-resource type, so profile databases, backups
  and WebDAV sync circles stay readable by older app versions.
- Stored scrobble-target lists without `ledger` keep Ledger off until the user
  connects it (connecting turns it on, like Trakt/Simkl).

## Size exceptions

Hard caps (`check_search_architecture.py`) were met by behavior-neutral
extractions: `EpisodeTrackerPercents` (per-episode tracker percents, used by
the payload builder, native launch and metadata push), `NativeScrobbleSession`
reset helpers, `LaunchAnalytics.trackPlaybackStarted/logPlaylistEntries`,
`applyTrackerSummaries`, `VpStremioTvNextLoadingOverlay`, the shared
Simkl/Ledger snapshot refresh and `EpisodeSnapshotRefreshCoordinator`.

One baseline raise recorded in `dev/tool/file_size_baseline.txt`
(2026-11-20): `home_sections_filter_page.dart` +3 (two imports and the feature-flag
line for the Ledger group). Exit: the next extraction of that page's group model.
`lib/services/ledger/ledger_service.dart` (~600 lines) is in the 501–800
review band: split reads and writes when it next grows.

## Evidence

Recorded under `.git/ledger-evidence/` (not committed): analyzer before/after
(identical diagnostic sets), full-suite failure lists before/after by test
name (2026-11-20 run 9 with the feature flag off, fingerprint 2ec4a13cafe7abd3:
16781 passed, the same 33 failures as both full runs of the original code,
none new), a video-player folder stress
comparison against the original code (`stress.txt`), live API fixtures (`scratchpad`) from a throwaway account on the dev
server.
