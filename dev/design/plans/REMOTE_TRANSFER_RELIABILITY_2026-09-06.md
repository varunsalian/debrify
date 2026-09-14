# Remote transfer reliability work — active, not release-ready

User objective: all Remote transfers must work reliably and quickly, including
large channel sets and Transfer Everything, with low-end TVs as sender or
receiver. User authorized implementation and thorough reviews. Do not reduce
scope to channels or a passing unit suite. No push/install has been performed.

## Implemented so far (requires final review)

- Protocol 6: file-backed HTTP/TCP transfer with 256 KiB authenticated encrypted
  blocks, backpressure, SHA-256, request retries and application receipts.
  Protocol <=5 keeps its UDP path.
- Completed receipts are retained on disk when the bounded memory cache turns
  over. Result callbacks return application results through receipt polling,
  avoiding dependence on a second reverse UDP/TCP connection.
- HTTP endpoint stays alive across remote role/session teardown so a completed
  result remains readable during profile handoff; new admissions still resolve
  current authorized sessions. Default port 5557, test override uses port 0.
- Transfer Everything uses LocalBackupExporter/Restorer file-backed archives on
  protocol 6, without dropping Debrify TV data to fit the old graph size limit.
- Individual channels use gzip JSON-lines with a channel header and every saved
  torrent row, queried by indexed infohash in batches of 500. Receiver imports
  channel and pool in one transaction; count/order/truncation failures roll back.
- DebrifyTvRepository.upsertChannel and DebrifyTvCacheService.saveEntry accept
  optional caller-owned transaction. saveEntry also accepts a streamed pool and
  commits batches of 500, preserving existing WebDAV mutation bookkeeping.
- Legacy channel YAML export uses portable cache reader, preserves orphan hashes,
  normalizes associations and avoids scanning the whole pool for each keyword.
- Fixed premature channel-result listener cancellation (`return await`).
- Export capability checks use authenticated session protocol; graph send no
  longer rejects from stale discovery before probing. Handshake silence reports
  connection failure instead of inventing an old receiver version.
- Legacy resend-cache expiry now starts its 90 second tail after sending ends.
- Shared transfer progress and wake ownership for sender actions and receipt
  processing; a running transfer isn't discarded from UI on a UDP heartbeat loss.
- Privacy-safe reliable transport diagnostics record bytes/phases/retries.

## Evidence so far

- 88 targeted tests passed after initial transport/graph integration.
- Real-socket tests exercise 8 MiB binary integrity, bounded progress blocks,
  lost upload response (exactly one import), slow application, handler failure,
  unknown pairing, mid-send revocation, application receipts and more transfers
  than memory receipt capacity. Last isolated run: 8 passed.
- Real SQLite streamed channel test exports 1,501 hashes (including old keyword
  associations), proves truncated import rolls back, then imports complete pool.
- Latest broader suite running/log at /tmp/debrify-remote-suite.log. Inspect its
  process handle/output before re-running. Earlier logs: /tmp/debrify-remote-*.log.
- Focused analysis last had only style issues (auto-fixed subsequently) and an
  existing deprecated scale call in remote_role_picker_screen.dart.
- Android manifest permits networking/HTTP; macOS release entitlements have
  network client/server. No Android devices were visible via `adb devices`.
  Async question sent asking user to connect phone and identify a low-end TV.

## Historical review checklist (see current validation audit below)

1. Re-run focused analysis and inspect latest suite; fix actual failures.
2. End-to-end tests through RemoteControlState + router for protocol 6, not only
   standalone transport tests: ordinary setup/addons, full profile archives,
   channel files, avatar replies, denied/locked profiles, onboarding handoff.
3. Test receipt reads after session retirement, lost final response, disk-cache
   eviction/replay, corrupted/truncated blocks, connection drop DURING upload,
   disk failure, concurrent/queued transfers. Mid-upload retries currently
   restart body rather than resume; evaluate/implement efficient resume.
4. Review header/body authentication and limits, partial-file cleanup, orphan
   scratch cleanup, receipt expiry, bounded cache behavior, stop/disconnect and
   service startup races. Completed receipt key retention only permits reading
   its original signed request, never a new admission.
