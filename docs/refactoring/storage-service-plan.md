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
    same label and the same single ledger stamp, plus every test.
  - **Map row:** `resetProfileCaches` has `ref_kind` `static` (how it is
    referenced today), `target` `resetStorageProfileCaches` (a top-level
    function), `step` 1, and `kind` `reset_entry`. It is checked by the reset
    partition check, not by declaration equality.
  - **Script exemption:** `repoint_storage.py` must never rewrite the
    forwarding call `StorageService.resetProfileCaches()` inside
    `storage_profile_caches.dart`, nor drop that file's import of the old
    file. Rewriting it would make the entry point call itself. The exemption
    ends when step 8 deletes the legacy reset. A fixture runs the script twice
    with the entry-point file tracked: external callers are redirected, and
    the forwarding call survives unchanged.
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
| 3 | First `playback_state_store.dart`: the two map helpers with their private dependencies `_playbackStateKey`, `_playbackRecoveryRecordKeys` and `_webDavPlaybackRecordKeys` (moved or shared, as the dependency report decides). Then trackers, search and Quick Play, player, external players. | The store moves first because playlist progress (step 6) and per-content audio/subtitle preferences use the map helpers. Per-content audio/subtitle preferences may move here or in step 7; the map decides. Sharing `_savePlaybackStateMap` renames it, so update the tombstone audit's **expected helper names** in this step (see Source-text tests). |
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
  - **Wiring test:** verify the whole chain:
    - the participant passes `resetStorageProfileCaches` to
      `_warmed('StorageService', ...)`;
    - `storage_profile_caches.dart` calls each storage file's reset-shaped
      method **exactly once**;
    - while `storage_service.dart` exists, it also calls
      `StorageService.resetProfileCaches()` exactly once, as a verified leaf
      of the chain. A participant import of `storage_service.dart` does not
      count.

    Files under `lib/services/storage/` and `storage_service.dart` are checked
    through the chain. Every other file in `lib/` keeps today's basename rule
    unchanged.
  - **Handoff extras:** also assert that the generation bump and the
    startup-channel clear are still present in some per-class reset.
  - **Mutation check:** temporarily remove one reset line, then one class's
    call from the entry point, then (in step 1) the legacy forwarding call.
    Confirm each fails, then restore.
- **`test/services/webdav_sync/webdav_sync_tombstone_audit_test.dart`.**
  - **Helper names, in step 3.** Seven entries (line 21 on) expect the
    literal `_savePlaybackStateMap`. Sharing it in step 3 changes how the
    still-unmoved APIs call it (for example `clearPlaybackStateByImdbId` at
    3032). So step 3 updates those expected callee names, and the
    qualified-key negative guards, to the shared spelling, while the APIs
    still live in the old file. The audit must pass at the end of step 3.
  - **Owner locations, later.** Port each audited API's file location in
    the **same step** that moves it: playlist entries in step 6, playback
    entries in step 7.
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
| 0 | `dfdf2d4a` | 10,952 | Baseline, complete map, resolved report, inventories and self-checked tooling; no Dart moves. |
| 1 | `0438a77d` | 10,473 | Small subjects, enums, validator and reset entry wired; analyzer and 245 affected suites PASS against baseline. |
| 2 | `a18aff4a` | 9,251 | Verbatim moves; analyzer, keys/bodies, size/import guards and affected suites PASS. |
| 3 | `93435156` | 7,184 | Verbatim moves; analyzer, keys/bodies, size/import guards and affected suites PASS. |
| 4 | `e30794c2` | 5,273 | Verbatim moves; analyzer, keys/bodies, size/import guards and affected suites PASS. |
| 5 | `15704c1f` | 3,447 | Verbatim moves; analyzer, keys/bodies, size/import guards and affected suites PASS. |
| 6 | `71e25130` | 2,022 | Verbatim moves; analyzer, keys/bodies, size/import guards and affected suites PASS. |
| 7 | `72dcf3bf` | 8 | Verbatim moves; analyzer, keys/bodies, size/import guards and affected suites PASS. |
| 8 | This step commit (hash recorded at gate 2) | 0 | Verbatim moves; analyzer, keys/bodies, size/import guards and affected suites PASS. |

### Step 0 evidence and retained source

- Baseline checkout: `e5c962c6`; `git diff 072407c3 -- lib test pubspec.yaml
  pubspec.lock` is empty. The four intervening commits only revise this plan
  and its comparison tooling; the application under test is exactly `072407c3`.
