# Apple TV storage and memory growth audit

**Date:** 2026-08-14  
**Branch reviewed:** `feature/profiles` at `26adfc1e`  
**Evidence device:** Apple TV named **Bedroom**  
**Scope:** the entire Debrify application, not only Profiles

## Executive summary

The Apple TV startup failure observed on Bedroom was not a vague low-memory
event. Four device crash reports identified a deterministic tvOS preferences
violation:

`__CFPREFERENCES_HAS_DETECTED_THIS_APP_TRYING_TO_STORE_TOO_MUCH_DATA__`

Apple documents a warning at 512 KiB and process termination at 1 MiB for the
tvOS `UserDefaults` database. The profiles migration copied legacy preferences
into a generation-scoped namespace, while a rebuildable TVMaze response cache
was still stored in preferences. That temporarily duplicated a large payload
and crossed the platform limit.

The immediate startup blocker is fixed. TVMaze persistence is disabled on
tvOS, its old entries are pruned before bootstrap/migration writes, and SQLite
migration now validates WAL-backed copies safely. The IPTV catalog path is also
substantially better than it first appears: downloads are bounded, large parse
work happens off the UI isolate, catalog rows are paged from SQLite, decoded
images have a 56 MiB cap, and several caches have explicit limits.

The application is not yet fully growth-proof on Apple TV. Two remaining
issues are future P1s:

1. There is no whole-`UserDefaults` byte budget enforced before every write.
   Several live JSON stores remain unbounded, so the same tvOS termination can
   recur as ordinary user data accumulates.
2. The Keychain recovery envelope has a 768 KiB limit, but runtime profile and
   connection counts are not budgeted before a registry transaction commits.
   At the limit, the cache projection can commit while the durable recovery
   publication fails.

Large purgeable stores also need disk quotas and peak-space checks. Bedroom
already demonstrated why: one IPTV catalog was about 426 MB, and migration
left both the legacy and profile-scoped copies present.

## Apple platform constraints used in this review

### `UserDefaults` is a hard process-safety boundary

Apple's current Foundation documentation says tvOS posts
`UserDefaults.sizeLimitExceededNotification` when the defaults database reaches
512 KiB. If the app continues writing and reaches or exceeds 1 MiB, tvOS
terminates the process. This is a database-wide limit, not a per-key limit.