5. Review receipt lifecycle races: file cleanup/journal write vs completion,
   cache eviction (only journaled/inactive receipts), in-flight session/profile
   revocation, callback/result arrival before UI listeners, safe retry semantics.
6. Review every UI action for busy/finally/error handling, stale widgets and
   concurrent sends. Verify progress and wake ownership on both sides, incl.
   foreground/background and cancellation. Receiver activity currently has an
   outer receive-file activity and an inner processing activity; both must drain.
7. Assess individual IPTV payloads (still bounded command JSON), device-only
   exclusions, all settings/connection resources and avatar completeness.
8. Build Android and macOS. Exercise actual devices if available; measure time
   and memory on large datasets and low-end hardware or a constrained emulator.
   No claim that low-end runtime is verified until there is actual evidence.
9. Thorough independent passes of the complete diff and appropriate broader
   profile/library/backup regression tests. Don't call goal complete based on
   the narrow targeted suite or absence of obvious bugs.

## Worktree hygiene

Branch webdav-sync, original HEAD 46c22b1a. Pre-existing local diagnostic and
Android TV modifications must remain separate/uncommitted, notably lib/main.dart,
backup_restore_service.dart, profile_restore_coordinator.dart, profile_preferences,
diagnostic_log, native MainActivity/player/diagnostic files and diagnostic tests.
Current task modifies Remote code, channel cache/repository/export helpers, and
relevant tests. No production release/push requested in the current objective.

## Later progress

## Current validation audit — 2026-09-06

- User-requested follow-up: Transfer Everything's v6 archive now captures
  WebDAV Sync via the backup runtime and restores it through the same
  prepublication journal/identity-remapping flow. The receiver confirmation
  discloses replacement of its sync connection. Postpublication reconnection
  errors report imported profiles plus pending sync, avoiding duplicate imports.
  The real graph router test verifies transferred login and paused state.
  All 14 router/backup tests passed; focused analysis clean. Artifacts need
  rebuilding before these changes are installed. Proposed simpler UI is an
  interactive mock at /tmp/debrify-transfer-ux-mock/remote-transfer.html;
  production navigation redesign is not implemented.

- Subsequent review fixes: persistent HTTP startup now clears the initiating
  captured profile scope while retaining other zone behavior. Each request
  captures the then-current committed scope independently. A real socket test
  starts under A, switches to B, reuses the same listener and verifies the
  avatar is saved to B only.
- Authenticated upload blocks revalidate and refresh receiver session activity.
  Absolute maximum age and revocation remain enforced. Tests simulate a
  24-minute upload, maximum-age expiry, and revocation after the first block.
  All 68 targeted tests passed (`/tmp/debrify-review-zone-idle-final-tests.log`);
  focused analysis is clean (`/tmp/debrify-review-zone-idle-analysis.log`).
  Existing release artifacts predate these two fixes and require rebuilding
  before installation. No push or installation performed for these fixes.

- Current-code regression run: **198 tests passed** in
  `/tmp/debrify-remote-final-regression.log`. Includes actual sockets/controller
  imports, interrupted uploads, receiver backpressure, receipt retirement and
  expiry, credentials/addons in file-backed graph import, saved avatar images,
  profile authorization, legacy transport, channel export/atomic import,
  backup packages and progress cleanup on failure/overlap.
- Static analysis: no errors/warnings in Remote changes; one existing
  deprecated `scale` info in remote_role_picker_screen.dart. `git diff --check`
  clean. Log `/tmp/debrify-remote-final-analysis.log`.
- Final real app Android release build succeeded (93.8 MB, local validation),
  log `/tmp/debrify-remote-final-android-build.log`. Final real app macOS release
  succeeded (151.7 MB), log `/tmp/debrify-remote-final-macos-build.log`.
- Installed final Android app ONLY on disposable emulator-5554. PID 4480 was
  alive; MainActivity was resumed/focused; checked error logs had no crash.
  Emulator screenshot capture produced empty files, so visual UI validation
  is NOT established by this launch check.
