# Storage service refactor — plan

Written 2026-10-01 on `refactor/codebase` at `072407c3`. Follow
[AGENTS.md](../../AGENTS.md). This page plus AGENTS.md is everything the
executing agent needs.

Work on the existing `refactor/codebase` branch; don't create a new one.
Commit after every step (more often is fine). Never push to `origin`; push to
`private` only if the goal you were given says so.

## Goal

`lib/services/storage_service.dart` is 10,952 lines: one static class
`StorageService` (lines 71–10934), two enums (`AmbientTrailerSurface`,
`TvRenderQuality`) and `ApiKeyValidator`. The class has 1,078 static
members:
- 764 non-constant members: methods, getters and fields, 30 of them private
  methods;
- 314 constants: 257 private typed `String` keys, 32 public constants, and
  some inferred-type constants.

Every feature reads and writes its settings and local state through it.

Split it into small per-subject storage classes under `lib/services/storage/`,
**moving code verbatim** and repointing every caller. At the end
`storage_service.dart` is deleted.

**Why not keep a facade (as the playback refactor did)?** 669 distinct
members are used from 225 production files and 182 test files. Forwarders
alone would be thousands of lines, far over any size limit. Calls are static
and compile-checked, so repointing them is mechanical. A checked-in member
map plus repoint script (step 0) lets other branches apply the same rename
when they merge.

## Facts that shape the plan (at `072407c3`)

- **Members are grouped by subject, not by line range.** Many key constants
  sit together near the top (lines ~300–690). Others are declared beside
  their accessors throughout the file: detail-section keys at 1257, the
  home-row-order key at 10817. Accessors are spread through the file too. So
  each step moves one subject's members **wherever they are**, using the
  member map, not a block of lines.
- **Keys mostly belong to one subject.** The exceptions are cross-subject
  functions and shared helpers. The step 0 dependency report must find all
  of them. Known ones:
  - `clearAllIntegrationStates` (5100–5112) removes provider and WebDAV keys;
  - `clearAllStartupSettings` (5082) removes three IPTV keys (5094–5096);
  - `clearAllPlaylistMetadata` (5065) uses playlist and TVMaze keys;
  - `_getPlaylistItemUniqueKey` (8381) is used by TVMaze (8430) and poster
    code (8542);
  - `migrateDefaultsGeneration` (147–223) writes appearance keys and also
    Sources presentation preferences (217–220).
- **Shared private helpers:**
  - `_getPlaybackStateMap`/`_savePlaybackStateMap` (3002, 3066): used in 17
    sections, including outside playback progress: per-content audio and
    subtitle preferences (4631, 4655) and playlist progress (6317). They take
    no lock.
  - The Trakt credential check (7075) uses the provider credential helper.
  - `_credentialConfigured`/`_readCurrentProviderCredential` (2375, 2357):
    provider credentials.
  - `_seriesProgressKey`, `_requiresExactProgressIdentity` and
    `_getFinishedMovieIds` (2901): progress. Some private helpers have a public
    wrapper with a similar name (2901/2911, 8381/8585); those are different
    members.
- **Static state** (each must keep one owner and its lifetime):
  - revision notifiers: `trackingSourceRevision`, `movieFinishedRevision`,
    `localCompletionRevision` (80–87);
  - write locks: `_episodeTrackerSnapshotWriteLock` (93, guards
    tracker-snapshot writes at 3885–3902), `_detailPageSectionWriteLock`,
    `_collectionStyleLock`, `_launchSelectionLock`;
  - write generations: `_detailPageSectionWriteGeneration`,
    `_launchSelectionGeneration`;
  - session state: `_tvTrailerUnderlaySession`, `_startupIptvChannelCached`
    (10216, behind the `startupIptvChannelCached` getter);
  - test hook: `debugMyWatchlistTvOsCapOverride`;
  - 20 public `*Cached` synchronous mirrors (`tvHomeStyleCached`,
    `appThemeCached`, `sidebarConfigurationCached`, `uiSoundsCached`, ...).
