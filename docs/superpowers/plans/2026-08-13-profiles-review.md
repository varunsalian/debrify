# Multi-Profile Implementation Review Plan

> **Status:** Ready to execute against the uncommitted multi-profile implementation. This document defines review work only; it does not authorize rollout or enable either profile feature flag.

**Review goal:** Establish, with reproducible evidence, that the multi-profile implementation preserves every existing user's data, prevents unintended cross-profile access, survives interruption and storage failures, and behaves consistently on every supported platform before profile migration can be enabled.

**Supported platforms:** Android, Android TV, iOS, tvOS, macOS, Windows, and Linux. Web is explicitly out of scope because Debrify does not support it.

**Primary references:**

- [Multi-Profile Architecture and Implementation Plan](./2026-08-13-profiles.md)
- [Profile storage ownership](../../architecture/profile-storage-ownership.md)
- [Profile security and privacy model](../../architecture/profile-threat-model.md)

The implementation plan is the intended contract. This review must verify the implementation independently rather than treating implementation comments, existing tests, or previous build results as proof.

---

## Release decision

The review produces one of three decisions:

- **Go for guarded rollout:** all automated gates pass, there are no open P0/P1 findings, and every required physical-platform gate passes.
- **Code-complete but rollout-blocked:** code review and available automation pass, but a required physical-device or unavailable-host check remains. Both profile activation flags stay disabled.
- **No-go:** any open data-loss, data-leak, authorization, migration, recovery, or platform-integrity blocker remains.

Passing unit tests alone is not sufficient. Migration, confidentiality, and durability each require an independent sign-off backed by fixtures or failure-injection evidence.

### Severity model

| Severity | Meaning | Examples | Release effect |
|---|---|---|---|
| P0 | Confirmed irreversible loss, secret exposure, cross-profile write, or remotely exploitable authorization bypass | Profile B receives A's token; migration deletes the only good copy; replayed remote command crosses profiles | Stop review and fix immediately |
| P1 | Credible leak/loss path, fail-open behavior, broken recovery, or required-platform failure | Unscoped fallback; partial restore becomes visible; tvOS cannot reconstruct its registry | Blocks rollout |
| P2 | Incorrect behavior with a safe recovery path and no confidentiality impact | Stale non-sensitive UI after switching; recoverable metadata omission | Fix before broad rollout unless explicitly waived |
| P3 | Maintainability, diagnostics, documentation, or low-risk UX issue | Ambiguous message; missing nonessential assertion | May be scheduled with an owner |

No P0 or P1 finding may be waived merely because the feature flags currently default to off.

---

## Review rules

1. Review by invariant and end-to-end journey, not by reading the diff from top to bottom.
2. Do not modify production code during the first audit pass. Record findings first so fixes do not hide related defects.
3. Every finding needs a stable ID, severity, affected platforms, evidence, reproduction, violated invariant, proposed fix, and required regression test.
4. A reviewer must not approve a high-risk subsystem solely from tests written in the same implementation. Inspect both implementation and test oracle.
5. Treat unknown persistent state as profile-owned unless it appears on the reviewed device allowlist with a reason.
6. Treat a missing profile scope, invalid policy, missing owner, stale authorization revision, corrupt envelope, or incomplete generation as an error. It must never fall back to another profile or an empty default that overwrites recoverable data.
7. Exercise both feature-flag states. A disabled flag must leave an unmigrated installation byte-compatible, while an already committed installation must continue using profile storage.
8. Keep fixes uncommitted unless the user later asks for commits. Preserve unrelated workspace changes.
9. Run the expensive full-suite and platform validations at controlled checkpoints. During fixes, rerun focused tests for the affected invariant.
10. Never include actual account credentials, PINs, private URLs, or personal libraries in fixtures, logs, screenshots, or reports.

### Finding format

```text
ID: PROF-REV-000
Severity: P0 | P1 | P2 | P3
Area: migration | isolation | durability | auth | backup | remote | native | UI
Platforms: ...
Invariant: ...
Evidence: file:line, test output, or captured state transition
Reproduction: deterministic steps
Impact: user-visible worst case
Fix direction: smallest safe architectural correction
Regression evidence required: test/build/manual scenario
Status: open | fixed-awaiting-verification | verified | accepted-P2/P3
```

---

## Required review artifacts

Create these while executing the review, not in advance:

