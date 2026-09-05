# Backup and restore reliability on TVs

Status: Milestones 2-4 implemented on branch `local-backup-archive`
(worktree `../debrify-backup-archive`, cut from `webdav-sync` at 65899f29).
Mac test evidence below; physical TV, Android save bridge, iOS, Windows and
Linux validation are PENDING. See "Implementation status" at the end. See [Mac validation results](BACKUP_RESTORE_MAC_VALIDATION.md).
Baseline: `v0.9.0-beta.1` compared with the current `webdav-sync` branch.
Date: 2026-09-05.

## Objective and boundaries

Make manual local backup and restore use bounded working memory as library
databases grow, preserve durable user data, and fail recoverably when storage,
permissions, or input files prevent completion.

Planning assumption from the discussion: new local backups are unencrypted.
Retain readers and passphrase prompts for existing encrypted backups. New
backup UI must clearly disclose that account credentials are included.

WebDAV sync is explicitly outside this project. Do not change its codec,
bootstrap, adoption, safety backups, record metadata, scheduling, or transports.
Also leave manual WebDAV backup/restore on its current format and path for now;
this avoids expanding this work into either WebDAV layer. Its memory limitations
remain deferred and must not be described as fixed by this work.

Do not change defaults or wire formats in shared `PortableProfilePackage`,
`ProfilePackageService`, or `ProfileDatabaseSnapshot` APIs. Prefer new local
archive services. Any necessary shared restore/storage extension must be
additive, preserve existing callers, and have regression coverage. Do not edit
the ongoing sync work or its plan.

## Evidence behind the change

- Snapshot export reads complete SQLite files and embeds them as base64.
- Section/package hashing and size checks allocate whole JSON strings and bytes.
- Encryption adds plaintext/ciphertext buffers, Argon2 working memory, a regular
  integer-list copy of ciphertext, and another base64 layer.
- Restore runs in an isolate but still reads and parses whole envelopes.
- Clearing references before save/upload helps after encryption, not its peak.
- Default snapshots retain rebuildable IPTV catalog and EPG caches until size
  compaction; current compaction can also omit Debrify TV and its saved hashes.
- The supplied TV log confirms the beta build but contains no failure or memory
  measurements. An out-of-memory diagnosis has not been established.

## Proposed local format

Use a separately versioned archive format, provisionally `.debrify`, with ZIP
container semantics and compact JSON metadata. Verify the installed archive
library's actual file-streaming APIs before choosing the implementation; an
archive API that materializes entire entries does not satisfy the requirement.

- A small manifest identifies format/version, creation time, backup mode,
  profile/resource identities, expected entries, sizes, hashes, and omissions.
- Store databases as binary entries, never base64 strings.
- Store preferences and resources as bounded records or separate bounded files,
  rather than one unbounded metadata document.
- Store imported M3U content, avatars, and portable engine files as attachments;
  large resource content must not accidentally return through inline JSON.
- Hash and optionally compress entries incrementally. Compression must use
  bounded buffers and move CPU-heavy processing away from the UI isolate.
- Initial implementation decision after the Mac probe: explicitly stored ZIP
  entries (`CompressionType.none`). The installed archive library buffers
  compressed entries/output; its standard compression path is not suitable.
  Compression is deferred until a bounded-memory implementation is validated.
  Use independent streamed SHA-256 verification; the library's ZIP decoder
  verification flag does not currently perform the expected CRC check.
- Use generated entry names and an explicit allowlist. Define maximum entry
  count, metadata sizes, individual expanded sizes, and aggregate expanded size.
  Set disk-oriented limits separately from memory limits after device testing.
- A manifest hash detects accidental corruption, not intentional tampering.
- Older app versions are not expected to read this new format; disclose that
  limitation and keep the existing formats readable in newer versions.

## Decisions taken 2026-09-05

### Imported M3U content becomes an archive attachment

Imported M3U content is the `content` field of the playlist JSON that is
sealed into the IPTV resource's `secretConfig` (see
`lib/services/storage_service.dart` around `_iptvPlaylistSecretFields`, and
`lib/services/profiles/profile_package_service.dart:138` where the secret is
exported). The shared package already caps a resource at
`PortableProfilePackage.maxResourceContentBytes` (64 MiB,
`lib/services/profiles/portable_profile_package.dart:38`).