- **Profile-handoff reset:** `resetProfileCaches()` (10910–10933) resets
  every `*Cached` mirror, bumps `_launchSelectionGeneration` (10924) and
  clears `_startupIptvChannelCached` (10932).
  - Production calls it from
    `lib/services/profiles/profile_app_lifecycle_participant.dart:123`, as
    `_warmed('StorageService', scope, StorageService.resetProfileCaches)`.
    `_warmed` resets, then stamps `ProfileCacheLedger` under the name
    `'StorageService'`.
  - Tests call it directly too, for example
    `test/iptv_spotlight_style_settings_test.dart:43` and
    `test/profiles/isolation_suite/preference_key_sweep_test.dart:95`. They
    rely on it resetting **everything**.
  - Other resets are separate APIs with their own semantics, for example
    `resetSidebarConfiguration` (2146–2150). They are not part of the
    handoff.
- **`migrateDefaultsGeneration()`** runs in two places, and both orders must
  stay:
  - in `main()` (`lib/main.dart:626`), before theme warm-up;
  - on profile switch, in the lifecycle participant (line 157).
- **Logging and labels:** `debugPrint` messages start with
  `'StorageService: '`, and the ledger label is `'StorageService'`. Tests also
  use the name in group names and ledger assertions, for example
  `test/profiles/isolation_suite/live_switch_isolation_test.dart:180`,
  `test/home_extra_rows_test.dart:32` and `test/home_hero_source_test.dart:11`.
  All of these stay unchanged.

## Destination areas

All new files go in `lib/services/storage/` (legacy data layer, like today).
Use `final class XxxStorage { const XxxStorage._(); static ... }` with the
members moved verbatim. The enums go to `lib/models/ambient_trailer_surface.dart`
and `lib/models/tv_render_quality.dart`. Suggested areas; the member map
decides:

| Area | Typical members | Suggested files |
| --- | --- | --- |
| Provider credentials and actions | Real-Debrid key/endpoint/file selection/post-torrent action, TorBox, Premiumize, AllDebrid, PikPak (auth, device id, captcha, restricted folder, hidden-from-nav, videos-only), the credential helpers, `clearAllIntegrationStates`, `ApiKeyValidator` | `provider_credential_storage.dart`, `real_debrid_storage.dart`, `torbox_storage.dart`, `premiumize_storage.dart`, `alldebrid_storage.dart`, `pikpak_storage.dart`, `api_key_validator.dart` |
| WebDAV | servers, selection, enabled, hidden-from-nav | `webdav_storage.dart` |
| Trackers | Trakt, Simkl, MDBList settings, tracking-source policy and `trackingSourceRevision`, scrobble preferences | `trakt_storage.dart`, `simkl_storage.dart`, `mdblist_storage.dart`, `tracking_source_storage.dart` |
| Content sources | Reddit, Lemmy, YouTube | `reddit_storage.dart`, `lemmy_storage.dart`, `youtube_storage.dart` |
| Search and Quick Play | Quick Play rules, VR, cache fallback, try-multiple; torrent search history, default filters, default providers, indexers/engines | `quick_play_storage.dart`, `torrent_search_storage.dart` |
| Player | Debrify Player defaults, subtitles/audio, renderer, start orientation; external players (incl. Linux/Windows) | `player_settings_storage.dart`, `external_player_storage.dart` |
| Appearance | themes, Looks, overrides, detail page style/sections/theme, home style, cards, hero/trailers, launch idents, sidebars, sounds/haptics, TV keyboard, `migrateDefaultsGeneration` | `theme_storage.dart`, `detail_page_storage.dart`, `home_appearance_storage.dart`, `launch_ident_storage.dart`, `sidebar_storage.dart`, `defaults_generation.dart` |
| Home | home page defaults, Discover layout | `home_page_storage.dart` |
| IPTV and startup | playlists (with secret fields), style, favorites, startup channel, `warmStartupIptv`, startup settings including `clearAllStartupSettings` | `iptv_storage.dart`, `iptv_favorites_storage.dart`, `startup_storage.dart` |
| Debrify TV and Stremio TV | settings, style, favorites, local catalogs | `debrify_tv_storage.dart`, `stremio_tv_storage.dart` |
| Watchlist and playlists | My Watchlist, playlist items/favorites/dedupe/progress, poster overrides, TVMaze mappings, `_getPlaylistItemUniqueKey`, `clearAllPlaylistMetadata` | `watchlist_storage.dart`, `playlist_storage.dart`, `tvmaze_mapping_storage.dart` |
| Playback state (largest, ~1,700 lines) | `_getPlaybackStateMap`/`_savePlaybackStateMap`, finished movies and `movieFinishedRevision`, episode progress and the tracker-snapshot lock, continue watching, recovery records, local completion and `localCompletionRevision` | `playback_state_store.dart` (the shared map helpers and keys), `movie_progress_storage.dart`, `episode_progress_storage.dart`, `continue_watching_storage.dart`, `playback_recovery_storage.dart`, `local_completion_storage.dart` |
| Device, remote, profile | battery optimisation, remote control, `profileAllowsAdultContent` | `device_storage.dart`, `remote_control_storage.dart`, `profile_policy_storage.dart` |