1. **Review manifest:** exact Git HEAD, complete tracked and untracked scope, dependency changes, generated files, feature-flag defaults, and excluded unrelated files.
2. **Persistence ledger:** every legacy and new preference, database, file, native store, secret, job, projection, backup field, and cache mapped from old owner to new owner.
3. **Migration report:** fixture matrix, stage/failure matrix, before/after canonical inventories, and unresolved compatibility limits.
4. **Isolation report:** sentinel matrix and results for reads, writes, caches, async work, native surfaces, logs, backups, and remote commands.
5. **Durability report:** destructive-operation ledger, crash-injection results, recovery behavior, and proof that source data remains until publication succeeds.
6. **Platform report:** build and manual results for all seven supported targets, with device/OS/toolchain identifiers.
7. **Findings register:** deduplicated, severity-ranked findings with regression evidence.
8. **Final go/no-go report:** explicit status for every gate in this document.

Reports must distinguish `passed`, `failed`, `not run`, and `not applicable`. “Expected to work” is not a passing result.

---

## Phase 0: Freeze scope and establish an honest baseline

### 0.1 Inventory the working tree

- [ ] Record `git rev-parse HEAD`, branch, Flutter/Dart versions, Xcode version, Android toolchain, host OS, and dependency lockfile hash.
- [ ] Capture `git status --short`, `git diff --stat`, `git diff --name-status`, and `git ls-files --others --exclude-standard` so untracked profile files are not omitted.
- [ ] Confirm the intended diff contains no build products, credentials, developer certificates, local paths, or unrelated formatting churn.
- [ ] Explicitly exclude the pre-existing `design/mockups/debrify_tv_spotlight_mockup/` and `design/plans/DEBRIFY_TV_STYLE_PLAN.md` changes from the profile review.
- [ ] Review `pubspec.yaml` and `pubspec.lock` dependency additions for platform support, maintenance status, license, and transitive security implications.
- [ ] Confirm both `DEBRIFY_PROFILES` and `DEBRIFY_PROFILES_MIGRATION_READY` default to `false` in production builds.
- [ ] Confirm no web implementation, web migration path, or accidental web-only dependency was introduced.

### 0.2 Establish the pre-change baseline independently

Use a separate temporary worktree at the recorded HEAD so the current uncommitted implementation is never stashed, reset, or overwritten.

- [ ] Run the pre-change unit/widget suite and record every baseline failure by test name and failure signature.
- [ ] Run analyzer/build checks that are meaningful at HEAD and record pre-existing failures separately.
- [ ] Do not classify a failure as “pre-existing” merely because it was seen earlier; reproduce it at the exact base commit.
- [ ] Compare implementation results against the baseline by stable test identity, not only total pass/fail count.

### 0.3 Verify diff integrity

- [ ] Run whitespace/conflict-marker checks.
- [ ] Inspect newly untracked source and test files in addition to the ordinary Git diff.
- [ ] Confirm generated platform registrants and lockfiles agree with declared dependencies.
- [ ] Confirm automatic backup exclusion files are intentional and do not accidentally exclude ordinary user-exported media.

**Phase 0 exit:** the review has a reproducible base, a complete file inventory, and no ambiguity about unrelated changes or pre-existing failures.

---

## Phase 1: Architecture and invariant audit

This phase proves that all later scenario tests are exercising a coherent design.

### 1.1 Ownership and storage closure

For every entry in `profile-storage-ownership.md`:

- [ ] Locate all read, write, delete, import, export, and cleanup paths.
- [ ] Assign exactly one authority: device, profile generation, connection resource, owner-tagged job, shared public cache, or ephemeral session.
- [ ] Verify every profile path uses an opaque profile ID and visible generation; names never form storage paths.
- [ ] Verify device scope is a closed allowlist rather than a convenient fallback.
- [ ] Verify shared caches contain no account endpoint, private catalog, library, history, or credential-derived content.
- [ ] Verify backup/restore, reset, diagnostics, and cleanup obey the same ownership mapping as normal reads and writes.

Build a persistence ledger that includes at least:

- `StorageService` and direct/shared preference access.
- `SecretVault` and every provider/tracker credential.
- Debrify TV, IPTV catalog/media, TVMaze, Discover, series-source, Stremio, engine, player, subtitle, theme, and layout state.
- Downloads, completed-download history, recordings, schedules, alarms, notifications, retries, and native/plugin task stores.
- Deep links, OAuth callbacks, pending external actions, remote pairing, remote leases, Top Shelf, and external-player handoffs.
- Backup manifests, portable files, restore journals, profile generations, registry snapshots, and tvOS recovery shards.

### 1.2 Bootstrap boundary

- [ ] Enumerate every operation before and after `ProfileBootstrap` in `main.dart` and native launch paths.
- [ ] Prove no profile preference, database, file, credential, cache, provider singleton, schedule, or native projection opens before an immutable scope is published.
- [ ] Verify `ProfilePreferences`, profile storage paths, credential facades, and authorization helpers fail closed when runtime is unavailable.
- [ ] Verify fresh install, legacy compatibility, migration, committed profile mode, corrupt registry, and tvOS recovery enter distinct state-machine branches.
- [ ] Verify a committed registry remains authoritative even if a rollout flag is later disabled.

