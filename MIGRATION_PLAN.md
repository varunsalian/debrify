# Migration — implementation plan

Bring a user's setup **into** Debrify from another app. Ship this as a new
**Settings → Migration** section. The first source is **Stremio account import**.
Nuvio file import is designed for but is not part of this change; phase 5 defines
the source-neutral seam it must reuse.

Everything below is grounded in the current Debrify tree and the current
Stremio Core API models. Line numbers are navigation hints only; re-grep before
implementing.

---

## 0. Scope

### In for v1

- Authenticate with email/password or an existing Stremio auth key.
- Fetch the account's addon collection and library without modifying either.
- Let the user choose addons, watchlist, progress, and watched/completed state.
- Addons → the active profile's Stremio addon collection.
- Saved movie/series library rows → My Watchlist.
- Last movie or series-episode progress → `playback_state_v1` and, when
  eligible, the local Continue Watching shelf.
- Watched movies → `finished_movies_v1`.
- The one last series episode directly evidenced by progress at or above the
  active profile's episode-completion threshold → that episode's existing
  `finishedEpisodes` representation in `playback_state_v1`.

### Explicitly out for v1

- Writing addons, library data, progress, or history back to Stremio.
- Debrid credentials; Stremio does not expose them here.
- `video_resume_v1`; see the invariant in section 2.
- Full watched-episode history. Stremio's `state.watched` is an encoded watched
  field, not a boolean. Correctly decoding it requires the ordered video list
  for each series, which is not present in `datastoreGet`. Do not guess episode
  history from `timesWatched`, `flaggedWatched`, or the last `video_id`.
- Nuvio import.

If full Stremio episode-history import is requested later, design it as a
separate phase that fetches series metadata, decodes Stremio's watched bitfield
against the ordered video IDs, and has fixtures copied from the current Stremio
Core behavior.

---

## 1. Stremio API contract

Use three POST requests to `https://api.strem.io`. No new dependency is needed:
`http` and `dart:convert` are already available.

```text
POST /api/login
  {email, password, facebook: false}
  -> result.authKey
  -> result.user._id / result.user.email

POST /api/addonCollectionGet
  {authKey, update: true}
  -> result.addons[] / result.lastModified

POST /api/datastoreGet
  {authKey, collection: "libraryItem", ids: [], all: true}
  -> result[]
```

The current response envelope is one of:

```jsonc
{"result": /* endpoint result */}
{"error": {"message": "...", "code": 123}}
```

Do not parse an `err` field and do not expect `_id` or `email` directly beside
`authKey`. Parse the structured error and show a short actionable message. Do
not echo an arbitrary server response, response body, request body, email,
password, or auth key. Diagnostics must use a stable event label through
`PrivacyLog.redact`.

Check HTTP status, JSON shape, and endpoint-specific result shape separately.
Give login, addon, and library calls explicit timeouts. Treat malformed rows as
row failures where possible rather than failing an otherwise usable import.

### Library item shape used by the importer

```jsonc
{
  "_id": "tt1234567",          // generic Stremio item ID; not always IMDb
  "name": "Some Title",
  "type": "movie" | "series" | "other",
  "poster": "https://...",
  "posterShape": "poster",
  "removed": false,
  "temp": false,
  "_ctime": "2026-01-01T00:00:00Z",
  "_mtime": "2026-01-02T00:00:00Z",
  "state": {
    "lastWatched": "2026-01-02T00:00:00Z",
    "timeWatched": 4290000,
    "timeOffset": 4290000,     // MILLISECONDS
    "overallTimeWatched": 4290000,
    "timesWatched": 0,
    "flaggedWatched": 0,
    "duration": 7200000,       // MILLISECONDS
    "video_id": "tt1234567:1:5",
    "watched": null,           // encoded watched field when present, not bool
    "noNotif": false
  },
  "behaviorHints": {}
}
```

Important parsing rules:

- `timeOffset` and `duration` are already milliseconds. **Never multiply by
  1000.**
- `_id` is a generic Stremio ID. Treat it as an IMDb ID only if it matches the
  supported IMDb form (`^tt[0-9]+$`, case-insensitive). Normalize it to
  lowercase before comparison/storage.
- Debrify v1 targets require an IMDb ID. A movie/series with another ID is
  `skippedUnsupported`, with a non-sensitive reason in the result.
- `name` must be non-empty for watchlist or playback rows. Missing presentation
  fields such as poster, year, and dates remain nullable.
