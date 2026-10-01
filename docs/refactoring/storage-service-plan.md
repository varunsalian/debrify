# Storage service refactor — plan

Written 2026-10-01 on `refactor/codebase` at `072407c3`. Follow
[AGENTS.md](../../AGENTS.md). This page plus AGENTS.md is everything the
executing agent needs.

Work on the existing `refactor/codebase` branch; don't create a new one.
Commit after every step (more often is fine). Never push to `origin`; push to
`private` only if the goal you were given says so.

## Goal

`lib/services/storage_service.dart` is 10,952 lines: one static class
`StorageService` (~760 static members, 257 private key constants, 30 public
constants), two enums (`AmbientTrailerSurface`, `TvRenderQuality`) and
`ApiKeyValidator`. Every feature reads and writes its settings and local
state through it.

Split it into small per-subject storage classes under `lib/services/storage/`,
**moving code verbatim** and repointing every caller. At the end
`storage_service.dart` is deleted.

**Why not keep a facade (as the playback refactor did)?** 669 distinct
members are used from 225 production files and 182 test files. Forwarders
alone would be thousands of lines, far over any size limit. Calls are static
and compile-checked, so repointing them is mechanical and safe. A checked-in
member map plus repoint script (step 0) lets other branches apply the same
rename when they merge.

## Facts that shape the plan (at `072407c3`)

- **Members are grouped by subject, not by line range.** Key constants for
  every subject sit together near the top (lines ~300–690). Their accessors
  are spread through the file, and some subjects appear in several places.
  So each step moves one subject's members **wherever they are**, not a block
  of lines.
- **Keys cluster cleanly by subject.** Each of the 257 private keys is used by
  one subject's members, except in a few cross-subject "clear all" functions,
  for example:
  - `clearAllIntegrationStates` uses the WebDAV, provider and tracker keys;
  - `clearAllPlaylistMetadata` uses the playlist and TVMaze keys;
  - `clearAllHomePageSettings`, `clearAllStartupSettings` and
    `clearAllDebrifyTvSettings` stay within their subject.
- **Shared private helpers.** 29 private static methods; the ones used across
  sections are:
  - `_getPlaybackStateMap`/`_savePlaybackStateMap`: playback state, used in 17
    sections;
  - `_credentialConfigured`/`_readCurrentProviderCredential`: provider
    credentials;
  - `_seriesProgressKey`, `_requiresExactProgressIdentity` and
    `_getFinishedMovieIds`: progress.
- **Static state** (each must keep one owner and its lifetime):
  - revision notifiers: `trackingSourceRevision`, `movieFinishedRevision`,
    `localCompletionRevision`;
  - write locks: `_episodeTrackerSnapshotWriteLock`,
    `_detailPageSectionWriteLock`, `_collectionStyleLock`,
    `_launchSelectionLock`;
  - write generations: `_detailPageSectionWriteGeneration`,
    `_launchSelectionGeneration`;
  - session state: `_tvTrailerUnderlaySession`, `_startupIptvChannelCached`;
  - test hook: `debugMyWatchlistTvOsCapOverride`;
  - 20 public `*Cached` synchronous mirrors (`tvHomeStyleCached`,
    `appThemeCached`, `sidebarConfigurationCached`, `uiSoundsCached`, ...),
    plus the private `_startupIptvChannelCached` behind the
    `startupIptvChannelCached` getter.
- **`resetProfileCaches()`** resets every `*Cached` mirror, bumps
  `_launchSelectionGeneration` and clears `_startupIptvChannelCached`. It is
  called on profile switch from
  `lib/services/profiles/profile_app_lifecycle_participant.dart:123` as
  `_warmed('StorageService', scope, StorageService.resetProfileCaches)`.
  Mirrors are not reset by anything else.
- **`migrateDefaultsGeneration()`** (lines ~147–223) runs in two places:
  - in `main()` (`lib/main.dart:626`), before theme warm-up;
  - on profile switch, in the lifecycle participant (line 157).

  Both orders must stay. It uses only appearance keys.
- **Source-text tests that read this file:**
  - `test/profiles/isolation_suite/stale_runtime_guard_test.dart` checks that
    every `*Cached` mirror declared in this file is reset in
    `resetProfileCaches()`. This is a profile-isolation guard: a mirror it
    misses leaks profile A's value to profile B.
  - `test/services/webdav_sync/webdav_sync_tombstone_audit_test.dart` checks
    that the named deletion APIs reach their tombstone helpers (for example
    `clearContinueWatching` → `_saveContinueWatchingItems`).
- **Logging and labels:** `debugPrint` messages start with
  `'StorageService: '`, and the lifecycle participant labels its step
  `'StorageService'`. Both are log text and stay unchanged.