### 1.3 Registry and lifecycle invariants

- [ ] Foreign keys and constraints are enabled on every registry connection.
- [ ] At least one enabled Admin always exists.
- [ ] Active profile references an enabled profile and a complete visible generation.
- [ ] Profile IDs, resource IDs, generation IDs, revisions, and owner fields cannot be silently regenerated during recovery.
- [ ] Profile switching follows prepare, quiesce, publish, reset, and rewarm ordering.
- [ ] Failed activation restores the prior visible scope without exposing a half-warmed new scope.
- [ ] Desktop single-instance enforcement occurs before any process opens mutable profile stores.

### 1.4 Source-level bypass search

- [ ] Search for direct `SharedPreferences` opens outside reviewed device stores.
- [ ] Search for hard-coded database and file paths lacking profile generation.
- [ ] Search serialized native jobs for missing owner/resource/revision fields.
- [ ] Search service singletons, static variables, memoized futures, streams, and caches that can retain Profile A after activation of B.
- [ ] Search route handlers and settings actions that rely only on hidden UI instead of operation-boundary authorization.
- [ ] Search logs and exceptions for tokens, headers, PINs, URLs, provider responses, stable profile IDs, and resource IDs.
- [ ] Search backup and remote decoders for mutation paths that bypass `ProfileRestoreCoordinator`.

**Phase 1 exit:** the persistence ledger has no unknown owner, and bootstrap/runtime access has no unreviewed fail-open path.

---

## Phase 2: Dedicated migration sign-off

Migration is a separate release gate. Review live-install migration and backup-format migration independently.

### 2.1 Build representative legacy fixtures

Create synthetic, privacy-safe fixtures from the last non-profile release. Each value must be unique enough to detect omission, duplication, reassignment, or accidental defaulting.

- [ ] Empty/fresh installation.
- [ ] Minimal existing installation with onboarding complete.
- [ ] Fully populated installation using every supported settings family.
- [ ] Every credential/resource type individually and all types together.
- [ ] Debrify TV, IPTV, Stremio, search/discovery, playback, subtitle, history, playlist/favorite/watchlist, and cache state.
- [ ] Downloads and completed history; Android recordings, schedules, alarms, and callbacks; desktop schedules/recordings where supported.
- [ ] Custom engine/config files, subtitle fonts, external-player settings, destinations, SAF/security-scoped grants, and unusual valid paths.
- [ ] Large databases, Unicode names/metadata, empty values, old optional fields, duplicated logical resources, and records at schema boundaries.
- [ ] Corrupt-but-partially-recoverable preferences, databases, files, secrets, native records, and legacy backups.

Fixtures must be generated by or validated against the actual last non-profile release format. Handwritten JSON that merely resembles the old format is insufficient.

### 2.2 Verify feature-state behavior

| Starting state | Flags/action | Required result |
|---|---|---|
| Fresh install | Profiles disabled | Existing legacy startup remains byte-compatible |
| Populated legacy install | Profiles disabled | No migration writes, registry commitment, namespacing, or credential conversion |
| Fresh install | Profiles permitted | One unpinned Admin is created before onboarding |
| Populated legacy install | Migration permitted | `legacy-admin-v1` becomes active with unchanged user-visible state |
| Committed profile install | Either flag later disabled | Profile storage remains authoritative; no stale legacy fallback |
| Interrupted migration | Relaunch | Deterministic resume or rollback without duplication |
| Corrupt registry/migration | Relaunch | Explicit recovery; never a silently empty replacement profile |

### 2.3 Trace the complete old-to-new mapping

For every fixture field, record:

```text
legacy source -> migration stage -> new authority/path -> validation rule -> retained source/cleanup rule
```

The mapping must cover:

- [ ] Profile-owned preferences and onboarding state.
- [ ] Credential conversion into one resource, its owner grant, binding, public configuration, and sealed secret.
- [ ] Profile SQLite databases, private files, imported configuration, and cache classification.
- [ ] Owner/revision tagging for native/plugin downloads, recordings, schedules, alarms, history, and pending callbacks.
- [ ] Device state that must remain device-owned rather than being copied into the Admin.
- [ ] Remote identity/pairing continuity without carrying stale per-profile authorization.
- [ ] Native preference projections and revision publication.
- [ ] tvOS durable recovery representation versus purgeable projections.

Prove that no migrated credential remains writable through legacy preference keys after commitment.

### 2.4 Review transaction and publication semantics

