import 'dart:async';

import 'package:flutter/foundation.dart';

import '../profiles/profile_async_authorization.dart';
import 'mdblist_models.dart';
import 'mdblist_service.dart';

typedef MdblistScrobbleSender =
    Future<MdblistResult<Map<String, dynamic>>> Function(
      String action,
      MdblistScrobbleTarget target,
      double progress,
    );

/// MDBList-only pause-centric playback state machine. Existing Trakt and Simkl
/// state/timers deliberately do not pass through this class.
class MdblistScrobbleSession {
  static const completionPercent = 80.0;
  static const defaultCheckpointInterval = Duration(minutes: 2);

  final MdblistScrobbleSender sender;
  final Duration checkpointInterval;
  final bool Function() budgetAvailable;
  MdblistScrobbleTarget target;

  Timer? _timer;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Future<void> _tail = Future.value();
  bool _playing = false;
  bool _closed = false;
  bool _checkpointingStopped = false;
  bool _stopQueuedForIdentity = false;
  bool _stoppedForIdentity = false;
  double? _lastQueuedProgress;
  String? _lastQueuedAction;

  MdblistScrobbleSession({
    required this.target,
    required this.sender,
    required this.budgetAvailable,
    this.checkpointInterval = defaultCheckpointInterval,
  });

  factory MdblistScrobbleSession.forService({
    required MdblistService service,
    required MdblistScrobbleTarget target,
    required ProfileAsyncAuthorization? capability,
    Duration checkpointInterval = defaultCheckpointInterval,
    int quotaFloor = 25,
  }) {
    var sessionCheckpoints = 0;
    return MdblistScrobbleSession(
      target: target,
      checkpointInterval: checkpointInterval,
      budgetAvailable: () {
        final account = service.currentAccount;
        if (account == null || account.apiRequests <= 0) return true;
        final remaining =
            account.apiRequests - account.apiRequestsUsed - sessionCheckpoints;
        if (remaining <= quotaFloor) return false;
        sessionCheckpoints++;
        return true;
      },
      sender: (action, currentTarget, progress) => switch (action) {
        'pause' => service.scrobblePause(
          currentTarget,
          progress,
          capability: capability,
        ),
        'stop' => service.scrobbleStop(
          currentTarget,
          progress,
          capability: capability,
        ),
        _ => Future.value(
          const MdblistResult.failure(MdblistResultKind.malformedResponse),
        ),
      },
    );
  }

  double get progress {
    if (_duration <= Duration.zero) return 0;
    return (_position.inMilliseconds / _duration.inMilliseconds * 100).clamp(
      0,
      100,
    );
  }

  void updatePosition(Duration position, Duration duration) {
    _position = position;
    _duration = duration;
  }

  void play() {
    if (_closed || _playing) return;
    debugPrint(
      '[MDBListDiag] session play imdb=${target.ids.imdb} '
      'progress=${progress.toStringAsFixed(3)}',
    );
    _playing = true;
    _stoppedForIdentity = false;
    _checkpoint();
    _timer?.cancel();
    _timer = Timer.periodic(checkpointInterval, (_) => _checkpoint());
  }

  void pause() {
    if (_closed) return;
    debugPrint(
      '[MDBListDiag] session pause imdb=${target.ids.imdb} '
      'progress=${progress.toStringAsFixed(3)}',
    );
    _playing = false;
    _timer?.cancel();
    _timer = null;
    _checkpoint(force: true);
  }

  void seek(Duration targetPosition, Duration duration) {
    final previous = progress;
    updatePosition(targetPosition, duration);
    final current = progress;
    if (previous < completionPercent && current >= completionPercent) {
      _stop();
    } else if (previous >= completionPercent && current < completionPercent) {
      _stoppedForIdentity = false;
      _checkpoint(force: true);
    }
  }

  Future<void> switchTarget(
    MdblistScrobbleTarget next, {
    Duration position = Duration.zero,
    Duration duration = Duration.zero,
  }) async {
    final wasPlaying = _playing;
    _finish();
    await flush();
    await _retryFailedCompletion();
    target = next;
    _position = position;
    _duration = duration;
    _stoppedForIdentity = false;
    _stopQueuedForIdentity = false;
    _lastQueuedAction = null;
    _lastQueuedProgress = null;
    _playing = wasPlaying;
    if (wasPlaying) {
      _checkpoint(force: true);
      _timer?.cancel();
      _timer = Timer.periodic(checkpointInterval, (_) => _checkpoint());
    }
  }

