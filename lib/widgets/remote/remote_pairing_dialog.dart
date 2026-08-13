import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../services/remote_control/remote_constants.dart';
import '../../services/remote_control/remote_control_state.dart';
import '../../services/remote_control/remote_pairing_store.dart';
import '../../services/remote_control/remote_session.dart';
import '../../services/remote_control/udp_command_service.dart';
import '../../services/remote_control/udp_discovery_service.dart';

/// Pairing-code UI for the encrypted remote-control protocol.
///
/// Receiver (TV) side: [RemotePairingPanel] embeds in the receive screen and
/// registers itself as the gate's presenter; [showRemotePairingDialog] is the
/// fallback route the router raises when a pairing request arrives while no
/// presenter is mounted (the always-on TV listener case). Sender (phone)
/// side: [showPairingCodeEntrySheet] collects the 6 digits off the TV screen,
/// and [showLegacyBlockedDialog] / [showTvIdentityChangedDialog] carry the
/// old-receiver policy messaging.

/// Card showing the active pairing code. Renders nothing while no pairing is
/// in flight; parents just drop it into their layout.
class RemotePairingPanel extends StatefulWidget {
  final PairingGate gate;

  /// When true the panel counts as a "presenter", suppressing the router's
  /// fallback dialog while it is mounted.
  final bool registerAsPresenter;

  const RemotePairingPanel({
    super.key,
    required this.gate,
    this.registerAsPresenter = true,
  });

  @override
  State<RemotePairingPanel> createState() => _RemotePairingPanelState();
}

class _RemotePairingPanelState extends State<RemotePairingPanel> {
  @override
  void initState() {
    super.initState();
    if (widget.registerAsPresenter) widget.gate.registerPresenter();
    widget.gate.addListener(_onGate);
  }

  @override
  void dispose() {
    widget.gate.removeListener(_onGate);
    if (widget.registerAsPresenter) widget.gate.unregisterPresenter();
    super.dispose();
  }

  void _onGate() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final display = widget.gate.current;
    if (display == null) return const SizedBox.shrink();
    final code = display.code;
    final spaced = '${code.substring(0, 3)} ${code.substring(3)}';
    return Container(
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '"${display.peerName}" wants to send settings',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Enter this code on that device to continue',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 12.5,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            spaced,
            style: const TextStyle(
              fontSize: 44,
              fontWeight: FontWeight.w800,
              letterSpacing: 6,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            autofocus: true,
            onPressed: widget.gate.cancel,
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}

bool _pairingDialogOpen = false;

/// Fallback pairing-code dialog for when no [RemotePairingPanel] is mounted.
/// Dismisses itself when the gate resolves (authorized, cancelled, or timed
/// out).
void showRemotePairingDialog(BuildContext context, PairingGate gate) {
  if (_pairingDialogOpen || gate.current == null) return;
  _pairingDialogOpen = true;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => _AutoDismissOnGateClear(
      gate: gate,
      child: Dialog(
        backgroundColor: const Color(0xFF16181D),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: RemotePairingPanel(gate: gate, registerAsPresenter: false),
        ),
      ),
    ),
  ).whenComplete(() => _pairingDialogOpen = false);
}

class _AutoDismissOnGateClear extends StatefulWidget {
  final PairingGate gate;
  final Widget child;
  const _AutoDismissOnGateClear({required this.gate, required this.child});

  @override
  State<_AutoDismissOnGateClear> createState() =>
      _AutoDismissOnGateClearState();
}

class _AutoDismissOnGateClearState extends State<_AutoDismissOnGateClear> {
  @override
  void initState() {
    super.initState();
    widget.gate.addListener(_onGate);
  }

  @override
  void dispose() {
    widget.gate.removeListener(_onGate);
    super.dispose();
  }

