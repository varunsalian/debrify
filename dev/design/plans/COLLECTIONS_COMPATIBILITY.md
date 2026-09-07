# Collection compatibility implementation

Scope: close all twelve gaps from the collection review while preserving addon
collections, profile isolation, watched filtering and remote navigation.
Baseline: `webdav-sync` at `12553320`. Changes are local and uncommitted.

## Requirement audit (2026-09-07)

| Requirement | Implementation and evidence |
|---|---|
| 1. Native TMDB | `collection_native_source_service.dart` loads LIST, COLLECTION, COMPANY, NETWORK, DISCOVER, PERSON and DIRECTOR. Deterministic request/filter/paging tests plus live checks of all seven types pass. Nuvio streaming region/monetization and network defaults are preserved. IMDb enrichment coalesces/caches lookups and retries failed enrichment on opening a title. |
| 2. Public Trakt | Singular movie/show list endpoints, all eight Nuvio sort options, direction and pagination. Live populated public list loads. Tests cover request semantics, errors and titles with only TMDB IDs. |
| 3. Addon matching | `home_collections_store.dart` resolves enabled addons by manifest/local identity, exact catalog ID and normalized type aliases. Ambiguous All types and unrelated provider catalogs are never substituted. Regression tests cover aliases and missing catalogs. |
| 4. Useful errors | Settings and browser distinguish absent/disabled addons, missing configured catalogs and unsupported providers. Partial source failures remain visible alongside working lists; native auth/network errors are retryable. Browser tests exercise partial failure and denial. |
| 5. Hero video | `FolderHeroBand` uses the shared muted looping `CollectionFocusArt` lifecycle, with still fallback. Rendered wiring tests cover the hero URL; existing engine tests verify mute/loop, decoder serialization, route/lifecycle suspension, reduced motion and failure fallback. |
| 6. Imported layout | TABBED_GRID selects tabs; FOLLOW_LAYOUT selects rows; absent viewMode uses the profile preference. Phone/TV browser tests verify imported tabs and native See all/Back navigation. |
| 7. Emoji covers | Folder metadata carries coverEmoji into shared Home cards and Spotlight. Rendered tests find all emoji labels; placeholders retain emoji when titles are hidden or artwork is missing. |
| 8. Collection backdrop | Folder hero falls back to collection backdrop, then folder cover. Folder metadata also uses the collection backdrop. Rendered hero test verifies fallback priority. |
| 9. Mixed shapes | Each folder selects its aspect in Classic and Spotlight; shared stage cards fit their own shape within the row's maximum-aspect slot. Rendered Spotlight test measures all three tile ratios; stage wiring regressions pass. |
| 10. GIF disable | Explicit focusGifEnabled=false suppresses animation; omitted flag permits legacy URL-only imports. Parser, row and persistence tests cover this. |
| 11. Editor/export | Collection, folder and source editors provide create/edit, removal, ordering, validation and detached drafts. Settings exposes file/clipboard export. Tests cover phone/desktop/TV-sized forms, nested creation, cancellation, offscreen validation, saved folder ordering and clipboard export preserving native definitions. All form fields remain registered during scrolling. |
| 12. Large packs/storage/sync | 8 MiB local import growth, independently bounded inventory chunks, separate collection sync sections and the original 1 MiB ordinary hot limit. See the mixed-version follow-up below. The 1,755-source real native pack survives backup and sync encode/merge/materialization with a compressed preference below 128 KiB. Corrupt gzip, excessive expansion, profile races, budget refusal and existing deletion/merge regressions pass. |

## Verification

- Final collection regression command below: **177 passed**, including the
  settings edit/order/export test.
- Native/visual final targeted run: **19 passed**.
- Live opt-in TMDB/Trakt suite: **8 passed**; NETWORK passed again after matching
  Nuvio's default filters.
- Additional codec, backup, sync engine/definitions, Spotlight and TV settings
  suite: **167 passed, 1 pre-existing failure**. The failing test is
  `Sync and Migrate has its own reachable TV rail category`; it expects the old
  label (`Sync and Migrate` instead of the current `Sync and backup`). The same test fails using the exact HEAD version of
  `settings_tv_layout.dart`, before the two attribution lines added here.
- Analyzer for collection models, services, screens, widgets and new tests:
  **No issues found**. Full touched-file analysis has pre-existing informational
  findings in Search, settings and Spotlight; no errors or warnings.
- Final Dart application bundle builds successfully with the ignored local TMDB
  configuration.
- `git diff --check` passes. Credential scan finds no token literal in any
  reviewable changed/untracked file; `.env.local.json` remains ignored.
- Screenshots rendered and inspected for mixed tile geometry and the phone
  editor. Headless test fonts limit emoji glyph appearance; actual platform
  decoder/hardware playback was not exercised. The existing playback engine is
  reused and its lifecycle is tested with controlled engines.

Reproduce the collection suite:

```sh
flutter test --no-pub test/collection_editor_test.dart test/collection_native_sources_test.dart test/collection_native_browser_test.dart test/collection_visuals_test.dart test/home_collections_test.dart test/home_collections_storage_test.dart test/home_collections_regression_test.dart test/collection_focus_effects_test.dart test/collections_stage_regression_test.dart test/collection_catalog_pager_test.dart test/home_collections_responsive_test.dart test/services/webdav_sync/webdav_sync_hot_merge_test.dart
flutter test --no-pub --dart-define-from-file=.env.local.json --dart-define=COLLECTION_LIVE_TESTS=true test/collection_native_live_test.dart
flutter build bundle --debug --no-pub --dart-define-from-file=.env.local.json
```

## Real imports and operating limits

- Kaptain Mega Native 0.61: all **822 TMDB + 933 Trakt** sources retained.
- The Kollection addon pack: all **11 collections, 138 folders and 289 unique
  configured sources** retained. Both fixture sources are recorded under
  `test/fixtures/collections/README.md`.
- Addon-backed lists still require the corresponding catalog configuration;
  native sources do not manufacture a missing addon catalog. Deleted/private
  or empty remote lists remain unavailable/empty rather than being replaced by
  unrelated lists. Playback requires a configured compatible stream provider.
- Existing imports must be reimported to recover native definitions or visual
  fields discarded by older builds. New collection changes sync between upgraded builds. Older builds retain
  ordinary hot sync and their legacy snapshot; rich data lives under a separate
  key and section namespace. Full backups use a plain legacy-readable envelope.

## References

- NuvioTV domain/model/Collection.kt, core/tmdb/TmdbCollectionSourceResolver.kt,
  and collection/FolderDetailViewModel.kt in https://github.com/NuvioMedia/NuvioTV.
- Current user-facing behavior: `docs/collections.md`.
- TMDB attribution: official blue-short logo and required notice in phone and
  TV Settings About. Logo source: https://www.themoviedb.org/about/logos-attribution.

## Follow-up review fixes

- P1: Existing source editor drafts are now deep mutable copies, including nested
  filters. Regression tests reopen Discover, Company and Network sources, both
  unchanged and edited, save through the nested editors and confirm the imported
  source remains unchanged.
- P2: Whole TMDB list/franchise/credits responses are paged locally in batches of
  20 before identity enrichment. Raw snapshots use a bounded cache; remote LIST
  pagination and failed-page retries preserve buffered titles and cursors. Tests
  block all lookups after the first 20 of a 400-title response and prove the first
  page still completes, then cover the final page, sorting, remote boundaries,
  failed requests and bounded empty-page retries.
- Validation: 76 selected editor/source/browser/pager/regression tests passed;
  the source suite with the final empty-window retry regression passes all 24
  tests. Analyzer reports no issues for the changed source/editor and tests.

- Cross-page sorting review: non-original TMDB LIST sorts now collect all raw
  remote pages and sort the complete snapshot once before local slicing. IMDb
  enrichment remains limited to the requested 20-title batch, and original
  order still loads on demand. Added cross-page popularity/rating/vote/date and
  ascending-order tests, plus an incomplete-snapshot retry regression. All 46
  selected native source/browser/pager tests pass; changed-file analyzer is clean.

- Merged-inventory review: reproduced two separate valid 7 MiB imports failing
  during sync materialization. Inventories now use the 32 MiB hot-document
  budget for encoding/decompression, with 44 MiB allowed for encoded gzip/base64
  overhead. Local growth remains capped at 8 MiB. The regression verifies merge,
  materialization, strict decode, recovery, rejection of additional local growth,
  visibility changes, deletion and subsequent smaller imports. All 80 selected
  collection storage/regression and hot-merge tests pass; analyzer is clean.


## Mixed-version and browsing review follow-up

- Kept ordinary hot payloads at 1 MiB. Collection records/order now publish in
  separate bounded `collections-v2/<profile>/<chunk>` sections, including seed
  activation, verified peer reads, cache invalidation and obsolete-shard cleanup.
- Collection conflicts use ordinary stamp ordering regardless of serialization
  version. The second review refuted the need for rich-version priority: no
  released build syncs collections.
- Moved compressed preferences to `remote_home_collections_v2`, a key old clients
  exclude from recurring sync. Full profile backups bound plain v2 under the legacy key to 128 KiB; larger
  inventories use an integrity-covered preference-section extension. New restores
  compact either representation directly, avoiding a duplicate large tvOS preference. Existing legacy preferences remain a downgrade snapshot.
- Merged inventories beyond 32 MiB use independently compressed chunks. A
  regression merges five separate 7 MiB inventories, round-trips sync and plain
  backup representations, then changes visibility and deletes a collection.
  Separate local growth limits and device preference budgets remain enforced.
- Native source identity excludes titles and foreign fields and is persisted.
  Explicit saved IDs are retained; missing IDs in stored and fresh imports use
  the same identity helper. Duplicate entries remain distinct, including IDs
  emitted by the editor. Cache keys still include source configuration.
- Migrated stored focus GIF behavior separately from fresh import defaults.
- Opening a title shows cancellable progress; a later selection supersedes an
  earlier request and only the current result may navigate. The wait is bounded.
- Identity enrichment has a three-second page budget, two workers and an
  independent gate. Slow external-ID calls cannot occupy catalog request slots.

Follow-up validation:

- Broader collection, sync, activation, graph, backup and profile suite: **476 passed**.
- After the final migration/provenance adjustments, the affected storage, editor,
  browser, merge, engine and restore suite: **235 passed**.
- Application bundle builds successfully with the ignored local configuration.
- Changed collection/sync/profile code and regression tests pass static analysis;
  `git diff --check` is clean.
- Changes remain local and uncommitted. Older builds require an upgrade to receive
  new collection changes, while ordinary hot sync retains its original format.

## Second review follow-up

- Enforced tvOS budgets now defer only oversized collection materialization with
  a settings notice, retaining the full target in engine state. Resume/watched
  writes continue; persisted local snapshots prevent false edits after restart.
- Collection splits are cached and unchanged per-shard digests reuse manifest
  references. Split/digest/seal work runs off the UI isolate.
- Missing TMDB list sort means author order. Explicit global sorting is bounded
  to 50 remote pages, with Original order offered for larger lists.
- Editor-generated duplicate source IDs receive stable ordinal suffixes.
- Normal LWW resolves mixed serialization versions; newer visibility toggles win.
- Legacy backup restoration recovers valid records from partial corruption.
- Encoding reuses serialized records across chunks; unpacking decodes once and
  measures decoded bytes without another JSON pass. Large store work runs outside
  the UI isolate and preference barrier with compare-and-retry at commit.
- Canonical JSON and native request gates share their existing implementations.

Second-pass validation:

- Collection, complete WebDAV sync, restore, preference and lock-order suite:
  **805 passed**. Additional interrupted deferral/restart engine test: **1 passed**.
- Tests enforce the real tvOS budget using an incompressible 7 MiB inventory,
  verify resume/watched writes across repeated deferrals, recovery after shrink,
  persisted remote targets, and genuine local edits while deferred.
- Three resume ticks preserve collection content hashes and publish at most the
  changed hot section and manifest. Invalid own sections still republish.
- Async preference preparation allows snapshots and racing sync writes, then
  retries against the fresh value before committing.
- Application bundle build succeeds with the ignored local configuration.
- Repository-wide analysis still reports unrelated existing package diagnostics;
  changed-file analysis has no errors or warnings (existing UI lint infos remain).
- Changes remain local and uncommitted.

## Third review: transition and compatibility regressions

- Fixed migration-only re-stamping by comparing migrated forms without storage
  markers, preserving the original value and stamp when unchanged. Tests cover
  legacy GIF migration, materialization/rebuild, and a peer edit winning in both
  merge orders.
- An interrupted first deferred apply with neither baseline nor local data emits
  no collection order. The pending manual order remains authoritative on replay.
- Bounded legacy backup preferences to 128 KiB. Large inventories use chunked
  `collectionInventory` metadata inside the preference section, covered by the
  whole-package integrity digest. Old readers ignore it and receive a compatibility
  notice; new readers restore the full inventory. Both single and graph exports
  share the same projection. No remote key is exposed to an old preference validator.
- Verified an incompressible 7 MiB backup using the actual HEAD package decoder
  in a temporary test copy, then restored every byte through the current coordinator.
  The temporary legacy source/test were removed afterward.
- That end-to-end test exposed the restore staging 4 MiB string limit. Collection
  storage now uses its dedicated bound; all staging writes check device capacity.
  An enforced-budget restore regression verifies the current generation survives.
- Refuted sanitized export finding: both collection keys are absent from the
  explicit sanitized allowlist. A full package export/decode regression verifies
  neither preference keys nor the new extension can leak into a sanitized package.
- Removed the obsolete rich-version precedence comment; provenance is migration
  metadata, not a conflict-resolution override.
- Unrelated configuration refreshes no longer cancel an opening title. The
  explicit request, profile, route and mounted guards still apply.
- Rails and All-view readers reuse raw list snapshots with five-minute idle expiry.
  Repeated readers do not restart global sorted pagination.
- Fixed singular folder descriptions and integral JSON double IDs. Preserved
  recovery notices through backup restoration and cleared stale capacity notices
  when no collection target remains.
- A separate bounded 64 MiB collection section cache handles shards over 4 MiB;
  ordinary hot state retains its separate 4 MiB budget. Both cache eviction and
  engine-level repeated resume cycles are covered.

Third-pass validation:

- Final collection/native UI/storage and complete WebDAV suite: **815 passed**.
- Focused engine/capacity/restore/package/budget suite: **178 passed**.
- Actual HEAD legacy decoder compatibility experiment: **1 passed**; temporary
  sources removed. The 7 MiB incompressible inventory round-trips byte-for-byte.
- Focused static analysis: **no issues**. Application bundle build succeeds.
- Full profile suite: **658 passed, 4 failed**. Remaining failures are the two
  existing profile-editor label assertions, a device-reset source substring
  assertion, and the raw preference allowlist missing the unchanged
  `webdav_sync_save_feedback.dart`. These code paths are unchanged from HEAD.
  The newly added capacity adapter's read-only budget access is now registered;
  a focused guard rerun confirms only the pre-existing save-feedback path remains.
- `git diff --check` passes. No commit or push was performed.