- Only `movie` and `series` are supported. Skip `other`, `channel`, `tv`, and
  unknown types.

### Library flags and domain eligibility

- Watchlist: `!temp && !removed`.
- Playback-state seed: valid IMDb ID, valid positive progress, and the required
  title/episode coordinates. A removed or temporary item may still seed
  playback state.
- Continue Watching: match Stremio's current eligibility within Debrify's
  supported types: `(!removed || temp) && timeOffset > 0`, then exclude items
  Debrify considers complete.
- Movie completion candidate: `type == movie && timesWatched > 0`. Do not use
  the series count to manufacture completed episodes.
- `timesWatched > 0` is historical, not proof that the current movie state is
  complete. Valid current progress below the profile's movie-completion
  threshold is an active rewatch. Treat it as progress; do not turn it back into
  a finished marker merely because `timesWatched` remains non-zero.
- A movie whose current state is complete is eligible for
  `finished_movies_v1`, removal from local Continue Watching, and removal of
  resumable movie state, subject to the timestamp conflict rules in section 2.
  "Current state is complete" means valid progress at/above
  `getMovieCompletionThreshold()`, or historical `timesWatched > 0` with no
  valid below-threshold current progress.
- For a series, parse the last `video_id` only when it has a valid
  `<base>:<season>:<episode>` suffix with positive integer season and episode.
  A malformed `video_id` does **not** turn the item into a movie: keep its series
  watchlist eligibility and skip only its episode progress.
- Valid last-episode progress at or above
  `StorageService.getEpisodeCompletionThreshold()` marks only that directly
  evidenced episode finished. It does not decode or infer any other episode.

Addon descriptors may have `flags.official == true`. Default official addons
off in the picker because Debrify bundles equivalents, but allow users to select
them.

### Authentication lifetime

- Never persist or log the password or auth key.
- Keep secrets only in page/service memory and clear controllers/state on
  dispose and after completion.
- An auth key created by login is a server-side session; dropping the local
  string does not revoke it. Do not claim otherwise in UI copy.
- Do not automatically call logout for a pasted auth key because it may be a
  session the user is actively using elsewhere. Account-session revocation is
  outside v1.

---

## 2. Debrify destinations and invariants

| Source | Debrify target | Existing behavior to preserve | Identity |
|---|---|---|---|
| saved library row | `my_watchlist_v1` | `setMyWatchlistItem` | `type:imdbId` |
| series last-episode progress | `playback_state_v1` | `saveSeriesPlaybackState` shape | `series_<slug(title)>` + S/E, with IMDb ID |
| movie progress | `playback_state_v1` | `saveVideoPlaybackState` shape | `video_<slug(title)>`, with IMDb ID |
| eligible shelf item | `continue_watching_v1` | `saveContinueWatchingItem` shape and 50-row cap | normalized IMDb ID |
| watched movie | `finished_movies_v1` | `markMovieAsFinished` semantics | normalized IMDb ID |

### Never import into `video_resume_v1`

`video_resume_v1` is source-file keyed (`torbox_<torrentId>_<fileId>`, PikPak
IDs, playlist IDs) and lives in `IptvMediaStore`. Those identities do not exist
until a Debrify source is selected. Synthetic rows would be unreadable. Account
migration touches only `playback_state_v1` for title-level progress.

### Playback-state keys are title-slugged, IMDb is the stable lookup

Series keys use `series_<slug(title)>`; non-series keys use
`video_<slug(title)>`. Always retain Stremio's name verbatim and attach the
normalized IMDb ID. Debrify's movie player can resolve the most recent video
state by IMDb ID, and series lookup scans entries by IMDb ID.

Define one shared key helper in `StorageService` for each shape and reuse it in
single and bulk writers. Do not duplicate slug derivation in migration code.

For an imported movie seed, use the existing video-state schema with `type:
video`, the Stremio title, normalized IMDb ID, imported position/duration,
source `lastWatched` as `updatedAt`, and an empty URL. Prefer making URL optional
in the seed model rather than inventing a playable URL. Verify both direct-link
and playlist movie resume paths use the IMDb fallback correctly.

### Deterministic merge policy

Everything is a merge; incoming data never deletes unrelated local data.

- Watchlist: existing identity wins completely, including presentation metadata
  and `addedAt`; a missing identity is inserted using `_ctime` as `addedAt` when
  valid, otherwise import time.
