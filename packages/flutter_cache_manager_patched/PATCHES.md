# Debrify cache maintenance patch

Based on the official flutter_cache_manager 3.4.1 pub.dev archive, SHA-256:
`400b6592f16a4409a7f2bb929a9a7e38c72cceb8ffb99ee57bbf2cb2cecf8386`.
Source and upstream tests are retained with their MIT license. The application
uses a path dependency override so no developer's global pub cache is modified.

## Changes to review when upgrading

- `CacheStore` deletes through the configured filesystem. Upstream constructs
  `io.File(relativePath)`, so a typical UUID filename is looked up relative to
  the process working directory instead of inside the image cache. Its metadata
  can then be removed while the actual image remains on disk.
- Await count/age deletions before removing metadata. Serialize removals of the
  same key and make cache reads wait for a removal already in progress.
- Optional `Config.maxCacheBytes` adds asynchronous LRU byte eviction, trimming
  to 90% of the limit. In-memory hits participate in recency. Download operations
  and images accessed within one minute are protected, with a deferred retry.
  This is a high-water budget, not a synchronous admission limit: current
  downloads and recently used files can temporarily exceed it.
- Use recorded download lengths. Backfill unknown legacy lengths in memory once
  per path, without statting all files every pass. Record lengths for direct and
  streamed writes too.
- On first maintenance per store and at most once daily on later activity, `IOFileSystem` removes unreferenced files older
  than one day inside that store's flat directory, without following symlinks.
  Existing recently-created orphans are reclaimed on later maintenance after the grace period. Other directories, channel databases and playback are excluded.
- Before metadata would trigger eviction, reconcile it against a native directory
  listing. Missing files do not consume the byte/count budget or force healthy
  artwork out. Missing rows are removed using the same active/recent-file guards.
  Under-budget, non-stale stores skip this inventory entirely.
- Orphan repair catches individual filesystem errors; directory-level failures
  are isolated from regular eviction and throttled to once daily. An inaccessible
  eviction candidate is retained while cleanup continues with other candidates.
- Legacy size failures are isolated per entry; inaccessible entries retain their
  metadata and are retried. Failed directory inventories fall back to individual
  existence checks, with per-file error isolation there too. Unverifiable bytes
  do not drive eviction of healthy files; the budget applies to the verifiable
  portion until access recovers. Tests cover recovery without caching false zeros.
- Readers waiting on a removal do not inherit its filesystem failure. Disk
  reads recheck the surviving file; memory-only reads may return a normal miss
  after invalidation. Successful removals still finish before readers proceed.
  Tests cover both read paths for successful and failed concurrent eviction.
- Cleanup is single-flight, yields between deletions, catches timer errors, and
  is cancelled/awaited on disposal. Startup scheduling is explicit and delayed.
- Debrify's shared artwork store is 200 MiB (trim to 180), IPTV logos 30 MiB
  (trim to 27), and the legacy/default image store 30 MiB (trim to 27).
  Existing cache keys, image URLs, image quality and HTTP behavior are retained.

## Validation

Run `flutter pub get` and `flutter test` in this package. `disk_budget_test.dart`
uses real temporary files and a JSON repository for disk deletion, orphan repair,
LRU, grace periods, in-flight protection, missing files and byte accounting.
The upstream suite covers loading, HTTP refresh, image resizing and repositories.
Generated Mockito mocks were refreshed for the added store methods.

TV hardware validation remains necessary for flash latency and cache-hit rates.
No claim is made that artwork explains every byte of a reported app-cache total.

Validated on 2026-09-07:
- Package suite: 129 tests passed (26 new disk regression tests).
- After pulling `webdav-sync` at `d11d912a`, app artwork, TV hero quality,
  TMDB transport and collection GIF/visual suites: 31 tests passed.
  Collection widget tests install a fresh memory-backed cache with fixture HTTP
  responses and dispose it inside the test body before pending-timer checks.
  Production cache timing and widget APIs are unchanged by this test fix.
- Targeted analysis of cache code and new tests: no issues.
- The app smoke test fails on an existing four-second AppInitializer timer;
  reproduced with all four tracked changes reverted to baseline `12553320`,
  then restored the patch and its dependency resolution. No startup-widget
  changes are included here.
