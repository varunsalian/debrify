import 'dart:async';

import 'package:debrify/services/ledger/ledger_auth_api.dart';
import 'package:debrify/services/ledger/ledger_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/profiles/profile_runtime.dart';

/// The device sign-in operations the page needs. [LedgerSignInGateway.live]
/// is the production adapter over [LedgerService]; tests override
/// [ledgerSignInGatewayProvider].
abstract interface class LedgerSignInGateway {
  Future<LedgerDeviceCode?> start();
  Future<LedgerPollStatus> poll(String deviceCode);
  void cancel(String deviceCode);

  /// Runs after approval: stores the display name. Best effort.
  Future<void> afterSignIn();

  factory LedgerSignInGateway.live(LedgerService service) =
      _LiveLedgerSignInGateway;
}

class _LiveLedgerSignInGateway implements LedgerSignInGateway {
  _LiveLedgerSignInGateway(this._service);
  final LedgerService _service;

  @override
  Future<LedgerDeviceCode?> start() => _service.session.startSignIn();

  @override
  Future<LedgerPollStatus> poll(String deviceCode) =>
      _service.session.pollSignIn(deviceCode);

  @override
  void cancel(String deviceCode) => _service.session.cancelSignIn(deviceCode);

  @override
  Future<void> afterSignIn() => _service.session.refreshUsername(_service.api);
}

final ledgerSignInGatewayProvider = Provider<LedgerSignInGateway>(
  (ref) => LedgerSignInGateway.live(LedgerService.instance),
);

final ledgerSignInClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

final ledgerSignInDelayProvider = Provider<Future<void> Function(Duration)>(
  (ref) => Future<void>.delayed,
);

/// The active profile session; a change abandons the sign-in.
final ledgerSignInScopeProvider = Provider<Object? Function()>(
  (ref) =>
      () => ProfileRuntime.isInitialized ? ProfileRuntime.scope.value : null,
);

sealed class LedgerSignInState {
  const LedgerSignInState();
}

class LedgerSignInIdle extends LedgerSignInState {
  const LedgerSignInIdle();
}

class LedgerSignInBusy extends LedgerSignInState {
  const LedgerSignInBusy();
}

class LedgerSignInWaiting extends LedgerSignInState {
  const LedgerSignInWaiting({
    required this.userCode,
    required this.verificationUri,
    required this.verificationUriComplete,
    required this.expiresAt,
  });

  final String userCode;
  final String verificationUri;
  final String verificationUriComplete;
  final DateTime expiresAt;
}

class LedgerSignInExpired extends LedgerSignInState {
  const LedgerSignInExpired();
}

class LedgerSignInDone extends LedgerSignInState {
  const LedgerSignInDone();
}

class LedgerSignInFailed extends LedgerSignInState {
  const LedgerSignInFailed(this.message);
  final String message;
}

final ledgerSignInControllerProvider =
    NotifierProvider.autoDispose<LedgerSignInController, LedgerSignInState>(
      LedgerSignInController.new,
      retry: (count, error) => null,
    );

/// One device sign-in for the settings page. Every await is followed by a
/// request-generation and profile-scope check, so a cancelled, replaced or
/// out-of-profile poll can neither publish state nor keep polling. (The
/// session itself also commits only into the profile that started it.)
class LedgerSignInController extends Notifier<LedgerSignInState> {
  late LedgerSignInGateway _gateway;
  late DateTime Function() _clock;
  late Future<void> Function(Duration) _delay;
  late Object? Function() _scope;
  int _generation = 0;
  Object? _startScope;
  String? _deviceCode;

  static const _profileChangedMessage =
      'The active profile changed. Sign in again from this profile.';

  @override
  LedgerSignInState build() {
    _gateway = ref.watch(ledgerSignInGatewayProvider);
    _clock = ref.watch(ledgerSignInClockProvider);
    _delay = ref.watch(ledgerSignInDelayProvider);
    _scope = ref.watch(ledgerSignInScopeProvider);
    ref.onDispose(() {
      _generation++;
      _cancelCode();
    });
    return const LedgerSignInIdle();
  }

  bool _current(int generation) =>
      ref.mounted && generation == _generation && _scope() == _startScope;

  void _cancelCode() {
    final code = _deviceCode;
    _deviceCode = null;
    if (code != null) _gateway.cancel(code);
  }

  /// Starts (or restarts) sign-in from an explicit user action.
  Future<void> start() async {
    final generation = ++_generation;
    _cancelCode();
    _startScope = _scope();
    state = const LedgerSignInBusy();
    final LedgerDeviceCode? code;
    try {
      code = await _gateway.start();
    } catch (_) {
      if (_current(generation)) state = const LedgerSignInFailed(_startError);
      return;
    }
    if (!_current(generation)) {
      if (code != null) _gateway.cancel(code.deviceCode);
      return;
    }
    if (code == null) {
      state = const LedgerSignInFailed(_startError);
      return;
    }
    _deviceCode = code.deviceCode;
    final expiresAt = _clock().add(code.expiresIn);
    state = LedgerSignInWaiting(
      userCode: code.userCode,
      verificationUri: code.verificationUri,
      verificationUriComplete: code.verificationUriComplete,
      expiresAt: expiresAt,
    );
    unawaited(_poll(generation, code, expiresAt));
  }

  static const _startError =
      "Couldn't get a sign-in code. Check your connection and try again.";

  void cancel() {
    _generation++;
    _cancelCode();
    state = const LedgerSignInIdle();
  }

  Future<void> _poll(
    int generation,
    LedgerDeviceCode code,
    DateTime expiresAt,
  ) async {
    var interval = code.interval;
    while (_current(generation)) {
      await _delay(interval);
      if (!_current(generation)) break;
      if (!_clock().isBefore(expiresAt)) {
        _cancelCode();
        state = const LedgerSignInExpired();
        return;
      }
      final LedgerPollStatus status;
      try {
        status = await _gateway.poll(code.deviceCode);
      } catch (_) {
        continue;
      }
      if (!_current(generation)) break;
      switch (status) {
        case LedgerPollStatus.pending:
        case LedgerPollStatus.networkError:
          continue;
        case LedgerPollStatus.slowDown:
          // RFC 8628: add five seconds to the interval.
          interval += const Duration(seconds: 5);
          continue;
        case LedgerPollStatus.approved:
          _deviceCode = null;
          await _gateway.afterSignIn();
          if (ref.mounted && generation == _generation) {
            state = const LedgerSignInDone();
          }
          return;
        case LedgerPollStatus.expired:
          _deviceCode = null;
          state = const LedgerSignInExpired();
          return;
        case LedgerPollStatus.denied:
          _deviceCode = null;
          state = LedgerSignInFailed(
            _scope() != _startScope
                ? _profileChangedMessage
                : 'Sign-in was declined.',
          );
          return;
        case LedgerPollStatus.error:
          _cancelCode();
          state = const LedgerSignInFailed(
            'Sign-in failed. Try again in a moment.',
          );
          return;
      }
    }
    // Left the loop because the profile changed under this attempt.
    if (ref.mounted && generation == _generation && _scope() != _startScope) {
      _generation++;
      _cancelCode();
      state = const LedgerSignInFailed(_profileChangedMessage);
    }
  }
}
