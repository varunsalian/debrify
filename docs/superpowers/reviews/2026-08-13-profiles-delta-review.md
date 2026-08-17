# Multi-Profile Remediation Delta Review

**Date:** 2026-08-13
**Reviewed baseline:** `591ec0a008115b8fd4ffa7c7ed3ffad70d582e86` (`0.8.2_alpha`) plus the uncommitted multi-profile implementation and first remediation pass
**Supersedes the release decision in:** [Multi-Profile Review Remediation Record](./2026-08-13-profiles-remediation.md)
**Supported platforms:** Android, Android TV, iOS, tvOS, macOS, Windows, and Linux. Web is not supported and is out of scope.
**Decision:** **NO-GO. Keep `DEBRIFY_PROFILES` and `DEBRIFY_PROFILES_MIGRATION_READY` disabled.**

> **Resolution status:** This document records the findings at review time.
> All 23 source findings have since been remediated in the uncommitted working
> tree and are mapped to current evidence in the
> [Multi-Profile Review Remediation Record](./2026-08-13-profiles-remediation.md).
> The NO-GO decision still applies until the listed physical and
> unavailable-host rollout gates pass.

## Executive result

The focused delta review found **5 P0**, **16 P1**, and **2 P2** unresolved source issues. The implementation still has a sound architectural base, and many first-review fixes are present, but it is not safe to expose to users yet.

The most important failures are:

1. A use-only Stremio grant can reveal, clone, and remotely export an addon URL containing credentials.
2. Resource authorization is not held through asynchronous secret reads or mutations, so revoked or cross-profile work can still return plaintext or commit.
3. Delayed Stremio operations started in Profile A can publish A's addon data into Profile B.
4. Remote exports can send an already-decrypted or mixed-profile secret after switch/revocation.
5. Native authority publication is neither fail-closed nor monotonic; a valid old Profile A snapshot can remain live after a failed Profile B switch/publication, and old job grants can survive revocation.
6. Upgrade/restore still has confirmed data-loss paths for legacy IPTV relations, queued jobs/schedules, native Android jobs, v3 generation evidence, and malformed legacy backup records.

The passing profile suite is useful but insufficient: `flutter test test/profiles --reporter compact` passes all 72 tests while every issue below remains reproducible from source. The missing tests are primarily adversarial switch/revoke timing, fault injection, legacy fixture reconciliation, native concurrency, and end-to-end platform journeys.

## Review scope and method

The delta review deliberately revisited the highest-risk claims rather than re-running the entire broad review:

- isolation and authorization: shared resources, secret provenance, async completion, PIN/profile management, policy boundaries, logs;
- remote behavior: peer/session leases, encrypted chunking, import/export authorization, revocation at send/commit;
- migration and durability: non-profile-to-Admin upgrade, v1/v2/v3 restore, final manifests, durable jobs, reset ordering, recovery UI;
- native/platform authority: Android projection and worker stores, Apple startup/backup/tvOS recovery, desktop lifecycle, supported-platform physical gates.

Severity is release-oriented:

| Severity | Meaning | Release consequence |
|---|---|---|
| P0 | Confirmed secret disclosure, cross-profile write, or authority bypass | Fix first; rollout must remain off |
| P1 | Credible data loss, stale authorization, broken recovery/feature, or security/privacy boundary failure | Blocks rollout |
| P2 | Bounded durability/availability defect or contract mismatch | Fix or explicitly accept before broad rollout |

## P0 findings

### DELTA-P0-001 — Stremio use-only grants disclose, clone, and remotely export credentials

**Platforms:** All
**Invariant:** `use` permits opaque execution only. It must not reveal, persist a borrower-owned copy of, or remotely transfer a secret.

**Evidence**

