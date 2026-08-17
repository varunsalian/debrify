# Multi-Profile Review Remediation Record

> **Final remediation update:** The focused
> [Multi-Profile Remediation Delta Review](./2026-08-13-profiles-delta-review.md)
> found 23 additional source issues after the first pass. All 23 now have
> source remediations and named automated or compile evidence below. The
> current decision remains **NO-GO** because physical-device, real-upgrade,
> crash, eviction, and unavailable-host gates have not run. Both rollout flags
> remain disabled.

**Date:** 2026-08-13
**Finding source:** [Multi-Profile Implementation Review Report](./2026-08-13-profiles-review-report.md)
**Supported platforms:** Android, Android TV, iOS, tvOS, macOS, Windows, and Linux. Web is not supported.
**Code status:** All 29 original findings and all 23 delta findings have a remediation in the uncommitted working tree. Profile-specific automated checks pass; the repository-wide suite matches its nine-failure baseline exactly.
**Release status:** **Code-complete and enabled for owner testing, but public rollout remains blocked.** `DEBRIFY_PROFILES` and `DEBRIFY_PROFILES_MIGRATION_READY` now default on so the device matrix below can be exercised. They must not be treated as publicly released until those gates pass.

This record closes the review finding-by-finding. “Automated” means exercised on the current macOS host. “Source verified” means the platform implementation compiles or parses where its toolchain is available, but it is not a substitute for the required kill, eviction, low-storage, backup, or device journey.

## Remediation summary

