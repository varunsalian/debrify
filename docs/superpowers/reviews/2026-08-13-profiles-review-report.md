# Multi-Profile Implementation Review Report

**Date:** 2026-08-13
**Reviewed baseline:** `591ec0a008115b8fd4ffa7c7ed3ffad70d582e86` (`0.8.2_alpha`) plus the uncommitted multi-profile implementation
**Companion review plan:** [2026-08-13-profiles-review.md](../plans/2026-08-13-profiles-review.md)
**Supported platforms:** Android, Android TV, iOS, tvOS, macOS, Windows, and Linux. Web is not supported and is out of scope.
**Decision:** **NO-GO. Keep `DEBRIFY_PROFILES` and `DEBRIFY_PROFILES_MIGRATION_READY` disabled.**

> **Remediation update:** This report is the immutable first-pass finding
> record. The source corrections, regression evidence, and remaining physical
> platform gates are tracked in
> [2026-08-13-profiles-remediation.md](./2026-08-13-profiles-remediation.md).

## Executive decision

The implementation has a strong base—explicit profile scopes, generation-based restore publication, a resource/grant graph, encrypted profile packages, PIN throttling, startup ordering, desktop single-instance locking, and device-specific key storage—but it is not safe to enable yet.

The review confirmed:

- **3 P0 release blockers**: direct use-only credential disclosure/cloning, cross-profile credential writes from stale async completions, and unauthenticated LAN commands inheriting a device-global remote lease.
- **21 P1 release blockers**: migration data-loss/recovery gaps, native fail-open behavior, lifecycle split authority, durable-job revocation failures, Android TV policy/secret defects, restore atomicity gaps, reset/deletion recovery gaps, operation-boundary authorization omissions, and missing release-grade migration evidence.
- **5 P2 issues** that should be fixed before broad rollout or explicitly accepted with bounded follow-up.

Passing unit tests do not override these findings. Most current profile tests exercise primitives and happy paths; the missing cases are exactly the interruption, stale-completion, native, real legacy-fixture, and cross-profile sentinel cases required to prove the design.

## Review method and scope

The review followed the companion review plan and used four lanes:

1. Lead review: bootstrap ordering, profile publication, restore paths, pre-unlock handoffs, backup policy, and test closure.
2. Migration/durability reviewer: live upgrade, v1/v2/v3 backup compatibility, registry generations, deletion/reset recovery, tvOS recovery publication, and interruption behavior.
3. Isolation/authorization reviewer: credentials, policies, PINs, async work, remote control/transfer, logs, and cross-profile state.
4. Platform/native reviewer: Android/Android TV native readers and jobs, Apple/Top Shelf, desktop lifecycle, UI handoffs, and platform gates.

The review inspected the complete tracked diff and new profile trees. The unrelated untracked design artifacts under `design/` were excluded. No production code was changed during review.

### Severity contract

| Severity | Meaning | Release consequence |
|---|---|---|
| P0 | Confirmed credential/data disclosure, cross-profile write, or remotely exploitable authorization bypass | Stop rollout; fix first |
| P1 | Credible data-loss/leak path, fail-open behavior, broken recovery, or required platform/security gate | Blocks rollout |
| P2 | Important correctness, privacy, availability, or maintainability issue with narrower impact | Fix before broad rollout or explicitly time-bound |

## P0 findings

### PROF-P0-001 — Use-only shared collection credentials are revealed and can be cloned

**Platforms:** All
**Invariant:** `use` allows opaque service use; it never reveals or transfers ownership of a secret.

**Evidence**