  void _onGate() {
    if (widget.gate.current == null && mounted) {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Phone-side entry for the code shown on the TV. Returns the 6 digits, or
/// null on cancel.
Future<String?> showPairingCodeEntrySheet(
  BuildContext context, {
  required String tvName,
  String? errorText,
}) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: Text('Enter the code shown on "$tvName"'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                letterSpacing: 8,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                counterText: '',
                hintText: '000000',
                errorText: errorText,
              ),
              onChanged: (_) => setDialogState(() {}),
              onSubmitted: (value) {
                if (value.length == 6) {
                  Navigator.of(dialogContext).pop(value);
                }
              },
            ),
            const SizedBox(height: 8),
            Text(
              'This confirms you are sending to the right TV — if the codes '
              'don\'t match, someone may be interfering with your network.',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).hintColor,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: controller.text.length == 6
                ? () => Navigator.of(dialogContext).pop(controller.text)
                : null,
            child: const Text('Confirm'),
          ),
        ],
      ),
    ),
  );
}

/// Policy: credential transfers to receivers that never advertised protocol
/// v2 are refused outright (kLegacyCredentialPolicy = block).
Future<void> showLegacyBlockedDialog(BuildContext context, String tvName) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Update the TV app first'),
      content: Text(
        '"$tvName" is running a Debrify version that can\'t receive '
        'credentials securely. Update Debrify on the TV, then try again.\n\n'
        'The D-pad remote keeps working with older versions.',
      ),
      actions: [
        FilledButton(
          autofocus: true,
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

/// The handshake identity doesn't match any pin stored under this TV's name.
/// Could be a reinstall, a second TV on the default name — or an imposter.
/// The user may proceed to a FRESH code pairing (the SAS is the real gate);
/// the remembered-device shortcut is disabled for this session by the caller.
Future<bool?> showTvIdentityMismatchDialog(
    BuildContext context, String tvName) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('TV identity changed'),
      content: Text(
        '"$tvName" does not match the secure identity it had when you last '
        'paired. This happens after reinstalling Debrify on the TV, or if a '
        'second TV shares the same name — but it can also mean something on '
        'the network is impersonating it.\n\n'
        'If you continue, the TV must show a fresh pairing code and you must '
        'confirm it matches before anything is sent.',
      ),
      actions: [
        FilledButton(
          autofocus: true,
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Re-pair with code'),
        ),
      ],
    ),
  );
}

