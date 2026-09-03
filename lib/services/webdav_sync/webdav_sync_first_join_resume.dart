import '../profiles/profile_preferences.dart';
import '../webdav_protocol_client.dart';
import 'webdav_sync_binding_store.dart';
import 'webdav_sync_diagnostics.dart';
import 'webdav_sync_models.dart';
import 'webdav_sync_operation_coordinator.dart';

typedef WebDavSyncFirstJoinConnect =
    Future<WebDavSyncBinding> Function(String bindingId);
typedef WebDavSyncFirstJoinDiagnostic =
    void Function(String message, Object? error);
typedef WebDavSyncFirstJoinPauseCheck = bool Function();

final class WebDavSyncFirstJoinAutoResumeExhausted implements Exception {
  const WebDavSyncFirstJoinAutoResumeExhausted();

  @override
  String toString() =>
      'WebDAV Sync could not finish its first sync automatically. Try again.';
}

enum WebDavSyncFirstJoinAutoResumeOutcome {
  skipped,
  waiting,
  activated,
  exhausted,
  failed,
}

/// Process-local policy for resuming a durable `awaitingAdoption` binding.
/// The shared operation coordinator is the authority for racing manual and
/// automatic attempts; the connector remains the authority for idempotently
/// resuming durable adoption state.
final class WebDavSyncFirstJoinAutoResume {
  WebDavSyncFirstJoinAutoResume({
    required WebDavSyncBindingStore bindingStore,
    required WebDavSyncOperationCoordinator operations,
    required WebDavSyncFirstJoinConnect connect,
    WebDavSyncFirstJoinPauseCheck? pauseCheck,
    DateTime Function()? clock,
    WebDavSyncFirstJoinDiagnostic? diagnostic,
  }) : _bindingStore = bindingStore,
       _operations = operations,
       _connect = connect,
       _pauseCheck = pauseCheck,
       _clock = clock ?? DateTime.now,
       _diagnostic = diagnostic ?? recordWebDavSyncDiagnostic;

  static const int attemptLimit = 5;
  // Match the active-cycle authentication posture in the runtime.
  static const int _authenticationFailureLimit = 3;
  static const Duration minimumSpacing = Duration(seconds: 30);
  static const String _attemptDiagnostic =
      'Automatic WebDAV first-sync completion attempt';

  final WebDavSyncBindingStore _bindingStore;
  final WebDavSyncOperationCoordinator _operations;
  final WebDavSyncFirstJoinConnect _connect;
  final WebDavSyncFirstJoinPauseCheck? _pauseCheck;
  final DateTime Function() _clock;
  final WebDavSyncFirstJoinDiagnostic _diagnostic;

  int _attempts = 0;
  DateTime? _lastAttemptAt;
  bool _terminalFailure = false;
  final Map<String, int> _authenticationFailures = <String, int>{};

  int get attemptCount => _attempts;
  bool get hasAttemptsRemaining =>
      !_terminalFailure && _attempts < attemptLimit;