## Destination areas

All new files go in `lib/services/storage/` (legacy data layer, like today).
Use `final class XxxStorage { const XxxStorage._(); static ... }` with the
members moved verbatim. Suggested areas; the member map decides:

| Area | Typical members | Suggested files |
| --- | --- | --- |
| Provider credentials and actions | Real-Debrid key/endpoint/file selection/post-torrent action, TorBox, Premiumize, AllDebrid, PikPak (auth, device id, captcha, restricted folder, hidden-from-nav, videos-only), `_credentialConfigured`, `_readCurrentProviderCredential`, `ApiKeyValidator` | `provider_credential_storage.dart`, `real_debrid_storage.dart`, `torbox_storage.dart`, `premiumize_storage.dart`, `alldebrid_storage.dart`, `pikpak_storage.dart`, `api_key_validator.dart` |
| WebDAV | servers, selection, enabled, hidden-from-nav | `webdav_storage.dart` |
| Trackers | Trakt, Simkl, MDBList settings, tracking-source policy and `trackingSourceRevision`, scrobble preferences | `trakt_storage.dart`, `simkl_storage.dart`, `mdblist_storage.dart`, `tracking_source_storage.dart` |
| Content sources | Reddit, Lemmy, YouTube | `reddit_storage.dart`, `lemmy_storage.dart`, `youtube_storage.dart` |
| Search and Quick Play | Quick Play rules, VR, cache fallback, try-multiple; torrent search history, default filters, default providers, indexers/engines | `quick_play_storage.dart`, `torrent_search_storage.dart` |
| Player | Debrify Player defaults, subtitles/audio, renderer, start orientation; external players (incl. Linux/Windows) | `player_settings_storage.dart`, `external_player_storage.dart` |
| Appearance | themes, Looks, overrides, detail page style/sections/theme, home style, cards, hero/trailers (`AmbientTrailerSurface`), launch idents, sidebars, sounds/haptics, TV keyboard, `TvRenderQuality`, `migrateDefaultsGeneration` | `theme_storage.dart`, `detail_page_storage.dart`, `home_appearance_storage.dart`, `launch_ident_storage.dart`, `sidebar_storage.dart`, `defaults_generation.dart`; the two enums go to `lib/models/` |
| Home and startup | home page defaults, startup settings, Discover layout | `home_page_storage.dart`, `startup_storage.dart` |
| IPTV | playlists (with secret fields), style, favorites, startup channel, `warmStartupIptv` | `iptv_storage.dart`, `iptv_favorites_storage.dart` |
| Debrify TV and Stremio TV | settings, style, favorites, local catalogs | `debrify_tv_storage.dart`, `stremio_tv_storage.dart` |
| Watchlist and playlists | My Watchlist, playlist items/favorites/dedupe/progress, poster overrides, TVMaze mappings | `watchlist_storage.dart`, `playlist_storage.dart`, `tvmaze_mapping_storage.dart` |
| Playback state (largest, ~1,700 lines) | `_getPlaybackStateMap`/`_savePlaybackStateMap` and their lock, finished movies and `movieFinishedRevision`, episode progress and tracker snapshots, continue watching, recovery records, local completion and `localCompletionRevision` | `playback_state_store.dart` (the shared map, lock, keys), `movie_progress_storage.dart`, `episode_progress_storage.dart`, `continue_watching_storage.dart`, `playback_recovery_storage.dart`, `local_completion_storage.dart` |
| Device and remote | battery optimisation, remote control, profile policy helpers (`profileAllowsAdultContent`) | `device_storage.dart`, `remote_control_storage.dart`, `profile_policy_storage.dart` |
| Profile caches | the central reset | `storage_profile_caches.dart` |

Each file stays under 500 lines (prefer 300). Split further where needed; the
playback-state area will need more than one file.

## Invariants (every step)

1. **No preference key changes.** The same key strings, read the same way,
   through the same API (`ProfilePreferences` or `SharedPreferences`,
   `SecretVault`, credential facades). No migration, no new keys, no renamed
   keys. Device-wide versus profile-owned storage stays exactly as it is.
2. **One owner per piece of static state.** Each notifier, lock, generation,
   session flag and `*Cached` mirror moves to exactly one class, keeping its
   initial value. Never duplicate one: two copies of a lock or notifier is a
   silent behaviour change.
3. **Profile isolation.** Every `*Cached` mirror is still reset on profile
   switch, in the same call, before the incoming profile's warm-up.
   `_launchSelectionGeneration` is still bumped and
   `_startupIptvChannelCached` still cleared there.
4. **Ordering.** `migrateDefaultsGeneration()` still runs before theme
   warm-up. Warm-up and startup reads keep their order in `main()` and the
   lifecycle participant.
