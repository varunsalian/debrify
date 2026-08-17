# Multi-Profile Independent Release-Readiness Review

**Date:** 2026-08-13
**Reviewed baseline:** `591ec0a` (`0.8.2_alpha`) plus the uncommitted multi-profile implementation, after both remediation passes
**Prior documents:** [review report](./2026-08-13-profiles-review-report.md) · [delta review](./2026-08-13-profiles-delta-review.md) · [remediation record](./2026-08-13-profiles-remediation.md)
**Scope:** Independent verification of three release questions: (1) is the 0.8.1 → 0.8.2 upgrade regression-free with both profile flags off, (2) does backup/restore work across versions, (3) does everything the plan advertises actually work. Five parallel review lanes plus direct verification. The finding narratives below preserve the review-time evidence; the closure table records the later remediation.

**Decision:**

- **0.8.2 release (flags off): source blockers resolved.** VER-P0-001/002 and VER-P1-001/002 are fixed and covered by automated tests/native compilation. Normal release-device regression remains required.
- **`DEBRIFY_PROFILES` / `DEBRIFY_PROFILES_MIGRATION_READY` are enabled for owner testing.** Source findings are resolved, but public rollout remains a NO-GO until the physical-device and fault-injection gates in the remediation record pass.
- The missing release-build CI assertion is an explicitly accepted product-owner exception and was not implemented.

## Post-review remediation closure

| Review findings | Status | Closure |
|---|---|---|
| VER-P0-001/002 | **Resolved** | Ordinary v2 remote entry pairs/re-handshakes; v1 peers retain plaintext navigation/media/text only; legacy credential input reaches the source-bound local consent flow; committed profile mode remains encrypted-only. |
| VER-P1-001/002 | **Resolved** | Legacy recording scans include unassigned media; flags-off task/schedule stores avoid Keystore sealing; key creation is synchronized; parseable metadata survives decrypt faults. |
| VER-P2-001–007 | **Resolved or documented** | Backup-scope and single-instance changes are release-noted; startup has a safe failure UI; completed ghosts, URL metadata, typed preference fallback, and backup-format errors are fixed. |
| VER-ON-001–006 | **Resolved** | Restore/export failures are surfaced, password prompts retry, optional network restoration cannot roll back local publication, legacy input is compatible, final envelope size is bounded, and omissions are reported. |
| VER-ON-101–112 | **Resolved** | Live lease reconnects, chunk admission, denial responses, profile-local resource state, Child download grants, granular permissions, TV inputs/PIN keys, expiry handling, deletion disposition, and borrowed-export reporting are implemented. |

The detailed sections that follow describe the defects as originally observed and are retained as an audit trail; they are not the current release status.

## Executive summary

| Question | Answer |
|---|---|
| Upgrade 0.8.1 → 0.8.2 smooth? | **Source-ready.** The flags-off remote, recordings, and Android task-store regressions found by this review are fixed. Release-device regression is still required. |
| Backup/restore across versions? | **Yes at source/automated-test level.** Every flags-off cell was verified against the v0.8.1-alpha.1 tag, and the profile-mode restore UX, optional-network, compatibility, size-budget, and omission-reporting defects found here are fixed. An actual-last-binary fixture and device restore matrix remain rollout gates. |
| Advertised features work? | **Yes at source/automated-test level.** The feature gaps found here are implemented; profile activation still waits on the documented physical-platform rollout matrix. |

The original review found that the earlier security/durability rounds had not covered the **flags-off behavior delta** and **cross-version compatibility**. Those defects drove the remediation recorded above.

## Validation evidence

| Check | Result |
|---|---|
| Full `flutter test` after remediation | `+3000 −9`; the 9 failures are exactly the recorded pre-existing baseline (7 series-parser, XMLTV retention, widget pending-timer). No profile-introduced failure. |
| Profile/remote/backup focused suite after remediation | 150 tests pass. |
| Android debug APK (`assembleDebug`, JBR 21) | Built successfully — Kotlin native changes compile. |
| Flag defaults | `DEBRIFY_PROFILES` / `DEBRIFY_PROFILES_MIGRATION_READY` compile-time, default true for owner testing (`profile_bootstrap.dart:27-34`). Either can still be overridden with `--dart-define=...=false`. |
| CI flag assertion (delta review remediation order item 1) | **Waived by product owner.** Not implemented. |