Each file stays under 500 lines (prefer 300). Split further where needed.

## Invariants (every step)

1. **No preference key changes.** The same key strings, read the same way,
   through the same API (`ProfilePreferences` or `SharedPreferences`,
   `SecretVault`, credential facades). No migration, no new keys, no renamed
   keys. Device-wide versus profile-owned storage stays exactly as it is.
2. **One owner per piece of static state.** Each notifier, lock, generation,
   session flag and `*Cached` mirror moves to exactly one class, keeping its
   initializer. Never duplicate one: two copies of a lock or notifier is a
   silent behaviour change. Don't add locking where there was none (the
   playback-map helpers have none).
3. **Profile isolation, checked at every step.**
   - Every `*Cached` mirror, wherever it lives, is still reset in the profile
     handoff, in the same `_warmed('StorageService', ...)` call and before
     the ledger stamp.
   - `_launchSelectionGeneration` is still bumped and
     `_startupIptvChannelCached` still cleared there.
4. **Ordering.** `migrateDefaultsGeneration()` still runs before theme warm-up
   in `main()`, and at the same point on profile switch.
5. **Same behaviour:** same defaults, validation, tombstone recording
   (`WebDavSyncTombstoneRecorder`), hot-merge calls, JSON isolate use, locking,
   log text and labels.
6. No Riverpod, providers or new DI here. Plain static classes, as today.

## Technique: move and repoint

**Move bodies verbatim.** Allowed edits:
- qualifiers at call sites (`StorageService.foo` → `FooStorage.foo`, and calls
  between storage classes, including from the shrinking `StorageService` to
  moved classes);
- imports;
- making a member shared, under the rules below.

**Sharing a private member.** When the dependency report shows a private key
or helper is needed in two places, prefer moving the members so they end up
together (the step table is arranged for this). Otherwise:
- drop the leading `_`, keep it `static const` or a static method, and add
  `// Shared within lib/services/storage/.`;
- if the bare name collides with an existing public member (for example
  `_getFinishedMovieIds` vs `getFinishedMovieIds`), use `<name>Internal`
  instead. Never call the existing public wrapper in its place: it isn't the
  same code;
- only `lib/services/storage/` and the shrinking `storage_service.dart` may
  use shared members. Record each one in the member map.

**Not allowed:**
- changing a key's string, a default, an `await`, lock usage or log text;
- merging look-alike helpers into one;
- changing whether a member is async;
- turning a static field into a getter, or the reverse.

**Profile-handoff reset.** One entry point, created in step 1, so every
caller resets everything at every step.
- **The entry point:** `lib/services/storage/storage_profile_caches.dart`
  declares the top-level `void resetStorageProfileCaches()`.
  - In step 1 it calls only `StorageService.resetProfileCaches()`.
  - From step 1 on, every caller uses it: the participant's
    `_warmed('StorageService', scope, resetStorageProfileCaches)`, with the
    same label and the same single ledger stamp, plus every test. The map
    sends `resetProfileCaches` to it, `ref_kind` `top_level`.
- **Per-class resets:** each storage class that owns `*Cached` mirrors, or
  the generation or session state reset in the handoff, gets
  `static void resetProfileCaches()`. It contains those lines from the
  original, verbatim and in their original relative order.
  - `resetStorageProfileCaches()` calls the class resets in the order their
    first line appeared in the original, then
    `StorageService.resetProfileCaches()`, which keeps the lines not yet
    moved, while that still exists.
  - The original assignments are independent, so per-class grouping keeps
    behaviour.
- **Reset partition check** (in `check_storage_bodies.py`): every statement
  of the original `resetProfileCaches()` appears exactly once across the
  per-class resets and the remaining legacy one. Each keeps its value, and
  each owner keeps the original relative order.
- **Guard:** see Source-text tests, where the wiring test is adapted to the
  entry point.