5. **Same behaviour:** same defaults, validation, tombstone recording
   (`WebDavSyncTombstoneRecorder`), hot-merge calls, JSON isolate use, locking
   and log text.
6. No Riverpod, providers or new DI here. Plain static classes, as today.

## Technique: move and repoint

- **Move bodies verbatim.** Allowed edits:
  - qualifiers at call sites (`StorageService.foo` → `FooStorage.foo`, and
    calls between the new classes);
  - imports;
  - dropping the leading `_` from a key constant or private helper that
    another storage class now uses. Keep it `static const`, add
    `// Shared within lib/services/storage/.`, and use it only from that
    folder. Only these names (`_getPlaybackStateMap`, the credential helpers,
    the cross-subject "clear all" keys) and anything the compiler proves is
    shared may change.
- **Not allowed:**
  - changing a key's string, a default, an `await`, lock usage or log text;
  - merging look-alike helpers into one;
  - changing whether a member is async;
  - turning a static field into a getter, or the reverse.
- **Cross-subject "clear all" functions** move with the subject named in them
  (`clearAllIntegrationStates` goes to the provider area, for example). They
  reach other subjects' keys through the shared constants above.
- **`resetProfileCaches()`:**
  - Each class that owns mirrors gets its own
    `static void resetProfileCaches()` containing its lines from the
    original, verbatim and in the original relative order.
  - `storage_profile_caches.dart` declares
    `void resetStorageProfileCaches()`, which calls them in the order their
    first line appeared in the original.
  - The lifecycle participant calls `resetStorageProfileCaches`, still with
    the label `'StorageService'`.
  - The original's assignments are independent, so grouping them per class
    keeps behaviour.
- **Repointing:**
  - Callers in `lib/` and `test/` change only their qualifier and import.
  - Test names don't change.
  - Assignments to mirrors in tests (`StorageService.tvHomeStyleCached = ...`)
    are repointed the same way.
  - Code relying on `storage_service.dart`'s re-export of
    `models/home_preferences.dart` imports that file directly.

## Steps

| # | Work | Notes |
| --- | --- | --- |
| 0 | Baseline, member map, tooling | See below. Nothing moves yet. |
| 1 | Low-coupling subjects: content sources (Reddit, Lemmy, YouTube), remote control, device, TVMaze mappings, the two enums, `ApiKeyValidator` | Proves the tooling end to end on small subjects. |
| 2 | Provider credentials and actions, WebDAV | Includes `clearAllIntegrationStates` and the credential helpers. |
| 3 | Trackers, search and Quick Play, player, external players | |
| 4 | Appearance, home and startup, `migrateDefaultsGeneration`, the central profile-cache reset | Ports `stale_runtime_guard_test` (see Source-text tests). **Full-suite gate 1** after this step. |
| 5 | IPTV, Debrify TV, Stremio TV | `warmStartupIptv` and `_startupIptvChannelCached` move together. |
| 6 | Watchlist, playlists, poster overrides | Includes `clearAllPlaylistMetadata`. |
| 7 | Playback state | Moves last: it is the most shared. Starts with `playback_state_store.dart`. Ports `webdav_sync_tombstone_audit_test`. |
| 8 | Delete `storage_service.dart`; guards; CI. **Full-suite gate 2.** | See "Definition of done". |

### Step 0 — baseline, map, tooling

1. **Full-suite baseline at `072407c3`.** No full suite has run since the
   playback tidy-up touched Dart, so record one:
   `python3 dev/tool/suite_evidence.py run ss/base`. `<E>` below is
   `$(git rev-parse --git-common-dir)/refactor-evidence`. Then record the
   analyzer: `flutter analyze > <E>/ss/analyze-base.txt`. The SDK must be
   Flutter 3.44.8; if it isn't, stop and ask.
2. **Member map: `dev/tool/storage_member_map.tsv`**, one line per member,
   tab-separated: `member`, `kind` (method/field/const/key/enum/class),
   `destination class`, `destination file`, `step`.
   - Cover every static member (including private keys and helpers), both
     enums and `ApiKeyValidator`.
   - A key goes where its users go. Flag any key or private helper used by
     members bound for different classes, and mark it shared.
   - Commit the map before moving anything. Changing it later is fine, in
     the same commit as the move.
3. **Repoint script: `dev/tool/repoint_storage.py`**. It reads the map and
   rewrites `StorageService.<member>` in the given paths (default `lib`,
   `test`, `dev`) to the destination class. It also replaces the
   `storage_service.dart` import with exactly the storage imports each file
   now needs, preserving `as`/`show` forms or failing loudly on them. It
   reports anything it can't rewrite. Other branches run it after merging.