## Part A — Flags-off upgrade regressions (release blockers first)

### VER-P0-001 — The plain D-pad/media/keyboard remote is broken for upgraders

The v2 encrypted-session enforcement is active regardless of profile flags, but the plain remote path has no pairing entry point.

- Receiver requires `session.authorized` for navigate/media/text and answers `pair.err 'required'` (`lib/services/remote_control/remote_control_state.dart:994-1016`).
- The sender drops that reply (`onPairMessage` handled only inside `_runPairingFlow`, `lib/widgets/remote/remote_pairing_dialog.dart:456`).
- The D-pad UI (`remote_control_screen.dart:805`, `remote_dpad_widget.dart:104`, `remote_floating_button.dart`) never calls `ensureAuthorizedSession`; only credential-transfer flows do (`remote_pairing_dialog.dart:363`).
- Both ends show "Connected" (plaintext heartbeats still flow, `remote_control_state.dart:537-542`) while every press is discarded. The in-code comment "v2 senders always pair first" (`remote_control_state.dart:1003`) shows the assumption; the navigation sender never pairs.

**Scenario:** user upgrades phone + TV, opens the remote as in 0.8.1, taps a device, presses D-pad — nothing happens, forever, with no error. Navigation only unlocks if the user happens to run Send Setup/Addons/Channels once (that flow pairs, and remembered-fingerprint auto-auth then admits navigation).

**Compounding defect:** even after pairing, the session idle-expires after 10 minutes (`remote_constants.dart:43`; only `sealCommand`/`openCommand` touch `lastUsed` — heartbeats do not) or dies on TV app restart, and nothing on the navigation path re-handshakes. `connectToDevice` early-returns while `isConnected` (`remote_control_state.dart:489-496`), so re-tapping the device does not recover. 0.8.1 worked indefinitely.

**Fix shape:** run `ensureAuthorizedSession` from the navigate view / `connectToDevice`, surface `pair.err` on the sender as a pairing prompt, and re-handshake (or queue-and-retry) on send-with-no-session.

### VER-P0-002 — Cross-version remote fails silently in both directions; the designed consent flow is dead code

Verified directly: production admission for plaintext datagrams is `_handleCommand` (`remote_control_state.dart:764-778`), which dispatches only authenticated chunk-transport packets and drops every other plaintext command with a debugPrint. It never constructs the `RemoteCommandContext(encrypted:false, authorized:false, sourceIp: ip)` that the router's legacy-consent machinery requires — so the entire buffered "Incoming settings … UNENCRYPTED connection" Allow/Deny flow (`remote_command_router.dart:955-1108`, `_legacyApprovedFor`, `_legacyBuffer`, plaintext chunk replay at `:2000-2009`) is unreachable.

| Direction | Feature | Result |
|---|---|---|
| 0.8.1 phone → 0.8.2 TV | nav/media/text | **Silently broken** (dropped at `remote_control_state.dart:777`) |
| 0.8.1 phone → 0.8.2 TV | config/addon/chunked transfer | **Silently broken**; old phone reports optimistic success while the TV writes nothing |
| 0.8.2 phone → 0.8.1 TV | nav/media/text | **Silently broken** (sender refuses plaintext, `remote_control_state.dart:556-567`) — and the update dialog **falsely states** "The D-pad remote keeps working with older versions" (`remote_pairing_dialog.dart:246-247`) |
| 0.8.2 phone → 0.8.1 TV | config/addon/transfer | Broken **by policy with a clear error** ("Update the TV app first") — acceptable |
| Either | discovery/heartbeat/"Connected" indicators | Compatible (additive fields; 0.8.1 ignores unknown packet types) — which makes the failures above look like app bugs rather than version skew |

No packet-format crashes anywhere; these are authorization-policy breaks. Alpha users update devices at different times, so both directions will occur in the wild.

