import 'diagnostic_log.dart';

/// Orders native checkpoints, including completion, before playback cleanup.
/// Each launch owns its queue; old players cannot write into a newer session.
class NativePlaybackProgressSession {
  NativePlaybackProgressSession({
    required this.id,
    required this.persist,
    required this.isCurrent,
  });

  final int id;
  final Future<void> Function(Map<String, dynamic>) persist;
  final bool Function() isCurrent;
  Future<void> _tail = Future<void>.value();
  bool _accepting = true;

  Future<bool> enqueue(Map<String, dynamic> progress) {
    if (!_accepting || progress['sourcePersistenceSessionId'] != id) {
      return Future<bool>.value(false);
    }
    final snapshot = Map<String, dynamic>.from(progress);
    final operation = _tail.then((_) async {
      try {
        if (!isCurrent()) return false;
        await persist(snapshot);
        return true;
      } catch (error, stack) {
        DiagnosticLog.instance.recordError(
          source: 'android_tv_bridge',
          durable: true,
          event: 'progress_persist_failed',
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