- Stremio manifest URLs may embed debrid credentials: `lib/models/stremio_addon.dart:478-495`.
- `StremioAddon` does not preserve resource provenance/read-only metadata through serialization/copying: `lib/models/stremio_addon.dart:716-801`.
- Ordinary addon reads decrypt under `use`: `lib/services/stremio_service.dart:146-158` and `lib/services/profiles/profile_collection_resource_facade.dart:55-69`.
- The settings UI renders and copies the full URL: `lib/screens/stremio_addons_page.dart:95-109,476-499,1284-1303,1504-1527`.
- Toggle/remove/add rewrites items without `sourceResourceId`: `lib/services/stremio_service.dart:195-220,236-267,387-402`. That defeats the borrowed-resource protection in `lib/services/profiles/connection_resource_service.dart:112-131` and can mint a borrower-owned clone.
- Remote addon export and transfer-all serialize normal addon values without `writeRemote`: `lib/widgets/remote/remote_addon_export.dart:31-64` and `lib/widgets/remote/remote_transfer_all.dart:136-141,391-403`.

**Deterministic regression:** Share an addon whose URL contains a sentinel secret with a use-only Member. The Member must be able to use it, but must not see/copy its URL, turn it into an owned resource by toggling/saving, or export it remotely.

### DELTA-P0-002 — Core resource authorization becomes stale across awaited work

**Platforms:** All
**Invariant:** Plaintext return and every authority mutation must still be authorized at their final publication boundary.

**Evidence**

- `authorize` validates the session once, then awaits resource/grant reads without a final validation: `lib/services/profiles/connection_resource_service.dart:298-325`.
- `resolveSecretForUse` subsequently awaits secret decryption: `lib/services/profiles/connection_resource_service.dart:230-240`.
- Create, replace, update, transfer, and bind paths similarly authorize before awaited cryptography/registry work and can mutate afterward: `lib/services/profiles/connection_resource_service.dart:32-87,93-173,243-278,480-520,523-545`.

**Deterministic regression:** Pause an injected cipher or registry operation, then switch profile, lock, revoke the grant, rotate/delete the resource, or publish a restore. Releasing the pause must produce neither plaintext nor a mutation/cache/notifier publication.

**Required shape:** Carry a captured capability containing profile, generation, session epoch, policy revision, resource ID/revision, and required permission. Revalidate immediately before plaintext escapes and immediately before each durable or process-global publication.

### DELTA-P0-003 — Delayed Stremio operations can write Profile A data into Profile B

**Platforms:** All
**Invariant:** An async operation must never recapture the current profile after it has read or decrypted source-profile state.

**Evidence**

- `addAddon` reads A's list, then awaits manifest HTTP: `lib/services/stremio_service.dart:241-248`.
- It calls `_saveAddons` after the await: `lib/services/stremio_service.dart:265-267`.
- `_saveAddons` only then captures the facade's current scope and also updates a process cache: `lib/services/stremio_service.dart:195-230` and `lib/services/profiles/profile_collection_resource_facade.dart:82-100`.
- Refresh paths have the same shape: `lib/services/stremio_service.dart:405-456`.

**Deterministic regression:** Delay the manifest response, switch A to B (and repeat with lock/revoke/delete/restore), then release it. B's resource graph, storage, and cache must remain byte-for-byte unchanged.

### DELTA-P0-004 — Remote outbound secrets are not authorized through the socket-send boundary

**Platforms:** All remote-capable platforms
**Invariant:** Authorization must bind the exact resource/revision and complete payload through the final send, not merely the earlier read.

**Evidence**

- Scalar export reads a bare `String` and sends later: `lib/widgets/remote/remote_config_export.dart:410-455` and `lib/widgets/remote/remote_transfer_all.dart:450-484`.
- Trakt access and refresh fields are read separately, allowing a mixed-profile payload: `lib/widgets/remote/remote_config_export.dart:470-493`.
- `readForRemoteTransfer` returns no resource/revision capability: `lib/services/profiles/profile_credential_facade.dart:267-293`.
- Remote state rechecks profile features, not the source resource; its final post-operation check occurs after bytes can have left: `lib/services/remote_control/remote_control_state.dart:125-144,614-646,946-955`.