  void complete() {
    if (_duration > Duration.zero) _position = _duration;
    _stop();
  }

  void exit() {
    debugPrint(
      '[MDBListDiag] session exit imdb=${target.ids.imdb} '
      'progress=${progress.toStringAsFixed(3)}',
    );
    _finish();
  }

  Future<void> close() async {
    if (_closed) return;
    debugPrint(
      '[MDBListDiag] session close imdb=${target.ids.imdb} '
      'progress=${progress.toStringAsFixed(3)}',
    );
    _finish();
    await flush();
    await _retryFailedCompletion();
    _closed = true;
    _playing = false;
    _timer?.cancel();
    _timer = null;
  }

  /// A threshold-crossing stop can still be in flight when Next is pressed.
  /// If that request fails, retry once while the outgoing target is intact;
  /// after [switchTarget] replaces it there is no safe way to reconstruct the
  /// episode identity. Successful stops remain exactly-once.
  Future<void> _retryFailedCompletion() async {
    if (_closed || progress < completionPercent || _stoppedForIdentity) return;
    _stop();
    await flush();
  }

  void _checkpoint({bool force = false}) {
    if (_closed || _checkpointingStopped || !target.isValid) return;
    final rawValue = progress;
    if (rawValue >= completionPercent) return;
    final value = rawValue <= 0 ? 1.0 : rawValue;
    final rounded = double.parse(value.toStringAsFixed(2));
    if (_lastQueuedAction == 'pause' && _lastQueuedProgress == rounded) return;
    if (!budgetAvailable()) {
      _checkpointingStopped = true;
      _timer?.cancel();
      _timer = null;
      return;
    }
    _enqueue('pause', value, force: force);
  }

  void _stop() {
    if (_closed ||
        _stoppedForIdentity ||
        _stopQueuedForIdentity ||
        !target.isValid) {
      return;
    }
    _timer?.cancel();
    _timer = null;
    _playing = false;
    _stopQueuedForIdentity = true;
    _enqueue('stop', progress, force: true);
  }

  /// Finish the current playback identity without accidentally completing it.
  /// MDBList requires a pause before a sub-threshold title exists in
  /// `/sync/playback`; sending stop as the first action is rejected with 400.
  /// A real completion still uses stop, while an early exit persists the
  /// current position with pause.
  void _finish() {
    if (_closed || _stoppedForIdentity || !target.isValid) return;
    _timer?.cancel();
    _timer = null;
    _playing = false;
    if (progress >= completionPercent) {
      _stop();
      return;
    }
    _checkpoint(force: true);
    _stoppedForIdentity = true;
  }

  void _enqueue(String action, double value, {required bool force}) {
    final rounded = double.parse(value.toStringAsFixed(2));
    if (!force &&
        _lastQueuedAction == action &&
        _lastQueuedProgress == rounded) {
      return;
    }
    _lastQueuedAction = action;
    _lastQueuedProgress = rounded;
    final queuedTarget = target;
    debugPrint(
      '[MDBListDiag] scrobble queued action=$action '
      'imdb=${queuedTarget.ids.imdb} ${_targetLabel(queuedTarget)} '
      'progress=${rounded.toStringAsFixed(2)} force=$force',
    );
    _tail = _tail.then((_) async {
      if (_checkpointingStopped && action == 'pause') return;
      final result = await sender(action, queuedTarget, rounded);
      if (action == 'stop') {
        _stopQueuedForIdentity = false;
        _stoppedForIdentity = result.isSuccess;
      } else if (action == 'pause' && result.isSuccess) {
        // A seek back below the completion threshold queues pause after stop.
        // Its accepted checkpoint makes the identity resumable again.
        _stoppedForIdentity = false;
      }
      debugPrint(
        '[MDBListDiag] scrobble result action=$action '
        'imdb=${queuedTarget.ids.imdb} ${_targetLabel(queuedTarget)} '
        'progress=$rounded '
        'kind=${result.kind.name} status=${result.statusCode}',
      );
      if (result.kind == MdblistResultKind.rateLimited ||
          result.kind == MdblistResultKind.denied ||
          result.kind == MdblistResultKind.unauthenticated) {
        _checkpointingStopped = true;
        _timer?.cancel();
        _timer = null;
      }
    });
  }

  Future<void> flush() => _tail;

  static String _targetLabel(MdblistScrobbleTarget value) => value.isEpisode
      ? 'season=${value.season} episode=${value.episode}'
      : 'type=movie';
}