- Native low-memory synthetic release probe previously passed 64 MiB transfer
  and 20,000-hash native SQLite channel export/import, peak RSS about 160 MiB.
  Loopback on a host-powered emulator does not establish physical TV CPU or
  Wi-Fi throughput. Current main artifacts are real apps, not probe targets.
- Remaining required validation: real sender/receiver pairing and full/selected
  transfers over an actual network, both directions with a low-end TV,
  including background/foreground interruption and visible UI outcomes.
  Only emulator-5554 is attached. User was asked to connect phone/identify TV;
  no answer received. Do not claim physical-device reliability or goal complete.
- No changes committed/pushed; no user phone/mac installation or data reset.

## Earlier progress notes (chronological snapshots, superseded above)

- Busy-receiver regression reproduced: second 2 MiB transfer emitted 27 body
  progress events within 400 ms while first import was held. Added authenticated
  capacity probe before uploads; busy responses return sender to polling.
  The test now proves zero queued body upload, then exactly two total imports.
  All 12 transport tests passed (`/tmp/debrify-remote-busy-fixed-tests.log`).
- Transport storage now uses AppStorage cache/remote-transfers, enabling expiry
  cleanup after process restart instead of abandoning unique temporary roots.
  Startup failure preserves existing receipts. All 35 cache/handshake/router/
  chunk/pairing tests passed (`/tmp/debrify-remote-cache-tests.log`).
- Full graph router test now includes a Torbox credential and addon resource,
  checks all four source/imported resource records and decrypts each to verify
  exact synthetic secret contents after confirmed durable import. All five
  controller tests passed (`/tmp/debrify-remote-graph-resources-tests.log`).
- macOS main release build succeeded (151.7 MB). Both platform build artifacts
  predate latest readiness/cache changes and need rebuilding after final review.

- Real Android release rebuild finished successfully (60.6 s, 93.8 MB).
  `build/app/outputs/flutter-apk/app-release.apk` is now the real application,
  not the probe. All 16 controller/transport tests pass after liveness changes
  (`/tmp/debrify-remote-liveness-tests.log`). macOS main release build started;
  inspect `/tmp/debrify-remote-main-macos-build.log` and its live process handle.

- Broad review suite: all 194 tests passed in
  `/tmp/debrify-remote-broad-review.log`, covering Remote handshake/transport,
  profile leases/outbound policies/onboarding/avatar/batch behavior, local
  backup ZIP/archive/portable packages, and channel database/import/export.
- Removed legacy UDP pacing delays from acknowledged v6 addon/config/channel
  sends, and suppressed the obsolete confirm-on-TV notice when a graph's
  application result has already arrived. Active reliable sends now refresh
  session activity while sending and polling import completion.
- Focused analysis for touched services/widgets is clean. Full Remote analysis
  has one preexisting deprecated `scale` info in remote_role_picker_screen.dart.
- Real Android app rebuild (`-t lib/main.dart`, release, local validation) is
  running as session 83132; log `/tmp/debrify-remote-main-release-build.log`.
  Revalidate before restarting. Only emulator-5554 is attached; no physical
  phone/TV currently available. Next review should exercise simultaneous large
  sends/receiver-busy behavior (possible early-response/body-write retries),
  complete ordinary setup/addon import and avatars through the new transport,
  and per-process scratch cleanup. Final macOS rebuild still required.

- Protocol 6 now negotiates both transfer listener ports in authenticated
  handshake transcripts. A busy preferred port falls back to an ephemeral
  listener; both normal commands and file archives use the negotiated peer
  port. Older protocol handshakes retain their original transcript format.
  Failed listener startup closes its client/service and removes staging.
- Added tests for negotiated ports in both directions, tampering with each
  advertised port, actual occupied-port fallback in RemoteControlState, and
  compressed credential/addon commands reaching a correlated receiver batch
  without loss on repeated admission. All 34 tests passed in
  `/tmp/debrify-remote-config-ports-tests.log`.

- Added startup/periodic expiry of transport-owned partial files and receipts.
  Sweeps wait for request admission to be idle, incoming requests wait for the
  sweep, and active imports remain protected. Interrupted upload receipts now
  have an inactivity timestamp. Real-socket test verifies stale-file cleanup,
  unrelated-file preservation, active-import protection and eventual expiry.