- SDK: Flutter 3.44.8, framework `058e0af2c2`, Dart 3.12.2. Evidence is in
  the clone's git common directory, `refactor-evidence/ss/`.
- `python3 dev/tool/suite_evidence.py run ss/base`: 10,294 success,
  20 failure, 29 error, 20 skipped. The runner completed. These exact observed
  identities, including every success, are the comparison authority.
- `flutter analyze` saved as `ss/analyze-base.txt`: 836 diagnostics. Later
  steps use the prescribed file-aware relocation comparison.
- `check_storage_map.py`: all 1,081 rows covered; the generated
  `storage_dependencies.txt` reports **Unresolved: 0**. Shared members are
  individually identified by `shared=yes` in the map and by their promotion
  and complete consumer list in that report. Keys required by an earlier
  step move at that earlier step into their eventual owner's file.
- `check_storage_keys.py`: 314 original constants, each declared once,
  including inferred constants and resolved external constant expressions.
  The inventory is committed for shallow CI clones.
- `repoint_storage.py --self-test`: nine fixtures cover calls, tear-offs,
  assignments, types, import combinators/aliases, nested interpolations,
  literals/comments, re-exported Home types, tracked scope, and two passes
  with the protected legacy reset leaf.
- `check_storage_bodies.py --self-test`: rejects changed defaults, inline
  keys, receivers and literal whitespace; accepts only mapped promotions
  and qualifiers. It also verifies the reset partition.
- The eight source-text inventory files are registered in CI, along with
  the plan's storage contract suites. The added WebDAV failure is an exact
  identity observed at `ss/base`; the existing two CI failures remain.
- Temporary retention: `lib/services/storage_service.dart` remains oversized
  because each step must keep unmoved subjects usable. Its remaining
  responsibilities are exactly the map rows not yet moved. Milestone: each
  step ratchets its size down; step 8 deletes it. New owners have a 500-line
  cap from their first production use.

### Static state ownership (unchanged by the split)

Every item below retains its original declaration, initializer and single
owner; `check_storage_bodies.py` verifies those declarations at each step.
The map records the destination. No lifecycle or storage classification is
changed by the mechanical move.

| Original state | Existing classification and lifetime |
| --- | --- |
| `trackingSourceRevision`, `movieFinishedRevision`, `localCompletionRevision` | Process-lifetime invalidation notifiers for profile-owned changes; retained notifier identity, no new reset. |
| `_episodeTrackerSnapshotWriteLock`, `_detailPageSectionWriteLock`, `_collectionStyleLock`, `_launchSelectionLock` | Process-lifetime locks; existing captured-profile write guards remain unchanged. |
| `_detailPageSectionWriteGeneration` | Process-lifetime write generation, existing per-action stale-write checks. |
| `_launchSelectionGeneration` | Process-lifetime write generation, bumped during every profile handoff. |
| `_tvTrailerUnderlaySession` | Launch-session choice, retained until its existing explicit debug reset. |
| `debugMyWatchlistTvOsCapOverride` | Existing process/test hook; no new handoff reset. |
| `tvKeyboardEnabledCached`, `tvHomeStyleCached`, `debrifyTvStyleCached`, `detailPageStyleCached`, `detailPageSectionVisibilityCached`, `detailThemeCached`, `appThemeCached`, `themeOverridesCached`, `parentsGuideStyleCached`, `iptvStyleCached`, `discoverLayoutCached`, `launchAnimationCached`, `importedLaunchAnimationCached`, `launchIdentPaletteCached`, `tvSidebarStyleCached`, `desktopSidebarStyleCached`, `sidebarConfigurationCached`, `playerStartPortraitCached`, `uiSoundsCached`, `uiHapticsCached` | Profile-owned synchronous mirrors; reset before the existing single ledger stamp, then warmed in the existing order. |
| `_startupIptvChannelCached` | Profile-owned startup snapshot; cleared at handoff and warmed by `warmStartupIptv`. The public getter remains a getter. |

### Applying the rename on other branches

After merging these commits, run
`python3 dev/tool/repoint_storage.py --through-step N`, where `N` is the
highest merged step (8 for the completed split). It scans every tracked Dart
file, including `tool/` and `dev/perf/`; run it again to verify zero changes.
Port branch-specific source-text guards without changing their meaning, then
run the relevant analyzer/tests and `check_storage_keys.py`. Local clones
with `072407c3` available also run `check_storage_bodies.py`. Plain literals
and comments are intentionally preserved for review.