- `profile_collection_resource_facade.dart:18-44` enumerates granted resources and obtains their full decrypted secret through `resolveSecretForUse`.
- `connection_resource_service.dart:203-218` requires only `ResourcePermission.use` before decrypting.
- `storage_service.dart:5594-5603`, `6174-6183`, and `7008-7017` expose full WebDAV, indexer, and IPTV models.
- The corresponding settings pages place those values into editable fields: `webdav_settings_page.dart:83-100,193-200`, `indexer_managers_settings_page.dart:409-418`, and `iptv_settings_page.dart:3154-3162,3331-3363`.
- The compatibility save paths can create borrower-owned resources from caller-supplied secrets: `storage_service.dart:5645-5657,6205-6227,7056-7077` and `connection_resource_service.dart:93-149`.
- Default Child grants are use-only, and Member grants omit reveal/manage, in `edit_profile_screen.dart:225-252`.

**Reproduction:** Share a WebDAV, indexer, or IPTV connection with a use-only Member/Child. Open its settings. The borrower receives the URL/username/password/API key in editable UI. A Member can save the returned model and mint a borrower-owned copy.

**Required correction:** Separate opaque execution capabilities from secret DTOs. Compatibility getters and ordinary settings screens must never receive cleartext for borrowed resources. Editing/reveal/cloning must require explicit reveal/manage permission and current authorization.

**Regression gate:** Sentinel-secret service and widget tests for every collection resource and role; verify use succeeds, reveal/edit/copy fails, and no cleartext reaches models, form controllers, logs, or backups.

### PROF-P0-002 — Delayed provider completions can write Profile A credentials/state into Profile B

**Platforms:** All
**Invariant:** Every async commit must remain bound to its initiating profile, generation, session epoch, policy revision, and resource authority.

**Evidence**

- MDBList validates over the network, then saves credentials and publishes account/cache state without a captured authorization: `mdblist_service.dart:93-120,132-181,230-314`.
- Real-Debrid, TorBox, Premiumize, and AllDebrid account services follow the same pattern: `account_service.dart:26-50`, `torbox_account_service.dart:24-54`, `premiumize_account_service.dart:24-54`, and `alldebrid_account_service.dart:23-53`.
- WebDAV tests a connection and then saves against whichever profile is current after the await: `webdav_settings_page.dart:128-161`.
- These UI paths invoke the long operation directly, for example `real_debrid_settings_page.dart:135-166`.
- Profile lifecycle cache reset omits the four debrid account singletons, and reset alone would not revoke an already-running completion: `profile_app_lifecycle_participant.dart:29-44`.

**Reproduction:** Begin Profile A credential validation against a delayed response, switch to B, then release the response. The post-await save captures B and can store A's credential in B; static account/list notifiers can expose A's state under B.

**Required correction:** Require a `ProfileAsyncAuthorization`-style captured capability for every provider/account/WebDAV async path and revalidate it immediately before each storage, resource, cache, and notifier mutation.

**Regression gate:** Inject delayed clients, then switch, lock, revoke, delete/disable, rotate a resource, or publish a generation before completion. No target-profile storage or process-global state may change.

### PROF-P0-003 — Remote command authority is not bound to an authenticated peer

**Platforms:** All platforms exposing remote control
**Invariant:** A command lease must bind authenticated peer/session, nonce/replay state, expiry, command class, local profile scope, and current authorization revision.

**Evidence**

- `profile_remote_lease.dart:13-27,38-58` stores only local profile/generation/epoch/revision/features. It has no peer identity, authenticated session, issue/expiry time, nonce, or command class.
- A sole unpinned profile is granted this lease automatically by `profile_gate.dart:105-123`.
- `remote_control_state.dart:632-645` identifies plaintext packets as unauthenticated, while `:793-814` requires session authorization only for config/addon commands—not navigation, media, or text.
- `remote_command_router.dart:300-349,384-402` checks the device-global local lease but does not bind navigation/text/media dispatch to the sending peer/session.

**Reproduction:** While a local profile is unlocked, send a plaintext LAN navigation, text, or media packet from an untrusted peer. It can inherit the current device-global lease; a `select` action can trigger the focused UI operation.

