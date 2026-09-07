import 'dart:async';

import 'remote_chunked_send.dart';
import 'remote_constants.dart';
import 'remote_control_state.dart';
import 'remote_session.dart';
import 'remote_transfer_diagnostics.dart';
import 'udp_command_service.dart';
import '../transfer/transfer_category_registry.dart';

/// Receiver-side bookkeeping for the v4 batch transfer protocol.
///
/// Two related jobs live here, because they are two halves of one promise the
/// receiver makes to a sending phone:
///
/// * the OPEN TRANSACTION — which request id, from which peer, is currently
///   allowed to stage configuration, and which of its manifest items have
///   actually arrived; and
/// * the OUTCOME — what the receiver decided about a request, retained long
///   enough that a sender whose acknowledgement was lost can retry safely,
///   plus the best-effort delivery of that decision back over the session.
///
/// Everything it needs from the router arrives through the callbacks below —
/// it never reaches into the router itself.
class RemoteTransferBookkeeper {
  RemoteTransferBookkeeper({required this.peerKeyOf});

  /// Identity a transfer is bound to, so a second peer cannot join it.
  final String? Function(RemoteCommandContext context) peerKeyOf;

  // Completed v4 requests are retained briefly so a sender can safely retry
  // a lost UDP completion packet without applying the same payload twice.
  final Map<String, ({bool ok, String message, DateTime completedAt})>
  _remoteTransferOutcomes = {};
  String? _activeRemoteTransferRequestId;
  String? _activeRemoteTransferPeer;
  final Map<String, int> _activeRemoteTransferReceived = {};
  static Set<String> get remoteBatchCommands => <String>{
    RemoteAction.addon,
    ...TransferCategoryRegistry.instance.remoteBatchCommands,
  };
  static const Duration remoteTransferOutcomeLifetime = Duration(minutes: 5);

  /// The decision already reached for [requestId], if one is still retained.
  ({bool ok, String message, DateTime completedAt})? outcomeFor(
    String requestId,
  ) => _remoteTransferOutcomes[requestId];

  /// True while [requestId] from this [peer] already owns the staging buffer.
  bool isOpenFor(String requestId, String peer) =>
      _activeRemoteTransferRequestId == requestId &&
      _activeRemoteTransferPeer == peer;

  /// Hand the staging buffer to a new transaction.
  void open(String requestId, String peer) {
    _activeRemoteTransferRequestId = requestId;
    _activeRemoteTransferPeer = peer;
    _activeRemoteTransferReceived.clear();
  }

  /// Reports a profile-graph transfer's real outcome back to the sender —
  /// delivery is not application, and without this the phone's "sent" toast
  /// was a lie whenever the TV refused or the user declined.
  Future<bool> reportProfileGraphResult(
    RemoteCommandContext remoteContext, {
    required String? requestId,
    required bool ok,
    required String message,
  }) async {
    final trace = RemoteTransferDiagnostics.traceToken(requestId);
    final sidB64 = remoteContext.sidB64;
    if (sidB64 == null) {
      RemoteTransferDiagnostics.record(
        'receiver_result_send_unavailable',
        fields: <String, Object?>{'trace': trace, 'reason': 'missing_sid'},
      );
      return false;
    }
    final state = RemoteControlState();
    final session = state.sessionManager?.sessionBySid(sidB64);
    if (session == null || !session.authorized) {
      RemoteTransferDiagnostics.record(
        'receiver_result_send_unavailable',
        fields: <String, Object?>{
          'trace': trace,
          'reason': session == null ? 'missing_session' : 'unauthorized',
        },
      );
      return false;
    }
    var sent = false;
    for (var attempt = 0; attempt < 3; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
      try {
        sent =
            await state.sendEncryptedCommand(
              session,
              RemoteCommand(
                action: RemoteAction.config,
                command: ConfigCommand.profileGraphResult,
                data: profileGraphResultBody(
                  requestId: requestId,
                  ok: ok,
                  message: message,
                ),
              ),
            ) ||
            sent;
      } catch (_) {
        // A later attempt can still reach the sender if the profile/session
        // authorization race that rejected this one settles safely.
      }
    }
    RemoteTransferDiagnostics.record(
      'receiver_result_send_finished',
      fields: <String, Object?>{'trace': trace, 'resultOk': ok, 'sent': sent},
    );
    return sent;
  }

  Future<bool> runBestEffortProfileGraphResult(
    Future<bool> Function() send,
  ) async {
    try {
      return await send();
    } catch (_) {
      return false;
    }
  }

  Future<bool> reportProfileGraphResultBestEffort(
    RemoteCommandContext remoteContext, {
    required String? requestId,
    required bool ok,
    required String message,
  }) {
    return runBestEffortProfileGraphResult(
      () => reportProfileGraphResult(
        remoteContext,
        requestId: requestId,
        ok: ok,
        message: message,
      ),
    );
  }

  static String? addonTransferRequestId(String? data) {
    if (data == null || data.isEmpty || data.length > 128) return null;
    return data;
  }