## Found, not fixed

(none found)

### Mechanical caller size exceptions

Existing oversized callers need extra imports and formatter wrapping for the
new static qualifiers. Their non-import executable declarations are checked
against the preceding commit with only map-authorized qualifier normalization;
no responsibilities are added. The existing file-size tool explicitly supports
review-visible, hand-recorded exceptions for small changes. Each count below
is the exact permitted cap; ordinary shrink-only ratcheting continues after
each step. Unrelated whole-file extractions remain outside this plan.

| Step | Retained caller | Previous cap | Exact new cap |
| --- | --- | --- | --- |
| 1 | `lib/main.dart` | 4158 | 4161 |
| 1 | `lib/screens/collections/collection_folder_screen.dart` | 1859 | 1860 |
| 1 | `lib/screens/merged_series_detail_screen.dart` | 5526 | 5527 |
| 1 | `lib/screens/settings/home_page_settings_page.dart` | 1065 | 1066 |
| 1 | `lib/screens/settings_screen.dart` | 8725 | 8727 |
| 1 | `lib/services/download_service.dart` | 4683 | 4684 |
| 1 | `lib/widgets/onboarding/onboarding_flow.dart` | 1206 | 1207 |
| 1 | `lib/widgets/see_all/discover_detail_rail.dart` | 1166 | 1167 |
| 2 | `lib/main.dart` | 4161 | 4169 |
| 2 | `lib/screens/addons/addon_hub_screen.dart` | 3412 | 3415 |
| 2 | `lib/screens/alldebrid/alldebrid_files_screen.dart` | 1995 | 1996 |
| 2 | `lib/screens/debrid_downloads_screen.dart` | 6444 | 6445 |
| 2 | `lib/screens/magic_tv_screen.dart` | 11264 | 11268 |
| 2 | `lib/screens/pikpak/pikpak_files_screen.dart` | 3441 | 3442 |
| 2 | `lib/screens/playlist_content_view_screen.dart` | 4121 | 4128 |
| 2 | `lib/screens/premiumize/premiumize_files_screen.dart` | 2275 | 2276 |
| 2 | `lib/screens/settings_screen.dart` | 8727 | 8735 |
| 2 | `lib/screens/stremio_tv/stremio_tv_screen.dart` | 3952 | 3957 |
| 2 | `lib/screens/torbox/torbox_downloads_screen.dart` | 7069 | 7070 |
| 2 | `lib/screens/video_player_screen.dart` | 18081 | 18085 |
| 2 | `lib/screens/webdav/webdav_files_screen.dart` | 1169 | 1171 |
| 2 | `lib/services/backup_restore_service.dart` | 1275 | 1281 |
| 2 | `lib/services/download_service.dart` | 4684 | 4685 |
| 2 | `lib/services/magnet_link_handler.dart` | 911 | 915 |
| 2 | `lib/services/playlist_player_service.dart` | 2873 | 2880 |
| 2 | `lib/services/remote_control/remote_command_router.dart` | 5460 | 5467 |
| 2 | `lib/services/torrent_bulk_add_service.dart` | 1040 | 1044 |
| 2 | `lib/services/video_player_launcher.dart` | 6571 | 6575 |
| 2 | `lib/widgets/aggregated_search_results.dart` | 1568 | 1573 |
| 2 | `lib/widgets/catalog_browser.dart` | 2135 | 2140 |
| 2 | `lib/widgets/onboarding/onboarding_flow.dart` | 1207 | 1212 |
| 2 | `lib/widgets/provider_status_cards.dart` | 1045 | 1046 |
| 2 | `lib/widgets/remote/remote_config_export.dart` | 1584 | 1592 |
| 2 | `lib/widgets/remote/remote_transfer_all.dart` | 1557 | 1565 |
| 2 | `lib/widgets/trakt/trakt_results_view.dart` | 3071 | 3076 |
| 3 | `lib/main.dart` | 4169 | 4170 |
| 3 | `lib/screens/catalog_item_detail_screen.dart` | 3497 | 3499 |
| 3 | `lib/screens/merged_series_detail_screen.dart` | 5527 | 5529 |
| 3 | `lib/screens/settings/external_player_settings_page.dart` | 4283 | 4289 |
| 3 | `lib/screens/settings/home_page_settings_page.dart` | 1066 | 1067 |
| 3 | `lib/screens/settings/quick_play_settings_page.dart` | 951 | 953 |
| 3 | `lib/screens/settings_screen.dart` | 8735 | 8741 |
| 3 | `lib/screens/video_player_screen.dart` | 18085 | 18091 |
| 3 | `lib/services/android_tv_player_bridge.dart` | 2149 | 2150 |
| 3 | `lib/services/backup_restore_service.dart` | 1281 | 1286 |
| 3 | `lib/services/iptv_source_search.dart` | 1169 | 1171 |
| 3 | `lib/services/mdblist/mdblist_service.dart` | 2398 | 2399 |
| 3 | `lib/services/remote_control/remote_command_router.dart` | 5467 | 5475 |
| 3 | `lib/services/simkl/simkl_service.dart` | 1797 | 1799 |
| 3 | `lib/services/trakt/trakt_service.dart` | 2292 | 2294 |
| 3 | `lib/services/video_player_launcher.dart` | 6575 | 6578 |
| 3 | `lib/widgets/remote/remote_config_export.dart` | 1592 | 1599 |
| 3 | `lib/widgets/remote/remote_transfer_all.dart` | 1565 | 1571 |
| 4 | `lib/main.dart` | 4170 | 4177 |
| 4 | `lib/screens/collections/collection_folder_screen.dart` | 1860 | 1864 |
| 4 | `lib/screens/merged_series_detail_screen.dart` | 5529 | 5531 |
| 4 | `lib/screens/settings/home_page_settings_page.dart` | 1067 | 1072 |
| 4 | `lib/screens/settings/home_sections_filter_page.dart` | 1581 | 1582 |
| 4 | `lib/screens/settings_screen.dart` | 8741 | 8750 |
| 4 | `lib/screens/video_player_screen.dart` | 18091 | 18092 |
| 4 | `lib/services/profiles/profile_restore_coordinator.dart` | 1938 | 1939 |
| 4 | `lib/widgets/series_browser.dart` | 2200 | 2201 |
| 5 | `lib/main.dart` | 4177 | 4181 |
| 5 | `lib/screens/magic_tv_screen.dart` | 11268 | 11271 |
| 5 | `lib/screens/settings/home_page_settings_page.dart` | 1072 | 1073 |
| 5 | `lib/screens/settings/iptv_settings_page.dart` | 4471 | 4480 |
| 5 | `lib/screens/settings/iptv_settings_two_pane.dart` | 2229 | 2231 |
| 5 | `lib/screens/settings_screen.dart` | 8750 | 8754 |
| 5 | `lib/screens/video_player/widgets/iptv_channel_sheet.dart` | 3666 | 3667 |
| 5 | `lib/screens/video_player_screen.dart` | 18092 | 18097 |
| 5 | `lib/services/android_tv_player_bridge.dart` | 2150 | 2153 |
| 5 | `lib/services/iptv_source_search.dart` | 1171 | 1175 |
| 5 | `lib/services/video_player_launcher.dart` | 6578 | 6581 |
| 5 | `lib/widgets/iptv/iptv_results_view.dart` | 9080 | 9084 |
| 6 | `lib/screens/catalog_item_detail_screen.dart` | 3499 | 3500 |
| 6 | `lib/screens/merged_series_detail_screen.dart` | 5531 | 5532 |
| 6 | `lib/screens/playlist_content_view_screen.dart` | 4128 | 4136 |
| 6 | `lib/screens/playlist_screen.dart` | 880 | 883 |
| 6 | `lib/screens/settings_screen.dart` | 8754 | 8756 |
| 6 | `lib/screens/video_player_screen.dart` | 18097 | 18099 |
| 6 | `lib/services/video_player_launcher.dart` | 6581 | 6584 |
| 6 | `lib/widgets/series_browser.dart` | 2201 | 2206 |
| 7 | `lib/main.dart` | 4181 | 4182 |
| 7 | `lib/screens/playlist_content_view_screen.dart` | 4136 | 4140 |
| 7 | `lib/screens/settings_screen.dart` | 8756 | 8757 |
| 7 | `lib/screens/video_player_screen.dart` | 18099 | 18106 |
| 7 | `lib/services/video_player_launcher.dart` | 6584 | 6594 |
| 7 | `lib/widgets/series_browser.dart` | 2206 | 2208 |
<!-- storage-caller-size-rows -->