| Finding | Remediation | Evidence status |
|---|---|---|
| PROF-P0-001 | Borrowed collection connections now expose redacted settings models. Decryption for actual use remains inside `ProfileCollectionResourceFacade`; reveal, management, cloning, and remote export are separate permissions. Remote export requires `writeRemote`. | Automated sentinel tests cover WebDAV, Prowlarr, IPTV M3U, Member, and Child. |
| PROF-P0-002 | `ProfileAsyncAuthorization` captures profile, generation, session epoch, policy revision, and optional resource authority. Provider/account, WebDAV, tracker, playlist, and credential mutation paths revalidate immediately before every storage/notifier/cache publication. | Automated switch/revision revocation tests plus source guard. |
| PROF-P0-003 | Remote commands require an authenticated encrypted peer/session. Profile leases are peer/session-bound with TTL; transport counters reject replay; lock, switch, deletion, and revision changes revoke authority. Plaintext state-changing commands are denied. | Automated lease, replay/buffer, and outbound-policy tests. Physical multi-device journey pending. |
| PROF-P1-001 | Activation now commits authority before warming process-global state. A pre-commit failure restores the old scope; a post-commit failure rolls forward to the committed target and never warms the previous profile under target authority. | Automated pre/post-publication lifecycle failure tests. |
| PROF-P1-002 | Android `ProfilePreferenceProjection` distinguishes legacy from committed mode. Missing, corrupt, stale, disabled, unauthorized, or omitted committed projection data fails closed; no committed reader falls back to unscoped Admin preferences. | Android Kotlin compile passed; device journey pending. |
| PROF-P1-003 | Durable downloads, recordings, and schedules capture owner, required feature, profile revision, resource ID, and resource revision. Enqueue, resume, retry, alarm fire, callback, and artifact indexing revalidate them. Native projection includes the authorization/resource graph. Legacy Android jobs are strictly parsed, rebound to migrated Admin, re-sealed with new AAD, durably committed, and retried idempotently before projection publication. | Dart job tests and Android Kotlin compile passed; process-kill/device journeys pending. |
| PROF-P1-004 | Android TV tee recording is unavailable in committed mode; all committed recording goes through the authorized, owner-tagged native recording path. | Android Kotlin compile passed; Android TV denial/ownership journey pending. |
| PROF-P1-005 | Every committed Android schedule requires a sealed execution payload. Android TV producers seal URL/headers and capture owner/resource revisions; the store rejects plaintext committed schedules. Legacy schedules are re-sealed during migration. | Android Kotlin compile passed; on-device store inspection pending. |
| PROF-P1-006 | Pending startup, deep-link, Top Shelf, IPTV, autoplay, and external handoffs are sealed and scoped to profile/generation/session/revision. The bridge is cleared/recomputed at lock/switch and consumption revalidates authority. | Automated pending-action tests and source guard; cold-launch platform journeys pending. |
| PROF-P1-007 | `ProfilePreferences` performs unconditional runtime validation for all reads and writes. A stale handle throws in release builds instead of relying on assertions. | Automated stale profile/generation/epoch tests. |
| PROF-P1-008 | Migration inventories raw legacy credential presence before lossy decoding. Present-but-unreadable scalar, list, or collection records block commit; verification reconciles every expected source with a destination/disposition. | Automated populated and corrupt-credential migration fixtures. |
| PROF-P1-009 | A device-scoped one-way commitment marker is consulted before legacy fallback. A committed installation with a missing/corrupt registry enters recovery. tvOS requires its device-only Keychain recovery authority. | Automated bootstrap recovery cases. |
| PROF-P1-010 | Existing-install preflight covers preferences, credential records, SQLite families, private files, engines, and native Android jobs rather than using preference keys alone. Database-only installs migrate to Admin. | Automated full and DB-only legacy fixtures; Android native detection compiles. |
| PROF-P1-011 | tvOS Keychain checkpoints use unique transaction shard namespaces. The manifest remains the sole visibility point; successful publication verifies the new envelope and removes every unreferenced generation, including shards orphaned by interruption. | Swift syntax parse passed; physical Apple TV interruption/eviction gate pending. |
| PROF-P1-012 | Restore removes complete destination SQLite families, avoids cloning live WAL/SHM sidecars, applies all overlays first, then computes and verifies the final manifest immediately before publication. | Automated database snapshot and restore-coordinator tests. |
| PROF-P1-013 | Legacy v1/v2 adaptation records malformed/omitted input and the coordinator rejects any unaccepted partial restore before publication. UI reports the authoritative result. | Automated v1, encrypted-v2, v3, partial-failure, and coordinator tests. |
| PROF-P1-014 | `ProfileCleanupLedger` preserves profile IDs/generations outside registry deletion. Normal deletion and restore failure retain cleanup authority until idempotent physical deletion completes. Graph recovery also retains staged IDs if the staging row was already lost. | Automated ledger/recovery tests, including the former row-loss crash boundary. |
| PROF-P1-015 | Device reset journals each writer drain independently and advances only after remote, desktop, Android recording/schedule, download, and directory-grant work is confirmed stopped. Failures remain retryable after restart. | Automated journal logic and platform-specific source validation; physical forced-stop matrix pending. |
| PROF-P1-016 | Device reset explicitly deletes retained legacy engines and every inventoried profile/private source after writers drain. Public completed media is intentionally preserved. | Automated/source verified. |
| PROF-P1-017 | Reset journal uses two validated generation slots and selects the newest valid record, so Windows never needs a delete-then-rename authority gap. | Automated journal recovery cases; Windows kill test pending. |
| PROF-P1-018 | `ProfilePolicyGuard` is enforced at service boundaries for cloud, IPTV, search, recording, remote control/transfer, connection mutation, and settings operations. UI visibility is defense in depth, not the authority. | Automated policy and remote outbound tests plus source guard. |
| PROF-P1-019 | Profile package export requires `backupRestore`, captured authorization, and final revalidation. Secret inclusion separately requires current resource permission. | Automated package-policy/encryption tests. |
| PROF-P1-020 | Remote payload-bearing stringification, provider identifiers, private endpoints, and raw transport/platform errors were removed or mapped to privacy-safe messages. The redaction guard covers account, transport, Top Shelf, handoff, and collection paths. | Automated sentinel/source-guard tests. |
| PROF-P1-021 | Dedicated bootstrap, migration, lifecycle, registry, database snapshot, restore coordinator, resource, PIN, remote, job, package, pending-action, and source-guard suites now exist. Realistic synthetic legacy inventories exercise non-profile-to-Admin and v1/v2/v3 restore paths. | 111 profile/remote security tests pass. Full physical fault matrix remains a rollout gate. |
| PROF-P2-001 | Candidate initialization happens only after registry/runtime target publication. Switch consumers are quiesced and rollback always uses the currently authoritative scope. | Automated lifecycle barrier/failure tests. |
| PROF-P2-002 | Startup GC retires generations for a seven-day recovery window, checks live references, records cleanup durably, and removes data/rows idempotently. | Automated registry/generation tests. |
| PROF-P2-003 | Desktop secondary launches use bounded endpoint discovery/retry plus acknowledgement instead of a one-shot send-and-exit path. | macOS build/source verified; Windows/Linux host runs pending. |
| PROF-P2-004 | Restore selection is path/stream based. File and envelope size limits are checked before reading/allocating the full package. | Automated bounded package parser tests. |
| PROF-P2-005 | Source guards use exact key/callsite adapters and cover native projections, credentials, account services, transports, pending bridges, backup/remote decoders, and operation boundaries. | Automated source guard passes. |