Decision: the local archive layer strips `content` from each IPTV resource
record on export into a stored entry `attachments/resource-<n>.m3u`, leaving a
reference `{contentAttachment: entry, bytes, sha256}` in the record. Restore
extracts to staging, verifies size and hash, reads the entry back into the
string, and re-inlines it into the record before the record reaches
`ProfileRestoreCoordinator`. The coordinator, `ConnectionResourceService`, and
the WebDAV layers never see the reference form. Keep the existing 64 MiB
per-resource limit as the attachment limit; reject at extraction time.

Honest limit: restore peak memory is bounded by the largest single playlist
(one Dart string), not by a constant. Export still materializes one resource's
secret at a time through the existing export path.

### Durable catalog table allowlist

`iptv_catalog.db` mixes caches with durable rows. The selective/pruned snapshot
must keep exactly these tables and drop the rest:

Keep: `category_default_selections`, `category_manual_orders`,
`channel_manual_orders`, `channel_number_aliases`, `channel_number_assignments`,
`channel_number_namespaces`, `hidden_groups`, `webdav_sync_meta`,
`webdav_sync_record_state`.

Drop: `meta`, `catalogs`, `channels`, `epg_programmes`, `epg_guides`.

This matches the existing compaction list in
`lib/services/profiles/profile_database_snapshot.dart:298`. For
`debrify_tv.db` nothing is dropped in the new local format. Any new table
added to either database must be classified here; unclassified tables fail
export loudly rather than being silently kept or dropped.

### Regression baseline

Reuse `test/profiles/profile_database_snapshot_test.dart`,
`test/profiles/portable_profile_package_test.dart`, and the
`ProfileDatabaseSnapshot.debugExportBudgetOverride` seam. New archive tests
live beside them. Existing tests must stay green unchanged.

### File anchors for implementation

- Export entry: `lib/screens/settings/profile_backup_flows.dart:101`
  (`_createProfileBackupUnchecked`), local branch at line ~322.
- Package export: `ProfilePackageService.exportProfile` / `exportAllProfiles`
  (`lib/services/profiles/profile_package_service.dart:59,218`).
- Snapshot export/compaction/restore:
  `lib/services/profiles/profile_database_snapshot.dart:151,284,371`.
- Restore entry: `lib/screens/settings/profile_backup_flows.dart:647`
  (`_restoreProfileBackupFromPath`), coordinator call at line ~794.
- Coordinator: `ProfileRestoreCoordinator.restore` (line 582),
  `restoreDeviceGraph` (line 82), `_restoreDatabaseSection` (line 1126).
- Save bridge: `DownloadService.saveGeneratedFile`
  (`lib/services/download_service.dart:2703`), Android publication at
  `_publishGeneratedFileOnAndroid`.
- Archive library: `archive` 4.0.7; stored entries only
  (`CompressionType.none`); do not rely on `verify: true`.

### Non-goals (do not build)

- No compression, no encryption for the new format, no runtime autotuning.
- No changes under `lib/services/webdav_sync/` or to
  `webdav_backup_transport.dart`.
- No new global snapshot/write-lock system.
- No fork of `ProfileRestoreCoordinator`; additive hooks only.
- No enabling of local backup on tvOS.
- No patching of the `archive` package.

## Data coverage

Preserve existing portable profile settings, accounts, permissions, PIN records
where already supported, avatars, addons, engines, IPTV provider definitions,
file-imported M3U content, favorites, lists, history, resume, hidden categories,
ordering, numbering, and Debrify TV channels with their saved hash pools.

Always exclude rebuildable IPTV catalog/channel and EPG caches from new local
backups. Explain that guide/catalog data refreshes after restore, potentially
requiring network access. Do not remove imported playlist source content.

The agreed IPTV coverage is durable user data only:

| Keep | Exclude and rebuild |
| --- | --- |
| Provider setup: M3U URLs, Xtream credentials, imported M3U content | Downloaded provider channel catalogs |
| Favorites and custom lists, including saved channel entries and identity references | Rebuildable catalog metadata |
| Channel/category ordering, hidden categories, numbering and related settings | Downloaded EPG programmes and guide caches |
| Watch history and resume positions | Other explicitly identified rebuildable IPTV cache rows |

Saved channel entries inside favorites/lists are durable data even though the
full provider channel catalog is a cache. Preserve their source references and
provider setup so arrangements can reconnect to refreshed catalogs after
restore. This policy applies to IPTV, not Debrify TV channel/hash libraries.

Create consistent snapshots in private scratch storage. Never mutate live
databases. Benchmark a local-only durable-table export into a fresh database
against the existing snapshot-then-prune approach. Prefer avoiding a full copy
of a large cache if the selective export preserves schema, durable rows,
indexes, identity references, and existing consistency safeguards. Use bounded
SQL/file processing, not whole-table Dart lists. Retain snapshot-then-prune as
the correctness baseline if a selective path is not proven. Shared snapshot
export defaults remain unchanged. Measure integrity checks and snapshot disk
cost: streaming alone does not eliminate the reported packaging delay.

Do not reuse the existing compact mode wholesale: it can omit Debrify TV.
Preserve durable Debrify TV data regardless of size, subject to explicit disk
limits. No silent omissions. Continue excluding media binaries, running jobs,
device credentials, pairings, OS grants, and other existing device-only state.

Transport-specific database metadata is not a new portable-data contract.
Preserve existing local restore handling of that metadata and cover it with a
focused regression check. Do not introduce a new copy/strip policy or redesign
sync. Only a concrete regression introduced by the new local archive path
justifies raising a separate dependency.

Preserve existing export authorization, captured profile-generation, and
snapshot consistency safeguards. Test edits/profile changes during export for
regressions against current behavior. This project does not introduce an
application-wide snapshot or write-lock system without evidence that the new
path requires it.

## Speed and responsiveness

Optimize actual elapsed time and UI responsiveness together. Do not promise
instant completion or show success before verification and publication.

- Do less work first: omit rebuildable IPTV data at export and avoid copying it
  when the selective snapshot prototype proves safe and faster.
- Hash entries incrementally while writing/extracting. Reuse those results
  within the same operation instead of extra hash-only reads. Retain completed
  archive verification and required SQLite integrity checks; a hash computed
  from source bytes alone does not verify a stored destination copy.
- Benchmark stored ZIP entries (no compression) against light compression on
  slow TV storage. Choose based on total time, peak memory, and archive size;
  do not introduce strong compression or runtime autotuning by default.
- Process one database/file at a time with bounded buffers. Run CPU-heavy work
  off the UI isolate without passing giant in-memory payloads to workers.
- Show the busy UI immediately, before snapshot work begins. Report concrete
  stages such as “Saving IPTV favorites…”, “Saving Debrify TV: 18 MB of 40 MB”,
  and “Checking backup…”. Show byte totals only when actually known; otherwise
  use a stage indicator, not a fabricated percentage or ETA.
- Allow cooperative cancellation before publication. Keep input/animations
  responsive even when slow storage limits throughput.
- Complete restore after durable data has been validated and safely committed.
  Refresh provider catalogs/EPG afterward through existing loading paths, with
  a clear notice that listings/guides may still be loading. Network failure
  must not roll back an otherwise successful restore or erase saved user data.
- Compare old/new export and restore stage timings on settings-only,
  cache-heavy IPTV, imported-M3U, and large Debrify TV libraries. Report backup
  completion separately from subsequent catalog/EPG refresh time.

## Implementation milestones

### 1. Diagnostics and baseline

- Record operation ID, stage, elapsed time, entry sizes, available disk space
  where supported, and process-memory samples where available.
- Record caught exception type and stack trace through the privacy-safe logger.
  Never log credentials, playlist URLs, raw metadata, or database contents.
- Use available Mac hardware for the prototype and local implementation gate.
  Reproduce on a 32-bit Android TV and Shield-class device when available;
  record those results as pending meanwhile. Separate snapshot time, hashing,
  encoding, and file I/O.
- Capture baseline memory measurements; do not infer a precise peak from code.