**Repointing.** Callers change only their qualifier and imports; test names
don't change. Code relying on `storage_service.dart`'s re-export of
`models/home_preferences.dart` imports that file directly once nothing else
from `storage_service.dart` is needed.

## Steps

The order keeps members that share private helpers or keys in the same step.

| # | Work | Notes |
| --- | --- | --- |
| 0 | Baseline, member map, dependency report, tooling | See below. Nothing moves, and no guard or CI registration yet (nothing to register). |
| 1 | Create `lib/services/storage/`, the reset entry point and the enum files; register them in the guard and CI in the same commit. Move content sources (Reddit, Lemmy, YouTube), remote control, device, profile policy, the two enums and `ApiKeyValidator`. | Proves the tooling on small subjects. Ports `stale_runtime_guard_test` to the entry point. |
| 2 | Provider credentials and actions, WebDAV, `clearAllIntegrationStates` | |
| 3 | First `playback_state_store.dart` (the two map helpers and their keys, shared), then trackers, search and Quick Play, player, external players | The store moves first because playlist progress (step 6) and per-content audio/subtitle preferences use the map helpers. Per-content audio/subtitle preferences may move here or in step 7; the map decides. |
| 4 | Appearance, home, `migrateDefaultsGeneration` | Most `*Cached` mirrors move here, so the handoff-reset wiring is exercised. **Full-suite gate 1** after this step. |
| 5 | IPTV, startup settings (`clearAllStartupSettings`), Debrify TV, Stremio TV | `warmStartupIptv` and `_startupIptvChannelCached` move together. |
| 6 | Watchlist, playlists, poster overrides, TVMaze mappings, `_getPlaylistItemUniqueKey`, `clearAllPlaylistMetadata` | Ports the playlist entries of the tombstone audit. |
| 7 | The rest of playback state | Moves last: it is the most shared. Ports the playback entries of the tombstone audit. |
| 8 | Delete `storage_service.dart`, final guards and CI, **full-suite gate 2** | See "Definition of done". |

### Step 0 — baseline, map, report, tooling

1. **Full-suite baseline at `072407c3`.** No full suite has run since the
   playback tidy-up touched Dart, so record one:
   `python3 dev/tool/suite_evidence.py run ss/base`. `<E>` below is
   `$(git rev-parse --git-common-dir)/refactor-evidence`. Then record the
   whole-repo analyzer: `flutter analyze > <E>/ss/analyze-base.txt`. The SDK
   must be Flutter 3.44.8; if it isn't, stop and ask.

2. **Member map: `dev/tool/storage_member_map.tsv`**, one row per symbol,
   tab-separated:
   - `member`: the original name;
   - `kind`: method, getter, field, const or key;
   - `ref_kind`: `static` (accessed as `StorageService.x`), `type` (enum or
     class, referenced unqualified) or `top_level`;
   - `target`: the full replacement expression, for example
     `ThemeStorage.appThemeCached`, `TvRenderQuality`, or a promoted shared
     name;
   - `file`: the destination file;
   - `step`: the step that moves it;
   - `shared`: yes or no.

   Cover every declaration in the original: the class's 1,078 static members
   (multi-line declarations such as `_iptvResumeStates` at 6234–6237,
   getters, inferred-type constants), both enums and `ApiKeyValidator`. A
   coverage check must prove nothing is missing. Commit the map before moving
   anything; later corrections go in the same commit as the move they affect.

3. **Dependency report**, generated from the map and committed beside it.
   For every private member, list the members that use it and their steps.
   - Any private member used across classes or steps must be resolved before
     its first move: move the users together, or mark it shared.
   - The report must come out with nothing unresolved.

4. **Repoint script: `dev/tool/repoint_storage.py`.**
   - **What it rewrites:** `--through-step N` rewrites only members with
     `step <= N`. It handles static calls, tear-offs
     (`StorageService.resetProfileCaches` with no call), field reads and
     assignments, and unqualified type references to the moved enums.
   - **Imports:** it keeps the `storage_service.dart` import while a file
     still uses any unmoved member, and adds imports only for destinations
     that file now uses. It handles `show`/`hide`/`as` imports, for example
     `test/features/home/home_catalog_preferences_screen_test.dart:10`
     (`show StorageService`), or fails loudly on them.
   - **Strings and comments:** it rewrites executable code inside string
     interpolation (`${...}`, including nested strings), for example
     `lib/theme/app_looks.dart:81` and `test/my_watchlist_storage_test.dart:274`.
     It leaves plain string text and comments unchanged and lists them for
     the source-text inventory below.
   - **Scope:** every tracked Dart file (`git ls-files '*.dart'`), not a fixed
     folder list. This covers `tool/native_player_settings_smoke.dart:19,123`
     and `dev/perf/search_screen_perf_probe_test.dart:25,84`.
   - **Running it:** it is idempotent (a second run changes nothing). Other
     branches run it after merging.
   - **Checked:** a fixture self-test covers each form: static call, tear-off,
     field assignment, unqualified type, `show`/`as` import, interpolation,
     plain string left alone, and the reset entry point.

