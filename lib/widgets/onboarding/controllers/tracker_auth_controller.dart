import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../services/analytics_service.dart';
import '../../../services/main_page_bridge.dart';
import '../../../services/simkl/simkl_service.dart';
import '../../../services/storage_service.dart';
import '../../../services/trakt/trakt_service.dart';

enum TrackerKind { trakt, simkl }

enum TrackerAuthPhase { idle, resolving, starting, code, connected, error }

/// Owns one tracker device-code flow, including cancellation and stale-result
/// protection. UI widgets only observe this controller.
class TrackerAuthController extends ChangeNotifier {
  TrackerAuthController(this.kind)
    : _authenticatedOverride = null,
      _usernameOverride = null,
      _requestOverride = null,
      _pollOverride = null,
      _connectedOverride = null;

  @visibleForTesting
  TrackerAuthController.forTesting(
    this.kind, {
    required Future<bool> Function() isAuthenticated,
    required Future<String?> Function() getUsername,
    required Future<Map<String, dynamic>?> Function() requestCode,
    required Future<String?> Function(String secret) poll,
    Future<void> Function()? onConnected,
  }) : _authenticatedOverride = isAuthenticated,
       _usernameOverride = getUsername,
       _requestOverride = requestCode,
       _pollOverride = poll,
       _connectedOverride = onConnected;

  final TrackerKind kind;
  final Future<bool> Function()? _authenticatedOverride;
  final Future<String?> Function()? _usernameOverride;
  final Future<Map<String, dynamic>?> Function()? _requestOverride;
  final Future<String?> Function(String secret)? _pollOverride;
  final Future<void> Function()? _connectedOverride;

  TrackerAuthPhase phase = TrackerAuthPhase.idle;
  String? username;
  String? userCode;
  String? verificationUrl;
  String? error;
  DateTime? expiresAt;

  String? _pollSecret;
  int _pollInterval = 5;
  int _attempt = 0;
  bool _polling = false;
  Timer? _pollTimer;
  Timer? _countdownTimer;
  bool _disposed = false;

  bool get connected => phase == TrackerAuthPhase.connected;

  String get label => kind == TrackerKind.trakt ? 'Trakt' : 'Simkl';

  String get countdown {
    final expiry = expiresAt;
    if (expiry == null) return '';
    final remaining = expiry.difference(DateTime.now());
    if (remaining.isNegative) return 'Expired';
    return '${remaining.inMinutes}m ${(remaining.inSeconds % 60).toString().padLeft(2, '0')}s';
  }

  Future<void> initialize() async {
    phase = TrackerAuthPhase.resolving;
    error = null;
    _notify();
    bool authenticated;
    String? name;
    try {
      authenticated = await _isAuthenticated();
      name = await _getUsername();
    } catch (_) {
      if (_disposed) return;
      phase = TrackerAuthPhase.error;
      error = 'Could not check $label. Please try again.';
      _notify();
      return;
    }
    if (_disposed) return;
    username = name;
    phase = authenticated ? TrackerAuthPhase.connected : TrackerAuthPhase.idle;
    _notify();
  }

  Future<bool> start() async {
    if (_disposed) return false;
    final attempt = ++_attempt;
    _stopTimers();
    phase = TrackerAuthPhase.starting;
    error = null;
    _notify();

    Map<String, dynamic>? result;
    try {
      result = await _requestCode();
    } catch (_) {
      result = null;
    }
    if (_disposed || attempt != _attempt) return false;
    if (result == null) {
      phase = TrackerAuthPhase.error;
      error = 'Could not get a $label code. Please try again.';
      _notify();
      return false;
    }

    final rawExpiry =
        result['expires_in'] as int? ?? (kind == TrackerKind.trakt ? 600 : 900);
    final rawInterval = result['interval'] as int? ?? 5;
    final expiry = rawExpiry > 0 ? rawExpiry : 900;
    _pollInterval = rawInterval > 0 ? rawInterval : 5;
    userCode = result['user_code'] as String?;
    verificationUrl = result['verification_url'] as String?;
    _pollSecret = kind == TrackerKind.trakt
        ? result['device_code'] as String?
        : userCode;
    expiresAt = DateTime.now().add(Duration(seconds: expiry));
    phase = TrackerAuthPhase.code;
    _notify();
    _startTimers();
    return true;
  }