- [ ] Migration writes only to a staging generation and journaled registry state.
- [ ] Validation completes before the visible-generation/active-profile publication.
- [ ] Publication is a single durable authority change, not a claimed transaction across unrelated stores.
- [ ] Source preferences/files/databases remain intact and read-only for the documented rollback window.
- [ ] Cleanup cannot run before successful publication, diagnostic availability, and retention criteria.
- [ ] Journal replay is idempotent and detects a stage already completed.
- [ ] Repeated launch after commitment produces no additional mutations.
- [ ] Two desktop launches cannot both perform migration.

### 2.5 Failure injection

Inject failure before and after every durable migration operation, including:

- Registry/schema creation.
- Admin creation.
- Preference snapshot/copy.
- Each database snapshot/copy.
- File manifest/copy.
- Device-key acquisition and each credential seal.
- Resource/grant/binding insertion.
- Native job ownership conversion.
- tvOS recovery shard writes and manifest publication.
- Generation validation.
- Active-profile publication.
- Native projection refresh.
- Legacy retention/cleanup scheduling.

For each boundary, exercise process termination, thrown exception, disk full/write failure, malformed input, missing source, vault unavailability, and—where applicable—concurrent secondary launch. After restart, the oracle must prove either the complete old state or the complete new state is visible, never a mixture.

### 2.6 Migration comparison oracle

Create a canonical, secret-redacted inventory before and after migration containing:

- Logical key/value hashes and ownership.
- Database table counts, primary-key sets, relationship counts, and selected canonical row hashes.
- File relative paths, sizes, and hashes.
- Resource types, owners, grants, bindings, and secret-presence markers—not secret plaintext.
- Job IDs, owners, resource references, authorization revisions, states, and destination references.
- Onboarding, active-profile, generation, migration, and registry revision state.

The oracle must explicitly classify allowed transformations. Any missing, duplicated, reassigned, or silently defaulted item is a failure.

### 2.7 Legacy backup migration

- [ ] Restore genuine plain-v1 and encrypted-v2 packages produced by the last non-profile release.
- [ ] Test restore into a fresh install, the selected Admin, and a staged new profile as supported by product policy.
- [ ] Confirm legacy credentials become resources rather than preference copies.
- [ ] Confirm conflict decisions are deterministic and previewed before mutation.
- [ ] Confirm malformed or wrong-password packages leave current visible state unchanged.
- [ ] Confirm all sources—local file and remote transfer—enter the same adapter and restore coordinator.

**Migration sign-off:** every persistence-ledger entry has a tested destination; all interruption points recover; profiles-disabled startup performs no migration; committed installations never revert to legacy authority; and source data is retained according to policy.

---

## Phase 3: Dedicated cross-profile data-leak sign-off

### 3.1 Define the authorization oracle

Use at least three profiles:

- `A`: Admin with a PIN and owned resources.
- `B`: Member with a mix of no grant, use-only grant, and narrowly writable grant.
- `C`: Child with restrictive feature policies and no secret-reveal permission.

Seed every profile-owned data family with a unique sentinel. Seed each connection resource and job with distinct owner/resource/revision sentinels. Define whether Admin management may inspect metadata for each data class; do not confuse intentional Admin authority with accidental content visibility.

PIN is an application access gate, not a cryptographic OS-user boundary. Review messages and documentation for claims that exceed that threat model.

### 3.2 Read-isolation matrix

For A, B, and C, verify all applicable surfaces expose only authorized data:

- [ ] Home, history, resume, favorites, playlists, watchlists, search, Discover, catalogs, guides, recommendations, and settings.
- [ ] Provider libraries, account information, Stremio catalogs, IPTV/EPG, Debrify TV, TVMaze, artwork, thumbnails, and derived caches.
- [ ] Downloads, recordings, schedules, notifications, job history, destination names, and errors.
- [ ] Picker, manage-profile UI, backup preview, restore preview, reset UI, diagnostics, and support exports.
- [ ] Android intents/notifications/PiP/native players, Apple URL handlers, Top Shelf, desktop forwarding, and external players.
- [ ] Logs, analytics, crash text, exception messages, clipboard content, share sheets, and temporary files.

Test normal navigation, cold launch, warm resume, process restart, app upgrade, profile lock, and profile deletion.

### 3.3 Write-isolation and asynchronous races

For each provider, database, preference family, player action, OAuth/PIN flow, download, recording, schedule, remote command, and external action:

1. Start the operation under Profile A.
2. Switch to Profile B before completion.
3. Complete, fail, retry, cancel, or time out the operation.
4. Verify any result writes only to A's captured generation and authorized resource.
5. Repeat after revoking the grant, changing policy, locking A, deleting A, transferring ownership, and restoring a new generation.

- [ ] Stale authorization revisions fail closed.
- [ ] A missing/deleted owner never falls back to the active profile.
- [ ] Streams, callbacks, timers, isolates, native callbacks, and cached futures cannot republish A's data into B's UI.
- [ ] In-flight OAuth or provider refresh cannot store a token for whichever profile happens to be active at completion.
- [ ] Cleanup initiated in one scope cannot delete current data from another generation.