5. **Key and body checks.**
   - **`dev/tool/storage_key_inventory.json`**, generated now from the
     original and **committed**, because CI clones are shallow and can't run
     `git show` on old commits. It lists every constant declaration
     (typed or inferred) with its name, declared value or expression (with
     referenced constants resolved, for example lines 74 and 539–540), and
     how many times it occurs.
   - **`dev/tool/check_storage_keys.py`** asserts that the constants declared
     across `lib/services/storage/**`, the enum files and any remaining
     `storage_service.dart` match the inventory exactly: the same name to
     value pairs (with renames only as the member map records them), each
     declared once, none lost, changed or added. It runs at every step and in
     CI.
   - **`dev/tool/check_storage_bodies.py`** (local only, it reads the
     original through `git show 072407c3:...`).
     - **What it compares:** each moved member's complete declaration against
       the original: modifiers, type, parameters **and their defaults** (for
       example `forRemoteTransfer = false` at 687), annotations, field
       initialisers and body.
     - **Normalisation:** it removes only map-authorised qualifier changes
       and renames (including `Internal` suffixes), and whitespace outside
       string literals.
     - **What this covers:** inline and generated keys (lines 725, 774,
       976–981 and 6647), defaults, storage APIs and guards, which a
       declaration inventory can't see.
     - **Reset partition:** it also runs the reset partition check described
       under Technique.
     - **Self-checked:** negative fixtures must fail for a changed parameter
       default, a changed inline key, a changed storage receiver and changed
       whitespace inside a literal.
     - It runs at every step.

6. **Source-text inventory: `dev/tool/storage_source_text.txt`.** List every
   test or tool that:
   - reads `storage_service.dart`'s source; or
   - contains `StorageService` inside a string. These include
     `test/rewatch_launch_routing_test.dart:12–23`, which expects
     `StorageService.movieFinishedRevision` in screen sources, and
     `test/media_server_player_resume_test.dart:103–115`, which forbids
     `StorageService.getVideoResume`.

   Each entry says which step ports it and how.

7. **CI test coverage** (registration of the new paths happens in step 1,
   when they exist; the guard rejects missing registered files).
   - Add `check_storage_keys.py` to CI now; it passes on the unsplit file.
   - Add these contract suites to `dev/tool/ci_behavior_tests.txt`:
     - `test/profiles/isolation_suite`
     - `test/services/webdav_sync`
     - `test/defaults_generation_test.dart`
     - `test/launch_animation/launch_selection_test.dart`
     - `test/tvos_keyboard_default_migration_test.dart`
     - `test/profiles/source_provider_credential_read_test.dart`
     - `test/storage_service_vault_migration_test.dart`
     - `test/episode_simkl_progress_storage_test.dart`
     - `test/episode_local_progress_storage_test.dart`
     - `test/local_watch_completion_storage_test.dart`
     - `test/tracking_source_storage_test.dart`
     - `test/tracking_source_policy_test.dart`
     - `test/audio_settings_storage_test.dart`
     - every file in the source-text inventory

     Record any of their failures at `ss/base` in
     `ci_behavior_known_failures.txt` by exact identity.
   - Expect roughly 1.7–1.9× today's job (about 1,900–2,100 test cases).
     Measure it on `private`; if it passes about 12 minutes, split the list
     into two jobs rather than dropping tests.

**Step 1 registration** (in the commit that creates the folder):
- Register `lib/services/storage/` and the two enum files in
  `dev/tool/check_search_architecture.py` as a measured data-layer source set:
  a 500-line cap and the data-layer import rules. Each registered path exists
  from step 1 on.
- Add them to `checks.yml`'s scoped `dart format` and `flutter analyze` steps.

### Per step

