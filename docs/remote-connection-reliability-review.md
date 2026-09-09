# Remote connection and transfer reliability review

Review date: 2026-09-09. Baseline: `7aa5899c`, branch `webdav-sync`.
Related reports: GitHub issues #50 and #59.

## Transport boundary

Discovery remains UDP 5555. Session negotiation, pairing, heartbeats and remote
buttons remain UDP 5556. Protocol 6 and newer use application-encrypted HTTP/TCP
5557 for bulk data and receipts; older peers retain the UDP transfer path.
Commit `2bc84234` introduced the reliable transport. It did not eliminate the UDP
dependency before a transfer. A corrected timeout message alone does not fix
discovery, session negotiation, permissions or firewall failures.

## Implemented corrections

- Serialize handshake messages per session, bound queued work, and prevent expired
  or replaced handshakes from publishing sessions after asynchronous work finishes.
- Recover from failed identity initialization instead of caching a failed future.
- Propagate socket startup failures; do not advertise a ready receiver before its
  command listener is available. Surface runtime listener and send failures.
- Confirm connectivity through negotiation or a peer heartbeat, not a fixed delay.
- Retire old sessions and endpoint hints during reconnect and role changes.
- Retry pairing requests and proofs; make a repeated successful proof idempotent.
  Recover a lost acknowledgement from legacy receivers without retyping the code.
- Propagate pairing cancellation and expiry, retain a single attempt deadline,
  and dismiss only the pairing route when another dialog is above it.
- Preserve handler-reported configuration failures in the final transfer receipt.
- Continue discovery after the initial scan, expire stale results, and broadcast
  from each local IPv4 interface without inventing a /24 subnet. Show all usable
  receive addresses, ranking physical/private interfaces ahead of virtual ones.
- Add structured handshake/socket failure diagnostics without credential payloads.
- Declare the macOS local-network usage description.

## Review iterations and evidence

1. Core handshake, binding and result propagation review: 39 focused tests passed.
   Review also found callers that needed to handle newly propagated startup errors.
2. Broader regression review: 160 tests passed. Real UDP packet-loss tests exposed
   test lifecycle problems; after correcting the harness, pairing retries passed.
   Review corrected pairing attempt lifetime and sender-dialog dismissal.
3. Lifecycle/race and compatibility review: 44 focused tests passed; four real UDP
   pairing scenarios passed, including a legacy receiver losing its final OK.
   Review corrected stale post-await session publication and reconnect cleanup.
4. Final sweep: all 167 remote/profile-transfer tests passed, including receiver
   modal-ownership coverage. Analysis reported no errors or warnings (one existing
   `scale` deprecation informational diagnostic remains). Android and macOS release
   packaging passed. An additional 70 encryption/backup/archive/snapshot tests
   passed. Apple distribution review remains unresolved.

The new regression suites are `remote_connection_recovery_test.dart`,
`remote_config_result_test.dart`, `remote_network_addresses_test.dart`, and
`remote_pairing_recovery_integration_test.dart`. Existing reliable-transfer tests
cover authenticated transfer failures, receipts and authorization revocation.

## Outstanding verification and distribution decisions

Do not interpret these tests as a physical Windows-to-Android/TV or
Apple-to-TV reproduction. Loopback tests validate protocol behavior, not router
isolation, OS permission prompts, firewalls or interface routing on real devices.
Android and macOS release builds passed after the final functional corrections.

The installation guide explicitly supports free-Apple-ID sideloading. Experimental
iOS multicast-entitlement and signing changes were therefore removed: the final
signing profile must permit that capability, so adding it unconditionally is not
a compatible fix. iOS automatic discovery remains unresolved. A native Bonjour
discovery path, with matching advertisement on receiving platforms, is a candidate
that needs a separate cross-platform implementation and device validation.
Manual-IP unicast is distinct from broadcast discovery; it does not prove that
broadcast permission or provisioning is correct. At this review, `flutter devices
--machine` listed only macOS and Chrome, not a phone or TV test target.

Apple's [local-network privacy guidance](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)
requires the multicast entitlement for iOS broadcast, but not macOS. macOS also
needs a suitable stable signing identity for reliable permission attribution;
local builds do not prove the public release has that identity. tvOS does not
have the same local-network privacy gate.

No physical-device validation, release publication or issue closure is claimed.

## Follow-up: legacy v1 control readiness

Review found that requiring a handshake or heartbeat made retained v1 controls
inaccessible: those receivers ignore handshakes and reply to a fixed UDP port,
not the sender's ephemeral socket. After probing, an explicitly discovered v1
peer with a running local command socket may therefore enable its existing
one-way controls. This is compatibility availability, not proof of a live remote
listener. Modern peers and manually entered addresses with unknown capabilities
do not receive this fallback; setup/credential transfer authorization is unchanged.

Three real-socket regression cases cover v1 navigation delivery, an unresponsive
modern peer, and an unknown manual peer. All 12 connection-recovery tests and 59
related session/handshake/chunked-send tests passed. Analysis of the two changed
Dart files reported no issues.