## Delta-review closure

| Finding | Remediation | Evidence |
|---|---|---|
| DELTA-P0-001 | Stremio addons preserve resource provenance and read-only state through serialization/copying. Borrowers receive redacted settings, borrowed records are skipped on save, and remote export requires `writeRemote`. | Stremio Member/Child sentinel and collection-facade tests. |
| DELTA-P0-002 | Resource operations carry captured profile/session/resource authority through awaited crypto and revalidate before plaintext return or transactional mutation. | Delayed cipher switch/revoke/rotation tests. |
| DELTA-P0-003 | Stremio add/refresh/save uses the initiating capability and captured collection instead of recapturing the current profile after HTTP awaits. | Delayed manifest A-to-B isolation tests. |
| DELTA-P0-004 | Remote credential reads return a resource-bound capability; multi-field payloads are captured together and revalidated immediately before the synchronous socket send. | Revocation-during-sealing test asserts zero sends. |
| DELTA-P0-005 | Native publication is serialized and monotonic, invalidates to a denied tombstone before mutation, and native readers reject stale publication sequences. | Publication failure and reordered-build tests; Android debug APK build. |
| DELTA-P1-001 | Job authorization requires the explicit `download` permission, and the native projection includes permission masks. | Dart use-only denial tests; Kotlin included in Android build. |
| DELTA-P1-002 | Lease expiry is checked before renewal; an expired peer/session remains tombstoned until explicit local authorization. | Injectable-clock TTL tests. |
| DELTA-P1-003 | Authenticated chunk envelopes now reach the production admission/router path while payload bytes remain encrypted, session-bound, and replay-checked. | Exact 6 KB production-route integration with reorder, duplicate, and replay. |
| DELTA-P1-004 | Remote confirmation repeats peer/session lease, active-profile, generation, revision, and `remoteTransfer` checks before restore staging. | Confirmation-boundary authorization tests/source guard. |
| DELTA-P1-005 | Torrent search and Stremio cached/network reads enforce service-boundary policy before returning data. | Policy revocation tests and structural guard. |
| DELTA-P1-006 | MDBList reads, mutations, and composite clone operations carry the same resource ID/revision capability through final publication. | Resource-rotation revocation regression. |
| DELTA-P1-007 | Privacy logging is installed process-wide and the guard scans profile, settings, networking, download, and remote sources for unsafe logging. | Sentinel log-sanitization and source-guard tests. |
| DELTA-P1-008 | Committed profile and PIN mutations require a live Admin profile/revision/session capability inside the write transaction. PIN verification, failure accounting, corruption repair, and KDF upgrades are conditional on the exact observed PIN record. | Switch-away/back stale-Admin, actorless-write denial, stale-PIN replacement, and PIN reset tests. |
| DELTA-P1-009 | Legacy IPTV provider IDs are mapped to staged destination resource IDs before Favorites/custom lists are applied. | v1/v2 relationship fixture verifies destination IDs. |
| DELTA-P1-010 | Legacy queued/paused downloads and desktop schedules are sealed and rebound to the final migrated Admin/resource revisions. | Migration fixtures inspect ciphertext and final revisions. |
| DELTA-P1-011 | Android native migration uses a global writer gate; late worker/alarm writes must validate the committed generation/authority before persistence, and the completion marker is last. | Android debug APK build; physical latch/process-death gate remains. |
| DELTA-P1-012 | Pre-`runApp` bootstrap failures enter a privacy-safe recovery shell offering bounded backup restore, Recovery Admin, remote restore, and explicit reset. | Bootstrap missing/corrupt authority tests; recovery screen source/build verification. |
| DELTA-P1-013 | Reset drains downloads and recording/schedule writers before releasing Android SAF grants or deleting partials. | Journal/source verification; active-SAF device gate remains. |
| DELTA-P1-014 | Every imported graph profile is finalized and re-verified against a nonempty preferences/database/file manifest before graph publication. | Positive manifest and byte-mutation rejection tests. |
| DELTA-P1-015 | Legacy schemas validate every known field and reject malformed known records; unknown top-level fields are ignored for forward compatibility. Inventory reconciliation still requires a disposition for every present supported item. | Malformed scalar/collection fixtures plus unknown-top-level compatibility coverage. |
| DELTA-P1-016 | iOS reapplies backup exclusion to profile support and preferences paths at launch and when the app becomes active. | iOS simulator build; physical backup-manifest/cross-device gate remains. |
| DELTA-P2-001 | Generation GC is age-authoritative and retains every young retired generation regardless of count. | Multi-generation retention tests. |
| DELTA-P2-002 | Local and provider-backed imports use bounded incremental reads instead of a size-check followed by whole-file allocation. | Oversize/growing-stream package tests. |