  Future<bool> reportAddonTransferResultBestEffort(
    RemoteCommandContext remoteContext, {
    required String? requestId,
    required bool ok,
  }) async {
    if (requestId == null) return false;
    try {
      final sidB64 = remoteContext.sidB64;
      if (sidB64 == null) return false;
      final state = RemoteControlState();
      final session = state.sessionManager?.sessionBySid(sidB64);
      if (session == null || !session.authorized) return false;
      var sent = false;
      for (var attempt = 0; attempt < 3; attempt++) {
        if (attempt > 0) {
          await Future<void>.delayed(const Duration(milliseconds: 120));
        }
        try {
          sent =
              await state.sendEncryptedCommand(
                session,
                RemoteCommand(
                  action: RemoteAction.config,
                  command: ConfigCommand.addonTransferResult,
                  data: addonTransferResultBody(requestId: requestId, ok: ok),
                ),
              ) ||
              sent;
        } catch (_) {
          // Best effort; retain an earlier success and keep retrying.
        }
      }
      return sent;
    } catch (_) {
      return false;
    }
  }

  Future<bool> reportRemoteTransferResultBestEffort(
    RemoteCommandContext remoteContext, {
    required String? requestId,
    required bool ok,
    required String message,
  }) async {
    if (requestId == null) return false;
    final now = DateTime.now();
    _remoteTransferOutcomes.removeWhere(
      (_, outcome) =>
          now.difference(outcome.completedAt) > remoteTransferOutcomeLifetime,
    );
    while (_remoteTransferOutcomes.length >= 256) {
      _remoteTransferOutcomes.remove(_remoteTransferOutcomes.keys.first);
    }
    _remoteTransferOutcomes[requestId] = (
      ok: ok,
      message: message,
      completedAt: now,
    );
    try {
      final sidB64 = remoteContext.sidB64;
      if (sidB64 == null) return false;
      final state = RemoteControlState();
      final session = state.sessionManager?.sessionBySid(sidB64);
      if (session == null || !session.authorized) return false;
      var sent = false;
      // The result is also UDP. Repeat it with fresh encrypted counters so a
      // single lost datagram cannot turn an applied transfer into a timeout
      // on the phone; request correlation makes duplicates harmless.
      for (var attempt = 0; attempt < 3; attempt++) {
        if (attempt > 0) {
          await Future<void>.delayed(const Duration(milliseconds: 120));
        }
        try {
          sent =
              await state.sendEncryptedCommand(
                session,
                RemoteCommand(
                  action: RemoteAction.config,
                  command: ConfigCommand.remoteTransferResult,
                  data: remoteTransferResultBody(
                    requestId: requestId,
                    ok: ok,
                    message: message,
                  ),
                ),
              ) ||
              sent;
        } catch (_) {
          // Best effort; retain an earlier success and keep retrying.
        }
      }
      return sent;
    } catch (_) {
      return false;
    }
  }

  Future<bool> reportCompleteTransferResultBestEffort(
    RemoteCommandContext remoteContext,
    String? data, {
    required bool ok,
    required String message,
  }) {
    final remoteRequest = parseRemoteTransferRequestBody(data);
    if (remoteRequest != null) {
      return reportRemoteTransferResultBestEffort(
        remoteContext,
        requestId: remoteRequest.requestId,
        ok: ok,
        message: message,
      );
    }
    return reportAddonTransferResultBestEffort(
      remoteContext,
      requestId: addonTransferRequestId(data),
      ok: ok,
    );
  }

  void recordRemoteTransferCommand(
    String command,
    RemoteCommandContext context,
  ) {
    if (!remoteBatchCommands.contains(command) ||
        _activeRemoteTransferPeer != peerKeyOf(context)) {
      return;
    }
    _activeRemoteTransferReceived.update(
      command,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
  }

  String? remoteTransferItemPayload(
    String command,
    String data,
    RemoteCommandContext context,
  ) {
    if (!remoteBatchCommands.contains(command)) return data;
    final item = parseRemoteTransferItemBody(data);
    final activeRequestId = _activeRemoteTransferRequestId;
    final activePeer = _activeRemoteTransferPeer;

    // Raw item bodies remain valid for older, non-transactional senders. A
    // wrapped item is meaningful only while its matching transaction is open.
    if (activeRequestId == null || activePeer == null) {
      return item == null ? data : null;
    }
    if (item == null ||
        item.requestId != activeRequestId ||
        activePeer != peerKeyOf(context)) {
      return null;
    }
    return item.payload;
  }

  bool activeRemoteTransferContainsExpected(
    String requestId,
    Map<String, int> expected,
    RemoteCommandContext context,
  ) {
    if (!activeRemoteTransferMatches(requestId, context) || expected.isEmpty) {
      return false;
    }
    for (final entry in expected.entries) {
      if ((_activeRemoteTransferReceived[entry.key] ?? 0) < entry.value) {
        return false;
      }
    }
    return true;
  }

  bool activeRemoteTransferMatches(
    String requestId,
    RemoteCommandContext context,
  ) =>
      _activeRemoteTransferRequestId == requestId &&
      _activeRemoteTransferPeer == peerKeyOf(context);

  void clearActiveRemoteTransfer() {
    _activeRemoteTransferRequestId = null;
    _activeRemoteTransferPeer = null;
    _activeRemoteTransferReceived.clear();
  }

  /// True while [requestId] owns the staging buffer, regardless of peer.
  bool isActiveRequest(String requestId) =>
      _activeRemoteTransferRequestId == requestId;
}