### 3.4 Resource graph and credential isolation

- [ ] Raw secrets never appear in profile preferences, UI intended for use-only borrowers, backups without encryption, logs, URLs, job payloads, or native mirrors.
- [ ] Borrower disconnect removes only that profile's bindings and grant.
- [ ] Borrower disconnect never deletes or remotely revokes the owner's account.
- [ ] Shared-owner disconnect fails closed until borrowers are revoked or ownership is transferred.
- [ ] Ownership transfer re-seals the secret under new owner-bound authenticated data.
- [ ] Unshared owner deletion checks active jobs and only then permits upstream revocation.
- [ ] Grant/policy/role precedence is enforced at service boundaries even with malformed imported policy JSON.
- [ ] Child/member routes cannot invoke Admin operations directly.

### 3.5 Remote and external-entry isolation

- [ ] Device pairing survives profile switches, but every command uses a short-lived profile-bound lease.
- [ ] Locked, expired, replayed, reordered, duplicated, or wrong-profile commands fail without side effects.
- [ ] Chunked transfers validate sender, lease, package identity, chunk order/count/size/hash, and final package authentication before restore staging.
- [ ] Pending links/shares are bounded, sealed, expiring, single-use, and dispatched only after explicit profile selection/unlock.
- [ ] Top Shelf publishes only a revisioned privacy-safe snapshot for the active unlocked profile and cannot access recovery secrets.
- [ ] External-player warnings accurately disclose that another app may retain URLs or viewing information.

### 3.6 Automated sentinel testing

Add or verify randomized tests that generate multiple profiles, data families, resources, grants, policies, jobs, switches, and failures. After every operation, query all public service APIs and inspect persisted stores for forbidden sentinel movement.

The test oracle must fail on:

- A sentinel readable by an unauthorized profile.
- A write attributed to the wrong owner/generation.
- A secret copied rather than referenced.
- An ownerless durable record.
- Unscoped fallback.
- A stale cache/stream result delivered after activation revision changes.
- Sensitive values in logs, diagnostics, backups, projections, or error strings.

**Isolation sign-off:** no unauthorized sentinel is visible or writable through Flutter, native, background, backup, remote, diagnostic, or external-entry surfaces, including during lifecycle races.

---

## Phase 4: Dedicated data-loss and recovery sign-off

### 4.1 Destructive-operation ledger

Inventory every operation that can overwrite, retire, revoke, detach, or delete data:

- Migration and schema upgrade.
- Restore publication and conflict resolution.
- Profile reset and device reset.
- Profile deletion.
- Resource disconnect, revocation, rotation, transfer, and deletion.
- Job cancellation/removal and artifact reconciliation.
- Cache cleanup, generation retirement, and legacy cleanup.
- tvOS shard pruning and projection reconstruction.
- App uninstall/OS backup/device transfer behavior where controllable.

For each operation record authority, prerequisites, preview/confirmation, journal, atomic visibility point, rollback or recovery behavior, retained artifacts, cleanup delay, and user-facing outcome.

### 4.2 Atomic visibility and generation recovery

- [ ] Restore/migration stages all profile stores, files, resources, grants, bindings, and native metadata before publication.
- [ ] The current visible generation remains usable while staging proceeds.
- [ ] A single authoritative commit marker makes the new graph visible.
- [ ] Startup recognizes incomplete staging, published-but-not-projected, and cleanup-pending states.
- [ ] It rolls forward or rolls back deterministically without merging incomplete data into the visible generation.
- [ ] Old generations remain until verification and the documented retention condition.
- [ ] Cleanup validates generation identity and never follows unsafe paths, names, unresolved variables, or attacker-controlled traversal.

### 4.3 Fault matrix

Run destructive workflows under:

- Process kill or device reboot at every durable boundary.
- Disk full, quota exceeded, read-only destination, short write, rename failure, and file disappearance.
- Corrupt SQLite database, invalid foreign key, malformed JSON, hash/MAC mismatch, and truncated package.
- Device key unavailable, vault locked, Keychain/Keystore/DPAPI/Secret Service failure, Linux fallback passphrase failure, and key loss.
- Destination grant revoked, external drive removed, network loss, remote sender disconnect, duplicate chunks, and retry storms.
- Two desktop launches, duplicated Android callbacks, late Apple callbacks, stale alarms, and package replacement.

The visible result must be one complete previously validated generation or one complete newly validated generation. Never accept silent reset-to-empty as recovery.

### 4.4 Backup round-trip oracle