- Completion/progress conflicts are resolved as one decision per movie or
  episode, not by independently applying a completion seed and a progress seed:
  - An existing local finished marker wins over incoming progress.
  - Otherwise find the newest local progress row for the same identity and
    compare it with incoming `lastWatched`.
  - Newer local active progress wins over incoming completion, preserving a
    local rewatch. If incoming completion has no valid timestamp and local
    progress exists, local progress wins.
  - Newer incoming active progress wins over older local progress.
  - Newer incoming completion marks the item complete and removes the older
    resumable/CW state.
  - With no local state, import the valid incoming state. A historical
    `timesWatched > 0` plus current below-threshold progress imports as an active
    rewatch, not completion.
- Because `finished_movies_v1` has no completion timestamp, an existing local
  finished movie cannot be safely ordered against an incoming rewatch. Preserve
  the local marker and report the incoming rewatch as `skippedConflicts`; do not
  save an unusable progress row that movie readers will suppress.
- A local watched marker is never removed by migration.
- Progress identity is IMDb-based before it is slug-based. For movies, inspect
  every `type: video` row with the normalized IMDb ID. For series, inspect every
  series row with the normalized IMDb ID and matching season/episode. Use the
  newest matching row for conflict resolution; a different title slug must not
  bypass the merge policy or create an apparently newer duplicate.
- Imported state is written to the canonical key derived from the source title.
  Existing alternate-slug rows are left intact unless an incoming completion
  wins, in which case all matching resumable rows for that movie/episode are
  cleared consistently. Readers may continue to encounter historical alternate
  rows, so tests must cover them.
- Continue Watching: dedupe by normalized IMDb ID and keep the newer row by
  `updatedAt`. Sort newest first and retain the newest 50 across local and
  incoming rows. Import must not evict a newer local entry in favor of an older
  Stremio entry.
- Re-running an unchanged import performs no writes and reports existing/equal
  rows as duplicates. Imported source timestamps must be preserved; using
  `DateTime.now()` for every row would violate idempotency.

Invalid progress (`position <= 0`, `duration <= 0`, `position > duration`) is
skipped. Clamp only a small server rounding overshoot if explicitly covered by
a fixture; otherwise count it as invalid. Read the active profile's thresholds
once with `StorageService.getMovieCompletionThreshold()` and
`StorageService.getEpisodeCompletionThreshold()` and put them into the planned
local batch. Do not define a second percentage in the importer.

---

## 3. Implementation phases

### Phase 1 — serialized bulk mutation seam

Per-item storage writers repeatedly decode and encode whole blobs, making a
large import O(N²). Add one coordinated, source-neutral local batch writer
beside the existing single-item methods:

```dart
static Future<LocalLibraryMigrationResult> bulkApplyLocalLibraryMigration(
  LocalLibraryMigrationBatch batch,
);
```

`LocalLibraryMigrationBatch` carries watchlist seeds, Continue Watching seeds,
movie/episode progress seeds, movie-completion candidates,
episode-completion candidates, the captured completion thresholds, and source
timestamps. It contains no Stremio-specific fields.

Requirements:

- Seed/result types are source-neutral; no Stremio fields in bulk writers.
- Enter one per-profile mutation lock, read each affected blob once, resolve all
  completion/progress conflicts in memory, and write each changed blob at most
  once. Skip every write whose encoded state is unchanged.
- Serialize the coordinated batch with all single-item mutations of the same
  blobs.
  A stale bulk snapshot must not overwrite a player autosave or watchlist tap.
  Prefer one shared storage mutation queue/lock rather than an importer-only
  lock.
- Reuse shared key builders and canonical IMDb normalization.
- Decode large JSON with `decodeJsonAsync`.
- Preserve the Continue Watching enabled gate and 50-row limit.
- Winning movie completions remove matching movie playback/CW rows in this same
  locked batch. Winning episode completions update `finishedEpisodes` and the
  corresponding episode progress shape in the same playback-map mutation.
  Increment `localCompletionRevision` once if any completion changed.
- Preserve source timestamps as specified by the merge policy.

Tests:

- 2,000 watchlist seeds decode once and write once.
- Existing watchlist metadata and `addedAt` are preserved.
- New watchlist `addedAt` uses source creation time.
- Newer progress wins; older/equal/undated-over-existing progress is a no-op.
- Finished local state wins over incoming progress.
- A newer local rewatch survives older incoming movie completion.
- Below-threshold incoming movie progress with historical `timesWatched > 0`
  imports as a rewatch, not a completion.