**Deterministic regression:** Pause encryption or the transport immediately before send. Switch profile or revoke/rotate/delete the resource, then release. No byte containing the sentinel may be sent. A multi-field payload must be proven to come from one captured authority snapshot.

### DELTA-P0-005 — Native authority publication can retain or resurrect a valid old profile snapshot

**Platforms:** Android and Android TV; the publication contract also affects all future native consumers
**Invariant:** Native authority reduction/switch must be a monotonic, crash-safe handoff. Failure must deny, never leave an older valid authority live.

**Evidence**

- Profile activation commits/publishes the Dart target before native projection publication: `lib/services/profiles/profile_lifecycle.dart:64-75`.
- Registry authority mutations commit before invoking the checkpoint/publication callback: `lib/services/profiles/profile_registry.dart:480-495,1191-1230,1526-1590`.
- Projection publication is one last-writer-wins preferences value and does not invalidate the previous snapshot first: `lib/services/profiles/native_profile_projection.dart:42-106`.
- Concurrent publications have no mutex or monotonic compare-and-set; an older snapshot can be read first, publish after a newer one, and overwrite it.
- Kotlin validates only the stored snapshot, with no registry-generation comparison: `android/app/src/main/kotlin/com/debrify/app/profiles/ProfilePreferenceProjection.kt:16-23,60-98`.

**Impact:** A failed A-to-B publication can leave A's native Stremio/settings authority visible while Dart believes B is active. A failed or reordered revocation publication can let downloads/recordings continue under an old grant.

**Required shape:** Publish a durable deny/tombstone before authority reduction, or use a journaled monotonic generation/outbox that native code refuses unless it is the latest committed generation. Serialize publications and make recovery idempotently roll forward. Fault-inject every write boundary and reorder concurrent publications.

## P1 findings

### DELTA-P1-001 — `download` resource permission is defined but never enforced

- `ResourcePermission.download` exists at `lib/models/profiles/connection_resource.dart:20-26`.
- Default Child sharing grants only `use`: `lib/screens/profiles/edit_profile_screen.dart:245-250`.
- `DeviceJobStore.validateAuthorization` accepts `use`: `lib/services/profiles/device_job_store.dart:82-111`.
- Download/record entry paths rely on that validator: `lib/services/download_service.dart:2042-2076`, `lib/services/android_native_downloader.dart:60-72`, and `lib/services/live_recording_service.dart:437-449`.
- Native projection serializes resource ID/revision but no permission mask: `lib/services/profiles/native_profile_projection.dart:64-75`; Kotlin checks existence/revision only: `ProfilePreferenceProjection.kt:81-98`.

**Gate:** A use-only Member/Child can browse/play but every download, retry, recording, and schedule path must be rejected in both Dart and Kotlin.

### DELTA-P1-002 — Expired remote leases renew themselves before expiry is checked

The 15-minute TTL is implemented in `lib/services/profiles/profile_remote_lease.dart:19-20,42-80`, but inbound routing calls `bindAuthenticatedPeer` before `allows` at `lib/services/remote_control/remote_command_router.dart:336-353`. An authenticated session can therefore reinsert its expired lease before the check; sessions live up to 12 hours (`lib/services/remote_control/remote_constants.dart:43-44`).

**Gate:** With an injectable clock, a command at TTL+1 must fail and must not renew itself. Only explicit local reauthorization may bind a new lease.

### DELTA-P1-003 — Encrypted chunked remote transfers are unreachable in production routing

The sender encrypts the aggregate payload but emits chunk start/data as plaintext `RemoteCommand`s (`lib/services/remote_control/remote_chunked_send.dart:141-190`). UDP routes ordinary packets to the production command handler (`lib/services/remote_control/udp_command_service.dart:332-343`), which rejects all plaintext (`lib/services/remote_control/remote_control_state.dart:714-718`). The router's chunk handlers at `lib/services/remote_control/remote_command_router.dart:1789-2013` are therefore not reached through the production path.

**Gate:** A real paired two-endpoint integration test must transfer a payload above the chunk threshold, survive reorder/duplicate/replay attempts, and verify the receiver obtains exactly the encrypted source bytes.