- [ ] Export a fully populated multi-profile graph using v3.
- [ ] Verify manifest authentication, encryption parameters, bounded extraction, path traversal defense, and secret handling.
- [ ] Restore into a clean supported device and compare canonical inventories.
- [ ] Restore into a populated device with ID/resource conflicts and verify the previewed deterministic resolution.
- [ ] Confirm PIN hashes are never exported; protected restored profiles require Admin PIN reassignment.
- [ ] Confirm device identity, platform keys, stale leases, unsafe filesystem grants, and device-bound native state are not transplanted.
- [ ] Verify profile/resource relationships, selected bindings, policies, settings, files, and supported activity survive exactly once.
- [ ] Verify wrong password, corruption, cancellation, low disk space, and interruption leave the pre-restore state intact.

### 4.5 Profile/resource deletion behavior

- [ ] Deleting a profile cannot remove the last enabled Admin.
- [ ] UI enumerates active jobs, retained public artifacts, owned resources, borrowers, schedules, and private data before confirmation.
- [ ] Public/user-selected downloads and recordings follow the documented retain/delete choice and never disappear silently.
- [ ] Owned shared resources require explicit borrower revocation or transfer.
- [ ] Jobs snapshot owner/resource/destination authorization so later profile switching cannot reassign them.
- [ ] Orphan reconciliation reports or safely quarantines inconsistent records rather than assigning them to the active profile.

### 4.6 tvOS durability exception

On a physical Apple TV:

- [ ] Measure Keychain shard sizes, latency, update failure behavior, and practical profile/resource limits.
- [ ] Delete every purgeable `Library/Caches`/temporary projection and relaunch.
- [ ] Reconstruct profile registry, roles, policies, lock metadata, resources, grants, bindings, and bounded must-survive preferences from the complete published Keychain generation.
- [ ] Confirm activity/catalog/cache loss is explicit and does not become registry loss.
- [ ] Interrupt each shard write and manifest publication; only the prior complete manifest may load.
- [ ] Exercise missing/mismatched `installInstanceId`, uninstall/reinstall behavior, Keychain loss, and authenticated remote restore.
- [ ] Prove the Top Shelf extension has no entitlement to recovery/resource secrets.

If physical-device Keychain feasibility, eviction reconstruction, or remote backup fails, tvOS profile rollout remains blocked even if its simulator build passes.

**Durability sign-off:** every destructive mutation has a deterministic failure path; no test produces an unrecoverable sole copy, partial visible generation, silent empty replacement, or unintended upstream revocation.

---

## Phase 5: PIN, policy, and profile-management review

- [ ] Verify Argon2id parameters, random per-profile salts, constant-time comparison, versioned parameter upgrades, and acceptable unlock latency on low-end Android TV hardware.
- [ ] Verify failed-attempt counters and lockout survive restart and cannot be bypassed by clock rollback, alternate routes, remote commands, deep links, or settings shortcuts.
- [ ] Verify PIN digits/hashes are absent from logs, analytics, backups, native projections, clipboard, and diagnostics.
- [ ] Verify sensitive Admin actions re-authenticate according to the product contract.
- [ ] Verify role is a maximum-authority boundary; policies and grants only narrow it.
- [ ] Verify malformed/unknown policy fields fail closed while forward-compatible known-safe fields survive round trip.
- [ ] Verify profile copy duplicates only approved settings—not identity, PIN, activity, secrets, grants, jobs, role escalation, onboarding state, or authorization revision.
- [ ] Verify the sole unpinned profile auto-enters; multiple or PIN-protected profiles enter the picker/gate.
- [ ] Verify disabled/deleted profiles cannot unlock, receive new work, or remain active.
- [ ] Review phone, tablet, TV focus/remote, keyboard, screen-reader, scaling, and back-navigation behavior.

---

## Phase 6: Background, native, and lifecycle review

### Common contract

- [ ] Every durable job has immutable owner profile, resource reference where needed, authorization revision, and destination snapshot.
- [ ] Job execution does not depend on whichever profile is currently active.
- [ ] Query/UI APIs return owner-filtered views; Admin management exceptions are explicit.
- [ ] Revocation and policy changes follow one documented queued/active/scheduled-job capability rule.
- [ ] Native callbacks with missing or invalid owner metadata quarantine/fail rather than adopt the active profile.

### Android and Android TV

- [ ] Download task/history stores, MediaStore service, recordings, schedules, alarm receiver, native TV players, subtitles, notifications, PiP, and package-replacement paths preserve owner/revision data.
- [ ] Kotlin/Java preference readers consume revisioned native projections rather than old unprefixed Flutter keys.
- [ ] Backup and data-extraction rules exclude device-bound registries, keys, generations, job stores, and resource ciphertext.
- [ ] PIN screens exclude voice/search leakage and remain usable with D-pad navigation.

