import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:collection/collection.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../utils/app_storage.dart';

import 'remote_constants.dart';
import 'remote_control_state.dart';
import 'remote_pairing_store.dart';
import 'remote_chunked_send.dart';
import 'remote_session.dart';
import 'remote_transfer_diagnostics.dart';
import 'udp_command_service.dart';
import '../../widgets/remote/remote_pairing_dialog.dart';
import '../../services/main_page_bridge.dart';
import '../../services/stremio_service.dart';
import '../../services/storage_service.dart';
import '../../services/stream_badges_service.dart';
import '../../services/tracking_source_policy.dart';
import '../../services/account_service.dart';
import '../../services/torbox_account_service.dart';
import '../../services/premiumize_account_service.dart';
import '../../services/alldebrid_account_service.dart';
import '../../services/pikpak_api_service.dart';
import '../../services/mdblist/mdblist_service.dart';
import '../../services/engine/config_loader.dart';
import '../../services/engine/engine_registry.dart';
import '../../services/engine/remote_engine_manager.dart';
import '../../services/engine/local_engine_storage.dart';
import '../../services/community/magnet_yaml_service.dart';
import '../../services/debrify_tv_zip_importer.dart';
import '../../services/iptv_transfer_payload.dart';
import '../../services/debrify_tv_database.dart';
import '../../services/debrify_tv_repository.dart';
import '../../services/debrify_tv_cache_service.dart';
import '../../models/debrify_tv_cache.dart';
import '../../models/debrify_tv_channel_record.dart';
import '../../models/indexer_manager_config.dart';
import '../../models/webdav_item.dart';
import '../../models/profiles/profile_policy.dart';
import '../../models/profiles/user_profile.dart';
import '../profiles/profile_remote_lease.dart';
import '../profiles/profile_runtime.dart';
import '../profiles/profile_scope.dart';
import '../profiles/profile_authorization.dart';
import '../profiles/profile_bootstrap.dart';
import '../profiles/profile_database_snapshot.dart';
import '../profiles/profile_avatar_ingest.dart';
import '../profiles/profile_avatar_policy.dart';
import '../profiles/portable_profile_package.dart';
import '../profiles/profile_app_lifecycle_participant.dart';
import '../profiles/profile_lifecycle.dart';
import '../profiles/native_profile_projection.dart';
import '../profiles/profile_restore_coordinator.dart';
import '../../models/profiles/connection_resource.dart';
import '../../services/app_migration_service.dart';
import '../profiles/connection_resource_service.dart';
import '../profiles/device_key_provider.dart';
import '../profiles/profile_cleanup_ledger.dart';
import '../profiles/profile_data_generation.dart';
import '../../services/backup_restore_service.dart';

/// Callback type for remote command handlers
typedef RemoteCommandCallback =
    void Function(String action, String command, String? data);

/// Android KeyEvent key codes
class AndroidKeyCode {
  static const int dpadUp = 19;
  static const int dpadDown = 20;
  static const int dpadLeft = 21;
  static const int dpadRight = 22;
  static const int dpadCenter = 23;
  static const int back = 4;
  static const int mediaPlayPause = 85;
  static const int mediaFastForward = 90;
  static const int mediaRewind = 89;
}

/// Routes UDP remote commands to registered handlers
///
/// Uses platform channels on Android TV to inject real key events,
/// which works with all widgets that respond to D-pad input.
class RemoteCommandRouter {
  // Singleton
  static final RemoteCommandRouter _instance = RemoteCommandRouter._internal();
  factory RemoteCommandRouter() => _instance;
  RemoteCommandRouter._internal();

  // Platform channel for key injection
  static const _channel = MethodChannel('com.debrify.app/remote_control');

  // Registered command handlers
  final List<RemoteCommandCallback> _handlers = [];
  final Set<Future<void>> _pendingRemoteTransferDispatches = {};

  // Chunk reassembly buffer for large channel transfers
  final Map<String, _ChunkBuffer> _chunkBuffers = {};

  Map<String, dynamic>? _profileRemotePayload;
  _ProfileCommandBinding? _profileRemoteBinding;
  String? _profileRemotePeer;
  Timer? _profileRemoteExpiry;
  static const int _maxProfileRemotePayloadBytes = 16 * 1024 * 1024;
  static const Duration _profileRemotePayloadLifetime = Duration(minutes: 10);

  // Completed v4 requests are retained briefly so a sender can safely retry
  // a lost UDP completion packet without applying the same payload twice.
  final Map<String, ({bool ok, String message, DateTime completedAt})>
  _remoteTransferOutcomes = {};
  final Set<String> _remoteTransfersInFlight = {};
  String? _activeRemoteTransferRequestId;
  String? _activeRemoteTransferPeer;
  final Map<String, int> _activeRemoteTransferReceived = {};
  static const Set<String> _remoteBatchCommands = <String>{
    RemoteAction.addon,
    ConfigCommand.realDebrid,
    ConfigCommand.torbox,
    ConfigCommand.premiumize,
    ConfigCommand.allDebrid,
    ConfigCommand.pikpak,
    ConfigCommand.trakt,
    ConfigCommand.simkl,
    ConfigCommand.mdblist,
    ConfigCommand.searchEngines,
    ConfigCommand.webDav,
    ConfigCommand.indexerManagers,
    ConfigCommand.iptvPlaylists,
    ConfigCommand.iptvFavorites,
    ConfigCommand.iptvLists,
    ConfigCommand.streamBadges,
  };
  static const Duration _remoteTransferOutcomeLifetime = Duration(minutes: 5);

  // Navigator key for back navigation
  GlobalKey<NavigatorState>? _navigatorKey;

  // Scaffold messenger key for showing snackbars
  GlobalKey<ScaffoldMessengerState>? _scaffoldMessengerKey;

  // Callback to restart app flow (set by main.dart)
  VoidCallback? _onRestartApp;

  @visibleForTesting
  List<ProfileLifecycleParticipant>? debugOnboardingLifecycleParticipants;

  /// Set the navigator key for back navigation
  void setNavigatorKey(GlobalKey<NavigatorState> key) {
    _navigatorKey = key;
  }

  /// Set the scaffold messenger key for showing snackbars
  void setScaffoldMessengerKey(GlobalKey<ScaffoldMessengerState> key) {
    _scaffoldMessengerKey = key;
  }

  /// Set the callback to restart the app flow
  void setRestartCallback(VoidCallback callback) {
    _onRestartApp = callback;
  }

  // ── import batching ──────────────────────────────────────────────────────
  //
  // A phone import arrives as one packet PER ITEM — every debrid service, both
  // trackers, WebDAV, the indexers, the search engines, and one more for each
  // addon. Each used to raise its own 3-second snackbar, and ScaffoldMessenger
  // QUEUES snackbars rather than overlapping them: twenty items meant a full
  // minute of them marching past, long after the transfer itself had finished.
  // During onboarding it was pure noise — `complete` restarts the app moments
  // later, so the play-by-play was never read.
  //
  // While packets are still arriving the messages are COLLECTED instead of
  // shown, and one summary is raised when the burst ends: on the `complete`
  // signal, or after [_batchIdleGap] of quiet for pushes that never send one.
  // A burst of ONE keeps its own message verbatim, so a single ad-hoc push
  // from the phone reads exactly as it always did.

  /// Quiet time after the last packet before a burst is considered over.
  /// Long enough to bridge the gap between packets of one transfer, short
  /// enough that a lone push doesn't feel delayed.
  static const Duration _batchIdleGap = Duration(milliseconds: 1200);

  Timer? _batchIdleTimer;
  bool _batching = false;
  final List<String> _batchOk = [];
  final List<String> _batchFailed = [];

  /// Open the collecting window, or push its deadline out because another
  /// packet just landed.
  void _beginOrExtendBatch() {
    // While a remote payload is being applied, the apply loop OWNS the batch
    // (opened with no idle timer; flushed once in its finally). An out-of-
    // band packet mid-loop (a channel push, an avatar) must not re-arm the
    // idle timer — it would flush the loop's batch early and let the
    // remaining messages parade individually.
    if (_applyingRemotePayload) {
      _batching = true;
      return;
    }
    _batching = true;
    _scheduleBatchFlush();
  }

  void _scheduleBatchFlush() {
    _batchIdleTimer?.cancel();
    _batchIdleTimer = Timer(_batchIdleGap, () {
      // Quiet on the wire is not the same as finished: a large IPTV list is
      // hundreds of SQLite writes that outlive their packet, and its snackbar
      // is raised when that work lands. Flushing here would close the window
      // before those arrive and let them through one at a time — the exact
      // parade this exists to prevent. Wait for the work, not the packets.
      if (_inFlightConfigWork.isNotEmpty || _chunkBuffers.isNotEmpty) {
        _scheduleBatchFlush();
        return;
      }
      _flushBatch();
    });
  }

  /// Raise the one summary and close the window.
  ///
  /// [prefix] is supplied by the `complete` signal, which knows what the batch
  /// WAS ("Setup received"); an idle flush has no such context and says so in
  /// its own words.
  void _flushBatch({String? prefix}) {
    _batchIdleTimer?.cancel();
    _batchIdleTimer = null;
    _batching = false;

    final ok = List<String>.from(_batchOk);
    final failed = List<String>.from(_batchFailed);
    _batchOk.clear();
    _batchFailed.clear();

    if (ok.isEmpty && failed.isEmpty) {
      // Nothing was imported — a bare `complete` still deserves its
      // acknowledgement, an idle flush has nothing to say.
      if (prefix != null) _showSnackBarNow(prefix, isError: false);
      return;
    }

    // One item and no end-of-batch context: it is a lone push, so it keeps the
    // specific wording its handler chose.
    if (prefix == null && ok.length + failed.length == 1) {
      final single = ok.isNotEmpty ? ok.first : failed.first;
      _showSnackBarNow(single, isError: failed.isNotEmpty);
      return;
    }

    final parts = <String>['${ok.length} imported'];
    if (failed.isNotEmpty) {
      // Only failures are NAMED — a list of everything that worked is the
      // wall of text this change removes, but "2 failed" with no clue which
      // is worse than useless.
      final names = failed.map(_subjectOf).toSet().toList();
      final shown = names.take(3).join(', ');
      final rest = names.length > 3 ? ' +${names.length - 3} more' : '';
      parts.add('${failed.length} failed ($shown$rest)');
    }
    _showSnackBarNow(
      '${prefix ?? 'Import complete'} · ${parts.join(', ')}',
      isError: failed.isNotEmpty,
      duration: const Duration(seconds: 5),
    );
  }

  /// The thing a message is ABOUT: handlers write "Real-Debrid: Invalid API
  /// key", so the part before the colon is the service. Messages without one
  /// ("Failed to install addon") are already their own subject.
  static String _subjectOf(String message) {
    final i = message.indexOf(':');
    return i > 0 ? message.substring(0, i) : message;
  }

  /// Show a snackbar message (TV feedback), or bank it while a burst is in
  /// flight — see the import-batching note above.
  void _showSnackBar(String message, {bool isError = false}) {
    if (_batching) {
      (isError ? _batchFailed : _batchOk).add(message);
      return;
    }
    _showSnackBarNow(message, isError: isError);
  }