### DELTA-P1-004 — Remote import can commit after `remoteTransfer` is revoked during confirmation

The incoming authority is checked while buffering and before the confirmation dialog (`lib/services/remote_control/remote_command_router.dart:316-366,794-858`). After user confirmation it performs only generic restore authorization (`lib/services/remote_control/remote_command_router.dart:865-883`); the restore coordinator checks `backupRestore`, not the originating remote capability (`lib/services/profiles/profile_restore_coordinator.dart:373-385`).

**Gate:** Revoke `remoteTransfer`, expire/revoke the peer lease, switch, lock, or delete while the confirmation dialog is open. Confirmation must not stage or publish anything.

### DELTA-P1-005 — Torrent search and cached Stremio reads bypass service-boundary policy

Torrent search has no `torrentSearch` service guard in `lib/services/torrent_service.dart:78-126,150-170,870-917` or `lib/services/dynamic_engine.dart:34-56,334-375`. Stremio returns its process cache before policy enforcement at `lib/services/stremio_service.dart:147-150`.

**Gate:** Revoke policy after a warm cache and during a delayed request. Both cached and network paths must deny before returning results or publishing state.

### DELTA-P1-006 — MDBList authorization ignores resource revision and composite writes can cross profiles

`ProfileAsyncAuthorization.isCurrentlyActive` validates scope but not an MDBList resource revision at `lib/services/profiles/profile_async_authorization.dart:24`. Reads and delayed list operations at `lib/services/mdblist/mdblist_service.dart:160-361`, mutations at `:371-432`, and clone/composite work at `:440-477` do not consistently hold one resource capability through final publication.

**Gate:** Delay each boundary, then rotate/revoke/delete the MDBList resource or switch/restore. No result, mutation, or notifier change may survive stale authority.

### DELTA-P1-007 — Sensitive logs remain outside the privacy source guard

The guard covers an exact file list and only selected print APIs (`test/profiles/profile_source_guard_test.dart:75-130`). Raw discovery errors/addresses remain in `lib/services/remote_control/udp_discovery_service.dart:112-132,167-199,223-265`; handshake data in `lib/services/remote_control/remote_session.dart:527-548`; Stremio URLs/errors in `lib/services/stremio_service.dart:175-177,387-393,421-423,449-452`; and torrent errors in `lib/services/torrent_service.dart:122-125`.

**Gate:** Expand structural coverage to every networking/credential/remote file and logging adapter. Sentinel URLs, tokens, IPs, payload excerpts, and exception strings must never reach release or debug logs.

### DELTA-P1-008 — Profile and PIN administration can commit after Admin authority expires

Profile creation carries no initiating actor capability (`lib/services/profiles/profile_creation_service.dart:45-84`). Registry update/disable APIs do not require one (`lib/services/profiles/profile_registry.dart:829-927`). Delete authorization occurs before a dialog, with deletion later (`lib/screens/profiles/manage_profiles_screen.dart:87-102,170-180`). PIN KDF work is awaited before the write without final revalidation (`lib/services/profiles/profile_pin_service.dart:37-46,60-76`). Editing similarly performs multiple awaited actions after one check (`lib/screens/profiles/edit_profile_screen.dart:142-213`).

**Gate:** Pause dialogs/KDF/registry calls, then lock, switch, demote, disable, or delete the Admin. No profile, grant, setting, or PIN mutation may commit.

### DELTA-P1-009 — Legacy IPTV restore can orphan Favorites and custom-list channels

Legacy providers receive new resource IDs and remain outside the visible graph while dependent Favorites/lists restore (`lib/services/profiles/profile_restore_coordinator.dart:431-512`). Rebinding only sees visible playlists and otherwise preserves the sender `playlistId` (`lib/services/iptv_transfer_payload.dart:301-345`). The resource is published later (`lib/services/profiles/profile_registry.dart:2184-2221`) and facade reads expose the generated UUID (`lib/services/profiles/profile_collection_resource_facade.dart:70-77`).

