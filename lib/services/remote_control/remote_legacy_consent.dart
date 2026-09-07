import 'dart:async';

import 'package:flutter/foundation.dart';

import 'remote_constants.dart';
import 'remote_session.dart';

/// A plaintext credential packet from a v1 sender, parked until the user
/// answers the consent dialog.
class LegacyConsentItem {
  final bool isAddon;
  final bool isComplete;
  final String command;
  final String data;

  const LegacyConsentItem.config(this.command, this.data)
    : isAddon = false,
      isComplete = false;
  const LegacyConsentItem.addon(this.command, this.data)
    : isAddon = true,
      isComplete = false;
  const LegacyConsentItem.complete()
    : isAddon = false,
      isComplete = true,
      command = ConfigCommand.complete,
      data = '';
}

/// The consent gate in front of PLAINTEXT (v1) remote traffic.
///
/// An encrypted-and-authorized sender (a paired phone or a remembered one)
/// applies directly, and encrypted-but-unauthorized was already bounced at the
/// session layer. A v1 phone has neither, so its packets are buffered here and
/// need an explicit Allow on screen — approval then covers the rest of the
/// burst for [approvalWindow].
///
/// The dialog itself belongs to the router (it is the only part that needs a
/// `BuildContext`): this unit asks for it through [presentConsent], is told the
/// answer through [onConsentAnswer], and takes a stale one down through
/// [dismissConsent]. Everything else it needs arrives through the callbacks
/// below — it never reaches into the router itself.
class RemoteLegacyConsentQueue {
  RemoteLegacyConsentQueue({
    required this.approvalWindow,
    required this.presentConsent,
    required this.dismissConsent,
    required this.dispatchCommand,
    required this.showSnackBar,
    required this.beginBatch,
    required this.markAuthorizedActivity,
  });

  /// How long an Allow keeps covering further packets from the same address.
  final Duration approvalWindow;

  /// Raise the consent dialog for [peer]; false when there is no UI to ask on.
  final bool Function(String peer) presentConsent;

  /// Take down a consent dialog that outlived its buffer.
  final void Function() dismissConsent;

  /// Replays an approved packet through the router's command dispatch.
  final Future<void> Function(
    String action,
    String command,
    String? data,
    RemoteCommandContext context,
  )
  dispatchCommand;

  final void Function(String message, {bool isError}) showSnackBar;

  /// Opens the import-batching window so the replayed burst raises one
  /// summary rather than a parade.
  final void Function() beginBatch;

  final void Function() markAuthorizedActivity;

  static const Duration _legacyBufferExpiry = Duration(seconds: 60);
  static const int _legacyBufferCap = 200;

  DateTime? _legacyApprovedAt;

  /// Both the pending buffer and a granted approval belong to ONE datagram
  /// source. Anything else on the LAN that talks while a consent is pending
  /// (or approved) is a different device and gets its own gate — approving
  /// your old phone must never blanket every host on the network.
  String? _legacyApprovedIp;
  String? _legacyPeerIp;
  final List<LegacyConsentItem> _legacyBuffer = [];
  Timer? _legacyExpiryTimer;
  bool _legacyDialogShowing = false;

  /// The address whose burst currently owns the pending consent.
  String? get peerIp => _legacyPeerIp;

  /// Whether a burst is parked (or its question still on screen).
  bool get hasPending => _legacyBuffer.isNotEmpty || _legacyDialogShowing;

  bool approvedFor(String? sourceIp) {
    final approvedAt = _legacyApprovedAt;
    return sourceIp != null &&
        sourceIp == _legacyApprovedIp &&
        approvedAt != null &&
        DateTime.now().difference(approvedAt) < approvalWindow;
  }

  void enqueue(LegacyConsentItem item, String? sourceIp) {
    // First packet claims the pending consent for its source; anything from
    // a DIFFERENT host while it's pending is a separate device and must not
    // ride this user's answer.
    if (_legacyPeerIp == null) {
      _legacyPeerIp = sourceIp;
    } else if (sourceIp != _legacyPeerIp) {
      debugPrint('RemoteCommandRouter: Dropping packet from another peer');
      return;
    }
    if (_legacyBuffer.length >= _legacyBufferCap) {
      debugPrint('RemoteCommandRouter: Legacy buffer full, dropping packet');
      return;
    }
    _legacyBuffer.add(item);
    _legacyExpiryTimer ??= Timer(_legacyBufferExpiry, () {
      debugPrint('RemoteCommandRouter: Legacy consent expired');
      _denyLegacy();
    });
    _maybeShowLegacyConsentDialog();
  }

  void _maybeShowLegacyConsentDialog() {
    if (_legacyDialogShowing) return;
    final peer = _legacyPeerIp ?? 'unknown address';
    if (!presentConsent(peer)) {
      // Headless (no UI mounted yet): nothing to ask — the expiry timer
      // drops the buffer and the sender sees nothing applied.
      debugPrint(
        'RemoteCommandRouter: No navigator for consent dialog, will drop',
      );
      return;
    }
    _legacyDialogShowing = true;
  }

  /// The user answered the dialog the router raised for us.
  void onConsentAnswer(bool allowed) {
    _legacyDialogShowing = false;
    if (allowed) {
      _allowLegacy();
    } else {
      _denyLegacy(showMessage: true);
    }
  }

  Future<void> _allowLegacy() async {
    _legacyExpiryTimer?.cancel();
    _legacyExpiryTimer = null;
    final approvedIp = _legacyPeerIp;
    _legacyPeerIp = null;
    final items = List<LegacyConsentItem>.from(_legacyBuffer);
    _legacyBuffer.clear();
    if (items.isEmpty) {
      // The buffer expired (or was denied) while the dialog sat open — an
      // Allow with nothing behind it must not open the approval window or
      // count as authorized activity.
      debugPrint(
        'RemoteCommandRouter: Legacy approval with empty buffer, '
        'ignoring',
      );
      return;
    }
    _legacyApprovedAt = DateTime.now();
    _legacyApprovedIp = approvedIp;
    markAuthorizedActivity();
    debugPrint(
      'RemoteCommandRouter: Legacy transfer approved (${items.length} buffered)',
    );
    beginBatch();
    final approvedContext = RemoteCommandContext(
      encrypted: false,
      authorized: true,
      sourceIp: approvedIp,
    );
    var sawComplete = false;
    for (final item in items) {
      if (item.isComplete) {
        sawComplete = true;
      } else if (item.isAddon) {
        await dispatchCommand(
          RemoteAction.addon,
          item.command,
          item.data,
          approvedContext,
        );
      } else {
        await dispatchCommand(
          RemoteAction.config,
          item.command,
          item.data,
          approvedContext,
        );
      }
    }
    if (sawComplete) {
      // Replayed LAST: its handler waits for the just-registered in-flight
      // work (and any live chunk buffers) before finalizing/restarting.
      await dispatchCommand(
        RemoteAction.config,
        ConfigCommand.complete,
        null,
        approvedContext,
      );
    }
  }

  void _denyLegacy({bool showMessage = false}) {
    _legacyExpiryTimer?.cancel();
    _legacyExpiryTimer = null;
    _legacyPeerIp = null;
    final dropped = _legacyBuffer.length;
    _legacyBuffer.clear();
    // A consent dialog that outlived its buffer is answering a dead question
    // — take it down with the buffer.
    dismissConsent();
    if (dropped > 0) {
      debugPrint('RemoteCommandRouter: Dropped $dropped unapproved packet(s)');
      if (showMessage) {
        showSnackBar('Incoming settings were blocked', isError: true);
      }
    }
  }
}