  void cancel({String? message}) {
    _attempt++;
    _polling = false;
    _stopTimers();
    _clearCode();
    error = message;
    phase = message == null ? TrackerAuthPhase.idle : TrackerAuthPhase.error;
    _notify();
  }

  void _startTimers() {
    _pollTimer = Timer.periodic(
      Duration(seconds: _pollInterval),
      (_) => unawaited(_pollOnce()),
    );
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_disposed) return;
      if (expiresAt != null && DateTime.now().isAfter(expiresAt!)) {
        cancel(message: 'Code expired. Please try again.');
      } else {
        _notify();
      }
    });
  }

  Future<void> _pollOnce() async {
    final secret = _pollSecret;
    final attempt = _attempt;
    if (secret == null || _polling || phase != TrackerAuthPhase.code) return;
    _polling = true;
    String? result;
    try {
      result = await _poll(secret);
    } catch (_) {
      result = 'network_error';
    } finally {
      if (attempt == _attempt) _polling = false;
    }
    if (_disposed || attempt != _attempt || secret != _pollSecret) return;

    if (result == null) {
      _stopTimers();
      try {
        username = await _getUsername();
      } catch (_) {
        username = null;
      }
      if (_disposed || attempt != _attempt) return;
      try {
        await _markConnected();
      } catch (connectError) {
        debugPrint(
          'TrackerAuthController: $label connected but post-auth setup '
          'failed: $connectError',
        );
      }
      if (_disposed || attempt != _attempt) return;
      _clearCode();
      error = null;
      phase = TrackerAuthPhase.connected;
      _notify();
      return;
    }

    switch (result) {
      case 'authorization_pending':
      case 'network_error':
        return;
      case 'slow_down':
        _pollInterval += 5;
        _pollTimer?.cancel();
        _pollTimer = Timer.periodic(
          Duration(seconds: _pollInterval),
          (_) => unawaited(_pollOnce()),
        );
        return;
      case 'expired_token':
        cancel(message: 'Code expired. Please try again.');
        return;
      case 'access_denied':
        cancel(message: 'Authorization denied.');
        return;
      default:
        cancel(message: 'Authorization failed. Please try again.');
        return;
    }
  }

  Future<bool> _isAuthenticated() {
    final override = _authenticatedOverride;
    if (override != null) return override();
    return kind == TrackerKind.trakt
        ? TraktService.instance.isAuthenticated()
        : SimklService.instance.isAuthenticated();
  }

  Future<String?> _getUsername() {
    final override = _usernameOverride;
    if (override != null) return override();
    return kind == TrackerKind.trakt
        ? TraktService.instance.getUsername()
        : SimklService.instance.getUsername();
  }

  Future<Map<String, dynamic>?> _requestCode() {
    final override = _requestOverride;
    if (override != null) return override();
    return kind == TrackerKind.trakt
        ? TraktService.instance.requestDeviceCode()
        : SimklService.instance.requestPin();
  }

  Future<String?> _poll(String secret) {
    final override = _pollOverride;
    if (override != null) return override(secret);
    return kind == TrackerKind.trakt
        ? TraktService.instance.pollDeviceToken(secret)
        : SimklService.instance.pollPin(secret);
  }

  Future<void> _markConnected() async {
    final override = _connectedOverride;
    if (override != null) {
      await override();
      return;
    }
    if (kind == TrackerKind.trakt) {
      await StorageService.setTraktSyncCatalogItems(true);
    } else {
      await StorageService.setSimklSyncCatalogItems(true);
    }
    AnalyticsService.integrationConnected(kind.name, {
      'surface': 'onboarding',
      'method': kind == TrackerKind.trakt ? 'device_code' : 'pin',
    });
    MainPageBridge.notifyIntegrationChanged();
  }

  void _clearCode() {
    userCode = null;
    verificationUrl = null;
    expiresAt = null;
    _pollSecret = null;
  }

  void _stopTimers() {
    _pollTimer?.cancel();
    _countdownTimer?.cancel();
    _pollTimer = null;
    _countdownTimer = null;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _attempt++;
    _stopTimers();
    super.dispose();
  }
}