**Fix shape:** either wire plaintext non-transport commands into the router with an unauthorized context so the consent gate works as designed, or delete the dead flow and make the break honest: fix the false dialog text, show a "TV/phone needs update" state on the navigate view (`DiscoveredDevice.protoVersion` is already plumbed), and consider allowing plaintext *navigation-class* commands (they carry no credentials) toward v1 receivers.

### VER-P1-001 — Recordings hub silently stops listing scan-only recordings (found independently by two lanes)

`MainActivity.buildRecordingsLibrary(ownerProfileId, includeUnassigned)` now gates the MediaStore scan (SDK ≥ Q) and the pre-Q legacy-dir scan behind `includeUnassigned`, which requires `adminAggregate` from Dart (`MainActivity.kt:474-591,1643`). The only caller, `LiveRecordingService.queryLibrary()` (`lib/services/live_recording_service.dart:567-573`), sends `_ownerFilter()` — an empty map in legacy mode (`:735-739`) — and has no `adminAggregate` parameter. In 0.8.1 the scan ran unconditionally and is what surfaces tee-recorded files and recordings whose store entries the old 24h TTL pruned.

**Scenario:** phone/TV user with tee recordings upgrades → the Recordings page no longer lists them. Files remain on disk, invisible and unmanageable in-app; reads as deleted recordings.

**Fix:** pass `adminAggregate: true` from `queryLibrary()` (legacy `activeMayManageProfiles()` returns true) or default `includeUnassigned = !committed` natively.

### VER-P1-002 — Legacy-mode task stores gained an unconditional Android Keystore dependency

Sealing is not gated on committed mode. `DownloadTaskStore.put` (`DownloadTaskStore.kt:62-68`) and `RecordingTaskStore.put` (`RecordingTaskStore.kt:91-93`) seal every entry lacking a sealed payload — every 0.8.1 record gets Keystore-sealed at its first post-upgrade state transition. `MainActivity.scheduleRecording` (~1764) and the TV EPG record dialog (`AndroidTvTorrentPlayerActivity.kt` ~6946) seal new schedules with flags off. 0.8.1 had zero crypto here; the app's Android-TV-box audience includes documented flaky-TEE devices. Concrete new surfaces:

1. TV EPG scheduling seals inside a DialogInterface click listener on the main thread — a Keystore exception is uncaught → crash (plus one-time lazy-keygen jank).
2. `DownloadTaskStore.all()` / `RecordingTaskStore.all()` catch-and-**drop** entries whose sealed payload fails to decrypt (`DownloadTaskStore.kt:86-90`) — key loss (TEE fault, OTA) silently empties the queued/paused download list.
3. `MediaStoreDownloadService` ACTION_PAUSE settle path calls `put` unwrapped (`MediaStoreDownloadService.kt:240`) — seal failure throws out of `onStartCommand` → service crash.
4. `RecordingTaskStore.reconcileDeadEntries` re-seals with no try/catch — a failure aborts the library-query worker → empty library reply to Dart.
5. `DeviceSecretCipherPlugin.getOrCreateKey` is unsynchronized — a first-use race can mint two keys; the loser's blobs become permanently undecryptable, then dropped per (2).

**Fix shape:** gate sealing on committed mode, or wrap every seal/put/reconcile path, synchronize key creation, and treat undecryptable-but-parseable entries as plaintext-preserved rather than dropped.

### Flags-off P2 notes (fix or release-note)