**Required correction:** Authenticate all state-changing remote commands. Issue short-lived peer/session-specific leases with replay protection and command scopes. Preserve device pairing across profile switches, but never reuse profile command authority across peers.

**Regression gate:** Deny plaintext and unauthorized-session commands; prove peer A's authority cannot be used by peer B; test expiry, replay, lock/switch/revision revocation, and reconnect.

## P1 findings

### PROF-P1-001 — Post-commit activation failure leaves registry/runtime/caches split

`profile_lifecycle.dart:66-80` commits the target and publishes its runtime before `didActivate`. If `NativeProfileProjection.publish` throws (`profile_app_lifecycle_participant.dart:51-54`), the activation journal is already cleared (`profile_registry.dart:721-747`). The catch aborts only a nonexistent journal and warms the previous profile without restoring registry/runtime authority.

**Impact:** Target B remains authoritative while process caches may contain A, creating both leakage and incorrect writes.
**Required correction/test:** Define explicit post-commit roll-forward or transactional rollback; failure-inject every participant before and after publication and restart at each boundary.

### PROF-P1-002 — Android committed-mode native readers fail open to legacy Admin state

`ProfilePreferenceProjection.kt:16-23` returns null for missing/corrupt committed projection; `:35-64` then assigns/authorizes `legacy-admin-v1`; `:67-110` falls back to unscoped legacy preferences/files. Native Stremio subtitles consume it at `StremioSubtitleService.kt:194-201`.

**Impact:** A Member can receive retained Admin addon/settings data, and missing/corrupt projections can reauthorize legacy-owned work.
**Required correction/test:** In committed mode, missing projection/key/authorization must deny or use a safe non-sensitive default—never legacy. Add Kotlin tests for omitted keys, corrupt projection, stale revisions, and every native consumer.

### PROF-P1-003 — Durable jobs do not carry and revalidate resource authority

Download enqueue lacks resource identity/revision (`download_service.dart:1885-1897,3343-3353`). Recording APIs accept resource fields, but production callers omit them (`live_recording_service.dart:424-463,596-645`; `iptv_results_view.dart:4494-4496,4639-4654`). Android validates only a profile revision from a projection with no resource graph; non-Android plugin callbacks primarily check owner (`download_service.dart:1575-1627`) and resume without full revision validation (`:1629-1630,1711-1773`). Resource rotation does not guarantee immediate native projection republish.

**Impact:** Revoked/rotated provider credentials can still be used by queued, retried, resumed, or scheduled jobs.
**Required correction/test:** Persist immutable owner/profile revision/resource ID/resource revision/feature for every job and validate at enqueue, start, resume, retry, alarm fire, callback, and artifact indexing.

### PROF-P1-004 — Android TV tee recording bypasses recording policy and ownership

`AndroidTvTorrentPlayerActivity.kt:6988-6999,6443-6446,6698-6733` exposes and starts the native tee recorder without checking profile recording authorization. `IptvRecordingController.kt:95-135` writes public MediaStore output without owner/job/artifact registration.

**Impact:** A denied Member/Child can create a public recording with no auditable owner.
**Required correction/test:** Route native recording through the same profile authorization/job registration contract as Flutter; add native denial and ownership tests.

### PROF-P1-005 — Android TV guide scheduling stores credential-bearing URLs in plaintext

`AndroidTvTorrentPlayerActivity.kt:6919-6932` schedules plaintext URL/headers with no resource linkage. `RecordingScheduleStore.kt:126-142` serializes them when no sealed payload is supplied. Xtream URLs embed username/password (`AndroidTvTorrentPlayerActivity.kt:6608-6622`). The Flutter/MainActivity path correctly seals its payload (`MainActivity.kt:1706-1727`).

**Impact:** Xtream credentials can remain in the native schedule store.
**Required correction/test:** Require sealed execution payloads and resource references from every schedule producer; assert persisted URL/headers are absent in committed profile mode.