  void _showSnackBarNow(
    String message, {
    bool isError = false,
    Duration duration = const Duration(seconds: 3),
  }) {
    final messenger = _scaffoldMessengerKey?.currentState;
    if (messenger == null) return;

    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        duration: duration,
      ),
    );
  }

  /// Register a command handler
  void addHandler(RemoteCommandCallback handler) {
    if (!_handlers.contains(handler)) {
      _handlers.add(handler);
      debugPrint('RemoteCommandRouter: Handler registered');
    }
  }

  /// Remove a command handler
  void removeHandler(RemoteCommandCallback handler) {
    _handlers.remove(handler);
    debugPrint('RemoteCommandRouter: Handler removed');
  }

  void _notifyHandlers(String action, String command, String? data) {
    for (final handler in _handlers.toList()) {
      try {
        handler(action, command, data);
      } catch (_) {
        debugPrint('RemoteCommandRouter: handler failed');
      }
    }
  }

  /// Dispatch a remote command to all registered handlers.
  ///
  /// [context] carries the transport's trust facts: whether the command came
  /// in encrypted, and whether its session has been authorized by a pairing
  /// code (or remembered device). Plaintext is the default so the eight
  /// legacy call sites keep working unchanged.
  void dispatchCommand(
    String action,
    String command,
    String? data, {
    RemoteCommandContext context = RemoteCommandContext.plaintext,
  }) {
    final work = _dispatchCommandAndWait(action, command, data, context);
    final transferWork =
        (action == RemoteAction.config || action == RemoteAction.addon) &&
        command != ConfigCommand.complete &&
        command != ConfigCommand.remoteTransferResult &&
        command != ConfigCommand.addonTransferResult &&
        command != ConfigCommand.profileGraphResult &&
        command != ConfigCommand.debrifyChannelNeed;
    if (!transferWork) {
      unawaited(work);
      return;
    }
    late Future<void> tracked;
    tracked = work.whenComplete(
      () => _pendingRemoteTransferDispatches.remove(tracked),
    );
    _pendingRemoteTransferDispatches.add(tracked);
    unawaited(tracked);
  }

  Future<void> _dispatchCommandAndWait(
    String action,
    String command,
    String? data,
    RemoteCommandContext context,
  ) async {
    if (ProfileRuntime.isInitialized &&
        ProfileRuntime.isProfileCommitted &&
        action != RemoteAction.pair) {
      final scope = ProfileRuntime.capture();
      await _dispatchAfterProfileAuthorization(
        action,
        command,
        data,
        context,
        scope,
      );
      return;
    }
    await _dispatchAuthorized(action, command, data, context);
  }

  Future<void> _dispatchAfterProfileAuthorization(
    String action,
    String command,
    String? data,
    RemoteCommandContext context,
    ProfileScope scope,
  ) async {
    final peerFingerprint = context.peerFingerprint;
    final sessionId = context.sidB64;
    if (!context.encrypted ||
        !context.authorized ||
        peerFingerprint == null ||
        sessionId == null) {
      debugPrint('RemoteCommandRouter: authenticated peer required');
      _noteUnauthenticatedDrop(context);
      unawaited(context.reject?.call('authentication_required'));
      return;
    }
    final feature =
        action == RemoteAction.config || action == RemoteAction.addon
        ? ProfileFeature.remoteTransfer
        : ProfileFeature.remoteControl;
    final profile = await ProfileBootstrap.registry.getProfile(scope.profileId);
    final runtimeCommitted = ProfileRuntime.isProfileCommitted;
    final scopeCurrent = ProfileRuntime.capture() == scope;
    final profilePresent = profile != null;
    final featureAllowed = profile?.allows(feature) ?? false;
    var peerBound =
        runtimeCommitted && scopeCurrent && profilePresent && featureAllowed
        ? ProfileRemoteLease.instance.bindAuthenticatedPeer(
            peerFingerprint: peerFingerprint,
            sessionId: sessionId,
            scope: scope,
            currentProfile: profile,
          )
        : false;
    if (!peerBound &&
        context.remembered &&
        runtimeCommitted &&
        scopeCurrent &&
        profilePresent &&
        featureAllowed) {
      peerBound = ProfileRemoteLease.instance.renewRememberedPeerAfterRevision(
        profile: profile,
        scope: scope,
        peerFingerprint: peerFingerprint,
        sessionId: sessionId,
      );
    }
    if (!peerBound &&
        context.remembered &&
        runtimeCommitted &&
        scopeCurrent &&
        profilePresent &&
        featureAllowed) {
      peerBound = ProfileRemoteLease.instance
          .bindRememberedPeerAfterUnboundRevision(
            profile: profile,
            scope: scope,
            peerFingerprint: peerFingerprint,
            sessionId: sessionId,
          );
    }
    final leaseAllowed = peerBound
        ? ProfileRemoteLease.instance.allows(
            feature,
            scope,
            currentProfile: profile!,
            peerFingerprint: peerFingerprint,
            sessionId: sessionId,
            rateLimit:
                command != ConfigCommand.remoteTransferStart &&
                command != ConfigCommand.debrifyChannelStart &&
                command != ConfigCommand.debrifyChannelChunk,
          )
        : false;
    if (!runtimeCommitted ||
        !scopeCurrent ||
        !profilePresent ||
        !featureAllowed ||
        !peerBound ||
        !leaseAllowed) {
      debugPrint('RemoteCommandRouter: local profile authorization required');
      final completeRequestId = command == ConfigCommand.complete
          ? parseRemoteTransferRequestBody(data)?.requestId ??
                _addonTransferRequestId(data)
          : null;
      final channelRequestId = command == ConfigCommand.debrifyChannel
          ? parseRemoteChannelTransferBody(data ?? '')?.requestId
          : command == ConfigCommand.debrifyChannelStart
          ? parseChunkResultRequestId(data)
          : null;
      final startRequestId = command == ConfigCommand.remoteTransferStart
          ? parseRemoteTransferRequestBody(data)?.requestId
          : null;
      final profileGraphRequestId = command == ConfigCommand.profileGraph
          ? data == null
                ? null
                : await Isolate.run(() => _profileGraphRequestId(data))
          : command == ConfigCommand.debrifyChannelStart &&
                parseChunkResultCommand(data) == ConfigCommand.profileGraph
          ? parseChunkResultRequestId(data)
          : null;
      if (action == RemoteAction.config &&
          (command == ConfigCommand.profileGraph ||
              (command == ConfigCommand.debrifyChannelStart &&
                  parseChunkResultCommand(data) ==
                      ConfigCommand.profileGraph))) {
        RemoteTransferDiagnostics.record(
          'receiver_graph_authorization_rejected',
          fields: <String, Object?>{
            'trace': RemoteTransferDiagnostics.traceToken(
              profileGraphRequestId,
            ),
            'runtimeCommitted': runtimeCommitted,
            'scopeCurrent': scopeCurrent,
            'profilePresent': profilePresent,
            'featureAllowed': featureAllowed,
            'peerBound': peerBound,
            'leaseAllowed': leaseAllowed,
          },
        );
      }
      if (action == RemoteAction.config && profileGraphRequestId != null) {
        unawaited(
          _reportProfileGraphResultBestEffort(
            context,
            requestId: profileGraphRequestId,
            ok: false,
            message: 'TV profile authorization is required',
          ),
        );
      } else if (action == RemoteAction.config && completeRequestId != null) {
        unawaited(
          _reportCompleteTransferResultBestEffort(
            context,
            data,
            ok: false,
            message: 'TV profile authorization is required',
          ),
        );
      } else if (action == RemoteAction.config && channelRequestId != null) {
        unawaited(
          _reportRemoteTransferResultBestEffort(
            context,
            requestId: channelRequestId,
            ok: false,
            message: 'TV profile authorization is required',
          ),
        );
      } else if (action == RemoteAction.config && startRequestId != null) {
        unawaited(
          _reportRemoteTransferResultBestEffort(
            context,
            requestId: startRequestId,
            ok: false,
            message: 'TV profile authorization is required',
          ),
        );
      } else {
        unawaited(context.reject?.call('profile_authorization_required'));
      }
      return;
    }
    await _dispatchAuthorized(
      action,
      command,
      data,
      context,
      profileBinding: _ProfileCommandBinding(
        scope: scope,
        authorizationRevision: profile.authorizationRevision,
      ),
    );
  }

  Future<void> _dispatchAuthorized(
    String action,
    String command,
    String? data,
    RemoteCommandContext context, {
    _ProfileCommandBinding? profileBinding,
  }) async {
    // Suppress per-chunk logs to avoid flooding
    final isChunk = command == ConfigCommand.debrifyChannelChunk;
    if (!isChunk) {
      debugPrint('RemoteCommandRouter: dispatching authorized command');
    }

    // Observer handlers (onboarding progress etc.) hear about config/addon
    // traffic only once it PASSES the authorization gates below — an
    // unsolicited or user-denied packet must not make onboarding report
    // "settings received".
    if (action != RemoteAction.config && action != RemoteAction.addon) {
      _notifyHandlers(action, command, data);
    }

    // Handle addon commands (TV side)
    if (action == RemoteAction.addon) {
      await _handleAddonCommand(
        command,
        data,
        context: context,
        profileBinding: profileBinding,
      );
      return;
    }

    // Handle text input commands (TV side)
    if (action == RemoteAction.text) {
      await _handleTextCommand(command, data);
      return;
    }

    // Handle config commands (TV side)
    if (action == RemoteAction.config) {
      await _handleConfigCommand(
        command,
        data,
        context: context,
        profileBinding: profileBinding,
      );
      return;
    }

    // Also try to use the focus system for navigation
    _tryFocusNavigation(action, command);
  }

  /// Handle addon commands on TV
  Future<void> _handleAddonCommand(
    String command,
    String? data, {
    RemoteCommandContext context = RemoteCommandContext.plaintext,
    _ProfileCommandBinding? profileBinding,
  }) async {
    if (command == AddonCommand.install && data != null) {
      final manifestUrl = _remoteTransferItemPayload(
        RemoteAction.addon,
        data,
        context,
      );
      if (manifestUrl == null) return;
      // Same trust rule as config: an unauthorized encrypted send was already
      // bounced at the session layer; plaintext (v1 phone) needs the user to
      // approve it on this screen first.
      if (!context.authorized) {
        if (_legacyApprovedFor(context.sourceIp)) {
          _markAuthorizedConfigActivity();
        } else {
          _enqueueLegacy(
            _LegacyItem.addon(command, manifestUrl),
            context.sourceIp,
          );
          return;
        }
      }
      _markAuthorizedConfigActivity();
      _recordRemoteTransferCommand(RemoteAction.addon, context);
      if (ProfileRuntime.isInitialized && ProfileRuntime.isProfileCommitted) {
        final payload = _profilePayload(context, profileBinding);
        if (payload == null) return;
        final addons =
            (payload['addonManifestUrls'] as List<String>?) ?? <String>[];
        if (!addons.contains(manifestUrl)) addons.add(manifestUrl);
        payload['addonManifestUrls'] = addons;
        if (!_profilePayloadWithinLimit(payload)) return;
        _showSnackBar('Addon staged for profile import');
        return;
      }
      _notifyHandlers(RemoteAction.addon, command, manifestUrl);
      // Addons ride the SAME phone import as the config packets (one command
      // per addon), so they join the same collecting window — otherwise a
      // ten-addon setup still parades ten snackbars past.
      _beginOrExtendBatch();
      debugPrint('RemoteCommandRouter: installing addon');
      await _trackConfigWork(() async {
        try {
          final addon = await StremioService.instance.addAddon(manifestUrl);
          debugPrint('RemoteCommandRouter: addon installed');
          _showSnackBar('Addon installed: ${addon.name}');
        } catch (_) {
          debugPrint('RemoteCommandRouter: addon install failed');
          _showSnackBar('Failed to install addon', isError: true);
        }
      }());
    }
  }

  /// Handle text input commands on TV
  Future<void> _handleTextCommand(String command, String? data) async {
    if (!Platform.isAndroid) {
      debugPrint('RemoteCommandRouter: Text input only supported on Android');
      return;
    }

    try {
      switch (command) {
        case TextCommand.type:
          if (data != null && data.isNotEmpty) {
            await _channel.invokeMethod('injectText', {'text': data});
            debugPrint('RemoteCommandRouter: injected text');
          }
          break;
        case TextCommand.backspace:
          // Send backspace key event
          await _channel.invokeMethod('injectKeyEvent', {
            'keyCode': 67,
          }); // KEYCODE_DEL
          debugPrint('RemoteCommandRouter: Injected backspace');
          break;
        case TextCommand.clear:
          // Select all (Ctrl+A) then delete
          await _channel.invokeMethod('injectText', {
            'text': '',
            'clear': true,
          });
          debugPrint('RemoteCommandRouter: Cleared text field');
          break;
        case TextCommand.enter:
          // Send KEYCODE_ENTER (66) - same as keyboard's Done/Enter button
          await _channel.invokeMethod('injectKeyEvent', {'keyCode': 66});
          debugPrint('RemoteCommandRouter: Injected enter key');
          break;
      }
    } catch (_) {
      debugPrint('RemoteCommandRouter: text command failed');
    }
  }

  // ── credential-write gating ──────────────────────────────────────────────
  //
  // Nothing that writes credentials or config applies silently anymore. The
  // trust ladder: an AUTHORIZED encrypted session (pairing code entered once,
  // or a remembered phone) applies directly; encrypted-but-unauthorized was
  // already bounced at the session layer; PLAINTEXT (a v1 phone) is buffered
  // and needs an explicit Allow on this screen — approval then covers the
  // rest of the burst.

  static const Duration _authorizedActivityWindow = Duration(minutes: 10);
  static const Duration _legacyBufferExpiry = Duration(seconds: 60);
  static const int _legacyBufferCap = 200;

  DateTime? _lastAuthorizedConfigAt;
  DateTime? _legacyApprovedAt;

  /// Both the pending buffer and a granted approval belong to ONE datagram
  /// source. Anything else on the LAN that talks while a consent is pending
  /// (or approved) is a different device and gets its own gate — approving
  /// your old phone must never blanket every host on the network.
  String? _legacyApprovedIp;
  String? _legacyPeerIp;
  final List<_LegacyItem> _legacyBuffer = [];
  Timer? _legacyExpiryTimer;
  bool _legacyDialogShowing = false;
  BuildContext? _legacyDialogContext;

  void _markAuthorizedConfigActivity() {
    _lastAuthorizedConfigAt = DateTime.now();
  }

  /// Tests simulate a transfer's `complete` without the config packets that
  /// precede it in the real flow — this stands in for those packets.
  @visibleForTesting
  void debugMarkAuthorizedConfigActivity() => _markAuthorizedConfigActivity();

  bool _legacyApprovedFor(String? sourceIp) {
    final approvedAt = _legacyApprovedAt;
    return sourceIp != null &&
        sourceIp == _legacyApprovedIp &&
        approvedAt != null &&
        DateTime.now().difference(approvedAt) < _authorizedActivityWindow;
  }

  // A pre-v2 phone cannot complete the handshake a committed profile install
  // requires, so every packet it sends is dropped — and because `reject` is
  // deliberately absent for plaintext, it is dropped in SILENCE. The phone
  // still discovers this TV and still looks connected, so the only symptom is
  // a remote that does nothing. Count drops per datagram source and name the
  // one thing the user can act on.

  static const int _staleRemoteNoticeThreshold = 3;
  static const Duration _staleRemoteBurstWindow = Duration(seconds: 10);
  static const Duration _staleRemoteNoticeCooldown = Duration(minutes: 10);
  static const int _staleRemoteTrackedSourceCap = 8;

  final Map<String, _StaleRemoteSource> _staleRemoteSources = {};
  int _staleRemoteNoticeCount = 0;

  /// Surface the only actionable cause of a silent drop: a phone app too old
  /// to pair. PLAINTEXT only — an encrypted peer that is merely unauthorized
  /// is a CURRENT app that has not paired yet, and it already gets a real
  /// rejection plus the pairing UI; telling that user to update would send
  /// them the wrong way. One stray datagram is not a stuck remote either, so
  /// the notice waits for a burst from a single source.
  void _noteUnauthenticatedDrop(RemoteCommandContext context) {
    if (context.encrypted) return;
    final sourceIp = context.sourceIp;
    if (sourceIp == null) return;
    final now = DateTime.now();

    // A source that has been quiet longer than the cooldown is forgotten
    // outright, so a phone that returns later earns a fresh notice rather
    // than inheriting a spent one.
    _staleRemoteSources.removeWhere(
      (_, source) =>
          now.difference(source.lastDropAt) > _staleRemoteNoticeCooldown,
    );
    if (!_staleRemoteSources.containsKey(sourceIp) &&
        _staleRemoteSources.length >= _staleRemoteTrackedSourceCap) {
      // LAN noise must never grow this map without bound; evict the coldest.
      String? coldestIp;
      DateTime? coldest;
      for (final entry in _staleRemoteSources.entries) {
        if (coldest == null || entry.value.lastDropAt.isBefore(coldest)) {
          coldest = entry.value.lastDropAt;
          coldestIp = entry.key;
        }
      }
      if (coldestIp != null) _staleRemoteSources.remove(coldestIp);
    }

    final source = _staleRemoteSources.putIfAbsent(
      sourceIp,
      () => _StaleRemoteSource(now),
    );
    if (now.difference(source.burstStartedAt) > _staleRemoteBurstWindow) {
      source.drops = 0;
      source.burstStartedAt = now;
    }
    source.drops++;
    source.lastDropAt = now;
    if (source.drops < _staleRemoteNoticeThreshold) return;

    final noticedAt = source.noticedAt;
    if (noticedAt != null &&
        now.difference(noticedAt) < _staleRemoteNoticeCooldown) {
      return;
    }
    source.noticedAt = now;
    source.drops = 0;
    source.burstStartedAt = now;
    _staleRemoteNoticeCount++;
    // Deliberately NOT _showSnackBar: this is a standalone warning and must
    // not be swallowed into an unrelated config batch's summary.
    _showSnackBarNow(
      'Update your phone app to use the remote',
      isError: true,
      duration: const Duration(seconds: 6),
    );
  }

  /// One-time banner when a remembered phone was silently re-authorized.
  void notifyRememberedAutoAuth(String peerName) {
    _showSnackBar('Receiving from remembered device "$peerName"');
  }

  /// Handle config commands on TV (credentials/setup from phone)
  Future<void> _handleConfigCommand(
    String command,
    String? data, {
    RemoteCommandContext context = RemoteCommandContext.plaintext,
    _ProfileCommandBinding? profileBinding,
  }) async {
    if (command != ConfigCommand.debrifyChannelChunk) {
      debugPrint('RemoteCommandRouter: Handling config command: $command');
    }

    if (command == ConfigCommand.remoteTransferStart) {
      if (data == null || !_openRemoteTransfer(data, context)) {
        final requestId = parseRemoteTransferRequestBody(data)?.requestId;
        await _reportRemoteTransferResultBestEffort(
          context,
          requestId: requestId,
          ok: false,
          message: 'The TV could not start the configuration transfer',
        );
      }
      return;
    }

    // Handle complete signal (doesn't need data)
    if (command == ConfigCommand.complete) {
      final transferRequest = parseRemoteTransferRequestBody(data);
      final cachedOutcome = transferRequest == null
          ? null
          : _remoteTransferOutcomes[transferRequest.requestId];
      if (cachedOutcome != null &&
          DateTime.now().difference(cachedOutcome.completedAt) <=
              _remoteTransferOutcomeLifetime) {
        await _reportRemoteTransferResultBestEffort(
          context,
          requestId: transferRequest!.requestId,
          ok: cachedOutcome.ok,
          message: cachedOutcome.message,
        );
        return;
      }
      final transferRequestId = transferRequest?.requestId;
      if (transferRequestId != null &&
          !_remoteTransfersInFlight.add(transferRequestId)) {
        return;
      }
      try {
        // `complete` can mark onboarding done and RESTART THE APP — honoring an
        // unsolicited one is a LAN denial-of-service. It only counts after
        // authorized config work landed recently over an approved transport.
        final approvedTransport =
            context.authorized || _legacyApprovedFor(context.sourceIp);
        final lastWork = _lastAuthorizedConfigAt;
        final recentWork =
            lastWork != null &&
            DateTime.now().difference(lastWork) < _authorizedActivityWindow;
        if (!approvedTransport || !recentWork) {
          // A v1 phone fires its whole burst — complete included — before the
          // user can possibly answer the consent dialog. Park the signal with
          // the burst; Allow replays it after the items, Deny drops it. Only a
          // complete from the SAME source as the pending burst qualifies —
          // anything else is unsolicited.
          if ((_legacyBuffer.isNotEmpty || _legacyDialogShowing) &&
              context.sourceIp != null &&
              context.sourceIp == _legacyPeerIp) {
            _enqueueLegacy(const _LegacyItem.complete(), context.sourceIp);
            return;
          }
          debugPrint(
            'RemoteCommandRouter: Ignoring unsolicited complete signal',
          );
          await _reportCompleteTransferResultBestEffort(
            context,
            data,
            ok: false,
            message: 'The TV rejected the transfer completion',
          );
          return;
        }
        // Readiness is receiver-owned. Commands that arrived before this
        // packet may still be awaiting profile authorization, and chunk gaps
        // are not requested until the receiver's repair stall elapses. Drain
        // both phases before deciding whether the manifest is incomplete.
        await _awaitInFlightConfigWork();
        if (transferRequest != null &&
            !_activeRemoteTransferContainsExpected(
              transferRequest.requestId,
              transferRequest.expected,
              context,
            )) {
          // A delayed completion from an interrupted request must not erase
          // the newer transaction that currently owns the staging buffer.
          if (_activeRemoteTransferMatches(
            transferRequest.requestId,
            context,
          )) {
            clearProfileTransferBuffer();
          }
          await _reportRemoteTransferResultBestEffort(
            context,
            requestId: transferRequest.requestId,
            ok: false,
            message: 'Some configuration packets did not reach the TV',
          );
          _showSnackBar(
            'Configuration transfer was incomplete — send it again',
            isError: true,
          );
          return;
        }
        if (ProfileRuntime.isInitialized && ProfileRuntime.isProfileCommitted) {
          if (transferRequest != null &&
              !_profilePayloadContainsExpected(transferRequest.expected)) {
            clearProfileTransferBuffer();
            await _reportRemoteTransferResultBestEffort(
              context,
              requestId: transferRequest.requestId,
              ok: false,
              message: 'Some configuration packets did not reach the TV',
            );
            _showSnackBar(
              'Configuration transfer was incomplete — send it again',
              isError: true,
            );
            return;
          }
          final wasOnboarding =
              !(await StorageService.isInitialSetupComplete());
          final applied = await _commitProfileRemotePayload(
            context,
            profileBinding,
          );
          await _reportCompleteTransferResultBestEffort(
            context,
            data,
            ok: applied,
            message: applied
                ? 'Configuration applied on TV'
                : 'The TV did not apply the configuration',
          );
          if (wasOnboarding && applied) {
            _notifyHandlers(RemoteAction.config, command, data);
            await _handleConfigComplete(wasOnboardingOverride: true);
          }
          return;
        }
        _notifyHandlers(RemoteAction.config, command, data);
        // Imports run as their packets arrive, and this signal restarts the app
        // moments later. A large IPTV list is hundreds of SQLite writes, so
        // restarting without waiting would leave it half-imported.
        final applied = _batchFailed.isEmpty && _batchOk.isNotEmpty;
        await _reportCompleteTransferResultBestEffort(
          context,
          data,
          ok: applied,
          message: applied
              ? 'Configuration applied on TV'
              : 'Some configuration items failed on TV',
        );
        await _handleConfigComplete();
      } finally {
        if (transferRequestId != null) {
          _remoteTransfersInFlight.remove(transferRequestId);
          if (_activeRemoteTransferRequestId == transferRequestId) {
            _clearActiveRemoteTransfer();
          }
        }
      }
      return;
    }

    if (data == null) {
      debugPrint('RemoteCommandRouter: Config command missing data');
      return;
    }

    // Gap repair for an outbound chunk transfer. Defense-in-depth only:
    // RemoteControlState._dispatch consumes every need before the role
    // callbacks that feed this router, so in production this branch is
    // unreachable — it exists so a future dispatch refactor cannot silently
    // turn repair requests into staged-import categories below. Same guards
    // as the live path: authorized encrypted session + requester binding.
    if (command == ConfigCommand.debrifyChannelNeed) {
      final requesterIp = context.sourceIp;
      if (context.encrypted && context.authorized && requesterIp != null) {
        final need = parseChunkNeedBody(data);
        if (need != null) {
          await ChunkResendCache.resend(
            RemoteControlState(),
            need.transferId,
            need.missing,
            requesterIp: requesterIp,
          );
        }
      }
      return;
    }

    final commandData = _remoteTransferItemPayload(command, data, context);
    if (commandData == null) return;

    // Chunk-transport packets only file bytes into a buffer — the payload
    // they carry hits these gates again when it replays after reassembly.
    final isTransport =
        command == ConfigCommand.debrifyChannelStart ||
        command == ConfigCommand.debrifyChannelChunk;
    if (!isTransport && !context.authorized) {
      if (_legacyApprovedFor(context.sourceIp)) {
        _markAuthorizedConfigActivity();
      } else {
        _enqueueLegacy(
          _LegacyItem.config(command, commandData),
          context.sourceIp,
        );
        return;
      }
    } else if (!isTransport) {
      _markAuthorizedConfigActivity();
    }

    _recordRemoteTransferCommand(command, context);

    if (ProfileRuntime.isInitialized &&
        ProfileRuntime.isProfileCommitted &&
        !isTransport &&
        // An avatar is not setup data — it applies immediately below rather
        // than joining the staged import payload.
        command != ConfigCommand.profileAvatar &&
        // Debrify TV channels are repository data, not connection secrets:
        // there is no staging category or restore adapter for them, so this
        // gate used to feed them into a FormatException that was swallowed —
        // channels sent to a profiles TV VANISHED while both sides reported
        // success. They import directly into the active profile's channel
        // repository, exactly as the pre-profiles path did; the transport is
        // already authorized and encrypted at this point.
        command != ConfigCommand.debrifyChannel &&
        // A profile graph is its own atomic import path (restoreDeviceGraph)
        // with its own confirmation — never a staged category.
        command != ConfigCommand.profileGraph) {
      if (!_bufferProfileConfig(
        command,
        commandData,
        context,
        profileBinding,
      )) {
        return;
      }
      _showSnackBar('Configuration staged for profile import');
      return;
    }

    // Past the gates — NOW the observers may hear about it.
    _notifyHandlers(RemoteAction.config, command, commandData);

    // Opened BEFORE the work starts, so the snackbar that work raises when it
    // finishes is banked rather than shown.
    _beginOrExtendBatch();
    await _trackConfigWork(
      _dispatchConfigCommand(
        command,
        commandData,
        context: context,
        profileBinding: profileBinding,
      ),
    );
  }

  /// A complete profile graph pushed from a paired Admin phone — the file
  /// restore's deviceGraph path over the wire. The session AEAD stands in
  /// for the backup passphrase, the ACTIVE TV profile must hold the same
  /// authority a file restore demands, and the user confirms on-screen
  /// before anything is created. Never staged: it applies atomically through
  /// [ProfileRestoreCoordinator.restoreDeviceGraph] or not at all.
  /// Reports a profile-graph transfer's real outcome back to the sender —
  /// delivery is not application, and without this the phone's "sent" toast
  /// was a lie whenever the TV refused or the user declined.
  Future<bool> _reportProfileGraphResult(
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

  Future<bool> _runBestEffortProfileGraphResult(
    Future<bool> Function() send,
  ) async {
    try {
      return await send();
    } catch (_) {
      return false;
    }
  }

  @visibleForTesting
  Future<bool> debugRunBestEffortProfileGraphResult(
    Future<bool> Function() send,
  ) => _runBestEffortProfileGraphResult(send);

  Future<bool> _reportProfileGraphResultBestEffort(
    RemoteCommandContext remoteContext, {
    required String? requestId,
    required bool ok,
    required String message,
  }) {
    return _runBestEffortProfileGraphResult(
      () => _reportProfileGraphResult(
        remoteContext,
        requestId: requestId,
        ok: ok,
        message: message,
      ),
    );
  }

  String? _addonTransferRequestId(String? data) {
    if (data == null || data.isEmpty || data.length > 128) return null;
    return data;
  }

  Future<bool> _reportAddonTransferResultBestEffort(
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

  Future<bool> _reportRemoteTransferResultBestEffort(
    RemoteCommandContext remoteContext, {
    required String? requestId,
    required bool ok,
    required String message,
  }) async {
    if (requestId == null) return false;
    final now = DateTime.now();
    _remoteTransferOutcomes.removeWhere(
      (_, outcome) =>
          now.difference(outcome.completedAt) > _remoteTransferOutcomeLifetime,
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

  Future<bool> _reportCompleteTransferResultBestEffort(
    RemoteCommandContext remoteContext,
    String? data, {
    required bool ok,
    required String message,
  }) {
    final remoteRequest = parseRemoteTransferRequestBody(data);
    if (remoteRequest != null) {
      return _reportRemoteTransferResultBestEffort(
        remoteContext,
        requestId: remoteRequest.requestId,
        ok: ok,
        message: message,
      );
    }
    return _reportAddonTransferResultBestEffort(
      remoteContext,
      requestId: _addonTransferRequestId(data),
      ok: ok,
    );
  }

  static String? _profileGraphRequestId(String data) {
    try {
      final decoded = jsonDecode(data);
      if (decoded is! Map) return null;
      if (decoded['format'] == 'debrify-profile-transport') {
        final requestId = decoded['requestId'];
        return requestId is String &&
                requestId.isNotEmpty &&
                requestId.length <= 128
            ? requestId
            : null;
      }
      final omissions = decoded['omissions'];
      if (omissions is! Map) return null;
      final requestId = omissions[kProfileGraphRequestIdOmission];
      if (requestId is! String || requestId.isEmpty || requestId.length > 128) {
        return null;
      }
      return requestId;
    } catch (_) {
      return null;
    }
  }

  Future<void> _handleProfileGraphConfig(
    String data,
    RemoteCommandContext remoteContext,
  ) async {
    // A graph may be ten megabytes. Correlation must not perform a full JSON
    // parse on the TV's UI isolate before the package decoder gets its own
    // worker-isolate pass below.
    final requestId = await Isolate.run(() => _profileGraphRequestId(data));
    final trace = RemoteTransferDiagnostics.traceToken(requestId);
    RemoteTransferDiagnostics.record(
      'receiver_graph_arrived',
      fields: <String, Object?>{
        'trace': trace,
        'characters': data.length,
        'encrypted': remoteContext.encrypted,
        'authorized': remoteContext.authorized,
      },
    );
    if (!remoteContext.encrypted || !remoteContext.authorized) {
      RemoteTransferDiagnostics.record(
        'receiver_graph_session_rejected',
        fields: <String, Object?>{'trace': trace},
      );
      debugPrint(
        'RemoteCommandRouter: profile graph requires an authorized session',
      );
      return;
    }
    // One import at a time: a phone re-sending while the confirm dialog is
    // still up must not stack a second dialog and duplicate the whole graph.
    if (_profileGraphInFlight) {
      RemoteTransferDiagnostics.record(
        'receiver_graph_already_in_flight',
        fields: <String, Object?>{'trace': trace},
      );
      _showSnackBar('A profile import is already in progress', isError: true);
      await _reportProfileGraphResult(
        remoteContext,
        requestId: requestId,
        ok: false,
        message: 'The TV is already importing profiles — wait for it',
      );
      return;
    }
    _profileGraphInFlight = true;
    try {
      await _handleProfileGraphConfigInner(
        data,
        remoteContext,
        requestId: requestId,
      );
    } catch (error) {
      RemoteTransferDiagnostics.record(
        'receiver_graph_unhandled_exception',
        fields: <String, Object?>{
          'trace': trace,
          'errorType': error.runtimeType,
        },
      );
      rethrow;
    } finally {
      _profileGraphInFlight = false;
    }
  }

  bool _profileGraphInFlight = false;

  Future<void> _handleProfileGraphConfigInner(
    String data,
    RemoteCommandContext remoteContext, {
    required String? requestId,
  }) async {
    final trace = RemoteTransferDiagnostics.traceToken(requestId);
    if (!ProfileRuntime.isInitialized || !ProfileRuntime.isProfileCommitted) {
      RemoteTransferDiagnostics.record(
        'receiver_graph_profiles_unavailable',
        fields: <String, Object?>{'trace': trace},
      );
      _showSnackBar(
        'Profiles are not set up on this device yet — finish setup first',
        isError: true,
      );
      await _reportProfileGraphResult(
        remoteContext,
        requestId: requestId,
        ok: false,
        message: 'Finish setting up the TV, then resend',
      );
      return;
    }
    final PortableProfilePackage package;
    final decodeWatch = Stopwatch()..start();
    RemoteTransferDiagnostics.record(
      'receiver_decode_start',
      fields: <String, Object?>{'trace': trace, 'characters': data.length},
    );
    try {
      // Off-main: a 10 MB parse + digest would freeze TV hardware for
      // seconds on the UI isolate.
      package = await PortableProfilePackage.decodeAuthenticatedJson(
        data,
        maxExpandedPayloadBytes: kMaxProfileGraphExpandedBytes,
      );
      if (package.mode != 'deviceGraph') {
        throw const FormatException('Not a profile graph package');
      }
    } on FormatException catch (error) {
      RemoteTransferDiagnostics.record(
        'receiver_decode_rejected',
        fields: <String, Object?>{
          'trace': trace,
          'errorType': error.runtimeType,
          'elapsedMs': decodeWatch.elapsedMilliseconds,
        },
      );
      _showSnackBar(
        'Profile transfer rejected: ${error.message}',
        isError: true,
      );
      await _reportProfileGraphResult(
        remoteContext,
        requestId: requestId,
        ok: false,
        message: 'The TV rejected the package: ${error.message}',
      );
      return;
    } catch (error) {
      RemoteTransferDiagnostics.record(
        'receiver_decode_exception',
        fields: <String, Object?>{
          'trace': trace,
          'errorType': error.runtimeType,
          'elapsedMs': decodeWatch.elapsedMilliseconds,
        },
      );
      rethrow;
    }
    RemoteTransferDiagnostics.record(
      'receiver_decode_complete',
      fields: <String, Object?>{
        'trace': trace,
        'profiles': package.profiles.length,
        'resources': package.resources.length,
        'sections': package.sections.length,
        'elapsedMs': decodeWatch.elapsedMilliseconds,
      },
    );
    final registry = ProfileBootstrap.registry;
    final authorization = await ProfileAuthorizationContext.capture(registry);
    final UserProfile actor;
    try {
      actor = await authorization.validate(registry);
    } catch (error) {
      RemoteTransferDiagnostics.record(
        'receiver_graph_authorization_expired',
        fields: <String, Object?>{
          'trace': trace,
          'errorType': error.runtimeType,
        },
      );
      _showSnackBar('Profile import authorization expired', isError: true);
      await _reportProfileGraphResult(
        remoteContext,
        requestId: requestId,
        ok: false,
        message: 'TV profile authorization expired — resend',
      );
      return;
    }
    if (actor.role != UserProfileRole.admin ||
        !actor.allows(ProfileFeature.manageProfiles) ||
        !actor.allows(ProfileFeature.backupRestore)) {
      RemoteTransferDiagnostics.record(
        'receiver_graph_admin_required',
        fields: <String, Object?>{'trace': trace},
      );
      _showSnackBar(
        'Switch this TV to an Admin profile to receive profiles',
        isError: true,
      );
      await _reportProfileGraphResult(
        remoteContext,
        requestId: requestId,
        ok: false,
        message: 'Open an Admin profile on the TV, then resend',
      );
      return;
    }
    final receivingDuringOnboarding =
        !(await StorageService.isInitialSetupComplete());
    final context = _navigatorKey?.currentContext;
    if (context == null || !context.mounted) {
      RemoteTransferDiagnostics.record(
        'receiver_graph_screen_unavailable',
        fields: <String, Object?>{'trace': trace},
      );
      _showSnackBar('Profile import needs the app screen open', isError: true);
      await _reportProfileGraphResult(
        remoteContext,
        requestId: requestId,
        ok: false,
        message: 'Open the Debrify screen on the TV, then resend',
      );
      return;
    }
    final sender =
        remoteContext.peerName ?? remoteContext.sourceIp ?? 'a paired phone';
    final rebuildableCachesOmitted = package.omissions.containsKey(
      'rebuildableDatabaseCachesOmitted',
    );
    final debrifyTvOmission = DebrifyTvBackupOmission.fromOmissions(
      package.omissions,
    );
    RemoteTransferDiagnostics.record(
      'receiver_confirmation_shown',
      fields: <String, Object?>{
        'trace': trace,
        'profiles': package.profiles.length,
        'cacheCompacted': rebuildableCachesOmitted,
        'debrifyTvChannelsOmitted': debrifyTvOmission?.channels ?? 0,
        'debrifyTvHashesOmitted': debrifyTvOmission?.savedHashes ?? 0,
      },
    );
    final confirmed =
        await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: Text('Import ${package.profiles.length} profiles?'),
            content: Text(
              'From: $sender\n\n'
              'The profiles and their shared connections are staged under '
              'new IDs, then made visible together. Existing profiles are '
              'not overwritten; only the unused automatic setup profile is '
              'removed. Profiles keep their PINs when the transfer '
              'carries them.'
              '${debrifyTvOmission?.isEmpty == false ? '\n\nDebrify TV was '
                        'excluded when this transfer was compacted '
                        '(${debrifyTvOmission!.contentsLabel}). No empty '
                        'channels will be created. After importing, restore '
                        'a channel ZIP from Debrify TV → Import → From '
                        'storage, or send them separately with Remote → '
                        'Debrify TV Channels.' : ''}'
              '${rebuildableCachesOmitted ? '\n\nRebuildable catalog and EPG '
                        'caches were compacted for transport. Playlists, '
                        'favorites, history, numbering, and settings are '
                        'included.' : ''}',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                autofocus: true,
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Import profiles'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) {
      RemoteTransferDiagnostics.record(
        'receiver_confirmation_declined',
        fields: <String, Object?>{'trace': trace},
      );
      _showSnackBar('Profile import declined');
      await _reportProfileGraphResult(
        remoteContext,
        requestId: requestId,
        ok: false,
        message: 'Declined on the TV',
      );
      return;
    }
    RemoteTransferDiagnostics.record(
      'receiver_confirmation_accepted',
      fields: <String, Object?>{'trace': trace},
    );
    // Busy dialog while the restore stages and verifies. Self-dismissing via
    // its own context — the router must never pop someone else's route.
    final done = ValueNotifier<bool>(false);
    if (context.mounted) {
      unawaited(
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) =>
              _RouterBusyDialog(message: 'Importing profiles…', done: done),
        ),
      );
    }
    try {
      final ProfileGraphRestoreReport report;
      final restoreWatch = Stopwatch()..start();
      RemoteTransferDiagnostics.record(
        'receiver_restore_start',
        fields: <String, Object?>{'trace': trace},
      );
      try {
        report = await ProfileRestoreCoordinator(
          registry: registry,
          cipher: DeviceKeyProvider.cipher,
          lifecycleParticipants: <ProfileLifecycleParticipant>[
            ProfileAppLifecycleParticipant(),
          ],
        ).restoreDeviceGraph(package: package, authorization: authorization);
      } catch (error) {
        RemoteTransferDiagnostics.record(
          'receiver_restore_exception',
          fields: <String, Object?>{
            'trace': trace,
            'errorType': error.runtimeType,
            'elapsedMs': restoreWatch.elapsedMilliseconds,
          },
        );
        debugPrint('RemoteCommandRouter: profile graph restore failed');
        _showSnackBar(
          'Profile import failed; existing data is unchanged',
          isError: true,
        );
        await _reportProfileGraphResultBestEffort(
          remoteContext,
          requestId: requestId,
          ok: false,
          message: 'Import failed on the TV; nothing was changed there',
        );
        return;
      }
      RemoteTransferDiagnostics.record(
        'receiver_restore_complete',
        fields: <String, Object?>{
          'trace': trace,
          'profiles': report.profilesImported,
          'resources': report.resourcesImported,
          'pinResets': report.pinResetsRequired,
          'elapsedMs': restoreWatch.elapsedMilliseconds,
        },
      );

      // The restore is durable at this point. A result-send or onboarding
      // hand-off failure must never fall through to the restore-failed path
      // and invite the sender to create a duplicate graph. Acknowledge while
      // the Admin that authorized the inbound transfer is still active; an
      // imported Admin may legitimately have remote features disabled.
      final acknowledged = await _reportProfileGraphResultBestEffort(
        remoteContext,
        requestId: requestId,
        ok: true,
        message:
            'TV imported ${report.profilesImported} profiles and '
            '${report.resourcesImported} connections'
            '${debrifyTvOmission?.isEmpty == false ? '; Debrify TV channels were not included' : ''}',
      );
      if (!acknowledged) {
        RemoteTransferDiagnostics.record(
          'receiver_restore_ack_missing',
          fields: <String, Object?>{'trace': trace},
        );
        debugPrint(
          'RemoteCommandRouter: imported profiles but could not report the result',
        );
      }

      if (receivingDuringOnboarding &&
          actor.id == ProfileBootstrap.freshAdminId) {
        // Retire onboarding BEFORE handing authority over. The hand-off makes
        // this a multi-profile device, so ProfileGate immediately locks the
        // newly active profile — and a locked profile cannot make the
        // active-session write that clears onboarding (the registry refuses
        // it: "Active profile session has ended"). Doing it here, while the
        // bootstrap Admin is still active and unlocked, is the only moment
        // this write is legal.
        try {
          await StorageService.setInitialSetupComplete(true);
        } catch (e) {
          debugPrint(
            'RemoteCommandRouter: could not pre-clear onboarding — $e',
          );
        }
        await handoffImportedAdminForOnboarding(report);
      }
      _showSnackBar(
        'Imported ${report.profilesImported} profiles and '
        '${report.resourcesImported} connections from $sender.'
        '${report.pinResetsRequired == 0 ? '' : ' ${report.pinResetsRequired} profile(s) need a new PIN.'}'
        '${debrifyTvOmission?.isEmpty == false ? ' Debrify TV channels were not included; import a channel ZIP or send them separately from Remote.' : ''}',
      );
      if (receivingDuringOnboarding) {
        try {
          _notifyHandlers(RemoteAction.config, ConfigCommand.complete, null);
          // Re-pinned for the same reason as the retirement above: the
          // onboarding flag and the privacy projection must be written for the
          // profile the runtime actually published, not the stale captured one.
          final live = ProfileRuntime.scope.value;
          await (live == null
              ? _handleConfigComplete(wasOnboardingOverride: true)
              : ProfileRuntime.withCapturedScope(
                  live,
                  () => _handleConfigComplete(wasOnboardingOverride: true),
                ));
        } catch (e, stack) {
          // The graph is already published and the sender has its success
          // result. Never turn a post-import navigation failure into a second,
          // contradictory "nothing changed" result. Log the cause: a silent
          // throw here strands the user on the onboarding screen with a fully
          // imported device behind it, which is indistinguishable from the
          // restart never being wired up.
          debugPrint(
            'RemoteCommandRouter: imported profiles but could not leave '
            'onboarding — $e\n$stack',
          );
        }
      }
    } finally {
      done.value = true;
    }
  }

  /// Move authority to an imported usable Admin after an onboarding restore,
  /// then retire the bootstrap setup profile it replaced.
  ///
  /// The setup profile used to be retained unconditionally, because a user may
  /// have configured services before navigating back to import and
  /// setup-incomplete is not proof the profile is disposable. That concern is
  /// now enforced precisely rather than by blanket retention — see
  /// [_retireBootstrapProfileAfterImport], which only removes a profile that
  /// owns nothing.
  Future<void> _activateImportedAdminForOnboarding(
    ProfileGraphRestoreReport report,
  ) async {
    final registry = ProfileBootstrap.registry;
    UserProfile? importedAdmin;
    for (final profileId in report.importedProfileIds) {
      final profile = await registry.getProfile(profileId);
      if (profile == null ||
          !profile.isEnabled ||
          !profile.isAdmin ||
          profile.pinResetRequired) {
        continue;
      }
      importedAdmin = profile;
      break;
    }
    if (importedAdmin == null) {
      // Nothing in the graph can take authority (disabled, non-Admin, or every
      // Admin needs a new PIN). The bootstrap Admin stays active and owns the
      // device — and is therefore never retired below.
      debugPrint(
        'RemoteCommandRouter: no usable imported Admin to hand off to',
      );
      return;
    }

    final lifecycle = ProfileLifecycleCoordinator(
      registry: registry,
      participants:
          debugOnboardingLifecycleParticipants ??
          <ProfileLifecycleParticipant>[ProfileAppLifecycleParticipant()],
    );
    try {
      await lifecycle.switchTo(
        importedAdmin.id,
        // The transfer was approved locally by the current Admin. The root
        // ProfileGate reloads and asks normally before Home.
        unlock: (_) async => true,
      );
    } catch (_) {
      // Publication already succeeded. Keep the bootstrap Admin active so the
      // restored profiles stay manageable instead of claiming the import did
      // not happen and encouraging a duplicate graph. NOTE: switchTo can also
      // throw AFTER its registry commit (a participant warm failure), in which
      // case the imported Admin IS authoritative despite the throw — which is
      // why the retire gate below asks the registry who is active instead of
      // trusting a success flag here.
      debugPrint(
        'RemoteCommandRouter: onboarding profile hand-off was deferred',
      );
    } finally {
      lifecycle.dispose();
    }
    // Only ever retire after a hand-off that actually landed: a bootstrap
    // Admin still active is the sole way into the device. The registry is the
    // authority on that — not the switchTo return path (see above).
    final activeAfterHandoff = (await registry.activeProfile())?.id;
    if (activeAfterHandoff != importedAdmin.id) {
      debugPrint(
        'RemoteCommandRouter: hand-off did not land; '
        'keeping the bootstrap setup profile',
      );
      return;
    }
    // This handler was entered under the PRE-hand-off scope, and
    // ProfileRuntime.capture() prefers an inherited zone value over the live
    // one — so everything below would otherwise still act as the bootstrap
    // Admin we are trying to retire. Re-pin to what the runtime actually
    // published so the acting profile matches the registry.
    final live = ProfileRuntime.scope.value;
    if (live == null) return;
    await ProfileRuntime.withCapturedScope(
      live,
      () => _retireBootstrapProfileAfterImport(report.importedProfileIds),
    );
  }

  /// Hands an onboarding restore to an imported usable Admin and conditionally
  /// retires the bootstrap profile. The caller must persist onboarding
  /// completion before invoking this method because switching profiles ends
  /// the authorizing bootstrap session.
  Future<void> handoffImportedAdminForOnboarding(
    ProfileGraphRestoreReport report,
  ) async {
    final activeProfileId =
        (await ProfileBootstrap.registry.activeProfile())?.id;
    if (activeProfileId != ProfileBootstrap.freshAdminId) {
      debugPrint(
        'RemoteCommandRouter: skipped onboarding profile hand-off because '
        'the bootstrap Admin is not active',
      );
      return;
    }
    await _activateImportedAdminForOnboarding(report);
  }

  /// Remove the bootstrap setup profile once an imported Admin owns the device.
  ///
  /// A profile the user actually configured before importing survives; only an
  /// untouched one is removed. That is the same protection the old
  /// unconditional retention provided, without keeping an empty "Profile 1"
  /// around forever. "Untouched" is decided in layers — identity first (a PIN
  /// or a rename proves the profile was somebody's, since ProfileResetService
  /// can send an established profile back into onboarding with both intact),
  /// then data:
  ///
  /// - Owned connections veto the delete — with ONE carve-out. On an online
  ///   first launch, AppMigrationService seeds the essential addons before
  ///   onboarding even starts, and each becomes a `stremioAddon` connection
  ///   resource owned by the bootstrap Admin — no user action involved. If
  ///   every owned connection is exactly such a seed (matched by unsealed
  ///   manifest URL against the essential set), they are deleted along with
  ///   the profile; anything else — a debrid account, a user-added addon —
  ///   keeps the veto. Without the carve-out virtually every real device
  ///   would retain the profile, since import implies being online.
  /// - Private generation files veto it ([_bootstrapProfileHasPrivateData]).
  /// - `detachPublicArtifacts: false` lets the registry refuse over public
  ///   files, and its other invariants (active profile, admin floor, shared
  ///   grants, live jobs) all still throw into the catch below.
  ///
  /// The registry checks cannot see PRIVATE generation files — search engines
  /// imported during local onboarding are YAMLs in the profile's scoped
  /// documents tree, not connection resources — so any file there also counts
  /// as "configured" and vetoes the delete ([_bootstrapProfileHasPrivateData]).
  ///
  /// Mirrors the delete sequence in ProfileRowActions — schedule, delete,
  /// erase data, complete — so a crash mid-way cannot strand generation data.
  /// A stranded schedule is self-cancelling: [ProfileCleanupLedger.resume]
  /// drops any pending entry whose profile still exists.
  Future<void> _retireBootstrapProfileAfterImport(
    List<String> importedProfileIds,
  ) async {
    final registry = ProfileBootstrap.registry;
    try {
      final bootstrap = await registry.getProfile(
        ProfileBootstrap.freshAdminId,
      );
      if (bootstrap == null) return;
      // Re-read authority from the runtime rather than trusting the switch:
      // deleteProfileWithDisposition compares the acting revision and session
      // epoch exactly, and refuses to delete the ACTIVE profile anyway.
      final actor = await ProfileAuthorizationContext.capture(registry);
      if (actor.profileId == ProfileBootstrap.freshAdminId) {
        // The registry committed the hand-off but the in-process runtime scope
        // has not caught up, so this session still acts AS the profile we are
        // about to delete — which the registry would refuse anyway.
        debugPrint(
          'RemoteCommandRouter: kept the bootstrap setup profile after import '
          '(runtime scope is still ${actor.profileId})',
        );
        return;
      }
      // The bootstrap ID alone does not prove a factory profile:
      // ProfileResetService sends an ESTABLISHED profile back into onboarding
      // with its identity, PIN, policy, and connections intact. Connections
      // and private files are vetoed below; of the rest, a PIN is the one
      // identity marker whose silent loss hurts — and no factory bootstrap
      // ever has one — so it is the cheap "was this ever somebody's profile"
      // test. A reset profile without a PIN is an empty husk its owner chose
      // to replace; retiring it is the point of this method.
      if (bootstrap.hasPin) {
        debugPrint(
          'RemoteCommandRouter: kept the bootstrap setup profile after '
          'import (it is PIN-protected)',
        );
        return;
      }
      // Same reasoning for a rename: the factory scaffold is always created
      // as [ProfileBootstrap.freshAdminName], so any other stored name was
      // chosen by a person — an established profile back in onboarding via
      // reset, not a disposable husk.
      if (bootstrap.name != ProfileBootstrap.freshAdminName) {
        debugPrint(
          'RemoteCommandRouter: kept the bootstrap setup profile after '
          'import (it was renamed)',
        );
        return;
      }
      // ProfileResetService also preserves presentation and policy. An avatar
      // is the customization a user would actually miss; a policy differing
      // from the role's defaults is a deliberate choice. Either proves the row
      // was somebody's, even with the factory name and no PIN. Deliberately
      // NOT an exhaustive field sweep — that would silently absorb every
      // future field and veto far more than it protects.
      // ProfilePolicy has no value equality, so compare the feature SET —
      // `policy != defaultsFor(role)` would compare identities, always differ,
      // and silently veto every retirement.
      final defaultPolicy = ProfilePolicy.defaultsFor(bootstrap.role);
      final policyCustomized = !const SetEquality<ProfileFeature>().equals(
        bootstrap.policy.enabled,
        defaultPolicy.enabled,
      );
      if (bootstrap.avatarKey != null || policyCustomized) {
        debugPrint(
          'RemoteCommandRouter: kept the bootstrap setup profile after '
          'import (it carries customized profile settings)',
        );
        return;
      }
      if (await _bootstrapProfileHasPrivateData()) {
        debugPrint(
          'RemoteCommandRouter: kept the bootstrap setup profile after '
          'import (it has private files)',
        );
        return;
      }
      final allResources = await registry.listAllResources();
      // INCLUDING disabled rows: listAllResources hides them, but the
      // delete-time owned-resource count does not — so reading the enabled set
      // here would classify a profile owning a disabled debrid credential as
      // "only disposable seeds" and then delete that credential unseen.
      final ownedResources = await registry.listOwnedResourcesIncludingDisabled(
        bootstrap.id,
      );
      // Anything the user configured keeps the profile. Only untouched
      // essential-addon seeds are disposable — and then they must be, or the
      // registry's owned-resource check would veto the delete instead.
      final seedUrls = ownedResources.isEmpty
          ? const <String>{}
          : await _ownedSeededAddonUrls(actor, ownedResources);
      if (seedUrls == null) {
        debugPrint(
          'RemoteCommandRouter: kept the bootstrap setup profile after '
          'import (it has configured connections)',
        );
        return;
      }
      // Seed addons are auto-granted to every profile, and only
      // freshAdminId/migratedAdminId are ever re-seeded — so a LOCAL profile
      // that predates this import (a member created before the admin was
      // reset) would lose these addons permanently if they were deleted.
      // Grants held by anyone outside this import veto the retirement;
      // grants held by the freshly imported profiles do not — they carry the
      // sender's own addons and lose nothing real.
      if (ownedResources.isNotEmpty) {
        final ownedIds = ownedResources.map((resource) => resource.id).toSet();
        final expectedBorrowers = <String>{bootstrap.id, ...importedProfileIds};
        final hasOutsideBorrower = (await registry.listAllResourceGrants()).any(
          (grant) =>
              ownedIds.contains(grant['resource_id']) &&
              !expectedBorrowers.contains(grant['profile_id']),
        );
        if (hasOutsideBorrower) {
          debugPrint(
            'RemoteCommandRouter: kept the bootstrap setup profile after '
            'import (its addons are shared with other local profiles)',
          );
          return;
        }
      }
      // Deleting a seed is only safe when the imported graph brought its own
      // copy: only freshAdminId/migratedAdminId are ever re-seeded, so a seed
      // deleted here is gone from the device for good. A sender on an older
      // build can predate one of the current essentials (the essential set
      // grows over time) — its graph then lacks that addon, and this veto
      // keeps the bootstrap so the imported profiles keep borrowing the
      // device's only copy. Fires BEFORE the revocation on purpose.
      if (seedUrls.isNotEmpty) {
        final uncovered = await _seedUrlsMissingFromImport(
          actor,
          allResources: allResources,
          importedProfileIds: importedProfileIds,
          seedUrls: seedUrls,
        );
        if (uncovered.isNotEmpty) {
          debugPrint(
            'RemoteCommandRouter: kept the bootstrap setup profile after '
            'import (the import lacks essential addons: '
            '${uncovered.join(', ')})',
          );
          return;
        }
      }
      var deleteActor = actor;
      if (ownedResources.isNotEmpty) {
        // Seeded resources are auto-granted to every profile — including the
        // freshly imported ones — and the delete-time shared==0 guard refuses
        // while any borrower grant stands. Strip them first. The revocation
        // bumps every borrower's authorization revision, the acting Admin's
        // own included (it borrows the seeds like everyone else), so the
        // delete below must run on a re-captured context.
        //
        // Accepted residual (reviewed, not worth an atomic disposition): if a
        // later step still fails, borrowers have lost their grants to seeds
        // that were about to be deleted anyway — the imported profiles carry
        // the sender's own addons — and the kept husk stays deletable from
        // Manage profiles.
        await registry.revokeGrantsOnOwnedResources(
          ownerProfileId: bootstrap.id,
          actingProfileId: actor.profileId,
          actingAuthorizationRevision: actor.authorizationRevision,
          actingSessionEpoch: actor.sessionEpoch,
        );
        deleteActor = await ProfileAuthorizationContext.capture(registry);
      }

      await ProfileCleanupLedger.scheduleProfile(bootstrap.id);
      await registry.deleteProfileWithDisposition(
        id: bootstrap.id,
        deleteOwnedResources: ownedResources.isNotEmpty,
        detachPublicArtifacts: false,
        actingProfileId: deleteActor.profileId,
        actingAuthorizationRevision: deleteActor.authorizationRevision,
        actingSessionEpoch: deleteActor.sessionEpoch,
      );
      await ProfileDataGenerationManager.deleteAllProfileData(bootstrap.id);
      await ProfileCleanupLedger.completeProfile(bootstrap.id);
      debugPrint(
        'RemoteCommandRouter: retired the bootstrap setup profile after import',
      );
    } catch (e) {
      // Configured, busy, or otherwise undeletable — keeping it is always the
      // safe outcome, and the user can still remove it from Manage profiles.
      debugPrint(
        'RemoteCommandRouter: kept the bootstrap setup profile after '
        'import — $e',
      );
    }
  }

  static const Set<String> _essentialManifestUrls = <String>{
    AppMigrationService.cinemetaManifestUrl,
    AppMigrationService.openSubtitlesManifestUrl,
    AppMigrationService.officialOpenSubtitlesManifestUrl,
    AppMigrationService.watchNextManifestUrl,
  };

  /// The unsealed manifest URLs of [ownedResources] when EVERY resource is an
  /// untouched essential-addon seed — type `stremioAddon`, manifest URL in the
  /// set AppMigrationService seeds on first launch — or null when anything
  /// else is present. Matching is by the exact URL: a user-added addon, even
  /// one sharing a seeded addon's name, has a different URL and keeps the
  /// retention veto. Any unseal failure (rotated key, disabled resource,
  /// insufficient reveal authority) throws into the caller's catch, which
  /// keeps the profile — always the safe outcome.
  Future<Set<String>?> _ownedSeededAddonUrls(
    ProfileAuthorizationContext actor,
    List<ConnectionResource> ownedResources,
  ) async {
    if (ownedResources.any(
      (resource) => resource.type != ConnectionResourceType.stremioAddon,
    )) {
      return null;
    }
    final resources = ConnectionResourceService(
      registry: ProfileBootstrap.registry,
      cipher: DeviceKeyProvider.cipher,
    );
    final urls = <String>{};
    for (final resource in ownedResources) {
      final manifestUrl = await _unsealManifestUrl(
        resources,
        actor,
        resource.id,
      );
      if (manifestUrl == null ||
          !_essentialManifestUrls.contains(manifestUrl)) {
        return null;
      }
      urls.add(manifestUrl);
    }
    return urls;
  }

  /// Which of [seedUrls] the imported graph did NOT bring its own copy of,
  /// judged by the unsealed manifest URLs of the imported profiles' addon
  /// resources. Disabled imported addons don't count as coverage on purpose
  /// (listAllResources excludes them): an unusable copy is no substitute for
  /// the seed being deleted, and over-keeping is the safe direction.
  Future<Set<String>> _seedUrlsMissingFromImport(
    ProfileAuthorizationContext actor, {
    required List<ConnectionResource> allResources,
    required List<String> importedProfileIds,
    required Set<String> seedUrls,
  }) async {
    final importedIds = importedProfileIds.toSet();
    final resources = ConnectionResourceService(
      registry: ProfileBootstrap.registry,
      cipher: DeviceKeyProvider.cipher,
    );
    final missing = Set<String>.of(seedUrls);
    for (final resource in allResources) {
      if (missing.isEmpty) break;
      if (resource.type != ConnectionResourceType.stremioAddon ||
          !importedIds.contains(resource.ownerProfileId)) {
        continue;
      }
      final manifestUrl = await _unsealManifestUrl(
        resources,
        actor,
        resource.id,
      );
      if (manifestUrl != null) missing.remove(manifestUrl);
    }
    return missing;
  }

  static Future<String?> _unsealManifestUrl(
    ConnectionResourceService resources,
    ProfileAuthorizationContext actor,
    String resourceId,
  ) async {
    final secret = await resources.revealSecretForDeviceBackup(
      context: actor,
      resourceId: resourceId,
    );
    return (secret['manifest_url'] ?? secret['manifestUrl'])?.toString();
  }

  /// Whether the bootstrap profile holds any private file — user work the
  /// registry's resource/artifact checks cannot see (imported engine YAMLs,
  /// exports, anything under its documents area, across every generation).
  ///
  /// Prefs are deliberately NOT a signal: activation warms and defaults
  /// migrations stamp preferences on every profile unconditionally, so a
  /// prefs check would veto the delete for everyone. Only documents files
  /// require user action to exist. Empty directories don't count — the
  /// scoped-documents helper creates them on demand.
  Future<bool> _bootstrapProfileHasPrivateData() async {
    // All THREE roots the deleter erases (see
    // ProfileDataGenerationManager.deleteAllProfileData). Scanning only
    // documents would leave anything written through
    // ProfileStoragePaths.supportFile/cacheFile invisible to this veto and
    // silently deleted with the profile — latent today only because nothing
    // writes user work there yet.
    for (final root in <Directory>[
      await AppStorage.documents(),
      await AppStorage.support(),
      await AppStorage.cache(),
    ]) {
      final tree = Directory(
        p.join(root.path, 'profiles', ProfileBootstrap.freshAdminId),
      );
      if (!await tree.exists()) continue;
      final hasFile = await tree
          .list(recursive: true, followLinks: false)
          .any((entry) => entry is File);
      if (hasFile) return true;
    }
    return false;
  }

  @visibleForTesting
  Future<void> debugActivateImportedAdminForOnboarding(
    ProfileGraphRestoreReport report,
  ) => handoffImportedAdminForOnboarding(report);

  /// A picked image pushed from the paired phone, applied to the ACTIVE
  /// profile. `updateProfile` requires a managing actor, so this works only
  /// while a managing Admin is signed in — a deliberate mirror of the local
  /// rule rather than a new capability.
  Future<void> _handleProfileAvatarConfig(
    String? data,
    RemoteCommandContext context,
  ) async {
    String? requestId;
    var encoded = data;
    if (data != null && data.startsWith('{')) {
      try {
        final envelope = jsonDecode(data);
        if (envelope is! Map ||
            envelope['version'] != 1 ||
            envelope['requestId'] is! String ||
            envelope['data'] is! String) {
          throw const FormatException('Invalid avatar envelope');
        }
        requestId = envelope['requestId'] as String;
        encoded = envelope['data'] as String;
        if (requestId.isEmpty || requestId.length > 96) {
          throw const FormatException('Invalid avatar request ID');
        }
      } on FormatException {
        await _replyProfileAvatar(context, null, 'invalid');
        _showSnackBar('Avatar payload could not be read', isError: true);
        return;
      }
    }
    if (encoded == null || encoded.isEmpty) {
      await _replyProfileAvatar(context, requestId, 'invalid');
      return;
    }
    if (!ProfileRuntime.isInitialized || !ProfileRuntime.isProfileCommitted) {
      await _replyProfileAvatar(context, requestId, 'profiles_disabled');
      _showSnackBar('Profiles are not enabled on this device', isError: true);
      return;
    }
    if (!ProfileAvatarPolicy.userImagesSupported) {
      // tvOS keeps no user avatar files. The receiver refuses so that a later
      // phase cannot quietly grant what the picker denies.
      await _replyProfileAvatar(context, requestId, 'unsupported');
      _showSnackBar('This device uses built-in avatars only', isError: true);
      return;
    }
    // Static images may be larger than the stored output and are downscaled by
    // ingest, exactly like the local picker. Bound the raw input allocation,
    // not the normalized 1 MiB result.
    if (encoded.length >
        ((ProfileAvatarIngest.maxInputBytes + 2) ~/ 3) * 4 + 8) {
      await _replyProfileAvatar(context, requestId, 'too_large');
      _showSnackBar('That image is too large for an avatar', isError: true);
      return;
    }
    try {
      final registry = ProfileBootstrap.registry;
      final authorization = await ProfileAuthorizationContext.capture(registry);
      final actor = await authorization.validate(registry);
      if (actor.role != UserProfileRole.admin ||
          !actor.allows(ProfileFeature.manageProfiles)) {
        await _replyProfileAvatar(context, requestId, 'not_authorized');
        _showSnackBar(
          'Only a managing Admin profile can receive an avatar',
          isError: true,
        );
        return;
      }
      final prepared = await ProfileAvatarIngest.prepare(base64Decode(encoded));
      final avatarKey = prepared.avatar.format();
      await ProfileAvatarIngest.publish(
        registry: registry,
        profileId: actor.id,
        avatarKey: avatarKey,
        prepared: prepared,
        persist: () async {
          await registry.updateProfile(
            id: actor.id,
            avatarKey: avatarKey,
            actingProfileId: authorization.profileId,
            actingAuthorizationRevision: authorization.authorizationRevision,
            actingSessionEpoch: authorization.sessionEpoch,
          );
        },
        wasPersisted: () async =>
            (await registry.getProfile(actor.id))?.avatarKey == avatarKey,
      );
      await _replyProfileAvatar(context, requestId, 'ok');
      _showSnackBar('Profile avatar updated');
    } on ProfileAvatarRejected catch (rejected) {
      await _replyProfileAvatar(context, requestId, 'rejected');
      _showSnackBar(rejected.message, isError: true);
    } on FormatException {
      await _replyProfileAvatar(context, requestId, 'invalid');
      _showSnackBar('Avatar payload could not be read', isError: true);
    } catch (_) {
      await _replyProfileAvatar(context, requestId, 'apply_failed');
      _showSnackBar('Avatar could not be applied', isError: true);
    }
  }

  Future<void> _replyProfileAvatar(
    RemoteCommandContext context,
    String? requestId,
    String result,
  ) async {
    final reply = context.reject;
    if (reply == null) return;
    final code = requestId == null
        ? 'avatar_$result'
        : 'profile_avatar:$requestId:$result';
    for (var attempt = 0; attempt < 3; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
      try {
        await reply(code);
      } catch (_) {
        // Applying the avatar is already durable. A failed best-effort reply
        // must not fall into the outer apply-failed handler and contradict a
        // success packet that may already have reached the phone.
      }
    }
  }

  @visibleForTesting
  Future<void> debugHandleProfileAvatar(
    String? data,
    RemoteCommandContext context,
  ) => _handleProfileAvatarConfig(data, context);

  Map<String, dynamic>? _profilePayload(
    RemoteCommandContext context,
    _ProfileCommandBinding? binding,
  ) {
    if (binding == null || ProfileRuntime.capture() != binding.scope) {
      _showSnackBar('Local profile authorization changed', isError: true);
      return null;
    }
    final peer = _profilePeerKey(context);
    if (peer == null) {
      _showSnackBar('Transfer peer could not be verified', isError: true);
      return null;
    }
    final existingBinding = _profileRemoteBinding;
    if (existingBinding != null && existingBinding != binding) {
      clearProfileTransferBuffer();
    } else if (_profileRemotePeer != null && _profileRemotePeer != peer) {
      _showSnackBar('Another transfer is already pending', isError: true);
      return null;
    }
    _profileRemoteBinding = binding;
    _profileRemotePeer = peer;
    _profileRemoteExpiry?.cancel();
    _profileRemoteExpiry = Timer(
      _profileRemotePayloadLifetime,
      clearProfileTransferBuffer,
    );
    return _profileRemotePayload ??= <String, dynamic>{
      'version': BackupRestoreService.payloadVersion,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    };
  }

  bool _bufferProfileConfig(
    String command,
    String data,
    RemoteCommandContext context,
    _ProfileCommandBinding? binding,
  ) {
    final payload = _profilePayload(context, binding);
    if (payload == null) return false;
    dynamic decoded() => jsonDecode(data);
    switch (command) {
      case ConfigCommand.realDebrid:
        payload['realDebridApiKey'] = data;
        break;
      case ConfigCommand.torbox:
        payload['torboxApiKey'] = data;
        break;
      case ConfigCommand.premiumize:
        payload['premiumizeApiKey'] = data;
        break;
      case ConfigCommand.allDebrid:
        payload['allDebridApiKey'] = data;
        break;
      case ConfigCommand.pikpak:
        payload['pikpak'] = decoded();
        break;
      case ConfigCommand.trakt:
        payload['trakt'] = decoded();
        break;
      case ConfigCommand.simkl:
        payload['simkl'] = decoded();
        break;
      case ConfigCommand.mdblist:
        payload['mdblist'] = decoded();
        break;
      case ConfigCommand.trackingPreferences:
        payload['trackingPreferences'] = decoded();
        break;
      case ConfigCommand.searchEngines:
        payload['searchEngineIds'] = decoded();
        break;
      case ConfigCommand.webDav:
        payload['webDavServers'] = decoded();
        break;
      case ConfigCommand.indexerManagers:
        payload['indexerManagers'] = decoded();
        break;
      case ConfigCommand.iptvPlaylists:
        payload['iptvPlaylists'] = decoded();
        break;
      case ConfigCommand.iptvFavorites:
        payload['iptvFavorites'] = decoded();
        break;
      case ConfigCommand.iptvLists:
        payload['iptvLists'] = decoded();
        break;
      case ConfigCommand.streamBadges:
        payload['streamBadges'] = decoded();
        break;
      default:
        throw FormatException('Unsupported profile transfer category $command');
    }
    return _profilePayloadWithinLimit(payload);
  }

  bool _profilePayloadWithinLimit(Map<String, dynamic> payload) {
    if (utf8.encode(jsonEncode(payload)).length <=
        _maxProfileRemotePayloadBytes) {
      return true;
    }
    clearProfileTransferBuffer();
    _showSnackBar('Received configuration is too large', isError: true);
    return false;
  }

  bool _profilePayloadContainsExpected(Map<String, int> expected) {
    if (expected.isEmpty) return true;
    final payload = _profileRemotePayload;
    if (payload == null) return false;
    const payloadKeys = <String, String>{
      ConfigCommand.realDebrid: 'realDebridApiKey',
      ConfigCommand.torbox: 'torboxApiKey',
      ConfigCommand.premiumize: 'premiumizeApiKey',
      ConfigCommand.allDebrid: 'allDebridApiKey',
      ConfigCommand.pikpak: 'pikpak',
      ConfigCommand.trakt: 'trakt',
      ConfigCommand.simkl: 'simkl',
      ConfigCommand.mdblist: 'mdblist',
      ConfigCommand.searchEngines: 'searchEngineIds',
      ConfigCommand.webDav: 'webDavServers',
      ConfigCommand.indexerManagers: 'indexerManagers',
      ConfigCommand.iptvPlaylists: 'iptvPlaylists',
      ConfigCommand.iptvFavorites: 'iptvFavorites',
      ConfigCommand.iptvLists: 'iptvLists',
      ConfigCommand.streamBadges: 'streamBadges',
    };
    for (final entry in expected.entries) {
      if (entry.key == RemoteAction.addon) {
        final addons = payload['addonManifestUrls'];
        if (addons is! List || addons.length < entry.value) return false;
        continue;
      }
      final payloadKey = payloadKeys[entry.key];
      if (payloadKey == null || !payload.containsKey(payloadKey)) return false;
    }
    return true;
  }

  bool _openRemoteTransfer(String data, RemoteCommandContext context) {
    final request = parseRemoteTransferRequestBody(data);
    final peer = _profilePeerKey(context);
    if (request == null || peer == null) return false;
    if (_activeRemoteTransferRequestId == request.requestId &&
        _activeRemoteTransferPeer == peer) {
      _markAuthorizedConfigActivity();
      return true;
    }
    if (_remoteTransfersInFlight.isNotEmpty || _applyingRemotePayload) {
      return false;
    }

    // A different request is a new transaction even when it comes from the
    // same remembered peer/session. Discard anything its predecessor staged
    // so missing packets cannot be satisfied by ten-minute-old values.
    clearProfileTransferBuffer();
    _batchIdleTimer?.cancel();
    _batchIdleTimer = null;
    _batching = false;
    _batchOk.clear();
    _batchFailed.clear();
    _activeRemoteTransferRequestId = request.requestId;
    _activeRemoteTransferPeer = peer;
    _activeRemoteTransferReceived.clear();
    _markAuthorizedConfigActivity();
    return true;
  }

  void _recordRemoteTransferCommand(
    String command,
    RemoteCommandContext context,
  ) {
    if (!_remoteBatchCommands.contains(command) ||
        _activeRemoteTransferPeer != _profilePeerKey(context)) {
      return;
    }
    _activeRemoteTransferReceived.update(
      command,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
  }

  String? _remoteTransferItemPayload(
    String command,
    String data,
    RemoteCommandContext context,
  ) {
    if (!_remoteBatchCommands.contains(command)) return data;
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
        activePeer != _profilePeerKey(context)) {
      return null;
    }
    return item.payload;
  }

  bool _activeRemoteTransferContainsExpected(
    String requestId,
    Map<String, int> expected,
    RemoteCommandContext context,
  ) {
    if (!_activeRemoteTransferMatches(requestId, context) || expected.isEmpty) {
      return false;
    }
    for (final entry in expected.entries) {
      if ((_activeRemoteTransferReceived[entry.key] ?? 0) < entry.value) {
        return false;
      }
    }
    return true;
  }

  bool _activeRemoteTransferMatches(
    String requestId,
    RemoteCommandContext context,
  ) =>
      _activeRemoteTransferRequestId == requestId &&
      _activeRemoteTransferPeer == _profilePeerKey(context);

  void _clearActiveRemoteTransfer() {
    _activeRemoteTransferRequestId = null;
    _activeRemoteTransferPeer = null;
    _activeRemoteTransferReceived.clear();
  }

  static String? _profilePeerKey(RemoteCommandContext context) {
    if (context.encrypted) {
      final fingerprint = context.peerFingerprint;
      final session = context.sidB64;
      if (fingerprint == null || fingerprint.isEmpty || session == null) {
        return null;
      }
      return 'v2:$fingerprint:$session';
    }
    final source = context.sourceIp;
    return source == null || source.isEmpty ? null : 'v1:$source';
  }

  void clearProfileTransferBuffer() {
    _profileRemoteExpiry?.cancel();
    _profileRemoteExpiry = null;
    _profileRemotePayload = null;
    _profileRemoteBinding = null;
    _profileRemotePeer = null;
    _clearActiveRemoteTransfer();
  }

  void clearProfileSessionState() {
    clearProfileTransferBuffer();
    for (final buffer in _chunkBuffers.values) {
      buffer.timeout?.cancel();
    }
    _chunkBuffers.clear();
  }

  @visibleForTesting
  int get debugStaleRemoteNoticeCount => _staleRemoteNoticeCount;

  @visibleForTesting
  void debugResetStaleRemoteNotices() {
    _staleRemoteSources.clear();
    _staleRemoteNoticeCount = 0;
  }

  @visibleForTesting
  Set<String> get debugProfileTransferKeys =>
      Set<String>.unmodifiable(_profileRemotePayload?.keys ?? const <String>[]);

  @visibleForTesting
  Object? debugProfileTransferValue(String key) => _profileRemotePayload?[key];

  @visibleForTesting
  bool debugProfilePayloadContainsExpected(Map<String, int> expected) =>
      _profilePayloadContainsExpected(expected);

  @visibleForTesting
  ProfileScope? get debugProfileTransferScope => _profileRemoteBinding?.scope;

  @visibleForTesting
  Future<void> debugDispatchAndWait(
    String action,
    String command,
    String? data,
    RemoteCommandContext context,
  ) => _dispatchCommandAndWait(action, command, data, context);

  Future<bool> _commitProfileRemotePayload(
    RemoteCommandContext remoteContext,
    _ProfileCommandBinding? binding,
  ) async {
    final payload = _profileRemotePayload;
    final bindingMatches = binding != null && _profileRemoteBinding == binding;
    final peerMatches = _profileRemotePeer == _profilePeerKey(remoteContext);
    final scopeMatches =
        binding != null && ProfileRuntime.capture() == binding.scope;
    if (payload == null ||
        payload.length <= 2 ||
        binding == null ||
        !bindingMatches ||
        !peerMatches ||
        !scopeMatches) {
      _showSnackBar('No profile configuration received', isError: true);
      return false;
    }
    if (!await _validateRemoteBinding(
      remoteContext,
      binding,
      ProfileFeature.remoteTransfer,
    )) {
      clearProfileTransferBuffer();
      _showSnackBar('Remote transfer authorization expired', isError: true);
      return false;
    }
    final context = _navigatorKey?.currentContext;
    if (context == null) {
      _showSnackBar('Local profile confirmation required', isError: true);
      return false;
    }
    final profile = await ProfileBootstrap.registry.activeProfile();
    if (profile == null) return false;
    final summary = BackupRestoreService.summarize(payload);
    final itemCount =
        <bool>[
          summary.hasRealDebrid,
          summary.hasTorbox,
          summary.hasPremiumize,
          summary.hasAllDebrid,
          summary.hasPikpak,
          summary.hasTrakt,
          summary.hasSimkl,
        ].where((value) => value).length +
        summary.searchEngineCount +
        summary.addonCount +
        summary.webDavServerCount +
        summary.indexerManagerCount +
        summary.iptvPlaylistCount +
        summary.iptvFavoriteCount +
        summary.iptvListCount +
        summary.streamBadgeSourceCount;
    if (!context.mounted) return false;
    final confirmed =
        await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Receive profile configuration?'),
            content: Text(
              'Destination: ${profile.name}\n\n'
              '$itemCount configuration item(s) will be applied. '
              'Downloads, recordings, PINs, profiles, and remote pairings '
              'are not transferred.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Import'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) {
      clearProfileTransferBuffer();
      _showSnackBar('Profile import cancelled');
      return false;
    }
    try {
      if (!await _validateRemoteBinding(
        remoteContext,
        binding,
        ProfileFeature.remoteTransfer,
      )) {
        clearProfileTransferBuffer();
        throw StateError('Remote transfer authorization expired');
      }
      final authorization = await ProfileAuthorizationContext.capture(
        ProfileBootstrap.registry,
      );
      if (authorization.profileId != profile.id ||
          authorization.authorizationRevision !=
              binding.authorizationRevision) {
        clearProfileTransferBuffer();
        throw StateError('Remote transfer destination changed');
      }
      // A second `complete` racing a running apply: the collection facades
      // are read-modify-write, so two interleaved loops could lose one
      // side's merge. The first confirm wins; the racer bows out here.
      if (_applyingRemotePayload) {
        _showSnackBar(
          'A transfer is already being applied — try again in a moment',
          isError: true,
        );
        return false;
      }
      _applyingRemotePayload = true;
      try {
        // Consume the receive capability before any writes. A repeated
        // `complete` packet cannot open a second commit over the same
        // secrets.
        clearProfileTransferBuffer();
        // Apply each item directly through the same per-command handlers
        // the legacy (pre-profiles) path and the Settings screens use —
        // every one is profile-aware and writes sealed secrets through the
        // reviewed facade. The staged-generation restore this replaced
        // cloned and re-hashed the ENTIRE profile (minutes on a TV with a
        // large IPTV library) to land what is usually one addon or a
        // handful of keys; that machinery remains where whole-package
        // atomicity is the point — backup-FILE restores. The trade is
        // per-item application instead of all-or-nothing, which remote
        // transfers tolerate by construction: they are idempotent, and a
        // resend converges.
        final allApplied = await _applyProfileRemotePayload(payload, binding);
        final updatedProfile = await ProfileBootstrap.registry.getProfile(
          binding.scope.profileId,
        );
        final peerFingerprint = remoteContext.peerFingerprint;
        final sessionId = remoteContext.sidB64;
        final currentScope = ProfileRuntime.capture();
        if (updatedProfile == null ||
            peerFingerprint == null ||
            sessionId == null ||
            currentScope != binding.scope ||
            !ProfileRemoteLease.instance.reauthorizeApprovedPeer(
              profile: updatedProfile,
              scope: currentScope,
              peerFingerprint: peerFingerprint,
              sessionId: sessionId,
            )) {
          throw StateError('Approved remote peer could not be reauthorized');
        }
        return allApplied;
      } finally {
        _applyingRemotePayload = false;
      }
    } catch (_) {
      // The apply loop banks item failures, but post-write lease refresh can
      // still fail if the destination changes at the end of the import.
      _showSnackBar(
        'Profile import stopped — nothing further was applied',
        isError: true,
      );
      return false;
    }
  }

  bool _applyingRemotePayload = false;

  /// Replays a staged remote payload through the per-command config
  /// handlers, in wire order (IPTV memberships name the playlists they
  /// belong to, so playlists must land first; addons go last — each is a
  /// manifest fetch). Never throws: every handler banks its own success or
  /// NAMED failure snackbar into the batch, and the single flush at the end
  /// is the honest summary — "2 failed (Real-Debrid, PikPak)" beats any
  /// counter this function could keep.
  Future<bool> _applyProfileRemotePayload(
    Map<String, dynamic> payload,
    _ProfileCommandBinding binding,
  ) async {
    // No number in the opener: the dialog counts granular items (every
    // engine, every server) while the flush counts one banked message per
    // category — two different numbers seconds apart read as dropped data.
    _showSnackBarNow('Applying the transfer from your phone…');
    // Hold the snackbar batch open MANUALLY — no idle timer. The timer
    // would flush mid-loop during any addon manifest fetch (>1200ms idle),
    // announce "Import complete" while items were still applying, and let
    // the remaining handler messages parade one by one. The flush in the
    // finally below is the only exit.
    _batching = true;
    _batchIdleTimer?.cancel();
    _batchIdleTimer = null;
    var destinationLost = false;
    var hadFailure = false;
    Future<void> apply(String label, Future<void> Function() body) async {
      if (destinationLost) return;
      // The confirm dialog authorized THIS profile. Handlers capture the
      // active profile per call, so a mid-loop profile switch would seal
      // the phone's remaining secrets into whichever profile is active now
      // — stop instead, and say so. Residual window: a switch DURING one
      // item's body can still land that single in-flight item in the new
      // profile; shrinking it to zero needs pinned-destination writes in
      // every handler, which the per-call capture design trades away.
      if (ProfileRuntime.capture() != binding.scope) {
        destinationLost = true;
        _showSnackBar(
          'Profile changed — remaining items were not applied',
          isError: true,
        );
        return;
      }
      try {
        await body();
      } catch (_) {
        hadFailure = true;
        // Handlers bank their own named failures; this catch only covers
        // throws that escape them (and the addon path below).
        debugPrint('RemoteCommandRouter: applying $label failed');
        _showSnackBar('$label: could not be applied', isError: true);
      }
    }

    try {
      const rawStringCategories = <String, String>{
        'realDebridApiKey': ConfigCommand.realDebrid,
        'torboxApiKey': ConfigCommand.torbox,
        'premiumizeApiKey': ConfigCommand.premiumize,
        'allDebridApiKey': ConfigCommand.allDebrid,
      };
      // Wire order: memberships resolve against playlists — playlists first.
      const encodedCategories = <String, String>{
        'pikpak': ConfigCommand.pikpak,
        'trakt': ConfigCommand.trakt,
        'simkl': ConfigCommand.simkl,
        'mdblist': ConfigCommand.mdblist,
        'trackingPreferences': ConfigCommand.trackingPreferences,
        'searchEngineIds': ConfigCommand.searchEngines,
        'webDavServers': ConfigCommand.webDav,
        'indexerManagers': ConfigCommand.indexerManagers,
        'iptvPlaylists': ConfigCommand.iptvPlaylists,
        'iptvFavorites': ConfigCommand.iptvFavorites,
        'iptvLists': ConfigCommand.iptvLists,
        'streamBadges': ConfigCommand.streamBadges,
      };
      for (final entry in rawStringCategories.entries) {
        final value = payload[entry.key];
        if (value is! String || value.isEmpty) continue;
        await apply(
          entry.key,
          () => _dispatchConfigCommand(entry.value, value),
        );
      }
      for (final entry in encodedCategories.entries) {
        final value = payload[entry.key];
        if (value == null) continue;
        await apply(
          entry.key,
          () => _dispatchConfigCommand(entry.value, jsonEncode(value)),
        );
      }
      final addonUrls = payload['addonManifestUrls'];
      if (addonUrls is List) {
        for (final url in addonUrls) {
          if (url is! String || url.trim().isEmpty) continue;
          await apply('Addon', () async {
            try {
              final addon = await StremioService.instance.addAddon(url.trim());
              _showSnackBar('Addon installed: ${addon.name}');
            } catch (error) {
              // Idempotence: a resend of an addon that already landed must
              // read as success, or the summary lies about the retry.
              if (error.toString().contains('already exists')) {
                _showSnackBar('Addon already installed');
                return;
              }
              rethrow;
            }
          });
        }
      }
    } finally {
      _flushBatch(prefix: 'Transfer applied');
    }
    return !destinationLost && !hadFailure;
  }

  Future<bool> _validateRemoteBinding(
    RemoteCommandContext remoteContext,
    _ProfileCommandBinding binding,
    ProfileFeature feature,
  ) async {
    if (!ProfileRuntime.isInitialized ||
        !ProfileRuntime.isProfileCommitted ||
        ProfileRuntime.capture() != binding.scope) {
      return false;
    }
    final fingerprint = remoteContext.peerFingerprint;
    final sessionId = remoteContext.sidB64;
    if (!remoteContext.encrypted ||
        !remoteContext.authorized ||
        fingerprint == null ||
        sessionId == null) {
      return false;
    }
    final profile = await ProfileBootstrap.registry.getProfile(
      binding.scope.profileId,
    );
    return profile != null &&
        profile.authorizationRevision == binding.authorizationRevision &&
        profile.allows(feature) &&
        ProfileRuntime.capture() == binding.scope &&
        ProfileRemoteLease.instance.allows(
          feature,
          binding.scope,
          currentProfile: profile,
          peerFingerprint: fingerprint,
          sessionId: sessionId,
        );
  }

  void _enqueueLegacy(_LegacyItem item, String? sourceIp) {
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
    final navigator = _navigatorKey?.currentState;
    if (navigator == null) {
      // Headless (no UI mounted yet): nothing to ask — the expiry timer
      // drops the buffer and the sender sees nothing applied.
      debugPrint(
        'RemoteCommandRouter: No navigator for consent dialog, will drop',
      );
      return;
    }
    _legacyDialogShowing = true;
    final peer = _legacyPeerIp ?? 'unknown address';
    showDialog<bool>(
      context: navigator.context,
      barrierDismissible: false,
      builder: (context) {
        // Retained so buffer expiry can dismiss the dialog — an answer given
        // after the buffer died must not grant anything.
        _legacyDialogContext = context;
        return AlertDialog(
          title: const Text('Incoming settings'),
          content: Text(
            'The device at $peer wants to send settings and account '
            'credentials to this TV over an UNENCRYPTED connection (its app '
            'version predates encryption).\n\nOnly allow this if it is your '
            'own phone and you started the transfer yourself.',
          ),
          actions: [
            FilledButton(
              autofocus: true,
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Deny'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Allow'),
            ),
          ],
        );
      },
    ).then((allowed) {
      _legacyDialogShowing = false;
      _legacyDialogContext = null;
      if (allowed == true) {
        _allowLegacy();
      } else {
        _denyLegacy(showMessage: true);
      }
    });
  }

  Future<void> _allowLegacy() async {
    _legacyExpiryTimer?.cancel();
    _legacyExpiryTimer = null;
    final approvedIp = _legacyPeerIp;
    _legacyPeerIp = null;
    final items = List<_LegacyItem>.from(_legacyBuffer);
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
    _markAuthorizedConfigActivity();
    debugPrint(
      'RemoteCommandRouter: Legacy transfer approved (${items.length} buffered)',
    );
    _beginOrExtendBatch();
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
        await _dispatchCommandAndWait(
          RemoteAction.addon,
          item.command,
          item.data,
          approvedContext,
        );
      } else {
        await _dispatchCommandAndWait(
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
      await _dispatchCommandAndWait(
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
    final dialogContext = _legacyDialogContext;
    if (dialogContext != null && dialogContext.mounted) {
      Navigator.of(dialogContext).pop(false);
    }
    if (dropped > 0) {
      debugPrint('RemoteCommandRouter: Dropped $dropped unapproved packet(s)');
      if (showMessage) {
        _showSnackBar('Incoming settings were blocked', isError: true);
      }
    }
  }

  /// Imports still writing. Tracked so the `complete` signal can wait for them
  /// rather than restarting into a partial setup.
  final Set<Future<void>> _inFlightConfigWork = {};

  Future<void> _trackConfigWork(Future<void> work) {
    late Future<void> tracked;
    tracked = work.whenComplete(() => _inFlightConfigWork.remove(tracked));
    _inFlightConfigWork.add(tracked);
    return tracked;
  }

  Future<void> _awaitInFlightConfigWork() async {
    Future<void> drainPendingDispatches() async {
      while (_pendingRemoteTransferDispatches.isNotEmpty) {
        try {
          await Future.wait(_pendingRemoteTransferDispatches.toList());
        } catch (_) {
          // Individual handlers report their own failure.
        }
      }
    }

    // Registration happens synchronously in [dispatchCommand], before any
    // profile lookup or handler await. Drain it first so a chunk start that
    // has already arrived gets a chance to create its buffer before the
    // buffer-repair phase below checks for one.
    await drainPendingDispatches();

    // A chunked transfer that hasn't finished arriving is NOT in-flight work
    // yet — each chunk's handler completes the moment it files the piece, and
    // the real import only starts on the last one. Restarting now would throw
    // the buffer away mid-transfer and lose the payload with no error shown,
    // so wait for the buffers to resolve first. They always do: either the
    // final chunk lands, or the stall deadline fires and reports it.
    final deadline = DateTime.now().add(
      kChunkTransferTimeout + const Duration(seconds: 5),
    );
    while (_chunkBuffers.isNotEmpty && DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 200));
    }
    if (_chunkBuffers.isNotEmpty) {
      debugPrint(
        'RemoteCommandRouter: Giving up on ${_chunkBuffers.length} unfinished '
        'transfer(s) before restart',
      );
    }

    // Repair replies arrive as new dispatches. The final chunk removes its
    // buffer before it decrypts/replays the payload, so drain again to wait
    // for that replay and its actual import to finish.
    await drainPendingDispatches();

    // Drain rather than waiting on one snapshot: the final packet's import can
    // still be running, and it can start further work as it finishes.
    while (_inFlightConfigWork.isNotEmpty) {
      try {
        await Future.wait(_inFlightConfigWork.toList());
      } catch (_) {
        // Handlers report their own failures; this only gates the restart.
        debugPrint('RemoteCommandRouter: in-flight config work failed');
      }
    }
  }

  Future<void> _dispatchConfigCommand(
    String command,
    String data, {
    RemoteCommandContext context = RemoteCommandContext.plaintext,
    _ProfileCommandBinding? profileBinding,
  }) async {
    switch (command) {
      case ConfigCommand.realDebrid:
        await _handleRealDebridConfig(data);
        break;
      case ConfigCommand.torbox:
        await _handleTorboxConfig(data);
        break;
      case ConfigCommand.premiumize:
        await _handlePremiumizeConfig(data);
        break;
      case ConfigCommand.allDebrid:
        await _handleAllDebridConfig(data);
        break;
      case ConfigCommand.pikpak:
        await _handlePikPakConfig(data);
        break;
      case ConfigCommand.trakt:
        await _handleTraktConfig(data);
        break;
      case ConfigCommand.simkl:
        await _handleSimklConfig(data);
        break;
      case ConfigCommand.mdblist:
        await _handleMdblistConfig(data);
        break;
      case ConfigCommand.trackingPreferences:
        await _handleTrackingPreferencesConfig(data);
        break;
      case ConfigCommand.searchEngines:
        await _handleSearchEnginesConfig(data);
        break;
      case ConfigCommand.webDav:
        await _handleWebDavConfig(data);
        break;
      case ConfigCommand.indexerManagers:
        await _handleIndexerManagersConfig(data);
        break;
      case ConfigCommand.iptvPlaylists:
        await _handleIptvPlaylistsConfig(data);
        break;
      case ConfigCommand.iptvFavorites:
        await _handleIptvFavoritesConfig(data);
        break;
      case ConfigCommand.iptvLists:
        await _handleIptvListsConfig(data);
        break;
      case ConfigCommand.streamBadges:
        await _handleStreamBadgesConfig(data);
        break;
      case ConfigCommand.debrifyChannel:
        await _handleDebrifyChannelConfig(data, context, profileBinding);
        break;
      case ConfigCommand.profileAvatar:
        await _handleProfileAvatarConfig(data, context);
        break;
      case ConfigCommand.profileGraph:
        await _handleProfileGraphConfig(data, context);
        break;
      case ConfigCommand.debrifyChannelStart:
        _handleDebrifyChannelStart(data, context);
        break;
      case ConfigCommand.debrifyChannelChunk:
        await _handleDebrifyChannelChunk(data, context);
        break;
      default:
        debugPrint('RemoteCommandRouter: Unknown config command: $command');
    }
  }

  /// Handle profile-scoped tracking preferences.
  Future<void> _handleTrackingPreferencesConfig(String data) async {
    try {
      final decoded = jsonDecode(data);
      if (decoded is! Map) throw const FormatException();
      await StorageService.applyTrackingPreferencesPayload(decoded);
      final requested = decoded['progress_source']?.toString();
      final effective = await TrackingSourcePolicy.load();
      final fellBack =
          requested != null &&
          requested != WatchProgressSource.smart.name &&
          effective.progressSource == WatchProgressSource.smart;
      if (fellBack) {
        await StorageService.takeTrackingProgressFallbackNotice();
      }
      _showSnackBar(
        fellBack
            ? 'Tracking configured. Progress tracker is disconnected; using Smart.'
            : 'Tracking preferences configured successfully',
      );
    } catch (_) {
      _showSnackBar(
        'Tracking preferences: Configuration failed',
        isError: true,
      );
    }
  }

  /// Handle Real-Debrid API key config
  Future<void> _handleRealDebridConfig(String apiKey) async {
    try {
      debugPrint('RemoteCommandRouter: Validating Real-Debrid API key...');

      // Validate the API key
      final isValid = await AccountService.validateAndGetUserInfo(apiKey);
      if (!isValid) {
        _showSnackBar('Real-Debrid: Invalid API key', isError: true);
        return;
      }

      // Save the API key
      await StorageService.saveApiKey(apiKey);
      await StorageService.setRealDebridIntegrationEnabled(true);

      debugPrint('RemoteCommandRouter: Real-Debrid configured successfully');
      _showSnackBar('Real-Debrid configured successfully');
    } catch (_) {
      debugPrint('RemoteCommandRouter: Real-Debrid configuration failed');
      _showSnackBar('Real-Debrid: Configuration failed', isError: true);
    }
  }

  /// Handle Torbox API key config
  Future<void> _handleTorboxConfig(String apiKey) async {
    try {
      debugPrint('RemoteCommandRouter: Validating Torbox API key...');

      // Validate the API key
      final isValid = await TorboxAccountService.validateAndGetUserInfo(apiKey);
      if (!isValid) {
        _showSnackBar('Torbox: Invalid API key', isError: true);
        return;
      }

      // Save the API key
      await StorageService.saveTorboxApiKey(apiKey);
      await StorageService.setTorboxIntegrationEnabled(true);

      debugPrint('RemoteCommandRouter: Torbox configured successfully');
      _showSnackBar('Torbox configured successfully');
    } catch (_) {
      debugPrint('RemoteCommandRouter: Torbox configuration failed');
      _showSnackBar('Torbox: Configuration failed', isError: true);
    }
  }

  /// Handle Premiumize API key config
  Future<void> _handlePremiumizeConfig(String apiKey) async {
    try {
      debugPrint('RemoteCommandRouter: Validating Premiumize API key...');

      final isValid = await PremiumizeAccountService.validateAndGetUserInfo(
        apiKey,
      );
      if (!isValid) {
        _showSnackBar('Premiumize: Invalid API key', isError: true);
        return;
      }

      await StorageService.savePremiumizeApiKey(apiKey);
      await StorageService.setPremiumizeIntegrationEnabled(true);

      debugPrint('RemoteCommandRouter: Premiumize configured successfully');
      _showSnackBar('Premiumize configured successfully');
    } catch (_) {
      debugPrint('RemoteCommandRouter: Premiumize configuration failed');
      _showSnackBar('Premiumize: Configuration failed', isError: true);
    }
  }

  /// Handle AllDebrid API key config
  Future<void> _handleAllDebridConfig(String apiKey) async {
    try {
      debugPrint('RemoteCommandRouter: Validating AllDebrid API key...');

      final isValid = await AllDebridAccountService.validateAndGetUserInfo(
        apiKey,
      );
      if (!isValid) {
        _showSnackBar('AllDebrid: Invalid API key', isError: true);
        return;
      }

      await StorageService.saveAllDebridApiKey(apiKey);
      await StorageService.setAllDebridIntegrationEnabled(true);

      debugPrint('RemoteCommandRouter: AllDebrid configured successfully');
      _showSnackBar('AllDebrid configured successfully');
    } catch (_) {
      debugPrint('RemoteCommandRouter: AllDebrid configuration failed');
      _showSnackBar('AllDebrid: Configuration failed', isError: true);
    }
  }

  /// Handle PikPak credentials config
  Future<void> _handlePikPakConfig(String jsonData) async {
    try {
      debugPrint('RemoteCommandRouter: Configuring PikPak...');

      final data = jsonDecode(jsonData) as Map<String, dynamic>;
      final email = data['email'] as String?;
      final password = data['password'] as String?;

      if (email == null || password == null) {
        _showSnackBar('PikPak: Invalid credentials data', isError: true);
        return;
      }

      // Attempt login
      final result = await PikPakApiService.instance.login(email, password);
      if (!result) {
        _showSnackBar('PikPak: Login failed', isError: true);
        return;
      }

      // Enable PikPak integration
      await StorageService.setPikPakEnabled(true);

      debugPrint('RemoteCommandRouter: PikPak configured successfully');
      _showSnackBar('PikPak configured successfully');
    } catch (_) {
      debugPrint('RemoteCommandRouter: PikPak configuration failed');
      _showSnackBar('PikPak: Configuration failed', isError: true);
    }
  }

  /// Handle Trakt session config - copies access/refresh tokens, expiry, and
  /// username from the sender so the TV ends up logged in to the same account.
  Future<void> _handleTraktConfig(String jsonData) async {
    try {
      debugPrint('RemoteCommandRouter: Configuring Trakt session...');

      final data = jsonDecode(jsonData) as Map<String, dynamic>;
      final accessToken = data['access_token'] as String?;
      final refreshToken = data['refresh_token'] as String?;
      final expiry = data['expiry_ms'] as int?;
      final username = data['username'] as String?;

      if (accessToken == null ||
          accessToken.isEmpty ||
          refreshToken == null ||
          refreshToken.isEmpty) {
        _showSnackBar('Trakt: Invalid session data', isError: true);
        return;
      }

      await StorageService.setTraktAccessToken(accessToken);
      await StorageService.setTraktRefreshToken(refreshToken);
      if (expiry != null) {
        await StorageService.setTraktTokenExpiry(expiry);
      }
      if (username != null && username.isNotEmpty) {
        await StorageService.setTraktUsername(username);
      }
      // Match interactive connect: a freshly imported Trakt session starts
      // with catalog scrobbling on.
      await StorageService.setTraktSyncCatalogItems(true);
      await StorageService.enableTrackingScrobbleTarget(TrackingSource.trakt);

      debugPrint('RemoteCommandRouter: Trakt session configured successfully');
      _showSnackBar('Trakt connected successfully');
    } catch (_) {
      debugPrint('RemoteCommandRouter: Trakt configuration failed');
      _showSnackBar('Trakt: Configuration failed', isError: true);
    }
  }

  /// Handle Simkl session config - copies the access token and username from
  /// the sender so the TV ends up logged in to the same account. Simpler than
  /// Trakt's: Simkl's PIN-issued tokens have no refresh token/expiry to carry.
  Future<void> _handleSimklConfig(String jsonData) async {
    try {
      debugPrint('RemoteCommandRouter: Configuring Simkl session...');

      final data = jsonDecode(jsonData) as Map<String, dynamic>;
      final accessToken = data['access_token'] as String?;
      final username = data['username'] as String?;

      if (accessToken == null || accessToken.isEmpty) {
        _showSnackBar('Simkl: Invalid session data', isError: true);
        return;
      }

      await StorageService.setSimklAccessToken(accessToken);
      if (username != null && username.isNotEmpty) {
        await StorageService.setSimklUsername(username);
      }
      // Match interactive connect: a freshly imported Simkl session starts
      // with catalog scrobbling on.
      await StorageService.setSimklSyncCatalogItems(true);
      await StorageService.enableTrackingScrobbleTarget(TrackingSource.simkl);

      debugPrint('RemoteCommandRouter: Simkl session configured successfully');
      _showSnackBar('Simkl connected successfully');
    } catch (_) {
      debugPrint('RemoteCommandRouter: Simkl configuration failed');
      _showSnackBar('Simkl: Configuration failed', isError: true);
    }
  }

  /// Validate before replacing the destination profile's MDBList connection.
  /// [connect] publishes credentials only after `/user` succeeds, so invalid
  /// transfer data leaves the prior resource unchanged.
  Future<void> _handleMdblistConfig(String jsonData) async {
    try {
      final data = jsonDecode(jsonData) as Map<String, dynamic>;
      final apiKey = data['api_key'] as String?;
      if (apiKey == null || apiKey.trim().isEmpty || !kMdblistEnabled) {
        _showSnackBar('MDBList: Invalid connection data', isError: true);
        return;
      }
      final account = await MdblistService.instance.connect(apiKey);
      if (account == null) {
        _showSnackBar('MDBList: API key validation failed', isError: true);
        return;
      }
      await StorageService.setMdblistSyncCatalogItems(true);
      MainPageBridge.notifyIntegrationChanged();
      _showSnackBar('MDBList connected successfully');
    } catch (_) {
      _showSnackBar('MDBList: Configuration failed', isError: true);
    }
  }

  /// Handle config complete signal.
  ///
  /// If this device is still in first-time onboarding, mark it complete and
  /// restart the app flow so the new credentials/integrations are picked up
  /// (the original "set up TV from phone" flow).
  ///
  /// If onboarding is already done — e.g. a phone or already-configured TV
  /// is in receive mode mid-session — we just acknowledge with a snackbar
  /// and let the user keep using the app uninterrupted.
  Future<void> _handleConfigComplete({bool? wasOnboardingOverride}) async {
    final wasOnboarding =
        wasOnboardingOverride ??
        !(await StorageService.isInitialSetupComplete());

    if (!wasOnboarding) {
      debugPrint('RemoteCommandRouter: Config complete (already onboarded)');
      // The end of the burst, and the only place that knows what it WAS: one
      // summary for everything banked since the first packet.
      _flushBatch(prefix: 'Setup received');
      return;
    }

    debugPrint(
      'RemoteCommandRouter: Config complete during onboarding, restarting app flow...',
    );

    // Best-effort, and deliberately not fatal: onboarding may already have
    // been cleared before an authority hand-off (the profile-graph import does
    // exactly that), in which case the active profile can now be LOCKED and
    // this write is refused. Losing the restart over a flag that is already
    // correct would strand the user on the onboarding screen behind a fully
    // imported device — the exact bug this guard exists to prevent.
    try {
      await StorageService.setInitialSetupComplete(true);
    } catch (e) {
      debugPrint('RemoteCommandRouter: onboarding flag write skipped — $e');
    }
    // Registry writes invalidate the native privacy projection before changing
    // authority. This is an in-process route restart, not a cold bootstrap, so
    // publish the now-final active scope explicitly before native readers run.
    try {
      if (ProfileRuntime.isProfileCommitted) {
        await NativeProfileProjection.publish(ProfileRuntime.capture());
      }
    } catch (e) {
      debugPrint(
        'RemoteCommandRouter: privacy projection republish failed — $e',
      );
    }
    _flushBatch(prefix: 'Setup received — restarting');

    // Give snackbar time to show, then restart app
    await Future.delayed(const Duration(milliseconds: 1500));

    if (_onRestartApp != null) {
      _onRestartApp!();
      debugPrint('RemoteCommandRouter: Restart callback invoked');
    } else {
      debugPrint('RemoteCommandRouter: Restart callback not available');
    }
  }

  /// Handle search engines config (downloads engine IDs)
  Future<void> _handleSearchEnginesConfig(String jsonData) async {
    try {
      debugPrint('RemoteCommandRouter: Configuring search engines...');

      final engineIds = (jsonDecode(jsonData) as List).cast<String>();
      if (engineIds.isEmpty) {
        debugPrint('RemoteCommandRouter: No engine IDs to import');
        return;
      }

      final remoteManager = RemoteEngineManager();
      final localStorage = LocalEngineStorage.instance;
      await localStorage.initialize();

      // Fetch available engines
      final availableEngines = await remoteManager.fetchAvailableEngines();
      int successCount = 0;
      int failCount = 0;
      int newlyImported = 0;

      for (final engineId in engineIds) {
        // Find the engine info
        final engineInfo = availableEngines
            .where((e) => e.id == engineId)
            .firstOrNull;
        if (engineInfo == null) {
          debugPrint('RemoteCommandRouter: requested engine not found');
          failCount++;
          continue;
        }

        // Check if already imported
        if (await localStorage.isEngineImported(engineId)) {
          debugPrint('RemoteCommandRouter: requested engine already imported');
          successCount++;
          continue;
        }

        // Download and save the engine
        try {
          final yamlContent = await remoteManager.downloadEngineYaml(
            engineInfo.fileName,
          );
          if (yamlContent == null) {
            debugPrint('RemoteCommandRouter: engine download failed');
            failCount++;
            continue;
          }
          await localStorage.saveEngine(
            engineId: engineId,
            fileName: engineInfo.fileName,
            yamlContent: yamlContent,
            displayName: engineInfo.displayName,
            icon: engineInfo.icon,
          );
          successCount++;
          newlyImported++;
        } catch (_) {
          debugPrint('RemoteCommandRouter: engine import failed');
          failCount++;
        }
      }

      // Refresh the in-memory registry so the new engines are visible to
      // keyword search without an app restart.
      if (newlyImported > 0) {
        ConfigLoader().clearCache();
        await EngineRegistry.instance.reload();
      }

      if (failCount == 0) {
        _showSnackBar(
          '$successCount search engine${successCount != 1 ? 's' : ''} configured',
        );
      } else if (successCount == 0) {
        _showSnackBar('Search engines: All failed to import', isError: true);
      } else {
        _showSnackBar(
          'Search engines: $successCount imported, $failCount failed',
          isError: true,
        );
      }
    } catch (_) {
      debugPrint('RemoteCommandRouter: search-engine configuration failed');
      _showSnackBar('Search engines: Configuration failed', isError: true);
    }
  }

  /// Handle WebDAV servers config — merges incoming entries into the local
  /// list, de-duped by normalized base URL.
  Future<void> _handleWebDavConfig(String jsonData) async {
    try {
      debugPrint('RemoteCommandRouter: Configuring WebDAV servers...');

      final decoded = jsonDecode(jsonData);
      if (decoded is! List) {
        _showSnackBar('WebDAV: Invalid payload', isError: true);
        return;
      }

      String normalize(String url) =>
          url.trim().toLowerCase().replaceFirst(RegExp(r'/+$'), '');

      final existing = await StorageService.getWebDavServers();
      final existingKeys = <String>{
        for (final s in existing) normalize(s.baseUrl),
      };
      final merged = List<WebDavConfig>.from(existing);
      int imported = 0;
      int skipped = 0;
      for (final raw in decoded) {
        if (raw is! Map) {
          skipped++;
          continue;
        }
        try {
          final config = WebDavConfig.fromTransferJson(
            Map<String, dynamic>.from(raw),
          );
          if (config.baseUrl.trim().isEmpty) {
            skipped++;
            continue;
          }
          final key = normalize(config.baseUrl);
          if (existingKeys.contains(key)) {
            skipped++;
            continue;
          }
          merged.add(config);
          existingKeys.add(key);
          imported++;
        } catch (_) {
          debugPrint('RemoteCommandRouter: WebDAV entry failed');
          skipped++;
        }
      }

      if (imported > 0) {
        await StorageService.saveWebDavServers(merged);
      }

      if (imported > 0 && skipped == 0) {
        _showSnackBar(
          '$imported WebDAV server${imported == 1 ? '' : 's'} configured',
        );
      } else if (imported > 0) {
        _showSnackBar(
          'WebDAV: $imported added, $skipped already present or invalid',
        );
      } else if (skipped > 0) {
        _showSnackBar('WebDAV: nothing new to add');
      } else {
        _showSnackBar('WebDAV: empty payload', isError: true);
      }
    } catch (_) {
      debugPrint('RemoteCommandRouter: WebDAV configuration failed');
      _showSnackBar('WebDAV: Configuration failed', isError: true);
    }
  }

  /// Handle indexer manager (Jackett / Prowlarr) configs — merges incoming
  /// entries into the local list, de-duped by (type, normalized baseUrl).
  Future<void> _handleIndexerManagersConfig(String jsonData) async {
    try {
      debugPrint('RemoteCommandRouter: Configuring indexer managers...');

      final decoded = jsonDecode(jsonData);
      if (decoded is! List) {
        _showSnackBar('Indexer managers: Invalid payload', isError: true);
        return;
      }

      String normalize(String url) =>
          url.trim().toLowerCase().replaceFirst(RegExp(r'/+$'), '');
      String fingerprint(IndexerManagerConfig c) =>
          '${c.type.value}|${normalize(c.baseUrl)}';

      final existing = await StorageService.getIndexerManagerConfigs();
      final existingKeys = <String>{for (final c in existing) fingerprint(c)};
      final merged = List<IndexerManagerConfig>.from(existing);
      int imported = 0;
      int skipped = 0;
      for (final raw in decoded) {
        if (raw is! Map) {
          skipped++;
          continue;
        }
        try {
          final config = IndexerManagerConfig.fromTransferJson(
            Map<String, dynamic>.from(raw),
          );
          if (config.baseUrl.trim().isEmpty || config.apiKey.trim().isEmpty) {
            skipped++;
            continue;
          }
          final key = fingerprint(config);
          if (existingKeys.contains(key)) {
            skipped++;
            continue;
          }
          merged.add(config);
          existingKeys.add(key);
          imported++;
        } catch (_) {
          debugPrint('RemoteCommandRouter: indexer manager entry failed');
          skipped++;
        }
      }

      if (imported > 0) {
        await StorageService.setIndexerManagerConfigs(merged);
      }

      if (imported > 0 && skipped == 0) {
        _showSnackBar(
          '$imported indexer manager${imported == 1 ? '' : 's'} configured',
        );
      } else if (imported > 0) {
        _showSnackBar(
          'Indexer managers: $imported added, $skipped already present or invalid',
        );
      } else if (skipped > 0) {
        _showSnackBar('Indexer managers: nothing new to add');
      } else {
        _showSnackBar('Indexer managers: empty payload', isError: true);
      }
    } catch (_) {
      debugPrint('RemoteCommandRouter: indexer configuration failed');
      _showSnackBar('Indexer managers: Configuration failed', isError: true);
    }
  }

  /// Handle IPTV providers — merged, never replacing what's already here.
  ///
  /// Senders put this before favorites and lists: those name the provider
  /// they came from, and the memberships have to land on a device that
  /// already knows it.
  Future<void> _handleIptvPlaylistsConfig(String jsonData) async {
    await _applyIptvPayload(jsonData, 'IPTV providers', (entries) async {
      final counts = await IptvTransferPayload.applyPlaylists(entries);
      final n = counts.imported;
      return (
        added: n,
        skipped: counts.alreadyPresent,
        failed: counts.failed,
        error: counts.error,
        summary: '$n IPTV provider${n == 1 ? '' : 's'} added',
      );
    });
  }

  /// Handle starred IPTV channels.
  Future<void> _handleIptvFavoritesConfig(String jsonData) async {
    await _applyIptvPayload(jsonData, 'IPTV favorites', (entries) async {
      final counts = await IptvTransferPayload.applyFavorites(entries);
      final n = counts.channelsImported;
      return (
        added: n,
        skipped: counts.channelsAlreadyPresent,
        failed: counts.failed,
        error: counts.error,
        summary: '$n favorite channel${n == 1 ? '' : 's'} added',
      );
    });
  }

  /// Handle user-created IPTV lists and their channels. A list whose name
  /// already exists here is topped up rather than duplicated, so both the
  /// lists created and the channels placed are worth reporting.
  Future<void> _handleIptvListsConfig(String jsonData) async {
    await _applyIptvPayload(jsonData, 'IPTV lists', (entries) async {
      final counts = await IptvTransferPayload.applyCustomLists(entries);
      final lists = counts.imported;
      final channels = counts.channelsImported;
      return (
        added: lists + channels,
        skipped: counts.channelsAlreadyPresent,
        failed: counts.failed,
        error: counts.error,
        summary:
            '$lists list${lists == 1 ? '' : 's'}, '
            '$channels channel${channels == 1 ? '' : 's'} added',
      );
    });
  }

  /// Stream badge rulesets arrive as the backup payload's `streamBadges`
  /// array; same id merges in place, so a re-send is an update.
  Future<void> _handleStreamBadgesConfig(String jsonData) async {
    await _applyIptvPayload(jsonData, 'Stream badges', (entries) async {
      final counts = await StreamBadgesService.instance.applyBackup(entries);
      final n = counts.imported;
      return (
        added: n,
        skipped: counts.alreadyPresent,
        failed: counts.failed,
        error: null,
        summary: '$n badge ruleset${n == 1 ? '' : 's'} added',
      );
    });
  }

  /// Shared decode + report for the IPTV payloads and stream badges: they all
  /// arrive as a JSON array and report the same added / already-there /
  /// failed shape.
  Future<void> _applyIptvPayload(
    String jsonData,
    String label,
    Future<
      ({int added, int skipped, int failed, String? error, String summary})
    >
    Function(List<dynamic>)
    apply,
  ) async {
    try {
      debugPrint('RemoteCommandRouter: Configuring $label...');

      final decoded = jsonDecode(jsonData);
      if (decoded is! List) {
        _showSnackBar('$label: Invalid payload', isError: true);
        return;
      }
      if (decoded.isEmpty) {
        _showSnackBar('$label: empty payload', isError: true);
        return;
      }

      final result = await apply(decoded);
      if (result.error != null) {
        debugPrint('RemoteCommandRouter: provider configuration failed');
        _showSnackBar('$label: Configuration failed', isError: true);
        return;
      }

      // Rejections outrank "nothing new". Reporting `skipped` first meant a
      // payload whose every new entry was refused still read as a successful
      // no-op, as long as ONE unrelated entry was already here — which is how
      // dropped providers looked like an up-to-date TV.
      if (result.added > 0 && result.failed == 0) {
        _showSnackBar(result.summary);
      } else if (result.added > 0) {
        _showSnackBar('${result.summary}, ${result.failed} failed');
      } else if (result.failed > 0) {
        _showSnackBar(
          '$label: ${result.failed} rejected, nothing added',
          isError: true,
        );
      } else if (result.skipped > 0) {
        _showSnackBar('$label: already up to date');
      } else {
        _showSnackBar('$label: nothing imported', isError: true);
      }
    } catch (_) {
      debugPrint('RemoteCommandRouter: IPTV configuration failed');
      _showSnackBar('$label: Configuration failed', isError: true);
    }
  }

  /// Handle Debrify TV channel import from remote
  Future<void> _handleDebrifyChannelConfig(
    String data,
    RemoteCommandContext context,
    _ProfileCommandBinding? profileBinding,
  ) async {
    final request = parseRemoteChannelTransferBody(data);
    final requestId = request?.requestId;
    final debrifyUri = request?.uri ?? data;
    final cachedOutcome = requestId == null
        ? null
        : _remoteTransferOutcomes[requestId];
    if (cachedOutcome != null &&
        DateTime.now().difference(cachedOutcome.completedAt) <=
            _remoteTransferOutcomeLifetime) {
      await _reportRemoteTransferResultBestEffort(
        context,
        requestId: requestId,
        ok: cachedOutcome.ok,
        message: cachedOutcome.message,
      );
      return;
    }
    try {
      debugPrint('RemoteCommandRouter: Importing Debrify TV channel...');

      // 1. Decode the debrify:// URI
      final decoded = MagnetYamlService.decode(debrifyUri);

      // 2. Parse YAML into channel data
      final parsed = DebrifyTvZipImporter.parseYaml(
        sourceName: decoded.channelName,
        content: decoded.yamlContent,
      );

      if (profileBinding != null &&
          !await _validateRemoteBinding(
            context,
            profileBinding,
            ProfileFeature.remoteTransfer,
          )) {
        throw StateError('Remote transfer authorization expired');
      }

      // 3. Keep lookup, channel write, and cache write on the one profile DB
      // admitted here. A profile switch waits for this scope to drain instead
      // of redirecting a later await into the newly active profile.
      await DebrifyTvDatabase.instance.runScoped((_) async {
        final existingChannels = await DebrifyTvRepository.instance
            .fetchAllChannels();
        final existingMatch = existingChannels
            .where(
              (c) => c.name.toLowerCase() == parsed.channelName.toLowerCase(),
            )
            .firstOrNull;
        final channelId =
            existingMatch?.channelId ??
            DateTime.now().microsecondsSinceEpoch.toString();
        final now = DateTime.now();

        final record = DebrifyTvChannelRecord(
          channelId: channelId,
          name: parsed.channelName,
          keywords: parsed.displayKeywords,
          avoidNsfw: parsed.avoidNsfw,
          channelNumber: 0,
          createdAt: now,
          updatedAt: now,
        );

        final entry = DebrifyTvChannelCacheEntry(
          version: 1,
          channelId: channelId,
          normalizedKeywords: parsed.normalizedKeywords,
          fetchedAt: now.millisecondsSinceEpoch,
          status: DebrifyTvCacheStatus.ready,
          errorMessage: null,
          torrents: parsed.torrents,
          keywordStats: parsed.keywordStats,
        );

        await DebrifyTvRepository.instance.upsertChannel(record);
        await DebrifyTvCacheService.saveEntry(entry);
      });

      debugPrint('RemoteCommandRouter: channel imported');
      _showSnackBar('Channel imported: ${parsed.channelName}');
      await _reportRemoteTransferResultBestEffort(
        context,
        requestId: requestId,
        ok: true,
        message: 'Channel imported on TV',
      );
    } catch (_) {
      debugPrint('RemoteCommandRouter: channel import failed');
      _showSnackBar('Failed to import channel', isError: true);
      await _reportRemoteTransferResultBestEffort(
        context,
        requestId: requestId,
        ok: false,
        message: 'The TV could not import the channel',
      );
    }
  }

  /// Handle start of a chunked transfer. The payload can belong to any config
  /// command — the start packet names it via `kind`.
  void _handleDebrifyChannelStart(
    String jsonData,
    RemoteCommandContext context,
  ) {
    String? diagnosticKind;
    String? diagnosticTrace;
    try {
      final data = jsonDecode(jsonData) as Map<String, dynamic>;
      final transferId = data['transferId'] as String;
      final label = data['channelName'] as String;
      final totalChunks = data['totalChunks'] as int;
      final kind = (data['kind'] as String?) ?? ConfigCommand.debrifyChannel;
      diagnosticKind = kind;
      final encrypted = data['enc'] == 1;
      final sid = data['sid'] as String?;
      final resultRequestId = data['resultRequestId'] as String?;
      diagnosticTrace = RemoteTransferDiagnostics.traceToken(resultRequestId);
      final peer = _profilePeerKey(context);

      if (transferId.isEmpty ||
          transferId.length > 160 ||
          label.length > 240 ||
          totalChunks < 1 ||
          totalChunks >
              _maxProfileRemotePayloadBytes ~/ kChunkRawBytesPerChunk + 1 ||
          peer == null ||
          encrypted != context.encrypted ||
          (resultRequestId != null &&
              (resultRequestId.isEmpty || resultRequestId.length > 128)) ||
          (encrypted && (!context.authorized || sid != context.sidB64))) {
        throw const FormatException('Invalid chunk transfer envelope');
      }

      // A transfer that reassembled into another envelope would re-enter this
      // path forever. Nothing legitimate names one, so refuse outright.
      if (kind == ConfigCommand.debrifyChannelStart ||
          kind == ConfigCommand.debrifyChannelChunk ||
          kind == ConfigCommand.debrifyChannelNeed ||
          kind == ConfigCommand.complete) {
        debugPrint('RemoteCommandRouter: refusing recursive chunk transfer');
        return;
      }

      debugPrint(
        'RemoteCommandRouter: chunked transfer started ($totalChunks chunks)',
      );
      if (kind == ConfigCommand.profileGraph) {
        RemoteTransferDiagnostics.record(
          'receiver_chunk_start',
          fields: <String, Object?>{
            'trace': diagnosticTrace,
            'chunks': totalChunks,
            'encrypted': encrypted,
          },
        );
      }

      final existing = _chunkBuffers[transferId];
      if (existing != null && existing.peerKey != peer) {
        throw const FormatException('Transfer ID belongs to another peer');
      }
      if (existing == null && _chunkBuffers.length >= 4) {
        throw const FormatException('Too many active transfers');
      }
      existing?.timeout?.cancel();
      // The sender fires its start packet twice (a lost start is the one
      // packet gap-repair cannot recover). A duplicate for a transfer that
      // is already receiving must be a NO-OP — rebuilding the buffer would
      // wipe every chunk that already landed.
      if (existing != null &&
          existing.totalChunks == totalChunks &&
          existing.kind == kind &&
          existing.receivedCount > 0) {
        if (kind == ConfigCommand.profileGraph) {
          RemoteTransferDiagnostics.record(
            'receiver_chunk_start_repeat',
            fields: <String, Object?>{
              'trace': diagnosticTrace,
              'received': existing.receivedCount,
              'chunks': totalChunks,
            },
          );
        }
        _armChunkTimeout(transferId, existing);
        return;
      }

      final buffer = _ChunkBuffer(
        label: label,
        kind: kind,
        totalChunks: totalChunks,
        chunks: List<String?>.filled(totalChunks, null),
        timeout: null,
        encrypted: encrypted,
        sidB64: sid,
        blobN: (data['n'] as num?)?.toInt(),
        // Plain (v1) transfers replay with the SENDER's source context —
        // keyed to null, the reassembled payload's consent entry would never
        // match the complete packet arriving from the real address.
        sourceIp: context.sourceIp,
        peerKey: peer,
        remembered: context.remembered,
        resultRequestId: resultRequestId,
      );
      _chunkBuffers[transferId] = buffer;
      _armChunkTimeout(transferId, buffer);
    } catch (error) {
      if (diagnosticKind == ConfigCommand.profileGraph) {
        RemoteTransferDiagnostics.record(
          'receiver_chunk_start_rejected',
          fields: <String, Object?>{
            'trace': diagnosticTrace,
            'errorType': error.runtimeType,
          },
        );
      }
      debugPrint('RemoteCommandRouter: invalid chunk start');
      _showSnackBar('Failed to receive transfer', isError: true);
    }
  }

  /// (Re)start a transfer's stall deadline.
  ///
  /// v2 (sealed) transfers repair instead of dying: after a short stall the
  /// receiver names the missing indices over the session and the sender
  /// replays them — this is what makes the sender's aggressive pacing safe.
  /// Plain v1 transfers have no session to carry that request, so they keep
  /// the original single long deadline.
  void _armChunkTimeout(String transferId, _ChunkBuffer buffer) {
    buffer.timeout?.cancel();
    if (!buffer.encrypted) {
      buffer.timeout = Timer(kChunkTransferTimeout, () {
        if (buffer.kind == ConfigCommand.profileGraph) {
          RemoteTransferDiagnostics.record(
            'receiver_chunk_timeout',
            fields: <String, Object?>{
              'trace': RemoteTransferDiagnostics.traceToken(
                buffer.resultRequestId,
              ),
              'received': buffer.receivedCount,
              'chunks': buffer.totalChunks,
              'encrypted': false,
            },
          );
        }
        debugPrint('RemoteCommandRouter: chunk transfer stalled');
        _chunkBuffers.remove(transferId);
        // A silent drop reads as success from the sender's side, so the
        // receiving end has to be the one that says the data never landed.
        _showSnackBar('Transfer timed out: ${buffer.label}', isError: true);
      });
      return;
    }
    buffer.timeout = Timer(kChunkRepairStall, () {
      final missing = <int>[];
      for (
        var i = 0;
        i < buffer.totalChunks && missing.length < kChunkNeedMaxIndices;
        i++
      ) {
        if (buffer.chunks[i] == null) missing.add(i);
      }
      if (missing.isEmpty) return; // completion raced the timer
      final state = RemoteControlState();
      final sid = buffer.sidB64;
      final session = sid == null
          ? null
          : state.sessionManager?.sessionBySid(sid);
      if (buffer.repairRounds >= kChunkRepairMaxRounds || session == null) {
        if (buffer.kind == ConfigCommand.profileGraph) {
          RemoteTransferDiagnostics.record(
            'receiver_chunk_repair_exhausted',
            fields: <String, Object?>{
              'trace': RemoteTransferDiagnostics.traceToken(
                buffer.resultRequestId,
              ),
              'received': buffer.receivedCount,
              'chunks': buffer.totalChunks,
              'rounds': buffer.repairRounds,
              'sessionReady': session != null,
            },
          );
        }
        debugPrint('RemoteCommandRouter: chunk transfer stalled beyond repair');
        _chunkBuffers.remove(transferId);
        _showSnackBar('Transfer timed out: ${buffer.label}', isError: true);
        unawaited(
          _reportChunkFailure(
            buffer,
            'Transfer timed out before the TV could import it',
          ),
        );
        return;
      }
      buffer.repairRounds++;
      if (buffer.kind == ConfigCommand.profileGraph) {
        RemoteTransferDiagnostics.record(
          'receiver_chunk_repair_requested',
          fields: <String, Object?>{
            'trace': RemoteTransferDiagnostics.traceToken(
              buffer.resultRequestId,
            ),
            'missing': missing.length,
            'round': buffer.repairRounds,
          },
        );
      }
      debugPrint(
        'RemoteCommandRouter: requesting ${missing.length} missing chunk(s), '
        'repair round ${buffer.repairRounds}',
      );
      // Guarded: sendEncryptedCommand can THROW (profile scope changed
      // mid-transfer), and an unawaited raw future would surface that as an
      // uncaught zone error from a timer callback.
      unawaited(() async {
        try {
          await state.sendEncryptedCommand(
            session,
            RemoteCommand(
              action: RemoteAction.config,
              command: ConfigCommand.debrifyChannelNeed,
              data: chunkNeedBody(transferId: transferId, missing: missing),
            ),
          );
        } catch (error) {
          if (buffer.kind == ConfigCommand.profileGraph) {
            RemoteTransferDiagnostics.record(
              'receiver_chunk_repair_send_exception',
              fields: <String, Object?>{
                'trace': RemoteTransferDiagnostics.traceToken(
                  buffer.resultRequestId,
                ),
                'errorType': error.runtimeType,
              },
            );
          }
          debugPrint('RemoteCommandRouter: repair request send failed');
        }
      }());
      _armChunkTimeout(transferId, buffer);
    });
  }

  /// Handle a single chunk of a chunked channel transfer
  Future<void> _handleDebrifyChannelChunk(
    String jsonData,
    RemoteCommandContext context,
  ) async {
    _ChunkBuffer? failedBuffer;
    try {
      final data = jsonDecode(jsonData) as Map<String, dynamic>;
      final transferId = data['transferId'] as String;
      final index = data['index'] as int;
      final chunkData = data['data'] as String;

      final buffer = _chunkBuffers[transferId];
      if (buffer == null) {
        debugPrint('RemoteCommandRouter: chunk has no active buffer');
        return;
      }
      failedBuffer = buffer;

      if (_profilePeerKey(context) != buffer.peerKey ||
          context.encrypted != buffer.encrypted ||
          chunkData.length > kChunkDataMaxBytes + 256) {
        debugPrint('RemoteCommandRouter: chunk peer or size mismatch');
        return;
      }

      // A corrupt or hostile packet must not blow up the receiver.
      if (index < 0 || index >= buffer.totalChunks) {
        debugPrint('RemoteCommandRouter: chunk index is out of range');
        return;
      }

      // Only count if this slot was not already filled (guards against duplicate UDP packets)
      if (buffer.chunks[index] == null) {
        buffer.receivedCount++;
      }
      buffer.chunks[index] = chunkData;
      if (buffer.kind == ConfigCommand.profileGraph) {
        final percent = (buffer.receivedCount * 100) ~/ buffer.totalChunks;
        final bucket = percent >= 100
            ? 100
            : percent >= 75
            ? 75
            : percent >= 50
            ? 50
            : percent >= 25
            ? 25
            : 0;
        if (bucket > buffer.diagnosticProgressBucket) {
          buffer.diagnosticProgressBucket = bucket;
          RemoteTransferDiagnostics.record(
            'receiver_chunk_progress',
            fields: <String, Object?>{
              'trace': RemoteTransferDiagnostics.traceToken(
                buffer.resultRequestId,
              ),
              'percent': bucket,
              'received': buffer.receivedCount,
              'chunks': buffer.totalChunks,
            },
          );
        }
      }
      // Progress means the transfer is alive — push the stall deadline out.
      _armChunkTimeout(transferId, buffer);

      // Check if all chunks have arrived
      if (buffer.receivedCount >= buffer.totalChunks) {
        buffer.timeout?.cancel();
        _chunkBuffers.remove(transferId);

        // Decode into one bounded byte buffer and release the base64 chunk
        // strings before decrypting or expanding a potentially large graph.
        // Keeping both representations alive through the awaited restore used
        // to add several megabytes to the receiver's peak memory.
        final reassembled = _takeReassembledPayload(buffer);
        final full = reassembled.payload;

        if (buffer.kind == ConfigCommand.profileGraph) {
          RemoteTransferDiagnostics.record(
            'receiver_chunks_complete',
            fields: <String, Object?>{
              'trace': RemoteTransferDiagnostics.traceToken(
                buffer.resultRequestId,
              ),
              'chunks': buffer.totalChunks,
              'wireBytes': reassembled.bytes,
              'characters': full.length,
            },
          );
        }

        debugPrint(
          'RemoteCommandRouter: All chunks received for ${buffer.label}, '
          'reassembled ${full.length} chars',
        );

        if (buffer.encrypted) {
          await _completeEncryptedBlob(transferId, buffer, full);
          return;
        }

        // Replay through the normal switch, exactly as if the payload had
        // arrived in a single packet — from the same source it actually did.
        await _dispatchCommandAndWait(
          RemoteAction.config,
          buffer.kind,
          full,
          RemoteCommandContext(
            encrypted: false,
            authorized: false,
            sourceIp: buffer.sourceIp,
          ),
        );
      }
    } catch (error) {
      if (failedBuffer?.kind == ConfigCommand.profileGraph) {
        RemoteTransferDiagnostics.record(
          'receiver_chunk_exception',
          fields: <String, Object?>{
            'trace': RemoteTransferDiagnostics.traceToken(
              failedBuffer?.resultRequestId,
            ),
            'errorType': error.runtimeType,
            'received': failedBuffer?.receivedCount,
            'chunks': failedBuffer?.totalChunks,
          },
        );
      }
      debugPrint('RemoteCommandRouter: chunk handling failed');
      final buffer = failedBuffer;
      if (buffer != null) {
        buffer.timeout?.cancel();
        _chunkBuffers.removeWhere(
          (_, candidate) => identical(candidate, buffer),
        );
        await _reportChunkFailure(
          buffer,
          'The TV could not reassemble the transfer',
        );
      }
    }
  }

  ({String payload, int bytes}) _takeReassembledPayload(_ChunkBuffer buffer) {
    final bytes = BytesBuilder(copy: false);
    try {
      for (final chunk in buffer.chunks) {
        final decoded = base64.decode(chunk!);
        if (bytes.length > _maxProfileRemotePayloadBytes - decoded.length) {
          throw const FormatException('Reassembled transfer is too large');
        }
        bytes.add(decoded);
      }
      final allBytes = bytes.takeBytes();
      return (payload: utf8.decode(allBytes), bytes: allBytes.length);
    } finally {
      buffer.chunks.fillRange(0, buffer.chunks.length, null);
    }
  }

  /// Decrypt and replay a reassembled v2 blob transfer.
  Future<void> _completeEncryptedBlob(
    String transferId,
    _ChunkBuffer buffer,
    String ctB64,
  ) async {
    final graphDiagnostic = buffer.kind == ConfigCommand.profileGraph;
    final trace = RemoteTransferDiagnostics.traceToken(buffer.resultRequestId);
    final state = RemoteControlState();
    final manager = state.sessionManager;
    final sidB64 = buffer.sidB64;
    final n = buffer.blobN;
    if (manager == null || sidB64 == null || n == null) {
      if (graphDiagnostic) {
        RemoteTransferDiagnostics.record(
          'receiver_blob_session_fields_missing',
          fields: <String, Object?>{'trace': trace},
        );
      }
      debugPrint('RemoteCommandRouter: Encrypted blob missing session fields');
      await _reportChunkFailure(buffer, 'Transfer session data was incomplete');
      return;
    }
    final session = manager.sessionBySid(sidB64);
    if (session == null) {
      if (graphDiagnostic) {
        RemoteTransferDiagnostics.record(
          'receiver_blob_session_expired',
          fields: <String, Object?>{'trace': trace},
        );
      }
      // Receiver restarted mid-transfer: the session (and its keys) are gone.
      _showSnackBar(
        'Transfer failed: session expired — send again',
        isError: true,
      );
      await _reportChunkFailure(buffer, 'Transfer session expired on TV');
      return;
    }
    if (!session.authorized) {
      if (graphDiagnostic) {
        RemoteTransferDiagnostics.record(
          'receiver_blob_session_unauthorized',
          fields: <String, Object?>{'trace': trace},
        );
      }
      debugPrint('RemoteCommandRouter: Dropping blob on unauthorized session');
      await _reportChunkFailure(buffer, 'Transfer session was not authorized');
      return;
    }
    if (graphDiagnostic) {
      RemoteTransferDiagnostics.record(
        'receiver_blob_open_start',
        fields: <String, Object?>{
          'trace': trace,
          'wireCharacters': ctB64.length,
        },
      );
    }
    final plaintext = await RemoteSessionCrypto.openBlob(
      key: session.recvKey,
      sid: session.sid,
      n: n,
      transferId: transferId,
      kind: buffer.kind,
      ctB64: ctB64,
    );
    if (plaintext == null) {
      if (graphDiagnostic) {
        RemoteTransferDiagnostics.record(
          'receiver_blob_open_rejected',
          fields: <String, Object?>{'trace': trace},
        );
      }
      _showSnackBar(
        'Transfer failed: could not decrypt ${buffer.label}',
        isError: true,
      );
      await _reportChunkFailure(
        buffer,
        'The TV could not decrypt the transfer',
      );
      return;
    }
    if (graphDiagnostic) {
      RemoteTransferDiagnostics.record(
        'receiver_blob_open_complete',
        fields: <String, Object?>{
          'trace': trace,
          'characters': plaintext.length,
        },
      );
    }
    if (!session.acceptBlob(n)) {
      if (graphDiagnostic) {
        RemoteTransferDiagnostics.record(
          'receiver_blob_replay_rejected',
          fields: <String, Object?>{'trace': trace},
        );
      }
      debugPrint('RemoteCommandRouter: Replayed blob counter $n, dropping');
      return;
    }
    if (graphDiagnostic) {
      RemoteTransferDiagnostics.record(
        'receiver_graph_dispatch_start',
        fields: <String, Object?>{'trace': trace},
      );
    }
    await _dispatchCommandAndWait(
      RemoteAction.config,
      buffer.kind,
      plaintext,
      RemoteCommandContext(
        encrypted: true,
        authorized: true,
        remembered: buffer.remembered,
        sidB64: session.sidB64,
        peerFingerprint: session.peerFingerprint,
        peerName: session.peerName,
        sourceIp: buffer.sourceIp,
        reject: (code) async {
          await state.sendEncryptedCommand(
            session,
            RemoteCommand(
              action: RemoteAction.pair,
              command: PairCommand.err,
              data: code,
            ),
          );
        },
      ),
    );
    if (graphDiagnostic) {
      RemoteTransferDiagnostics.record(
        'receiver_graph_dispatch_complete',
        fields: <String, Object?>{'trace': trace},
      );
    }
  }

  Future<bool> _reportChunkFailure(_ChunkBuffer buffer, String message) {
    final requestId = buffer.resultRequestId;
    final sid = buffer.sidB64;
    if (requestId == null || sid == null) return Future<bool>.value(false);
    final state = RemoteControlState();
    final session = state.sessionManager?.sessionBySid(sid);
    if (session == null || !session.authorized) {
      return Future<bool>.value(false);
    }
    final context = RemoteCommandContext(
      encrypted: true,
      authorized: true,
      remembered: buffer.remembered,
      sidB64: session.sidB64,
      peerFingerprint: session.peerFingerprint,
      peerName: session.peerName,
      sourceIp: buffer.sourceIp,
    );
    if (buffer.kind == ConfigCommand.profileGraph) {
      return _reportProfileGraphResultBestEffort(
        context,
        requestId: requestId,
        ok: false,
        message: message,
      );
    }
    return _reportRemoteTransferResultBestEffort(
      context,
      requestId: requestId,
      ok: false,
      message: message,
    );
  }

  // ── pairing (receiver side) ──────────────────────────────────────────────

  /// Drive the pairing gate for pair-action traffic arriving over a session.
  Future<void> handlePairMessage(
    RemoteControlState state,
    RemoteSession session,
    String command,
    String? data,
  ) async {
    final gate = state.pairingGate;
    if (gate == null) return;

    Future<void> reply(String cmd, [String? replyData]) =>
        state.sendEncryptedCommand(
          session,
          RemoteCommand(
            action: RemoteAction.pair,
            command: cmd,
            data: replyData,
          ),
        );

    switch (command) {
      case PairCommand.request:
        switch (gate.request(session)) {
          case PairingRequestOutcome.autoAuthorized:
            unawaited(RemotePairingStore.touchPeer(session.peerFingerprint));
            notifyRememberedAutoAuth(session.peerName);
            await reply(PairCommand.ok, 'remembered');
          case PairingRequestOutcome.shown:
            await reply(PairCommand.challenge);
            _ensurePairingUi(gate);
          case PairingRequestOutcome.busy:
            await reply(PairCommand.err, 'busy');
        }
      case PairCommand.confirm:
        if (data == null) return;
        List<int> proof;
        try {
          proof = base64.decode(data);
        } catch (_) {
          await reply(PairCommand.err, 'bad_proof');
          return;
        }
        switch (await gate.confirmProof(session, proof)) {
          case PairProofOutcome.ok:
            // Written even when remembering is off, so flipping the flag
            // later works retroactively.
            unawaited(
              RemotePairingStore.rememberPeer(
                fingerprint: session.peerFingerprint,
                staticKey: session.peerStaticKey,
                name: session.peerName,
              ).then((_) => state.refreshRememberedPeers()),
            );
            _showSnackBar('Paired with "${session.peerName}"');
            await reply(PairCommand.ok);
          case PairProofOutcome.wrong:
            await reply(PairCommand.err, 'wrong');
          case PairProofOutcome.tooEarly:
            await reply(PairCommand.err, 'too_early');
          case PairProofOutcome.rateLimited:
            await reply(PairCommand.err, 'rate_limited');
          case PairProofOutcome.noRequest:
            await reply(PairCommand.err, 'no_request');
        }
      default:
        debugPrint('RemoteCommandRouter: Unknown pair command $command');
    }
  }

  /// When no pairing presenter is mounted (TV sitting on Home with its
  /// always-on listener), raise the fallback code dialog.
  void _ensurePairingUi(PairingGate gate) {
    if (gate.hasPresenter) return;
    final navigator = _navigatorKey?.currentState;
    if (navigator == null) {
      debugPrint('RemoteCommandRouter: No navigator for pairing dialog');
      return;
    }
    showRemotePairingDialog(navigator.context, gate);
  }

  /// Try to handle navigation commands via platform key injection (Android) or focus system (other platforms)
  void _tryFocusNavigation(String action, String command) {
    // On Android, use platform channel to inject real key events
    if (Platform.isAndroid) {
      _injectKeyEvent(action, command);
      return;
    }

    // Fallback for non-Android platforms: use focus system
    if (action != RemoteAction.navigate) return;

    final primaryFocus = FocusManager.instance.primaryFocus;

    switch (command) {
      case NavigateCommand.up:
        primaryFocus?.focusInDirection(TraversalDirection.up);
        break;
      case NavigateCommand.down:
        primaryFocus?.focusInDirection(TraversalDirection.down);
        break;
      case NavigateCommand.left:
        _focusLeft(primaryFocus);
        break;
      case NavigateCommand.right:
        primaryFocus?.focusInDirection(TraversalDirection.right);
        break;
      case NavigateCommand.select:
        _activateFocusedElement(primaryFocus);
        break;
      case NavigateCommand.back:
        _handleBack();
        break;
    }
  }

  /// LEFT is special on TV: the sidebar's focus nodes skip traversal, so a
  /// plain focusInDirection can never reach it. MainPageBridge exposes the
  /// same left-edge-aware move the DPAD Actions override uses; off-TV (or
  /// before main.dart wires it) it's null and we use plain traversal.
  void _focusLeft(FocusNode? primaryFocus) {
    final tvLeft = MainPageBridge.tvDirectionalLeft;
    if (tvLeft != null) {
      tvLeft();
    } else {
      primaryFocus?.focusInDirection(TraversalDirection.left);
    }
  }

  /// Inject a key event via platform channel (Android only)
  Future<void> _injectKeyEvent(String action, String command) async {
    final keyCode = _commandToAndroidKeyCode(action, command);
    if (keyCode == null) {
      debugPrint(
        'RemoteCommandRouter: No key code mapping for $action:$command',
      );
      return;
    }

    try {
      await _channel.invokeMethod('injectKeyEvent', {'keyCode': keyCode});
      debugPrint(
        'RemoteCommandRouter: Injected key event $keyCode for $action:$command',
      );
    } catch (_) {
      debugPrint('RemoteCommandRouter: key injection failed');
      // Fallback to focus-based navigation if platform channel fails
      _fallbackFocusNavigation(action, command);
    }
  }

  /// Map command to Android KeyEvent key code
  int? _commandToAndroidKeyCode(String action, String command) {
    if (action == RemoteAction.navigate) {
      switch (command) {
        case NavigateCommand.up:
          return AndroidKeyCode.dpadUp;
        case NavigateCommand.down:
          return AndroidKeyCode.dpadDown;
        case NavigateCommand.left:
          return AndroidKeyCode.dpadLeft;
        case NavigateCommand.right:
          return AndroidKeyCode.dpadRight;
        case NavigateCommand.select:
          return AndroidKeyCode.dpadCenter;
        case NavigateCommand.back:
          return AndroidKeyCode.back;
      }
    } else if (action == RemoteAction.media) {
      switch (command) {
        case MediaCommand.playPause:
          return AndroidKeyCode.mediaPlayPause;
        case MediaCommand.seekForward:
          return AndroidKeyCode.mediaFastForward;
        case MediaCommand.seekBackward:
          return AndroidKeyCode.mediaRewind;
      }
    }
    return null;
  }

  /// Fallback focus-based navigation for when platform channel fails
  void _fallbackFocusNavigation(String action, String command) {
    if (action != RemoteAction.navigate) return;

    final primaryFocus = FocusManager.instance.primaryFocus;

    switch (command) {
      case NavigateCommand.up:
        primaryFocus?.focusInDirection(TraversalDirection.up);
        break;
      case NavigateCommand.down:
        primaryFocus?.focusInDirection(TraversalDirection.down);
        break;
      case NavigateCommand.left:
        _focusLeft(primaryFocus);
        break;
      case NavigateCommand.right:
        primaryFocus?.focusInDirection(TraversalDirection.right);
        break;
      case NavigateCommand.select:
        _activateFocusedElement(primaryFocus);
        break;
      case NavigateCommand.back:
        _handleBack();
        break;
    }
  }

  /// Activate the currently focused element using Flutter's Actions system
  void _activateFocusedElement(FocusNode? focus) {
    final context = focus?.context;
    if (context == null) {
      debugPrint('RemoteCommandRouter: No focused element to activate');
      return;
    }

    debugPrint('RemoteCommandRouter: Activating focused element');

    // Try to invoke ActivateIntent - this works for buttons, list tiles, etc.
    final result = Actions.maybeInvoke<Intent>(context, const ActivateIntent());
    if (result != null) {
      debugPrint('RemoteCommandRouter: ActivateIntent handled');
      return;
    }

    // Fallback: Try ButtonActivateIntent for buttons specifically
    final buttonResult = Actions.maybeInvoke<Intent>(
      context,
      const ButtonActivateIntent(),
    );
    if (buttonResult != null) {
      debugPrint('RemoteCommandRouter: ButtonActivateIntent handled');
      return;
    }

    debugPrint(
      'RemoteCommandRouter: No activate handler found for focused element',
    );
  }

  /// Handle back navigation
  void _handleBack() {
    debugPrint('RemoteCommandRouter: Handling back');

    // Try using the navigator key if set
    if (_navigatorKey?.currentState != null) {
      if (_navigatorKey!.currentState!.canPop()) {
        _navigatorKey!.currentState!.pop();
        debugPrint('RemoteCommandRouter: Popped via navigator key');
        return;
      }
    }

    // Fallback: Simulate system back button press
    // This triggers the PopScope/WillPopScope handlers
    SystemNavigator.pop();
    debugPrint('RemoteCommandRouter: Called SystemNavigator.pop()');
  }

  /// Map command to LogicalKeyboardKey for reference
  LogicalKeyboardKey? commandToKey(String action, String command) {
    if (action == RemoteAction.navigate) {
      switch (command) {
        case NavigateCommand.up:
          return LogicalKeyboardKey.arrowUp;
        case NavigateCommand.down:
          return LogicalKeyboardKey.arrowDown;
        case NavigateCommand.left:
          return LogicalKeyboardKey.arrowLeft;
        case NavigateCommand.right:
          return LogicalKeyboardKey.arrowRight;
        case NavigateCommand.select:
          return LogicalKeyboardKey.select;
        case NavigateCommand.back:
          return LogicalKeyboardKey.goBack;
      }
    } else if (action == RemoteAction.media) {
      switch (command) {
        case MediaCommand.playPause:
          return LogicalKeyboardKey.mediaPlayPause;
        case MediaCommand.seekForward:
          return LogicalKeyboardKey.arrowRight;
        case MediaCommand.seekBackward:
          return LogicalKeyboardKey.arrowLeft;
      }
    }
    return null;
  }
}