/// A receiver that previously spoke v2 now claims it can't — likely an
/// attacker stripping the discovery advertisement, possibly a reinstall.
Future<void> showTvIdentityChangedDialog(BuildContext context, String tvName) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('TV identity changed'),
      content: Text(
        '"$tvName" no longer matches the secure identity it had before. '
        'This can happen after reinstalling Debrify on the TV — or if '
        'something on the network is impersonating it.\n\n'
        'Nothing was sent. If you reinstalled the TV app, remove and '
        're-discover the device, then pair again.',
      ),
      actions: [
        FilledButton(
          autofocus: true,
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Sender preflight: policy → session → pairing
// ---------------------------------------------------------------------------

/// Queue of pair-action responses for one pairing flow, so sequential awaits
/// don't fight over a single-subscription stream.
class _PairResponseQueue {
  final List<(String, String?)> _buffer = [];
  final List<Completer<(String, String?)>> _waiting = [];

  void add(String command, String? data) {
    if (_waiting.isNotEmpty) {
      _waiting.removeAt(0).complete((command, data));
    } else {
      _buffer.add((command, data));
    }
  }

  Future<(String, String?)> next(Duration timeout) {
    if (_buffer.isNotEmpty) {
      return Future.value(_buffer.removeAt(0));
    }
    final completer = Completer<(String, String?)>();
    _waiting.add(completer);
    // The waiter MUST leave the queue on timeout — a stale completer would
    // swallow the next real response and starve every retry after it.
    return completer.future.timeout(timeout, onTimeout: () {
      _waiting.remove(completer);
      throw TimeoutException('No pairing response');
    });
  }
}

/// The one gate every credential-bearing send goes through.
///
/// Resolves the legacy policy (v1 receivers are BLOCKED — product decision),
/// detects downgrades against the pinned identity, establishes the encrypted
/// session, and runs the pairing-code flow when the TV doesn't remember this
/// phone. Returns an authorized session, or null with the user already told
/// why.
Future<RemoteSession?> ensureAuthorizedSession(
  BuildContext context,
  RemoteControlState state,
  DiscoveredDevice device,
) async {
  final sameNamePins =
      await RemotePairingStore.knownReceiversNamed(device.deviceName);
  if (!context.mounted) return null;

  // The handshake itself is the version detector: manually entered IPs (and
  // VPN targets) carry no discovery advertisement, so protoVersion defaults
  // to 1 there even for a current TV — and an attacker can strip the
  // advertisement anyway. Probe first; the policy dialogs only fire when the
  // peer genuinely cannot do v2.
  final session = await state.ensureEncryptedSession(device.ip);
  if (!context.mounted) return null;

  if (session == null) {
    switch (decideLegacyCredentialSend(
      peerAdvertisesV2: device.supportsEncryption,
      peerPinnedV2: sameNamePins.isNotEmpty,
    )) {
      case LegacySendDecision.suspectedDowngrade:
        await showTvIdentityChangedDialog(context, device.deviceName);
      case LegacySendDecision.blocked:
      case LegacySendDecision.askOverride: // policy is block; kept compilable
        await showLegacyBlockedDialog(context, device.deviceName);
      case LegacySendDecision.encrypted:
        // Advertised v2 but the handshake failed — transient network state.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not establish a secure connection to the TV'),
          ),
        );
    }
    return null;
  }

  // Identity check against the HANDSHAKE key, not the (optional, spoofable)
  // discovery advertisement: pins under this name exist but none matches the
  // key that just proved itself. Either the TV was reinstalled, it's a second
  // TV sharing the default name — or something is impersonating it. The SAS
  // code is the real gate either way, so the user may proceed to a fresh
  // pairing; the remembered-device shortcut is disabled below for exactly
  // this case.
  final identityMismatch = sameNamePins.isNotEmpty &&
      !sameNamePins.any((p) => p.fingerprint == session.peerFingerprint);
  if (identityMismatch) {
    if (!context.mounted) return null;
    final proceed =
        await showTvIdentityMismatchDialog(context, device.deviceName);
    if (proceed != true) return null;
  }

  var authorized = session.authorized;
  if (!authorized) {
    if (!context.mounted) return null;
    final paired = await _runPairingFlow(context, state, session, device,
        requireSas: identityMismatch);
    if (!paired) return null;
    authorized = true;
  }

  // Pin only an identity that reached authorization — a failed pairing must
  // not overwrite (or seed) the stored pin.
  unawaited(RemotePairingStore.pinReceiver(
    fingerprint: session.peerFingerprint,
    staticKey: session.peerStaticKey,
    name: device.deviceName,
  ));
  return session;
}