### PROF-P1-006 — Pre-unlock startup/Top Shelf payloads can cross into another profile

IPTV startup resolution reads the last-active profile before `ProfileGate` (`main.dart:232-348,407-420`) and stores an unscoped process-static payload (`main_page_bridge.dart:408-445`). Selecting B does not clear/recompute it; B chooses/consumes the IPTV route (`main.dart:890-895`, `iptv_results_view.dart:3387-3418`).

The same bridge has other unscoped pending content: catalog details, MDBList lists, Debrify/Stremio TV channels, Continue Watching, and advanced-search autoplay (`main_page_bridge.dart:131-178,367-391,453-495`). They are not comprehensively cleared by `profile_app_lifecycle_participant.dart:29-45`.

On tvOS, `TvosTopShelfService.initialize` runs before `ProfileGate`. During that window, `ProfileLockController.lockedProfileId` is still null, so an action for last-active A can be accepted into `pendingCatalogDetailOpen` by `tvos_top_shelf_service.dart:441-480`; the initial locked branch in `profile_gate.dart:105-128` does not clear that bridge payload.

**Impact:** B can display or autoplay A's content metadata/channel after a cold-launch profile choice.
**Required correction/test:** Bind every pending payload to profile/generation/epoch/revision and validate on consumption, or quarantine all payloads until local unlock; test every handoff across cold start, switch, lock, delete, and restore.

### PROF-P1-007 — Stale `ProfilePreferences` protection vanishes in release builds

The current-session check is entirely inside `assert` at `profile_preferences.dart:58-69`; `_assertWritable` depends on it at `:72-78`. Assertions are removed in release builds.

**Impact:** A retained A wrapper can read/write A's prefix while B is active.
**Required correction/test:** Use an unconditional runtime check for ordinary session-bound handles and add release-equivalent tests for every read/write/remove/clear API after profile/generation/epoch change.

### PROF-P1-008 — Legacy migration can silently commit missing/undecryptable credentials

`secret_vault.dart:64-81` maps every decryption failure to null. Migration removes null/empty secret fields and skips empty resources (`profile_migration_service.dart:149-150,189-196`); malformed list entries can also disappear (`secret_vault.dart:118-143`). Verification (`profile_migration_service.dart:520-548`) does not reconcile raw present credential records against created resources.

**Impact:** Migration can commit profile mode with the user's existing provider/account missing, with no explicit recovery state.
**Required correction/test:** Inventory raw credential presence as absent/valid/unreadable; any present-but-unreadable source blocks publication. Verify a destination/disposition for every scalar/list/blob credential.

### PROF-P1-009 — Missing registry can revert a committed install to stale legacy authority

`profile_bootstrap.dart:62-67` treats only a physical registry file or tvOS recovery snapshot as authority and enters legacy mode when neither exists. The persistent commitment mirror written at `:292-296` is not consulted for this decision.

**Impact:** After registry loss/corruption, retained legacy settings can become authoritative again or be remigrated over newer profile-only state.
**Required correction/test:** Honor a separate one-way commitment/recovery marker. A committed marker plus missing/corrupt registry must enter explicit recovery, never legacy. Test missing DB, zero-byte DB, WAL loss, corruption, and both flag states.

### PROF-P1-010 — Existing-install detection examines only legacy preferences

`profile_bootstrap.dart:124-127` decides fresh versus existing from filtered `SharedPreferences` keys only. It does not inventory legacy databases, private files, engine configuration, native job stores, or credentials as independent authorities.

**Impact:** An install whose preferences were cleared/corrupted but whose DB/files/native state remain can be classified as fresh, leaving existing data outside the Admin migration.
**Required correction/test:** Add a preflight persistence inventory/sentinel across every legacy authority and fixture cases where each source is the only remaining source.

### PROF-P1-011 — Interrupted tvOS recovery publication cannot be retried