- **VER-P2-001 — OS-level backup scope broadened for everyone.** `backup_rules.xml` / `data_extraction_rules.xml` now exclude databases/files/root/external (0.8.1 excluded only SharedPreferences), so Google-One restore and device-to-device transfer no longer carry SQLite state (IPTV DB, resume positions). iOS: `excludeDeviceBoundStateFromBackup` (`ios/Runner/AppDelegate.swift`) excludes Application Support **and all of `Library/Preferences`** from iCloud backup at every launch, legacy users included. Defensible hardening (device-bound ciphertext would not decrypt anyway) but user-visible: a restored phone comes up factory-fresh where 0.8.1 partially restored. Release-note it.
- **VER-P2-002 — Desktop single-instance gate edge cases.** New for all desktop users (`lib/main.dart:187-191`, `desktop_single_instance.dart:38-92`). A `FileSystemException` from `lock()` for any reason other than "primary alive" (e.g. advisory-lock-less network home dir) is treated as "secondary" → argless launch exits silently every time; a secondary with args that cannot deliver in 5 s throws an uncaught `StateError` instead of exiting cleanly. Also removes the (previously possible) two-window use on Windows/Linux — intentional, note it.
- **VER-P2-003 — Narrow pre-`runApp` catch.** Only `ProfileBootstrapRecoveryRequired` is caught around bootstrap (`main.dart:193-224`); `resumeWithoutRegistryIfNeeded()` runs before the try with no catch. Any other exception (tvOS Keychain `PlatformException`, file-IO errors) → stuck splash with no UI. Exotic-fault-only for legacy users (all legacy inputs short-circuit safely — verified), but a top-level catch-all → minimal error screen is cheap insurance.
- **VER-P2-004 — Completed downloads leave sealed "done" ghosts in the native store until next launch** (0.8.1 removed on success; legacy cleanup now only in `_reconcileWithNative`, `download_service.dart:3146`). Bounded; invisible to UI.
- **VER-P2-005 — Native download events/queries no longer carry the URL** (`url: ""`; `ownerProfileId` replaced it in progress/complete/failed events). All current legacy consumers chase taskId or Dart-side records — verified no functional break — but post-upgrade history rows carry empty URLs; latent trap.
- **VER-P2-006 — `LiveRecordingService.maxConcurrent` lost its Int-typed fallback** (`ProfilePreferenceProjection.getLong` returns default on ClassCastException); a legacy Int-typed write silently reverts the user's custom limit.
- **VER-P2-007 — Backup version-gate error message regressed.** `settings_screen.dart:3890-3895` discards `FormatException.message`; 0.8.1 showed the actionable "newer than this app supports… Update the app." A v3 profile package on a flags-off build now says only "The backup format is invalid" (and even the swallowed text would be wrong advice — `format: 'debrify-profile-package'` is trivially detectable; say "this is a profile backup").

## Part B — Backup/restore compatibility matrix

| Cell | Verdict | Notes |
|---|---|---|
| 0.8.1 v1 file → 0.8.2, flags OFF | **WORKS** | `parse()` gate is `> currentVersion`; `applyBackup` semantically identical to the 0.8.1 tag (only error strings redacted). Verified line-by-line — no keys dropped/renamed/newly validated away. |
| 0.8.1 v1/v2 → 0.8.2, flags ON | WORKS-WITH-CAVEATS | All 15 legacy categories mapped through `LegacyBackupAdapter`; partial-failure policy throws before publication. Caveats: VER-ON-001/002 below. |
| 0.8.2 flags-OFF backup → 0.8.1 (downgrade) | **WORKS** (plaintext) / clean fail (encrypted) | Plaintext export deliberately stamps `version: 1` (`backup_restore_service.dart:49-52`) — 0.8.1 restores it fully. Passphrase export is v2; 0.8.1 rejects with the actionable "Update the app" message. No crash. |
| flags-OFF backup → flags-ON restore (same build) | WORKS | Routed through parse → optional decrypt → adapter; credential-free exports pass the adapter. |
| v3 package → flags-OFF build (this or 0.8.1) | Clean fail | FormatException on both; message quality is VER-P2-007. |
| v3 export/import round-trip (flags ON) | WORKS | Secrets require ≥8-char passphrase + AES-GCM AAD; sanitized packages scrubbed and re-validated; per-section SHA-256; streaming import enforces byte budget per chunk (DELTA-P2-002 fix present). |
| Restore atomicity/truthfulness (coordinator) | WORKS | Shadow generation; manifest recomputed **after** all overlays (`profile_data_generation.dart:156-198`); publication transaction requires non-empty manifest hash + unchanged base generation (`profile_registry.dart:2851-2872`); legacy follow-up failure throws before publication. UI half is VER-ON-001. |
| Android SAF / content-URI file picks | WORKS | file_picker 10.2.3 cache-copies `content://` picks to a real path; both flows guard null path; streaming read is an improvement, not a regression. |