Source: [Apple — `UserDefaults.sizeLimitExceededNotification`](https://developer.apple.com/documentation/foundation/userdefaults/sizelimitexceedednotification)

Consequences for Debrify:

- A 4 MiB per-value allowance is not safe on tvOS.
- Moving a value behind a profile prefix does not move it out of
  `UserDefaults`; it still counts toward the same database.
- Excluding a value from the Keychain recovery snapshot does not stop it from
  consuming `UserDefaults` space.
- Catching a Dart exception is not sufficient after the native database has
  crossed the termination threshold.

### Cache storage is purgeable, not durable

Apple's tvOS storage guidance says data outside the very small local persistent
store must be purgeable. Files in `Library/Caches` may be deleted while the app
is not running, and the app must be able to operate without or regenerate
them. Apple also warns against consuming the entire cache space because the
result is unpredictable.

Sources:

- [Apple — App Programming Guide for tvOS: Local Storage for Your App Is Limited](https://developer.apple.com/library/archive/documentation/General/Conceptual/AppleTV_PG/)
- [Apple — Using the file system effectively](https://developer.apple.com/documentation/foundation/using-the-file-system-effectively)

Debrify's `AppStorage` intentionally maps documents, application support, and
cache roots to `Library/Caches` on physical tvOS. Therefore every SQLite DB and
file reached through those helpers is a projection. User-created identity,
profile authorization, and connection ownership must be recoverable from the
device-bound authority; catalogs, artwork, EPG, and activity need to tolerate
purge or be rebuilt.

### There is no one published RAM number to design against

Apple does not publish one stable per-app RAM ceiling for every Apple TV model.
The effective limit depends on the device and current system pressure. tvOS can
terminate a visible app in a jetsam event, and the event report is the evidence
needed to distinguish that from an ordinary crash.

Sources:

- [Apple — Identifying high-memory use with jetsam event reports](https://developer.apple.com/documentation/xcode/identifying-high-memory-use-with-jetsam-event-reports)
- [Apple — Reducing your app's memory use](https://developer.apple.com/documentation/xcode/reducing-your-app-s-memory-use)

Accordingly, this audit treats unbounded buffers, decoded image working sets,
and multiple simultaneous representations of large payloads as defects even
when they fit on the current Bedroom device.

## Evidence captured from Bedroom

The following is a privacy-safe summary of the 2026-08-14 device inspection.
No credentials, URLs, playlist names, or viewing titles are included.

| Observation | Measurement | Meaning |
|---|---:|---|
| CFPreferences crash reports | 4 | Confirms the startup failure was the tvOS defaults limit, not jetsam or SQLite corruption. |
| App container size during the sweep | approximately 1.36 GB | The cache projection is already large enough that duplication and missing eviction matter. |
| Decoded preference values after recovery cleanup | 62,748 bytes across 148 keys | Healthy at that moment, but not protected by a global future-write budget. |
| Preferences file observed on disk | approximately 105 KB | Safely below the current warning, after the offending rebuildable cache was removed. |
| Legacy IPTV catalog DB | 425,963,520 bytes | Retained source from the migration rollback window. |
| Profile-scoped IPTV catalog DB | 425,963,520 bytes | Byte-for-byte scale duplication of the largest store. |
| Profile `debrify_tv.db` | approximately 17.85 MB | Material but not the dominant store. |
| Active IPTV catalog rows | approximately 330,993 | About 206,448 VOD, 56,632 live, 55,166 live, and 12,747 public-list rows. |
| SQLite integrity check | `ok` | The large catalog was healthy; its size was real data, not corruption. |

These measurements are a snapshot of one installation, not a benchmark or a
promise that other providers have similar payload sizes.

## Current storage map

| Subsystem | tvOS location/authority | Current bound | Growth assessment |
|---|---|---|---|
| Device and profile preferences | `UserDefaults` / CFPreferences | No database-wide pre-write cap | **Red.** Platform kills the process at 1 MiB. |
| Profile/security recovery | device-only Keychain, 8 KiB immutable shards plus atomic manifest | 768 KiB envelope; recoverable preferences also capped at 512 KiB | **Red.** Bounded, but the budget is checked after ordinary mutations can commit. |
| `profiles.db` | `Library/Caches` projection | Rebuilt from recovery envelope | Green only while every authority mutation is successfully checkpointed. |
| IPTV catalogs and stored EPG | profile generation `iptv_catalog.db` in `Library/Caches` | Per-download caps; no total on-disk quota | **Amber/red.** 426 MB observed and multiple providers add linearly. |
| Debrify TV channels/torrent pool and IPTV activity | profile `debrify_tv.db` in `Library/Caches` | IPTV watch history 100; Debrify TV torrent pool has no row/byte cap | **Amber.** Activity is purgeable, but manual imports can grow indefinitely. |
| Home/poster/backdrop disk cache | `flutter_cache_manager` under caches | 1,000 objects, 30 days; count-based only | **Amber.** Object count is not a byte ceiling. |
| IPTV logo disk cache | separate cache manager | 2,000 objects, 30 days | Amber/green; isolated from poster churn but count-based. |
| Flutter decoded image cache | process RAM | 140 images and 56 MiB on TV | Green. Hard byte cap. |
| Top Shelf trailer previews | `Library/Caches/TopShelfPreviews` | 6 files, 180 MiB, 14 days | Green/amber. Explicitly bounded, though the ceiling is substantial. |
| M3U response | process RAM, then worker/SQLite | 50 MiB | Green/amber. Bounded and transferred to a worker, but the permitted peak still requires device testing. |
| Xtream response | process RAM, then worker/SQLite | 100 MiB per response; 3-entry fallback result cache | Green/amber. The unbounded HTTP body was fixed. |
| XMLTV guide download | temporary cache file, worker parse, SQLite | 300 MiB download ceiling | Amber. Streaming avoids a 300 MiB UI-heap buffer, but parser peak and low-disk behavior need stress coverage. |
| Profile backup received on tvOS | authenticated Remote transfer | 16 MiB receiver ceiling | Green. File-picker export/restore is disabled on tvOS. |
| Profile database attachments on other platforms | temporary file plus package JSON | 64 MiB each, 128 MiB total | Bounded, but whole-buffer/base64 construction has a high peak. |
| Imported profile engines | scoped files | 4 MiB each, 64 MiB total | Green. |
| User avatar bytes | not materialized on tvOS | art/icon only on tvOS | Green for Apple TV storage and RAM. |
| Pending external actions | sealed device file | 32 entries and 24-hour expiry | Green. |

## Findings

### P1 — `UserDefaults` can still grow back into the tvOS kill threshold

> **Status 2026-08-14:** the enforcement half of this finding has shipped. See
> `docs/superpowers/plans/2026-08-14-tvos-preference-budget.md`.
> `ProfilePreferenceBudget` refuses net-growth writes above 384 KiB at the
> `ProfilePreferences._write()` chokepoint, and legacy migration now preflights
> the whole copy set before creating or writing anything, degrading to legacy
> mode instead of crashing. The recurrence path is closed.
>
> The **required direction below is still outstanding**: the bulk stores listed
> here remain in `UserDefaults` and are now capped rather than relocated. Once
> an installation reaches the limit, further growth is silently dropped. Moving
> them to scoped SQLite is the real fix and remains the next piece of work.

The TVMaze cache was one proven trigger, not the only possible source. All
profile preferences still share the same native defaults database. The
`ProfilePreferences` facade writes first and requests a recovery checkpoint
afterward; it does not calculate the projected total CFPreferences footprint
before the native write.

Live growth-capable examples include:

- `playback_state_v1`: an unbounded map of titles, seasons, episodes, finished
  episodes, track preferences, and playback metadata.
- `episode_trakt_progress_v2` and `episode_simkl_progress_v1`: growing
  all-series snapshots.
- `series_source_<imdbId>`: one key per bound title, with no global title or
  per-title source cap.
- `user_playlist_v1`, `my_watchlist_v1`, and Stremio local catalogs: full JSON
  collections with no byte quota.
- Other dynamic maps and lists in `StorageService`; individually modest values
  can still cross the database-wide limit in aggregate.

Some stores are already well controlled: continue watching is capped at 50,
torrent search history at 5, IPTV watch history at 100 and moved to SQLite,
and TVMaze is memory-only on tvOS. Those local caps do not provide a global
guarantee.

The recovery filter is not a storage budget. It excludes names containing
history, resume, cache, favorites, EPG, TVMaze, downloads, or recordings from
the Keychain snapshot, but the original values remain in `UserDefaults`.
`playback_state_v1`, episode progress, and `series_source_*` also pass the
current recovery-name filter.

**Required direction:** make tvOS `UserDefaults` an allowlisted small-scalar
store. Move collections, activity, and caches to scoped SQLite/files; enforce a
conservative whole-database byte budget before every remaining write; and
listen for `sizeLimitExceededNotification` as telemetry and emergency cleanup,
not as the primary guard.

Suggested internal ceiling: keep controlled Debrify values below roughly
384 KiB, leaving space for plugin/native keys and serialization overhead. The
exact threshold should be validated against the native database size, not the
sum of Dart string lengths alone.

### P1 — recovery publication can fail after registry state commits

`TvOsProfileRecoveryStore` uses a good publication structure: 8 KiB immutable
Keychain shards, hashes, a transaction UUID, an atomic manifest switch, and an
orphan-shard sweep. It also refuses an envelope above 768 KiB.

The unresolved problem is ordering and capacity admission. Runtime profile,
resource, grant, binding, journal, and ownership tables do not have a recovery
budget enforced before their SQLite transaction. A mutation commits to the
purgeable `profiles.db` projection, then `checkpointTvOsRecovery()` serializes
and publishes the new authority. If serialization exceeds either the 512 KiB
recoverable-preferences bound or 768 KiB envelope bound, the call throws after
the projection changed while Keychain still contains the previous generation.
A later tvOS cache purge can therefore roll back an apparently completed
profile or connection mutation.

Portable-package limits of 64 profiles and 1,024 resources do not constrain
normal runtime creation.

**Required direction:** calculate the prospective recovery envelope before
committing any authority mutation, impose explicit runtime limits, and fail the
operation before changing SQLite. Also expose current/maximum recovery bytes in
privacy-safe diagnostics. Longer term, compact the recovery schema rather than
raising the cap blindly.

### P2 — legacy migration currently doubles the largest databases

The migration deliberately retains legacy files for a rollback window. On
Bedroom this left a 425,963,520-byte legacy IPTV catalog and an equally large
profile-scoped copy. This is the dominant reason the container was about
1.36 GB.

The current branch has WAL-safe snapshot validation (`16a8392d`), so the copy
is consistent. What is missing is the planned follow-up migration that removes
retained legacy databases and preferences after the rollback window ends.

**Required direction:** ship a versioned, journaled legacy-source cleanup after
the supported downgrade window. Verify the scoped copy and recovery authority,
delete only the inventoried legacy sources, and make interruption resumable.

### P2 — staging and restore need peak-disk admission

Profile generation staging clones the current generation's durable areas
before publication. Retired generations are kept for seven days and collected
at startup. With a 426 MB catalog, even a settings-focused restore can require
another complete database copy; SQLite sidecars and a concurrent catalog
refresh add more transient space.

There is no available-capacity preflight before these copies. Apple exposes
volume capacity APIs for important and opportunistic usage, but using the
required-reason API must be declared in the privacy manifest.

Source: [Apple — `volumeAvailableCapacityForImportantUsage`](https://developer.apple.com/documentation/foundation/urlresourcevalues/volumeavailablecapacityforimportantusage)

**Required direction:** estimate peak bytes before migration, restore, or
generation cloning; require headroom for source + destination + expected WAL;
clean abandoned staging generations immediately; and shorten retention on
tvOS when more than one retired generation or a low-space condition exists.

### P2 — IPTV catalog and EPG storage have no global byte quota

The catalog implementation is strong at the operation level:

- a catalog points atomically at a generation;
- chunked ingest limits write-lock and WAL growth;
- one previous generation is retained only long enough for pinned readers;
- source deletion removes its channel catalogs;
- the UI pages rows instead of materializing hundreds of thousands of channel
  objects on the main isolate.

The missing boundary is total storage. Every configured source and content
kind can add another catalog, and no LRU or byte budget spans them. A single
real installation reached approximately 331,000 active rows and 426 MB.

Stored XMLTV guides are replaced per `guideKey`, but deleting a playlist or
changing its EPG URL does not remove unreferenced `epg_guides` and
`epg_programmes` rows. JSON EPG snapshot files older than seven days are swept;
the equivalent SQLite orphan sweep is absent.

**Required direction:** add a per-profile catalog budget, show its usage,
prefer eviction of rebuildable inactive/stale catalogs, and garbage-collect EPG
guide keys not referenced by any live playlist/resource. `VACUUM` or incremental
vacuum policy should be measured after large deletions so logical cleanup also
returns disk space.

### P2 — two import paths can still create excessive RAM peaks

Debrify TV's device-file import rejects files above 100 MB, but a 100 MB ZIP or
YAML is still materialized whole and a ZIP can expand far beyond its compressed
size. The URL and community-channel download helpers buffer responses without
an equivalent byte limit before parsing. `archive` decoding then holds the
compressed input, expanded entries, decoded strings, YAML object graph, and
converted models during the same operation.

This is reachable independently of Profiles and is a classic jetsam/OOM path
on a constrained television.

**Required direction:** stream downloads with a small compressed-byte cap,
limit archive entry count and total expanded bytes, reject suspicious
compression ratios, cap YAML depth/records/strings, and import channels
incrementally rather than retaining the complete archive result.

### P2 — artwork disk caches are count-bounded, not byte-bounded

The main artwork cache allows 1,000 objects for 30 days. Its own comment notes
that 2,000 objects had reached roughly 600 MB and that halving the object count
only roughly halves the footprint. One thousand unusually large backdrops can
still greatly exceed that estimate. The IPTV logo cache has the same structural
limitation at 2,000 objects, although typical logo files are much smaller.

The in-memory side is properly bounded at 56 MiB / 140 decoded images on TV.
This finding is about disk pressure and purge churn.

**Required direction:** add a byte-accounted eviction layer or periodic size
sweep, keep poster/backdrop and logo budgets separate, and validate that every
cache miss has a functional placeholder/reload path after tvOS purges the
directory.

### P2 validation item — the 300 MB XMLTV ceiling is bounded but unproven

XMLTV is streamed to a temporary file, parsed off-isolate, filtered to the
current channel set, and written directly into SQLite. That avoids the worst
whole-file UI-heap design. However, 300 MB is a network safety ceiling, not a
measured Apple TV working-set budget. The parser's index, strings, SQLite
writes, and any concurrent video/artwork allocations can still exceed the
device-dependent jetsam limit.

**Required direction:** run the 90th/99th-percentile guide fixtures on the
oldest supported Apple TV while collecting Xcode peak memory and jetsam logs.
Lower the cap or parse more incrementally if the measured headroom is poor.

## Risks already mitigated in the current branch

### Preferences and migration

- `c4a31b0a` disables persistent TVMaze response caching on tvOS and prunes
  both legacy and partially scoped TVMaze keys before bootstrap/migration
  writes.
- `16a8392d` validates copied SQLite databases in a WAL-safe way and removes
  temporary sidecars before accepting the snapshot.
- Committed startup can rebuild the purgeable profile registry projection from
  the Keychain recovery authority.

### IPTV memory and responsiveness

- M3U downloads are streamed with a 50 MiB cap and deadline.
- Xtream responses are streamed with a 100 MiB cap rather than `http.get`
  buffering without a limit.
- Large M3U/Xtream payloads cross isolates as transferable bytes; decode,
  parse, and SQLite ingest happen in the worker so the large channel list does
  not return to the UI heap in DB mode.
- Catalog views use paged SQLite-backed lists with bounded page retention.
- Ingest is chunked and publication is generation-atomic.
- Interrupted automatic refreshes back off instead of crash-looping every page
  open.

Most of this hardening landed in `79b1bb00`; the DB-backed architecture was
introduced in `fc24700a`.

### Images, avatars, transfer, and previews

- TV decoded-image cache: 56 MiB / 140 entries.
- IPTV logos use a separate 2,000-object disk cache so they cannot evict Home
  artwork continuously.
- Top Shelf previews: 6 files, 180 MiB total, 14-day age limit.
- tvOS refuses user-file avatars; code/asset avatars survive cache purge.
- Profile remote payload receiver: 16 MiB maximum.
- Profile file/database attachments and imported engines have explicit
  per-file and total limits.

## Recommended implementation order

1. **Centralize the tvOS preference budget.** Inventory the small scalar
   allowlist, move bulk live stores out, add pre-write projected-size admission,
   and test against a native database near 512 KiB and 1 MiB.
2. **Make recovery capacity transactional.** Pre-serialize the prospective
   recovery state before every authority commit; add runtime profile/resource
   limits and diagnostic byte counts.
3. **Retire legacy migration sources.** Remove the duplicate 426 MB-class DBs
   after the downgrade window with a crash-resumable cleanup journal.
4. **Add disk headroom and quotas.** Cover generation staging, catalogs, EPG,
   artwork, and Top Shelf as one device budget rather than isolated counters.
5. **Bound channel imports and archive expansion.** Close the remaining direct
   RAM-amplification path.
6. **Measure the bounded large paths.** M3U 50 MB, Xtream 100 MB, XMLTV 300 MB,
   a catalog refresh during video playback, cache purge, and restore/profile
   switch on the oldest supported Apple TV.

## Required regression matrix

| Journey | Fixture/state | Pass condition |
|---|---|---|
| Cold launch | defaults DB below warning, at warning, and attempted over-budget write | App never writes past its internal limit; actionable error replaces native termination. |
| Long-term playback | thousands of titles and complete multi-season histories | Bulk state is outside preferences; bounded query/startup time. |
| Profile growth | maximum supported profiles, resources, grants, and preferences | Recovery preflight succeeds or rejects before SQLite mutation; purge restores the exact committed graph. |
| Cache purge | delete all of `Library/Caches` while app is not running | App starts safely; authority survives; rebuildable data repopulates; no infinite spinner. |
| Migration | 500 MB WAL-mode catalogs plus near-budget preferences | Peak-space check is correct; no partial authority; cleanup resumes after forced termination. |
| Restore | large live generation plus failed staged restore | No live corruption; abandoned copy removed; disk returns to baseline. |
| Catalog growth | several 100k-row providers and multiple EPG URLs | Total quota enforced; inactive data evicts; active provider remains usable. |
| Import | oversized HTTP body, 100 MB YAML, high-ratio ZIP, deep YAML | Refused before high allocation; UI remains responsive; no jetsam. |
| Playback stress | video + trailer transition + artwork churn + guide refresh | Peak memory stays below the Xcode red region; one video output; no jetsam report. |
| Top Shelf and image cache | fill limits, relaunch, force cache purge | Caps hold, oldest data evicts, and missing assets degrade cleanly. |

## Audit boundary and caveats

This was a source sweep plus a real-device storage/crash inspection. It covered
preference writers, profile recovery, SQLite stores and migration, filesystem
caches, IPTV/Xtream/XMLTV ingestion, images, Top Shelf, imports, avatars,
backup/restore, and profile-generation lifecycle.

It was not a full Instruments allocation trace of every navigation journey.
RAM findings are therefore based on allocation shape and explicit bounds;
release acceptance still requires device measurements and jetsam review. The
Bedroom sizes are evidence of present scale, not fixed thresholds. Secrets and
content-identifying values were intentionally not inspected or recorded.