class _ProfileCommandBinding {
  final ProfileScope scope;
  final int authorizationRevision;

  const _ProfileCommandBinding({
    required this.scope,
    required this.authorizationRevision,
  });

  @override
  bool operator ==(Object other) =>
      other is _ProfileCommandBinding &&
      other.scope == scope &&
      other.authorizationRevision == authorizationRevision;

  @override
  int get hashCode => Object.hash(scope, authorizationRevision);
}

/// Buffer for reassembling chunked channel transfers
class _ChunkBuffer {
  /// Human label for messages while the transfer is in flight.
  final String label;

  /// The config command the reassembled payload belongs to. Senders that
  /// predate the generalized envelope don't name one, so it defaults to the
  /// Debrify TV channel it was originally built for.
  final String kind;

  final int totalChunks;
  final List<String?> chunks;

  /// v2 sealed-blob transfers: the payload is AES-GCM ciphertext bound to
  /// session [sidB64] with counter [blobN]; decrypted after reassembly.
  final bool encrypted;
  final String? sidB64;
  final int? blobN;

  /// Datagram source of a PLAIN (v1) transfer's start packet, so the
  /// reassembled payload replays under the sender's consent identity.
  final String? sourceIp;
  final String peerKey;
  final bool remembered;
  final String? resultRequestId;