### Flags-ON restore findings (must fix before flags enable)

- **VER-ON-001 (P1) — Profile-mode restore fails silently.** `_restoreProfileBackup` (`settings_screen.dart:3220-3296`): size check, null path, invalid UTF-8/JSON, **wrong v3 passphrase**, **wrong v2 passphrase**, every adapter `FormatException`, and the non-Admin graph `StateError` all throw **before** the try at `:3298`; the callsite is a bare `onTap` — the dialog closes and nothing happens. The legacy flow handles every one of these with a snackbar and re-prompts on bad passphrase; the v3 prompt is single-shot. Same pattern on export (`_createProfileBackup` StateError at `:3071`).
- **VER-ON-002 (P1) — All-or-nothing legacy restore over network-dependent steps.** `legacyFollowUp` runs search-engine fetch/downloads inside the staged restore (`profile_restore_coordinator.dart:516-547`); any failure → `StateError` before publication, and `_verifyLegacyInventory` requires exact counts. A stale engine ID in the remote registry (or restoring offline) permanently bricks a valid v1/v2 backup in profile mode — the same file restores fine flags-off with "1 failed." Pre-flight the engine list or record misses as accepted omissions.
- **VER-ON-003 (P2) — Adapter strictness rejects real-world-legal legacy data** (empty Xtream password, empty list names, unknown *top-level* keys reject the whole restore — `legacy_backup_adapter.dart:33-35,232-236,316`), amplified by VER-ON-001's silence.
- **VER-ON-004 (P2) — No captured-from-real-binary v1 fixture** in the suite (only hand-built maps; `test/fixtures/` has just `release_names.json`). Already an acknowledged rollout gate; remains the weakest cell.
- **VER-ON-005 (P2) — Large IPTV DBs:** export caps (64 MiB/DB, 128 MiB total, `profile_database_snapshot.dart:56-58`) are checked pre-base64, so a successfully exported package can exceed the importer's 128 MiB envelope budget and be refused at import.
- **VER-ON-006 (P2) — Borrowed-resource omissions unsurfaced:** single-profile restore silently skips `owned: false` resources; the success snackbar reports only settings+connections counts; the returned `omissions` map is never shown.

## Part C — Advertised features (flags ON)

### Feature table