`tvos/Runner/AppDelegate.swift:140-150` derives the next shard namespace only from the published manifest. Shards are immutable inserts at `:234-245`; the manifest is published later at `:167-170`. If the process dies after a new shard but before the manifest, retry selects the same generation and hits `errSecDuplicateItem`.

**Impact:** The old snapshot remains readable, but all later authoritative recovery checkpoints can be permanently blocked until destructive clearing.
**Required correction/test:** Use unique transaction namespaces or validate/reuse/delete unpublished shards. Failure-inject every shard/manifest boundary and run physical Apple TV eviction/reconstruction tests.

### PROF-P1-012 — Restore publishes contents different from the generation it verified

`profile_data_generation.dart:187-231` clones files including SQLite WAL/SHM sidecars and records a verified manifest before restore overlays (`:141-147`, `profile_registry.dart:2051-2077`). The coordinator mutates databases/files afterward (`profile_restore_coordinator.dart:417-425`). `profile_database_snapshot.dart:116-136` replaces only the main DB, leaving cloned sidecars. Publication checks only the earlier nonempty manifest hash (`profile_registry.dart:2131-2140`).

**Impact:** A published DB can have stale WAL/SHM state or corruption introduced after verification; the visible bytes are not the verified bytes.
**Required correction/test:** Snapshot SQLite consistently, exclude sidecars from generic copies, replace the whole DB family, and compute/verify the final manifest after all overlays immediately before publication.

### PROF-P1-013 — Partial v1/v2 restore can become visible and be reported as success

`profile_restore_coordinator.dart:479-505` calls `BackupRestoreService.applyBackup` for legacy follow-up categories. That service catches per-category/entry failures and returns a `RestoreReport`; the coordinator does not reject `errors`/failures before publication at `:518-545`. Settings success UI ignores `legacyFollowUp` errors (`settings_screen.dart:3267-3272`). `legacy_backup_adapter.dart:79-151` also silently skips malformed collection entries.

**Impact:** Search engines, IPTV favorites/lists, or other legacy categories can partially restore, become authoritative, and still produce a success message.
**Required correction/test:** Convert every legacy field into a bounded staged model with explicit omission/error records. Fail publication on unaccepted partial results, or require a preview/acceptance contract and truthful final report.

### PROF-P1-014 — Profile deletion/restore recovery can lose cleanup authority

Normal UI deletion removes registry state before physical data (`manage_profiles_screen.dart:172-184`). Interrupted-restore recovery deletes staging profile/journal state before bootstrap deletes its generation (`profile_registry.dart:2252-2291`; `profile_bootstrap.dart:85-90`). A crash in between leaves no durable record identifying cleanup work.

**Impact:** Private preferences, DBs, and files can remain orphaned indefinitely; the UI may report failure even though graph deletion is irreversible.
**Required correction/test:** Persist a deletion/GC tombstone containing profile/generation paths until idempotent physical cleanup completes. Test process death and filesystem failure at every deletion boundary.

### PROF-P1-015 — Device reset marks work drained after stop failures

`profile_device_reset_service.dart:94-103` swallows remote and desktop recording/schedule shutdown failures; the caller unconditionally advances the journal to `workDrained` at `:75-81` and starts deleting private state.

**Impact:** A writer or remote session can remain alive while stores, credentials, and ownership metadata are destroyed.
**Required correction/test:** Journal per-subsystem drain status and retry failures. Never advance while any writer is unconfirmed. Inject failures for all download/recording/schedule/remote backends.

### PROF-P1-016 — Device reset leaves retained legacy engine files

Migration copies legacy `documents/engines` (`profile_migration_service.dart:483-517`), but reset deletes scoped `profiles/` trees and selected legacy DBs only (`profile_device_reset_service.dart:123-145`).

**Impact:** Private/custom engine configuration survives a factory-style device reset.
**Required correction/test:** Put every retained migration source in the reset ledger and verify sentinel removal across platform storage roots.