### 1a. End-to-end feasibility gate

- Before building the complete format, prototype one large database and one
  large imported M3U through archive writing, local file save, extraction, and
  restore staging on Mac. Separately validate the Android destination bridge
  when available. Measure process memory and, during app integration, Dart heap.
- Mac file-stream feasibility is complete: approximately 614 MiB input used
  45–47 MiB peak probe RSS for stored-entry writing/restoring. This does not
  complete actual app export/transactional restore or metadata integration.
- Trace allocations before the archive writer as well: exporting a resource
  may already materialize M3U content. Streaming ZIP entries alone is not proof
  of bounded memory. Define per-record and aggregate metadata limits and a
  bounded attachment path; document any existing storage API limit explicitly.
- Verify that the archive library streams actual file contents and enforces
  extraction budgets without first inflating an entire entry into memory.
- Benchmark selective durable-table snapshots and no/light compression using
  the speed rules above before choosing defaults for the complete writer.
- Use the existing Android native file-path save bridge through an additive
  Dart file-based save entry point. Preserve destination selection and fallback
  behavior; do not build another native publication mechanism unnecessarily.
- Identify the smallest file-based staging extension to the existing restore
  coordinator. Keep one implementation of authorization, ID remapping, rollback,
  and publication. A new general restore abstraction is optional, not a goal.
- Proceed to the full implementation once this path demonstrates bounded
  database/attachment processing and unchanged restore transaction behavior.
  Re-estimate the remaining work from the prototype results.

### 2. File-backed export and archive writer

- Add a local export inventory of snapshot paths and bounded metadata records.
- Snapshot profiles sequentially; avoid retaining every profile's data in RAM.
- Implement streaming entries, hashes, and manifest publication.
- Add disk-space estimation covering snapshot copies, compaction workspace,
  archive output, and destination copying. Handle ENOSPC during every stage even
  after a successful preflight check.
- Verify the finished archive before marking it ready for save.
- Add a file-path/stream save route; the current `saveGeneratedFile(bytes: ...)`
  route must not force the completed archive back into a `Uint8List`. Preserve
  existing byte-based callers and Android/desktop destination policy.
- Publish atomically where supported. On document providers without atomic
  rename, keep local verified staging until copy completion and report partial
  destination failures accurately. Never overwrite an unrelated backup.

### 3. File-backed restore

- Probe file headers with bounded reads to distinguish new archives from
  supported legacy JSON backups; do not rely on extension alone.
- Extract to private staging with path traversal, duplicate-entry, symlink,
  unexpected-entry, truncation, and decompression-limit checks.
- Verify all declared sizes/hashes, metadata references, and SQLite integrity
  before any destination becomes visible. Do not execute SQL from the archive.
- Use a file-backed restore input to stage database files directly. Never adapt
  the archive back into a base64 `PortableProfilePackage` to reuse old code.
- Prefer additive database/file staging hooks in the existing coordinator, with
  the current legacy staging path as the default. Do not fork the coordinator
  or duplicate its transaction/publication logic. Introduce an adapter only if
  the prototype shows it makes that integration smaller and clearer.
- Preserve authorization revalidation, ID remapping, rollback, and shadow
  generation publication semantics of existing single/all-profile restore.
- Keep existing encrypted/plain JSON readers available through explicit legacy
  routing. Their whole-envelope memory limits remain; do not claim old large
  backups acquire bounded-memory restoration merely from the new format.

### 4. Local UI and lifecycle

- Route only manual local creation to the new archive implementation.
- Show concrete stages and byte progress when totals are known; no invented ETA.
- Support cooperative cancellation before publication and clean owned scratch.
  Prevent overlapping operations and define profile-switch/app-background rules.
- Clean abandoned scratch safely on restart; retain completed user backups.
- Surface actionable storage, permission, corruption, and compatibility errors.
- Keep existing platform restrictions until each platform passes verification;
  this work does not automatically enable local backup on tvOS.

### 5. Verification and release gates

- Round-trip one/all profiles and every durable data category above, including
  imported M3U attachments, large Debrify TV pools, credentials, and custom files.