- Same-IMDb movie rows with different slugs participate in one conflict.
- Same-IMDb/S/E series rows with different slugs participate in one conflict.
- Threshold-complete last-episode progress marks only that episode finished.
- Continue Watching keeps the newest 50 and honors the disabled gate.
- Concurrent queued autosave and bulk import retain both mutations.
- A second identical bulk apply performs zero preference writes.

### Phase 2 — `StremioAccountService`

Create `lib/services/migration/stremio_account_service.dart` with models under
`lib/models/migration/`:

```dart
Future<StremioSession> login(String email, String password);
StremioSession sessionFromAuthKey(String authKey);
Future<List<StremioAccountAddon>> fetchAddons(String authKey);
Future<List<StremioLibraryItem>> fetchLibrary(String authKey);
```

`StremioSession` holds the auth key and optional account identity in memory.
`login` fills identity from `result.user`; `sessionFromAuthKey` has no account
identity. Treat an auth key as opaque: locally trim it, require non-empty input,
and enforce only a generous input-size limit. Do not impose a character-pattern
regex. The subsequent addon/library reads validate it remotely without adding a
fourth API call. It is never persisted.

Requirements:

- Inject the HTTP client/base URI for unit tests; production base URI is fixed
  to `https://api.strem.io`.
- Parse `{result}` and `{error: {message, code}}` correctly.
- Parse login identity from `result.user`.
- Tolerate null/absent optional fields and numeric fields represented as JSON
  integers or doubles. Reject a row only when its required domain fields cannot
  be used.
- Use bounded response sizes where the HTTP layer allows it and explicit
  timeouts; `datastoreGet` may be large.
- Never log request bodies, response bodies, email, password, or auth key.
- Verify `all: true` against a large real account. If the API caps results,
  discover and document the supported paging/batching mechanism before adding
  it; `ids` batching cannot discover unknown IDs by itself.

Tests use captured, sanitized fixtures for success, structured API error,
non-200, invalid JSON, null fields, non-IMDb IDs, and a large library response.

### Phase 3 — pure source planning and profile-bound apply

Create `lib/services/migration/stremio_migration_payload.dart`:

```dart
abstract final class StremioMigrationPayload {
  static StremioMigrationPlan plan(
    List<StremioAccountAddon> addons,
    List<StremioLibraryItem> items,
  );

  static Future<MigrationApplyResult> apply(
    StremioMigrationPlan plan,
    MigrationSelection selection,
    ProfileAsyncAuthorization authorization,
  );
}
```

`plan()` is pure. It validates IDs/types, parses the last episode coordinates,
preserves millisecond progress and source timestamps, and builds source-neutral
seeds. It does no network or storage I/O.

`MigrationSelection` has domain booleans for addons, watchlist, progress, and
watched/completed state, plus the selected addon descriptor identities.
Threshold-derived completion of the directly evidenced last episode belongs to
the progress domain. Movie completion directly evidenced by at/above-threshold
current progress also belongs to the progress domain; historical movie
completion from `timesWatched > 0` belongs to watched/completed state. If both
domains select the same completion candidate, apply and count it once. An active
rewatch is eligible only for the progress domain. Official addons start
unselected.

`MigrationApplyResult` is source-neutral and reports per-domain `discovered`,
`imported`, `skippedDuplicates`, `skippedOlder`, `skippedConflicts`,
`skippedUnsupported`, `failed`, and concise names/reasons. Equal identity/state
is a duplicate; an older timestamp is `skippedOlder`; a newer local completion
or rewatch that blocks a semantically different incoming state is
`skippedConflicts`. Do not count an item once globally when different domains
have different outcomes.

Before starting network work, capture authorization for
`ProfileFeature.backupRestore`. Immediately before commit, use
`authorization.runIfCurrent` around the complete selected apply. If the profile,
policy, or authorization revision changes, commit nothing and report that the
import was cancelled because the destination profile changed.

Migration requires `ProfileRuntime.isProfileCommitted`. In legacy compatibility
mode, show the row as unavailable with explanatory copy and do not open the
authentication page. This keeps `ProfileAsyncAuthorization` non-null throughout
the flow; do not add an unscoped legacy write path for migration.

Addon application additionally requires `ProfileFeature.addonsAndEngines`.
Disable the addon checkbox with explanatory copy when the destination profile
cannot manage addons; watchlist/progress import may still proceed under
`backupRestore`.