### PROF-P1-017 — Windows reset journal has a crash window with no valid journal

`profile_device_reset_service.dart:187-202` writes `.next`, deletes the current journal on Windows, then renames `.next`; `_readJournal` at `:175-184` recognizes only the final path.

**Impact:** A process death between delete and rename can make startup mount an incompletely reset registry/state.
**Required correction/test:** Use Windows atomic replacement or a validated double-slot generation journal; recover every target/`.next` combination.

### PROF-P1-018 — Feature policy is missing at direct operation boundaries

Settings routes open provider, WebDAV, indexer, IPTV, and remote screens without consistent feature gates (`settings_screen.dart:2725-2795,2867-2914,2926-2983`). Remote discovery/listen/connect can start directly (`remote_control_state.dart:192-254,279-313,394-450`). Collection replacement checks `manageConnections` but not the resource feature (`connection_resource_service.dart:93-104`).

**Impact:** A disabled `remoteControl`, `cloud`, `iptv`, or `torrentSearch` policy can be bypassed through direct routes, already-open screens, or service calls.
**Required correction/test:** Enforce policy and captured revision in each service operation, with route/UI checks only as defense in depth; test direct calls and mid-screen revocation.

### PROF-P1-019 — Single-profile export omits the backup/restore policy boundary

`profile_package_service.dart:21-107` validates identity/scope but does not require `ProfileFeature.backupRestore`. With `includeSecrets=false`, no resource reveal check supplies that missing authorization. The Settings UI checks policy, but the service boundary does not.

**Impact:** A policy-disabled profile can export its preferences, DB snapshot, and files through another caller; long export work is also not revalidated immediately before return.
**Required correction/test:** Require backup permission at the service boundary and use a captured capability/final validation for all export modes.

### PROF-P1-020 — Sensitive logs and raw errors fall outside redaction coverage

`udp_command_service.dart:84-89` includes the first 80 payload bytes in `RemoteCommand.toString`, logged at `:207,260,348`; plaintext receive is logged before authorization (`remote_control_state.dart:632-635`). Provider identifiers are logged by TorBox/Premiumize/AllDebrid account services. WebDAV exposes raw exception text (`webdav_settings_page.dart:158-161`). Top Shelf logs raw platform errors (`tvos_top_shelf_service.dart:63-66,284-287`). These files are absent from the current redaction source guard.

**Impact:** Credential prefixes, emails/usernames, private endpoints, content metadata, or transport details can reach logs/UI.
**Required correction/test:** Remove payload-bearing stringification, map errors to privacy-safe codes, capture logs/UI with sentinel secrets, and extend the guard to all transports/account/native-entry services.

### PROF-P1-021 — Migration/restore evidence required for rollout does not exist

There are no dedicated `profile_migration_service_test.dart`, `profile_bootstrap_test.dart`, or `profile_restore_coordinator_test.dart` suites. Current v1/v2 tests prove a small handcrafted adapter/decryption case but do not run a genuine last-release fixture through destination publication and compare the complete before/after inventory. There is no exhaustive fault injection for migration, activation, reset, restore, tvOS shard publication, or native jobs.

**Impact:** Even after the code defects above are fixed, safe upgrade from the non-profile app is not demonstrated.
**Required correction/test:** Build canonical legacy fixtures for every persistence/resource family, real v1 and encrypted-v2 backups, before/after redacted inventories, and deterministic failures at each durable boundary on every supported platform.

## P2 findings

### PROF-P2-001 — Candidate warming mutates global state before authority publication

Candidate work runs while A remains authoritative (`profile_lifecycle.dart:51-69`) but `_warm` mutates process-global controllers/caches (`profile_app_lifecycle_participant.dart:67-104`), including theme/text/Discover notifiers. The `switching` notifier has no production access barrier.

**Action:** Warm into private candidate containers followed by one atomic swap, or quiesce all consumers until publication. Add barrier tests that query global state mid-warm.