**Gate:** Restore v1 and v2 fixtures with provider ID `iptv-1`, Favorites, and custom lists. Every dependent channel must bind the published destination ID, play after restart, and follow provider deletion.

### DELTA-P1-010 — Legacy durable jobs are stamped revision 1 while Admin migration advances its revision

Credential insertion advances Admin revision (`lib/services/profiles/profile_registry.dart:1103-1131`). Migration classifies queues/schedules as device state without final rebasing (`lib/services/profiles/profile_migration_service.dart:695-724`). Legacy pending jobs, plugin metadata, and desktop schedules default to revision 1 (`lib/services/download_service.dart:170-188,1944-1972` and `lib/services/desktop_schedule_service.dart:42-65`). Authorization requires exact equality (`lib/services/profiles/device_job_store.dart:82-111`).

**Impact:** A valid queued download or recording schedule can be silently canceled/removed solely by upgrading; desktop URL/header payloads can also remain in legacy preferences.

**Gate:** Use real legacy fixtures with credentials plus pending/paused native/plugin downloads and recording schedules. Rebind each job to the final migrated Admin/resource revisions and prove successful execution.

### DELTA-P1-011 — Android native resealing races active old-revision writers

Three native stores migrate sequentially and one completion marker is then written (`android/app/src/main/kotlin/com/debrify/app/MainActivity.kt:1202-1233`). Locks are store-local (`DownloadTaskStore.kt:94-116`, `RecordingTaskStore.kt:116-134`, `RecordingScheduleStore.kt:82-101`). Workers/alarms can later persist in-memory old authority (`MediaStoreDownloadService.kt:357-380`, `LiveRecordingService.kt:877-903`, `RecordingAlarmReceiver.kt:121-143`). The marker prevents a future retry.

**Gate:** Instrument latches at every store replacement/marker boundary while workers and alarms write. The marker may commit only after producers are quiesced or a generation/row gate guarantees that every late write is resealed/rejected.

### DELTA-P1-012 — Missing/corrupt committed registry crashes before `runApp` instead of entering recovery UI

Bootstrap correctly refuses legacy fallback but throws on marker-without-authority and on unusable registry without a tvOS snapshot (`lib/services/profiles/profile_bootstrap.dart:65-93`). `main` awaits bootstrap before `runApp` (`lib/main.dart:188-195`). Tests currently assert the throw (`test/profiles/profile_bootstrap_test.dart:74-101`), not a usable recovery path.

**Impact:** Registry loss, corruption, or lost-WAL recovery can create a permanent startup crash loop with no in-app restore/reset option.

**Gate:** Launch into a privacy-safe recovery shell for missing DB, corrupt DB, lost WAL, and unusable recovery envelope. Prove v3 restore and explicit reset work without exposing legacy/profile data first.

### DELTA-P1-013 — Device reset releases Android SAF authority before stopping downloads

Directory cleanup is drained before general downloads (`lib/services/profiles/profile_device_reset_service.dart:187-224`). Native cleanup releases persisted URI grants (`android/app/src/main/kotlin/com/debrify/app/MainActivity.kt:1948-1981`). Downloads are canceled only later (`lib/services/download_service.dart:794-838`).

**Gate:** Trace reset with an active SAF-backed download. Every writer must be confirmed stopped before storage authority is released, then private partials may be deleted.

### DELTA-P1-014 — v3 device-graph restore publishes generations with empty final manifests

New generation rows start with `{}` and an empty hash (`lib/services/profiles/profile_registry.dart:497-527`). Device-graph restore writes attachments directly (`lib/services/profiles/profile_restore_coordinator.dart:135-177`), graph verification advances journal state without finalizing physical bytes (`lib/services/profiles/profile_registry.dart:1905-1934`), and publication does not finalize. Only the single-profile path invokes `generationManager.finalize` (`lib/services/profiles/profile_restore_coordinator.dart:514-542`).

**Gate:** Restore deviceGraph preferences, files, SQLite main files and sidecars; require a nonempty final manifest covering exactly the visible bytes. Mutating one byte immediately before publication must reject the graph.