  /// Restarted on every chunk that arrives: the deadline is for a *stalled*
  /// transfer, not a slow one. A large payload is paced at 50ms per chunk, so
  /// a fixed deadline would kill transfers that were arriving perfectly.
  Timer? timeout;

  int receivedCount = 0;

  /// Last 25% milestone emitted to the retained transfer diagnostics sink.
  int diagnosticProgressBucket = 0;

  /// Gap-repair rounds already spent (v2 transfers only) — bounds the worst
  /// case on a dead link at roughly rounds × [kChunkRepairStall].
  int repairRounds = 0;

  _ChunkBuffer({
    required this.label,
    required this.kind,
    required this.totalChunks,
    required this.chunks,
    required this.timeout,
    this.encrypted = false,
    this.sidB64,
    this.blobN,
    this.sourceIp,
    required this.peerKey,
    this.remembered = false,
    this.resultRequestId,
  });
}

/// Per-source-IP drop tally behind the "update your phone app" notice.
class _StaleRemoteSource {
  _StaleRemoteSource(DateTime now)
    : burstStartedAt = now,
      lastDropAt = now,
      drops = 0;

  int drops;
  DateTime burstStartedAt;
  DateTime lastDropAt;
  DateTime? noticedAt;
}

/// A plaintext credential packet from a v1 sender, parked until the user
/// answers the consent dialog.
class _LegacyItem {
  final bool isAddon;
  final bool isComplete;
  final String command;
  final String data;