- Added a real-socket profile-handoff test: completed result is readable after
  pairing retirement, while a new transfer with the retired pairing is denied.
  All 14 transport/controller tests passed in
  `/tmp/debrify-remote-handoff-tests.log` before the final prune-order cleanup.
  Remaining: cleanup of per-process scratch directories, negotiated port/startup
  failures, ordinary config/addon/avatar controller coverage and full final
  builds/review. The goal remains incomplete.

- Confirmed disposable Android TV release probe passed: 64 MiB in 9,810 ms;
  20,000 channel hashes prepared in 398 ms and transferred/imported in 1,046 ms;
  peak RSS 167,686,144 bytes. These are local loopback emulator measurements,
  not physical TV or Wi-Fi throughput evidence. Probe APK copied to
  `/tmp/debrify-remote-device-probe.apk`; default build artifact still requires
  a production `lib/main.dart` rebuild before delivery.
- Fixed profile staging cleanup on failed archive extraction, and guaranteed
  clearing the graph admission flag even if cleanup throws. Restored Unicode
  case-insensitive channel matching (SQLite LOWER only handles ASCII).
  Extended atomic channel import test with mixed-case accented names.
  All 28 transport/router/library tests passed in
  `/tmp/debrify-remote-cleanup-review-tests.log`.

- 133 targeted Remote/profile/library tests passed before subsequent review fixes.
- Android and macOS release builds both compiled successfully (intermediate
  source state; rebuild final artifacts after remaining changes).
- Added real controller/router socket tests: channel file imports 1,001 hashes,
  locked profile returns a correlated failure, file-backed graph shows the real
  confirmation dialog and imports two profiles. All 3 passed.
- Added in-upload connection drop test. Resumes authenticated 256 KiB prefixes;
  final SHA/count verification still precedes any import. Nine standalone
  transport tests passed, including interrupted upload.
- Added signed receipt responses, activity/wake ownership during reception,
  privacy-safe diagnostics and cleanup draining in explicit transport.close().
- Created an isolated Android TV AVD `codex_remote_low_memory_20260906`, started
  headless with 1024 MiB RAM and 2 CPU cores. This does not touch the user's AVD.
- Added `tool/remote_transfer_device_probe.dart`: synthetic 64 MiB binary and
  20,000-hash channel tests for native Android release runtime/memory measurements.
  Probe build is in progress at /tmp/debrify-device-probe-build.log.
  IMPORTANT: building this target REPLACES build/.../app-release.apk with the
  probe. NEVER install that artifact on the user's phone. Copy to a distinct
  /tmp/probe APK for the disposable emulator and rebuild `-t lib/main.dart`
  before any user-device installation or final delivery.

## Approved transfer UX implementation (2026-09-06)

- Replaced the sender menu with Send / Control, Send everything, and granular
  addons, channels, accounts/setup and photo paths. Category selections persist;
  individual sends use exactly one item, while the review action uses the basket.
- All profiles remains distinct from current-profile setup. WebDAV sync is an
  explicit all-profiles option; receivers lacking archive support cannot silently
  omit it. WebDAV browsing connections are labeled separately.
- Applied Settings theme surfaces and ink to the sender, discovery, controls,
  keyboard and transfer review. Kept pairing, manual IP and receiving paths.
- Reused existing authorized send handlers. Selected config/addons share a batch;
  a preparation failure prevents partial batch completion. Successful channels
  are removed from the retry selection. Inventory failures expose retry controls.
- Review fixes: Material-backed selection rows retain visible tap feedback;
  narrow discovery status text wraps; disposal cannot clear a disposed password
  controller. Verified the receiver discards an abandoned staged batch on retry.
- Validation: 113 transfer/profile/WebDAV/UI tests passed, followed by 4 UI tests
  including an additional 320-pixel discovery-screen regression (114 unique tests).
  Focused analysis has no errors/warnings; one preexisting role-picker deprecation
  remains. git diff --check passed. The final Android release build passed. No physical two-device transfer validation
  or user-device install was performed for this UI change.