## Migration and compatibility closure

The current user's data is migrated into `legacy-admin-v1`; a fresh opted-in install uses `profile-initial-admin-v1`. Migration remains disabled unless both rollout flags are explicitly enabled.

The migration state machine now provides these guarantees:

1. An exclusive migration lock and raw persistence inventory are obtained before staging.
2. Preferences, every credential/resource family, SQLite databases, private files, engines, and native job authorities are copied/rebound into the Admin authority.
3. Present but unreadable credentials, malformed collection entries, corrupt databases, failed file copies, failed native job re-sealing, or an incomplete inventory stop publication.
4. Destination contents and the resource graph are verified before the registry commit.
5. Legacy sources remain intact after success for rollback diagnostics, but the one-way commitment marker prevents them from becoming authoritative again.
6. Android native legacy tasks/schedules migrate before the committed native projection appears. Parsing is strict and replacements use synchronous durable commits; the completion marker is written last.
7. tvOS treats the device-only Keychain recovery envelope as durable authority and its writable SQLite/files as reconstructible cache state.

Backups follow one restore coordinator:

- Non-profile v1 maps through `LegacyBackupAdapter` into a staged profile package.
- Encrypted v2 decrypts to the same legacy model, then follows that path.
- Profile-native v3 supports sanitized or authenticated-encrypted secret-bearing packages.
- All formats stage into a shadow generation/resource graph, validate bounded input and final physical contents, and publish once. Errors leave the previous generation visible and preserve cleanup authority.
- Backup/restore does not move device identity, remote pairing identity, PIN material, active sessions, native security grants, or public completed media.

## Remote behavior after profiles

Remote pairing remains device-scoped so users do not re-pair on every profile switch. Pairing alone grants no profile authority.

- The locally unlocked profile grants a short-lived lease only to the authenticated peer/session.
- Current-version commands are encrypted, session-bound, replay-checked,
  feature-checked, and validated against current
  profile/generation/session/revision. With profiles disabled, legacy peers
  retain plaintext navigation/media/text compatibility; credential-bearing
  legacy input remains source-bound behind explicit local consent. Committed
  profile mode admits no plaintext command.