Every plan promise verified non-stub: profile CRUD/roles/avatars; launch picker with sole-unpinned auto-enter; PIN (Argon2id off-isolate, constant-time, persisted exponential lockout, admin reset); in-process switching (journaled begin→commit→abort with roll-forward, ~20 process-global caches reset, app root rebuilt via `KeyedSubtree(sessionEpoch)`); generation-scoped storage; connection resources with all six permissions enforced service-side; role policy bundles enforced at service boundaries; flag-gated migration with fail-closed credential inventory; journaled device reset + cleanup ledger; Linux vault; recovery shell (DELTA-P1-012's crash loop is genuinely gone); privacy-safe diagnostics. Plan-named files that don't exist as such (`profile_connections_screen.dart`, `legacy_credential_backend.dart`, `owned_artifact_index.dart`, …) have their responsibilities folded into other units — functionally present except as noted below.

### Remediation spot-check — all six HOLD, no new bugs found in the fixes

| Finding | Verdict | Key evidence |
|---|---|---|
| PROF-P0-001 (borrowed secrets redacted) | HOLDS | Redacted husks for borrowers; owner flows keep cleartext; provider pages hold presence flags only; scalar getters default redacted with zero external callers. |
| PROF-P0-002 / DELTA-P0-003 (async captured authorization) | HOLDS | Capture-before-await + `runIfCurrent` commits verified on MDBList, account services, WebDAV, Stremio; resource service revalidates after every awaited seal/open; registry re-checks actor/revision in-transaction. |
| PROF-P1-007 (runtime stale-handle checks) | HOLDS | Unconditional `throw StateError` on every read/write/remove/clear (`profile_preferences.dart:58-75`); only no-op `reload()`/deprecated `commit()` skip it. |
| PROF-P1-009 (one-way commitment marker) | HOLDS | Written only post-commit (`profile_bootstrap.dart:483-488`); checked at bootstrap; unreachable from legacy paths; reset-window covered by reset journal resumed before bootstrap. |
| PROF-P1-012 (final-manifest verification) | HOLDS | `finalize()` recomputes from final staged bytes; publication transaction demands nonempty hash; graph restore byte-re-verifies immediately before publication. |
| DELTA-P1-008 (PIN/profile admin capability in-transaction) | HOLDS | `_assertManagingActor` inside write transactions; actorless PIN writes denied when committed; compare-and-set on the exact observed PIN record; UI re-validates after dialogs/KDF. |

### New flags-ON findings

- **VER-ON-101 (P1) — Remote lease tombstone blocks reconnects.** `profile_remote_lease.dart:62-71`: a fresh session ID for a fingerprint with *any* existing entry is refused; entries clear only on `authorize()`/`revoke()` (profile gate events). Transport sessions always rotate (10-min idle / 12-h max / app restart), so after any rotation the paired phone is dead until the TV app restarts or revisits the picker. The DELTA-P1-002 test pins the *expired* case; the implementation also blocks re-bind while the previous lease is still valid. Allow replacement sessions for unexpired leases, or clear the fingerprint on transport-session drop.
- **VER-ON-102 (P1) — Lease rate limiter breaks chunked transfers > ~55 KB and starves navigation.** `profile_remote_lease.dart:84-87` caps `allows()` at 60/10 s globally; chunk packets take the profile path at 20 packets/s (`remote_chunked_send.dart:177`), so from ~chunk 60 admissions are denied, chunks are never retransmitted, and the transfer times out. IPTV lists and channel payloads routinely exceed this. Rate-limit per peer and exempt/budget chunk transport, or check the lease once per transfer.
- **VER-ON-103 (P2) — Profile-mode denials are silent on the wire** (`remote_command_router.dart:329,354` debugPrint only; the plan specifies a privacy-safe "authorization required" response). Combined with VER-ON-101 the phone sees unexplained total silence.
- **VER-ON-104 (MEDIUM) — `profile_resource_settings` is dead schema.** Created (`profile_registry.dart:187`), never read/written. A borrower cannot disable a borrowed Stremio addon (`setAddonEnabled`/`removeAddon` throw for `!canManage`; `replaceOwnedCollection` drops borrowed rows) — plan Task 5 promises profile-local enabled/filter state. Fail-closed, but advertised capability missing.
- **VER-ON-105 (MEDIUM) — Child can never receive the `download` grant.** `edit_profile_screen.dart:283-289` hardcodes child grants to `{use}`; `DeviceJobStore.validateAuthorization` requires `download`. The plan's role table says child downloads are possible with explicit Admin grant — that half is unreachable; enabling the child `downloads` feature still yields silent job denial.
- **VER-ON-106 (MEDIUM, TV) — Profile editor uses raw `TextField`s** (`edit_profile_screen.dart:353,408`) instead of the house `TvTextField`/in-app keyboard (Flutter IME bug #177360 on Android TV). Creating/renaming a profile or typing a PIN in the editor on TV is likely unreliable. Picker and unlock keypad avoid text input.
- **VER-ON-107 (LOW) — Grant granularity absent from UI** (no manage/revealSecret/share grants; Member always gets `{use, download, writeRemote}`); services enforce the full model, the UI cannot express it.
- **VER-ON-108 (LOW) — Manage screen uncaught `StateError`** when the managing session changes while the editor is open (`manage_profiles_screen.dart:77-85`) — fail-closed but ungraceful (unhandled async error instead of the snackbar `_delete` uses).
- **VER-ON-109 (LOW) — Delete dialog dead-end:** confirm silently disables unless "Delete unshared owned connections" is checked and "Keep downloaded and recorded files" stays checked; no explanation; deleting public files (plan Task 12 option) not offered.
- **VER-ON-110 (INFO) — PIN keypad ignores hardware digit keys; submit unfocusable until 4 digits.** Minor TV polish.
- **VER-ON-111 (INFO) — Borrower legacy export contains redacted husks** (no leak; cosmetic report accuracy).
- **VER-ON-112 (INFO) — Pairing store is new** (`remote_pairing_store.dart` keys have no 0.8.1 predecessor): nothing to migrate, but every upgrader must pair once — which is exactly why VER-P0-001's missing pairing entry point is fatal.

## Consolidated verified-OK (spot-checks that need no re-review)

- Legacy bootstrap cannot brick or mis-route a never-migrated user: `profiles_committed_once_v1` written only by `_repairRuntimeMirror` after committed bootstrap/migration/recovery; unreachable with flags off; `ProfileBootstrapRecoveryRequired` throw unreachable for legacy users. All bootstrap inputs platform-safe in legacy mode (no `DeviceKeyProvider.initialize()`, no Keychain writes, tvOS read returns nil cleanly).
- `ProfilePreferences` legacy passthrough byte-identical (null scope → physical key unchanged; `StorageService` conversion mechanical; no renamed keys — diff-verified). `DevicePreferences` reads the same raw keys as 0.8.1.
- SecretVault migration (bfe813a) has no credential-loss path: decrypt failure never removes stored values; list migration blocked on any element failure; key-source marker prevents key flipping; covered by `storage_service_vault_migration_test.dart`.
- `ProfileGate`/policy/facades are true no-ops in legacy mode; profile UI hidden; settings flows branch to pre-profile paths.
- Native legacy fallbacks: `ProfilePreferenceProjection` treats absent/≠`profileCommitted` mode as legacy and reads unscoped `flutter.*` (all 14 projected key names verified identical); 0.8.1 task/schedule records parse (missing owner/revision/sealed fields default legally); strict parsing confined to the flag-gated migration; alarms re-arm and fire end-to-end post-upgrade; `NativeProfileMigrationGate` is inert; MediaStore/SAF mechanics verbatim; download queue/records files unchanged.
- Remote security core sound: commit-then-reveal X25519 + triple-DH, transcript-bound HKDF, SAS never transmitted, replay windows, downgrade pinning, flood caps; DELTA-P1-002/003/004 and DELTA-P0-004 fixes present with tests; forget revokes live sessions; legacy mode skips all profile lease machinery.
- Wire compatibility of discovery/heartbeats: additive fields; 0.8.1 ignores unknown types; no cross-version parse crashes.
- Backup crypto: KDF-bomb bounds on v2 and v3 decrypt paths (incl. m ≥ 8·p cross-check); v2 inner-payload version gate; v3 secrets cannot exist unencrypted; sanitized packages scrubbed and re-validated.
- DELTA-P1-009 IPTV rebinding verified end-to-end through publication (staged resource IDs override fingerprints and raw legacy IDs; graceful fallback for never-backed-up providers).
- Registry invariants: final-Admin asserted at 8 mutation sites in-transaction; active-profile deletion blocked; deletion dispositions DB-enforced; interrupted-restore recovery journaled; cleanup ledger survives outside the registry.

## Required actions — current status

**Before releasing 0.8.2 (flags off):**

1. **Done:** VER-P0-001/002, VER-P1-001/002, and the P2 source fixes.
2. **Done:** release notes cover the OS-backup scope and desktop single-instance behavior.
3. **Accepted exception:** the product owner waived the CI assertion preventing release builds from enabling profile flags.
4. **Still required:** normal supported-device regression before publishing the build.

**Before enabling the profile flags:** all source findings in this review are closed. The prior reviews' physical-device, process-death, low-storage, cache-eviction, and cross-version rollout gates still apply.

## Final note

The review's flags-off and flags-on findings have been remediated in source and automated verification is at the repository's known baseline. Profile rollout remains deliberately gated on the physical-platform matrix; this document does not convert unrun device journeys into a release claim.