### PROF-P2-002 — Retired generations have no bounded garbage collector

Publication marks old generations retired (`profile_registry.dart:2184-2189`), while cleanup removes only the restore journal (`:2298-2304`). Bootstrap deletes abandoned staging generations, not retired ones.

**Action:** Add restart-safe delayed GC with reference/rollback checks and a defined retention window; test repeated restores and tvOS recovery-envelope growth.

### PROF-P2-003 — Desktop secondary-launch forwarding can lose startup events

The primary acquires its lock before publishing the socket endpoint (`desktop_single_instance.dart:46-80`). A secondary forwards once; missing endpoint/connect errors are swallowed (`:118-151`) and `main.dart:182-186` exits.

**Action:** Add bounded retry/acknowledgement or a durable inbox; test simultaneous launch, stale endpoint, primary crash, and exactly-once forwarding.

### PROF-P2-004 — Local restore buffers the whole file before size validation

`settings_screen.dart:3151-3164` asks FilePicker for `withData: true`, so the file is allocated before its declared-size/tree limits can reject it.

**Action:** Open a stream/path, enforce compressed/envelope limits before allocation, then decode through the existing bounded package parser.

### PROF-P2-005 — Source guards are broad allowlists and miss critical services

`profile_source_guard_test.dart` permits raw `SharedPreferences` in entire large files and checks a limited log-file list. It would not catch several findings above or future unscoped accesses in an allowlisted file.

**Action:** Replace whole-file exemptions with exact adapter/key/callsite rules and cover all native projections, transports, account services, pending bridges, backup/remote decoders, and operation-boundary APIs.

## Verified foundations

The following areas were reviewed and found structurally sound within the inspected scope. They do not negate the blockers above.

- Both rollout flags are compile-time opt-in and default to false.
- When a valid committed registry exists, disabling the flags does not intentionally revert it to legacy mode.
- Bootstrap is placed before profile-sensitive Dart preference/cache warming, and desktop single-instance locking occurs before bootstrap/store opening.
- Migration uses an exclusive lock, retains legacy source data, and its ordinary resource/profile insertions are designed to be retryable.
- Legacy SQLite copy logic checkpoints, integrity-checks, hashes, and validates the copied destination.
- Resource secrets use authenticated encryption with owner/type/resource-bound associated data; direct `revealSecret` rejects use-only borrowers.
- Grant/revoke/secret updates increment affected profile authorization revisions.
- PIN records have all-or-none DB constraints, Argon2id hashing, constant-time comparison, persistent exponential throttling, and Admin-authorized reset. No concrete PIN bypass was found.
- V3 sensitive packages require authenticated encryption and enforce bounded KDF/tree/attachment constraints; sanitized packages validate required omissions.
- Single-profile restore keeps the staged generation invisible and publishes resource rows plus the visible-generation pointer in one registry transaction. The blocker is that final physical contents are not re-verified and legacy follow-up errors are not authoritative failures.
- Chunked remote transfers bind the receive buffer to a peer/session, enforce declared sizes/counts and final authenticated content, and reject replay counters. This does not fix live-command lease binding.
- Android automatic backup/device-transfer XML excludes app-private preference/database/file/root domains and is referenced from the manifest.
- Apple resource keys are device-only Keychain items; Android uses Keystore and Windows uses DPAPI.
- Top Shelf snapshots/actions carry owner/revision and multi-profile personalization defaults off. The remaining defect is cold-start lock initialization and the unscoped bridge handoff.

## Validation evidence