Apply domains in one authorization boundary. Build all mutations first, then
enter a non-cancellable commit window. Addons and the coordinated local batch
are two commit units because the existing addon service owns its persistence.
Apply addons first, then the local batch. If addon import throws before saving,
do not start the local batch. If either unit has already persisted before a later
failure, report its committed result explicitly. Do not claim cross-unit or
cross-SharedPreferences transactionality.

Addon import reuses `StremioService.importAddonsFromJson` with a JSON payload
containing only selected descriptors and `replaceExisting: false`.

Core plan/apply tests:

- Millisecond position and duration are unchanged.
- Non-IMDb IDs and unsupported types are reported, not mislabelled.
- `temp`/`removed` rows never enter the watchlist.
- Removed non-temp progress does not enter Continue Watching.
- Valid `tt123:1:5` yields series S1E5; malformed IDs skip episode progress but
  keep series watchlist eligibility.
- Movie `timesWatched > 0` without valid below-threshold current progress
  produces completion and no resumable/CW row.
- Below-threshold movie rewatch progress is not converted back to completion.
- Newer local rewatch progress blocks older incoming completion.
- Series `timesWatched` and `watched` do not manufacture episode completion.
- A threshold-complete last episode is marked finished solely from its directly
  evidenced progress.
- Alternate title slugs cannot bypass IMDb/S/E conflict resolution.
- Incoming older progress never replaces newer local progress.
- Re-running the same import is a no-op.
- Switching profiles or revoking permission before the commit window prevents
  all commits.
- Addon-disabled profiles can import selected non-addon domains only.
- Legacy compatibility mode cannot open migration.

### Phase 4 — UI and settings integration

Create `lib/screens/settings/migration/stremio_migration_page.dart`, opened with
`pushSettingsPage`.

#### State machine

1. **Authenticate** — email/password or paste auth key.
2. **Fetching** — fetch addons and library; cancel returns without writes.
3. **Choose** — show destination profile and per-domain eligible/unsupported
   counts. Addons are individually selectable; official ones default off.
4. **Importing** — cancellation is allowed while preparing the selected data,
   before the first commit begins. Keep a cancel affordance focused while it can
   still act. Once addon/local persistence starts, enter a clearly labelled
   non-cancellable commit window and keep focus on a passive progress/status
   element. Do not describe the two commit units as one atomic transaction.
5. **Done** — show per-domain imported, duplicate, older, conflict, unsupported,
   and failed counts, including partial-domain status if a storage failure
   occurred.

Never keep password/auth-key text controllers alive after authentication. Do
not place secrets in restoration state, routes, analytics, exception text, or
debug labels.

#### Destination profile and permissions

Show `Importing into <Profile Name>` before authentication and again on Choose.
Gate the page with `ProfileFeature.backupRestore`. Capture the authorization
when the flow begins and reject commit if the active profile changes. Reflect
the independent addon-management permission in the selection UI. In legacy
compatibility mode, disable the row and explain that migration requires the
profile store to be available.

#### Settings integration checklist

The settings implementation has indexed category catalogs and multiple
responsive renderers. Do not treat this as only four insertions.

- Add the `Migration` `SettingsCategoryDefinition` after `Data & Backup` in
  `settings_screen.dart`.
- Add the matching `_Category` in `settings_tv_layout.dart` with exactly the
  same label.
- Add `SettingsRows.stremioMigration` in
  `settings/widgets/settings_widgets.dart`.
- Add the opener callback/function to every settings layout constructor and
  invocation that needs it.
- Add the row to the phone category switch, TV category switch, and compact/
  flattened responsive settings layout.
- Update every numeric category case after the insertion; prefer replacing
  fragile numeric cases with stable category identities if this can be done
  without expanding the feature excessively.
- Update TV focus-node capacity/count assumptions and DPAD traversal.
- Register settings search navigation, `pageIcons`, and `pageOpeners`.
- Search keywords: `stremio`, `import`, `migrate`, `move`, `switch`, `transfer`,
  `library`, `watchlist`, `progress`.

Suggested category copy:

```dart
SettingsCategoryDefinition(
  icon: Icons.moving_rounded,
  label: 'Migration',
  subtitle: 'Bring your setup from another app',
  eyebrow: 'Migration',
  title: 'Move in without starting over.',
  description:
      'Import addons, saved titles and playback state into this profile. '
      'Your library and addons in Stremio are not changed.',
)
```

