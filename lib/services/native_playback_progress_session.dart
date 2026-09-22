import 'diagnostic_log.dart';

/// Orders native checkpoints, including completion, before playback cleanup.
/// Each launch owns its queue; old players cannot write into a newer session.
class NativePlaybackProgressSession {
  NativePlaybackProgressSession({
    required this.id,
    required this.persist,
    required this.isCurrent,
    this.onSourceCommitted,
  });

  final int id;
  final Future<void> Function(Map<String, dynamic>) persist;
  final bool Function() isCurrent;
  final void Function(int sourceIndex)? onSourceCommitted;
  Future<void> _tail = Future<void>.value();
  bool _accepting = true;

  Future<bool> enqueue(Map<String, dynamic> progress) {
    if (!_accepting || progress['sourcePersistenceSessionId'] != id) {
      return Future<bool>.value(false);
    }
    final snapshot = Map<String, dynamic>.from(progress);
    return _enqueue(() => persist(snapshot), event: 'progress_persist_failed');
  }

  /// Source identity changes share the progress queue, not the independent
  /// pin-write queue. Reserve the boundary at callback receipt so an outgoing
  /// final checkpoint runs before it, and incoming progress runs after it.
  Future<bool> enqueueSourceCommit({
    required int sessionId,
    required int sourceIndex,
  }) {
    if (!_accepting || sessionId != id || sourceIndex < 0) {
      return Future<bool>.value(false);
    }
    return _enqueue(
      () async => onSourceCommitted?.call(sourceIndex),
      event: 'progress_source_commit_failed',
    );
  }

  Future<bool> _enqueue(
    Future<void> Function() callback, {
    required String event,
  }) {
    final operation = _tail.then((_) async {
      try {
        if (!isCurrent()) return false;
        await callback();
        return true;
      } catch (error, stack) {
        DiagnosticLog.instance.recordError(
          source: 'android_tv_bridge',
          durable: true,
          event: event,
          error: error,
          stackTrace: stack,
        );
        return false;
      }
    });
    _tail = operation.then((_) {});
    return operation;
  }

  Future<void> closeAndDrain() {
    _accepting = false;
    return _tail;
  }
}