### iOS and tvOS

- [ ] URL/OAuth/file callbacks retain initiating scope and revalidate authorization.
- [ ] Keychain accessibility/access-group choices match the threat and durability models.
- [ ] App Group/Top Shelf projections contain no secrets and update atomically.
- [ ] iOS automatic backup/device transfer cannot activate copied device-bound profile state.
- [ ] tvOS exposes no unsupported local backup, download, or DVR promise.

### macOS, Windows, and Linux

- [ ] Primary-instance acquisition precedes mutable profile/bootstrap stores.
- [ ] Secondary arguments are bounded, authenticated/sealed as required, forwarded once, and profile-gated by the primary process.
- [ ] Stale lock recovery cannot permit concurrent writers.
- [ ] Keychain, DPAPI, Secret Service, and Linux passphrase fallback behavior is explicit under key loss and account/session changes.
- [ ] Downloads, desktop DVR, user-selected paths, UNC paths, removable storage, AppImage paths, and external commands preserve ownership and safe quoting.

---

## Phase 7: Backup, restore, and remote interoperability review

### One restore pipeline

- [ ] Local v1, local v2, local v3, remote legacy configuration, and remote v3 package inputs are decoded into a bounded intermediate model.
- [ ] All mutations pass through `ProfileRestoreCoordinator`; decoders and command handlers cannot write stores directly.
- [ ] Validation and preview happen before staging; staging completes before visibility publication.
- [ ] Restore cancellation or sender disconnect cannot leave a partially active profile/resource graph.

### Compatibility matrix

| Sender/source | Receiver | Required behavior |
|---|---|---|
| Last non-profile local v1 backup | Profile build | Import through legacy adapter into explicit destination |
| Last non-profile encrypted v2 backup | Profile build | Authenticate/decrypt, then use the same staged restore |
| Profile v3 local package | Profile build | Restore selected graph with deterministic conflicts |
| Legacy remote sender | Profile receiver | Preview and explicit destination; no direct mutation |
| Profile sender | Legacy receiver | Explicitly supported safe subset or clear incompatibility; never misleading success |
| Profile sender | Profile receiver | Authenticated, resumable, bounded v3 transfer |
| Profile sender | tvOS receiver | Reliable authenticated transfer and recovery-store publication |

### Remote protocol

- [ ] Pairing is device-owned; authorization is profile-bound and short-lived.
- [ ] Lease binds peer, profile, authorization revision, command class, nonce, issue/expiry times, and package where applicable.
- [ ] Replay cache persists or otherwise meets the documented restart threat model.
- [ ] Chunk counts, sizes, cumulative limits, hashes, order, duplication, timeout, and storage paths are bounded before allocation/extraction.
- [ ] Profile switch, lock, deletion, policy change, grant revocation, restore publication, or authorization revision change invalidates unsafe outstanding work.
- [ ] Error messages do not reflect remote payloads, endpoints, credentials, or private metadata.

---

## Phase 8: Automated and platform validation

### 8.1 Focused automation after fixes

At minimum, run and record:

```bash
flutter test test/profiles \
  test/remote_chunked_send_test.dart \
  test/remote_session_test.dart \
  test/onboarding/onboarding_route_test.dart
```

- [ ] Add missing fixture, failure-injection, isolation, and round-trip tests discovered in Phases 2–4.
- [ ] Run source guards after every storage/native/restore change.
- [ ] Run credential/provider tests after resource-lifecycle or error-redaction changes.
- [ ] Run formatter only on intentionally changed files to avoid unrelated churn.
- [ ] Run targeted analyzer on changed Dart production/test files and inspect all new warnings/errors.

### 8.2 Full regression checkpoint

- [ ] Run the entire Flutter test suite once after review fixes stabilize.
- [ ] Compare failures with the independently reproduced base-HEAD results.
- [ ] Investigate changes in failure signature, timing, pending timers, crashes, hangs, and skipped tests—not just the count.
- [ ] Run repository-wide analyzer and separate new feature errors from documented baseline/package debt.
- [ ] Run `git diff --check` and repeat scope/secret/generated-artifact checks.

### 8.3 Build and manual platform matrix

| Platform | Automated/build requirement | Required hands-on evidence |
|---|---|---|
| Android | Debug and release APK; native compilation/tests | Upgrade fixture, background download, share/deep link, backup exclusion, restart |
| Android TV | TV build on target ABI | Low-end PIN latency, D-pad UI, native playback/subtitles, notifications/PiP, switching |
| iOS | Simulator and unsigned/device build | Keychain, URL/OAuth/file callback, external player, device-transfer/backup behavior |
| tvOS | Runner and Top Shelf schemes | Physical Keychain/eviction/recovery, remote backup/restore, Top Shelf privacy |
| macOS | Debug/release as available | Keychain, sandbox files, primary instance, forwarding, downloads/DVR |
| Windows | Native CI/host build | DPAPI, installer/paths, UNC/removable storage, primary instance, jobs |
| Linux | x86_64 and ARM64 where supported | Secret Service/fallback, AppImage paths, primary instance, jobs |