- Assert cache omission while durable rows and settings survive unchanged.
- Restore with network unavailable: favorites/lists, provider definitions, and
  arrangements must survive; catalog/EPG refresh can succeed later. Verify
  saved identities and ordering still resolve after the provider refresh.
- Test supported legacy encrypted/plain fixtures and wrong passphrases.
- Test low disk space during snapshot/write/extraction, revoked destination
  access, cancellation, process interruption, damaged archives, unsafe entries,
  excessive expanded content, and unknown format versions.
- Verify failed restore leaves existing profiles and generations usable.
- Check ordinary edits and profile changes during export against existing
  safeguards; fix new regressions without adding a global snapshot system.
- Check that database sync metadata follows existing local restore behavior.
  This is a compatibility test, not authorization to change the sync layer.
- Measure export AND restore with increasing database sizes (for example 10,
  100, and 500 MiB where device disk permits), and with multiple profiles.
  Database-size growth must not produce proportional Dart heap growth; inspect
  total process memory too, including SQLite and compression allocations.
- Establish a concrete memory ceiling from the smallest supported test TV after
  the prototype. Do not present an unmeasured number as a release guarantee.
- Run relevant existing profile/restore regressions and unchanged sync caller
  compatibility checks if shared APIs are extended. No sync implementation edits.
- Physical Android TV/Fire TV and Shield tests are follow-up compatibility
  checks when hardware is available, not blockers for Mac implementation.
  Desktop tests alone do not establish that the reported TV failure is resolved;
  disclose pending TV validation in any release assessment.

### Platform validation matrix

Use one archive format across platforms. Validate the actual platform file
save/pick paths; a shared Dart implementation is not evidence that permissions,
document providers, and lifecycle behavior work everywhere.

| Platform | Required checks |
| --- | --- |
| Android phones/tablets | Local round trip, document-provider/MediaStore destinations as applicable, permission loss and interrupted copies |
| Android TV / Fire TV / Shield | Physical round trip, large libraries, 32-bit memory where supported, slow/low storage, remote navigation and responsive progress |
| iOS | Local round trip through supported Files/save paths, picker access and lifecycle interruption |
| macOS | Local round trip, destination permissions, cancellation and large-library check |
| Windows | Local round trip, path/filename handling, locked files and interrupted save |
| Linux | Local round trip, destination permissions and interrupted save |
| tvOS | Preserve existing local-backup restrictions; do not enable a new local flow or change WebDAV behavior |

Verify cross-platform archives in both directions for Android and desktop, and
include iOS in interchange checks. Record untested platforms as pending rather
than claiming universal compatibility. Test one/all-profile semantics and
legacy-reader availability on platforms where those flows are supported.

## Completion criteria and remaining limits

New local archives never materialize whole databases or whole archives in RAM
on creation, destination save, validation, or restore. Durable data survives a
round trip, caches are deliberately rebuildable, failures are diagnosable, and
existing destination data remains intact until restore commits.

Full disks, inaccessible destinations, failing hardware, and unsupported input
cannot be guaranteed to succeed. The guarantee is bounded processing and safe,
clear failure handling. Existing JSON paths and all WebDAV paths retain their
current behavior until separately addressed.

## Effort

Initial estimate is provisionally 3–6 engineering days, subject to milestone 1a.
The main uncertainty is a file-backed restore/save integration that preserves
existing transactional semantics without altering sync consumers. Re-estimate
after the end-to-end prototype, before committing to the full implementation.

## Implementation status (2026-09-05, Mac only)

Built:

- `lib/services/profiles/local_backup/local_backup_zip.dart`: own stored-entry
  ZIP writer/reader (ZIP64 offsets, UTF-8 names). The `archive` package's
  encoder/decoder process a whole entry synchronously and buffer compressed
  data, so the container is written and read in 256 KiB chunks with
  streaming CRC-32 and SHA-256, cooperative cancellation, and bounded
  central-directory parsing. Archives remain readable by the library's
  decoder (tested).
