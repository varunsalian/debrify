# Collections hardening review — PR #54

Reviewed against `webdav-sync` at `93b92cafcf3b8e71d7333fa28ae84848ab7e4226`,
after the contributor branch incorporated the conflict resolution at
`27992115e6db2886fe3fcf7faf1c188631332e46`. The repair retains the import format
and Home/folder integration and replaces the unsafe persistence and paging
behavior. The PR remains based on `webdav-sync`; it is not merged into that
branch by this work.

## Five review rounds

1. **Profile storage and import integrity.** Reproduced the original failures,
   then verified profile-switch cancellation, concurrent imports, imports racing
   a sync apply, refused device-budget writes, corrupt data protection, legacy
   array migration, backup round trips, retained deletions, explicit reorder,
   reimport visibility, full-content signatures, and storage/identity bounds.
   Imports now use the profile mutation barrier for the entire read/update/write.
2. **Recurring sync and deletion.** Replaced the collection-list scalar with
   individual stamped records and an order record. Tests cover independent
   device imports, durable deletion, Home refresh dispatch, and a two-engine
   encrypted publish/merge/apply scenario, including an engine restart and an
   intentional later reimport. Existing WebDAV engine, codec, profile, graph,
   tombstone, adoption and runtime tests were included in broad verification.
3. **Catalog browsing and navigation.** Verified fallback resolution against the
   requested browsable catalog, filtered-empty pages, overlapping catalog pages,
   same-ID movie/series separation, serving-addon propagation, transport failure
   and retry, raw exhaustion, bounded no-progress behavior and concurrency.
   TV Tabs now uses the attached grid key. Retry retains tab B, successfully
   loads its results and moves TV focus from Retry into content. Folder requests
   are retired on configuration/folder changes; All gets a fresh grid key.
4. **Responsive UI and live changes.** Rows and Tabs were exercised at 320×568,
   568×320, 768×1024, 1280×720 and 1920×1080 with long names and unavailable
   artwork. Tests open the phone Filters sheet and select All, check merged
   deduplication/source identity, and remove the collection while the folder is
   open. Settings dialogs use 1.5× text at phone portrait/landscape and TV sizes.
   Paste import is exercised with a landscape keyboard inset. This round found
   and fixed narrow-sheet dropdown overflow, scrollability gaps, and stale open
   settings. Initial and retry rail batches are bounded to four requests.
5. **Integration and final audit.** Ran the combined collections, WebDAV, Home,
   backup, sorting and shared filter/dropdown suites. An existing source guard
   expected four Home browser routes; its expectation now includes the fifth
   collection route, which also applies the existing expanded-card settings.
   Analyzed every Dart file changed by the PR or repairs and built the complete
   application Dart bundle. Reviewed the final diff and documentation for the
   inventory migration, retained deletions and practical size limits.

## Reproduction commands

```sh
flutter test --no-pub \
  test/home_collections_test.dart \
  test/home_collections_regression_test.dart \
  test/home_collections_storage_test.dart \
  test/home_collections_responsive_test.dart \
  test/collection_catalog_pager_test.dart \
  test/services/webdav_sync \
  test/home_row_focus_test.dart test/home_row_order_test.dart \
  test/home_sections_filter_page_test.dart test/home_layout_policy_test.dart \
  test/home_catalog_refresh_test.dart test/home_extra_rows_test.dart \
  test/home_expanded_card_settings_test.dart test/home_hero_source_test.dart \
  test/backup_encryption_test.dart test/profile_backup_migrate_source_guard_test.dart \
  test/see_all_added_sort_test.dart test/see_all_filter_bar_test.dart \
  test/stremio_dropdown_sections_test.dart
flutter build bundle --debug --no-pub
```

Static analysis of the PR and repair files reports no errors or warnings and
25 informational notices already recorded on the pre-repair branch. The Dart
bundle build succeeds. The final combined command above passes **736 tests**.

## Verification limits

These are unit/widget tests and an encrypted in-memory WebDAV transport; they
are not a physical-TV playback session or a live WebDAV-server soak test. The
bundle build compiles application Dart, not each native release package. No
claim of universally bug-free playback, addon behavior, animated-art performance
or every possible device size is made.

Concurrent edits to the same collection retain the existing last-writer stamp
semantics. Different collections merge independently. The 128 KiB/1,024-live-collection
definition bounds exclude pending deletion records; the existing shared 1 MiB WebDAV
hot-document ceiling still applies after aggregation with other profile data.
Legacy array preferences upgrade on mutation, so devices editing this feature
should run the repaired implementation. The import UI remains an importer and
manager, not a collection authoring editor.


## Follow-up review — 2026-09-07

The review of `519454cf` identified additional P2 issues. They are addressed by:

- Salvaging valid records for Home, Home Rows and backup; settings offers an
  explicit reset, and restore can repair a damaged inventory. Ordinary imports
  still protect damaged data from accidental overwrite.
- Tolerant hot build/materialization, including malformed record values and
  encoded identities. A multi-profile engine test verifies corrupt collection
  data does not abort the cycle.
- Moving null deletion markers into WebDAV's native tombstone tier. The engine
  journals converted deletions before local apply, then removes local markers.
  Retention starts at publication and uses the existing 90-day horizon and
  dormant-peer suppression. Tests cover crash-after-apply recovery, expiry,
  dormant peers, explicit reimport, and 1,100 pending deletion identities without
  blocking a new live collection.
- Claiming catalogs only when collection rows are visible in Home. Hidden rows,
  Search and Discover do not suppress their catalogs.