Future<bool> _runPairingFlow(
  BuildContext context,
  RemoteControlState state,
  RemoteSession session,
  DiscoveredDevice device, {
  bool requireSas = false,
}) async {
  final responses = _PairResponseQueue();
  final previous = state.onPairMessage;
  state.onPairMessage = (s, command, data) {
    if (s.sidB64 == session.sidB64) responses.add(command, data);
  };
  try {
    final sent = await state.sendEncryptedCommand(
      session,
      RemoteCommand(action: RemoteAction.pair, command: PairCommand.request),
    );
    if (!sent) return false;

    (String, String?) reply;
    try {
      reply = await responses.next(const Duration(seconds: 10));
    } on TimeoutException {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('The TV did not respond to pairing')),
        );
      }
      return false;
    }

    if (reply.$1 == PairCommand.ok) {
      // Remembered device — the TV authorized without a code. Refused when
      // the TV's identity didn't match its pin: an imposter claiming
      // "remembered" would otherwise skip the one check that exposes it.
      if (requireSas) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'This TV skipped code verification but its identity '
                    'changed — transfer refused')),
          );
        }
        return false;
      }
      session.authorized = true;
      return true;
    }
    if (reply.$1 == PairCommand.err) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(reply.$2 == 'busy'
                  ? 'The TV is busy pairing with another device'
                  : 'The TV declined pairing (${reply.$2 ?? 'unknown'})')),
        );
      }
      return false;
    }
    // challenge: the code is on the TV screen now.

    String? errorText;
    while (true) {
      if (!context.mounted) return false;
      final code = await showPairingCodeEntrySheet(
        context,
        tvName: device.deviceName,
        errorText: errorText,
      );
      if (code == null) return false; // user cancelled

      // THE security comparison: the phone checks the typed code against its
      // OWN derivation. Across a MITM the two sessions' codes differ, so this
      // is where an attack dies — before any credential leaves the phone.
      if (code != session.sasCode) {
        errorText = 'Codes don\'t match — read it off the TV again';
        continue;
      }

      final proof =
          await RemoteSessionCrypto.pairProof(session.keys.conf, code);

      Future<(String, String?)> sendProofAwaitVerdict() async {
        final confirmed = await state.sendEncryptedCommand(
          session,
          RemoteCommand(
            action: RemoteAction.pair,
            command: PairCommand.confirm,
            data: base64Encode(proof),
          ),
        );
        if (!confirmed) throw TimeoutException('send failed');
        return responses.next(const Duration(seconds: 10));
      }

      (String, String?) verdict;
      try {
        verdict = await sendProofAwaitVerdict();
        // too_early: the proof landed inside the TV's minimum-display window.
        // The code is already verified locally — resend the SAME proof after
        // a beat instead of making the user retype it (and never feed
        // synthetic entries into the response queue).
        var earlyRetries = 0;
        while (verdict.$1 == PairCommand.err &&
            verdict.$2 == 'too_early' &&
            ++earlyRetries <= 5) {
          await Future.delayed(const Duration(seconds: 2));
          verdict = await sendProofAwaitVerdict();
        }
      } on TimeoutException {
        errorText = 'The TV did not respond — try again';
        continue;
      }
      if (verdict.$1 == PairCommand.ok) {
        session.authorized = true;
        return true;
      }
      switch (verdict.$2) {
        case 'rate_limited':
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text(
                      'Too many attempts — wait a few minutes and try again')),
            );
          }
          return false;
        default:
          errorText = 'The TV rejected the code (${verdict.$2 ?? 'unknown'})';
          continue;
      }
    }
  } finally {
    state.onPairMessage = previous;
  }
}

// ---------------------------------------------------------------------------
// Paired-device management
// ---------------------------------------------------------------------------

/// List of phones this device has paired with, with per-device forget and a
/// forget-all. Forgetting means the next credential transfer from that phone
/// shows the code again.
Future<void> showPairedDevicesDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => const _PairedDevicesDialog(),
  );
}

class _PairedDevicesDialog extends StatefulWidget {
  const _PairedDevicesDialog();

  @override
  State<_PairedDevicesDialog> createState() => _PairedDevicesDialogState();
}

class _PairedDevicesDialogState extends State<_PairedDevicesDialog> {
  List<PairedDevice>? _devices;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final devices = await RemotePairingStore.listPaired();
    if (mounted) setState(() => _devices = devices);
  }

  Future<void> _forget(PairedDevice device) async {
    await RemotePairingStore.forget(device.fingerprint);
    await RemoteControlState().refreshRememberedPeers();
    // A live session from that phone must not stay authorized — otherwise
    // "forget" only takes effect once the session happens to expire.
    RemoteControlState().revokeAuthorization(fingerprint: device.fingerprint);
    await _load();
  }

  Future<void> _forgetAll() async {
    await RemotePairingStore.forgetAll();
    await RemoteControlState().refreshRememberedPeers();
    RemoteControlState().revokeAuthorization();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final devices = _devices;
    return AlertDialog(
      title: const Text('Paired remote devices'),
      content: SizedBox(
        width: 420,
        child: devices == null
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            : devices.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'No devices have paired with this one yet. A device is '
                      'remembered after you enter its code once, so later '
                      'transfers skip the code.',
                    ),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final device in devices)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.smartphone_rounded),
                          title: Text(device.name),
                          subtitle: Text(
                            'Paired ${device.pairedAt.toLocal().toString().split(' ').first}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: TextButton(
                            onPressed: () => _forget(device),
                            child: const Text('Forget'),
                          ),
                        ),
                    ],
                  ),
      ),
      actions: [
        if (devices != null && devices.isNotEmpty)
          TextButton(
            onPressed: _forgetAll,
            child: const Text('Forget all'),
          ),
        FilledButton(
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