4. **Key inventory check: `dev/tool/check_storage_keys.py`**. It extracts
   every `static const String` key value declared in the original file (from
   `git show 072407c3:lib/services/storage_service.dart`). It asserts that
   the set of key values declared across `lib/services/storage/**` plus any
   remaining `storage_service.dart` is **exactly** that set: none lost,
   changed or added. Run it at every step, and add it to CI in step 8.

### Per step

1. Using the map, move the step's members verbatim into their files, then
   run `repoint_storage.py`. Fix what it reports.
2. Run `flutter analyze` on touched files: nothing new. A shifted line or a
   moved file is not a new diagnostic. `suite_evidence.py compare --moved`
   compares by rule and message.
3. Run `dart format` on **new** storage files and on repointed call sites.
   Don't reformat untouched code in caller files; if the formatter would
   change unrelated lines, format only the new files.
4. Run `check_storage_keys.py`, `check_file_sizes.py`, and
   `check_search_architecture.py`. Run `check_file_sizes.py --update` when
   `storage_service.dart` shrinks.
5. Run the affected tests: every test file that imports a file you created
   or that referenced a moved member (`grep -rl`). Record them with
   `suite_evidence.py run ss/stepN <paths>` and
   `compare --against <E>/ss/base.jsonl`.
6. Self-check that the move is verbatim:
   `git diff --color-moved=dimmed-zebra --color-moved-ws=allow-indentation-change HEAD -- lib/services`.
7. Commit: `refactor: move <subjects> out of StorageService`.

**Full-suite gates.** `suite_evidence.py run ss/gate1` (later `ss/gate2`),
then `compare --against <E>/ss/base.jsonl`. `PASS` is required: no new
failures, no missing tests, no new skips. Show that each repointed test
identity is present with the same outcome.

### Source-text tests

- **`stale_runtime_guard_test.dart`** (profile isolation). Port it to scan
  every file in `lib/services/storage/`:
  - each `*Cached` mirror a file declares must be reset in that file's
    `resetProfileCaches()`;
  - every class with a `resetProfileCaches()` must be called from
    `resetStorageProfileCaches()`;
  - the lifecycle participant must call `resetStorageProfileCaches`.

  Keep its other assertions. Mutation-check the port: temporarily remove one
  reset line and one class's call, confirm the test fails, then restore them.
- **`webdav_sync_tombstone_audit_test.dart`.** Point each audited API at its
  new file; keep every audited pair.
- Any other test reading `storage_service.dart` (`grep -rn
  "lib/services/storage_service.dart" test`) is ported the same way. Never
  delete an assertion to make a move pass.

## Definition of done

1. `lib/services/storage_service.dart` no longer exists, and nothing in
   `lib/` or `test/` references `StorageService`. Comments and `dev/design/`
   docs may still name it; update comments in moved code only where they
   would now be misleading.
2. Every file in `lib/services/storage/` is at most 500 lines.
   - Register the folder in `dev/tool/check_search_architecture.py` as a
     measured data-layer source set: 500-line cap, the data-layer import rules
     (no UI or presentation imports).
   - Remove the old file from `dev/tool/file_size_baseline.txt`.
3. `check_storage_keys.py` passes, and runs in CI.
4. CI behaviour tests cover storage.
   - Add `test/profiles/isolation_suite`, `test/services/webdav_sync`, and
     every test file whose name contains `storage` or `preferences` to
     `dev/tool/ci_behavior_tests.txt`.
   - Record any failures they have at `ss/base` in
     `ci_behavior_known_failures.txt` by exact identity.
   - Keep the job under about 12 minutes. If it would exceed that, split it
     into a second job rather than dropping tests.
5. Gate 2 passes against `ss/base.jsonl` and `ss/gate1.jsonl`. The whole-repo
   analyzer matches `analyze-base.txt` (`--moved`). All guards pass, and CI
   passes on `private`.
6. Progress below records:
   - the step commits;
   - the classification of every moved static state item, and that it is
     unchanged;
   - the map and repoint script, for other branches.
7. Stop after gate 2 and report. The user has Claude review
   `<step 0 commit>..HEAD`.

## Explicitly not in scope

- Changing any key, default, storage backend, profile classification or
  migration.
- Converting static storage to instances, repositories, interfaces or
  Riverpod. That is a later design change, and needs this split first.
- Merging look-alike accessors, or fixing bugs. Record a bug you find under
  "Found, not fixed", with file, member and a one-line repro.
- Other large files.

## Progress

| Step | Commit | `storage_service.dart` lines | Result |
| --- | --- | --- | --- |
| 0 | | 10,952 | |

## Found, not fixed

(none yet)