- `local_backup_archive.dart`: manifest (`manifest.json` + `manifest.sha256`),
  `LocalBackupExporter` (staging inventory, file sinks, verification pass),
  `LocalBackupRestorer` (extract with size/digest/name/unexpected-entry/
  future-version checks, playlist re-inline, file-backed decode),
  `LocalBackupScratch` (startup sweep from `main.dart`), operation guard,
  diagnostics events (`local_backup` source, no paths or contents).
- Additive shared hooks: `ProfileDatabaseSnapshot.export(fileSink:,
  pruneRebuildableCaches:)` and `restore(fileResolver:)`;
  `ProfilePackageFileSinks` on `ProfilePackageService.exportProfile/
  exportAllProfiles`; `PortableProfilePackage.decodeFileBackedMap`;
  `ProfileRestoreCoordinator.restore/restoreDeviceGraph(databaseFileResolver:)`;
  `DownloadService.saveGeneratedFileFromPath`. Base64 and WebDAV callers are
  untouched; the durable/rebuildable catalog table allowlist is enforced and an
  unclassified table fails the export.
- UI: local creation routes to the archive (disclosure dialog, no passphrase,
  cancel button, stage + MB progress); local restore probes the ZIP header and
  routes archives to staging, then the existing confirm/restore path.

Evidence (Mac, `flutter test`, 302 MiB `debrify_tv.db`, one profile):

| Stage | Time | Process RSS |
| --- | ---: | ---: |
| Baseline (test VM) | — | 199 MiB (peak 213) |
| Export + verify | 5.6 s | peak 293 MiB |
| Stage + coordinator restore | 10.5 s | peak 293 MiB |

Peak growth of ~80 MiB is SQLite `VACUUM INTO`/copy working memory plus test
harness; it did not scale with the database. Restore peak is bounded by the
largest single imported playlist string, as decided above. Tests:
`test/profiles/local_backup_zip_test.dart`,
`test/profiles/local_backup_archive_test.dart`; existing snapshot, package,
coordinator, encryption and resource-service suites pass unchanged (106).

Review round 1 (2026-09-05) applied: restore inspects the manifest and
confirms/authorizes before extracting; one streamed copy helper
(`lib/utils/streamed_file_copy.dart`) replaces three loops; picker cache is
cleared after mobile restores; manifest encode/hash and package decode run off
the UI isolate through argument-only helpers (an inline `Isolate.run` closure
captures the enclosing scope); the dead local JSON creation branch is gone and
the JSON flow is WebDAV-only; `saveGeneratedFile` stages to a temp file and
delegates to the one path-based destination ladder; `_compactSnapshot` derives
its catalog list from the classification; `iptv_catalog_table_classification_
test.dart` binds the allowlist to the live schema.

Review round 2 applied: the generated-file ladder checks the test override
before touching the cache dir (round 1 had broken
`download_service_generated_file_test.dart`) and is one writer-parameterized
ladder; `inspect` returns a digest that `stage` re-checks against the archive
stamp so the manifest is read once and a swapped file is refused; manifest
hashing joined parsing off-main and the envelope no longer crosses back to the
UI isolate; the busy dialog removes its own route instead of popping whatever
is on top; the inactivity lock is held off during unpack via
`setPlaybackActive`; only the picker's own cached copy is deleted (the plugin's
clearTemporaryFiles wipes iOS tmp wholesale).

Review round 3 (low effort, last commit only) applied: the inactivity-lock
hold lives in the shared busy dialog so every long stage is covered; the
picker copy is found via `Directory.systemTemp` with symlinks resolved (iOS
picks live in NSTemporaryDirectory, not Caches) and Android's timestamped
parent folder is dropped when empty; `stage()` requires an inspection, so no
unpack path skips the swap check; export verification compares the stored
manifest stamp and streamed digest instead of re-parsing the envelope; the
generated-file ladder stages for Android itself, so callers pass only a writer.
Three review rounds converged; remaining findings were nits.

Not done / pending:

- No physical Android TV, Fire TV, Shield, phone, iOS, Windows or Linux run.
  The Android native save bridge is reused by path but has not been exercised
  with a file outside the cache directory.
- No disk-space preflight; ENOSPC is caught and surfaced at every stage.
- Compression, encryption of the new format, and the legacy JSON memory
  limits are unchanged by design.