Step 1: `ss/step1.jsonl` records 3,449 success, 18 error, 1 failure,
10 skipped; comparison to `ss/base.jsonl` is PASS, with identical identities
and outcomes for the affected tests. `ss/analyze-step1.txt` adds no diagnostics
versus the analyzer baseline. Keys, bodies, size/import guards and diff checks
pass. Repointing is idempotent. The omitted-mirror and omitted-legacy-leaf
mutations both fail the isolation guard and were restored. There is no moved
cache owner in step 1; the omitted-class-call mutation is exercised when the
first such owner moves in step 3. An initial concurrent analyzer/test run
caused a 30-second large-import test timeout; the complete affected run was
repeated with the analyzer idle and passed. Both logs are retained.

Step 2 tooling correction: Dart 3.12's default formatter inserts trailing
commas when longer cross-owner qualifiers wrap. The strict declaration checker
caught this before affected tests or the commit. The storage folder alone uses
a 120-column page and preserves existing trailing commas; every owner was
already below 500 lines before this choice. This accommodates the mapped
qualifiers while retaining original punctuation. Declaration comparisons are
still strict, with no broader normalization. The root formatter policy and
other folders remain unchanged.

Caller formatting clarification: the plan's required formatting may add an
optional trailing argument comma when a repointed call now wraps. This is
limited to those call sites; no moved declaration admits punctuation changes.
The caller review also checks that the enclosing expression is a function or
constructor argument list containing a mapped storage reference (never a
record), and that every other executable token and literal is unchanged.
Callers with unrelated pre-existing formatter changes are left unformatted.