- Lock, profile switch, disable/delete, restore publication, policy change, or resource revision invalidates outstanding authority.
- Remote config/addon transfer additionally requires `remoteTransfer`; each credential/resource is re-read immediately before sending and must have `writeRemote` permission.
- Receive buffers bind one peer/session/profile and are replaced rather than inherited across a switch.
- A live profile lease follows the same authenticated peer across transport
  session rotation; an expired lease cannot self-renew. Chunk packets are
  exempt from the per-peer interactive-command budget.
- A remote can control the selected unlocked profile, but cannot select a profile or submit/bypass a PIN.

## Release-readiness follow-up

The independent flags-off/cross-version review was remediated after this
record's original verification pass:

- ordinary remote entry now pairs v2 peers and re-handshakes after idle expiry
  or receiver restart; v1 navigation remains compatible;
- legacy task stores do not depend on Android Keystore while profiles are off,
  scan-only recordings remain visible, terminal task ghosts are forgotten,
  and native URL metadata is retained;
- profile restore catches and explains every preflight/decrypt error, retries
  passphrases, publishes local data before optional network engine downloads,
  reports omissions, and refuses to export an envelope its importer rejects;
- the legacy adapter ignores future top-level fields and accepts historical
  empty Xtream passwords/list labels; the tag-derived 0.8.1 v1 contract fixture
  is covered in the automated suite;
- profile-local connection settings, Child download grants, permission-level
  sharing controls, TV-safe profile inputs, hardware PIN keys, graceful editor
  expiry, and keep/delete media disposition are implemented;
- startup now has a catch-all safe screen, and desktop secondary launches use
  an acknowledged primary-instance probe.

## Current automated evidence

| Check | Result |
|---|---|
| `flutter test test/profiles test/remote_chunked_send_test.dart test/remote_session_test.dart test/backup_encryption_test.dart` | Passed: 150 tests |
| Full `flutter test` | `+3000 -9`; exactly the recorded baseline identities: seven series-parser cases, XMLTV legacy retention, and the widget pending-timer smoke test. No profile-introduced failure remains. |
| Changed-Dart-source analyzer | No errors; warning/info diagnostics remain in touched legacy files. Full-repository analysis also retains pre-existing errors in the vendored `media_kit_patched` tests and `media_kit_video_tvos` package. |
| Android debug APK | Passed with Android Studio JBR 21 |
| macOS debug build | Passed on the final source state |
| iOS simulator debug build | Passed on the final source state |
| tvOS Runner and Top Shelf Swift syntax parse | Passed; full link unavailable on this host as described below |
| `git diff --check` | Passed on the final source state |

Stock Flutter on this host cannot link the tvOS target because its `Flutter.xcframework` has no tvOS simulator slice. The repository's tvOS CI uses `flutter-tvos`, which is not installed on this host. Windows and Linux native targets cannot be built on this macOS host.

## Rollout gates still required

These are validation gates, not unresolved source findings:

- **Android / Android TV:** legacy upgrade with native paused jobs/schedules; revoke/rotate while queued; process death around re-seal and projection publication; denied recording; sealed schedule inspection; remote two-device replay/isolation journey.
- **iOS:** physical device key lifecycle, OS backup/restore exclusion, deep-link/OAuth callback scoping, kill during migration/restore/reset.
- **tvOS:** physical Apple TV cache eviction followed by Keychain reconstruction; termination after each shard and around manifest publication; Top Shelf locked/switch journeys; remote journey.
- **macOS:** crash/low-disk migration, restore, cleanup, recording/schedule drain, and secondary-launch race journeys.
- **Windows:** native build plus double-slot reset-journal kill matrix, DPAPI key journey, single-instance forwarding, recording/schedule drain.
- **Linux:** native build plus vault unlock/recovery, single-instance forwarding, migration/restore/reset kill matrix, recording/schedule drain.
- **All platforms:** canonical release-upgrade fixture captured from the actual last non-profile binary, large/low-storage cases, and full supported-platform manual matrix.

No rollout flag should change until those rows are recorded as passed. If a platform is excluded from the first profiles release, that exclusion must be explicit in release packaging rather than relying on an untested code path.