### DELTA-P1-015 — Legacy backup adaptation accepts or silently drops semantically invalid resources

The adapter largely checks only for nonempty maps/lists (`lib/services/profiles/legacy_backup_adapter.dart:63-105`). Normalization can silently skip an emptied scalar secret or publish an unusable collection resource (`lib/services/profiles/profile_restore_coordinator.dart:449-480`).

**Gate:** Required-field schemas for every v1/v2 resource type, plus an inventory ledger requiring exactly one disposition—restored, explicitly user-accepted omission, or fatal error—for every present source record. Examples such as `pikpak: {"email":""}` and WebDAV without a URL must not yield a successful partial restore.

### DELTA-P1-016 — iOS automatic-backup exclusion is best-effort and may miss first-run preferences

Backup exclusion executes only at launch for paths already present, and errors are swallowed (`ios/Runner/AppDelegate.swift:127-159`). On a clean install the preferences plist may be created later by Flutter. The device key is appropriately `ThisDeviceOnly` (`ios/Runner/AppDelegate.swift:60-85`), while the commitment mirror is written later (`lib/services/profiles/profile_bootstrap.dart:401-423`).

**Impact:** A backup can contain commitment/scoped preference state without the excluded registry or device-only key, leading after restore to the committed-missing-authority crash loop.

**Gate:** Apply/assert exclusion after the preferences container exists, or make every restoreable mirror independently device-key-bound and non-authoritative. Verify the actual Apple backup manifest and a cross-device restore on physical iOS hardware.

## P2 findings

### DELTA-P2-001 — Generation GC can delete young restore evidence before the promised seven-day window

Bootstrap supplies a seven-day cutoff (`lib/services/profiles/profile_bootstrap.dart:118-126`), but registry selection deletes a generation when it is expired **or** beyond a positional two-generation cap (`lib/services/profiles/profile_registry.dart:2374-2403`). Three restores in one day can therefore remove still-young evidence.

**Gate:** Make age authoritative, or explicitly change the product/recovery contract and surface the tighter cap. Test several young retired generations.

### DELTA-P2-002 — Backup import still performs a whole-file read after a TOCTOU-prone size check

The UI checks provider-reported size/`length()` and then calls `readAsString` (`lib/screens/settings_screen.dart:3213-3247`). `PortableProfilePackage.decode` receives the whole String and only then allocates/checks UTF-8 bytes (`lib/services/profiles/portable_profile_package.dart:79-101`). A provider-backed file can grow or be replaced between those operations.

**Gate:** Enforce the byte limit incrementally while streaming. A custom/growing source must abort before exceeding the allocation budget.

## Verified closures retained from the first remediation

The delta review did not invalidate all prior work. These areas are structurally present and should be preserved:

- committed-mode missing/corrupt native projection falls closed rather than falling back to unscoped legacy preferences;
- WebDAV, Prowlarr, and IPTV borrowed-resource provenance/redaction paths have sentinel coverage (Stremio is the uncovered exception);
- strict secret scalar/list/field reads and raw migration inventory exist for the currently covered shapes;
- one-way commitment prevents a committed installation from silently treating legacy storage as authoritative;
- tvOS recovery uses transaction-specific shards, manifest-last visibility, length/hash validation, and orphan cleanup;
- single-profile restore excludes copied SQLite sidecars, replaces the DB family, and finalizes a manifest;
- cleanup ledger records work before graph deletion and retries physical cleanup;
- reset journal uses staged, retryable work and double-slot recovery;
- remote pairing/session cryptography, replay counters, scoped buffers, and lock-triggered revocation are present;
- PIN storage/KDF, constant-time verification, and throttling are present; the remaining PIN issue is authorization across awaited administration work;
- desktop secondary-launch retry/ack logic is present.

These closures do not offset a P0/P1. They reduce the remaining repair surface.

## Required remediation order