No platform may be marked passed from source inspection alone. If a host or device is unavailable, record `not run` and keep that rollout gate closed.

### 8.4 Required end-to-end journeys

Run applicable journeys on every platform:

1. Fresh installation creates the first Admin and completes onboarding once.
2. Populated non-profile installation migrates to an auto-entered Admin without changed visible state.
3. Create Admin/member/child profiles; set PIN/policies; switch, lock, resume, and restart.
4. Create, share, use, revoke, transfer, disconnect, and delete each supported connection type.
5. Start playback/scrobble/download/recording/schedule, switch profiles, and verify origin ownership through completion.
6. Exercise links, OAuth, shares, external players, remote commands, and delayed callbacks across lock/switch/delete races.
7. Export/restore v3 and genuine legacy backups; interrupt each path and compare inventories.
8. Delete profiles with jobs, public artifacts, private data, grants, and owned shared resources.
9. Corrupt registry, policy, resource, job, native projection, backup, and recovery records and verify explicit fail-closed recovery.
10. Disable rollout flags before migration and after committed migration and verify the two distinct contracts.

---

## Review execution and ownership

Use one coordinated audit, followed by targeted verification—not repeated whole-codebase reviews after every fix.

### Independent first pass

Assign non-overlapping primary ownership:

- **Reviewer A — migration and durability:** Phases 2 and 4, including backup-format migration and tvOS recovery.
- **Reviewer B — isolation and authorization:** Phases 1 and 3 plus PIN, credential lifecycle, remote leases, and log/error privacy.
- **Reviewer C — platform and product integration:** Phases 5–8, native bridges, background jobs, lifecycle, UI, and platform matrices.
- **Review lead:** independently audits bootstrap, commit/publication boundaries, the highest-risk P0/P1 paths, deduplicates findings, resolves cross-area conflicts, and owns the release decision.

Reviewers should be given the architecture documents, exact base HEAD, complete diff/untracked manifest, and finding template. They must cite evidence rather than return general summaries.

### Fix and verification loop

1. Freeze and severity-rank the initial findings.
2. Fix P0/P1 issues in small invariant-based batches.
3. Add a regression or failure-injection test for every P0/P1 fix.
4. Have a reviewer other than the fixer verify the finding against its reproduction.
5. Run focused suites for each batch.
6. After all P0/P1 findings close, perform one delta review of the fixes and one full regression/platform checkpoint.
7. Do not restart a complete architectural review unless a fix changes an authority, schema, migration publication model, encryption model, or job ownership contract.

---

## Final acceptance checklist

### Migration

- [ ] Every legacy state family maps exactly once to Admin, device, resource, job, or intentionally disposable cache state.
- [ ] Disabled rollout causes no legacy mutation.
- [ ] Migration is idempotent, interruption-safe, non-destructive, and concurrency-safe.
- [ ] Genuine v1/v2 backup restoration passes through the staged profile restore path.
- [ ] A committed install never falls back to stale legacy state.

### Confidentiality and authorization

- [ ] Cross-profile sentinel tests pass across UI, services, persistence, caches, async work, native jobs, remote, backup, diagnostics, and external surfaces.
- [ ] No unscoped fallback or active-profile adoption exists.
- [ ] Roles, policies, grants, PIN gates, and authorization revisions are enforced at operation boundaries.
- [ ] Secrets and sensitive identifiers are absent from unauthorized UI, logs, backups, projections, errors, and URLs.

### Durability

- [ ] Crash/failure injection never exposes partial state or removes the only validated copy.
- [ ] Restore and migration publish by validated generation.
- [ ] Profile/resource deletion and cleanup preserve declared public artifacts and shared ownership rules.
- [ ] tvOS passes physical recovery tests or remains rollout-disabled.

### Platforms and regressions

- [ ] All seven supported-platform build/manual gates are passed or explicitly block rollout.
- [ ] Full test results introduce no new unexplained failure relative to base HEAD.
- [ ] New analyzer/build errors are zero in changed production code.
- [ ] Diff integrity, backup exclusions, feature-flag defaults, and secret scans pass.
- [ ] No P0/P1 findings remain open.

**Final rule:** profile migration may be enabled only after all four sign-offs—migration, isolation, durability, and platform integration—are complete. Until then, keep `DEBRIFY_PROFILES` and `DEBRIFY_PROFILES_MIGRATION_READY` disabled by default.