| Check | Result |
|---|---|
| `git diff --check` | Passed |
| `flutter test test/profiles` | 57 tests passed |
| Backup/package/database focused bundle | 19 tests passed |
| Isolation focused bundle | 24 tests passed |
| Lifecycle/job/source-guard focused bundle | 7 tests passed |
| `flutter analyze lib/services/profiles lib/models/profiles lib/screens/profiles test/profiles` | No issues |
| Full `flutter analyze` | Not clean: 2,156 existing workspace/package issues, including errors in vendored `packages/media_kit_video_tvos`; not a useful profile-specific pass |
| Baseline full Flutter test suite at HEAD | `+2897 -9`; nine known baseline failures (seven series parser, one XMLTV legacy retention, one widget pending-timer) |
| Current full suite after profile implementation | Not rerun in this review; focused suites passed but cannot close release gates |
| Physical Apple TV Keychain/eviction/recovery | Not run; blocking |
| Android TV policy/native job/security journeys | Not run; blocking |
| iOS physical key/backup/callback journeys | Not run; blocking |
| Windows/Linux native builds and crash recovery | Not run on this macOS host; blocking |
| Android/iOS/tvOS/macOS builds | Previously reported during implementation, not independently counted as review sign-off |

Dependency lock SHA-256 captured during review: `5250dc584e3377a936182a373397f2e2a8ea9476da1d9e564e841078ffa76e39`.

## Required remediation order

1. **Contain P0 exposure first:** opaque resource-use API, async captured authorization everywhere, authenticated peer-bound remote commands.
2. **Fix authority transitions:** release-mode stale-handle checks, activation post-commit semantics, pending handoff scoping, and Android native fail-closed projection.
3. **Make migration provable:** full persistence preflight, credential reconciliation, one-way commitment recovery, genuine old-install fixtures, and interruption tests.
4. **Make restore/deletion/reset durable:** final-byte manifests and SQLite-family handling, strict legacy partial-result policy, durable GC/deletion tombstones, reset drains, Windows journal, and retained-source cleanup.
5. **Close native/background contracts:** resource-bound jobs, Android TV recording policy, sealed schedule execution, projection refresh/revision handling.
6. **Enforce policy/privacy at services:** settings/remote/export boundaries and complete log/error redaction.
7. **Run one delta review**, focused only on changed invariants and all P0/P1 regression tests.
8. **Run one final full checkpoint:** current full test suite, analyzer baseline comparison, supported-platform builds, and physical-device/manual matrix. Do not repeat a whole architecture review unless an authority/schema/encryption/publication contract changes.

## Go/no-go matrix

| Gate | Status | Reason |
|---|---|---|
| Migration sign-off | **Blocked** | Silent credential loss, incomplete install detection, registry-loss fallback, no genuine full fixtures/fault matrix |
| Isolation sign-off | **Blocked** | Three P0 paths plus release-only stale-handle and pending-payload leaks |
| Durability sign-off | **Blocked** | tvOS retry failure, restore verification order/sidecars, cleanup/reset journal gaps |
| Backup/restore sign-off | **Blocked** | Legacy partial success, missing end-to-end v1/v2 fixtures, service-boundary export gap |
| Remote sign-off | **Blocked** | Live commands inherit a non-peer-bound global lease; focused transfer buffer itself is sound |
| Android / Android TV | **Blocked** | Fail-open projection, native job/revision gaps, recording bypass, plaintext schedule secret |
| iOS | **Blocked** | Physical key/backup/callback journeys not run |
| tvOS | **Blocked** | Retryable recovery publication defect and physical eviction/recovery gate not run |
| macOS | **Blocked** | Full platform/manual and crash-recovery matrix not independently run |
| Windows | **Blocked** | Reset journal defect and host build/manual matrix not run |
| Linux | **Blocked** | Host build/manual/vault recovery matrix not run |

## Final rule

Do not enable profile migration or ship a build that can commit profile mode until every P0/P1 finding is fixed with the stated regression coverage and all seven supported-platform gates are either passed or explicitly excluded from that release. Existing users must continue on legacy authority while both flags remain disabled; once a future build commits migration, it must remain one-way and fail closed into recovery rather than expose stale legacy data.