Step 2: `ss/step2.jsonl` records {'success': 3733, 'error': 16, 'skipped': 10, 'failure': 1};
comparison to `ss/base.jsonl` PASS (no new failures, missing tests or skips).
`ss/analyze-step2.txt` vs the previous step adds no diagnostics after the
prescribed old-file relocation. Map/dependency, constant, declaration/reset,
size/import and diff checks pass. Caller review confirms only authorized
expressions, imports and whitespace changed.

Step 3 tooling correction: the declaration lexer now includes the semicolon of
an arrow method returning a set/map literal (the playback recovery record-key
helper). A fixture covers that shape. Coverage and dependency ownership remain
unchanged; regeneration and the strict declaration check retain the entire
original declaration. This was caught by formatting before affected tests.

Step 3: `ss/step3.jsonl` records {'success': 3787, 'error': 20, 'skipped': 10, 'failure': 1};
comparison to `ss/base.jsonl` PASS (no new failures, missing tests or skips).
`ss/analyze-step3.txt` vs the previous step adds no diagnostics after the
prescribed old-file relocation. Map/dependency, constant, declaration/reset,
size/import and diff checks pass. Caller review confirms only authorized
expressions, imports and whitespace changed.
Step 3 reset mutations: deleting the moved `playerStartPortraitCached` reset
assignment and deleting its owner's call from the entry point each fails the
isolation guard. Both were restored; `ss/step3-reset.jsonl` passes all five
original test identities against `ss/base.jsonl`.

Step 4: `ss/step4.jsonl` records {'success': 3733, 'error': 18, 'skipped': 10, 'failure': 1};
comparison to `ss/base.jsonl` PASS (no new failures, missing tests or skips).
`ss/analyze-step4.txt` vs the previous step adds no diagnostics after the
prescribed old-file relocation. Map/dependency, constant, declaration/reset,
size/import and diff checks pass. Caller review confirms only authorized
expressions, imports and whitespace changed.
Step 4: the complete CI formatting scope also passes (1,046 files). Two affected
feature test call sites needed the formatter's optional literal/argument commas;
their 18 original identities pass again in `ss/step4-format.jsonl`. No moved
application declaration permits those punctuation changes. The smoke tool's
step-3-only repointing was included in the unpushed step 3 commit before this
checkpoint; the performance probe and remaining smoke-tool settings move in
step 4 as their map rows require.

Full-suite gate 1 at `e30794c2`: `ss/gate1.jsonl` has 10,294 success,
20 failure, 29 error, 20 skipped. Comparison against `ss/base.jsonl` is PASS;
all 10,363 original identities have exactly the same outcome, including every
repointed test. The historical `test_baseline.py` comparison was reused on the
completed run: its older list lacks 40 failures already observed at `ss/base`.
That historical limitation is recorded in `ss/historical-gate1.txt`; the list
was not rewritten and cannot mask any observed-baseline regression. Analyzer
chain, constants, complete declarations/reset partitions, architecture/size,
CI formatting scope and diff checks pass. This gate is pushed only to `private`;
the exact CI result and duration are recorded with step 5 after verification.