- Comparing folder configuration before rebuilding. Unrelated notifications
  preserve the grid state and focused poster; actual configuration changes
  restore a usable focus target.

Additional checks cover a one-request retry cache bypass, HTTP 200 without
`metas`, a shared eight-request paging budget, fallback source deduplication,
visibility changes on oversized synced definitions, and the reset UI. Settings
no longer labels action dialogs as imports, and its layout toggle is visibly
inactive while an operation is pending. Same-collection edit/delete stamp
semantics are documented in `collections.md`.


Follow-up validation: **772 tests passed** in the combined command above plus
`test/profiles/profile_stremio_isolation_test.dart`,
`test/catalog_ingest_spike_test.dart`, `test/stremio_addon_import_test.dart` and
`test/stremio_metadata_provider_test.dart`. Full PR analysis reports no errors
or warnings and the same 25 informational notices. The application Dart bundle
build succeeds. Physical-device playback/live-server limits remain as stated.

## Whole-feature follow-up (Part 2, 2026-09-07)

This pass starts at `38a60e6f` and supersedes the earlier permissive catalog
fallback behavior described above. The Part 1 inventory/sync repairs remain.

- Canvas, Atrium, Mosaic, Deck, Tonight and Promenade now size collection
  cells using collection geometry and pass cover art, focus GIF and hidden-title
  preferences to the shared card. Folder focus replaces the stage identity/art,
  retires pending title enrichment and trailers, and clears live IPTV. Route
  returns cannot schedule a folder trailer.
- Sources require their declared addon identity and requested browsable catalog.
  A matching catalog id on another provider cannot silently supply or claim a
  row. Different manifest identities need an explicit source-id correction.
- The common import parser accepts a leading BOM for file, URL and pasted JSON.
- Newly discovered pinned rows lead existing saved orders. Canvas/Classic and
  Home Rows use the same pin seeding; already saved manual positions survive.
- Spotlight supports square covers and per-card hidden captions. Focus GIFs
  have bounded decode width; failed Spotlight previews reveal the cover.
- Rail See All carries the current Discover card preferences across the route
  boundary and only passes genres supported by the catalog. Folder detail/play
  uses the actual serving addon object, preserving its configuration.
- TV poster focus uses the grid's scroll behavior; only rail-pill focus also
  invokes rail alignment, removing the competing outer scroll request.

Validation: **834 tests passed**, including collections recovery/storage/paging,
WebDAV engine/runtime, backup/profile isolation, Home ordering/filtering, shared
Spotlight rendering, BOM/identity regressions and See All scope propagation.
The full debug Dart bundle builds. Analysis across PR Dart files and the shared
Spotlight widget reports **no errors or warnings**, with 27 existing infos
(the wider file set adds the Spotlight widget's two pre-existing infos).
Stage-private wiring and hero retirement have source guards; shared Spotlight
shape/caption rendering, Home Rows persistence and See All propagation have
widget tests. This does not substitute for an Android TV hardware pass through
all six layouts, focus GIFs and active trailer transitions. Remaining Part 2
P3s are deferred, apart from the adjacent fixes explicitly listed above.

## Replay and All-view follow-up (Part 3, 2026-09-07)

Starting at `06290656`, the new regression tests reproduced both reported
All-view failures (an overlapping source and a client-filtered window) and a
collection deletion lost during pending-apply replay.

- All ignores individual no-progress windows while sibling sources advance.
  Genuine transport errors still surface, and exhausting the shared eight-window
  budget still produces a resumable retry state.
- Replay journals converted collection tombstones in the adapter's `beforeWrite`
  hook, inside the preference mutation fence, before local markers disappear.
  The successful replay state update also retains those tombstones with the
  baseline. The regression interrupts a normal apply, deletes a collection,
  crashes again after replay materialization, restarts and verifies convergence
  on a peer still holding the live record.
- Empty-object and null-`metas` catalog responses are accepted as exhaustion,
  matching Home/See All. Wrongly typed `metas` remains an uncached retryable
  failure. This supersedes the earlier missing-array strictness.

The low-impact addon-signature and live See All preference limitations, and
remaining P3 findings, are not addressed in this pass.

Validation: **841 tests passed** across the same collections, WebDAV, backup,
profile, Home and Spotlight suites used in Part 2. Full debug Dart bundle
build succeeded. Analysis of all PR-touched Dart files found no errors or
warnings and the same 27 existing informational diagnostics. Hardware TV
validation remains outstanding.

## Final whole-branch review (2026-09-07)

Reviewed the full feature at `697ab9bf` against `webdav-sync` (`93b92caf`),
including imports, inventory persistence, Home and TV layouts, Rows/Tabs/All,
source resolution, backup, sync replay and shared widget changes. No new P1/P2
blocker was confirmed; the earlier blocking fixes retained their behavior.

All **841 regression tests passed**. Analysis of every PR-touched Dart file
reported no errors or warnings and 27 existing informational diagnostics. An
additional widget probe traversed 12 folder rails with DPAD Down at 1280×720.

A direct legacy collection-helper probe found an export/restore size-limit
mismatch for an oversized synced union. Call-site review established that synced
profiles use the native profile archive path instead, so this is not evidence
of a normal Backup & Restore failure and was not treated as a merge blocker.

The partial addon-signature and live See All settings behavior and documented
P3s remain follow-up work. Physical Android TV checks of rapid folder focus,
focus GIFs and transitions from active trailers are still outstanding.