  const _LegacyItem.config(this.command, this.data)
    : isAddon = false,
      isComplete = false;
  const _LegacyItem.addon(this.command, this.data)
    : isAddon = true,
      isComplete = false;
  const _LegacyItem.complete()
    : isAddon = false,
      isComplete = true,
      command = ConfigCommand.complete,
      data = '';
}

/// Busy dialog for long-running remote imports: undismissable while work
/// runs, closed through its OWN context when `done` fires — the initiating
/// State may be anywhere, and an orphaned `canPop: false` modal on the root
/// navigator would wedge the app.
class _RouterBusyDialog extends StatefulWidget {
  const _RouterBusyDialog({required this.message, required this.done});

  final String message;
  final ValueNotifier<bool> done;

  @override
  State<_RouterBusyDialog> createState() => _RouterBusyDialogState();
}

class _RouterBusyDialogState extends State<_RouterBusyDialog> {
  @override
  void initState() {
    super.initState();
    widget.done.addListener(_maybeClose);
    if (widget.done.value) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeClose());
    }
  }

  @override
  void dispose() {
    widget.done.removeListener(_maybeClose);
    super.dispose();
  }

  void _maybeClose() {
    if (widget.done.value && mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(width: 16),
            Expanded(child: Text(widget.message)),
          ],
        ),
      ),
    );
  }
}