#### TV requirements

- Use `TvTextField`; never replace its `FocusNode.onKeyEvent`, which would break
  the in-app keyboard.
- Every control is DPAD reachable with visible focus.
- Long lists use bounded, focus-safe scrolling.
- Fetching and pre-commit cancellation always leave focus on a valid control.
- Test the on-screen keyboard with email, password, and auth-key modes.

### Phase 5 — source-neutral seam for Nuvio (design only)

Nuvio exports `library`, `watchProgress`, `watchHistory`, and `addons`; its
progress is already milliseconds. A future Nuvio parser should produce the same
`WatchlistSeed`, `ContinueWatchingSeed`, `PlaybackStateSeed`, completion seeds,
selection model, and apply result.

Do not put Stremio-specific flags, ID parsing, response fields, or UI copy in
bulk writers or source-neutral result models.

---

## 4. Review invariants

1. Never write `video_resume_v1`.
2. Stremio progress/duration are already milliseconds; never multiply by 1000.
3. Never assume every Stremio `_id` is IMDb; validate it.
4. Always attach normalized IMDb IDs to imported playback state and preserve the
   source title verbatim.
5. Movie keys are `video_<slug>`, not `movie_<slug>`.
6. `temp` and `removed` rows never enter My Watchlist.
7. Full watched-episode history is not imported in v1 and is never guessed.
8. Only the directly evidenced last episode may be marked complete from its
   progress and the active profile threshold.
9. Historical incoming watched status never destroys current rewatch progress;
   an untimestamped existing local finished marker remains authoritative and is
   reported as a conflict instead of being removed.
10. Merge identity is IMDb-based (plus S/E for episodes) across title slugs.
11. Merge never replaces newer local state or removes unrelated local state.
12. Re-importing unchanged data performs no writes.
13. Password/auth key are never persisted or logged; auth keys remain opaque.
14. Commit remains bound to the initiating committed profile and current
    permissions; migration is unavailable in legacy mode.
15. Each blob is decoded once and written at most once per apply, with shared
    mutation serialization preventing lost updates.
16. Nothing calls `addonCollectionSet`, `datastorePut`, or any other Stremio
    write endpoint.
17. Phone, TV, compact settings, search maps, focus counts, and indexed category
    cases are all updated together.

---

## 5. Verification before merge

- Unit tests for API envelopes and sanitized current-schema fixtures.
- Unit tests for pure planning, merge conflicts, idempotency, permissions, and
  source-neutral bulk writers.
- One real Stremio account with 500+ library items, including temporary,
  removed, watched movie, series, non-IMDb, and malformed rows.
- Verify whether `all: true` returns the entire large library; document observed
  count and behavior.
- End-to-end import on phone and physical Android TV.
- Import twice: second run reports duplicates/equal rows and performs no writes.
- Import into profile A, switch to profile B during fetch and before commit, and
  confirm B is untouched and stale commit is rejected.
- Verify a newer local resume point survives an older Stremio import.
- Verify newer local rewatch progress survives an older watched/completed
  Stremio movie row.
- Verify a movie resumes through IMDb lookup despite an empty imported URL.
- Verify series resume and Continue Watching open the expected episode.
- Verify threshold-complete last-episode progress marks only that episode
  finished.
- Verify different title slugs for the same IMDb ID cannot create a newer
  duplicate or bypass conflict rules.
- Verify completed movies have a Rewatch state and no local CW/resume row.
- Verify Continue Watching retains the newest 50 across local and incoming data.
- Verify addon selection, official-addon defaults, and addon-disabled profiles.
- Run `flutter analyze` on changed `lib/` files and the relevant storage,
  profiles, completion, addon-import, settings, and TV-focus test suites.

---

## 6. Questions that require evidence during implementation

- Does `datastoreGet(all: true)` cap or omit old rows for a large real account?
- What exact API error codes are returned for expired auth keys, invalid
  credentials, throttling, and oversized responses? Map known codes without
  exposing arbitrary response bodies.
- Does an imported movie video-state row with an empty URL resume correctly on
  every player path, including native Android TV? If not, make URL nullable and
  update readers rather than inventing a source URL.
- Can the existing preference/storage layer host a shared per-profile mutation
  queue cleanly, or should the bulk API accept an already captured profile scope?
- Should a later version decode Stremio watched bitfields for full series
  history? Keep that separate from v1 unless ordered video metadata and fixtures
  are available.