1. Run `repoint_storage.py --through-step N` after moving the step's members
   verbatim. Fix what it reports. Port the source-text entries scheduled for
   this step.
2. Run `dart format` on new storage files and on repointed call sites. If the
   formatter would change unrelated lines in a caller, format only the new
   files.
3. Record the whole-repo analyzer **after formatting** and compare it with the
   previous step's:
   `suite_evidence.py compare --against <previous>.txt --relocate lib/services/storage_service.dart=lib/services/storage/ <this>.txt`.
   A diagnostic may only move from the old file into the new folder, with
   the same severity, rule and message. Anything else counts as added. Don't
   use `--moved` here; it ignores which file a diagnostic is in.
4. Run `check_storage_keys.py`, `check_storage_bodies.py`,
   `check_file_sizes.py` (`--update` when the old file shrinks), and
   `check_search_architecture.py`.
5. Run the affected tests: every test that imports a touched file, references
   a moved member, or is in the source-text inventory. Record them with
   `suite_evidence.py run ss/stepN <paths>` and
   `compare --against <E>/ss/base.jsonl`.
6. Self-check:
   `git diff --color-moved=dimmed-zebra --color-moved-ws=allow-indentation-change HEAD -- lib/services`.
7. Commit: `refactor: move <subjects> out of StorageService`.

**Full-suite gates.** `suite_evidence.py run ss/gate1` (later `ss/gate2`),
then `compare --against <E>/ss/base.jsonl`. `PASS` is required: no new
failures, no missing tests, no new skips. Show that each repointed test
identity is present with the same outcome.

### Source-text tests

- **`test/profiles/isolation_suite/stale_runtime_guard_test.dart`.** This is
  a profile-isolation guard. Port it in step 1, with the entry point.
  - **Mirror test:** it scans the remaining `storage_service.dart` **and**
    every file under `lib/services/storage/`. Each `*Cached` mirror a file
    declares must be reset in that file's `resetProfileCaches()`.
  - **Wiring test:** for files under `lib/services/storage/`, require the
    chain: each file with a reset-shaped method is called from
    `storage_profile_caches.dart`, whose basename the participant names, and
    whose function the participant passes to `_warmed('StorageService', ...)`.
    Every other file in `lib/` keeps today's rule unchanged.
  - **Handoff extras:** also assert that the generation bump and the
    startup-channel clear are still present in some per-class reset.
  - **Mutation check:** temporarily remove one reset line, then one class's
    call from the entry point. Confirm each fails, then restore.
- **`test/services/webdav_sync/webdav_sync_tombstone_audit_test.dart`.**
  - Port each audited API in the **same step** that moves it: playlist
    entries in step 6, playback entries in step 7.
  - Update expected helper names from the member map (for example a shared
    `_savePlaybackStateMap`).
  - Keep every audited pair, and keep the forbidden-removal assertions
    (around lines 56–58) applied to every resulting owner, including qualified
    key references.
- **The rest of the source-text inventory** is ported in its scheduled step.
  Positive and negative guards keep their meaning. String-only references
  don't get imports. Test identities don't change.

## Definition of done

1. `lib/services/storage_service.dart` is deleted. A scan of every tracked
   Dart file finds no executable reference to `StorageService`, and no import
   of the old file.
   - The only permitted mentions of the name are:
     - the ledger label `'StorageService'` and its test assertions;
     - log text;
     - test group and test names;
     - comments and `dev/design/` docs;
     - `repoint_storage.py`'s patterns and fixtures, and the body checker's
       historical inputs.
   - Update comments in moved code only where they would now mislead.
2. Every file in `lib/services/storage/` and both enum files are at most 500
   lines and pass the data-layer guard. The old file is removed from
   `dev/tool/file_size_baseline.txt`.
3. `check_storage_keys.py` passes in CI. `check_storage_bodies.py` passes
   locally for every moved member.
4. The CI behaviour job(s) pass with the storage contract suites, with
   failures listed only by exact identity. Format and analyze scopes cover
   the storage folder.
5. Gate 2 passes against `ss/base.jsonl` and `ss/gate1.jsonl`. The step-by-step
   analyzer chain shows no added diagnostics. All guards pass, and CI passes
   on `private`.
6. Progress below records:
   - the step commits;
   - every shared member;
   - the classification of every moved static state item, and that it is
     unchanged;
   - how other branches use `repoint_storage.py`.
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