1. **Containment:** Keep both rollout flags off and add a CI assertion preventing release builds from enabling either flag.
2. **Close plaintext/cross-profile P0s:** Stremio provenance/redaction, resource capability revalidation, delayed Stremio commits, outbound remote send authority.
3. **Make native authority monotonic:** deny/tombstone or durable outbox, serialization/generation checks, failure/reordering tests in Dart and Kotlin.
4. **Close migration/data-loss paths:** final Admin job rebinding, IPTV dependency mapping, Android producer quiescence, graph manifest finalization, strict legacy schemas, recovery shell.
5. **Finish remote/policy semantics:** lease expiry order, chunk routing, dialog-time revoke, service-boundary policies, `download` permission masks.
6. **Close remaining async/privacy/reset gaps:** MDBList, profile/PIN administration, logging coverage, SAF drain ordering, bounded streaming decoder.
7. **Run the canonical last-release upgrade fixture and every supported-platform physical gate.** Do not enable migration based solely on synthetic/unit fixtures.

## Minimum regression matrix before another whole-plan review

The next review should start only after these tests exist and pass:

| Matrix | Mandatory cases |
|---|---|
| Secret isolation | Sentinel use/reveal/manage/download/writeRemote for every scalar and collection resource, especially Stremio |
| Async revocation | Switch, lock, profile disable/delete, feature revoke, grant revoke, resource rotate/delete, generation restore at every injected await/publication boundary |
| Native authority | Projection write failure, process death, concurrent reordered publications, old job execution, use-only download denial |
| Upgrade | Actual last non-profile release fixture with preferences, every credential family, DBs/files/engines, plugin/native jobs, alarms, schedules, interrupted migration |
| Restore | v1, encrypted v2, single-profile v3, deviceGraph v3, malformed record inventory, IPTV dependency rebinding, byte mutation before publication |
| Remote | Two physical peers, TTL expiry, replay, chunk threshold, revoke during dialog/encryption/send, mixed-field payload prevention |
| Recovery/reset | Missing/corrupt DB and WAL, recovery UI restore/reset, active SAF/native/plugin writers, process death and low storage |

## Supported-platform rollout gates

Source fixes and unit tests are necessary but do not replace these gates:

- **Android / Android TV:** real legacy native jobs and alarms; process death at each reseal/projection boundary; concurrent writer migration; use-only job denial; SAF reset; two-device remote; recording ownership/policy.
- **iOS:** actual backup manifest and cross-device restore; device-key lifecycle; kill during migration/restore/reset; deep-link/OAuth scoping.
- **tvOS:** physical cache eviction followed by Keychain reconstruction; termination around every shard/manifest boundary; Keychain size/performance; Top Shelf cold-launch/lock/switch; remote journey.
- **macOS:** native build plus crash/low-disk migration, restore, cleanup, recording/schedule drain, and secondary-launch race.
- **Windows:** native build; DPAPI lifecycle; reset double-slot kill matrix; single-instance forwarding; recording/schedule drain.
- **Linux:** native build; vault unlock/recovery; migration/restore/reset kill matrix; single-instance forwarding; recording/schedule drain.
- **All platforms:** large backup, low storage, corrupted persistence, canonical release-upgrade inventory reconciliation, and no cross-profile sentinel in UI/log/network/durable bytes.

If a platform cannot pass, exclude profiles from that platform's release packaging explicitly. Do not rely on an untested path or runtime accident.

## Re-review exit criteria

A final whole-plan review is warranted only after:

1. every DELTA-P0 and DELTA-P1 item has a source fix and named regression;
2. the 72 existing profile tests still pass and the adversarial matrix above is added;
3. `git diff --check`, the profile analyzer, Android Kotlin compile, available Apple builds/parses, and host platform builds are green;
4. canonical migration and backup fixtures reconcile every input record to an output/disposition;
5. physical-platform evidence is attached or the platform is explicitly excluded;
6. neither rollout flag is enabled before all required evidence is recorded.

Until then, another broad review would mostly rediscover known gaps. The efficient next step is a finding-by-finding remediation pass followed by targeted regression verification, then one final cross-cutting review.