  Future<WebDavSyncFirstJoinAutoResumeOutcome> resumeIfNeeded({
    required bool reconfigurationPaused,
  }) => _operations.run(() async {
    if (reconfigurationPaused ||
        (_pauseCheck?.call() ?? false) ||
        !hasAttemptsRemaining) {
      return WebDavSyncFirstJoinAutoResumeOutcome.skipped;
    }
    final snapshot = await _bindingStore.load();
    final binding = _awaitingBinding(snapshot);
    if (binding == null) {
      return WebDavSyncFirstJoinAutoResumeOutcome.skipped;
    }
    final now = _clock().toUtc();
    final lastAttemptAt = _lastAttemptAt;
    if (lastAttemptAt != null &&
        now.difference(lastAttemptAt) < minimumSpacing) {
      return WebDavSyncFirstJoinAutoResumeOutcome.skipped;
    }

    _attempts++;
    _lastAttemptAt = now;
    _diagnostic(_attemptDiagnostic, null);
    try {
      final result = await _connect(binding.id);
      if (result.lifecycle == WebDavSyncLifecycle.active) {
        _authenticationFailures.remove(binding.id);
        return WebDavSyncFirstJoinAutoResumeOutcome.activated;
      }
      if (result.lifecycle != WebDavSyncLifecycle.awaitingAdoption) {
        throw StateError('WebDAV first-sync completion left invalid state');
      }
      _authenticationFailures.remove(binding.id);
      return _waitOrExhaust(binding.id);
    } on ProfilePreferenceMutationConflict {
      _authenticationFailures.remove(binding.id);
      return _waitOrExhaust(binding.id);
    } on WebDavException catch (error) {
      if (_isTransient(error)) {
        _authenticationFailures.remove(binding.id);
        return _waitAfterRetryableFailure(binding.id);
      }
      if (error.kind == WebDavErrorKind.authentication &&
          !_authenticationFailureIsTerminal(binding.id)) {
        return _waitAfterRetryableFailure(binding.id);
      }
      _authenticationFailures.remove(binding.id);
      _terminalFailure = true;
      await _recordTerminalFailure(binding.id, error);
      return WebDavSyncFirstJoinAutoResumeOutcome.failed;
    } catch (error) {
      _authenticationFailures.remove(binding.id);
      _terminalFailure = true;
      await _recordTerminalFailure(binding.id, error);
      return WebDavSyncFirstJoinAutoResumeOutcome.failed;
    }
  });

  Future<void> _recordTerminalFailure(String bindingId, Object error) async {
    final current = (await _bindingStore.load()).bindings[bindingId];
    if (current?.lifecycle == WebDavSyncLifecycle.awaitingAdoption) {
      await _bindingStore.markAwaitingAdoptionError(bindingId, error);
    }
  }

  Future<WebDavSyncFirstJoinAutoResumeOutcome> _waitAfterRetryableFailure(
    String bindingId,
  ) async {
    final current = (await _bindingStore.load()).bindings[bindingId];
    if (current != null &&
        (current.lifecycle == WebDavSyncLifecycle.error ||
            current.lifecycle == WebDavSyncLifecycle.awaitingAdoption)) {
      await _bindingStore.setLifecycle(
        bindingId,
        WebDavSyncLifecycle.awaitingAdoption,
      );
    }
    return _waitOrExhaust(bindingId);
  }

  bool _authenticationFailureIsTerminal(String bindingId) {
    final failures = (_authenticationFailures[bindingId] ?? 0) + 1;
    _authenticationFailures[bindingId] = failures;
    return failures >= _authenticationFailureLimit;
  }

  static bool _isTransient(WebDavException error) =>
      error.kind == WebDavErrorKind.transient ||
      error.kind == WebDavErrorKind.timeout ||
      error.kind == WebDavErrorKind.network;

  Future<WebDavSyncFirstJoinAutoResumeOutcome> _waitOrExhaust(
    String bindingId,
  ) async {
    if (_attempts < attemptLimit) {
      return WebDavSyncFirstJoinAutoResumeOutcome.waiting;
    }
    _terminalFailure = true;
    await _bindingStore.markAwaitingAdoptionError(
      bindingId,
      const WebDavSyncFirstJoinAutoResumeExhausted(),
    );
    return WebDavSyncFirstJoinAutoResumeOutcome.exhausted;
  }

  static WebDavSyncBinding? _awaitingBinding(WebDavSyncStoreSnapshot snapshot) {
    final staged = snapshot.stagedBinding;
    if (staged?.lifecycle == WebDavSyncLifecycle.awaitingAdoption &&
        staged?.errorMessage == null) {
      return staged;
    }
    final active = snapshot.activeBinding;
    return active?.lifecycle == WebDavSyncLifecycle.awaitingAdoption &&
            active?.errorMessage == null
        ? active
        : null;
  }

  void reset() {
    _attempts = 0;
    _lastAttemptAt = null;
    _terminalFailure = false;
    _authenticationFailures.clear();
  }
}