Gate 1 private CI: run `36886791557` on `1a54fd34` passed all three jobs.
https://github.com/varunsalian/debrify-refactor/actions/runs/36886791557
The behavior job took 9m 39s including setup; it is below the plan's 12-minute
threshold, so the expanded contract list stays in one job. No tests were dropped.

Step 5 formatting note: the IPTV history file uses `// dart format width=160`
so Dart does not introduce a trailing parameter comma when formatting the
original record-returning `_iptvResumeStates` signature. Its declarations
remain verbatim and the owner was below 500 lines before formatting. The strict
declaration check caught this and passed after restoring the original punctuation.
All profile-handoff assignments are now in their owners; the legacy reset is an
empty leaf, forwarded exactly once until step 8 removes it.

Step 5: `ss/step5.jsonl` records {'success': 1535, 'skipped': 10, 'error': 2, 'failure': 1};
comparison to `ss/base.jsonl` PASS (no new failures, missing tests or skips).
`ss/analyze-step5.txt` vs the previous step adds no diagnostics after the
prescribed old-file relocation. Map/dependency, constant, declaration/reset,
size/import and diff checks pass. Caller review confirms only authorized
expressions, imports and whitespace changed.

Gate 1 CI executed 1,991 identities: 1,987 success, one skip and the three
exact baseline failures. All three jobs passed; the behavior job took 9m39s.

Step 6: `ss/step6.jsonl` records {'success': 916, 'skipped': 10, 'error': 2};
comparison to `ss/base.jsonl` PASS (no new failures, missing tests or skips).
`ss/analyze-step6.txt` vs the previous step adds no diagnostics after the
prescribed old-file relocation. Map/dependency, constant, declaration/reset,
size/import and diff checks pass. Caller review confirms only authorized
expressions, imports and whitespace changed.

Step 7 formatting note: Dart adds an outer argument comma to the original
`saveContinueWatchingItem` predicate at every tested page width because its
inner call already has a trailing comma. Three comments preserve just that
original statement with a formatter off/on region; the rest of the 147-line
owner is formatted normally. No punctuation is normalized away by the strict
declaration checker. This preserves the requested verbatim code and does not
reduce the file to meet a size limit. Formatter controls are documented at
https://dart.dev/blog/announcing-dart-3-7 .

Step 7: `ss/step7.jsonl` records {'success': 2451, 'error': 6, 'skipped': 10};
comparison to `ss/base.jsonl` PASS (no new failures, missing tests or skips).
`ss/analyze-step7.txt` vs the previous step adds no diagnostics after the
prescribed old-file relocation. Map/dependency, constant, declaration/reset,
size/import and diff checks pass. Caller review confirms only authorized
expressions, imports and whitespace changed.

Step 8: `ss/step8.jsonl` records {'success': 340};
comparison to `ss/base.jsonl` PASS (no new failures, missing tests or skips).
`ss/analyze-step8.txt` vs the previous step adds no diagnostics after the
prescribed old-file relocation. Map/dependency, constant, declaration/reset,
size/import and diff checks pass. Caller review confirms only authorized
expressions, imports and whitespace changed.

Step 8 final source set: 82 Dart files in `lib/services/storage/` plus both
enum files. The largest is `debrify_tv_storage.dart` at 381 physical lines;
all 84 files meet the 500-line data-layer cap. The old source file and its
size-baseline entry are gone. Twelve owner resets are reached exactly once
before the unchanged single StorageService ledger stamp.

`check_storage_references.py --self-test` is now required by CI. It scans all
tracked Dart files, rejects executable legacy references (including string
interpolations), old import/export URIs (including conditional imports and
intervening comments), and shared-member references outside the storage folder.
The reviewed remaining literal mentions are only preserved logs, test groups
and ledger labels/assertions. Cross-owner doc references now name their owners
without adding dependencies only for documentation.

Final tooling fixtures pass (nine repoint fixtures, declaration negatives and
reference-guard fixtures). The exact CI format scope checks 1,079 files without
changes; its analyzer command succeeds with the same 15 existing informational
diagnostics. All step analyzer comparisons add no diagnostics. Gate 2 remains
the final integration and private-CI check.
